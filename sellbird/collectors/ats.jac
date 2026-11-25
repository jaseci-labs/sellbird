"""Open roles, read from the job-board feed a company's ATS publishes.

Cost: $0, one request. Greenhouse, Lever, Ashby and Workable each publish a
company's open roles as public, unauthenticated JSON — the same data their
hosted job boards render. That beats reading a careers page: most careers
pages load their roles with JavaScript from exactly these feeds, so the HTML
we fetch has none of them, and the feed gives the department, location and
posting date as well as the title.

Which board a company uses comes from links and embeds on its OWN site
(``boards.greenhouse.io/<token>``, ``jobs.lever.co/<company>``, an embed
script). Never by guessing tokens: a guessed token that happens to exist is
somebody else's board, and the roles would be attributed to the wrong company.
"""

import builtins;

import operator;

import json;

import logging;

import re;

import from collections { Counter }

import from dataclasses { dataclass }

import from datetime { datetime, timezone }

import from urllib.parse { quote, unquote }

import httpx;

glob logger: any = logging.getLogger("sellbird.collectors.ats");

glob MAX_FEED_BYTES: any = 8 * 1024 * 1024;

glob ATS_LABELS: any = {
    "greenhouse": "Greenhouse",
    "lever": "Lever",
    "lever_eu": "Lever",
    "ashby": "Ashby",
    "workable": "Workable",
};

glob _S: any = "\\\\?/";

glob _TOKEN: any = "([A-Za-z0-9][A-Za-z0-9_.%-]*)";

glob _BOARD_RES: any = (
    (
        "greenhouse",
        re.compile(
            f"(?:job-)?boards\\.greenhouse\\.io{_S}embed{_S}job_(?:board|app)(?:{_S}js)?\\?(?:[^\\\"'\\s<>]*?&(?:amp;)?)?for=([A-Za-z0-9_-]+)",
            re.I,
        ),
    ),
    (
        "greenhouse",
        re.compile(f"boards-api\\.greenhouse\\.io{_S}v1{_S}boards{_S}([A-Za-z0-9_-]+)", re.I),
    ),
    (
        "greenhouse",
        re.compile(f"(?<![\\w.@-])(?:job-)?boards\\.greenhouse\\.io{_S}([A-Za-z0-9_-]+)", re.I),
    ),
    ("lever", re.compile(f"(?<![\\w.@-])jobs\\.lever\\.co{_S}{_TOKEN}", re.I)),
    ("lever", re.compile(f"(?<![\\w.@-])api\\.lever\\.co{_S}v0{_S}postings{_S}{_TOKEN}", re.I)),
    ("lever_eu", re.compile(f"(?<![\\w.@-])jobs\\.eu\\.lever\\.co{_S}{_TOKEN}", re.I)),
    (
        "lever_eu",
        re.compile(f"(?<![\\w.@-])api\\.eu\\.lever\\.co{_S}v0{_S}postings{_S}{_TOKEN}", re.I),
    ),
    ("ashby", re.compile(f"(?<![\\w.@-])jobs\\.ashbyhq\\.com{_S}{_TOKEN}", re.I)),
    ("ashby", re.compile(f"api\\.ashbyhq\\.com{_S}posting-api{_S}job-board{_S}{_TOKEN}", re.I)),
    (
        "workable",
        re.compile(
            f"apply\\.workable\\.com{_S}api{_S}v1{_S}widget{_S}accounts{_S}([A-Za-z0-9_-]+)", re.I
        ),
    ),
    ("workable", re.compile(f"(?<![\\w.@-])apply\\.workable\\.com{_S}([A-Za-z0-9_-]+)", re.I)),
    ("workable", re.compile("(?<![\\w.@-])([a-z0-9][a-z0-9-]*)\\.workable\\.com(?![\\w-])", re.I)),
);

glob _NOT_TOKENS: any = frozenset(
    "\nembed api j v0 v1 jobs job job_board posting-api www apply app help resources\ncareers static assets cdn widget accounts blog login signin\n".split(),
);

glob _ASSET: any = re.compile("\\.(js|mjs|css|json|png|jpe?g|svg|gif|ico|webp|woff2?|map)$", re.I);

glob MANY_BOARDS: any = 3;

glob _FILLER_WORDS: any = frozenset({"of", "the", "and", "for", "a", "an", "&", "to"});

