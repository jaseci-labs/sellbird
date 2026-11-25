import builtins;
import asyncio;
import logging;
import random;
import re;
import time;
import from datetime { datetime, timedelta, timezone }

glob MIN_FOLLOW_UP_GAP = timedelta(days=1),
     logger = logging.getLogger("sellbird.sender"),
     MAX_SENDS_PER_CYCLE = 8,
     QUIET_HOURS_SCAN = 200,
     SEND_JITTER_SECONDS = (4, 15),
     ADDRESS_RETRY_AFTER = timedelta(hours=6),
     DOMAINS_FAILING_TO_PAUSE = 2,
     CHECK_SECONDS_PER_CYCLE = 90,
     STOP_STATUSES = set("replied opted_out lost meeting closed".split()),
     KILL_SWITCH_KEY = "sending_paused",
     BOUNCE_COUNT_KEY = "bounce_count",
     EMAIL_RE = re.compile(r"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"),
     SENDABLE_STATUSES = {"new", "queued"},
     SENDABLE_EMAIL_STATUSES = {"verified"},
     SENDABLE_EMAIL_STATUSES_WITH_RISKY = {"verified", "risky"};

def _utcnow -> datetime {
    return datetime.now(timezone.utc).replace(tzinfo=None);
}

def _local_now -> datetime {
    return datetime.now().astimezone();
}

def _now_iso -> str {
    return datetime.now(timezone.utc).replace(tzinfo=None).isoformat();
}

def _since_midnight(now: datetime) -> str {
    midnight = now.replace(hour=0, minute=0, second=0, microsecond=0);
    return midnight.astimezone(timezone.utc).replace(tzinfo=None).isoformat();
}

def _names(prospect: any) -> list[str] {
    if prospect is None {
        return [];
    }
    return [n for n in (prospect.company, prospect.first_name, prospect.last_name) if n];
}

def _merge_fields(p: any) -> str {
    fields = (p.first_name, p.last_name, p.company, p.title, p.personalization_notes);
    return " \n".join(str(v or "") for v in fields);
}

def _at(value: any) -> any {
    try {
        return datetime.fromisoformat(str(value));
    } except (TypeError, ValueError) {
        return None;
    }
}

def _text(thing: any, attr: str) -> str {
    return (getattr(thing, attr, "") or "").strip();
}

def _new(have: list[any], items: list[any]) -> list[any] {
    seen = {item["id"] for item in have};
    return [item for item in items if item["id"] not in seen];
}

class Sender {
    has brain: any = None,
        state: any = None,
        config: any = None,
        env: any = None,
        instantly: any = None,
        provider: any = None,
        inboxes: any = None,
        secrets: any = None,
        _inbox_providers: dict[str, any] = {},
        precleared: any = None,
        _failing_domains: set[str] = set(),
        send_pacing: bool = True,
        cold_only: bool = False,
        compliance_held: bool = False;

    def init(brain: any, state: any, config: any, env: any) {
        self.brain = brain;
        self.state = state;
        self.config = config;
        self.env = env;
        self.instantly = InstantlyClient(env.instantly_api_key);
        self.provider = get_mail_provider(config, env);
        self.precleared = PreclearedClient.from_config(config, env);
    }

    @builtins.property
    def is_native -> bool {
        return self.config.channels.email.provider in NATIVE_PROVIDERS
            and self.provider is not None;
    }

    async def _send_zone(
        prospect: any, country: str = "", given: str = "", names: any = ("", "")
    ) -> str {
        window = send_window_of(self.config);
        if window is not None and window.recipient_timezone {
            if not country and self.precleared is not None and prospect is not None {
                country = await self.precleared.known_country(
                    prospect.email, self.state, given, company=names[0], name=names[1]
                );
            }
            zone = await recipient_zone(self.state, prospect, self.config, country);
            if zone {
                return zone;
            }
        }
        return operator_timezone(self.config);
    }

    async def _zone_or_default(
        prospect: any, country: str = "", given: str = "", names: any = ("", "")
    ) -> str {
        try {
            return await self._send_zone(prospect, country, given, names);
        } except Exception as e {
            logger.warning(
                f"Sender: couldn't work out the time zone for "
                    f"{getattr(prospect, 'email', '?')}, using quiet_hours.timezone: {e}",
            );
            return operator_timezone(self.config);
        }
    }

    async def _recipient_country(prospect: any) -> str {
        try {
            return await recipient_country(self.state, prospect);
        } except Exception as e {
            logger.warning(
                f"Sender: couldn't work out the country for "
                    f"{getattr(prospect, 'email', '?')}, leaving it to Precleared: {e}",
            );
            return "";
        }
    }

    async def _recipient_names(prospect: any) -> tuple[str, str] {
        if prospect is None {
            return ("", "");
        }
        company = "";
        if getattr(prospect, "company_id", "") {
            try {
                record = await self.state.get_company(prospect.company_id);
                company = (getattr(record, "name", "") or "") if record else "";
            } except Exception as e {
                logger.warning(
                    f"Sender: couldn't load the company for "
                        f"{getattr(prospect, 'email', '?')}, using the prospect's own: {e}",
                );
            }
        }
        company = company.strip() or _text(prospect, "company");
        if getattr(prospect, "is_company_inbox", False) {
            return (company, "");
        }
        return (company, f"{_text(prospect, 'first_name')} {_text(prospect, 'last_name')}".strip());
    }

