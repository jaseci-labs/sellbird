impl humanizer_enabled(config) -> builtins.bool {
    return `bool(getattr(getattr(config, "writer", None), "humanizer", False));
}

impl load_skill(path: Path | None = None) -> builtins.str {
    try {
        text: any = read_user_text(path or SKILL_PATH);
    } except OSError {
        return "";
    }
    if text.startswith("---") {
        end: any = text.find("\n---", 3);
        if end != -1 {
            text = text[end + 4:];
        }
    }
    return text.strip();
}

impl _acceptable(original: builtins.dict, rewrite) -> builtins.bool {
    if not isinstance(rewrite, `dict) {
        return False;
    }
    body: any = `str(rewrite.get("body") or "").strip();
    subject: any = `str(rewrite.get("subject") or "").strip();
    if not body or original.get("subject") and not subject {
        return False;
    }
    if body.lower().startswith(META_PREFIXES) {
        return False;
    }
    before: any = original.get("subject", "") + original["body"];
    after: any = subject + body;
    if sorted(MERGE_VAR.findall(before)) != sorted(MERGE_VAR.findall(after)) {
        return False;
    }
    if "—" in after and "—" not in before {
        return False;
    }
    return operator.le(len(body.split()), len(original["body"].split()) + MAX_GROWTH_WORDS);
}

impl humanize(
    brain,
    drafts: builtins.list[builtins.dict],
    agent: builtins.str,
    path: Path | None = None,
    enabled: builtins.bool = False,
) -> builtins.list[builtins.dict] {
    if not enabled or not drafts {
        return drafts;
    }
    skill: any = load_skill(path);
    if not skill {
        return drafts;
    }

    out: any = [await _humanize_one(brain, skill, draft, agent) for draft in drafts];
    kept: any = sum(1 for (a, b) in zip(drafts, out) if a is b);
    if kept {
        logger.info(f"Humanizer: kept {kept} of {len(drafts)} draft(s) unchanged after checks.");
    }
    return out;
}

impl _humanize_one(
    brain, skill: builtins.str, draft: builtins.dict, agent: builtins.str
) -> builtins.dict {
    payload: any = {"subject": draft.get("subject", ""), "body": draft["body"]};
    prompt: any = format(skill, "")
        + "\n\n---\n\nApply the Humanizer instructions above to the cold-email draft below. It is\na short plain-text business email, so return email text only.\n\nHard limits on the rewrite, on top of the instructions above:\n- Keep every merge variable such as {{first_name}} or {{company}} exactly as written.\n- Add no fact, name, number or claim that is not already in the draft.\n- No em dashes, no bullets, no bold, no exclamation marks.\n- Do not make the email longer. Keep exactly one question.\n- The subject stays lowercase, 2-5 words. An empty subject stays empty.\n\nDraft:\n"
        + format(fence(json.dumps(payload, ensure_ascii=False, indent=2), "draft"), "")
        + "\n\n"
        + format(UNTRUSTED_RULE, "")
        + "\n\nReturn ONLY a JSON object: {\"subject\": \"...\", \"body\": \"...\"}";

    try {
        rewrite: any = await brain.think_json(
            prompt, session_id="sellbird-humanizer", agent=agent, task="humanize"
        );
    } except Exception as e {
        logger.warning(f"Humanizer pass failed, keeping draft: {e}");
        return draft;
    }
    if not _acceptable(draft, rewrite) {
        return draft;
    }
    return {
        **draft,
        "subject": `str(rewrite.get("subject") or "").strip(),
        "body": `str(rewrite["body"]).strip(),
    };
}
