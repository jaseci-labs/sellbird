impl CoreUnavailable.init {
    super.init(NOT_RUNNING);
}

impl base_url(host: str, port: int) -> str {
    if ":" in host and not host.startswith("[") {
        host = f"[{host}]";
    }
    return f"http://{host}:{port}/";
}

impl CoreClient.init(data_dir: Path, transport: httpx.AsyncBaseTransport | None = None) {
    self.data_dir = Path(data_dir);
    self._transport = transport;
}

impl CoreClient._client(base: str, timeout: float = 15.0) -> httpx.AsyncClient {
    extra = {"transport": self._transport} if self._transport is not None else {};
    return httpx.AsyncClient(base_url=base, timeout=timeout, **extra);
}

impl CoreClient._connection -> tuple[str, str] {
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

impl CoreClient._request(
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

impl CoreClient.get(path: str) -> builtins.dict {
    return await self._request("GET", path);
}

impl CoreClient.post(path: str, body: any = None, timeout: float = 15.0) -> builtins.dict {
    return await self._request("POST", path, json=body, timeout=timeout);
}

impl default_client -> CoreClient {
    return CoreClient(PROJECT_ROOT / "data");
}

impl WorkspaceNotFound.init(message: str) {
    super.init(message);
    self.message = message;
}

impl _with_workspace(fn: any, workspace_arg: WorkspaceArg) -> any {
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
    wrapper.__annotations__ = annotations | {
        "workspace": param.annotation,
        "return": sig.return_annotation,
    };
    return wrapper;
}

impl _workspace_call(
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

impl _add_workspace_arg(server: MCPServer, workspace_arg: WorkspaceArg) {
    register_tool = server.tool;
    def tool(*args: any, **kwargs: any) -> any {
        register = register_tool(*args, **kwargs);
        return lambda (fn: any) -> any { register(_with_workspace(fn, workspace_arg)) };
    }
    server.tool = tool;
}

impl _Tools.guarded(call: any) -> any {
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

impl _Tools._read(path: str) -> builtins.dict {
    return await self.guarded(lambda (c: any) -> any { c.get(path) });
}

impl _Tools._post(path: str, body: any = None, timeout: float = 15.0) -> builtins.dict {
    return await self.guarded(lambda (c: any) -> any { c.post(path, body, timeout=timeout) });
}

impl _Tools.company_contacts(company_id: str) -> builtins.dict {
    return await self._read(f"/api/companies/{quote(company_id, safe='')}/contacts");
}

impl _Tools.company_profile(company_id: str) -> builtins.dict {
    return await self._read(f"/api/companies/{quote(company_id, safe='')}/profile");
}

impl _Tools.discover_estimate(
    provider: str,
    cities: list[str] | None = None,
    depth: int = 30,
    limit: int = 100,
    preset: str = "",
) -> builtins.dict {
    body = dict(provider=provider, cities=cities or [], depth=depth, limit=limit, preset=preset);
    return await self._post("/api/discover/estimate", body);
}

impl _Tools.sending_status -> builtins.dict {
    return await self.guarded(_live_and_mode);
}

impl _Tools.sending_pause -> builtins.dict {
    return await self.guarded(_pause);
}

impl _Tools.offer_suggest -> builtins.dict {
    return await self._post("/api/offer/suggest", timeout=MODEL_CALL_TIMEOUT);
}

impl _Tools.offer_preview(`entry: str) -> builtins.dict {
    return await self._post("/api/offer/preview", {"entry": `entry}, timeout=MODEL_CALL_TIMEOUT);
}

impl _Tools.offer_propose(`entry: str, why: str = "") -> builtins.dict {
    return await self._post("/api/offer/propose", {"entry": `entry, "why": why});
}

impl _Tools.inbox_pause(inbox_id: str, reason: str = "") -> builtins.dict {
    return await self._post(f"/api/inboxes/{quote(inbox_id, safe='')}/pause", {"reason": reason});
}

impl build_server(
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
        tool = functools.partial(getattr(tools, name))
            if path == "-"
            else functools.partial(tools._read, path);
        tool.__name__ = name;
        server.tool(description=re.sub(r"\n\s+", "\n", text))(tool);
    }
    for register in extensions.registry().mcp_tools.values() {
        register(server, client_factory, tools.guarded);
    }
    return server;
}

impl run_stdio {
    logging.basicConfig(level=logging.WARNING, stream=sys.stderr, force=True);
    build_server().run("stdio");
}

impl _live_and_mode(c: CoreClient) -> builtins.dict {
    live = await c.get("/api/live-status");
    mode = await c.get("/api/sending-mode");
    return live if live.get("ok") is False else {"live": live, "mode": mode};
}

impl _pause(c: CoreClient) -> builtins.dict {
    result = await c.post("/api/sending/pause");
    if result.get("ok") is False {
        return result;
    }
    return {
        **result,
        "paused": True,
        "message": "Sending is paused. Only the user can resume it, in the dashboard.",
    };
}
