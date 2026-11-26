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
     _HONORIFIC = re.compile(
         "(?i)^(?:(?:dre?|mr|mrs|ms|miss|prof|rev|hon|mme|mlle|me)\\.?|m\\.)\\s+"
     ),
     _CREDENTIAL_TAIL = re.compile(
         "(?i)(?:\\s*,?\\s+(?:dds|dmd|md|do|dvm|od|phd|jd|esq|cpa|pe|ra|rn|np|pa|mba|ms|ma|facs|fagd|ccc-slp|jr|sr|ii|iii|iv)\\.?)+\\s*$",
     ),
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
     _FEMININE_RE = re.compile("(?<![a-z])(?:" + "|".join(_FEMININE) + ")(?![a-z])"),
     _MEMO_SIZE = 4096,
     _NORMED: dict[str, str] = {},
     _FAMILY: dict[str, str] = {},
     _CLEANED: dict[tuple[str, str], str] = {},
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
     _LINE_BREAK = re.compile(
         "(?i)<(?:/?(?:p|div|li|ul|ol|h[1-6]|section|article|header|footer|nav|td|tr|table|blockquote|figcaption|dt|dd|span|a|strong|b|em|label|button)\\b[^>]*|br\\s*/?)>",
     ),
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

    def add(
        split: any, title: str, source: str, ev: str, url: str, full: str, owner: bool = False
    ) {
        key = (split[0].lower(), split[1].lower()) if split else None;
        if key and key not in self.seen {
            self.seen.add(key);
            self.people.append({
                "first_name": split[0],
                "last_name": split[1],
                "title": title[:80].strip(" ,;:-–—|"),
                "full_name": full or f"{split[0]} {split[1]}",
                "owner": owner,
                "source": source,
                "evidence": ev[:200],
                "evidence_url": url,
            });
        }
    }
}

def _word_ok(token: str) -> bool {
    low = fold_accents(token.strip(".,'’")).lower();
    return bool(low)
        and low not in COMMON_WORDS
        and low not in NON_NAME_WORDS
        and not _NOUN_SUFFIX.search(low);
}

def split_person_name(text: str) -> tuple[str, str] | None {
    text = str(
        re.sub("\\s+", " ", html_lib.unescape(text or "").replace("\xa0", " ")).strip(" ,.-|–—")
    );
    text = str(_HONORIFIC.sub("", re.sub("(?i)^(?:meet|introducing)\\s+", "", text)));
    text = nfc(str(_CREDENTIAL_TAIL.sub("", text).strip(" ,")));
    tokens = text.split();
    odd = len(text) > 45 or any(ch.isdigit() for ch in text) or "@" in text;
    if odd or len(tokens) not in (2, 3, 4, 5) {
        return None;
    }
    folded = fold_accents(text).split();
    (first, rest) = (folded[0], folded[1:]);
    start = len(rest) - 1;
    while start > 0 and rest[start - 1].lower() in _PARTICLES {
        start -= 1;
    }
    (surname, last_word) = (rest[start:], rest[-1]);
    if not re.match("^[A-Z][a-z]+(?:[-'’][A-Z]?[a-z]+)*$", first)
        or not _word_ok(first)
        or not all(
            re.match(_NAME_TOKEN, t) and (len(t.strip(".")) == 1 or _word_ok(t))
            for t in rest[:start],
        )
        or not re.match("^[A-Z][a-zA-Z]*(?:[-'’][A-Z]?[a-zA-Z]+)*$", last_word)
        or len(last_word) < 2
        or (last_word.isupper() and len(last_word) > 2)
        or not _word_ok(last_word)
        or first.isupper()
        or any(t.lower() not in _PARTICLES for t in surname[:-1])
    {
        return None;
    }
    return (tokens[0], " ".join(tokens[1 + start:]));
}

def is_person_name(text: str) -> bool {
    return split_person_name(text) is not None;
}

def _remember(memo: any, key: any, value: str) -> str {
    if len(memo) >= _MEMO_SIZE {
        memo.clear();
    }
    memo[key] = value;
    return value;
}

def _norm_title(text: str) -> str {
    text = text or "";
    if text in _NORMED {
        return _NORMED[text];
    }
    feminine = lambda (m: any) -> any { _FEMININE[m.group(0)] };
    return _remember(_NORMED, text, str(_FEMININE_RE.sub(feminine, fold_accents(text).lower())));
}

