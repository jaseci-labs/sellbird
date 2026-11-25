impl _m(name: str) -> any {
    return importlib.import_module(f"sellbird.{name}");
}

impl _state -> any {
    state = _m("state").StateManager();
    await state.init_db();
    return state;
}

impl _wrapped(text: str) {
    print(textwrap.fill(text, width=72, initial_indent=_INDENT, subsequent_indent=_INDENT));
}

impl _split(text: str, sep: str = ",") -> list[str] {
    return [part.strip() for part in text.split(sep) if part.strip()];
}

impl _check_python_version {
    if sys.version_info >= MIN_PYTHON {
        return;
    }
    have = f"{sys.version_info.major}.{sys.version_info.minor}";
    print(
        f"\n  Sellbird needs Python {MIN_PYTHON[0]}.{MIN_PYTHON[1]} or newer. This is Python {have}.",
    );
    print(f"  ({sys.executable})\n");
    print(_OLD_PYTHON);
    sys.exit(1);
}

impl cmd_install(args: any) {
    _check_python_version();
    print("\n  Installing Sellbird dependencies...\n");
    paths = _m("paths");
    package_root = paths.PACKAGE_ROOT;
    checkout = paths.is_checkout(package_root);
    if checkout {
        print("  [1/2] Installing Python packages...");
        pip_args = ["-r", "requirements.txt"]
            if (package_root / "requirements.txt").exists()
            else ["-e", "."];
        if subprocess.run(
            [sys.executable, "-m", "pip", "install", *pip_args], cwd=str(package_root)
        ).returncode
            != 0
        {
            print("\n  Failed to install Python packages.");
            print(
                "  Tip: make sure you're inside a virtualenv (python3 -m venv .venv && source .venv/bin/activate).",
            );
            sys.exit(1);
        }
        print("  ✓ Python packages installed.\n");
    } else {
        print("  [1/2] Python packages: already part of this install.");
    }
    print("  [2/2] Installing Playwright browsers...");
    try {
        playwright_ok = bool(
            subprocess.run(
                [sys.executable, "-m", "playwright", "install", "chromium"], timeout=600
            ).returncode
                == 0,
        );
    } except (subprocess.TimeoutExpired, OSError) {
        playwright_ok = False;
    }
    if playwright_ok {
        print("  ✓ Playwright browsers installed.\n");
    } else {
        print("\n  Playwright browser install failed (optional — needed for LinkedIn).");
    }
    if checkout {
        _ensure_importable(str(package_root));
    }
    print("  Sellbird is installed. Run 'sellbird setup' next.\n");
}

impl _imports_outside -> bool {
    return subprocess.run(
        [sys.executable, "-c", "import sellbird"], cwd="/", capture_output=True
    ).returncode
        == 0;
}

impl _ensure_importable(project_root: str) {
    if _imports_outside() {
        return;
    }
    try {
        link = Path(importlib.import_module("site").getsitepackages()[0]) / "sellbird";
        target = Path(project_root) / "sellbird";
        if not link.exists() and target.is_dir() {
            link.symlink_to(target);
            if _imports_outside() {
                print(
                    "  ✓ Fixed package visibility (editable .pth was being ignored; linked the package directly).\n",
                );
                return;
            }
        }
    } except OSError as e {
        print(f"  Could not apply import fix: {e}");
    }
    print(_NOT_IMPORTABLE);
}

impl cmd_setup(args: any) {
    asyncio.run(_m("setup").run_setup());
}

impl cmd_run(args: any) {
    _m("main").main();
}

impl cmd_train(args: any) {
    Trainer = _m("trainer").Trainer;
    url = args.url.strip();
    if not url.startswith(("http://", "https://")) {
        url = f"https://{url}";
        print(f"  No scheme given — using {url}");
    }
    if args.max_pages < 1 {
        print("  max_pages must be at least 1.");
        sys.exit(2);
    }
    ValidationError = importlib.import_module("pydantic").ValidationError;
    config = importlib.import_module("sellbird.config");
    try {
        brain_config = config.load_brain_config();
        overrides: dict[str, any] = {
            k: v
            for (k, v) in (
                ("provider", args.provider),
                ("model", args.model),
                ("reasoning_effort", args.reasoning_effort),
            )
            if v is not None
        };
        if overrides
            and "provider" in overrides
            and overrides["provider"] != brain_config.provider
        {
            brain_config = config.BrainConfig(**overrides);
        } elif overrides {
            fields: dict[str, any] = brain_config.model_dump();
            brain_config = config.BrainConfig(**{**fields, **overrides});
        }
    } except (config.ConfigError, ValidationError) as e {
        print(f"  {e}");
        sys.exit(2);
    }
    asyncio.run(Trainer(brain_config=brain_config).train(url, max_pages=args.max_pages));
}

impl cmd_mcp(args: any) {
    if getattr(args, "mcp_action", None) {
        sys.exit(
            _m("mcp_install").run_command(
                args.mcp_action, args.client, print_only=args.print_config, yes=args.yes
            ),
        );
    }
    if getattr(args, "print_config", False) or getattr(args, "yes", False) {
        print(
            "  --print and --yes go with install or uninstall, e.g. sellbird mcp install --print",
            file=sys.stderr,
        );
        sys.exit(2);
    }
    _m("mcp_server").run_stdio();
}

impl cmd_dashboard(args: any) {
    dashboard = importlib.import_module("sellbird.dashboard");
    TokenError = importlib.import_module("sellbird.dashboard_auth").TokenError;
    if args.port < 1 or args.port > 65535 {
        print(f"  Invalid port: {args.port}. Must be 1-65535.");
        sys.exit(2);
    }
    try {
        if getattr(args, "url", False) {
            print(dashboard.dashboard_url(host=args.host, port=args.port));
            return;
        }
        dashboard.start_dashboard(host=args.host, port=args.port);
    } except (dashboard.DashboardSetupError, TokenError) as e {
        print(f"\n  Dashboard not started: {e}\n");
        sys.exit(2);
    }
}

