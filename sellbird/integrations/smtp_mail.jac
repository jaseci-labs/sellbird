import asyncio;
import builtins;
import email;
import email.policy;
import imaplib;
import logging;
import re;
import from dataclasses { asdict, dataclass, field }
import from email.utils { formataddr, make_msgid, parseaddr }
import aiosmtplib;

glob _AUTO_REPLY_HEADERS: any = tuple(
         "Auto-Submitted X-Autoreply X-Autorespond X-Autoresponse Precedence".split()
     ),
     logger: any = logging.getLogger("sellbird.smtp"),
     _DEFINITE_SMTP_ERRORS: any = tuple(
         getattr(aiosmtplib, f"SMTP{name}")
         for name in "ConnectError ConnectTimeoutError AuthenticationError HeloError NotSupported RecipientsRefused SenderRefused DataError".split(),
     );

@dataclass
class SmtpSettings {
    has host: str,
        username: str,
        password: str = field(repr=False),
        port: int = 587,
        imap_host: str = "",
        imap_port: int = 993;

    def public -> builtins.dict;
}

class SmtpImapProvider(MailProvider) {
    static has name: str = "smtp",
               carries_headers: bool = True;

    def init(
        config: any,
        env: any,
        *,
        identity: MailIdentity | None = None,
        smtp: SmtpSettings | None = None,
    );
    def is_configured -> bool;
    async def send_email(
        to_email: str,
        subject: str,
        body: str,
        thread_ref: str = "",
        in_reply_to: str = "",
        headers: any = (),
    ) -> SendResult;
    async def get_replies(limit: int = 50) -> list[InboundMessage];
    def _server(timeout: int) -> builtins.dict;
    def _imap(work: any) -> any;
    def _fetch_unseen(limit: int) -> list[InboundMessage];
    static def _parse_rfc822(raw: bytes) -> InboundMessage | None;
    async def test_connection -> tuple[bool, str];
}
