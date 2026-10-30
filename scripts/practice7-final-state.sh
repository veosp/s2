#!/usr/bin/env bash
set -euo pipefail
exec </dev/null
EVIDENCE='/home/devops/devops-course-2026/evidence/practice7'
cd /home/devops/app
{
    printf 'Final container state: %s\n' "$(date -u +%FT%TZ)"
    docker compose config --quiet
    docker compose ps
    for service in app db; do
        container_id="$(docker compose ps -q "$service")"
        [[ -n "$container_id" ]]
        [[ "$(docker inspect --format '{{.State.Health.Status}}' "$container_id")" == healthy ]]
    done
    docker exec app-app-1 id
    docker exec app-app-1 getent ahostsv4 db
    docker exec app-app-1 sh -c 'test ! -e /app/.env && test ! -w /app/app.py'
    [[ "$(docker port app-app-1 5000/tcp)" == '127.0.0.1:5000' ]]
    [[ -z "$(docker port app-db-1)" ]]
    docker port app-app-1
    printf 'DB published ports: none\n'
    if ss -H -tln | awk '{print $4}' | grep -Eq ':(5001|5002)$'; then
        printf 'A temporary test listener remains.\n' >&2
        exit 1
    fi
    if docker ps -a --format '{{.Names}}' | grep -Eq '^(exposed|app-test|practice7-reset-)'; then
        printf 'A temporary test container remains.\n' >&2
        exit 1
    fi
    docker volume ls
    docker volume inspect app_db_data --format '{{.Name}}'
    stat -c '%a %U %n' .env
    docker exec app-db-1 psql -U app -d app -Atqc 'SELECT count(*) FROM visits'
    df -h /
} > "$EVIDENCE/final-container-state.log" 2>&1
docker history --no-trunc devops-app:1.0 > "$EVIDENCE/image-history-final.log"
python3 /home/devops/devops-course-2026/scripts/check-server-evidence.py \
    | tee "$EVIDENCE/secret-check.log"
printf 'Final container, port, data and evidence checks passed.\n'
