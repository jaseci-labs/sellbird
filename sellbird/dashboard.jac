import asyncio;
import builtins;
import csv;
import functools;
import io;
import ipaddress;
import json;
import logging;
import os;
import shutil;
import signal;
import sqlite3;
import stat;
import subprocess;
import sys;
import tempfile;
import uuid;
import from collections.abc { Sequence }
import from datetime { date, datetime, timedelta, timezone }
import from pathlib { Path }
import aiosqlite;
import httpx;
import uvicorn;
import yaml;
import from dotenv { load_dotenv }
import from fastapi { APIRouter, FastAPI, Request }
import from fastapi.responses { HTMLResponse, JSONResponse, PlainTextResponse, Response }
import from starlette.middleware { Middleware }
import from starlette.routing { Mount }

glob logger = logging.getLogger("sellbird.dashboard"),
     DB_PATH = PROJECT_ROOT / "data" / "sellbird.db",
     ENV_FILE = PROJECT_ROOT / ".env",
     CONFIG_FILE = PROJECT_ROOT / "sellbird.yaml",
     PID_FILE = PROJECT_ROOT / "data" / "sellbird.pid",
     LOG_FILE = PROJECT_ROOT / "data" / "sellbird.log",
     TOKEN_FILE = PROJECT_ROOT / "data" / "dashboard-token",
     AGENT_TOKEN_FILE = PROJECT_ROOT / "data" / "agent-token",
     app = FastAPI(title="Sellbird Dashboard", docs_url=None, redoc_url=None, openapi_url=None),
     token_store = auth.TokenStore(TOKEN_FILE),
     agent_token_store = auth.TokenStore(AGENT_TOKEN_FILE),
     _sellbird_process: any = None,
     _sellbird_started_at: any = None,
     _env_lock = asyncio.Lock(),
     _ENV_KEYS = ("INSTANTLY_API_KEY LINKEDIN_EMAIL LINKEDIN_PASSWORD CLOUDFLARE_ACCOUNT_ID CLOUDFLARE_API_TOKEN "
         "GMAIL_CLIENT_ID GMAIL_CLIENT_SECRET SMTP_HOST SMTP_PORT SMTP_USERNAME SMTP_PASSWORD IMAP_HOST "
         "IMAP_PORT IMAP_USERNAME IMAP_PASSWORD M365_CLIENT_ID M365_TENANT_ID REOON_API_KEY "
         "ZEROBOUNCE_API_KEY HUNTER_API_KEY").split(),
     _SECRET_KEYS = set(
         "INSTANTLY_API_KEY LINKEDIN_PASSWORD CLOUDFLARE_API_TOKEN GMAIL_CLIENT_SECRET SMTP_PASSWORD IMAP_PASSWORD REOON_API_KEY ZEROBOUNCE_API_KEY HUNTER_API_KEY".split(),
     ),
     _SIGN_IN_KEYS = ("GMAIL_CLIENT_ID", "GMAIL_CLIENT_SECRET", "M365_CLIENT_ID", "M365_TENANT_ID"),
     _PROVIDER_SETUP = {
         "gmail": "GMAIL_CLIENT_ID GMAIL_CLIENT_SECRET|gmail_token.json|Add your Google OAuth client ID and secret in Settings, then sign in on the Inboxes tab (or run 'sellbird gmail auth').",
         "microsoft": "M365_CLIENT_ID|m365_token.json|Add your Microsoft 365 client and tenant IDs in Settings, then sign in on the Inboxes tab (or run 'sellbird microsoft auth').",
         "smtp": "SMTP_HOST SMTP_USERNAME SMTP_PASSWORD||Enter your SMTP host, username, and password in Settings.",
     },
     _SETUP_CHECKS = [
         "venv|Python virtual environment|Run: python3 -m venv .venv && source .venv/bin/activate && pip install -e .|y",
         "env_file|Environment file (.env)|Go to the Settings tab to enter your API keys.|y",
         "email_provider|Email provider configured ({provider})|{provider_help}|y",
         "verifier|Email verification key|Add a Reoon (free 600/mo), ZeroBounce, or Hunter key in Settings — without one, found emails stay 'guess' and are never sent.|y",
         "config|Sellbird configured ({config})|Train Sellbird on your product. Use the trainer or set up manually through Claude.|y",
         "product_trained|Product knowledge trained|Run: sellbird train https://yourwebsite.com (or set up through Claude).|y",
         "linkedin|LinkedIn credentials|Optional. Enter your LinkedIn credentials in Settings to enable LinkedIn prospecting.|n",
         "cloudflare|Cloudflare deep crawling|Optional. For JavaScript-rendered website crawling during training.|n",
         "warmup_service|{warmup}|A new mailbox needs 2-4 weeks of warmup before cold email, and warmup keeps it out of spam after that. We recommend TrulyInbox: connect it and Sellbird shows whether your mailbox is warmed.|y",
     ],
     _NO_OFFERS = "Sellbird couldn't come up with offers just now. Try again.",
     _EMPTY: dict[str, any] = {},
     COMPANIES_TAB_LIMIT = 2000;

