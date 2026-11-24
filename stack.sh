#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

# Git Bash on Windows rewrites /container/paths into C:/Program Files/Git/...
# MSYS_NO_PATHCONV is ignored on Linux and macOS.
export MSYS_NO_PATHCONV=1

if [[ -f .env ]]; then
    set -a
    # shellcheck disable=SC1091
    source .env
    set +a
fi

# stack.cmd (Windows) sets STACK_WRAPPER so hints name the wrapper the user ran.
if [[ -n "${STACK_WRAPPER:-}" ]]; then
    STACK_CMD="${STACK_WRAPPER}"
else
    STACK_CMD="bash stack.sh"
fi

COMPOSE=(docker compose)
PHP_VERSION="${PHP_VERSION:-8.3}"
DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-root}"
DB_USER="${DB_USER:-dev}"
DB_PASSWORD="${DB_PASSWORD:-dev}"
WEB_PORT="${WEB_PORT:-80}"
DB_PORT="${DB_PORT:-3306}"
PMA_PORT="${PMA_PORT:-8080}"
MAILPIT_SMTP_PORT="${MAILPIT_SMTP_PORT:-1025}"
MAILPIT_UI_PORT="${MAILPIT_UI_PORT:-8025}"
JENKINS_PORT="${JENKINS_PORT:-8081}"

# Docker Hub publishing: pushed images are named <DOCKERHUB_USER>/<repo>-php etc.
DOCKERHUB_USER="${DOCKERHUB_USER:-}"
DOCKERHUB_REPO="${DOCKERHUB_REPO:-${COMPOSE_PROJECT_NAME:-xampp}}"

usage() {
    cat <<EOF
Local PHP stack (XAMPP-style) with Docker.

Usage:
  ${STACK_CMD} <command> [args]

Core commands:
  up                 Start web, MySQL, phpMyAdmin and Mailpit; offers to
                     reinstall a Moodle project whose database was wiped
  up --reinstall     Same, but reinstall broken Moodle projects without asking
  up --no-reinstall  Same, but never ask
  down               Stop and remove containers (the database volume is kept)
  stop               Stop containers without removing them
  restart [service]  Restart one or all core services
  ps                 Show container status
  logs [service]     Follow logs (all services by default)
  shell [service]    Open bash in a container (default: web)
  db                 Open the MySQL client as root
  sql "<query>"      Run a SQL query as root
  build              Rebuild the PHP image
  info               Print URLs and credentials

Docker Hub:
  login              Log in to Docker Hub (uses DOCKERHUB_USER from .env)
  push [target]      Build and push images: php (default), jenkins or all

Projects:
  wp <name>          Create a WordPress site at www/<name>
  moodle <name>      Create a Moodle site at www/<name>
  vhost <name> [sub] Add an exact vhost; optional subdir sets the document root
  delete <name>      Delete a project, its vhost and database (asks to confirm)
  dump <db> [file]   Dump a database into backups/
  restore <file>     Restore a dump created by this script

CI (optional):
  ci-up              Build and start Jenkins
  ci-down            Stop Jenkins
  ci-logs            Follow Jenkins logs

Projects are served at:
  http://<name>.localhost      Apache wildcard vhost
  http://localhost/<name>      path fallback

Examples:
  ${STACK_CMD} up
  ${STACK_CMD} wp blog
  ${STACK_CMD} moodle learn
  ${STACK_CMD} dump blog
  ${STACK_CMD} ci-up
EOF
}

web_suffix() {
    if [[ "$WEB_PORT" == "80" ]]; then
        printf ''
    else
        printf ':%s' "$WEB_PORT"
    fi
}

require_name() {
    local name="${1:-}"
    if [[ -z "$name" ]]; then
        echo "A project name is required." >&2
        exit 1
    fi
    if [[ ! "$name" =~ ^[a-z][a-z0-9-]{0,30}$ ]]; then
        echo "Invalid name '$name'. Use a lowercase letter first, then lowercase letters, digits or '-'." >&2
        exit 1
    fi
}

