impl Scout.init(brain: Brain, state: StateManager, config: SellbirdConfig, env: EnvConfig) {
    self.brain = brain;
    self.state = state;
    self.config = config;
    self.env = env;
    self._reset();
}

impl Scout._reset {
    self._queries_this_cycle = 0;
    self._seen_prospect_keys = set();
    self._seen_domains = set();
    self._site_reads = {};
    self._site_evidence = {};
    self._own_domains = {};
    self._challenged = set();
}

impl Scout._default_industry -> str {
    return self.config.icp.industries[0] if self.config.icp.industries else "";
}

impl Scout.run {
    logger.info("Scout: Starting prospecting cycle...");
    self.skills = self.brain.load_skills_for_agent("scout");
    self._reset();
    prospects_found = 0;
    linkedin = self.config.channels.linkedin.enabled and self.env.linkedin_email;
    for name in "hunter known_companies linkedin hiring_boards profile_search company_discovery".split() {
        if not linkedin and name in ("linkedin", "profile_search") {
            continue;
        }
        try {
            prospects_found += await getattr(self, f"_prospect_via_{name}")();
        } except Exception as e {
            logger.warning(f"Scout: strategy '{name}' failed: {e}");
        }
    }
    await self.state.log_action(
        action_type="prospect", agent="scout", details={"prospects_found": prospects_found}
    );
    logger.info(f"Scout: Found {prospects_found} new prospects this cycle.");
}

impl Scout._do_not_contact_entry(domain: str) -> str {
    try {
        entries = live_do_not_contact(self.config);
    } except Exception as e {
        logger.debug(f"do_not_contact list unavailable: {e}");
        return "";
    }
    return do_not_contact_domain_match(domain, entries);
}

impl Scout._mark_checked(company: any, domain: str) {
    try {
        await self.state.mark_prospects_checked(company["id"]);
    } except Exception as e {
        logger.debug(f"mark_prospects_checked failed for {domain}: {e}");
    }
}

impl Scout._listed(domain: str) -> bool {
    listed = self._do_not_contact_entry(domain);
    if listed {
        logger.info(f"Scout: {domain} is on compliance.do_not_contact ({listed}); skipping.");
    }
    return bool(listed);
}

impl Scout._skip_listed_company(company: any, domain: str) -> bool {
    if not self._listed(domain) {
        return False;
    }
    await self._mark_checked(company, domain);
    return True;
}

impl Scout._prospect_key(prospect: Prospect) -> str {
    if prospect.email {
        return f"email:{prospect.email.lower().strip()}";
    }
    if prospect.linkedin_url {
        u = re.sub(
            r"^https?://(www\.)?", "", prospect.linkedin_url.lower().split("?")[0].rstrip("/")
        );
        return f"li:{u}";
    }
    return f"name:{prospect.first_name.lower().strip()}|{prospect.last_name.lower().strip()}|{prospect.company.lower().strip()}";
}

impl Scout._is_duplicate_prospect(prospect: Prospect) -> bool {
    key = self._prospect_key(prospect);
    if key in self._seen_prospect_keys {
        return True;
    }
    try {
        if await self.state.prospect_exists(
            email=prospect.email,
            linkedin_url=prospect.linkedin_url,
            first_name=prospect.first_name,
            last_name=prospect.last_name,
            company=prospect.company,
        ) {
            self._seen_prospect_keys.add(key);
            return True;
        }
    } except Exception as e {
        logger.debug(f"prospect_exists check failed: {e}");
    }
    return False;
}

impl Scout._remember_prospect(prospect: Prospect) {
    self._seen_prospect_keys.add(self._prospect_key(prospect));
}

impl Scout._keep(prospect: Prospect) -> bool {
    if not prospect.is_valid() or await self._is_duplicate_prospect(prospect) {
        return False;
    }
    await self.state.add_prospect(prospect);
    self._remember_prospect(prospect);
    return True;
}

impl Scout._headers(extra: dict[str, any] | None = None) -> dict[str, any] {
    return {
        "User-Agent": random.choice(USER_AGENTS),
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.9",
        **(extra or {}),
    };
}

impl Scout._looks_blocked(text: str, status: int = 200) -> bool {
    return looks_like_challenge(text, status);
}

impl Scout._host(url_or_domain: str) -> str {
    host = urlparse(url_or_domain if "://" in url_or_domain else f"http://{url_or_domain}").netloc;
    return host.lower().split(":")[0].removeprefix("www.");
}

impl Scout.challenged(domain: str) -> bool {
    return self._host(domain) in getattr(self, "_challenged", set[str]());
}

impl Scout._fetch(
    url: str,
    *,
    method: str = "GET",
    json_body: dict[str, any] | None = None,
    headers: dict[str, any] | None = None,
    timeout: float = HTTP_TIMEOUT,
    retries: int = MAX_RETRIES,
) -> any {
    last_status: any = None;
    for attempt in range(retries) {
        resp: any = None;
        try {
            async with public_http_client(timeout=timeout) as client {
                resp = await client.request(
                    method, url, json=json_body, headers=self._headers(headers)
                );
            }
        } except (httpx.TimeoutException, httpx.TransportError) as e {
            logger.debug(f"Fetch transport error ({url[:80]}): {e}");
        } except Exception as e {
            logger.debug(f"Fetch unexpected error ({url[:80]}): {e}");
            return None;
        }
        if resp is not None {
            last_status = resp.status_code;
            if resp.status_code in (200, 202, 403, 429, 503)
                and self._looks_blocked(getattr(resp, "text", "") or "", resp.status_code)
            {
                vars(self).setdefault("_challenged", set[str]()).add(self._host(url));
                logger.debug(f"Fetch got a bot challenge ({resp.status_code}) for {url[:80]}");
                return None;
            }
            if resp.status_code in (429, 500, 502, 503, 504) {
                logger.debug(
                    f"Fetch got {resp.status_code} for {url[:80]} (attempt {attempt + 1}/{retries})"
                );
            } elif resp.status_code == 200 {
                return resp;
            } else {
                logger.debug(f"Fetch got {resp.status_code} for {url[:80]}");
                return None;
            }
        }
        if attempt < retries - 1 {
            await asyncio.sleep(BACKOFF_BASE * (2 ** attempt) + random.uniform(0, 1));
        }
    }
    logger.debug(f"Fetch exhausted retries for {url[:80]} (last={last_status})");
    return None;
}

impl Scout._safe_soup(text: str) -> any {
    try {
        return BeautifulSoup(text, "html.parser");
    } except Exception as e {
        logger.debug(f"HTML parse failed: {e}");
        return None;
    }
}

impl Scout._attr_str(value: any) -> str {
    if isinstance(value, (list, tuple)) {
        return str(value[0]) if value else "";
    }
    return str(value) if value else "";
}

