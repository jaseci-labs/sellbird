impl TokenTooLarge.init(provider: str = "Microsoft") {
    super.init(
        f"This {provider} sign-in is too large for the Windows keychain, so it can't "
            "be stored. Connect this inbox with its SMTP login instead.",
    );
}

impl _integration(name: str) -> any {
    return importlib.import_module(f"sellbird.integrations.{name}");
}

impl oauth_ref(mailbox_id: str) -> str {
    return f"mailbox:{mailbox_id}:oauth";
}

impl smtp_ref(mailbox_id: str) -> str {
    return f"mailbox:{mailbox_id}:smtp";
}

impl keychain_token(token: builtins.dict, provider: str = "Microsoft") -> str {
    raw = json.dumps(
        {k: token[k] for k in _KEPT_TOKEN_FIELDS if token.get(k)}, separators=(",", ":")
    );
    if len(raw) > MAX_KEYCHAIN_TOKEN_CHARS {
        raise TokenTooLarge(provider);
    }
    return raw;
}

impl KeychainTokenSource.init(secrets: any, ref: str) {
    self._secrets = secrets;
    self._ref = ref;
}

impl KeychainTokenSource.load -> builtins.dict | None {
    raw = self._secrets.get(self._ref);
    if not raw {
        return None;
    }
    try {
        data = json.loads(raw);
    } except ValueError {
        logger.warning(f"Unreadable sign-in in the keychain for {self._ref}");
        return None;
    }
    return data if isinstance(data, dict) and data.get("refresh_token") else None;
}

impl KeychainTokenSource.save(data: builtins.dict) {
    try {
        self._secrets.set(self._ref, keychain_token(data));
    } except TokenTooLarge as e {
        logger.warning(f"Kept the old sign-in for {self._ref}: {e}");
    } except SecretStoreUnavailable {
        logger.warning(
            f"Couldn't store the refreshed sign-in for {self._ref}: the keychain is unavailable"
        );
    }
}

impl KeychainTokenSource.missing_reason -> str {
    if not self._secrets.available() {
        return "The keychain is locked or unavailable, so this inbox's sign-in can't be read. Unlock it, or connect the inbox again.";
    }
    return "This inbox isn't connected. Connect it again: sellbird inboxes connect";
}

impl KeychainTokenSource.__repr__ -> str {
    return f"KeychainTokenSource({self._ref!r})";
}

impl MailboxStore._rows(query: str, args: tuple[any, ...] = ()) -> list[builtins.dict] {
    return await self._dicts(query, args);
}

impl MailboxStore.list_mailboxes(*, include_retired: bool = False) -> list[builtins.dict] {
    where = "" if include_retired else " WHERE state != 'retired'";
    return await self._dicts(f"SELECT * FROM mailboxes{where} ORDER BY created_at, address");
}

impl MailboxStore.get_mailbox(mailbox_id: str) -> builtins.dict | None {
    return await self._dict("SELECT * FROM mailboxes WHERE id = ?", (mailbox_id,));
}

impl MailboxStore.get_mailbox_by_address(address: str) -> builtins.dict | None {
    return await self._dict("SELECT * FROM mailboxes WHERE address = ?", (_norm(address),));
}

impl MailboxStore.add_mailbox(
    *,
    mailbox_id: str,
    address: str,
    provider: str,
    connection: str,
    display_name: str = "",
    credential_ref: str = "",
    settings: builtins.dict | None = None,
    warmup_started_at: str = "",
) -> str {
    addr = _norm(address);
    if "@" not in addr {
        raise ValueError("address must be an email address");
    }
    if provider not in PROVIDERS and connection in BUILT_IN_CONNECTIONS {
        raise ValueError(f"unknown mailbox provider {provider!r}");
    }
    (name, blob, warm) = (
        (display_name or "").strip(),
        json.dumps(settings or {}),
        warmup_started_at or None,
    );
    async with self._connect() as db {
        cur = await db.execute(
            "UPDATE mailboxes SET state = 'active', provider = ?, connection = ?,"
                " display_name = ?, credential_ref = ?, settings_json = ?,"
                " warmup_started_at = ?, paused_reason = '', cap_override = NULL"
                " WHERE id = ? AND address = ? AND state = 'retired'",
            (provider, connection, name, credential_ref, blob, warm, mailbox_id, addr),
        );
        if cur.rowcount {
            await db.commit();
            return mailbox_id;
        }
        try {
            await db.execute(
                "INSERT INTO mailboxes (id, address, display_name, provider, connection,"
                    " credential_ref, settings_json, warmup_started_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                (mailbox_id, addr, name, provider, connection, credential_ref, blob, warm),
            );
        } except sqlite3.IntegrityError as e {
            if "mailboxes.address" in str(e) {
                raise MailboxExists(addr) from None;
            }
            raise;
        }
        await db.commit();
    }
    return mailbox_id;
}

