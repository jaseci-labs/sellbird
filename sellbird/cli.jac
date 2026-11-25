import argparse;
import builtins;
import asyncio;
import functools;
import importlib;
import subprocess;
import sys;
import textwrap;
import from collections { Counter, defaultdict }
import from datetime { date }
import from pathlib { Path }

glob MIN_PYTHON = (3, 11),
     _INDENT = " " * 24,
     _LABELS = {"claude": "Claude", "codex": "Codex"},
     _OLD_PYTHON = """  On macOS, `python3` is usually the system 3.9, so a venv built
  with it is 3.9 too. Build the venv from a newer Python instead:

    brew install python@3.13
    rm -rf .venv
    $(brew --prefix)/bin/python3.13 -m venv .venv
    source .venv/bin/activate && pip install -e .
""",
     _NOT_IMPORTABLE = """
  Warning: 'import sellbird' fails outside the project directory.
  Run sellbird commands from the project root, or reinstall with:
    pip install -e . --config-settings editable_mode=compat
""",
     _DNS_LIMITS = """
  What DNS can't tell you (the real reputation signal):
    - Google Postmaster Tools: https://postmaster.google.com - add the domain;
      it shows Gmail's spam rate and domain reputation once you send volume.
    - Inbox placement: send one email to a seed test (mail-tester.com is free)
      and aim for 9/10+. TrulyInbox shows the warmup inbox rate, and with it
      connected (sellbird trulyinbox connect) Sellbird reads it into this report.
      Wait for ~95%+ inbox for a week before relying on cold sends.
""",
     _QUICK_START = """
  Quick start:
    sellbird install   — Install dependencies
    sellbird setup     — Configure Sellbird (first time)
    sellbird run       — Start closing deals
    sellbird dashboard — Open the web dashboard
""",
     _TRULYINBOX_KEY = """  You need Starter or higher. In TrulyInbox, open Settings > API keys and
  create a workspace key with accounts:read, warmup:read, analytics:read
  and workspace:read.
""",
     _SIGNALS_HINT = """
  Confirm with: sellbird signals --confirm CODE[,CODE...]
  Everything free: sellbird signals --confirm free
  Details and descriptions: sellbird dashboard → Signals
""",
     _SAY = {
         "codex_ready": "ready (CLI, isolation, login, model and account checked; no prompt sent)",
         "claude_ready": "CLI isolation flags present (login not checked: Claude is checked by its first call)",
         "writable": "{} (new, with a verified or catch-all email)",
         "write_failed": "{} (the model's drafts kept coming back unusable; `sellbird retry-writes` tries again)",
         "no_tip": "{} (writer.require_tip skipped them; `sellbird retry-writes --no-tip` tries again once more is known)",
         "not_waiting": "Nothing waiting to send with that id (already sending or sent?).",
         "discovered": "  DISCOVER — {found} results across {queries_ran} of {queries} queries\n    {new_companies} new companies, {known_companies} already known\n    {junk} filtered out as directories/aggregators",
         "recorded": "    {observations} observations recorded\n    actual cost: ${actual_cost:.4f}",
         "profiled": "\n  PROFILE — {} sites read, {} observations  (free)",
         "no_coordinates": "   (no coordinates — add icp.geo_coordinates for radius search)",
         "no_queries": "\n  {}\n  DISCOVERY COMPLETED NO QUERIES ({}) — exiting non-zero",
         "retrying": "\n  {} prospect(s) are back in line. The Writer will try each up to {} more times.\n",
         "harvey_env": "Using your HARVEY_* settings as {}. Rename them when convenient.",
         "browsers_ok": "  ✓ Playwright browsers installed.\n",
         "browsers_failed": "\n  Playwright browser install failed (optional — needed for LinkedIn).",
         "virtualenv": "  Tip: make sure you're inside a virtualenv (python3 -m venv .venv && source .venv/bin/activate).",
         "linked": "  ✓ Fixed package visibility (editable .pth was being ignored; linked the package directly).\n",
         "mcp_flags": "  --print and --yes go with install or uninstall, e.g. sellbird mcp install --print",
         "codex_quota": "  Quota gauge unavailable (check 'codex login', the Codex CLI version, and network).",
         "not_billed": "\n  Subscription plans aren't billed per token — these are usage\n  counts, not costs.\n",
         "export_tip": "  Tip: no deliverable emails yet? Add a REOON_API_KEY to .env so\n  Sellbird can verify addresses, or use --all for the raw list.\n",
         "held": "  {held} email(s) Sellbird held for review were left out: read each one,\n  then approve it with --approve <id>.",
         "outbox_hint": "\n  Approve: sellbird outbox --approve <id>   |   all: sellbird outbox --approve-all\n  Reject:  sellbird outbox --reject <id>\n",
         "no_tip_back": "\n  {count} prospect(s) are back in line. With writer.require_tip on, anyone still without something concrete is skipped again.\n",
         "ti_other": "\n  Noted: you use another warmup service. Sellbird won't ask about TrulyInbox again.\n",
         "have_key": "\n  You already have a Precleared key (PRECLEARED_API_KEY), so Sellbird kept it.\n  To get a new one, delete that line from .env and run this again.\n",
         "free_key": "\n  Sellbird can get you a free Precleared key: 100 checks a day for the\n  first 14 days, then 25 a day. Precleared receives your email address\n  to make the key (privacy: https://precleared.dev/privacy).",
         "no_key": "\n  Couldn't get a key: {error}.\n  You can get one at {url} and put it in .env as PRECLEARED_API_KEY.\n",
         "not_saved": "\n  Precleared made the key, but Sellbird couldn't save it to .env ({e}).\n  Fix that and run this again, or get a key at {url}.\n",
         "key_saved": "\n  Done: your free Precleared key is saved in .env as PRECLEARED_API_KEY.\n  It gives Sellbird 100 checks a day for 14 days, then 25 a day.",
         "check_off": "  The check itself is off: turn it on with `sellbird setup` or set\n  compliance.precleared.enabled: true in your config.",
         "no_suppression": "\n  No suppression with id {value}. Run `sellbird suppressions` to see ids.\n",
         "missing_key": "\n  {bang}\n  ERROR: provider skipped: missing key - {label} is not configured, 0 queries can run.",
     },
     _MAIL = {
         "gmail": ("GmailProvider", "gmail_client_id", "gmail_client_secret"),
         "microsoft": ("MicrosoftProvider", "m365_client_id", "m365_tenant_id"),
     },
     _HELP = {
         "provider": "Subscription to think with (default: the one in your config, else claude)",
         "effort": "Codex reasoning effort (minimal/low/medium/high/xhigh)",
         "host": "Loopback address to listen on (default: 127.0.0.1; other addresses are refused)",
         "check": "Also check the configured brain now (Codex: CLI version, isolation and login; Claude: CLI isolation flags; no model call)",
         "email_status": "Comma-separated statuses to include (default: verified,risky)",
         "status": "Comma-separated pipeline statuses (e.g. new,queued); opted-out contacts stay excluded",
         "all": "Export the raw list without filters, including opted-out contacts (not for outreach)",
         "out": "Output file (default: data/exports/company-register-<date>.csv)",
         "city": "Semicolon-separated cities, e.g. \"Denver, CO;Dallas, TX\" (default: icp.geography)",
         "depth": "SERP depth (default: 30 — depth 100 costs 10x since Sept 2025)",
         "preset": "A built-in search instead of your ICP's industries (each needs a search provider like tinyfish, serper or dataforseo_serp). yc: startups whose own site says they're YC-backed; hiring: companies whose own careers pages list one of your hiring_signals roles (else ICP titles); accelerator: ones backed by Techstars, Antler, EF, SPC, 500 Global, Neo, AI Grant, a16z speedrun or Plug and Play; funding: companies announcing a raise on their own site in the last 18 months",
         "trulyinbox": "connect a key, 'other' if you use another warmup service, or show the status (default)",
         "microsoft": "auth: one-time sign-in; test: verify connection",
         "confirm": "Comma-separated codes to confirm ('all' or 'free' accepted)",
         "no_tip": "Retry the prospects writer.require_tip skipped (status no_tip) instead",
         "mcp": "Add or remove the server in your coding agent's config",
         "print": "Print the config to add by hand; change nothing",
     },
     _COMMANDS: list[any] = [
         "install: Install dependencies",
         "setup: Run the interactive setup wizard",
         "run: Start Sellbird's heartbeat loop",
         "train: Train Sellbird on a website",
         ("url", "Website URL to crawl and learn from"),
         ("max_pages?", "Max pages to crawl (default: 100)", 100),
         ("--provider", _HELP["provider"], None, ["claude", "codex"]),
         ("--model", "Model for this provider (default: provider default)"),
         ("--reasoning-effort", _HELP["effort"]),
         "dashboard: Open the web dashboard",
         ("--host", _HELP["host"], "127.0.0.1"),
         ("--port", "Port (default: 5555)", 5555),
         ("--url", "Print the unlock link (with its token) and exit", False),
         "status: Show pipeline status",
         ("--check", _HELP["check"], False),
         "export: Export prospects as a sequencer-ready CSV",
         ("--out", "Output file (default: prospects.csv)", "prospects.csv"),
         ("--email-status", _HELP["email_status"], ""),
         ("--min-score", "Minimum ICP score", 0),
         ("--status", _HELP["status"], ""),
         ("--all", _HELP["all"], False),
         "companies: Export the company register: every company, why it fits, and why it wasn't contacted",
         ("--out", _HELP["out"], ""),
         "gmail: Gmail provider setup",
         ("gmail_action", "auth: one-time OAuth; test: verify connection", None, ["auth", "test"]),
         "microsoft: Microsoft 365 provider setup",
         ("microsoft_action", _HELP["microsoft"], None, ["auth", "test"]),
         "outbox: Review/approve queued emails",
         ("--approve", "Approve one item", "", None, "ID"),
         ("--approve-all", "Approve all pending", False),
         ("--reject", "Reject one item", "", None, "ID"),
         "discover: Find businesses matching your ICP",
         ("--provider", "Discovery provider (default: osm — free, no account)", "osm"),
         ("--providers", "List every provider with cost and setup, then exit", False),
         ("--estimate", "Print projected spend and exit without calling anything", False),
         ("--city", _HELP["city"], ""),
         ("--depth", _HELP["depth"], 30),
         ("--limit", "Max records per query (default: 100)", 100),
         ("--max-spend", "Hard cap in dollars (default: 1.00)", 1.0),
         ("--preset", _HELP["preset"], "", ["", "yc", "hiring", "accelerator", "funding"]),
         ("--no-profile", "Don't profile what was found (profiling is free)", False),
         "profile: Read discovered companies' websites (free, no Claude)",
         ("--limit", "Max sites to read (default: 200)", 200),
         ("--stale-days", "Re-read a site after this many days (default: 90)", 90),
         "signals: Review/confirm which signals Sellbird prospects against",
         ("--confirm", _HELP["confirm"], "", None, "CODES"),
         ("--reject", "Comma-separated codes to turn off", "", None, "CODES"),
         "retry-writes: Retry prospects the Writer couldn't write an email for",
         ("--no-tip", _HELP["no_tip"], False),
         "sending: Kill switch: pause/resume sending",
         ("sending_action?", None, "status", ["pause", "resume", "status"]),
         "warmup: Check if your sending domain is set up and warmed up for cold email",
         ("domain?", "Domain to check (default: your sending mailbox's domain)", ""),
         "trulyinbox: Warmup service: connect TrulyInbox so Sellbird can read the inbox rate",
         ("trulyinbox_action?", _HELP["trulyinbox"], "status", ["status", "connect", "other"]),
         "precleared-key: Get a free Precleared key for the cold-email check and save it to .env",
         ("--email", "Email address for the key (asked if not given)", ""),
         "usage: Show brain usage and quota (Claude or Codex)",
         ("--days", "Breakdown window (default: 30)", 30),
         "mcp: MCP server for your coding agent (launched by it, over stdio)",
         ("mcp_action?", _HELP["mcp"], None, ["install", "uninstall"]),
         ("client?", "Which agent (default: Claude Code only)", None, ["claude", "codex"]),
         ("--print", _HELP["print"], False, None, None, "print_config"),
         ("--yes", "Apply without asking", False),
         "suppressions: Addresses and domains Sellbird never emails",
         ("suppression_action?", None, "list", ["list", "add", "remove"]),
         ("value?", "add: an address or domain; remove: its id", ""),
     ];

