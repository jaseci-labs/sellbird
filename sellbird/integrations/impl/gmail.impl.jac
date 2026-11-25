impl _entry_id(change: any, page: int) -> str {
    msg = change.get("message") if isinstance(change, builtins.dict) else None;
    msg_id = msg.get("id") if isinstance(msg, builtins.dict) else None;
    if not isinstance(msg_id, str) or not msg_id {
        raise GmailError(f"history page {page}: a change has no message id");
    }
    return msg_id;
}

impl _next_page(data: builtins.dict, seen: set[str], where: str) -> str | None {
    token = data.get("nextPageToken");
    if token is None {
        return None;
    }
    if not isinstance(token, str) or not token or token in seen {
        raise GmailError(f"{where}: invalid or repeated nextPageToken");
    }
    seen.add(token);
    return token;
}

impl _load_token -> builtins.dict | None {
    return read_token_file(current_home().gmail_token_file, "Gmail", logger);
}

impl _save_token(data: builtins.dict) {
    write_token_file(current_home().gmail_token_file, data);
}

impl GmailProvider.init(
    config: any,
    env: any,
    transport: any = None,
    *,
    identity: MailIdentity | None = None,
    tokens: dyn TokenSource | None = None,
) {
    self.config = config;
    self.client_id = getattr(env, "gmail_client_id", "");
    self.client_secret = getattr(env, "gmail_client_secret", "");
    self._transport = transport;
    (self._access_token, self._access_expires, self._token_problem) = ("", 0.0, "");
    self._read_cache = {};
    self._label_cache = {};
    (self._history_id, self._pending) = (None, None);
    (self._last_full_read, self._verify_week) = (0.0, False);
    self.identity = identity or identity_from_config(config);
    self._tokens = tokens;
}

impl GmailProvider._load -> builtins.dict | None {
    return self._tokens.load() if self._tokens else _load_token();
}

impl GmailProvider._client -> httpx.AsyncClient {
    extra = {"transport": self._transport} if self._transport is not None else {};
    return httpx.AsyncClient(timeout=TIMEOUT, **extra);
}

impl GmailProvider.is_configured -> bool {
    return bool(self.client_id and self.client_secret and self._load());
}

impl GmailProvider._token -> str | None {
    if self._access_token and time.time() < self._access_expires - 60 {
        return self._access_token;
    }
    stored = self._load();
    if not stored {
        self._token_problem = missing_token_text(
            self._tokens, "not signed in to Gmail. Run 'sellbird gmail auth'."
        );
        logger.error("Gmail: " + self._token_problem);
        return None;
    }
    unreachable = "couldn't reach Google to refresh the Gmail sign-in{}; Sellbird tries again next cycle.";
    try {
        async with self._client() as client {
            resp = await client.post(
                TOKEN_URL,
                data={
                    "client_id": self.client_id,
                    "client_secret": self.client_secret,
                    "refresh_token": stored["refresh_token"],
                    "grant_type": "refresh_token",
                },
            );
        }
    } except httpx.HTTPError as e {
        logger.error(f"Gmail token refresh failed: {e}");
        self._token_problem = unreachable.format(f" ({type(e).__name__})");
        return None;
    }
    if resp.status_code in (400, 401, 403) {
        fix = "Connect this inbox again." if self._tokens else "Run 'sellbird gmail auth'.";
        self._token_problem = f"Google rejected the saved Gmail sign-in ({resp.status_code}). "
            + fix;
        logger.error(f"Gmail token refresh rejected ({resp.status_code}). " + fix);
        return None;
    }
    if resp.status_code != 200 {
        self._token_problem = unreachable.format(f" (HTTP {resp.status_code})");
        logger.error(f"Gmail token refresh failed ({resp.status_code}).");
        return None;
    }
    try {
        data = resp.json();
    } except ValueError {
        data = None;
    }
    token = data.get("access_token") if isinstance(data, builtins.dict) else None;
    if not isinstance(token, str) or not token {
        self._token_problem = unreachable.format(" (no token in Google's answer)");
        logger.error("Gmail token refresh returned no access token.");
        return None;
    }
    self._token_problem = "";
    try {
        expires_in = float(data.get("expires_in") or 3600);
    } except (TypeError, ValueError) {
        expires_in = 3600.0;
    }
    self._access_token = token;
    self._access_expires = time.time() + expires_in;
    return self._access_token or None;
}

