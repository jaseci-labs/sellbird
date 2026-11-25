impl normalize_domain(url_or_domain: str) -> str {
    if not url_or_domain {
        return "";
    }
    raw = url_or_domain.strip().lower();
    host = (urlparse(raw if "://" in raw else "http://" + raw).hostname or "").strip(".");
    return host[4:] if host.startswith("www.") else host;
}

impl _words(text: str) -> list[str] {
    return [w for w in re.findall(r"[a-z0-9]+", text.lower()) if w];
}

impl _domain_stem(domain: str) -> str {
    host = normalize_domain(domain);
    return re.sub(r"[^a-z0-9]", "", host.rsplit(".", 1)[0]) if host else "";
}

impl _segment_matches_domain(segment: str, stem: str) -> bool {
    if re.fullmatch(r"(?i)(contact(?: us)?|about(?: us)?|home(?: page)?)", segment.strip())
        or re.search(r"(?i)\bservices?\s+(?:in|near)\s+\S", segment)
    {
        return False;
    }
    words = _words(segment);
    if any(len(w) >= 3 and w in stem for w in words if w not in _GENERIC_NAME_WORDS) {
        return True;
    }
    initials = "".join(w[0] for w in words if w not in ("of", "the", "and", "&"));
    return len(initials) >= 3 and stem.startswith(initials);
}

impl _segment_domain_evidence(segment: str, stem: str) -> int {
    if not _segment_matches_domain(segment, stem) {
        return 0;
    }
    return sum(
        len(w)
        for w in set(_words(segment))
        if w not in _GENERIC_NAME_WORDS and len(w) >= 3 and w in stem,
    );
}

impl _split_stem(stem: str) -> list[str] {
    starts: dict[int, str] = {};
    for w in _SPLIT_WORDS {
        i = stem.find(w);
        while i >= 0 {
            starts.setdefault(i, w);
            i = stem.find(w, i + 1);
        }
    }
    parts: list[str] = [];
    start = 0;
    for i in sorted(starts) {
        if i >= start {
            if start < i {
                parts.append(stem[start:i]);
            }
            parts.append(starts[i]);
            start = i + len(starts[i]);
        }
    }
    if start < len(stem) {
        parts.append(stem[start:]);
    }
    return parts;
}

impl name_from_domain(domain: str) -> str {
    stem = normalize_domain(domain).rsplit(".", 1)[0];
    words = [w for chunk in re.split(r"[-_.]+", stem) if chunk for w in _split_stem(chunk)];
    return " ".join(
        w.upper() if len(w) <= 3 and not re.search(r"[aeiouy]", w) else w.capitalize()
        for w in words,
    );
}

impl name_matches_domain(name: str, domain: str) -> bool {
    stem = _domain_stem(domain);
    return bool(stem and name and _segment_matches_domain(name, stem));
}

impl _named_segments(texts: list[str], stem: str) -> list[str] {
    segments = [x.strip(" ,.-") for text in texts for x in _TITLE_SEPARATORS.split(text)];
    return [s for s in segments if s and len(s) <= 60 and _segment_matches_domain(s, stem)];
}

impl site_name_from_html(html: str, domain: str) -> str {
    stem = _domain_stem(domain);
    candidates: list[str] = [];
    for pat in (
        r'<meta[^>]+property=["\']og:site_name["\'][^>]*content=["\']([^"\']+)',
        r'<meta[^>]+content=["\']([^"\']+)["\'][^>]*property=["\']og:site_name',
        r"(?is)<title[^>]*>(.*?)</title>",
    ) {
        m = re.search(pat, html or "", re.I);
        if m {
            candidates.append(unescape(re.sub(r"\s+", " ", m.group(1))).strip());
        }
    }
    return max(
        _named_segments(candidates, stem),
        key=lambda (seg: str) -> tuple[any, ...] {
            (_segment_domain_evidence(seg, stem), len(seg))
        },
        default="",
    );
}

impl business_name(title: str, domain: str) -> str {
    stem = _domain_stem(domain);
    title = re.sub(r"\s*(\.\.\.|…)\s*$", "", (title or "").strip());
    matches = _named_segments([title], stem) if stem and title else [];
    if matches {
        return max(matches, key=lambda (seg: str) -> int { _segment_domain_evidence(seg, stem) });
    }
    return name_from_domain(domain) if stem else title;
}

impl is_junk(domain: str, name: str = "") -> bool {
    if domain
        and (
            any(p.search(domain) for p in JUNK_DOMAIN_PATTERNS)
            or "." not in domain
            or re.fullmatch(r"[\d.]+", domain)
        )
    {
        return True;
    }
    return bool(name) and any(p.search(name) for p in JUNK_NAME_PATTERNS);
}

impl geocode_city(state: any, city: str, radius_km: int = 40, client: any = None) -> str {
    if not city {
        return "";
    }
    cache_key = f"geo:{city.strip().lower()}";
    cached = await state.get_setting(cache_key);
    if cached {
        return "" if cached == "-" else f"{cached},{radius_km}";
    }
    owned = client is None;
    client = client or httpx.AsyncClient(timeout=TIMEOUT);
    try {
        r = await client.get(
            NOMINATIM,
            params={"q": city, "format": "json", "limit": 1},
            headers={"User-Agent": GEOCODE_UA},
        );
        r.raise_for_status();
        hits = r.json();
    } except Exception as e {
        logger.warning("geocode failed for %r: %s", city, e);
        return "";
    } finally {
        if owned {
            await client.aclose();
        }
    }
    if not hits {
        await state.set_setting(cache_key, "-");
        logger.warning("geocode: no match for %r", city);
        return "";
    }
    point = f"{float(hits[0]['lat']):.4f},{float(hits[0]['lon']):.4f}";
    await state.set_setting(cache_key, point);
    return f"{point},{radius_km}";
}