def _m(name: str) -> any {
    return importlib.import_module(f"sellbird.{name}");
}

def _sync(command: any) -> any {
    def run(args: any) {
        code = asyncio.run(command(args));
        if code {
            sys.exit(code);
        }
    }
    return functools.wraps(command)(run);
}

async def _state -> any {
    state = _m("state").StateManager();
    await state.init_db();
    return state;
}

def _wrapped(text: str) {
    print(textwrap.fill(text, width=72, initial_indent=_INDENT, subsequent_indent=_INDENT));
}

def _split(text: str, sep: str = ",") -> list[str] {
    return [part.strip() for part in text.split(sep) if part.strip()];
}

def _check_python_version {
    if sys.version_info < MIN_PYTHON {
        need = f"{MIN_PYTHON[0]}.{MIN_PYTHON[1]}";
        have = f"{sys.version_info.major}.{sys.version_info.minor}";
        print(f"\n  Sellbird needs Python {need} or newer. This is Python {have}.");
        print(f"  ({sys.executable})\n\n{_OLD_PYTHON}");
        sys.exit(1);
    }
}

def cmd_install(args: any) {
    _check_python_version();
    print("\n  Installing Sellbird dependencies...\n");
    paths = _m("paths");
    package_root = paths.PACKAGE_ROOT;
    checkout = paths.is_checkout(package_root);
    module = [sys.executable, "-m"];
    if not checkout {
        print("  [1/2] Python packages: already part of this install.");
    } else {
        print("  [1/2] Installing Python packages...");
        requirements = (package_root / "requirements.txt").exists();
        pip_args = ["-r", "requirements.txt"] if requirements else ["-e", "."];
        pip = subprocess.run([*module, "pip", "install", *pip_args], cwd=str(package_root));
        if pip.returncode != 0 {
            print("\n  Failed to install Python packages.");
            print(_SAY["virtualenv"]);
            sys.exit(1);
        }
        print("  ✓ Python packages installed.\n");
    }
    print("  [2/2] Installing Playwright browsers...");
    try {
        browsers = subprocess.run([*module, "playwright", "install", "chromium"], timeout=600);
        ok = bool(browsers.returncode == 0);
    } except (subprocess.TimeoutExpired, OSError) {
        ok = False;
    }
    print(_SAY["browsers_ok" if ok else "browsers_failed"]);
    if checkout {
        _ensure_importable(str(package_root));
    }
    print("  Sellbird is installed. Run 'sellbird setup' next.\n");
}

