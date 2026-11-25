impl _Found.add(
    split: any, title: str, source: str, ev: str, url: str, full: str, owner: bool = False
) {
    key = (split[0].lower(), split[1].lower()) if split else None;
    if key and key not in self.seen {
        self.seen.add(key);
        self.people.append({
            "first_name": split[0],
            "last_name": split[1],
            "title": title[:80].strip(" ,;:-–—|"),
            "full_name": full or f"{split[0]} {split[1]}",
            "owner": owner,
            "source": source,
            "evidence": ev[:200],
            "evidence_url": url,
        });
    }
}

impl _word_ok(token: str) -> bool {
    low = fold_accents(token.strip(".,'’")).lower();
    return bool(low)
        and low not in COMMON_WORDS
        and low not in NON_NAME_WORDS
        and not _NOUN_SUFFIX.search(low);
}

impl split_person_name(text: str) -> tuple[str, str] | None {
    text = re.sub("\\s+", " ", html_lib.unescape(text or "").replace("\xa0", " ")).strip(" ,.-|–—");
    text = re.sub(_HONORIFIC, "", re.sub("(?i)^(?:meet|introducing)\\s+", "", text));
    text = nfc(re.sub(_CREDENTIAL_TAIL, "", text).strip(" ,"));
    tokens = text.split();
    odd = len(text) > 45 or any(ch.isdigit() for ch in text) or "@" in text;
    if odd or len(tokens) not in (2, 3, 4, 5) {
        return None;
    }
    folded = fold_accents(text).split();
    (first, rest) = (folded[0], folded[1:]);
    start = len(rest) - 1;
    while start > 0 and rest[start - 1].lower() in _PARTICLES {
        start -= 1;
    }
    (surname, last_word) = (rest[start:], rest[-1]);
    if not re.match("^[A-Z][a-z]+(?:[-'’][A-Z]?[a-z]+)*$", first)
        or not _word_ok(first)
        or not all(
            re.match(_NAME_TOKEN, t) and (len(t.strip(".")) == 1 or _word_ok(t))
            for t in rest[:start],
        )
        or not re.match("^[A-Z][a-zA-Z]*(?:[-'’][A-Z]?[a-zA-Z]+)*$", last_word)
        or len(last_word) < 2
        or (last_word.isupper() and len(last_word) > 2)
        or not _word_ok(last_word)
        or first.isupper()
        or any(t.lower() not in _PARTICLES for t in surname[:-1])
    {
        return None;
    }
    return (tokens[0], " ".join(tokens[1 + start:]));
}

impl is_person_name(text: str) -> bool {
    return split_person_name(text) is not None;
}

impl _norm_title(text: str) -> str {
    feminine = lambda (m: any) -> any { _FEMININE.get(m.group(0), m.group(0)) };
    return re.sub("[a-z]+", feminine, fold_accents(text or "").lower());
}

impl _family_key(text: str) -> str {
    return re.sub("[\\s\\-–]+", " ", _norm_title(text).strip());
}

impl is_owner_title(title: str) -> bool {
    title = fold_accents((title or "").strip());
    return bool(title)
        and not re.search(_SUBORDINATE, title)
        and not re.search(_FORMER, title)
        and bool(re.search(_OWNER_TITLE, title) or re.match(_PARTNER_ONLY, title));
}

impl _clean_for_target(title: str, target: str) -> str {
    low = f" {_norm_title(title)} ";
    if "vice" not in target and "vp" not in target.split() {
        low = re.sub("\\bvice[- ]president\\b|\\b[se]?vp\\b", " ", low);
    }
    if "assistant" not in target {
        low = re.sub("\\b(?:executive )?assistant\\b.*", " ", low);
    }
    if not re.search("\\badjoint|\\bsous-", target)
        and re.search("\\badjoint\\b|\\bsous-\\w", low)
    {
        return " ";
    }
    return re.sub("\\bto the\\b.*", " ", low);
}

