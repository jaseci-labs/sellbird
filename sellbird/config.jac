import builtins;
import copy;
import logging;
import operator;
import os;
import re;
import shutil;
import unicodedata;
import yaml;
import from contextlib { contextmanager }
import from contextvars { ContextVar }
import from datetime { date as _date, datetime as _datetime, time as _time }
import from pathlib { Path }
import from dotenv { load_dotenv }
import from pydantic { BaseModel, PrivateAttr, TypeAdapter, ValidationError }
import from pydantic { create_model, field_validator, model_validator }

glob logger: any = logging.getLogger("sellbird.config"),
     PRECLEARED_ADDRESS_SOURCES: any = tuple("published bought scraped given unknown".split()),
     PRECLEARED_SENDER_COUNTRIES: any = tuple("GB US CA DE FR AU IE NL ES IT LV AE EG QA".split()),
     COUNTRY_ALIASES: any = {"UK": "GB", "USA": "US", "UAE": "AE"},
     DEFAULT_OPT_OUT_LINE: any = "Not interested? Just let me know and I won't email you again.",
     PREVIOUS_DEFAULT_OPT_OUT_LINE: any = "Not interested? Reply \"no thanks\" and I won't email again.",
     OPT_OUT_WORDS: any = tuple(
         "no thanks|no thank you|unsubscribe|stop|remove me|opt out".split("|")
     ),
     HEBREW_OPT_OUT_WORDS: any = tuple("הסר|הסירו|הסרה|לא תודה|הסירו אותי|תורידו אותי".split("|")),
     SPANISH_OPT_OUT_WORDS: any = ("no gracias", "baja", "darme de baja"),
     FRENCH_OPT_OUT_WORDS: any = tuple(
         "non merci|non, merci|arrêt|désabonner|désabonnement|désabonnez-moi|retirez-moi".split("|")
     ),
     _SAYS_IT_STOPS_RE: any = re.compile(
         "|".join([
             "\\b(?:stop|unsubscribe|opt[\\s-]?out|remove|no\\s+thanks|not\\s+interested|leave\\s+you\\s+(?:be|alone)|take\\s+you\\s+off|off\\s+(?:my|our|the)\\s+list|hear\\s+from\\s+(?:me|us)|no\\s+more\\s+e-?mails?|won[\\'’]?t\\s+(?:\\w+\\s+){0,2}(?:e-?mail|write|contact|reach|bother|follow|message|send)|(?:not|never)\\s+(?:\\w+\\s+){0,2}(?:e-?mail|contact|write|message)\\w*\\s+(?:you\\s+)?again)",
             "(?:הסר|להסיר|הסירו|הסרה|נסיר|לא,?\\s+תודה|להפסיק|אפסיק|תורידו|לא\\s+אפנה|לא\\s+אכתוב|לא\\s+אשלח)",
             "(?:\\bbaja\\b|no,?\\s+gracias|dejar[ée]?\\s+de|dejo\\s+de|no\\s+(?:le|te|les)\\s+(?:escribir|volver|molestar)|no\\s+volver[ée]|eliminar|quitar|\\bparar\\b)",
             "(?:\\bnon\\s+(?:ti|vi|le)\\s+(?:scriver[òo]|scrivo|contatter[òo]|contatto|disturber[òo]|disturbo|mander[òo]|mando|invier[òo]|invio)\\b|\\bnon\\s+(?:ricever\\w*|vuoi\\s+ricevere|volete\\s+ricevere)\\b|\\b(?:disiscri\\w+|rimuov\\w+|rimozione|cancell\\w+|togli\\w+)|\\bannull\\w*\\s+l[’']?\\s*iscrizione|\\bsmetto\\s+di\\b|\\bsmetter[òo]\\s+di\\b|\\bnon\\s+(?:ti\\s+|vi\\s+|le\\s+)?interess\\w+|\\bnon\\s+interessat\\w+|\\bstop\\b)",
         ]),
         re.IGNORECASE,
     ),
     _SAYS_IT_STOPS_FR_RE: any = re.compile(
         "(?:desabonn|desinscri|\\barret(?:e|er|ez|erai|erons)?\\b|\\bnon,?\\s+merci\\b|\\bpas\\s+interess|\\bn(?:e\\s+|')(?:vous\\s+|t'|te\\s+)?(?:ecri|contact|relanc|envo|enverr|derang|sollicit|importun|recevr)\\w*\\s+(?:plus|jamais|pas\\s+(?:a|de)\\s+nouveau)\\b|\\bne\\s+plus\\s+(?:jamais\\s+)?(?:vous\\s+|t'|te\\s+|m'|me\\s+)?(?:ecrire|contacter|relancer|recevoir|solliciter|deranger|etre\\s+(?:contacte|sollicite|relance))|\\bne\\s+(?:voulez|souhaitez|desirez|veux|veut)\\s+(?:plus|pas)\\s+(?:\\w+\\s+){0,2}?(?:recevoir|courriels?|messages?|nouvelles)|\\b(?:retir|enlev|supprim|ray)\\w*\\s+(?:\\w+\\s+){0,3}?(?:de|d'|des)\\s*(?:(?:la|ma|notre|votre|vos|nos|mes|cette|ses)\\s+)?(?:listes?|envois?|base|infolettre|courriels)|\\blaiss\\w*\\s+tranquilles?|\\bplus\\s+(?:jamais\\s+)?(?:de\\s+)?(?:courriels?|messages?|nouvelles)\\s+de\\s+(?:ma|notre)\\s+part)",
         re.IGNORECASE,
     ),
     _FRENCH_CLICK_RE: any = re.compile("\\bcliqu(?:ez|er|e)\\b", re.IGNORECASE),
     _HEBREW_CLICK_RE: any = re.compile(
         "(?<!\\w)ו?(?:לחצו|לחצי|לחץ\\s+(?:כאן|על)|הקליקו|הקליקי|הקלק)(?!\\w)"
     ),
     BRAIN_PROVIDERS: any = ("claude", "codex"),
     CODEX_REASONING_EFFORTS: any = tuple("minimal low medium high xhigh".split()),
     _MODEL_NAME_RE: any = re.compile("^[A-Za-z0-9][A-Za-z0-9._:/\\[\\]-]{0,127}$"),
     MAX_EMAIL_RULES_CHARS: any = 20000,
     _CURRENT_CONFIG: any = ContextVar("sellbird_config", default=None),
     _APPROVAL_LINE_RE: any = re.compile(
         "^(?P<lead>[ \\t]*require_approval[ \\t]*:[ \\t]*)(?P<val>[^\\s#]+)", re.MULTILINE
     ),
     _EMAIL_KEY_RE: any = re.compile(
         "^(?P<ind>[ \\t]+)email[ \\t]*:[ \\t]*(?:#.*)?$", re.MULTILINE
     ),
     _mode_cache: dict[str, any] = {},
     _dnc_cache: dict[str, any] = {},
     EnvConfig: any = create_model(
         "EnvConfig",
         **{
             k: (int, int(d)) if d else (str, "")
             for (k, _, d) in [
                 w.partition("=")
                 for w in "instantly_api_key dataforseo_login dataforseo_password dataforseo_sandbox linkedin_email linkedin_password hunter_api_key serper_api_key scavio_api_key tinyfish_api_key reoon_api_key zerobounce_api_key gmail_client_id gmail_client_secret smtp_host smtp_port=587 smtp_username smtp_password imap_host imap_port=993 imap_username imap_password m365_client_id m365_tenant_id precleared_api_key".split()
             ]
         },
     );

