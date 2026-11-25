impl identity_from_config(config: any) -> MailIdentity {
    persona = getattr(config, "persona", None);
    return MailIdentity(
        address=(getattr(persona, "email", "") or "").strip(),
        display_name=getattr(persona, "name", "") or "",
    );
}

impl missing_token_text(tokens: any, main_mailbox_text: str) -> str {
    if tokens is None {
        return main_mailbox_text;
    }
    reason = getattr(tokens, "missing_reason", None);
    return reason() if reason else INBOX_NOT_CONNECTED;
}

impl save_if_signed_in_as(
    record: builtins.dict,
    expected_address: str | None,
    read_address: Callable[[], str],
    save: Callable[[builtins.dict], None],
) -> bool {
    if expected_address {
        expected = expected_address.strip().lower();
        try {
            got = read_address();
        } except Exception as e {
            print(f"  Could not read which account signed in: {type(e).__name__}");
            return False;
        }
        if got != expected {
            print(
                f"  Signed in as {got}, but this inbox is {expected}. Run it again and sign in as {expected}.",
            );
            return False;
        }
    }
    save(record);
    return True;
}

impl _unquoted(text: str) -> str {
    return "\n".join([l for l in text.split("\n") if not l.lstrip().startswith(">")]);
}

impl strip_quoted_reply(body: str) -> str {
    text = (body or "").replace("\r\n", "\n");
    cut = min([len(text)] + [m.start() for m in [p.search(text) for p in _BLOCK_HEADERS] if m]);
    head = text[:cut];
    for pattern in _ATTRIBUTION_HEADERS {
        m = pattern.search(head);
        if m {
            below = head[m.end():];
            marked = any([l.lstrip().startswith(">") for l in below.split("\n")]);
            head = head[:m.start()] + ("\n" + below if marked else "");
        }
    }
    kept = _unquoted(head).strip() or _unquoted(text).strip();
    return re.sub("\\n{3,}", "\n\n", kept);
}

impl looks_like_bounce(from_email: str, subject: str) -> bool {
    f = (from_email or "").lower();
    s = (subject or "").lower();
    return any([m in f for m in BOUNCE_SENDERS]) or any([m in s for m in BOUNCE_SUBJECTS]);
}

impl MailProvider.confirm_read {}

impl get_mail_provider(config: any, env: any) -> MailProvider | None {
    found = _PROVIDER_CLASSES.get((config.channels.email.provider or "").strip().lower());
    if found is None {
        return None;
    }
    (module, cls) = found;
    return getattr(importlib.import_module(f"sellbird.integrations.{module}"), cls)(config, env);
}
