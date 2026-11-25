impl _resolve(name: str, rtype: str) -> any {
    try {
        return `list(dns.resolver.resolve(name, rtype, lifetime=8));
    } except (dns.resolver.NXDOMAIN, dns.resolver.NoAnswer) {
        return [];
    } except dns.exception.DNSException as e {
        raise LookupFailed(`type(e).__name__) from e;
    }
}

impl _txt(name: str) -> list[str] {
    return [b"".join(r.strings).decode("utf-8", "replace") for r in _resolve(name, "TXT")];
}

impl _a(name: str) -> list[str] {
    return [r.address for r in _resolve(name, "A")];
}

impl _unknown(name: str, e: any) -> Check {
    return Check(name, INFO, _TEXT["unknown"].format(e), unknown=True);
}

impl check_mx(domain: str) -> Check {
    try {
        mx = sorted(_resolve(domain, "MX"), key=lambda (r: any) -> any { r.preference });
    } except LookupFailed as e {
        return _unknown("MX", e);
    }
    if not mx {
        return Check("MX", FAIL, _TEXT["mx_none"]);
    }
    return Check("MX", OK, ", ".join(`str(r.exchange).rstrip(".") for r in mx[:3]));
}

impl _records(name: str, label: str, prefix: str) -> any {
    try {
        return [t for t in _txt(name) if t.lower().startswith(prefix)];
    } except LookupFailed as e {
        return _unknown(label, e);
    }
}

impl check_spf(domain: str) -> Check {
    records = _records(domain, "SPF", "v=spf1");
    if isinstance(records, Check) {
        return records;
    }
    if len(records) != 1 {
        return Check(
            "SPF", FAIL, _TEXT["spf_many"].format(len(records)) if records else _TEXT["spf_none"]
        );
    }
    spf = records[0];
    terms = spf.lower().split();
    lookups = sum(
        t.lstrip("+-~?").split(":")[0].split("=")[0].split("/")[0]
            in ("include", "a", "mx", "ptr", "exists", "redirect")
        for t in terms,
    );
    if "+all" in terms or "all" in terms {
        return Check("SPF", FAIL, f"'+all' lets anyone send as you: {spf}");
    } elif lookups > 10 {
        return Check("SPF", FAIL, _TEXT["spf_lookups"].format(lookups));
    } elif "?all" in terms {
        return Check("SPF", WARN, f"'?all' is neutral; use '~all' or '-all': {spf}");
    } elif not `any(t.lstrip("+-~?") == "all" or t.startswith("redirect=") for t in terms) {
        return Check("SPF", WARN, _TEXT["spf_no_all"].format(spf));
    }
    return Check("SPF", OK, spf);
}

impl check_dmarc(domain: str) -> Check {
    records = _records(f"_dmarc.{domain}", "DMARC", "v=dmarc1");
    if isinstance(records, Check) {
        return records;
    }
    if len(records) != 1 {
        return Check(
            "DMARC",
            FAIL,
            _TEXT["dmarc_many"].format(len(records))
                if records
                else _TEXT["dmarc_none"].format(domain),
        );
    }
    tags = {
        k.strip().lower(): v
        for (k, v) in (part.strip().split("=", 1) for part in records[0].split(";") if "=" in part)
    };
    policy = tags.get("p", "").strip().lower();
    if not policy {
        return Check("DMARC", WARN, _TEXT["dmarc_no_p"].format(records[0]));
    }
    if policy == "none" {
        return Check("DMARC", WARN, _TEXT["dmarc_p_none"].format(records[0]));
    }
    return Check("DMARC", OK, records[0]);
}

impl check_dkim(domain: str, selector: str = "") -> Check {
    for sel in ((selector,) if selector else COMMON_DKIM_SELECTORS) {
        try {
            records = _txt(f"{sel}._domainkey.{domain}");
        } except LookupFailed as e {
            return _unknown("DKIM", e);
        }
        for record in records {
            flat = record.replace(" ", "");
            if "p=" in flat and "p=;" not in flat + ";" {
                return Check("DKIM", OK, f"selector '{sel}' found");
            }
        }
    }
    if selector {
        return Check("DKIM", FAIL, f"No DKIM key at {selector}._domainkey.{domain}.");
    }
    return Check("DKIM", WARN, _TEXT["dkim_none"]);
}

impl check_domain_age(domain: str) -> Check {
    try {
        r = httpx.get(f"https://rdap.org/domain/{domain}", timeout=15, follow_redirects=True);
        r.raise_for_status();
        events = r.json().get("events", []);
    } except Exception as e {
        return Check(
            "Domain age", INFO, f"Couldn't look up registration date ({`type(e).__name__})."
        );
    }
    registered = next(
        (e.get("eventDate") for e in events if e.get("eventAction") == "registration"), None
    );
    if not registered {
        return Check("Domain age", INFO, "Registry didn't publish a registration date.");
    }
    try {
        age = (
            date.today() - datetime.fromisoformat(registered.replace("Z", "+00:00")).date()
        ).days;
    } except ValueError {
        return Check("Domain age", INFO, f"Registry gave an unreadable date ({registered[:40]}).");
    }
    head = f"{age} days (registered {registered[:10]})";
    if age < MIN_DOMAIN_AGE_DAYS {
        return Check("Domain age", FAIL, _TEXT["age_new"].format(head));
    }
    if age < GOOD_DOMAIN_AGE_DAYS {
        return Check("Domain age", WARN, head + " - still young; keep volume low.");
    }
    return Check("Domain age", OK, head);
}

impl _refused(hits: list[str], refusal: str) -> bool {
    for ip in hits {
        if refusal and (ip.startswith(refusal) if refusal.endswith(".") else ip == refusal) {
            return True;
        }
    }
    return False;
}

impl _blocklist_checks(query: str, label: str, lists: any) -> list[Check] {
    checks: list[Check] = [];
    for (zone, refusal, manual) in lists {
        name = f"{label} {zone}";
        try {
            hits = _a(f"{query}.{zone}");
        } except LookupFailed as e {
            checks.append(_unknown(name, e));
            continue;
        }
        if not hits {
            checks.append(Check(name, OK, "not listed"));
        } elif _refused(hits, refusal) {
            checks.append(Check(name, INFO, _TEXT["refused"].format(manual)));
        } else {
            checks.append(Check(name, FAIL, f"LISTED ({', '.join(hits)})"));
        }
    }
    return checks;
}

impl check_domain_blocklists(domain: str) -> list[Check] {
    return _blocklist_checks(domain, "Blocklist", DOMAIN_BLOCKLISTS);
}

impl check_ip_blocklists(smtp_host: str) -> list[Check] {
    try {
        ips = _a(smtp_host);
    } except LookupFailed as e {
        return [_unknown("Sending IP", e)];
    }
    if not ips {
        return [Check("Sending IP", INFO, f"Couldn't resolve {smtp_host}.")];
    }
    return _blocklist_checks(".".join(reversed(ips[0].split("."))), f"IP {ips[0]}", IP_BLOCKLISTS);
}

impl check_warmup(
    warmup: any, ceiling: int, today: date | None = None, provider: str = ""
) -> Check {
    if provider == "instantly" {
        return Check("Warmup", INFO, _TEXT["ramp_instantly"]);
    }
    days = warmup.days_in(today);
    if days is None {
        return Check("Warmup", WARN, _TEXT["ramp_unset"]);
    }
    if days < 0 {
        return Check("Warmup", WARN, f"Starts {warmup.start_date} (in {-days} days).");
    }
    if days < warmup.min_days {
        return Check(
            "Warmup",
            FAIL,
            _TEXT["ramp_early"].format(days, warmup.min_days, warmup.min_days - days),
        );
    }
    cap = warmup.daily_cap(ceiling, today);
    step = warmup.daily_increase;
    if cap <= 0 and step <= 0 {
        return Check("Warmup", WARN, _TEXT["ramp_zero"]);
    }
    ramp = "full volume";
    if cap < ceiling and step <= 0 {
        ramp = f"stays at {cap}/day (daily_increase is 0)";
    } elif cap < ceiling {
        ramp = f"reaches {ceiling}/day on day {warmup.min_days + -(-(ceiling - warmup.start_sends) // step)}";
    }
    return Check("Warmup", OK, _TEXT["ramp_ok"].format(days, cap, ramp));
}

impl check_warmup_service(
    health: any,
    warmup: any = None,
    *,
    error: str = "",
    other_service: bool = False,
    today: date | None = None,
) -> Check {
    name = "Warmup service";
    if error {
        return Check(name, WARN, f"Couldn't read TrulyInbox: {error}");
    }
    if health is None {
        return Check(
            name,
            INFO,
            _TEXT["ti_other"]
                if other_service
                else _TEXT["ti_none"].format(AFFILIATE_URL, AFFILIATE_TAG),
        );
    }
    for (ok, key) in (
        (health.found, "ti_missing"),
        (health.login_ok, "ti_login"),
        (health.warming, "ti_off"),
    ) {
        if not ok {
            return Check(name, FAIL, _TEXT[key].format(health.address));
        }
    }
    min_days = warmup.min_days if warmup is not None else 14;
    days = ((today or date.today()) - health.started_on).days if health.started_on else None;
    hint = "";
    if health.started_on and warmup is not None and not warmup.start_date {
        hint = _TEXT["ti_hint"].format(health.started_on.isoformat());
    }
    rate = health.spam_rate;
    if rate is not None and health.sent >= MIN_WARMUP_SAMPLE and rate >= MAX_WARMUP_SPAM {
        return Check(
            name,
            FAIL,
            _TEXT["ti_spam"].format(round(rate * 100), round(MAX_WARMUP_SPAM * 100)) + hint,
        );
    }
    inbox = _TEXT["ti_inbox"].format(round((1 - rate) * 100)) if rate is not None else "";
    if health.sent < MIN_WARMUP_SAMPLE {
        return Check(name, WARN, _TEXT["ti_few"].format(health.sent) + hint);
    }
    if days is None or days < min_days {
        shown = "warming" if days is None else f"day {max(days, 0)} of {min_days}";
        return Check(
            name, FAIL, f"TrulyInbox: {shown}{inbox}. Keep warming before cold email." + hint
        );
    }
    return Check(name, OK, _TEXT["ti_ok"].format(days, inbox) + hint);
}

impl check_send_history(total_sent: int, bounces: int) -> Check {
    if total_sent < MIN_SENDS_FOR_RATES {
        return Check("Bounce rate", INFO, _TEXT["bounce_few"].format(bounces, total_sent));
    }
    rate = bounces / total_sent;
    return Check(
        "Bounce rate",
        OK if rate <= MAX_BOUNCE_RATE else FAIL,
        f"{rate:.1%} ({bounces}/{total_sent}); keep it under {MAX_BOUNCE_RATE:.0%}.",
    );
}
