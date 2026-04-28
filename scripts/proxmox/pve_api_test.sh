#!/usr/bin/env bash
# =============================================================================
# DATEI:        pve_api_test.sh
# ZWECK:        Testet die PVE und PBS API-Verbindungen und gibt eine
#               vollständige Diagnose aus. Gut als erster Test nach der
#               API-Token-Konfiguration.
# AUFRUFEN:     bash scripts/proxmox/pve_api_test.sh
# VORAUSSETZUNGEN:
#   - .env Datei mit PVE_* und PBS_* Variablen
#   - curl und jq installiert
# SICHERHEIT:
#   - Backup-Verhalten: keines (nur Lesezugriff)
#   - Destruktiv: NEIN
# VERSION:      1.0.0 | Stand: 2026-04
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_ok()   { echo -e "${GREEN}  ✓${NC} $*"; }
log_fail() { echo -e "${RED}  ✗${NC} $*" >&2; }
log_warn() { echo -e "${YELLOW}  ⚠${NC} $*"; }
log_info() { echo -e "${BLUE}  i${NC} $*"; }

FAILED=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo ""
echo "============================================================"
echo "  Proxmox API Verbindungs-Test"
echo "============================================================"
echo ""

# ─── .env laden ──────────────────────────────────────────────────────────────
echo "[ Konfiguration ]"

if [ -f "$REPO_ROOT/.env" ]; then
    # shellcheck disable=SC1091
    set -a; source "$REPO_ROOT/.env"; set +a
    log_ok ".env geladen: $REPO_ROOT/.env"
else
    log_fail ".env nicht gefunden!"
    log_info "Erstellen: cp .env.example .env && nano .env"
    exit 1
fi

echo ""

# ─── Voraussetzungen ─────────────────────────────────────────────────────────
echo "[ Tools ]"

if command -v curl &>/dev/null; then
    log_ok "curl: $(curl --version | head -1)"
else
    log_fail "curl: nicht installiert"
    FAILED=$((FAILED + 1))
fi

if command -v jq &>/dev/null; then
    log_ok "jq: $(jq --version)"
else
    log_fail "jq: nicht installiert — apt install -y jq"
    FAILED=$((FAILED + 1))
fi

if [ "$FAILED" -gt 0 ]; then
    log_fail "Fehlende Tools — bitte installieren und erneut ausführen"
    exit 1
fi

echo ""

# ─── PVE API-Bibliothek laden ─────────────────────────────────────────────────
# shellcheck source=../../proxmox-api/lib/pve_api.sh
# shellcheck disable=SC1091
source "$REPO_ROOT/proxmox-api/lib/pve_api.sh"

# shellcheck source=../../proxmox-api/lib/pbs_api.sh
# shellcheck disable=SC1091
source "$REPO_ROOT/proxmox-api/lib/pbs_api.sh"

# ─── PVE-Verbindung testen ───────────────────────────────────────────────────
echo "[ Proxmox VE API ]"
log_info "Host: ${PVE_HOST:-nicht gesetzt}:${PVE_PORT:-8006}"

if [ -z "${PVE_HOST:-}" ]; then
    log_fail "PVE_HOST nicht gesetzt — .env prüfen"
    FAILED=$((FAILED + 1))
elif [ -z "${PVE_TOKEN_ID:-}" ] || [ -z "${PVE_TOKEN_SECRET:-}" ]; then
    log_fail "PVE_TOKEN_ID oder PVE_TOKEN_SECRET nicht gesetzt — .env prüfen"
    FAILED=$((FAILED + 1))
else
    # Verbindungstest
    if pve_api_test 2>/dev/null; then
        log_ok "PVE API: Verbindung erfolgreich"
    else
        log_fail "PVE API: Verbindung fehlgeschlagen"
        log_info "Prüfen: Host erreichbar? Token korrekt? SSL-Zertifikat (PVE_VERIFY_SSL=false)?"
        FAILED=$((FAILED + 1))
    fi
fi

echo ""

# ─── PBS-Verbindung testen ───────────────────────────────────────────────────
echo "[ Proxmox Backup Server API ]"
log_info "Host: ${PBS_HOST:-nicht gesetzt}:${PBS_PORT:-8007}"

if [ -z "${PBS_HOST:-}" ]; then
    log_warn "PBS_HOST nicht gesetzt — PBS-Test übersprungen"
elif [ -z "${PBS_TOKEN_ID:-}" ] || [ -z "${PBS_TOKEN_SECRET:-}" ]; then
    log_warn "PBS_TOKEN_ID oder PBS_TOKEN_SECRET nicht gesetzt — PBS-Test übersprungen"
else
    if pbs_api_test 2>/dev/null; then
        log_ok "PBS API: Verbindung erfolgreich"
    else
        log_fail "PBS API: Verbindung fehlgeschlagen"
        log_info "Prüfen: Host erreichbar? PBS-Token korrekt? SSL (PBS_VERIFY_SSL=false)?"
        FAILED=$((FAILED + 1))
    fi
fi

echo ""

# ─── Ergebnis ────────────────────────────────────────────────────────────────
echo "============================================================"
if [ "$FAILED" -eq 0 ]; then
    echo -e "${GREEN}  Alle API-Verbindungen erfolgreich!${NC}"
    echo ""
    echo "  Nächste Schritte:"
    echo "  - VMs auflisten:    bash proxmox-api/examples/list_vms.sh"
    echo "  - Backups prüfen:   bash proxmox-api/examples/pbs_backup_verify.sh"
else
    echo -e "${RED}  ${FAILED} Verbindung(en) fehlgeschlagen!${NC}"
    echo ""
    echo "  Häufige Ursachen:"
    echo "  1. Falsche Host-IP oder Port in .env"
    echo "  2. API-Token nicht erstellt (Proxmox GUI: Datacenter → API Tokens)"
    echo "  3. Self-signed SSL: PVE_VERIFY_SSL=false setzen"
    echo "  4. Firewall blockiert Port 8006/8007"
    echo "  5. API-Token hat keine ausreichenden Berechtigungen"
    echo ""
    echo "  Token erstellen (PVE GUI):"
    echo "    Datacenter → Permissions → API Tokens → Add"
    echo "    User: ansible@pve, Token ID: deploy, Privilege Separation: yes"
    exit 1
fi
echo "============================================================"
echo ""
