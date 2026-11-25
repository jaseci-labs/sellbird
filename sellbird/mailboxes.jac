import builtins;
import importlib;
import json;
import logging;
import sqlite3;
import aiosqlite;
import from dataclasses { dataclass, field, fields }
import from datetime { date, datetime, timezone }

glob logger = logging.getLogger("sellbird.mailboxes"),
     MAIN = "",
     PROVIDERS = ("google", "microsoft", "smtp"),
     BUILT_IN_CONNECTIONS = ("oauth", "smtp"),
     HARD_MAX_INBOX_CAP = 500,
     PER_INBOX_CAP_DEFAULT = 30,
     _UNSENT = ("pending_review", "approved"),
     _STARTED = ("sent", "sending"),
     MAX_KEYCHAIN_TOKEN_CHARS = 1200,
     _KEPT_TOKEN_FIELDS = ("refresh_token", "tenant"),
     _OAUTH_PROVIDERS = {
         "google": ("gmail", "GmailProvider"),
         "microsoft": ("microsoft", "MicrosoftProvider"),
     },
     _FINGERPRINT = "connection provider address display_name credential_ref settings_json".split();

class MailboxExists(Exception) {}

class ConnectRefused(Exception) {}

class TokenTooLarge(ConnectRefused) {
    def init(provider: str = "Microsoft");
}

def _integration(name: str) -> any;

def oauth_ref(mailbox_id: str) -> str;

def smtp_ref(mailbox_id: str) -> str;

def keychain_token(token: builtins.dict, provider: str = "Microsoft") -> str;

class KeychainTokenSource {
    has _secrets: any = None,
        _ref: str = "";

    def init(secrets: any, ref: str);

    def load -> builtins.dict | None;

    def save(data: builtins.dict);

    def missing_reason -> str;

    def __repr__ -> str;
}

class MailboxStore(StateManager) {
    async def _rows(query: str, args: tuple[any, ...] = ()) -> list[builtins.dict];

    async def list_mailboxes(*, include_retired: bool = False) -> list[builtins.dict];

    async def get_mailbox(mailbox_id: str) -> builtins.dict | None;

    async def get_mailbox_by_address(address: str) -> builtins.dict | None;

    async def add_mailbox(
        *,
        mailbox_id: str,
        address: str,
        provider: str,
        connection: str,
        display_name: str = "",
        credential_ref: str = "",
        settings: builtins.dict | None = None,
        warmup_started_at: str = "",
    ) -> str;

    async def set_pause(mailbox_id: str, reason: str) -> bool;

    async def set_cap(mailbox_id: str, cap: int | None) -> bool;

    async def set_display_name(mailbox_id: str, name: str) -> bool;

    async def retire(mailbox_id: str) -> bool;

    async def set_campaign_pool(campaign_id: str, mailbox_ids: list[str]);

    async def campaign_pool(campaign_id: str) -> set[str];

    async def campaign_pools -> dict[str, set[str]];

    async def sent_since(mailbox_id: str, since_iso: str, kind: str | None = None) -> int;

    async def queued_first_emails -> dict[str, int];

    async def unsent_off_main -> bool;

    async def thread_started(campaign_id: str, prospect_id: str) -> bool;

    async def thread_mailbox(campaign_id: str, prospect_id: str) -> str;

    async def set_thread_mailbox(campaign_id: str, prospect_id: str, mailbox_id: str);

    async def conversation_mailbox(conversation_id: str) -> str;
}

def _local_midnight_utc_iso(now: datetime) -> str;

def per_inbox_cap(email_cfg: any) -> int;

def inbox_cold_cap(row: builtins.dict, email_cfg: any, today: date | None = None) -> int;

def _ramped(email_cfg: any, ceiling: int, today: date) -> int;

def _smtp_settings(row: builtins.dict, password: str) -> any;

def build_provider(row: builtins.dict, *, config: any, env: any, secrets: any) -> any;

def check_provider_allows_inboxes(config: any);

async def _check_address(store: MailboxStore, config: any, address: str) -> tuple[str, str];

def check_warmup_start(value: str) -> str;

async def _insert(store: MailboxStore, **row: any) -> str;

async def connect_oauth_mailbox(
    store: MailboxStore,
    secrets: any,
    config: any,
    *,
    provider: str,
    address: str,
    display_name: str,
    warmup_started_at: str,
    token: builtins.dict,
) -> str;

async def connect_smtp_mailbox(
    store: MailboxStore,
    secrets: any,
    config: any,
    *,
    address: str,
    display_name: str,
    warmup_started_at: str,
    settings: any,
) -> str;

@dataclass
class Inbox {
    has id: str,
        address: str,
        name: str,
        provider: any,
        cap: int,
        sent_today: int,
        queued_first: int,
        paused_reason: str = "",
        sent_this_cycle: int = 0;

    @builtins.property
    def main -> bool;

    @builtins.property
    def connected -> bool;

    @builtins.property
    def cold_left -> int;

    @builtins.property
    def room -> int;
}

@dataclass(frozen=True)
class Route {
    has action: str,
        mailbox_id: str = MAIN,
        reason: str = "";
}

@dataclass
class Inboxes {
    has store: any,
        inboxes: dict[str, Inbox],
        pools: dict[str, set[str]] = field(default_factory=dict[str, set[str]]),
        routed_mail: bool = False;

    @builtins.property
    def several -> bool;

    def get(mailbox_id: str) -> Inbox | None;

    def sendable -> list[Inbox];

    def readers -> list[Inbox];

    def eligible(campaign_id: str) -> list[Inbox];

    def pick(campaign_id: str) -> Inbox | None;

    async def assign(campaign_id: str, prospect_id: str, *, staged_now: bool = False) -> str | None;

    async def route(item: builtins.dict) -> Route;
}

def _fingerprint(row: builtins.dict) -> tuple[any, ...];

async def load_inboxes(
    state: any,
    config: any,
    env: any,
    main_provider: any,
    *,
    secrets: any = None,
    now: datetime | None = None,
    cache: builtins.dict | None = None,
) -> Inboxes;

def _cached_provider(
    row: builtins.dict, cache: builtins.dict | None, config: any, env: any, secrets: any
) -> any;
