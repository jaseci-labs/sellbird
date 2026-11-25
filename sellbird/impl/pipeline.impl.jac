impl PipelineReport.as_dict -> builtins.dict {
    return {
        "discover": self.discover,
        "profiled_companies": self.profiled_companies,
        "profile_observations": self.profile_observations,
        "profile_run_id": self.profile_run_id,
        "skipped": self.skipped,
        "errors": self.errors,
    };
}

impl run_profile_stage(
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

impl run_prospecting(
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
