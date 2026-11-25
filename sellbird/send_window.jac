import math;
import random;
import re;
import unicodedata;
import from datetime { datetime, timedelta, time }
import from functools { lru_cache }
import pytz;

glob START_SPREAD = timedelta(minutes=30),
     MAX_NEAREST_KM = 500,
     MAX_REGION_KM = 3000,
     US_STATES = _regions(
         "AL:alabama:America/Chicago,AK:alaska:America/Anchorage,AZ:arizona:America/Phoenix,"
             "AR:arkansas:America/Chicago,CA:california:America/Los_Angeles,CO:colorado:America/Denver,"
             "CT:connecticut:America/New_York,DE:delaware:America/New_York,"
             "DC:district of columbia:America/New_York,FL:florida:America/New_York,"
             "GA:georgia:America/New_York,HI:hawaii:Pacific/Honolulu,ID:idaho:America/Boise,"
             "IL:illinois:America/Chicago,IN:indiana:America/Indiana/Indianapolis,IA:iowa:America/Chicago,"
             "KS:kansas:America/Chicago,KY:kentucky:America/New_York,LA:louisiana:America/Chicago,"
             "ME:maine:America/New_York,MD:maryland:America/New_York,MA:massachusetts:America/New_York,"
             "MI:michigan:America/Detroit,MN:minnesota:America/Chicago,MS:mississippi:America/Chicago,"
             "MO:missouri:America/Chicago,MT:montana:America/Denver,NE:nebraska:America/Chicago,"
             "NV:nevada:America/Los_Angeles,NH:new hampshire:America/New_York,NJ:new jersey:America/New_York,"
             "NM:new mexico:America/Denver,NY:new york:America/New_York,NC:north carolina:America/New_York,"
             "ND:north dakota:America/Chicago,OH:ohio:America/New_York,OK:oklahoma:America/Chicago,"
             "OR:oregon:America/Los_Angeles,PA:pennsylvania:America/New_York,RI:rhode island:America/New_York,"
             "SC:south carolina:America/New_York,SD:south dakota:America/Chicago,TN:tennessee:America/Chicago,"
             "TX:texas:America/Chicago,UT:utah:America/Denver,VT:vermont:America/New_York,"
             "VA:virginia:America/New_York,WA:washington:America/Los_Angeles,"
             "WV:west virginia:America/New_York,WI:wisconsin:America/Chicago,WY:wyoming:America/Denver",
     ),
     CA_PROVINCES = _regions(
         "AB:alberta:America/Edmonton,BC:british columbia:America/Vancouver,MB:manitoba:America/Winnipeg,"
             "NB:new brunswick:America/Moncton,NL:newfoundland and labrador:America/St_Johns,"
             "NS:nova scotia:America/Halifax,NT:northwest territories:America/Edmonton,"
             "NU:nunavut:America/Iqaluit,ON:ontario:America/Toronto,PE:prince edward island:America/Halifax,"
             "QC:quebec:America/Toronto,SK:saskatchewan:America/Regina,YT:yukon:America/Whitehorse",
     ),
     AU_STATES = _regions(
         "NSW:new south wales:Australia/Sydney,VIC:victoria:Australia/Melbourne,"
             "QLD:queensland:Australia/Brisbane,WA:western australia:Australia/Perth,"
             "SA:south australia:Australia/Adelaide,TAS:tasmania:Australia/Hobart,"
             "ACT:australian capital territory:Australia/Sydney,NT:northern territory:Australia/Darwin",
     ),
     MAIN_ZONE = _pairs(
         "CL:America/Santiago,CN:Asia/Shanghai,EC:America/Guayaquil,ES:Europe/Madrid,NZ:Pacific/Auckland,"
             "PT:Europe/Lisbon,UA:Europe/Kyiv,AU:Australia/Sydney,BR:America/Sao_Paulo,CA:America/Toronto,"
             "ID:Asia/Jakarta,MX:America/Mexico_City,RU:Europe/Moscow",
     ),
     COUNTRY_ALIASES = _pairs(
         "uk:GB,united kingdom:GB,great britain:GB,britain:GB,england:GB,scotland:GB,wales:GB,"
             "northern ireland:GB,usa:US,us:US,united states of america:US,america:US,the netherlands:NL,"
             "holland:NL,deutschland:DE,south korea:KR,korea:KR,uae:AE,czechia:CZ,republic of ireland:IE,"
             "eire:IE",
     ),
     REGION_ALIASES = _pairs("newfoundland:NL,labrador:NL,pei:PE,yukon territory:YT"),
     CA_CODES_ALONE = set("AB BC MB NB NS ON QC".split()),
     AU_CODES_ALONE = set("NSW VIC QLD TAS ACT".split()),
     REGION_COUNTRY = dict.fromkeys(US_STATES, "US")
         | dict.fromkeys(CA_PROVINCES, "CA")
         | dict.fromkeys(AU_STATES, "AU");