impl _status(args: any) -> bool {
    state = await _state();
    summary = await state.get_state_summary();
    prospects = summary.get("prospects") or {};
    print("\n  Sellbird Pipeline Status\n  " + "=" * 40);
    print(f"  Prospects:            {summary['prospects']}");
    print(
        f"  Ready to write for:   {summary.get('writable_prospects', 0)} (new, with a verified or catch-all email)",
    );
    if prospects.get("write_failed", 0) {
        print(
            f"  Couldn't write for:   {prospects.get('write_failed', 0)} (the model's drafts kept coming back unusable; `sellbird retry-writes` tries again)",
        );
    }
    if prospects.get("no_tip", 0) {
        print(
            f"  Nothing to write about: {prospects.get('no_tip', 0)} (writer.require_tip skipped them; `sellbird retry-writes --no-tip` tries again once more is known)",
        );
    }
    print(f"  Draft campaigns:      {summary['draft_campaigns']}");
    print(f"  Active campaigns:     {summary['active_campaigns']}");
    print(f"  Open conversations:   {summary['open_conversations']}");
    by_provider = summary.get("usage_today_by_provider", {});
    print(f"  Claude calls today:   {by_provider.get('claude', summary['usage_today'])}");
    print(f"  Codex calls today:    {by_provider.get('codex', 0)}");
    config = _m("config");
    loaded: any = None;
    try {
        loaded = config.load_config();
        notice = config.sending_notice(loaded);
        address_notice = config.compliance_notice(loaded);
    } except Exception {
        notice = address_notice = "";
    }
    backlog = _m("main").unusable_backlog_notice(summary);
    if backlog {
        print("  Prospecting:          PAUSED");
        _wrapped(backlog);
    }
    if notice {
        print("  Sending:              HELD");
        _wrapped(notice);
    }
    rules_problem = await state.get_setting(_m("agents.writer").EMAIL_RULES_PROBLEM_KEY);
    if rules_problem {
        print(f"  Writing:              STOPPED (writer.email_rules: {rules_problem})");
    }
    hold = await state.current_sends_held();
    if hold {
        waiting = len(await state.get_outbox(status="approved", limit=500));
        (title, detail) = _m("sending_mode").held_message(hold, waiting=waiting);
        print(f"  Sending:              NOT SENDING ({title.split(': ', 1)[-1]})");
        _wrapped(detail);
    }
    precleared = _m("integrations.precleared");
    precleared_hold = await precleared.current_hold(state, loaded);
    if precleared_hold {
        message = precleared.hold_message(precleared_hold);
        print(
            f"  Precleared:           HOLDING COLD EMAIL since {precleared_hold.get('since', '?')}"
        );
        _wrapped(f"{message['title']}. {message['detail']}");
    }
    if address_notice {
        print("  Postal address:       MISSING");
        _wrapped(address_notice);
    }
    brain = _m("brain");
    config_error: any = None;
    try {
        brain_config = config.load_brain_config();
    } except config.ConfigError as e {
        (brain_config, config_error) = (None, e);
    }
    brain_status = brain.active_brain_status(
        await state.get_setting(brain.BRAIN_STATUS_KEY),
        brain_config.provider if brain_config else "",
    );
    healthy = True;
    if getattr(args, "check", False) {
        if brain_config is None {
            print(f"  Brain:                config error: {config_error}");
            healthy = False;
        } else {
            thinker = brain.Brain(state, brain_config);
            problem = await thinker.preflight();
            label = thinker.provider_label + (f" ({thinker.model})" if thinker.model else "");
            if problem {
                healthy = False;
                print(f"  Brain:                {label} NOT READY\n{_INDENT}{problem}");
            } elif thinker.provider == "codex" {
                print(
                    f"  Brain:                {label} ready (CLI, isolation, login, model and account checked; no prompt sent)",
                );
            } else {
                print(
                    f"  Brain:                {label} CLI isolation flags present (login not checked: Claude is checked by its first call)",
                );
            }
        }
    } elif brain_status.get("status") == "paused" {
        label = _LABELS.get(brain_status.get("provider"), "Brain");
        print(f"  Brain:                {label} PAUSED since {brain_status.get('since', '?')}");
        print(f"{_INDENT}{brain_status.get('reason', '')}");
    }
    print();
    return healthy;
}

impl cmd_status(args: any) {
    if not asyncio.run(_status(args)) {
        raise SystemExit(1);
    }
}

impl _usage_rows(title: str, days: int, rows: list[any], key: str, width: int) {
    print(f"\n  By {title} (last {days} days):");
    for row in rows {
        print(
            f"    {row[key]:<{width}} {row['calls']:>5} calls  {row['output_tokens']:>10,} out tokens",
        );
    }
}

