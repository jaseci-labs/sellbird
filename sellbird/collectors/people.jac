import html as html_lib;
import json;
import re;
import from urllib.parse { unquote, urljoin, urlparse }

glob COMMON_WORDS = frozenset(
         ("a an and or the of for to in on at by with from our your my we us you me it is are "
             "team teams expert experts people person member members staff crew leadership leader "
             "leaders meet welcome hello hi thanks thank family owned operated local trusted "
             "professional professionals certified licensed insured quality best top great good "
             "read more less view see all learn know about contact call book schedule now today "
             "here there this that these those who what why how where when story mission vision "
             "values culture history office offices hours open closed home page blog news events "
             "press media careers jobs join apply portal login sign account cart shop store "
             "founder founders owner owners president partners partner principal director manager "
             "managers doctor doctors dentist dentists attorney attorneys lawyer lawyers dr mr "
             "mrs ms miss sir madam associates associate secret sauce happy smile smiles proud "
             "since years year experience care patient patients client clients customer customers "
             "testimonial testimonials review reviews award awards realty realtors consulting "
             "consultants capital ventures holdings enterprises industries technologies "
             "technology media studio studios labs agency digital creative analytics software "
             "sports medicine fitness salon spa dental medical clinic insurance financial "
             "properties inc llc pllc ltd corp co coach pastor father mother judge mayor senator "
             "governor captain sergeant sheriff officer uncle aunt grandpa grandma mom dad memory "
             "memoriam late former notre nos votre vos nous vous leur leurs et ou avec pour par "
             "chez dans qui que accueil equipe equipes propos joindre contactez contacter "
             "rejoignez rencontrez decouvrez voir lire plus savoir demande demandez obtenez "
             "gratuit gratuite bienvenue merci histoire mission valeurs carriere carrieres emploi "
             "emplois blogue nouvelles evenements politique confidentialite connexion compte "
             "panier boutique magasin direction dirigeants personnel employes membre membres "
             "fondateur fondatrice fondateurs proprietaire proprietaires president presidente "
             "directeur directrice general generale gerant gerante associe associee associes "
             "technicien technicienne techniciens adjoint adjointe responsable gestionnaire "
             "conseiller conseillere annee annees experience clients clientele famille familiale "
             "familial depuis secteur secteurs francais anglais pourquoi choisir avis prix "
             "service services").split(),
     ),
     _PARTICLES = frozenset("van von de der den del della di da la le du dos das st".split()),
     _HONORIFIC = "(?i)^(?:(?:dre?|mr|mrs|ms|miss|prof|rev|hon|mme|mlle|me)\\.?|m\\.)\\s+",
     _CREDENTIAL_TAIL = "(?i)(?:\\s*,?\\s+(?:dds|dmd|md|do|dvm|od|phd|jd|esq|cpa|pe|ra|rn|np|pa|mba|ms|ma|facs|fagd|ccc-slp|jr|sr|ii|iii|iv)\\.?)+\\s*$",
     _NAME_TOKEN = "^[A-Z][a-z]+(?:[-'’][A-Z]?[a-z]+)*\\.?$|^[A-Z]\\.$|^[A-Z]$",
     _OWNER_FAMILY = ("owner|co-owner|founder|co-founder|cofounder|president|ceo|chief executive|"
         "chief executive officer|principal|proprietor|managing partner|founding partner|"
         "managing member|owner/operator|owner-operator|proprietaire|coproprietaire|co-proprietaire|"
         "pdg|p.-d.g.|p.d.g.|president-directeur general|fondateur|cofondateur|co-fondateur|"
         "directeur general|associe").split("|"),
     _FEMININE = dict(
         pair.partition(":")[::2]
         for pair in ("presidente:president directrice:directeur fondatrice:fondateur "
             "cofondatrice:cofondateur associee:associe generale:general adjointe:adjoint "
             "gerante:gerant coordonnatrice:coordonnateur coordinatrice:coordinateur "
             "conseillere:conseiller representante:representant technicienne:technicien "
             "estimatrice:estimateur ingenieure:ingenieur contremaitresse:contremaitre "
             "vendeuse:vendeur commerciale:commercial administratrice:administrateur "
             "superviseure:superviseur chargee:charge principale:principal controleuse:controleur "
             "mecanicienne:mecanicien installatrice:installateur repartitrice:repartiteur "
             "proprietaires:proprietaire").split(),
     ),
     _OWNER_FAMILY_KEYS = frozenset(_family_key(t) for t in _OWNER_FAMILY) | {"partner"},
     _OWNER_TITLE = "(?i)\\b(?:co-?owner|owner|co-?founder|founder|proprietor|ceo|chief executive(?: officer)?|president|managing (?:partner|member)|founding (?:partner|attorney|dentist|doctor)|principal(?! (?:designer|engineer|consultant|architect|associate|scientist|developer))|co-?proprietaire|proprietaire|presidente?|pdg|p\\.-?d\\.g|co-?fondat(?:eur|rice)|fondat(?:eur|rice)|direct(?:eur|rice) generale?)\\b",
     _SUBORDINATE = "(?i)\\b(?:vice[- ]presidente?|vp|svp|evp|assistant(?: to)?|executive assistant|to the|deputy|associate|aide|assistante?s?|adjointe?s?|sous-\\w+)\\b",
     _PARTNER_ONLY = "(?i)^(?:senior |founding |managing |name |equity )?partner\\b|^associee?s?(?:\\s+(?:principale?|direct(?:eur|rice)|fondat(?:eur|rice)|majoritaire|gerante?))?(?!\\s*(?:aux?|a la|en|-))\\b",
     _FORMER = "(?i)\\b(?:former|formerly|past|retired|late|emerit(?:us|a)|deceased|in memory|memoriam|ex-|one-time|onetime|ancien(?:ne)?s?|retraitee?s?|defunte?|emerite|en memoire)\\b|\\b(?:1[89]|20)\\d{2}\\s*[-–—]\\s*(?:1[89]|20)\\d{2}\\b";

