#!/bin/sh
# Truncate every table in the MariaDB target so the pipelines can re-run clean.
# Table list comes from information_schema, so new tables are picked up
# automatically. System schemas are never touched.
set -eu
DB="${1:-marketplace}"

docker compose exec -T mariadb sh -c "
  mariadb -uroot -proot -N -B -e \"
    SELECT CONCAT('TRUNCATE TABLE \\\`', table_name, '\\\`;')
    FROM information_schema.tables
    WHERE table_schema = '$DB' AND table_type = 'BASE TABLE';\" \
  | { echo 'SET FOREIGN_KEY_CHECKS=0;'; cat; } \
  | mariadb -uroot -proot '$DB'
" 2>&1 | grep -v '^Warning: ' || true

docker compose exec -T mariadb mariadb -uroot -proot "$DB" -N -B -e "
  SELECT CONCAT(table_name, '=', table_rows)
  FROM information_schema.tables
  WHERE table_schema = '$DB' AND table_type = 'BASE TABLE'
  ORDER BY table_name;" 2>&1 | grep -v '^Warning: ' | tr '\n' ' '
echo
