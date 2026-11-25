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
     _NO_TRAY = "The menu-bar icon runs on macOS and Windows. On Linux, run `sellbird dashboard` and `sellbird run` in a terminal or as services.",
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

def resolve_port(data_dir: Path, port: int | None) -> int {
    if port is not None {
        return port;
    }
    try {
        saved = json.loads((Path(data_dir) / TRAY_JSON).read_text(encoding="utf-8"))["port"];
    } except (OSError, ValueError, KeyError, TypeError) {
        saved = None;
    }
    return saved if isinstance(saved, int) and 1 <= saved and saved <= 65535 else DEFAULT_PORT;
}

def remember_port(data_dir: Path, port: int) {
    Path(data_dir).mkdir(parents=True, exist_ok=True);
    (Path(data_dir) / TRAY_JSON).write_text(json.dumps({"port": port}), encoding="utf-8");
}

def dashboard_command(port: int, platform: str = sys.platform) -> list[str] {
    pythonw = Path(sys.executable).with_name("pythonw.exe");
    python = str(pythonw) if platform == "win32" and pythonw.exists() else sys.executable;
    return [python, "-P", "-m", "sellbird", "dashboard", "--port", str(port)];
}

def default_launcher(argv: list[str], log_path: Path) {
    log_path.parent.mkdir(parents=True, exist_ok=True);
    kwargs: dict[str, any] = {"start_new_session": True};
    if sys.platform == "win32" {
        flags = subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.DETACHED_PROCESS;
        kwargs = {"creationflags": flags};
    }
    fd = os.open(log_path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600);
    with os.fdopen(fd, "a", encoding="utf-8") as log {
        subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=log, stderr=log, **kwargs);
    }
}

def _read_user_token(data_dir: Path) -> str {
    try {
        return TokenStore(Path(data_dir) / "dashboard-token").peek() or "";
    } except (TokenError, OSError) {
        return "";
    }
}

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
        transport: any = None,
        launcher: any = default_launcher,
        opener: any = webbrowser.open,
        sleep: any = time.sleep,
        clock: any = time.monotonic,
    ) {
        (self.data_dir, self.port, self._transport) = (Path(data_dir), port, transport);
        (self._launcher, self._opener, self._sleep, self._clock) = (launcher, opener, sleep, clock);
    }

    def _client(base: str) -> httpx.Client {
        extra = {"transport": self._transport} if self._transport is not None else {};
        return httpx.Client(base_url=base, timeout=5.0, **extra);
    }

    def _base -> str | None {
        info = dashboard_instance.read(self.data_dir);
        if info is None {
            return None;
        }
        base = base_url(info.host, info.port);
        try {
            with self._client(base) as http {
                answer = http.get("/api/instance");
            }
            if answer.status_code == 200 and answer.json().get("instance") == info.instance {
                return base;
            }
        } except (httpx.HTTPError, OSError, ValueError, AttributeError) {}
        return None;
    }

    def _call(method: str, path: str) -> tuple[int, dict[str, any]] {
        base = self._base();
        if base is None {
            return (0, {"message": NOT_RUNNING});
        }
        token = _read_user_token(self.data_dir);
        try {
            with self._client(base) as http {
                r = http.request(method, path, headers={"Authorization": f"Bearer {token}"});
            }
        } except (httpx.HTTPError, OSError) {
            return (0, {"message": UNREACHABLE});
        }
        try {
            body = r.json();
        } except ValueError {
            body = {};
        }
        return (r.status_code, body if isinstance(body, dict) else {});
    }

    def status -> TrayStatus {
        (code, loop) = self._call("GET", "/api/sellbird/status");
        if code == 0 {
            starting = self._clock() < self._starting_until;
            return TrayStatus("starting" if starting else "stopped", "unknown");
        }
        if code in (401, 403) {
            return TrayStatus("running", "unknown", error=SIGNED_OUT);
        }
        running = "running" if loop.get("running") else "stopped";
        return TrayStatus("running", running, sending_paused=loop.get("sending_paused") or "");
    }

    def start_dashboard -> str {
        if self._base() is not None {
            return "The dashboard is running.";
        }
        self._launcher(dashboard_command(self.port), self.data_dir / START_LOG);
        self._starting_until = self._clock() + START_WAIT_SECONDS;
        while self._clock() < self._starting_until {
            if self._base() is not None {
                self._starting_until = 0.0;
                return "The dashboard started.";
            }
            self._sleep(0.5);
        }
        return f"The dashboard didn't answer yet. See {self.data_dir / START_LOG}.";
    }

    def _post(path: str, done: str) -> str {
        (code, body) = self._call("POST", path);
        if code == 200 and body.get("success", True) is not False {
            return done;
        }
        return body.get("message") or UNREACHABLE;
    }

    def start_loop -> str {
        return self._post("/api/sellbird/start", "Sellbird started.");
    }

    def stop_loop -> str {
        return self._post("/api/sellbird/stop", "Sellbird stopped.");
    }

    def pause_sending -> str {
        return self._post("/api/sending/pause", "Sending is paused.");
    }

    def resume_sending -> str {
        return self._post("/api/sending/resume", "Sending resumed.");
    }

    def open_dashboard -> bool {
        if (base := self._base()) is None {
            return False;
        }
        token = _read_user_token(self.data_dir);
        self._opener(base + (f"#token={token}" if token else ""));
        return True;
    }
}