def _imports_outside -> bool {
    return subprocess.run(
        [sys.executable, "-c", "import sellbird"], cwd="/", capture_output=True
    ).returncode
        == 0;
}

def _ensure_importable(project_root: str) {
    if _imports_outside() {
        return;
    }
    try {
        link = Path(importlib.import_module("site").getsitepackages()[0]) / "sellbird";
        target = Path(project_root) / "sellbird";
        if not link.exists() and target.is_dir() {
            link.symlink_to(target);
            if _imports_outside() {
                print(_SAY["linked"]);
                return;
            }
        }
    } except OSError as e {
        print(f"  Could not apply import fix: {e}");
    }
    print(_NOT_IMPORTABLE);
}

def cmd_setup(args: any) {
    asyncio.run(_m("setup").run_setup());
}

def cmd_run(args: any) {
    _m("main").main();
}

def cmd_train(args: any) {
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
        overrides: dict[str, any] = {};
        for key in ("provider", "model", "reasoning_effort") {
            if getattr(args, key) is not None {
                overrides[key] = getattr(args, key);
            }
        }
        if overrides {
            same = overrides.get("provider", brain_config.provider) == brain_config.provider;
            base: dict[str, any] = brain_config.model_dump() if same else {};
            brain_config = config.BrainConfig(**{**base, **overrides});
        }
    } except (config.ConfigError, ValidationError) as e {
        print(f"  {e}");
        sys.exit(2);
    }
    asyncio.run(
        _m("trainer").Trainer(brain_config=brain_config).train(url, max_pages=args.max_pages)
    );
}

