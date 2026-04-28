# Automatisierung — Wissensdatenbank
# Stand: 2026-04

## 1. Automatisierungsstrategie

### 1.1 Automatisierungs-Pyramide
```
Level 3 (Höchste Automation): Ansible Playbooks deployen gesamten Stack
Level 2 (Mittlere Automation): Skripte für wiederkehrende Aufgaben
Level 1 (Niedrigste Automation): Manuelle Skripte mit Dry-Run
Level 0: Manuelle Verwaltung (nur für einmalige Aktionen)
```

### 1.2 Was sollte automatisiert werden?
```
✓ Regelmäßige Backups (Cron + Ansible)
✓ Sicherheitsupdates (unattended-upgrades)
✓ Zertifikats-Erneuerung (certbot --renew via systemd-Timer)
✓ Monitoring-Checks (Prometheus Scraping)
✓ Log-Rotation (logrotate)
✓ Backup-Verifikation (regelmäßiger Restore-Test)

✗ NICHT automatisieren ohne menschliche Überprüfung:
✗ Major-Updates von Diensten (Matrix, Nextcloud)
✗ Firewall-Regeln ändern
✗ Secrets rotieren
✗ Infrastruktur-Änderungen
```

## 2. Cron-Jobs und Systemd-Timer

### 2.1 Cron-Syntax
```
# FORMAT: Minute Stunde Tag Monat Wochentag Befehl
# Felder: 0-59  0-23  1-31 1-12  0-7 (0=7=So)

# Beispiele:
0 3 * * *   # täglich 03:00 Uhr
0 2 * * 0   # Sonntags 02:00 Uhr
*/15 * * * * # alle 15 Minuten
0 0 1 * *   # 1. jeden Monats um Mitternacht
0 */6 * * * # alle 6 Stunden

# Spezielle Strings:
@reboot     # beim Systemstart
@daily      # täglich (= 0 0 * * *)
@weekly     # wöchentlich (= 0 0 * * 0)
@monthly    # monatlich (= 0 0 1 * *)
```

### 2.2 Systemd-Timer (modernere Alternative)
```ini
# /etc/systemd/system/backup-matrix.timer
[Unit]
Description=Matrix PostgreSQL Backup Timer
Requires=backup-matrix.service

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true     # Verpasste Ausführungen nachholen
RandomizedDelaySec=300  # Zufällige Verzögerung (Lastspitzen vermeiden)

[Install]
WantedBy=timers.target

# Dazugehörige Service-Datei:
# /etc/systemd/system/backup-matrix.service
[Unit]
Description=Matrix PostgreSQL Backup

[Service]
Type=oneshot
ExecStart=/usr/local/bin/backup-matrix.sh
User=root
StandardOutput=journal
StandardError=journal

# Timer aktivieren:
# systemctl enable --now backup-matrix.timer
# systemctl list-timers | grep backup
```

## 3. Shell-Skripting Best Practices

### 3.1 Pflicht-Header für alle Skripte
```bash
#!/usr/bin/env bash
# =============================================================================
# DATEI:        skript.sh
# ZWECK:        Ein Satz Beschreibung
# AUFRUFEN:     ./skript.sh [PARAMETER]
# VORAUSSETZUNGEN:
#   - Liste der Abhängigkeiten
# SICHERHEIT:
#   - Backup-Verhalten
#   - Destruktiv: ja/nein
# =============================================================================
set -euo pipefail
# set -e  : Abbruch bei Fehler (kein stilles Weiterlaufen)
# set -u  : Fehler bei undefinierten Variablen
# set -o pipefail : Fehler in Pipes wird erkannt

IFS=$'\n\t'  # Sichere Feldtrennung
```

### 3.2 Idempotente Skripte
```bash
# FALSCH — nicht idempotent:
echo "text" >> /etc/datei  # Hängt bei jedem Aufruf erneut an

# RICHTIG — idempotent:
grep -qxF "text" /etc/datei || echo "text" >> /etc/datei

# Noch besser — mit Ansible:
# ansible.builtin.lineinfile für idempotente Datei-Manipulation
```

