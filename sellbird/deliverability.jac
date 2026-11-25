import re;
import from dataclasses { dataclass }
import from datetime { date, datetime }
import dns.exception;
import dns.resolver;
import httpx;

glob OK = "ok",
     WARN = "warn",
     FAIL = "fail",
     INFO = "info",
     COMMON_DKIM_SELECTORS = tuple(
         "google default selector1 selector2 k1 k2 s1 s2 mail dkim fm1 fm2 fm3 zoho zmail mxvault protonmail protonmail2 mandrill smtp sig1 everlytickey1".split(),
     ),
     DOMAIN_BLOCKLISTS = (
         ("dbl.spamhaus.org", "127.255.255.", "https://check.spamhaus.org"),
         ("multi.surbl.org", "127.0.0.1", "https://www.surbl.org/surbl-analysis"),
         ("multi.uribl.com", "127.0.0.1", "https://admin.uribl.com/"),
     ),
     IP_BLOCKLISTS = (
         ("zen.spamhaus.org", "127.255.255.", "https://check.spamhaus.org"),
         ("bl.spamcop.net", "", "https://www.spamcop.net/bl.shtml"),
     ),
     MIN_DOMAIN_AGE_DAYS = 30,
     GOOD_DOMAIN_AGE_DAYS = 90,
     MAX_BOUNCE_RATE = 0.03,
     MIN_SENDS_FOR_RATES = 20,
     MAX_WARMUP_SPAM = 0.05,
     MIN_WARMUP_SAMPLE = 20,
     DOMAIN_RE = re.compile(
         "^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\\.)+(?:[a-z]{2,63}|xn--[a-z0-9-]{1,59})$",
     ),
     _TEXT = {
         "unknown": "Couldn't look this up ({}). Check your connection and run again.",
         "mx_none": "No MX record - replies and bounces have nowhere to go.",
         "spf_none": "No SPF record. Add the TXT record your mail provider gives you.",
         "spf_many": "{} SPF records - receivers treat that as no SPF. Merge them.",
         "spf_lookups": "{} DNS lookups (limit is 10) - SPF will permerror.",
         "spf_no_all": "No 'all' at the end, so it ends neutral; add '~all': {}",
         "dmarc_none": "No DMARC record. Gmail and Yahoo require one for bulk senders. Start with TXT _dmarc.{0} = \"v=DMARC1; p=none; rua=mailto:you@{0}\"",
         "dmarc_many": "{} DMARC records - receivers ignore them all. Keep one.",
         "dmarc_no_p": "No p= policy tag - add p=none to start: {}",
         "dmarc_p_none": "p=none (monitoring only) - fine while warming; move to quarantine once reports look clean. {}",
         "dkim_none": "No key at any common selector. If your provider uses a custom one, set channels.email.warmup.dkim_selector; otherwise turn DKIM on in your provider.",
         "age_new": "{} - brand-new domains are distrusted; warm only, no cold email yet.",
         "refused": "list refused the query (common via public DNS like 8.8.8.8) - check manually at {}",
         "ramp_instantly": "Sellbird's ramp doesn't apply to Instantly: use Instantly's own warmup and per-account daily limit.",
         "ramp_unset": "No warmup start date set, so sends aren't ramped. Once your warmup service is on, set channels.email.warmup.start_date: YYYY-MM-DD.",
         "ramp_early": "Day {} of {} - warming only, no cold email until {} more day(s) pass.",
         "ramp_zero": "Today's cold cap is 0 and won't grow: raise start_sends or daily_increase.",
         "ramp_ok": "Day {}: today's cap is {}/day ({}). Keep the warmup service running alongside Sellbird.",
         "ti_other": "Using another warmup service: check its dashboard for the inbox rate before cold email.",
         "ti_none": "Not connected, so Sellbird can't see whether this mailbox is warmed. We recommend TrulyInbox: it warms the mailbox, keeps it healthy, and Sellbird reads its inbox rate here. {} {} Then run: sellbird trulyinbox connect",
         "ti_missing": "{} isn't in your TrulyInbox account yet. Add it in TrulyInbox to start its warmup.",
         "ti_login": "TrulyInbox can't sign in to {}. Reconnect the mailbox in TrulyInbox.",
         "ti_off": "Warmup isn't on for {}. Turn it on in TrulyInbox.",
         "ti_hint": " Set channels.email.warmup.start_date: {} so Sellbird ramps cold email from it.",
         "ti_spam": "{}% spam in warmup over the last 14 days. Keep warming and hold cold email until it's under {}%.",
         "ti_inbox": ", {}% inbox over the last 14 days",
         "ti_few": "TrulyInbox sent {} warmup emails in the last 14 days: not enough to judge yet. Check that warmup is running and keep warming before cold email.",
         "ti_ok": "TrulyInbox: warmed, day {}{}. Keep it running alongside Sellbird.",
         "bounce_few": "{} bounces / {} sent - too few sends to judge yet.",
     };

@dataclass
class Check {
    has name: str,
        status: str,
        detail: str,
        unknown: bool = False;
}

class LookupFailed(Exception) {}

def _resolve(name: str, rtype: str) -> any;

def _txt(name: str) -> list[str];

def _a(name: str) -> list[str];

def _unknown(name: str, e: any) -> Check;

def check_mx(domain: str) -> Check;

def _records(name: str, label: str, prefix: str) -> any;

def check_spf(domain: str) -> Check;

def check_dmarc(domain: str) -> Check;

def check_dkim(domain: str, selector: str = "") -> Check;

def check_domain_age(domain: str) -> Check;

def _refused(hits: list[str], refusal: str) -> bool;

def _blocklist_checks(query: str, label: str, lists: any) -> list[Check];

def check_domain_blocklists(domain: str) -> list[Check];

def check_ip_blocklists(smtp_host: str) -> list[Check];

def check_warmup(warmup: any, ceiling: int, today: date | None = None, provider: str = "") -> Check;

def check_warmup_service(
    health: any,
    warmup: any = None,
    *,
    error: str = "",
    other_service: bool = False,
    today: date | None = None,
) -> Check;

def check_send_history(total_sent: int, bounces: int) -> Check;
