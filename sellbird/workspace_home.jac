import builtins;
import importlib;
import sys;
import from contextlib { contextmanager }
import from contextvars { ContextVar }
import from dataclasses { dataclass }
import from pathlib { Path }

glob _HOME: ContextVar = ContextVar("sellbird_home", default=None),
     _DASH = "sellbird.dashboard",
     LOCAL_ONLY: dict[str, str] = {
         "local_ai_loop": "the heartbeat calling the Claude or Codex CLI signed in on this computer",
         "local_training": "training through the Claude or Codex CLI on this computer",
         "local_discovery": "discovery runs started from this computer's dashboard",
         "desktop": "the menu-bar app and starting at login",
         "mcp_install": "adding Sellbird to this computer's coding-agent config",
         "env_settings": "editing this install's .env file",
         "process_logs": "this computer's process log",
         "demo_vendors": "the offline demo vendors",
     },
     HOSTED_REFUSED = tuple(LOCAL_ONLY);

@dataclass(frozen=True)
class Home {
    has `root: Path,
        data_dir: Path,
        db_path: Path,
        env_file: Path,
        prompts_dir: Path,
        skills_dir: Path,
        m365_token_file: Path,
        gmail_token_file: Path,
        dashboard_token_file: Path,
        agent_token_file: Path,
        config_file: Path | None,
        mode: str = "self_hosted",
        secret_backend: any = None;

    @builtins.classmethod
    class def for_root(
        `root: Path, *, mode: str = "self_hosted", secret_backend: any = None
    ) -> Home {
        data = `root / "data";
        tokens = "m365_token.json gmail_token.json dashboard-token agent-token".split();
        made = [
            `root,
            data,
            data / "sellbird.db",
            `root / ".env",
            `root / "prompts",
            `root / "skills",
        ];
        made.extend([data / name for name in tokens]);
        made.append(`root / "sellbird.yaml");
        return cls(*made, mode=mode, secret_backend=secret_backend);
    }

    @builtins.property
    def hosted -> bool {
        return self.mode == "hosted";
    }
}

def _legacy(module: str, name: str, fallback: any) -> Path {
    loaded = sys.modules.get(module);
    return Path(getattr(loaded, name) if loaded is not None else fallback);
}

def default_home -> Home {
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

def current_home -> Home {
    return _HOME.get() or default_home();
}

@contextmanager
def use_home(home: Home) -> Generator[any, any, any] {
    token = _HOME.set(home);
    try {
        yield home;
    } finally {
        _HOME.reset(token);
    }
}

class NotOnHosted(Exception) {
    has feature: str = "",
        payload: dict[str, str] = {};

    def init(feature: str = "") {
        super.init(feature);
        self.feature = feature;
        what = LOCAL_ONLY.get(feature);
        message = f"This runs only on your own computer ({what}). Hosted Sellbird does this on the server instead."
            if what
            else "This runs only on your own computer, not on hosted Sellbird.";
        self.payload = {"error": "not_on_hosted", "message": message};
    }
}

def require_self_hosted(feature: str) {
    if feature not in LOCAL_ONLY {
        raise ValueError(f"unknown local-only feature: {feature!r}");
    }
    if current_home().hosted {
        raise NotOnHosted(feature);
    }
}
