# Action Log — Proxmox Infra Admin

> Diese Datei dient als persistentes Gedächtnis für die KI (Claude Code).
> Sie enthält Projektziel, erledigte Tasks, offene Tasks, TODO-Liste
> und alle Notizen die für die Weiterführung des Projekts notwendig sind.
>
> **Format:** Datum | Was | Wer
> **Aktualisierung:** Nach jeder Claude Code Sitzung

---

## Projektziel

**Vollständig automatisierte, sichere und reproduzierbare Proxmox-Infrastruktur**
mit folgenden Diensten:

| Dienst | Technologie | Status |
|--------|-------------|--------|
| Chat-Server | Matrix Synapse v1.123.0 | 🔧 Vorbereitet, noch nicht deployt |
| Cloud-Speicher | Nextcloud AIO :latest | 🔧 Vorbereitet, noch nicht deployt |
| Hypervisor | Proxmox VE 9.x | ⏳ Muss manuell installiert werden |
| Backup | Proxmox Backup Server 4.x | ⏳ Muss manuell installiert werden |
| Automatisierung | Ansible 2.17+ | 🔧 Playbooks fertig |
| Container | Docker CE + Compose v2 | 🔧 Rolle fertig |

**Ziel-Umgebung:**
- Hetzner Dedicated Server (AX41 oder größer)
- Proxmox VE 9.x auf Debian 13 "Trixie"
- LXC Container als Control Node (Debian 12, CT 100)
- Matrix auf LXC Container (CT 20)
- Nextcloud auf LXC Container (CT 21)

---

## Aktueller Status

**STAND: Vorbereitung abgeschlossen — Deploy-bereit**

Alle Skripte, Playbooks, Templates und Konfigurationsdateien sind erstellt und
auf Korrektheit geprüft. Der nächste Schritt ist der erste echte Deploy auf
Hardware (Hetzner Server).

**Bevor der Deploy möglich ist (manuell vom Nutzer):**
1. Hetzner Server bestellen
2. Proxmox VE 9.x installieren
3. LXC Control Node erstellen
4. Grundpakete + Claude Code installieren
5. Repository klonen
6. `scripts/setup/03_init_ansible_vault.sh` ausführen

Danach übernimmt Claude Code (siehe `prompt.txt` oder `instruction.md`).

---

## Erledigte Tasks (Chronologisch)

### Phase 0 — Repository-Grundstruktur (2026-04-27)
- [x] Verzeichnisstruktur angelegt
- [x] `.gitignore` mit Secret-Ausschlüssen erstellt
- [x] `.claudeignore` erstellt
- [x] `CLAUDE.md` als Arbeitsanweisung erstellt

### Phase 1 — Wissensdatenbanken (2026-04-27)
- [x] 15 Wissensdatenbanken in `docs/knowledge/` erstellt:
  - `ansible.md`, `ansible_playbooks.md`
  - `automation.md`, `claude_code.md`
  - `docker_containerization.md`, `general_it_admin.md`
  - `git.md`, `hetzner_dedicated_server.md`
  - `legal_and_security_rules.md`, `linux.md`
  - `matrix_synapse_playbook_knowledge.md`
  - `networking_basics.md`, `nextcloud_aio_playbook_knowledge.md`
  - `proxmox_backup.md`, `proxmox_ve_9x.md`
  - `troubleshooting_and_security_hardening.md`
- [x] `letsencrypt_certbot.md` hinzugefügt (Phase 6, 2026-04-28)

### Phase 2 — Setup-Skripte + CI/CD (2026-04-28)
- [x] `scripts/setup/00_preflight_check.sh` — Voraussetzungen prüfen
- [x] `scripts/setup/01_install_claude_code.sh` — Claude Code installieren
- [x] `scripts/setup/02_configure_git.sh` — Git + gitleaks Setup
- [x] `scripts/setup/03_init_ansible_vault.sh` — Vault initialisieren
- [x] `.github/workflows/lint.yml` — YAML + Shell + Ansible Lint CI
- [x] `.github/workflows/security_scan.yml` — gitleaks Secret-Scan CI
- [x] `.yamllint.yml`, `.ansible-lint`, `.gitleaks.toml` — CI-Konfiguration

### Phase 2b — Proxmox API Bibliotheken (2026-04-28)
- [x] `proxmox-api/lib/pve_api.sh` — PVE REST API Shell-Bibliothek
- [x] `proxmox-api/lib/pbs_api.sh` — PBS REST API Shell-Bibliothek
- [x] `proxmox-api/examples/list_vms.sh`
- [x] `proxmox-api/examples/snapshot_create.sh`
- [x] `proxmox-api/examples/pbs_backup_verify.sh`