def _family_key(text: str) -> str {
    if text in _FAMILY {
        return _FAMILY[text];
    }
    return _remember(_FAMILY, text, str(re.sub("[\\s\\-–]+", " ", _norm_title(text).strip())));
}

def is_owner_title(title: str) -> bool {
    title = fold_accents((title or "").strip());
    return bool(title)
        and not re.search(_SUBORDINATE, title)
        and not re.search(_FORMER, title)
        and bool(re.search(_OWNER_TITLE, title) or re.match(_PARTNER_ONLY, title));
}

def _clean_for_target(title: str, target: str) -> str {
    if (title, target) in _CLEANED {
        return _CLEANED[(title, target)];
    }
    return _remember(_CLEANED, (title, target), _clean_uncached(title, target));
}

def _clean_uncached(title: str, target: str) -> str {
    low = f" {_norm_title(title)} ";
    if "vice" not in target and "vp" not in target.split() {
        low = re.sub("\\bvice[- ]president\\b|\\b[se]?vp\\b", " ", low);
    }
    if "assistant" not in target {
        low = re.sub("\\b(?:executive )?assistant\\b.*", " ", low);
    }
    if not re.search("\\badjoint|\\bsous-", target)
        and re.search("\\badjoint\\b|\\bsous-\\w", low)
    {
        return " ";
    }
    return re.sub("\\bto the\\b.*", " ", low);
}

def title_matches(title: str, targets: any, owner: bool = False) -> bool {
    title = (title or "").strip();
    wanted = [_norm_title(str(t.strip())) for t in targets or [] if t and t.strip()];
    if not wanted or re.search(_FORMER, fold_accents(title)) {
        return False;
    }
    if any(_family_key(t) in _OWNER_FAMILY_KEYS for t in wanted)
        and (owner or is_owner_title(title))
    {
        return True;
    }
    return bool(title)
        and any(
            re.search(f"(?<![\\w-]){re.escape(t)}(?![\\w])", _clean_for_target(title, t))
            for t in wanted,
        );
}

def owner_rank(title: str, owner: bool = False) -> int {
    low = fold_accents(title or "").lower();
    if is_owner_title(title) {
        if re.search("\\b(?:co-?owner|owner|proprietor|co-?proprietaire|proprietaire)\\b", low) {
            return 100;
        }
        president = "\\b(?:presidente?|pdg|p\\.-?d\\.g|fondat(?:eur|rice)|co-?fondat(?:eur|rice))\\b";
        general = re.search("\\bdirect(?:eur|rice) generale?\\b", low)
            and not re.search(president, low);
        return 92 if general else 95;
    }
    if owner {
        return 90;
    }
    if re.search("\\bpartner\\b|\\bassociee?s?\\b(?!\\s*(?:aux?|a la|en)\\b)", low) {
        return 80;
    }
    if re.search("\\b(?:general manager|managing director)\\b", low) {
        return 60;
    }
    manager = "\\b(?:director|manager|head of|chief|directeur|directrice|gerante?|gestionnaire|responsable)\\b";
    return 40 if re.search(manager, low) and not re.search(_SUBORDINATE, low) else 10;
}

def _alnum(text: str) -> str {
    return re.sub("[^a-z0-9]", "", fold_accents(text or "").lower());
}

def _domain_label(domain: str) -> str {
    host = re.sub("^https?://", "", (domain or "").lower().strip().removeprefix("www."));
    parts = [p for p in host.split("/")[0].split(".") if p];
    if len(parts) >= 3 and parts[-2] in ("co", "com", "org", "net") and len(parts[-1]) == 2 {
        return parts[-3];
    }
    return parts[-2] if len(parts) >= 2 else (parts[0] if parts else "");
}

def names_business(text: str, domain: str, site_name: str = "") -> bool {
    blob = _domain_label(domain) + "|" + _alnum(site_name);
    words = re.findall("[a-z0-9]+", fold_accents(text or "").lower());
    if any(len(w) >= 3 and w not in _GENERIC_BUSINESS_WORDS and w in blob for w in words) {
        return True;
    }
    (squashed, label) = (_alnum(text), _domain_label(domain));
    return len(squashed) >= 4 and (squashed in blob or (len(label) >= 4 and label in squashed));
}

