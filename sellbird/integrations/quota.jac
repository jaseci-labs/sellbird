import asyncio;
import json;
import logging;
import subprocess;
import sys;
import time;
import from pathlib { Path }
import httpx;

glob logger: any = logging.getLogger("sellbird.quota"),
     USAGE_URL: str = "https://api.anthropic.com/api/oauth/usage",
     OAUTH_BETA_HEADER: str = "oauth-2025-04-20",
     CACHE_TTL_OK: float = 300.0,
     CACHE_TTL_FAIL: float = 60.0,
     REQUEST_TIMEOUT: any = httpx.Timeout(connect=5.0, read=10.0, write=5.0, pool=5.0),
     KEYCHAIN_SERVICE: str = "Claude Code-credentials";

def _token_from_json_blob(blob: str) -> str | None;
def get_oauth_token -> str | None;
def _keychain_services -> list[str];
def _parse_window(value: any) -> dict[str, any] | None;

class QuotaClient {
    has _cache: dict[str, any] | None = None,
        _cache_at: float = 0.0,
        _cache_ttl: float = 0.0,
        _lock: any = None;

    def init;
    async def get_utilization -> dict[str, any] | None;
    async def _fetch -> dict[str, any] | None;
}