impl title_matches(title: str, targets: any, owner: bool = False) -> bool {
    title = (title or "").strip();
    wanted = [_norm_title(t.strip()) for t in targets or [] if t and t.strip()];
    if not wanted or re.search(_FORMER, fold_accents(title)) {
        return False;
    }
    if any(_family_key(t) in _OWNER_FAMILY_KEYS for t in wanted)
        and (owner or is_owner_title(title))
    {
        return True;
    }
    return bool(title)
        and any(
            re.search(f"(?<![\\w-]){re.escape(t)}(?![\\w])", _clean_for_target(title, t))
            for t in wanted,
        );
}

impl owner_rank(title: str, owner: bool = False) -> int {
    low = fold_accents(title or "").lower();
    if is_owner_title(title) {
        if re.search("\\b(?:co-?owner|owner|proprietor|co-?proprietaire|proprietaire)\\b", low) {
            return 100;
        }
        president = "\\b(?:presidente?|pdg|p\\.-?d\\.g|fondat(?:eur|rice)|co-?fondat(?:eur|rice))\\b";
        general = re.search("\\bdirect(?:eur|rice) generale?\\b", low)
            and not re.search(president, low);
        return 92 if general else 95;
    }
    if owner {
        return 90;
    }
    if re.search("\\bpartner\\b|\\bassociee?s?\\b(?!\\s*(?:aux?|a la|en)\\b)", low) {
        return 80;
    }
    if re.search("\\b(?:general manager|managing director)\\b", low) {
        return 60;
    }
    manager = "\\b(?:director|manager|head of|chief|directeur|directrice|gerante?|gestionnaire|responsable)\\b";
    return 40 if re.search(manager, low) and not re.search(_SUBORDINATE, low) else 10;
}

impl _alnum(text: str) -> str {
    return re.sub("[^a-z0-9]", "", fold_accents(text or "").lower());
}

impl _domain_label(domain: str) -> str {
    host = re.sub("^https?://", "", (domain or "").lower().strip().removeprefix("www."));
    parts = [p for p in host.split("/")[0].split(".") if p];
    if len(parts) >= 3 and parts[-2] in ("co", "com", "org", "net") and len(parts[-1]) == 2 {
        return parts[-3];
    }
    return parts[-2] if len(parts) >= 2 else (parts[0] if parts else "");
}

impl names_business(text: str, domain: str, site_name: str = "") -> bool {
    blob = _domain_label(domain) + "|" + _alnum(site_name);
    words = re.findall("[a-z0-9]+", fold_accents(text or "").lower());
    if any(len(w) >= 3 and w not in _GENERIC_BUSINESS_WORDS and w in blob for w in words) {
        return True;
    }
    (squashed, label) = (_alnum(text), _domain_label(domain));
    return len(squashed) >= 4 and (squashed in blob or (len(label) >= 4 and label in squashed));
}

impl surname_on_the_door(last_name: str, domain: str, site_name: str = "") -> bool {
    blob = _domain_label(domain) + "|" + _alnum(site_name);
    parts = [p.lower() for p in re.findall("[A-Za-z]+", fold_accents(last_name or ""))];
    return any(len(p) >= 4 and p not in _GENERIC_BUSINESS_WORDS and p in blob for p in parts);
}

impl title_names_other_org(title: str, domain: str, site_name: str = "") -> bool {
    roles = "(?i)(?:and\\s+)?(?:owner|founder|co-?founder|ceo|cto|coo|cmo|president|principal|partner|director|chief[\\w\\s]*|operations|executive officer)";
    for m in re.finditer(_TITLE_ORG, fold_accents(title or "")) {
        org = m.group(1).strip();
        if not re.fullmatch(roles, org)
            and not re.fullmatch(f"(?i){_FR_TITLE_WORDS}", org)
            and not names_business(org, domain, site_name)
        {
            return True;
        }
    }
    return False;
}