def surname_on_the_door(last_name: str, domain: str, site_name: str = "") -> bool {
    blob = _domain_label(domain) + "|" + _alnum(site_name);
    parts = [p.lower() for p in re.findall("[A-Za-z]+", fold_accents(last_name or ""))];
    return any(len(p) >= 4 and p not in _GENERIC_BUSINESS_WORDS and p in blob for p in parts);
}

def title_names_other_org(title: str, domain: str, site_name: str = "") -> bool {
    roles = "(?i)(?:and\\s+)?(?:owner|founder|co-?founder|ceo|cto|coo|cmo|president|principal|partner|director|chief[\\w\\s]*|operations|executive officer)";
    for m in re.finditer(_TITLE_ORG, fold_accents(title or "")) {
        org = m.group(1).strip();
        if not re.fullmatch(roles, org)
            and not re.fullmatch(f"(?i){_FR_TITLE_WORDS}", org)
            and not names_business(org, domain, site_name)
        {
            return True;
        }
    }
    return False;
}

def _close_of(html: str, start: int, tag: str) -> int {
    depth = 0;
    pattern = re.compile(f"(?i)<(/?){re.escape(tag)}\\b[^>]*?(/?)>");
    for m in pattern.finditer(html, start, min(len(html), start + MAX_QUOTE_CHARS)) {
        depth += 0 if m.group(2) else (-1 if m.group(1) else 1);
        if depth == 0 and not m.group(2) {
            return m.end();
        }
    }
    return start;
}

def drop_quoted(html: str) -> str {
    html = re.sub(_STATUS_LINK, " ", html or "");
    out: list[str] = [];
    pos = 0;
    for (n, m) in enumerate(re.finditer(_QUOTED_CLASS, html)) {
        if n >= MAX_QUOTES {
            break;
        }
        if m.start() < pos or m.group(1).lower() in _VOID_TAGS {
            continue;
        }
        end = _close_of(html, m.start(), m.group(1));
        if end > m.start() {
            out.append(html[pos:m.start()]);
            pos = max(end, m.end());
        }
    }
    html = "".join(out) + html[pos:];
    return re.sub("(?is)<blockquote\\b(?:(?!</?blockquote).){0,8000}</blockquote>", " ", html);
}

def page_lines(html: str) -> list[str] {
    text = _LINE_BREAK.sub("\n", _strip_code(nfc(html)));
    text = html_lib.unescape(re.sub("(?s)<[^>]+>", " ", text)).replace("\xa0", " ");
    lines = [str(re.sub("\\s+", " ", line).strip(" |·•")) for line in text.split("\n")];
    return [line for line in lines if line];
}

def _sentences(html: str) -> list[str] {
    blocks = "(?i)<(?:/?(?:p|div|li|h[1-6]|section|article|td|tr|blockquote|figcaption|dd|dt)\\b[^>]*|br\\s*/?)>";
    text: any = re.sub(blocks, "\n", _strip_code(nfc(html)));
    text = nfc(html_lib.unescape(re.sub("(?s)<[^>]+>", " ", text)).replace("\xa0", " "));
    abbrev = "\\b(Dre?|Mr|Mrs|Ms|Mme|Mlle|Prof|St|Ste|Jr|Sr|Inc|Co|Ltd|Lt[ée]e|[A-Z])\\. ";
    out: list[str] = [];
    for block in text.split("\n") {
        block = re.sub(abbrev, "\\1.\xa0", re.sub("\\s+", " ", block).strip());
        out.extend([
            str(s.strip())
            for s in re.split("(?<=[.!?]) +(?=[A-ZÀ-ÖØ-Þ])", block)
            if s.strip()
        ]);
    }
    return out;
}

