# Practical work 6: short screenshot guide

Commands are for reproducing evidence in a terminal. The report can contain
short section captions and screenshots rather than pasting every command.

WSL prompt: `q@Q`. VM prompt: `devops@devops-vm`. Run the following once in WSL:

```bash
cd /mnt/c/Users/Q/Other/HW/Devops/Core/tasks
```

## 1. SSH settings transferred to WSL; WSL-to-VM connection

WSL:

```bash
stat -c '%a %n' ~/.ssh ~/.ssh/devops_vm ~/.ssh/config
ssh -o BatchMode=yes devops 'hostname -f'
```

Capture the key/config modes and successful hostname output. The completed copy
procedure is documented in `docs/server-setup.md`, section 9.

## 2. Nginx configuration and enabled site

VM, after `ssh devops`:

```bash
sudo nginx -t
ls -l /etc/nginx/sites-enabled/
sudo ss -tnlp | grep nginx
ps -o user,pid,ppid,cmd -C nginx
```

Capture the successful syntax test, enabled link, listeners and process users.
`sudo cat /etc/nginx/sites-available/devops-site` shows the complete live config.

## 3. HTTP redirect and trusted HTTPS

WSL, after returning from the VM with `exit`:

```bash
curl -I http://devops.local
curl --cacert ~/devops.crt -I https://devops.local
openssl x509 -in ~/devops.crt -noout -subject -issuer -dates -ext subjectAltName
```

Capture HTTP 301, HTTPS 200 without `-k`, and the self-signed certificate with
SAN. The current HTTP configuration redirects; the earlier default welcome-page
state is not claimed to be the current state.

## 4. Site transfer and final permissions

WSL, repository root:

```bash
ls -l site/
rsync -avz --delete --chmod=D755,F644 --dry-run site/ devops:/var/www/devops-site/
ssh devops 'ls -la /var/www/devops-site/'
curl --cacert ~/devops.crt -I https://devops.local/no-such-page
```

Capture local versus remote modes and 404. For the already completed actual
transfer, display `cat evidence/practice6/rsync-integration.log`.

## 5. Deploy-script checks

WSL:

```bash
bash tests/test-deploy.sh
bash scripts/deploy.sh --dry-run
echo $?
```

The test suite is explicitly mocked and reports twelve passed contract checks.
Before committing, the real deploy script must refuse the dirty tree with exit
1. After the owner commits all relevant changes, repeat the dry run and run
`bash scripts/deploy.sh; echo $?`; both should return 0. Do not label the mocked
tests as a real deployment of a newly committed version.

## 6. Permission diagnosis, audit and request logs

VM:

```bash
cd ~/devops-course-2026
sed -n '/Directory mode | others | HTTPS status/,+4p' evidence/practice6/permissions.log
sudo bash scripts/audit.sh
echo $?
sudo tail -n 6 /var/log/nginx/devops-site.access.log
sudo awk '{print $9}' /var/log/nginx/devops-site.access.log | sort | uniq -c | sort -rn
```

Capture the actual permission table, final 10/0 audit with exit 0, and request
records/status distribution. For negative audit evidence, display
`cat evidence/practice6/audit.log`; it records the real 400-day threshold and
world-writable-file failures, followed by recovery. No need to damage the live
configuration again just for a screenshot.

## Additional visual evidence

- Browser: main page and custom `/no-such-page` error page.
- Browser: certificate details for `devops.local`.
- VirtualBox snapshot manager: `04-nginx-https`.

## Files to commit manually

- `.gitattributes` and the `/evidence/` addition to `.gitignore`.
- `site/index.html` and `site/404.html`.
- `scripts/deploy.sh`, `scripts/audit.sh`, `scripts/practice6-verify.sh`.
- `tests/test-deploy.sh`.
- `config/nginx/devops-site`.
- `docs/server-setup.md`, `docs/practice6-validation.md`,
  `docs/practice6-screenshots.md`, `docs/command-reference.md`.

Mark shell scripts executable when staging, for example
`git add --chmod=+x scripts/*.sh tests/*.sh`. Stage the other listed files
separately. Raw `evidence/` transcripts are ignored. Neither the private TLS key
nor SSH private keys belong in this commit. The owner subsequently authorized
one local commit named `pr6`; no push was authorized or performed.
