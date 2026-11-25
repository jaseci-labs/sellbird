import builtins;
import json;
import operator;
import uuid;
import aiosqlite;
import from datetime { date, datetime, timedelta, timezone }
import from pathlib { Path }

glob DB_PATH: any = PROJECT_ROOT / "data" / "sellbird.db",
     WRITABLE_EMAIL_STATUSES: any = ("verified", "risky"),
     MANUAL_SEND_KEY: any = "manual_send:",
     HAND_SENT_REASON: any = "sent_by_hand",
     REVIEW_NEXT_REPLY_KEY: any = "review_next_reply:",
     HELD_FOR_REVIEW: any = "held for your review: ",
     SENDS_HELD_KEY: any = "sends_held",
     COLLEAGUE_REPLIED: any = "a colleague replied",
     COMPANY_STOP_KEY: any = "company_stop:",
     FREE_MAIL_DOMAINS: any = frozenset(
         """gmail.com googlemail.com yahoo.com ymail.com hotmail.com outlook.com live.com msn.com
         aol.com icloud.com me.com mac.com proton.me protonmail.com gmx.com gmx.de web.de mail.com
         zoho.com yandex.com yandex.ru qq.com 163.com comcast.net att.net verizon.net sbcglobal.net
         bellsouth.net cox.net charter.net hey.com fastmail.com pm.me rr.com earthlink.net
         frontier.com frontiernet.net windstream.net centurylink.net optonline.net roadrunner.com
         juno.com netzero.net mindspring.com embarqmail.com suddenlink.net yahoo.co.uk yahoo.ca
         yahoo.com.au hotmail.co.uk hotmail.ca live.co.uk live.ca btinternet.com sky.com
         virginmedia.com talktalk.net ntlworld.com shaw.ca rogers.com sympatico.ca telus.net
         bigpond.com optusnet.com.au orange.fr free.fr wanadoo.fr laposte.net t-online.de libero.it
         mail.ru naver.com seznam.cz wp.pl o2.pl tutanota.com tuta.io""".split()
     ),
     AUTOPILOT_OFF_REASON: any = "waiting for you: autopilot was turned off before it went out",
     RECHECK_PREFIX: any = "Precleared couldn't check this address; trying again after ",
     UNKNOWN_HOLD_PREFIX: any = "Precleared couldn't settle this address; trying again after ",
     MOVED_BACK_PREFIXES: any = (RECHECK_PREFIX, UNKNOWN_HOLD_PREFIX),
     MAYBE_SENT_PREFIX: any = "may have gone out: ",
     STALE_SENDING_ERROR: any = MAYBE_SENT_PREFIX
         + "Sellbird stopped in the middle of sending it; check your Sent folder before emailing them again",
     STALE_SENDING_AFTER: any = timedelta(minutes=15);

