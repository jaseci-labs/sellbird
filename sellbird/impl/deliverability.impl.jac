impl LookupFailed.__repr__ -> str {
    return (getattr(builtins.super(LookupFailed, self), "__repr__") as any)();
}

impl LookupFailed.__eq__(other: any) -> bool {
    return self is other;
}

impl LookupFailed.__hash__ -> int {
    return id(self);
}

impl _resolve(name: builtins.str, rtype: builtins.str) -> any {
    try {
        return `list(dns.resolver.resolve(name, rtype, lifetime=8));
    } except (dns.resolver.NXDOMAIN, dns.resolver.NoAnswer) {
        return [];
    } except dns.exception.DNSException as e {
        raise LookupFailed(`type(e).__name__) from e;
    }
}

impl _txt(name: builtins.str) -> builtins.list[builtins.str] {
    return [b"".join(r.strings).decode("utf-8", "replace") for r in _resolve(name, "TXT")];
}

impl _a(name: builtins.str) -> builtins.list[builtins.str] {
    return [r.address for r in _resolve(name, "A")];
}

impl _unknown(name: builtins.str, e: any) -> Check {
    return Check(
        name,
        INFO,
        f"Couldn't look this up ({e}). Check your connection and run again.",
        unknown=True,
    );
}

impl check_mx(domain: builtins.str) -> Check {
    try {
        mx: any = sorted(_resolve(domain, "MX"), key=lambda (r) -> any { r.preference });
    } except LookupFailed as e {
        return _unknown("MX", e);
    }
    if not mx {
        return Check("MX", FAIL, "No MX record - replies and bounces have nowhere to go.");
    }
    return Check("MX", OK, ", ".join(`str(r.exchange).rstrip(".") for r in mx[:3]));
}

impl check_spf(domain: builtins.str) -> Check {
    try {
        records: any = [t for t in _txt(domain) if t.lower().startswith("v=spf1")];
    } except LookupFailed as e {
        return _unknown("SPF", e);
    }
    if not records {
        return Check(
            "SPF", FAIL, "No SPF record. Add the TXT record your mail provider gives you."
        );
    }
    if len(records) > 1 {
        return Check(
            "SPF", FAIL, f"{len(records)} SPF records - receivers treat that as no SPF. Merge them."
        );
    }
    spf: any = records[0];
    terms: any = spf.lower().split();
    if "+all" in terms or "all" in terms {
        return Check("SPF", FAIL, f"'+all' lets anyone send as you: {spf}");
    }
    lookups: any = sum(
        t.lstrip("+-~?").split(":")[0].split("=")[0].split("/")[0]
            in ("include", "a", "mx", "ptr", "exists", "redirect")
        for t in terms,
    );
    if lookups > 10 {
        return Check("SPF", FAIL, f"{lookups} DNS lookups (limit is 10) - SPF will permerror.");
    }
    if "?all" in terms {
        return Check("SPF", WARN, f"'?all' is neutral; use '~all' or '-all': {spf}");
    }
    if not `any(operator.eq(t.lstrip("+-~?"), "all") or t.startswith("redirect=") for t in terms) {
        return Check("SPF", WARN, f"No 'all' at the end, so it ends neutral; add '~all': {spf}");
    }
    return Check("SPF", OK, spf);
}

impl check_dmarc(domain: builtins.str) -> Check {
    try {
        records: any = [t for t in _txt(f"_dmarc.{domain}") if t.lower().startswith("v=dmarc1")];
    } except LookupFailed as e {
        return _unknown("DMARC", e);
    }
    if not records {
        return Check(
            "DMARC",
            FAIL,
            f"No DMARC record. Gmail and Yahoo require one for bulk senders. Start with TXT _dmarc.{domain} = \"v=DMARC1; p=none; rua=mailto:you@{domain}\"",
        );
    }
    if len(records) > 1 {
        return Check(
            "DMARC", FAIL, f"{len(records)} DMARC records - receivers ignore them all. Keep one."
        );
    }
    tags: any = {
        k.strip().lower(): v
        for (k, v) in (part.strip().split("=", 1) for part in records[0].split(";") if "=" in part)
    };
    policy: any = tags.get("p", "").strip().lower();
    if not policy {
        return Check("DMARC", WARN, f"No p= policy tag - add p=none to start: {records[0]}");
    }
    if policy == "none" {
        return Check(
            "DMARC",
            WARN,
            f"p=none (monitoring only) - fine while warming; move to quarantine once reports look clean. {records[0]}",
        );
    }
    return Check("DMARC", OK, records[0]);
}

impl check_dkim(domain: builtins.str, selector: builtins.str = "") -> Check {
    selectors: any = (selector,) if selector else COMMON_DKIM_SELECTORS;
    for sel in selectors {
        try {
            records: any = _txt(f"{sel}._domainkey.{domain}");
        } except LookupFailed as e {
            return _unknown("DKIM", e);
        }
        for record in records {
            if "p=" in record.replace(" ", "") and "p=;" not in record.replace(" ", "") + ";" {
                return Check("DKIM", OK, f"selector '{sel}' found");
            }
        }
    }
    if selector {
        return Check("DKIM", FAIL, f"No DKIM key at {selector}._domainkey.{domain}.");
    }
    return Check(
        "DKIM",
        WARN,
        "No key at any common selector. If your provider uses a custom one, set channels.email.warmup.dkim_selector; otherwise turn DKIM on in your provider.",
    );
}

impl check_domain_age(domain: builtins.str) -> Check {
    try {
        r: any = httpx.get(f"https://rdap.org/domain/{domain}", timeout=15, follow_redirects=True);
        r.raise_for_status();
        events: any = r.json().get("events", []);
    } except Exception as e {
        return Check(
            "Domain age", INFO, f"Couldn't look up registration date ({`type(e).__name__})."
        );
    }
    registered: any = next(
        (e.get("eventDate") for e in events if e.get("eventAction") == "registration"), None
    );
    if not registered {
        return Check("Domain age", INFO, "Registry didn't publish a registration date.");
    }
    try {
        age: any = (
            date.today() - datetime.fromisoformat(registered.replace("Z", "+00:00")).date()
        ).days;
    } except ValueError {
        return Check("Domain age", INFO, f"Registry gave an unreadable date ({registered[:40]}).");
    }
    status: any = FAIL if age < MIN_DOMAIN_AGE_DAYS else WARN if age < GOOD_DOMAIN_AGE_DAYS else OK;
    note: any = {
        FAIL: " - brand-new domains are distrusted; warm only, no cold email yet.",
        WARN: " - still young; keep volume low.",
        OK: "",
    }[status];
    return Check("Domain age", status, f"{age} days (registered {registered[:10]}){note}");
}

impl _blocklist_checks(query: builtins.str, label: builtins.str, lists) -> builtins.list[Check] {
    refused: any;
    checks: any = [];
    zone: any;
    for item_ in lists {
        (zone, refused) = item_;
        try {
            hits: any = _a(f"{query}.{zone}");
        } except LookupFailed as e {
            checks.append(_unknown(f"{label} {zone}", e));
            continue;
        }
        if not hits {
            checks.append(Check(f"{label} {zone}", OK, "not listed"));
        } elif `any(refused(ip) for ip in hits) {
            checks.append(
                Check(
                    f"{label} {zone}",
                    INFO,
                    f"list refused the query (common via public DNS like 8.8.8.8) - check manually at {MANUAL_LOOKUP.get(zone, zone)}",
                ),
            );
        } else {
            checks.append(
                Check(f"{label} {zone}", FAIL, "LISTED (" + format(", ".join(hits), "") + ")")
            );
        }
    }
    return checks;
}

impl check_domain_blocklists(domain: builtins.str) -> builtins.list[Check] {
    return _blocklist_checks(domain, "Blocklist", DOMAIN_BLOCKLISTS);
}

impl check_ip_blocklists(smtp_host: builtins.str) -> builtins.list[Check] {
    try {
        ips: any = _a(smtp_host);
    } except LookupFailed as e {
        return [_unknown("Sending IP", e)];
    }
    if not ips {
        return [Check("Sending IP", INFO, f"Couldn't resolve {smtp_host}.")];
    }
    reversed_ip: any = ".".join(reversed(ips[0].split(".")));
    return _blocklist_checks(reversed_ip, f"IP {ips[0]}", IP_BLOCKLISTS);
}

impl check_warmup(
    warmup, ceiling: builtins.int, today: date | None = None, provider: builtins.str = ""
) -> Check {
    if provider == "instantly" {
        return Check(
            "Warmup",
            INFO,
            "Sellbird's ramp doesn't apply to Instantly: use Instantly's own warmup and per-account daily limit.",
        );
    }
    days: any = warmup.days_in(today);
    if days is None {
        return Check(
            "Warmup",
            WARN,
            "No warmup start date set, so sends aren't ramped. Once your warmup service is on, set channels.email.warmup.start_date: YYYY-MM-DD.",
        );
    }
    if days < 0 {
        return Check("Warmup", WARN, f"Starts {warmup.start_date} (in {-days} days).");
    }
    if days < warmup.min_days {
        return Check(
            "Warmup",
            FAIL,
            f"Day {days} of {warmup.min_days} - warming only, no cold email until {warmup.min_days - days} more day(s) pass.",
        );
    }
    cap: any = warmup.daily_cap(ceiling, today);
    if cap <= 0 and warmup.daily_increase <= 0 {
        return Check(
            "Warmup",
            WARN,
            "Today's cold cap is 0 and won't grow: raise start_sends or daily_increase.",
        );
    }
    if cap >= ceiling {
        ramp: any = "full volume";
    } elif warmup.daily_increase <= 0 {
        ramp = f"stays at {cap}/day (daily_increase is 0)";
    } else {
        full_on: any = warmup.min_days
            + -(-(ceiling - warmup.start_sends) // warmup.daily_increase);
        ramp = f"reaches {ceiling}/day on day {full_on}";
    }
    return Check(
        "Warmup",
        OK,
        f"Day {days}: today's cap is {cap}/day ({ramp}). Keep the warmup service running alongside Sellbird.",
    );
}

impl check_warmup_service(
    health,
    warmup=None,
    *,
    error: builtins.str = "",
    other_service: builtins.bool = False,
    today: date | None = None,
) -> Check {
    import from sellbird.integrations.trulyinbox { AFFILIATE_TAG, AFFILIATE_URL }
    if error {
        return Check("Warmup service", WARN, f"Couldn't read TrulyInbox: {error}");
    }
    if health is None {
        if other_service {
            return Check(
                "Warmup service",
                INFO,
                "Using another warmup service: check its dashboard for the inbox rate before cold email.",
            );
        }
        return Check(
            "Warmup service",
            INFO,
            f"Not connected, so Sellbird can't see whether this mailbox is warmed. We recommend TrulyInbox: it warms the mailbox, keeps it healthy, and Sellbird reads its inbox rate here. {AFFILIATE_URL} {AFFILIATE_TAG} Then run: sellbird trulyinbox connect",
        );
    }
    if not health.found {
        return Check(
            "Warmup service",
            FAIL,
            f"{health.address} isn't in your TrulyInbox account yet. Add it in TrulyInbox to start its warmup.",
        );
    }
    if not health.login_ok {
        return Check(
            "Warmup service",
            FAIL,
            f"TrulyInbox can't sign in to {health.address}. Reconnect the mailbox in TrulyInbox.",
        );
    }
    if not health.warming {
        return Check(
            "Warmup service",
            FAIL,
            f"Warmup isn't on for {health.address}. Turn it on in TrulyInbox.",
        );
    }
    min_days: any = warmup.min_days if warmup is not None else 14;
    days: any = (today or date.today()) - health.started_on if health.started_on else None;
    days = days.days if days is not None else None;
    hint: any = "";
    if health.started_on and warmup is not None and not warmup.start_date {
        hint = f" Set channels.email.warmup.start_date: {health.started_on.isoformat()} so Sellbird ramps cold email from it.";
    }
    rate: any = health.spam_rate;
    if rate is not None and health.sent >= MIN_WARMUP_SAMPLE and rate >= MAX_WARMUP_SPAM {
        return Check(
            "Warmup service",
            FAIL,
            f"{round(rate * 100)}% spam in warmup over the last 14 days. Keep warming and hold cold email until it's under {round(MAX_WARMUP_SPAM * 100)}%."
                + hint,
        );
    }
    inbox: any = f", {round((1 - rate) * 100)}% inbox over the last 14 days"
        if rate is not None
        else "";
    if health.sent < MIN_WARMUP_SAMPLE {
        return Check(
            "Warmup service",
            WARN,
            f"TrulyInbox sent {health.sent} warmup emails in the last 14 days: not enough to judge yet. Check that warmup is running and keep warming before cold email."
                + hint,
        );
    }
    if days is None or days < min_days {
        shown: any = "warming" if days is None else f"day {max(days, 0)} of {min_days}";
        return Check(
            "Warmup service",
            FAIL,
            f"TrulyInbox: {shown}{inbox}. Keep warming before cold email." + hint,
        );
    }
    return Check(
        "Warmup service",
        OK,
        f"TrulyInbox: warmed, day {days}{inbox}. Keep it running alongside Sellbird." + hint,
    );
}

impl check_send_history(total_sent: builtins.int, bounces: builtins.int) -> Check {
    if total_sent < MIN_SENDS_FOR_RATES {
        return Check(
            "Bounce rate",
            INFO,
            f"{bounces} bounces / {total_sent} sent - too few sends to judge yet.",
        );
    }
    rate: any = bounces / total_sent;
    status: any = OK if rate <= MAX_BOUNCE_RATE else FAIL;
    return Check(
        "Bounce rate",
        status,
        f"{rate:.1%} ({bounces}/{total_sent}); keep it under {MAX_BOUNCE_RATE:.0%}.",
    );
}
