"""Seed the home folder with the files the app needs before its first run.

A pipx install puts the package in site-packages and the editable defaults
(sellbird.yaml, .env.example, prompts/, skills/) in ``<prefix>/share/
Sellbird`` (pyproject's data-files). The home folder starts empty, so
every command first copies over whatever is missing. It never overwrites:
those files are the user's to edit, and a re-seed after an upgrade must not
undo their changes. A checkout is its own source, so there only data/ is
created.
"""

import builtins;

import shutil;

import sys;

import from pathlib { Path }

glob SEED_GLOBS: any = ("prompts/*.md", "skills/*.md", "sellbird.yaml", ".env.example");

"""Where the shipped default files are, or None when there are none."""
def bundled_defaults -> Path | None;

"""Create data/ and copy missing defaults; return the relative paths created."""
def seed_home(home: Path, source: Path | None) -> builtins.list[builtins.str];
