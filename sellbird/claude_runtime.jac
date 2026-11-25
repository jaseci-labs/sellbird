"""How Sellbird starts the Claude CLI: no tools, and none of the operator's own
Claude Code customisation.

Sellbird's prompts carry untrusted text and its output goes to third parties
as email, so a brain call must see only what Sellbird sends it. A plain
``claude -p`` loads the operator's ``~/.claude/CLAUDE.md``, any ``CLAUDE.md``
in the working directory or its ancestors, settings hooks, skills, plugins
and MCP servers, and saves a transcript of the prompt under
``~/.claude/projects``. Every call here instead runs with:

- ``--safe-mode``: CLAUDE.md, skills, plugins, hooks, MCP servers, custom
  commands and agents disabled. Login (OAuth, keychain or token) still works
  and admin-managed policy still applies. ``--bare`` is NOT used: it never
  reads OAuth or the keychain, which would break subscription login.
- ``--setting-sources ""``: no user, project or local settings files.
- ``--tools ""`` and ``--strict-mcp-config``: no built-in tools, no MCP.
- ``--disable-slash-commands`` and ``--no-session-persistence``: no skills,
  and nothing about the call is written to the operator's transcripts.
- a fresh, empty temporary working directory (never the checkout, whose own
  CLAUDE.md is the setup wizard), with ``PWD`` pointed at it;
- the prompt on stdin, never in argv, where other local users can read it
  (``ps``) and where Windows ``.cmd`` shims would re-parse it;
- a few inherited variables that load extra instructions or tie the call to
  an enclosing Claude Code session removed. Login, proxy and provider
  variables are left exactly as they are.

Before any prompt is sent the CLI's ``--help`` must list every one of those
flags; if any is missing Sellbird refuses to call it (there is no fallback to
an unisolated call). That check proves the flags exist, not what the CLI
does with them: the behaviour itself is verified offline against the
installed CLI by ``tests/test_claude_cli_isolation.py``.
"""

import builtins;

import from __future__ { annotations }

import os;

import re;

import shutil;

import subprocess;

import sys;

import tempfile;

import threading;

import uuid;

import from contextlib { contextmanager }

import from pathlib { Path }

glob REQUIRED_FLAGS: any = (
    "--safe-mode",
    "--setting-sources",
    "--no-session-persistence",
    "--disable-slash-commands",
    "--strict-mcp-config",
    "--tools",
    "--output-format",
);

glob STRIPPED_ENV: any = (
    "CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD",
    "CLAUDE_CODE_SIMPLE",
    "CLAUDE_CODE_ENTRYPOINT",
    "CLAUDE_CODE_SSE_PORT",
    "CLAUDE_ENV_FILE",
    "CLAUDE_PROJECT_DIR",
    "CLAUDECODE",
    "OLDPWD",
);

glob HELP_TIMEOUT_SECONDS: any = 30;

glob _capable: dict[tuple[str, int | None, int | None], bool];

glob _capable_lock: any;

glob _PLATFORM: any;

glob _SHIM_TARGET_RE: any;

glob _MIN_NATIVE_BYTES: any;

glob INSTALL_HINT: any;

with entry {
    _capable = {};
    _capable_lock = threading.Lock();
}

"""The Claude CLI can't be used safely until the operator acts."""
obj ClaudeRuntimeError(Exception) {
    def __repr__ -> str;

    def __eq__(other: any) -> bool;

    def __hash__ -> int;
}

with entry {
    _PLATFORM = sys.platform;
    _SHIM_TARGET_RE = re.compile(
        "\"(?:%~?dp0%?\\\\)?((?:[A-Za-z]:\\\\)?[^\"%]*?\\bclaude\\.exe)\"", re.IGNORECASE
    );
    _MIN_NATIVE_BYTES = 4096;
    INSTALL_HINT = "Install Claude Code (https://code.claude.com/docs/en/setup): on Windows run 'irm https://claude.ai/install.ps1 | iex' in PowerShell or 'winget install Anthropic.ClaudeCode'; or 'npm install -g @anthropic-ai/claude-code@latest' (without --ignore-scripts).";
}

"""The native exe a .cmd shim launches (read from the shim, else npm's
    usual layout next to it)."""
def _shim_target(shim: Path) -> Path;

"""(what PATH finds, the native exe a Windows shim wraps or None)."""
def _locate(env: dict | None) -> tuple[str | None, Path | None];

"""Full path of the ``claude`` executable on the PATH Sellbird will use.

    On Windows an npm install puts a ``claude.cmd`` shim on PATH. Running it
    goes through cmd.exe, which re-parses every argument, and the isolation
    flags include empty ones (``--tools ""``) whose meaning changes if one is
    dropped. So the shim is resolved to the native ``claude.exe`` it wraps,
    and refused if that isn't there.
    """
def find_claude(env: dict | None = None) -> str | None;

"""The child's environment: the operator's, minus instruction sources."""
def runtime_env(cwd: str, base: dict | None = None) -> dict;

"""argv for one isolated, tool-less, print-mode call. The prompt goes
    on stdin."""
def build_command(executable: str, model: str = "", session_id: str | None = None) -> list[str];

"""A fresh empty directory outside the checkout, removed afterwards. A
    failed removal (Windows, a child still exiting) never masks the call's
    own outcome or a cancellation."""
@contextmanager
def isolated_cwd -> Generator[any, any, any];

def _fingerprint(executable: str) -> tuple[str, int | None, int | None];

"""Changes when the installed CLI changes (used to re-check a pause)."""
def fingerprint(env: dict | None = None) -> tuple;

"""``claude --help`` output (no login, no model call). A nonzero exit
    raises CalledProcessError, whatever the output says: a CLI that fails
    its own help isn't trusted to honour the flags it lists."""
def _probe_help(executable: str) -> str;

def missing_flags(help_text: str) -> list[str];

"""Path of a Claude CLI that supports every isolation flag, or raise
    ClaudeRuntimeError saying what to do. A passing result is cached until
    the executable changes."""
def check_cli(env: dict | None = None) -> str;

def clear_cache -> any;
