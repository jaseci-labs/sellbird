"""When someone says yes to your offer, hand them to the system that delivers it.

Sellbird finds people, writes the first email and reads the replies. What
happens after "yes, send it" belongs to whatever you sell: a site builder
starts a build, an agency books an audit, a CRM gets a new deal. So when a
reply accepts the offer (handler intent ``accepted_offer``), Sellbird calls
one tool on another system's MCP server, configured in ``handoff``::

    handoff:
      mcp_url: https://example.com/mcp      # an MCP server over HTTP, or
      mcp_command: ["npx", "-y", "some-mcp"] # one Sellbird starts locally
      token_env: EXAMPLE_MCP_TOKEN           # .env variable with its bearer token
      tool: create_site
      arguments:
        company: "{company}"
        website: "{website}"
        email: "{email}"
        contact: "{first_name} {last_name}"
        note: "{reply}"

Argument values may use {first_name} {last_name} {email} {title} {company}
{website} {reply} {offer}. Whatever the tool answers is kept with the
conversation, and the reply Sellbird drafts (for your approval) can use it,
such as the link to what was made.

With no handoff configured, nothing is called: the person shows up as
"said yes to your offer" on Conversations and in the agent's
``offers_accepted`` tool, for you or your coding agent to act on.
"""

import builtins;

import logging;

import os;

import re;

glob logger: any;

glob CALL_TIMEOUT: any;

glob MAX_RESULT_CHARS: any;

glob _FIELD_RE: any;

glob FIELDS: any;

with entry {
    logger = logging.getLogger("sellbird.handoff");

    CALL_TIMEOUT = 60.0;
    MAX_RESULT_CHARS = 2000;
    _FIELD_RE = re.compile("\\{(\\w+)\\}");
    FIELDS = ("first_name", "last_name", "email", "title", "company", "website", "reply", "offer");
}

def configured(config) -> builtins.bool;

"""``arguments`` with each {field} replaced; unknown fields become ""."""
def fill(arguments: builtins.dict, values: builtins.dict) -> builtins.dict;

def values_for(prospect, company, reply_text: builtins.str, offer: builtins.str) -> builtins.dict;

def _result_text(result) -> builtins.str;

"""Call ``h.tool`` with ``arguments`` on the configured server.

    Returns {"ok": True, "result": text} or {"ok": False, "error": why}.
    Never raises: a handoff that fails leaves the person on Conversations
    as "said yes to your offer", for you to act on."""
async def call_tool(h, arguments: builtins.dict, env: builtins.dict | None = None) -> builtins.dict;

"""Hand an accepted offer to the configured system, or None when no
    handoff is configured."""
async def hand_off(config, prospect, company, reply_text: builtins.str) -> builtins.dict | None;
