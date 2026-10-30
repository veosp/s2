# DevOps server coursework

Server exercises for the Ubuntu VM. The `main` history starts with practical
work 5 from `vm-things`; earlier Git exercises remain on the existing branches.

- Practical work 5: VM networking, SSH hardening and UFW.
- Practical work 6: Nginx, a static site, HTTPS and deployment checks.

See [server setup](docs/server-setup.md),
[practical work 6 verification](docs/practice6-validation.md) and
[screenshot instructions](docs/practice6-screenshots.md).

The static site is `https://devops.local/`. The VM audit is
`~/devops-course-2026/scripts/audit.sh`. Commands in the setup document distinguish
the Windows host, WSL client and Ubuntu Server VM.

Runtime secrets and TLS private keys belong only on the VM. Raw experiment
evidence is excluded from this source repository.
