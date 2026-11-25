impl require_supported_platform {
    if _PLATFORM == "darwin" or _PLATFORM.startswith("linux") {
        return;
    }
    raise CodexError(
        "Sellbird's Codex provider supports macOS and Linux only; it isn't supported on Windows yet. Use the Claude provider there (brain.provider: claude in sellbird.yaml).",
        kind="setup",
    );
}

impl CodexError.init(
    message: builtins.str, kind: builtins.str = "protocol", retryable: builtins.bool = False
) {
    super.init(message);
    self.kind = kind;
    self.retryable = retryable;
}

impl CodexError.__repr__ -> str {
    return (getattr(builtins.super(CodexError, self), "__repr__") as any)();
}

impl CodexError.__eq__(other: any) -> bool {
    return self is other;
}

impl CodexError.__hash__ -> int {
    return id(self);
}

impl _setup_error(message: builtins.str) -> any {
    return CodexError(message, kind="setup");
}

impl _isolation_error(message: builtins.str) -> any {
    return CodexError(
        f"Codex isolation could not be verified: {message}. Nothing was sent to the model.",
        kind="isolation",
    );
}

impl native_codex_home -> Path {
    `override: any = os.environ.get("CODEX_HOME", "").strip();
    if `override {
        return Path(`override).expanduser();
    }
    return Path.home() / ".codex";
}

impl find_codex -> builtins.str | None {
    return shutil.which("codex");
}

impl check_native_auth(home: Path | None = None) -> Path {
    return _load_native_auth(home)[0];
}

impl _load_native_auth(home: Path | None = None) -> builtins.tuple[Path, builtins.dict] {
    require_supported_platform();
    home = home or native_codex_home();
    auth_file: any = home / "auth.json";
    try {
        st: any = auth_file.stat();
    } except FileNotFoundError {
        raise _setup_error(
            f"No Codex login found at {auth_file}. Run 'codex login' and sign in with ChatGPT. Sellbird supports Codex's file credential storage only (cli_auth_credentials_store = \"file\", the default when no OS keyring is configured).",
        );
    } except OSError as e {
        raise _setup_error(f"Cannot access {auth_file}: {e.strerror or e}");
    }
    if not stat.S_ISREG(st.st_mode) {
        raise _setup_error(f"{auth_file} is not a regular file.");
    }
    if st.st_uid != os.getuid() {
        raise _setup_error(f"{auth_file} is not owned by the user running Sellbird.");
    }
    if st.st_mode & 63 {
        raise _setup_error(f"{auth_file} is readable by other users. Run: chmod 600 {auth_file}");
    }
    try {
        data: any = json.loads(auth_file.read_text(encoding="utf-8"));
    } except (OSError, ValueError) {
        raise _setup_error(f"{auth_file} is not readable Codex login data. Run 'codex login'.");
    }
    mode: any = data.get("auth_mode") if isinstance(data, `dict) else None;
    tokens: any = data.get("tokens") if isinstance(data, `dict) else None;
    if mode not in (None, "chatgpt")
        or not isinstance(tokens, `dict)
        or not isinstance(tokens.get("access_token"), `str)
        or not tokens["access_token"]
        or not isinstance(tokens.get("id_token"), `str)
        or not tokens["id_token"]
    {
        raise _setup_error(
            "Codex is not logged in with a ChatGPT account. Sellbird only uses your ChatGPT subscription, never an API key. Run 'codex login' and choose 'Sign in with ChatGPT'.",
        );
    }
    return (auth_file, data);
}

impl _jwt_expiry(token: builtins.str) -> builtins.float | None {
    try {
        payload: any = token.split(".")[1];
        claims: any = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)));
    } except (IndexError, ValueError, TypeError) {
        return None;
    }
    exp: any = claims.get("exp") if isinstance(claims, `dict) else None;
    return `float(exp) if isinstance(exp, (`int, `float)) and not isinstance(exp, `bool) else None;
}

impl _parse_timestamp(value) -> builtins.float | None {
    if not isinstance(value, `str) {
        return None;
    }
    text: any = re.sub("(\\.\\d{6})\\d+", "\\1", value.strip()).replace("Z", "+00:00");
    try {
        parsed: any = datetime.fromisoformat(text);
    } except ValueError {
        return None;
    }
    return parsed.timestamp() if parsed.tzinfo else None;
}

