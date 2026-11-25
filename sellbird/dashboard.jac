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
import from collections { Counter }
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
     _VERIFIER_KEYS = "REOON_API_KEY ZEROBOUNCE_API_KEY HUNTER_API_KEY".split(),
     _WARMUP = {
         "connected": "Warmup: TrulyInbox connected",
         "other": "Warmup: your own warmup service",
     },
     _NO_OFFERS = "Sellbird couldn't come up with offers just now. Try again.",
     _EMPTY: dict[str, any] = {},
     COMPANIES_TAB_LIMIT = 2000;

obj home_middleware {
    has app: any;

    async def __call__(scope: any, receive: any, send: any) {
        home: any = None;
        if scope["type"] in ("http", "websocket") {
            home = getattr(getattr(scope.get("app"), "state", None), "home", None);
        }
        if home is None {
            await self.app(scope, receive, send);
            return;
        }
        with use_home(home) {
            await self.app(scope, receive, send);
        }
    }
}

with entry {
    app.add_middleware(agent_policy.AgentPolicy);
    app.add_middleware(auth.DashboardGuard, store=token_store, agent_store=agent_token_store);
    app.add_middleware(home_middleware);
}

@app.exception_handler(NotOnHosted)
async def _not_on_hosted(request: Request, exc: NotOnHosted) -> any {
    return JSONResponse(exc.payload, status_code=409);
}

def _resolve_config_file -> Path {
    try {
        return Path(_find_config_file());
    } except ConfigFileNotFoundError {
        return CONFIG_FILE;
    }
}

def _refuse(message: str, code: int = 409) -> any {
    return JSONResponse({"success": False, "message": message}, status_code=code);
}

def _error(message: str, code: int = 500) -> any {
    return JSONResponse({"error": message}, status_code=code);
}

def _not_ok(message: str, code: int) -> any {
    return JSONResponse({"ok": False, "message": message}, status_code=code);
}

obj _Guarded {
    has route: any, answer: any;

    async def __call__(*args: any, **kwargs: any) -> any {
        try {
            return await self.route(*args, **kwargs);
        } except Exception as e {
            return self.answer(e);
        }
    }
}

def _on_error(answer: any) -> any {
    return lambda (route: any) -> any { functools.update_wrapper(_Guarded(route, answer), route) };
}

glob _OR_500 = _on_error(lambda (e: any) -> any { _refuse(str(e), 500) }),
     _OR_ERROR = _on_error(lambda (e: any) -> any { dict(error=str(e)) });

def _csv(text: str, filename: str) -> any {
    return PlainTextResponse(
        text,
        media_type="text/csv",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    );
}

def _state -> any {
    return StateManager(db_path=str(DB_PATH));
}

async def _open_state -> any {
    state = _state();
    await state.init_db();
    return state;
}

async def _json(request: any, fallback: any = None) -> any {
    try {
        return await request.json();
    } except Exception {
        return fallback;
    }
}

async def _json_if_json(request: any) -> any {
    if not request.headers.get("content-type", "").startswith("application/json") {
        return {};
    }
    return (await request.json()) or {};
}

def _dict(value: any) -> dict[any, any] {
    return value if isinstance(value, dict) else {};
}

def _loads(text: any, fallback: any) -> any {
    try {
        return json.loads(text);
    } except (json.JSONDecodeError, TypeError) {
        return fallback;
    }
}

def _words(value: any, limit: int) -> str {
    return " ".join(str(value or "").split())[:limit];
}

async def query_db(sql: str, params: tuple[any, ...] = ()) -> list[any] {
    if not DB_PATH.exists() {
        return [];
    }
    try {
        async with storage.connect(str(DB_PATH)) as db {
            db.row_factory = aiosqlite.Row;
            async with db.execute(sql, params) as cursor {
                return [dict(r) for r in await cursor.fetchall()];
            }
        }
    } except Exception as e {
        logger.warning("query_db failed (%s): %s", sql.split(None, 4)[:4], e);
        return [];
    }
}

def _read_env_file -> dict[str, str] {
    env_vars: dict[str, str] = {};
    if ENV_FILE.exists() {
        for raw in read_user_text(ENV_FILE).splitlines() {
            line = raw.strip();
            if line and not line.startswith("#") and "=" in line {
                (key, _, value) = line.partition("=");
                env_vars[key.strip()] = value.strip();
            }
        }
    }
    return env_vars;
}

def _env_key(line: str) -> str {
    stripped = line.strip();
    if not stripped or stripped.startswith("#") or "=" not in stripped {
        return "";
    }
    key = stripped.partition("=")[0].strip();
    return key[len("export "):].strip() if key.startswith("export ") else key;
}

def _write_env_file(updates: dict[str, str]) {
    if ENV_FILE.is_symlink() {
        raise OSError(f"{ENV_FILE} is a symbolic link; edit it by hand.");
    }
    if ENV_FILE.exists() and not ENV_FILE.is_file() {
        raise OSError(f"{ENV_FILE} is not a regular file.");
    }
    lines = read_user_text(ENV_FILE).splitlines() if ENV_FILE.exists() else [];
    out: list[str] = [];
    written: set[any] = set();
    for line in lines {
        key = _env_key(line);
        if key not in updates {
            out.append(line);
        } elif key not in written {
            out.append(f"{key}={updates[key]}");
            written.add(key);
        }
    }
    out += [f"{k}={v}" for (k, v) in updates.items() if k not in written];
    (fd, tmp) = tempfile.mkstemp(prefix=".env.", suffix=".tmp", dir=str(ENV_FILE.parent));
    try {
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as f {
            if os.name != "nt" {
                os.fchmod(f.fileno(), stat.S_IRUSR | stat.S_IWUSR);
            }
            f.write("\n".join(out) + "\n");
            f.flush();
            os.fsync(f.fileno());
        }
        os.replace(tmp, ENV_FILE);
    } except BaseException {
        try {
            os.unlink(tmp);
        } except FileNotFoundError {}
        raise;
    }
    load_dotenv(str(ENV_FILE), override=True);
}

def _check_sellbird_pid -> int | None {
    if _sellbird_process and _sellbird_process.poll() is None {
        return _sellbird_process.pid;
    }
    if PID_FILE.exists() {
        try {
            pid: int | None = int(PID_FILE.read_text(encoding="utf-8").strip());
        } except (OSError, ValueError) {
            pid = None;
        }
        if pid is not None and pid_alive(pid) and loop_lock_held(LOCK_FILE) {
            return pid;
        }
        try {
            PID_FILE.unlink(missing_ok=True);
        } except OSError {}
    }
    return None;
}

def _env_value(env_vars: dict[str, str], key: str) -> str {
    return env_vars.get(key, "") or os.getenv(key, "");
}

def _has(env_vars: dict[str, str], keys: any) -> bool {
    for k in keys {
        if not _env_value(env_vars, k).strip() {
            return False;
        }
    }
    return True;
}

def _all_set(env_vars: dict[str, str], keys: str) -> bool {
    return all(_env_value(env_vars, k) for k in keys.split());
}

def _setup_check(spec: list[str], done: dict[str, any], names: dict[str, any]) -> dict[str, any] {
    (id, label, help, needed) = spec;
    return {
        "id": id,
        "label": label.format(**names),
        "done": done[id],
        "required": needed == "y",
        "help": help.format(**names),
    };
}

def _config_valid(config_path: any) -> bool {
    if not config_path.exists() {
        return False;
    }
    try {
        cfg = yaml.safe_load(read_user_text(config_path));
        company = cfg.get("persona", {}).get("company", "");
        product = cfg.get("product", {}).get("name", "");
        return company not in ("Your Company", "") and product not in ("Your Product", "");
    } except Exception {
        return False;
    }
}

@app.get("/api/setup-status")
async def get_setup_status -> any {
    env_vars = _read_env_file();
    provider = _current_provider();
    if provider in _PROVIDER_SETUP {
        (keys, token_file, provider_help) = _PROVIDER_SETUP[provider].split("|");
        token_ok = not token_file or (PROJECT_ROOT / "data" / token_file).is_file();
        provider_done = _has(env_vars, keys.split()) and token_ok;
    } else {
        instantly_key = _env_value(env_vars, "INSTANTLY_API_KEY");
        provider_done = bool(instantly_key) and instantly_key != "your_instantly_api_key_here";
        provider_help = "Enter your Instantly API key in Settings.";
    }
    config_path = _resolve_config_file();
    try {
        choice = await ti.get_choice(await _open_state());
    } except Exception {
        choice = "";
    }
    if _has(env_vars, ["TRULYINBOX_API_KEY"]) {
        choice = "connected";
    }
    done = {
        "venv": (not is_checkout(PACKAGE_ROOT)) or (PACKAGE_ROOT / ".venv").is_dir(),
        "env_file": ENV_FILE.exists() and bool(env_vars),
        "email_provider": provider_done,
        "verifier": any(_has(env_vars, [k]) for k in _VERIFIER_KEYS),
        "config": _config_valid(config_path),
        "product_trained": (PROJECT_ROOT / "skills" / "product_knowledge.md").exists(),
        "linkedin": _all_set(env_vars, "LINKEDIN_EMAIL LINKEDIN_PASSWORD"),
        "cloudflare": _all_set(env_vars, "CLOUDFLARE_ACCOUNT_ID CLOUDFLARE_API_TOKEN"),
        "warmup_service": bool(choice),
    };
    names = {
        "provider": provider,
        "provider_help": provider_help,
        "config": config_path.name,
        "warmup": _WARMUP.get(choice, "Warm up your mailbox"),
    };
    checks = [_setup_check(spec.split("|"), done, names) for spec in _SETUP_CHECKS];
    checks[-1]["required"] = provider != "instantly";
    checks[-1]["link"] = ti.AFFILIATE_URL;
    required = [c for c in checks if c["required"]];
    completed = sum(1 for c in required if c["done"]);
    return {
        "checks": checks,
        "completed": completed,
        "total_required": len(required),
        "percent": int(completed / len(required) * 100) if required else 0,
    };
}

def _current_provider -> str {
    try {
        cfg = yaml.safe_load(read_user_text(_resolve_config_file())) or _EMPTY;
        return ((cfg.get("channels") or _EMPTY).get("email") or _EMPTY).get(
            "provider", "instantly"
        );
    } except Exception {
        return "instantly";
    }
}

@app.get("/api/settings")
async def get_settings -> any {
    env_vars = _read_env_file();
    out: dict[str, any] = {"provider": _current_provider()};
    for key in _ENV_KEYS {
        value = env_vars[key] if key in env_vars else os.getenv(key, "");
        if key in _SECRET_KEYS {
            out[key.lower() + "_set"] = bool((value or "").strip());
        } else {
            out[key.lower()] = value;
        }
    }
    out["gmail_authorized"] = (PROJECT_ROOT / "data" / "gmail_token.json").is_file();
    out["m365_authorized"] = (PROJECT_ROOT / "data" / "m365_token.json").is_file();
    return out;
}

