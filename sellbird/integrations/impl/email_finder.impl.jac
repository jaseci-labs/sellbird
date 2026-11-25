impl _clean_domain(domain: str) -> str {
    domain = re.sub("^https?://", "", (domain or "").strip().lower()).split("/")[0].split("?")[0];
    return domain[4:] if domain.startswith("www.") else domain;
}

impl _clean_name_part(value: str) -> str {
    return re.sub("[^a-z]", "", (value or "").lower());
}

impl _name(first: str, last: str) -> tuple[str, str] {
    return (_clean_name_part(first), _clean_name_part(last));
}

impl build_email(pattern: str, first: str, last: str, domain: str) -> str {
    ((first, last), domain) = (_name(first, last), _clean_domain(domain));
    if not first or not last or not domain or pattern not in PATTERNS {
        return "";
    }
    local = pattern.format(f=first, l=last, fi=first[0]);
    return f"{local}@{domain}" if local else "";
}

impl generate_patterns(first_name: str, last_name: str, domain: str) -> list[str] {
    out: list[str] = [];
    for pattern in PATTERNS {
        out.append(build_email(pattern, first_name, last_name, domain));
    }
    return `list(`dict.fromkeys(e for e in out if e));
}

impl classify_mx(mx_host: str) -> str {
    h = (mx_host or "").lower();
    if not h {
        return "none";
    } elif "google" in h or "googlemail" in h or "aspmx.l" in h {
        return "google";
    } elif "outlook" in h or "protection.outlook" in h or "microsoft" in h {
        return "microsoft";
    }
    return "gateway" if `any(g in h for g in GATEWAYS) else "other";
}

impl get_mx_host(domain: str) -> str | None {
    domain = _clean_domain(domain);
    if not domain {
        return None;
    }
    if domain in _mx_cache {
        return _mx_cache[domain];
    }
    try {
        answers = await asyncio.get_event_loop().run_in_executor(
            None, lambda -> any { dns.resolver.resolve(domain, "MX") }
        );
        records = sorted(answers, key=lambda (x: any) -> any { x.preference });
        _mx_cache[domain] = (`str(records[0].exchange).rstrip(".") if records else None) or None;
    } except Exception as e {
        logger.debug(f"MX lookup failed for {domain}: {e}");
        _mx_cache[domain] = None;
    }
    return _mx_cache[domain];
}

impl infer_pattern_from_email(email: str, first: str, last: str) -> str | None {
    email = (email or "").strip().lower();
    (first, last) = _name(first, last);
    if "@" not in email or not first or not last {
        return None;
    }
    local = email.split("@", 1)[0];
    for pattern in PATTERNS {
        if pattern.format(f=first, l=last, fi=first[0]) == local {
            return pattern;
        }
    }
    return None;
}

impl pattern_from_local(local: str) -> tuple[str, float] | None {
    local = (local or "").strip().lower();
    if not local or local in ROLE_LOCALS or `any(ch.isdigit() for ch in local) {
        return None;
    }
    m = re.fullmatch("([a-z]+)([._-])([a-z]+)", local);
    if not m {
        return None;
    }
    (first, sep, last) = m.groups();
    if sep == "." and len(first) == 1 and len(last) >= 2 {
        return ("{fi}.{l}", 0.6);
    }
    if len(first) >= 2 and len(last) >= 2 and first not in ROLE_LOCALS and last not in ROLE_LOCALS {
        return ("{f}" + sep + "{l}", 0.6);
    }
    return None;
}

impl _disambiguate(local: str, people: any) -> tuple[str, float] | None {
    if not re.fullmatch("[a-z]{3,20}", local or "") {
        return None;
    }
    lasts = {_clean_name_part(last) for (_, last) in people or []} - {""};
    firsts = {_clean_name_part(first) for (first, _) in people or []} - {""};
    if local in firsts {
        return ("{f}", 0.6);
    }
    if `any(len(last) >= 3 and local[1:] == last for last in lasts) {
        return ("{fi}{l}", 0.6);
    }
    return ("{l}", 0.55) if local in lasts else None;
}

