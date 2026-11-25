impl _need(ok: any, msg: str, v: any) -> any {
    if not ok {
        raise ValueError(msg);
    }
    return v;
}

impl _one_of(v: str, allowed: any, what: str) -> str {
    return _need(v in allowed, f"'{v}' is not {what}. Use one of: {', '.join(allowed)}.", v);
}

impl _parses(kind: any, v: str) -> bool {
    try {
        kind.fromisoformat(v);
    } except ValueError {
        return False;
    }
    return True;
}

impl WarmupConfig._blank_is_default(v: any, info: any) -> any {
    if v is None {
        return cls.model_fields[info.field_name].default;
    }
    if info.field_name == "start_date" and isinstance(v, _date) {
        return (v.date() if isinstance(v, _datetime) else v).isoformat();
    }
    day: any = v.strip() if info.field_name == "start_date" and isinstance(v, str) else "";
    return day[:10] if len(day) > 10 and day[10] in " T" else v;
}

impl WarmupConfig._valid(v: any, info: any) -> any {
    if info.field_name != "start_date" {
        return _need(v >= 0, "warmup values must be >= 0", v);
    }
    v = (v or "").strip();
    return _need(not v or _parses(_date, v), f"warmup.start_date '{v}' must be YYYY-MM-DD.", v);
}

impl WarmupConfig.days_in(today: _date | None = None) -> int | None {
    if not self.start_date {
        return None;
    }
    return ((today or _date.today()) - _date.fromisoformat(self.start_date)).days;
}

impl WarmupConfig.daily_cap(ceiling: int, today: _date | None = None) -> int {
    days: any = self.days_in(today);
    if days is None {
        return ceiling;
    }
    return 0
        if days < self.min_days
        else min(ceiling, self.start_sends + (days - self.min_days) * self.daily_increase);
}

impl SendWindowConfig._valid_clock(v: any, info: any) -> any {
    if v is None {
        return cls.model_fields[info.field_name].default;
    }
    if isinstance(v, int) and not isinstance(v, bool) and v >= 0 and v < 24 * 60 {
        v = f"{v // 60:02d}:{v % 60:02d}";
    }
    v = str(v).strip();
    return _need(
        _parses(_time, v), f"send_window time '{v}' is not valid. Use 24h HH:MM, e.g. '08:00'.", v
    );
}

impl SendWindowConfig._start_before_end -> any {
    return _need(
        _time.fromisoformat(self.start) < _time.fromisoformat(self.end),
        "send_window.start must be earlier than send_window.end (a send window can't run past midnight).",
        self,
    );
}

impl SignatureConfig._blank_is_empty(v: any, info: any) -> any {
    if info.field_name != "direction" {
        return "" if v is None else str(v).strip();
    }
    v = (str(v) if v is not None else "auto").strip().lower() or "auto";
    return _need(v in ("auto", "rtl", "ltr"), "signature.direction must be rtl, ltr or auto.", v);
}

impl SignatureConfig._valid(v: any, info: any) -> any {
    if info.field_name == "width" {
        return _need(v >= 16 and v <= 600, "signature.width must be between 16 and 600 pixels.", v);
    }
    return _need(
        not v or re.match("https?://[^\\s\\\"<>]+$", v),
        f"signature.link '{v}' must be a web address (https://...).",
        v,
    );
}

impl EmailChannelConfig._blank_section(v: any, info: any) -> any {
    return (WarmupConfig if info.field_name == "warmup" else SignatureConfig)() if v is None else v;
}

impl EmailChannelConfig._valid_caps(v: any, info: any) -> any {
    if info.field_name == "max_daily_sends" {
        return _need(v >= 0, "max_daily_sends must be >= 0", v);
    }
    return _need(v >= 1 and v <= 500, "per_inbox_daily_cap must be between 1 and 500", v);
}

impl EmailChannelConfig.cold_daily_cap(today: _date | None = None) -> int {
    return self.warmup.daily_cap(self.max_daily_sends, today);
}

impl PreclearedConfig._clean(v: any, info: any) -> str {
    if info.field_name == "prospect_country" {
        return normalize_prospect_country(v);
    }
    if info.field_name == "address_source" {
        return _one_of(
            str(v or "unknown").strip().lower(),
            PRECLEARED_ADDRESS_SOURCES,
            "a valid address_source",
        );
    }
    v = str(v or "").strip().upper();
    return COUNTRY_ALIASES.get(v, v);
}

