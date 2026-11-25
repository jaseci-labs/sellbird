import importlib;
import logging;
import subprocess;
import sys;
import from pathlib { Path }

glob _AUTOSTART_PORT_HELP = "Dashboard port the tray uses (default: the tray's own default)",
     _STATUS_HELP = "Print whether it's running and the next setup step, then exit",
     _TRAY_PORT_HELP = "Dashboard port (default: the last one given, else 5555)",
     _FOREIGN = "exists but wasn't created by Sellbird.";

def register_desktop_commands(subparsers: any);

def cmd_autostart(args: any, **injected: any);

def register(subparsers: any);

def cmd_tray(args: any, *, data_dir: any = None, transport: any = None, autostart: any = None);
