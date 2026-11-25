"""Send windows in the recipient's own time zone.

With ``channels.email.send_window`` set, a cold email goes out only inside
that window (08:00 to 17:00 on weekdays by default) in the recipient's local
time, so a campaign that reaches New York and Oslo lands in office hours in
both. Replies are never held by the window; in quiet hours they wait for
the operator's own hours, as before. ``weekdays_only`` means Monday to
Friday everywhere.

The recipient's zone comes from what Sellbird already knows, in this order:

1. the company's location: a US state ("Austin, TX", "Brooklyn, New York"),
   a Canadian province or Australian state ("Toronto, ON, Canada",
   "Sydney NSW 2000"), or a country with a single time zone ("Oslo, Norway");
2. the coordinates discovery cached when it geocoded that location (the
   ``geo:<place>`` settings), for a country with several zones or a place
   given without its country;
3. the recipient's country as Precleared worked it out from the address,
   company records or the company's website, when the optional compliance
   check is on;
4. ``compliance.precleared.prospect_country``.

A country with several zones and nothing more specific gets its main zone
(MAIN_ZONE: Sydney for Australia, Moscow for Russia), except the US, which
has none. A main zone is used but not stored, so coordinates or a country
found later can still correct it. An empty location stays unresolved. Those recipients get the window in
``usage.quiet_hours.timezone``, which is what Sellbird did before. A resolved
zone is stored on the prospect, so it is worked out once (unless a country
found later could still change it; see ``recipient_zone``).

A code that is a state or province and a country too ("Berlin, DE",
"Mumbai, IN", "St. John's, NL", "Adelaide, SA") is settled by Precleared's
country, the cached coordinates or ``prospect_country``. With none of
those, a US state code reads as the state and any other as the country, and
that guess isn't stored. Writing the country out ("Berlin, Germany") always
works.

The same reading gives Precleared the recipient's country, when the check
is on (``recipient_country``). Only a country Sellbird is sure of goes: one
named in the location, the country of a state or province named there, a
code that is a region and a country too once nearby cached coordinates settle
it. A stored time zone alone has no country provenance and does not count.
A code read by convention alone, a state reading the coordinates
contradict, and coordinates by themselves (the nearest reference city can
be over a border) send nothing, because Precleared takes the country it is
given as settled, and a wrong one is worse than none. Without one,
``prospect_country`` or the one country every ``icp.geography`` entry is in
goes as a default Precleared uses only when its own lookups show nothing
(``icp_country``).
"""

import builtins;

import operator;

import math;

import random;

import re;

import unicodedata;

import from datetime { datetime, timedelta, time }

import from functools { lru_cache }

import pytz;

glob START_SPREAD: any;

glob MAX_NEAREST_KM: any;

glob MAX_REGION_KM: any;

glob US_STATES: any;

glob CA_PROVINCES: any;

glob AU_STATES: any;

glob CA_CODES_ALONE: any;

glob AU_CODES_ALONE: any;

glob MAIN_ZONE: any;

glob COUNTRY_ALIASES: any;

glob REGION_ALIASES: any;

glob REGION_COUNTRY: any;