### Phase 3 — Ansible-Rollen (2026-04-28)
- [x] `ansible/roles/common/` — Basis: Updates, Zeitzone, SSH, UFW, Fail2Ban, sysctl
- [x] `ansible/roles/docker/` — Docker CE Installation
- [x] `ansible/roles/matrix_synapse/` — Vollständiger Matrix-Stack:
  - Templates: compose.yml.j2, homeserver.yaml.j2, nginx.conf.j2, coturn.conf.j2
  - Tasks: directories, postgres, redis, synapse, coturn, nginx, compose, firewall
- [x] `ansible/roles/nextcloud_aio/` — Nextcloud AIO Deploy
- [x] `ansible/playbooks/` — site.yml, common.yml, docker.yml, matrix_synapse.yml, nextcloud_aio.yml

### Phase 4 — Docker-Referenz (2026-04-28)
- [x] `docker/matrix-synapse/compose.yml` + `.env.example`
- [x] `docker/nextcloud-aio/compose.yml` + `.env.example`

### Phase 5 — Skripte (2026-04-28)
- [x] `scripts/security/` — harden_ssh, setup_fail2ban, setup_ufw, audit_secrets,
  system_audit, rotate_vault_password
- [x] `scripts/proxmox/` — pve_status_report, pve_snapshot_create, pve_snapshot_rollback,
  pbs_verify_backups, pve_api_test
- [x] `scripts/monitoring/` — check_services, check_disk_usage, check_ssl_certs
- [x] `scripts/backup/` — backup_configs, backup_test_restore, cleanup_old_backups
- [x] `config/` — sshd_hardened.conf, jail.local, ufw_rules.sh, 99-hardening.conf

### Phase 5b — Dokumentation (2026-04-28)
- [x] `docs/architecture/overview.md` — Gesamtarchitektur
- [x] `docs/architecture/network_layout.md` — Ports, DNS, Docker-Netzwerke
- [x] `docs/architecture/deployment_sequence.md` — Schritt-für-Schritt Erstdeploy
- [x] `docs/runbooks/matrix_admin.md` — Matrix Verwaltung
- [x] `docs/runbooks/nextcloud_admin.md` — Nextcloud Verwaltung
- [x] `docs/runbooks/backup_restore.md` — Backup + Restore
- [x] `docs/runbooks/proxmox_maintenance.md` — Proxmox Wartung
- [x] `docs/runbooks/incident_response.md` — Incident Response

### Phase 6 — Deploy-Vorbereitung + Bugfixes (2026-04-28)
- [x] `instruction.md` — 9-Schritt Anleitung (Null bis Claude Code aktiv)
- [x] `ansible/inventories/prod/hosts.yml` — Template mit RFC-5737-Platzhaltern
- [x] `ansible/inventories/prod/group_vars/all/vars.yml` — Konfigurationstemplate
- [x] `ansible.cfg` — `vault_password_file` ergänzt
- [x] `prompt.txt` — Claude Code Startprompt für Deploy-Fortsetzung
- [x] `docs/actionlog.md` — Diese Datei

**Bugfixes in Phase 6:**

| Datei | Bug | Fix |
|-------|-----|-----|
| `docker/tasks/main.yml` | Keyring-Verzeichnis NACH GPG-Key-Import erstellt | Reihenfolge getauscht |
| `ansible.cfg` | `vault_password_file` fehlte | Hinzugefügt |
| `templates/nginx.conf.j2` | `listen 443 ssl http2` deprecated (nginx 1.25+) | `listen 443 ssl; http2 on;` |
| `tasks/firewall.yml` | Kommentar "STUN/TURN" falsch (`no-stun` aktiv) | Auf "TURN" geändert |
| `tasks/sysctl.yml` | `net.ipv4.ip_forward=0` bricht Docker | Auf `=1` gesetzt |
| `tasks/nginx.yml` | `certbot --cert-path` existiert nicht | `--config-dir` + Work/Logs-Dirs |
| `tasks/nginx.yml` | Port 80 bei certbot durch UFW gesperrt | Pre-certbot UFW-Task hinzugefügt |
| `common/defaults/main.yml` | `certbot` nicht installiert | Zu `common_packages` hinzugefügt |
| `tasks/ssh_hardening.yml` | `AllowTcpForwarding` + `AllowAgentForwarding` fehlten | Hinzugefügt |

**Bugfixes aus früheren Phasen (Phase 5b):**

