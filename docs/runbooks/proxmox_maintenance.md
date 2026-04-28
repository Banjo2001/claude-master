# Runbook: Proxmox Wartung

> Stand: 2026-04 | Proxmox VE 9.x

## 1. Status-Übersicht

```bash
# Vollständiger Status-Report via API
bash scripts/proxmox/pve_status_report.sh

# Proxmox Web-UI
# https://192.0.2.10:8006

# Node-Ressourcen (CPU, RAM, Disk) via CLI
pvesh get /nodes/pve/status
```

## 2. VM/LXC Verwaltung

```bash
# VMs auflisten
qm list

# LXC-Container auflisten
pct list

# VM starten/stoppen/neustarten
qm start 101
qm shutdown 101
qm reboot 101

# LXC starten/stoppen
pct start 101
pct shutdown 101

# In LXC einloggen
pct enter 101
```

## 3. Snapshot-Verwaltung

```bash
# Snapshot VOR jeder Änderung erstellen!
bash scripts/proxmox/pve_snapshot_create.sh 101 "vor-update-$(date +%Y%m%d)" "Beschreibung"

# Alle Snapshots anzeigen
qm listsnapshot 101   # für VMs
pct listsnapshot 101  # für LXC

# Rollback
bash scripts/proxmox/pve_snapshot_rollback.sh 101 "vor-update-20260428"

# Alten Snapshot löschen (nach erfolgreichem Update)
qm delsnapshot 101 vor-update-20260428
```

## 4. Proxmox Updates

```bash
# Auf Proxmox VE Host:
# Subscription-Status prüfen (No-Subscription Repo verwenden)
cat /etc/apt/sources.list.d/pve-enterprise.list
# Für Homelab: auf pve-no-subscription umstellen:
# deb http://download.proxmox.com/debian/pve trixie pve-no-subscription

# Updates installieren (VIA WEB-UI empfohlen!)
# Proxmox Web-UI → Node → Updates → Aktualisieren

# Oder CLI:
apt update && apt dist-upgrade

# WICHTIG: Nach Kernel-Update Reboot erforderlich!
# Vorher: Alle VMs auf anderen Node migrieren (bei Cluster)
# oder: Kurze Downtime ankündigen
```

## 5. Storage-Verwaltung

```bash
# Storage-Übersicht
pvesm status

# Freien Speicherplatz prüfen
df -h /var/lib/pve/local-btrfs  # oder /var/lib/vz

# Alte Backups löschen (über Web-UI!)
# Proxmox Web-UI → Storage → Backups → alte Einträge löschen

# LVM-Storage-Übersicht
lvs
vgs
```

## 6. Netzwerk-Konfiguration prüfen

```bash
# Netzwerk-Interfaces
ip addr show
ip route show

# Bridge-Status
brctl show

# Konfiguration
cat /etc/network/interfaces
```

## 7. Logs

```bash
# Systemlogs
journalctl -u pveproxy --since "1 hour ago"
journalctl -u pvedaemon --since "1 hour ago"

# Task-Logs
# Proxmox Web-UI → Node → Tasks

# Via API
bash -c 'source proxmox-api/lib/pve_api.sh && pve_task_list pve'
```

## 8. Häufige Probleme

| Problem | Ursache | Lösung |
|---------|---------|--------|
| Web-UI nicht erreichbar | pveproxy Fehler | `systemctl restart pveproxy` |
| VM startet nicht | Ressourcen fehlen | CPU/RAM auf Node prüfen |
| Storage voll | Alte Backups | Alte Backups/Snapshots löschen |
| Netzwerk nach Reboot weg | Konfigurationsfehler | `/etc/network/interfaces` prüfen |
| Backup schlägt fehl | PBS nicht erreichbar | PBS-Verbindung testen: `bash scripts/proxmox/pbs_verify_backups.sh` |
