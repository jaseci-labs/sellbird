impl _folded(cp: int) -> any {
    d = unicodedata.normalize("NFD", chr(cp));
    return d[0]
        if len(d) > 1 and ord(d[0]) < 128 and all(unicodedata.combining(c) for c in d[1:])
        else "";
}

impl fold_accents(text: str) -> str {
    return (text or "").translate(_FOLD_TABLE);
}

impl nfc(text: str) -> str {
    return unicodedata.normalize("NFC", text or "");
}

impl _is_name_token(token: str) -> bool {
    for part in fold_accents(token).split("-") {
        bare = part.strip(".,'");
        if bare.lower() in NON_NAME_WORDS
            or _NOUN_SUFFIX.search(bare.lower())
            or (len(bare) >= 3 and bare.isupper())
        {
            return False;
        }
    }
    return True;
}

impl _name_like(text: str) -> bool {
    return all(_is_name_token(t) for t in text.split());
}

impl _title_chunks(raw_after: str) -> list[str] {
    pieces = re.split(_BLOCK_BREAK, re.sub("<[^*]*$".replace("*", ">"), "", raw_after));
    chunks = [
        re.sub("\\s+", " ", unescape(re.sub("(?s)<[^>]+>", " ", p))).strip(" ,.|-–—·")
        for p in pieces
    ];
    return [c for c in chunks if c];
}

impl _reads_like_title(text: str) -> bool {
    words = text.split();
    lower = [
        w
        for w in words[1:]
        if w[:1].islower() and w.lower() not in _CONNECTORS and not re.match("(?i)^[ld]['’]", w)
    ];
    return len(words) > 0 and len(words) <= 10 and len(lower) <= 2 and title_looks_like_role(text);
}

impl title_looks_like_role(text: str) -> bool {
    return bool(re.search(ROLE_HINT, fold_accents(text[:160])));
}

impl _strip_code(html: str) -> str {
    html = re.sub("(?is)<script\\b.*?</script>", " ", html);
    html = re.sub("(?is)<style\\b.*?</style>", " ", html);
    return re.sub("(?s)<!--.*?-->", " ", html);
}

impl looks_like_challenge(text: str, status: int = 200) -> bool {
    if not text {
        return False;
    }
    head = text[:6000];
    low = head.lower();
    title = re.search("(?is)<title[^>]*>(.*?)</title>", head);
    shown = title.group(1).strip().lower() if title else "";
    if any(marker in low for marker in _BLOCK_MARKERS)
        or (title and any(t in shown for t in _BLOCK_TITLES))
    {
        return True;
    }
    if status in (202, 403, 429, 503) and len(text) < 15000 {
        visible = re.sub("(?s)<[^>]+>", " ", _strip_code(text)).lower();
        return any(marker in visible for marker in _WEAK_BLOCK_MARKERS);
    }
    return False;
}

impl _text(html: str) -> str {
    return re.sub("\\s+", " ", re.sub("(?s)<[^>]+>", " ", _strip_code(html)));
}

impl _program(prog: str, strict: bool = False) -> dict[str, any] {
    (batch, nouns, events) = (_ACC_BATCH, _ACC_NOUNS, _ACC_EVENTS)
        if strict
        else (_BATCH, _YC_NOUNS, _YC_EVENTS);
    extra = _ACC_EXTRA.format(prog=prog) if strict else "";
    cohort = partial(_acc_cohort, _cohort_shapes(prog)) if strict else _yc_cohort;
    return {
        "mention": re.compile(f"\\b{prog}\\b", re.I),
        "extra": extra,
        "strict": strict,
        "cohort": cohort,
        "badge": re.compile(
            f"^\\(?\\s*(?:(?:backed|funded|supported)\\s+by\\s+{prog}(?:\\s*[\\(\\[]?\\s*{batch}\\s*[\\)\\]]?)?|{prog}[\\s-]+(?:backed|funded)(?:\\s*[\\(\\[]?\\s*{batch}\\s*[\\)\\]]?)?|{prog}\\s*[\\(\\[]?\\s*{batch}\\s*[\\)\\]]?)\\s*\\)?\\.?$",
            re.I,
        ),
        "body": f"{_FILLER}\\s+(?:backed by|funded by|supported by|part of|a member of|members of|graduated from|alumni of|alums? of|went through|joined|hatched (?:in|at)|incubated (?:in|at|by)|accepted into|participated in|launched at|in)\\s+(?:the\\s+)?{prog}\\b|{_FILLER}\\s+in\\s+the\\s+{_SEASON_WORD}\\s+\\d{{4}}\\s+batch\\s+of\\s+{prog}\\b|{_FILLER}\\s+(?:a|an)\\s+{prog}(?:\\s+{batch})?[\\s-]+(?:(?:backed|funded)\\s+)?(?:{nouns})\\b|{_FILLER}\\s+{prog}[\\s-]+(?:backed|funded|alumni|alums?|alumnus)\\b|\\s*[\\(\\[]\\s*{prog}\\s*{batch}\\s*[\\)\\]]",
        "in_needs_be": re.compile(
            f"(?<!\\bwere)(?<!\\bwas)(?<!\\bare)(?<!\\bis)(?<!\\bbeen)\\s+in\\s+(?:the\\s+)?{prog}\\b",
            re.I,
        ),
        "later": f"[^.]{{0,80}}?(?<!\\bthat)(?<!\\bwhich)(?<!\\bwho)\\s+(?:is|are|was|were|has been|have been)\\s+(?:proudly\\s+)?(?:backed|funded|supported)\\s+by\\s+{prog}\\b",
        "investors": re.compile(
            f"^(?:our\\s+)?investors?\\s*(?:include|including|are|:)[^.]{{0,80}}\\b{prog}\\b", re.I
        ),
        "leading": re.compile(f"^(?:backed|funded|supported)\\s+by\\s+{prog}\\b", re.I),
        "programs": re.compile(f"\\b{prog}(?:['’]s)?\\s+(?:{events})\\b", re.I),
    };
}

