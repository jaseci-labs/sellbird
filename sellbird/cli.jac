import argparse;
import builtins;
import asyncio;
import importlib;
import subprocess;
import sys;
import textwrap;
import from collections { Counter }
import from datetime { date }
import from pathlib { Path }

glob MIN_PYTHON = (3, 11),
     _INDENT = " " * 24,
     _LABELS = {"claude": "Claude", "codex": "Codex"},
     _OLD_PYTHON = """  On macOS, `python3` is usually the system 3.9, so a venv built
  with it is 3.9 too. Build the venv from a newer Python instead:

    brew install python@3.13
    rm -rf .venv
    $(brew --prefix)/bin/python3.13 -m venv .venv
    source .venv/bin/activate && pip install -e .
""",
     _NOT_IMPORTABLE = """
  Warning: 'import sellbird' fails outside the project directory.
  Run sellbird commands from the project root, or reinstall with:
    pip install -e . --config-settings editable_mode=compat
""",
     _DNS_LIMITS = """
  What DNS can't tell you (the real reputation signal):
    - Google Postmaster Tools: https://postmaster.google.com - add the domain;
      it shows Gmail's spam rate and domain reputation once you send volume.
    - Inbox placement: send one email to a seed test (mail-tester.com is free)
      and aim for 9/10+. TrulyInbox shows the warmup inbox rate, and with it
      connected (sellbird trulyinbox connect) Sellbird reads it into this report.
      Wait for ~95%+ inbox for a week before relying on cold sends.
""",
     _QUICK_START = """
  Quick start:
    sellbird install   — Install dependencies
    sellbird setup     — Configure Sellbird (first time)
    sellbird run       — Start closing deals
    sellbird dashboard — Open the web dashboard
""",
     _TRULYINBOX_KEY = """  You need Starter or higher. In TrulyInbox, open Settings > API keys and
  create a workspace key with accounts:read, warmup:read, analytics:read
  and workspace:read.
""",
     _HELP = {
         "train.provider": "Subscription to think with (default: the one in your config, else claude)",
         "train.reasoning_effort": "Codex reasoning effort (minimal/low/medium/high/xhigh)",
         "dashboard.host": "Loopback address to listen on (default: 127.0.0.1; other addresses are refused)",
         "status.check": "Also check the configured brain now (Codex: CLI version, isolation and login; Claude: CLI isolation flags; no model call)",
         "export.email_status": "Comma-separated statuses to include (default: verified,risky)",
         "export.status": "Comma-separated pipeline statuses (e.g. new,queued); opted-out contacts stay excluded",
         "export.all": "Export the raw list without filters, including opted-out contacts (not for outreach)",
         "companies": "Export the company register: every company, why it fits, and why it wasn't contacted",
         "companies.out": "Output file (default: data/exports/company-register-<date>.csv)",
         "discover.city": "Semicolon-separated cities, e.g. \"Denver, CO;Dallas, TX\" (default: icp.geography)",
         "discover.depth": "SERP depth (default: 30 — depth 100 costs 10x since Sept 2025)",
         "discover.preset": "A built-in search instead of your ICP's industries (each needs a search provider like tinyfish, serper or dataforseo_serp). yc: startups whose own site says they're YC-backed; hiring: companies whose own careers pages list one of your hiring_signals roles (else ICP titles); accelerator: ones backed by Techstars, Antler, EF, SPC, 500 Global, Neo, AI Grant, a16z speedrun or Plug and Play; funding: companies announcing a raise on their own site in the last 18 months",
         "retry-writes.no_tip": "Retry the prospects writer.require_tip skipped (status no_tip) instead",
         "warmup": "Check if your sending domain is set up and warmed up for cold email",
         "trulyinbox": "Warmup service: connect TrulyInbox so Sellbird can read the inbox rate",
         "trulyinbox.action": "connect a key, 'other' if you use another warmup service, or show the status (default)",
         "precleared-key": "Get a free Precleared key for the cold-email check and save it to .env",
         "mcp.action": "Add or remove the server in your coding agent's config",
     };

def _m(name: str) -> any;

async def _state -> any;

def _wrapped(text: str);

def _split(text: str, sep: str = ",") -> list[str];

def _check_python_version;

def cmd_install(args: any);

def _imports_outside -> bool;

def _ensure_importable(project_root: str);

def cmd_setup(args: any);

def cmd_run(args: any);

def cmd_train(args: any);

def cmd_mcp(args: any);

def cmd_dashboard(args: any);

async def _status(args: any) -> bool;

def cmd_status(args: any);

def _usage_rows(title: str, days: int, rows: list[any], key: str, width: int);

async def _usage(args: any);

def cmd_usage(args: any);

def cmd_companies(args: any);

async def _export(args: any);

def cmd_export(args: any);

async def _test_provider(provider: any);

def _mail_command(action: str, module: str, provider: str, client_id: str, secret: str);

def cmd_gmail(args: any);

def cmd_microsoft(args: any);

async def _outbox(args: any);

def cmd_outbox(args: any);

async def _profile(args: any);

def cmd_profile(args: any);

def _print_providers(menu: list[any]);

async def _discover(args: any);

def cmd_discover(args: any);

def _is_free(signal: any) -> bool;

async def _signals(args: any);

def cmd_signals(args: any);

async def _retry_writes(args: any);

def cmd_retry_writes(args: any);

def _load_config_or_exit -> any;

async def _send_history -> tuple[int, int];

def cmd_warmup(args: any);

async def _warmup_service(address: str, warmup: any) -> any;

def _warmup_service_check(address: str, warmup: any) -> any;

async def _trulyinbox_connect(state: any, address: str, warmup: any) -> int;

async def _trulyinbox(args: any, address: str, warmup: any) -> int;

def cmd_trulyinbox(args: any);

def cmd_precleared_key(args: any);

async def _sending(args: any);

def cmd_sending(args: any);

def _carry_over_from_harvey;

async def _suppressions(args: any) -> int;

def cmd_suppressions(args: any);

def _command(subparsers: any, name: str, about: str, func: any) -> any;

def _build_parser -> any;

def main;

with entry:__main__ {
    main();
}
