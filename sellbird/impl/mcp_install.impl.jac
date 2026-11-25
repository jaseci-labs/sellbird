impl server_entry -> dict[str, any] {
    return {
        "command": sys.executable,
        "args": ["-P", "-m", "sellbird", "mcp"],
        "env": {HOME_ENV: `str(PROJECT_ROOT)},
    };
}

impl is_ours(candidate: any) -> bool {
    args = (candidate.get("args") or []) if isinstance(candidate, `dict) else None;
    if not isinstance(args, `list) {
        return False;
    }
    if args[-3:] == ["-m", "sellbird", "mcp"] {
        return True;
    }
    command = `str(candidate.get("command") or "").replace("\\", "/").rsplit("/", 1)[-1].lower();
    return command.removesuffix(".exe") == "sellbird" and args == ["mcp"];
}

impl _same(candidate: any) -> bool {
    if not isinstance(candidate, `dict) {
        return False;
    }
    if candidate.get("type") == "stdio" {
        candidate = {k: v for (k, v) in candidate.items() if k != "type"};
    }
    return candidate == server_entry();
}

impl _prefixed(sign: str, text: str) -> list[str] {
    return [f"{sign} {line}" if line else sign for line in text.splitlines()];
}

impl _read_claude(path: Path) -> tuple[any, ...] {
    if path.is_symlink() {
        return (None, SYMLINK_REFUSAL.format(CLAUDE_LABEL));
    }
    if not path.exists() {
        return ({}, "");
    }
    try {
        doc = json.loads(path.read_bytes().decode("utf-8"));
    } except OSError as e {
        return (None, UNREADABLE.format(CLAUDE_LABEL, e.strerror or `type(e).__name__));
    } except (ValueError, UnicodeDecodeError) {
        return (None, REFUSE_BAD_JSON);
    }
    if not isinstance(doc, `dict) or not isinstance(doc.get("mcpServers", {}), `dict) {
        return (None, REFUSE_BAD_JSON);
    }
    return (doc, "");
}

impl _claude_entry_preview(old: any, new: any) -> str {
    lines: list[str] = [];
    for (sign, value) in (("-", old), ("+", new)) {
        if value is not None {
            lines += _prefixed(sign, json.dumps({SERVER_NAME: value}, indent=2));
        }
    }
    return "\n".join(lines);
}

impl _claude_cli_argv(
    claude: str, verb: str, previous: dict[str, any] | None = None
) -> tuple[any, ...] {
    if verb != "add" {
        return (claude, "mcp", "remove", SERVER_NAME, "--scope", "user");
    }
    payload = json.dumps(server_entry() if previous is None else previous);
    return (claude, "mcp", "add-json", "--scope", "user", SERVER_NAME, payload);
}

impl _plan_claude(home: Path, which: any, install: bool) -> PlannedChange {
    path = Path(home) / ".claude.json";
    claude = which("claude");
    if not claude and not path.exists() {
        return PlannedChange("claude", "refuse", None, "", REFUSE_NO_CLAUDE);
    }
    (doc, refusal) = _read_claude(path);
    if refusal {
        return PlannedChange("claude", "refuse", path, "", refusal);
    }
    current = doc.get("mcpServers", {}).get(SERVER_NAME);
    if install and current is not None and _same(current) {
        return PlannedChange("claude", "none", path, "");
    }
    if not install and current is None {
        return PlannedChange(
            "claude", "none", path, "", "Sellbird isn't set up for Claude Code; nothing to remove."
        );
    }
    if current is not None and not is_ours(current) {
        return PlannedChange("claude", "refuse", path, "", REFUSE_FOREIGN_CLAUDE);
    }
    preview = _claude_entry_preview(current, server_entry() if install else None);
    action = ("add" if current is None else "replace") if install else "remove";
    if not claude {
        return PlannedChange("claude", action, path, preview);
    }
    replacing = install and current is not None;
    argv = _claude_cli_argv(claude, "add" if install else "remove");
    pre = _claude_cli_argv(claude, "remove") if replacing else ();
    preview = "\n".join([preview, "Runs:"] + [shlex.join(a) for a in (pre, argv) if a]);
    old_json = json.dumps(current) if replacing else "";
    return PlannedChange("claude", "cli", path, preview, "", argv, pre, old_json);
}

