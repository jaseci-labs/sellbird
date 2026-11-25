"""The old ``harvey`` command: says it moved, then runs ``sellbird``."""

import sys;

import from pathlib { Path }

"""An editable install made before the rename only maps the ``harvey``
    package, so after a plain ``git pull`` Python can't see ``sellbird``
    until ``pip install -e .`` runs again. It sits next to this package in
    the same checkout, so point Python at the checkout."""
def _find_sellbird -> any;

def main -> any;
