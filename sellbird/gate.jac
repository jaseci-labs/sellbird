"""Deterministic pre-send gate — the last line before an email leaves.

LLM instructions are a floor, not a guarantee. Every outgoing email passes
these non-LLM checks at send time; a failure blocks the send and records
why, so a bad generation can never reach a prospect. This is the pattern
the surviving commercial AI-SDR vendors converged on after the 2025
autonomous-agent flameouts: constraints in the prompt, verification in
code.
"""

import builtins;

import operator;

import re;

import unicodedata;

import from dataclasses { dataclass, field }

glob BANNED_PHRASES: any = (
    "act now",
    "buy now",
    "click here",
    "click below",
    "limited time",
    "limited offer",
    "exclusive deal",
    "special offer",
    "risk-free",
    "no obligation",
    "100% free",
    "make money",
    "double your",
    "guaranteed results",
    "winner",
    "congratulations",
    "i hope this finds you well",
    "hope this email finds you well",
    "i hope this email finds you",
    "picture this",
    "what if i told you",
    "in today's fast-paced world",
    "game-changer",
    "game changer",
    "cutting-edge solution",
    "revolutionize your",
    "unlock your",
    "supercharge your",
    "as an ai",
    "i'm an ai",
    "i am an ai",
    "as a language model",
);

glob MAX_SUBJECT_LEN: any = 90;

glob MAX_BODY_WORDS: any = 220;

glob MAX_LINKS: any = 1;

glob EMAIL_RE: any;

glob MERGE_TAG_RE: any;

glob URL_RE: any;

glob DELIVERABLE_STATUSES: any;

glob _INVISIBLE_RE: any;

glob _DNC_DOMAIN_RE: any;

glob _DNC_LOCAL_RE: any;

glob _FILE_ENDINGS: any;

glob _KNOWN_ENDINGS: any;

glob _ENDINGS_RE: any;

glob _ZERO_WIDTH_RE: any;

glob _DOT_FORMS_RE: any;

glob _SPOKEN_DOT_RE: any;

glob _SPACED_DOT_RE: any;

glob _SCHEME_URL_RE: any;

glob _EMAIL_HOST_RE: any;

glob _HOST_OK_RE: any;

glob UNREADABLE_LINK: any;

glob _IP_RE: any;

glob _BARE_RE: any;

glob _SAY_ALOUD_FILES: any;

glob LEAK_RUN_WORDS: any;

glob _WORD_RE: any;

glob _SCRIPT_LINE_RE: any;

glob _QUOTED_RE: any;

glob _leak_cache: builtins.dict;

glob _PHONE_RE: any;

glob _ISO_DATE_RE: any;

glob _PAYMENT_RE: any;

with entry {
    EMAIL_RE = re.compile("^[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}$");
    MERGE_TAG_RE = re.compile("\\{\\{\\s*\\w+\\s*\\}\\}|\\{\\s*\\w+\\s*\\}(?!\\})");
    URL_RE = re.compile("https?://\\S+", re.IGNORECASE);

    DELIVERABLE_STATUSES = {"verified", "risky"};
}

@dataclass
class GateResult {
    has ok: builtins.bool;

    has reasons: builtins.list[builtins.str] = field(default_factory=list[any]);

    def __bool__ -> bool;
}

with entry {
    _INVISIBLE_RE = re.compile("[­​-‍⁠﻿]");
    _DNC_DOMAIN_RE = re.compile("^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z0-9-]{2,63}$");
    _DNC_LOCAL_RE = re.compile("^[a-z0-9._%+'-]+$");
}

def _clean_text(raw) -> builtins.str;

def _dnc_domain(value: builtins.str) -> builtins.str;

"""One do-not-contact entry as an address or a bare domain, or "" when
    it names neither.

    People paste what the browser shows, so "https://www.acme.example/about",
    "mailto:jane@acme.example", "*.acme.example", "*@acme.example" and
    "acme.example:443" all reduce to what they name. Left alone, each would
    quietly match nothing. An international domain becomes its ASCII form,
    the one recipient addresses carry.
    """
def do_not_contact_entry(raw) -> builtins.str;

"""Every entry one configured string holds. Commas, semicolons and spaces
    separate entries; "Jane Doe <jane@acme.example>" is that address.
    Raises ValueError for a piece that is neither an address nor a domain:
    an entry that silently matches nothing leaves the user believing a
    company is protected when it isn't."""
def do_not_contact_entries(raw) -> builtins.list[builtins.str];

