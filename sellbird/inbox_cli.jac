import argparse;
import asyncio;
import getpass;
import importlib;
import sys;
import from datetime { date }

glob MAIN_NAME = "main",
     _ADDRESS_ACTIONS = [
         ("test", "Check one inbox can sign in"),
         ("pause", "Stop sending from one inbox"),
         ("resume", "Send from a paused inbox again"),
         ("cap", "Set one inbox's daily cold-email cap"),
         ("name", "Change the name an inbox sends as"),
         ("remove", "Stop using an inbox for good (its sign-in stays in your keychain)"),
     ],
     _LOGGED = dict(
         pause="inbox_paused", resume="inbox_resumed", cap="inbox_cap", remove="inbox_removed"
     ),
     _PAUSED = "Its unsent first emails move to your other inboxes; follow-ups and replies on threads it started wait for it.",
     _REMOVED = "Its unsent first emails move to your other inboxes; follow-ups on threads it started are cancelled. Its sign-in is still in your keychain (service 'sellbird'); delete it there if you like.",
     _USE_ID = "Use its id (sellbird status lists campaigns).",
     _RAISE_MAX = "  Note: max_daily_sends caps everything sent in a day across every inbox. Raise it in sellbird.yaml so this inbox adds to what goes out.";

def _date(value: str) -> str;

def _cap(value: str) -> int | None;

def _connect_args(p: any, smtp: bool);

def register(subparsers: any);

async def print_inbox_list(store: MailboxStore, config: any, env: any);

async def _test_and_print(provider: any) -> bool;

def _oauth_sign_in(args: any, env: any) -> dict[str, any] | None;

def read_smtp_password(args: any) -> str;

async def _build_and_test(row: any, config: any, env: any, secrets: any, missing: str) -> int;

async def connect_flow(
    args: any, store: MailboxStore, secrets: SecretStore, config: any, env: any
) -> int;

async def _find(store: MailboxStore, address: str) -> dict[any, any] | None;

async def _use(args: any, store: MailboxStore) -> int;

async def run(args: any, store: MailboxStore, secrets: SecretStore, config: any, env: any) -> int;

async def _run_inboxes(args: any, config: any, env: any) -> int;

def cmd_inboxes(args: any);
