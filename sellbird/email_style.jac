import re;

glob FIRST_EMAIL_MAX_WORDS = 60,
     FOLLOW_UP_MAX_WORDS = 50,
     BREAKUP_MAX_WORDS = 30,
     REPLY_MAX_WORDS = 120;

glob _DASH_CHARS = "‒–—―−",
     _SPACED_HYPHEN_RE = re.compile("(?<=\\S) +-{1,3} +(?=\\S)|(?<=\\w)--(?=\\w)"),
     _LIST_LINE_RE = re.compile("(?m)^\\s*(?:[-*•●▪]|\\d{1,2}[.)])\\s+\\S"),
     _MARKDOWN_RE = re.compile("(?m)\\*\\*[^*\\n]+\\*\\*|__[^_\\n]+__|^\\s*#{1,6}\\s");

glob AI_TELLS = tuple(
         ("hope this finds you|hope this email finds you|hope you're doing well|hope you are doing well|hope you're well|"
             "hope all is well|i know you're busy|i know you are busy|reaching out because|i'm reaching out|i am reaching out|"
             "just wanted to|wanted to reach out|just following up|just checking in|following up on my|circling back|"
             "circle back|touch base|i'd love to|i would love to|in today's|fast-paced|picture this|imagine if|"
             "imagine a world|what if i told you|here's the thing|here is the thing|the truth is|funny enough|"
             "let that sink in|worth a quick|quick question|no pressure|no obligation|no strings|would you be open to|"
             "let me know if you're interested|let me know if you are interested|are you the right person|game-changer|"
             "game changer|gamechanger|revolutionize|revolutionise|cutting-edge|cutting edge|next-level|next level|"
             "supercharge|unlock|unleash|elevate|empower|seamless|seamlessly|leverage|leveraging|synergy|synergies|delve|"
             "tapestry|testament to|robust|crucial|pivotal|transformative|transform your|streamline|pain point|pain points|"
             "best-in-class|world-class|low-hanging fruit|move the needle|at the end of the day|a whole new level|"
             "it's not about|it is not about|isn't about|this isn't just|"
             "it's not just|it isn't just|not just a").split("|"),
     ),
     _TELL_RES = tuple(
         (p, re.compile("(?<![\\w-])" + re.escape(p).replace("'", "['’]") + "(?![\\w-])"))
         for p in AI_TELLS,
     ),
     _NOT_ONLY_BUT_RE = re.compile("(?i)\\bnot (?:only|just|merely) [^.?!\\n]{1,60}?\\bbut\\b"),
     _GREETING_RE = re.compile(
         "(?i)^(?:hi|hey|hello|dear|good (?:morning|afternoon))\\b[^\\n]{0,40}$|^\\w[\\w .'-]{0,30},$",
     ),
     _SELF_OPENING_RE = re.compile("(?i)^(?:i|we|i'm|we're|i've|we've|i'd|we'd|my|our)\\b"),
     _TIDY = str.maketrans("‘’‚‛′“”„″    ", "'''''\"\"\"\"    ", "​⁠﻿"),
     _SIGN_OFF_RE = re.compile(
         "(?i)^(?:best|best wishes|thanks|thank you|thanks again|many thanks|cheers|regards|best regards|kind regards|warm regards|warmly|talk soon|speak soon|all the best|sincerely|take care)[,.]?$",
     );

def max_words(step: int) -> int {
    return (FIRST_EMAIL_MAX_WORDS, FOLLOW_UP_MAX_WORDS, BREAKUP_MAX_WORDS)[min(max(step, 1), 3)
        - 1];
}

def tidy(text: str) -> str {
    text = (text or "").translate(_TIDY).replace("…", "...");
    return "\n".join(line.rstrip() for line in text.split("\n")).strip();
}

def words(text: str) -> int {
    return len((text or "").split());
}

def style_problems(
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

def with_sign_off(body: str, name: str) -> str {
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
