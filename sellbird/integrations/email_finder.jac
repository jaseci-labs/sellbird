"""Email discovery — pattern-first, verify-once, honest about confidence.

Raw SMTP probing is largely dead against Google Workspace and Microsoft
365 (which host most B2B mail): they tarpit probers or accept every
recipient and bounce later. So instead of brute-forcing every name
permutation, this pipeline:

1. Classifies the domain by its MX host (google / microsoft / gateway / other).
2. Derives the domain's email PATTERN once — from cache, then Hunter's
   free domain-search, then known addresses scraped off the site, else a
   sensible default — collapsing N guesses to one candidate.
3. Verifies that single candidate through the best available channel for
   the domain type: a real-verdict API (Reoon, ZeroBounce for the big
   providers), Hunter, or SMTP for small self-hosted servers.
4. Detects catch-all domains and buckets them as ``risky`` instead of
   pretending they're verified.

Every result carries an honest status: verified / risky / guess / invalid.
Only ``verified`` (and optionally ``risky``) should ever be emailed.
"""

import builtins;

import operator;

import asyncio;

import logging;

import os;

import random;

import re;

import from dataclasses { dataclass }

import from datetime { datetime, timezone }

import from typing { Optional }

import dns.resolver;

import aiosmtplib;

import httpx;

glob logger: any;

glob _mx_cache: builtins.dict[builtins.str, Optional[builtins.str]];

glob API_TIMEOUT: any;

glob PATTERN_BUILDERS: any;

glob DEFAULT_PATTERN: any;

glob SMALL_BUSINESS_PATTERN: any;

glob DEFAULT_SOURCES: any;

glob WEAK_SOURCES: any;

glob ROLE_LOCALS: any;

glob HUNTER_FREE_MONTHLY_SEARCHES: any;

with entry {
    logger = logging.getLogger("sellbird.email_finder");
    _mx_cache = {};

    API_TIMEOUT = httpx.Timeout(connect=10.0, read=20.0, write=10.0, pool=10.0);
    PATTERN_BUILDERS = {
        "{f}.{l}": lambda (f, l) -> any { f"{f}.{l}" },
        "{f}{l}": lambda (f, l) -> any { f"{f}{l}" },
        "{fi}{l}": lambda (f, l) -> any { f"{f[0]}{l}" },
        "{f}": lambda (f, l) -> any { f"{f}" },
        "{fi}.{l}": lambda (f, l) -> any { f"{f[0]}.{l}" },
        "{f}_{l}": lambda (f, l) -> any { f"{f}_{l}" },
        "{l}": lambda (f, l) -> any { f"{l}" },
        "{l}.{f}": lambda (f, l) -> any { f"{l}.{f}" },
        "{f}-{l}": lambda (f, l) -> any { f"{f}-{l}" },
        "{l}{fi}": lambda (f, l) -> any { f"{l}{f[0]}" },
    };
    DEFAULT_PATTERN = "{f}.{l}";
    SMALL_BUSINESS_PATTERN = "{f}";
    DEFAULT_SOURCES = ("default", "default_after_hunter");
    WEAK_SOURCES = DEFAULT_SOURCES + ("site_address_guess", "site_address_guess_after_hunter");
}

"""Hunter couldn't answer right now (timeout, 429, 5xx). Transient: the
    domain is asked again later, never remembered as having no pattern."""
obj HunterUnavailable(Exception) {
    def __repr__ -> str;

    def __eq__(other: any) -> bool;

    def __hash__ -> int;
}

"""Outcome of an email lookup. status is the source of truth."""
@dataclass
class EmailResult {
    has email: builtins.str;

    has status: builtins.str;

    has pattern: builtins.str = "";

    has mx_type: builtins.str = "";

    has verified: builtins.bool {
        getter {
            return operator.eq(self.status, "verified");
        }
    }

    """Safe to send cold: confirmed mailbox only (risky is opt-in elsewhere)."""
    has sendable: builtins.bool {
        getter {
            return operator.eq(self.status, "verified");
        }
    }
}

def _clean_domain(domain: builtins.str) -> builtins.str;

def _clean_name_part(value: builtins.str) -> builtins.str;

"""Render a named pattern into an address, or '' if it can't be built."""
def build_email(
    pattern: builtins.str, first: builtins.str, last: builtins.str, domain: builtins.str
) -> builtins.str;

"""All candidate addresses for a person, most-likely first (deduped)."""
def generate_patterns(
    first_name: builtins.str, last_name: builtins.str, domain: builtins.str
) -> builtins.list[builtins.str];

"""Bucket a domain by its mail host — decides the verification strategy."""
def classify_mx(mx_host: builtins.str) -> builtins.str;