impl plan_claude(
    *, home: Path, which: any = shutil.which, runner: any = subprocess.run
) -> PlannedChange {
    return _plan_claude(home, which, True);
}

impl plan_uninstall_claude(
    *, home: Path, which: any = shutil.which, runner: any = subprocess.run
) -> PlannedChange {
    return _plan_claude(home, which, False);
}

impl _claude_new_text(action: str, text: str) -> str {
    doc: any = json.loads(text) if text else {};
    servers: any = doc.setdefault("mcpServers", {});
    current = servers.get(SERVER_NAME);
    if current is not None and not is_ours(current) {
        raise InstallError(REFUSE_FOREIGN_CLAUDE);
    }
    if action == "remove" {
        servers.pop(SERVER_NAME, None);
    } else {
        servers[SERVER_NAME] = server_entry();
    }
    return json.dumps(doc, indent=2, ensure_ascii=False) + "\n";
}

impl _parts(client: str, text: str) -> tuple[any, ...] {
    (key, loads) = ("mcpServers", json.loads)
        if client == "claude"
        else ("mcp_servers", tomllib.loads);
    doc: any = loads(text) if text else {};
    servers: any = `dict(doc.get(key) or {});
    ours = servers.pop(SERVER_NAME, None);
    rest = {k: v for (k, v) in doc.items() if k != key};
    if servers {
        rest[key] = servers;
    }
    return (rest, ours);
}

impl _codex_path(env: Mapping[str, str], home: Path) -> Path {
    return Path(env.get("CODEX_HOME") or Path(home) / ".codex") / "config.toml";
}

impl _toml_str(value: str) -> str {
    if "'" not in value and "\n" not in value and "\r" not in value {
        return f"'{value}'";
    }
    for (raw, escaped) in (
        ("\\", "\\\\"),
        ("\"", "\\\""),
        ("\n", "\\n"),
        ("\r", "\\r"),
        ("\t", "\\t"),
    ) {
        value = value.replace(raw, escaped);
    }
    return f"\"{value}\"";
}

impl render_codex_block(server: dict[str, any]) -> str {
    args = ", ".join(_toml_str(a) for a in server["args"]);
    env = ", ".join(
        f"{k if _BARE_KEY.match(k) else _toml_str(k)} = {_toml_str(v)}"
        for (k, v) in server["env"].items(),
    );
    return f"{CODEX_MARKER}\n[mcp_servers.{SERVER_NAME}]\ncommand = {_toml_str(server['command'])}\nargs = [{args}]\nenv = {{ {env} }}\n";
}

impl _read_codex(path: Path) -> tuple[any, ...] {
    if path.is_symlink() {
        return (None, None, SYMLINK_REFUSAL.format(CODEX_LABEL));
    }
    if not path.exists() {
        return (None, {}, "");
    }
    try {
        text = path.read_bytes().decode("utf-8");
        return (text, tomllib.loads(text), "");
    } except OSError as e {
        return (None, None, UNREADABLE.format(CODEX_LABEL, e.strerror or `type(e).__name__));
    } except (tomllib.TOMLDecodeError, UnicodeDecodeError) {
        return (None, None, REFUSE_BAD_TOML);
    }
}

