# Git — Wissensdatenbank
# Stand: 2026-04

## 1. Grundlegende Git-Befehle

```bash
git init                           # Neues Repository initialisieren
git clone <url>                    # Repository klonen
git status                         # Änderungen anzeigen
git add <datei>                    # Datei zum Staging hinzufügen
git add -p                         # Interaktiv Teile hinzufügen
git commit -m "Nachricht"         # Commit erstellen
git log --oneline                  # Kompakte Log-Ansicht
git log --graph --oneline         # Grafischer Verlauf
git diff                           # Unstaged Änderungen
git diff --staged                  # Staged Änderungen
git diff HEAD~1                    # Vergleich mit letztem Commit
```

## 2. Branches

```bash
git branch                         # Branches anzeigen
git branch <name>                  # Branch erstellen
git checkout <name>                # Branch wechseln
git checkout -b <name>             # Branch erstellen und wechseln
git switch -c <name>               # Modernere Alternative
git merge <branch>                 # Branch mergen
git branch -d <branch>             # Branch löschen (lokal)
git push origin --delete <branch>  # Branch löschen (remote)
```

## 3. Remote-Operationen

```bash
git remote -v                      # Remotes anzeigen
git remote add origin <url>        # Remote hinzufügen
git push -u origin <branch>       # Push + Tracking setzen
git fetch origin                   # Änderungen holen (nicht mergen)
git pull origin <branch>           # Fetch + Merge
git push origin <branch>           # Änderungen hochladen
```

## 4. Git Sicherheit

### 4.1 .gitignore
```bash
# .gitignore prüfen ob Datei ignoriert wird
git check-ignore -v datei.env

# Bereits getrackte Datei aus Git entfernen (aber lokal behalten)
git rm --cached datei.env
echo "datei.env" >> .gitignore
git commit -m "Remove tracked secret file"
```

### 4.2 Pre-Commit Hooks (Gitleaks)
```bash
# Hook-Datei: .git/hooks/pre-commit
#!/usr/bin/env bash
# Verhindert Commit wenn Secrets gefunden werden
gitleaks protect --staged --verbose
if [ $? -ne 0 ]; then
    echo "FEHLER: Mögliche Secrets gefunden! Commit abgebrochen."
    echo "Prüfe die Ausgabe oben und entferne Secrets."
    exit 1
fi
```

### 4.3 Secret aus Git-Historie entfernen
```bash
# WARNUNG: Ändert die Git-Historie — alle Mitarbeiter müssen neu klonen!
# Tool: git-filter-repo (besser als filter-branch)
pip3 install git-filter-repo

# Datei komplett aus Historie entfernen
git filter-repo --path secrets.yml --invert-paths

# String aus allen Commits entfernen
git filter-repo --replace-text <(echo "ECHTES_PASSWORD==>ENTFERNT")

# Nach dem Bereinigen: Force-Push erforderlich
# ⚠️  ACHTUNG — DESTRUKTIV: Überschreibt Remote-Historie
git push origin --force --all
git push origin --force --tags
```

## 5. Git Workflow für dieses Projekt

### 5.1 Feature-Branch Workflow
```bash
# 1. Neuen Branch erstellen
git checkout -b feature/matrix-setup

# 2. Änderungen machen und committen
git add ansible/roles/matrix_synapse/
git commit -m "Add Matrix Synapse Ansible role

- PostgreSQL 16 setup
- Redis 7 setup
- Synapse container with security hardening
- Coturn TURN server
- Nginx reverse proxy with TLS"

# 3. Vor Push: Secret-Scan durchführen
gitleaks detect --source . --verbose

# 4. Push
git push -u origin feature/matrix-setup

# 5. Pull Request erstellen (in GitHub/Gitea)
```

### 5.2 Commit-Nachrichten Format
```
# Format: <Typ>: <Kurzbeschreibung> (max. 72 Zeichen)
# Leerzeile
# <Detaillierte Beschreibung (optional)>

# Typen:
feat:     Neue Funktion
fix:      Bugfix
docs:     Dokumentation
style:    Formatierung (kein Code-Änderung)
refactor: Code-Umstrukturierung
test:     Tests
chore:    Wartung (Build-System, Dependencies)
security: Sicherheitsfix

# Beispiele:
feat: Add Matrix Synapse Ansible role with full stack
fix: Correct nginx proxy_pass trailing slash issue
security: Enforce no-new-privileges in all containers
docs: Add troubleshooting guide for PBS connection
```

## 6. Nützliche Git-Befehle

```bash
# Letzten Commit rückgängig machen (Änderungen bleiben)
git reset HEAD~1

# Alle nicht-committeten Änderungen verwerfen
# ⚠️  ACHTUNG — DESTRUKTIV: Geht nicht wieder her!
git checkout -- .

# Datei auf Stand des letzten Commits zurücksetzen
git checkout -- pfad/zur/datei

# Tag erstellen
git tag -a v1.0.0 -m "Version 1.0.0"
git push origin --tags

# Stash (temporär wegräumen)
git stash                          # Änderungen weglegen
git stash pop                      # Änderungen zurückholen
git stash list                     # Gespeicherte Stashes anzeigen

# Blame (wer hat was geändert)
git blame datei.yml

# Suche in Commits
git log --grep="matrix"            # Commits mit "matrix" in Nachricht
git log -S "Suchbegriff"          # Commits die diesen Code hinzufügten
```

## 7. Git-Konfiguration

```bash
# Globale Konfiguration
git config --global user.name "<DEIN_NAME>"
git config --global user.email "<DEINE_EMAIL>"
git config --global core.editor vim
git config --global pull.rebase false  # Merge statt Rebase beim Pull
git config --global init.defaultBranch main

# Signierende Commits mit GPG
git config --global user.signingkey <GPG_KEY_ID>
git config --global commit.gpgsign true
```
