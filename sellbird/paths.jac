import os;
import sys;
import from pathlib { Path }
import from typing { Mapping }

glob HOME_ENV = "SELLBIRD_HOME",
     APP_DIR = "sellbird";

def _package_root(module_file: str) -> Path {
    top = Path(module_file).resolve().parent.parent;
    checkout = Path(*top.parts[:top.parts.index(".jac")]) if ".jac" in top.parts else top;
    return checkout if (checkout / "jac.toml").is_file() else top;
}

glob PACKAGE_ROOT = _package_root(__file__);

def is_checkout(package_root: Path) -> bool {
    package = Path(package_root) / "sellbird";
    return (Path(package_root) / "pyproject.toml").is_file()
        and ((package / "__init__.py").is_file() or (package / "__init__.jac").is_file())
        and "site-packages" not in Path(package_root).parts;
}

def user_home_default(platform: str, env: Mapping[str, str], home: Path) -> Path {
    home = Path(home);
    if platform == "darwin" {
        return home / "Library" / "Application Support" / APP_DIR;
    }
    if platform == "win32" {
        appdata = env.get("APPDATA");
        return Path(appdata) / APP_DIR if appdata else home / "AppData" / "Roaming" / APP_DIR;
    }
    return Path(env.get("XDG_DATA_HOME") or home / ".local" / "share") / APP_DIR;
}

def resolve_home(
    env: Mapping[str, str] = os.environ,
    package_root: Path = PACKAGE_ROOT,
    platform: str = sys.platform,
    home: Path | None = None,
) -> Path {
    pinned = (env.get(HOME_ENV) or "").strip();
    if pinned {
        return Path(pinned).expanduser().resolve();
    }
    if is_checkout(package_root) {
        return Path(package_root);
    }
    return user_home_default(platform, env, Path.home() if home is None else home);
}

glob PROJECT_ROOT = resolve_home();