impl PreclearedConfig._country_when_enabled -> any {
    return _need(
        not self.enabled or self.sender_country in PRECLEARED_SENDER_COUNTRIES,
        f"compliance.precleared.sender_country must be one of {', '.join(PRECLEARED_SENDER_COUNTRIES)} when the check is enabled.",
        self,
    );
}

impl ComplianceConfig._blank_is_empty(v: any, info: any) -> any {
    import from sellbird.gate { do_not_contact_entries }
    if info.field_name != "do_not_contact" {
        return "" if v is None else v;
    }
    if v is None {
        return [];
    }
    items: any = [v] if isinstance(v, str) else v;
    _need(isinstance(items, (list, tuple)), "must be a list of email addresses and domains", v);
    seen: list[str] = [];
    for item in items {
        _need(
            item is None or isinstance(item, str),
            f"{item!r} is not an email address or a domain",
            v,
        );
        for cleaned in (do_not_contact_entries(item) if item is not None else []) {
            if cleaned not in seen {
                seen.append(cleaned);
            }
        }
    }
    return seen;
}

impl ComplianceConfig._recognisable_opt_out(v: str) -> str {
    v = v.strip();
    folded: any = _fold_accents(v);
    if v
        and (
            any(bit in v.lower() for bit in ("http", "www.", "click", "@"))
            or _HEBREW_CLICK_RE.search(v)
            or _FRENCH_CLICK_RE.search(folded)
        )
    {
        raise ValueError(
            "opt_out_line can't contain a link or an email address: cold email allows one link, and opting out must be as simple as replying.",
        );
    }
    return _need(
        not v or _SAYS_IT_STOPS_RE.search(v) or _SAYS_IT_STOPS_FR_RE.search(folded),
        "opt_out_line doesn't tell people they can stop these emails. Say so in any words (\"Not interested? Just let me know and I won't email you again.\"), or set it to \"\" to leave the line off.",
        v,
    );
}

impl QuietHoursConfig._valid(v: str, info: any) -> str {
    import pytz;
    if info.field_name == "timezone" {
        return _need(
            v in pytz.all_timezones_set,
            f"'{v}' is not a valid timezone. Use an IANA name like 'America/New_York'.",
            v,
        );
    }
    return _need(
        _parses(_time, v), f"'{v}' is not a valid time. Use 24h HH:MM format, e.g. '22:00'.", v
    );
}

impl UsageConfig._valid(v: any, info: any) -> any {
    if info.field_name == "heartbeat_interval_minutes" {
        return _need(v >= 1, "heartbeat_interval_minutes must be at least 1", v);
    }
    return _need(v > 0 and v <= 100, "max_daily_claude_percent must be between 0 and 100", v);
}

impl BrainConfig._valid(v: any, info: any) -> str {
    if info.field_name == "provider" {
        return _one_of(
            str(v or "claude").strip().lower(), BRAIN_PROVIDERS, "a supported brain provider"
        );
    }
    if info.field_name == "model" {
        v = str(v or "").strip();
        return _need(not v or _MODEL_NAME_RE.match(v), f"'{v}' is not a valid model name.", v);
    }
    v = str(v or "").strip().lower();
    return _one_of(v, CODEX_REASONING_EFFORTS, "a valid reasoning effort") if v else v;
}

impl WriterConfig._blank_rules(v: any) -> any {
    return "" if v is None else v.strip() if isinstance(v, str) else v;
}

impl _email_of(config: any) -> any {
    return getattr(getattr(config, "channels", None), "email", None);
}

impl send_window_of(config: any) -> any {
    window: any = getattr(_email_of(config), "send_window", None);
    return window if isinstance(window, SendWindowConfig) else None;
}

impl operator_timezone(config: any) -> str {
    return getattr(getattr(getattr(config, "usage", None), "quiet_hours", None), "timezone", "")
        or "UTC";
}

impl cold_daily_cap(email_config: any, today: _date | None = None) -> int {
    warmup: any = getattr(email_config, "warmup", None);
    return warmup.daily_cap(email_config.max_daily_sends, today)
        if isinstance(warmup, WarmupConfig)
        else email_config.max_daily_sends;
}

impl legacy_sending_held(config: any) -> bool {
    email: any = _email_of(config);
    return operator.eq(getattr(email, "provider", ""), "instantly")
        and bool(getattr(email, "require_approval", True));
}

impl sending_notice(config: any) -> str {
    return "Instantly sending is held: channels.email.require_approval is true, and Instantly has no approval queue. Campaigns stay as drafts and replies go to a human (dashboard Activity tab). Set require_approval: false to let Instantly send automatically, or switch to gmail, microsoft or smtp to approve each email."
        if legacy_sending_held(config)
        else "";
}

