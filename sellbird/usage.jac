"""Usage accounting helpers.

Sellbird's usage ledger is built entirely from its OWN Claude calls: every
`claude -p` invocation goes through the Brain, which parses the call's
result JSON and writes one usage_events row tagged with the agent and task
(see sellbird/brain.py). That path is the single source of truth — it never
sees, and never records, your other Claude Code sessions.

(An earlier version also scanned every transcript in the Claude config
directory to "backfill" usage. That pulled in unrelated projects' sessions
and polluted Sellbird's numbers, so it was removed: Sellbird tracks only what
Sellbird does.)

This module now holds just the shared location helper the quota client
needs.
"""

import os;

import from pathlib { Path }

"""Claude Code's config directory (honors CLAUDE_CONFIG_DIR)."""
def claude_config_dir -> Path;
