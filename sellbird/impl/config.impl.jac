impl ConfigError.__repr__ -> str {
    return (getattr(builtins.super(ConfigError, self), "__repr__") as any)();
}

impl ConfigError.__eq__(other: any) -> bool {
    return self is other;
}

impl ConfigError.__hash__ -> int {
    return id(self);
}

impl ConfigFileNotFoundError.__repr__ -> str {
    return (getattr(builtins.super(ConfigFileNotFoundError, self), "__repr__") as any)();
}

impl ConfigFileNotFoundError.__eq__(other: any) -> bool {
    return self is other;
}

impl ConfigFileNotFoundError.__hash__ -> int {
    return id(self);
}

impl WarmupConfig._blank_is_empty(v, info) -> any {
    if v is None {
        return "";
    }
    if info.field_name != "start_date" {
        return v;
    }
    if isinstance(v, _date) {
        return (v.date() if hasattr(v, "date") and callable(v.date) else v).isoformat();
    }
    if isinstance(v, `str) and len(v.strip()) > 10 and v.strip()[10] in " T" {
        return v.strip()[:10];
    }
    return "" if v is None else v;
}

impl WarmupConfig._blank_is_default(v, info) -> any {
    return cls.model_fields[info.field_name].default if v is None else v;
}

impl WarmupConfig._valid_date(v: builtins.str) -> builtins.str {
    v = (v or "").strip();
    if v {
        try {
            _date.fromisoformat(v);
        } except ValueError {
            raise ValueError(f"warmup.start_date '{v}' must be YYYY-MM-DD.");
        }
    }
    return v;
}

impl WarmupConfig._non_negative(v: builtins.int) -> builtins.int {
    if v < 0 {
        raise ValueError("warmup values must be >= 0");
    }
    return v;
}

impl WarmupConfig.days_in(today: _date | None = None) -> builtins.int | None {
    if not self.start_date {
        return None;
    }
    return ((today or _date.today()) - _date.fromisoformat(self.start_date)).days;
}

impl WarmupConfig.daily_cap(ceiling: builtins.int, today: _date | None = None) -> builtins.int {
    days: any = self.days_in(today);
    if days is None {
        return ceiling;
    }
    if days < self.min_days {
        return 0;
    }
    return min(ceiling, self.start_sends + (days - self.min_days) * self.daily_increase);
}

impl SendWindowConfig._valid_clock(v, info) -> any {
    if v is None {
        return cls.model_fields[info.field_name].default;
    }
    if isinstance(v, `int) and not isinstance(v, `bool) and 0 <= v < 24 * 60 {
        v = f"{v // 60:02d}:{v % 60:02d}";
    }
    v = `str(v).strip();
    try {
        _time.fromisoformat(v);
    } except ValueError {
        raise ValueError(f"send_window time '{v}' is not valid. Use 24h HH:MM, e.g. '08:00'.");
    }
    return v;
}

impl SendWindowConfig._start_before_end -> any {
    if _time.fromisoformat(self.start) >= _time.fromisoformat(self.end) {
        raise ValueError(
            "send_window.start must be earlier than send_window.end (a send window can't run past midnight).",
        );
    }
    return self;
}

impl send_window_of(config) -> "SendWindowConfig | None" {
    email: any = getattr(getattr(config, "channels", None), "email", None);
    window: any = getattr(email, "send_window", None);
    return window if isinstance(window, SendWindowConfig) else None;
}

impl operator_timezone(config) -> builtins.str {
    quiet: any = getattr(getattr(config, "usage", None), "quiet_hours", None);
    return getattr(quiet, "timezone", "") or "UTC";
}

impl SignatureConfig._blank_is_empty(v) -> any {
    return "" if v is None else `str(v).strip();
}

impl SignatureConfig._sane_width(v: builtins.int) -> builtins.int {
    if not 16 <= v <= 600 {
        raise ValueError("signature.width must be between 16 and 600 pixels.");
    }
    return v;
}

impl SignatureConfig._web_link(v: builtins.str) -> builtins.str {
    if v and not re.match("https?://[^\\s\\\"<>]+$", v) {
        raise ValueError(f"signature.link '{v}' must be a web address (https://...).");
    }
    return v;
}

impl SignatureConfig._known_direction(v) -> any {
    v = (`str(v) if v is not None else "auto").strip().lower() or "auto";
    if v not in ("auto", "rtl", "ltr") {
        raise ValueError("signature.direction must be rtl, ltr or auto.");
    }
    return v;
}

