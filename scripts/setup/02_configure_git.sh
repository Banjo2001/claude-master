#!/usr/bin/env bash
# =============================================================================
# DATEI:        02_configure_git.sh
# ZWECK:        Git-Grundkonfiguration + gitleaks als Pre-Commit-Hook.
#               Verhindert, dass Secrets versehentlich in Git-Commits landen.
# AUFRUFEN:     GIT_USER_NAME="Max Mustermann" GIT_USER_EMAIL="max@example.com" \
#               bash scripts/setup/02_configure_git.sh
# VORAUSSETZUNGEN:
#   - git installiert: apt install -y git
#   - Im Git-Repository ausführen
#   - GIT_USER_NAME und GIT_USER_EMAIL als Umgebungsvariablen oder interaktiv
# SICHERHEIT:
#   - Backup-Verhalten: .gitconfig wird via 'git config' angepasst (nicht überschrieben)
#   - Destruktiv: NEIN
#   - Rollback: git config --global --unset user.name
# VERSION:      1.0.0 | Stand: 2026-04
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

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
echo "  Git-Konfiguration + gitleaks Pre-Commit-Hook"
echo "============================================================"
echo ""

# ─── 1. Git prüfen ──────────────────────────────────────────────────────────
echo "[ Git ]"

if ! command -v git &>/dev/null; then
    log_fail "git ist nicht installiert!"
    log_info "Installieren: sudo apt install -y git"
    exit 1
fi
log_ok "git: $(git --version)"

# Im Git-Repository?
if ! git rev-parse --git-dir &>/dev/null; then
    log_fail "Nicht in einem Git-Repository!"
    log_info "Repository initialisieren: git init"
    exit 1
fi
REPO_ROOT=$(git rev-parse --show-toplevel)
log_ok "Repository: $REPO_ROOT"

echo ""

# ─── 2. Git-Benutzer konfigurieren ──────────────────────────────────────────
echo "[ Git-Benutzer ]"

# Name: aus Umgebungsvariable oder interaktiv abfragen
if [ -n "${GIT_USER_NAME:-}" ]; then
    USER_NAME="$GIT_USER_NAME"
    log_info "Name aus Umgebungsvariable: $USER_NAME"
else
    # Aktuellen Wert zeigen
    CURRENT_NAME=$(git config --global user.name 2>/dev/null || echo "")
    if [ -n "$CURRENT_NAME" ]; then
        log_info "Aktueller Name: $CURRENT_NAME"
        read -r -p "  Neuen Namen eingeben (Enter = behalten): " USER_NAME
        USER_NAME="${USER_NAME:-$CURRENT_NAME}"
    else
        read -r -p "  Git-Benutzername (z.B. 'Max Mustermann'): " USER_NAME
    fi
fi

if [ -z "$USER_NAME" ]; then
    log_fail "Kein Benutzername angegeben!"
    exit 1
fi

git config --global user.name "$USER_NAME"
log_ok "user.name gesetzt: $USER_NAME"

# E-Mail: aus Umgebungsvariable oder interaktiv
if [ -n "${GIT_USER_EMAIL:-}" ]; then
    USER_EMAIL="$GIT_USER_EMAIL"
    log_info "E-Mail aus Umgebungsvariable: $USER_EMAIL"
else
    CURRENT_EMAIL=$(git config --global user.email 2>/dev/null || echo "")
    if [ -n "$CURRENT_EMAIL" ]; then
        log_info "Aktuelle E-Mail: $CURRENT_EMAIL"
        read -r -p "  Neue E-Mail eingeben (Enter = behalten): " USER_EMAIL
        USER_EMAIL="${USER_EMAIL:-$CURRENT_EMAIL}"
    else
        read -r -p "  Git-E-Mail (z.B. 'max@example.com'): " USER_EMAIL
    fi
fi

if [ -z "$USER_EMAIL" ]; then
    log_fail "Keine E-Mail angegeben!"
    exit 1
fi

git config --global user.email "$USER_EMAIL"
log_ok "user.email gesetzt: $USER_EMAIL"

echo ""

# ─── 3. Git-Basis-Konfiguration ─────────────────────────────────────────────
echo "[ Git-Basis-Konfiguration ]"

# Standardbranch: main (nicht master)
git config --global init.defaultBranch main
log_ok "init.defaultBranch: main"

# Pull-Verhalten: merge statt rebase (sicherer für Anfänger)
git config --global pull.rebase false
log_ok "pull.rebase: false (merge)"

# Editor: nano ist für Anfänger einfacher als vim
git config --global core.editor nano
log_ok "core.editor: nano"

# Farbausgabe aktivieren
git config --global color.ui auto
log_ok "color.ui: auto"

# Zeilenenden: LF (Linux-Standard, wichtig für Skripte)
git config --global core.autocrlf false
log_ok "core.autocrlf: false (LF)"

# Globale .gitignore (für Editor-Dateien etc.)
GLOBAL_GITIGNORE="$HOME/.gitignore_global"
if [ ! -f "$GLOBAL_GITIGNORE" ]; then
    cat > "$GLOBAL_GITIGNORE" << 'EOF'
# Globale .gitignore — Editor und OS-spezifische Dateien
.DS_Store
Thumbs.db
*.swp
*.swo
.idea/
.vscode/settings.json
EOF
    git config --global core.excludesfile "$GLOBAL_GITIGNORE"
    log_ok "Globale .gitignore: $GLOBAL_GITIGNORE"
