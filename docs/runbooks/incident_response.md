# Runbook: Incident Response

> Stand: 2026-04 | Sofortmaßnahmen bei Sicherheitsvorfällen

## 1. Allgemeines Vorgehen

```
1. ERKENNEN  — Was ist passiert? Welche Systeme betroffen?
2. EINDÄMMEN — Schaden begrenzen, Angreifer aussperren
3. ANALYSIEREN — Wie ist es passiert? Was wurde kompromittiert?
4. BEREINIGEN — Schadsoftware entfernen, Schwachstelle schließen
5. WIEDERHERSTELLEN — Dienste aus sauberem Backup wiederherstellen
6. DOKUMENTIEREN — Was war passiert, was wurde getan?
```

## 2. Verdächtiger SSH-Zugriff

```bash
# Aktive SSH-Verbindungen anzeigen
who
ss -tnp | grep :22

# Letzte Logins
last | head -20
lastb | head -20  # fehlgeschlagene Versuche

# Sofortmaßnahme: Verdächtige Verbindung trennen
pkill -u <USERNAME>

# Fail2Ban Status
fail2ban-client status sshd
fail2ban-client status

# IP manuell sperren
ufw deny from <VERDAECHTIGE-IP>
fail2ban-client set sshd banip <VERDAECHTIGE-IP>

# SSH-Keys prüfen
cat /root/.ssh/authorized_keys
# Unbekannte Keys sofort entfernen!
```

## 3. Kompromittierter Server

```bash
# SOFORT: Server vom Netz nehmen (Proxmox Web-UI)
# Proxmox Web-UI → Container/VM → "Herunterfahren"
# Oder Network-Interface deaktivieren

# Auf Proxmox Host:
qm set 101 --net0 virtio,bridge=vmbr0,firewall=1,link_down=1

# Snapshot des aktuellen Zustands für forensische Analyse
bash scripts/proxmox/pve_snapshot_create.sh 101 "forensic-$(date +%Y%m%d-%H%M)" "Forensik-Snapshot"

# Sauberes System aus letztem bekannten guten Backup wiederherstellen
# Docs: docs/runbooks/backup_restore.md
```

## 4. Secret-Leak (Secrets im Git)

```bash
# Sofort: Betroffene Secrets rotieren BEVOR History bereinigt wird!
# (Selbst wenn nicht öffentlich — Rotation ist Pflicht)

# Betroffene Secrets identifizieren
bash scripts/security/audit_secrets.sh

# Secret aus Git-History entfernen (git filter-repo):
pip install git-filter-repo
git filter-repo --path <DATEI> --invert-paths

# Oder: Passwort-String aus History entfernen
git filter-repo --replace-text <(echo '<ALTES_SECRET>==>REMOVED')

# Force-Push (ACHTUNG: History wird überschrieben!)
git push --force origin main

# Ansible Vault Passwort rotieren
bash scripts/security/rotate_vault_password.sh

# GitHub/Gitea informieren wenn Public Repo!
# Alle ausgestellten API-Tokens und Passwörter sofort invalidieren
```

## 5. Matrix unter Spam-Angriff

```bash
# Rate-Limiting prüfen (homeserver.yaml)
# rc_login, rc_registration, rc_joins sollten aktiv sein

# Spammer-Account sperren (Admin-API)
ADMIN_TOKEN="syt_..."
curl -X PUT \
  "https://matrix.example.com/_synapse/admin/v2/users/@spammer:example.com" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"deactivated": true}'

# Registrierung deaktivieren (falls noch offen)
# homeserver.yaml: enable_registration: false
# Dann Synapse neu starten

# Fail2Ban Matrix-Jail prüfen
fail2ban-client status matrix-synapse

# IP direkt sperren
ufw deny from <ANGREIFER-IP>
```

## 6. Nextcloud-Angriff

```bash
# Wartungsmodus aktivieren
docker exec -it nextcloud-aio-nextcloud \
  php occ maintenance:mode --on

# Verdächtiger Nutzer: Account sperren
docker exec -it nextcloud-aio-nextcloud \
  php occ user:disable <USERNAME>

# Alle Sessions löschen
docker exec -it nextcloud-aio-nextcloud \
  php occ session:delete --all

# Logs prüfen
tail -200 /opt/nextcloud-aio/data/nextcloud.log | grep -i "login\|fail\|brute"

# Wartungsmodus deaktivieren
docker exec -it nextcloud-aio-nextcloud \
  php occ maintenance:mode --off
```

## 7. DDoS / Ressourcen-Erschöpfung

```bash
# Aktuelle Verbindungen
ss -tnp | wc -l
ss -tnp state established | head -20

# Top-IPs nach Verbindungsanzahl
ss -tn state established | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -rn | head -20

# Verdächtige IP sperren
ufw deny from <IP>

# Rate-Limiting in Nginx verschärfen (matrix/nginx.conf):
# limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
# limit_req zone=api burst=20 nodelay;

# Hetzner Firewall (Hardware-Level) aktivieren:
# Hetzner Robot → Server → Firewall → Regel hinzufügen
```

## 8. Kontakte und Eskalation

```
Primärer Admin:   <DEIN_NAME> — <DEINE_EMAIL>
Hetzner Support:  https://robot.hetzner.com/support
BSI CERT:         https://www.bsi.bund.de/cert (bei ernsten Vorfällen)

Meldepflicht (DSGVO Art. 33):
- Datenpanne mit Personendaten → Meldung an Aufsichtsbehörde binnen 72h!
- Template: docs/changelogs/ → Incident-Report anlegen
```

## 9. Incident-Dokumentation

```markdown
# Incident Report — YYYY-MM-DD

## Zeitlinie
- HH:MM — Incident erkannt
- HH:MM — Maßnahme X eingeleitet
- HH:MM — Dienste wiederhergestellt

## Betroffene Systeme
- Matrix Synapse / Nextcloud / SSH / etc.

## Ursache
- Beschreibung

## Maßnahmen
- Beschreibung der Gegenmaßnahmen

## Präventive Maßnahmen
- Was wird zukünftig anders gemacht?
```