    async def _facts(prospect: any, wanted: bool) -> tuple[str, any] {
        if not wanted {
            return ("", ("", ""));
        }
        return (await self._recipient_country(prospect), await self._recipient_names(prospect));
    }

    async def _cached(item: any, country: str, names: any) -> any {
        return await self.precleared.cached(
            item["to_email"], self.state, country, company=names[0], name=names[1]
        );
    }

    async def _has_cached_verdict(item: any) -> bool {
        prospect = await self.state.get_prospect(item["prospect_id"]);
        (country, names) = await self._facts(prospect, True);
        return await self._cached(item, country, names) is not None;
    }

    async def _due(due_before: str, limit: int, **query: any) -> list[any] {
        return await self.state.get_outbox(
            status="approved", due_before=due_before, limit=limit, **query
        );
    }

    async def cold_due_in_window -> bool {
        window = send_window_of(self.config);
        email = self.config.channels.email;
        if window is None
            or not self.is_native
            or await self.state.get_setting(KILL_SWITCH_KEY)
            or email.max_daily_sends - await self.state.count_outbox_sent_today() <= 0
        {
            return False;
        }
        inboxes = await self._load_inboxes();
        if inboxes.several {
            room = any(i.cold_left > 0 for i in inboxes.sendable());
        } else {
            since = _since_midnight(datetime.now().astimezone());
            room = self.provider.is_configured()
                and cold_daily_cap(email)
                    - await self.state.count_outbox_sent_today(kind="sequence", since=since)
                    > 0;
        }
        if not room {
            return False;
        }
        now = _utcnow();
        due_before = _now_iso();
        due = await self._due(
            due_before, QUIET_HOURS_SCAN, skip_unready_follow_ups=True, kind="sequence"
        );
        held = self.compliance_held and self.precleared is not None;
        if held {
            due += _new(
                due,
                await self._due(
                    due_before, QUIET_HOURS_SCAN, skip_unready_follow_ups=True, follow_ups_only=True
                ),
            );
        }
        for item in due {
            if item["kind"] != "sequence" {
                continue;
            }
            prospect = await self.state.get_prospect(item["prospect_id"]);
            (country, names) = await self._facts(prospect, self.precleared is not None);
            if held {
                clearance = await self._cached(item, country, names);
                if clearance is None or not clearance.allowed {
                    continue;
                }
            }
            if prospect is not None
                and in_window(
                    now, await self._zone_or_default(prospect, given=country, names=names), window
                )
            {
                return True;
            }
        }
        return False;
    }

    async def _outside_window(item: any, zone: str, window: any) -> bool {
        now = _utcnow();
        if in_window(now, zone, window) {
            return False;
        }
        await self._set(item, send_at=next_send_time(now, zone, window).isoformat());
        return True;
    }

    async def _set(item: any, **fields: any) {
        await self.state.update_outbox_item(item["id"], **fields);
    }

    async def run {
        if not self.config.channels.email.enabled {
            logger.info("Sender: Email channel disabled. Skipping.");
            return;
        }
        if self.is_native {
            await self._run_native();
            return;
        }
        logger.info("Sender: Checking for campaigns to deploy...");
        draft_campaigns = await self.state.get_campaigns_by_status("draft");
        if not draft_campaigns {
            logger.info("Sender: No draft campaigns to deploy.");
            return;
        }
        max_sends = self.config.channels.email.max_daily_sends;
        sends_today = await self._count_sends_today();
        if max_sends - sends_today <= 0 {
            logger.info(f"Sender: Daily send limit reached ({sends_today}/{max_sends}). Skipping.");
            return;
        }
        for campaign in draft_campaigns {
            try {
                await self._deploy_campaign(campaign);
            } except Exception as e {
                logger.error(f"Sender: Failed to deploy campaign {campaign.name}: {e}");
            }
        }
    }

    def _validate_sequence(campaign: any) -> bool {
        if not campaign.sequence {
            logger.error(
                f"Sender: Campaign '{campaign.name}' has no email sequence. Marking failed."
            );
            return False;
        }
        for step in campaign.sequence {
            if not (step.subject or "").strip() or not (step.body or "").strip() {
                logger.error(
                    f"Sender: Campaign '{campaign.name}' step {step.step} has an empty "
                        "subject or body. Marking failed.",
                );
                return False;
            }
            if step.delay_days < 0 {
                logger.error(
                    f"Sender: Campaign '{campaign.name}' step {step.step} has a negative delay."
                );
                return False;
            }
        }
        return True;
    }

