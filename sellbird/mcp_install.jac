import builtins;
import json;
import os;
import re;
import shlex;
import shutil;
import subprocess;
import sys;
import tempfile;
import tomllib;
import from dataclasses { dataclass }
import from datetime { datetime }
import from pathlib { Path }
import from typing { Callable, Literal, Mapping }

glob SERVER_NAME = "sellbird",
     CODEX_MARKER = "# Added by Sellbird (sellbird mcp install). Remove with: sellbird mcp uninstall codex",
     CLIENT_NAMES = {"claude": "Claude Code", "codex": "Codex"},
     RESTART_CLAUDE = "If Claude Code is open, restart it.",
     REFUSE_NO_CLAUDE = "Claude Code isn't installed here (no `claude` command and no ~/.claude.json).",
     REFUSE_BAD_JSON = "~/.claude.json isn't valid JSON, so it was left alone.",
     REFUSE_FOREIGN_CLAUDE = "~/.claude.json already has a Sellbird server that this command didn't add. Edit it yourself, or remove it and run this again.",
     REFUSE_BAD_TOML = "~/.codex/config.toml isn't valid TOML, so it was left alone.",
     REFUSE_FOREIGN_CODEX = "~/.codex/config.toml already has a Sellbird server that this command didn't add. Edit it yourself, or remove it and run this again.",
     VERIFY_FAILED = "The change didn't check out, so your original file was restored.",
     NOT_TTY = "Nothing was changed. Re-run with --yes to apply.",
     CLAUDE_LABEL = "~/.claude.json",
     SYMLINK_REFUSAL = "{} is a symlink, so it was left alone. Add the entry to the file it points to yourself (sellbird mcp install --print shows it).",
     UNREADABLE = "{} couldn't be read ({}), so it was left alone.",
     CODEX_LABEL = "~/.codex/config.toml",
     _BARE_KEY = re.compile("^[A-Za-z0-9_-]+$"),
     _HEADER = re.compile("^\\s*\\["),
     _OUR_HEADER = re.compile(
         "^\\s*\\[\\s*mcp_servers\\s*\\.\\s*(sellbird|\"sellbird\"|'sellbird')\\s*\\]\\s*(#.*)?$"
     );

class InstallError(Exception) {}

class InstallVerifyFailed(InstallError) {}

@dataclass(frozen=True)
class PlannedChange {
    has client: Literal["claude", "codex"],
        action: Literal["add", "replace", "remove", "none", "refuse", "cli"],
        path: Path | None,
        preview: str,
        reason: str = "",
        argv: tuple[str, ...] = (),
        pre_argv: tuple[str, ...] = (),
        old_json: str = "";
}

def server_entry -> dict[str, any];

def is_ours(candidate: any) -> bool;

def _same(candidate: any) -> bool;

def _prefixed(sign: str, text: str) -> list[str];

def _read_claude(path: Path) -> tuple[any, ...];

def _claude_entry_preview(old: any, new: any) -> str;

def _claude_cli_argv(
    claude: str, verb: str, previous: dict[str, any] | None = None
) -> tuple[any, ...];

def _plan_claude(home: Path, which: any, install: bool) -> PlannedChange;

def plan_claude(
    *, home: Path, which: any = shutil.which, runner: any = subprocess.run
) -> PlannedChange;

def plan_uninstall_claude(
    *, home: Path, which: any = shutil.which, runner: any = subprocess.run
) -> PlannedChange;

def _claude_new_text(action: str, text: str) -> str;

def _parts(client: str, text: str) -> tuple[any, ...];

def _codex_path(env: Mapping[str, str], home: Path) -> Path;

def _toml_str(value: str) -> str;

def render_codex_block(server: dict[str, any]) -> str;

def _read_codex(path: Path) -> tuple[any, ...];

def _our_block(text: str) -> tuple[int, int] | None;

def _plan_codex(env: Mapping[str, str], home: Path, install: bool) -> PlannedChange;

def plan_codex(*, env: Mapping[str, str], home: Path) -> PlannedChange;

def plan_uninstall_codex(*, env: Mapping[str, str], home: Path) -> PlannedChange;

def _codex_new_text(action: str, text: str) -> str;

def _backup_path(path: Path, now: datetime) -> Path;

def _write_atomic(target: Path, text: str);

def _write_private(path: Path, data: bytes, *, exclusive: bool);

def _restore(data: bytes, backup: Path, target: Path);

def _label(change: PlannedChange) -> str;
def _cant_back_up(change: PlannedChange, e: any) -> InstallError;

def _read(change: PlannedChange) -> bytes | None;

def _back_up(change: PlannedChange, data: bytes | None, now: datetime) -> Path | None;

def _apply_file(change: PlannedChange, now: datetime);

def _run_cli(argv: tuple[str, ...], runner: any);

def _kept_at(backup: Path | None) -> str;

def _apply_cli(change: PlannedChange, runner: any, now: datetime, *, expect_absent: bool);

def apply_change(change: PlannedChange, *, runner: any = subprocess.run, now: datetime) -> str;

def print_config -> str;

def run_command(
    action: str,
    client: str | None,
    *,
    print_only: bool = False,
    yes: bool = False,
    home: Path | None = None,
    env: Mapping[str, str] | None = None,
    which: any = shutil.which,
    runner: any = subprocess.run,
    isatty: Callable[[], bool] | None = None,
    ask: Callable[[str], str] = builtins.input,
    out: Callable[[str], None] = builtins.print,
    now: datetime | None = None,
) -> int;

def _show_and_apply(
    change: PlannedChange, *, yes: bool, isatty: any, ask: any, out: any, runner: any, now: datetime
) -> int;
