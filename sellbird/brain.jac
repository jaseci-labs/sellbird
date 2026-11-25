import asyncio;
import builtins;
import json;
import logging;
import re;
import time;

glob logger = logging.getLogger("sellbird.brain"),
     PROMPTS_DIR = PROJECT_ROOT / "prompts",
     SKILLS_DIR = PROJECT_ROOT / "skills",
     DEFAULT_TIMEOUT_SECONDS = 300,
     DEFAULT_MAX_RETRIES = 2,
     RETRY_BASE_DELAY = 5.0,
     KILL_REAP_SECONDS = 10.0,
     _NON_RETRYABLE_PATTERNS = (
         "not logged in",
         "please run `claude login`",
         "invalid api key",
         "unauthorized",
     ),
     PROVIDER_LABELS = {"claude": "Claude", "codex": "Codex"},
     BRAIN_STATUS_KEY = "brain_status",
     _PERSISTENT_CODEX_KINDS = {"setup", "auth", "isolation"},
     PROVIDER_RECHECK_SECONDS = 1800,
     USAGE_LIMIT_PAUSE_SECONDS = 3600,
     _MODEL_USAGE_KEYS = "inputTokens outputTokens cacheReadInputTokens cacheCreationInputTokens".split(),
     _ROW_KEYS = "input_tokens output_tokens cache_read_tokens cache_creation_tokens".split(),
     _FLAT_USAGE_KEYS = "input_tokens output_tokens cache_read_input_tokens cache_creation_input_tokens".split();

def parse_brain_status(raw: str) -> dict[str, any];
def active_brain_status(raw: str, provider: str) -> dict[str, any];

class BrainUnavailable(Exception) {}

def _read_knowledge(folder: str, name: str) -> str;
def _load(folder: str, name: str, kind: str) -> str;
def _agent_of(agent: str, label: str) -> str;
def _usage_row(model: str, usage: dict[str, any], keys: list[str], cost: any) -> dict[str, any];
async def _backoff(what: str, attempt: int, max_retries: int);
def _kill(process: any) -> bool;
async def _account(counter: any, record: any, **kwargs: any);

class Brain {
    has state: any = None,
        transport: any = None,
        config: any = None,
        provider: str = "",
        model: str = "",
        codex: any = None,
        quota: any = None,
        last_reply_empty: bool = False,
        unavailable: str = "",
        _unavailable_at: float = 0.0,
        _unavailable_fingerprint: any = None,
        _usage_limited_until: float = 0.0,
        _usage_pause_recorded: bool = False,
        _status_synced: bool = False;

    def init(state: StateManager, brain_config: any = None, transport: any = None);

    @builtins.property
    def provider_label -> str;

    @builtins.property
    def paused_reason -> str;

    async def preflight -> str;
    async def _claude_ready -> any;
    def _fingerprint -> any;
    async def _expire_usage_pause;
    async def _mark_unavailable(error: any);
    async def _mark_available;
    async def _record_status(status: str, reason: str, **extra: any);
    async def think(
        prompt: str,
        session_id: str | None = None,
        expect_json: bool = False,
        timeout: float = DEFAULT_TIMEOUT_SECONDS,
        max_retries: int = DEFAULT_MAX_RETRIES,
        agent: str = "",
        task: str = "",
    ) -> str;
    async def _think_codex(
        prompt: str, session_id: str | None, timeout: float, max_retries: int, agent: str, task: str
    ) -> str;
    static def _parse_result_payload(raw: str) -> tuple[str, dict[str, any] | None];
    async def _record_usage(payload: dict[str, any] | None, agent: str, task: str, label: str);
    async def think_json(
        prompt: str, session_id: str | None = None, agent: str = "", task: str = ""
    ) -> dict[str, any] | list[any] | None;
    static def _extract_json(text: str) -> dict[str, any] | list[any] | None;
    async def check_usage -> float;
    async def is_within_budget(
        max_daily_calls: int = 200, max_percent: float | None = None
    ) -> bool;
    def load_prompt(prompt_name: str, **kwargs: any) -> str;
    def load_skill(skill_name: str) -> str;
    def load_skills_for_agent(agent_name: str) -> str;
}
