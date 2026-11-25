import os;
import from pathlib { Path }

glob FILES = [
         ("harvey.local.yaml", "sellbird.local.yaml"),
         ("data/harvey.db", "data/sellbird.db"),
         ("data/harvey.db-wal", "data/sellbird.db-wal"),
         ("data/harvey.db-shm", "data/sellbird.db-shm"),
         ("data/harvey.log", "data/sellbird.log"),
     ],
     OLD_PID = "data/harvey.pid",
     WELCOME = "data/renamed-from-harvey",
     ENV_PREFIX_OLD = "HARVEY_",
     ENV_PREFIX_NEW = "SELLBIRD_";

def adopt_legacy_env(environ: any = os.environ) -> list[str] {
    adopted: list[str] = [];
    for (name, value) in list(environ.items()) {
        new = ENV_PREFIX_NEW + name[len(ENV_PREFIX_OLD):];
        if name.startswith(ENV_PREFIX_OLD) and new not in environ {
            environ[new] = value;
            adopted.append(new);
        }
    }
    return sorted(adopted);
}

def _old_process_running(`root: Path) -> int | None {
    import from sellbird.pidfile { pid_alive, read_pid }
    pid = read_pid(`root / OLD_PID);
    return pid if pid and pid_alive(pid) else None;
}

def _move(`root: Path, old: Path, new: Path) -> str {
    (old_name, new_name) = (old.relative_to(`root).as_posix(), new.relative_to(`root).as_posix());
    if new.exists() {
        return f"Left {old_name} alone: {new_name} already exists. Compare them and keep the one you want.";
    }
    try {
        old.rename(new);
    } except OSError as e {
        return f"Couldn't move {old_name} to {new_name}: {e.strerror or e}";
    }
    return f"Moved {old_name} to {new_name}.";
}

def migrate_files(`root: Path = PROJECT_ROOT) -> list[str] {
    pending = [(`root / old, `root / new) for (old, new) in FILES if (`root / old).exists()];
    if not pending {
        return [];
    }
    pid = _old_process_running(`root);
    if pid {
        return [
            f"Harvey is still running here (process {pid}). Stop it, then run Sellbird again to move its files over.",
        ];
    }
    notes = [_move(`root, old, new) for (old, new) in pending];
    if any([n.startswith("Moved ") for n in notes]) {
        _leave_welcome(`root);
    }
    try {
        (`root / OLD_PID).unlink(missing_ok=True);
    } except OSError {}
    return notes;
}

def _leave_welcome(`root: Path) {
    try {
        (`root / WELCOME).parent.mkdir(parents=True, exist_ok=True);
        (`root / WELCOME).write_text(
            "Harvey's files moved to Sellbird's names. The dashboard says so once, then deletes this.\n",
            encoding="utf-8",
        );
    } except OSError {}
}

def welcome_pending(`root: Path | None = None) -> bool {
    return ((`root or PROJECT_ROOT) / WELCOME).exists();
}

def dismiss_welcome(`root: Path | None = None) {
    try {
        ((`root or PROJECT_ROOT) / WELCOME).unlink(missing_ok=True);
    } except OSError {}
}
