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

glob logger: any = logging.getLogger("sellbird.handoff");

glob CALL_TIMEOUT: any = 60.0;

glob MAX_RESULT_CHARS: any = 2000;

glob _FIELD_RE: any = re.compile("\\{(\\w+)\\}");

glob FIELDS: any = (
    "first_name",
    "last_name",
    "email",
    "title",
    "company",
    "website",
    "reply",
    "offer",
);

def configured(config) -> builtins.bool {
    h: any = getattr(config, "handoff", None);
    return `bool(h and h.tool and (h.mcp_url or h.mcp_command));
}

"""``arguments`` with each {field} replaced; unknown fields become ""."""
def fill(arguments: builtins.dict, values: builtins.dict) -> builtins.dict {
    def one(v) -> any {
        if isinstance(v, `str) {
            return _FIELD_RE.sub(lambda (m) -> any { `str(values.get(m.group(1), "")) }, v).strip();
        }
        if isinstance(v, `dict) {
            return {k: one(x) for (k, x) in v.items()};
        }
        if isinstance(v, `list) {
            return [one(x) for x in v];
        }
        return v;
    }
    return {k: one(v) for (k, v) in (arguments or {}).items()};
}

def values_for(prospect, company, reply_text: builtins.str, offer: builtins.str) -> builtins.dict {
    website: any = "";
    if company is not None {
        website = getattr(company, "website", "") or getattr(company, "domain", "") or "";
    }
    return {
        "first_name": prospect.first_name or "",
        "last_name": prospect.last_name or "",
        "email": prospect.email or "",
        "title": prospect.title or "",
        "company": prospect.company or "",
        "website": website,
        "reply": (reply_text or "")[:1500],
        "offer": offer or "",
    };
}

def _result_text(result) -> builtins.str {
    parts: any = [];
    for item in getattr(result, "content", None) or [] {
        text: any = getattr(item, "text", None);
        if text {
            parts.append(text);
        }
    }
    structured: any = getattr(result, "structured_content", None);
    if not parts and structured {
        parts.append(`str(structured));
    }
    return "\n".join(parts).strip()[:MAX_RESULT_CHARS];
}

"""Call ``h.tool`` with ``arguments`` on the configured server.

    Returns {"ok": True, "result": text} or {"ok": False, "error": why}.
    Never raises: a handoff that fails leaves the person on Conversations
    as "said yes to your offer", for you to act on."""
async def call_tool(
    h, arguments: builtins.dict, env: builtins.dict | None = None
) -> builtins.dict {
    import from mcp { ClientSession }
    env = env if env is not None else os.environ;
    try {
        if h.mcp_url {
            import from mcp.client.streamable_http {
                create_mcp_http_client,
                streamable_http_client,
            }
            headers: any = {};
            token: any = (env.get(h.token_env) or "").strip() if h.token_env else "";
            if h.token_env and not token {
                return {"ok": False, "error": f"{h.token_env} isn't set in .env"};
            }
            if token {
                headers["Authorization"] = f"Bearer {token}";
            }
            http: any;
            async with create_mcp_http_client(headers=headers) as http {
                read: any;
                write: any;
                async with streamable_http_client(h.mcp_url, http_client=http) as (read, write) {
                    session: any;
                    async with ClientSession(read, write) as session {
                        await session.initialize();
                        result: any = await session.call_tool(
                            h.tool, arguments, read_timeout_seconds=CALL_TIMEOUT
                        );
                    }
                }
            }
        } else {
            import from mcp.client.stdio { StdioServerParameters, stdio_client }
            params: any = StdioServerParameters(
                command=h.mcp_command[0], args=`list(h.mcp_command[1:])
            );
            async with stdio_client(params) as (read, write) {
                async with ClientSession(read, write) as session {
                    await session.initialize();
                    result = await session.call_tool(
                        h.tool, arguments, read_timeout_seconds=CALL_TIMEOUT
                    );
                }
            }
        }
    } except Exception as e {
        logger.warning(f"Handoff: calling {h.tool} failed: {e}");
        return {"ok": False, "error": f"couldn't reach the handoff server ({`type(e).__name__})"};
    }
    text: any = _result_text(result);
    if getattr(result, "is_error", False) {
        return {"ok": False, "error": text or f"{h.tool} returned an error"};
    }
    return {"ok": True, "result": text};
}

"""Hand an accepted offer to the configured system, or None when no
    handoff is configured."""
async def hand_off(config, prospect, company, reply_text: builtins.str) -> builtins.dict | None {
    if not configured(config) {
        return None;
    }
    h: any = config.handoff;
    offer: any = getattr(getattr(config.product, "offer", None), "entry", "") or "";
    arguments: any = fill(h.arguments, values_for(prospect, company, reply_text, offer));
    outcome: any = await call_tool(h, arguments);
    return {**outcome, "tool": h.tool, "arguments": arguments};
}