def state_label(status: TrayStatus) -> str {
    if status.dashboard != "running" {
        return "starting…" if status.dashboard == "starting" else "not running";
    }
    running = "running, sending paused" if status.sending_paused else "running";
    return "signed out" if status.error else ("stopped" if status.loop != "running" else running);
}

def icon_state(status: TrayStatus) -> str {
    paused = status.loop != "running" or status.sending_paused;
    return "stopped" if status.dashboard != "running" else ("paused" if paused else "running");
}

def menu_items(status: TrayStatus, autostart_on: bool) -> list[MenuRow] {
    up = status.dashboard == "running" and not status.error;
    rows = [
        MenuRow(f"Sellbird: {state_label(status)}", None, False),
        MenuRow("Open dashboard", "open", status.dashboard == "running"),
        MenuRow("Stop Sellbird", "stop_loop", up)
            if status.loop == "running"
            else MenuRow("Start Sellbird", "start_loop", up),
        MenuRow("Resume sending", "resume_sending", up)
            if status.sending_paused
            else MenuRow("Pause sending", "pause_sending", up),
    ];
    if status.dashboard == "stopped" {
        rows.append(MenuRow("Start the dashboard", "start_dashboard", True));
    }
    return rows + [
        MenuRow("Start at login", "toggle_autostart", True, checked=autostart_on),
        MenuRow("Quit (Sellbird keeps running)" if up else "Quit", "quit", True),
    ];
}

def _cubic(a: float, b: float, c: float, d: float, t: float) -> float {
    u = 1 - t;
    return u ** 3 * a + 3 * u * u * t * b + 3 * u * t * t * c + t ** 3 * d;
}

def bird_points(width: float, height: float, x0: float = 0, y0: float = 0, steps: int = 16) -> any {
    pts: list[tuple[float, float]] = [];
    cur = (0.0, 0.0);
    for (cmd, args) in re.findall(r"([MLCZ])([^MLCZ]*)", BIRD_PATH) {
        nums = [float(n) for n in args.split()];
        if cmd == "C" {
            for k in range(1, steps + 1) {
                t = k / steps;
                pts.append((_cubic(cur[0], *nums[0:5:2], t), _cubic(cur[1], *nums[1:6:2], t)));
            }
            cur = (nums[4], nums[5]);
        } elif cmd != "Z" {
            cur = (nums[0], nums[1]);
            pts.append(cur);
        }
    }
    (sx, sy) = (width / BIRD_BOX[0], height / BIRD_BOX[1]);
    return [(x0 + x * sx, y0 + y * sy) for (x, y) in pts];
}

def _dark_bar -> bool {
    if sys.platform != "darwin" {
        return True;
    }
    try {
        argv = ["defaults", "read", "-g", "AppleInterfaceStyle"];
        out = subprocess.run(argv, capture_output=True, text=True, timeout=2).stdout;
    } except (OSError, subprocess.SubprocessError) {
        return False;
    }
    return out.strip().lower() == "dark";
}