impl Scout._web_search(query: str) -> list[tuple[str, str]] {
    if self._queries_this_cycle >= MAX_QUERIES_PER_CYCLE {
        logger.info("Scout: Query limit reached for this cycle. Will continue next cycle.");
        return [];
    }
    self._queries_this_cycle += 1;
    if self._queries_this_cycle > 1 {
        await asyncio.sleep(random.uniform(*SEARCH_DELAY));
    }
    serper_key = getattr(self.env, "serper_api_key", "") or "";
    tinyfish_key = getattr(self.env, "tinyfish_api_key", "") or "";
    backends: list[any] = [];
    if serper_key {
        backends.append(functools.partial(self._search_serper, query, serper_key));
    }
    if tinyfish_key {
        backends.append(functools.partial(self._search_tinyfish, query, tinyfish_key));
    }
    backends.extend([
        functools.partial(self._search_duckduckgo, query),
        functools.partial(self._search_bing, query),
        functools.partial(self._search_google, query),
    ]);
    for backend in backends {
        try {
            results = await backend();
        } except Exception as e {
            logger.debug(f"Search backend raised: {e}");
            results = [];
        }
        if results {
            return self._dedupe_results(results);
        }
    }
    logger.warning(f"Scout: All search backends failed for: {query[:80]}");
    return [];
}

impl Scout._dedupe_results(results: list[tuple[str, str]]) -> list[tuple[str, str]] {
    seen: set[str] = set();
    out: list[tuple[str, str]] = [];
    for (url, snippet) in results {
        norm = url.split("#")[0].rstrip("/");
        if url and norm not in seen {
            seen.add(norm);
            out.append((url, snippet));
        }
    }
    return out;
}

impl _search_api(
    fetch: any, name: str, url: str, list_key: str, url_key: str, **options: any
) -> list[tuple[str, str]] {
    resp = await fetch(url, retries=2, **options);
    if resp is None {
        return [];
    }
    try {
        data = resp.json();
    } except (json.JSONDecodeError, ValueError) as e {
        logger.debug(f"{name} returned non-JSON: {e}");
        return [];
    }
    if not isinstance(data, dict) {
        return [];
    }
    results: list[tuple[str, str]] = [];
    for item in data.get(list_key, []) or [] {
        if isinstance(item, dict) and (item.get(url_key, "") or "") {
            results.append((item.get(url_key, "") or "", item.get("snippet", "") or ""));
        }
    }
    return results[:MAX_RESULTS_PER_QUERY];
}

impl Scout._search_serper(query: str, api_key: str) -> list[tuple[str, str]] {
    return await _search_api(
        self._fetch,
        "Serper",
        "https://google.serper.dev/search",
        "organic",
        "link",
        method="POST",
        json_body={"q": query, "num": min(MAX_RESULTS_PER_QUERY, SERPER_MAX_NUM)},
        headers={"X-API-KEY": api_key, "Content-Type": "application/json"},
    );
}

impl Scout._search_tinyfish(query: str, api_key: str) -> list[tuple[str, str]] {
    return await _search_api(
        self._fetch,
        "TinyFish",
        f"https://api.search.tinyfish.ai?query={quote_plus(query)}",
        "results",
        "url",
        headers={"X-API-Key": api_key, "Accept": "application/json"},
    );
}

impl Scout._search_html(name: str, query: str) -> list[tuple[str, str]] {
    (url, item_sel, link_sel, snippet_sel) = _HTML_SEARCH[name].split("|");
    (retries, strip) = (1, False) if name == "Google" else (MAX_RETRIES, True);
    resp = await self._fetch(
        url.format(q=quote_plus(query), n=MAX_RESULTS_PER_QUERY), retries=retries
    );
    soup = self._safe_soup(resp.text) if resp is not None else None;
    if soup is None {
        return [];
    }
    results: list[tuple[str, str]] = [];
    for result in soup.select(item_sel) {
        link = result.select_one(link_sel);
        snippet_el = result.select_one(snippet_sel);
        if not (link and link.get("href")) {
            continue;
        }
        href = self._attr_str(link.get("href"));
        href = _unwrap_ddg(href) if name == "DuckDuckGo" else href;
        snippet = snippet_el.get_text() if snippet_el else "";
        if href.startswith("http") {
            results.append((href, snippet.strip() if strip else snippet));
        }
    }
    if results {
        logger.debug(f"{name} returned {len(results)} results");
    }
    return results[:MAX_RESULTS_PER_QUERY];
}

impl Scout._search_duckduckgo(query: str) -> list[tuple[str, str]] {
    return await self._search_html("DuckDuckGo", query);
}

impl Scout._search_bing(query: str) -> list[tuple[str, str]] {
    return await self._search_html("Bing", query);
}

impl Scout._search_google(query: str) -> list[tuple[str, str]] {
    return await self._search_html("Google", query);
}

impl Scout._prospect_via_hunter -> int {
    api_key = getattr(self.env, "hunter_api_key", "") or "";
    if not api_key {
        return 0;
    }
    remaining = await hunter_searches_remaining(self.state);
    if remaining <= 0 {
        return 0;
    }
    try {
        companies = await self.state.companies_needing_prospects(
            limit=min(remaining, HUNTER_DOMAINS_PER_CYCLE)
        );
    } except Exception as e {
        logger.debug(f"companies_needing_prospects failed: {e}");
        return 0;
    }
    count = 0;
    for company in companies or [] {
        domain = (company.get("domain") or "").strip();
        if not domain or await self._skip_listed_company(company, domain) {
            continue;
        }
        if await hunter_searches_remaining(self.state) <= 0 {
            break;
        }
        await record_hunter_search(self.state);
        people = await hunter_domain_people(domain, api_key);
        await self._mark_checked(company, domain);
        for person in people or [] {
            if not isinstance(person, dict) {
                continue;
            }
            title = person.get("position") or "";
            if not self._title_matches_icp(title) {
                continue;
            }
            verification = person.get("verification") or {};
            email_status = _HUNTER_STATUS_MAP.get(
                (verification.get("status") or "").lower(), "guess"
            );
            prospect = Prospect(
                first_name=person.get("first_name") or "",
                last_name=person.get("last_name") or "",
                email=person.get("value") or "",
                email_status=email_status,
                email_verified=email_status == "verified",
                linkedin_url=person.get("linkedin") or "",
                company=company.get("name") or self._domain_to_name(domain),
                company_id=company["id"],
                title=title,
                seniority=person.get("seniority") or self._infer_seniority(title),
                industry=company.get("industry") or self._default_industry(),
                source="hunter_domain_search",
                source_url=f"https://{domain}",
            );
            if await self._keep(prospect) {
                count += 1;
                logger.info(
                    f"Scout: Added {prospect.full_name()} ({prospect.title}) at {prospect.company} [hunter]",
                );
                if count >= MAX_PROSPECTS_PER_CYCLE {
                    return count;
                }
            }
        }
    }
    return count;
}