impl _close_of(html: str, start: int, tag: str) -> int {
    depth = 0;
    pattern = re.compile(f"(?i)<(/?){re.escape(tag)}\\b[^>]*?(/?)>");
    for m in pattern.finditer(html, start, min(len(html), start + MAX_QUOTE_CHARS)) {
        depth += 0 if m.group(2) else (-1 if m.group(1) else 1);
        if depth == 0 and not m.group(2) {
            return m.end();
        }
    }
    return start;
}

impl drop_quoted(html: str) -> str {
    html = re.sub(_STATUS_LINK, " ", html or "");
    out: list[str] = [];
    pos = 0;
    for (n, m) in enumerate(re.finditer(_QUOTED_CLASS, html)) {
        if n >= MAX_QUOTES {
            break;
        }
        if m.start() < pos or m.group(1).lower() in _VOID_TAGS {
            continue;
        }
        end = _close_of(html, m.start(), m.group(1));
        if end > m.start() {
            out.append(html[pos:m.start()]);
            pos = max(end, m.end());
        }
    }
    html = "".join(out) + html[pos:];
    return re.sub("(?is)<blockquote\\b(?:(?!</?blockquote).){0,8000}</blockquote>", " ", html);
}

impl page_lines(html: str) -> list[str] {
    text = re.sub(_LINE_BREAK, "\n", _strip_code(nfc(html)));
    text = html_lib.unescape(re.sub("(?s)<[^>]+>", " ", text)).replace("\xa0", " ");
    lines = [re.sub("\\s+", " ", line).strip(" |·•") for line in text.split("\n")];
    return [line for line in lines if line];
}

impl _sentences(html: str) -> list[str] {
    blocks = "(?i)<(?:/?(?:p|div|li|h[1-6]|section|article|td|tr|blockquote|figcaption|dd|dt)\\b[^>]*|br\\s*/?)>";
    text = re.sub(blocks, "\n", _strip_code(nfc(html)));
    text = nfc(html_lib.unescape(re.sub("(?s)<[^>]+>", " ", text)).replace("\xa0", " "));
    abbrev = "\\b(Dre?|Mr|Mrs|Ms|Mme|Mlle|Prof|St|Ste|Jr|Sr|Inc|Co|Ltd|Lt[ée]e|[A-Z])\\. ";
    out: list[str] = [];
    for block in text.split("\n") {
        block = re.sub(abbrev, "\\1.\xa0", re.sub("\\s+", " ", block).strip());
        out.extend([
            s.strip()
            for s in re.split("(?<=[.!?]) +(?=[A-ZÀ-ÖØ-Þ])", block)
            if s.strip()
        ]);
    }
    return out;
}

impl people_from_lines(
    html: str, domain: str = "", site_name: str = "", url: str = ""
) -> list[any] {
    lines = page_lines(drop_quoted(html));
    found = _Found();
    for (i, line) in enumerate(lines) {
        nxt = lines[i + 1] if i + 1 < len(lines) else "";
        (name, m) = (split_person_name(line), re.match(_SEPARATED, line));
        if re.search(_QUOTE_LINE, lines[i - 1] if i else "") or re.match("^[—–-]\\s*\\S", line) {
            continue;
        } elif name and _reads_like_title(nxt) and not nxt.rstrip().endswith(("!", "?")) {
            (title, raw) = (nxt, line);
        } elif m {
            (title, raw) = (m.group("title").strip(), m.group("name").strip());
            strong = _reads_like_title(title) and re.search(_STRONG_ROLE, fold_accents(title));
            ok = strong and not title.endswith(".") and len(title.split()) <= 7;
            name = split_person_name(m.group("name")) if ok else None;
        } else {
            continue;
        }
        if name and not title_names_other_org(title, domain, site_name) {
            found.add(name, title, "card", f"{raw} — {title}", url, raw);
        }
    }
    return found.people;
}

impl _nodes(data: any) -> list[any] {
    if isinstance(data, list) {
        return [n for item in data for n in _nodes(item)];
    }
    if not isinstance(data, dict) {
        return [];
    }
    return [data] + [n for k in _GRAPH_KEYS if k in data for n in _nodes(data[k])];
}

