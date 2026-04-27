#!/usr/bin/env bash
# =============================================================================
# DATEI:        00_preflight_check.sh
# ZWECK:        Prüft ob alle Voraussetzungen für den Betrieb von Claude Code
#               und der Infrastruktur-Automatisierung erfüllt sind.
# AUFRUFEN:     bash scripts/setup/00_preflight_check.sh
# VORAUSSETZUNGEN:
#   - Bash >= 4.0
#   - Ausführen als normaler Benutzer (nicht root)
# SICHERHEIT:
#   - Backup-Verhalten: keines (nur Lese-Operationen)
#   - Destruktiv: NEIN
#   - Rollback: nicht nötig
# VERSION:      1.0.0 | Stand: 2026-04
# =============================================================================
set -euo pipefail
# set -e  : Abbruch bei Fehler
# set -u  : Fehler bei undefinierten Variablen
# set -o pipefail : Fehler in Pipes wird erkannt

IFS=$'\n\t'

# ─── Farben für die Ausgabe ──────────────────────────────────────────────────
# Macht die Ausgabe lesbarer: Grün=OK, Rot=Fehler, Gelb=Warnung
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color (Reset)

# ─── Hilfsfunktionen ────────────────────────────────────────────────────────
log_ok()   { echo -e "${GREEN}  ✓${NC} $*"; }
log_fail() { echo -e "${RED}  ✗${NC} $*"; FAILED=$((FAILED + 1)); }
log_warn() { echo -e "${YELLOW}  ⚠${NC} $*"; WARNINGS=$((WARNINGS + 1)); }
log_info() { echo -e "${BLUE}  i${NC} $*"; }

# Zähler für Fehler und Warnungen
FAILED=0
WARNINGS=0

# ─── Banner ─────────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo "  Proxmox Infra Admin — Preflight Check"
echo "  Prüft alle Voraussetzungen vor dem ersten Start"
echo "============================================================"
echo ""

# ─── 1. Betriebssystem ──────────────────────────────────────────────────────
echo "[ Betriebssystem ]"

# Welches OS läuft hier?
if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    log_info "OS: $PRETTY_NAME"

    # Prüfen ob es Debian/Ubuntu ist (unterstützte Plattformen)
    if echo "$ID $ID_LIKE" | grep -qiE 'debian|ubuntu'; then
        log_ok "Unterstütztes Betriebssystem erkannt"
    else
        log_warn "Nicht getestetes Betriebssystem: $PRETTY_NAME"
        log_warn "Skripte wurden für Debian 12/13 und Ubuntu 22-25 entwickelt"
    fi
else
    log_warn "Betriebssystem konnte nicht erkannt werden (/etc/os-release fehlt)"
fi

# Architektur prüfen (nur amd64/x86_64 getestet)
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    log_ok "Architektur: $ARCH (unterstützt)"
else
    log_warn "Architektur: $ARCH — nur x86_64 vollständig getestet"
fi

echo ""

# ─── 2. Benutzer-Prüfung ────────────────────────────────────────────────────
echo "[ Benutzer ]"

# SICHERHEIT: Nicht als root ausführen (außer in Docker)
if [ "$EUID" -eq 0 ]; then
    log_warn "Läuft als root — empfohlen ist ein normaler Benutzer mit sudo"
    log_warn "Claude Code sollte NIEMALS dauerhaft als root betrieben werden"
else
    log_ok "Läuft als normaler Benutzer: $(whoami)"

    # Sudo verfügbar?
    if sudo -n true 2>/dev/null; then
        log_ok "sudo-Zugriff ohne Passwort verfügbar (für Ansible benötigt)"
    elif sudo -v 2>/dev/null; then
        log_ok "sudo-Zugriff verfügbar (mit Passwort)"
    else
        log_warn "Kein sudo-Zugriff — Ansible-Playbooks benötigen sudo auf Zielhosts"
    fi
fi

echo ""

# ─── 3. Basis-Tools ─────────────────────────────────────────────────────────
echo "[ Basis-Tools ]"

# Funktion: Prüft ob ein Befehl vorhanden ist und gibt Version aus
check_tool() {
    local tool="$1"
    local version_flag="${2:---version}"
    local min_version="${3:-}"

    if command -v "$tool" &>/dev/null; then
        local version
        version=$("$tool" "$version_flag" 2>&1 | head -1) || true
        log_ok "$tool: gefunden ($version)"
        return 0
    else
        log_fail "$tool: NICHT gefunden — installieren mit: apt install -y $tool"
        return 1
    fi
}