obj home_middleware {
    has app: any;

    async def __call__(scope: any, receive: any, send: any);
}

with entry {
    app.add_middleware(agent_policy.AgentPolicy);
    app.add_middleware(auth.DashboardGuard, store=token_store, agent_store=agent_token_store);
    app.add_middleware(home_middleware);
}

@app.exception_handler(NotOnHosted)
async def _not_on_hosted(request: Request, exc: NotOnHosted) -> any;

def _resolve_config_file -> Path;

def _refuse(message: str, code: int = 409) -> any;

def _error(message: str, code: int = 500) -> any;

def _csv(text: str, filename: str) -> any;

def _state -> any;

async def _open_state -> any;

async def _json(request: any, fallback: any = None) -> any;

async def _json_if_json(request: any) -> any;

def _loads(text: any, fallback: any) -> any;

def _words(value: any, limit: int) -> str;

async def query_db(sql: str, params: tuple[any, ...] = ()) -> list[any];

def _read_env_file -> dict[str, str];

def _env_key(line: str) -> str;

def _write_env_file(updates: dict[str, str]);

def _check_sellbird_pid -> int | None;

def _env_value(env_vars: dict[str, str], key: str) -> str;

def _has(env_vars: dict[str, str], keys: any) -> bool;

def _config_valid(config_path: any) -> bool;

@app.get("/api/setup-status")
async def get_setup_status -> any;

def _current_provider -> str;

@app.get("/api/settings")
async def get_settings -> any;

@app.post("/api/settings/env")
async def save_env_settings(request: Request) -> any;

@app.post("/api/trulyinbox/connect")
async def trulyinbox_connect(request: Request) -> any;

@app.get("/api/rename-notice")
async def get_rename_notice -> any;

@app.post("/api/rename-notice/dismiss")
async def dismiss_rename_notice -> any;

@app.post("/api/trulyinbox/other")
async def trulyinbox_other -> any;

def _offer_config_file -> Path;

async def _offer_brain -> tuple[any, any, any];

@app.get("/api/offer")
async def get_offer -> any;

@app.post("/api/offer/suggest")
async def suggest_offer -> any;

@app.post("/api/offer/preview")
async def preview_offer(request: Request) -> any;

@app.post("/api/offer")
async def save_offer_route(request: Request) -> any;

@app.get("/api/company")
async def get_company -> any;

@app.post("/api/company")
async def save_company_route(request: Request) -> any;

@app.post("/api/offer/propose")
async def propose_offer(request: Request) -> any;

@app.delete("/api/offer/propose")
async def dismiss_proposed_offer -> any;

@app.post("/api/settings/test-instantly")
async def test_instantly(request: Request) -> any;

@app.get("/api/companies")
async def get_companies -> any;

