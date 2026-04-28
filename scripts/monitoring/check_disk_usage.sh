#!/usr/bin/env bash
# =============================================================================
# DATEI:        scripts/monitoring/check_disk_usage.sh
# ZWECK:        Festplatten-Auslastung prüfen und bei Überschreitung warnen
# AUFRUFEN:     ./check_disk_usage.sh [warn-schwelle] [kritisch-schwelle]
# BEISPIEL:     ./check_disk_usage.sh 80 90
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

# ─── Schwellen ────────────────────────────────────────────────────────────────
readonly WARN_THRESHOLD="${1:-80}"
readonly CRIT_THRESHOLD="${2:-90}"

FAILURES=0
WARNINGS=0

echo ""
echo "=================================================================="
echo "  Festplatten-Check — $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Warn: ${WARN_THRESHOLD}% | Kritisch: ${CRIT_THRESHOLD}%"
echo "=================================================================="

log_section "Dateisystem-Auslastung"

while IFS= read -r line; do
    # Format: Quelle Größe Benutzt Verfügbar Prozent Mountpoint
    USAGE=$(echo "${line}" | awk '{print $5}' | tr -d '%')
    MOUNT=$(echo "${line}" | awk '{print $6}')
    SOURCE=$(echo "${line}" | awk '{print $1}')

    if [[ -z "${USAGE}" || "${USAGE}" == "Use%" ]]; then
        continue
    fi

    if [[ "${USAGE}" -ge "${CRIT_THRESHOLD}" ]]; then
        echo -e "${RED}  [KRIT]${NC}  ${USAGE}% — ${MOUNT} (${SOURCE})"
        ((FAILURES++))
    elif [[ "${USAGE}" -ge "${WARN_THRESHOLD}" ]]; then
        echo -e "${YELLOW}  [WARN]${NC}  ${USAGE}% — ${MOUNT} (${SOURCE})"
        ((WARNINGS++))
    else
        echo -e "${GREEN}  [OK]${NC}    ${USAGE}% — ${MOUNT} (${SOURCE})"
    fi
done < <(df -h --output=source,size,used,avail,pcent,target | grep -v "tmpfs\|udev\|Filesystem")

# ─── Docker-Volumes ───────────────────────────────────────────────────────────
log_section "Docker-Speicher"
if command -v docker &>/dev/null; then
    docker system df 2>/dev/null | sed 's/^/  /'
else
    echo "  Docker nicht verfügbar"
fi

# ─── Größte Verzeichnisse ─────────────────────────────────────────────────────
log_section "Größte Verzeichnisse (Top 10)"
du -sh /opt/*/data 2>/dev/null | sort -rh | head -10 | sed 's/^/  /' || \
    echo "  Keine /opt/*/data Verzeichnisse gefunden"

# ─── Ergebnis ─────────────────────────────────────────────────────────────────
log_section "Zusammenfassung"
if [[ "${FAILURES}" -eq 0 && "${WARNINGS}" -eq 0 ]]; then
    echo -e "${GREEN}  Alle Dateisysteme im grünen Bereich.${NC}"
    exit 0
elif [[ "${FAILURES}" -gt 0 ]]; then
    echo -e "${RED}  ${FAILURES} kritische Auslastungen — sofort handeln!${NC}"
    exit 2
else
    echo -e "${YELLOW}  ${WARNINGS} Warnungen — bald Speicherplatz freigeben.${NC}"
    exit 1
fi
