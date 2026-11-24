# Local PHP Stack (XAMPP-style)

A local development stack in Docker: Apache + PHP, MySQL, phpMyAdmin, Mailpit, and an optional Jenkins. Drop a project into `www/` and open it in the browser. WordPress and Moodle can be installed with one command.

**New here?** Follow [GUIDE.md](GUIDE.md) for the short step-by-step version. This README is the detailed reference.

## What you get

| Service | Address | Notes |
| --- | --- | --- |
| Dashboard | http://localhost/ | Lists projects and service links |
| Apache + PHP | http://localhost/ | PHP 8.3, document root `www/` |
| phpMyAdmin | http://localhost:8080/ | Log in with the MySQL credentials below |
| Mailpit UI | http://localhost:8025/ | Catches every email sent by PHP |
| Mailpit SMTP | `mailpit:1025` (containers), `127.0.0.1:1025` (host) | No TLS or authentication |
| MySQL | `127.0.0.1:3306` | MySQL 8.4 |
| Jenkins (optional) | http://localhost:8081/ | Start with `bash stack.sh ci-up` |

Default credentials (change these in `.env` for anything beyond local use):

| User | Password | Scope |
| --- | --- | --- |
| `root` | `root` | MySQL superuser |
| `dev` | `dev` | General MySQL user, database `dev` |
| `admin` | `admin` | WordPress admin created by the helper |
| `admin` | `Admin123!` | Moodle admin created by the helper |

PHP includes mysqli, PDO MySQL, gd, intl, zip, soap, exif, bcmath, opcache, imagick, and Xdebug. Composer and WP-CLI are installed in the web container.

The helpers are pinned to **WordPress 7.1.5** and **Moodle 5.3.1**. Moodle 5.3 requires PHP 8.3+ and MySQL 8.4, which are the defaults in `.env`. WordPress 7.1.5 requires PHP 7.4+ and MySQL 5.5.5+.

## Requirements

- Docker Desktop (Windows/macOS) or Docker Engine with the Compose plugin.
- Bash: Git Bash or WSL on Windows, Terminal on macOS/Linux.
- Free ports `80`, `3306`, `8080`, `8025`, `1025`, and optionally `8081`/`50000`.

## Quick start

From Git Bash:

```bash
bash stack.sh up
```

