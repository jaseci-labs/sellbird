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

def _normalize_start_url(url: str) -> str {
    url = url.strip();
    return f"https://{url}" if url and not urlparse(url).scheme else url;
}

class CloudflareCrawler {
    has account_id: str = "",
        api_token: str = "",
        base_url: str = "",
        headers: dict[str, str] = {};

    def init(account_id: str, api_token: str) {
        self.account_id = account_id;
        self.api_token = api_token;
        self.base_url = f"{CF_API_BASE}/{account_id}/browser-rendering/crawl";
        self.headers = {"Authorization": f"Bearer {api_token}", "Content-Type": "application/json"};
    }

    async def crawl(
        url: str, max_pages: int = 100, depth: int = 5, render: bool = True
    ) -> dict[str, str] {
        async with httpx.AsyncClient(timeout=60, headers=self.headers) as client {
            payload = {
                "url": url,
                "limit": max_pages,
                "depth": depth,
                "formats": ["markdown"],
                "render": render,
                "source": "all",
                "options": {"includeSubdomains": False, "includeExternalLinks": False},
                "rejectResourceTypes": ["image", "media", "font", "stylesheet"],
            };
            logger.info(f"Starting Cloudflare crawl: {url} (max {max_pages} pages)");
            resp = await client.post(self.base_url, json=payload);
            if resp.status_code != 200 {
                logger.error(f"Cloudflare crawl start failed: {resp.status_code} {resp.text}");
                return {};
            }
            result = resp.json();
            if not result.get("success") {
                logger.error(f"Cloudflare crawl error: {result}");
                return {};
            }
            job_id = result.get("result");
            if not job_id {
                logger.error("No job ID returned from Cloudflare crawl");
                return {};
            }
            logger.info(f"Crawl job started: {job_id}");
            return await self._poll_job(client, job_id);
        }
    }

    async def _poll_job(client: any, job_id: str) -> dict[str, str] {
        start_time = time.time();
        while time.time() - start_time < CRAWL_TIMEOUT {
            resp = await client.get(f"{self.base_url}/{job_id}", params={"limit": 1});
            if resp.status_code != 200 {
                logger.error(f"Poll failed: {resp.status_code}");
                break;
            }
            data = resp.json().get("result", {});
            status = data.get("status", "unknown");
            elapsed = int(time.time() - start_time);
            done = f"{data.get('finished', 0)}/{data.get('total', 0)}";
            print(f"\r      Crawling... {done} pages ({elapsed}s)", end="", flush=True);
            if status in _CRAWL_ENDED {
                print();
                if status != "completed" {
                    logger.warning(f"Crawl ended with status: {status}");
                }
                break;
            }
            if status == "errored" {
                logger.error("Crawl job errored");
                print();
                break;
            }
            await asyncio.sleep(POLL_INTERVAL);
        }
        return await self._collect_results(client, job_id);
    }

    async def _collect_results(client: any, job_id: str) -> dict[str, str] {
        pages: dict[str, str] = {};
        cursor: any = None;
        while True {
            params: dict[str, any] = {"limit": 50, "status": "completed"};
            if cursor {
                params["cursor"] = cursor;
            }
            resp = await client.get(f"{self.base_url}/{job_id}", params=params);
            if resp.status_code != 200 {
                break;
            }
            data = resp.json().get("result", {});
            for record in data.get("records", []) {
                (url, markdown) = (record.get("url", ""), record.get("markdown", ""));
                if url and markdown {
                    pages[url] = markdown;
                }
            }
            next_cursor = data.get("cursor");
            if not next_cursor or next_cursor == cursor {
                break;
            }
            cursor = next_cursor;
        }
        return pages;
    }
}

class FallbackCrawler {
    has blocked: bool = False;

