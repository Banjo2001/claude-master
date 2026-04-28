#!/usr/bin/env bash
# =============================================================================
# DATEI:        scripts/security/audit_secrets.sh
# ZWECK:        Repository auf versehentlich eingecheckte Secrets prüfen
# AUFRUFEN:     ./audit_secrets.sh [REPO_PATH]
# VORAUSSETZUNGEN:
#   - gitleaks installiert (scripts/setup/02_configure_git.sh führt das durch)
#   - git repository
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

log_info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_section() { echo -e "\n${CYAN}━━━ $* ━━━${NC}"; }

# ─── Konfiguration ────────────────────────────────────────────────────────────
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="${1:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
readonly GITLEAKS_CONF="${REPO_ROOT}/.gitleaks.toml"

log_section "Secret-Audit mit gitleaks"
log_info "Repository: ${REPO_ROOT}"

# ─── gitleaks prüfen ──────────────────────────────────────────────────────────
if ! command -v gitleaks &> /dev/null; then
    log_error "gitleaks nicht gefunden!"
    log_error "Installieren mit: scripts/setup/02_configure_git.sh"
    exit 1
fi

GITLEAKS_VERSION="$(gitleaks version 2>/dev/null || echo 'unbekannt')"
log_info "gitleaks Version: ${GITLEAKS_VERSION}"

# ─── Scan: Gesamtes Repository (alle Commits) ─────────────────────────────────
log_section "Scan 1: Vollständiger Repository-History-Scan"
log_info "Scannt alle Commits — kann etwas dauern..."

GITLEAKS_ARGS=(
    "detect"
    "--source" "${REPO_ROOT}"
    "--verbose"
)

if [[ -f "${GITLEAKS_CONF}" ]]; then
    GITLEAKS_ARGS+=("--config" "${GITLEAKS_CONF}")
    log_info "Konfiguration: ${GITLEAKS_CONF}"
fi

SECRETS_FOUND=0
if ! gitleaks "${GITLEAKS_ARGS[@]}" 2>&1; then
    SECRETS_FOUND=1
fi

# ─── Scan: Working Directory (unstaged) ───────────────────────────────────────
log_section "Scan 2: Ungecheckte Änderungen (Working Directory)"
log_info "Prüfe lokale Änderungen die noch nicht committed sind..."

NO_GIT_ARGS=(
    "detect"
    "--source" "${REPO_ROOT}"
    "--no-git"
    "--verbose"
)

if [[ -f "${GITLEAKS_CONF}" ]]; then
    NO_GIT_ARGS+=("--config" "${GITLEAKS_CONF}")
fi

if ! gitleaks "${NO_GIT_ARGS[@]}" 2>&1; then
    SECRETS_FOUND=1
fi

# ─── Manuelle Muster-Prüfung ──────────────────────────────────────────────────
log_section "Scan 3: Manuelle Muster-Prüfung"
log_info "Prüfe auf bekannte Muster..."

PATTERNS=(
    "password\s*=\s*['\"][^'\"<{]"
    "secret\s*=\s*['\"][^'\"<{]"
    "token\s*=\s*['\"][^'\"<{]"
    "api_key\s*=\s*['\"][^'\"<{]"
    "private_key\s*=\s*['\"][^'\"<{]"
    "BEGIN (RSA|EC|OPENSSH) PRIVATE KEY"
)

PATTERN_FOUND=0
for PATTERN in "${PATTERNS[@]}"; do
    MATCHES=$(grep -rIni --include="*.yml" --include="*.yaml" \
        --include="*.env" --include="*.sh" --include="*.conf" \
        --include="*.json" \
        -E "${PATTERN}" "${REPO_ROOT}" \
        --exclude-dir=".git" \
        --exclude-dir="docs" 2>/dev/null || true)

    if [[ -n "${MATCHES}" ]]; then
        log_warn "Verdächtiges Muster gefunden ('${PATTERN}'):"
        echo "${MATCHES}" | head -20
        PATTERN_FOUND=1
    fi
done

if [[ "${PATTERN_FOUND}" -eq 0 ]]; then
    log_info "Keine verdächtigen Muster gefunden"
fi

# ─── Ergebnis ─────────────────────────────────────────────────────────────────
log_section "Ergebnis"

if [[ "${SECRETS_FOUND}" -eq 0 && "${PATTERN_FOUND}" -eq 0 ]]; then
    log_info "Audit bestanden — keine Secrets gefunden."
    exit 0
else
    log_error "Mögliche Secrets gefunden! Bitte prüfen und bereinigen."
    log_error "Anleitung: docs/knowledge/git.md (Abschnitt: Secret aus History entfernen)"
    log_warn "WICHTIG: Betroffene Secrets sofort rotieren, auch wenn sie aus History entfernt werden!"
    exit 1
fi
