"""Sellbird's main heartbeat loop."""

import builtins;

import operator;

import asyncio;

import from typing { Any }

import logging;

import signal;

import sys;

import from datetime { datetime, time, timedelta }

import pytz;

glob logger: any;

glob ERROR_BACKOFF_BASE: any;

glob ERROR_BACKOFF_CAP: any;

glob CYCLE_TIMEOUT_SECONDS: any;

glob QUIET_HOURS_POLL_SECONDS: any;

glob REPLY_READERS: any;

glob PROSPECT_BACKLOG: any;

with entry {
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(name)s] %(levelname)s: %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    );
    logger = logging.getLogger("sellbird");
}

"""Keep request URLs out of the terminal.

    httpx logs every request at INFO ("HTTP Request: GET https://...") with
    the full query string. Reoon and ZeroBounce only accept their API key as
    a query parameter, so at INFO `sellbird run` would print those keys in
    clear text on every verification. Nothing in those lines is useful to a
    user, so both client loggers sit at WARNING.
    """
def quiet_http_client_logs -> any;

with entry {
    quiet_http_client_logs();
    ERROR_BACKOFF_BASE = 60;
    ERROR_BACKOFF_CAP = 900;
    CYCLE_TIMEOUT_SECONDS = 600;
    QUIET_HOURS_POLL_SECONDS = 300;
    REPLY_READERS = ("handle_replies", "read_replies");
}

"""Check if we're currently in quiet hours."""
def in_quiet_hours(config: SellbirdConfig) -> builtins.bool;

"""True when quiet hours pause Sellbird's own work but not cold email
    that is due in its recipient's window.

    With a send window in each recipient's time zone, the operator's night
    can be a recipient's morning. Prospecting and writing still sleep, and
    replies wait for the operator's hours as before. A heartbeat wakes only
    when a cold email can go now (Sender.cold_due_in_window): it reads and
    handles replies first (so stop-on-reply has run; reading a reply is what
    consumes it, so it can't be left for the morning), then runs the sender,
    which stages any draft campaign into the outbox (no model call, nothing
    sent) and sends only cold email. Otherwise it does nothing. Native mail
    providers only.
    """
def sends_through_quiet_hours(config: SellbirdConfig) -> builtins.bool;

"""Calculate seconds until quiet hours end."""
def seconds_until_quiet_hours_end(config: SellbirdConfig) -> builtins.int;

with entry {
    PROSPECT_BACKLOG = 20;
}

"""(all 'new' prospects, the ones the Writer can draft for)."""
def _new_counts(summary: builtins.dict) -> builtins.tuple[builtins.int, builtins.int];

"""Why Sellbird paused prospecting for the day, or ""."""
def unusable_backlog_notice(summary: builtins.dict) -> builtins.str;

"""Decide what Sellbird should do next based on current state.

    Uses deterministic priority rules (send_campaign > write_campaign >
    prospect > idle) instead of burning a Claude call on a decision that is
    fully derivable from pipeline counts. This saves budget every cycle and
    removes a fragile LLM string-parsing step.

    Replies are not an action here: the handler rides along every cycle
    there is a mailbox or an open conversation to read. Making an open
    conversation the top priority starved everything else for as long as it
    stayed open, and one waiting on the prospect can stay open for weeks.
    """
async def decide_next_action(
    brain: Brain, state: StateManager, config: SellbirdConfig, summary: builtins.dict | None = None
) -> builtins.str;

"""Run (name, coroutine) pairs in parallel; return {name: outcome}.

    Errors are caught per task so one bad agent never takes down the cycle,
    and the whole batch is bounded so one HUNG agent (no exception, just
    never returns) can't either. A task's outcome is what it returned, or
    the exception it raised; a task cut off by the bound has no outcome.
    """
async def _run_agents(tasks: builtins.list) -> builtins.dict;

"""Sleep up to `seconds`, waking immediately on shutdown.

    Returns True if a shutdown was requested during the sleep.
    """
async def _interruptible_sleep(seconds: builtins.float, stop_event: asyncio.Event) -> builtins.bool;

"""What to record about this cycle's send phase: why sending is held by
    unread replies, "" when it ran (clear the note), or None to leave the
    note alone (a paused brain has its own Today card)."""
def send_hold_reason(
    unread: builtins.list, paused: builtins.str, read_problem: builtins.str
) -> builtins.str | None;

"""Note why sending was held this cycle (Today and `sellbird status` show
    it), or clear the note when sending ran. Never stops the loop."""
async def record_send_phase(state, held_reason: builtins.str) -> any;

"""Sellbird's main loop. Wakes up, decides, acts, sleeps. Repeat."""
async def heartbeat(stop_event: asyncio.Event | None = None) -> any;

"""Check if Sellbird needs first-time setup."""
def _needs_setup -> builtins.bool;

"""Run the heartbeat with SIGINT/SIGTERM wired to a graceful shutdown."""
async def _run_with_signals -> any;

"""Entry point."""
def main -> any;

with entry:__main__ {
    import from sellbird.textio { utf8_stdio }
    utf8_stdio();
    main();
}
