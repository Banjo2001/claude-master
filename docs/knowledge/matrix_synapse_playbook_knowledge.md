# Matrix Synapse — Playbook Wissensdatenbank
# Stand: 2026-04 | Matrix Synapse 1.x

## 1. Überblick Stack-Komponenten

Matrix Synapse ist ein selbstgehosteter Matrix-Homeserver.
Der vollständige Stack besteht aus:

```
┌─────────────────────────────────────────────────┐
│ Internet                                         │
│    ↓ HTTPS/443                                  │
│ ┌──────────────────────────────────────────┐    │
│ │ Nginx (Reverse Proxy + TLS via certbot)  │    │
│ └──────┬───────────────────────────────────┘    │
│        │ localhost:8008                          │
│ ┌──────▼──────────────────────────────────┐    │
│ │ Matrix Synapse (Docker Container)        │    │
│ └──────┬──────────────────────────────────┘    │
│        ├─ PostgreSQL 16 (Datenbank)             │
│        ├─ Redis 7 (Worker + Rate-Limiting)      │
│        └─ Coturn (TURN für Voice/Video)         │
│                                                  │
│ ┌──────────────────────────────────────────┐    │
│ │ Prometheus + Node Exporter + Grafana     │    │
│ └──────────────────────────────────────────┘    │
└─────────────────────────────────────────────────┘
```

## 2. Kritische Sicherheitsregeln

### 2.1 Registrierung DEAKTIVIEREN
```yaml
# homeserver.yaml — IMMER:
enable_registration: false
# BEGRÜNDUNG: Offene Registrierung = Spam, Missbrauch, Datenpannen
# Nutzer nur via Admin-API oder Einladungslink anlegen
```

### 2.2 Nginx proxy_pass ohne trailing slash
```nginx
# RICHTIG (kein / am Ende):
proxy_pass http://localhost:8008;

# FALSCH — verursacht Signaturfehler bei Matrix!
# proxy_pass http://localhost:8008/;
```

### 2.3 Federation
```yaml
# homeserver.yaml
federation_domain_whitelist: []  # Leer = alle, oder explizite Liste
suppress_key_server_warning: false

# /.well-known/matrix/server MUSS korrekt gesetzt sein:
# {"m.server": "matrix.example.com:443"}
```

## 3. Ports und Firewall-Regeln

```
80/TCP    — ACME Challenge (Let's Encrypt) — MUSS offen sein
443/TCP   — HTTPS (Matrix Client + Federation)
3478/TCP  — TURN (Coturn)
3478/UDP  — TURN (Coturn)
5349/TCP  — TURNS (Coturn TLS)
5349/UDP  — TURNS (Coturn TLS)
10000/UDP — TURN Media (Coturn Media-Range Anfang)
```

## 4. Docker Compose Stack (Referenz)

### 4.1 Image-Versionen (Stand 2026-04, regelmäßig prüfen!)
```
matrixdotorg/synapse:v1.123.0    # https://github.com/element-hq/synapse/releases
postgres:16.4                     # https://hub.docker.com/_/postgres/tags
redis:7.2-alpine                  # https://hub.docker.com/_/redis/tags
coturn/coturn:4.6                 # https://hub.docker.com/r/coturn/coturn/tags
grafana/grafana:10.4.2            # https://hub.docker.com/r/grafana/grafana/tags
prom/prometheus:v2.51.0          # https://hub.docker.com/r/prom/prometheus/tags
prom/node-exporter:v1.8.0        # https://hub.docker.com/r/prom/node-exporter/tags
```

### 4.2 PostgreSQL für Synapse vorbereiten
```sql
-- Datenbank mit korrekten Einstellungen erstellen
-- locale: C (WICHTIG! Nicht UTF-8 bei Synapse)
CREATE USER synapse_user WITH PASSWORD '<PASSWORT>';
CREATE DATABASE synapse
    ENCODING 'UTF8'
    LC_COLLATE='C'
    LC_CTYPE='C'
    template=template0
    OWNER synapse_user;
```

### 4.3 Synapse homeserver.yaml — wichtige Einstellungen
```yaml
# Server-ID (NIEMALS nach Erst-Setup ändern!)
server_name: "example.com"  # Ihre Domain — ohne subdomain!

# Datenbank
database:
  name: psycopg2
  args:
    user: synapse_user
    password: "<VIA_VAULT>"
    database: synapse
    host: localhost
    cp_min: 5
    cp_max: 10

# Redis (für Worker)
redis:
  enabled: true
  host: localhost
  port: 6379

# TLS — Nginx übernimmt TLS, Synapse hört nur auf localhost
listeners:
  - port: 8008
    tls: false
    type: http
    x_forwarded: true  # WICHTIG: Nginx leitet IP weiter
    resources:
      - names: [client, federation]
        compress: false

# Medien
media_store_path: "/data/media_store"
max_upload_size: "50M"

# Rate-Limiting (Schutz gegen Spam)
rc_messages_per_second: 0.2
rc_message_burst_count: 10

# Registrierung DEAKTIVIERT
enable_registration: false

# Reporting (an Matrix.org) — deaktivieren für Datenschutz
report_stats: false
```

## 5. Coturn Konfiguration