def cmd_mcp(args: any) {
    if getattr(args, "mcp_action", None) {
        sys.exit(
            _m("mcp_install").run_command(
                args.mcp_action, args.client, print_only=args.print_config, yes=args.yes
            ),
        );
    }
    if getattr(args, "print_config", False) or getattr(args, "yes", False) {
        print(_SAY["mcp_flags"], file=sys.stderr);
        sys.exit(2);
    }
    _m("mcp_server").run_stdio();
}

def cmd_dashboard(args: any) {
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

def _row(label: str, value: any) {
    print(f"  {label:<22}{value}");
}

async def _brain_check(state: any, brain_config: any, config_error: any) -> int {
    if brain_config is None {
        _row("Brain:", f"config error: {config_error}");
        return 1;
    }
    thinker = _m("brain").Brain(state, brain_config);
    problem = await thinker.preflight();
    label = thinker.provider_label + (f" ({thinker.model})" if thinker.model else "");
    if problem {
        _row("Brain:", f"{label} NOT READY\n{_INDENT}{problem}");
        return 1;
    }
    _row(
        "Brain:",
        f"{label} {_SAY['codex_ready' if thinker.provider == 'codex' else 'claude_ready']}",
    );
    return 0;
}

@_sync
async def cmd_status(args: any) -> int {
    state = await _state();
    summary = await state.get_state_summary();
    prospects = summary.get("prospects") or {};
    print("\n  Sellbird Pipeline Status\n  " + "=" * 40);
    _row("Prospects:", summary["prospects"]);
    _row("Ready to write for:", _SAY["writable"].format(summary.get("writable_prospects", 0)));
    if prospects.get("write_failed", 0) {
        _row("Couldn't write for:", _SAY["write_failed"].format(prospects.get("write_failed", 0)));
    }
    if prospects.get("no_tip", 0) {
        _row("Nothing to write about: ", _SAY["no_tip"].format(prospects.get("no_tip", 0)));
    }
    _row("Draft campaigns:", summary["draft_campaigns"]);
    _row("Active campaigns:", summary["active_campaigns"]);
    _row("Open conversations:", summary["open_conversations"]);
    by_provider = summary.get("usage_today_by_provider", {});
    _row("Claude calls today:", by_provider.get("claude", summary["usage_today"]));
    _row("Codex calls today:", by_provider.get("codex", 0));
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
        _row("Prospecting:", "PAUSED");
        _wrapped(backlog);
    }
    if notice {
        _row("Sending:", "HELD");
        _wrapped(notice);
    }
    rules_problem = await state.get_setting(_m("agents.writer").EMAIL_RULES_PROBLEM_KEY);
    if rules_problem {
        _row("Writing:", f"STOPPED (writer.email_rules: {rules_problem})");
    }
    hold = await state.current_sends_held();
    if hold {
        waiting = len(await state.get_outbox(status="approved", limit=500));
        (title, detail) = _m("sending_mode").held_message(hold, waiting=waiting);
        _row("Sending:", f"NOT SENDING ({title.split(': ', 1)[-1]})");
        _wrapped(detail);
    }
    precleared = _m("integrations.precleared");
    precleared_hold = await precleared.current_hold(state, loaded);
    if precleared_hold {
        message = precleared.hold_message(precleared_hold);
        _row("Precleared:", f"HOLDING COLD EMAIL since {precleared_hold.get('since', '?')}");
        _wrapped(f"{message['title']}. {message['detail']}");
    }
    if address_notice {
        _row("Postal address:", "MISSING");
        _wrapped(address_notice);
    }
    brain = _m("brain");
    (brain_config, config_error) = (None, None);
    try {
        brain_config = config.load_brain_config();
    } except config.ConfigError as e {
        config_error = e;
    }
    provider = brain_config.provider if brain_config else "";
    brain_status = brain.active_brain_status(
        await state.get_setting(brain.BRAIN_STATUS_KEY), provider
    );
    code = 0;
    if getattr(args, "check", False) {
        code = await _brain_check(state, brain_config, config_error);
    } elif brain_status.get("status") == "paused" {
        label = _LABELS.get(brain_status.get("provider"), "Brain");
        _row("Brain:", f"{label} PAUSED since {brain_status.get('since', '?')}");
        print(f"{_INDENT}{brain_status.get('reason', '')}");
    }
    print();
    return code;
}

