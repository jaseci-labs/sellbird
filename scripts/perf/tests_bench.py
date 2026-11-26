"""The test suite of each side, in its own checkout, in turn (order rotating);
median wall time of N rounds and the pass/fail counts of each."""
import json
import os
import re
import statistics
import subprocess
import sys
import time

REPO, BASE, PY, PERF = (os.environ[k] for k in ("REPO", "SELLBIRD_BASE", "PY", "PERF_DIR"))
# Each side: (checkout whose tests/ run, what goes on PYTHONPATH)
SIDES = {"base": (BASE, BASE), "jac": (REPO, f"{REPO}/.jac/build/pypi/top/site")}
if os.environ.get("JAC_BEFORE_CHECKOUT"):
    c = os.environ["JAC_BEFORE_CHECKOUT"]
    SIDES["before"] = (c, f"{c}/.jac/build/pypi/top/site")
names = list(SIDES)
N = int(sys.argv[1])
out = sys.argv[2]
ts = {s: [] for s in names}
summary = {}
loads = []
for i in range(N):
    for side in names[i % len(names):] + names[:i % len(names)]:
        checkout, path = SIDES[side]
        env = {k: v for k, v in os.environ.items() if k != "SELLBIRD_HOME"}
        env["PYTHONPATH"] = path
        t = time.perf_counter()
        p = subprocess.run([PY, "-m", "pytest", "-q", "-p", "no:cacheprovider", "--import-mode=append",
                            "tests"], cwd=checkout, env=env, capture_output=True, text=True)
        ts[side].append(time.perf_counter() - t)
        summary[side] = re.findall(r"^.*\d+ passed.*$", p.stdout, re.M)[-1:]
        print(f"round {i} {side}: {ts[side][-1]:.1f} s  {summary[side]}", flush=True)
    loads.append(os.getloadavg()[0])
res = {s: {"median_s": statistics.median(ts[s]), "runs": ts[s], "summary": summary[s]} for s in names}
res["load"] = statistics.median(loads)
for s in names:
    print(f"{s:7s} median {res[s]['median_s']:.1f} s  {res[s]['summary']}")
print(f"load median {res['load']:.2f}")
json.dump(res, open(out, "w"), indent=1)