fi

echo ""

# ─── 4. gitleaks installieren ───────────────────────────────────────────────
echo "[ gitleaks Installation ]"

GITLEAKS_VERSION="8.21.2"
GITLEAKS_URL="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"
GITLEAKS_BIN="/usr/local/bin/gitleaks"

if command -v gitleaks &>/dev/null; then
    CURRENT_GL_VERSION=$(gitleaks version 2>&1 | head -1)
    log_ok "gitleaks bereits installiert: $CURRENT_GL_VERSION"
else
    log_info "gitleaks wird installiert (Version $GITLEAKS_VERSION)..."
    log_info "Quelle: $GITLEAKS_URL"

    # Download in temporäres Verzeichnis
    TMP_DIR=$(mktemp -d)
    # shellcheck disable=SC2064
    trap "rm -rf '$TMP_DIR'" EXIT

    if curl -fsSL "$GITLEAKS_URL" -o "$TMP_DIR/gitleaks.tar.gz"; then
        tar -xzf "$TMP_DIR/gitleaks.tar.gz" -C "$TMP_DIR" gitleaks
        sudo install -m 755 "$TMP_DIR/gitleaks" "$GITLEAKS_BIN"
        log_ok "gitleaks installiert: $GITLEAKS_BIN"
    else
        log_warn "Download fehlgeschlagen — gitleaks nicht installiert"
        log_info "Manuell installieren: https://github.com/gitleaks/gitleaks/releases"
    fi
fi

echo ""

# ─── 5. Pre-Commit-Hook einrichten ──────────────────────────────────────────
echo "[ Pre-Commit-Hook (gitleaks) ]"

# Hooks-Verzeichnis im Repository
HOOKS_DIR="$REPO_ROOT/.git/hooks"
HOOK_FILE="$HOOKS_DIR/pre-commit"

# Prüfen ob gitleaks verfügbar ist
if ! command -v gitleaks &>/dev/null; then
    log_warn "gitleaks nicht gefunden — Pre-Commit-Hook NICHT eingerichtet"
    log_info "Hook ohne gitleaks ist wirkungslos"
else
    # Backup falls bereits ein Hook existiert
    if [ -f "$HOOK_FILE" ]; then
        cp "$HOOK_FILE" "${HOOK_FILE}.bak.$(date +%F)"
        log_info "Bestehender Hook gesichert: ${HOOK_FILE}.bak.$(date +%F)"
    fi

    # Pre-Commit-Hook schreiben
    cat > "$HOOK_FILE" << 'HOOKEOF'
#!/usr/bin/env bash
# Pre-Commit-Hook: Scannt staged Dateien auf Secrets (gitleaks)
# Automatisch eingerichtet von scripts/setup/02_configure_git.sh
set -euo pipefail

# Prüfen ob gitleaks vorhanden
if ! command -v gitleaks &>/dev/null; then
    echo "WARNUNG: gitleaks nicht gefunden — Secret-Scan übersprungen"
    exit 0
fi

echo "Scanne staged Dateien auf Secrets (gitleaks)..."

# Staged-only scannen (nur was committet wird, nicht das gesamte Repo)
if gitleaks protect --staged --config .gitleaks.toml --verbose 2>&1; then
    echo "OK: Keine Secrets in staged Dateien gefunden"
else
    echo ""
    echo "FEHLER: Mögliche Secrets in staged Dateien gefunden!"
    echo "Bitte die gemeldeten Dateien prüfen und Secrets entfernen."
    echo "Dann erneut: git add <datei> && git commit"
    exit 1
fi
HOOKEOF

    chmod +x "$HOOK_FILE"
    log_ok "Pre-Commit-Hook eingerichtet: $HOOK_FILE"
fi

echo ""

# ─── 6. Initialer gitleaks-Scan ─────────────────────────────────────────────
echo "[ Initialer Secret-Scan ]"

if command -v gitleaks &>/dev/null; then
    log_info "Scanne gesamtes Repository auf Secrets..."

    GITLEAKS_CONFIG=""
    if [ -f "$REPO_ROOT/.gitleaks.toml" ]; then
        GITLEAKS_CONFIG="--config $REPO_ROOT/.gitleaks.toml"
    fi

    # shellcheck disable=SC2086
    if gitleaks detect --source "$REPO_ROOT" $GITLEAKS_CONFIG --verbose 2>&1; then
        log_ok "Kein Secret im Repository-Verlauf gefunden!"
    else
        log_warn "Mögliche Secrets im Repository-Verlauf gefunden!"
        log_info "Bitte die Ausgabe prüfen und Secrets aus der Historie entfernen"
        log_info "Anleitung: docs/knowledge/git.md (Abschnitt: Secret aus Git-Historie entfernen)"
    fi
else
    log_warn "gitleaks nicht verfügbar — Scan übersprungen"
fi

echo ""

# ─── 7. Ergebnis ────────────────────────────────────────────────────────────
echo "============================================================"
echo "  Git-Konfiguration abgeschlossen!"
echo "============================================================"
echo ""
echo "  Konfiguriert:"
echo "    Name:    $USER_NAME"
echo "    E-Mail:  $USER_EMAIL"
echo "    Branch:  main"
echo "    Editor:  nano"
echo ""
echo "  Nächster Schritt: bash scripts/setup/03_init_ansible_vault.sh"
echo ""
