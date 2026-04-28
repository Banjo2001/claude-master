# CLAUDE.md — Proxmox Infra Admin Repository
# Arbeitsanweisung + Notizen + Changelog für Claude Code

> **Diese Datei steuert das Verhalten von Claude Code in diesem Projekt.**
> Claude Code liest sie beim Start und befolgt alle Regeln ohne Ausnahme.
> Zusätzlich enthält sie am Ende einen Changelog aller durchgeführten Aktionen.

---

## 1. Projektkontext und Ziel

**Was wird hier aufgebaut:**
Vollständig automatisierte, sichere und reproduzierbare Proxmox-Infrastruktur
mit Matrix Synapse (Chat), Nextcloud AIO (Cloud) und allen Automations- und
Sicherheitsskripten — als Anfänger-freundliche, kommentierte Codebasis.

**Ziel-Umgebung:**
- Proxmox VE 9.x (Basis: Debian 13 "Trixie")
- Proxmox Backup Server 4.x
- Gast-OS: Debian 12/13, Ubuntu 22.04/24.04
- Docker Compose v2 (Befehl: `docker compose`, KEIN Bindestrich)
- Ansible 2.17+
- SSH: nur ed25519 Keys
- Zeitzone: Europe/Berlin

**AKTUELLER STATUS:** Vorbereitung (kein Deploy auf echtem System)
Alle Skripte/Playbooks werden nur vorbereitet und auf Korrektheit geprüft.

---

## 2. Identität und Rolle (für Claude Code)

Claude Code agiert als **defensiver IT-Administrations-Assistent** und **Mentor**.

Das bedeutet:
- Jede Datei enthält ausführliche Kommentare (WAS + WARUM)
- Keine Schritte ohne Erklärung
- Keine Schritte ohne Rollback-Hinweis (wo relevant)
- Keine destruktiven Befehle ohne explizite Warnung

---

## 3. Sicherheitsregeln (UNVERHANDELBAR)

### 3.1 Wissensdatenbank lesen
Vor jeder technischen Entscheidung relevante Datei aus `docs/knowledge/` lesen:
- `docs/knowledge/legal_and_security_rules.md` — IMMER zuerst
- `docs/knowledge/claude_code.md` — für Claude Code Operationen
- Weitere je nach Aufgabe

### 3.2 Keine echten Secrets
Ausschließlich Platzhalter:
```
<DEIN_TOKEN>          — API-Tokens
<DEINE_DOMAIN>        — Domainnamen
<DEIN_USER>           — Benutzernamen
<DEIN_PASSWORT>       — Passwörter
192.0.2.10            — Platzhalter-IPv4 (RFC 5737 TEST-NET)
pve01.example.com     — Platzhalter-Hostname
```

### 3.3 Backup vor jeder Änderung
```bash
# SICHERUNG: Originaldatei sichern
cp /etc/datei /etc/datei.bak.$(date +%F)
```

### 3.4 Destruktive Befehle markieren
Vor rm -rf, dd, qm destroy, pct destroy, systemctl restart (Produktiv), etc.:
```bash
# ⚠️  ACHTUNG — DESTRUKTIV: Kann Datenverlust verursachen.
# Rollback: <konkreter Befehl>
```

### 3.5 Docker-Regeln
- Kein `:latest` (außer Nextcloud AIO Mastercontainer — ausdrücklich begründet)
- `no-new-privileges: true` + `cap_drop: ALL` in jedem Container
- Kein Root-User wo vermeidbar
- Kein Docker-Socket außer bei AIO-Mastercontainer

---

## 4. Was Claude Code NICHT tut

- Keine Playbooks ausführen (kein `ansible-playbook` ohne explizite Anweisung)
- Keine Docker Container starten (kein `docker compose up` ohne Anweisung)
- Keine Proxmox-API-Calls die Daten verändern
- Keine Dateien löschen ohne explizite Bestätigung
- Keine Commits ohne Aufforderung
- Keine echten Secrets ausgeben
- Nicht raten — bei Unklarheiten nachfragen

---

## 5. Notizen — Was wo wie gemacht wird

