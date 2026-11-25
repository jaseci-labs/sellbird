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

    def public -> builtins.dict {
        data = asdict(self);
        data.pop("password");
        return data;
    }
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
    ) {
        self.config = config;
        self.identity = identity or identity_from_config(config);
        (host, port, user, password, imap_host, imap_port, imap_user, imap_pass) = (
            (
                smtp.host,
                smtp.port,
                smtp.username,
                smtp.password,
                smtp.imap_host,
                smtp.imap_port,
                "",
                "",
            )
                if smtp is not None
                else [
                    getattr(env, key, "")
                    for key in "smtp_host smtp_port smtp_username smtp_password imap_host imap_port imap_username imap_password".split()
                ]
        );
        (self.smtp_host, self.smtp_user, self.smtp_pass) = (host, user, password);
        self.smtp_port = builtins.int(port or 587);
        self.imap_host = imap_host or host;
        self.imap_port = builtins.int(imap_port or 993);
        self.imap_user = imap_user or user;
        self.imap_pass = imap_pass or password;
    }

    def is_configured -> bool {
        return bool(self.smtp_host and self.smtp_user and self.smtp_pass);
    }

    async def send_email(
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
        address = self.identity.address or self.smtp_user;
        message_id = make_msgid(domain=address.split("@")[-1]);
        sender = formataddr((self.identity.display_name, address));
        msg = compose(to_email, sender, subject, body, sig, headers, in_reply_to, message_id);
        try {
            await aiosmtplib.send(
                msg, username=self.smtp_user, password=self.smtp_pass, **self._server(30)
            );
        } except Exception as e {
            logger.error(f"SMTP send failed to {to_email}: {e}");
            definite = isinstance(e, _DEFINITE_SMTP_ERRORS);
            return SendResult(ok=False, error=str(e)[:300], uncertain=not definite);
        }
        return SendResult(ok=True, message_id=message_id, thread_ref=message_id);
    }

    async def get_replies(limit: int = 50) -> list[InboundMessage] {
        try {
            return await asyncio.get_event_loop().run_in_executor(None, self._fetch_unseen, limit);
        } except Exception as e {
            logger.error(f"IMAP fetch failed: {e}");
            return [];
        }
    }

    def _server(timeout: int) -> builtins.dict {
        tls = {"start_tls": self.smtp_port == 587, "use_tls": self.smtp_port == 465};
        return {"hostname": self.smtp_host, "port": self.smtp_port, "timeout": timeout, **tls};
    }

    def _imap(work: any) -> any {
        conn = imaplib.IMAP4_SSL(self.imap_host, self.imap_port);
        try {
            conn.login(self.imap_user, self.imap_pass);
            return work(conn);
        } finally {
            try {
                conn.logout();
            } except Exception {}
        }
    }

    def _fetch_unseen(limit: int) -> list[InboundMessage] {
        def fetch(conn: any) -> list[InboundMessage] {
            conn.select("INBOX");
            (status, data) = conn.search(None, "UNSEEN");
            if status != "OK" {
                return [];
            }
            out: list[InboundMessage | None] = [];
            for msg_id in data[0].split()[-limit:] {
                (status, parts) = conn.fetch(msg_id, "(RFC822)");
                if status == "OK" and parts and isinstance(parts[0], tuple) {
                    out.append(SmtpImapProvider._parse_rfc822(parts[0][1]));
                }
            }
            return [m for m in out if m];
        }
        return self._imap(fetch);
    }

    static def _parse_rfc822(raw: bytes) -> InboundMessage | None {
        try {
            msg = email.message_from_bytes(raw, policy=email.policy.default);
        } except Exception {
            return None;
        }
        from_email = parseaddr(str(msg.get("From", "")))[1].lower();
        if not from_email {
            return None;
        }
        subject = str(msg.get("Subject", ""));
        body = "";
        try {
            part = msg.get_body(preferencelist=("plain", "html"));
            if part is not None {
                body = part.get_content();
                if part.get_content_type() == "text/html" {
                    body = re.sub("<[^>]+>", " ", body);
                }
            }
        } except Exception {}
        message_id = str(msg.get("Message-ID", "")).strip();
        in_reply_to = str(msg.get("In-Reply-To", "")).strip();
        auto = {n.lower(): str(msg.get(n, "")) for n in _AUTO_REPLY_HEADERS if msg.get(n)};
        return InboundMessage(
            provider_id=message_id or f"{from_email}:{subject}",
            from_email=from_email,
            subject=subject,
            body=(body or "")[:5000],
            message_id=message_id,
            in_reply_to=in_reply_to,
            thread_ref=in_reply_to,
            date=str(msg.get("Date", "")),
            is_bounce=looks_like_bounce(from_email, subject),
            headers=auto,
        );
    }

    async def test_connection -> tuple[bool, str] {
        if not self.is_configured() {
            return (False, "SMTP_HOST / SMTP_USERNAME / SMTP_PASSWORD missing from .env");
        }
        try {
            smtp = aiosmtplib.SMTP(**self._server(15));
            await smtp.connect();
            await smtp.login(self.smtp_user, self.smtp_pass);
            await smtp.quit();
        } except Exception as e {
            return (False, f"SMTP login failed: {str(e)[:200]}");
        }
        try {
            await asyncio.get_event_loop().run_in_executor(None, self._imap, lambda (conn: any) {});
        } except Exception as e {
            return (False, f"SMTP OK but IMAP login failed: {str(e)[:200]}");
        }
        return (True, f"SMTP + IMAP connected as {self.smtp_user}");
    }
}
