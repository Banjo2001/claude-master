#!/usr/bin/env bash
# =============================================================================
# DATEI:        scripts/proxmox/pbs_verify_backups.sh
# ZWECK:        Alle Backups auf Proxmox Backup Server verifizieren
# AUFRUFEN:     ./pbs_verify_backups.sh [datastore]
# VORAUSSETZUNGEN:
#   - .env Datei mit PBS_* Variablen
#   - proxmox-api/lib/pbs_api.sh vorhanden
# SICHERHEIT:
#   - Destruktiv: NEIN (nur Lesezugriff + Verifikation)
# VERSION:      1.0.0 | Stand: 2026-04
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly REPO_ROOT

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

log_info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_section() { echo -e "\n${CYAN}━━━ $* ━━━${NC}"; }

# ─── Umgebung laden ───────────────────────────────────────────────────────────
if [[ -f "${REPO_ROOT}/.env" ]]; then
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/.env"
fi

# shellcheck disable=SC1091
source "${REPO_ROOT}/proxmox-api/lib/pbs_api.sh"

readonly DATASTORE="${1:-${PBS_DATASTORE:-backup}}"

echo ""
echo "=================================================================="
echo "  PBS Backup-Verifikation — $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Host: ${PBS_HOST:-nicht gesetzt}"
echo "  Datastore: ${DATASTORE}"
echo "=================================================================="

# ─── Verbindung testen ────────────────────────────────────────────────────────
log_section "PBS Verbindung"
pbs_api_test

# ─── Datastore-Status ─────────────────────────────────────────────────────────
log_section "Datastore-Status"
pbs_datastore_status "${DATASTORE}"

# ─── Backup-Liste ─────────────────────────────────────────────────────────────
log_section "Vorhandene Backups"
pbs_backup_list "${DATASTORE}"

# ─── Letzten Snapshot anzeigen ────────────────────────────────────────────────
log_section "Neuester Snapshot"
pbs_snapshot_latest "${DATASTORE}"

# ─── Verifikation starten ─────────────────────────────────────────────────────
log_section "Verifikation starten"
log_info "Starte Verifikation aller Backups im Datastore '${DATASTORE}'..."
log_info "Hinweis: Verifikation läuft als Hintergrundtask auf PBS."
pbs_verify_all "${DATASTORE}"

log_info ""
log_info "Verifikations-Task gestartet. Status prüfen mit:"
log_info "  pbs_task_list (in pbs_api.sh)"
log_info "  Oder im PBS Web-Interface: https://${PBS_HOST:-<PBS-HOST>}:8007"