wait_core() {
    mkdir -p data/moodledata data/apache-vhosts
    "${COMPOSE[@]}" up -d --wait db mailpit web
}

write_project_vhost() {
    local name="$1"
    local docroot="$2"
    mkdir -p data/apache-vhosts
    cat > "data/apache-vhosts/${name}.conf" <<EOF
<VirtualHost *:80>
    ServerName ${name}.localhost
    DocumentRoot ${docroot}
    UseCanonicalName Off
    DirectoryIndex index.php index.html index.htm

    <Directory ${docroot}>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/projects-error.log
    CustomLog \${APACHE_LOG_DIR}/projects-access.log combined
</VirtualHost>
EOF
    "${COMPOSE[@]}" exec -T web apachectl -k graceful >/dev/null 2>&1 || true
}

# Moodle's CLI installer writes config.php as 0640 owned by the user that ran it.
# docker compose exec runs as root, so Apache (www-data) cannot read it and Moodle
# fails with "Failed to open stream: Permission denied". Hand config.php to www-data
# (and fall back to world-readable where the mount ignores ownership).
fix_web_configs() {
    "${COMPOSE[@]}" exec -T web bash -s <<'FIX_WEB_CONFIGS' >/dev/null 2>&1 || true
set -u
shopt -s nullglob
for dir in /var/www/html/*/; do
    for file in "${dir}config.php" "${dir}public/config.php"; do
        [ -f "$file" ] || continue
        if chown www-data:www-data "$file" 2>/dev/null; then
            chmod 640 "$file" 2>/dev/null || true
        else
            chmod 644 "$file" 2>/dev/null || true
        fi
    done
done
FIX_WEB_CONFIGS
}

# Both the first install and a reinstall go through run_moodle_installer, so the
# credentials are printed here instead of in each caller. The values are the ones
# install.php was given, so they always match what is in the database.
print_moodle_credentials() {
    local name="$1" wwwroot="$2" database="$3"
    wwwroot="${wwwroot%/}"
    cat <<EOF

Moodle '${name}' is installed.
  Site       ${wwwroot}/
  Login      ${wwwroot}/login/index.php
  Username   ${MOODLE_ADMIN_USER:-admin}
  Password   ${MOODLE_ADMIN_PASSWORD:-Admin123!}
  Database   ${database}
EOF
}

# Single place that runs Moodle's CLI installer: chowns the project directory so
# the installer (running as www-data) can write, drops a stale config.php, then
# repairs config permissions. Used by both new_moodle and reinstall_moodle.
run_moodle_installer() {
    local name="$1" wwwroot="$2" dataroot="$3" database="$4"
    local dbtype="${5:-mysqli}" dbhost="${6:-db}"
    local dbuser="${7:-$DB_USER}" dbpass="${8:-$DB_PASSWORD}"
    local title="${name^}"

    # Kept non-recursive: the extracted tree is world-readable and a recursive
    # chown is very slow on Windows bind mounts.
    "${COMPOSE[@]}" exec -T web chown www-data:www-data "/var/www/html/${name}" \
        >/dev/null 2>&1 || true
    # A config.php left behind makes install.php refuse to run.
    "${COMPOSE[@]}" exec -T web rm -f "/var/www/html/${name}/config.php" \
        >/dev/null 2>&1 || true

    "${COMPOSE[@]}" exec -T -u www-data -w "/var/www/html/${name}" web php admin/cli/install.php \
        --wwwroot="$wwwroot" \
        --dataroot="$dataroot" \
        --dbtype="$dbtype" \
        --dbhost="$dbhost" \
        --dbname="$database" \
        --dbuser="$dbuser" \
        --dbpass="$dbpass" \
        --fullname="$title" \
        --shortname="$title" \
        --adminuser="${MOODLE_ADMIN_USER:-admin}" \
        --adminpass="${MOODLE_ADMIN_PASSWORD:-Admin123!}" \
        --adminemail="${MOODLE_ADMIN_EMAIL:-admin@example.test}" \
        --lang=en \
        --agree-license \
        --non-interactive

    fix_web_configs
    print_moodle_credentials "$name" "$wwwroot" "$database"
}

create_database() {
    local database="$1"
    "${COMPOSE[@]}" exec -T db mysql -uroot -p"${DB_ROOT_PASSWORD}" <<SQL
CREATE DATABASE IF NOT EXISTS \`${database}\`
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON \`${database}\`.* TO '${DB_USER}'@'%';
FLUSH PRIVILEGES;
SQL
}

# Moodle keeps all of its state in MySQL: if the database volume is recreated the
# code in www/<name> survives but the schema does not, and every request fails with
# "Error reading from database" because Moodle cannot bootstrap without mdl_config.
# Detect an empty or half-installed schema and offer to reinstall from the files
# that are already on disk.
moodle_config_value() {
    local file="$1" key="$2"
    [[ -f "$file" ]] || return 0
    awk -v key="$key" -v q="'" '
        /^[[:space:]]*(\/\/|#)/ { next }
        index($0, "$CFG->" key) && match($0, q "[^" q "]*" q) {
            print substr($0, RSTART + 1, RLENGTH - 2)
            exit
        }
    ' "$file"
}

moodle_schema_state() {
    local database="$1" prefix="$2"
    "${COMPOSE[@]}" exec -T db mysql -uroot -p"${DB_ROOT_PASSWORD}" -N -B -e "
        SELECT CONCAT(COUNT(*), ' ', COALESCE(SUM(table_name IN (
            '${prefix}config', '${prefix}course', '${prefix}user', '${prefix}modules'
        )), 0))
        FROM information_schema.tables
        WHERE table_schema = '${database}';" 2>/dev/null
}

confirm_moodle_reinstall() {
    local name="$1" answer=""
    case "${MOODLE_REINSTALL:-ask}" in
        1 | yes | true) return 0 ;;
        0 | no | false) return 1 ;;
    esac
    # Never block a non-interactive run (CI, piped stdin). Under the Windows
    # wrapper stdin is often not a tty even in a real console, so stderr counts.
    if [[ ! -t 0 && ! -t 2 ]]; then
        return 1
    fi
    printf "Reinstall '%s'? Its database is recreated; files in www/%s are kept. [Y/n] " \
        "$name" "$name"
    if ! read -r answer; then
        echo
        return 1
    fi
    case "$answer" in
        '' | y | Y | yes | YES) return 0 ;;
        *) return 1 ;;
    esac
}

reinstall_moodle() {
    local name="$1" database="$2" config="$3"
    local wwwroot dataroot dbtype dbhost dbuser dbpass suffix

    suffix="$(web_suffix)"
    wwwroot="$(moodle_config_value "$config" wwwroot)"
    [[ -n "$wwwroot" ]] || wwwroot="http://${name}.localhost${suffix}"
    dataroot="$(moodle_config_value "$config" dataroot)"
    [[ -n "$dataroot" ]] || dataroot=/var/moodledata
    dbtype="$(moodle_config_value "$config" dbtype)"
    [[ -n "$dbtype" ]] || dbtype=mysqli
    dbhost="$(moodle_config_value "$config" dbhost)"
    [[ -n "$dbhost" ]] || dbhost=db
    dbuser="$(moodle_config_value "$config" dbuser)"
    [[ -n "$dbuser" ]] || dbuser="$DB_USER"
    dbpass="$(moodle_config_value "$config" dbpass)"
    [[ -n "$dbpass" ]] || dbpass="$DB_PASSWORD"

    echo "Recreating database '$database' and reinstalling Moodle in www/${name}..."
    echo "The installer runs in the foreground; on Windows this can take several minutes."
    "${COMPOSE[@]}" exec -T db mysql -uroot -p"${DB_ROOT_PASSWORD}" \
        -e "DROP DATABASE IF EXISTS \`${database}\`;" >/dev/null
    create_database "$database"

    run_moodle_installer "$name" "$wwwroot" "$dataroot" "$database" \
        "$dbtype" "$dbhost" "$dbuser" "$dbpass"
}

check_moodle_databases() {
    local dir name config database prefix state total core

    shopt -s nullglob
    for dir in www/*/; do
        dir="${dir%/}"
        name="$(basename "$dir")"
        # Only Moodle projects: they ship version.php at the root or in public/.
        [[ -f "${dir}/public/version.php" || -f "${dir}/version.php" ]] || continue

        config="${dir}/config.php"
        [[ -f "$config" ]] || config="${dir}/public/config.php"
        database="$(moodle_config_value "$config" dbname)"
        [[ -n "$database" ]] || database="${name//-/_}"
        prefix="$(moodle_config_value "$config" prefix)"
        [[ -n "$prefix" ]] || prefix="mdl_"

        state="$(moodle_schema_state "$database" "$prefix")" || continue
        read -r total core <<< "$state"
        [[ "$total" =~ ^[0-9]+$ && "$core" =~ ^[0-9]+$ ]] || continue

        if [[ "$total" -eq 0 ]]; then
            echo "Moodle project '$name' has an empty database '$database'."
        elif [[ "$core" -lt 4 ]]; then
            echo "Moodle project '$name' has an incomplete database '$database' (${total} tables, core tables missing)."
        else
            continue
        fi
        echo "  Moodle cannot start without its tables: http://${name}.localhost/ answers \"Error reading from database\"."
        echo "  This normally means the MySQL volume was wiped or recreated."

        if confirm_moodle_reinstall "$name"; then
            reinstall_moodle "$name" "$database" "$config"
        else
            echo "  Left as is. Reinstall later with: ${STACK_CMD} up --reinstall"
            echo "  (or start over with: ${STACK_CMD} delete ${name} && ${STACK_CMD} moodle ${name})"
        fi
    done
}

