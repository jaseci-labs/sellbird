impl _sections(markdown: str) -> dict[str, str] {
    parts = re.split(r"^(#.*)$", markdown, flags=re.M);
    return {parts[i].strip(): parts[i + 1].strip() for i in range(1, len(parts), 2)};
}

impl _names(prospect: any) -> list[str] {
    fields = ("company", "first_name", "last_name", "title");
    return [n for n in (getattr(prospect, f, "") for f in fields) if n];
}

impl _fields(result: any) -> tuple[str, str] | None {
    if not isinstance(result, dict) {
        return None;
    }
    subject = str(result.get("subject") or "").strip();
    body = str(result.get("body") or "").strip();
    return (subject, body) if subject and body else None;
}

impl operator_rules_block(rules: str) -> str {
    if not rules {
        return "";
    }
    return "\n\nOPERATOR'S EMAIL RULES, written by the person running Sellbird. For\n"
        "length, structure, what to say about the product, links, subject lines\n"
        "and sign-off, these replace the STRICT EMAIL RULES and skills above\n"
        "wherever the two disagree. They never override the FACTS rule: what you\n"
        "say about the prospect comes only from the facts given, never invented.\n"
        "Nor do they allow a fake \"Re:\" or \"Fwd:\" subject line, or a claim of a\n"
        "conversation that never happened.\n"
        + rules;
}

impl offer_block(config: any) -> str {
    offer = getattr(getattr(config, "product", None), "offer", None);
    offered = str(getattr(offer, "entry", "") or "").strip();
    if not offered {
        return "\n\nYOUR OFFER: none set (product.offer.entry). End email 1 with one easy\n"
            "question about the problem you found instead.";
    }
    return f"\n\nYOUR OFFER for a first email: {offered}\n"
        "Something free and useful you can really deliver. Email 1 offers it as the one\n"
        "question, tied to what you found about them, in a few plain words. Offer only\n"
        "this, as it's written here: don't say you already made or did something unless\n"
        "it says so, and never promise anything else.";
}

impl footer_rule(config: any, rules: str) -> str {
    if not rules {
        return BUILT_IN_FOOTER;
    }
    compliance = compliance_of(config);
    lines: list[str] = [];
    if compliance.postal_address.strip() {
        lines.append("- No postal address: Sellbird adds it under the email when it sends.");
    }
    opt_out = compliance.opt_out_line.strip();
    if opt_out {
        lines.append(
            f"- Sellbird adds this opt-out line under the email when it sends: \"{opt_out}\".\n"
                "  Don't write another way to opt out, even if the operator's rules give one.",
        );
    } else {
        lines.append(
            "- Sellbird adds no opt-out line. If the operator's rules give a sentence that\n"
                "  lets the reader say no, write it into the body as they say.",
        );
    }
    return "\n".join(lines);
}

impl Writer.init(brain: Brain, state: StateManager, config: SellbirdConfig, env: any = None) {
    self.brain = brain;
    self.state = state;
    self.config = config;
    self.env = env;
}

impl Writer.is_native -> bool {
    return self.config.channels.email.provider in NATIVE_PROVIDERS;
}

