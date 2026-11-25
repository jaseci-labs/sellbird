import asyncio;
import copy;
import logging;
import os;
import shutil;
import sys;
import time;
import httpx;
import yaml;
import from pathlib { Path }
import from urllib.parse { urljoin, urlparse }
import from bs4 { BeautifulSoup }
import from dotenv { load_dotenv }

glob logger = logging.getLogger("sellbird.trainer"),
     MAX_OBJECTION_ATTEMPTS = 3,
     FALLBACK_PATHS = "/ /about /about-us /pricing /features /product /products /solutions /services /how-it-works /why-us /case-studies /customers /testimonials /faq /contact /team /our-team /blog /resources /integrations".split(),
     CF_API_BASE = "https://api.cloudflare.com/client/v4/accounts",
     CRAWL_TIMEOUT = 600,
     POLL_INTERVAL = 10,
     _CRAWL_ENDED = ("completed", "cancelled_due_to_timeout", "cancelled_due_to_limits"),
     _NOISE_TAGS = ["script", "style", "nav", "footer", "noscript", "iframe"],
     _FILE_EXTENSIONS = (".pdf", ".zip", ".png", ".jpg", ".svg", ".css", ".js"),
     _USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
     LEARNED_FIELDS = {
         "persona": ("company",),
         "product": ("name", "description", "pricing", "key_benefits", "objection_responses"),
         "icp": ("industries", "company_size", "titles", "geography"),
     },
     UNTRAINED_COMPANY = "Your Company",
     _RULE = "=" * 60,
     _BUY_WHEN = "When these events happen, prospects are most likely to buy:",
     _INSTEAD = "What prospects do instead of buying a solution like ours:",
     _BAD_URL = "\nERROR: '{}' doesn't look like a valid URL.\nTry something like: https://yourcompany.com",
     _NO_CLOUDFLARE = "[1/6] Crawling website (add CLOUDFLARE_ACCOUNT_ID and\n      CLOUDFLARE_API_TOKEN to .env for deep JS-rendered crawling)...",
     _PRIVATE_SITE = "\nERROR: {} points to a local or private address. Sellbird only\nlearns from public websites, so it never reaches into your own network.\nTrain on the live public site instead.",
     _NO_PLAYBOOK = "\nERROR: Could not generate a valid objection playbook.\nTraining stopped. Existing configuration was not modified.",
     _NEXT_OFFER = "\n  Next: work out the offer every first email ends with. Ask your coding agent\n  to work it out with you, or open the dashboard's Your company tab.",
     _REVIEW_GUESSED = "\n  Review {} and adjust as needed — especially the\n  persona name/email, which I guessed from your domain.",
     _REVIEW_KEPT = "\n  Review {} and adjust as needed. Emails still go out as\n  {} <{}>.",
     _DEFAULT_TONE = "professional, consultative, confident",
     _KNOWLEDGE = [
         ("What We Sell", "p", "product_description", ""),
         ("Core Value Proposition", "p", "value_proposition", ""),
         ("Key Benefits", "p", "key_benefits", None),
         ("Features", "p", "features", None),
         ("Use Cases", "p", "use_cases", None),
         ("Pricing", "p", "pricing", "Contact for pricing"),
         ("Target Audience", "p", "target_audience", ""),
         ("Ideal Buyer Persona", "i", "buyer_persona", ""),
         ("Integrations", "p", "integrations", None),
         ("What Makes Us Different", "p", "differentiators", None),
         ("Social Proof & Case Studies", "p", "social_proof", None),
         ("Prospect Pain Points", "i", "pain_points", None),
         ("Buying Triggers\n" + _BUY_WHEN, "i", "buying_triggers", None),
         ("Disqualifiers\nDo NOT pursue prospects who:", "i", "disqualifiers", None),
         ("Market Positioning", "c", "positioning", ""),
         ("Tone & Voice", "p", "tone", _DEFAULT_TONE),
     ],
     _BATTLE_CARDS = [
         ("Market Positioning", "c", "positioning", ""),
         ("Our Unique Strengths", "c", "unique_strengths", None),
         ("Common Alternatives (Non-Competitors)\n" + _INSTEAD, "c", "common_alternatives", None),
     ],
     _OBJECTIONS_RETRY = """

IMPORTANT: Your previous response was invalid or empty.
Return a NON-EMPTY JSON object containing objection strings as keys
and non-empty consultative response strings as values.
Do not return an empty object, markdown, or explanations.
""",
     _USAGE = """Usage: python -m sellbird.trainer <website-url> [max-pages]

Examples:
  python -m sellbird.trainer https://acmecorp.com
  python -m sellbird.trainer https://acmecorp.com 200

For deep JS-rendered crawling, add to .env:
  CLOUDFLARE_ACCOUNT_ID=your_account_id
  CLOUDFLARE_API_TOKEN=your_api_token

Without Cloudflare credentials, Sellbird will use basic HTTP
scraping (no JavaScript rendering, limited page discovery).""";

def _normalize_start_url(url: str) -> str;

class CloudflareCrawler {
    has account_id: str = "",
        api_token: str = "",
        base_url: str = "",
        headers: dict[str, str] = {};

    def init(account_id: str, api_token: str);

    async def crawl(
        url: str, max_pages: int = 100, depth: int = 5, render: bool = True
    ) -> dict[str, str];

    async def _poll_job(client: any, job_id: str) -> dict[str, str];

    async def _collect_results(client: any, job_id: str) -> dict[str, str];
}

class FallbackCrawler {
    has blocked: bool = False;

    async def crawl(base_url: str, max_pages: int = 100) -> dict[str, str];

    async def _fetch_page(client: any, url: str) -> tuple[str, str];

    def _extract_links(html: str, base_url: str, domain: str) -> list[str];

    def _normalize_url(url: str) -> str;
}

def brain_section(brain_config: BrainConfig) -> dict[str, any];

def _persona_untrained(persona: any) -> bool;

def merge_trained_config(learned: any, existing: any) -> any;

def _offer_from(product_info: any) -> dict[str, any];

def _backup(path: Path, raw: str) -> Path;

def write_trained_config(learned: any, path: any) -> any;

def _bullets(items: any) -> str;

def _sections(spec: list[any], sources: any) -> str;

class Trainer {
    has brain_config: any = None,
        state: any = None,
        brain: any = None,
        scraped_pages: dict[str, str] = {};

    def init(brain_config: BrainConfig | None = None);

    async def train(
        url: str, output_path: str = "sellbird.local.yaml", max_pages: int = 100
    ) -> any;

    def _get_all_content(max_chars: int = 60000) -> str;

    async def _ask_json(prompt: str, fallback: dict[str, any]) -> any;

    async def _extract_product_info -> any;

    async def _extract_icp -> any;

    async def _extract_competitive_intel(product_info: any) -> any;

    async def _generate_objections(product_info: any, competitive_intel: any) -> dict[str, str]
        | None;

    async def _generate_product_knowledge(product_info: any, icp_info: any, competitive_intel: any);

    async def _generate_battle_cards(product_info: any, competitive_intel: any);

    def _build_config(
        product_info: any, icp_info: any, objections: any, domain: str
    ) -> dict[str, any];
}

def _joined(items: any) -> str;

def _nonblank_pair(pair: any) -> bool;

def _playbook(result: any) -> dict[str, str] | None;

def _battle_card(comp: any, product_name: str) -> str;

async def run_training(url: str, output: str = "sellbird.local.yaml", max_pages: int = 100);

def main;

with entry:__main__ {
    utf8_stdio();
    main();
}
