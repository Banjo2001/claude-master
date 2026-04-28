#!/usr/bin/env bash
# =============================================================================
# DATEI:        scripts/proxmox/pve_status_report.sh
# ZWECK:        Übersicht über VMs, LXC-Container und Ressourcen auf PVE
# AUFRUFEN:     ./pve_status_report.sh
# VORAUSSETZUNGEN:
#   - .env Datei im Repo-Root (PVE_HOST, PVE_TOKEN_ID, PVE_TOKEN_SECRET)
#   - proxmox-api/lib/pve_api.sh vorhanden
# SICHERHEIT:
#   - Destruktiv: NEIN (nur Lesezugriff)
# VERSION:      1.0.0 | Stand: 2026-04
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# .env laden
if [[ -f "${REPO_ROOT}/.env" ]]; then
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/.env"
fi

# PVE API-Bibliothek laden
# shellcheck disable=SC1091
source "${REPO_ROOT}/proxmox-api/lib/pve_api.sh"

readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

log_section() { echo -e "\n${CYAN}━━━ $* ━━━${NC}"; }

echo ""
echo "=================================================================="
echo "  Proxmox VE Status-Report — $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Host: ${PVE_HOST:-nicht gesetzt}"
echo "=================================================================="

# ─── API-Verbindung testen ────────────────────────────────────────────────────
log_section "API-Verbindung"
pve_api_test

# ─── Cluster-Status ───────────────────────────────────────────────────────────
log_section "Cluster-Status"
pve_cluster_status

# ─── Node-Status ──────────────────────────────────────────────────────────────
log_section "Node-Status"
NODE="${PVE_NODE:-pve}"
pve_node_status "${NODE}"

# ─── VMs ──────────────────────────────────────────────────────────────────────
log_section "Virtuelle Maschinen"
pve_vm_list "${NODE}"

# ─── LXC-Container ────────────────────────────────────────────────────────────
log_section "LXC-Container"
pve_lxc_list "${NODE}"

# ─── Storage ──────────────────────────────────────────────────────────────────
log_section "Storage"
pve_storage_list "${NODE}"

echo ""
echo "Report abgeschlossen: $(date '+%Y-%m-%d %H:%M:%S')"
