import asyncio;
import base64;
import builtins;
import logging;
import math;
import re;
import time;
import from dataclasses { asdict, dataclass, field, replace }
import from datetime { date, timedelta }
import from html { unescape }
import from urllib.parse { urlparse }
import httpx;

glob logger = logging.getLogger("sellbird.collectors.discover"),
     TIMEOUT = httpx.Timeout(connect=10.0, read=45.0, write=10.0, pool=10.0),
     _JUNK_SITES = """yelp yellowpages superpages manta bbb angi angieslist homeadvisor thumbtack houzz porch
         buildzoom networx modernize nextdoor facebook instagram twitter x linkedin youtube tiktok pinterest
         meetup eventbrite indeed glassdoor ziprecruiter craigslist zillow realtor mapquest foursquare
         tripadvisor trustpilot birdeye expertise naukri jobrapido jobsora empleos shine foundit timesjobs
         freelancer upwork indiamart justdial tradeindia exportersindia sulekha urbanpro yet5 olx quikr
         flipkart snapdeal myntra shopclues etsy ebay alibaba aliexpress boardgamegeek team-bhp hackaday
         instructables thingiverse printables cults3d thangs grabcad wikipedia reddit quora medium substack
         forbes inc entrepreneur ycombinator workatastartup startupschool yclist ycdb seedtable crunchbase
         techcrunch wellfound angel tracxn pitchbook cbinsights producthunt f6s dealroom growjo owler zoominfo
         techstars antler joinef southparkcommons aigrant a16z pioneer plugandplaytechcenter plugandplay
         prnewswire businesswire globenewswire accesswire einpresswire newswire finsmes axios venturebeat
         siliconangle eu-startups sifted geekwire thesaasnews fortune bloomberg reuters wsj cnbc
         businessinsider privco recentfunding pulse2 startupfundraising startupintros openvc siliconcanals
         startupdaily e27 similarweb vcbacked roundos google bing yahoo duckduckgo amazon apple microsoft""".split(),
     JUNK_DOMAIN_PATTERNS = tuple(
         re.compile(p, re.I)
         for p in (
             r"(^|\.)(" + "|".join(_JUNK_SITES) + r")\.",
             r"(^|\.)(github\.com|tech\.eu|500\.co|neo\.com|(job-)?boards\.(eu\.)?greenhouse\.io|jobs\.(eu\.)?lever\.co|jobs\.ashbyhq\.com|(apply|jobs)\.workable\.com|(jobs|careers)\.smartrecruiters\.com|jobs\.jobvite\.com|ats\.rippling\.com|(myworkdayjobs|applytojob)\.com)$",
             r"(directory|listings?|find-?a-|top\d+|best-?of|hospital|healthsystem|medicalcenter)\.",
             r"(news|magazine|journal|gazette|tribune|herald)\.(com|org|net)$|\.(edu|gov|mil)$|health\.org$",
             r"\.((icims|bamboohr|recruitee|teamtailor)\.com|breezy\.hr|jobs\.personio\.(de|com))$",
             r"^(jobs|careers)\.((co|com|org|net|ac)\.)?[a-z]{2,}$",
             r"(^|\.)(techfundingnews|startups\.gallery)|(wordpress|wix|squarespace|shopify|godaddy|weebly|webflow)\.com$",
         ),
     ),
     JUNK_NAME_PATTERNS = tuple(
         re.compile(p, re.I)
         for p in (
             r"^\s*(top|best|\d+)\s+\d*\s*(best\s+)?\w+.*\b(in|near|of)\b",
             r"\b(directory|listings?|reviews? of|compare|find a)\b",
             r"\b(compan(y|ies)|firms?|contractors?|businesses|providers?)\s+list\b|\blist of\b",
         ),
     ),
     _TITLE_SEPARATORS = re.compile(r"\s+[|\-–—·•]\s+|\s*[|•·]\s*|:\s+"),
     _GENERIC_NAME_WORDS = frozenset(
         """home page welcome official site website hoa hoas management manager managers mgmt mgt company
         companies co inc llc ltd corp firm group services service property properties community communities
         association associations condo condominium residential homeowners owners real estate the and of in for
         best top leading trusted local full arizona phoenix az texas tx florida fl california ca nevada nv
         colorado co georgia ga carolina nc usa us america roofing roof roofers roofer plumbing plumber plumbers
         contact about""".split(),
     ),
     _SPLIT_WORDS = sorted(
         (w for w in _GENERIC_NAME_WORDS | {"with", "your"} if len(w) >= 4), key=len, reverse=True
     ),
     NOMINATIM = "https://nominatim.openstreetmap.org/search",
     GEOCODE_UA = "Sellbird/0.1 (open-source sales agent; github.com/ethanplusai/sellbird)",
     US_STATES = {
         s.split(":")[0]: s.split(":")[1]
         for s in "AL:Alabama,AK:Alaska,AZ:Arizona,AR:Arkansas,CA:California,CO:Colorado,CT:Connecticut,DE:Delaware,DC:District of Columbia,FL:Florida,GA:Georgia,HI:Hawaii,ID:Idaho,IL:Illinois,IN:Indiana,IA:Iowa,KS:Kansas,KY:Kentucky,LA:Louisiana,ME:Maine,MD:Maryland,MA:Massachusetts,MI:Michigan,MN:Minnesota,MS:Mississippi,MO:Missouri,MT:Montana,NE:Nebraska,NV:Nevada,NH:New Hampshire,NJ:New Jersey,NM:New Mexico,NY:New York,NC:North Carolina,ND:North Dakota,OH:Ohio,OK:Oklahoma,OR:Oregon,PA:Pennsylvania,RI:Rhode Island,SC:South Carolina,SD:South Dakota,TN:Tennessee,TX:Texas,UT:Utah,VT:Vermont,VA:Virginia,WA:Washington,WV:West Virginia,WI:Wisconsin,WY:Wyoming".split(
             ","
         )
     },
     _US_STATE_NAMES = {v.lower(): v for v in US_STATES.values()},
     DEFAULT_LOCATION_CODE = 2840,
     _PLACEHOLDER_RE = re.compile(
         r"(?i)(placeholder|change[-_]?me|your[_-](?:api[_-])?key(?:[_-]here)?|paste[_-](?:api[_-])?key(?:[_-]here)?|x{4,}|<[a-z_ -]+>|todo|fixme|example[_-](?:api[_-])?key)",
     ),
     NO_SEARCH_RESULTS = 40102,
     DEFAULT_PROVIDER = "osm",
     FUNDING_LOOKBACK_DAYS = 548,
     _CAREERS_HOST = re.compile(r"^(careers|jobs|join|work|apply|hiring)\.", re.I),
     _SECOND_LEVEL_SUFFIX = set("co com org net ac gov edu ltd plc or ne go".split()),
     RANK_FIELDS = ("rank", "local_pack_rank", "maps_rank"),
     RANK_CODES = ("SERP_RANK", "IN_LOCAL_PACK", "MAPS_RANK"),
     PRESETS = {
         "yc": {
             "label": "YC startups",
             "kinds": ("serp",),
             "term": "\"backed by Y Combinator\" {industry} -site:ycombinator.com -site:workatastartup.com -site:startupschool.org -site:linkedin.com -site:crunchbase.com",
             "local": False,
         },
         "hiring": {
             "label": "Companies hiring for your roles",
             "kinds": ("serp",),
             "term": "\"{role}\" careers {industry} -site:greenhouse.io -site:lever.co -site:ashbyhq.com -site:workable.com -site:smartrecruiters.com -site:jobvite.com -site:icims.com -site:bamboohr.com -site:recruitee.com -site:teamtailor.com -site:personio.de -site:breezy.hr -site:applytojob.com -site:myworkdayjobs.com -site:ats.rippling.com -site:linkedin.com -site:indeed.com -site:glassdoor.com -site:ziprecruiter.com",
             "local": False,
         },
         "accelerator": {
             "label": "Accelerator startups",
             "kinds": ("serp",),
             "terms": (
                 "{industry} (\"backed by Techstars\" OR \"backed by Antler\" OR \"backed by Entrepreneur First\" OR \"backed by South Park Commons\" OR \"backed by 500 Global\") -site:linkedin.com -site:crunchbase.com",
                 "{industry} (\"backed by Neo\" OR \"backed by AI Grant\" OR \"a16z speedrun\" OR \"backed by Plug and Play\") -site:linkedin.com -site:crunchbase.com -site:a16z.com -site:neo.com",
             ),
             "local": False,
         },
         "funding": {
             "label": "Recently funded",
             "kinds": ("serp",),
             "term": "{industry} (\"we raised\" OR \"we've raised\" OR announces OR raises) (\"seed round\" OR \"Series A\" OR \"Series B\") after:{since} -site:techcrunch.com -site:crunchbase.com -site:pitchbook.com -site:linkedin.com -site:prnewswire.com -site:businesswire.com -site:globenewswire.com",
             "local": False,
         },
     };

