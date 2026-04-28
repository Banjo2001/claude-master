# Deploy-Anleitung — Von Null bis Claude Code

> Diese Anleitung beschreibt alles was **manuell** erledigt werden muss,
> bevor Claude Code übernehmen kann.
>
> Zeitaufwand: ca. 60–90 Minuten

---

## Voraussetzungen (auf deinem lokalen PC)

Bevor du anfängst, braucht dein lokaler PC:

- **SSH-Client** (Linux/Mac: bereits vorhanden | Windows: Windows Terminal + OpenSSH)
- **Browser** (für Hetzner Robot und Proxmox Web-UI)
- **Passwort-Manager** (z.B. KeePass, Bitwarden) — für alle Passwörter und Keys

---

## Schritt 1 — SSH-Key erstellen (auf lokalem PC)

```bash
# Ed25519 Key erstellen (sicherer als RSA)
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_proxmox -C "proxmox-admin"

# Public Key anzeigen und kopieren (wird gleich benötigt)
cat ~/.ssh/id_ed25519_proxmox.pub
```

**Sichern:** Beide Dateien (`id_ed25519_proxmox` + `.pub`) in Passwort-Manager sichern!

---

## Schritt 2 — Hetzner Dedicated Server bestellen

1. **Hetzner Robot** öffnen: https://robot.hetzner.com
2. **Server bestellen** (Empfehlung: AX41 oder größer)
3. Nach Lieferung: **Rescue-System aktivieren**
   - Robot → Server → Rescue → Aktivieren
   - Root-Passwort notieren
   - Server neu starten

---

## Schritt 3 — Proxmox VE 9.x installieren

```bash
# In Rescue-System einloggen
ssh root@<SERVER-IP>
# Passwort: aus Schritt 2

# installimage aufrufen
installimage
```

**Auswahl im Installer:**
```
→ Other → Proxmox VE 9.x
```

**Konfiguration in installimage:**
```bash
# Hostname setzen
HOSTNAME pve01.example.com   # ANPASSEN

# Festplatten (Beispiel für 2x NVMe RAID-1):
SWRAID 1
SWRAIDLEVEL 1
DRIVE1 /dev/nvme0n1
DRIVE2 /dev/nvme1n1

# Partitionen
PART /boot/efi esp 256M
PART /boot ext4 1G
PART lvm pve all

# LVM Volumes
LV pve root / ext4 50G
LV pve swap swap swap 8G
```

**Speichern und installieren** → Server bootet neu (~5 min)

---

## Schritt 4 — Proxmox Erstzugang und Grundkonfiguration

```bash
# SSH-Key auf Proxmox-Host kopieren
ssh-copy-id -i ~/.ssh/id_ed25519_proxmox.pub root@<SERVER-IP>

# Testen ob Key-Auth funktioniert
ssh -i ~/.ssh/id_ed25519_proxmox root@<SERVER-IP>
```

**Im Browser:** Proxmox Web-UI öffnen:
```
https://<SERVER-IP>:8006
Login: root / <INSTALLATIONSPASSWORT>
```

**Subscription-Hinweis wegklicken** (kein Abonnement nötig für Homelab):

Proxmox Web-UI → Node → Updates → Repositories:
- `pve-enterprise` deaktivieren
- `pve-no-subscription` aktivieren:

```bash
# Auf dem Proxmox-Host via SSH:
# Enterprise-Repo deaktivieren
echo "# disabled" > /etc/apt/sources.list.d/pve-enterprise.list

# No-Subscription-Repo aktivieren
echo "deb http://download.proxmox.com/debian/pve trixie pve-no-subscription" \
    > /etc/apt/sources.list.d/pve-no-subscription.list

# Updates installieren
apt update && apt dist-upgrade -y
```

---

## Schritt 5 — LXC Container für Control Node erstellen

**Im Proxmox Web-UI:**

1. **Debian 12 Template herunterladen:**
   Lokaler Storage → CT Templates → Templates → `debian-12-standard` → Herunterladen

2. **LXC erstellen:**
   ```
   CT ID:        100
   Hostname:     control-node
   Template:     debian-12-standard
   Storage:      local-lvm
   Disk:         20 GB
   CPU:          2 Kerne
   RAM:          2048 MB
   Netzwerk:     vmbr0, DHCP oder feste IP
   ```

3. **LXC starten** und **SSH-Key hinterlegen:**
   ```bash
   # Auf Proxmox-Host:
   pct exec 100 -- bash -c "mkdir -p /root/.ssh && chmod 700 /root/.ssh"

   # Public Key in den Container kopieren
   cat ~/.ssh/id_ed25519_proxmox.pub | \
     pct exec 100 -- bash -c "cat >> /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys"
   ```

4. **IP-Adresse des Containers herausfinden:**
   ```bash
   pct exec 100 -- ip addr show eth0
   ```