def _need(ok: any, msg: str, v: any) -> any;

def _one_of(v: str, allowed: any, what: str) -> str;

def _parses(kind: any, v: str) -> bool;

class ConfigError(Exception) {}

class ConfigFileNotFoundError(ConfigError, FileNotFoundError) {}

class EmailRulesError(ConfigError) {}

class PersonaConfig(BaseModel) {
    has name: str,
        company: str,
        role: str,
        email: str,
        linkedin: str,
        tone: str;
}

class OfferConfig(BaseModel) {
    has primary: str = "",
        `entry: str = "",
        entry_ideas: list[str] = [],
        goal: str = "book_call",
        booking_method: str = "calendar_link",
        booking_url: str = "",
        meeting_duration: str = "15 minutes",
        meeting_owner: str = "";
}

class ProductConfig(BaseModel) {
    has name: str,
        description: str,
        pricing: str,
        key_benefits: list[str],
        objection_responses: dict[str, str],
        offer: OfferConfig = OfferConfig();
}

class ICPConfig(BaseModel) {
    has industries: list[str],
        company_size: str,
        titles: list[str],
        geography: list[str],
        hiring_signals: list[str] = [],
        geo_coordinates: dict[str, str] = {},
        keyword_variants: dict[str, list[str]] = {};
}

class WarmupConfig(BaseModel) {
    has start_date: str = "",
        min_days: int = 14,
        start_sends: int = 5,
        daily_increase: int = 3,
        dkim_selector: str = "";

    @field_validator(
        "start_date", "min_days", "start_sends", "daily_increase", "dkim_selector", mode="before"
    )
    @builtins.classmethod
    class def _blank_is_default(v: any, info: any) -> any;

    @field_validator("start_date", "min_days", "start_sends", "daily_increase")
    @builtins.classmethod
    class def _valid(v: any, info: any) -> any;

    def days_in(today: _date | None = None) -> int | None;

    def daily_cap(ceiling: int, today: _date | None = None) -> int;
}

class SendWindowConfig(BaseModel) {
    has start: str = "08:00",
        end: str = "17:00",
        weekdays_only: bool = True,
        recipient_timezone: bool = True;

    @field_validator("start", "end", mode="before")
    @builtins.classmethod
    class def _valid_clock(v: any, info: any) -> any;

    @model_validator(mode="after")
    def _start_before_end -> any;
}

class SignatureConfig(BaseModel) {
    has logo: str = "",
        width: int = 120,
        alt: str = "",
        link: str = "",
        direction: str = "auto";

    @field_validator("logo", "alt", "link", "direction", mode="before")
    @builtins.classmethod
    class def _blank_is_empty(v: any, info: any) -> any;

    @field_validator("width", "link")
    @builtins.classmethod
    class def _valid(v: any, info: any) -> any;
}

class EmailChannelConfig(BaseModel) {
    has enabled: bool = True,
        provider: str = "instantly",
        max_daily_sends: int = 50,
        per_inbox_daily_cap: int = 30,
        send_to_risky: bool = False,
        min_write_score: int = 0,
        require_approval: bool = True,
        link_domains: list[str] = [],
        phone_numbers: list[str] = [],
        max_bounce_rate: float = 0.05,
        follow_ups: bool = True,
        warmup: WarmupConfig = WarmupConfig(),
        send_window: SendWindowConfig | None = None,
        signature: SignatureConfig = SignatureConfig();

    @field_validator("warmup", "signature", mode="before")
    @builtins.classmethod
    class def _blank_section(v: any, info: any) -> any;

    @field_validator("max_daily_sends", "per_inbox_daily_cap")
    @builtins.classmethod
    class def _valid_caps(v: any, info: any) -> any;

    def cold_daily_cap(today: _date | None = None) -> int;
}

class LinkedInChannelConfig(BaseModel) {
    has enabled: bool = False,
        max_daily_connections: int = 20,
        max_daily_messages: int = 10;
}

class ChannelsConfig(BaseModel) {
    has email: EmailChannelConfig = EmailChannelConfig(),
        linkedin: LinkedInChannelConfig = LinkedInChannelConfig();
}

class PreclearedConfig(BaseModel) {
    has enabled: bool = False,
        sender_country: str = "",
        address_source: str = "unknown",
        prospect_country: str = "";

    @field_validator("sender_country", "address_source", "prospect_country", mode="before")
    @builtins.classmethod
    class def _clean(v: any, info: any) -> str;

    @model_validator(mode="after")
    def _country_when_enabled -> any;
}

class ComplianceConfig(BaseModel) {
    has precleared: PreclearedConfig = PreclearedConfig(),
        postal_address: str = "",
        opt_out_line: str = DEFAULT_OPT_OUT_LINE,
        do_not_contact: list[str] = [];

    @field_validator("postal_address", "opt_out_line", "do_not_contact", mode="before")
    @builtins.classmethod
    class def _blank_is_empty(v: any, info: any) -> any;

    @field_validator("opt_out_line")
    @builtins.classmethod
    class def _recognisable_opt_out(v: str) -> str;
}

class QuietHoursConfig(BaseModel) {
    has start: str = "22:00",
        end: str = "07:00",
        timezone: str = "America/New_York";

    @field_validator("start", "end", "timezone")
    @builtins.classmethod
    class def _valid(v: str, info: any) -> str;
}

class UsageConfig(BaseModel) {
    has max_daily_claude_percent: float = 80.0,
        heartbeat_interval_minutes: int = 15,
        quiet_hours: QuietHoursConfig = QuietHoursConfig();

    @field_validator("max_daily_claude_percent", "heartbeat_interval_minutes")
    @builtins.classmethod
    class def _valid(v: any, info: any) -> any;
}

class BrainConfig(BaseModel) {
    has provider: str = "claude",
        model: str = "",
        reasoning_effort: str = "";

    @field_validator("provider", "model", "reasoning_effort", mode="before")
    @builtins.classmethod
    class def _valid(v: any, info: any) -> str;
}

class WriterConfig(BaseModel) {
    has humanizer: bool = False,
        email_rules: str = "",
        site_facts: bool = True,
        require_tip: bool = False;

    @field_validator("email_rules", mode="before")
    @builtins.classmethod
    class def _blank_rules(v: any) -> any;
}

class HandoffConfig(BaseModel) {
    has mcp_url: str = "",
        mcp_command: list[str] = [],
        token_env: str = "",
        tool: str = "",
        arguments: builtins.dict = {};
}

class SellbirdConfig(BaseModel) {
    has persona: PersonaConfig,
        product: ProductConfig,
        icp: ICPConfig,
        channels: ChannelsConfig = ChannelsConfig(),
        usage: UsageConfig = UsageConfig(),
        brain: BrainConfig = BrainConfig(),
        compliance: ComplianceConfig = ComplianceConfig(),
        writer: WriterConfig = WriterConfig(),
        handoff: HandoffConfig = HandoffConfig(),
        _source_path: str | None = PrivateAttr(default=None);
}

def _email_of(config: any) -> any;

def send_window_of(config: any) -> any;

def operator_timezone(config: any) -> str;

def cold_daily_cap(email_config: any, today: _date | None = None) -> int;

def legacy_sending_held(config: any) -> bool;

def sending_notice(config: any) -> str;

def normalize_prospect_country(v: any) -> str;

def _fold_accents(text: str) -> str;

def compliance_of(config: any) -> ComplianceConfig;

def compliance_footer_lines(config: any) -> list[str];

def compliance_notice(config: any) -> str;

def load_email_rules(config: any) -> str;

def _format_validation_error(e: ValidationError) -> str;

@contextmanager
def use_config(config: SellbirdConfig) -> Generator[any, any, any];

def current_config -> any;

def load_config(config_path: str | None = None) -> SellbirdConfig;

def load_brain_config(config_path: str | None = None) -> BrainConfig;

def load_env -> any;

def _email_section(data: any) -> any;

def _with_approval_line(raw: str, word: str) -> list[str];

def set_require_approval(value: bool, path: any = None) -> Path;

def _reread(cache: dict[str, any], path: any, read: any) -> any;

def _read_mode(target: any) -> any;

def _read_dnc(target: any) -> any;

def refresh_sending_mode(config: any, path: any = None) -> bool;

def live_do_not_contact(config: any) -> list[str];

def do_not_contact_from_file(path: any = None) -> list[str];

def _find_config_file -> str;
