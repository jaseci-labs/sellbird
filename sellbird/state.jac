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

def _email_domain(alias: str) -> str {
    return f"lower(substr({alias}.email, instr({alias}.email, '@') + 1))";
}

def _colleagues(p: str, c: str) -> str {
    domain = _email_domain(p);
    free = ", ".join([f"'{d}'" for d in sorted(FREE_MAIL_DOMAINS)]);
    owner = "(SELECT lower(co.domain) FROM companies co WHERE co.id = {x}.company_id)";
    return f"{c}.id != {p}.id AND (({p}.company_id != '' AND {c}.company_id = {p}.company_id) OR (({p}.company_id = '' OR {c}.company_id = '') AND instr({p}.email, '@') > 0 AND {domain} != '' AND {domain} NOT IN ({free}) AND {_email_domain(c)} = {domain} AND ({p}.company_id = '' OR {domain} = {owner.format(x=p)}) AND ({c}.company_id = '' OR {domain} = {owner.format(x=c)})))";
}

def _company_answered(p: str) -> str {
    return f"EXISTS (SELECT 1 FROM prospects c, settings s WHERE s.key = '{COMPANY_STOP_KEY}' || c.id AND {_colleagues(p, 'c')})";
}

def _new_id -> str {
    return uuid.uuid4().hex[:12];
}

def _utcnow -> datetime {
    return datetime.now(timezone.utc).replace(tzinfo=None);
}

def _norm(value: str | None) -> str {
    return (value or "").strip().lower();
}

def _marks(n: int) -> str {
    return ",".join("?" * n);
}

def _insert(table: str, columns: str, verb: str = "INSERT OR IGNORE") -> str {
    names = columns.split();
    return f"{verb} INTO {table} ({', '.join(names)}) VALUES ({_marks(len(names))})";
}

def _filters(pairs: list[tuple[str, any]]) -> tuple[str, list[any]] {
    used = [(c, v) for (c, v) in pairs if v];
    return (
        " WHERE " + " AND ".join([c for (c, v) in used]) if used else "",
        [v for (c, v) in used if "?" in c],
    );
}

def _json_list(raw: any) -> list[any] {
    try {
        parsed = json.loads(raw) if raw else [];
    } except (json.JSONDecodeError, TypeError) {
        return [];
    }
    return parsed if isinstance(parsed, list) else [];
}

def _checked(kind: str, fields: builtins.dict, allowed: any) -> builtins.dict {
    invalid = set(fields) - allowed;
    if invalid {
        raise ValueError(f"Invalid {kind} column(s): {sorted(invalid)}");
    }
    return fields;
}

def _parse_time(value: any, fallback: datetime) -> datetime {
    try {
        return datetime.fromisoformat(str(value));
    } except (TypeError, ValueError) {
        return fallback;
    }
}

def _parent_domains(domain: str) -> list[str] {
    labels = domain.split(".");
    return [".".join(labels[i:]) for i in range(len(labels) - 1)];
}

async def _fetch(db: any, sql: str, params: any = (), one: bool = False) -> any {
    async with db.execute(sql, params) as cursor {
        return (await cursor.fetchone()) if one else (await cursor.fetchall());
    }
}

def _row_values(model: any, columns: list[str]) -> list[any] {
    values: list[any] = [];
    for column in columns {
        value = getattr(model, column, None);
        if column.endswith("_json") {
            value = value()
                if callable(value)
                else json.dumps(getattr(model, column.removesuffix("_json")));
        }
        values.append(value.isoformat() if isinstance(value, datetime) else value);
    }
    return values;
}

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

def _company_from_row(row: any) -> Company {
    d: builtins.dict = dict(row);
    d["tech_stack"] = _json_list(d.pop("tech_stack_json", None));
    d["signals"] = _json_list(d.pop("signals_json", None));
    return Company(**d);
}

def _prospect_from_row(row: any) -> Prospect {
    d: builtins.dict = dict(row);
    for k in ("email_verified", "phone_verified") {
        d[k] = bool(d.get(k, 0));
    }
    for k in ("email_status", "timezone") {
        d[k] = d.get(k) or "";
    }
    return Prospect(**d);
}

def _conversation_from_row(row: any) -> Conversation {
    d: builtins.dict = dict(row);
    d["thread"] = Conversation.thread_from_json(d.pop("thread_json"));
    return Conversation(**d);
}

def _usage_row_to_dict(row: any) -> builtins.dict {
    d: builtins.dict = {
        k: (0 if v is None and k != "period" else v)
        for (k, v) in dict(row).items()
    };
    if "cost_usd" in d {
        d["cost_usd"] = round(float(d["cost_usd"] or 0.0), 6);
    }
    return d;
}

def _suppression_key(kind: str, value: str) -> str {
    value = _norm(value);
    if kind == "domain" {
        value = value.split("@")[-1].removeprefix("https://").removeprefix("http://");
        value = value.split("/")[0].split("?")[0].split("#")[0].split(":")[0].removeprefix(
            "www."
        ).strip(".");
        if "." not in value or " " in value {
            return "";
        }
    }
    return value;
}

class StateManager {
    has db_path: str = "";

    def init(db_path: str | None = None) {
        if not db_path {
            home = _HOME.get();
            db_path = str(home.db_path) if home is not None else str(DB_PATH);
        }
        self.db_path = db_path;
    }

    def _connect -> any {
        return storage.connect(self.db_path, timeout=BUSY_TIMEOUT_SECONDS);
    }

    async def _select(sql: str, params: any = (), one: bool = False) -> any {
        async with self._connect() as db {
            db.row_factory = aiosqlite.Row;
            return await _fetch(db, sql, params, one);
        }
    }

    async def _dicts(sql: str, params: any = ()) -> list[builtins.dict] {
        return [dict(r) for r in await self._select(sql, params)];
    }

    async def _dict(sql: str, params: any = ()) -> builtins.dict | None {
        row = await self._select(sql, params, True);
        return dict(row) if row else None;
    }

    async def _value(sql: str, params: any = (), fallback: any = None) -> any {
        row = await self._select(sql, params, True);
        return row[0] if row else fallback;
    }

    async def _counts(sql: str) -> dict[str, int] {
        return {r[0]: r[1] for r in await self._select(sql)};
    }

    async def _insert_row(
        model: any, table: str, columns: str, keys: str = "", verb: str = "INSERT OR IGNORE"
    ) -> str {
        async with self._connect() as db {
            cursor = await db.execute(
                _insert(table, columns, verb), _row_values(model, columns.split())
            );
            await db.commit();
            if cursor.rowcount == 0 {
                for column in keys.split() {
                    value = getattr(model, column);
                    row = (
                        await _fetch(
                            db, f"SELECT id FROM {table} WHERE {column} = ?", (value,), True
                        )
                    )
                        if value
                        else None;
                    if row {
                        model.id = row[0];
                        break;
                    }
                }
            }
        }
        return model.id;
    }

    async def _changed(sql: str, params: any = ()) -> bool {
        return (await self._exec(sql, params)) > 0;
    }

    async def _exec(sql: str, params: any = ()) -> int {
        async with self._connect() as db {
            cursor = await db.execute(sql, params);
            await db.commit();
            return cursor.rowcount;
        }
    }

