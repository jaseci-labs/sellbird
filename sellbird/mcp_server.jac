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
    def init;
}

def base_url(host: str, port: int) -> str;

class CoreClient {
    has data_dir: any = None,
        _transport: any = None;

    def init(data_dir: Path, transport: httpx.AsyncBaseTransport | None = None);

    def _client(base: str, timeout: float = 15.0) -> httpx.AsyncClient;

    async def _connection -> tuple[str, str];

    async def _request(
        method: str, path: str, *, json: any = None, timeout: float = 15.0
    ) -> builtins.dict;

    async def get(path: str) -> builtins.dict;

    async def post(path: str, body: any = None, timeout: float = 15.0) -> builtins.dict;
}

def default_client -> CoreClient;

class WorkspaceNotFound(Exception) {
    def init(message: str);
}

@dataclass(frozen=True)
class WorkspaceArg {
    has resolve: Callable[[str | None], Awaitable[dict]],
        current: ContextVar;
}

def _with_workspace(fn: any, workspace_arg: WorkspaceArg) -> any;

async def _workspace_call(
    fn: any, workspace_arg: WorkspaceArg, *args: any, workspace: str | None = None, **kwargs: any
) -> any;

def _add_workspace_arg(server: MCPServer, workspace_arg: WorkspaceArg);

obj _Tools {
    has client_factory: any,
        unavailable_message: str | None;

    async def guarded(call: any) -> any;
    async def _read(path: str) -> builtins.dict;
    async def _post(path: str, body: any = None, timeout: float = 15.0) -> builtins.dict;
    async def company_contacts(company_id: str) -> builtins.dict;
    async def company_profile(company_id: str) -> builtins.dict;
    async def discover_estimate(
        provider: str,
        cities: list[str] | None = None,
        depth: int = 30,
        limit: int = 100,
        preset: str = "",
    ) -> builtins.dict;
    async def sending_status -> builtins.dict;
    async def sending_pause -> builtins.dict;
    async def offer_suggest -> builtins.dict;
    async def offer_preview(`entry: str) -> builtins.dict;
    async def offer_propose(`entry: str, why: str = "") -> builtins.dict;
    async def inbox_pause(inbox_id: str, reason: str = "") -> builtins.dict;
}

async def _live_and_mode(c: CoreClient) -> builtins.dict;

async def _pause(c: CoreClient) -> builtins.dict;

def build_server(
    client_factory: Callable[[], CoreClient] = default_client,
    *,
    workspace_arg: WorkspaceArg | None = None,
    unavailable_message: str | None = None,
    instructions: str = INSTRUCTIONS,
) -> MCPServer;

def run_stdio;