check_tool "git"
check_tool "curl"
check_tool "wget"
check_tool "python3"
check_tool "jq"

echo ""

# ─── 4. Claude Code ─────────────────────────────────────────────────────────
echo "[ Claude Code ]"

if command -v claude &>/dev/null; then
    CLAUDE_VERSION=$(claude --version 2>&1 | head -1) || true
    log_ok "Claude Code: $CLAUDE_VERSION"
else
    log_warn "Claude Code: nicht installiert"
    log_info "Installieren mit: bash scripts/setup/01_install_claude_code.sh"
fi

# ANTHROPIC_API_KEY — NUR prüfen ob gesetzt, NIEMALS ausgeben!
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    # Nur erste 4 Zeichen anzeigen (sicher)
    KEY_PREVIEW="${ANTHROPIC_API_KEY:0:4}****"
    log_ok "ANTHROPIC_API_KEY: gesetzt ($KEY_PREVIEW...)"
else
    log_fail "ANTHROPIC_API_KEY: nicht gesetzt!"
    log_info "Setzen mit: export ANTHROPIC_API_KEY='sk-ant-...'"
    log_info "Dauerhaft: echo 'export ANTHROPIC_API_KEY=...' >> ~/.bashrc"
fi

echo ""

# ─── 5. Ansible ─────────────────────────────────────────────────────────────
echo "[ Ansible ]"

if command -v ansible &>/dev/null; then
    ANSIBLE_VERSION=$(ansible --version 2>&1 | head -1)
    log_ok "Ansible: $ANSIBLE_VERSION"

    # Mindestversion 2.17 prüfen
    ANSIBLE_MAJOR=$(ansible --version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1 | cut -d. -f1)
    ANSIBLE_MINOR=$(ansible --version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1 | cut -d. -f2)
    if [ "${ANSIBLE_MAJOR:-0}" -ge 2 ] && [ "${ANSIBLE_MINOR:-0}" -ge 17 ]; then
        log_ok "Ansible-Version >= 2.17: OK"
    else
        log_warn "Ansible-Version < 2.17 — empfohlen: pip3 install ansible>=2.17"
    fi

    # ansible-lint prüfen
    if command -v ansible-lint &>/dev/null; then
        log_ok "ansible-lint: $(ansible-lint --version 2>&1 | head -1)"
    else
        log_warn "ansible-lint: nicht installiert — installieren mit: pip3 install ansible-lint"
    fi
else
    log_fail "Ansible: NICHT installiert"
    log_info "Installieren mit: sudo apt install -y ansible"
    log_info "Oder: pip3 install ansible"
fi

echo ""

# ─── 6. Docker ──────────────────────────────────────────────────────────────
echo "[ Docker ]"

if command -v docker &>/dev/null; then
    DOCKER_VERSION=$(docker --version 2>&1)
    log_ok "Docker: $DOCKER_VERSION"

    # Prüfen ob es Docker CE ist (nicht docker.io vom Ubuntu-Repo)
    if docker info 2>/dev/null | grep -q "Docker Engine"; then
        log_ok "Docker Engine CE erkannt (empfohlen)"
    else
        log_warn "Docker-Version konnte nicht bestimmt werden"
    fi

    # Docker Compose Plugin prüfen (v2 — KEIN Bindestrich!)
    if docker compose version &>/dev/null 2>&1; then
        COMPOSE_VERSION=$(docker compose version 2>&1)
        log_ok "Docker Compose v2: $COMPOSE_VERSION"
    else
        log_fail "Docker Compose Plugin (v2): nicht gefunden"
        log_info "Installieren: apt install -y docker-compose-plugin"
        log_info "WICHTIG: 'docker compose' (kein Bindestrich) ist Pflicht"
    fi

    # Läuft Docker?
    if docker info &>/dev/null 2>&1; then
        log_ok "Docker-Daemon: läuft"
    else
        log_fail "Docker-Daemon: läuft NICHT"
        log_info "Starten mit: sudo systemctl start docker"
    fi
else
    log_fail "Docker: NICHT installiert"
    log_info "Installieren mit: bash ansible/roles/docker/tasks/main.yml"
    log_info "WICHTIG: Nicht docker.io aus apt verwenden — docker-ce aus Docker-Repo nutzen"