impl GmailProvider._request(
    method: str, path: str, *, sending: bool = False, not_found: any = None, **kwargs: any
) -> any {
    token = await self._token();
    if not token {
        return None;
    }
    try {
        async with self._client() as client {
            resp = await client.request(
                method, f"{API_BASE}{path}", headers={"Authorization": f"Bearer {token}"}, **kwargs
            );
        }
    } except httpx.HTTPError as e {
        logger.error(f"Gmail request failed ({path}): {e}");
        if sending {
            raise RuntimeError("Gmail send outcome is unknown") from e;
        }
        return None;
    }
    status = resp.status_code;
    if sending and not (200 <= status and status < 300 or 400 <= status and status < 500) {
        raise RuntimeError("Gmail send outcome is unknown");
    }
    if status == 404 and not_found is not None {
        return not_found;
    }
    if status >= 400 {
        logger.error(f"Gmail API {status} on {path}: {resp.text[:200]}");
        return None;
    }
    try {
        data = resp.json();
        if sending
            and (
                not isinstance(data, builtins.dict)
                or not isinstance(data.get("id"), str)
                or not data["id"].strip()
            )
        {
            raise ValueError("Missing Gmail send message ID");
        }
        return data;
    } except ValueError as e {
        logger.error(f"Gmail returned malformed JSON ({path})");
        if sending {
            raise RuntimeError("Gmail send returned an unreadable response") from e;
        }
        return None;
    }
}

impl GmailProvider.send_email(
    to_email: str,
    subject: str,
    body: str,
    thread_ref: str = "",
    in_reply_to: str = "",
    headers: any = (),
) -> SendResult {
    try {
        sig = load_signature(self.config);
    } except SignatureError as e {
        return SendResult(ok=False, error=f"signature: {e}"[:300]);
    }
    me = self.identity;
    sender = formataddr((me.display_name, me.address)) if me.address else me.display_name;
    msg = compose(to_email, sender, subject, body, sig, headers, in_reply_to);
    payload: builtins.dict = {"raw": base64.urlsafe_b64encode(msg.as_bytes()).decode()};
    if thread_ref {
        payload["threadId"] = thread_ref;
    }
    data = await self._request("POST", "/messages/send", sending=True, json=payload);
    if data is None {
        return SendResult(ok=False, error="gmail send failed");
    }
    message_id = "";
    gmail_id = data.get("id", "");
    if gmail_id {
        try {
            meta = await self._request(
                "GET",
                f"/messages/{gmail_id}",
                params={"format": "metadata", "metadataHeaders": "Message-ID"},
            );
        } except Exception {
            logger.warning("Gmail sent message metadata could not be read");
            meta = None;
        }
        metadata = meta.get("payload") if isinstance(meta, builtins.dict) else None;
        found = metadata.get("headers") if isinstance(metadata, builtins.dict) else None;
        for h in (found if isinstance(found, builtins.list) else []) {
            if isinstance(h, builtins.dict)
                and isinstance(h.get("name"), str)
                and h["name"].lower() == "message-id"
                and isinstance(h.get("value"), str)
            {
                message_id = h["value"];
            }
        }
    }
    thread = data.get("threadId", "");
    return SendResult(
        ok=True,
        message_id=message_id or gmail_id,
        thread_ref=thread if isinstance(thread, str) else "",
    );
}