impl Writer.run {
    logger.info("Writer: Crafting email campaigns...");
    self.skills = self.brain.load_skills_for_agent("writer");
    if not current_home().hosted {
        try {
            self.config.product.offer = load_config().product.offer;
        } except Exception {}
    }
    try {
        self.email_rules = load_email_rules(self.config);
    } except EmailRulesError as e {
        logger.warning(
            f"Writer: your email rules (writer.email_rules) can't be used: {e}. "
                "Writing nothing until that's fixed.",
        );
        await self.state.set_setting(EMAIL_RULES_PROBLEM_KEY, str(e));
        return;
    }
    if await self.state.get_setting(EMAIL_RULES_PROBLEM_KEY) {
        await self.state.delete_setting(EMAIL_RULES_PROBLEM_KEY);
    }
    new_prospects = await self.state.get_prospects_by_status("new");
    if not new_prospects {
        logger.info("Writer: No new prospects to write for.");
        return;
    }
    candidates: list[any] = [];
    for p in new_prospects {
        if p.email
            and (p.email_status or "guess") in WRITABLE_EMAIL_STATUSES
            and not await self.state.colleague_who_replied(p.id)
        {
            candidates.append(p);
        }
    }
    if not candidates {
        logger.info("Writer: No prospects with deliverable (verified/risky) emails yet.");
        return;
    }
    email = getattr(getattr(self.config, "channels", None), "email", None);
    try {
        min_score = max(0, int(getattr(email, "min_write_score", 0) or 0));
    } except (TypeError, ValueError) {
        min_score = 0;
    }
    if min_score > 0 {
        kept = [p for p in candidates if (p.score or 0) >= min_score];
        if len(candidates) > len(kept) {
            logger.info(
                f"Writer: Skipping {len(candidates) - len(kept)} prospect(s) scored below "
                    f"channels.email.min_write_score ({min_score}).",
            );
        }
        candidates = kept;
        if not candidates {
            logger.info("Writer: No prospects at or above the minimum score.");
            return;
        }
    }
    if getattr(getattr(self.config, "writer", None), "require_tip", False) {
        kept = [];
        for p in candidates {
            if await self._has_tip_basis(p) {
                kept.append(p);
            } else {
                await self.state.update_prospect_status(p.id, NO_TIP_STATUS);
            }
        }
        if len(candidates) > len(kept) {
            logger.info(
                f"Writer: Not writing for {len(candidates) - len(kept)} prospect(s) with nothing concrete "
                    f"to build a tip on (writer.require_tip); marked {NO_TIP_STATUS}.",
            );
        }
        candidates = kept;
        if not candidates {
            return;
        }
    }
    for (batch_name, prospects) in self._group_prospects(candidates).items() {
        logger.info(f"Writer: Creating campaign '{batch_name}' for {len(prospects)} prospects.");
        self._no_reply = False;
        sequence = await self._write_sequence(prospects);
        if not sequence {
            paused = getattr(self.brain, "paused_reason", "")
                or ("no reply from the model" if self._no_reply else "");
            if paused {
                logger.warning(f"Writer: {paused}; leaving '{batch_name}' for later.");
                return;
            }
            logger.warning(f"Writer: Failed to generate sequence for {batch_name}");
            await self._count_failed_attempt(batch_name, prospects);
            continue;
        }
        campaign_id = await self.state.add_campaign(
            Campaign(
                id="",
                name=batch_name,
                channel="email",
                sequence=sequence,
                prospect_ids=[p.id for p in prospects],
                status="draft",
            ),
        );
        for p in prospects {
            await self.state.queue_prospect_if_unsent(p.id);
            await self.state.delete_setting(WRITE_ATTEMPTS_KEY + p.id);
        }
        if self.is_native {
            await self._personalize_first_emails(campaign_id, prospects);
        }
        await self.state.log_action(
            action_type="write_campaign",
            agent="writer",
            details={
                "campaign_id": campaign_id,
                "campaign_name": batch_name,
                "prospect_count": len(prospects),
                "steps": len(sequence),
            },
        );
        logger.info(
            f"Writer: Campaign '{batch_name}' created with {len(sequence)} emails for {len(prospects)} prospects.",
        );
    }
}

impl Writer._site_facts(company_id: any) -> list[str] {
    if not getattr(getattr(self.config, "writer", None), "site_facts", True) {
        return [];
    }
    return await site_facts(vars(self).get("state"), company_id);
}

impl Writer._has_tip_basis(prospect: any) -> bool {
    if (prospect.personalization_notes or "").strip()
        or await self._site_facts(prospect.company_id)
        or await self._startup(prospect.company_id)
    {
        return True;
    }
    company = await self._company(prospect.company_id);
    return bool(company and company.signals);
}

impl Writer._company(company_id: any) -> any {
    try {
        return await self.state.get_company(company_id) if company_id else None;
    } except Exception {
        return None;
    }
}

