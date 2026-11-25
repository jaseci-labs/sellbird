impl _print_sellbird(message: str) {
    print(f"\n  Sellbird: {message}");
}

impl _say(block: str) {
    for message in re.split(r"\n(?!$)", block) {
        _print_sellbird(message);
    }
}

impl _print_step(step: int, total: int, title: str) {
    print(f"\n{_RULE}\n  Step {step}/{total}: {title}\n{_RULE}");
}

impl _cancelled {
    print("\n\n  Setup cancelled.");
    raise SystemExit(1);
}

impl _ask(prompt: str, `default: str = "", required: bool = True, secret: bool = False) -> str {
    suffix = f" [{`default}]" if `default else "";
    reader = getpass.getpass if secret else builtins.input;
    while True {
        try {
            answer = reader(f"\n  → {prompt}{suffix}: ").strip();
        } except (EOFError, KeyboardInterrupt) {
            _cancelled();
        }
        if not answer and `default {
            return `default;
        }
        if answer or not required {
            return answer;
        }
        print("    (required — please enter a value)");
    }
}

impl _ask_yes_no(prompt: str, `default: bool = True) -> bool {
    suffix = " [Y/n]" if `default else " [y/N]";
    try {
        answer = builtins.input(f"\n  → {prompt}{suffix}: ").strip().lower();
    } except (EOFError, KeyboardInterrupt) {
        _cancelled();
    }
    return answer in ("y", "yes") if answer else `default;
}

impl _read_env_file -> dict[str, str] {
    existing: dict[str, str] = {};
    if ENV_FILE.exists() {
        for line in read_user_text(ENV_FILE).splitlines() {
            line = line.strip();
            if line and not line.startswith("#") and "=" in line {
                (key, _, value) = line.partition("=");
                existing[key.strip()] = value.strip();
            }
        }
    }
    return existing;
}

impl _config_file -> Path {
    local = CONFIG_FILE.with_name("sellbird.local.yaml");
    return local if local.exists() else CONFIG_FILE;
}

impl _saved(*path: str) -> any {
    try {
        data = yaml.safe_load(read_user_text(_config_file()));
    } except (OSError, yaml.YAMLError) {
        return None;
    }
    for key in path {
        data = data.get(key) if isinstance(data, dict) else None;
    }
    return data;
}

impl _current_precleared -> dict[any, any] {
    section = _saved("compliance", "precleared");
    return section if isinstance(section, dict) else {};
}

impl _sender_country(value: any, strict: bool = True) -> str {
    code = str(value or "").strip().upper();
    code = COUNTRY_ALIASES.get(code, code);
    return "" if strict and code not in SENDER_COUNTRIES else code;
}

impl _saved_timezone -> str {
    return str(_saved("usage", "quiet_hours", "timezone") or "").strip();
}

impl _save_precleared(config: any, answers: any) {
    compliance = config.get("compliance");
    if not isinstance(compliance, dict) {
        compliance = config["compliance"] = {};
    }
    section = compliance.get("precleared");
    if not isinstance(section, dict) {
        section = compliance["precleared"] = {};
    }
    section.update(answers);
}

impl _merge_answers(existing: any, answers: any) {
    for (key, value) in answers.items() {
        if isinstance(value, dict) and isinstance(existing.get(key), dict) {
            _merge_answers(existing[key], value);
        } elif value not in ("", [], {}, None) {
            existing[key] = value;
        }
    }
}

impl _product_configured -> bool {
    data = _saved();
    if not isinstance(data, dict) {
        return False;
    }
    persona = data.get("persona") if isinstance(data.get("persona"), dict) else {};
    product = data.get("product") if isinstance(data.get("product"), dict) else {};
    return persona.get("company") not in (None, "", "Your Company")
        and product.get("name") not in (None, "", "Your Product");
}

impl _check_claude_cli -> bool {
    return shutil.which("claude") is not None;
}

impl _check_codex_cli -> bool {
    return shutil.which("codex") is not None;
}

impl _test_claude(brain: any) -> bool {
    return "SELLBIRD_READY"
        in await brain.think(
            "Respond with exactly: SELLBIRD_READY", session_id="sellbird-setup-test"
        );
}

impl _ask_brain_config -> BrainConfig {
    _print_sellbird("I think with an AI subscription you already pay for:");
    print(
        "    claude — your Claude plan, via Claude Code (default)\n    codex  — your ChatGPT plan, via the Codex CLI",
    );
    while True {
        provider = _ask("Which one? (claude/codex)", default="claude").lower();
        if provider == "codex" {
            codex = importlib.import_module("sellbird.codex");
            try {
                codex.require_supported_platform();
            } except codex.CodexError as e {
                print(f"    ({e})");
                continue;
            }
        }
        if provider in ("claude", "codex") {
            break;
        }
        print("    (type claude or codex)");
    }
    suggested = "";
    if provider == "codex" {
        suggested = importlib.import_module("sellbird.codex").SUGGESTED_MODEL;
        print(
            f"    {suggested} is the Codex model Sellbird has verified as text-only\n    (no code-execution tools). Press Enter to use it, or type another.",
        );
    }
    while True {
        if provider == "codex" {
            model = _ask("Model", default=suggested, required=False);
        } else {
            model = _ask("Model (leave blank for the default)", required=False);
        }
        try {
            return BrainConfig(provider=provider, model=model);
        } except ValidationError {
            print(_MODEL_RETRY);
        }
    }
}

impl _test_instantly(api_key: str) -> bool {
    try {
        async with httpx.AsyncClient(timeout=10) as client {
            resp = await client.get(
                "https://api.instantly.ai/api/v2/accounts",
                headers={"Authorization": f"Bearer {api_key}"},
            );
            return resp.status_code == 200;
        }
    } except Exception {
        return False;
    }
}

impl _split(answer: str) -> list[str] {
    return [part.strip() for part in answer.split(",") if part.strip()];
}

impl _ask_number(prompt: str, fallback: str, parse: any) -> any {
    answer = _ask(prompt, default=fallback);
    try {
        return parse(answer);
    } except ValueError {
        print(f"    (didn't catch that — using {fallback})");
        return parse(fallback);
    }
}

impl _percent(value: str) -> float {
    return min(100.0, max(1.0, float(value)));
}

impl _at_least_one(value: str) -> int {
    return max(1, int(value));
}

impl SetupWizard.init {
    self.env_vars = {};
    self.config = {};
    self.brain_config = BrainConfig();
    self.precleared = None;
    self.config_saved = False;
    self.manual_product = False;
}

impl SetupWizard.run {
    print(_BANNER);
    _say("""Hey. I'm Sellbird. Let's get me set up so I can start
closing deals for you. I'll walk you through everything.
This takes about 5 minutes.\n""");
    _print_step(1, 7, "Checking Prerequisites");
    await self._check_prerequisites();
    _print_step(2, 7, "Email Platform (Instantly)");
    await self._setup_email_platform();
    _print_step(3, 7, "LinkedIn (Optional)");
    self._setup_linkedin();
    _print_step(4, 7, "Website Crawling (Optional)");
    self._setup_cloudflare();
    _print_step(5, 7, "Train Sellbird on Your Product");
    await self._setup_product();
    _print_step(6, 7, "Configure Behavior");
    self._setup_behavior();
    _print_step(7, 7, "Cold-Email Check (Optional)");
    self._setup_compliance();
    self._write_env();
    self._write_config();
    await self._print_summary();
}

impl SetupWizard._check_prerequisites {
    self.brain_config = _ask_brain_config();
    if self.brain_config.provider == "codex" {
        await self._check_codex();
    } else {
        await self._check_claude();
    }
}

impl SetupWizard._test_brain(testing: str, failed: str, note: str = "") {
    print(testing, end=" ", flush=True);
    state = StateManager();
    await state.init_db();
    if await _test_claude(Brain(state, self.brain_config)) {
        print("✓ Working");
    } else {
        print("✗ Failed");
        _say(failed);
        if note {
            print(note);
        }
        if not _ask_yes_no("Continue anyway?", default=False) {
            raise SystemExit(1);
        }
    }
    self._check_python_packages();
}

impl SetupWizard._check_claude {
    print("\n  Checking Claude Code CLI...", end=" ");
    if not _check_claude_cli() {
        print("✗ Not found");
        _print_sellbird("I need Claude Code CLI to think. Install it from:");
        print(
            "         https://claude.ai/download\n\n         After installing, run 'claude login' to authenticate,\n         then re-run this setup.",
        );
        raise SystemExit(1);
    }
    print("✓ Found");
    await self._test_brain(
        "  Testing Claude headless mode...",
        """Claude CLI is installed but headless mode isn't working.
Make sure you're logged in: run 'claude login'""",
        "\n         Also verify your Max subscription is active.",
    );
}

impl SetupWizard._check_codex {
    codex = importlib.import_module("sellbird.codex");
    print("\n  Checking Codex CLI...", end=" ");
    if not _check_codex_cli() {
        print("✗ Not found");
        _print_sellbird("I need the Codex CLI to think with your ChatGPT plan:");
        print(
            f"         {codex.CODEX_INSTALL_HINT}\n\n         Then run 'codex login', choose 'Sign in with ChatGPT',\n         and re-run this setup.",
        );
        raise SystemExit(1);
    }
    print("✓ Found");
    print("  Checking Codex CLI version...", end=" ");
    try {
        print(f"✓ {codex.check_cli_version()}");
    } except codex.CodexError as e {
        print("✗ Not supported");
        _print_sellbird(str(e));
        raise SystemExit(1);
    }
    print("  Checking Codex ChatGPT login...", end=" ");
    try {
        codex.check_native_auth();
        print("✓ Found");
    } except codex.CodexError as e {
        print("✗ Not ready");
        _print_sellbird(str(e));
        raise SystemExit(1);
    }
    await self._test_brain(
        "  Testing Codex (isolated, no tools)...",
        """Codex is installed but the test call failed. The log
above says why (login, plan limits, or isolation).""",
    );
}

impl SetupWizard._check_python_packages {
    print("  Checking Python dependencies...", end=" ");
    missing: list[str] = [];
    for pkg in _PACKAGES {
        try {
            importlib.import_module(pkg);
        } except ImportError {
            missing.append(pkg);
        }
    }
    if not missing {
        print("✓ All installed");
    } else {
        print(f"✗ Missing: {', '.join(missing)}\n\n  Run: pip install -r requirements.txt");
        if not _ask_yes_no("Continue anyway?", default=False) {
            raise SystemExit(1);
        }
    }
    _print_sellbird("Prerequisites look good. Let's keep going.");
}

impl SetupWizard._setup_email_platform {
    _say("""I need a cold email platform to send campaigns through.
Right now I support Instantly (recommended) and Woodpecker.""");
    if not _ask_yes_no("Do you have an Instantly account?") {
        _say("""No problem. You'll need one eventually to send emails.
Sign up at https://instantly.ai (Growth plan for API access).
Add your API key to .env later as INSTANTLY_API_KEY.""");
        self.env_vars["INSTANTLY_API_KEY"] = "";
        return;
    }
    api_key = _ask("Instantly API key (from Settings → Integrations; input hidden)", secret=True);
    self.env_vars["INSTANTLY_API_KEY"] = api_key;
    print("\n  Testing API key...", end=" ", flush=True);
    if await _test_instantly(api_key) {
        print("✓ Connected");
        _print_sellbird("Perfect. I can send campaigns through Instantly now.");
    } else {
        print("✗ Failed");
        _say("""Couldn't connect. The key might be wrong, or you might
need the Growth plan for API access. I'll save it anyway —
you can fix it later in .env.""");
    }
}

impl SetupWizard._setup_linkedin {
    _say("""I can search LinkedIn to find prospects matching your ICP.
I'll log into your LinkedIn account using a browser, with
conservative rate limits and human-like pacing.""");
    print(_LINKEDIN_RISK);
    if _ask_yes_no("Set up LinkedIn prospecting anyway?", default=False) {
        self.env_vars["LINKEDIN_EMAIL"] = _ask("LinkedIn email/username");
        self.env_vars["LINKEDIN_PASSWORD"] = _ask("LinkedIn password (input hidden)", secret=True);
        _say("""Got it. I'll stay well under the rate limits and behave
like a careful human, but the ToS risk is yours to own.""");
    } else {
        _say("""That's fine. I can still find prospects via Google
and company websites. You can add LinkedIn later.""");
        self.env_vars["LINKEDIN_EMAIL"] = "";
        self.env_vars["LINKEDIN_PASSWORD"] = "";
    }
}

impl SetupWizard._setup_cloudflare {
    _say("""When I train on a product website, I can crawl it deeply
using Cloudflare's Browser Rendering API. This means I can
handle JavaScript-heavy sites and crawl hundreds of pages.
It's $5/month for ~12,000 pages. Totally optional.""");
    if _ask_yes_no("Set up Cloudflare crawling?", default=False) {
        self.env_vars["CLOUDFLARE_ACCOUNT_ID"] = _ask("Cloudflare Account ID");
        self.env_vars["CLOUDFLARE_API_TOKEN"] = _ask(_CF_TOKEN, secret=True);
        _print_sellbird("Nice. I'll use Cloudflare for deep crawling during training.");
    } else {
        _say("""No problem. I'll use my built-in crawler instead. It works
great for most sites — just can't render JavaScript.""");
        self.env_vars["CLOUDFLARE_ACCOUNT_ID"] = "";
        self.env_vars["CLOUDFLARE_API_TOKEN"] = "";
    }
}

impl SetupWizard._setup_product {
    _say("""Now the important part — I need to learn about what you're selling.
I can either crawl your website and figure it out myself,
or you can tell me the basics manually.\n""");
    method = _ask("Train from website URL or enter manually? (url/manual)", default="url").lower();
    if method in ("url", "u", "website") {
        url = _ask("Your product's website URL (e.g. https://yourcompany.com)");
        _say(f"""Give me a minute — I'm going to crawl {url}
and learn everything I can about your product.\n""");
        trainer = importlib.import_module("sellbird.trainer").Trainer(
            brain_config=self.brain_config
        );
        self.config = await trainer.train(url, str(_config_file())) or {};
        if self.config {
            _say("""Training complete! I've got a solid understanding
of your product now. Check sellbird.yaml to review
what I learned — tweak anything that looks off.""");
            return;
        }
        _print_sellbird("Hmm, had trouble with that URL. Let's do it manually.");
    }
    self._ask_product();
    self.manual_product = True;
    _print_sellbird("Got it. I have everything I need about your product.");
}

impl SetupWizard._ask_product {
    _print_sellbird("I'll ask you a few questions about your product.\n");
    company = _ask("Company name");
    product = _ask("Product/service name");
    description = _ask("One-line description (what does it do, who is it for?)");
    pricing = _ask("Pricing info", default="Contact for pricing");
    print("\n  Enter 3-5 key benefits (one per line, empty line to finish):");
    benefits: list[str] = [];
    while benefit := _ask(f"  Benefit {len(benefits) + 1}", required=False) {
        benefits.append(benefit);
    }
    _print_sellbird("Now let's define your ideal customer.\n");
    industries = _split(_ask("Target industries (comma-separated)"));
    titles = _split(_ask("Decision-maker titles (comma-separated)"));
    company_size = _ask("Target company size", default="10-200 employees");
    geography = _split(_ask(_GEOGRAPHY, default="United States"));
    _print_sellbird("Now let's talk about your offer — what happens when someone's interested?\n");
    primary_offer = _ask(_MAIN_OFFER, required=False);
    entry_offer = _ask(_ENTRY_OFFER, default="", required=False);
    print(
        "\n  What's the goal when someone shows interest?\n    1. Book a call\n    2. Start a free trial\n    3. Just get a reply / start a conversation",
    );
    goal = _GOALS.get(_ask("Goal (1/2/3)", default="1"), "book_call");
    (booking_method, booking_url, meeting_duration, meeting_owner) = (
        "suggest_times",
        "",
        "15 minutes",
        "",
    );
    if goal == "book_call" {
        if _ask_yes_no("Do you have a calendar booking link (Calendly, Cal.com, etc.)?") {
            booking_url = _ask("Booking URL");
            booking_method = "calendar_link";
        } else {
            print(
                "\n  How should Sellbird suggest meeting times?\n    1. Suggest specific times ('How about Thursday at 2pm?')\n    2. Ask for their preference ('What does your calendar look like?')",
            );
            booking_method = "suggest_times"
                if _ask("Method (1/2)", default="1") == "1"
                else "ask_preference";
        }
        meeting_duration = _ask("How long is the call?", default="15 minutes");
        meeting_owner = _ask("Who takes the meeting? (your name or role)", required=False);
    }
    _print_sellbird("What persona should I use for outreach?\n");
    persona_name = _ask("My name (what prospects see)", default="Alex");
    persona_email = _ask("My email address");
    persona_role = _ask("My title/role", default="Business Development");
    self.config = {
        "persona": {
            "name": persona_name,
            "company": company,
            "role": persona_role,
            "email": persona_email,
            "linkedin": "",
            "tone": "professional, consultative, confident",
        },
        "product": {
            "name": product,
            "description": description,
            "pricing": pricing,
            "key_benefits": benefits or ["Benefit 1"],
            "objection_responses": {},
            "offer": {
                "primary": primary_offer or "",
                "entry": entry_offer or "",
                "goal": goal,
                "booking_method": booking_method,
                "booking_url": booking_url,
                "meeting_duration": meeting_duration,
                "meeting_owner": meeting_owner or "",
            },
        },
        "icp": {
            "industries": industries or ["Technology"],
            "company_size": company_size,
            "titles": titles or ["VP", "Director"],
            "geography": geography,
        },
        "channels": {
            "email": {"enabled": True, "provider": "instantly", "max_daily_sends": 50},
            "linkedin": {
                "enabled": bool(self.env_vars.get("LINKEDIN_EMAIL")),
                "max_daily_connections": 20,
                "max_daily_messages": 10,
            },
        },
        "usage": {
            "max_daily_claude_percent": 80,
            "heartbeat_interval_minutes": 15,
            "quiet_hours": {"start": "22:00", "end": "07:00", "timezone": "America/New_York"},
        },
    };
}

impl SetupWizard._setup_behavior {
    _print_sellbird("Last thing — a few settings for how I operate.\n");
    print("  I track my own Claude usage so I don't eat your whole daily quota.");
    usage_pct = _ask_number("Max % of daily Claude usage I can consume", "80", _percent);
    print("\n  I wake up on a schedule to check for work.");
    interval = _ask_number("How often should I check for work (minutes)?", "15", _at_least_one);
    print("\n  I won't send emails or do outreach during quiet hours.");
    quiet_start = _ask("Quiet hours start (24h format)", default="22:00");
    quiet_end = _ask("Quiet hours end (24h format)", default="07:00");
    timezone = _ask("Your timezone", default="America/New_York");
    daily_sends = _ask_number("Max emails to send per day", "50", _at_least_one);
    if daily_sends > 200 {
        print(
            "\n  ⚠  200+ sends/day from a fresh domain will torch your\n     deliverability. Warm up gradually (see docs/deliverability.md).",
        );
    }
    if self.config {
        self.config["usage"] = {
            "max_daily_claude_percent": usage_pct,
            "heartbeat_interval_minutes": interval,
            "quiet_hours": {"start": quiet_start, "end": quiet_end, "timezone": timezone},
        };
        if "channels" in self.config and "email" in self.config["channels"] {
            self.config["channels"]["email"]["max_daily_sends"] = daily_sends;
        }
    }
    _print_sellbird("Perfect. All configured.");
}

impl SetupWizard._timezone -> str {
    usage = self.config.get("usage") if isinstance(self.config, dict) else None;
    quiet = usage.get("quiet_hours") if isinstance(usage, dict) else None;
    zone = quiet.get("timezone") if isinstance(quiet, dict) else None;
    return str(zone or "").strip() or _saved_timezone();
}

impl SetupWizard._leave_off(was_on: bool) {
    self.precleared = {"enabled": False} if was_on else None;
}

impl SetupWizard._setup_compliance {
    current = _current_precleared();
    was_on = current.get("enabled") is True;
    uk_sender = self._timezone() == "Europe/London";
    _say("""Before the first email to anyone new, I can ask Precleared
(precleared.dev) which cold-email rules apply to them. A UK
sole trader needs consent where a limited company doesn't,
and the address alone won't tell you which. Totally optional.""");
    if uk_sender {
        _say("""Recommended for a UK sender like you: under PECR, whether a cold
email is allowed turns on who the recipient is (a company or a
sole trader), and Precleared looks each one up on Companies House.""");
    }
    print(_PRECLEARED_DATA);
    if not _ask_yes_no("Turn on the cold-email check?", default=was_on) {
        self._leave_off(was_on);
        _say(f"""No problem. You can turn it on later under
compliance.precleared in {_config_file().name}.""");
        return;
    }
    default_country = _sender_country(current.get("sender_country")) or ("GB" if uk_sender else "");
    codes = ", ".join(SENDER_COUNTRIES);
    ending = ")" if default_country else "; blank to skip)";
    while True {
        country = _sender_country(
            _ask(
                f"Where is your business based? (two-letter code, e.g. GB or US{ending}",
                default=default_country,
                required=False,
            ),
            strict=False,
        );
        if country in SENDER_COUNTRIES {
            break;
        }
        if not country {
            self._leave_off(was_on);
            _say(f"""Precleared takes a sender based in one of these countries:
{codes}. I'll leave the check off for now.""");
            return;
        }
        print(f"    (type one of {codes}, or leave it blank to skip)");
    }
    try {
        saved_prospects = normalize_prospect_country(current.get("prospect_country"));
    } except ValueError {
        saved_prospects = "";
    }
    hint = "type none if not" if saved_prospects else "blank if not";
    while True {
        answer = _ask(
            f"Your prospects' country, if they're all in one (e.g. US; {hint})",
            default=saved_prospects,
            required=False,
        );
        word = answer.strip().lower();
        if word == "none"
            or (
                word == "no"
                and not _ask_yes_no(
                    "NO is Norway's code. Are your prospects all in Norway?", default=False
                )
            )
        {
            prospects = "";
            break;
        }
        try {
            prospects = normalize_prospect_country(answer);
            break;
        } except ValueError as e {
            print(f"    ({e})");
        }
    }
    self.precleared = {"enabled": True, "sender_country": country, "prospect_country": prospects};
    self._ask_precleared_key();
}

impl SetupWizard._ask_precleared_key {
    saved_key = _read_env_file().get("PRECLEARED_API_KEY", "").strip("'\" ");
    has_key = bool(saved_key or os.getenv("PRECLEARED_API_KEY", "").strip());
    if not has_key {
        _say("""Without a key Precleared allows 10 checks a day. A free key
gives Sellbird 100 a day for its first 14 days, then 25 a day.""");
        key = self._get_free_precleared_key();
        if key {
            self.env_vars["PRECLEARED_API_KEY"] = key;
            _print_sellbird("Got your free key and saved it to .env.");
            return;
        }
    }
    keeps = "Enter keeps your current key" if has_key else "Enter to skip";
    key = _ask(f"Precleared API key (input hidden; {keeps})", required=False, secret=True);
    if key {
        self.env_vars["PRECLEARED_API_KEY"] = key;
        _print_sellbird("Saved the key to .env.");
    } elif has_key {
        _print_sellbird("Keeping the key you already have.");
    } else {
        self.env_vars["PRECLEARED_API_KEY"] = "";
        _say("""No problem: 10 checks a day without one. Run
`sellbird precleared-key` whenever you'd like a free key.""");
    }
}

impl SetupWizard._get_free_precleared_key -> str {
    if not _ask_yes_no("Get a free Precleared key now? It only needs your email address") {
        return "";
    }
    print(
        "\n  Precleared receives the address to make the key\n  (privacy: https://precleared.dev/privacy).",
    );
    country = (self.precleared or {}).get("sender_country", "");
    while True {
        email = _ask("Email address for the key (Enter to skip)", required=False);
        if not email {
            return "";
        }
        result = create_free_key(email, country=country);
        if result.key {
            return result.key;
        }
        _print_sellbird(f"Couldn't get a key: {result.error}.");
        if not result.bad_email {
            _print_sellbird(f"You can paste one from {GET_KEY_URL} instead.");
            return "";
        }
    }
}

impl SetupWizard._write_env {
    merged = _read_env_file();
    for (key, value) in self.env_vars.items() {
        if value or key not in merged {
            merged[key] = value;
        }
    }
    ENV_FILE.write_text(
        "\n".join(f"{key}={value}" for (key, value) in merged.items()) + "\n", encoding="utf-8"
    );
    try {
        ENV_FILE.chmod(0o600);
    } except OSError {}
    logger.info(f"Wrote {ENV_FILE}");
}

impl SetupWizard._write_config {
    config_file = _config_file();
    if not self.config {
        return;
    }
    self.config["brain"] = importlib.import_module("sellbird.trainer").brain_section(
        self.brain_config
    );
    if not config_file.exists() {
        if self.precleared {
            _save_precleared(self.config, self.precleared);
        }
        with open(config_file, "w", encoding="utf-8") as f {
            yaml.dump(self.config, f, default_flow_style=False, sort_keys=False);
        }
        logger.info(f"Wrote {config_file}");
        self.config_saved = True;
        return;
    }
    try {
        existing = yaml.safe_load(read_user_text(config_file)) or builtins.dict();
        if self.manual_product {
            for section in ("persona", "product", "icp") {
                if section in self.config {
                    if not isinstance(existing.get(section), dict) {
                        existing[section] = {};
                    }
                    _merge_answers(existing[section], self.config[section]);
                }
            }
        }
        existing["usage"] = self.config.get("usage", existing.get("usage", {}));
        existing["brain"] = self.config["brain"];
        if "LINKEDIN_EMAIL" in self.env_vars {
            existing.setdefault("channels", {}).setdefault("linkedin", {})["enabled"] = bool(
                self.env_vars["LINKEDIN_EMAIL"]
            );
        }
        if "channels" in self.config {
            existing.setdefault("channels", {});
            if "email" in self.config["channels"] {
                existing["channels"].setdefault("email", {});
                existing["channels"]["email"]["max_daily_sends"] = self.config["channels"]["email"].get(
                    "max_daily_sends", 50
                );
            }
        }
        if self.precleared {
            _save_precleared(existing, self.precleared);
        }
        text = yaml.dump(existing, default_flow_style=False, sort_keys=False);
        with open(config_file, "w", encoding="utf-8") as f {
            f.write(text);
        }
        self.config_saved = True;
    } except Exception as e {
        _print_sellbird(f"Couldn't save your settings to {config_file.name} ({e}).");
        _print_sellbird("Nothing in it was changed. Fix the file and re-run setup.");
    }
}

impl SetupWizard._print_summary {
    print(_DONE_BANNER);
    codex = self.brain_config.provider == "codex";
    checks = {
        ("Codex CLI (ChatGPT plan)" if codex else "Claude Code CLI"): (
            _check_codex_cli() if codex else _check_claude_cli()
        ),
        "Instantly API": bool(self.env_vars.get("INSTANTLY_API_KEY")),
        "LinkedIn": bool(self.env_vars.get("LINKEDIN_EMAIL")),
        "Cloudflare Crawl": bool(self.env_vars.get("CLOUDFLARE_ACCOUNT_ID")),
        "Product trained": _product_configured(),
        "Cold-email check (Precleared)": bool(
            self.config_saved and self.precleared and self.precleared.get("enabled")
        ),
    };
    for (name, ok) in checks.items() {
        print(f"  {'✓' if ok else '–'} {name}");
    }
    print(_NEXT_STEPS.format(_config_file().name));
    _say("""I'm ready. Run 'sellbird run' and I'll start closing.
Make the first move.\n""");
}

impl run_setup {
    await SetupWizard().run();
}

impl main {
    asyncio.run(run_setup());
}
