impl HunterUnavailable.__repr__ -> str {
    return (getattr(builtins.super(HunterUnavailable, self), "__repr__") as any)();
}

impl HunterUnavailable.__eq__(other: any) -> bool {
    return self is other;
}

impl HunterUnavailable.__hash__ -> int {
    return id(self);
}

impl _clean_domain(domain: builtins.str) -> builtins.str {
    domain = (domain or "").strip().lower();
    domain = re.sub("^https?://", "", domain);
    domain = domain.split("/")[0].split("?")[0];
    if domain.startswith("www.") {
        domain = domain[4:];
    }
    return domain;
}

impl _clean_name_part(value: builtins.str) -> builtins.str {
    return re.sub("[^a-z]", "", (value or "").lower());
}

impl build_email(
    pattern: builtins.str, first: builtins.str, last: builtins.str, domain: builtins.str
) -> builtins.str {
    first = _clean_name_part(first);
    last = _clean_name_part(last);
    domain = _clean_domain(domain);
    if not first or not last or not domain {
        return "";
    }
    builder: any = PATTERN_BUILDERS.get(pattern);
    if not builder {
        return "";
    }
    try {
        local: any = builder(first, last);
    } except IndexError {
        return "";
    }
    return f"{local}@{domain}" if local else "";
}

impl generate_patterns(
    first_name: builtins.str, last_name: builtins.str, domain: builtins.str
) -> builtins.list[builtins.str] {
    out: any = [];
    for pattern in PATTERN_BUILDERS {
        email: any = build_email(pattern, first_name, last_name, domain);
        if email {
            out.append(email);
        }
    }
    return `list(dict.fromkeys(out));
}

impl classify_mx(mx_host: builtins.str) -> builtins.str {
    h: any;
    if not mx_host {
        return "none";
    }
    h = mx_host.lower();
    if "google" in h or "googlemail" in h or "aspmx.l" in h {
        return "google";
    }
    if "outlook" in h or "protection.outlook" in h or "microsoft" in h {
        return "microsoft";
    }
    if `any(
        g in h
        for g in (
            "pphosted",
            "mimecast",
            "barracuda",
            "proofpoint",
            "messagelabs",
            "cisco",
            "fortinet",
            "trendmicro",
        ),
    ) {
        return "gateway";
    }
    return "other";
}

