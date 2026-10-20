# Server setup: devops-vm

## 1. Machine parameters

- VirtualBox VM name: ubuntu-server.
- Operating system: Ubuntu Server 26.04.1 LTS.
- CPU: 2 virtual cores.
- Memory reported by Linux: 3.3 GiB.
- Swap: 2 GiB.
- Virtual disk: 25 GiB.
- Root filesystem: 11.5 GiB, ext4 on LVM.
- Boot partition: 2 GiB.

## 2. Network interfaces and hostnames

| Interface | Mode | Address | Purpose |
|---|---|---|---|
| enp0s3 | NAT | 10.0.2.15/24 | Internet access |
| enp0s8 | Host-only | 192.168.56.102/24 | Communication with Windows |

Windows Host-only adapter: Ethernet 2, 192.168.56.1/24.

Windows file: C:\Windows\System32\drivers\etc\hosts

```text
192.168.56.102 devops.local
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

Windows private key: C:\Users\ovlad\.ssh\devops_vm
Windows public key: C:\Users\ovlad\.ssh\devops_vm.pub

The public key is installed in /home/devops/.ssh/authorized_keys.
Directory permissions: 700. File permissions: 600.

Before disabling password authentication, install the public key
from Git Bash on Windows:

```bash
ssh-copy-id -i ~/.ssh/devops_vm.pub -p 2222 devops@127.0.0.1
```

Windows SSH configuration, C:\Users\ovlad\.ssh\config:

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

A Windows request to TCP port 8080 produced UFW BLOCK entries:
SRC=192.168.56.1, DST=192.168.56.102, PROTO=TCP, DPT=8080.

## 7. Snapshots and recovery order

- 01-almost-clean-install: initial baseline.
- 02-keys-configured: user and key authentication configured.
- 03-ssh-hardened: SSH hardened, before UFW configuration.

Recovery order:

1. Restore the baseline snapshot.
2. Set the NAT guest port to 22 for initial SSH access.
3. Check the devops account and install its public key.
4. Restore the hostname and hosts entries.
5. Restore SSH hardening and verify its effective configuration.
6. Apply SSH settings and test a new connection through Host-only.
7. Change the NAT guest port to 2222 and verify ssh devops.
8. Restore UFW rules, enable it, and verify another SSH connection.
9. Run scripts/audit.sh: all six checks must pass with exit code 0.