impl site_email_evidence(
    addresses: list[str], people: list[tuple[str, str]], domain: str
) -> tuple[list[tuple[str, str, str]], str, float] {
    domain = _clean_domain(domain);
    known: list[tuple[str, str, str]] = [];
    tied: any = Counter();
    loose: any = Counter();
    for addr in addresses or [] {
        addr = (addr or "").strip().lower();
        (local, _, adomain) = addr.partition("@");
        if adomain != domain or local in ROLE_LOCALS {
            continue;
        }
        owners: list[tuple[str, str, str]] = [];
        for (first, last) in people or [] {
            pattern = infer_pattern_from_email(addr, first, last);
            if pattern {
                owners.append((first, last, pattern));
            }
        }
        if len(owners) == 1 {
            known.append((addr, owners[0][0], owners[0][1]));
            tied[owners[0][2]] += 1;
        } elif owners and len({o[2] for o in owners}) == 1 {
            loose[owners[0][2]] += 2;
        } elif not owners {
            guess = pattern_from_local(local) or _disambiguate(local, people);
            if guess {
                loose[guess[0]] += 1;
            }
        }
    }
    if tied {
        (pattern, n) = tied.most_common(1)[0];
        return (known, pattern, 0.95 if n >= 2 else 0.9);
    }
    if loose {
        (pattern, n) = loose.most_common(1)[0];
        return (known, pattern, min(0.55 + 0.05 * n, 0.7));
    }
    return (known, "", 0.0);
}

impl _hunter_headers(api_key: str) -> dict[str, str] {
    return {"X-API-KEY": api_key};
}

impl _redact(error: any, api_key: str) -> str {
    return `str(error).replace(api_key, "***") if api_key else `str(error);
}

impl _request(
    url: str, params: dict[str, any], api_key: str, failed: str, hunter: bool = False
) -> any {
    extra = {"headers": _hunter_headers(api_key)} if hunter else {};
    try {
        async with httpx.AsyncClient(timeout=API_TIMEOUT) as client {
            return await client.get(url, params=params, **extra);
        }
    } except httpx.HTTPError as e {
        logger.debug(f"{failed}: {_redact(e, api_key)}");
        raise HunterUnavailable(_redact(e, api_key)) from e;
    }
}

impl _fetch_json(
    url: str, params: dict[str, any], api_key: str, failed: str, hunter: bool = False
) -> tuple[bool, any] {
    try {
        resp = await _request(url, params, api_key, failed, hunter);
    } except HunterUnavailable {
        return (False, None);
    }
    try {
        return (True, resp.json()) if resp.status_code == 200 else (False, None);
    } except ValueError {
        return (False, None);
    }
}

impl _hunter_domain_pattern(domain: str, api_key: str) -> tuple[str, float] | None {
    resp = await _request(
        HUNTER_SEARCH,
        {"domain": domain, "limit": 1},
        api_key,
        f"Hunter domain-search failed for {domain}",
        True,
    );
    if resp.status_code == 429 or resp.status_code >= 500 {
        raise HunterUnavailable(f"HTTP {resp.status_code}");
    }
    if resp.status_code != 200 {
        return None;
    }
    try {
        data = (resp.json() or {}).get("data") or {};
    } except ValueError {
        raise HunterUnavailable("bad JSON");
    }
    translated = _translate_hunter_pattern(data.get("pattern") or "");
    return (translated, min(0.7 + 0.05 * len(data.get("emails") or []), 0.95))
        if translated
        else None;
}

impl _translate_hunter_pattern(hunter_pattern: str) -> str | None {
    return _HUNTER_PATTERNS.get(hunter_pattern.lower().strip()) if hunter_pattern else None;
}

impl _hunter_api_key -> str {
    return os.getenv("HUNTER_API_KEY", "").strip();
}

impl _hunter_monthly_cap -> int {
    raw = os.getenv("HUNTER_MONTHLY_SEARCHES", "").strip();
    try {
        return max(int(raw), 0) if raw else HUNTER_FREE_MONTHLY_SEARCHES;
    } except ValueError {
        return HUNTER_FREE_MONTHLY_SEARCHES;
    }
}

impl _hunter_usage_key -> str {
    return f"hunter_domain_search_count:{datetime.now(timezone.utc):%Y-%m}";
}

impl hunter_searches_remaining(state: any) -> int {
    cap = _hunter_monthly_cap();
    if state is None {
        return cap;
    }
    try {
        used = int(await state.get_setting(_hunter_usage_key(), "0") or "0");
    } except (ValueError, TypeError) {
        used = 0;
    } except Exception as e {
        logger.debug(f"Hunter usage read failed: {e}");
        return 0;
    }
    return max(cap - used, 0);
}

impl record_hunter_search(state: any) {
    if state is None {
        return;
    }
    try {
        await state.increment_setting(_hunter_usage_key());
    } except Exception as e {
        logger.debug(f"Hunter usage write failed: {e}");
    }
}