impl Writer._count_failed_attempt(batch_name: str, prospects: list[any]) {
    given_up: list[str] = [];
    for p in prospects {
        key = WRITE_ATTEMPTS_KEY + p.id;
        try {
            attempts = int(await self.state.get_setting(key) or 0) + 1;
        } except ValueError {
            attempts = 1;
        }
        if attempts >= MAX_WRITE_ATTEMPTS {
            await self.state.update_prospect_status(p.id, "write_failed");
            await self.state.delete_setting(key);
            given_up.append(p.email);
        } else {
            await self.state.set_setting(key, str(attempts));
        }
    }
    if given_up {
        await self.state.log_action(
            action_type="write_failed",
            agent="writer",
            details={
                "campaign_name": batch_name,
                "prospects": given_up,
                "attempts": MAX_WRITE_ATTEMPTS,
            },
        );
        logger.warning(
            f"Writer: Gave up on {len(given_up)} prospect(s) in '{batch_name}' after "
                f"{MAX_WRITE_ATTEMPTS} unusable drafts; marked write_failed.",
        );
    }
}

impl Writer._personalize_first_emails(campaign_id: str, prospects: list[any]) {
    await sync_sending_mode(self.config, self.state);
    require_approval = getattr(self.config.channels.email, "require_approval", True);
    now = datetime.now(timezone.utc).replace(tzinfo=None).isoformat();
    pending: list[any] = [];
    for prospect in prospects {
        try {
            draft = await self._write_personal_email(prospect);
        } except Exception as e {
            logger.warning(f"Writer: personal draft failed for {prospect.email}: {e}");
            continue;
        }
        if draft {
            pending.append((prospect, draft));
        }
    }
    polished = await humanize(
        self.brain,
        [d for (_, d) in pending],
        agent="writer",
        enabled=humanizer_enabled(self.config),
    );
    drafted = 0;
    for ((prospect, _), draft) in zip(pending, polished) {
        draft = await self._keep_to_rules(draft, step=1, names=_names(prospect));
        if draft is not None
            and await self.state.add_outbox_item(
                prospect_id=prospect.id,
                campaign_id=campaign_id,
                step=1,
                to_email=prospect.email,
                subject=draft["subject"],
                body=draft["body"],
                send_at=now,
                status="pending_review" if require_approval else "approved",
                provider=self.config.channels.email.provider,
                approved_by="" if require_approval else "autopilot",
            )
        {
            drafted += 1;
        }
    }
    if drafted {
        logger.info(
            f"Writer: drafted {drafted} personalized first email(s) ({'awaiting approval' if require_approval else 'approved'}).",
        );
    }
}

impl Writer._startup(company_id: any) -> any {
    return await startup_facts(vars(self).get("state"), company_id);
}

impl Writer._signal_guide(facts: str) -> str {
    load = getattr(self.brain, "load_skill", None);
    text = load("signal_playbook") if load else "";
    if not isinstance(text, str) or not text.strip() {
        return "";
    }
    sections = _sections(text);
    low = facts.lower();
    wanted = ["## The core rule"] + [
        h
        for (heading, words) in _SIGNAL_SECTIONS.items()
        if re.search(words, low)
        for h in sections
        if h.startswith(heading)
    ];
    if len(wanted) == 1 {
        wanted.append("## When you have no real signal");
    }
    body = "\n\n".join(f"{h}\n{sections[h]}" for h in dict.fromkeys(wanted) if h in sections);
    body = body.replace(" — ", ", ").replace("—", ", ");
    return "\n\nUSING THEIR SIGNAL\n" + body if body else "";
}

impl Writer._guidance(facts: str, startup: bool, prospect_ids: list[str]) -> str {
    text = "\n\n" + self.skills if self.skills else "";
    text += self._signal_guide(facts);
    if startup {
        playbook = self.brain.load_skill("selling_to_startups")
            if hasattr(self.brain, "load_skill")
            else "";
        text += "\n\nSELLING TO STARTUP FOUNDERS\n" + playbook if playbook else "";
    }
    try {
        notes = await self.state.get_writing_feedback(prospect_ids);
    } except Exception as e {
        logger.warning(f"Writer: could not read feedback: {e}");
        notes = [];
    }
    if notes {
        text += "\n\nOWNER FEEDBACK: notes the person running Sellbird left on earlier\n"
            "campaigns and contacts, newest first (a newer note wins). Apply them to\n"
            "this writing. They never override the STRICT EMAIL RULES or the FACTS rule:\n"
            + "\n".join(
                f"- {str(n.get('created_at') or '')[:10]} on {n['about']}: {' '.join(str(n['comment']).split())[:500]}"
                for n in notes,
            );
    }
    return text + offer_block(self.config) + operator_rules_block(getattr(self, "email_rules", ""));
}

