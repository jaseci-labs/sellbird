impl max_words(step: builtins.int) -> builtins.int {
    if step <= 1 {
        return FIRST_EMAIL_MAX_WORDS;
    }
    if step == 2 {
        return FOLLOW_UP_MAX_WORDS;
    }
    return BREAKUP_MAX_WORDS;
}

impl tidy(text: builtins.str) -> builtins.str {
    text = (text or "").translate(_TIDY).replace("…", "...");
    return "\n".join(line.rstrip() for line in text.split("\n")).strip();
}

impl words(text: builtins.str) -> builtins.int {
    return len((text or "").split());
}

impl _blank(text: builtins.str, names) -> builtins.str {
    name: any;
    for name in names or () {
        name = (name or "").strip();
        if len(name) >= 3 {
            text = re.sub(re.escape(name), " ", text, flags=re.IGNORECASE);
        }
    }
    return text;
}

impl _first_line(body: builtins.str) -> builtins.str {
    line: any;
    lines: any = [line.strip() for line in body.split("\n") if line.strip()];
    for line in lines {
        if _GREETING_RE.match(line) {
            continue;
        }
        return line;
    }
    return "";
}

impl style_problems(
    subject: builtins.str,
    body: builtins.str,
    *,
    kind: builtins.str = "cold",
    step: builtins.int = 1,
    names=(),
    shape: builtins.bool = True,
) -> builtins.list[builtins.str] {
    subject = subject or "";
    body = body or "";
    text: any = _blank(f"{subject}\n{body}", names);
    lowered: any = tidy(text).lower();
    reasons: builtins.list[builtins.str] = [];

    dashes: any = sorted({c for c in text if c in _DASH_CHARS});
    if dashes or _SPACED_HYPHEN_RE.search(text) {
        reasons.append("uses a dash between words; use a period or a comma instead");
    }
    if "!" in text {
        reasons.append("has an exclamation mark");
    }
    if _LIST_LINE_RE.search(body) or _MARKDOWN_RE.search(text) {
        reasons.append("has formatting (a list, bold or a heading); write plain sentences");
    }

    hits: any = [phrase for (phrase, rx) in _TELL_RES if rx.search(lowered)];
    if _NOT_ONLY_BUT_RE.search(lowered) {
        hits.append("not just X but Y");
    }
    if hits {
        shown: any = ", ".join(f"\"{h}\"" for h in hits[:4]);
        reasons.append(f"sounds AI-written or salesy: {shown}");
    }

    if kind == "cold" and shape {
        cap: any = max_words(step);
        count: any = words(body);
        if count > cap {
            reasons.append(f"is {count} words; email {step} must be {cap} or fewer");
        }
        if body.count("?") > 1 {
            reasons.append("asks more than one question; keep the one that matters");
        }
        if _SELF_OPENING_RE.match(_first_line(body)) {
            reasons.append("opens with \"I\" or \"we\"; open with them, not you");
        }
        if words(subject) > 6 {
            reasons.append(f"subject is {words(subject)} words; keep it to 2-5");
        }
    } elif kind == "reply" and words(body) > REPLY_MAX_WORDS {
        reasons.append(f"is {words(body)} words; a reply must be {REPLY_MAX_WORDS} or fewer");
    }
    return reasons;
}

impl with_sign_off(body: builtins.str, name: builtins.str) -> builtins.str {
    first: any = (name or "").strip().split(" ")[0] if (name or "").strip() else "";
    if not first {
        return body;
    }
    full: any = (name or "").strip().lower();
    lines: any = (body or "").rstrip().split("\n");
    while lines {
        last: any = lines[-1].strip().lstrip("-~ ").strip();
        low: any = last.lower().rstrip(",.");
        if not last or _SIGN_OFF_RE.match(last) or low in (first.lower(), full) {
            lines.pop();
            continue;
        }
        m: any = re.match(
            "^(.*?)[,.]?\\s+(?:-\\s*)?" + re.escape(first) + "\\.?$", last, re.IGNORECASE
        );
        if m and _SIGN_OFF_RE.match(m.group(1).strip() + ",") {
            lines.pop();
            continue;
        }
        break;
    }
    return "\n".join(lines).rstrip() + "\n\n" + first;
}