impl Scout._prospect_via_known_companies -> int {
    try {
        companies = await self.state.companies_needing_prospects(limit=MAX_COMPANIES_PER_CYCLE);
    } except Exception as e {
        logger.debug(f"companies_needing_prospects failed: {e}");
        return 0;
    }
    if not companies {
        return 0;
    }
    logger.info(f"Scout: Backfilling contacts for {len(companies)} known companies...");
    count = 0;
    for company in companies {
        domain = (company.get("domain") or "").strip();
        if not domain or await self._skip_listed_company(company, domain) {
            continue;
        }
        name = company.get("name") or self._domain_to_name(domain);
        industry = company.get("industry") or self._default_industry();
        contacts = await self._contacts_from_company(
            company_id=company["id"],
            domain=domain,
            company_name=name,
            industry=industry,
            source="known_company_backfill",
        );
        await self._mark_checked(company, domain);
        for prospect in contacts {
            await self.state.add_prospect(prospect);
            count += 1;
            logger.info(
                f"Scout: Added {prospect.full_name()} ({prospect.title}) at {prospect.company} [backfill]",
            );
            if count >= MAX_PROSPECTS_PER_CYCLE {
                return count;
            }
        }
    }
    return count;
}

impl Scout._prospect_via_linkedin -> int {
    logger.info("Scout: Searching LinkedIn...");
    linkedin = LinkedInAutomation(self.env.linkedin_email, self.env.linkedin_password);
    try {
        await linkedin.start();
        if not await linkedin.login() {
            logger.warning("Scout: LinkedIn login failed. Skipping.");
            return 0;
        }
        count = 0;
        for title in self.config.icp.titles {
            for industry in self.config.icp.industries {
                keywords = f"{title} {industry}";
                try {
                    profiles = await linkedin.search_people(keywords=keywords, max_results=10);
                } except Exception as e {
                    logger.debug(f"LinkedIn search failed for '{keywords}': {e}");
                    continue;
                }
                for profile in profiles or [] {
                    if not isinstance(profile, dict) {
                        continue;
                    }
                    prospect = await self._linkedin_prospect(profile, title, industry);
                    if await self._keep(prospect) {
                        count += 1;
                        logger.info(
                            f"Scout: Added prospect {prospect.full_name()} at {prospect.company}"
                        );
                        if count >= MAX_PROSPECTS_PER_CYCLE {
                            return count;
                        }
                    }
                }
            }
        }
        return count;
    } finally {
        try {
            await linkedin.stop();
        } except Exception as e {
            logger.debug(f"LinkedIn stop failed: {e}");
        }
    }
}

impl Scout._linkedin_prospect(profile: dict[str, any], title: str, industry: str) -> Prospect {
    (first_name, last_name) = (
        (profile.get("first_name") or "").strip(),
        (profile.get("last_name") or "").strip(),
    );
    p_title = (profile.get("title") or title).strip();
    company_name = (profile.get("company") or "").strip();
    li_url = (profile.get("linkedin_url") or "").strip();
    (domain, company_id, email, email_status) = ("", "", "", "");
    if company_name {
        try {
            domain = await self._guess_domain(company_name);
        } except Exception {
            domain = "";
        }
        if domain {
            company_id = await self._ensure_company(
                name=company_name, domain=domain, industry=industry, source="linkedin_search"
            );
        }
    }
    if domain and first_name and last_name {
        (email, email_status) = await self._resolve_email(first_name, last_name, domain);
    }
    return Prospect(
        first_name=first_name,
        last_name=last_name,
        email=email,
        email_status=email_status,
        email_verified=email_status == "verified",
        linkedin_url=li_url,
        company=company_name,
        company_id=company_id,
        title=p_title,
        seniority=self._infer_seniority(p_title),
        industry=industry,
        source="linkedin_search",
        source_url=li_url,
    );
}

impl Scout._prospect_via_profile_search -> int {
    logger.info("Scout: Searching for LinkedIn profiles...");
    count = 0;
    geo = self.config.icp.geography[0] if self.config.icp.geography else "";
    industry = self._default_industry();
    for title in self.config.icp.titles {
        if self._queries_this_cycle >= MAX_QUERIES_PER_CYCLE {
            break;
        }
        query = f"site:linkedin.com/in \"{title}\""
            + (f" \"{industry}\"" if industry else "")
            + (f" \"{geo}\"" if geo else "");
        for (url, snippet) in await self._web_search(query) {
            parsed = self._parse_linkedin_url(url, snippet) if "/in/" in url else None;
            if not parsed {
                continue;
            }
            prospect = Prospect(
                first_name=parsed.get("first_name", ""),
                last_name=parsed.get("last_name", ""),
                linkedin_url=url,
                title=title,
                seniority=self._infer_seniority(title),
                industry=industry,
                source="web_search",
                source_url=url,
            );
            if await self._keep(prospect) {
                count += 1;
                if count >= 15 {
                    return count;
                }
            }
        }
    }
    return count;
}

impl Scout._prospect_via_company_discovery -> int {
    logger.info("Scout: Discovering companies...");
    companies: list[dict[str, any]] = [];
    for (label, find) in (
        ("Company search", self._find_companies_via_search),
        ("Directory discovery", self._find_companies_via_directories),
    ) {
        try {
            companies.extend(await find());
        } except Exception as e {
            logger.debug(f"{label} failed: {e}");
        }
    }
    if not companies {
        logger.info("Scout: No new companies found this cycle.");
        return 0;
    }
    seen: set[str] = set();
    unique: list[dict[str, any]] = [];
    for c in companies {
        domain = (c.get("domain") or "").lower();
        if not domain or domain in seen {
            continue;
        }
        seen.add(domain);
        if self._listed(domain) {
            continue;
        }
        unique.append(c);
    }
    companies = unique[:MAX_COMPANIES_PER_CYCLE];
    logger.info(f"Scout: Found {len(companies)} candidate companies.");
    all_contacts: list[Prospect] = [];
    for company in companies {
        domain = company["domain"];
        industry = company.get("industry", self._default_industry());
        name = company.get("name") or self._domain_to_name(domain);
        company_id = await self._ensure_company(
            name=name,
            domain=domain,
            website=company.get("website", f"https://{domain}"),
            description=company.get("description", ""),
            industry=industry,
            source=company.get("source", "web_search"),
            source_url=company.get("source_url", ""),
        );
        signal_note = "";
        try {
            signal_note = await self._enrich_company_signals(
                company_id, domain, homepage_html=company.get("_homepage_html", "")
            );
        } except Exception as e {
            logger.debug(f"Signal enrichment failed for {domain}: {e}");
        }
        all_contacts.extend(
            await self._contacts_from_company(
                company_id=company_id,
                domain=domain,
                company_name=name,
                industry=industry,
                signal_note=signal_note,
                source="company_website",
            ),
        );
    }
    if not all_contacts {
        logger.info("Scout: No ICP-matching contacts found on team pages.");
        return 0;
    }
    return await self._add_scored(all_contacts, "");
}