| Datei | Bug | Fix |
|-------|-----|-----|
| `defaults/main.yml` | `matrix_db_host: "localhost"` | Auf `"postgres"` (Docker-Service-Name) |
| `defaults/main.yml` | `matrix_redis_host: "localhost"` | Auf `"redis"` (Docker-Service-Name) |
| `tasks/redis.yml` | `bind 127.0.0.1` | Auf `bind 0.0.0.0` (internal: true Netzwerk) |
| `tasks/postgres.yml` | Doppeltes `CREATE DATABASE` | Nur `GRANT` behalten |
| `templates/coturn.conf.j2` | `no-auth` + `use-auth-secret` Widerspruch | `no-auth` entfernt |
| `templates/coturn.conf.j2` | Falscher Zertifikat-Pfad | `live/<domain>/fullchain.pem` |
| `templates/homeserver.yaml.j2` | `media_store_path: /media_store` | `/data/media_store` |
| `templates/homeserver.yaml.j2` | `log_config` Datei nicht gemountet | Inline-Logging |
| `templates/homeserver.yaml.j2` | `metrics_port` deprecated | Listener-Block hinzugefügt |

---

## Offene Tasks (vor erstem Deploy)

### Manuell vom Nutzer zu erledigen:
- [ ] Hetzner Account erstellen + Server bestellen
- [ ] SSH-Key ed25519 generieren
- [ ] Proxmox VE 9.x mit installimage installieren
- [ ] LXC Control Node erstellen (CT 100, Debian 12, 2 CPU, 2 GB RAM)
- [ ] `scripts/setup/00_preflight_check.sh` ausführen
- [ ] `scripts/setup/01_install_claude_code.sh` ausführen
- [ ] `scripts/setup/02_configure_git.sh` ausführen
- [ ] Repository klonen nach `/opt/infra-admin`
- [ ] Anthropic API Key in `~/.bashrc` setzen
- [ ] Claude Code starten und `prompt.txt` Inhalt einfügen

### Von Claude Code beim Deploy zu erledigen:
- [ ] `scripts/setup/03_init_ansible_vault.sh` ausführen
- [ ] Echte IPs in `hosts.yml` eintragen
- [ ] Echte Werte in `vault.yml` (via ansible-vault edit)
- [ ] Echte Werte in `vars.yml` eintragen
- [ ] DNS-Einträge setzen (Claude informiert was gebraucht wird)
- [ ] `ansible-playbook ansible/playbooks/common.yml --check --diff` (Dry-run)
- [ ] `ansible-playbook ansible/playbooks/common.yml` (Ausführen)
- [ ] `ansible-playbook ansible/playbooks/docker.yml` (Docker installieren)
- [ ] `ansible-playbook ansible/playbooks/matrix_synapse.yml --check --diff`
- [ ] `ansible-playbook ansible/playbooks/matrix_synapse.yml`
- [ ] Matrix testen (Federation, Client-API, TURN)
- [ ] `ansible-playbook ansible/playbooks/nextcloud_aio.yml`
- [ ] Nextcloud AIO Admin-Interface einrichten (Nutzer klickt)
- [ ] Monitoring-Skripte testen

### Nach erstem Deploy zu erledigen:
- [ ] Fail2Ban E-Mail-Benachrichtigung konfigurieren
- [ ] Hetzner Storage Box für externe Backups einrichten
- [ ] Automatische Zertifikatserneuerung (certbot renew via Cron) einrichten
- [ ] 2FA für Proxmox Web-UI aktivieren
- [ ] Monitoring-Alerts (E-Mail / Matrix) konfigurieren
- [ ] Backup-Restore-Test durchführen

---

## TODO-Liste nach Phasen

### Phase 7 — Erster Deploy (sobald Hardware bereit)
```
7.1  DNS-Einträge vorbereiten:
     matrix.<DOMAIN>  A  <SERVER-IP>
     cloud.<DOMAIN>   A  <SERVER-IP>

7.2  Vault befüllen:
     ansible-vault edit ansible/inventories/prod/group_vars/all/vault.yml
     → vault_matrix_db_password: <32-Zeichen-Passwort>
     → vault_matrix_registration_shared_secret: <32 Zeichen>
     → vault_matrix_macaroon_secret_key: <32 Zeichen>
     → vault_coturn_auth_secret: <32 Zeichen>
     → vault_pve_api_token_id + _secret (aus Proxmox UI)
     → vault_pbs_api_token_id + _secret (aus PBS UI)

7.3  hosts.yml befüllen:
     nano ansible/inventories/prod/hosts.yml
     → pve01: <echte IP>
     → matrix01: <echte LXC-IP>
     → nextcloud01: <echte LXC-IP>

7.4  vars.yml befüllen:
     nano ansible/inventories/prod/group_vars/all/vars.yml
     → matrix_domain: "<echte Domain>"
     → nextcloud_domain: "cloud.<echte Domain>"
     → ufw_allowed_ssh_sources: ["<Management-IP>"]
     → admin_email: "<E-Mail>"

7.5  Syntax-Check:
     ansible-playbook --syntax-check ansible/playbooks/site.yml

7.6  Dry-Run common:
     ansible-playbook --check --diff ansible/playbooks/common.yml

7.7  Deploy:
     ansible-playbook ansible/playbooks/common.yml
     ansible-playbook ansible/playbooks/docker.yml
     ansible-playbook ansible/playbooks/matrix_synapse.yml
     ansible-playbook ansible/playbooks/nextcloud_aio.yml
```