impl _claims(p: dict[str, any], html: str, domain: str) -> list[any] {
    name = _alnum(_domain_name(domain) if domain else "");
    spelled = "[\\s.-]?".join(re.escape(ch) for ch in name) if len(name) >= 3 else "";
    subject = f"(?:{_SELF_SUBJECT}" + (f"|{spelled}\\b" if spelled else "") + ")";
    claim_re = re.compile(
        f"^{_FOUNDED_PREFIX}{subject},?(?:{p["body"]}|{p["later"]}{p["extra"]})", re.I
    );
    batch = "(?i)\\bin\\s+the\\s+\\w+\\s+\\d{4}\\s+batch|hatched in|incubated in|participated in";
    found_in: list[any] = [];
    for s in _lines(html) {
        if not p["mention"].search(s) {
            continue;
        }
        hit = claim_re.search(s);
        if hit and p["in_needs_be"].search(hit.group(0)) and not re.search(batch, hit.group(0)) {
            hit = None;
        }
        (found, ok) = (
            p["cohort"](s),
            p["badge"].match(s) or hit or p["investors"].search(s) or p["leading"].search(s),
        );
        if ok and not ((not found or p["strict"]) and p["programs"].search(s)) {
            found_in.append(found);
        }
    }
    return found_in;
}

impl _lines(html: str) -> list[str] {
    text = unescape(re.sub("(?s)<[^>]+>", " ", re.sub(_BLOCK_TAG_RE, "\n", _strip_code(html))));
    text += "\n" + "\n".join(unescape(a) for a in re.findall(_ATTR_TEXT_RE, html));
    out: list[str] = [];
    for line in text.split("\n") {
        out.extend([
            s.strip()
            for s in re.split(_SENTENCE_RE, re.sub("\\s+", " ", line).strip())
            if s.strip()
        ]);
    }
    return out;
}

impl _alnum(text: str) -> str {
    return re.sub("[^a-z0-9]", "", text.lower());
}

impl _domain_name(domain: str) -> str {
    parts = [p for p in domain.lower().strip(".").split(".") if p];
    if len(parts) >= 3 and parts[-2] in _SECOND_LEVEL and len(parts[-1]) == 2 {
        return parts[-3];
    }
    return parts[-2] if len(parts) >= 2 else (parts[0] if parts else "");
}

impl _core(t: str) -> str {
    return re.sub(_SUFFIXES, "", re.sub(_PREFIXES, "", t));
}

impl _is_their_yc_page(slug: str, domain: str) -> bool {
    (name, label) = (_alnum(slug), _alnum(_domain_name(domain)) if domain else "");
    if not name or not label {
        return False;
    }
    return name == label
        or (min(len(_core(name)), len(_core(label))) >= 4 and _core(name) == _core(label));
}

impl _yc_cohort(sentence: str) -> any {
    for r in _YC_BATCH_RES {
        m = r.search(sentence);
        if m {
            return m;
        }
    }
    return None;
}

impl _yc_batch(m: any) -> str {
    (season, year) = (_YC_SEASONS[m.group(1).lower()], m.group(2)[-2:]);
    return f"{season}{year}" if int(year) >= 5 and int(year) <= 40 else "";
}

impl yc_backed(html: str, domain: str = "") -> tuple[str, float] | None {
    if not html {
        return None;
    }
    link = any(_is_their_yc_page(m.group(1), domain) for m in re.finditer(_YC_LINK_RE, html));
    found_in = _claims(_YC_CLAIMS, html, domain);
    batch = next((b for b in [_yc_batch(f) for f in found_in if f] if b), "");
    if link {
        return (batch, 0.95);
    }
    return (batch, 0.9 if batch else 0.85) if found_in else None;
}

