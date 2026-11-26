import re, time, sys
from spam import _fast
_FORMER = re.compile(r"\b(?:former|ex-|retired)\b")
def norm(text): return re.sub(r"[\s\-]+", " ", text.lower()).strip()
def count_words(texts):
    n = 0
    for t in texts: n += len(t.split())
    return n
def is_former(t): return _FORMER.search(t) is not None
texts = [f"Practice-Manager  and Former Owner {i} of the clinic" for i in range(20000)]
def t(f, *a, n=1):
    s = time.perf_counter()
    for _ in range(n): r = f(*a)
    return (time.perf_counter() - s), r
for name, py, nat in [("norm", norm, _fast.norm), ("is_former", is_former, _fast.is_former)]:
    tp = time.perf_counter(); rp = [py(x) for x in texts]; tp = time.perf_counter() - tp
    tn = time.perf_counter(); rn = [nat(x) for x in texts]; tn = time.perf_counter() - tn
    print(name, f"py {tp*1000:.1f} ms  native {tn*1000:.1f} ms  same={rp==rn}")
a, ra = t(count_words, texts, n=20); b, rb = t(_fast.count_words, texts, n=20)
print("count_words", f"py {a*1000:.1f} native {b*1000:.1f} same={ra==rb}")
