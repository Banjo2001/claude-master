# Proxmox Backup Server (PBS) — Wissensdatenbank
# Stand: 2026-04 | PBS 4.x

## 1. Überblick

Proxmox Backup Server (PBS) ist eine dedizierte Backup-Lösung für Proxmox VE.
Er bietet deduplizierte, komprimierte und verschlüsselte Backups.

### Vorteile PBS gegenüber lokalem Backup:
- Deduplizierung: Spart bis zu 80% Speicherplatz
- Inkrementelle Backups: Nur Änderungen werden übertragen
- Verifikation: Backups werden regelmäßig auf Integrität geprüft
- Verschlüsselung: Client-seitig, PBS kennt die Daten nicht
- Retention-Policies: Automatische Bereinigung alter Backups

### Wichtige Ports
- 8007/TCP — PBS Web-UI (HTTPS)
- 8007/TCP — PBS API (HTTPS)

## 2. PBS API

### 2.1 API-Token erstellen
```
PBS Web-UI → Administration → API-Tokens → Hinzufügen
```

### 2.2 API-Endpunkte (Auswahl)
```
GET  /api2/json/nodes                    — Nodes auflisten
GET  /api2/json/admin/datastore          — Datastores auflisten
GET  /api2/json/admin/datastore/<DS>/snapshots  — Snapshots auflisten
POST /api2/json/admin/datastore/<DS>/gc  — Garbage Collection starten
GET  /api2/json/admin/traffic-control    — Traffic-Statistiken
```

### 2.3 Backup-Status prüfen (API)
```bash
curl -sk -H "Authorization: PBSAPIToken=<USER>@pbs!<TOKEN>=<SECRET>" \
  https://192.0.2.11:8007/api2/json/admin/datastore/<DATASTORE>/snapshots \
  | python3 -m json.tool
```

## 3. Backup-Strategien

### 3.1 3-2-1-Regel (Best Practice)
```
3 Kopien der Daten
2 verschiedene Medien/Technologien
1 Kopie extern/offsite
```

Umsetzung:
- Kopie 1: Live-System auf Proxmox VE
- Kopie 2: PBS auf anderem Host/anderer Festplatte
- Kopie 3: Externes Backup (Hetzner Storage Box, Backblaze B2, etc.)

### 3.2 Retention Policy (Aufbewahrung)
```
keep-last:    3   # Letzte 3 Backups immer behalten
keep-daily:   7   # Je 1 Backup pro Tag für 7 Tage
keep-weekly:  4   # Je 1 Backup pro Woche für 4 Wochen
keep-monthly: 3   # Je 1 Backup pro Monat für 3 Monate
```

## 4. Backup-Verifikation

### 4.1 Automatische Verifikation konfigurieren
```
PBS Web-UI → Datastore → Verify Jobs → Hinzufügen
Schedule: täglich 04:00 Uhr (nach dem Backup)
```

### 4.2 Manuelle Verifikation
```bash
# Letzten Snapshot verifizieren
proxmox-backup-client snapshot verify vm/100/2025-01-01T02:00:00Z \
  --repository 192.0.2.11:backup

# Alle Snapshots verifizieren (dauert lange!)
proxmox-backup-client snapshot verify --all \
  --repository 192.0.2.11:backup
```

## 5. Restore-Prozedur

### 5.1 VM aus PBS wiederherstellen
```bash
# In Proxmox VE Web-UI:
# Rechenzentrum → Backup → PBS-Storage wählen → Wiederherstellen

# Oder per CLI:
qmrestore pbs:<DATASTORE>:backup/vm/100/2025-01-01T02:00:00Z \
  <NEUE_VMID> --storage local-lvm
```

### 5.2 Einzelne Dateien aus Backup extrahieren (PBS-Mount)
```bash
# Backup als FUSE-Mount einbinden
proxmox-backup-client mount vm/100/2025-01-01T02:00:00Z /mnt/restore \
  --repository 192.0.2.11:backup

# Dateien kopieren
cp /mnt/restore/etc/nginx/nginx.conf /tmp/nginx.conf.restore

# Unmount
fusermount -u /mnt/restore
```

## 6. Monitoring und Alerts

### 6.1 PBS Backup-Status überwachen
```bash
# Letzten Backup-Zeitpunkt prüfen
proxmox-backup-client snapshot list --repository 192.0.2.11:backup \
  | grep "vm/100" | tail -5

# Prüfen ob Backup jünger als 24h ist (für Monitoring-Skript)
LAST_BACKUP=$(proxmox-backup-client snapshot list --repository 192.0.2.11:backup \
  --output-format json | python3 -c "
import json, sys
data = json.load(sys.stdin)
# Neuesten Timestamp ausgeben
timestamps = [s['backup-time'] for s in data]
print(max(timestamps) if timestamps else 0)
")
```

### 6.2 PBS Notification konfigurieren
```
PBS Web-UI → Administration → Notifications
SMTP konfigurieren für Backup-Fehler-Alerts
```

## 7. Verschlüsselung

### 7.1 Verschlüsselungsschlüssel erstellen
```bash
# Schlüssel erstellen (SICHER AUFBEWAHREN — ohne ihn kein Restore!)
proxmox-backup-client key create /root/backup-encryption.key

# Schlüssel sichern (z.B. auf USB-Stick und Passwort-Manager)
# NIEMALS den Schlüssel im gleichen Backup speichern!

# Backup mit Verschlüsselung
proxmox-backup-client backup root.pxar:/ \
  --repository 192.0.2.11:backup \
  --keyfile /root/backup-encryption.key
```

## 8. PBS Wartung

### 8.1 Garbage Collection (GC)
```bash
# Nicht referenzierte Daten bereinigen (läuft automatisch, aber manuell möglich)
# PBS Web-UI → Datastore → GC starten
# Oder per API:
curl -sk -X POST \
  -H "Authorization: PBSAPIToken=<USER>@pbs!<TOKEN>=<SECRET>" \
  https://192.0.2.11:8007/api2/json/admin/datastore/<DATASTORE>/gc
```

### 8.2 Datastore-Status prüfen
```bash
# Über API
curl -sk \
  -H "Authorization: PBSAPIToken=<USER>@pbs!<TOKEN>=<SECRET>" \
  https://192.0.2.11:8007/api2/json/admin/datastore/<DATASTORE>/status \
  | python3 -m json.tool
```
