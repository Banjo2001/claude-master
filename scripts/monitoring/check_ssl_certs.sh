#!/usr/bin/env bash
# =============================================================================
# DATEI:        scripts/monitoring/check_ssl_certs.sh
# ZWECK:        SSL-Zertifikate auf Ablaufdatum prüfen
# AUFRUFEN:     ./check_ssl_certs.sh [warn-tage]
# BEISPIEL:     ./check_ssl_certs.sh 30   (warnen wenn < 30 Tage)
# SICHERHEIT:
#   - Destruktiv: NEIN (nur Lesezugriff)
# VERSION:      1.0.0 | Stand: 2026-04
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

log_section() { echo -e "\n${CYAN}━━━ $* ━━━${NC}"; }

readonly WARN_DAYS="${1:-30}"
FAILURES=0
WARNINGS=0

# Prüft ein Zertifikat per HTTPS-Verbindung
check_cert_remote() {
    local domain="$1"
    local port="${2:-443}"
    local label="${3:-${domain}}"

    local expiry_raw
    expiry_raw=$(echo \
        | timeout 10 openssl s_client -connect "${domain}:${port}" -servername "${domain}" 2>/dev/null \
        | openssl x509 -noout -enddate 2>/dev/null \
        | cut -d= -f2 || echo "")

    if [[ -z "${expiry_raw}" ]]; then
        echo -e "${YELLOW}  [SKIP]${NC}  ${label} — nicht erreichbar oder kein Zertifikat"
        ((WARNINGS++))
        return
    fi

    local expiry_epoch
    expiry_epoch=$(date -d "${expiry_raw}" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "${expiry_raw}" +%s 2>/dev/null || echo 0)
    local now_epoch
    now_epoch=$(date +%s)
    local days_left=$(( (expiry_epoch - now_epoch) / 86400 ))

    if [[ "${days_left}" -le 0 ]]; then
        echo -e "${RED}  [ABGL]${NC}  ${label} — Zertifikat ABGELAUFEN seit $((days_left * -1)) Tagen!"
        ((FAILURES++))
    elif [[ "${days_left}" -le "${WARN_DAYS}" ]]; then
        echo -e "${YELLOW}  [WARN]${NC}  ${label} — läuft in ${days_left} Tagen ab ($(date -d "${expiry_raw}" '+%Y-%m-%d' 2>/dev/null || echo "${expiry_raw}"))"
        ((WARNINGS++))
    else
        echo -e "${GREEN}  [OK]${NC}    ${label} — gültig für ${days_left} Tage"
    fi
}

# Prüft ein lokales Zertifikat
check_cert_file() {
    local certfile="$1"
    local label="${2:-${certfile}}"

    if [[ ! -f "${certfile}" ]]; then
        echo -e "${YELLOW}  [SKIP]${NC}  ${label} — Datei nicht gefunden"
        return
    fi

    local expiry_raw
    expiry_raw=$(openssl x509 -noout -enddate -in "${certfile}" 2>/dev/null | cut -d= -f2 || echo "")
    if [[ -z "${expiry_raw}" ]]; then
        echo -e "${RED}  [FEHLER]${NC} ${label} — Zertifikat konnte nicht gelesen werden"
        ((FAILURES++))
        return
    fi

    local expiry_epoch
    expiry_epoch=$(date -d "${expiry_raw}" +%s 2>/dev/null || echo 0)
    local days_left=$(( (expiry_epoch - $(date +%s)) / 86400 ))

    if [[ "${days_left}" -le 0 ]]; then
        echo -e "${RED}  [ABGL]${NC}  ${label} — ABGELAUFEN!"
        ((FAILURES++))
    elif [[ "${days_left}" -le "${WARN_DAYS}" ]]; then
        echo -e "${YELLOW}  [WARN]${NC}  ${label} — läuft in ${days_left} Tagen ab"
        ((WARNINGS++))
    else
        echo -e "${GREEN}  [OK]${NC}    ${label} — gültig für ${days_left} Tage"
    fi
}

echo ""
echo "=================================================================="
echo "  SSL-Zertifikat-Check — $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Warnen wenn < ${WARN_DAYS} Tage verbleiben"
echo "=================================================================="

# ─── Remote-Zertifikate prüfen ────────────────────────────────────────────────
log_section "Remote-Zertifikate (HTTPS)"

# ANPASSEN: Domains aus Umgebung oder Platzhalter
MATRIX_DOMAIN="${MATRIX_DOMAIN:-matrix.example.com}"
NEXTCLOUD_DOMAIN="${NEXTCLOUD_DOMAIN:-cloud.example.com}"

check_cert_remote "${MATRIX_DOMAIN}" 443 "Matrix (${MATRIX_DOMAIN})"
check_cert_remote "${NEXTCLOUD_DOMAIN}" 8443 "Nextcloud (${NEXTCLOUD_DOMAIN}:8443)"

# ─── Lokale Zertifikate ───────────────────────────────────────────────────────
log_section "Lokale Zertifikate (Let's Encrypt)"

# Typische Let's Encrypt Pfade
for CERT_PATH in /etc/letsencrypt/live/*/fullchain.pem /opt/matrix/certs/live/*/fullchain.pem; do
    if [[ -f "${CERT_PATH}" ]]; then
        DOMAIN_NAME=$(echo "${CERT_PATH}" | grep -oP '(?<=live/)[^/]+')
        check_cert_file "${CERT_PATH}" "Let's Encrypt: ${DOMAIN_NAME}"
    fi
done

# ─── Ergebnis ─────────────────────────────────────────────────────────────────
log_section "Zusammenfassung"
if [[ "${FAILURES}" -eq 0 && "${WARNINGS}" -eq 0 ]]; then
    echo -e "${GREEN}  Alle Zertifikate in Ordnung.${NC}"
    exit 0
elif [[ "${FAILURES}" -gt 0 ]]; then
    echo -e "${RED}  ${FAILURES} abgelaufene/fehlerhafte Zertifikate — sofort handeln!${NC}"
    exit 2
else
    echo -e "${YELLOW}  ${WARNINGS} Zertifikate laufen bald ab — erneuern!${NC}"
    exit 1
fi
