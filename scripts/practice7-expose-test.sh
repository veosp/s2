#!/usr/bin/env bash
# Temporary port-5001 demonstration; a watchdog stops only this test container.
set -euo pipefail
EVIDENCE='/home/devops/devops-course-2026/evidence/practice7'
ID_FILE="$EVIDENCE/exposed-container.id"
case "${1:-}" in
    start)
        if docker container inspect exposed >/dev/null 2>&1; then
            printf 'An exposed container already exists; refusing to replace it.\n' >&2
            exit 1
        fi
        container_id="$(docker run -d --rm --name exposed --label classroom.practice=7 -p 5001:5000 devops-app:1.0)"
        printf '%s\n' "$container_id" > "$ID_FILE"
        nohup sh -c 'sleep 90; docker stop "$1" >/dev/null 2>&1 || true' sh "$container_id" >/dev/null 2>&1 </dev/null &
        ready=false
        for attempt in $(seq 1 30); do
            if curl -fsS --connect-timeout 2 --max-time 3 http://127.0.0.1:5001/health >/dev/null 2>&1; then ready=true; break; fi
            sleep 1
        done
        [[ "$ready" == true ]]
        printf 'Temporary exposure started: %s\n' "$container_id"
        docker port "$container_id"
        ;;
    stop)
        if [[ -f "$ID_FILE" ]]; then
            container_id="$(cat "$ID_FILE")"
            [[ "$container_id" =~ ^[0-9a-f]{64}$ ]]
            if docker container inspect "$container_id" >/dev/null 2>&1; then docker stop "$container_id"; fi
        fi
        printf 'Temporary exposure stopped.\n'
        ;;
    *) printf 'Usage: %s start|stop\n' "$0" >&2; exit 1 ;;
esac