impl _usage(args: any) {
    state = await _state();
    config = _m("config");
    brain_config: any = None;
    try {
        brain_config = config.load_brain_config();
    } except config.ConfigError as e {
        print(f"  {e}");
    }
    windows: any = None;
    provider = brain_config.provider if brain_config else None;
    try {
        if provider == "codex" {
            codex = _m("codex");
            windows = await codex.CodexQuotaClient(
                codex.CodexClient(model=brain_config.model)
            ).get_utilization();
        } elif provider == "claude" {
            windows = await _m("integrations.quota").QuotaClient().get_utilization();
        }
    } except Exception {}
    print(f"\n  {_LABELS.get(provider, 'Brain')} Usage\n  " + "=" * 52);
    if windows {
        labels = {
            "five_hour": "5-hour window",
            "seven_day": "Weekly",
            "limit_reached": "Usage limit",
        };
        for (key, w) in windows.items() {
            resets = f"  (resets {w['resets_at']})" if w.get("resets_at") else "";
            print(f"  {labels.get(key, key):<16} {w['utilization']:5.1f}% used{resets}");
        }
    } elif provider == "codex" {
        print(
            "  Quota gauge unavailable (check 'codex login', the Codex CLI version, and network)."
        );
    } elif provider == "claude" {
        print("  Quota gauge unavailable (run 'claude login' or check network).");
    }
    totals = await state.usage_totals();
    print(f"\n  {'Period':<10} {'Calls':>7} {'Input':>12} {'Output':>10} {'Cache read':>12}");
    for (label, key) in (("Today", "today"), ("7 days", "week"), ("30 days", "month")) {
        t = totals.get(key) or {};
        print(
            f"  {label:<10} {t.get('calls', 0):>7} {t.get('input_tokens', 0):>12,} {t.get('output_tokens', 0):>10,} {t.get('cache_read_tokens', 0):>12,}",
        );
    }
    by_provider = await state.usage_by_provider(days=args.days);
    if len(by_provider) > 1 or (by_provider and by_provider[0]["provider"] != "claude") {
        _usage_rows("provider", args.days, by_provider, "provider", 14);
    }
    by_agent = await state.usage_by_agent(days=args.days);
    if by_agent {
        _usage_rows("agent", args.days, by_agent, "agent", 14);
    }
    by_task = await state.usage_by_task(days=args.days);
    if by_task {
        _usage_rows("task", args.days, by_task[:10], "task", 22);
    }
    print(
        "\n  Subscription plans aren't billed per token — these are usage\n  counts, not costs.\n"
    );
}

impl cmd_usage(args: any) {
    asyncio.run(_usage(args));
}

impl cmd_companies(args: any) {
    register = _m("register");
    db_path = _m("state").DB_PATH;
    if not db_path.exists() {
        print("\n  No database yet: run 'sellbird discover' or 'sellbird run' first.\n");
        return;
    }
    rows = asyncio.run(
        register.build_register(register.sqlite_query(db_path), _m("config").load_config())
    );
    out = Path(args.out)
        if args.out
        else _m("paths").PROJECT_ROOT
            / "data"
            / "exports"
            / f"company-register-{date.today():%Y-%m-%d}.csv";
    out.parent.mkdir(parents=True, exist_ok=True);
    out.write_text(register.to_csv(rows), encoding="utf-8-sig");
    print(f"\n  Company register: {len(rows)} companies → {out}");
    for (status, n) in Counter(r["status"] for r in rows).most_common() {
        print(f"    {status:<18} {n}");
    }
    print();
}

impl _export(args: any) {
    state = await _state();
    email_statuses = _split(args.email_status) if args.email_status else None;
    (count, _) = await _m("export").export_prospects_csv(
        state,
        out_path=args.out,
        email_statuses=email_statuses,
        min_score=args.min_score,
        statuses=_split(args.status) if args.status else None,
        include_all=args.all,
    );
    score = f", score >= {args.min_score}" if args.min_score else "";
    scope = "all prospects"
        if args.all
        else f"email status {email_statuses or ['verified', 'risky']}{score}";
    print(f"\n  Exported {count} prospect(s) to {args.out}  ({scope})");
    if count == 0 and not args.all {
        print(
            "  Tip: no deliverable emails yet? Add a REOON_API_KEY to .env so\n  Sellbird can verify addresses, or use --all for the raw list.\n",
        );
    } else {
        print("  The CSV imports directly into Instantly, Smartlead, or any sequencer.\n");
    }
}

impl cmd_export(args: any) {
    asyncio.run(_export(args));
}

impl _test_provider(provider: any) {
    (ok, detail) = await provider.test_connection();
    print(f"\n  {'✓' if ok else '✗'} {detail}\n");
    sys.exit(0 if ok else 1);
}

impl _mail_command(action: str, module: str, provider: str, client_id: str, secret: str) {
    env = _m("config").load_env();
    integration = _m(f"integrations.{module}");
    if action == "auth" {
        sys.exit(
            0 if integration.run_auth_flow(getattr(env, client_id), getattr(env, secret)) else 1
        );
    }
    if action == "test" {
        asyncio.run(
            _test_provider(getattr(integration, provider)(_m("config").load_config(), env))
        );
    }
}

impl cmd_gmail(args: any) {
    _mail_command(
        args.gmail_action, "gmail", "GmailProvider", "gmail_client_id", "gmail_client_secret"
    );
}

impl cmd_microsoft(args: any) {
    _mail_command(
        args.microsoft_action, "microsoft", "MicrosoftProvider", "m365_client_id", "m365_tenant_id"
    );
}

impl _outbox(args: any) {
    state = await _state();
    if args.approve_all {
        print(f"\n  Approved {await state.approve_outbox()} email(s). They'll send on schedule.");
        held = await state.count_held_for_review();
        if held {
            print(
                f"  {held} email(s) Sellbird held for review were left out: read each one,\n  then approve it with --approve <id>.",
            );
        }
        print();
        return;
    }
    if args.approve {
        print(
            f"\n  {'Approved.' if await state.approve_outbox(args.approve) else 'No pending item with that id.'}\n",
        );
        return;
    }
    if args.reject {
        n = await state.reject_outbox_item(args.reject);
        print(
            f"\n  {'Rejected.' if n else 'Nothing waiting to send with that id (already sending or sent?).'}\n",
        );
        return;
    }
    paused = await state.get_setting("sending_paused");
    if paused {
        print(f"\n  ⚠ SENDING PAUSED: {paused}\n  Resume with: sellbird sending resume");
    }
    pending = await state.get_outbox(status="pending_review", limit=50);
    approved = await state.get_outbox(status="approved", limit=10);
    print(
        f"\n  Outbox — {len(pending)} awaiting approval, {len(approved)}+ approved/scheduled\n  "
            + "=" * 60,
    );
    for item in pending {
        print(
            f"\n  [{item['id']}] step {item['step']} ({item['kind']}) → {item['to_email']}  (send {item['send_at'][:16]})",
        );
        print(f"  Subject: {item['subject']}");
        body = item["body"];
        for line in (body[:200] + "..." if len(body) > 200 else body).splitlines() {
            print(f"    {line}");
        }
    }
    if pending {
        print(
            "\n  Approve: sellbird outbox --approve <id>   |   all: sellbird outbox --approve-all\n  Reject:  sellbird outbox --reject <id>\n",
        );
    } else {
        print("  Nothing awaiting review.\n");
    }
}

