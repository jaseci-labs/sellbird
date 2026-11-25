"""Canonical filesystem locations: the user's home folder for config,
knowledge and state.

Config (sellbird.yaml, .env), knowledge (prompts/, skills/) and state (data/)
all live in one home folder. Which folder depends on how the app was
installed, decided once at import:

- ``SELLBIRD_HOME`` set: that folder. Docker pins it to /app, which is not a
  checkout (no pyproject.toml) but is where the volumes are mounted.
- A source checkout (pyproject.toml next to sellbird/): the checkout itself,
  so a clone keeps working in place exactly as before.
- Anything else (a pipx or pip install into site-packages): a per-user
  folder, because site-packages is replaced on every upgrade.

``resolve()`` matters: when the package is reached through a symlink (some
editable installs), a bare ``Path(__file__).parent`` would point into
site-packages and the app would silently read/write the wrong files.
"""

import builtins;

import os;

import sys;

import from pathlib { Path }

import from typing { Mapping }

glob HOME_ENV: any = "SELLBIRD_HOME";

glob APP_DIR: any = "sellbird";

"""The package's parent. neojac builds a checkout into its own
    ``.jac/build/``, and a package running from there is that checkout's."""
def _package_root(module_file: builtins.str) -> Path;

glob PACKAGE_ROOT: any;

glob PROJECT_ROOT: any;

with entry {
    PACKAGE_ROOT = _package_root(__file__);
}

"""True for a source checkout, never for anything inside site-packages."""
def is_checkout(package_root: Path) -> builtins.bool;

"""The per-user data folder each OS expects an app to use."""
def user_home_default(
    platform: builtins.str, env: Mapping[builtins.str, builtins.str], home: Path
) -> Path;

glob env_default_: any;

glob package_root_default_: any;

glob platform_default_: any;

with entry {
    env_default_ = os.environ;
    package_root_default_ = PACKAGE_ROOT;
    platform_default_ = sys.platform;
}

"""First match wins: SELLBIRD_HOME, then a checkout, then the per-user default."""
def resolve_home(
    env: Mapping[builtins.str, builtins.str] = env_default_,
    package_root: Path = package_root_default_,
    platform: builtins.str = platform_default_,
    home: Path | None = None,
) -> Path;

with entry {
    PROJECT_ROOT = resolve_home();
}
