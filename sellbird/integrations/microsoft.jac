import asyncio;
import base64;
import builtins;
import hashlib;
import http.server;
import logging;
import socket;
import time;
import urllib.parse;
import from collections.abc { Callable }
import from datetime { datetime, timedelta, timezone }
import httpx;

glob logger: any = logging.getLogger("sellbird.microsoft"),
     TOKEN_FILE: any = PROJECT_ROOT / "data" / "m365_token.json",
     GRAPH: str = "https://graph.microsoft.com/v1.0",
     GRAPH_HOST: str = "graph.microsoft.com",
     INBOX_MESSAGES: str = "/me/mailFolders/inbox/messages",
     INBOX_MESSAGES_PATH: str = "/v1.0" + INBOX_MESSAGES,
     INBOX_NEXT_LINK_PATHS: set[str] = {
         INBOX_MESSAGES_PATH.lower(),
         "/v1.0/me/mailfolders('inbox')/messages",
         "/v1.0/me/mailfolders(%27inbox%27)/messages",
     },
     MAX_INBOX_PAGES: int = 40,
     LOGIN: str = "https://login.microsoftonline.com",
     SCOPE: str = "offline_access https://graph.microsoft.com/Mail.ReadWrite https://graph.microsoft.com/Mail.Send https://graph.microsoft.com/User.Read",
     LOOPBACK_PORT: int = 8766,
     REPLY_WINDOW_DAYS: int = 7,
     MAX_RETRY_AFTER_SECONDS: int = 10,
     TIMEOUT: any = httpx.Timeout(connect=10.0, read=30.0, write=30.0, pool=10.0),
     _SELECT: str = "id,subject,from,body,internetMessageId,conversationId,receivedDateTime,internetMessageHeaders";

class GraphError(RuntimeError) {
    has uncertain: bool = False;

    def init(message: str = "", uncertain: bool = False) {
        super.init(message);
        self.uncertain = uncertain;
    }
}

def _load_token -> builtins.dict | None {
    return read_token_file(current_home().m365_token_file, "Microsoft", logger);
}

def _save_token(data: builtins.dict) {
    write_token_file(current_home().m365_token_file, data);
}

def _token_url(tenant: str) -> str {
    return f"{LOGIN}/{tenant or 'organizations'}/oauth2/v2.0/token";
}

class MicrosoftProvider(MailProvider) {
    static has name: str = "microsoft";

    def init(
        config: any,
        env: any,
        transport: any = None,
        *,
        identity: MailIdentity | None = None,
        tokens: dyn TokenSource | None = None,
    ) {
        self.config = config;
        self.client_id = getattr(env, "m365_client_id", "");
        self.tenant = getattr(env, "m365_tenant_id", "") or "organizations";
        self._transport = transport;
        (self._access_token, self._access_expires, self._me) = ("", 0.0, "");
        self._main_mailbox = identity is None;
        self.identity = identity or identity_from_config(config);
        self._tokens = tokens;
    }

    def _load -> builtins.dict | None {
        return self._tokens.load() if self._tokens else _load_token();
    }

    def _save(data: builtins.dict) {
        (self._tokens.save if self._tokens else _save_token)(data);
    }

    def is_configured -> bool {
        return bool(self.client_id and self._load());
    }

    def _client -> httpx.AsyncClient {
        extra = {"transport": self._transport} if self._transport is not None else {};
        return httpx.AsyncClient(timeout=TIMEOUT, **extra);
    }

    async def _token -> str {
        if self._access_token and time.time() < self._access_expires - 60 {
            return self._access_token;
        }
        stored = self._load();
        if not stored {
            raise GraphError(
                missing_token_text(self._tokens, "not authorized. Run 'sellbird microsoft auth'.")
            );
        }
        try {
            async with self._client() as client {
                resp = await client.post(
                    _token_url(self.tenant),
                    data={
                        "client_id": self.client_id,
                        "grant_type": "refresh_token",
                        "refresh_token": stored["refresh_token"],
                        "scope": SCOPE,
                    },
                );
            }
        } except httpx.HTTPError as e {
            raise GraphError(f"token refresh failed: {e}") from e;
        }
        if resp.status_code != 200 {
            fix = "Connect this inbox again."
                if self._tokens
                else "Re-run 'sellbird microsoft auth'.";
            raise GraphError(
                f"token refresh rejected ({resp.status_code}): {resp.text[:200]}. " + fix
            );
        }
        data = resp.json();
        if data.get("refresh_token") {
            self._save({
                **stored,
                "refresh_token": data["refresh_token"],
                "refreshed_at": builtins.int(time.time()),
            });
        }
        self._access_token = data.get("access_token", "");
        self._access_expires = time.time() + float(data.get("expires_in", 3600));
        if not self._access_token {
            raise GraphError("token refresh returned no access token");
        }
        return self._access_token;
    }

