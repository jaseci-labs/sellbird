import re;
import from datetime { date }

glob FUNDING_RECENT_DAYS = 548,
     _DATE_RE = re.compile("^(\\d{4})(?:-(\\d{2}))?(?:-(\\d{2}))?$");

def funding_text(found: dict[str, any]) -> str {
    return " · ".join([v for v in map(found.get, ("round", "amount", "date")) if v]);
}

def parse_funding(text: str) -> dict[str, str] {
    out = {"round": "", "amount": "", "date": ""};
    for part in [p.strip() for p in (text or "").split("·")] {
        if part {
            key = "date" if _DATE_RE.match(part) else "amount" if part[0] in "$€£" else "round";
            out[key] = part;
        }
    }
    return out;
}

def _as_date(when: str) -> date | None {
    m = _DATE_RE.match(when or "");
    try {
        return date(int(m.group(1)), int(m.group(2) or 1), int(m.group(3) or 1)) if m else None;
    } except ValueError {
        return None;
    }
}

def funding_recency(when: str, today: date | None = None) -> str {
    day = _as_date(when);
    if day is None {
        return "unknown";
    }
    return "recent" if ((today or date.today()) - day).days <= FUNDING_RECENT_DAYS else "old";
}

def _funding_fact(found: dict[str, any], today: date | None) -> str {
    what = ", ".join([p for p in (found["round"], found["amount"]) if p]) or "a funding round";
    when = found["date"];
    recency = funding_recency(when, today);
    if recency == "recent" {
        months = max(0, ((today or date.today()) - _as_date(when)).days // 30);
        return f"- Raised: {what}, announced {when} (about {months} month(s) ago), as their own site says";
    }
    if recency == "old" {
        return f"- Raised: {what}, announced {when}, as their own site says. That is over 18 months ago, so not recent: don't write as if they just raised";
    }
    return f"- Raised: {what}, as their own site says, but no date was found: don't call it recent";
}

async def _read(state: any, name: str, company_id: str) -> any {
    lookup = getattr(state, name, None);
    try {
        return None if lookup is None else await lookup(company_id);
    } except Exception {
        return None;
    }
}

async def startup_facts(state: any, company_id: str, today: date | None = None) -> list[str]
    | None {
    if not company_id or state is None {
        return None;
    }
    facts: list[str] = [];
    yc = await _read(state, "yc_batch", company_id);
    if yc is not None {
        batch = f" (YC {yc})" if yc else "";
        facts.append(f"- Backed by Y Combinator{batch}, as their own site says");
    }
    program = await _read(state, "accelerator", company_id);
    if program is not None {
        facts.append(
            f"- Went through an accelerator: {program}, as their own site says"
                if program
                else "- Went through a startup accelerator (a search matched it on their own site)",
        );
    }
    funding = await _read(state, "funding_round", company_id);
    recent = funding is not None and funding_recency(funding["date"], today) == "recent";
    if not facts and not recent {
        return None;
    }
    return facts + [_funding_fact(funding, today)] if funding is not None else facts;
}
