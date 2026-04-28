#!/usr/bin/env bash
# =============================================================================
# DATEI:        scripts/security/setup_ufw.sh
# ZWECK:        UFW installieren und Grundregeln setzen
# AUFRUFEN:     sudo ./setup_ufw.sh
# VORAUSSETZUNGEN:
#   - Debian/Ubuntu
#   - SSH-Key-Auth funktioniert (PFLICHT vor Aktivierung!)
# SICHERHEIT:
#   - Backup-Verhalten: Regeln werden nicht gelöscht
#   - Destruktiv: JA — UFW aktivieren sperrt ungeschützte Ports!
#   - Rollback: ufw disable && ufw reset
# VERSION:      1.0.0 | Stand: 2026-04
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

log_info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_section() { echo -e "\n${CYAN}━━━ $* ━━━${NC}"; }

if [[ "${EUID}" -ne 0 ]]; then
    log_error "Root erforderlich: sudo $0"
    exit 1
fi

# ─── Konfiguration (anpassen!) ────────────────────────────────────────────────
SSH_PORT="${SSH_PORT:-22}"
MANAGEMENT_IP="${MANAGEMENT_IP:-192.0.2.10}"

log_section "UFW Setup"
log_warn "SSH-Port: ${SSH_PORT}"
log_warn "Management-IP: ${MANAGEMENT_IP}"
log_warn "ANPASSEN: Setze SSH_PORT und MANAGEMENT_IP als Umgebungsvariablen"
log_warn "Beispiel: MANAGEMENT_IP=203.0.113.5 ./setup_ufw.sh"
echo ""

# ─── Installieren ─────────────────────────────────────────────────────────────
log_section "Schritt 1: Installation"
apt-get update -qq
apt-get install -y ufw
log_info "UFW installiert"

# ─── Sicherheitswarnung ───────────────────────────────────────────────────────
log_section "Schritt 2: Sicherheitscheck"
log_warn "⚠️  ACHTUNG — DESTRUKTIV: UFW-Aktivierung filtert alle Verbindungen!"
log_warn ""
log_warn "Stelle sicher:"
log_warn "  1. SSH-Key-Auth funktioniert"
log_warn "  2. Management-IP korrekt: ${MANAGEMENT_IP}"
log_warn "  3. SSH-Port korrekt: ${SSH_PORT}"
echo ""
read -r -p "Alles korrekt? UFW konfigurieren und aktivieren? [ja/NEIN]: " CONFIRM

if [[ "${CONFIRM,,}" != "ja" ]]; then
    log_info "Abbruch — keine Änderungen."
    exit 0
fi

# ─── Regeln setzen ────────────────────────────────────────────────────────────
log_section "Schritt 3: Regeln konfigurieren"

# Standardregeln
ufw default deny incoming
ufw default allow outgoing
log_info "Standards: eingehend=deny, ausgehend=allow"

# SSH (KRITISCH: Zuerst!)
ufw allow from "${MANAGEMENT_IP}" to any port "${SSH_PORT}" proto tcp comment "SSH Management"
log_info "SSH Port ${SSH_PORT} von ${MANAGEMENT_IP} erlaubt"

# Web
ufw allow 80/tcp comment "HTTP"
ufw allow 443/tcp comment "HTTPS"
log_info "HTTP/HTTPS erlaubt"

# Coturn TURN
ufw allow 3478/tcp comment "Coturn TURN"
ufw allow 3478/udp comment "Coturn TURN"
ufw allow 5349/tcp comment "Coturn TURNS"
ufw allow 5349/udp comment "Coturn TURNS"
ufw allow 49152:65535/udp comment "Coturn Media"
log_info "Coturn TURN-Ports erlaubt"

# Nextcloud AIO
ufw allow 8443/tcp comment "Nextcloud AIO HTTPS"
ufw allow from "${MANAGEMENT_IP}" to any port 8080 proto tcp comment "Nextcloud Admin"
log_info "Nextcloud AIO-Ports erlaubt"

# Proxmox
ufw allow from "${MANAGEMENT_IP}" to any port 8006 proto tcp comment "Proxmox Web-UI"
log_info "Proxmox Web-UI für Management erlaubt"

# ─── UFW aktivieren ───────────────────────────────────────────────────────────
log_section "Schritt 4: UFW aktivieren"
log_info "Aktiviere UFW..."

# ⚠️  ACHTUNG — DESTRUKTIV: Filtert ab jetzt alle eingehenden Verbindungen!
# Rollback: ufw disable
ufw --force enable

# ─── Status ───────────────────────────────────────────────────────────────────
log_section "Status"
ufw status verbose

log_section "Abgeschlossen"
log_info "UFW aktiv und konfiguriert."
log_warn "ROLLBACK bei Aussperrung: ufw disable"