impl _cohort_shapes(prog: str) -> list[any] {
    shapes = (
        f"\\b{prog}(?:['’]s)?{_CITY}\\s*[\\(\\[,]?\\s*(?:class of\\s+)?['’](\\d{{2}})\\b",
        f"\\b{prog}(?:['’]s)?{_CITY}\\s*[\\(\\[,]?\\s*(?:class of\\s+)?(20\\d{{2}})\\b",
        f"\\b{prog}\\s+(\\d{{2}})\\s*[\\)\\]]",
        f"\\b{prog}(?:['’]s)?\\s+(?:batch|cohort)\\s*#?\\s*(\\d{{1,2}})\\b",
        f"\\b{prog}(?:['’]s)?\\s*[\\(\\[]?\\s*(?-i:SR)\\s*(\\d{{1,3}})\\b",
    );
    return [
        (re.compile(p, re.I), t)
        for (p, t) in zip(shapes, "20{0}|{0}|20{0}|batch {1}|SR{1:03d}".split("|"))
    ];
}

impl _acc_cohort(shapes: list[any], sentence: str) -> str | None {
    for (shape, template) in shapes {
        m = shape.search(sentence);
        cohort = template.format(m.group(1), int(m.group(1))) if m else "";
        if m
            and not (
                cohort.startswith("20")
                and not (2005 <= int(cohort) and int(cohort) <= datetime.now().year + 1)
            )
        {
            return cohort;
        }
    }
    return None;
}

impl _on_logo_wall(html: str, prog: str) -> bool {
    logo = re.compile(
        f"(?:\\b(?:alt|aria-label|title)=[\"']|>)\\s*{prog}\\b[^\"'<]{{0,30}}(?:[\"']|<)", re.I
    );
    for label in re.finditer(_WALL_LABEL_RE, html) {
        end = label.end() + _WALL_SPAN;
        stop = _SECTION_END_RE.search(html, label.end(), end);
        m = logo.search(html, label.end(), stop.start() if stop else end);
        between = _text(html[label.end():m.start()]).strip() if m else "";
        if m and len(between) <= _WALL_TEXT and not re.search(_OTHER_WALL_RE, between) {
            return True;
        }
    }
    return False;
}

impl accelerators(html: str, domain: str = "") -> list[tuple[str, str, float]] {
    out: list[tuple[str, str, float]] = [];
    stripped = _strip_code(html) if html else "";
    for (name, prog, claims) in _ACC_CLAIMS if html else [] {
        found_in = _claims(claims, html, domain);
        stated = next((c for c in found_in if c), "");
        if found_in {
            out.append((name, stated, 0.9 if stated else 0.85));
        } elif _on_logo_wall(stripped, prog) {
            out.append((name, "", 0.8));
        }
    }
    return out;
}

impl _sentence_date(sentence: str) -> str {
    m = re.search(_ISO_DATE_RE, sentence);
    if m {
        return m.group(0);
    }
    m = re.search(_MONTH_DATE_RE, sentence);
    if m {
        month = _MONTHS[m.group(1).lower()[:3]];
        return f"{m.group(3)}-{month:02d}" + (f"-{int(m.group(2)):02d}" if m.group(2) else "");
    }
    m = re.search(_YEAR_RE, sentence);
    return m.group(1) if m else "";
}

impl _not_future(when: str) -> str {
    return "" if when and when > date.today().isoformat()[:len(when)] else when;
}

impl _page_date(html: str, url: str) -> str {
    path = urlparse(url or "").path;
    if not (
        re.search(_ARTICLE_PATH_RE, path)
        or re.search(_ARTICLE_TYPE_RE, html)
        or any(re.search(r, path) for r in _URL_DATE_RES)
    ) {
        return "";
    }
    for r in (_JSONLD_DATE_RE,) + _META_DATE_RES {
        m = re.search(r, html);
        if m {
            return m.group(1);
        }
    }
    for r in _URL_DATE_RES {
        m = re.search(r, url or "");
        if m {
            return "-".join(m.groups());
        }
    }
    times = set(re.findall(_TIME_RE, html));
    return times.pop() if len(times) == 1 else "";
}

impl _amount(symbol: str, number: str, suffix: str) -> str {
    suffix = (suffix or "").lower();
    if suffix and re.fullmatch("\\d{1,3},\\d{1,2}", number) {
        number = number.replace(",", ".");
    }
    try {
        value = float(number.replace(",", "")) * _MULTIPLIER.get(suffix, 1);
    } except ValueError {
        return "";
    }
    for (div, unit) in ((1e9, "B"), (1e6, "M"), (1e3, "K")) {
        if value >= div {
            return f"{symbol}{round(value / div, 2):g}{unit}";
        }
    }
    return f"{symbol}{value:g}";
}