def _regions(text: str) -> dict[str, tuple[str, str]] {
    return {r.split(":")[0]: (r.split(":")[1], r.split(":")[2]) for r in text.split(",")};
}

def _pairs(text: str) -> dict[str, str] {
    return {r.split(":")[0]: r.split(":")[1] for r in text.split(",")};
}

def _clean(text: str) -> str {
    text = unicodedata.normalize("NFKD", str(text or ""));
    text = "".join(c for c in text if not unicodedata.combining(c));
    return " ".join(text.replace(".", "").lower().split());
}

@lru_cache(maxsize=1)
def _country_names -> dict[str, any] {
    states = {name for (name, _) in US_STATES.values()};
    names = {_clean(n): c for (c, n) in pytz.country_names.items() if _clean(n) not in states};
    return names | COUNTRY_ALIASES;
}

@lru_cache(maxsize=1)
def _zone_points -> dict[str, tuple[float, float]] {
    with pytz.open_resource("zone.tab") as f {
        lines = f.read().decode("utf-8").splitlines();
    }
    rows = [line.split("\t") for line in lines if line and not line.startswith("#")];
    points = {r[2]: _iso6709(r[1]) for r in rows if len(r) >= 3};
    return {z: p for (z, p) in points.items() if p};
}

def _iso6709(text: str) -> tuple[float, float] | None {
    m = re.fullmatch("([+-])(\\d{2})(\\d{2})(\\d{2})?([+-])(\\d{3})(\\d{2})(\\d{2})?", text);
    if not m {
        return None;
    }
    (s1, d1, m1, x1, s2, d2, m2, x2) = m.groups();
    lat = int(d1) + int(m1) / 60 + int(x1 or 0) / 3600;
    lon = int(d2) + int(m2) / 60 + int(x2 or 0) / 3600;
    return (lat if s1 == "+" else -lat, lon if s2 == "+" else -lon);
}

def _km(a: tuple[float, float], b: tuple[float, float]) -> float {
    (lat1, lon1, lat2, lon2) = [math.radians(v) for v in (*a, *b)];
    h = math.sin((lat2 - lat1) / 2) ** 2
        + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2;
    return 6371 * 2 * math.asin(min(1.0, math.sqrt(h)));
}

def _nearest(point: any, zones: any = None, max_km: float | None = None) -> str {
    refs = _zone_points();
    candidates = [z for z in (zones if zones is not None else refs) if z in refs];
    if not point or not candidates {
        return "";
    }
    best = min(candidates, key=lambda (z: str) -> float { _km(point, refs[z]) });
    return "" if max_km is not None and _km(point, refs[best]) > max_km else best;
}

def _point(text: str) -> tuple[float, float] | None {
    try {
        v = [float(x) for x in str(text or "").split(",")[:2]];
    } except ValueError {
        return None;
    }
    return (v[0], v[1]) if len(v) == 2 and abs(v[0]) <= 90 and abs(v[1]) <= 180 else None;
}

def country_code(value: any) -> str {
    code = str(value or "").strip().upper();
    code = {"UK": "GB", "USA": "US"}.get(code, code);
    return code if code in pytz.country_timezones else "";
}

@lru_cache(maxsize=1)
def _zone_countries -> dict[str, str] {
    return {zone: code for (code, zones) in pytz.country_timezones.items() for zone in zones};
}

def zone_country(zone: str) -> str {
    return _zone_countries().get(str(zone or ""), "");
}

def _one_offset(zones: list[str]) -> bool {
    year = datetime.now().year;
    (jan, jul) = (datetime(year, 1, 15, 12), datetime(year, 7, 15, 12));
    return len({(pytz.timezone(z).utcoffset(jan), pytz.timezone(z).utcoffset(jul)) for z in zones})
        == 1;
}

