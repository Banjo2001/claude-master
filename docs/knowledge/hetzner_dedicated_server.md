# Hetzner Dedicated Server — Wissensdatenbank
# Stand: 2026-04

## 1. Überblick Hetzner Dedicated

Hetzner bietet dedizierte Server über das Robot-Panel an.
Im Gegensatz zu Cloud-VMs hat man vollen Zugriff auf die Hardware.

### Unterschied Robot vs. Cloud Console:
- Robot: Physische Server, eigene Hardware, mehr Kontrolle
- Cloud: VMs (hcloud), einfacher zu verwalten, teurer pro Ressource

## 2. Server-Setup nach Kauf

### 2.1 Initialer Zugriff (Rescue-System)
```bash
# 1. Im Robot-Panel: Server → Rescue → Linux aktivieren
# 2. Root-Passwort notieren
# 3. Server neu starten (im Robot-Panel)
# 4. Per SSH verbinden:
ssh root@<SERVER_IP>
# Passwort = das aus dem Rescue-System

# Im Rescue-System: Proxmox installieren
```

### 2.2 Proxmox auf Hetzner installieren
```bash
# Hetzner installimage nutzen (im Rescue-System)
installimage -a -r yes -t yes -n proxmox-pve \
  -p / ,btrfs,128G \
  -p none,swap,8G

# Oder manuell über Debian + Proxmox-Repository
# Empfehlung: Hetzner installimage verwenden
```

## 3. Hetzner Netzwerk

### 3.1 IP-Konfiguration
```
# Jeder Server bekommt:
# - 1 IPv4 (statisch, kann nicht geändert werden)
# - 1 /64 IPv6-Block

# Failover-IPs:
# - Zusätzliche IPs für VMs
# - Können zwischen Servern umgezogen werden
# - Im Robot-Panel bestellbar und konfigurierbar
```

### 3.2 Subnet für VMs (stateless)
```bash
# Hetzner ermöglicht ein /29 subnet zu einer Server-IP zu routen
# Dies gibt 6 verwendbare IPs für VMs

# Beispiel Konfiguration für Proxmox (vmbr0):
# In /etc/network/interfaces:
# VMs erhalten IPs aus dem gerouteten Subnet
# Gateway = Server-IP
```

### 3.3 IPv6-Konfiguration
```bash
# Hetzner gibt /64 Block
# Beispiel: 2a01:4f8:XXX:YYY::/64
# Jede VM kann eigene IPv6 aus dem Block nutzen

# In Proxmox VM:
# ip addr add 2a01:4f8:XXX:YYY::2/64 dev eth0
# ip route add default via fe80::1 dev eth0
```

## 4. Hetzner Firewall (Robot)

### 4.1 Firewall-Regeln im Robot-Panel
```
# Hetzner Firewall ist STATELESS (keine Connection-Tracking)
# D.h. INCOMING und OUTGOING müssen separat erlaubt werden
# (anders als UFW/iptables die stateful sind)

# Empfohlene eingehende Regeln:
# TCP Port 22    — SSH (nur von bestimmten IPs wenn möglich)
# TCP Port 80    — HTTP
# TCP Port 443   — HTTPS
# TCP Port 8006  — Proxmox Web-UI (nur von Admin-IP!)

# Ausgehende Regeln (Hetzner-Firewall) — normalerweise alles erlaubt
```

### 4.2 Wichtiger Hinweis zur Stateless-Firewall
```
# Problem: TCP-Antworten brauchen eigene Regel!
# Lösung: Hetzner erlaubt "established,related" Traffic per Standard

# Bei Hetzner-Firewall IMMER:
# Eingehend: TCP Port 22 ACCEPT (für SSH)
# Eingehend: TCP established,related ACCEPT (für Antworten auf ausgehende Verbindungen)
```

## 5. Hetzner Storage Box (als Backup-Ziel)

### 5.1 Storage Box einrichten
```bash
# Storage Box wird über SFTP, Samba oder Restic angebunden
# Für PBS-Backups: SFTP-Methode empfohlen

# SSH-Schlüssel für Storage Box hinterlegen
ssh-keygen -t ed25519 -C "proxmox-backup" -f ~/.ssh/id_ed25519_storagebox
# Public Key in Robot-Panel unter Storage Box → SSH Keys hinterlegen

# Verbindungstest
sftp <USERNAME>@<STORAGEBOX_HOST>
```

### 5.2 Restic mit Hetzner Storage Box
```bash
# Restic installieren
apt install -y restic

# Repository initialisieren (SFTP)
restic -r sftp:<USERNAME>@<HOST>:/restic init

# Backup erstellen
restic -r sftp:<USERNAME>@<HOST>:/restic backup /etc /home

# Snapshots anzeigen
restic -r sftp:<USERNAME>@<HOST>:/restic snapshots

# Retention (alte Backups löschen)
restic -r sftp:<USERNAME>@<HOST>:/restic forget \
  --keep-daily 7 --keep-weekly 4 --keep-monthly 3
```

## 6. Hetzner Robot API

```bash
# API-Dokumentation: https://robot.hetzner.com/doc/webservice/en.html

# Beispiel: Server-Liste abrufen
curl -u "<USER>:<PASSWORT>" \
  https://robot-ws.your-server.de/server

# Failover-IP verschieben
curl -u "<USER>:<PASSWORT>" \
  -d "active_server_ip=<NEUE_SERVER_IP>" \
  https://robot-ws.your-server.de/failover/<FAILOVER_IP>
```

## 7. Wichtige Hetzner-Spezifika für Proxmox

### 7.1 MAC-Adresse für VMs
```
# Hetzner verlangt registrierte MAC-Adressen für VMs im Netz
# Failover-IPs brauchen eigene MAC (im Robot-Panel bestellbar)
# Oder: NAT auf Server-IP (einfacher, aber alle VMs teilen eine externe IP)
```

### 7.2 Proxmox-Node nicht direkt aus dem Internet erreichbar
```
# Hetzner Firewall schützt, aber zusätzlich:
# - Proxmox Web-UI nur via SSH-Tunnel oder VPN zugänglich machen
# - SSH-Tunnel Beispiel:
ssh -L 8006:localhost:8006 root@<SERVER_IP>
# Dann: https://localhost:8006 im Browser öffnen
```

### 7.3 DDoS-Schutz
```
# Hetzner hat DDoS-Schutz automatisch aktiviert
# Bei intensivem Angriff: Automatisches Null-Routing der IP für 1h
# Benachrichtigung via E-Mail
```

## 8. Monitoring bei Hetzner

```bash
# Hetzner Robot bietet kein eingebautes Monitoring
# Externe Lösung nötig:

# Option 1: Uptime Kuma (selbstgehostet)
docker run -d --name uptime-kuma \
  -v uptime-kuma:/app/data \
  -p 3001:3001 \
  louislam/uptime-kuma:1.23.13

# Option 2: Prometheus + Grafana (im Ansible-Stack enthalten)

# Option 3: Hetzner hat kostenpflichtiges Cloud-Monitoring (für Cloud-VMs)
```