def _usage_rows(title: str, days: int, rows: list[any], key: str, width: int) {
    if not rows {
        return;
    }
    print(f"\n  By {title} (last {days} days):");
    for row in rows {
        print(
            f"    {row[key]:<{width}} {row['calls']:>5} calls  {row['output_tokens']:>10,} out tokens",
        );
    }
}

@_sync
async def cmd_usage(args: any) {
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
        print(_SAY["codex_quota"]);
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
    _usage_rows("agent", args.days, await state.usage_by_agent(days=args.days), "agent", 14);
    _usage_rows("task", args.days, (await state.usage_by_task(days=args.days))[:10], "task", 22);
    print(_SAY["not_billed"]);
}

def cmd_companies(args: any) {
    register = _m("register");
    db_path = _m("state").DB_PATH;
    if not db_path.exists() {
        print("\n  No database yet: run 'sellbird discover' or 'sellbird run' first.\n");
        return;
    }
    rows = asyncio.run(
        register.build_register(register.sqlite_query(db_path), _m("config").load_config())
    );
    exports = _m("paths").PROJECT_ROOT / "data" / "exports";
    out = Path(args.out) if args.out else exports / f"company-register-{date.today():%Y-%m-%d}.csv";
    out.parent.mkdir(parents=True, exist_ok=True);
    out.write_text(register.to_csv(rows), encoding="utf-8-sig");
    print(f"\n  Company register: {len(rows)} companies → {out}");
    for (status, n) in Counter(r["status"] for r in rows).most_common() {
        print(f"    {status:<18} {n}");
    }
    print();
}

