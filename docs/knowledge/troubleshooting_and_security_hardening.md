# Troubleshooting & Security Hardening — Wissensdatenbank
# Stand: 2026-04

## 1. Systematisches Troubleshooting

### 1.1 Methodik (TOP-DOWN)
```
1. Was genau ist das Problem? (Fehlermeldung, Symptom)
2. Wann begann es? (Letzte Änderung?)
3. Ist es reproduzierbar?
4. Logs prüfen (systemd journal, Applikations-Logs)
5. Netzwerk prüfen (Erreichbarkeit, DNS, Firewall)
6. Ressourcen prüfen (RAM, Disk, CPU)
7. Dienst-Status prüfen
8. Konfiguration prüfen (Syntax-Check)
9. Rollback wenn nötig
```

### 1.2 Checkliste bei "Dienst nicht erreichbar"
```bash
# 1. Dienst läuft?
systemctl status <dienst>
docker ps | grep <name>

# 2. Port gebunden?
ss -tlnp | grep <port>

# 3. Firewall blockiert?
ufw status
iptables -L -n | grep <port>

# 4. DNS korrekt?
dig <domain>
curl -v https://<domain>

# 5. TLS-Fehler?
openssl s_client -connect <domain>:443 -servername <domain>

# 6. Logs des Dienstes
journalctl -u <dienst> -n 50
docker logs <container> --tail=50

# 7. Ressourcen erschöpft?
free -h
df -h
top
```

## 2. Häufige Probleme und Lösungen

### 2.1 SSH-Verbindung schlägt fehl
```bash
# Problem: "Connection refused"
# Lösung:
systemctl status sshd
ss -tlnp | grep :22
# Ist SSH-Port vielleicht geändert? /etc/ssh/sshd_config prüfen

# Problem: "Permission denied (publickey)"
# Lösung:
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
# Auf Remote: Schlüssel korrekt in authorized_keys?
cat ~/.ssh/authorized_keys

# Problem: SSH zu langsam
# Lösung: In /etc/ssh/sshd_config
# UseDNS no  (kein Reverse-DNS-Lookup bei Login)
```

### 2.2 Docker Container startet nicht
```bash
# Logs anzeigen
docker logs <container>
docker logs <container> --tail=100 2>&1 | grep -i error

# Konfiguration prüfen
docker compose config

# Image neu herunterladen
docker compose pull

# Volume-Berechtigungen prüfen (häufiges Problem)
ls -la ./data/
# Container läuft als UID X, Verzeichnis gehört wem?

# Netzwerk-Konflikt?
docker network ls
# Wenn Netzwerk bereits existiert: docker network rm <name>
```

### 2.3 Ansible-Fehler
```bash
# Verbindung testen
ansible <host> -m ping -i inventories/prod/hosts.yml

# Verbose-Mode für mehr Details
ansible-playbook site.yml -vvv

# Nur bestimmten Task ausführen (via Tags)
ansible-playbook site.yml --tags <tag> --check

# Häufiger Fehler: Sudo-Passwort fehlt
ansible-playbook site.yml --ask-become-pass

# Vault-Fehler: Falsches Passwort?
ansible-vault view vault.yml  # Fragt nach Passwort
```

### 2.4 Nginx 502 Bad Gateway
```bash
# 502 = Nginx kann Upstream nicht erreichen (Matrix/Nextcloud)
# 1. Läuft der Upstream-Dienst?
systemctl status synapse
docker ps | grep synapse

# 2. Hört der Dienst auf dem konfigurierten Port?
ss -tlnp | grep 8008  # Matrix

# 3. Nginx Konfiguration prüfen
nginx -t
journalctl -u nginx -n 20

# 4. SELinux/AppArmor blockiert? (Ubuntu)
# Normalerweise nicht aktiviert, aber prüfen:
aa-status
```

### 2.5 Let's Encrypt Zertifikat schlägt fehl
```bash
# Port 80 offen?
ufw status | grep 80
ss -tlnp | grep :80

# Webroot korrekt?
ls -la /var/www/certbot/

# Test-Zertifikat (für Diagnose, kein Limit)
certbot certonly --staging --webroot -w /var/www/certbot -d example.com

# Manueller HTTP-Test
curl -v http://example.com/.well-known/acme-challenge/test

# Log anzeigen
journalctl -u certbot -n 50
```

## 3. Security Hardening