impl Writer._base_prompt -> str {
    (product, persona) = (self.config.product, self.config.persona);
    return self.brain.load_prompt(
        "writer",
        product_name=product.name,
        product_description=product.description,
        product_benefits="\n".join(f"- {b}" for b in product.key_benefits),
        product_pricing=product.pricing,
        persona_name=persona.name,
        persona_company=persona.company,
        persona_role=persona.role,
        persona_tone=persona.tone,
    );
}

impl Writer._write_personal_email(prospect: any) -> dict[str, any] | None {
    if prospect.is_company_inbox {
        facts = [
            f"- Name: unknown (the company's general inbox, {prospect.email})",
            f"- Company: {prospect.company}",
        ];
        inbox_rule = "\n- This goes to the company's general inbox, most likely read by the owner"
            "\n  or the office manager. Use no first name; open with 'Hi there' or"
            "\n  address the company's team.";
    } else {
        facts = [
            f"- Name: {prospect.full_name()}",
            f"- Title: {prospect.title}",
            f"- Company: {prospect.company}",
        ];
        inbox_rule = "";
    }
    company = await self._company(prospect.company_id);
    known = [("Industry", prospect.industry)];
    if company {
        known += [
            ("Location", company.location),
            ("What the company says about itself", company.description),
        ];
    }
    facts += [f"- {label}: {value}" for (label, value) in known if value];
    if company and company.tech_stack {
        facts.append(f"- Tools detected on their website: {', '.join(company.tech_stack[:6])}");
    }
    for signal in company.signals[:3] if company else [] {
        facts.append(f"- Signal ({signal.get('type', 'signal')}): {signal.get('detail', '')}");
    }
    facts += await self._site_facts(prospect.company_id);
    if prospect.personalization_notes {
        facts.append(f"- Research notes: {prospect.personalization_notes}");
    }
    startup = await self._startup(prospect.company_id);
    facts += startup or [];
    prompt = (self._base_prompt() or "")
        + await self._guidance("\n".join(facts), startup is not None, [prospect.id]);
    rules = getattr(self, "email_rules", "");
    if rules {
        shape = "- Follow the OPERATOR'S EMAIL RULES above for this first email: its length,\n"
            "  structure, what it says about the product, links and subject line.\n"
            "- Write the actual text (no merge variables: you know their name/company).";
        strict = "- Follow every STRICT EMAIL RULE above that the operator's rules don't replace.";
    } else {
        shape = PERSONAL_SHAPE;
        strict = "- Follow every STRICT EMAIL RULE above.";
    }
    research = fence("\n".join(facts), "prospect research");
    footer = footer_rule(self.config, rules);
    prompt += f"""

Write ONE cold email (the very first touch) to this specific person.

FACTS: everything you know about them, gathered from their website and
the web. Every claim about the prospect in your email must come from these
facts. If a fact isn't listed here, you don't know it. Do not invent
funding rounds, mutual contacts, metrics, or anything else:
{research}

{UNTRUSTED_RULE}

Requirements:
{shape}
{footer}
{strict}{inbox_rule}

Return ONLY JSON: {{"subject": "...", "body": "..."}}""";
    fields = _fields(
        await self.brain.think_json(
            prompt, session_id="sellbird-writer", agent="writer", task="personal_email"
        ),
    );
    return {"subject": fields[0][:120], "body": fields[1][:2000]} if fields else None;
}

