impl read_user_text(path) -> builtins.str {
    data: any = Path(path).read_bytes();
    try {
        return _newlines(data.decode("utf-8-sig"));
    } except UnicodeDecodeError {
        encoding: any = locale.getencoding();
        logger.warning(
            f"{path} isn't saved as UTF-8; read it as {encoding}. Re-save it as UTF-8 to keep characters like ★ or — intact.",
        );
        return _newlines(data.decode(encoding, errors="replace"));
    }
}

impl _newlines(text: builtins.str) -> builtins.str {
    return text.replace("\r\n", "\n").replace("\r", "\n");
}

impl utf8_stdio(*streams_) -> any {
    streams: any = tuple(streams_);
    for stream in streams or (sys.stdout, sys.stderr) {
        errors: any = "backslashreplace" if stream is sys.stderr else "replace";
        try {
            stream.reconfigure(encoding="utf-8", errors=errors);
        } except (AttributeError, ValueError, OSError) {}
    }
}