fi

echo ""

# ─── 7. Sicherheits-Tools ───────────────────────────────────────────────────
echo "[ Sicherheits-Tools ]"

# gitleaks — Secret-Scanner
if command -v gitleaks &>/dev/null; then
    log_ok "gitleaks: $(gitleaks version 2>&1 | head -1)"
else
    log_warn "gitleaks: nicht installiert"
    log_info "Installieren: bash scripts/setup/02_configure_git.sh"
    log_info "Oder manuell: https://github.com/gitleaks/gitleaks/releases"
fi

# shellcheck — Shell-Skript-Linter
if command -v shellcheck &>/dev/null; then
    log_ok "shellcheck: $(shellcheck --version 2>&1 | head -2 | tail -1)"
else
    log_warn "shellcheck: nicht installiert — apt install -y shellcheck"
fi

# yamllint
if command -v yamllint &>/dev/null; then
    log_ok "yamllint: $(yamllint --version 2>&1)"
else
    log_warn "yamllint: nicht installiert — pip3 install yamllint"
fi

echo ""

# ─── 8. SSH-Keys ────────────────────────────────────────────────────────────
echo "[ SSH-Konfiguration ]"

# ed25519 Key vorhanden?
if [ -f ~/.ssh/id_ed25519 ]; then
    log_ok "SSH ed25519 Key: vorhanden (~/.ssh/id_ed25519)"
elif [ -f ~/.ssh/id_ed25519_proxmox ]; then
    log_ok "SSH ed25519 Key: vorhanden (~/.ssh/id_ed25519_proxmox)"
else
    log_warn "Kein SSH ed25519 Key gefunden"
    log_info "Erstellen: ssh-keygen -t ed25519 -C 'proxmox-control' -f ~/.ssh/id_ed25519_proxmox"
fi

# RSA-Keys warnen (veraltet)
if [ -f ~/.ssh/id_rsa ]; then
    log_warn "RSA-Key gefunden (~/.ssh/id_rsa) — veraltet, bitte ed25519 verwenden"
fi

echo ""

# ─── 9. Ansible Vault ───────────────────────────────────────────────────────
echo "[ Ansible Vault ]"

VAULT_PASS_FILE="${ANSIBLE_VAULT_PASSWORD_FILE:-$HOME/.vault_pass.txt}"

if [ -f "$VAULT_PASS_FILE" ]; then
    VAULT_PERMS=$(stat -c "%a" "$VAULT_PASS_FILE" 2>/dev/null || echo "?")
    if [ "$VAULT_PERMS" = "600" ]; then
        log_ok "Vault-Passwort-Datei: $VAULT_PASS_FILE (Rechte: 600 ✓)"
    else
        log_warn "Vault-Passwort-Datei: $VAULT_PASS_FILE hat Rechte $VAULT_PERMS — sollte 600 sein"
        log_info "Korrigieren: chmod 600 $VAULT_PASS_FILE"
    fi
else
    log_warn "Vault-Passwort-Datei nicht gefunden: $VAULT_PASS_FILE"
    log_info "Initialisieren: bash scripts/setup/03_init_ansible_vault.sh"
fi

echo ""

# ─── 10. Ergebnis ───────────────────────────────────────────────────────────
echo "============================================================"
echo "  Preflight-Ergebnis"
echo "============================================================"

if [ "$FAILED" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
    echo -e "${GREEN}  Alle Prüfungen bestanden! Das System ist bereit.${NC}"
    echo ""
    echo "  Nächster Schritt: claude (Claude Code starten)"
elif [ "$FAILED" -eq 0 ]; then
    echo -e "${YELLOW}  $WARNINGS Warnung(en) — Grundfunktion OK, aber bitte Warnungen beheben.${NC}"
    echo ""
    echo "  Nächster Schritt: bash scripts/setup/01_install_claude_code.sh"
else
    echo -e "${RED}  $FAILED Fehler und $WARNINGS Warnung(en) gefunden!${NC}"
    echo -e "${RED}  Bitte alle FEHLER (✗) beheben bevor du weitermachst.${NC}"
    echo ""
    echo "  Hilfe: docs/knowledge/claude_code.md lesen"
    echo "         docs/knowledge/troubleshooting_and_security_hardening.md"
    exit 1
fi

echo ""
