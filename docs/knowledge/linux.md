# Linux — Administration Wissensdatenbank
# Stand: 2026-04 | Debian 12/13, Ubuntu 22-25

## 1. Systemverwaltung

### 1.1 Paket-Management (Debian/Ubuntu)
```bash
apt update                          # Paketliste aktualisieren
apt upgrade -y                      # Pakete aktualisieren
apt full-upgrade -y                 # Vollständiges Upgrade (mit Abhängigkeiten)
apt install -y <paket>             # Paket installieren
apt remove <paket>                 # Paket entfernen (Konfiguration bleibt)
apt purge <paket>                  # Paket + Konfiguration entfernen
apt autoremove -y                  # Nicht mehr benötigte Pakete entfernen
apt list --installed                # Installierte Pakete
apt-cache search <suchbegriff>     # Pakete suchen
dpkg -l | grep <name>              # Installiertes Paket prüfen
```

### 1.2 Systemd-Dienste
```bash
systemctl start <dienst>           # Dienst starten
systemctl stop <dienst>            # Dienst stoppen
systemctl restart <dienst>        # Dienst neustarten
systemctl reload <dienst>         # Konfiguration neu laden (kein Neustart)
systemctl enable <dienst>         # Dienst beim Boot aktivieren
systemctl disable <dienst>        # Dienst beim Boot deaktivieren
systemctl status <dienst>         # Dienst-Status anzeigen
systemctl is-active <dienst>      # Ist Dienst aktiv? (rc=0 ja, rc=3 nein)
systemctl daemon-reload            # systemd neu laden (nach .service-Änderungen)

# Logs eines Dienstes anzeigen
journalctl -u <dienst>            # Alle Logs
journalctl -u <dienst> -f        # Live-Logs (follow)
journalctl -u <dienst> --since "1 hour ago"
journalctl -u <dienst> -n 100    # Letzte 100 Zeilen
```

### 1.3 Benutzer und Rechte
```bash
useradd -m -s /bin/bash <user>    # Benutzer anlegen (mit Home)
usermod -aG <gruppe> <user>       # Benutzer zu Gruppe hinzufügen
passwd <user>                      # Passwort setzen
su - <user>                        # Als Benutzer einloggen
sudo -u <user> <befehl>           # Befehl als anderer Benutzer

# Dateiberechtigungen
chmod 600 datei                    # Nur Eigentümer: lesen/schreiben
chmod 644 datei                    # Eigentümer: lesen/schreiben; Gruppe/Andere: lesen
chmod 700 verzeichnis              # Nur Eigentümer: Vollzugriff
chmod 755 verzeichnis              # Eigentümer: Vollzugriff; Gruppe/Andere: lesen+ausführen
chown user:gruppe datei            # Eigentümer/Gruppe ändern
chown -R user:gruppe verzeichnis   # Rekursiv
```

## 2. Netzwerk

### 2.1 Netzwerk-Diagnose
```bash
ip addr                            # IP-Adressen anzeigen
ip route                           # Routing-Tabelle
ip link                            # Netzwerkinterfaces
ss -tlnp                           # Offene Ports (Ersatz für netstat)
ss -tulnp                          # TCP + UDP offene Ports
ping -c4 <host>                    # Erreichbarkeit testen
traceroute <host>                  # Route verfolgen
dig <domain>                       # DNS-Auflösung
nslookup <domain>                  # DNS-Auflösung (einfacher)
curl -v https://example.com        # HTTP-Verbindung testen
```

### 2.2 UFW Firewall
```bash
ufw status                         # Status anzeigen
ufw status verbose                 # Detaillierter Status
ufw enable                         # Firewall aktivieren (VORSICHT: SSH vorher erlauben!)
ufw disable                        # Firewall deaktivieren
ufw default deny incoming          # Standard: alles eingehend blockieren
ufw default deny outgoing          # Standard: alles ausgehend blockieren
ufw allow ssh                      # SSH erlauben (Port 22)
ufw allow 22/tcp                   # Explizit Port 22
ufw allow from 192.0.2.0/24       # Von bestimmtem Netzwerk
ufw allow in on eth0 to any port 80  # Auf bestimmtem Interface
ufw delete allow 80/tcp            # Regel löschen
ufw reset                          # Alle Regeln zurücksetzen
```

## 3. Sicherheit

### 3.1 SSH-Konfiguration (/etc/ssh/sshd_config)
```
# Sicherheits-Einstellungen:
PermitRootLogin no                 # Root-Login verbieten
PasswordAuthentication no          # Passwort-Auth deaktivieren
PubkeyAuthentication yes           # Nur Schlüssel
Protocol 2                         # Nur SSH-Protokoll 2
MaxAuthTries 3                     # Max. 3 Fehlversuche
LoginGraceTime 60                  # 60 Sekunden für Login
AllowUsers <user>                  # Nur bestimmte Benutzer
ClientAliveInterval 300            # Keep-Alive alle 5 Minuten
ClientAliveCountMax 2             # Max. 2 Keep-Alives ohne Antwort
```

