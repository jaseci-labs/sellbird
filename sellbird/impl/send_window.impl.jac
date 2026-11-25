impl _clean(text: builtins.str) -> builtins.str {
    text = unicodedata.normalize("NFKD", `str(text or ""));
    text = "".join(c for c in text if not unicodedata.combining(c));
    return " ".join(text.replace(".", "").lower().split());
}

impl _country_names -> builtins.dict[builtins.str, builtins.str] {
    states: any = {name for (name, _) in US_STATES.values()};
    names: any = {
        _clean(name): code
        for (code, name) in pytz.country_names.items()
        if _clean(name) not in states
    };
    names.update(COUNTRY_ALIASES);
    return names;
}

impl _zone_points -> builtins.dict[builtins.str, builtins.tuple[builtins.float, builtins.float]] {
    points: any = {};
    f: any;
    with pytz.open_resource("zone.tab") as f {
        for line in f.read().decode("utf-8").splitlines() {
            if not line or line.startswith("#") {
                continue;
            }
            fields: any = line.split("\t");
            if len(fields) >= 3 {
                point: any = _iso6709(fields[1]);
                if point {
                    points[fields[2]] = point;
                }
            }
        }
    }
    return points;
}

impl _iso6709(text: builtins.str) -> builtins.tuple[builtins.float, builtins.float] | None {
    m: any = re.fullmatch("([+-])(\\d{2})(\\d{2})(\\d{2})?([+-])(\\d{3})(\\d{2})(\\d{2})?", text);
    if not m {
        return None;
    }
    s1: any;
    d1: any;
    m1: any;
    x1: any;
    s2: any;
    d2: any;
    m2: any;
    x2: any;
    (s1, d1, m1, x1, s2, d2, m2, x2) = m.groups() as any;
    lat: any = `int(d1) + `int(m1) / 60 + `int(x1 or 0) / 3600;
    lon: any = `int(d2) + `int(m2) / 60 + `int(x2 or 0) / 3600;
    return (lat if s1 == "+" else -lat, lon if s2 == "+" else -lon);
}

impl _km(
    a: builtins.tuple[builtins.float, builtins.float],
    b: builtins.tuple[builtins.float, builtins.float],
) -> builtins.float {
    lat1: any;
    lon1: any;
    lat2: any;
    lon2: any;
    (lat1, lon1, lat2, lon2) = map(math.radians, (*a, *b)) as any;
    h: any = math.sin((lat2 - lat1) / 2) ** 2
        + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2;
    return 6371 * 2 * math.asin(min(1.0, math.sqrt(h)));
}

impl _nearest(point, zones=None, max_km: builtins.float | None = None) -> builtins.str {
    refs: any;
    refs = _zone_points();
    candidates: any = [z for z in (zones if zones is not None else refs) if z in refs];
    if not point or not candidates {
        return "";
    }
    best: any = min(candidates, key=lambda (z) -> any { _km(point, refs[z]) });
    if max_km is not None and _km(point, refs[best]) > max_km {
        return "";
    }
    return best;
}

impl _point(text: builtins.str) -> builtins.tuple[builtins.float, builtins.float] | None {
    try {
        lat: any;
        lon: any;
        (lat, lon) = (`float(x) for x in `str(text or "").split(",")[:2]) as any;
    } except ValueError {
        return None;
    }
    if not (-90 <= lat <= 90 and -180 <= lon <= 180) {
        return None;
    }
    return (lat, lon);
}

impl country_code(value) -> builtins.str {
    code: any = `str(value or "").strip().upper();
    code = {"UK": "GB", "USA": "US"}.get(code, code);
    return code if code in pytz.country_timezones else "";
}

impl _zone_countries -> builtins.dict[builtins.str, builtins.str] {
    return {zone: code for (code, zones) in pytz.country_timezones.items() for zone in zones};
}

impl zone_country(zone: builtins.str) -> builtins.str {
    return _zone_countries().get(`str(zone or ""), "");
}

impl _one_offset(zones: builtins.list[builtins.str]) -> builtins.bool {
    year: any;
    year = datetime.now().year;
    days: any = [datetime(year, 1, 15, 12), datetime(year, 7, 15, 12)];
    seen: any = {
        (pytz.timezone(z).utcoffset(days[0]), pytz.timezone(z).utcoffset(days[1]))
        for z in zones
    };
    return operator.eq(len(seen), 1);
}

impl _country_zone(code: builtins.str, point=None) -> builtins.str {
    zones: any = pytz.country_timezones.get(code, []);
    if not zones {
        return "";
    }
    if len(zones) == 1 or _one_offset(zones) {
        return zones[0];
    }
    if point {
        return _nearest(point, zones);
    }
    return MAIN_ZONE.get(code, "");
}

impl _main_zone_only(code: builtins.str, point=None) -> builtins.bool {
    zones: any = pytz.country_timezones.get(code, []);
    return not point and operator.gt(len(zones), 1) and not _one_offset(zones);
}

impl _parts(location: builtins.str) -> builtins.list[builtins.str] {
    parts: any = [];
    for raw in reversed(`str(location or "").split(",")) {
        part: any = re.sub("\\b[\\dA-Z]*\\d[\\dA-Z-]*\\b", " ", raw);
        part = " ".join(part.split());
        if part {
            parts.append(part);
        }
    }
    return parts;
}

impl _codes(part: builtins.str) -> builtins.list[builtins.str] {
    return [w.replace(".", "") for w in part.split() if w.isupper()];
}

impl _country_in(parts: builtins.list[builtins.str]) -> builtins.str {
    names: any = _country_names();
    for part in parts {
        name: any = _clean(part);
        if name in names {
            return names[name];
        }
        if len(part) == 2 and part.isupper() and part not in REGION_COUNTRY {
            found: any = country_code(part);
            if found {
                return found;
            }
        }
    }
    return "";
}

impl _ambiguous_code(parts: builtins.list[builtins.str]) -> builtins.str {
    for part in parts {
        for code in _codes(part) {
            if code in REGION_COUNTRY and country_code(code) {
                return code;
            }
        }
    }
    return "";
}

impl _ref_km(point, zone: builtins.str) -> builtins.float {
    ref: any = _zone_points().get(zone);
    return _km(point, ref) if ref else math.inf;
}

impl _region(
    parts: builtins.list[builtins.str], text_country: builtins.str, hint: builtins.str
) -> builtins.str {
    name: any;
    zone: any;
    context: any = text_country or hint;
    us_names: any = {name: zone for (name, zone) in US_STATES.values()};
    for part in parts {
        name = _clean(part);
        codes: any = _codes(part);
        if text_country in ("", "US") {
            if name in us_names {
                return us_names[name];
            }
            if name.replace(" ", "") == "dc" {
                return US_STATES["DC"][1];
            }
            code: any;
            for code in codes {
                if code in US_STATES
                    and not (hint and hint != "US" and country_code(code) == hint)
                {
                    return US_STATES[code][1];
                }
            }
        }
        if context in ("", "CA") {
            code = REGION_ALIASES.get(name, "");
            key: any;
            full: any;
            for (key, (full, zone)) in CA_PROVINCES.items() {
                if name == full
                    or code == key
                    or key in codes and (context == "CA" or key in CA_CODES_ALONE)
                {
                    return zone;
                }
            }
        }
        if context in ("", "AU") {
            for (key, (full, zone)) in AU_STATES.items() {
                if name == full or key in codes and (context == "AU" or key in AU_CODES_ALONE) {
                    return zone;
                }
            }
        }
    }
    return "";
}

impl zone_for(
    location: builtins.str = "", country: builtins.str = "", point: builtins.str = ""
) -> builtins.str {
    return _resolve(location, country, point)[0];
}

impl _country(
    parts: builtins.list[builtins.str], coords=None, hint: builtins.str = ""
) -> builtins.tuple[builtins.str, builtins.bool] {
    text_country: any = _country_in(parts);
    code: any = "" if text_country else _ambiguous_code(parts);
    if not code {
        return (text_country, False);
    }
    home: any = REGION_COUNTRY[code];
    if hint {
        return (hint, False);
    }
    if coords {
        as_region: any = _region(parts, home, "");
        as_country: any = _country_zone(code, coords);
        return (
            home
                if as_region and _ref_km(coords, as_region) <= _ref_km(coords, as_country)
                else code,
            False,
        );
    }
    return (home if home == "US" else code, True);
}

impl country_for(
    location: builtins.str = "", point: builtins.str = ""
) -> builtins.tuple[builtins.str, builtins.bool] {
    parts: any = _parts(location);
    coords: any = _point(point);
    country: any;
    guessed: any;
    (country, guessed) = _country(parts, coords) as any;
    if guessed {
        return (country, False);
    }
    ambiguous: any = "" if _country_in(parts) else _ambiguous_code(parts);
    if ambiguous and coords {
        region_zone: any = _region(parts, REGION_COUNTRY[ambiguous], "");
        country_zone: any = _country_zone(ambiguous, coords);
        if min(_ref_km(coords, region_zone), _ref_km(coords, country_zone)) > MAX_REGION_KM {
            return ("", False);
        }
    }
    zone: any = _region(parts, country, "");
    if zone and coords and _ref_km(coords, zone) > MAX_REGION_KM {
        zone = "";
        if country == "US" {
            country = "";
        }
    }
    if zone {
        country = country or zone_country(zone);
    }
    return (country, `bool(country));
}

impl _resolve(
    location: builtins.str = "", country: builtins.str = "", point: builtins.str = ""
) -> builtins.tuple[builtins.str, builtins.bool] {
    parts: any = _parts(location);
    coords: any = _point(point);
    hint: any = country_code(country);
    text_country: any;
    guessed: any;
    (text_country, guessed) = _country(parts, coords, hint) as any;
    zone: any = _region(parts, text_country, hint);
    if zone and coords and _km(coords, _zone_points().get(zone, coords)) > MAX_REGION_KM {
        zone = "";
        if text_country == "US" {
            text_country = "";
        }
    }
    if zone {
        return (zone, guessed);
    }
    named: any = text_country or hint;
    if named {
        zone = _country_zone(named, coords);
        return (zone, guessed or `bool(zone) and _main_zone_only(named, coords));
    }
    if coords {
        return (_nearest(coords, max_km=MAX_NEAREST_KM), False);
    }
    return ("", False);
}

