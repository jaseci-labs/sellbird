import importlib;
import json;
import ntpath;
import os;
import plistlib;
import shutil;
import subprocess;
import sys;
import tempfile;
import time;
import from dataclasses { dataclass }
import from pathlib { Path, PureWindowsPath }
import from typing { Callable, Mapping }

glob LABEL = "com.sellbird.tray",
     MARKER = "Created by Sellbird",
     PLIST_COMMENT = "<!-- Created by Sellbird. Remove with: sellbird autostart uninstall -->",
     WINDOWS_SHORTCUT = "Sellbird tray.lnk",
     LAUNCHCTL = "/bin/launchctl",
     BOOTSTRAP_RETRY_WAIT = 1.0,
     _SHORTCUT_OPEN = "$ErrorActionPreference = 'Stop'; $s = (New-Object -ComObject WScript.Shell).CreateShortcut($env:OL_LNK); ",
     _READ_SCRIPT = _SHORTCUT_OPEN
         + "@{Description = $s.Description; TargetPath = $s.TargetPath; Arguments = $s.Arguments} | ConvertTo-Json -Compress",
     _CREATE_SCRIPT = _SHORTCUT_OPEN
         + "$s.TargetPath = $env:OL_TARGET; $s.Arguments = $env:OL_ARGS; $s.WorkingDirectory = $env:OL_WORKDIR; $s.Description = $env:OL_DESC; $s.Save()";

class UnsupportedPlatform(Exception) {
    def init(message: str = "Start at login works on macOS and Windows.") {
        super.init(message);
    }
}

class ForeignLoginItem(Exception) {
    has path: any = None;

    def init(path: Path) {
        self.path = path;
        super.init(f"{path} exists and wasn't created by Sellbird. Nothing was changed.");
    }
}

class LoginItemFailed(Exception) {}

@dataclass(frozen=True)
class LoginItemResult {
    has changed: bool,
        path: Path,
        message: str;
}

def _why(e: OSError) -> str {
    return e.strerror or type(e).__name__;
}

def login_item_path(
    platform: str | None = None, env: Mapping[str, str] | None = None, home: Path | None = None
) -> Path {
    platform = sys.platform if platform is None else platform;
    env = os.environ if env is None else env;
    if platform == "darwin" {
        return Path(
            Path.home() if home is None else home, "Library", "LaunchAgents", f"{LABEL}.plist"
        );
    }
    if platform != "win32" {
        raise UnsupportedPlatform();
    }
    if not env.get("APPDATA") {
        raise LoginItemFailed("APPDATA isn't set, so the Windows Startup folder can't be found.");
    }
    return Path(
        env["APPDATA"],
        "Microsoft",
        "Windows",
        "Start Menu",
        "Programs",
        "Startup",
        WINDOWS_SHORTCUT,
    );
}

def tray_argv(platform: str | None = None, port: int | None = None) -> list[str] {
    python: str = sys.executable;
    pythonw = Path(python).with_name("pythonw.exe");
    if (sys.platform if platform is None else platform) == "win32" and pythonw.exists() {
        python = str(pythonw);
    }
    return [python, "-P", "-m", "sellbird", "tray"]
        + (["--port", str(port)] if port is not None else []);
}

def render_plist(
    argv: list[str],
    path_env: str,
    home_env: str | None,
    log_path: Path,
    working_dir: Path | None = None,
) -> bytes {
    data = plistlib.dumps({
        "Label": LABEL,
        "ProgramArguments": list(argv),
        "RunAtLoad": True,
        "KeepAlive": {"SuccessfulExit": False},
        "ProcessType": "Interactive",
        "LimitLoadToSessionType": "Aqua",
        "EnvironmentVariables": {"PATH": path_env} | ({HOME_ENV: home_env} if home_env else {}),
        "WorkingDirectory": str(PROJECT_ROOT if working_dir is None else working_dir),
        "StandardOutPath": str(log_path),
        "StandardErrorPath": str(log_path),
    });
    lines = data.split(b"\n");
    doctype = next(i for (i, line) in enumerate(lines) if line.startswith(b"<!DOCTYPE"));
    lines.insert(doctype + 1, PLIST_COMMENT.encode("utf-8"));
    return b"\n".join(lines);
}

