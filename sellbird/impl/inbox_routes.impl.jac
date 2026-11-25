impl _refuse(message: str, code: int = 400) -> any {
    return JSONResponse({"success": False, "message": message}, status_code=code);
}

impl _store -> any {
    store = MailboxStore(db_path=str(importlib.import_module("sellbird.dashboard").DB_PATH));
    await store.init_db();
    return store;
}

impl _config_env -> tuple[any, any] {
    return (load_config(), load_env());
}

impl _body(request: any) -> dict[str, any] {
    try {
        body = await request.json();
    } except ValueError {
        return {};
    }
    return body if isinstance(body, dict) else {};
}

impl _row(store: any, mailbox_id: str) -> dict[str, any] | None {
    row = await store.get_mailbox(mailbox_id);
    return row if row and row.get("state") != "retired" else None;
}

impl _inbox(mailbox_id: str) -> tuple[any, any] {
    store = await _store();
    return (store, await _row(store, mailbox_id));
}

impl _log(store: any, action: str, agent: str = "you", **details: any) {
    await store.log_action(action_type=action, agent=agent, details=details);
}

impl _pool(ids: any) -> list[str] {
    return sorted(MAIN_PATH if m == MAIN else m for m in ids);
}

impl _whole(value: any, top: int) -> bool {
    return isinstance(value, int) and not isinstance(value, bool) and 1 <= value and value <= top;
}

impl _failed(message: str) {
    _connect_job.update(state="failed", message=message);
}

impl list_inboxes -> any {
    store = await _store();
    (config, env) = _config_env();
    email = config.channels.email;
    provider = (email.provider or "").strip().lower();
    native = provider in NATIVE_PROVIDERS;
    main = get_mail_provider(config, env) if native else None;
    inboxes = await load_inboxes(store, config, env, main);
    rows = {r["id"]: r for r in await store.list_mailboxes()};
    out: list[dict[str, any]] = [];
    for inbox in inboxes.inboxes.values() {
        row = rows.get(inbox.id, {});
        state = "not_connected"
            if not inbox.connected
            else ("paused" if inbox.paused_reason else "sending");
        hint = MAIN_CONNECT_HINTS.get(provider, "") if inbox.main and not inbox.connected else "";
        out.append({
            "id": MAIN_PATH if inbox.main else inbox.id,
            "main": inbox.main,
            "address": inbox.address,
            "name": inbox.name,
            "connection": "main" if inbox.main else row.get("connection", ""),
            "provider": email.provider if inbox.main else row.get("provider", ""),
            "state": state,
            "paused_reason": inbox.paused_reason,
            "cold_cap": inbox.cap,
            "cap_is_yours": row.get("cap_override") is not None,
            "cold_sent_today": inbox.sent_today,
            "first_emails_waiting": max(0, inbox.queued_first),
            "warmup_started_at": row.get("warmup_started_at") or "",
            "connect_hint": hint,
        });
    }
    campaigns = "SELECT id, name, status FROM campaigns ORDER BY created_at DESC LIMIT 200";
    return {
        "inboxes": out,
        "several": inboxes.several,
        "native": native,
        "max_daily_sends": email.max_daily_sends,
        "per_inbox_daily_cap": getattr(email, "per_inbox_daily_cap", 30),
        "pools": {cid: _pool(ids) for (cid, ids) in (await store.campaign_pools()).items()},
        "campaigns": await store._rows(campaigns),
        "sending_paused": await store.get_setting("sending_paused") or "",
        "connect_command": "sellbird inboxes connect gmail|microsoft|smtp --address you@domain",
        "can_connect": {k: not _connect_problem(k, env) for k in _CLIENTS},
        "connect_problems": {k: _connect_problem(k, env) for k in _CLIENTS},
        "connecting": await connect_status(),
    };
}

impl pause_inbox(mailbox_id: str, request: Request) -> any {
    (store, row) = await _inbox(mailbox_id);
    if row is None {
        return _refuse(_NO_PAUSE, 404);
    }
    who = "agent" if getattr(request.state, "principal", "user") == "agent" else "you";
    reason = ((await _body(request)).get("reason") or "").strip()[:200];
    reason = reason or ("paused by your coding agent" if who == "agent" else "paused by you");
    await store.set_pause(row["id"], reason);
    await _log(store, "inbox_paused", who, inbox=row["address"], reason=reason);
    return {"success": True, "paused": True, "address": row["address"]};
}

