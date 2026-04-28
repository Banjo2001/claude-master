#!/usr/bin/env bash
# =============================================================================
# DATEI:        scripts/proxmox/pve_snapshot_create.sh
# ZWECK:        Snapshot einer VM oder eines LXC-Containers erstellen
# AUFRUFEN:     ./pve_snapshot_create.sh <vmid> [snapshot-name] [beschreibung]
# BEISPIEL:     ./pve_snapshot_create.sh 100 "vor-update-2026-04" "vor nginx-Update"
# VORAUSSETZUNGEN:
#   - .env Datei mit PVE_* Variablen
#   - proxmox-api/lib/pve_api.sh vorhanden
# SICHERHEIT:
#   - Destruktiv: NEIN (Snapshot erstellt, nichts gelöscht)
#   - Rollback: pve_snapshot_rollback.sh verwenden
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
readonly NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ─── Parameter ────────────────────────────────────────────────────────────────
VMID="${1:-}"
SNAP_NAME="${2:-auto-$(date +%Y%m%d-%H%M)}"
SNAP_DESC="${3:-Automatischer Snapshot}"

if [[ -z "${VMID}" ]]; then
    log_error "VMID fehlt!"
    echo "Verwendung: $0 <vmid> [snapshot-name] [beschreibung]"
    echo "Beispiel:   $0 100 'vor-update' 'vor nginx Update'"
    exit 1
fi

# ─── Umgebung laden ───────────────────────────────────────────────────────────
if [[ -f "${REPO_ROOT}/.env" ]]; then
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/.env"
fi

# shellcheck disable=SC1091
source "${REPO_ROOT}/proxmox-api/lib/pve_api.sh"

readonly NODE="${PVE_NODE:-pve}"

# ─── Bestehende Snapshots anzeigen ────────────────────────────────────────────
log_info "Bestehende Snapshots für VM/LXC ${VMID}:"
pve_snapshot_list "${NODE}" "${VMID}" || true

# ─── Snapshot erstellen ───────────────────────────────────────────────────────
log_info "Erstelle Snapshot '${SNAP_NAME}' für VM/LXC ${VMID}..."
log_info "Beschreibung: ${SNAP_DESC}"

pve_snapshot_create "${NODE}" "${VMID}" "${SNAP_NAME}" "${SNAP_DESC}"

log_info "Snapshot erfolgreich erstellt."
log_info "Rollback-Befehl: scripts/proxmox/pve_snapshot_rollback.sh ${VMID} ${SNAP_NAME}"