print_info() {
    local suffix
    suffix="$(web_suffix)"
    cat <<EOF
Dashboard   http://localhost${suffix}/
phpMyAdmin  http://localhost:${PMA_PORT}/
Mailpit     http://localhost:${MAILPIT_UI_PORT}/
Jenkins     http://localhost:${JENKINS_PORT}/   (start with: ${STACK_CMD} ci-up)

MySQL       127.0.0.1:${DB_PORT}
            root / ${DB_ROOT_PASSWORD}
            ${DB_USER} / ${DB_PASSWORD}

Mailpit SMTP (containers): mailpit:${MAILPIT_SMTP_PORT}
Mailpit SMTP (host):       127.0.0.1:${MAILPIT_SMTP_PORT}
EOF
}

new_wordpress() {
    local name="$1"
    local database="${name//-/_}"
    local suffix url
    suffix="$(web_suffix)"
    url="http://${name}.localhost${suffix}/"

    if [[ -e "www/${name}" ]] && { [[ ! -d "www/${name}" ]] || [[ -n "$(ls -A "www/${name}")" ]]; }; then
        echo "www/${name} already exists and is not empty." >&2
        exit 1
    fi

    wait_core
    create_database "$database"

    echo "Downloading WordPress ${WORDPRESS_VERSION:-7.1.5}..."
    "${COMPOSE[@]}" exec -T web wp core download \
        --version="${WORDPRESS_VERSION:-7.1.5}" \
        --path="/var/www/html/${name}" --allow-root

    echo "Writing wp-config.php..."
    "${COMPOSE[@]}" exec -T web wp config create \
        --path="/var/www/html/${name}" \
        --dbname="$database" \
        --dbuser="$DB_USER" \
        --dbpass="$DB_PASSWORD" \
        --dbhost=db \
        --allow-root

    echo "Installing WordPress..."
    "${COMPOSE[@]}" exec -T web wp core install \
        --path="/var/www/html/${name}" \
        --url="$url" \
        --title="$name" \
        --admin_user="${WP_ADMIN_USER:-admin}" \
        --admin_password="${WP_ADMIN_PASSWORD:-admin}" \
        --admin_email="${WP_ADMIN_EMAIL:-admin@example.test}" \
        --skip-email \
        --allow-root

    "${COMPOSE[@]}" exec -T web wp config set WP_DEBUG true --raw \
        --path="/var/www/html/${name}" --allow-root >/dev/null
    "${COMPOSE[@]}" exec -T web wp config set WP_DEBUG_LOG true --raw \
        --path="/var/www/html/${name}" --allow-root >/dev/null

    # WP-CLI only writes .htaccess when mod_rewrite is declared in the config
    # file it finds from the working directory (/var/www/html).
    if [[ ! -f www/wp-cli.yml ]]; then
        printf 'apache_modules:\n  - mod_rewrite\n' > www/wp-cli.yml
    fi
    "${COMPOSE[@]}" exec -T web wp rewrite structure '/%postname%/' --hard \
        --path="/var/www/html/${name}" --allow-root >/dev/null

    cat <<EOF

WordPress is ready.
  Site       ${url}
  Admin      ${url}wp-admin/
  Username   ${WP_ADMIN_USER:-admin}
  Password   ${WP_ADMIN_PASSWORD:-admin}
  Database   ${database}
EOF
}

