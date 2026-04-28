#!/usr/bin/env bash
# =============================================================================
# DATEI:        snapshot_create.sh
# ZWECK:        Beispiel — Snapshot für eine VM oder einen LXC-Container erstellen.
#               Demonstriert Snapshot-Erstellung und -Verwaltung via PVE API.
# AUFRUFEN:     bash proxmox-api/examples/snapshot_create.sh <vmid> [vm|lxc] [snapshot-name]
# BEISPIEL:     bash proxmox-api/examples/snapshot_create.sh 100 lxc "vor-update-2026-04"
# VORAUSSETZUNGEN:
#   - .env Datei mit PVE_* Variablen
#   - jq installiert
# SICHERHEIT:
#   - Bei VMs mit laufendem RAM-State: kurze IO-Pause (wenige Sekunden)
#   - Destruktiv: NEIN (Snapshot-Erstellung ist nicht destruktiv)
#   - Rollback: pve_snapshot_rollback() (interaktiv, mit Bestätigung)
# VERSION:      1.0.0 | Stand: 2026-04
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# .env laden
if [ -f "$REPO_ROOT/.env" ]; then
    # shellcheck disable=SC1091
    set -a; source "$REPO_ROOT/.env"; set +a
else
    echo "FEHLER: .env nicht gefunden — cp .env.example .env" >&2
    exit 1
fi

# shellcheck source=../lib/pve_api.sh
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/pve_api.sh"

# ─── Parameter ───────────────────────────────────────────────────────────────
VMID="${1:-}"
TYP="${2:-lxc}"       # qemu (für VMs) oder lxc (für Container)
SNAP_NAME="${3:-snap-$(date +%Y%m%d-%H%M)}"
DESCRIPTION="Manueller Snapshot vom $(date '+%Y-%m-%d %H:%M')"

if [ -z "$VMID" ]; then
    echo "FEHLER: Keine VM/Container-ID angegeben!" >&2
    echo "Verwendung: $0 <vmid> [qemu|lxc] [snapshot-name]" >&2
    echo "Beispiel:   $0 100 lxc vor-update-2026-04" >&2
    exit 1
fi

if [[ "$TYP" != "qemu" && "$TYP" != "lxc" ]]; then
    echo "FEHLER: Typ muss 'qemu' oder 'lxc' sein (nicht: $TYP)" >&2
    exit 1
fi

echo ""
echo "============================================================"
echo "  Snapshot erstellen"
echo "  ${TYP^^} ${VMID}: '${SNAP_NAME}'"
echo "============================================================"
echo ""

# ─── Aktuellen Status anzeigen ───────────────────────────────────────────────
echo "[ Aktueller Status ]"
if [ "$TYP" = "qemu" ]; then
    pve_vm_status "$VMID"
else
    pve_lxc_status "$VMID"
fi
echo ""

# ─── Bestehende Snapshots anzeigen ───────────────────────────────────────────
echo "[ Vorhandene Snapshots ]"
pve_snapshot_list "$VMID" "$TYP"
echo ""

# ─── Snapshot erstellen ──────────────────────────────────────────────────────
echo "[ Snapshot erstellen ]"
pve_snapshot_create "$VMID" "$SNAP_NAME" "$DESCRIPTION" "$TYP"
echo ""

# ─── Bestätigung ─────────────────────────────────────────────────────────────
echo "[ Snapshots nach Erstellung ]"
pve_snapshot_list "$VMID" "$TYP"
echo ""
echo "Snapshot '${SNAP_NAME}' erfolgreich erstellt!"
echo "Rollback falls nötig: pve_snapshot_rollback $VMID $SNAP_NAME $TYP"
