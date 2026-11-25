impl GateResult.__bool__ -> bool {
    return self.ok;
}

impl _clean_text(raw) -> builtins.str {
    text: any = unicodedata.normalize("NFKC", `str(raw or ""));
    return _INVISIBLE_RE.sub("", text).replace("。", ".");
}

impl _dnc_domain(value: builtins.str) -> builtins.str {
    domain: any = value.split(":", 1)[0].strip().strip(".");
    if domain.startswith("www.") {
        domain = domain[4:];
    }
    try {
        domain = domain.encode("idna").decode("ascii");
    } except UnicodeError {
        return "";
    }
    return domain if _DNC_DOMAIN_RE.match(domain) else "";
}

impl do_not_contact_entry(raw) -> builtins.str {
    `entry: any = _clean_text(raw).strip().lower();
    `entry = re.sub("^(?:[a-z][a-z0-9+.-]*://|mailto:)", "", `entry);
    `entry = re.split("[/?#]", `entry, maxsplit=1)[0];
    `entry = re.sub("^(?:\\*@|\\*\\.|@)", "", `entry);
    if "@" in `entry {
        local: any;
        _: any;
        domain: any;
        (local, _, domain) = `entry.rpartition("@") as any;
        domain = _dnc_domain(domain);
        if not domain or not _DNC_LOCAL_RE.match(local) {
            return "";
        }
        return f"{local}@{domain}";
    }
    return _dnc_domain(`entry);
}

impl do_not_contact_entries(raw) -> builtins.list[builtins.str] {
    text: any = _clean_text(raw);
    parts: any = re.findall("<([^<>\\s]+@[^<>\\s]+)>", text) or re.split("[\\s,;]+", text);
    found: any = [];
    for part in parts {
        if not part.strip() {
            continue;
        }
        `entry: any = do_not_contact_entry(part);
        if not `entry {
            raise ValueError(f"'{part.strip()}' is not an email address or a domain");
        }
        found.append(`entry);
    }
    return found;
}