    async def _leads(campaign: any, instantly: bool) -> tuple[list[any], int, int] {
        sendable_email = SENDABLE_EMAIL_STATUSES_WITH_RISKY
            if getattr(self.config.channels.email, "send_to_risky", False)
            else SENDABLE_EMAIL_STATUSES;
        leads: list[any] = [];
        seen_emails: set[str] = set();
        (skipped, answered) = (0, 0);
        for prospect_id in campaign.prospect_ids {
            prospect = await self.state.get_prospect(prospect_id);
            if not prospect or not prospect.email {
                continue;
            }
            email = prospect.email.strip().lower();
            if not EMAIL_RE.match(email) {
                if instantly {
                    logger.warning(f"Sender: Skipping invalid email '{prospect.email}'");
                }
                continue;
            }
            if email in seen_emails {
                continue;
            }
            if prospect.status not in SENDABLE_STATUSES {
                if instantly {
                    logger.debug(
                        f"Sender: Skipping {email} (status '{prospect.status}' is not sendable)."
                    );
                }
                continue;
            }
            if instantly and await self.state.get_setting(MANUAL_SEND_KEY + prospect.id) {
                continue;
            }
            if await self.state.is_suppressed(email) {
                if instantly {
                    logger.debug(f"Sender: Skipping {email} (suppressed).");
                }
                continue;
            }
            if (prospect.email_status or "guess") not in sendable_email {
                skipped += 1;
                if instantly {
                    logger.debug(
                        f"Sender: Skipping {email} (email_status "
                            f"'{prospect.email_status or 'guess'}' not deliverable).",
                    );
                }
                continue;
            }
            if not instantly and await self.state.colleague_who_replied(prospect.id) {
                answered += 1;
                continue;
            }
            seen_emails.add(email);
            leads.append(prospect);
        }
        return (leads, skipped, answered);
    }

    def _reviewed_leads(prospects: list[any]) -> list[any] {
        kept: list[any] = [];
        for p in prospects {
            held = autopilot_review("", _merge_fields(p), self.config, recipient=p.email);
            if listed := do_not_contact_match(p.email, live_do_not_contact(self.config)) {
                held = [f"'{listed}' is on the do-not-contact list", *held];
            }
            if held {
                logger.warning(f"Sender: left {p.email} out of the Instantly upload: {held}");
            } else {
                kept.append(p);
            }
        }
        return kept;
    }

    async def _deploy_campaign(campaign: any) {
        await sync_sending_mode(self.config, self.state);
        if getattr(self.config.channels.email, "require_approval", True) {
            logger.warning(
                "Sender: Instantly campaign held because require_approval is true. "
                    "Use a native mail provider for outbox review, or explicitly set "
                    "channels.email.require_approval: false for Instantly autopilot.",
            );
            return;
        }
        logger.info(f"Sender: Deploying campaign '{campaign.name}'...");
        if not self._validate_sequence(campaign) {
            await self.state.update_campaign(campaign.id, status="failed");
            return;
        }
        held = [
            f"step {s.step} {r}"
            for s in campaign.sequence
            for r in autopilot_review(s.subject, s.body, self.config)
        ];
        if held {
            logger.warning(f"Sender: Instantly campaign '{campaign.name}' held for review: {held}");
            key = "instantly_review_hold:" + campaign.id;
            if not await self.state.get_setting(key) {
                await self.state.set_setting(key, "1");
                reason = "campaign held: " + "; ".join(held)[:200];
                await self.state.log_action(
                    action_type="escalation",
                    agent="sender",
                    details={"campaign_name": campaign.name, "reason": reason},
                );
            }
            return;
        }
        campaign_id = campaign.instantly_campaign_id;
        if campaign_id {
            logger.info(
                f"Sender: Campaign '{campaign.name}' already has Instantly ID "
                    f"{campaign_id}. Resuming deploy instead of recreating.",
            );
        } else {
            created = await self.instantly.create_campaign(campaign.name);
            if not created or not isinstance(created, dict) {
                logger.error(f"Sender: Failed to create Instantly campaign: {campaign.name}");
                return;
            }
            campaign_id = created.get("id");
            if not campaign_id {
                logger.error("Sender: No campaign ID returned from Instantly.");
                return;
            }
            await self.state.update_campaign(campaign.id, instantly_campaign_id=campaign_id);
            campaign.instantly_campaign_id = campaign_id;
        }
        sequences = [
            {
                "subject": step.subject.strip(),
                "body": self._with_footer(step.body.strip()),
                "wait": step.delay_days,
            }
            for step in campaign.sequence
        ];
        await self.state.remember_footer_lines(compliance_footer_lines(self.config));
        if await self.instantly.set_campaign_emails(campaign_id, sequences) is None {
            logger.error(f"Sender: Failed to set emails for campaign {campaign_id}");
            return;
        }
        (prospects, skipped_unverified, _) = await self._leads(campaign, True);
        if skipped_unverified {
            logger.info(
                f"Sender: Held back {skipped_unverified} prospect(s) with "
                    f"unverified emails from '{campaign.name}'.",
            );
        }
        if not prospects {
            for pid in campaign.prospect_ids {
                p = await self.state.get_prospect(pid);
                if p and p.status == "contacted" {
                    logger.info(
                        f"Sender: Leads for '{campaign.name}' already staged. Retrying activation."
                    );
                    if await self.instantly.activate_campaign(campaign_id) is not None {
                        await self.state.update_campaign(campaign.id, status="active");
                        logger.info(f"Sender: Campaign '{campaign.name}' activated on retry.");
                    }
                    return;
                }
            }
            logger.warning(f"Sender: No valid prospects for campaign {campaign.name}");
            return;
        }
        remaining = self.config.channels.email.max_daily_sends - await self._count_sends_today();
        if remaining <= 0 {
            logger.info(f"Sender: Daily limit reached. Deferring campaign '{campaign.name}'.");
            return;
        }
        if len(prospects) > remaining {
            logger.info(
                f"Sender: Capping leads from {len(prospects)} to {remaining} (daily limit)."
            );
            prospects = prospects[:remaining];
        }
        prospects = self._reviewed_leads(prospects);
        if not prospects {
            return;
        }
        leads = [
            {
                "email": p.email.strip().lower(),
                "first_name": p.first_name,
                "last_name": p.last_name,
                "company_name": p.company,
                "variables": {"title": p.title, "personalization": p.personalization_notes},
            }
            for p in prospects
        ];
        if await self.instantly.add_leads(campaign_id, leads) is None {
            logger.error(f"Sender: Failed to add leads to campaign {campaign_id}");
            return;
        }
        for prospect in prospects {
            await self.state.update_prospect_status(prospect.id, "contacted");
        }
        if await self.instantly.activate_campaign(campaign_id) is None {
            logger.error(
                f"Sender: Failed to activate campaign {campaign_id}. "
                    "Leads are staged; will retry activation next cycle.",
            );
            return;
        }
        await self.state.update_campaign(
            campaign.id, instantly_campaign_id=campaign_id, status="active"
        );
        details = {
            "campaign_name": campaign.name,
            "instantly_campaign_id": campaign_id,
            "leads_added": len(leads),
        };
        await self.state.log_action(action_type="send_campaign", agent="sender", details=details);
        logger.info(
            f"Sender: Campaign '{campaign.name}' deployed to Instantly "
                f"with {len(leads)} leads. Campaign ID: {campaign_id}",
        );
    }

