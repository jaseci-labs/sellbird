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

def identity_from_config(config: any) -> MailIdentity;

class TokenSource(Protocol) {
    def load -> builtins.dict | None abst;
    def save(data: builtins.dict) -> None abst;
}

def missing_token_text(tokens: any, main_mailbox_text: str) -> str;

def save_if_signed_in_as(
    record: builtins.dict,
    expected_address: str | None,
    read_address: Callable[[], str],
    save: Callable[[builtins.dict], None],
) -> bool;

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

def _unquoted(text: str) -> str;

def strip_quoted_reply(body: str) -> str;

def looks_like_bounce(from_email: str, subject: str) -> bool;

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

    def confirm_read;

    @abstractmethod
    async def test_connection -> tuple[bool, str] abst;
}

def get_mail_provider(config: any, env: any) -> MailProvider | None;
def compose(
    to_email: str,
    sender: str,
    subject: str,
    body: str,
    sig: any,
    headers: any,
    in_reply_to: str,
    message_id: str = "",
) -> EmailMessage;
def read_token_file(path: any, label: str, log: any) -> builtins.dict | None;
def write_token_file(path: any, data: builtins.dict);
def loopback_code(
    auth_url: str,
    state: str,
    signer: str,
    service: str,
    servers: list[any],
    port: int,
    error_keys: tuple[str, ...],
) -> builtins.dict | None;