impl normalize_prospect_country(v: any) -> str {
    if isinstance(v, bool) {
        raise ValueError(
            f"prospect_country was read as {v}. YAML turns an unquoted NO or ON into true/false, so quote the code, e.g. prospect_country: \"NO\".",
        );
    }
    v = str(v or "").strip().upper();
    v = COUNTRY_ALIASES.get(v, v);
    return _need(
        not v or (len(v) == 2 and v.isascii() and v.isalpha()),
        f"'{v}' is not a valid prospect_country. Use a two-letter country code such as US or GB, or leave it empty.",
        v,
    );
}

impl _fold_accents(text: str) -> str {
    text = text.replace("’", "'").replace("‘", "'");
    return "".join([
        c
        for c in unicodedata.normalize("NFD", text)
        if not (unicodedata.combining(c) and ord(c) < 880)
    ]);
}

impl compliance_of(config: any) -> ComplianceConfig {
    found: any = getattr(config, "compliance", None);
    return found if isinstance(found, ComplianceConfig) else ComplianceConfig();
}

impl compliance_footer_lines(config: any) -> list[str] {
    compliance: any = compliance_of(config);
    return [
        line
        for line in (compliance.postal_address.strip(), compliance.opt_out_line.strip())
        if line
    ];
}

impl compliance_notice(config: any) -> str {
    if not getattr(_email_of(config), "enabled", False) {
        return "";
    }
    compliance: any = compliance_of(config);
    missing: list[str] = [
        "a postal address (compliance.postal_address: a street address, PO box or virtual mailbox)",
    ]
        if not compliance.postal_address.strip()
        else [];
    if not compliance.opt_out_line.strip() {
        missing.append("a way to opt out (compliance.opt_out_line)");
    }
    return "Cold emails are going out without "
        + " or ".join(missing)
        + ". US law (CAN-SPAM) requires both in every cold email. Set them in sellbird.yaml (or sellbird.local.yaml if you trained Sellbird)."
        if missing
        else "";
}

