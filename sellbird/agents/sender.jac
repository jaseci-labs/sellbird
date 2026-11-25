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

def _utcnow -> datetime;
def _local_now -> datetime;
def _now_iso -> str;
def _since_midnight(now: datetime) -> str;
def _names(prospect: any) -> list[str];
def _merge_fields(p: any) -> str;
def _at(value: any) -> any;
def _text(thing: any, attr: str) -> str;
def _new(have: list[any], items: list[any]) -> list[any];

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

    def init(brain: any, state: any, config: any, env: any);

    @builtins.property
    def is_native -> bool;

    async def _send_zone(
        prospect: any, country: str = "", given: str = "", names: any = ("", "")
    ) -> str;
    async def _zone_or_default(
        prospect: any, country: str = "", given: str = "", names: any = ("", "")
    ) -> str;
    async def _recipient_country(prospect: any) -> str;
    async def _recipient_names(prospect: any) -> tuple[str, str];
    async def _facts(prospect: any, wanted: bool) -> tuple[str, any];
    async def _cached(item: any, country: str, names: any) -> any;
    async def _has_cached_verdict(item: any) -> bool;
    async def _due(due_before: str, limit: int, **query: any) -> list[any];
    async def cold_due_in_window -> bool;
    async def _outside_window(item: any, zone: str, window: any) -> bool;
    async def _set(item: any, **fields: any);
    async def run;
    def _validate_sequence(campaign: any) -> bool;
    async def _leads(campaign: any, instantly: bool) -> tuple[list[any], int, int];
    def _reviewed_leads(prospects: list[any]) -> list[any];
    async def _deploy_campaign(campaign: any);
    async def _count_sends_today -> int;
    async def _run_native;
    async def _load_inboxes -> any;
    def _render(text: str, prospect: any) -> str;
    async def _stage_campaign_native(campaign: any);
    def _with_footer(body: str) -> str;
    def _outgoing_body(item: any) -> str;
    async def _follow_up_order(item: any, prospect: any = None) -> any;
    async def _retry_later(
        item: any, reason: str, after: any = ADDRESS_RETRY_AFTER, prefix: str = RECHECK_PREFIX
    ) -> datetime;
    async def _blocked(item: any, prospect: any, allow_risky: bool) -> any;
    async def _held(item: any, prospect: any, allow_risky: bool) -> bool;
    async def _drain_due;
}
