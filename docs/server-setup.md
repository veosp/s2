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

## 3. Port forwarding

Adapter 1, NAT, TCP:

- Host address: 127.0.0.1.
- Host port: 2222.
- Guest address: unspecified.
- Guest port: 2222.

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

## 7. Snapshots and recovery order

| Snapshot | Created, UTC | Purpose |
|---|---|---|
| 01-almost-clean-install | 2026-10-13 17:16:49 | Initial baseline |
| 02-keys-configured | 2026-10-13 18:13:02 | User and key authentication |
| 03-ssh-hardened | 2026-10-20 16:49:49 | SSH hardening, before UFW |
| 04-nginx-https | 2026-10-28 07:49:09 | Nginx and HTTPS |

Recovery order:

1. Restore the baseline snapshot.
2. Set the NAT guest port to 22 for initial SSH access.
3. Check the devops account and install its public key.
4. Restore the hostname and hosts entries.
5. Restore SSH hardening and verify its effective configuration.
6. Apply SSH settings and test a new connection through Host-only.
7. Change the NAT guest port to 2222 and verify ssh devops.
8. Restore UFW rules, enable it, and verify another SSH connection.
9. Restore the web server using section 8, then run `sudo bash scripts/audit.sh`.
   All ten SSH, firewall, and web checks must pass with exit code 0.

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

Run the configuration-copy commands from the repository on the VM.
Copy a regenerated public certificate to the client again.

## 9. WSL client and deployment

- Client: Ubuntu under WSL 1, user q.
- Repository: veosp/s2, default branch main.
- Windows checkout: `C:\Users\Q\Other\HW\Devops\Core\tasks`.
- WSL checkout: `/mnt/c/Users/Q/Other/HW/Devops/Core/tasks`.
- SSH private key: `/home/q/.ssh/devops_vm`, mode 600.
- SSH configuration: `/home/q/.ssh/config`, mode 600.
- Trusted certificate: `/home/q/devops.crt`.

Client configuration [WSL]:

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
cp /mnt/c/Users/Q/.ssh/devops_vm ~/.ssh/
cp /mnt/c/Users/Q/.ssh/config ~/.ssh/
cp /mnt/c/Users/Q/.ssh/known_hosts ~/.ssh/
chmod 600 ~/.ssh/devops_vm ~/.ssh/config ~/.ssh/known_hosts
git config core.fileMode false
ssh -o BatchMode=yes devops 'hostname -f'
scp devops:/etc/ssl/certs/devops.crt ~/devops.crt
```

Initial site delivery from the repository root [WSL]:

```bash
rsync -avz --delete --chmod=D755,F644 --dry-run site/ devops:/var/www/devops-site/
rsync -avz --delete --chmod=D755,F644 site/ devops:/var/www/devops-site/
curl --cacert ~/devops.crt -I https://devops.local/
curl --cacert ~/devops.crt -I https://devops.local/no-such-page
```

Subsequent deployment requires a clean working tree [WSL]:

```bash
bash scripts/deploy.sh --dry-run
bash scripts/deploy.sh
```

Configuration audit [VM]:

```bash
sudo bash ~/devops-course-2026/scripts/audit.sh
echo $?
```
