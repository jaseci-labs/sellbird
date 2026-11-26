"""Alternate the original and the Jac build on the in-process workloads
(dashboard endpoints, page reading); median of N runs each, outputs compared."""
import json, os, statistics, subprocess, sys
REPO, BASE, PY, PERF = (os.environ[k] for k in ("REPO", "SELLBIRD_BASE", "PY", "PERF_DIR"))
SITE = {"base": BASE, "jac": f"{REPO}/.jac/build/pypi/top/site"}
HERE = os.path.dirname(os.path.abspath(__file__))
N = int(sys.argv[1]); out = sys.argv[2]


def run(side, script, *args):
    home = f"{PERF}/home_{side}"
    env = dict(os.environ, PYTHONPATH=SITE[side], SELLBIRD_HOME=home)
    res = f"{PERF}/{side}_{os.path.basename(script)}.json"
    subprocess.run([PY, f"{HERE}/{script}", *args, res], env=env, cwd=home, check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return json.load(open(res))


report = {"load": [], "dash": {}, "pages": {}}
dash = {"base": [], "jac": []}; pages = {"base": [], "jac": []}
for i in range(N):
    for side in (("base", "jac") if i % 2 == 0 else ("jac", "base")):
        dash[side].append(run(side, "dash_bench.py", "5"))
        pages[side].append(run(side, "pages_bench.py", "2", "40"))
    report["load"].append(os.getloadavg()[0])
for ep in dash["base"][0]["times"]:
    b = statistics.median(r["times"][ep] for r in dash["base"])
    j = statistics.median(r["times"][ep] for r in dash["jac"])
    bb, jb = dash["base"][-1]["bodies"][ep], dash["jac"][-1]["bodies"][ep]
    same = bb == jb
    if not same and bb[0] == jb[0]:
        try:
            same = "same-json" if json.loads(bb[1]) == json.loads(jb[1]) else False
        except ValueError:
            pass
    report["dash"][ep] = {"base": b, "jac": j, "same": same}
    print(f"{ep:40s} base {b*1000:8.2f} ms  jac {j*1000:8.2f} ms  x{b/j:5.2f}  {same}")
pb = statistics.median(r["ms"] for r in pages["base"]); pj = statistics.median(r["ms"] for r in pages["jac"])
same = {r["hash"] for r in pages["base"]} == {r["hash"] for r in pages["jac"]}
report["pages"] = {"base": pb, "jac": pj, "same": same}
print(f"{'read 40 pages x2':40s} base {pb:8.1f} ms  jac {pj:8.1f} ms  x{pb/pj:5.2f}  {same}")
print(f"load median {statistics.median(report['load']):.2f}")
json.dump(report, open(out, "w"), indent=1)
