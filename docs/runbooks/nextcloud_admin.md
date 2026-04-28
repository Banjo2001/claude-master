# Runbook: Nextcloud AIO Administration

> Stand: 2026-04 | Nextcloud AIO (all-in-one:latest)

## 1. Dienst-Status prüfen

```bash
# Mastercontainer-Status
docker inspect nextcloud-aio-mastercontainer --format='{{.State.Status}}'

# Alle AIO-Container anzeigen
docker ps --filter "name=nextcloud-aio"

# Mastercontainer-Logs
docker logs nextcloud-aio-mastercontainer --tail=100

# Nextcloud-Status via API
curl -s https://cloud.example.com/status.php | jq .
# Erwartet: {"installed":true,"maintenance":false,...}
```

## 2. Admin-Interface aufrufen

```
URL: https://<SERVER-IP>:8080
WICHTIG: NUR über IP, NIEMALS über Domain-Namen!

Begründung: Der Mastercontainer prüft TLS-Zertifikate beim ersten Aufruf.
Ein Domain-Aufruf würde scheitern, weil das Zertifikat noch nicht existiert.
```

## 3. Update

```bash
# Methode 1: Über Admin-Interface (empfohlen)
# https://<IP>:8080 → "Check for updates" → Update starten
# AIO lädt neue Images und startet Container neu

# Methode 2: Mastercontainer aktualisieren
docker pull nextcloud/all-in-one:latest
docker compose -f /opt/nextcloud-aio/compose.yml up -d

# Methode 3: Via Ansible
ansible-playbook \
  --vault-password-file ~/.vault_pass.txt \
  ansible/playbooks/nextcloud_aio.yml
```

## 4. Neustart

```bash
# Mastercontainer neu starten (startet alle Sub-Container neu)
docker compose -f /opt/nextcloud-aio/compose.yml restart

# Oder via Docker direkt
docker restart nextcloud-aio-mastercontainer
```

## 5. Backup

```bash
# Methode 1: AIO-integriertes Backup (empfohlen)
# Admin-Interface → Backup-Tab → Backup erstellen
# Backup-Pfad: /opt/nextcloud-aio/data/backup

# Methode 2: PBS Snapshot (VM/LXC-Ebene)
# Proxmox Web-UI → Container auswählen → Backup → Jetzt sichern

# Methode 3: Volumes manuell
docker compose -f /opt/nextcloud-aio/compose.yml stop
tar -czf /opt/backups/nextcloud-$(date +%Y%m%d).tar.gz /opt/nextcloud-aio/data
docker compose -f /opt/nextcloud-aio/compose.yml start
```

## 6. Restore

```bash
# Via AIO Admin-Interface:
# https://<IP>:8080 → Backup-Tab → Restore

# WICHTIG: Vor Restore alle AIO-Container stoppen:
docker stop $(docker ps --filter "name=nextcloud-aio" -q)
```

## 7. Nextcloud occ-Befehle

```bash
# occ im Nextcloud-Container ausführen
docker exec -it nextcloud-aio-nextcloud \
  php occ <BEFEHL>

# Wartungsmodus aktivieren/deaktivieren
docker exec -it nextcloud-aio-nextcloud php occ maintenance:mode --on
docker exec -it nextcloud-aio-nextcloud php occ maintenance:mode --off

# Datenbank-Wartung
docker exec -it nextcloud-aio-nextcloud php occ db:add-missing-indices
docker exec -it nextcloud-aio-nextcloud php occ db:convert-filecache-bigint

# Dateien-Scan (nach manuellen Dateioperationen)
docker exec -it nextcloud-aio-nextcloud php occ files:scan --all

# Apps auflisten
docker exec -it nextcloud-aio-nextcloud php occ app:list
```

## 8. Logs

```bash
# Nextcloud-Logs (im Datenverzeichnis)
tail -f /opt/nextcloud-aio/data/nextcloud.log

# Mastercontainer-Logs
docker logs -f nextcloud-aio-mastercontainer

# Apache-Logs (Nextcloud-Container)
docker logs -f nextcloud-aio-apache
```

## 9. Häufige Probleme

| Problem | Ursache | Lösung |
|---------|---------|--------|
| Admin-Interface nicht erreichbar | Falscher Aufruf via Domain | IP statt Domain verwenden |
| Container starten nicht | Docker-Netzwerk fehlt | `docker network create nextcloud-aio` |
| Container-Name falsch | Name geändert | MUSS `nextcloud-aio-mastercontainer` sein |
| Update-Mechanismus defekt | Container-Name geändert | Container löschen, mit korrektem Namen neu starten |
| Speicherplatz voll | /opt/nextcloud-aio/data voll | `check_disk_usage.sh` ausführen, Daten aufräumen |
| SSL-Zertifikat-Fehler | Domain nicht erreichbar | DNS prüfen, Port 80/443 offen? |
