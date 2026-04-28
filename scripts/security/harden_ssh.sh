#!/usr/bin/env bash
# =============================================================================
# DATEI:        scripts/security/harden_ssh.sh
# ZWECK:        SSH-Konfiguration nach BSI TR-02102-4 härten
# AUFRUFEN:     sudo ./harden_ssh.sh
# VORAUSSETZUNGEN:
#   - SSH-Key auf Server kopiert (testen mit: ssh -i ~/.ssh/id_ed25519 root@<IP>)
#   - sshd installiert
# SICHERHEIT:
#   - Backup-Verhalten: Original-Config wird gesichert
#   - Destruktiv: NEIN (bestehende Verbindungen bleiben)
#   - Rollback: cp /etc/ssh/sshd_config.bak.<DATUM> /etc/ssh/sshd_config && systemctl restart sshd
# VERSION:      1.0.0 | Stand: 2026-04
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

# ─── Farben ───────────────────────────────────────────────────────────────────
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

log_info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_section() { echo -e "\n${CYAN}━━━ $* ━━━${NC}"; }

# ─── Root-Check ───────────────────────────────────────────────────────────────
if [[ "${EUID}" -ne 0 ]]; then
    log_error "Dieses Skript muss als root ausgeführt werden: sudo $0"
    exit 1
fi

# ─── Konfiguration ────────────────────────────────────────────────────────────
readonly SSHD_CONFIG="/etc/ssh/sshd_config"
readonly SSHD_HARDENED_DIR="/etc/ssh/sshd_config.d"
readonly HARDENED_CONF="${SSHD_HARDENED_DIR}/99-hardened.conf"
readonly BACKUP="${SSHD_CONFIG}.bak.$(date +%F)"

log_section "SSH-Hardening"

# ─── Schritt 1: SSH-Key-Auth prüfen ──────────────────────────────────────────
log_section "Schritt 1: Voraussetzungen prüfen"

log_warn "KRITISCHE SICHERHEITSPRÜFUNG:"
log_warn "Stelle sicher, dass Public-Key-Auth funktioniert!"
log_warn "Test-Befehl (auf lokalem PC ausführen):"
log_warn "  ssh -i ~/.ssh/id_ed25519 root@<SERVER-IP> 'echo KEY_OK'"
echo ""
read -r -p "Funktioniert Key-Auth? [ja/NEIN]: " KEY_CONFIRM

if [[ "${KEY_CONFIRM,,}" != "ja" ]]; then
    log_error "SSH-Key-Auth nicht bestätigt. Abbruch — keine Änderungen."
    log_error "Kopiere erst deinen Public-Key: ssh-copy-id -i ~/.ssh/id_ed25519.pub root@<IP>"
    exit 1
fi
log_info "Key-Auth bestätigt. Fahre fort..."

# ─── Schritt 2: Backup ────────────────────────────────────────────────────────
log_section "Schritt 2: Backup"

# SICHERUNG: Originaldatei sichern
cp "${SSHD_CONFIG}" "${BACKUP}"
log_info "Backup erstellt: ${BACKUP}"

# ─── Schritt 3: sshd_config.d Verzeichnis prüfen ────────────────────────────
log_section "Schritt 3: Konfiguration"

if [[ ! -d "${SSHD_HARDENED_DIR}" ]]; then
    mkdir -p "${SSHD_HARDENED_DIR}"
    log_info "Verzeichnis erstellt: ${SSHD_HARDENED_DIR}"
fi

# Prüfen ob Include bereits in sshd_config steht
if ! grep -q "Include /etc/ssh/sshd_config.d" "${SSHD_CONFIG}"; then
    echo "Include /etc/ssh/sshd_config.d/*.conf" >> "${SSHD_CONFIG}"
    log_info "Include-Direktive zu sshd_config hinzugefügt"
fi

# ─── Schritt 4: Hardened Config schreiben ─────────────────────────────────────
log_info "Hardened-Konfiguration schreiben: ${HARDENED_CONF}"

cat > "${HARDENED_CONF}" << 'SSHD_EOF'
# Automatisch generiert durch harden_ssh.sh — NICHT manuell bearbeiten!
# BSI TR-02102-4 konform

# Nur moderne Schlüsseltypen
HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_ecdsa_key

# Moderne Kex-Algorithmen
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512

# Starke Ciphers
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com

# ETM-MACs (Encrypt-then-MAC)
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com

# Authentifizierung
PasswordAuthentication no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
PermitRootLogin prohibit-password
MaxAuthTries 3
LoginGraceTime 30

# Verbindungslimits
MaxStartups 10:30:60
ClientAliveInterval 300
ClientAliveCountMax 3

# Angriffsflächenreduktion
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
PermitTunnel no

# Sicherheits-Flags
StrictModes yes
PrintLastLog yes
UseDNS no

# Logging
LogLevel VERBOSE
SyslogFacility AUTH
SSHD_EOF

chmod 644 "${HARDENED_CONF}"

# ─── Schritt 5: Syntax prüfen ─────────────────────────────────────────────────
log_section "Schritt 4: Syntaxprüfung"
log_info "Prüfe SSH-Konfiguration..."

if ! sshd -t; then
    log_error "SYNTAXFEHLER in SSH-Konfiguration!"
    log_error "Rollback: cp ${BACKUP} ${SSHD_CONFIG}"
    rm -f "${HARDENED_CONF}"
    exit 1
fi
log_info "Syntaxprüfung OK"

# ─── Schritt 6: SSH neu starten ───────────────────────────────────────────────
log_section "Schritt 5: SSH neu starten"
log_warn "SSH wird jetzt neu gestartet. Aktuelle Verbindungen bleiben."
log_warn "Neue Verbindungen benötigen ab sofort Public-Key!"

systemctl restart sshd
log_info "SSH erfolgreich neu gestartet"

# ─── Abschluss ────────────────────────────────────────────────────────────────
log_section "Abgeschlossen"
log_info "SSH-Hardening erfolgreich angewendet."
echo ""
log_info "Testen (neue SSH-Verbindung in neuem Terminal):"
log_info "  ssh -i ~/.ssh/id_ed25519 root@<SERVER-IP>"
echo ""
log_warn "Rollback bei Problemen:"
log_warn "  cp ${BACKUP} ${SSHD_CONFIG} && rm ${HARDENED_CONF} && systemctl restart sshd"
