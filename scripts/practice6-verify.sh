#!/usr/bin/env bash
# Run once on the VM with sudo. All deliberate failures are restored on exit.
set -euo pipefail
export LC_ALL=C

((EUID == 0)) || { printf 'Run with sudo on the VM.\n' >&2; exit 1; }
COURSE='/home/devops/devops-course-2026'
SITE='/var/www/devops-site'
INDEX="${SITE}/index.html"
CERT='/etc/ssl/certs/devops.crt'
KEY='/etc/ssl/private/devops.key'
AUDIT="${COURSE}/scripts/audit.sh"
EVIDENCE="${COURSE}/evidence/practice6"
[[ -f "$INDEX" && -f "$AUDIT" && -f "$CERT" && -f "$KEY" ]] \
    || { printf 'Required practice files are missing.\n' >&2; exit 1; }
mkdir -p "$EVIDENCE"
BACKUP="$(mktemp "${EVIDENCE}/index.backup.XXXXXX")"
cp -p -- "$INDEX" "$BACKUP"
NGINX_STOPPED=false
cleanup() {
    local result=$?
    trap - EXIT INT TERM
    chmod 755 "$SITE"
    cp -p -- "$BACKUP" "$INDEX"
    chown devops:devops "$INDEX"
    chmod 644 "$INDEX"
    chown root:root "$KEY" "$CERT"
    chmod 600 "$KEY"
    chmod 644 "$CERT"
    if [[ "$NGINX_STOPPED" == true ]]; then systemctl start nginx; fi
    rm -f -- "$BACKUP"
    chown -R devops:devops "$EVIDENCE"
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
chown root:root "$KEY" "$CERT"
chmod 600 "$KEY"
chmod 644 "$CERT"
chmod 755 "$SITE"
chmod 644 "$INDEX"

http_code() {
    curl -sS --cacert "$CERT" --resolve devops.local:443:127.0.0.1 \
        --connect-timeout 3 --max-time 6 -o /dev/null -w '%{http_code}' \
        "https://devops.local${1:-/}"
}
expect_code() {
    local expected="$1" actual
    actual="$(http_code)"
    printf 'HTTPS status: %s (expected %s)\n' "$actual" "$expected"
    [[ "$actual" == "$expected" ]]
}

{
    printf 'Server verification: %s\n' "$(date -u +%FT%TZ)"
    nginx -t
    systemctl is-active nginx
    ss -tlnp | grep nginx
    ps -o user,pid,ppid,cmd -C nginx
    ls -l /etc/nginx/sites-enabled/
    cat /etc/nginx/sites-available/devops-site
    ufw status verbose
    namei -l "$INDEX"
    ls -l "$KEY" "$CERT"
    openssl x509 -in "$CERT" -noout -subject -issuer -dates -ext subjectAltName
    sudo -u www-data test -r "$CERT" && printf 'Certificate is readable by www-data.\n'
    if sudo -u www-data test -r "$KEY"; then
        printf 'ERROR: private key is readable by www-data.\n'; exit 1
    else
        printf 'Private key is not readable by www-data.\n'
    fi
    curl -sSI --resolve devops.local:80:127.0.0.1 http://devops.local/
    expect_code 200
} > "${EVIDENCE}/server-checks.log" 2>&1

{
    printf 'Permission experiments: %s\n' "$(date -u +%FT%TZ)"
    ls -la "$SITE/"
    printf '\nFile mode 600\n'
    chmod 600 "$INDEX"
    expect_code 403
    if sudo -u www-data cat "$INDEX"; then exit 1; else printf 'Read refusal is expected.\n'; fi
    tail -n 3 /var/log/nginx/devops-site.error.log
    chmod 644 "$INDEX"
    printf '\nDirectory mode | others | HTTPS status\n'
    for row in '755 r-x 200' '750 --- 403' '744 r-- 403' '711 --x 200'; do
        read -r mode rights expected <<< "$row"
        chmod "$mode" "$SITE"
        printf '%s | %s | ' "$mode" "$rights"
        expect_code "$expected"
    done
    printf '\nError-log records for file and directory permission failures\n'
    tail -n 6 /var/log/nginx/devops-site.error.log
    printf '\nDirectory 711: list denied, file read allowed\n'
    if sudo -u www-data ls "$SITE"; then exit 1; else printf 'Directory listing refusal is expected.\n'; fi
    sudo -u www-data cat "$INDEX"
    chmod 755 "$SITE"
    printf '\nUnsafe mode 666 and content replacement by www-data\n'
    chmod 666 "$INDEX"
    find "$SITE" -perm -0002 -print
    sudo -u www-data sh -c 'printf "<h1>defaced</h1>\n" > "$1"' sh "$INDEX"
    curl -sS --cacert "$CERT" --resolve devops.local:443:127.0.0.1 https://devops.local/
    printf '\nRestore from the host-provided source with the deployment permission policy\n'
    sudo -u devops rsync -av --delete --chmod=D755,F644 "${COURSE}/site/" "$SITE/"
    find "$SITE" -perm -0002 -print
    if sudo -u www-data touch "$INDEX"; then exit 1; else printf 'Write refusal after restoration is expected.\n'; fi
    expect_code 200
    printf '\nActual Nginx outage and recovery\n'
    systemctl stop nginx
    NGINX_STOPPED=true
    set +e
    curl -fsS --cacert "$CERT" --resolve devops.local:443:127.0.0.1 \
        --connect-timeout 3 --max-time 5 https://devops.local/ -o /dev/null
    outage_status=$?
    set -e
    printf 'HTTPS command exit code while Nginx is stopped: %s (expected nonzero)\n' "$outage_status"
    [[ "$outage_status" -ne 0 ]]
    systemctl start nginx
    NGINX_STOPPED=false
    expect_code 200
} > "${EVIDENCE}/permissions.log" 2>&1

{
    printf 'Baseline audit\n'
    bash "$AUDIT"
    printf 'Exit code: 0\n\nCertificate threshold intentionally exceeds certificate lifetime\n'
    set +e
    CERT_MIN_DAYS=400 bash "$AUDIT"
    expiry_status=$?
    set -e
    printf 'Exit code: %s (expected 1)\n' "$expiry_status"
    [[ "$expiry_status" -eq 1 ]]
    printf '\nWorld-writable content intentionally introduced\n'
    chmod 666 "$INDEX"
    set +e
    bash "$AUDIT"
    permissions_status=$?
    set -e
    chmod 644 "$INDEX"
    printf 'Exit code: %s (expected 1)\n' "$permissions_status"
    [[ "$permissions_status" -eq 1 ]]
    printf '\nFinal restored audit\n'
    bash "$AUDIT"
    printf 'Exit code: 0\n'
} > "${EVIDENCE}/audit.log" 2>&1

{
    printf 'HTTP and access-log analysis: %s\n' "$(date -u +%FT%TZ)"
    curl -v --cacert "$CERT" --resolve devops.local:443:127.0.0.1 https://devops.local/
    for unused in 1 2 3; do http_code; printf '\n'; done
    for path in /admin /wp-login.php /.env; do http_code "$path"; printf '\n'; done
    curl -sS --resolve devops.local:80:127.0.0.1 -o /dev/null -w '%{http_code}\n' http://devops.local/
    printf '\nRecent access records\n'
    tail -n 10 /var/log/nginx/devops-site.access.log
    printf '\nResponse-code distribution\n'
    awk '{print $9}' /var/log/nginx/devops-site.access.log | sort | uniq -c | sort -rn
} > "${EVIDENCE}/http-log-analysis.log" 2>&1
printf 'All privileged checks passed. Evidence: %s\n' "$EVIDENCE"
