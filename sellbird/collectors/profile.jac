import asyncio;
import logging;
import random;
import re;
import unicodedata;
import from functools { partial }
import from importlib { import_module }
import from html { unescape }
import from datetime { date, datetime, timezone }
import from urllib.parse { urljoin, urlparse }
import httpx;

glob logger = logging.getLogger("sellbird.collectors.profile"),
     TIMEOUT = httpx.Timeout(connect=8.0, read=12.0, write=8.0, pool=8.0),
     USER_AGENTS = [
         "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
         "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36",
     ],
     BENIGN_HOSTS = tuple(
         ("facebook. instagram. twitter. x.com linkedin. youtube. tiktok. pinterest. yelp. nextdoor. "
             "threads. google.com/maps g.page maps.app.goo.gl goo.gl wa.me bing.com/maps apple.com/maps "
             "greensky wellsfargo synchrony affirm klarna paypal stripe.com bbb.org angi.com homeadvisor "
             "houzz. trustpilot birdeye podium.com accessibe userway audioeye termly iubenda onetrust "
             "cloudflare godaddy wordpress.org wix.com squarespace.com shopify.com webflow.com duda.co "
             "gtranslate jquery gstatic googleapis cloudfront akamai w3.org schema.org gaf.com "
             "owenscorning certainteed nrca.net iko.com energystar.gov osha.gov nahb.org").split(),
     ),
     STRONG_CREDIT = "(?i)\\b(powered|website|site|web\\s*design|designed|developed|built|created|marketing)\\s+(by|&)\\b",
     DESCRIPTIVE_CREDIT = "(?i)\\b(web\\s*design|website\\s*design|digital\\s*marketing|seo|marketing\\s*agency|web\\s*development)\\b",
     RECORD_FLOOR = 0.75,
     TECH_FINGERPRINTS = dict(
         (row.partition(":")[0], tuple(row.partition(":")[2].split()))
         for row in ("WordPress:wp-content/ wp-includes/|Shopify:cdn\\.shopify\\.com myshopify\\.com|"
             "Wix:static\\.parastorage\\.com|Squarespace:static1\\.squarespace\\.com|"
             "Webflow:assets\\.website-files\\.com data-wf-domain|Duda:irp\\.cdn-website\\.com d1\\.awsstatic|"
             "GoDaddy Website Builder:img1\\.wsimg\\.com|HubSpot:js\\.hs-scripts\\.com js\\.hsforms\\.net|"
             "Google Analytics:googletagmanager\\.com/gtag google-analytics\\.com|"
             "Google Tag Manager:googletagmanager\\.com/gtm\\.js|Intercom:widget\\.intercom\\.io|"
             "Drift:js\\.driftt\\.com|Podium:connect\\.podium\\.com|Birdeye:birdeye\\.com|"
             "Calendly:assets\\.calendly\\.com|ServiceTitan:servicetitan|Jobber:getjobber\\.com|"
             "Housecall Pro:housecallpro|CallRail:cdn\\.callrail\\.com|Stripe:js\\.stripe\\.com").split(
             "|"
         ),
     ),
     GOOGLE_ADS = tuple(
         "googleadservices\\.com gtag/js\\?id=AW- google_conversion googletagmanager\\.com/gtag/js\\?id=AW-".split(),
     ),
     META_PIXEL = ("connect\\.facebook\\.net/[^\\\"']*fbevents\\.js", "fbq\\s*\\(\\s*['\\\"]init"),
     BOOKING_HINTS = tuple(
         ("calendly\\.com acuityscheduling schedulicity squareup\\.com/appointments setmore book(ing)?[-_]?now "
             "schedule[-_]?(an?[-_])?(appointment|estimate|consultation) housecallpro getjobber\\.com "
             "servicetitan").split(),
     ),
     AI_CRAWLERS = tuple(
         "gptbot google-extended ccbot anthropic-ai claudebot perplexitybot bytespider".split()
     ),
     TEAM_PATHS = tuple(
         "/team /about /about-us /our-team /staff /leadership /meet-the-team /company/team".split()
     ),
     CAREERS_PATHS = tuple(
         "/careers /jobs /join-us /employment /hiring /about/careers /careers/".split()
     ),
     _CAREERS_HOST = "(?i)^(careers?|jobs|join)\\.",
     _CAREERS_SEGMENTS = frozenset(
         "careers career jobs join join-us joinus work-with-us open-roles open-positions hiring".split(),
     ),
     _CAREERS_ANCHOR = "(?i)^(careers?|jobs|join us|join (our|the) team|we['’]?re hiring|open (roles|positions)|work with us)$",
     MAX_BOARD_ROLES = 5,
     CONTACT_PATHS = tuple(
         "/contact /contact-us /get-a-quote /free-estimate /request-estimate /quote".split()
     ),
     _FOLD_TABLE = {cp: _folded(cp) for cp in range(0xC0, 0x250) if _folded(cp)},
     NON_NAME_WORDS = frozenset(
         ("service services repair repairs roofing roof roofs contractor contracting "
             "commercial residential industrial storm damage restoration installation "
             "history about contact quote quotes estimate estimates free request get call "
             "learn more read view our their your team staff careers jobs home page site "
             "company companies inc llc ltd corp group solutions systems partners "
             "gallery projects reviews testimonials financing warranty insurance claims "
             "maintenance inspection replacement gutters siding windows doors metal shingle "
             "shingles tile flat emergency 24 hour hours today now new best top quality "
             "privacy policy terms conditions sitemap blog news events why choose us "
             "areas served locations location city county state north south east west "
             "español espanol menu skip navigation search close open toggle "
             "hoa hoas condo condos association associations board boards community "
             "communities management property properties owners residents customer care "
             "scope alignment implementation consistency communication process driven "
             "focused structured "
             "chauffage climatisation ventilation refrigeration thermopompe thermopompes "
             "climatiseur climatiseurs fournaise fournaises plomberie electricite toiture "
             "entretien reparation reparations urgence soumission soumissions estimation "
             "residentiel residentielle commercial commerciale industriel industrielle "
             "produits produit garantie garanties financement subventions subvention "
             "realisations accueil equipe equipes propos joindre contactez").split(),
     ),
     _NOUN_SUFFIX = re.compile("(tion|tions|sion|sions|ness)$"),
     _BLOCK_BREAK = "(?i)<(?:/?(?:p|div|li|ul|ol|section|article|td|tr)\\b[^>]*|br\\s*/?)>",
     _CONNECTORS = frozenset("of and the for & to in at de du des la le et en au aux a".split()),
     DECISION_MAKER_TITLES = tuple(
         ("owner|founder|co-founder|president|ceo|principal|partner|general manager|operations manager|"
             "practice manager|office manager|marketing director|marketing manager|director of marketing|"
             "vice president|vp |managing director|chief|director|proprietaire|president|pdg|fondat|"
             "directeur|directrice|gerant|associe").split("|"),
     ),
     ROLE_HINT = "(?i)\\b(owner|founder|president|ceo|cfo|coo|cto|principal|partner|manager|director|supervisor|superintendent|foreman|estimator|specialist|consultant|coordinator|representative|rep|sales|marketing|operations|office|project|account|service|technician|installer|inspector|vice president|vp|executive|lead|head of|chief|proprietor|attorney|lawyer|dentist|orthodontist|periodontist|endodontist|hygienist|dds|dmd|esq|cpa|administrator|paralegal|associate|co-?owner|co-?founder|co-?proprietaire|proprietaire|presidente?|pdg|p\\.-?d\\.g|co-?fondat(?:eur|rice)|fondat(?:eur|rice)|directeur|directrice|gerante?|gestionnaire|associee?|adjointe?|technicien(?:ne)?|estimat(?:eur|rice)|representante?|conseill(?:er|ere)|coordonnat(?:eur|rice)|contremaitre|superviseure?|responsable|chargee?|ventes|comptable|administrat(?:eur|rice)|ingenieure?|frigoriste|mecanicien(?:ne)?|installat(?:eur|rice)|repartit(?:eur|rice)|secretaire|receptionniste)\\b",
     _BLOCK_MARKERS = tuple(
         ("unusual traffic|detected unusual activity|/sorry/index|/.well-known/sgcaptcha|cf-chl-|cf_chl_opt|"
             "px-captcha|_incapsula_resource|incapsula incident id|sucuri website firewall").split(
             "|"
         ),
     ),
     _BLOCK_TITLES = tuple(
         ("just a moment|attention required|access denied|access to this page has been denied|are you a robot|"
             "security check|verify you are human|human verification|bot verification|ddos protection|"
             "ddos-guard|one more step").split("|"),
     ),
     _WEAK_BLOCK_MARKERS = tuple(
         ("captcha|are you a robot|verify you are human|access denied|"
             "enable javascript and cookies to continue").split("|"),
     );

