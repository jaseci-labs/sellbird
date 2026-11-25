import re;
import unicodedata;
import from dataclasses { dataclass, field }
import from urllib.parse { urlsplit, unquote }

glob BANNED_PHRASES = tuple(
         ("act now|buy now|click here|click below|limited time|limited offer|exclusive deal|special offer|"
             "risk-free|no obligation|100% free|make money|double your|guaranteed results|winner|congratulations|"
             "i hope this finds you well|hope this email finds you well|i hope this email finds you|picture this|"
             "what if i told you|in today's fast-paced world|game-changer|game changer|cutting-edge solution|"
             "revolutionize your|unlock your|supercharge your|as an ai|i'm an ai|i am an ai|"
             "as a language model").split("|"),
     ),
     MAX_SUBJECT_LEN = 90,
     MAX_BODY_WORDS = 220,
     MAX_LINKS = 1,
     EMAIL_RE = re.compile("^[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}$"),
     MERGE_TAG_RE = re.compile("\\{\\{\\s*\\w+\\s*\\}\\}|\\{\\s*\\w+\\s*\\}(?!\\})"),
     URL_RE = re.compile("(?i)https?://\\S+"),
     DELIVERABLE_STATUSES = {"verified", "risky"},
     _INVISIBLE_RE = re.compile("[\\u00ad\\u200b-\\u200d\\u2060\\ufeff]"),
     _DNC_DOMAIN_RE = re.compile("^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z0-9-]{2,63}$"),
     _DNC_LOCAL_RE = re.compile("^[a-z0-9._%+'-]+$");

glob _FILE_ENDINGS = frozenset(
         ("js ts pdf png jpg jpeg gif svg webp heic txt csv doc docx xls xlsx ppt pptx key pages "
             "json yaml yml toml xml html htm css exe dmg msi bat ini cfg mp3 mp4 wav").split(),
     ),
     _KNOWN_ENDINGS = frozenset(
         ("com net org info biz name pro mobi asia tel xxx io ai app dev xyz site online store shop tech cloud "
             "page agency studio digital email live life media news blog club world today one link click top icu buzz "
             "win bid loan work fun space website host press services solutions company business center group network "
             "systems software tools zone works sale deals plus vip best ltd inc llc gmbh zip mov cfd sbs cyou rest "
             "bar beauty hair skin love sexy porn casino bet poker game games bio eco green energy solar money cash "
             "pay finance capital fund trade market markets exchange loans credit insurance legal law health care "
             "clinic dental doctor coach academy school university courses training jobs careers events tickets "
             "travel tours hotel homes house realty estate properties land gov edu mil int test example invalid "
             "localhost onion").split(),
     ),
     _ENDINGS_RE = "|".join(sorted(_KNOWN_ENDINGS, key=len, reverse=True)),
     _ZERO_WIDTH_RE = re.compile("[\\u200b-\\u200f\\u2060\\ufeff]"),
     _DOT_FORMS_RE = re.compile("(?i)\\s*[\\[({]\\s*(?:\\.|dot)\\s*[\\])}]\\s*"),
     _SPOKEN_DOT_RE = re.compile(f"(?i)(?<=\\w\\w)\\s+dot\\s+(?=(?:{_ENDINGS_RE}|[a-z]{{2}})\\b)"),
     _SPACED_DOT_RE = re.compile(
         f"(?i)(?<=\\w)\\s+\\.\\s*(?=(?:{_ENDINGS_RE})\\b|[^\\W\\d_]{{2,24}}/)"
     ),
     _SCHEME_URL_RE = re.compile("(?i)\\b[a-z][a-z0-9+.-]*://[^\\s<>\\\"']+"),
     _EMAIL_HOST_RE = re.compile(
         "(?:[\\w.%+\\-]+|\\\"[^\\\"\\n]*\\\"|“[^”\\n]*”)?@((?:[^\\W_][\\w-]*\\.)+[^\\W\\d_]{2,})"
     ),
     _HOST_OK_RE = re.compile("^[^\\W_](?:[\\w.-]*[^\\W_])?$"),
     UNREADABLE_LINK = "link that can't be read",
     _IP_RE = re.compile("(?<![\\w.])\\d{1,3}(?:\\.\\d{1,3}){3}(?![\\w.])"),
     _BARE_RE = re.compile(
         "(?<![\\w@.])((?:[^\\W_](?:[\\w-]{0,61}[^\\W_])?\\.)+([^\\W\\d_]{2,24}))(?![\\w-])([/?#][^\\s<>\\\"']*)?",
     );