@app.post("/api/settings/env")
async def save_env_settings(request: Request) -> any {
    data = await _json(request);
    if not isinstance(data, dict) {
        return _refuse("Invalid request body.", 400);
    }
    async with _env_lock {
        updates: dict[str, str] = {};
        for key in _ENV_KEYS {
            if key not in data or data[key] is None {
                continue;
            }
            value = data[key];
            if isinstance(value, bool) or not isinstance(value, (str, int, float)) {
                return _refuse(f"{key} must be text.", 400);
            }
            value = str(value);
            if key.endswith("_PORT") and value.strip() and not value.strip().isdigit() {
                return _refuse(f"{key} must be a number.", 400);
            }
            if len(value) > 4096 or "\x00" in value {
                return _refuse(f"{key} is invalid.", 400);
            }
            updates[key] = value.replace("\n", " ").replace("\r", " ").strip();
        }
        if updates {
            try {
                _write_env_file(updates);
            } except Exception as e {
                logger.warning("Failed to write .env: %s", e);
                return {"success": False, "message": "Could not write .env file."};
            }
            os.environ.update({k: updates[k] for k in _SIGN_IN_KEYS if k in updates});
        }
    }
    return {"success": True};
}

@app.post("/api/trulyinbox/connect")
async def trulyinbox_connect(request: Request) -> any {
    data = await _json(request);
    key = data.get("key") if isinstance(data, dict) else None;
    if not isinstance(key, str) or not key.strip() or len(key) > 512 {
        return _refuse("Paste your TrulyInbox API key.", 400);
    }
    key = key.strip();
    try {
        config = load_config();
        (address, warmup) = (ti.sending_address(config), config.channels.email.warmup);
    } except Exception {
        (address, warmup) = ("", None);
    }
    if not address {
        return _refuse(ti.NO_ADDRESS, 400);
    }
    workspace = _env_value(_read_env_file(), "TRULYINBOX_WORKSPACE_ID").strip();
    ti.forget_rejected(key);
    try {
        client = ti.TrulyInbox(key, workspace);
        health = await client.mailbox_health(address);
    } except ti.TrulyInboxError as e {
        return _refuse(str(e), 400);
    }
    updates: dict[str, str] = {"TRULYINBOX_API_KEY": key};
    if not workspace {
        updates["TRULYINBOX_WORKSPACE_ID"] = client.workspace_id;
    }
    async with _env_lock {
        try {
            _write_env_file(updates);
        } except Exception as e {
            logger.warning("Failed to write .env: %s", e);
            return {"success": False, "message": "Could not write .env file."};
        }
    }
    await ti.set_choice(await _open_state(), "connected");
    return {"success": True, "message": d.check_warmup_service(health, warmup).detail};
}

@app.get("/api/rename-notice")
async def get_rename_notice -> any {
    return {"show": legacy.welcome_pending()};
}

@app.post("/api/rename-notice/dismiss")
async def dismiss_rename_notice -> any {
    legacy.dismiss_welcome();
    return {"success": True};
}

@app.post("/api/trulyinbox/other")
async def trulyinbox_other -> any {
    await ti.set_choice(await _open_state(), "other");
    return {"success": True};
}

def _offer_config_file -> Path {
    target = _resolve_config_file();
    if target.name == "sellbird.yaml" {
        local = target.with_name("sellbird.local.yaml");
        if not local.exists() {
            shutil.copyfile(target, local);
        }
        target = local;
    }
    return target;
}

async def _offer_brain -> tuple[any, any, any] {
    config = load_config();
    state = await _open_state();
    return (Brain(state, config.brain), state, config);
}

@app.get("/api/offer")
async def get_offer -> any {
    try {
        return offer_view(load_config());
    } except Exception as e {
        return _error(f"Couldn't read your config: {e}");
    }
}

@app.post("/api/offer/suggest")
async def suggest_offer -> any {
    try {
        (brain, _, config) = await _offer_brain();
        ideas = await suggest_offers(brain, config);
    } except Exception as e {
        logger.warning(f"Offer suggestions failed: {e}");
        return _error(_NO_OFFERS, 502);
    }
    return {"ideas": ideas} if ideas else _error(_NO_OFFERS, 502);
}

@app.post("/api/offer/preview")
async def preview_offer(request: Request) -> any {
    offer = _words((await _json_if_json(request)).get("entry"), MAX_OFFER_CHARS);
    if not offer {
        return _not_ok("Write an offer first.", 400);
    }
    try {
        (brain, state, config) = await _offer_brain();
        return await preview_email(brain, state, config, offer);
    } except Exception as e {
        logger.warning(f"Offer preview failed: {e}");
        return _not_ok("The preview failed. Try again.", 502);
    }
}

@app.post("/api/offer")
async def save_offer_route(request: Request) -> any {
    body = await _json_if_json(request);
    offer = _words(body.get("entry"), MAX_OFFER_CHARS);
    ideas = body.get("ideas");
    target = _offer_config_file();
    try {
        save_offer(target, offer, [str(i) for i in ideas] if isinstance(ideas, list) else None);
        await (await _open_state()).delete_setting(PROPOSED_KEY);
    } except Exception as e {
        return _refuse(f"Couldn't save to {target.name}: {e}", 500);
    }
    message = "Saved. Every new first email ends with this offer."
        if offer
        else "Saved. With no offer, first emails end with a question.";
    return {"success": True, "entry": offer, "message": message};
}

@app.get("/api/company")
async def get_company -> any {
    try {
        raw = await (await _open_state()).get_setting(PROPOSED_KEY);
        return company_view(load_config(), PROJECT_ROOT, json.loads(raw) if raw else None);
    } except Exception as e {
        return _error(f"Couldn't read your config: {e}");
    }
}

@app.post("/api/company")
async def save_company_route(request: Request) -> any {
    body = await _json_if_json(request);
    fields = body.get("fields");
    if not isinstance(fields, dict) or not fields {
        return _refuse("Nothing to save.", 400);
    }
    try {
        save_company(_offer_config_file(), str(body.get("section") or ""), fields);
    } except ValueError as e {
        return _refuse(f"Not saved: {e}.", 400);
    } except Exception as e {
        return _refuse(f"Couldn't save: {e}", 500);
    }
    return {"success": True, "message": "Saved. New emails use it from the next draft."};
}

@app.post("/api/offer/propose")
async def propose_offer(request: Request) -> any {
    body = await _json_if_json(request);
    offer = _words(body.get("entry"), MAX_OFFER_CHARS);
    why = _words(body.get("why"), 500);
    if not offer {
        return _not_ok("An offer is required.", 400);
    }
    proposal = {"entry": offer, "why": why, "at": datetime.now(timezone.utc).isoformat()};
    await (await _open_state()).set_setting(PROPOSED_KEY, json.dumps(proposal));
    return {
        "ok": True,
        "message": "Proposed. The user confirms it on the Your company tab (dashboard → Your company → Your offer → Use this offer).",
    };
}

@app.delete("/api/offer/propose")
async def dismiss_proposed_offer -> any {
    await (await _open_state()).delete_setting(PROPOSED_KEY);
    return {"success": True};
}

@app.post("/api/settings/test-instantly")
async def test_instantly(request: Request) -> any {
    api_key = str((await _json(request, {})).get("api_key", "") or "");
    if not api_key {
        return {"success": False, "message": "No API key provided."};
    }
    try {
        async with httpx.AsyncClient(timeout=10) as client {
            url = "https://api.instantly.ai/api/v2/accounts";
            resp = await client.get(url, headers={"Authorization": f"Bearer {api_key}"});
        }
    } except Exception as e {
        return {"success": False, "message": f"Connection failed: {str(e)}"};
    }
    if resp.status_code == 200 {
        return {"success": True, "message": "Connected to Instantly."};
    }
    return {"success": False, "message": f"API returned {resp.status_code}. Check your key."};
}

@app.get("/api/companies")
async def get_companies -> any {
    rows = await query_db(
        "SELECT c.*, (SELECT COUNT(*) FROM prospects p WHERE p.company_id = c.id) as contact_count FROM companies c ORDER BY c.created_at DESC",
    );
    try {
        register = {r["id"]: r for r in await build_register(query_db, load_config())};
        for c in rows {
            r = register.get(c["id"]);
            if r {
                c.update(
                    fit=r["fit"],
                    fit_reasons=r["fit_reasons"],
                    register_status=r["status"],
                    register_why=r["why_not_contacted"],
                );
            }
        }
        rows.sort(key=lambda (c: any) -> any { c.get("fit", 0) }, reverse=True);
    } except Exception as e {
        logger.warning(f"Company fit unavailable: {e}");
    }
    return rows[:COMPANIES_TAB_LIMIT];
}

@app.get("/api/export/companies.csv")
async def export_companies -> any {
    try {
        text = to_csv(await build_register(query_db, load_config()));
    } except Exception as e {
        logger.warning("Company register export failed: %s", e);
        return PlainTextResponse(f"Company register export failed: {e}", status_code=500);
    }
    return _csv(chr(0xFEFF) + text, "company-register.csv");
}

@app.get("/api/companies/{company_id}/profile")
async def get_company_profile(company_id: str) -> any {
    rows = await query_db("SELECT * FROM companies WHERE id = ?", (company_id,));
    if not rows {
        return _error("not found", 404);
    }
    observations = await query_db(
        "SELECT o.signal_code, o.value_text, o.value_num, o.evidence_url, o.observed_at, "
            "COALESCE(s.label, o.signal_code) AS label FROM observations o "
            "LEFT JOIN signal_codes s ON s.code = o.signal_code "
            "WHERE o.company_id = ? AND o.prospect_id = '' ORDER BY o.observed_at DESC LIMIT 200",
        (company_id,),
    );
    register: any = {};
    try {
        register = next(iter(await build_register(query_db, load_config(), company_id)), {});
    } except Exception as e {
        logger.warning(f"Company profile register unavailable: {e}");
    }
    return {"company": rows[0], "register": register, "observations": observations};
}

@app.get("/api/companies/{company_id}/contacts")
async def get_company_contacts(company_id: str) -> any {
    return await query_db(
        "SELECT * FROM prospects WHERE company_id = ? ORDER BY score DESC", (company_id,)
    );
}

@app.post("/api/feedback")
async def add_feedback(request: Request) -> any {
    data = _dict(await _json(request, {}));
    entity_type = str(data.get("entity_type", "") or "")[:50];
    entity_id = str(data.get("entity_id", "") or "")[:100];
    comment = str(data.get("comment", "") or "").strip()[:4000];
    if not comment {
        return {"success": False, "message": "Comment is required."};
    }
    feedback_id = uuid.uuid4().hex[:12];
    try {
        DB_PATH.parent.mkdir(parents=True, exist_ok=True);
        async with storage.connect(str(DB_PATH)) as db {
            await db.execute(
                "CREATE TABLE IF NOT EXISTS feedback (id TEXT PRIMARY KEY, entity_type TEXT, entity_id TEXT, comment TEXT, created_at TEXT DEFAULT (datetime('now')))",
            );
            await db.execute(
                "INSERT INTO feedback (id, entity_type, entity_id, comment) VALUES (?, ?, ?, ?)",
                (feedback_id, entity_type, entity_id, comment),
            );
            await db.commit();
        }
    } except Exception as e {
        logger.warning("Failed to save feedback: %s", e);
        return {"success": False, "message": "Could not save feedback."};
    }
    return {"success": True, "id": feedback_id};
}