### 3.2 Fail2Ban
```bash
fail2ban-client status             # Status aller Jails
fail2ban-client status sshd        # SSH-Jail Status (gebannte IPs)
fail2ban-client unban <IP>         # IP entbannen
fail2ban-client reload             # Konfiguration neu laden
cat /var/log/fail2ban.log          # Fail2Ban Logs
```

### 3.3 Sysctl-Härtung (/etc/sysctl.d/99-hardening.conf)
```
# Netzwerk-Härtung
net.ipv4.tcp_syncookies = 1           # SYN-Flood Schutz
net.ipv4.ip_forward = 0              # IP-Weiterleitung aus (außer bei Router)
net.ipv4.conf.all.rp_filter = 1      # Reverse Path Filtering
net.ipv4.conf.all.accept_redirects = 0 # ICMP-Redirects deaktivieren
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Kernel-Härtung
kernel.randomize_va_space = 2         # ASLR aktivieren
kernel.dmesg_restrict = 1            # dmesg für nicht-root einschränken
kernel.kptr_restrict = 2             # Kernel-Pointer verstecken
```

## 4. Festplatten und Storage

```bash
df -h                              # Festplattenauslastung
du -sh /pfad/*                    # Verzeichnisgrößen
lsblk                              # Block-Devices anzeigen
fdisk -l                           # Partitionen anzeigen
mount                              # Eingehängte Dateisysteme
findmnt                            # Eingehängte Dateisysteme (schöne Ausgabe)

# Große Dateien finden
find / -type f -size +100M 2>/dev/null | head -20

# Speichernutzung sortiert
du -sh /* 2>/dev/null | sort -h | tail -10
```

## 5. Prozesse und Ressourcen

```bash
top / htop                         # Prozess-Übersicht (htop besser)
ps aux                             # Alle Prozesse
ps aux | grep <name>               # Prozess suchen
kill <PID>                         # Prozess beenden (SIGTERM)
kill -9 <PID>                      # Prozess sofort töten (SIGKILL)
killall <name>                     # Alle Prozesse mit Name beenden
pgrep <name>                       # PID suchen
free -h                            # RAM-Auslastung
vmstat 1                           # System-Statistiken (jede Sekunde)
iostat -x 1                        # Festplatten-I/O
```

## 6. Logs

```bash
journalctl                         # Alle System-Logs
journalctl -b                      # Logs seit letztem Boot
journalctl -b -1                   # Logs vom vorletzten Boot
journalctl --since "2025-01-01"    # Ab Datum
journalctl -p err                  # Nur Fehler
journalctl -k                      # Nur Kernel-Logs
journalctl --disk-usage            # Log-Speicherverbrauch
journalctl --vacuum-size=500M      # Logs auf 500MB begrenzen

# Klassische Log-Dateien
tail -f /var/log/syslog            # System-Log live
tail -f /var/log/auth.log          # Auth-Logs (SSH-Logins, sudo)
cat /var/log/dpkg.log              # Paket-Installations-Log
```

## 7. Automatische Updates (unattended-upgrades)

```bash
# Installieren und konfigurieren
apt install -y unattended-upgrades apt-listchanges

# Konfiguration
cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Mail "root";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";  # Manuelle Neustarts bevorzugt
EOF

# Aktivieren
dpkg-reconfigure --priority=low unattended-upgrades

# Status prüfen
systemctl status unattended-upgrades
cat /var/log/unattended-upgrades/unattended-upgrades.log
```

## 8. Cron-Jobs

```bash
# Crontab bearbeiten
crontab -e                         # Eigene Crontab
crontab -l                         # Eigene Crontab anzeigen
crontab -u root -e                 # Root-Crontab

# Syntax: MIN STD TAG MON WOT BEFEHL
# 0 3 * * *  = täglich um 03:00 Uhr
# 0 2 * * 0  = sonntags um 02:00 Uhr
# */15 * * * * = alle 15 Minuten

# Systemd-Timer (modernere Alternative)
# /etc/systemd/system/backup.service + backup.timer
systemctl list-timers              # Alle Timer anzeigen
```

## 9. Nützliche Tools installieren

```bash
apt install -y \
  htop \          # Prozess-Monitor
  ncdu \          # Disk-Usage mit TUI
  tree \          # Verzeichnisbaum
  vim \           # Editor
  curl wget \     # HTTP-Downloads
  jq \            # JSON verarbeiten
  ripgrep \       # Schnelles grep (rg)
  mtr \           # Traceroute + ping
  tcpdump \       # Netzwerk-Analyse
  rsync \         # Dateisynchronisation
  git \           # Versionskontrolle
  fail2ban \      # Brute-Force-Schutz
  ufw \           # Firewall
  certbot \       # Let's Encrypt
  lynis \         # Sicherheits-Audit
  gitleaks        # Secret-Scanner
```
