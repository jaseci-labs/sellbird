"""The prospecting pipeline: DISCOVER → PROFILE → (people, verification).

Each stage is independently runnable and independently re-runnable. That is
the point of the design, not an accident of it: profiling can re-run without
re-buying discovery, and discovery can widen without re-profiling everyone.

What chains them is a *query*, not a hand-off. PROFILE asks the database
"which companies have I not looked at, or not looked at lately?" rather than
being handed a list by DISCOVER. So a profile run started for any reason
picks up whatever discovery left behind, a crashed run resumes by itself, and
re-observing on a schedule turns the same signal into a time series.

Segment before you enrich: enrichment cost scales with list size and
conversion does not, so profile the businesses you would actually contact,
not every row you hold.
"""

import builtins;

import logging;

import from dataclasses { dataclass, field }

glob logger: any = logging.getLogger("sellbird.pipeline");

glob PROFILE_STALE_DAYS: any = 90;

"""What a full pass did, stage by stage."""
@dataclass
class PipelineReport {
    has discover: builtins.dict | None = None;

    has profiled_companies: builtins.int = 0;

    has profile_observations: builtins.int = 0;

    has profile_run_id: builtins.str = "";

    has skipped: builtins.str = "";

    has errors: builtins.list[builtins.str] = field(default_factory=list[any]);

    def as_dict -> builtins.dict {
        return {
            "discover": self.discover,
            "profiled_companies": self.profiled_companies,
            "profile_observations": self.profile_observations,
            "profile_run_id": self.profile_run_id,
            "skipped": self.skipped,
            "errors": self.errors,
        };
    }
}

glob stale_days_default_: any;

with entry {
    stale_days_default_ = PROFILE_STALE_DAYS;
}

"""Profile whatever currently needs it.

    Returns (companies, observations, run_id). Free — three HTTP requests per
    business, no browser, no model call — so it is safe to run on every
    heartbeat without touching the Claude budget. ``config`` says which open
    roles count as hiring intent (``icp.hiring_signals``, else ``icp.titles``).
    """
async def run_profile_stage(
    state, limit: builtins.int = 100, stale_days: builtins.int = stale_days_default_, config=None
) -> builtins.tuple[builtins.int, builtins.int, builtins.str] {
    import from sellbird.collectors.profile { profile_companies }

    pending: any = await state.companies_needing_profile(limit=limit, stale_days=stale_days);
    if not pending {
        return (0, 0, "");
    }

    logger.info("profile: %d companies need a look", len(pending));
    observations: any;
    run_id: any;
    (observations, run_id) = await profile_companies(state, pending, config=config) as any;
    return (len(pending), observations, run_id);
}

"""Discover businesses, then read what their websites say about them.

    The two stages are deliberately not coupled through a list: profiling
    queries the database for what needs attention, so it also sweeps up
    anything an earlier run left unfinished.
    """
async def run_prospecting(
    state,
    config,
    provider: builtins.str | None = None,
    queries=None,
    max_spend: builtins.float = 1.0,
    profile: builtins.bool = True,
    profile_limit: builtins.int = 200,
    dry_run: builtins.bool = False,
) -> PipelineReport {
    import from sellbird.collectors.discover { DEFAULT_PROVIDER, run_discovery }

    `report: any = PipelineReport();

    discovery: any = await run_discovery(
        state, config, provider or DEFAULT_PROVIDER, queries, max_spend=max_spend, dry_run=dry_run
    );
    `report.discover = discovery.as_dict();
    `report.errors.extend(discovery.errors);

    if dry_run {
        `report.skipped = "dry run";
        return `report;
    }
    if not profile {
        `report.skipped = "profiling skipped";
        return `report;
    }
    try {
        companies: any;
        observations: any;
        run_id: any;
        (companies, observations, run_id) = await run_profile_stage(
            state, limit=profile_limit, config=config
        ) as any;
        `report.profiled_companies = companies;
        `report.profile_observations = observations;
        `report.profile_run_id = run_id;
    } except Exception as e {
        logger.exception("profile stage failed");
        `report.errors.append(f"profile: {e}");
    }

    return `report;
}
