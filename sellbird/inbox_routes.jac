import asyncio;
import importlib;
import logging;
import re;
import from fastapi { APIRouter, Request }
import from fastapi.responses { JSONResponse }

glob logger = logging.getLogger("sellbird.inbox_routes"),
     router = APIRouter(),
     MAIN_PATH = "main",
     MAIN_CONNECT_HINTS = {
         "gmail": "Sign in with Google below as this address (or run `sellbird gmail auth`).",
         "microsoft": "Sign in with Microsoft below as this address (or run `sellbird microsoft auth`).",
         "smtp": "Fill in the SMTP settings under channels.email in sellbird.yaml and the password in .env, then run `sellbird doctor`.",
     },
     _NO_INBOX = "No connected inbox with that id.",
     _NO_PAUSE = "No connected inbox with that id. The main mailbox pauses with all sending, on the Outbox tab.",
     _NO_CAP = "No connected inbox with that id. The main mailbox's cap is channels.email.per_inbox_daily_cap in sellbird.yaml.",
     _BAD_CAP = f"A cap is a whole number from 1 to {HARD_MAX_INBOX_CAP}, or null for the default.",
     _BAD_NAME = "A name is up to 100 characters, on one line, without < > or \".",
     _MAIN_ONLY = "The main mailbox signs in with a browser only for Gmail or Microsoft 365. Set channels.email.provider in sellbird.yaml.",
     _BUSY = "A sign-in is already open. Finish it in your browser, or wait five minutes for it to time out.",
     _UNFINISHED = "The sign-in didn't finish, or you signed in as a different address. ",
     _secrets: any = SecretStore,
     _connect_job: dict[str, any] = {"state": "idle"},
     _connect_task: any = None,
     _CLIENTS = {
         "gmail": (
             "gmail_client_id",
             "gmail_client_secret",
             re.compile(r"^\d+-[0-9a-z]+\.apps\.googleusercontent\.com$"),
             "Google sign-in isn't set up yet. Sellbird signs in to Gmail through your own Google OAuth client, so it needs its Client ID and secret first.",
             "The Google Client ID in Settings isn't a real one. It looks like 123456789-abc123.apps.googleusercontent.com.",
         ),
         "microsoft": (
             "m365_client_id",
             "",
             re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", re.I),
             "Microsoft sign-in isn't set up yet. Sellbird signs in through your own Microsoft app registration, so it needs its Application (client) ID first.",
             "The Microsoft Application (client) ID in Settings isn't a real one. It looks like 1b2c3d4e-5f60-7182-93a4-b5c6d7e8f901.",
         ),
     };

def _refuse(message: str, code: int = 400) -> any;

async def _store -> any;

def _config_env -> tuple[any, any];

async def _body(request: any) -> dict[str, any];

async def _row(store: any, mailbox_id: str) -> dict[str, any] | None;

async def _inbox(mailbox_id: str) -> tuple[any, any];

async def _log(store: any, action: str, agent: str = "you", **details: any);

def _pool(ids: any) -> list[str];

def _whole(value: any, top: int) -> bool;

def _failed(message: str);

@router.get("/api/inboxes")
async def list_inboxes -> any;

@router.post("/api/inboxes/{mailbox_id}/pause")
async def pause_inbox(mailbox_id: str, request: Request) -> any;

@router.post("/api/inboxes/{mailbox_id}/resume")
async def resume_inbox(mailbox_id: str) -> any;

@router.post("/api/inboxes/{mailbox_id}/cap")
async def set_inbox_cap(mailbox_id: str, request: Request) -> any;

@router.post("/api/inboxes/{mailbox_id}/name")
async def set_inbox_name(mailbox_id: str, request: Request) -> any;

@router.post("/api/inboxes/{mailbox_id}/remove")
async def remove_inbox(mailbox_id: str, request: Request) -> any;

@router.post("/api/campaigns/{campaign_id}/inboxes")
async def set_campaign_inboxes(campaign_id: str, request: Request) -> any;

def _connect_problem(kind: str, env: any) -> str;

async def _test(row: any, config: any, env: any, secrets: any) -> tuple[bool, str];

def _sign_in(kind: str, address: str, env: any, main: bool = False) -> dict[str, any] | None;

async def _run_connect(kind: str, fields: dict[str, any], main: bool = False);

def _start_sign_in(kind: str, fields: dict[str, any], env: any, main: bool) -> any;

@router.post("/api/inboxes/main/connect")
async def connect_main_mailbox -> any;

@router.post("/api/inboxes/connect/{kind}")
async def connect_inbox(kind: str, request: Request) -> any;

@router.get("/api/inboxes/connect/status")
async def connect_status -> any;

@router.post("/api/inboxes/{mailbox_id}/test")
async def test_inbox(mailbox_id: str) -> any;
