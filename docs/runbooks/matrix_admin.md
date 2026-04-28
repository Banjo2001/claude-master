# Runbook: Matrix Synapse Administration

> Stand: 2026-04 | Matrix Synapse v1.123.0

## 1. Dienst-Status prüfen

```bash
# Alle Container
docker compose -f /opt/matrix/compose.yml ps

# Logs anzeigen
docker compose -f /opt/matrix/compose.yml logs --tail=100 synapse
docker compose -f /opt/matrix/compose.yml logs --tail=50 nginx

# Synapse Health-Check
curl -s http://localhost:8008/health
# Erwartet: OK

# Matrix Client API
curl -s https://matrix.example.com/_matrix/client/versions | jq .
```

## 2. Neustart

```bash
# Einzelnen Container neu starten
docker compose -f /opt/matrix/compose.yml restart synapse

# Gesamten Stack neu starten
docker compose -f /opt/matrix/compose.yml down
docker compose -f /opt/matrix/compose.yml up -d

# Reihenfolge beachten: postgres → redis → synapse → nginx
```

## 3. Update

```bash
# Neue Image-Versionen in defaults/main.yml eintragen, dann:
ansible-playbook \
  --vault-password-file ~/.vault_pass.txt \
  --tags nextcloud_compose \
  ansible/playbooks/matrix_synapse.yml

# Oder manuell:
cd /opt/matrix
docker compose pull
docker compose up -d
```

## 4. Admin-User anlegen

```bash
# Methode 1: register_new_matrix_user (im Container)
docker exec -it matrix-synapse-1 \
  register_new_matrix_user \
  -c /config/homeserver.yaml \
  -u <USERNAME> \
  -p '<PASSWORT>' \
  -a \
  http://localhost:8008

# Methode 2: Admin-API (benötigt registration_shared_secret aus vault.yml)
curl -X POST \
  https://matrix.example.com/_synapse/admin/v1/register \
  -H "Content-Type: application/json" \
  -d '{"nonce":"...","username":"admin","password":"...","admin":true,"mac":"..."}'
```

## 5. Passwort zurücksetzen

```bash
# Via Admin-API (Admin-Token erforderlich)
ADMIN_TOKEN="syt_..."  # Token aus vorherigem Login

curl -X PUT \
  https://matrix.example.com/_synapse/admin/v2/users/@user:example.com \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"password": "<NEUES_PASSWORT>"}'
```

## 6. Federation prüfen

```bash
# Lokaler Test
curl -s https://matrix.example.com/.well-known/matrix/server
# Erwartet: {"m.server":"matrix.example.com:443"}

curl -s https://matrix.example.com/.well-known/matrix/client
# Erwartet: {"m.homeserver":{"base_url":"https://matrix.example.com"}}

# Externer Test (Federation Tester)
# https://federationtester.matrix.org/#matrix.example.com
```

## 7. Datenbank-Wartung

```bash
# Verbindung zur PostgreSQL-Datenbank
docker exec -it matrix-postgres-1 psql -U synapse -d synapse

# Größte Tabellen anzeigen
SELECT relname, pg_size_pretty(pg_total_relation_size(relid))
FROM pg_catalog.pg_statio_user_tables
ORDER BY pg_total_relation_size(relid) DESC LIMIT 10;

# Datenbankgröße
SELECT pg_size_pretty(pg_database_size('synapse'));

# Synapse Purge (alte Nachrichten löschen — Admin-API)
# Dokumentation: https://element-hq.github.io/synapse/latest/admin_api/purge_history_api.html
```

## 8. Logs

```bash
# Synapse Logs (in Container)
docker logs matrix-synapse-1 --since 1h

# Nginx Access-Log
tail -f /opt/matrix/data/logs/nginx/access.log

# Nginx Error-Log
tail -f /opt/matrix/data/logs/nginx/error.log

# Fail2Ban Matrix-Jail
fail2ban-client status matrix-synapse
```

## 9. Häufige Probleme

| Problem | Ursache | Lösung |
|---------|---------|--------|
| Federation schlägt fehl | Falscher proxy_pass (trailing slash) | `nginx.conf` prüfen: `proxy_pass http://synapse:8008;` (kein `/`) |
| Registrierung offen | `enable_registration: true` | In `homeserver.yaml` auf `false` setzen |
| TURN funktioniert nicht | coturn_auth_secret falsch | Secret in vault.yml und coturn.conf abgleichen |
| DB-Fehler beim Start | PostgreSQL nicht bereit | `depends_on: postgres: condition: service_healthy` prüfen |
| Signing-Key fehlt | Erster Start | `/data/matrix.example.com.signing.key` wird automatisch erstellt |