    async def _count_sends_today -> int {
        async with storage.connect(self.state.db_path) as db {
            async with db.execute(
                "SELECT COUNT(*) FROM prospects "
                    "WHERE status = 'contacted' AND datetime(updated_at) >= datetime(?)",
                (_since_midnight(_local_now()),),
            ) as cursor {
                row = await cursor.fetchone();
                return row[0] if row else 0;
            }
        }
    }

    async def _run_native {
        stale = await self.state.fail_stale_sending_outbox();
        if stale {
            logger.warning(
                f"Sender: {stale} email(s) were interrupted mid-send and won't be "
                    "retried. Check your Sent folder; they're under Didn't send.",
            );
        }
        paused = await self.state.get_setting(KILL_SWITCH_KEY);
        if paused {
            logger.warning(
                f"Sender: SENDING PAUSED ({paused}). Resume from the dashboard "
                    "or `sellbird sending resume` once the cause is fixed.",
            );
            return;
        }
        self.inboxes = await self._load_inboxes();
        try {
            for campaign in await self.state.get_campaigns_by_status("draft") {
                try {
                    await self._stage_campaign_native(campaign);
                } except Exception as e {
                    logger.error(f"Sender: staging '{campaign.name}' failed: {e}");
                }
            }
            await self._drain_due();
        } finally {
            self.inboxes = None;
        }
    }

    async def _load_inboxes -> any {
        return await load_inboxes(
            self.state,
            self.config,
            self.env,
            self.provider,
            secrets=self.secrets,
            cache=self._inbox_providers,
        );
    }

    def _render(text: str, prospect: any) -> str {
        company = prospect.company or "";
        if company.endswith(("s", "S")) {
            for tag in ("{{company}}", "{{ company }}") {
                text = text.replace(tag + "'s", company + "'").replace(tag + "’s", company + "’");
            }
        }
        replacements = {
            "first_name": prospect.first_name or ("there" if prospect.is_company_inbox else ""),
            "last_name": prospect.last_name,
            "company": prospect.company,
            "title": prospect.title,
            "personalization": prospect.personalization_notes,
        };
        for (key, value) in replacements.items() {
            text = text.replace("{{" + key + "}}", value or "").replace(
                "{{ " + key + " }}", value or ""
            );
        }
        return text.strip();
    }

