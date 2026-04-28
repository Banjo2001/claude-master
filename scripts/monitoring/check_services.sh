#!/usr/bin/env bash
# =============================================================================
# DATEI:        scripts/monitoring/check_services.sh
# ZWECK:        Alle wichtigen Dienste auf Verfügbarkeit prüfen
# AUFRUFEN:     ./check_services.sh
# VORAUSSETZUNGEN:
#   - curl, docker, systemctl
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

log_ok()      { echo -e "${GREEN}  [OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}  [WARN]${NC}  $*"; }
log_fail()    { echo -e "${RED}  [FAIL]${NC}  $*"; }
log_section() { echo -e "\n${CYAN}━━━ $* ━━━${NC}"; }

FAILURES=0
WARNINGS=0

check_systemd() {
    local service="$1"
    if systemctl is-active --quiet "${service}" 2>/dev/null; then
        log_ok "systemd: ${service}"
    else
        log_fail "systemd: ${service} läuft NICHT"
        ((FAILURES++))
    fi
}

check_docker_container() {
    local name="$1"
    if docker inspect --format='{{.State.Running}}' "${name}" 2>/dev/null | grep -q "true"; then
        log_ok "Docker: ${name}"
    else
        log_warn "Docker: ${name} nicht gefunden oder gestoppt"
        ((WARNINGS++))
    fi
}

check_http() {
    local url="$1"
    local label="$2"
    if curl -fsSk --max-time 10 "${url}" &>/dev/null; then
        log_ok "HTTP: ${label} (${url})"
    else
        log_fail "HTTP: ${label} nicht erreichbar (${url})"
        ((FAILURES++))
    fi
}

echo ""
echo "=================================================================="
echo "  Dienste-Check — $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Host: $(hostname -f)"
echo "=================================================================="

# ─── Systemdienste ────────────────────────────────────────────────────────────
log_section "System-Dienste"
check_systemd "docker"
check_systemd "ufw"
check_systemd "fail2ban"
check_systemd "sshd"

# ─── Matrix-Stack ─────────────────────────────────────────────────────────────
log_section "Matrix Synapse Stack"
check_docker_container "matrix-synapse-1"
check_docker_container "matrix-postgres-1"
check_docker_container "matrix-redis-1"
check_docker_container "matrix-nginx-1"
check_docker_container "matrix-coturn-1"

# Synapse Health-Endpoint
MATRIX_DOMAIN="${MATRIX_DOMAIN:-matrix.example.com}"
check_http "https://${MATRIX_DOMAIN}/_matrix/client/versions" "Matrix Client API"
check_http "https://${MATRIX_DOMAIN}/.well-known/matrix/server" "Matrix Federation"

# ─── Nextcloud-Stack ──────────────────────────────────────────────────────────
log_section "Nextcloud AIO"
check_docker_container "nextcloud-aio-mastercontainer"

NEXTCLOUD_DOMAIN="${NEXTCLOUD_DOMAIN:-cloud.example.com}"
check_http "https://${NEXTCLOUD_DOMAIN}/status.php" "Nextcloud Status"

# ─── Ergebnis ─────────────────────────────────────────────────────────────────
log_section "Zusammenfassung"
echo ""
if [[ "${FAILURES}" -eq 0 && "${WARNINGS}" -eq 0 ]]; then
    echo -e "${GREEN}  Alle Dienste laufen korrekt.${NC}"
    exit 0
elif [[ "${FAILURES}" -eq 0 ]]; then
    echo -e "${YELLOW}  ${WARNINGS} Warnungen — bitte prüfen.${NC}"
    exit 0
else
    echo -e "${RED}  ${FAILURES} Fehler und ${WARNINGS} Warnungen!${NC}"
    exit 1
fi
