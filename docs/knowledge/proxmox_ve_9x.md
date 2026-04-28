# Proxmox VE 9.x — Wissensdatenbank
# Stand: 2026-04 | Basis: Debian 13 "Trixie"

## 1. Überblick Proxmox VE 9.x

Proxmox Virtual Environment ist eine Open-Source-Virtualisierungsplattform.
Sie kombiniert KVM-Virtualisierung (für VMs) und LXC (für Container).

### Wichtige Ports
- 8006/TCP  — Proxmox Web-UI (HTTPS)
- 8007/TCP  — Proxmox Backup Server (falls PBS installiert)
- 3128/TCP  — SPICE Proxy (für VM-Konsolen)
- 22/TCP    — SSH (für direkte Verwaltung)
- 5404-5405/UDP — Corosync Cluster-Kommunikation
- 111/TCP+UDP    — RPCbind (für NFS-Storage)
- 2049/TCP+UDP   — NFS

### API-Zugriff
- REST API: https://<HOST>:8006/api2/json/
- Auth via API-Token (empfohlen) oder Session-Ticket
- API-Token Format: PVEAPIToken=<USER>@<REALM>!<TOKENID>=<UUID>
- Header: Authorization: PVEAPIToken=root@pam!mytoken=<UUID>

## 2. Wichtige Pfade in Proxmox

```
/etc/pve/               — Proxmox-Konfiguration (verteiltes Dateisystem)
/etc/pve/nodes/         — Pro-Node Konfigurationen
/etc/pve/qemu-server/   — VM-Konfigurationen (<VMID>.conf)
/etc/pve/lxc/           — LXC-Konfigurationen (<CTID>.conf)
/etc/pve/storage.cfg    — Storage-Konfiguration
/etc/pve/corosync.conf  — Cluster-Konfiguration
/var/log/pve/           — Proxmox-Logs
/var/lib/vz/            — Standard-Storage für Images/Templates
```

## 3. VM-Verwaltung (qm)

### 3.1 VM erstellen (Beispiel Debian 12)
```bash
# VM mit 2 Cores, 4GB RAM, 20GB Disk, UEFI, Virtio-Netz
qm create 100 \
  --name debian12-base \
  --ostype l26 \
  --memory 4096 \
  --cores 2 \
  --net0 virtio,bridge=vmbr0 \
  --scsi0 local-lvm:20 \
  --bootdisk scsi0 \
  --boot order=scsi0 \
  --ide2 local:iso/debian-12.iso,media=cdrom \
  --machine q35 \
  --bios ovmf \
  --efidisk0 local-lvm:1
```

### 3.2 VM-Snapshot-Workflow
```bash
# SICHERUNG: Snapshot erstellen VOR Änderungen
qm snapshot <VMID> "vor-update-$(date +%F)" --description "Vor apt full-upgrade"

# Snapshots auflisten
qm listsnapshot <VMID>

# Rollback zu Snapshot
# ⚠️  ACHTUNG — DESTRUKTIV: VM wird auf Stand des Snapshots zurückgesetzt
# Rollback: qm rollback <VMID> <vorheriger-snapshot>
qm rollback <VMID> "vor-update-2025-01-01"

# Snapshot löschen (nach erfolgreichem Update)
qm delsnapshot <VMID> "vor-update-2025-01-01"
```

### 3.3 VM klonen (für schnelle Bereitstellung)
```bash
# Full Clone (unabhängig vom Template)
qm clone <SOURCE_VMID> <NEW_VMID> --name <NAME> --full

# Linked Clone (schneller, abhängig vom Template — nur für Tests)
qm clone <SOURCE_VMID> <NEW_VMID> --name <NAME>
```

## 4. LXC Container-Verwaltung (pct)

### 4.1 Container erstellen (empfohlen für Dienste wie Claude Code)
```bash
# Debian 12 Container, unprivileged (sicherer als privileged)
pct create <CTID> local:vztmpl/debian-12-standard_20240203_amd64.tar.zst \
  --hostname <NAME> \
  --rootfs local-lvm:20 \
  --memory 2048 \
  --cores 2 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --unprivileged 1 \
  --features nesting=1  # Für Docker in LXC nötig
```

### 4.2 Container für Docker vorbereiten (LXC)
```
WICHTIG: Docker in LXC funktioniert, aber erfordert:
1. Unprivileged Container mit nesting=1
2. Oder: privileged Container (weniger sicher)

In /etc/pve/lxc/<CTID>.conf hinzufügen (für unprivileged + Docker):
lxc.apparmor.profile: unconfined
lxc.cgroup2.devices.allow: a
lxc.cap.drop:
```

