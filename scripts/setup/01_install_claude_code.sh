#!/usr/bin/env bash
# =============================================================================
# DATEI:        01_install_claude_code.sh
# ZWECK:        Installiert Claude Code sicher via offiziellem Installer.
#               Richtet den API-Key sicher über das Shell-Profil ein.
# AUFRUFEN:     bash scripts/setup/01_install_claude_code.sh
# VORAUSSETZUNGEN:
#   - Debian 12/13 oder Ubuntu 22-25 (amd64)
#   - curl installiert: apt install -y curl
#   - Internetverbindung
#   - Normaler Benutzer (nicht root empfohlen)
# SICHERHEIT:
#   - Backup-Verhalten: keines (nur Installation)
#   - Destruktiv: NEIN
#   - Rollback: claude kann deinstalliert werden — Pfad: ~/.claude/
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
echo "  Claude Code Installation"
echo "  Quelle: https://claude.ai/install.sh (offizieller Installer)"
echo "============================================================"
echo ""

# ─── 1. Voraussetzungen prüfen ──────────────────────────────────────────────
echo "[ Voraussetzungen ]"

# curl wird für den Download benötigt
if ! command -v curl &>/dev/null; then
    log_fail "curl ist nicht installiert!"
    log_info "Installieren: sudo apt install -y curl"
    exit 1
fi
log_ok "curl: verfügbar"

# Betriebssystem prüfen
if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    log_info "Betriebssystem: $PRETTY_NAME"
fi

echo ""

# ─── 2. Bereits installiert? ────────────────────────────────────────────────
echo "[ Installations-Status ]"

if command -v claude &>/dev/null; then
    CURRENT_VERSION=$(claude --version 2>&1 | head -1)
    log_warn "Claude Code ist bereits installiert: $CURRENT_VERSION"
    echo ""
    read -r -p "  Trotzdem (neu) installieren? [j/N] " ANSWER
    if [[ ! "$ANSWER" =~ ^[jJyY]$ ]]; then
        log_info "Installation abgebrochen. Aktuell: $CURRENT_VERSION"
        exit 0
    fi
fi

echo ""

# ─── 3. Claude Code installieren ────────────────────────────────────────────
echo "[ Installation ]"
log_info "Lade offiziellen Installer von https://claude.ai/install.sh..."
log_info "Dies kann eine Minute dauern..."

# Installer herunterladen und ausführen
# SICHERHEIT: Wir nutzen den offiziellen Installer von Anthropic.
# Der Installer installiert Claude Code für den aktuellen Benutzer.
if curl -fsSL https://claude.ai/install.sh | bash; then
    log_ok "Claude Code erfolgreich installiert!"
else
    log_fail "Installation fehlgeschlagen!"
    log_info "Alternative: npm install -g @anthropic-ai/claude-code (braucht Node.js)"
    exit 1
fi

# PATH aktualisieren damit claude direkt gefunden wird
# shellcheck disable=SC1090
source ~/.bashrc 2>/dev/null || true
export PATH="$HOME/.local/bin:$PATH"

# Installation verifizieren
if command -v claude &>/dev/null; then
    INSTALLED_VERSION=$(claude --version 2>&1 | head -1)
    log_ok "Verifiziert: $INSTALLED_VERSION"
else
    log_warn "claude-Befehl nicht im PATH — neues Terminal öffnen oder:"
    log_info "  source ~/.bashrc"
    log_info "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

echo ""

# ─── 4. API-Key sicher einrichten ───────────────────────────────────────────
echo "[ API-Key Konfiguration ]"

# Prüfen ob API-Key bereits gesetzt ist
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    KEY_PREVIEW="${ANTHROPIC_API_KEY:0:8}****"
    log_ok "ANTHROPIC_API_KEY ist bereits gesetzt ($KEY_PREVIEW)"