### 5.1 Repository-Struktur (Kurzübersicht)
```
infra-admin/
├── CLAUDE.md                 ← Diese Datei (Arbeitsanweisung + Log)
├── README.md                 ← Projekt-Übersicht + Schnellstart
├── .gitignore / .claudeignore← Secrets ausschließen (ERSTE Dateien!)
├── .env.example              ← Variablen-Vorlage (KEINE echten Werte)
│
├── docs/
│   ├── knowledge/            ← Wissensdatenbanken (15 Dateien)
│   ├── architecture/         ← Architektur-Diagramme
│   ├── runbooks/             ← Schritt-für-Schritt Anleitungen
│   └── changelogs/           ← Änderungsprotokolle
│
├── scripts/
│   ├── setup/                ← 00-03: Installation und Konfiguration
│   │   ├── 00_preflight_check.sh     ← Prüft Voraussetzungen
│   │   ├── 01_install_claude_code.sh ← Installiert Claude Code
│   │   ├── 02_configure_git.sh       ← Git + gitleaks Setup
│   │   └── 03_init_ansible_vault.sh  ← Ansible Vault initialisieren
│   ├── proxmox/              ← PVE Status, Snapshots, PBS-Prüfung
│   ├── security/             ← SSH Hardening, Fail2Ban, UFW, Audit
│   ├── backup/               ← Backup + Restore-Test
│   └── monitoring/           ← Dienste, Disk, SSL-Certs prüfen
│
├── proxmox-api/
│   ├── lib/pve_api.sh        ← Shell-Bibliothek für PVE REST-API
│   ├── lib/pbs_api.sh        ← Shell-Bibliothek für PBS REST-API
│   └── examples/             ← Beispiel-Skripte (list, snapshot, backup)
│
├── ansible/
│   ├── inventories/prod/     ← Produktiv-Inventar (Platzhalter-IPs)
│   ├── roles/common/         ← Basis: Updates, Zeitzone, SSH, UFW
│   ├── roles/docker/         ← Docker CE Installation
│   ├── roles/matrix_synapse/ ← Vollständiger Matrix-Stack
│   ├── roles/nextcloud_aio/  ← Nextcloud AIO Deploy
│   └── playbooks/            ← site.yml, matrix.yml, nextcloud.yml
│
├── docker/
│   ├── matrix-synapse/       ← Docker Compose Referenz (Matrix)
│   └── nextcloud-aio/        ← Docker Compose (Nextcloud AIO)
│
├── config/
│   ├── ssh/sshd_hardened.conf← SSH Hardening Config
│   ├── fail2ban/jail.local   ← Fail2Ban Konfiguration
│   ├── ufw/ufw_rules.sh      ← UFW Idempotentes Skript
│   └── sysctl/99-hardening.conf ← Kernel-Härtung
│
└── .github/workflows/
    ├── lint.yml              ← ansible-lint + yamllint bei Push
    └── security_scan.yml     ← gitleaks Secret-Scan bei Push
```

### 5.2 Deployment-Reihenfolge (wenn es so weit ist)

**WICHTIG:** Alles ist momentan nur Vorbereitung. Deploy-Reihenfolge:

```
1. Proxmox VE 9.x auf Hetzner installieren (Rescue-Modus)
2. Proxmox Backup Server 4.x installieren (separater Host)
3. LXC Container für Claude Code erstellen (CTID z.B. 100)
4. Im LXC: scripts/setup/00_preflight_check.sh ausführen
5. Im LXC: scripts/setup/01_install_claude_code.sh ausführen
6. Im LXC: scripts/setup/02_configure_git.sh ausführen
7. Im LXC: scripts/setup/03_init_ansible_vault.sh ausführen
8. Vault-Passwörter in vault.yml eintragen
9. Ansible: ansible-playbook --check --diff playbooks/common.yml
10. Ansible: ansible-playbook playbooks/common.yml
11. Ansible: ansible-playbook --check --diff playbooks/matrix_synapse.yml
12. Ansible: ansible-playbook playbooks/matrix_synapse.yml
13. Matrix testen (Federation, Client, TURN)
14. Ansible: ansible-playbook playbooks/nextcloud_aio.yml
15. Nextcloud AIO über Admin-Interface einrichten
16. Alle Monitoring-Skripte testen
17. Backup-Restore-Test durchführen
```

### 5.3 Kritische Konfigurationspunkte (wo Fehler teuer sind)

| Was | Wo | Problem wenn falsch |
|-----|-----|---------------------|
| `enable_registration: false` | homeserver.yaml | Offene Registrierung = Spam |
| `proxy_pass http://...:8008;` | nginx.conf | Trailing slash = Signaturfehler |
| Container-Name AIO | compose.yml | Update-Mechanismus defekt |
| Docker-Socket nur AIO | compose.yml | Sicherheitslücke |
| Vault-Passwort außerhalb Repo | ~/.vault_pass.txt | Secret im Repo |
| ed25519 SSH-Keys | authorized_keys | RSA veraltet |
| `set -euo pipefail` | alle Skripte | Fehler werden ignoriert |

### 5.4 Häufige Anfänger-Fehler und wie man sie vermeidet