def is_ours_plist(data: bytes) -> bool {
    if PLIST_COMMENT.encode("utf-8") not in data {
        return False;
    }
    try {
        parsed = plistlib.loads(data);
    } except Exception {
        return False;
    }
    return isinstance(parsed, dict) and parsed.get("Label") == LABEL;
}

def _uid -> int {
    return getattr(os, "getuid", lambda -> int { 0 })();
}

def _launchctl(runner: any, *args: str) -> any {
    return runner([LAUNCHCTL, *args], capture_output=True, text=True);
}

def _read_bytes(path: Path) -> bytes {
    try {
        return path.read_bytes();
    } except OSError as e {
        raise LoginItemFailed(f"Couldn't read {path} ({_why(e)}). Nothing was changed.") from None;
    }
}

def _remove(path: Path) -> LoginItemResult {
    try {
        path.unlink();
    } except OSError as e {
        raise LoginItemFailed(f"Couldn't remove {path} ({_why(e)}).") from None;
    }
    return LoginItemResult(True, path, "Start at login is off.");
}

def _run_powershell(
    runner: any, script: str, env: Mapping[str, str], extra: Mapping[str, str]
) -> any {
    sysroot = env.get("SystemRoot") or env.get("SYSTEMROOT") or r"C:\Windows";
    shell = shutil.which("powershell", path=env.get("PATH"))
        or str(PureWindowsPath(sysroot, "System32", "WindowsPowerShell", "v1.0", "powershell.exe"));
    return runner(
        [shell, "-NoProfile", "-NonInteractive", "-Command", script],
        env={**env, **extra},
        capture_output=True,
        text=True,
    );
}

def read_shortcut(
    path: Path, runner: any = subprocess.run, env: Mapping[str, str] | None = None
) -> dict[str, str] | None {
    if not Path(path).exists() {
        return None;
    }
    blank = {"Description": "", "TargetPath": "", "Arguments": ""};
    proc = _run_powershell(
        runner, _READ_SCRIPT, os.environ if env is None else env, {"OL_LNK": str(path)}
    );
    try {
        data = json.loads(proc.stdout or "") if proc.returncode == 0 else None;
    } except ValueError {
        return blank;
    }
    return {key: str(data.get(key) or "") for key in blank} if isinstance(data, dict) else blank;
}

def _same_windows_path(a: str, b: str) -> bool {
    return ntpath.normcase(ntpath.normpath(a)) == ntpath.normcase(ntpath.normpath(b));
}

def _user_registry_env(name: str) -> str | None {
    try {
        winreg = importlib.import_module("winreg");
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment") as key {
            return str(winreg.QueryValueEx(key, name)[0]);
        }
    } except Exception {
        return None;
    }
}

def _target(
    platform: str | None, env: Mapping[str, str] | None, home: Path | None
) -> tuple[str, Mapping[str, str], Path] {
    platform = sys.platform if platform is None else platform;
    env = os.environ if env is None else env;
    return (platform, env, login_item_path(platform, env, home));
}

