import argparse;
import asyncio;
import getpass;
import importlib;
import sys;
import from datetime { date }

glob MAIN_NAME = "main",
     _ACTIONS = "test: Check one inbox can sign in|pause: Stop sending from one inbox|resume: Send from a paused inbox again|cap: Set one inbox's daily cold-email cap|name: Change the name an inbox sends as|remove: Stop using an inbox for good (its sign-in stays in your keychain)",
     _ADDRESS_ACTIONS = [tuple(a.split(": ", 1)) for a in _ACTIONS.split("|")],
     _LOGGED = dict(zip("pause resume cap remove".split(), "paused resumed cap removed".split())),
     _WARMUP = "When this inbox started warming up (leave out if established)",
     _ADDRESSES = f"Inbox addresses; '{MAIN_NAME}' is your main mailbox",
     _UNTESTABLE = "\n  ✗ This inbox has no connection to test.\n",
     _USE_HELP = "Choose which inboxes a campaign sends from (none: every inbox)",
     _PAUSED = "Its unsent first emails move to your other inboxes; follow-ups and replies on threads it started wait for it.",
     _REMOVED = "Its unsent first emails move to your other inboxes; follow-ups on threads it started are cancelled. Its sign-in is still in your keychain (service 'sellbird'); delete it there if you like.",
     _DEFAULT_CAP = "back to the default daily cap and its warmup ramp.",
     _USE_ID = "Use its id (sellbird status lists campaigns).",
     _USED = "New threads follow this; threads already started keep their inbox.",
     _RAISE_MAX = "  Note: max_daily_sends caps everything sent in a day across every inbox. Raise it in sellbird.yaml so this inbox adds to what goes out.";

def _date(value: str) -> str {
    try {
        return date.fromisoformat(value).isoformat();
    } except ValueError {
        raise argparse.ArgumentTypeError("use a real date, YYYY-MM-DD") from None;
    }
}

def _cap(value: str) -> int | None {
    try {
        cap = None if value == "default" else int(value);
    } except ValueError {
        raise argparse.ArgumentTypeError("a whole number, or 'default'") from None;
    }
    if cap is not None and (cap < 1 or cap > HARD_MAX_INBOX_CAP) {
        raise argparse.ArgumentTypeError(f"between 1 and {HARD_MAX_INBOX_CAP}");
    }
    return cap;
}

def register(subparsers: any) {
    sub = subparsers.add_parser("inboxes", help="Connect and run the inboxes you send from");
    actions = sub.add_subparsers(dest="inboxes_action");
    actions.add_parser("list", help="Every inbox, its state and today's cold sends");
    connect = actions.add_parser("connect", help="Connect an inbox you already have");
    kinds = connect.add_subparsers(dest="kind", required=True);
    for kind in ("gmail", "microsoft", "smtp") {
        p = kinds.add_parser(kind);
        p.add_argument("--address", required=True, help="The inbox's email address");
        p.add_argument("--name", default="", help="Name shown in From (default: persona.name)");
        p.add_argument(
            "--warmup-started", default="", type=_date, metavar="YYYY-MM-DD", help=_WARMUP
        );
        if kind == "smtp" {
            p.add_argument("--smtp-host", required=True);
            p.add_argument("--smtp-port", type=int, default=587);
            p.add_argument("--username", default="", help="Defaults to the address");
            p.add_argument("--imap-host", default="", help="Defaults to the SMTP host");
            p.add_argument("--imap-port", type=int, default=993);
        }
    }
    parsers = {a: actions.add_parser(a, help=about) for (a, about) in _ADDRESS_ACTIONS};
    for p in parsers.values() {
        p.add_argument("address");
    }
    parsers["pause"].add_argument("--reason", default="paused by you");
    parsers["cap"].add_argument("cap", type=_cap, help=f"1-{HARD_MAX_INBOX_CAP}, or 'default'");
    parsers["name"].add_argument("name");
    use = actions.add_parser("use", help=_USE_HELP);
    use.add_argument("campaign", help="Campaign id or exact name");
    use.add_argument("addresses", nargs="*", help=_ADDRESSES);
    sub.set_defaults(func=cmd_inboxes);
}

async def print_inbox_list(store: MailboxStore, config: any, env: any) {
    email = config.channels.email;
    main = get_mail_provider(config, env) if email.provider in NATIVE_PROVIDERS else None;
    inboxes = await load_inboxes(store, config, env, main);
    if not inboxes.inboxes {
        print(f"\n  No inboxes: your sending provider is {email.provider or 'not set'}.\n");
        return;
    }
    print(f"\n  {'Inbox':38} {'State':16} Cold today");
    for box in inboxes.inboxes.values() {
        label = f"{box.address or '(main mailbox)'}{' (main)' if box.main and box.address else ''}";
        state = ("paused" if box.paused_reason else "sending")
            if box.connected
            else "not connected";
        print(f"  {label:38} {state:16} {box.sent_today}/{box.cap}");
        if box.paused_reason {
            print(f"  {'':38} {box.paused_reason}");
        }
    }
    if not inboxes.several {
        print("\n  Add another with: sellbird inboxes connect gmail|microsoft|smtp --address ...");
    }
    print(f"\n  Everything sent today stays under max_daily_sends ({email.max_daily_sends}).\n");
}

async def _test(row: any, config: any, env: any, secrets: any, missing: str) -> int {
    provider = build_provider(row, config=config, env=env, secrets=secrets);
    if provider is None {
        print(missing);
        return 1;
    }
    try {
        (ok, detail) = await provider.test_connection();
    } except Exception as e {
        (ok, detail) = (False, f"Couldn't check the connection ({type(e).__name__})");
    }
    print(f"\n  {'✓' if ok else '✗'} {detail}\n");
    return 0 if ok else 1;
}