def normalize_domain(url_or_domain: str) -> str;

def _words(text: str) -> list[str];

def _domain_stem(domain: str) -> str;

def _segment_matches_domain(segment: str, stem: str) -> bool;

def _segment_domain_evidence(segment: str, stem: str) -> int;

def _split_stem(stem: str) -> list[str];

def name_from_domain(domain: str) -> str;

def name_matches_domain(name: str, domain: str) -> bool;

def _named_segments(texts: list[str], stem: str) -> list[str];

def site_name_from_html(html: str, domain: str) -> str;

def business_name(title: str, domain: str) -> str;

def is_junk(domain: str, name: str = "") -> bool;

async def geocode_city(state: any, city: str, radius_km: int = 40, client: any = None) -> str;

async def resolve_coordinates(
    state: any, queries: list[any], radius_km: int = 40, client: any = None
) -> list[any];

@dataclass
class Business {
    has name: str = "",
        domain: str = "",
        website: str = "",
        phone: str = "",
        address: str = "",
        location: str = "",
        category: str = "",
        rating: float | None = None,
        review_count: int | None = None,
        is_claimed: bool | None = None,
        has_website: bool | None = None,
        rank: int | None = None,
        local_pack_rank: int | None = None,
        maps_rank: int | None = None,
        keyword: str = "",
        external_id: str = "",
        alt_ids: tuple[any, ...] = (),
        source_url: str = "",
        provider: str = "",
        raw_title: str = "";

