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
    def init(message: str = "Start at login works on macOS and Windows.");
}

class ForeignLoginItem(Exception) {
    has path: any = None;

    def init(path: Path);
}

class LoginItemFailed(Exception) {}

@dataclass(frozen=True)
class LoginItemResult {
    has changed: bool,
        path: Path,
        message: str;
}

def _why(e: OSError) -> str;

def login_item_path(
    platform: str | None = None, env: Mapping[str, str] | None = None, home: Path | None = None
) -> Path;

def tray_argv(platform: str | None = None, port: int | None = None) -> list[str];

def render_plist(
    argv: list[str],
    path_env: str,
    home_env: str | None,
    log_path: Path,
    working_dir: Path | None = None,
) -> bytes;

def is_ours_plist(data: bytes) -> bool;

def _uid -> int;

def _launchctl(runner: any, *args: str) -> any;

def _read_bytes(path: Path) -> bytes;

def _remove(path: Path) -> LoginItemResult;

def _run_powershell(
    runner: any, script: str, env: Mapping[str, str], extra: Mapping[str, str]
) -> any;

def read_shortcut(
    path: Path, runner: any = subprocess.run, env: Mapping[str, str] | None = None
) -> dict[str, str] | None;

def _same_windows_path(a: str, b: str) -> bool;

def _user_registry_env(name: str) -> str | None;

def _target(
    platform: str | None, env: Mapping[str, str] | None, home: Path | None
) -> tuple[str, Mapping[str, str], Path];

def install(
    *,
    platform: str | None = None,
    runner: any = subprocess.run,
    env: Mapping[str, str] | None = None,
    home: Path | None = None,
    port: int | None = None,
    user_env: Callable[[str], str | None] = _user_registry_env,
    sleep: Callable[[float], None] = time.sleep,
) -> LoginItemResult;

def uninstall(
    *, platform: str | None = None, runner: any = subprocess.run, env: any = None, home: any = None
) -> LoginItemResult;

def status(
    *, platform: str | None = None, runner: any = subprocess.run, env: any = None, home: any = None
) -> dict[str, any];