impl GmailProvider.get_replies(limit: int = 500) -> list[InboundMessage] {
    if not await self._token() {
        raise GmailError(
            self._token_problem or "not signed in to Gmail. Run 'sellbird gmail auth'."
        );
    }
    self._pending = None;
    recent_full = self._last_full_read
        and time.time() - self._last_full_read < FULL_READ_EVERY_SECONDS;
    if self._history_id and recent_full {
        changed = await self._read_history(self._history_id);
        if changed is not None {
            (messages, marker) = changed;
            if self._verify_week {
                have = {m.provider_id for m in messages};
                messages = messages + [
                    m
                    for m in await self._read_week(limit, prune=False)
                    if m.provider_id not in have
                ];
            }
            self._pending = (marker, False, self._verify_week);
            return messages;
        }
        logger.info("Gmail: the history marker has expired; reading the last week in full.");
    }
    marker = await self._current_history_id();
    messages = await self._read_week(limit);
    self._pending = (marker, True, False);
    return messages;
}

impl GmailProvider.confirm_read {
    if not self._pending {
        return;
    }
    (marker, full, verified) = self._pending;
    self._pending = None;
    self._history_id = marker;
    if full {
        self._last_full_read = time.time();
        self._verify_week = True;
    } elif verified {
        self._verify_week = False;
    }
}

impl GmailProvider._current_history_id -> str | None {
    try {
        profile = await self._request("GET", "/profile");
    } except Exception as e {
        logger.warning(f"Gmail: couldn't read the history marker: {e}");
        return None;
    }
    marker = profile.get("historyId") if isinstance(profile, builtins.dict) else None;
    return str(marker) if isinstance(marker, (str, builtins.int)) and str(marker) else None;
}

impl GmailProvider._fetch(msg_id: str, where: str) -> any {
    if msg_id in self._read_cache {
        return (self._read_cache[msg_id], self._label_cache.get(msg_id, frozenset()));
    }
    data = await self._request(
        "GET", f"/messages/{msg_id}", params={"format": "full"}, not_found=_GONE
    );
    if data is _GONE {
        return _GONE;
    }
    if not isinstance(data, builtins.dict) or data.get("id") != msg_id {
        raise GmailError(f"{where}: could not read message {msg_id}");
    }
    labels = data.get("labelIds");
    self._read_cache[msg_id] = self._parse_message(data);
    self._label_cache[msg_id] = frozenset([l for l in labels if isinstance(l, str)])
        if isinstance(labels, builtins.list)
        else frozenset();
    return (self._read_cache[msg_id], self._label_cache[msg_id]);
}

impl GmailProvider._read_history(start: str) -> any {
    params: builtins.dict = {
        "startHistoryId": start,
        "historyTypes": ["messageAdded", "labelAdded"],
        "labelId": "INBOX",
        "maxResults": 500,
    };
    wanted: list[tuple[str, bool]] = [];
    seen_tokens: set[str] = set();
    marker: any = None;
    for page in range(1, MAX_INBOX_PAGES + 1) {
        data = await self._request(
            "GET", "/history", params=builtins.dict(params), not_found=_GONE
        );
        if data is _GONE {
            return None;
        }
        if not isinstance(data, builtins.dict)
            or not isinstance(data.get("history", []), builtins.list)
        {
            raise GmailError(f"history page {page}: could not read changes");
        }
        if page == 1 {
            marker = data.get("historyId");
            if not isinstance(marker, (str, builtins.int)) or not str(marker) {
                raise GmailError("history page 1: no historyId");
            }
        }
        for record in data.get("history", []) {
            if not isinstance(record, builtins.dict) {
                raise GmailError(f"history page {page}: a record is not an object");
            }
            for change in record.get("messagesAdded") or [] {
                wanted.append((_entry_id(change, page), False));
            }
            for change in record.get("labelsAdded") or [] {
                labels = change.get("labelIds") if isinstance(change, builtins.dict) else None;
                if "INBOX" in (labels or []) {
                    wanted.append((_entry_id(change, page), True));
                }
            }
        }
        params["pageToken"] = _next_page(data, seen_tokens, f"history page {page}");
        if params["pageToken"] is None {
            break;
        }
    } else {
        raise GmailError(f"history has more than {MAX_INBOX_PAGES} pages; refusing a partial read");
    }
    out: list[InboundMessage] = [];
    done: set[str] = set();
    for (msg_id, moved_in) in wanted {
        if msg_id in done {
            continue;
        }
        done.add(msg_id);
        if moved_in {
            self._read_cache.pop(msg_id, None);
            self._label_cache.pop(msg_id, None);
        }
        got = await self._fetch(msg_id, "history");
        if got is _GONE {
            continue;
        }
        (msg, labels) = got;
        if msg and not (labels & _NOT_REPLIES or (not moved_in and "INBOX" not in labels)) {
            out.append(msg);
        }
    }
    return (out, str(marker));
}

