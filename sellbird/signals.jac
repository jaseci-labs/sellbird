glob _COLUMNS = "code label category value_type collector confidence_floor cost_note description".split(),
     _KEY_ORDER = "code label description category value_type collector cost_note confidence_floor".split(),
     _SEEDED_FIELDS = ("label", "description", "category", "value_type", "collector", "cost_note");

glob _ROWS = [
    "SERP_RANK|Search rank position|discovery|num|discover|0|~$0.006 per search at depth 30 (paid SERP API, Live endpoint)|"
        "Where the business ranks organically for a '<service> <city>' search (the search phrase is "
        "stored with it). The most useful prospecting signal there is: positions 11-30 are the sweet "
        "spot — visible enough to be trying, not winning yet. Top 10 are already winning (harder "
        "sell); 31+ are cheaper but less motivated. Rank depends on where the searcher stands: this "
        "is the view from the city centre.",
    "IN_LOCAL_PACK|In the Google local 3-pack|discovery|num|discover|0|included in the organic rank search above|"
        "Holds one of the three map slots above the organic results for a '<service> <city>' search "
        "(value = slot 1-3; ads excluded). These businesses are already winning local search — "
        "exclude them to find the ones who aren't, or target them with something else.",
    "MAPS_RANK|Google Maps rank position|discovery|num|discover|0|~$0.002 per Maps search of up to 100 results (paid SERP API)|"
        "Where the business appears in Google Maps for a '<service> <city>' search from the city "
        "centre (the search phrase is stored with it). Outside the top 3 on the map means outside the "
        "local pack most searchers see. Also finds businesses with no website at all.",
    "FOUND_IN_SERP|Discovered via search|discovery|text|discover|0|included in the search above|"
        "The business appeared in a target-market search — how Sellbird found it at all.",
    "NO_WEBSITE|No website at all|discovery|bool|discover|0|included in the business listing lookup|"
        "The business has a listing and a phone number but no site. If you sell websites this is the "
        "highest-intent signal that exists — and it is a filter you can query for directly, not "
        "something you infer.",
    "UNCLAIMED_LISTING|Unclaimed Google listing|discovery|bool|discover|0|included in the business listing lookup|"
        "Nobody has claimed their Google Business Profile, so they are not managing how they show up "
        "locally. Strong signal for anyone selling local marketing.",
    "REVIEW_RATING|Review rating|discovery|num|discover|0|included in the business listing lookup|"
        "Their average star rating. Useful in both directions: a low rating is a reputation problem "
        "to solve, a high one with few reviews is proof they are good but invisible.",
    "REVIEW_COUNT|Number of reviews|discovery|num|discover|0|included in the business listing lookup|"
        "How many reviews they have. A rough proxy for size and for how much attention they pay to "
        "their online presence.",
    "INCUMBENT_AGENCY|Has a marketing/web agency|profile|text|profile|0.75|free (homepage HTML)|"
        "An agency credited in the site footer ('Website by X'). High-value: it tells you who you're "
        "displacing, and every detection builds a roster you can target as a whole book of business. "
        "Only recorded when the credit wording is explicit — a wrong incumbent is worse than none.",
    "RUNNING_GOOGLE_ADS|Running Google Ads|profile|bool|profile|0|free (homepage HTML)|"
        "Google Ads tag on the site — they are spending on acquisition TODAY. Strong budget signal.",
    "RUNNING_META_ADS|Running Meta/Facebook Ads|profile|bool|profile|0|free (homepage HTML)|"
        "Meta Pixel on the site — actively spending on paid social.",
    "TECH_STACK|Website platform / tools|profile|text|profile|0|free (homepage HTML)|"
        "What the site is built on and which tools it runs (WordPress, Shopify, HubSpot, chat "
        "widgets, booking tools).",
    "NO_SCHEMA_MARKUP|Missing structured data|profile|bool|profile|0|free (homepage HTML)|"
        "No JSON-LD schema markup — a concrete, checkable SEO gap you can name in an email.",
    "NO_ONLINE_BOOKING|No online booking/scheduling|profile|bool|profile|0|free (homepage HTML)|"
        "No booking or scheduling widget detected — leads have to phone in, so after-hours demand is "
        "lost.",
    "SITE_PAGE_COUNT|Site size|profile|num|profile|0|free (sitemap.xml)|"
        "Page count from sitemap.xml. A very thin site suggests little investment; a large stale one "
        "suggests neglect.",
    "BLOG_STALE|Content gone stale|profile|num|profile|0|free (sitemap.xml)|"
        "No new content in a long time — content marketing started and abandoned.",
    "BLOCKS_AI_CRAWLERS|Blocks AI crawlers|profile|bool|profile|0|free (robots.txt)|"
        "robots.txt blocks AI crawlers — they'll be invisible in AI search answers.",
    "YC_BACKED|Backed by Y Combinator|profile|bool|profile|0|free (homepage HTML)|"
        "The company says on its own site that it's YC-backed (a batch like W24, a YC badge, or a "
        "link to its YC page). Pairs with the YC-startups discovery preset and the startup-founder "
        "writing playbook.",
    "ACCELERATOR|Went through an accelerator|profile|bool|profile|0|free (homepage and About page)|"
        "The company says on its own site that an accelerator backed it: Techstars, 500 Global, "
        "Antler, Entrepreneur First, South Park Commons, Neo, AI Grant, a16z speedrun, Pioneer or "
        "Plug and Play, with the cohort when stated. YC is YC_BACKED. Pairs with the accelerator "
        "discovery preset and the startup-founder writing playbook.",
    "FUNDING_ROUND|Announced a funding round|profile|bool|profile|0|free (homepage, About, press page)|"
        "The company announces its own raise on its site (\"we raised\", \"Acme raises $12M Series A\"): "
        "round, amount and date when stated. Raises over 18 months old aren't written to as news. "
        "Pairs with the recently-funded discovery preset.",
    "HIRING_ROLE|Hiring for a relevant role|profile|text|profile|0|free (careers page or public job-board feed)|"
        "An open role that implies they're buying in your category right now: one of your "
        "hiring_signals roles (or ICP titles) on the Greenhouse, Lever, Ashby or Workable board their "
        "site links to, with department, location and posting date, or a role listed on their careers "
        "page.",
    "OPEN_ROLES|Open roles on their job board|profile|num|profile|0|free (public job-board feed, one request)|"
        "How many roles are open on the Greenhouse, Lever, Ashby or Workable board their site links "
        "to. A growing team is a budget signal; zero is a quiet one.",
    "CONTACT_FOUND|Named contact found|people|text|people|0|free (team page)|"
        "A named person scraped from the team/about page, with their title.",
    "DECISION_MAKER_TITLE|Decision-maker title|people|text|people|0|free (team page)|"
        "Title matches an owner/decision-maker pattern (Owner, President, Practice Manager, Marketing "
        "Director).",
    "REGISTRY_VERIFIED|Confirmed in a public registry|people|text|people|0|free (public registry API)|"
        "The person was confirmed in an authoritative public registry (licensing board, professional "
        "registry). Also filters out scraping artifacts — a name that matches nothing usually wasn't "
        "a person.",
    "LIKELY_OWNER|Likely the owner|people|bool|people|0|free (company website)|"
        "The company's own website says this person owns or founded it: an Owner/Founder/President "
        "title, a sentence like 'owned and operated by' or a schema.org founder. Former, retired and "
        "late owners don't count. The evidence is kept with the fact.",
    "EMAIL_PATTERN|Company email pattern|verification|text|verify|0|free, or ~1 lookup credit|"
        "The domain's address format (first.last@, flast@). One real address cracks the whole "
        "company.",
    "EMAIL_STATUS|Email deliverability|verification|text|verify|0|1 verification credit (free tiers available)|"
        "Whether the address is verified, catch-all/risky, an unverified guess, or invalid.",
    "CONTACT_FORM_URL|Contact form available|verification|text|profile|0|free (site HTML)|"
        "A contact form on the site. Worth knowing because it reaches the business without needing an "
        "email address at all — and roughly half of domains can't be email-verified.",
];

glob SIGNAL_CATALOG: list[dict[str, any]] = [_signal(row) for row in _ROWS];

def _signal(row: str) -> dict[str, any] {
    sig: dict[str, any] = dict(zip(_COLUMNS, row.split("|")));
    sig["confidence_floor"] = float(sig["confidence_floor"]);
    return {k: sig[k] for k in _KEY_ORDER};
}

def _seeded(row: any, sig: dict[str, any]) -> bool {
    if row is None or any((row.get(f) or "") != (sig.get(f) or "") for f in _SEEDED_FIELDS) {
        return False;
    }
    return float(row.get("confidence_floor") or 0.0) == float(sig.get("confidence_floor", 0.0));
}

async def seed_signal_catalog(state: any) -> int {
    have = {row["code"]: row for row in await state.get_signal_codes()};
    for sig in SIGNAL_CATALOG {
        if not _seeded(have.get(sig["code"]), sig) {
            await state.upsert_signal_code(
                sig["code"], **{k: v for (k, v) in sig.items() if k != "code"}
            );
        }
    }
    return len(SIGNAL_CATALOG);
}
