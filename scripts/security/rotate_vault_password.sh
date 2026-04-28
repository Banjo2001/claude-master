#!/usr/bin/env bash
# =============================================================================
# DATEI:        scripts/security/rotate_vault_password.sh
# ZWECK:        Ansible Vault Passwort rotieren
# AUFRUFEN:     ./rotate_vault_password.sh
# VORAUSSETZUNGEN:
#   - ansible-vault installiert
#   - ~/.vault_pass.txt vorhanden (aktuelles Passwort)
#   - ansible/inventories/prod/group_vars/all/vault.yml verschlüsselt
# SICHERHEIT:
#   - Backup-Verhalten: vault.yml wird gesichert vor der Rotation
#   - Destruktiv: JA — altes Passwort wird ungültig
#   - Rollback: vault.yml.bak wiederherstellen + altes Passwort setzen
# VERSION:      1.0.0 | Stand: 2026-04
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

log_info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_section() { echo -e "\n${CYAN}━━━ $* ━━━${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly REPO_ROOT
readonly VAULT_FILE="${REPO_ROOT}/ansible/inventories/prod/group_vars/all/vault.yml"
readonly VAULT_PASS_FILE="${HOME}/.vault_pass.txt"
readonly NEW_VAULT_PASS_FILE="${HOME}/.vault_pass_new.txt"

log_section "Ansible Vault Passwort-Rotation"

# ─── Voraussetzungen prüfen ───────────────────────────────────────────────────
if ! command -v ansible-vault &>/dev/null; then
    log_error "ansible-vault nicht installiert"
    exit 1
fi

if [[ ! -f "${VAULT_PASS_FILE}" ]]; then
    log_error "Aktuelles Vault-Passwort nicht gefunden: ${VAULT_PASS_FILE}"
    exit 1
fi

if [[ ! -f "${VAULT_FILE}" ]]; then
    log_error "Vault-Datei nicht gefunden: ${VAULT_FILE}"
    exit 1
fi

# ─── Sicherheitswarnung ───────────────────────────────────────────────────────
log_warn "⚠️  Diese Aktion rotiert das Ansible Vault Passwort."
log_warn "Stelle sicher, dass du das neue Passwort sicher aufbewahrst!"
log_warn "Vault-Datei: ${VAULT_FILE}"
echo ""
read -r -p "Fortfahren? [ja/NEIN]: " CONFIRM
if [[ "${CONFIRM,,}" != "ja" ]]; then
    log_info "Abbruch."
    exit 0
fi

# ─── Neues Passwort eingeben ──────────────────────────────────────────────────
log_section "Neues Passwort"

while true; do
    read -rs -p "Neues Vault-Passwort (min. 20 Zeichen): " NEW_PASS
    echo ""
    read -rs -p "Wiederholung: " NEW_PASS_CONFIRM
    echo ""

    if [[ "${NEW_PASS}" != "${NEW_PASS_CONFIRM}" ]]; then
        log_error "Passwörter stimmen nicht überein!"
        continue
    fi

    if [[ "${#NEW_PASS}" -lt 20 ]]; then
        log_error "Passwort zu kurz (${#NEW_PASS} Zeichen, min. 20 erforderlich)"
        continue
    fi

    break
done

# ─── Backup erstellen ─────────────────────────────────────────────────────────
log_section "Backup"
# SICHERUNG: vault.yml sichern vor Rotation
cp "${VAULT_FILE}" "${VAULT_FILE}.bak.$(date +%F-%H%M)"
log_info "Backup erstellt: ${VAULT_FILE}.bak.$(date +%F-%H%M)"

# ─── Rotation durchführen ─────────────────────────────────────────────────────
log_section "Rotation"

# Neues Passwort temporär speichern
echo "${NEW_PASS}" > "${NEW_VAULT_PASS_FILE}"
chmod 600 "${NEW_VAULT_PASS_FILE}"

# vault.yml mit neuem Passwort re-verschlüsseln
ansible-vault rekey \
    --vault-password-file="${VAULT_PASS_FILE}" \
    --new-vault-password-file="${NEW_VAULT_PASS_FILE}" \
    "${VAULT_FILE}"

# Altes Passwort-File mit neuem ersetzen
cp "${NEW_VAULT_PASS_FILE}" "${VAULT_PASS_FILE}"
rm -f "${NEW_VAULT_PASS_FILE}"
log_info "Passwort rotiert und ~/.vault_pass.txt aktualisiert"

# ─── Verifikation ─────────────────────────────────────────────────────────────
log_section "Verifikation"
if ansible-vault view --vault-password-file="${VAULT_PASS_FILE}" "${VAULT_FILE}" &>/dev/null; then
    log_info "Verifikation OK — Vault mit neuem Passwort lesbar"
else
    log_error "Verifikation FEHLGESCHLAGEN!"
    log_error "Rollback: cp ${VAULT_FILE}.bak.$(date +%F) ${VAULT_FILE}"
    exit 1
fi

log_section "Abgeschlossen"
log_info "Passwort-Rotation erfolgreich."
log_warn "WICHTIG: Neues Passwort sicher aufbewahren (z.B. KeePass/Bitwarden)!"
