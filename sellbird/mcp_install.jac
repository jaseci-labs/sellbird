"""`sellbird mcp install|uninstall [claude|codex]`: register the MCP server with
the user's coding agent.

These are the user's own config files, shared with everything else they run,
so the rules are strict:

- Show the exact change first, and apply it only on a yes (or `--yes`).
- Touch only our entry. A server named Sellbird that this command didn't
  write is refused and nothing changes. In Codex's TOML "ours" is proven by
  the marker comment just above our table.
- Files: back up, write a temp file, atomic replace, re-read and verify that
  only our entry moved. If it didn't check out, restore the original.
- Claude Code: the `claude` CLI does the writing when it exists (Claude Code
  rewrites ~/.claude.json while it runs). Detection always reads the file,
  because `claude mcp get` prints human text, not data.
- Codex is touched only by an explicit `sellbird mcp install codex`. Sellbird's
  own Codex brain keeps its private CODEX_HOME; nothing here touches it.

The entry holds no token: the MCP server reads the agent token from the home
folder (SELLBIRD_HOME) at runtime.
"""

import builtins;

import operator;

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

glob SERVER_NAME: any = "sellbird";

glob CODEX_MARKER: any = "# Added by Sellbird (sellbird mcp install). Remove with: sellbird mcp uninstall codex";

glob CLIENT_NAMES: any = {"claude": "Claude Code", "codex": "Codex"};

glob RESTART_CLAUDE: any = "If Claude Code is open, restart it.";

glob REFUSE_NO_CLAUDE: any = "Claude Code isn't installed here (no `claude` command and no ~/.claude.json).";

glob REFUSE_BAD_JSON: any = "~/.claude.json isn't valid JSON, so it was left alone.";

glob REFUSE_FOREIGN_CLAUDE: any = "~/.claude.json already has a Sellbird server that this command didn't add. Edit it yourself, or remove it and run this again.";

glob REFUSE_BAD_TOML: any = "~/.codex/config.toml isn't valid TOML, so it was left alone.";

glob REFUSE_FOREIGN_CODEX: any = "~/.codex/config.toml already has a Sellbird server that this command didn't add. Edit it yourself, or remove it and run this again.";

glob VERIFY_FAILED: any = "The change didn't check out, so your original file was restored.";

glob NOT_TTY: any = "Nothing was changed. Re-run with --yes to apply.";

glob CLAUDE_LABEL: any = "~/.claude.json";

glob CODEX_LABEL: any = "~/.codex/config.toml";

def _symlink_refusal(label: builtins.str) -> builtins.str;

def _unreadable(label: builtins.str, err: any) -> builtins.str;

"""The change couldn't be made. The message is safe to show."""
obj InstallError(Exception) {
    def __repr__ -> str;

    def __eq__(other: any) -> bool;

    def __hash__ -> int;
}

"""The written file didn't check out; the original was put back."""
obj InstallVerifyFailed(InstallError) {
    def __repr__ -> str;

    def __eq__(other: any) -> bool;

    def __hash__ -> int;
}

@dataclass(frozen=True)
class PlannedChange {
    has client: Literal["claude", "codex"];

    has action: Literal["add", "replace", "remove", "none", "refuse", "cli"];

    has path: Path | None;

    has preview: builtins.str;

    has reason: builtins.str = "";

    has argv: any = ();

    has pre_argv: any = ();

    has old_json: builtins.str = "";
}

def server_entry -> builtins.dict;

"""Launched as `python [-P] -m sellbird mcp` or `sellbird mcp`: written by this command."""
def is_ours(`entry) -> builtins.bool;

"""Equal to ours. Claude's CLI stores "type": "stdio", the default."""
def _same(`entry) -> builtins.bool;

def _prefixed(sign: builtins.str, text: builtins.str) -> builtins.list[builtins.str];

def _claude_path(home: Path) -> Path;

"""(document, refusal). A missing file is an empty document."""
def _read_claude(path: Path) -> builtins.tuple[builtins.dict | None, builtins.str];

def _claude_entry_preview(old, new) -> builtins.str;

def _claude_cli_argv(
    claude: builtins.str, verb: builtins.str, `entry: builtins.dict | None = None
) -> any;

glob which_default_: any;

glob runner_default_: any;

glob _BARE_KEY: any;

glob _HEADER: any;

glob _OUR_HEADER: any;

with entry {
    which_default_ = shutil.which;
    runner_default_ = subprocess.run;
}

"""What installing for Claude Code would do. Reads only; never runs `claude`."""
def plan_claude(*, home: Path, which=which_default_, runner=runner_default_) -> PlannedChange;

glob which_default__: any;

glob runner_default__: any;

with entry {
    which_default__ = shutil.which;
    runner_default__ = subprocess.run;
}

def plan_uninstall_claude(
    *, home: Path, which=which_default__, runner=runner_default__
) -> PlannedChange;

def _claude_new_text(action: builtins.str, text: builtins.str) -> builtins.str;

"""(document without our entry, our entry or None)."""
def _claude_parts(text: builtins.str) -> builtins.tuple[builtins.dict, builtins.object];

with entry {
    _BARE_KEY = re.compile("^[A-Za-z0-9_-]+$");
    _HEADER = re.compile("^\\s*\\[");
    _OUR_HEADER = re.compile(
        "^\\s*\\[\\s*mcp_servers\\s*\\.\\s*(sellbird|\"sellbird\"|'sellbird')\\s*\\]\\s*(#.*)?$"
    );
}

def _codex_path(env: Mapping[builtins.str, builtins.str], home: Path) -> Path;

def _toml_str(value: builtins.str) -> builtins.str;

def _toml_key(key: builtins.str) -> builtins.str;

def render_codex_block(`entry: builtins.dict) -> builtins.str;

