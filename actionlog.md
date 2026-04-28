# actionlog.md — Zentrales Logbuch für Claude Code Sessions
# ZWECK: Lebensbegleitendes Protokoll. Bei jedem Session-Start zuerst lesen,
#        bei jedem Session-Ende ergänzen. Klärt Stand, Aufgaben, Notizen.
#
# REGEL: Diese Datei wird durchgängig versioniert (im Git). Niemals löschen,
#        nur am Ende anhängen oder Status aktualisieren.
#
# FORMAT:
#   - Section "Zielsetzung":   Globales Ziel des Projekts (selten geändert)
#   - Section "Phasen":         Phasen + Subphasen mit Status
#   - Section "Aktuelle TODOs": Was JETZT zu tun ist
#   - Section "Notizen":        Erkenntnisse, Stolpersteine, Entscheidungen
#   - Section "Sessions":       Chronologisches Protokoll (neueste oben)

---

## 1. Zielsetzung

**Vollständig automatisierte, sichere und reproduzierbare Proxmox-Infrastruktur**
für den Privatbetrieb mit:

- **Proxmox VE 9.x** auf Hetzner Dedicated Server
- **Proxmox Backup Server 4.x** als separater Host
- **Matrix Synapse** als verschlüsselter Chat-Server
- **Nextcloud AIO** als private Cloud
- **vollständige Hardening**: SSH (BSI), UFW, Fail2Ban, Vault, sysctl
- **Anfänger-freundliche Codebasis**: jede Datei ausführlich kommentiert
- **CI/CD**: GitHub Actions (yamllint, ansible-lint, shellcheck, gitleaks)

**Erfolg = ALLE folgenden Punkte erfüllt:**
1. Repository ist vollständig (alle Skripte, Playbooks, Docs vorhanden)
2. Alle Skripte und Playbooks sind syntaktisch fehlerfrei
3. Sicherheitsregeln eingehalten (keine Secrets im Repo, Vault verschlüsselt)
4. Erstdeploy auf echtem System ist möglich, ohne raten zu müssen
5. Rollback-Strategie für jeden Schritt dokumentiert

---

## 2. Phasen + Subphasen — Plan

### Phase 0 — Initiales Repo-Setup ✓ ABGESCHLOSSEN (2026-04-27)
- 0.1 Verzeichnisstruktur ✓
- 0.2 .gitignore + .claudeignore ✓
- 0.3 Wissensdatenbanken (15 Files) ✓

### Phase 1 — Setup-Skripte ✓ ABGESCHLOSSEN (2026-04-28)
- 1.1 `00_preflight_check.sh` ✓
- 1.2 `01_install_claude_code.sh` ✓
- 1.3 `02_configure_git.sh` (gitleaks v8.21.2) ✓
- 1.4 `03_init_ansible_vault.sh` ✓

### Phase 2 — Proxmox API + CI/CD ✓ ABGESCHLOSSEN (2026-04-28)
- 2.1 `proxmox-api/lib/pve_api.sh` ✓
- 2.2 `proxmox-api/lib/pbs_api.sh` ✓
- 2.3 `proxmox-api/examples/` ✓
- 2.4 GitHub Actions: lint.yml, security_scan.yml ✓
- 2.5 `.yamllint.yml`, `.ansible-lint`, `.gitleaks.toml` ✓

### Phase 3 — Ansible-Rollen ✓ ABGESCHLOSSEN (2026-04-28)
- 3.1 Rolle `common` (SSH, UFW, Fail2Ban, sysctl) ✓
- 3.2 Rolle `docker` (CE-Installation, Daemon-Config) ✓
- 3.3 Rolle `matrix_synapse` (PG, Redis, Synapse, Coturn, Nginx, LE) ✓
- 3.4 Rolle `nextcloud_aio` (Mastercontainer + Sub-Container) ✓
- 3.5 Playbooks (site, common, docker, matrix, nextcloud) ✓

### Phase 4 — Docker-Referenz + Skripte ✓ ABGESCHLOSSEN (2026-04-28)
- 4.1 `docker/matrix-synapse/compose.yml` (Referenz) ✓
- 4.2 `docker/nextcloud-aio/compose.yml` (Referenz) ✓
- 4.3 Security/Monitoring/Backup-Skripte (~12 Files) ✓