glob MIGRATIONS: list[str] = ["""
    CREATE TABLE IF NOT EXISTS companies (
        id TEXT PRIMARY KEY, name TEXT DEFAULT '', domain TEXT DEFAULT '', website TEXT DEFAULT '',
        description TEXT DEFAULT '', industry TEXT DEFAULT '', company_size TEXT DEFAULT '',
        location TEXT DEFAULT '', source TEXT DEFAULT '', source_url TEXT DEFAULT '',
        notes TEXT DEFAULT '', created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    CREATE TABLE IF NOT EXISTS prospects (
        id TEXT PRIMARY KEY, company_id TEXT DEFAULT '' REFERENCES companies(id),
        first_name TEXT DEFAULT '', last_name TEXT DEFAULT '', email TEXT DEFAULT '',
        email_verified INTEGER DEFAULT 0, phone TEXT DEFAULT '', phone_verified INTEGER DEFAULT 0,
        linkedin_url TEXT DEFAULT '', title TEXT DEFAULT '', seniority TEXT DEFAULT '',
        department TEXT DEFAULT '', source TEXT DEFAULT '', source_url TEXT DEFAULT '',
        status TEXT DEFAULT 'new', score INTEGER DEFAULT 0, personalization_notes TEXT DEFAULT '',
        company TEXT DEFAULT '', industry TEXT DEFAULT '', company_size TEXT DEFAULT '',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    CREATE TABLE IF NOT EXISTS campaigns (
        id TEXT PRIMARY KEY, name TEXT DEFAULT '', channel TEXT DEFAULT 'email',
        instantly_campaign_id TEXT DEFAULT '', sequence_json TEXT DEFAULT '[]',
        prospect_ids_json TEXT DEFAULT '[]', status TEXT DEFAULT 'draft',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    CREATE TABLE IF NOT EXISTS conversations (
        id TEXT PRIMARY KEY, prospect_id TEXT REFERENCES prospects(id), campaign_id TEXT DEFAULT '',
        channel TEXT DEFAULT 'email', thread_json TEXT DEFAULT '[]', intent TEXT DEFAULT '',
        stage TEXT DEFAULT 'initial_outreach', status TEXT DEFAULT 'open',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    CREATE TABLE IF NOT EXISTS feedback (
        id TEXT PRIMARY KEY, entity_type TEXT DEFAULT '', entity_id TEXT DEFAULT '',
        comment TEXT DEFAULT '', created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    CREATE TABLE IF NOT EXISTS actions (
        id TEXT PRIMARY KEY, action_type TEXT, agent TEXT, details_json TEXT DEFAULT '{}',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    CREATE TABLE IF NOT EXISTS usage_log (
        id TEXT PRIMARY KEY, date TEXT UNIQUE, claude_calls INTEGER DEFAULT 0,
        usage_percent REAL DEFAULT 0.0, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    CREATE TABLE IF NOT EXISTS processed_replies (
        reply_id TEXT PRIMARY KEY, processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    CREATE INDEX IF NOT EXISTS idx_companies_domain ON companies(domain);
    CREATE INDEX IF NOT EXISTS idx_prospects_company_id ON prospects(company_id);
    CREATE INDEX IF NOT EXISTS idx_prospects_status ON prospects(status);
    CREATE INDEX IF NOT EXISTS idx_prospects_email ON prospects(email);
    CREATE INDEX IF NOT EXISTS idx_campaigns_status ON campaigns(status);
    CREATE INDEX IF NOT EXISTS idx_conversations_status ON conversations(status);
    CREATE INDEX IF NOT EXISTS idx_feedback_entity ON feedback(entity_type, entity_id);
    CREATE INDEX IF NOT EXISTS idx_usage_date ON usage_log(date);
    """, """
    UPDATE prospects SET email = LOWER(TRIM(email)) WHERE email != LOWER(TRIM(email));
    UPDATE companies SET domain = LOWER(TRIM(domain)) WHERE domain != LOWER(TRIM(domain));
    DELETE FROM prospects WHERE email != '' AND rowid NOT IN (
        SELECT MIN(rowid) FROM prospects WHERE email != '' GROUP BY email
    );
    DELETE FROM prospects WHERE linkedin_url != '' AND rowid NOT IN (
        SELECT MIN(rowid) FROM prospects WHERE linkedin_url != '' GROUP BY linkedin_url
    );
    DELETE FROM companies WHERE domain != '' AND rowid NOT IN (
        SELECT MIN(rowid) FROM companies WHERE domain != '' GROUP BY domain
    );
    CREATE UNIQUE INDEX IF NOT EXISTS uq_prospects_email ON prospects(email) WHERE email != '';
    CREATE UNIQUE INDEX IF NOT EXISTS uq_prospects_linkedin
        ON prospects(linkedin_url) WHERE linkedin_url != '';
    CREATE UNIQUE INDEX IF NOT EXISTS uq_companies_domain ON companies(domain) WHERE domain != '';
    CREATE INDEX IF NOT EXISTS idx_conversations_campaign_id ON conversations(campaign_id);
    CREATE INDEX IF NOT EXISTS idx_conversations_prospect_id ON conversations(prospect_id);
    CREATE INDEX IF NOT EXISTS idx_conversations_intent ON conversations(intent);
    CREATE INDEX IF NOT EXISTS idx_prospects_name_company
        ON prospects(LOWER(first_name), LOWER(last_name), LOWER(company));
    CREATE INDEX IF NOT EXISTS idx_prospects_status_updated ON prospects(status, updated_at);
    CREATE INDEX IF NOT EXISTS idx_actions_created_at ON actions(created_at);
    """, """
    CREATE TABLE IF NOT EXISTS usage_events (
        id TEXT PRIMARY KEY, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, agent TEXT DEFAULT '',
        task TEXT DEFAULT '', session_id TEXT DEFAULT '', request_key TEXT DEFAULT '',
        model TEXT DEFAULT '', input_tokens INTEGER DEFAULT 0, output_tokens INTEGER DEFAULT 0,
        cache_read_tokens INTEGER DEFAULT 0, cache_creation_tokens INTEGER DEFAULT 0,
        cost_usd REAL DEFAULT 0.0, duration_ms INTEGER DEFAULT 0, num_turns INTEGER DEFAULT 0,
        is_error INTEGER DEFAULT 0, source TEXT DEFAULT 'result_json'
    );
    CREATE INDEX IF NOT EXISTS idx_usage_events_created ON usage_events(created_at);
    CREATE INDEX IF NOT EXISTS idx_usage_events_agent ON usage_events(agent);
    CREATE INDEX IF NOT EXISTS idx_usage_events_session ON usage_events(session_id);
    CREATE UNIQUE INDEX IF NOT EXISTS uq_usage_events_request
        ON usage_events(request_key) WHERE request_key != '';
    """, """
    ALTER TABLE prospects ADD COLUMN email_status TEXT DEFAULT '';
    UPDATE prospects SET email_status = 'guess', email_verified = 0 WHERE email != '';
    CREATE TABLE IF NOT EXISTS email_patterns (
        domain TEXT PRIMARY KEY, pattern TEXT DEFAULT '', source TEXT DEFAULT '',
        confidence REAL DEFAULT 0.0, mx_type TEXT DEFAULT '', is_catch_all INTEGER DEFAULT -1,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    """, """
    ALTER TABLE companies ADD COLUMN tech_stack_json TEXT DEFAULT '[]';
    ALTER TABLE companies ADD COLUMN signals_json TEXT DEFAULT '[]';
    """, """
    CREATE TABLE IF NOT EXISTS outbox (
        id TEXT PRIMARY KEY, campaign_id TEXT DEFAULT '', prospect_id TEXT DEFAULT '',
        conversation_id TEXT DEFAULT '', step INTEGER DEFAULT 1, kind TEXT DEFAULT 'sequence',
        to_email TEXT DEFAULT '', subject TEXT DEFAULT '', body TEXT DEFAULT '',
        status TEXT DEFAULT 'pending_review', send_at TIMESTAMP, sent_at TIMESTAMP,
        provider TEXT DEFAULT '', message_id TEXT DEFAULT '', thread_ref TEXT DEFAULT '',
        in_reply_to TEXT DEFAULT '', error TEXT DEFAULT '',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    CREATE UNIQUE INDEX IF NOT EXISTS uq_outbox_campaign_step
        ON outbox(campaign_id, prospect_id, step) WHERE campaign_id != '' AND kind = 'sequence';
    CREATE INDEX IF NOT EXISTS idx_outbox_status_send_at ON outbox(status, send_at);
    CREATE INDEX IF NOT EXISTS idx_outbox_prospect ON outbox(prospect_id);
    CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY, value TEXT DEFAULT '', updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    """, """
    CREATE TABLE IF NOT EXISTS signal_codes (
        code TEXT PRIMARY KEY, label TEXT DEFAULT '', description TEXT DEFAULT '',
        category TEXT DEFAULT '', value_type TEXT DEFAULT 'text', collector TEXT DEFAULT '',
        cost_note TEXT DEFAULT '', status TEXT DEFAULT 'proposed', confidence_floor REAL DEFAULT 0.0,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    CREATE TABLE IF NOT EXISTS observations (
        id TEXT PRIMARY KEY, company_id TEXT DEFAULT '', prospect_id TEXT DEFAULT '',
        signal_code TEXT NOT NULL, collector TEXT DEFAULT '', value_num REAL,
        value_text TEXT DEFAULT '', confidence REAL DEFAULT 1.0, evidence_url TEXT DEFAULT '',
        observed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, run_id TEXT DEFAULT ''
    );
    CREATE INDEX IF NOT EXISTS idx_obs_company ON observations(company_id);
    CREATE INDEX IF NOT EXISTS idx_obs_signal ON observations(signal_code);
    CREATE INDEX IF NOT EXISTS idx_obs_company_signal
        ON observations(company_id, signal_code, observed_at);
    CREATE INDEX IF NOT EXISTS idx_obs_run ON observations(run_id);
    CREATE TRIGGER IF NOT EXISTS trg_observations_signal_known
    BEFORE INSERT ON observations
    FOR EACH ROW
    WHEN NEW.signal_code NOT IN (SELECT code FROM signal_codes)
    BEGIN
        SELECT RAISE(ABORT, 'unknown signal_code: not in signal_codes vocabulary');
    END;
    CREATE TABLE IF NOT EXISTS runs (
        id TEXT PRIMARY KEY, stage TEXT DEFAULT '', status TEXT DEFAULT 'running',
        provider TEXT DEFAULT '', records INTEGER DEFAULT 0, cost_usd REAL DEFAULT 0.0,
        params_json TEXT DEFAULT '{}', error TEXT DEFAULT '',
        started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, ended_at TIMESTAMP
    );
    CREATE INDEX IF NOT EXISTS idx_runs_stage_started ON runs(stage, started_at);
    """, """
    ALTER TABLE companies ADD COLUMN external_id TEXT DEFAULT '';
    ALTER TABLE companies ADD COLUMN phone TEXT DEFAULT '';
    CREATE UNIQUE INDEX IF NOT EXISTS uq_companies_external
        ON companies(external_id) WHERE external_id != '';
    """, """
    ALTER TABLE companies ADD COLUMN prospects_checked_at TIMESTAMP DEFAULT NULL;
    """, """
    ALTER TABLE companies ADD COLUMN profile_checked_at TIMESTAMP DEFAULT NULL;
    UPDATE companies SET profile_checked_at = (
        SELECT MAX(observed_at) FROM observations
        WHERE observations.company_id = companies.id AND observations.collector = 'profile'
    ) WHERE id IN (SELECT DISTINCT company_id FROM observations WHERE collector = 'profile');
    """, """
    ALTER TABLE usage_events ADD COLUMN provider TEXT DEFAULT 'claude';
    CREATE INDEX IF NOT EXISTS idx_usage_events_provider ON usage_events(provider);
    ALTER TABLE usage_log ADD COLUMN codex_calls INTEGER DEFAULT 0;
    """, """
    CREATE INDEX IF NOT EXISTS idx_actions_type_created ON actions(action_type, created_at);
    """, """
    ALTER TABLE outbox ADD COLUMN approved_by TEXT DEFAULT '';
    UPDATE outbox SET approved_by = 'earlier' WHERE status IN ('approved', 'sending');
    """, """
    ALTER TABLE prospects ADD COLUMN timezone TEXT DEFAULT '';
    """, """
    CREATE TABLE IF NOT EXISTS suppressions (id TEXT PRIMARY KEY, kind TEXT NOT NULL,
      value TEXT NOT NULL, reason TEXT DEFAULT 'manual', source TEXT DEFAULT '',
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);
    CREATE UNIQUE INDEX IF NOT EXISTS uq_suppressions_kind_value ON suppressions(kind, value);
    """, """
    CREATE TABLE IF NOT EXISTS mailboxes (id TEXT PRIMARY KEY, address TEXT NOT NULL UNIQUE,
      display_name TEXT DEFAULT '', provider TEXT NOT NULL, connection TEXT NOT NULL,
      state TEXT DEFAULT 'active', paused_reason TEXT DEFAULT '', cap_override INTEGER,
      credential_ref TEXT DEFAULT '', settings_json TEXT DEFAULT '{}',
      warmup_started_at TIMESTAMP, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);
    CREATE TABLE IF NOT EXISTS campaign_mailboxes (campaign_id TEXT NOT NULL,
      mailbox_id TEXT NOT NULL, PRIMARY KEY (campaign_id, mailbox_id));
    ALTER TABLE outbox ADD COLUMN mailbox_id TEXT DEFAULT '';
    ALTER TABLE conversations ADD COLUMN mailbox_id TEXT DEFAULT '';
    CREATE INDEX IF NOT EXISTS idx_outbox_mailbox_sent ON outbox(mailbox_id, status, sent_at);
    """];