impl cmd_outbox(args: any) {
    asyncio.run(_outbox(args));
}

impl _profile(args: any) {
    state = await _state();
    pending = await state.count_companies_needing_profile(args.stale_days);
    if not pending {
        print("\n  Nothing to profile. Every company with a website has been read recently.\n");
        return;
    }
    print(f"\n  {pending} companies need profiling. Reading up to {args.limit}...\n");
    config: any = None;
    try {
        config = _m("config").load_config();
    } except Exception {}
    (companies, observations, _) = await _m("pipeline").run_profile_stage(
        state, limit=args.limit, stale_days=args.stale_days, config=config
    );
    print(f"  Read {companies} sites → {observations} observations (free)");
    print("\n  See what turned up: sellbird dashboard → Signals\n");
}

impl cmd_profile(args: any) {
    asyncio.run(_profile(args));
}

impl _print_providers(menu: list[any]) {
    print("\n  Discovery providers\n  " + "=" * 68);
    for m in menu {
        print(f"\n  {m['label']}  [{m['key']}]  ({'ready' if m['configured'] else 'needs setup'})");
        print(f"    {m['blurb']}\n    Cost: {m['cost_note']}\n    Free: {m['free_tier']}");
        if m["env_keys"] {
            print(f"    Needs: {', '.join(m['env_keys'])} in .env  —  {m['signup_url']}");
        }
        if m["caveat"] {
            print(f"    Note: {m['caveat']}");
        }
    }
    print("\n  Run one with: sellbird discover --provider <key> --estimate\n");
}

impl _discover(args: any) {
    discover = _m("collectors.discover");
    config_mod = _m("config");
    if args.providers {
        _print_providers(discover.provider_menu(config_mod.load_env().model_dump()));
        return;
    }
    if args.provider not in discover.PROVIDERS {
        print(f"\n  Unknown provider {args.provider!r}. See: sellbird discover --providers\n");
        return;
    }
    provider = discover.PROVIDERS[args.provider];
    missing = provider.missing_keys(config_mod.load_env().model_dump());
    if missing and not args.estimate {
        bang = "!" * 68;
        print(
            f"\n  {bang}\n  ERROR: provider skipped: missing key - {provider.label} is not configured, 0 queries can run.",
        );
        print(f"  Missing or empty: {', '.join(k.upper() for k in missing)}");
        print("  Put a real value in .env (template placeholders don't count), then retry.");
        print(f"  All providers and their keys: sellbird discover --providers\n  {bang}\n");
        raise SystemExit(1);
    }
    config = config_mod.load_config();
    state = await _state();
    preset = getattr(args, "preset", "") or "";
    problem = discover.preset_problem(preset, args.provider, config=config);
    if problem {
        print(f"\n  {problem}\n");
        sys.exit(2);
    }
    queries = discover.build_queries(
        config,
        cities=_split(args.city, ";") or None,
        depth=args.depth,
        limit=args.limit,
        preset=preset,
    );
    estimate = await discover.run_discovery(
        state, config, args.provider, queries, max_spend=args.max_spend, dry_run=True
    );
    print(f"\n  {len(queries)} queries via {provider.label}");
    for q in queries[:8] {
        print(
            f"    - {q.keyword()}"
                + (
                    ""
                        if q.coordinate
                        else "   (no coordinates — add icp.geo_coordinates for radius search)"
                ),
        );
    }
    if len(queries) > 8 {
        print(f"    ... and {len(queries) - 8} more");
    }
    print(f"\n  Estimated cost: ${estimate.estimated_cost:.4f}   (cap: ${args.max_spend:.2f})");
    if args.estimate {
        print("\n  Estimate only. Re-run without --estimate to collect.\n");
        return;
    }
    print("\n  Running...\n");
    result = await _m("pipeline").run_prospecting(
        state, config, args.provider, queries, max_spend=args.max_spend, profile=not args.no_profile
    );
    r = result.discover or {};
    print(
        f"  DISCOVER — {r.get('found', 0)} results across {r.get('queries_ran', 0)} of {r.get('queries', 0)} queries",
    );
    print(
        f"    {r.get('new_companies', 0)} new companies, {r.get('known_companies', 0)} already known",
    );
    print(f"    {r.get('junk', 0)} filtered out as directories/aggregators");
    if r.get("excluded") {
        print(f"    {r['excluded']} skipped — on your do-not-contact list");
    }
    print(
        f"    {r.get('observations', 0)} observations recorded\n    actual cost: ${r.get('actual_cost', 0):.4f}",
    );
    if r.get("stopped") {
        print(f"    stopped early: {r['stopped']}");
    }
    if args.no_profile {
        print("\n  PROFILE — skipped (--no-profile)");
    } else {
        print(
            f"\n  PROFILE — {result.profiled_companies} sites read, {result.profile_observations} observations  (free)",
        );
    }
    for err in result.errors[:5] {
        print(f"    ! {err}");
    }
    if r.get("queries_succeeded", 0) == 0 {
        rule = "=" * 68;
        print(
            f"\n  {rule}\n  DISCOVERY COMPLETED NO QUERIES ({r.get('stopped') or 'no queries succeeded'}) — exiting non-zero",
        );
        for err in (r.get("errors") or [])[:3] {
            print(f"    - {err}");
        }
        print(f"  {rule}\n");
        raise SystemExit(1);
    }
    print("\n  Next: sellbird dashboard → Signals → cohort builder\n");
}

