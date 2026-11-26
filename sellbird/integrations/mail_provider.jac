import builtins;
import importlib;
import json;
import logging;
import re;
import from abc { ABC, abstractmethod }
import from collections.abc { Sequence }
import from dataclasses { dataclass, field }
import from typing { Protocol }

glob logger: any = logging.getLogger("sellbird.mail"),
     token_urlsafe: any = importlib.import_module("secrets").token_urlsafe,
     NATIVE_PROVIDERS: any = ("gmail", "smtp", "microsoft"),
     _PROVIDER_CLASSES: dict[str, str] = {
         "gmail": "gmail.GmailProvider",
         "smtp": "smtp_mail.SmtpImapProvider",
         "microsoft": "microsoft.MicrosoftProvider",
     },
     INBOX_NOT_CONNECTED: any = "This inbox isn't connected, or its saved sign-in can't be read. Connect it again.",
     BOUNCE_SENDERS: any = ("mailer-daemon", "postmaster", "mail delivery subsystem"),
     _BOUNCE_SUBJECTS = "delivery status notification|undeliverable|returned mail|delivery failure|failure notice|could not be delivered|delivery incomplete|address not found",
     BOUNCE_SUBJECTS: any = tuple(_BOUNCE_SUBJECTS.split("|")),
     _ATTRIBUTION_HEADERS: any = tuple(
         re.compile(r"^[ \t]*" + head + r"[ \t]*$", re.MULTILINE)
         for head in [
             r"On\b[^\n]{0,300}(?:\n[^\n]{0,300})?\bwrote:",
             r"El\b[^\n]{0,300}(?:\n[^\n]{0,300})?\bescribi[oó]:",
             r"Am\b[^\n]{0,300}(?:\n[^\n]{0,300})?\bschrieb[^\n]{0,100}:",
             r"Le\b[^\n]{0,300}(?:\n[^\n]{0,300})?\ba [ée]crit[ \t]*:",
         ],
     ),
     _BLOCK_HEADERS: any = (
         re.compile(r"^[ \t]*-{2,}[ \t]*Original Message[ \t]*-{2,}", re.MULTILINE | re.IGNORECASE),
         re.compile(
             r"^[ \t]*(?:_{10,}[ \t]*\n[ \t]*)?(?:From|Von|De):[^\n]*\n[ \t]*(?:Sent|Date|Gesendet|Enviado|Envoy[ée]):",
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
    email = (getattr(persona, "email", "") or "").strip();
    return MailIdentity(address=email, display_name=getattr(persona, "name", "") or "");
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
    record: builtins.dict, expected_address: str | None, read_address: any, save: any
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
        if m := pattern.search(head) {
            below = head[m.end():];
            marked = any([l.lstrip().startswith(">") for l in below.split("\n")]);
            head = head[:m.start()] + ("\n" + below if marked else "");
        }
    }
    kept = _unquoted(head).strip() or _unquoted(text).strip();
    return re.sub(r"\n{3,}", "\n\n", kept);
}

def looks_like_bounce(from_email: str, subject: str) -> bool {
    (f, s) = ((from_email or "").lower(), (subject or "").lower());
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
    (module, cls) = found.split(".");
    return getattr(importlib.import_module(f"sellbird.integrations.{module}"), cls)(config, env);
}

def compose(
    to: str, sender: str, subject: str, body: str, sig: any, headers: any, ref: str, mid: str = ""
) -> any {
    import from email.message { EmailMessage }
    import from sellbird.integrations.signature { set_body }
    msg = EmailMessage();
    for (name, value) in [("To", to), ("From", sender), ("Subject", subject), *headers] {
        msg[name] = value;
    }
    for (name, value) in [("Message-ID", mid), ("In-Reply-To", ref), ("References", ref)] {
        if value {
            msg[name] = value;
        }
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
