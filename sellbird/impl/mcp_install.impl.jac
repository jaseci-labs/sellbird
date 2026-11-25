impl _symlink_refusal(label: builtins.str) -> builtins.str {
    return f"{label} is a symlink, so it was left alone. Add the entry to the file it points to yourself (sellbird mcp install --print shows it).";
}

impl _unreadable(label: builtins.str, err: any) -> builtins.str {
    return f"{label} couldn't be read ({err.strerror or `type(err).__name__}), so it was left alone.";
}

impl InstallError.__repr__ -> str {
    return (getattr(builtins.super(InstallError, self), "__repr__") as any)();
}

impl InstallError.__eq__(other: any) -> bool {
    return self is other;
}

impl InstallError.__hash__ -> int {
    return id(self);
}

impl InstallVerifyFailed.__repr__ -> str {
    return (getattr(builtins.super(InstallVerifyFailed, self), "__repr__") as any)();
}

impl InstallVerifyFailed.__eq__(other: any) -> bool {
    return self is other;
}

impl InstallVerifyFailed.__hash__ -> int {
    return id(self);
}

impl server_entry -> builtins.dict {
    return {
        "command": sys.executable,
        "args": ["-P", "-m", "sellbird", "mcp"],
        "env": {HOME_ENV: `str(PROJECT_ROOT)},
    };
}

impl is_ours(`entry) -> builtins.bool {
    if not isinstance(`entry, `dict) {
        return False;
    }
    args: any = `entry.get("args") or [];
    if not isinstance(args, `list) {
        return False;
    }
    if args[-3:] == ["-m", "sellbird", "mcp"] {
        return True;
    }
    command: any = `str(`entry.get("command") or "").replace("\\", "/").rsplit("/", 1)[-1].lower();
    return operator.eq(command.removesuffix(".exe"), "sellbird") and operator.eq(args, ["mcp"]);
}

impl _same(`entry) -> builtins.bool {
    if not isinstance(`entry, `dict) {
        return False;
    }
    if `entry.get("type") == "stdio" {
        `entry = {k: v for (k, v) in `entry.items() if k != "type"};
    }
    return operator.eq(`entry, server_entry());
}

impl _prefixed(sign: builtins.str, text: builtins.str) -> builtins.list[builtins.str] {
    return [f"{sign} {line}" if line else sign for line in text.splitlines()];
}

impl _claude_path(home: Path) -> Path {
    return Path(home) / ".claude.json";
}

impl _read_claude(path: Path) -> builtins.tuple[builtins.dict | None, builtins.str] {
    if path.is_symlink() {
        return (None, _symlink_refusal(CLAUDE_LABEL));
    }
    if not path.exists() {
        return ({}, "");
    }
    try {
        doc: any = json.loads(path.read_bytes().decode("utf-8"));
    } except OSError as e {
        return (None, _unreadable(CLAUDE_LABEL, e));
    } except (ValueError, UnicodeDecodeError) {
        return (None, REFUSE_BAD_JSON);
    }
    if not isinstance(doc, `dict) or not isinstance(doc.get("mcpServers", {}), `dict) {
        return (None, REFUSE_BAD_JSON);
    }
    return (doc, "");
}

impl _claude_entry_preview(old, new) -> builtins.str {
    lines: any = [];
    if old is not None {
        lines += _prefixed("-", json.dumps({SERVER_NAME: old}, indent=2));
    }
    if new is not None {
        lines += _prefixed("+", json.dumps({SERVER_NAME: new}, indent=2));
    }
    return "\n".join(lines);
}

impl _claude_cli_argv(
    claude: builtins.str, verb: builtins.str, `entry: builtins.dict | None = None
) -> any {
    if verb == "add" {
        return (
            claude,
            "mcp",
            "add-json",
            "--scope",
            "user",
            SERVER_NAME,
            json.dumps(server_entry() if `entry is None else `entry),
        );
    }
    return (claude, "mcp", "remove", SERVER_NAME, "--scope", "user");
}

