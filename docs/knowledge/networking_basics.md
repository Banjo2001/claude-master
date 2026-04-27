# Netzwerk-Grundlagen — Wissensdatenbank
# Stand: 2026-04

## 1. IP-Adressen

### 1.1 Private IP-Bereiche (RFC 1918)
```
10.0.0.0/8          — Klasse A (10.0.0.1 – 10.255.255.254)
172.16.0.0/12       — Klasse B (172.16.0.1 – 172.31.255.254)
192.168.0.0/16      — Klasse C (192.168.0.1 – 192.168.255.254)
```

### 1.2 Dokumentations-Adressen (für Beispiele/Platzhalter)
```
192.0.2.0/24        — TEST-NET-1 (RFC 5737) — NIEMALS im echten Netz verwenden
198.51.100.0/24     — TEST-NET-2 (RFC 5737)
203.0.113.0/24      — TEST-NET-3 (RFC 5737)
2001:db8::/32       — IPv6 Dokumentation (RFC 3849)
```

### 1.3 Subnetz-Rechnung (CIDR-Notation)
```
/24 = 255.255.255.0  → 254 Hosts
/25 = 255.255.255.128 → 126 Hosts
/26 = 255.255.255.192 → 62 Hosts
/27 = 255.255.255.224 → 30 Hosts
/28 = 255.255.255.240 → 14 Hosts
/29 = 255.255.255.248 → 6 Hosts
/30 = 255.255.255.252 → 2 Hosts (Point-to-Point)
```

## 2. DNS

### 2.1 Wichtige DNS-Einträge
```
A     → IPv4-Adresse (example.com → 192.0.2.10)
AAAA  → IPv6-Adresse (example.com → 2001:db8::10)
CNAME → Alias (www.example.com → example.com)
MX    → Mail-Server (mit Priorität)
TXT   → Texteintrag (für SPF, DKIM, Verifizierung)
SRV   → Dienst-Eintrag (für Matrix: _matrix._tcp)
CAA   → Certificate Authority Authorization (welche CA darf Zertifikate ausstellen)
```

### 2.2 Matrix-spezifische DNS-Einträge
```
# Für Federation (Domain-Discovery):
_matrix._tcp.example.com. 3600 IN SRV 10 5 443 matrix.example.com.

# Oder einfacher via .well-known (kein SRV nötig):
# https://example.com/.well-known/matrix/server
# {"m.server": "matrix.example.com:443"}
```

### 2.3 DNS-Diagnose
```bash
dig A example.com                  # IPv4-Adresse
dig AAAA example.com               # IPv6-Adresse
dig MX example.com                 # Mail-Server
dig TXT example.com                # TXT-Einträge
dig SRV _matrix._tcp.example.com   # Matrix Federation
dig @8.8.8.8 example.com          # Bestimmten DNS-Server befragen
nslookup example.com               # Einfache DNS-Abfrage
host example.com                   # Alle Einträge
```

## 3. TLS/SSL

### 3.1 Zertifikate mit Let's Encrypt (certbot)
```bash
# Certbot installieren (für Nginx)
apt install -y certbot python3-certbot-nginx

# Zertifikat ausstellen
certbot --nginx -d example.com -d www.example.com \
  --email admin@example.com \
  --agree-tos --non-interactive

# Nur Zertifikat (ohne nginx-Konfiguration ändern)
certbot certonly --webroot -w /var/www/certbot \
  -d matrix.example.com \
  --email admin@example.com \
  --agree-tos

# Zertifikate anzeigen
certbot certificates

# Erneuerung testen
certbot renew --dry-run

# Automatische Erneuerung (via systemd-Timer, wird von certbot gesetzt)
systemctl status certbot.timer
```

### 3.2 TLS-Konfiguration prüfen
```bash
# SSL-Labs-Bewertung (online)
# https://www.ssllabs.com/ssltest/analyze.html?d=example.com

# Lokal testen
openssl s_client -connect example.com:443 -servername example.com

# Ablaufdatum prüfen
openssl s_client -connect example.com:443 -servername example.com 2>/dev/null \
  | openssl x509 -noout -dates

# Zertifikat-Details
openssl x509 -in /etc/letsencrypt/live/example.com/cert.pem -text -noout
```

### 3.3 Moderne TLS-Einstellungen (2024)
```nginx
# Nur TLS 1.2 und 1.3 (1.0 und 1.1 veraltet und unsicher)
ssl_protocols TLSv1.2 TLSv1.3;

# Moderne Ciphers (BSI-konform)
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
ssl_prefer_server_ciphers off;  # Client darf bevorzugte Cipher wählen

# HSTS (HTTP Strict Transport Security)
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

# OCSP Stapling (für schnellere TLS-Verbindungen)
ssl_stapling on;
ssl_stapling_verify on;
ssl_trusted_certificate /etc/letsencrypt/live/example.com/chain.pem;
```

## 4. HTTP/HTTPS Grundlagen

### 4.1 HTTP-Status-Codes (wichtigste)
```
200 OK                — Erfolg
301 Moved Permanently — Permanente Weiterleitung (SEO-freundlich)
302 Found             — Temporäre Weiterleitung
400 Bad Request       — Ungültige Anfrage
401 Unauthorized      — Authentifizierung erforderlich
403 Forbidden         — Zugriff verweigert (trotz Auth)
404 Not Found         — Ressource nicht gefunden
429 Too Many Requests — Rate-Limiting
500 Internal Server Error — Server-Fehler
502 Bad Gateway       — Upstream-Fehler (Reverse Proxy → Dienst down)
503 Service Unavailable — Dienst überlastet/nicht verfügbar
```

### 4.2 HTTP-Header (Sicherheit)
```nginx
# Security Headers (in Nginx)
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Content-Security-Policy "default-src 'self'" always;
```

## 5. Proxmox Netzwerk-Setup

### 5.1 Bridge-Konfiguration (/etc/network/interfaces)
```
# Physisches Interface
auto eno1
iface eno1 inet manual

# Bridge für VMs/LXC
auto vmbr0
iface vmbr0 inet static
    address 192.0.2.10/24
    gateway 192.0.2.1
    bridge-ports eno1
    bridge-stp off
    bridge-fd 0

# Optionale interne Bridge (ohne physisches Interface)
auto vmbr1
iface vmbr1 inet static
    address 10.10.10.1/24
    bridge-ports none
    bridge-stp off
    bridge-fd 0
```

### 5.2 VLAN in Proxmox
```
# Bridge mit VLAN-Support aktivieren (in Web-UI oder /etc/network/interfaces):
bridge-vlan-aware yes
bridge-vids 2-4094

# VM mit VLAN:
# In VM-Konfiguration: net0: virtio=XX:XX:XX:XX:XX:XX,bridge=vmbr0,tag=10
```

## 6. Hetzner-Spezifika

### 6.1 Hetzner Dedicated Server Netzwerk
```
# Hetzner stellt eine statische IPv4 pro Server
# Für VMs: Hetzner Robot → Failover-IPs bestellen
# Oder: NAT-Setup mit einer Server-IP für alle VMs

# Hetzner Firewall (Robot-Panel)
# Eingehend: Nur SSH, HTTP, HTTPS, Proxmox-API öffnen
# Alles andere blockieren

# IPv6: Hetzner gibt /64-Block pro Server
```

### 6.2 Reverse DNS (PTR-Record)
```
# In Hetzner Robot für Server-IP setzen
# Ermöglicht E-Mail-Versand ohne Spam-Probleme
```