    async def crawl(base_url: str, max_pages: int = 100) -> dict[str, str] {
        self.blocked = False;
        pages: dict[str, str] = {};
        visited: set[str] = set();
        domain = urlparse(base_url).netloc;
        queue: list[str] = [urljoin(base_url, p) for p in FALLBACK_PATHS];
        async with public_http_client(timeout=15, headers={"User-Agent": _USER_AGENT}) as client {
            while queue and len(pages) < max_pages {
                url = queue.pop(0);
                clean_url = self._normalize_url(url);
                if clean_url in visited {
                    continue;
                }
                visited.add(clean_url);
                (html, text) = await self._fetch_page(client, url);
                if not text {
                    continue;
                }
                pages[url] = text;
                print(f"\r      Scraped {len(pages)} pages...", end="", flush=True);
                if html {
                    for link in self._extract_links(html, base_url, domain) {
                        if self._normalize_url(link) not in visited and link not in queue {
                            queue.append(link);
                        }
                    }
                }
            }
        }
        print();
        return pages;
    }

    async def _fetch_page(client: any, url: str) -> tuple[str, str] {
        try {
            resp = await client.get(url);
            if resp.status_code != 200 or "text/html" not in resp.headers.get("content-type", "") {
                return ("", "");
            }
            raw_html = resp.text;
            soup = BeautifulSoup(raw_html, "html.parser");
            for tag in soup(_NOISE_TAGS) {
                tag.decompose();
            }
            text = soup.get_text(separator="\n", strip=True);
            return (
                raw_html,
                "\n".join(line.strip() for line in text.splitlines() if line.strip()),
            );
        } except UnsafeURLError {
            self.blocked = True;
            return ("", "");
        } except Exception as e {
            logger.debug(f"Failed to fetch {url}: {e}");
            return ("", "");
        }
    }

    def _extract_links(html: str, base_url: str, domain: str) -> list[str] {
        links: list[str] = [];
        for a in BeautifulSoup(html, "html.parser").find_all("a", href=True) {
            href = a["href"];
            if href.startswith(("#", "mailto:", "tel:", "javascript:")) {
                continue;
            }
            parsed = urlparse(urljoin(base_url, href));
            if parsed.netloc == domain and parsed.scheme in ("http", "https") {
                clean = f"{parsed.scheme}://{parsed.netloc}{parsed.path}";
                if not clean.endswith(_FILE_EXTENSIONS) and clean not in links {
                    links.append(clean);
                }
            }
        }
        return links;
    }

    def _normalize_url(url: str) -> str {
        parsed = urlparse(url);
        return f"{parsed.scheme}://{parsed.netloc}{parsed.path.rstrip('/') or '/'}";
    }
}

def brain_section(brain_config: BrainConfig) -> dict[str, any] {
    section: dict[str, any] = {"provider": brain_config.provider};
    for key in ("model", "reasoning_effort") {
        if getattr(brain_config, key) {
            section[key] = getattr(brain_config, key);
        }
    }
    return section;
}

def _persona_untrained(persona: any) -> bool {
    return not isinstance(persona, dict)
        or persona.get("company") == UNTRAINED_COMPANY
        or not persona.get("email");
}

def merge_trained_config(learned: any, existing: any) -> any {
    if not isinstance(existing, dict) or not existing {
        return learned;
    }
    merged = copy.deepcopy(existing);
    untrained = _persona_untrained(existing.get("persona"));
    for (section, value) in learned.items() {
        if not isinstance(merged.get(section), dict) {
            merged[section] = copy.deepcopy(value);
        }
    }
    for (section, keys) in LEARNED_FIELDS.items() {
        for key in keys {
            if key in learned.get(section, {}) {
                merged[section][key] = copy.deepcopy(learned[section][key]);
            }
        }
    }
    if untrained {
        merged["persona"].update(copy.deepcopy(learned.get("persona", {})));
    }
    learned_offer = (learned.get("product") or {}).get("offer") or {};
    if learned_offer.get("entry_ideas") and isinstance(merged.get("product"), dict) {
        offer = merged["product"].setdefault("offer", {});
        if isinstance(offer, dict) {
            offer["entry_ideas"] = list(learned_offer["entry_ideas"]);
        }
    }
    if "brain" in learned {
        merged["brain"] = copy.deepcopy(learned["brain"]);
    }
    trained = ((learned.get("channels") or {}).get("email") or {}).get("link_domains") or [];
    if trained and isinstance(merged.get("channels"), dict) {
        email = merged["channels"].setdefault("email", {});
        if isinstance(email, dict) {
            have = list(email.get("link_domains") or []);
            email["link_domains"] = have + [d for d in trained if d not in have];
        }
    }
    return merged;
}