new_moodle() {
    local name="$1"
    local database="${name//-/_}"
    local suffix url
    suffix="$(web_suffix)"
    url="http://${name}.localhost${suffix}"

    if [[ -e "www/${name}" ]] && { [[ ! -d "www/${name}" ]] || [[ -n "$(ls -A "www/${name}")" ]]; }; then
        echo "www/${name} already exists and is not empty." >&2
        exit 1
    fi

    mkdir -p data/moodledata
    wait_core
    create_database "$database"

    local moodle_version="${MOODLE_VERSION:-5.3.1}"
    local major minor patch branch download_url
    IFS='.' read -r major minor patch <<< "$moodle_version"
    branch="$(printf '%s%02d' "$major" "$minor")"
    download_url="https://download.moodle.org/download.php/direct/stable${branch}/moodle-${moodle_version}.tgz"

    echo "Downloading Moodle ${moodle_version}..."
    "${COMPOSE[@]}" exec -T web bash -s -- "$name" "$download_url" <<'MOODLE_DOWNLOAD'
set -euo pipefail

name="$1"
url="$2"
target="/var/www/html/${name}"

mkdir -p "$target"
echo "Using ${url}"
curl -fsSL --retry 3 "$url" -o /tmp/moodle.tgz
tar -xzf /tmp/moodle.tgz -C "$target" --strip-components=1
rm -f /tmp/moodle.tgz
MOODLE_DOWNLOAD

    local docroot="/var/www/html/${name}"
    if [[ -d "www/${name}/public" ]]; then
        docroot="${docroot}/public"
    fi
    write_project_vhost "$name" "$docroot"

    echo "Installing Moodle (this can take a minute)..."
    run_moodle_installer "$name" "$url" /var/moodledata "$database"
}