def people_from_lines(
    html: str, domain: str = "", site_name: str = "", url: str = ""
) -> list[any] {
    lines = page_lines(drop_quoted(html));
    found = _Found();
    for (i, line) in enumerate(lines) {
        nxt = lines[i + 1] if i + 1 < len(lines) else "";
        (name, m) = (split_person_name(line), re.match(_SEPARATED, line));
        if re.search(_QUOTE_LINE, lines[i - 1] if i else "") or re.match("^[—–-]\\s*\\S", line) {
            continue;
        } elif name and _reads_like_title(nxt) and not nxt.rstrip().endswith(("!", "?")) {
            (title, raw) = (nxt, line);
        } elif m {
            (title, raw) = (m.group("title").strip(), m.group("name").strip());
            strong = _reads_like_title(title) and re.search(_STRONG_ROLE, fold_accents(title));
            ok = strong and not title.endswith(".") and len(title.split()) <= 7;
            name = split_person_name(m.group("name")) if ok else None;
        } else {
            continue;
        }
        if name and not title_names_other_org(title, domain, site_name) {
            found.add(name, title, "card", f"{raw} — {title}", url, raw);
        }
    }
    return found.people;
}

def _nodes(data: any) -> list[any] {
    if isinstance(data, list) {
        return [n for item in data for n in _nodes(item)];
    }
    if not isinstance(data, dict) {
        return [];
    }
    return [data] + [n for k in _GRAPH_KEYS if k in data for n in _nodes(data[k])];
}

def _as_list(value: any) -> list[any] {
    return [] if value is None else (value if isinstance(value, list) else [value]);
}

def _types(item: any) -> list[str] {
    return [x.lower() for x in _as_list(item.get("@type", "")) if isinstance(x, str)];
}

def people_from_schema(html: str, url: str = "") -> list[any] {
    found = _Found();
    for raw in re.findall(_LD_JSON, html or "") {
        try {
            data = json.loads(raw.strip());
        } except (ValueError, TypeError) {
            continue;
        }
        nodes = _nodes(data);
        by_id = {n.get("@id"): n for n in nodes if isinstance(n.get("@id"), str)};
        for item in nodes {
            types = _types(item);
            if not types or _NOT_STAFF_TYPES.intersection(types) {
                continue;
            }
            for (key, default_title) in _ORG_KEYS.items() {
                for v in _as_list(item.get(key)) {
                    if isinstance(v, dict) and set(v) <= {"@id"} and v.get("@id") in by_id {
                        v = by_id[v["@id"]];
                    }
                    name: any = v if isinstance(v, str) else "";
                    title = default_title;
                    if isinstance(v, dict) {
                        if v.get("@type") and "person" not in _types(v) {
                            continue;
                        }
                        names = (v.get("givenName"), v.get("familyName"));
                        name = v.get("name") or " ".join([x for x in names if isinstance(x, str)]);
                        jt = v.get("jobTitle");
                        title = jt.strip() if isinstance(jt, str) and jt.strip() else title;
                    }
                    split = split_person_name(name if isinstance(name, str) else "");
                    owner = default_title in ("Founder", "Owner") or is_owner_title(title);
                    ev = f"schema.org {key}: {name}";
                    found.add(split, title or "Team member", "schema", ev, url, name, owner);
                }
            }
        }
    }
    found.people.sort(key=lambda (p: any) -> int { -owner_rank(p["title"], p["owner"]) });
    return found.people;
}

def _departed(person: dict[str, any], text: str) -> bool {
    first = re.escape(fold_accents(person["first_name"]));
    last = re.escape(fold_accents(person["last_name"].split()[-1]));
    return bool(
        re.search(
            f"(?i)(?:\\bthe late|in (?:loving )?memory of|remembering|\\bfeue?|(?:a la|en) memoire de(?: feue?)?)\\s+(?:dre?\\.?\\s+|m\\.\\s+|mme\\s+)?{first}\\b|\\b{first}\\b(?:\\s+(?:\\w\\.|\\w+)){{0,3}}?(?:\\s+{last})?\\s*,?[^.]{{0,40}}?\\b{_DEPARTED}",
            text,
        ),
    );
}

def _title_word(word: str) -> str {
    low = re.sub("\\s+", " ", word.lower()).strip();
    folded = fold_accents(low);
    if low == "ceo" or low.startswith("partner") {
        return "CEO" if low == "ceo" else "Partner";
    }
    if re.fullmatch("pdg|p\\.-?d\\.g\\.?", folded) {
        return "PDG";
    }
    if folded != low or re.match(_FRENCH_TITLE, folded) {
        return low[:1].upper() + low[1:];
    }
    return "-".join(p.capitalize() for p in low.split("-")).replace("Co-Founder", "Co-founder");
}