impl _as_list(value: any) -> list[any] {
    return [] if value is None else (value if isinstance(value, list) else [value]);
}

impl _types(item: any) -> list[str] {
    return [x.lower() for x in _as_list(item.get("@type", "")) if isinstance(x, str)];
}

impl people_from_schema(html: str, url: str = "") -> list[any] {
    found = _Found();
    for raw in re.findall(_LD_JSON, html or "") {
        try {
            data = json.loads(raw.strip());
        } except (ValueError, TypeError) {
            continue;
        }
        nodes = _nodes(data);
        by_id = {n.get("@id"): n for n in nodes if isinstance(n.get("@id"), str)};
        for item in nodes {
            types = _types(item);
            if not types or _NOT_STAFF_TYPES.intersection(types) {
                continue;
            }
            for (key, default_title) in _ORG_KEYS.items() {
                for v in _as_list(item.get(key)) {
                    if isinstance(v, dict) and set(v) <= {"@id"} and v.get("@id") in by_id {
                        v = by_id[v["@id"]];
                    }
                    name: any = v if isinstance(v, str) else "";
                    title = default_title;
                    if isinstance(v, dict) {
                        if v.get("@type") and "person" not in _types(v) {
                            continue;
                        }
                        names = (v.get("givenName"), v.get("familyName"));
                        name = v.get("name") or " ".join([x for x in names if isinstance(x, str)]);
                        jt = v.get("jobTitle");
                        title = jt.strip() if isinstance(jt, str) and jt.strip() else title;
                    }
                    split = split_person_name(name if isinstance(name, str) else "");
                    owner = default_title in ("Founder", "Owner") or is_owner_title(title);
                    ev = f"schema.org {key}: {name}";
                    found.add(split, title or "Team member", "schema", ev, url, name, owner);
                }
            }
        }
    }
    found.people.sort(key=lambda (p: any) -> int { -owner_rank(p["title"], p["owner"]) });
    return found.people;
}

impl _departed(person: dict[str, any], text: str) -> bool {
    first = re.escape(fold_accents(person["first_name"]));
    last = re.escape(fold_accents(person["last_name"].split()[-1]));
    return bool(
        re.search(
            f"(?i)(?:\\bthe late|in (?:loving )?memory of|remembering|\\bfeue?|(?:a la|en) memoire de(?: feue?)?)\\s+(?:dre?\\.?\\s+|m\\.\\s+|mme\\s+)?{first}\\b|\\b{first}\\b(?:\\s+(?:\\w\\.|\\w+)){{0,3}}?(?:\\s+{last})?\\s*,?[^.]{{0,40}}?\\b{_DEPARTED}",
            text,
        ),
    );
}

impl _title_word(word: str) -> str {
    low = re.sub("\\s+", " ", word.lower()).strip();
    folded = fold_accents(low);
    if low == "ceo" or low.startswith("partner") {
        return "CEO" if low == "ceo" else "Partner";
    }
    if re.fullmatch("pdg|p\\.-?d\\.g\\.?", folded) {
        return "PDG";
    }
    if folded != low or re.match(_FRENCH_TITLE, folded) {
        return low[:1].upper() + low[1:];
    }
    return "-".join(p.capitalize() for p in low.split("-")).replace("Co-Founder", "Co-founder");
}

impl _prose_match(
    m: any, sentence: str, folded: str, fixed: str, domain: str, site_name: str
) -> any {
    groups = {
        k: (sentence[m.start(k):m.end(k)] if v is not None else None)
        for (k, v) in m.groupdict().items()
    };
    org = fold_accents(groups.get("org") or "");
    own_org = re.match(f"(?i)the\\s|(?:l['’]|la\\s+|son\\s+|sa\\s+){_FR_ORG_NOUN}\\b", org);
    if org and not own_org and not names_business(org, domain, site_name) {
        return None;
    }
    tail = groups.get("tail");
    if tail is None {
        tail = folded[m.end():m.end() + 60];
        tail = tail if re.match("^\\s+(?:of|at|chez)\\s", tail) else "";
    }
    t = fold_accents(tail).strip().lstrip(",;:-–—").strip();
    m_org = re.match(_ORG_AFTER, t);
    if m_org
        and not re.fullmatch(_ROLE_ONLY, m_org.group(1))
        and not names_business(m_org.group(1), domain, site_name)
    {
        return None;
    }
    return (groups["name"], fixed or _title_word(groups.get("title") or ""), sentence);
}

