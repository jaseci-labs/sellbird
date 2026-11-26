"""In-process workloads (dashboard endpoints, page reading): each side run in
turn, the order rotating every round; median of N rounds, outputs compared."""
import json
import os
import statistics
import subprocess
import sys

REPO, BASE, PY, PERF = (os.environ[k] for k in ("REPO", "SELLBIRD_BASE", "PY", "PERF_DIR"))
SITE = {"base": BASE, "jac": f"{REPO}/.jac/build/pypi/top/site"}
if os.environ.get("JAC_BEFORE"):
    SITE["before"] = os.environ["JAC_BEFORE"]
SIDES = list(SITE)
HERE = os.path.dirname(os.path.abspath(__file__))
N = int(sys.argv[1])
out = sys.argv[2]


def run(side, script, *args):
    home = f"{PERF}/home_{side}"
    env = dict(os.environ, PYTHONPATH=SITE[side], SELLBIRD_HOME=home)
    res = f"{PERF}/{side}_{os.path.basename(script)}.json"
    subprocess.run([PY, f"{HERE}/{script}", *args, res], env=env, cwd=home, check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return json.load(open(res))


def same_body(a, b):
    if a == b:
        return True
    if a[0] == b[0]:
        try:
            return "same-json" if json.loads(a[1]) == json.loads(b[1]) else False
        except ValueError:
            pass
    return False


report = {"load": [], "dash": {}, "pages": {}}
dash = {s: [] for s in SIDES}
pages = {s: [] for s in SIDES}
for i in range(N):
    for side in SIDES[i % len(SIDES):] + SIDES[:i % len(SIDES)]:
        dash[side].append(run(side, "dash_bench.py", "5"))
        pages[side].append(run(side, "pages_bench.py", "2", "40"))
    report["load"].append(os.getloadavg()[0])
for ep in dash["base"][0]["times"]:
    row = {s: statistics.median(r["times"][ep] for r in dash[s]) for s in SIDES}
    row["same"] = {s: same_body(dash["base"][-1]["bodies"][ep], dash[s][-1]["bodies"][ep]) for s in SIDES}
    report["dash"][ep] = row
    cols = "  ".join(f"{s} {row[s] * 1000:8.2f} ms" for s in SIDES)
    print(f"{ep:36s} {cols}  base/jac x{row['base'] / row['jac']:5.2f}  {row['same']['jac']}")
row = {s: statistics.median(r["ms"] for r in pages[s]) for s in SIDES}
row["same"] = all({r["hash"] for r in pages[s]} == {r["hash"] for r in pages["base"]} for s in SIDES)
report["pages"] = row
cols = "  ".join(f"{s} {row[s]:8.1f} ms" for s in SIDES)
print(f"{'read 40 pages twice':36s} {cols}  base/jac x{row['base'] / row['jac']:5.2f}  {row['same']}")
print(f"load median {statistics.median(report['load']):.2f}")
json.dump(report, open(out, "w"), indent=1)
