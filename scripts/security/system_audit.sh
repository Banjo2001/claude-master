#!/usr/bin/env bash
# =============================================================================
# DATEI:        scripts/security/system_audit.sh
# ZWECK:        Sicherheits-Audit des Systems — Überblick über Systemzustand
# AUFRUFEN:     sudo ./system_audit.sh
# VORAUSSETZUNGEN:
#   - Debian/Ubuntu
# SICHERHEIT:
#   - Backup-Verhalten: NEIN (nur Lesezugriff)
#   - Destruktiv: NEIN
#   - Rollback: nicht erforderlich
# VERSION:      1.0.0 | Stand: 2026-04
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

log_ok()      { echo -e "${GREEN}  [OK]${NC}  $*"; }
log_warn()    { echo -e "${YELLOW}  [WARN]${NC} $*"; }
log_fail()    { echo -e "${RED}  [FAIL]${NC} $*"; }
log_info()    { echo -e "  [INFO] $*"; }
log_section() { echo -e "\n${CYAN}━━━ $* ━━━${NC}"; }

WARNINGS=0
FAILURES=0

check_ok()   { log_ok "$1"; }
check_warn() { log_warn "$1"; ((WARNINGS++)); }
check_fail() { log_fail "$1"; ((FAILURES++)); }

echo ""
echo "=================================================================="
echo "  System-Sicherheits-Audit — $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Host: $(hostname -f)"
echo "=================================================================="

# ─── SSH-Konfiguration ────────────────────────────────────────────────────────
log_section "SSH-Konfiguration"

if sshd -T 2>/dev/null | grep -qi "passwordauthentication no"; then
    check_ok "PasswordAuthentication deaktiviert"
else
    check_fail "PasswordAuthentication ist AKTIV — Sicherheitsrisiko!"
fi

if sshd -T 2>/dev/null | grep -qi "permitrootlogin prohibit-password\|permitrootlogin no"; then
    check_ok "Root-Login eingeschränkt (prohibit-password oder no)"
else
    check_warn "PermitRootLogin nicht auf 'prohibit-password' oder 'no' gesetzt"
fi

if sshd -T 2>/dev/null | grep -qi "x11forwarding no"; then
    check_ok "X11Forwarding deaktiviert"
else
    check_warn "X11Forwarding aktiv — nicht benötigt"
fi

# ─── UFW-Status ───────────────────────────────────────────────────────────────
log_section "Firewall (UFW)"

if command -v ufw &> /dev/null; then
    UFW_STATUS="$(ufw status 2>/dev/null | head -1)"
    if echo "${UFW_STATUS}" | grep -qi "active"; then
        check_ok "UFW aktiv"
        ufw status verbose 2>/dev/null | grep -E "^\d|^To|^--" | head -20 | sed 's/^/    /'
    else
        check_fail "UFW NICHT aktiv! Firewall fehlt."
    fi
else
    check_fail "UFW nicht installiert"
fi

# ─── Fail2Ban ─────────────────────────────────────────────────────────────────
log_section "Fail2Ban"

if systemctl is-active --quiet fail2ban 2>/dev/null; then
    check_ok "Fail2Ban läuft"
    fail2ban-client status 2>/dev/null | grep "Jail list" | sed 's/^/    /'
else
    check_warn "Fail2Ban läuft nicht"
fi

# ─── System-Updates ───────────────────────────────────────────────────────────
log_section "System-Updates"

if command -v apt-get &> /dev/null; then
    UPDATES=$(apt-get --simulate upgrade 2>/dev/null | grep "^Inst" | wc -l)
    SECURITY_UPDATES=$(apt-get --simulate upgrade 2>/dev/null | grep "^Inst.*security" | wc -l)
    if [[ "${UPDATES}" -eq 0 ]]; then
        check_ok "System aktuell"
    elif [[ "${SECURITY_UPDATES}" -gt 0 ]]; then
        check_fail "${SECURITY_UPDATES} Sicherheits-Updates ausstehend!"
    else
        check_warn "${UPDATES} Updates verfügbar (keine Sicherheitsupdates)"
    fi
fi

# ─── Offene Ports ─────────────────────────────────────────────────────────────
log_section "Offene Ports (ss)"
log_info "Listening-Ports:"
ss -tlnp 2>/dev/null | grep LISTEN | awk '{print $4, $6}' | sed 's/^/    /'

# ─── Docker-Container ─────────────────────────────────────────────────────────
log_section "Docker-Container"

if command -v docker &> /dev/null; then
    CONTAINERS=$(docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" 2>/dev/null)
    if [[ -n "${CONTAINERS}" ]]; then
        log_info "Laufende Container:"
        echo "${CONTAINERS}" | sed 's/^/    /'
    else
        log_info "Keine laufenden Container"
    fi
else
    log_info "Docker nicht installiert"
fi

# ─── Festplatten ──────────────────────────────────────────────────────────────
log_section "Festplatten-Auslastung"
df -h --output=source,size,used,avail,pcent,target 2>/dev/null \
    | grep -v "tmpfs\|udev\|Filesystem" \
    | while IFS= read -r line; do
        USAGE=$(echo "${line}" | awk '{print $5}' | tr -d '%')
        if [[ "${USAGE:-0}" -ge 90 ]]; then
            echo -e "${RED}  [CRIT]${NC} ${line}"
            ((FAILURES++))
        elif [[ "${USAGE:-0}" -ge 80 ]]; then
            echo -e "${YELLOW}  [WARN]${NC} ${line}"
        else
            echo "         ${line}"
        fi
    done

# ─── Letzte Login-Versuche ────────────────────────────────────────────────────
log_section "Letzte gescheiterte Logins (last 10)"
lastb 2>/dev/null | head -10 | sed 's/^/    /' || log_info "Keine Daten verfügbar"

# ─── Zusammenfassung ──────────────────────────────────────────────────────────
log_section "Zusammenfassung"
echo ""

if [[ "${FAILURES}" -eq 0 && "${WARNINGS}" -eq 0 ]]; then
    echo -e "${GREEN}  Audit bestanden — keine Probleme gefunden.${NC}"
elif [[ "${FAILURES}" -eq 0 ]]; then
    echo -e "${YELLOW}  ${WARNINGS} Warnungen — bitte prüfen.${NC}"
else
    echo -e "${RED}  ${FAILURES} Fehler und ${WARNINGS} Warnungen gefunden!${NC}"
fi

echo ""
[[ "${FAILURES}" -gt 0 ]] && exit 1 || exit 0
