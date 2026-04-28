# Architektur-Übersicht — Proxmox Infrastruktur

> Stand: 2026-04 | Proxmox VE 9.x | Debian 13 "Trixie"

## 1. Gesamtübersicht

```
┌─────────────────────────────────────────────────────────────────┐
│  INTERNET                                                        │
│    │ HTTPS/443  │ HTTPS/8443  │ TURN/3478+5349                  │
└────┼────────────┼─────────────┼────────────────────────────────-┘
     │            │             │
┌────▼────────────▼─────────────▼─────────────────────────────────┐
│  Hetzner Dedicated Server (Proxmox VE 9.x Host)                  │
│                                                                   │
│  ┌─────────────────────────┐  ┌──────────────────────────────┐  │
│  │  VM / LXC: Matrix       │  │  VM / LXC: Nextcloud AIO     │  │
│  │                         │  │                              │  │
│  │  ┌──────────────────┐   │  │  ┌──────────────────────┐   │  │
│  │  │ Nginx (443)      │   │  │  │ AIO Mastercontainer   │   │  │
│  │  │ Synapse (8008)   │   │  │  │   :latest             │   │  │
│  │  │ PostgreSQL 16.4  │   │  │  │ ↳ Nextcloud           │   │  │
│  │  │ Redis 7.2        │   │  │  │ ↳ PostgreSQL          │   │  │
│  │  │ Coturn (3478)    │   │  │  │ ↳ Redis               │   │  │
│  │  └──────────────────┘   │  │  │ ↳ Collabora           │   │  │
│  └─────────────────────────┘  │  │ ↳ Talk (TURN)         │   │  │
│                                │  └──────────────────────────┘   │  │
│  ┌─────────────────────────┐  └──────────────────────────────┘  │
│  │  LXC: Claude Code       │                                     │
│  │  (Control Node)         │  ┌──────────────────────────────┐  │
│  │  - Ansible              │  │  Proxmox Backup Server (PBS) │  │
│  │  - Git                  │  │  (separater Host)            │  │
│  │  - gitleaks             │  │  Backups: VM/LXC Snapshots   │  │
│  └─────────────────────────┘  └──────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────-┘
```

## 2. Komponenten-Übersicht

| Komponente | Technologie | Version | Zweck |
|------------|-------------|---------|-------|
| Hypervisor | Proxmox VE | 9.x | VM/LXC Verwaltung |
| Backup | Proxmox Backup Server | 4.x | Versionierte Backups |
| Gast-OS | Debian | 13 "Trixie" | Basis für VMs/LXC |
| Container | Docker CE + Compose v2 | aktuell | Service-Ausführung |
| Chat | Matrix Synapse | v1.123.0 | Selbstgehosteter Matrix-Server |
| Chat-DB | PostgreSQL | 16.4 | Matrix-Datenbank |
| Chat-Cache | Redis | 7.2-alpine | Synapse Worker-Koordination |
| Chat-Proxy | Nginx | 1.27-alpine | TLS-Termination, Reverse Proxy |
| Chat-TURN | Coturn | 4.6 | Voice/Video (WebRTC) |
| Cloud | Nextcloud AIO | latest¹ | Nextcloud All-in-One |
| Automation | Ansible | 2.17+ | Deployment-Automatisierung |
| Secrets | Ansible Vault | AES-256 | Passwort-Verschlüsselung |
| SSH | OpenSSH | - | Nur ed25519-Keys |
| Firewall | UFW | - | Default-deny, Whitelist |
| Schutz | Fail2Ban | - | Brute-Force-Schutz |

> ¹ Nextcloud AIO Mastercontainer verwendet `:latest` — er ist selbst der Updatemanager und lädt versionierte Sub-Images.

## 3. Netzwerkzonen

```
Zone          Zugänglich von        Ports
─────────────────────────────────────────────────────────────────
PUBLIC        Internet              443 (HTTPS), 8443 (NC HTTPS)
                                    3478/5349 UDP+TCP (TURN)
                                    80 (HTTP → Redirect)

MANAGEMENT    Management-IP only    22 (SSH), 8006 (Proxmox UI)
              (192.0.2.10)          8080 (Nextcloud Admin)

INTERN        Docker-intern         8008 (Synapse), 5432 (PG)
              (bridge network)      6379 (Redis)
```

## 4. Sicherheitskonzept

- **SSH:** Nur ed25519 Public-Key, kein Passwort, BSI TR-02102-4
- **Firewall:** UFW default-deny, explizite Whitelist
- **Fail2Ban:** SSH/Nginx/Matrix/Nextcloud/Proxmox Jails
- **Docker:** `no-new-privileges:true`, `cap_drop: ALL`, kein Root
- **Secrets:** Ansible Vault (AES-256), Vault-Passwort außerhalb Repo
- **Scans:** gitleaks pre-commit Hook + CI, audit_secrets.sh
- **Kernel:** CIS Benchmark sysctl (ASLR, SYN-Cookies, ICMP-Schutz)
- **Images:** Pinned Versionen (außer AIO Mastercontainer)

## 5. Backup-Strategie

```
Ebene 1: Proxmox Backup Server (PBS)
  → Tägliche VM/LXC Snapshots (inkrementell, dedupliziert)
  → Aufbewahrung: 7 täglich, 4 wöchentlich, 3 monatlich
  → Verifikation: scripts/proxmox/pbs_verify_backups.sh

Ebene 2: Lokale Konfigurations-Backups
  → scripts/backup/backup_configs.sh (täglich via Cron)
  → Aufbewahrung: 30 Archive
  → Test: scripts/backup/backup_test_restore.sh

Ebene 3: Nextcloud AIO integriertes Backup
  → Nextcloud Admin-Interface → Backup-Tab
  → Speicherort: Hetzner Storage Box (optional)
```

## 6. Monitoring

| Skript | Zweck | Empfohlenes Intervall |
|--------|-------|----------------------|
| `check_services.sh` | Dienste + HTTP-Endpunkte | alle 5 min |
| `check_disk_usage.sh` | Festplatten-Auslastung | stündlich |
| `check_ssl_certs.sh` | Zertifikat-Ablauf | täglich |
| `system_audit.sh` | Sicherheits-Überblick | wöchentlich |