else
    log_warn "ANTHROPIC_API_KEY ist nicht gesetzt"
    echo ""
    echo "  Der API-Key wird benötigt um Claude Code zu verwenden."
    echo "  Du findest ihn unter: https://console.anthropic.com/settings/keys"
    echo ""
    echo "  SICHERHEIT: Der Key wird in ~/.anthropic_secrets gespeichert"
    echo "              (nicht in .bashrc, besser isolierbar)"
    echo ""

    read -r -p "  API-Key jetzt einrichten? [j/N] " SETUP_KEY
    if [[ "$SETUP_KEY" =~ ^[jJyY]$ ]]; then
        read -r -s -p "  API-Key eingeben (wird nicht angezeigt): " API_KEY
        echo ""

        # Grundlegende Validierung: Key beginnt mit 'sk-ant-'
        if [[ "$API_KEY" != sk-ant-* ]]; then
            log_warn "Key-Format ungewöhnlich (erwartet: sk-ant-... Format)"
            read -r -p "  Trotzdem speichern? [j/N] " CONFIRM
            if [[ ! "$CONFIRM" =~ ^[jJyY]$ ]]; then
                log_info "Key nicht gespeichert — manuell setzen mit:"
                log_info "  export ANTHROPIC_API_KEY='<DEIN_API_KEY>'"
                exit 0
            fi
        fi

        # Key sicher in separater Datei speichern (600 Rechte)
        SECRETS_FILE="$HOME/.anthropic_secrets"
        cat > "$SECRETS_FILE" << SECRETEOF
# Anthropic API-Key — NIEMALS teilen oder ins Repo committen!
# Diese Datei liegt in .gitignore und wird nicht verfolgt.
export ANTHROPIC_API_KEY='${API_KEY}'
SECRETEOF
        chmod 600 "$SECRETS_FILE"
        log_ok "API-Key in $SECRETS_FILE gespeichert (Rechte: 600)"

        # Aktivierungs-Zeile in .bashrc hinzufügen (falls noch nicht vorhanden)
        BASHRC="$HOME/.bashrc"
        SOURCE_LINE="[ -f ~/.anthropic_secrets ] && source ~/.anthropic_secrets"
        if ! grep -qF "anthropic_secrets" "$BASHRC" 2>/dev/null; then
            {
                echo ""
                echo "# Claude Code API-Key (automatisch von 01_install_claude_code.sh)"
                echo "$SOURCE_LINE"
            } >> "$BASHRC"
            log_ok "Aktivierungs-Zeile zu $BASHRC hinzugefügt"
        else
            log_ok "Aktivierungs-Zeile bereits in $BASHRC vorhanden"
        fi

        # Sofort aktiv machen
        export ANTHROPIC_API_KEY="$API_KEY"
        log_ok "API-Key für diese Session aktiviert"
    else
        log_info "Key nicht eingerichtet. Manuell setzen:"
        log_info "  export ANTHROPIC_API_KEY='<DEIN_API_KEY>'"
    fi
fi

echo ""

# ─── 5. .claudeignore erstellen ─────────────────────────────────────────────
echo "[ .claudeignore ]"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLAUDEIGNORE_FILE="$REPO_ROOT/.claudeignore"

if [ -f "$CLAUDEIGNORE_FILE" ]; then
    log_ok ".claudeignore existiert bereits: $CLAUDEIGNORE_FILE"
else
    log_warn ".claudeignore nicht gefunden — erstelle..."
    cat > "$CLAUDEIGNORE_FILE" << 'IGNEOF'
.env
*.env.*
*.key
*.pem
id_rsa
id_ed25519
vault-password.txt
vault_pass*
secrets.yml
data/
volumes/
backups/
docs/private/
IGNEOF
    log_ok ".claudeignore erstellt"
fi

echo ""

# ─── 6. Erste Schritte ──────────────────────────────────────────────────────
echo "============================================================"
echo "  Installation abgeschlossen!"
echo "============================================================"
echo ""
echo "  Nächste Schritte:"
echo ""
echo "  1. Neues Terminal öffnen (oder: source ~/.bashrc)"
echo "  2. Claude Code starten:     claude"
echo "  3. Im Browser anmelden (wird automatisch geöffnet)"
echo "  4. Diagnose:                claude doctor"
echo ""
echo "  Wichtige Slash-Befehle in Claude Code:"
echo "    /help    — Alle Befehle anzeigen"
echo "    /init    — CLAUDE.md für Projekt erstellen"
echo "    /doctor  — Verbindung prüfen"
echo "    /model   — Modell wechseln"
echo ""
