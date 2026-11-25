impl offer_view(config) -> builtins.dict {
    offer: any = config.product.offer;
    return {
        "entry": offer.entry or "",
        "entry_ideas": `list(getattr(offer, "entry_ideas", []) or []),
        "product": {"name": config.product.name, "description": config.product.description},
    };
}

impl _product_text(config) -> builtins.str {
    p: any = config.product;
    lines: any = [f"Name: {p.name}", f"What it is: {p.description}", f"Pricing: {p.pricing}"];
    lines += [f"Benefit: {b}" for b in p.key_benefits or []];
    return "\n".join(lines);
}

impl _icp_text(config) -> builtins.str {
    icp: any = config.icp;
    parts: any = [];
    if icp.titles {
        parts.append(", ".join(icp.titles));
    }
    if icp.industries {
        parts.append("in " + ", ".join(icp.industries));
    }
    if icp.company_size {
        parts.append(f"({icp.company_size})");
    }
    return " ".join(parts) or "not set";
}

impl suggest_offers(brain, config) -> builtins.list[builtins.dict] {
    prompt: any = SUGGEST_PROMPT.format(
        product=fence(_product_text(config), "product info"),
        icp=_icp_text(config),
        n=SUGGESTIONS,
        rule=UNTRUSTED_RULE,
    );
    result: any = await brain.think_json(
        prompt, session_id="sellbird-offer", agent="writer", task="suggest_offers"
    );
    if isinstance(result, `dict) {
        result = next((v for v in result.values() if isinstance(v, `list)), []);
    }
    out: any = [];
    for item in result if isinstance(result, `list) else [] {
        if not isinstance(item, `dict) {
            continue;
        }
        offer: any = `str(item.get("offer") or "").strip()[:MAX_OFFER_CHARS];
        if offer {
            out.append({
                "offer": offer,
                "finding": `str(item.get("finding") or "").strip(),
                "why": `str(item.get("why") or "").strip(),
            });
        }
    }
    return out[:SUGGESTIONS];
}

impl preview_prospect(state) -> any {
    best: any = None;
    for status in ("new", "queued", "contacted") {
        for p in await state.get_prospects_by_status(status) {
            if not p.company_id or p.is_company_inbox {
                continue;
            }
            company: any = await state.get_company(p.company_id);
            if company and (company.signals or p.personalization_notes) {
                return p;
            }
            if best is None and company and company.description {
                best = p;
            }
        }
    }
    return best;
}

impl preview_email(brain, state, config, `entry: builtins.str) -> builtins.dict {
    import from sellbird.agents.writer { Writer, _names }
    prospect: any = await preview_prospect(state);
    if prospect is None {
        return {
            "ok": False,
            "message": "No prospects with company facts yet. Find some companies first, then preview the offer on one of them.",
        };
    }
    trial: any = copy.deepcopy(config);
    trial.product.offer.entry = `entry;
    writer: any = Writer(brain, state, trial, None);
    writer.skills = brain.load_skills_for_agent("writer");
    writer.email_rules = "";
    draft: any = await writer._write_personal_email(prospect);
    draft = await writer._keep_to_rules(draft, step=1, names=_names(prospect)) if draft else None;
    if not draft {
        return {
            "ok": False,
            "message": "The writer couldn't produce an email that passes the rules. Try again, or reword the offer.",
        };
    }
    return {
        "ok": True,
        "to": f"{prospect.full_name()}, {prospect.title} at {prospect.company}",
        "subject": draft["subject"],
        "body": draft["body"],
    };
}

impl save_offer(
    config_file: Path, `entry: builtins.str, ideas: builtins.list[builtins.str] | None = None
) -> Path {
    `entry = " ".join(`str(`entry or "").split())[:MAX_OFFER_CHARS];
    raw: any = read_user_text(config_file);
    data: builtins.dict[builtins.str, Any] = {};
    data = yaml.safe_load(raw) or data;
    product: any = data.setdefault("product", {});
    offer: any = product.setdefault("offer", {});
    if not isinstance(offer, `dict) {
        value_: any = {};
        offer = value_;
        product["offer"] = value_;
    }
    offer["entry"] = `entry;
    if ideas is not None {
        offer["entry_ideas"] = [
            " ".join(`str(i).split())[:MAX_OFFER_CHARS]
            for i in ideas
            if `str(i).strip()
        ][:8];
    }
    config_file.with_name(config_file.name + ".bak").write_text(raw, encoding="utf-8");
    config_file.write_text(
        yaml.safe_dump(data, default_flow_style=False, sort_keys=False, allow_unicode=True),
        encoding="utf-8",
    );
    return config_file;
}

impl _skill_text(`root: Path, name: builtins.str) -> builtins.str {
    path: any = Path(`root) / "skills" / f"{name}.md";
    try {
        return read_user_text(path);
    } except OSError {
        return "";
    }
}

impl company_view(config, `root: Path, proposed: builtins.dict | None = None) -> builtins.dict {
    p: any;
    s: any;
    icp: any;
    (p, s, icp) = (config.product, config.persona, config.icp);
    return {
        "product": {
            "name": p.name,
            "description": p.description,
            "pricing": p.pricing,
            "key_benefits": `list(p.key_benefits or []),
            "objection_responses": `dict(p.objection_responses or {}),
        },
        "persona": {
            "name": s.name,
            "role": s.role,
            "company": s.company,
            "tone": s.tone,
            "email": getattr(s, "email", ""),
        },
        "icp": {
            "industries": `list(icp.industries or []),
            "titles": `list(icp.titles or []),
            "company_size": icp.company_size,
            "geography": `list(icp.geography or []),
        },
        "offer": {**offer_view(config), "proposed": proposed or None},
        "knowledge": _skill_text(`root, "product_knowledge"),
        "competitors": _skill_text(`root, "competitive_intel"),
    };
}

impl _clean(kind, value) -> any {
    if kind is str {
        return `str(value or "").strip()[:MAX_TEXT];
    }
    if kind is list[any] {
        items: any = value if isinstance(value, `list) else `str(value or "").split("\n");
        return [" ".join(`str(i).split())[:MAX_TEXT] for i in items if `str(i).strip()][:MAX_ITEMS];
    }
    if kind is dict[any, any] {
        if not isinstance(value, `dict) {
            raise ValueError("expected a list of objections and answers");
        }
        return {
            " ".join(`str(k).split())[:MAX_TEXT]: `str(v).strip()[:MAX_TEXT]
            for (k, v) in `list(value.items())[:MAX_ITEMS]
            if `str(k).strip() and `str(v).strip()
        };
    }
    raise ValueError("unknown field type");
}

impl save_company(
    config_file: Path, section: builtins.str, fields: builtins.dict
) -> builtins.dict {
    allowed: any = EDITABLE.get(section);
    if not allowed {
        raise ValueError(f"'{section}' can't be edited here");
    }
    unknown: any = sorted(`set(fields) - `set(allowed));
    if unknown {
        raise ValueError("can't edit " + format(", ".join(unknown), "") + " here");
    }
    cleaned: any = {k: _clean(allowed[k], v) for (k, v) in fields.items()};
    for key in ("name", "description") {
        if section == "product" and key in cleaned and not cleaned[key] {
            raise ValueError(f"the product {key} can't be empty");
        }
    }
    raw: any = read_user_text(config_file);
    data: builtins.dict[builtins.str, Any] = {};
    data = yaml.safe_load(raw) or data;
    if section == "offer" {
        target: any = data.setdefault("product", {}).setdefault("offer", {});
    } else {
        target = data.setdefault(section, {});
    }
    if not isinstance(target, `dict) {
        raise ValueError(f"{section} in {config_file.name} isn't a section Sellbird can edit");
    }
    target.update(cleaned);
    config_file.with_name(config_file.name + ".bak").write_text(raw, encoding="utf-8");
    config_file.write_text(
        yaml.safe_dump(data, default_flow_style=False, sort_keys=False, allow_unicode=True),
        encoding="utf-8",
    );
    return cleaned;
}