    def identity -> str;
}

@dataclass
class DiscoveryQuery {
    has term: str,
        location: str = "",
        category: str = "",
        coordinate: str = "",
        depth: int = 30,
        limit: int = 100,
        preset: str = "";

    def keyword -> str;
}

def dataforseo_location_name(place: str) -> str;

def _dfs_location(query: DiscoveryQuery, point_suffix: str) -> dict[str, any];

def _missing_value(value: any) -> bool;

def _pages_of(n: int, size: int) -> int;

def _join(sep: str, *parts: any) -> str;

class ProviderExhausted(RuntimeError) {}

class DiscoveryProvider(builtins.object) {
    has key: str = "",
        label: str = "",
        kind: str = "listings",
        blurb: str = "",
        cost_note: str = "",
        free_tier: str = "",
        signup_url: str = "",
        env_keys: tuple[any, ...] = (),
        caveat: str = "",
        needs_coordinates: bool = False,
        rank_codes: tuple[any, ...] = (),
        last_cost: float = 0.0,
        last_error: str = "",
        stop_reason: str = "",
        complete: bool = True,
        remaining_budget: float = math.inf;

    def missing_keys(env: dict[str, any]) -> list[str];

    def configured(env: dict[str, any]) -> bool;

    def estimate(queries: list[DiscoveryQuery]) -> float;

    async def fetch(client: any, env: dict[str, any], query: DiscoveryQuery) -> list[Business];

    def _hit(title: any, url: str, domain: str, query: DiscoveryQuery, **extra: any) -> Business;
}

class _DataForSEO(DiscoveryProvider) {
    has needs_coordinates: bool = True,
        signup_url: str = "https://app.dataforseo.com/api-access",
        env_keys: tuple[any, ...] = ("dataforseo_login", "dataforseo_password");

    def _auth(env: dict[str, any]) -> str;

    def base_url(env: dict[str, any]) -> str;

    async def _post(
        client: any, env: dict[str, any], endpoint: str, task: dict[str, any]
    ) -> list[any];
}

