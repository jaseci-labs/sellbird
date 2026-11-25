import asyncio;

import logging;

import signal;

import sys;

import from datetime { datetime, time, timedelta }

import pytz;

glob ERROR_BACKOFF_BASE = 60,
     ERROR_BACKOFF_CAP = 900,
     CYCLE_TIMEOUT_SECONDS = 600,
     QUIET_HOURS_POLL_SECONDS = 300,
     REPLY_READERS = ("handle_replies", "read_replies"),
     PROSPECT_BACKLOG = 20,
     logger = logging.getLogger("sellbird");

def quiet_http_client_logs {
    for name in ("httpx", "httpcore") {
        logging.getLogger(name).setLevel(logging.WARNING);
    }
}

with entry {
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(name)s] %(levelname)s: %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    );
    quiet_http_client_logs();
}

def in_quiet_hours(config: SellbirdConfig) -> bool {
    qh = config.usage.quiet_hours;
    tz = pytz.timezone(qh.timezone);
    now = datetime.now(tz).time();
    start = time.fromisoformat(qh.start);
    end = time.fromisoformat(qh.end);

    return start <= now and now <= end if start <= end else now >= start or now <= end;
}

def sends_through_quiet_hours(config: SellbirdConfig) -> bool {
    email = config.channels.email;
    window = send_window_of(config);
    return bool(
        window is not None
            and window.recipient_timezone
            and email.enabled
            and email.provider in NATIVE_PROVIDERS,
    );
}

def seconds_until_quiet_hours_end(config: SellbirdConfig) -> int {
    qh = config.usage.quiet_hours;
    tz = pytz.timezone(qh.timezone);
    now = datetime.now(tz);
    end = time.fromisoformat(qh.end);
    end_today = now.replace(hour=end.hour, minute=end.minute, second=0, microsecond=0);

    if end_today <= now {
        end_today += timedelta(days=1);
    }
    return max(int((end_today - now).total_seconds()), 60);
}

def _new_counts(summary: dict[str, any]) -> tuple[int, int] {
    prospects = summary.get("prospects") or {};
    new = (prospects.get("new", 0) if isinstance(prospects, dict) else 0) or 0;
    writable = summary.get("writable_prospects", new) or 0;
    return (new, writable);
}

def unusable_backlog_notice(summary: dict[str, any]) -> str {
    (_, writable) = _new_counts(summary) as any;
    recent = summary.get("recent_unusable_prospects", 0) or 0;
    if writable or recent < PROSPECT_BACKLOG {
        return "";
    }
    return f"Sellbird found {recent} prospects in the last day, but none has a verified or catch-all email, so it paused prospecting for about a day to save search and verifier credits. Add an email verifier key (REOON_API_KEY, ZEROBOUNCE_API_KEY or HUNTER_API_KEY in .env) or check it still has credits. `sellbird export --all` exports the list as it is.";
}