glob _GENERIC_BUSINESS_WORDS = frozenset(
         ("the and of a an inc llc pllc plc pc ltd co corp company group firm law legal office "
             "offices practice dental dentistry family roofing roof roofers heating cooling hvac "
             "air plumbing electric services service solutions marketing agency media digital "
             "creative studio studios design partners associates construction contractors "
             "contracting home homes repair center clinic health care analytics software labs").split(),
     ),
     _FR_ROLE = "co-?proprietaire|proprietaire|presidente?|pdg|co-?fondat(?:eur|rice)|fondat(?:eur|rice)|directeur|directrice|associee?",
     _TITLE_ORG = f"(?i:\\b(?:owner|founder|co-?founder|ceo|cto|coo|cmo|president|principal|partner|director|{_FR_ROLE})\\b(?:\\s*(?:,|&|and|et)\\s*\\w+)*?\\s*(?:,|\\bat\\b|\\bof\\b|\\bchez\\b|\\bde\\b|\\bdu\\b|@|\\s))\\s*((?:the\\s+|la\\s+|le\\s+|l['’])?[A-Z][\\w&.'’-]*(?:\\s+(?:[A-Z][\\w&.'’-]*|&|and|of|de|des|du))*)",
     _FR_TITLE_WORDS = f"(?:(?:et|and)\\s+)?(?:{_FR_ROLE}|generale?|executi(?:f|ve)|principale?)(?:[\\s-]+(?:{_FR_ROLE}|generale?|executi(?:f|ve)|principale?|et))*",
     _QUOTED_CLASS = "(?is)<(\\w+)\\b[^>]*\\bclass\\s*=\\s*[\"'][^\"']*\\b(?:testimonials?|reviews?|tweets?|quotes?|blockquote|client-say|customer-say|endorsements?|temoignages?|avis)\\b[^\"']*[\"'][^>]*>",
     _STATUS_LINK = "(?is)<a\\b[^>]*href\\s*=\\s*[\"'][^\"']*(?:twitter|x)\\.com/[^\"']*/status/[^\"']*[\"'][^>]*>.*?</a>",
     _VOID_TAGS = frozenset(
         "img input br hr meta link source area col embed wbr track param".split()
     ),
     MAX_QUOTE_CHARS = 8000,
     MAX_QUOTES = 200,
     _LINE_BREAK = "(?i)<(?:/?(?:p|div|li|ul|ol|h[1-6]|section|article|header|footer|nav|td|tr|table|blockquote|figcaption|dt|dd|span|a|strong|b|em|label|button)\\b[^>]*|br\\s*/?)>",
     _QUOTE_LINE = "^\\s*[\\\"“‘'«]|[\\\"”’»]\\s*$|[★⭐]",
     _SEPARATED = "^(?P<name>(?:[^,|–—\\-]|(?<=\\w)-(?=\\w)){4,45}?)\\s*(?:,|\\||–|—|\\s-\\s)\\s*(?P<title>.{2,80})$",
     _STRONG_ROLE = "(?i)\\b(?:owner|co-?owner|founder|co-?founder|president|ceo|cfo|coo|cto|cmo|cro|chief|principal|partner|proprietor|director|manager|attorney|lawyer|dds|dmd|md|esq|cpa|dentist|orthodontist|officer|head of|vp|vice president|superintendent|estimator|administrator|co-?proprietaire|proprietaire|presidente?|pdg|co-?fondat(?:eur|rice)|fondat(?:eur|rice)|directeur|directrice|gerante?|associee?|vice-presidente?|estimat(?:eur|rice)|contremaitre|superviseure?|comptable|ingenieure?)\\b",
     _ORG_KEYS = dict(
         kv.partition(":")[::2]
         for kv in "founder:Founder founders:Founder employee: employees: member: members: owner:Owner".split(),
     ),
     _NOT_STAFF_TYPES = frozenset(
         "person article blogposting newsarticle webpage website imageobject breadcrumblist review".split(),
     );

