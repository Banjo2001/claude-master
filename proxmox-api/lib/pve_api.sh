#!/usr/bin/env bash
# =============================================================================
# DATEI:        pve_api.sh
# ZWECK:        Shell-Bibliothek für Proxmox VE REST-API (v8/v9)
#               Stellt Funktionen für VM/LXC-Verwaltung, Snapshots,
#               Storage-Abfragen und Cluster-Status bereit.
# AUFRUFEN:     source proxmox-api/lib/pve_api.sh
# VORAUSSETZUNGEN:
#   - curl installiert
#   - jq installiert (JSON-Verarbeitung)
#   - Umgebungsvariablen gesetzt (s.u.) oder .env geladen
# UMGEBUNGSVARIABLEN:
#   PVE_HOST          — Hostname/IP des PVE-Nodes (z.B. pve01.example.com)
#   PVE_PORT          — API-Port (Standard: 8006)
#   PVE_TOKEN_ID      — API-Token ID (Format: USER@REALM!TOKENID)
#   PVE_TOKEN_SECRET  — API-Token Secret (UUID)
#   PVE_NODE          — Node-Name für Operationen (Standard: pve01)
#   PVE_VERIFY_SSL    — SSL-Zertifikat prüfen: true/false (Standard: true)
# SICHERHEIT:
#   - Backup-Verhalten: keines (nur Lese-/API-Operationen)
#   - Destruktiv: Abhängig von aufgerufener Funktion
#   - Rollback: Snapshots ermöglichen VM-Rollback
# VERSION:      1.0.0 | Stand: 2026-04
# =============================================================================

# Schutz gegen Mehrfach-Laden
[[ -n "${_PVE_API_LOADED:-}" ]] && return 0
readonly _PVE_API_LOADED=1

# ─── Standard-Werte ──────────────────────────────────────────────────────────
PVE_PORT="${PVE_PORT:-8006}"
PVE_NODE="${PVE_NODE:-pve01}"
PVE_VERIFY_SSL="${PVE_VERIFY_SSL:-true}"

# ─── Interne Hilfsfunktionen ─────────────────────────────────────────────────

# _pve_curl: Führt einen API-Aufruf gegen PVE aus
# Parameter: HTTP-Methode, API-Pfad, [optionale curl-Argumente]
# Gibt JSON zurück oder Exit-Code 1 bei Fehler
_pve_curl() {
    local method="$1"
    local api_path="$2"
    shift 2

    # Pflicht-Variablen prüfen
    if [[ -z "${PVE_HOST:-}" ]]; then
        echo "FEHLER: PVE_HOST ist nicht gesetzt" >&2
        return 1
    fi
    if [[ -z "${PVE_TOKEN_ID:-}" ]] || [[ -z "${PVE_TOKEN_SECRET:-}" ]]; then
        echo "FEHLER: PVE_TOKEN_ID oder PVE_TOKEN_SECRET nicht gesetzt" >&2
        return 1
    fi

    local base_url="https://${PVE_HOST}:${PVE_PORT}/api2/json"
    local ssl_opt=""

    # SSL-Prüfung: Bei self-signed Zertifikaten (Standard bei PVE) deaktivieren
    if [[ "$PVE_VERIFY_SSL" != "true" ]]; then
        ssl_opt="--insecure"
    fi

    # API-Token-Authentifizierung (PVE-Format: "PVEAPIToken=USER@REALM!TOKENID=SECRET")
    local auth_header="Authorization: PVEAPIToken=${PVE_TOKEN_ID}=${PVE_TOKEN_SECRET}"

    curl \
        --silent \
        --show-error \
        --fail \
        $ssl_opt \
        --request "$method" \
        --header "$auth_header" \
        --header "Content-Type: application/json" \
        "$@" \
        "${base_url}${api_path}"
}

# _pve_check_jq: Prüft ob jq installiert ist
_pve_check_jq() {
    if ! command -v jq &>/dev/null; then
        echo "FEHLER: jq ist nicht installiert — apt install -y jq" >&2
        return 1
    fi
}

# ─── 1. Cluster und Node-Status ──────────────────────────────────────────────

# pve_cluster_status: Zeigt Status aller Cluster-Nodes
pve_cluster_status() {
    _pve_check_jq || return 1
    _pve_curl GET "/cluster/status" | jq '.data[] | {name: .name, type: .type, online: .online, ip: .ip}'
}

# pve_node_status: Status eines einzelnen Nodes (CPU, RAM, Storage)
# Parameter: [node-name] (Standard: $PVE_NODE)
pve_node_status() {
    local node="${1:-$PVE_NODE}"
    _pve_check_jq || return 1
    _pve_curl GET "/nodes/${node}/status" | jq '{
        uptime: .data.uptime,
        cpu: (.data.cpu * 100 | round),
        ram_used_gb: (.data.memory.used / 1073741824 * 100 | round / 100),
        ram_total_gb: (.data.memory.total / 1073741824 * 100 | round / 100),
        kernel: .data.kversion
    }'
}