### 4.3 LXC Snapshot-Workflow
```bash
# Snapshot erstellen
pct snapshot <CTID> "vor-aenderung-$(date +%F)"

# Snapshots anzeigen
pct listsnapshot <CTID>

# Rollback
# ⚠️  ACHTUNG — DESTRUKTIV
pct rollback <CTID> "vor-aenderung-2025-01-01"
```

## 5. Storage-Verwaltung

### 5.1 Storage-Typen in Proxmox
- `local`       — Lokales Verzeichnis (/var/lib/vz) — für ISOs, Templates
- `local-lvm`   — LVM-Thin — für VM-Disks und Container (empfohlen)
- `local-zfs`   — ZFS — für Snapshots und Replikation (wenn ZFS installiert)
- `nfs`         — NFS-Share — für Backup-Ziele oder gemeinsame Daten
- `ceph`        — Verteilter Storage (nur Cluster)
- `pbs`         — Proxmox Backup Server (für Backups)

### 5.2 Nützliche Storage-Befehle
```bash
pvesm status                  # Alle Storage anzeigen
pvesm list local              # Inhalte von "local" anzeigen
pvesm list local-lvm          # LVM-Volumes anzeigen
```

## 6. Proxmox API — Shell-Zugriff

### 6.1 API-Token erstellen (in Web-UI)
```
Web-UI → Rechenzentrum → API-Tokens → Hinzufügen
Benutzer: <USER>@pam
Token-ID: <TOKEN_NAME>
Berechtigung nicht übertragen: aktivieren (für eingeschränkte Rechte)
```

### 6.2 API-Token Berechtigungen setzen
```bash
# Minimal-Rechte für Monitoring (nur lesen)
pveum aclmod / -token <USER>@pam!<TOKEN_NAME> -role PVEAuditor

# Für Snapshot-Verwaltung zusätzlich:
pveum aclmod / -token <USER>@pam!<TOKEN_NAME> -role PVEVMAdmin
```

### 6.3 Einfacher API-Test mit curl
```bash
# GET: Node-Liste abrufen
curl -sk -H "Authorization: PVEAPIToken=<USER>@pam!<TOKEN>=<SECRET>" \
  https://192.0.2.10:8006/api2/json/nodes | python3 -m json.tool

# Eigene TLS-Zertifikate: -k entfernen und --cacert /pfad/zu/ca.pem nutzen
```

## 7. Backup-Strategie

### 7.1 Proxmox Backup Server (PBS) Integration
```bash
# PBS als Storage hinzufügen (in Web-UI oder):
pvesm add pbs pbs01 \
  --server 192.0.2.11 \
  --datastore <DATASTORE_NAME> \
  --username <USER>@pbs!<TOKEN_NAME> \
  --password <TOKEN_SECRET>
```

### 7.2 Automatische Backups einrichten (via Web-UI)
```
Rechenzentrum → Backup → Hinzufügen
Schedule: täglich 02:00 Uhr
Modus: Snapshot (kein Stopp, kein Suspend)
Aufbewahrung: 7 täglich, 4 wöchentlich, 2 monatlich
```

## 8. Sicherheit Proxmox

### 8.1 Zwei-Faktor-Authentifizierung (2FA)
```
Web-UI → Rechenzentrum → Permissions → Two Factor
TOTP aktivieren für alle Admin-Benutzer
```

### 8.2 Firewall
```bash
# Proxmox-eigene Firewall aktivieren
pve-firewall start
pve-firewall status

# Wichtig: Vor Aktivierung SSH (Port 22) sicherstellen!
# Datei: /etc/pve/firewall/cluster.fw
```

### 8.3 Fail2Ban für Proxmox Web-UI
```ini
# /etc/fail2ban/jail.local hinzufügen:
[proxmox]
enabled = true
port    = 8006
filter  = proxmox
logpath = /var/log/daemon.log
maxretry = 3
bantime = 3600
```

## 9. Netzwerk-Konfiguration

### 9.1 Bridges (vmbr)
```
vmbr0 — Standard-Bridge (verbunden mit physischem Interface)
vmbr1 — Optionale interne Bridge (für isolierte VMs/Container)
```

### 9.2 Netzwerk-Konfiguration (Debian-Basis)
```
/etc/network/interfaces — Netzwerk-Konfiguration
# Änderungen: ifreload -a oder Neustart
```

## 10. Wartung und Updates

### 10.1 Proxmox Updates einspielen
```bash
# SICHERUNG: Snapshot aller VMs vorher!

# Repositories prüfen
cat /etc/apt/sources.list.d/pve-enterprise.list
# Oder No-Subscription (ohne Support):
# deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription

# Update durchführen
apt update && apt full-upgrade -y

# WICHTIG: Nach Kernel-Update Neustart erforderlich
# ⚠️  ACHTUNG — DESTRUKTIV bei laufenden VMs
# Alle VMs vorher sauber herunterfahren oder migrieren
```
