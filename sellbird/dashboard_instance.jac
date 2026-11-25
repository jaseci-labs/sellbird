"""Where the running dashboard is: data/dashboard.json.

`sellbird dashboard` writes it once it knows its address, and removes it when
it stops. The MCP server reads it to find the dashboard, then asks
``/api/instance`` and talks to that address only if the id there matches the
file's, so a stale file never sends the agent's token to some other program
that took the port. The file holds no secrets.
"""

import from __future__ { annotations }

import json;

import os;

import tempfile;

import from dataclasses { dataclass }

import from pathlib { Path }

glob INFO_NAME: any = "dashboard.json";

@dataclass(frozen=True)
class DashboardInfo {
    has host: str;

    has port: int;

    has instance: str;

    has pid: int;
}

"""Publish the dashboard's address atomically (owner-only where it means anything)."""
def write(data_dir: Path, *, host: str, port: int, instance: str) -> None;

"""The published address, or None when there's no readable, well-formed file."""
def read(data_dir: Path) -> DashboardInfo | None;

"""Remove the file if it is still this dashboard's (a newer one may have replaced it)."""
def remove(data_dir: Path, *, instance: str) -> None;