impl Scout._add_scored(contacts: list[Prospect], how: str) -> int {
    count = 0;
    for prospect in await self._score_contacts(contacts) {
        await self.state.add_prospect(prospect);
        count += 1;
        logger.info(
            f"Scout: Added {prospect.full_name()} ({prospect.title}) at {prospect.company} {how}[score: {prospect.score}]",
        );
        if count >= MAX_PROSPECTS_PER_CYCLE {
            break;
        }
    }
    return count;
}

impl Scout._claim_domain(domain: str) -> bool {
    if not self._is_candidate_domain(domain) {
        return False;
    }
    known = await self.state.company_exists(domain);
    self._seen_domains.add(domain);
    return not known;
}

impl Scout._company_info(domain: str, source: str, url: str) -> dict[str, any] {
    info = await self._scrape_company_info(domain);
    info.update({"domain": domain, "source": source, "source_url": url});
    if not info.get("name") {
        info["name"] = self._domain_to_name(domain);
    }
    return info;
}

impl Scout._find_companies_via_search -> list[dict[str, any]] {
    companies: list[dict[str, any]] = [];
    for query in self._build_company_search_queries() {
        if self._queries_this_cycle >= MAX_QUERIES_PER_CYCLE {
            break;
        }
        for (url, snippet) in await self._web_search(query) {
            domain = self._extract_domain(url);
            if await self._claim_domain(domain) {
                companies.append(await self._company_info(domain, "web_search", url));
                if len(companies) >= 5 {
                    return companies;
                }
            }
        }
    }
    return companies;
}

impl Scout._find_companies_via_directories -> list[dict[str, any]] {
    companies: list[dict[str, any]] = [];
    industries = self.config.icp.industries or [];
    directory_queries: list[str] = [];
    for industry in industries[:2] {
        directory_queries.extend([
            f"site:g2.com/categories \"{industry}\"",
            f"site:clutch.co \"{industry}\" companies",
            f"\"{industry}\" company directory list",
        ]);
    }
    for query in directory_queries {
        if self._queries_this_cycle >= MAX_QUERIES_PER_CYCLE {
            break;
        }
        for (url, snippet) in await self._web_search(query) {
            for domain in self._extract_company_domains_from_snippet(snippet, url) {
                if await self._claim_domain(domain) {
                    companies.append(await self._company_info(domain, "directory", url));
                    if len(companies) >= 5 {
                        return companies;
                    }
                }
            }
            if len(companies) < 5 {
                for pc in await self._scrape_directory_page(url) {
                    if await self._claim_domain(pc.get("domain", "")) {
                        companies.append(pc);
                        if len(companies) >= 5 {
                            return companies;
                        }
                    }
                }
            }
        }
    }
    return companies;
}

impl Scout._is_candidate_domain(domain: str) -> bool {
    return bool(domain)
        and len(domain) >= 4
        and domain not in self._seen_domains
        and not self._is_noise_domain(domain);
}

impl Scout._scrape_directory_page(url: str) -> list[dict[str, any]] {
    resp = await self._fetch(url, timeout=SCRAPE_TIMEOUT, retries=2);
    soup = self._safe_soup(resp.text) if resp is not None else None;
    if soup is None {
        return [];
    }
    companies: list[dict[str, any]] = [];
    page_domain = self._extract_domain(url);
    seen_here: set[str] = set();
    try {
        for link in soup.find_all("a", href=True) {
            href = self._attr_str(link.get("href"));
            domain = self._extract_domain(href) if href.startswith("http") else "";
            if not domain
                or self._is_noise_domain(domain)
                or domain == page_domain
                or domain in seen_here
            {
                continue;
            }
            link_text = link.get_text().strip();
            if 3 < len(link_text) and len(link_text) < 60 {
                seen_here.add(domain);
                companies.append({
                    "name": link_text,
                    "domain": domain,
                    "website": f"https://{domain}",
                    "source": "directory",
                    "source_url": url,
                });
            }
            if len(companies) >= 10 {
                break;
            }
        }
    } except Exception as e {
        logger.debug(f"Failed to parse directory page {url}: {e}");
    }
    return companies;
}

impl Scout._extract_company_domains_from_snippet(snippet: str, source_url: str) -> list[str] {
    if not snippet {
        return [];
    }
    found: list[str] = re.findall(
        r"\b([a-zA-Z0-9][a-zA-Z0-9-]*\.(?:com|io|co|net|org|ai))\b", snippet
    );
    domains = [d.lower() for d in found if not self._is_noise_domain(d.lower()) and len(d) > 5];
    return list(dict.fromkeys(domains))[:5];
}

impl Scout._build_company_search_queries -> list[str] {
    queries: list[str] = [];
    geos = self.config.icp.geography or [""];
    size = self.config.icp.company_size or "";
    geo = geos[0] if geos else "";
    for industry in (self.config.icp.industries or [""])[:2] {
        parts = [f"\"{p}\"" for p in (industry, geo, size) if p] + ["company"];
        queries.append(" ".join(parts));
        if geo and industry {
            queries.append(f"top \"{industry}\" companies {geo}");
        }
    }
    cleaned = [q.strip() for q in queries];
    return [q for q in dict.fromkeys(cleaned) if q and q != "company"][:3];
}

impl Scout._resolve_email(first_name: str, last_name: str, domain: str) -> tuple[str, str] {
    if not (first_name and last_name and domain) {
        return ("", "invalid");
    }
    evidence: any = getattr(self, "_site_evidence", {}).get(self._host(domain), {});
    options: dict[str, any] = {"default_pattern": evidence.get("default", DEFAULT_PATTERN)};
    if evidence.get("known") {
        options["known_emails"] = evidence["known"];
    }
    if evidence.get("people") {
        options["other_people"] = evidence["people"];
    }
    try {
        result = await find_email(
            first_name, last_name, domain, verify=True, env=self.env, state=self.state, **options
        );
    } except Exception as e {
        logger.debug(f"find_email failed for {domain}: {e}");
        return ("", "invalid");
    }
    return (result.email, result.status);
}

