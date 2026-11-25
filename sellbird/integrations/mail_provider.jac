import builtins;
import http.server;
import importlib;
import json;
import logging;
import re;
import threading;
import urllib.parse;
import webbrowser;
import from abc { ABC, abstractmethod }
import from collections.abc { Callable, Sequence }
import from dataclasses { dataclass, field }
import from email.message { EmailMessage }
import from typing { Protocol }

glob logger: any = logging.getLogger("sellbird.mail"),
     token_urlsafe: any = importlib.import_module("secrets").token_urlsafe,
     NATIVE_PROVIDERS: any = ("gmail", "smtp", "microsoft"),
     _PROVIDER_CLASSES: dict[str, tuple[str, str]] = {
         "gmail": ("gmail", "GmailProvider"),
         "smtp": ("smtp_mail", "SmtpImapProvider"),
         "microsoft": ("microsoft", "MicrosoftProvider"),
     },
     INBOX_NOT_CONNECTED: any = "This inbox isn't connected, or its saved sign-in can't be read. Connect it again.",
     BOUNCE_SENDERS: any = ("mailer-daemon", "postmaster", "mail delivery subsystem"),
     BOUNCE_SUBJECTS: any = tuple(
         "delivery status notification|undeliverable|returned mail|delivery failure|failure notice|could not be delivered|delivery incomplete|address not found".split(
             "|"
         ),
     ),
     _ATTRIBUTION_HEADERS: any = tuple(
         re.compile(
             "^[ \\t]*" + lead + "\\b[^\\n]{0,300}(?:\\n[^\\n]{0,300})?\\b" + tail + "[ \\t]*$",
             re.MULTILINE,
         )
         for (lead, tail) in [
             ("On", "wrote:"),
             ("El", "escribi[oó]:"),
             ("Am", "schrieb[^\\n]{0,100}:"),
             ("Le", "a [ée]crit[ \\t]*:"),
         ],
     ),
     _BLOCK_HEADERS: any = (
         re.compile(
             "^[ \\t]*-{2,}[ \\t]*Original Message[ \\t]*-{2,}", re.MULTILINE | re.IGNORECASE
         ),
         re.compile(
             "^[ \\t]*(?:_{10,}[ \\t]*\\n[ \\t]*)?(?:From|Von|De):[^\\n]*\\n[ \\t]*(?:Sent|Date|Gesendet|Enviado|Envoy[ée]):",
             re.MULTILINE,
         ),
     );

@dataclass
class SendResult {
    has ok: bool,
        message_id: str = "",
        thread_ref: str = "",
        error: str = "",
        uncertain: bool = False;
}

@dataclass(frozen=True)
class MailIdentity {
    has address: str,
        display_name: str;
}

def identity_from_config(config: any) -> MailIdentity {
    persona = getattr(config, "persona", None);
    return MailIdentity(
        address=(getattr(persona, "email", "") or "").strip(),
        display_name=getattr(persona, "name", "") or "",
    );
}

class TokenSource(Protocol) {
    def load -> builtins.dict | None abst;
    def save(data: builtins.dict) -> None abst;
}

def missing_token_text(tokens: any, main_mailbox_text: str) -> str {
    if tokens is None {
        return main_mailbox_text;
    }
    reason = getattr(tokens, "missing_reason", None);
    return reason() if reason else INBOX_NOT_CONNECTED;
}

def save_if_signed_in_as(
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

@dataclass
class InboundMessage {
    has provider_id: str,
        from_email: str,
        subject: str = "",
        body: str = "",
        message_id: str = "",
        in_reply_to: str = "",
        thread_ref: str = "",
        date: str = "",
        is_bounce: bool = False,
        headers: builtins.dict = field(default_factory=builtins.dict);
}

def _unquoted(text: str) -> str {
    return "\n".join([l for l in text.split("\n") if not l.lstrip().startswith(">")]);
}

def strip_quoted_reply(body: str) -> str {
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

def looks_like_bounce(from_email: str, subject: str) -> bool {
    f = (from_email or "").lower();
    s = (subject or "").lower();
    return any([m in f for m in BOUNCE_SENDERS]) or any([m in s for m in BOUNCE_SUBJECTS]);
}

class MailProvider(ABC) {
    static has carries_headers: bool = False;
    has name: str = "base";

    @abstractmethod
    def is_configured -> bool abst;

    @abstractmethod
    async def send_email(
        to_email: str,
        subject: str,
        body: str,
        thread_ref: str = "",
        in_reply_to: str = "",
        headers: Sequence[tuple[str, str]] = (),
    ) -> SendResult abst;

    @abstractmethod
    async def get_replies(limit: int = 50) -> list[InboundMessage] abst;

    def confirm_read {}

    @abstractmethod
    async def test_connection -> tuple[bool, str] abst;
}

def get_mail_provider(config: any, env: any) -> MailProvider | None {
    found = _PROVIDER_CLASSES.get((config.channels.email.provider or "").strip().lower());
    if found is None {
        return None;
    }
    (module, cls) = found;
    return getattr(importlib.import_module(f"sellbird.integrations.{module}"), cls)(config, env);
}

def compose(
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

def read_token_file(path: any, label: str, log: any) -> builtins.dict | None {
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

def write_token_file(path: any, data: builtins.dict) {
    path.parent.mkdir(parents=True, exist_ok=True);
    path.write_text(json.dumps(data, indent=2), encoding="utf-8");
    try {
        path.chmod(0o600);
    } except OSError {}
}

def loopback_code(
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
