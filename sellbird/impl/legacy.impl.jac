impl adopt_legacy_env(environ=environ_default_) -> list[str] {
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

impl _old_process_running(`root: Path) -> int | None {
    import from sellbird.pidfile { pid_alive, read_pid }
    pid: any = read_pid(`root / OLD_PID);
    return pid if pid and pid_alive(pid) else None;
}

impl migrate_files(`root: Path = root_default_) -> list[str] {
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

impl _leave_welcome(`root: Path) -> None {
    try {
        (`root / WELCOME).parent.mkdir(parents=True, exist_ok=True);
        (`root / WELCOME).write_text(
            "Harvey's files moved to Sellbird's names. The dashboard says so once, then deletes this.\n",
            encoding="utf-8",
        );
    } except OSError {}
}

impl welcome_pending(`root: Path | None = None) -> bool {
    return ((`root or PROJECT_ROOT) / WELCOME).exists();
}

impl dismiss_welcome(`root: Path | None = None) -> None {
    try {
        ((`root or PROJECT_ROOT) / WELCOME).unlink(missing_ok=True);
    } except OSError {}
}
