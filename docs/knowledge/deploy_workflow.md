# Deploy-Workflow — Wissensdatenbank
# Stand: 2026-04 | Reihenfolge der Skripte und Playbooks beim Erstdeploy

> Diese Datei ist die zentrale Anlaufstelle, wenn der erste Deploy ansteht.
> Sie verlinkt auf alle anderen Dateien und erklärt die Reihenfolge.

---

## 1. Übersicht — Was passiert in welcher Reihenfolge?

```
[ Manuelle Vorbereitung ]
   │
   ├─ Hetzner-Server bestellen + Rescue-System aktivieren
   ├─ Proxmox VE 9.x via installimage installieren
   ├─ Proxmox Backup Server installieren (separater Host)
   ├─ LXC Container für Control-Node anlegen (CTID 100)
   └─ SSH-Key (ed25519) erstellen und kopieren
              │
              ▼
[ Automatisch via setup-Skripte (in dieser Reihenfolge!) ]
   │
   ├─ 00_preflight_check.sh         — Voraussetzungen prüfen
   ├─ 01_install_claude_code.sh     — Claude Code installieren
   ├─ 02_configure_git.sh           — Git + gitleaks
   ├─ 03_init_ansible_vault.sh      — Vault initialisieren + hosts.yml/vars.yml
   ├─ 04_generate_secrets.sh        — Secrets generieren (vault.yml befüllen)
   ├─ 05_dns_preflight.sh           — DNS-Records prüfen (vor Let's Encrypt!)
   └─ 06_inventory_check.sh         — Inventar + SSH + Vault validieren
              │
              ▼
[ Ansible-Deploy (in dieser Reihenfolge!) ]
   │
   ├─ ansible-playbook ... common.yml         — Basis-Härtung (UFW, SSH, Fail2Ban)
   ├─ ansible-playbook ... docker.yml         — Docker CE installieren
   ├─ ansible-playbook ... matrix_synapse.yml — Matrix-Stack (PG, Redis, Synapse, Coturn, Nginx, LE)
   └─ ansible-playbook ... nextcloud_aio.yml  — Nextcloud AIO Mastercontainer
              │
              ▼
[ Manuelle Konfiguration nach Deploy ]
   │
   ├─ Matrix Admin-User anlegen (siehe docs/runbooks/matrix_admin.md)
   └─ Nextcloud AIO Setup-Wizard durchklicken (https://<IP>:8080)
```

---

## 2. Reihenfolge — DETAIL

### Phase 0 — Manuelle Vorbereitung
Siehe `instruction.md` für Schritt-für-Schritt-Anleitung.

### Phase 1 — Setup-Skripte (auf Control-Node)

```bash
# Im Repository-Root ausführen:
bash scripts/setup/00_preflight_check.sh
bash scripts/setup/01_install_claude_code.sh
GIT_USER_NAME="<NAME>" GIT_USER_EMAIL="<MAIL>" bash scripts/setup/02_configure_git.sh
bash scripts/setup/03_init_ansible_vault.sh
bash scripts/setup/04_generate_secrets.sh
bash scripts/setup/05_dns_preflight.sh
bash scripts/setup/06_inventory_check.sh
```

**Manuell zwischen 03 und 06:**
1. `ansible-vault edit ansible/inventories/prod/group_vars/all/vault.yml` — PVE/PBS-Tokens eintragen
2. `nano ansible/inventories/prod/hosts.yml` — echte IPs der Server eintragen
3. `nano ansible/inventories/prod/group_vars/all/vars.yml` — Domain, Mail, IPs anpassen

### Phase 2 — Ansible Dry-Run (PFLICHT!)

```bash
# IMMER zuerst --check --diff ausführen!
ansible-playbook ansible/playbooks/site.yml --check --diff
```

Wenn alle Tasks "OK" oder "changed" zeigen (kein "FAILED"), ist der Deploy bereit.

### Phase 3 — Schrittweiser Deploy

```bash
# 1. Basis-Härtung (alle Hosts)
ansible-playbook ansible/playbooks/common.yml

# 2. Docker (nur App-Server)
ansible-playbook ansible/playbooks/docker.yml

# 3. Matrix Synapse Stack
ansible-playbook ansible/playbooks/matrix_synapse.yml

# Test: Matrix Federation prüfen
curl -fsS "https://federationtester.matrix.org/api/report?server_name=<DEINE_DOMAIN>"

# 4. Nextcloud AIO
ansible-playbook ansible/playbooks/nextcloud_aio.yml
```

---

## 3. Was tun bei Fehlern?

| Fehler | Vermutliche Ursache | Lösung |
|--------|---------------------|--------|
| `vault.yml decryption failed` | Vault-Passwort falsch | `~/.vault_pass.txt` prüfen |
| `apt: Unable to locate package docker-ce` | Repo nicht verfügbar | `docker.yml` erneut + `update_cache: true` |
| `certbot: error too many requests` | LE Rate-Limit | 1h warten, danach erneut |
| `nginx: bind() to :80 failed` | certbot --standalone läuft noch | nginx.yml einmal idempotent erneut laufen lassen |
| `ssh: connection refused` | UFW hat SSH geblockt | Hetzner Rescue → UFW disable |
| `synapse: signature error` | DNS .well-known falsch | nginx.yml prüfen, .well-known/matrix/server |
| `matrix login: 500 internal server error` | Datenbank-Locale ≠ C | `data/postgres` löschen + neu deployen |

