# Server setup: devops-vm

## 1. Machine parameters

- VirtualBox VM name: ubuntu-server.
- Operating system: Ubuntu Server 26.04.1 LTS.
- CPU: 2 virtual cores.
- Configured RAM: 4096 MiB.
- Memory reported by Linux: 3.3 GiB.
- Swap: 2 GiB.
- Virtual disk: 25 GiB.
- Root filesystem: 11.5 GiB, ext4 on LVM.
- Boot partition: 2 GiB.

## 2. Network interfaces and hostnames

| Interface | Mode | Address | Purpose |
|---|---|---|---|
| enp0s3 | NAT | 10.0.2.15/24 | Internet access |
| enp0s8 | Host-only | 192.168.56.101/24 | Communication with Windows |

Windows Host-only adapter: Ethernet 2, 192.168.56.1/24.

Windows file: C:\Windows\System32\drivers\etc\hosts

```text
192.168.56.101 devops.local
```

Ubuntu hostname:

```bash
sudo hostnamectl set-hostname devops-vm
```

Ubuntu /etc/hosts entry:

```text
127.0.1.1 devops-vm.devops.local devops-vm
```

Verification: `ip -brief address` and `hostname -f`.

VPN routing previously interfered with Host-only access.
The successful SSH connection by hostname was tested with VPN disabled.

## 3. Port forwarding

Adapter 1, NAT, TCP:

- Host address: 127.0.0.1.
- Host port: 2222.
- Guest address: unspecified.
- Guest port: 2222.

Before SSH hardening, the guest port was 22.

## 4. User accounts and authentication

- q: initial local account with sudo access.
- devops: administration account with sudo and SSH access.
- Only devops is permitted to log in through SSH.

Account setup, if required after restoring the baseline:

```bash
id devops || sudo adduser devops
sudo usermod -aG sudo devops
```

Windows private key: C:\Users\Q\.ssh\devops_vm
Windows public key: C:\Users\Q\.ssh\devops_vm.pub

The public key is installed in /home/devops/.ssh/authorized_keys.
Directory permissions: 700. File permissions: 600.

Before disabling password authentication, install the public key
from Git Bash on Windows:

```bash
ssh-copy-id -i ~/.ssh/devops_vm.pub -p 2222 devops@127.0.0.1
```

Windows SSH configuration, C:\Users\Q\.ssh\config:

```sshconfig
Host devops
    HostName 127.0.0.1
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes
```

## 5. SSH service

Original configuration backup: /etc/ssh/sshd_config.backup

Hardening file: /etc/ssh/sshd_config.d/99-hardening.conf

```text
Port 2222
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
AllowUsers devops
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
```

In /etc/ssh/sshd_config.d/50-cloud-init.conf, the conflicting
PasswordAuthentication yes directive is commented out.
The first encountered value takes precedence.

Validate and apply:

```bash
sudo sshd -t
sudo sshd -T
sudo systemctl disable --now ssh.socket
sudo systemctl enable --now ssh.service
sudo systemctl restart ssh
sudo ss -tlnp | grep sshd
```

Keep the existing SSH session open until a new connection succeeds.

After changing the server port, update the NAT guest port to 2222.

Connection tests from Windows:

```bash
ssh devops
ssh -i ~/.ssh/devops_vm -p 2222 devops@devops.local
```

## 6. Firewall

Default policies: deny incoming, allow outgoing.

Rules:
- TCP 2222: LIMIT for SSH.
- TCP 80: ALLOW for HTTP.
- TCP 443: ALLOW for HTTPS.
- Logging: medium.
- Rules apply to IPv4 and IPv6.

Restore the rules before enabling UFW:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw logging medium
sudo ufw enable
sudo ufw status verbose
```

Verify a new SSH connection after enabling UFW.

An earlier practical-work-5 request, before the DHCP address changed, produced:
SRC=192.168.56.1, DST=192.168.56.102, PROTO=TCP, DPT=8080.

## 7. Snapshots and recovery order

| Snapshot | Created, UTC | Purpose |
|---|---|---|
| 01-almost-clean-install | 2026-10-13 17:16:49 | Initial baseline |
| 02-keys-configured | 2026-10-13 18:13:02 | User and key authentication |
| 03-ssh-hardened | 2026-10-20 16:49:49 | SSH hardening, before UFW |
| 04-nginx-https | 2026-10-28 07:49:09 | Nginx and HTTPS |
| before-practice7 | 2026-10-28 13:24:09 | Completed practice 6, before Docker installation |
| 05-docker-compose | 2026-10-28 14:21:38 | Working application, database and reverse proxy |

Recovery order:

1. Restore the baseline snapshot.
2. Set the NAT guest port to 22 for initial SSH access.
3. Check the devops account and install its public key.
4. Restore the hostname and hosts entries.
5. Restore SSH hardening and verify its effective configuration.
6. Apply SSH settings and test a new connection through Host-only.
7. Change the NAT guest port to 2222 and verify ssh devops.
8. Restore UFW rules, enable it, and verify another SSH connection.
9. Restore the web server using section 8 and containers using section 9, then
   run `sudo bash scripts/audit.sh`. All fourteen checks must pass with exit 0.

## 8. Web server

- Package: `nginx`; verified running version: 1.28.3 on Ubuntu.
- Site configuration: `/etc/nginx/sites-available/devops-site`.
- Enabled link: `/etc/nginx/sites-enabled/devops-site`.
- The default site link is absent; its available configuration is retained.
- Source-controlled configuration: `config/nginx/devops-site`.
- Document root: `/var/www/devops-site`, owned by `devops:devops`.
- Directory mode: 755. HTML file mode: 644.
- Master process: root. Worker processes: www-data.
- HTTP: TCP 80, permanent redirect (301) to the same path on HTTPS.
- HTTPS: TCP 443, TLS 1.2 and TLS 1.3.
- Reverse proxy: `/app/` forwards to `http://127.0.0.1:5000/`; static `/` is retained.
- Access log: `/var/log/nginx/devops-site.access.log`, including HTTP redirects.
- Error log: `/var/log/nginx/devops-site.error.log`.
- Certificate: `/etc/ssl/certs/devops.crt`, root-owned, mode 644.
- Private key: `/etc/ssl/private/devops.key`, root-owned, mode 600.
- SAN: `DNS:devops.local`; self-signed subject and issuer: `CN=devops.local`.
- Certificate lifetime: 365 days, 2026-10-28 07:34:07 UTC to 2027-10-28 07:34:07 UTC.
- HSTS is not configured for this self-signed classroom setup.