impl EmailChannelConfig._blank_warmup(v) -> any {
    return WarmupConfig() if v is None else v;
}

impl EmailChannelConfig._blank_signature(v) -> any {
    return SignatureConfig() if v is None else v;
}

impl EmailChannelConfig._sends_non_negative(v: builtins.int) -> builtins.int {
    if v < 0 {
        raise ValueError("max_daily_sends must be >= 0");
    }
    return v;
}

impl EmailChannelConfig._per_inbox_cap_range(v: builtins.int) -> builtins.int {
    if not 1 <= v <= 500 {
        raise ValueError("per_inbox_daily_cap must be between 1 and 500");
    }
    return v;
}

impl EmailChannelConfig.cold_daily_cap(today: _date | None = None) -> builtins.int {
    return self.warmup.daily_cap(self.max_daily_sends, today);
}

impl cold_daily_cap(email_config, today: _date | None = None) -> builtins.int {
    warmup: any = getattr(email_config, "warmup", None);
    if isinstance(warmup, WarmupConfig) {
        return warmup.daily_cap(email_config.max_daily_sends, today);
    }
    return email_config.max_daily_sends;
}

impl legacy_sending_held(config) -> builtins.bool {
    email: any = getattr(getattr(config, "channels", None), "email", None);
    return operator.eq(getattr(email, "provider", ""), "instantly")
        and `bool(getattr(email, "require_approval", True));
}

impl sending_notice(config) -> builtins.str {
    if not legacy_sending_held(config) {
        return "";
    }
    return "Instantly sending is held: channels.email.require_approval is true, and Instantly has no approval queue. Campaigns stay as drafts and replies go to a human (dashboard Activity tab). Set require_approval: false to let Instantly send automatically, or switch to gmail, microsoft or smtp to approve each email.";
}

impl normalize_prospect_country(v) -> builtins.str {
    if isinstance(v, `bool) {
        raise ValueError(
            f"prospect_country was read as {v}. YAML turns an unquoted NO or ON into true/false, so quote the code, e.g. prospect_country: \"NO\".",
        );
    }
    v = `str(v or "").strip().upper();
    v = COUNTRY_ALIASES.get(v, v);
    if v and not (len(v) == 2 and v.isascii() and v.isalpha()) {
        raise ValueError(
            f"'{v}' is not a valid prospect_country. Use a two-letter country code such as US or GB, or leave it empty.",
        );
    }
    return v;
}

impl PreclearedConfig._upper_country(v) -> builtins.str {
    v = `str(v or "").strip().upper();
    return COUNTRY_ALIASES.get(v, v);
}

