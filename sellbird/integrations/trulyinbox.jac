import builtins;
import hashlib;
import json;
import math;
import os;
import from dataclasses { dataclass }
import from datetime { date, datetime, timezone }
import httpx;

glob API_BASE: str = "https://lynx-api.trulyinbox.com",
     AFFILIATE_URL: str = "https://trulyinbox.com/?via=sellbird",
     AFFILIATE_TAG: str = "(affiliate link)",
     TIMEOUT: any = httpx.Timeout(connect=10.0, read=20.0, write=10.0, pool=10.0),
     REPORT_DAYS: int = 14,
     FIND_LIMIT: int = 25,
     CHOICE_KEY: str = "trulyinbox:choice",
     CHOICES: any = ("connected", "other"),
     KEY_REJECTED: str = "TrulyInbox rejected the API key. Create a workspace key in TrulyInbox (Settings > API keys) and connect it again.",
     MISSING_SCOPE: str = "The TrulyInbox key is missing a scope. Create a workspace key with accounts:read, warmup:read, analytics:read and workspace:read.",
     NO_API_PLAN: str = "Your TrulyInbox plan doesn't include API access. API access starts on Starter.",
     PAUSED: str = "Your TrulyInbox subscription is paused. Resume it in TrulyInbox.",
     WRONG_WORKSPACE: str = "This key belongs to a different TrulyInbox workspace.",
     NO_WORKSPACE: str = "Couldn't find the TrulyInbox workspace. Add the workspace:read scope to the key, or set TRULYINBOX_WORKSPACE_ID in .env.",
     RATE_LIMITED: str = "TrulyInbox's API limit is reached. Try again in a minute.",
     LOCKED_OUT: str = "TrulyInbox locked this computer out for 15 minutes after rejected keys. Wait, then try again with a working key.",
     BAD_WORKSPACE_ID: str = "TRULYINBOX_WORKSPACE_ID must be the workspace's number. Fix it in .env.",
     NO_ADDRESS: str = "Sellbird doesn't know which mailbox it sends from. Set persona.email in sellbird.yaml first.",
     NO_ANSWER: str = "TrulyInbox didn't answer. Try again in a minute.",
     UNREADABLE: str = "TrulyInbox sent a reply Sellbird couldn't read.",
     _WARM: set[str] = set("active warming enabled running".split()),
     _LOGIN_FAILED: any = tuple(
         "auth_error auth_expired auth_failed suspended_auth blocked disconnect".split()
     ),
     _REJECTED: set[str] = set(),
     _STATUS_FIELDS: any = tuple("status accountState statusBucket warmupPausedReason".split()),
     _RULES: any = (
         (set("150006 Api.TooManyFailedAttempts too_many_requests".split()), None, LOCKED_OUT),
         (
             set("150001 150002 invalid_api_key unauthorized Api.InvalidKey".split()),
             401,
             KEY_REJECTED,
         ),
         (set("150003 insufficient_scope Api.ScopeForbidden".split()), None, MISSING_SCOPE),
         (set("150007 api_access_not_in_plan".split()), None, NO_API_PLAN),
         (set("040006 subscription_paused".split()), None, PAUSED),
         (set("150004 workspace_forbidden Api.WorkspaceForbidden".split()), None, WRONG_WORKSPACE),
         (set("150005 rate_limit_exceeded Api.RateLimitExceeded".split()), 429, RATE_LIMITED),
     ),
     _hash: any = lambda (key: str) -> str {
         return hashlib.sha256(key.encode("utf-8")).hexdigest()[:16];
     },
     forget_rejected: any = lambda (key: str) { _REJECTED.discard(_hash(key)); },
     _dict: any = lambda (x: any) -> builtins.dict {
         return x if isinstance(x, builtins.dict) else {};
     },
     _list: any = lambda (x: any) -> builtins.list {
         return x if isinstance(x, builtins.list) else [];
     },
     _str: any = lambda (x: any) -> str { return x if isinstance(x, str) else ""; };

class TrulyInboxError(RuntimeError) {}

def _int(x: any) -> int;
def _code(x: any) -> str;
def _day(x: any) -> date | None;

@dataclass(frozen=True)
class MailboxHealth {
    has address: str,
        found: bool,
        warming: bool = False,
        login_ok: bool = True,
        started_on: date | None = None,
        sent: int = 0,
        spam: int = 0,
        score: float | None = None;

    @builtins.property
    def spam_rate -> float | None;
}

class TrulyInbox {
    has _key: str = "",
        workspace_id: str = "",
        _transport: any = None;

    def init(api_key: str, workspace_id: str = "", *, transport: any = None);
    def __repr__ -> str;
    async def _get(path: str, params: builtins.dict | None = None) -> any;
    async def _workspace -> str;
    async def mailbox_health(address: str) -> MailboxHealth;
}

async def get_choice(state: any) -> str;
async def set_choice(state: any, choice: str);
def sending_address(config: any) -> str;
def key_from_env -> tuple[str, str];
def describe_status(health: MailboxHealth | None, error: str, choice: str) -> str;
async def current_health(address: str) -> tuple[MailboxHealth | None, str];
