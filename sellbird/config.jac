"""Configuration loader for Sellbird. Reads sellbird.yaml + .env."""

import builtins;

import operator;

import logging;

import os;

import re;

import unicodedata;

import from contextlib { contextmanager }

import from contextvars { ContextVar }

import from datetime { date as _date, time as _time }

import from pathlib { Path }

import from typing { Iterator }

import yaml;

import from dotenv { load_dotenv }

import from pydantic {
    BaseModel,
    PrivateAttr,
    TypeAdapter,
    ValidationError,
    field_validator,
    model_validator,
}

glob logger: any = logging.getLogger("sellbird.config");

glob PRECLEARED_ADDRESS_SOURCES: any = ("published", "bought", "scraped", "given", "unknown");

glob PRECLEARED_SENDER_COUNTRIES: any = (
    "GB",
    "US",
    "CA",
    "DE",
    "FR",
    "AU",
    "IE",
    "NL",
    "ES",
    "IT",
    "LV",
    "AE",
    "EG",
    "QA",
);

glob COUNTRY_ALIASES: any = {"UK": "GB", "USA": "US", "UAE": "AE"};

glob DEFAULT_OPT_OUT_LINE: any = "Not interested? Just let me know and I won't email you again.";

glob PREVIOUS_DEFAULT_OPT_OUT_LINE: any = "Not interested? Reply \"no thanks\" and I won't email again.";

glob OPT_OUT_WORDS: any = (
    "no thanks",
    "no thank you",
    "unsubscribe",
    "stop",
    "remove me",
    "opt out",
);

glob HEBREW_OPT_OUT_WORDS: any = ("הסר", "הסירו", "הסרה", "לא תודה", "הסירו אותי", "תורידו אותי");

glob SPANISH_OPT_OUT_WORDS: any = ("no gracias", "baja", "darme de baja");

glob FRENCH_OPT_OUT_WORDS: any = (
    "non merci",
    "non, merci",
    "arrêt",
    "désabonner",
    "désabonnement",
    "désabonnez-moi",
    "retirez-moi",
);

glob _SAYS_IT_STOPS_RE: any = re.compile(
    "\\b(?:stop|unsubscribe|opt[\\s-]?out|remove|no\\s+thanks|not\\s+interested|leave\\s+you\\s+(?:be|alone)|take\\s+you\\s+off|off\\s+(?:my|our|the)\\s+list|hear\\s+from\\s+(?:me|us)|no\\s+more\\s+e-?mails?|won[\\'’]?t\\s+(?:\\w+\\s+){0,2}(?:e-?mail|write|contact|reach|bother|follow|message|send)|(?:not|never)\\s+(?:\\w+\\s+){0,2}(?:e-?mail|contact|write|message)\\w*\\s+(?:you\\s+)?again)",
    re.IGNORECASE,
);

glob _SAYS_IT_STOPS_HE_RE: any = re.compile(
    "(?:הסר|להסיר|הסירו|הסרה|נסיר|לא,?\\s+תודה|להפסיק|אפסיק|תורידו|לא\\s+אפנה|לא\\s+אכתוב|לא\\s+אשלח)",
);

glob _SAYS_IT_STOPS_ES_RE: any = re.compile(
    "(?:\\bbaja\\b|no,?\\s+gracias|dejar[ée]?\\s+de|dejo\\s+de|no\\s+(?:le|te|les)\\s+(?:escribir|volver|molestar)|no\\s+volver[ée]|eliminar|quitar|\\bparar\\b)",
    re.IGNORECASE,
);

glob _SAYS_IT_STOPS_IT_RE: any = re.compile(
    "(?:\\bnon\\s+(?:ti|vi|le)\\s+(?:scriver[òo]|scrivo|contatter[òo]|contatto|disturber[òo]|disturbo|mander[òo]|mando|invier[òo]|invio)\\b|\\bnon\\s+(?:ricever\\w*|vuoi\\s+ricevere|volete\\s+ricevere)\\b|\\b(?:disiscri\\w+|rimuov\\w+|rimozione|cancell\\w+|togli\\w+)|\\bannull\\w*\\s+l[’']?\\s*iscrizione|\\bsmetto\\s+di\\b|\\bsmetter[òo]\\s+di\\b|\\bnon\\s+(?:ti\\s+|vi\\s+|le\\s+)?interess\\w+|\\bnon\\s+interessat\\w+|\\bstop\\b)",
    re.IGNORECASE,
);