def draw_icon(state: str, dark: bool, width: int, height: int) -> any {
    Image = importlib.import_module("PIL.Image");
    ImageDraw = importlib.import_module("PIL.ImageDraw");
    (w, h) = (width * 4, height * 4);
    image = Image.new("RGBA", (w, h), (0, 0, 0, 0));
    (r, ring) = (h * 0.14, h * 0.05);
    wide = w > h * 1.4;
    unit = min((w - (r if wide else 0)) / BIRD_BOX[0], h * 0.94 / BIRD_BOX[1]);
    (bird_w, bird_h) = (BIRD_BOX[0] * unit, BIRD_BOX[1] * unit);
    (left, top) = (0 if wide else (w - bird_w) / 2, (h - bird_h) / 2);
    ImageDraw.Draw(image).polygon(
        bird_points(bird_w, bird_h, left, top), fill="#ffffff" if dark else "#1d1d1f"
    );
    (cx, cy) = (w - r - ring, h - r - ring);
    hole = Image.new("L", (w, h), 0);
    outer = r + ring;
    ImageDraw.Draw(hole).ellipse((cx - outer, cy - outer, cx + outer, cy + outer), fill=255);
    image.paste((0, 0, 0, 0), mask=hole);
    dot = COLORS.get(state, COLORS["stopped"]);
    ImageDraw.Draw(image).ellipse((cx - r, cy - r, cx + r, cy + r), fill=dot);
    return image.resize((width, height), Image.LANCZOS);
}

def make_icon(state: str, dark: bool | None = None) -> any {
    return draw_icon(state, _dark_bar() if dark is None else dark, 64, 64);
}

def menubar_png(state: str, dark: bool, scale: int = 2) -> bytes {
    out = io.BytesIO();
    draw_icon(state, dark, MENUBAR_PT[0] * scale, MENUBAR_PT[1] * scale).save(out, "png");
    return out.getvalue();
}

def _sharp_on_retina(icon: any) {
    if sys.platform != "darwin" {
        return;
    }
    def assert_image {
        AppKit = importlib.import_module("AppKit");
        Foundation = importlib.import_module("Foundation");
        look = getattr(icon, "_sellbird_look", ("stopped", _dark_bar()));
        if getattr(icon, "_sellbird_drawn", None) == look and icon._icon_image {
            return;
        }
        image = AppKit.NSImage.alloc().initWithData_(Foundation.NSData(menubar_png(*look)));
        image.setSize_(MENUBAR_PT);
        icon._icon_image = image;
        icon._sellbird_drawn = look;
        icon._status_item.button().setImage_(image);
    }
    icon._assert_image = assert_image;
}

def _autostart_on -> bool {
    try {
        state = login_item.status();
    } except Exception as e {
        logger.debug("Start at login unreadable: %s", e);
        return False;
    }
    return bool(state["installed"] and state["ours"]);
}

def _spawn(fn: any) {
    threading.Thread(target=fn, daemon=True).start();
}

def main_thread_scheduler(platform: str = sys.platform) -> any {
    if platform == "darwin" {
        try {
            return importlib.import_module("PyObjCTools.AppHelper").callAfter;
        } except ImportError {}
    }
    return lambda (fn: any) -> any { fn() };
}

def _menu_item(pystray: any, row: MenuRow, action: any) -> any {
    toggle = row.action == "toggle_autostart";
    checked = (lambda (item: any) -> bool { row.checked }) if toggle else None;
    return pystray.MenuItem(row.label, action, checked=checked, enabled=row.enabled);
}

class TrayApp {
    has controller: any = None,
        pystray: any = None,
        _autostart: any = None,
        _spawn: any = None,
        _ui: any = None,
        status: any = TrayStatus("stopped", "unknown"),
        autostart_on: bool = False,
        icon: any = None,
        _drawn: any = None,
        _lock: any = threading.Lock();

