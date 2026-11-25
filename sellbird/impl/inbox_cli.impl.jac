impl _date(value: str) -> str {
    try {
        return date.fromisoformat(value).isoformat();
    } except ValueError {
        raise argparse.ArgumentTypeError("use a real date, YYYY-MM-DD") from None;
    }
}

impl _cap(value: str) -> int | None {
    if value == "default" {
        return None;
    }
    try {
        cap = int(value);
    } except ValueError {
        raise argparse.ArgumentTypeError("a whole number, or 'default'") from None;
    }
    if cap < 1 or cap > HARD_MAX_INBOX_CAP {
        raise argparse.ArgumentTypeError(f"between 1 and {HARD_MAX_INBOX_CAP}");
    }
    return cap;
}

impl _connect_args(p: any, smtp: bool) {
    p.add_argument("--address", required=True, help="The inbox's email address");
    p.add_argument("--name", default="", help="Name shown in From (default: persona.name)");
    p.add_argument(
        "--warmup-started",
        default="",
        type=_date,
        metavar="YYYY-MM-DD",
        help="When this inbox started warming up (leave out if established)",
    );
    if smtp {
        p.add_argument("--smtp-host", required=True);
        p.add_argument("--smtp-port", type=int, default=587);
        p.add_argument("--username", default="", help="Defaults to the address");
        p.add_argument("--imap-host", default="", help="Defaults to the SMTP host");
        p.add_argument("--imap-port", type=int, default=993);
    }
}

impl register(subparsers: any) {
    sub = subparsers.add_parser("inboxes", help="Connect and run the inboxes you send from");
    actions = sub.add_subparsers(dest="inboxes_action");
    actions.add_parser("list", help="Every inbox, its state and today's cold sends");
    kinds = actions.add_parser("connect", help="Connect an inbox you already have").add_subparsers(
        dest="kind", required=True
    );
    for kind in ("gmail", "microsoft", "smtp") {
        _connect_args(kinds.add_parser(kind), kind == "smtp");
    }
    parsers = {a: actions.add_parser(a, help=about) for (a, about) in _ADDRESS_ACTIONS};
    for p in parsers.values() {
        p.add_argument("address");
    }
    parsers["pause"].add_argument("--reason", default="paused by you");
    parsers["cap"].add_argument("cap", type=_cap, help=f"1-{HARD_MAX_INBOX_CAP}, or 'default'");
    parsers["name"].add_argument("name");
    use = actions.add_parser(
        "use", help="Choose which inboxes a campaign sends from (none: every inbox)"
    );
    use.add_argument("campaign", help="Campaign id or exact name");
    use.add_argument(
        "addresses", nargs="*", help=f"Inbox addresses; '{MAIN_NAME}' is your main mailbox"
    );
    sub.set_defaults(func=cmd_inboxes);
}

impl print_inbox_list(store: MailboxStore, config: any, env: any) {
    mail = importlib.import_module("sellbird.integrations.mail_provider");
    email = config.channels.email;
    main = mail.get_mail_provider(config, env) if email.provider in mail.NATIVE_PROVIDERS else None;
    inboxes = await load_inboxes(store, config, env, main);
    if not inboxes.inboxes {
        print(f"\n  No inboxes: your sending provider is {email.provider or 'not set'}.\n");
        return;
    }
    print(f"\n  {'Inbox':38} {'State':16} Cold today");
    for inbox in inboxes.inboxes.values() {
        label = f"{inbox.address or '(main mailbox)'}{' (main)' if inbox.main and inbox.address else ''}";
        state = "not connected"
            if not inbox.connected
            else ("paused" if inbox.paused_reason else "sending");
        print(f"  {label:38} {state:16} {inbox.sent_today}/{inbox.cap}");
        if inbox.paused_reason {
            print(f"  {'':38} {inbox.paused_reason}");
        }
    }
    if not inboxes.several {
        print("\n  Add another with: sellbird inboxes connect gmail|microsoft|smtp --address ...");
    }
    print(f"\n  Everything sent today stays under max_daily_sends ({email.max_daily_sends}).\n");
}

impl _test_and_print(provider: any) -> bool {
    try {
        (ok, detail) = await provider.test_connection();
    } except Exception as e {
        (ok, detail) = (False, f"Couldn't check the connection ({type(e).__name__})");
    }
    print(f"\n  {'✓' if ok else '✗'} {detail}\n");
    return ok;
}

impl _oauth_sign_in(args: any, env: any) -> dict[str, any] | None {
    captured: dict[str, any] = {};
    gmail = args.kind == "gmail";
    sign_in = importlib.import_module(
        "sellbird.integrations." + ("gmail" if gmail else "microsoft")
    ).run_auth_flow;
    (client, secret) = (env.gmail_client_id, env.gmail_client_secret)
        if gmail
        else (env.m365_client_id, env.m365_tenant_id);
    ok = sign_in(client, secret, save=captured.update, expected_address=args.address);
    return captured if ok and captured else None;
}

impl read_smtp_password(args: any) -> str {
    return getpass.getpass(f"SMTP password for {args.address}: ");
}