    async def _stage_campaign_native(campaign: any) {
        if not self._validate_sequence(campaign) {
            await self.state.update_campaign(campaign.id, status="failed");
            return;
        }
        await sync_sending_mode(self.config, self.state);
        email_config = self.config.channels.email;
        require_approval = getattr(email_config, "require_approval", True);
        (prospects, skipped, answered) = await self._leads(campaign, False);
        staged = 0;
        now = _utcnow();
        window = send_window_of(self.config);
        for prospect in prospects {
            zone = await self._zone_or_default(prospect) if window is not None else "";
            cumulative_days = 0;
            new_rows = 0;
            for step in campaign.sequence {
                if step.step > 1 and not getattr(email_config, "follow_ups", True) {
                    continue;
                }
                cumulative_days += max(0, step.delay_days);
                send_at = now + timedelta(days=cumulative_days);
                if window is not None {
                    send_at = next_send_time(send_at, zone, window);
                }
                if await self.state.add_outbox_item(
                    prospect_id=prospect.id,
                    campaign_id=campaign.id,
                    step=step.step,
                    to_email=prospect.email.strip().lower(),
                    subject=self._render(step.subject, prospect),
                    body=self._render(step.body, prospect),
                    send_at=send_at.isoformat(),
                    status="pending_review" if require_approval else "approved",
                    provider=self.provider.name,
                    approved_by="" if require_approval else "autopilot",
                ) {
                    staged += 1;
                    new_rows += 1;
                }
            }
            if new_rows and self.inboxes is not None and self.inboxes.several {
                await self.inboxes.assign(campaign.id, prospect.id, staged_now=True);
            }
            await self.state.queue_prospect_if_unsent(prospect.id);
        }
        await self.state.update_campaign(campaign.id, status="active");
        if skipped {
            logger.info(
                f"Sender: held back {skipped} prospect(s) with unverified "
                    f"emails from '{campaign.name}'.",
            );
        }
        if answered {
            logger.info(
                f"Sender: left out {answered} prospect(s) from '{campaign.name}': "
                    f"{COLLEAGUE_REPLIED} at their company.",
            );
        }
        if staged {
            mode = "awaiting your approval" if require_approval else "approved";
            logger.info(
                f"Sender: staged {staged} email(s) for '{campaign.name}' "
                    f"({mode}). Review in the dashboard Outbox tab.",
            );
            await self.state.log_action(
                action_type="stage_campaign",
                agent="sender",
                details={"campaign": campaign.name, "staged": staged, "mode": mode},
            );
        }
    }

    def _with_footer(body: str) -> str {
        footer = "\n".join(compliance_footer_lines(self.config));
        if not footer or body.rstrip().endswith(footer) {
            return body;
        }
        return body.rstrip() + "\n\n" + footer;
    }

    def _outgoing_body(item: any) -> str {
        return self._with_footer(item["body"]) if item["kind"] == "sequence" else item["body"];
    }

    async def _follow_up_order(item: any, prospect: any = None) -> any {
        if item["kind"] != "sequence" or int(item["step"]) <= 1 {
            return None;
        }
        prev = await self.state.get_previous_step(item);
        if prev is None {
            return None;
        }
        if prev["status"] in ("pending_review", "approved", "sending") {
            return "wait";
        }
        if prev["status"] != "sent" {
            return ("cancelled", f"step {prev['step']} wasn't sent ({prev['status']})");
        }
        sent_at = _at(prev["sent_at"]);
        if sent_at is None {
            return None;
        }
        delay = await self.state.get_step_delay_days(item.get("campaign_id"), item["step"]);
        if delay is None {
            (planned, prev_planned) = (_at(item["send_at"]), _at(prev["send_at"]));
            gap = (planned - prev_planned) if planned and prev_planned else MIN_FOLLOW_UP_GAP;
        } else {
            gap = timedelta(days=delay);
        }
        ready_at = sent_at + max(MIN_FOLLOW_UP_GAP, gap);
        window = send_window_of(self.config);
        if window is not None and prospect is not None {
            ready_at = next_send_time(ready_at, await self._zone_or_default(prospect), window);
        }
        if _utcnow() >= ready_at {
            return None;
        }
        await self._set(item, send_at=ready_at.isoformat());
        return "wait";
    }

    async def _retry_later(
        item: any, reason: str, after: any = ADDRESS_RETRY_AFTER, prefix: str = RECHECK_PREFIX
    ) -> datetime {
        retry_at = _utcnow() + after;
        note = f"{prefix}{retry_at:%Y-%m-%d %H:%M} UTC: {reason}"[:300];
        await self._set(item, send_at=retry_at.isoformat(), error=note);
        return retry_at;
    }

