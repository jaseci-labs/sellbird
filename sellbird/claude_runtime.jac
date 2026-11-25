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

glob REQUIRED_FLAGS = tuple(
         "--safe-mode --setting-sources --no-session-persistence --disable-slash-commands --strict-mcp-config --tools --output-format".split(),
     ),
     STRIPPED_ENV = tuple(
         "CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD CLAUDE_CODE_SIMPLE CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_SSE_PORT CLAUDE_ENV_FILE CLAUDE_PROJECT_DIR CLAUDECODE OLDPWD".split(),
     ),
     HELP_TIMEOUT_SECONDS = 30,
     _capable: dict[tuple[str, int | None, int | None], bool] = {},
     _capable_lock = threading.Lock(),
     _PLATFORM = sys.platform,
     _SHIM_TARGET_RE = re.compile(
         "\"(?:%~?dp0%?\\\\)?((?:[A-Za-z]:\\\\)?[^\"%]*?\\bclaude\\.exe)\"", re.IGNORECASE
     ),
     _MIN_NATIVE_BYTES = 4096,
     INSTALL_HINT = "Install Claude Code (https://code.claude.com/docs/en/setup): on Windows run 'irm https://claude.ai/install.ps1 | iex' in PowerShell or 'winget install Anthropic.ClaudeCode'; or 'npm install -g @anthropic-ai/claude-code@latest' (without --ignore-scripts).";

class ClaudeRuntimeError(Exception) {}

def _shim_target(shim: Path) -> Path {
    try {
        text = shim.read_text(encoding="utf-8", errors="replace");
    } except OSError {
        text = "";
    }
    m = _SHIM_TARGET_RE.search(text);
    if m {
        target = m.group(1).replace("\\", "/");
        return Path(target) if re.match("[A-Za-z]:/", target) else shim.parent / target;
    }
    return shim.parent / "node_modules" / "@anthropic-ai" / "claude-code" / "bin" / "claude.exe";
}

def _locate(env: any) -> tuple[str | None, Path | None] {
    found = shutil.which("claude", path=(env if env is not None else os.environ).get("PATH"));
    if not found or _PLATFORM != "win32" or not found.lower().endswith((".cmd", ".bat")) {
        return (found, None);
    }
    return (found, _shim_target(Path(found)));
}

def find_claude(env: any = None) -> str | None {
    (found, native) = _locate(env) as any;
    if native is None {
        return found;
    }
    try {
        size = native.stat().st_size if native.is_file() else None;
    } except OSError {
        size = None;
    }
    if size is not None and size >= _MIN_NATIVE_BYTES {
        return str(native);
    }
    problem = "is only a placeholder: the package's install script didn't run"
        if size is not None
        else "isn't there";
    raise ClaudeRuntimeError(
        f"Found the claude.cmd shim ({found}), but the claude.exe it launches ({native}) {problem}. Sellbird never runs Claude through cmd.exe, which re-parses the flags that keep each call isolated. {INSTALL_HINT}",
    );
}

def runtime_env(cwd: str, base: any = None) -> dict[str, any] {
    env: dict[str, any] = dict(os.environ if base is None else base);
    for key in STRIPPED_ENV {
        env.pop(key, None);
    }
    env["PWD"] = cwd;
    env["CLAUDE_CODE_SAFE_MODE"] = "1";
    return env;
}

def build_command(executable: str, model: str = "", session_id: str | None = None) -> list[str] {
    cmd = [
        executable,
        "-p",
        "--output-format",
        "json",
        "--tools",
        "",
        "--strict-mcp-config",
        "--safe-mode",
        "--setting-sources",
        "",
        "--disable-slash-commands",
        "--no-session-persistence",
    ];
    if model {
        cmd += ["--model", model];
    }
    if session_id {
        try {
            uuid.UUID(session_id);
            cmd += ["--session-id", session_id];
        } except ValueError {}
    }
    return cmd;
}

@contextmanager
def isolated_cwd -> Generator[any, any, any] {
    with tempfile.TemporaryDirectory(prefix="sellbird-claude-", ignore_cleanup_errors=True) as tmp {
        yield str(Path(tmp).resolve());
    }
}

def _fingerprint(executable: str) -> tuple[str, int | None, int | None] {
    real = os.path.realpath(executable);
    try {
        st = os.stat(real);
        return (real, st.st_mtime_ns, st.st_size);
    } except OSError {
        return (real, None, None);
    }
}

def fingerprint(env: any = None) -> tuple[str, int | None, int | None] {
    (found, native) = _locate(env) as any;
    exe = str(native) if native is not None else found;
    return _fingerprint(exe) if exe else ("", None, None);
}

def _probe_help(executable: str) -> str {
    with isolated_cwd() as cwd {
        out = subprocess.run(
            [executable, "--help"],
            cwd=cwd,
            env=runtime_env(cwd),
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=HELP_TIMEOUT_SECONDS,
        );
    }
    out.check_returncode();
    return (out.stdout or "") + (out.stderr or "");
}

def missing_flags(help_text: str) -> list[str] {
    return [
        f
        for f in REQUIRED_FLAGS
        if not re.search(f"(?<![\\w-]){re.escape(f)}(?![\\w-])", help_text)
    ];
}

def check_cli(env: any = None) -> str {
    exe = find_claude(env);
    if not exe {
        raise ClaudeRuntimeError(
            "Claude CLI not found on PATH. Install it (https://code.claude.com/docs/en/setup) and run 'claude login'.",
        );
    }
    key = _fingerprint(exe);
    with _capable_lock {
        if _capable.get(key) {
            return exe;
        }
    }
    try {
        help_text = _probe_help(exe);
    } except (OSError, subprocess.SubprocessError) as e {
        raise ClaudeRuntimeError(
            f"Could not run '{exe} --help' to check the Claude CLI ({type(e).__name__}). Sellbird sends no prompt until it can confirm the CLI isolates calls.",
        ) from e;
    }
    missing = missing_flags(help_text);
    if missing {
        raise ClaudeRuntimeError(
            f"This Claude CLI ({exe}) lacks {', '.join(missing)}, which Sellbird needs to keep your CLAUDE.md, hooks, skills, plugins and settings out of its prompts. Update it ('claude update', or rebuild the Docker image) and Sellbird resumes on its own. No prompt was sent.",
        );
    }
    with _capable_lock {
        _capable[key] = True;
    }
    return exe;
}

def clear_cache {
    with _capable_lock {
        _capable.clear();
    }
}
