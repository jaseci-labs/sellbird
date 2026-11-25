import asyncio;
import logging;
import random;
import httpx;

glob logger = logging.getLogger("sellbird.instantly"),
     BASE_URL = "https://api.instantly.ai/api/v2",
     MAX_RETRIES = 4,
     BACKOFF_BASE = 1.0,
     BACKOFF_CAP = 30.0,
     RETRYABLE_STATUS = {429, 500, 502, 503, 504},
     TIMEOUT = httpx.Timeout(connect=10.0, read=30.0, write=30.0, pool=10.0);

class InstantlyClient {
    has api_key: str = "",
        headers: dict[str, str] = {};

    def init(api_key: str);
    def _redact(text: str) -> str;
    static def _retry_delay(attempt: int, response: any) -> float;
    async def _request(
        method: str,
        endpoint: str,
        data: dict[str, any] | None = None,
        params: dict[str, any] | None = None,
    ) -> any;
    static def _extract_items(result: any) -> list[any];

    async def _post(endpoint: str, body: dict[str, any] | None = None) -> dict[str, any] | None;
    async def create_campaign(name: str) -> dict[str, any] | None;
    async def activate_campaign(campaign_id: str) -> dict[str, any] | None;
    async def set_campaign_emails(
        campaign_id: str, sequences: list[dict[str, any]]
    ) -> dict[str, any] | None;
    async def add_leads(campaign_id: str, leads: list[dict[str, any]]) -> dict[str, any] | None;
    async def get_replies(campaign_id: str | None = None) -> list[any];
    async def send_reply(reply_to_uuid: str, body: str) -> dict[str, any] | None;
}
