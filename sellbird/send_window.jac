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

def _regions(text: str) -> dict[str, tuple[str, str]];

def _pairs(text: str) -> dict[str, str];

def _clean(text: str) -> str;

@lru_cache(maxsize=1)
def _country_names -> dict[str, any];

@lru_cache(maxsize=1)
def _zone_points -> dict[str, tuple[float, float]];

def _iso6709(text: str) -> tuple[float, float] | None;

def _km(a: tuple[float, float], b: tuple[float, float]) -> float;

def _nearest(point: any, zones: any = None, max_km: float | None = None) -> str;

def _point(text: str) -> tuple[float, float] | None;
def country_code(value: any) -> str;

@lru_cache(maxsize=1)
def _zone_countries -> dict[str, str];
def zone_country(zone: str) -> str;

def _one_offset(zones: list[str]) -> bool;

def _country_zone(code: str, point: any = None) -> str;

def _parts(location: str) -> list[str];

def _codes(part: str) -> list[str];

def _country_in(parts: list[str]) -> str;

def _ambiguous_code(parts: list[str]) -> str;

def _ref_km(point: any, zone: str) -> float;

def _region(parts: list[str], text_country: str, hint: str) -> str;
def zone_for(location: str = "", country: str = "", point: str = "") -> str;

def _country(parts: list[str], coords: any = None, hint: str = "") -> tuple[str, bool];
def country_for(location: str = "", point: str = "") -> tuple[str, bool];

def _resolve(location: str = "", country: str = "", point: str = "") -> tuple[str, bool];

def _localize(tz: any, naive: datetime) -> datetime;

def _bounds(tz: any, day: any, window: any) -> tuple[datetime, datetime];
def in_window(at: datetime, zone: str, window: any) -> bool;
def next_send_time(after: datetime, zone: str, window: any, rng: any = None) -> datetime;

def icp_country(config: any) -> str;

async def _place(state: any, prospect: any) -> tuple[str, str];
async def recipient_country(state: any, prospect: any) -> str;
async def recipient_zone(state: any, prospect: any, config: any, country: str = "") -> str;
