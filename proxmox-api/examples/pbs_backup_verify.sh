#!/usr/bin/env bash
# =============================================================================
# DATEI:        pbs_backup_verify.sh
# ZWECK:        Beispiel — Backups im Proxmox Backup Server prüfen und
#               verifizieren. Zeigt Backup-Übersicht + startet Verifikation.
# AUFRUFEN:     bash proxmox-api/examples/pbs_backup_verify.sh [datastore]
# VORAUSSETZUNGEN:
#   - .env Datei mit PBS_* Variablen
#   - jq installiert
# SICHERHEIT:
#   - Backup-Verhalten: keines (Lesezugriff + optionale Verifikation)
#   - Destruktiv: NEIN (Verifikation ist rein lesend)
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

# shellcheck source=../lib/pbs_api.sh
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/pbs_api.sh"

DATASTORE="${1:-${PBS_DATASTORE:-backup-store}}"

echo ""
echo "============================================================"
echo "  Proxmox Backup Server — Backup-Prüfung"
echo "  Host: ${PBS_HOST}:${PBS_PORT}"
echo "  Datastore: ${DATASTORE}"
echo "============================================================"
echo ""

# ─── Verbindungstest ─────────────────────────────────────────────────────────
echo "[ API-Verbindung ]"
pbs_api_test
echo ""

# ─── Server-Status ───────────────────────────────────────────────────────────
echo "[ Server Status ]"
pbs_node_status
echo ""

# ─── Datastore-Übersicht ─────────────────────────────────────────────────────
echo "[ Datastores ]"
pbs_datastore_list
echo ""

# ─── Datastore-Details ───────────────────────────────────────────────────────
echo "[ Datastore '${DATASTORE}' Details ]"
pbs_datastore_status "$DATASTORE"
echo ""

# ─── Backup-Gruppen ──────────────────────────────────────────────────────────
echo "[ Backup-Gruppen in '${DATASTORE}' ]"
pbs_backup_list "$DATASTORE"
echo ""

# ─── Neueste Backups pro Gruppe ──────────────────────────────────────────────
echo "[ Neueste Backups ]"
echo "VMs (vm/*)"
pbs_backup_list "$DATASTORE" 2>/dev/null | \
    jq -r 'select(.type == "vm") | "  VM \(.id): letztes Backup \(.last_backup | todate), \(.backup_count) Snapshots"' \
    2>/dev/null || echo "  Keine VM-Backups gefunden"

echo "Container (ct/*)"
pbs_backup_list "$DATASTORE" 2>/dev/null | \
    jq -r 'select(.type == "ct") | "  CT \(.id): letztes Backup \(.last_backup | todate), \(.backup_count) Snapshots"' \
    2>/dev/null || echo "  Keine CT-Backups gefunden"
echo ""

# ─── Optionale Verifikation ───────────────────────────────────────────────────
echo "[ Verifikation ]"
echo "  Eine vollständige Verifikation liest alle Chunks und prüft Checksummen."
echo "  Dies kann bei großen Datastores mehrere Stunden dauern."
echo ""
read -r -p "  Vollständige Verifikation starten? [j/N] " VERIFY
if [[ "$VERIFY" =~ ^[jJyY]$ ]]; then
    pbs_verify_all "$DATASTORE"
    echo ""
    echo "  Verifikation läuft als Hintergrund-Task."
    echo "  Status prüfen mit: pbs_task_list"
else
    echo "  Verifikation übersprungen."
fi

echo ""
echo "============================================================"
echo "  Backup-Prüfung abgeschlossen"
echo "============================================================"
echo ""