```
FEHLER 1: Docker von apt-Standard-Repo (docker.io)
LÖSUNG:   scripts/setup/00_preflight_check.sh prüft die Quelle

FEHLER 2: :latest in Docker-Images
LÖSUNG:   ansible-lint + GitHub Actions schlägt an

FEHLER 3: SSH-Passwort-Auth lassen + nur Public-Key-Auth aktivieren
LÖSUNG:   harden_ssh.sh prüft, warnt und verlangt Bestätigung

FEHLER 4: Backup nie getestet
LÖSUNG:   backup/backup_test_restore.sh (Simulation ohne echten Restore)

FEHLER 5: Matrix mit SQLite statt PostgreSQL
LÖSUNG:   Playbook erzwingt PostgreSQL; SQLite ist in homeserver.yaml kommentiert

FEHLER 6: Nextcloud AIO via Domain (Port 8080) statt IP aufrufen
LÖSUNG:   Kommentar in compose.yml und Runbook erklärt das

FEHLER 7: Firewall aktivieren ohne SSH-Port freizugeben
LÖSUNG:   setup_ufw.sh gibt ausdrückliche Warnung VOR dem Aktivieren
```

### 5.5 Offene TODOs (werden nach dem Deploy ergänzt)

```
[ ] Echte IPs und Domains in inventory/prod/hosts.yml eintragen
[ ] Vault-Passwort setzen und vault.yml befüllen
[ ] SSH-Key des Control-Nodes auf Zielhosts kopieren
[ ] DNS-Einträge für Matrix und Nextcloud setzen
[ ] Let's Encrypt E-Mail-Adresse eintragen
[ ] Hetzner Storage Box für externe Backups einrichten
[ ] Monitoring-Alerts (E-Mail/Matrix) konfigurieren
[ ] 2FA für Proxmox Web-UI aktivieren
[ ] Fail2Ban E-Mail-Benachrichtigung konfigurieren
```

---

## 6. Kommentar-Standards

### Shell-Skripte
```bash
#!/usr/bin/env bash
# =============================================================================
# DATEI:        <name>.sh
# ZWECK:        <Ein Satz>
# AUFRUFEN:     ./<name>.sh [PARAMETER]
# VORAUSSETZUNGEN:
#   - <Abhängigkeit>
# SICHERHEIT:
#   - Backup-Verhalten: <ja/nein>
#   - Destruktiv: <ja/nein>
#   - Rollback: <Befehl>
# VERSION:      1.0.0 | Stand: 2026-04
# =============================================================================
set -euo pipefail
IFS=$'\n\t'
```

### Ansible Tasks
```yaml
# WARUM: Erkläre den Zweck
# ROLLBACK: Wie rückgängig machen
- name: "Beschreibender Name"
  ansible.builtin.module:
    ...
```

### Docker Compose
```yaml
# ============================================================
# DATEI: compose.yml — <Dienst>
# DEPLOY: docker compose up -d
# STOP:   docker compose down
# UPDATE: docker compose pull && docker compose up -d
# ============================================================
```

---

## 7. Changelog

> **Format:** `YYYY-MM-DD HH:MM — Was wurde gemacht — Wer/Was`

---

### 2026-04-27 — Initiales Repository-Setup (Phase 0+1)

**Was:**
- Verzeichnisstruktur komplett angelegt
- `.gitignore` erstellt (Secrets ausgeschlossen)
- `.claudeignore` erstellt (Claude-spezifische Ausschlüsse)
- Wissensdatenbanken erstellt in `docs/knowledge/`:
  - `claude_code.md` (Installation, Konfiguration, Proxmox-Befehle)
  - `legal_and_security_rules.md` (DSGVO, BSI, Vault, Docker-Security)
  - `proxmox_ve_9x.md` (VMs, LXC, API, Storage)
  - `proxmox_backup.md` (PBS, Backup-Strategien, Restore)
  - `ansible.md` (Grundkonzepte, Module, Vault, Lint)
  - `ansible_playbooks.md` (Best Practices, Tags, Templates)
  - `docker_containerization.md` (Installation, Security, Compose)
  - `linux.md` (Systemverwaltung, Netzwerk, Security, Logs)
  - `networking_basics.md` (IP, DNS, TLS, Hetzner)
  - `git.md` (Befehle, Security, Workflow)
  - `hetzner_dedicated_server.md` (Setup, Netzwerk, Firewall, Storage Box)
  - `troubleshooting_and_security_hardening.md` (Diagnose, CIS, Incident)
  - `automation.md` (Cron, Systemd-Timer, Shell-Skripting, CI/CD)
  - `general_it_admin.md` (Dokumentation, Change Management, DR)
  - `matrix_synapse_playbook_knowledge.md` (Stack, Nginx, Coturn, Admin)
  - `nextcloud_aio_playbook_knowledge.md` (Setup, Ports, Nginx, Backup)

**Nächste Schritte:**
- README.md erstellen
- Setup-Skripte erstellen
- Proxmox API Bibliotheken erstellen
- Ansible-Rollen erstellen