"""The do-not-contact entry ``to_email`` matches, or "".

    An entry with an "@" is one address, plus-tags included ("jane@" also
    covers "jane+news@"). Anything else is a domain and covers its
    subdomains, matched on a label boundary so "acme.example" blocks
    "mail.acme.example" without also blocking "notacme.example" — a suffix
    test without that boundary is the classic way a blocklist overreaches.

    Entries are expected already normalised by ComplianceConfig; this
    normalises anyway so a hand-built tuple behaves the same way.
    """
def do_not_contact_match(to_email: builtins.str, entries) -> builtins.str;

"""The do-not-contact entry ``domain`` belongs to, or "".

    Only domain entries count here. An address entry bars one mailbox, not
    the company behind it: "jane@acme.example" says don't email Jane, so
    acme.example stays discoverable and a colleague can still be reached.
    Excluding a whole company on the strength of one address would shrink
    the pool in a way nobody asked for, and silently.

    The domain test is the one in ``do_not_contact_match``: a label
    boundary, so "acme.example" covers "mail.acme.example" and leaves
    "notacme.example" — a different company — alone.
    """
def do_not_contact_domain_match(domain: builtins.str, entries) -> builtins.str;

"""Run every deterministic check. Returns ok=False with reasons on any hit.

    postal_address: when set, a cold (sequence) email must carry it (CAN-SPAM).
    do_not_contact: addresses and domains that must never be emailed at all.
    """
def pre_send_check(
    to_email: builtins.str,
    subject: builtins.str,
    body: builtins.str,
    prospect=None,
    allow_risky: builtins.bool = False,
    kind: builtins.str = "sequence",
    postal_address: builtins.str = "",
    do_not_contact=(),
) -> GateResult;

with entry {
    _FILE_ENDINGS = frozenset(
        "\n    js ts pdf png jpg jpeg gif svg webp heic txt csv doc docx xls xlsx ppt pptx key pages\n    json yaml yml toml xml html htm css exe dmg msi bat ini cfg mp3 mp4 wav\n".split(),
    );
    _KNOWN_ENDINGS = frozenset(
        "\n    com net org info biz name pro mobi asia tel xxx io ai app dev xyz site online store shop\n    tech cloud page agency studio digital email live life media news blog club world today\n    one link click top icu buzz win bid loan work fun space website host press services\n    solutions company business center group network systems software tools zone works sale\n    deals plus vip best ltd inc llc gmbh zip mov cfd sbs cyou rest bar beauty hair skin\n    love sexy porn casino bet poker game games bio eco green energy solar money cash pay\n    finance capital fund trade market markets exchange loans credit insurance legal law\n    health care clinic dental doctor coach academy school university courses training jobs\n    careers events tickets travel tours hotel homes house realty estate properties land\n    gov edu mil int test example invalid localhost onion\n".split(),
    );
    _ENDINGS_RE = "|".join(sorted(_KNOWN_ENDINGS, key=builtins.len, reverse=True));
    _ZERO_WIDTH_RE = re.compile("[​-‏⁠﻿]");
    _DOT_FORMS_RE = re.compile("\\s*[\\[({]\\s*(?:\\.|dot)\\s*[\\])}]\\s*", re.IGNORECASE);
    _SPOKEN_DOT_RE = re.compile(
        f"(?<=\\w\\w)\\s+dot\\s+(?=(?:{_ENDINGS_RE}|[a-z]{{2}})\\b)", re.IGNORECASE
    );
    _SPACED_DOT_RE = re.compile(
        f"(?<=\\w)\\s+\\.\\s*(?=(?:{_ENDINGS_RE})\\b|[^\\W\\d_]{{2,24}}/)", re.IGNORECASE
    );
    _SCHEME_URL_RE = re.compile("\\b[a-z][a-z0-9+.-]*://[^\\s<>\\\"']+", re.IGNORECASE);
    _EMAIL_HOST_RE = re.compile(
        "(?:[\\w.%+\\-]+|\\\"[^\\\"\\n]*\\\"|“[^”\\n]*”)?@((?:[^\\W_][\\w-]*\\.)+[^\\W\\d_]{2,})"
    );
    _HOST_OK_RE = re.compile("^[^\\W_](?:[\\w.-]*[^\\W_])?$");
    UNREADABLE_LINK = "link that can't be read";
    _IP_RE = re.compile("(?<![\\w.])\\d{1,3}(?:\\.\\d{1,3}){3}(?![\\w.])");
    _BARE_RE = re.compile(
        "(?<![\\w@.])((?:[^\\W_](?:[\\w-]{0,61}[^\\W_])?\\.)+([^\\W\\d_]{2,24}))(?![\\w-])([/?#][^\\s<>\\\"']*)?",
    );
}