def _offer_from(product_info: any) -> dict[str, any] {
    ideas = product_info.get("entry_offer_ideas");
    ideas = [str(i).strip() for i in ideas if str(i).strip()][:4]
        if isinstance(ideas, list)
        else [];
    return {"entry_ideas": ideas};
}

def _backup(path: Path, raw: str) -> Path {
    backup = path.with_name(path.name + ".bak");
    if backup.exists() {
        backup = path.with_name(f"{path.name}.{time.strftime('%Y%m%d-%H%M%S')}.bak");
    }
    backup.write_text(raw, encoding="utf-8");
    return backup;
}

def write_trained_config(learned: any, path: any) -> any {
    path = Path(path);
    source = path if path.exists() else path.with_name("sellbird.yaml");
    existing: any = None;
    if source.exists() {
        raw = read_user_text(source);
        try {
            existing = yaml.safe_load(raw);
        } except yaml.YAMLError {
            existing = None;
        }
        if not isinstance(existing, dict) and source == path and raw.strip() {
            print(
                f"      Couldn't read the existing {path.name}; saved it as {_backup(path, raw).name}.",
            );
        }
    }
    config = merge_trained_config(learned, existing);
    if config is not learned and source == path {
        print(
            f"      Kept your settings from {path.name} (email provider, schedule, limits,\n      compliance, sender identity); updated the product, targeting and company.",
        );
    }
    tmp = path.with_name(path.name + ".tmp");
    try {
        with open(tmp, "w", encoding="utf-8") as f {
            yaml.safe_dump(config, f, default_flow_style=False, sort_keys=False);
        }
        if path.exists() {
            shutil.copymode(path, tmp);
        }
        os.replace(tmp, path);
    } finally {
        tmp.unlink(missing_ok=True);
    }
    return config;
}

def _bullets(items: any) -> str {
    return "\n".join("- " + item for item in items);
}

def _sections(spec: list[any], sources: any) -> str {
    parts: list[str] = [];
    for (title, source, key, fallback) in spec {
        data = sources[source];
        body = _bullets(data.get(key, [])) if fallback is None else f"{data.get(key, fallback)}";
        parts.append(f"## {title}\n{body}");
    }
    return "\n\n".join(parts);
}

class Trainer {
    has brain_config: any = None,
        state: any = None,
        brain: any = None,
        scraped_pages: dict[str, str] = {};

    def init(brain_config: BrainConfig | None = None) {
        self.brain_config = brain_config or load_brain_config();
        self.state = StateManager();
        self.brain = Brain(self.state, self.brain_config);
        self.scraped_pages = {};
    }

