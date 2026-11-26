"""The checks every outgoing email passes: pre_send_check, and the autopilot
review that looks for links, phone numbers and quoted instructions."""
import json
import sys
import time
from types import SimpleNamespace

from sellbird import gate
from sellbird.paths import PROJECT_ROOT

reps = int(sys.argv[1])
config = SimpleNamespace(
    channels=SimpleNamespace(email=SimpleNamespace(link_domains=["example.com"], booking_link="")),
    company=SimpleNamespace(website="https://example.com", phone="+1 555 0100"),
    booking=SimpleNamespace(link="", calendar_link=""),
)
bodies = [
    f"Hi Alex,\n\nI noticed Example Dental {i} has no online booking on its site. That likely costs you "
    "new patients each week, since most people book after hours.\n\nWant me to send a mockup of your "
    "homepage with booking added? See https://example.com/work for two we did.\n\nSam\n123 Example St"
    for i in range(50)
]
out = []
t = time.perf_counter()
for r in range(reps):
    for i, body in enumerate(bodies):
        res = gate.pre_send_check(f"alex{i}@example{i}.example.com", "Quick idea", body,
                                  postal_address="123 Example St")
        rev = gate.autopilot_review("Quick idea", body, config, root=PROJECT_ROOT)
        if r == 0:
            out.append([res.ok, list(res.reasons), rev])
el = time.perf_counter() - t
json.dump({"ms": el * 1000, "out": out}, open(sys.argv[2], "w"))