def _oauth_sign_in(args: any, env: any) -> dict[str, any] | None {
    captured: dict[str, any] = {};
    gmail = args.kind == "gmail";
    module = importlib.import_module(f"sellbird.integrations.{'gmail' if gmail else 'microsoft'}");
    client = env.gmail_client_id if gmail else env.m365_client_id;
    secret = env.gmail_client_secret if gmail else env.m365_tenant_id;
    ok = module.run_auth_flow(client, secret, save=captured.update, expected_address=args.address);
    return captured if ok and captured else None;
}

def read_smtp_password(args: any) -> str {
    return getpass.getpass(f"SMTP password for {args.address}: ");
}

async def connect_flow(args: any, store: any, secrets: any, config: any, env: any) -> int {
    address = args.address.strip().lower();
    try {
        check_provider_allows_inboxes(config);
        common = {"address": args.address, "display_name": args.name};
        common["warmup_started_at"] = args.warmup_started or "";
        if args.kind == "smtp" {
            import from sellbird.integrations.smtp_mail { SmtpSettings }
            settings = SmtpSettings(
                host=args.smtp_host,
                username=args.username or address,
                password=read_smtp_password(args),
                port=args.smtp_port,
                imap_host=args.imap_host,
                imap_port=args.imap_port,
            );
            mid = await connect_smtp_mailbox(store, secrets, config, settings=settings, **common);
        } else {
            token = _oauth_sign_in(args, env);
            if token is None {
                print("\n  Sign-in didn't finish, so nothing was connected.\n");
                return 1;
            }
            provider = "google" if args.kind == "gmail" else "microsoft";
            common |= {"provider": provider, "token": token};
            mid = await connect_oauth_mailbox(store, secrets, config, **common);
        }
    } except (ConnectRefused, SecretStoreUnavailable) as e {
        print(f"\n  {e}\n");
        return 1;
    }
    print(f"\n  Connected {address}.");
    if config.channels.email.max_daily_sends <= config.channels.email.per_inbox_daily_cap {
        print(_RAISE_MAX);
    }
    row = await store.get_mailbox(mid);
    return await _test(row, config, env, secrets, "  Couldn't build a connection to test.\n");
}

async def _find(store: MailboxStore, address: str) -> dict[any, any] | None {
    row = await store.get_mailbox_by_address(address);
    if row is None or row.get("state") == "retired" {
        print(f"\n  No connected inbox {address.strip().lower()}. See: sellbird inboxes list\n");
        return None;
    }
    return row;
}

async def _use(args: any, store: MailboxStore) -> int {
    ref = args.campaign;
    rows = await store._rows("SELECT id, name FROM campaigns WHERE id = ? OR name = ?", (ref, ref));
    if len(rows) != 1 {
        print(f"\n  {'No' if not rows else 'More than one'} campaign matches {ref!r}. {_USE_ID}\n");
        return 1;
    }
    ids: list[str] = [];
    for address in args.addresses {
        row = {"id": MAIN} if address.strip().lower() == MAIN_NAME else await _find(store, address);
        if row is None {
            return 1;
        }
        ids.append(row["id"]);
    }
    await store.set_campaign_pool(rows[0]["id"], ids);
    which = f"from {len(ids)} inbox(es) only." if ids else "from every inbox.";
    print(f"\n  This campaign sends {which} {_USED}\n");
    return 0;
}

async def run(args: any, store: MailboxStore, secrets: SecretStore, config: any, env: any) -> int {
    action = args.inboxes_action or "list";
    if action == "list" {
        await print_inbox_list(store, config, env);
        return 0;
    } elif action == "connect" {
        return await connect_flow(args, store, secrets, config, env);
    } elif action == "use" {
        return await _use(args, store);
    }
    row = await _find(store, args.address);
    if row is None {
        return 1;
    }
    (address, mailbox, details) = (row["address"], row["id"], {"inbox": row["address"]});
    if action == "test" {
        return await _test(row, config, env, secrets, _UNTESTABLE);
    } elif action == "pause" {
        await store.set_pause(mailbox, args.reason);
        details["reason"] = args.reason;
        said = f"Paused {address}. {_PAUSED}";
    } elif action == "resume" {
        await store.set_pause(mailbox, "");
        said = f"{address} sends again.";
    } elif action == "cap" {
        await store.set_cap(mailbox, args.cap);
        details["cap"] = args.cap;
        said = f"{address}: "
            + (f"up to {args.cap} cold emails a day." if args.cap else _DEFAULT_CAP);
    } elif action == "name" {
        await store.set_display_name(mailbox, args.name);
        print(f"\n  {address} sends as {args.name.strip() or config.persona.name}.\n");
        return 0;
    } elif action == "remove" {
        await store.retire(mailbox);
        said = f"Removed {address}. {_REMOVED}";
    } else {
        return 0;
    }
    await store.log_action(action_type=f"inbox_{_LOGGED[action]}", agent="you", details=details);
    print(f"\n  {said}\n");
    return 0;
}

async def _run_inboxes(args: any, config: any, env: any) -> int {
    state = StateManager();
    await state.init_db();
    return await run(args, MailboxStore(db_path=state.db_path), SecretStore(), config, env);
}

def cmd_inboxes(args: any) {
    sys.exit(asyncio.run(_run_inboxes(args, load_config(), load_env())));
}