glob _SAYS_IT_STOPS_FR_RE: any = re.compile(
    "(?:desabonn|desinscri|\\barret(?:e|er|ez|erai|erons)?\\b|\\bnon,?\\s+merci\\b|\\bpas\\s+interess|\\bn(?:e\\s+|')(?:vous\\s+|t'|te\\s+)?(?:ecri|contact|relanc|envo|enverr|derang|sollicit|importun|recevr)\\w*\\s+(?:plus|jamais|pas\\s+(?:a|de)\\s+nouveau)\\b|\\bne\\s+plus\\s+(?:jamais\\s+)?(?:vous\\s+|t'|te\\s+|m'|me\\s+)?(?:ecrire|contacter|relancer|recevoir|solliciter|deranger|etre\\s+(?:contacte|sollicite|relance))|\\bne\\s+(?:voulez|souhaitez|desirez|veux|veut)\\s+(?:plus|pas)\\s+(?:\\w+\\s+){0,2}?(?:recevoir|courriels?|messages?|nouvelles)|\\b(?:retir|enlev|supprim|ray)\\w*\\s+(?:\\w+\\s+){0,3}?(?:de|d'|des)\\s*(?:(?:la|ma|notre|votre|vos|nos|mes|cette|ses)\\s+)?(?:listes?|envois?|base|infolettre|courriels)|\\blaiss\\w*\\s+tranquilles?|\\bplus\\s+(?:jamais\\s+)?(?:de\\s+)?(?:courriels?|messages?|nouvelles)\\s+de\\s+(?:ma|notre)\\s+part)",
    re.IGNORECASE,
);

glob _FRENCH_CLICK_RE: any = re.compile("\\bcliqu(?:ez|er|e)\\b", re.IGNORECASE);

glob _HEBREW_CLICK_RE: any = re.compile(
    "(?<!\\w)ו?(?:לחצו|לחצי|לחץ\\s+(?:כאן|על)|הקליקו|הקליקי|הקלק)(?!\\w)"
);

glob BRAIN_PROVIDERS: any = ("claude", "codex");

glob CODEX_REASONING_EFFORTS: any = ("minimal", "low", "medium", "high", "xhigh");

glob _MODEL_NAME_RE: any = re.compile("^[A-Za-z0-9][A-Za-z0-9._:/\\[\\]-]{0,127}$");

glob MAX_EMAIL_RULES_CHARS: any = 20000;

glob _CURRENT_CONFIG: ContextVar["SellbirdConfig | None"];

glob _APPROVAL_LINE_RE: any;

glob _EMAIL_KEY_RE: any;

glob _mode_cache: builtins.dict[builtins.str, builtins.tuple[builtins.tuple, builtins.object]];

glob _dnc_cache: builtins.dict[builtins.str, builtins.tuple[builtins.tuple, builtins.list[builtins.str]
    | None]];

"""Raised when Sellbird's configuration is missing or invalid."""
obj ConfigError(Exception) {
    def __repr__ -> str;

    def __eq__(other: any) -> bool;

    def __hash__ -> int;
}

"""Config file is missing. Subclasses FileNotFoundError for
    backward compatibility with existing callers/tests."""
obj ConfigFileNotFoundError(ConfigError, FileNotFoundError) {
    def __repr__ -> str;

    def __eq__(other: any) -> bool;

    def __hash__ -> int;
}

class PersonaConfig(BaseModel) {
    has name: builtins.str;

    has company: builtins.str;

    has role: builtins.str;

    has email: builtins.str;

    has linkedin: builtins.str;

    has tone: builtins.str;
}

class OfferConfig(BaseModel) {
    has primary: builtins.str = "";