async def decide_next_action(
    brain: Brain, state: StateManager, config: SellbirdConfig, summary: dict[str, any] | None = None
) -> str {
    if summary is None {
        summary = await state.get_state_summary();
    }
    (new_prospects, writable) = _new_counts(summary) as any;
    draft_campaigns = summary.get("draft_campaigns", 0) or 0;
    email = getattr(getattr(config as any, "channels", None), "email", None);
    native_paused = summary.get("sending_paused") and getattr(email, "provider", "") != "instantly";
    held = legacy_sending_held(config) or native_paused or not getattr(email, "enabled", True);
    if not held and draft_campaigns > 0 {
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

async def _run_agents(tasks: list[any]) -> dict[str, any] {
    if not tasks {
        return {};
    }
    if len(tasks) > 1 {
        logger.info(f"Running {len(tasks)} agents in parallel: {[t[0] for t in tasks]}");
    }
    try {
        results = await asyncio.wait_for(
            asyncio.gather(*[t[1] for t in tasks], return_exceptions=True),
            timeout=CYCLE_TIMEOUT_SECONDS,
        );
    } except asyncio.TimeoutError {
        logger.error(
            f"Cycle timed out after {CYCLE_TIMEOUT_SECONDS}s with {[t[0] for t in tasks]} still running — cancelled, moving on to the next heartbeat instead of hanging forever.",
        );
        results = [];
    }
    outcomes: dict[str, any] = {};
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

async def _interruptible_sleep(seconds: float, stop_event: asyncio.Event) -> bool {
    try {
        await asyncio.wait_for(stop_event.wait(), timeout=seconds);
        return True;
    } except asyncio.TimeoutError {
        return False;
    }
}

def send_hold_reason(unread: list[any], paused: str, read_problem: str) -> str | None {
    if paused {
        return None;
    }
    return read_problem or "replies couldn't all be read and handled." if unread else "";
}

async def record_send_phase(state: any, held_reason: str) {
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

async def heartbeat(stop_event: asyncio.Event | None = None) {
    if stop_event is None {
        stop_event = asyncio.Event();
    }

    logger.info("=" * 60);
    logger.info("Sellbird is online.");
    logger.info("=" * 60);

    try {
        config = load_config();
    } except Exception as e {
        logger.error(f"Cannot start — configuration error:\n{e}");
        return;
    }
    env = load_env();
    state = StateManager();
    brain = Brain(state, config.brain);
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

    scout = Scout(brain, state, config, env);
    writer = Writer(brain, state, config, env);
    sender = Sender(brain, state, config, env);
    handler = Handler(brain, state, config, env);
    analyst = Analyst(state);

    interval = config.usage.heartbeat_interval_minutes * 60;
    max_calls = max(int(200 * (config.usage.max_daily_claude_percent / 100)), 1);
    consecutive_errors = 0;

    while not stop_event.is_set() {
        try {
            await sync_sending_mode(config, state);
            quiet = in_quiet_hours(config);
            send_only = quiet and sender.is_native and sends_through_quiet_hours(config);
            if quiet and not send_only {
                logger.info(
                    f"Quiet hours. Sleeping for {seconds_until_quiet_hours_end(config) // 60} minutes.",
                );
                stopping = False;
                while not stopping and in_quiet_hours(config) {
                    stopping = await _interruptible_sleep(QUIET_HOURS_POLL_SECONDS, stop_event);
                }
                if stopping {
                    break;
                }
                continue;
            }
            sender.cold_only = send_only;
            nap = 0;
            if send_only and not await sender.cold_due_in_window() {
                logger.info(
                    f"Quiet hours. No cold email can go now; checking again in {config.usage.heartbeat_interval_minutes} minutes.",
                );
                nap = interval;
            } else {
                problem = await brain.preflight();
                if problem {
                    logger.error(
                        f"Sellbird is paused: {problem} Nothing was sent or changed. Re-checking in {config.usage.heartbeat_interval_minutes} minutes.",
                    );
                    nap = interval;
                } elif not await brain.is_within_budget(
                    max_calls, max_percent=config.usage.max_daily_claude_percent
                ) {
                    logger.info(
                        f"{brain.provider_label} usage limit reached ({config.usage.max_daily_claude_percent}% of quota or {max_calls} calls). Sleeping 1h, then re-checking.",
                    );
                    nap = 3600;
                }
            }
            if nap {
                if await _interruptible_sleep(nap, stop_event) {
                    break;
                }
                continue;
            }
            if send_only {
                logger.info(
                    "Quiet hours: reading replies, then sending what's due in recipients' own time zones.",
                );
                summary: dict[str, any] = {};
                action = "quiet_hours_send";
            } else {
                logger.info("Checking pipeline state...");
                summary = await state.get_state_summary();
                action = await decide_next_action(brain, state, config, summary=summary);
            }
            tasks = [];
            has_open_convos = summary.get("open_conversations", 0)
                + summary.get("auto_reply_handoffs", 0)
                > 0;

            if action == "prospect" {
                tasks.append(("prospect", scout.run()));
                tasks.append(("analyze", analyst.run()));
            } elif action == "write_campaign" {
                tasks.append(("write_campaign", writer.run()));
            } elif action == "idle" {
                tasks.append(("analyze", analyst.run()));
            }
            send_name = "send_campaign"
                if action == "send_campaign"
                else "send_outbox" if sender.is_native else "";
            if sender.is_native or has_open_convos {
                tasks.append(("handle_replies", handler.run()));
            }
            if summary.get("unprofiled", 0) {
                tasks.append(("profile", run_profile_stage(state, limit=25, config=config)));
            }

            outcomes = await _run_agents(tasks);
            if send_name {
                unread = [
                    n
                    for (n, _) in tasks
                    if n in REPLY_READERS and outcomes.get(n) is not True
                ];
                paused = brain.paused_reason;
                if paused or unread {
                    reason = paused or "replies couldn't all be read and handled.";
                    logger.error(
                        f"Not sending this cycle: {reason} Queued emails wait until replies can be read again.",
                    );
                    held = send_hold_reason(
                        unread, paused, getattr(handler, "last_read_problem", "")
                    );
                    if held is not None {
                        await record_send_phase(state, held);
                    }
                } else {
                    await record_send_phase(state, send_hold_reason([], "", ""));
                    await _run_agents([(send_name, sender.run())]);
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
            backoff = min(ERROR_BACKOFF_BASE * 2 ** (consecutive_errors - 1), ERROR_BACKOFF_CAP);
            logger.error(f"Error in heartbeat (failure #{consecutive_errors}): {e}", exc_info=True);
            logger.info(f"Recovering... sleeping {backoff}s before retry.");
            if await _interruptible_sleep(backoff, stop_event) {
                break;
            }
        }
    }

    logger.info("Sellbird shutting down. Deals don't close themselves, but I need a break.");
}

def _needs_setup -> bool {
    import from sellbird.paths { PROJECT_ROOT }
    import from sellbird.config { _find_config_file, ConfigFileNotFoundError }

    if not (PROJECT_ROOT / ".env").exists() {
        return True;
    }
    try {
        config_file = _find_config_file();
    } except ConfigFileNotFoundError {
        return True;
    }

    try {
        import yaml;
        import from sellbird.textio { read_user_text }
        config = yaml.safe_load(read_user_text(config_file));
        return not isinstance(config, dict)
            or (config.get("persona") or {}).get("company", "") in ("Your Company", "");
    } except Exception {
        return True;
    }
}

async def _run_with_signals {
    stop_event = asyncio.Event();
    loop = asyncio.get_running_loop();

    def _request_shutdown(sig_name: str) -> any {
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

def main {
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
    lock = hold_loop_lock(LOCK_FILE);
    if lock is None {
        running = read_pid();
        pid = f" (pid {running})" if running else "";
        print(
            f"Sellbird is already running{pid}. Stop it first, from the dashboard or with Ctrl+C in its terminal.",
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

with entry:__main__ {
    import from sellbird.textio { utf8_stdio }
    utf8_stdio();
    main();
}
