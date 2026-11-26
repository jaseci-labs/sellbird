import functools;

glob KEYS = frozenset(key(t) for t in ["A", "B"]);

@functools.lru_cache(maxsize=16)
def key(text: str) -> str {
    return text.lower();
}

with entry {
    print(sorted(KEYS));
}