impl Scout._score_contacts(contacts: list[Prospect]) -> list[Prospect] {
    if not contacts {
        return contacts;
    }
    for c in contacts {
        c.score = self._heuristic_score(c);
    }
    summaries = "\n".join(_prospect_line(i, c) for (i, c) in enumerate(contacts));
    icp = self.config.icp;
    prompt = f"""You are analyzing a batch of sales prospects that have already been found and verified.
Your job is to score each one (1-100) based on how well they match the ICP, and add a short personalization note.

Our product: {self.config.product.description}
Target industries: {', '.join(icp.industries)}
Target titles: {', '.join(icp.titles)}
Target company size: {icp.company_size}

Here are the prospects to score, as found on the web:
{fence(summaries, "found prospects")}

{UNTRUSTED_RULE}

Return a JSON array with one object per prospect, in the same order:
[{{"index": 1, "score": 75, "personalization": "Short angle for outreach"}}, ...]

Score criteria:
- 80-100: Perfect ICP match, right title, right industry, right company size
- 60-79: Good match, close to ICP
- 40-59: Partial match, might be worth a shot
- 1-39: Poor match, probably skip

Respond ONLY with the JSON array.""";
    try {
        result = await self.brain.think_json(
            prompt, session_id="sellbird-scout-score", agent="scout", task="score_contacts"
        );
    } except Exception as e {
        logger.warning(f"Scout: Claude scoring errored ({e}); using heuristic scores.");
        result = None;
    }
    if isinstance(result, list) {
        for item in result {
            if not isinstance(item, dict) {
                continue;
            }
            try {
                idx = int(item.get("index", 0)) - 1;
            } except (TypeError, ValueError) {
                continue;
            }
            if idx < 0 or idx >= len(contacts) {
                continue;
            }
            try {
                score = int(item.get("score", contacts[idx].score));
            } except (TypeError, ValueError) {
                score = contacts[idx].score;
            }
            contacts[idx].score = max(1, min(100, score));
            note = item.get("personalization", "");
            if isinstance(note, str) {
                contacts[idx].personalization_notes = note.strip()[:500];
            }
        }
    } else {
        logger.warning("Scout: Claude scoring failed, using heuristic scores.");
    }
    kept = [c for c in contacts if c.score >= 30];
    kept.sort(key=lambda (c: any) -> int { c.score }, reverse=True);
    return kept;
}

impl Scout._heuristic_score(contact: Prospect) -> int {
    score = 40
        + (25 if self._title_matches_icp(contact.title) else 0)
        + _SENIORITY_BONUS.get(contact.seniority, 0);
    industry = (contact.industry or "").lower();
    if industry
        and self.config.icp.industries
        and any(
            ind.lower() in industry or industry in ind.lower() for ind in self.config.icp.industries
        )
    {
        score += 10;
    }
    score += {"verified": 8, "risky": 3}.get(contact.email_status, 1 if contact.email else 0);
    if "Signal: hiring" in (contact.personalization_notes or "") {
        score += 10;
    }
    return max(1, min(100, score));
}

impl Scout._ensure_company(name: str, domain: str, website: str = "", **fields: any) -> str {
    try {
        existing = await self.state.get_company_by_domain(domain);
        if existing {
            return existing.id;
        }
    } except Exception as e {
        logger.debug(f"get_company_by_domain failed for {domain}: {e}");
    }
    return await self.state.add_company(
        Company(name=name, domain=domain, website=website or f"https://{domain}", **fields)
    );
}

impl Scout._resolve_base_url(domain: str, retries: int = 1) -> tuple[str, any] {
    for base in _variants(domain) {
        resp = await self._fetch(base, timeout=SCRAPE_TIMEOUT, retries=retries);
        if resp is not None {
            return (base, resp);
        }
        if self.challenged(domain) {
            logger.info(
                f"Scout: {domain} answered with a bot challenge; skipped as challenged, not unreachable.",
            );
            break;
        }
    }
    return ("", None);
}

impl Scout._scrape_company_info(domain: str) -> dict[str, any] {
    info: dict[str, any] = {"name": "", "description": "", "website": f"https://{domain}"};
    (base, resp) = await self._resolve_base_url(domain, retries=2);
    if resp is None {
        return info;
    }
    info["website"] = base;
    info["_homepage_html"] = resp.text;
    soup = self._safe_soup(resp.text);
    if soup is None {
        return info;
    }
    try {
        title_tag = soup.find("title");
        name = re.split(r"[|—–\-:]", title_tag.get_text().strip())[0].strip() if title_tag else "";
        if name {
            info["name"] = name[:120];
        }
        info["description"] = self._meta(soup, "name", "description")[:500];
        og = self._meta(soup, "property", "og:site_name");
        if og {
            info["name"] = og[:120];
        }
        if not info["description"] {
            info["description"] = self._meta(soup, "property", "og:description")[:500];
        }
    } except Exception as e {
        logger.debug(f"Failed to parse company info for {domain}: {e}");
    }
    return info;
}

impl Scout._meta(soup: any, attr: str, value: str) -> str {
    tag = soup.find("meta", attrs={attr: value});
    return self._attr_str(tag.get("content")).strip() if tag and tag.get("content") else "";
}

impl Scout._read_site(domain: str) -> dict[str, any] {
    cache = vars(self).setdefault("_site_reads", {});
    key = self._host(domain);
    if key in cache {
        return cache[key];
    }
    site: dict[str, any] = {
        "base": "",
        "pages": [],
        "tried": set[str](),
        "challenged": False,
        "fetches": 0,
    };
    cache[key] = site;
    if self.challenged(key) {
        site["challenged"] = True;
        return site;
    }
    (base, home) = await self._resolve_base_url(domain);
    variants = _variants(domain);
    site["fetches"] = variants.index(base) + 1 if base in variants else len(variants);
    if not base or home is None {
        site["challenged"] = self.challenged(key);
        return site;
    }
    home_text = getattr(home, "text", "") or "";
    home_url = str(getattr(home, "url", "") or base);
    site["base"] = base;
    site["pages"].append((home_url, home_text));
    norm = people_mod._norm_url;
    seen = {norm(home_url), norm(base)};
    site["tried"] |= seen;
    links = people_mod.menu_links(home_text, home_url, limit=MAX_SITE_PAGES - 1);
    if len(links) < 2 {
        links += [f"{base}{p}" for p in FALLBACK_SITE_PATHS];
    }
    for url in links {
        if len(site["pages"]) >= MAX_SITE_PAGES {
            break;
        }
        if norm(url) in seen {
            continue;
        }
        seen.add(norm(url));
        site["tried"].add(norm(url));
        resp = await self._site_fetch(site, url);
        if resp is None {
            if self.challenged(key) or site["fetches"] >= MAX_SITE_FETCHES {
                break;
            }
            continue;
        }
        final = str(getattr(resp, "url", "") or url);
        text = getattr(resp, "text", "") or "";
        if self._host(final) == key
            and norm(final) not in (norm(home_url), norm(base))
            and text != home_text
            and norm(final) not in [norm(u) for (u, _) in site["pages"]]
        {
            site["pages"].append((final, text));
        }
    }
    return site;
}

impl Scout._site_fetch(site: dict[str, any], url: str) -> any {
    if site.get("fetches", 0) >= MAX_SITE_FETCHES {
        return None;
    }
    site["fetches"] = site.get("fetches", 0) + 1;
    return await self._fetch(url, timeout=SCRAPE_TIMEOUT, retries=1);
}

