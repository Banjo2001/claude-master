#!/usr/bin/env bash
# =============================================================================
# DATEI:        scripts/backup/cleanup_old_backups.sh
# ZWECK:        Alte Backups nach Aufbewahrungsrichtlinie löschen
# AUFRUFEN:     ./cleanup_old_backups.sh [backup-verzeichnis] [behalten]
# BEISPIEL:     ./cleanup_old_backups.sh /opt/backups 30
# SICHERHEIT:
#   - Backup-Verhalten: Löscht alte Backups (destruktiv!)
#   - Destruktiv: JA — alte Backup-Archive werden gelöscht
#   - Rollback: nicht möglich (gelöschte Backups nicht wiederherstellbar)
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

# ─── Konfiguration ────────────────────────────────────────────────────────────
readonly BACKUP_DIR="${1:-/opt/backups}"
readonly KEEP_COUNT="${2:-30}"
readonly DRY_RUN="${DRY_RUN:-false}"

log_section "Backup-Aufräumen"
log_info "Verzeichnis: ${BACKUP_DIR}"
log_info "Behalten: letzte ${KEEP_COUNT} Archive"
if [[ "${DRY_RUN}" == "true" ]]; then
    log_warn "DRY-RUN Modus — keine Dateien werden gelöscht"
fi

# ─── Verzeichnis prüfen ───────────────────────────────────────────────────────
if [[ ! -d "${BACKUP_DIR}" ]]; then
    log_error "Backup-Verzeichnis nicht gefunden: ${BACKUP_DIR}"
    exit 1
fi

# ─── Konfigurations-Backups aufräumen ─────────────────────────────────────────
log_section "Konfigurations-Backups"

CONFIGS_DIR="${BACKUP_DIR}/configs"
if [[ -d "${CONFIGS_DIR}" ]]; then
    mapfile -t ALL_BACKUPS < <(find "${CONFIGS_DIR}" -name "config-backup-*.tar.gz" | sort)
    TOTAL="${#ALL_BACKUPS[@]}"
    DELETE_COUNT=$((TOTAL > KEEP_COUNT ? TOTAL - KEEP_COUNT : 0))

    log_info "Gefunden: ${TOTAL} Archive | Zu löschen: ${DELETE_COUNT}"

    if [[ "${DELETE_COUNT}" -gt 0 ]]; then
        # ⚠️  ACHTUNG — DESTRUKTIV: Löscht alte Backup-Archive
        # Rollback: nicht möglich
        for i in $(seq 0 $((DELETE_COUNT - 1))); do
            TARGET="${ALL_BACKUPS[${i}]}"
            if [[ "${DRY_RUN}" == "true" ]]; then
                log_warn "[DRY-RUN] Würde löschen: $(basename "${TARGET}")"
            else
                rm -f "${TARGET}"
                log_info "Gelöscht: $(basename "${TARGET}")"
            fi
        done
    else
        log_info "Keine alten Archive zu löschen."
    fi
else
    log_info "Kein Konfigurations-Backup-Verzeichnis: ${CONFIGS_DIR}"
fi

# ─── Docker Log-Dateien aufräumen ─────────────────────────────────────────────
log_section "Docker-Logs (> 100MB)"

if command -v docker &>/dev/null; then
    # Log-Größe anzeigen
    docker system df --verbose 2>/dev/null | head -20 | sed 's/^/  /'
    echo ""
    log_warn "Zum Aufräumen von Docker-Logs und ungenutzten Images:"
    log_warn "  docker system prune --volumes  (interaktiv)"
    log_warn "  docker image prune -a           (ungenutzte Images)"
fi

log_section "Abgeschlossen"
log_info "Aufräumen abgeschlossen."