glob _SAY_ALOUD_FILES = frozenset(
         "email_frameworks.md product_knowledge.md objection_handling.md README.md".split()
     ),
     LEAK_RUN_WORDS = 12,
     _WORD_RE = re.compile("[a-z0-9']+"),
     _SCRIPT_LINE_RE = re.compile("^\\s*(?:[-*]\\s*)?(?:>|[\\\"“'‘])"),
     _QUOTED_RE = re.compile("\"[^\"\\n]{12,}\"|“[^”\\n]{12,}”"),
     _leak_cache: dict[str, any] = {},
     _PHONE_RE = re.compile(
         "(?<![\\w+#$€£])(?:\\+|00)?\\(?\\d[\\d \\t().\\-\\u2010-\\u2015/]{5,22}\\d(?![\\w])"
     ),
     _ISO_DATE_RE = re.compile("^\\d{4}-\\d{2}-\\d{2}$"),
     _PAYMENT_RE = re.compile(
         "(?i)\\b(?:wire\\s+transfer|bank\\s+(?:account|details|transfer|wire)|routing\\s+number|"
             "account\\s+number|sort\\s+code|iban|swift\\s+code|bitcoin|btc\\s+address|ethereum|"
             "usdt|crypto(?:currency)?\\s+(?:wallet|address|payment)|wallet\\s+address|"
             "gift\\s+cards?|western\\s+union|moneygram|zelle|venmo|cash\\s*app|paypal\\.me)\\b",
     );

@dataclass
class GateResult {
    has ok: bool,
        reasons: list[str] = field(default_factory=list[any]);

    def __bool__ -> bool {
        return self.ok;
    }
}

def _clean_text(raw: any) -> str {
    text = unicodedata.normalize("NFKC", str(raw or ""));
    return _INVISIBLE_RE.sub("", text).replace("\u3002", ".");
}

def _dnc_domain(value: str) -> str {
    domain = value.split(":", 1)[0].strip().strip(".");
    domain = domain[4:] if domain.startswith("www.") else domain;
    try {
        domain = domain.encode("idna").decode("ascii");
    } except UnicodeError {
        return "";
    }
    return domain if _DNC_DOMAIN_RE.match(domain) else "";
}

def do_not_contact_entry(raw: any) -> str {
    e = re.sub("^(?:[a-z][a-z0-9+.-]*://|mailto:)", "", _clean_text(raw).strip().lower());
    e = re.sub("^(?:\\*@|\\*\\.|@)", "", re.split("[/?#]", e, maxsplit=1)[0]);
    if "@" not in e {
        return _dnc_domain(e);
    }
    (local, _, domain) = e.rpartition("@");
    domain = _dnc_domain(domain);
    return f"{local}@{domain}" if domain and _DNC_LOCAL_RE.match(local) else "";
}

def do_not_contact_entries(raw: any) -> list[str] {
    text = _clean_text(raw);
    parts: list[any] = re.findall("<([^<>\\s]+@[^<>\\s]+)>", text) or re.split("[\\s,;]+", text);
    parts = [p for p in parts if p.strip()];
    bad = [p for p in parts if not do_not_contact_entry(p)];
    if bad {
        raise ValueError(f"'{bad[0].strip()}' is not an email address or a domain");
    }
    return [do_not_contact_entry(p) for p in parts];
}

def _covers(host: str, domains: any) -> bool {
    return any(host == d or host.endswith("." + d) for d in domains);
}

def _is_our_number(number: str, ours: set[str]) -> bool {
    d = _digits(number);
    return any(d == o or (len(d) >= 7 and (o.endswith(d) or d.endswith(o))) for o in ours);
}

def _dnc_find(local: str | None, host: str, entries: any) -> str {
    for e in (do_not_contact_entry(raw) for raw in entries or ()) {
        (e_local, at, e_host) = e.rpartition("@");
        mine = local is not None and e_host == host and e_local in (local, local.split("+")[0]);
        if e and (mine if at else _covers(host, (e,))) {
            return e;
        }
    }
    return "";
}

def do_not_contact_match(to_email: str, entries: any) -> str {
    (local, at, host) = (to_email or "").strip().lower().rpartition("@");
    return _dnc_find(local, _host(host), entries) if at else "";
}

def do_not_contact_domain_match(domain: str, entries: any) -> str {
    host = _host(domain or "");
    return _dnc_find(None, host, entries) if host and "@" not in host else "";
}