def _country_zone(code: str, point: any = None) -> str {
    zones = pytz.country_timezones.get(code, []);
    if not zones {
        return "";
    }
    if len(zones) == 1 or _one_offset(zones) {
        return zones[0];
    }
    return _nearest(point, zones) if point else MAIN_ZONE.get(code, "");
}

def _parts(location: str) -> list[str] {
    raws = reversed(str(location or "").split(","));
    parts = [" ".join(re.sub("\\b[\\dA-Z]*\\d[\\dA-Z-]*\\b", " ", raw).split()) for raw in raws];
    return [p for p in parts if p];
}

def _codes(part: str) -> list[str] {
    return [w.replace(".", "") for w in part.split() if w.isupper()];
}

def _country_in(parts: list[str]) -> str {
    names = _country_names();
    for part in parts {
        if _clean(part) in names {
            return names[_clean(part)];
        }
        if len(part) == 2 and part.isupper() and part not in REGION_COUNTRY and country_code(part) {
            return country_code(part);
        }
    }
    return "";
}

def _ambiguous_code(parts: list[str]) -> str {
    return next(
        (c for p in parts for c in _codes(p) if c in REGION_COUNTRY and country_code(c)), ""
    );
}

def _ref_km(point: any, zone: str) -> float {
    ref = _zone_points().get(zone);
    return _km(point, ref) if ref else math.inf;
}

def _region(parts: list[str], text_country: str, hint: str) -> str {
    context = text_country or hint;
    us_names = {name: zone for (name, zone) in US_STATES.values()};
    for part in parts {
        (name, codes) = (_clean(part), _codes(part));
        if text_country in ("", "US") {
            if name in us_names {
                return us_names[name];
            }
            if name.replace(" ", "") == "dc" {
                return US_STATES["DC"][1];
            }
            for code in codes {
                if code in US_STATES
                    and not (hint and hint != "US" and country_code(code) == hint)
                {
                    return US_STATES[code][1];
                }
            }
        }
        alias = REGION_ALIASES.get(name, "");
        for (country, table, alone) in (
            ("CA", CA_PROVINCES, CA_CODES_ALONE),
            ("AU", AU_STATES, AU_CODES_ALONE),
        ) {
            for (key, (full, zone)) in table.items() if context in ("", country) else [] {
                if name == full
                    or alias == key
                    or (key in codes and (context == country or key in alone))
                {
                    return zone;
                }
            }
        }
    }
    return "";
}

def zone_for(location: str = "", country: str = "", point: str = "") -> str {
    return _resolve(location, country, point)[0];
}

def _country(parts: list[str], coords: any = None, hint: str = "") -> tuple[str, bool] {
    text_country = _country_in(parts);
    code = "" if text_country else _ambiguous_code(parts);
    if not code {
        return (text_country, False);
    }
    home = REGION_COUNTRY[code];
    if hint {
        return (hint, False);
    }
    if coords {
        as_region = _region(parts, home, "");
        near = as_region
            and _ref_km(coords, as_region) <= _ref_km(coords, _country_zone(code, coords));
        return (home if near else code, False);
    }
    return (home if home == "US" else code, True);
}

def country_for(location: str = "", point: str = "") -> tuple[str, bool] {
    (parts, coords) = (_parts(location), _point(point));
    (country, guessed) = _country(parts, coords);
    if guessed {
        return (country, False);
    }
    ambiguous = "" if _country_in(parts) else _ambiguous_code(parts);
    if ambiguous and coords {
        region_km = _ref_km(coords, _region(parts, REGION_COUNTRY[ambiguous], ""));
        if min(region_km, _ref_km(coords, _country_zone(ambiguous, coords))) > MAX_REGION_KM {
            return ("", False);
        }
    }
    zone = _region(parts, country, "");
    if zone and coords and _ref_km(coords, zone) > MAX_REGION_KM {
        zone = "";
        country = "" if country == "US" else country;
    }
    country = country or zone_country(zone);
    return (country, bool(country));
}