impl cmd_discover(args: any) {
    asyncio.run(_discover(args));
}

impl _is_free(signal: any) -> bool {
    return (signal["cost_note"] or "").lower().startswith(("free", "included"));
}

impl _signals(args: any) {
    state = await _state();
    await _m("signals").seed_signal_catalog(state);
    codes = [code.upper() for code in _split(args.confirm or args.reject or "")];
    if codes {
        status = "confirmed" if args.confirm else "rejected";
        if codes in (["ALL"], ["FREE"]) {
            everything = await state.get_signal_codes();
            codes = [c["code"] for c in everything if codes == ["ALL"] or _is_free(c)];
        }
        changed = 0;
        for code in codes {
            if await state.set_signal_status(code, status) {
                changed += 1;
            }
        }
        print(f"\n  {changed} signal(s) {status}.\n");
        return;
    }
    rows = await state.get_signal_codes();
    counts = {c["signal_code"]: c for c in await state.signal_counts()};
    by_status = {"confirmed": 0, "proposed": 0, "rejected": 0};
    for r in rows {
        by_status[r["status"]] = by_status.get(r["status"], 0) + 1;
    }
    print(
        f"\n  Signals — {by_status['confirmed']} confirmed, {by_status['proposed']} awaiting you, {by_status['rejected']} off\n  "
            + "=" * 66,
    );
    mark = {"confirmed": "[on] ", "proposed": "[ ? ]", "rejected": "[off]"};
    current: any = None;
    for r in rows {
        if r["category"] != current {
            current = r["category"];
            print(f"\n  {current.upper()}");
        }
        seen = counts.get(r["code"], {}).get("companies", 0);
        seen_txt = f"  ({seen} companies)" if seen else "";
        print(
            f"    {mark.get(r['status'], '     ')} {r['code']:<22} {r['label']}{seen_txt}\n          {r['cost_note']}",
        );
    }
    if by_status["proposed"] {
        print(
            "\n  Confirm with: sellbird signals --confirm CODE[,CODE...]\n  Everything free: sellbird signals --confirm free\n  Details and descriptions: sellbird dashboard → Signals\n",
        );
    } else {
        print("");
    }
}

impl cmd_signals(args: any) {
    asyncio.run(_signals(args));
}

impl _retry_writes(args: any) {
    MAX_WRITE_ATTEMPTS = _m("agents.writer").MAX_WRITE_ATTEMPTS;
    state = await _state();
    if getattr(args, "no_tip", False) {
        count = await state.retry_no_tip();
        if count {
            print(
                f"\n  {count} prospect(s) are back in line. With writer.require_tip on, anyone still without something concrete is skipped again.\n",
            );
        } else {
            print("\n  No prospects were skipped for having nothing to write about.\n");
        }
        return;
    }
    count = await state.retry_write_failed();
    if count {
        print(
            f"\n  {count} prospect(s) are back in line. The Writer will try each up to {MAX_WRITE_ATTEMPTS} more times.\n",
        );
    } else {
        print("\n  No prospects are waiting on a retry.\n");
    }
}

impl cmd_retry_writes(args: any) {
    asyncio.run(_retry_writes(args));
}

impl _load_config_or_exit -> any {
    importlib.import_module("dotenv").load_dotenv(_m("paths").PROJECT_ROOT / ".env");
    config = _m("config");
    try {
        return config.load_config();
    } except config.ConfigError as e {
        print(f"\n  {e}\n");
        raise SystemExit(1);
    }
}

impl _send_history -> tuple[int, int] {
    state = await _state();
    return (
        await state.count_outbox_sent(),
        int(await state.get_setting(_m("agents.handler").BOUNCE_COUNT_KEY) or 0),
    );
}

impl cmd_warmup(args: any) {
    os = importlib.import_module("os");
    d = _m("deliverability");
    config = _load_config_or_exit();
    email = config.channels.email;
    smtp = email.provider == "smtp";
    smtp_user = os.getenv("SMTP_USERNAME", "").strip() if smtp else "";
    sender = smtp_user if "@" in smtp_user else config.persona.email;
    domain = (args.domain or sender.rpartition("@")[2]).strip().lower().rstrip(".");
    if not d.DOMAIN_RE.match(domain) {
        print("\n  No valid sending domain found. Pass one: sellbird warmup yourdomain.com\n");
        raise SystemExit(1);
    }
    smtp_host = os.getenv("SMTP_HOST", "").strip() if smtp else "";
    print(f"\n  Deliverability check - {domain}\n  " + "=" * 56);
    sections = [
        (
            "Authentication",
            [
                d.check_mx(domain),
                d.check_spf(domain),
                d.check_dkim(domain, email.warmup.dkim_selector),
                d.check_dmarc(domain),
            ],
        ),
        (
            "Reputation",
            [d.check_domain_age(domain), *d.check_domain_blocklists(domain)]
                + (d.check_ip_blocklists(smtp_host) if smtp_host else []),
        ),
        (
            "Warmup & sending",
            [
                d.check_warmup(email.warmup, email.max_daily_sends, provider=email.provider),
                _warmup_service_check(sender, email.warmup),
                d.check_send_history(*asyncio.run(_send_history())),
            ],
        ),
    ];
    icons = {d.OK: "OK  ", d.WARN: "WARN", d.FAIL: "FAIL", d.INFO: "info"};
    (failed, warned, unknown) = (0, 0, 0);
    for (title, checks) in sections {
        print(f"\n  {title}");
        for c in checks {
            failed += int(c.status == d.FAIL);
            warned += int(c.status == d.WARN);
            unknown += int(bool(c.unknown and title == "Authentication"));
            print(f"    [{icons[c.status]}] {c.name:<26} {c.detail}");
        }
    }
    print("\n  " + "=" * 56);
    if failed {
        print(f"  NOT READY - fix the {failed} FAIL item(s) before any cold email.");
    } elif unknown {
        print(f"  NOT CHECKED - {unknown} authentication lookup(s) failed; run again.");
    } elif warned {
        print(f"  READY WITH CAVEATS - {warned} warning(s); keep volume low.");
    } else {
        print("  READY - send within today's cap and watch bounces.");
    }
    print(_DNS_LIMITS);
    if failed or unknown {
        raise SystemExit(1);
    }
}