5. **Verbindung testen:**
   ```bash
   # Von lokalem PC:
   ssh -i ~/.ssh/id_ed25519_proxmox root@<CONTAINER-IP>
   ```

---

## Schritt 6 — Control Node einrichten

```bash
# Im LXC Container (via SSH):
ssh -i ~/.ssh/id_ed25519_proxmox root@<CONTAINER-IP>

# Grundpakete installieren
apt update && apt install -y git curl wget ansible python3 python3-pip

# Ansible Community Collections installieren
ansible-galaxy collection install community.general community.docker ansible.posix

# Repository klonen
cd /opt
git clone https://github.com/Banjo2001/claude-master.git infra-admin
cd infra-admin
```

---

## Schritt 7 — Preflight-Check ausführen

```bash
# Im /opt/infra-admin Verzeichnis:
bash scripts/setup/00_preflight_check.sh
```

**Alle Checks müssen grün sein** bevor du weitermachst.
Falls etwas rot ist: Anweisung im Script befolgen.

---

## Schritt 8 — Claude Code installieren

```bash
bash scripts/setup/01_install_claude_code.sh
```

Nach der Installation:
```bash
# Claude Code Verbindung testen
claude --version

# Anthropic API-Key setzen (aus https://console.anthropic.com)
export ANTHROPIC_API_KEY="sk-ant-..."
# Oder dauerhaft in ~/.bashrc:
echo 'export ANTHROPIC_API_KEY="sk-ant-..."' >> ~/.bashrc
source ~/.bashrc
```

---

## Schritt 9 — Git konfigurieren + gitleaks einrichten

```bash
bash scripts/setup/02_configure_git.sh
```

Du wirst nach Git-Benutzername und E-Mail gefragt.

---

## ✅ Ab hier übernimmt Claude Code

Starte Claude Code im Repository:

```bash
cd /opt/infra-admin
claude
```

Den vorbereiteten Prompt aus `prompt.txt` (im Repo-Root) komplett kopieren und
in Claude Code einfügen. Claude Code arbeitet dann selbstständig durch:

```bash
# Prompt anzeigen, kopieren und in Claude Code einfügen:
cat prompt.txt
```

Der Prompt führt Claude Code durch:
1. Setup-Skripte 03 → 06 (Vault + Secrets + DNS-Check + Inventar-Validierung)
2. Manuelles Eintragen der API-Tokens und IPs
3. Dry-Run + schrittweise Deploys (common → docker → matrix → nextcloud)
4. Tests und Status-Updates in `actionlog.md`

---

## Was Claude Code dann automatisch erledigt

1. `scripts/setup/03_init_ansible_vault.sh` — Vault initialisieren
2. Echte IPs in `hosts.yml` eintragen (du gibst sie an)
3. Secrets in `vault.yml` eintragen (du gibst sie an)
4. DNS-Einträge setzen (du wirst informiert was einzutragen ist)
5. `ansible-playbook common.yml` — Basis-Hardening
6. `ansible-playbook docker.yml` — Docker installieren
7. `ansible-playbook matrix_synapse.yml` — Matrix deployen
8. Matrix testen (Federation, Client-API)
9. `ansible-playbook nextcloud_aio.yml` — Nextcloud deployen
10. Nextcloud über Admin-Interface einrichten (du klickst)
11. Monitoring und Backup aktivieren

---

## Wichtige Zugangsdaten sichern

Vor dem Deploy in **Passwort-Manager** eintragen:

| Was | Wo |
|-----|----|
| SSH Private Key | `~/.ssh/id_ed25519_proxmox` |
| SSH Public Key | `~/.ssh/id_ed25519_proxmox.pub` |
| Proxmox root Passwort | aus Installation |
| Hetzner Robot Login | https://robot.hetzner.com |
| Anthropic API Key | https://console.anthropic.com |
| Gitea/GitHub Zugangsdaten | für Repo-Zugriff |

---

## Notfall: Aussperrung vom Server

Falls SSH nicht mehr funktioniert:

1. **Hetzner Robot** → Server → Rescue aktivieren
2. In Rescue einloggen: `ssh root@<IP>` (Rescue-Passwort)
3. Proxmox-Partition mounten:
   ```bash
   mount /dev/mapper/pve-root /mnt
   # SSH-Key in authorized_keys prüfen/reparieren
   cat /mnt/root/.ssh/authorized_keys
   ```
4. Server neu starten

---

## Checkliste vor dem Start

```
[ ] Hetzner Account erstellt und Server bestellt
[ ] SSH-Key ed25519 erstellt und Public Key kopiert
[ ] Browser-Zugang zu Proxmox Web-UI getestet
[ ] Passwort-Manager bereit
[ ] Anthropic API-Key vorhanden (https://console.anthropic.com)
[ ] Domains für Matrix und Nextcloud registriert
[ ] DNS-Zugang (um A-Records setzen zu können)
```
