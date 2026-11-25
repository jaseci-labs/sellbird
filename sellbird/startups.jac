"""What Sellbird knows about a prospect's company as a startup.

Three profile signals mark one, each read off the company's own site:
YC_BACKED, ACCELERATOR, and a FUNDING_ROUND dated within the last 18
months. The writer and the reply handler use the founder playbook
(skills/selling_to_startups.md) for those, and these facts go into the
writer's prompt as they are. An old or undated raise alone doesn't make a
startup (a 2013 Series A, or a law firm's misread "$100M"), and "just
raised" is only an angle while it's true.
"""

import builtins;

import operator;

import re;

import from datetime { date }

glob FUNDING_RECENT_DAYS: any = 548;

glob _DATE_RE: any;

with entry {
    _DATE_RE = re.compile("^(\\d{4})(?:-(\\d{2}))?(?:-(\\d{2}))?$");
}

"""The FUNDING_ROUND value as stored: "Series A · $12M · 2025-03"."""
def funding_text(found: builtins.dict) -> builtins.str {
    return " · ".join(p for p in (found.get("round"), found.get("amount"), found.get("date")) if p);
}

"""funding_text, read back into its parts (any may be "")."""
def parse_funding(text: builtins.str) -> builtins.dict {
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

"""The earliest day a stated date could mean: "2025" is 1 January, so an
    imprecise date never makes a raise look newer than it is."""
def _as_date(when: builtins.str) -> date | None {
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

""""recent", "old" (over ~18 months) or "unknown" (no date found)."""
def funding_recency(when: builtins.str, today: date | None = None) -> builtins.str {
    day: any = _as_date(when);
    if day is None {
        return "unknown";
    }
    return "recent" if ((today or date.today()) - day).days <= FUNDING_RECENT_DAYS else "old";
}

def _funding_fact(found: builtins.dict, today: date | None) -> builtins.str {
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

async def _read(state, name: builtins.str, company_id: builtins.str) -> any {
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

"""Fact lines for the writer's prompt when the company is a startup
    (YC, another accelerator, or a raise it announced in the last 18
    months), else None. A failed read is just "not known to be one", never
    a reason not to write."""
async def startup_facts(
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
