import asyncio;
import builtins;
import hashlib;
import ipaddress;
import json;
import logging;
import re;
import unicodedata;
import httpx;
import from dataclasses { dataclass }
import from datetime { datetime, timedelta, timezone }
import from urllib.parse { unquote, urlsplit }

glob logger = logging.getLogger("sellbird.precleared"),
     API_URL = "https://precleared.dev/api/v1/check",
     KEYS_URL = "https://precleared.dev/api/v1/keys",
     USER_AGENT = "sellbird (+https://github.com/ethanplusai/sellbird)",
     TIMEOUT = httpx.Timeout(connect=10.0, read=30.0, write=10.0, pool=10.0),
     TOTAL_TIMEOUT = 40.0,
     CACHE_DAYS = 30,
     CACHE_VERSION = 2,
     SETTINGS_PREFIX = "precleared:",
     UNKNOWN_PREFIX = SETTINGS_PREFIX + "unknown:",
     DEFINITE_VERDICTS = set("ok_to_email consent_needed blocked".split()),
     VERDICTS = DEFINITE_VERDICTS | {"unknown"},
     UNKNOWN_ATTEMPTS = 3,
     UNKNOWN_RETRY_AFTER = timedelta(hours=24),
     SENDER_COUNTRIES = PRECLEARED_SENDER_COUNTRIES,
     MAX_COMPANY_NAME = 160,
     MAX_RECIPIENT_NAME = 120,
     BUY_URL = "https://precleared.dev/buy",
     GET_KEY_URL = "https://precleared.dev/get-key",
     KEY_USE_CASE = "Sellbird: cold-email check before the first email",
     KEY_TIMEOUT = httpx.Timeout(20.0),
     MAX_BUY_URL = 2048,
     STATUS_KEY = "precleared_status",
     STATUS_MAX_AGE = timedelta(hours=26),
     HOLD_KINDS = tuple(
         "keyless_limit out_of_checks key_rejected rate_limited unavailable".split()
     ),
     BUY_HOSTS = ("precleared.dev", "checkout.stripe.com"),
     SERVER_BUSY = (502, 503, 504),
     _HEADERS = {"Content-Type": "application/json", "User-Agent": USER_AGENT},
     _EMAIL_RE = re.compile(r"[^@\s]+@[^@\s]+\.[^@\s]+"),
     _LABEL = re.compile(r"[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?"),
     _REASONS = {
         "bad_key": "PRECLEARED_API_KEY has a character that can't be sent (a curly quote, a space or a line break); check it in .env",
         "key_rejected": "PRECLEARED_API_KEY was rejected (wrong or revoked)",
         "rate_limited": "Precleared rate limit reached; asking again next cycle",
         "keyless_limit": "Precleared daily allowance used up; add PRECLEARED_API_KEY (`sellbird precleared-key` gets a free one, or https://precleared.dev/get-key) or wait until tomorrow",
     },
     _UNREACHABLE = "warn|||Precleared can't be reached right now|{emails} until it answers ({reason}). Sellbird asks again every cycle. Replies are not held.",
     _HOLDS = {
         "keyless_limit": f"warn|{GET_KEY_URL}|Get a free key|Precleared's free checks for today are used up|{{emails}}. Without a key, Precleared allows 10 checks a day. A free key gives Sellbird its own allowance: 100 a day for the first 14 days, then 25. Run `sellbird precleared-key` to get one with just your email address, or get one at {{url}} and put it in .env as PRECLEARED_API_KEY. Otherwise the waiting emails go out after the checks reset at midnight UK time. Replies are not held.",
         "out_of_checks": f"warn|{BUY_URL}|Buy checks|Your Precleared key is out of checks for today|{{emails}}. The key has used today's free checks and has no pack left. Buy checks to send them now: {{url}}. Otherwise they go out after the free checks reset at midnight UK time, or switch the check off (compliance.precleared.enabled: false). Replies are not held.",
         "key_rejected": f"bad|{GET_KEY_URL}|Get a new key|Precleared rejected your key|{{emails}}. PRECLEARED_API_KEY was rejected (wrong or revoked). Check the key in .env, get a new free key at {{url}}, or switch the check off (compliance.precleared.enabled: false). Replies are not held.",
         "rate_limited": "warn|||Precleared is limiting how fast Sellbird can check|{emails}. Precleared allows a set number of checks a minute, and Sellbird asks again next cycle. Replies are not held.",
     };

