#!/usr/bin/env bash
# Install the official Docker Engine and Compose plugin on the classroom VM.
set -euo pipefail
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

((EUID == 0)) || { printf 'Run with sudo on the Ubuntu VM.\n' >&2; exit 1; }
[[ "$(hostname -s)" == devops-vm ]] || { printf 'Unexpected target host.\n' >&2; exit 1; }
. /etc/os-release
[[ "$ID" == ubuntu && "$VERSION_ID" == 26.04 ]] \
    || { printf 'This installation was reviewed for Ubuntu 26.04.\n' >&2; exit 1; }
id devops >/dev/null

LOG_DIR='/home/devops/devops-course-2026/evidence/practice7'
mkdir -p "$LOG_DIR"
trap 'result=$?; chown -R devops:devops "$LOG_DIR"; exit "$result"' EXIT
exec > >(tee "${LOG_DIR}/docker-install.log") 2>&1
printf 'Official Docker Engine installation: %s\n' "$(date -u +%FT%TZ)"
printf 'Target: %s; Ubuntu %s; architecture %s\n' "$(hostname -f)" "$VERSION_ID" "$(dpkg --print-architecture)"

for package in docker.io docker-compose docker-compose-v2 docker-doc docker-buildx podman-docker containerd runc; do
    if dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -qx 'install ok installed'; then
        printf 'Conflicting package needs review before installation: %s\n' "$package" >&2
        exit 1
    fi
done

APT_OPTIONS=(-o Acquire::Retries=2 -o Acquire::http::Timeout=20 \
    -o Acquire::https::Timeout=20 -o Acquire::ForceIPv4=true)
apt-get "${APT_OPTIONS[@]}" update
apt-get "${APT_OPTIONS[@]}" install -y ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL --retry 2 --connect-timeout 10 --max-time 60 \
    https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod 0644 /etc/apt/keyrings/docker.asc
cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${UBUNTU_CODENAME:-$VERSION_CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
apt-get "${APT_OPTIONS[@]}" update
apt-get "${APT_OPTIONS[@]}" install -y --no-install-recommends \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now containerd.service docker.service
usermod -aG docker devops

printf '\nInstalled package origin\n'
apt-cache policy docker-ce
printf '\nDocker Engine\n'
docker version
printf '\nCompose\n'
docker compose version
printf '\nServices\n'
systemctl is-active docker containerd nginx
printf '\nDocker group\n'
getent group docker
printf '\nRemaining disk space\n'
df -h /
printf '\nInstallation complete. Verify hello-world in a new devops SSH connection.\n'