def pre_send_check(
    to_email: str,
    subject: str,
    body: str,
    prospect: any = None,
    allow_risky: bool = False,
    kind: str = "sequence",
    postal_address: str = "",
    do_not_contact: any = (),
) -> GateResult {
    subject = (subject or "").strip();
    body = (body or "").strip();
    to_email = (to_email or "").strip().lower();
    blocked = do_not_contact_match(to_email, do_not_contact);
    seq = kind == "sequence";
    status = (prospect.email_status or "guess") if prospect is not None and seq else "verified";
    undeliverable = status not in (DELIVERABLE_STATUSES if allow_risky else {"verified"});
    mismatch = prospect is not None and (prospect.email or "").strip().lower() != to_email;
    (word_count, links) = (len(body.split()), len(URL_RE.findall(body)));
    postal = postal_address.strip();
    leftover = MERGE_TAG_RE.findall(subject + " " + body);
    hits = [p for p in BANNED_PHRASES if p in (subject + " " + body).lower()];
    html = re.search("(?i)<\\s*(html|body|div|table|img|a)\\b", body);
    checks = [
        (not EMAIL_RE.match(to_email), f"invalid recipient address '{to_email}'"),
        (blocked, f"'{blocked}' is on the do-not-contact list"),
        (mismatch, "recipient does not match the prospect record"),
        (undeliverable, f"email_status '{status}' is not deliverable"),
        (not subject, "empty subject"),
        (not body, "empty body"),
        (len(subject) > MAX_SUBJECT_LEN, f"subject too long ({len(subject)} > {MAX_SUBJECT_LEN})"),
        (word_count > MAX_BODY_WORDS, f"body too long ({word_count} words > {MAX_BODY_WORDS})"),
        (leftover, f"unrendered merge tags: {sorted(set(leftover))[:3]}"),
        (hits, f"banned phrases: {hits[:3]}"),
        (links > MAX_LINKS, f"too many links ({links} > {MAX_LINKS})"),
        (seq and postal and postal not in body, "postal address footer missing"),
        (html, "HTML markup in body (plain text only)"),
    ];
    reasons = [msg for (bad, msg) in checks if bad];
    return GateResult(ok=not reasons, reasons=reasons);
}

def _normalize(text: str) -> str {
    text = _ZERO_WIDTH_RE.sub("", unicodedata.normalize("NFKC", text or ""));
    text = _DOT_FORMS_RE.sub(".", text.replace("\u3002", ".").replace("\uff61", "."));
    return _SPOKEN_DOT_RE.sub(".", _SPACED_DOT_RE.sub(".", text));
}

def _host(value: str) -> str {
    h = (value or "").strip().strip(".").lower();
    return h[4:] if h.startswith("www.") else h;
}

def find_links(text: str) -> list[tuple[str, str]] {
    text = _normalize(text);
    found: list[tuple[str, str]] = [];
    for m in _SCHEME_URL_RE.finditer(text) {
        try {
            parts = urlsplit(m.group(0).replace("\\", "/"));
            (host, path) = (_host(parts.hostname or ""), str(parts.path));
        } except ValueError {
            (host, path) = ("", "");
        }
        (host, path) = (host, path) if _HOST_OK_RE.match(host) else (UNREADABLE_LINK, "");
        found.append((host, host + path));
    }
    rest = _SCHEME_URL_RE.sub(" ", text);
    found += [(_host(m.group(1)), _host(m.group(1))) for m in _EMAIL_HOST_RE.finditer(rest)];
    rest = _EMAIL_HOST_RE.sub(" ", rest);
    found += [(m.group(0), m.group(0)) for m in _IP_RE.finditer(rest)];
    for m in _BARE_RE.finditer(rest) {
        ending = m.group(2).lower();
        if m.group(3)
            or m.group(1).lower().startswith("www.")
            or ending not in _FILE_ENDINGS and (len(ending) == 2 or ending in _KNOWN_ENDINGS)
        {
            host = _host(m.group(1));
            found.append((host, host + (m.group(3) or "").split("?")[0].split("#")[0]));
        }
    }
    return list(dict.fromkeys(f for f in found if f[0]));
}

def find_link_domains(text: str) -> list[str] {
    return list(dict.fromkeys(host for (host, _) in find_links(text)));
}

def _booking_prefix(config: any) -> str {
    offer = getattr(getattr(config, "product", None), "offer", None);
    links = find_links(str(getattr(offer, "booking_url", "") or ""));
    return links[0][1].rstrip("/") if links else "";
}

def allowed_link_domains(config: any) -> set[str] {
    address = str(getattr(getattr(config, "persona", None), "email", "") or "");
    email_cfg = getattr(getattr(config, "channels", None), "email", None);
    out: set[str] = {_host(address.rsplit("@", 1)[1])} if "@" in address else set[str]();
    for e in getattr(email_cfg, "link_domains", None) or [] {
        out.update(find_link_domains(str(e)) or [_host(str(e))]);
    }
    return {d for d in out if d};
}