    async def train(
        url: str, output_path: str = "sellbird.local.yaml", max_pages: int = 100
    ) -> any {
        load_dotenv();
        await self.state.init_db();
        url = _normalize_start_url(url);
        parsed = urlparse(url);
        domain = parsed.netloc;
        if not domain {
            print(_BAD_URL.format(url));
            return None;
        }
        base_url = f"{parsed.scheme}://{domain}";
        logger.info(f"Training Sellbird on {base_url}...");
        print(f"\n{_RULE}\n  Sellbird Training Mode\n  Learning from: {base_url}\n{_RULE}\n");
        cf_account_id = os.getenv("CLOUDFLARE_ACCOUNT_ID", "");
        cf_api_token = os.getenv("CLOUDFLARE_API_TOKEN", "");
        crawler: any = None;
        if cf_account_id and cf_api_token {
            print(f"[1/6] Deep crawling with Cloudflare (up to {max_pages} pages)...");
            crawler = CloudflareCrawler(cf_account_id, cf_api_token);
            self.scraped_pages = await crawler.crawl(base_url, max_pages=max_pages, depth=10);
        } else {
            print(_NO_CLOUDFLARE);
            crawler = FallbackCrawler();
            self.scraped_pages = await crawler.crawl(base_url, max_pages=max_pages);
        }
        if not self.scraped_pages {
            if getattr(crawler, "blocked", False) {
                print(_PRIVATE_SITE.format(base_url));
            } else {
                print("\nERROR: Could not scrape any pages. Check the URL.");
            }
            return None;
        }
        print(f"      Done! Crawled {len(self.scraped_pages)} pages.\n");
        print("[2/6] Analyzing product information...");
        product_info = await self._extract_product_info();
        if not product_info {
            print("ERROR: Could not extract product information.");
            return None;
        }
        print(f"      Found: {product_info.get('product_name', 'Unknown Product')}\n");
        print("[3/6] Identifying ideal customer profile...");
        icp_info = await self._extract_icp();
        print(f"      Target: {', '.join(icp_info.get('industries', ['Unknown']))}\n");
        print("[4/6] Analyzing competitive landscape...");
        competitive_intel = await self._extract_competitive_intel(product_info);
        print(f"      Identified {len(competitive_intel.get('competitors', []))} competitors.\n");
        print("[5/6] Generating objection handling playbook...");
        objections = await self._generate_objections(product_info, competitive_intel);
        if not objections {
            print(_NO_PLAYBOOK);
            return None;
        }
        print(f"      Prepared {len(objections)} objection responses.\n");
        print("[6/6] Building configuration and product knowledge...");
        config = self._build_config(product_info, icp_info, objections, domain);
        config_path = Path(output_path);
        if not config_path.is_absolute() {
            config_path = PROJECT_ROOT / config_path;
        }
        guessed_email = config["persona"]["email"];
        config = write_trained_config(config, config_path);
        await self._generate_product_knowledge(product_info, icp_info, competitive_intel);
        if competitive_intel.get("competitors") {
            await self._generate_battle_cards(product_info, competitive_intel);
        }
        print(f"\n{_RULE}\n  Training complete!\n{_RULE}");
        print(f"\n  Product:      {config['product']['name']}");
        print(f"  Company:      {config['persona']['company']}");
        print(f"  ICP titles:   {', '.join(config['icp']['titles'])}");
        print(f"  Industries:   {', '.join(config['icp']['industries'])}");
        print(f"  Pages crawled: {len(self.scraped_pages)}");
        offer = (config.get("product") or {}).get("offer") or {};
        if offer.get("entry") {
            print(f"\n  First-email offer: {offer['entry']}");
        } else {
            print(_NEXT_OFFER);
            if offer.get("entry_ideas") {
                print("  Ideas to start from: " + "; ".join(offer["entry_ideas"]));
            }
        }
        print(f"\n  Files generated:\n    - {config_path}\n    - skills/product_knowledge.md");
        if competitive_intel.get("competitors") {
            print("    - skills/competitive_intel.md");
        }
        if config["persona"].get("email") == guessed_email {
            print(_REVIEW_GUESSED.format(config_path));
        } else {
            print(
                _REVIEW_KEPT.format(
                    config_path, config['persona'].get('name', ''), config['persona']['email']
                ),
            );
        }
        print("  Then run: sellbird run\n");
        return config;
    }

    def _get_all_content(max_chars: int = 60000) -> str {
        all_content = "";
        for (url, content) in self.scraped_pages.items() {
            all_content += f"\n\n--- PAGE: {urlparse(url).path or '/'} ---\n{content[:8000]}";
            if len(all_content) > max_chars {
                break;
            }
        }
        return fence(all_content, "your website");
    }

    async def _ask_json(prompt: str, fallback: dict[str, any]) -> any {
        result = await self.brain.think_json(prompt, session_id="sellbird-trainer");
        return result if isinstance(result, dict) else fallback;
    }

