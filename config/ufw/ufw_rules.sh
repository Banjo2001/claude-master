#!/usr/bin/env bash
# =============================================================================
# DATEI:        config/ufw/ufw_rules.sh
# ZWECK:        UFW-Regeln idempotent setzen (sicher wiederholbar)
# AUFRUFEN:     sudo ./ufw_rules.sh
# VORAUSSETZUNGEN:
#   - ufw installiert: apt install ufw
#   - SSH-Key auf Server kopiert (BEVOR Passwort-Auth gesperrt wird!)
# SICHERHEIT:
#   - Backup-Verhalten: Regeln werden nicht gelöscht, nur hinzugefügt
#   - Destruktiv: NEIN (aber Aktivierung sperrt ungeschützte Verbindungen!)
#   - Rollback: ufw disable && ufw reset
# VERSION:      1.0.0 | Stand: 2026-04
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

# ─── Farben ───────────────────────────────────────────────────────────────────
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ─── Root-Check ───────────────────────────────────────────────────────────────
if [[ "${EUID}" -ne 0 ]]; then
    log_error "Dieses Skript muss als root ausgeführt werden: sudo $0"
    exit 1
fi

# ─── Konfiguration ────────────────────────────────────────────────────────────
# ANPASSEN: SSH-Port wenn geändert
SSH_PORT="${SSH_PORT:-22}"

# ANPASSEN: Management-IPs (RFC 5737 Platzhalter — ersetzen!)
MANAGEMENT_IP="${MANAGEMENT_IP:-192.0.2.10}"

# ─── Sicherheitswarnung ───────────────────────────────────────────────────────
echo ""
log_warn "=========================================================="
log_warn "UFW-Regeln werden gesetzt. Aktuelle Verbindungen bleiben."
log_warn "WARNUNG: Nach 'ufw enable' werden neue Verbindungen gefiltert!"
log_warn "Stelle sicher, dass SSH-Key-Auth funktioniert, BEVOR du"
log_warn "Passwort-Auth deaktivierst!"
log_warn "SSH-Port: ${SSH_PORT}"
log_warn "Management-IP: ${MANAGEMENT_IP}"
log_warn "=========================================================="
echo ""

# ─── UFW-Standardregeln ───────────────────────────────────────────────────────
log_info "Standardregeln setzen: alles verweigern, ausgehend erlauben..."

# Alles eingehend ablehnen
ufw default deny incoming

# Alles ausgehend erlauben
ufw default allow outgoing

# ─── SSH ──────────────────────────────────────────────────────────────────────
# KRITISCH: SSH MUSS freigegeben sein — sonst Aussperrung!
log_info "SSH-Port ${SSH_PORT} von Management-IP ${MANAGEMENT_IP} erlauben..."
ufw allow from "${MANAGEMENT_IP}" to any port "${SSH_PORT}" proto tcp comment "SSH Management"

# ─── HTTP/HTTPS ───────────────────────────────────────────────────────────────
log_info "HTTP und HTTPS erlauben..."
ufw allow 80/tcp comment "HTTP (Redirect zu HTTPS)"
ufw allow 443/tcp comment "HTTPS"

# ─── Matrix TURN (Coturn) ─────────────────────────────────────────────────────
log_info "Coturn TURN-Ports erlauben..."
ufw allow 3478/tcp comment "Coturn TURN"
ufw allow 3478/udp comment "Coturn TURN"
ufw allow 5349/tcp comment "Coturn TURNS (TLS)"
ufw allow 5349/udp comment "Coturn TURNS (TLS)"
# TURN Media-Ports (Bereich für RTP/RTCP)
ufw allow 49152:65535/udp comment "Coturn Media-Ports"

# ─── Nextcloud AIO ───────────────────────────────────────────────────────────
log_info "Nextcloud AIO HTTPS-Port erlauben..."
ufw allow 8443/tcp comment "Nextcloud AIO HTTPS"

log_info "Nextcloud Admin-Interface NUR von Management-IP erlauben..."
ufw allow from "${MANAGEMENT_IP}" to any port 8080 proto tcp comment "Nextcloud Admin (Management only)"

# ─── Proxmox Web-UI ───────────────────────────────────────────────────────────
log_info "Proxmox Web-UI NUR von Management-IP erlauben..."
ufw allow from "${MANAGEMENT_IP}" to any port 8006 proto tcp comment "Proxmox Web-UI (Management only)"

# ─── UFW aktivieren ───────────────────────────────────────────────────────────
log_info "Aktuelle UFW-Regeln:"
ufw show added

echo ""
log_warn "WICHTIG: UFW ist noch NICHT aktiviert."
log_warn "Prüfe die Regeln oben, dann aktivieren mit:"
log_warn "  ufw enable"
log_warn "  ufw status verbose"
echo ""
log_info "Regeln erfolgreich konfiguriert."
