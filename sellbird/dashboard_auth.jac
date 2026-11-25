import errno;
import functools;
import hmac;
import importlib;
import ipaddress;
import json;
import operator;
import os;
import re;
import stat;
import threading;
import time;
import from pathlib { Path }

glob _stdsecrets: any = importlib.import_module("secrets"),
     TOKEN_RE = re.compile("[A-Za-z0-9_-]{43,128}"),
     _PORT_RE = re.compile(":[0-9]{1,5}"),
     _IS_WINDOWS = os.name == "nt",
     SECURITY_HEADERS = [
         (b"cache-control", b"no-store"),
         (b"referrer-policy", b"same-origin"),
         (b"x-content-type-options", b"nosniff"),
         (b"x-frame-options", b"DENY"),
         (b"cross-origin-opener-policy", b"same-origin"),
         (b"cross-origin-resource-policy", b"same-origin"),
         (
             b"content-security-policy",
             b"default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
         ),
     ],
     _SECURITY_NAMES = {h for (h, _) in SECURITY_HEADERS},
     _JSON_TYPE = (b"content-type", b"application/json"),
     _CHALLENGE = (b"www-authenticate", b'Bearer realm="sellbird"'),
     _SAME_TOKENS = "The agent token ({}) is the same as the dashboard token, so the agent would have your rights. Delete the agent token file and restart the dashboard to create a new one.",
     _UNSAFE_METHODS = set("POST PUT PATCH DELETE".split()),
     _REFUSALS = {
         "host": (400, "bad_host", "This dashboard only answers to localhost / 127.0.0.1."),
         "origin": (403, "cross_origin", "Cross-origin requests are refused."),
         "site": (403, "cross_origin", "Cross-site requests are refused."),
         "auth": (401, "unauthorized", "Open the link printed by 'sellbird dashboard' to unlock."),
         "media": (415, "unsupported_media_type", "Request bodies must be application/json."),
     };

class TokenError(Exception) {}

class _ExtraLinkError(TokenError) {}

class _WindowsReadBusyError(TokenError) {}

def _flags(names: str) -> int;

def _refused(path: any, why: str, tail: str = "", kind: any = None) -> any;

def _check_open_file(fd: int, path: any);

def _read_token(path: any) -> str | None;

def _write_and_close(fd: int, token: str);

def _publish_token(path: any, token: str);

def _read_token_settled(path: any) -> str | None;

def load_or_create_token(path: any) -> str;

obj TokenStore {
    has path: any,
        _token: str | None = None,
        _lock: any = None;

    def postinit;

    def configure(path: any);

    def _cached(load: any) -> str | None;

    def get -> str;

    def peek -> str | None;
}

def parse_host(value: str) -> str | None;

def is_loopback(host: str) -> bool;

def is_public_path(method: str, path: str) -> bool;

def bearer_ok(header_values: list[str], token: str) -> bool;

async def _send_secured(send: any, message: any);

obj DashboardGuard {
    has app: any,
        store: any,
        agent_store: any = None;

    def _refusal(scope: any) -> tuple[int, str, str] | None;

    async def __call__(scope: any, receive: any, send: any);
}
