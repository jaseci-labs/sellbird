import json;
import os;
import tempfile;
import from dataclasses { dataclass }
import from pathlib { Path }

glob INFO_NAME = "dashboard.json";

@dataclass(frozen=True)
class DashboardInfo {
    has host: str,
        port: int,
        instance: str,
        pid: int;
}

def write(data_dir: Path, *, host: str, port: int, instance: str) {
    data_dir = Path(data_dir);
    data_dir.mkdir(parents=True, exist_ok=True);
    payload = {"host": host, "port": int(port), "instance": instance, "pid": os.getpid()};
    (fd, tmp) = tempfile.mkstemp(prefix=".dashboard-", suffix=".json", dir=data_dir) as any;
    try {
        with os.fdopen(fd, "w", encoding="utf-8") as f {
            f.write(json.dumps(payload));
        }
        os.replace(tmp, data_dir / INFO_NAME);
    } except BaseException {
        Path(tmp).unlink(missing_ok=True);
        raise;
    }
}

def read(data_dir: Path) -> DashboardInfo | None {
    try {
        r = json.loads((Path(data_dir) / INFO_NAME).read_text(encoding="utf-8"));
        info = DashboardInfo(str(r["host"]), int(r["port"]), str(r["instance"]), int(r["pid"]));
    } except (OSError, ValueError, KeyError, TypeError) {
        return None;
    }
    return info if 0 < info.port and info.port < 65536 and info.instance and info.host else None;
}

def remove(data_dir: Path, *, instance: str) {
    info = read(data_dir);
    if info is not None and info.instance == instance {
        (Path(data_dir) / INFO_NAME).unlink(missing_ok=True);
    }
}
