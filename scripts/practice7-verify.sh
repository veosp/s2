#!/usr/bin/env bash
# VM-only privileged integration checks with automatic restoration.
set -euo pipefail
export LC_ALL=C
exec </dev/null
((EUID == 0)) || { printf 'Run with sudo on the VM.\n' >&2; exit 1; }
COURSE='/home/devops/devops-course-2026'
APP_DIR='/home/devops/app'
EVIDENCE="$COURSE/evidence/practice7"
AUDIT="$COURSE/scripts/audit.sh"
CERT='/etc/ssl/certs/devops.crt'
NGINX_CONFIG='/etc/nginx/sites-available/devops-site'
BAD_COMPOSE=''
PORT_TEST_ACTIVE=false
APP_STOPPED=false
mkdir -p "$EVIDENCE"
compose() { docker compose --project-name app --project-directory "$APP_DIR" -f "$APP_DIR/docker-compose.yml" "$@"; }
cleanup() {
    local result=$?
    trap - EXIT INT TERM
    if [[ "$PORT_TEST_ACTIVE" == true || "$APP_STOPPED" == true ]]; then
        compose up -d --no-build --wait --wait-timeout 120 >/dev/null 2>&1 || true
    fi
    [[ -z "$BAD_COMPOSE" ]] || rm -f -- "$BAD_COMPOSE"
    chmod 600 "$APP_DIR/.env"
    chown devops:devops "$APP_DIR/.env"
    chown -R devops:devops "$EVIDENCE"
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ ! -e "${NGINX_CONFIG}.pre-practice7" ]]; then cp -p "$NGINX_CONFIG" "${NGINX_CONFIG}.pre-practice7"; fi
install -m 644 "$COURSE/config/nginx/devops-site" "$NGINX_CONFIG"
if ! nginx -t; then
    cp -p "${NGINX_CONFIG}.pre-practice7" "$NGINX_CONFIG"
    nginx -t && systemctl reload nginx
    exit 1
fi
systemctl reload nginx
proxy_ready=false
for attempt in $(seq 1 20); do
    if curl -fsS --cacert "$CERT" --resolve devops.local:443:127.0.0.1 \
            --connect-timeout 2 --max-time 4 https://devops.local/app/health >/dev/null 2>&1; then
        proxy_ready=true
        break
    fi
    sleep 0.3
done
[[ "$proxy_ready" == true ]]

{
    printf 'Reverse proxy checks: %s\n' "$(date -u +%FT%TZ)"
    nginx -t
    cat "$NGINX_CONFIG"
    printf '\nApplication through HTTPS\n'
    curl -fsS --cacert "$CERT" --resolve devops.local:443:127.0.0.1 https://devops.local/app/
    curl -fsS --cacert "$CERT" --resolve devops.local:443:127.0.0.1 https://devops.local/app/health
    curl -fsSI --cacert "$CERT" --resolve devops.local:443:127.0.0.1 https://devops.local/
    printf '\nApp is non-root and its code is read-only\n'
    compose exec -T app id
    [[ "$(compose exec -T app id -u)" != 0 ]]
    compose exec -T app sh -c 'test ! -w /app/app.py && test ! -e /app/.env'
    printf 'Image contains no /app/.env and its user cannot modify app.py.\n'
    printf '\nActual upstream outage\n'
    compose stop app
    APP_STOPPED=true
    status="$(curl -sS --cacert "$CERT" --resolve devops.local:443:127.0.0.1 \
        --connect-timeout 3 --max-time 8 -o "$EVIDENCE/proxy-502-body.html" -w '%{http_code}' https://devops.local/app/)"
    printf 'Application stopped: HTTPS /app/ returned %s (expected 502).\n' "$status"
    [[ "$status" == 502 ]]
    tail -n 3 /var/log/nginx/devops-site.error.log
    compose up -d --no-build --wait --wait-timeout 120
    APP_STOPPED=false
    curl -fsS --cacert "$CERT" --resolve devops.local:443:127.0.0.1 https://devops.local/app/health
} > "$EVIDENCE/proxy.log" 2>&1

{
    printf 'Baseline container audit\n'
    bash "$AUDIT"
    printf 'Exit code: 0\n'
    printf '\nTemporarily publish app on all VM addresses\n'
    BAD_COMPOSE="$(mktemp "$APP_DIR/.ports-test.XXXXXX.yml")"
    sed 's/127[.]0[.]0[.]1:5000:5000/5000:5000/' "$APP_DIR/docker-compose.yml" > "$BAD_COMPOSE"
    PORT_TEST_ACTIVE=true
    docker compose --project-name app --project-directory "$APP_DIR" -f "$BAD_COMPOSE" \
        up -d --no-build --wait --wait-timeout 120
    ss -tlnp | grep -E ':(5000|5432)\b'
    set +e
    bash "$AUDIT"
    audit_status=$?
    set -e
    printf 'Public-port audit exit code: %s (expected 1).\n' "$audit_status"
    [[ "$audit_status" -eq 1 ]]
    compose up -d --no-build --wait --wait-timeout 120
    PORT_TEST_ACTIVE=false
    rm -f -- "$BAD_COMPOSE"
    BAD_COMPOSE=''
    printf '\nRestored private-port configuration\n'
    ss -tlnp | grep -E ':(5000|5432)\b'
    bash "$AUDIT"
    printf 'Exit code: 0\n'
    printf '\nServer environment metadata\n'
    stat -c '%a %U %n' "$APP_DIR/.env"
    printf '\nFinal services\n'
    compose ps
    systemctl is-active docker nginx
} > "$EVIDENCE/container-audit.log" 2>&1
printf 'Privileged practice 7 checks passed; proxy and private ports restored.\n'
