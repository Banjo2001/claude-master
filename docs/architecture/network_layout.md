# Netzwerk-Layout

> Stand: 2026-04 | Alle IPs sind RFC 5737 TEST-NET Platzhalter

## 1. IP-Adressen (Platzhalter)

| Host | Platzhalter-IP | Funktion |
|------|----------------|----------|
| Proxmox VE Host | 192.0.2.10 | Hypervisor, SSH, Proxmox Web-UI |
| Proxmox Backup Server | 192.0.2.11 | PBS, Backup-Storage |
| Matrix VM/LXC | 192.0.2.20 | Matrix Synapse Stack |
| Nextcloud VM/LXC | 192.0.2.21 | Nextcloud AIO |
| Management-Workstation | 192.0.2.1 | Admin-PC (SSH-Zugang) |

> **ANPASSEN:** Echte IPs in `ansible/inventories/prod/hosts.yml` eintragen.

## 2. Ports und Dienste

### Öffentlich erreichbar (Internet)

| Port | Protokoll | Dienst | Host |
|------|-----------|--------|------|
| 80 | TCP | HTTP → HTTPS Redirect | Matrix VM |
| 443 | TCP | Matrix HTTPS (Nginx) | Matrix VM |
| 3478 | TCP+UDP | Coturn TURN | Matrix VM |
| 5349 | TCP+UDP | Coturn TURNS (TLS) | Matrix VM |
| 49152–65535 | UDP | Coturn Media-Ports | Matrix VM |
| 8443 | TCP | Nextcloud AIO HTTPS | Nextcloud VM |

### Nur Management-IP (192.0.2.1)

| Port | Protokoll | Dienst | Host |
|------|-----------|--------|------|
| 22 | TCP | SSH | alle Server |
| 8006 | TCP | Proxmox VE Web-UI | PVE Host |
| 8007 | TCP | Proxmox Backup Server Web-UI | PBS Host |
| 8080 | TCP | Nextcloud Admin-Interface | Nextcloud VM |

### Intern (Docker-Netzwerk)

| Port | Protokoll | Dienst | Netzwerk |
|------|-----------|--------|----------|
| 8008 | TCP | Matrix Synapse | matrix_internal |
| 5432 | TCP | PostgreSQL | matrix_internal |
| 6379 | TCP | Redis | matrix_internal |

## 3. DNS-Einträge

```dns
; Matrix
matrix.example.com.    IN A     <MATRIX-VM-IP>
matrix.example.com.    IN AAAA  <MATRIX-VM-IPv6>  ; optional

; Nextcloud
cloud.example.com.     IN A     <NEXTCLOUD-VM-IP>

; Matrix Federation (SRV Record — optional, wenn Port 443 genutzt)
_matrix._tcp.example.com. IN SRV 10 5 443 matrix.example.com.
```

> **WICHTIG:** DNS-Einträge müssen gesetzt sein, BEVOR Let's Encrypt Zertifikate ausgestellt werden können.

## 4. Docker-Netzwerke

### Matrix Synapse Stack

```
matrix_external (bridge)
  ├── nginx          → Internet-seitig
  └── synapse        → Internet-seitig

matrix_internal (bridge, internal: true)
  ├── synapse        → Datenbankzugriff
  ├── postgres       → nur intern
  └── redis          → nur intern
```

### Nextcloud AIO

```
nextcloud-aio (bridge, external: true)
  └── nextcloud-aio-mastercontainer
      ↳ spawnt alle Sub-Container in dieses Netzwerk
```

> Das Netzwerk `nextcloud-aio` muss **vor** dem Container existieren:
> `docker network create nextcloud-aio`
> (Wird durch Ansible automatisch erledigt.)

## 5. TLS-Zertifikate

| Dienst | Zertifikat | Speicherort |
|--------|-----------|-------------|
| Matrix Nginx | Let's Encrypt (certbot) | `/opt/matrix/certs/live/matrix.example.com/` |
| Coturn | Gleiche Certs wie Nginx | `/opt/matrix/certs/live/matrix.example.com/` |
| Nextcloud AIO | Let's Encrypt (intern vom AIO) | vom AIO-Mastercontainer verwaltet |

> Nextcloud AIO verwaltet seine Zertifikate vollständig selbst — kein manueller certbot nötig.

## 6. Firewall-Übersicht (UFW)

```bash
# Status nach setup_ufw.sh:
ufw status verbose

To                         Action    From
──────────────────────────────────────────────────────
22/tcp                     ALLOW     192.0.2.1       # SSH Management
80/tcp                     ALLOW     Anywhere        # HTTP Redirect
443/tcp                    ALLOW     Anywhere        # HTTPS
3478/tcp                   ALLOW     Anywhere        # Coturn TURN
3478/udp                   ALLOW     Anywhere        # Coturn TURN
5349/tcp                   ALLOW     Anywhere        # Coturn TURNS
5349/udp                   ALLOW     Anywhere        # Coturn TURNS
49152:65535/udp            ALLOW     Anywhere        # Coturn Media
8443/tcp                   ALLOW     Anywhere        # Nextcloud HTTPS
8080/tcp                   ALLOW     192.0.2.1       # Nextcloud Admin
8006/tcp                   ALLOW     192.0.2.1       # Proxmox Web-UI
```