    async def _blocked(item: any, prospect: any, allow_risky: bool) -> any {
        await sync_sending_mode(self.config, self.state);
        if prospect is None {
            return ("failed", "prospect missing");
        }
        suppressed = await self.state.is_suppressed(item["to_email"]);
        if suppressed {
            return ("cancelled", f"suppressed ({suppressed})");
        }
        if item["kind"] == "sequence" {
            if prospect.status in STOP_STATUSES {
                return ("cancelled", f"prospect status '{prospect.status}'");
            }
            if await self.state.get_setting(MANUAL_SEND_KEY + prospect.id) {
                return ("cancelled", HAND_SENT_REASON);
            }
            if item["step"] == 1 and prospect.status == "contacted" {
                return ("cancelled", "already contacted");
            }
            colleague = await self.state.colleague_who_replied(prospect.id);
            if colleague {
                return ("cancelled", f"{COLLEAGUE_REPLIED} ({colleague})");
            }
        }
        kind = "reply" if item["kind"] == "reply" else "cold";
        style = style_problems(
            item["subject"], item["body"], kind=kind, names=_names(prospect), shape=False
        );
        if style {
            logger.warning(f"Sender: holding email to {item['to_email']}: {style}");
            return ("pending_review", (HELD_FOR_REVIEW + "the email " + "; ".join(style))[:300]);
        }
        gate = pre_send_check(
            item["to_email"],
            item["subject"],
            self._outgoing_body(item),
            prospect=prospect,
            allow_risky=allow_risky,
            kind=item["kind"],
            postal_address=compliance_of(self.config).postal_address,
            do_not_contact=live_do_not_contact(self.config),
        );
        if not gate {
            logger.warning(f"Sender: gate blocked email to {item['to_email']}: {gate.reasons}");
            return ("failed", "gate: " + "; ".join(gate.reasons)[:300]);
        }
        if item.get("approved_by") == "autopilot"
            and getattr(self.config.channels.email, "require_approval", True)
        {
            return ("pending_review", AUTOPILOT_OFF_REASON);
        }
        if item.get("approved_by") != "you" {
            held = autopilot_review(
                item["subject"], self._outgoing_body(item), self.config, recipient=item["to_email"]
            );
            if held {
                logger.warning(f"Sender: holding email to {item['to_email']} for review: {held}");
                return ("pending_review", (HELD_FOR_REVIEW + "; ".join(held))[:300]);
            }
        }
        rules = extensions.registry().send_rules;
        if rules {
            check = SendCheck(item=item, prospect=prospect, config=self.config, state=self.state);
            verdict = await first_verdict(rules, check);
            if verdict {
                logger.info(f"Sender: {verdict[1]} ({item['to_email']})");
                return verdict;
            }
        }
        return None;
    }

    async def _held(item: any, prospect: any, allow_risky: bool) -> bool {
        blocked = await self._blocked(item, prospect, allow_risky);
        if blocked {
            await self._set(item, status=blocked[0], error=blocked[1]);
        }
        return bool(blocked);
    }

