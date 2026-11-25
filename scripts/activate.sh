# Source this from the Sellbird checkout, after `neojac install && neojac build`:
#   source scripts/activate.sh
# It puts neojac's build of Sellbird first on Python's path, uses the project's
# environment (.jac/venv), and gives this shell a `sellbird` command. Rebuild
# with `neojac build` after changing any .jac file.
SELLBIRD_CHECKOUT="$(pwd)"
export PYTHONPATH="$SELLBIRD_CHECKOUT/.jac/build/pypi/top/site"
export PATH="$SELLBIRD_CHECKOUT/.jac/venv/bin:$PATH"
sellbird() { python -m sellbird "$@"; }
harvey() { python -m harvey "$@"; }
