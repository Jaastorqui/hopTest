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
./bin/reset-melvis.sh             # drop + rebuild `melvis`, including the pre-existing seed
```

## Open the GUI

```bash
JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home \
HOP_PROJECT=oferta $HOP_HOME/hop-gui.sh
```

## Check the result

```bash
docker compose exec -T mariadb mariadb -uroot -proot melvis -e "
SELECT COUNT(*) AS master_ids, SUM(mi_co_id>0) AS matched_existing, SUM(mi_co_id=0) AS minted
FROM customer_master_id_lookup;"
```

## Constantine constants

`hop/datasets/constantine.csv` holds all 420 x-consts, copied from
`apps/melvis/Core/Tools/Constantine.php`. It is committed, so nothing here needs a melvis
checkout. `00-constantine.hpl` loads it into the `constantine` table and the pipelines
resolve `mi_rel_type` against that.

To refresh it when the PHP changes, from a melvis checkout:

```bash
grep -oE 'const [A-Za-z_]+ *= *[0-9]+' Core/Tools/Constantine.php \
  | sed -E 's/const ([A-Za-z_]+) *= *([0-9]+)/\2,\1/'
```

then reconcile against `ConstantineMapping` for the module and app class columns.
