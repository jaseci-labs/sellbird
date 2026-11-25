glob STALE_DAYS = 180,
     THIN_PAGES = 5,
     HEADER = "- Site checks (an automated read of their public pages; it can miss things). Use at most ONE, only if it fits this kind of business, put it as what you would do in their place, and never call it an audit or say you went through the site:";

async def site_facts(state: any, company_id: str) -> list[str] {
    lookup = getattr(state, "get_observations", None) if company_id and state is not None else None;
    if lookup is None {
        return [];
    }
    try {
        rows = await lookup(company_id=company_id, latest_only=True, limit=500);
    } except Exception {
        return [];
    }
    current = {r.get("signal_code"): r.get("value_num") for r in rows};

    facts: list[str] = [];
    if current.get("NO_SCHEMA_MARKUP") == 1 {
        facts.append(
            "  - Their homepage has no JSON-LD structured data (schema.org markup), so search engines get less to show about them, such as opening hours, contact details or reviews",
        );
    }
    age = current.get("BLOG_STALE");
    if age is not None and age >= STALE_DAYS {
        facts.append(f"  - The newest date in their sitemap.xml is about {int(age)} days old");
    }
    pages = current.get("SITE_PAGE_COUNT");
    if pages is not None and 0 < pages and pages <= THIN_PAGES {
        facts.append(f"  - Their sitemap.xml lists only {int(pages)} page(s)");
    }
    if current.get("BLOCKS_AI_CRAWLERS") == 1 {
        facts.append(
            "  - Their robots.txt blocks AI crawlers, so AI search answers can't read their site"
        );
    }
    return [HEADER] + facts if facts else [];
}