### Phase 8 — Post-Deploy Konfiguration
```
8.1  Matrix Admin-User erstellen:
     register_new_matrix_user -c /opt/matrix/config/homeserver.yaml \
       -u admin -p <PASSWORT> --admin

8.2  Nextcloud Admin-Interface aufrufen:
     https://<SERVER-IP>:8080
     → Domain eingeben → Zertifikate werden automatisch beantragt

8.3  Certbot-Erneuerung einrichten:
     /etc/cron.d/certbot-matrix

8.4  PBS API Token erstellen:
     PBS Web-UI → Datacenter → API Tokens

8.5  Monitoring aktivieren:
     bash scripts/monitoring/check_services.sh
```

---

## Wichtige Konfigurationspunkte (für KI-Referenz)

### Kritische Invarianten (NIEMALS ändern!)
```
matrix_db_host: "postgres"       # Docker-Service-Name, NICHT "localhost"
matrix_redis_host: "redis"       # Docker-Service-Name, NICHT "localhost"
nextcloud_aio_container_name: "nextcloud-aio-mastercontainer"  # FEST!
matrix_enable_registration: false  # NIEMALS true ohne Schutz!
```

### Docker-Image-Versionen (Stand: 2026-04)
```
matrixdotorg/synapse:v1.123.0
postgres:16.4
redis:7.2-alpine
coturn/coturn:4.6
nginx:1.27-alpine
nextcloud/all-in-one:latest    # Ausnahme: AIO ist der Updatemanager
```

### Netzwerk-Architektur
```
matrix_internal (Docker, internal:true) → Synapse, Postgres, Redis
matrix_external (Docker, öffentlich)    → Synapse, Nginx
nextcloud-aio (Docker, external:true)   → AIO-Mastercontainer + Sub-Container
coturn: network_mode: host              → Direkter Host-Netzwerkzugang
```

### Zertifikat-Pfade (nach certbot)
```
/opt/matrix/certs/live/matrix.<DOMAIN>/fullchain.pem
/opt/matrix/certs/live/matrix.<DOMAIN>/privkey.pem
Im Nginx-Container:  /etc/nginx/certs/live/matrix.<DOMAIN>/...
Im Coturn-Container: /etc/ssl/live/matrix.<DOMAIN>/...
```

### Ansible-Playbook-Reihenfolge (PFLICHT)
```
1. common.yml        → SSH, UFW, Fail2Ban, sysctl, Pakete
2. docker.yml        → Docker CE installieren
3. matrix_synapse.yml → Matrix + certbot + Nginx + Coturn
4. nextcloud_aio.yml  → Nextcloud AIO Mastercontainer
```

---

## Notizen für die KI

### Sicherheitsprinzipien dieser Codebasis
- **Kein Root-Docker**: Alle Container laufen als non-root (außer AIO-Mastercontainer)
- **cap_drop: ALL** überall wo möglich
- **no-new-privileges:true** in allen Containern
- **Vault für alle Secrets**: Kein Plaintext in Repo
- **SSH nur ed25519**: Kein RSA, kein Passwort-Login
- **UFW default deny**: Nur explizit geöffnete Ports erlaubt

### Bekannte Einschränkungen
1. **Coturn ohne cap_drop**: `network_mode: host` macht cap_drop problematisch
2. **certbot --standalone**: Nginx und certbot können Port 80 nicht teilen
3. **AIO :latest**: Ausnahme von der No-Latest-Regel — bewusste Designentscheidung
4. **AIO Docker-Socket**: AIO braucht Docker-Socket zum Starten von Sub-Containern

### Häufige Fehlerquellen
1. DNS nicht gesetzt vor certbot → Timeout
2. Port 80 durch UFW gesperrt vor certbot → Connection refused
3. Vault-Passwort vergessen → Vault nicht entschlüsselbar
4. `localhost` statt Service-Name in Docker → Container können sich nicht erreichen
5. Matrix-Domain nach Deploy ändern → Alle Benutzer-IDs werden ungültig

---

## Changelog (diese Datei)

| Datum | Änderung |
|-------|----------|
| 2026-04-28 | Erstellt. Enthält Vollständigen Projektstatus nach 5 PRs. |

---

*Diese Datei wird bei jeder Claude Code Sitzung aktualisiert.*
*Letztes Update: 2026-04-28*
