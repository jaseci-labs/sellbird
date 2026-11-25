impl _pid_alive_windows(pid: builtins.int) -> builtins.bool {
    import ctypes;
    import from ctypes { wintypes }

    kernel32: any = ctypes.WinDLL("kernel32", use_last_error=True);
    kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD];
    kernel32.OpenProcess.restype = wintypes.HANDLE;
    kernel32.GetExitCodeProcess.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD)];
    kernel32.GetExitCodeProcess.restype = wintypes.BOOL;
    kernel32.CloseHandle.argtypes = [wintypes.HANDLE];

    handle: any = kernel32.OpenProcess(_PROCESS_QUERY_LIMITED_INFORMATION, False, pid);
    if not handle {
        return operator.eq(ctypes.get_last_error(), _ERROR_ACCESS_DENIED);
    }
    try {
        code: any = wintypes.DWORD();
        if not kernel32.GetExitCodeProcess(handle, ctypes.byref(code)) {
            return False;
        }
        return operator.eq(code.value, _STILL_ACTIVE);
    } finally {
        kernel32.CloseHandle(handle);
    }
}

impl pid_alive(pid: builtins.int) -> builtins.bool {
    if pid <= 0 {
        return False;
    }
    if sys.platform == "win32" {
        return _pid_alive_windows(pid);
    }
    try {
        os.kill(pid, 0);
    } except ProcessLookupError {
        return False;
    } except PermissionError {
        return True;
    } except OSError {
        return False;
    }
    return True;
}

impl read_pid(path: Path | None = None) -> builtins.int | None {
    path = path or PID_FILE;
    try {
        return `int(path.read_text(encoding="utf-8").strip());
    } except (OSError, ValueError) {
        return None;
    }
}

impl write_pid_file(path: Path | None = None) -> None {
    path = path or PID_FILE;
    try {
        path.parent.mkdir(parents=True, exist_ok=True);
        path.write_text(`str(os.getpid()), encoding="utf-8");
    } except OSError as e {
        logger.warning("Could not write PID file: %s", e);
    }
}

impl remove_pid_file(path: Path | None = None) -> None {
    path = path or PID_FILE;
    if read_pid(path) == os.getpid() {
        try {
            path.unlink(missing_ok=True);
        } except OSError as e {
            logger.warning("Could not remove PID file: %s", e);
        }
    }
}

impl _try_lock(handle) -> builtins.bool {
    try {
        if sys.platform == "win32" {
            import msvcrt;
            handle.seek(0);
            msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1);
        } else {
            import fcntl;
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB);
        }
    } except OSError {
        return False;
    }
    return True;
}

impl _unlock(handle) -> None {
    try {
        if sys.platform == "win32" {
            import msvcrt;
            handle.seek(0);
            msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1);
        } else {
            import fcntl;
            fcntl.flock(handle.fileno(), fcntl.LOCK_UN);
        }
    } except OSError {}
}

impl hold_loop_lock(path: Path | None = None) -> any {
    path = path or LOCK_FILE;
    try {
        path.parent.mkdir(parents=True, exist_ok=True);
        handle: any = open(path, "a+b");
    } except OSError as e {
        logger.warning("Could not open the loop lock: %s", e);
        return None;
    }
    for attempt in range(10) {
        if _try_lock(handle) {
            return handle;
        }
        time.sleep(0.01 * (attempt + 1));
    }
    handle.close();
    return None;
}

impl release_loop_lock(handle) -> None {
    if handle is None {
        return;
    }
    _unlock(handle);
    handle.close();
}

impl loop_lock_held(path: Path | None = None) -> builtins.bool {
    path = path or LOCK_FILE;
    if not path.exists() {
        return False;
    }
    try {
        handle: any = open(path, "a+b");
    } except OSError {
        return False;
    }
    try {
        if _try_lock(handle) {
            _unlock(handle);
            return False;
        }
        return True;
    } finally {
        handle.close();
    }
}
