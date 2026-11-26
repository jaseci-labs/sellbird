# Shared settings for the benchmarks. Source it; override any of these first.
#   SELLBIRD_BASE  a checkout of the original Python (commit b21238525)
#   PERF_DIR       scratch folder for the seeded homes and results
REPO="${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
SELLBIRD_BASE="${SELLBIRD_BASE:?set SELLBIRD_BASE to a checkout of the original Python}"
PERF_DIR="${PERF_DIR:-/tmp/sbperf}"
PY="$REPO/.jac/venv/bin/python"
export REPO SELLBIRD_BASE PERF_DIR PY
# Both run on the same interpreter and packages (.jac/venv); a fake HOME keeps
# the live Claude quota and the user's settings out of it.
export HOME="$PERF_DIR/fakehome" CLAUDE_CONFIG_DIR="$PERF_DIR/fakehome/.claude" PYTHONSAFEPATH=1
mkdir -p "$HOME"
runb() { ( cd "$PERF_DIR/home_base" && SELLBIRD_HOME="$PERF_DIR/home_base" PYTHONPATH="$SELLBIRD_BASE" "$PY" "$@" ); }
runj() { ( cd "$PERF_DIR/home_jac" && SELLBIRD_HOME="$PERF_DIR/home_jac" PYTHONPATH="$REPO/.jac/build/pypi/top/site" "$PY" "$@" ); }