@app.get("/api/feedback/{entity_type}/{entity_id}")
async def get_feedback(entity_type: str, entity_id: str) -> any {
    return await query_db(
        "SELECT * FROM feedback WHERE entity_type = ? AND entity_id = ? ORDER BY created_at DESC",
        (entity_type, entity_id),
    );
}

@app.get("/api/sellbird/status")
async def get_sellbird_status -> any {
    pid = _check_sellbird_pid();
    started = _sellbird_started_at.isoformat() if _sellbird_started_at else None;
    try {
        paused = await (await _open_state()).get_setting("sending_paused") or "";
    } except Exception {
        paused = "";
    }
    return {
        "running": pid is not None,
        "pid": pid,
        "started_at": started,
        "sending_paused": paused,
    };
}

@app.post("/api/sellbird/start")
async def start_sellbird -> any {
    if _check_sellbird_pid() {
        return {"success": False, "message": "Sellbird is already running."};
    }
    if _needs_setup() {
        message = "Sellbird isn't set up yet. Run `sellbird setup` in a terminal first.";
        return {"success": False, "message": message};
    }
    (PROJECT_ROOT / "data").mkdir(parents=True, exist_ok=True);
    env = os.environ.copy();
    local_bin = Path.home() / ".local" / "bin";
    if not shutil.which("claude") and local_bin.is_dir() {
        env["PATH"] = str(local_bin) + os.pathsep + env.get("PATH", "");
    }
    try {
        with open(LOG_FILE, "a", encoding="utf-8") as log {
            _sellbird_process = subprocess.Popen(
                [sys.executable, "-m", "sellbird", "run"],
                cwd=str(PROJECT_ROOT),
                stdin=subprocess.DEVNULL,
                stdout=log,
                stderr=log,
                start_new_session=True,
                env=env,
            );
        }
    } except Exception as e {
        logger.warning("Failed to start Sellbird: %s", e);
        return {"success": False, "message": f"Failed to start Sellbird: {e}"};
    }
    _sellbird_started_at = datetime.now();
    return {"success": True, "pid": _sellbird_process.pid};
}

def _alive(mine: any, pid: int) -> bool {
    return mine.poll() is None if mine is not None else pid_alive(pid);
}

@app.post("/api/sellbird/stop")
async def stop_sellbird -> any {
    pid = _check_sellbird_pid();
    if not pid {
        return {"success": False, "message": "Sellbird is not running."};
    }
    mine = _sellbird_process if _sellbird_process and _sellbird_process.pid == pid else None;
    try {
        os.kill(pid, signal.SIGTERM);
        for _ in range(10) {
            if not _alive(mine, pid) {
                break;
            }
            await asyncio.sleep(0.5);
        } else {
            try {
                os.kill(pid, getattr(signal, "SIGKILL", signal.SIGTERM));
            } except OSError {}
            await asyncio.sleep(0.5);
        }
    } except OSError as e {
        logger.warning("Couldn't signal Sellbird (pid %s): %s", pid, e);
    }
    if _alive(mine, pid) {
        message = f"Couldn't stop Sellbird (pid {pid}). Stop it where it was started.";
        return {"success": False, "message": message};
    }
    _sellbird_process = None;
    _sellbird_started_at = None;
    PID_FILE.unlink(missing_ok=True);
    return {"success": True};
}

@app.get("/api/sellbird/logs")
async def get_sellbird_logs -> any {
    if not LOG_FILE.exists() {
        return {"lines": []};
    }
    try {
        with open(LOG_FILE, "rb") as f {
            f.seek(0, os.SEEK_END);
            f.seek(max(0, f.tell() - 65536));
            text = f.read().decode("utf-8", errors="replace");
        }
        return {"lines": text.strip().splitlines()[-100:]};
    } except Exception {
        return {"lines": []};
    }
}

def _pipeline_bucket(
    status: str | None, stage: str | None, intent: str | None, email_status: str | None = None
) -> str {
    status = status or "new";
    if status in ("new", "queued") {
        return "to_write";
    }
    if status == "contacted" {
        return "closed_out" if email_status == "invalid" else "contacted";
    }
    if status == "meeting" or (status == "replied" and stage == "closing") {
        return "ready_to_meet";
    }
    if status == "replied" and stage != "closed_lost" {
        return "interested"
            if intent == "interested" or stage in ("presenting", "negotiating")
            else "replied";
    }
    return "closed_out";
}

async def _count_map(table: str) -> dict[any, any] {
    return {
        r["status"]: r["count"]
        for r in await query_db(f"SELECT status, COUNT(*) as count FROM {table} GROUP BY status")
    };
}

@app.get("/api/stats")
@_OR_ERROR
async def get_stats -> any {
    out: dict[str, any] = {};
    for table in ("prospects", "campaigns", "conversations") {
        found = await _count_map(table);
        out[table] = {"total": sum(found.values()), "by_status": found};
    }
    rows = await query_db(
        "SELECT p.status, p.email_status, l.stage, l.intent, COUNT(*) AS count FROM prospects p "
            "LEFT JOIN (SELECT prospect_id, stage, intent, ROW_NUMBER() OVER ("
            "PARTITION BY prospect_id ORDER BY updated_at DESC, created_at DESC) AS rn "
            "FROM conversations) l ON l.prospect_id = p.id AND l.rn = 1 "
            "GROUP BY p.status, p.email_status, l.stage, l.intent",
    );
    pipeline = dict.fromkeys(
        "to_write contacted replied interested ready_to_meet closed_out".split(), 0
    );
    for r in rows {
        pipeline[_pipeline_bucket(
            r["status"], r["stage"], r["intent"], r["email_status"]
        )] += r["count"];
    }
    usage = await query_db(
        "SELECT claude_calls, codex_calls FROM usage_log WHERE date = ?",
        (date.today().isoformat(),),
    );
    today = usage[0] if usage else {};
    return {
        **out,
        "pipeline": pipeline,
        "actions_total": await _scalar("SELECT COUNT(*) as count FROM actions"),
        "claude_calls_today": today.get("claude_calls") or 0,
        "codex_calls_today": today.get("codex_calls") or 0,
        "brain_provider": _active_provider(),
        "brain_status": await _brain_status(),
    };
}

glob _USAGE_SUM = ("COUNT(DISTINCT CASE WHEN session_id != '' THEN session_id ELSE id END) AS calls, "
         "COALESCE(SUM(input_tokens), 0) AS input_tokens, COALESCE(SUM(output_tokens), 0) AS output_tokens, "
         "COALESCE(SUM(cache_read_tokens), 0) AS cache_read_tokens, "
         "COALESCE(SUM(cache_creation_tokens), 0) AS cache_creation_tokens, "
         "ROUND(COALESCE(SUM(cost_usd), 0), 4) AS cost_usd"),
     _quota_clients: dict[any, any] = {};

def _active_brain -> any {
    try {
        return load_brain_config();
    } except Exception {
        return None;
    }
}

async def _brain_status -> dict[str, any] {
    rows = await query_db("SELECT value FROM settings WHERE key = ?", (BRAIN_STATUS_KEY,));
    return active_brain_status(rows[0]["value"], _active_provider()) if rows else {};
}

def _active_provider -> str {
    brain = _active_brain();
    return brain.provider if brain else "";
}

def _quota_client_for(provider: str, model: str = "") -> any {
    key = (provider, model if provider == "codex" else "");
    if key not in _quota_clients {
        if provider == "codex" {
            _quota_clients[key] = CodexQuotaClient(CodexClient(model=model));
        } elif provider == "claude" {
            _quota_clients[key] = QuotaClient();
        } else {
            return None;
        }
    }
    return _quota_clients[key];
}

def _usage_grouped(expr: str, alias: str) -> str {
    return f"SELECT {expr} AS {alias}, {_USAGE_SUM} FROM usage_events WHERE created_at >= datetime('now', '-30 days') GROUP BY {alias} ORDER BY output_tokens DESC LIMIT 25";
}

@app.get("/api/usage")
async def get_usage -> any {
    totals: dict[str, any] = {};
    for (label, where) in (
        ("today", "date(created_at) = date('now')"),
        ("week", "created_at >= datetime('now', '-7 days')"),
        ("month", "created_at >= datetime('now', '-30 days')"),
    ) {
        rows = await query_db(f"SELECT {_USAGE_SUM} FROM usage_events WHERE {where}");
        totals[label] = rows[0] if rows else {};
    }
    grouped: dict[str, any] = {};
    for (alias, blank) in (("agent", "other"), ("task", "other"), ("model", "unknown")) {
        expr = f"CASE WHEN {alias} = '' THEN '{blank}' ELSE {alias} END";
        grouped["by_" + alias] = await query_db(_usage_grouped(expr, alias));
    }
    by_provider = await query_db(_usage_grouped("provider", "provider"));
    by_day = await query_db(
        f"SELECT date(created_at) AS day, {_USAGE_SUM} FROM usage_events WHERE created_at >= datetime('now', '-30 days') GROUP BY day ORDER BY day ASC",
    );
    brain = _active_brain();
    provider = brain.provider if brain else "";
    quota: any = None;
    try {
        client = _quota_client_for(provider, brain.model if brain else "");
        if client is not None {
            quota = await client.get_utilization();
        }
    } except Exception as e {
        logger.debug("Quota lookup failed: %s", e);
    }
    return {
        "provider": provider,
        "quota": quota,
        "quota_provider": provider,
        "quota_status": ("available" if quota else "unavailable") if provider else "",
        "by_provider": by_provider,
        "totals": totals,
        "by_day": by_day,
        **grouped,
    };
}

@app.get("/api/prospects")
async def get_prospects -> any {
    rows = await query_db("SELECT * FROM prospects ORDER BY created_at DESC LIMIT 200");
    undone = {
        r["pid"]
        for r in await query_db(
            "SELECT DISTINCT json_extract(details_json, '$.prospect_id') AS pid FROM actions "
                "WHERE action_type = 'opt_out_undone' AND json_valid(details_json)",
        )
    };
    for r in rows {
        r["opt_out_undone"] = r.get("id") in undone;
    }
    return rows;
}

glob OUTBOX_CONTEXT_SIGNALS = tuple(
         "TECH_STACK INCUMBENT_AGENCY HIRING_ROLE RUNNING_GOOGLE_ADS NO_ONLINE_BOOKING".split()
     ),
     HAND_SENDABLE_STATUSES = ("new", "queued"),
     HAND_SENDABLE_EMAIL = ("verified", "risky");