impl _warmup_service(address: str, warmup: any) -> any {
    ti = _m("integrations.trulyinbox");
    state = await _state();
    (health, error) = await ti.current_health(address);
    other = health is None and not error and await ti.get_choice(state) == "other";
    return _m("deliverability").check_warmup_service(
        health, warmup, error=error, other_service=other
    );
}

impl _warmup_service_check(address: str, warmup: any) -> any {
    return asyncio.run(_warmup_service(address, warmup));
}

impl _trulyinbox_connect(state: any, address: str, warmup: any) -> int {
    ti = _m("integrations.trulyinbox");
    print(f"\n  Connect TrulyInbox. Don't have it yet? {ti.AFFILIATE_URL} {ti.AFFILIATE_TAG}");
    print(_TRULYINBOX_KEY);
    if not address {
        print(f"\n  {ti.NO_ADDRESS}\n");
        return 1;
    }
    key = importlib.import_module("getpass").getpass("  TrulyInbox API key (hidden): ").strip();
    if not key {
        print("\n  No key entered.\n");
        return 1;
    }
    workspace = ti.key_from_env()[1];
    ti.forget_rejected(key);
    try {
        client = ti.TrulyInbox(key, workspace);
        health = await client.mailbox_health(address);
    } except ti.TrulyInboxError as e {
        print(f"\n  {e}\n");
        return 1;
    }
    updates = {"TRULYINBOX_API_KEY": key};
    if not workspace {
        updates["TRULYINBOX_WORKSPACE_ID"] = client.workspace_id;
    }
    try {
        _m("dashboard")._write_env_file(updates);
    } except OSError as e {
        print(f"\n  The key works, but Sellbird couldn't save it to .env: {e}\n");
        return 1;
    }
    await ti.set_choice(state, "connected");
    print(
        "\n  Connected. " + _m("deliverability").check_warmup_service(health, warmup).detail + "\n"
    );
    return 0;
}

impl _trulyinbox(args: any, address: str, warmup: any) -> int {
    ti = _m("integrations.trulyinbox");
    state = await _state();
    if args.trulyinbox_action == "other" {
        await ti.set_choice(state, "other");
        print(
            "\n  Noted: you use another warmup service. Sellbird won't ask about TrulyInbox again.\n",
        );
        return 0;
    }
    if args.trulyinbox_action == "connect" {
        return await _trulyinbox_connect(state, address, warmup);
    }
    choice = await ti.get_choice(state);
    (health, error) = await ti.current_health(address);
    print(f"\n  TrulyInbox: {ti.describe_status(health, error, choice)}");
    check = _m("deliverability").check_warmup_service(
        health, warmup, error=error, other_service=choice == "other"
    );
    print(f"  {check.detail}\n");
    return 0;
}

impl cmd_trulyinbox(args: any) {
    config = _load_config_or_exit();
    address = _m("integrations.trulyinbox").sending_address(config);
    raise SystemExit(asyncio.run(_trulyinbox(args, address, config.channels.email.warmup)));
}

impl cmd_precleared_key(args: any) {
    os = importlib.import_module("os");
    write_env_file = _m("dashboard")._write_env_file;
    precleared = _m("integrations.precleared");
    importlib.import_module("dotenv").load_dotenv(_m("paths").PROJECT_ROOT / ".env");
    if _m("setup")._read_env_file().get("PRECLEARED_API_KEY", "").strip("'\" ")
        or os.getenv("PRECLEARED_API_KEY", "").strip()
    {
        print(
            "\n  You already have a Precleared key (PRECLEARED_API_KEY), so Sellbird kept it.\n  To get a new one, delete that line from .env and run this again.\n",
        );
        raise SystemExit(0);
    }
    (enabled, country) = (None, "");
    try {
        settings = _m("config").load_config().compliance.precleared;
        enabled = settings.enabled is True;
        country = settings.sender_country if enabled else "";
    } except Exception {}
    email = (args.email or "").strip();
    if not email {
        print(
            "\n  Sellbird can get you a free Precleared key: 100 checks a day for the\n  first 14 days, then 25 a day. Precleared receives your email address\n  to make the key (privacy: https://precleared.dev/privacy).",
        );
        try {
            email = builtins.input("\n  → Email address for the key: ").strip();
        } except (EOFError, KeyboardInterrupt) {
            print();
            raise SystemExit(1);
        }
        if not email {
            print("\n  No email address entered.\n");
            raise SystemExit(1);
        }
    }
    result = precleared.create_free_key(email, country=country);
    if not result.key {
        print(
            f"\n  Couldn't get a key: {result.error}.\n  You can get one at {precleared.GET_KEY_URL} and put it in .env as PRECLEARED_API_KEY.\n",
        );
        raise SystemExit(1);
    }
    try {
        write_env_file({"PRECLEARED_API_KEY": result.key});
    } except OSError as e {
        print(
            f"\n  Precleared made the key, but Sellbird couldn't save it to .env ({e}).\n  Fix that and run this again, or get a key at {precleared.GET_KEY_URL}.\n",
        );
        raise SystemExit(1);
    }
    print(
        "\n  Done: your free Precleared key is saved in .env as PRECLEARED_API_KEY.\n  It gives Sellbird 100 checks a day for 14 days, then 25 a day.",
    );
    if enabled is False {
        print(
            "  The check itself is off: turn it on with `sellbird setup` or set\n  compliance.precleared.enabled: true in your config.",
        );
    }
    print("  If Sellbird is running, restart it so it uses the key.\n");
    raise SystemExit(0);
}