impl plan_claude(*, home: Path, which=which_default_, runner=runner_default_) -> PlannedChange {
    path: any = _claude_path(home);
    claude: any = which("claude");
    if not claude and not path.exists() {
        return PlannedChange("claude", "refuse", None, "", REFUSE_NO_CLAUDE);
    }
    doc: any;
    refusal: any;
    (doc, refusal) = _read_claude(path) as any;
    if refusal {
        return PlannedChange("claude", "refuse", path, "", refusal);
    }
    current: any = doc.get("mcpServers", {}).get(SERVER_NAME);
    if current is not None and _same(current) {
        return PlannedChange("claude", "none", path, "");
    }
    if current is not None and not is_ours(current) {
        return PlannedChange("claude", "refuse", path, "", REFUSE_FOREIGN_CLAUDE);
    }
    if claude {
        argv: any = _claude_cli_argv(claude, "add");
        pre: any = _claude_cli_argv(claude, "remove") if current is not None else ();
        preview: any = "\n".join(
            [_claude_entry_preview(current, server_entry()), "Runs:"] + [
                shlex.join(a)
                for a in (pre, argv)
                if a
            ],
        );
        return PlannedChange(
            "claude",
            "cli",
            path,
            preview,
            argv=argv,
            pre_argv=pre,
            old_json=json.dumps(current) if current is not None else "",
        );
    }
    action: any = "add" if current is None else "replace";
    return PlannedChange("claude", action, path, _claude_entry_preview(current, server_entry()));
}

impl plan_uninstall_claude(
    *, home: Path, which=which_default__, runner=runner_default__
) -> PlannedChange {
    path: any = _claude_path(home);
    claude: any = which("claude");
    if not claude and not path.exists() {
        return PlannedChange("claude", "refuse", None, "", REFUSE_NO_CLAUDE);
    }
    doc: any;
    refusal: any;
    (doc, refusal) = _read_claude(path) as any;
    if refusal {
        return PlannedChange("claude", "refuse", path, "", refusal);
    }
    current: any = doc.get("mcpServers", {}).get(SERVER_NAME);
    if current is None {
        return PlannedChange(
            "claude", "none", path, "", "Sellbird isn't set up for Claude Code; nothing to remove."
        );
    }
    if not is_ours(current) {
        return PlannedChange("claude", "refuse", path, "", REFUSE_FOREIGN_CLAUDE);
    }
    if claude {
        argv: any = _claude_cli_argv(claude, "remove");
        preview: any = "\n".join([_claude_entry_preview(current, None), "Runs:", shlex.join(argv)]);
        return PlannedChange("claude", "cli", path, preview, argv=argv);
    }
    return PlannedChange("claude", "remove", path, _claude_entry_preview(current, None));
}

