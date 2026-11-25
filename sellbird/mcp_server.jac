import builtins;
import functools;
import inspect;
import logging;
import re;
import sys;
import from contextvars { ContextVar }
import from dataclasses { dataclass }
import from pathlib { Path }
import from typing { Annotated, Awaitable, Callable, Optional }
import from urllib.parse { quote }
import httpx;
import from mcp.server.mcpserver { MCPServer }
import from pydantic { Field }

glob logger = logging.getLogger("sellbird.mcp_server"),
     AGENT_TOKEN_NAME = "agent-token",
     NOT_RUNNING = "Sellbird's dashboard isn't running. Ask the user to start it with: sellbird dashboard",
     INSTRUCTIONS = """Sellbird is the user's outreach engine: it finds companies and the people who decide,
writes cold email, sends it from the user's own inboxes and handles replies.

You can read everything (today's summary, campaigns, prospects, companies, conversations,
the Outbox, signals, inboxes, usage, setup, the company profile), estimate what a
discovery run would cost, and pause sending or one inbox. You also help the user design
the offer every first email ends with (offer_suggest, offer_preview, offer_propose): they
confirm it in the dashboard. You cannot approve or send email, resume sending, confirm
signals, run discovery, change settings or keys, or delete anything: those are the
user's, in the dashboard (`sellbird dashboard`). When something needs them, say which tab
to open (Today, Your company, Outbox, Inboxes, Signals, Discover, Settings) and what to
click. Never ask the user for
their dashboard token, and never read data/dashboard-token.
""",
     MODEL_CALL_TIMEOUT = 180.0,
     WORKSPACE_PARAM_DOC = "Workspace id or name. Your default workspace when left out.",
     RESULT_WORKSPACE_KEY = "sellbird_workspace",
     _PAUSED = "Sending is paused. Only the user can resume it, in the dashboard.",
     _TOOLS = """
today /api/today What needs the user now, and the pipeline at a glance. Start here.
setup_status /api/setup-status Which setup steps are done and what's still missing, from install to sending.
stats /api/stats Pipeline counts: companies, prospects, campaigns, conversations, sends.
activity /api/activity What Sellbird did recently, newest first.
usage /api/usage How much of the Claude or Codex subscription Sellbird has used, and its own calls.
campaigns_list /api/campaigns Every campaign with its sequence and status.
prospects_list /api/prospects The newest prospects (up to 200) with their status and email verification.
companies_list /api/companies The companies Sellbird has found, with their fit.
company_contacts - The people Sellbird found at one company.
company_profile - What Sellbird read off one company's website: its signals and profile.
conversations_list /api/conversations Reply threads, with their stage and whether they need the user.
outbox_list /api/outbox Email waiting for approval, approved and scheduled, and recently sent or failed.
signals_list /api/signals The signals Sellbird can collect, which the user confirmed, and what each costs.
discover_providers /api/discover/providers The discovery sources, what each costs and which keys each needs.
discover_estimate - The searches a discovery run would make and what they'd cost. Runs nothing:
    only the user starts a run, on the Discover tab. `provider` is a key from
    discover_providers; cities default to the ICP's.
sending_status - Whether sending is paused and why, and whether email waits for approval.
sending_pause - Pause all sending now. Safe to repeat. Only the user can resume, in the dashboard.
company /api/company Everything Sellbird writes from: the product, who it sells to, the
    first-email offer (and any offer you proposed), the sender, objections,
    and what training wrote about the product.
offer_suggest - Ask Sellbird for 4 first-email offers that fit the product, each with
    the finding it pairs with and why a prospect would say yes. Saves nothing.
    Use them to start the offer conversation with the user, not as the answer.
offer_preview - Write one real first email with `entry` as the offer, for one of the
    user's prospects, so they can judge the offer in a real email. Saves and
    sends nothing.
offer_propose - Propose the offer the user agreed on, in the words they agreed to. It
    waits on dashboard → Your company until they click Use this offer: only
    the user changes what every first email offers.
offers_accepted /api/offers/accepted People who said yes to the user's first-email offer, newest first, with
    their details and what the configured handoff answered (if any). Use it to
    deliver the offer with the user's other tools, such as starting the work in
    the system that makes it.
inboxes_list /api/inboxes Every sending inbox: the main mailbox and the extra ones the user connected,
    whether each is sending, paused or not connected, and today's cold sends
    against its cap.
inbox_pause - Pause one extra inbox (an id from inboxes_list). Its unsent first emails
    move to the other inboxes. Only the user can resume it, in the dashboard's
    Inboxes tab. To stop every inbox, use sending_pause.
""";

