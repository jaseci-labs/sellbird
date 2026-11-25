impl _int(x: any) -> int {
    if isinstance(x, bool)
        or not (isinstance(x, builtins.int) or (isinstance(x, float) and math.isfinite(x)))
    {
        return 0;
    }
    return max(0, builtins.int(x));
}

impl _code(x: any) -> str {
    if isinstance(x, bool) or x is None {
        return "";
    }
    code = str(x).strip();
    return code.zfill(6) if code.isdigit() else code;
}

impl _day(x: any) -> date | None {
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

impl MailboxHealth.spam_rate -> float | None {
    return self.spam / self.sent if self.sent else None;
}

impl TrulyInbox.init(api_key: str, workspace_id: str = "", *, transport: any = None) {
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

impl TrulyInbox.__repr__ -> str {
    return f"TrulyInbox(workspace_id={self.workspace_id!r})";
}

impl TrulyInbox._get(path: str, params: builtins.dict | None = None) -> any {
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

impl TrulyInbox._workspace -> str {
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

impl TrulyInbox.mailbox_health(address: str) -> MailboxHealth {
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

impl get_choice(state: any) -> str {
    try {
        choice = _dict(json.loads(await state.get_setting(CHOICE_KEY) or "{}")).get("choice");
    } except ValueError {
        return "";
    }
    return choice if choice in CHOICES else "";
}

impl set_choice(state: any, choice: str) {
    if choice not in CHOICES {
        raise ValueError(f"choice must be one of {CHOICES}");
    }
    at = datetime.now(timezone.utc).isoformat(timespec="seconds");
    await state.set_setting(CHOICE_KEY, json.dumps({"choice": choice, "at": at}));
}

impl sending_address(config: any) -> str {
    smtp_user = os.getenv("SMTP_USERNAME", "").strip()
        if config.channels.email.provider == "smtp"
        else "";
    return smtp_user if "@" in smtp_user else config.persona.email;
}

impl key_from_env -> tuple[str, str] {
    return (
        os.getenv("TRULYINBOX_API_KEY", "").strip(),
        os.getenv("TRULYINBOX_WORKSPACE_ID", "").strip(),
    );
}

impl describe_status(health: MailboxHealth | None, error: str, choice: str) -> str {
    if error {
        return f"connected, but: {error}";
    }
    return "connected"
        if health is not None
        else {"other": "using another warmup service"}.get(choice, "not set up");
}

impl current_health(address: str) -> tuple[MailboxHealth | None, str] {
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
