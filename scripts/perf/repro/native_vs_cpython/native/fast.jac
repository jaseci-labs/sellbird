import re;

glob _FORMER = re.compile("\\b(?:former|ex-|retired)\\b");

def:pub norm(text: str) -> str {
    return re.sub("[\\s\\-]+", " ", text.lower()).strip();
}

def:pub count_words(texts: list[str]) -> int {
    n = 0;
    for t in texts {
        n += len(t.split());
    }
    return n;
}

def:pub is_former(t: str) -> bool {
    return _FORMER.search(t) is not None;
}

def:pub score_text(t: str) -> int {
    s = 0;
    for ch in t {
        o = ord(ch);
        if o >= 97 and o <= 122 {
            s = (s * 31 + o) % 1000003;
        } elif o == 32 {
            s += 7;
        }
    }
    return s;
}

def:pub dict_work(n: int) -> int {
    d: dict[str, int] = {};
    for i in range(n) {
        k = "k" + str(i % 1000);
        d[k] = d.get(k, 0) + i;
    }
    return len(d);
}
