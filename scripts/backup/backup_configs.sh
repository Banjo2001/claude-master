#!/usr/bin/env bash
# =============================================================================
# DATEI:        scripts/backup/backup_configs.sh
# ZWECK:        Konfigurationsdateien sichern (vor Änderungen oder täglich)
# AUFRUFEN:     ./backup_configs.sh [zielverzeichnis]
# SICHERHEIT:
#   - Backup-Verhalten: Erstellt tar.gz Archiv mit Timestamp
#   - Destruktiv: NEIN
#   - Rollback: tar -xzf <archiv> -C /
# VERSION:      1.0.0 | Stand: 2026-04
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

log_info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_section() { echo -e "\n${CYAN}━━━ $* ━━━${NC}"; }

# ─── Konfiguration ────────────────────────────────────────────────────────────
readonly BACKUP_DIR="${1:-/opt/backups/configs}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
readonly TIMESTAMP
readonly ARCHIVE="${BACKUP_DIR}/config-backup-${TIMESTAMP}.tar.gz"

# Zu sichernde Pfade (nur Konfigurationen, keine Daten!)
readonly BACKUP_PATHS=(
    "/etc/ssh/sshd_config"
    "/etc/ssh/sshd_config.d"
    "/etc/fail2ban/jail.local"
    "/etc/fail2ban/filter.d"
    "/etc/sysctl.d/99-hardening.conf"
    "/etc/ufw"
    "/opt/matrix/compose.yml"
    "/opt/matrix/config"
    "/opt/nextcloud-aio/compose.yml"
    "/etc/cron.d"
    "/etc/systemd/system"
)

log_section "Konfigurations-Backup"
log_info "Zielverzeichnis: ${BACKUP_DIR}"
log_info "Archiv: ${ARCHIVE}"

# ─── Zielverzeichnis erstellen ────────────────────────────────────────────────
mkdir -p "${BACKUP_DIR}"
chmod 700 "${BACKUP_DIR}"

# ─── Vorhandene Pfade sammeln ─────────────────────────────────────────────────
EXISTING_PATHS=()
for PATH_ENTRY in "${BACKUP_PATHS[@]}"; do
    if [[ -e "${PATH_ENTRY}" ]]; then
        EXISTING_PATHS+=("${PATH_ENTRY}")
    fi
done

if [[ "${#EXISTING_PATHS[@]}" -eq 0 ]]; then
    log_error "Keine der konfigurierten Pfade gefunden!"
    exit 1
fi

log_info "Sichere ${#EXISTING_PATHS[@]} Pfade..."

# ─── Archiv erstellen ─────────────────────────────────────────────────────────
# SICHERUNG: Erstellt komprimiertes Archiv aller Konfigurationen
tar -czf "${ARCHIVE}" "${EXISTING_PATHS[@]}" 2>/dev/null || {
    log_error "Fehler beim Erstellen des Archivs: ${ARCHIVE}"
    exit 1
}

chmod 600 "${ARCHIVE}"
ARCHIVE_SIZE=$(du -sh "${ARCHIVE}" | cut -f1)
log_info "Archiv erstellt: ${ARCHIVE} (${ARCHIVE_SIZE})"

# ─── Alte Backups aufräumen (behalte letzte 30) ───────────────────────────────
log_section "Alte Backups aufräumen"
BACKUP_COUNT=$(find "${BACKUP_DIR}" -name "config-backup-*.tar.gz" | wc -l)
if [[ "${BACKUP_COUNT}" -gt 30 ]]; then
    REMOVE_COUNT=$((BACKUP_COUNT - 30))
    find "${BACKUP_DIR}" -name "config-backup-*.tar.gz" | sort | head -"${REMOVE_COUNT}" | while read -r OLD_BACKUP; do
        rm -f "${OLD_BACKUP}"
        log_info "Altes Backup entfernt: $(basename "${OLD_BACKUP}")"
    done
fi

log_info "Backup abgeschlossen."
log_info "Wiederherstellen: sudo tar -xzf ${ARCHIVE} -C /"
