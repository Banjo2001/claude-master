#!/usr/bin/env bash
# =============================================================================
# DATEI:        list_vms.sh
# ZWECK:        Beispiel-Skript — Listet alle VMs und LXC-Container auf PVE auf.
#               Demonstriert die Verwendung der pve_api.sh Bibliothek.
# AUFRUFEN:     bash proxmox-api/examples/list_vms.sh
# VORAUSSETZUNGEN:
#   - .env Datei mit PVE_* Variablen (aus .env.example kopieren)
#   - jq installiert
# SICHERHEIT:
#   - Backup-Verhalten: keines (nur Lesezugriff)
#   - Destruktiv: NEIN
# VERSION:      1.0.0 | Stand: 2026-04
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

# Skript-Verzeichnis ermitteln und .env laden
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# .env laden falls vorhanden (enthält PVE_* Variablen)
if [ -f "$REPO_ROOT/.env" ]; then
    # shellcheck disable=SC1091
    set -a; source "$REPO_ROOT/.env"; set +a
    echo "INFO: .env geladen"
elif [ -f "$REPO_ROOT/.env.example" ]; then
    echo "HINWEIS: Keine .env gefunden — kopiere .env.example und trage echte Werte ein:"
    echo "  cp .env.example .env && nano .env"
    exit 1
else
    echo "FEHLER: Weder .env noch .env.example gefunden" >&2
    exit 1
fi

# PVE API Bibliothek laden
# shellcheck source=../lib/pve_api.sh
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/pve_api.sh"

echo ""
echo "============================================================"
echo "  Proxmox VE — VM und LXC Übersicht"
echo "  Host: ${PVE_HOST}:${PVE_PORT}"
echo "  Node: ${PVE_NODE}"
echo "============================================================"
echo ""

# ─── Verbindungstest ─────────────────────────────────────────────────────────
echo "[ API-Verbindung ]"
pve_api_test
echo ""

# ─── Node-Status ─────────────────────────────────────────────────────────────
echo "[ Node Status: ${PVE_NODE} ]"
pve_node_status
echo ""

# ─── VMs auflisten ───────────────────────────────────────────────────────────
echo "[ Virtuelle Maschinen (QEMU/KVM) ]"
pve_vm_list
echo ""

# ─── LXC-Container auflisten ─────────────────────────────────────────────────
echo "[ LXC-Container ]"
pve_lxc_list
echo ""

# ─── Storage-Übersicht ───────────────────────────────────────────────────────
echo "[ Storage-Pools ]"
pve_storage_list
echo ""