glob YC_OWNED_DOMAINS = ("ycombinator.com", "workatastartup.com", "startupschool.org"),
     _YC = "(?:YC|Y[\\s-]?Combinator)",
     _YC_LINK_RE = "(?i)ycombinator\\.com\\\\?/companies\\\\?/([a-z0-9][\\w-]*)",
     YC_ABOUT_PATHS = ("/about", "/about-us", "/company", "/our-story"),
     FUNDING_PATHS = ("/press", "/news", "/newsroom", "/blog"),
     _YC_SEASONS = dict(
         kv.partition(":")[::2]
         for kv in "w:W winter:W s:S summer:S f:F fall:F x:X spring:X".split(),
     ),
     _SEASON_WORD = "(Winter|Summer|Fall|Spring)",
     _YC_BATCH_RES = [
         re.compile(p, re.I)
         for p in (
             f"\\b{_YC}(?:['’]s)?\\s*(?:(?:alumni|alums?|company|startup)\\s*)?[\\(\\[]?\\s*(W|S|F|X)\\s*'?(\\d{{2}})\\b(?![\\w-]*\\s*(?:Ultra|Plus|Pro|FE|Max)\\b)",
             f"\\b{_YC}(?:['’]s)?\\s+{_SEASON_WORD}\\s+(?:batch\\s+)?(\\d{{4}})\\b",
             f"\\b{_SEASON_WORD}\\s+(\\d{{4}})\\s+batch\\s+(?:of|at)\\s+{_YC}\\b",
             f"\\b{_YC}\\s+(?:in|during)\\s+(?:the\\s+)?{_SEASON_WORD}\\s+(?:of\\s+)?(\\d{{4}})\\b",
             f"\\b{_YC}\\s+demo day\\s*[\\(\\[]\\s*(W|S|F|X)\\s*'?(\\d{{2}})\\b",
         )
     ],
     _BATCH = "(?:W|S|F|X)\\s*'?\\d{2}",
     _FILLER = "(?:\\s+(?:proudly|also|now|officially|recently|originally|first|both|all|so|were|was|are|is|been|have|has|had|very))*",
     _SELF_SUBJECT = "(?:we|we're|we are|we were|we've been|proud(?:ly)? to be|excited to be|honou?red to be|the company|our company)",
     _FOUNDED_PREFIX = "(?:founded in \\d{4},?\\s+)?",
     _YC_NOUNS = "company|startup|platform|product|business|team|tool",
     _YC_EVENTS = "startup school|demo day|application|interview|events?|podcast|blog|news|jobs|deals?|perks?",
     _ATTR_TEXT_RE = "(?i)\\b(?:alt|title|aria-label)=[\"']([^\"']{0,200})[\"']",
     _BLOCK_TAG_RE = "(?i)</?(?:p|div|h[1-6]|li|ul|ol|br|section|footer|header|nav|article|td|tr|table|blockquote|figcaption|dt|dd)\\b[^>]*>",
     _SENTENCE_RE = "(?<=[.!?])\\s+|\\s*[|•·]\\s*|\\n",
     _PREFIXES = "^(?:get|try|use|join)(?=\\w{4})",
     _SUFFIXES = "(?<=\\w{4})hq$",
     _SECOND_LEVEL = {"co", "com", "org", "net", "ac", "gov", "edu"};

