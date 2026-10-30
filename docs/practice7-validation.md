# Practical work 7: completion and verification

## Result

- Publication branch: `feature/docker`, based on the practical-work-6 server history.
- The original runtime validation used the earlier local `5617cc0 pr6` checkout.
- Runtime validation was completed before source publication. Publication uses a
  separate `pr7` commit and a pull request into the server-history `main` branch.
- The existing static site remains at `https://devops.local/`.
- Flask is published at `https://devops.local/app/`; health is `/app/health`.
- The chosen greeting is `Hello from Docker, Q!`.
- Docker Engine 29.9.2 and Compose 5.6.1 run inside the Ubuntu Server VM.
- Two primary containers run: `app-app-1` and `app-db-1`; both have healthchecks.
- The main data volume is `app_db_data`. No destructive test targets this volume.

## Image and standalone checks

The Dockerfile uses Python 3.12 slim, installs requirements before copying the
application, runs Gunicorn in exec form, and selects the unprivileged app user.
`COPY --chmod=644` protects the image source even when WSL reads NTFS files as
mode 777. Host-to-VM rsync also normalizes modes with `--chmod=D755,F644`.

The standalone container, launched without a database, returned 200 for `/health`
and 500 for `/`. Its real traceback showed a refused connection to localhost
port 5432. Localhost inside that container refers to the app container itself;
the Compose configuration instead sets `DB_HOST=db`.

`docker exec ... id` reported UID/GID 999 (app). A write-access check confirmed
that `/app/app.py` was not writable by the app user. The temporary standalone
container was removed after verification.

Only the greeting in app.py changed before the second build. The user-creation,
WORKDIR, requirements COPY, and pip-install steps were CACHED; the application
COPY was rebuilt. Actual output is retained in `build-initial.log`,
`build-cached.log`, `image-history.log` and `standalone.log`.

## Compose, networking and data

| Check | Observed result |
|---|---|
| Startup ordering | App waits for the database healthcheck |
| Initial visits | 1, 2, 3 |
| Main-project down/up | Visits 4 before, 5 after; named volume preserved |
| Docker DNS | The app resolves service name db on app_backend |
| App process | Non-root app user, UID/GID 999 |
| Main app binding | 127.0.0.1:5000 only |
| Database publication | None; 5432/tcp in docker ps is an internal exposed port |
| Server secret | /home/devops/app/.env, mode 600, owner devops |
| Secret in image | No /app/.env file |

The `.env` file was generated with a random password on the VM. It is excluded
from Git, rsync source synchronization and the Docker build context. Only the
placeholder `.env.example` is in the repository. Expanded environment/config
output is not included in the evidence.

The destructive demonstration used a separate project named
`practice7-reset-11497`, a separate volume, and loopback port 5002. Its visits
were 1, 2, 3, then 4 after normal down/up, then 1 after down -v/up. Its containers,
network, temporary files and data volume were removed afterwards. The main
volume creation identity was unchanged and its record count did not decrease.

This is a real deletion experiment on disposable data, not a simulated reset of
the main application. See `compose.log` and `volume-isolated.log`.

## Reverse proxy, UFW and failure diagnosis

The existing HTTPS block now includes `location /app/` with
`proxy_pass http://127.0.0.1:5000/`. The trailing slash replaces the `/app/` prefix
with `/`, so `/app/health` reaches Flask's `/health`. Host and forwarding headers
are retained. The static `/` location and the TLS key/certificate are preserved.

A temporary container on `0.0.0.0:5001` was reachable from WSL with HTTP 200 and
body `ok`, even though UFW had no allow rule for that port. The real Docker NAT
chain contained the 5001 DNAT rule. Docker's forwarding/NAT path does not rely
on the usual UFW INPUT allow rules. The test container was stopped immediately;
a watchdog also bounded its lifetime. No public port-5001 listener remains.

Stopping the app service produced HTTPS 502 and the actual Nginx error
`connect() failed (111: Connection refused) while connecting to upstream`.
The client-to-Nginx path worked; the Nginx-to-app connection failed. The service
was restarted and health recovered. A readiness retry handles the brief period
while Nginx workers adopt a reloaded configuration.

See `exposed-rules.log`, `exposed-client.log` and `proxy.log`.

## Container audit

The audit retains the previous ten checks and adds four:

1. Docker service is active.
2. The Compose database container is healthy.
3. The app mapping is exactly 127.0.0.1:5000, database mappings are absent,
   and no relevant unexpected listener exists.
4. The server `.env` is owned by devops and mode 600.

The baseline and restored runs passed 14/14 with exit 0. Temporarily publishing
5000 on all addresses made the port check fail and returned exit 1. The canonical
Compose file was retained; the override was removed and private publication was
restored. See `container-audit.log`.

## Evidence and owner actions

Raw transcripts are under `evidence/practice7/` in the host checkout and
`~/devops-course-2026/evidence/practice7/` on the VM. The host evidence directory
is ignored by Git. It contains real build, runtime, network, volume and audit
output, without the server secret file.

`before-practice7` protects the VM state before Docker installation. The final
snapshot is `05-docker-compose`. VirtualBox snapshots do not cover Windows/WSL
repository files; local pr6 is committed and practice-7 changes remain reviewable
in feature/docker.

Use `docs/practice7-screenshots.md` for a short report checklist. Source publication targets `main`, starting from the existing `vm-things`
history. Practical work 6 is integrated first so the Docker pull request contains
only practical-work-7 changes. Earlier Git exercises remain on their original
branches. KR2 extends the live audit separately; this historical result remains
14 checks.