impl _amount_in(text: str) -> str {
    m = re.search(_AMOUNT, text, re.I);
    if m {
        return _amount(m.group(1), m.group(2), m.group(3));
    }
    m = re.search(_AMOUNT_WORD, text, re.I);
    return _amount(_CURRENCY[m.group(3).lower()], m.group(1), m.group(2)) if m else "";
}

impl _round_name(text: str) -> str {
    text = re.sub("\\s+", " ", text.lower());
    if text.startswith("pre") {
        return "Pre-seed";
    }
    return "Series " + text[-1].upper() if text.startswith("series") else text.capitalize();
}

impl _raise_rank(c: dict[str, any]) -> tuple[any, ...] {
    r = c["round"];
    return (
        c["date"],
        _ROUND_RANK.get(r, 10 + ord(r[-1]) if r.startswith("Series") else 0),
        bool(c["amount"]),
    );
}

impl funding_round(html: str, domain: str = "", url: str = "") -> dict[str, any] | None {
    if not html {
        return None;
    }
    name = _alnum(_domain_name(domain)) if domain else "";
    spelled = "[\\s.-]?".join(re.escape(ch) for ch in name) if len(name) >= 3 else "";
    spelled = spelled and f"{spelled}(?:\\.[a-z]{{2,6}})?";
    subject = "(?:we(?:['’]ve)?|the company|our company"
        + (f"|{spelled}\\b" if spelled else "")
        + ")";
    owner = "(?:our" + (f"|{spelled}['’]s" if spelled else "") + ")";
    shapes = [
        f"^{_LEAD_IN}{_ANNOUNCE}?{subject},?(?:\\s+(?:has|have|had|just|now|recently|officially|successfully|today|also|finally))*\\s+{_RAISE_VERB}\\b(?P<rest>{_CLAUSE}{{0,160}})",
        f"^{_LEAD_IN}(?:(?:announcing|introducing|celebrating)\\s+|{_ANNOUNCE})(?:that\\s+)?{owner}\\s+(?P<rest>(?:{_AMOUNT}\\s+)?{_ROUND}{_CLAUSE}{{0,160}})",
        f"^{owner}\\s+(?P<rest>(?:{_AMOUNT}\\s+)?{_ROUND}(?:\\s+(?:round|funding|financing))?(?:\\s+(?:was|is|has been))?\\s+(?:led|co-led|closed|backed)\\b{_CLAUSE}{{0,160}})",
    ];
    res = [re.compile(s, re.I) for s in shapes];
    claims: list[dict[str, any]] = [];
    for sentence in _lines(html) {
        m = res[0].search(sentence) or res[1].search(sentence) or res[2].search(sentence);
        if m {
            claim = _claim(m, sentence);
            if claim {
                claims.append(claim);
            }
        }
    }
    if not claims {
        return None;
    }
    page_date = _not_future(_page_date(html, url));
    undated = [c for c in claims if not c["date"]];
    one = len({(u["round"], u["amount"]) for u in undated}) == 1;
    title = _page_title(html) if page_date else "";
    for c in undated if page_date else [] {
        if one
            or (c["round"] and c["round"].lower() in title)
            or (c["amount"] and _alnum(c["amount"]) in _alnum(title))
        {
            c["date"] = page_date;
        }
    }
    for c in claims {
        c["conf"] = 0.9 if c["date"] else 0.85;
    }
    return max(claims, key=_raise_rank);
}

impl _claim(m: any, sentence: str) -> dict[str, any] | None {
    rest = m.group("rest");
    end = re.search(_CLAUSE_END_RE, rest);
    rest = rest[:end.start()] if end else rest;
    if re.search(_NOT_THEIR_RAISE, rest) {
        return None;
    }
    rnd = re.search(f"\\b{_ROUND}", rest, re.I);
    amount = _amount_in(rest);
    plain = (m.groupdict().get("verb") or "").lower().startswith("rais")
        and amount[-1:] in ("M", "B");
    if not rnd
        and (
            not amount
            or re.search(_NOT_FUNDING_MONEY, rest)
            or not (plain or re.search(_FUNDING_EVIDENCE, rest))
        )
    {
        return None;
    }
    when = _not_future(_sentence_date(sentence[:m.start("rest")] + rest));
    return {"round": _round_name(rnd.group(1)) if rnd else "", "amount": amount, "date": when};
}

impl _page_title(html: str) -> str {
    parts = re.findall("(?is)<title[^>]*>(.*?)</title>", html)[:1];
    parts += re.findall(
        "(?i)<meta[^>]+property=[\"']og:title[\"'][^>]*content=[\"']([^\"']*)", html
    )[:1];
    parts += re.findall("(?is)<h1\\b[^>]*>(.*?)</h1>", html)[:1];
    return unescape(re.sub("(?s)<[^>]+>", " ", " ".join(parts))).lower();
}

