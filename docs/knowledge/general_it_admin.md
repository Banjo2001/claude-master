# Allgemeine IT-Administration — Wissensdatenbank
# Stand: 2026-04

## 1. Dokumentations-Standards

### 1.1 Warum dokumentieren?
```
- Anderer Admin muss das System übernehmen können
- Man selbst vergisst Details nach 6 Monaten
- Incident Response braucht klare Prozesse
- Compliance-Anforderungen (BSI, ISO 27001, DSGVO)
```

### 1.2 Minimale Dokumentation pro Dienst
```markdown
# Dienst: Name

## Zweck
Was macht dieser Dienst?

## Architektur
Welche Komponenten? Wie hängen sie zusammen?

## URLs und Ports
- Admin-UI: https://example.com:8080
- API: https://example.com/api

## Konfiguration
Wo liegen die Konfigurationsdateien?

## Backup
Was wird gesichert? Wie? Wie oft?

## Logs
Wo sind die Logs? Wie betrachtet man sie?

## Update-Prozess
Wie wird der Dienst aktualisiert?

## Rollback
Wie macht man eine Änderung rückgängig?

## Kontakt
Wer ist verantwortlich?
```

## 2. Change Management

### 2.1 Änderungsprotokoll (Change Log)
```
Vor JEDER Änderung in Produktion:
1. Backup/Snapshot erstellen
2. Änderung planen und dokumentieren
3. Change-Fenster festlegen (z.B. Sonntag 02:00-04:00)
4. Rollback-Plan definieren
5. Änderung durchführen
6. Testen (ist alles wie erwartet?)
7. Änderung dokumentieren (Changelog)
```

### 2.2 Maintenance-Fenster
```
Empfehlung für Produktivsysteme:
- Reguläre Updates: Sonntag 02:00-04:00 Uhr (wenig Nutzer)
- Sicherheitsupdates: Sofort (kritisch) oder nächstes Fenster
- Größere Änderungen: Ankündigung an Nutzer (24-48h vorher)
```

## 3. Capacity Planning

### 3.1 Ressourcen-Monitoring
```bash
# Speicher-Trends (täglich loggen)
df -h / >> /var/log/disk_usage.log

# RAM-Nutzung
free -h | grep Mem >> /var/log/memory.log

# Was verbraucht Speicher?
du -sh /var/lib/docker/* | sort -h

# Datenbankgröße
docker exec postgres psql -U synapse_user -c "
SELECT pg_database.datname,
       pg_size_pretty(pg_database_size(pg_database.datname)) AS Size
FROM pg_database
ORDER BY pg_database_size(pg_database.datname) DESC;"
```

### 3.2 Wachstums-Abschätzung
```
Matrix Synapse (50 aktive Nutzer):
- Datenbank: ~1-5 GB pro Jahr (ohne Medien)
- Medien: stark abhängig von Nutzung (5-50 GB)
- PostgreSQL WAL: ~500 MB - 2 GB

Nextcloud (20 aktive Nutzer, 100 GB Storage):
- Datenbank: ~500 MB - 2 GB
- Dateien: Nutzerlimit (z.B. 5 GB/Nutzer = 100 GB)
```

## 4. Passwort und Secret Management

### 4.1 Passwort-Generierung
```bash
# Sicheres Passwort generieren (32 Zeichen, alphanumerisch)
openssl rand -base64 32

# Nur alphanumerisch (für Datenbankpasswörter)
openssl rand -hex 32

# UUID (für API-Tokens, Synapse-Secret)
python3 -c "import secrets; print(secrets.token_hex(32))"
```

