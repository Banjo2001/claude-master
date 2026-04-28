#!/usr/bin/env bash
# =============================================================================
# DATEI:        04_generate_secrets.sh
# ZWECK:        Generiert kryptografisch starke Secrets für vault.yml und
#               schreibt sie verschlüsselt in die Vault. Vermeidet manuelles
#               Hantieren mit openssl rand und Copy-Paste-Fehler.
# AUFRUFEN:     bash scripts/setup/04_generate_secrets.sh
# VORAUSSETZUNGEN:
#   - 03_init_ansible_vault.sh wurde erfolgreich ausgeführt
#   - ~/.vault_pass.txt existiert
#   - openssl, ansible-vault verfügbar
# SICHERHEIT:
#   - Backup-Verhalten: bestehende vault.yml wird NICHT überschrieben
#                       (nur leere Felder werden befüllt)
#   - Destruktiv: NEIN
#   - Rollback: ansible-vault edit vault.yml und manuell zurücksetzen
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
log_fail() { echo -e "${RED}  ✗${NC} $*" >&2; }
log_warn() { echo -e "${YELLOW}  ⚠${NC} $*"; }
log_info() { echo -e "${BLUE}  i${NC} $*"; }

echo ""
echo "============================================================"
echo "  Secret-Generator für Ansible Vault"
echo "  Erzeugt starke Zufalls-Secrets via openssl rand -hex 32"
echo "============================================================"
echo ""

# ─── Voraussetzungen prüfen ─────────────────────────────────────────────────
echo "[ Voraussetzungen ]"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VAULT_FILE="$REPO_ROOT/ansible/inventories/prod/group_vars/all/vault.yml"
VAULT_PASS_FILE="${ANSIBLE_VAULT_PASSWORD_FILE:-$HOME/.vault_pass.txt}"

if ! command -v openssl &>/dev/null; then
    log_fail "openssl ist nicht installiert!"
    exit 1
fi
log_ok "openssl: $(openssl version)"

if ! command -v ansible-vault &>/dev/null; then
    log_fail "ansible-vault ist nicht installiert!"
    exit 1
fi
log_ok "ansible-vault: verfügbar"

if [ ! -f "$VAULT_PASS_FILE" ]; then
    log_fail "Vault-Passwort-Datei nicht gefunden: $VAULT_PASS_FILE"
    log_info "Erst initialisieren: bash scripts/setup/03_init_ansible_vault.sh"
    exit 1
fi
log_ok "Vault-Passwort: $VAULT_PASS_FILE"

if [ ! -f "$VAULT_FILE" ]; then
    log_fail "vault.yml nicht gefunden: $VAULT_FILE"
    log_info "Erst initialisieren: bash scripts/setup/03_init_ansible_vault.sh"
    exit 1
fi
log_ok "vault.yml: $VAULT_FILE"

echo ""

# ─── Secrets generieren ─────────────────────────────────────────────────────
# WARUM hex 32: 32 Bytes = 256 Bit Entropie. Hex-kodiert = 64 ASCII-Zeichen,
# YAML-sicher (keine Quotes/Backslashes/Sonderzeichen).
echo "[ Secret-Erzeugung ]"

generate_hex() { openssl rand -hex 32; }
generate_pass() {
    # Stark, aber printable + URL-safe (für DB-Passwörter)
    openssl rand -base64 33 | tr -d '+/=' | head -c 32
}

MATRIX_REG_SECRET=$(generate_hex)
MATRIX_MACAROON=$(generate_hex)
MATRIX_DB_PASS=$(generate_pass)
COTURN_SECRET=$(generate_hex)
NEXTCLOUD_DB=$(generate_pass)
NEXTCLOUD_DB_ROOT=$(generate_pass)
NEXTCLOUD_ADMIN=$(generate_pass)

log_ok "Matrix Registration Shared Secret (hex 64): generiert"
log_ok "Matrix Macaroon Secret Key (hex 64): generiert"
log_ok "Matrix DB-Passwort (32 Zeichen): generiert"
log_ok "Coturn Auth Secret (hex 64): generiert"
log_ok "Nextcloud DB-Passwort: generiert"
log_ok "Nextcloud DB-Root-Passwort: generiert"
log_ok "Nextcloud Admin-Passwort: generiert"

echo ""

