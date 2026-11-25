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

    def init(email: str, password: str) {
        self.email = email;
        self.password = password;
        self._activity = self._load_activity();
    }

    static def _load_activity -> dict[str, any] {
        today = date.today().isoformat();
        try {
            text = ACTIVITY_PATH.read_text(encoding="utf-8") if ACTIVITY_PATH.exists() else "{}";
            data = json.loads(text);
            if isinstance(data, dict) and data.get("date") == today {
                return {
                    "date": today,
                    "search_pages": int(data.get("search_pages", 0)),
                    "profile_views": int(data.get("profile_views", 0)),
                };
            }
        } except (ValueError, OSError) as e {
            logger.debug(f"Could not load LinkedIn activity log: {e}");
        }
        return {"date": today, "search_pages": 0, "profile_views": 0};
    }

    def _count(kind: str) -> int {
        today = date.today().isoformat();
        if self._activity.get("date") != today {
            self._activity = {"date": today, "search_pages": 0, "profile_views": 0};
        }
        return self._activity.get(kind, 0);
    }

    async def _random_delay(min_s: float = 2.0, max_s: float = 6.0) {
        delay = random.uniform(min_s, max_s);
        if random.random() < 0.10 {
            delay += random.uniform(4.0, 10.0);
        }
        await asyncio.sleep(delay);
    }

    async def _wait_settled(timeout: int = 15000) {
        try {
            await self.page.wait_for_load_state("networkidle", timeout=timeout);
        } except Exception {}
    }

    async def start {
        self._pw = await importlib.import_module("playwright.async_api").async_playwright().start();
        self.browser = await self._pw.chromium.launch(headless=True);
        self.context = await self.browser.new_context(
            viewport={"width": 1280, "height": 800}, user_agent=USER_AGENT
        );
        try {
            cookies = json.loads(COOKIES_PATH.read_text(encoding="utf-8"))
                if COOKIES_PATH.exists()
                else None;
            if isinstance(cookies, list) {
                await self.context.add_cookies(cookies);
                logger.info("Loaded saved LinkedIn cookies.");
            }
        } except Exception as e {
            logger.warning(f"Could not load saved LinkedIn cookies: {e}");
        }
        self.page = await self.context.new_page();
    }

    def _save_cookies_sync(cookies: list[any]) {
        try {
            COOKIES_PATH.parent.mkdir(parents=True, exist_ok=True);
            COOKIES_PATH.write_text(json.dumps(cookies), encoding="utf-8");
            try {
                COOKIES_PATH.chmod(0o600);
            } except OSError {}
        } except OSError as e {
            logger.warning(f"Could not save LinkedIn cookies: {e}");
        }
    }

    async def stop {
        try {
            if self.context {
                self._save_cookies_sync(await self.context.cookies());
                logger.info("Saved LinkedIn cookies.");
            }
        } except Exception as e {
            logger.debug(f"Could not save cookies on shutdown: {e}");
        }
        try {
            if self.browser {
                await self.browser.close();
            }
        } except Exception as e {
            logger.debug(f"Error closing browser: {e}");
        } finally {
            self.browser = self.context = self.page = None;
        }
        try {
            if self._pw {
                await self._pw.stop();
            }
        } except Exception as e {
            logger.debug(f"Error stopping Playwright: {e}");
        } finally {
            self._pw = None;
        }
    }

    async def login -> bool {
        if not self.page {
            await self.start();
        }
        if not self.email or not self.password {
            logger.warning("LinkedIn credentials not configured; cannot log in.");
            return False;
        }
        try {
            await self.page.goto("https://www.linkedin.com/login", timeout=30000);
            await self._wait_settled();
        } except Exception as e {
            logger.error(f"Could not load LinkedIn login page: {e}");
            return False;
        }
        await self._random_delay(1, 3);
        if "feed" in self.page.url or "mynetwork" in self.page.url {
            logger.info("Already logged into LinkedIn.");
            return True;
        }
        try {
            for (selector, value) in (("#username", self.email), ("#password", self.password)) {
                await self.page.fill(selector, value);
                await self._random_delay(0.5, 1.5);
            }
            await self.page.click('button[type="submit"]');
            await self._wait_settled();
            if "feed" in self.page.url or "mynetwork" in self.page.url {
                logger.info("Successfully logged into LinkedIn.");
                self._save_cookies_sync(await self.context.cookies());
                return True;
            }
            checkpoint = "checkpoint" in self.page.url or "challenge" in self.page.url;
            logger.warning(
                "LinkedIn security checkpoint detected. Please log in manually and save cookies."
                    if checkpoint
                    else f"Login may have failed. Current URL: {self.page.url}",
            );
            return False;
        } except Exception as e {
            msg = str(e).replace(self.password, "***") if self.password else str(e);
            logger.error(f"LinkedIn login failed: {msg}");
            return False;
        }
    }

    async def search_people(
        keywords: str = "",
        title: str = "",
        company: str = "",
        location: str = "",
        max_results: int = 25,
    ) -> list[dict[str, any]] {
        if not self.page and not (await self.start() or await self.login()) {
            return [];
        }
        terms = " ".join([t for t in [keywords, title, company, location] if t]).strip();
        if not terms {
            logger.warning("search_people called with no criteria; skipping.");
            return [];
        }
        search_url = f"https://www.linkedin.com/search/results/people/?keywords={quote_plus(terms)}";
        results: list[dict[str, any]] = [];
        for page_num in range(1, MAX_SEARCH_PAGES_PER_QUERY + 1) {
            if len(results) >= max_results {
                break;
            }
            if self._count("search_pages") >= MAX_DAILY_SEARCH_PAGES {
                logger.warning(
                    f"LinkedIn daily cap reached for search_pages ({MAX_DAILY_SEARCH_PAGES}/day). Skipping to protect the account.",
                );
                break;
            }
            try {
                await self.page.goto(f"{search_url}&page={page_num}", timeout=30000);
            } except Exception as e {
                logger.warning(f"Failed to load search page {page_num}: {e}");
                break;
            }
            self._activity["search_pages"] = self._count("search_pages") + 1;
            try {
                ACTIVITY_PATH.parent.mkdir(parents=True, exist_ok=True);
                ACTIVITY_PATH.write_text(json.dumps(self._activity), encoding="utf-8");
            } except OSError as e {
                logger.debug(f"Could not save LinkedIn activity log: {e}");
            }
            await self._random_delay(3, 6);
            await self._wait_settled();
            try {
                for _ in range(random.randint(2, 4)) {
                    await self.page.mouse.wheel(0, random.randint(250, 700));
                    await asyncio.sleep(random.uniform(0.4, 1.4));
                }
            } except Exception as e {
                logger.debug(f"Scroll simulation failed: {e}");
            }
            cards = await self.page.query_selector_all("div.entity-result__item")
                or await self.page.query_selector_all("li.reusable-search__result-container");
            if not cards {
                logger.info(f"No results found on page {page_num}.");
                break;
            }
            for card in cards {
                if len(results) >= max_results {
                    break;
                }
                try {
                    profile = await self._extract_search_card(card);
                    if profile {
                        results.append(profile);
                    }
                } except Exception as e {
                    logger.debug(f"Error extracting search card: {e}");
                }
            }
            await self._random_delay(4, 8);
        }
        logger.info(f"Found {len(results)} LinkedIn profiles.");
        return results;
    }

    async def _extract_search_card(card: any) -> dict[str, any] | None {
        link_el = await card.query_selector("a.app-aware-link");
        href = (await link_el.get_attribute("href")) if link_el else None;
        if not href or "/in/" not in href {
            return None;
        }
        texts: list[str] = [];
        for selector in (
            "span.entity-result__title-text a span",
            "div.entity-result__primary-subtitle",
            "div.entity-result__secondary-subtitle",
        ) {
            el = await card.query_selector(selector);
            texts.append(((await el.inner_text()) if el else "").strip());
        }
        (name, title_text, location) = texts;
        (first_name, _, last_name) = name.partition(" ");
        (title_text, sep, company) = title_text.partition(" at ");
        return {
            "first_name": first_name,
            "last_name": last_name,
            "title": title_text.strip() if sep else title_text,
            "company": company.strip(),
            "linkedin_url": href.split("?")[0],
            "location": location,
        };
    }
}
