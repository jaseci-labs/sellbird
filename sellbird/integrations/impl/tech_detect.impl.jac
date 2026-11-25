impl _get_compiled -> builtins.dict[builtins.str, builtins.list[re.Pattern]] {
    if _compiled is None {
        _compiled = {
            name: [re.compile(p, re.IGNORECASE) for p in patterns]
            for (name, patterns) in FINGERPRINTS.items()
        };
    }
    return _compiled;
}

impl detect_tech(
    html: builtins.str, max_bytes: builtins.int = 300000
) -> builtins.list[builtins.str] {
    sample: any;
    if not html {
        return [];
    }
    sample = html[:max_bytes];
    found: any = [];
    for (name, patterns) in _get_compiled().items() {
        if `any(p.search(sample) for p in patterns) {
            found.append(name);
        }
    }
    return sorted(found);
}
