# Docker & Docker Compose v2 — Wissensdatenbank
# Stand: 2026-04 | Docker CE + Compose Plugin

## 1. Grundkonzepte

Docker ist eine Containerisierungsplattform. Container sind isolierte Prozesse
mit eigenem Dateisystem, Netzwerk und Ressourcen.

### Unterschied Container vs. VM:
- VM: Vollständiges OS, mehr Overhead, stärkere Isolation
- Container: Teilt Linux-Kernel, weniger Overhead, schneller
- Für Dienste wie Matrix/Nextcloud: Container bevorzugt

## 2. Docker CE Installation (Empfohlen — NICHT docker.io aus apt)

```bash
# Schritt 1: Alte Versionen entfernen
apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

# Schritt 2: Abhängigkeiten installieren
apt install -y ca-certificates curl gnupg lsb-release

# Schritt 3: Docker GPG-Schlüssel importieren
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Schritt 4: Repository hinzufügen
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

# Schritt 5: Installieren
apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Schritt 6: Verifizieren
docker --version
docker compose version
```

## 3. Docker Sicherheit — Pflichtregeln

### 3.1 Jeder Container MUSS haben:
```yaml
security_opt:
  - no-new-privileges:true   # Verhindert Privilege-Escalation
cap_drop:
  - ALL                       # Alle Linux-Capabilities entfernen
```

### 3.2 Kein :latest-Tag!
```yaml
# FALSCH:
image: postgres:latest

# RICHTIG (fixe Version):
# Stand: 2026-04 — Versionen regelmäßig prüfen!
image: postgres:16.4         # https://hub.docker.com/_/postgres/tags
image: redis:7.2-alpine      # https://hub.docker.com/_/redis/tags
image: nginx:1.27-alpine     # https://hub.docker.com/_/nginx/tags
```

### 3.3 Kein Root-User im Container (wenn vermeidbar):
```yaml
user: "1000:1000"   # UID:GID
# Oder in Dockerfile: USER nobody
```

### 3.4 Netzwerk-Isolation:
```yaml
networks:
  # Nur Container, die kommunizieren müssen, im gleichen Netzwerk
  backend:
    internal: true    # Kein Internet-Zugriff aus diesem Netzwerk
  frontend:
    # Ohne internal: kann auf Internet zugreifen
```

## 4. Docker Compose v2 — Syntax

### 4.1 Grundstruktur (compose.yml)
```yaml
---
# ============================================================
# DATEI: compose.yml — Dienst-Name
# DEPLOY:
#   Vorbereitung: cp .env.example .env && nano .env
#   Start:        docker compose up -d
#   Stopp:        docker compose down
#   Logs:         docker compose logs -f
#   Update:       docker compose pull && docker compose up -d
# ============================================================

# WICHTIG: 'version:' ist in Compose v2 veraltet — weglassen!

services:
  service-name:
    image: image:tag
    container_name: service-name
    restart: unless-stopped   # Neustart bei Fehler, aber nicht nach 'docker compose down'
    
    # Umgebungsvariablen aus .env-Datei (die NICHT im Repo liegt)
    env_file: .env
    
    # Oder direkt (nur für nicht-sensitive Werte):
    environment:
      - TZ=Europe/Berlin
      - PUID=1000
      - PGID=1000
    
    # Volumes
    volumes:
      - ./data:/var/lib/service:rw
      - ./config:/etc/service:ro  # :ro = read-only
    
    # Ports (nur wenn nötig — intern via Docker-Netz bevorzugen)
    ports:
      - "127.0.0.1:8080:8080"  # Nur localhost, NICHT 0.0.0.0!
    
    # Netzwerke
    networks:
      - backend
    
    # Sicherheit (PFLICHT!)
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    
    # Ressourcenlimits
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: "1.0"

networks:
  backend:
    internal: true
```

### 4.2 Wichtige Befehle
```bash
# Container starten (detached = im Hintergrund)
docker compose up -d

# Container stoppen (Daten bleiben erhalten)
docker compose down

# Container stoppen UND Volumes löschen (VORSICHT!)
# ⚠️  ACHTUNG — DESTRUKTIV
docker compose down -v

# Logs anzeigen (follow mode)
docker compose logs -f service-name

# Shell in Container öffnen
docker compose exec service-name bash

# Status anzeigen
docker compose ps

# Images aktualisieren
docker compose pull

# Nach Pull neu starten
docker compose pull && docker compose up -d

# Konfiguration validieren
docker compose config
```

## 5. Volumes und Datenpersistenz

```bash
# Named Volumes (von Docker verwaltet)
volumes:
  postgres_data:    # Docker erstellt und verwaltet dieses Volume
    driver: local

# Bind Mounts (lokales Verzeichnis)
volumes:
  - ./data/postgres:/var/lib/postgresql/data:rw

# Backup von Volumes
# Schritt 1: Container stoppen
docker compose down
# Schritt 2: Daten sichern
tar -czf backup-$(date +%F).tar.gz ./data/
# Schritt 3: Container starten
docker compose up -d
```

## 6. Docker Netzwerke verstehen

```bash
# Netzwerke anzeigen
docker network ls

# Netzwerk inspizieren (welche Container sind verbunden?)
docker network inspect <netzwerk-name>

# Container im gleichen Netzwerk können sich per Container-Name erreichen:
# Container "nginx" erreicht "postgres" via: postgres:5432
```

## 7. Docker Logs und Monitoring

```bash
# Logs aller Container
docker compose logs

# Nur letzte 100 Zeilen, live
docker compose logs --tail=100 -f

# Container-Ressourcen (CPU, RAM)
docker stats

# Container-Details
docker inspect <container-name>

# Festplattennutzung von Docker
docker system df
```

## 8. Sicherheits-Scan

```bash
# Docker Images auf Sicherheitslücken prüfen
# Tool: trivy (empfohlen)
apt install -y wget
wget -qO trivy.tar.gz https://github.com/aquasecurity/trivy/releases/latest/download/trivy_linux_amd64.tar.gz
tar -xzf trivy.tar.gz trivy
./trivy image postgres:16.4

# Oder Docker Scout (offiziell von Docker)
docker scout cves postgres:16.4
```

## 9. Docker in LXC (Proxmox)

### 9.1 Anforderungen
Für Docker in einem unprivilegierten LXC-Container benötigt man:
- `features: nesting=1` in der LXC-Konfiguration
- Kernel-Module: overlay, br_netfilter

### 9.2 LXC-Konfiguration für Docker
```
# In /etc/pve/lxc/<CTID>.conf hinzufügen:
features: nesting=1,keyctl=1
lxc.apparmor.profile: unconfined
lxc.cgroup2.devices.allow: a
lxc.cap.drop:
```

### 9.3 Hinweise
- Privilegierter LXC: Einfacher, aber weniger sicher
- Unprivilegierter LXC mit nesting: Sicherer, aber komplexer
- Empfehlung: Für Produktion vollständige VMs für Docker-Hosts

## 10. Update-Strategie

```bash
# Watchtower — automatische Container-Updates (nur für unkritische Dienste!)
# Für Produktion: NIEMALS automatische Updates ohne Test!
# Stattdessen: Manuelle Updates nach Test in Staging

# Manueller Update-Workflow:
# 1. Neue Version in compose.yml eintragen
# 2. In Staging testen: docker compose -f compose.yml up -d
# 3. Testen ob Dienst funktioniert
# 4. In Produktion deployen (nach Snapshot!)
# 5. Alte Images bereinigen: docker image prune -f
```
