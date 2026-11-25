import builtins;
import argparse;
import asyncio;
import logging;
import re;
import from collections.abc { Awaitable, Callable }
import from dataclasses { dataclass, field }
import from importlib.metadata { entry_points }
import from typing { Any }

glob logger = logging.getLogger(__name__),
     ENTRY_POINT_GROUP = "sellbird.extensions",
     _NAME = re.compile("^[a-z][a-z0-9_.-]{0,63}$"),
     TICK_STEP_TIMEOUT_SECONDS = 120.0,
     TickStep = Callable[["TickContext"], Awaitable[None]],
     ConfigureCommand = Callable[[argparse.ArgumentParser], Callable[[argparse.Namespace], Any]],
     _LOADED = False;

class ExtensionError(RuntimeError) {}

@dataclass(frozen=True)
class TickContext {
    has config: any,
        state: any;
}

def _check_name(name: str, what: str) {
    if not isinstance(name, str) or not _NAME.match(name) {
        raise ExtensionError(f"{what} name {name!r} must be lowercase letters, digits, . _ or -");
    }
}

def _add(table: any, what: str, name: str, value: any, coroutine: bool = False) {
    _check_name(name, what);
    if name in table {
        raise ExtensionError(f"{what} {name!r} is already registered");
    }
    if coroutine and not asyncio.iscoroutinefunction(value) {
        raise ExtensionError(f"{what} {name!r} must be an async function");
    }
    table[name] = value;
}

@dataclass
class Registry {
    has routers: list[any] = field(default_factory=builtins.list),
        tick_steps: dict[str, TickStep] = field(default_factory=builtins.dict),
        cli_commands: dict[str, tuple[str, ConfigureCommand]] = field(
            default_factory=builtins.dict
        ),
        send_rules: dict[str, any] = field(default_factory=builtins.dict),
        send_headers: dict[str, any] = field(default_factory=builtins.dict),
        agent_routes: list[tuple[str, str]] = field(default_factory=builtins.list),
        mcp_tools: dict[str, any] = field(default_factory=builtins.dict),
        mailbox_connections: dict[str, any] = field(default_factory=builtins.dict);

    def add_router(router: any) {
        self.routers.append(router);
    }

    def add_tick_step(name: str, step: TickStep) {
        _add(self.tick_steps, "tick step", name, step, coroutine=True);
    }

    def add_cli_command(name: str, configure: ConfigureCommand, *, help: str = "") {
        _add(self.cli_commands, "command", name, (help, configure));
    }

    def add_send_rule(name: str, rule: any) {
        _add(self.send_rules, "send rule", name, rule, coroutine=True);
    }

    def add_send_headers(name: str, hook: any) {
        _add(self.send_headers, "header hook", name, hook);
    }

    def add_agent_route(method: str, pattern: str) {
        if method.upper() not in ("GET", "POST", "PUT", "PATCH", "DELETE") {
            raise ExtensionError(f"agent route method {method!r} isn't an HTTP method");
        }
        try {
            re.compile(pattern);
        } except re.error as e {
            raise ExtensionError(f"agent route pattern {pattern!r} doesn't compile: {e}") from e;
        }
        self.agent_routes.append((method.upper(), pattern));
    }

    def add_mcp_tools(name: str, register: any) {
        _add(self.mcp_tools, "MCP tool set", name, register);
    }

    def add_mailbox_connection(connection: str, build: any) {
        import from sellbird.mailboxes { BUILT_IN_CONNECTIONS }
        _check_name(connection, "mailbox connection");
        if connection in BUILT_IN_CONNECTIONS {
            raise ExtensionError(f"mailbox connection {connection!r} is already registered");
        }
        _add(self.mailbox_connections, "mailbox connection", connection, build);
    }
}

glob _REGISTRY: any;

with entry {
    _REGISTRY = Registry();
}

def registry -> Registry {
    load();
    return _REGISTRY;
}

def load {
    if _LOADED {
        return;
    }
    _LOADED = True;
    for ep in sorted(entry_points(group=ENTRY_POINT_GROUP), key=lambda (e: any) -> any { e.name }) {
        try {
            ep.load()(_REGISTRY);
        } except Exception as e {
            raise ExtensionError(
                f"the Sellbird extension {ep.name!r} failed to install: {e}"
            ) from e;
        }
        logger.info(f"Loaded the Sellbird extension {ep.name!r}.");
    }
}

async def run_tick_steps(
    config: any, state: any, *, timeout: float = TICK_STEP_TIMEOUT_SECONDS
) -> dict[str, str] {
    results: dict[str, str] = {};
    context = TickContext(config=config, state=state);
    for (name, step) in list(registry().tick_steps.items()) {
        try {
            await asyncio.wait_for(step(context), timeout=timeout);
            results[name] = "ok";
        } except asyncio.TimeoutError {
            logger.error(f"Extension step {name!r} ran past {timeout:.0f}s and was stopped.");
            results[name] = "timed out";
        } except (KeyboardInterrupt, asyncio.CancelledError) {
            raise;
        } except Exception as e {
            logger.error(f"Extension step {name!r} failed: {e}", exc_info=True);
            results[name] = "failed";
        }
    }
    return results;
}
