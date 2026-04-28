#!/usr/bin/env bash
# =============================================================================
# DATEI:        scripts/proxmox/pve_snapshot_rollback.sh
# ZWECK:        Rollback einer VM/LXC zu einem Snapshot
# AUFRUFEN:     ./pve_snapshot_rollback.sh <vmid> <snapshot-name>
# BEISPIEL:     ./pve_snapshot_rollback.sh 100 "vor-update-2026-04"
# VORAUSSETZUNGEN:
#   - .env Datei mit PVE_* Variablen
#   - proxmox-api/lib/pve_api.sh vorhanden
# SICHERHEIT:
#   - Destruktiv: JA — Änderungen nach dem Snapshot gehen verloren!
#   - Rollback: NICHT möglich (Snapshot-Rollback ist selbst der Rollback)
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
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ─── Parameter ────────────────────────────────────────────────────────────────
VMID="${1:-}"
SNAP_NAME="${2:-}"

if [[ -z "${VMID}" || -z "${SNAP_NAME}" ]]; then
    log_error "Parameter fehlen!"
    echo "Verwendung: $0 <vmid> <snapshot-name>"
    echo "Beispiel:   $0 100 'vor-update'"
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

# ─── Verfügbare Snapshots anzeigen ────────────────────────────────────────────
log_info "Verfügbare Snapshots für VM/LXC ${VMID}:"
pve_snapshot_list "${NODE}" "${VMID}"

# ─── Sicherheitswarnung ───────────────────────────────────────────────────────
echo ""
log_warn "⚠️  ACHTUNG — DESTRUKTIV!"
log_warn "Rollback zu Snapshot '${SNAP_NAME}' für VM/LXC ${VMID}"
log_warn "Alle Änderungen NACH dem Snapshot gehen UNWIDERRUFLICH verloren!"
echo ""
read -r -p "Rollback wirklich durchführen? [ja/NEIN]: " CONFIRM

if [[ "${CONFIRM,,}" != "ja" ]]; then
    log_info "Abbruch — keine Änderungen."
    exit 0
fi

# ─── Rollback durchführen ─────────────────────────────────────────────────────
log_info "Führe Rollback durch..."
pve_snapshot_rollback "${NODE}" "${VMID}" "${SNAP_NAME}"

log_info "Rollback zu '${SNAP_NAME}' erfolgreich."
log_info "VM/LXC ${VMID} befindet sich jetzt im Zustand des Snapshots."
