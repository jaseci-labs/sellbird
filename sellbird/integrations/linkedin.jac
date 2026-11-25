import asyncio;
import importlib;
import json;
import logging;
import random;
import from datetime { date }
import from urllib.parse { quote_plus }

glob logger = logging.getLogger("sellbird.linkedin"),
     DATA_DIR = PROJECT_ROOT / "data",
     COOKIES_PATH = DATA_DIR / "linkedin_cookies.json",
     ACTIVITY_PATH = DATA_DIR / "linkedin_activity.json",
     USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
     MAX_DAILY_SEARCH_PAGES = 20,
     MAX_SEARCH_PAGES_PER_QUERY = 5;

class LinkedInAutomation {
    has email: str = "",
        password: str = "",
        browser: any = None,
        context: any = None,
        page: any = None,
        _pw: any = None,
        _activity: dict[str, any] = {};

    def init(email: str, password: str);

    static def _load_activity -> dict[str, any];

    def _count(kind: str) -> int;

    async def _random_delay(min_s: float = 2.0, max_s: float = 6.0);

    async def _wait_settled(timeout: int = 15000);

    async def start;

    def _save_cookies_sync(cookies: list[any]);

    async def stop;

    async def login -> bool;

    async def search_people(
        keywords: str = "",
        title: str = "",
        company: str = "",
        location: str = "",
        max_results: int = 25,
    ) -> list[dict[str, any]];

    async def _extract_search_card(card: any) -> dict[str, any] | None;
}