glob _NOT_NAMED = "(?![\\w-]|\\.\\w|\\s+(?!(?:and|or|in|as|with|since|from|to|alongside|plus|batch|cohort|company|startup|portfolio|alumni|alums?|backed|funded|residency|program)\\b)[\\w])",
     ACCELERATORS = (
         ("Techstars", "Techstars"),
         ("500 Global", "(?-i:500\\s+(?:Global(?!\\s+[a-z]+s\\b)|Startups))"),
         ("Antler", f"(?-i:Antler){_NOT_NAMED}"),
         ("Entrepreneur First", "(?-i:Entrepreneur\\s+First)"),
         ("South Park Commons", "South\\s+Park\\s+Commons"),
         ("Neo", f"(?-i:Neo){_NOT_NAMED}"),
         ("AI Grant", "(?-i:AI\\s+Grant)"),
         ("a16z speedrun", "(?:a16z(?:['’]s)?\\s+speedrun|speedrun\\s+(?:by|from)\\s+a16z)"),
         ("Pioneer", f"(?-i:Pioneer){_NOT_NAMED}"),
         ("Plug and Play", "(?-i:Plug\\s+(?:and|&)\\s+Play)"),
     ),
     _ACC_BATCH = "(?:['’]?\\d{2}|20\\d{2}|(?-i:SR)\\s*\\d{1,3})",
     _ACC_NOUNS = "company|startup|portfolio company|alumn(?:us|i|a)",
     _ACC_EVENTS = "startup weekend|startup week|startup digest|summit|expo|events?|conference|podcast|blog|news|newsletter|jobs|applications?|mentors?|demo day|office hours",
     _CITY = "(?:\\s+(?!(?:Startup|Demo|Summit|Expo|Weekend|Week|Day|Conference|Podcast)\\b)(?-i:[A-Z][a-z]+)){0,2}",
     _ACC_EXTRA = "|\\s+(?:was\\s+)?founded(?:\\s+in\\s+\\d{{4}})?(?:\\s+by\\s+[^.]{{0,80}}?)?,?\\s+(?:(?:both|all)\\s+)?(?:alumni|alums?|graduates)\\s+of\\s+(?:the\\s+)?{prog}\\b|(?:\\s+founded,?)?\\s+(?:joins|enters|graduates from)\\s+(?:the\\s+)?{prog}\\b",
     _YC_CLAIMS = _program(_YC),
     _ACC_CLAIMS = [(name, prog, _program(prog, True)) for (name, prog) in ACCELERATORS],
     _WALL_LABEL_RE = "(?i)(?:>|[\"'])\\s*(?:(?:proudly\\s+)?(?:backed|funded|supported)\\s+by|(?:our\\s+)?investors?(?:\\s+(?:and|&)\\s+partners?)?(?:\\s+logos?)?)\\s*:?\\s*(?:<|[\"'])",
     _WALL_SPAN = 4000,
     _WALL_TEXT = 300,
     _SECTION_END_RE = re.compile("(?i)<h[1-6]\\b|</section>"),
     _OTHER_WALL_RE = "(?i)\\b(?:customers?|clients?|partners?|trusted by|used by|featured in|as seen)\\b";