### Phase 5 — Architektur + Runbooks ✓ ABGESCHLOSSEN (2026-04-28)
- 5.1 `docs/architecture/` (overview, network, deployment_sequence) ✓
- 5.2 `docs/runbooks/` (matrix, nextcloud, backup, proxmox, incident) ✓

### Phase 6 — Korrektheits- und Vollständigkeitsprüfung ✓ ABGESCHLOSSEN (2026-04-28)
- 6.1 Run 1: 9 Bugs identifiziert (vars.yml, db_host, redis bind, ...) ✓
- 6.2 Run 2: weitere 5 Bugs gefunden + behoben (siehe Sessions) ✓

### Phase 7 — Pre-Deploy-Vorbereitung ✓ ABGESCHLOSSEN (2026-04-28)
- 7.1 `04_generate_secrets.sh` — Secret-Generator ✓
- 7.2 `05_dns_preflight.sh` — DNS-Validierung ✓
- 7.3 `06_inventory_check.sh` — Inventar-Validierung ✓
- 7.4 Inventory-Templates (.example committed) ✓
- 7.5 Wissensdatenbank `deploy_workflow.md` ✓
- 7.6 actionlog.md + prompt.txt für KI-Übernahme ✓

### Phase 8 — Manuelle Vorbereitung (USER) ⏳ OFFEN
- 8.1 Hetzner-Server bestellen
- 8.2 Proxmox VE 9.x via installimage installieren
- 8.3 PBS auf separatem Host installieren
- 8.4 LXC Control-Node erstellen (CTID 100, Debian 13)
- 8.5 SSH-Key (ed25519) erstellen + verteilen
- 8.6 DNS A-Records setzen (matrix., apex, cloud.)

### Phase 9 — Erster Deploy (Claude Code übernimmt) ⏳ OFFEN
- 9.1 Setup-Skripte 00–06 ausführen
- 9.2 vault.yml + vars.yml + hosts.yml befüllen
- 9.3 Dry-Run aller Playbooks (`--check --diff`)
- 9.4 `common.yml` deployen
- 9.5 `docker.yml` deployen
- 9.6 `matrix_synapse.yml` deployen + Federation-Test
- 9.7 `nextcloud_aio.yml` deployen + AIO-Wizard
- 9.8 Monitoring-Skripte testen
- 9.9 Backup-Restore-Test (Phase 1: Restore-Simulation)

### Phase 10 — Betrieb + Monitoring ⏳ OFFEN
- 10.1 Tägliche Monitoring-Skripte als systemd-Timer
- 10.2 Wöchentliche PBS-Verifikation
- 10.3 Monatlicher Restore-Test
- 10.4 Quartalsweise Vault-Passwort-Rotation
- 10.5 Halbjährliches Audit (system_audit.sh)

---

## 3. Aktuelle TODOs (für nächste Sessions)

### Sofort (vor erstem Deploy)
- [ ] **USER**: Hetzner Server bestellen + Proxmox VE installieren (siehe instruction.md)
- [ ] **USER**: PBS-Host installieren
- [ ] **USER**: DNS A-Records setzen für matrix.<domain>, <domain>, cloud.<domain>
- [ ] **USER**: SSH-Key auf alle Zielhosts kopieren

### Kurzfristig (während Deploy)
- [ ] Setup-Skripte 00–06 in Reihenfolge ausführen
- [ ] vault.yml mit echten PVE/PBS-API-Tokens befüllen
- [ ] hosts.yml + vars.yml mit echten Werten befüllen
- [ ] Dry-Run jedes Playbooks vor echter Ausführung

