# Ansible Playbooks — Best Practices Wissensdatenbank
# Stand: 2026-04

## 1. Playbook-Struktur Best Practices

### 1.1 Site.yml — Master-Playbook
```yaml
---
# site.yml — Führt ALLE Rollen auf ALLE Hosts aus
# Verwendung: ansible-playbook ansible/playbooks/site.yml
# Dry-Run:    ansible-playbook ansible/playbooks/site.yml --check --diff

- name: "Basis-Konfiguration auf alle Hosts anwenden"
  import_playbook: common.yml

- name: "Matrix Synapse deployen"
  import_playbook: matrix_synapse.yml

- name: "Nextcloud AIO deployen"
  import_playbook: nextcloud_aio.yml
```

### 1.2 Einzelnes Playbook
```yaml
---
# matrix_synapse.yml
- name: "Matrix Synapse Stack deployen"
  hosts: matrix_servers           # Gruppe aus hosts.yml
  become: true                    # sudo verwenden
  gather_facts: true              # Systeminformationen sammeln

  vars_files:
    - "{{ inventory_dir }}/group_vars/all/vars.yml"
    - "{{ inventory_dir }}/group_vars/matrix_servers/vars.yml"

  pre_tasks:
    # WARUM: Vor jedem Deploy sicherstellen, dass Paket-Cache aktuell ist
    - name: "Paket-Cache aktualisieren"
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 3600
      tags: always

  roles:
    - role: common        # Basis-Konfiguration
      tags: common
    - role: docker        # Docker CE installieren
      tags: docker
    - role: matrix_synapse  # Matrix Synapse Stack
      tags: matrix

  post_tasks:
    - name: "Deploy-Status ausgeben"
      ansible.builtin.debug:
        msg: "Matrix Synapse erfolgreich deployed auf {{ inventory_hostname }}"
      tags: always
```

## 2. Rollen-Struktur

```
roles/
└── meine-rolle/
    ├── tasks/
    │   ├── main.yml          # Aufrufreihenfolge der Task-Dateien
    │   ├── install.yml       # Installation
    │   ├── configure.yml     # Konfiguration
    │   └── service.yml       # Dienst-Management
    ├── handlers/
    │   └── main.yml          # Handler (nur bei Änderungen ausgeführt)
    ├── defaults/
    │   └── main.yml          # Standard-Variablen (niedrigste Priorität)
    ├── vars/
    │   └── main.yml          # Interne Variablen (höhere Priorität als defaults)
    ├── files/
    │   └── datei.conf        # Statische Dateien
    ├── templates/
    │   └── config.j2         # Jinja2-Templates
    └── meta/
        └── main.yml          # Rollen-Metadaten und Abhängigkeiten
```

## 3. Tags verwenden

```yaml
# Tags erlauben selektives Ausführen von Tasks
- name: "Docker installieren"
  ansible.builtin.apt:
    name: docker-ce
  tags:
    - docker
    - install

# Verwendung:
# ansible-playbook site.yml --tags docker
# ansible-playbook site.yml --skip-tags install
# ansible-playbook site.yml --tags always  # 'always' immer ausführen
```

## 4. Conditionals (Bedingungen)

```yaml
# Task nur auf Debian-Systemen
- name: "Debian-spezifische Konfiguration"
  ansible.builtin.apt:
    name: apt-transport-https
  when: ansible_os_family == "Debian"

# Task nur wenn Variable gesetzt
- name: "Optionalen Dienst konfigurieren"
  ansible.builtin.template:
    src: optional.conf.j2
    dest: /etc/optional.conf
  when: enable_optional_service | default(false)

# Task nur wenn Datei nicht existiert
- name: "Nur bei Erstinstallation"
  ansible.builtin.shell: setup_script.sh
  args:
    creates: /etc/setup_complete  # Nicht ausführen wenn diese Datei existiert
```

## 5. Fehlerbehandlung