glob BRAIN_PROVIDERS: any = ("claude", "codex"),
     _USAGE_LOG_COLUMN: dict[str, str] = {"claude": "claude_calls", "codex": "codex_calls"},
     _LAST_PROFILED_JOIN: any = """LEFT JOIN (
                       SELECT company_id, MAX(observed_at) AS last_seen
                       FROM observations WHERE collector = 'profile'
                       GROUP BY company_id
                   ) p ON p.company_id = c.id""",
     _LAST_PROFILED: any = "(CASE WHEN p.last_seen IS NULL OR c.profile_checked_at > p.last_seen THEN c.profile_checked_at ELSE p.last_seen END)",
     _PROFILE_DUE: any = f"FROM companies c {_LAST_PROFILED_JOIN} WHERE c.domain != '' AND ({_LAST_PROFILED} IS NULL OR {_LAST_PROFILED} < datetime('now', ?))",
     _CAMPAIGN_COLUMNS: any = frozenset(
         "name channel instantly_campaign_id sequence_json prospect_ids_json status".split()
     ),
     _CONVERSATION_COLUMNS: any = frozenset(
         "prospect_id campaign_id channel thread_json intent stage status mailbox_id".split()
     ),
     _UPSERT_SETTING: any = "INSERT INTO settings (key, value, updated_at) VALUES (?, ?, CURRENT_TIMESTAMP) ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = CURRENT_TIMESTAMP",
     _LOG_ACTION: any = "INSERT INTO actions (id, action_type, agent, details_json) VALUES (?, ?, ?, ?)",
     _INSERT_OBSERVATION: any = "INSERT INTO observations (id, company_id, prospect_id, signal_code, collector, value_num, value_text, confidence, evidence_url, observed_at, run_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, COALESCE(?, CURRENT_TIMESTAMP), ?)",
     _PREV_STEP_UNSENT: any = "EXISTS (SELECT 1 FROM outbox p WHERE p.prospect_id = o.prospect_id AND p.campaign_id = o.campaign_id AND p.kind = 'sequence' AND p.step = o.step - 1 AND p.status IN ('pending_review', 'approved', 'sending'))",
     _RANK_CODES: any = "('SERP_RANK', 'IN_LOCAL_PACK', 'MAPS_RANK')";

