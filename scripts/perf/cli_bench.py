"""Alternate base/jac runs of each command; report medians and load."""
import subprocess, sys, time, statistics, json, os
REPO = os.environ["REPO"]
BASE = os.environ["SELLBIRD_BASE"]
PY = os.environ["PY"]
SITE = {"base": BASE, "jac": REPO + "/.jac/build/pypi/top/site"}
ENV = dict(os.environ, HOME=os.environ["HOME"], CLAUDE_CONFIG_DIR=os.environ["CLAUDE_CONFIG_DIR"],
           PYTHONSAFEPATH="1")
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
N = int(sys.argv[1]); out = sys.argv[2]
only = sys.argv[3:] 
res = {}
for name, args in CMDS:
    if only and not any(o in name for o in only): continue
    ts = {"base": [], "jac": []}; outs = {}
    loads = []
    for i in range(N):
        for w in (("base", "jac") if i % 2 == 0 else ("jac", "base")):
            env = dict(ENV, PYTHONPATH=SITE[w], SELLBIRD_HOME=os.path.join(os.environ["PERF_DIR"], f"home_{w}"))
            t = time.perf_counter()
            p = subprocess.run([PY] + args, env=env, cwd=os.path.join(os.environ["PERF_DIR"], f"home_{w}"), capture_output=True)
            ts[w].append(time.perf_counter() - t)
            outs[w] = (p.returncode, p.stdout.replace(f"home_{w}".encode(), b"HOME"), p.stderr.replace(f"home_{w}".encode(), b"HOME"))
        loads.append(os.getloadavg()[0])
    same = outs["base"][:2] == outs["jac"][:2]
    mb, mj = statistics.median(ts["base"]), statistics.median(ts["jac"])
    res[name] = dict(base=mb, jac=mj, same=same, load=statistics.median(loads), rc=(outs["base"][0], outs["jac"][0]))
    print(f"{name:34s} base {mb*1000:7.1f} ms  jac {mj*1000:7.1f} ms  x{mb/mj:5.2f}  {'same' if same else 'DIFF'} rc={res[name]['rc']} load={res[name]['load']:.2f}", flush=True)
json.dump(res, open(out, "w"), indent=1)