    has `entry: builtins.str = "";

    has entry_ideas: builtins.list[builtins.str] = [];

    has goal: builtins.str = "book_call";

    has booking_method: builtins.str = "calendar_link";

    has booking_url: builtins.str = "";

    has meeting_duration: builtins.str = "15 minutes";

    has meeting_owner: builtins.str = "";
}

class ProductConfig(BaseModel) {
    has name: builtins.str;

    has description: builtins.str;

    has pricing: builtins.str;

    has key_benefits: builtins.list[builtins.str];

    has objection_responses: builtins.dict[builtins.str, builtins.str];

    has offer: OfferConfig = OfferConfig();
}

class ICPConfig(BaseModel) {
    has industries: builtins.list[builtins.str];

    has company_size: builtins.str;

    has titles: builtins.list[builtins.str];

    has geography: builtins.list[builtins.str];

    has hiring_signals: builtins.list[builtins.str] = [];

    has geo_coordinates: builtins.dict[builtins.str, builtins.str] = {};

    has keyword_variants: builtins.dict[builtins.str, builtins.list[builtins.str]] = {};
}

"""Cold-email ramp for a new domain or mailbox.

    Sellbird doesn't run a warmup network itself; that needs a pool of real
    inboxes (Instantly, Lemwarm, Mailreach...). This is the other half: no
    cold email goes out for ``min_days`` after ``start_date``, then the cold
    cap climbs from ``start_sends`` by ``daily_increase`` a day until it
    reaches ``max_daily_sends``. Replies are never held. Empty
    ``start_date`` means no ramp.
    """
class WarmupConfig(BaseModel) {
    has start_date: builtins.str = "";

    has min_days: builtins.int = 14;

    has start_sends: builtins.int = 5;

    has daily_increase: builtins.int = 3;

    has dkim_selector: builtins.str = "";

    @field_validator("start_date", "dkim_selector", mode="before")
    @builtins.classmethod
    class def _blank_is_empty(v, info) -> any;

    @field_validator("min_days", "start_sends", "daily_increase", mode="before")
    @builtins.classmethod
    class def _blank_is_default(v, info) -> any;

    @field_validator("start_date")
    @builtins.classmethod
    class def _valid_date(v: builtins.str) -> builtins.str;

    @field_validator("min_days", "start_sends", "daily_increase")
    @builtins.classmethod
    class def _non_negative(v: builtins.int) -> builtins.int;

    """Days since warmup started, or None when no ramp is configured."""
    def days_in(today: _date | None = None) -> builtins.int | None;

    """Today's cold-email cap under the ramp (never above ``ceiling``)."""
    def daily_cap(ceiling: builtins.int, today: _date | None = None) -> builtins.int;
}

"""When cold email may go out, in each recipient's local time.

    Off unless ``channels.email.send_window`` is set. A cold email goes out
    only between ``start`` and ``end`` (on weekdays, with ``weekdays_only``)
    in the recipient's own time zone, worked out from what Sellbird knows
    about them (see sellbird/send_window.py). Recipients whose zone can't be
    told get the window in ``usage.quiet_hours.timezone``; so does everyone
    with ``recipient_timezone: false``. Follow-ups keep their delay_days and
    move into the window. Replies are never held.
    """
class SendWindowConfig(BaseModel) {
    has start: builtins.str = "08:00";

    has end: builtins.str = "17:00";

    has weekdays_only: builtins.bool = True;

    has recipient_timezone: builtins.bool = True;

    @field_validator("start", "end", mode="before")
    @builtins.classmethod
    class def _valid_clock(v, info) -> any;

    @model_validator(mode="after")
    def _start_before_end -> any;
}

"""The configured send window, or None when there isn't one."""
def send_window_of(config) -> "SendWindowConfig | None";

"""usage.quiet_hours.timezone: the zone Sellbird itself runs on."""
def operator_timezone(config) -> builtins.str;

"""A logo under every email (see sellbird/integrations/signature.py).

    Empty ``logo``: no signature, and email goes out as plain text, as
    before. Gmail, Microsoft and SMTP only.
    """
class SignatureConfig(BaseModel) {
    has logo: builtins.str = "";

    has width: builtins.int = 120;

    has alt: builtins.str = "";

    has link: builtins.str = "";

    has direction: builtins.str = "auto";

    @field_validator("logo", "alt", "link", mode="before")
    @builtins.classmethod
    class def _blank_is_empty(v) -> any;

    @field_validator("width")
    @builtins.classmethod
    class def _sane_width(v: builtins.int) -> builtins.int;

    @field_validator("link")
    @builtins.classmethod
    class def _web_link(v: builtins.str) -> builtins.str;

    @field_validator("direction", mode="before")
    @builtins.classmethod
    class def _known_direction(v) -> any;
}

class EmailChannelConfig(BaseModel) {
    has enabled: builtins.bool = True;

    has provider: builtins.str = "instantly";

    has max_daily_sends: builtins.int = 50;

    has per_inbox_daily_cap: builtins.int = 30;

    has send_to_risky: builtins.bool = False;

    has min_write_score: builtins.int = 0;

    has require_approval: builtins.bool = True;

    has link_domains: builtins.list[builtins.str] = [];

    has phone_numbers: builtins.list[builtins.str] = [];

    has max_bounce_rate: builtins.float = 0.05;

    has follow_ups: builtins.bool = True;

    has warmup: WarmupConfig = WarmupConfig();

    has send_window: SendWindowConfig | None = None;

    has signature: SignatureConfig = SignatureConfig();

    @field_validator("warmup", mode="before")
    @builtins.classmethod
    class def _blank_warmup(v) -> any;

    @field_validator("signature", mode="before")
    @builtins.classmethod
    class def _blank_signature(v) -> any;

    @field_validator("max_daily_sends")
    @builtins.classmethod
    class def _sends_non_negative(v: builtins.int) -> builtins.int;

    @field_validator("per_inbox_daily_cap")
    @builtins.classmethod
    class def _per_inbox_cap_range(v: builtins.int) -> builtins.int;

    """Today's cap on cold (sequence) email: max_daily_sends, throttled
        by the warmup ramp. Replies count only toward max_daily_sends."""
    def cold_daily_cap(today: _date | None = None) -> builtins.int;
}

"""cold_daily_cap for any email config, including ones without a ramp."""
def cold_daily_cap(email_config, today: _date | None = None) -> builtins.int;

"""True when Instantly is the provider and approval is required.

    Instantly has no per-email approval queue, so with require_approval on
    Sellbird holds campaign deployment and hands replies to a human.
    """
def legacy_sending_held(config) -> builtins.bool;

"""A plain-language warning when outbound sending is held by config, or ""."""
def sending_notice(config) -> builtins.str;

class LinkedInChannelConfig(BaseModel) {
    has enabled: builtins.bool = False;

    has max_daily_connections: builtins.int = 20;

    has max_daily_messages: builtins.int = 10;
}

class ChannelsConfig(BaseModel) {
    has email: EmailChannelConfig = EmailChannelConfig();

    has linkedin: LinkedInChannelConfig = LinkedInChannelConfig();
}

"""A two-letter country code ("us" -> "US", "UK" -> "GB"), or "" for none.

    Raises ValueError on anything else, including the booleans YAML makes of
    an unquoted NO (Norway) or ON, so a typo is never silently ignored.
    """
def normalize_prospect_country(v) -> builtins.str;

"""Optional per-recipient cold-email check through Precleared.

    Off by default. When on, each new recipient is checked once, before the
    first cold email, under the cold-email rules of the recipient's country
    (UK PECR, US CAN-SPAM, Canada's CASL, Germany's UWG, France's CPCE and
    the other countries in PRECLEARED_SENDER_COUNTRIES). Any verdict other
    than ok_to_email holds the email back with the reason. See
    sellbird/integrations/precleared.py.
    """
class PreclearedConfig(BaseModel) {
    has enabled: builtins.bool = False;

    has sender_country: builtins.str = "";

    has address_source: builtins.str = "unknown";

    has prospect_country: builtins.str = "";

    @field_validator("sender_country", mode="before")
    @builtins.classmethod
    class def _upper_country(v) -> builtins.str;

    @field_validator("address_source", mode="before")
    @builtins.classmethod
    class def _valid_source(v) -> builtins.str;

    @field_validator("prospect_country", mode="before")
    @builtins.classmethod
    class def _valid_prospect_country(v) -> builtins.str;

    @model_validator(mode="after")
    def _country_when_enabled -> any;
}

"""Latin accents dropped and curly apostrophes made straight, so French
    reads the same typed with or without them."""
def _fold_accents(text: builtins.str) -> builtins.str;

class ComplianceConfig(BaseModel) {
    has precleared: PreclearedConfig = PreclearedConfig();

    has postal_address: builtins.str = "";

    has opt_out_line: builtins.str = DEFAULT_OPT_OUT_LINE;

    has do_not_contact: builtins.list[builtins.str] = [];

    @field_validator("postal_address", "opt_out_line", mode="before")
    @builtins.classmethod
    class def _blank_is_empty(v) -> any;

    """One string is a list; blanks and duplicates are dropped.

        Normalising here rather than at the point of use keeps the gate's
        matching free of parsing, and means " @Acme.EXAMPLE " or a pasted
        "https://www.acme.example/" behaves the same as "acme.example". An
        entry that names no address or domain is an error, not a no-op.
        """
    @field_validator("do_not_contact", mode="before")
    @builtins.classmethod
    class def _clean_do_not_contact(v) -> any;

    @field_validator("opt_out_line")
    @builtins.classmethod
    class def _recognisable_opt_out(v: builtins.str) -> builtins.str;
}

"""The compliance section, or the defaults when a config has none."""
def compliance_of(config) -> ComplianceConfig;

"""The lines added under every cold email: address, then opt-out line."""
def compliance_footer_lines(config) -> builtins.list[builtins.str];

"""A plain-language warning when cold email goes out without a postal
    address, or "". Sending isn't held for it: this is the nudge."""
def compliance_notice(config) -> builtins.str;

class QuietHoursConfig(BaseModel) {
    has start: builtins.str = "22:00";

    has end: builtins.str = "07:00";

    has timezone: builtins.str = "America/New_York";

    @field_validator("start", "end")
    @builtins.classmethod
    class def _valid_time(v: builtins.str) -> builtins.str;

    @field_validator("timezone")
    @builtins.classmethod
    class def _valid_timezone(v: builtins.str) -> builtins.str;
}

class UsageConfig(BaseModel) {
    has max_daily_claude_percent: builtins.float = 80.0;

    has heartbeat_interval_minutes: builtins.int = 15;

    has quiet_hours: QuietHoursConfig = QuietHoursConfig();

    @field_validator("max_daily_claude_percent")
    @builtins.classmethod
    class def _valid_percent(v: builtins.float) -> builtins.float;

    @field_validator("heartbeat_interval_minutes")
    @builtins.classmethod
    class def _valid_interval(v: builtins.int) -> builtins.int;
}

"""Which subscription Sellbird thinks with.

    ``claude`` (default) runs Claude Code headless on your Claude plan.
    ``codex`` runs Codex on your ChatGPT plan. There is never an automatic
    fallback between them, and an explicit ``model`` only affects Sellbird —
    your own Claude Code / Codex settings are never read or changed.
    """
class BrainConfig(BaseModel) {
    has provider: builtins.str = "claude";

    has model: builtins.str = "";

    has reasoning_effort: builtins.str = "";

    @field_validator("provider", mode="before")
    @builtins.classmethod
    class def _valid_provider(v) -> builtins.str;

    @field_validator("model", mode="before")
    @builtins.classmethod
    class def _valid_model(v) -> builtins.str;

    @field_validator("reasoning_effort", mode="before")
    @builtins.classmethod
    class def _valid_effort(v) -> builtins.str;
}

class WriterConfig(BaseModel) {
    has humanizer: builtins.bool = False;

    has email_rules: builtins.str = "";

    has site_facts: builtins.bool = True;

    has require_tip: builtins.bool = False;

    @field_validator("email_rules", mode="before")
    @builtins.classmethod
    class def _blank_rules(v) -> any;
}

"""writer.email_rules names a file Sellbird can't use."""
obj EmailRulesError(ConfigError) {
    def __repr__ -> str;

    def __eq__(other: any) -> bool;

    def __hash__ -> int;
}

"""The operator's email rules (writer.email_rules), or "" when none are set.

    Raises EmailRulesError when a file is set but missing, unreadable, empty
    or too long: the Writer then writes nothing rather than fall back to the
    built-in shape the operator chose to replace.
    """
def load_email_rules(config) -> builtins.str;

"""Who gets a prospect who says yes to your offer (sellbird.handoff):
    one tool on another system's MCP server."""
class HandoffConfig(BaseModel) {
    has mcp_url: builtins.str = "";

    has mcp_command: builtins.list[builtins.str] = [];

    has token_env: builtins.str = "";

    has tool: builtins.str = "";

    has arguments: builtins.dict = {};
}

class SellbirdConfig(BaseModel) {
    has persona: PersonaConfig;

    has product: ProductConfig;

    has icp: ICPConfig;

    has channels: ChannelsConfig = ChannelsConfig();

    has usage: UsageConfig = UsageConfig();

    has brain: BrainConfig = BrainConfig();

    has compliance: ComplianceConfig = ComplianceConfig();

    has writer: WriterConfig = WriterConfig();

    has handoff: HandoffConfig = HandoffConfig();

    has _source_path: builtins.str | None = PrivateAttr(default=None);
}

class EnvConfig(BaseModel) {
    has instantly_api_key: builtins.str = "";

    has dataforseo_login: builtins.str = "";

    has dataforseo_password: builtins.str = "";

    has dataforseo_sandbox: builtins.str = "";

    has linkedin_email: builtins.str = "";

    has linkedin_password: builtins.str = "";

    has hunter_api_key: builtins.str = "";

    has serper_api_key: builtins.str = "";

    has scavio_api_key: builtins.str = "";

    has tinyfish_api_key: builtins.str = "";

    has reoon_api_key: builtins.str = "";

    has zerobounce_api_key: builtins.str = "";

    has gmail_client_id: builtins.str = "";

    has gmail_client_secret: builtins.str = "";

    has smtp_host: builtins.str = "";

    has smtp_port: builtins.int = 587;

    has smtp_username: builtins.str = "";

    has smtp_password: builtins.str = "";

    has imap_host: builtins.str = "";

    has imap_port: builtins.int = 993;

    has imap_username: builtins.str = "";

    has imap_password: builtins.str = "";

    has m365_client_id: builtins.str = "";

    has m365_tenant_id: builtins.str = "";

    has precleared_api_key: builtins.str = "";
}

"""Turn a pydantic ValidationError into a readable, actionable message."""
def _format_validation_error(e: ValidationError) -> builtins.str;

with entry {
    _CURRENT_CONFIG = ContextVar("sellbird_config", default=None);
}

"""Make ``config`` what ``load_config()`` returns, for this task and the
    threads it starts. A server keeping each workspace's settings somewhere
    other than a sellbird.yaml loads them and runs the work inside this."""
@contextmanager
def use_config(config: SellbirdConfig) -> Generator[any, any, any];

"""The config set with ``use_config``, or None when the file decides."""
def current_config -> "SellbirdConfig | None";

"""Load Sellbird configuration from YAML file.

    Raises ConfigError with a clear, actionable message on any problem.
    """
def load_config(config_path: builtins.str | None = None) -> SellbirdConfig;

"""Read just the ``brain:`` section, without validating the rest.

    Training runs before a product is configured (the template sellbird.yaml
    still has placeholder values), but it must still think with the
    provider the user chose. A missing file or section means the Claude
    default; an invalid section raises rather than silently switching
    providers.
    """
def load_brain_config(config_path: builtins.str | None = None) -> BrainConfig;

"""Load environment variables from .env file."""
def load_env -> EnvConfig;

with entry {
    _APPROVAL_LINE_RE = re.compile(
        "^(?P<lead>[ \\t]*require_approval[ \\t]*:[ \\t]*)(?P<val>[^\\s#]+)", re.MULTILINE
    );
    _EMAIL_KEY_RE = re.compile("^(?P<ind>[ \\t]+)email[ \\t]*:[ \\t]*(?:#.*)?$", re.MULTILINE);
}

def _email_section(data) -> any;

"""Ways to say require_approval: <word> in ``raw``: change the line that
    is there, or add one under an ``email:`` key."""
def _with_approval_line(raw: builtins.str, word: builtins.str) -> builtins.list[builtins.str];

"""Write channels.email.require_approval into the config file Sellbird
    reads (sellbird.local.yaml wins, as in load_config). Only that value
    changes: the result must parse to the same settings apart from it, or
    nothing is written and ConfigError says to set it by hand."""
def set_require_approval(value: builtins.bool, path=None) -> Path;

with entry {
    _mode_cache = {};
}

"""Bring a running config's require_approval in line with the file it was
    loaded from, so a switch made while Sellbird runs counts at once: the
    sender, writer and handler call this before they queue or send. Cheap:
    the file is only read again when it changed. True when the value
    changed. A config not loaded from a file, or a file that can't be read,
    leaves the running value alone."""
def refresh_sending_mode(config, path=None) -> builtins.bool;

with entry {
    _dnc_cache = {};
}

"""The do-not-contact list as the config file says it is now.

    Someone who sees an approved email to a company they must not contact
    adds it to the list while Sellbird runs; waiting for a restart would let
    that email go. Re-read only when the file changed (as refresh_sending_mode
    does). A file that can't be read, or a list with a mistake in it, keeps
    the last good list: never an empty one.
    """
def live_do_not_contact(config) -> builtins.list[builtins.str];

"""Just ``compliance.do_not_contact`` from a config file, validated.
    Raises on a file that can't be read or a list with a mistake in it."""
def do_not_contact_from_file(path=None) -> builtins.list[builtins.str];

"""Search for Sellbird's config.

    ``sellbird.local.yaml`` wins when present. It is gitignored, so a fork can
    carry a real product configuration (trained on an actual company) while
    the tracked ``sellbird.yaml`` stays an untrained template — nobody
    publishes their positioning, pricing, and prospect targeting by accident.
    """
def _find_config_file -> builtins.str;