From PowerShell, use the Windows wrapper (PowerShell's own `bash` command launches WSL, not Git Bash):

```powershell
.\stack.cmd up
```

Then open http://localhost/. Stop containers without deleting the database:

```bash
bash stack.sh down
```

Other useful commands:

```bash
bash stack.sh ps
bash stack.sh logs
bash stack.sh logs web
bash stack.sh shell
bash stack.sh shell db
bash stack.sh restart web
bash stack.sh build
bash stack.sh info
```

## How projects are served

Apache's document root is `www/`. Any directory with an `index.php` works at both:

- `http://localhost/<folder>/` — the XAMPP-style path URL.
- `http://<folder>.localhost/` — a wildcard virtual host.

Modern browsers resolve `*.localhost` to loopback automatically. If a tool does not, add an entry to your hosts file (for example `127.0.0.1 blog.localhost`), or access it through curl with a `Host` header.

The WordPress and Moodle helpers install with the `*.localhost` URL as their canonical URL, because both applications need a fixed site URL. Use the subdomain URLs for those projects; their path URLs will redirect or break.

For projects whose public files live in a subdirectory, create an exact virtual host whose document root is that subdirectory:

```bash
bash stack.sh vhost myapp public
```

This creates `data/apache-vhosts/myapp.conf` for `http://myapp.localhost/` and reloads Apache. Generated vhosts are included before the wildcard vhost, so exact hostnames take precedence. The Moodle helper does this automatically when it finds Moodle's `public/` directory.

## Delete a project

```bash
bash stack.sh delete blog
```

This removes `www/blog`, its generated vhost, and the database whose name matches the project (`blog`; hyphens become underscores). It asks you to type the project name before deleting; add `--yes` to skip the prompt. Shared Moodle uploads in `data/moodledata` are left in place. `bash stack.sh down` and `docker compose down -v` never delete project files.

## WordPress

```bash
bash stack.sh wp blog
```

The helper downloads WordPress 7.1.5 into `www/blog`, creates a database named `blog`, writes `wp-config.php`, installs the site, and enables pretty permalinks. Change `WORDPRESS_VERSION` in `.env` to use another release.

- Site: http://blog.localhost/
- Admin: http://blog.localhost/wp-admin/
- Credentials: `WP_ADMIN_USER` / `WP_ADMIN_PASSWORD` from `.env` (default `admin` / `admin`)

It writes `www/wp-cli.yml` with `apache_modules: [mod_rewrite]` so WP-CLI can generate `.htaccess`. If pretty permalinks stop working, check that this file and `www/blog/.htaccess` exist.

## Moodle

```bash
bash stack.sh moodle learn
```

The helper downloads Moodle 5.3.1, detects whether it uses the `public/` web root, creates a matching virtual host, creates the database, and runs Moodle's CLI installer. Change `MOODLE_VERSION` in `.env` to use another 5.3.x release.

- Site: http://learn.localhost/
- Admin: http://learn.localhost/admin/
- Credentials: `MOODLE_ADMIN_*` from `.env` (default `admin` / `Admin123!`)

The first Moodle install writes tens of thousands of small files. On Windows bind mounts this can take a long time; let it finish. Later requests are faster once the files are cached.

## Plain PHP and Composer

Create any project directory with a web entry point:

```bash
mkdir -p www/hello
printf '<?php phpinfo();\n' > www/hello/index.php
```

Open http://hello.localhost/ or http://localhost/hello/.

Composer is available inside the web container. Open a shell to avoid Windows path conversion issues:

```bash
bash stack.sh shell
cd /var/www/html/hello
composer require monolog/monolog
```

For ad-hoc `docker compose exec` commands that pass absolute container paths from Git Bash, prefix the command with `MSYS_NO_PATHCONV=1`.

## Database

phpMyAdmin is at http://localhost:8080/. From applications running in containers use host `db`, port `3306`. From your host use `127.0.0.1:3306`.

```bash
bash stack.sh db
bash stack.sh sql "SHOW DATABASES;"

bash stack.sh dump blog
bash stack.sh restore backups/blog-20260101-120000.sql
```

Dumps are written to `backups/`. The database volume survives `bash stack.sh down`. To delete the database and Jenkins volumes, run `docker compose down -v` — this is destructive.

The first time the MySQL volume is created, the init script also creates empty `wordpress` and `moodle` databases and grants `dev` access. Initialization scripts run only on a fresh volume.

## Email

PHP's `mail()` is wired to Mailpit through msmtp. Send a test message:

```bash
docker compose exec web php -r 'mail("dev@example.test", "Hello", "From the stack");'
```

Open http://localhost:8025/ to read it. Configure other applications with SMTP host `mailpit` and port `1025` when they run in a container, or `127.0.0.1:1025` from the host. Mailpit accepts any credentials and does not use TLS, so set authentication/TLS to off where required. Mail is captured locally; it is not delivered externally.

## Xdebug

`XDEBUG_MODE=develop` is the default. To step-debug:

1. Set `XDEBUG_MODE=debug` in `.env` and run `bash stack.sh restart web`.
2. In VS Code, install the recommended PHP Debug extension (`.vscode/extensions.json`).
3. Open the repository folder, start the **Listen for Xdebug (Docker)** configuration, and set breakpoints.

Xdebug listens on port `9003` and connects back to `host.docker.internal`; the path mapping from `/var/www/html` to `www/` is already in `.vscode/launch.json`. Use `XDEBUG_MODE=off` for maximum performance.

## Jenkins (optional)

```bash
bash stack.sh ci-up
```

Open http://localhost:8081/. The initial admin password is inside the container:

```bash
docker compose exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

The Jenkins image includes the Docker CLI and Compose plugin, and the Docker socket is mounted so jobs can build and run containers. This gives Jenkins effective root access to the Docker daemon, so keep it local and do not expose it. Jenkins data lives in the `jenkins_home` volume.

```bash
bash stack.sh ci-logs
bash stack.sh ci-down
```

The CI profile is not started by `up`; Jenkins is opt-in so the core stack stays fast.

## Customization

`.env` controls ports, the PHP version, the WordPress and Moodle versions, database credentials, bind address, timezone, admin accounts, and Xdebug mode. After changing it, run `bash stack.sh up` (Compose recreates affected containers).

- PHP settings: `docker/php/php.ini` (mounted read-only at runtime).
- PHP extensions: edit `docker/php/Dockerfile`, then `bash stack.sh build` and `bash stack.sh up`.
- PHP version: set `PHP_VERSION=8.4` (or another official tag) in `.env`, then rebuild. Moodle 5.3 requires at least PHP 8.3.
- Apache: `docker/apache/000-default.conf` for `localhost`, `docker/apache/010-projects.conf` for the wildcard vhost, and `data/apache-vhosts/*.conf` for exact hosts.
- MySQL options: the `command:` list in `docker-compose.yml`.
- Bind to your LAN: set `BIND_ADDRESS=0.0.0.0`. The default is loopback only. WordPress/Moodle site URLs still use `*.localhost`, which resolves to the client's own loopback, so LAN access needs different site URLs.

After editing Apache configs, reload with `docker compose exec web apachectl -k graceful`.

## Troubleshooting

- **A port is already in use**: change the matching port in `.env` and run `bash stack.sh up`. If you change `WEB_PORT`, the dashboard and helpers include the port automatically.
- **PowerShell reports `Failed to attach disk ... ext4.vhdx`**: PowerShell's `bash` command is the WSL launcher, and its default distribution is missing or broken. Use `.\stack.cmd` (or Git Bash) instead. To repair WSL itself, list distributions with `wsl -l -v` and select a working one with `wsl --set-default <name>`.
- **`*.localhost` does not resolve**: use a browser that supports it (Chrome, Edge, Firefox, Safari), add individual hosts-file entries, or use `curl -H 'Host: name.localhost' http://localhost/`.
- **Git Bash rewrites container paths**: prefix ad-hoc Docker commands with `MSYS_NO_PATHCONV=1`. `stack.sh` already does this.
- **Permission errors on Linux**: Apache runs as `www-data` (uid 33). Use `sudo chown -R 33:33 www data/moodledata` if an application cannot write.
- **Moodle install is slow on Windows**: Docker Desktop's bind mount is slow with very many small files. The one-time extraction and install can take several minutes; let it finish.
- **Xdebug does not connect**: confirm `XDEBUG_MODE=debug`, the IDE is listening on 9003, port 9003 is free, and the container can reach `host.docker.internal`.
- **MySQL init scripts did not run**: they only execute when the data volume is first created. Apply SQL manually or recreate the volume (destructive).
- **WordPress permalinks return 404**: ensure `www/wp-cli.yml` and `www/<name>/.htaccess` exist, then rerun `wp rewrite structure '/%postname%/' --hard --path=/var/www/html/<name> --allow-root`.
- **Helper refuses a name**: names must start with a lowercase letter and contain only lowercase letters, digits, or hyphens. Existing non-empty project folders are never overwritten.

## Layout

```text
.
├── docker-compose.yml
├── stack.sh                  # main command runner
├── stack.cmd                 # Windows wrapper that calls stack.sh via Git Bash
├── .env                      # local settings (not committed)
├── docker/
│   ├── php/                  # PHP + Apache image and php.ini
│   ├── apache/               # default and wildcard vhosts
│   ├── mysql/init/           # first-boot database setup
│   └── jenkins/              # optional CI image
├── www/                      # projects; dashboard at www/index.php
├── data/
│   ├── moodledata/           # Moodle data directory
│   └── apache-vhosts/        # generated exact vhosts
├── backups/                  # database dumps
└── .vscode/                  # Xdebug launch configuration
```

## Security

This is a local development stack. It uses known default passwords, runs Xdebug, exposes MySQL and Jenkins on loopback, and gives Jenkins access to the Docker socket. Do not expose it to the internet and do not use these credentials in production.