impl people_from_prose(html: str, domain: str, site_name: str = "", url: str = "") -> list[any] {
    html = drop_quoted(html);
    sentences = _sentences(html);
    cands: list[any] = [];
    for sentence in sentences {
        folded = fold_accents(sentence);
        for (regex, fixed) in _PROSE {
            for m in regex.finditer(folded) {
                cands.append(_prose_match(m, sentence, folded, fixed, domain, site_name));
            }
        }
    }
    listed: dict[str, set[any]] = {};
    for line in page_lines(html) {
        split = split_person_name(line);
        if split {
            listed.setdefault(fold_accents(split[0]).lower(), set()).add((split, line));
        }
    }
    for sentence in sentences {
        for m in re.finditer(_FIRST_NAME_FOUNDER, fold_accents(sentence)) {
            matches = listed.get(m.group("first").lower(), set());
            if len({s[0] for s in matches}) == 1
                and names_business(m.group("org"), domain, site_name)
            {
                cands.append((next(iter(matches))[1], "Founder", sentence));
            }
        }
    }
    if re.search(_FIRST_PERSON, fold_accents(" ".join(sentences))) {
        heads = re.findall("(?is)<title[^>]*>(.*?)</title>", html)[:1]
            + re.findall("(?is)<h1[^>]*>(.*?)</h1>", html)[:1];
        bio = "(?i)^\\s*(?:meet\\s+|rencontrez\\s+)?(?:attorney|dre?\\.?|doctor|lawyer|founder|owner|me|fondat(?:eur|rice)|propri[ée]taire|pr[ée]sidente?)\\s+";
        for raw in heads {
            text = html_lib.unescape(re.sub("(?s)<[^>]+>", " ", raw));
            head = re.sub(bio, "", re.split("\\s[|–—-]\\s|\\|", text)[0]);
            if split_person_name(head) {
                cands.append((head, "Founder", "first-person founder on a bio page"));
                break;
            }
        }
    }
    found = _Found();
    for (raw_name, title, sentence) in [c for c in cands if c is not None] {
        words = raw_name.split();
        split = split_person_name(raw_name)
            or (split_person_name(" ".join(words[:2])) if len(words) > 2 else None);
        found.add(split, title, "prose", sentence, url, raw_name, is_owner_title(title));
    }
    found.people.sort(key=lambda (p: any) -> int { -owner_rank(p["title"], p["owner"]) });
    return found.people;
}

impl _merge(merged: dict[any, any], p: dict[str, any]) {
    key = (p["first_name"].lower(), p["last_name"].split()[-1].lower());
    p = {k: v for (k, v) in p.items() if k != "is_decision_maker"};
    p["owner"] = bool(p.get("owner")) or is_owner_title(p["title"]);
    cur = merged.setdefault(key, p);
    if cur is p {
        return;
    }
    better = owner_rank(p["title"], p["owner"]) > owner_rank(cur["title"], cur["owner"]);
    weak = owner_rank(cur["title"]) < 40;
    if (cur["source"] != "card" and p["source"] == "card")
        or (better and (cur["source"] != "card" or p["source"] == "card" or weak))
    {
        for k in ("title", "evidence", "evidence_url", "source") {
            cur[k] = p[k];
        }
    }
    cur["owner"] = cur["owner"] or p["owner"];
}

