"""Company fit: one 0-100 number per company, with the reasons behind it.

Worked out on read from what Sellbird already holds (the company's industry,
its contacts and their email status, and its observations), weighed against
the ICP in the config. Nothing is stored, so the score follows the config
the moment it changes.

    sector match      20  the company's industry is one of icp.industries
    decision maker    30  a contact whose title matches icp.titles
                          (15 for another named person, 5 for a general inbox)
    reachable         25  best email: verified 25, risky 12, guess 5;
                          a contact form alone is 5
    buying signal     25  an open role matching icp.hiring_signals
                          (5 for a careers page with no matching role)

A company on the do-not-contact list scores 0.
"""

import operator;

import from __future__ { annotations }

import re;

glob SECTOR: any;

glob DECISION_MAKER: any;

glob REACHABLE: any;

glob BUYING: any;

glob EMAIL_POINTS: any;

glob DEAD_STATUSES: any;

with entry {
    (SECTOR, DECISION_MAKER, REACHABLE, BUYING) = (20, 30, 25, 25);
    EMAIL_POINTS = {"verified": 25, "risky": 12, "guess": 5};
    DEAD_STATUSES = {"lost", "opted_out"};
}

def _hiring_terms(icp) -> list[str];

"""The first hiring term found in ``text`` as whole words, or ""."""
def _role_matches(text: str, terms: list[str]) -> str;

"""HIRING_ROLE rows still current: those after the latest "board lists
    nothing relevant" row (num 0, no text), which closes earlier roles."""
def current_roles(observations: list[dict]) -> list[dict];

"""(score, reasons) for one company. ``prospects`` and ``observations``
    are that company's rows, as dicts. ``dnc`` is the do-not-contact list
    (default: the config's)."""
def company_fit(
    company: dict,
    prospects: list[dict],
    observations: list[dict],
    config,
    dnc: list[str] | None = None,
) -> tuple[int, list[str]];