    async def _request(method: str, path: str, **kwargs: any) -> builtins.dict {
        return await self._request_url(method, f"{GRAPH}{path}", **kwargs);
    }

    async def _request_url(
        method: str,
        url: str,
        *,
        headers: any = None,
        retry_503: bool = True,
        any_2xx_ok: bool = False,
        **kwargs: any,
    ) -> builtins.dict {
        path = url[len(GRAPH):] if url.startswith(GRAPH) else url;
        where = f"{method} {path}";
        token = await self._token();
        all_headers = {"Authorization": f"Bearer {token}", **(headers or {})};
        for attempt in (1, 2) {
            try {
                async with self._client() as client {
                    resp = await client.request(method, url, headers=all_headers, **kwargs);
                }
            } except httpx.HTTPError as e {
                never_left = isinstance(e, (httpx.ConnectError, httpx.ConnectTimeout));
                raise GraphError(f"{where} failed: {e}", uncertain=not never_left) from e;
            }
            if attempt == 1
                and (resp.status_code == 429 or (resp.status_code == 503 and retry_503))
            {
                try {
                    delay = float(resp.headers.get("Retry-After", "5"));
                } except ValueError {
                    delay = 5.0;
                }
                if delay <= MAX_RETRY_AFTER_SECONDS {
                    await asyncio.sleep(delay);
                    continue;
                }
            }
            break;
        }
        failed = f"Graph {resp.status_code} on {where}";
        if resp.status_code >= 400 {
            raise GraphError(f"{failed}: {resp.text[:200]}", uncertain=resp.status_code >= 500);
        }
        if any_2xx_ok {
            return {};
        }
        if not resp.content {
            if resp.status_code in (202, 204) {
                return {};
            }
            raise GraphError(f"{failed}: empty response");
        }
        try {
            data = resp.json();
        } except ValueError as e {
            raise GraphError(f"{failed}: malformed JSON") from e;
        }
        if not isinstance(data, builtins.dict) {
            raise GraphError(f"{failed}: expected a JSON object, got {type(data).__name__}");
        }
        return data;
    }

    async def _my_address -> str {
        if not self._me {
            me = await self._request("GET", "/me", params={"$select": "mail,userPrincipalName"});
            self._me = (me.get("mail") or me.get("userPrincipalName") or "").lower();
        }
        return self._me;
    }

    async def _check_identity -> str {
        me = await self._my_address();
        expected = (self.identity.address or "").strip().lower();
        if expected and me != expected {
            if self._main_mailbox {
                raise GraphError(
                    f"signed in as {me}, but persona.email is {expected}. Run 'sellbird microsoft auth' again and sign in as {expected}.",
                );
            }
            raise GraphError(
                f"signed in as {me}, but this inbox is {expected}. Connect it again and sign in as {expected}.",
            );
        }
        return me;
    }

    async def send_email(
        to_email: str,
        subject: str,
        body: str,
        thread_ref: str = "",
        in_reply_to: str = "",
        headers: any = (),
    ) -> SendResult {
        if headers {
            return SendResult(ok=False, error="Microsoft 365 can't add custom headers");
        }
        try {
            sig = load_signature(self.config);
        } except SignatureError as e {
            return SendResult(ok=False, error=f"signature: {e}"[:300]);
        }
        content = {
            "subject": subject,
            "body": {"contentType": "HTML", "content": render_html(body, sig)}
                if sig
                else {"contentType": "Text", "content": body},
            "toRecipients": [{"emailAddress": {"address": to_email}}],
        };
        draft: any = None;
        try {
            await self._check_identity();
            if thread_ref {
                try {
                    draft = await self._request("POST", f"/me/messages/{thread_ref}/createReply");
                    await self._request("PATCH", f"/me/messages/{draft['id']}", json=content);
                } except GraphError as e {
                    logger.warning(f"Microsoft: createReply failed ({e}); sending as new.");
                    if draft and draft.get("id") {
                        await self._delete_draft(draft["id"]);
                    }
                    draft = None;
                }
            }
            if draft is None {
                draft = await self._request("POST", "/me/messages", json=content);
            }
            if sig {
                await self._request(
                    "POST",
                    f"/me/messages/{draft['id']}/attachments",
                    json={
                        "@odata.type": "#microsoft.graph.fileAttachment",
                        "name": sig.filename,
                        "contentType": sig.mime,
                        "contentBytes": base64.b64encode(sig.data).decode(),
                        "isInline": True,
                        "contentId": sig.content_id,
                    },
                );
            }
            try {
                await self._request(
                    "POST", f"/me/messages/{draft['id']}/send", retry_503=False, any_2xx_ok=True
                );
            } except GraphError as e {
                if not e.uncertain {
                    raise;
                }
                logger.error(f"Microsoft send to {to_email} may have gone out: {e}");
                return SendResult(ok=False, error=str(e)[:300], uncertain=True);
            }
        } except (GraphError, KeyError) as e {
            if draft and draft.get("id") {
                await self._delete_draft(draft["id"]);
            }
            logger.error(f"Microsoft send failed to {to_email}: {e}");
            return SendResult(ok=False, error=str(e)[:300]);
        }
        return SendResult(
            ok=True,
            message_id=draft.get("internetMessageId", ""),
            thread_ref=draft.get("conversationId", ""),
        );
    }