impl MailboxStore.set_pause(mailbox_id: str, reason: str) -> bool {
    return await self._changed(
        "UPDATE mailboxes SET paused_reason = ? WHERE id = ?", ((reason or "").strip(), mailbox_id)
    );
}

impl MailboxStore.set_cap(mailbox_id: str, cap: int | None) -> bool {
    if cap is not None
        and (
            isinstance(cap, bool) or not isinstance(cap, int) or cap < 1 or cap > HARD_MAX_INBOX_CAP
        )
    {
        raise ValueError(f"cap must be between 1 and {HARD_MAX_INBOX_CAP}");
    }
    return await self._changed(
        "UPDATE mailboxes SET cap_override = ? WHERE id = ?", (cap, mailbox_id)
    );
}

impl MailboxStore.set_display_name(mailbox_id: str, name: str) -> bool {
    return await self._changed(
        "UPDATE mailboxes SET display_name = ? WHERE id = ?", ((name or "").strip(), mailbox_id)
    );
}

impl MailboxStore.retire(mailbox_id: str) -> bool {
    async with self._connect() as db {
        cur = await db.execute(
            "UPDATE mailboxes SET state = 'retired' WHERE id = ? AND state != 'retired'",
            (mailbox_id,),
        );
        await db.execute("DELETE FROM campaign_mailboxes WHERE mailbox_id = ?", (mailbox_id,));
        await db.commit();
        return cur.rowcount > 0;
    }
}

impl MailboxStore.set_campaign_pool(campaign_id: str, mailbox_ids: list[str]) {
    async with self._connect() as db {
        await db.execute("DELETE FROM campaign_mailboxes WHERE campaign_id = ?", (campaign_id,));
        await db.executemany(
            "INSERT INTO campaign_mailboxes (campaign_id, mailbox_id) VALUES (?, ?)",
            [(campaign_id, m) for m in dict.fromkeys(mailbox_ids)],
        );
        await db.commit();
    }
}

impl MailboxStore.campaign_pool(campaign_id: str) -> set[str] {
    rows = await self._dicts(
        "SELECT mailbox_id FROM campaign_mailboxes WHERE campaign_id = ?", (campaign_id,)
    );
    return {r["mailbox_id"] or MAIN for r in rows};
}

impl MailboxStore.campaign_pools -> dict[str, set[str]] {
    pools: dict[str, set[str]] = {};
    for r in await self._dicts("SELECT campaign_id, mailbox_id FROM campaign_mailboxes") {
        pools.setdefault(r["campaign_id"], set()).add(r["mailbox_id"] or MAIN);
    }
    return pools;
}

impl MailboxStore.sent_since(mailbox_id: str, since_iso: str, kind: str | None = None) -> int {
    query = "SELECT COUNT(*) FROM outbox WHERE COALESCE(mailbox_id, '') = ? AND status = 'sent' AND sent_at >= ?";
    args: tuple[any, ...] = (mailbox_id, since_iso);
    if kind {
        query += " AND kind = ?";
        args += (kind,);
    }
    return await self._value(query, args);
}

impl MailboxStore.queued_first_emails -> dict[str, int] {
    rows = await self._dicts(
        "SELECT COALESCE(mailbox_id, '') AS m, COUNT(*) AS n FROM outbox"
            " WHERE kind = 'sequence' AND step <= 1 AND status IN ('pending_review', 'approved')"
            " GROUP BY COALESCE(mailbox_id, '')",
    );
    return {r["m"]: r["n"] for r in rows};
}

impl MailboxStore.unsent_off_main -> bool {
    return await self._dict(
        "SELECT 1 FROM outbox WHERE COALESCE(mailbox_id, '') != ''"
            " AND status IN ('pending_review', 'approved') LIMIT 1",
    )
        is not None;
}

impl MailboxStore.thread_started(campaign_id: str, prospect_id: str) -> bool {
    return await self._dict(
        "SELECT 1 FROM outbox WHERE COALESCE(campaign_id, '') = ? AND prospect_id = ?"
            " AND kind = 'sequence' AND status IN (?, ?) LIMIT 1",
        (campaign_id or "", prospect_id, *_STARTED),
    )
        is not None;
}