# ─── Bestätigung einholen ───────────────────────────────────────────────────
echo "[ Vault aktualisieren ]"
log_warn "Die folgenden Schlüssel werden in vault.yml mit neuen Werten ersetzt:"
echo "    - vault_matrix_registration_shared_secret"
echo "    - vault_matrix_macaroon_secret_key"
echo "    - vault_matrix_db_password"
echo "    - vault_coturn_auth_secret"
echo "    - vault_nextcloud_db_password"
echo "    - vault_nextcloud_db_root_password"
echo "    - vault_nextcloud_admin_password"
echo ""
log_warn "ACHTUNG: Bestehende Werte werden NICHT zurückgesetzt — nur Platzhalter"
log_warn "         '<WIRD_VIA_VAULT_GESETZT>' werden ersetzt."
echo ""
read -r -p "  Fortfahren? [j/N] " CONFIRM

if [[ ! "$CONFIRM" =~ ^[jJyY]$ ]]; then
    log_info "Abgebrochen — vault.yml bleibt unverändert."
    exit 0
fi

# ─── Vault entschlüsseln, modifizieren, neu verschlüsseln ──────────────────
TMP_VAULT=$(mktemp)
# shellcheck disable=SC2064
trap "rm -f '$TMP_VAULT'" EXIT
chmod 600 "$TMP_VAULT"

log_info "Entschlüssele vault.yml..."
if ! ansible-vault decrypt --output "$TMP_VAULT" \
       --vault-password-file "$VAULT_PASS_FILE" "$VAULT_FILE" 2>/dev/null; then
    # Falls Datei nicht verschlüsselt ist, einfach kopieren
    cp "$VAULT_FILE" "$TMP_VAULT"
fi

# Nur Platzhalter ersetzen (sed -i mit Backreference)
# WARUM grep+sed: in-place Ersetzung ist YAML-sicher, da Werte in Quotes stehen.
replace_placeholder() {
    local key="$1"
    local value="$2"
    # Nur ersetzen wenn der Wert noch der Platzhalter ist
    if grep -qE "^${key}:.*<WIRD_VIA_VAULT_GESETZT>" "$TMP_VAULT"; then
        # Slashes im Wert escapen (für sed)
        local escaped="${value//\//\\/}"
        sed -i "s|^${key}:.*|${key}: \"${escaped}\"|" "$TMP_VAULT"
        log_ok "  $key: ersetzt"
    else
        log_info "  $key: bereits gesetzt (übersprungen)"
    fi
}

replace_placeholder "vault_matrix_registration_shared_secret" "$MATRIX_REG_SECRET"
replace_placeholder "vault_matrix_macaroon_secret_key" "$MATRIX_MACAROON"
replace_placeholder "vault_matrix_db_password" "$MATRIX_DB_PASS"
replace_placeholder "vault_coturn_auth_secret" "$COTURN_SECRET"
replace_placeholder "vault_nextcloud_db_password" "$NEXTCLOUD_DB"
replace_placeholder "vault_nextcloud_db_root_password" "$NEXTCLOUD_DB_ROOT"
replace_placeholder "vault_nextcloud_admin_password" "$NEXTCLOUD_ADMIN"

log_info "Verschlüssele vault.yml neu..."
ansible-vault encrypt --vault-password-file "$VAULT_PASS_FILE" \
    --output "$VAULT_FILE" "$TMP_VAULT"
log_ok "vault.yml verschlüsselt aktualisiert"

# Variablen aus Speicher löschen (best effort)
unset MATRIX_REG_SECRET MATRIX_MACAROON MATRIX_DB_PASS
unset COTURN_SECRET NEXTCLOUD_DB NEXTCLOUD_DB_ROOT NEXTCLOUD_ADMIN

echo ""

# ─── Ergebnis ───────────────────────────────────────────────────────────────
echo "============================================================"
echo "  Secrets erfolgreich generiert und gespeichert!"
echo "============================================================"
echo ""
echo "  Manuell prüfen (zeigt entschlüsselt):"
echo "    ansible-vault view $VAULT_FILE"
echo ""
echo "  Bearbeiten (z.B. PVE/PBS-Tokens manuell eintragen):"
echo "    ansible-vault edit $VAULT_FILE"
echo ""
echo "  Diese Secrets müssen NICHT manuell notiert werden — sie werden"
echo "  ausschließlich von Ansible konsumiert. Verloren = neu generieren."
echo ""
