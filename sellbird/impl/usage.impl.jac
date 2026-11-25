impl claude_config_dir -> Path {
    `override: any = os.environ.get("CLAUDE_CONFIG_DIR", "").strip();
    if `override {
        return Path(`override).expanduser();
    }
    return Path.home() / ".claude";
}