impl _clock(value: builtins.str) -> time {
    return time.fromisoformat(value);
}

impl _localize(tz, naive: datetime) -> datetime {
    try {
        return tz.localize(naive, is_dst=None);
    } except pytz.AmbiguousTimeError {
        return tz.localize(naive, is_dst=True);
    } except pytz.NonExistentTimeError {
        return tz.normalize(tz.localize(naive, is_dst=False));
    }
}

impl _bounds(tz, day, window) -> builtins.tuple[datetime, datetime] {
    return (
        _localize(tz, datetime.combine(day, _clock(window.start))),
        _localize(tz, datetime.combine(day, _clock(window.end))),
    );
}

impl in_window(at: datetime, zone: builtins.str, window) -> builtins.bool {
    tz: any = pytz.timezone(zone);
    local: any = pytz.utc.localize(at).astimezone(tz);
    if window.weekdays_only and local.weekday() >= 5 {
        return False;
    }
    opens: any;
    closes: any;
    (opens, closes) = _bounds(tz, local.date(), window) as any;
    return operator.le(opens, local) and operator.lt(local, closes);
}

impl next_send_time(after: datetime, zone: builtins.str, window, rng=None) -> datetime {
    tz: any = pytz.timezone(zone);
    local: any = pytz.utc.localize(after).astimezone(tz);
    for offset in range(8) {
        day: any = local.date() + timedelta(days=offset);
        if window.weekdays_only and day.weekday() >= 5 {
            continue;
        }
        opens: any;
        closes: any;
        (opens, closes) = _bounds(tz, day, window) as any;
        if local >= closes {
            continue;
        }
        if local >= opens {
            return after;
        }
        spread: any = min(START_SPREAD, (closes - opens) / 4).total_seconds();
        when: any = opens + timedelta(seconds=(rng or random).uniform(0, spread));
        return when.astimezone(pytz.utc).replace(tzinfo=None);
    }
    raise ValueError("send window never opens");
}