### 4.2 Secrets-Hierarchie
```
Tier 1 (Kritisch):
  - Root-SSH-Schlüssel
  - Ansible Vault Passwort
  - Datenbankpasswörter

Tier 2 (Wichtig):
  - API-Tokens
  - Matrix Shared Secret
  - Let's Encrypt Account

Tier 3 (Standard):
  - Service-Account Passwörter
  - Monitoring-Zugänge

Aufbewahrung:
  - Tier 1: Hardware-Key (YubiKey) + Passwort-Manager (KeePassXC offline)
  - Tier 2: Ansible Vault + Passwort-Manager
  - Tier 3: Ansible Vault
```

## 5. Disaster Recovery

### 5.1 RTO und RPO
```
RTO (Recovery Time Objective): Wie lange darf der Dienst ausfallen?
  - Matrix Synapse: max. 4h (Kommunikation)
  - Nextcloud: max. 8h (Dokumente)

RPO (Recovery Point Objective): Wie alt darf das Backup bei Restore sein?
  - Matrix: max. 24h (täglich Backup)
  - Nextcloud: max. 24h

Daraus folgt:
  - Täglich Backup ist ausreichend
  - Für kürzere RPO: 2x täglich oder Streaming-Replikation
```

### 5.2 Recovery-Szenarien
```
Szenario 1: Konfigurationsfehler
→ Rollback via Proxmox-Snapshot (< 5 Min)

Szenario 2: Datenbankkorruption
→ pg_restore vom letzten Backup (30-60 Min)

Szenario 3: Kompletter Server-Ausfall
→ Neuen Server aufsetzen + Ansible-Playbook + Backup-Restore (2-4h)

Szenario 4: Datenzentrum-Ausfall
→ Auf zweitem Server deployen (AWS, Hetzner Cloud) (2-6h)
```

## 6. Sicherheits-Checkliste (monatlich)

```markdown
## Monatliche Sicherheits-Checkliste

### System
- [ ] Sind alle Pakete aktuell? (apt update && apt list --upgradable)
- [ ] Gibt es kritische CVEs für unsere Software? (CVE-Check)
- [ ] Sind die Docker-Images aktuell? (docker compose pull --dry-run)
- [ ] Auslaufende TLS-Zertifikate? (check_ssl_certs.sh)

### Zugang
- [ ] Aktive SSH-Schlüssel prüfen (authorized_keys)
- [ ] Aktive API-Tokens prüfen (Proxmox, PBS)
- [ ] Gibt es unbekannte Benutzerkonten? (cat /etc/passwd | grep -v nologin)
- [ ] Fail2Ban aktiv und gebannte IPs prüfen?

### Backup
- [ ] Backup heute erfolgreich? (PBS-Webinterface prüfen)
- [ ] Letzter Restore-Test wann? (alle 3 Monate testen!)
- [ ] Backup-Speicher ausreichend? (df -h)

### Logs
- [ ] Verdächtige Log-Einträge? (journalctl -p err -b)
- [ ] Ungewöhnliche Logins? (last -n 20)
- [ ] Fail2Ban Anomalien? (fail2ban-client status)

### Dokumentation
- [ ] Änderungen der letzten 30 Tage dokumentiert?
- [ ] Passwörter müssen rotiert werden?
```

## 7. Kommunikation bei Ausfällen

### 7.1 Statuspages
```
# Mögliche Lösungen für eigene Statuspage:
# - Uptime Kuma (selbstgehostet, Docker)
# - Cachet (selbstgehostet)
# - Statuspal (SaaS)

# Wichtig: Statuspage muss unabhängig vom betroffenen System laufen!
```

### 7.2 Incident-Kommunikation
```
Incident-Template (für Matrix/E-Mail):
---
INCIDENT: [SCHWERE: Critical/High/Medium]
Dienst: Nextcloud
Beginn: 2025-01-01 14:32 Uhr
Status: In Bearbeitung

Beschreibung: Nextcloud nicht erreichbar (502 Bad Gateway)

Ursache: (wird ermittelt) / (Docker-Container abgestürzt)

Maßnahmen: Container neu gestartet, Logs werden analysiert

Nächstes Update: in 30 Minuten
---
```