impl _build_and_test(row: any, config: any, env: any, secrets: any, missing: str) -> int {
    provider = build_provider(row, config=config, env=env, secrets=secrets);
    if provider is None {
        print(missing);
        return 1;
    }
    return 0 if await _test_and_print(provider) else 1;
}

impl connect_flow(
    args: any, store: MailboxStore, secrets: SecretStore, config: any, env: any
) -> int {
    try {
        check_provider_allows_inboxes(config);
        common = {
            "address": args.address,
            "display_name": args.name,
            "warmup_started_at": args.warmup_started or "",
        };
        if args.kind == "smtp" {
            settings = importlib.import_module("sellbird.integrations.smtp_mail").SmtpSettings(
                host=args.smtp_host,
                username=args.username or args.address.strip().lower(),
                password=read_smtp_password(args),
                port=args.smtp_port,
                imap_host=args.imap_host,
                imap_port=args.imap_port,
            );
            mailbox_id = await connect_smtp_mailbox(
                store, secrets, config, settings=settings, **common
            );
        } else {
            token = _oauth_sign_in(args, env);
            if token is None {
                print("\n  Sign-in didn't finish, so nothing was connected.\n");
                return 1;
            }
            provider = "google" if args.kind == "gmail" else "microsoft";
            mailbox_id = await connect_oauth_mailbox(
                store, secrets, config, provider=provider, token=token, **common
            );
        }
    } except (ConnectRefused, SecretStoreUnavailable) as e {
        print(f"\n  {e}\n");
        return 1;
    }
    print(f"\n  Connected {args.address.strip().lower()}.");
    if config.channels.email.max_daily_sends <= config.channels.email.per_inbox_daily_cap {
        print(_RAISE_MAX);
    }
    row = await store.get_mailbox(mailbox_id);
    return await _build_and_test(
        row, config, env, secrets, "  Couldn't build a connection to test.\n"
    );
}

impl _find(store: MailboxStore, address: str) -> dict[any, any] | None {
    row = await store.get_mailbox_by_address(address);
    if row is None or row.get("state") == "retired" {
        print(f"\n  No connected inbox {address.strip().lower()}. See: sellbird inboxes list\n");
        return None;
    }
    return row;
}

impl _use(args: any, store: MailboxStore) -> int {
    ref = args.campaign;
    rows = await store._rows("SELECT id, name FROM campaigns WHERE id = ? OR name = ?", (ref, ref));
    if len(rows) != 1 {
        which = "No" if not rows else "More than one";
        print(f"\n  {which} campaign matches {ref!r}. {_USE_ID}\n");
        return 1;
    }
    ids: list[str] = [];
    for address in args.addresses {
        if address.strip().lower() == MAIN_NAME {
            ids.append(MAIN);
            continue;
        }
        row = await _find(store, address);
        if row is None {
            return 1;
        }
        ids.append(row["id"]);
    }
    await store.set_campaign_pool(rows[0]["id"], ids);
    which = f"from {len(ids)} inbox(es) only." if ids else "from every inbox.";
    print(
        f"\n  This campaign sends {which} New threads follow this; threads already started keep their inbox.\n",
    );
    return 0;
}

impl run(args: any, store: MailboxStore, secrets: SecretStore, config: any, env: any) -> int {
    action = args.inboxes_action or "list";
    if action == "list" {
        await print_inbox_list(store, config, env);
        return 0;
    }
    if action == "connect" {
        return await connect_flow(args, store, secrets, config, env);
    }
    if action == "use" {
        return await _use(args, store);
    }
    row = await _find(store, args.address);
    if row is None {
        return 1;
    }
    address = row["address"];
    details: dict[str, any] = {"inbox": address};
    if action == "test" {
        return await _build_and_test(
            row, config, env, secrets, "\n  ✗ This inbox has no connection to test.\n"
        );
    } elif action == "pause" {
        await store.set_pause(row["id"], args.reason);
        details["reason"] = args.reason;
        said = f"Paused {address}. {_PAUSED}";
    } elif action == "resume" {
        await store.set_pause(row["id"], "");
        said = f"{address} sends again.";
    } elif action == "cap" {
        await store.set_cap(row["id"], args.cap);
        details["cap"] = args.cap;
        said = f"{address}: "
            + (
                f"up to {args.cap} cold emails a day."
                    if args.cap
                    else "back to the default daily cap and its warmup ramp."
            );
    } elif action == "name" {
        await store.set_display_name(row["id"], args.name);
        print(f"\n  {address} sends as {args.name.strip() or config.persona.name}.\n");
        return 0;
    } elif action == "remove" {
        await store.retire(row["id"]);
        said = f"Removed {address}. {_REMOVED}";
    } else {
        return 0;
    }
    await store.log_action(action_type=_LOGGED[action], agent="you", details=details);
    print(f"\n  {said}\n");
    return 0;
}

impl _run_inboxes(args: any, config: any, env: any) -> int {
    state = StateManager();
    await state.init_db();
    return await run(args, MailboxStore(db_path=state.db_path), SecretStore(), config, env);
}

impl cmd_inboxes(args: any) {
    (config, env) = (load_config(), load_env());
    sys.exit(asyncio.run(_run_inboxes(args, config, env)));
}