impl _claude_new_text(action: builtins.str, text: builtins.str) -> builtins.str {
    doc: any = json.loads(text) if text else {};
    servers: any = doc.setdefault("mcpServers", {});
    current: any = servers.get(SERVER_NAME);
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

impl _claude_parts(text: builtins.str) -> builtins.tuple[builtins.dict, builtins.object] {
    doc: any = json.loads(text) if text else {};
    servers: any = `dict(doc.get("mcpServers") or {});
    ours: any = servers.pop(SERVER_NAME, None);
    rest: any = {k: v for (k, v) in doc.items() if k != "mcpServers"};
    if servers {
        rest["mcpServers"] = servers;
    }
    return (rest, ours);
}

impl _codex_path(env: Mapping[builtins.str, builtins.str], home: Path) -> Path {
    return Path(env.get("CODEX_HOME") or Path(home) / ".codex") / "config.toml";
}

impl _toml_str(value: builtins.str) -> builtins.str {
    if "'" not in value and "\n" not in value and "\r" not in value {
        return f"'{value}'";
    }
    escaped: any = value.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace(
        "\r", "\\r"
    ).replace("\t", "\\t");
    return f"\"{escaped}\"";
}

impl _toml_key(key: builtins.str) -> builtins.str {
    return key if _BARE_KEY.match(key) else _toml_str(key);
}

impl render_codex_block(`entry: builtins.dict) -> builtins.str {
    args: any = ", ".join(_toml_str(a) for a in `entry["args"]);
    env: any = ", ".join(f"{_toml_key(k)} = {_toml_str(v)}" for (k, v) in `entry["env"].items());
    return "\n".join([
        CODEX_MARKER,
        f"[mcp_servers.{SERVER_NAME}]",
        "command = " + format(_toml_str(`entry["command"]), ""),
        f"args = [{args}]",
        f"env = {{ {env} }}",
    ])
        + "\n";
}

impl _read_codex(path: Path) -> builtins.tuple[builtins.str | None, builtins.dict
    | None, builtins.str] {
    if path.is_symlink() {
        return (None, None, _symlink_refusal(CODEX_LABEL));
    }
    if not path.exists() {
        return (None, {}, "");
    }
    try {
        text: any = path.read_bytes().decode("utf-8");
        return (text, tomllib.loads(text), "");
    } except OSError as e {
        return (None, None, _unreadable(CODEX_LABEL, e));
    } except (tomllib.TOMLDecodeError, UnicodeDecodeError) {
        return (None, None, REFUSE_BAD_TOML);
    }
}

impl _our_block(text: builtins.str) -> builtins.tuple[builtins.int, builtins.int] | None {
    lines: any = text.splitlines(keepends=True);
    for (i, line) in enumerate(lines) {
        if _OUR_HEADER.match(line) {
            if i == 0 or lines[i - 1].rstrip("\r\n") != CODEX_MARKER {
                return None;
            }
            end: any = i + 1;
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
    }
    return None;
}

impl plan_codex(*, env: Mapping[builtins.str, builtins.str], home: Path) -> PlannedChange {
    path: any = _codex_path(env, home);
    text: any;
    doc: any;
    refusal: any;
    (text, doc, refusal) = _read_codex(path) as any;
    if refusal {
        return PlannedChange("codex", "refuse", path, "", refusal);
    }
    current: any = (doc.get("mcp_servers") or {}).get(SERVER_NAME);
    if current is not None and current == server_entry() {
        return PlannedChange("codex", "none", path, "");
    }
    new: any = _prefixed("+", render_codex_block(server_entry()));
    if current is None {
        return PlannedChange("codex", "add", path, "\n".join(new));
    }
    block: any = _our_block(text or "");
    if block is None {
        return PlannedChange("codex", "refuse", path, "", REFUSE_FOREIGN_CODEX);
    }
    old: any = "".join(text.splitlines(keepends=True)[block[0]:block[1]]);
    return PlannedChange("codex", "replace", path, "\n".join(_prefixed("-", old) + new));
}

impl plan_uninstall_codex(
    *, env: Mapping[builtins.str, builtins.str], home: Path
) -> PlannedChange {
    path: any = _codex_path(env, home);
    text: any;
    doc: any;
    refusal: any;
    (text, doc, refusal) = _read_codex(path) as any;
    if refusal {
        return PlannedChange("codex", "refuse", path, "", refusal);
    }
    if (doc.get("mcp_servers") or {}).get(SERVER_NAME) is None {
        return PlannedChange(
            "codex", "none", path, "", "Sellbird isn't set up for Codex; nothing to remove."
        );
    }
    block: any = _our_block(text or "");
    if block is None {
        return PlannedChange("codex", "refuse", path, "", REFUSE_FOREIGN_CODEX);
    }
    old: any = "".join(text.splitlines(keepends=True)[block[0]:block[1]]);
    return PlannedChange("codex", "remove", path, "\n".join(_prefixed("-", old)));
}

impl _codex_new_text(action: builtins.str, text: builtins.str) -> builtins.str {
    if action == "add" {
        if text and not text.endswith("\n") {
            text += "\n";
        }
        return text + ("\n" if text else "") + render_codex_block(server_entry());
    }
    block: any = _our_block(text);
    if block is None {
        raise InstallError(REFUSE_FOREIGN_CODEX);
    }
    lines: any = text.splitlines(keepends=True);
    start: any;
    end: any;
    (start, end) = block as any;
    if action == "replace" {
        return "".join(lines[:start]) + render_codex_block(server_entry()) + "".join(lines[end:]);
    }
    if start > 0 and not lines[start - 1].strip() {
        start -= 1;
    }
    return "".join(lines[:start] + lines[end:]);
}

impl _codex_parts(text: builtins.str) -> builtins.tuple[builtins.dict, builtins.object] {
    doc: any = tomllib.loads(text) if text else {};
    servers: any = `dict(doc.get("mcp_servers") or {});
    ours: any = servers.pop(SERVER_NAME, None);
    rest: any = {k: v for (k, v) in doc.items() if k != "mcp_servers"};
    if servers {
        rest["mcp_servers"] = servers;
    }
    return (rest, ours);
}

impl _backup_path(path: Path, now: datetime) -> Path {
    base: any = f"{path.name}.sellbird-backup-{now:%Y%m%d%H%M%S}";
    candidate: any;
    n: any;
    (candidate, n) = (path.with_name(base), 2);
    while candidate.exists() {
        (candidate, n) = (path.with_name(f"{base}-{n}"), n + 1);
    }
    return candidate;
}

impl _write_atomic(target: Path, text: builtins.str) -> None {
    target.parent.mkdir(parents=True, exist_ok=True);
    fd: any;
    tmp: any;
    (fd, tmp) = tempfile.mkstemp(
        dir=target.parent, prefix=f".{target.name}.", suffix=".tmp"
    ) as any;
    try {
        f: any;
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

impl _write_private(path: Path, data: builtins.bytes, *, exclusive: builtins.bool) -> None {
    flags: any = os.O_WRONLY | os.O_CREAT | getattr(os, "O_BINARY", 0);
    flags |= os.O_EXCL if exclusive else os.O_TRUNC;
    fd: any = os.open(path, flags, 384);
    f: any;
    with os.fdopen(fd, "wb") as f {
        f.write(data);
    }
}

impl _restore(data: builtins.bytes, backup: Path, target: Path) -> None {
    tmp: any = target.with_name(f".{target.name}.restore.tmp");
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

impl _label(change: PlannedChange) -> builtins.str {
    return CLAUDE_LABEL if change.client == "claude" else CODEX_LABEL;
}

impl _cant_back_up(label: builtins.str, e: any) -> any {
    return InstallError(
        f"{label} couldn't be read or backed up ({e.strerror or `type(e).__name__}), so nothing was changed.",
    );
}

impl _read(change: PlannedChange) -> builtins.bytes | None {
    path: any;
    label: any;
    (path, label) = (change.path, _label(change));
    if path.is_symlink() {
        raise InstallError(_symlink_refusal(label));
    }
    try {
        return path.read_bytes() if path.exists() else None;
    } except OSError as e {
        raise _cant_back_up(label, e);
    }
}

impl _back_up(change: PlannedChange, data: builtins.bytes | None, now: datetime) -> Path | None {
    if data is None {
        return None;
    }
    path: any = change.path;
    try {
        backup: any = _backup_path(path, now);
        _write_private(backup, data, exclusive=True);
        shutil.copymode(path, backup);
        return backup;
    } except OSError as e {
        raise _cant_back_up(_label(change), e);
    }
}

impl _read_and_back_up(change: PlannedChange, now: datetime) -> builtins.tuple[builtins.bytes
    | None, Path | None] {
    data: any = _read(change);
    return (data, _back_up(change, data, now));
}

impl _apply_file(change: PlannedChange, now: datetime) -> None {
    path: any = change.path;
    data: any = _read(change);
    existed: any = data is not None;
    try {
        original: any = data.decode("utf-8") if existed else "";
        if change.client == "claude" {
            new_text: any;
            parts: any;
            (new_text, parts) = (_claude_new_text(change.action, original), _claude_parts);
        } else {
            (new_text, parts) = (_codex_new_text(change.action, original), _codex_parts);
        }
    } except (ValueError, UnicodeDecodeError) {
        bad: any = REFUSE_BAD_JSON if change.client == "claude" else REFUSE_BAD_TOML;
        raise InstallError(bad);
    }
    backup: any = _back_up(change, data, now);
    try {
        _write_atomic(path, new_text);
        rest_after: any;
        ours_after: any;
        (rest_after, ours_after) = parts(path.read_bytes().decode("utf-8")) as any;
        rest_before: any;
        _: any;
        (rest_before, _) = parts(original) as any;
        wanted: any = None if change.action == "remove" else server_entry();
        ok: any = operator.eq(rest_after, rest_before) and operator.eq(ours_after, wanted);
    } except Exception {
        ok = False;
    }
    if not ok {
        if existed {
            _restore(data, backup, path);
        } else {
            path.unlink(missing_ok=True);
        }
        raise InstallVerifyFailed(VERIFY_FAILED);
    }
}

impl _run_cli(argv: any, runner) -> None {
    try {
        result: any = runner(
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
        detail: any = ((result.stderr or result.stdout or "").strip().splitlines() or [""])[-1];
        raise InstallError(f"`{shlex.join(argv[:3])}` failed: {detail}".rstrip(": "));
    }
}

impl _kept_at(backup: Path | None) -> builtins.str {
    return f" Your previous file is at {backup}." if backup else "";
}

impl _apply_cli(
    change: PlannedChange, runner, now: datetime, *, expect_absent: builtins.bool
) -> None {
    _: any;
    backup: any;
    (_, backup) = _read_and_back_up(change, now) as any;
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
    doc: any;
    refusal: any;
    (doc, refusal) = _read_claude(change.path) as any;
    `entry: any = (doc or {}).get("mcpServers", {}).get(SERVER_NAME);
    if refusal or not (`entry is None if expect_absent else _same(`entry)) {
        raise InstallError(
            "Claude Code's config didn't end up as expected after `claude mcp`." + _kept_at(backup)
        );
    }
}

impl apply_change(
    change: PlannedChange, *, runner=runner_default___, now: datetime
) -> builtins.str {
    name: any = CLIENT_NAMES[change.client];
    if change.action == "refuse" {
        return change.reason;
    }
    if change.action == "none" {
        return change.reason or f"Already set up for {name}.";
    }
    removing: any = operator.eq(change.action, "remove")
        or operator.eq(change.argv[2:3], ("remove",));
    done: any = f"Removed Sellbird from {name}." if removing else f"Added Sellbird to {name}.";
    if change.action == "cli" {
        _apply_cli(change, runner, now, expect_absent=removing);
        return f"{done} Start a new Claude Code session to use it.";
    }
    _apply_file(change, now);
    if change.client == "claude" {
        return f"{done} {RESTART_CLAUDE}";
    }
    return f"{done} Restart Codex to pick it up.";
}

impl print_config -> builtins.str {
    `entry: any = server_entry();
    return "\n\n".join([
        json.dumps({"mcpServers": {SERVER_NAME: `entry}}, indent=2),
        render_codex_block(`entry).rstrip("\n"),
        "Any other MCP client: command "
            + format(`entry["command"], "")
            + ", args -P -m sellbird mcp, env "
            + format(HOME_ENV, "")
            + "="
            + format(`entry["env"][HOME_ENV], ""),
    ]);
}

impl _codex_detected(which, env: Mapping[builtins.str, builtins.str], home: Path) -> builtins.bool {
    return `bool(which("codex")) or _codex_path(env, home).parent.is_dir();
}

impl run_command(
    action: builtins.str,
    client: builtins.str | None,
    *,
    print_only: builtins.bool = False,
    yes: builtins.bool = False,
    home: Path | None = None,
    env: Mapping[builtins.str, builtins.str] | None = None,
    which=which_default___,
    runner=runner_default____,
    isatty: Callable[[], builtins.bool] | None = None,
    ask: Callable[[builtins.str], builtins.str] = ask_default_,
    out: Callable[[builtins.str], None] = out_default_,
    now: datetime | None = None,
) -> builtins.int {
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
    isatty = isatty or sys.stdin.isatty;
    target: any = client or "claude";
    if target == "claude" {
        plan: any = plan_claude if action == "install" else plan_uninstall_claude;
        change: any = plan(home=home, which=which, runner=runner);
    } else {
        plan = plan_codex if action == "install" else plan_uninstall_codex;
        change = plan(env=env, home=home);
    }

    if client is None and _codex_detected(which, env, home) {
        verb: any = "add Sellbird to it too"
            if action == "install"
            else "remove Sellbird from it too";
        hint: any = f"Codex found. To {verb}, run: sellbird mcp {action} codex";
    } else {
        hint = "";
    }

    code: any = _show_and_apply(
        change, yes=yes, isatty=isatty, ask=ask, out=out, runner=runner, now=now or datetime.now()
    );
    if hint {
        out(hint);
    }
    return code;
}

impl _show_and_apply(change: PlannedChange, *, yes, isatty, ask, out, runner, now) -> builtins.int {
    name: any = CLIENT_NAMES[change.client];
    if change.action == "refuse" {
        out(change.reason);
        return 1;
    }
    if change.action == "none" {
        out(apply_change(change, runner=runner, now=now));
        return 0;
    }
    if change.action == "cli" {
        out(f"{name}: this will run");
    } else {
        out(f"{name}: {change.path}");
    }
    out(change.preview);
    if not yes {
        if not isatty() {
            out(NOT_TTY);
            return 2;
        }
        if ask("Apply this change? [y/N] ").strip().lower() not in ("y", "yes") {
            out("Nothing was changed.");
            return 1;
        }
    }
    try {
        out(apply_change(change, runner=runner, now=now));
    } except InstallError as e {
        out(`str(e));
        return 1;
    }
    return 0;
}
