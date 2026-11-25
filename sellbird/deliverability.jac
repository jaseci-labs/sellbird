"""Deliverability readiness - is this sending domain safe to cold email from?

Everything here is free and read-only: public DNS, RDAP, DNS blocklists, and
Sellbird's own send history. None of it can measure inbox reputation directly
(only mailbox providers know that), so the report also points at the two
things that can: Google Postmaster Tools and an inbox-placement test.
"""

import builtins;

import operator;

import re;

import from dataclasses { dataclass }

import from datetime { date, datetime }

import dns.exception;

import dns.resolver;

import httpx;

glob OK: any;

glob WARN: any;

glob FAIL: any;

glob INFO: any;

glob COMMON_DKIM_SELECTORS: any;

glob DOMAIN_BLOCKLISTS: any;

glob IP_BLOCKLISTS: any;

glob MANUAL_LOOKUP: any;

glob MIN_DOMAIN_AGE_DAYS: any;

glob GOOD_DOMAIN_AGE_DAYS: any;

glob MAX_BOUNCE_RATE: any;

glob MIN_SENDS_FOR_RATES: any;

glob DOMAIN_RE: any;

glob MAX_WARMUP_SPAM: any;

glob MIN_WARMUP_SAMPLE: any;

with entry {
    (OK, WARN, FAIL, INFO) = ("ok", "warn", "fail", "info");
    COMMON_DKIM_SELECTORS = (
        "google",
        "default",
        "selector1",
        "selector2",
        "k1",
        "k2",
        "s1",
        "s2",
        "mail",
        "dkim",
        "fm1",
        "fm2",
        "fm3",
        "zoho",
        "zmail",
        "mxvault",
        "protonmail",
        "protonmail2",
        "mandrill",
        "smtp",
        "sig1",
        "everlytickey1",
    );
    DOMAIN_BLOCKLISTS = (
        ("dbl.spamhaus.org", lambda (ip) -> any { ip.startswith("127.255.255.") }),
        ("multi.surbl.org", lambda (ip) -> any { operator.eq(ip, "127.0.0.1") }),
        ("multi.uribl.com", lambda (ip) -> any { operator.eq(ip, "127.0.0.1") }),
    );
    IP_BLOCKLISTS = (
        ("zen.spamhaus.org", lambda (ip) -> any { ip.startswith("127.255.255.") }),
        ("bl.spamcop.net", lambda (ip) -> any { False }),
    );
    MANUAL_LOOKUP = {
        "dbl.spamhaus.org": "https://check.spamhaus.org",
        "zen.spamhaus.org": "https://check.spamhaus.org",
        "multi.surbl.org": "https://www.surbl.org/surbl-analysis",
        "multi.uribl.com": "https://admin.uribl.com/",
        "bl.spamcop.net": "https://www.spamcop.net/bl.shtml",
    };

    MIN_DOMAIN_AGE_DAYS = 30;
    GOOD_DOMAIN_AGE_DAYS = 90;
    MAX_BOUNCE_RATE = 0.03;
    MIN_SENDS_FOR_RATES = 20;
}

@dataclass
class Check {
    has name: builtins.str;

    has status: builtins.str;

    has detail: builtins.str;

    has unknown: builtins.bool = False;
}

with entry {
    DOMAIN_RE = re.compile(
        "^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\\.)+(?:[a-z]{2,63}|xn--[a-z0-9-]{1,59})$",
    );
}

"""DNS couldn't answer (timeout, no reachable server): not the same as
    'no such record', so a check reports it as unknown, never as missing."""
obj LookupFailed(Exception) {
    def __repr__ -> str;

    def __eq__(other: any) -> bool;

    def __hash__ -> int;
}

def _resolve(name: builtins.str, rtype: builtins.str) -> any;

def _txt(name: builtins.str) -> builtins.list[builtins.str];

def _a(name: builtins.str) -> builtins.list[builtins.str];

def _unknown(name: builtins.str, e: any) -> Check;

def check_mx(domain: builtins.str) -> Check;

def check_spf(domain: builtins.str) -> Check;

def check_dmarc(domain: builtins.str) -> Check;

def check_dkim(domain: builtins.str, selector: builtins.str = "") -> Check;

def check_domain_age(domain: builtins.str) -> Check;

def _blocklist_checks(query: builtins.str, label: builtins.str, lists) -> builtins.list[Check];

def check_domain_blocklists(domain: builtins.str) -> builtins.list[Check];

def check_ip_blocklists(smtp_host: builtins.str) -> builtins.list[Check];

def check_warmup(
    warmup, ceiling: builtins.int, today: date | None = None, provider: builtins.str = ""
) -> Check;

with entry {
    MAX_WARMUP_SPAM = 0.05;
    MIN_WARMUP_SAMPLE = 20;
}

"""Is the sending mailbox actually warmed? Read from TrulyInbox when it's connected."""
def check_warmup_service(
    health,
    warmup=None,
    *,
    error: builtins.str = "",
    other_service: builtins.bool = False,
    today: date | None = None,
) -> Check;

def check_send_history(total_sent: builtins.int, bounces: builtins.int) -> Check;