impl _our_block(text: str) -> tuple[int, int] | None {
    lines = text.splitlines(keepends=True);
    for (i, line) in enumerate(lines) {
        if not _OUR_HEADER.match(line) {
            continue;
        }
        if i == 0 or lines[i - 1].rstrip("\r\n") != CODEX_MARKER {
            return None;
        }
        end = i + 1;
        while end < len(lines) and not _HEADER.match(lines[end]) {
            end += 1;
        }
        while end > i + 1
            and (not lines[end - 1].strip() or lines[end - 1].lstrip().startswith("#"))
        {
            end -= 1;
        }
        return (i - 1, end);
    }
    return None;
}

impl _plan_codex(env: Mapping[str, str], home: Path, install: bool) -> PlannedChange {
    path = _codex_path(env, home);
    (text, doc, refusal) = _read_codex(path);
    if refusal {
        return PlannedChange("codex", "refuse", path, "", refusal);
    }
    current = (doc.get("mcp_servers") or {}).get(SERVER_NAME);
    if install and current is not None and current == server_entry() {
        return PlannedChange("codex", "none", path, "");
    }
    if not install and current is None {
        return PlannedChange(
            "codex", "none", path, "", "Sellbird isn't set up for Codex; nothing to remove."
        );
    }
    new = _prefixed("+", render_codex_block(server_entry())) if install else [];
    if current is None {
        return PlannedChange("codex", "add", path, "\n".join(new));
    }
    block = _our_block(text or "");
    if block is None {
        return PlannedChange("codex", "refuse", path, "", REFUSE_FOREIGN_CODEX);
    }
    old = "".join(text.splitlines(keepends=True)[block[0]:block[1]]);
    return PlannedChange(
        "codex", "replace" if install else "remove", path, "\n".join(_prefixed("-", old) + new)
    );
}

impl plan_codex(*, env: Mapping[str, str], home: Path) -> PlannedChange {
    return _plan_codex(env, home, True);
}

impl plan_uninstall_codex(*, env: Mapping[str, str], home: Path) -> PlannedChange {
    return _plan_codex(env, home, False);
}

impl _codex_new_text(action: str, text: str) -> str {
    if action == "add" {
        if text and not text.endswith("\n") {
            text += "\n";
        }
        return text + ("\n" if text else "") + render_codex_block(server_entry());
    }
    block = _our_block(text);
    if block is None {
        raise InstallError(REFUSE_FOREIGN_CODEX);
    }
    lines = text.splitlines(keepends=True);
    (start, end) = block;
    if action == "replace" {
        return "".join(lines[:start]) + render_codex_block(server_entry()) + "".join(lines[end:]);
    }
    if start > 0 and not lines[start - 1].strip() {
        start -= 1;
    }
    return "".join(lines[:start] + lines[end:]);
}

impl _backup_path(path: Path, now: datetime) -> Path {
    base = f"{path.name}.sellbird-backup-{now:%Y%m%d%H%M%S}";
    (candidate, n) = (path.with_name(base), 2);
    while candidate.exists() {
        (candidate, n) = (path.with_name(f"{base}-{n}"), n + 1);
    }
    return candidate;
}

impl _write_atomic(target: Path, text: str) {
    target.parent.mkdir(parents=True, exist_ok=True);
    (fd, tmp) = tempfile.mkstemp(dir=target.parent, prefix=f".{target.name}.", suffix=".tmp");
    try {
        with os.fdopen(fd, "wb") as f {
            f.write(text.encode("utf-8"));
        }
        if target.exists() {
            shutil.copymode(target, tmp);
        }
        os.replace(tmp, target);
    } except BaseException {
        Path(tmp).unlink(missing_ok=True);
        raise;
    }
}

impl _write_private(path: Path, data: bytes, *, exclusive: bool) {
    flags = os.O_WRONLY
        | os.O_CREAT
        | getattr(os, "O_BINARY", 0)
        | (os.O_EXCL if exclusive else os.O_TRUNC);
    with os.fdopen(os.open(path, flags, 0o600), "wb") as f {
        f.write(data);
    }
}

