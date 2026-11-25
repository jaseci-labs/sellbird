import builtins;
import copy;
import logging;
import from pathlib { Path }
import yaml;

glob logger = logging.getLogger("sellbird.offer"),
     MAX_OFFER_CHARS = 300,
     SUGGESTIONS = 4,
     SUGGEST_PROMPT = "You help a business design the offer at the end of its cold emails.\n\nThe business:\n{product}\n\nWho it emails: {icp}\n\nA first email names one finding about the prospect (where they rank on Google,\nwhat their website lacks, a role they're hiring for, their reviews), says what\nthat costs them, and ends by offering one free, useful thing as the next step to\nfix it. Suggest {n} offers for this business. Each must be:\n- tied to a finding Sellbird can really see about a prospect (search rank, the\n  website, job posts, reviews, tools on the site, funding news);\n- specific and valuable on its own, so saying yes costs nothing (\"a written plan\n  for getting you onto page one\", \"a mockup of your homepage with online\n  booking\", \"a two-week trial answering your after-hours calls\");\n- something this business can deliver quickly after a yes;\n- never a discount, a generic call or a demo.\n\n{rule}\n\nReturn ONLY a JSON array of {n} objects:\n[{{\"offer\": \"the offer in a few words, as it would be written in the email\",\n   \"finding\": \"the kind of finding it pairs with\",\n   \"why\": \"one sentence on why a prospect would say yes\"}}]",
     PROPOSED_KEY = "offer_proposed",
     EDITABLE = {
         "product": builtins.dict.fromkeys(["name", "description", "pricing"], str) | {
             "key_benefits": builtins.list,
             "objection_responses": builtins.dict,
         },
         "persona": builtins.dict.fromkeys(["name", "role", "tone"], str),
         "icp": builtins.dict.fromkeys(["industries", "titles"], builtins.list) | {
             "company_size": str,
             "geography": builtins.list,
         },
         "offer": {"entry": str},
     },
     MAX_TEXT = 2000,
     MAX_ITEMS = 30,
     _NO_PROSPECT = "No prospects with company facts yet. Find some companies first, then preview the offer on one of them.",
     _NO_DRAFT = "The writer couldn't produce an email that passes the rules. Try again, or reword the offer.";

def offer_view(config: any) -> dict[str, any] {
    offer = config.product.offer;
    return {
        "entry": offer.entry or "",
        "entry_ideas": list(getattr(offer, "entry_ideas", []) or []),
        "product": {"name": config.product.name, "description": config.product.description},
    };
}

def _product_text(config: any) -> str {
    p = config.product;
    lines = [f"Name: {p.name}", f"What it is: {p.description}", f"Pricing: {p.pricing}"];
    return "\n".join(lines + [f"Benefit: {b}" for b in p.key_benefits or []]);
}

def _icp_text(config: any) -> str {
    icp = config.icp;
    parts = [
        ", ".join(icp.titles) if icp.titles else "",
        "in " + ", ".join(icp.industries) if icp.industries else "",
        f"({icp.company_size})" if icp.company_size else "",
    ];
    return " ".join([x for x in parts if x]) or "not set";
}

def _suggestion(item: dict[str, any]) -> dict[str, any] {
    (offer, finding, why) = [str(item.get(k) or "").strip() for k in ("offer", "finding", "why")];
    return {"offer": offer[:MAX_OFFER_CHARS], "finding": finding, "why": why};
}

async def suggest_offers(brain: any, config: any) -> list[dict[str, any]] {
    prompt = SUGGEST_PROMPT.format(
        product=fence(_product_text(config), "product info"),
        icp=_icp_text(config),
        n=SUGGESTIONS,
        rule=UNTRUSTED_RULE,
    );
    result = await brain.think_json(
        prompt, session_id="sellbird-offer", agent="writer", task="suggest_offers"
    );
    if isinstance(result, dict) {
        result = next((v for v in result.values() if isinstance(v, list)), []);
    }
    items = result if isinstance(result, list) else [];
    out = [_suggestion(i) for i in items if isinstance(i, dict)];
    return [o for o in out if o["offer"]][:SUGGESTIONS];
}

