import sys, time, json, statistics, logging
logging.disable(logging.INFO)
from fastapi.testclient import TestClient
import sellbird.dashboard as dash
N = int(sys.argv[1]); out = sys.argv[2]
EPS = ["/api/setup-status", "/api/settings", "/api/offer", "/api/company", "/api/companies",
       "/api/export/companies.csv", "/api/sellbird/status", "/api/stats", "/api/prospects",
       "/api/outbox", "/api/sending-mode", "/api/export/prospects.csv", "/api/campaigns",
       "/api/conversations", "/api/trend", "/api/activity", "/api/discover/providers",
       "/api/today", "/api/signals", "/api/cohort.csv?require=SERP_RANK", "/api/runs", "/api/usage",
       "/", "/app.js"]
tok = dash.token_store.get()
res = {}; bodies = {}
with TestClient(dash.app, base_url="http://127.0.0.1:5555", headers={"Authorization": f"Bearer {tok}"}) as c:
    for ep in EPS:
        ts = []
        for i in range(N):
            t = time.perf_counter(); r = c.get(ep); ts.append(time.perf_counter() - t)
        res[ep] = statistics.median(ts)
        bodies[ep] = (r.status_code, r.content.decode("utf-8", "replace"))
json.dump({"times": res, "bodies": bodies}, open(out, "w"))
