impl _contact(p: dict[any, any]) -> str {
    name = f"{p.get('first_name') or ''} {p.get('last_name') or ''}".strip() or "General inbox";
    title = p.get("title") or "";
    label = name + (f" ({title})" if title and title != "General inbox" else "");
    flag = " [not relevant]" if p.get("status") == "lost" else "";
    return f"{label}: {p.get('email') or 'no email'} [{p.get('email_status') or 'unchecked'}]{flag}";
}

impl _has(prospects: list[any], wanted: set[str]) -> bool {
    return any(p.get("status") in wanted for p in prospects);
}

impl company_status(
    company: any,
    prospects: any,
    outbox: any,
    observations: any,
    dnc: any,
    send_to_risky: bool = False,
) -> tuple[str, str] {
    domain = (company.get("domain") or "").lower();
    if domain and dnc and do_not_contact_match(f"x@{domain}", dnc) {
        return ("Excluded", "On your do-not-contact list");
    }
    listed = [
        p
        for p in prospects
        if dnc and p.get("email") and do_not_contact_match(p["email"], dnc)
    ];
    if listed and len(listed) == len([p for p in prospects if p.get("email")]) {
        return ("Excluded", "Every contact here is on your do-not-contact list");
    }
    prospects = [p for p in prospects if p not in listed];
    if _has(prospects, {"opted_out"}) {
        return ("Opted out", "A contact here asked not to be emailed");
    }
    states: set[str] = {o.get("status") for o in outbox};
    if "sent" in states or _has(prospects, DONE) {
        return ("Replied" if _has(prospects, {"replied", "meeting", "closed"}) else "Emailed", "");
    }
    if states & {"approved", "sending"} {
        sends = [o.get("send_at") or "" for o in outbox if o.get("status") == "approved"];
        when = min(sends, default="")[:10];
        return ("Approved", "Approved by you" + (f"; first send due {when}" if when else ""));
    }
    if "pending_review" in states {
        return ("Draft waiting", "Email written, waiting for your review in the Outbox");
    }
    stopped = bool(states & _STOPPED);
    if _has(prospects, {"queued"}) and not _has(prospects, {"new"}) {
        return (_NOT, _WHY_STOPPED) if stopped else ("Queued", "Staged for a campaign");
    }
    if _has(prospects, {"write_failed"}) and not _has(prospects, LIVE) {
        return (_NOT, _WHY_WRITE_FAILED);
    }
    live = [p for p in prospects if p.get("status") in LIVE];
    statuses = {(p.get("email_status") or "") for p in live};
    has_form = any(o.get("signal_code") == "CONTACT_FORM_URL" for o in observations);
    form = " Contact form available." if has_form else "";
    if "verified" in statuses or (send_to_risky and "risky" in statuses) {
        return ("Ready", _WHY_READY);
    }
    if "risky" in statuses {
        return (_NOT, _WHY_RISKY + form);
    }
    if live and statuses <= {"guess", "invalid", ""} {
        who = ", ".join(sorted({(p.get("title") or "contact") for p in live}))[:120];
        return (_NOT, f"Found {who}, {_WHY_NO_EMAIL}{form}");
    }
    if prospects and not live {
        return (_NOT, _WHY_STOPPED if stopped else _WHY_IRRELEVANT);
    }
    if company.get("prospects_checked_at") {
        return (_NOT, "Website read, but no named person or usable email on it." + form);
    }
    if company.get("profile_checked_at") {
        return ("Not processed yet", _WHY_UNSEARCHED + form);
    }
    return ("Not processed yet", "Found by search; website not read yet");
}

impl _by_company(rows: list[any]) -> dict[any, list[any]] {
    grouped: dict[any, list[any]] = {};
    for r in rows {
        grouped.setdefault(r["company_id"], []).append(r);
    }
    return grouped;
}

impl _register_row(
    c: any, grouped: list[any], config: any, dnc: any, risky: bool
) -> dict[str, any] {
    (ps, outbox, obs) = [g.get(c["id"], []) for g in grouped];
    (fit, reasons) = company_fit(c, ps, obs, config, dnc);
    (status, why) = company_status(c, ps, outbox, obs, dnc, risky);
    found = f"Found via {c['source']}" if c.get("source") else "";
    roles = dict.fromkeys(
        (o.get("value_text") or "")[:60] for o in current_roles(obs) if o.get("value_text")
    );
    return {
        "id": c["id"],
        "fit_reasons": reasons,
        "company": c.get("name") or c.get("domain") or "",
        "website": c.get("website") or (f"https://{c['domain']}" if c.get("domain") else ""),
        "sector": c.get("industry") or "",
        "area": c.get("location") or "",
        "fit": fit,
        "why_selected": "; ".join(x for x in (found, " · ".join(reasons)) if x),
        "status": status,
        "why_not_contacted": why,
        "contacts": "; ".join(_contact(p) for p in ps),
        "contact_form": next(
            (o.get("value_text") or "" for o in obs if o.get("signal_code") == "CONTACT_FORM_URL"),
            "",
        ),
        "hiring": "; ".join(roles)[:300],
        "found_via": c.get("source_url") or "",
        "first_found": (c.get("created_at") or "")[:10],
    };
}

impl build_register(query_db: any, config: any, company_id: str | None = None) -> list[any] {
    (one, args) = ("", ()) if company_id is None else (" AND {col} = ?", (company_id,));
    companies = await query_db(_COMPANIES.format(one.format(col="id")), args);
    if not companies {
        return [];
    }
    grouped: list[any] = [];
    for sql in _QUERIES {
        col = sql.split()[1].rstrip(",");
        grouped.append(_by_company(await query_db(sql + one.format(col=col), args)));
    }
    dnc = _do_not_contact(config);
    email = getattr(getattr(config, "channels", None), "email", None);
    risky = bool(getattr(email, "send_to_risky", False));
    rows = [_register_row(c, grouped, config, dnc, risky) for c in companies];
    rows.sort(key=lambda (r: dict[str, any]) -> any { r["fit"] }, reverse=True);
    return rows;
}

impl _do_not_contact(config: any) -> list[str] {
    compliance = getattr(config, "compliance", None);
    if isinstance(compliance, ComplianceConfig) {
        try {
            return list(live_do_not_contact(config) or []);
        } except Exception {}
    }
    return list(getattr(compliance, "do_not_contact", None) or []);
}

impl _sqlite_rows(db_path: str, sql: str, params: any = ()) -> list[dict[any, any]] {
    async with storage.connect(db_path) as db {
        db.row_factory = aiosqlite.Row;
        async with db.execute(sql, params) as cursor {
            return [dict(r) for r in await cursor.fetchall()];
        }
    }
}

impl sqlite_query(db_path: any) -> any {
    return partial(_sqlite_rows, str(db_path));
}

impl _cell(value: any) -> any {
    if isinstance(value, (int, float)) {
        return value;
    }
    text = str(value or "");
    unsafe = text.lstrip().startswith(("=", "+", "-", "@")) or text.startswith(("\t", "\r", "\n"));
    return "'" + text if unsafe else text;
}

impl _csv_row(row: dict[str, any]) -> dict[str, any] {
    return {k: _cell(row.get(k)) for k in COLUMNS};
}

impl to_csv(rows: list[dict[str, any]]) -> str {
    buf = io.StringIO();
    writer = csv.DictWriter(buf, fieldnames=COLUMNS, extrasaction="ignore");
    writer.writeheader();
    writer.writerows([_csv_row(row) for row in rows]);
    return buf.getvalue();
}
