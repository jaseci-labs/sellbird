impl Home.for_root(`root: Path, *, mode: str = "self_hosted", secret_backend: any = None) -> Home {
    data = `root / "data";
    tokens = "m365_token.json gmail_token.json dashboard-token agent-token".split();
    made = [`root, data, data / "sellbird.db", `root / ".env", `root / "prompts", `root / "skills"];
    made.extend([data / name for name in tokens]);
    made.append(`root / "sellbird.yaml");
    return cls(*made, mode=mode, secret_backend=secret_backend);
}

impl Home.hosted -> bool {
    return self.mode == "hosted";
}

impl _legacy(module: str, name: str, fallback: any) -> Path {
    loaded = sys.modules.get(module);
    return Path(getattr(loaded, name) if loaded is not None else fallback);
}

impl default_home -> Home {
    paths = importlib.import_module("sellbird.paths");
    state = importlib.import_module("sellbird.state");
    db_path = _legacy(_DASH, "DB_PATH", state.DB_PATH);
    data = db_path.parent;
    `root = _legacy(_DASH, "PROJECT_ROOT", paths.PROJECT_ROOT);
    return Home(
        `root,
        data,
        db_path,
        _legacy(_DASH, "ENV_FILE", `root / ".env"),
        _legacy("sellbird.brain", "PROMPTS_DIR", `root / "prompts"),
        _legacy("sellbird.brain", "SKILLS_DIR", `root / "skills"),
        _legacy("sellbird.integrations.microsoft", "TOKEN_FILE", data / "m365_token.json"),
        _legacy("sellbird.integrations.gmail", "TOKEN_FILE", data / "gmail_token.json"),
        _legacy(_DASH, "TOKEN_FILE", data / "dashboard-token"),
        Path(getattr(sys.modules.get(_DASH), "AGENT_TOKEN_FILE", data / "agent-token")),
        None,
    );
}

impl current_home -> Home {
    return _HOME.get() or default_home();
}

impl use_home(home: Home) -> Generator[any, any, any] {
    token = _HOME.set(home);
    try {
        yield home;
    } finally {
        _HOME.reset(token);
    }
}

impl NotOnHosted.init(feature: str = "") {
    super.init(feature);
    self.feature = feature;
    what = LOCAL_ONLY.get(feature);
    message = f"This runs only on your own computer ({what}). Hosted Sellbird does this on the server instead."
        if what
        else "This runs only on your own computer, not on hosted Sellbird.";
    self.payload = {"error": "not_on_hosted", "message": message};
}

impl require_self_hosted(feature: str) {
    if feature not in LOCAL_ONLY {
        raise ValueError(f"unknown local-only feature: {feature!r}");
    }
    if current_home().hosted {
        raise NotOnHosted(feature);
    }
}
