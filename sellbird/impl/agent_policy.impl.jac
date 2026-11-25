impl _compile(routes: any) -> list[tuple[str, re.Pattern]] {
    return [(method.upper(), re.compile(pattern)) for (method, pattern) in routes];
}

impl agent_may(method: str, path: str, extra: any = ()) -> bool {
    method = "GET" if method.upper() == "HEAD" else method.upper();
    return any(m == method and p.fullmatch(path) for (m, p) in (*_BUILT_IN, *extra));
}

impl AgentPolicy.__call__(scope: any, receive: any, send: any) {
    if scope["type"] == "http"
        and (scope.get("state") or {}).get("principal") == "agent"
        and not agent_may(
            scope["method"], scope["path"], _compile(extensions.registry().agent_routes)
        )
    {
        body = json.dumps(USER_ONLY).encode();
        headers = [
            (b"content-type", b"application/json"),
            (b"content-length", str(len(body)).encode()),
        ];
        await send({"type": "http.response.start", "status": 403, "headers": headers});
        await send({"type": "http.response.body", "body": body});
        return;
    }
    return await self.app(scope, receive, send);
}