impl resolve_coordinates(
    state: any, queries: list[any], radius_km: int = 40, client: any = None
) -> list[any] {
    points: dict[str, str] = {};
    for (i, city) in enumerate(
        sorted({q.location for q in queries if q.location and not q.coordinate})
    ) {
        if i {
            await asyncio.sleep(1.1);
        }
        points[city] = await geocode_city(state, city, radius_km, client);
    }
    for query in queries {
        if not query.coordinate {
            query.coordinate = points.get(query.location, "");
        }
    }
    return queries;
}

impl Business.identity -> str {
    return self.domain or self.external_id;
}

impl DiscoveryQuery.keyword -> str {
    return f"{self.term} {self.location}".strip();
}

impl dataforseo_location_name(place: str) -> str {
    parts = [p.strip() for p in (place or "").split(",") if p.strip()];
    if len(parts) == 2 {
        state = US_STATES.get(parts[1].upper()) or _US_STATE_NAMES.get(parts[1].lower());
        if state {
            return f"{parts[0]},{state},United States";
        }
    }
    return ",".join(parts);
}

impl _dfs_location(query: DiscoveryQuery, point_suffix: str) -> dict[str, any] {
    (lat, lng) = (query.coordinate.split(",") + [""])[:2];
    if query.coordinate and lat.strip() and lng.strip() {
        return {"location_coordinate": f"{lat.strip()},{lng.strip()},{point_suffix}"};
    }
    if query.location {
        return {"location_name": dataforseo_location_name(query.location)};
    }
    return {"location_code": DEFAULT_LOCATION_CODE};
}

impl _missing_value(value: any) -> bool {
    if not isinstance(value, str) {
        return not value;
    }
    return not value.strip() or bool(_PLACEHOLDER_RE.fullmatch(value.strip()));
}

