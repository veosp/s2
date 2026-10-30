#!/usr/bin/env bash
set -euo pipefail

fail() {
    printf 'Deployment failed: %s\n' "$*" >&2
    exit 1
}

DRY_RUN=false
case "$#:$*" in
    0:) ;;
    1:--dry-run) DRY_RUN=true ;;
    *) fail 'Usage: scripts/deploy.sh [--dry-run]' ;;
esac

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)" \
    || fail 'The script must belong to a Git working tree.'
LOCAL_DIR="${REPO_ROOT}/site/"
REMOTE='devops'
REMOTE_DIR='/var/www/devops-site/'
SITE_URL='https://devops.local/'
CA_CERT="${HOME}/devops.crt"

[[ -f "${LOCAL_DIR}index.html" ]] || fail 'site/index.html is missing; nothing was transferred.'
STATUS="$(git -C "$REPO_ROOT" status --porcelain=v1 --untracked-files=all)" \
    || fail 'Cannot inspect the Git working tree.'
if [[ -n "$STATUS" ]]; then
    printf '%s\n' "$STATUS" >&2
    fail 'Commit or otherwise resolve all working-tree and staged changes before deployment.'
fi
git -C "$REPO_ROOT" ls-files --error-unmatch -- site/index.html >/dev/null 2>&1 \
    || fail 'site/index.html must be tracked by Git.'
COMMIT="$(git -C "$REPO_ROOT" rev-parse --short HEAD)" \
    || fail 'The repository has no readable HEAD commit.'
if [[ "$DRY_RUN" == false && ! -r "$CA_CERT" ]]; then
    fail "Trusted certificate not found: $CA_CERT"
fi

RSYNC_OPTIONS=(-avz --delete --chmod=D755,F644)
if [[ "$DRY_RUN" == true ]]; then
    RSYNC_OPTIONS+=(--dry-run)
fi
SSH_COMMAND='ssh -o BatchMode=yes -o ConnectTimeout=5 -o ControlMaster=auto -o ControlPersist=60 -o ControlPath=~/.ssh/devops-%C'
printf 'Source: %s\nDestination: %s:%s\n' "$LOCAL_DIR" "$REMOTE" "$REMOTE_DIR"
if ! rsync "${RSYNC_OPTIONS[@]}" -e "$SSH_COMMAND" -- "$LOCAL_DIR" "${REMOTE}:${REMOTE_DIR}"; then
    fail 'rsync failed.'
fi
if [[ "$DRY_RUN" == true ]]; then
    printf 'Dry run complete; server content was not changed. Commit: %s\n' "$COMMIT"
    exit 0
fi
if ! curl -fsS --cacert "$CA_CERT" --connect-timeout 5 --max-time 15 \
        --output /dev/null "$SITE_URL"; then
    fail 'HTTPS verification failed after synchronization.'
fi
printf 'Deployment successful. Commit: %s\n' "$COMMIT"