@_sync
async def cmd_export(args: any) {
    state = await _state();
    email_statuses = _split(args.email_status) if args.email_status else None;
    statuses = _split(args.status) if args.status else None;
    (count, _) = await _m("export").export_prospects_csv(
        state,
        out_path=args.out,
        email_statuses=email_statuses,
        min_score=args.min_score,
        statuses=statuses,
        include_all=args.all,
    );
    score = f", score >= {args.min_score}" if args.min_score else "";
    scope = "all prospects"
        if args.all
        else f"email status {email_statuses or ['verified', 'risky']}{score}";
    print(f"\n  Exported {count} prospect(s) to {args.out}  ({scope})");
    if count == 0 and not args.all {
        print(_SAY["export_tip"]);
    } else {
        print("  The CSV imports directly into Instantly, Smartlead, or any sequencer.\n");
    }
}

def _mail_command(module: str, action: str) {
    (provider, client_id, secret) = _MAIL[module];
    env = _m("config").load_env();
    integration = _m(f"integrations.{module}");
    if action == "auth" {
        ok = integration.run_auth_flow(getattr(env, client_id), getattr(env, secret));
    } elif action == "test" {
        connection = getattr(integration, provider)(_m("config").load_config(), env);
        (ok, detail) = asyncio.run(connection.test_connection());
        print(f"\n  {'✓' if ok else '✗'} {detail}\n");
    } else {
        return;
    }
    sys.exit(0 if ok else 1);
}

def cmd_gmail(args: any) {
    _mail_command("gmail", args.gmail_action);
}

def cmd_microsoft(args: any) {
    _mail_command("microsoft", args.microsoft_action);
}

@_sync
async def cmd_outbox(args: any) {
    state = await _state();
    if args.approve_all {
        print(f"\n  Approved {await state.approve_outbox()} email(s). They'll send on schedule.");
        held = await state.count_held_for_review();
        if held {
            print(_SAY["held"].format(held=held));
        }
        print();
        return;
    }
    if args.approve {
        approved = await state.approve_outbox(args.approve);
        print(f"\n  {'Approved.' if approved else 'No pending item with that id.'}\n");
        return;
    }
    if args.reject {
        rejected = await state.reject_outbox_item(args.reject);
        print(f"\n  {'Rejected.' if rejected else _SAY['not_waiting']}\n");
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
        print(_SAY["outbox_hint"]);
    } else {
        print("  Nothing awaiting review.\n");
    }
}

