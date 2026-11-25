impl quiet_http_client_logs -> any {
    for name in ("httpx", "httpcore") {
        logging.getLogger(name).setLevel(logging.WARNING);
    }
}

impl in_quiet_hours(config: SellbirdConfig) -> builtins.bool {
    qh: any = config.usage.quiet_hours;
    tz: any = pytz.timezone(qh.timezone);
    now: any = datetime.now(tz).time();
    start: any = time.fromisoformat(qh.start);
    end: any = time.fromisoformat(qh.end);

    if start <= end {
        return operator.le(start, now) and operator.le(now, end);
    }
    return operator.ge(now, start) or operator.le(now, end);
}

impl sends_through_quiet_hours(config: SellbirdConfig) -> builtins.bool {
    email: any = config.channels.email;
    window: any = send_window_of(config);
    return `bool(
        window is not None
            and window.recipient_timezone
            and email.enabled
            and email.provider in NATIVE_PROVIDERS,
    );
}

impl seconds_until_quiet_hours_end(config: SellbirdConfig) -> builtins.int {
    qh: any = config.usage.quiet_hours;
    tz: any = pytz.timezone(qh.timezone);
    now: any = datetime.now(tz);
    end: any = time.fromisoformat(qh.end);
    end_today: any = now.replace(hour=end.hour, minute=end.minute, second=0, microsecond=0);

    if end_today <= now {
        end_today = end_today + timedelta(days=1);
    }

    delta: any = end_today - now;
    return max(`int(delta.total_seconds()), 60);
}