def _prose_match(
    m: any, sentence: str, folded: str, fixed: str, domain: str, site_name: str
) -> any {
    groups = {
        k: (sentence[m.start(k):m.end(k)] if v is not None else None)
        for (k, v) in m.groupdict().items()
    };
    org = fold_accents(groups.get("org") or "");
    own_org = re.match(f"(?i)the\\s|(?:l['’]|la\\s+|son\\s+|sa\\s+){_FR_ORG_NOUN}\\b", org);
    if org and not own_org and not names_business(org, domain, site_name) {
        return None;
    }
    tail = groups.get("tail");
    if tail is None {
        tail = folded[m.end():m.end() + 60];
        tail = tail if re.match("^\\s+(?:of|at|chez)\\s", tail) else "";
    }
    t = fold_accents(tail).strip().lstrip(",;:-–—").strip();
    m_org = re.match(_ORG_AFTER, t);
    if m_org
        and not re.fullmatch(_ROLE_ONLY, m_org.group(1))
        and not names_business(m_org.group(1), domain, site_name)
    {
        return None;
    }
    return (groups["name"], fixed or _title_word(groups.get("title") or ""), sentence);
}

def people_from_prose(html: str, domain: str, site_name: str = "", url: str = "") -> list[any] {
    html = drop_quoted(html);
    sentences = _sentences(html);
    cands: list[any] = [];
    for sentence in sentences {
        folded = fold_accents(sentence);
        for (regex, fixed) in _PROSE {
            for m in regex.finditer(folded) {
                cands.append(_prose_match(m, sentence, folded, fixed, domain, site_name));
            }
        }
    }
    listed: dict[str, set[any]] = {};
    for line in page_lines(html) {
        split = split_person_name(line);
        if split {
            listed.setdefault(fold_accents(split[0]).lower(), set()).add((split, line));
        }
    }
    for sentence in sentences {
        for m in re.finditer(_FIRST_NAME_FOUNDER, fold_accents(sentence)) {
            matches = listed.get(m.group("first").lower(), set());
            if len({s[0] for s in matches}) == 1
                and names_business(m.group("org"), domain, site_name)
            {
                cands.append((next(iter(matches))[1], "Founder", sentence));
            }
        }
    }
    if re.search(_FIRST_PERSON, fold_accents(" ".join(sentences))) {
        heads = re.findall("(?is)<title[^>]*>(.*?)</title>", html)[:1]
            + re.findall("(?is)<h1[^>]*>(.*?)</h1>", html)[:1];
        bio = "(?i)^\\s*(?:meet\\s+|rencontrez\\s+)?(?:attorney|dre?\\.?|doctor|lawyer|founder|owner|me|fondat(?:eur|rice)|propri[ée]taire|pr[ée]sidente?)\\s+";
        for raw in heads {
            text = html_lib.unescape(re.sub("(?s)<[^>]+>", " ", raw));
            head = re.sub(bio, "", re.split("\\s[|–—-]\\s|\\|", text)[0]);
            if split_person_name(head) {
                cands.append((head, "Founder", "first-person founder on a bio page"));
                break;
            }
        }
    }
    found = _Found();
    for (raw_name, title, sentence) in [c for c in cands if c is not None] {
        words = raw_name.split();
        split = split_person_name(raw_name)
            or (split_person_name(" ".join(words[:2])) if len(words) > 2 else None);
        found.add(split, title, "prose", sentence, url, raw_name, is_owner_title(title));
    }
    found.people.sort(key=lambda (p: any) -> int { -owner_rank(p["title"], p["owner"]) });
    return found.people;
}

def _merge(merged: dict[any, any], p: dict[str, any]) {
    key = (p["first_name"].lower(), p["last_name"].split()[-1].lower());
    p = {k: v for (k, v) in p.items() if k != "is_decision_maker"};
    p["owner"] = bool(p.get("owner")) or is_owner_title(p["title"]);
    cur = merged.setdefault(key, p);
    if cur is p {
        return;
    }
    better = owner_rank(p["title"], p["owner"]) > owner_rank(cur["title"], cur["owner"]);
    weak = owner_rank(cur["title"]) < 40;
    if (cur["source"] != "card" and p["source"] == "card")
        or (better and (cur["source"] != "card" or p["source"] == "card" or weak))
    {
        for k in ("title", "evidence", "evidence_url", "source") {
            cur[k] = p[k];
        }
    }
    cur["owner"] = cur["owner"] or p["owner"];
}

