import builtins;
import asyncio;
import getpass;
import importlib;
import logging;
import os;
import re;
import shutil;
import httpx;
import yaml;
import from pathlib { Path }
import from pydantic { ValidationError }

glob logger = logging.getLogger("sellbird.setup"),
     ENV_FILE = PROJECT_ROOT / ".env",
     CONFIG_FILE = PROJECT_ROOT / "sellbird.yaml",
     _RULE = "─" * 60,
     _BANNER = """
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║   Sellbird Setup Wizard                                    ║
║   Let's get you closing deals.                           ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝""",
     _DONE_BANNER = """
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║   Setup Complete!                                        ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
""",
     _NEXT_STEPS = """
  Files created:
    - .env (your credentials)
    - {} (your configuration)

  To start Sellbird:
    sellbird run          (or: python -m sellbird)

  To re-train on a different product:
    sellbird train https://newproduct.com

  To re-run this setup:
    sellbird setup

  News, new releases and the roadmap go out first on X:
    https://x.com/sellbirdagent

  Before you send a single email:
    1. Use a dedicated sending domain (not your main domain) with
       SPF, DKIM, and DMARC configured.
    2. Warm it up 2-4 weeks before real volume (Instantly has warmup).
    3. Make sure your Instantly campaigns include an unsubscribe
       option and your physical mailing address (CAN-SPAM).
    See docs/deliverability.md.
""",
     _PRECLEARED_DATA = """
  Anything that isn't a clear yes waits in the Outbox with the reason.
  It checks mail sent through Gmail, Microsoft 365 or SMTP, not Instantly.
  Precleared receives each new recipient's address, your country, how
  the address was found, your product description and the recipient's
  country when the company's location makes it certain, else your
  prospects' country if you set one. It also gets the company's and
  person's names, to find a UK company on the register; it doesn't
  store the person's name.""",
     _LINKEDIN_RISK = """
  ⚠  Heads up: automating LinkedIn violates their Terms of Service.
     Accounts doing this can be restricted or banned. Only use an
     account you're comfortable putting at risk, and keep the
     default rate limits. This is entirely optional.""",
     _GEOGRAPHY = "Target geography (for a city, include the state/country, e.g. 'Solon, Ohio' — an unqualified city name can silently geocode to the wrong place)",
     _MAIN_OFFER = "What's your main offer? (e.g., 'SaaS subscription at $99/mo', 'Marketing retainer')",
     _ENTRY_OFFER = "Any low-commitment entry offer? (e.g., 'Free trial', 'Free audit', 'Sample report')",
     _GOALS = {"1": "book_call", "2": "start_trial", "3": "get_reply"},
     _PACKAGES = ["httpx", "aiosqlite", "yaml", "pydantic", "bs4"],
     _MODEL_RETRY = "    (that doesn't look like a model name — try again or leave blank)",
     _CF_TOKEN = "Cloudflare API Token (needs Browser Rendering - Edit permission; input hidden)";

def _print_sellbird(message: str);

def _say(block: str);

def _print_step(step: int, total: int, title: str);

def _cancelled;

def _ask(prompt: str, `default: str = "", required: bool = True, secret: bool = False) -> str;

def _ask_yes_no(prompt: str, `default: bool = True) -> bool;

def _read_env_file -> dict[str, str];

def _config_file -> Path;

def _saved(*path: str) -> any;

def _current_precleared -> dict[any, any];

def _sender_country(value: any, strict: bool = True) -> str;

def _saved_timezone -> str;

def _save_precleared(config: any, answers: any);

def _merge_answers(existing: any, answers: any);

def _product_configured -> bool;

def _check_claude_cli -> bool;

def _check_codex_cli -> bool;

async def _test_claude(brain: any) -> bool;

def _ask_brain_config -> BrainConfig;

async def _test_instantly(api_key: str) -> bool;

def _split(answer: str) -> list[str];

def _ask_number(prompt: str, fallback: str, parse: any) -> any;

def _percent(value: str) -> float;

def _at_least_one(value: str) -> int;

class SetupWizard {
    has env_vars: dict[str, str] = {},
        config: any = None,
        brain_config: any = None,
        precleared: any = None,
        config_saved: bool = False,
        manual_product: bool = False;

    def init;

    async def run;

    async def _check_prerequisites;

    async def _test_brain(testing: str, failed: str, note: str = "");

    async def _check_claude;

    async def _check_codex;

    def _check_python_packages;

    async def _setup_email_platform;

    def _setup_linkedin;

    def _setup_cloudflare;

    async def _setup_product;

    def _ask_product;

    def _setup_behavior;

    def _timezone -> str;

    def _leave_off(was_on: bool);

    def _setup_compliance;

    def _ask_precleared_key;

    def _get_free_precleared_key -> str;

    def _write_env;

    def _write_config;

    async def _print_summary;
}

async def run_setup;

def main;

with entry:__main__ {
    utf8_stdio();
    main();
}
