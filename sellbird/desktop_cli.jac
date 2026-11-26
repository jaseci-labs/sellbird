import logging;
import subprocess;
import sys;
import from pathlib { Path }

def _add_port(sub: any, help: str) {
    sub.add_argument("--port", type=int, default=None, help=help);
}

def register_desktop_commands(subparsers: any) {
    sub = subparsers.add_parser("autostart", help="Start the Sellbird tray when you log in");
    sub.add_argument("autostart_action", choices=["install", "uninstall", "status"]);
    _add_port(sub, "Dashboard port the tray uses (default: the tray's own default)");
    sub.set_defaults(func=cmd_autostart);
}

def cmd_autostart(args: any, **injected: any) {
    import sellbird.desktop.login_item as li;
    common = {"platform": None, "runner": subprocess.run, "env": None, "home": None} | injected;
    try {
        if args.autostart_action == "install" {
            print(f"  {li.install(port=args.port, **common).message}");
        } elif args.autostart_action == "uninstall" {
            print(f"  {li.uninstall(**common).message}");
        } elif not (state := li.status(**common))["installed"] {
            print("  Start at login is off.");
        } elif state["ours"] {
            print(f"  Start at login is on ({state['path']}).");
        } else {
            print(
                f"  Start at login is off. {state['path']} exists but wasn't created by Sellbird."
            );
        }
    } except (li.UnsupportedPlatform, li.ForeignLoginItem, li.LoginItemFailed) as e {
        print(f"  {e}", file=sys.stderr);
        sys.exit(1);
    }
}

def register(subparsers: any) {
    sub = subparsers.add_parser("tray", help="Menu-bar icon: start, stop and open Sellbird");
    help = "Print whether it's running and the next setup step, then exit";
    sub.add_argument("--status", action="store_true", help=help);
    _add_port(sub, "Dashboard port (default: the last one given, else 5555)");
    sub.set_defaults(func=cmd_tray);
}

def cmd_tray(args: any, *, data_dir: any = None, transport: any = None, autostart: any = None) {
    import sellbird.desktop.tray as tray;
    data_dir = Path(data_dir) if data_dir is not None else PROJECT_ROOT / "data";
    if args.port is not None and not (1 <= args.port and args.port <= 65535) {
        print(f"  Invalid port: {args.port}. Must be 1-65535.", file=sys.stderr);
        sys.exit(2);
    }
    port = tray.resolve_port(data_dir, args.port);
    controller = tray.TrayController(data_dir, port=port, transport=transport);
    if args.status {
        status = controller.status();
        print(f"  Sellbird: {tray.state_label(status)}");
        if status.error {
            print(f"  {status.error}");
        } elif status.dashboard != "running" {
            print("  Start it with `sellbird tray` or `sellbird dashboard`.");
        } elif status.sending_paused {
            print(f"  Sending is paused: {status.sending_paused}");
        }
        return;
    }
    if args.port is not None {
        tray.remember_port(data_dir, args.port);
    }
    handler = logging.StreamHandler();
    handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s: %(message)s"));
    import from sellbird.logsafety { RedactSecrets }
    handler.addFilter(RedactSecrets());
    (tray_logger := logging.getLogger("sellbird.tray")).addHandler(handler);
    tray_logger.setLevel(logging.INFO);
    try {
        tray.run_tray(data_dir, port=port, controller=controller, autostart=autostart);
    } except tray.TrayUnavailable as e {
        print(f"  {e}", file=sys.stderr);
    } finally {
        tray_logger.removeHandler(handler);
    }
}