with entry {
    START_SPREAD = timedelta(minutes=30);
    MAX_NEAREST_KM = 500;
    MAX_REGION_KM = 3000;
    US_STATES = {
        "AL": ("alabama", "America/Chicago"),
        "AK": ("alaska", "America/Anchorage"),
        "AZ": ("arizona", "America/Phoenix"),
        "AR": ("arkansas", "America/Chicago"),
        "CA": ("california", "America/Los_Angeles"),
        "CO": ("colorado", "America/Denver"),
        "CT": ("connecticut", "America/New_York"),
        "DE": ("delaware", "America/New_York"),
        "DC": ("district of columbia", "America/New_York"),
        "FL": ("florida", "America/New_York"),
        "GA": ("georgia", "America/New_York"),
        "HI": ("hawaii", "Pacific/Honolulu"),
        "ID": ("idaho", "America/Boise"),
        "IL": ("illinois", "America/Chicago"),
        "IN": ("indiana", "America/Indiana/Indianapolis"),
        "IA": ("iowa", "America/Chicago"),
        "KS": ("kansas", "America/Chicago"),
        "KY": ("kentucky", "America/New_York"),
        "LA": ("louisiana", "America/Chicago"),
        "ME": ("maine", "America/New_York"),
        "MD": ("maryland", "America/New_York"),
        "MA": ("massachusetts", "America/New_York"),
        "MI": ("michigan", "America/Detroit"),
        "MN": ("minnesota", "America/Chicago"),
        "MS": ("mississippi", "America/Chicago"),
        "MO": ("missouri", "America/Chicago"),
        "MT": ("montana", "America/Denver"),
        "NE": ("nebraska", "America/Chicago"),
        "NV": ("nevada", "America/Los_Angeles"),
        "NH": ("new hampshire", "America/New_York"),
        "NJ": ("new jersey", "America/New_York"),
        "NM": ("new mexico", "America/Denver"),
        "NY": ("new york", "America/New_York"),
        "NC": ("north carolina", "America/New_York"),
        "ND": ("north dakota", "America/Chicago"),
        "OH": ("ohio", "America/New_York"),
        "OK": ("oklahoma", "America/Chicago"),
        "OR": ("oregon", "America/Los_Angeles"),
        "PA": ("pennsylvania", "America/New_York"),
        "RI": ("rhode island", "America/New_York"),
        "SC": ("south carolina", "America/New_York"),
        "SD": ("south dakota", "America/Chicago"),
        "TN": ("tennessee", "America/Chicago"),
        "TX": ("texas", "America/Chicago"),
        "UT": ("utah", "America/Denver"),
        "VT": ("vermont", "America/New_York"),
        "VA": ("virginia", "America/New_York"),
        "WA": ("washington", "America/Los_Angeles"),
        "WV": ("west virginia", "America/New_York"),
        "WI": ("wisconsin", "America/Chicago"),
        "WY": ("wyoming", "America/Denver"),
    };
    CA_PROVINCES = {
        "AB": ("alberta", "America/Edmonton"),
        "BC": ("british columbia", "America/Vancouver"),
        "MB": ("manitoba", "America/Winnipeg"),
        "NB": ("new brunswick", "America/Moncton"),
        "NL": ("newfoundland and labrador", "America/St_Johns"),
        "NS": ("nova scotia", "America/Halifax"),
        "NT": ("northwest territories", "America/Edmonton"),
        "NU": ("nunavut", "America/Iqaluit"),
        "ON": ("ontario", "America/Toronto"),
        "PE": ("prince edward island", "America/Halifax"),
        "QC": ("quebec", "America/Toronto"),
        "SK": ("saskatchewan", "America/Regina"),
        "YT": ("yukon", "America/Whitehorse"),
    };
    AU_STATES = {
        "NSW": ("new south wales", "Australia/Sydney"),
        "VIC": ("victoria", "Australia/Melbourne"),
        "QLD": ("queensland", "Australia/Brisbane"),
        "WA": ("western australia", "Australia/Perth"),
        "SA": ("south australia", "Australia/Adelaide"),
        "TAS": ("tasmania", "Australia/Hobart"),
        "ACT": ("australian capital territory", "Australia/Sydney"),
        "NT": ("northern territory", "Australia/Darwin"),
    };
    CA_CODES_ALONE = {"AB", "BC", "MB", "NB", "NS", "ON", "QC"};
    AU_CODES_ALONE = {"NSW", "VIC", "QLD", "TAS", "ACT"};
    MAIN_ZONE = {
        "CL": "America/Santiago",
        "CN": "Asia/Shanghai",
        "EC": "America/Guayaquil",
        "ES": "Europe/Madrid",
        "NZ": "Pacific/Auckland",
        "PT": "Europe/Lisbon",
        "UA": "Europe/Kyiv",
        "AU": "Australia/Sydney",
        "BR": "America/Sao_Paulo",
        "CA": "America/Toronto",
        "ID": "Asia/Jakarta",
        "MX": "America/Mexico_City",
        "RU": "Europe/Moscow",
    };

    COUNTRY_ALIASES = {
        "uk": "GB",
        "united kingdom": "GB",
        "great britain": "GB",
        "britain": "GB",
        "england": "GB",
        "scotland": "GB",
        "wales": "GB",
        "northern ireland": "GB",
        "usa": "US",
        "us": "US",
        "united states of america": "US",
        "america": "US",
        "the netherlands": "NL",
        "holland": "NL",
        "deutschland": "DE",
        "south korea": "KR",
        "korea": "KR",
        "uae": "AE",
        "czechia": "CZ",
        "republic of ireland": "IE",
        "eire": "IE",
    };
    REGION_ALIASES = {"newfoundland": "NL", "labrador": "NL", "pei": "PE", "yukon territory": "YT"};
}

