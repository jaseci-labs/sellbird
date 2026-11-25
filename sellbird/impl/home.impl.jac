impl bundled_defaults -> Path | None {
    if paths.is_checkout(paths.PACKAGE_ROOT) {
        return paths.PACKAGE_ROOT;
    }
    shared: any = Path(sys.prefix) / "share" / paths.APP_DIR;
    return shared if shared.is_dir() else None;
}

impl seed_home(home: Path, source: Path | None) -> builtins.list[builtins.str] {
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