Reproduce the configuration on a restored VM:

```bash
sudo apt update
sudo apt install -y nginx rsync openssl
sudo mkdir -p /var/www/devops-site
sudo chown devops:devops /var/www/devops-site
sudo chmod 755 /var/www/devops-site
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key \
  -out /etc/ssl/certs/devops.crt \
  -subj "/CN=devops.local" \
  -addext "subjectAltName=DNS:devops.local"
sudo chown root:root /etc/ssl/private/devops.key /etc/ssl/certs/devops.crt
sudo chmod 600 /etc/ssl/private/devops.key
sudo chmod 644 /etc/ssl/certs/devops.crt
sudo install -m 644 config/nginx/devops-site /etc/nginx/sites-available/devops-site
sudo ln -sfn /etc/nginx/sites-available/devops-site /etc/nginx/sites-enabled/devops-site
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
```

The configuration-copy commands assume a copy of this repository is present on
the VM. Restore the site content from WSL using section 10. A new certificate
requires copying the new public certificate to the client again. Keep the
private key on the server; it is not included in this repository.

## 9. Containerization

- Engine: Docker CE 29.9.2 from the official `download.docker.com` Ubuntu apt repository.
- Compose plugin: 5.6.1. Buildx: 0.38.1. The `docker.io` and Snap packages are not used.
- Install helper: `scripts/install-docker-engine.sh`; installation transcript is in
  `evidence/practice7/docker-install.log`.
- Docker-enabled user: `devops`, already a sudo administrator. Docker-group
  membership grants root-equivalent access to the Docker host.
- Host source directory: the repository's `app/` directory in WSL.
- VM project directory: `/home/devops/app`; Compose project name: `app`.
- Container names: `app-app-1` and `app-db-1`.
- App image: `devops-app:1.0`, based on `python:3.12-slim`.
- Database image: `postgres:16-alpine`; keep the major version fixed for this data volume.
- Main process: Gunicorn in exec form, user `app`, observed UID/GID 999.
- Image source files are root-owned and mode 644; the app user cannot modify them.
- Application publication: `127.0.0.1:5000:5000` only.
- PostgreSQL listens on container port 5432, with no published host port.
- Private Compose bridge: `app_backend`; the app resolves the database as `db`.
- Persistent named volume: `app_db_data`, mounted at `/var/lib/postgresql/data`.
- Server-only secret file: `/home/devops/app/.env`, owned by devops, mode 600.
- Public template: `app/.env.example`. `.gitignore` and `.dockerignore` exclude `.env`.
- Dependency versions follow the handout: Flask 3.0.3, psycopg2-binary 2.9.9, Gunicorn 22.0.0.
- Database readiness uses `pg_isready`; app startup waits for `service_healthy`.
- The app has an HTTP `/health` healthcheck. Both services use `unless-stopped`.
- Container logs are rotated at 10 MiB, retaining three files per service.

Initial Docker installation on the VM:

```bash
sudo bash ~/devops-course-2026/scripts/install-docker-engine.sh
```

Reconnect SSH after joining the docker group. Verify `docker version`,
`docker compose version`, and `docker run --rm hello-world` as devops.

Transfer application source from the repository root in WSL:

```bash
rsync -avz --delete --exclude=.env --chmod=D755,F644 --dry-run app/ devops:app/
rsync -avz --delete --exclude=.env --chmod=D755,F644 app/ devops:app/
```

The exclusion protects the existing server `.env` from `--delete`. On a fresh VM,
create the secret locally and start the project as devops:

```bash
cd ~/app
if [ ! -f .env ]; then
  (umask 077; printf 'POSTGRES_DB=app\nPOSTGRES_USER=app\nPOSTGRES_PASSWORD=%s\nDB_HOST=db\n' "$(openssl rand -hex 16)" > .env)
fi
chmod 600 .env
docker compose config --quiet
docker compose up -d --build --wait --wait-timeout 120
docker compose ps
curl -f http://127.0.0.1:5000/health
```

The password is generated only on the VM and is never copied into the host
checkout. Avoid printing expanded `docker compose config` output or complete
container environment dumps into the report; `--quiet` validates without secrets.

Nginx forwards `/app/` to the app and strips that prefix because `proxy_pass`
ends in `/`. It passes Host, X-Real-IP, X-Forwarded-For and X-Forwarded-Proto.
The existing HTTPS certificate and static document root are unchanged.

`docker compose down` preserves `app_db_data`. `down -v` deletes project volumes;
the destructive demonstration was performed on an isolated disposable project
using loopback port 5002. The main volume was preserved. The temporary public
port-5001 demonstration and deliberately public port-5000 audit test were restored.

## 10. WSL client and deployment

- Host-side Linux: Ubuntu under WSL 1, user `q`.
- Windows checkout: `C:\Users\Q\Other\HW\Devops\Core\tasks`.
- WSL path: `/mnt/c/Users/Q/Other/HW/Devops/Core/tasks`.
- Existing repository: `veosp/s2`; base branch: `master`.
- Practical-work branch: `feature/web-deploy`.
- The handout calls the base branch `main`; this existing repository uses `master`.
- WSL private key: `/home/q/.ssh/devops_vm`, mode 600.
- WSL SSH configuration: `/home/q/.ssh/config`, mode 600.
- Trusted public certificate: `/home/q/devops.crt`.
- `.gitattributes` retains LF endings for the shell scripts and exercise artifacts.
- Repository-local `core.autocrlf=true` matches Git for Windows; `core.fileMode=false`
  avoids false executable-bit changes on `/mnt/c`.
- VPN routing/filtering previously blocked WSL traffic and Host-only connections.
  Successful final checks were performed with the interfering VPN disconnected.

Copy the client configuration from Windows into WSL:

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
cp /mnt/c/Users/Q/.ssh/devops_vm ~/.ssh/
cp /mnt/c/Users/Q/.ssh/config ~/.ssh/
cp /mnt/c/Users/Q/.ssh/known_hosts ~/.ssh/
chmod 600 ~/.ssh/devops_vm ~/.ssh/config ~/.ssh/known_hosts
ssh -o BatchMode=yes devops 'hostname -f'
scp devops:/etc/ssl/certs/devops.crt ~/devops.crt
```

`BatchMode=yes` makes an unsuitable key fail immediately instead of requesting
interactive credentials. The existing trusted host-key entries are retained.
The SSH alias uses NAT port forwarding at 127.0.0.1:2222, whereas web requests
use the Host-only address 192.168.56.101 directly.

Manual content synchronization from the repository root in WSL:

```bash
rsync -avz --delete --chmod=D755,F644 --dry-run site/ devops:/var/www/devops-site/
rsync -avz --delete --chmod=D755,F644 site/ devops:/var/www/devops-site/
curl --cacert ~/devops.crt -I https://devops.local/
curl --cacert ~/devops.crt -I https://devops.local/no-such-page
```

The first request must return 200; the missing page must return 404 with the
custom error-page body. The trailing slash after `site/` copies its contents.
The destination path is dedicated to the site; `--delete` removes stale files
only within that destination.

After committing the exercise files, use:

```bash
bash scripts/deploy.sh --dry-run
bash scripts/deploy.sh
```

The script locates the repository from its own path, rejects missing or
untracked `site/index.html` and all uncommitted changes, synchronizes using one
rsync/SSH operation, checks HTTPS using the trusted certificate, and prints the
short HEAD hash on success. A dry run does not check service availability.
SSH multiplexing reduces repeated connections during rapid successive runs.

## 11. Verification and evidence

```bash
# VM
sudo bash /home/devops/devops-course-2026/scripts/audit.sh
echo $?

# WSL, repository root: offline contract tests
bash tests/test-deploy.sh
```

The audit checks SSH, UFW, Nginx service state and configuration, at least 30 days
of certificate lifetime, absence of world-writable site content, and private-key
ownership/mode. `CERT_MIN_DAYS=400` deliberately exercises the expiry failure.

Practice 7 adds four checks: Docker active, database healthy, loopback-only app
publication with no database publication, and server `.env` mode/ownership.
The current total is fourteen; the saved practice-6 transcripts retain their
original ten-check results. Use `docs/practice7-validation.md` and
`docs/practice7-screenshots.md` for container tests and report evidence.

`scripts/practice6-verify.sh` is a VM-only, sudo-run classroom verifier. It
records permission experiments, a short real Nginx outage, audit failures and
recovery, and HTTP-log analysis. It restores the working content, safe modes,
and Nginx before returning. Raw transcripts are in `evidence/practice6/`, ignored
by Git. See `docs/practice6-validation.md` for the distinction between real
integration evidence and mocked contract tests, and `docs/practice6-screenshots.md`
for a short screenshot checklist.