def _is_booking_page(link: str, prefix: str) -> bool {
    link = unquote(unquote(link));
    return bool(prefix)
        and not any(seg in ("..", ".") for seg in link.split("/")[1:])
        and (link.rstrip("/") == prefix or link.startswith(prefix + "/"));
}

def _words(text: str) -> list[str] {
    return _WORD_RE.findall((text or "").lower());
}

def _instruction_runs(base: any) -> dict[any, str] {
    files = [p for d in ("prompts", "skills") for p in (base / d).glob("*.md")];
    files = sorted(p for p in files if p.name not in _SAY_ALOUD_FILES);
    key = (str(base), tuple((str(p), p.stat().st_mtime_ns) for p in files));
    if _leak_cache.get("key") != key {
        runs: dict[any, str] = {};
        sources: list[tuple[str, str]] = [];
        for p in files {
            lines = p.read_text(encoding="utf-8", errors="replace").splitlines();
            text = "\n".join(l for l in lines if not _SCRIPT_LINE_RE.match(l));
            sources.append((p.name, _QUOTED_RE.sub(" | ", text)));
        }
        sources.append(("Sellbird's prompt rules", UNTRUSTED_RULE));
        for (name, text) in sources {
            ws = _words(text);
            for i in range(len(ws) - LEAK_RUN_WORDS + 1) {
                runs.setdefault(tuple(ws[i:i + LEAK_RUN_WORDS]), name);
            }
        }
        _leak_cache.update(key=key, runs=runs);
    }
    return _leak_cache["runs"];
}

def _digits(value: str) -> str {
    digits = re.sub("\\D", "", value or "");
    return digits[2:] if digits.startswith("00") else digits;
}

def find_phone_numbers(text: str) -> list[str] {
    found: list[str] = [];
    for m in _PHONE_RE.finditer(_normalize(text)) {
        (raw, n) = (m.group(0).strip(), len(_digits(m.group(0).strip())));
        if not _ISO_DATE_RE.match(raw) and n >= 7 and n <= 15 and not (raw.isdigit() and n < 10) {
            found.append(raw);
        }
    }
    return found;
}

def own_phone_numbers(config: any) -> set[str] {
    email_cfg = getattr(getattr(config, "channels", None), "email", None);
    postal = str(getattr(getattr(config, "compliance", None), "postal_address", "") or "");
    out = {_digits(str(n)) for n in (getattr(email_cfg, "phone_numbers", None) or [])};
    out.update(_digits(n) for n in find_phone_numbers(postal));
    return {d for d in out if len(d) >= 7};
}

def autopilot_review(
    subject: str, body: str, config: any, `root: any = None, recipient: str = ""
) -> list[str] {
    text = (subject or "") + "\n" + (body or "");
    allowed = allowed_link_domains(config);
    if "@" in (recipient or "") {
        allowed.add(_host(recipient.rsplit("@", 1)[1]));
    }
    prefix = _booking_prefix(config);
    shared = prefix.split("/", 1)[0];
    foreign: list[str] = [];
    for (host, link) in find_links(text) {
        if not _covers(host, allowed) and not _is_booking_page(link, prefix) {
            foreign.append("/".join(link.split("/")[:2]) if prefix and host == shared else host);
        }
    }
    foreign = list(dict.fromkeys(foreign));
    ours = own_phone_numbers(config);
    numbers = [n for n in find_phone_numbers(text) if not _is_our_number(n, ours)];
    numbers = list(dict.fromkeys(numbers));
    payment = _PAYMENT_RE.search(_normalize(text));
    (ws, k) = (_words(text), LEAK_RUN_WORDS);
    runs = _instruction_runs(`root or PROJECT_ROOT);
    found = [runs.get(tuple(ws[i:i + k]), "") for i in range(len(ws) - k + 1)];
    source = next((s for s in found if s), "");
    checks = [
        (
            foreign,
            f"links to {', '.join(foreign[:3])}, not one of your domains (add it to channels.email.link_domains if it's yours)",
        ),
        (
            numbers,
            f"gives the phone number {', '.join(numbers[:3])}, not one of yours (add it to channels.email.phone_numbers if it's yours)",
        ),
        (payment, f"asks about sending money (\"{payment.group(0) if payment else ''}\")"),
        (source, f"quotes Sellbird's instructions ({source})"),
    ];
    return [msg for (bad, msg) in checks if bad];
}
