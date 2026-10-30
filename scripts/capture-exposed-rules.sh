#!/usr/bin/env bash
set -euo pipefail
((EUID == 0)) || exit 1
LOG='/home/devops/devops-course-2026/evidence/practice7/exposed-rules.log'
{
    printf 'Temporary all-interface port publication: %s\n' "$(date -u +%FT%TZ)"
    docker ps --filter name=exposed
    printf '\nUFW rule for 5001 (expected absent):\n'
    if ufw status | grep 5001; then printf 'Unexpected explicit UFW rule.\n' >&2; exit 1; else printf 'No UFW allow rule for 5001.\n'; fi
    printf '\nDocker NAT rule for 5001:\n'
    iptables -t nat -L DOCKER -n | grep 5001
    printf '\nPublished listeners:\n'
    ss -tlnp | grep ':5001'
} > "$LOG" 2>&1
chown devops:devops "$LOG"
cat "$LOG"
