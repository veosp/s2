# Practical work 7: short screenshot guide

WSL prompt: `q@Q`. VM prompt: `devops@devops-vm`. Enter the VM with `ssh devops` (or Windows `ssh.exe -o IPQoS=none devops` from WSL);
return to WSL with `exit`. Run VM commands below as devops. Screenshots of saved
transcripts show actual earlier experiments without repeating destructive tests.

## 1. Docker installation and image construction

VM:

```bash
docker version
docker compose version
docker history devops-app:1.0
```

Capture Client/Server, Compose and image layers. The Dockerfile is in the host
repository at `app/Dockerfile`.

## 2. Standalone error, non-root user and build cache

VM:

```bash
cd ~/devops-course-2026
grep -E 'HTTP/1.1|Main endpoint|OperationalError|Connection refused|uid=|read-only' evidence/practice7/standalone.log
grep -E 'RUN pip|COPY|CACHED' evidence/practice7/build-cached.log
```

Capture health 200, expected database-related 500, app UID, and cached dependency
layers. The full traceback and build output are retained in the same files.

## 3. Compose services, increasing counter and DNS

VM:

```bash
cd ~/app
docker compose ps
for i in 1 2 3; do curl -s http://127.0.0.1:5000/; done
docker exec app-app-1 id
docker exec app-app-1 getent ahostsv4 db
```

Capture healthy services, increasing Visits, non-root identity and database-name
resolution. The IPv4-specific lookup avoids waiting for an unnecessary AAAA lookup.

## 4. Private ports and server-only secret metadata

VM:

```bash
docker port app-app-1
docker port app-db-1
sudo ss -tlnp | grep -E ':(5000|5432)\b'
stat -c '%a %U %n' ~/app/.env
```

Capture loopback 5000, no database mapping and mode 600. Do not print the contents
of `.env`. A plain 5432/tcp label in docker ps is not a published host port.

## 5. Data persistence and disposable volume deletion

VM:

```bash
cd ~/devops-course-2026
grep -E 'Before compose down|After compose down|survived' evidence/practice7/compose.log
grep -E 'Disposable project|After normal|After down -v|Main counter|identity' evidence/practice7/volume-isolated.log
```

Capture the retained main counter and the disposable project's reset to 1.
There is no need to run down -v against the main project for a screenshot.

## 6. HTTPS proxy, UFW demonstration and audit

WSL:

```bash
curl --cacert ~/devops.crt https://devops.local/app/
curl --cacert ~/devops.crt https://devops.local/app/health
curl --cacert ~/devops.crt -I https://devops.local/
```

VM:

```bash
cd ~/devops-course-2026
cat evidence/practice7/exposed-rules.log
grep -E 'returned|Connection refused|upstream' evidence/practice7/proxy.log
sudo bash scripts/audit.sh
echo $?
grep -E '\[FAIL\]|Public-port audit|Passed:' evidence/practice7/container-audit.log
```

Capture the proxy responses, saved UFW/Docker rule demonstration, 502 error,
final 14/0 audit and the saved negative-audit result. The temporary public
container and bad mapping are already removed. `exposed-client.log` in the WSL
repository records the real successful request from WSL during that experiment.

Also capture VirtualBox snapshot `05-docker-compose`; a browser view of `/app/`
can accompany the proxy section.

## Files for the owner's commit

- `app/`: app.py, requirements.txt, Dockerfile, docker-compose.yml,
  .dockerignore and .env.example.
- Modified `.gitignore` and `.gitattributes`.
- Modified `config/nginx/devops-site` and `scripts/audit.sh`.
- New install/verification helpers in `scripts/`.
- Updated `docs/server-setup.md` and `docs/command-reference.md`.
- New `docs/practice7-validation.md` and `docs/practice7-screenshots.md`.

Publication uses the `feature/docker` branch and a pull request into `main`.
The actual server `.env` and raw ignored evidence do not belong in the commit.
The saved 14-check audit is the practice-7 result; later KR2 checks are separate.