"""Lowercase, no accents or dots, single spaces: "Québec" -> "quebec"."""
def _clean(text: builtins.str) -> builtins.str;

@lru_cache(maxsize=1)
def _country_names -> builtins.dict[builtins.str, builtins.str];

"""Each zone's reference city, from the tz database's zone.tab."""
@lru_cache(maxsize=1)
def _zone_points -> builtins.dict[builtins.str, builtins.tuple[builtins.float, builtins.float]];

""""+5955+01045" or "+404251-0740023" -> (lat, lon) in degrees."""
def _iso6709(text: builtins.str) -> builtins.tuple[builtins.float, builtins.float] | None;

"""Great-circle distance in km."""
def _km(
    a: builtins.tuple[builtins.float, builtins.float],
    b: builtins.tuple[builtins.float, builtins.float],
) -> builtins.float;

"""The zone whose reference city is closest to ``point``, or ""."""
def _nearest(point, zones=None, max_km: builtins.float | None = None) -> builtins.str;

"""The "lat,lon" (optionally ",radius") discovery caches, or None."""
def _point(text: builtins.str) -> builtins.tuple[builtins.float, builtins.float] | None;

"""A two-letter country code the tz database knows ("uk" -> "GB"), or ""."""
def country_code(value) -> builtins.str;

"""Each zone's country, from the tz database: no zone is listed under two."""
@lru_cache(maxsize=1)
def _zone_countries -> builtins.dict[builtins.str, builtins.str];

"""The country a zone belongs to ("Europe/London" -> "GB"), or ""."""
def zone_country(zone: builtins.str) -> builtins.str;

"""True when every zone keeps the same clock all year (Berlin and
    Busingen), so the country effectively has one zone."""
def _one_offset(zones: builtins.list[builtins.str]) -> builtins.bool;

def _country_zone(code: builtins.str, point=None) -> builtins.str;

"""True when _country_zone can only give MAIN_ZONE's answer."""
def _main_zone_only(code: builtins.str, point=None) -> builtins.bool;

"""Comma-separated parts, last first, with postcodes dropped."""
def _parts(location: builtins.str) -> builtins.list[builtins.str];

with entry {
    REGION_COUNTRY = {
        **{code: "US" for code in US_STATES},
        **{code: "CA" for code in CA_PROVINCES},
        **{code: "AU" for code in AU_STATES},
    };
}

"""Upper-case words in a part, dots dropped: "D.C." -> "DC"."""
def _codes(part: builtins.str) -> builtins.list[builtins.str];

"""A country the location names without doubt, or ""."""
def _country_in(parts: builtins.list[builtins.str]) -> builtins.str;

"""The first code in the location that is a state or province and a
    country too ("Berlin, DE", "St. John's, NL"), or ""."""
def _ambiguous_code(parts: builtins.list[builtins.str]) -> builtins.str;

