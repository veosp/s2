#!/usr/bin/env bash
# Offline contract tests. No commits, network calls, or server changes are made.
set -euo pipefail

TEST_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCE_SCRIPT="${TEST_SCRIPT_DIR}/../scripts/deploy.sh"
TEST_DIR="$(mktemp -d /tmp/practice6-deploy-tests.XXXXXX)"
cleanup() {
    case "$TEST_DIR" in /tmp/practice6-deploy-tests.*) rm -rf -- "$TEST_DIR" ;; esac
}
trap cleanup EXIT
export P6_TEST_REPO="${TEST_DIR}/repo"
export P6_TEST_CALLS="${TEST_DIR}/calls"
mkdir -p "${P6_TEST_REPO}/scripts" "${P6_TEST_REPO}/site" "${TEST_DIR}/bin" \
    "${TEST_DIR}/home" "${TEST_DIR}/elsewhere" "$P6_TEST_CALLS"
cp "$SOURCE_SCRIPT" "${P6_TEST_REPO}/scripts/deploy.sh"
printf '<h1>Fixture</h1>\n' > "${P6_TEST_REPO}/site/index.html"
printf 'Fixture certificate\n' > "${TEST_DIR}/home/devops.crt"

cat > "${TEST_DIR}/bin/git" <<'MOCK'
#!/usr/bin/env bash
set -eu
if [[ "${1:-}" == '-C' ]]; then shift 2; fi
case "${1:-}:${2:-}" in
    rev-parse:--show-toplevel) printf '%s\n' "$P6_TEST_REPO" ;;
    rev-parse:--short) printf 'abc1234\n' ;;
    status:--porcelain=v1) printf '%s' "${P6_TEST_STATUS:-}" ;;
    ls-files:--error-unmatch) exit "${P6_TEST_TRACKED_EXIT:-0}" ;;
    *) printf 'Unexpected Git command in test: %s\n' "$*" >&2; exit 91 ;;
esac
MOCK
cat > "${TEST_DIR}/bin/rsync" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "${P6_TEST_CALLS}/rsync"
printf 'Mock rsync executed.\n'
exit "${P6_TEST_RSYNC_EXIT:-0}"
MOCK
cat > "${TEST_DIR}/bin/curl" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "${P6_TEST_CALLS}/curl"
exit "${P6_TEST_CURL_EXIT:-0}"
MOCK
chmod +x "${TEST_DIR}/bin/"*
export PATH="${TEST_DIR}/bin:${PATH}"
export HOME="${TEST_DIR}/home"
cd "${TEST_DIR}/elsewhere"
PASSED=0

run_case() {
    local name="$1" expected="$2" actual
    shift 2
    rm -f "${P6_TEST_CALLS}/rsync" "${P6_TEST_CALLS}/curl"
    set +e
    "$@" > "${TEST_DIR}/output" 2>&1
    actual=$?
    set -e
    if [[ "$actual" -ne "$expected" ]]; then
        cat "${TEST_DIR}/output"
        printf '[FAIL] %s: expected exit %s, got %s\n' "$name" "$expected" "$actual" >&2
        exit 1
    fi
    PASSED=$((PASSED + 1))
    printf '[OK] %s: exit %s\n' "$name" "$actual"
}
assert_no_transfer() {
    [[ ! -e "${P6_TEST_CALLS}/rsync" && ! -e "${P6_TEST_CALLS}/curl" ]]
}
DEPLOY="${P6_TEST_REPO}/scripts/deploy.sh"
printf 'Offline contract tests: Git, rsync and curl are mocked. No commits are created.\n'
run_case 'Dry run from another directory' 0 bash "$DEPLOY" --dry-run
grep -Fx -- '--dry-run' "${P6_TEST_CALLS}/rsync" >/dev/null
grep -F -- 'BatchMode=yes' "${P6_TEST_CALLS}/rsync" >/dev/null
[[ ! -e "${P6_TEST_CALLS}/curl" ]]
run_case 'Clean Git state and successful HTTPS check' 0 bash "$DEPLOY"
grep -F 'Commit: abc1234' "${TEST_DIR}/output" >/dev/null
grep -Fx -- '--cacert' "${P6_TEST_CALLS}/curl" >/dev/null
grep -Fx -- '--chmod=D755,F644' "${P6_TEST_CALLS}/rsync" >/dev/null
grep -Fx -- '--delete' "${P6_TEST_CALLS}/rsync" >/dev/null
[[ "$(grep -Fxc -- '-e' "${P6_TEST_CALLS}/rsync")" -eq 1 ]]
run_case 'Unstaged change rejected before synchronization' 1 env P6_TEST_STATUS=' M site/index.html' bash "$DEPLOY"
assert_no_transfer
run_case 'Staged change rejected before synchronization' 1 env P6_TEST_STATUS='M  site/index.html' bash "$DEPLOY"
assert_no_transfer
run_case 'Untracked file rejected before synchronization' 1 env P6_TEST_STATUS='?? new-file' bash "$DEPLOY"
assert_no_transfer
run_case 'HTTPS failure after synchronization' 1 env P6_TEST_CURL_EXIT=7 bash "$DEPLOY"
[[ -e "${P6_TEST_CALLS}/rsync" && -e "${P6_TEST_CALLS}/curl" ]]
run_case 'rsync failure stops deployment' 1 env P6_TEST_RSYNC_EXIT=12 bash "$DEPLOY"
[[ ! -e "${P6_TEST_CALLS}/curl" ]]
mv "${P6_TEST_REPO}/site/index.html" "${P6_TEST_REPO}/site/index.saved"
run_case 'Missing index rejected before synchronization' 1 bash "$DEPLOY"
assert_no_transfer
mv "${P6_TEST_REPO}/site/index.saved" "${P6_TEST_REPO}/site/index.html"
run_case 'Invalid argument rejected' 1 bash "$DEPLOY" --unknown
assert_no_transfer
run_case 'Ignored or untracked index cannot be certified as a commit' 1 env P6_TEST_TRACKED_EXIT=1 bash "$DEPLOY"
assert_no_transfer
rm "${HOME}/devops.crt"
run_case 'Missing trusted certificate blocks real deployment' 1 bash "$DEPLOY"
assert_no_transfer
run_case 'Dry run does not require a certificate or HTTPS check' 0 bash "$DEPLOY" --dry-run
[[ ! -e "${P6_TEST_CALLS}/curl" ]]
printf 'Passed: %s; failed: 0\n' "$PASSED"