impl _new_counts(summary: builtins.dict) -> builtins.tuple[builtins.int, builtins.int] {
    prospects: any = summary.get("prospects") or {};
    new: any = (prospects.get("new", 0) if isinstance(prospects, `dict) else 0) or 0;
    writable: any = summary.get("writable_prospects", new) or 0;
    return (new, writable);
}

impl unusable_backlog_notice(summary: builtins.dict) -> builtins.str {
    _: any;
    writable: any;
    (_, writable) = _new_counts(summary) as any;
    recent: any = summary.get("recent_unusable_prospects", 0) or 0;
    if writable or recent < PROSPECT_BACKLOG {
        return "";
    }
    return f"Sellbird found {recent} prospects in the last day, but none has a verified or catch-all email, so it paused prospecting for about a day to save search and verifier credits. Add an email verifier key (REOON_API_KEY, ZEROBOUNCE_API_KEY or HUNTER_API_KEY in .env) or check it still has credits. `sellbird export --all` exports the list as it is.";
}

impl decide_next_action(
    brain: Brain, state: StateManager, config: SellbirdConfig, summary: builtins.dict | None = None
) -> builtins.str {
    if summary is None {
        summary = await state.get_state_summary();
    }
    new_prospects: any;
    writable: any;
    (new_prospects, writable) = _new_counts(summary) as any;
    draft_campaigns: any = summary.get("draft_campaigns", 0) or 0;
    loose: Any = config;
    email: any = getattr(getattr(loose, "channels", None), "email", None);
    native_paused: any = summary.get("sending_paused")
        and operator.ne(getattr(email, "provider", ""), "instantly");
    held: any = legacy_sending_held(config) or native_paused or not getattr(email, "enabled", True);
    deployable: any = 0 if held else draft_campaigns;

    if deployable > 0 {
        action: any;
        reason: any;
        (action, reason) = (
            "send_campaign",
            f"{draft_campaigns} draft campaign(s) ready to deploy",
        );
    } elif writable > 0 {
        (action, reason) = ("write_campaign", f"{writable} new prospect(s) with no drafts ready");
    } elif unusable_backlog_notice(summary) {
        (action, reason) = ("idle", "a day's worth of prospects with no usable email");
        logger.warning(unusable_backlog_notice(summary));
    } else {
        (action, reason) = (
            "prospect",
            f"{new_prospects} new prospect(s), none ready to write for",
        );
    }

    logger.info(f"Decision: {action} ({reason})");
    return action;
}

impl _run_agents(tasks: builtins.list) -> builtins.dict {
    if not tasks {
        return {};
    }
    if len(tasks) > 1 {
        logger.info(f"Running {len(tasks)} agents in parallel: {[t[0] for t in tasks]}");
    }
    try {
        results: any = await asyncio.wait_for(
            asyncio.gather(*[t[1] for t in tasks], return_exceptions=True),
            timeout=CYCLE_TIMEOUT_SECONDS,
        );
    } except asyncio.TimeoutError {
        logger.error(
            f"Cycle timed out after {CYCLE_TIMEOUT_SECONDS}s with {[t[0] for t in tasks]} still running — cancelled, moving on to the next heartbeat instead of hanging forever.",
        );
        results = [];
    }
    outcomes: any = {};
    for ((name, _), result) in zip(tasks, results) {
        if isinstance(result, asyncio.CancelledError) {
            raise result;
        }
        if isinstance(result, Exception) {
            logger.error(f"Agent {name} failed: {result}", exc_info=result);
        }
        outcomes[name] = result;
    }
    return outcomes;
}

impl _interruptible_sleep(seconds: builtins.float, stop_event: asyncio.Event) -> builtins.bool {
    try {
        await asyncio.wait_for(stop_event.wait(), timeout=seconds);
        return True;
    } except asyncio.TimeoutError {
        return False;
    }
}

impl send_hold_reason(
    unread: builtins.list, paused: builtins.str, read_problem: builtins.str
) -> builtins.str | None {
    if paused {
        return None;
    }
    if unread {
        return read_problem or "replies couldn't all be read and handled.";
    }
    return "";
}

impl record_send_phase(state, held_reason: builtins.str) -> any {
    try {
        if held_reason {
            await state.note_sends_held(held_reason);
        } else {
            await state.clear_sends_held();
        }
    } except Exception as e {
        logger.warning(f"Couldn't record the send hold: {e}");
    }
}

impl heartbeat(stop_event: asyncio.Event | None = None) -> any {
    if stop_event is None {
        stop_event = asyncio.Event();
    }

    logger.info("=" * 60);
    logger.info("Sellbird is online.");
    logger.info("=" * 60);

    try {
        config: any = load_config();
    } except (ConfigError, Exception) as e {
        if isinstance(e, (KeyboardInterrupt, asyncio.CancelledError)) {
            raise;
        }
        logger.error(f"Cannot start — configuration error:\n{e}");
        return;
    }
    env: any = load_env();
    state: any = StateManager();
    brain: any = Brain(state, config.brain);
    logger.info(
        f"Thinking with {brain.provider_label}"
            + (f" ({brain.model})" if brain.model else "")
            + ". Change brain.provider in sellbird.yaml to switch.",
    );
    for notice in (sending_notice(config), compliance_notice(config)) {
        if notice {
            logger.warning("=" * 60);
            logger.warning(notice);
            logger.warning("=" * 60);
        }
    }

    await state.init_db();
    logger.info("Database initialized.");
    import from sellbird.agents.scout { Scout }
    import from sellbird.agents.writer { Writer }
    import from sellbird.agents.sender { Sender }
    import from sellbird.agents.handler { Handler }
    import from sellbird.agents.analyst { Analyst }

    scout: any = Scout(brain, state, config, env);
    writer: any = Writer(brain, state, config, env);
    sender: any = Sender(brain, state, config, env);
    handler: any = Handler(brain, state, config, env);
    analyst: any = Analyst(state);

    interval: any = config.usage.heartbeat_interval_minutes * 60;
    max_calls: any = max(`int(200 * (config.usage.max_daily_claude_percent / 100)), 1);
    consecutive_errors: any = 0;

    while not stop_event.is_set() {
        try {
            await sync_sending_mode(config, state);
            quiet: any = in_quiet_hours(config);
            send_only: any = quiet and sender.is_native and sends_through_quiet_hours(config);
            if quiet and not send_only {
                sleep_for: any = seconds_until_quiet_hours_end(config);
                logger.info(f"Quiet hours. Sleeping for {sleep_for // 60} minutes.");
                shutting_down: any = False;
                while in_quiet_hours(config) {
                    if await _interruptible_sleep(QUIET_HOURS_POLL_SECONDS, stop_event) {
                        shutting_down = True;
                        break;
                    }
                }
                if shutting_down {
                    break;
                }
                continue;
            }
            sender.cold_only = send_only;
            if send_only and not await sender.cold_due_in_window() {
                logger.info(
                    f"Quiet hours. No cold email can go now; checking again in {config.usage.heartbeat_interval_minutes} minutes.",
                );
                if await _interruptible_sleep(interval, stop_event) {
                    break;
                }
                continue;
            }
            problem: any = await brain.preflight();
            if problem {
                logger.error(
                    f"Sellbird is paused: {problem} Nothing was sent or changed. Re-checking in {config.usage.heartbeat_interval_minutes} minutes.",
                );
                if await _interruptible_sleep(interval, stop_event) {
                    break;
                }
                continue;
            }
            if not await brain.is_within_budget(
                max_calls, max_percent=config.usage.max_daily_claude_percent
            ) {
                logger.info(
                    f"{brain.provider_label} usage limit reached ({config.usage.max_daily_claude_percent}% of quota or {max_calls} calls). Sleeping 1h, then re-checking.",
                );
                if await _interruptible_sleep(3600, stop_event) {
                    break;
                }
                continue;
            }
            if send_only {
                logger.info(
                    "Quiet hours: reading replies, then sending what's due in recipients' own time zones.",
                );
                summary: any = {};
                action: any = "quiet_hours_send";
            } else {
                logger.info("Checking pipeline state...");
                summary = await state.get_state_summary();
                action = await decide_next_action(brain, state, config, summary=summary);
            }
            tasks: any = [];
            has_open_convos: any = operator.gt(
                summary.get("open_conversations", 0) + summary.get("auto_reply_handoffs", 0), 0
            );

            if action == "prospect" {
                tasks.append(("prospect", scout.run()));
                tasks.append(("analyze", analyst.run()));
            } elif action == "write_campaign" {
                tasks.append(("write_campaign", writer.run()));
            } elif action == "idle" {
                tasks.append(("analyze", analyst.run()));
            }
            send_tasks: any = [];
            if action == "send_campaign" {
                send_tasks.append(("send_campaign", sender.run));
            } elif sender.is_native {
                send_tasks.append(("send_outbox", sender.run));
            }
            if sender.is_native or has_open_convos {
                tasks.append(("handle_replies", handler.run()));
            }
            if summary.get("unprofiled", 0) {
                tasks.append(("profile", run_profile_stage(state, limit=25, config=config)));
            }

            outcomes: any = await _run_agents(tasks);
            if send_tasks {
                unread: any = [
                    n
                    for (n, _) in tasks
                    if n in REPLY_READERS and outcomes.get(n) is not True
                ];
                paused: any = brain.paused_reason;
                if paused or unread {
                    reason: any = paused or "replies couldn't all be read and handled.";
                    logger.error(
                        f"Not sending this cycle: {reason} Queued emails wait until replies can be read again.",
                    );
                    held: any = send_hold_reason(
                        unread, paused, getattr(handler, "last_read_problem", "")
                    );
                    if held is not None {
                        await record_send_phase(state, held);
                    }
                } else {
                    await record_send_phase(state, send_hold_reason([], "", ""));
                    await _run_agents([(name, run()) for (name, run) in send_tasks]);
                }
            }
            try {
                await state.log_action(action_type=action, agent="main");
            } except Exception as e {
                logger.warning(f"Failed to log action '{action}': {e}");
            }
            await run_tick_steps(config, state);

            consecutive_errors = 0;
            logger.info(
                f"Cycle complete. Sleeping for {config.usage.heartbeat_interval_minutes} minutes."
            );
            if await _interruptible_sleep(interval, stop_event) {
                break;
            }
        } except (KeyboardInterrupt, asyncio.CancelledError) {
            break;
        } except Exception as e {
            consecutive_errors += 1;
            backoff: any = min(
                ERROR_BACKOFF_BASE * 2 ** (consecutive_errors - 1), ERROR_BACKOFF_CAP
            );
            logger.error(f"Error in heartbeat (failure #{consecutive_errors}): {e}", exc_info=True);
            logger.info(f"Recovering... sleeping {backoff}s before retry.");
            if await _interruptible_sleep(backoff, stop_event) {
                break;
            }
        }
    }

    logger.info("Sellbird shutting down. Deals don't close themselves, but I need a break.");
}

impl _needs_setup -> builtins.bool {
    import from sellbird.paths { PROJECT_ROOT }
    import from sellbird.config { _find_config_file, ConfigFileNotFoundError }

