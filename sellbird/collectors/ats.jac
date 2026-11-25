import json;
import logging;
import re;
import from collections { Counter }
import from dataclasses { dataclass }
import from datetime { datetime, timezone }
import from urllib.parse { quote, unquote }
import httpx;

glob logger = logging.getLogger("sellbird.collectors.ats"),
     MAX_FEED_BYTES = 8 * 1024 * 1024,
     MANY_BOARDS = 3,
     _ATS_TABLE = [
         row.split()
         for row in (
             "greenhouse Greenhouse https://boards.greenhouse.io/{} https://boards-api.greenhouse.io/v1/boards/{}/departments",
             "lever Lever https://jobs.lever.co/{} https://api.lever.co/v0/postings/{}?mode=json",
             "lever_eu Lever https://jobs.eu.lever.co/{} https://api.eu.lever.co/v0/postings/{}?mode=json",
             "ashby Ashby https://jobs.ashbyhq.com/{} https://api.ashbyhq.com/posting-api/job-board/{}",
             "workable Workable https://apply.workable.com/{}/ https://apply.workable.com/api/v1/widget/accounts/{}",
         )
     ],
     ATS_LABELS = {r[0]: r[1] for r in _ATS_TABLE},
     _PAGE_URLS = {r[0]: r[2] for r in _ATS_TABLE},
     _FEED_URLS = {r[0]: r[3] for r in _ATS_TABLE},
     _FIELDS = {
         "greenhouse": "title - location.name first_published|updated_at absolute_url",
         "lever": "text categories.department|categories.team categories.location createdAt hostedUrl",
         "ashby": "title department location publishedAt jobUrl",
         "workable": "title department - published_on|created_at url|shortlink",
     },
     _TOKEN = "([A-Za-z0-9][A-Za-z0-9_.%-]*)",
     _BOARD_RES = tuple(
         (ats, re.compile(p.replace("/", "\\\\?/").replace("TOKEN", _TOKEN), re.I))
         for (ats, p) in (
             (
                 "greenhouse",
                 "(?:job-)?boards\\.greenhouse\\.io/embed/job_(?:board|app)(?:/js)?\\?(?:[^\\\"'\\s<>]*?&(?:amp;)?)?for=([A-Za-z0-9_-]+)",
             ),
             ("greenhouse", "boards-api\\.greenhouse\\.io/v1/boards/([A-Za-z0-9_-]+)"),
             ("greenhouse", "(?<![\\w.@-])(?:job-)?boards\\.greenhouse\\.io/([A-Za-z0-9_-]+)"),
             ("lever", "(?<![\\w.@-])jobs\\.lever\\.co/TOKEN"),
             ("lever", "(?<![\\w.@-])api\\.lever\\.co/v0/postings/TOKEN"),
             ("lever_eu", "(?<![\\w.@-])jobs\\.eu\\.lever\\.co/TOKEN"),
             ("lever_eu", "(?<![\\w.@-])api\\.eu\\.lever\\.co/v0/postings/TOKEN"),
             ("ashby", "(?<![\\w.@-])jobs\\.ashbyhq\\.com/TOKEN"),
             ("ashby", "api\\.ashbyhq\\.com/posting-api/job-board/TOKEN"),
             ("workable", "apply\\.workable\\.com/api/v1/widget/accounts/([A-Za-z0-9_-]+)"),
             ("workable", "(?<![\\w.@-])apply\\.workable\\.com/([A-Za-z0-9_-]+)"),
             ("workable", "(?<![\\w.@-])([a-z0-9][a-z0-9-]*)\\.workable\\.com(?![\\w-])"),
         ),
     ),
     _NOT_TOKENS = frozenset(
         ("embed api j v0 v1 jobs job job_board posting-api www apply app help resources "
             "careers static assets cdn widget accounts blog login signin").split(),
     ),
     _ASSET = re.compile("(?i)\\.(js|mjs|css|json|png|jpe?g|svg|gif|ico|webp|woff2?|map)$");

