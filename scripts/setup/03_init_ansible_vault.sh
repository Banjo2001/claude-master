#!/usr/bin/env bash
# =============================================================================
# DATEI:        03_init_ansible_vault.sh
# ZWECK:        Initialisiert Ansible Vault: Passwort-Datei erstellen,
#               vault.yml mit verschlüsselten Platzhaltern anlegen,
#               ansible.cfg konfigurieren.
# AUFRUFEN:     bash scripts/setup/03_init_ansible_vault.sh
# VORAUSSETZUNGEN:
#   - Ansible installiert: apt install -y ansible
#   - Im Git-Repository ausführen
#   - Normaler Benutzer (nicht root empfohlen)
# SICHERHEIT:
#   - Backup-Verhalten: vault.yml wird gesichert falls vorhanden
#   - Destruktiv: NEIN
#   - Rollback: rm ~/.vault_pass.txt && git checkout -- ansible/
# VERSION:      1.0.0 | Stand: 2026-04
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

# ─── Farben ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_ok()   { echo -e "${GREEN}  ✓${NC} $*"; }
log_fail() { echo -e "${RED}  ✗${NC} $*" >&2; }
log_warn() { echo -e "${YELLOW}  ⚠${NC} $*"; }
log_info() { echo -e "${BLUE}  i${NC} $*"; }

echo ""
echo "============================================================"
echo "  Ansible Vault Initialisierung"
echo "  Erstellt Vault-Passwort + vault.yml mit Platzhaltern"
echo "============================================================"
echo ""

# ─── 1. Voraussetzungen prüfen ──────────────────────────────────────────────
echo "[ Voraussetzungen ]"

if ! command -v ansible &>/dev/null; then
    log_fail "Ansible ist nicht installiert!"
    log_info "Installieren: sudo apt install -y ansible"
    log_info "Oder: pip3 install ansible"
    exit 1
fi
log_ok "ansible: $(ansible --version 2>&1 | head -1)"

if ! command -v ansible-vault &>/dev/null; then
    log_fail "ansible-vault ist nicht verfügbar (Teil von Ansible)!"
    exit 1
fi
log_ok "ansible-vault: verfügbar"

# Repository-Wurzel ermitteln
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
log_ok "Repository: $REPO_ROOT"

echo ""

# ─── 2. Vault-Passwort-Datei erstellen ──────────────────────────────────────
echo "[ Vault-Passwort-Datei ]"

# SICHERHEIT: Das Vault-Passwort liegt AUSSERHALB des Repos (~/)
# Es darf NIEMALS committed werden!
VAULT_PASS_FILE="${ANSIBLE_VAULT_PASSWORD_FILE:-$HOME/.vault_pass.txt}"

if [ -f "$VAULT_PASS_FILE" ]; then
    CURRENT_PERMS=$(stat -c "%a" "$VAULT_PASS_FILE" 2>/dev/null || echo "?")
    log_warn "Vault-Passwort-Datei existiert bereits: $VAULT_PASS_FILE (Rechte: $CURRENT_PERMS)"
    echo ""
    read -r -p "  Neues Passwort setzen? (überschreibt bestehendes) [j/N] " OVERWRITE
    if [[ ! "$OVERWRITE" =~ ^[jJyY]$ ]]; then
        log_info "Bestehendes Passwort beibehalten."
        # Rechte sicherstellen
        chmod 600 "$VAULT_PASS_FILE"
        log_ok "Rechte auf 600 gesetzt: $VAULT_PASS_FILE"
        VAULT_ALREADY_EXISTS=true
    else
        VAULT_ALREADY_EXISTS=false
    fi
else
    VAULT_ALREADY_EXISTS=false
fi