class CoreUnavailable(Exception) {
    def init {
        super.init(NOT_RUNNING);
    }
}

def base_url(host: str, port: int) -> str {
    if ":" in host and not host.startswith("[") {
        host = f"[{host}]";
    }
    return f"http://{host}:{port}/";
}

class CoreClient {
    has data_dir: any = None,
        _transport: any = None;

    def init(data_dir: Path, transport: httpx.AsyncBaseTransport | None = None) {
        self.data_dir = Path(data_dir);
        self._transport = transport;
    }

    def _client(base: str, timeout: float = 15.0) -> httpx.AsyncClient {
        extra = {"transport": self._transport} if self._transport is not None else {};
        return httpx.AsyncClient(base_url=base, timeout=timeout, **extra);
    }

    async def _connection -> tuple[str, str] {
        info = dashboard_instance.read(self.data_dir);
        if info is None {
            raise CoreUnavailable();
        }
        base = base_url(info.host, info.port);
        try {
            async with self._client(base) as http {
                answer = await http.get("/api/instance");
            }
            same = answer.status_code == 200 and answer.json().get("instance") == info.instance;
        } except (httpx.TransportError, httpx.InvalidURL, OSError, ValueError, AttributeError) {
            raise CoreUnavailable() from None;
        }
        if not same {
            raise CoreUnavailable();
        }
        try {
            return (base, load_or_create_token(self.data_dir / AGENT_TOKEN_NAME));
        } except TokenError {
            raise CoreUnavailable() from None;
        }
    }

    async def _request(
        method: str, path: str, *, json: any = None, timeout: float = 15.0
    ) -> builtins.dict {
        (base, token) = await self._connection();
        try {
            async with self._client(base, timeout) as http {
                response = await http.request(
                    method, path, json=json, headers={"Authorization": f"Bearer {token}"}
                );
            }
        } except (httpx.TransportError, httpx.InvalidURL, OSError) {
            raise CoreUnavailable() from None;
        }
        try {
            data = response.json();
        } except ValueError {
            data = {};
        }
        is_dict = isinstance(data, dict);
        if response.status_code == 409 and is_dict and data.get("error") == "not_on_hosted" {
            raise NotOnHosted(data.get("feature", ""));
        }
        if response.status_code >= 400 {
            return {"ok": False, "status": response.status_code, **(data if is_dict else {})};
        }
        return data if is_dict else {"result": data};
    }

    async def get(path: str) -> builtins.dict {
        return await self._request("GET", path);
    }

    async def post(path: str, body: any = None, timeout: float = 15.0) -> builtins.dict {
        return await self._request("POST", path, json=body, timeout=timeout);
    }
}

def default_client -> CoreClient {
    return CoreClient(PROJECT_ROOT / "data");
}

class WorkspaceNotFound(Exception) {
    def init(message: str) {
        super.init(message);
        self.message = message;
    }
}

@dataclass(frozen=True)
class WorkspaceArg {
    has resolve: Callable[[str | None], Awaitable[dict]],
        current: ContextVar;
}

def _with_workspace(fn: any, workspace_arg: WorkspaceArg) -> any {
    sig = inspect.signature(fn, eval_str=True);
    param = inspect.Parameter(
        "workspace",
        inspect.Parameter.KEYWORD_ONLY,
        default=None,
        annotation=Annotated[Optional[str], Field(description=WORKSPACE_PARAM_DOC)],
    );
    wrapper = functools.update_wrapper(functools.partial(_workspace_call, fn, workspace_arg), fn);
    wrapper.__signature__ = sig.replace(parameters=[*sig.parameters.values(), param]);
    annotations: builtins.dict = {p.name: p.annotation for p in sig.parameters.values()};
    annotations["workspace"] = param.annotation;
    annotations["return"] = sig.return_annotation;
    wrapper.__annotations__ = annotations;
    return wrapper;
}

async def _workspace_call(
    fn: any, workspace_arg: WorkspaceArg, *args: any, workspace: str | None = None, **kwargs: any
) -> any {
    try {
        resolved = await workspace_arg.resolve(workspace);
    } except WorkspaceNotFound as e {
        return {"ok": False, "message": e.message};
    }
    token = workspace_arg.current.set(resolved);
    try {
        result = await fn(*args, **kwargs);
    } finally {
        workspace_arg.current.reset(token);
    }
    return {**result, RESULT_WORKSPACE_KEY: resolved} if isinstance(result, dict) else result;
}