def _founded_by_history(p: dict[str, any]) -> bool {
    history = "(?i)\\bfounded\\b[^.]*\\bby\\b|\\bour founder\\b|\\bfondee?s?\\b[^.]*\\bpar\\b|\\b(?:notre|son|sa|leur)\\s+fondat(?:eur|rice)\\b";
    return p["source"] == "prose"
        and fold_accents(p["title"]).lower() in ("founder", "fondateur", "fondatrice")
        and bool(re.search(history, fold_accents(p["evidence"])));
}

def find_people(pages: list[tuple[str, str]], domain: str, site_name: str = "") -> list[any] {
    detect = ProfileCollector(state=None).detect_people;
    merged: dict[any, any] = {};
    for (url, html) in pages {
        for c in detect(html, domain=domain, site_name=site_name) {
            ev = {"evidence": c["full_name"] + " — " + c["title"], "evidence_url": url};
            _merge(merged, c | {"source": "card", "owner": False} | ev);
        }
        for q in people_from_schema(html, url=url)
            + people_from_prose(html, domain, site_name, url=url) {
            _merge(merged, q);
        }
    }
    text = fold_accents(" ".join(" ".join(_sentences(html))[:200000] for (_, html) in pages));
    people = [p for p in merged.values() if not _departed(p, text)];
    if any(p["source"] != "prose" and p["owner"] for p in people) {
        people = [p for p in people if not _founded_by_history(p)];
    }
    for p in people {
        surnames = " ".join(p.get("full_name", p["last_name"]).split()[1:]) or p["last_name"];
        p["rank"] = owner_rank(p["title"], p["owner"])
            + (3 if p["source"] == "card" and is_owner_title(p["title"]) else 0)
            + (2 if p["owner"] and surname_on_the_door(surnames, domain, site_name) else 0)
            - (5 if p["source"] == "prose" else 0);
    }
    people.sort(key=lambda (p: dict[str, any]) -> int { -p["rank"] });
    return people;
}

def _norm_url(url: str) -> str {
    p = urlparse(url);
    return p.netloc.lower().removeprefix("www.")
        + (p.path.rstrip("/") or "/")
        + (("?" + p.query) if p.query else "");
}

def _link_score(segments: list[any], label: str) -> int {
    score = 0;
    for (weight, pattern) in _LINK_WEIGHTS {
        whole = f"^(?:our-|the-|meet-(?:the-|our-)?|about-|notre-|nos-|l-|la-)?(?:{pattern})(?:-(?:us|team|page|bios?|staff|de-nous|nous))?$";
        if [seg for seg in segments if re.search(whole, seg)]
            or (segments and re.match("^meet-", segments[-1]) and weight == 3)
            or re.search(f"(?:^|[^a-z])(?:{pattern})(?:$|[^a-z])", label)
        {
            score = max(score, weight);
        }
    }
    return score;
}

def menu_links(html: str, page_url: str, limit: int = 5) -> list[str] {
    host = urlparse(page_url).netloc.lower().removeprefix("www.");
    seen = {_norm_url(page_url)};
    scored: list[any] = [];
    anchor = "(?is)<a\\b[^>]*?href\\s*=\\s*[\"\\']([^\"\\'#][^\"\\']*)[\"\\'][^>]*>(.*?)</a>";
    for (i, m) in enumerate(re.finditer(anchor, _strip_code(html or ""))) {
        href = html_lib.unescape(m.group(1)).strip();
        if href.lower().startswith(("mailto:", "tel:", "javascript:", "sms:")) {
            continue;
        }
        url = urljoin(page_url, href).split("#")[0];
        (p, key) = (urlparse(url), _norm_url(url));
        if p.scheme not in ("http", "https")
            or p.netloc.lower().removeprefix("www.") != host
            or re.search(_SKIP_LINK, url)
            or key in seen
            or p.path.rstrip("/") in ("", "/index.html", "/index.php", "/home")
        {
            continue;
        }
        text: any = html_lib.unescape(re.sub("(?s)<[^>]+>", " ", m.group(2)));
        text = fold_accents(nfc(re.sub("\\s+", " ", text).strip().lower()));
        path = fold_accents(nfc(unquote(p.path))).lower();
        segments = [re.sub("\\.(?:html?|php|aspx?)$", "", seg) for seg in path.split("/") if seg];
        score = _link_score(segments, text if len(text.split()) <= 4 else "");
        if score {
            seen.add(key);
            scored.append((-score, len(p.path), i, url));
        }
    }
    scored.sort();
    return [s[3] for s in scored[:limit]];
}

