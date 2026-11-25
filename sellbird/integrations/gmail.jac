import base64;
import builtins;
import codecs;
import http.server;
import logging;
import re;
import time;
import urllib.parse;
import from collections.abc { Callable }
import from email.message { Message }
import from email.utils { formataddr, parseaddr }
import httpx;

glob logger: any = logging.getLogger("sellbird.gmail"),
     TOKEN_FILE: any = PROJECT_ROOT / "data" / "gmail_token.json",
     API_BASE: str = "https://gmail.googleapis.com/gmail/v1/users/me",
     TOKEN_URL: str = "https://oauth2.googleapis.com/token",
     AUTH_URL: str = "https://accounts.google.com/o/oauth2/v2/auth",
     SCOPE: str = "https://www.googleapis.com/auth/gmail.modify",
     LOOPBACK_PORT: int = 8765,
     MAX_INBOX_PAGES: int = 40,
     FULL_READ_EVERY_SECONDS: int = 24 * 3600,
     _NOT_REPLIES: frozenset[str] = frozenset("SENT DRAFT SPAM TRASH".split()),
     _NOT_MAIL_CHARSETS: frozenset[str] = frozenset(
         "punycode idna utf_7 unicode_escape raw_unicode_escape".split()
     ),
     MAX_DECODE_BYTES: int = 200000,
     _GONE: any = builtins.object(),
     TIMEOUT: any = httpx.Timeout(connect=10.0, read=30.0, write=30.0, pool=10.0);

class GmailError(RuntimeError) {}

def _entry_id(change: any, page: int) -> str;
def _next_page(data: builtins.dict, seen: set[str], where: str) -> str | None;
def _load_token -> builtins.dict | None;
def _save_token(data: builtins.dict);

class GmailProvider(MailProvider) {
    static has name: str = "gmail",
               carries_headers: bool = True;

    def init(
        config: any,
        env: any,
        transport: any = None,
        *,
        identity: MailIdentity | None = None,
        tokens: dyn TokenSource | None = None,
    );
    def _load -> builtins.dict | None;
    def _client -> httpx.AsyncClient;
    def is_configured -> bool;
    async def _token -> str | None;
    async def _request(
        method: str, path: str, *, sending: bool = False, not_found: any = None, **kwargs: any
    ) -> any;
    async def send_email(
        to_email: str,
        subject: str,
        body: str,
        thread_ref: str = "",
        in_reply_to: str = "",
        headers: any = (),
    ) -> SendResult;
    async def get_replies(limit: int = 500) -> list[InboundMessage];
    def confirm_read;
    async def _current_history_id -> str | None;
    async def _fetch(msg_id: str, where: str) -> any;
    async def _read_history(start: str) -> any;
    async def _read_week(limit: int, prune: bool = True) -> list[InboundMessage];
    static def _parse_message(data: builtins.dict) -> InboundMessage | None;
    static def _extract_text(payload: builtins.dict) -> str;
    async def test_connection -> tuple[bool, str];
}

def authorized_address(access_token: str, transport: any = None) -> str;
def run_auth_flow(
    client_id: str,
    client_secret: str,
    *,
    save: Callable[[builtins.dict], None] | None = None,
    expected_address: str | None = None,
) -> bool;
