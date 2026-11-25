"""What Sellbird knows about a prospect's company as a startup.

Three profile signals mark one, each read off the company's own site:
YC_BACKED, ACCELERATOR, and a FUNDING_ROUND dated within the last 18
months. The writer and the reply handler use the founder playbook
(skills/selling_to_startups.md) for those, and these facts go into the
writer's prompt as they are. An old or undated raise alone doesn't make a
startup (a 2013 Series A, or a law firm's misread "$100M"), and "just
raised" is only an angle while it's true.
"""

import builtins;

import operator;

import re;

import from datetime { date }

glob FUNDING_RECENT_DAYS: any = 548;

glob _DATE_RE: any;

with entry {
    _DATE_RE = re.compile("^(\\d{4})(?:-(\\d{2}))?(?:-(\\d{2}))?$");
}

"""The FUNDING_ROUND value as stored: "Series A · $12M · 2025-03"."""
def funding_text(found: builtins.dict) -> builtins.str;

"""funding_text, read back into its parts (any may be "")."""
def parse_funding(text: builtins.str) -> builtins.dict;

"""The earliest day a stated date could mean: "2025" is 1 January, so an
    imprecise date never makes a raise look newer than it is."""
def _as_date(when: builtins.str) -> date | None;

""""recent", "old" (over ~18 months) or "unknown" (no date found)."""
def funding_recency(when: builtins.str, today: date | None = None) -> builtins.str;

def _funding_fact(found: builtins.dict, today: date | None) -> builtins.str;

async def _read(state, name: builtins.str, company_id: builtins.str) -> any;

"""Fact lines for the writer's prompt when the company is a startup
    (YC, another accelerator, or a raise it announced in the last 18
    months), else None. A failed read is just "not known to be one", never
    a reason not to write."""
async def startup_facts(
    state, company_id: builtins.str, today: date | None = None
) -> builtins.list[builtins.str] | None;