dump_database() {
    local database="${1:-}"
    local file="${2:-}"
    if [[ -z "$database" ]]; then
        echo "Usage: ${STACK_CMD} dump <database> [file]" >&2
        exit 1
    fi
    if [[ -z "$file" ]]; then
        file="backups/${database}-$(date +%Y%m%d-%H%M%S).sql"
    fi
    mkdir -p "$(dirname "$file")"
    "${COMPOSE[@]}" exec -T db mysqldump -uroot -p"${DB_ROOT_PASSWORD}" \
        --single-transaction --routines --triggers --set-gtid-purged=OFF \
        --databases "$database" > "$file"
    echo "Wrote $file"
}

restore_database() {
    local file="${1:-}"
    if [[ -z "$file" || ! -f "$file" ]]; then
        echo "Usage: ${STACK_CMD} restore <file.sql>" >&2
        exit 1
    fi
    "${COMPOSE[@]}" exec -T db mysql -uroot -p"${DB_ROOT_PASSWORD}" < "$file"
    echo "Restored $file"
}

delete_project() {
    local name="$1"
    local database="${name//-/_}"
    local target="www/${name}"
    local is_moodle=0

    if [[ ! -e "$target" && ! -f "data/apache-vhosts/${name}.conf" ]]; then
        echo "Project '$name' not found." >&2
        exit 1
    fi

    if [[ -f "$target/public/version.php" || -f "$target/version.php" ]]; then
        is_moodle=1
    fi

    if [[ "${2:-}" != "--yes" ]]; then
        printf "Type '%s' to delete www/%s, its vhost and database '%s': " \
            "$name" "$name" "$database"
        local answer=""
        if ! read -r answer; then
            echo
            echo "Aborted." >&2
            exit 1
        fi
        if [[ "$answer" != "$name" ]]; then
            echo "Aborted." >&2
            exit 1
        fi
    fi

    rm -f "data/apache-vhosts/${name}.conf"
    if [[ -d "$target" ]]; then
        rm -rf "$target"
    fi
    "${COMPOSE[@]}" exec -T web apachectl -k graceful >/dev/null 2>&1 || true

    if ! "${COMPOSE[@]}" exec -T db mysql -uroot -p"${DB_ROOT_PASSWORD}" \
        -e "DROP DATABASE IF EXISTS \`${database}\`;" >/dev/null 2>&1; then
        echo "Note: database '$database' was not dropped (is the stack running?)." >&2
    fi

    echo "Deleted project '$name' (files, vhost, database '$database')."
    if [[ "$is_moodle" == "1" ]]; then
        echo "Shared Moodle uploads in data/moodledata were left in place."
    fi
}

