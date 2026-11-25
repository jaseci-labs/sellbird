impl max_words(step: int) -> int {
    return (FIRST_EMAIL_MAX_WORDS, FOLLOW_UP_MAX_WORDS, BREAKUP_MAX_WORDS)[min(max(step, 1), 3)
        - 1];
}

impl tidy(text: str) -> str {
    text = (text or "").translate(_TIDY).replace("…", "...");
    return "\n".join(line.rstrip() for line in text.split("\n")).strip();
}

impl words(text: str) -> int {
    return len((text or "").split());
}

impl style_problems(
    subject: str,
    body: str,
    *,
    kind: str = "cold",
    step: int = 1,
    names: any = (),
    shape: bool = True,
) -> list[str] {
    (subject, body) = (subject or "", body or "");
    text = f"{subject}\n{body}";
    for name in [(n or "").strip() for n in names or ()] {
        text = re.sub(re.escape(name), " ", text, flags=re.I) if len(name) >= 3 else text;
    }
    lowered = tidy(text).lower();
    hits = [p for (p, rx) in _TELL_RES if rx.search(lowered)];
    hits += ["not just X but Y"] if _NOT_ONLY_BUT_RE.search(lowered) else [];
    dash = any(c in _DASH_CHARS for c in text) or _SPACED_HYPHEN_RE.search(text);
    formatted = _LIST_LINE_RE.search(body) or _MARKDOWN_RE.search(text);
    cold = kind == "cold" and shape;
    (cap, count, subject_words) = (max_words(step), words(body), words(subject));
    lines = [x.strip() for x in body.split("\n")];
    me_first = cold
        and _SELF_OPENING_RE.match(next((l for l in lines if l and not _GREETING_RE.match(l)), ""));
    checks = [
        (dash, "uses a dash between words; use a period or a comma instead"),
        ("!" in text, "has an exclamation mark"),
        (formatted, "has formatting (a list, bold or a heading); write plain sentences"),
        (hits, "sounds AI-written or salesy: " + ", ".join(f"\"{h}\"" for h in hits[:4])),
        (cold and count > cap, f"is {count} words; email {step} must be {cap} or fewer"),
        (cold and body.count("?") > 1, "asks more than one question; keep the one that matters"),
        (me_first, "opens with \"I\" or \"we\"; open with them, not you"),
        (cold and subject_words > 6, f"subject is {subject_words} words; keep it to 2-5"),
        (
            kind == "reply" and count > REPLY_MAX_WORDS,
            f"is {count} words; a reply must be {REPLY_MAX_WORDS} or fewer",
        ),
    ];
    return [msg for (bad, msg) in checks if bad];
}

impl with_sign_off(body: str, name: str) -> str {
    full = (name or "").strip();
    first = full.split(" ")[0] if full else "";
    if not first {
        return body;
    }
    lines = (body or "").rstrip().split("\n");
    while lines {
        last = lines[-1].strip().lstrip("-~ ").strip();
        m = re.match("^(.*?)[,.]?\\s+(?:-\\s*)?" + re.escape(first) + "\\.?$", last, re.IGNORECASE);
        if not (
            not last
            or _SIGN_OFF_RE.match(last)
            or last.lower().rstrip(",.") in (first.lower(), full.lower())
            or m and _SIGN_OFF_RE.match(m.group(1).strip() + ",")
        ) {
            break;
        }
        lines.pop();
    }
    return "\n".join(lines).rstrip() + "\n\n" + first;
}
