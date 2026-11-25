"""The old ``harvey`` command: says it moved, then runs ``sellbird``."""

import sys;

import from pathlib { Path }

"""An editable install made before the rename only maps the ``harvey``
    package, so after a plain ``git pull`` Python can't see ``sellbird``
    until ``pip install -e .`` runs again. It sits next to this package in
    the same checkout, so point Python at the checkout."""
def _find_sellbird -> any {
    try {
        import sellbird;
    } except ModuleNotFoundError {
        checkout: any = Path(__file__).resolve().parent.parent;
        if (checkout / "sellbird" / "__init__.py").is_file() {
            sys.path.insert(0, `str(checkout));
        }
    }
}

def main -> any {
    print(NOTICE, file=sys.stderr);
    _find_sellbird();
    import from sellbird.cli { main as sellbird_main }
    sys.argv[0] = "sellbird";
    return sellbird_main();
}