impl _decides(title: str) -> bool {
    return any(t in fold_accents(title.lower()) for t in DECISION_MAKER_TITLES);
}

impl _benign(href: str, host: str) -> bool {
    return any(b in href.lower() or b in host for b in BENIGN_HOSTS);
}

impl _Observations.add(
    code: str, num: any = None, text: str = "", conf: float = 1.0, url: str = ""
) {
    if self.wants(code) {
        self.rows.append({
            "signal_code": code,
            "company_id": self.company_id,
            "collector": "profile",
            "value_num": num,
            "value_text": text,
            "confidence": conf,
            "evidence_url": url or self.site,
        });
    }
}

impl ProfileCollector.wants(code: str) -> bool {
    return code in self.confirmed;
}

impl ProfileCollector.__aenter__ -> ProfileCollector {
    headers: dict[str, str] = {
        "User-Agent": random.choice(USER_AGENTS),
        "Accept": "text/html,application/xhtml+xml,*/*;q=0.8",
    };
    self._client = public_http_client(timeout=TIMEOUT, headers=headers);
    return self;
}

impl ProfileCollector.__aexit__(*exc: any) {
    if self._client {
        await self._client.aclose();
    }
}

impl ProfileCollector._get(url: str) -> str {
    try {
        resp = await self._client.get(url);
    } except (httpx.HTTPError, ValueError) as e {
        logger.debug(f"fetch failed {url}: {e}");
        return "";
    }
    if resp.status_code in (200, 202, 403, 429, 503)
        and looks_like_challenge(resp.text or "", resp.status_code)
    {
        self.challenged.add(urlparse(url).netloc.lower().removeprefix("www."));
        return "";
    }
    ctype = resp.headers.get("content-type", "");
    if resp.status_code != 200
        or ("html" not in ctype and "xml" not in ctype and "text" not in ctype)
    {
        return "";
    }
    return resp.text;
}

impl ProfileCollector._resolve_site(domain: str) -> tuple[str, str] {
    for base in (
        f"https://{domain}",
        f"https://www.{domain}",
        f"http://{domain}",
        f"http://www.{domain}",
    ) {
        html = await self._get(base);
        if html {
            return (base, html);
        }
        if domain.lower().removeprefix("www.") in self.challenged {
            break;
        }
    }
    return ("", "");
}

impl ProfileCollector._first_present(site: str, paths: any) -> tuple[str, str] {
    for path in paths {
        html = await self._get(f"{site}{path}");
        if html and len(html) > 500 {
            return (f"{site}{path}", html);
        }
    }
    return ("", "");
}

impl ProfileCollector._careers_page(site: str, home: str, domain: str) -> tuple[str, str] {
    for link in re.finditer(
        "(?is)<a\\b[^>]*href=[\"\\']([^\"\\'#]+)[\"\\'][^>]*>(.*?)</a>", _strip_code(home)
    ) {
        url = urljoin(site + "/", link.group(1).strip());
        parsed = urlparse(url);
        host = (parsed.hostname or "").lower().removeprefix("www.");
        if parsed.scheme not in ("http", "https")
            or not (host == domain or host.endswith("." + domain))
        {
            continue;
        }
        anchor = re.sub("\\s+", " ", re.sub("(?s)<[^>]+>", " ", link.group(2))).strip();
        segments: any = {seg.lower() for seg in parsed.path.split("/") if seg};
        careers = re.match(_CAREERS_HOST, host)
            or segments & _CAREERS_SEGMENTS
            or re.match(_CAREERS_ANCHOR, unescape(anchor));
        if (segments or host != domain) and careers {
            html = await self._get(url);
            if html and len(html) > 500 {
                return (url, html);
            }
            break;
        }
    }
    return await self._first_present(site, CAREERS_PATHS);
}

impl ProfileCollector._hiring(site: str, home: str, domain: str, add: any) {
    (curl, chtml) = ("", "");
    board = detect_board(home, domain);
    if board is None {
        (curl, chtml) = await self._careers_page(site, home, domain);
        board = detect_board(chtml, domain);
    }
    postings = (await read_board(self._client, board)) if board else None;
    if postings is not None {
        add("OPEN_ROLES", num=len(postings), text=board.label, url=board.page_url);
        matched = matching_roles(postings, self.role_keywords or [])[:MAX_BOARD_ROLES];
        for post in matched {
            add("HIRING_ROLE", text=post.summary(), url=post.url or board.page_url);
        }
        if not matched {
            add("HIRING_ROLE", num=0, url=board.page_url);
        }
        return;
    }
    if board and not chtml {
        (curl, chtml) = await self._careers_page(site, home, domain);
    }
    roles: list[str] = [];
    hiring = "(?i)\\b(hiring|apply|position|opening|wanted|technician|installer|sales|manager|foreman|estimator|crew|representative)\\b";
    listed = _strip_code(chtml) if chtml and self.wants("HIRING_ROLE") else "";
    for m in re.finditer("(?is)<(h[2-5]|a|li)[^>]*>\\s*([^<]{6,70})\\s*</\\1>", listed) {
        t = re.sub("\\s+", " ", m.group(2)).strip();
        if re.search(hiring, t) and t.lower() not in [r.lower() for r in roles] {
            roles.append(t);
        }
        if len(roles) >= 3 {
            break;
        }
    }
    for r in roles {
        add("HIRING_ROLE", text=r, url=curl);
    }
}