impl MailboxStore.thread_mailbox(campaign_id: str, prospect_id: str) -> str {
    row = await self._dict(
        "SELECT COALESCE(mailbox_id, '') AS m FROM outbox WHERE COALESCE(campaign_id, '') = ?"
            " AND prospect_id = ? AND kind = 'sequence' ORDER BY step LIMIT 1",
        (campaign_id or "", prospect_id),
    );
    return row["m"] if row else MAIN;
}

impl MailboxStore.set_thread_mailbox(campaign_id: str, prospect_id: str, mailbox_id: str) {
    await self._exec(
        "UPDATE outbox SET mailbox_id = ? WHERE COALESCE(campaign_id, '') = ?"
            " AND prospect_id = ? AND kind = 'sequence' AND status IN (?, ?)",
        (mailbox_id, campaign_id or "", prospect_id, *_UNSENT),
    );
}

impl MailboxStore.conversation_mailbox(conversation_id: str) -> str {
    row = await self._dict(
        "SELECT COALESCE(mailbox_id, '') AS m FROM conversations WHERE id = ?", (conversation_id,)
    );
    return row["m"] if row else MAIN;
}

impl _local_midnight_utc_iso(now: datetime) -> str {
    midnight = now.astimezone().replace(hour=0, minute=0, second=0, microsecond=0);
    return midnight.astimezone(timezone.utc).replace(tzinfo=None).isoformat();
}

impl per_inbox_cap(email_cfg: any) -> int {
    value = getattr(email_cfg, "per_inbox_daily_cap", PER_INBOX_CAP_DEFAULT);
    return value if isinstance(value, int) and value > 0 else PER_INBOX_CAP_DEFAULT;
}

impl inbox_cold_cap(row: builtins.dict, email_cfg: any, today: date | None = None) -> int {
    if row.get("cap_override") is not None {
        return int(row["cap_override"]);
    }
    shape = getattr(email_cfg, "warmup", None);
    if not isinstance(shape, WarmupConfig) {
        shape = WarmupConfig();
    }
    ramp = WarmupConfig(
        start_date=str(row.get("warmup_started_at") or "")[:10],
        min_days=shape.min_days,
        start_sends=shape.start_sends,
        daily_increase=shape.daily_increase,
    );
    return ramp.daily_cap(per_inbox_cap(email_cfg), today);
}

impl _ramped(email_cfg: any, ceiling: int, today: date) -> int {
    warmup = getattr(email_cfg, "warmup", None);
    return warmup.daily_cap(ceiling, today) if isinstance(warmup, WarmupConfig) else ceiling;
}

impl _smtp_settings(row: builtins.dict, password: str) -> any {
    SmtpSettings = _integration("smtp_mail").SmtpSettings;
    stored: any = {};
    try {
        stored = json.loads(row.get("settings_json") or "{}");
    } except ValueError {}
    known = {f.name for f in fields(SmtpSettings) if f.name != "password"};
    kept: builtins.dict = {};
    if isinstance(stored, dict) {
        kept = {k: v for (k, v) in stored.items() if k in known};
    }
    kept.setdefault("host", "");
    kept.setdefault("username", row.get("address", ""));
    return SmtpSettings(**kept, password=password);
}

impl build_provider(row: builtins.dict, *, config: any, env: any, secrets: any) -> any {
    if row.get("state") == "retired" {
        return None;
    }
    address = row.get("address", "") or "";
    identity = MailIdentity(
        address,
        (row.get("display_name") or "").strip() or identity_from_config(config).display_name,
    );
    (connection, provider) = (row.get("connection", ""), row.get("provider", ""));
    if connection == "oauth" {
        tokens = KeychainTokenSource(secrets, oauth_ref(row["id"]));
        if provider not in _OAUTH_PROVIDERS {
            return None;
        }
        (module, name) = _OAUTH_PROVIDERS[provider];
        return getattr(_integration(module), name)(config, env, identity=identity, tokens=tokens);
    }
    if connection == "smtp" {
        settings = _smtp_settings(row, secrets.get(smtp_ref(row["id"])) or "");
        return _integration("smtp_mail").SmtpImapProvider(
            config, env, identity=identity, smtp=settings
        );
    }
    builder = importlib.import_module("sellbird.extensions").registry().mailbox_connections.get(
        connection
    );
    return None if builder is None else builder(row, config=config, env=env, secrets=secrets);
}

impl check_provider_allows_inboxes(config: any) {
    provider = (getattr(config.channels.email, "provider", "") or "").strip().lower();
    if provider in NATIVE_PROVIDERS {
        return;
    }
    name = "Instantly" if provider == "instantly" else (provider or "not set");
    raise ConnectRefused(
        f"Your sending provider is {name}. Instantly installs send through Instantly "
            "only. Set channels.email.provider to gmail, microsoft or smtp before "
            "connecting inboxes.",
    );
}