class DataForSEOListings(_DataForSEO) {
    has key: str = "dataforseo_listings",
        label: str = "DataForSEO Business Listings",
        blurb: str = "Enumerate every business of a type within a radius, with phone, domain, rating and whether the listing is claimed. Best choice for local trades, clinics and contractors.",
        cost_note: str = "$0.372 per 1,000 businesses ($0.012/query + $0.00036 each)",
        free_tier: str = "$1 signup credit; $50 minimum deposit to go live",
        caveat: str = "No email addresses — Sellbird resolves those in a later stage.",
        TASK_COST: float = 0.012,
        ITEM_COST: float = 0.00036;

    def estimate(queries: list[DiscoveryQuery]) -> float;

    async def fetch(client: any, env: dict[str, any], query: DiscoveryQuery) -> list[Business];
}

class DataForSEOSerp(_DataForSEO) {
    has key: str = "dataforseo_serp",
        label: str = "DataForSEO SERP (organic rank)",
        kind: str = "serp",
        blurb: str = "Search '<service> <city>' from the city centre and record where each business ranks, plus who holds the local 3-pack. Discovers businesses you didn't have AND scores the ones you did.",
        cost_note: str = "$0.002 per 10 results (Live) — depth 30 costs $0.006 a search",
        free_tier: str = "$1 signup credit; free sandbox; $50 minimum deposit to go live",
        caveat: str = "Google removed 100-results-per-page in September 2025, so depth 100 now costs 10x depth 10. Depth 20-30 is the sweet spot; below rank 30 it is mostly directories anyway. Rank depends on where the searcher stands — this is the view from the city centre.",
        PAGE_COST: float = 0.002,
        POINT_RADIUS: str = "2000",
        rank_codes: tuple[any, ...] = ("SERP_RANK", "IN_LOCAL_PACK");

    def estimate(queries: list[DiscoveryQuery]) -> float;

    async def fetch(client: any, env: dict[str, any], query: DiscoveryQuery) -> list[Business];
}

class DataForSEOMaps(DataForSEOSerp) {
    has key: str = "dataforseo_maps",
        label: str = "DataForSEO Google Maps (map rank)",
        blurb: str = "Search Google Maps for '<service> <city>' and record each business's map position, rating, category and claimed status — including businesses with no website at all.",
        cost_note: str = "$0.002 per search of up to 100 results (Live)",
        caveat: str = "Map rank depends heavily on where the searcher stands; Sellbird searches from the city centre at city zoom. Treat it as 'when we searched from downtown', not an absolute position.",
        SERP_COST: float = 0.002,
        rank_codes: tuple[any, ...] = ("MAPS_RANK",),
        ZOOM: str = "12z";

    def estimate(queries: list[DiscoveryQuery]) -> float;

    async def fetch(client: any, env: dict[str, any], query: DiscoveryQuery) -> list[Business];
}

def _gbp_business(item: dict[str, any], provider: str) -> Business;

def _best(current: int | None, new: any) -> int | None;

class Serper(DiscoveryProvider) {
    has key: str = "serper",
        label: str = "Serper",
        kind: str = "serp",
        rank_codes: tuple[any, ...] = ("SERP_RANK",),
        blurb: str = "Fast Google search with rank positions. The easiest one to try: 2,500 free queries, no credit card, one API key.",
        cost_note: str = "~$0.30-$1.00 per 1,000 searches depending on plan",
        free_tier: str = "2,500 queries free, no card required",
        signup_url: str = "https://serper.dev",
        env_keys: tuple[any, ...] = ("serper_api_key",),
        caveat: str = "Returns at most 10 results per query, including when a greater depth is requested.";

    def estimate(queries: list[DiscoveryQuery]) -> float;

    async def fetch(client: any, env: dict[str, any], query: DiscoveryQuery) -> list[Business];
}

class TinyFish(DiscoveryProvider) {
    has key: str = "tinyfish",
        label: str = "TinyFish",
        kind: str = "serp",
        blurb: str = "Free web search with a key. Finds businesses by phrase; it records no search rank, since its ordering isn't Google's.",
        cost_note: str = "free",
        free_tier: str = "free with a key, no card: 30 searches a minute, 500 an hour",
        signup_url: str = "https://agent.tinyfish.ai/api-keys",
        env_keys: tuple[any, ...] = ("tinyfish_api_key",),
        caveat: str = "Needs TINYFISH_API_KEY in .env. Sellbird paces itself to 30 searches a minute; a depth-30 phrase is 3 searches, so about 160 phrases an hour fit in the 500. No SERP_RANK: use Serper or DataForSEO SERP for rank signals.",
        ENDPOINT: str = "https://api.search.tinyfish.ai",
        MIN_INTERVAL: float = 2.1,
        HOURLY_LIMIT: int = 490,
        _last_call: float = 0.0,
        _calls: list[any] = [],
        _lock: any = None;

