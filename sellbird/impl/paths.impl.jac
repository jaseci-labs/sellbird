impl _package_root(module_file: builtins.str) -> Path {
    `root: any = Path(module_file).resolve().parent.parent;
    if ".jac" in `root.parts {
        checkout: any = Path(*`root.parts[:`root.parts.index(".jac")]);
        if (checkout / "jac.toml").is_file() {
            return checkout;
        }
    }
    return `root;
}

impl is_checkout(package_root: Path) -> builtins.bool {
    package_root = Path(package_root);
    package: any = package_root / "sellbird";
    return (package_root / "pyproject.toml").is_file()
        and ((package / "__init__.py").is_file() or (package / "__init__.jac").is_file())
        and "site-packages" not in package_root.parts;
}

impl user_home_default(
    platform: builtins.str, env: Mapping[builtins.str, builtins.str], home: Path
) -> Path {
    home = Path(home);
    if platform == "darwin" {
        return home / "Library" / "Application Support" / APP_DIR;
    }
    if platform == "win32" {
        appdata: any = env.get("APPDATA");
        return Path(appdata) / APP_DIR if appdata else home / "AppData" / "Roaming" / APP_DIR;
    }
    return Path(env.get("XDG_DATA_HOME") or home / ".local" / "share") / APP_DIR;
}

impl resolve_home(
    env: Mapping[builtins.str, builtins.str] = env_default_,
    package_root: Path = package_root_default_,
    platform: builtins.str = platform_default_,
    home: Path | None = None,
) -> Path {
    `override: any = (env.get(HOME_ENV) or "").strip();
    if `override {
        return Path(`override).expanduser().resolve();
    }
    if is_checkout(package_root) {
        return Path(package_root);
    }
    return user_home_default(platform, env, Path.home() if home is None else home);
}