"""Primary MX host for a domain (cached; None on failure)."""
async def get_mx_host(domain: builtins.str) -> Optional[builtins.str];

"""Given one known address, work out which named pattern produced it."""
def infer_pattern_from_email(
    email: builtins.str, first: builtins.str, last: builtins.str
) -> Optional[builtins.str];

with entry {
    ROLE_LOCALS = frozenset(
        "\ninfo office contact contactus hello hi team admin administrator support help sales\nservice services estimates estimate quotes quote inquiries inquiry enquiries enquiry\nbilling accounts accounting accountspayable ap ar invoices payments orders order\ncareers career jobs job hr recruiting employment apply marketing media press pr news\nnewsletter webmaster web website postmaster hostmaster abuse noreply no-reply donotreply\nreception frontdesk front appointments appointment schedule scheduling dispatch\ncustomerservice customercare care clients client mail email general main owner\nmanager management operations ops legal privacy compliance security it tech\nfeedback reviews referrals warranty claims insurance parts shop store\n".split(),
    );
}

"""The likely pattern behind one published address when nobody on the
    site is tied to it: corwin@ -> {f}, jsmith@ -> {fi}{l}, j.smith@ ->
    {fi}.{l}, john.smith@ -> {f}.{l}. None for role mailboxes and junk.

    Dotless addresses (corwin@, jsmith@) return None: alone they are
    ambiguous. The confidence is deliberately modest; an address tied to a
    named person (infer_pattern_from_email) is the stronger evidence.
    """
def pattern_from_local(
    local: builtins.str
) -> Optional[builtins.tuple[builtins.str, builtins.float]];

"""A dotless address no named person owns, read with the names the site
    does list: jsmith@ where an Amy Smith works is an initial plus a
    surname. Anything else stays ambiguous."""
def _disambiguate(
    local: builtins.str, people
) -> Optional[builtins.tuple[builtins.str, builtins.float]];

"""What a site's own published addresses say about its email format.

    Returns (known, pattern, confidence): ``known`` is every on-domain
    address that belongs to a named person on the site (nvale@ for Nora
    Vale), ready for find_email(known_emails=...). ``pattern`` is the
    format those addresses agree on; failing that, the majority format of
    addresses that show a format without being one person's (j.smith@,
    jsmith@ when John and Jane Smith are both named, or jsmith@ where an Amy
    Smith works); else "". An address two named people could own is never
    returned as either one's.
    """
def site_email_evidence(
    addresses: builtins.list[builtins.str],
    people: builtins.list[builtins.tuple[builtins.str, builtins.str]],
    domain: builtins.str,
) -> builtins.tuple[builtins.list[builtins.tuple[builtins.str, builtins.str, builtins.str]], builtins.str, builtins.float];

"""Hunter reads the key from X-API-KEY (documented alternative to the
    api_key query parameter), so it never appears in a request URL."""
def _hunter_headers(api_key: builtins.str) -> builtins.dict;

"""str(error) with the key blanked: an httpx error can carry the URL."""
def _redact(error, api_key: builtins.str) -> builtins.str;

"""Hunter's free domain-search returns the org's dominant email pattern.

    Hunter formats it with {first}/{last}/{f} tokens; translate to ours.
    Returns (named_pattern, confidence 0-1), or None when Hunter has no
    pattern for the domain. Raises HunterUnavailable when it couldn't answer.
    """
async def _hunter_domain_pattern(
    domain: builtins.str, api_key: builtins.str
) -> Optional[builtins.tuple[builtins.str, builtins.float]];

"""Map Hunter's {first}.{last}-style tokens to our named patterns."""
def _translate_hunter_pattern(hunter_pattern: builtins.str) -> Optional[builtins.str];

def _hunter_api_key -> builtins.str;

with entry {
    HUNTER_FREE_MONTHLY_SEARCHES = 25;
}

def _hunter_monthly_cap -> builtins.int;

def _hunter_usage_key -> builtins.str;

"""Domain-searches left this calendar month (UTC). Without a state
    store there is nothing to count against, so the full cap is reported."""
async def hunter_searches_remaining(state) -> builtins.int;

"""Count one domain-search against this month's budget. Called before
    the request, so a call that fails mid-flight is still counted."""
async def record_hunter_search(state) -> None;

"""Hunter's domain-search doesn't just give a pattern — it lists real
    named people it already has on file for the domain (name, title, email,
    and its own verification verdict). Returns the raw ``emails`` list, or
    None on any failure (network, non-200, bad JSON, or no data).

    Costs one domain-search credit per call regardless of ``limit``, so
    callers must check hunter_searches_remaining() and record_hunter_search()
    first rather than rely on this failing gracefully to protect the quota.
    """
