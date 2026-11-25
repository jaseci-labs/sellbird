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

def _public_address(value: str) -> str;

class PublicHTTPTransport(httpx.AsyncBaseTransport) {
    has _transport: any = None;

    def init;

    async def handle_async_request(request: any) -> any;

    async def aclose;
}

def public_http_client(*, timeout: any = 15.0, headers: dict[str, str] | None = None) -> any;
