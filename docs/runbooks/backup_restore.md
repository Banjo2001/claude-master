# Runbook: Backup und Restore

> Stand: 2026-04 | Proxmox Backup Server 4.x

## 1. Backup-Strategie Übersicht

```
Ebene 1: PBS — VM/LXC Snapshots (täglich, inkrementell)
Ebene 2: Lokale Konfig-Backups (tar.gz, täglich)
Ebene 3: Nextcloud AIO Backup (integriert, täglich)
```

## 2. PBS Backup

### Backup-Job einrichten (Proxmox Web-UI)

```
1. Proxmox Web-UI → Rechenzentrum → Backup
2. "Hinzufügen" klicken
3. Einstellungen:
   - Storage: PBS Datastore
   - Plan: täglich 03:00 Uhr
   - Auswahl: alle VMs und Container
   - Modus: Snapshot (kein RAM, kein Stromausfall-Risiko)
   - Aufbewahrung:
     - täglich: 7
     - wöchentlich: 4
     - monatlich: 3
4. Speichern
```

### Manuelles Backup

```bash
# Via Proxmox Web-UI: Container → Backup → Jetzt sichern

# Via API (pve_api.sh)
source proxmox-api/lib/pve_api.sh
# Backup-Task starten (VMID 101 = Matrix)
curl -X POST "https://${PVE_HOST}:${PVE_PORT}/api2/json/nodes/${PVE_NODE}/vzdump" \
  -H "Authorization: PVEAPIToken=${PVE_TOKEN_ID}=${PVE_TOKEN_SECRET}" \
  -d "vmid=101&storage=pbs-store&mode=snapshot"
```

### Backup-Verifikation

```bash
# Alle Backups verifizieren
bash scripts/proxmox/pbs_verify_backups.sh

# Oder direkt via PBS Web-UI:
# https://192.0.2.11:8007 → Datastore → Verify All
```

## 3. PBS Restore

### VM/LXC aus PBS wiederherstellen

```bash
# ⚠️  ACHTUNG — DESTRUKTIV: Bestehende VM wird überschrieben!
# Rollback: erneut aus PBS wiederherstellen

# Via Proxmox Web-UI (empfohlen):
# PBS → Datastore → Backup-Eintrag → Restore
# Ziel-VMID wählen (kann neue VMID sein!)
# Überprüfen: Restore-Ziel ist korrekt
# "Restore" klicken

# Via CLI (auf Proxmox VE Host):
# ⚠️  ACHTUNG — DESTRUKTIV:
qmrestore /var/lib/vz/dump/vzdump-qemu-101-... 101 --force
# oder für LXC:
pct restore 101 /var/lib/vz/dump/vzdump-lxc-101-... --force
```

## 4. Snapshot Restore (VM-Ebene)

```bash
# Bestehende Snapshots anzeigen
bash scripts/proxmox/pve_snapshot_create.sh 101

# Snapshot erstellen (VOR jeder größeren Änderung!)
bash scripts/proxmox/pve_snapshot_create.sh 101 "vor-update-$(date +%Y%m%d)" "vor nginx Update"

# ⚠️  ACHTUNG — DESTRUKTIV: Rollback zu Snapshot
# Änderungen nach dem Snapshot gehen verloren!
bash scripts/proxmox/pve_snapshot_rollback.sh 101 "vor-update-20260428"
```

## 5. Konfigurations-Backup + Restore

```bash
# Backup erstellen
bash scripts/backup/backup_configs.sh

# Liste der Backups
ls -lh /opt/backups/configs/

# Restore (einzelne Datei)
tar -tzf /opt/backups/configs/config-backup-<TIMESTAMP>.tar.gz  # Inhalt anzeigen
tar -xzf /opt/backups/configs/config-backup-<TIMESTAMP>.tar.gz \
  -C / etc/ssh/sshd_config  # Einzelne Datei wiederherstellen

# Restore (alles)
# ⚠️  ACHTUNG — DESTRUKTIV: Überschreibt alle Konfigurationsdateien!
tar -xzf /opt/backups/configs/config-backup-<TIMESTAMP>.tar.gz -C /
systemctl restart sshd fail2ban
```

## 6. Nextcloud Restore

```bash
# Methode 1: Via AIO Admin-Interface (empfohlen)
# https://<IP>:8080 → Backup-Tab → Restore
# Backup-Pfad auswählen → Restore starten

# Methode 2: Manuell aus tar.gz
docker compose -f /opt/nextcloud-aio/compose.yml stop
# ⚠️  ACHTUNG — DESTRUKTIV:
rm -rf /opt/nextcloud-aio/data
tar -xzf /opt/backups/nextcloud-<DATUM>.tar.gz -C /
docker compose -f /opt/nextcloud-aio/compose.yml start
```

## 7. Disaster Recovery

### Szenario: Kompletter Serververlust

```
1. Neuen Hetzner Server bestellen
2. Proxmox VE 9.x installieren
3. PBS als Backup-Storage hinzufügen:
   Proxmox Web-UI → Rechenzentrum → Storage → PBS hinzufügen
4. VMs/LXC aus PBS wiederherstellen:
   PBS → Datastore → Backup auswählen → Restore
5. DNS auf neue IP umstellen
6. SSL-Zertifikate erneuern (Let's Encrypt)
7. Funktionstest: Matrix Federation, Nextcloud Zugang
```

### Szenario: Datenbankkorruption (Matrix)

```bash
# 1. Matrix-Stack stoppen
docker compose -f /opt/matrix/compose.yml stop

# 2. PostgreSQL-Daten aus PBS-Snapshot wiederherstellen
#    (über Proxmox VM/LXC Snapshot Restore)

# 3. Alternativ: Nur PostgreSQL-Daten aus Backup
#    ⚠️  ACHTUNG — DESTRUKTIV:
rm -rf /opt/matrix/data/postgres
tar -xzf /opt/backups/... -C /opt/matrix/data/

# 4. Stack neu starten
docker compose -f /opt/matrix/compose.yml up -d
```

## 8. Backup-Test (Regelmäßig durchführen!)

```bash
# Simuliert Restore-Test ohne echten Eingriff
bash scripts/backup/backup_test_restore.sh

# Empfehlung: Monatlich einen echten Restore auf Test-VM durchführen
# → Beweist dass Backups wirklich funktionieren
```