impl get_mx_host(domain: builtins.str) -> Optional[builtins.str] {
    domain = _clean_domain(domain);
    if not domain {
        return None;
    }
    if domain in _mx_cache {
        return _mx_cache[domain];
    }
    try {
        loop: any = asyncio.get_event_loop();
        answers: any = await loop.run_in_executor(
            None, lambda -> any { dns.resolver.resolve(domain, "MX") }
        );
        records: any = sorted(answers, key=lambda (x) -> any { x.preference });
        mx_host: any = `str(records[0].exchange).rstrip(".") if records else None;
        _mx_cache[domain] = mx_host or None;
        return _mx_cache[domain];
    } except Exception as e {
        logger.debug(f"MX lookup failed for {domain}: {e}");
        _mx_cache[domain] = None;
        return None;
    }
}

impl infer_pattern_from_email(
    email: builtins.str, first: builtins.str, last: builtins.str
) -> Optional[builtins.str] {
    email = (email or "").strip().lower();
    if "@" not in email {
        return None;
    }
    local: any = email.split("@", 1)[0];
    first = _clean_name_part(first);
    last = _clean_name_part(last);
    if not first or not last {
        return None;
    }
    for (pattern, builder) in PATTERN_BUILDERS.items() {
        try {
            if builder(first, last) == local {
                return pattern;
            }
        } except IndexError {
            continue;
        }
    }
    return None;
}

impl pattern_from_local(
    local: builtins.str
) -> Optional[builtins.tuple[builtins.str, builtins.float]] {
    local = (local or "").strip().lower();
    if not local or local in ROLE_LOCALS or `any(ch.isdigit() for ch in local) {
        return None;
    }
    m: any = re.fullmatch("([a-z]+)([._-])([a-z]+)", local);
    if m {
        first: any;
        sep: any;
        last: any;
        (first, sep, last) = m.groups() as any;
        if sep == "." and len(first) == 1 and len(last) >= 2 {
            return ("{fi}.{l}", 0.6);
        }
        if len(first) >= 2
            and len(last) >= 2
            and first not in ROLE_LOCALS
            and last not in ROLE_LOCALS
        {
            return ({".": "{f}.{l}", "_": "{f}_{l}", "-": "{f}-{l}"}[sep], 0.6);
        }
        return None;
    }
    return None;
}

impl _disambiguate(
    local: builtins.str, people
) -> Optional[builtins.tuple[builtins.str, builtins.float]] {
    if not re.fullmatch("[a-z]{3,20}", local or "") {
        return None;
    }
    lasts: any = {_clean_name_part(last) for (_, last) in people or []} - {""};
    firsts: any = {_clean_name_part(first) for (first, _) in people or []} - {""};
    if local in firsts {
        return ("{f}", 0.6);
    }
    if `any(operator.ge(len(last), 3) and operator.eq(local[1:], last) for last in lasts) {
        return ("{fi}{l}", 0.6);
    }
    if local in lasts {
        return ("{l}", 0.55);
    }
    return None;
}

impl site_email_evidence(
    addresses: builtins.list[builtins.str],
    people: builtins.list[builtins.tuple[builtins.str, builtins.str]],
    domain: builtins.str,
) -> builtins.tuple[builtins.list[builtins.tuple[builtins.str, builtins.str, builtins.str]], builtins.str, builtins.float] {
    domain = _clean_domain(domain);
    known: builtins.list[builtins.tuple[builtins.str, builtins.str, builtins.str]] = [];
    tied_votes: builtins.dict[builtins.str, builtins.int] = {};
    loose_votes: builtins.dict[builtins.str, builtins.int] = {};
    addr: any;
    for addr in addresses or [] {
        addr = (addr or "").strip().lower();
        local: any;
        _: any;
        adomain: any;
        (local, _, adomain) = addr.partition("@") as any;
        if adomain != domain or local in ROLE_LOCALS {
            continue;
        }
        owners: any = [];
        first: any;
        last: any;
        for (first, last) in people or [] {
            pattern: any = infer_pattern_from_email(addr, first, last);
            if pattern {
                owners.append((first, last, pattern));
            }
        }
        if len(owners) == 1 {
            (first, last, pattern) = owners[0] as any;
            known.append((addr, first, last));
            tied_votes[pattern] = tied_votes.get(pattern, 0) + 1;
            continue;
        }
        if owners {
            patterns: any = {o[2] for o in owners};
            if len(patterns) == 1 {
                loose_votes[owners[0][2]] = loose_votes.get(owners[0][2], 0) + 2;
            }
            continue;
        }
        guess: any = pattern_from_local(local) or _disambiguate(local, people);
        if guess {
            loose_votes[guess[0]] = loose_votes.get(guess[0], 0) + 1;
        }
    }
    if tied_votes {
        pattern = max(tied_votes, key=tied_votes.get);
        return (known, pattern, 0.95 if tied_votes[pattern] >= 2 else 0.9);
    }
    if loose_votes {
        pattern = max(loose_votes, key=loose_votes.get);
        n: any = loose_votes[pattern];
        return (known, pattern, min(0.55 + 0.05 * n, 0.7));
    }
    return (known, "", 0.0);
}

impl _hunter_headers(api_key: builtins.str) -> builtins.dict {
    return {"X-API-KEY": api_key};
}

impl _redact(error, api_key: builtins.str) -> builtins.str {
    text: any = `str(error);
    if api_key {
        text = text.replace(api_key, "***");
    }
    return text;
}

impl _hunter_domain_pattern(
    domain: builtins.str, api_key: builtins.str
) -> Optional[builtins.tuple[builtins.str, builtins.float]] {
    try {
        client: any;
        async with httpx.AsyncClient(timeout=API_TIMEOUT) as client {
            resp: any = await client.get(
                "https://api.hunter.io/v2/domain-search",
                params={"domain": domain, "limit": 1},
                headers=_hunter_headers(api_key),
            );
        }
    } except httpx.HTTPError as e {
        logger.debug(f"Hunter domain-search failed for {domain}: {_redact(e, api_key)}");
        raise HunterUnavailable(_redact(e, api_key)) from e;
    }
    if resp.status_code == 429 or resp.status_code >= 500 {
        raise HunterUnavailable(f"HTTP {resp.status_code}");
    }
    if resp.status_code != 200 {
        return None;
    }
    try {
        data: any = (resp.json() or {}).get("data") or {};
    } except ValueError {
        raise HunterUnavailable("bad JSON");
    }

    hunter_pattern: any = data.get("pattern") or "";
    translated: any = _translate_hunter_pattern(hunter_pattern);
    if translated {
        n: any = len(data.get("emails") or []);
        confidence: any = min(0.7 + 0.05 * n, 0.95);
        return (translated, confidence);
    }
    return None;
}

impl _translate_hunter_pattern(hunter_pattern: builtins.str) -> Optional[builtins.str] {
    if not hunter_pattern {
        return None;
    }
    p: any = hunter_pattern.lower().strip();
    mapping: any = {
        "{first}.{last}": "{f}.{l}",
        "{first}{last}": "{f}{l}",
        "{f}{last}": "{fi}{l}",
        "{first}": "{f}",
        "{f}.{last}": "{fi}.{l}",
        "{first}_{last}": "{f}_{l}",
        "{last}": "{l}",
        "{last}.{first}": "{l}.{f}",
        "{first}-{last}": "{f}-{l}",
        "{last}{f}": "{l}{fi}",
    };
    return mapping.get(p);
}

impl _hunter_api_key -> builtins.str {
    return os.getenv("HUNTER_API_KEY", "").strip();
}

impl _hunter_monthly_cap -> builtins.int {
    raw: any = os.getenv("HUNTER_MONTHLY_SEARCHES", "").strip();
    if not raw {
        return HUNTER_FREE_MONTHLY_SEARCHES;
    }
    try {
        return max(`int(raw), 0);
    } except ValueError {
        return HUNTER_FREE_MONTHLY_SEARCHES;
    }
}

impl _hunter_usage_key -> builtins.str {
    return f"hunter_domain_search_count:{datetime.now(timezone.utc):%Y-%m}";
}

impl hunter_searches_remaining(state) -> builtins.int {
    cap: any = _hunter_monthly_cap();
    if state is None {
        return cap;
    }
    try {
        used: any = `int(await state.get_setting(_hunter_usage_key(), "0") or "0");
    } except (ValueError, TypeError) {
        used = 0;
    } except Exception as e {
        logger.debug(f"Hunter usage read failed: {e}");
        return 0;
    }
    return max(cap - used, 0);
}

impl record_hunter_search(state) -> None {
    if state is None {
        return;
    }
    try {
        await state.increment_setting(_hunter_usage_key());
    } except Exception as e {
        logger.debug(f"Hunter usage write failed: {e}");
    }
}

impl hunter_domain_people(
    domain: builtins.str, api_key: builtins.str, limit: builtins.int = 10
) -> Optional[builtins.list[builtins.dict]] {
    try {
        client: any;
        async with httpx.AsyncClient(timeout=API_TIMEOUT) as client {
            resp: any = await client.get(
                "https://api.hunter.io/v2/domain-search",
                params={"domain": domain, "limit": limit},
                headers=_hunter_headers(api_key),
            );
        }
    } except httpx.HTTPError as e {
        logger.debug(f"Hunter domain-search failed for {domain}: {_redact(e, api_key)}");
        return None;
    }
    if resp.status_code != 200 {
        return None;
    }
    try {
        data: any = (resp.json() or {}).get("data") or {};
    } except ValueError {
        return None;
    }
    emails: any = data.get("emails");
    return emails if isinstance(emails, `list) else None;
}

impl derive_pattern(
    domain: builtins.str,
    known_emails: Optional[builtins.list[builtins.tuple[builtins.str, builtins.str, builtins.str]]] = None,
    state=None,
    default_pattern: builtins.str = default_pattern_default_,
) -> builtins.tuple[builtins.str, builtins.str, builtins.float] {
    domain = _clean_domain(domain);
    for (email, first, last) in known_emails or [] {
        if email.split("@")[-1].lower() == domain {
            inferred: any = infer_pattern_from_email(email, first, last);
            if inferred {
                return (inferred, "known_email", 0.9);
            }
        }
    }

    cached: any = None;
    if state is not None {
        try {
            cached = await state.get_email_pattern(domain);
        } except Exception as e {
            logger.debug(f"Pattern cache read failed for {domain}: {e}");
        }
    }
    source: any = (cached or {}).get("source") or "";
    if cached and cached.get("pattern") and source not in WEAK_SOURCES {
        return (cached["pattern"], source or "cache", cached.get("confidence", 0.6));
    }
    site_guess: any = cached
        if cached and cached.get("pattern") and source.startswith("site_address_guess")
        else None;
    hunter_tried: any = source.endswith("_after_hunter");
    key: any = _hunter_api_key();
    if key and not hunter_tried and await hunter_searches_remaining(state) > 0 {
        await record_hunter_search(state);
        try {
            result: any = await _hunter_domain_pattern(domain, key);
            answered: any = True;
        } except HunterUnavailable as e {
            logger.debug(f"Hunter unavailable for {domain}: {e}");
            (result, answered) = (None, False);
        }
        if result {
            return (result[0], "hunter_domain_search", result[1]);
        }
        if answered {
            if site_guess {
                return (
                    site_guess["pattern"],
                    "site_address_guess_after_hunter",
                    site_guess.get("confidence", 0.6),
                );
            }
            return (default_pattern, "default_after_hunter", 0.3);
        }
    }

    if site_guess {
        return (site_guess["pattern"], source, site_guess.get("confidence", 0.6));
    }
    return (default_pattern, source if hunter_tried else "default", 0.3);
}

impl verify_reoon(email: builtins.str, api_key: builtins.str) -> Optional[builtins.dict] {
    try {
        client: any;
        async with httpx.AsyncClient(timeout=API_TIMEOUT) as client {
            resp: any = await client.get(
                "https://emailverifier.reoon.com/api/v1/verify",
                params={"email": email, "key": api_key, "mode": "power"},
            );
        }
    } except httpx.HTTPError as e {
        logger.debug(f"Reoon request failed for {email}: {_redact(e, api_key)}");
        return None;
    }
    if resp.status_code != 200 {
        return None;
    }
    try {
        data: any = resp.json();
    } except ValueError {
        return None;
    }
    if not isinstance(data, `dict) {
        return None;
    }
    status: any = `str(data.get("status") or "").lower();
    if status == "role_account" {
        status = "valid" if data.get("is_deliverable") is True else "unknown";
    }
    is_catch_all: any = `bool(data.get("is_catch_all") or operator.eq(status, "catch_all"));
    return {"status": status, "catch_all": is_catch_all};
}

impl verify_zerobounce(email: builtins.str, api_key: builtins.str) -> Optional[builtins.dict] {
    try {
        client: any;
        async with httpx.AsyncClient(timeout=API_TIMEOUT) as client {
            resp: any = await client.get(
                "https://api.zerobounce.net/v2/validate",
                params={"email": email, "api_key": api_key},
            );
        }
    } except httpx.HTTPError as e {
        logger.debug(f"ZeroBounce request failed for {email}: {_redact(e, api_key)}");
        return None;
    }
    if resp.status_code != 200 {
        return None;
    }
    try {
        data: any = resp.json();
    } except ValueError {
        return None;
    }
    if not isinstance(data, `dict) {
        return None;
    }
    status: any = `str(data.get("status") or "").lower();
    sub: any = `str(data.get("sub_status") or "").lower();
    return {
        "status": status,
        "catch_all": operator.eq(sub, "catch-all") or operator.eq(status, "catch-all"),
    };
}

impl verify_hunter(email: builtins.str, api_key: builtins.str) -> Optional[builtins.dict] {
    try {
        client: any;
        async with httpx.AsyncClient(timeout=API_TIMEOUT) as client {
            resp: any = await client.get(
                "https://api.hunter.io/v2/email-verifier",
                params={"email": email},
                headers=_hunter_headers(api_key),
            );
        }
    } except httpx.HTTPError as e {
        logger.debug(f"Hunter verify failed for {email}: {_redact(e, api_key)}");
        return None;
    }
    if resp.status_code != 200 {
        return None;
    }
    try {
        data: any = (resp.json() or {}).get("data") or {};
    } except ValueError {
        return None;
    }
    status: any = `str(data.get("status") or data.get("result") or "").lower();
    return {"status": status, "catch_all": `bool(data.get("accept_all"))};
}

impl verify_email_smtp(email: builtins.str) -> Optional[builtins.bool] {
    if "@" not in email {
        return False;
    }
    domain: any = email.rsplit("@", 1)[1];
    mx_host: any = await get_mx_host(domain);
    if not mx_host {
        return None;
    }
    smtp: any = aiosmtplib.SMTP(hostname=mx_host, port=25, timeout=10);
    try {
        await smtp.connect();
        await smtp.ehlo();
        await smtp.mail("verify@example.com");
        code: any;
        _: any;
        (code, _) = await smtp.rcpt(email) as any;
        if code == 250 {
            return True;
        }
        if code in (550, 551, 553) {
            return False;
        }
        return None;
    } except Exception as e {
        logger.debug(f"SMTP verification failed for {email}: {e}");
        return None;
    } finally {
        try {
            await smtp.quit();
        } except Exception {}
    }
}

impl detect_catch_all(domain: builtins.str) -> Optional[builtins.bool] {
    fake: any = f"zz-no-such-user-{random.randint(10000, 99999)}@{_clean_domain(domain)}";
    result: any = await verify_email_smtp(fake);
    if result is True {
        return True;
    }
    if result is False {
        return False;
    }
    return None;
}

impl _status_from_verdict(verdict: builtins.dict) -> Optional[builtins.str] {
    if verdict.get("catch_all") {
        return "risky";
    }
    status: any = verdict.get("status", "");
    if status in ("valid", "deliverable", "safe") {
        return "verified";
    }
    if status in ("invalid", "undeliverable", "disabled", "disposable", "spamtrap") {
        return "invalid";
    }
    if status in ("catch_all", "catch-all", "accept_all") {
        return "risky";
    }
    return None;
}

impl _verify_candidate(
    email: builtins.str, mx_type: builtins.str, env
) -> builtins.tuple[Optional[builtins.str], builtins.bool] {
    reoon_key: any;
    zerobounce_key: any;
    hunter_key: any;
    reoon_key = getattr(env, "reoon_api_key", "") if env else "";
    zerobounce_key = getattr(env, "zerobounce_api_key", "") if env else "";
    hunter_key = _hunter_api_key();

    catch_all_seen: any = False;
    if mx_type in ("google", "microsoft", "gateway") {
        channels: any = [];
        if zerobounce_key {
            channels.append(lambda -> any { verify_zerobounce(email, zerobounce_key) });
        }
        if reoon_key {
            channels.append(lambda -> any { verify_reoon(email, reoon_key) });
        }
        if hunter_key {
            channels.append(lambda -> any { verify_hunter(email, hunter_key) });
        }
        for channel in channels {
            verdict: any = await channel();
            if verdict is None {
                continue;
            }
            if verdict.get("catch_all") {
                catch_all_seen = True;
            }
            status: any = _status_from_verdict(verdict);
            if status is not None {
                return (status, catch_all_seen);
            }
        }
        return (None, catch_all_seen);
    }
    if reoon_key {
        verdict = await verify_reoon(email, reoon_key);
        if verdict {
            if verdict.get("catch_all") {
                catch_all_seen = True;
            }
            status = _status_from_verdict(verdict);
            if status is not None {
                return (status, catch_all_seen);
            }
        }
    }

    smtp: any = await verify_email_smtp(email);
    if smtp is True {
        if await detect_catch_all(email.split("@")[1]) is True {
            return ("risky", True);
        }
        return ("verified", catch_all_seen);
    }
    if smtp is False {
        return ("invalid", catch_all_seen);
    }

    if hunter_key {
        verdict = await verify_hunter(email, hunter_key);
        if verdict {
            if verdict.get("catch_all") {
                catch_all_seen = True;
            }
            status = _status_from_verdict(verdict);
            if status is not None {
                return (status, catch_all_seen);
            }
        }
    }

    return (None, catch_all_seen);
}

impl verify_published_address(email: builtins.str, env=None) -> builtins.str {
    email = (email or "").strip().lower();
    domain: any = email.partition("@")[2];
    if not domain {
        return "invalid";
    }
    mx_host: any = await get_mx_host(domain);
    if not mx_host {
        return "invalid";
    }
    status: any;
    _: any;
    (status, _) = await _verify_candidate(email, classify_mx(mx_host), env) as any;
    return status or "guess";
}

impl _belongs_to_someone_else(
    candidate, pattern, person, domain, other_people, known_emails
) -> builtins.bool {
    me: any = (_clean_name_part(person[0]), _clean_name_part(person[1]));
    first: any;
    last: any;
    for (email, first, last) in known_emails or [] {
        if email.strip().lower() == candidate
            and (_clean_name_part(first), _clean_name_part(last)) != me
        {
            return True;
        }
    }
    for (first, last) in other_people or [] {
        if (_clean_name_part(first), _clean_name_part(last)) == me {
            continue;
        }
        if build_email(pattern, first, last, domain) == candidate {
            return True;
        }
    }
    return False;
}

impl find_email(
    first_name: builtins.str,
    last_name: builtins.str,
    domain: builtins.str,
    verify: builtins.bool = True,
    env=None,
    state=None,
    known_emails: Optional[builtins.list[builtins.tuple[builtins.str, builtins.str, builtins.str]]] = None,
    default_pattern: builtins.str = default_pattern_default__,
    other_people: Optional[builtins.list[builtins.tuple[builtins.str, builtins.str]]] = None,
) -> EmailResult {
    domain = _clean_domain(domain);
    if not (first_name and last_name and domain) {
        return EmailResult(email="", status="invalid");
    }

    mx_host: any = await get_mx_host(domain);
    if not mx_host {
        guess: any = build_email(DEFAULT_PATTERN, first_name, last_name, domain);
        return EmailResult(email=guess, status="invalid", mx_type="none");
    }

    mx_type: any = classify_mx(mx_host);

    pattern: any;
    source: any;
    confidence: any;
    (pattern, source, confidence) = await derive_pattern(
        domain, known_emails=known_emails, state=state, default_pattern=default_pattern
    ) as any;
    candidate: any = build_email(pattern, first_name, last_name, domain);
    `own: any = (_clean_name_part(first_name), _clean_name_part(last_name));
    for (email, first, last) in known_emails or [] {
        if (_clean_name_part(first), _clean_name_part(last)) == `own
            and email.split("@")[-1].lower() == domain
        {
            candidate = email.strip().lower();
            pattern = infer_pattern_from_email(candidate, first, last) or pattern;
            break;
        }
    }
    if _belongs_to_someone_else(
        candidate, pattern, (first_name, last_name), domain, other_people, known_emails
    ) {
        logger.info(
            f"Email for {first_name} {last_name}@{domain}: {candidate} could be another named person's mailbox; not guessed",
        );
        return EmailResult(email="", status="guess", pattern=pattern, mx_type=mx_type);
    }
    if not candidate {
        candidate = build_email(DEFAULT_PATTERN, first_name, last_name, domain);
        pattern = DEFAULT_PATTERN;
    }

    if state is not None {
        try {
            await state.save_email_pattern(
                domain, pattern=pattern, source=source, confidence=confidence, mx_type=mx_type
            );
        } except Exception as e {
            logger.debug(f"Pattern cache write failed for {domain}: {e}");
        }
    }

    if not verify {
        return EmailResult(email=candidate, status="guess", pattern=pattern, mx_type=mx_type);
    }

    status: any;
    catch_all: any;
    (status, catch_all) = await _verify_candidate(candidate, mx_type, env) as any;

    if catch_all and state is not None {
        try {
            await state.save_email_pattern(domain, mx_type=mx_type, is_catch_all=1);
        } except Exception {}
    }

    if status is None {
        status = "guess";
    }

    logger.info(f"Email for {first_name} {last_name}@{domain}: {candidate} [{status}]");
    return EmailResult(email=candidate, status=status, pattern=pattern, mx_type=mx_type);
}
