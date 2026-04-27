# Ansible — Wissensdatenbank
# Stand: 2026-04 | Ansible 2.17+

## 1. Grundkonzepte

Ansible ist ein agentenloses Automatisierungstool.
Es verbindet sich per SSH zu den Zielhosts und führt Aufgaben (Tasks) aus.

### Wichtige Begriffe:
- **Inventory**: Liste der Zielhosts
- **Playbook**: YAML-Datei mit Aufgaben (Tasks)
- **Role**: Wiederverwendbare Sammlung von Tasks
- **Task**: Einzelne Aufgabe (z.B. Paket installieren)
- **Handler**: Task, der nur bei Änderungen ausgeführt wird
- **Variable**: Konfigurationswert (aus vars.yml oder vault.yml)
- **Module**: Ansible-Funktion (z.B. ansible.builtin.apt)
- **Idempotenz**: Mehrfaches Ausführen ändert nichts, wenn Ziel erreicht

## 2. Installation

```bash
# Debian/Ubuntu
sudo apt install -y ansible

# Python-Pip (neueste Version)
pip3 install ansible

# Version prüfen
ansible --version

# Nützliche Collections installieren
ansible-galaxy collection install community.general
ansible-galaxy collection install community.docker
ansible-galaxy collection install ansible.posix
```

## 3. Ansible-Konfiguration (ansible.cfg)

```ini
[defaults]
# Inventory-Pfad (Standard)
inventory = inventories/prod/hosts.yml

# Verbosity (0=minimal, 4=debug)
verbosity = 1

# Kein Host-Key-Checking (für Test-Umgebungen)
# NICHT in Produktion! Immer known_hosts pflegen.
# host_key_checking = False

# Farbe in Output
force_color = True

# SSH Multiplexing (schnellere Verbindungen)
[ssh_connection]
ssh_args = -o ControlMaster=auto -o ControlPersist=60s
pipelining = True
```

## 4. Inventory-Format (hosts.yml)

```yaml
---
# Alle Hosts in Gruppen organisieren
all:
  children:
    # Gruppe: Alle Proxmox-Hosts
    proxmox:
      hosts:
        pve01.example.com:
          ansible_host: 192.0.2.10
          ansible_user: root
          ansible_ssh_private_key_file: ~/.ssh/id_ed25519_proxmox

    # Gruppe: Matrix-Server
    matrix_servers:
      hosts:
        matrix01.example.com:
          ansible_host: 192.0.2.20
          ansible_user: ansible  # Kein root!
          ansible_become: true   # sudo verwenden

    # Gruppe: Nextcloud-Server
    nextcloud_servers:
      hosts:
        cloud01.example.com:
          ansible_host: 192.0.2.30
          ansible_user: ansible
          ansible_become: true
```

## 5. Task-Syntax und Module

### 5.1 Pakete installieren
```yaml
# WARUM: System-Pakete müssen installiert sein, bevor Dienste starten können
- name: "Basis-Pakete installieren"
  ansible.builtin.apt:
    name:
      - curl
      - git
      - ufw
      - fail2ban
    state: present
    update_cache: true
    cache_valid_time: 3600  # Cache max. 1h alt
```

### 5.2 Datei aus Template erstellen
```yaml
# WARUM: Konfigurationsdateien werden aus Jinja2-Templates generiert
# ROLLBACK: Backup-Datei liegt bei <pfad>.bak
- name: "SSH-Konfiguration aus Template erstellen"
  ansible.builtin.template:
    src: templates/sshd_config.j2
    dest: /etc/ssh/sshd_config
    owner: root
    group: root
    mode: "0600"
    backup: true  # Erstellt automatisch .bak-Datei
  notify: "sshd neu starten"  # Handler aufrufen
```

### 5.3 Dienst verwalten
```yaml
- name: "SSH-Dienst aktivieren und starten"
  ansible.builtin.systemd:
    name: sshd
    state: started
    enabled: true
    daemon_reload: true
```

### 5.4 Benutzer anlegen
```yaml
- name: "Ansible-Benutzer anlegen"
  ansible.builtin.user:
    name: ansible
    shell: /bin/bash
    groups: sudo
    append: true
    create_home: true
    system: false
```

