#!/usr/bin/env bash
# =============================================================================
# DATEI:        05_dns_preflight.sh
# ZWECK:        Prüft ob alle benötigten DNS-Records gesetzt sind, BEVOR der
#               Matrix/Nextcloud-Deploy beginnt. Verhindert Fehlversuche bei
#               Let's Encrypt (Rate-Limit: 5 Fehlschläge/Stunde/Domain).
# AUFRUFEN:     bash scripts/setup/05_dns_preflight.sh
# VORAUSSETZUNGEN:
#   - dig (apt install -y dnsutils)
#   - .env-Datei mit MATRIX_DOMAIN und NEXTCLOUD_DOMAIN
# SICHERHEIT:
#   - Backup-Verhalten: keines (nur Lese-Operationen)
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
log_fail() { echo -e "${RED}  ✗${NC} $*" >&2; FAILED=$((FAILED + 1)); }
log_warn() { echo -e "${YELLOW}  ⚠${NC} $*"; WARNINGS=$((WARNINGS + 1)); }
log_info() { echo -e "${BLUE}  i${NC} $*"; }

FAILED=0
WARNINGS=0

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo ""
echo "============================================================"
echo "  DNS-Preflight-Check"
echo "  Prüft DNS-Records für Matrix + Nextcloud"
echo "============================================================"
echo ""

# ─── Voraussetzungen ─────────────────────────────────────────────────────────
echo "[ Voraussetzungen ]"

if ! command -v dig &>/dev/null; then
    log_fail "dig nicht installiert — apt install -y dnsutils"
    exit 1
fi
log_ok "dig: $(dig -v 2>&1 | head -1)"

# .env laden
if [ -f "$REPO_ROOT/.env" ]; then
    # shellcheck disable=SC1091
    set -a; source "$REPO_ROOT/.env"; set +a
    log_ok ".env geladen"
else
    log_warn ".env nicht gefunden — manuelle Eingabe erforderlich"
fi

# Domains entweder aus .env oder interaktiv
if [ -z "${MATRIX_DOMAIN:-}" ] || [ "${MATRIX_DOMAIN}" = "<DEINE_DOMAIN>" ]; then
    read -r -p "  Matrix-Domain (z.B. example.com): " MATRIX_DOMAIN
fi

if [ -z "${NEXTCLOUD_DOMAIN:-}" ] || [[ "${NEXTCLOUD_DOMAIN}" == *"<"* ]]; then
    read -r -p "  Nextcloud-Domain (z.B. cloud.example.com): " NEXTCLOUD_DOMAIN
fi

# Erwartete Server-IP (für Vergleich)
EXPECTED_IP="${EXPECTED_IP:-}"
if [ -z "$EXPECTED_IP" ]; then
    read -r -p "  Erwartete Server-IPv4 (z.B. 203.0.113.10): " EXPECTED_IP
fi

echo ""
log_info "Matrix Domain:    $MATRIX_DOMAIN"
log_info "Nextcloud Domain: $NEXTCLOUD_DOMAIN"
log_info "Erwartete IP:     $EXPECTED_IP"
echo ""

# ─── DNS-Check-Funktion ─────────────────────────────────────────────────────
check_a_record() {
    local name="$1"
    local label="$2"

    local resolved
    resolved=$(dig +short "$name" A | head -1)

    if [ -z "$resolved" ]; then
        log_fail "$label ($name): KEIN A-Record gefunden"
        log_info "  Setze: A-Record für $name → $EXPECTED_IP"
    elif [ "$resolved" = "$EXPECTED_IP" ]; then
        log_ok "$label ($name): $resolved ✓"
    else
        log_warn "$label ($name): $resolved (erwartet: $EXPECTED_IP)"
        log_info "  DNS-Cache? Nochmal mit: dig +trace $name"
    fi
}

check_aaaa_record() {
    local name="$1"
    local label="$2"
    local resolved
    resolved=$(dig +short "$name" AAAA | head -1)
    if [ -n "$resolved" ]; then
        log_ok "$label IPv6 ($name): $resolved (optional)"
    else
        log_info "$label IPv6 ($name): kein AAAA-Record (OK falls IPv4-only geplant)"
    fi
}

# ─── Matrix-Records prüfen ──────────────────────────────────────────────────
echo "[ Matrix DNS ]"
check_a_record "matrix.${MATRIX_DOMAIN}" "Matrix Subdomain"
check_aaaa_record "matrix.${MATRIX_DOMAIN}" "Matrix Subdomain"

# Apex-Domain (für .well-known/matrix/server)
check_a_record "${MATRIX_DOMAIN}" "Matrix Apex (für .well-known)"

# Federation TLS — SRV-Record optional, da wir .well-known nutzen
SRV_RESULT=$(dig +short _matrix._tcp."${MATRIX_DOMAIN}" SRV)
if [ -n "$SRV_RESULT" ]; then
    log_ok "SRV _matrix._tcp.${MATRIX_DOMAIN}: $SRV_RESULT"
else
    log_info "SRV _matrix._tcp.${MATRIX_DOMAIN}: nicht gesetzt (OK, .well-known wird benutzt)"
fi

echo ""

# ─── Nextcloud-Records prüfen ──────────────────────────────────────────────
echo "[ Nextcloud DNS ]"
check_a_record "${NEXTCLOUD_DOMAIN}" "Nextcloud Domain"
check_aaaa_record "${NEXTCLOUD_DOMAIN}" "Nextcloud Domain"

echo ""

# ─── HTTP/HTTPS-Erreichbarkeit ─────────────────────────────────────────────
echo "[ Erreichbarkeit von außen ]"

check_http() {
    local url="$1"
    local label="$2"
    if curl -fsSk --max-time 5 -o /dev/null -w "%{http_code}\n" "$url" 2>/dev/null | grep -qE "^(200|301|302|404)"; then
        log_ok "$label: erreichbar"
    else
        log_warn "$label: nicht erreichbar (Server läuft noch nicht? Firewall?)"
    fi
}

# Vor Deploy: Server hat noch keinen Webserver — diese Checks sind informativ
log_info "Diese Checks zeigen ob bereits ein Webserver läuft:"
check_http "http://matrix.${MATRIX_DOMAIN}/" "HTTP matrix.${MATRIX_DOMAIN}"
check_http "http://${NEXTCLOUD_DOMAIN}/" "HTTP ${NEXTCLOUD_DOMAIN}"

echo ""

# ─── Ergebnis ───────────────────────────────────────────────────────────────
echo "============================================================"
if [ "$FAILED" -eq 0 ]; then
    echo -e "${GREEN}  DNS-Setup OK!${NC} (Warnungen: $WARNINGS)"
    echo ""
    echo "  Du kannst jetzt mit dem Deploy beginnen:"
    echo "    ansible-playbook ansible/playbooks/site.yml --check --diff"
else
    echo -e "${RED}  $FAILED Fehler — DNS-Records noch nicht (vollständig) gesetzt!${NC}"
    echo ""
    echo "  Setze die fehlenden A-Records bei deinem DNS-Provider:"
    echo "    matrix.${MATRIX_DOMAIN}  → $EXPECTED_IP"
    echo "    ${MATRIX_DOMAIN}         → $EXPECTED_IP   (für Federation)"
    echo "    ${NEXTCLOUD_DOMAIN}      → $EXPECTED_IP"
    echo ""
    echo "  TTL niedrig setzen (300s) bis alles funktioniert."
    echo "  Cache prüfen: dig +trace matrix.${MATRIX_DOMAIN}"
    exit 1
fi
echo "============================================================"
echo ""