impl PreclearedConfig._valid_source(v) -> builtins.str {
    v = `str(v or "unknown").strip().lower();
    if v not in PRECLEARED_ADDRESS_SOURCES {
        raise ValueError(
            "'"
                + format(v, "")
                + "' is not a valid address_source. Use one of: "
                + format(", ".join(PRECLEARED_ADDRESS_SOURCES), "")
                + ".",
        );
    }
    return v;
}

impl PreclearedConfig._valid_prospect_country(v) -> builtins.str {
    return normalize_prospect_country(v);
}

impl PreclearedConfig._country_when_enabled -> any {
    if self.enabled and self.sender_country not in PRECLEARED_SENDER_COUNTRIES {
        raise ValueError(
            "compliance.precleared.sender_country must be one of "
                + format(", ".join(PRECLEARED_SENDER_COUNTRIES), "")
                + " when the check is enabled.",
        );
    }
    return self;
}

impl _fold_accents(text: builtins.str) -> builtins.str {
    text = text.replace("’", "'").replace("‘", "'");
    return "".join(
        c
        for c in unicodedata.normalize("NFD", text)
        if not (unicodedata.combining(c) and ord(c) < 880),
    );
}

impl ComplianceConfig._blank_is_empty(v) -> any {
    return "" if v is None else v;
}

impl ComplianceConfig._clean_do_not_contact(v) -> any {
    import from sellbird.gate { do_not_contact_entries }
    if v is None {
        return [];
    }
    if isinstance(v, `str) {
        v = [v];
    }
    if not isinstance(v, (`list, `tuple)) {
        raise ValueError("must be a list of email addresses and domains");
    }
    seen: builtins.list[builtins.str] = [];
    for item in v {
        if item is None {
            continue;
        }
        if not isinstance(item, `str) {
            raise ValueError(f"{item!r} is not an email address or a domain");
        }
        for cleaned in do_not_contact_entries(item) {
            if cleaned not in seen {
                seen.append(cleaned);
            }
        }
    }
    return seen;
}

impl ComplianceConfig._recognisable_opt_out(v: builtins.str) -> builtins.str {
    lowered: any;
    v = v.strip();
    lowered = v.lower();
    if not v {
        return v;
    }
    folded: any = _fold_accents(v);
    if `any(bit in lowered for bit in ("http", "www.", "click", "@"))
        or _HEBREW_CLICK_RE.search(v)
        or _FRENCH_CLICK_RE.search(folded)
    {
        raise ValueError(
            "opt_out_line can't contain a link or an email address: cold email allows one link, and opting out must be as simple as replying.",
        );
    }
    if not (
        _SAYS_IT_STOPS_RE.search(v)
        or _SAYS_IT_STOPS_HE_RE.search(v)
        or _SAYS_IT_STOPS_ES_RE.search(v)
        or _SAYS_IT_STOPS_IT_RE.search(v)
        or _SAYS_IT_STOPS_FR_RE.search(folded)
    ) {
        raise ValueError(
            "opt_out_line doesn't tell people they can stop these emails. Say so in any words (\"Not interested? Just let me know and I won't email you again.\"), or set it to \"\" to leave the line off.",
        );
    }
    return v;
}

impl compliance_of(config) -> ComplianceConfig {
    found: any = getattr(config, "compliance", None);
    return found if isinstance(found, ComplianceConfig) else ComplianceConfig();
}

impl compliance_footer_lines(config) -> builtins.list[builtins.str] {
    compliance: any = compliance_of(config);
    return [
        line
        for line in (compliance.postal_address.strip(), compliance.opt_out_line.strip())
        if line
    ];
}

impl compliance_notice(config) -> builtins.str {
    email: any = getattr(getattr(config, "channels", None), "email", None);
    if not getattr(email, "enabled", False) {
        return "";
    }
    compliance: any = compliance_of(config);
    missing: any = [];
    if not compliance.postal_address.strip() {
        missing.append(
            "a postal address (compliance.postal_address: a street address, PO box or virtual mailbox)",
        );
    }
    if not compliance.opt_out_line.strip() {
        missing.append("a way to opt out (compliance.opt_out_line)");
    }
    if not missing {
        return "";
    }
    return "Cold emails are going out without "
        + " or ".join(missing)
        + ". US law (CAN-SPAM) requires both in every cold email. Set them in sellbird.yaml (or sellbird.local.yaml if you trained Sellbird).";
}

impl QuietHoursConfig._valid_time(v: builtins.str) -> builtins.str {
    try {
        _time.fromisoformat(v);
    } except ValueError {
        raise ValueError(f"'{v}' is not a valid time. Use 24h HH:MM format, e.g. '22:00'.");
    }
    return v;
}

impl QuietHoursConfig._valid_timezone(v: builtins.str) -> builtins.str {
    import pytz;

    if v not in pytz.all_timezones_set {
        raise ValueError(
            f"'{v}' is not a valid timezone. Use an IANA name like 'America/New_York'."
        );
    }
    return v;
}

impl UsageConfig._valid_percent(v: builtins.float) -> builtins.float {
    if not 0 < v <= 100 {
        raise ValueError("max_daily_claude_percent must be between 0 and 100");
    }
    return v;
}

impl UsageConfig._valid_interval(v: builtins.int) -> builtins.int {
    if v < 1 {
        raise ValueError("heartbeat_interval_minutes must be at least 1");
    }
    return v;
}

impl BrainConfig._valid_provider(v) -> builtins.str {
    v = `str(v or "claude").strip().lower();
    if v not in BRAIN_PROVIDERS {
        raise ValueError(
            "'"
                + format(v, "")
                + "' is not a supported brain provider. Use one of: "
                + format(", ".join(BRAIN_PROVIDERS), "")
                + ".",
        );
    }
    return v;
}

impl BrainConfig._valid_model(v) -> builtins.str {
    v = `str(v or "").strip();
    if v and not _MODEL_NAME_RE.match(v) {
        raise ValueError(f"'{v}' is not a valid model name.");
    }
    return v;
}

impl BrainConfig._valid_effort(v) -> builtins.str {
    v = `str(v or "").strip().lower();
    if v and v not in CODEX_REASONING_EFFORTS {
        raise ValueError(
            "'"
                + format(v, "")
                + "' is not a valid reasoning effort. Use one of: "
                + format(", ".join(CODEX_REASONING_EFFORTS), "")
                + ".",
        );
    }
    return v;
}

impl WriterConfig._blank_rules(v) -> any {
    if v is None {
        return "";
    }
    return v.strip() if isinstance(v, `str) else v;
}