@app.get("/api/export/companies.csv")
async def export_companies -> any;

@app.get("/api/companies/{company_id}/profile")
async def get_company_profile(company_id: str) -> any;

@app.get("/api/companies/{company_id}/contacts")
async def get_company_contacts(company_id: str) -> any;

@app.post("/api/feedback")
async def add_feedback(request: Request) -> any;

@app.get("/api/feedback/{entity_type}/{entity_id}")
async def get_feedback(entity_type: str, entity_id: str) -> any;

@app.get("/api/sellbird/status")
async def get_sellbird_status -> any;

@app.post("/api/sellbird/start")
async def start_sellbird -> any;

def _alive(mine: any, pid: int) -> bool;

@app.post("/api/sellbird/stop")
async def stop_sellbird -> any;

@app.get("/api/sellbird/logs")
async def get_sellbird_logs -> any;

def _pipeline_bucket(
    status: str | None, stage: str | None, intent: str | None, email_status: str | None = None
) -> str;

async def _count_map(table: str) -> dict[any, any];

@app.get("/api/stats")
async def get_stats -> any;

glob _USAGE_SUM = ("COUNT(DISTINCT CASE WHEN session_id != '' THEN session_id ELSE id END) AS calls, "
         "COALESCE(SUM(input_tokens), 0) AS input_tokens, COALESCE(SUM(output_tokens), 0) AS output_tokens, "
         "COALESCE(SUM(cache_read_tokens), 0) AS cache_read_tokens, "
         "COALESCE(SUM(cache_creation_tokens), 0) AS cache_creation_tokens, "
         "ROUND(COALESCE(SUM(cost_usd), 0), 4) AS cost_usd"),
     _quota_clients: dict[any, any] = {};

def _active_brain -> any;

async def _brain_status -> dict[str, any];

def _active_provider -> str;

def _quota_client_for(provider: str, model: str = "") -> any;

def _usage_grouped(expr: str, alias: str) -> str;

@app.get("/api/usage")
async def get_usage -> any;

@app.get("/api/prospects")
async def get_prospects -> any;

glob OUTBOX_CONTEXT_SIGNALS = tuple(
         "TECH_STACK INCUMBENT_AGENCY HIRING_ROLE RUNNING_GOOGLE_ADS NO_ONLINE_BOOKING".split()
     ),
     HAND_SENDABLE_STATUSES = ("new", "queued"),
     HAND_SENDABLE_EMAIL = ("verified", "risky");

def _in(ids: any) -> str;

def _signal_value(r: dict[any, any]) -> str;

def _joined(values: any, sep: str = ", ") -> str;

async def _with_context(items: list[any]) -> list[any];

@app.get("/api/outbox")
async def get_outbox_api -> any;

@app.get("/api/sending-mode")
async def get_sending_mode -> any;

@app.post("/api/sending-mode")
async def set_sending_mode(request: Request) -> any;

@app.post("/api/outbox/approve-all")
async def outbox_approve_all -> any;

@app.post("/api/outbox/{item_id}/approve")
async def outbox_approve(item_id: str) -> any;

def _signed(text: str, kind: any) -> str;

@app.post("/api/outbox/{item_id}/edit")
async def outbox_edit(item_id: str, request: Request) -> any;

def _sellbird_can_send -> bool;

def _extra_inboxes_connected -> bool;

def _send_as -> str;

def _compliance_view -> dict[str, any];

async def _instantly_ids -> list[any];

async def _sellbird_committed_ids -> set[any];

def _is_str(value: any) -> bool;

async def _hand_sent_ids -> set[any];

async def _sellbird_sent_to(prospect_id: str) -> bool;

@app.post("/api/prospects/{prospect_id}/sent")
async def mark_prospect_sent(prospect_id: str, request: Request) -> any;

@app.post("/api/outbox/{item_id}/reject")
async def outbox_reject(item_id: str) -> any;

@app.post("/api/sending/{action}")
async def sending_toggle(action: str) -> any;