impl _restore(data: bytes, backup: Path, target: Path) {
    tmp = target.with_name(f".{target.name}.restore.tmp");
    try {
        tmp.unlink(missing_ok=True);
        _write_private(tmp, data, exclusive=True);
        shutil.copymode(backup, tmp);
        os.replace(tmp, target);
    } except BaseException {
        tmp.unlink(missing_ok=True);
        raise;
    }
}

impl _label(change: PlannedChange) -> str {
    return CLAUDE_LABEL if change.client == "claude" else CODEX_LABEL;
}

impl _cant_back_up(change: PlannedChange, e: any) -> InstallError {
    return InstallError(
        f"{_label(change)} couldn't be read or backed up ({e.strerror or `type(e).__name__}), so nothing was changed.",
    );
}

impl _read(change: PlannedChange) -> bytes | None {
    if change.path.is_symlink() {
        raise InstallError(SYMLINK_REFUSAL.format(_label(change)));
    }
    try {
        return change.path.read_bytes() if change.path.exists() else None;
    } except OSError as e {
        raise _cant_back_up(change, e);
    }
}

impl _back_up(change: PlannedChange, data: bytes | None, now: datetime) -> Path | None {
    if data is None {
        return None;
    }
    try {
        backup = _backup_path(change.path, now);
        _write_private(backup, data, exclusive=True);
        shutil.copymode(change.path, backup);
        return backup;
    } except OSError as e {
        raise _cant_back_up(change, e);
    }
}

impl _apply_file(change: PlannedChange, now: datetime) {
    (path, claude) = (change.path, change.client == "claude");
    data = _read(change);
    try {
        original = data.decode("utf-8") if data is not None else "";
        new_text = _claude_new_text(change.action, original)
            if claude
            else _codex_new_text(change.action, original);
    } except (ValueError, UnicodeDecodeError) {
        raise InstallError(REFUSE_BAD_JSON if claude else REFUSE_BAD_TOML);
    }
    backup = _back_up(change, data, now);
    try {
        _write_atomic(path, new_text);
        (rest_after, ours_after) = _parts(change.client, path.read_bytes().decode("utf-8"));
        wanted = None if change.action == "remove" else server_entry();
        ok = rest_after == _parts(change.client, original)[0] and ours_after == wanted;
    } except Exception {
        ok = False;
    }
    if ok {
        return;
    }
    if data is not None {
        _restore(data, backup, path);
    } else {
        path.unlink(missing_ok=True);
    }
    raise InstallVerifyFailed(VERIFY_FAILED);
}

impl _run_cli(argv: tuple[str, ...], runner: any) {
    try {
        result = runner(
            `list(argv),
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=60,
        );
    } except (OSError, subprocess.SubprocessError) as e {
        raise InstallError(f"`{shlex.join(argv[:3])}` couldn't run ({`type(e).__name__})");
    }
    if result.returncode != 0 {
        detail = ((result.stderr or result.stdout or "").strip().splitlines() or [""])[-1];
        raise InstallError(f"`{shlex.join(argv[:3])}` failed: {detail}".rstrip(": "));
    }
}

impl _kept_at(backup: Path | None) -> str {
    return f" Your previous file is at {backup}." if backup else "";
}

impl _apply_cli(change: PlannedChange, runner: any, now: datetime, *, expect_absent: bool) {
    backup = _back_up(change, _read(change), now);
    if change.pre_argv {
        _run_cli(change.pre_argv, runner);
    }
    try {
        _run_cli(change.argv, runner);
    } except InstallError as add_failed {
        if not change.pre_argv {
            raise;
        }
        try {
            _run_cli(_claude_cli_argv(change.argv[0], "add", json.loads(change.old_json)), runner);
        } except InstallError {
            raise InstallError(
                f"The old Sellbird entry was removed and the new one couldn't be added ({add_failed})."
                    + _kept_at(backup),
            );
        }
        raise InstallError(f"{add_failed}. Your previous Sellbird entry was put back.");
    }
    (doc, refusal) = _read_claude(change.path);
    current = (doc or {}).get("mcpServers", {}).get(SERVER_NAME);
    if refusal or not (current is None if expect_absent else _same(current)) {
        raise InstallError(
            "Claude Code's config didn't end up as expected after `claude mcp`." + _kept_at(backup)
        );
    }
}

