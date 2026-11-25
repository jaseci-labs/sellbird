import builtins;
import importlib;
import io;
import json;
import logging;
import os;
import re;
import subprocess;
import sys;
import threading;
import time;
import webbrowser;
import from dataclasses { dataclass }
import from pathlib { Path }
import from typing { Callable }
import httpx;

glob logger = logging.getLogger("sellbird.tray"),
     DEFAULT_PORT = 5555,
     TRAY_LOCK = "tray.lock",
     TRAY_JSON = "tray.json",
     START_LOG = "dashboard-start.log",
     REFRESH_SECONDS = 5.0,
     START_WAIT_SECONDS = 20.0,
     COLORS = {"running": "#2e9e5b", "paused": "#c9a227", "stopped": "#8a8f98"},
     NOT_RUNNING = "The dashboard isn't running.",
     UNREACHABLE = "Couldn't reach the dashboard.",
     SIGNED_OUT = "The dashboard didn't accept the saved token. Open it from the menu.",
     BIRD_PATH = "M83 0C246 47 417 91 562 157C676 209 759 258 744 314C813 257 896 239 954 301L1034 324L944 359C837 473 731 548 563 524C506 516 464 513 427 519L0 631L407 406L224 213L555 300L420 428L663 315L630 281C407 229 264 237 83 0Z",
     BIRD_BOX = (1040, 640),
     MENUBAR_PT = (31, 18),
     _ACTIONS = ("start_loop", "stop_loop", "pause_sending", "resume_sending", "start_dashboard");

class TrayUnavailable(Exception) {}

@dataclass(frozen=True)
class TrayStatus {
    has dashboard: str,
        loop: str,
        sending_paused: str = "",
        error: str = "";
}

@dataclass(frozen=True)
class MenuRow {
    has label: str,
        action: str | None,
        enabled: bool,
        checked: bool = False;
}

def resolve_port(data_dir: Path, port: int | None) -> int;

def remember_port(data_dir: Path, port: int);

def dashboard_command(port: int, platform: str = sys.platform) -> list[str];

def default_launcher(argv: list[str], log_path: Path);

def _read_user_token(data_dir: Path) -> str;

class TrayController {
    has data_dir: any = None,
        port: int = DEFAULT_PORT,
        _transport: any = None,
        _launcher: any = None,
        _opener: any = None,
        _sleep: any = None,
        _clock: any = None,
        _starting_until: float = 0.0;

    def init(
        data_dir: Path,
        port: int = DEFAULT_PORT,
        *,
        transport: httpx.BaseTransport | None = None,
        launcher: Callable[[list[str], Path], None] = default_launcher,
        opener: Callable[[str], object] = webbrowser.open,
        sleep: Callable[[float], None] = time.sleep,
        clock: Callable[[], float] = time.monotonic,
    );

    def _client(base: str) -> httpx.Client;

    def _base -> str | None;

    def _call(method: str, path: str) -> tuple[int, dict[str, any]];

    def status -> TrayStatus;

    def start_dashboard -> str;

    def _post(path: str, done: str) -> str;

    def start_loop -> str;

    def stop_loop -> str;

    def pause_sending -> str;

    def resume_sending -> str;

    def open_dashboard -> bool;
}

def state_label(status: TrayStatus) -> str;

def icon_state(status: TrayStatus) -> str;

def menu_items(status: TrayStatus, autostart_on: bool) -> list[MenuRow];

def _cubic(a: float, b: float, c: float, d: float, t: float) -> float;

def bird_points(
    width: float, height: float, x0: float = 0, y0: float = 0, steps: int = 16
) -> list[tuple[float, float]];

def _dark_bar -> bool;

def draw_icon(state: str, dark: bool, width: int, height: int) -> any;

def make_icon(state: str, dark: bool | None = None) -> any;

def menubar_png(state: str, dark: bool, scale: int = 2) -> bytes;

def _sharp_on_retina(icon: any);

def _autostart_on -> bool;

def _spawn(fn: Callable[[], None]);

def main_thread_scheduler(platform: str = sys.platform) -> any;

def _menu_item(pystray: any, row: MenuRow, action: any) -> any;

class TrayApp {
    has controller: any = None,
        pystray: any = None,
        _autostart: any = None,
        _spawn: any = None,
        _ui: any = None,
        status: any = None,
        autostart_on: bool = False,
        icon: any = None,
        _drawn: any = None,
        _lock: any = None;

    def init(
        controller: TrayController,
        pystray: any,
        *,
        autostart: Callable[[], bool] | None = None,
        `spawn: Callable[[Callable[[], None]], None] = _spawn,
        ui: Callable[[Callable[[], None]], None] | None = None,
    );

    def refresh(*, autostart: bool = False);

    def _apply(status: TrayStatus);

    def _notify(message: str);

    def menu_items -> list[any];

    def _handler(action: str) -> any;

    def dispatch(action: str);

    def _toggle_autostart -> tuple[str, bool];
}

def _hide_dock_icon;

def run_tray(
    data_dir: Path,
    port: int | None = None,
    *,
    controller: TrayController | None = None,
    platform: str = sys.platform,
    autostart: Callable[[], bool] | None = None,
    refresh_every: float | None = REFRESH_SECONDS,
    ui: Callable[[Callable[[], None]], None] | None = None,
);