"""The text as a reader's browser or eye takes it: fullwidth and other
    lookalike dots become dots, hidden characters go, "evil[.]com" and
    "evil dot com" become evil.com."""
def _normalize(text: builtins.str) -> builtins.str;

def _host(value: builtins.str) -> builtins.str;

"""Every link and address in ``text`` as (host, host + path), in order.

    The host is the one a browser opens: "https://yours.com:pw@evil.com"
    and "https://evil.com\\.yours.com" both go to evil.com."""
def find_links(text: builtins.str) -> builtins.list[builtins.tuple[builtins.str, builtins.str]];

"""Every domain a link or email address in ``text`` points at, in order."""
def find_link_domains(text: builtins.str) -> builtins.list[builtins.str];

def _booking_prefix(config) -> builtins.str;

"""Your own domains: the sending address's and any listed in
    channels.email.link_domains. (The booking link allows its own page,
    not its whole host: cal.com is everyone's.)"""
def allowed_link_domains(config) -> builtins.set[builtins.str];

def _is_ours(host: builtins.str, allowed: builtins.set[builtins.str]) -> builtins.bool;

"""``link`` is your booking page (or below it), as a browser resolves it:
    "cal.com/you/15/../../them" is someone else's page."""
def _is_booking_page(link: builtins.str, prefix: builtins.str) -> builtins.bool;

"""What to name in the reason: the host, or host/first-segment when the
    host is the booking link's shared one."""
def _shown(host: builtins.str, link: builtins.str, prefix: builtins.str) -> builtins.str;

with entry {
    _SAY_ALOUD_FILES = frozenset({
        "email_frameworks.md",
        "product_knowledge.md",
        "objection_handling.md",
        "README.md",
    });
    LEAK_RUN_WORDS = 12;
    _WORD_RE = re.compile("[a-z0-9']+");
    _SCRIPT_LINE_RE = re.compile("^\\s*(?:[-*]\\s*)?(?:>|[\\\"“'‘])");
    _QUOTED_RE = re.compile("\"[^\"\\n]{12,}\"|“[^”\\n]{12,}”");
    _leak_cache = {};
}

def _words(text: builtins.str) -> builtins.list[builtins.str];

"""Every LEAK_RUN_WORDS-word run in Sellbird's instructions → its file."""
def _instruction_runs(`root) -> builtins.dict[builtins.tuple, builtins.str];

with entry {
    _PHONE_RE = re.compile(
        "(?<![\\w+#$€£])(?:\\+|00)?\\(?\\d[\\d \\t().\\-\\u2010-\\u2015/]{5,22}\\d(?![\\w])"
    );
    _ISO_DATE_RE = re.compile("^\\d{4}-\\d{2}-\\d{2}$");
    _PAYMENT_RE = re.compile(
        "\\b(?:wire\\s+transfer|bank\\s+(?:account|details|transfer|wire)|routing\\s+number|account\\s+number|sort\\s+code|iban|swift\\s+code|bitcoin|btc\\s+address|ethereum|usdt|crypto(?:currency)?\\s+(?:wallet|address|payment)|wallet\\s+address|gift\\s+cards?|western\\s+union|moneygram|zelle|venmo|cash\\s*app|paypal\\.me)\\b",
        re.IGNORECASE,
    );
}

def _digits(value: builtins.str) -> builtins.str;

"""Every phone number in ``text``, as written."""
def find_phone_numbers(text: builtins.str) -> builtins.list[builtins.str];

"""``number`` is one of ``ours``, with or without its country code."""
def _is_our_number(number: builtins.str, ours: builtins.set[builtins.str]) -> builtins.bool;

"""Your numbers: channels.email.phone_numbers, and any in your postal address."""
def own_phone_numbers(config) -> builtins.set[builtins.str];

"""Why an email nobody approved must wait for a human, or [] to send.

    What a planted instruction would try: point the reader somewhere that
    isn't yours (a link, an address, a phone number), ask them to send money,
    or get Sellbird to quote its own instructions back.
    ``recipient``'s own domain is fine to mention to them ("saw
    joesroofing.com"): it's theirs."""
def autopilot_review(
    subject: builtins.str, body: builtins.str, config, `root=None, recipient: builtins.str = ""
) -> builtins.list[builtins.str];
