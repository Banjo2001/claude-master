# Claude Code — Wissensdatenbank
# Stand: 2026-04 | Quelle: Anthropic Dokumentation + eigene Notizen

## 1. Überblick

Claude Code ist ein terminal-basierter Coding-Assistent von Anthropic.
Er integriert sich direkt in die Shell, liest und editiert Dateien,
führt Befehle aus und kann über MCP-Server mit externen Tools interagieren.

Unterstützte Plattformen: Linux, macOS, Windows (PowerShell/WSL)

## 2. Systemvoraussetzungen

- OS: Debian 10+, Ubuntu 20.04+, aktuelle macOS/Windows-Versionen
  Für LXC-Einsätze: Debian 12/13 oder Ubuntu 22–24 empfohlen
- RAM: Mindestens 4 GB, empfohlen 8 GB
- Account: Kostenpflichtiges Anthropic-Konto erforderlich
  (Gratis-Version von Claude.ai enthält Claude Code NICHT)
- Node.js: Für native Installation NICHT erforderlich;
  nur npm-Variante oder MCP-Server benötigen Node.js >= 18

## 3. Proxmox LXC Container Setup (empfohlene Umgebung)

### 3.1 Template herunterladen (auf dem Proxmox-Host)
```bash
# Template-Liste aktualisieren
pveam update
# Debian 12 Template herunterladen
pveam download local debian-12-standard_20240203_amd64.tar.zst
```

### 3.2 Container erstellen
```bash
# CTID = Container-ID (z.B. 101, 200, etc.)
# local-lvm:8 = 8 GB Festplattenplatz auf local-lvm Storage
# memory 4096 = 4 GB RAM
# cores 2 = 2 CPU-Kerne (für Claude Code ausreichend)
pct create <CTID> local:vztmpl/debian-12-standard_20240203_amd64.tar.zst \
  -hostname claude-code \
  -rootfs local-lvm:8 \
  -memory 4096 -cores 2 \
  -net0 name=eth0,bridge=vmbr0,ip=dhcp
```

### 3.3 Container starten und betreten
```bash
pct start <CTID>
pct console <CTID>
# Alternative für SSH-Zugriff:
# pct exec <CTID> -- bash
```

### 3.4 System im Container vorbereiten
```bash
# Pakete aktualisieren
apt update && apt full-upgrade -y
# Basis-Tools installieren (git für Repo, ripgrep für Code-Suche)
apt install -y curl git ripgrep wget ca-certificates
```

## 4. Claude Code installieren

### 4.1 Native Installer (EMPFOHLEN — kein Node.js nötig)
```bash
# Neueste Version
curl -fsSL https://claude.ai/install.sh | bash

# Spezifische Version installieren (für Reproduzierbarkeit empfohlen)
curl -fsSL https://claude.ai/install.sh | bash -s 2.1.118

# "latest" explizit:
curl -fsSL https://claude.ai/install.sh | bash -s latest

# Installation verifizieren:
claude --version
```

### 4.2 APT-Repository (Legacy-Methode)
```bash
# GPG-Schlüssel importieren
sudo install -d -m 0755 /etc/apt/keyrings
sudo curl -fsSL https://downloads.claude.ai/keys/claude-code.asc \
  -o /etc/apt/keyrings/claude-code.asc

# WICHTIG: Fingerprint prüfen!
# Erwartet: 31DD DE24 DDFA B679 F42D 7BD2 BAA9 29FF 1A7E CACE
gpg --show-keys /etc/apt/keyrings/claude-code.asc

# Repository hinzufügen
echo "deb [signed-by=/etc/apt/keyrings/claude-code.asc] \
https://downloads.claude.ai/claude-code/apt/stable stable main" | \
sudo tee /etc/apt/sources.list.d/claude-code.list

# Installieren
sudo apt update
sudo apt install claude-code -y
```

### 4.3 Via npm (benötigt Node.js >= 18)
```bash
# Nur wenn Node.js bereits installiert ist
npm install -g @anthropic-ai/claude-code
```

