import re;

glob SECTOR = 20,
     DECISION_MAKER = 30,
     REACHABLE = 25,
     BUYING = 25,
     EMAIL_POINTS = {"verified": 25, "risky": 12, "guess": 5},
     DEAD_STATUSES = {"lost", "opted_out"};

def _hiring_terms(icp: any) -> list[str] {
    return [t.strip().lower() for t in getattr(icp, "hiring_signals", None) or [] if t.strip()];
}

def _role_matches(text: str, terms: list[str]) -> str {
    low = (text or "").lower();
    return next((t for t in terms if re.search(f"(?<![\\w-]){re.escape(t)}(?![\\w-])", low)), "");
}

def current_roles(observations: list[dict[str, any]]) -> list[dict[str, any]] {
    roles = sorted(
        [o for o in observations if o.get("signal_code") == "HIRING_ROLE"],
        key=lambda (o: any) -> any { o.get("observed_at") or "" },
    );
    closed = [
        i
        for (i, o) in enumerate(roles)
        if o.get("value_num") == 0 and not (o.get("value_text") or "").strip()
    ];
    return roles[closed[-1]:] if closed else roles;
}

def company_fit(
    company: dict[str, any],
    prospects: list[dict[str, any]],
    observations: list[dict[str, any]],
    config: any,
    dnc: list[str] | None = None,
) -> tuple[int, list[str]] {
    icp = config.icp;
    if dnc is None {
        dnc = getattr(getattr(config, "compliance", None), "do_not_contact", None) or [];
    }
    domain = (company.get("domain") or "").lower();
    if domain and dnc and do_not_contact_match(f"x@{domain}", dnc) {
        return (0, ["on the do-not-contact list"]);
    }
    found: list[tuple[int, str]] = [];
    industries = {i.strip().lower() for i in icp.industries or []};
    if (company.get("industry") or "").strip().lower() in industries {
        found.append((SECTOR, f"sector: {company['industry']}"));
    }
    live = [
        p
        for p in prospects
        if (p.get("status") or "") not in DEAD_STATUSES
            and not (dnc and p.get("email") and do_not_contact_match(p["email"], dnc))
    ];
    named = [p for p in live if (p.get("first_name") or "").strip()];
    makers = [p for p in named if icp.titles and title_matches(p.get("title") or "", icp.titles)];
    if not makers and icp.titles {
        seen = [
            (o.get("value_text") or "").split("—", 1)[-1].strip(" ~()")
            for o in observations
            if o.get("signal_code") == "DECISION_MAKER_TITLE"
        ];
        makers = [{"title": t} for t in seen if title_matches(t, icp.titles)][:1];
    }
    if makers {
        found.append((DECISION_MAKER, f"decision maker: {makers[0].get('title')}"));
    } elif named {
        found.append((DECISION_MAKER // 2, "named contact (not a target title)"));
    } elif live {
        found.append((5, "general inbox only"));
    }
    best = max([EMAIL_POINTS.get((p.get("email_status") or "").lower(), 0) for p in live] + [0]);
    if best {
        found.append((best, {25: "verified email", 12: "risky email", 5: "guessed email"}[best]));
    } elif "CONTACT_FORM_URL" in [o.get("signal_code") for o in observations] {
        found.append((5, "contact form only"));
    } else {
        found.append((0, "no way to reach yet"));
    }
    roles = current_roles(observations);
    hits = [_role_matches(o.get("value_text"), _hiring_terms(icp)) for o in roles];
    hit = next((m for m in hits if m), "");
    if hit {
        found.append((BUYING, f"hiring: {hit}"));
    } elif roles {
        found.append((5, "careers page, no matching role"));
    }
    return (min(sum([f[0] for f in found]), 100), [f[1] for f in found]);
}
