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

impl compose(
    to_email: str,
    sender: str,
    subject: str,
    body: str,
    sig: any,
    headers: any,
    in_reply_to: str,
    message_id: str = "",
) -> EmailMessage {
    msg = EmailMessage();
    msg["To"] = to_email;
    msg["From"] = sender;
    msg["Subject"] = subject;
    for (name, value) in headers {
        msg[name] = value;
    }
    if message_id {
        msg["Message-ID"] = message_id;
    }
    if in_reply_to {
        msg["In-Reply-To"] = in_reply_to;
        msg["References"] = in_reply_to;
    }
    set_body(msg, body, sig);
    return msg;
}

impl read_token_file(path: any, label: str, log: any) -> builtins.dict | None {
    try {
        data = json.loads(path.read_text(encoding="utf-8")) if path.is_file() else None;
        if isinstance(data, builtins.dict) and data.get("refresh_token") {
            return data;
        }
    } except (OSError, json.JSONDecodeError) as e {
        log.warning(f"Could not read {label} token file: {e}");
    }
    return None;
}

impl write_token_file(path: any, data: builtins.dict) {
    path.parent.mkdir(parents=True, exist_ok=True);
    path.write_text(json.dumps(data, indent=2), encoding="utf-8");
    try {
        path.chmod(0o600);
    } except OSError {}
}

impl loopback_code(
    auth_url: str,
    state: str,
    signer: str,
    service: str,
    servers: list[any],
    port: int,
    error_keys: tuple[str, ...],
) -> builtins.dict | None {
    result: builtins.dict = {};
    done = threading.Event();
    page = f"<h2>Sellbird is connected to {service}.</h2>You can close this tab.".encode();
    class Handler(http.server.BaseHTTPRequestHandler) {
        def do_GET {
            query = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query);
            if query.get("state", [""])[0] != state {
                self.send_response(400);
                self.end_headers();
                return;
            }
            result["code"] = query.get("code", [""])[0];
            result["error"] = next((query[k][0] for k in error_keys if query.get(k)), None) or "";
            self.send_response(200);
            self.send_header("Content-Type", "text/html");
            self.end_headers();
            self.wfile.write(page);
            done.set();
        }

        def log_message(*args: any) {}
    }
    bound: list[any] = [];
    for (server_class, host) in servers {
        try {
            bound.append(server_class((host, port), Handler));
        } except OSError {
            if not bound {
                raise;
            }
        }
    }
    for server in bound {
        threading.Thread(target=server.serve_forever, daemon=True).start();
    }
    print(f"\n  Opening browser for {signer} sign-in...\n  {auth_url}\n");
    webbrowser.open(auth_url);
    finished = done.wait(timeout=300);
    for server in bound {
        server.shutdown();
        server.server_close();
    }
    if not finished {
        print("  Timed out waiting for the browser round-trip.");
        return None;
    }
    if result.get("error") or not result.get("code") {
        print(f"  Authorization failed: {result.get('error') or 'no code returned'}");
        return None;
    }
    return result;
}