@dataclass
class Clearance {
    has allowed: bool,
        held: bool = False,
        pause_checks: bool = False,
        retry_address: bool = False,
        verdict: str = "",
        reason: str = "",
        receipt_id: str = "",
        country: str = "",
        hold_kind: str = "",
        fix_url: str = "",
        cached: bool = False,
        unknown_attempts: int = 0,
        unknown_final: bool = False;
}

@dataclass
class NewKey {
    has key: str = "",
        error: str = "",
        bad_email: bool = False;
}

def _held(
    reason: str, kind: str = "unavailable", pause: bool = True, retry: bool = False, url: str = ""
) -> Clearance {
    return Clearance(False, True, pause, retry, reason=reason, hold_kind=kind, fix_url=url);
}

def _some(fields: builtins.dict) -> builtins.dict {
    return {k: v for (k, v) in fields.items() if v};
}

def _get(item: any, key: str) -> any {
    return item.get(key) if isinstance(item, builtins.dict) else None;
}

def _field(resp: any, key: str) -> any {
    try {
        return _get(resp.json(), key);
    } except (ValueError, RecursionError) {
        return None;
    }
}

def _loads(raw: any) -> any {
    try {
        return json.loads(raw) if raw else None;
    } except (ValueError, TypeError) {
        return None;
    }
}

def _question(to_email: any, country: any, company: any, name: any) -> tuple[str, str, str, str] {
    return (
        (to_email or "").strip().lower(),
        _country(country),
        _name(company, MAX_COMPANY_NAME),
        _name(name, MAX_RECIPIENT_NAME),
    );
}

class PreclearedClient {
    has sender_country: str = "",
        api_key: str = "",
        address_source: str = "unknown",
        pitch: str = "",
        prospect_country: str = "",
        default_country: str = "",
        _transport: any = None;

    def init(
        sender_country: str,
        api_key: str = "",
        address_source: str = "unknown",
        pitch: str = "",
        prospect_country: str = "",
        default_country: str = "",
        transport: any = None,
    ) {
        self.sender_country = sender_country;
        self.api_key = api_key or "";
        self.address_source = address_source;
        self.pitch = (pitch or "").strip()[:200];
        self.prospect_country = normalize_prospect_country(prospect_country);
        self.default_country = self.prospect_country or normalize_prospect_country(default_country);
        self._transport = transport;
    }

    static def from_config(config: any, env: any) -> any {
        settings = _settings(config);
        if settings is None {
            return None;
        }
        return PreclearedClient(
            sender_country=settings.sender_country,
            api_key=getattr(env, "precleared_api_key", ""),
            address_source=settings.address_source,
            pitch=getattr(getattr(config, "product", None), "description", ""),
            prospect_country=getattr(settings, "prospect_country", ""),
            default_country=icp_country(config),
        );
    }

    def _redact(text: str) -> str {
        text = text.replace(self.api_key, "***REDACTED***")
            if self.api_key and text
            else text or "";
        return "***REDACTED***"
            if self.api_key and text and _contains_key(text, self.api_key)
            else text;
    }

    def _facts(country: str, company: str, name: str, fallback: str) -> builtins.dict {
        return {
            "sender_country": self.sender_country,
            "address_source": self.address_source,
            "existing_customer": False,
        }
            | (
                {"recipient_country": country}
                    if country
                    else _some({fallback: self.default_country})
            )
            | _some({"company_name": company, "recipient_name": name});
    }

    def _fingerprint(country: str = "", company: str = "", name: str = "") -> str {
        fallback = "prospect_country" if self.prospect_country else "icp_country";
        facts = {"v": CACHE_VERSION, "pitch": self.pitch}
            | self._facts(country, company, name, fallback);
        return hashlib.sha256(json.dumps(facts, sort_keys=True).encode()).hexdigest();
    }

    async def clear(
        to_email: str, state: any, country: str = "", company: str = "", name: str = ""
    ) -> Clearance {
        return await self.cached(to_email, state, country, company=company, name=name)
            or await self.check(to_email, state, country, company=company, name=name);
    }

    async def cached(
        to_email: str, state: any, country: str = "", company: str = "", name: str = ""
    ) -> Clearance | None {
        q = _question(to_email, country, company, name);
        return self._cached(await state.get_setting(SETTINGS_PREFIX + q[0]), *q[1:]);
    }

    def stored_verdicts -> tuple[str, str, str] {
        oldest = (_utcnow() - timedelta(days=CACHE_DAYS)).isoformat();
        return (SETTINGS_PREFIX, self._fingerprint(), oldest);
    }