impl EmailRulesError.__repr__ -> str {
    return (getattr(builtins.super(EmailRulesError, self), "__repr__") as any)();
}

impl EmailRulesError.__eq__(other: any) -> bool {
    return self is other;
}

impl EmailRulesError.__hash__ -> int {
    return id(self);
}

impl load_email_rules(config) -> builtins.str {
    raw: any = `str(getattr(getattr(config, "writer", None), "email_rules", "") or "").strip();
    if not raw {
        return "";
    }
    path: any = Path(raw).expanduser();
    if not path.is_absolute() {
        path = PROJECT_ROOT / path;
    }
    try {
        text: any = read_user_text(path).strip();
    } except FileNotFoundError {
        raise EmailRulesError(f"{raw} doesn't exist") from None;
    } except OSError as e {
        raise EmailRulesError(f"{raw} can't be read ({e})") from None;
    }
    if not text {
        raise EmailRulesError(f"{raw} is empty");
    }
    if len(text) > MAX_EMAIL_RULES_CHARS {
        raise EmailRulesError(
            f"{raw} is {len(text):,} characters; the limit is {MAX_EMAIL_RULES_CHARS:,}"
        );
    }
    return text;
}

impl _format_validation_error(e: ValidationError) -> builtins.str {
    lines: any = [];
    for err in e.errors() {
        loc: any = ".".join(`str(p) for p in err["loc"]) or "(root)";
        lines.append("  - " + format(loc, "") + ": " + format(err["msg"], ""));
    }
    return "\n".join(lines);
}

impl use_config(config: SellbirdConfig) -> Generator[any, any, any] {
    token: any = _CURRENT_CONFIG.set(config);
    try {
        yield config;
    } finally {
        _CURRENT_CONFIG.reset(token);
    }
}

impl current_config -> "SellbirdConfig | None" {
    return _CURRENT_CONFIG.get();
}

