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

    def __bool__ -> bool;
}

def _clean_text(raw: any) -> str;

def _dnc_domain(value: str) -> str;
def do_not_contact_entry(raw: any) -> str;
def do_not_contact_entries(raw: any) -> list[str];

def _covers(host: str, domains: any) -> bool;
def _is_our_number(number: str, ours: set[str]) -> bool;
def _dnc_find(local: str | None, host: str, entries: any) -> str;
def do_not_contact_match(to_email: str, entries: any) -> str;
def do_not_contact_domain_match(domain: str, entries: any) -> str;
def pre_send_check(
    to_email: str,
    subject: str,
    body: str,
    prospect: any = None,
    allow_risky: bool = False,
    kind: str = "sequence",
    postal_address: str = "",
    do_not_contact: any = (),
) -> GateResult;

def _normalize(text: str) -> str;

def _host(value: str) -> str;
def find_links(text: str) -> list[tuple[str, str]];
def find_link_domains(text: str) -> list[str];

def _booking_prefix(config: any) -> str;
def allowed_link_domains(config: any) -> set[str];

def _is_booking_page(link: str, prefix: str) -> bool;

def _words(text: str) -> list[str];

def _instruction_runs(base: any) -> dict[any, str];

def _digits(value: str) -> str;
def find_phone_numbers(text: str) -> list[str];
def own_phone_numbers(config: any) -> set[str];
def autopilot_review(
    subject: str, body: str, config: any, `root: any = None, recipient: str = ""
) -> list[str];
