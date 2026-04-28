# Deployment-Reihenfolge

> Stand: 2026-04 | Vollständige Schritt-für-Schritt Reihenfolge für den Erstdeploy

## Übersicht

```
Phase 0: Hetzner + Proxmox Setup (manuell)
Phase 1: Control Node (LXC) + Tools einrichten
Phase 2: Ansible Vault initialisieren
Phase 3: Common-Rolle (Basis-Hardening) deployen
Phase 4: Docker-Rolle deployen
Phase 5: Matrix Synapse deployen + testen
Phase 6: Nextcloud AIO deployen + einrichten
Phase 7: Monitoring + Backup aktivieren
```

---

## Phase 0: Hetzner + Proxmox (manuell, einmalig)

```bash
# 1. Hetzner Dedicated Server bestellen
# 2. In Rescue-Modus booten (Hetzner Robot → Server → Rescue)
# 3. Proxmox VE 9.x installieren via installimage:
installimage

# 4. Nach Reboot: Proxmox Web-UI aufrufen
# https://192.0.2.10:8006

# 5. Proxmox Backup Server auf separatem Host installieren
# https://192.0.2.11:8007

# 6. VM oder LXC für die Services erstellen:
#    CTID 100: Claude Code / Control Node (LXC, 2 CPU, 4GB RAM)
#    CTID 101: Matrix Synapse (LXC oder VM, 2 CPU, 4GB RAM, 50GB Disk)
#    CTID 102: Nextcloud AIO (LXC oder VM, 4 CPU, 8GB RAM, 200GB Disk)
```

## Phase 1: Control Node einrichten

```bash
# Im LXC Container (CTID 100):
cd /opt
git clone https://gitea.example.com/Banjo2001/claude-master.git infra-admin
cd infra-admin

# Voraussetzungen prüfen
bash scripts/setup/00_preflight_check.sh

# Claude Code installieren (optional)
bash scripts/setup/01_install_claude_code.sh

# Git + gitleaks einrichten
bash scripts/setup/02_configure_git.sh
```

## Phase 2: Ansible Vault initialisieren

```bash
# Ansible Vault und Verzeichnisstruktur erstellen
bash scripts/setup/03_init_ansible_vault.sh

# Echte Werte eintragen:
# 1. ansible/inventories/prod/hosts.yml — echte IPs eintragen
# 2. ~/.vault_pass.txt — sicheres Passwort (min. 20 Zeichen)
# 3. ansible/inventories/prod/group_vars/all/vault.yml — Secrets eintragen:
ansible-vault edit ansible/inventories/prod/group_vars/all/vault.yml

# Zu setzende Werte in vault.yml:
# vault_matrix_db_password         — PostgreSQL Passwort
# vault_matrix_registration_shared_secret — für Admin-API
# vault_matrix_macaroon_secret_key — intern (zufällig, min. 32 Zeichen)
# vault_coturn_auth_secret         — TURN shared secret (min. 32 Zeichen)

# vars.yml anpassen (nicht-sensitive Werte):
nano ansible/inventories/prod/group_vars/all/vars.yml
# matrix_domain, nextcloud_domain, letsencrypt_email etc.
```

## Phase 3: Common-Rolle deployen

```bash
# Erst: SSH-Key auf Zielhosts kopieren
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@192.0.2.20
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@192.0.2.21

# Syntax prüfen (kein Deploy)
ansible-playbook --syntax-check ansible/playbooks/common.yml

# Dry-Run (zeigt Änderungen ohne Ausführung)
ansible-playbook --check --diff \
  --vault-password-file ~/.vault_pass.txt \
  ansible/playbooks/common.yml

# Deploy
ansible-playbook \
  --vault-password-file ~/.vault_pass.txt \
  ansible/playbooks/common.yml

# Prüfen:
# - SSH-Hardening aktiv?
# - UFW aktiv?
# - Fail2Ban aktiv?
bash scripts/security/system_audit.sh
```

## Phase 4: Docker deployen

```bash
ansible-playbook \
  --vault-password-file ~/.vault_pass.txt \
  ansible/playbooks/docker.yml

# Prüfen:
docker --version     # Muss Docker CE sein, nicht docker.io!
docker compose version
```

## Phase 5: Matrix Synapse deployen

```bash
# DNS setzen (VORHER!):
# matrix.example.com → 192.0.2.20

# Dry-Run
ansible-playbook --check --diff \
  --vault-password-file ~/.vault_pass.txt \
  ansible/playbooks/matrix_synapse.yml

# Deploy
ansible-playbook \
  --vault-password-file ~/.vault_pass.txt \
  ansible/playbooks/matrix_synapse.yml

# Testen (Runbook: docs/runbooks/matrix_admin.md):
curl https://matrix.example.com/_matrix/client/versions
curl https://matrix.example.com/.well-known/matrix/server

# Ersten Admin-User anlegen:
docker exec -it matrix-synapse-1 \
  register_new_matrix_user -c /config/homeserver.yaml \
  -u admin -p '<PASSWORT>' -a http://localhost:8008
```

## Phase 6: Nextcloud AIO deployen

```bash
# DNS setzen (VORHER!):
# cloud.example.com → 192.0.2.21

ansible-playbook \
  --vault-password-file ~/.vault_pass.txt \
  ansible/playbooks/nextcloud_aio.yml

# Admin-Interface aufrufen (NUR über IP, nie über Domain!):
# https://192.0.2.21:8080

# Nextcloud einrichten:
# 1. Domain eintragen: cloud.example.com
# 2. Optionale Container wählen (Collabora, Talk, etc.)
# 3. "Start containers" klicken
# 4. Warten bis alle Container grün sind (~10–15 min)
# 5. Admin-Passwort notieren!
```

## Phase 7: Monitoring + Backup aktivieren

```bash
# Cronjobs einrichten (auf jedem Server):
cat >> /etc/cron.d/infra-monitoring << 'EOF'
*/5 * * * * root /opt/infra-admin/scripts/monitoring/check_services.sh >> /var/log/infra-monitor.log 2>&1
0 * * * * root /opt/infra-admin/scripts/monitoring/check_disk_usage.sh >> /var/log/infra-monitor.log 2>&1
0 6 * * * root /opt/infra-admin/scripts/monitoring/check_ssl_certs.sh >> /var/log/infra-monitor.log 2>&1
0 2 * * * root /opt/infra-admin/scripts/backup/backup_configs.sh >> /var/log/infra-backup.log 2>&1
EOF

# PBS Backup-Plan einrichten:
# Proxmox Web-UI → Rechenzentrum → Backup → Backup-Job hinzufügen
# Zeitplan: täglich 03:00 Uhr
# Aufbewahrung: 7 täglich, 4 wöchentlich, 3 monatlich

# Backup-Test durchführen:
bash scripts/backup/backup_test_restore.sh
```

---

## Checkliste: Vor dem Produktivbetrieb

```
[ ] SSH-Key-Auth auf allen Servern getestet
[ ] UFW aktiv auf allen Servern (ufw status)
[ ] Fail2Ban aktiv (fail2ban-client status)
[ ] Matrix Federation getestet (federationtester.matrix.org)
[ ] Nextcloud erreichbar + Admin-Login funktioniert
[ ] PBS Backup-Plan aktiv und erster Backup erfolgreich
[ ] Backup-Test bestanden (backup_test_restore.sh)
[ ] SSL-Zertifikate gültig (check_ssl_certs.sh)
[ ] Monitoring-Cronjobs aktiv
[ ] Admin-Passwörter sicher gespeichert (KeePass/Bitwarden)
[ ] 2FA für Proxmox Web-UI aktiviert
```