# --- Docker Hub publishing ---------------------------------------------------
# The compose file names the images that are built locally. Pushing copies them
# under the Docker Hub account in DOCKERHUB_USER, so the same build can be pulled
# elsewhere (set PHP_IMAGE / JENKINS_IMAGE in .env to run it without building).

require_dockerhub() {
    if [[ -z "$DOCKERHUB_USER" ]]; then
        echo "Set DOCKERHUB_USER in .env to your Docker Hub username first." >&2
        echo "Optionally set DOCKERHUB_REPO (default: ${DOCKERHUB_REPO})." >&2
        exit 1
    fi
}

remote_image_name() {
    case "$1" in
        web) printf '%s/%s-php:%s' "$DOCKERHUB_USER" "$DOCKERHUB_REPO" "$PHP_VERSION" ;;
        jenkins) printf '%s/%s-jenkins:lts' "$DOCKERHUB_USER" "$DOCKERHUB_REPO" ;;
    esac
}

push_one_image() {
    local service="$1" local_image remote_image
    local profiles=()
    [[ "$service" == "jenkins" ]] && profiles=(--profile ci)

    echo "Building ${service}..."
    "${COMPOSE[@]}" "${profiles[@]}" build "$service"

    # Ask compose for the tag it built instead of guessing it.
    local_image="$("${COMPOSE[@]}" "${profiles[@]}" config --images "$service")"
    remote_image="$(remote_image_name "$service")"

    docker tag "$local_image" "$remote_image"
    docker push "$remote_image"
    echo "Pushed ${remote_image}"
}

publish_images() {
    local wanted target
    require_dockerhub
    if [[ $# -eq 0 ]]; then
        set -- php
    fi
    for wanted in "$@"; do
        case "$wanted" in
            php|web) push_one_image web ;;
            jenkins|ci) push_one_image jenkins ;;
            all)
                push_one_image web
                push_one_image jenkins
                ;;
            *)
                echo "Unknown image '$wanted'." >&2
                echo "Usage: ${STACK_CMD} push [php|jenkins|all]" >&2
                exit 1
                ;;
        esac
    done
    echo "Pull these images elsewhere with:"
    echo "  PHP_IMAGE=${DOCKERHUB_USER}/${DOCKERHUB_REPO}-php:${PHP_VERSION}"
    echo "  JENKINS_IMAGE=${DOCKERHUB_USER}/${DOCKERHUB_REPO}-jenkins:lts"
}