    async def _pace;

    async def _get(client: any, headers: dict[str, any], params: dict[str, any]) -> any;

    async def fetch(client: any, env: dict[str, any], query: DiscoveryQuery) -> list[Business];
}

class OpenStreetMap(DiscoveryProvider) {
    has key: str = "osm",
        label: str = "OpenStreetMap (Overpass)",
        needs_coordinates: bool = True,
        blurb: str = "Free public map data. No signup, no key, no card. Try the whole pipeline for nothing before you pay anyone.",
        cost_note: str = "free",
        free_tier: str = "unlimited, within community rate etiquette",
        signup_url: str = "https://www.openstreetmap.org",
        caveat: str = "Coverage is thin for any trade without a storefront — OSM maps premises, so it holds under 2,000 roofers for the entire US. Great for a free trial run or as a cross-reference; not a complete list.",
        ENDPOINTS: tuple[any, ...] = (
            "https://overpass-api.de/api/interpreter",
            "https://overpass.kumi.systems/api/interpreter",
        ),
        MIN_INTERVAL: float = 2.0,
        BACKOFF: float = 5.0,
        HTTP_TIMEOUT: any = httpx.Timeout(connect=10.0, read=120.0, write=10.0, pool=10.0),
        SERVER_TIMEOUT: int = 90,
        RETRY_STATUSES: any = frozenset({429, 500, 502, 503, 504}),
        TAG_MAP: dict[str, any] = {
            e.split(":")[0]: e.split(":")[1].split()
            for e in "roof:craft=roofer shop=roofing|plumb:craft=plumber|hvac:craft=hvac|electric:craft=electrician|dentist:amenity=dentist|lawyer:office=lawyer|attorney:office=lawyer|contractor:craft=builder office=construction_company|landscap:craft=gardener shop=garden_centre|ferreter:shop=hardware shop=doityourself|supermercado:shop=supermarket|abasto:shop=convenience shop=supermarket|distribuidora:shop=wholesale|al mayor:shop=wholesale|por mayor:shop=wholesale|mayorista:shop=wholesale|contad:office=accountant|contable:office=accountant|farmacia:amenity=pharmacy|repuesto:shop=car_parts|electrodom:shop=electronics shop=appliance|tienda de ropa:shop=clothes|panader:shop=bakery|clinica:amenity=clinic|clínica:amenity=clinic".split(
                "|"
            )
        };

    def _tags(term: str) -> list[str];

    async def fetch(client: any, env: dict[str, any], query: DiscoveryQuery) -> list[Business];
}

class ScavioProvider(DiscoveryProvider) {
    has signup_url: str = "https://scavio.dev",
        env_keys: tuple[any, ...] = ("scavio_api_key",),
        free_tier: str = "50 credits on signup, no card",
        API: str = "https://api.scavio.dev/api/v2/google",
        CREDIT_PRICE: float = 0.01,
        MIN_INTERVAL: float = 1.05,
        _last_call: float = 0.0;

    async def _post(
        client: any, env: dict[str, any], path: str, body: dict[str, any]
    ) -> dict[str, any];

    async def _pages(
        client: any,
        env: dict[str, any],
        query: DiscoveryQuery,
        path: str,
        body: any,
        results_key: str,
        page_size: int,
        pages: int,
    ) -> list[tuple[any, ...]];

    def _last_page(data: dict[str, any], items: list[any], page_size: int) -> bool;
}

def _is_count(value: any) -> bool;

def _check_scavio_item(item: dict[str, any]);

class ScavioMaps(ScavioProvider) {
    has key: str = "scavio_maps",
        needs_coordinates: bool = True,
        label: str = "Scavio Google Maps",
        kind: str = "listings",
        blurb: str = "Google Maps results around each city: phone, website, category, rating and review count for every place. Up to 120 businesses per search.",
        cost_note: str = "1 credit per page (up to 20 listings); estimates use $0.01/credit",
        caveat: str = "Google Maps does not say whether a listing is claimed, so the unclaimed-listing signal stays empty. Same key as Scavio Google Search.",
        PAGE_SIZE: int = 20,
        MAX_PAGES: int = 6;

