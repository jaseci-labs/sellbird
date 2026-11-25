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
    class def for_root(`root: Path, *, mode: str = "self_hosted", secret_backend: any = None) -> Home;

    @builtins.property
    def hosted -> bool;
}

def _legacy(module: str, name: str, fallback: any) -> Path;

def default_home -> Home;

def current_home -> Home;

@contextmanager
def use_home(home: Home) -> Generator[any, any, any];

class NotOnHosted(Exception) {
    has feature: str = "",
        payload: dict[str, str] = {};

    def init(feature: str = "");
}

def require_self_hosted(feature: str);
