import json;
import time;

def rows_typed(rows: list[dict[str, any]]) -> int {
    return len(rows);
}

def rows_any(rows: any) -> int {
    return len(rows);
}

def word_typed(text: str) -> str {
    return text.strip();
}

with entry {
    rows = json.loads(json.dumps([{"id": str(i), "name": "Example", "score": i} for i in range(20)]));
    n = 20000;
    t = time.perf_counter();
    for _ in range(n) {
        rows_typed(rows);
    }
    typed = time.perf_counter() - t;
    t = time.perf_counter();
    for _ in range(n) {
        rows_any(rows);
    }
    untyped = time.perf_counter() - t;
    words = json.loads("[\" a \", \" b \"]");
    t = time.perf_counter();
    for _ in range(n * 10) {
        s: str = words[0];
    }
    checked = time.perf_counter() - t;
    t = time.perf_counter();
    for _ in range(n * 10) {
        s2 = str(words[0]);
    }
    plain = time.perf_counter() - t;
    print(f"20 rows into list[dict[str, any]]: {typed / n * 1e6:.2f} us a call; into any: {untyped / n * 1e6:.2f} us");
    print(f"any -> str by annotation: {checked / n / 10 * 1e9:.0f} ns; by str(): {plain / n / 10 * 1e9:.0f} ns");
}