def _email_domain(alias: str) -> str;

def _colleagues(p: str, c: str) -> str;

def _company_answered(p: str) -> str;

def _new_id -> str;

def _utcnow -> datetime;

def _norm(value: str | None) -> str;

def _marks(n: int) -> str;

def _insert(table: str, columns: str, verb: str = "INSERT OR IGNORE") -> str;

def _filters(pairs: list[tuple[str, any]]) -> tuple[str, list[any]];

def _json_list(raw: any) -> list[any];

def _checked(kind: str, fields: builtins.dict, allowed: any) -> builtins.dict;

def _parse_time(value: any, fallback: datetime) -> datetime;

def _parent_domains(domain: str) -> list[str];

async def _fetch(db: any, sql: str, params: any = (), one: bool = False) -> any;

def _row_values(model: any, columns: list[str]) -> list[any];

glob SUPPRESSION_KINDS: any = ("address", "domain"),
     SUPPRESSION_REASONS: any = tuple("opted_out bounced complaint manual imported".split()),
     FOOTER_HISTORY_KEY: str = "compliance_footer_history",
     _OUTBOX_COLUMNS: any = frozenset(
         "status error message_id thread_ref sent_at subject body send_at provider mailbox_id".split(),
     ),
     _CURRENT_CTE: str = f"""
    WITH latest AS (
        SELECT o.* FROM observations o
        JOIN (SELECT company_id, signal_code, MAX(observed_at) AS t
              FROM observations GROUP BY company_id, signal_code) newest
          ON newest.company_id = o.company_id
         AND newest.signal_code = o.signal_code
         AND newest.t = o.observed_at
        WHERE o.signal_code NOT IN {_RANK_CODES}
    ),
    ranked AS (
        SELECT o.* FROM observations o
        WHERE o.signal_code IN {_RANK_CODES}
          AND o.rowid = (
              SELECT n.rowid FROM observations n
              WHERE n.company_id = o.company_id
                AND n.signal_code = o.signal_code
                AND COALESCE(n.value_text, '') = COALESCE(o.value_text, '')
              ORDER BY n.observed_at DESC, n.rowid DESC LIMIT 1)
          AND NOT (COALESCE(o.value_text, '') = '' AND EXISTS (
              SELECT 1 FROM observations p
              WHERE p.company_id = o.company_id
                AND p.signal_code = o.signal_code
                AND COALESCE(p.value_text, '') != ''))
    ),
    positive AS (
        SELECT * FROM latest WHERE value_num IS NULL OR value_num != 0
        UNION ALL
        SELECT * FROM ranked WHERE value_num IS NOT NULL AND value_num != 0
    )
    """,
     _USAGE_SUM: str = "COUNT(DISTINCT CASE WHEN session_id != '' THEN session_id ELSE id END) AS calls, SUM(input_tokens) AS input_tokens, SUM(output_tokens) AS output_tokens, SUM(cache_read_tokens) AS cache_read_tokens, SUM(cache_creation_tokens) AS cache_creation_tokens, SUM(cost_usd) AS cost_usd";

