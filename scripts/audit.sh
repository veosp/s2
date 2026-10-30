#!/usr/bin/env bash
set -uo pipefail
export LC_ALL=C

PASS=0
FAIL=0
SITE_DIR='/var/www/devops-site'
CERT_FILE='/etc/ssl/certs/devops.crt'
KEY_FILE='/etc/ssl/private/devops.key'
CERT_MIN_DAYS="${CERT_MIN_DAYS:-30}"

check() {
    local description="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        printf '[OK]   %s\n' "$description"
        PASS=$((PASS + 1))
    else
        printf '[FAIL] %s: expected %s, got %s\n' "$description" "$expected" "$actual"
        FAIL=$((FAIL + 1))
    fi
}

if [[ ! "$CERT_MIN_DAYS" =~ ^[0-9]+$ ]] || ((CERT_MIN_DAYS > 36500)); then
    printf 'CERT_MIN_DAYS must be an integer between 0 and 36500.\n' >&2
    exit 1
fi
if ((EUID != 0)); then
    sudo -v || exit 1
fi
root_command() {
    if ((EUID == 0)); then
        "$@"
    else
        sudo -n "$@"
    fi
}
if ! SSH_CONFIG="$(root_command /usr/sbin/sshd -T)"; then
    printf 'Cannot read the effective SSH configuration.\n' >&2
    exit 1
fi
if ! UFW_STATUS="$(root_command ufw status verbose)"; then
    printf 'Cannot read the firewall configuration.\n' >&2
    exit 1
fi

printf 'Configuration audit: %s\n' "$(hostname -f)"
printf '[1] SSH\n'
check 'Root SSH login disabled' no "$(awk '/^permitrootlogin / {print $2}' <<< "$SSH_CONFIG")"
check 'Password authentication disabled' no "$(awk '/^passwordauthentication / {print $2}' <<< "$SSH_CONFIG")"
check 'SSH port differs from 22' yes "$(awk '/^port / {print ($2 != 22 ? "yes" : "no")}' <<< "$SSH_CONFIG")"
check 'MaxAuthTries equals 3' 3 "$(awk '/^maxauthtries / {print $2}' <<< "$SSH_CONFIG")"
printf '[2] Firewall\n'
check 'UFW is active' active "$(awk '/^Status:/ {print $2}' <<< "$UFW_STATUS")"
check 'Default incoming policy is deny' deny "$(awk '/^Default:/ {print $2}' <<< "$UFW_STATUS")"
printf '[3] User accounts\n'
awk -F: '$3 >= 1000 && $3 < 65534 {printf "    %s (uid=%s)\n", $1, $3}' /etc/passwd
printf '[4] Web server\n'
check 'Nginx is active' active "$(systemctl is-active nginx 2>/dev/null)"
root_command nginx -t >/dev/null 2>&1
check 'Nginx configuration is valid' 0 "$?"
openssl x509 -in "$CERT_FILE" -checkend "$((CERT_MIN_DAYS * 86400))" -noout >/dev/null 2>&1
check "Certificate remains valid for at least ${CERT_MIN_DAYS} days" 0 "$?"
CONTENT_STATE='unsafe'
if WORLD_WRITABLE="$(root_command find "$SITE_DIR" -perm -0002 -print)" \
        && KEY_STATE="$(root_command stat -c '%a:%U' "$KEY_FILE")" \
        && [[ -z "$WORLD_WRITABLE" && "$KEY_STATE" == '600:root' ]]; then
    CONTENT_STATE='safe'
fi
check 'No world-writable content; TLS key is root-owned with mode 600' safe "$CONTENT_STATE"
printf '[5] Containers\n'
APP_DIR='/home/devops/app'
check 'Docker service is active' active "$(systemctl is-active docker 2>/dev/null)"
DB_CONTAINER="$(root_command docker compose -f "$APP_DIR/docker-compose.yml" ps -q db 2>/dev/null)"
APP_CONTAINER="$(root_command docker compose -f "$APP_DIR/docker-compose.yml" ps -q app 2>/dev/null)"
DB_HEALTH='missing'
if [[ -n "$DB_CONTAINER" ]]; then
    DB_HEALTH="$(root_command docker inspect --format '{{.State.Health.Status}}' "$DB_CONTAINER" 2>/dev/null)"
fi
check 'PostgreSQL container is healthy' healthy "$DB_HEALTH"
PORT_STATE='unsafe'
UNEXPECTED_LISTENERS="$(ss -H -tln | awk '$4 ~ /:(5000|5432)$/ && $4 !~ /^127[.]0[.]0[.]1:/ {print $4}')"
APP_BINDINGS=''
DB_BINDINGS=''
if [[ -n "$APP_CONTAINER" && -n "$DB_CONTAINER" ]]; then
    APP_BINDINGS="$(root_command docker port "$APP_CONTAINER" 5000/tcp 2>/dev/null)"
    DB_BINDINGS="$(root_command docker port "$DB_CONTAINER" 2>/dev/null)"
    if [[ -z "$UNEXPECTED_LISTENERS" && "$APP_BINDINGS" == '127.0.0.1:5000' && -z "$DB_BINDINGS" ]]; then
        PORT_STATE='safe'
    fi
fi
check 'App is loopback-only and database ports are unpublished' safe "$PORT_STATE"
check 'Server .env is devops-owned with mode 600' '600:devops' \
    "$(root_command stat -c '%a:%U' "$APP_DIR/.env" 2>/dev/null)"
printf 'Passed: %s; failed: %s\n' "$PASS" "$FAIL"
((FAIL == 0))
