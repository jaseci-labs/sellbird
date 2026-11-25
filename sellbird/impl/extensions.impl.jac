impl ExtensionError.__repr__ -> str {
    return (getattr(builtins.super(ExtensionError, self), "__repr__") as any)();
}

impl ExtensionError.__eq__(other: any) -> bool {
    return self is other;
}

impl ExtensionError.__hash__ -> int {
    return id(self);
}

impl Registry.add_router(router) -> None {
    self.routers.append(router);
}

impl Registry.add_tick_step(name: str, step: TickStep) -> None {
    _check_name(name, "tick step");
    if name in self.tick_steps {
        raise ExtensionError(f"tick step {name!r} is already registered");
    }
    if not asyncio.iscoroutinefunction(step) {
        raise ExtensionError(f"tick step {name!r} must be an async function");
    }
    self.tick_steps[name] = step;
}

impl Registry.add_cli_command(name: str, configure: ConfigureCommand, *, help: str = "") -> None {
    _check_name(name, "command");
    if name in self.cli_commands {
        raise ExtensionError(f"command {name!r} is already registered");
    }
    self.cli_commands[name] = (help, configure);
}

impl Registry.add_send_rule(name: str, rule) -> None {
    _check_name(name, "send rule");
    if name in self.send_rules {
        raise ExtensionError(f"send rule {name!r} is already registered");
    }
    if not asyncio.iscoroutinefunction(rule) {
        raise ExtensionError(f"send rule {name!r} must be an async function");
    }
    self.send_rules[name] = rule;
}

impl Registry.add_send_headers(name: str, hook) -> None {
    _check_name(name, "header hook");
    if name in self.send_headers {
        raise ExtensionError(f"header hook {name!r} is already registered");
    }
    self.send_headers[name] = hook;
}

impl Registry.add_agent_route(method: str, pattern: str) -> None {
    import re;
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

impl Registry.add_mcp_tools(name: str, register) -> None {
    _check_name(name, "MCP tool set");
    if name in self.mcp_tools {
        raise ExtensionError(f"MCP tool set {name!r} is already registered");
    }
    self.mcp_tools[name] = register;
}

impl Registry.add_mailbox_connection(connection: str, build) -> None {
    import from sellbird.mailboxes { BUILT_IN_CONNECTIONS }
    _check_name(connection, "mailbox connection");
    if connection in BUILT_IN_CONNECTIONS or connection in self.mailbox_connections {
        raise ExtensionError(f"mailbox connection {connection!r} is already registered");
    }
    self.mailbox_connections[connection] = build;
}

impl _check_name(name: str, what: str) -> None {
    if not isinstance(name, `str) or not _NAME.match(name) {
        raise ExtensionError(f"{what} name {name!r} must be lowercase letters, digits, . _ or -");
    }
}

impl registry -> Registry {
    load();
    return _REGISTRY;
}

impl load -> None {
    if _LOADED {
        return;
    }
    _LOADED = True;
    for ep in sorted(entry_points(group=ENTRY_POINT_GROUP), key=lambda (e) -> any { e.name }) {
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

impl run_tick_steps(config, state, *, timeout: float = timeout_default_) -> dict[str, str] {
    results: dict[str, str] = {};
    context: any = TickContext(config=config, state=state);
    for (name, step) in `list(registry().tick_steps.items()) {
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
