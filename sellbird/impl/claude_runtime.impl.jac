impl ClaudeRuntimeError.__repr__ -> str {
    return (getattr(builtins.super(ClaudeRuntimeError, self), "__repr__") as any)();
}

impl ClaudeRuntimeError.__eq__(other: any) -> bool {
    return self is other;
}

impl ClaudeRuntimeError.__hash__ -> int {
    return id(self);
}

impl _shim_target(shim: Path) -> Path {
    try {
        m: any = _SHIM_TARGET_RE.search(shim.read_text(encoding="utf-8", errors="replace"));
    } except OSError {
        m = None;
    }
    if m {
        target: any = m.group(1).replace("\\", "/");
        return Path(target) if re.match("[A-Za-z]:/", target) else shim.parent / target;
    }
    return shim.parent / "node_modules" / "@anthropic-ai" / "claude-code" / "bin" / "claude.exe";
}

impl _locate(env: dict | None) -> tuple[str | None, Path | None] {
    path: any = (env if env is not None else os.environ).get("PATH");
    found: any = shutil.which("claude", path=path);
    if not found or _PLATFORM != "win32" or not found.lower().endswith((".cmd", ".bat")) {
        return (found, None);
    }
    return (found, _shim_target(Path(found)));
}

impl find_claude(env: dict | None = None) -> str | None {
    found: any;
    native: any;
    (found, native) = _locate(env) as any;
    if native is None {
        return found;
    }
    try {
        size: any = native.stat().st_size if native.is_file() else None;
    } except OSError {
        size = None;
    }
    if size is not None and size >= _MIN_NATIVE_BYTES {
        return `str(native);
    }
    problem: any = "is only a placeholder: the package's install script didn't run"
        if size is not None
        else "isn't there";
    raise ClaudeRuntimeError(
        f"Found the claude.cmd shim ({found}), but the claude.exe it launches ({native}) {problem}. Sellbird never runs Claude through cmd.exe, which re-parses the flags that keep each call isolated. {INSTALL_HINT}",
    );
}

impl runtime_env(cwd: str, base: dict | None = None) -> dict {
    env: any = `dict(os.environ if base is None else base);
    for key in STRIPPED_ENV {
        env.pop(key, None);
    }
    env["PWD"] = cwd;
    env["CLAUDE_CODE_SAFE_MODE"] = "1";
    return env;
}

impl build_command(executable: str, model: str = "", session_id: str | None = None) -> list[str] {
    cmd: any = [
        executable,
        "-p",
        "--output-format",
        "json",
        "--tools",
        "",
        "--strict-mcp-config",
        "--safe-mode",
        "--setting-sources",
        "",
        "--disable-slash-commands",
        "--no-session-persistence",
    ];
    if model {
        cmd += ["--model", model];
    }
    if session_id {
        try {
            uuid.UUID(session_id);
            cmd += ["--session-id", session_id];
        } except ValueError {}
    }
    return cmd;
}

impl isolated_cwd -> Generator[any, any, any] {
    tmp: any;
    with tempfile.TemporaryDirectory(prefix="sellbird-claude-", ignore_cleanup_errors=True) as tmp {
        yield `str(Path(tmp).resolve());
    }
}

impl _fingerprint(executable: str) -> tuple[str, int | None, int | None] {
    real: any = os.path.realpath(executable);
    try {
        st: any = os.stat(real);
        return (real, st.st_mtime_ns, st.st_size);
    } except OSError {
        return (real, None, None);
    }
}

impl fingerprint(env: dict | None = None) -> tuple {
    found: any;
    native: any;
    (found, native) = _locate(env) as any;
    exe: any = `str(native) if native is not None else found;
    return _fingerprint(exe) if exe else ("", None, None);
}

impl _probe_help(executable: str) -> str {
    cwd: any;
    with isolated_cwd() as cwd {
        out: any = subprocess.run(
            [executable, "--help"],
            cwd=cwd,
            env=runtime_env(cwd),
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=HELP_TIMEOUT_SECONDS,
        );
    }
    out.check_returncode();
    return (out.stdout or "") + (out.stderr or "");
}

impl missing_flags(help_text: str) -> list[str] {
    return [
        f
        for f in REQUIRED_FLAGS
        if not re.search(f"(?<![\\w-]){re.escape(f)}(?![\\w-])", help_text)
    ];
}

impl check_cli(env: dict | None = None) -> str {
    exe: any = find_claude(env);
    if not exe {
        raise ClaudeRuntimeError(
            "Claude CLI not found on PATH. Install it (https://code.claude.com/docs/en/setup) and run 'claude login'.",
        );
    }
    key: any = _fingerprint(exe);
    with _capable_lock {
        if _capable.get(key) {
            return exe;
        }
    }
    try {
        help_text: any = _probe_help(exe);
    } except (OSError, subprocess.SubprocessError) as e {
        raise ClaudeRuntimeError(
            f"Could not run '{exe} --help' to check the Claude CLI ({`type(e).__name__}). Sellbird sends no prompt until it can confirm the CLI isolates calls.",
        ) from e;
    }
    missing: any = missing_flags(help_text);
    if missing {
        raise ClaudeRuntimeError(
            "This Claude CLI ("
                + format(exe, "")
                + ") lacks "
                + format(", ".join(missing), "")
                + ", which Sellbird needs to keep your CLAUDE.md, hooks, skills, plugins and settings out of its prompts. Update it ('claude update', or rebuild the Docker image) and Sellbird resumes on its own. No prompt was sent.",
        );
    }
    with _capable_lock {
        _capable[key] = True;
    }
    return exe;
}

impl clear_cache -> any {
    with _capable_lock {
        _capable.clear();
    }
}
