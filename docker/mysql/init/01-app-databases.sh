#!/usr/bin/env bash
set -euo pipefail

for db in wordpress moodle; do
  mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" <<SQL
CREATE DATABASE IF NOT EXISTS \`${db}\`
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON \`${db}\`.* TO '${MYSQL_USER}'@'%';
FLUSH PRIVILEGES;
SQL
done