### 3.1 Lynis Security Audit
```bash
# Lynis installieren
apt install -y lynis

# Audit durchführen
lynis audit system

# Bericht anzeigen
cat /var/log/lynis.log | grep -E "WARNING|SUGGESTION" | head -30

# Häufige Empfehlungen:
# - Kernel-Parameter härten (sysctl)
# - SSH-Konfiguration
# - Paket-Updates
# - Cron-Job-Berechtigungen
```

### 3.2 CIS Benchmark (Kurzversion)

**1. Filesystem**
```bash
# Noexec auf /tmp setzen
echo "tmpfs /tmp tmpfs defaults,rw,nosuid,nodev,noexec,relatime 0 0" >> /etc/fstab
mount -o remount /tmp
```

**2. Network**
```bash
# IPv6 deaktivieren (wenn nicht benötigt)
echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.d/99-hardening.conf
sysctl -p /etc/sysctl.d/99-hardening.conf
```

**3. Access Control**
```bash
# Root-Login über console einschränken
echo "tty1" > /etc/securetty

# su einschränken (nur sudo-Gruppe)
echo "auth required pam_wheel.so" >> /etc/pam.d/su
```

**4. Logging**
```bash
# Alle Auth-Logs zentral
# systemd-journal ist Standard — Papier-Trail sicherstellen
journalctl --disk-usage
# Mehr Speicher für Logs
mkdir -p /etc/systemd/journald.conf.d/
cat > /etc/systemd/journald.conf.d/retention.conf << 'EOF'
[Journal]
SystemMaxUse=500M
SystemKeepFree=100M
MaxRetentionSec=3months
EOF
systemctl restart systemd-journald
```

### 3.3 Kernel-Härtung (sysctl)
```bash
cat > /etc/sysctl.d/99-hardening.conf << 'EOF'
# Netzwerk-Schutz
net.ipv4.tcp_syncookies = 1
net.ipv4.ip_forward = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Kernel-Härtung
kernel.randomize_va_space = 2
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.perf_event_paranoid = 3
kernel.yama.ptrace_scope = 1
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
EOF
sysctl -p /etc/sysctl.d/99-hardening.conf
```

## 4. Incident Response

### 4.1 Verdächtige Aktivität erkannt

```bash
# 1. Aktive SSH-Verbindungen anzeigen
who
w
last -n 20

# 2. Aktive Netzwerkverbindungen
ss -tulnp
netstat -tulnp 2>/dev/null || ss -tulnp

# 3. Laufende Prozesse prüfen
ps aux --forest
pstree -a

# 4. Kürzlich geänderte Dateien
find /etc /usr /bin /sbin -newer /tmp/reference -type f 2>/dev/null
# Referenzzeit erstellen: touch /tmp/reference

# 5. Cron-Jobs prüfen
crontab -l
ls -la /etc/cron*
systemctl list-timers

# 6. Systemd-Services prüfen
systemctl list-units --state=failed
systemctl list-units --type=service | grep -v inactive
```

### 4.2 Kompromittiertes System — Sofortmaßnahmen
```bash
# 1. SOFORT: Netzwerk isolieren (wenn möglich)
# Proxmox: Netzwerk der VM/LXC trennen

# 2. Snapshot erstellen (für forensische Analyse)
qm snapshot <VMID> "compromise-$(date +%F-%H%M)"

# 3. Logs sichern BEVOR etwas bereinigt wird
tar -czf /tmp/logs-backup-$(date +%F).tar.gz /var/log/

# 4. Alle SSH-Schlüssel invalidieren
# In authorized_keys: alle Schlüssel löschen
# Neue Schlüssel generieren

# 5. Alle Passwörter ändern (Vault, DB, API-Keys)

# 6. Aus Snapshot wiederherstellen (sauberer Zustand)
# qm rollback <VMID> <sauberer-snapshot>
```

## 5. Backup-Verifikation

```bash
# Backup-Restore IMMER regelmäßig testen!
# "Ein ungetestetes Backup ist kein Backup"

# PostgreSQL Backup testen
pg_restore --list /backup/synapse_2025-01-01.dump | head -20
# Probe-Restore in separater Datenbank:
createdb test_restore
pg_restore -d test_restore /backup/synapse_2025-01-01.dump
# Tabellen prüfen
psql -d test_restore -c "\dt"
# Aufräumen
dropdb test_restore

# Docker Volume Backup testen
tar -tzf /backup/volumes-2025-01-01.tar.gz | head -20
```