impl _sending(args: any) {
    state = await _state();
    if args.sending_action == "pause" {
        await state.set_setting("sending_paused", "paused manually");
        print("\n  Sending paused. Nothing will leave the outbox.\n");
    } elif args.sending_action == "resume" {
        await state.set_setting("sending_paused", "");
        await state.set_setting("bounce_count", "0");
        print("\n  Sending resumed (bounce counter reset).\n");
    } else {
        paused = await state.get_setting("sending_paused");
        print(f"\n  Sending: {'PAUSED — ' + paused if paused else 'active'}\n");
    }
}

impl cmd_sending(args: any) {
    asyncio.run(_sending(args));
}

impl _carry_over_from_harvey {
    notes = _m("legacy").migrate_files();
    legacy_env = importlib.import_module("sellbird").LEGACY_ENV;
    if legacy_env {
        notes.append(
            "Using your HARVEY_* settings as "
                + ", ".join(legacy_env)
                + ". Rename them when convenient.",
        );
    }
    for note in notes {
        print(f"Sellbird (formerly Harvey): {note}", file=sys.stderr);
    }
}

impl _suppressions(args: any) -> int {
    state = await _state();
    if args.suppression_action == "add" {
        kind = "domain" if "@" not in args.value else "address";
        try {
            added = await state.add_suppression(kind, args.value, "manual", source="cli");
        } except ValueError {
            print(f"\n  That isn't an email address or a domain: {args.value}\n");
            return 1;
        }
        print(
            f"\n  {'Suppressed' if added else 'Already suppressed'}: {state.suppression_key(kind, args.value)} ({kind}).\n",
        );
    } elif args.suppression_action == "remove" {
        if not await state.remove_suppression(args.value) {
            print(
                f"\n  No suppression with id {args.value}. Run `sellbird suppressions` to see ids.\n",
            );
            return 1;
        }
        print("\n  Removed. Sellbird may email them again.\n");
    } else {
        rows = await state.list_suppressions(limit=1000);
        if not rows {
            print("\n  Nobody is suppressed.\n");
        }
        for r in rows {
            print(
                f"  {r['id']}  {r['kind']:<7} {r['value']:<40} {r['reason']:<10} {r['created_at']}"
            );
        }
    }
    return 0;
}

impl cmd_suppressions(args: any) {
    code = asyncio.run(_suppressions(args));
    if code {
        sys.exit(code);
    }
}

impl _command(subparsers: any, name: str, about: str, func: any) -> any {
    sub = subparsers.add_parser(name, help=about);
    sub.set_defaults(func=func);
    return sub;
}