impl load_config(config_path: builtins.str | None = None) -> SellbirdConfig {
    if config_path is None {
        given: any = _CURRENT_CONFIG.get();
        if given is not None {
            return given;
        }
        import from sellbird.workspace_home { current_home }
        if current_home().hosted {
            raise ConfigFileNotFoundError("This workspace's settings weren't loaded.");
        }
        config_path = _find_config_file();
    }

    try {
        data: any = yaml.safe_load(read_user_text(config_path));
    } except FileNotFoundError {
        raise ConfigFileNotFoundError(
            f"Config file not found: {config_path}. Create one from sellbird.yaml.example or run 'sellbird setup'.",
        );
    } except yaml.YAMLError as e {
        raise ConfigError(f"Invalid YAML in {config_path}:\n  {e}");
    } except OSError as e {
        raise ConfigError(f"Could not read {config_path}: {e}");
    }

    if data is None {
        raise ConfigError(f"{config_path} is empty. Run 'sellbird setup' to configure Sellbird.");
    }
    if not isinstance(data, `dict) {
        raise ConfigError(
            f"{config_path} must contain a YAML mapping (key: value pairs), got {`type(data).__name__}.",
        );
    }

    try {
        config: any = SellbirdConfig(**data);
        config._source_path = `str(config_path);
        return config;
    } except ValidationError as e {
        logger.error(
            f"Invalid configuration in {config_path}:\n{_format_validation_error(e)}\nFix the fields above or re-run 'sellbird setup'.",
        );
        raise;
    }
}

impl load_brain_config(config_path: builtins.str | None = None) -> BrainConfig {
    if config_path is None {
        try {
            config_path = _find_config_file();
        } except ConfigFileNotFoundError {
            return BrainConfig();
        }
    }
    try {
        data: any = yaml.safe_load(read_user_text(config_path));
    } except FileNotFoundError {
        return BrainConfig();
    } except (yaml.YAMLError, OSError) as e {
        raise ConfigError(f"Could not read the brain settings in {config_path}: {e}");
    }
    section: any = data.get("brain") if isinstance(data, `dict) else None;
    if section is None {
        return BrainConfig();
    }
    if not isinstance(section, `dict) {
        raise ConfigError(f"'brain' in {config_path} must be a mapping.");
    }
    try {
        return BrainConfig(**section);
    } except ValidationError as e {
        raise ConfigError(
            f"Invalid brain settings in {config_path}:\n{_format_validation_error(e)}"
        );
    }
}

impl load_env -> EnvConfig {
    load_dotenv();
    env: any = EnvConfig(
        instantly_api_key=os.getenv("INSTANTLY_API_KEY", "").strip(),
        dataforseo_login=os.getenv("DATAFORSEO_LOGIN", "").strip(),
        dataforseo_password=os.getenv("DATAFORSEO_PASSWORD", "").strip(),
        dataforseo_sandbox=os.getenv("DATAFORSEO_SANDBOX", "").strip(),
        linkedin_email=os.getenv("LINKEDIN_EMAIL", "").strip(),
        linkedin_password=os.getenv("LINKEDIN_PASSWORD", "").strip(),
        hunter_api_key=os.getenv("HUNTER_API_KEY", "").strip(),
        serper_api_key=os.getenv("SERPER_API_KEY", "").strip(),
        scavio_api_key=os.getenv("SCAVIO_API_KEY", "").strip(),
        tinyfish_api_key=os.getenv("TINYFISH_API_KEY", "").strip(),
        reoon_api_key=os.getenv("REOON_API_KEY", "").strip(),
        zerobounce_api_key=os.getenv("ZEROBOUNCE_API_KEY", "").strip(),
        gmail_client_id=os.getenv("GMAIL_CLIENT_ID", "").strip(),
        gmail_client_secret=os.getenv("GMAIL_CLIENT_SECRET", "").strip(),
        smtp_host=os.getenv("SMTP_HOST", "").strip(),
        smtp_port=`int(os.getenv("SMTP_PORT", "587").strip() or 587),
        smtp_username=os.getenv("SMTP_USERNAME", "").strip(),
        smtp_password=os.getenv("SMTP_PASSWORD", "").strip(),
        imap_host=os.getenv("IMAP_HOST", "").strip(),
        imap_port=`int(os.getenv("IMAP_PORT", "993").strip() or 993),
        imap_username=os.getenv("IMAP_USERNAME", "").strip(),
        imap_password=os.getenv("IMAP_PASSWORD", "").strip(),
        m365_client_id=os.getenv("M365_CLIENT_ID", "").strip(),
        m365_tenant_id=os.getenv("M365_TENANT_ID", "").strip(),
        precleared_api_key=os.getenv("PRECLEARED_API_KEY", "").strip(),
    );
    return env;
}

impl _email_section(data) -> any {
    channels: any = data.get("channels") if isinstance(data, `dict) else None;
    email: any = channels.get("email") if isinstance(channels, `dict) else None;
    return email if isinstance(email, `dict) else None;
}

