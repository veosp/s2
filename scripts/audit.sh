#!/usr/bin/env bash
set -uo pipefail

PASS=0
FAIL=0

check() {
    local description="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "[OK] $description"
        ((PASS++))
    else
        echo "[FAIL] $description: expected '$expected', got '$actual'"
        ((FAIL++))
    fi
}

echo "Configuration audit: $(hostname -f)"

check "Root SSH login disabled" "no" \
    "$(sudo sshd -T | awk '/^permitrootlogin / {print $2}')"

check "Password authentication disabled" "no" \
    "$(sudo sshd -T | awk '/^passwordauthentication / {print $2}')"

check "SSH port differs from 22" "yes" \
    "$(sudo sshd -T | awk '/^port / {print ($2 != 22 ? "yes" : "no")}')"

check "MaxAuthTries equals 3" "3" \
    "$(sudo sshd -T | awk '/^maxauthtries / {print $2}')"

check "UFW is active" "active" \
    "$(sudo ufw status | awk '/^Status:/ {print $2}')"

check "Default incoming policy is deny" "deny" \
    "$(sudo ufw status verbose | awk '/^Default:/ {print $2}')"

echo "User accounts:"
awk -F: '$3>=1000 && $3<65534 {printf "%s (uid=%s)\n", $1, $3}' /etc/passwd

echo "Passed: $PASS; failed: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