glob _CAP = "[A-Z][a-z]+(?:[-'’][A-Z]?[a-z]+)*",
     _NAME_RE = f"(?:Dre?\\.?\\s+)?(?P<name>{_CAP}(?:\\s+[A-Z]\\.)?(?:\\s+(?:{'|'.join(sorted(_PARTICLES))}))*\\s+{_CAP}(?:\\s+{_CAP})?)",
     _OWNER_WORD = "(?P<title>(?i:co-?owner|owner|co-?founder|founder|proprietor|president|ceo|principal|managing partner|founding partner|founding attorney|partners?))",
     _ADJ = "(?:(?:our|the|its|current|proud|longtime|second[- ]generation|third[- ]generation|original|today'?s?|new)\\s+)*",
     _FR_HON = "(?:(?:M\\.|Mme\\.?|Mlle\\.?|Me|Dre?\\.?)\\s+|(?i:monsieur|madame)\\s+)?",
     _FR_ONE = "(?:co-?proprietaires?|proprietaires?|co-?fondat(?:eur|rice)s?|fondat(?:eur|rice)s?|presidente?(?:[- ]direct(?:eur|rice)[- ]generale?)?|pdg|p\\.-?d\\.g\\.?|direct(?:eur|rice)\\s+generale?)",
     _FR_OWNER_WORD = f"(?P<title>(?i:{_FR_ONE}(?:\\s+(?:et|&)\\s+{_FR_ONE})?))",
     _FR_ORG_NOUN = "(?:entreprise|compagnie|societe|agence|firme|cabinet|clinique|commerce)",
     _PROSE = tuple(
         zip(
             [
                 re.compile(p)
                 for p in (
                     f"(?i:\\b(?:founded|started|established|launched|opened|created)\\s+(?:in\\s+\\d{{4}}\\s+)?by)\\s+(?:(?i:attorney|dentist|our\\s+founder|owner|president)\\s+)?{_NAME_RE}",
                     f"(?i:\\b(?:owned\\s+and\\s+operated|owned|operated)\\s+(?:today\\s+)?by)\\s+(?!(?i:president|owner|ceo|founder)\\b){_NAME_RE}",
                     f"(?i:\\b(?:by|with|as|our|its|current|proud|longtime|(?:second|third|fourth)[- ]generation|today'?s)\\s+{_ADJ}){_OWNER_WORD}\\s+{_NAME_RE}",
                     f"(?i:\\b(?:our|the\\s+company'?s|its)\\s+){_OWNER_WORD},\\s+{_NAME_RE}",
                     f"{_NAME_RE}\\s*,\\s*(?i:{_ADJ}){_OWNER_WORD}\\b(?P<tail>.{{0,40}})",
                     f"{_NAME_RE}\\s+(?i:co-?founded|founded|started|launched|established|opened)\\s+(?P<org>(?i:the\\s+(?:company|business|firm|practice|agency))|[A-Z][\\w&'’.-]*(?:\\s+(?:[A-Z][\\w&'’.-]*|&))*)",
                     f"(?i:\\b(?:the\\s+)?(?:office|practice|clinic)\\s+of)\\s+Dr\\.?\\s+{_NAME_RE}",
                     f"(?i:\\b(?:fondee?s?|creee?s?|lancee?s?|demarree?s?|mise?s?\\s+sur\\s+pied|etablie?s?)\\s+(?:en\\s+\\d{{4}}\\s+)?par)\\s+(?:(?i:(?:son|sa|notre|leur|le|la)\\s+(?:fondat(?:eur|rice)|proprietaire|presidente?))\\s*,?\\s+)?{_FR_HON}{_NAME_RE}",
                     f"(?i:\\b(?:(?:detenue?s?|exploitee?s?|operee?s?)(?:\\s+(?:aujourd'hui|depuis\\s+\\d{{4}}|fierement))?\\s+par|appartient\\s+a|propriete\\s+de))\\s+(?!(?i:(?:le|la|les|son|sa|notre)\\s|presidente?\\b|proprietaire\\b|pdg\\b|fondat)){_FR_HON}{_NAME_RE}",
                     f"(?i:\\b(?:par|avec|notre|nos|son|sa|ses|leur|leurs)\\s+(?:(?:le|la|les)\\s+|l['’])?(?:(?:nouveau|nouvelle|actuel(?:le)?|fier|fiere|jeune)\\s+)?){_FR_OWNER_WORD}(?i:\\s+(?:actuel(?:le)?|fondat(?:eur|rice)))?\\s*,?\\s+{_FR_HON}{_NAME_RE}",
                     f"{_FR_HON}{_NAME_RE}\\s*,\\s*(?i:(?:(?:le|la|notre|son|sa)\\s+|l['’])?(?:(?:nouveau|nouvelle|fier|fiere|actuel(?:le)?)\\s+)?){_FR_OWNER_WORD}\\b(?P<tail>.{{0,40}})",
                     f"{_FR_HON}{_NAME_RE}\\s+(?i:est\\s+(?:(?:le|la|notre|son|sa|fier|fiere)\\s+|l['’])?(?:(?:nouveau|nouvelle|actuel(?:le)?)\\s+)?){_FR_OWNER_WORD}\\b(?P<tail>.{{0,40}})",
                     f"{_FR_HON}{_NAME_RE}\\s+(?i:a\\s+)?(?i:co-?fonde|fonde|demarre|lance|cree|mis\\s+sur\\s+pied)\\s+(?P<org>(?i:(?:l['’]|la\\s+|son\\s+|sa\\s+){_FR_ORG_NOUN})|[A-Z][\\w&'’.-]*(?:\\s+(?:[A-Z][\\w&'’.-]*|&))*)",
                 )
             ],
             "Founder,Owner,,,,Founder,Owner,Founder,Owner,,,,Founder".split(","),
         ),
     ),
     _FIRST_PERSON = "(?i)\\bI\\s+(?:founded|started|opened|own|established|launched)\\b|\\bj['’]ai\\s+(?:co-?)?(?:fonde|demarre|ouvert|lance|cree|mis\\s+sur\\s+pied)\\b|\\bje\\s+suis\\s+(?:le\\s+|la\\s+|l['’])?(?:co-?)?(?:proprietaire|fondat(?:eur|rice)|presidente?)\\b",
     _FIRST_NAME_FOUNDER = f"\\b(?P<first>{_CAP})\\s+(?i:co-?founded|founded|started|launched|established|opened|(?:a\\s+)?(?:co-?fonde|fonde|demarre|lance|mis\\s+sur\\s+pied))\\s+(?P<org>(?:the\\s+|la\\s+|le\\s+|l['’])?[A-Z][\\w&'’.-]*(?:\\s+(?:[A-Z][\\w&'’.-]*|&))*)",
     _ROLE_ONLY = f"(?i)(?:(?:and|et)\\s+)?(?:ceo|cfo|coo|cto|cmo|president|owner|founder|co-?founder|principal|partner|chief\\s+\\w+(?:\\s+officer)?|general manager|{_FR_ROLE}|direct(?:eur|rice)\\s+generale?)",
     _DEPARTED = "(?:passed away|died|retired|was laid to rest|is missed|rest in peace|decedee?|nous a quittee?s?|s['’]est eteinte?|a pris sa retraite|repose en paix)",
     _FRENCH_TITLE = "(?i)^(?:co-?)?(?:proprietaire|fondat|directeur|directrice|presidente|pdg|p\\.-?d\\.g)|^president[- ]+(?:direct|et\\b)";

