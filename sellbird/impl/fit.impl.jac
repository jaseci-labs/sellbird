impl _hiring_terms(icp) -> list[str] {
    return [t.strip().lower() for t in getattr(icp, "hiring_signals", None) or [] if t.strip()];
}

impl _role_matches(text: str, terms: list[str]) -> str {
    low: any = (text or "").lower();
    for term in terms {
        if re.search(f"(?<![\\w-]){re.escape(term)}(?![\\w-])", low) {
            return term;
        }
    }
    return "";
}

impl current_roles(observations: list[dict]) -> list[dict] {
    roles: any = sorted(
        (o for o in observations if o.get("signal_code") == "HIRING_ROLE"),
        key=lambda (o) -> any { o.get("observed_at") or "" },
    );
    closed: any = [
        i
        for (i, o) in enumerate(roles)
        if o.get("value_num") == 0 and not (o.get("value_text") or "").strip()
    ];
    return roles[closed[-1]:] if closed else roles;
}

impl company_fit(
    company: dict,
    prospects: list[dict],
    observations: list[dict],
    config,
    dnc: list[str] | None = None,
) -> tuple[int, list[str]] {
    terms: any;
    icp: any = config.icp;
    if dnc is None {
        dnc = getattr(getattr(config, "compliance", None), "do_not_contact", None) or [];
    }
    domain: any = (company.get("domain") or "").lower();
    if domain and dnc and do_not_contact_match(f"x@{domain}", dnc) {
        return (0, ["on the do-not-contact list"]);
    }

    score: any;
    reasons: any;
    (score, reasons) = (0, []);

    industries: any = {i.strip().lower() for i in icp.industries or []};
    if (company.get("industry") or "").strip().lower() in industries {
        score += SECTOR;
        reasons.append("sector: " + format(company["industry"], ""));
    }
    live: any = [
        p
        for p in prospects
        if (p.get("status") or "") not in DEAD_STATUSES
            and not (dnc and p.get("email") and do_not_contact_match(p["email"], dnc))
    ];
    named: any = [p for p in live if (p.get("first_name") or "").strip()];
    makers: any = [
        p
        for p in named
        if icp.titles and title_matches(p.get("title") or "", icp.titles)
    ];
    if not makers {
        for o in observations {
            if o.get("signal_code") == "DECISION_MAKER_TITLE" {
                title: any = (o.get("value_text") or "").split("—", 1)[-1].strip(" ~()");
                if icp.titles and title_matches(title, icp.titles) {
                    makers.append({"title": title, "first_name": ""});
                    break;
                }
            }
        }
    }
    if makers {
        score += DECISION_MAKER;
        reasons.append("decision maker: " + format(makers[0].get("title"), ""));
    } elif named {
        score += DECISION_MAKER // 2;
        reasons.append("named contact (not a target title)");
    } elif live {
        score += 5;
        reasons.append("general inbox only");
    }

    best: any = max(
        (EMAIL_POINTS.get((p.get("email_status") or "").lower(), 0) for p in live), default=0
    );
    if best {
        score += best;
        label: any = {25: "verified email", 12: "risky email", 5: "guessed email"}[best];
        reasons.append(label);
    } elif `any(operator.eq(o.get("signal_code"), "CONTACT_FORM_URL") for o in observations) {
        score += 5;
        reasons.append("contact form only");
    } else {
        reasons.append("no way to reach yet");
    }

    terms = _hiring_terms(icp);
    roles: any = current_roles(observations);
    hit: any = next((m for m in (_role_matches(o.get("value_text"), terms) for o in roles) if m), "");
    if hit {
        score += BUYING;
        reasons.append(f"hiring: {hit}");
    } elif roles {
        score += 5;
        reasons.append("careers page, no matching role");
    }

    return (min(score, 100), reasons);
}