def _cf_decode(hexstr: str) -> str {
    try {
        key = int(hexstr[:2], 16);
        return "".join(chr(int(hexstr[i:i + 2], 16) ^ key) for i in range(2, len(hexstr) - 1, 2));
    } except ValueError {
        return "";
    }
}

def _clean_address(addr: str) -> str {
    addr = unquote(html_lib.unescape(addr or "")).strip().strip(".,;:<>()[]'\"").lower();
    addr = addr.removeprefix("mailto:").split("?")[0].strip();
    domain = addr.rpartition("@")[2];
    junk = domain in _JUNK_DOMAINS or domain.endswith(_JUNK_TLDS) or re.search("@\\d+x\\.", addr);
    return addr if EMAIL_RE.fullmatch(addr) and not junk else "";
}

def _data_pair(raw_tag: str) -> str {
    mailish = re.match("(?i)<a\\b", raw_tag)
        or re.search("(?i)\\b(?:class|id|title|aria-label)\\s*=\\s*[\"'][^\"']*mail", raw_tag);
    pairs = re.findall("(?i)\\b(data-[a-z\\-]+)\\s*=\\s*[\"\\']([^\"\\']*)[\"\\']", raw_tag)
        if mailish
        else [];
    attrs = {k.lower(): v for (k, v) in pairs};
    local = next((attrs[k] for k in _DATA_PAIR_LOCAL if k in attrs), "");
    domain = next((attrs[k] for k in _DATA_PAIR_DOMAIN if k in attrs), "");
    ok = re.fullmatch("[a-z0-9._%+\\-]+", local, re.I)
        and re.fullmatch("[a-z0-9\\-]+(?:\\.[a-z0-9\\-]+)+", domain, re.I);
    return f"{local}@{domain}" if local and domain and ok else "";
}

def emails_on_page(html: str) -> list[str] {
    html = (html or "")[:MAX_PAGE_CHARS];
    cands = re.findall("(?i)href\\s*=\\s*[\"\\']\\s*mailto:([^\"\\'>]+)[\"\\']", html);
    for raw in re.findall(_LD_JSON, html) {
        cands += re.findall("\"email\"\\s*:\\s*\"([^\"]+)\"", raw);
    }
    cfemail = re.findall("(?i)data-cfemail\\s*=\\s*[\"\\']([0-9a-f]{4,})[\"\\']", html);
    cdn = re.findall("(?i)/cdn-cgi/l/email-protection#([0-9a-f]{4,})", html);
    tags = re.findall("(?is)<[a-z][^>]*\\bdata-[a-z\\-]+\\s*=[^>]*>", html);
    cands += [_cf_decode(h) for h in cfemail + cdn] + [_data_pair(tag) for tag in tags];
    text = unquote(html_lib.unescape(_strip_code(html)));
    cands += [m.group(0) for m in EMAIL_RE.finditer(text)];
    dots = "\\s*(?:\\[\\s*dot\\s*\\]|\\(\\s*dot\\s*\\)|\\{\\s*dot\\s*\\})\\s*";
    for (local, dotted) in re.findall(_AT_DOT, re.sub("(?s)<[^>]+>", " ", text)) {
        domain = re.sub(dots, ".", dotted, flags=re.I).replace(" ", "").lower();
        if domain.rpartition(".")[2] in _KNOWN_TLDS {
            cands.append(f"{local}@{domain}");
        }
    }
    return list(dict.fromkeys(a for a in map(_clean_address, cands) if a));
}