async def hunter_domain_people(
    domain: builtins.str, api_key: builtins.str, limit: builtins.int = 10
) -> Optional[builtins.list[builtins.dict]];

glob default_pattern_default_: any;

with entry {
    default_pattern_default_ = DEFAULT_PATTERN;
}

"""Determine a domain's email pattern. Returns (pattern, source, confidence).

    Order: a known address for this domain (a named person's address on
    the site) → the DB cache, unless all it holds is a default → Hunter
    domain-search (once per domain) → ``default_pattern``. This is the step
    that collapses six guesses to one and is where free tiers stretch
    furthest. A cached default is a fallback, not evidence: it never blocks
    a real address or Hunter (it used to, forever).
    """
async def derive_pattern(
    domain: builtins.str,
    known_emails: Optional[builtins.list[builtins.tuple[builtins.str, builtins.str, builtins.str]]] = None,
    state=None,
    default_pattern: builtins.str = default_pattern_default_,
) -> builtins.tuple[builtins.str, builtins.str, builtins.float];

"""Reoon email-verifier — generous free tier, good catch-all flagging.

    Returns {'status': ..., 'catch_all': bool} or None if unavailable.
    Reoon power-mode 'status' values: safe / invalid / disabled / disposable /
    inbox_full / catch_all / role_account / spamtrap / unknown. 'safe' is its
    deliverable verdict; a 'role_account' (info@, office@) counts as valid
    only when Reoon also reports it deliverable.
    """
async def verify_reoon(email: builtins.str, api_key: builtins.str) -> Optional[builtins.dict];

"""ZeroBounce — its 2026 engine is the reliable one for M365/Workspace catch-alls."""
async def verify_zerobounce(email: builtins.str, api_key: builtins.str) -> Optional[builtins.dict];

async def verify_hunter(email: builtins.str, api_key: builtins.str) -> Optional[builtins.dict];

"""SMTP RCPT check — only trustworthy for small, self-hosted mail servers.

    Returns True (accepted), False (rejected), or None (couldn't tell).
    Port 25 is blocked on most cloud hosts, so this frequently returns None.
    """
async def verify_email_smtp(email: builtins.str) -> Optional[builtins.bool];

"""Probe a definitely-fake address; if accepted, the domain is catch-all.

    Only works where SMTP probing works at all (small hosts). Returns None
    when we can't tell.
    """
async def detect_catch_all(domain: builtins.str) -> Optional[builtins.bool];

"""Map a provider verdict dict to our status, or None if inconclusive."""
def _status_from_verdict(verdict: builtins.dict) -> Optional[builtins.str];

"""Run the best available verifier for this domain type.

    Returns (status_or_None, catch_all_seen). Order is chosen so scarce
    paid-ish credits are spent only where they actually resolve the domain.
    """
async def _verify_candidate(
    email: builtins.str, mx_type: builtins.str, env
) -> builtins.tuple[Optional[builtins.str], builtins.bool];

"""Grade an address the company publishes on its own website.

    Graded like any other address: a catch-all verdict stays "risky", so
    ``send_to_risky`` still decides whether it is sent (a published address
    can be stale). A verifier's invalid verdict wins, and an inconclusive
    check stays an honest guess that is never sent.
    """
async def verify_published_address(email: builtins.str, env=None) -> builtins.str;

def _belongs_to_someone_else(
    candidate, pattern, person, domain, other_people, known_emails
) -> builtins.bool;

glob default_pattern_default__: any;

with entry {
    default_pattern_default__ = DEFAULT_PATTERN;
}

"""Find and honestly grade one email for a person at a company.

    Returns an EmailResult whose ``status`` is verified / risky / guess /
    invalid. When ``verify`` is False (or no verifier is configured), the
    best pattern guess is returned as ``guess`` — never as verified. A
    person's own published address (in ``known_emails``) is used as is,
    and is still graded like any other.

    ``other_people`` are the other people named at the company. A candidate
    one of them could own (jsmith@ for Jane when John Smith works there too,
    or an address published as theirs) is never guessed or verified for
    this person: a verifier would confirm the other person's mailbox.
    """
async def find_email(
    first_name: builtins.str,
    last_name: builtins.str,
    domain: builtins.str,
    verify: builtins.bool = True,
    env=None,
    state=None,
    known_emails: Optional[builtins.list[builtins.tuple[builtins.str, builtins.str, builtins.str]]] = None,
    default_pattern: builtins.str = default_pattern_default__,
    other_people: Optional[builtins.list[builtins.tuple[builtins.str, builtins.str]]] = None,
) -> EmailResult;