impl resume_inbox(mailbox_id: str) -> any {
    (store, row) = await _inbox(mailbox_id);
    if row is None {
        return _refuse(_NO_INBOX, 404);
    }
    await store.set_pause(row["id"], "");
    await _log(store, "inbox_resumed", inbox=row["address"]);
    return {"success": True};
}

impl set_inbox_cap(mailbox_id: str, request: Request) -> any {
    (store, row) = await _inbox(mailbox_id);
    if row is None {
        return _refuse(_NO_CAP, 404);
    }
    cap = (await _body(request)).get("cap");
    if cap is not None and not _whole(cap, HARD_MAX_INBOX_CAP) {
        return _refuse(_BAD_CAP);
    }
    await store.set_cap(row["id"], cap);
    await _log(store, "inbox_cap", inbox=row["address"], cap=cap);
    return {"success": True};
}

impl set_inbox_name(mailbox_id: str, request: Request) -> any {
    (store, row) = await _inbox(mailbox_id);
    if row is None {
        return _refuse(_NO_INBOX, 404);
    }
    name = (await _body(request)).get("name");
    if not isinstance(name, str) or len(name) > 100 or any(c in name for c in "\r\n<>\"") {
        return _refuse(_BAD_NAME);
    }
    await store.set_display_name(row["id"], name);
    return {"success": True};
}

impl remove_inbox(mailbox_id: str, request: Request) -> any {
    (store, row) = await _inbox(mailbox_id);
    if row is None {
        return _refuse(_NO_INBOX, 404);
    }
    if (await _body(request)).get("confirm") != row["address"] {
        return _refuse("Type the inbox's address to confirm: threads it started end.");
    }
    await store.retire(row["id"]);
    await _log(store, "inbox_removed", inbox=row["address"]);
    return {"success": True};
}

impl set_campaign_inboxes(campaign_id: str, request: Request) -> any {
    store = await _store();
    if not await store._rows("SELECT 1 FROM campaigns WHERE id = ?", (campaign_id,)) {
        return _refuse("No campaign with that id.", 404);
    }
    ids = (await _body(request)).get("inboxes");
    if not isinstance(ids, list) or not all(isinstance(i, str) for i in ids) {
        return _refuse('Expected {"inboxes": ["main", "<inbox id>", ...]} ([] = every inbox).');
    }
    missing = [i for i in ids if i != MAIN_PATH and await _row(store, i) is None];
    if missing {
        return _refuse(f"No connected inbox {missing[0]!r}.", 404);
    }
    chosen = [MAIN if i == MAIN_PATH else i for i in ids];
    await store.set_campaign_pool(campaign_id, chosen);
    return {"success": True};
}

impl _connect_problem(kind: str, env: any) -> str {
    (id_field, secret_field, pattern, missing, malformed) = _CLIENTS[kind];
    client_id = (getattr(env, id_field, "") or "").strip();
    if not client_id or (secret_field and not (getattr(env, secret_field, "") or "").strip()) {
        return missing;
    }
    return "" if pattern.match(client_id) else malformed;
}

impl _test(row: any, config: any, env: any, secrets: any) -> tuple[bool, str] {
    provider = build_provider(row, config=config, env=env, secrets=secrets);
    if provider is None {
        return (False, "Couldn't build a connection to test.");
    }
    try {
        return await asyncio.wait_for(provider.test_connection(), timeout=30);
    } except Exception as e {
        return (False, f"Couldn't check the connection ({type(e).__name__}).");
    }
}

impl _sign_in(kind: str, address: str, env: any, main: bool = False) -> dict[str, any] | None {
    captured: dict[str, any] = {};
    gmail = kind == "gmail";
    client = env.gmail_client_id if gmail else env.m365_client_id;
    other = env.gmail_client_secret if gmail else env.m365_tenant_id;
    save = None if main else captured.update;
    run_auth_flow = importlib.import_module(f"sellbird.integrations.{kind}").run_auth_flow;
    ok = run_auth_flow(client, other, save=save, expected_address=address or None);
    return ({"main": True} if main else captured) if ok and (main or captured) else None;
}

