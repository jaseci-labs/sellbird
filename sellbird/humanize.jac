"""Humanizer pass — rewrites drafts with the operator's installed Humanizer skill.

Sellbird's brain calls run with no tools and no skills (see brain.py), so a
Claude Code skill can't be invoked directly. Instead the skill's
instructions are read from the operator's skills folder and sent as a
second, editing-only call over drafts that are already written.

Off unless ``writer.humanizer: true`` is set in sellbird.yaml; the skill
being installed is not enough on its own.

Fails open: no skill file, a failed call, or a rewrite that breaks a rule
(lost merge variable, new em dash, much longer, meta-text) keeps the
original draft.
Every draft still passes the deterministic pre-send gate afterwards.
"""

import builtins;

import operator;

import json;

import logging;

import os;

import re;

import from pathlib { Path }

glob logger: any = logging.getLogger("sellbird.humanize");

glob SKILL_PATH: any = Path(
    os.getenv(
        "SELLBIRD_HUMANIZER_SKILL",
        `str(Path.home() / ".claude" / "skills" / "humanizer" / "SKILL.md"),
    ),
);

glob MERGE_VAR: any = re.compile("\\{\\{\\s*\\w+\\s*\\}\\}");

glob MAX_GROWTH_WORDS: any = 2;

glob META_PREFIXES: any = ("i can't", "i cannot", "as an ai", "sorry,", "here is", "here's");

"""True only when the operator turned the pass on in sellbird.yaml."""
def humanizer_enabled(config) -> builtins.bool;

"""The skill's instructions without its YAML frontmatter, or ""."""
def load_skill(path: Path | None = None) -> builtins.str;

def _acceptable(original: builtins.dict, rewrite) -> builtins.bool;

"""Return ``drafts`` ({"subject", "body"} dicts) rewritten by the skill.

    A no-op unless ``enabled`` (see ``humanizer_enabled``). One brain call
    per draft: personal drafts carry real names and companies, so a batched
    call that came back reordered could hand one prospect another's email.
    Any draft whose rewrite fails a check comes back unchanged, so the
    result always has the same length and order.
    """
async def humanize(
    brain,
    drafts: builtins.list[builtins.dict],
    agent: builtins.str,
    path: Path | None = None,
    enabled: builtins.bool = False,
) -> builtins.list[builtins.dict];

async def _humanize_one(
    brain, skill: builtins.str, draft: builtins.dict, agent: builtins.str
) -> builtins.dict;