impl GmailProvider._read_week(limit: int, prune: bool = True) -> list[InboundMessage] {
    params: builtins.dict = {
        "q": "in:inbox -from:me newer_than:7d",
        "maxResults": max(1, min(500, builtins.int(limit))),
    };
    out: list[InboundMessage] = [];
    seen_ids: set[str] = set();
    seen_tokens: set[str] = set();
    for page in range(1, MAX_INBOX_PAGES + 1) {
        listing = await self._request("GET", "/messages", params=builtins.dict(params));
        if not isinstance(listing, builtins.dict) {
            raise GmailError(f"inbox page {page}: could not read messages");
        }
        messages = listing.get("messages", []);
        if not isinstance(messages, builtins.list) {
            raise GmailError(f"inbox page {page}: messages is not a list");
        }
        for stub in messages {
            msg_id = stub.get("id") if isinstance(stub, builtins.dict) else None;
            if not isinstance(msg_id, str) or not msg_id {
                raise GmailError(f"inbox page {page}: message has no id");
            }
            if msg_id not in seen_ids {
                seen_ids.add(msg_id);
                got = await self._fetch(msg_id, f"inbox page {page}");
                if got is not _GONE and got[0] {
                    out.append(got[0]);
                }
            }
        }
        params["pageToken"] = _next_page(listing, seen_tokens, f"inbox page {page}");
        if params["pageToken"] is None {
            if prune {
                self._read_cache = {k: v for (k, v) in self._read_cache.items() if k in seen_ids};
                self._label_cache = {k: v for (k, v) in self._label_cache.items() if k in seen_ids};
            }
            return out;
        }
    }
    raise GmailError(f"inbox has more than {MAX_INBOX_PAGES} pages; refusing a partial read");
}

impl GmailProvider._parse_message(data: builtins.dict) -> InboundMessage | None {
    payload = data.get("payload") or {};
    headers = {h.get("name", "").lower(): h.get("value", "") for h in payload.get("headers", [])};
    from_email = parseaddr(headers.get("from", ""))[1].lower();
    if not from_email {
        return None;
    }
    subject = headers.get("subject", "");
    return InboundMessage(
        provider_id=data.get("id", ""),
        from_email=from_email,
        subject=subject,
        body=(GmailProvider._extract_text(payload) or data.get("snippet", ""))[:5000],
        message_id=headers.get("message-id", ""),
        in_reply_to=headers.get("in-reply-to", ""),
        thread_ref=data.get("threadId", ""),
        date=headers.get("date", ""),
        is_bounce=looks_like_bounce(from_email, subject),
        headers=headers,
    );
}

