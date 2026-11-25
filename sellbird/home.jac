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
def bundled_defaults -> Path | None {
    if paths.is_checkout(paths.PACKAGE_ROOT) {
        return paths.PACKAGE_ROOT;
    }
    shared: any = Path(sys.prefix) / "share" / paths.APP_DIR;
    return shared if shared.is_dir() else None;
}

"""Create data/ and copy missing defaults; return the relative paths created."""
def seed_home(home: Path, source: Path | None) -> builtins.list[builtins.str] {
    home = Path(home);
    (home / "data").mkdir(parents=True, exist_ok=True);
    if source is None or Path(source).resolve() == home.resolve() {
        return [];
    }
    source = Path(source);
    created: any = [];
    for pattern in SEED_GLOBS {
        for src in sorted(source.glob(pattern)) {
            if not src.is_file() {
                continue;
            }
            rel: any = src.relative_to(source);
            dest: any = home / rel;
            if dest.exists() or dest.is_symlink() {
                continue;
            }
            dest.parent.mkdir(parents=True, exist_ok=True);
            shutil.copyfile(src, dest);
            created.append(rel.as_posix());
        }
    }
    return created;
}