impl apply_change(change: PlannedChange, *, runner: any = subprocess.run, now: datetime) -> str {
    name = CLIENT_NAMES[change.client];
    if change.action == "refuse" {
        return change.reason;
    }
    if change.action == "none" {
        return change.reason or f"Already set up for {name}.";
    }
    removing = change.action == "remove" or change.argv[2:3] == ("remove",);
    done = f"Removed Sellbird from {name}." if removing else f"Added Sellbird to {name}.";
    if change.action == "cli" {
        _apply_cli(change, runner, now, expect_absent=removing);
        return f"{done} Start a new Claude Code session to use it.";
    }
    _apply_file(change, now);
    return f"{done} {RESTART_CLAUDE}"
        if change.client == "claude"
        else f"{done} Restart Codex to pick it up.";
}

impl print_config -> str {
    server = server_entry();
    other = f"Any other MCP client: command {server['command']}, args -P -m sellbird mcp, env {HOME_ENV}={server['env'][HOME_ENV]}";
    return "\n\n".join([
        json.dumps({"mcpServers": {SERVER_NAME: server}}, indent=2),
        render_codex_block(server).rstrip("\n"),
        other,
    ]);
}

impl run_command(
    action: str,
    client: str | None,
    *,
    print_only: bool = False,
    yes: bool = False,
    home: Path | None = None,
    env: Mapping[str, str] | None = None,
    which: any = shutil.which,
    runner: any = subprocess.run,
    isatty: Callable[[], bool] | None = None,
    ask: Callable[[str], str] = builtins.input,
    out: Callable[[str], None] = builtins.print,
    now: datetime | None = None,
) -> int {
    try {
        require_self_hosted("mcp_install");
    } except NotOnHosted as e {
        out(e.payload["message"]);
        return 1;
    }
    if print_only {
        out(print_config());
        return 0;
    }
    home = Path.home() if home is None else Path(home);
    env = os.environ if env is None else env;
    install = action == "install";
    change = _plan_claude(home, which, install)
        if (client or "claude") == "claude"
        else _plan_codex(env, home, install);
    codex_found = client is None
        and (`bool(which("codex")) or _codex_path(env, home).parent.is_dir());
    code = _show_and_apply(
        change,
        yes=yes,
        isatty=isatty or sys.stdin.isatty,
        ask=ask,
        out=out,
        runner=runner,
        now=now or datetime.now(),
    );
    if codex_found {
        verb = "add Sellbird to it too" if install else "remove Sellbird from it too";
        out(f"Codex found. To {verb}, run: sellbird mcp {action} codex");
    }
    return code;
}

impl _show_and_apply(
    change: PlannedChange, *, yes: bool, isatty: any, ask: any, out: any, runner: any, now: datetime
) -> int {
    if change.action == "refuse" {
        out(change.reason);
        return 1;
    }
    if change.action == "none" {
        out(apply_change(change, runner=runner, now=now));
        return 0;
    }
    name = CLIENT_NAMES[change.client];
    out(f"{name}: this will run" if change.action == "cli" else f"{name}: {change.path}");
    out(change.preview);
    if not yes and not isatty() {
        out(NOT_TTY);
        return 2;
    }
    if not yes and ask("Apply this change? [y/N] ").strip().lower() not in ("y", "yes") {
        out("Nothing was changed.");
        return 1;
    }
    try {
        out(apply_change(change, runner=runner, now=now));
    } except InstallError as e {
        out(`str(e));
        return 1;
    }
    return 0;
}