# pve_nodes_list: Liste aller Nodes im Cluster
pve_nodes_list() {
    _pve_check_jq || return 1
    _pve_curl GET "/nodes" | jq '.data[] | {node: .node, status: .status, cpu: (.cpu * 100 | round), ram_gb: (.maxmem / 1073741824 | round)}'
}

# ─── 2. VM-Verwaltung ────────────────────────────────────────────────────────

# pve_vm_list: Alle VMs auf einem Node auflisten
# Parameter: [node-name]
pve_vm_list() {
    local node="${1:-$PVE_NODE}"
    _pve_check_jq || return 1
    _pve_curl GET "/nodes/${node}/qemu" | \
        jq '.data | sort_by(.vmid) | .[] | {vmid: .vmid, name: .name, status: .status, cpu: .cpus, ram_mb: (.maxmem / 1048576 | round)}'
}

# pve_vm_status: Status einer spezifischen VM
# Parameter: vmid, [node-name]
pve_vm_status() {
    local vmid="$1"
    local node="${2:-$PVE_NODE}"
    _pve_check_jq || return 1
    _pve_curl GET "/nodes/${node}/qemu/${vmid}/status/current" | \
        jq '.data | {vmid: .vmid, name: .name, status: .status, uptime: .uptime, cpu: (.cpu * 100 | round), ram_mb: (.mem / 1048576 | round)}'
}

# pve_vm_start: VM starten
# Parameter: vmid, [node-name]
pve_vm_start() {
    local vmid="$1"
    local node="${2:-$PVE_NODE}"
    echo "Starte VM ${vmid} auf Node ${node}..."
    _pve_curl POST "/nodes/${node}/qemu/${vmid}/status/start" | jq '.data'
}

# pve_vm_stop: VM stoppen (ACPI Shutdown — wartet auf sauberes Herunterfahren)
# Parameter: vmid, [node-name]
pve_vm_stop() {
    local vmid="$1"
    local node="${2:-$PVE_NODE}"
    echo "Stoppe VM ${vmid} auf Node ${node} (ACPI Shutdown)..."
    _pve_curl POST "/nodes/${node}/qemu/${vmid}/status/shutdown" | jq '.data'
}

# ─── 3. LXC-Container-Verwaltung ─────────────────────────────────────────────

# pve_lxc_list: Alle LXC-Container auf einem Node auflisten
# Parameter: [node-name]
pve_lxc_list() {
    local node="${1:-$PVE_NODE}"
    _pve_check_jq || return 1
    _pve_curl GET "/nodes/${node}/lxc" | \
        jq '.data | sort_by(.vmid) | .[] | {vmid: .vmid, name: .name, status: .status, cpus: .cpus, ram_mb: (.maxmem / 1048576 | round)}'
}

# pve_lxc_status: Status eines LXC-Containers
# Parameter: ctid, [node-name]
pve_lxc_status() {
    local ctid="$1"
    local node="${2:-$PVE_NODE}"
    _pve_check_jq || return 1
    _pve_curl GET "/nodes/${node}/lxc/${ctid}/status/current" | \
        jq '.data | {vmid: .vmid, name: .name, status: .status, uptime: .uptime, cpu: (.cpu * 100 | round), ram_mb: (.mem / 1048576 | round)}'
}

# pve_lxc_start: LXC-Container starten
# Parameter: ctid, [node-name]
pve_lxc_start() {
    local ctid="$1"
    local node="${2:-$PVE_NODE}"
    echo "Starte Container ${ctid} auf Node ${node}..."
    _pve_curl POST "/nodes/${node}/lxc/${ctid}/status/start" | jq '.data'
}

# pve_lxc_stop: LXC-Container stoppen
# Parameter: ctid, [node-name]
pve_lxc_stop() {
    local ctid="$1"
    local node="${2:-$PVE_NODE}"
    echo "Stoppe Container ${ctid} auf Node ${node}..."
    _pve_curl POST "/nodes/${node}/lxc/${ctid}/status/shutdown" | jq '.data'
}

# ─── 4. Snapshots ────────────────────────────────────────────────────────────

# pve_snapshot_list: Snapshots einer VM/Container auflisten
# Parameter: vmid_oder_ctid, typ (qemu|lxc), [node-name]
pve_snapshot_list() {
    local vmid="$1"
    local typ="${2:-qemu}"
    local node="${3:-$PVE_NODE}"
    _pve_check_jq || return 1
    _pve_curl GET "/nodes/${node}/${typ}/${vmid}/snapshot" | \
        jq '.data[] | {name: .name, description: .description, snaptime: .snaptime}'
}

