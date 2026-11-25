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
def adopt_legacy_env(environ=environ_default_) -> list[str] {
    adopted: any = [];
    for (name, value) in `list(environ.items()) {
        if not name.startswith(ENV_PREFIX_OLD) {
            continue;
        }
        new: any = ENV_PREFIX_NEW + name[len(ENV_PREFIX_OLD):];
        if new not in environ {
            environ[new] = value;
            adopted.append(new);
        }
    }
    return sorted(adopted);
}

def _old_process_running(`root: Path) -> int | None {
    import from sellbird.pidfile { pid_alive, read_pid }
    pid: any = read_pid(`root / OLD_PID);
    return pid if pid and pid_alive(pid) else None;
}

glob root_default_: any;

with entry {
    root_default_ = PROJECT_ROOT;
}

"""Rename this install's Harvey-era files. Returns one line per thing
    done or left alone, for the caller to show; empty when there was nothing."""
def migrate_files(`root: Path = root_default_) -> list[str] {
    old: any;
    new: any;
    pending: any = [(`root / old, `root / new) for (old, new) in FILES if (`root / old).exists()];
    if not pending {
        return [];
    }
    pid: any = _old_process_running(`root);
    if pid {
        return [
            f"Harvey is still running here (process {pid}). Stop it, then run Sellbird again to move its files over.",
        ];
    }
    notes: any = [];
    for (old, new) in pending {
        old_name: any;
        new_name: any;
        (old_name, new_name) = (
            old.relative_to(`root).as_posix(),
            new.relative_to(`root).as_posix(),
        );
        if new.exists() {
            notes.append(
                f"Left {old_name} alone: {new_name} already exists. Compare them and keep the one you want.",
            );
            continue;
        }
        try {
            old.rename(new);
        } except OSError as e {
            notes.append(f"Couldn't move {old_name} to {new_name}: {e.strerror or e}");
            continue;
        }
        notes.append(f"Moved {old_name} to {new_name}.");
    }
    if `any(n.startswith("Moved ") for n in notes) {
        _leave_welcome(`root);
    }
    stale: any = `root / OLD_PID;
    if stale.exists() {
        try {
            stale.unlink();
        } except OSError {}
    }
    return notes;
}

def _leave_welcome(`root: Path) -> None {
    try {
        (`root / WELCOME).parent.mkdir(parents=True, exist_ok=True);
        (`root / WELCOME).write_text(
            "Harvey's files moved to Sellbird's names. The dashboard says so once, then deletes this.\n",
            encoding="utf-8",
        );
    } except OSError {}
}

"""True until the dashboard's "Harvey is now Sellbird" notice is dismissed."""
def welcome_pending(`root: Path | None = None) -> bool {
    return ((`root or PROJECT_ROOT) / WELCOME).exists();
}

def dismiss_welcome(`root: Path | None = None) -> None {
    try {
        ((`root or PROJECT_ROOT) / WELCOME).unlink(missing_ok=True);
    } except OSError {}
}