impl _check_address(store: MailboxStore, config: any, address: str) -> tuple[str, str] {
    addr = _norm(address);
    if "@" not in addr {
        raise ConnectRefused("Enter the inbox's full email address.");
    }
    if addr == _norm(getattr(config.persona, "email", "") or "") {
        raise ConnectRefused("That's already your main mailbox.");
    }
    existing = await store.get_mailbox_by_address(addr);
    if existing and existing.get("state") != "retired" {
        raise ConnectRefused("That inbox is already connected.");
    }
    return (addr, existing["id"] if existing else _new_id());
}

impl check_warmup_start(value: str) -> str {
    value = (value or "").strip();
    if not value {
        return "";
    }
    try {
        day = date.fromisoformat(value[:10]);
    } except ValueError {
        raise ConnectRefused(
            "Give the day this inbox started warming up as YYYY-MM-DD, or leave it out for an established inbox.",
        ) from None;
    }
    if (day - datetime.now(timezone.utc).date()).days > 1 {
        raise ConnectRefused("The warmup start can't be in the future.");
    }
    return day.isoformat();
}

impl _insert(store: MailboxStore, **row: any) -> str {
    try {
        return await store.add_mailbox(**row);
    } except MailboxExists {
        raise ConnectRefused("That inbox is already connected.") from None;
    }
}

impl connect_oauth_mailbox(
    store: MailboxStore,
    secrets: any,
    config: any,
    *,
    provider: str,
    address: str,
    display_name: str,
    warmup_started_at: str,
    token: builtins.dict,
) -> str {
    check_provider_allows_inboxes(config);
    (addr, mailbox_id) = await _check_address(store, config, address);
    warmup = check_warmup_start(warmup_started_at);
    ref = oauth_ref(mailbox_id);
    secrets.set(ref, keychain_token(token, "Google" if provider == "google" else "Microsoft"));
    return await _insert(
        store,
        mailbox_id=mailbox_id,
        address=addr,
        provider=provider,
        connection="oauth",
        display_name=display_name,
        credential_ref=ref,
        warmup_started_at=warmup,
    );
}

impl connect_smtp_mailbox(
    store: MailboxStore,
    secrets: any,
    config: any,
    *,
    address: str,
    display_name: str,
    warmup_started_at: str,
    settings: any,
) -> str {
    check_provider_allows_inboxes(config);
    (addr, mailbox_id) = await _check_address(store, config, address);
    warmup = check_warmup_start(warmup_started_at);
    if not settings.host {
        raise ConnectRefused("Give the SMTP server's host name.");
    }
    ref = smtp_ref(mailbox_id);
    secrets.set(ref, settings.password);
    return await _insert(
        store,
        mailbox_id=mailbox_id,
        address=addr,
        provider="smtp",
        connection="smtp",
        display_name=display_name,
        credential_ref=ref,
        settings=settings.public(),
        warmup_started_at=warmup,
    );
}

impl Inbox.main -> bool {
    return self.id == MAIN;
}

impl Inbox.connected -> bool {
    return self.provider is not None and self.provider.is_configured();
}

impl Inbox.cold_left -> int {
    return max(0, self.cap - self.sent_today);
}

impl Inbox.room -> int {
    return self.cap - self.sent_today - self.queued_first;
}

impl Inboxes.several -> bool {
    return self.routed_mail or any(not i.main for i in self.inboxes.values());
}

impl Inboxes.get(mailbox_id: str) -> Inbox | None {
    return self.inboxes.get(mailbox_id or MAIN);
}

impl Inboxes.sendable -> list[Inbox] {
    return [i for i in self.inboxes.values() if i.connected and not i.paused_reason];
}

impl Inboxes.readers -> list[Inbox] {
    return [i for i in self.inboxes.values() if i.connected];
}

impl Inboxes.eligible(campaign_id: str) -> list[Inbox] {
    pool = self.pools.get(campaign_id or "");
    return [i for i in self.sendable() if not pool or i.id in pool];
}

impl Inboxes.pick(campaign_id: str) -> Inbox | None {
    candidates = self.eligible(campaign_id);
    if not candidates {
        return None;
    }
    return min(
        candidates,
        key=lambda (i: Inbox) -> tuple[any, ...] { return (-i.room, not i.main, i.address); },
    );
}

impl Inboxes.assign(campaign_id: str, prospect_id: str, *, staged_now: bool = False) -> str | None {
    inbox = self.pick(campaign_id);
    if inbox is None {
        return None;
    }
    before = None if staged_now else await self.store.thread_mailbox(campaign_id, prospect_id);
    await self.store.set_thread_mailbox(campaign_id, prospect_id, inbox.id);
    if before != inbox.id {
        old = self.get(before) if before is not None else None;
        if old is not None {
            old.queued_first -= 1;
        }
        inbox.queued_first += 1;
    }
    return inbox.id;
}