### 3.3 Fehlerbehandlung
```bash
# Fehler-Handler
cleanup() {
    local exit_code=$?
    # Aufräum-Aktionen (immer ausführen, auch bei Fehler)
    echo "Skript beendet mit Code: $exit_code"
}
trap cleanup EXIT

# Auf Fehler reagieren
if ! command -v docker &>/dev/null; then
    echo "FEHLER: Docker ist nicht installiert!" >&2
    exit 1
fi

# Befehl mit Fehlerprüfung
if ! systemctl is-active --quiet nginx; then
    echo "WARNUNG: Nginx läuft nicht, starte..."
    systemctl start nginx
fi
```

### 3.4 Logging in Skripten
```bash
# Logging-Funktion
log() {
    echo "[$(date +%F\ %T)] $*" | tee -a /var/log/mein-skript.log
}

log "INFO: Backup beginnt..."
log "FEHLER: Backup fehlgeschlagen!"
```

## 4. Monitoring-Automatisierung

### 4.1 Prometheus Alerting Rules
```yaml
# /etc/prometheus/alert_rules.yml
groups:
  - name: system
    rules:
      # Alert wenn Dienst down
      - alert: ServiceDown
        expr: up == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Dienst {{ $labels.job }} ist nicht erreichbar"

      # Alert bei hoher CPU-Auslastung
      - alert: HighCPU
        expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 90
        for: 10m
        labels:
          severity: warning

      # Alert bei vollem Disk
      - alert: DiskAlmostFull
        expr: (node_filesystem_free_bytes / node_filesystem_size_bytes) * 100 < 10
        for: 5m
        labels:
          severity: critical
```

### 4.2 Healthcheck in Docker Compose
```yaml
services:
  postgres:
    image: postgres:16.4
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U synapse_user -d synapse"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s  # Startzeit bevor Healthcheck beginnt
    
  synapse:
    image: matrixdotorg/synapse:v1.123.0
    depends_on:
      postgres:
        condition: service_healthy  # Warte bis postgres healthy ist
```

## 5. Automatische Backup-Validierung

```bash
#!/usr/bin/env bash
# Täglicher Backup-Validierungs-Job
# Prüft: Existiert Backup? Ist es jünger als 24h? Ist es nicht korrupt?

set -euo pipefail

BACKUP_DIR="/backup/matrix"
MAX_AGE_HOURS=25  # Etwas Puffer über 24h

# Letztes Backup finden
LATEST_BACKUP=$(find "$BACKUP_DIR" -name "synapse_*.dump" -type f \
  -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)

if [ -z "$LATEST_BACKUP" ]; then
    echo "KRITISCH: Kein Backup gefunden in $BACKUP_DIR" >&2
    exit 1
fi

# Alter prüfen
BACKUP_AGE_HOURS=$(( ($(date +%s) - $(stat -c %Y "$LATEST_BACKUP")) / 3600 ))
if [ "$BACKUP_AGE_HOURS" -gt "$MAX_AGE_HOURS" ]; then
    echo "WARNUNG: Backup ist $BACKUP_AGE_HOURS Stunden alt (Limit: $MAX_AGE_HOURS h)" >&2
    exit 1
fi

# Integrität prüfen
if ! pg_restore --list "$LATEST_BACKUP" > /dev/null 2>&1; then
    echo "KRITISCH: Backup ist korrupt: $LATEST_BACKUP" >&2
    exit 1
fi

echo "OK: Backup ist gültig, Alter: $BACKUP_AGE_HOURS Stunden"
```

## 6. CI/CD mit GitHub Actions

```yaml
# .github/workflows/deploy.yml (Beispiel — wird NICHT automatisch deployed!)
name: Ansible Lint und Secret Scan

on:
  push:
    branches: [main, develop]
  pull_request:

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: ansible-lint
        uses: ansible/ansible-lint@v24
      
      - name: yamllint
        run: yamllint ansible/
      
      - name: gitleaks Secret Scan
        uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```