    async def _drain_due {
        if self.precleared is None {
            await clear_hold(self.state);
        }
        loaded = self.inboxes if self.inboxes is not None else await self._load_inboxes();
        inboxes = loaded if loaded.several else None;
        if inboxes is None and not self.provider.is_configured() {
            logger.warning(
                f"Sender: mail provider '{self.provider.name}' is not configured "
                    "yet — outbox is holding. See CLAUDE.md → provider setup.",
            );
            return;
        }
        if inboxes is not None and not inboxes.sendable() {
            logger.warning(
                "Sender: no inbox can send right now (each is paused or not "
                    "connected) — outbox is holding. See `sellbird inboxes list`.",
            );
            return;
        }
        problem = signature_problem(self.config);
        if problem {
            logger.warning(
                f"Sender: email signature can't be used ({problem}) — outbox is holding."
            );
            await self.state.note_sends_held(f"{SIGNATURE_HOLD_PREFIX}{problem}");
            return;
        }
        email_config = self.config.channels.email;
        max_daily = email_config.max_daily_sends;
        sent_today = await self.state.count_outbox_sent_today();
        per_cycle = MAX_SENDS_PER_CYCLE * (len(inboxes.sendable()) if inboxes else 1);
        budget = min(per_cycle, max_daily - sent_today);
        if budget <= 0 {
            logger.info(f"Sender: daily send cap reached ({sent_today}/{max_daily}).");
            return;
        }
        cold_cap = cold_daily_cap(email_config);
        since = _since_midnight(datetime.now().astimezone());
        cold_left = cold_cap
            - await self.state.count_outbox_sent_today(kind="sequence", since=since);
        now = _now_iso();
        due = await self._due(
            now,
            budget * 3,
            skip_unready_follow_ups=True,
            kind="sequence" if self.cold_only else None,
        );
        extra = []
            if self.cold_only
            else _new(due, await self._due(now, budget * 3, exclude_kind="sequence"));
        if self.precleared is not None {
            extra += _new(
                due + extra,
                await self._due(
                    now, budget * 3, skip_unready_follow_ups=True, follow_ups_only=True
                ),
            );
        }
        if extra {
            due = sorted(
                due + extra,
                key=lambda (i: any) -> any { (i.get("send_at") or "", i.get("created_at") or "") },
            );
        }
        if not due {
            return;
        }
        allow_risky = getattr(email_config, "send_to_risky", False);
        window = send_window_of(self.config);
        (sent, sent_cold, outside_window, held_cold, waiting_on_check, unknown_held) = (
            0, 0, 0, 0, 0, 0,
        );
        (compliance_paused, answered, hold, check_seconds) = (False, False, None, 0.0);
        failed_addresses: set[str] = set();
        inbox_waits: dict[str, int] = {};
        for item in due {
            if sent >= budget {
                break;
            }
            if self.cold_only and item["kind"] != "sequence" {
                continue;
            }
            (provider, inbox) = (self.provider, None);
            if inboxes is not None {
                route = await inboxes.route(item);
                if route.action == "cancel" {
                    await self._set(item, status="cancelled", error=route.reason);
                    continue;
                }
                if route.action == "hold" {
                    inbox_waits[route.reason] = inbox_waits.get(route.reason, 0) + 1;
                    continue;
                }
                inbox = inboxes.get(route.mailbox_id);
                if inbox.sent_this_cycle >= MAX_SENDS_PER_CYCLE {
                    continue;
                }
                if item["kind"] == "sequence" and inbox.cold_left <= 0 {
                    held_cold += 1;
                    continue;
                }
                provider = inbox.provider;
            } elif item["kind"] == "sequence" and sent_cold >= cold_left {
                held_cold += 1;
                continue;
            }
            needs_check = self.precleared is not None and item["kind"] == "sequence";
            prospect = await self.state.get_prospect(item["prospect_id"]);
            if await self._held(item, prospect, allow_risky) {
                continue;
            }
            order = await self._follow_up_order(item, prospect);
            if order == "wait" {
                continue;
            }
            if order {
                await self._set(item, status=order[0], error=order[1]);
                continue;
            }
            (country, names) = await self._facts(prospect, needs_check);
            if window is not None
                and item["kind"] == "sequence"
                and await self._outside_window(
                    item, await self._zone_or_default(prospect, given=country, names=names), window
                )
            {
                outside_window += 1;
                continue;
            }
            receipt_id = "";
            if needs_check {
                clearance = await self._cached(item, country, names);
                if clearance is None
                    and (compliance_paused or check_seconds > CHECK_SECONDS_PER_CYCLE)
                {
                    waiting_on_check += 1;
                    continue;
                }
                address = (item["to_email"] or "").strip().lower();
                if clearance is None and address in failed_addresses {
                    await self._retry_later(
                        item, "the check failed for this address earlier this cycle"
                    );
                    continue;
                }
                if clearance is None {
                    started = time.monotonic();
                    clearance = await self.precleared.check(
                        item["to_email"], self.state, country, company=names[0], name=names[1]
                    );
                    check_seconds += time.monotonic() - started;
                }
                if clearance.held and not clearance.pause_checks {
                    again = (item.get("error") or "").startswith(RECHECK_PREFIX);
                    failed_addresses.add(address);
                    if not again {
                        self._failing_domains.add(address.rpartition("@")[2]);
                    }
                    waiting_on_check += 1;
                    retry_at = await self._retry_later(item, clearance.reason);
                    logger.warning(
                        f"Sender: Precleared couldn't check {item['to_email']}, trying "
                            f"again after {retry_at:%Y-%m-%d %H:%M} UTC: {clearance.reason}",
                    );
                    if again or len(self._failing_domains) < DOMAINS_FAILING_TO_PAUSE {
                        continue;
                    }
                }
                if clearance.held {
                    (compliance_paused, hold) = (True, clearance);
                    if clearance.pause_checks {
                        waiting_on_check += 1;
                        if clearance.retry_address {
                            await self._retry_later(item, clearance.reason);
                        }
                    }
                    logger.warning(
                        f"Sender: compliance check unavailable, holding cold "
                            f"email until a later cycle: {clearance.reason}",
                    );
                    continue;
                }
                if not clearance.cached {
                    answered = True;
                    self._failing_domains.clear();
                }
                if clearance.verdict == "unknown" and not clearance.unknown_final {
                    after = ADDRESS_RETRY_AFTER
                        if clearance.unknown_attempts <= 1
                        else UNKNOWN_RETRY_AFTER;
                    retry_at = await self._retry_later(
                        item, clearance.reason, after=after, prefix=UNKNOWN_HOLD_PREFIX
                    );
                    unknown_held += 1;
                    logger.warning(
                        f"Sender: Precleared couldn't settle {item['to_email']} "
                            f"(unknown, answer {clearance.unknown_attempts} of "
                            f"{UNKNOWN_ATTEMPTS}); trying again after "
                            f"{retry_at:%Y-%m-%d %H:%M} UTC: {clearance.reason}",
                    );
                    continue;
                }
                if not clearance.allowed {
                    verdict = clearance.verdict;
                    if verdict == "unknown" {
                        verdict = f"unknown after {clearance.unknown_attempts} checks";
                    }
                    error = f"precleared: {verdict}: {clearance.reason}"[:300];
                    await self._set(item, status="failed", error=error);
                    logger.warning(
                        f"Sender: Precleared held back email to {item['to_email']}: "
                            f"{verdict} ({clearance.reason})",
                    );
                    continue;
                }
                receipt_id = clearance.receipt_id;
                if window is not None
                    and window.recipient_timezone
                    and clearance.country
                    and not prospect.timezone
                {
                    zone = await self._zone_or_default(prospect, clearance.country);
                    if zone and await self._outside_window(item, zone, window) {
                        outside_window += 1;
                        continue;
                    }
                }
            }
            if not await self.state.claim_outbox_item(item["id"]) {
                continue;
            }
            item = await self.state.get_outbox_item(item["id"]) or item;
            prospect = await self.state.get_prospect(item["prospect_id"]);
            if await self._held(item, prospect, allow_risky) {
                continue;
            }
            body = self._outgoing_body(item);
            try {
                headers = extra_headers(extensions.registry().send_headers, item);
            } except SendHookError as e {
                logger.error(f"Sender: holding email to {item['to_email']}: {e}");
                await self._set(item, status="approved", error=f"held: {e}"[:300]);
                continue;
            }
            if headers and not getattr(provider, "carries_headers", False) {
                await self._set(item, status="approved", error=f"held: {NO_HEADERS_HOLD}");
                continue;
            }
            sent_headers = {"headers": headers} if headers else {};
            try {
                result = await provider.send_email(
                    item["to_email"],
                    item["subject"],
                    body,
                    thread_ref=item.get("thread_ref", ""),
                    in_reply_to=item.get("in_reply_to", ""),
                    **sent_headers,
                );
            } except Exception as e {
                await self._set(
                    item, status="failed", error=f"{MAYBE_SENT_PREFIX}send error: {e}"[:300]
                );
                logger.warning(f"Sender: send to {item['to_email']} raised: {e}");
                continue;
            }
            if not result.ok and result.error.startswith("signature:") {
                await self._set(item, status="approved");
                await self.state.note_sends_held(SIGNATURE_HOLD_PREFIX + result.error[10:].strip());
                logger.warning(f"Sender: {result.error} — outbox is holding.");
                break;
            }
            if not result.ok {
                prefix = MAYBE_SENT_PREFIX if getattr(result, "uncertain", False) else "";
                await self._set(item, status="failed", error=f"{prefix}{result.error}"[:300]);
                continue;
            }
            sent += 1;
            if item["kind"] == "sequence" {
                sent_cold += 1;
            }
            note_inbox: dict[str, any] = {};
            if inbox is not None {
                inbox.sent_this_cycle += 1;
                if item["kind"] == "sequence" {
                    inbox.sent_today += 1;
                }
                note_inbox = {"mailbox_id": inbox.id, "provider": provider.name};
            }
            note = {"error": ""}
                if (item.get("error") or "").startswith(MOVED_BACK_PREFIXES)
                else {};
            await self._set(
                item,
                status="sent",
                sent_at=_now_iso(),
                body=body,
                message_id=result.message_id,
                thread_ref=result.thread_ref,
                **note,
                **note_inbox,
            );
            if prospect.status in ("new", "queued") {
                await self.state.update_prospect_status(prospect.id, "contacted");
            }
            if item["kind"] == "reply" and item.get("conversation_id") {
                try {
                    convo = await self.state.get_conversation(item["conversation_id"]);
                    if convo {
                        convo.thread.append(Message(sender="sellbird", content=item["body"]));
                        await self.state.update_conversation(
                            convo.id, thread_json=convo.thread_json()
                        );
                    }
                } except Exception as e {
                    logger.debug(f"Sender: convo append failed: {e}");
                }
            }
            details: dict[str, any] = {
                "to": item["to_email"],
                "step": item["step"],
                "kind": item["kind"],
                "provider": provider.name,
            };
            if inbox is not None {
                details["from"] = inbox.address;
            }
            if receipt_id {
                details["precleared_receipt"] = receipt_id;
            }
            await self.state.log_action(action_type="email_sent", agent="sender", details=details);
            logger.info(
                f"Sender: sent step {item['step']} to {item['to_email']} via {provider.name}"
                    + (f" from {inbox.address}." if inbox is not None else "."),
            );
            if self.send_pacing and sent < budget {
                await asyncio.sleep(random.uniform(*SEND_JITTER_SECONDS));
            }
        }
        self.compliance_held = compliance_paused;
        for (reason, count) in inbox_waits.items() {
            logger.info(f"Sender: {count} email(s) wait: {reason}.");
        }
        if outside_window {
            logger.info(
                f"Sender: {outside_window} cold email(s) wait for the recipient's "
                    f"send window ({window.start}-{window.end} their time).",
            );
        }
        if unknown_held {
            logger.info(
                f"Sender: {unknown_held} cold email(s) wait on a fact Precleared couldn't "
                    f"establish; the Outbox says what would settle each one.",
            );
        }
        if self.precleared is not None and hold is not None {
            counted = await self.state.count_due_cold_outbox(
                now, has_cached_verdict=self._has_cached_verdict, moved_back_prefix=RECHECK_PREFIX
            );
            await record_hold(self.state, hold, max(waiting_on_check, counted));
        } elif self.precleared is not None and answered {
            await clear_hold(self.state);
        }
        if held_cold and inboxes is not None {
            logger.info(
                f"Sender: {held_cold} cold email(s) wait for their inbox's daily cap. "
                    "Replies still go out. See `sellbird inboxes list`.",
            );
        } elif held_cold {
            warmup = getattr(email_config, "warmup", None);
            days = warmup.days_in() if warmup is not None else None;
            if days is not None and cold_cap < max_daily {
                logger.info(
                    f"Sender: warmup day {days}: {held_cold} cold email(s) wait; today's "
                        f"cold cap is {cold_cap}. Replies still go out. See `sellbird warmup`.",
                );
            } else {
                logger.info(f"Sender: cold email cap reached for today ({cold_cap}).");
            }
        }
        if sent_cold {
            await self.state.remember_footer_lines(compliance_footer_lines(self.config));
            notice = compliance_notice(self.config);
            if notice {
                logger.warning(f"Sender: {notice}");
            }
        }
        if sent {
            logger.info(
                f"Sender: {sent} email(s) sent this cycle ({sent_today + sent}/{max_daily} today)."
            );
        }
    }
}
