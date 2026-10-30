# Command reference

Commands selected during the practical exercises. Keep each complete command on a single line and append new entries when requested.

| Command | Purpose and options |
| --- | --- |
| `ps -o user,pid,ppid,cmd -C nginx` | Show processes named `nginx`. `-o` selects columns: effective user, process ID, parent process ID, and command line. Use the Latin letter `C`. |
| `sudo ss -tnlp` | Show listening TCP sockets and their processes. `-t`: TCP; `-n`: numeric addresses and ports; `-l`: listening sockets; `-p`: owning processes. `sudo` permits viewing process details for other users. Option order does not matter here. |
| `sudo ss -tnlp \| grep nginx` | Show only socket-output lines containing the case-sensitive text `nginx`. The pipe sends standard output to `grep`, which selects matching text lines. |
| `sudo ufw app list` | List available UFW application profiles. This does not show whether their rules are enabled. |
| `sudo ufw status` | Show firewall status and configured rules. |
| `sudo ufw status verbose` | Also show default policies, logging settings, and additional rule details. |
| `ssh -o BatchMode=yes devops 'hostname -f'` | Connect using the saved alias/key, run the remote hostname command, then exit. BatchMode disables interactive password, passphrase, and confirmation prompts. |
| `namei -l /var/www/devops-site/index.html` | Show ownership and permissions of every component of the file path. Each parent directory needs traversal permission. |
| `sudo nginx -t` | Validate the Nginx configuration without applying changes. |
| `sudo nginx -t && sudo systemctl reload nginx` | Reload the configuration only after a successful syntax check. |
| `curl -I http://devops.local` | Request HTTP response headers using HEAD; the configured site returns a 301 redirect. |
| `curl --cacert ~/devops.crt -I https://devops.local` | Request HTTPS headers while verifying the server certificate using the explicitly trusted public certificate. |
| `curl -k -I https://devops.local` | Request HTTPS headers while skipping certificate verification; useful only for the comparison exercise. |
| `rsync -avz --delete --chmod=D755,F644 --dry-run site/ devops:/var/www/devops-site/` | Preview synchronization without changing the server. `-a`: recursive archive mode; `-v`: verbose; `-z`: compression; `--delete`: remove stale destination files; `--chmod`: normalize directory/file modes. The slash after `site/` means its contents. |
| `rsync -avz --delete --chmod=D755,F644 site/ devops:/var/www/devops-site/` | Perform the same synchronization after reviewing the dry-run plan. |
| `docker version` | Show Docker client and daemon versions; both sections must be available. |
| `docker compose version` | Show the installed Compose plugin version. |
| `docker build -t devops-app:1.0 .` | Build the application image from the current directory and assign its tag. |
| `docker history devops-app:1.0` | Show image-layer history and instruction sizes. |
| `docker compose up -d --build --wait` | Build and start the project in the background, waiting for its readiness checks. |
| `docker compose ps` | Show Compose service status, health and port publication. |
| `docker compose exec -T app id` | Run id inside the app container without allocating a terminal; verifies the non-root user. |
| `docker compose exec -T app getent ahostsv4 db` | Resolve the database service name through the Compose network's DNS, requesting IPv4 results. |
| `docker port app-app-1` | Show the app container's host port mappings; expected 127.0.0.1:5000 only. |
| `docker compose down` | Remove project containers and networks while preserving named data volumes. |
| `docker compose down -v` | Also delete the project's named volumes and their data. The classroom demonstration uses a separate disposable project. |
| `rsync -avz --delete --exclude=.env --chmod=D755,F644 app/ devops:app/` | Synchronize app source while preserving the server-only .env file and normalizing modes. Preview with --dry-run first. |