impl ProfileCollector._search_hit(company_id: str, code: str) -> bool {
    if self.state is None {
        return False;
    }
    try {
        return await self.state.search_hit(company_id, code);
    } except Exception {
        return False;
    }
}

impl ProfileCollector._own_hit_page(company_id: str, domain: str, site: str) -> str {
    try {
        company = await self.state.get_company(company_id);
    } except Exception {
        return "";
    }
    url = (getattr(company, "source_url", "") or "").strip();
    parsed = urlparse(url);
    host = (parsed.hostname or "").lower().removeprefix("www.");
    if parsed.scheme not in ("http", "https")
        or not (host == domain or host.endswith("." + domain))
        or parsed.path.strip("/") == ""
        or url.rstrip("/") == site.rstrip("/")
    {
        return "";
    }
    return url;
}

impl ProfileCollector.detect_agency(html: str, domain: str) -> tuple[str, float, str] | None {
    cleaned = _strip_code(html);
    m = re.search("(?is)<footer\\b.*?</footer>", cleaned);
    region = m.group(0) if m else cleaned[-12000:];
    best: tuple[str, float, str] | None = None;
    for link in re.finditer(
        "(?is)<a\\b[^>]*href=[\"\\']([^\"\\']+)[\"\\'][^>]*>(.*?)</a>", region
    ) {
        href = link.group(1);
        anchor = re.sub("\\s+", " ", re.sub("(?s)<[^>]+>", " ", link.group(2))).strip();
        host = (urlparse(href).netloc or "").lower().replace("www.", "")
            if href.startswith("http")
            else "";
        if not host
            or host.endswith(domain)
            or domain.endswith(host)
            or _benign(href, host)
            or not anchor
            or len(anchor) > 80
        {
            continue;
        }
        context = re.sub("(?s)<[^>]+>", " ", region[max(0, link.start() - 120):link.start()]);
        conf = 0.9
            if re.search(STRONG_CREDIT, f"{context} {anchor}")
            else (0.75 if re.search(DESCRIPTIVE_CREDIT, anchor) else 0.35);
        if conf >= RECORD_FLOOR and (best is None or conf > best[1]) {
            best = (anchor[:80], conf, href);
        }
    }
    return best;
}

impl ProfileCollector.detect_tech(html: str) -> list[str] {
    return sorted(
        name for (name, patterns) in TECH_FINGERPRINTS.items() if self._any(html, patterns)
    );
}

impl ProfileCollector._any(html: str, patterns: any) -> bool {
    return any(re.search(p, html, re.I) for p in patterns);
}

impl ProfileCollector.detect_people(
    html: str, domain: str = "", site_name: str = ""
) -> list[dict[str, any]] {
    pm = import_module("sellbird.collectors.people");
    text_html = _strip_code(pm.drop_quoted(nfc(html)));
    folded_html = fold_accents(text_html);
    cands: list[any] = [];
    heading = "(?s)<((?i:h[1-5]|strong|b))[^>]*>\\s*((?:Dre?\\.?\\s+)?[A-Z][a-z'’\\-]+(?:\\s+[A-Z]\\.?)?(?:\\s+(?:[A-Z][a-zA-Z'’\\-]+|van|von|de|der|del|du|la|le|di|da)){1,3}(?:,?\\s+(?:DDS|DMD|MD|Esq\\.?|CPA|Jr\\.?|Sr\\.?|II|III))?)\\s*</(?i:\\1)>(?=(.{0,220}))";
    for m in re.finditer(heading, folded_html) {
        name = re.sub("\\s+", " ", text_html[m.start(2):m.end(2)]).strip();
        raw_after = text_html[m.start(3):m.end(3)];
        nxt = re.search("(?i)<(h[1-5]|strong|b)\\b", raw_after);
        raw_after = raw_after[:nxt.start()] if nxt else raw_after;
        if len(name) > 45
            or re.search("\\d|@|\\bthe\\b|\\bour\\b|\\bwe\\b", name, re.I)
            or not _name_like(name)
        {
            continue;
        }
        split = pm.split_person_name(name);
        title = next((c for c in _title_chunks(raw_after)[:2] if _reads_like_title(c)), "")
            if split
            else "";
        if title {
            cands.append((split[0], split[1], title, re.sub("(?i)^dre?\\.?\\s+", "", name)));
        }
    }
    for p in pm.people_from_lines(html, domain, site_name) {
        if _name_like(p["first_name"] + " " + p["last_name"]) {
            cands.append((p["first_name"], p["last_name"], p["title"], p["full_name"]));
        }
    }
    people: list[dict[str, any]] = [];
    seen: set[any] = set();
    for (first, last, title, full_name) in cands {
        key = (first.lower(), last.lower());
        if key in seen or len(people) >= 12 or pm.title_names_other_org(title, domain, site_name) {
            continue;
        }
        seen.add(key);
        people.append({
            "first_name": first,
            "last_name": last,
            "full_name": full_name or f"{first} {last}",
            "title": title[:80],
            "is_decision_maker": _decides(title),
        });
    }
    return people;
}

