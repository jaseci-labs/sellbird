import builtins;
import logging;
import from dataclasses { dataclass, field, fields }

glob logger = logging.getLogger("sellbird.pipeline"),
     PROFILE_STALE_DAYS = 90;

@dataclass
class PipelineReport {
    has discover: dict[str, any] | None = None,
        profiled_companies: int = 0,
        profile_observations: int = 0,
        profile_run_id: str = "",
        skipped: str = "",
        errors: list[str] = field(default_factory=builtins.list);

    def as_dict -> dict[str, any] {
        return {f.name: getattr(self, f.name) for f in fields(self)};
    }
}

async def run_profile_stage(
    state: any, limit: int = 100, stale_days: int = PROFILE_STALE_DAYS, config: any = None
) -> tuple[int, int, str] {
    import from sellbird.collectors.profile { profile_companies }
    pending = await state.companies_needing_profile(limit=limit, stale_days=stale_days);
    if not pending {
        return (0, 0, "");
    }
    logger.info("profile: %d companies need a look", len(pending));
    (observations, run_id) = await profile_companies(state, pending, config=config) as any;
    return (len(pending), observations, run_id);
}

async def run_prospecting(
    state: any,
    config: any,
    provider: str | None = None,
    queries: any = None,
    max_spend: float = 1.0,
    profile: bool = True,
    profile_limit: int = 200,
    dry_run: bool = False,
) -> PipelineReport {
    import from sellbird.collectors.discover { DEFAULT_PROVIDER, run_discovery }
    `report = PipelineReport();
    discovery = await run_discovery(
        state, config, provider or DEFAULT_PROVIDER, queries, max_spend=max_spend, dry_run=dry_run
    );
    `report.discover = discovery.as_dict();
    `report.errors.extend(discovery.errors);
    if dry_run or not profile {
        `report.skipped = "dry run" if dry_run else "profiling skipped";
        return `report;
    }
    try {
        (
            `report.profiled_companies,
            `report.profile_observations,
            `report.profile_run_id,
        ) = await run_profile_stage(state, limit=profile_limit, config=config) as any;
    } except Exception as e {
        logger.exception("profile stage failed");
        `report.errors.append(f"profile: {e}");
    }
    return `report;
}