impl _prospect_country(config) -> builtins.str {
    compliance: any = getattr(config, "compliance", None);
    precleared: any = getattr(compliance, "precleared", None);
    return country_code(getattr(precleared, "prospect_country", ""));
}

impl icp_country(config) -> builtins.str {
    icp: any = getattr(config, "icp", None);
    coords: any = getattr(icp, "geo_coordinates", None) or {};
    found: any = set[any]();
    for place in getattr(icp, "geography", None) or [] {
        country: any;
        certain: any;
        (country, certain) = country_for(place, coords.get(place, "")) as any;
        if not certain {
            return "";
        }
        found.add(country);
    }
    return found.pop() if len(found) == 1 else "";
}

impl _place(state, prospect) -> builtins.tuple[builtins.str, builtins.str] {
    location: any = "";
    if getattr(prospect, "company_id", "") {
        company: any = await state.get_company(prospect.company_id);
        location = getattr(company, "location", "") or "" if company else "";
    }
    point: any = "";
    if location.strip() {
        cached: any = await state.get_setting("geo:" + location.strip().lower());
        point = "" if not cached or cached == "-" else cached;
    }
    return (location, point);
}

impl recipient_country(state, prospect) -> builtins.str {
    if prospect is None {
        return "";
    }
    location: any;
    point: any;
    (location, point) = await _place(state, prospect) as any;
    country: any;
    certain: any;
    (country, certain) = country_for(location, point) as any;
    if certain {
        return country;
    }
    return "";
}

impl recipient_zone(state, prospect, config, country: builtins.str = "") -> builtins.str {
    if prospect is None {
        return "";
    }
    if getattr(prospect, "timezone", "") {
        return prospect.timezone;
    }
    location: any;
    point: any;
    (location, point) = await _place(state, prospect) as any;
    zone: any;
    guessed: any;
    (zone, guessed) = _resolve(location, country_code(country), point) as any;
    if zone and not guessed {
        prospect.timezone = zone;
        await state.set_prospect_timezone(prospect.id, zone);
        return zone;
    }
    fallback: any = _prospect_country(config);
    if fallback and not country_code(country) {
        return _resolve(location, fallback, point)[0] or zone;
    }
    return zone;
}