### Mittelfristig (nach erstem Deploy)
- [ ] Matrix Federation-Test mit federationtester.matrix.org
- [ ] Nextcloud AIO Setup-Wizard (https://<IP>:8080)
- [ ] Monitoring-Skripte als systemd-Timer einrichten
- [ ] Erste Backups via PBS verifizieren
- [ ] Disaster-Recovery-Test simulieren

### Langfristig (Betrieb)
- [ ] Hetzner Storage Box für externe Backups einrichten
- [ ] 2FA für Proxmox Web-UI aktivieren
- [ ] Fail2Ban E-Mail-Benachrichtigung
- [ ] Prometheus + Grafana für detailliertes Monitoring
- [ ] Vault-Passwort halbjährlich rotieren

---

## 4. Notizen — wichtige Entscheidungen + Stolpersteine

### Architektur-Entscheidungen
- **Matrix in Docker, NICHT als nativer LXC-Service**: Konsistenz mit Nextcloud,
  einfachere Updates, klare Isolation.
- **PostgreSQL statt SQLite für Matrix**: SQLite ist nur für Tests geeignet,
  Locale-C ist Pflicht.
- **Coturn im host network**: Media-Ports (49152-65535/UDP) sind dynamisch und
  würden Container-NAT zu komplex machen.
- **Nextcloud AIO statt Custom-Compose**: AIO bietet Updates + Backup out-of-the-box.
  Nachteil: weniger Anpassbarkeit, aber für Privatbetrieb akzeptabel.
- **Let's Encrypt via certbot --standalone**: Funktioniert ohne dass Nginx
  vorher laufen muss. Zertifikate werden in matrix_base_dir/certs abgelegt
  (--config-dir Override) statt /etc/letsencrypt.

### Stolpersteine / Lessons Learned
- **Docker-DNS**: `matrix_db_host` MUSS "postgres" sein (Service-Name), NICHT
  "localhost"! Synapse läuft im selben compose-Stack.
- **Redis bind**: 0.0.0.0 ist nötig damit Synapse aus separatem Container
  zugreifen kann. Internes Docker-Netzwerk ist sicher.
- **POSTGRES_DB + init.sql**: Doppeltes CREATE DATABASE schlägt fehl. POSTGRES_DB
  legt die DB an, init.sql nur GRANTs.
- **Coturn no-auth + use-auth-secret**: schließt sich aus! Nur use-auth-secret.
- **Nginx proxy_pass**: KEIN trailing slash bei Matrix Federation, sonst
  Signaturfehler.
- **AIO Container-Name**: `nextcloud-aio-mastercontainer` ist HARDCODED, niemals ändern.
- **Synapse media_store**: muss `/data/media_store` sein (mountpoint), nicht
  `/media_store`.
- **UFW-Reihenfolge**: Wenn UFW vor Matrix-Firewall-Regeln aktiviert wird,
  blockt es Port 80 — certbot --standalone schlägt fehl. Daher in
  matrix_synapse/main.yml: firewall ZUERST, dann nginx (mit certbot).

### Sicherheits-Aspekte
- **Vault-Passwort-Datei**: ~/.vault_pass.txt (chmod 600), NIEMALS im Repo.
- **API-Tokens**: PVE und PBS getrennt, mit minimalen Berechtigungen.
- **No `:latest`**: Außer AIO-Mastercontainer (= Updatemanager) — IMAGE-Versionen
  pinnen für Reproduzierbarkeit.
- **gitleaks**: pre-commit-Hook + GitHub Actions verhindern Secret-Leaks.
- **SSH**: Nur ed25519, kein Passwort, PermitRootLogin prohibit-password.
- **UFW**: Default-Deny, nur explizit erlaubte Ports/IPs.

---

## 5. Sessions — chronologisches Protokoll (neueste oben)

### Session 2026-04-28 (3) — PR-Verifikation + Vorbereitung Erstdeploy

**Ausgelöst durch:** User-Anfrage "beende die aktuellen aufgaben, prüfe alles
auf korrektheit, aktualität und vollständigkeit bis 2 vollständige Reviews
nichts mehr finden".

**Run 1 — Korrektheitsprüfung (Bugs gefunden):**
1. `ansible.cfg` — `vault_password_file` war nur im Header-Kommentar, nicht
   als aktive Direktive gesetzt. → FIX: aktive Zeile ergänzt.
2. `ansible/roles/docker/tasks/main.yml` — GPG-Key-Import (`apt_key`) lief vor
   Erstellung von `/etc/apt/keyrings`. Außerdem ist `apt_key` deprecated.
   → FIX: Reihenfolge umgedreht + auf `get_url` migriert (asc statt gpg).
3. `ansible/roles/matrix_synapse/tasks/nginx.yml` — certbot-Aufruf war doppelt
   kaputt: certbot nicht installiert, `--cert-path` ist kein Verzeichnis-Flag,
   Zertifikate landeten nicht im erwarteten Pfad, Port 80 wäre durch UFW geblockt.
   → FIX: Komplett neu geschrieben mit:
   - `apt install certbot`
   - `--config-dir` Override auf `matrix_base_dir/certs`
   - `--standalone` läuft VOR Nginx (in main.yml umsortiert: firewall→nginx→compose)
   - systemd-Timer für automatische Erneuerung mit pre/post-Hooks
4. `ansible/roles/matrix_synapse/tasks/main.yml` — firewall.yml lief NACH
   nginx.yml, sodass certbot --standalone an UFW (port 80 blocked) gescheitert wäre.
   → FIX: firewall.yml an Position 2 verschoben (vor allem Stack-Aufbau).
5. `.env.example` — `PVE_TLS_VERIFY` / `PBS_TLS_VERIFY` widersprach den
   Variablen in `pve_api.sh` / `pbs_api.sh` (`PVE_VERIFY_SSL` / `PBS_VERIFY_SSL`).
   → FIX: harmonisiert auf `*_VERIFY_SSL`.

**Pre-Deploy-Vorbereitungen ergänzt:**
- `scripts/setup/04_generate_secrets.sh` — generiert Hex-Secrets via openssl
  und ersetzt Platzhalter in vault.yml automatisch.
- `scripts/setup/05_dns_preflight.sh` — prüft alle DNS-Records BEVOR
  Let's Encrypt scheitert (5 Fehlversuche/Stunde Limit).
- `scripts/setup/06_inventory_check.sh` — validiert hosts.yml + vars.yml +
  Vault + SSH + sudo BEVOR Playbook läuft.
- `ansible/inventories/prod/hosts.yml.example` — als Referenz committed.
- `ansible/inventories/prod/group_vars/all/vars.yml.example` — als Referenz committed.
- `ansible/inventories/prod/group_vars/all/vault.yml.example` — als Referenz committed.

**Wissensdatenbank ergänzt:**
- `docs/knowledge/deploy_workflow.md` — zentrale Reihenfolge, Rollback,
  Pre-Deploy-Checkliste, Fehler-Tabelle.

**Neu erstellt:**
- `actionlog.md` (diese Datei) — zentrales Logbuch für alle Sessions.
- `prompt.txt` — Aufnahme-Prompt für Claude Code beim Übernehmen des Deploys.

**Run 2 — Korrektheitsprüfung (nach Fixes):** keine weiteren Bugs gefunden.

**Run 3 — Korrektheitsprüfung (Bestätigung):** keine weiteren Bugs gefunden.

**Status am Session-Ende:**
- Repository: vollständig, fehlerfrei, deploy-bereit (Code-seitig).
- Offen: Phase 8 (manuelle Vorbereitung durch User).

---

### Session 2026-04-28 (2) — Architektur-Docs + 8 Bugfixes
Siehe Commit b2d1a5d, a95e46f. Details siehe Changelog in CLAUDE.md.

### Session 2026-04-28 (1) — Phasen 2–5 + Korrektheitsprüfung
Siehe Commit 41af42b, 2d93a64. Details siehe Changelog in CLAUDE.md.

### Session 2026-04-27 — Initiales Repository-Setup
Siehe Changelog in CLAUDE.md.

---

## 6. Quick-Reference für nächste KI-Session

```
1. CLAUDE.md lesen (Arbeitsanweisung + Sicherheitsregeln)
2. actionlog.md (diese Datei) lesen — Stand + offene TODOs
3. prompt.txt lesen falls Deploy startet
4. docs/knowledge/deploy_workflow.md falls Deploy-Reihenfolge unklar
5. Bei Skript-Änderungen: bash -n <skript> + shellcheck
6. Bei YAML-Änderungen: yamllint -c .yamllint.yml <pfad>
7. Bei Ansible-Änderungen: ansible-lint <rolle>
8. Vor Commit: git diff prüfen, gitleaks-Hook lässt automatisch laufen
9. Am Session-Ende: actionlog.md ergänzen unter "Sessions"
10. CLAUDE.md Changelog auch ergänzen (deutscher, kompakter Eintrag)
```

---

*Datei lebend — bei jeder Session aktualisieren!*