impl build_access_snapshot(
    native: builtins.dict, now: builtins.float | None = None
) -> builtins.dict {
    tokens: any = native["tokens"];
    now = time.time() if now is None else now;
    expiry: any = _jwt_expiry(tokens["access_token"]);
    refreshed: any = _parse_timestamp(native.get("last_refresh"));
    if expiry is None
        or expiry - now < ACCESS_TOKEN_MIN_SECONDS
        or refreshed is None
        or now - refreshed > CODEX_RENEWAL_AGE_SECONDS - RENEWAL_MARGIN_SECONDS
    {
        raise CodexError(
            "Your Codex login has expired or is due for renewal. Sellbird never renews Codex logins itself (it gives Codex a copy without the refresh token): use Codex once, which renews a login older than 8 days, or run 'codex login'. Sellbird picks the renewed login up on its next call.",
            kind="auth",
        );
    }
    snapshot_tokens: any = {
        "id_token": tokens["id_token"],
        "access_token": tokens["access_token"],
        "refresh_token": "",
    };
    if isinstance(tokens.get("account_id"), `str) {
        snapshot_tokens["account_id"] = tokens["account_id"];
    }
    return {
        "auth_mode": "chatgpt",
        "OPENAI_API_KEY": None,
        "tokens": snapshot_tokens,
        "last_refresh": native["last_refresh"],
    };
}

impl parse_cli_version(raw: builtins.bytes) -> builtins.str {
    `match: any = re.search(
        b"\\b(\\d+\\.\\d+\\.\\d+(?:[-+.][0-9A-Za-z.-]+)?)\\s*$", (raw or b"").strip()
    );
    return `match.group(1).decode() if `match else "";
}

impl require_supported_version(version: builtins.str) {
    if version not in SUPPORTED_CODEX_VERSIONS {
        raise _setup_error(
            "Codex CLI "
                + format(version or "(unknown version)", "")
                + " hasn't been verified with Sellbird, so Sellbird won't send it prompts: a different Codex can add tools Sellbird's lockdown doesn't know about. Supported: "
                + format(", ".join(SUPPORTED_CODEX_VERSIONS), "")
                + ". Install one with: "
                + format(CODEX_INSTALL_HINT, ""),
        );
    }
}

impl check_cli_version(
    codex_path: builtins.str | None = None, timeout: builtins.float = 30.0
) -> builtins.str {
    require_supported_platform();
    path: any = codex_path or find_codex();
    if not path {
        raise _setup_error(f"Codex CLI not found. Install it: {CODEX_INSTALL_HINT}");
    }
    `root: any = tempfile.mkdtemp(prefix=RUNTIME_PREFIX);
    try {
        home: any = os.path.join(`root, "codex-home");
        os.mkdir(home, 448);
        out: any = subprocess.run(
            [path, "--version"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            cwd=`root,
            env=build_child_env(`root, home),
            timeout=timeout,
        ).stdout;
    } except (OSError, subprocess.SubprocessError) as e {
        raise _setup_error(f"Could not run the Codex CLI ({`type(e).__name__}).");
    } finally {
        shutil.rmtree(`root, ignore_errors=True);
    }
    version: any = parse_cli_version(out);
    require_supported_version(version);
    return version;
}

impl _toml_value(value) -> builtins.str {
    if isinstance(value, `bool) {
        return "true" if value else "false";
    }
    if isinstance(value, `int) {
        return `str(value);
    }
    return json.dumps(`str(value));
}

impl build_private_config_toml -> builtins.str {
    lines: any = [f"{k} = {_toml_value(v)}" for (k, v) in REQUIRED_SETTINGS.items()];
    lines += [
        "check_for_update_on_startup = false",
        "notify = []",
        "",
        "[agents]",
        "enabled = false",
        "",
        "[analytics]",
        "enabled = false",
        "",
        "[skills]",
        "include_instructions = false",
        "",
        "[skills.bundled]",
        "enabled = false",
        "",
        "[tools.experimental_request_user_input]",
        "enabled = false",
        "",
        "[features]",
    ];
    lines += [f"{name} = false" for name in DISABLED_FEATURES];
    return "\n".join(lines) + "\n";
}

impl build_thread_config(mcp_server_names) -> builtins.dict {
    config: builtins.dict = `dict(REQUIRED_SETTINGS);
    config.update({
        "skills.include_instructions": False,
        "skills.bundled.enabled": False,
        "tools.experimental_request_user_input.enabled": False,
        "agents.enabled": False,
        "notify": [],
    });
    for name in DISABLED_FEATURES {
        config[f"features.{name}"] = False;
    }
    names: any = sorted(`set(mcp_server_names));
    if names {
        config["mcp_servers"] = {name: {"enabled": False} for name in names};
    }
    return config;
}

impl build_thread_params(
    workspace: builtins.str, model: builtins.str, mcp_server_names
) -> builtins.dict {
    params: any = {
        "cwd": workspace,
        "runtimeWorkspaceRoots": [workspace],
        "modelProvider": OPENAI_PROVIDER,
        "approvalPolicy": "never",
        "sandbox": "read-only",
        "serviceName": SERVICE_NAME,
        "baseInstructions": "",
        "developerInstructions": DEVELOPER_INSTRUCTIONS,
        "config": build_thread_config(mcp_server_names),
        "environments": [],
        "dynamicTools": [],
        "selectedCapabilityRoots": [],
        "ephemeral": True,
        "allowProviderModelFallback": False,
        "experimentalRawEvents": True,
    };
    if model {
        params["model"] = model;
    }
    return params;
}

impl build_child_env(
    private_root: builtins.str, codex_home: builtins.str, base_env=None
) -> builtins.dict {
    source: any = os.environ if base_env is None else base_env;
    env: any = {};
    for (key, value) in source.items() {
        upper: any = key.upper();
        if upper in ENV_ALLOWLIST or upper.startswith("LC_") {
            env[key] = value;
        }
    }
    env["HOME"] = private_root;
    env["CODEX_HOME"] = codex_home;
    return env;
}

impl attest_effective_config(
    response, model_catalog_path: builtins.str = ""
) -> builtins.list[builtins.str] {
    if not isinstance(response, `dict) or not isinstance(response.get("config"), `dict) {
        raise _isolation_error("config/read returned no effective config");
    }
    config: any = response["config"];

    key: any;
    for (key, expected) in REQUIRED_SETTINGS.items() {
        if config.get(key) != expected {
            raise _isolation_error(f"setting '{key}' is not {expected!r}");
        }
    }

    provider: any = config.get("model_provider");
    if provider not in (None, OPENAI_PROVIDER) {
        raise _isolation_error("a custom model provider is configured");
    }
    if config.get("chatgpt_base_url") not in (None, DEFAULT_CHATGPT_BASE_URL) {
        raise _isolation_error("a custom ChatGPT endpoint is configured");
    }
    for key in MUST_BE_EMPTY {
        if key == "model_catalog_json" and model_catalog_path {
            if config.get(key) != model_catalog_path {
                raise _isolation_error("the private model catalog was overridden");
            }
            continue;
        }
        if config.get(key) not in (None, "", [], {}) {
            raise _isolation_error(f"setting '{key}' is set by another config layer");
        }
    }
    endpoint: any = _find_custom_endpoint(config);
    if endpoint {
        raise _isolation_error(f"a custom endpoint is configured ({endpoint})");
    }

    features: any = config.get("features");
    if not isinstance(features, `dict) {
        raise _isolation_error("feature flags are unreadable");
    }
    for name in DISABLED_FEATURES {
        if features.get(name) is not False {
            raise _isolation_error(f"feature '{name}' is not disabled");
        }
    }

    skills: any = config.get("skills");
    bundled: any = skills.get("bundled") if isinstance(skills, `dict) else None;
    if not isinstance(skills, `dict)
        or skills.get("include_instructions") is not False
        or not isinstance(bundled, `dict)
        or bundled.get("enabled") is not False
    {
        raise _isolation_error("skill instructions are not disabled");
    }

    agents: any = config.get("agents");
    if not isinstance(agents, `dict) or agents.get("enabled") is not False {
        raise _isolation_error("sub-agents are not disabled");
    }

    servers: any = config.get("mcp_servers");
    if servers in (None, {}) {
        return [];
    }
    if not isinstance(servers, `dict) {
        raise _isolation_error("MCP server config is unreadable");
    }
    return sorted(`str(name) for name in servers);
}

impl _find_custom_endpoint(config: builtins.dict) -> builtins.str {
    value: any;
    stack: any = [
        (key, value)
        for (key, value) in config.items()
        if key not in _ENDPOINT_SCAN_EXEMPT
    ];
    while stack {
        path: any;
        (path, value) = stack.pop() as any;
        if isinstance(value, `dict) {
            stack += [(f"{path}.{k}", v) for (k, v) in value.items()];
        } elif isinstance(value, `list) {
            stack += [(f"{path}[{i}]", v) for (i, v) in enumerate(value)];
        } elif isinstance(value, `str) and _URL_RE.match(value) {
            if path == "chatgpt_base_url" and value == DEFAULT_CHATGPT_BASE_URL {
                continue;
            }
            return path;
        }
    }
    return "";
}

impl attest_thread(
    response, requested_model: builtins.str
) -> builtins.tuple[builtins.str, builtins.str] {
    if not isinstance(response, `dict) or not isinstance(response.get("thread"), `dict) {
        raise _isolation_error("thread/start returned no thread");
    }
    sources: any = response.get("instructionSources");
    if not isinstance(sources, `list) {
        raise _isolation_error("thread/start omitted its instruction sources");
    }
    if sources {
        raise _isolation_error(f"{len(sources)} instruction file(s) were loaded");
    }
    if response.get("modelProvider") != OPENAI_PROVIDER {
        raise _isolation_error("the thread is not using the built-in OpenAI provider");
    }
    if response.get("approvalPolicy") != "never" {
        raise _isolation_error("the thread approval policy is not 'never'");
    }
    sandbox: any = response.get("sandbox");
    if not isinstance(sandbox, `dict)
        or sandbox.get("type") != "readOnly"
        or sandbox.get("networkAccess")
    {
        raise _isolation_error("the thread sandbox is not read-only without network");
    }
    if requested_model and response.get("model") != requested_model {
        raise CodexError(
            f"Codex would not run the configured model '{requested_model}'. Check brain.model in sellbird.yaml.",
            kind="setup",
        );
    }
    thread_id: any = response["thread"].get("id");
    if not isinstance(thread_id, `str) or not thread_id {
        raise _isolation_error("thread/start returned no thread id");
    }
    model: any = response.get("model");
    return (thread_id, model if isinstance(model, `str) else "");
}

impl attest_mcp_status(pages, expected_names) {
    expected: any = `set(expected_names);
    for page in pages {
        if not isinstance(page, `dict) or not isinstance(page.get("data"), `list) {
            raise _isolation_error("MCP status is unreadable");
        }
        for server in page["data"] {
            if not isinstance(server, `dict) or not isinstance(server.get("name"), `str) {
                raise _isolation_error("MCP status is malformed");
            }
            tools: any = server.get("tools");
            if server["name"] not in expected
                or not isinstance(tools, `dict)
                or tools
                or server.get("serverInfo") is not None
            {
                raise _isolation_error(
                    "MCP server '" + format(server["name"], "") + "' is not fully disabled"
                );
            }
        }
    }
}

impl attest_hooks(response) {
    if not isinstance(response, `dict) or not isinstance(response.get("data"), `list) {
        raise _isolation_error("hook list is unreadable");
    }
    for `entry in response["data"] {
        if not isinstance(`entry, `dict) or `entry.get("hooks") != [] {
            raise _isolation_error("hooks are configured");
        }
    }
}

impl parse_model_catalog(raw: builtins.bytes) -> builtins.dict {
    try {
        data: any = json.loads(raw or b"null");
    } except ValueError {
        data = None;
    }
    models: any = data.get("models") if isinstance(data, `dict) else None;
    if not isinstance(models, `list) {
        raise _isolation_error("the Codex model catalog is unreadable");
    }
    return {
        m["slug"]: m
        for m in models
        if isinstance(m, `dict) and isinstance(m.get("slug"), `str)
    };
}

impl model_tools_removable(`entry) -> builtins.bool {
    return isinstance(`entry, `dict)
        and `entry.get("tool_mode") in (None, "", "direct")
        and not `entry.get("experimental_supported_tools");
}

impl text_only_catalog(catalog: builtins.dict) -> builtins.dict {
    return {
        slug: {**`entry, "tool_mode": "direct", "experimental_supported_tools": []}
            if `entry.get("tool_mode") in (None, "", "direct", "code_mode", "code_mode_only")
            else `dict(`entry)
        for (slug, `entry) in catalog.items()
    };
}

impl _safe_name(value) -> builtins.str {
    return re.sub("[^A-Za-z0-9._:-]", "?", `str(value))[:40];
}

impl describe_model(`entry) -> builtins.str {
    if not isinstance(`entry, `dict) {
        return "unreadable";
    }
    if `entry.get("tool_mode") not in (None, "", "direct") {
        return "code mode (" + format(_safe_name(`entry["tool_mode"]), "") + ")";
    }
    extra: any = `entry.get("experimental_supported_tools");
    if extra {
        names: any = extra if isinstance(extra, `list) else [extra];
        return "extra tools (" + ", ".join(_safe_name(t) for t in names[:5]) + ")";
    }
    if `entry.get("visibility") != "list" {
        return "tool-less but not listed (visibility "
            + format(_safe_name(`entry.get("visibility")), "")
            + ")";
    }
    return "tool-less";
}

impl describe_catalog(catalog: builtins.dict, limit: builtins.int = 20) -> builtins.str {
    parts: any = [
        f"{_safe_name(slug)}: {describe_model(m)}"
        for (slug, m) in `list(catalog.items())[:limit]
    ];
    if len(catalog) > limit {
        parts.append(f"… {len(catalog) - limit} more");
    }
    return "; ".join(parts) or "empty";
}

impl _unlisted_toolless(catalog: builtins.dict) -> builtins.list[builtins.str] {
    return [
        slug
        for (slug, m) in catalog.items()
        if model_tools_removable(m) and m.get("visibility") != "list"
    ];
}

impl require_toolless_model(catalog: builtins.dict, model: builtins.str) {
    `entry: any = catalog.get(model);
    if `entry is None {
        raise _isolation_error(
            f"model '{model}' is not in the Codex model catalog, so its tools can't be checked (catalog: {describe_catalog(catalog)})",
        );
    }
    if not model_tools_removable(`entry) {
        usable: any = [slug for (slug, m) in catalog.items() if model_tools_removable(m)];
        hint: any = " Models that work: " + format(", ".join(usable), "") + "." if usable else "";
        raise CodexError(
            f"Codex model '{model}' always exposes tools that Sellbird cannot disable ({describe_model(`entry)}), so Sellbird won't send it prompts.{hint} Set brain.model in sellbird.yaml.",
            kind="isolation",
        );
    }
}

impl pick_default_model(catalog: builtins.dict) -> builtins.str {
    candidates: any = sorted(
        (m for m in catalog.values() if model_tools_removable(m) and m.get("visibility") == "list"),
        key=lambda (m) -> any {
            (m.get("priority") if isinstance(m.get("priority"), `int) else 1 << 30, m["slug"])
        },
    );
    if not candidates {
        unlisted: any = _unlisted_toolless(catalog);
        if unlisted {
            raise CodexError(
                "Codex lists no model whose tools can all be disabled, but these unlisted ones can: "
                    + format(", ".join(_safe_name(s) for s in unlisted), "")
                    + ". Sellbird won't pick an unlisted model on its own; to use one, set brain.model in sellbird.yaml.",
                kind="setup",
            );
        }
        raise _isolation_error(
            f"no Codex model is available whose tools can all be disabled (catalog: {describe_catalog(catalog)})",
        );
    }
    return candidates[0]["slug"];
}

impl _iso_from_unix(value) -> builtins.str {
    if not isinstance(value, (`int, `float)) or value <= 0 {
        return "";
    }
    return datetime.fromtimestamp(value, tz=timezone.utc).isoformat().replace("+00:00", "Z");
}

impl parse_rate_limits(snapshot) -> builtins.dict | None {
    if not isinstance(snapshot, `dict) {
        return None;
    }
    windows: any = {};
    for slot in ("primary", "secondary") {
        w: any = snapshot.get(slot);
        if not isinstance(w, `dict) or not isinstance(w.get("usedPercent"), (`int, `float)) {
            continue;
        }
        minutes: any = w.get("windowDurationMins");
        if minutes == 300 {
            name: any = "five_hour";
        } elif minutes == 10080 {
            name = "seven_day";
        } else {
            name = slot;
        }
        windows[name] = {
            "utilization": `float(w["usedPercent"]),
            "resets_at": _iso_from_unix(w.get("resetsAt")),
            "window_minutes": `int(minutes) if isinstance(minutes, `int) else None,
        };
    }
    return windows or None;
}

impl bucket_applies(snapshot, model: builtins.str) -> builtins.bool {
    if not isinstance(snapshot, `dict) {
        return False;
    }
    slug: any = snapshot.get("normalModelSlug");
    if slug {
        return `bool(model) and operator.eq(slug, model);
    }
    return snapshot.get("limitId") in (None, "", GENERAL_LIMIT_ID);
}

impl _usage_blocked(snapshot) -> builtins.bool {
    return isinstance(snapshot, `dict)
        and (
            snapshot.get("spendControlReached") is True
            or `bool(snapshot.get("rateLimitReachedType"))
        );
}

impl select_rate_limits(response, model: builtins.str) -> builtins.dict | None {
    if not isinstance(response, `dict) {
        return None;
    }
    buckets: any = response.get("rateLimitsByLimitId");
    buckets = buckets if isinstance(buckets, `dict) else {};
    `own: any = [
        b
        for b in buckets.values()
        if isinstance(b, `dict) and model and b.get("normalModelSlug") == model
    ];
    general: any = [
        b
        for (key, b) in buckets.items()
        if isinstance(b, `dict)
            and not b.get("normalModelSlug")
            and GENERAL_LIMIT_ID in (key, b.get("limitId"))
    ];
    chosen: any = (`own or general or [None])[0];
    if chosen is None and bucket_applies(response.get("rateLimits"), model) {
        chosen = response["rateLimits"];
    }
    windows: any = parse_rate_limits(chosen) or {};
    if response.get("ordinaryUsageAllowed") is False or _usage_blocked(chosen) {
        return mark_exhausted(windows);
    }
    return windows or None;
}

impl mark_exhausted(windows: builtins.dict) -> builtins.dict {
    if not windows {
        return {
            LIMIT_REACHED_WINDOW: {"utilization": 100.0, "resets_at": "", "window_minutes": None},
        };
    }
    for window in windows.values() {
        window["utilization"] = max(window["utilization"], 100.0);
    }
    return windows;
}

impl normalize_usage(token_usage) -> builtins.dict {
    counts: any;
    if not isinstance(token_usage, `dict) {
        return {};
    }
    counts = token_usage.get("total")
        if isinstance(token_usage.get("total"), `dict)
        else token_usage.get("last");
    if not isinstance(counts, `dict) {
        return {};
    }

    def num(key) -> any {
        v: any = counts.get(key);
        return `int(v) if isinstance(v, (`int, `float)) and v >= 0 else 0;
    }

    cached: any = num("cachedInputTokens");
    return {
        "input_tokens": max(num("inputTokens") - cached, 0),
        "cache_read_tokens": cached,
        "cache_creation_tokens": num("cacheWriteInputTokens"),
        "output_tokens": num("outputTokens"),
    };
}

impl _classify_turn_error(error) -> any {
    info: any = error.get("codexErrorInfo") if isinstance(error, `dict) else None;
    code: any = info
        if isinstance(info, `str)
        else next(iter(info)) if isinstance(info, `dict) and info else "";
    kind: any = _NON_RETRYABLE_TURN_ERRORS.get(code);
    if kind == "auth" {
        return CodexError("Codex rejected the ChatGPT login. Run 'codex login'.", kind="auth");
    }
    if kind == "usage_limit" {
        return CodexError("Codex usage limit reached for this ChatGPT plan.", kind="usage_limit");
    }
    if kind {
        return CodexError(f"Codex refused the request ({code}).", kind="request");
    }
    return CodexError(
        "Codex turn failed (" + format(code or "unknown error", "") + ").",
        kind="turn_failed",
        retryable=True,
    );
}

impl _timeout_error -> any {
    return CodexError("Codex call timed out.", kind="timeout", retryable=True);
}

impl _remaining(deadline: builtins.float) -> builtins.float {
    remaining: any = deadline - time.monotonic();
    if remaining <= 0 {
        raise _timeout_error();
    }
    return remaining;
}

impl _wait_exit(proc) -> any {
    try {
        await asyncio.wait_for(proc.wait(), KILL_WAIT_SECONDS);
    } except (asyncio.TimeoutError, ProcessLookupError) {}
}

impl server_version(initialize_response) -> builtins.str {
    agent: any = initialize_response.get("userAgent")
        if isinstance(initialize_response, `dict)
        else None;
    if not isinstance(agent, `str) or not agent.strip() {
        return "";
    }
    return agent.split()[0].partition("/")[2];
}

impl _AppServer.init(codex_path: builtins.str) {
    self.codex_path = codex_path;
    self.root = "";
    self.codex_home = "";
    self.workspace = "";
    self.version = "";
    self.model_catalog_path = "";
    self.proc = None;
    self._next_id = 1;
    self._stderr_tail = b"";
    self._stderr_task = None;
    self.on_message = None;
}

impl _AppServer.prepare -> any {
    try {
        self.root = tempfile.mkdtemp(prefix=RUNTIME_PREFIX);
        self.codex_home = os.path.join(self.root, "codex-home");
        self.workspace = os.path.join(self.root, "workspace");
        os.mkdir(self.codex_home, 448);
        os.mkdir(self.workspace, 448);
        os.chmod(self.root, 448);
        f: any;
        with open(os.path.join(self.codex_home, "config.toml"), "w", encoding="utf-8") as f {
            f.write(build_private_config_toml());
        }
    } except OSError as e {
        raise CodexError(
            f"Could not create Codex's private runtime folder ({`type(e).__name__}).",
            kind="runtime",
        ) from None;
    }
}

impl _AppServer.install_auth(snapshot: builtins.dict) -> any {
    path: any = os.path.join(self.codex_home, "auth.json");
    try {
        fd: any = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 384);
        f: any;
        with os.fdopen(fd, "w", encoding="utf-8") as f {
            json.dump(snapshot, f);
        }
    } except OSError as e {
        raise CodexError(
            f"Could not prepare Codex's private login copy ({`type(e).__name__}).", kind="runtime"
        ) from None;
    }
}

impl _AppServer.install_model_catalog(catalog: builtins.dict) {
    self.model_catalog_path = os.path.join(self.codex_home, "text-models.json");
    f: any;
    with open(self.model_catalog_path, "x", encoding="utf-8") as f {
        json.dump({"models": `list(catalog.values())}, f);
    }
    path: any = os.path.join(self.codex_home, "config.toml");
    with open(path, encoding="utf-8") as f {
        config: any = f.read();
    }
    with open(path, "w", encoding="utf-8") as f {
        f.write(f"model_catalog_json = {_toml_value(self.model_catalog_path)}\n" + config);
    }
}

impl _AppServer._child_kwargs -> builtins.dict {
    return {
        "cwd": self.workspace,
        "env": build_child_env(self.root, self.codex_home),
        "start_new_session": True,
    };
}

impl _AppServer.__repr__ -> str {
    return (getattr(builtins.object, "__repr__") as any)(self);
}

impl _AppServer.__eq__(other: any) -> bool {
    return self is other;
}

impl _AppServer.__hash__ -> int {
    return id(self);
}

impl _kill_tree(proc) -> any {
    try {
        os.killpg(proc.pid, signal.SIGKILL);
        return;
    } except (ProcessLookupError, PermissionError, OSError) {}
    try {
        proc.kill();
    } except ProcessLookupError {}
}

impl CodexClient.init(
    model: builtins.str = "",
    reasoning_effort: builtins.str = "",
    codex_path: builtins.str | None = None,
    native_home: Path | None = None,
) {
    self.model = model;
    self.reasoning_effort = reasoning_effort;
    self._codex_path = codex_path;
    self.native_home = native_home;
    self._lock = None;
    self.last_rate_limits = None;
    self._announced_default = "";
}

impl CodexClient._resolve_codex -> builtins.str {
    path: any = self._codex_path or find_codex();
    if not path {
        raise _setup_error(
            f"Codex CLI not found. Install it ({CODEX_INSTALL_HINT}), run 'codex login' with ChatGPT, then restart Sellbird.",
        );
    }
    return path;
}

impl CodexClient._serialize -> asyncio.Lock {
    if self._lock is None {
        self._lock = asyncio.Lock();
    }
    return self._lock;
}

impl CodexClient.fingerprint -> builtins.tuple {
    def meta(path) -> any {
        try {
            st: any = os.stat(path);
        } except (OSError, TypeError, ValueError) {
            return None;
        }
        return (st.st_ino, st.st_size, st.st_mtime_ns);
    }

    return (
        meta((self.native_home or native_codex_home()) / "auth.json"),
        meta(self._codex_path or find_codex()),
    );
}

impl CodexClient._default_model(catalog: builtins.dict) -> builtins.str {
    model: any = pick_default_model(catalog);
    if model != self._announced_default {
        logger.info(
            f"Codex: using {model}, the first listed model whose tools can be fully disabled. Set brain.model in sellbird.yaml to choose another.",
        );
        self._announced_default = model;
    }
    return model;
}

impl CodexClient._on_turn_message(turn: _Turn, method: builtins.str, params) -> any {
    if not isinstance(params, `dict) {
        return;
    }
    if params.get("threadId") not in (None, turn.thread_id) {
        return;
    }
    if method in ("item/started", "item/completed") {
        item: any = params.get("item");
        item_type: any = item.get("type") if isinstance(item, `dict) else None;
        if item_type not in ALLOWED_ITEM_TYPES {
            turn.violation = `str(item_type);
            return;
        }
        if method == "item/completed" and item_type == "agentMessage" {
            self._take_message(turn, item);
        }
    } elif method == "rawResponseItem/completed" {
        item = params.get("item");
        item_type = item.get("type") if isinstance(item, `dict) else None;
        if item_type not in ALLOWED_RAW_ITEM_TYPES {
            turn.violation = `str(item_type);
        }
    } elif method == "rawResponse/completed" {
        turn.model_responses += 1;
        if turn.model_responses > MAX_MODEL_RESPONSES_PER_TURN {
            turn.violation = "repeated model responses";
        }
    } elif method == "thread/tokenUsage/updated" {
        turn.token_usage = params.get("tokenUsage");
    } elif method == "account/rateLimits/updated" {
        snapshot: any = params.get("rateLimits");
        if bucket_applies(snapshot, turn.model) {
            parsed: any = parse_rate_limits(snapshot) or {};
            if _usage_blocked(snapshot) {
                parsed = mark_exhausted(parsed);
            }
            if parsed {
                turn.rate_limits = parsed;
            }
        }
    } elif method == "turn/completed" and isinstance(params.get("turn"), `dict) {
        self._accept_terminal(turn, params["turn"]);
    } elif method == "error" and params.get("willRetry") is not True {
        turn.status = "failed";
        turn.error = params.get("error");
    }
}

impl CodexClient._accept_terminal(turn: _Turn, payload: builtins.dict) -> any {
    status: any = payload.get("status");
    if status not in ("completed", "failed", "interrupted") {
        return;
    }
    for item in payload.get("items") or [] {
        if not isinstance(item, `dict) {
            continue;
        }
        if item.get("type") not in ALLOWED_ITEM_TYPES {
            turn.violation = `str(item.get("type"));
            return;
        }
        if item.get("type") == "agentMessage" {
            self._take_message(turn, item);
        }
    }
    turn.status = status;
    turn.error = payload.get("error") or turn.error;
    if isinstance(payload.get("durationMs"), `int) {
        turn.duration_ms = payload["durationMs"];
    }
}

impl CodexClient._take_message(turn: _Turn, item: builtins.dict) -> any {
    text: any = item.get("text");
    if not isinstance(text, `str) {
        return;
    }
    phase: any = item.get("phase");
    if phase == "final_answer" {
        turn.final_text = text;
    } elif phase in (None, "") {
        turn.unphased_text = text;
    }
}

impl CodexClient.__repr__ -> str {
    return (getattr(builtins.object, "__repr__") as any)(self);
}

impl CodexClient.__eq__(other: any) -> bool {
    return self is other;
}

impl CodexClient.__hash__ -> int {
    return id(self);
}

impl CodexQuotaClient.init(client: any) {
    self.client = client;
    self._cache = None;
    self._cache_at = 0.0;
    self._cache_ttl = 0.0;
    self._lock = None;
}

impl CodexQuotaClient.invalidate -> any {
    self._cache_at = 0.0;
}

impl CodexQuotaClient.__repr__ -> str {
    return (getattr(builtins.object, "__repr__") as any)(self);
}

impl CodexQuotaClient.__eq__(other: any) -> bool {
    return self is other;
}

impl CodexQuotaClient.__hash__ -> int {
    return id(self);
}

impl _AppServer._spawn(*args_, **kwargs) -> any {
    args: any = tuple(args_);
    try {
        return await asyncio.create_subprocess_exec(
            `self.codex_path, *args, **kwargs, **`self._child_kwargs()
        );
    } except OSError as e {
        raise _setup_error(
            f"Could not start the Codex CLI ({`type(e).__name__}). Install it: {CODEX_INSTALL_HINT}"
        ) from None;
    }
}

impl _AppServer.run_cli(args, deadline: builtins.float) -> builtins.tuple[builtins.int
    | None, builtins.bytes] {
    proc: any = await `self._spawn(
        *args,
        stdin=asyncio.subprocess.DEVNULL,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.DEVNULL,
    );
    try {
        out: any;
        _: any;
        (out, _) = await asyncio.wait_for(proc.communicate(), _remaining(deadline)) as any;
    } except asyncio.TimeoutError {
        raise _timeout_error() from None;
    } finally {
        if proc.returncode is None {
            await _kill_tree(proc);
            await _wait_exit(proc);
        }
    }
    return (proc.returncode, out);
}

impl _AppServer.read_version(deadline: builtins.float) -> builtins.str {
    code: any;
    out: any;
    (code, out) = await `self.run_cli(["--version"], deadline) as any;
    `self.version = parse_cli_version(out if code == 0 else b"");
    require_supported_version(`self.version);
    return `self.version;
}

impl _AppServer.read_catalog(deadline: builtins.float) -> builtins.dict {
    code: any;
    out: any;
    (code, out) = await `self.run_cli(["debug", "models"], deadline) as any;
    return parse_model_catalog(out if code == 0 else b"");
}

impl _AppServer.launch(deadline: builtins.float) -> any {
    `self._next_id = 1;
    `self.proc = await `self._spawn(
        "app-server",
        "--listen",
        "stdio://",
        stdin=asyncio.subprocess.PIPE,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        limit=MAX_PROTOCOL_LINE_BYTES,
    );
    `self._stderr_task = asyncio.ensure_future(`self._drain_stderr(`self.proc));

    `init: any = await `self.request(
        "initialize",
        {
            "clientInfo": {"name": CLIENT_NAME, "title": "Sellbird", "version": "1"},
            "capabilities": {
                "experimentalApi": True,
                "requestAttestation": False,
                "optOutNotificationMethods": OPTED_OUT_NOTIFICATIONS,
            },
        },
        deadline,
    );
    version: any = server_version(`init);
    if version != `self.version {
        require_supported_version(version);
        raise _setup_error(
            f"Codex app-server reported version {version}, not {`self.version}. Reinstall Codex so only one version is on PATH.",
        );
    }
    await `self.notify("initialized", {});
}

impl _AppServer.read_config(deadline: builtins.float) -> any {
    return await `self.request(
        "config/read", {"cwd": `self.workspace, "includeLayers": False}, deadline
    );
}

impl _AppServer.stop -> any {
    items_: any = list((`self.proc, None));
    if len(items_) != 2 {
        raise ValueError(
            f"too many values to unpack (expected 2, got {len(items_)})"
                if len(items_) > 2
                else f"not enough values to unpack (expected 2, got {len(items_)})",
        );
    }
    proc: any = items_[0];
    `self.proc = items_[1];
    items__: any = list((`self._stderr_task, None));
    if len(items__) != 2 {
        raise ValueError(
            f"too many values to unpack (expected 2, got {len(items__)})"
                if len(items__) > 2
                else f"not enough values to unpack (expected 2, got {len(items__)})",
        );
    }
    task: any = items__[0];
    `self._stderr_task = items__[1];
    try {
        if proc is not None and proc.returncode is None {
            await _kill_tree(proc);
            await _wait_exit(proc);
        }
    } finally {
        if task is not None {
            task.cancel();
        }
    }
}

impl _AppServer.close -> any {
    try {
        await `self.stop();
    } finally {
        if `self.root {
            shutil.rmtree(`self.root, ignore_errors=True);
            `self.root = "";
        }
    }
}

impl _AppServer._drain_stderr(proc) -> any {
    while proc.stderr is not None {
        chunk: any = await proc.stderr.read(4096);
        if not chunk {
            return;
        }
        `self._stderr_tail = (`self._stderr_tail + chunk)[-MAX_STDERR_TAIL_BYTES:];
    }
}

impl _AppServer._send(message: builtins.dict) -> any {
    if `self.proc is None or `self.proc.stdin is None {
        raise CodexError("Codex app-server is not running.", retryable=True);
    }
    try {
        `self.proc.stdin.write((json.dumps(message) + "\n").encode("utf-8"));
        await `self.proc.stdin.drain();
    } except (BrokenPipeError, ConnectionResetError) {
        raise CodexError("Codex app-server exited unexpectedly.", retryable=True) from None;
    }
}

impl _AppServer.notify(method: builtins.str, params) -> any {
    await `self._send({"method": method, "params": params});
}

impl _AppServer.read_message(deadline: builtins.float) -> builtins.dict {
    try {
        line: any = await asyncio.wait_for(`self.proc.stdout.readline(), _remaining(deadline));
    } except asyncio.TimeoutError {
        raise _timeout_error() from None;
    } except (ValueError, asyncio.LimitOverrunError) {
        raise CodexError("Codex app-server sent an oversized message.") from None;
    }
    if not line {
        raise CodexError("Codex app-server exited unexpectedly.", retryable=True);
    }
    try {
        message: any = json.loads(line);
    } except ValueError {
        raise CodexError("Codex app-server sent malformed output.") from None;
    }
    if not isinstance(message, `dict) {
        raise CodexError("Codex app-server sent malformed output.");
    }
    return message;
}

impl _AppServer.request(method: builtins.str, params, deadline: builtins.float) -> any {
    request_id: any = `self._next_id;
    `self._next_id += 1;
    await `self._send({"id": request_id, "method": method, "params": params});
    while True {
        message: any = await `self.read_message(deadline);
        if "method" in message {
            await `self.dispatch(message);
            continue;
        }
        if message.get("id") != request_id {
            continue;
        }
        if "error" in message {
            err: any = message.get("error");
            code: any = err.get("code") if isinstance(err, `dict) else None;
            raise CodexError(
                f"Codex app-server rejected {method} (code {code}).",
                retryable=method not in ("thread/start", "turn/start"),
            );
        }
        return message.get("result");
    }
}

impl _AppServer.dispatch(message: builtins.dict) -> any {
    method: any = message.get("method");
    if "id" in message {
        await `self._send({
            "id": message["id"],
            "error": {"code": -32601, "message": "Sellbird does not permit tools."},
        });
        raise CodexError(
            f"Codex attempted a forbidden action ({method}); the call was aborted and nothing ran.",
            kind="isolation",
        );
    }
    if `self.on_message is not None {
        `self.on_message(method, message.get("params"));
    }
}

impl CodexClient.run(prompt: builtins.str, timeout: builtins.float, skip_if=None) -> CodexResult {
    return await `self._bounded(
        timeout, lambda (deadline) -> any { `self._run(prompt, deadline) }, skip_if
    );
}

impl CodexClient.read_rate_limits(timeout: builtins.float = 30.0) -> builtins.dict | None {
    return await `self._bounded(timeout, `self._read_rate_limits);
}

impl CodexClient._bounded(timeout: builtins.float, work, skip_if=None) -> any {
    require_supported_platform();
    deadline: any = time.monotonic() + timeout;
    try {
        async with asyncio.timeout(timeout) {
            async with `self._serialize() {
                reason: any = skip_if() if skip_if else "";
                if reason {
                    raise CodexError(reason, kind="paused");
                }
                return await work(deadline);
            }
        }
    } except CodexError {
        raise;
    } except TimeoutError {
        raise _timeout_error() from None;
    } except (OSError, ValueError, RuntimeError, EOFError) as e {
        raise CodexError(
            f"Codex runtime failed ({`type(e).__name__}).", kind="runtime", retryable=True
        ) from None;
    }
}

impl CodexClient.preflight(timeout: builtins.float = 120.0) -> None {
    return await `self._bounded(timeout, `self._preflight);
}

impl CodexClient._preflight(deadline: builtins.float) {
    server: any = _AppServer(`self._resolve_codex());
    try {
        await `self._attested_thread(server, deadline);
    } finally {
        await server.close();
    }
}

impl CodexClient._open_session(
    server: any, deadline: builtins.float, toolless_model: builtins.bool
) -> builtins.tuple[builtins.str, builtins.list[builtins.str]] {
    _: any;
    native: any;
    (_, native) = _load_native_auth(`self.native_home) as any;
    snapshot: any = build_access_snapshot(native);
    server.prepare();
    await server.read_version(deadline);
    await server.launch(deadline);
    attest_effective_config(await server.read_config(deadline));
    await server.stop();
    server.install_auth(snapshot);
    model: any = `self.model;
    if toolless_model or not model {
        catalog: any = text_only_catalog(await server.read_catalog(deadline));
        model = model or `self._default_model(catalog);
        if toolless_model {
            require_toolless_model(catalog, model);
            server.install_model_catalog(catalog);
        }
    }
    await server.launch(deadline);
    mcp_names: any = attest_effective_config(
        await server.read_config(deadline), server.model_catalog_path
    );
    await `self._require_chatgpt(server, deadline);
    return (model, mcp_names);
}

impl CodexClient._attested_thread(
    server: any, deadline: builtins.float
) -> builtins.tuple[builtins.str, builtins.str] {
    model: any;
    mcp_names: any;
    (model, mcp_names) = await `self._open_session(server, deadline, toolless_model=True) as any;
    params: any = build_thread_params(server.workspace, model, mcp_names);
    params["config"]["model_catalog_json"] = server.model_catalog_path;
    thread_id: any;
    (thread_id, model) = attest_thread(
        await server.request("thread/start", params, deadline), model
    ) as any;
    attest_mcp_status(await `self._mcp_status_pages(server, thread_id, deadline), mcp_names);
    attest_hooks(await server.request("hooks/list", {"cwds": [server.workspace]}, deadline));
    return (thread_id, model);
}

impl CodexClient._run(prompt: builtins.str, deadline: builtins.float) -> CodexResult {
    turn: any;
    server: any = _AppServer(`self._resolve_codex());
    started: any = time.monotonic();
    try {
        thread_id: any;
        model: any;
        (thread_id, model) = await `self._attested_thread(server, deadline) as any;
        turn = _Turn(thread_id=thread_id, model=model);
        server.on_message = lambda (method, params) -> any {
            `self._on_turn_message(turn, method, params)
        };
        turn_params: any = {
            "threadId": thread_id,
            "input": [{"type": "text", "text": prompt, "text_elements": []}],
        };
        if `self.reasoning_effort {
            turn_params["effort"] = `self.reasoning_effort;
        }
        started_turn: any = await server.request("turn/start", turn_params, deadline);
        if isinstance(started_turn, `dict) and isinstance(started_turn.get("turn"), `dict) {
            `self._accept_terminal(turn, started_turn["turn"]);
        }
        while not turn.status and not turn.violation {
            await server.dispatch(await server.read_message(deadline));
        }

        if turn.violation {
            raise CodexError(
                f"Codex attempted a forbidden {turn.violation} item; the call was aborted.",
                kind="isolation",
            );
        }
        if turn.rate_limits {
            `self.last_rate_limits = turn.rate_limits;
        }
        if turn.status != "completed" {
            if turn.status == "failed" {
                raise _classify_turn_error(turn.error);
            }
            raise CodexError(f"Codex turn ended as '{turn.status}'.", retryable=True);
        }
        if turn.answer is None {
            raise CodexError("Codex finished without a final answer.", retryable=True);
        }
        return CodexResult(
            text=turn.answer,
            model=model,
            thread_id=thread_id,
            duration_ms=turn.duration_ms or `int((time.monotonic() - started) * 1000),
            usage=normalize_usage(turn.token_usage),
            rate_limits=turn.rate_limits,
        );
    } finally {
        await server.close();
    }
}

impl CodexClient._read_rate_limits(deadline: builtins.float) -> builtins.dict | None {
    server: any = _AppServer(`self._resolve_codex());
    try {
        model: any;
        _: any;
        (model, _) = await `self._open_session(server, deadline, toolless_model=False) as any;
        result: any = await server.request(
            "account/rateLimits/read", {"excludeResetCreditDetails": True}, deadline
        );
    } finally {
        await server.close();
    }
    parsed: any = select_rate_limits(result, model);
    if parsed {
        `self.last_rate_limits = parsed;
    }
    return parsed;
}

impl CodexClient._require_chatgpt(server: any, deadline: builtins.float) -> any {
    account: any = await server.request("account/read", {"refreshToken": False}, deadline);
    acct: any = account.get("account") if isinstance(account, `dict) else None;
    acct_type: any = acct.get("type") if isinstance(acct, `dict) else None;
    if acct_type == "chatgpt" {
        return;
    }
    if acct_type is None {
        raise CodexError(
            "Codex is not logged in. Run 'codex login' and sign in with ChatGPT.", kind="auth"
        );
    }
    raise _setup_error(
        "Codex is logged in with an API key or another provider. Sellbird only uses a ChatGPT subscription; run 'codex login' with ChatGPT.",
    );
}

impl CodexClient._mcp_status_pages(
    server: any, thread_id: builtins.str, deadline: builtins.float
) -> any {
    pages: any;
    cursor: any;
    (pages, cursor) = ([], None);
    for _ in range(MAX_STATUS_PAGES) {
        params: any = {"threadId": thread_id, "detail": "toolsAndAuthOnly"};
        if cursor {
            params["cursor"] = cursor;
        }
        page: any = await server.request("mcpServerStatus/list", params, deadline);
        pages.append(page);
        cursor = page.get("nextCursor") if isinstance(page, `dict) else None;
        if not cursor {
            return pages;
        }
    }
    raise _isolation_error("MCP status did not finish paging");
}

impl CodexQuotaClient.get_utilization -> builtins.dict | None {
    if `self._lock is None {
        `self._lock = asyncio.Lock();
    }
    async with `self._lock {
        now: any = time.monotonic();
        if `self._cache_at and now - `self._cache_at < `self._cache_ttl {
            return `self._cache;
        }
        try {
            result: any = await `self.client.read_rate_limits();
        } except CodexError as e {
            logger.debug(f"Codex quota unavailable: {e}");
            result = None;
        }
        `self._cache = result;
        `self._cache_at = now;
        `self._cache_ttl = CACHE_TTL_OK if result else CACHE_TTL_FAIL;
        return result;
    }
}