## 5. Konfiguration

### 5.1 Erste Anmeldung
```bash
# Claude Code starten — öffnet Browser zur Authentifizierung
claude
# Oder direkt API-Key setzen:
export ANTHROPIC_API_KEY="<DEIN_API_KEY>"
claude auth login
```

### 5.2 Konfigurationsdatei (~/.config/claude/settings.json)
```json
{
  "autoUpdatesChannel": "stable",
  "DISABLE_AUTOUPDATER": "1"
}
```
- `autoUpdatesChannel`: "stable" (empfohlen) oder "latest"
- `DISABLE_AUTOUPDATER`: "1" verhindert automatische Updates
  (gut für reproduzierbare Umgebungen)

### 5.3 Manuelles Update
```bash
claude update
# Oder spezifische Version:
claude install 2.1.118
```

## 6. Claude Code verwenden

### 6.1 Starten
```bash
# Interaktiv
claude
# Mit direkter Frage
claude "Erkläre mir dieses Skript: ./script.sh"
# Letzte Sitzung fortsetzen
claude -c
# Sitzung mit ID fortsetzen
claude -r <SESSION_ID>
```

### 6.2 Wichtige CLI-Flags
```bash
--model <modell>      # Modell wählen (z.B. claude-opus-4-7)
--add-dir <pfad>      # Zusätzliches Verzeichnis zugänglich machen
-c                    # Letzte Sitzung fortsetzen
-r <id>              # Bestimmte Sitzung fortsetzen
claude auth login     # Neu anmelden
claude auth logout    # Abmelden
claude update         # Update
claude doctor         # Diagnose bei Problemen
```

### 6.3 Slash-Befehle (innerhalb von Claude Code)
```
/help      — Alle Befehle anzeigen
/init      — CLAUDE.md für aktuelles Projekt erstellen
/doctor    — Diagnose (Verbindung, API-Key, etc.)
/context   — Kontext-Informationen anzeigen
/model     — Modell wechseln
/copy      — Letzten Output kopieren
/clear     — Kontext leeren
/exit      — Claude Code beenden
/resume    — Sitzung fortsetzen
/plan      — Aufgabe planen (ohne ausführen)
/batch     — Mehrere Aufgaben zusammenfassen
```

## 7. Sicherheitsempfehlungen für Claude Code

### 7.1 Zugriffseinschränkung
```bash
# Nur bestimmtes Verzeichnis zugänglich machen
claude --add-dir /home/admin/infra-admin

# Claude Code läuft als normaler Benutzer — NIEMALS als root starten!
```

### 7.2 API-Key sicher setzen
```bash
# Richtig: In Shell-Profil (nicht im Skript hardcoded)
echo 'export ANTHROPIC_API_KEY="<DEIN_KEY>"' >> ~/.bashrc
# Noch besser: Über eine secrets-Datei die NICHT im Repo liegt
source ~/.anthropic_secrets  # Diese Datei liegt in .gitignore
```

### 7.3 MCP-Server (Model Context Protocol)
```bash
# MCP-Server hinzufügen (z.B. für GitHub-Integration)
claude mcp add github -- node /pfad/zu/github-mcp-server.js

# Installierte MCP-Server anzeigen
claude mcp list
```

## 8. Proxmox VE Befehlsreferenz

### 8.1 Virtuelle Maschinen (VMs)
```bash
qm list                              # Alle VMs auflisten
qm create <id> ...                   # VM erstellen
qm set <id> <optionen>              # VM-Optionen setzen
qm start <id>                        # VM starten
qm shutdown <id>                     # VM sauber herunterfahren
qm stop <id>                         # VM sofort stoppen (Stromausfall-Simulation)
qm snapshot <id> <name>             # Snapshot erstellen
qm rollback <id> <name>             # Snapshot zurückspielen
qm clone <id> <neue-id>            # VM klonen
qm migrate <id> <node>             # VM migrieren
# ⚠️ DESTRUKTIV:
qm destroy <id>                      # VM löschen (unwiderruflich!)
```

