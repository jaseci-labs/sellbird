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

    def init(message: str = "", uncertain: bool = False);
}

def _load_token -> builtins.dict | None;
def _save_token(data: builtins.dict);
def _token_url(tenant: str) -> str;

class MicrosoftProvider(MailProvider) {
    static has name: str = "microsoft";

    def init(
        config: any,
        env: any,
        transport: any = None,
        *,
        identity: MailIdentity | None = None,
        tokens: dyn TokenSource | None = None,
    );
    def _load -> builtins.dict | None;
    def _save(data: builtins.dict);
    def is_configured -> bool;
    def _client -> httpx.AsyncClient;
    async def _token -> str;
    async def _request(method: str, path: str, **kwargs: any) -> builtins.dict;
    async def _request_url(
        method: str,
        url: str,
        *,
        headers: any = None,
        retry_503: bool = True,
        any_2xx_ok: bool = False,
        **kwargs: any,
    ) -> builtins.dict;
    async def _my_address -> str;
    async def _check_identity -> str;
    async def send_email(
        to_email: str,
        subject: str,
        body: str,
        thread_ref: str = "",
        in_reply_to: str = "",
        headers: any = (),
    ) -> SendResult;
    async def _delete_draft(draft_id: str);
    async def get_replies(limit: int = 50) -> list[InboundMessage];
    static def _parse_message(item: any) -> InboundMessage | None;
    async def test_connection -> tuple[bool, str];
}

def _checked_next_link(link: any) -> str;
def _pkce_pair -> tuple[str, str];

class _LoopbackServer(http.server.HTTPServer) {
    static has allow_reuse_address: bool = True;
}

class _LoopbackServerV6(_LoopbackServer) {
    static has address_family: any = socket.AF_INET6;
}

def authorized_address(access_token: str, transport: any = None) -> str;
def run_auth_flow(
    client_id: str,
    tenant: str = "",
    *,
    save: Callable[[builtins.dict], None] | None = None,
    expected_address: str | None = None,
    scope: str | None = None,
) -> bool;