glob _LINK_WEIGHTS = tuple(
         zip(
             (3, 2, 1),
             (
                 "team|meet|leadership|staff|people|doctors?|dentists?|attorneys?|lawyers?|physicians?|providers?|owners?|founders?|principals?|partners|who-?we-?are|bios?|equipe|direction|dirigeants|personnel|proprietaires?|fondat(?:eurs?|rices?)|qui[- ]sommes[- ]nous|rencontrez[- ]\\w+",
                 "about|story|history|company|firm|practice|family|a[- ]propos|apropos|histoire|entreprise|compagnie|famille",
                 "contact|nous[- ]joindre|joindre|coordonnees",
             ),
         ),
     ),
     _LD_JSON = "(?is)<script[^>]+application/ld\\+json[^>]*>(.*?)</script>",
     _ORG_AFTER = "^(?:(?:of|at|chez|de|du|des)\\s+|d['’]|@\\s*)?((?:the\\s+|la\\s+|le\\s+|l['’])?[A-Z][\\w&'’.-]*(?:\\s+[A-Z][\\w&'’.-]*)*)",
     _SKIP_LINK = "(?i)\\.(?:pdf|jpe?g|png|gif|webp|svg|zip|docx?|mp4|mp3)(?:$|\\?)|/(?:blog|blogue|news|nouvelles|posts?|articles?|category|tag|author|feed|wp-json|cart|checkout|login|account|careers?|jobs?)/|/\\d{4}/\\d{2}/|[?&](?:replytocom|share)=|/:param",
     EMAIL_RE = re.compile(
         "(?<![a-z0-9._%+\\-])[a-z0-9][a-z0-9._%+\\-]{0,63}@[a-z0-9](?:[a-z0-9\\-]{0,61}[a-z0-9])?(?:\\.[a-z0-9](?:[a-z0-9\\-]{0,61}[a-z0-9])?){0,6}\\.[a-z]{2,24}(?![a-z0-9\\-])",
         re.I,
     ),
     _JUNK_DOMAINS = tuple(
         ("example.com example.org domain.com email.com yourdomain.com mail.com sentry.io "
             "wixpress.com sentry-next.wixpress.com yoursite.com website.com company.com test.com").split(),
     ),
     _JUNK_TLDS = tuple(".png .jpg .jpeg .gif .webp .svg .js .css".split()),
     _AT_DOT = "(?i)(?<![a-z0-9._%+\\-])([a-z0-9][a-z0-9._%+\\-]{0,63})\\s{0,3}(?:\\[\\s{0,3}at\\s{0,3}\\]|\\(\\s{0,3}at\\s{0,3}\\)|\\{\\s{0,3}at\\s{0,3}\\})\\s{0,3}([a-z0-9\\-]{1,63}(?:\\s{0,3}(?:\\[\\s{0,3}dot\\s{0,3}\\]|\\(\\s{0,3}dot\\s{0,3}\\)|\\{\\s{0,3}dot\\s{0,3}\\}|\\.)\\s{0,3}[a-z0-9\\-]{1,63}){1,4})",
     _KNOWN_TLDS = frozenset(
         ("com net org edu gov io co us biz info me ca uk au nz ie de fr es it nl be ch at se no "
             "dk fi pl pt mx br in ai app dev law legal dental agency marketing design studio "
             "tech solutions services company group pro health care clinic roofing law").split(),
     ),
     _DATA_PAIR_LOCAL = ("data-user", "data-front", "data-mailbox"),
     _DATA_PAIR_DOMAIN = ("data-domain", "data-back"),
     MAX_PAGE_CHARS = 1500000;

