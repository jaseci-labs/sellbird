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

def _flags(names: str) -> int {
    return functools.reduce(operator.or_, [getattr(os, n, 0) for n in names.split()], 0);
}

def _refused(path: any, why: str, tail: str = "", kind: any = None) -> any {
    return (kind or TokenError)(f"{path} {why}. Remove it and restart the dashboard{tail}.");
}

def _check_open_file(fd: int, path: any) {
    st = os.fstat(fd);
    if not stat.S_ISREG(st.st_mode) {
        raise _refused(path, "is not a regular file");
    }
    if _IS_WINDOWS {
        return;
    }
    if st.st_uid != os.geteuid() {
        raise _refused(path, "is owned by another user", " to create a new token");
    }
    if st.st_mode & 0o077 {
        why = f"is readable or writable by other users (mode {stat.S_IMODE(st.st_mode):o}), so the token may be known";
        raise _refused(path, why, " to create a new one");
    }
    if st.st_nlink != 1 {
        raise _refused(path, "has other hard links", kind=_ExtraLinkError);
    }
}

def _read_token(path: any) -> str | None {
    if _IS_WINDOWS and os.path.islink(path) {
        raise _refused(path, "is a symbolic link");
    }
    try {
        fd = os.open(path, _flags("O_RDONLY O_NOFOLLOW O_CLOEXEC O_NONBLOCK O_BINARY"));
    } except FileNotFoundError {
        return None;
    } except OSError as e {
        if e.errno in (errno.ELOOP, errno.EMLINK) {
            raise _refused(path, "is a symbolic link") from e;
        }
        busy = _IS_WINDOWS
            and (e.errno == errno.EACCES or getattr(e, "winerror", None) in (5, 32, 33));
        kind = _WindowsReadBusyError if busy else TokenError;
        raise kind(f"Can't read {path}: {e.strerror}.") from e;
    }
    try {
        _check_open_file(fd, path);
        data = os.read(fd, 4097);
    } finally {
        os.close(fd);
    }
    try {
        token: str = data.decode("ascii").strip();
    } except UnicodeDecodeError {
        token = "";
    }
    if len(data) > 4096 or not TOKEN_RE.fullmatch(token) {
        raise _refused(path, "doesn't hold a valid token", " to create a new one");
    }
    return token;
}

def _write_and_close(fd: int, token: str) {
    try {
        if not _IS_WINDOWS {
            os.fchmod(fd, 0o600);
        }
        os.write(fd, (token + "\n").encode("ascii"));
        os.fsync(fd);
    } finally {
        os.close(fd);
    }
}

def _publish_token(path: any, token: str) {
    tmp = path.with_name(f".{path.name}.{_stdsecrets.token_hex(8)}.tmp");
    flags = _flags("O_WRONLY O_CREAT O_EXCL O_NOFOLLOW O_CLOEXEC O_BINARY");
    _write_and_close(os.open(tmp, flags, 0o600), token);
    try {
        if _IS_WINDOWS {
            os.rename(tmp, path);
        } else {
            try {
                os.link(tmp, path);
            } except FileExistsError {
                raise;
            } except OSError {
                _write_and_close(os.open(path, flags, 0o600), token);
            }
        }
    } except FileExistsError {} finally {
        try {
            os.unlink(tmp);
        } except FileNotFoundError {}
    }
}

def _read_token_settled(path: any) -> str | None {
    for _ in range(50) {
        try {
            return _read_token(path);
        } except (_ExtraLinkError, _WindowsReadBusyError) {
            time.sleep(0.01);
        }
    }
    return _read_token(path);
}

def load_or_create_token(path: any) -> str {
    path = Path(path);
    try {
        path.parent.mkdir(mode=0o700, parents=True, exist_ok=True);
    } except OSError as e {
        raise TokenError(f"Can't create {path.parent}: {e.strerror}.") from e;
    }
    token = _read_token_settled(path);
    if token is None {
        try {
            _publish_token(path, _stdsecrets.token_urlsafe(32));
        } except OSError as e {
            raise TokenError(f"Can't create {path}: {e.strerror}.") from e;
        }
        token = _read_token_settled(path);
    }
    if token is None {
        raise TokenError(f"{path} disappeared while it was being created. Restart the dashboard.");
    }
    return token;
}

obj TokenStore {
    has path: any,
        _token: str | None = None,
        _lock: any = None;

    def postinit {
        self._lock = threading.Lock();
        self.configure(self.path);
    }

    def configure(path: any) {
        with self._lock {
            self.path = Path(path);
            self._token = None;
        }
    }

    def _cached(load: any) -> str | None {
        with self._lock {
            if self._token is None {
                self._token = load(self.path);
            }
            return self._token;
        }
    }

    def get -> str {
        return self._cached(load_or_create_token);
    }

    def peek -> str | None {
        return self._cached(_read_token_settled);
    }
}

