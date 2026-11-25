impl Analyst.init(state: StateManager) {
    self.state = state;
}

impl Analyst.run {
    logger.info("Analyst: Running performance analysis...");
    summary = {
        "generated_at": datetime.utcnow().isoformat(),
        "pipeline": await self.state.count_prospects_by_status(),
        "campaigns": await self.state.get_campaign_stats(),
        "intents": await self.state.get_intent_distribution(),
        "stages": await self.state.get_stage_distribution(),
        "insights": [],
    };
    summary["insights"] = self._generate_insights(summary);
    report_path = Path(self.state.db_path).parent / "analytics.json";
    try {
        tmp_path = report_path.with_suffix(".json.tmp");
        with open(tmp_path, "w", encoding="utf-8") as f {
            json.dump(summary, f, indent=2);
        }
        tmp_path.replace(report_path);
        logger.info(f"Analyst: Report written to {report_path}");
    } except OSError as e {
        logger.error(f"Analyst: Failed to write report: {e}");
    }
    pipeline = summary["pipeline"];
    total = sum(pipeline.values());
    if total > 0 {
        contacted = pipeline.get("contacted", 0);
        reply_rate = pipeline.get("replied", 0) / max(contacted, 1) * 100;
        logger.info(
            f"Analyst: {total} prospects | {contacted} contacted | Reply rate: {reply_rate:.1f}%"
        );
    }
    for insight in summary["insights"] {
        logger.info(f"Analyst: Insight — {insight}");
    }
}

impl Analyst._generate_insights(summary: dict[str, any]) -> list[str] {
    insights: list[str] = [];
    pipeline = summary.get("pipeline") or {};
    intents = summary.get("intents") or {};
    stages = summary.get("stages") or {};
    fresh = pipeline.get("new", 0);
    queued = pipeline.get("queued", 0);
    contacted = pipeline.get("contacted", 0);
    interested = intents.get("interested", 0);
    escalations = intents.get("escalate", 0);
    if contacted > 10 {
        reply_rate = pipeline.get("replied", 0) / contacted * 100;
        if reply_rate < 5 {
            insights.append(
                f"ACTION: Reply rate is low ({reply_rate:.1f}%, benchmark 5-10%). "
                    "Rewrite email 1 in prompts/writer.md with a sharper observation, "
                    "and test 2-3 new subject lines via skills/email_frameworks.md.",
            );
        } elif reply_rate > 15 {
            insights.append(
                f"KEEP: Reply rate is strong ({reply_rate:.1f}%). Don't change the "
                    "current messaging. Scale prospecting to feed it more leads.",
            );
        }
        optout_rate = (intents.get("unsubscribe", 0) + pipeline.get("opted_out", 0))
            / contacted
            * 100;
        if optout_rate > 2 {
            insights.append(
                f"URGENT: Opt-out rate is {optout_rate:.1f}% (>2% risks blacklisting). "
                    "Pause sending, tighten ICP targeting in sellbird.yaml, and reduce "
                    "max_daily_sends until the list quality improves.",
            );
        }
    }
    if escalations > 0 {
        insights.append(
            f"HUMAN NEEDED: {escalations} conversation(s) escalated (angry/legal). "
                "Review conversations with status 'needs_human' in the dashboard before "
                "any further sending to those domains.",
        );
    }
    replies = sum(intents.values()) if intents else 0;
    objection_pct = intents.get("objection", 0) / replies * 100 if replies > 5 else 0;
    if objection_pct > 40 {
        insights.append(
            f"ACTION: {objection_pct:.0f}% of replies are objections. Add the "
                "recurring objections to objection_responses in sellbird.yaml and "
                "skills/objection_handling.md, or narrow targeting to better-fit accounts.",
        );
    }
    if interested > 0 and contacted > 0 {
        insights.append(
            f"Interest rate: {interested / contacted * 100:.1f}% of contacted prospects show interest "
                f"({interested} of {contacted}).",
        );
    }
    rated = [c for c in summary.get("campaigns") or [] if c.get("reply_rate") is not None];
    if len(rated) >= 2 {
        best = max(rated, key=lambda (c: any) -> any { return c.get("reply_rate", 0); });
        worst = min(rated, key=lambda (c: any) -> any { return c.get("reply_rate", 0); });
        if best.get("reply_rate", 0) > 0 and best is not worst {
            insights.append(
                f"ACTION: '{best.get('name')}' ({best.get('reply_rate')}% replies) beats "
                    f"'{worst.get('name')}' ({worst.get('reply_rate', 0)}%). Reuse the winner's "
                    "angle and subject-line style for the next campaign; pause or rewrite the loser.",
            );
        }
    }
    if stages.get("engaged", 0) > 3 and stages.get("closing", 0) == 0 {
        insights.append(
            "ACTION: Prospects engage but none reach closing. Update prompts/handler.md "
                "CLOSING guidance to propose specific meeting times earlier (by message 2).",
        );
    }
    if queued > 0 and contacted == 0 {
        insights.append(
            f"BLOCKED: {queued} prospects are queued but nothing has been sent. "
                "Check the Instantly API key and Sender logs — campaigns may be failing to deploy.",
        );
    }
    if fresh < 10 and queued == 0 {
        insights.append(
            f"ACTION: Prospect pool is nearly empty ({fresh} new). Scout should run "
                "next cycle; if it keeps coming up dry, broaden the ICP in sellbird.yaml.",
        );
    }
    return insights or ["Not enough data yet. Keep prospecting and sending campaigns."];
}