def _company_from_row(row: any) -> Company;

def _prospect_from_row(row: any) -> Prospect;

def _conversation_from_row(row: any) -> Conversation;

def _usage_row_to_dict(row: any) -> builtins.dict;

def _suppression_key(kind: str, value: str) -> str;

class StateManager {
    has db_path: str = "";

    def init(db_path: str | None = None);

    def _connect -> any;

    async def _select(sql: str, params: any = (), one: bool = False) -> any;

    async def _dicts(sql: str, params: any = ()) -> list[builtins.dict];

    async def _dict(sql: str, params: any = ()) -> builtins.dict | None;

    async def _value(sql: str, params: any = (), fallback: any = None) -> any;

    async def _counts(sql: str) -> dict[str, int];

    async def _insert_row(
        model: any, table: str, columns: str, keys: str = "", verb: str = "INSERT OR IGNORE"
    ) -> str;

    async def _changed(sql: str, params: any = ()) -> bool;

    async def _exec(sql: str, params: any = ()) -> int;

    async def _update(table: str, row_id: str, fields: builtins.dict, stamp: bool);

    async def init_db;

    async def _company_by(column: str, value: str) -> Company | None;

    async def add_company(company: Company) -> str;

    async def update_company_signals(
        company_id: str,
        tech_stack: list[str] | None = None,
        new_signals: list[builtins.dict] | None = None,
    );