impl Writer._write_sequence(prospects: list[any]) -> list[EmailStep] {
    prospect_summary = "\n".join(
        f"- {p.full_name()}, {p.title} at {p.company}"
            + (f" | Notes: {p.personalization_notes}" if p.personalization_notes else "")
        for p in prospects[:5],
    );
    inbox_batch = all(p.is_company_inbox for p in prospects);
    if inbox_batch {
        merge_rule = "- These go to each company's general inbox, so no names are known.\n"
            "  Use {{company}} as the merge variable in every email and NEVER\n"
            "  {{first_name}} or {{title}}. Greet with 'Hi there' or the company's team.";
    } else {
        merge_rule = "- Use {{first_name}}, {{company}}, {{title}} as merge variables. Every email\n"
            "  must use at least one, and email 1 must reference something specific to\n"
            "  these prospects' industry or role (use the notes above).";
    }
    prompt = self._base_prompt();
    if not prompt {
        (product, persona) = (self.config.product, self.config.persona);
        prompt = f"""You are {persona.name}, {persona.role} at {persona.company}.
Your tone is: {persona.tone}

Product: {product.name}
Description: {product.description}
Key benefits: {', '.join(product.key_benefits)}
Pricing: {product.pricing}""";
    }
    backed = [await self._startup(p.company_id) for p in prospects];
    startup = bool(prospects) and all(b is not None for b in backed);
    prompt += await self._guidance(prospect_summary, startup, []);
    rules = getattr(self, "email_rules", "");
    if rules {
        shape = "- Email 1 is the first touch, email 2 a follow-up 3 days later, email 3 a\n"
            "  last one 4 days after that. Follow the OPERATOR'S EMAIL RULES above for\n"
            "  each one's length, structure, what it says about the product, links and\n"
            "  subject line.";
        style = "";
        strict = "- Follow every rule in the STRICT EMAIL RULES above that the operator's\n"
            "  rules don't replace.";
    } else {
        (shape, style) = (SEQUENCE_SHAPE, "\n" + SEQUENCE_STYLE);
        strict = "- Follow every rule in the STRICT EMAIL RULES above. No exceptions.";
    }
    sample = fence(prospect_summary, "sample prospects");
    footer = footer_rule(self.config, rules);
    prompt += f"""

Write a 3-email cold outreach sequence for prospects like these:
{sample}

{UNTRUSTED_RULE}

Requirements:
{shape}
{merge_rule}{style}
{footer}
{strict}

Return ONLY a JSON array (no markdown fences, no commentary):
[
  {{"step": 1, "subject": "...", "body": "...", "delay_days": 0}},
  {{"step": 2, "subject": "...", "body": "...", "delay_days": 3}},
  {{"step": 3, "subject": "...", "body": "...", "delay_days": 4}}
]""";
    result = await self.brain.think_json(
        prompt, session_id="sellbird-writer", agent="writer", task="write_sequence"
    );
    self._no_reply = result is None and bool(getattr(self.brain, "last_reply_empty", False));
    steps = self._parse_sequence(result);
    if inbox_batch and any(PERSON_VAR.search(s.subject + s.body) for s in steps) {
        logger.warning("Writer: inbox sequence used a person merge variable; discarding it.");
        return [];
    }
    polished = await humanize(
        self.brain,
        [{"subject": s.subject, "body": s.body} for s in steps],
        agent="writer",
        enabled=humanizer_enabled(self.config),
    );
    names = [n for p in prospects for n in _names(p)];
    for (step, draft) in zip(steps, polished) {
        kept = await self._keep_to_rules(draft, step=step.step, names=names);
        if kept is None {
            return [];
        }
        (step.subject, step.body) = (kept["subject"], kept["body"]);
    }
    return steps;
}

impl Writer._keep_to_rules(draft: dict[str, any], *, step: int, names: any = ()) -> dict[str, any]
    | None {
    shape = not getattr(self, "email_rules", "");
    for attempt in range(2) {
        draft = self._finish(draft, shape);
        found = style_problems(
            draft["subject"], draft["body"], kind="cold", step=step, names=names, shape=shape
        );
        if not found {
            return draft;
        }
        if attempt {
            break;
        }
        draft = await self._rewrite_to_rules(draft, found, step, shape);
        if draft is None {
            break;
        }
    }
    logger.warning(
        f"Writer: dropped a draft for email {step} that breaks the rules: " + "; ".join(found)
    );
    return None;
}

