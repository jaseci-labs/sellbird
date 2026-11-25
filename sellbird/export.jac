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

def _row(r: dict[any, any]) -> dict[str, any] {
    return {c: r.get(_SOURCE.get(c, c), 0 if c == "score" else "") for c in CSV_COLUMNS};
}

async def collect_prospects(
    state: StateManager,
    email_statuses: list[str] | None = None,
    min_score: int = 0,
    statuses: list[str] | None = None,
    include_all: bool = False,
    config: any = None,
) -> list[dict[str, any]] {
    where: list[str] = [];
    params: list[any] = [];
    if not include_all {
        wanted = email_statuses if email_statuses is not None else DEFAULT_EMAIL_STATUSES;
        for (clause, values) in [
            ("status IS NOT ?", ["opted_out"]),
            ("email != '' AND email_status IN ({})", wanted),
            ("score >= ?", [min_score] if min_score > 0 else []),
            ("status IN ({})", statuses or []),
        ] {
            if values {
                where.append(clause.format(",".join("?" * len(values))));
                params.extend(values);
            }
        }
    }
    sql = "SELECT * FROM prospects" + (" WHERE " + " AND ".join(where) if where else "");
    async with storage.connect(state.db_path) as db {
        db.row_factory = aiosqlite.Row;
        async with db.execute(sql + " ORDER BY score DESC, created_at DESC", params) as cursor {
            rows = [dict(r) for r in await cursor.fetchall()];
        }
    }
    if not include_all and rows {
        blocked = _do_not_contact(config);
        rows = [r for r in rows if not do_not_contact_match(r.get("email") or "", blocked)];
    }
    return [_row(r) for r in rows];
}

def _do_not_contact(config: any) -> list[str] {
    if config is not None {
        return live_do_not_contact(config);
    }
    try {
        return do_not_contact_from_file();
    } except (ConfigFileNotFoundError, FileNotFoundError) {
        return [];
    } except Exception as e {
        raise ConfigError(
            f"compliance.do_not_contact couldn't be read ({e}). Fix it before exporting."
        ) from e;
    }
}

def to_csv(rows: list[dict[str, any]]) -> str {
    buf = io.StringIO();
    writer = csv.DictWriter(buf, fieldnames=CSV_COLUMNS, extrasaction="ignore");
    writer.writeheader();
    writer.writerows(rows);
    return buf.getvalue();
}

async def export_prospects_csv(
    state: StateManager, out_path: str | None = None, **filters: any
) -> tuple[int, str] {
    rows = await collect_prospects(state, **filters);
    text = to_csv(rows);
    if out_path {
        with open(out_path, "w", newline="", encoding="utf-8") as f {
            f.write(text);
        }
        logger.info(f"Exported {len(rows)} prospects to {out_path}");
    }
    return (len(rows), text);
}
