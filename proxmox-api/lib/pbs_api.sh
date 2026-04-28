#!/usr/bin/env bash
# =============================================================================
# DATEI:        pbs_api.sh
# ZWECK:        Shell-Bibliothek für Proxmox Backup Server REST-API (v4)
#               Stellt Funktionen für Backup-Verwaltung, Verifizierung
#               und Datastore-Übersicht bereit.
# AUFRUFEN:     source proxmox-api/lib/pbs_api.sh
# VORAUSSETZUNGEN:
#   - curl installiert
#   - jq installiert (JSON-Verarbeitung)
#   - Umgebungsvariablen gesetzt (s.u.) oder .env geladen
# UMGEBUNGSVARIABLEN:
#   PBS_HOST          — Hostname/IP des PBS-Servers
#   PBS_PORT          — API-Port (Standard: 8007)
#   PBS_TOKEN_ID      — API-Token ID (Format: USER@REALM!TOKENID)
#   PBS_TOKEN_SECRET  — API-Token Secret (UUID)
#   PBS_DATASTORE     — Standard-Datastore-Name
#   PBS_VERIFY_SSL    — SSL-Zertifikat prüfen: true/false (Standard: true)
# SICHERHEIT:
#   - Backup-Verhalten: keines (nur Lese-/API-Operationen)
#   - Destruktiv: Nur pbs_backup_forget() ist destruktiv
#   - Rollback: Vor Garbage-Collect immer Snapshot prüfen
# VERSION:      1.0.0 | Stand: 2026-04
# =============================================================================

# Schutz gegen Mehrfach-Laden
[[ -n "${_PBS_API_LOADED:-}" ]] && return 0
readonly _PBS_API_LOADED=1

# ─── Standard-Werte ──────────────────────────────────────────────────────────
PBS_PORT="${PBS_PORT:-8007}"
PBS_VERIFY_SSL="${PBS_VERIFY_SSL:-true}"

# ─── Interne Hilfsfunktionen ─────────────────────────────────────────────────

# _pbs_curl: Führt einen API-Aufruf gegen PBS aus
# Parameter: HTTP-Methode, API-Pfad, [optionale curl-Argumente]
_pbs_curl() {
    local method="$1"
    local api_path="$2"
    shift 2

    if [[ -z "${PBS_HOST:-}" ]]; then
        echo "FEHLER: PBS_HOST ist nicht gesetzt" >&2
        return 1
    fi
    if [[ -z "${PBS_TOKEN_ID:-}" ]] || [[ -z "${PBS_TOKEN_SECRET:-}" ]]; then
        echo "FEHLER: PBS_TOKEN_ID oder PBS_TOKEN_SECRET nicht gesetzt" >&2
        return 1
    fi

    local base_url="https://${PBS_HOST}:${PBS_PORT}/api2/json"
    local ssl_opt=""

    if [[ "$PBS_VERIFY_SSL" != "true" ]]; then
        ssl_opt="--insecure"
    fi

    # PBS nutzt dasselbe Token-Format wie PVE
    local auth_header="Authorization: PBSAPIToken=${PBS_TOKEN_ID}=${PBS_TOKEN_SECRET}"

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

# _pbs_check_jq: Prüft ob jq installiert ist
_pbs_check_jq() {
    if ! command -v jq &>/dev/null; then
        echo "FEHLER: jq ist nicht installiert — apt install -y jq" >&2
        return 1
    fi
}

# ─── 1. Server-Status ────────────────────────────────────────────────────────

# pbs_api_test: Testet die API-Verbindung und zeigt Version
pbs_api_test() {
    echo "Teste Verbindung zu PBS ${PBS_HOST}:${PBS_PORT}..."
    local result
    if result=$(_pbs_curl GET "/version" 2>&1); then
        echo "Verbindung erfolgreich!"
        echo "$result" | jq '.data | {version: .version, release: .release}'
    else
        echo "Verbindung fehlgeschlagen: $result" >&2
        return 1
    fi
}

# pbs_node_status: Ressourcen-Auslastung des PBS-Servers
pbs_node_status() {
    _pbs_check_jq || return 1
    _pbs_curl GET "/nodes/localhost/status" | jq '{
        uptime: .data.uptime,
        cpu: (.data.cpu * 100 | round),
        ram_used_gb: (.data.memory.used / 1073741824 * 100 | round / 100),
        ram_total_gb: (.data.memory.total / 1073741824 * 100 | round / 100)
    }'
}

# ─── 2. Datastore-Verwaltung ─────────────────────────────────────────────────

# pbs_datastore_list: Alle Datastores auflisten
pbs_datastore_list() {
    _pbs_check_jq || return 1
    _pbs_curl GET "/admin/datastore" | \
        jq '.data[] | {store: .store, path: .path, used_gb: (.used / 1073741824 | round), avail_gb: (.avail / 1073741824 | round), total_gb: (.total / 1073741824 | round)}'
}

# pbs_datastore_status: Status eines spezifischen Datastores
# Parameter: [datastore-name] (Standard: $PBS_DATASTORE)
pbs_datastore_status() {
    local store="${1:-${PBS_DATASTORE:-backup-store}}"
    _pbs_check_jq || return 1
    _pbs_curl GET "/admin/datastore/${store}/status" | \
        jq '.data | {store: .store, total_gb: (.total / 1073741824 | round), used_gb: (.used / 1073741824 | round), avail_gb: (.avail / 1073741824 | round), dedup_factor: .dedup}'
}

# ─── 3. Backup-Gruppen und Snapshots ─────────────────────────────────────────

