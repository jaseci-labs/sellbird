"""Design the first-email offer with Sellbird (the dashboard's "Your offer").

Every first email ends by offering ``product.offer.entry``: something free and
useful the sender can really deliver. The offer is the sender's call, so
Sellbird helps design it instead of picking it alone:

- ``suggest_offers`` asks the brain for a few offers that fit the product,
  each paired with the finding about a prospect that makes it the obvious
  next step.
- ``preview_email`` writes one real first email with a draft offer, for a real
  prospect, without saving or sending anything.
- ``save_offer`` writes the chosen offer to the config file, keeping a backup.
"""

import builtins;

import copy;

import from typing { Any }

import logging;

import from pathlib { Path }

import yaml;

glob logger: any;

glob MAX_OFFER_CHARS: any;

glob SUGGESTIONS: any;

glob SUGGEST_PROMPT: any;

glob PROPOSED_KEY: any;

glob EDITABLE: any;

glob MAX_TEXT: any;

glob MAX_ITEMS: any;

with entry {
    logger = logging.getLogger("sellbird.offer");

    MAX_OFFER_CHARS = 300;
    SUGGESTIONS = 4;

    SUGGEST_PROMPT = "You help a business design the offer at the end of its cold emails.\n\nThe business:\n{product}\n\nWho it emails: {icp}\n\nA first email names one finding about the prospect (where they rank on Google,\nwhat their website lacks, a role they're hiring for, their reviews), says what\nthat costs them, and ends by offering one free, useful thing as the next step to\nfix it. Suggest {n} offers for this business. Each must be:\n- tied to a finding Sellbird can really see about a prospect (search rank, the\n  website, job posts, reviews, tools on the site, funding news);\n- specific and valuable on its own, so saying yes costs nothing (\"a written plan\n  for getting you onto page one\", \"a mockup of your homepage with online\n  booking\", \"a two-week trial answering your after-hours calls\");\n- something this business can deliver quickly after a yes;\n- never a discount, a generic call or a demo.\n\n{rule}\n\nReturn ONLY a JSON array of {n} objects:\n[{{\"offer\": \"the offer in a few words, as it would be written in the email\",\n   \"finding\": \"the kind of finding it pairs with\",\n   \"why\": \"one sentence on why a prospect would say yes\"}}]";
}

"""What the dashboard shows: the offer, the ideas, and the product it's for."""
def offer_view(config) -> builtins.dict;

def _product_text(config) -> builtins.str;

def _icp_text(config) -> builtins.str;

"""A few offers that fit the product, each with its finding and why."""
async def suggest_offers(brain, config) -> builtins.list[builtins.dict];

"""A real prospect with something to write about, or None.

    Prefers one whose company has signals or a description, so the preview
    shows a finding, not a guess."""
async def preview_prospect(state) -> any;

"""One first email written with ``entry`` as the offer. Nothing is saved."""
async def preview_email(brain, state, config, `entry: builtins.str) -> builtins.dict;

"""Write ``entry`` (and the ideas, when given) to product.offer in the
    config file. Keeps a .bak of the file as it was."""
def save_offer(
    config_file: Path, `entry: builtins.str, ideas: builtins.list[builtins.str] | None = None
) -> Path;

with entry {
    PROPOSED_KEY = "offer_proposed";
    EDITABLE = {
        "product": {
            "name": str,
            "description": str,
            "pricing": str,
            "key_benefits": list[any],
            "objection_responses": dict[any, any],
        },
        "persona": {"name": str, "role": str, "tone": str},
        "icp": {
            "industries": list[any],
            "titles": list[any],
            "company_size": str,
            "geography": list[any],
        },
        "offer": {"entry": str},
    };
    MAX_TEXT = 2000;
    MAX_ITEMS = 30;
}

def _skill_text(`root: Path, name: builtins.str) -> builtins.str;

"""Your company as the tab shows it: what you sell, to whom, the offer,
    the sender, objections, and what training wrote about the product."""
def company_view(config, `root: Path, proposed: builtins.dict | None = None) -> builtins.dict;

def _clean(kind, value) -> any;

"""Write the edited ``fields`` of one section to the config file (with a
    .bak of it as it was). Only EDITABLE fields are accepted. Returns what
    was saved."""
def save_company(config_file: Path, section: builtins.str, fields: builtins.dict) -> builtins.dict;
