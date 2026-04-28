#!/usr/bin/env bash
# =============================================================================
# DATEI:        scripts/backup/backup_test_restore.sh
# ZWECK:        Backup-Restore-Test (Simulation ohne echten Restore)
#               Prüft ob Backups vorhanden, lesbar und vollständig sind.
# AUFRUFEN:     ./backup_test_restore.sh
# VORAUSSETZUNGEN:
#   - .env mit PBS_* Variablen für Proxmox Backup Server Tests
# SICHERHEIT:
#   - Destruktiv: NEIN (Simulation — kein echter Restore!)
#   - Rollback: nicht erforderlich (kein Eingriff ins System)
# VERSION:      1.0.0 | Stand: 2026-04
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

log_ok()      { echo -e "${GREEN}  [OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}  [WARN]${NC}  $*"; }
log_fail()    { echo -e "${RED}  [FAIL]${NC}  $*"; }
log_info()    { echo -e "  [INFO]  $*"; }
log_section() { echo -e "\n${CYAN}━━━ $* ━━━${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly REPO_ROOT

FAILURES=0
WARNINGS=0

echo ""
echo "=================================================================="
echo "  Backup-Restore-Test (SIMULATION) — $(date '+%Y-%m-%d %H:%M:%S')"
echo "  KEIN echter Restore — nur Prüfung der Backups!"
echo "=================================================================="

# ─── Test 1: Lokale Konfigurations-Backups ────────────────────────────────────
log_section "Test 1: Lokale Konfigurations-Backups"

BACKUP_DIR="/opt/backups/configs"
if [[ -d "${BACKUP_DIR}" ]]; then
    BACKUP_COUNT=$(find "${BACKUP_DIR}" -name "config-backup-*.tar.gz" | wc -l)
    if [[ "${BACKUP_COUNT}" -eq 0 ]]; then
        log_fail "Keine Konfigurations-Backups gefunden in ${BACKUP_DIR}"
        ((FAILURES++))
    else
        LATEST=$(find "${BACKUP_DIR}" -name "config-backup-*.tar.gz" | sort | tail -1)
        LATEST_AGE=$(( ($(date +%s) - $(stat -c %Y "${LATEST}")) / 3600 ))
        log_ok "${BACKUP_COUNT} Backups gefunden, neuestes: $(basename "${LATEST}")"
        if [[ "${LATEST_AGE}" -gt 48 ]]; then
            log_warn "Letztes Backup ist ${LATEST_AGE}h alt (>48h)"
            ((WARNINGS++))
        else
            log_ok "Letztes Backup ist ${LATEST_AGE}h alt — aktuell"
        fi

        # Integrität des letzten Backups prüfen
        log_info "Prüfe Integrität: $(basename "${LATEST}")..."
        if tar -tzf "${LATEST}" &>/dev/null; then
            log_ok "Archiv ist integer (tar -tzf bestanden)"
        else
            log_fail "Archiv BESCHÄDIGT: ${LATEST}"
            ((FAILURES++))
        fi
    fi
else
    log_warn "Backup-Verzeichnis nicht vorhanden: ${BACKUP_DIR}"
    log_warn "Erste Backup-Erstellung: scripts/backup/backup_configs.sh"
    ((WARNINGS++))
fi

# ─── Test 2: Docker-Volume-Backups ────────────────────────────────────────────
log_section "Test 2: Docker Volumes"

if command -v docker &>/dev/null; then
    VOLUMES=$(docker volume ls --format "{{.Name}}" 2>/dev/null || echo "")
    if [[ -n "${VOLUMES}" ]]; then
        log_ok "Docker-Volumes vorhanden:"
        echo "${VOLUMES}" | while read -r vol; do
            log_info "  - ${vol}"
        done
    else
        log_warn "Keine Docker-Volumes gefunden"
        ((WARNINGS++))
    fi
else
    log_warn "Docker nicht verfügbar"
fi

# ─── Test 3: PBS-Verbindung (wenn konfiguriert) ───────────────────────────────
log_section "Test 3: Proxmox Backup Server"

PBS_API="${REPO_ROOT}/proxmox-api/lib/pbs_api.sh"
ENV_FILE="${REPO_ROOT}/.env"

if [[ -f "${ENV_FILE}" && -f "${PBS_API}" ]]; then
    # shellcheck disable=SC1090
    source "${ENV_FILE}"
    # shellcheck disable=SC1090
    source "${PBS_API}"

    if pbs_api_test &>/dev/null; then
        log_ok "PBS-Verbindung OK: ${PBS_HOST:-unbekannt}"

        DATASTORE="${PBS_DATASTORE:-backup}"
        LATEST_SNAP=$(pbs_snapshot_latest "${DATASTORE}" 2>/dev/null | head -3 || echo "")
        if [[ -n "${LATEST_SNAP}" ]]; then
            log_ok "Neuester PBS-Snapshot vorhanden"
            echo "${LATEST_SNAP}" | sed 's/^/    /'
        else
            log_warn "Keine PBS-Snapshots gefunden"
            ((WARNINGS++))
        fi
    else
        log_warn "PBS nicht erreichbar — Konfiguration prüfen"
        ((WARNINGS++))
    fi
else
    log_warn "PBS nicht konfiguriert (.env oder pbs_api.sh fehlt)"
    log_warn "Für PBS-Tests: PVE_* und PBS_* in .env eintragen"
fi

# ─── Zusammenfassung ──────────────────────────────────────────────────────────
log_section "Zusammenfassung"

if [[ "${FAILURES}" -eq 0 && "${WARNINGS}" -eq 0 ]]; then
    echo -e "${GREEN}  Backup-Test bestanden.${NC}"
    exit 0
elif [[ "${FAILURES}" -gt 0 ]]; then
    echo -e "${RED}  ${FAILURES} Fehler — Backup-Strategie unvollständig!${NC}"
    exit 1
else
    echo -e "${YELLOW}  ${WARNINGS} Warnungen — Backup-Strategie prüfen.${NC}"
    exit 0
fi