def install(
    *,
    platform: str | None = None,
    runner: any = subprocess.run,
    env: Mapping[str, str] | None = None,
    home: Path | None = None,
    port: int | None = None,
    user_env: Callable[[str], str | None] = _user_registry_env,
    sleep: Callable[[float], None] = time.sleep,
) -> LoginItemResult {
    (platform, env, path) = _target(platform, env, home);
    if platform == "darwin" {
        home_env = (env.get(HOME_ENV) or "").strip();
        log_path = PROJECT_ROOT / "data" / "tray.log";
        data = render_plist(
            tray_argv("darwin", port),
            env.get("PATH", os.defpath),
            str(Path(home_env).expanduser().resolve()) if home_env else None,
            log_path,
        );
        if path.exists() {
            current = _read_bytes(path);
            if not is_ours_plist(current) {
                raise ForeignLoginItem(path);
            }
            if current == data {
                return LoginItemResult(False, path, "Already starts at login.");
            }
        }
        try {
            log_path.parent.mkdir(parents=True, exist_ok=True);
            path.parent.mkdir(parents=True, exist_ok=True);
            (fd, tmp) = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.", suffix=".tmp");
            try {
                with os.fdopen(fd, "wb") as f {
                    f.write(data);
                }
                os.replace(tmp, path);
            } except BaseException {
                try {
                    os.unlink(tmp);
                } except OSError {}
                raise;
            }
        } except OSError as e {
            raise LoginItemFailed(f"Couldn't write {path} ({_why(e)}).") from None;
        }
        domain = f"gui/{_uid()}";
        _launchctl(runner, "bootout", f"{domain}/{LABEL}");
        boot = _launchctl(runner, "bootstrap", domain, str(path));
        if boot.returncode != 0 {
            sleep(BOOTSTRAP_RETRY_WAIT);
            boot = _launchctl(runner, "bootstrap", domain, str(path));
        }
        if boot.returncode != 0 {
            reason = (boot.stderr or "").strip() or f"exit {boot.returncode}";
            return LoginItemResult(
                True,
                path,
                f"Saved, but macOS didn't load it ({reason}). It will start at your next login.",
            );
        }
        return LoginItemResult(True, path, "Sellbird starts at login, and is starting now.");
    }
    custom = (env.get(HOME_ENV) or "").strip();
    if custom
        and not _same_windows_path(
            custom, str(user_home_default("win32", env, Path.home() if home is None else home))
        )
    {
        registry = user_env(HOME_ENV);
        if not (registry and _same_windows_path(registry.strip(), custom)) {
            raise UnsupportedPlatform(
                "Start at login on Windows uses the default home folder. Set SELLBIRD_HOME as a user environment variable (System Properties → Environment Variables), then run this again.",
            );
        }
    }
    argv = tray_argv("win32", port);
    (target, arguments) = (argv[0], subprocess.list2cmdline(argv[1:]));
    existing = read_shortcut(path, runner, env);
    if existing is not None {
        if existing["Description"] != MARKER {
            raise ForeignLoginItem(path);
        }
        if existing["TargetPath"] == target and existing["Arguments"] == arguments {
            return LoginItemResult(False, path, "Already starts at login.");
        }
    }
    path.parent.mkdir(parents=True, exist_ok=True);
    shortcut = {
        "OL_LNK": str(path),
        "OL_TARGET": target,
        "OL_ARGS": arguments,
        "OL_WORKDIR": str(PROJECT_ROOT),
        "OL_DESC": MARKER,
    };
    proc = _run_powershell(runner, _CREATE_SCRIPT, env, shortcut);
    if proc.returncode != 0 {
        reason = (proc.stderr or "").strip() or f"exit {proc.returncode}";
        raise LoginItemFailed(f"Windows couldn't create the Startup shortcut ({reason}).");
    }
    return LoginItemResult(True, path, "Sellbird starts at login.");
}

def uninstall(
    *, platform: str | None = None, runner: any = subprocess.run, env: any = None, home: any = None
) -> LoginItemResult {
    (platform, env, path) = _target(platform, env, home);
    if platform == "darwin" {
        if not path.exists() {
            gone = _launchctl(runner, "bootout", f"gui/{_uid()}/{LABEL}").returncode == 0;
            return LoginItemResult(
                gone, path, "Start at login is off." if gone else "Start at login was already off."
            );
        }
        if not is_ours_plist(_read_bytes(path)) {
            raise ForeignLoginItem(path);
        }
        _launchctl(runner, "bootout", f"gui/{_uid()}/{LABEL}");
        return _remove(path);
    }
    existing = read_shortcut(path, runner, env);
    if existing is None {
        return LoginItemResult(False, path, "Start at login was already off.");
    }
    if existing["Description"] != MARKER {
        raise ForeignLoginItem(path);
    }
    return _remove(path);
}

def status(
    *, platform: str | None = None, runner: any = subprocess.run, env: any = None, home: any = None
) -> dict[str, any] {
    (platform, env, path) = _target(platform, env, home);
    if platform == "darwin" {
        installed = path.exists();
        try {
            ours = installed and is_ours_plist(path.read_bytes());
        } except OSError {
            ours = False;
        }
    } else {
        existing = read_shortcut(path, runner, env);
        installed = existing is not None;
        ours = installed and existing["Description"] == MARKER;
    }
    return {"installed": installed, "ours": ours, "path": str(path)};
}
