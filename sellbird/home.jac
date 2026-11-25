import shutil;
import sys;
import from pathlib { Path }

glob SEED_GLOBS = ("prompts/*.md", "skills/*.md", "sellbird.yaml", ".env.example");

def bundled_defaults -> Path | None {
    if paths.is_checkout(paths.PACKAGE_ROOT) {
        return paths.PACKAGE_ROOT;
    }
    shared = Path(sys.prefix) / "share" / paths.APP_DIR;
    return shared if shared.is_dir() else None;
}

def seed_home(home: Path, source: Path | None) -> list[str] {
    home = Path(home);
    (home / "data").mkdir(parents=True, exist_ok=True);
    if source is None or Path(source).resolve() == home.resolve() {
        return [];
    }
    source = Path(source);
    created: list[str] = [];
    for pattern in SEED_GLOBS {
        for src in sorted(source.glob(pattern)) {
            rel = src.relative_to(source);
            dest = home / rel;
            if src.is_file() and not (dest.exists() or dest.is_symlink()) {
                dest.parent.mkdir(parents=True, exist_ok=True);
                shutil.copyfile(src, dest);
                created.append(rel.as_posix());
            }
        }
    }
    return created;
}
