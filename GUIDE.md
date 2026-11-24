# Quick Start Guide

Get the stack running and create a WordPress, Moodle, or plain PHP site in a few minutes.
Everything runs in Docker, so you do not need PHP or MySQL installed on your computer.

Detailed reference: [README.md](README.md).

---

## 1. Install the requirements

- **Docker Desktop** — install it, start it, and wait until it says it is running.
- **Git Bash** (Windows) or the built-in terminal (macOS/Linux).

Check that Docker works:

```bash
docker --version
docker compose version
```

## 2. Open the project folder

In **Git Bash** on Windows:

```bash
cd /c/Users/Keval/Documents/xampp-like-docker-setup
```

In **PowerShell**:

```powershell
cd C:\Users\Keval\Documents\xampp-like-docker-setup
```

> **PowerShell users:** do not type `bash stack.sh`. PowerShell's `bash` command starts WSL, not Git Bash, and fails if WSL is not configured. Use `.\stack.cmd` instead, for example `.\stack.cmd up`. It finds Git Bash for you. The Git Bash commands below also work if you replace `bash stack.sh` with `.\stack.cmd`.

## 3. Create your settings file

Do this once. In Git Bash:

```bash
cp .env.example .env
```

In PowerShell:

```powershell
Copy-Item .env.example .env
```

`.env` holds ports, passwords, and the app versions. It defaults to WordPress 7.1.5, Moodle 5.3.1, PHP 8.3, and MySQL 8.4; those PHP/MySQL versions meet Moodle 5.3's requirements. You can edit it later.

## 4. Start the stack

Git Bash:

```bash
bash stack.sh up
```

PowerShell:

```powershell
.\stack.cmd up
```

The first run builds the PHP image, which takes a few minutes. When it finishes, open:

**http://localhost/**

You will see a dashboard with links to every service and project.

## 5. Know your addresses

| What | Address | Login |
| --- | --- | --- |
| Dashboard | http://localhost/ | — |
| phpMyAdmin | http://localhost:8080/ | `root` / `root` |
| Mailpit (email catcher) | http://localhost:8025/ | — |
| MySQL from your computer | `127.0.0.1:3306` | `root` / `root` or `dev` / `dev` |
| Jenkins (optional) | http://localhost:8081/ | see step 10 |

MySQL host **inside** the containers is `db`, not `127.0.0.1`.

## 6. Create a WordPress site

One command (installs WordPress 7.1.5):

```bash
bash stack.sh wp blog
```

Open **http://blog.localhost/**

- Admin: http://blog.localhost/wp-admin/
- Username: `admin`
- Password: `admin`

Change these defaults in `.env` (`WP_ADMIN_*`) before running the command.

## 7. Create a Moodle site

Install Moodle 5.3.1:

```bash
bash stack.sh moodle learn
```

Open **http://learn.localhost/**

- Admin: http://learn.localhost/admin/
- Username: `admin`
- Password: `Admin123!`

Change these defaults in `.env` (`MOODLE_ADMIN_*`) before running the command.

> The first Moodle install copies tens of thousands of small files. On Windows this can take several minutes. Let it finish; later page loads are normal.

## 8. Run your own PHP project

Create a folder in `www/` with an `index.php`:

```bash
mkdir -p www/hello
printf '<?php echo "Hello from my project";\n' > www/hello/index.php
```

Open **http://hello.localhost/** (or http://localhost/hello/).

If your project's public files are in a subfolder such as `public/`:

```bash
bash stack.sh vhost hello public
```

That creates **http://hello.localhost/** pointing at `www/hello/public/`.

Project folder names must be lowercase, start with a letter, and contain only letters, digits, or hyphens.

## 9. Everyday commands

| Task | Command |
| --- | --- |
| Start everything | `bash stack.sh up` |
| Stop (keep database) | `bash stack.sh down` |
| Show status | `bash stack.sh ps` |
| Follow logs | `bash stack.sh logs` |
| Follow one service's logs | `bash stack.sh logs web` |
| Open a shell in the web container | `bash stack.sh shell` |
| Open MySQL console | `bash stack.sh db` |
| Run a query | `bash stack.sh sql "SHOW DATABASES;"` |
| Back up a database | `bash stack.sh dump blog` |
| Restore a backup | `bash stack.sh restore backups/blog-20260101-120000.sql` |
| Delete a project and its files | `bash stack.sh delete blog` |
| Rebuild after changing the Dockerfile | `bash stack.sh build` |
| Print URLs and credentials | `bash stack.sh info` |

Composer is available inside the web container:

```bash
bash stack.sh shell
cd /var/www/html/hello
composer require monolog/monolog
```

## 10. Start Jenkins (optional)

```bash
bash stack.sh ci-up
```

Open **http://localhost:8081/**. Get the first-time admin password with:

```bash
docker compose exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

Stop it with `bash stack.sh ci-down`.

Jenkins is not started by `up` so the core stack stays fast.

## 11. Test email

PHP `mail()` is already routed to Mailpit. Send a test message:

```bash
docker compose exec web php -r 'mail("dev@example.test", "Hello", "From the stack");'
```

Read it at **http://localhost:8025/**. Mail is captured locally and never sent outside your computer.

## 12. Stop or remove everything

Stop containers, keeping your websites and databases:

```bash
bash stack.sh down
```

Delete containers **and** the database/Jenkins data (destructive):

```bash
docker compose down -v
```

Neither command deletes project files. To delete one project completely, including its folder in `www/`, its vhost, and its database:

```bash
bash stack.sh delete blog
```

It asks you to type the project name first. Add `--yes` to skip the prompt:

```bash
bash stack.sh delete blog --yes
```

Moodle projects also keep uploaded files in the shared `data/moodledata` directory; that directory is left in place because it is shared by every Moodle site.

## 13. If something goes wrong

| Problem | Fix |
| --- | --- |
| PowerShell shows `Failed to attach disk ... ext4.vhdx` | PowerShell's `bash` is WSL and its default distro is broken. Use `.\stack.cmd` or Git Bash. |
| A port is already in use | Change the port in `.env`, then run `bash stack.sh up` |
| A site does not load | Run `bash stack.sh ps` and `bash stack.sh logs web` |
| `*.localhost` does not open | Try Chrome, Edge, or Firefox; or use `curl -H 'Host: blog.localhost' http://localhost/` |
| WordPress links return 404 | Make sure `www/wp-cli.yml` and `www/blog/.htaccess` exist |
| Moodle seems stuck | It is still copying files on Windows; wait for the terminal prompt |
| Permission errors on Linux | `sudo chown -R 33:33 www data/moodledata` |

More solutions: [README.md](README.md#troubleshooting).

---

**Security:** this stack uses known passwords, exposes MySQL/Jenkins on localhost, and runs Xdebug. Use it for local development only and never expose it to the internet.
