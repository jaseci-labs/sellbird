import json;

import logging;

import os;

import re;

import from pathlib { Path }

glob logger = logging.getLogger("sellbird.humanize"),
     SKILL_PATH = Path(
         os.getenv(
             "SELLBIRD_HUMANIZER_SKILL",
             str(Path.home() / ".claude" / "skills" / "humanizer" / "SKILL.md"),
         ),
     ),
     MERGE_VAR = re.compile("\\{\\{\\s*\\w+\\s*\\}\\}"),
     MAX_GROWTH_WORDS = 2,
     META_PREFIXES = ("i can't", "i cannot", "as an ai", "sorry,", "here is", "here's");

def humanizer_enabled(config: any) -> bool {
    return bool(getattr(getattr(config, "writer", None), "humanizer", False));
}

def load_skill(path: Path | None = None) -> str {
    try {
        text = read_user_text(path or SKILL_PATH);
    } except OSError {
        return "";
    }
    if text.startswith("---") {
        end = text.find("\n---", 3);
        if end != -1 {
            text = text[end + 4:];
        }
    }
    return text.strip();
}

def _acceptable(original: dict[str, any], rewrite: any) -> bool {
    if not isinstance(rewrite, dict) {
        return False;
    }
    body = str(rewrite.get("body") or "").strip();
    subject = str(rewrite.get("subject") or "").strip();
    if not body
        or original.get("subject") and not subject
        or body.lower().startswith(META_PREFIXES)
    {
        return False;
    }
    (before, after) = (original.get("subject", "") + original["body"], subject + body);
    return sorted(MERGE_VAR.findall(before)) == sorted(MERGE_VAR.findall(after))
        and not ("—" in after and "—" not in before)
        and len(body.split()) <= len(original["body"].split()) + MAX_GROWTH_WORDS;
}

async def humanize(
    brain: any,
    drafts: list[dict[str, any]],
    agent: str,
    path: Path | None = None,
    enabled: bool = False,
) -> list[dict[str, any]] {
    if not enabled or not drafts {
        return drafts;
    }
    skill = load_skill(path);
    if not skill {
        return drafts;
    }

    out = [await _humanize_one(brain, skill, draft, agent) for draft in drafts];
    kept = len([a for (a, b) in zip(drafts, out) if a is b]);
    if kept {
        logger.info(f"Humanizer: kept {kept} of {len(drafts)} draft(s) unchanged after checks.");
    }
    return out;
}

async def _humanize_one(
    brain: any, skill: str, draft: dict[str, any], agent: str
) -> dict[str, any] {
    payload = {"subject": draft.get("subject", ""), "body": draft["body"]};
    prompt = format(skill, "")
        + "\n\n---\n\nApply the Humanizer instructions above to the cold-email draft below. It is\na short plain-text business email, so return email text only.\n\nHard limits on the rewrite, on top of the instructions above:\n- Keep every merge variable such as {{first_name}} or {{company}} exactly as written.\n- Add no fact, name, number or claim that is not already in the draft.\n- No em dashes, no bullets, no bold, no exclamation marks.\n- Do not make the email longer. Keep exactly one question.\n- The subject stays lowercase, 2-5 words. An empty subject stays empty.\n\nDraft:\n"
        + format(fence(json.dumps(payload, ensure_ascii=False, indent=2), "draft"), "")
        + "\n\n"
        + format(UNTRUSTED_RULE, "")
        + "\n\nReturn ONLY a JSON object: {\"subject\": \"...\", \"body\": \"...\"}";

    try {
        rewrite = await brain.think_json(
            prompt, session_id="sellbird-humanizer", agent=agent, task="humanize"
        );
    } except Exception as e {
        logger.warning(f"Humanizer pass failed, keeping draft: {e}");
        return draft;
    }
    if not _acceptable(draft, rewrite) {
        return draft;
    }
    return {
        **draft,
        "subject": str(rewrite.get("subject") or "").strip(),
        "body": str(rewrite["body"]).strip(),
    };
}
