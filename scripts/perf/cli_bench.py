"""Start-up and CLI commands: each side run in turn (the order rotating every
round), median wall time of N rounds, stdout and exit code compared with base."""
import json
import os
import statistics
import subprocess
import sys
import time

REPO, BASE, PY, PERF = (os.environ[k] for k in ("REPO", "SELLBIRD_BASE", "PY", "PERF_DIR"))
SITE = {"base": BASE, "jac": f"{REPO}/.jac/build/pypi/top/site"}
if os.environ.get("JAC_BEFORE"):
    SITE["before"] = os.environ["JAC_BEFORE"]
SIDES = list(SITE)
CMDS = [
    ("python -c pass", ["-c", "pass"]),
    ("import sellbird.cli", ["-c", "import sellbird.cli"]),
    ("import sellbird.dashboard", ["-c", "import sellbird.dashboard"]),
    ("import sellbird.mcp_server", ["-c", "import sellbird.mcp_server"]),
    ("import sellbird.main", ["-c", "import sellbird.main"]),
    ("sellbird --help", ["-m", "sellbird", "--help"]),
    ("sellbird status", ["-m", "sellbird", "status"]),
    ("sellbird signals", ["-m", "sellbird", "signals"]),
    ("sellbird export --all", ["-m", "sellbird", "export", "--all"]),
    ("sellbird companies", ["-m", "sellbird", "companies"]),
    ("sellbird discover --providers", ["-m", "sellbird", "discover", "--providers"]),
    ("sellbird outbox", ["-m", "sellbird", "outbox"]),
    ("sellbird suppressions", ["-m", "sellbird", "suppressions"]),
    ("sellbird sending status", ["-m", "sellbird", "sending", "status"]),
]
N = int(sys.argv[1])
out = sys.argv[2]
only = sys.argv[3:]
res = {}
for name, args in CMDS:
    if only and not any(o in name for o in only):
        continue
    ts = {s: [] for s in SIDES}
    outs = {}
    loads = []
    for i in range(N):
        for side in SIDES[i % len(SIDES):] + SIDES[:i % len(SIDES)]:
            home = f"{PERF}/home_{side}"
            env = dict(os.environ, PYTHONPATH=SITE[side], SELLBIRD_HOME=home)
            t = time.perf_counter()
            p = subprocess.run([PY] + args, env=env, cwd=home, capture_output=True)
            ts[side].append(time.perf_counter() - t)
            outs[side] = (p.returncode, p.stdout.replace(f"home_{side}".encode(), b"HOME"))
        loads.append(os.getloadavg()[0])
    row = {s: statistics.median(ts[s]) for s in SIDES}
    row["same"] = all(outs[s] == outs["base"] for s in SIDES)
    row["load"] = statistics.median(loads)
    res[name] = row
    cols = "  ".join(f"{s} {row[s] * 1000:7.1f} ms" for s in SIDES)
    print(f"{name:32s} {cols}  base/jac x{row['base'] / row['jac']:4.2f}  "
          f"{'same' if row['same'] else 'DIFF'}  load {row['load']:.2f}", flush=True)
json.dump(res, open(out, "w"), indent=1)