    async def get_company(company_id: str) -> Company | None;

    async def get_company_by_domain(domain: str) -> Company | None;

    async def get_company_by_external_id(external_id: str) -> Company | None;

    async def get_contacts_for_company(company_id: str) -> list[Prospect];

    async def company_exists(domain: str) -> bool;

    async def _prospect_by(column: str, value: str) -> Prospect | None;

    async def add_prospect(prospect: Prospect) -> str;

    async def get_prospect(prospect_id: str) -> Prospect | None;

    async def get_prospects_by_status(status: str) -> list[Prospect];

    async def set_prospect_timezone(prospect_id: str, zone: str);

    async def update_prospect_status(prospect_id: str, status: str);

    async def undo_opt_out(prospect_id: str, details: builtins.dict | None = None) -> bool;

    async def opt_out_history(prospect_id: str) -> list[builtins.dict];

    async def queue_prospect_if_unsent(prospect_id: str) -> bool;

    async def get_prospect_by_email(email: str) -> Prospect | None;

    async def update_prospect_email(prospect_id: str, email: str, email_status: str);

    async def get_email_pattern(domain: str) -> builtins.dict | None;

    async def save_email_pattern(
        domain: str,
        pattern: str = "",
        source: str = "",
        confidence: float = 0.0,
        mx_type: str = "",
        is_catch_all: int | None = None,
    );

    async def add_outbox_item(
        *,
        prospect_id: str,
        to_email: str,
        subject: str,
        body: str,
        send_at: str,
        status: str = "pending_review",
        campaign_id: str = "",
        conversation_id: str = "",
        step: int = 1,
        kind: str = "sequence",
        provider: str = "",
        thread_ref: str = "",
        in_reply_to: str = "",
        approved_by: str = "",
        mailbox_id: str = "",
    ) -> str | None;

