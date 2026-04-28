# Wissensdatenbank: Let's Encrypt + Certbot

> Stand: 2026-04 | Gilt für: Debian 12/13, Ubuntu 22.04/24.04

---

## 1. Grundkonzept

**Let's Encrypt** ist eine kostenlose Certificate Authority (CA) die TLS-Zertifikate ausstellt.
**Certbot** ist das offizielle CLI-Tool zum Beantragen und Erneuern dieser Zertifikate.

### Herausforderungstypen (Challenges)

| Typ | Voraussetzung | Vorteil | Nachteil |
|-----|---------------|---------|----------|
| HTTP-01 | Port 80 erreichbar | Einfach | Port 80 muss frei sein |
| DNS-01 | DNS-API-Zugang | Keine offenen Ports | DNS-Provider muss API haben |
| TLS-ALPN-01 | Port 443 erreichbar | — | Selten genutzt |

**Diese Infrastruktur nutzt HTTP-01** (standalone mode) für Matrix Synapse.

---

## 2. Certbot Installation

```bash
# Debian/Ubuntu (via apt):
apt install -y certbot

# Oder via snap (immer aktuell):
snap install --classic certbot
ln -s /snap/bin/certbot /usr/bin/certbot
```

---

## 3. Certbot Modi

### Standalone (für Matrix)
```bash
# WARUM: Nginx läuft beim ersten Aufruf noch nicht.
# Certbot startet kurz seinen eigenen HTTP-Server auf Port 80.
certbot certonly \
  --standalone \
  --non-interactive \
  --agree-tos \
  --email admin@example.com \
  --domain matrix.example.com \
  --config-dir /opt/matrix/certs \
  --work-dir /tmp/certbot-work \
  --logs-dir /tmp/certbot-logs
```

**KRITISCH: `--config-dir` statt `--cert-path`!**
- `--config-dir` = wo certbot Zertifikate + Konfiguration ablegt
- `--cert-path` existiert bei `certonly` NICHT als Parameter
- Standard ohne `--config-dir`: `/etc/letsencrypt/`

### Webroot (wenn Webserver läuft)
```bash
# Webserver muss /.well-known/acme-challenge/ bedienen können
certbot certonly \
  --webroot \
  --webroot-path /var/www/html \
  --email admin@example.com \
  --domain example.com
```

---

## 4. Verzeichnisstruktur nach certbot

Nach `certbot certonly --config-dir /opt/matrix/certs`:

```
/opt/matrix/certs/
├── live/                          ← Symlinks auf aktuelle Zertifikate
│   └── matrix.example.com/
│       ├── fullchain.pem          ← Zertifikat + Kette (für Nginx)
│       ├── cert.pem               ← Nur Zertifikat
│       ├── chain.pem              ← Nur Zwischenzertifikat
│       └── privkey.pem            ← Privater Schlüssel (geheim!)
├── archive/                       ← Echte Dateien (alle Versionen)
│   └── matrix.example.com/
│       ├── fullchain1.pem
│       └── privkey1.pem
├── renewal/                       ← Renewal-Konfiguration
│   └── matrix.example.com.conf
└── accounts/                      ← ACME-Account-Daten
```

**WICHTIG für Docker-Mounts:**
- Nginx mount: `matrix_base_dir/certs:/etc/nginx/certs:ro`
- Coturn mount: `matrix_base_dir/certs:/etc/ssl:ro`
- Im Container: `/etc/nginx/certs/live/matrix.example.com/fullchain.pem`

---

## 5. Zertifikat-Erneuerung

Let's Encrypt Zertifikate laufen nach 90 Tagen ab. Certbot erneuert automatisch wenn < 30 Tage übrig.

```bash
# Manuell erneuern (testen):
certbot renew --dry-run --config-dir /opt/matrix/certs

# Manuell erneuern (echt):
certbot renew --config-dir /opt/matrix/certs

# Nach Erneuerung Dienste neu starten:
docker compose -f /opt/matrix/compose.yml exec nginx nginx -s reload
docker compose -f /opt/matrix/compose.yml restart coturn
```

