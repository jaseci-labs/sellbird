import logging;

import os;

import sys;

import time;

import from pathlib { Path }

glob logger = logging.getLogger("sellbird.pidfile"),
     PID_FILE = PROJECT_ROOT / "data" / "sellbird.pid",
     LOCK_FILE = PROJECT_ROOT / "data" / "sellbird.lock",
     _PROCESS_QUERY_LIMITED_INFORMATION = 4096,
     _STILL_ACTIVE = 259,
     _ERROR_ACCESS_DENIED = 5;

def _pid_alive_windows(pid: int) -> bool {
    import ctypes;
    import from ctypes { wintypes }

    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True);
    kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD];
    kernel32.OpenProcess.restype = wintypes.HANDLE;
    kernel32.GetExitCodeProcess.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD)];
    kernel32.GetExitCodeProcess.restype = wintypes.BOOL;
    kernel32.CloseHandle.argtypes = [wintypes.HANDLE];

    handle = kernel32.OpenProcess(_PROCESS_QUERY_LIMITED_INFORMATION, False, pid);
    if not handle {
        return ctypes.get_last_error() == _ERROR_ACCESS_DENIED;
    }
    try {
        code = wintypes.DWORD();
        return bool(kernel32.GetExitCodeProcess(handle, ctypes.byref(code)))
            and code.value == _STILL_ACTIVE;
    } finally {
        kernel32.CloseHandle(handle);
    }
}

def pid_alive(pid: int) -> bool {
    if pid <= 0 {
        return False;
    }
    if sys.platform == "win32" {
        return _pid_alive_windows(pid);
    }
    try {
        os.kill(pid, 0);
    } except PermissionError {
        return True;
    } except OSError {
        return False;
    }
    return True;
}

def read_pid(path: Path | None = None) -> int | None {
    path = path or PID_FILE;
    try {
        return int(path.read_text(encoding="utf-8").strip());
    } except (OSError, ValueError) {
        return None;
    }
}

def write_pid_file(path: Path | None = None) {
    path = path or PID_FILE;
    try {
        path.parent.mkdir(parents=True, exist_ok=True);
        path.write_text(str(os.getpid()), encoding="utf-8");
    } except OSError as e {
        logger.warning("Could not write PID file: %s", e);
    }
}

def remove_pid_file(path: Path | None = None) {
    path = path or PID_FILE;
    if read_pid(path) == os.getpid() {
        try {
            path.unlink(missing_ok=True);
        } except OSError as e {
            logger.warning("Could not remove PID file: %s", e);
        }
    }
}

def _lock(handle: any, take: bool = True) -> bool {
    try {
        if sys.platform == "win32" {
            import msvcrt;
            handle.seek(0);
            msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK if take else msvcrt.LK_UNLCK, 1);
        } else {
            import fcntl;
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB if take else fcntl.LOCK_UN);
        }
    } except OSError {
        return False;
    }
    return True;
}

def hold_loop_lock(path: Path | None = None) -> any {
    path = path or LOCK_FILE;
    try {
        path.parent.mkdir(parents=True, exist_ok=True);
        handle = open(path, "a+b");
    } except OSError as e {
        logger.warning("Could not open the loop lock: %s", e);
        return None;
    }
    for attempt in range(10) {
        if _lock(handle) {
            return handle;
        }
        time.sleep(0.01 * (attempt + 1));
    }
    handle.close();
    return None;
}

def release_loop_lock(handle: any) {
    if handle is not None {
        _lock(handle, take=False);
        handle.close();
    }
}

def loop_lock_held(path: Path | None = None) -> bool {
    path = path or LOCK_FILE;
    if not path.exists() {
        return False;
    }
    try {
        handle = open(path, "a+b");
    } except OSError {
        return False;
    }
    try {
        held = not _lock(handle);
        if not held {
            _lock(handle, take=False);
        }
        return held;
    } finally {
        handle.close();
    }
}