    def init(
        controller: any,
        pystray: any,
        *,
        autostart: any = None,
        `spawn: any = _spawn,
        ui: any = None,
    ) {
        (self.controller, self.pystray, self._spawn) = (controller, pystray, `spawn);
        self._autostart = autostart
            if autostart is not None
            else (lambda -> bool { _autostart_on() });
        self._ui = ui if ui is not None else main_thread_scheduler();
    }

    def refresh(*, autostart: bool = False) {
        status = self.controller.status();
        autostart_on = self._autostart() if autostart else None;
        with self._lock {
            self.status = status;
            if autostart_on is not None {
                self.autostart_on = autostart_on;
            }
        }
        self._ui(lambda { self._apply(status) });
    }

    def _apply(status: TrayStatus) {
        if self.icon is not None {
            look = (icon_state(status), _dark_bar());
            if look != self._drawn {
                self.icon._sellbird_look = look;
                self.icon.icon = make_icon(*look);
                self._drawn = look;
            }
            self.icon.update_menu();
        }
    }

    def _notify(message: str) {
        def show {
            if self.icon is not None {
                try {
                    self.icon.notify(message, "Sellbird");
                } except Exception {
                    logger.debug("Notification not shown");
                }
            }
        }
        self._ui(show);
    }

    def menu_items -> list[any] {
        with self._lock {
            rows = menu_items(self.status, self.autostart_on);
        }
        return [_menu_item(self.pystray, row, self._handler(row.action)) for row in rows];
    }

    def _handler(action: str | None) -> any {
        return None
            if action is None
            else (lambda (icon: any, item: any) { self.dispatch(action) });
    }

    def dispatch(action: str) {
        if action == "quit" {
            if self.icon is not None {
                self.icon.stop();
            }
            return;
        }
        def work {
            message = "";
            if action == "toggle_autostart" {
                (message, ok) = self._toggle_autostart();
                if not ok {
                    self._notify(message);
                }
            } elif action == "open" {
                message = "" if self.controller.open_dashboard() else NOT_RUNNING;
            } elif action in _ACTIONS {
                message = getattr(self.controller, action)();
            }
            if message {
                logger.info("%s", message);
            }
            self.refresh(autostart=action == "toggle_autostart");
        }
        self._spawn(work);
    }

    def _toggle_autostart -> tuple[str, bool] {
        try {
            state = login_item.status();
            if state["installed"] and state["ours"] {
                login_item.uninstall();
                return ("Start at login is off.", True);
            }
            port = self.controller.port;
            login_item.install(port=port if port not in (None, DEFAULT_PORT) else None);
            return ("Start at login is on.", True);
        } except Exception as e {
            return (str(e) or "Start at login didn't change.", False);
        }
    }
}

def _hide_dock_icon {
    try {
        importlib.import_module("AppKit").NSApplication.sharedApplication().setActivationPolicy_(1);
    } except Exception {
        logger.debug("Could not hide the Dock icon");
    }
}

def run_tray(
    data_dir: Path,
    port: int | None = None,
    *,
    controller: TrayController | None = None,
    platform: str = sys.platform,
    autostart: any = None,
    refresh_every: float | None = REFRESH_SECONDS,
    ui: any = None,
) {
    try {
        pystray = builtins.__import__("pystray");
    } except ImportError {
        raise TrayUnavailable(_NO_TRAY) from None;
    }
    data_dir = Path(data_dir);
    lock = hold_loop_lock(data_dir / TRAY_LOCK);
    if lock is None {
        logger.debug("Another tray is running for this folder.");
        return;
    }
    try {
        if platform == "darwin" {
            _hide_dock_icon();
        }
        if controller is None {
            controller = TrayController(data_dir, port=resolve_port(data_dir, port));
        }
        ui = ui if ui is not None else main_thread_scheduler(platform);
        app = TrayApp(controller, pystray, autostart=autostart, ui=ui);
        stop = threading.Event();
        def refresher {
            while not stop.wait(refresh_every) {
                try {
                    app.refresh();
                } except Exception as e {
                    logger.debug("Refresh failed: %s", type(e).__name__);
                }
            }
        }
        def setup(icon: any) {
            icon.visible = True;
            app.refresh(autostart=True);
            logger.info("%s", controller.start_dashboard());
            app.refresh();
            if refresh_every {
                threading.Thread(target=refresher, daemon=True).start();
            }
        }
        menu = pystray.Menu(app.menu_items);
        icon = pystray.Icon("sellbird", icon=make_icon("stopped"), title="Sellbird", menu=menu);
        _sharp_on_retina(icon);
        app.icon = icon;
        try {
            icon.run(setup=setup);
        } finally {
            stop.set();
        }
    } finally {
        release_loop_lock(lock);
    }
}