def _in(ids: any) -> str {
    return ",".join(["?"] * len(ids));
}

def _signal_value(r: dict[any, any]) -> str {
    if r["value_text"] {
        return r["value_text"];
    }
    return "" if r["value_num"] is None else ("yes" if r["value_num"] else "no");
}

def _joined(values: any, sep: str = ", ") -> str {
    return sep.join(filter(None, values));
}

async def _rows_in(sql: str, ids: any, more: tuple[any, ...] = ()) -> list[any] {
    if not ids {
        return [];
    }
    return await query_db(sql.replace("IN (?)", f"IN ({_in(ids)})", 1), (*ids, *more));
}

async def _with_context(items: list[any]) -> list[any] {
    pids = sorted({i["prospect_id"] for i in items if i.get("prospect_id")});
    cids = sorted({i["campaign_id"] for i in items if i.get("campaign_id")});
    people_rows = await _rows_in(
        "SELECT p.id, p.first_name, p.last_name, p.title, p.source, p.email_status, "
            "p.score, p.personalization_notes, p.company_id, c.name AS company_name, "
            "c.domain, c.website, c.description, c.industry AS found_by "
            "FROM prospects p LEFT JOIN companies c ON c.id = p.company_id WHERE p.id IN (?)",
        pids,
    );
    people = {r["id"]: r for r in people_rows};
    campaign_rows = await _rows_in("SELECT id, name FROM campaigns WHERE id IN (?)", cids);
    campaigns = {r["id"]: r["name"] for r in campaign_rows};
    company_ids = sorted({p["company_id"] for p in people.values() if p.get("company_id")});
    signals: dict[any, dict[str, str]] = {};
    latest: dict[tuple[any, ...], tuple[any, ...]] = {};
    for r in await _rows_in(
        "SELECT o.company_id, o.signal_code, o.value_num, o.value_text, o.observed_at, o.run_id, "
            "COALESCE(NULLIF(sc.label, ''), o.signal_code) AS label FROM observations o "
            "LEFT JOIN signal_codes sc ON sc.code = o.signal_code WHERE o.company_id IN (?) "
            f"AND o.signal_code IN ({_in(OUTBOX_CONTEXT_SIGNALS)}) ORDER BY o.observed_at, o.id",
        company_ids,
        OUTBOX_CONTEXT_SIGNALS,
    ) {
        value = _signal_value(r);
        key = (r["company_id"], r["label"]);
        seen = r["run_id"] or r["observed_at"];
        (prev_seen, values) = latest.get(key, (None, []));
        if seen != prev_seen {
            values = [];
        }
        latest[key] = (seen, values if value in values else values + [value]);
    }
    for ((company_id, label), (_, values)) in latest.items() {
        signals.setdefault(company_id, {})[label] = _joined(values);
    }
    for item in items {
        p = people.get(item.get("prospect_id")) or {};
        item["context"] = _context(p, campaigns.get(item.get("campaign_id"), ""), signals);
    }
    return items;
}

def _context(p: dict[any, any], campaign: str, signals: dict[any, dict[str, str]]) -> dict[str, any] {
    return {
        "campaign": campaign,
        "company": p.get("company_name", ""),
        "website": p.get("website") or (f"https://{p['domain']}" if p.get("domain") else ""),
        "contact": _joined((p.get("first_name"), p.get("last_name")), " "),
        "contact_title": p.get("title", ""),
        "contact_source": p.get("source", ""),
        "email_status": p.get("email_status", ""),
        "score": p.get("score"),
        "notes": p.get("personalization_notes", ""),
        "signals": signals.get(p.get("company_id"), {}),
    };
}

@app.get("/api/outbox")
@_OR_ERROR
async def get_outbox_api -> any {
    state = await _open_state();
    await state.fail_stale_sending_outbox();
    return {
        **_compliance_view(),
        "paused": await state.get_setting("sending_paused"),
        "pending": await _with_context(await state.get_outbox(status="pending_review", limit=100)),
        "approved": await state.get_outbox(status="sending", limit=10)
            + await state.get_outbox(status="approved", limit=50),
        "sent": await query_db(
            "SELECT * FROM outbox WHERE status = 'sent' ORDER BY sent_at DESC LIMIT 25"
        ),
        "failed": await query_db(
            "SELECT * FROM outbox WHERE status IN ('failed','rejected','cancelled') ORDER BY updated_at DESC LIMIT 25",
        ),
    };
}

@app.get("/api/sending-mode")
async def get_sending_mode -> any {
    path = _resolve_config_file();
    try {
        config = load_config(str(path));
    } except Exception as e {
        return _error(f"Couldn't read {path.name}: {e}");
    }
    state = await _open_state();
    return {
        "mode": "approval" if config.channels.email.require_approval else "autopilot",
        "provider": config.channels.email.provider,
        "file": path.name,
        "your_domains": sorted(allowed_link_domains(config)),
        "booking_page": _booking_prefix(config),
        "held": await state.count_held_for_review(),
    };
}

@app.post("/api/sending-mode")
async def set_sending_mode(request: Request) -> any {
    body = await _json(request);
    mode = body.get("mode") if isinstance(body, dict) else None;
    if mode not in ("approval", "autopilot") {
        return _refuse(
            'expected {"mode": "approval"} or {"mode": "autopilot", "confirm": "autopilot"}', 400
        );
    }
    if mode == "autopilot" and body.get("confirm") != "autopilot" {
        return _refuse(
            'Type "autopilot" to confirm: Sellbird will send email without asking you.', 400
        );
    }
    path = _resolve_config_file();
    try {
        set_require_approval(mode == "approval", path);
    } except ConfigError as e {
        return _refuse(str(e), 409);
    }
    state = await _open_state();
    requeued = await state.requeue_autopilot_approved() if mode == "approval" else 0;
    await state.log_action(
        "sending_mode", "dashboard", {"mode": mode, "file": path.name, "requeued": requeued}
    );
    out = {"success": True, "mode": mode};
    return {**out, "requeued": requeued} if mode == "approval" else out;
}

@app.post("/api/outbox/approve-all")
@_OR_500
async def outbox_approve_all -> any {
    state = await _open_state();
    n = await state.approve_outbox();
    return {"success": True, "approved": n, "held": await state.count_held_for_review()};
}

@app.post("/api/outbox/{item_id}/approve")
@_OR_500
async def outbox_approve(item_id: str) -> any {
    return {"success": bool(await (await _open_state()).approve_outbox(item_id))};
}

def _signed(text: str, kind: any) -> str {
    footer = _compliance_view()["footer"];
    if kind == "sequence" and footer and not text.rstrip().endswith(footer) {
        return text.rstrip() + "\n\n" + footer;
    }
    return text;
}

@app.post("/api/outbox/{item_id}/edit")
@_OR_500
async def outbox_edit(item_id: str, request: Request) -> any {
    body = _dict(await _json(request, {}));
    subject = str(body.get("subject") or "").strip();
    text = str(body.get("body") or "").strip();
    state = await _open_state();
    item = await state.get_outbox_item(item_id);
    if not item or item.get("status") != "pending_review" {
        return _refuse("Only drafts awaiting review can be edited.");
    }
    reply = item.get("kind") == "reply";
    if reply {
        subject = item.get("subject") or "";
    }
    if not subject.strip() or not text {
        return _refuse("Subject and body are both required.", 400);
    }
    gate = pre_send_check("reviewer@example.com", subject, _signed(text, item.get("kind")));
    prospect = await state.get_prospect(item.get("prospect_id") or "");
    names = [getattr(prospect, a, "") for a in ("company", "first_name", "last_name")];
    kind = "reply" if reply else "cold";
    style = style_problems(subject, text, shape=False, names=list(filter(None, names)), kind=kind);
    if style {
        return _refuse("The sender would hold this: the email " + "; ".join(style), 400);
    }
    if not gate {
        return _refuse("The sender would have blocked this: " + "; ".join(gate.reasons), 400);
    }
    if not await state.edit_outbox_draft(item_id, subject, text) {
        return _refuse("Only drafts awaiting review can be edited.");
    }
    await state.log_action(
        "outbox_edited",
        "dashboard",
        {
            "outbox_id": item_id,
            "to_email": item.get("to_email", ""),
            "old_subject": item.get("subject", ""),
            "old_body": item.get("body", ""),
        },
    );
    return {"success": True};
}

def _sellbird_can_send -> bool {
    try {
        (config, env) = (load_config(), load_env());
        email = config.channels.email;
        if not email.enabled or legacy_sending_held(config) {
            return False;
        }
        if (email.provider or "").strip().lower() in NATIVE_PROVIDERS {
            provider = get_mail_provider(config, env);
            return bool(provider and provider.is_configured()) or _extra_inboxes_connected();
        }
        return bool(env.instantly_api_key);
    } except Exception {
        return True;
    }
}

def _extra_inboxes_connected -> bool {
    if not Path(DB_PATH).exists() {
        return False;
    }
    try {
        with sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True) as db {
            row = db.execute("SELECT 1 FROM mailboxes WHERE state != 'retired' LIMIT 1").fetchone();
        }
    } except sqlite3.Error {
        return False;
    }
    return row is not None;
}

def _send_as -> str {
    try {
        return load_config().persona.email or "";
    } except Exception {
        return "";
    }
}

def _compliance_view -> dict[str, any] {
    try {
        config = load_config();
        return {
            "footer": "\n".join(compliance_footer_lines(config)),
            "compliance_notice": compliance_notice(config),
        };
    } except Exception {
        return {"footer": "", "compliance_notice": ""};
    }
}

async def _instantly_ids -> list[any] {
    rows = await query_db(
        "SELECT prospect_ids_json FROM campaigns WHERE COALESCE(instantly_campaign_id, '') != ''"
    );
    return [_loads(row.get("prospect_ids_json") or "[]", None) for row in rows];
}

async def _sellbird_committed_ids -> set[any] {
    ids = {
        r["prospect_id"]
        for r in await query_db(
            "SELECT DISTINCT prospect_id FROM outbox WHERE status IN ('approved', 'sending', 'sent') "
                "OR (status = 'failed' AND substr(error, 1, ?) = ?)",
            (len(MAYBE_SENT_PREFIX), MAYBE_SENT_PREFIX),
        )
    };
    for found in await _instantly_ids() {
        if isinstance(found, list) {
            ids.update(filter(_is_str, found));
        }
    }
    return ids;
}

def _is_str(value: any) -> bool {
    return isinstance(value, str);
}

async def _hand_sent_ids -> set[any] {
    rows = await query_db("SELECT key FROM settings WHERE key LIKE ?", (MANUAL_SEND_KEY + "%",));
    return {r["key"][len(MANUAL_SEND_KEY):] for r in rows};
}