impl hunter_domain_people(domain: str, api_key: str, limit: int = 10) -> list[dict[str, any]]
    | None {
    (ok, body) = await _fetch_json(
        HUNTER_SEARCH,
        {"domain": domain, "limit": limit},
        api_key,
        f"Hunter domain-search failed for {domain}",
        True,
    );
    emails = ((body or {}).get("data") or {}).get("emails") if ok else None;
    return emails if isinstance(emails, `list) else None;
}

impl derive_pattern(
    domain: str,
    known_emails: list[tuple[str, str, str]] | None = None,
    state: any = None,
    default_pattern: str = DEFAULT_PATTERN,
) -> tuple[str, str, float] {
    domain = _clean_domain(domain);
    for (email, first, last) in known_emails or [] {
        inferred = infer_pattern_from_email(email, first, last)
            if email.split("@")[-1].lower() == domain
            else None;
        if inferred {
            return (inferred, "known_email", 0.9);
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
    source = (cached or {}).get("source") or "";
    has_pattern = cached and cached.get("pattern");
    if has_pattern and source not in WEAK_SOURCES {
        return (cached["pattern"], source or "cache", cached.get("confidence", 0.6));
    }
    site_guess = has_pattern and source.startswith("site_address_guess");
    hunter_tried = source.endswith("_after_hunter");
    key = _hunter_api_key();
    if key and not hunter_tried and await hunter_searches_remaining(state) > 0 {
        await record_hunter_search(state);
        try {
            result = await _hunter_domain_pattern(domain, key);
            if result {
                return (result[0], "hunter_domain_search", result[1]);
            }
            if site_guess {
                return (
                    cached["pattern"],
                    "site_address_guess_after_hunter",
                    cached.get("confidence", 0.6),
                );
            }
            return (default_pattern, "default_after_hunter", 0.3);
        } except HunterUnavailable as e {
            logger.debug(f"Hunter unavailable for {domain}: {e}");
        }
    }
    if site_guess {
        return (cached["pattern"], source, cached.get("confidence", 0.6));
    }
    return (default_pattern, source if hunter_tried else "default", 0.3);
}

impl verify_reoon(email: str, api_key: str) -> dict[str, any] | None {
    (ok, data) = await _fetch_json(
        "https://emailverifier.reoon.com/api/v1/verify",
        {"email": email, "key": api_key, "mode": "power"},
        api_key,
        f"Reoon request failed for {email}",
    );
    if not ok or not isinstance(data, `dict) {
        return None;
    }
    status = `str(data.get("status") or "").lower();
    if status == "role_account" {
        status = "valid" if data.get("is_deliverable") is True else "unknown";
    }
    return {
        "status": status,
        "catch_all": `bool(data.get("is_catch_all") or status == "catch_all"),
    };
}

