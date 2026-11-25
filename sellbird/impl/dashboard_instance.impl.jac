impl write(data_dir: Path, *, host: str, port: int, instance: str) -> None {
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

impl read(data_dir: Path) -> DashboardInfo | None {
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

impl remove(data_dir: Path, *, instance: str) -> None {
    info: any = read(data_dir);
    if info is not None and info.instance == instance {
        (Path(data_dir) / INFO_NAME).unlink(missing_ok=True);
    }
}