async def _sellbird_sent_to(prospect_id: str) -> bool {
    if await query_db(
        "SELECT 1 FROM outbox WHERE prospect_id = ? AND (status IN ('sending', 'sent') "
            "OR (status = 'failed' AND substr(error, 1, ?) = ?)) LIMIT 1",
        (prospect_id, len(MAYBE_SENT_PREFIX), MAYBE_SENT_PREFIX),
    ) {
        return True;
    }
    for found in await _instantly_ids() {
        try {
            if found is not None and prospect_id in found {
                return True;
            }
        } except TypeError {}
    }
    return False;
}

@app.post("/api/prospects/{prospect_id}/sent")
@_OR_500
async def mark_prospect_sent(prospect_id: str, request: Request) -> any {
    try {
        body = await request.json();
    } except ValueError {
        body = {};
    }
    if body is None {
        body = {};
    }
    if not isinstance(body, dict) or not isinstance(body.get("sent", True), bool) {
        return _refuse('expected {"sent": true|false}', 400);
    }
    sent = body.get("sent", True);
    rows = await query_db("SELECT status FROM prospects WHERE id = ?", (prospect_id,));
    if not rows {
        return _refuse("unknown prospect", 404);
    }
    current = rows[0].get("status") or "new";
    state = await _open_state();
    key = MANUAL_SEND_KEY + prospect_id;
    marked = bool(await state.get_setting(key));
    if sent {
        if marked {
            return {"success": True, "sent": True, "already": True};
        }
        if current not in HAND_SENDABLE_STATUSES {
            return {"success": True, "sent": True, "status": current};
        }
        await state.set_setting(key, current);
        if prospect_id in await _sellbird_committed_ids() {
            await state.delete_setting(key);
            return _refuse(
                "Sellbird has already approved or sent an email to this person. Check the Outbox."
            );
        }
        await state.update_prospect_status(prospect_id, "contacted");
        changed = await state.cancel_pending_outbox_for_prospect(
            prospect_id, reason=HAND_SENT_REASON
        );
    } else {
        if not marked {
            if current in HAND_SENDABLE_STATUSES {
                return {"success": True, "sent": False};
            }
            if current == "contacted" {
                return _refuse("This wasn't marked as sent by hand here, so it stays sent.");
            }
            return {"success": True, "sent": True, "status": current};
        }
        if current != "contacted" {
            return {"success": True, "sent": True, "status": current};
        }
        previous = await state.get_setting(key) or "queued";
        await state.update_prospect_status(
            prospect_id, previous if previous in HAND_SENDABLE_STATUSES else "queued"
        );
        await state.delete_setting(key);
        changed = await state.restore_hand_cancelled_outbox(prospect_id, reason=HAND_SENT_REASON);
    }
    if sent {
        await state.remember_footer_lines(_compliance_view()["footer"].split("\n"));
    }
    await state.log_action(
        action_type="manual_send" if sent else "manual_send_undone",
        agent="user",
        details={"prospect_id": prospect_id, "outbox_items": changed},
    );
    return {"success": True, "sent": sent};
}

@app.post("/api/outbox/{item_id}/reject")
@_OR_500
async def outbox_reject(item_id: str) -> any {
    if not await (await _open_state()).reject_outbox_item(item_id) {
        return _refuse("That email is already sending or sent, so it can't be rejected.");
    }
    return {"success": True};
}

@app.post("/api/sending/{action}")
@_OR_500
async def sending_toggle(action: str) -> any {
    if action not in ("pause", "resume") {
        return _refuse("unknown action", 400);
    }
    state = await _open_state();
    await state.set_setting("sending_paused", "paused from dashboard" if action == "pause" else "");
    if action == "resume" {
        await state.set_setting("bounce_count", "0");
    }
    return {"success": True};
}

@app.get("/api/export/prospects.csv")
async def export_prospects(all: bool = False, min_score: int = 0, email_status: str = "") -> any {
    state = StateManager(db_path=str(DB_PATH));
    try {
        await state.init_db();
        wanted = [s.strip() for s in email_status.split(",") if s.strip()];
        statuses: list[str] | None = None;
        if wanted {
            statuses = wanted;
        }
        (_, text) = await export_prospects_csv(
            state, email_statuses=statuses, min_score=min_score, include_all=all
        );
    } except Exception as e {
        logger.warning("Prospect export failed: %s", e);
        text = "";
    }
    return _csv(text, "prospects.csv");
}

@app.get("/api/campaigns")
async def get_campaigns -> any {
    rows = await query_db("SELECT * FROM campaigns ORDER BY created_at DESC LIMIT 100");
    sellbird_sends = _sellbird_can_send();
    send_as = "" if sellbird_sends else _send_as();
    footer = _compliance_view()["footer"];
    committed = await _sellbird_committed_ids();
    hand_sent = await _hand_sent_ids();
    for row in rows {
        row["sequence"] = _loads(row.get("sequence_json", "[]"), []);
        row["prospect_ids"] = _loads(row.get("prospect_ids_json", "[]"), []);
        ids = row["prospect_ids"];
        row["recipients"] = await _rows_in(
            "SELECT id, email, first_name, last_name, company, title, status, email_status, "
                "source, personalization_notes FROM prospects WHERE id IN (?) AND email != ''",
            ids,
        );
        row["send_as"] = send_as;
        row["footer"] = footer;
        for r in row["recipients"] {
            r["sent_by_hand"] = r["id"] in hand_sent;
            r["can_mark_sent"] = r["id"] not in hand_sent
                and r["id"] not in committed
                and (r.get("status") or "new") in HAND_SENDABLE_STATUSES;
            r["can_send_by_hand"] = r["can_mark_sent"]
                and not sellbird_sends
                and (r.get("email_status") or "guess") in HAND_SENDABLE_EMAIL;
        }
    }
    return rows;
}

glob _OPT_OUT_FIELDS = ("rule", "matched", "why", "message", "conversation_id");

def _last_opt_out(history: list[any]) -> any {
    return next((h for h in reversed(history) if h["action"] == "opt_out"), None);
}

def _their_messages(thread: any) -> list[any] {
    return [m for m in thread if isinstance(m, dict) and m.get("sender") == "prospect"];
}

@app.get("/api/prospects/{prospect_id}/opt-out")
async def get_opt_out(prospect_id: str) -> any {
    rows = await query_db("SELECT status FROM prospects WHERE id = ?", (prospect_id,));
    if not rows {
        return _refuse("unknown prospect", 404);
    }
    status = rows[0].get("status") or "new";
    history = await (await _open_state()).opt_out_history(prospect_id);
    last = _last_opt_out(history);
    out: dict[str, any] = {
        "opted_out": status == "opted_out",
        "status": status,
        "recorded": bool(last),
        "at": last["at"] if last else None,
        "rule": None,
        **dict.fromkeys(("matched", "why", "message", "conversation_id"), ""),
        "history": history,
    };
    if last {
        out.update({k: last.get(k) or out[k] for k in _OPT_OUT_FIELDS});
    } elif status == "opted_out" or history {
        for c in await query_db(
            "SELECT id, thread_json, updated_at FROM conversations WHERE prospect_id = ? ORDER BY updated_at DESC",
            (prospect_id,),
        ) {
            thread = _loads(c.get("thread_json") or "[]", None);
            if thread is None {
                continue;
            }
            theirs = _their_messages(thread);
            if theirs {
                out.update(
                    message=str(theirs[-1].get("content") or ""),
                    conversation_id=c["id"],
                    at=theirs[-1].get("timestamp") or c.get("updated_at"),
                );
                break;
            }
        }
    }
    return out;
}

@app.post("/api/prospects/{prospect_id}/opt-out/undo")
async def undo_opt_out(prospect_id: str, request: Request) -> any {
    body = await _json(request);
    if not isinstance(body, dict) or body.get("confirm") is not True {
        return _refuse('expected {"confirm": true}', 400);
    }
    rows = await query_db("SELECT email FROM prospects WHERE id = ?", (prospect_id,));
    if not rows {
        return _refuse("unknown prospect", 404);
    }
    state = await _open_state();
    last = _last_opt_out(await state.opt_out_history(prospect_id)) or {};
    details = {
        "prospect_email": rows[0].get("email") or "",
        "previous_why": last.get("why", ""),
        "previous_at": last.get("at", ""),
    };
    if not await state.undo_opt_out(prospect_id, details=details) {
        return _refuse("This person isn't opted out.");
    }
    return {"success": True, "status": "replied"};
}

@app.get("/api/offers/accepted")
async def get_offers_accepted -> any {
    rows = await query_db(
        "SELECT c.id AS conversation_id, c.status, c.updated_at, c.prospect_id, "
            "p.first_name, p.last_name, p.email, p.title, p.company, p.company_id "
            "FROM conversations c LEFT JOIN prospects p ON c.prospect_id = p.id "
            "WHERE c.intent = 'accepted_offer' ORDER BY c.updated_at DESC LIMIT 100",
    );
    for row in rows {
        done = await query_db(
            "SELECT value FROM settings WHERE key = ?",
            ("handoff:" + str(row.get("prospect_id") or ""),),
        );
        row["handoff"] = _loads(done[0]["value"], None) if done else None;
    }
    return {"accepted": rows};
}

def _thread_emails(sent: list[any], camp: str) -> list[any] {
    out: list[any] = [];
    for e in sent {
        if not camp or e.get("campaign_id") == camp {
            shown = dict(e);
            shown.pop("campaign_id", None);
            out.append(shown);
        }
    }
    return out;
}

@app.get("/api/conversations")
async def get_conversations(`awaiting: bool = False) -> any {
    rows = await query_db(
        "SELECT c.*, p.first_name, p.last_name, p.email as prospect_email, p.company, "
            "p.status as prospect_status FROM conversations c "
            "LEFT JOIN prospects p ON c.prospect_id = p.id ORDER BY c.updated_at DESC LIMIT 100",
    );
    pids = sorted({r["prospect_id"] for r in rows if r.get("prospect_id")});
    emails: dict[any, list[any]] = {};
    for e in await _rows_in(
        "SELECT prospect_id, campaign_id, step, subject, body, sent_at FROM outbox "
            "WHERE kind = 'sequence' AND status = 'sent' AND prospect_id IN (?) ORDER BY sent_at",
        pids,
    ) {
        emails.setdefault(e.pop("prospect_id"), []).append(e);
    }
    draft_rows = await _rows_in(
        "SELECT id, conversation_id, subject, body, send_at FROM outbox WHERE kind = 'reply' "
            "AND status = 'pending_review' AND conversation_id IN (?) ORDER BY created_at",
        [r["id"] for r in rows],
    );
    drafts = {dr.pop("conversation_id"): dr for dr in draft_rows};
    for row in rows {
        row["thread"] = _loads(row.get("thread_json", "[]"), []);
        row["emails"] = _thread_emails(
            emails.get(row.get("prospect_id"), []), row.get("campaign_id") or ""
        );
        row["draft"] = drafts.get(row["id"]);
    }
    if `awaiting {
        rows += await _awaiting_reply();
    }
    return rows;
}