def _resolve(location: str = "", country: str = "", point: str = "") -> tuple[str, bool] {
    (parts, coords, hint) = (_parts(location), _point(point), country_code(country));
    (text_country, guessed) = _country(parts, coords, hint);
    zone = _region(parts, text_country, hint);
    if zone and coords and _km(coords, _zone_points().get(zone, coords)) > MAX_REGION_KM {
        zone = "";
        text_country = "" if text_country == "US" else text_country;
    }
    if zone {
        return (zone, guessed);
    }
    named = text_country or hint;
    if named {
        (zone, zones) = (_country_zone(named, coords), pytz.country_timezones.get(named, []));
        main_only = not coords and len(zones) > 1 and not _one_offset(zones);
        return (zone, guessed or (bool(zone) and main_only));
    }
    return (_nearest(coords, max_km=MAX_NEAREST_KM), False) if coords else ("", False);
}

def _localize(tz: any, naive: datetime) -> datetime {
    try {
        return tz.localize(naive, is_dst=None);
    } except pytz.AmbiguousTimeError {
        return tz.localize(naive, is_dst=True);
    } except pytz.NonExistentTimeError {
        return tz.normalize(tz.localize(naive, is_dst=False));
    }
}

def _bounds(tz: any, day: any, window: any) -> tuple[datetime, datetime] {
    opens = _localize(tz, datetime.combine(day, time.fromisoformat(window.start)));
    return (opens, _localize(tz, datetime.combine(day, time.fromisoformat(window.end))));
}

def in_window(at: datetime, zone: str, window: any) -> bool {
    tz = pytz.timezone(zone);
    local = pytz.utc.localize(at).astimezone(tz);
    if window.weekdays_only and local.weekday() >= 5 {
        return False;
    }
    (opens, closes) = _bounds(tz, local.date(), window);
    return opens <= local and local < closes;
}

def next_send_time(after: datetime, zone: str, window: any, rng: any = None) -> datetime {
    tz = pytz.timezone(zone);
    local = pytz.utc.localize(after).astimezone(tz);
    for offset in range(8) {
        day = local.date() + timedelta(days=offset);
        if window.weekdays_only and day.weekday() >= 5 {
            continue;
        }
        (opens, closes) = _bounds(tz, day, window);
        if local < closes {
            if local >= opens {
                return after;
            }
            spread = min(START_SPREAD, (closes - opens) / 4).total_seconds();
            when = opens + timedelta(seconds=(rng or random).uniform(0, spread));
            return when.astimezone(pytz.utc).replace(tzinfo=None);
        }
    }
    raise ValueError("send window never opens");
}

def icp_country(config: any) -> str {
    icp = getattr(config, "icp", None);
    coords = getattr(icp, "geo_coordinates", None) or {};
    found: set[str] = set();
    for place in getattr(icp, "geography", None) or [] {
        (country, certain) = country_for(place, coords.get(place, ""));
        if not certain {
            return "";
        }
        found.add(country);
    }
    return found.pop() if len(found) == 1 else "";
}

async def _place(state: any, prospect: any) -> tuple[str, str] {
    (location, point) = ("", "");
    if getattr(prospect, "company_id", "") {
        company = await state.get_company(prospect.company_id);
        location = (getattr(company, "location", "") or "") if company else "";
    }
    if location.strip() {
        cached = await state.get_setting("geo:" + location.strip().lower());
        point = "" if not cached or cached == "-" else cached;
    }
    return (location, point);
}

async def recipient_country(state: any, prospect: any) -> str {
    if prospect is None {
        return "";
    }
    (location, point) = await _place(state, prospect);
    (country, certain) = country_for(location, point);
    return country if certain else "";
}

async def recipient_zone(state: any, prospect: any, config: any, country: str = "") -> str {
    if prospect is None {
        return "";
    }
    if getattr(prospect, "timezone", "") {
        return prospect.timezone;
    }
    (location, point) = await _place(state, prospect);
    (zone, guessed) = _resolve(location, country_code(country), point);
    if zone and not guessed {
        prospect.timezone = zone;
        await state.set_prospect_timezone(prospect.id, zone);
        return zone;
    }
    precleared = getattr(getattr(config, "compliance", None), "precleared", None);
    fallback = country_code(getattr(precleared, "prospect_country", ""));
    return (_resolve(location, fallback, point)[0] or zone)
        if fallback and not country_code(country)
        else zone;
}