impl load_email_rules(config: any) -> str {
    raw: any = str(getattr(getattr(config, "writer", None), "email_rules", "") or "").strip();
    if not raw {
        return "";
    }
    path: any = Path(raw).expanduser();
    try {
        text: any = read_user_text(path if path.is_absolute() else PROJECT_ROOT / path).strip();
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

impl _format_validation_error(e: ValidationError) -> str {
    lines: list[str] = [];
    for err in e.errors() {
        lines.append(f"  - {'.'.join([str(p) for p in err['loc']]) or '(root)'}: {err['msg']}");
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

impl current_config -> any {
    return _CURRENT_CONFIG.get();
}

impl load_config(config_path: str | None = None) -> SellbirdConfig {
    import from sellbird.workspace_home { current_home }
    if config_path is None {
        given: any = _CURRENT_CONFIG.get();
        if given is not None {
            return given;
        }
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
    if not isinstance(data, dict) {
        raise ConfigError(
            f"{config_path} must contain a YAML mapping (key: value pairs), got {type(data).__name__}.",
        );
    }
    try {
        config: any = SellbirdConfig(**data);
    } except ValidationError as e {
        logger.error(
            f"Invalid configuration in {config_path}:\n{_format_validation_error(e)}\nFix the fields above or re-run 'sellbird setup'.",
        );
        raise;
    }
    config._source_path = str(config_path);
    return config;
}

impl load_brain_config(config_path: str | None = None) -> BrainConfig {
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
    section: any = data.get("brain") if isinstance(data, dict) else None;
    if section is None {
        return BrainConfig();
    }
    if not isinstance(section, dict) {
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

impl load_env -> any {
    load_dotenv();
    return EnvConfig(
        **{
            name: os.getenv(name.upper(), str(f.default)).strip() or f.default
            for (name, f) in EnvConfig.model_fields.items()
        },
    );
}

impl _email_section(data: any) -> any {
    channels: any = data.get("channels") if isinstance(data, dict) else None;
    email: any = channels.get("email") if isinstance(channels, dict) else None;
    return email if isinstance(email, dict) else None;
}

impl _with_approval_line(raw: str, word: str) -> list[str] {
    m: any;
    out: any = [
        raw[:m.start("val")] + word + raw[m.end("val"):]
        for m in _APPROVAL_LINE_RE.finditer(raw)
    ];
    for m in _EMAIL_KEY_RE.finditer(raw) {
        child: any = m.group("ind") + "  ";
        for line in raw[m.end():].split("\n")[1:] {
            if line.strip() and not line.lstrip().startswith("#") {
                indent: any = line[:len(line) - len(line.lstrip(" \t"))];
                child = indent if len(indent) > len(m.group("ind")) else child;
                break;
            }
        }
        out.append(raw[:m.end()] + f"\n{child}require_approval: {word}" + raw[m.end():]);
    }
    return out;
}

impl set_require_approval(value: bool, path: any = None) -> Path {
    path = Path(path or _find_config_file());
    target: any = path.resolve();
    data_bytes: any = target.read_bytes();
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
    _email_section(expected)["require_approval"] = bool(value);
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
        new = new.replace("\n", "\r\n") if b"\r\n" in data_bytes else new;
        tmp: any = target.with_name(target.name + ".tmp");
        try {
            tmp.write_bytes(
                (b"\xef\xbb\xbf" if data_bytes.startswith(b"\xef\xbb\xbf") else b"")
                    + new.encode("utf-8"),
            );
            shutil.copymode(target, tmp);
            os.replace(tmp, target);
        } finally {
            tmp.unlink(missing_ok=True);
        }
        _mode_cache.pop(str(target), None);
        return path;
    }
    raise ConfigError(
        f"Couldn't change require_approval in {path.name} safely. Set channels.email.require_approval: {word} there by hand.",
    );
}

impl _reread(cache: dict[str, any], path: any, read: any) -> any {
    target: any = Path(path).resolve();
    st: any = target.stat();
    stamp: any = (st.st_mtime_ns, st.st_size, st.st_ino, st.st_ctime_ns);
    cached: any = cache.get(str(target));
    if cached and cached[0] == stamp {
        return cached[1];
    }
    value: any = read(target);
    cache[str(target)] = (stamp, value);
    return value;
}

impl _read_mode(target: any) -> any {
    email: any = _email_section(yaml.safe_load(read_user_text(target)));
    try {
        return TypeAdapter(bool).validate_python(
            email.get("require_approval", True) if email is not None else None
        );
    } except ValidationError {
        return None;
    }
}

impl _read_dnc(target: any) -> any {
    try {
        return do_not_contact_from_file(target);
    } except Exception as e {
        logger.warning(
            f"compliance.do_not_contact in {target.name} couldn't be read ({e}); still using the last good list.",
        );
        return None;
    }
}

impl refresh_sending_mode(config: any, path: any = None) -> bool {
    path = path or getattr(config, "_source_path", None);
    if not path {
        return False;
    }
    try {
        value: any = _reread(_mode_cache, path, _read_mode);
    } except Exception {
        return False;
    }
    if not isinstance(value, bool) or value == config.channels.email.require_approval {
        return False;
    }
    config.channels.email.require_approval = value;
    return True;
}

impl live_do_not_contact(config: any) -> list[str] {
    compliance: any = compliance_of(config);
    path: any = getattr(config, "_source_path", None);
    try {
        value: any = _reread(_dnc_cache, path, _read_dnc) if path else None;
    } except OSError {
        value = None;
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

impl do_not_contact_from_file(path: any = None) -> list[str] {
    data: any = yaml.safe_load(read_user_text(path or _find_config_file()));
    section: any = data.get("compliance") if isinstance(data, dict) else None;
    return ComplianceConfig(
        do_not_contact=section.get("do_not_contact") if isinstance(section, dict) else None
    ).do_not_contact;
}

impl _find_config_file -> str {
    import from sellbird.workspace_home { current_home }
    import from sellbird.paths { HOME_ENV, is_checkout }
    home_config: any = current_home().config_file;
    if home_config is not None {
        if not home_config.exists() {
            raise ConfigFileNotFoundError(
                f"sellbird.yaml not found at {home_config}. Create one from sellbird.yaml.example or run 'sellbird setup'.",
            );
        }
        return str(home_config);
    }
    (cwd, top) = (Path.cwd(), PROJECT_ROOT);
    candidates: any = [top / "sellbird.local.yaml", top / "sellbird.yaml"];
    if is_checkout(top) and not os.environ.get(HOME_ENV, "").strip() {
        candidates = [
            cwd / "sellbird.local.yaml",
            top / "sellbird.local.yaml",
            cwd / "sellbird.yaml",
            cwd.parent / "sellbird.yaml",
            top / "sellbird.yaml",
        ];
    }
    for path in candidates {
        if path.exists() {
            return str(path);
        }
    }
    raise ConfigFileNotFoundError(
        "sellbird.yaml not found in "
            + ", ".join([str(p.parent) for p in candidates])
            + ". Create one from sellbird.yaml.example or run 'sellbird setup'.",
    );
}