def _picked(row: dict[any, any], keys: any) -> dict[any, any] {
    return {k: row[k] for k in keys};
}

glob _PERSON_COLUMNS = "first_name last_name prospect_email company prospect_status".split();

def _awaiting_row(pid: str, e: dict[any, any]) -> dict[any, any] {
    return {
        "id": "awaiting-" + pid,
        "prospect_id": pid,
        "campaign_id": "",
        "channel": "email",
        "intent": "",
        "stage": "",
        "status": "awaiting_reply",
        "thread": [],
        "draft": None,
        "emails": [],
        **{k: e.get(k) or "" for k in _PERSON_COLUMNS},
    };
}

async def _awaiting_reply -> list[any] {
    waiting: dict[str, dict[any, any]] = {};
    sent = await query_db(
        "SELECT o.prospect_id, o.step, o.subject, o.body, o.sent_at, "
            "p.first_name, p.last_name, p.email AS prospect_email, p.company, "
            "p.status AS prospect_status FROM outbox o JOIN prospects p ON p.id = o.prospect_id "
            "WHERE o.kind = 'sequence' AND o.status = 'sent' "
            "AND p.status NOT IN ('replied', 'opted_out', 'lost', 'meeting', 'closed') "
            "AND COALESCE(p.email_status, '') != 'invalid' "
            "AND NOT EXISTS (SELECT 1 FROM conversations c JOIN prospects q ON q.id = c.prospect_id "
            "WHERE q.id = p.id OR (q.company_id = p.company_id AND COALESCE(p.company_id, '') != '')) "
            "ORDER BY o.sent_at DESC LIMIT 2000",
    );
    for e in reversed(sent) {
        pid = e["prospect_id"];
        if pid not in waiting {
            waiting[pid] = _awaiting_row(pid, e);
        }
        row = waiting[pid];
        row["emails"].append(_picked(e, ("step", "subject", "body", "sent_at")));
        row["created_at"] = row.get("created_at") or e["sent_at"];
        row["updated_at"] = e["sent_at"];
    }
    return sorted(
        waiting.values(), key=lambda (r: any) -> any { r.get("updated_at") or "" }, reverse=True
    );
}

@app.post("/api/conversations/{convo_id}/status")
async def set_conversation_status(convo_id: str, request: Request) -> any {
    data = await _json(request, {});
    status = data.get("status") if isinstance(data, dict) else None;
    if status not in ("open", "closed") {
        return _refuse("status must be open or closed", 400);
    }
    rows = await query_db("SELECT status FROM conversations WHERE id = ?", (convo_id,));
    if not rows {
        return _refuse("No such conversation.", 404);
    }
    state = _state();
    await state.update_conversation(convo_id, status=status);
    await state.log_action(
        "conversation_status",
        "dashboard",
        {"conversation_id": convo_id, "from": rows[0]["status"], "to": status},
    );
    return {"success": True, "status": status};
}

async def _per_day(
    shift: str, labels: list[any], table: str, column: str, where: str = ""
) -> list[int] {
    rows = await query_db(
        f"SELECT date({column}, ?) AS d, COUNT(*) AS n FROM {table} WHERE date({column}, ?) >= ? {where} GROUP BY d",
        (shift, shift, labels[0]),
    );
    counts = {r["d"]: r["n"] for r in rows};
    return [counts.get(day, 0) for day in labels];
}

@app.get("/api/trend")
async def get_trend(days: int = 14, tz: int = 0) -> any {
    days = max(1, min(90, days));
    tz = max(-840, min(840, tz));
    shift = f"{tz:+d} minutes";
    today = (datetime.now(timezone.utc) + timedelta(minutes=tz)).date();
    labels = [(today - timedelta(days=n)).isoformat() for n in range(days - 1, -1, -1)];
    return {
        "days": labels,
        "found": await _per_day(shift, labels, "prospects", "created_at"),
        "sent": await _per_day(shift, labels, "outbox", "sent_at", "AND status = 'sent'"),
        "replies": await _per_day(shift, labels, "conversations", "created_at"),
    };
}

@app.get("/api/activity")
async def get_activity -> any {
    rows = await query_db("SELECT * FROM actions ORDER BY created_at DESC LIMIT 100");
    for row in rows {
        row["details"] = _loads(row.get("details_json", "{}"), {});
    }
    return rows;
}

glob _discovery_task: any = None,
     _discovery_report: any = None,
     _discovery_kind = "discover",
     _BUSY_RUN = "a run is already going";

def _discovery_queries(body: dict[any, any], config: any) -> any {
    preset = str(body.get("preset") or "");
    problem = preset_problem(preset, str(body.get("provider") or ""), config=config);
    if problem {
        raise ValueError(problem);
    }
    cities = [c.strip() for c in (body.get("cities") or []) if c.strip()];
    return build_queries(
        config,
        cities=cities or None,
        depth=int(body.get("depth") or 30),
        limit=int(body.get("limit") or 100),
        preset=preset,
    );
}

def _running -> bool {
    return bool(_discovery_task and not _discovery_task.done());
}

@app.get("/api/discover/providers")
async def get_discovery_providers -> any {
    try {
        state = await _open_state();
        return {
            "providers": provider_menu(load_env().model_dump()),
            "default": DEFAULT_PROVIDER,
            "selected": await state.get_setting("discovery_provider") or DEFAULT_PROVIDER,
            "paused": await state.get_setting("discovery_paused"),
            "running": _running(),
            "running_kind": _discovery_kind,
            "unprofiled": await state.count_companies_needing_profile(),
            "last_report": _discovery_report,
        };
    } except Exception as e {
        logger.exception("discovery providers failed");
        return {"providers": [], "error": str(e)};
    }
}

@app.post("/api/discover/estimate")
async def estimate_discovery(request: Request) -> any {
    try {
        body = await request.json();
        provider = body.get("provider") or "";
        if provider not in PROVIDERS {
            return _error(f"unknown provider {provider!r}", 400);
        }
        try {
            queries = _discovery_queries(body, load_config());
        } except ValueError as e {
            return _error(str(e), 400);
        }
        return {
            "provider": provider,
            "queries": [q.keyword() for q in queries],
            "query_count": len(queries),
            "estimated_cost": round(estimate_cost(provider, queries), 4),
            "free": PROVIDERS[provider].estimate(queries) == 0,
        };
    } except Exception as e {
        return _error(str(e));
    }
}

async def _discover_report(
    state: any, config: any, provider: str, queries: any, spend: float
) -> any {
    result = await run_prospecting(state, config, provider, queries, max_spend=spend);
    return {
        **(result.discover or {}),
        "profiled_companies": result.profiled_companies,
        "profile_observations": result.profile_observations,
        "errors": result.errors,
    };
}

async def _profile_report(state: any) -> any {
    try {
        config: any = load_config();
    } except Exception {
        config = None;
    }
    (companies, observations, _) = await run_profile_stage(state, limit=200, config=config);
    return {"profiled_companies": companies, "profile_observations": observations};
}

async def _finish_run(name: str, work: any) {
    try {
        _discovery_report = await work;
    } except Exception as exc {
        logger.exception(f"{name} run failed");
        _discovery_report = {"errors": [str(exc)], "stopped": "failed"};
    }
}

def _launch(kind: str, work: any) {
    _discovery_kind = kind;
    _discovery_report = None;
    _discovery_task = asyncio.create_task(
        _finish_run("discovery" if kind == "discover" else kind, work)
    );
}

@app.post("/api/discover/run")
@_OR_500
async def start_discovery(request: Request) -> any {
    if _running() {
        return _refuse(_BUSY_RUN);
    }
    body = await request.json();
    provider = body.get("provider") or "";
    if provider not in PROVIDERS {
        return _refuse(f"unknown provider {provider!r}", 400);
    }
    config = load_config();
    try {
        queries = _discovery_queries(body, config);
    } except ValueError as e {
        return _refuse(str(e), 400);
    }
    max_spend = float(body.get("max_spend") or 1.0);
    state = await _open_state();
    await state.set_setting("discovery_provider", provider);
    await state.set_setting("discovery_paused", "");
    _launch("discover", _discover_report(state, config, provider, queries, max_spend));
    return {"success": True, "queries": len(queries)};
}

@app.post("/api/profile/run")
@_OR_500
async def start_profile -> any {
    if _running() {
        return _refuse(_BUSY_RUN);
    }
    state = await _open_state();
    pending = await state.count_companies_needing_profile();
    if not pending {
        return {"success": True, "pending": 0};
    }
    _launch("profile", _profile_report(state));
    return {"success": True, "pending": pending};
}

@app.post("/api/discover/stop")
@_OR_500
async def stop_discovery -> any {
    await (await _open_state()).set_setting("discovery_paused", "stopped from dashboard");
    return {"success": True};
}

def _parse_ts(value: any) -> datetime | None {
    if not value {
        return None;
    }
    try {
        return datetime.fromisoformat(str(value).replace("Z", "").split("+")[0]);
    } except ValueError {
        return None;
    }
}

async def _scalar(sql: str, params: tuple[any, ...] = ()) -> int {
    rows = await query_db(sql, params);
    return int(next(iter(rows[0].values())) or 0) if rows else 0;
}

async def _first(sql: str, params: tuple[any, ...] = (), key: str = "t") -> any {
    rows = await query_db(sql, params);
    return rows[0].get(key) if rows else None;
}

glob STALE_RUN_SECONDS = 900,
     CONTACT_ACTIVE_SECONDS = 180,
     SENT_STATUSES = ("contacted", "replied", "meeting", "closed", "lost", "opted_out"),
     REPLY_STATUSES = ("replied", "meeting", "closed");

def _eta_text(minutes: any) -> str {
    if minutes is None {
        return "";
    }
    return "less than a minute left" if minutes < 1 else f"about {round(minutes)} min left";
}

def _step(
    label: str, done: int, total: int, active: bool, detail: str, info: bool = False
) -> dict[str, any] {
    complete = bool(done) if info else bool(total and done >= total);
    state = "running"
        if active
        else "done" if complete else "partial" if done and not info else "waiting";
    return {"label": label, "done": done, "total": total, "state": state, "detail": detail};
}

async def _stalled(run: dict[any, any], now: any) -> bool {
    last = _parse_ts(
        await _first(
            "SELECT MAX(observed_at) AS t FROM observations WHERE run_id = ?", (run["id"],)
        ),
    )
        or _parse_ts(run.get("started_at"));
    return bool(last and (now - last).total_seconds() > STALE_RUN_SECONDS);
}

def _drafted_ids(rows: list[any]) -> set[any] {
    drafted: set[any] = set();
    for row in rows {
        ids = _loads(row.get("prospect_ids_json") or "[]", []);
        if isinstance(ids, list) {
            drafted.update(filter(_is_str, ids));
        }
    }
    return drafted;
}