def _ref_km(point, zone: builtins.str) -> builtins.float;

"""The zone of a US state, Canadian province or Australian state named
    in the location, or "".

    ``text_country`` is a country written in the location itself, ``hint``
    one known from elsewhere. A two-letter code that is both a US state and
    a country ("DE", "IN") is read as the state, unless the hint says it's
    that country.
    """
def _region(
    parts: builtins.list[builtins.str], text_country: builtins.str, hint: builtins.str
) -> builtins.str;

"""The IANA time zone for a recipient, or "" when it can't be told.

    ``location`` is free text such as a company's address or "Denver, CO";
    ``country`` a two-letter code known from elsewhere (Precleared's answer
    or the configured prospect country); ``point`` the "lat,lon" discovery
    cached for the location. A state or country written in the location
    wins over ``country``.
    """
def zone_for(
    location: builtins.str = "", country: builtins.str = "", point: builtins.str = ""
) -> builtins.str;

"""The country the location's text puts the place in, or "", plus
    whether that was a guess: a code that is a region and a country, read
    by the US-first convention because nothing else said which."""
def _country(
    parts: builtins.list[builtins.str], coords=None, hint: builtins.str = ""
) -> builtins.tuple[builtins.str, builtins.bool];

"""The country a location puts a recipient in, and whether it is certain.

    Certain: a country named in the text, a US state, Canadian province or
    Australian state (by name or an unambiguous code), or a code that is a
    region and a country too settled by the cached coordinates. Not
    certain: that code read by convention alone (the reading comes back,
    marked so), a state reading the coordinates contradict, and the
    coordinates by themselves, which can put a place over a border. ""
    when nothing names one.
    """
def country_for(
    location: builtins.str = "", point: builtins.str = ""
) -> builtins.tuple[builtins.str, builtins.bool];

"""zone_for, plus whether the answer was a guess: a code that is a
    region and a country, read by the US-first convention because nothing
    else said which."""
def _resolve(
    location: builtins.str = "", country: builtins.str = "", point: builtins.str = ""
) -> builtins.tuple[builtins.str, builtins.bool];

def _clock(value: builtins.str) -> time;

"""A local wall-clock time as an aware datetime, through DST changes:
    a time skipped in spring becomes the moment after the gap, and a time
    that happens twice in autumn is the first of the two."""
def _localize(tz, naive: datetime) -> datetime;

def _bounds(tz, day, window) -> builtins.tuple[datetime, datetime];

"""Whether ``at`` (naive UTC) falls inside the window in ``zone``."""
def in_window(at: datetime, zone: builtins.str, window) -> builtins.bool;

"""The first moment at or after ``after`` (naive UTC) inside the window
    in ``zone``, as naive UTC. Inside the window already: ``after`` itself.
    Otherwise the next opening, plus up to START_SPREAD so a batch moved to
    the same morning doesn't all go at once."""
def next_send_time(after: datetime, zone: builtins.str, window, rng=None) -> datetime;

def _prospect_country(config) -> builtins.str;

"""The one country every ``icp.geography`` entry is certainly in, or "".

    Precleared's default when ``prospect_country`` is unset: the ICP is
    where discovery looked. A default only, so Precleared's own finding
    still wins."""
def icp_country(config) -> builtins.str;

"""The company's location and the "lat,lon" discovery cached for it."""
async def _place(state, prospect) -> builtins.tuple[builtins.str, builtins.str];

"""The recipient's country when Sellbird is sure of it, for Precleared's
    ``recipient_country``; "" otherwise, since a guess sent as fact would
    override Precleared's own evidence. See ``country_for``."""
async def recipient_country(state, prospect) -> builtins.str;

"""This recipient's zone, worked out once and stored on the prospect.

    ``country`` is the recipient's country from Precleared, when a check
    returned one. Returns "" when nothing settles it."""
async def recipient_zone(state, prospect, config, country: builtins.str = "") -> builtins.str;
