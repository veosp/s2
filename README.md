# DevOps server coursework

Server exercises for the Ubuntu VM. The `main` history starts with practical
work 5 from `vm-things`; earlier Git exercises remain on the existing branches.

- Practical work 5: VM networking, SSH hardening and UFW.
- Practical work 6: Nginx, a static site, HTTPS and deployment checks.
- Practical work 7: Flask/PostgreSQL with Compose, persistent data and HTTPS proxying.

See [server setup](docs/server-setup.md),
[practical work 6 verification](docs/practice6-validation.md) and
[screenshot instructions](docs/practice6-screenshots.md).

The static site is `https://devops.local/`. The VM audit is
`~/devops-course-2026/scripts/audit.sh`. Commands in the setup document distinguish
the Windows host, WSL client and Ubuntu Server VM.

Runtime secrets and TLS private keys belong only on the VM. Raw experiment
evidence is excluded from this source repository.

## Containerized application

The VM project is `~/app`. Flask is available at `https://devops.local/app/`;
its health endpoint is `/app/health`. The application is published only at
`127.0.0.1:5000`; PostgreSQL has no published host port. The named volume is
`app_db_data`. Generate the runtime `.env` only on the VM and keep mode 600.

See [practical work 7 verification](docs/practice7-validation.md) and
[its screenshot guide](docs/practice7-screenshots.md). This branch contains the
14-check practice-7 audit. The live server's later KR2 extension is also saved
in the separate `veosp/devops-kr2` project, which remains pending defense.