    async def get_outbox(
        status: str | None = None,
        due_before: str | None = None,
        limit: int = 200,
        exclude_kind: str | None = None,
        skip_unready_follow_ups: bool = False,
        kind: str | None = None,
        follow_ups_only: bool = False,
    ) -> list[builtins.dict];

    async def get_texts_for_prospect(prospect_id: str, limit: int = 50) -> list[str];

    async def count_due_cold_outbox(
        due_before: str,
        stored_verdicts: tuple[str, str, str] | None = None,
        moved_back_prefix: str = "",
        has_cached_verdict: any = None,
    ) -> int;

    async def get_outbox_item(item_id: str) -> builtins.dict | None;

    async def update_outbox_item(item_id: str, **kwargs: any);

    async def claim_outbox_item(item_id: str) -> bool;

    async def fail_stale_sending_outbox(older_than: timedelta = STALE_SENDING_AFTER) -> int;

    async def edit_outbox_draft(item_id: str, subject: str, body: str) -> int;

    async def restore_hand_cancelled_outbox(prospect_id: str, reason: str) -> int;

    async def reject_outbox_item(item_id: str) -> int;

    async def approve_outbox(item_id: str | None = None) -> int;

    async def note_sends_held(reason: str);

    async def clear_sends_held;

    async def current_sends_held(max_age_hours: float = 12) -> builtins.dict | None;

    async def requeue_autopilot_approved -> int;

    async def count_held_for_review -> int;

    async def cancel_pending_outbox_for_prospect(
        prospect_id: str, reason: str = "stop_on_reply"
    ) -> int;

    async def stop_company(prospect_id: str) -> int;

    static def suppression_key(kind: str, value: str) -> str;

    async def add_suppression(
        kind: str, value: str, reason: str = "manual", source: str = ""
    ) -> bool;

    async def suppressed_among(emails: any) -> dict[str, str];

    async def is_suppressed(email: str) -> str | None;

    async def list_suppressions(limit: int = 200, offset: int = 0) -> list[builtins.dict];

    async def remove_suppression(suppression_id: str) -> bool;

    async def colleague_who_replied(prospect_id: str) -> str | None;

    async def count_outbox_sent -> int;

    async def count_outbox_sent_today(
        kind: str | None = None, since: str | None = None, mailbox_id: str | None = None
    ) -> int;

    async def get_step_delay_days(campaign_id: str, step: int) -> int | None;

    async def get_previous_step(item: builtins.dict) -> builtins.dict | None;

    async def find_outbox_by_message_id(message_id: str) -> builtins.dict | None;

    async def upsert_signal_code(
        code: str,
        *,
        label: str = "",
        description: str = "",
        category: str = "",
        value_type: str = "text",
        collector: str = "",
        cost_note: str = "",
        confidence_floor: float = 0.0,
        status: str | None = None,
    );

    async def get_signal_codes(status: str | None = None) -> list[builtins.dict];

    async def set_signal_status(code: str, status: str) -> bool;

    async def confirmed_signal_codes -> set[str];

    async def add_observation(
        signal_code: str,
        *,
        company_id: str = "",
        prospect_id: str = "",
        collector: str = "",
        value_num: float | None = None,
        value_text: str = "",
        confidence: float = 1.0,
        evidence_url: str = "",
        run_id: str = "",
        observed_at: str | None = None,
    ) -> str;

    async def add_observations(rows: list[builtins.dict], run_id: str = "") -> int;

    async def _latest(company_id: str, signal_code: str) -> builtins.dict | None;

    async def _latest_yes(company_id: str, signal_code: str) -> builtins.dict | None;

    async def yc_batch(company_id: str) -> str | None;

    async def search_hit(company_id: str, signal_code: str) -> bool;

    async def accelerator(company_id: str) -> str | None;

    async def funding_round(company_id: str) -> builtins.dict | None;

    async def get_observations(
        company_id: str = "", signal_code: str = "", latest_only: bool = False, limit: int = 500
    ) -> list[builtins.dict];

    async def signal_counts -> list[builtins.dict];

    async def cohort(
        require: list[str],
        exclude: list[str] | None = None,
        min_confidence: float = 0.0,
        limit: int = 500,
    ) -> list[str];