command="${1:-help}"
if [[ $# -gt 0 ]]; then
    shift
fi

case "$command" in
    up)
        # --reinstall / --no-reinstall answer the Moodle repair prompt up front.
        if [[ "${1:-}" == "--reinstall" ]]; then
            MOODLE_REINSTALL=1
        elif [[ "${1:-}" == "--no-reinstall" ]]; then
            MOODLE_REINSTALL=0
        fi
        mkdir -p data/moodledata data/apache-vhosts
        "${COMPOSE[@]}" up -d --wait
        # Repairs Moodle/WordPress configs left unreadable by an earlier install.
        fix_web_configs
        # A wiped MySQL volume leaves a Moodle project with no tables: offer to reinstall.
        check_moodle_databases
        print_info
        ;;
    down)
        "${COMPOSE[@]}" --profile ci down
        ;;
    stop)
        "${COMPOSE[@]}" stop
        ;;
    restart)
        if [[ $# -gt 0 ]]; then
            "${COMPOSE[@]}" restart "$@"
        else
            "${COMPOSE[@]}" restart
        fi
        ;;
    ps|status)
        "${COMPOSE[@]}" ps
        ;;
    logs)
        if [[ $# -gt 0 ]]; then
            "${COMPOSE[@]}" logs -f --tail=200 "$@"
        else
            "${COMPOSE[@]}" logs -f --tail=200
        fi
        ;;
    shell)
        "${COMPOSE[@]}" exec "${1:-web}" bash
        ;;
    db)
        "${COMPOSE[@]}" exec db mysql -uroot -p"${DB_ROOT_PASSWORD}"
        ;;
    sql)
        if [[ -z "${1:-}" ]]; then
            echo "Usage: ${STACK_CMD} sql \"SELECT 1;\"" >&2
            exit 1
        fi
        "${COMPOSE[@]}" exec -T db mysql -uroot -p"${DB_ROOT_PASSWORD}" -e "$1"
        ;;
    build)
        "${COMPOSE[@]}" build web
        ;;
    login)
        require_dockerhub
        echo "Logging in to Docker Hub as ${DOCKERHUB_USER} (use an access token as the password)."
        docker login --username "$DOCKERHUB_USER"
        ;;
    push|publish)
        publish_images "$@"
        ;;
    info)
        print_info
        ;;
    wp)
        require_name "${1:-}"
        new_wordpress "$1"
        ;;
    moodle)
        require_name "${1:-}"
        new_moodle "$1"
        ;;
    vhost)
        require_name "${1:-}"
        docroot="/var/www/html/$1"
        if [[ -n "${2:-}" ]]; then
            docroot="${docroot}/$2"
        fi
        write_project_vhost "$1" "$docroot"
        echo "Wrote data/apache-vhosts/$1.conf for http://$1.localhost/"
        ;;
    delete|remove)
        require_name "${1:-}"
        delete_project "$1" "${2:-}"
        ;;
    dump)
        dump_database "${1:-}" "${2:-}"
        ;;
    restore)
        restore_database "${1:-}"
        ;;
    ci-up)
        "${COMPOSE[@]}" --profile ci up -d --build --wait jenkins
        echo "Jenkins: http://localhost:${JENKINS_PORT}/"
        ;;
    ci-down)
        "${COMPOSE[@]}" --profile ci stop jenkins
        ;;
    ci-logs)
        "${COMPOSE[@]}" --profile ci logs -f --tail=200 jenkins
        ;;
    help|-h|--help)
        usage
        ;;
    *)
        usage >&2
        exit 1
        ;;
esac