impl _founded_by_history(p: dict[str, any]) -> bool {
    history = "(?i)\\bfounded\\b[^.]*\\bby\\b|\\bour founder\\b|\\bfondee?s?\\b[^.]*\\bpar\\b|\\b(?:notre|son|sa|leur)\\s+fondat(?:eur|rice)\\b";
    return p["source"] == "prose"
        and fold_accents(p["title"]).lower() in ("founder", "fondateur", "fondatrice")
        and bool(re.search(history, fold_accents(p["evidence"])));
}

impl find_people(pages: list[tuple[str, str]], domain: str, site_name: str = "") -> list[any] {
    detect = ProfileCollector(state=None).detect_people;
    merged: dict[any, any] = {};
    for (url, html) in pages {
        for c in detect(html, domain=domain, site_name=site_name) {
            ev = {"evidence": c["full_name"] + " — " + c["title"], "evidence_url": url};
            _merge(merged, c | {"source": "card", "owner": False} | ev);
        }
        for q in people_from_schema(html, url=url)
            + people_from_prose(html, domain, site_name, url=url) {
            _merge(merged, q);
        }
    }
    text = fold_accents(" ".join(" ".join(_sentences(html))[:200000] for (_, html) in pages));
    people = [p for p in merged.values() if not _departed(p, text)];
    if any(p["source"] != "prose" and p["owner"] for p in people) {
        people = [p for p in people if not _founded_by_history(p)];
    }
    for p in people {
        surnames = " ".join(p.get("full_name", p["last_name"]).split()[1:]) or p["last_name"];
        p["rank"] = owner_rank(p["title"], p["owner"])
            + (3 if p["source"] == "card" and is_owner_title(p["title"]) else 0)
            + (2 if p["owner"] and surname_on_the_door(surnames, domain, site_name) else 0)
            - (5 if p["source"] == "prose" else 0);
    }
    people.sort(key=lambda (p: dict[str, any]) -> int { -p["rank"] });
    return people;
}

impl _norm_url(url: str) -> str {
    p = urlparse(url);
    return p.netloc.lower().removeprefix("www.")
        + (p.path.rstrip("/") or "/")
        + (("?" + p.query) if p.query else "");
}

impl _link_score(segments: list[any], label: str) -> int {
    score = 0;
    for (weight, pattern) in _LINK_WEIGHTS {
        whole = f"^(?:our-|the-|meet-(?:the-|our-)?|about-|notre-|nos-|l-|la-)?(?:{pattern})(?:-(?:us|team|page|bios?|staff|de-nous|nous))?$";
        if [seg for seg in segments if re.search(whole, seg)]
            or (segments and re.match("^meet-", segments[-1]) and weight == 3)
            or re.search(f"(?:^|[^a-z])(?:{pattern})(?:$|[^a-z])", label)
        {
            score = max(score, weight);
        }
    }
    return score;
}

impl menu_links(html: str, page_url: str, limit: int = 5) -> list[str] {
    host = urlparse(page_url).netloc.lower().removeprefix("www.");
    seen = {_norm_url(page_url)};
    scored: list[any] = [];
    anchor = "(?is)<a\\b[^>]*?href\\s*=\\s*[\"\\']([^\"\\'#][^\"\\']*)[\"\\'][^>]*>(.*?)</a>";
    for (i, m) in enumerate(re.finditer(anchor, _strip_code(html or ""))) {
        href = html_lib.unescape(m.group(1)).strip();
        if href.lower().startswith(("mailto:", "tel:", "javascript:", "sms:")) {
            continue;
        }
        url = urljoin(page_url, href).split("#")[0];
        (p, key) = (urlparse(url), _norm_url(url));
        if p.scheme not in ("http", "https")
            or p.netloc.lower().removeprefix("www.") != host
            or re.search(_SKIP_LINK, url)
            or key in seen
            or p.path.rstrip("/") in ("", "/index.html", "/index.php", "/home")
        {
            continue;
        }
        text = html_lib.unescape(re.sub("(?s)<[^>]+>", " ", m.group(2)));
        text = fold_accents(nfc(re.sub("\\s+", " ", text).strip().lower()));
        path = fold_accents(nfc(unquote(p.path))).lower();
        segments = [re.sub("\\.(?:html?|php|aspx?)$", "", seg) for seg in path.split("/") if seg];
        score = _link_score(segments, text if len(text.split()) <= 4 else "");
        if score {
            seen.add(key);
            scored.append((-score, len(p.path), i, url));
        }
    }
    scored.sort();
    return [s[3] for s in scored[:limit]];
}

