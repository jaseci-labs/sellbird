impl _regions(text: str) -> dict[str, tuple[str, str]] {
    return {r.split(":")[0]: (r.split(":")[1], r.split(":")[2]) for r in text.split(",")};
}

impl _pairs(text: str) -> dict[str, str] {
    return {r.split(":")[0]: r.split(":")[1] for r in text.split(",")};
}

impl _clean(text: str) -> str {
    text = unicodedata.normalize("NFKD", str(text or ""));
    text = "".join(c for c in text if not unicodedata.combining(c));
    return " ".join(text.replace(".", "").lower().split());
}

impl _country_names -> dict[str, any] {
    states = {name for (name, _) in US_STATES.values()};
    names = {_clean(n): c for (c, n) in pytz.country_names.items() if _clean(n) not in states};
    return names | COUNTRY_ALIASES;
}

impl _zone_points -> dict[str, tuple[float, float]] {
    with pytz.open_resource("zone.tab") as f {
        lines = f.read().decode("utf-8").splitlines();
    }
    rows = [line.split("\t") for line in lines if line and not line.startswith("#")];
    points = {r[2]: _iso6709(r[1]) for r in rows if len(r) >= 3};
    return {z: p for (z, p) in points.items() if p};
}

impl _iso6709(text: str) -> tuple[float, float] | None {
    m = re.fullmatch("([+-])(\\d{2})(\\d{2})(\\d{2})?([+-])(\\d{3})(\\d{2})(\\d{2})?", text);
    if not m {
        return None;
    }
    (s1, d1, m1, x1, s2, d2, m2, x2) = m.groups();
    lat = int(d1) + int(m1) / 60 + int(x1 or 0) / 3600;
    lon = int(d2) + int(m2) / 60 + int(x2 or 0) / 3600;
    return (lat if s1 == "+" else -lat, lon if s2 == "+" else -lon);
}

impl _km(a: tuple[float, float], b: tuple[float, float]) -> float {
    (lat1, lon1, lat2, lon2) = [math.radians(v) for v in (*a, *b)];
    h = math.sin((lat2 - lat1) / 2) ** 2
        + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2;
    return 6371 * 2 * math.asin(min(1.0, math.sqrt(h)));
}

impl _nearest(point: any, zones: any = None, max_km: float | None = None) -> str {
    refs = _zone_points();
    candidates = [z for z in (zones if zones is not None else refs) if z in refs];
    if not point or not candidates {
        return "";
    }
    best = min(candidates, key=lambda (z: str) -> float { _km(point, refs[z]) });
    return "" if max_km is not None and _km(point, refs[best]) > max_km else best;
}

impl _point(text: str) -> tuple[float, float] | None {
    try {
        v = [float(x) for x in str(text or "").split(",")[:2]];
    } except ValueError {
        return None;
    }
    return (v[0], v[1]) if len(v) == 2 and abs(v[0]) <= 90 and abs(v[1]) <= 180 else None;
}

impl country_code(value: any) -> str {
    code = str(value or "").strip().upper();
    code = {"UK": "GB", "USA": "US"}.get(code, code);
    return code if code in pytz.country_timezones else "";
}

impl _zone_countries -> dict[str, str] {
    return {zone: code for (code, zones) in pytz.country_timezones.items() for zone in zones};
}

impl zone_country(zone: str) -> str {
    return _zone_countries().get(str(zone or ""), "");
}

impl _one_offset(zones: list[str]) -> bool {
    year = datetime.now().year;
    (jan, jul) = (datetime(year, 1, 15, 12), datetime(year, 7, 15, 12));
    return len({(pytz.timezone(z).utcoffset(jan), pytz.timezone(z).utcoffset(jul)) for z in zones})
        == 1;
}

impl _country_zone(code: str, point: any = None) -> str {
    zones = pytz.country_timezones.get(code, []);
    if not zones {
        return "";
    }
    if len(zones) == 1 or _one_offset(zones) {
        return zones[0];
    }
    return _nearest(point, zones) if point else MAIN_ZONE.get(code, "");
}

impl _parts(location: str) -> list[str] {
    raws = reversed(str(location or "").split(","));
    parts = [" ".join(re.sub("\\b[\\dA-Z]*\\d[\\dA-Z-]*\\b", " ", raw).split()) for raw in raws];
    return [p for p in parts if p];
}

impl _codes(part: str) -> list[str] {
    return [w.replace(".", "") for w in part.split() if w.isupper()];
}

impl _country_in(parts: list[str]) -> str {
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

impl _ambiguous_code(parts: list[str]) -> str {
    return next(
        (c for p in parts for c in _codes(p) if c in REGION_COUNTRY and country_code(c)), ""
    );
}

impl _ref_km(point: any, zone: str) -> float {
    ref = _zone_points().get(zone);
    return _km(point, ref) if ref else math.inf;
}

impl _region(parts: list[str], text_country: str, hint: str) -> str {
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

impl zone_for(location: str = "", country: str = "", point: str = "") -> str {
    return _resolve(location, country, point)[0];
}

impl _country(parts: list[str], coords: any = None, hint: str = "") -> tuple[str, bool] {
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

impl country_for(location: str = "", point: str = "") -> tuple[str, bool] {
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

impl _resolve(location: str = "", country: str = "", point: str = "") -> tuple[str, bool] {
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

impl _localize(tz: any, naive: datetime) -> datetime {
    try {
        return tz.localize(naive, is_dst=None);
    } except pytz.AmbiguousTimeError {
        return tz.localize(naive, is_dst=True);
    } except pytz.NonExistentTimeError {
        return tz.normalize(tz.localize(naive, is_dst=False));
    }
}

impl _bounds(tz: any, day: any, window: any) -> tuple[datetime, datetime] {
    opens = _localize(tz, datetime.combine(day, time.fromisoformat(window.start)));
    return (opens, _localize(tz, datetime.combine(day, time.fromisoformat(window.end))));
}

impl in_window(at: datetime, zone: str, window: any) -> bool {
    tz = pytz.timezone(zone);
    local = pytz.utc.localize(at).astimezone(tz);
    if window.weekdays_only and local.weekday() >= 5 {
        return False;
    }
    (opens, closes) = _bounds(tz, local.date(), window);
    return opens <= local and local < closes;
}

impl next_send_time(after: datetime, zone: str, window: any, rng: any = None) -> datetime {
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

impl icp_country(config: any) -> str {
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

impl _place(state: any, prospect: any) -> tuple[str, str] {
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

impl recipient_country(state: any, prospect: any) -> str {
    if prospect is None {
        return "";
    }
    (location, point) = await _place(state, prospect);
    (country, certain) = country_for(location, point);
    return country if certain else "";
}

impl recipient_zone(state: any, prospect: any, config: any, country: str = "") -> str {
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
