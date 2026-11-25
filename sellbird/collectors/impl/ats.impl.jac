impl Posting.summary -> builtins.str {
    parts: any = [self.title, self.department, self.location];
    if self.posted {
        parts.append(f"posted {self.posted}");
    }
    return " · ".join(p for p in parts if p)[:200];
}

impl _alnum(text: builtins.str) -> builtins.str {
    return re.sub("[^a-z0-9]", "", text.lower());
}

impl detect_board(html: builtins.str, domain: builtins.str = "") -> Board | None {
    found: Counter;
    first: builtins.dict[Board, builtins.int];
    name: any;
    if not html {
        return None;
    }
    found = Counter();
    first = {};
    for (ats, pattern) in _BOARD_RES {
        for m in pattern.finditer(html) {
            token: any = unquote(m.group(1)).strip(".").strip();
            if not token or token.lower() in _NOT_TOKENS or _ASSET.search(token) {
                continue;
            }
            board: any = Board(ats, token);
            found[board] += 1;
            first.setdefault(board, m.start());
        }
    }
    if not found {
        return None;
    }
    name = _alnum((domain or "").split(".")[0] if domain else "");

    def named_like_them(board: Board) -> builtins.bool {
        token: any = _alnum(board.token);
        return operator.ge(len(name), 3)
            and operator.ge(len(token), 3)
            and (name in token or token in name);
    }

    best: any = max(found, key=lambda (b) -> any { (named_like_them(b), found[b], -first[b]) });
    if not named_like_them(best) and len(found) >= MANY_BOARDS {
        return None;
    }
    return best;
}

impl feed_url(board: Board) -> builtins.str {
    t: any = quote(board.token, safe="");
    return {
        "greenhouse": f"https://boards-api.greenhouse.io/v1/boards/{t}/departments",
        "lever": f"https://api.lever.co/v0/postings/{t}?mode=json",
        "lever_eu": f"https://api.eu.lever.co/v0/postings/{t}?mode=json",
        "ashby": f"https://api.ashbyhq.com/posting-api/job-board/{t}",
        "workable": f"https://apply.workable.com/api/v1/widget/accounts/{t}",
    }[board.ats];
}

impl _s(value) -> builtins.str {
    return re.sub("\\s+", " ", value).strip() if isinstance(value, `str) else "";
}

impl _day(value) -> builtins.str {
    if isinstance(value, (`int, `float)) and not isinstance(value, `bool) and value > 0 {
        try {
            return datetime.fromtimestamp(value / 1000, tz=timezone.utc).date().isoformat();
        } except (OverflowError, OSError, ValueError) {
            return "";
        }
    }
    text: any = _s(value);
    return text[:10] if re.match("\\d{4}-\\d{2}-\\d{2}", text) else "";
}

impl _greenhouse(payload) -> builtins.list[Posting] {
    out: any;
    seen: any;
    (out, seen) = ([], set[any]());
    departments: any = payload.get("departments") if isinstance(payload, `dict) else None;
    for dept in departments if isinstance(departments, `list) else [] {
        if not isinstance(dept, `dict) or not isinstance(dept.get("jobs"), `list) {
            continue;
        }
        name: any = _s(dept.get("name"));
        if name.lower() == "no department" {
            name = "";
        }
        for job in dept["jobs"] {
            if not isinstance(job, `dict) or not _s(job.get("title")) {
                continue;
            }
            key: any = job.get("id") or job.get("absolute_url") or job.get("title");
            if key in seen {
                continue;
            }
            seen.add(key);
            loc: any = job.get("location");
            out.append(
                Posting(
                    title=_s(job["title"]),
                    department=name,
                    location=_s(loc.get("name")) if isinstance(loc, `dict) else "",
                    posted=_day(job.get("first_published")) or _day(job.get("updated_at")),
                    url=_s(job.get("absolute_url")),
                ),
            );
        }
    }
    return out;
}