impl _cf_decode(hexstr: str) -> str {
    try {
        key = int(hexstr[:2], 16);
        return "".join(chr(int(hexstr[i:i + 2], 16) ^ key) for i in range(2, len(hexstr) - 1, 2));
    } except ValueError {
        return "";
    }
}

impl _clean_address(addr: str) -> str {
    addr = unquote(html_lib.unescape(addr or "")).strip().strip(".,;:<>()[]'\"").lower();
    addr = addr.removeprefix("mailto:").split("?")[0].strip();
    domain = addr.rpartition("@")[2];
    junk = domain in _JUNK_DOMAINS or domain.endswith(_JUNK_TLDS) or re.search("@\\d+x\\.", addr);
    return addr if EMAIL_RE.fullmatch(addr) and not junk else "";
}

impl _data_pair(raw_tag: str) -> str {
    mailish = re.match("(?i)<a\\b", raw_tag)
        or re.search("(?i)\\b(?:class|id|title|aria-label)\\s*=\\s*[\"'][^\"']*mail", raw_tag);
    pairs = re.findall("(?i)\\b(data-[a-z\\-]+)\\s*=\\s*[\"\\']([^\"\\']*)[\"\\']", raw_tag)
        if mailish
        else [];
    attrs = {k.lower(): v for (k, v) in pairs};
    local = next((attrs[k] for k in _DATA_PAIR_LOCAL if k in attrs), "");
    domain = next((attrs[k] for k in _DATA_PAIR_DOMAIN if k in attrs), "");
    ok = re.fullmatch("[a-z0-9._%+\\-]+", local, re.I)
        and re.fullmatch("[a-z0-9\\-]+(?:\\.[a-z0-9\\-]+)+", domain, re.I);
    return f"{local}@{domain}" if local and domain and ok else "";
}

impl emails_on_page(html: str) -> list[str] {
    html = (html or "")[:MAX_PAGE_CHARS];
    cands = re.findall("(?i)href\\s*=\\s*[\"\\']\\s*mailto:([^\"\\'>]+)[\"\\']", html);
    for raw in re.findall(_LD_JSON, html) {
        cands += re.findall("\"email\"\\s*:\\s*\"([^\"]+)\"", raw);
    }
    cfemail = re.findall("(?i)data-cfemail\\s*=\\s*[\"\\']([0-9a-f]{4,})[\"\\']", html);
    cdn = re.findall("(?i)/cdn-cgi/l/email-protection#([0-9a-f]{4,})", html);
    tags = re.findall("(?is)<[a-z][^>]*\\bdata-[a-z\\-]+\\s*=[^>]*>", html);
    cands += [_cf_decode(h) for h in cfemail + cdn] + [_data_pair(tag) for tag in tags];
    text = unquote(html_lib.unescape(_strip_code(html)));
    cands += [m.group(0) for m in EMAIL_RE.finditer(text)];
    dots = "\\s*(?:\\[\\s*dot\\s*\\]|\\(\\s*dot\\s*\\)|\\{\\s*dot\\s*\\})\\s*";
    for (local, dotted) in re.findall(_AT_DOT, re.sub("(?s)<[^>]+>", " ", text)) {
        domain = re.sub(dots, ".", dotted, flags=re.I).replace(" ", "").lower();
        if domain.rpartition(".")[2] in _KNOWN_TLDS {
            cands.append(f"{local}@{domain}");
        }
    }
    return list(dict.fromkeys(a for a in map(_clean_address, cands) if a));
}