    async def _update(table: str, row_id: str, fields: builtins.dict, stamp: bool) {
        if fields {
            sets = ", ".join([f"{k} = ?" for k in fields]) + (", updated_at = ?" if stamp else "");
            stamps = [_utcnow().isoformat()] if stamp else [];
            await self._exec(
                f"UPDATE {table} SET {sets} WHERE id = ?", [*fields.values(), *stamps, row_id]
            );
        }
    }

    async def init_db {
        if storage.manages_schema(self.db_path) {
            await storage.check_schema(self.db_path);
            return;
        }
        Path(self.db_path).parent.mkdir(parents=True, exist_ok=True);
        async with self._connect() as db {
            await db.execute("PRAGMA journal_mode=WAL");
            await db.execute("PRAGMA synchronous=NORMAL");
            version = (await _fetch(db, "PRAGMA user_version", (), True))[0];
            for (target, script) in enumerate(MIGRATIONS, 1) {
                if version < target {
                    await db.executescript(script);
                    await db.execute(f"PRAGMA user_version = {target}");
                    await db.commit();
                }
            }
        }
    }

    async def _company_by(column: str, value: str) -> Company | None {
        row = await self._dict(f"SELECT * FROM companies WHERE {column} = ?", (value,));
        return _company_from_row(row) if row else None;
    }

    async def add_company(company: Company) -> str {
        if not company.id {
            company.id = _new_id();
        }
        company.domain = _norm(company.domain);
        return await self._insert_row(
            company,
            "companies",
            "id name domain website description industry company_size location phone source source_url external_id notes tech_stack_json signals_json created_at updated_at",
            "domain external_id",
        );
    }

    async def update_company_signals(
        company_id: str,
        tech_stack: list[str] | None = None,
        new_signals: list[builtins.dict] | None = None,
    ) {
        async with self._connect() as db {
            row = await _fetch(
                db,
                "SELECT tech_stack_json, signals_json FROM companies WHERE id = ?",
                (company_id,),
                True,
            );
            if not row {
                return;
            }
            tech = _json_list(row[0]);
            signals = _json_list(row[1]);
            for t in tech_stack or [] {
                if t not in tech {
                    tech.append(t);
                }
            }
            seen = {(s.get("type"), s.get("detail")) for s in signals if isinstance(s, dict)};
            for s in new_signals or [] {
                if isinstance(s, dict) and (s.get("type"), s.get("detail")) not in seen {
                    signals.append(s);
                    seen.add((s.get("type"), s.get("detail")));
                }
            }
            await db.execute(
                "UPDATE companies SET tech_stack_json = ?, signals_json = ?, updated_at = ? WHERE id = ?",
                (json.dumps(tech), json.dumps(signals), _utcnow().isoformat(), company_id),
            );
            await db.commit();
        }
    }

    async def get_company(company_id: str) -> Company | None {
        return await self._company_by("id", company_id);
    }

    async def get_company_by_domain(domain: str) -> Company | None {
        return await self._company_by("domain", _norm(domain));
    }

    async def get_company_by_external_id(external_id: str) -> Company | None {
        return (await self._company_by("external_id", external_id)) if external_id else None;
    }

    async def get_contacts_for_company(company_id: str) -> list[Prospect] {
        return [
            _prospect_from_row(r)
            for r in await self._select(
                "SELECT * FROM prospects WHERE company_id = ? ORDER BY score DESC", (company_id,)
            )
        ];
    }

    async def company_exists(domain: str) -> bool {
        return bool(
            await self._select("SELECT 1 FROM companies WHERE domain = ?", (_norm(domain),), True)
        );
    }

    async def _prospect_by(column: str, value: str) -> Prospect | None {
        row = await self._select(f"SELECT * FROM prospects WHERE {column} = ?", (value,), True);
        return _prospect_from_row(row) if row else None;
    }

    async def add_prospect(prospect: Prospect) -> str {
        if not prospect.id {
            prospect.id = _new_id();
        }
        prospect.email = _norm(prospect.email);
        prospect.linkedin_url = (prospect.linkedin_url or "").strip();
        return await self._insert_row(
            prospect,
            "prospects",
            "id company_id first_name last_name email email_verified email_status phone phone_verified linkedin_url title seniority department source source_url status score personalization_notes company industry company_size created_at updated_at",
            "email linkedin_url id",
        );
    }

    async def get_prospect(prospect_id: str) -> Prospect | None {
        return await self._prospect_by("id", prospect_id);
    }

    async def get_prospects_by_status(status: str) -> list[Prospect] {
        return [
            _prospect_from_row(r)
            for r in await self._select(
                "SELECT * FROM prospects WHERE status = ? ORDER BY created_at DESC", (status,)
            )
        ];
    }

    async def set_prospect_timezone(prospect_id: str, zone: str) {
        await self._exec("UPDATE prospects SET timezone = ? WHERE id = ?", (zone, prospect_id));
    }

    async def update_prospect_status(prospect_id: str, status: str) {
        await self._exec(
            "UPDATE prospects SET status = ?, updated_at = ? WHERE id = ? AND status IS NOT 'opted_out'",
            (status, _utcnow().isoformat(), prospect_id),
        );
    }

    async def undo_opt_out(prospect_id: str, details: builtins.dict | None = None) -> bool {
        async with self._connect() as db {
            cursor = await db.execute(
                "UPDATE prospects SET status = 'replied', updated_at = ? WHERE id = ? AND status = 'opted_out'",
                (_utcnow().isoformat(), prospect_id),
            );
            if cursor.rowcount != 1 {
                await db.rollback();
                return False;
            }
            row = await _fetch(
                db, "SELECT email FROM prospects WHERE id = ?", (prospect_id,), True
            );
            if row and row[0] {
                await db.execute(
                    "DELETE FROM suppressions WHERE kind = 'address' AND value = ? AND reason = 'opted_out'",
                    (_suppression_key("address", row[0]),),
                );
            }
            await db.execute(_UPSERT_SETTING, (REVIEW_NEXT_REPLY_KEY + prospect_id, "1"));
            await db.execute(
                _LOG_ACTION,
                (
                    _new_id(),
                    "opt_out_undone",
                    "dashboard",
                    json.dumps({"prospect_id": prospect_id, **(details or {})}),
                ),
            );
            await db.commit();
            return True;
        }
    }

    async def opt_out_history(prospect_id: str) -> list[builtins.dict] {
        rows = await self._select(
            "SELECT action_type, details_json, created_at FROM actions WHERE action_type IN ('opt_out', 'opt_out_undone') AND json_valid(details_json) AND json_extract(details_json, '$.prospect_id') = ? ORDER BY created_at, rowid",
            (prospect_id,),
        );
        return [dict(json.loads(d), action=a, at=str(at or "")) for (a, d, at) in rows];
    }

    async def queue_prospect_if_unsent(prospect_id: str) -> bool {
        return await self._changed(
            "UPDATE prospects SET status = 'queued', updated_at = ? WHERE id = ? AND status IN ('new', 'queued')",
            (_utcnow().isoformat(), prospect_id),
        );
    }

    async def get_prospect_by_email(email: str) -> Prospect | None {
        email = _norm(email);
        return (await self._prospect_by("email", email)) if email else None;
    }

    async def update_prospect_email(prospect_id: str, email: str, email_status: str) {
        await self._exec(
            "UPDATE prospects SET email = ?, email_status = ?, email_verified = ?, updated_at = ? WHERE id = ?",
            (
                _norm(email),
                email_status,
                1 if email_status == "verified" else 0,
                _utcnow().isoformat(),
                prospect_id,
            ),
        );
    }