glob _ROUND = "(pre[\\s-]?seed|seed(?=[\\s-]+(?:round|funding|financing|investment|extension|capital)\\b|\\s*(?:[,.;:)]|$|\\s+(?:led|from|with|in|on|by|to|and)\\b))|series\\s+[a-h](?![\\w-])|bridge(?=\\s+round)|growth(?=\\s+round))",
     _AMOUNT = "([$€£])\\s?(\\d[\\d,]*(?:\\.\\d+)?)\\s?(k|mm|mn|mio|m|bn|b|million|billion|thousand)?(?!\\w)",
     _AMOUNT_WORD = "(\\d[\\d,]*(?:\\.\\d+)?)\\s?(k|mm|mn|mio|m|bn|b|million|billion|thousand)\\s+(euros?|eur|usd|dollars?|gbp|pounds?)\\b",
     _CURRENCY = dict(
         kv.partition(":")[::2]
         for kv in "eur:€ euro:€ euros:€ usd:$ dollar:$ dollars:$ gbp:£ pound:£ pounds:£".split(),
     ),
     _MULTIPLIER = dict(
         zip(
             "k thousand m mm mn mio million b bn billion".split(),
             [1e3, 1e3, 1e6, 1e6, 1e6, 1e6, 1e6, 1e9, 1e9, 1e9],
         ),
     ),
     _ROUND_RANK = {"Pre-seed": 1, "Seed": 2, "Bridge": 3},
     _CLAUSE = "(?:[^.!?]|\\.(?=\\d))",
     _RAISE_VERB = "(?P<verb>raised|raises|closed|closes|secured|secures|landed|lands|completed|completes|announced|announces)",
     _ANNOUNCE = "(?:(?:today,?\\s+)?we(?:['’]re|\\s+are)\\s+(?:\\w+\\s+)?(?:excited|thrilled|proud|happy|delighted|pleased)\\s+to\\s+(?:announce|share)(?:\\s+that)?\\s+)",
     _LEAD_IN = "(?:(?:today|update|news|announcement)\\s*[,:]?\\s+|(?:in|on|back in)\\s+(?:[A-Za-z]+\\.?\\s+)?(?:\\d{1,2}(?:st|nd|rd|th)?,?\\s+)?\\d{4},?\\s+)?",
     _NOT_THEIR_RAISE = "(?i)\\b(?:for|on behalf of|across)\\s+(?:our\\s+|their\\s+|its\\s+)?(?:clients?|customers?|founders?|startups?|companies|portfolio|charity|charities|nonprofits?|members?|users?|causes?|families)\\b|(?<!\\bto )\\bfund\\b(?!\\s+(?:our|the|its|their)\\b)|\\bto invest\\b|\\bthe bar\\b|\\b(?:investment|round|funding|stake)\\s+(?:in|into|for)\\s+(?!our\\b|us\\b)(?-i:[A-Z])|\\bportfolio compan",
     _NOT_FUNDING_MONEY = "(?i)\\b(?:arr|mrr|revenue|sales|bookings|pipeline|contracts?|deals?|orders?|savings|grants?|loans?|mortgages?|verdicts?|settlements?|judgments?|transactions?|projects?|volume|worth|donations?|donated|charity|charities|gala|auction|fundraiser|scholarships?|claims?|recover(?:ed|ies|y)|properties|homes|listings|awards?|for)\\b",
     _FUNDING_EVIDENCE = "(?i)\\b(?:funding|investment|financing|led by|co-led by|investors?|venture|backed by)\\b",
     _CLAUSE_END_RE = "(?i),\\s+(?:and|but|while|then|before|after|since)\\b|;|\\s+and\\s+(?:in|on|then|later)\\b",
     _MONTHS = {
         m: i + 1
         for (i, m) in enumerate("jan feb mar apr may jun jul aug sep oct nov dec".split())
     },
     _MONTH_DATE_RE = "(?i)\\b(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sept?(?:ember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\\.?\\s+(?:(\\d{1,2})(?:st|nd|rd|th)?,?\\s+)?(20\\d{2})\\b",
     _ISO_DATE_RE = "\\b(20\\d{2})-(\\d{2})-(\\d{2})\\b",
     _YEAR_RE = "(?:\\bin\\s+|\\(\\s*)(20\\d{2})\\b",
     _JSONLD_DATE_RE = "\"datePublished\"\\s*:\\s*\"(20\\d{2}-\\d{2}-\\d{2})",
     _META_DATE_RES = (
         "(?i)<meta[^>]+(?:property|name)=[\"'](?:article:published_time|date|pubdate)[\"'][^>]*content=[\"'](20\\d{2}-\\d{2}-\\d{2})",
         "(?i)<meta[^>]+content=[\"'](20\\d{2}-\\d{2}-\\d{2})[^\"']*[\"'][^>]*(?:property|name)=[\"'](?:article:published_time|date|pubdate)[\"']",
     ),
     _TIME_RE = "(?i)<time\\b[^>]*datetime=[\"'](20\\d{2}-\\d{2}-\\d{2})",
     _URL_DATE_RES = ("/(20\\d{2})-(\\d{2})-(\\d{2})(?:[/-]|$)", "/(20\\d{2})/(\\d{2})/"),
     _ARTICLE_PATH_RE = "(?i)/(?:press|news|newsroom|blog|posts?|announc\\w*|stories|updates|articles?|insights)(?:[/-]|$)",
     _ARTICLE_TYPE_RE = "\"@type\"\\s*:\\s*\\[?\\s*\"(?:NewsArticle|BlogPosting|Article|PressRelease|ReportageNewsArticle|TechArticle)\"";

