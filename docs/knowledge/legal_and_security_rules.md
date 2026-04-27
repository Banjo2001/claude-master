# Rechtliche und Sicherheitsregeln
# Stand: 2026-04 | Gilt für: ALLE Aktionen in diesem Repository

## 1. Grundprinzipien (UNVERHANDELBAR)

### 1.1 Keine echten Secrets im Repo

NIEMALS folgendes in Git-Dateien schreiben:
- Passwörter (auch nicht "Test-Passwörter")
- API-Tokens oder API-Keys
- SSH Private Keys
- OAuth Client Secrets
- Datenbankpasswörter
- Zertifikatsprivat-Schlüssel

Ausschließlich Platzhalter verwenden:
```
<DEIN_TOKEN>          — für API-Tokens
<DEINE_DOMAIN>        — für Domainnamen (z.B. example.com)
<DEIN_USER>           — für Benutzernamen
<DEIN_PASSWORT>       — für Passwörter (wird via Vault gesetzt)
192.0.2.10            — Platzhalter-IPv4 (TEST-NET RFC 5737)
198.51.100.10         — weiterer Platzhalter (TEST-NET-2 RFC 5737)
203.0.113.10          — weiterer Platzhalter (TEST-NET-3 RFC 5737)
2001:db8::10          — Platzhalter-IPv6 (Dokumentations-Range RFC 3849)
pve01.example.com     — Platzhalter-Hostname
```

### 1.2 Least Privilege — Minimale Rechte

Jede Komponente erhält nur die minimal notwendigen Rechte:
- Docker Container: kein Root, kein --privileged (außer PBS-Client)
- Ansible: kein sudo ALL, nur benötigte Befehle
- Proxmox API Tokens: nur die nötigen Berechtigungen
- SSH: kein PasswordAuthentication, kein Root-Login

### 1.3 Backup vor Änderung

VOR jeder Änderung an produktiven Systemen:
1. Proxmox Snapshot erstellen
2. Konfigurationsdatei sichern: cp datei datei.bak.$(date +%F)
3. Rollback-Pfad kennen und dokumentieren

### 1.4 Destruktive Befehle markieren

Jeder destruktive Befehl muss davor haben:
```bash
# ⚠️  ACHTUNG — DESTRUKTIV: Dieser Befehl kann Datenverlust verursachen.
# Nur ausführen, wenn ein aktuelles Backup/Snapshot vorhanden ist.
# Rollback: <konkreter Rollback-Befehl>
```

Betrifft: rm -rf, dd, mkfs, wipefs, truncate, > datei,
git push --force, git reset --hard, DROP TABLE,
qm destroy, pct destroy, systemctl restart (Produktivdienste),
Firewall-Policy-Änderungen, Secret-Rotation.

## 2. DSGVO — Datenschutz-Grundverordnung

### 2.1 Relevanz für dieses Projekt

Matrix Synapse und Nextcloud verarbeiten personenbezogene Daten:
- Chat-Nachrichten (Matrix)
- Dateien und Dokumente (Nextcloud)
- E-Mail-Adressen und Nutzerprofile

### 2.2 Pflichten als Betreiber

- Datenschutzerklärung erstellen und veröffentlichen
- Auftragsverarbeitungsvertrag (AVV) bei Drittanbietern
- Datenminimierung: Nur notwendige Daten erheben
- Recht auf Löschung: Nutzer können Konto-Löschung verlangen
- Backup-Retention: Backups nicht länger als nötig aufbewahren
  (Matrix/Nextcloud: max. 30-90 Tage je nach Policy)
- Meldepflicht bei Datenpanne: 72h an Datenschutzbehörde

### 2.3 Technische Maßnahmen (TOMs)

- Verschlüsselung in Übertragung: TLS 1.2+ (besser TLS 1.3)
- Verschlüsselung im Ruhezustand: Festplattenverschlüsselung (LUKS)
- Zugriffskontrolle: Nur autorisierte Nutzer
- Logging: Zugriffe protokollieren, aber nicht übermäßig
- Pseudonymisierung wo möglich

## 3. BSI Grundschutz — relevante Maßnahmen

### 3.1 SSH-Härtung (nach BSI SYS.1.1)

```
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
Protocol 2
MaxAuthTries 3
LoginGraceTime 60
ClientAliveInterval 300
ClientAliveCountMax 2
AllowUsers <DEIN_USER>
```

Erlaubte Cipher (BSI-konform, Stand 2024):
```
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
```

### 3.2 Firewall (nach BSI NET.3.2)