impl _pages_of(n: int, size: int) -> int {
    return max(1, -(-n // size));
}

impl _join(sep: str, *parts: any) -> str {
    return sep.join(x for x in parts if x);
}

impl DiscoveryProvider.missing_keys(env: dict[str, any]) -> list[str] {
    return [k for k in self.env_keys if _missing_value(env.get(k))];
}

impl DiscoveryProvider.configured(env: dict[str, any]) -> bool {
    return not self.missing_keys(env);
}

impl DiscoveryProvider.estimate(queries: list[DiscoveryQuery]) -> float {
    return 0.0;
}

impl DiscoveryProvider.fetch(
    client: any, env: dict[str, any], query: DiscoveryQuery
) -> list[Business] {
    raise NotImplementedError();
}

impl DiscoveryProvider._hit(
    title: any, url: str, domain: str, query: DiscoveryQuery, **extra: any
) -> Business {
    return Business(
        name=business_name(title, domain),
        raw_title=title,
        domain=domain,
        website=url,
        location=query.location,
        has_website=True,
        source_url=url,
        provider=self.key,
        **extra,
    );
}

impl _DataForSEO._auth(env: dict[str, any]) -> str {
    return base64.b64encode(
        f"{env['dataforseo_login']}:{env['dataforseo_password']}".encode()
    ).decode();
}

impl _DataForSEO.base_url(env: dict[str, any]) -> str {
    return "https://sandbox.dataforseo.com/v3"
        if env.get("dataforseo_sandbox")
        else "https://api.dataforseo.com/v3";
}

impl _DataForSEO._post(
    client: any, env: dict[str, any], endpoint: str, task: dict[str, any]
) -> list[any] {
    r = await client.post(
        f"{self.base_url(env)}/{endpoint}",
        headers={"Authorization": f"Basic {self._auth(env)}", "Content-Type": "application/json"},
        json=[task],
    );
    r.raise_for_status();
    data = r.json();
    self.last_cost = float(data.get("cost") or 0.0);
    return _dfs_items(data);
}

impl DataForSEOListings.estimate(queries: list[DiscoveryQuery]) -> float {
    return sum(self.TASK_COST + self.ITEM_COST * q.limit for q in queries);
}

impl DataForSEOListings.fetch(
    client: any, env: dict[str, any], query: DiscoveryQuery
) -> list[Business] {
    payload: dict[str, any] = {
        "limit": min(query.limit, 1000),
        "order_by": ["rating.votes_count,desc"],
    };
    if query.category {
        payload["categories"] = [query.category];
    } else {
        payload["title"] = query.term;
    }
    if query.coordinate {
        payload["location_coordinate"] = query.coordinate;
    } elif query.location {
        payload["description"] = query.location;
    }
    items = await self._post(client, env, "business_data/business_listings/search/live", payload);
    return [_gbp_business(item, self.key) for item in items];
}

impl DataForSEOSerp.estimate(queries: list[DiscoveryQuery]) -> float {
    return sum(self.PAGE_COST * _pages_of(q.depth, 10) for q in queries);
}

impl DataForSEOSerp.fetch(
    client: any, env: dict[str, any], query: DiscoveryQuery
) -> list[Business] {
    keyword = query.keyword();
    items = await self._post(
        client,
        env,
        "serp/google/organic/live/advanced",
        {
            "keyword": keyword,
            "language_code": "en",
            "depth": query.depth,
            "device": "desktop",
            **_dfs_location(query, self.POINT_RADIUS),
        },
    );
    found: dict[str, Business] = {};
    for item in items {
        domain = normalize_domain(item.get("domain") or item.get("url") or "");
        url = item.get("url") or "";
        if item.get("type") == "organic" {
            if domain {
                biz = found.setdefault(
                    domain, self._hit(item.get("title") or "", url, domain, query, keyword=keyword)
                );
                biz.rank = _best(biz.rank, item.get("rank_group"));
            }
        } elif item.get("type") == "local_pack" and not item.get("is_paid") {
            cid = item.get("cid") or "";
            ident = domain or (f"dataforseo:cid:{cid}" if cid else "");
            if not ident {
                continue;
            }
            rating = item.get("rating") or {};
            if ident not in found {
                found[ident] = Business(
                    name=item.get("title") or "",
                    raw_title=item.get("title") or "",
                    domain=domain,
                    website=url,
                    location=query.location,
                    has_website=True if domain else None,
                    external_id="" if domain else ident,
                    source_url=url,
                    provider=self.key,
                    keyword=keyword,
                );
            }
            biz = found[ident];
            biz.phone = biz.phone or item.get("phone") or "";
            if rating.get("value") is not None {
                biz.rating = rating.get("value");
                biz.review_count = rating.get("votes_count");
            }
            biz.local_pack_rank = _best(biz.local_pack_rank, item.get("rank_group"));
        }
    }
    return list(found.values());
}

impl DataForSEOMaps.estimate(queries: list[DiscoveryQuery]) -> float {
    return sum(self.SERP_COST * _pages_of(q.depth, 100) for q in queries);
}

impl DataForSEOMaps.fetch(
    client: any, env: dict[str, any], query: DiscoveryQuery
) -> list[Business] {
    keyword = query.keyword();
    items = await self._post(
        client,
        env,
        "serp/google/maps/live/advanced",
        {
            "keyword": keyword,
            "language_code": "en",
            "depth": query.depth,
            **_dfs_location(query, self.ZOOM),
        },
    );
    out: list[Business] = [];
    for item in items {
        if item.get("type") != "maps_search" {
            continue;
        }
        biz = _gbp_business(item, self.key);
        if biz.domain or biz.external_id {
            out.append(
                replace(
                    biz,
                    raw_title=biz.name,
                    location=biz.location or query.location,
                    has_website=bool(biz.website or biz.domain),
                    maps_rank=item.get("rank_group"),
                    source_url=biz.website,
                    keyword=keyword,
                ),
            );
        }
    }
    return out;
}

impl _gbp_business(item: dict[str, any], provider: str) -> Business {
    url = item.get("url") or "";
    rating = item.get("rating") or {};
    addr = item.get("address_info") or {};
    place = item.get("place_id") or "";
    cid = str(item.get("cid") or "");
    place_id = f"dataforseo:{place}" if place else "";
    return Business(
        name=item.get("title") or "",
        domain=normalize_domain(item.get("domain") or url),
        website=url,
        phone=item.get("phone") or "",
        address=item.get("address") or "",
        location=_join(", ", addr.get("city"), addr.get("region")),
        category=item.get("category") or "",
        rating=rating.get("value"),
        review_count=rating.get("votes_count"),
        is_claimed=item.get("is_claimed"),
        has_website=bool(url),
        external_id=f"dataforseo:cid:{cid}" if cid else place_id,
        alt_ids=(place_id,) if cid and place else (),
        source_url=item.get("check_url") or "",
        provider=provider,
    );
}

impl _best(current: int | None, new: any) -> int | None {
    if not isinstance(new, int) {
        return current;
    }
    return new if current is None else min(current, new);
}

impl Serper.estimate(queries: list[DiscoveryQuery]) -> float {
    return 0.001 * len(queries);
}

impl Serper.fetch(client: any, env: dict[str, any], query: DiscoveryQuery) -> list[Business] {
    r = await client.post(
        "https://google.serper.dev/search",
        headers={"X-API-KEY": env["serper_api_key"], "Content-Type": "application/json"},
        json={"q": query.keyword(), "num": max(1, min(query.depth, 10))},
    );
    r.raise_for_status();
    out: list[Business] = [];
    for item in r.json().get("organic") or [] {
        domain = normalize_domain(item.get("link") or "");
        if domain {
            out.append(
                self._hit(
                    item.get("title") or "",
                    item.get("link") or "",
                    domain,
                    query,
                    rank=item.get("position"),
                ),
            );
        }
    }
    return out;
}

impl TinyFish._pace {
    loop = asyncio.get_running_loop();
    if self._lock is None or self._lock[0] is not loop {
        self._lock = (loop, asyncio.Lock());
    }
    async with self._lock[1] {
        now = time.monotonic();
        self._calls = [t for t in self._calls if now - t < 3600];
        if len(self._calls) >= self.HOURLY_LIMIT {
            minutes = int((3600 - (now - self._calls[0])) // 60) + 1;
            raise ProviderExhausted(
                f"TinyFish allows 500 searches an hour and this hour's are used up. Run again in about {minutes} minutes.",
            );
        }
        pause = self._last_call + self.MIN_INTERVAL - now;
        if self._last_call and pause > 0 {
            await asyncio.sleep(pause);
        }
        self._last_call = time.monotonic();
        self._calls.append(self._last_call);
    }
}

impl TinyFish._get(client: any, headers: dict[str, any], params: dict[str, any]) -> any {
    for attempt in range(2) {
        await self._pace();
        try {
            r = await client.get(self.ENDPOINT, headers=headers, params=params);
        } except httpx.HTTPError as e {
            if attempt == 0 {
                await asyncio.sleep(1.0);
                continue;
            }
            raise RuntimeError(f"TinyFish search unreachable: {e}") from e;
        }
        if r.status_code != 429 {
            return r;
        }
        if attempt == 1 {
            raise ProviderExhausted(
                "TinyFish: rate limited (it allows 30 searches a minute and 500 an hour). Try again later, or with fewer phrases.",
            );
        }
        retry_after = 2.0;
        try {
            retry_after = float(r.headers.get("Retry-After", "2"));
        } except (ValueError, TypeError) {}
        await asyncio.sleep(min(60.0, max(1.0, retry_after)));
    }
}

impl TinyFish.fetch(client: any, env: dict[str, any], query: DiscoveryQuery) -> list[Business] {
    api_key = env.get("tinyfish_api_key", "").strip();
    if not api_key {
        raise RuntimeError("TinyFish needs TINYFISH_API_KEY in .env");
    }
    headers = {"X-API-Key": api_key, "Accept": "application/json"};
    out: list[Business] = [];
    for page in range(max(1, min(11, -(-query.depth // 10)))) {
        r = await self._get(client, headers, {"query": query.keyword(), "page": page});
        if r.status_code == 401 {
            raise ProviderExhausted(
                "TinyFish: Invalid or missing API key (HTTP 401). Check TINYFISH_API_KEY in .env or get a free key at https://agent.tinyfish.ai/api-keys",
            );
        }
        if r.status_code == 402 {
            err_msg = "";
            try {
                err = r.json().get("error");
                err_msg = err.get("message", "")
                    if isinstance(err, dict)
                    else err if isinstance(err, str) else "";
            } except Exception {}
            raise ProviderExhausted(f"TinyFish refused the search (HTTP 402). {err_msg}".strip());
        }
        r.raise_for_status();
        try {
            data = r.json();
        } except ValueError as e {
            raise RuntimeError("TinyFish sent an unexpected answer (not JSON)") from e;
        }
        if not isinstance(data, dict) {
            raise RuntimeError("TinyFish sent an unexpected answer (not an object)");
        }
        items = data.get("results") or [];
        if not isinstance(items, list) or not items {
            break;
        }
        for item in items {
            url = item.get("url") or "" if isinstance(item, dict) else "";
            domain = normalize_domain(url) if isinstance(url, str) else "";
            if domain {
                out.append(
                    self._hit(item.get("title") or "", url, domain, query, keyword=query.keyword())
                );
            }
        }
        if len(items) < 10 {
            break;
        }
    }
    return out;
}

impl OpenStreetMap._tags(term: str) -> list[str] {
    low = term.lower();
    for (needle, tags) in self.TAG_MAP.items() {
        if needle in low {
            return tags;
        }
    }
    return [];
}

impl OpenStreetMap.fetch(
    client: any, env: dict[str, any], query: DiscoveryQuery
) -> list[Business] {
    if not query.coordinate {
        logger.warning(
            "osm: no coordinate for %r — Overpass needs a lat,lng,radius to search", query.keyword()
        );
        return [];
    }
    tags = self._tags(query.term);
    if not tags {
        raise RuntimeError(
            f"OpenStreetMap has no category for {query.term!r}. It can only search mapped trades ({', '.join(sorted(self.TAG_MAP))}). Use a listings or SERP provider for this one.",
        );
    }
    (lat, lng, radius_km) = (query.coordinate.split(",") + ["", "", ""])[:3];
    around = f"(around:{int(float(radius_km or 25) * 1000)},{lat},{lng});";
    clauses = "".join(
        f"{kind}[{tag.split('=')[0]}={tag.split('=')[1]}]{around}"
        for tag in tags
        for kind in ("node", "way"),
    );
    body = f"[out:json][timeout:{self.SERVER_TIMEOUT}];({clauses});out center {query.limit};";
    headers = {"User-Agent": GEOCODE_UA};
    r: any = None;
    for (i, endpoint) in enumerate(self.ENDPOINTS) {
        if i {
            await asyncio.sleep(self.BACKOFF);
        }
        try {
            r = await client.post(
                endpoint, content=body.encode(), headers=headers, timeout=self.HTTP_TIMEOUT
            );
        } except httpx.HTTPError as e {
            logger.warning("osm: %s unreachable (%s)", endpoint, e);
            continue;
        }
        if r.status_code not in self.RETRY_STATUSES {
            break;
        }
        logger.warning(
            "osm: %s is throttling or down (%s) — trying the next mirror", endpoint, r.status_code
        );
    } else {
        raise RuntimeError(
            "Every public Overpass mirror is unavailable or throttling right now. This is free volunteer infrastructure — wait a few minutes and re-run, or use a paid provider for bulk work.",
        );
    }
    r.raise_for_status();
    out: list[Business] = [];
    for el in r.json().get("elements") or [] {
        info = el.get("tags") or {};
        site = info.get("website") or info.get("contact:website") or "";
        if info.get("name") {
            out.append(
                Business(
                    name=info.get("name"),
                    domain=normalize_domain(site),
                    website=site,
                    phone=info.get("phone") or info.get("contact:phone") or "",
                    address=_join(" ", info.get("addr:housenumber"), info.get("addr:street")),
                    location=_join(", ", info.get("addr:city"), info.get("addr:state"))
                        or query.location,
                    category=info.get("craft") or info.get("shop") or info.get("office") or "",
                    has_website=bool(site),
                    external_id=f"osm:{el.get('type')}/{el.get('id')}",
                    source_url=f"https://www.openstreetmap.org/{el.get('type')}/{el.get('id')}",
                    provider=self.key,
                ),
            );
        }
    }
    return out;
}

impl ScavioProvider._post(
    client: any, env: dict[str, any], path: str, body: dict[str, any]
) -> dict[str, any] {
    if self.last_cost + self.CREDIT_PRICE > self.remaining_budget + 1e-12 {
        raise ProviderExhausted("Scavio: budget reached before the next page");
    }
    pause = self._last_call + self.MIN_INTERVAL - time.monotonic();
    if pause > 0 {
        await asyncio.sleep(pause);
    }
    self._last_call = time.monotonic();
    try {
        r = await client.post(
            f"{self.API}{path}",
            headers={
                "Authorization": f"Bearer {env['scavio_api_key']}",
                "Content-Type": "application/json",
            },
            json=body,
        );
    } except httpx.HTTPError {
        raise RuntimeError("Scavio: request failed; try again later") from None;
    }
    reasons = {
        401: "invalid API key",
        402: "insufficient credits",
        403: "access refused",
        429: "rate limit reached",
    };
    if r.status_code in reasons {
        raise ProviderExhausted(f"Scavio {r.status_code}: {reasons[r.status_code]}");
    }
    if r.status_code >= 400 {
        raise RuntimeError(f"Scavio {r.status_code}: request failed");
    }
    self.last_cost += self.CREDIT_PRICE;
    try {
        data = r.json();
    } except ValueError {
        raise RuntimeError("Scavio: invalid JSON response") from None;
    }
    if not isinstance(data, dict) or data.get("error") {
        raise RuntimeError("Scavio: invalid response");
    }
    credits = data.get("credits_used", 1);
    if _is_count(credits) {
        self.last_cost += (credits - 1) * self.CREDIT_PRICE;
    }
    return data;
}

impl ScavioProvider._pages(
    client: any,
    env: dict[str, any],
    query: DiscoveryQuery,
    path: str,
    body: any,
    results_key: str,
    page_size: int,
    pages: int,
) -> list[tuple[any, ...]] {
    self.last_cost = 0.0;
    self.last_error = self.stop_reason = "";
    self.complete = True;
    rows: list[tuple[any, ...]] = [];
    for page in range(pages) {
        start = page * page_size;
        try {
            data = await self._post(client, env, path, dict(body, start=start));
            items = data.get(results_key);
            if not isinstance(items, list) or not all(isinstance(item, dict) for item in items) {
                raise RuntimeError("Scavio: invalid results list");
            }
            for item in items {
                _check_scavio_item(item);
            }
            last_page = self._last_page(data, items, page_size);
        } except Exception as e {
            self.complete = False;
            self.last_error = str(e);
            if isinstance(e, ProviderExhausted) {
                self.stop_reason = str(e);
            }
            if not rows {
                raise;
            }
            logger.warning(
                "%s: page %d of %r failed, keeping %d results: %s",
                self.key,
                page + 1,
                query.keyword(),
                len(rows),
                e,
            );
            break;
        }
        for item in items {
            rows.append((start, item));
        }
        if last_page {
            break;
        }
    }
    return rows;
}

impl ScavioProvider._last_page(data: dict[str, any], items: list[any], page_size: int) -> bool {
    return len(items) < page_size;
}

impl _is_count(value: any) -> bool {
    return isinstance(value, (int, float))
        and not isinstance(value, bool)
        and math.isfinite(value)
        and value >= 0;
}

impl _check_scavio_item(item: dict[str, any]) {
    for f in ("title", "website", "link", "phone", "address", "type", "place_id") {
        if item.get(f) is not None and not isinstance(item[f], str) {
            raise RuntimeError("Scavio: invalid result field");
        }
    }
    for f in ("rating", "reviews", "position") {
        if item.get(f) is not None and not _is_count(item.get(f)) {
            raise RuntimeError("Scavio: invalid numeric result field");
        }
    }
}

impl ScavioMaps._page_count(query: DiscoveryQuery) -> int {
    return min(self.MAX_PAGES, _pages_of(query.limit, self.PAGE_SIZE));
}

impl ScavioMaps.estimate(queries: list[DiscoveryQuery]) -> float {
    return sum(self.CREDIT_PRICE * self._page_count(q) for q in queries);
}

impl ScavioMaps.map_center(coordinate: str) -> str {
    parts = [p.strip() for p in coordinate.split(",")];
    if len(parts) < 2 or not all(parts[:2]) {
        return "";
    }
    try {
        (lat, lng) = (float(parts[0]), float(parts[1]));
    } except ValueError {
        return "";
    }
    if not (-90 <= lat and lat <= 90 and -180 <= lng and lng <= 180) {
        return "";
    }
    radius_km = 40.0;
    try {
        radius_km = float(parts[2]) if len(parts) > 2 and parts[2] else 40.0;
    } except ValueError {}
    if not math.isfinite(radius_km) or radius_km <= 0 {
        radius_km = 40.0;
    }
    zoom = round(math.log2(40000 / max(radius_km, 0.5)));
    return f"@{parts[0]},{parts[1]},{max(3, min(zoom, 16))}z";
}

impl ScavioMaps.fetch(client: any, env: dict[str, any], query: DiscoveryQuery) -> list[Business] {
    center = self.map_center(query.coordinate) if query.coordinate else "";
    body = {"query": query.term, "ll": center} if center else {"query": query.keyword()};
    out: list[Business] = [];
    for (_, item) in await self._pages(
        client,
        env,
        query,
        "/maps/search",
        body,
        "local_results",
        self.PAGE_SIZE,
        self._page_count(query),
    ) {
        site = item.get("website") or "";
        place_id = item.get("place_id") or "";
        if item.get("title") {
            out.append(
                Business(
                    name=item.get("title"),
                    domain=normalize_domain(site),
                    website=site,
                    phone=item.get("phone") or "",
                    address=item.get("address") or "",
                    location=query.location,
                    category=item.get("type") or "",
                    rating=item.get("rating"),
                    review_count=item.get("reviews"),
                    has_website=bool(site),
                    external_id=f"gmaps:{place_id}" if place_id else "",
                    source_url=f"https://www.google.com/maps/place/?q=place_id:{place_id}"
                        if place_id
                        else site,
                    provider=self.key,
                ),
            );
        }
    }
    return out;
}

impl ScavioSearch.estimate(queries: list[DiscoveryQuery]) -> float {
    return sum(self.CREDIT_PRICE * _pages_of(q.depth, self.PAGE_SIZE) for q in queries);
}

impl ScavioSearch._last_page(data: dict[str, any], items: list[any], page_size: int) -> bool {
    pagination = data.get("pagination") or {};
    if not isinstance(pagination, dict) {
        raise RuntimeError("Scavio: invalid pagination");
    }
    return not items or not pagination.get("next");
}

impl ScavioSearch.fetch(client: any, env: dict[str, any], query: DiscoveryQuery) -> list[Business] {
    out: list[Business] = [];
    for (start, item) in await self._pages(
        client,
        env,
        query,
        "",
        {"query": query.keyword()},
        "organic_results",
        self.PAGE_SIZE,
        _pages_of(query.depth, self.PAGE_SIZE),
    ) {
        domain = normalize_domain(item.get("link") or "");
        position = item.get("position");
        if domain {
            out.append(
                self._hit(
                    item.get("title") or "",
                    item.get("link") or "",
                    domain,
                    query,
                    rank=start + position if isinstance(position, int) and position > 0 else None,
                ),
            );
        }
    }
    return out;
}

impl _dfs_items(payload: dict[str, any]) -> list[any] {
    if payload.get("status_code") not in (20000, None) {
        raise RuntimeError(
            f"DataForSEO {payload.get('status_code')}: {payload.get('status_message')}"
        );
    }
    tasks = payload.get("tasks") or [];
    if not tasks or tasks[0].get("status_code") == NO_SEARCH_RESULTS {
        return [];
    }
    task = tasks[0];
    if task.get("status_code") not in (20000, None) {
        raise RuntimeError(
            f"DataForSEO task {task.get('status_code')}: {task.get('status_message')}"
        );
    }
    results = task.get("result") or [];
    if not results or not results[0] {
        return [];
    }
    return results[0].get("items") or [];
}

impl DiscoveryReport.as_dict -> dict[str, any] {
    fields: dict[str, any] = asdict(self);
    return {
        **fields,
        "estimated_cost": round(self.estimated_cost, 4),
        "actual_cost": round(self.actual_cost, 4),
        "errors": self.errors,
    };
}

impl preset_templates(spec: dict[str, any]) -> tuple[any, ...] {
    return tuple(spec.get("terms") or (spec["term"],));
}

impl company_host(domain: str) -> str {
    stripped = _CAREERS_HOST.sub("", domain);
    labels = stripped.split(".");
    if stripped == domain
        or len(labels) < 2
        or (len(labels) == 2 and labels[0] in _SECOND_LEVEL_SUFFIX and len(labels[1]) == 2)
    {
        return domain;
    }
    return stripped;
}

impl _wants_role(spec: dict[str, any]) -> bool {
    return any("{role}" in tpl for tpl in preset_templates(spec));
}

impl preset_problem(preset: str, provider_key: str, config: any = None) -> str | None {
    if not preset {
        return None;
    }
    spec = PRESETS.get(preset);
    if spec is None {
        return f"Unknown preset {preset!r}. Presets: {', '.join(PRESETS)}.";
    }
    provider = PROVIDERS.get(provider_key);
    if provider is None or provider.kind not in spec["kinds"] {
        names = ", ".join(k for (k, p) in PROVIDERS.items() if p.kind in spec["kinds"]);
        return f"The {spec['label']} preset is a web search, so it needs a search provider ({names}), not {provider_key}.";
    }
    if _wants_role(spec)
        and config is not None
        and not role_keywords(getattr(config, "icp", None))
    {
        return f"The {spec['label']} preset searches for roles, and sellbird.yaml has none: set icp.hiring_signals (or icp.titles).";
    }
    return None;
}

impl build_queries(
    config: any,
    cities: list[str] | None = None,
    depth: int = 30,
    limit: int = 100,
    preset: str = "",
) -> list[DiscoveryQuery] {
    icp = config.icp;
    terms = list(icp.industries) or [config.product.name];
    spec = PRESETS.get(preset) if preset else None;
    if spec {
        templates = preset_templates(spec);
        since = (date.today() - timedelta(days=FUNDING_LOOKBACK_DAYS)).isoformat();
        roles = role_keywords(icp) if _wants_role(spec) else [""];
        terms = [
            tpl.format(industry=t, role=r, since=since)
            for r in roles
            for t in terms
            for tpl in templates
        ];
        places = cities
            if cities is not None
            else [""] if not spec["local"] else list(icp.geography) or [""];
    } else {
        variants = getattr(icp, "keyword_variants", {}) or {};
        terms = list(
            dict.fromkeys(v.strip() for t in terms for v in [t, *variants.get(t, [])] if v.strip())
        );
        places = cities if cities is not None else list(icp.geography) or [""];
    }
    coords = getattr(icp, "geo_coordinates", {}) or {};
    return [
        DiscoveryQuery(
            term=term,
            location=place,
            depth=depth,
            limit=limit,
            coordinate=coords.get(place, ""),
            preset=preset if spec else "",
        )
        for term in terms
        for place in places
    ];
}

impl estimate_cost(provider_key: str, queries: list[DiscoveryQuery]) -> float {
    provider = PROVIDERS.get(provider_key);
    return provider.estimate(queries) if provider else 0.0;
}

impl _refusal(rep: DiscoveryReport, error: str, stopped: str) -> DiscoveryReport {
    rep.errors.append(error);
    rep.stopped = stopped;
    return rep;
}

impl run_discovery(
    state: any,
    config: any,
    provider_key: str = DEFAULT_PROVIDER,
    queries: list[DiscoveryQuery] | None = None,
    max_spend: float = 1.0,
    dry_run: bool = False,
) -> DiscoveryReport {
    provider = PROVIDERS.get(provider_key);
    if provider is None {
        raise ValueError(f"unknown discovery provider: {provider_key!r}");
    }
    queries = queries or build_queries(config);
    if provider.needs_coordinates {
        queries = await resolve_coordinates(state, queries);
    }
    rep = DiscoveryReport(provider=provider_key, queries=len(queries));
    rep.estimated_cost = provider.estimate(queries);
    if dry_run {
        return rep;
    }
    env = load_env().model_dump();
    missing = provider.missing_keys(env);
    if missing {
        names = ", ".join(k.upper() for k in missing);
        return _refusal(
            rep,
            f"{provider.label} is not ready: {names} is empty or still the template placeholder in .env",
            "not configured",
        );
    }
    if rep.estimated_cost > max_spend {
        return _refusal(
            rep,
            f"estimated ${rep.estimated_cost:.2f} exceeds the ${max_spend:.2f} cap — raise the cap or run fewer queries",
            "over budget",
        );
    }
    await seed_signal_catalog(state);
    confirmed = await state.confirmed_signal_codes();
    if not confirmed {
        return _refusal(
            rep,
            "no signals confirmed — confirm signals first (dashboard → Signals, or `sellbird signals --confirm free`) or discovery has nothing to record",
            "no confirmed signals",
        );
    }
    rep.run_id = await state.start_run(
        "discover",
        provider=provider_key,
        params={"queries": len(queries), "estimate": rep.estimated_cost},
    );
    run = _Run(state=state, rep=rep, confirmed=confirmed, dnc=live_do_not_contact(config));
    try {
        async with httpx.AsyncClient(timeout=TIMEOUT, follow_redirects=True) as client {
            for (i, query) in enumerate(queries) {
                if await state.get_setting("discovery_paused") {
                    rep.stopped = "paused";
                    break;
                }
                if rep.actual_cost > max_spend {
                    rep.stopped = "budget reached";
                    break;
                }
                if i and provider.key == "osm" {
                    await asyncio.sleep(OpenStreetMap.MIN_INTERVAL);
                }
                try {
                    rep.queries_ran += 1;
                    provider.last_cost = 0.0;
                    provider.last_error = provider.stop_reason = "";
                    provider.complete = True;
                    provider.remaining_budget = max(0.0, max_spend - rep.actual_cost);
                    found = await provider.fetch(client, env, query);
                    rep.queries_succeeded += 1;
                } except ProviderExhausted as e {
                    logger.warning("discover: %s stopped: %s", provider_key, e);
                    rep.stopped = str(e);
                    break;
                } except Exception as e {
                    logger.warning(
                        "discover: %s failed on %r: %s", provider_key, query.keyword(), e
                    );
                    rep.errors.append(f"{query.keyword()}: {e}");
                    continue;
                } finally {
                    rep.actual_cost += provider.last_cost;
                }
                await run.record(provider, query, found);
                if provider.stop_reason {
                    rep.stopped = provider.stop_reason;
                    break;
                }
            }
        }
        await state.finish_run(
            rep.run_id,
            status="completed",
            records=rep.new_companies + rep.known_companies,
            cost_usd=rep.actual_cost,
        );
    } except Exception as e {
        logger.exception("discover run failed");
        rep.errors.append(str(e));
        await state.finish_run(
            rep.run_id,
            status="failed",
            records=rep.new_companies,
            cost_usd=rep.actual_cost,
            error=str(e),
        );
    }
    return rep;
}

impl _Run.record(provider: any, query: DiscoveryQuery, found: list[Business]) {
    rep = self.rep;
    if provider.last_error {
        rep.errors.append(f"{query.keyword()}: {provider.last_error}");
    }
    rep.found += len(found);
    batch: list[dict[str, any]] = [];
    for biz in found {
        batch.extend(await self.take(biz, query));
    }
    phrase = query.keyword();
    for code in provider.rank_codes if provider.complete else () {
        if code in self.confirmed {
            found_now = self.ranked.setdefault((code, phrase), set[str]());
            for gone in await self.state.ranked_company_ids(code, phrase) - found_now {
                batch.append(_row(gone, code, 0.0, phrase, 1.0, "", rep.run_id));
            }
        }
    }
    if batch {
        rep.observations += await self.state.add_observations(batch, run_id=rep.run_id);
    }
}

impl _Run.take(biz: Business, query: DiscoveryQuery) -> list[dict[str, any]] {
    if query.preset == "hiring" and biz.domain and not is_junk(biz.domain) {
        biz.domain = company_host(biz.domain);
    }
    if is_junk(biz.domain, biz.raw_title or biz.name) {
        self.rep.junk += 1;
        return [];
    }
    if do_not_contact_domain_match(biz.domain, self.dnc) {
        self.rep.excluded += 1;
        return [];
    }
    ident = biz.identity();
    if not ident {
        return [];
    }
    first = ident not in self.company_ids;
    if first {
        (self.company_ids[ident], is_new) = await _upsert(self.state, biz, query);
        self.rep.new_companies += int(is_new);
        self.rep.known_companies += int(not is_new);
    }
    company_id = self.company_ids[ident];
    phrase = biz.keyword or query.keyword();
    ranks = (biz.rank, biz.local_pack_rank, biz.maps_rank);
    for (code, value) in zip(RANK_CODES, ranks) {
        if value is not None {
            self.ranked.setdefault((code, phrase), set[str]()).add(company_id);
        }
    }
    rank_key = (ident, phrase.lower());
    previous = self.best_ranks.get(rank_key);
    better = [
        new is not None and (old is None or new < old)
        for (new, old) in zip(ranks, previous or (None, None, None))
    ];
    improved = previous is None or any(better);
    if not first and not improved {
        return [];
    }
    if previous is not None {
        biz = replace(
            biz,
            **{name: new if ok else None for (name, new, ok) in zip(RANK_FIELDS, ranks, better)},
        );
    }
    if improved {
        self.best_ranks[rank_key] = tuple(
            _best(old, new) for (new, old) in zip(ranks, previous or (None, None, None))
        );
    }
    return _observations(
        biz, company_id, self.confirmed, self.rep.run_id, query=query, ranks_only=not first
    );
}

impl _upsert(state: any, biz: Business, query: DiscoveryQuery) -> tuple[any, ...] {
    existing = await state.get_company_by_domain(biz.domain) if biz.domain else None;
    for external in (biz.external_id, *biz.alt_ids) {
        if existing is None and external {
            existing = await state.get_company_by_external_id(external);
        }
    }
    if existing {
        return (existing.id, False);
    }
    company = Company(
        name=biz.name,
        domain=biz.domain,
        website=biz.website,
        phone=biz.phone,
        industry=biz.category or query.term,
        location=biz.location or query.location,
        source=f"discover:{biz.provider}",
        source_url=biz.source_url,
        external_id=biz.external_id,
    );
    return (await state.add_company(company), True);
}

impl _row(
    company_id: str, code: str, num: any, text: str, conf: float, url: str, run_id: str
) -> dict[str, any] {
    return {
        "company_id": company_id,
        "signal_code": code,
        "collector": "discover",
        "value_num": num,
        "value_text": text,
        "confidence": conf,
        "evidence_url": url,
        "run_id": run_id,
    };
}

impl _num(value: any) -> float | None {
    return None if value is None else float(value);
}

impl _observations(
    biz: Business,
    company_id: str,
    confirmed: set[str],
    run_id: str,
    query: DiscoveryQuery | None = None,
    ranks_only: bool = False,
) -> list[dict[str, any]] {
    keyword = biz.keyword or (query.keyword() if query is not None else "");
    preset = query.preset if query is not None else "";
    facts = [
        (code, value is not None, _num(value), keyword, 1.0)
        for (code, value) in zip(RANK_CODES, (biz.rank, biz.local_pack_rank, biz.maps_rank))
    ];
    if not ranks_only {
        facts += [
            ("FOUND_IN_SERP", True, None, biz.provider, 1.0),
            ("NO_WEBSITE", biz.has_website is False, 1.0, "", 1.0),
            ("UNCLAIMED_LISTING", biz.is_claimed is False, 1.0, "", 1.0),
            ("REVIEW_RATING", biz.rating is not None, _num(biz.rating), "", 1.0),
            ("REVIEW_COUNT", biz.review_count is not None, _num(biz.review_count), "", 1.0),
            ("YC_BACKED", preset == "yc", 1.0, "", 0.7),
            ("ACCELERATOR", preset == "accelerator", 1.0, "", 0.6),
        ];
    }
    return [
        _row(company_id, code, num, text, conf, biz.source_url, run_id)
        for (code, wanted, num, text, conf) in facts
        if wanted and code in confirmed
    ];
}

impl provider_menu(env: dict[str, any] | None = None) -> list[dict[str, any]] {
    if env is None {
        env = load_env().model_dump();
    }
    return [
        {
            "key": p.key,
            "label": p.label,
            "kind": p.kind,
            "blurb": p.blurb,
            "cost_note": p.cost_note,
            "free_tier": p.free_tier,
            "signup_url": p.signup_url,
            "caveat": p.caveat,
            "env_keys": [k.upper() for k in p.env_keys],
            "configured": p.configured(env),
            "needs_key": bool(p.env_keys),
        }
        for p in PROVIDERS.values()
    ];
}