    async def _delete_draft(draft_id: str) {
        try {
            await self._request("DELETE", f"/me/messages/{draft_id}");
        } except GraphError as e {
            logger.warning(f"Microsoft: couldn't delete unsent draft {draft_id}: {e}");
        }
    }

    async def get_replies(limit: int = 50) -> list[InboundMessage] {
        me = await self._check_identity();
        since = datetime.now(timezone.utc) - timedelta(days=REPLY_WINDOW_DAYS);
        url = str(
            httpx.URL(
                f"{GRAPH}{INBOX_MESSAGES}",
                params={
                    "$filter": f"receivedDateTime ge {since.strftime('%Y-%m-%dT%H:%M:%SZ')}",
                    "$orderby": "receivedDateTime desc",
                    "$top": str(max(1, builtins.int(limit))),
                    "$select": _SELECT,
                },
            ),
        );
        seen_urls = {url};
        seen_ids: set[str] = set();
        out: list[InboundMessage] = [];
        for page in range(1, MAX_INBOX_PAGES + 1) {
            data = await self._request_url(
                "GET", url, headers={"Prefer": "outlook.body-content-type=\"text\""}
            );
            items = data.get("value");
            if not isinstance(items, builtins.list) {
                raise GraphError(f"inbox page {page}: 'value' is missing or not a list");
            }
            for item in items {
                msg = self._parse_message(item);
                if msg and msg.from_email != me and msg.provider_id not in seen_ids {
                    seen_ids.add(msg.provider_id);
                    out.append(msg);
                }
            }
            next_link = data.get("@odata.nextLink");
            if next_link is None {
                return out;
            }
            url = _checked_next_link(next_link);
            if url in seen_urls {
                raise GraphError(f"inbox page {page}: @odata.nextLink repeats an earlier page");
            }
            seen_urls.add(url);
        }
        raise GraphError(f"inbox has more than {MAX_INBOX_PAGES} pages; refusing a partial read");
    }

    static def _parse_message(item: any) -> InboundMessage | None {
        def checked(value: any, what: str, kind: any, empty: any, name: str) -> any {
            if value is None {
                return empty;
            }
            if not isinstance(value, kind) {
                raise GraphError(f"malformed inbox message: {what} is not {name}");
            }
            return value;
        }
        def as_obj(value: any, what: str) -> any {
            return checked(value, what, builtins.dict, {}, "an object");
        }
        def text(value: any, what: str) -> any {
            return checked(value, what, str, "", "a string");
        }
        if not isinstance(item, builtins.dict) {
            raise GraphError("malformed inbox message: not an object");
        }
        msg_id = text(item.get("id"), "id");
        if not msg_id {
            raise GraphError("malformed inbox message: no id");
        }
        sender = as_obj(as_obj(item.get("from"), "from").get("emailAddress"), "from.emailAddress");
        from_email = text(sender.get("address"), "sender address").strip().lower();
        if not from_email {
            return None;
        }
        subject = text(item.get("subject"), "subject");
        raw_headers = item.get("internetMessageHeaders") or [];
        if not isinstance(raw_headers, builtins.list) {
            raise GraphError("malformed inbox message: internetMessageHeaders is not a list");
        }
        headers: builtins.dict = {};
        for h in raw_headers {
            h = as_obj(h, "header");
            headers[text(h.get("name"), "header name").lower()] = text(
                h.get("value"), "header value"
            );
        }
        return InboundMessage(
            provider_id=msg_id,
            from_email=from_email,
            subject=subject,
            body=text(as_obj(item.get("body"), "body").get("content"), "body content")[:5000],
            message_id=text(item.get("internetMessageId"), "internetMessageId"),
            in_reply_to=headers.get("in-reply-to", ""),
            thread_ref=msg_id,
            date=text(item.get("receivedDateTime"), "receivedDateTime"),
            is_bounce=looks_like_bounce(from_email, subject),
            headers=headers,
        );
    }