---

## 4. Idempotenz-Hinweise

Alle Playbooks sind **idempotent**: mehrfaches Ausführen ist sicher und führt
zum selben Endzustand. Was passiert beim erneuten Ausführen?

- **common.yml**: Konfiguration wird nur geändert wenn nicht bereits korrekt.
  Backup-Dateien (.bak.DATUM) bleiben.
- **docker.yml**: Pakete bleiben installiert; Daemon-Config wird verglichen.
- **matrix_synapse.yml**: Container werden nur neu gestartet wenn Config oder
  Image geändert. Datenbank-Initialisierung läuft nur beim ersten Mal.
- **nextcloud_aio.yml**: Mastercontainer wird nur neu erstellt bei
  Image-Update.

**Achtung**: Nach manuellen Änderungen auf einem Host kann ein erneuter
Ansible-Lauf diese überschreiben. Immer erst `--check --diff` ausführen!

---

## 5. Rollback-Strategien

### Rollback Phase 1 (Setup)
- `rm ~/.vault_pass.txt` und Skripte erneut ausführen.
- `git checkout -- ansible/` setzt alle ansible-Dateien zurück.

### Rollback Phase 2 (Common)
- Alle Konfigurationsdateien wurden mit `.bak.DATUM` gesichert.
- Beispiel SSH: `cp /etc/ssh/sshd_config.bak.<DATUM> /etc/ssh/sshd_config && systemctl restart sshd`

### Rollback Phase 3 (Docker / Matrix / Nextcloud)
- Stack stoppen: `docker compose -f /opt/matrix/compose.yml down`
- Bei vollständigem Rückbau: `rm -rf /opt/matrix /opt/nextcloud-aio`
  ⚠️ DESTRUKTIV — alle Daten werden gelöscht!

### Rollback komplett (PBS-Backup zurückspielen)
1. PBS Web-UI öffnen
2. Backup auswählen → Restore
3. Snapshot eines bekannt funktionierenden Zustands wiederherstellen

---

## 6. Pre-Deploy-Checkliste

Vor dem ersten `ansible-playbook` MÜSSEN folgende Punkte erfüllt sein:

```
[ ] Hetzner-Server bestellt und Proxmox installiert
[ ] LXC für Control-Node läuft, SSH-Zugriff möglich
[ ] DNS A-Records gesetzt (matrix.<domain>, <domain>, cloud.<domain>)
[ ] DNS-Propagation abgeschlossen (dig +trace prüfen)
[ ] hosts.yml mit echten IPs befüllt
[ ] vars.yml mit echter Domain + E-Mail befüllt
[ ] ufw_allowed_ssh_sources enthält MEINE Management-IP (sonst Aussperrung!)
[ ] vault.yml enthält gültige PVE/PBS API-Tokens
[ ] vault.yml-Secrets (Passwörter) generiert (04_generate_secrets.sh)
[ ] SSH-Key-Auth zu allen Zielhosts getestet
[ ] 06_inventory_check.sh: alles grün
[ ] Ansible Dry-Run: keine Fehler
```

---

## 7. Wenn Claude Code übernimmt

Nach Phase 1 (Setup-Skripte erfolgreich) kann Claude Code Phase 2+3
selbstständig durchführen. Siehe `prompt.txt` im Repo-Root.

Claude Code soll dabei:
1. **Immer zuerst Dry-Run** (`--check --diff`)
2. **Nicht raten** — bei Unklarheit nachfragen
3. **Backups respektieren** — `.bak.DATUM` nicht löschen
4. **Logs prüfen** nach jedem Deploy-Schritt
5. **Tests ausführen** zwischen Schritten (z.B. Matrix Federation Test)

---

## 8. Nach dem Deploy — Erste Schritte

### Matrix
```bash
# Admin-User registrieren
docker compose -f /opt/matrix/compose.yml exec synapse \
  register_new_matrix_user -c /config/homeserver.yaml \
  -u admin -p '<STARK_RANDOM>' -a http://localhost:8008

# Federation-Test
curl -fsS "https://federationtester.matrix.org/api/report?server_name=<DOMAIN>"
```

### Nextcloud AIO
```
1. Browser: https://<NEXTCLOUD_IP>:8080
2. Initialpasswort kopieren (wird beim ersten Start angezeigt)
3. Domain eingeben (cloud.<domain>)
4. Optionale Container auswählen (Talk, Office, Imaginary, ...)
5. Setup starten → AIO holt automatisch alle Subcontainer
```

Siehe `docs/runbooks/matrix_admin.md` und `docs/runbooks/nextcloud_admin.md`
für vollständige Anleitungen.

---

## 9. Monitoring nach Deploy

```bash
# Tägliche Skript-Aufrufe (z.B. via systemd-Timer):
bash scripts/monitoring/check_services.sh
bash scripts/monitoring/check_disk_usage.sh
bash scripts/monitoring/check_ssl_certs.sh

# Wöchentlich:
bash scripts/security/system_audit.sh
bash scripts/proxmox/pbs_verify_backups.sh

# Monatlich:
bash scripts/backup/backup_test_restore.sh
```

---

*Stand: 2026-04 — siehe Changelog in `CLAUDE.md` für Versionsverlauf*