    async def check(
        to_email: str, state: any, country: str = "", company: str = "", name: str = ""
    ) -> Clearance {
        (email, country, company, name) = _question(to_email, country, company, name);
        try {
            result = await self._check(email, country, company, name);
        } except Exception as e {
            reason = _clean(self._redact(f"Precleared check failed ({type(e).__name__}: {e})"));
            return _held(reason[:240], retry=True);
        }
        inputs = self._fingerprint(country, company, name);
        if not result.held and result.verdict in DEFINITE_VERDICTS {
            await state.set_setting(
                SETTINGS_PREFIX + email,
                json.dumps(
                    {k: getattr(result, k) for k in "verdict reason receipt_id country".split()} | {
                        "checked_at": _utcnow().isoformat(),
                        "inputs": inputs,
                    },
                ),
            );
            await state.delete_setting(UNKNOWN_PREFIX + email);
        } elif not result.held and result.verdict == "unknown" {
            result.unknown_attempts = await _count_unknown(state, email, inputs);
            result.unknown_final = result.unknown_attempts >= UNKNOWN_ATTEMPTS;
        }
        return result;
    }

    async def known_country(
        to_email: str, state: any, country: str = "", company: str = "", name: str = ""
    ) -> str {
        found = await self.cached(to_email, state, country, company=company, name=name);
        return found.country if found is not None else "";
    }

    def _cached(raw: any, country: str, company: str = "", name: str = "") -> Clearance | None {
        found = self._same_question(raw, country, company, name);
        earlier = self._same_question(raw, country)
            if found is None and (company or name)
            else None;
        return earlier if earlier is not None and earlier.verdict == "ok_to_email" else found;
    }

    def _same_question(raw: any, country: str, company: str = "", name: str = "") -> Clearance
        | None {
        found = _from_cache(raw, self._fingerprint(country, company, name));
        earlier = _from_cache(raw, self._fingerprint("", company, name))
            if found is None and country
            else None;
        return earlier if earlier is not None and earlier.country == country else found;
    }

    async def _check(
        email: str, country: str = "", company: str = "", name: str = ""
    ) -> Clearance {
        payload = {"recipient_email": email}
            | _some({"pitch": self.pitch})
            | self._facts(country, company, name, "default_recipient_country");
        if self.api_key and not re.fullmatch(r"[!-~]+", self.api_key) {
            return _held(_REASONS["bad_key"], "key_rejected", url=GET_KEY_URL);
        }
        headers = _HEADERS
            | _some({"Authorization": f"Bearer {self.api_key}" if self.api_key else ""});
        try {
            async with httpx.AsyncClient(timeout=TIMEOUT, transport=self._transport) as client {
                resp = await asyncio.wait_for(
                    client.post(API_URL, json=payload, headers=headers), TOTAL_TIMEOUT
                );
            }
        } except httpx.HTTPError as e {
            return _held(
                self._redact(f"Precleared unreachable: {e}"), retry=isinstance(e, httpx.ReadTimeout)
            );
        } except asyncio.TimeoutError {
            return _held("Precleared took too long to answer", retry=True);
        }
        status = resp.status_code;
        if status in (401, 429) {
            limited = status == 429
                and (self.api_key or _text(_field(resp, "error")) == "rate_limited");
            kind = "key_rejected"
                if status == 401
                else "rate_limited" if limited else "keyless_limit";
            return _held(_REASONS[kind], kind, url="" if limited else GET_KEY_URL);
        }
        if status == 402 {
            buy_url = _buy_url(resp, self.api_key);
            reason = f"Precleared: today's free checks on your key are used and it has no credits left; add a pack ({buy_url}) or wait until tomorrow";
            return _held(self._redact(reason), "out_of_checks", url=buy_url);
        }
        if status != 200 {
            return _held(
                f"Precleared HTTP {status}: {_clean(self._redact(resp.text))[:200]}",
                pause=status in SERVER_BUSY,
            );
        }
        try {
            data = resp.json();
        } except (ValueError, RecursionError) {
            return _held("Precleared returned invalid JSON", retry=True);
        }
        if not isinstance(data, builtins.dict) {
            return _held(
                "Precleared returned an unexpected response (not a JSON object)", retry=True
            );
        }
        verdict = data.get("verdict");
        if not isinstance(verdict, str) or verdict not in VERDICTS {
            return _held("Precleared returned a response without a known verdict", retry=True);
        }
        receipt_id = _text(_get(data.get("receipt"), "id"));
        country = _country(_get(data.get("facts"), "recipient_country"));
        reason = _reason(data, next_step_first=verdict == "unknown")
            if verdict != "ok_to_email"
            else "";
        return Clearance(
            verdict == "ok_to_email",
            verdict=verdict,
            reason=_clean(reason),
            receipt_id=receipt_id,
            country=country,
        );
    }
}

