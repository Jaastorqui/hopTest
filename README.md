# hopTest

Mock migration: MS SQL Server (acquired company) -> MariaDB (our platform), via Apache Hop.

## Start the databases

```bash
docker compose up -d
```

Source seeds itself (`mssql/init.sql`), target schema is created empty (`mariadb/init.sql`).

## Register the Hop project

```bash
$HOP_HOME/hop-conf.sh -pc -p oferta -ph "$(pwd)/hop"
```

## Run the migration

```bash
./bin/hop-migrate.sh              # all pipelines, in FK order
./bin/hop-migrate.sh hop/pipelines/02-accounts.hpl   # just one
```

Logs land in `hop/logs/`.

## Run the unit tests

```bash
./bin/hop-test.sh                 # no database needed; fails on a golden-data mismatch
```

## Reset the target

```bash
./bin/reset-target.sh             # truncates every table in `marketplace`
```

## Open the GUI

```bash
JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home \
HOP_PROJECT=oferta $HOP_HOME/hop-gui.sh
```

## Check the result

```bash
docker compose exec -T mariadb mariadb -uroot -proot marketplace -e "
SELECT merge_source, COUNT(*) FROM accounts GROUP BY merge_source;"
```
