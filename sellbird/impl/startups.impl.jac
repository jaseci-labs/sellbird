impl funding_text(found: builtins.dict) -> builtins.str {
    return " · ".join(p for p in (found.get("round"), found.get("amount"), found.get("date")) if p);
}

impl parse_funding(text: builtins.str) -> builtins.dict {
    out: any = {"round": "", "amount": "", "date": ""};
    for part in (p.strip() for p in (text or "").split("·")) {
        if not part {
            continue;
        }
        if _DATE_RE.match(part) {
            out["date"] = part;
        } elif part[0] in "$€£" {
            out["amount"] = part;
        } else {
            out["round"] = part;
        }
    }
    return out;
}

impl _as_date(when: builtins.str) -> date | None {
    m: any = _DATE_RE.match(when or "");
    if not m {
        return None;
    }
    try {
        return date(`int(m.group(1)), `int(m.group(2) or 1), `int(m.group(3) or 1));
    } except ValueError {
        return None;
    }
}

impl funding_recency(when: builtins.str, today: date | None = None) -> builtins.str {
    day: any = _as_date(when);
    if day is None {
        return "unknown";
    }
    return "recent" if ((today or date.today()) - day).days <= FUNDING_RECENT_DAYS else "old";
}

impl _funding_fact(found: builtins.dict, today: date | None) -> builtins.str {
    what: any = ", ".join(p for p in (found["round"], found["amount"]) if p) or "a funding round";
    when: any = found["date"];
    recency: any = funding_recency(when, today);
    if recency == "recent" {
        months: any = max(0, ((today or date.today()) - _as_date(when)).days // 30);
        return f"- Raised: {what}, announced {when} (about {months} month(s) ago), as their own site says";
    }
    if recency == "old" {
        return f"- Raised: {what}, announced {when}, as their own site says. That is over 18 months ago, so not recent: don't write as if they just raised";
    }
    return f"- Raised: {what}, as their own site says, but no date was found: don't call it recent";
}

impl _read(state, name: builtins.str, company_id: builtins.str) -> any {
    lookup: any = getattr(state, name, None);
    if lookup is None {
        return None;
    }
    try {
        return await lookup(company_id);
    } except Exception {
        return None;
    }
}

impl startup_facts(
    state, company_id: builtins.str, today: date | None = None
) -> builtins.list[builtins.str] | None {
    if not company_id or state is None {
        return None;
    }
    facts: builtins.list[builtins.str] = [];
    read: any = lambda (name) -> any { _read(state, name, company_id) };
    yc: any = await read("yc_batch");
    if yc is not None {
        facts.append(
            "- Backed by Y Combinator" + (f" (YC {yc})" if yc else "") + ", as their own site says"
        );
    }
    program: any = await read("accelerator");
    if program is not None {
        facts.append(
            f"- Went through an accelerator: {program}, as their own site says"
                if program
                else "- Went through a startup accelerator (a search matched it on their own site)",
        );
    }
    funding: any = await read("funding_round");
    recent: any = funding is not None
        and operator.eq(funding_recency(funding["date"], today), "recent");
    if not (facts or recent) {
        return None;
    }
    if funding is not None {
        facts.append(_funding_fact(funding, today));
    }
    return facts;
}