    async def _extract_product_info -> any {
        all_content = self._get_all_content();
        return await self._ask_json(
            f"""Analyze this entire website and extract comprehensive product/company information.

    WEBSITE CONTENT ({len(self.scraped_pages)} pages):
    {all_content}

    {UNTRUSTED_RULE}

    Extract the following and return as JSON:
    {{
      "company_name": "the company name",
      "product_name": "the main product or service name",
      "product_description": "2-3 sentence description of what the product does and who it's for",
      "pricing": "pricing info if available (tiers, starting price, etc.), otherwise 'Contact for pricing'",
      "key_benefits": ["benefit 1", "benefit 2", "benefit 3", "benefit 4", "benefit 5"],
      "features": ["feature 1", "feature 2", "feature 3", "feature 4", "feature 5", "feature 6"],
      "target_audience": "who this product is for — be specific about roles and company types",
      "value_proposition": "the core value proposition in one sentence",
      "differentiators": ["what makes this different from alternatives — point 1", "point 2"],
      "competitors": ["competitor 1", "competitor 2", "competitor 3"],
      "social_proof": ["any case studies, testimonials, notable customers, or stats mentioned"],
      "integrations": ["tools and platforms this integrates with"],
      "use_cases": ["specific use case 1", "use case 2", "use case 3"],
      "tone": "describe the brand's communication tone in 3-4 words",
      "entry_offer_ideas": ["3 or 4 things this business could offer a prospect for free in a first cold email: specific, useful on their own, quick for this business to deliver, and tied to what it sells. E.g. for a web designer 'a mockup of your homepage with online booking', for an SEO agency 'a one-page report on where you rank and why', for inventory software 'a reorder forecast for your top 20 SKUs'. Never a discount or a generic call."]
    }}

    Be thorough — you have access to the full website. Extract everything relevant.""", {}
        );
    }

    async def _extract_icp -> any {
        all_content = self._get_all_content(max_chars=40000);
        fallback = {
            "industries": ["Technology"],
            "company_size": "10-200 employees",
            "titles": ["VP", "Director", "Head of"],
            "geography": ["United States"],
        };
        return await self._ask_json(
            f"""Based on this entire website, determine the Ideal Customer Profile (ICP).
    Look at case studies, testimonials, pricing tiers, feature descriptions, and target messaging
    to understand exactly who this product is built for.

    WEBSITE CONTENT ({len(self.scraped_pages)} pages):
    {all_content}

    {UNTRUSTED_RULE}

    Return as JSON:
    {{
      "industries": ["industry 1", "industry 2", "industry 3"],
      "company_size": "employee range like '10-200 employees'",
      "titles": ["decision maker title 1", "title 2", "title 3", "title 4"],
      "geography": ["country or region 1", "region 2"],
      "buyer_persona": "A detailed description of the ideal buyer — their role, daily challenges, goals, and what success looks like for them",
      "pain_points": ["specific pain point 1", "pain point 2", "pain point 3", "pain point 4"],
      "buying_triggers": ["trigger event that makes them ready to buy 1", "trigger 2", "trigger 3"],
      "disqualifiers": ["signals that someone is NOT a good fit 1", "disqualifier 2"]
    }}

    For any city in "geography", always include the state/province and country if
    the name could plausibly refer to more than one place — write "Solon, Ohio"
    not "Solon" (there's also a Solon in France), "Springfield, Illinois" not
    "Springfield" (30+ US cities share that name). These strings get geocoded
    automatically for local-business discovery, and an unqualified name silently
    resolves to the wrong place on Earth instead of failing loudly.

    "titles" MUST be literal job titles exactly as they'd appear on a business
    card or LinkedIn profile ("Owner", "CEO", "President", "Plant Manager",
    "Practice Manager") — never a customer-segment or persona label ("Business
    Owner Segment", "Decision Maker", "Healthcare Professional"). Sellbird matches
    a found contact's title against this list by substring, so a descriptive
    label instead of a real title means every real contact silently fails to
    match and gets discarded. If the buyer is an INDIVIDUAL bought into by
    persona rather than a role at a target company (e.g. this product targets
    physicians, business owners, or executives directly as people, not a
    "Director of X" at a company you sell software to), list every real job
    title that persona plausibly holds — a "business owner" persona should
    produce ["Owner", "President", "CEO", "Founder", "Managing Partner"], a
    "physician" persona should produce ["Physician", "MD", "Doctor"], and so on.
    Prefer more titles over fewer; a missed real title costs a contact forever,
    an extra one costs nothing.

    Be specific — don't guess generically. Base this on what the website actually says about their customers.""", fallback
        );
    }