impl Writer._finish(draft: dict[str, any], shape: bool) -> dict[str, any] {
    body = tidy(str(draft.get("body") or ""));
    if shape {
        body = with_sign_off(body, self.config.persona.name);
    }
    return {**draft, "subject": tidy(str(draft.get("subject") or "")), "body": body};
}

impl Writer._rewrite_to_rules(
    draft: dict[str, any], found: list[str], step: int, shape: bool
) -> dict[str, any] | None {
    body = draft["body"];
    first = (self.config.persona.name or "").strip().split(" ")[0] if shape else "";
    if first and body.endswith("\n\n" + first) {
        body = body[:-len(first) - 2].rstrip();
    }
    payload = {"subject": draft["subject"], "body": body};
    problems = "\n".join(f"- It {p}." for p in found);
    fenced = fence(json.dumps(payload, ensure_ascii=False, indent=2), "draft");
    prompt = f"""This cold email (email {step} of a sequence) breaks Sellbird's writing rules:
{problems}

Rewrite it so it breaks none of them. Keep its facts, its one question and every
merge variable such as {{{{first_name}}}} exactly as written; add no fact, name or claim.
Make it shorter, never longer: cut words instead of adding them. Plain text, no
dash between words (use a period or a comma), no exclamation marks, no sign-off
and no name at the end.

Draft:
{fenced}

{UNTRUSTED_RULE}

Return ONLY a JSON object: {{"subject": "...", "body": "..."}}""";
    try {
        fields = _fields(
            await self.brain.think_json(
                prompt, session_id="sellbird-writer", agent="writer", task="fix_draft"
            ),
        );
    } except Exception as e {
        logger.warning(f"Writer: rewrite to rules failed: {e}");
        return None;
    }
    if fields is None {
        return None;
    }
    (subject, new_body) = fields;
    before = set(MERGE_VAR.findall(payload["subject"] + payload["body"]));
    after = set(MERGE_VAR.findall(subject + new_body));
    if not after <= before or (before and not after) {
        return None;
    }
    return {**draft, "subject": subject[:120], "body": new_body[:2000]};
}

impl Writer._parse_sequence(result: any) -> list[EmailStep] {
    if isinstance(result, dict) {
        result = next(
            (result[k]
            for k in ("emails", "sequence", "steps", "campaign")
            if isinstance(result.get(k), list)),
            result,
        );
    }
    if not isinstance(result, list) or not result {
        logger.error(f"Writer: Brain did not return an email array (got {type(result).__name__}).");
        return [];
    }
    steps: list[EmailStep] = [];
    for (i, raw) in enumerate(result[:5]) {
        if not isinstance(raw, dict) {
            logger.warning(f"Writer: Skipping non-dict step at index {i}.");
            continue;
        }
        (subject, body) = (
            str(raw.get("subject") or "").strip(),
            str(raw.get("body") or "").strip(),
        );
        if not subject or not body {
            logger.warning(f"Writer: Skipping step {i + 1} with empty subject/body.");
            continue;
        }
        fallback = 3 if steps else 0;
        try {
            delay = max(0, int(raw.get("delay_days", fallback)));
        } except (TypeError, ValueError) {
            delay = fallback;
        }
        try {
            steps.append(
                EmailStep(step=len(steps) + 1, subject=subject, body=body, delay_days=delay)
            );
        } except Exception as e {
            logger.warning(f"Writer: Skipping invalid step {i + 1}: {e}");
        }
    }
    if steps and steps[0].delay_days != 0 {
        steps[0].delay_days = 0;
    }
    if len(steps) < 3 {
        logger.warning(f"Writer: Expected 3 emails, got {len(steps)}.");
    }
    return steps;
}

impl Writer._group_prospects(prospects: list[any]) -> dict[str, list[any]] {
    batches: dict[str, list[any]] = {};
    for prospect in prospects {
        kind = "inbox-outreach" if prospect.is_company_inbox else "outreach";
        batches.setdefault(f"{prospect.industry or 'general'}-{kind}", []).append(prospect);
    }
    cap = NATIVE_BATCH_CAP if self.is_native else LEGACY_BATCH_CAP;
    return {key: group[:cap] for (key, group) in batches.items()};
}