impl Scout._scrape_team_page(domain: str) -> list[dict[str, any]] {
    site = await self._read_site(domain);
    if not site["pages"] {
        return [];
    }
    site_name = site_name_from_html(site["pages"][0][1], domain);
    found: list[any] = [];
    try {
        found = people_mod.find_people(site["pages"], domain, site_name);
    } except Exception as e {
        logger.debug(f"People detection failed for {domain}: {e}");
        found = [];
    }
    if not found {
        found = self._people_from_cards(site["pages"]);
    }
    addresses: list[str] = [];
    for (_, html) in site["pages"] {
        for addr in people_mod.emails_on_page(html) {
            if addr not in addresses {
                addresses.append(addr);
            }
        }
    }
    site["addresses"] = addresses;
    await self._learn_email_evidence(domain, addresses, found);
    return found;
}

impl Scout._learn_email_evidence(domain: str, addresses: list[str], found: list[dict[str, any]]) {
    key = self._host(domain);
    named: list[tuple[str, str]] = [(p["first_name"], p["last_name"]) for p in found];
    (known, pattern, confidence) = site_email_evidence(addresses, named, key);
    vars(self).setdefault("_site_evidence", {})[key] = {
        "known": known,
        "people": named,
        "default": SMALL_BUSINESS_PATTERN if await self._known_small(key) else DEFAULT_PATTERN,
    };
    if pattern {
        try {
            await self.state.save_email_pattern(
                key,
                pattern=pattern,
                confidence=confidence,
                source="site_address" if known else "site_address_guess",
            );
            logger.debug(f"Scout: learned pattern {pattern} for {key} ({confidence:.2f})");
        } except Exception as e {
            logger.debug(f"save_email_pattern failed: {e}");
        }
    }
}

impl Scout._known_small(domain: str) -> bool {
    icp = getattr(vars(self).get("config"), "icp", None);
    if _small(getattr(icp, "company_size", "") or "") {
        return True;
    }
    try {
        company = await self.state.get_company_by_domain(domain);
    } except Exception {
        company = None;
    }
    if company is None {
        return False;
    }
    return _small(getattr(company, "company_size", "") or "")
        or (getattr(company, "source", "") or "") in LOCAL_BUSINESS_SOURCES;
}

impl Scout._people_from_cards(pages: list[tuple[str, str]]) -> list[dict[str, any]] {
    members: list[dict[str, any]] = [];
    seen: set[tuple[str, str]] = set();
    for (url, html) in pages {
        soup = self._safe_soup(html);
        if soup is None {
            continue;
        }
        try {
            cards = soup.select(
                ".team-member, .person, .staff, [class*='team'], [class*='leadership'], [class*='member'], [class*='person']",
            );
        } except Exception {
            cards = [];
        }
        for card in cards {
            name_el = card.select_one("h2, h3, h4, .name, [class*='name']");
            split = people_mod.split_person_name(re.sub(r"\s+", " ", name_el.get_text()))
                if name_el
                else None;
            if not split or (split[0].lower(), split[1].lower()) in seen {
                continue;
            }
            title = _card_title(card, name_el.get_text().strip());
            seen.add((split[0].lower(), split[1].lower()));
            owner = people_mod.is_owner_title(title);
            members.append({
                "first_name": split[0],
                "last_name": split[1],
                "title": title[:120],
                "owner": owner,
                "rank": people_mod.owner_rank(title, owner),
                "source": "card",
                "evidence": f"{split[0]} {split[1]} — {title}",
                "evidence_url": url,
            });
        }
    }
    members.sort(key=lambda (m: dict[str, any]) -> int { -m["rank"] });
    return members;
}

impl Scout._contacts_from_company(
    company_id: str,
    domain: str,
    company_name: str,
    industry: str,
    signal_note: str = "",
    source: str = "company_website",
) -> list[Prospect] {
    try {
        team_members = await self._scrape_team_page(domain);
    } except Exception as e {
        logger.debug(f"Team scrape failed for {domain}: {e}");
        return [];
    }
    contacts: list[Prospect] = [];
    named_on_site = False;
    considered = 0;
    for member in sorted(
        team_members, key=lambda (m: dict[str, any]) -> int { -(m.get("rank") or 0) }
    ) {
        title = member.get("title", "");
        owner = bool(member.get("owner"));
        (first_name, last_name) = (member.get("first_name", ""), member.get("last_name", ""));
        if not (self._title_matches_icp(title) or (owner and self._icp_wants_owner()))
            or not first_name
            or not last_name
        {
            continue;
        }
        named_on_site = True;
        if considered >= MAX_CONTACTS_PER_COMPANY {
            break;
        }
        considered += 1;
        (email, email_status) = await self._resolve_email(first_name, last_name, domain);
        prospect = Prospect(
            first_name=first_name,
            last_name=last_name,
            email=email,
            email_status=email_status,
            email_verified=email_status == "verified",
            company=company_name,
            company_id=company_id,
            title=title or ("Owner" if owner else ""),
            seniority="c_suite" if owner else self._infer_seniority(title),
            industry=industry,
            source=source,
            source_url=member.get("evidence_url") or f"https://{domain}",
            personalization_notes=signal_note,
        );
        if not prospect.is_valid() or await self._is_duplicate_prospect(prospect) {
            continue;
        }
        self._remember_prospect(prospect);
        contacts.append(prospect);
        if owner {
            await self._observe_likely_owner(company_id, member);
        }
    }
    reachable = any(c.email_status in ("verified", "risky") for c in contacts);
    if not reachable
        and (contacts or not named_on_site)
        and await self._company_uncontacted(company_id)
    {
        inbox = await self._company_inbox_prospect(
            company_id, domain, company_name, industry, signal_note
        );
        if inbox {
            contacts.append(inbox);
        }
    }
    return contacts;
}

impl Scout._observe_likely_owner(company_id: str, member: dict[str, any]) {
    if not company_id {
        return;
    }
    try {
        confirmed = await self.state.confirmed_signal_codes();
    } except Exception {
        return;
    }
    if "LIKELY_OWNER" not in (confirmed or set[str]()) {
        return;
    }
    name = f"{member.get('first_name', '')} {member.get('last_name', '')}".strip();
    explicit = people_mod.is_owner_title(member.get("title", ""));
    evidence = member.get("evidence") or "";
    try {
        await self.state.add_observations([
            {
                "signal_code": "LIKELY_OWNER",
                "company_id": company_id,
                "collector": "people",
                "value_num": 1,
                "value_text": f"{name} — {member.get('title') or 'owner'}: {evidence}"[:300],
                "confidence": 0.9 if explicit else 0.7,
                "evidence_url": member.get("evidence_url", ""),
            },
        ]);
    } except Exception as e {
        logger.debug(f"LIKELY_OWNER observation failed for {company_id}: {e}");
    }
}

impl Scout._company_uncontacted(company_id: str) -> bool {
    if not company_id {
        return False;
    }
    try {
        return not await self.state.get_contacts_for_company(company_id);
    } except Exception as e {
        logger.debug(f"Contact lookup failed for company {company_id}: {e}");
        return False;
    }
}

