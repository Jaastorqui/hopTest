#!/bin/sh
# Headless Hop runner. Usage: bin/hop-migrate.sh [pipelines/a.hpl ...]
# With no arguments, runs every numbered pipeline in filename order.
# Runs pipelines in the order given and stops at the first failure (FK order matters).
set -eu

# cron gives you almost no environment, so everything is explicit here.
: "${HOP_HOME:=/Users/jon.ibanez/Downloads/hop}"
: "${JAVA_HOME:=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home}"
: "${HOP_PROJECT:=oferta}"
: "${HOP_RUNCONFIG:=local}"
# Hop parses date STRINGS using the JVM default timezone - the field-level
# "date format timezone" only affects rendering back out. Their MS SQL box runs UTC,
# so the JVM has to be UTC or every timestamp lands two hours out in summer.
# MariaDB is Europe/Oslo, so the instant is displayed as Norwegian wall-clock.
: "${HOP_OPTIONS:=-Duser.timezone=UTC}"
export HOP_OPTIONS
export JAVA_HOME
export PATH="$JAVA_HOME/bin:$PATH"

LOG_DIR="$(cd "$(dirname "$0")/.." && pwd)/hop/logs"
mkdir -p "$LOG_DIR"
STAMP=$(date +%Y%m%d-%H%M%S)

# No arguments: the whole migration. The 01-..10- prefixes are the FK order.
if [ $# -eq 0 ]; then
    set -- "$(cd "$(dirname "$0")/.." && pwd)"/hop/pipelines/[0-9]*.hpl
    [ -e "$1" ] || { echo "no numbered pipelines found" >&2; exit 2; }
fi

for pipeline in "$@"; do
    # hop-run rejects relative paths, so resolve anything the caller passed by hand.
    case "$pipeline" in /*) ;; *) pipeline="$(cd "$(dirname "$pipeline")" && pwd)/$(basename "$pipeline")" ;; esac
    name=$(basename "$pipeline" .hpl)
    log="$LOG_DIR/${STAMP}-${name}.log"
    echo "--> $name  (log: $log)"
    if ! sh "$HOP_HOME/hop-run.sh" \
            -j "$HOP_PROJECT" -r "$HOP_RUNCONFIG" -f "$pipeline" \
            -l BASIC -lf "$log"; then
        echo "FAILED: $name — see $log" >&2
        exit 1
    fi
    # hop-run exits 0 even on pipeline errors in some versions; check the log too.
    if grep -qE 'ERROR|Errors detected' "$log"; then
        echo "FAILED: $name reported errors — see $log" >&2
        exit 1
    fi
done
echo "all pipelines ok"