impl verify_zerobounce(email: str, api_key: str) -> dict[str, any] | None {
    (ok, data) = await _fetch_json(
        "https://api.zerobounce.net/v2/validate",
        {"email": email, "api_key": api_key},
        api_key,
        f"ZeroBounce request failed for {email}",
    );
    if not ok or not isinstance(data, `dict) {
        return None;
    }
    status = `str(data.get("status") or "").lower();
    sub = `str(data.get("sub_status") or "").lower();
    return {"status": status, "catch_all": sub == "catch-all" or status == "catch-all"};
}

impl verify_hunter(email: str, api_key: str) -> dict[str, any] | None {
    (ok, body) = await _fetch_json(
        "https://api.hunter.io/v2/email-verifier",
        {"email": email},
        api_key,
        f"Hunter verify failed for {email}",
        True,
    );
    if not ok {
        return None;
    }
    data = (body or {}).get("data") or {};
    status = `str(data.get("status") or data.get("result") or "").lower();
    return {"status": status, "catch_all": `bool(data.get("accept_all"))};
}

impl verify_email_smtp(email: str) -> bool | None {
    if "@" not in email {
        return False;
    }
    mx_host = await get_mx_host(email.rsplit("@", 1)[1]);
    if not mx_host {
        return None;
    }
    smtp = aiosmtplib.SMTP(hostname=mx_host, port=25, timeout=10);
    try {
        await smtp.connect();
        await smtp.ehlo();
        await smtp.mail("verify@example.com");
        (code, _) = await smtp.rcpt(email);
        return True if code == 250 else False if code in (550, 551, 553) else None;
    } except Exception as e {
        logger.debug(f"SMTP verification failed for {email}: {e}");
        return None;
    } finally {
        try {
            await smtp.quit();
        } except Exception {}
    }
}

impl detect_catch_all(domain: str) -> bool | None {
    result = await verify_email_smtp(
        f"zz-no-such-user-{random.randint(10000, 99999)}@{_clean_domain(domain)}"
    );
    return result if isinstance(result, `bool) else None;
}

impl _status_from_verdict(verdict: dict[str, any]) -> str | None {
    status = verdict.get("status", "");
    if verdict.get("catch_all") or status in ("catch_all", "catch-all", "accept_all") {
        return "risky";
    }
    if status in ("valid", "deliverable", "safe") {
        return "verified";
    }
    return "invalid"
        if status in ("invalid", "undeliverable", "disabled", "disposable", "spamtrap")
        else None;
}

impl _ask(email: str, channels: list[tuple[any, str]]) -> tuple[str | None, bool] {
    seen = False;
    for (verify_with, key) in channels {
        verdict = await verify_with(email, key) if key else None;
        if not verdict {
            continue;
        }
        seen = seen or `bool(verdict.get("catch_all"));
        status = _status_from_verdict(verdict);
        if status is not None {
            return (status, seen);
        }
    }
    return (None, seen);
}

impl _verify_candidate(email: str, mx_type: str, env: any) -> tuple[str | None, bool] {
    reoon_key = getattr(env, "reoon_api_key", "") if env else "";
    zerobounce_key = getattr(env, "zerobounce_api_key", "") if env else "";
    hunter_key = _hunter_api_key();
    if mx_type in ("google", "microsoft", "gateway") {
        return await _ask(
            email,
            [
                (verify_zerobounce, zerobounce_key),
                (verify_reoon, reoon_key),
                (verify_hunter, hunter_key),
            ],
        );
    }
    (status, seen) = await _ask(email, [(verify_reoon, reoon_key)]);
    if status is not None {
        return (status, seen);
    }
    smtp = await verify_email_smtp(email);
    if smtp is True {
        return ("risky", True)
            if await detect_catch_all(email.split("@")[1]) is True
            else ("verified", seen);
    }
    if smtp is False {
        return ("invalid", seen);
    }
    (status, later) = await _ask(email, [(verify_hunter, hunter_key)]);
    return (status, seen or later);
}

impl verify_published_address(email: str, env: any = None) -> str {
    email = (email or "").strip().lower();
    domain = email.partition("@")[2];
    mx_host = await get_mx_host(domain) if domain else None;
    if not mx_host {
        return "invalid";
    }
    (status, _) = await _verify_candidate(email, classify_mx(mx_host), env);
    return status or "guess";
}

impl _belongs_to_someone_else(
    candidate: str,
    pattern: str,
    person: tuple[str, str],
    domain: str,
    other_people: any,
    known_emails: any,
) -> bool {
    me = _name(person[0], person[1]);
    for (email, first, last) in known_emails or [] {
        if email.strip().lower() == candidate and _name(first, last) != me {
            return True;
        }
    }
    for (first, last) in other_people or [] {
        if _name(first, last) != me and build_email(pattern, first, last, domain) == candidate {
            return True;
        }
    }
    return False;
}

impl find_email(
    first_name: str,
    last_name: str,
    domain: str,
    verify: bool = True,
    env: any = None,
    state: any = None,
    known_emails: list[tuple[str, str, str]] | None = None,
    default_pattern: str = DEFAULT_PATTERN,
    other_people: list[tuple[str, str]] | None = None,
) -> EmailResult {
    domain = _clean_domain(domain);
    if not (first_name and last_name and domain) {
        return EmailResult("", "invalid");
    }
    mx_host = await get_mx_host(domain);
    if not mx_host {
        return EmailResult(
            build_email(DEFAULT_PATTERN, first_name, last_name, domain), "invalid", mx_type="none"
        );
    }
    mx_type = classify_mx(mx_host);
    (pattern, source, confidence) = await derive_pattern(
        domain, known_emails=known_emails, state=state, default_pattern=default_pattern
    );
    candidate = build_email(pattern, first_name, last_name, domain);
    me = _name(first_name, last_name);
    for (email, first, last) in known_emails or [] {
        if _name(first, last) == me and email.split("@")[-1].lower() == domain {
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
        return EmailResult("", "guess", pattern, mx_type);
    }
    if not candidate {
        (candidate, pattern) = (
            build_email(DEFAULT_PATTERN, first_name, last_name, domain),
            DEFAULT_PATTERN,
        );
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
        return EmailResult(candidate, "guess", pattern, mx_type);
    }
    (status, catch_all) = await _verify_candidate(candidate, mx_type, env);
    if catch_all and state is not None {
        try {
            await state.save_email_pattern(domain, mx_type=mx_type, is_catch_all=1);
        } except Exception {}
    }
    status = "guess" if status is None else status;
    logger.info(f"Email for {first_name} {last_name}@{domain}: {candidate} [{status}]");
    return EmailResult(candidate, status, pattern, mx_type);
}