impl Scout._company_inbox_prospect(
    company_id: str, domain: str, company_name: str, industry: str, signal_note: str = ""
) -> Prospect | None {
    email = await self._find_inbox_address(domain);
    if not email {
        return None;
    }
    try {
        status = await verify_published_address(email, env=self.env);
    } except Exception as e {
        logger.debug(f"Inbox verification failed for {email}: {e}");
        status = "guess";
    }
    prospect = Prospect(
        email=email,
        email_status=status,
        email_verified=status == "verified",
        company=company_name,
        company_id=company_id,
        title="General inbox",
        industry=industry,
        source=COMPANY_INBOX_SOURCE,
        source_url=f"https://{domain}",
        personalization_notes=signal_note,
    );
    if not prospect.is_valid() or await self._is_duplicate_prospect(prospect) {
        return None;
    }
    self._remember_prospect(prospect);
    logger.info(f"Scout: No named owner at {domain}; using its published inbox {email} [{status}]");
    return prospect;
}

impl Scout._find_inbox_address(domain: str) -> str {
    site = await self._read_site(domain);
    if not site["base"] {
        return "";
    }
    domain = self._host(domain);
    pages = list(site["pages"]);
    if not any("contact" in url.lower() for (url, _) in pages[1:]) {
        for path in INBOX_PAGES {
            url = f"{site['base']}{path}";
            if people_mod._norm_url(url) in site["tried"] {
                continue;
            }
            site["tried"].add(people_mod._norm_url(url));
            resp = await self._site_fetch(site, url);
            if resp is not None {
                pages.append((url, getattr(resp, "text", "") or ""));
            }
        }
    }
    candidates: list[str] = [];
    for (_, text) in pages {
        for addr in people_mod.emails_on_page(text) {
            (local, _, adomain) = addr.partition("@");
            if local not in INBOX_PREFERRED or addr in candidates {
                continue;
            }
            adomain = adomain.removeprefix("www.");
            if adomain == domain
                or adomain.endswith("." + domain)
                or await self._is_own_domain(adomain, site)
            {
                candidates.append(addr);
            }
        }
    }
    return min(
        candidates,
        key=lambda (a: str) -> int { INBOX_PREFERRED.index(a.partition("@")[0]) },
        default="",
    );
}

impl Scout._is_own_domain(other: str, site: dict[str, any]) -> bool {
    cache = vars(self).setdefault("_own_domains", {});
    if other in cache {
        return cache[other];
    }
    cache[other] = False;
    if not re.fullmatch(r"[a-z0-9\-]+(?:\.[a-z0-9\-]+)+", other or "") {
        return False;
    }
    resp = await self._site_fetch(site, f"https://{other}");
    if resp is not None {
        landed = self._host(str(getattr(resp, "url", "") or f"https://{other}"));
        cache[other] = landed == self._host(site["base"]) and landed != other;
    }
    return cache[other];
}

impl Scout._prospect_via_hiring_boards -> int {
    try {
        scrape_jobs = importlib.import_module("jobspy").scrape_jobs;
    } except ImportError {
        logger.debug("Scout: python-jobspy not installed; skipping job boards.");
        return 0;
    }
    keywords = self._signal_role_keywords();
    if not keywords {
        return 0;
    }
    search_term = keywords[0];
    geo = self.config.icp.geography[0] if self.config.icp.geography else "";
    logger.info(f"Scout: Searching job boards for '{search_term}' roles...");
    loop = asyncio.get_event_loop();
    search = functools.partial(
        scrape_jobs,
        site_name=["indeed"],
        search_term=search_term,
        location=geo,
        results_wanted=15,
        hours_old=24 * 14,
    );
    try {
        df = await asyncio.wait_for(loop.run_in_executor(None, search), timeout=120);
    } except Exception as e {
        logger.warning(f"Scout: job-board search failed: {e}");
        return 0;
    }
    if df is None or getattr(df, "empty", True) {
        return 0;
    }
    default_industry = self._default_industry();
    today = datetime.now(timezone.utc).date().isoformat();
    all_contacts: list[Prospect] = [];
    companies_used = 0;
    try {
        rows = df.to_dict("records");
    } except Exception {
        return 0;
    }
    seen_names: set[str] = set();
    for row in rows {
        if companies_used >= 5 {
            break;
        }
        company_name = str(row.get("company") or "").strip();
        job_title = str(row.get("title") or "").strip()[:80];
        if not company_name or company_name.lower() in seen_names {
            continue;
        }
        seen_names.add(company_name.lower());
        try {
            domain = await self._guess_domain(company_name);
        } except Exception {
            domain = "";
        }
        if not self._is_candidate_domain(domain) {
            continue;
        }
        if self._listed(domain) {
            continue;
        }
        if not await self._claim_domain(domain) {
            continue;
        }
        companies_used += 1;
        info = await self._scrape_company_info(domain);
        name = info.get("name") or company_name;
        company_id = await self._ensure_company(
            name=name,
            domain=domain,
            website=info.get("website", f"https://{domain}"),
            description=info.get("description", ""),
            industry=default_industry,
            source="job_board",
            source_url=str(row.get("job_url") or ""),
        );
        try {
            await self.state.update_company_signals(
                company_id, new_signals=[{"type": "hiring", "detail": job_title, "found_at": today}]
            );
        } except Exception as e {
            logger.debug(f"update_company_signals failed: {e}");
        }
        signal_note = f"Signal: hiring {job_title} (posted on job board)";
        tech = detect_tech(info.get("_homepage_html", ""));
        if tech {
            await self.state.update_company_signals(company_id, tech_stack=tech);
            signal_note += ". Tech on site: " + ", ".join(tech[:5]);
        }
        all_contacts.extend(
            await self._contacts_from_company(
                company_id=company_id,
                domain=domain,
                company_name=name,
                industry=default_industry,
                signal_note=signal_note[:400],
                source="job_board",
            ),
        );
    }
    if not all_contacts {
        logger.info("Scout: job-board sweep found no ICP-matching contacts.");
        return 0;
    }
    return await self._add_scored(all_contacts, "via job-board signal ");
}

impl Scout._signal_role_keywords -> list[str] {
    return role_keywords(self.config.icp);
}

