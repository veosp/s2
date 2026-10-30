#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
exec </dev/null
APP_DIR='/home/devops/app'
EVIDENCE='/home/devops/devops-course-2026/evidence/practice7'
mkdir -p "$EVIDENCE"
cd "$APP_DIR"
[[ "$(id -un)" == devops ]] || { printf 'Run as devops on the VM.\n' >&2; exit 1; }

wait_for_health() {
    for attempt in $(seq 1 40); do
        if curl -fsS --connect-timeout 2 --max-time 3 http://127.0.0.1:5000/health >/dev/null; then return 0; fi
        sleep 1
    done
    printf 'Application did not become ready.\n' >&2
    return 1
}

case "${1:-}" in
    initial)
        docker build --progress=plain -t devops-app:1.0 . 2>&1 | tee "$EVIDENCE/build-initial.log"
        docker history --no-trunc devops-app:1.0 > "$EVIDENCE/image-history.log"
        if docker container inspect app-test >/dev/null 2>&1; then
            printf 'An app-test container already exists; refusing to replace it.\n' >&2
            exit 1
        fi
        test_container=''
        cleanup() { if [[ -n "$test_container" ]]; then docker rm -f "$test_container" >/dev/null; fi; }
        trap cleanup EXIT
        test_container="$(docker run -d --name app-test -p 127.0.0.1:5000:5000 devops-app:1.0)"
        {
            printf 'Standalone application, without a database: %s\n' "$(date -u +%FT%TZ)"
            wait_for_health
            docker ps --filter name=app-test
            curl -sSi http://127.0.0.1:5000/health
            status="$(curl -sS -o "$EVIDENCE/standalone-error-body.html" -w '%{http_code}' http://127.0.0.1:5000/)"
            printf 'Main endpoint without DB: HTTP %s (expected 500)\n' "$status"
            [[ "$status" == 500 ]]
            docker logs app-test
            docker exec app-test id
            [[ "$(docker exec app-test id -u)" != 0 ]]
            docker exec app-test sh -c 'test ! -w /app/app.py'
            printf 'Application source is read-only to the container user.\n'
        } 2>&1 | tee "$EVIDENCE/standalone.log"
        docker rm -f "$test_container" | tee -a "$EVIDENCE/standalone.log"
        test_container=''
        ;;
    compose)
        docker build --progress=plain -t devops-app:1.0 . 2>&1 | tee "$EVIDENCE/build-cached.log"
        if [[ ! -f .env ]]; then
            (
                umask 077
                database_password="$(openssl rand -hex 16)"
                printf 'POSTGRES_DB=app\nPOSTGRES_USER=app\nPOSTGRES_PASSWORD=%s\nDB_HOST=db\n' "$database_password" > .env
            )
        fi
        chmod 600 .env
        docker compose config --quiet
        {
            printf 'Compose startup: %s\n' "$(date -u +%FT%TZ)"
            stat -c '%a %U %n' .env
            docker compose up -d --no-build --wait --wait-timeout 120
            docker compose ps
            for unused in 1 2 3; do curl -fsS http://127.0.0.1:5000/; done
            docker compose exec -T app id
            docker compose exec -T app getent hosts db
            docker network ls
            docker port app-app-1
            printf 'DB published ports (expected empty):\n'
            docker port app-db-1
            ss -tln | grep -E ':(5000|5432)\b'
            [[ "$(docker port app-app-1 5000/tcp)" == '127.0.0.1:5000' ]]
            [[ -z "$(docker port app-db-1)" ]]
            before="$(curl -fsS http://127.0.0.1:5000/ | sed -n 's/.*Visits: \([0-9][0-9]*\).*/\1/p')"
            printf '\nBefore compose down: Visits=%s\n' "$before"
            docker compose down
            docker volume inspect app_db_data --format '{{.Name}}'
            docker compose up -d --no-build --wait --wait-timeout 120
            after="$(curl -fsS http://127.0.0.1:5000/ | sed -n 's/.*Visits: \([0-9][0-9]*\).*/\1/p')"
            printf 'After compose down/up: Visits=%s\n' "$after"
            ((after > before))
            printf 'The main app_db_data volume and counter survived container recreation.\n'
        } 2>&1 | tee "$EVIDENCE/compose.log"
        ;;
    *) printf 'Usage: %s initial|compose\n' "$0" >&2; exit 1 ;;
esac