# pbs_backup_list: Alle Backup-Gruppen eines Datastores auflisten
# Parameter: [datastore-name]
pbs_backup_list() {
    local store="${1:-${PBS_DATASTORE:-backup-store}}"
    _pbs_check_jq || return 1
    _pbs_curl GET "/admin/datastore/${store}/groups" | \
        jq '.data[] | {type: ."backup-type", id: ."backup-id", last_backup: ."last-backup", backup_count: ."backup-count"}'
}

# pbs_snapshot_list: Alle Snapshots einer Backup-Gruppe
# Parameter: backup-typ (vm|ct), backup-id (VMID), [datastore-name]
pbs_snapshot_list() {
    local backup_type="$1"
    local backup_id="$2"
    local store="${3:-${PBS_DATASTORE:-backup-store}}"
    _pbs_check_jq || return 1
    _pbs_curl GET "/admin/datastore/${store}/snapshots?backup-type=${backup_type}&backup-id=${backup_id}" | \
        jq '.data[] | {"backup-time": ."backup-time", size: (.size / 1073741824 * 100 | round / 100), verified: .verification}'
}

# pbs_snapshot_latest: Neuesten Snapshot einer VM/CT finden
# Parameter: backup-typ (vm|ct), backup-id (VMID), [datastore-name]
pbs_snapshot_latest() {
    local backup_type="$1"
    local backup_id="$2"
    local store="${3:-${PBS_DATASTORE:-backup-store}}"
    _pbs_check_jq || return 1
    _pbs_curl GET "/admin/datastore/${store}/snapshots?backup-type=${backup_type}&backup-id=${backup_id}" | \
        jq '.data | sort_by(."backup-time") | last | {"backup-time": ."backup-time", size_gb: (.size / 1073741824 * 100 | round / 100)}'
}

# ─── 4. Backup-Verifizierung ──────────────────────────────────────────────────

# pbs_verify_all: Alle Backups in einem Datastore verifizieren
# Parameter: [datastore-name]
# HINWEIS: Startet einen asynchronen Task — prüfe Ergebnis mit pbs_task_list
pbs_verify_all() {
    local store="${1:-${PBS_DATASTORE:-backup-store}}"
    echo "Starte Verifikation aller Backups in Datastore '${store}'..."
    echo "HINWEIS: Dies ist ein asynchroner Task — Ergebnis mit pbs_task_list prüfen"
    _pbs_curl POST "/admin/datastore/${store}/verify" | jq '.data'
}

# pbs_verify_snapshot: Einzelnen Snapshot verifizieren
# Parameter: backup-typ, backup-id, backup-time (Unix-Timestamp), [datastore-name]
pbs_verify_snapshot() {
    local backup_type="$1"
    local backup_id="$2"
    local backup_time="$3"
    local store="${4:-${PBS_DATASTORE:-backup-store}}"

    echo "Verifiziere Snapshot: ${backup_type}/${backup_id}/${backup_time} in '${store}'..."
    _pbs_curl POST "/admin/datastore/${store}/verify" \
        --data "{\"backup-type\":\"${backup_type}\",\"backup-id\":\"${backup_id}\",\"backup-time\":${backup_time}}" | \
        jq '.data'
}

# ─── 5. Backup-Vergessen (Prune) ─────────────────────────────────────────────

# pbs_prune_backup: Alte Backups nach Aufbewahrungsregeln löschen
# ⚠️  ACHTUNG — DESTRUKTIV: Löscht Backups unwiderruflich!
# Parameter: backup-typ, backup-id, keep-last (Anzahl), [datastore-name]
# Beispiel: pbs_prune_backup vm 100 7   — behält letzte 7 Backups von VM 100
pbs_prune_backup() {
    local backup_type="$1"
    local backup_id="$2"
    local keep_last="${3:-7}"
    local store="${4:-${PBS_DATASTORE:-backup-store}}"

    echo ""
    echo "⚠️  WARNUNG: Prune löscht Backups von ${backup_type}/${backup_id}!"
    echo "   Behalte nur die letzten ${keep_last} Backups."
    echo "   Ältere Backups werden UNWIDERRUFLICH gelöscht!"
    echo ""
    read -r -p "  Prune durchführen? [j/N] " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[jJyY]$ ]]; then
        echo "Prune abgebrochen."
        return 0
    fi

    echo "Führe Prune durch..."
    _pbs_curl POST "/admin/datastore/${store}/prune" \
        --data "{\"backup-type\":\"${backup_type}\",\"backup-id\":\"${backup_id}\",\"keep-last\":${keep_last}}" | \
        jq '.data'
}

# ─── 6. Tasks ────────────────────────────────────────────────────────────────

# pbs_task_list: Aktive und kürzlich abgeschlossene Tasks
pbs_task_list() {
    _pbs_check_jq || return 1
    _pbs_curl GET "/nodes/localhost/tasks?limit=20" | \
        jq '.data[] | {upid: .upid, type: .type, status: .status, user: .user}'
}

# pbs_task_log: Log eines Tasks anzeigen
# Parameter: UPID (Task-ID)
pbs_task_log() {
    local upid="$1"
    _pbs_check_jq || return 1
    local encoded_upid
    encoded_upid=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${upid}', safe=''))" 2>/dev/null || \
                   printf '%s' "$upid" | sed 's/:/\%3A/g; s/!/\%21/g')
    _pbs_curl GET "/nodes/localhost/tasks/${encoded_upid}/log" | jq -r '.data[].t'
}