### 5.5 Handler (wird nur bei Änderung aufgerufen)
```yaml
# handlers/main.yml
- name: "sshd neu starten"
  ansible.builtin.systemd:
    name: sshd
    state: restarted
  # SICHERHEIT: Vor Neustart prüfen ob Konfiguration gültig ist
  # Das erledigt das validate-Argument im template-Task
```

## 6. Variables und Vault

### 6.1 Variablen-Hierarchie (Priorität: hoch → niedrig)
```
1. Extra-Vars (--extra-vars / -e)
2. Task-Variablen (vars: im Task)
3. Block-Variablen
4. Role-Variablen (aus defaults/main.yml)
5. Inventory-Group-Vars
6. Inventory-Host-Vars
7. Play-Variablen
```

### 6.2 vars.yml (nicht geheime Variablen)
```yaml
---
# ansible/inventories/prod/group_vars/all/vars.yml
timezone: "Europe/Berlin"
ssh_port: 22
admin_user: "ansible"

# Docker-Versionen (regelmäßig aktualisieren!)
docker_compose_version: "2.24.0"
```

### 6.3 vault.yml (verschlüsselte Secrets)
```yaml
---
# Diese Datei ist mit ansible-vault verschlüsselt
# Bearbeiten: ansible-vault edit vault.yml
# Die Datei enthält Variablen die mit vault_ beginnen:

vault_db_password: "<WIRD_VIA_VAULT_GESETZT>"
vault_matrix_secret: "<WIRD_VIA_VAULT_GESETZT>"
```

### 6.4 Vault in Playbook verwenden
```yaml
# In vars.yml referenzieren (Best Practice: vault_ Präfix)
matrix_db_password: "{{ vault_db_password }}"
```

## 7. Playbook ausführen

```bash
# Syntax-Check (ohne Änderungen)
ansible-playbook --syntax-check ansible/playbooks/site.yml

# Dry-Run (zeigt was sich ändern würde)
ansible-playbook --check --diff ansible/playbooks/site.yml \
  --vault-password-file ~/.vault_pass.txt

# Nur bestimmten Host
ansible-playbook ansible/playbooks/site.yml \
  --limit matrix01.example.com \
  --vault-password-file ~/.vault_pass.txt

# Nur bestimmte Tags
ansible-playbook ansible/playbooks/site.yml \
  --tags "docker,security" \
  --vault-password-file ~/.vault_pass.txt

# Mit erhöhter Verbosity (für Debugging)
ansible-playbook ansible/playbooks/site.yml -vvv \
  --vault-password-file ~/.vault_pass.txt
```

## 8. Ansible-Lint (Code-Qualität)

```bash
# ansible-lint installieren
pip3 install ansible-lint

# Gesamtes Ansible-Verzeichnis prüfen
ansible-lint ansible/

# Einzelnes Playbook prüfen
ansible-lint ansible/playbooks/matrix_synapse.yml

# Häufige Fehler die ansible-lint erkennt:
# - Fehlende name: in Tasks
# - Verwendung von Shell statt spezifischem Modul
# - Veraltete Module-Namen (z.B. 'apt' statt 'ansible.builtin.apt')
# - Fehlende become: bei privilegierten Tasks
```

## 9. Idempotenz sicherstellen

Idempotenz = Das Playbook kann beliebig oft ausgeführt werden,
das Ergebnis ist immer das gleiche.

```yaml
# FALSCH — nicht idempotent (fügt immer hinzu)
- name: "Zeile hinzufügen"
  ansible.builtin.shell: echo "text" >> /etc/datei

# RICHTIG — idempotent
- name: "Zeile in Datei sicherstellen"
  ansible.builtin.lineinfile:
    path: /etc/datei
    line: "text"
    state: present
```

## 10. Debugging

```bash
# Variablen eines Hosts anzeigen
ansible matrix01.example.com -m debug -a "var=hostvars[inventory_hostname]"

# Verbindung testen
ansible all -m ping -i inventories/prod/hosts.yml

# Fakten eines Hosts sammeln
ansible matrix01.example.com -m setup | grep ansible_os_family

# Task-Output anzeigen (register + debug)
```yaml
- name: "Befehl ausführen und Ergebnis speichern"
  ansible.builtin.command: systemctl status nginx
  register: nginx_status
  ignore_errors: true

- name: "Ergebnis anzeigen"
  ansible.builtin.debug:
    var: nginx_status.stdout_lines
```