glob _FILLER_WORDS = frozenset("of the and for a an & to".split()),
     _EQUIVALENT = tuple(
         (re.compile(pair.split("=")[0], re.I), pair.split("=")[1])
         for pair in ("\\bvice[\\s-]+president\\b=vp \\bchief\\s+executive\\s+officer\\b=ceo "
             "\\bchief\\s+marketing\\s+officer\\b=cmo \\bchief\\s+technology\\s+officer\\b=cto "
             "\\bchief\\s+technical\\s+officer\\b=cto \\bchief\\s+financial\\s+officer\\b=cfo "
             "\\bchief\\s+operating\\s+officer\\b=coo \\bchief\\s+revenue\\s+officer\\b=cro "
             "\\bchief\\s+product\\s+officer\\b=cpo \\bsr\\b\\.?=senior \\bjr\\b\\.?=junior "
             "\\bfront[\\s-]+end\\b=frontend \\bback[\\s-]+end\\b=backend \\bfull[\\s-]+stack\\b=fullstack").split(),
     ),
     _REPORTS_TO = re.compile("(?i)\\s+to\\s+(?:the\\s+|our\\s+)?\\S.*$");

@dataclass(frozen=True)
class Board {
    has ats: str,
        token: str;

    has label: str {
        getter {
            return ATS_LABELS.get(self.ats, self.ats);
        }
    }

    has page_url: str {
        getter {
            return _PAGE_URLS[self.ats].format(quote(self.token, safe=""));
        }
    }
}

@dataclass
class Posting {
    has title: str,
        department: str = "",
        location: str = "",
        posted: str = "",
        url: str = "";

    def summary -> str {
        posted = f"posted {self.posted}" if self.posted else "";
        return " · ".join(
            p for p in (self.title, self.department, self.location, posted) if p
        )[:200];
    }
}

def _alnum(text: str) -> str {
    return re.sub("[^a-z0-9]", "", text.lower());
}

def _named_like(board: Board, name: str) -> bool {
    token = _alnum(board.token);
    return len(name) >= 3 and len(token) >= 3 and (name in token or token in name);
}

def detect_board(html: str, domain: str = "") -> Board | None {
    found = Counter();
    first: dict[Board, int] = {};
    for (ats, pattern) in _BOARD_RES {
        for m in pattern.finditer(html or "") {
            token = unquote(m.group(1)).strip(".").strip();
            if token and token.lower() not in _NOT_TOKENS and not _ASSET.search(token) {
                found[Board(ats, token)] += 1;
                first.setdefault(Board(ats, token), m.start());
            }
        }
    }
    if not found {
        return None;
    }
    name = _alnum((domain or "").split(".")[0]);
    best = max(found, key=lambda (b: Board) -> any { (_named_like(b, name), found[b], -first[b]) });
    return best if _named_like(best, name) or len(found) < MANY_BOARDS else None;
}

def feed_url(board: Board) -> str {
    return _FEED_URLS[board.ats].format(quote(board.token, safe=""));
}

def _s(value: any) -> str {
    return re.sub("\\s+", " ", value).strip() if isinstance(value, str) else "";
}

def _day(value: any) -> str {
    if isinstance(value, (int, float)) and not isinstance(value, bool) and value > 0 {
        try {
            return datetime.fromtimestamp(value / 1000, tz=timezone.utc).date().isoformat();
        } except (OverflowError, OSError, ValueError) {
            return "";
        }
    }
    text = _s(value);
    return text[:10] if re.match("\\d{4}-\\d{2}-\\d{2}", text) else "";
}

def _items(payload: any, key: str = "") -> list[any] {
    value = (payload.get(key) if isinstance(payload, dict) else None) if key else payload;
    return [v for v in value if isinstance(v, dict)] if isinstance(value, list) else [];
}

