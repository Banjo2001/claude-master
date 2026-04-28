#!/usr/bin/env bash
# =============================================================================
# DATEI:        scripts/security/setup_fail2ban.sh
# ZWECK:        Fail2Ban installieren und konfigurieren
# AUFRUFEN:     sudo ./setup_fail2ban.sh
# VORAUSSETZUNGEN:
#   - Debian/Ubuntu
#   - jail.local aus config/fail2ban/ vorhanden
# SICHERHEIT:
#   - Backup-Verhalten: Bestehende jail.local wird gesichert
#   - Destruktiv: NEIN
#   - Rollback: systemctl stop fail2ban && apt remove fail2ban
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

if [[ "${EUID}" -ne 0 ]]; then
    log_error "Root erforderlich: sudo $0"
    exit 1
fi

# ─── Pfade ────────────────────────────────────────────────────────────────────
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly JAIL_SOURCE="${REPO_ROOT}/config/fail2ban/jail.local"
readonly JAIL_DEST="/etc/fail2ban/jail.local"

log_section "Fail2Ban Setup"

# ─── Installieren ─────────────────────────────────────────────────────────────
log_section "Schritt 1: Installation"
log_info "Paketliste aktualisieren..."
apt-get update -qq

log_info "Fail2Ban installieren..."
apt-get install -y fail2ban

# ─── Backup ───────────────────────────────────────────────────────────────────
log_section "Schritt 2: Konfiguration"

if [[ -f "${JAIL_DEST}" ]]; then
    # SICHERUNG: Bestehende Konfiguration sichern
    cp "${JAIL_DEST}" "${JAIL_DEST}.bak.$(date +%F)"
    log_info "Backup erstellt: ${JAIL_DEST}.bak.$(date +%F)"
fi

# ─── Konfiguration kopieren ───────────────────────────────────────────────────
if [[ ! -f "${JAIL_SOURCE}" ]]; then
    log_error "jail.local nicht gefunden: ${JAIL_SOURCE}"
    log_error "Stelle sicher, dass das Repository vollständig vorhanden ist."
    exit 1
fi

cp "${JAIL_SOURCE}" "${JAIL_DEST}"
chmod 644 "${JAIL_DEST}"
log_info "jail.local kopiert: ${JAIL_DEST}"

# ─── Fail2Ban starten ─────────────────────────────────────────────────────────
log_section "Schritt 3: Dienst starten"
systemctl enable fail2ban
systemctl restart fail2ban

log_info "Warte auf Fail2Ban-Start..."
sleep 3

if systemctl is-active --quiet fail2ban; then
    log_info "Fail2Ban läuft"
else
    log_error "Fail2Ban konnte nicht gestartet werden!"
    log_error "Log prüfen: journalctl -u fail2ban --no-pager -n 50"
    exit 1
fi

# ─── Status anzeigen ──────────────────────────────────────────────────────────
log_section "Status"
fail2ban-client status

log_section "Abgeschlossen"
log_info "Fail2Ban konfiguriert und aktiv."
log_info "Status prüfen: fail2ban-client status sshd"
log_warn "ANPASSEN: Management-IP in ${JAIL_DEST} setzen (ignoreip)"