glob _GRAPH_KEYS = "@graph mainEntity about publisher provider brand parentOrganization".split();

obj _Found {
    has people: list[dict[str, any]] = [],
        seen: set[any] = set();

    def add(split: any, title: str, source: str, ev: str, url: str, full: str, owner: bool = False);
}

def _word_ok(token: str) -> bool;
def split_person_name(text: str) -> tuple[str, str] | None;
def is_person_name(text: str) -> bool;
def _norm_title(text: str) -> str;
def _family_key(text: str) -> str;
def is_owner_title(title: str) -> bool;
def _clean_for_target(title: str, target: str) -> str;
def title_matches(title: str, targets: any, owner: bool = False) -> bool;
def owner_rank(title: str, owner: bool = False) -> int;
def _alnum(text: str) -> str;
def _domain_label(domain: str) -> str;
def names_business(text: str, domain: str, site_name: str = "") -> bool;
def surname_on_the_door(last_name: str, domain: str, site_name: str = "") -> bool;
def title_names_other_org(title: str, domain: str, site_name: str = "") -> bool;
def _close_of(html: str, start: int, tag: str) -> int;
def drop_quoted(html: str) -> str;
def page_lines(html: str) -> list[str];
def _sentences(html: str) -> list[str];
def people_from_lines(html: str, domain: str = "", site_name: str = "", url: str = "") -> list[any];
def _nodes(data: any) -> list[any];
def _as_list(value: any) -> list[any];
def _types(item: any) -> list[str];
def people_from_schema(html: str, url: str = "") -> list[any];
def _departed(person: dict[str, any], text: str) -> bool;
def _title_word(word: str) -> str;
def _prose_match(
    m: any, sentence: str, folded: str, fixed: str, domain: str, site_name: str
) -> any;
def people_from_prose(html: str, domain: str, site_name: str = "", url: str = "") -> list[any];
def _merge(merged: dict[any, any], p: dict[str, any]);
def _founded_by_history(p: dict[str, any]) -> bool;
def find_people(pages: list[tuple[str, str]], domain: str, site_name: str = "") -> list[any];
def _norm_url(url: str) -> str;
def _link_score(segments: list[any], label: str) -> int;
def menu_links(html: str, page_url: str, limit: int = 5) -> list[str];
def _cf_decode(hexstr: str) -> str;
def _clean_address(addr: str) -> str;
def _data_pair(raw_tag: str) -> str;
def emails_on_page(html: str) -> list[str];
