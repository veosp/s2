# Practical work 6: completion and verification

## Implemented

- Work is on `feature/web-deploy` in the existing `veosp/s2` repository.
- The base branch is `master`, rather than the handout's `main`.
- `site/index.html` and the custom `site/404.html` are delivered from WSL.
- `config/nginx/devops-site` records the live HTTP redirect and HTTPS server.
- `scripts/deploy.sh` implements dry-run, Git-state and index-file guards,
  permission-normalizing rsync, noninteractive SSH, HTTPS verification, and
  commit-hash output. It works from directories other than the repository root.
- `scripts/audit.sh` extends the SSH/firewall audit with four web-server checks.
- `scripts/practice6-verify.sh` performs bounded sudo-only classroom experiments
  and restores safe site content, permissions, and service state on exit.
- `docs/server-setup.md` retains the previous setup instructions, corrects the
  current Host-only address and Windows profile path, and adds web/WSL recovery.
- The initial implementation left all changes uncommitted and unstaged. The
  owner subsequently authorized one local commit named `pr6`. No push, pull
  request, or merge is authorized or performed as part of that commit.
  The starting commit is `fcdc4a4379c26ef96bc02432379af4dcf684e5e7`.

## Real integration checks

| Check | Observed result |
|---|---|
| WSL to VM SSH with the saved key | `devops-vm.devops.local`, success |
| HTTP request | 301, Location `https://devops.local/` |
| HTTPS with `--cacert`, without `-k` | 200, certificate/SAN verified |
| HTTPS negotiation captured from WSL | TLS 1.3 |
| Main response headers | nginx/1.28.3 (Ubuntu), text/html, 247 bytes before student details are edited |
| Custom missing-page response | 404 and the custom `Page not found` body |
| rsync dry-run | Server index SHA-256 unchanged |
| Actual rsync | Both remote HTML checksums equal their local checksums |
| Remote ownership and modes | devops:devops, directories 755, HTML files 644 |
| TLS key and public certificate | root-owned; key 600, certificate 644 |
| Baseline audit | 10 passed, 0 failed; exit 0 |
| Audit with `CERT_MIN_DAYS=400` | Certificate check fails; exit 1 |
| Audit with world-writable index | Content/key protection check fails; exit 1 |
| Audit after restoring normal state | 10 passed, 0 failed; exit 0 |
| Actual Nginx stop | HTTPS connection fails; curl exit 7 |
| Nginx restart | HTTPS 200 restored |
| Snapshot | `04-nginx-https` already exists, created 2026-10-28 07:49:09 UTC |

Raw command output is stored in `evidence/practice6/`, which is ignored by Git.
The VM also has a copy at `/home/devops/devops-course-2026/evidence/practice6/`.
These files are transcripts of actual runs, not fabricated output.

## Permission experiments

The HTML file mode was 644 while directory modes were varied.

| Directory mode | Other-user rights | HTTPS status | Explanation |
|---|---|---|---|
| 755 | r-x | 200 | The worker can traverse the directory and read the file. |
| 750 | --- | 403 | The worker cannot traverse this directory. |
| 744 | r-- | 403 | Directory listing permission does not permit traversal. |
| 711 | --x | 200 | A known filename can be reached without listing names. |

Setting the index file to 600 produced 403 and an `open() ... failed (13:
Permission denied)` record. Directory permission failures were also captured
from the real error log. With directory mode 711, `www-data` could read the known
index file but could not list the directory.

Mode 666 allowed a real content replacement by `www-data`. The source content
and safe modes were restored with rsync's `--chmod=D755,F644` policy; a subsequent
write attempt was denied. An application vulnerability allowing command or file
execution as the web worker could otherwise permit the same defacement.

## HTTP and access logs

`wsl-client.log` contains a real verbose TLS/HTTP exchange: `>` lines describe
the request, `<` lines describe the response, and `*` lines describe transport
and certificate negotiation. Requests were generated for `/`, `/admin`,
`/wp-login.php`, `/.env`, and HTTP port 80.

An access-log record contains client address, identity placeholders, timestamp,
request method/path/protocol, status, body bytes, referrer, and User-Agent. HEAD
responses can have zero body bytes in the access log even when the response's
Content-Length header describes the full representation size.

The status distribution includes successful responses, HTTP redirects, missing
pages, and permission failures generated during the experiments. Counts change
when checks are repeated; use the live aggregation command in the screenshot
guide instead of treating an old count as fixed.

Public scans for `/.env` look for exposed environment secrets; `/wp-login.php`
looks for a WordPress login endpoint. Logs identify the requesting address,
time, requested path, status, bytes and declared User-Agent. A log entry alone
does not identify a person's real identity or prove an intrusion succeeded.

## Deploy-test scope and the no-commit constraint

`bash tests/test-deploy.sh` passed twelve offline contract tests. Git, rsync,
and curl are mocked in that test suite. It checks clean/dry-run behavior,
unstaged/staged/untracked changes, a missing or untracked index, rsync failure,
HTTPS failure, invalid arguments, and trusted-certificate handling without
creating commits or changing the server.

Separately, actual rsync transfer, dry-run preservation, HTTPS verification,
custom 404, permission failures and Nginx outage/recovery were verified against
the real VM. The real deploy script was also run against this working tree and
correctly returned 1 before transferring anything because the exercise files
are uncommitted.

Before the local `pr6` commit was authorized, the handout's committed-version
scenarios could not be demonstrated literally. The real positive dry run and
deployment are checked after that commit, with output retained in
`evidence/practice6/deploy-after-commit.log`. The committed-index-removal scenario
would require another owner-authorized commit. Mocked clean-Git tests must not
be presented as proof of a newly committed real deployment.

After committing any later changes, repeat:

```bash
bash scripts/deploy.sh --dry-run
echo $?
bash scripts/deploy.sh
echo $?
```

Both should return 0. The second command prints the delivered commit's short
hash. Future runs refuse any unrelated uncommitted changes as well, which is
intentional. The required pull request and merge remain an owner action.

## Owner actions before submission

1. Replace `Student: Q. Group: YOUR GROUP.` with the correct student details,
   then commit that follow-up change before deploying it.
2. Review the local `pr6` commit and the files listed in the screenshot guide.
3. Repeat the two positive deployment commands above after any later commit.
4. Take the screenshots in `docs/practice6-screenshots.md`.
5. Push and create/merge the course pull request when ready; none were done here.

The detailed narrative report can be assembled later from the setup document,
this verification record, the screenshots, and the raw transcripts.