def _settings(config: any) -> any {
    settings = getattr(getattr(config, "compliance", None), "precleared", None);
    return settings if getattr(settings, "enabled", False) is True else None;
}

def _name(value: any, limit: int) -> str {
    return " ".join(value.split())[:limit].strip() if isinstance(value, str) else "";
}

def _country(value: any) -> str {
    code = value.strip().upper() if isinstance(value, str) else "";
    return code if len(code) == 2 and code.isascii() and code.isalpha() else "";
}

def _text(value: any) -> str {
    return value.strip() if isinstance(value, str) else "";
}

def _clean(text: any) -> str {
    return "".join(" " if unicodedata.category(ch) == "Cc" else ch for ch in text or "");
}

def _utcnow -> datetime {
    return datetime.now(timezone.utc);
}

def _fresh(value: any, max_age: timedelta) -> bool {
    try {
        at = datetime.fromisoformat(str(value));
    } except (TypeError, ValueError) {
        return False;
    }
    return _utcnow() - (at.replace(tzinfo=timezone.utc) if at.tzinfo is None else at) <= max_age;
}

def _contains_key(text: str, api_key: str) -> bool {
    decoded = text;
    for _ in range(8) {
        if api_key in decoded {
            return True;
        }
        next_decoded = unquote(decoded).replace("\\/", "/");
        if next_decoded == decoded {
            return False;
        }
        decoded = next_decoded;
    }
    return True;
}

def _host_shape(parsed: any) -> bool {
    (host, netloc) = (parsed.hostname, parsed.netloc);
    if parsed.scheme != "https"
        or not host
        or parsed.username is not None
        or parsed.password is not None
        or "%" in netloc
        or netloc.endswith(":")
        or parsed.port == 0
        or not any(host == h or host.endswith("." + h) for h in BUY_HOSTS)
    {
        return False;
    }
    if ":" in host {
        ipaddress.IPv6Address(host);
        return re.fullmatch(r"\[[0-9a-fA-F:.]+\](?::[0-9]+)?", netloc) is not None;
    }
    ascii_host = host.encode("idna").decode("ascii").rstrip(".");
    return len(ascii_host) <= 253
        and all(_LABEL.fullmatch(label) for label in ascii_host.split("."));
}

def _buy_url(resp: any, api_key: str = "") -> str {
    url = _field(resp, "buy_url");
    try {
        ok = isinstance(url, str)
            and len(url) <= MAX_BUY_URL
            and url.isprintable()
            and not any(ch.isspace() for ch in url)
            and "\\" not in url
            and _host_shape(urlsplit(url));
    } except (ValueError, UnicodeError) {
        ok = False;
    }
    return url if ok and not (api_key and _contains_key(url, api_key)) else BUY_URL;
}

def _reason(data: builtins.dict, next_step_first: bool = False) -> str {
    reasons = data.get("reasons");
    first = reasons[0] if isinstance(reasons, list) and reasons else None;
    text = _text(_get(first, "text")) or _text(_get(first, "note"));
    source = _text(_get(first, "source_title"));
    rule = f"{text} ({source})" if text and source else text;
    next_step = _text(data.get("next_step"));
    return " ".join(
        part for part in ([next_step, rule] if next_step_first else [rule, next_step]) if part
    )[:240];
}

def _from_cache(raw: any, inputs: str) -> Clearance | None {
    data = _loads(raw);
    verdict = _get(data, "verdict") if _get(data, "inputs") == inputs else None;
    if not isinstance(verdict, str)
        or verdict not in DEFINITE_VERDICTS
        or not _fresh(data.get("checked_at"), timedelta(days=CACHE_DAYS))
    {
        return None;
    }
    return Clearance(
        allowed=verdict == "ok_to_email",
        verdict=verdict,
        reason=_text(data.get("reason")),
        receipt_id=_text(data.get("receipt_id")),
        country=_country(data.get("country")),
        cached=True,
    );
}

async def _count_unknown(state: any, email: str, inputs: str) -> int {
    data = _loads(await state.get_setting(UNKNOWN_PREFIX + email));
    attempts = 0;
    if _get(data, "inputs") == inputs and _fresh(data.get("at"), timedelta(days=CACHE_DAYS)) {
        try {
            attempts = max(0, builtins.int(data.get("attempts") or 0));
        } except (ValueError, TypeError) {
            attempts = 0;
        }
    }
    attempts += 1;
    await state.set_setting(
        UNKNOWN_PREFIX + email,
        json.dumps({"inputs": inputs, "attempts": attempts, "at": _utcnow().isoformat()}),
    );
    return attempts;
}

