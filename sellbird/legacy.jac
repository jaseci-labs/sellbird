"""Carrying an install over from Harvey, Sellbird's old name.

People run Sellbird from a clone and update with ``git pull``. A clone made
while the project was called Harvey has its own files under the old names
(``harvey.local.yaml``, ``data/harvey.db`` and its log), and may set
``HARVEY_*`` environment variables. This module moves those across once,
quietly and safely, so an update never looks like lost data:

- A file is renamed only when nothing exists under the new name. Nothing of
  the user's is overwritten or deleted; a conflict is reported and left for a
  person. (A dead process's pidfile is the one thing removed.)
- Nothing moves while a Harvey process is still running from this folder,
  because it would keep writing to the old files.
- ``HARVEY_X`` is honoured when ``SELLBIRD_X`` is unset, and never wins over it.

The file moves are kept permanently: someone may pull years from now. Only
the ``harvey`` command (the package next to this one) is temporary.
"""

import from __future__ { annotations }

import os;

import from pathlib { Path }

glob FILES: any = [
    ("harvey.local.yaml", "sellbird.local.yaml"),
    ("data/harvey.db", "data/sellbird.db"),
    ("data/harvey.db-wal", "data/sellbird.db-wal"),
    ("data/harvey.db-shm", "data/sellbird.db-shm"),
    ("data/harvey.log", "data/sellbird.log"),
];

glob OLD_PID: any = "data/harvey.pid";

glob WELCOME: any = "data/renamed-from-harvey";

glob ENV_PREFIX_OLD: any;

glob ENV_PREFIX_NEW: any;

with entry {
    (ENV_PREFIX_OLD, ENV_PREFIX_NEW) = ("HARVEY_", "SELLBIRD_");
    environ_default_ = os.environ;
}

glob environ_default_: any;

"""Copy each ``HARVEY_X`` to ``SELLBIRD_X`` where that is unset. Returns
    the new names it set, so a command can mention them once."""
def adopt_legacy_env(environ=environ_default_) -> list[str];

def _old_process_running(`root: Path) -> int | None;

glob root_default_: any;

with entry {
    root_default_ = PROJECT_ROOT;
}

"""Rename this install's Harvey-era files. Returns one line per thing
    done or left alone, for the caller to show; empty when there was nothing."""
def migrate_files(`root: Path = root_default_) -> list[str];

def _leave_welcome(`root: Path) -> None;

"""True until the dashboard's "Harvey is now Sellbird" notice is dismissed."""
def welcome_pending(`root: Path | None = None) -> bool;

def dismiss_welcome(`root: Path | None = None) -> None;
