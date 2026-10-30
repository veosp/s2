#!/usr/bin/env bash
# Demonstrate volume deletion only in an isolated disposable Compose project.
set -euo pipefail
export LC_ALL=C
exec </dev/null
APP_DIR='/home/devops/app'
EVIDENCE='/home/devops/devops-course-2026/evidence/practice7'
cd "$APP_DIR"
main_created_before="$(docker volume inspect app_db_data --format '{{.CreatedAt}}')"
main_count_before="$(docker compose exec -T db psql -U app -d app -Atqc 'SELECT count(*) FROM visits')"
RESET_DIR="$(mktemp -d /home/devops/practice7-reset.XXXXXX)"
PROJECT="practice7-reset-${RANDOM}"
TEST_STARTED=false
compose() {
    docker compose --project-name "$PROJECT" --project-directory "$RESET_DIR" \
        -f "$RESET_DIR/docker-compose.yml" "$@"
}
cleanup() {
    local result=$?
    trap - EXIT INT TERM
    if [[ "$TEST_STARTED" == true ]]; then compose down --volumes --remove-orphans >/dev/null 2>&1 || true; fi
    rm -f -- "$RESET_DIR/.env" "$RESET_DIR/docker-compose.yml"
    rmdir -- "$RESET_DIR"
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
sed 's/127[.]0[.]0[.]1:5000:5000/127.0.0.1:5002:5000/' \
    "$APP_DIR/docker-compose.yml" > "$RESET_DIR/docker-compose.yml"
(
    umask 077
    database_password="$(openssl rand -hex 16)"
    printf 'POSTGRES_DB=app\nPOSTGRES_USER=app\nPOSTGRES_PASSWORD=%s\nDB_HOST=db\n' "$database_password" > "$RESET_DIR/.env"
)
{
    printf 'Isolated volume-deletion experiment: %s\n' "$(date -u +%FT%TZ)"
    printf 'Disposable project: %s; loopback port: 5002\n' "$PROJECT"
    printf 'Main project app/app_db_data is not deleted by this experiment.\n'
    TEST_STARTED=true
    compose up -d --no-build --wait --wait-timeout 120
    for unused in 1 2 3; do curl -fsS http://127.0.0.1:5002/; done
    printf '\nNormal down: preserve the disposable volume\n'
    compose down
    docker volume ls --filter "label=com.docker.compose.project=$PROJECT"
    compose up -d --no-build --wait --wait-timeout 120
    preserved="$(curl -fsS http://127.0.0.1:5002/ | sed -n 's/.*Visits: \([0-9][0-9]*\).*/\1/p')"
    printf 'After normal down/up: Visits=%s (expected 4)\n' "$preserved"
    [[ "$preserved" == 4 ]]
    printf '\nDestructive down -v: disposable project only\n'
    compose down --volumes
    compose up -d --no-build --wait --wait-timeout 120
    reset="$(curl -fsS http://127.0.0.1:5002/ | sed -n 's/.*Visits: \([0-9][0-9]*\).*/\1/p')"
    printf 'After down -v/up: Visits=%s (expected 1)\n' "$reset"
    [[ "$reset" == 1 ]]
    printf '\nMain-project preservation check\n'
    main_created_after="$(docker volume inspect app_db_data --format '{{.CreatedAt}}')"
    main_count_after="$(docker compose exec -T db psql -U app -d app -Atqc 'SELECT count(*) FROM visits')"
    [[ "$main_created_before" == "$main_created_after" ]]
    ((main_count_after >= main_count_before))
    printf 'Main counter before=%s; after=%s; volume identity unchanged.\n' "$main_count_before" "$main_count_after"
    printf 'Disposable containers, network and volume are removed by cleanup.\n'
} > "$EVIDENCE/volume-isolated.log" 2>&1
printf 'Isolated volume experiment passed; main app_db_data was preserved.\n'