def parse_host(value: str) -> str | None {
    if not value or len(value) > 262 or any(ord(c) <= 32 or ord(c) >= 127 for c in value) {
        return None;
    }
    if value.startswith("[") {
        end = value.find("]");
        (host, rest) = (value[1:end], value[end + 1:]);
        if end < 0 or not host or ":" not in host or "%" in host {
            return None;
        }
    } else {
        (host, sep, port) = value.partition(":");
        rest = sep + port;
        if not host or ":" in port {
            return None;
        }
    }
    if rest and (not _PORT_RE.fullmatch(rest) or int(rest[1:]) <= 0 or int(rest[1:]) > 65535) {
        return None;
    }
    return host.lower();
}

def is_loopback(host: str) -> bool {
    try {
        return host == "localhost" or ("%" not in host and ipaddress.ip_address(host).is_loopback);
    } except ValueError {
        return False;
    }
}

def is_public_path(method: str, path: str) -> bool {
    under_static = path.startswith("/static/")
        and all(seg not in ("", ".", "..") for seg in path[8:].split("/"));
    return method in ("GET", "HEAD") and (path in ("/", "/api/instance") or under_static);
}

def bearer_ok(header_values: list[str], token: str) -> bool {
    if len(header_values) != 1 {
        return False;
    }
    (scheme, _, presented) = header_values[0].partition(" ");
    presented_bytes = presented.strip().encode("utf-8", "replace");
    return scheme.lower() == "bearer"
        and hmac.compare_digest(presented_bytes, token.encode("ascii"));
}

async def _send_secured(send: any, message: any) {
    if message["type"] == "http.response.start" {
        old = message.get("headers", []);
        kept: list[any] = [h for h in old if h[0].lower() not in _SECURITY_NAMES];
        message = {**message, "headers": kept + SECURITY_HEADERS};
    }
    await send(message);
}

obj DashboardGuard {
    has app: any,
        store: any,
        agent_store: any = None;

    def _refusal(scope: any) -> tuple[int, str, str] | None {
        headers: dict[str, list[str]] = {};
        for (k, v) in scope.get("headers") or [] {
            headers.setdefault(k.decode("latin-1").lower(), []).append(v.decode("latin-1"));
        }
        method: str = scope.get("method", "GET").upper();
        path: str = scope.get("path", "");
        hosts = headers.get("host", []);
        host = parse_host(hosts[0]) if len(hosts) == 1 else None;
        if host is None or not is_loopback(host) {
            return _REFUSALS["host"];
        }
        fetch = (headers.get("sec-fetch-mode", [""])[0], headers.get("sec-fetch-dest", [""])[0]);
        navigation = method in ("GET", "HEAD")
            and path == "/"
            and fetch == ("navigate", "document");
        origins = [o.lower() for o in headers.get("origin", [])];
        if origins and origins != [f"http://{hosts[0].lower()}"] and not navigation {
            return _REFUSALS["origin"];
        }
        site = headers.get("sec-fetch-site", []);
        if site and site[0].lower() not in ("same-origin", "none") and not navigation {
            return _REFUSALS["site"];
        }
        if is_public_path(method, path) {
            return None;
        }
        authorization = headers.get("authorization", []);
        agent_token: str | None = None;
        try {
            token = self.store.get();
            user = bearer_ok(authorization, token);
            if user and self.agent_store is not None {
                try {
                    agent_token = self.agent_store.peek();
                } except TokenError {}
            } elif self.agent_store is not None and authorization {
                agent_token = self.agent_store.get();
            }
        } except TokenError as e {
            return (503, "token_unavailable", str(e));
        }
        if agent_token is not None
            and hmac.compare_digest(agent_token.encode("ascii"), token.encode("ascii"))
        {
            return (503, "token_unavailable", _SAME_TOKENS.format(self.agent_store.path));
        }
        agent = not user and agent_token is not None and bearer_ok(authorization, agent_token);
        if not user and not agent {
            return _REFUSALS["auth"];
        }
        scope.setdefault("state", {})["principal"] = "user" if user else "agent";
        length = headers.get("content-length", ["0"])[0].strip();
        has_body = bool(headers.get("transfer-encoding")) or length not in ("", "0");
        media = headers.get("content-type", [""])[0].split(";", 1)[0].strip().lower();
        if method in _UNSAFE_METHODS and has_body and media != "application/json" {
            return _REFUSALS["media"];
        }
        return None;
    }

    async def __call__(scope: any, receive: any, send: any) {
        if scope["type"] != "http" {
            if scope["type"] == "lifespan" {
                return await self.app(scope, receive, send);
            }
            if scope["type"] == "websocket" {
                await send({"type": "websocket.close", "code": 1008});
            }
            return;
        }
        refusal = self._refusal(scope);
        if refusal is None {
            return await self.app(scope, receive, functools.partial(_send_secured, send));
        }
        (status, code, message) = refusal;
        body = json.dumps({"error": code, "message": message}).encode();
        length = (b"content-length", str(len(body)).encode());
        hdrs = [_JSON_TYPE, length, _CHALLENGE] if status == 401 else [_JSON_TYPE, length];
        await _send_secured(
            send, {"type": "http.response.start", "status": status, "headers": hdrs}
        );
        await _send_secured(send, {"type": "http.response.body", "body": body});
    }
}