    env_file: any = PROJECT_ROOT / ".env";
    if not env_file.exists() {
        return True;
    }
    try {
        config_file: any = _find_config_file();
    } except ConfigFileNotFoundError {
        return True;
    }

    try {
        import yaml;
        import from sellbird.textio { read_user_text }
        config: any = yaml.safe_load(read_user_text(config_file));
        if not isinstance(config, `dict) {
            return True;
        }
        company: any = (config.get("persona") or {}).get("company", "");
        if company in ("Your Company", "") {
            return True;
        }
    } except Exception {
        return True;
    }

    return False;
}

impl _run_with_signals -> any {
    stop_event: any;
    stop_event = asyncio.Event();
    loop: any = asyncio.get_running_loop();

    def _request_shutdown(sig_name: builtins.str) -> any {
        if stop_event.is_set() {
            logger.info("Second shutdown signal — exiting immediately.");
            sys.exit(1);
        }
        logger.info(f"Received {sig_name}. Finishing current work, then shutting down...");
        stop_event.set();
    }

    for sig in (signal.SIGINT, signal.SIGTERM) {
        try {
            loop.add_signal_handler(sig, _request_shutdown, sig.name);
        } except (NotImplementedError, RuntimeError) {
            signal.signal(sig, lambda (s, f) -> any { _request_shutdown(signal.Signals(s).name) });
        }
    }

    await heartbeat(stop_event);
}

impl main -> any {
    if _needs_setup() {
        if not sys.stdin.isatty() {
            print("Sellbird isn't set up yet. Run `sellbird setup` in a terminal first.");
            sys.exit(1);
        }
        print("\n  First time running Sellbird? Let's get you set up.\n");
        import from sellbird.setup { run_setup }
        asyncio.run(run_setup());
        return;
    }
    lock: any = hold_loop_lock(LOCK_FILE);
    if lock is None {
        running: any = read_pid();
        print(
            "Sellbird is already running"
                + format(f" (pid {running})" if running else "", "")
                + ". Stop it first, from the dashboard or with Ctrl+C in its terminal.",
        );
        sys.exit(1);
    }
    write_pid_file();
    try {
        asyncio.run(_run_with_signals());
    } except KeyboardInterrupt {
        logger.info("Goodbye.");
    } finally {
        remove_pid_file();
        release_loop_lock(lock);
    }
}
