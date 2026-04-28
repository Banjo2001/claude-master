# Proxmox Infra Admin — Automatisierte Infrastruktur

Vollständig automatisierte, sichere und reproduzierbare Proxmox-Infrastruktur
mit Matrix Synapse, Nextcloud AIO und allen Sicherheits- und Automationsskripten.

**Für Anfänger gebaut:** Jede Datei enthält ausführliche Kommentare.

---

## Was ist in diesem Repository?

```
✓ Claude Code Setup + Automatisierung
✓ Proxmox VE 9.x + PBS 4.x API-Verbindungsschicht (Shell)
✓ Ansible Playbook: Matrix Synapse (vollständiger Stack)
✓ Ansible Playbook: Nextcloud AIO
✓ SSH-Hardening, Fail2Ban, UFW-Konfiguration
✓ Backup-Skripte + Restore-Tests
✓ Monitoring: SSL-Zertifikate, Dienste, Disk-Auslastung
✓ GitHub Actions: Lint + Secret-Scan
```

---

## Schnellstart (Schritt für Schritt)

> **WICHTIG:** Erst lesen, dann ausführen! Jedes Skript enthält ausführliche
> Kommentare die erklären was es tut.

### Schritt 1: Voraussetzungen prüfen

```bash
# Im LXC oder auf dem Control-Node ausführen:
bash scripts/setup/00_preflight_check.sh
```

Das Skript prüft ob folgendes installiert ist:
- git, curl, wget
- ansible (>= 2.17)
- docker + docker compose Plugin
- gitleaks (Secret-Scanner)
- ANTHROPIC_API_KEY ist gesetzt (für Claude Code)

### Schritt 2: Claude Code installieren

```bash
bash scripts/setup/01_install_claude_code.sh
```

Installiert Claude Code via offiziellem Installer. Nach der Installation:
```bash
claude --version    # Installiert?
claude             # Starten + im Browser anmelden
```

### Schritt 3: Git konfigurieren

```bash
# Umgebungsvariablen setzen:
export GIT_USER_NAME="<DEIN_NAME>"
export GIT_USER_EMAIL="<DEINE_EMAIL>"

bash scripts/setup/02_configure_git.sh
```

Richtet git-Benutzer ein und installiert gitleaks als Pre-Commit-Hook.

### Schritt 4: Ansible Vault einrichten

```bash
bash scripts/setup/03_init_ansible_vault.sh
```

Erstellt die Vault-Passwort-Datei **außerhalb** des Repos (in `~/.vault_pass.txt`).

### Schritt 5: .env-Datei erstellen

```bash
# Vorlage kopieren und ausfüllen:
cp .env.example .env
nano .env    # DEINE Werte eintragen
```

### Schritt 6: Proxmox API testen

```bash
# API-Verbindung testen:
bash scripts/proxmox/pve_api_test.sh
```

### Schritt 7: Ansible-Inventar befüllen

```bash
# Hosts eintragen:
nano ansible/inventories/prod/hosts.yml

# Globale Variablen setzen:
nano ansible/inventories/prod/group_vars/all/vars.yml

# Secrets via Vault setzen:
ansible-vault edit ansible/inventories/prod/group_vars/all/vault.yml \
  --vault-password-file ~/.vault_pass.txt

# (Empfohlen) Starke Zufalls-Secrets generieren statt manuell setzen:
bash scripts/setup/04_generate_secrets.sh
```

### Schritt 7b: Pre-Deploy-Validierung

```bash
# DNS-Records prüfen (Pflicht vor Let's Encrypt!):
bash scripts/setup/05_dns_preflight.sh

# Inventar + SSH + Vault validieren:
bash scripts/setup/06_inventory_check.sh
```

### Schritt 8: Ansible Dry-Run (BEVOR etwas deployed wird)

```bash
# IMMER zuerst --check --diff ausführen!
ansible-playbook ansible/playbooks/site.yml \
  --check --diff \
  --vault-password-file ~/.vault_pass.txt
```

### Schritt 9: Deploy (wenn Dry-Run sauber war)

```bash
# Matrix Synapse deployen:
ansible-playbook ansible/playbooks/matrix_synapse.yml \
  --vault-password-file ~/.vault_pass.txt

# Nextcloud AIO deployen:
ansible-playbook ansible/playbooks/nextcloud_aio.yml \
  --vault-password-file ~/.vault_pass.txt
```