def create_free_key(email: str, country: str = "", transport: any = None) -> NewKey {
    email = (email or "").strip();
    if len(email) > 254 or not _EMAIL_RE.fullmatch(email) {
        return NewKey(error="that doesn't look like an email address", bad_email=True);
    }
    country = _text(country).upper();
    payload = {"email": email, "use_case": KEY_USE_CASE}
        | _some({"country": country if country in SENDER_COUNTRIES else ""});
    try {
        with httpx.Client(timeout=KEY_TIMEOUT, transport=transport) as client {
            resp = client.post(KEYS_URL, json=payload, headers=_HEADERS);
        }
    } except httpx.HTTPError {
        return NewKey(error="Precleared couldn't be reached");
    }
    try {
        data = resp.json();
    } except ValueError {
        data = None;
    }
    data = data if isinstance(data, builtins.dict) else builtins.dict();
    logger.debug("Precleared free key request: HTTP %s", resp.status_code);
    if resp.status_code in (200, 201) {
        key = data.get("key");
        if isinstance(key, str) and re.fullmatch(r"[!-~]{16,200}", key) {
            return NewKey(key=key);
        }
        return NewKey(error="Precleared's answer had no key in it");
    }
    message = " ".join(_clean(_text(data.get("message"))).split())[:200].rstrip(". ");
    return NewKey(
        error=message or f"Precleared answered HTTP {resp.status_code}",
        bad_email=resp.status_code == 400 and data.get("error") == "invalid_request",
    );
}

def parse_status(raw: any) -> builtins.dict {
    try {
        value: any = json.loads(raw) if raw else {};
    } except ValueError {
        return {};
    }
    return value if isinstance(value, builtins.dict) else {};
}

async def record_hold(state: any, clearance: Clearance, waiting: int) {
    try {
        previous = await current_hold(state);
        kind = clearance.hold_kind if clearance.hold_kind in HOLD_KINDS else "unavailable";
        now = _utcnow().replace(microsecond=0).isoformat();
        since = previous.get("since")
            if previous.get("status") == "held" and previous.get("kind") == kind
            else None;
        await state.set_setting(
            STATUS_KEY,
            json.dumps({
                "status": "held",
                "kind": kind,
                "reason": _clean(clearance.reason)[:300],
                "url": _clean(clearance.fix_url),
                "waiting": max(1, builtins.int(waiting)),
                "since": since or now,
                "at": now,
            }),
        );
    } except Exception as e {
        logger.warning(f"Precleared: failed to record the hold: {e}");
    }
}

async def clear_hold(state: any) {
    try {
        if parse_status(await state.get_setting(STATUS_KEY)).get("status") == "held" {
            await state.set_setting(STATUS_KEY, "");
        }
    } except Exception as e {
        logger.warning(f"Precleared: failed to clear the hold: {e}");
    }
}

def hold_applies(config: any) -> bool {
    provider = getattr(getattr(getattr(config, "channels", None), "email", None), "provider", None);
    return _settings(config) is not None and provider in NATIVE_PROVIDERS;
}

async def current_hold(state: any, config: any = None) -> builtins.dict {
    if config is not None and not hold_applies(config) {
        return {};
    }
    status = parse_status(await state.get_setting(STATUS_KEY));
    if status.get("status") != "held" or not _fresh(status.get("at"), STATUS_MAX_AGE) {
        return {};
    }
    return {k: _clean(v) if isinstance(v, str) else v for (k, v) in status.items()};
}

def hold_message(hold: builtins.dict) -> builtins.dict {
    url = _text(hold.get("url"));
    if any(unicodedata.category(ch) == "Cc" or ch.isspace() for ch in url) {
        url = "";
    }
    try {
        waiting = max(1, builtins.int(hold.get("waiting") or 1));
    } except (TypeError, ValueError) {
        waiting = 1;
    }
    emails = f"{waiting} cold email is waiting"
        if waiting == 1
        else f"{waiting} cold emails are waiting";
    (tone, fallback, label, title, detail) = _HOLDS.get(str(hold.get("kind")), _UNREACHABLE).split(
        "|"
    );
    url = (url or fallback) if fallback else "";
    reason = _text(_clean(_text(hold.get("reason")))) or "no answer";
    detail = detail.format(emails=emails, url=url, reason=reason);
    return {"tone": tone, "url": url, "url_label": label, "title": title, "detail": detail};
}