@app.get("/api/live-status")
async def get_live_status -> any {
    now = datetime.now(timezone.utc).replace(tzinfo=None);
    has_site = "COALESCE(domain, '') != ''";
    companies = await _scalar("SELECT COUNT(*) FROM companies");
    with_site = await _scalar(f"SELECT COUNT(*) FROM companies WHERE {has_site}");
    no_site = companies - with_site;
    read = f"SELECT COUNT(*) FROM companies WHERE {has_site} AND profile_checked_at IS NOT NULL";
    profiled = await _scalar(read);
    checked = await _scalar(read + " AND prospects_checked_at IS NOT NULL");
    prospects = await query_db("SELECT id, email, email_status, status FROM prospects");
    with_email = [p for p in prospects if p.get("email")];
    by_status = Counter([(p.get("email_status") or "guess").lower() for p in with_email]);
    deliverable = {p["id"] for p in with_email if p.get("email_status") in ("verified", "risky")};
    unconfirmed = len(with_email) - by_status["verified"] - by_status["risky"] - by_status["invalid"];
    drafted = _drafted_ids(await query_db("SELECT prospect_ids_json FROM campaigns"));
    sent = {p["id"] for p in prospects if p.get("status") in SENT_STATUSES};
    sellbird_sends = _sellbird_can_send();
    awaiting_review = await _scalar("SELECT COUNT(*) FROM outbox WHERE status = 'pending_review'");
    by_hand: set[any] = set();
    if not sellbird_sends {
        skipped = await _sellbird_committed_ids() | await _hand_sent_ids();
        by_hand = {
            p["id"]
            for p in prospects
            if p["id"] in drafted
                and p["id"] not in skipped
                and (p.get("status") or "new") in HAND_SENDABLE_STATUSES
                and (p.get("email_status") or "guess") in HAND_SENDABLE_EMAIL
        };
    }
    replies = sum(1 for p in prospects if p.get("status") in REPLY_STATUSES);
    cost = float(await _first("SELECT COALESCE(SUM(cost_usd), 0) AS c FROM runs", key="c") or 0);
    running: list[any] = [];
    stopped: list[any] = [];
    for run in await query_db("SELECT * FROM runs WHERE status = 'running' ORDER BY started_at") {
        started = _parse_ts(run.get("started_at"));
        elapsed = max(0.0, (now - started).total_seconds()) if started else 0.0;
        item: dict[str, any] = {
            "stage": run.get("stage"),
            "provider": run.get("provider"),
            "elapsed_min": round(elapsed / 60, 1),
            "eta_min": None,
        };
        if await _stalled(run, now) {
            stopped.append(item);
            continue;
        }
        if run.get("stage") == "profile" and started {
            done_in_run = await _scalar(
                f"SELECT COUNT(*) FROM companies WHERE {has_site} AND profile_checked_at >= ?",
                (run["started_at"],),
            );
            left = max(0, with_site - profiled);
            if left and done_in_run and elapsed > 0 {
                item["eta_min"] = left / (done_in_run / elapsed) / 60;
            }
        }
        running.append(item);
    }
    last_contact = _parse_ts(await _first("SELECT MAX(prospects_checked_at) AS t FROM companies"));
    finding_emails = bool(last_contact and (now - last_contact).total_seconds() < CONTACT_ACTIVE_SECONDS);
    stages = [r["stage"] for r in running];
    (reading, finding) = ("profile" in stages, "discover" in stages);
    profile_eta = next((r["eta_min"] for r in running if r["stage"] == "profile"), None);
    read_detail = f"{profiled} of {with_site} read";
    if reading and profile_eta is not None {
        read_detail += " · " + _eta_text(profile_eta);
    }
    if no_site {
        read_detail += f" · {no_site} have no website (skipped)";
    }
    bad = f" · {by_status['invalid']} bad" if by_status["invalid"] else "";
    (n_mail, n_draft, n_sent) = (len(with_email), len(drafted), len(sent & drafted));
    found_detail = f"{checked} of {profiled} checked · {n_mail} emails found";
    real_detail = f"{by_status.get('verified', 0)} verified · {by_status.get('risky', 0)} risky · {unconfirmed} not confirmed{bad}";
    reply_detail = f"{replies} replies" if replies else "No replies yet";
    to_write = len(deliverable | drafted);
    steps = [
        _step("Find businesses", companies, 0, finding, f"{companies} businesses found", info=True),
        _step("Read their websites", profiled, with_site, reading, read_detail),
        _step("Find emails", checked, profiled, finding_emails, found_detail),
        _step("Check emails are real", n_mail - unconfirmed, n_mail, False, real_detail),
        _step("Write first emails", n_draft, to_write, False, f"{n_draft} written · see Campaigns"),
        _step("Sent", n_sent, n_draft, False, f"{n_sent} of {n_draft} sent"),
        _step("Replies", replies, 0, False, reply_detail, info=True),
    ];
    next_tab = "discover";
    if reading or finding {
        (next_up, next_tab) = ("Wait — Sellbird is working. This page updates by itself.", "");
    } elif finding_emails {
        (next_up, next_tab) = ("Wait — emails are being found.", "");
    } elif stopped {
        next_up = "A job stopped before finishing. Run it again.";
    } elif sellbird_sends and awaiting_review {
        next_up = f"Review the {awaiting_review} draft(s) waiting in the Outbox.";
        next_tab = "outbox";
    } elif by_hand {
        next_up = f"Open Campaigns and send the {len(by_hand)} unsent email(s).";
        next_tab = "campaigns";
    } elif profiled > checked {
        next_up = f"Find emails for the {profiled - checked} businesses not checked yet.";
        next_tab = "controls";
    } elif deliverable - drafted {
        next_up = f"Write first emails for {len(deliverable - drafted)} more contact(s).";
        next_tab = "controls";
    } elif not companies {
        next_up = "Search for businesses to get started.";
    } else {
        next_up = "Search more cities or industries to get more leads.";
    }
    return {
        "steps": steps,
        "running": [dict(r, eta_text=_eta_text(r["eta_min"])) for r in running],
        "stopped": stopped,
        "next": next_up,
        "next_tab": next_tab,
        "cost_usd": round(cost, 4),
        "updated_at": now.isoformat() + "Z",
    };
}

def _require_approval_now -> bool {
    try {
        return bool(load_config(str(_resolve_config_file())).channels.email.require_approval);
    } except Exception {
        return True;
    }
}

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

def _today(key: str, **values: any) -> dict[str, any] {
    (tone, title, detail, action, tab) = [part.format(**values) for part in _TODAY[key].split("|")];
    return {
        "key": key,
        "tone": tone,
        "title": title,
        "detail": detail,
        "action": action,
        "tab": tab,
    };
}

def _plural(n: int, one: str, many: str) -> str {
    return f"{n} {one}" if n == 1 else f"{n} {many}";
}

@app.get("/api/today")
async def get_today -> any {
    items: list[any] = [];
    stats: dict[str, any] = {};
    try {
        state = await _open_state();
        await seed_signal_catalog(state);
        codes = await state.get_signal_codes();
        proposed = [c for c in codes if c.get("status") == "proposed"];
        confirmed = [c for c in codes if c.get("status") == "confirmed"];
        pending = await state.get_outbox(status="pending_review", limit=200);
        approved = await state.get_outbox(status="approved", limit=200);
        paused = await state.get_setting("sending_paused");
        counts = await state.count_prospects_by_status();
        convos = await _count_map("conversations");
        (open_convos, needs_human) = (convos.get("open", 0), convos.get("needs_human", 0));
        n_companies = await _scalar("SELECT COUNT(*) AS n FROM companies");
        unprofiled = await state.count_companies_needing_profile();
        stats = {
            "companies": n_companies,
            "prospects": sum(counts.values()),
            "signals_confirmed": len(confirmed),
            "outbox_pending": len(pending),
            "outbox_approved": len(approved),
            "open_conversations": open_convos,
            "needs_human": needs_human,
            "signals_proposed": len(proposed),
            "email_provider": _current_provider(),
            "unprofiled": unprofiled,
        };
        brain = await _brain_status();
        if brain.get("status") == "paused" {
            who = "Codex" if brain.get("provider") == "codex" else "Sellbird's model";
            reason = str(brain.get("reason") or "It can't be used right now.")[:300];
            items.append(_today("brain-paused", who=who, reason=reason));
        }
        rules_problem = await state.get_setting(EMAIL_RULES_PROBLEM_KEY);
        if rules_problem {
            items.append(_today("email-rules", problem=rules_problem));
        }
        hold = await state.current_sends_held();
        if hold {
            (title, detail) = held_message(hold, waiting=len(approved));
            items.append(_today("sends-held", title=title, detail=detail));
        }
        if paused {
            items.append(_today("paused", paused=paused));
        }
        try {
            loaded: any = load_config(str(_resolve_config_file()));
        } except Exception {
            loaded = None;
        }
        precleared_hold = await current_hold(state, loaded);
        if precleared_hold {
            message = hold_message(precleared_hold);
            item = _today("precleared-hold", **message);
            items.append({**item, "url": message["url"], "url_label": message["url_label"]});
        }
        setup = await get_setup_status();
        if isinstance(setup, dict) and setup.get("percent", 100) < 100 {
            missing = [
                c["label"]
                for c in setup.get("checks", [])
                if c.get("required") and not c.get("done")
            ];
            detail = ", ".join(missing[:3]) or "Some required steps are incomplete.";
            items.append(_today("setup", detail=detail));
        }
        if proposed {
            items.append(_today("signals", title=_plural(len(proposed), "signal", "signals")));
        } elif not confirmed {
            items.append(_today("signals-none"));
        }
        if not n_companies and confirmed {
            items.append(_today("discover"));
        }
        if unprofiled {
            items.append(_today("profile", n=unprofiled));
        }
        if needs_human {
            title = _plural(needs_human, "conversation needs you", "conversations need you");
            items.append(_today("needs-human", title=title));
        }
        if pending {
            detail = "Nothing sends until you approve it."
                if _require_approval_now()
                else "Autopilot sends the rest on its own; these wait for you.";
            title = _plural(len(pending), "email", "emails");
            items.append(
                _today("outbox", title=title, detail=detail + " Read them one at a time.")
            );
        }
        if open_convos {
            title = _plural(open_convos, "live conversation", "live conversations");
            items.append(_today("replies", title=title));
        }
        return {"items": items, "stats": stats};
    } except Exception as e {
        logger.exception("today load failed");
        return {"items": [], "stats": stats, "error": str(e)};
    }
}

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

def _signal_rows(codes: list[any], cat: str, counts: dict[any, any]) -> list[any] {
    return [
        {**sig, **_seen(counts.get(sig["code"], {}))}
        for sig in codes
        if sig.get("category") == cat
    ];
}

def _seen(found: dict[any, any]) -> dict[str, any] {
    return {"companies": found.get("companies", 0), "observations": found.get("observations", 0)};
}