impl _with_approval_line(raw: builtins.str, word: builtins.str) -> builtins.list[builtins.str] {
    m: any;
    out: any = [
        raw[:m.start("val")] + word + raw[m.end("val"):]
        for m in _APPROVAL_LINE_RE.finditer(raw)
    ];
    for m in _EMAIL_KEY_RE.finditer(raw) {
        child: any = m.group("ind") + "  ";
        for line in raw[m.end():].split("\n")[1:] {
            if not line.strip() or line.lstrip().startswith("#") {
                continue;
            }
            indent: any = line[:len(line) - len(line.lstrip(" \t"))];
            if len(indent) > len(m.group("ind")) {
                child = indent;
            }
            break;
        }
        out.append(raw[:m.end()] + f"\n{child}require_approval: {word}" + raw[m.end():]);
    }
    return out;
}

impl set_require_approval(value: builtins.bool, path=None) -> Path {
    import copy;
    import shutil;
    path = Path(path or _find_config_file());
    target: any = path.resolve();
    data_bytes: any = target.read_bytes();
    bom: any = data_bytes.startswith(b"\xef\xbb\xbf");
    try {
        raw: any = data_bytes.decode("utf-8-sig").replace("\r\n", "\n");
    } except UnicodeDecodeError {
        raise ConfigError(
            f"{path.name} isn't UTF-8, so it isn't rewritten. Set channels.email.require_approval there by hand.",
        );
    }
    try {
        data: any = yaml.safe_load(raw);
    } except yaml.YAMLError as e {
        raise ConfigError(f"Invalid YAML in {path.name}: {e}");
    }
    if _email_section(data) is None {
        raise ConfigError(
            f"{path.name} has no channels.email section. Set channels.email.require_approval there by hand.",
        );
    }
    expected: any = copy.deepcopy(data);
    _email_section(expected)["require_approval"] = `bool(value);
    word: any = "true" if value else "false";
    new: any;
    for new in _with_approval_line(raw, word) {
        try {
            if yaml.safe_load(new) != expected {
                continue;
            }
        } except yaml.YAMLError {
            continue;
        }
        SellbirdConfig(**expected);
        if b"\r\n" in data_bytes {
            new = new.replace("\n", "\r\n");
        }
        tmp: any = target.with_name(target.name + ".tmp");
        try {
            tmp.write_bytes((b"\xef\xbb\xbf" if bom else b"") + new.encode("utf-8"));
            shutil.copymode(target, tmp);
            os.replace(tmp, target);
        } finally {
            tmp.unlink(missing_ok=True);
        }
        _mode_cache.pop(`str(target), None);
        return path;
    }
    raise ConfigError(
        f"Couldn't change require_approval in {path.name} safely. Set channels.email.require_approval: {word} there by hand.",
    );
}

