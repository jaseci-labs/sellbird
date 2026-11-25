"""Extensions: code outside this package that adds to Sellbird without patching it.

An extension is a Python package that declares an entry point in the
``sellbird.extensions`` group. Its value is a function taking the registry:

    # the extension's pyproject.toml
    [project.entry-points."sellbird.extensions"]
    myext = "myext.sellbird_plugin:install"

    # myext/sellbird_plugin.py
    def install(registry):
        registry.add_router(router)                     # dashboard routes
        registry.add_tick_step("myext.sync", sync)      # runs every heartbeat cycle
        registry.add_cli_command("myext", configure)    # a `sellbird myext` subcommand

Extensions load once per process, on first use, in entry-point name order. A
failing ``install`` stops Sellbird with the extension's name, rather than
running with half an extension. An install with no extensions (every
self-hosted install) loads nothing and behaves exactly as before.

Extensions are trusted code: they run in the same process with the same
access as Sellbird itself. Install only ones you'd install as a Python package.
"""

import builtins;

import from __future__ { annotations }

import argparse;

import asyncio;

import logging;

import re;

import from collections.abc { Awaitable, Callable }

import from dataclasses { dataclass, field }

import from importlib.metadata { entry_points }

import from typing { Any }

glob logger: any = logging.getLogger(__name__);

glob ENTRY_POINT_GROUP: any = "sellbird.extensions";

glob _NAME: any = re.compile("^[a-z][a-z0-9_.-]{0,63}$");

glob TICK_STEP_TIMEOUT_SECONDS: any = 120.0;

glob TickStep: any = Callable[["TickContext"], Awaitable[None]];

glob ConfigureCommand: any = Callable[[argparse.ArgumentParser], Callable[[
    argparse.Namespace,
], Any]];

glob _LOADED: any = False;

"""An extension couldn't be installed, or asked for something invalid."""
obj ExtensionError(RuntimeError) {
    def __repr__ -> str;

    def __eq__(other: any) -> bool;

    def __hash__ -> int;
}

"""What a tick step gets: the cycle's config and state (a StateManager)."""
@dataclass(frozen=True)
class TickContext {
    has config: Any;

    has state: Any;
}

@dataclass
class Registry {
    has routers: list[Any] = field(default_factory=list[any]);

    has tick_steps: dict[str, TickStep] = field(default_factory=dict[any, any]);

    has cli_commands: dict[str, tuple[str, ConfigureCommand]] = field(
        default_factory=dict[any, any]
    );

    has send_rules: dict[str, Any] = field(default_factory=dict[any, any]);

    has send_headers: dict[str, Any] = field(default_factory=dict[any, any]);

    has agent_routes: list[tuple[str, str]] = field(default_factory=list[any]);

    has mcp_tools: dict[str, Any] = field(default_factory=dict[any, any]);

    has mailbox_connections: dict[str, Any] = field(default_factory=dict[any, any]);

    """A FastAPI ``APIRouter`` served by the dashboard, behind its guard,
        after the built-in routes (an extension can add paths, not replace them)."""
    def add_router(router) -> None;

    """An async ``step(TickContext)`` run once each heartbeat cycle, after the
        cycle's own work. A step that fails or runs past the timeout is logged
        and skipped; it never stops the cycle."""
    def add_tick_step(name: str, step: TickStep) -> None;

    """A ``sellbird <name>`` subcommand. ``configure(parser)`` adds its
        arguments and returns the function that runs it with the parsed args.
        A name the built-in CLI already uses is refused when the CLI is built."""
    def add_cli_command(name: str, configure: ConfigureCommand, *, help: str = "") -> None;

    """An async ``rule(SendCheck)`` asked before each email, after the
        built-in checks: return ``send_hooks.Hold`` or ``send_hooks.Cancel``
        to stop it, None to let it through (sellbird.send_hooks)."""
    def add_send_rule(name: str, rule) -> None;

    """``hook(outbox_item)`` returns extra (header, value) pairs for an email."""
    def add_send_headers(name: str, hook) -> None;

    """Let the coding agent call one of your routes (sellbird.agent_policy).
        ``pattern`` is a full-match regex on the path. Everything not added is
        the user's alone."""
    def add_agent_route(method: str, pattern: str) -> None;

    """``register(server, client_factory, guarded)`` adds tools to the MCP
        server (sellbird.mcp_server), after the built-in ones."""
    def add_mcp_tools(name: str, register) -> None;

    """Another way an inbox can connect (sellbird.mailboxes): mailbox rows
        whose ``connection`` is this name are sent and read with
        ``build(row, config=, env=, secrets=)``, a MailProvider or None. The
        built-in kinds (oauth, smtp) can't be replaced."""
    def add_mailbox_connection(connection: str, build) -> None;
}

glob _REGISTRY: any;

with entry {
    _REGISTRY = Registry();
}

def _check_name(name: str, what: str) -> None;

"""The process's registry, with every installed extension loaded."""
def registry -> Registry;

def load -> None;

glob timeout_default_: any;

with entry {
    timeout_default_ = TICK_STEP_TIMEOUT_SECONDS;
}

"""Run every registered tick step once, in registration order. Returns
    ``{name: "ok" | "failed" | "timed out"}``."""
async def run_tick_steps(config, state, *, timeout: float = timeout_default_) -> dict[str, str];