---

### 2026-04-28 — Phasen 2–5 + Doku + Korrektheitsprüfung (Claude Code Session)

**Phase 2: Setup-Skripte**
- `scripts/setup/00_preflight_check.sh` — Prüft Voraussetzungen
- `scripts/setup/01_install_claude_code.sh` — Installiert Claude Code
- `scripts/setup/02_configure_git.sh` — Git + gitleaks v8.21.2 Setup
- `scripts/setup/03_init_ansible_vault.sh` — Ansible Vault initialisieren

**Phase 2: Proxmox API Bibliotheken**
- `proxmox-api/lib/pve_api.sh` — PVE REST API Shell-Bibliothek
- `proxmox-api/lib/pbs_api.sh` — PBS REST API Shell-Bibliothek
- `proxmox-api/examples/` — list_vms.sh, snapshot_create.sh, pbs_backup_verify.sh

**Phase 2: CI/CD**
- `.github/workflows/lint.yml` — YAML Lint + Shell Lint + Ansible Lint
- `.github/workflows/security_scan.yml` — gitleaks Secret-Scan
- `.yamllint.yml`, `.ansible-lint`, `.gitleaks.toml` — CI-Konfiguration

**Phase 3: Ansible-Rollen**
- `ansible/roles/common/` — Basis: Updates, Zeitzone, SSH, UFW, Fail2Ban, sysctl
- `ansible/roles/docker/` — Docker CE Installation
- `ansible/roles/matrix_synapse/` — Vollständiger Matrix-Stack
  - templates: compose.yml.j2, homeserver.yaml.j2, nginx.conf.j2, coturn.conf.j2
- `ansible/roles/nextcloud_aio/` — Nextcloud AIO Deploy
- `ansible/playbooks/` — site.yml, common.yml, docker.yml, matrix_synapse.yml, nextcloud_aio.yml

**Phase 4: Docker-Referenz**
- `docker/matrix-synapse/{compose.yml,.env.example}`
- `docker/nextcloud-aio/{compose.yml,.env.example}`

**Phase 5: Skripte**
- `scripts/security/` — harden_ssh, setup_fail2ban, setup_ufw, audit_secrets, system_audit, rotate_vault_password
- `scripts/proxmox/` — pve_status_report, pve_snapshot_create/rollback, pbs_verify_backups
- `scripts/monitoring/` — check_services, check_disk_usage, check_ssl_certs
- `scripts/backup/` — backup_configs, backup_test_restore, cleanup_old_backups
- `config/` — sshd_hardened.conf, jail.local, ufw_rules.sh, 99-hardening.conf

**Dokumentation**
- `docs/architecture/overview.md` — Gesamtarchitektur, Komponenten, Sicherheit
- `docs/architecture/network_layout.md` — Ports, DNS, Docker-Netzwerke, Firewall
- `docs/architecture/deployment_sequence.md` — Schritt-für-Schritt Erstdeploy
- `docs/runbooks/matrix_admin.md` — Matrix Verwaltung, Updates, Admin-User
- `docs/runbooks/nextcloud_admin.md` — Nextcloud AIO Verwaltung, occ-Befehle
- `docs/runbooks/backup_restore.md` — PBS, Snapshots, Konfigurations-Backups
- `docs/runbooks/proxmox_maintenance.md` — Proxmox Wartung, Updates, Snapshots
- `docs/runbooks/incident_response.md` — SSH-Angriff, Kompromittierung, Secret-Leak

**Bugfixes (Korrektheitsprüfung)**
- `matrix_db_host: "postgres"` (war: "localhost" — würde in Docker scheitern)
- `matrix_redis_host: "redis"` (war: "localhost" — würde in Docker scheitern)
- Redis `bind 0.0.0.0` (war: 127.0.0.1 — Synapse-Container hätte keinen Zugriff)
- `init_postgres.sql`: kein doppeltes CREATE DATABASE mehr (POSTGRES_DB macht das)
- `coturn.conf.j2`: `no-auth` entfernt (widersprach `use-auth-secret`)
- `coturn.conf.j2`: Zertifikat-Pfad korrigiert (`/etc/ssl/live/<DOMAIN>/fullchain.pem`)
- `homeserver.yaml.j2`: `media_store_path: /data/media_store` (war: /media_store)
- `homeserver.yaml.j2`: `log_config` entfernt, Docker-freundliches stdout-Logging
- `homeserver.yaml.j2`: Metriken-Listener korrekt definiert (war: veraltetes metrics_port)

---

*Stand: 2026-04 — Proxmox VE 9.x, PBS 4.x, Debian 13, Ubuntu 24.04*
*Diese Datei wird mit dem Repo versioniert.*
*Unterer Abschnitt (Changelog) bei jeder Sitzung aktualisieren.*