"""(text, document, refusal). Text None: no file."""
def _read_codex(path: Path) -> builtins.tuple[builtins.str | None, builtins.dict
    | None, builtins.str];

"""Line range [start, end) of our marked block, or None if not marked.

    It runs from the marker to the line before the next table header (or the
    end), less trailing blank and comment lines, which belong to what follows.
    """
def _our_block(text: builtins.str) -> builtins.tuple[builtins.int, builtins.int] | None;

def plan_codex(*, env: Mapping[builtins.str, builtins.str], home: Path) -> PlannedChange;

def plan_uninstall_codex(*, env: Mapping[builtins.str, builtins.str], home: Path) -> PlannedChange;

def _codex_new_text(action: builtins.str, text: builtins.str) -> builtins.str;

def _codex_parts(text: builtins.str) -> builtins.tuple[builtins.dict, builtins.object];

"""A fresh name: two changes in one second must not overwrite a backup."""
def _backup_path(path: Path, now: datetime) -> Path;

"""Temp file in the same folder, then os.replace: never a half-written file."""
def _write_atomic(target: Path, text: builtins.str) -> None;

"""Write `data` to a file created owner-only (0o600) whatever the umask, so
    a config's contents never sit in a world-readable file, even briefly."""
def _write_private(path: Path, data: builtins.bytes, *, exclusive: builtins.bool) -> None;

"""Put the original bytes back, atomically, by its own path (not the writer)."""
def _restore(data: builtins.bytes, backup: Path, target: Path) -> None;

def _label(change: PlannedChange) -> builtins.str;

def _cant_back_up(label: builtins.str, e: any) -> any;

"""The file's bytes (None when it doesn't exist); a symlink is refused."""
def _read(change: PlannedChange) -> builtins.bytes | None;

"""A backup of exactly these bytes, created owner-only, then given the
    original's mode (~/.claude.json is private)."""
def _back_up(change: PlannedChange, data: builtins.bytes | None, now: datetime) -> Path | None;

"""The file's bytes and its backup, taken from those same bytes."""
def _read_and_back_up(change: PlannedChange, now: datetime) -> builtins.tuple[builtins.bytes
    | None, Path | None];

def _apply_file(change: PlannedChange, now: datetime) -> None;

def _run_cli(argv: any, runner) -> None;

def _kept_at(backup: Path | None) -> builtins.str;

"""Run `claude mcp …`, roll back a half-done replace, then check the file."""
def _apply_cli(
    change: PlannedChange, runner, now: datetime, *, expect_absent: builtins.bool
) -> None;

glob runner_default___: any;

with entry {
    runner_default___ = subprocess.run;
}

"""Make the planned change and say what happened."""
def apply_change(change: PlannedChange, *, runner=runner_default___, now: datetime) -> builtins.str;

"""Everything needed to add the server by hand. Writes nothing."""
def print_config -> builtins.str;

def _codex_detected(which, env: Mapping[builtins.str, builtins.str], home: Path) -> builtins.bool;

glob which_default___: any;

glob runner_default____: any;

glob ask_default_: any;

glob out_default_: any;

with entry {
    which_default___ = shutil.which;
    runner_default____ = subprocess.run;
    ask_default_ = builtins.input;
    out_default_ = builtins.print;
}

"""`sellbird mcp install|uninstall [claude|codex]`. Returns the exit code.

    With no client only Claude Code is touched; Codex needs `codex` spelled
    out, and gets a one-line hint when it's installed.
    """
def run_command(
    action: builtins.str,
    client: builtins.str | None,
    *,
    print_only: builtins.bool = False,
    yes: builtins.bool = False,
    home: Path | None = None,
    env: Mapping[builtins.str, builtins.str] | None = None,
    which=which_default___,
    runner=runner_default____,
    isatty: Callable[[], builtins.bool] | None = None,
    ask: Callable[[builtins.str], builtins.str] = ask_default_,
    out: Callable[[builtins.str], None] = out_default_,
    now: datetime | None = None,
) -> builtins.int;

def _show_and_apply(change: PlannedChange, *, yes, isatty, ask, out, runner, now) -> builtins.int;
