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

    def init(api_key: str) {
        self.api_key = api_key or "";
        self.headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        };
    }

    def _redact(text: str) -> str {
        return text.replace(self.api_key, "***REDACTED***")
            if self.api_key and text
            else text or "";
    }

    static def _retry_delay(attempt: int, response: any) -> float {
        retry_after = response.headers.get("Retry-After") if response is not None else None;
        if retry_after {
            try {
                return min(float(retry_after), BACKOFF_CAP) + random.uniform(0, 1);
            } except ValueError {}
        }
        return min(BACKOFF_BASE * (2 ** attempt), BACKOFF_CAP) * random.uniform(0.5, 1.5);
    }

    async def _request(
        method: str,
        endpoint: str,
        data: dict[str, any] | None = None,
        params: dict[str, any] | None = None,
    ) -> any {
        if not self.api_key {
            logger.error("Instantly API key is not configured.");
            return None;
        }
        url = f"{BASE_URL}/{endpoint.lstrip('/')}";
        where = f"{method} {endpoint}";
        async with httpx.AsyncClient(timeout=TIMEOUT) as client {
            for attempt in range(MAX_RETRIES + 1) {
                retry = f"Retry {attempt + 1}/{MAX_RETRIES}";
                try {
                    response = await client.request(
                        method, url, headers=self.headers, json=data, params=params
                    );
                } except httpx.HTTPError as e {
                    if attempt < MAX_RETRIES {
                        delay = InstantlyClient._retry_delay(attempt, None);
                        logger.warning(
                            f"Instantly request error ({where}): {self._redact(str(e))}. {retry} in {delay:.1f}s.",
                        );
                        await asyncio.sleep(delay);
                        continue;
                    }
                    logger.error(
                        f"Instantly request failed after {MAX_RETRIES} retries ({where}): {self._redact(str(e))}",
                    );
                    return None;
                }
                status = response.status_code;
                if status in RETRYABLE_STATUS {
                    if attempt < MAX_RETRIES {
                        delay = InstantlyClient._retry_delay(attempt, response);
                        label = "rate limited (429)"
                            if status == 429
                            else f"server error ({status})";
                        logger.warning(f"Instantly {label} on {where}. {retry} in {delay:.1f}s.");
                        await asyncio.sleep(delay);
                        continue;
                    }
                    logger.error(
                        f"Instantly API error {status} on {where} after {MAX_RETRIES} retries: {self._redact(response.text[:500])}",
                    );
                    return None;
                }
                if status >= 400 {
                    logger.error(
                        f"Instantly API error {status} on {where}: {self._redact(response.text[:500])}",
                    );
                    return None;
                }
                if status == 204 or not response.content {
                    return {};
                }
                try {
                    payload = response.json();
                } except ValueError {
                    logger.error(
                        f"Instantly returned non-JSON response on {where}: {self._redact(response.text[:200])}",
                    );
                    return None;
                }
                if isinstance(payload, (dict, list)) {
                    return payload;
                }
                logger.error(
                    f"Instantly returned unexpected JSON type ({type(payload).__name__}) on {where}.",
                );
                return None;
            }
        }
        return None;
    }

    static def _extract_items(result: any) -> list[any] {
        if isinstance(result, list) {
            return result;
        }
        items = (result.get("items") or result.get("data")) if isinstance(result, dict) else None;
        return items if isinstance(items, list) else [];
    }

    async def _post(endpoint: str, body: dict[str, any] | None = None) -> dict[str, any] | None {
        result = await self._request("POST", endpoint, body);
        return result if isinstance(result, dict) else None;
    }

    async def create_campaign(name: str) -> dict[str, any] | None {
        result = await self._post("/campaigns", {"name": name, "stop_for_company": True});
        if result is not None {
            logger.info(f"Created campaign: {name} (id={result.get('id')})");
        }
        return result;
    }

    async def activate_campaign(campaign_id: str) -> dict[str, any] | None {
        return await self._post(f"/campaigns/{campaign_id}/activate");
    }

    async def set_campaign_emails(
        campaign_id: str, sequences: list[dict[str, any]]
    ) -> dict[str, any] | None {
        return await self._post(f"/campaigns/{campaign_id}/emails", {"sequences": [sequences]});
    }

    async def add_leads(campaign_id: str, leads: list[dict[str, any]]) -> dict[str, any] | None {
        if not leads {
            logger.warning("add_leads called with an empty lead list; skipping.");
            return {};
        }
        return await self._post("/leads", {"campaign_id": campaign_id, "leads": leads});
    }

    async def get_replies(campaign_id: str | None = None) -> list[any] {
        params: dict[str, any] | None = {"campaign_id": campaign_id} if campaign_id else None;
        return InstantlyClient._extract_items(
            await self._request("GET", "/emails/replies", params=params)
        );
    }

    async def send_reply(reply_to_uuid: str, body: str) -> dict[str, any] | None {
        return await self._post("/emails/reply", {"reply_to_uuid": reply_to_uuid, "body": body});
    }
}
