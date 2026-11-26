#!/usr/bin/env bash
# Seed one fictional database (1,500 companies) with the original code and copy
# it, with the shipped config, prompts and skills, into a home for each side.
set -e
. "$(dirname "$0")/common.sh"
mkdir -p "$PERF_DIR/seed/data"
rm -f "$PERF_DIR/seed/data/sellbird.db"
( cd "$PERF_DIR" && PYTHONPATH="$SELLBIRD_BASE" "$PY" "$REPO/scripts/perf/seed.py" "$PERF_DIR/seed/data/sellbird.db" "${1:-1500}" )
for side in base jac ${JAC_BEFORE:+before}; do
  h="$PERF_DIR/home_$side"; rm -rf "$h"; mkdir -p "$h"
  cp -r "$PERF_DIR/seed/data" "$h/"
  cp "$SELLBIRD_BASE/sellbird.yaml" "$h/"; cp -r "$SELLBIRD_BASE/skills" "$SELLBIRD_BASE/prompts" "$h/"
done