@app.get("/api/export/prospects.csv")
async def export_prospects(all: bool = False, min_score: int = 0, email_status: str = "") -> any;

@app.get("/api/campaigns")
async def get_campaigns -> any;

def _last_opt_out(history: list[any]) -> any;

def _their_messages(thread: any) -> list[any];

@app.get("/api/prospects/{prospect_id}/opt-out")
async def get_opt_out(prospect_id: str) -> any;

@app.post("/api/prospects/{prospect_id}/opt-out/undo")
async def undo_opt_out(prospect_id: str, request: Request) -> any;

@app.get("/api/offers/accepted")
async def get_offers_accepted -> any;

def _thread_emails(sent: list[any], camp: str) -> list[any];

@app.get("/api/conversations")
async def get_conversations(`awaiting: bool = False) -> any;

async def _awaiting_reply -> list[any];

@app.post("/api/conversations/{convo_id}/status")
async def set_conversation_status(convo_id: str, request: Request) -> any;

async def _per_day(
    shift: str, labels: list[any], table: str, column: str, where: str = ""
) -> list[int];

@app.get("/api/trend")
async def get_trend(days: int = 14, tz: int = 0) -> any;

@app.get("/api/activity")
async def get_activity -> any;

glob _discovery_task: any = None,
     _discovery_report: any = None,
     _discovery_kind = "discover",
     _BUSY_RUN = "a run is already going";

def _discovery_queries(body: dict[any, any], config: any) -> any;

def _running -> bool;

@app.get("/api/discover/providers")
async def get_discovery_providers -> any;

@app.post("/api/discover/estimate")
async def estimate_discovery(request: Request) -> any;

async def _go_discover(state: any, config: any, provider: str, queries: any, max_spend: float);

async def _go_profile(state: any);

@app.post("/api/discover/run")
async def start_discovery(request: Request) -> any;

@app.post("/api/profile/run")
async def start_profile -> any;

@app.post("/api/discover/stop")
async def stop_discovery -> any;

def _parse_ts(value: any) -> datetime | None;

async def _scalar(sql: str, params: tuple[any, ...] = ()) -> int;

async def _first(sql: str, params: tuple[any, ...] = (), key: str = "t") -> any;

glob STALE_RUN_SECONDS = 900,
     CONTACT_ACTIVE_SECONDS = 180,
     SENT_STATUSES = ("contacted", "replied", "meeting", "closed", "lost", "opted_out"),
     REPLY_STATUSES = ("replied", "meeting", "closed");

def _eta_text(minutes: any) -> str;

def _step(
    label: str, done: int, total: int, active: bool, detail: str, info: bool = False
) -> dict[str, any];

async def _stalled(run: dict[any, any], now: any) -> bool;

def _drafted_ids(rows: list[any]) -> set[any];

@app.get("/api/live-status")
async def get_live_status -> any;

def _require_approval_now -> bool;

glob _TODAY = {
    "brain-paused": "bad|{who} is paused, so Sellbird is waiting|{reason} Replies and queued emails are untouched; Sellbird resumes once it's fixed. sellbird status --check says what's wrong.|Open the log|controls",
    "email-rules": "bad|Sellbird isn't writing emails: your email rules can't be used|{problem}. Fix the file, or clear writer.email_rules to use Sellbird's built-in rules.|Open the log|controls",
    "sends-held": "bad|{title}|{detail}|Open the log|controls",
    "paused": "bad|Sending is paused|{paused}. Nothing will go out until you resume it.|Review and resume|outbox",
    "precleared-hold": "{tone}|{title}|{detail}|Open the log|controls",
    "setup": "warn|Finish setting Sellbird up|{detail}|Open setup|settings",
    "signals": "warn|{title} waiting for your confirmation|Sellbird won't collect anything you haven't approved. Confirm which signals define a good prospect for you.|Review signals|signals",
    "signals-none": "warn|No signals confirmed|Every signal is rejected, so prospecting has nothing to collect.|Review signals|signals",
    "discover": "good|No companies yet|Signals are confirmed but nothing has been collected. Discovery is free to try — no account needed.|Find businesses|discover",
    "profile": "good|{n} companies not looked at yet|Reading their websites is free and it is what makes an email specific — who their agency is, what they are missing, whether they are spending on ads.|Read their sites|discover",
    "needs-human": "bad|{title}|Sellbird stopped and handed these over: an escalation, or a reply it had no safe answer for. Reply yourself, then close it or hand it back.|Read them|conversations",
    "outbox": "warn|{title} waiting for approval|{detail}|Open the decisions desk|outbox",
    "replies": "good|{title}|People replied. Check how Sellbird is handling them.|Read conversations|conversations",
};

def _today(key: str, **values: any) -> dict[str, any];
def _plural(n: int, one: str, many: str) -> str;

@app.get("/api/today")
async def get_today -> any;

glob _CATEGORIES = {
         "discovery": "Discovery — who exists|How Sellbird finds businesses at all, and how visible they are. This is the only stage that costs money.",
         "profile": "Profile — what they are|Read from the pages a business already publishes. Free, no AI tokens, three HTTP requests per company. These are the signals that make an email specific.",
         "people": "People — who decides|Named humans and whether they're the one who can say yes.",
         "verification": "Contactability — can you reach them|Whether the address will actually deliver, and what to do when it won't.",
     },
     CATEGORY_META = {
         k: dict(zip(("label", "blurb"), v.split("|")))
         for (k, v) in _CATEGORIES.items()
     },
     CATEGORY_ORDER = ["discovery", "profile", "people", "verification"],
     COHORT_PAGE_SIZE = 50,
     COHORT_MAX_PAGE_SIZE = 200,
     COHORT_MAX_RANGES = 20,
     _COHORT_COLUMNS = ("name", "domain", "website", "industry", "location");

def _signal_rows(codes: list[any], cat: str, counts: dict[any, any]) -> list[any];

@app.get("/api/signals")
async def get_signals -> any;

@app.post("/api/signals/status")
async def set_signals_status(request: Request) -> any;

async def _cohort_companies(
    require: list[str],
    exclude: list[str],
    offset: int = 0,
    limit: int | None = None,
    ranges: list[any] | None = None,
) -> any;

def _codes(raw: any) -> list[str];

def _range_bound(raw: any) -> float | None;

def _range_items(raw: str) -> list[any];

def _ranges(raw: any) -> list[any];

def _cohort_integer(raw: any, fallback: int) -> int;

@app.post("/api/cohort")
async def preview_cohort(request: Request) -> any;

def _csv_cell(value: any) -> str;

@app.get("/api/cohort.csv")
async def export_cohort(require: str = "", exclude: str = "", ranges: str = "") -> any;

@app.get("/api/runs")
async def get_runs_api -> any;

glob WEB_DIR = Path(__file__).resolve().parent / "web",
     TEXT_TYPES = {".css": "text/css", ".js": "text/javascript", ".svg": "image/svg+xml"},
     BINARY_TYPES = {".woff2": "font/woff2", ".woff": "font/woff", ".png": "image/png"};

@app.get("/static/{path:path}")
async def static_file(path: str) -> any;

@app.get("/", response_class=HTMLResponse)
async def dashboard -> any;

class DashboardSetupError(Exception) {}

def _check_loopback_bind(host: str) -> str;

def dashboard_url(host: str = "127.0.0.1", port: int = 5555) -> str;

glob INSTANCE_ID = uuid.uuid4().hex;

@app.get("/api/instance")
async def get_instance -> any;

with entry {
    app.include_router(_inbox_router);
    for _router in _extensions.registry().routers {
        app.include_router(_router);
    }
}

def build_app(*, guard: Middleware | None = None, routers: Sequence[APIRouter] = ()) -> FastAPI;

def start_dashboard(host: str = "127.0.0.1", port: int = 5555);
