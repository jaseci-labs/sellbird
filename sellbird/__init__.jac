"""Sellbird — the open-source outreach platform that runs on your Claude or Codex subscription."""

import sys;

glob LEGACY_ENV: any;

with entry {
    if sys.version_info < (3, 11) {
        raise RuntimeError(
            f"Sellbird needs Python 3.11+, but this is {sys.version_info.major}.{sys.version_info.minor} ({sys.executable}). On macOS `python3` is the system 3.9 — rebuild the venv from a newer Python:\n    brew install python@3.13\n    rm -rf .venv && $(brew --prefix)/bin/python3.13 -m venv .venv\n    source .venv/bin/activate && pip install -e .",
        );
    }

    LEGACY_ENV = adopt_legacy_env();
}