impl refresh_sending_mode(config, path=None) -> builtins.bool {
    path = path or getattr(config, "_source_path", None);
    if not path {
        return False;
    }
    try {
        target: any = Path(path).resolve();
        st: any = target.stat();
        stamp: any = (st.st_mtime_ns, st.st_size, st.st_ino, st.st_ctime_ns);
        cached: any = _mode_cache.get(`str(target));
        if cached and cached[0] == stamp {
            value: any = cached[1];
        } else {
            email: any = _email_section(yaml.safe_load(read_user_text(target)));
            value = email.get("require_approval", True) if email is not None else None;
            try {
                value = TypeAdapter(bool).validate_python(value);
            } except ValidationError {
                value = None;
            }
            _mode_cache[`str(target)] = (stamp, value);
        }
    } except Exception {
        return False;
    }
    if not isinstance(value, `bool) or value == config.channels.email.require_approval {
        return False;
    }
    config.channels.email.require_approval = value;
    return True;
}

impl live_do_not_contact(config) -> builtins.list[builtins.str] {
    compliance: any = compliance_of(config);
    path: any = getattr(config, "_source_path", None);
    if not path {
        return compliance.do_not_contact;
    }
    try {
        target: any = Path(path).resolve();
        st: any = target.stat();
        stamp: any = (st.st_mtime_ns, st.st_size, st.st_ino, st.st_ctime_ns);
        cached: any = _dnc_cache.get(`str(target));
        if cached and cached[0] == stamp {
            value: any = cached[1];
        } else {
            value = None;
            try {
                value = do_not_contact_from_file(target);
            } except Exception as e {
                logger.warning(
                    f"compliance.do_not_contact in {target.name} couldn't be read ({e}); still using the last good list.",
                );
            }
            _dnc_cache[`str(target)] = (stamp, value);
        }
    } except OSError {
        return compliance.do_not_contact;
    }
    if value is None {
        return compliance.do_not_contact;
    }
    if value != compliance.do_not_contact
        and isinstance(getattr(config, "compliance", None), ComplianceConfig)
    {
        config.compliance.do_not_contact = value;
    }
    return value;
}

impl do_not_contact_from_file(path=None) -> builtins.list[builtins.str] {
    data: any = yaml.safe_load(read_user_text(path or _find_config_file()));
    section: any = data.get("compliance") if isinstance(data, `dict) else None;
    raw: any = section.get("do_not_contact") if isinstance(section, `dict) else None;
    return ComplianceConfig(do_not_contact=raw).do_not_contact;
}

impl _find_config_file -> builtins.str {
    import from sellbird.workspace_home { current_home }
    home_config: any = current_home().config_file;
    if home_config is not None {
        if not home_config.exists() {
            raise ConfigFileNotFoundError(
                f"sellbird.yaml not found at {home_config}. Create one from sellbird.yaml.example or run 'sellbird setup'.",
            );
        }
        return `str(home_config);
    }
    import from sellbird.paths { HOME_ENV, is_checkout }
    if is_checkout(PROJECT_ROOT) and not os.environ.get(HOME_ENV, "").strip() {
        candidates: any = [
            Path.cwd() / "sellbird.local.yaml",
            PROJECT_ROOT / "sellbird.local.yaml",
            Path.cwd() / "sellbird.yaml",
            Path.cwd().parent / "sellbird.yaml",
            PROJECT_ROOT / "sellbird.yaml",
        ];
    } else {
        candidates = [PROJECT_ROOT / "sellbird.local.yaml", PROJECT_ROOT / "sellbird.yaml"];
    }
    for path in candidates {
        if path.exists() {
            return `str(path);
        }
    }
    raise ConfigFileNotFoundError(
        "sellbird.yaml not found in "
            + ", ".join(`str(p.parent) for p in candidates)
            + ". Create one from sellbird.yaml.example or run 'sellbird setup'.",
    );
}
