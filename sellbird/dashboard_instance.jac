"""Where the running dashboard is: data/dashboard.json.

`sellbird dashboard` writes it once it knows its address, and removes it when
it stops. The MCP server reads it to find the dashboard, then asks
``/api/instance`` and talks to that address only if the id there matches the
file's, so a stale file never sends the agent's token to some other program
that took the port. The file holds no secrets.
"""

import from __future__ { annotations }

import json;

import os;

import tempfile;

import from dataclasses { dataclass }

import from pathlib { Path }

glob INFO_NAME: any = "dashboard.json";

@dataclass(frozen=True)
class DashboardInfo {
    has host: str;

    has port: int;

    has instance: str;

    has pid: int;
}

"""Publish the dashboard's address atomically (owner-only where it means anything)."""
def write(data_dir: Path, *, host: str, port: int, instance: str) -> None {
    data_dir = Path(data_dir);
    data_dir.mkdir(parents=True, exist_ok=True);
    payload: any = json.dumps({
        "host": host,
        "port": `int(port),
        "instance": instance,
        "pid": os.getpid(),
    });
    fd: any;
    tmp: any;
    (fd, tmp) = tempfile.mkstemp(prefix=".dashboard-", suffix=".json", dir=data_dir) as any;
    try {
        f: any;
        with os.fdopen(fd, "w", encoding="utf-8") as f {
            f.write(payload);
        }
        os.replace(tmp, data_dir / INFO_NAME);
    } except BaseException {
        Path(tmp).unlink(missing_ok=True);
        raise;
    }
}

"""The published address, or None when there's no readable, well-formed file."""
def read(data_dir: Path) -> DashboardInfo | None {
    try {
        raw: any = json.loads((Path(data_dir) / INFO_NAME).read_text(encoding="utf-8"));
        info: any = DashboardInfo(
            host=`str(raw["host"]),
            port=`int(raw["port"]),
            instance=`str(raw["instance"]),
            pid=`int(raw["pid"]),
        );
    } except (OSError, ValueError, KeyError, TypeError) {
        return None;
    }
    if not 0 < info.port < 65536 or not info.instance or not info.host {
        return None;
    }
    return info;
}

"""Remove the file if it is still this dashboard's (a newer one may have replaced it)."""
def remove(data_dir: Path, *, instance: str) -> None {
    info: any = read(data_dir);
    if info is not None and info.instance == instance {
        (Path(data_dir) / INFO_NAME).unlink(missing_ok=True);
    }
}
