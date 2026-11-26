import sys, collections, runpy, atexit, time, os
import _jac_sellbird as J
C = collections.Counter(); N = collections.Counter()
orig = J.convert
depth = [0]
pc = time.perf_counter
def convert(v, want):
    if depth[0]:
        return orig(v, want)
    f = sys._getframe(1)
    k = (f.f_code.co_filename.split("ethanplusai_sellbird/")[-1], f.f_lineno, str(getattr(want, "__name__", want))[:60])
    depth[0] = 1
    t = pc()
    try:
        return orig(v, want)
    finally:
        C[k] += pc() - t; N[k] += 1; depth[0] = 0
J.convert = convert
def dump():
    tot = sum(C.values())
    out = open(os.environ.get("CVOUT", "/dev/stderr"), "w")
    out.write(f"TOTAL convert time {tot*1000:.1f} ms over {sum(N.values())} top-level calls\n")
    for k, t in C.most_common(int(os.environ.get("TOPN", "30"))):
        out.write(f"{t*1000:8.2f} ms {N[k]:7d} {k[0]}:{k[1]} -> {k[2]}\n")
atexit.register(dump)
mode = sys.argv[1]; sys.argv = sys.argv[1:]
if mode == "-m":
    sys.argv = sys.argv[1:]; runpy.run_module(sys.argv[0], run_name="__main__", alter_sys=True)
else:
    runpy.run_path(sys.argv[0], run_name="__main__")
