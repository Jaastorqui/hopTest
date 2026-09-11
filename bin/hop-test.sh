#!/bin/sh
# Runs the Hop pipeline unit tests. Exits non-zero if any golden data set does not match.
set -eu

: "${HOP_HOME:=/Users/jon.ibanez/Downloads/hop}"
: "${JAVA_HOME:=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home}"
: "${HOP_PROJECT:=oferta}"
: "${HOP_RUNCONFIG:=local}"
: "${HOP_OPTIONS:=-Duser.timezone=UTC}"
export JAVA_HOME HOP_OPTIONS
export PATH="$JAVA_HOME/bin:$PATH"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec sh "$HOP_HOME/hop-run.sh" -j "$HOP_PROJECT" -r "$HOP_RUNCONFIG" \
     -f "$ROOT/hop/workflows/run-tests.hwf" -l BASIC