@_sync
async def cmd_profile(args: any) {
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

def _print_providers(menu: list[any]) {
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

def _print_discovery(r: any, result: any, no_profile: bool) {
    counts: dict[str, any] = defaultdict(int, r);
    print(_SAY["discovered"].format_map(counts));
    if r.get("excluded") {
        print(f"    {r['excluded']} skipped — on your do-not-contact list");
    }
    print(_SAY["recorded"].format_map(counts));
    if r.get("stopped") {
        print(f"    stopped early: {r['stopped']}");
    }
    if no_profile {
        print("\n  PROFILE — skipped (--no-profile)");
    } else {
        print(_SAY["profiled"].format(result.profiled_companies, result.profile_observations));
    }
    for err in result.errors[:5] {
        print(f"    ! {err}");
    }
}

@_sync
async def cmd_discover(args: any) {
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
        print(_SAY["missing_key"].format(bang=bang, label=provider.label));
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
    cities = _split(args.city, ";") or None;
    queries = discover.build_queries(
        config, cities=cities, depth=args.depth, limit=args.limit, preset=preset
    );
    estimate = await discover.run_discovery(
        state, config, args.provider, queries, max_spend=args.max_spend, dry_run=True
    );
    print(f"\n  {len(queries)} queries via {provider.label}");
    for q in queries[:8] {
        print(f"    - {q.keyword()}" + ("" if q.coordinate else _SAY["no_coordinates"]));
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
    _print_discovery(r, result, args.no_profile);
    if r.get("queries_succeeded", 0) == 0 {
        rule = "=" * 68;
        print(_SAY["no_queries"].format(rule, r.get("stopped") or "no queries succeeded"));
        for err in (r.get("errors") or [])[:3] {
            print(f"    - {err}");
        }
        print(f"  {rule}\n");
        raise SystemExit(1);
    }
    print("\n  Next: sellbird dashboard → Signals → cohort builder\n");
}

def _is_free(signal: any) -> bool {
    return (signal["cost_note"] or "").lower().startswith(("free", "included"));
}

@_sync
async def cmd_signals(args: any) {
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
            changed += int(bool(await state.set_signal_status(code, status)));
        }
        print(f"\n  {changed} signal(s) {status}.\n");
        return;
    }
    rows = await state.get_signal_codes();
    counts = {c["signal_code"]: c for c in await state.signal_counts()};
    by_status = Counter(r["status"] for r in rows);
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
    print(_SIGNALS_HINT if by_status["proposed"] else "");
}

@_sync
async def cmd_retry_writes(args: any) {
    state = await _state();
    if getattr(args, "no_tip", False) {
        count = await state.retry_no_tip();
        if count {
            print(_SAY["no_tip_back"].format(count=count));
        } else {
            print("\n  No prospects were skipped for having nothing to write about.\n");
        }
        return;
    }
    count = await state.retry_write_failed();
    if count {
        print(_SAY["retrying"].format(count, _m("agents.writer").MAX_WRITE_ATTEMPTS));
    } else {
        print("\n  No prospects are waiting on a retry.\n");
    }
}

def _load_config_or_exit -> any {
    importlib.import_module("dotenv").load_dotenv(_m("paths").PROJECT_ROOT / ".env");
    config = _m("config");
    try {
        return config.load_config();
    } except config.ConfigError as e {
        print(f"\n  {e}\n");
        raise SystemExit(1);
    }
}

async def _send_history -> tuple[int, int] {
    state = await _state();
    bounces = int(await state.get_setting(_m("agents.handler").BOUNCE_COUNT_KEY) or 0);
    return (await state.count_outbox_sent(), bounces);
}

def cmd_warmup(args: any) {
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
    auth = [
        d.check_mx(domain),
        d.check_spf(domain),
        d.check_dkim(domain, email.warmup.dkim_selector),
        d.check_dmarc(domain),
    ];
    blocklisted = d.check_ip_blocklists(smtp_host) if smtp_host else [];
    reputation = [d.check_domain_age(domain), *d.check_domain_blocklists(domain), *blocklisted];
    sending = [
        d.check_warmup(email.warmup, email.max_daily_sends, provider=email.provider),
        asyncio.run(_warmup_service(sender, email.warmup)),
        d.check_send_history(*asyncio.run(_send_history())),
    ];
    sections = [
        ("Authentication", auth),
        ("Reputation", reputation),
        ("Warmup & sending", sending),
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

async def _warmup_service(address: str, warmup: any) -> any {
    ti = _m("integrations.trulyinbox");
    state = await _state();
    (health, error) = await ti.current_health(address);
    other = health is None and not error and await ti.get_choice(state) == "other";
    return _m("deliverability").check_warmup_service(
        health, warmup, error=error, other_service=other
    );
}

async def _trulyinbox_connect(state: any, address: str, warmup: any) -> int {
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

async def _trulyinbox(args: any, address: str, warmup: any) -> int {
    ti = _m("integrations.trulyinbox");
    state = await _state();
    if args.trulyinbox_action == "other" {
        await ti.set_choice(state, "other");
        print(_SAY["ti_other"]);
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

def cmd_trulyinbox(args: any) {
    config = _load_config_or_exit();
    address = _m("integrations.trulyinbox").sending_address(config);
    raise SystemExit(asyncio.run(_trulyinbox(args, address, config.channels.email.warmup)));
}

def cmd_precleared_key(args: any) {
    os = importlib.import_module("os");
    precleared = _m("integrations.precleared");
    importlib.import_module("dotenv").load_dotenv(_m("paths").PROJECT_ROOT / ".env");
    saved = _m("setup")._read_env_file().get("PRECLEARED_API_KEY", "").strip("'\" ");
    if saved or os.getenv("PRECLEARED_API_KEY", "").strip() {
        print(_SAY["have_key"]);
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
        print(_SAY["free_key"]);
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
        print(_SAY["no_key"].format(error=result.error, url=precleared.GET_KEY_URL));
        raise SystemExit(1);
    }
    try {
        _m("dashboard")._write_env_file({"PRECLEARED_API_KEY": result.key});
    } except OSError as e {
        print(_SAY["not_saved"].format(e=e, url=precleared.GET_KEY_URL));
        raise SystemExit(1);
    }
    print(_SAY["key_saved"]);
    if enabled is False {
        print(_SAY["check_off"]);
    }
    print("  If Sellbird is running, restart it so it uses the key.\n");
    raise SystemExit(0);
}

@_sync
async def cmd_sending(args: any) {
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

def _carry_over_from_harvey {
    notes = _m("legacy").migrate_files();
    legacy_env = importlib.import_module("sellbird").LEGACY_ENV;
    if legacy_env {
        notes.append(_SAY["harvey_env"].format(", ".join(legacy_env)));
    }
    for note in notes {
        print(f"Sellbird (formerly Harvey): {note}", file=sys.stderr);
    }
}

@_sync
async def cmd_suppressions(args: any) -> int {
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
            print(_SAY["no_suppression"].format(value=args.value));
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

def _add_argument(sub: any, flag: str, help: any, `default: any = None, *more: any) {
    options: dict[str, any] = {"help": help, **dict(zip(("choices", "metavar", "dest"), more))};
    if `default is False {
        options["action"] = "store_true";
    } elif isinstance(`default, (int, float)) {
        options["type"] = type(`default);
    }
    if `default is not False {
        options["default"] = `default;
    }
    if flag.endswith("?") {
        (flag, options["nargs"]) = (flag[:-1], "?");
    }
    sub.add_argument(flag, **{k: v for (k, v) in options.items() if v is not None});
}

def _build_parser -> any {
    parser = argparse.ArgumentParser(
        prog="sellbird",
        description="Sellbird — the open-source outreach platform. Make the first move.",
    );
    subparsers = parser.add_subparsers(dest="command");
    sub: any = None;
    for row in _COMMANDS {
        if not isinstance(row, str) {
            _add_argument(sub, *row);
            continue;
        }
        (name, about) = row.split(": ", 1);
        if name == "suppressions" {
            _m("inbox_cli").register(subparsers);
            _m("desktop_cli").register_desktop_commands(subparsers);
            _m("desktop_cli").register(subparsers);
        }
        sub = subparsers.add_parser(name, help=about);
        sub.set_defaults(func=globals()["cmd_" + name.replace("-", "_")]);
    }
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

def main {
    _m("textio").utf8_stdio();
    paths = _m("paths");
    project_root = str(paths.PROJECT_ROOT);
    parser = _build_parser();
    args = parser.parse_args();
    _carry_over_from_harvey();
    args._project_root = project_root;
    home = _m("home");
    home_root = paths.PROJECT_ROOT;
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

with entry:__main__ {
    main();
}