@app.get("/api/signals")
async def get_signals -> any {
    try {
        state = await _open_state();
        await seed_signal_catalog(state);
        codes = await state.get_signal_codes();
        counts = {c["signal_code"]: c for c in await state.signal_counts()};
        groups: list[any] = [];
        for cat in CATEGORY_ORDER {
            rows = _signal_rows(codes, cat, counts);
            if rows {
                groups.append({"key": cat, **CATEGORY_META[cat], "signals": rows});
            }
        }
        summary: dict[any, any] = {"proposed": 0, "confirmed": 0, "rejected": 0};
        summary.update(dict(Counter([sig.get("status", "proposed") for sig in codes])));
        return {"summary": summary, "groups": groups, "total": len(codes)};
    } except Exception as e {
        logger.exception("signals load failed");
        return {"error": str(e), "groups": [], "summary": {}};
    }
}

@app.post("/api/signals/status")
@_OR_500
async def set_signals_status(request: Request) -> any {
    body = await request.json();
    status = (body.get("status") or "").strip();
    codes = body.get("codes") or ([body["code"]] if body.get("code") else []);
    if status not in ("proposed", "confirmed", "rejected") {
        return _refuse(f"invalid status: {status!r}", 400);
    }
    if not codes {
        return _refuse("no signal codes given", 400);
    }
    state = await _open_state();
    await seed_signal_catalog(state);
    unknown: list[any] = [];
    for code in codes {
        if not await state.set_signal_status(code, status) {
            unknown.append(code);
        }
    }
    return {
        "success": True,
        "changed": len(codes) - len(unknown),
        "status": status,
        "unknown": unknown,
    };
}

async def _cohort_companies(
    require: list[str], exclude: list[str], offset: int = 0, limit: any = None, ranges: any = None
) -> any {
    return await (await _open_state()).cohort_companies(
        require, exclude, offset, limit, ranges=ranges
    );
}

def _codes(raw: any) -> list[str] {
    if raw is None {
        return [];
    }
    if isinstance(raw, str) {
        raw = raw.split(",");
    }
    if not isinstance(raw, list) or any(not isinstance(c, str) for c in raw) {
        raise ValueError("signals must be a list of strings or comma-separated string");
    }
    codes = list(dict.fromkeys(c.strip() for c in raw if c.strip()));
    if len(codes) > 200 or any(len(c) > 128 for c in codes) {
        raise ValueError("too many or oversized signal codes");
    }
    return codes;
}

def _range_bound(raw: any) -> float | None {
    if raw is None or raw == "" {
        return None;
    }
    if isinstance(raw, bool) or not isinstance(raw, (int, float, str)) {
        raise ValueError("range bounds must be numbers");
    }
    value = float(raw);
    if value != value or abs(value) > 1e12 {
        raise ValueError("range bound is out of bounds");
    }
    return value;
}

def _range_items(raw: str) -> list[any] {
    pieces = [part.split(":") for part in raw.split(",") if part.strip()];
    if any(len(p) != 3 for p in pieces) {
        raise ValueError("ranges look like CODE:min:max");
    }
    return [{"code": code, "min": low, "max": high} for (code, low, high) in pieces];
}

def _ranges(raw: any) -> list[any] {
    if raw is None or raw == "" or raw == [] {
        return [];
    }
    if isinstance(raw, str) {
        raw = _range_items(raw);
    }
    if not isinstance(raw, list) or any(not isinstance(r, dict) for r in raw) {
        raise ValueError("ranges must be a list of {code, min, max}");
    }
    if len(raw) > COHORT_MAX_RANGES {
        raise ValueError("too many ranges");
    }
    out: list[any] = [];
    for r in raw {
        code = r.get("code");
        if not isinstance(code, str) or not code.strip() or len(code) > 128 {
            raise ValueError("each range needs a signal code");
        }
        (low, high) = (_range_bound(r.get("min")), _range_bound(r.get("max")));
        if low is None and high is None {
            raise ValueError(f"range on {code} needs a min or a max");
        }
        if low is not None and high is not None and low > high {
            raise ValueError(f"range on {code}: min is above max");
        }
        out.append({"code": code.strip(), "min": low, "max": high});
    }
    return out;
}

def _cohort_integer(raw: any, fallback: int) -> int {
    if raw is None {
        return fallback;
    }
    if isinstance(raw, bool) or not isinstance(raw, (int, str)) {
        raise ValueError("offset and limit must be integers");
    }
    value = builtins.int(raw);
    if abs(value) > 9223372036854775807 {
        raise ValueError("offset or limit is too large");
    }
    return value;
}

@app.post("/api/cohort")
async def preview_cohort(request: Request) -> any {
    try {
        body = await request.json();
        if not isinstance(body, dict) {
            raise ValueError("request body must be an object");
        }
        require = _codes(body.get("require"));
        exclude = _codes(body.get("exclude"));
        ranges = _ranges(body.get("ranges"));
        offset = max(0, _cohort_integer(body.get("offset"), 0));
        limit = min(
            max(1, _cohort_integer(body.get("limit"), COHORT_PAGE_SIZE)), COHORT_MAX_PAGE_SIZE
        );
        if not require and not ranges {
            return {"size": 0, "offset": 0, "limit": limit, "companies": []};
        }
        (size, rows) = await _cohort_companies(require, exclude, offset, limit, ranges);
        return {"size": size, "offset": offset, "limit": limit, "companies": rows};
    } except (ValueError, TypeError) as e {
        return _error(str(e), 400);
    } except Exception as e {
        return JSONResponse({"size": 0, "companies": [], "error": str(e)}, status_code=500);
    }
}

def _csv_cell(value: any) -> str {
    text = str(value or "");
    if text.lstrip().startswith(("=", "+", "-", "@")) or text.startswith(("\t", "\r", "\n")) {
        return "'" + text;
    }
    return text;
}

@app.get("/api/cohort.csv")
async def export_cohort(require: str = "", exclude: str = "", ranges: str = "") -> any {
    buf = io.StringIO();
    writer = csv.writer(buf);
    writer.writerow(list(_COHORT_COLUMNS));
    try {
        (codes, excluded, bounds) = (_codes(require), _codes(exclude), _ranges(ranges));
        if codes or bounds {
            (_, rows) = await _cohort_companies(codes, excluded, ranges=bounds);
            for r in rows {
                writer.writerow([_csv_cell(r.get(k)) for k in _COHORT_COLUMNS]);
            }
        }
    } except ValueError as e {
        return _error(str(e), 400);
    } except Exception as e {
        logger.warning("Cohort export failed: %s", e);
        return _error("Cohort export failed");
    }
    return _csv(buf.getvalue(), "cohort.csv");
}

@app.get("/api/runs")
@_OR_ERROR
async def get_runs_api -> any {
    state = await _open_state();
    await state.sweep_stale_runs();
    runs = await state.get_runs(limit=25);
    now = datetime.now(timezone.utc).replace(tzinfo=None);
    for run in runs {
        if run.get("status") == "running" and await _stalled(run, now) {
            run["status"] = "stalled";
        }
    }
    return runs;
}

glob WEB_DIR = Path(__file__).resolve().parent / "web",
     TEXT_TYPES = {".css": "text/css", ".js": "text/javascript", ".svg": "image/svg+xml"},
     BINARY_TYPES = {".woff2": "font/woff2", ".woff": "font/woff", ".png": "image/png"};

@app.get("/static/{path:path}")
async def static_file(path: str) -> any {
    target = (WEB_DIR / path).resolve();
    if not target.is_file() or not target.is_relative_to(WEB_DIR.resolve()) {
        return PlainTextResponse("not found", status_code=404);
    }
    if target.suffix in BINARY_TYPES {
        return Response(
            target.read_bytes(),
            media_type=BINARY_TYPES[target.suffix],
            headers={"Cache-Control": "public, max-age=604800"},
        );
    }
    return PlainTextResponse(
        target.read_text(encoding="utf-8"),
        media_type=TEXT_TYPES.get(target.suffix, "text/plain"),
        headers={"Cache-Control": "no-store"},
    );
}

@app.get("/", response_class=HTMLResponse)
async def dashboard -> any {
    return (WEB_DIR / "index.html").read_text(encoding="utf-8");
}

class DashboardSetupError(Exception) {}

def _check_loopback_bind(host: str) -> str {
    name = (host or "").strip().lower();
    if name.startswith("[") and name.endswith("]") {
        name = name[1:-1];
    }
    if not auth.is_loopback(name) {
        raise DashboardSetupError(
            f"Refusing to listen on {host!r}: the dashboard only listens on this machine (127.0.0.1, ::1 or localhost). To reach it from elsewhere, tunnel instead: ssh -L 5555:127.0.0.1:5555 <this-host>",
        );
    }
    return name;
}

def dashboard_url(host: str = "127.0.0.1", port: int = 5555) -> str {
    name = _check_loopback_bind(host);
    try {
        if ipaddress.ip_address(name).version == 6 {
            name = f"[{name}]";
        }
    } except ValueError {}
    return f"http://{name}:{port}/#token={token_store.get()}";
}

glob INSTANCE_ID = uuid.uuid4().hex;

@app.get("/api/instance")
async def get_instance -> any {
    return {"instance": INSTANCE_ID};
}

with entry {
    app.include_router(_inbox_router);
    for _router in _extensions.registry().routers {
        app.include_router(_router);
    }
}

def build_app(*, guard: Middleware | None = None, routers: Sequence[APIRouter] = ()) -> FastAPI {
    new = FastAPI(title=app.title, docs_url=None, redoc_url=None, openapi_url=None);
    for router in routers {
        new.include_router(router);
    }
    new.router.routes.append(Mount("", app=app.router));
    new.user_middleware = [
        guard if guard is not None and m.cls is auth.DashboardGuard else m
        for m in app.user_middleware
    ];
    new.exception_handlers.update(app.exception_handlers);
    return new;
}

def start_dashboard(host: str = "127.0.0.1", port: int = 5555) {
    try {
        bind = _check_loopback_bind(host);
        url = dashboard_url(host, port);
    } except (DashboardSetupError, auth.TokenError) as e {
        raise DashboardSetupError(str(e)) from e;
    }
    print(f"\n  Sellbird Dashboard running. Open this link to unlock it:\n\n    {url}\n");
    print(f"  The token is stored in {token_store.path} (owner-only). Keep the link");
    print("  private; anyone with it can use the dashboard. Press Ctrl+C to stop.\n");
    if os.name == "nt" {
        print("  Windows: the token file is protected by your folder's permissions,");
        print("  not POSIX file modes.\n");
    }
    dashboard_instance.write(DB_PATH.parent, host=bind, port=port, instance=INSTANCE_ID);
    try {
        uvicorn.run(
            app,
            host=bind,
            port=port,
            log_level="warning",
            proxy_headers=False,
            server_header=False,
            date_header=False,
        );
    } finally {
        dashboard_instance.remove(DB_PATH.parent, instance=INSTANCE_ID);
    }
}