    def _page_count(query: DiscoveryQuery) -> int;

    def estimate(queries: list[DiscoveryQuery]) -> float;

    static def map_center(coordinate: str) -> str;

    async def fetch(client: any, env: dict[str, any], query: DiscoveryQuery) -> list[Business];
}

class ScavioSearch(ScavioProvider) {
    has key: str = "scavio_search",
        rank_codes: tuple[any, ...] = ("SERP_RANK",),
        label: str = "Scavio Google Search",
        kind: str = "serp",
        blurb: str = "Google organic results with rank positions. One Scavio key covers this and Google Maps listings.",
        cost_note: str = "1 credit per page (up to 10 results); depth 30 estimated at $0.03",
        caveat: str = "Results come from google.com in English (US) unless the search names another place. Depth 20-30 is the sweet spot.",
        PAGE_SIZE: int = 10;

    def estimate(queries: list[DiscoveryQuery]) -> float;

    def _last_page(data: dict[str, any], items: list[any], page_size: int) -> bool;

    async def fetch(client: any, env: dict[str, any], query: DiscoveryQuery) -> list[Business];
}

glob PROVIDERS: dict[str, any];

with entry {
    PROVIDERS = {
        p.key: p
        for p in (
            OpenStreetMap(),
            TinyFish(),
            DataForSEOListings(),
            DataForSEOSerp(),
            DataForSEOMaps(),
            Serper(),
            ScavioMaps(),
            ScavioSearch(),
        )
    };
}

def _dfs_items(payload: dict[str, any]) -> list[any];

@dataclass
class DiscoveryReport {
    has provider: str = "",
        queries: int = 0,
        queries_ran: int = 0,
        queries_succeeded: int = 0,
        estimated_cost: float = 0.0,
        actual_cost: float = 0.0,
        found: int = 0,
        junk: int = 0,
        excluded: int = 0,
        new_companies: int = 0,
        known_companies: int = 0,
        observations: int = 0,
        run_id: str = "",
        errors: list[str] = field(default_factory=list[any]),
        stopped: str = "";

    def as_dict -> dict[str, any];
}

def preset_templates(spec: dict[str, any]) -> tuple[any, ...];

def company_host(domain: str) -> str;

def _wants_role(spec: dict[str, any]) -> bool;

def preset_problem(preset: str, provider_key: str, config: any = None) -> str | None;

def build_queries(
    config: any,
    cities: list[str] | None = None,
    depth: int = 30,
    limit: int = 100,
    preset: str = "",
) -> list[DiscoveryQuery];

def estimate_cost(provider_key: str, queries: list[DiscoveryQuery]) -> float;

obj _Run {
    has state: any,
        rep: DiscoveryReport,
        confirmed: set[str],
        dnc: any,
        company_ids: dict[str, str] = {},
        best_ranks: dict[tuple[any, ...], tuple[any, ...]] = {},
        ranked: dict[tuple[any, ...], set[str]] = {};

    async def record(provider: any, query: DiscoveryQuery, found: list[Business]);
    async def take(biz: Business, query: DiscoveryQuery) -> list[dict[str, any]];
}

def _refusal(rep: DiscoveryReport, error: str, stopped: str) -> DiscoveryReport;

async def run_discovery(
    state: any,
    config: any,
    provider_key: str = DEFAULT_PROVIDER,
    queries: list[DiscoveryQuery] | None = None,
    max_spend: float = 1.0,
    dry_run: bool = False,
) -> DiscoveryReport;

async def _upsert(state: any, biz: Business, query: DiscoveryQuery) -> tuple[any, ...];

def _row(
    company_id: str, code: str, num: any, text: str, conf: float, url: str, run_id: str
) -> dict[str, any];

def _num(value: any) -> float | None;

def _observations(
    biz: Business,
    company_id: str,
    confirmed: set[str],
    run_id: str,
    query: DiscoveryQuery | None = None,
    ranks_only: bool = False,
) -> list[dict[str, any]];

def provider_menu(env: dict[str, any] | None = None) -> list[dict[str, any]];
