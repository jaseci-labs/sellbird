import csv;
import io;
import aiosqlite;
import from functools { partial }

glob COLUMNS = "company website sector area fit why_selected status why_not_contacted contacts contact_form hiring found_via first_found".split(),
     LIVE = {"new", "queued"},
     DONE = {"contacted", "replied", "meeting", "closed"},
     _STOPPED = {"rejected", "failed", "cancelled"},
     _NOT = "Not contacted",
     _COMPANIES = "SELECT * FROM companies WHERE 1=1{} ORDER BY created_at",
     _QUERIES = [
         "SELECT company_id, first_name, last_name, title, email, email_status, status FROM prospects WHERE 1=1",
         "SELECT p.company_id, o.status, o.send_at FROM outbox o JOIN prospects p ON p.id = o.prospect_id WHERE 1=1",
         "SELECT company_id, signal_code, value_text, value_num, observed_at FROM observations WHERE signal_code IN ('DECISION_MAKER_TITLE', 'CONTACT_FORM_URL', 'HIRING_ROLE')",
     ],
     _WHY_UNSEARCHED = "Website read; Sellbird hasn't looked for contacts here yet.",
     _WHY_STOPPED = "Drafts were rejected or blocked before sending",
     _WHY_WRITE_FAILED = "Sellbird couldn't write a draft after several tries; see the log, and fix the cause to retry",
     _WHY_RISKY = "Only a risky (catch-all) email, which your rules don't send to. Try phone, LinkedIn or the cold-email domain later.",
     _WHY_NO_EMAIL = "but no valid email (address guessed or rejected by the verifier). Try phone, LinkedIn or a contact database.",
     _WHY_IRRELEVANT = "Contacts found were not relevant (e.g. not a factory, wrong person)",
     _WHY_READY = "Deliverable email found; Sellbird will write to it on a coming cycle";

def _contact(p: dict[any, any]) -> str;

def _has(prospects: list[any], wanted: set[str]) -> bool;

def company_status(
    company: any,
    prospects: any,
    outbox: any,
    observations: any,
    dnc: any,
    send_to_risky: bool = False,
) -> tuple[str, str];

def _by_company(rows: list[any]) -> dict[any, list[any]];

def _register_row(c: any, grouped: list[any], config: any, dnc: any, risky: bool) -> dict[str, any];

async def build_register(query_db: any, config: any, company_id: str | None = None) -> list[any];

def _do_not_contact(config: any) -> list[str];

async def _sqlite_rows(db_path: str, sql: str, params: any = ()) -> list[dict[any, any]];

def sqlite_query(db_path: any) -> any;

def _cell(value: any) -> any;

def _csv_row(row: dict[str, any]) -> dict[str, any];

def to_csv(rows: list[dict[str, any]]) -> str;