impl _lever(payload) -> builtins.list[Posting] {
    out: any = [];
    for job in payload if isinstance(payload, `list) else [] {
        if not isinstance(job, `dict) or not _s(job.get("text")) {
            continue;
        }
        cats: any = job.get("categories") if isinstance(job.get("categories"), `dict) else {};
        out.append(
            Posting(
                title=_s(job["text"]),
                department=_s(cats.get("department")) or _s(cats.get("team")),
                location=_s(cats.get("location")),
                posted=_day(job.get("createdAt")),
                url=_s(job.get("hostedUrl")),
            ),
        );
    }
    return out;
}

impl _ashby(payload) -> builtins.list[Posting] {
    out: any = [];
    jobs: any = payload.get("jobs") if isinstance(payload, `dict) else None;
    for job in jobs if isinstance(jobs, `list) else [] {
        if not isinstance(job, `dict) or not _s(job.get("title")) or job.get("isListed") is False {
            continue;
        }
        out.append(
            Posting(
                title=_s(job["title"]),
                department=_s(job.get("department")),
                location=_s(job.get("location")),
                posted=_day(job.get("publishedAt")),
                url=_s(job.get("jobUrl")),
            ),
        );
    }
    return out;
}

impl _workable(payload) -> builtins.list[Posting] {
    job: any;
    out: any = [];
    jobs: any = payload.get("jobs") if isinstance(payload, `dict) else None;
    for job_ in jobs if isinstance(jobs, `list) else [] {
        job = job_;
        if not isinstance(job, `dict) or not _s(job.get("title")) {
            continue;
        }
        place: any = ", ".join(
            p for p in (_s(job.get(k)) for k in ("city", "state", "country")) if p
        );
        if not place and job.get("telecommuting") {
            place = "Remote";
        }
        out.append(
            Posting(
                title=_s(job["title"]),
                department=_s(job.get("department")),
                location=place,
                posted=_day(job.get("published_on")) or _day(job.get("created_at")),
                url=_s(job.get("url")) or _s(job.get("shortlink")),
            ),
        );
    }
    return out;
}

impl parse_feed(ats: builtins.str, payload) -> builtins.list[Posting] {
    parser: any = _PARSERS.get(ats);
    return parser(payload) if parser else [];
}

impl read_board(client: httpx.AsyncClient, board: Board) -> builtins.list[Posting] | None {
    url: any = feed_url(board);
    body: any = bytearray();
    try {
        resp: any;
        async with client.stream("GET", url, headers={"Accept": "application/json"}) as resp {
            if resp.status_code != 200 or "json" not in resp.headers.get("content-type", "") {
                logger.debug(f"ats: {url} → {resp.status_code}");
                return None;
            }
            if `int(resp.headers.get("content-length") or 0) > MAX_FEED_BYTES {
                logger.info(f"ats: {board.label} board {board.token} too large, skipped");
                return None;
            }
            async for chunk in resp.aiter_bytes() {
                body += chunk;
                if len(body) > MAX_FEED_BYTES {
                    logger.info(f"ats: {board.label} board {board.token} too large, skipped");
                    return None;
                }
            }
        }
    } except (httpx.HTTPError, ValueError) as e {
        logger.debug(f"ats: fetch failed {url}: {e}");
        return None;
    }
    try {
        return parse_feed(board.ats, json.loads(`bytes(body)));
    } except (ValueError, RecursionError) {
        return None;
    }
}

impl _words(text: builtins.str) -> builtins.set[builtins.str] {
    for (pattern, replacement) in _EQUIVALENT {
        text = pattern.sub(replacement, text);
    }
    return `set(re.findall("[a-z0-9+#]+", text.lower()));
}

impl role_keywords(icp) -> builtins.list[builtins.str] {
    if icp is None {
        return [];
    }
    keywords: any = [
        k.strip().lower()
        for k in getattr(icp, "hiring_signals", None) or []
        if isinstance(k, `str) and k.strip()
    ];
    if keywords {
        return keywords;
    }
    return [
        t.strip().lower()
        for t in getattr(icp, "titles", None) or []
        if isinstance(t, `str) and t.strip()
    ];
}

impl matching_roles(
    postings: builtins.list[Posting], keywords: builtins.list[builtins.str]
) -> builtins.list[Posting] {
    wanted: any = [w for w in (_words(k) - _FILLER_WORDS for k in keywords) if w];
    found: builtins.list[Posting] = [];
    for p in postings {
        have: any = _words(_REPORTS_TO.sub("", p.title));
        if `any(operator.le(w, have) for w in wanted) {
            found.append(p);
        }
    }
    return found;
}
