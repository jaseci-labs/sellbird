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

def _int(x: any) -> int {
    if isinstance(x, bool)
        or not (isinstance(x, builtins.int) or (isinstance(x, float) and math.isfinite(x)))
    {
        return 0;
    }
    return max(0, builtins.int(x));
}

def _code(x: any) -> str {
    if isinstance(x, bool) or x is None {
        return "";
    }
    code = str(x).strip();
    return code.zfill(6) if code.isdigit() else code;
}

def _day(x: any) -> date | None {
    if not isinstance(x, str) or not x {
        return None;
    }
    try {
        dt = datetime.fromisoformat(x.replace("Z", "+00:00"));
    } except ValueError {
        return None;
    }
    return (dt.astimezone(timezone.utc) if dt.tzinfo else dt).date();
}

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
    def spam_rate -> float | None {
        return self.spam / self.sent if self.sent else None;
    }
}

class TrulyInbox {
    has _key: str = "",
        workspace_id: str = "",
        _transport: any = None;

    def init(api_key: str, workspace_id: str = "", *, transport: any = None) {
        self._key = api_key.strip() if isinstance(api_key, str) else "";
        if not self._key or not (api_key.isascii() and api_key.isprintable()) {
            raise TrulyInboxError(KEY_REJECTED);
        }
        self.workspace_id = str(workspace_id or "").strip();
        if self.workspace_id and not self.workspace_id.isdigit() {
            raise TrulyInboxError(BAD_WORKSPACE_ID);
        }
        self._transport = transport;
    }

    def __repr__ -> str {
        return f"TrulyInbox(workspace_id={self.workspace_id!r})";
    }

    async def _get(path: str, params: builtins.dict | None = None) -> any {
        if _hash(self._key) in _REJECTED {
            raise TrulyInboxError(KEY_REJECTED);
        }
        auth = {"Authorization": f"Bearer {self._key}"};
        try {
            async with httpx.AsyncClient(
                base_url=API_BASE, transport=self._transport, timeout=TIMEOUT
            ) as client {
                resp = await client.get(path, params=params, headers=auth);
            }
        } except httpx.HTTPError {
            raise TrulyInboxError(NO_ANSWER) from None;
        }
        try {
            body = resp.json() if resp.content else {};
        } except ValueError {
            body = None;
        }
        envelope = _dict(body);
        error = _dict(envelope.get("error"));
        code = _code(envelope.get("errorCode")) or _code(error.get("code"));
        if resp.is_success and not code and envelope.get("success") is not False {
            if body is None {
                raise TrulyInboxError(UNREADABLE);
            }
            return envelope.get("data");
        }
        for (codes, status, message) in _RULES {
            if code in codes or resp.status_code == status {
                if message == KEY_REJECTED {
                    _REJECTED.add(_hash(self._key));
                }
                raise TrulyInboxError(message);
            }
        }
        if resp.status_code >= 500 {
            raise TrulyInboxError(NO_ANSWER);
        }
        found = _str(envelope.get("errorMessage")) or _str(error.get("message"));
        message = found.replace(self._key, "[hidden]")[:200];
        suffix = f": {message}" if message else ".";
        raise TrulyInboxError(f"TrulyInbox returned {resp.status_code}{suffix}");
    }

    async def _workspace -> str {
        if not self.workspace_id {
            listed = _list(await self._get("/v2/workspaces"));
            spaces = [
                w
                for w in listed
                if isinstance(w, builtins.dict) and str(w.get("id", "")).isdigit()
            ];
            if not spaces {
                raise TrulyInboxError(NO_WORKSPACE);
            }
            self.workspace_id = str(spaces[0]["id"]);
        }
        return self.workspace_id;
    }

    async def mailbox_health(address: str) -> MailboxHealth {
        address = address.strip();
        base = f"/v2/workspaces/{await self._workspace()}";
        accounts = await self._get(f"{base}/accounts", {"q": address, "limit": FIND_LIMIT});
        hit = next(
            (a
            for a in _list(accounts)
            if isinstance(a, builtins.dict)
                and _str(a.get("emailAddress")).strip().lower() == address.lower()
                and str(a.get("id", "")).isdigit()),
            None,
        );
        if hit is None {
            return MailboxHealth(address=address, found=False);
        }
        account = f"{base}/accounts/{hit['id']}";
        status = _dict(await self._get(f"{account}/warmup"));
        stats = _dict(await self._get(f"{account}/analytics/stats", {"days": REPORT_DAYS}));
        tokens = " ".join([_str(status.get(k)).lower() for k in _STATUS_FIELDS]);
        login_ok = not any([w in tokens for w in _LOGIN_FAILED])
            and status.get("sendCheckFailed") is not True
            and status.get("receiveCheckFailed") is not True;
        days = [x for x in _list(stats.get("dailyBreakdown")) if isinstance(x, builtins.dict)];
        score = stats.get("deliverabilityRate");
        return MailboxHealth(
            address=address,
            found=True,
            warming=_str(status.get("warmupStatus")).lower() in _WARM and login_ok,
            login_ok=login_ok,
            started_on=_day(status.get("warmupStartDate")),
            sent=sum([_int(x.get("sent")) for x in days]),
            spam=sum([_int(x.get("spamDetected")) for x in days]),
            score=float(score)
                if isinstance(score, (builtins.int, float))
                    and not isinstance(score, bool)
                    and math.isfinite(score)
                else None,
        );
    }
}

async def get_choice(state: any) -> str {
    try {
        choice = _dict(json.loads(await state.get_setting(CHOICE_KEY) or "{}")).get("choice");
    } except ValueError {
        return "";
    }
    return choice if choice in CHOICES else "";
}

async def set_choice(state: any, choice: str) {
    if choice not in CHOICES {
        raise ValueError(f"choice must be one of {CHOICES}");
    }
    at = datetime.now(timezone.utc).isoformat(timespec="seconds");
    await state.set_setting(CHOICE_KEY, json.dumps({"choice": choice, "at": at}));
}

def sending_address(config: any) -> str {
    smtp_user = os.getenv("SMTP_USERNAME", "").strip()
        if config.channels.email.provider == "smtp"
        else "";
    return smtp_user if "@" in smtp_user else config.persona.email;
}

def key_from_env -> tuple[str, str] {
    return (
        os.getenv("TRULYINBOX_API_KEY", "").strip(),
        os.getenv("TRULYINBOX_WORKSPACE_ID", "").strip(),
    );
}

def describe_status(health: MailboxHealth | None, error: str, choice: str) -> str {
    if error {
        return f"connected, but: {error}";
    }
    return "connected"
        if health is not None
        else {"other": "using another warmup service"}.get(choice, "not set up");
}

async def current_health(address: str) -> tuple[MailboxHealth | None, str] {
    (key, workspace) = key_from_env();
    if not key {
        return (None, "");
    }
    try {
        return (await TrulyInbox(key, workspace).mailbox_health(address), "");
    } except TrulyInboxError as e {
        return (None, str(e));
    }
}