```
# /etc/coturn/turnserver.conf
listening-port=3478
tls-listening-port=5349
listening-ip=<SERVER_IP>
relay-ip=<SERVER_IP>
external-ip=<SERVER_IP>

# Auth mit HMAC (muss mit Synapse übereinstimmen)
use-auth-secret
static-auth-secret=<VIA_VAULT>

# Realm = Ihre Domain
realm=example.com

# TLS
cert=/etc/letsencrypt/live/matrix.example.com/fullchain.pem
pkey=/etc/letsencrypt/live/matrix.example.com/privkey.pem

# Log
log-file=/var/log/coturn/coturn.log

# Sicherheit
no-tcp-relay
no-multicast-peers
denied-peer-ip=10.0.0.0-10.255.255.255    # RFC 1918
denied-peer-ip=172.16.0.0-172.31.255.255  # RFC 1918
denied-peer-ip=192.168.0.0-192.168.255.255 # RFC 1918
```

## 6. Nginx Konfiguration (Matrix)

```nginx
# /etc/nginx/sites-available/matrix
server {
    listen 80;
    server_name matrix.example.com;
    
    # Let's Encrypt Challenge
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    
    # Alles andere zu HTTPS
    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name matrix.example.com;
    
    ssl_certificate /etc/letsencrypt/live/matrix.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/matrix.example.com/privkey.pem;
    
    # Moderne TLS-Einstellungen
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:...;
    ssl_prefer_server_ciphers off;
    
    # Matrix Synapse
    location / {
        proxy_pass http://localhost:8008;  # KEIN trailing slash!
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Host $host;
        
        # Große Uploads erlauben (für Medien)
        client_max_body_size 50M;
        proxy_read_timeout 600;
    }
    
    # .well-known für Matrix Federation
    location /.well-known/matrix/server {
        default_type application/json;
        return 200 '{"m.server": "matrix.example.com:443"}';
        add_header Access-Control-Allow-Origin *;
    }
    
    location /.well-known/matrix/client {
        default_type application/json;
        return 200 '{"m.homeserver": {"base_url": "https://matrix.example.com"}}';
        add_header Access-Control-Allow-Origin *;
    }
}
```

## 7. Matrix Admin-Operationen

```bash
# Nutzer anlegen (via Admin-API)
curl -sk -X POST \
  -H "Authorization: Bearer <ADMIN_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"password":"<PASSWORT>","admin":false}' \
  "https://matrix.example.com/_synapse/admin/v2/users/@alice:example.com"

# Nutzer deaktivieren
curl -sk -X PUT \
  -H "Authorization: Bearer <ADMIN_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"deactivated": true}' \
  "https://matrix.example.com/_synapse/admin/v2/users/@alice:example.com"

# Server-Statistiken
curl -sk \
  -H "Authorization: Bearer <ADMIN_TOKEN>" \
  "https://matrix.example.com/_synapse/admin/v1/server_version"

# Datenbank bereinigen (Purge history)
curl -sk -X POST \
  -H "Authorization: Bearer <ADMIN_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"delete_local_events": false, "purge_up_to_event_id": "<EVENT_ID>"}' \
  "https://matrix.example.com/_synapse/admin/v1/purge_history/<ROOM_ID>"
```

## 8. Backup-Strategie Matrix

### 8.1 Was gesichert werden muss:
- PostgreSQL-Datenbank (täglich via pg_dump)
- Synapse Medien-Dateien (/data/media_store/)
- homeserver.yaml (Konfiguration)
- TLS-Zertifikate (automatisch via certbot erneuert)

### 8.2 PostgreSQL Backup
```bash
# Backup (täglich via Cron 03:00 Uhr)
docker exec matrix-postgres pg_dump \
  -U synapse_user \
  -Fc \                          # Custom Format (komprimiert, schneller Restore)
  synapse > /backup/synapse_$(date +%F).dump

# Retention: 30 Tage
find /backup/ -name "synapse_*.dump" -mtime +30 -delete

# Restore (bei Bedarf)
docker exec -i matrix-postgres pg_restore \
  -U synapse_user \
  -d synapse \
  --clean \
  < /backup/synapse_2025-01-01.dump
```

## 9. Monitoring mit Prometheus

```yaml
# homeserver.yaml — Prometheus-Metriken aktivieren
enable_metrics: true
metrics_flags:
  known_servers: false  # Verhindert großes Cardinality-Problem

# Prometheus-Scrape-Config
# prometheus.yml:
scrape_configs:
  - job_name: 'synapse'
    metrics_path: /_synapse/metrics
    static_configs:
      - targets: ['localhost:8008']
```

## 10. Skalierung mit Workers

Für größere Installationen kann Synapse in Worker-Prozesse aufgeteilt werden:

```yaml
# homeserver.yaml
worker_replication_secret: "<VIA_VAULT>"

# Separate Worker-Konfigurationen:
# - federation_sender: Sendet Federation-Nachrichten
# - media_repository: Verarbeitet Medien-Uploads
# - client_reader: Beantwortet Client-Anfragen
# - event_creator: Erstellt neue Events
```

**WICHTIG:** Workers erfordern Redis als Message-Broker.
Für Einzelserver-Installationen können Workers weggelassen werden.
