impl SendHookError.__repr__ -> str {
    return (getattr(builtins.super(SendHookError, self), "__repr__") as any)();
}

impl SendHookError.__eq__(other: any) -> bool {
    return self is other;
}

impl SendHookError.__hash__ -> int {
    return id(self);
}

impl first_verdict(rules: dict[str, SendRule], check: SendCheck) -> tuple[str, str] | None {
    for (name, rule) in rules.items() {
        try {
            verdict: any = await rule(check);
        } except Exception as e {
            logger.error(f"Send rule {name!r} failed; holding the email: {e}", exc_info=True);
            return ("approved", f"held: {name} couldn't check it");
        }
        if verdict is None {
            continue;
        }
        if isinstance(verdict, Cancel) {
            return ("cancelled", f"{name}: {verdict.reason}"[:300]);
        }
        if isinstance(verdict, Hold) {
            return ("approved", f"held: {name}: {verdict.reason}"[:300]);
        }
        logger.error(f"Send rule {name!r} returned {verdict!r}; holding the email.");
        return ("approved", f"held: {name} gave no clear answer");
    }
    return None;
}

impl extra_headers(hooks: dict[str, HeaderHook], item: dict) -> list[tuple[str, str]] {
    out: list[tuple[str, str]] = [];
    for (name, hook) in hooks.items() {
        header: any;
        value: any;
        for (header, value) in hook(item) or () {
            (header, value) = (`str(header), `str(value));
            if not _HEADER_NAME.match(header) or header.lower() in RESERVED_HEADERS {
                raise SendHookError(f"{name} added a header Sellbird can't send: {header!r}");
            }
            if "\r" in value or "\n" in value {
                raise SendHookError(f"{name} added a header value with a line break: {header}");
            }
            out.append((header, value));
        }
    }
    return out;
}