    async def test_connection -> tuple[bool, str] {
        if not self.client_id {
            return (False, "M365_CLIENT_ID missing from .env");
        }
        if not self._load() {
            return (
                False,
                missing_token_text(
                    self._tokens, "Not authorized yet — run 'sellbird microsoft auth'"
                ),
            );
        }
        try {
            me = await self._check_identity();
            await self._request(
                "GET", "/me/mailFolders/inbox/messages", params={"$top": "1", "$select": "id"}
            );
        } except GraphError as e {
            return (False, str(e)[:300]);
        }
        return (True, f"Connected as {me}");
    }
}

def _checked_next_link(link: any) -> str {
    if not isinstance(link, str) or not link {
        raise GraphError("@odata.nextLink is not a URL");
    }
    if any([c in "#\\" or c.isspace() or ord(c) < 32 for c in link]) {
        raise GraphError("@odata.nextLink rejected: unexpected characters");
    }
    try {
        url = httpx.URL(link);
    } except (httpx.InvalidURL, ValueError) as e {
        raise GraphError(f"@odata.nextLink rejected: {e}") from e;
    }
    path = url.raw_path.split(b"?", 1)[0].decode("ascii", "replace");
    if url.scheme != "https"
        or url.host != GRAPH_HOST
        or url.port not in (None, 443)
        or url.userinfo
        or url.fragment
        or path.lower() not in INBOX_NEXT_LINK_PATHS
        or not url.query
    {
        raise GraphError("@odata.nextLink rejected: not the Graph inbox listing");
    }
    return link;
}

def _pkce_pair -> tuple[str, str] {
    verifier = token_urlsafe(64)[:96];
    challenge = base64.urlsafe_b64encode(
        hashlib.sha256(verifier.encode()).digest()
    ).decode().rstrip("=");
    return (verifier, challenge);
}

class _LoopbackServer(http.server.HTTPServer) {
    static has allow_reuse_address: bool = True;
}

class _LoopbackServerV6(_LoopbackServer) {
    static has address_family: any = socket.AF_INET6;
}

def authorized_address(access_token: str, transport: any = None) -> str {
    with httpx.Client(timeout=TIMEOUT, transport=transport) as client {
        resp = client.get(
            f"{GRAPH}/me",
            params={"$select": "mail,userPrincipalName"},
            headers={"Authorization": f"Bearer {access_token}"},
        );
    }
    resp.raise_for_status();
    me = resp.json();
    return (me.get("mail") or me.get("userPrincipalName") or "").strip().lower();
}

def run_auth_flow(
    client_id: str,
    tenant: str = "",
    *,
    save: Callable[[builtins.dict], None] | None = None,
    expected_address: str | None = None,
    scope: str | None = None,
) -> bool {
    scope = scope or SCOPE;
    if not client_id {
        print("  Set M365_CLIENT_ID (and M365_TENANT_ID) in .env first.");
        print("  (entra.microsoft.com → App registrations → New registration)");
        return False;
    }
    tenant = tenant or "organizations";
    state = token_urlsafe(16);
    (verifier, challenge) = _pkce_pair();
    redirect_uri = f"http://localhost:{LOOPBACK_PORT}";
    auth_url = f"{LOGIN}/{tenant}/oauth2/v2.0/authorize?"
        + urllib.parse.urlencode({
            "client_id": client_id,
            "response_type": "code",
            "redirect_uri": redirect_uri,
            "response_mode": "query",
            "scope": scope,
            "state": state,
            "code_challenge": challenge,
            "code_challenge_method": "S256",
            "prompt": "select_account",
        });
    result = loopback_code(
        auth_url,
        state,
        "Microsoft",
        "Microsoft 365",
        [(_LoopbackServer, "127.0.0.1"), (_LoopbackServerV6, "::1")],
        LOOPBACK_PORT,
        ("error_description", "error"),
    );
    if result is None {
        return False;
    }
    resp = httpx.post(
        _token_url(tenant),
        data={
            "client_id": client_id,
            "grant_type": "authorization_code",
            "code": result["code"],
            "redirect_uri": redirect_uri,
            "code_verifier": verifier,
            "scope": scope,
        },
        timeout=30,
    );
    if resp.status_code != 200 {
        print(f"  Token exchange failed ({resp.status_code}): {resp.text[:300]}");
        return False;
    }
    data = resp.json();
    if not data.get("refresh_token") {
        print("  Microsoft returned no refresh token (offline_access missing?).");
        return False;
    }
    record = {
        "refresh_token": data["refresh_token"],
        "tenant": tenant,
        "scope": data.get("scope", scope),
        "obtained_at": builtins.int(time.time()),
    };
    who = lambda -> str { return authorized_address(data.get("access_token", "")); };
    if not save_if_signed_in_as(record, expected_address, who, save or _save_token) {
        return False;
    }
    print(
        "  ✓ Microsoft 365 authorized."
            if save
            else f"  ✓ Microsoft 365 authorized. Token stored at {current_home().m365_token_file}",
    );
    return True;
}
