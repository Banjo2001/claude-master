# Nextcloud AIO — Playbook Wissensdatenbank
# Stand: 2026-04 | Nextcloud AIO (All-In-One)

## 1. Überblick Nextcloud AIO

Nextcloud AIO (All-In-One) ist eine Docker-basierte Nextcloud-Installation,
die alle Komponenten automatisch verwaltet:
- Nextcloud (Core)
- PostgreSQL (Datenbank)
- Redis (Cache)
- Nextcloud Office (Collabora)
- Nextcloud Talk (TURN-Server)
- Imaginary (Bildvorschau)
- ClamAV (Virenscan)
- Vaultwarden (Passwort-Manager, optional)

### Hauptvorteile AIO:
- Automatische Updates aller Komponenten
- Integriertes Backup-System
- Einfachere Verwaltung als manuelle Installation
- Let's Encrypt automatisch integriert

## 2. Kritische Anforderungen

### 2.1 Container-Name DARF NICHT geändert werden
```yaml
container_name: nextcloud-aio-mastercontainer
# BEGRÜNDUNG: Der interne Update-Mechanismus und alle AIO-Container
# referenzieren diesen exakten Namen. Änderung = Systemfehler!
```

### 2.2 Docker-Socket wird benötigt
```yaml
volumes:
  - /var/run/docker.sock:/var/run/docker.sock:ro
# SICHERHEITSHINWEIS: Dies gibt dem Container erweiterten Zugriff
# auf das Docker-System. Er kann neue Container starten/stoppen.
# Dies ist für AIO notwendig und NUR für den Mastercontainer erlaubt.
# Alle anderen Container: KEIN Docker-Socket!
```

### 2.3 Dedicated Docker-Netzwerk erforderlich
```bash
# Netzwerk erstellen (BEVOR compose up):
docker network create nextcloud-aio
# AIO benötigt dieses spezifische Netzwerk zur Kommunikation
```

## 3. Ports und Firewall

```
80/TCP    — HTTP (ACME Challenge für Let's Encrypt) — MUSS offen sein
443/TCP   — HTTPS (Nextcloud)
443/UDP   — HTTP/3 (optional, besser Performance)
8080/TCP  — AIO Admin-Interface (NUR via IP aufrufen, nicht via Domain!)
8443/TCP  — AIO Admin-Interface mit gültigem Zertifikat
3478/TCP  — TURN-Server (Nextcloud Talk)
3478/UDP  — TURN-Server (Nextcloud Talk)
```

**WICHTIG:** Port 8080 niemals direkt aus dem Internet zugänglich machen!
Nur für initiales Setup lokal oder via SSH-Tunnel verwenden.

## 4. AIO Admin-Interface verwenden

```bash
# Setup-URL (erster Aufruf):
# https://<SERVER_IP>:8080
# NICHT via Domain aufrufen — SSL-Fehler wäre zu erwarten

# Nach TLS-Einrichtung:
# https://cloud.example.com:8443
# Oder via Nginx Reverse Proxy auf 443/TCP
```

## 5. Docker Compose (Mastercontainer)

```yaml
# compose.yml für Nextcloud AIO
services:
  nextcloud-aio-mastercontainer:
    # WICHTIG: :latest ist hier ausnahmsweise akzeptiert
    # AIO verwaltet eigene Versionen intern
    # Für reproduzierbare Deployments: spezifische Version nutzen
    image: nextcloud/all-in-one:latest  # Ausnahme — AIO hat eigenes Versionsmanagement
    container_name: nextcloud-aio-mastercontainer  # DARF NICHT geändert werden!
    restart: unless-stopped
    
    volumes:
      # Docker-Socket (NOTWENDIG für AIO — nur Mastercontainer)
      - /var/run/docker.sock:/var/run/docker.sock:ro
      # AIO-Konfiguration
      - nextcloud_aio_mastercontainer:/mnt/docker-aio-config
    
    ports:
      - "8080:8080"  # Admin-Interface — nur für Setup, danach sperren!
    
    environment:
      - APACHE_PORT=11000          # AIO-interne Port (Nginx leitet darauf weiter)
      - APACHE_IP_BINDING=0.0.0.0
      - NEXTCLOUD_DATADIR=/mnt/ncdata  # Datenpfad
      - TZ=Europe/Berlin
    
    networks:
      - nextcloud-aio
    
    # SICHERHEIT: Socket-Zugriff ist notwendig — kein cap_drop möglich
    # Alle anderen AIO-Container erhalten KEIN Socket-Zugriff

volumes:
  nextcloud_aio_mastercontainer:

networks:
  nextcloud-aio:
    external: true  # Muss vorher mit 'docker network create nextcloud-aio' erstellt werden
```

## 6. Nginx Reverse Proxy für AIO

```nginx
# /etc/nginx/sites-available/nextcloud
# AIO läuft intern auf Port 11000 (konfigurierbar via APACHE_PORT)

server {
    listen 80;
    server_name cloud.example.com;
    
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    
    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name cloud.example.com;
    
    ssl_certificate /etc/letsencrypt/live/cloud.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/cloud.example.com/privkey.pem;
    
    # Große Uploads erlauben (Nextcloud braucht das)
    client_max_body_size 10G;
    
    # Timeouts für große Uploads
    proxy_read_timeout 86400;
    proxy_send_timeout 86400;
    proxy_connect_timeout 86400;
    send_timeout 86400;
    
    location / {
        proxy_pass http://localhost:11000;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Host $host;
        proxy_redirect off;
        
        # WebSocket-Support (für Nextcloud Talk)
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

## 7. AIO Backup-System

AIO hat ein integriertes Backup-System:
```
AIO Admin-Interface → Backup → Configure Backup
```

### 7.1 Backup-Ziele (unterstützt)
- Lokales Verzeichnis (für Proxmox PBS oder externe Festplatte)
- Borgmatic (für Remote-Backups)

### 7.2 Backup-Verzeichnis einrichten
```bash
# Lokales Backup-Verzeichnis
mkdir -p /mnt/backups/nextcloud
chown -R 33:33 /mnt/backups/nextcloud  # www-data UID

# In AIO Admin-Interface eintragen:
# Backup location: /mnt/backups/nextcloud
```

## 8. Nextcloud Talk TURN-Server

AIO bringt einen integrierten TURN-Server mit.
Für externe Verbindungen muss Coturn separat eingerichtet werden:

```bash
# In AIO Admin-Interface:
# Talk → STUN/TURN → Eigenen TURN-Server konfigurieren
# Host: turn.example.com
# Secret: <VIA_VAULT>
# Protocol: TLS
```

## 9. Updates

```bash
# AIO-Updates werden über das Admin-Interface verwaltet
# AIO Admin-Interface → Containers → Pull & Update

# Oder via API:
curl -sk -X POST \
  -u ":<ADMIN_PASSWORD>" \
  https://cloud.example.com:8443/api/docker-actions/pull

# WICHTIG: VOR jedem Update:
# 1. Backup durchführen
# 2. Proxmox-Snapshot erstellen
```

## 10. Troubleshooting

```bash
# AIO Mastercontainer Logs
docker logs nextcloud-aio-mastercontainer -f

# Alle AIO-Container anzeigen
docker ps | grep nextcloud-aio

# AIO Apache/Nextcloud Logs
docker logs nextcloud-aio-nextcloud -f

# Container neu starten (wenn hängt)
docker restart nextcloud-aio-mastercontainer

# Berechtigungsprobleme beheben
docker exec -it nextcloud-aio-nextcloud bash
# Im Container:
chown -R www-data:www-data /mnt/ncdata
```