    async def ranked_company_ids(code: str, phrase: str) -> set[str];

    async def cohort_companies(
        require: list[str],
        exclude: list[str],
        offset: int = 0,
        limit: int | None = None,
        ranges: list[builtins.dict] | None = None,
    ) -> tuple[int, list[builtins.dict]];

    async def companies_needing_profile(
        limit: int = 100, stale_days: int = 90
    ) -> list[builtins.dict];

    async def count_companies_needing_profile(stale_days: int = 90) -> int;

    async def mark_company_profiled(company_id: str);

    async def rename_company(company_id: str, name: str);

    async def companies_needing_prospects(
        limit: int = 10, stale_days: int = 14
    ) -> list[builtins.dict];

    async def mark_prospects_checked(company_id: str);

    async def start_run(stage: str, provider: str = "", params: builtins.dict | None = None) -> str;

    async def finish_run(
        run_id: str,
        status: str = "completed",
        records: int = 0,
        cost_usd: float = 0.0,
        error: str = "",
    );

    async def sweep_stale_runs(older_than_hours: int = 6) -> int;

    async def get_runs(limit: int = 25) -> list[builtins.dict];

    async def remember_footer_lines(lines: any);

    async def get_footer_history -> list[str];

    async def get_setting(key: str, `default: str = "") -> str;

    async def retry_write_failed -> int;

    async def retry_no_tip -> int;

    async def delete_setting(key: str);

    async def set_setting(key: str, value: str);

    async def increment_setting(key: str, `by: int = 1) -> int;

    async def prospect_exists(
        email: str = "",
        linkedin_url: str = "",
        first_name: str = "",
        last_name: str = "",
        company: str = "",
    ) -> bool;

    async def count_writable_prospects -> int;

    async def count_recent_unusable_prospects(hours: int = 24) -> int;

    async def count_prospects_by_status -> dict[str, int];

    async def add_feedback(entity_type: str, entity_id: str, comment: str) -> str;

    async def get_feedback(entity_type: str, entity_id: str) -> list[builtins.dict];

    async def get_all_feedback -> list[builtins.dict];

    async def get_writing_feedback(prospect_ids: any = (), limit: int = 10) -> list[builtins.dict];

    async def is_reply_processed(reply_id: str) -> bool;

    async def mark_reply_processed(reply_id: str);

    async def add_campaign(campaign: Campaign) -> str;

    async def get_campaigns_by_status(status: str) -> list[Campaign];

    async def update_campaign(campaign_id: str, **kwargs: any);

    async def add_conversation(convo: Conversation) -> str;

    async def get_conversation(convo_id: str) -> Conversation | None;

    async def get_conversations_by_status(status: str) -> list[Conversation];

    async def update_conversation(convo_id: str, **kwargs: any);

    async def log_action(action_type: str, agent: str, details: builtins.dict | None = None);

    async def get_campaign_stats -> list[builtins.dict];

    async def get_intent_distribution -> dict[str, int];

    async def get_stage_distribution -> dict[str, int];

    async def get_usage_today(provider: str = "claude") -> int;

    async def increment_usage(provider: str = "claude");

    async def record_usage_event(
        *,
        agent: str = "",
        task: str = "",
        session_id: str = "",
        request_key: str = "",
        model: str = "",
        input_tokens: int = 0,
        output_tokens: int = 0,
        cache_read_tokens: int = 0,
        cache_creation_tokens: int = 0,
        cost_usd: float = 0.0,
        duration_ms: int = 0,
        num_turns: int = 0,
        is_error: bool = False,
        source: str = "result_json",
        created_at: str | None = None,
        provider: str = "claude",
    ) -> bool;

    async def _usage_grouped(group_expr: str, alias: str, days: int) -> list[builtins.dict];

    async def usage_by_agent(days: int = 30) -> list[builtins.dict];

    async def usage_by_task(days: int = 30) -> list[builtins.dict];

    async def usage_by_model(days: int = 30) -> list[builtins.dict];

    async def usage_by_provider(days: int = 30) -> list[builtins.dict];

    async def usage_totals -> builtins.dict;

    async def get_state_summary -> builtins.dict;
}