---

## Architektur-Übersicht

```
Internet
    │
    │ HTTPS/443 (TLS via Let's Encrypt)
    ▼
┌─────────────────────────────────────────────────────────┐
│ Hetzner Dedicated Server                                 │
│                                                          │
│  ┌─────────────────────────────────────────────────┐    │
│  │ Proxmox VE 9.x (Debian 13 Trixie Basis)         │    │
│  │                                                  │    │
│  │  ┌──────────────┐  ┌──────────────────────────┐ │    │
│  │  │ LXC: Claude  │  │ VM: Matrix Synapse         │ │    │
│  │  │ Code Control │  │  ├ Nginx (Reverse Proxy)  │ │    │
│  │  │ Node         │  │  ├ Synapse (Docker)       │ │    │
│  │  └──────────────┘  │  ├ PostgreSQL 16           │ │    │
│  │                    │  ├ Redis 7                 │ │    │
│  │  ┌──────────────┐  │  ├ Coturn (TURN)           │ │    │
│  │  │ VM: Nextcloud│  │  └ Prometheus + Grafana   │ │    │
│  │  │ AIO          │  └──────────────────────────┘ │    │
│  │  │  ├ Mastercon │                                │    │
│  │  │  ├ Nextcloud │  ┌──────────────────────────┐ │    │
│  │  │  ├ PostgreSQL│  │ Proxmox Backup Server    │ │    │
│  │  │  └ Redis     │  │ PBS 4.x                  │ │    │
│  │  └──────────────┘  └──────────────────────────┘ │    │
│  └─────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
         │
         │ SFTP/Restic (offsite Backup)
         ▼
┌─────────────────┐
│ Hetzner Storage │
│ Box             │
└─────────────────┘
```

---

## Sicherheitskonzept

| Bereich | Maßnahme |
|---------|----------|
| SSH | Nur ed25519, kein Root-Login, kein Passwort |
| Firewall | UFW Default-Deny + explizite Regeln |
| Brute-Force | Fail2Ban für SSH + Matrix + Nextcloud |
| Secrets | Ansible Vault (AES-256), niemals im Repo |
| Docker | no-new-privileges + cap_drop: ALL |
| Updates | unattended-upgrades (Sicherheitsupdates automatisch) |
| Zertifikate | Let's Encrypt, automatische Erneuerung |
| Backup | PBS + Hetzner Storage Box (3-2-1-Regel) |
| Monitoring | Prometheus + Grafana + Alerting |
| Audit | gitleaks Pre-Commit-Hook + GitHub Actions |

---

## Wichtige Pfade

```bash
# Wissensdatenbanken (immer zuerst lesen!):
docs/knowledge/legal_and_security_rules.md
docs/knowledge/claude_code.md
docs/knowledge/<Thema>.md

# Architektur-Dokumentation:
docs/architecture/overview.md

# Runbooks (Schritt-für-Schritt-Anleitungen):
docs/runbooks/proxmox_maintenance.md
docs/runbooks/matrix_admin.md
docs/runbooks/nextcloud_admin.md
docs/runbooks/backup_restore.md
docs/runbooks/incident_response.md

# Ansible:
ansible/playbooks/site.yml          # Master-Playbook
ansible/playbooks/matrix_synapse.yml
ansible/playbooks/nextcloud_aio.yml
ansible/inventories/prod/hosts.yml   # ← Hier IPs eintragen!

# Docker Compose (Referenz):
docker/matrix-synapse/compose.yml
docker/nextcloud-aio/compose.yml

# Proxmox API:
proxmox-api/lib/pve_api.sh          # PVE Shell-Bibliothek
proxmox-api/lib/pbs_api.sh          # PBS Shell-Bibliothek
```

---

## Hilfe und Troubleshooting

Bei Problemen:
1. `docs/knowledge/troubleshooting_and_security_hardening.md` lesen
2. Logs prüfen: `journalctl -u <dienst> -n 50`
3. Docker: `docker compose logs -f <service>`
4. Ansible: `ansible-playbook ... -vvv` (verbose)
5. Claude Code fragen: `claude` → Frage stellen

---

## Lizenz / Nutzung

Diese Codebasis ist für den privaten Betrieb gedacht.
Alle Konfigurationen müssen vor dem Einsatz auf die eigene Umgebung
angepasst werden (Platzhalter ersetzen, Secrets via Vault setzen).
