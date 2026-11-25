import logging;
import os;
import re;

glob logger = logging.getLogger("sellbird.handoff"),
     CALL_TIMEOUT = 60.0,
     MAX_RESULT_CHARS = 2000,
     _FIELD_RE = re.compile("\\{(\\w+)\\}"),
     FIELDS = ("first_name", "last_name", "email", "title", "company", "website", "reply", "offer");

def configured(config: any) -> bool {
    h = getattr(config, "handoff", None);
    return bool(h and h.tool and (h.mcp_url or h.mcp_command));
}

def _fill_one(v: any, values: any) -> any {
    if isinstance(v, str) {
        return _FIELD_RE.sub(lambda (m: any) -> str { str(values.get(m.group(1), "")) }, v).strip();
    }
    if isinstance(v, dict) {
        return {k: _fill_one(x, values) for (k, x) in v.items()};
    }
    return [_fill_one(x, values) for x in v] if isinstance(v, list) else v;
}

def fill(arguments: dict[str, any], values: any) -> dict[str, any] {
    return {k: _fill_one(v, values) for (k, v) in (arguments or {}).items()};
}

def values_for(prospect: any, company: any, reply_text: str, offer: str) -> any {
    website = ""
        if company is None
        else getattr(company, "website", "") or getattr(company, "domain", "") or "";
    return {f: getattr(prospect, f) or "" for f in FIELDS[:5]} | {
        "website": website,
        "reply": (reply_text or "")[:1500],
        "offer": offer or "",
    };
}

def _result_text(result: any) -> str {
    parts = [
        t
        for t in [getattr(i, "text", None) for i in getattr(result, "content", None) or []]
        if t
    ];
    structured = getattr(result, "structured_content", None);
    if not parts and structured {
        parts.append(str(structured));
    }
    return "\n".join(parts).strip()[:MAX_RESULT_CHARS];
}

async def _session_call(
    client: any, read: any, write: any, h: any, arguments: dict[str, any]
) -> any {
    async with client(read, write) as session {
        await session.initialize();
        return await session.call_tool(h.tool, arguments, read_timeout_seconds=CALL_TIMEOUT);
    }
}

async def call_tool(
    h: any, arguments: dict[str, any], env: any = None
) -> dict[str, any] {
    import from mcp { ClientSession }
    env = env if env is not None else os.environ;
    try {
        if h.mcp_url {
            import from mcp.client.streamable_http {
                create_mcp_http_client,
                streamable_http_client,
            }
            token = (env.get(h.token_env) or "").strip() if h.token_env else "";
            if h.token_env and not token {
                return {"ok": False, "error": f"{h.token_env} isn't set in .env"};
            }
            headers = {"Authorization": f"Bearer {token}"} if token else {};
            async with create_mcp_http_client(headers=headers) as http {
                async with streamable_http_client(h.mcp_url, http_client=http) as (read, write) {
                    result = await _session_call(ClientSession, read, write, h, arguments);
                }
            }
        } else {
            import from mcp.client.stdio { StdioServerParameters, stdio_client }
            params = StdioServerParameters(command=h.mcp_command[0], args=list(h.mcp_command[1:]));
            async with stdio_client(params) as (read, write) {
                result = await _session_call(ClientSession, read, write, h, arguments);
            }
        }
    } except Exception as e {
        logger.warning(f"Handoff: calling {h.tool} failed: {e}");
        return {"ok": False, "error": f"couldn't reach the handoff server ({type(e).__name__})"};
    }
    text = _result_text(result);
    if getattr(result, "is_error", False) {
        return {"ok": False, "error": text or f"{h.tool} returned an error"};
    }
    return {"ok": True, "result": text};
}

async def hand_off(config: any, prospect: any, company: any, reply_text: str) -> dict[str, any]
    | None {
    if not configured(config) {
        return None;
    }
    h = config.handoff;
    offer = getattr(getattr(config.product, "offer", None), "entry", "") or "";
    arguments = fill(h.arguments, values_for(prospect, company, reply_text, offer));
    return {**await call_tool(h, arguments), "tool": h.tool, "arguments": arguments};
}