### Automatische Erneuerung via Cron (empfohlen)
```bash
# /etc/cron.d/certbot-renewal
0 3 * * * root certbot renew --config-dir /opt/matrix/certs --quiet \
  && docker compose -f /opt/matrix/compose.yml exec nginx nginx -s reload \
  && docker compose -f /opt/matrix/compose.yml restart coturn
```

---

## 6. Voraussetzungen für HTTP-01 Challenge

1. **Port 80 in UFW offen:**
   ```bash
   ufw allow 80/tcp comment "HTTP Let's Encrypt"
   ```

2. **Port 80 an certbot gebunden:**
   - Im `--standalone` Modus: Certbot bindet selbst auf Port 80
   - KEIN anderer Prozess darf auf Port 80 laufen (z.B. Nginx stoppen)

3. **DNS-Eintrag muss existieren:**
   ```
   matrix.example.com  A  <SERVER-IP>
   ```
   - Certbot prüft: Can I reach http://matrix.example.com/.well-known/acme-challenge/ ?
   - DNS-TTL abwarten bevor certbot gestartet wird!

---

## 7. Certbot Troubleshooting

### "Connection refused" oder Timeout
```bash
# Port 80 prüfen:
ss -tlnp | grep :80
ufw status | grep 80
curl -v http://matrix.example.com/.well-known/acme-challenge/test
```

### "Name does not resolve"
```bash
# DNS prüfen:
dig matrix.example.com +short
# Muss Server-IP zurückgeben
```

### "Too many requests" (Rate Limit)
- Let's Encrypt: 5 Zertifikate pro Domain pro 7 Tage
- **Staging-Server zum Testen nutzen:**
  ```bash
  certbot certonly --staging --standalone ...
  ```
- Staging-Zertifikate sind NICHT vertrauenswürdig, nur zum Testen

### Zertifikat manuell inspizieren
```bash
openssl x509 -in /opt/matrix/certs/live/matrix.example.com/fullchain.pem \
  -noout -dates -subject
```

---

## 8. Zertifikat für mehrere Domains (Coturn)

Wenn Coturn auf `matrix.example.com` läuft (gleiche IP wie Synapse):
```bash
certbot certonly --standalone \
  --config-dir /opt/matrix/certs \
  --domain matrix.example.com
  # Kein zweites --domain nötig wenn Coturn auf gleicher Domain
```

---

## 9. Sicherheitshinweise

| Aspekt | Empfehlung |
|--------|------------|
| `privkey.pem` | Rechte 0640, Owner root:root |
| Zertifikat-Verzeichnis | Rechte 0700 für `/opt/matrix/certs` |
| Docker-Mount | `:ro` (read-only) für alle Zertifikats-Mounts |
| Vault | Privater Schlüssel NIEMALS in vault.yml oder Repo |
| Backup | Privaten Schlüssel in Passwort-Manager sichern |

---

## 10. Let's Encrypt Staging vs. Production

| Umgebung | URL | Vertrauenswürdig | Rate Limit |
|----------|-----|-----------------|------------|
| **Production** | acme-v02.api.letsencrypt.org | JA | Streng (5/7 Tage) |
| **Staging** | acme-staging-v02.api.letsencrypt.org | NEIN | Locker (zum Testen) |

**Workflow für First-Deploy:**
1. Zuerst mit `--staging` testen
2. DNS korrekt? Certbot-Aufruf erfolgreich?
3. Dann echte Zertifikate holen (ohne `--staging`)

---

*Relevante Ansible-Rolle: `ansible/roles/matrix_synapse/tasks/nginx.yml`*
*Certbot-Konfiguration: `--config-dir {{ matrix_base_dir }}/certs`*