glob _EQUIVALENT: any = `tuple(
    (re.compile(p, re.I), r)
    for (p, r) in (
        ("\\bvice[\\s-]+president\\b", "vp"),
        ("\\bchief\\s+executive\\s+officer\\b", "ceo"),
        ("\\bchief\\s+marketing\\s+officer\\b", "cmo"),
        ("\\bchief\\s+technology\\s+officer\\b", "cto"),
        ("\\bchief\\s+technical\\s+officer\\b", "cto"),
        ("\\bchief\\s+financial\\s+officer\\b", "cfo"),
        ("\\bchief\\s+operating\\s+officer\\b", "coo"),
        ("\\bchief\\s+revenue\\s+officer\\b", "cro"),
        ("\\bchief\\s+product\\s+officer\\b", "cpo"),
        ("\\bsr\\b\\.?", "senior"),
        ("\\bjr\\b\\.?", "junior"),
        ("\\bfront[\\s-]+end\\b", "frontend"),
        ("\\bback[\\s-]+end\\b", "backend"),
        ("\\bfull[\\s-]+stack\\b", "fullstack"),
    ),
);

glob _REPORTS_TO: any = re.compile("\\s+to\\s+(?:the\\s+|our\\s+)?\\S.*$", re.I);

"""One company's job board on one ATS."""
@dataclass(frozen=True)
class Board {
    has ats: builtins.str;

    has token: builtins.str;

    has label: builtins.str {
        getter {
            return ATS_LABELS.get(self.ats, self.ats);
        }
    }

    """The public board a person would open."""
    has page_url: builtins.str {
        getter {
            t: any = quote(self.token, safe="");
            return {
                "greenhouse": f"https://boards.greenhouse.io/{t}",
                "lever": f"https://jobs.lever.co/{t}",
                "lever_eu": f"https://jobs.eu.lever.co/{t}",
                "ashby": f"https://jobs.ashbyhq.com/{t}",
                "workable": f"https://apply.workable.com/{t}/",
            }[self.ats];
        }
    }
}

"""One open role, as the board lists it."""
@dataclass
class Posting {
    has title: builtins.str;

    has department: builtins.str = "";

    has location: builtins.str = "";

    has posted: builtins.str = "";

    has url: builtins.str = "";

    """"Head of Growth · Marketing · New York, NY · posted 2026-10-01"."""
    def summary -> builtins.str;
}

def _alnum(text: builtins.str) -> builtins.str;

"""The job board this page links to or embeds, or None.

    A page can mention several (a customer story linking to a customer's
    board): the one named like the company's domain wins, then the one
    linked most often.
    """
def detect_board(html: builtins.str, domain: builtins.str = "") -> Board | None;

"""The documented public JSON feed for a board."""
def feed_url(board: Board) -> builtins.str;

def _s(value) -> builtins.str;

"""YYYY-MM-DD from an ISO timestamp, a date, or epoch milliseconds."""
def _day(value) -> builtins.str;

def _greenhouse(payload) -> builtins.list[Posting];

def _lever(payload) -> builtins.list[Posting];

def _ashby(payload) -> builtins.list[Posting];

def _workable(payload) -> builtins.list[Posting];

glob _PARSERS: any;

with entry {
    _PARSERS = {
        "greenhouse": _greenhouse,
        "lever": _lever,
        "lever_eu": _lever,
        "ashby": _ashby,
        "workable": _workable,
    };
}

"""The open roles in a feed. Anything unexpected is skipped, never raised."""
def parse_feed(ats: builtins.str, payload) -> builtins.list[Posting];

"""Read one board's feed: one request, size-capped. None when the board
    doesn't answer with JSON (gone, renamed, or never existed)."""
async def read_board(client: httpx.AsyncClient, board: Board) -> builtins.list[Posting] | None;

def _words(text: builtins.str) -> builtins.set[builtins.str];

"""Roles that mean a company is in-market: ``icp.hiring_signals``, or
    ``icp.titles`` when none are set. Lowercased."""
def role_keywords(icp) -> builtins.list[builtins.str];

"""Postings whose title holds every word of some keyword, in any order:
    "VP Marketing" matches "VP of Marketing", "cto" doesn't match "Director"."""
def matching_roles(
    postings: builtins.list[Posting], keywords: builtins.list[builtins.str]
) -> builtins.list[Posting];