def _folded(cp: int) -> any;

def fold_accents(text: str) -> str;

def nfc(text: str) -> str;

def _is_name_token(token: str) -> bool;

def _name_like(text: str) -> bool;

def _title_chunks(raw_after: str) -> list[str];

def _reads_like_title(text: str) -> bool;

def title_looks_like_role(text: str) -> bool;

def _strip_code(html: str) -> str;

def looks_like_challenge(text: str, status: int = 200) -> bool;

def _text(html: str) -> str;

def _program(prog: str, strict: bool = False) -> dict[str, any];

def _claims(p: dict[str, any], html: str, domain: str) -> list[any];

def _lines(html: str) -> list[str];

def _alnum(text: str) -> str;

def _domain_name(domain: str) -> str;

def _core(t: str) -> str;

def _is_their_yc_page(slug: str, domain: str) -> bool;

def _yc_cohort(sentence: str) -> any;

def _yc_batch(m: any) -> str;

def yc_backed(html: str, domain: str = "") -> tuple[str, float] | None;

def _cohort_shapes(prog: str) -> list[any];

def _acc_cohort(shapes: list[any], sentence: str) -> str | None;

def _on_logo_wall(html: str, prog: str) -> bool;

def accelerators(html: str, domain: str = "") -> list[tuple[str, str, float]];