async def preview_prospect(state: any) -> any {
    best: any = None;
    for status in ("new", "queued", "contacted") {
        for p in await state.get_prospects_by_status(status) {
            if not p.company_id or p.is_company_inbox {
                continue;
            }
            company = await state.get_company(p.company_id);
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

async def preview_email(brain: any, state: any, config: any, `entry: str) -> dict[str, any] {
    import from sellbird.agents.writer { Writer, _names }
    prospect = await preview_prospect(state);
    if prospect is None {
        return {"ok": False, "message": _NO_PROSPECT};
    }
    trial = copy.deepcopy(config);
    trial.product.offer.entry = `entry;
    writer = Writer(brain, state, trial, None);
    writer.skills = brain.load_skills_for_agent("writer");
    writer.email_rules = "";
    draft = await writer._write_personal_email(prospect);
    draft = await writer._keep_to_rules(draft, step=1, names=_names(prospect)) if draft else None;
    if not draft {
        return {"ok": False, "message": _NO_DRAFT};
    }
    to = f"{prospect.full_name()}, {prospect.title} at {prospect.company}";
    return {"ok": True, "to": to, "subject": draft["subject"], "body": draft["body"]};
}

def _load(config_file: Path) -> tuple[str, any] {
    raw = read_user_text(config_file);
    empty: dict[str, any] = {};
    return (raw, yaml.safe_load(raw) or empty);
}

def _store(config_file: Path, raw: str, data: dict[str, any]) {
    config_file.with_name(config_file.name + ".bak").write_text(raw, encoding="utf-8");
    dumped = yaml.safe_dump(data, default_flow_style=False, sort_keys=False, allow_unicode=True);
    config_file.write_text(dumped, encoding="utf-8");
}

def _squash(text: any, limit: int) -> str {
    return " ".join(str(text).split())[:limit];
}

def save_offer(config_file: Path, `entry: str, ideas: list[str] | None = None) -> Path {
    (raw, data) = _load(config_file);
    product = data.setdefault("product", {});
    offer = product.setdefault("offer", {});
    if not isinstance(offer, dict) {
        offer = product["offer"] = {};
    }
    offer["entry"] = _squash(`entry or "", MAX_OFFER_CHARS);
    if ideas is not None {
        offer["entry_ideas"] = [_squash(i, MAX_OFFER_CHARS) for i in ideas if str(i).strip()][:8];
    }
    _store(config_file, raw, data);
    return config_file;
}

def _skill_text(top: Path, name: str) -> str {
    try {
        return read_user_text(Path(top) / "skills" / f"{name}.md");
    } except OSError {
        return "";
    }
}

def _fields(source: any, kinds: dict[str, any]) -> dict[str, any] {
    return {
        f: getattr(source, f) if k is str else k(getattr(source, f) or k())
        for (f, k) in kinds.items()
    };
}

def company_view(config: any, `root: Path, proposed: any = None) -> dict[str, any] {
    s = config.persona;
    return {
        "product": _fields(config.product, EDITABLE["product"]),
        "persona": {f: getattr(s, f) for f in ("name", "role", "company", "tone")} | {
            "email": getattr(s, "email", ""),
        },
        "icp": _fields(config.icp, EDITABLE["icp"]),
        "offer": {**offer_view(config), "proposed": proposed or None},
        "knowledge": _skill_text(`root, "product_knowledge"),
        "competitors": _skill_text(`root, "competitive_intel"),
    };
}

def _clean(kind: any, value: any) -> any {
    if kind is str {
        return str(value or "").strip()[:MAX_TEXT];
    }
    if kind is builtins.list {
        items = value if isinstance(value, list) else str(value or "").split("\n");
        return [_squash(i, MAX_TEXT) for i in items if str(i).strip()][:MAX_ITEMS];
    }
    if not isinstance(value, dict) {
        raise ValueError("expected a list of objections and answers");
    }
    return {
        _squash(k, MAX_TEXT): str(v).strip()[:MAX_TEXT]
        for (k, v) in list(value.items())[:MAX_ITEMS]
        if str(k).strip() and str(v).strip()
    };
}

def save_company(config_file: Path, section: str, fields: dict[str, any]) -> dict[str, any] {
    allowed = EDITABLE.get(section);
    if not allowed {
        raise ValueError(f"'{section}' can't be edited here");
    }
    unknown = sorted([k for k in fields if k not in allowed]);
    if unknown {
        raise ValueError(f"can't edit {', '.join(unknown)} here");
    }
    cleaned = {k: _clean(allowed[k], v) for (k, v) in fields.items()};
    for key in ("name", "description") {
        if section == "product" and key in cleaned and not cleaned[key] {
            raise ValueError(f"the product {key} can't be empty");
        }
    }
    (raw, data) = _load(config_file);
    target = data.setdefault("product", {}).setdefault("offer", {})
        if section == "offer"
        else data.setdefault(section, {});
    if not isinstance(target, dict) {
        raise ValueError(f"{section} in {config_file.name} isn't a section Sellbird can edit");
    }
    target.update(cleaned);
    _store(config_file, raw, data);
    return cleaned;
}