def _add_workspace_arg(server: MCPServer, workspace_arg: WorkspaceArg) {
    register_tool = server.tool;
    def tool(*args: any, **kwargs: any) -> any {
        register = register_tool(*args, **kwargs);
        return lambda (fn: any) -> any { register(_with_workspace(fn, workspace_arg)) };
    }
    server.tool = tool;
}

obj _Tools {
    has client_factory: any,
        unavailable_message: str | None;

    async def guarded(call: any) -> any {
        try {
            return await call(self.client_factory());
        } except CoreUnavailable as e {
            return {"ok": False, "message": self.unavailable_message or str(e)};
        } except NotOnHosted as e {
            return {"ok": False, "message": e.payload["message"]};
        } except Exception {
            logger.exception("Sellbird MCP tool failed");
            return {"ok": False, "message": self.unavailable_message or NOT_RUNNING};
        }
    }

    async def _read(path: str) -> builtins.dict {
        return await self.guarded(lambda (c: any) -> any { c.get(path) });
    }

    async def _post(path: str, body: any = None, timeout: float = 15.0) -> builtins.dict {
        return await self.guarded(lambda (c: any) -> any { c.post(path, body, timeout=timeout) });
    }

    async def company_contacts(company_id: str) -> builtins.dict {
        return await self._read(f"/api/companies/{quote(company_id, safe='')}/contacts");
    }

    async def company_profile(company_id: str) -> builtins.dict {
        return await self._read(f"/api/companies/{quote(company_id, safe='')}/profile");
    }

    async def discover_estimate(
        provider: str,
        cities: list[str] | None = None,
        depth: int = 30,
        limit: int = 100,
        preset: str = "",
    ) -> builtins.dict {
        body = dict(provider=provider, cities=cities or [], depth=depth, limit=limit);
        return await self._post("/api/discover/estimate", body | {"preset": preset});
    }

    async def sending_status -> builtins.dict {
        return await self.guarded(_live_and_mode);
    }

    async def sending_pause -> builtins.dict {
        return await self.guarded(_pause);
    }

    async def offer_suggest -> builtins.dict {
        return await self._post("/api/offer/suggest", timeout=MODEL_CALL_TIMEOUT);
    }

    async def offer_preview(`entry: str) -> builtins.dict {
        body = {"entry": `entry};
        return await self._post("/api/offer/preview", body, timeout=MODEL_CALL_TIMEOUT);
    }

    async def offer_propose(`entry: str, why: str = "") -> builtins.dict {
        return await self._post("/api/offer/propose", {"entry": `entry, "why": why});
    }

    async def inbox_pause(inbox_id: str, reason: str = "") -> builtins.dict {
        path = f"/api/inboxes/{quote(inbox_id, safe='')}/pause";
        return await self._post(path, {"reason": reason});
    }
}

async def _live_and_mode(c: CoreClient) -> builtins.dict {
    live = await c.get("/api/live-status");
    mode = await c.get("/api/sending-mode");
    return live if live.get("ok") is False else {"live": live, "mode": mode};
}

async def _pause(c: CoreClient) -> builtins.dict {
    result = await c.post("/api/sending/pause");
    return result if result.get("ok") is False else {**result, "paused": True, "message": _PAUSED};
}

def build_server(
    client_factory: Callable[[], CoreClient] = default_client,
    *,
    workspace_arg: WorkspaceArg | None = None,
    unavailable_message: str | None = None,
    instructions: str = INSTRUCTIONS,
) -> MCPServer {
    server = MCPServer("sellbird", instructions=instructions);
    if workspace_arg is not None {
        _add_workspace_arg(server, workspace_arg);
    }
    tools = _Tools(client_factory, unavailable_message);
    for spec in re.split(r"\n(?=\S)", _TOOLS.strip()) {
        (name, path, text) = spec.split(" ", 2);
        (fn, args) = (getattr(tools, name), ()) if path == "-" else (tools._read, (path,));
        tool = functools.partial(fn, *args);
        tool.__name__ = name;
        server.tool(description=re.sub(r"\n\s+", "\n", text))(tool);
    }
    for register in extensions.registry().mcp_tools.values() {
        register(server, client_factory, tools.guarded);
    }
    return server;
}

def run_stdio {
    logging.basicConfig(level=logging.WARNING, stream=sys.stderr, force=True);
    build_server().run("stdio");
}