def _sentence_date(sentence: str) -> str;

def _not_future(when: str) -> str;

def _page_date(html: str, url: str) -> str;

def _amount(symbol: str, number: str, suffix: str) -> str;

def _amount_in(text: str) -> str;

def _round_name(text: str) -> str;

def _raise_rank(c: dict[str, any]) -> tuple[any, ...];

def funding_round(html: str, domain: str = "", url: str = "") -> dict[str, any] | None;

def _claim(m: any, sentence: str) -> dict[str, any] | None;

def _page_title(html: str) -> str;

def _decides(title: str) -> bool;

def _benign(href: str, host: str) -> bool;

obj _Observations {
    has wants: any,
        company_id: str,
        site: str = "",
        rows: list[dict[str, any]] = [];

    def add(code: str, num: any = None, text: str = "", conf: float = 1.0, url: str = "");
}

class ProfileCollector {
    has state: any = None,
        confirmed: set[str] = set(),
        timeout: float = 12.0,
        role_keywords: list[str] = [],
        _client: any = None,
        site_names: dict[str, str] = {},
        challenged: set[str] = set();

    def wants(code: str) -> bool;

    async def __aenter__ -> ProfileCollector;

    async def __aexit__(*exc: any);

    async def _get(url: str) -> str;

    async def _resolve_site(domain: str) -> tuple[str, str];

    async def _first_present(site: str, paths: any) -> tuple[str, str];

    async def _careers_page(site: str, home: str, domain: str) -> tuple[str, str];

    async def _hiring(site: str, home: str, domain: str, add: any);

    async def _search_hit(company_id: str, code: str) -> bool;

    async def _own_hit_page(company_id: str, domain: str, site: str) -> str;

    def detect_agency(html: str, domain: str) -> tuple[str, float, str] | None;

    def detect_tech(html: str) -> list[str];

    static def _any(html: str, patterns: any) -> bool;

    def detect_people(html: str, domain: str = "", site_name: str = "") -> list[dict[str, any]];

    async def profile_company(company_id: str, domain: str) -> list[dict[str, any]];

    async def _improve_name(company: dict[str, any], domain: str);

    async def _mark_checked(company_id: str);

    async def run(companies: list[dict[str, any]], run_id: str = "") -> int;
}

async def profile_companies(
    state: any, companies: list[dict[str, any]], config: any = None
) -> tuple[int, str];
