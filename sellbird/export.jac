import csv;
import io;
import logging;
import aiosqlite;

glob logger = logging.getLogger("sellbird.export"),
     CSV_COLUMNS = "email first_name last_name company_name title website linkedin_url industry personalization email_status score seniority source status created_at".split(),
     _SOURCE = {
         "company_name": "company",
         "website": "source_url",
         "personalization": "personalization_notes",
     },
     DEFAULT_EMAIL_STATUSES = ["verified", "risky"];

def _row(r: dict[any, any]) -> dict[str, any];

async def collect_prospects(
    state: StateManager,
    email_statuses: list[str] | None = None,
    min_score: int = 0,
    statuses: list[str] | None = None,
    include_all: bool = False,
    config: any = None,
) -> list[dict[str, any]];

def _do_not_contact(config: any) -> list[str];

def to_csv(rows: list[dict[str, any]]) -> str;

async def export_prospects_csv(
    state: StateManager, out_path: str | None = None, **filters: any
) -> tuple[int, str];