impl do_not_contact_match(to_email: builtins.str, entries) -> builtins.str {
    address: any = (to_email or "").strip().lower();
    if "@" not in address or not entries {
        return "";
    }
    local: any;
    _: any;
    host: any;
    (local, _, host) = address.rpartition("@") as any;
    host = _host(host);
    base_local: any = local.split("+", 1)[0];
    for raw in entries {
        `entry: any = do_not_contact_entry(raw);
        if not `entry {
            continue;
        }
        if "@" in `entry {
            e_local: any;
            e_host: any;
            (e_local, _, e_host) = `entry.rpartition("@") as any;
            if e_host == host and e_local in (local, base_local) {
                return `entry;
            }
        } elif host == `entry or host.endswith("." + `entry) {
            return `entry;
        }
    }
    return "";
}

impl do_not_contact_domain_match(domain: builtins.str, entries) -> builtins.str {
    host: any = _host(domain or "");
    if not host or "@" in host or not entries {
        return "";
    }
    for raw in entries {
        `entry: any = do_not_contact_entry(raw);
        if not `entry or "@" in `entry {
            continue;
        }
        if host == `entry or host.endswith("." + `entry) {
            return `entry;
        }
    }
    return "";
}

impl pre_send_check(
    to_email: builtins.str,
    subject: builtins.str,
    body: builtins.str,
    prospect=None,
    allow_risky: builtins.bool = False,
    kind: builtins.str = "sequence",
    postal_address: builtins.str = "",
    do_not_contact=(),
) -> GateResult {
    reasons: builtins.list[builtins.str] = [];
    subject = (subject or "").strip();
    body = (body or "").strip();
    to_email = (to_email or "").strip().lower();
    if not EMAIL_RE.match(to_email) {
        reasons.append(f"invalid recipient address '{to_email}'");
    }
    blocked: any = do_not_contact_match(to_email, do_not_contact);
    if blocked {
        reasons.append(f"'{blocked}' is on the do-not-contact list");
    }
    if prospect is not None {
        if (prospect.email or "").strip().lower() != to_email {
            reasons.append("recipient does not match the prospect record");
        }
        allowed: any = DELIVERABLE_STATUSES if allow_risky else {"verified"};
        if kind == "sequence" and (prospect.email_status or "guess") not in allowed {
            reasons.append(
                "email_status '"
                    + format(prospect.email_status or "guess", "")
                    + "' is not deliverable",
            );
        }
    }
    if not subject {
        reasons.append("empty subject");
    }
    if not body {
        reasons.append("empty body");
    }
    if len(subject) > MAX_SUBJECT_LEN {
        reasons.append(f"subject too long ({len(subject)} > {MAX_SUBJECT_LEN})");
    }
    word_count: any = len(body.split());
    if word_count > MAX_BODY_WORDS {
        reasons.append(f"body too long ({word_count} words > {MAX_BODY_WORDS})");
    }
    leftover: any = MERGE_TAG_RE.findall(subject + " " + body);
    if leftover {
        reasons.append(f"unrendered merge tags: {sorted(`set(leftover))[:3]}");
    }
    lowered: any = (subject + " " + body).lower();
    hits: any = [p for p in BANNED_PHRASES if p in lowered];
    if hits {
        reasons.append(f"banned phrases: {hits[:3]}");
    }
    links: any = URL_RE.findall(body);
    if len(links) > MAX_LINKS {
        reasons.append(f"too many links ({len(links)} > {MAX_LINKS})");
    }

    if kind == "sequence" and postal_address.strip() and postal_address.strip() not in body {
        reasons.append("postal address footer missing");
    }
    if re.search("<\\s*(html|body|div|table|img|a)\\b", body, re.IGNORECASE) {
        reasons.append("HTML markup in body (plain text only)");
    }

    return GateResult(ok=not reasons, reasons=reasons);
}

impl _normalize(text: builtins.str) -> builtins.str {
    import unicodedata;
    text = unicodedata.normalize("NFKC", text or "");
    text = _ZERO_WIDTH_RE.sub("", text).replace("。", ".").replace("｡", ".");
    text = _DOT_FORMS_RE.sub(".", text);
    text = _SPACED_DOT_RE.sub(".", text);
    return _SPOKEN_DOT_RE.sub(".", text);
}

impl _host(value: builtins.str) -> builtins.str {
    h: any = (value or "").strip().strip(".").lower();
    return h[4:] if h.startswith("www.") else h;
}

impl find_links(text: builtins.str) -> builtins.list[builtins.tuple[builtins.str, builtins.str]] {
    import from urllib.parse { urlsplit }
    text = _normalize(text);
    found: builtins.list[builtins.tuple[builtins.str, builtins.str]] = [];
    m: any;
    for m in _SCHEME_URL_RE.finditer(text) {
        url: any = m.group(0).replace("\\", "/");
        try {
            parts: any = urlsplit(url);
            host: any = _host(parts.hostname or "");
            path: any = parts.path;
        } except ValueError {
            (host, path) = ("", "");
        }
        if not _HOST_OK_RE.match(host) {
            (host, path) = (UNREADABLE_LINK, "");
        }
        found.append((host, host + path));
    }
    rest: any = _SCHEME_URL_RE.sub(" ", text);
    for m in _EMAIL_HOST_RE.finditer(rest) {
        found.append((_host(m.group(1)), _host(m.group(1))));
    }
    rest = _EMAIL_HOST_RE.sub(" ", rest);
    for m in _IP_RE.finditer(rest) {
        found.append((m.group(0), m.group(0)));
    }
    for m in _BARE_RE.finditer(rest) {
        ending: any;
        has_path: any;
        (ending, has_path) = (m.group(2).lower(), `bool(m.group(3)));
        www: any = m.group(1).lower().startswith("www.");
        if not has_path
            and not www
            and (ending in _FILE_ENDINGS or not (len(ending) == 2 or ending in _KNOWN_ENDINGS))
        {
            continue;
        }
        host = _host(m.group(1));
        found.append((host, host + (m.group(3) or "").split("?")[0].split("#")[0]));
    }
    out: any;
    seen: any;
    (out, seen) = ([], set[any]());
    for (host, link) in found {
        if host and (host, link) not in seen {
            seen.add((host, link));
            out.append((host, link));
        }
    }
    return out;
}

impl find_link_domains(text: builtins.str) -> builtins.list[builtins.str] {
    return `list(dict.fromkeys(host for (host, _) in find_links(text)));
}

impl _booking_prefix(config) -> builtins.str {
    offer: any = getattr(getattr(config, "product", None), "offer", None);
    links: any = find_links(`str(getattr(offer, "booking_url", "") or ""));
    return links[0][1].rstrip("/") if links else "";
}

impl allowed_link_domains(config) -> builtins.set[builtins.str] {
    persona: any = getattr(config, "persona", None);
    email_cfg: any = getattr(getattr(config, "channels", None), "email", None);
    out: builtins.set[builtins.str] = set[any]();
    address: any = `str(getattr(persona, "email", "") or "");
    if "@" in address {
        out.add(_host(address.rsplit("@", 1)[1]));
    }
    for `entry in getattr(email_cfg, "link_domains", None) or [] {
        out.update(find_link_domains(`str(`entry)) or [_host(`str(`entry))]);
    }
    return {d for d in out if d};
}

impl _is_ours(host: builtins.str, allowed: builtins.set[builtins.str]) -> builtins.bool {
    return `any(operator.eq(host, d) or host.endswith("." + d) for d in allowed);
}

impl _is_booking_page(link: builtins.str, prefix: builtins.str) -> builtins.bool {
    import from urllib.parse { unquote }
    if not prefix {
        return False;
    }
    link = unquote(unquote(link));
    if `any(seg in ("..", ".") for seg in link.split("/")[1:]) {
        return False;
    }
    return operator.eq(link.rstrip("/"), prefix) or link.startswith(prefix + "/");
}

impl _shown(host: builtins.str, link: builtins.str, prefix: builtins.str) -> builtins.str {
    if prefix and host == prefix.split("/", 1)[0] {
        return "/".join(link.split("/")[:2]);
    }
    return host;
}

impl _words(text: builtins.str) -> builtins.list[builtins.str] {
    return _WORD_RE.findall((text or "").lower());
}

impl _instruction_runs(`root) -> builtins.dict[builtins.tuple, builtins.str] {
    import from sellbird.untrusted { UNTRUSTED_RULE }
    files: any = sorted(
        p
        for folder in ("prompts", "skills")
        for p in (`root / folder).glob("*.md")
        if p.name not in _SAY_ALOUD_FILES,
    );
    key: any = (`str(`root), `tuple((`str(p), p.stat().st_mtime_ns) for p in files));
    if _leak_cache.get("key") != key {
        runs: builtins.dict[builtins.tuple, builtins.str] = {};
        sources: any = [
            (
                p.name,
                _QUOTED_RE.sub(
                    " | ",
                    "\n".join(
                        line
                        for line in p.read_text(encoding="utf-8", errors="replace").splitlines()
                        if not _SCRIPT_LINE_RE.match(line),
                    ),
                ),
            )
            for p in files
        ];
        sources.append(("Sellbird's prompt rules", UNTRUSTED_RULE));
        for (name, text) in sources {
            words: any = _words(text);
            for i in range(len(words) - LEAK_RUN_WORDS + 1) {
                runs.setdefault(`tuple(words[i:i + LEAK_RUN_WORDS]), name);
            }
        }
        _leak_cache.update(key=key, runs=runs);
    }
    return _leak_cache["runs"];
}

impl _digits(value: builtins.str) -> builtins.str {
    digits: any = re.sub("\\D", "", value or "");
    return digits[2:] if digits.startswith("00") else digits;
}

impl find_phone_numbers(text: builtins.str) -> builtins.list[builtins.str] {
    text = _normalize(text);
    found: any = [];
    for m in _PHONE_RE.finditer(text) {
        raw: any = m.group(0).strip();
        digits: any = _digits(raw);
        if _ISO_DATE_RE.match(raw)
            or not 7 <= len(digits) <= 15
            or raw.isdigit() and len(digits) < 10
        {
            continue;
        }
        found.append(raw);
    }
    return found;
}

impl _is_our_number(number: builtins.str, ours: builtins.set[builtins.str]) -> builtins.bool {
    d: any;
    d = _digits(number);
    return `any(
        operator.eq(d, o) or operator.ge(len(d), 7) and (o.endswith(d) or d.endswith(o))
        for o in ours,
    );
}

impl own_phone_numbers(config) -> builtins.set[builtins.str] {
    email_cfg: any = getattr(getattr(config, "channels", None), "email", None);
    compliance: any = getattr(config, "compliance", None);
    out: any = {_digits(`str(n)) for n in getattr(email_cfg, "phone_numbers", None) or []};
    out.update(
        _digits(n)
        for n in find_phone_numbers(`str(getattr(compliance, "postal_address", "") or "")),
    );
    return {d for d in out if len(d) >= 7};
}

impl autopilot_review(
    subject: builtins.str, body: builtins.str, config, `root=None, recipient: builtins.str = ""
) -> builtins.list[builtins.str] {
    allowed: any;
    prefix: any;
    ours: any;
    import from sellbird.paths { PROJECT_ROOT }
    reasons: builtins.list[builtins.str] = [];
    text: any = format(subject or "", "") + "\n" + format(body or "", "");
    allowed = allowed_link_domains(config);
    if "@" in (recipient or "") {
        allowed.add(_host(recipient.rsplit("@", 1)[1]));
    }
    prefix = _booking_prefix(config);
    foreign: any = `list(
        dict.fromkeys(
            _shown(host, link, prefix)
            for (host, link) in find_links(text)
            if not _is_ours(host, allowed) and not _is_booking_page(link, prefix),
        ),
    );
    if foreign {
        reasons.append(
            "links to "
                + format(", ".join(foreign[:3]), "")
                + ", not one of your domains (add it to channels.email.link_domains if it's yours)",
        );
    }
    ours = own_phone_numbers(config);
    numbers: any = `list(
        dict.fromkeys(n for n in find_phone_numbers(text) if not _is_our_number(n, ours))
    );
    if numbers {
        reasons.append(
            "gives the phone number "
                + format(", ".join(numbers[:3]), "")
                + ", not one of yours (add it to channels.email.phone_numbers if it's yours)",
        );
    }
    payment: any = _PAYMENT_RE.search(_normalize(text));
    if payment {
        reasons.append(f"asks about sending money (\"{payment.group(0)}\")");
    }
    words: any = _words(text);
    runs: any = _instruction_runs(`root or PROJECT_ROOT);
    for i in range(len(words) - LEAK_RUN_WORDS + 1) {
        source: any = runs.get(`tuple(words[i:i + LEAK_RUN_WORDS]));
        if source {
            reasons.append(f"quotes Sellbird's instructions ({source})");
            break;
        }
    }
    return reasons;
}