def _field(job: any, keys: str, conv: any) -> str {
    for key in keys.split("|") {
        value = job;
        for part in key.split(".") {
            value = value.get(part) if isinstance(value, dict) else None;
        }
        if conv(value) {
            return conv(value);
        }
    }
    return "";
}

def _posting(job: any, ats: str, dept: str = "", place: str = "") -> Posting {
    (title, d, loc, posted, url) = _FIELDS[ats].split();
    (title, d, loc) = (
        _field(job, title, _s),
        dept or _field(job, d, _s),
        place or _field(job, loc, _s),
    );
    return Posting(title, d, loc, _field(job, posted, _day), _field(job, url, _s));
}

def parse_feed(ats: str, payload: any) -> list[Posting] {
    out: list[Posting] = [];
    seen: set[any] = set();
    for dept in _items(payload, "departments") if ats == "greenhouse" else [] {
        name = _s(dept.get("name"));
        for job in _items(dept, "jobs") {
            key = job.get("id") or job.get("absolute_url") or job.get("title");
            if _s(job.get("title")) and key not in seen {
                seen.add(key);
                out.append(_posting(job, ats, "" if name.lower() == "no department" else name));
            }
        }
    }
    for job in _items(payload) if ats in ("lever", "lever_eu") else [] {
        if _s(job.get("text")) {
            out.append(_posting(job, "lever"));
        }
    }
    for job in _items(payload, "jobs") if ats in ("ashby", "workable") else [] {
        place = ", ".join(
            filter(None, [_s(job.get("city")), _s(job.get("state")), _s(job.get("country"))])
        );
        place = "Remote" if not place and job.get("telecommuting") else place;
        if _s(job.get("title")) and not (ats == "ashby" and job.get("isListed") is False) {
            out.append(_posting(job, ats, "", place if ats == "workable" else ""));
        }
    }
    return out;
}

async def read_board(client: httpx.AsyncClient, board: Board) -> list[Posting] | None {
    url = feed_url(board);
    body = bytearray();
    too_large = f"ats: {board.label} board {board.token} too large, skipped";
    try {
        async with client.stream("GET", url, headers={"Accept": "application/json"}) as resp {
            if resp.status_code != 200 or "json" not in resp.headers.get("content-type", "") {
                logger.debug(f"ats: {url} → {resp.status_code}");
                return None;
            }
            if int(resp.headers.get("content-length") or 0) > MAX_FEED_BYTES {
                logger.info(too_large);
                return None;
            }
            async for chunk in resp.aiter_bytes() {
                body += chunk;
                if len(body) > MAX_FEED_BYTES {
                    logger.info(too_large);
                    return None;
                }
            }
        }
    } except (httpx.HTTPError, ValueError) as e {
        logger.debug(f"ats: fetch failed {url}: {e}");
        return None;
    }
    try {
        return parse_feed(board.ats, json.loads(bytes(body)));
    } except (ValueError, RecursionError) {
        return None;
    }
}

def _words(text: str) -> set[str] {
    for (pattern, replacement) in _EQUIVALENT {
        text = pattern.sub(replacement, text);
    }
    return {str(w) for w in re.findall("[a-z0-9+#]+", text.lower())};
}

def _lowered(values: any) -> list[str] {
    return [v.strip().lower() for v in (values or []) if isinstance(v, str) and v.strip()];
}

def role_keywords(icp: any) -> list[str] {
    return _lowered(getattr(icp, "hiring_signals", None)) or _lowered(getattr(icp, "titles", None));
}

def _within(wanted: list[set[str]], title: set[str]) -> bool {
    return any(w <= title for w in wanted);
}

def matching_roles(postings: list[Posting], keywords: list[str]) -> list[Posting] {
    wanted = [w for w in ((_words(k) - _FILLER_WORDS) for k in keywords) if w];
    return [p for p in postings if _within(wanted, _words(_REPORTS_TO.sub("", p.title)))];
}