# pve_snapshot_create: Snapshot erstellen
# Parameter: vmid_oder_ctid, snapshot-name, beschreibung, typ (qemu|lxc), [node-name]
# ACHTUNG: Bei VMs mit RAM-State (vmstate=1) wird VM kurz eingefroren
pve_snapshot_create() {
    local vmid="$1"
    local snap_name="$2"
    local description="${3:-Automatischer Snapshot}"
    local typ="${4:-qemu}"
    local node="${5:-$PVE_NODE}"

    echo "Erstelle Snapshot '${snap_name}' für ${typ} ${vmid}..."
    _pve_curl POST "/nodes/${node}/${typ}/${vmid}/snapshot" \
        --data-urlencode "snapname=${snap_name}" \
        --data-urlencode "description=${description}" | jq '.data'
}

# pve_snapshot_rollback: Rollback zu einem Snapshot
# ⚠️  ACHTUNG — DESTRUKTIV: VM/Container wird auf Snapshot-Zustand zurückgesetzt!
# Parameter: vmid_oder_ctid, snapshot-name, typ (qemu|lxc), [node-name]
pve_snapshot_rollback() {
    local vmid="$1"
    local snap_name="$2"
    local typ="${3:-qemu}"
    local node="${4:-$PVE_NODE}"

    echo ""
    echo "⚠️  WARNUNG: Rollback setzt ${typ} ${vmid} auf Snapshot '${snap_name}' zurück!"
    echo "   Alle Änderungen seit dem Snapshot gehen verloren!"
    echo ""
    read -r -p "  Rollback durchführen? [j/N] " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[jJyY]$ ]]; then
        echo "Rollback abgebrochen."
        return 0
    fi

    echo "Führe Rollback durch..."
    _pve_curl POST "/nodes/${node}/${typ}/${vmid}/snapshot/${snap_name}/rollback" | jq '.data'
}

# ─── 5. Storage ──────────────────────────────────────────────────────────────

# pve_storage_list: Storage-Pools auflisten
# Parameter: [node-name]
pve_storage_list() {
    local node="${1:-$PVE_NODE}"
    _pve_check_jq || return 1
    _pve_curl GET "/nodes/${node}/storage" | \
        jq '.data[] | {storage: .storage, type: .type, total_gb: (.total / 1073741824 | round), used_gb: (.used / 1073741824 | round), avail_gb: (.avail / 1073741824 | round)}'
}

# pve_storage_content: Inhalte eines Storage-Pools anzeigen
# Parameter: storage-name, [node-name]
pve_storage_content() {
    local storage="$1"
    local node="${2:-$PVE_NODE}"
    _pve_check_jq || return 1
    _pve_curl GET "/nodes/${node}/storage/${storage}/content" | \
        jq '.data[] | {volid: .volid, size_gb: (.size / 1073741824 | round), format: .format}'
}

# ─── 6. Tasks (laufende und abgeschlossene Operationen) ───────────────────────

# pve_task_list: Laufende Tasks anzeigen
# Parameter: [node-name]
pve_task_list() {
    local node="${1:-$PVE_NODE}"
    _pve_check_jq || return 1
    _pve_curl GET "/nodes/${node}/tasks" | \
        jq '.data[] | {upid: .upid, type: .type, status: .status, user: .user}'
}

# pve_task_status: Status eines Tasks prüfen
# Parameter: UPID (Task-ID), [node-name]
pve_task_status() {
    local upid="$1"
    local node="${2:-$PVE_NODE}"
    _pve_check_jq || return 1
    # UPID muss URL-kodiert werden (enthält Sonderzeichen)
    local encoded_upid
    encoded_upid=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${upid}', safe=''))" 2>/dev/null || \
                   printf '%s' "$upid" | sed 's/:/\%3A/g; s/!/\%21/g')
    _pve_curl GET "/nodes/${node}/tasks/${encoded_upid}/status" | jq '.data | {status: .status, exitstatus: .exitstatus}'
}

# ─── 7. API-Verbindung testen ─────────────────────────────────────────────────

# pve_api_test: Testet die API-Verbindung und zeigt Version
pve_api_test() {
    echo "Teste Verbindung zu PVE ${PVE_HOST}:${PVE_PORT}..."
    local result
    if result=$(_pve_curl GET "/version" 2>&1); then
        echo "Verbindung erfolgreich!"
        echo "$result" | jq '.data | {version: .version, release: .release, repoid: .repoid}'
    else
        echo "Verbindung fehlgeschlagen: $result" >&2
        return 1
    fi
}
