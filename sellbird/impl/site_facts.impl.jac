impl site_facts(state, company_id: builtins.str) -> builtins.list[builtins.str] {
    if not company_id or state is None {
        return [];
    }
    lookup: any = getattr(state, "get_observations", None);
    if lookup is None {
        return [];
    }
    try {
        rows: any = await lookup(company_id=company_id, latest_only=True, limit=500);
    } except Exception {
        return [];
    }
    current: any = {r.get("signal_code"): r.get("value_num") for r in rows};

    facts: builtins.list[builtins.str] = [];
    if current.get("NO_SCHEMA_MARKUP") == 1 {
        facts.append(
            "  - Their homepage has no JSON-LD structured data (schema.org markup), so search engines get less to show about them, such as opening hours, contact details or reviews",
        );
    }
    age: any = current.get("BLOG_STALE");
    if age is not None and age >= STALE_DAYS {
        facts.append(f"  - The newest date in their sitemap.xml is about {`int(age)} days old");
    }
    pages: any = current.get("SITE_PAGE_COUNT");
    if pages is not None and 0 < pages <= THIN_PAGES {
        facts.append(f"  - Their sitemap.xml lists only {`int(pages)} page(s)");
    }
    if current.get("BLOCKS_AI_CRAWLERS") == 1 {
        facts.append(
            "  - Their robots.txt blocks AI crawlers, so AI search answers can't read their site"
        );
    }
    return [HEADER] + facts if facts else [];
}