if [ "$VAULT_ALREADY_EXISTS" = false ]; then
    echo ""
    echo "  Das Vault-Passwort verschlüsselt alle Secrets (Passwörter, Tokens, Keys)."
    echo "  WICHTIG: Dieses Passwort sicher aufbewahren (Passwort-Manager)!"
    echo "           Ohne es sind die Vault-Dateien NICHT entschlüsselbar."
    echo ""

    # Passwort interaktiv eingeben (zweimal zur Bestätigung)
    while true; do
        read -r -s -p "  Vault-Passwort eingeben (mind. 20 Zeichen): " VAULT_PASSWORD
        echo ""

        # Mindestlänge prüfen
        if [ ${#VAULT_PASSWORD} -lt 20 ]; then
            log_warn "Passwort zu kurz (${#VAULT_PASSWORD} Zeichen, mind. 20 erforderlich)"
            continue
        fi

        read -r -s -p "  Vault-Passwort bestätigen: " VAULT_PASSWORD_CONFIRM
        echo ""

        if [ "$VAULT_PASSWORD" = "$VAULT_PASSWORD_CONFIRM" ]; then
            break
        else
            log_warn "Passwörter stimmen nicht überein — erneut versuchen"
        fi
    done

    # Passwort in Datei speichern (600 Rechte — nur für aktuellen Benutzer lesbar)
    printf '%s\n' "$VAULT_PASSWORD" > "$VAULT_PASS_FILE"
    chmod 600 "$VAULT_PASS_FILE"
    log_ok "Vault-Passwort gespeichert: $VAULT_PASS_FILE (Rechte: 600)"

    # Aus Speicher löschen (best effort — bash kann Variablen nicht sicher löschen)
    unset VAULT_PASSWORD VAULT_PASSWORD_CONFIRM
fi

echo ""

# ─── 3. ansible.cfg konfigurieren ───────────────────────────────────────────
echo "[ ansible.cfg ]"

ANSIBLE_CFG="$REPO_ROOT/ansible.cfg"

if [ -f "$ANSIBLE_CFG" ]; then
    log_ok "ansible.cfg existiert bereits: $ANSIBLE_CFG"
    log_info "Manuelle Prüfung: vault_password_file muss gesetzt sein"
else
    log_info "Erstelle ansible.cfg..."
    cat > "$ANSIBLE_CFG" << CFGEOF
# =============================================================================
# ansible.cfg — Ansible Konfiguration
# ZWECK: Projektweite Ansible-Einstellungen
# SICHERHEIT: vault_password_file zeigt auf ~/.vault_pass.txt (AUSSERHALB Repo)
# =============================================================================
[defaults]
# Inventar-Verzeichnis
inventory = ansible/inventories/prod/hosts.yml

# Vault-Passwort-Datei (NIEMALS ins Repo committen!)
vault_password_file = ~/.vault_pass.txt

# SSH-Einstellungen
remote_user = root
private_key_file = ~/.ssh/id_ed25519_proxmox
host_key_checking = true

# Parallelität (wie viele Hosts gleichzeitig)
forks = 10

# Ausgabe-Format
stdout_callback = yaml
bin_ansible_callbacks = true

# Python-Interpreter automatisch erkennen
interpreter_python = auto_silent

# Rollen-Verzeichnis
roles_path = ansible/roles

# Retry-Dateien deaktivieren (erzeugen Unordnung)
retry_files_enabled = false

[ssh_connection]
# SSH Verbindungs-Multiplexing (schneller bei mehreren Tasks)
ssh_args = -o ControlMaster=auto -o ControlPersist=60s -o StrictHostKeyChecking=yes

# Pipelining beschleunigt Ausführung (kein sudo mit requiretty nötig)
pipelining = true

[privilege_escalation]
become = false
become_method = sudo
become_user = root
CFGEOF
    log_ok "ansible.cfg erstellt: $ANSIBLE_CFG"
fi

echo ""

# ─── 4. vault.yml mit Platzhaltern erstellen ────────────────────────────────
echo "[ vault.yml — Verschlüsselte Secrets ]"

VAULT_FILE="$REPO_ROOT/ansible/inventories/prod/group_vars/all/vault.yml"
VAULT_DIR="$(dirname "$VAULT_FILE")"

# Verzeichnis erstellen falls nötig
mkdir -p "$VAULT_DIR"

if [ -f "$VAULT_FILE" ]; then
    log_warn "vault.yml existiert bereits: $VAULT_FILE"
    log_info "Inhalt wird NICHT überschrieben — manuell prüfen falls nötig"
else
    log_info "Erstelle vault.yml mit Platzhaltern..."

    # Zuerst eine unverschlüsselte Vorlage erstellen
    VAULT_TEMPLATE=$(mktemp)
    # shellcheck disable=SC2064
    trap "rm -f '$VAULT_TEMPLATE'" EXIT

    cat > "$VAULT_TEMPLATE" << 'VAULTEOF'
---
# =============================================================================
# vault.yml — Ansible Vault (AES-256 verschlüsselt)
# ZWECK: Alle Secrets für die Infrastruktur
# BEARBEITEN: ansible-vault edit ansible/inventories/prod/group_vars/all/vault.yml
# ANZEIGEN:   ansible-vault view ansible/inventories/prod/group_vars/all/vault.yml
# =============================================================================

# ─── Proxmox VE ─────────────────────────────────────────────────────────────
vault_pve_api_token_id: "ansible@pve!deploy"
vault_pve_api_token_secret: "<WIRD_VIA_VAULT_GESETZT>"

# ─── Proxmox Backup Server ──────────────────────────────────────────────────
vault_pbs_api_token_id: "ansible@pbs!verify"
vault_pbs_api_token_secret: "<WIRD_VIA_VAULT_GESETZT>"

# ─── Matrix Synapse ─────────────────────────────────────────────────────────
# Registrierungsschlüssel (verhindert Spam-Anmeldungen)
vault_matrix_registration_shared_secret: "<WIRD_VIA_VAULT_GESETZT>"

# Macaroon-Key für Tokens
vault_matrix_macaroon_secret_key: "<WIRD_VIA_VAULT_GESETZT>"

# PostgreSQL-Passwörter
vault_matrix_db_password: "<WIRD_VIA_VAULT_GESETZT>"

# Coturn TURN-Server Authentifizierung
vault_coturn_auth_secret: "<WIRD_VIA_VAULT_GESETZT>"

# ─── Nextcloud ───────────────────────────────────────────────────────────────
vault_nextcloud_db_password: "<WIRD_VIA_VAULT_GESETZT>"
vault_nextcloud_db_root_password: "<WIRD_VIA_VAULT_GESETZT>"
vault_nextcloud_admin_password: "<WIRD_VIA_VAULT_GESETZT>"

# ─── SSH ─────────────────────────────────────────────────────────────────────
# Öffentlicher Schlüssel des Control-Nodes (für authorized_keys)
vault_control_node_ssh_pubkey: "<WIRD_VIA_VAULT_GESETZT>"

# ─── E-Mail / SMTP ──────────────────────────────────────────────────────────
vault_smtp_password: "<WIRD_VIA_VAULT_GESETZT>"
VAULTEOF

    # Mit ansible-vault verschlüsseln
    if ansible-vault encrypt "$VAULT_TEMPLATE" --vault-password-file "$VAULT_PASS_FILE" \
        --output "$VAULT_FILE" 2>/dev/null; then
        log_ok "vault.yml verschlüsselt erstellt: $VAULT_FILE"
    else
        log_fail "Vault-Verschlüsselung fehlgeschlagen!"
        log_info "Manuell: ansible-vault create $VAULT_FILE"
        rm -f "$VAULT_TEMPLATE"
        exit 1
    fi
fi

echo ""

# ─── 5. vars.yml mit nicht-sensitiven Variablen erstellen ───────────────────
echo "[ vars.yml — Nicht-sensitive Variablen ]"

VARS_FILE="$REPO_ROOT/ansible/inventories/prod/group_vars/all/vars.yml"

if [ -f "$VARS_FILE" ]; then
    log_ok "vars.yml existiert bereits: $VARS_FILE"
else
    log_info "Erstelle vars.yml..."
    cat > "$VARS_FILE" << 'VARSEOF'
---
# =============================================================================
# vars.yml — Nicht-sensitive Variablen
# ZWECK: Konfiguration die KEIN Secret enthält (öffentlich commitbar)
# SECRETS: Gehören in vault.yml (ansible-vault verschlüsselt)
# =============================================================================

# ─── Allgemein ───────────────────────────────────────────────────────────────
timezone: "Europe/Berlin"
locale: "de_DE.UTF-8"

# ─── Proxmox VE ─────────────────────────────────────────────────────────────
pve_host: "pve01.example.com"
pve_port: 8006

# ─── Proxmox Backup Server ──────────────────────────────────────────────────
pbs_host: "pbs01.example.com"
pbs_port: 8007
pbs_datastore: "backup-store"

# ─── Matrix Synapse ─────────────────────────────────────────────────────────
matrix_domain: "<DEINE_DOMAIN>"
matrix_server_name: "<DEINE_DOMAIN>"
matrix_public_baseurl: "https://matrix.<DEINE_DOMAIN>"

# PostgreSQL für Matrix
matrix_db_name: "synapse"
matrix_db_user: "synapse"
matrix_db_host: "localhost"
matrix_db_port: 5432

# Coturn TURN-Server
coturn_listening_port: 3478
coturn_tls_listening_port: 5349
coturn_min_port: 49152
coturn_max_port: 65535

# ─── Nextcloud ───────────────────────────────────────────────────────────────
nextcloud_domain: "<DEINE_NEXTCLOUD_DOMAIN>"
nextcloud_db_name: "nextcloud"
nextcloud_db_user: "nextcloud"

# ─── SSH-Härtung ─────────────────────────────────────────────────────────────
ssh_port: 22
ssh_allowed_users: []

# ─── UFW-Firewall ────────────────────────────────────────────────────────────
# Management-IPs die SSH-Zugriff erhalten (Platzhalter: RFC 5737)
ufw_allowed_ssh_sources:
  - "192.0.2.10"

# ─── E-Mail / SMTP ──────────────────────────────────────────────────────────
smtp_host: "mail.example.com"
smtp_port: 587
smtp_user: "admin@example.com"
smtp_from: "admin@example.com"
VARSEOF
    log_ok "vars.yml erstellt: $VARS_FILE"
fi

echo ""

# ─── 6. Hosts-Inventar erstellen ────────────────────────────────────────────
echo "[ Hosts-Inventar ]"

HOSTS_FILE="$REPO_ROOT/ansible/inventories/prod/hosts.yml"

if [ -f "$HOSTS_FILE" ] && [ -s "$HOSTS_FILE" ]; then
    # Prüfen ob es noch das .gitkeep ist oder echte Inhalt hat
    if grep -q "gitkeep\|PLATZHALTER\|pve01\|pbs01" "$HOSTS_FILE" 2>/dev/null; then
        log_ok "hosts.yml existiert bereits: $HOSTS_FILE"
    else
        log_ok "hosts.yml existiert bereits: $HOSTS_FILE"
    fi
else
    log_info "Erstelle hosts.yml (Platzhalter-IPs nach RFC 5737)..."
    cat > "$HOSTS_FILE" << 'HOSTSEOF'
---
# =============================================================================
# hosts.yml — Ansible Inventar (Produktion)
# ZWECK: Alle verwalteten Hosts gruppiert nach Funktion
# SICHERHEIT: Echte IPs hier eintragen (keine Secrets — Vault für Passwörter)
# PLATZHALTER: 192.0.2.x = RFC 5737 TEST-NET (nicht routbar, sicher für Docs)
# =============================================================================

all:
  vars:
    # Ansible nutzt Python 3 auf den Zielhosts
    ansible_python_interpreter: /usr/bin/python3

  children:

    # ─── Proxmox VE Cluster ──────────────────────────────────────────────────
    proxmox_ve:
      hosts:
        pve01:
          ansible_host: "192.0.2.10"
          ansible_user: root
          ansible_ssh_private_key_file: "~/.ssh/id_ed25519_proxmox"

    # ─── Proxmox Backup Server ───────────────────────────────────────────────
    proxmox_backup:
      hosts:
        pbs01:
          ansible_host: "192.0.2.11"
          ansible_user: root
          ansible_ssh_private_key_file: "~/.ssh/id_ed25519_proxmox"

    # ─── Matrix Synapse (LXC Container auf PVE) ──────────────────────────────
    matrix_servers:
      hosts:
        matrix01:
          ansible_host: "192.0.2.20"
          ansible_user: root
          ansible_ssh_private_key_file: "~/.ssh/id_ed25519_proxmox"

    # ─── Nextcloud AIO (LXC Container auf PVE) ───────────────────────────────
    nextcloud_servers:
      hosts:
        nextcloud01:
          ansible_host: "192.0.2.21"
          ansible_user: root
          ansible_ssh_private_key_file: "~/.ssh/id_ed25519_proxmox"

    # ─── Alle App-Server (Matrix + Nextcloud) ────────────────────────────────
    app_servers:
      children:
        matrix_servers:
        nextcloud_servers:

    # ─── Alle verwalteten Server ──────────────────────────────────────────────
    managed:
      children:
        proxmox_ve:
        proxmox_backup:
        app_servers:
HOSTSEOF
    log_ok "hosts.yml erstellt: $HOSTS_FILE"
fi

echo ""

# ─── 7. Vault-Zugriff testen ────────────────────────────────────────────────
echo "[ Vault-Test ]"

log_info "Prüfe ob vault.yml lesbar ist..."

if ansible-vault view "$VAULT_FILE" --vault-password-file "$VAULT_PASS_FILE" \
    2>/dev/null | grep -q "vault_pve_api_token_id"; then
    log_ok "Vault-Entschlüsselung: erfolgreich"
else
    log_warn "Vault-Test fehlgeschlagen — Passwort oder Datei prüfen"
    log_info "Manuell testen: ansible-vault view $VAULT_FILE"
fi

echo ""

# ─── 8. .gitignore prüfen ───────────────────────────────────────────────────
echo "[ .gitignore Sicherheits-Check ]"

GITIGNORE="$REPO_ROOT/.gitignore"

# vault_pass.txt sollte in .gitignore sein
if grep -q "vault.pass\|vault_pass\|\.vault" "$GITIGNORE" 2>/dev/null; then
    log_ok ".gitignore enthält Vault-Passwort-Ausschluss"
else
    log_warn ".vault_pass.txt ist NICHT in .gitignore!"
    log_info "Hinzufügen: echo '.vault_pass.txt' >> .gitignore"
fi

# ansible.cfg prüfen (enthält Pfad zu vault_password_file — kein Secret)
if grep -q "ansible.cfg" "$GITIGNORE" 2>/dev/null; then
    log_warn "ansible.cfg ist in .gitignore — sollte versioniert sein!"
    log_info "ansible.cfg enthält keine Secrets (nur Pfade)"
else
    log_ok "ansible.cfg ist nicht in .gitignore (wird versioniert — korrekt)"
fi

echo ""

# ─── 9. Ergebnis ────────────────────────────────────────────────────────────
echo "============================================================"
echo "  Ansible Vault Initialisierung abgeschlossen!"
echo "============================================================"
echo ""
echo "  Erstellt/geprüft:"
echo "    $VAULT_PASS_FILE (Vault-Passwort, Rechte: 600)"
echo "    $VAULT_FILE (verschlüsselt)"
echo "    $VARS_FILE (nicht-sensitiv)"
echo "    $HOSTS_FILE (Inventar)"
echo "    $ANSIBLE_CFG (Konfiguration)"
echo ""
echo "  Nächste Schritte:"
echo ""
echo "  1. Echte Werte in vault.yml eintragen:"
echo "     ansible-vault edit ansible/inventories/prod/group_vars/all/vault.yml"
echo ""
echo "  2. Echte IPs in hosts.yml eintragen:"
echo "     nano ansible/inventories/prod/hosts.yml"
echo ""
echo "  3. Ansible testen (Ping aller Hosts):"
echo "     ansible all -m ping"
echo ""
echo "  4. Syntax prüfen:"
echo "     ansible-playbook --syntax-check ansible/playbooks/site.yml"
echo ""
echo "  SICHERHEIT:"
echo "    - Vault-Passwort im Passwort-Manager sichern!"
echo "    - ~/.vault_pass.txt NIEMALS ins Repo committen"
echo "    - git status prüfen vor jedem commit"
echo ""