    async def _extract_competitive_intel(product_info: any) -> any {
        all_content = self._get_all_content(max_chars=40000);
        return await self._ask_json(f"""Analyze this website for competitive intelligence.
    The product is: {product_info.get('product_name', '')}
    Known competitors: {', '.join(product_info.get('competitors', []))}

    WEBSITE CONTENT:
    {all_content}

    {UNTRUSTED_RULE}

    Look for comparison pages, "why us" messaging, feature differentiation,
    and any mentions of competitors or alternatives.

    Return as JSON:
    {{
      "competitors": [
        {{
          "name": "Competitor Name",
          "how_we_win": "What makes our product better than this competitor",
          "their_weakness": "Known limitations or complaints about this competitor",
          "migration_angle": "Why someone would switch from them to us"
        }}
      ],
      "positioning": "How this product positions itself in the market — one paragraph",
      "unique_strengths": ["strength that no competitor has 1", "strength 2"],
      "common_alternatives": ["what prospects do instead of buying this — DIY, spreadsheets, etc."]
    }}

    If the website doesn't mention specific competitors, infer the most likely ones based on the product category.""", {"competitors": []});
    }

    async def _generate_objections(product_info: any, competitive_intel: any) -> dict[str, str]
        | None {
        names = [
            c.get("name", "")
            for c in competitive_intel.get("competitors", [])
            if isinstance(c, dict) and isinstance(c.get("name", ""), str)
        ];
        (benefits, differentiators) = [
            _joined(product_info.get(k, []))
            for k in ("key_benefits", "differentiators")
        ];
        prompt = f"""You are a world-class B2B sales trainer. Based on this product and its competitive
    landscape, generate the most common objections a prospect would raise, with consultative responses.

    Product: {product_info.get('product_name', '')}
    Description: {product_info.get('product_description', '')}
    Pricing: {product_info.get('pricing', '')}
    Key Benefits: {benefits}
    Competitors: {', '.join(names)}
    Differentiators: {differentiators}

    Generate 8-12 objections covering:
    - Price/budget concerns
    - Existing solutions / competitor loyalty
    - Timing / priority
    - Implementation / switching costs
    - Trust / credibility
    - Need / relevance

    Each response should be 1-2 sentences, consultative (not defensive), and end with
    a question or redirect that keeps the conversation going.

    Return a JSON object where keys are objections and values are non-empty responses.""";
        for attempt in range(MAX_OBJECTION_ATTEMPTS) {
            result = await self.brain.think_json(prompt, session_id="sellbird-trainer");
            if getattr(self.brain, "last_reply_empty", False) {
                logger.warning("Objection generation stopped: provider returned no response.");
                return None;
            }
            cleaned = _playbook(result);
            if cleaned is not None {
                logger.info("Generated %s valid objection responses.", len(cleaned));
                return cleaned;
            }
            if attempt < MAX_OBJECTION_ATTEMPTS - 1 {
                logger.warning(
                    "Invalid objection playbook. Retrying attempt %s/%s.",
                    attempt + 1,
                    MAX_OBJECTION_ATTEMPTS,
                );
                prompt += _OBJECTIONS_RETRY;
            }
        }
        logger.error("Objection generation failed after %s attempts.", MAX_OBJECTION_ATTEMPTS);
        return None;
    }

    async def _generate_product_knowledge(
        product_info: any, icp_info: any, competitive_intel: any
    ) {
        sources = {"p": product_info, "i": icp_info, "c": competitive_intel};
        knowledge = f"# Product Knowledge: {product_info.get('product_name', 'the product')}\n\n{_sections(_KNOWLEDGE, sources)}\n";
        (PROJECT_ROOT / "skills" / "product_knowledge.md").write_text(knowledge, encoding="utf-8");
        print("      Generated: skills/product_knowledge.md");
    }