impl ProfileCollector.profile_company(company_id: str, domain: str) -> list[dict[str, any]] {
    out = _Observations(self.wants, company_id);
    domain = domain.lower().replace("www.", "").strip("/");
    if any(domain == d or domain.endswith("." + d) for d in YC_OWNED_DOMAINS) {
        return out.rows;
    }
    (site, home) = await self._resolve_site(domain);
    out.site = site;
    if not home {
        if domain in self.challenged {
            logger.info(
                f"profile: {domain} answered with a bot challenge (challenged, not unreachable)"
            );
        } else {
            logger.info(f"profile: {domain} unreachable");
        }
        return out.rows;
    }
    self.site_names[company_id] = site_name_from_html(home, domain);
    out.add("RUNNING_GOOGLE_ADS", num=1 if self._any(home, GOOGLE_ADS) else 0);
    out.add("RUNNING_META_ADS", num=1 if self._any(home, META_PIXEL) else 0);
    tech = self.detect_tech(home);
    if tech {
        out.add("TECH_STACK", text=", ".join(tech));
    }
    has_schema = re.search("(?i)application/ld\\+json", home) and re.search("\"@type\"", home);
    out.add("NO_SCHEMA_MARKUP", num=0 if has_schema else 1);
    out.add("NO_ONLINE_BOOKING", num=0 if self._any(home, BOOKING_HINTS) else 1);
    about: tuple[str, str] | None = None;
    if self.wants("YC_BACKED") {
        (yc, where) = (yc_backed(home, domain), site);
        if yc is None {
            about = about or await self._first_present(site, YC_ABOUT_PATHS);
            if about[1] {
                (yc, where) = (yc_backed(about[1], domain), about[0]);
            }
        }
        searched = yc is None and await self._search_hit(company_id, "YC_BACKED");
        if yc is not None or not searched {
            (num, text, conf, url) = (1, yc[0], yc[1], where) if yc else (0, "", 1.0, site);
            out.add("YC_BACKED", num, text, conf, url);
        }
    }
    if self.wants("ACCELERATOR") {
        (programs, where) = (accelerators(home, domain), site);
        if not programs {
            about = about or await self._first_present(site, YC_ABOUT_PATHS);
            if about[1] {
                (programs, where) = (accelerators(about[1], domain), about[0]);
            }
        }
        text = "; ".join(f"{p} {c}".strip() for (p, c, _) in programs);
        conf = max(c for (_, _, c) in programs) if programs else 1.0;
        out.add("ACCELERATOR", 1 if programs else 0, text, conf, where if programs else site);
    }
    if self.wants("FUNDING_ROUND") {
        pages = [(site, home)];
        hit = await self._own_hit_page(company_id, domain, site);
        if hit {
            pages.append((hit, await self._get(hit)));
        }
        about = about or await self._first_present(site, YC_ABOUT_PATHS);
        pages.append(about);
        found: list[any] = [];
        for (url, html) in pages {
            f = funding_round(html, domain, url) if html else None;
            if f {
                found.append((f, url));
            }
        }
        if not found {
            (url, html) = await self._first_present(site, FUNDING_PATHS);
            f = funding_round(html, domain, url) if html else None;
            found = [(f, url)] if f else [];
        }
        if found {
            (best, where) = max(found, key=lambda (fu: any) -> any { fu[0]["date"] });
            out.add("FUNDING_ROUND", num=1, text=funding_text(best), conf=best["conf"], url=where);
        } else {
            out.add("FUNDING_ROUND", num=0, url=site);
        }
    }
    agency = self.detect_agency(home, domain);
    if agency {
        out.add("INCUMBENT_AGENCY", text=agency[0], conf=agency[1], url=agency[2]);
    }
    if self.wants("BLOCKS_AI_CRAWLERS") {
        robots = (await self._get(f"{site}/robots.txt")).lower();
        rule = "user-agent:\\s*{}[\\s\\S]{{0,200}}?disallow:\\s*/";
        blocked = any(re.search(rule.format(re.escape(bot)), robots) for bot in AI_CRAWLERS);
        out.add("BLOCKS_AI_CRAWLERS", num=1 if blocked else 0, url=f"{site}/robots.txt");
    }
    if self.wants("SITE_PAGE_COUNT") or self.wants("BLOG_STALE") {
        sm = await self._get(f"{site}/sitemap.xml");
        locs = re.findall("<loc>\\s*([^<]+)\\s*</loc>", sm);
        dates = re.findall("<lastmod>\\s*(\\d{4}-\\d{2}-\\d{2})", sm);
        if self.wants("SITE_PAGE_COUNT") and locs {
            out.add("SITE_PAGE_COUNT", num=len(locs), url=f"{site}/sitemap.xml");
        }
        if dates and self.wants("BLOG_STALE") {
            (newest, today) = (max(dates), datetime.now(timezone.utc).date());
            try {
                age = (today - datetime.strptime(newest, "%Y-%m-%d").date()).days;
                out.add("BLOG_STALE", age, f"newest content {newest}", 1.0, f"{site}/sitemap.xml");
            } except ValueError {}
        }
    }
    if self.wants("CONTACT_FORM_URL") {
        if re.search("(?is)<form\\b", _strip_code(home)) {
            out.add("CONTACT_FORM_URL", text=site, url=site);
        } else {
            (curl, chtml) = await self._first_present(site, CONTACT_PATHS);
            if chtml and re.search("(?is)<form\\b", _strip_code(chtml)) {
                out.add("CONTACT_FORM_URL", text=curl, url=curl);
            }
        }
    }
    if self.wants("HIRING_ROLE") or self.wants("OPEN_ROLES") {
        try {
            await self._hiring(site, home, domain, out.add);
        } except Exception as e {
            logger.info(f"profile: {domain} open roles unread: {type(e).__name__}: {e}");
        }
    }
    if self.wants("CONTACT_FOUND") or self.wants("DECISION_MAKER_TITLE") {
        (turl, thtml) = await self._first_present(site, TEAM_PATHS);
        name = self.site_names.get(company_id, "");
        team = self.detect_people(thtml, domain=domain, site_name=name) if thtml else [];
        for person in team {
            label = f"{person["first_name"]} {person["last_name"]}";
            titled = f"{label} — {person["title"]}";
            out.add("CONTACT_FOUND", text=titled if person["title"] else label, url=turl);
            if person["is_decision_maker"] {
                out.add("DECISION_MAKER_TITLE", text=titled, url=turl);
            }
        }
    }
    return out.rows;
}