impl Scout._enrich_company_signals(company_id: str, domain: str, homepage_html: str = "") -> str {
    if not homepage_html {
        resp = await self._fetch(f"https://{domain}", timeout=SCRAPE_TIMEOUT, retries=1);
        homepage_html = resp.text if resp is not None else "";
    }
    tech = detect_tech(homepage_html);
    try {
        hiring_roles = await self._scrape_hiring_signals(domain);
    } except Exception as e {
        logger.debug(f"Hiring scan failed for {domain}: {e}");
        hiring_roles = [];
    }
    today = datetime.now(timezone.utc).date().isoformat();
    signals = [{"type": "hiring", "detail": role, "found_at": today} for role in hiring_roles];
    if tech or signals {
        try {
            await self.state.update_company_signals(
                company_id, tech_stack=tech, new_signals=signals
            );
        } except Exception as e {
            logger.debug(f"update_company_signals failed for {domain}: {e}");
        }
    }
    notes = (["Signal: hiring " + ", ".join(hiring_roles[:2])] if hiring_roles else [])
        + (["Tech on site: " + ", ".join(tech[:5])] if tech else []);
    note = ". ".join(notes);
    if note {
        logger.info(f"Scout: signals for {domain} — {note}");
    }
    return note[:400];
}

impl Scout._scrape_hiring_signals(domain: str) -> list[str] {
    keywords = self._signal_role_keywords();
    if not keywords {
        return [];
    }
    for path in _CAREERS_PATHS {
        resp = await self._fetch(f"https://{domain}{path}", timeout=SCRAPE_TIMEOUT, retries=1);
        soup = self._safe_soup(resp.text) if resp is not None else None;
        if soup is None {
            continue;
        }
        roles: list[str] = [];
        seen: set[str] = set();
        try {
            elements = soup.select("a, h2, h3, h4, li");
        } except Exception {
            elements = [];
        }
        for el in elements[:400] {
            text = re.sub(r"\s+", " ", el.get_text()).strip();
            low = text.lower();
            if len(text) < 4 or len(text) > 80 or not _mentions(low, keywords) or low[:60] in seen {
                continue;
            }
            seen.add(low[:60]);
            roles.append(text[:80]);
            if len(roles) >= 3 {
                return roles;
            }
        }
        return roles;
    }
    return [];
}

impl Scout._guess_domain(company_name: str) -> str {
    name = company_name.lower().strip();
    for suffix in [
        " inc",
        " llc",
        " ltd",
        " corp",
        " co",
        " group",
        " incorporated",
        " limited",
        " company",
    ] {
        if name.endswith(suffix) {
            name = name[:-len(suffix)];
        }
    }
    name = re.sub(r"[^a-z0-9]", "", name);
    if not name {
        return "";
    }
    for tld in (".com", ".io", ".co") {
        resp = await self._fetch(f"https://{name}{tld}", method="HEAD", timeout=6, retries=1);
        if resp is not None and resp.status_code < 400 {
            return f"{name}{tld}";
        }
    }
    return "";
}

impl Scout._extract_domain(url: str) -> str {
    if not url {
        return "";
    }
    try {
        parsed = urlparse(url if "://" in url else "http://" + url);
        host = (parsed.netloc or parsed.path.split("/")[0]).split("@")[-1].split(":")[0];
        host = re.sub(r"^www\.", "", host.lower());
        if "." in host and len(host) > 3 {
            return host;
        }
    } except Exception {}
    return "";
}

impl Scout._is_noise_domain(domain: str) -> bool {
    return domain in _NOISE_DOMAINS or _noise_subdomain(domain);
}

impl Scout._domain_to_name(domain: str) -> str {
    return domain.split(".")[0].replace("-", " ").title() if domain else "";
}

impl Scout._title_matches_icp(title: str) -> bool {
    if not title {
        return False;
    }
    if self.config.icp.titles {
        return people_mod.title_matches(title, self.config.icp.titles);
    }
    title_lower = fold_accents(title).lower();
    return any(
        re.search(r"(?<![\w-])" + re.escape(kw) + r"\b", title_lower) for kw in _SENIOR_KEYWORDS
    );
}

impl Scout._icp_wants_owner -> bool {
    titles = self.config.icp.titles;
    return not titles or people_mod.title_matches("", titles, owner=True);
}

impl Scout._infer_seniority(title: str) -> str {
    if not title {
        return "";
    }
    t = fold_accents(title).lower();
    deputy = re.search(r"\b(?:adjointe?|assistante?|sous-\w+)\b", t);
    vice = re.search(r"\bvice[- ]president", t);
    if not deputy
        and (
            (_mentions(t, _C_SUITE_WORDS) and not vice)
            or re.search(r"\bdirect(?:eur|rice) generale?\b", t)
        )
    {
        return "c_suite";
    }
    if vice or _mentions(t, ("vp", "svp", "evp", "head of")) {
        return "vp";
    }
    if _mentions(t, ("director", "directeur", "directrice")) {
        return "director";
    }
    return "manager" if _mentions(t, _MANAGER_WORDS) else "individual";
}

impl Scout._parse_linkedin_url(url: str, snippet: str) -> dict[str, str] | None {
    name_match = re.match(r"^\s*([A-Z][a-z]+)\s+([A-Z][a-z'\-]+)", snippet.strip())
        if snippet
        else None;
    if name_match {
        return {"first_name": name_match.group(1), "last_name": name_match.group(2)};
    }
    slug_match = re.search(r"/in/([\w][\w-]+)", url);
    if not slug_match {
        return None;
    }
    slug = re.sub(r"-\d+$", "", re.sub(r"-[0-9a-f]{4,}$", "", slug_match.group(1)));
    parts = [p for p in slug.split("-") if p and not p.isdigit()];
    if len(parts) < 2 {
        return None;
    }
    return {"first_name": parts[0].title(), "last_name": " ".join(p.title() for p in parts[1:])};
}

impl _variants(domain: str) -> list[str] {
    return [
        f"https://{domain}",
        f"https://www.{domain}",
        f"http://{domain}",
        f"http://www.{domain}",
    ];
}

impl _unwrap_ddg(href: str) -> str {
    if "uddg=" in href {
        try {
            real = parse_qs(urlparse(href).query).get("uddg", []);
            if real {
                return real[0];
            }
        } except Exception {}
    }
    return href;
}

impl _mentions(text: str, words: any) -> bool {
    return any(w in text for w in words);
}

impl _noise_subdomain(domain: str) -> bool {
    return any(domain.endswith(f".{n}") for n in _NOISE_DOMAINS);
}

impl _card_title(card: any, name_text: str) -> str {
    for el in card.select(
        ".title, .role, .position, [class*='title'], [class*='role'], [class*='position'], p, span"
    ) {
        text = re.sub(r"\s+", " ", el.get_text()).strip();
        if text and text != name_text and len(text) <= 80 and _reads_like_title(text) {
            return text;
        }
    }
    return "";
}

impl _small(text: str) -> bool {
    nums = [int(n.replace(",", "")) for n in re.findall(r"\d[\d,]*", text or "")];
    return bool(nums) and max(nums) <= SMALL_COMPANY_MAX;
}

impl _prospect_line(i: int, c: any) -> str {
    return f"{i + 1}. {c.full_name()} — {c.title} at {c.company} ({c.industry}). Email: {c.email or 'none'}. Seniority: {c.seniority or 'unknown'}.";
}