    async def _generate_battle_cards(product_info: any, competitive_intel: any) {
        competitors = competitive_intel.get("competitors", []);
        if not competitors {
            return;
        }
        product_name = product_info.get("product_name", "Our Product");
        cards = f"# Competitive Battle Cards: {product_name}\n\nUse these when a prospect mentions a competitor or asks \"how are you different?\"\n\n";
        cards += _sections(_BATTLE_CARDS, {"c": competitive_intel}) + "\n\n---\n";
        for comp in competitors {
            if isinstance(comp, dict) {
                cards += _battle_card(comp, product_name);
            }
        }
        (PROJECT_ROOT / "skills" / "competitive_intel.md").write_text(cards, encoding="utf-8");
        print("      Generated: skills/competitive_intel.md");
    }

    def _build_config(
        product_info: any, icp_info: any, objections: any, domain: str
    ) -> dict[str, any] {
        email_domain = domain.removeprefix("www.");
        return {
            "persona": {
                "name": "Alex",
                "company": product_info.get("company_name", "Your Company"),
                "role": "Business Development",
                "email": f"alex@{email_domain}",
                "linkedin": f"linkedin.com/in/alex-{email_domain.replace('.', '-')}",
                "tone": product_info.get("tone", _DEFAULT_TONE),
            },
            "product": {
                "name": product_info.get("product_name", "Your Product"),
                "description": product_info.get("product_description", ""),
                "pricing": product_info.get("pricing", "Contact for pricing"),
                "key_benefits": product_info.get("key_benefits", []),
                "objection_responses": objections,
                "offer": _offer_from(product_info),
            },
            "icp": {
                "industries": icp_info.get("industries", ["Technology"]),
                "company_size": icp_info.get("company_size", "10-200 employees"),
                "titles": icp_info.get("titles", ["VP", "Director"]),
                "geography": icp_info.get("geography", ["United States"]),
            },
            "channels": {
                "email": {
                    "enabled": True,
                    "provider": "instantly",
                    "max_daily_sends": 50,
                    "link_domains": [email_domain],
                },
                "linkedin": {
                    "enabled": False,
                    "max_daily_connections": 20,
                    "max_daily_messages": 10,
                },
            },
            "usage": {
                "max_daily_claude_percent": 80,
                "heartbeat_interval_minutes": 15,
                "quiet_hours": {"start": "22:00", "end": "07:00", "timezone": "America/New_York"},
            },
            "brain": brain_section(self.brain_config),
        };
    }
}

def _joined(items: any) -> str {
    return ", ".join(str(item) for item in items) if isinstance(items, list) else "";
}

def _nonblank_pair(pair: any) -> bool {
    (objection, response) = pair;
    return bool(
        isinstance(objection, str)
            and objection.strip()
            and isinstance(response, str)
            and response.strip(),
    );
}

def _playbook(result: any) -> dict[str, str] | None {
    if not isinstance(result, dict)
        or not result
        or not all(_nonblank_pair(pair) for pair in result.items())
    {
        return None;
    }
    return {objection.strip(): response.strip() for (objection, response) in result.items()};
}

def _battle_card(comp: any, product_name: str) -> str {
    name = comp.get("name", "Unknown");
    return f"""
## vs. {name}

**How we win:** {comp.get('how_we_win', 'N/A')}

**Their weakness:** {comp.get('their_weakness', 'N/A')}

**Migration angle:** {comp.get('migration_angle', 'N/A')}

**When a prospect says "We use {name}":**
"That's a solid tool. The teams that've moved to {product_name} from {name} tell us the biggest difference is {comp.get('how_we_win', 'the experience')}. Worth a quick comparison?"

---
""";
}

async def run_training(url: str, output: str = "sellbird.local.yaml", max_pages: int = 100) {
    await Trainer().train(url, output, max_pages=max_pages);
}

def main {
    if len(sys.argv) < 2 {
        print(_USAGE);
        sys.exit(1);
    }
    url = _normalize_start_url(sys.argv[1]);
    max_pages = 100;
    if len(sys.argv) > 2 {
        try {
            max_pages = max(1, int(sys.argv[2]));
        } except ValueError {
            print(f"Invalid max-pages value: {sys.argv[2]!r} (expected a number)");
            sys.exit(1);
        }
    }
    asyncio.run(run_training(url, max_pages=max_pages));
}

with entry:__main__ {
    utf8_stdio();
    main();
}