    async def get_email_pattern(domain: str) -> builtins.dict | None {
        return await self._dict("SELECT * FROM email_patterns WHERE domain = ?", (_norm(domain),));
    }

    async def save_email_pattern(
        domain: str,
        pattern: str = "",
        source: str = "",
        confidence: float = 0.0,
        mx_type: str = "",
        is_catch_all: int | None = None,
    ) {
        domain = _norm(domain);
        if domain {
            await self._exec("""INSERT INTO email_patterns
                           (domain, pattern, source, confidence, mx_type, is_catch_all, updated_at)
                       VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
                       ON CONFLICT(domain) DO UPDATE SET
                           pattern = CASE WHEN excluded.confidence >= email_patterns.confidence
                                           AND excluded.pattern != ''
                                          THEN excluded.pattern ELSE email_patterns.pattern END,
                           source = CASE WHEN excluded.confidence >= email_patterns.confidence
                                          AND excluded.pattern != ''
                                         THEN excluded.source ELSE email_patterns.source END,
                           confidence = MAX(email_patterns.confidence, excluded.confidence),
                           mx_type = CASE WHEN excluded.mx_type != ''
                                          THEN excluded.mx_type ELSE email_patterns.mx_type END,
                           is_catch_all = CASE WHEN excluded.is_catch_all != -1
                                               THEN excluded.is_catch_all
                                               ELSE email_patterns.is_catch_all END,
                           updated_at = CURRENT_TIMESTAMP""", (domain, pattern, source, float(confidence), mx_type, -1 if is_catch_all is None else int(is_catch_all)));
        }
    }

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
    ) -> str | None {
        item_id = _new_id();
        async with self._connect() as db {
            cursor = await db.execute(
                _insert(
                    "outbox",
                    "id campaign_id prospect_id conversation_id step kind to_email subject body status send_at provider thread_ref in_reply_to mailbox_id",
                ),
                (
                    item_id,
                    campaign_id,
                    prospect_id,
                    conversation_id,
                    int(step),
                    kind,
                    _norm(to_email),
                    subject,
                    body,
                    status,
                    send_at,
                    provider,
                    thread_ref,
                    in_reply_to,
                    mailbox_id or "",
                ),
            );
            if cursor.rowcount > 0 and approved_by {
                await db.execute(
                    "UPDATE outbox SET approved_by = ? WHERE id = ?", (approved_by, item_id)
                );
            }
            await db.commit();
            return item_id if cursor.rowcount > 0 else None;
        }
    }

    async def get_outbox(
        status: str | None = None,
        due_before: str | None = None,
        limit: int = 200,
        exclude_kind: str | None = None,
        skip_unready_follow_ups: bool = False,
        kind: str | None = None,
        follow_ups_only: bool = False,
    ) -> list[builtins.dict] {
        (where, params) = _filters([
            ("kind = ?", kind),
            ("status = ?", status),
            ("(send_at IS NULL OR send_at <= ?)", due_before),
            ("(kind IS NULL OR kind != ?)", exclude_kind),
            ("o.kind = 'sequence' AND o.step > 1", follow_ups_only),
            (
                f"NOT (o.kind = 'sequence' AND o.step > 1 AND {_PREV_STEP_UNSENT})",
                skip_unready_follow_ups,
            ),
        ]);
        return await self._dicts(
            f"SELECT * FROM outbox o{where} ORDER BY send_at ASC, created_at ASC LIMIT ?",
            params + [int(limit)],
        );
    }

    async def get_texts_for_prospect(prospect_id: str, limit: int = 50) -> list[str] {
        texts: list[str] = [
            r[0] or ""
            for r in await self._select(
                "SELECT body FROM outbox WHERE prospect_id = ? ORDER BY created_at DESC LIMIT ?",
                (prospect_id, int(limit)),
            )
        ];
        rows = await self._select(
            "SELECT sequence_json, prospect_ids_json FROM campaigns WHERE prospect_ids_json LIKE ? ORDER BY created_at DESC LIMIT ?",
            ("%" + prospect_id + "%", int(limit)),
        );
        for (sequence_json, ids_json) in rows {
            try {
                if prospect_id in json.loads(ids_json or "[]") {
                    texts += [
                        str(step.get("body") or "")
                        for step in json.loads(sequence_json or "[]")
                        if isinstance(step, dict)
                    ];
                }
            } except (json.JSONDecodeError, TypeError, AttributeError) {}
        }
        return texts;
    }

    async def count_due_cold_outbox(
        due_before: str,
        stored_verdicts: tuple[str, str, str] | None = None,
        moved_back_prefix: str = "",
        has_cached_verdict: any = None,
    ) -> int {
        due = "(o.send_at IS NULL OR o.send_at <= ?)";
        params: list[any] = [due_before];
        if moved_back_prefix {
            due = f"({due} OR substr(COALESCE(o.error, ''), 1, ?) = ?)";
            params += [len(moved_back_prefix), moved_back_prefix];
        }
        sql = f"SELECT COUNT(*) FROM outbox o WHERE o.status = 'approved' AND o.kind = 'sequence' AND {due} AND NOT (o.step > 1 AND {_PREV_STEP_UNSENT})";
        if stored_verdicts {
            sql += " AND NOT EXISTS (SELECT 1 FROM settings s WHERE s.key = ? || lower(trim(o.to_email)) AND CASE WHEN json_valid(s.value) THEN json_extract(s.value, '$.inputs') END = ? AND CASE WHEN json_valid(s.value) THEN json_extract(s.value, '$.verdict') END IN ('ok_to_email', 'consent_needed', 'blocked') AND CASE WHEN json_valid(s.value) THEN julianday(json_extract(s.value, '$.checked_at')) END >= julianday(?))";
            params += list(stored_verdicts);
        }
        if has_cached_verdict is None {
            return await self._value(sql, params);
        }
        waiting = 0;
        for item in await self._dicts(
            sql.replace("SELECT COUNT(*)", "SELECT o.prospect_id, o.to_email", 1), params
        ) {
            if not await has_cached_verdict(item) {
                waiting += 1;
            }
        }
        return waiting;
    }

    async def get_outbox_item(item_id: str) -> builtins.dict | None {
        return await self._dict("SELECT * FROM outbox WHERE id = ?", (item_id,));
    }

    async def update_outbox_item(item_id: str, **kwargs: any) {
        await self._update(
            "outbox", item_id, {k: v for (k, v) in kwargs.items() if k in _OUTBOX_COLUMNS}, True
        );
    }

    async def claim_outbox_item(item_id: str) -> bool {
        now = _utcnow().isoformat();
        sql = "UPDATE outbox SET status = 'sending', updated_at = ? WHERE id = ? AND status = 'approved' AND (send_at IS NULL OR send_at <= ?)";
        return (await self._exec(sql, (now, item_id, now))) == 1;
    }

    async def fail_stale_sending_outbox(older_than: timedelta = STALE_SENDING_AFTER) -> int {
        cutoff = (_utcnow() - older_than).isoformat();
        return await self._exec(
            "UPDATE outbox SET status = 'failed', error = ?, updated_at = ? WHERE status = 'sending' AND datetime(updated_at) < datetime(?)",
            (STALE_SENDING_ERROR, _utcnow().isoformat(), cutoff),
        );
    }

    async def edit_outbox_draft(item_id: str, subject: str, body: str) -> int {
        return await self._exec(
            "UPDATE outbox SET subject = ?, body = ?, updated_at = ? WHERE id = ? AND status = 'pending_review'",
            (subject, body, _utcnow().isoformat(), item_id),
        );
    }

    async def restore_hand_cancelled_outbox(prospect_id: str, reason: str) -> int {
        async with self._connect() as db {
            rows = await _fetch(
                db,
                "SELECT id, send_at FROM outbox WHERE prospect_id = ? AND status = 'cancelled' AND error = ? ORDER BY send_at",
                (prospect_id, reason),
            );
            if not rows {
                return 0;
            }
            now = _utcnow();
            first = _parse_time(rows[0][1], now);
            for (item_id, send_at) in rows {
                await db.execute(
                    "UPDATE outbox SET status = 'pending_review', error = '', send_at = ?, updated_at = ? WHERE id = ?",
                    (
                        (now + max(timedelta(0), _parse_time(send_at, now) - first)).isoformat(),
                        now.isoformat(),
                        item_id,
                    ),
                );
            }
            await db.commit();
            return len(rows);
        }
    }

    async def reject_outbox_item(item_id: str) -> int {
        return await self._exec(
            "UPDATE outbox SET status = 'rejected', updated_at = ?, error = CASE WHEN substr(COALESCE(error, ''), 1, ?) = ? OR substr(COALESCE(error, ''), 1, ?) = ? THEN '' ELSE error END WHERE id = ? AND status IN ('pending_review', 'approved')",
            (
                _utcnow().isoformat(),
                len(RECHECK_PREFIX),
                RECHECK_PREFIX,
                len(UNKNOWN_HOLD_PREFIX),
                UNKNOWN_HOLD_PREFIX,
                item_id,
            ),
        );
    }

    async def approve_outbox(item_id: str | None = None) -> int {
        sql = "UPDATE outbox SET status = 'approved', approved_by = 'you', error = '', updated_at = ? WHERE ";
        if item_id {
            return await self._exec(
                sql + "id = ? AND status = 'pending_review'", (_utcnow().isoformat(), item_id)
            );
        }
        return await self._exec(
            sql + "status = 'pending_review' AND COALESCE(error, '') NOT LIKE ?",
            (_utcnow().isoformat(), HELD_FOR_REVIEW + "%"),
        );
    }

    async def note_sends_held(reason: str) {
        now = _utcnow().isoformat();
        since = ((await self.current_sends_held()) or {}).get("since") or now;
        await self.set_setting(
            SENDS_HELD_KEY,
            json.dumps({"since": since, "last_seen": now, "reason": str(reason)[:500]}),
        );
    }

    async def clear_sends_held {
        if await self.get_setting(SENDS_HELD_KEY) {
            await self.delete_setting(SENDS_HELD_KEY);
        }
    }

    async def current_sends_held(max_age_hours: float = 12) -> builtins.dict | None {
        try {
            hold = json.loads(await self.get_setting(SENDS_HELD_KEY) or "null");
            seen = datetime.fromisoformat(hold["last_seen"]);
        } except (json.JSONDecodeError, TypeError, KeyError, ValueError) {
            return None;
        }
        return None if _utcnow() - seen > timedelta(hours=max_age_hours) else hold;
    }

    async def requeue_autopilot_approved -> int {
        return await self._exec(
            "UPDATE outbox SET status = 'pending_review', approved_by = '', error = ?, updated_at = ? WHERE status = 'approved' AND approved_by IN ('autopilot', 'earlier')",
            (AUTOPILOT_OFF_REASON, _utcnow().isoformat()),
        );
    }

    async def count_held_for_review -> int {
        return await self._value(
            "SELECT COUNT(*) FROM outbox WHERE status = 'pending_review' AND error LIKE ?",
            (HELD_FOR_REVIEW + "%",),
        );
    }

    async def cancel_pending_outbox_for_prospect(
        prospect_id: str, reason: str = "stop_on_reply"
    ) -> int {
        return await self._exec(
            "UPDATE outbox SET status = 'cancelled', error = ?, updated_at = ? WHERE prospect_id = ? AND status IN ('pending_review', 'approved')",
            (reason, _utcnow().isoformat(), prospect_id),
        );
    }

    async def stop_company(prospect_id: str) -> int {
        async with self._connect() as db {
            row = await _fetch(
                db,
                "SELECT first_name, last_name, email FROM prospects WHERE id = ?",
                (prospect_id,),
                True,
            );
            if row is None {
                return 0;
            }
            who = " ".join([x for x in (row[0], row[1]) if x]) or row[2];
            await db.execute(
                "INSERT OR REPLACE INTO settings (key, value, updated_at) VALUES (?, ?, ?)",
                (COMPANY_STOP_KEY + prospect_id, who, _utcnow().isoformat()),
            );
            cursor = await db.execute(
                f"UPDATE outbox SET status = 'cancelled', error = ?, updated_at = ? WHERE kind = 'sequence' AND status IN ('pending_review', 'approved') AND prospect_id IN (SELECT c.id FROM prospects c, prospects p WHERE p.id = ? AND {_colleagues('p', 'c')})",
                (f"{COLLEAGUE_REPLIED} ({who})", _utcnow().isoformat(), prospect_id),
            );
            await db.commit();
            return cursor.rowcount;
        }
    }

    static def suppression_key(kind: str, value: str) -> str {
        return _suppression_key(kind, value);
    }

    async def add_suppression(
        kind: str, value: str, reason: str = "manual", source: str = ""
    ) -> bool {
        if kind not in SUPPRESSION_KINDS {
            raise ValueError("kind must be address or domain");
        }
        if reason not in SUPPRESSION_REASONS {
            reason = "manual";
        }
        key = _suppression_key(kind, value);
        if not key or (kind == "address" and "@" not in key) {
            raise ValueError("not an address or domain");
        }
        return await self._changed(
            "INSERT OR IGNORE INTO suppressions (id, kind, value, reason, source) VALUES (?, ?, ?, ?, ?)",
            (uuid.uuid4().hex, kind, key, reason, source[:200]),
        );
    }

    async def suppressed_among(emails: any) -> dict[str, str] {
        wanted = {_norm(e) for e in emails if _norm(e)};
        if not wanted {
            return {};
        }
        domains = {d for e in wanted for d in _parent_domains(e.split("@")[-1])};
        keys = [("address", e) for e in wanted] + [("domain", d) for d in domains];
        found: dict[tuple[str, str], str] = {};
        async with self._connect() as db {
            for start in range(0, len(keys), 500) {
                chunk = keys[start:start + 500];
                where = " OR ".join(["(kind = ? AND value = ?)"] * len(chunk));
                for (kind, value, reason) in await _fetch(
                    db,
                    f"SELECT kind, value, reason FROM suppressions WHERE {where}",
                    [x for pair in chunk for x in pair],
                ) {
                    found[(kind, value)] = reason;
                }
            }
        }
        out: dict[str, str] = {};
        for e in wanted {
            reason = found.get(("address", e));
            for d in _parent_domains(e.split("@")[-1]) {
                if not reason and ("domain", d) in found {
                    reason = found[("domain", d)];
                }
            }
            if reason {
                out[e] = reason;
            }
        }
        return out;
    }

    async def is_suppressed(email: str) -> str | None {
        return (await self.suppressed_among([email])).get(_norm(email));
    }

    async def list_suppressions(limit: int = 200, offset: int = 0) -> list[builtins.dict] {
        return await self._dicts(
            "SELECT id, kind, value, reason, source, created_at FROM suppressions ORDER BY created_at DESC, id LIMIT ? OFFSET ?",
            (int(limit), int(offset)),
        );
    }

    async def remove_suppression(suppression_id: str) -> bool {
        return await self._changed("DELETE FROM suppressions WHERE id = ?", (suppression_id,));
    }

    async def colleague_who_replied(prospect_id: str) -> str | None {
        return await self._value(
            f"SELECT s.value FROM prospects p, prospects c, settings s WHERE p.id = ? AND s.key = '{COMPANY_STOP_KEY}' || c.id AND {_colleagues('p', 'c')} LIMIT 1",
            (prospect_id,),
        );
    }

    async def count_outbox_sent -> int {
        return await self._value("SELECT COUNT(*) FROM outbox WHERE status = 'sent'");
    }

    async def count_outbox_sent_today(
        kind: str | None = None, since: str | None = None, mailbox_id: str | None = None
    ) -> int {
        sql = "SELECT COUNT(*) FROM outbox WHERE status = 'sent' AND "
            + ("sent_at >= ?" if since else "date(sent_at) = date('now')");
        params: list[any] = [since] if since else [];
        if kind {
            sql += " AND kind = ?";
            params.append(kind);
        }
        if mailbox_id is not None {
            sql += " AND COALESCE(mailbox_id, '') = ?";
            params.append(mailbox_id);
        }
        return await self._value(sql, params);
    }

    async def get_step_delay_days(campaign_id: str, step: int) -> int | None {
        raw = await self._value(
            "SELECT sequence_json FROM campaigns WHERE id = ?", (campaign_id or "",)
        );
        try {
            for s in json.loads(raw or "[]") {
                if isinstance(s, dict) and int(s.get("step", 0)) == int(step) {
                    return max(0, int(s.get("delay_days") or 0));
                }
            }
        } except (json.JSONDecodeError, TypeError, ValueError) {}
        return None;
    }

    async def get_previous_step(item: builtins.dict) -> builtins.dict | None {
        return await self._dict(
            "SELECT * FROM outbox WHERE prospect_id = ? AND campaign_id = ? AND kind = 'sequence' AND step = ? ORDER BY created_at DESC LIMIT 1",
            (item["prospect_id"], item.get("campaign_id") or "", int(item["step"]) - 1),
        );
    }

    async def find_outbox_by_message_id(message_id: str) -> builtins.dict | None {
        return (await self._dict("SELECT * FROM outbox WHERE message_id = ?", (message_id,)))
            if message_id
            else None;
    }

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
    ) {
        await self._exec("""INSERT INTO signal_codes
                       (code, label, description, category, value_type,
                        collector, cost_note, confidence_floor, status)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, COALESCE(?, 'proposed'))
                   ON CONFLICT(code) DO UPDATE SET
                       label = excluded.label, description = excluded.description,
                       category = excluded.category, value_type = excluded.value_type,
                       collector = excluded.collector, cost_note = excluded.cost_note,
                       confidence_floor = excluded.confidence_floor,
                       status = COALESCE(?, signal_codes.status),
                       updated_at = CURRENT_TIMESTAMP""", (code, label, description, category, value_type, collector, cost_note, float(confidence_floor), status, status));
    }

    async def get_signal_codes(status: str | None = None) -> list[builtins.dict] {
        (where, params) = _filters([("status = ?", status)]);
        return await self._dicts(
            f"SELECT * FROM signal_codes{where} ORDER BY category, code", params
        );
    }

    async def set_signal_status(code: str, status: str) -> bool {
        if status not in ("proposed", "confirmed", "rejected") {
            raise ValueError(f"invalid signal status: {status}");
        }
        return await self._changed(
            "UPDATE signal_codes SET status = ?, updated_at = CURRENT_TIMESTAMP WHERE code = ?",
            (status, code),
        );
    }

    async def confirmed_signal_codes -> set[str] {
        return {r["code"] for r in await self.get_signal_codes(status="confirmed")};
    }

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
    ) -> str {
        obs_id = _new_id();
        await self._exec(
            _INSERT_OBSERVATION,
            (
                obs_id,
                company_id,
                prospect_id,
                signal_code,
                collector,
                value_num,
                value_text,
                float(confidence),
                evidence_url,
                observed_at,
                run_id,
            ),
        );
        return obs_id;
    }

    async def add_observations(rows: list[builtins.dict], run_id: str = "") -> int {
        if not rows {
            return 0;
        }
        payload = [
            (
                _new_id(),
                r.get("company_id", ""),
                r.get("prospect_id", ""),
                r["signal_code"],
                r.get("collector", ""),
                r.get("value_num"),
                r.get("value_text", ""),
                float(r.get("confidence", 1.0)),
                r.get("evidence_url", ""),
                r.get("observed_at"),
                r.get("run_id", run_id),
            )
            for r in rows
        ];
        async with self._connect() as db {
            await db.executemany(_INSERT_OBSERVATION, payload);
            await db.commit();
        }
        return len(payload);
    }

    async def _latest(company_id: str, signal_code: str) -> builtins.dict | None {
        rows = await self.get_observations(
            company_id=company_id, signal_code=signal_code, latest_only=True, limit=1
        );
        return rows[0] if rows else None;
    }

    async def _latest_yes(company_id: str, signal_code: str) -> builtins.dict | None {
        row = (await self._latest(company_id, signal_code)) if company_id else None;
        return row if row and row.get("value_num") == 1 else None;
    }

    async def yc_batch(company_id: str) -> str | None {
        row = await self._latest_yes(company_id, "YC_BACKED");
        return (row.get("value_text") or "") if row else None;
    }

    async def search_hit(company_id: str, signal_code: str) -> bool {
        row = await self._latest(company_id, signal_code);
        return bool(row)
            and bool(operator.eq(row.get("collector"), "discover"))
            and bool(operator.eq(row.get("value_num"), 1));
    }

    async def accelerator(company_id: str) -> str | None {
        row = await self._latest_yes(company_id, "ACCELERATOR");
        return (row.get("value_text") or "") if row else None;
    }

    async def funding_round(company_id: str) -> builtins.dict | None {
        row = await self._latest_yes(company_id, "FUNDING_ROUND");
        return parse_funding(row.get("value_text") or "") if row else None;
    }

    async def get_observations(
        company_id: str = "", signal_code: str = "", latest_only: bool = False, limit: int = 500
    ) -> list[builtins.dict] {
        (where, params) = _filters([
            ("company_id = ?", company_id),
            ("signal_code = ?", signal_code),
        ]);
        sql = "SELECT * FROM observations" + where;
        sql = f"SELECT * FROM ({sql} ORDER BY observed_at DESC) GROUP BY company_id, signal_code"
            if latest_only
            else sql + " ORDER BY observed_at DESC";
        return await self._dicts(sql + " LIMIT ?", params + [int(limit)]);
    }

    async def signal_counts -> list[builtins.dict] {
        return await self._dicts(_CURRENT_CTE + """
                    SELECT p.signal_code,
                           COALESCE(sc.label, p.signal_code) AS label,
                           sc.status AS status,
                           COUNT(DISTINCT p.company_id) AS companies,
                           COUNT(*) AS observations
                    FROM positive p
                    LEFT JOIN signal_codes sc ON sc.code = p.signal_code
                    GROUP BY p.signal_code
                    ORDER BY companies DESC""");
    }

    async def cohort(
        require: list[str],
        exclude: list[str] | None = None,
        min_confidence: float = 0.0,
        limit: int = 500,
    ) -> list[str] {
        if not require {
            return [];
        }
        sql = _CURRENT_CTE
            + f"SELECT company_id FROM positive WHERE signal_code IN ({_marks(len(require))}) AND company_id != '' AND confidence >= ? GROUP BY company_id HAVING COUNT(DISTINCT signal_code) = ?";
        params: list[any] = [*require, float(min_confidence), len(set(require))];
        if exclude {
            sql += f" AND company_id NOT IN (SELECT company_id FROM positive WHERE signal_code IN ({_marks(len(exclude))}))";
            params.extend(exclude);
        }
        return [r[0] for r in await self._select(sql + " LIMIT ?", params + [int(limit)])];
    }

    async def ranked_company_ids(code: str, phrase: str) -> set[str] {
        return {
            r[0]
            for r in await self._select(
                _CURRENT_CTE
                    + " SELECT DISTINCT company_id FROM positive WHERE signal_code = ? AND value_text = ? AND company_id != ''",
                (code, phrase),
            )
        };
    }

    async def cohort_companies(
        require: list[str],
        exclude: list[str],
        offset: int = 0,
        limit: int | None = None,
        ranges: list[builtins.dict] | None = None,
    ) -> tuple[int, list[builtins.dict]] {
        ranges = list(ranges or []);
        if not require and not ranges {
            return (0, []);
        }
        require = list(dict.fromkeys(require));
        exclude = list(dict.fromkeys(exclude));
        where: list[str] = [];
        params: list[any] = [];
        if require {
            where.append(
                f"id IN (SELECT company_id FROM positive WHERE company_id != '' AND signal_code IN ({_marks(len(require))}) AND confidence >= 0 GROUP BY company_id HAVING COUNT(DISTINCT signal_code) = ?)",
            );
            params += [*require, len(require)];
        }
        if exclude {
            where.append(
                f"id NOT IN (SELECT company_id FROM positive WHERE signal_code IN ({_marks(len(exclude))}))",
            );
            params.extend(exclude);
        }
        for r in ranges {
            sub = "id IN (SELECT company_id FROM positive WHERE signal_code = ? AND value_num IS NOT NULL AND confidence >= 0";
            params.append(r["code"]);
            for (bound, op) in (("min", ">="), ("max", "<=")) {
                if r.get(bound) is not None {
                    sub += f" AND value_num {op} ?";
                    params.append(float(r[bound]));
                }
            }
            where.append(sub + ")");
        }
        base = _CURRENT_CTE + " SELECT {columns} FROM companies WHERE " + " AND ".join(where);
        sql = base.format(columns="id, name, domain, website, industry, location")
            + " ORDER BY LOWER(COALESCE(name, '')), id";
        page_params = list(params);
        if limit is not None {
            sql += " LIMIT ? OFFSET ?";
            page_params.extend([limit, offset]);
        }
        async with self._connect() as db {
            db.row_factory = aiosqlite.Row;
            await db.execute("BEGIN");
            size = (await _fetch(db, base.format(columns="COUNT(*)"), params, True))[0];
            return (size, [dict(row) for row in await _fetch(db, sql, page_params)]);
        }
    }

    async def companies_needing_profile(
        limit: int = 100, stale_days: int = 90
    ) -> list[builtins.dict] {
        return await self._dicts(
            f"SELECT c.id, c.name, c.domain {_PROFILE_DUE} ORDER BY {_LAST_PROFILED} IS NOT NULL, {_LAST_PROFILED} LIMIT ?",
            (f"-{int(stale_days)} days", int(limit)),
        );
    }

    async def count_companies_needing_profile(stale_days: int = 90) -> int {
        return await self._value(
            f"SELECT COUNT(*) {_PROFILE_DUE}", (f"-{int(stale_days)} days",), 0
        );
    }

    async def mark_company_profiled(company_id: str) {
        await self._exec(
            "UPDATE companies SET profile_checked_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
            (company_id,),
        );
    }

    async def rename_company(company_id: str, name: str) {
        async with self._connect() as db {
            await db.execute(
                "UPDATE companies SET name = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
                (name, company_id),
            );
            await db.execute(
                "UPDATE prospects SET company = ?, updated_at = CURRENT_TIMESTAMP WHERE company_id = ?",
                (name, company_id),
            );
            await db.commit();
        }
    }

    async def companies_needing_prospects(
        limit: int = 10, stale_days: int = 14
    ) -> list[builtins.dict] {
        return await self._dicts("""SELECT c.id, c.name, c.domain, c.industry
                   FROM companies c
                   LEFT JOIN prospects p ON p.company_id = c.id
                   WHERE c.domain != ''
                     AND (c.prospects_checked_at IS NULL
                          OR c.prospects_checked_at < datetime('now', ?))
                   GROUP BY c.id
                   HAVING COUNT(p.id) = 0
                   ORDER BY c.prospects_checked_at IS NOT NULL, c.prospects_checked_at
                   LIMIT ?""", (f"-{int(stale_days)} days", int(limit)));
    }

    async def mark_prospects_checked(company_id: str) {
        await self._exec(
            "UPDATE companies SET prospects_checked_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
            (company_id,),
        );
    }

    async def start_run(
        stage: str, provider: str = "", params: builtins.dict | None = None
    ) -> str {
        run_id = _new_id();
        await self._exec(
            "INSERT INTO runs (id, stage, provider, params_json, status) VALUES (?, ?, ?, ?, 'running')",
            (run_id, stage, provider, json.dumps(params or {})),
        );
        return run_id;
    }

    async def finish_run(
        run_id: str,
        status: str = "completed",
        records: int = 0,
        cost_usd: float = 0.0,
        error: str = "",
    ) {
        await self._exec(
            "UPDATE runs SET status = ?, records = ?, cost_usd = ?, error = ?, ended_at = CURRENT_TIMESTAMP WHERE id = ?",
            (status, int(records), float(cost_usd), error[:500], run_id),
        );
    }

    async def sweep_stale_runs(older_than_hours: int = 6) -> int {
        return await self._exec(
            "UPDATE runs SET status = 'stale', ended_at = CURRENT_TIMESTAMP WHERE status = 'running' AND started_at < datetime('now', ?)",
            (f"-{int(older_than_hours)} hours",),
        );
    }

    async def get_runs(limit: int = 25) -> list[builtins.dict] {
        return await self._dicts(
            "SELECT * FROM runs ORDER BY started_at DESC LIMIT ?", (int(limit),)
        );
    }

    async def remember_footer_lines(lines: any) {
        lines = [l.strip() for l in lines if l and l.strip()];
        if lines {
            known = _json_list(await self.get_setting(FOOTER_HISTORY_KEY) or "[]");
            merged = [l for l in known if isinstance(l, str)];
            merged += [l for l in lines if l not in merged];
            if merged != known {
                await self.set_setting(FOOTER_HISTORY_KEY, json.dumps(merged[-50:]));
            }
        }
    }

    async def get_footer_history -> list[str] {
        return [
            l
            for l in _json_list(await self.get_setting(FOOTER_HISTORY_KEY) or "[]")
            if isinstance(l, str)
        ];
    }

    async def get_setting(key: str, `default: str = "") -> str {
        return await self._value("SELECT value FROM settings WHERE key = ?", (key,), `default);
    }

    async def retry_write_failed -> int {
        return await self._exec(
            "UPDATE prospects SET status = 'new', updated_at = ? WHERE status = 'write_failed'",
            (_utcnow().isoformat(),),
        );
    }

    async def retry_no_tip -> int {
        return await self._exec(
            "UPDATE prospects SET status = 'new', updated_at = ? WHERE status = 'no_tip'",
            (_utcnow().isoformat(),),
        );
    }

    async def delete_setting(key: str) {
        await self._exec("DELETE FROM settings WHERE key = ?", (key,));
    }

    async def set_setting(key: str, value: str) {
        await self._exec(_UPSERT_SETTING, (key, str(value)));
    }

    async def increment_setting(key: str, `by: int = 1) -> int {
        try {
            value = int(await self.get_setting(key, "0")) + `by;
        } except ValueError {
            value = `by;
        }
        await self.set_setting(key, str(value));
        return value;
    }

    async def prospect_exists(
        email: str = "",
        linkedin_url: str = "",
        first_name: str = "",
        last_name: str = "",
        company: str = "",
    ) -> bool {
        checks: list[tuple[any, str, any]] = [
            (email, "email = ?", (_norm(email),)),
            (linkedin_url, "linkedin_url = ?", (linkedin_url.strip(),)),
            (
                first_name and last_name and company,
                "LOWER(first_name) = ? AND LOWER(last_name) = ? AND LOWER(company) = ?",
                (first_name.lower(), last_name.lower(), company.lower()),
            ),
        ];
        async with self._connect() as db {
            for (wanted, where, params) in checks {
                if wanted
                    and await _fetch(db, "SELECT 1 FROM prospects WHERE " + where, params, True)
                {
                    return True;
                }
            }
        }
        return False;
    }

    async def count_writable_prospects -> int {
        return await self._value(
            f"SELECT COUNT(*) FROM prospects p WHERE status = 'new' AND email != '' AND email_status IN ({_marks(len(WRITABLE_EMAIL_STATUSES))}) AND NOT {_company_answered('p')}",
            WRITABLE_EMAIL_STATUSES,
        );
    }

    async def count_recent_unusable_prospects(hours: int = 24) -> int {
        since = (_utcnow() - timedelta(hours=hours)).isoformat();
        return await self._value(
            f"SELECT COUNT(*) FROM prospects WHERE status = 'new' AND NOT (COALESCE(email, '') != '' AND COALESCE(email_status, '') IN ({_marks(len(WRITABLE_EMAIL_STATUSES))})) AND datetime(created_at) >= datetime(?)",
            (*WRITABLE_EMAIL_STATUSES, since),
        );
    }

    async def count_prospects_by_status -> dict[str, int] {
        return await self._counts("SELECT status, COUNT(*) FROM prospects GROUP BY status");
    }

    async def add_feedback(entity_type: str, entity_id: str, comment: str) -> str {
        feedback_id = _new_id();
        await self._exec(
            "INSERT INTO feedback (id, entity_type, entity_id, comment) VALUES (?, ?, ?, ?)",
            (feedback_id, entity_type, entity_id, comment),
        );
        return feedback_id;
    }

    async def get_feedback(entity_type: str, entity_id: str) -> list[builtins.dict] {
        return await self._dicts(
            "SELECT * FROM feedback WHERE entity_type = ? AND entity_id = ? ORDER BY created_at DESC",
            (entity_type, entity_id),
        );
    }

    async def get_all_feedback -> list[builtins.dict] {
        return await self._dicts("SELECT * FROM feedback ORDER BY created_at DESC LIMIT 100");
    }

    async def get_writing_feedback(prospect_ids: any = (), limit: int = 10) -> list[builtins.dict] {
        out: list[builtins.dict] = [];
        for r in await self._select(
            "SELECT f.comment, f.created_at, c.name FROM feedback f LEFT JOIN campaigns c ON c.id = f.entity_id WHERE f.entity_type = 'campaign' AND TRIM(f.comment) != '' ORDER BY f.created_at DESC LIMIT ?",
            (int(limit),),
        ) {
            out.append({
                "about": f"campaign '{r['name']}'" if r["name"] else "a past campaign",
                "comment": r["comment"],
                "created_at": r["created_at"],
            });
        }
        ids = [i for i in prospect_ids if i][:50];
        if ids {
            for r in await self._select(
                f"SELECT f.comment, f.created_at, p.first_name, p.last_name FROM feedback f JOIN prospects p ON p.id = f.entity_id WHERE f.entity_type = 'contact' AND f.entity_id IN ({_marks(len(ids))}) AND TRIM(f.comment) != '' ORDER BY f.created_at DESC LIMIT ?",
                (*ids, int(limit)),
            ) {
                name = " ".join([x for x in (r["first_name"], r["last_name"]) if x]);
                out.append({
                    "about": name or "this contact",
                    "comment": r["comment"],
                    "created_at": r["created_at"],
                });
            }
        }
        out.sort(
            key=lambda (n: builtins.dict) -> str { str(n.get("created_at") or "") }, reverse=True
        );
        return out;
    }

    async def is_reply_processed(reply_id: str) -> bool {
        return bool(reply_id)
            and bool(
                await self._select(
                    "SELECT 1 FROM processed_replies WHERE reply_id = ?", (reply_id,), True
                ),
            );
    }

    async def mark_reply_processed(reply_id: str) {
        if reply_id {
            await self._exec(
                "INSERT OR IGNORE INTO processed_replies (reply_id) VALUES (?)", (reply_id,)
            );
        }
    }

    async def add_campaign(campaign: Campaign) -> str {
        if not campaign.id {
            campaign.id = _new_id();
        }
        return await self._insert_row(
            campaign,
            "campaigns",
            "id name channel instantly_campaign_id sequence_json prospect_ids_json status created_at",
            "",
            "INSERT",
        );
    }

    async def get_campaigns_by_status(status: str) -> list[Campaign] {
        campaigns: list[Campaign] = [];
        for d in await self._dicts("SELECT * FROM campaigns WHERE status = ?", (status,)) {
            d["sequence"] = Campaign.sequence_from_json(d.pop("sequence_json"));
            d["prospect_ids"] = json.loads(d.pop("prospect_ids_json") or "[]");
            campaigns.append(Campaign(**d));
        }
        return campaigns;
    }

    async def update_campaign(campaign_id: str, **kwargs: any) {
        await self._update(
            "campaigns", campaign_id, _checked("campaign", kwargs, _CAMPAIGN_COLUMNS), False
        );
    }

    async def add_conversation(convo: Conversation) -> str {
        if not convo.id {
            convo.id = _new_id();
        }
        return await self._insert_row(
            convo,
            "conversations",
            "id prospect_id campaign_id channel thread_json intent stage status created_at updated_at",
            "",
            "INSERT",
        );
    }

    async def get_conversation(convo_id: str) -> Conversation | None {
        row = await self._select("SELECT * FROM conversations WHERE id = ?", (convo_id,), True);
        return _conversation_from_row(row) if row else None;
    }

    async def get_conversations_by_status(status: str) -> list[Conversation] {
        return [
            _conversation_from_row(r)
            for r in await self._select("SELECT * FROM conversations WHERE status = ?", (status,))
        ];
    }

    async def update_conversation(convo_id: str, **kwargs: any) {
        await self._update(
            "conversations", convo_id, _checked("conversation", kwargs, _CONVERSATION_COLUMNS), True
        );
    }

    async def log_action(action_type: str, agent: str, details: builtins.dict | None = None) {
        await self._exec(_LOG_ACTION, (_new_id(), action_type, agent, json.dumps(details or {})));
    }

    async def get_campaign_stats -> list[builtins.dict] {
        stats = await self._dicts("""SELECT c.id, c.name, c.status, c.prospect_ids_json,
                          COUNT(v.id) as reply_count,
                          SUM(CASE WHEN v.intent = 'interested' THEN 1 ELSE 0 END) as interested_count,
                          SUM(CASE WHEN v.intent = 'objection' THEN 1 ELSE 0 END) as objection_count,
                          SUM(CASE WHEN v.intent = 'not_interested' THEN 1 ELSE 0 END) as not_interested_count
                   FROM campaigns c
                   LEFT JOIN conversations v ON v.campaign_id = c.id
                   WHERE c.status IN ('active', 'completed')
                   GROUP BY c.id
                   ORDER BY c.created_at DESC""");
        for d in stats {
            for key in ("interested_count", "objection_count", "not_interested_count") {
                d[key] = d[key] or 0;
            }
            prospect_ids = json.loads(d.get("prospect_ids_json") or "[]");
            d["leads_count"] = len(prospect_ids);
            d["reply_rate"] = round(d["reply_count"] / len(prospect_ids) * 100, 1)
                if prospect_ids
                else 0;
        }
        return stats;
    }

    async def get_intent_distribution -> dict[str, int] {
        return await self._counts(
            "SELECT intent, COUNT(*) FROM conversations WHERE intent != '' GROUP BY intent"
        );
    }

    async def get_stage_distribution -> dict[str, int] {
        return await self._counts(
            "SELECT stage, COUNT(*) FROM conversations WHERE stage != '' GROUP BY stage"
        );
    }

    async def get_usage_today(provider: str = "claude") -> int {
        column = _USAGE_LOG_COLUMN[provider];
        return (
            await self._value(
                f"SELECT {column} FROM usage_log WHERE date = ?", (date.today().isoformat(),)
            )
        )
            or 0;
    }

    async def increment_usage(provider: str = "claude") {
        column = _USAGE_LOG_COLUMN[provider];
        await self._exec(
            f"INSERT INTO usage_log (id, date, {column}) VALUES (?, ?, 1) ON CONFLICT(date) DO UPDATE SET {column} = {column} + 1",
            (_new_id(), date.today().isoformat()),
        );
    }

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
    ) -> bool {
        if provider not in BRAIN_PROVIDERS {
            raise ValueError(f"unknown brain provider: {provider!r}");
        }
        counts = [
            int(n or 0)
            for n in (input_tokens, output_tokens, cache_read_tokens, cache_creation_tokens)
        ];
        return await self._changed("""INSERT OR IGNORE INTO usage_events
               (id, created_at, agent, task, session_id, request_key, model,
                input_tokens, output_tokens, cache_read_tokens,
                cache_creation_tokens, cost_usd, duration_ms, num_turns,
                is_error, source, provider)
               VALUES (?, COALESCE(?, CURRENT_TIMESTAMP), ?, ?, ?, ?, ?,
                       ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""", (_new_id(), created_at, agent, task, session_id, request_key, model, *counts, float(cost_usd or 0.0), int(duration_ms or 0), int(num_turns or 0), 1 if is_error else 0, source, provider));
    }

    async def _usage_grouped(group_expr: str, alias: str, days: int) -> list[builtins.dict] {
        rows = await self._select(
            f"SELECT {group_expr} AS {alias}, {_USAGE_SUM} FROM usage_events WHERE created_at >= datetime('now', ?) GROUP BY {alias} ORDER BY cost_usd DESC",
            (f"-{int(days)} days",),
        );
        return [_usage_row_to_dict(r) for r in rows];
    }

    async def usage_by_agent(days: int = 30) -> list[builtins.dict] {
        return await self._usage_grouped(
            "CASE WHEN agent = '' THEN 'other' ELSE agent END", "agent", days
        );
    }

    async def usage_by_task(days: int = 30) -> list[builtins.dict] {
        return await self._usage_grouped(
            "CASE WHEN task = '' THEN 'other' ELSE task END", "task", days
        );
    }

    async def usage_by_model(days: int = 30) -> list[builtins.dict] {
        return await self._usage_grouped(
            "CASE WHEN model = '' THEN 'unknown' ELSE model END", "model", days
        );
    }

    async def usage_by_provider(days: int = 30) -> list[builtins.dict] {
        return await self._usage_grouped("provider", "provider", days);
    }

    async def usage_totals -> builtins.dict {
        totals: builtins.dict = {};
        for (label, where) in (
            ("today", "date(created_at) = date('now')"),
            ("week", "created_at >= datetime('now', '-7 days')"),
            ("month", "created_at >= datetime('now', '-30 days')"),
        ) {
            row = await self._select(
                f"SELECT {_USAGE_SUM} FROM usage_events WHERE {where}", (), True
            );
            totals[label] = _usage_row_to_dict(row) if row else {};
        }
        return totals;
    }

    async def get_state_summary -> builtins.dict {
        prospect_counts = await self.count_prospects_by_status();
        today = date.today().isoformat();
        async with self._connect() as db {
            campaigns = await _fetch(
                db,
                "SELECT SUM(CASE WHEN status = 'draft' THEN 1 ELSE 0 END), SUM(CASE WHEN status = 'active' THEN 1 ELSE 0 END) FROM campaigns",
                (),
                True,
            );
            open_conversations = (
                await _fetch(
                    db, "SELECT COUNT(*) FROM conversations WHERE status = 'open'", (), True
                )
            )[0];
            auto_reply_handoffs = (
                await _fetch(
                    db,
                    "SELECT COUNT(*) FROM conversations WHERE status = 'needs_human' AND intent = 'ooo'",
                    (),
                    True,
                )
            )[0];
            usage_row = await _fetch(
                db, "SELECT claude_calls, codex_calls FROM usage_log WHERE date = ?", (today,), True
            );
        }
        usage_today = (usage_row[0] or 0) if usage_row else 0;
        return {
            "prospects": prospect_counts,
            "writable_prospects": await self.count_writable_prospects(),
            "recent_unusable_prospects": await self.count_recent_unusable_prospects(),
            "draft_campaigns": campaigns[0] or 0,
            "active_campaigns": campaigns[1] or 0,
            "sending_paused": bool(await self.get_setting("sending_paused")),
            "open_conversations": open_conversations,
            "auto_reply_handoffs": auto_reply_handoffs,
            "usage_today": usage_today,
            "usage_today_by_provider": {
                "claude": usage_today,
                "codex": (usage_row[1] or 0) if usage_row else 0,
            },
            "unprofiled": await self.count_companies_needing_profile(),
        };
    }
}