impl GmailProvider._extract_text(payload: builtins.dict) -> str {
    def decode(part: any) -> str {
        data = (part.get("body") or {}).get("data", "");
        if not data {
            return "";
        }
        try {
            raw = base64.urlsafe_b64decode(data + "===");
        } except Exception {
            return "";
        }
        charset = "utf-8";
        try {
            headers = part.get("headers");
            for header in (headers if isinstance(headers, builtins.list) else []) {
                if isinstance(header, builtins.dict)
                    and isinstance(header.get("value"), str)
                    and str(header.get("name") or "").lower() == "content-type"
                {
                    mime = Message();
                    mime["Content-Type"] = header["value"];
                    charset = mime.get_content_charset() or "utf-8";
                    break;
                }
            }
        } except Exception {
            charset = "utf-8";
        }
        try {
            if codecs.lookup(charset).name.replace("-", "_") in _NOT_MAIL_CHARSETS {
                charset = "utf-8";
            }
        } except (LookupError, ValueError, TypeError) {
            charset = "utf-8";
        }
        raw = raw[:MAX_DECODE_BYTES];
        try {
            return raw.decode(charset, errors="replace");
        } except (LookupError, ValueError) {
            return raw.decode("utf-8", errors="replace");
        }
    }
    mime_type = payload.get("mimeType", "");
    if mime_type.startswith("text/plain") {
        return decode(payload);
    }
    for part in payload.get("parts", []) or [] {
        text = GmailProvider._extract_text(part);
        if text {
            return text;
        }
    }
    return re.sub("<[^>]+>", " ", decode(payload)) if mime_type.startswith("text/html") else "";
}

impl GmailProvider.test_connection -> tuple[bool, str] {
    if not self.client_id or not self.client_secret {
        return (False, "GMAIL_CLIENT_ID / GMAIL_CLIENT_SECRET missing from .env");
    }
    if not self._load() {
        return (
            False,
            missing_token_text(self._tokens, "Not authorized yet — run 'sellbird gmail auth'"),
        );
    }
    data = await self._request("GET", "/profile");
    if data and data.get("emailAddress") {
        return (True, f"Connected as {data['emailAddress']}");
    }
    return (False, "Token refresh or profile fetch failed");
}

impl authorized_address(access_token: str, transport: any = None) -> str {
    with httpx.Client(timeout=TIMEOUT, transport=transport) as client {
        resp = client.get(
            f"{API_BASE}/profile", headers={"Authorization": f"Bearer {access_token}"}
        );
    }
    resp.raise_for_status();
    return (resp.json().get("emailAddress") or "").strip().lower();
}

impl run_auth_flow(
    client_id: str,
    client_secret: str,
    *,
    save: Callable[[builtins.dict], None] | None = None,
    expected_address: str | None = None,
) -> bool {
    if not client_id or not client_secret {
        print("  Set GMAIL_CLIENT_ID and GMAIL_CLIENT_SECRET in .env first.");
        print("  (Google Cloud Console → APIs → Credentials → OAuth client, Desktop app)");
        return False;
    }
    state = token_urlsafe(16);
    redirect_uri = f"http://localhost:{LOOPBACK_PORT}";
    auth_url = AUTH_URL
        + "?"
        + urllib.parse.urlencode({
            "client_id": client_id,
            "redirect_uri": redirect_uri,
            "response_type": "code",
            "scope": SCOPE,
            "access_type": "offline",
            "prompt": "consent",
            "state": state,
        });
    result = loopback_code(
        auth_url,
        state,
        "Google",
        "Gmail",
        [(http.server.HTTPServer, "localhost")],
        LOOPBACK_PORT,
        ("error",),
    );
    if result is None {
        return False;
    }
    resp = httpx.post(
        TOKEN_URL,
        data={
            "client_id": client_id,
            "client_secret": client_secret,
            "code": result["code"],
            "grant_type": "authorization_code",
            "redirect_uri": redirect_uri,
        },
        timeout=30,
    );
    if resp.status_code != 200 {
        print(f"  Token exchange failed ({resp.status_code}): {resp.text[:200]}");
        return False;
    }
    data = resp.json();
    if not data.get("refresh_token") {
        print(
            "  Google returned no refresh token. Remove Sellbird from your account's third-party access list and retry.",
        );
        return False;
    }
    record = {
        "refresh_token": data["refresh_token"],
        "scope": data.get("scope", SCOPE),
        "obtained_at": builtins.int(time.time()),
    };
    who = lambda -> str { return authorized_address(data.get("access_token", "")); };
    if not save_if_signed_in_as(record, expected_address, who, save or _save_token) {
        return False;
    }
    print(
        "  ✓ Gmail authorized."
            if save
            else f"  ✓ Gmail authorized. Token stored at {current_home().gmail_token_file}",
    );
    return True;
}