Prinzip: Default Deny — alles ist verboten, außer explizit erlaubt.
```bash
ufw default deny incoming
ufw default deny outgoing
ufw allow out 80/tcp   # HTTP (für apt, Let's Encrypt)
ufw allow out 443/tcp  # HTTPS
ufw allow out 53/udp   # DNS
ufw allow out 53/tcp   # DNS (TCP Fallback)
ufw allow in 22/tcp    # SSH (nur von bestimmten IPs!)
ufw allow in 80/tcp    # HTTP (Let's Encrypt Challenge)
ufw allow in 443/tcp   # HTTPS
```

### 3.3 Automatische Sicherheitsupdates (BSI SYS.1.1)

```bash
apt install -y unattended-upgrades
# Konfiguration: /etc/apt/apt.conf.d/50unattended-upgrades
# Sicherheitsupdates automatisch installieren
# Reboot-Benachrichtigung konfigurieren
```

### 3.4 Audit und Logging (BSI OPS.1.1.7)

- Fail2Ban: Brute-Force-Schutz für SSH, Matrix, Nextcloud
- Systemd Journal: Zentrale Log-Sammlung
- Logrotate: Logs rotieren, um Speicher zu sparen
- Optional: Graylog oder Loki für zentrales Log-Management

## 4. Ansible Vault — Secret Management

### 4.1 Warum Vault?

Ansible Vault verschlüsselt Secrets mit AES-256.
So können vault.yml-Dateien im Git-Repo liegen, ohne Secrets preiszugeben.

### 4.2 Grundlegende Befehle

```bash
# Neue verschlüsselte Datei erstellen
ansible-vault create ansible/inventories/prod/group_vars/all/vault.yml

# Bestehende Datei verschlüsseln
ansible-vault encrypt datei.yml

# Entschlüsseln (nur lokal, NIE committen!)
ansible-vault decrypt datei.yml

# Inhalt anzeigen
ansible-vault view datei.yml

# Passwort ändern
ansible-vault rekey datei.yml

# Playbook mit Vault ausführen
ansible-playbook site.yml --vault-password-file ~/.vault_pass.txt
# ODER interaktiv:
ansible-playbook site.yml --ask-vault-pass
```

### 4.3 Vault-Passwort sicher aufbewahren

```bash
# Vault-Passwort-Datei AUSSERHALB des Repos anlegen!
echo "<SICHERES_PASSWORT>" > ~/.vault_pass.txt
chmod 600 ~/.vault_pass.txt
# Diese Datei NIEMALS ins Repo committen
# Sicherung: separates Passwort-Manager Eintrag (z.B. KeePassXC)
```

## 5. Docker Security

### 5.1 Pflicht-Konfiguration für jeden Container

```yaml
security_opt:
  - no-new-privileges:true   # Verhindert Privilege-Escalation
cap_drop:
  - ALL                       # Alle Linux Capabilities entfernen
read_only: true               # Dateisystem schreibgeschützt (wo möglich)
```

### 5.2 Kein :latest

```yaml
# FALSCH — nicht reproduzierbar:
image: postgres:latest

# RICHTIG — fixe Version:
image: postgres:16.4  # Stand: 2025-01, prüfen: hub.docker.com/_/postgres/tags
```

### 5.3 Kein Root-User

```yaml
user: "1000:1000"  # UID:GID des Dienstnutzers
# Oder in Dockerfile:
# USER nobody
```

### 5.4 Netzwerk-Isolation

```yaml
networks:
  internal:        # Internes Netzwerk (kein Internet-Zugriff)
    internal: true
  external:        # Nur für Container die nach außen müssen
    internal: false
```

## 6. Changelog-Format

Jeder Changelog-Eintrag in docs/changelogs/ muss enthalten:

```markdown
# YYYY-MM-DD — Kurztitel der Änderung

## Was wurde geändert?
- Punkt 1
- Punkt 2

## Warum?
Begründung

## Rollback
Wie macht man die Änderung rückgängig?

## Getestet mit
- Umgebung: Proxmox VE 9.x
- Datum: YYYY-MM-DD
- Ergebnis: OK / Fehler: <Beschreibung>
```

## 7. Git Security Best Practices

```bash
# Secrets NIEMALS committen — gitleaks als Pre-Commit-Hook verwenden
# gitleaks installieren (Go-basiert):
go install github.com/gitleaks/gitleaks/v8@latest
# Oder via Release-Download:
wget https://github.com/gitleaks/gitleaks/releases/latest/download/gitleaks_linux_x64.tar.gz

# Pre-Commit-Hook einrichten (wird von 02_configure_git.sh gemacht)
# Prüft jeden Commit auf versehentliche Secrets

# Git-Historie auf Secrets prüfen:
gitleaks detect --source . --verbose

# Benutzer konfigurieren (nie Root-Benutzer für Git verwenden)
git config --global user.name "<DEIN_NAME>"
git config --global user.email "<DEINE_EMAIL>"
```