impl _build_parser -> any {
    parser = argparse.ArgumentParser(
        prog="sellbird",
        description="Sellbird — the open-source outreach platform. Make the first move.",
    );
    subparsers = parser.add_subparsers(dest="command");
    _command(subparsers, "install", "Install dependencies", cmd_install);
    _command(subparsers, "setup", "Run the interactive setup wizard", cmd_setup);
    _command(subparsers, "run", "Start Sellbird's heartbeat loop", cmd_run);
    sub = _command(subparsers, "train", "Train Sellbird on a website", cmd_train);
    sub.add_argument("url", help="Website URL to crawl and learn from");
    sub.add_argument(
        "max_pages", nargs="?", type=int, default=100, help="Max pages to crawl (default: 100)"
    );
    sub.add_argument(
        "--provider", choices=["claude", "codex"], default=None, help=_HELP["train.provider"]
    );
    sub.add_argument(
        "--model", default=None, help="Model for this provider (default: provider default)"
    );
    sub.add_argument("--reasoning-effort", default=None, help=_HELP["train.reasoning_effort"]);
    sub = _command(subparsers, "dashboard", "Open the web dashboard", cmd_dashboard);
    sub.add_argument("--host", default="127.0.0.1", help=_HELP["dashboard.host"]);
    sub.add_argument("--port", type=int, default=5555, help="Port (default: 5555)");
    sub.add_argument(
        "--url", action="store_true", help="Print the unlock link (with its token) and exit"
    );
    sub = _command(subparsers, "status", "Show pipeline status", cmd_status);
    sub.add_argument("--check", action="store_true", help=_HELP["status.check"]);
    sub = _command(subparsers, "export", "Export prospects as a sequencer-ready CSV", cmd_export);
    sub.add_argument("--out", default="prospects.csv", help="Output file (default: prospects.csv)");
    sub.add_argument("--email-status", default="", help=_HELP["export.email_status"]);
    sub.add_argument("--min-score", type=int, default=0, help="Minimum ICP score");
    sub.add_argument("--status", default="", help=_HELP["export.status"]);
    sub.add_argument("--all", action="store_true", help=_HELP["export.all"]);
    sub = _command(subparsers, "companies", _HELP["companies"], cmd_companies);
    sub.add_argument("--out", default="", help=_HELP["companies.out"]);
    sub = _command(subparsers, "gmail", "Gmail provider setup", cmd_gmail);
    sub.add_argument(
        "gmail_action",
        choices=["auth", "test"],
        help="auth: one-time OAuth; test: verify connection",
    );
    sub = _command(subparsers, "microsoft", "Microsoft 365 provider setup", cmd_microsoft);
    sub.add_argument(
        "microsoft_action",
        choices=["auth", "test"],
        help="auth: one-time sign-in; test: verify connection",
    );
    sub = _command(subparsers, "outbox", "Review/approve queued emails", cmd_outbox);
    sub.add_argument("--approve", metavar="ID", default="", help="Approve one item");
    sub.add_argument("--approve-all", action="store_true", help="Approve all pending");
    sub.add_argument("--reject", metavar="ID", default="", help="Reject one item");
    sub = _command(subparsers, "discover", "Find businesses matching your ICP", cmd_discover);
    sub.add_argument(
        "--provider", default="osm", help="Discovery provider (default: osm — free, no account)"
    );
    sub.add_argument(
        "--providers",
        action="store_true",
        help="List every provider with cost and setup, then exit",
    );
    sub.add_argument(
        "--estimate",
        action="store_true",
        help="Print projected spend and exit without calling anything",
    );
    sub.add_argument("--city", default="", help=_HELP["discover.city"]);
    sub.add_argument("--depth", type=int, default=30, help=_HELP["discover.depth"]);
    sub.add_argument("--limit", type=int, default=100, help="Max records per query (default: 100)");
    sub.add_argument(
        "--max-spend", type=float, default=1.0, help="Hard cap in dollars (default: 1.00)"
    );
    sub.add_argument(
        "--preset",
        default="",
        choices=["", "yc", "hiring", "accelerator", "funding"],
        help=_HELP["discover.preset"],
    );
    sub.add_argument(
        "--no-profile", action="store_true", help="Don't profile what was found (profiling is free)"
    );
    sub = _command(
        subparsers, "profile", "Read discovered companies' websites (free, no Claude)", cmd_profile
    );
    sub.add_argument("--limit", type=int, default=200, help="Max sites to read (default: 200)");
    sub.add_argument(
        "--stale-days",
        type=int,
        default=90,
        help="Re-read a site after this many days (default: 90)",
    );
    sub = _command(
        subparsers,
        "signals",
        "Review/confirm which signals Sellbird prospects against",
        cmd_signals,
    );
    sub.add_argument(
        "--confirm",
        metavar="CODES",
        default="",
        help="Comma-separated codes to confirm ('all' or 'free' accepted)",
    );
    sub.add_argument(
        "--reject", metavar="CODES", default="", help="Comma-separated codes to turn off"
    );
    sub = _command(
        subparsers,
        "retry-writes",
        "Retry prospects the Writer couldn't write an email for",
        cmd_retry_writes,
    );
    sub.add_argument("--no-tip", action="store_true", help=_HELP["retry-writes.no_tip"]);
    sub = _command(subparsers, "sending", "Kill switch: pause/resume sending", cmd_sending);
    sub.add_argument(
        "sending_action", nargs="?", default="status", choices=["pause", "resume", "status"]
    );
    sub = _command(subparsers, "warmup", _HELP["warmup"], cmd_warmup);
    sub.add_argument(
        "domain",
        nargs="?",
        default="",
        help="Domain to check (default: your sending mailbox's domain)",
    );
    sub = _command(subparsers, "trulyinbox", _HELP["trulyinbox"], cmd_trulyinbox);
    sub.add_argument(
        "trulyinbox_action",
        nargs="?",
        default="status",
        choices=["status", "connect", "other"],
        help=_HELP["trulyinbox.action"],
    );
    sub = _command(subparsers, "precleared-key", _HELP["precleared-key"], cmd_precleared_key);
    sub.add_argument("--email", default="", help="Email address for the key (asked if not given)");
    sub = _command(subparsers, "usage", "Show brain usage and quota (Claude or Codex)", cmd_usage);
    sub.add_argument("--days", type=int, default=30, help="Breakdown window (default: 30)");
    sub = _command(
        subparsers, "mcp", "MCP server for your coding agent (launched by it, over stdio)", cmd_mcp
    );
    sub.add_argument(
        "mcp_action", nargs="?", choices=["install", "uninstall"], help=_HELP["mcp.action"]
    );
    sub.add_argument(
        "client",
        nargs="?",
        choices=["claude", "codex"],
        help="Which agent (default: Claude Code only)",
    );
    sub.add_argument(
        "--print",
        dest="print_config",
        action="store_true",
        help="Print the config to add by hand; change nothing",
    );
    sub.add_argument("--yes", action="store_true", help="Apply without asking");
    _m("inbox_cli").register(subparsers);
    desktop_cli = _m("desktop_cli");
    desktop_cli.register_desktop_commands(subparsers);
    desktop_cli.register(subparsers);
    sub = _command(
        subparsers, "suppressions", "Addresses and domains Sellbird never emails", cmd_suppressions
    );
    sub.add_argument(
        "suppression_action", nargs="?", default="list", choices=["list", "add", "remove"]
    );
    sub.add_argument(
        "value", nargs="?", default="", help="add: an address or domain; remove: its id"
    );
    extensions = _m("extensions");
    for (name, command) in extensions.registry().cli_commands.items() {
        if name in subparsers.choices {
            raise extensions.ExtensionError(
                f"an extension's command {name!r} clashes with a built-in command"
            );
        }
        (help_text, configure) = command;
        sub = subparsers.add_parser(name, help=help_text);
        sub.set_defaults(func=configure(sub));
    }
    return parser;
}

impl main {
    _m("textio").utf8_stdio();
    project_root = str(_m("paths").PROJECT_ROOT);
    parser = _build_parser();
    args = parser.parse_args();
    _carry_over_from_harvey();
    args._project_root = project_root;
    home = _m("home");
    home_root = _m("paths").PROJECT_ROOT;
    try {
        home.seed_home(home_root, home.bundled_defaults());
    } except Exception as e {
        reason = (e.strerror if isinstance(e, OSError) else None) or type(e).__name__;
        print(f"  Could not prepare the home folder {home_root}: {reason}", file=sys.stderr);
    }
    if args.command is None {
        parser.print_help();
        print(_QUICK_START);
        sys.exit(0);
    }
    try {
        args.func(args);
    } except KeyboardInterrupt {
        print("\n  Interrupted. Goodbye.");
        sys.exit(130);
    } except Exception as e {
        if isinstance(e, _m("config").ConfigError) {
            print(f"\n  Configuration problem:\n  {e}\n");
        } else {
            print(f"\n  Error running 'sellbird {args.command}': {e}\n");
        }
        sys.exit(1);
    }
}