impl _run_connect(kind: str, fields: dict[str, any], main: bool = False) {
    (config, env) = _config_env();
    address = fields["address"];
    try {
        token = await asyncio.to_thread(_sign_in, kind, address, env, main);
        if token is None {
            _failed(_UNFINISHED + ("Nothing changed." if main else "Nothing was connected."));
            return;
        }
        store = await _store();
        if not main {
            secrets = _secrets();
            provider = "google" if kind == "gmail" else "microsoft";
            mailbox_id = await connect_oauth_mailbox(
                store, secrets, config, provider=provider, token=token, **fields
            );
            row = await store.get_mailbox(mailbox_id);
        }
        await _log(store, "inbox_connected", inbox=address or "main mailbox", provider=kind);
        (ok, detail) = (True, "") if main else await _test(row, config, env, secrets);
        _connect_job.update(state="connected", message=detail if not ok else "");
    } except Exception as e {
        known = not main and isinstance(e, (ConnectRefused, SecretStoreUnavailable));
        if not known {
            logger.exception(f"Connecting {'the main mailbox' if main else 'an inbox'} failed");
        }
        _failed(str(e) if known else "Connecting failed. See the dashboard log.");
    }
}

impl _start_sign_in(kind: str, fields: dict[str, any], env: any, main: bool) -> any {
    problem = _connect_problem(kind, env);
    if problem {
        return _refuse(problem);
    }
    if _connect_task is not None and not _connect_task.done() {
        return _refuse(_BUSY, 409);
    }
    _connect_job.clear();
    _connect_job.update(state="waiting", kind=kind, address=fields["address"], message="");
    _connect_task = asyncio.create_task(_run_connect(kind, fields, main));
    return {"success": True, "started": True, **({"kind": kind} if main else {})};
}

impl connect_main_mailbox -> any {
    (config, env) = _config_env();
    provider = (config.channels.email.provider or "").strip().lower();
    if provider not in ("gmail", "microsoft") {
        return _refuse(_MAIN_ONLY);
    }
    address = (getattr(config.persona, "email", "") or "").strip().lower();
    return _start_sign_in(provider, {"address": address}, env, True);
}

impl connect_inbox(kind: str, request: Request) -> any {
    if kind not in ("gmail", "microsoft", "smtp") {
        return _refuse("Connect gmail, microsoft or smtp.", 404);
    }
    body = await _body(request);
    (config, env) = _config_env();
    try {
        check_provider_allows_inboxes(config);
    } except ConnectRefused as e {
        return _refuse(str(e));
    }
    address = body.get("address");
    name = body.get("name") or "";
    warmup = body.get("warmup_started") or "";
    if not isinstance(address, str) or "@" not in address or len(address) > 254 {
        return _refuse("Enter the inbox's full email address.");
    }
    if not isinstance(name, str) or len(name) > 100 or any(c in name for c in "\r\n<>\"") {
        return _refuse(_BAD_NAME);
    }
    if not isinstance(warmup, str) {
        return _refuse("Give the warmup start as YYYY-MM-DD.");
    }
    address = address.strip().lower();
    fields = dict(address=address, display_name=name.strip(), warmup_started_at=warmup.strip());
    if kind != "smtp" {
        return _start_sign_in(kind, fields, env, False);
    }
    password = body.get("password");
    host = body.get("smtp_host");
    imap_host = body.get("imap_host") or "";
    username = body.get("username") or "";
    ports = (body.get("smtp_port", 587), body.get("imap_port", 993));
    if not isinstance(password, str) or not password or len(password) > 1024 {
        return _refuse("Enter the inbox's SMTP password (or app password).");
    }
    if not all(isinstance(v, str) for v in (host, imap_host, username)) or not host.strip() {
        return _refuse("Enter the SMTP server's host name.");
    }
    if not all(_whole(p, 65535) for p in ports) {
        return _refuse("A port is a whole number from 1 to 65535.");
    }
    user = username.strip() or address;
    smtp = SmtpSettings(host.strip(), user, password, ports[0], imap_host.strip(), ports[1]);
    (store, secrets) = (await _store(), _secrets());
    try {
        mailbox_id = await connect_smtp_mailbox(store, secrets, config, settings=smtp, **fields);
    } except (ConnectRefused, SecretStoreUnavailable) as e {
        return _refuse(str(e));
    }
    await _log(store, "inbox_connected", inbox=address, provider="smtp");
    (ok, detail) = await _test(await store.get_mailbox(mailbox_id), config, env, secrets);
    return {"success": True, "address": address, "test_ok": ok, "test_detail": detail};
}

impl connect_status -> any {
    return {k: _connect_job.get(k, "") for k in ("state", "kind", "address", "message")};
}

impl test_inbox(mailbox_id: str) -> any {
    (store, row) = await _inbox(mailbox_id);
    if row is None {
        return _refuse(_NO_INBOX, 404);
    }
    (ok, detail) = await _test(row, *_config_env(), _secrets());
    return {"success": True, "ok": ok, "detail": detail};
}