impl Inboxes.route(item: builtins.dict) -> Route {
    mailbox_id = item.get("mailbox_id") or MAIN;
    campaign_id = item.get("campaign_id") or "";
    if item.get("kind") == "sequence" {
        if int(item.get("step") or 1) <= 1
            and not await self.store.thread_started(campaign_id, item["prospect_id"])
        {
            if mailbox_id in {i.id for i in self.eligible(campaign_id)} {
                return Route("send", mailbox_id);
            }
            moved = await self.assign(campaign_id, item["prospect_id"]);
            if moved is None {
                return Route("hold", mailbox_id, "no inbox is available for this campaign");
            }
            item["mailbox_id"] = moved;
            return Route("send", moved);
        }
        if mailbox_id == MAIN {
            mailbox_id = await self.store.thread_mailbox(campaign_id, item["prospect_id"]);
        }
    } elif mailbox_id == MAIN and item.get("conversation_id") {
        mailbox_id = await self.store.conversation_mailbox(item["conversation_id"]);
    }
    item["mailbox_id"] = mailbox_id;
    inbox = self.get(mailbox_id);
    if inbox is None {
        return Route("cancel", mailbox_id, "its inbox was removed");
    }
    if not inbox.connected {
        return Route("hold", mailbox_id, f"{inbox.address or 'the main mailbox'} isn't connected");
    }
    if inbox.paused_reason {
        return Route("hold", mailbox_id, f"its inbox is paused: {inbox.paused_reason}");
    }
    return Route("send", mailbox_id);
}

impl _fingerprint(row: builtins.dict) -> tuple[any, ...] {
    return tuple(row.get(k) for k in _FINGERPRINT);
}

impl load_inboxes(
    state: any,
    config: any,
    env: any,
    main_provider: any,
    *,
    secrets: any = None,
    now: datetime | None = None,
    cache: builtins.dict | None = None,
) -> Inboxes {
    store = state if isinstance(state, MailboxStore) else MailboxStore(db_path=state.db_path);
    secrets = secrets if secrets is not None else SecretStore();
    now = now or datetime.now().astimezone();
    email_cfg = config.channels.email;
    since = _local_midnight_utc_iso(now);
    today = now.astimezone().date();
    queued = await store.queued_first_emails();
    inboxes: dict[str, Inbox] = {};
    rows = await store.list_mailboxes();
    routed = await store.unsent_off_main();
    if main_provider is not None {
        persona = identity_from_config(config);
        cap = cold_daily_cap(email_cfg, today);
        if rows or routed {
            cap = min(cap, _ramped(email_cfg, per_inbox_cap(email_cfg), today));
        }
        inboxes[MAIN] = Inbox(
            id=MAIN,
            address=persona.address,
            name=persona.display_name,
            provider=main_provider,
            cap=cap,
            sent_today=await store.sent_since(MAIN, since, kind="sequence"),
            queued_first=queued.get(MAIN, 0),
        );
    }
    if cache is not None {
        for gone in set(cache) - {r["id"] for r in rows} {
            del cache[gone];
        }
    }
    for row in rows {
        inboxes[row["id"]] = Inbox(
            id=row["id"],
            address=row["address"],
            name=(row.get("display_name") or "").strip()
                or identity_from_config(config).display_name,
            provider=_cached_provider(row, cache, config, env, secrets),
            cap=inbox_cold_cap(row, email_cfg, today),
            sent_today=await store.sent_since(row["id"], since, kind="sequence"),
            queued_first=queued.get(row["id"], 0),
            paused_reason=row.get("paused_reason") or "",
        );
    }
    pools = await store.campaign_pools() if len(inboxes) > 1 else {};
    return Inboxes(store=store, inboxes=inboxes, pools=pools, routed_mail=routed);
}

impl _cached_provider(
    row: builtins.dict, cache: builtins.dict | None, config: any, env: any, secrets: any
) -> any {
    kept = cache.get(row["id"]) if cache is not None else None;
    if kept is not None and kept[0] == _fingerprint(row) {
        return kept[1];
    }
    try {
        provider = build_provider(row, config=config, env=env, secrets=secrets);
    } except Exception as e {
        logger.error(f"Inbox {row.get('address', '')}: can't be used ({type(e).__name__})");
        provider = None;
    }
    if cache is not None and provider is not None {
        cache[row["id"]] = (_fingerprint(row), provider);
    }
    return provider;
}