### 8.2 LXC Container
```bash
pct list                             # Alle Container auflisten
pct create <id> <template> ...       # Container erstellen
pct start <id>                       # Container starten
pct stop <id>                        # Container stoppen
pct shutdown <id>                    # Container sauber herunterfahren
pct reboot <id>                      # Container neustarten
pct console <id>                     # Container-Konsole öffnen
pct enter <id>                       # In Container einloggen (direkt)
pct snapshot <id> <name>            # Snapshot erstellen
pct rollback <id> <name>            # Snapshot zurückspielen
pct migrate <id> <node>            # Container migrieren
# ⚠️ DESTRUKTIV:
pct destroy <id>                     # Container löschen (unwiderruflich!)
```

### 8.3 Storage & Netzwerk
```bash
pveam update                         # Template-Liste aktualisieren
pveam available                      # Verfügbare Templates anzeigen
pveam download <storage> <template>  # Template herunterladen
pvesm status                         # Storage-Status
pvesm add <type> <name> ...         # Storage hinzufügen
pvesm remove <name>                  # Storage entfernen
pve-firewall status                  # Firewall-Status
pve-firewall reload                  # Firewall neu laden
```

### 8.4 Benutzer & Rollen
```bash
pveum user add <user>@pve            # Benutzer anlegen
pveum role add <rolename> -privs ... # Rolle erstellen
pveum aclmod / -user <user>@pve -role <rolename>  # Rechte vergeben
```

## 9. Proxmox Backup Client (PBS)

### 9.1 Installation (Debian/Ubuntu)
```bash
# PBS-Client Repository hinzufügen
echo "deb [arch=amd64] http://download.proxmox.com/debian/pbs-client bullseye main" \
| sudo tee /etc/apt/sources.list.d/pbs-client.list

# Schlüssel importieren
sudo wget http://enterprise.proxmox.com/debian/proxmox-release-bullseye.gpg \
-O /etc/apt/trusted.gpg.d/proxmox-release-bullseye.gpg

# Installieren
sudo apt update && sudo apt install proxmox-backup-client -y
```

### 9.2 Backup-Operationen
```bash
# Backup erstellen (<PBS_IP> = IP des PBS, <Repo> = Repository-Name)
proxmox-backup-client backup root.pxar:/ --repository <PBS_IP>:<Repo>

# Mit Verschlüsselung (Schlüssel vorher erstellen):
proxmox-backup-client key create backup.key
proxmox-backup-client backup root.pxar:/ --repository <PBS_IP>:<Repo> --keyfile backup.key

# Backups auflisten
proxmox-backup-client list --repository <PBS_IP>:<Repo>

# Snapshots auflisten
proxmox-backup-client snapshot list --repository <PBS_IP>:<Repo>
```

## 10. Automatisierung vorbereiten

### 10.1 SSH-Schlüssel für Ansible erstellen
```bash
# ed25519 ist der modernste und sicherste SSH-Schlüsseltyp
ssh-keygen -t ed25519 -C "proxmox-controller" -f ~/.ssh/id_ed25519_proxmox

# Schlüssel auf Hosts verteilen
ssh-copy-id -i ~/.ssh/id_ed25519_proxmox.pub root@<PROXMOX_HOST>
ssh-copy-id -i ~/.ssh/id_ed25519_proxmox.pub root@<PBS_HOST>
```

### 10.2 Ansible einrichten
```bash
# Ansible installieren
sudo apt install -y ansible

# Community-Kollektionen installieren (für erweiterte Module)
ansible-galaxy collection install community.general
ansible-galaxy collection install community.docker

# Verbindung testen
ansible all -i inventories/prod/hosts.yml -m ping
```

## 11. Diagnose bei Problemen

```bash
claude doctor              # Claude Code Selbstdiagnose
claude --version          # Version prüfen
echo $ANTHROPIC_API_KEY   # API-Key gesetzt? (Wert nicht ausgeben!)
test -n "$ANTHROPIC_API_KEY" && echo "Key gesetzt" || echo "Key fehlt!"
```
