import asyncio;
import ipaddress;
import socket;
import httpx;
import from time { monotonic }

glob _NETS = "64:ff9b::/96 64:ff9b:1::/48",
     _TRANSLATION_NETWORKS = tuple(map(ipaddress.ip_network, _NETS.split())),
     _NOT_PUBLIC = "is_multicast is_reserved is_unspecified".split(),
     _TRANSLATED = "is_site_local ipv4_mapped sixtofour teredo".split();

class UnsafeURLError(httpx.RequestError, Exception) {}

def _public_address(value: str) -> str {
    if "%" in value {
        raise ValueError("Scoped addresses are not public website targets");
    }
    address = ipaddress.ip_address(value);
    if not address.is_global or any(getattr(address, flag) for flag in _NOT_PUBLIC) {
        raise ValueError("Address is not public");
    }
    if isinstance(address, ipaddress.IPv6Address) {
        translated = any(address in network for network in _TRANSLATION_NETWORKS);
        if translated or any(getattr(address, flag) for flag in _TRANSLATED) {
            raise ValueError("Translated IPv6 addresses are not supported");
        }
    }
    return str(address);
}

class PublicHTTPTransport(httpx.AsyncBaseTransport) {
    has _transport: any = None;

    def init {
        self._transport = httpx.AsyncHTTPTransport(
            trust_env=False, limits=httpx.Limits(max_keepalive_connections=0)
        );
    }

    async def handle_async_request(request: any) -> any {
        url = request.url;
        host = url.raw_host.decode("ascii");
        bad_host = not host or "%" in host or f".{host.rstrip('.').lower()}".endswith(".localhost");
        if url.scheme not in {"http", "https"} or bad_host or url.username or url.password {
            raise UnsafeURLError("Only public HTTP(S) websites are allowed", request=request);
        }
        port = url.port if url.port is not None else (443 if url.scheme == "https" else 80);
        if port < 1 or port > 65535 {
            raise UnsafeURLError("Invalid website port", request=request);
        }
        timeout = request.extensions.get("timeout", {}).get("connect");
        connect_budget = timeout if timeout is not None else 10.0;
        deadline = monotonic() + connect_budget;
        try {
            literal = ipaddress.ip_address(host);
        } except ValueError {
            literal = None;
        }
        try {
            if literal is not None {
                found = [host];
            } else {
                lookup = asyncio.get_running_loop().getaddrinfo(
                    host, port, type=socket.SOCK_STREAM
                );
                found = [
                    row[4][0]
                    for row in await asyncio.wait_for(lookup, timeout=connect_budget)
                ];
            }
            addresses = list(dict.fromkeys(_public_address(a) for a in found));
            if not addresses {
                raise ValueError("DNS returned no addresses");
            }
            addresses.sort(key=lambda (a: str) -> bool { return ":" in a; });
        } except ValueError as exc {
            raise UnsafeURLError(
                "Website resolves to a non-public destination", request=request
            ) from exc;
        } except asyncio.TimeoutError as exc {
            raise httpx.ConnectTimeout(
                "Website DNS resolution timed out", request=request
            ) from exc;
        } except OSError as exc {
            raise httpx.ConnectError("Website DNS resolution failed", request=request) from exc;
        }
        headers = request.headers.copy();
        headers["Host"] = url.netloc.decode("ascii");
        for (index, address) in enumerate(addresses) {
            remaining = deadline - monotonic();
            if remaining <= 0 {
                raise httpx.ConnectTimeout("Website connection budget exhausted", request=request);
            }
            timeouts = {**request.extensions.get("timeout", {}), "connect": remaining};
            extensions = {**request.extensions, "sni_hostname": host, "timeout": timeouts};
            pinned = httpx.Request(
                request.method,
                url.copy_with(host=address),
                headers=headers,
                stream=request.stream,
                extensions=extensions,
            );
            try {
                return await self._transport.handle_async_request(pinned);
            } except (httpx.ConnectError, httpx.ConnectTimeout) {
                if index == len(addresses) - 1 {
                    raise;
                }
            }
        }
    }

    async def aclose {
        await self._transport.aclose();
    }
}

def public_http_client(*, timeout: any = 15.0, headers: dict[str, str] | None = None) -> any {
    return httpx.AsyncClient(
        transport=PublicHTTPTransport(),
        trust_env=False,
        timeout=timeout,
        headers=headers,
        follow_redirects=True,
        max_redirects=10,
    );
}