```yaml
# Fehler ignorieren und trotzdem fortfahren
- name: "Status-Check (darf fehlschlagen)"
  ansible.builtin.command: systemctl status nginx
  register: nginx_status
  failed_when: false
  changed_when: false  # Diesen Task nie als "changed" markieren

# Custom Fehlerbedingung
- name: "Prüfe ob Dienst läuft"
  ansible.builtin.command: systemctl is-active nginx
  register: result
  failed_when: result.rc != 0 and result.rc != 3
  # rc=0: aktiv, rc=3: inaktiv, rc=andere: echter Fehler

# Retry bei vorübergehenden Fehlern
- name: "Warte bis Dienst erreichbar ist"
  ansible.builtin.uri:
    url: http://localhost:8008/_matrix/static/
    status_code: 200
  register: result
  until: result.status == 200
  retries: 30
  delay: 10  # 30x versuchen, alle 10 Sekunden
```

## 6. Jinja2 Templates

### 6.1 Grundlegende Template-Syntax
```jinja2
{# Kommentar #}

{# Variable ausgeben #}
{{ variable_name }}

{# Mit Standardwert #}
{{ variable_name | default("Standardwert") }}

{# If-Bedingung #}
{% if enable_feature %}
Feature ist aktiviert
{% endif %}

{# For-Schleife #}
{% for item in liste %}
  - {{ item }}
{% endfor %}

{# Filter #}
{{ text | upper }}                # GROSSBUCHSTABEN
{{ liste | join(", ") }}         # Liste verbinden
{{ zahl | string }}              # Zu String konvertieren
{{ pfad | basename }}            # Dateiname ohne Pfad
```

### 6.2 Konfigurationsdatei-Template
```jinja2
# {{ ansible_managed }}
# Diese Datei wird von Ansible verwaltet — manuelle Änderungen werden überschrieben!

[server]
hostname = {{ ansible_hostname }}
ip = {{ ansible_default_ipv4.address }}
domain = {{ server_domain }}

{% if enable_tls %}
[tls]
cert = /etc/letsencrypt/live/{{ server_domain }}/fullchain.pem
key = /etc/letsencrypt/live/{{ server_domain }}/privkey.pem
{% endif %}
```

## 7. Ansible Galaxy (Rollen aus Community)

```bash
# Verfügbare Rollen suchen
ansible-galaxy search nginx

# Rolle installieren
ansible-galaxy role install geerlingguy.nginx

# Requirements-Datei (empfohlen für Reproduzierbarkeit)
# requirements.yml:
# ---
# roles:
#   - name: geerlingguy.nginx
#     version: 3.2.0
# collections:
#   - name: community.docker
#     version: 3.4.0

ansible-galaxy install -r requirements.yml
```

## 8. Molecule — Rollen testen (für Fortgeschrittene)

```bash
# Molecule installieren
pip3 install molecule molecule-docker

# Test-Szenario initialisieren
cd ansible/roles/common
molecule init scenario

# Tests ausführen (erstellt Docker-Container und testet Rolle)
molecule test

# Nur Konvergenz (schneller)
molecule converge

# Container für manuelle Überprüfung behalten
molecule converge && molecule login
```

## 9. Performance-Tipps

```ini
# ansible.cfg
[defaults]
# Mehrere Hosts parallel verarbeiten
forks = 10

# SSH Multiplexing
[ssh_connection]
pipelining = True
ssh_args = -o ControlMaster=auto -o ControlPersist=300s -o ConnectTimeout=30
```

## 10. Ansible Lint Regeln (Wichtigste)

```yaml
# FALSCH — vermeiden:
- apt: name=nginx state=present     # Veraltete Kurzform

# RICHTIG — verwenden:
- name: "Nginx installieren"
  ansible.builtin.apt:              # Vollständiger FQCN
    name: nginx
    state: present

# Regeln von ansible-lint:
# no-free-form      — Keine Kurzform-Tasks
# yaml[truthy]      — true/false statt yes/no
# name[missing]     — Jeder Task braucht name:
# risky-shell-opt   — Shell-Tasks mit set -o pipefail
# package-latest    — Keine state=latest
```
