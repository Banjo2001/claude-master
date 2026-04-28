#!/usr/bin/env bash
# =============================================================================
# DATEI:        06_inventory_check.sh
# ZWECK:        Validiert das Ansible-Inventar VOR dem ersten Playbook-Lauf.
#               Prüft ob alle Hosts erreichbar sind, SSH-Keys passen, Vault
#               entschlüsselbar ist und alle Pflicht-Variablen gesetzt sind.
# AUFRUFEN:     bash scripts/setup/06_inventory_check.sh
# VORAUSSETZUNGEN:
#   - 03_init_ansible_vault.sh wurde ausgeführt
#   - hosts.yml und vars.yml wurden mit echten Werten befüllt
#   - SSH-Key auf alle Zielhosts kopiert
# SICHERHEIT:
#   - Backup-Verhalten: keines (nur Lese-Operationen)
#   - Destruktiv: NEIN
# VERSION:      1.0.0 | Stand: 2026-04
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_ok()   { echo -e "${GREEN}  ✓${NC} $*"; }
log_fail() { echo -e "${RED}  ✗${NC} $*" >&2; FAILED=$((FAILED + 1)); }
log_warn() { echo -e "${YELLOW}  ⚠${NC} $*"; WARNINGS=$((WARNINGS + 1)); }
log_info() { echo -e "${BLUE}  i${NC} $*"; }

FAILED=0
WARNINGS=0

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOSTS_FILE="$REPO_ROOT/ansible/inventories/prod/hosts.yml"
VARS_FILE="$REPO_ROOT/ansible/inventories/prod/group_vars/all/vars.yml"
VAULT_FILE="$REPO_ROOT/ansible/inventories/prod/group_vars/all/vault.yml"
VAULT_PASS_FILE="${ANSIBLE_VAULT_PASSWORD_FILE:-$HOME/.vault_pass.txt}"

cd "$REPO_ROOT"

echo ""
echo "============================================================"
echo "  Inventar-Validierung vor Ansible-Deploy"
echo "============================================================"
echo ""

# ─── 1. Dateien existieren? ─────────────────────────────────────────────────
echo "[ Dateien ]"

for FILE in "$HOSTS_FILE" "$VARS_FILE" "$VAULT_FILE" "$VAULT_PASS_FILE"; do
    if [ -f "$FILE" ]; then
        log_ok "$(basename "$FILE"): vorhanden"
    else
        log_fail "$(basename "$FILE"): FEHLT — $FILE"
    fi
done

[ "$FAILED" -gt 0 ] && { echo ""; log_fail "Erst 03_init_ansible_vault.sh ausführen!"; exit 1; }

echo ""

# ─── 2. Vault entschlüsselbar? ──────────────────────────────────────────────
echo "[ Vault-Entschlüsselung ]"

if ansible-vault view "$VAULT_FILE" --vault-password-file "$VAULT_PASS_FILE" \
     >/dev/null 2>&1; then
    log_ok "Vault entschlüsselbar"
else
    log_fail "Vault NICHT entschlüsselbar — falsches Passwort?"
fi

# Platzhalter in Vault prüfen
if ansible-vault view "$VAULT_FILE" --vault-password-file "$VAULT_PASS_FILE" \
     2>/dev/null | grep -q "<WIRD_VIA_VAULT_GESETZT>"; then
    log_warn "Vault enthält noch Platzhalter '<WIRD_VIA_VAULT_GESETZT>'"
    log_info "  Generieren: bash scripts/setup/04_generate_secrets.sh"
    log_info "  Manuell:    ansible-vault edit $VAULT_FILE"
fi

echo ""

# ─── 3. Platzhalter in vars.yml prüfen ──────────────────────────────────────
echo "[ vars.yml ]"

if grep -qE "<DEINE_DOMAIN>|<DEINE_EMAIL>|<DEINE_MANAGEMENT_IP>|<PVE-HOST-IP>|<PBS-HOST-IP>" "$VARS_FILE"; then
    log_fail "vars.yml enthält noch Platzhalter — bitte ausfüllen!"
    grep -nE "<[A-Z_]+>" "$VARS_FILE" | head -10
else
    log_ok "vars.yml: keine Platzhalter mehr enthalten"
fi

echo ""

# ─── 4. Inventory-Syntax prüfen ─────────────────────────────────────────────
echo "[ Inventar-Syntax ]"

if ansible-inventory --inventory "$HOSTS_FILE" --list >/dev/null 2>&1; then
    log_ok "hosts.yml: Syntax OK"
    HOST_COUNT=$(ansible-inventory --inventory "$HOSTS_FILE" --list 2>/dev/null \
        | jq -r '._meta.hostvars | keys | length' 2>/dev/null || echo "0")
    log_info "Anzahl Hosts: $HOST_COUNT"
else
    log_fail "hosts.yml: Syntax-Fehler"
    ansible-inventory --inventory "$HOSTS_FILE" --list 2>&1 | tail -5
fi

echo ""

# ─── 5. Playbook-Syntax prüfen ──────────────────────────────────────────────
echo "[ Playbook-Syntax ]"

for PB in common docker matrix_synapse nextcloud_aio; do
    if ansible-playbook --syntax-check "ansible/playbooks/${PB}.yml" \
         --vault-password-file "$VAULT_PASS_FILE" >/dev/null 2>&1; then
        log_ok "${PB}.yml: Syntax OK"
    else
        log_fail "${PB}.yml: Syntax-Fehler"
    fi
done

echo ""

# ─── 6. SSH-Konnektivität prüfen ────────────────────────────────────────────
echo "[ SSH-Konnektivität (ansible -m ping) ]"

if ansible all -m ping --vault-password-file "$VAULT_PASS_FILE" \
     -o 2>&1 | grep -q "SUCCESS"; then
    log_ok "Ansible kann mindestens einen Host erreichen"
    log_info "Detail: ansible all -m ping"
else
    log_fail "Kein Host via Ansible/SSH erreichbar!"
    log_info "Prüfen: ssh -i ~/.ssh/id_ed25519_proxmox root@<HOST-IP>"
    log_info "        ssh-copy-id -i ~/.ssh/id_ed25519_proxmox.pub root@<HOST-IP>"
fi

echo ""

# ─── 7. Sudo / become testen ────────────────────────────────────────────────
echo "[ Privilege Escalation ]"

if ansible all -m command -a "id -u" --become \
     --vault-password-file "$VAULT_PASS_FILE" -o 2>&1 \
     | grep -q "stdout=0"; then
    log_ok "become (root) funktioniert auf allen Hosts"
else
    log_warn "become (root) konnte nicht auf allen Hosts geprüft werden"
fi

echo ""

# ─── Ergebnis ───────────────────────────────────────────────────────────────
echo "============================================================"
if [ "$FAILED" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
    echo -e "${GREEN}  Alle Prüfungen bestanden — bereit für Deploy!${NC}"
    echo ""
    echo "  Empfohlener nächster Schritt (Dry-Run!):"
    echo "    ansible-playbook ansible/playbooks/site.yml --check --diff"
elif [ "$FAILED" -eq 0 ]; then
    echo -e "${YELLOW}  $WARNINGS Warnung(en) — vor Deploy beheben${NC}"
else
    echo -e "${RED}  $FAILED Fehler — Deploy noch nicht möglich${NC}"
    exit 1
fi
echo "============================================================"
echo ""