impl ProfileCollector._improve_name(company: dict[str, any], domain: str) {
    better = self.site_names.pop(company["id"], "");
    current = company.get("name") or "";
    fallback = current == name_from_domain(domain);
    if not better or better == current or (name_matches_domain(current, domain) and not fallback) {
        return;
    }
    try {
        await self.state.rename_company(company["id"], better);
        logger.info(f"profile: {domain} named '{better}' (was '{current}')");
    } except Exception as e {
        logger.debug(f"rename_company failed for {domain}: {e}");
    }
}

impl ProfileCollector._mark_checked(company_id: str) {
    try {
        await self.state.mark_company_profiled(company_id);
    } except Exception as e {
        logger.debug(f"mark_company_profiled failed for {company_id}: {e}");
    }
}

impl ProfileCollector.run(companies: list[dict[str, any]], run_id: str = "") -> int {
    total = 0;
    for company in companies {
        domain = (company.get("domain") or "").strip();
        if not domain {
            continue;
        }
        try {
            obs = await self.profile_company(company["id"], domain);
        } except Exception as e {
            logger.warning(f"profile failed for {domain}: {e}");
            await self._mark_checked(company["id"]);
            continue;
        }
        await self._mark_checked(company["id"]);
        await self._improve_name(company, domain);
        if obs {
            total += await self.state.add_observations(obs, run_id=run_id);
            logger.info(f"profile: {domain} → {len(obs)} observation(s)");
        }
        await asyncio.sleep(random.uniform(0.4, 1.2));
    }
    return total;
}

impl profile_companies(
    state: any, companies: list[dict[str, any]], config: any = None
) -> tuple[int, str] {
    await seed_signal_catalog(state);
    confirmed = await state.confirmed_signal_codes();
    if not confirmed {
        logger.warning(
            "profile: no signals confirmed yet — confirm signals first (nothing is collected until you choose what matters).",
        );
        return (0, "");
    }
    run_id = await state.start_run("profile", provider="http");
    try {
        keywords = role_keywords(getattr(config, "icp", None));
        async with ProfileCollector(state, confirmed, role_keywords=keywords) as collector {
            n = await collector.run(companies, run_id=run_id);
        }
        await state.finish_run(run_id, records=n, cost_usd=0.0);
        return (n, run_id);
    } except Exception as e {
        await state.finish_run(run_id, status="failed", error=str(e));
        raise;
    }
}
