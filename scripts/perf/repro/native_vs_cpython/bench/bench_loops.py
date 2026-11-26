import time
from spam import _fast
def score_text(t):
    s = 0
    for ch in t:
        o = ord(ch)
        if 97 <= o <= 122: s = (s * 31 + o) % 1000003
        elif o == 32: s += 7
    return s
def dict_work(n):
    d = {}
    for i in range(n):
        k = "k" + str(i % 1000)
        d[k] = d.get(k, 0) + i
    return len(d)
txt = "the quick brown fox jumps over the lazy dog " * 2000
for name, py, nat, arg in [("score_text", score_text, _fast.score_text, txt), ("dict_work", dict_work, _fast.dict_work, 300000)]:
    a = time.perf_counter(); ra = py(arg); a = time.perf_counter() - a
    b = time.perf_counter(); rb = nat(arg); b = time.perf_counter() - b
    print(name, f"py {a*1000:.1f} native {b*1000:.1f} same={ra==rb}")
