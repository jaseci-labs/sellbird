import sys, time, json, hashlib, random
from sellbird.collectors import people, profile, ats, discover
from sellbird.integrations import tech_detect
from sellbird import email_style
R = random.Random(7)
FIRST = ["Alex", "Sam", "Jordan", "Taylor", "Casey", "Morgan", "Riley", "Jamie", "Camille", "Hélène"]
LAST = ["Example", "Sample", "Tester", "Demo", "Placeholder", "Fictional", "Lefictif"]
TITLES = ["Owner", "Founder & CEO", "Practice Manager", "Office Manager", "Présidente", "Hygienist", "Co-founder"]
def page(i):
    cards = "".join(f'<div class="team-card"><h3>{R.choice(FIRST)} {R.choice(LAST)}</h3><p>{R.choice(TITLES)}</p></div>' for _ in range(8))
    prose = f"<p>Example Dental {i} is owned and operated by Dr. {R.choice(FIRST)} {R.choice(LAST)}, who founded the practice in 2009. " + \
            "We are proud to serve the community with gentle, modern care. " * 20 + "</p>"
    nav = "".join(f'<li><a href="/{p}">{p.title()}</a></li>' for p in ["about", "team", "meet-the-doctor", "services", "contact", "blog", "careers"])
    scripts = '<script src="https://js.hs-scripts.com/123.js"></script><script src="https://widget.intercom.io/w/x"></script><link href="https://cdn.shopify.com/x.css">'
    schema = '<script type="application/ld+json">{"@context":"https://schema.org","@type":"Dentist","name":"Example Dental %d","founder":{"@type":"Person","name":"Alex Example","jobTitle":"Owner"}}</script>' % i
    funding = "<p>Example Co announced its $4M seed round led by Example Ventures in March 2026. Backed by Y Combinator (W24).</p>"
    jobs = '<a href="https://boards.greenhouse.io/example%d">Careers</a>' % i
    return f"<html><head><title>Example Dental {i} | Family Dentist</title>{scripts}{schema}</head><body><nav><ul>{nav}</ul></nav><main>{cards}{prose}{funding}{jobs}<p>Contact: hello@example{i}.example.com, info [at] example{i} [dot] example [dot] com</p></main><footer>&copy; 2026</footer></body></html>" * 3
PAGES = [page(i) for i in range(int(sys.argv[2]))]
reps = int(sys.argv[1])
out = []
t = time.perf_counter()
for r in range(reps):
    for i, html in enumerate(PAGES):
        dom = f"example{i}.example.com"; url = f"https://{dom}/team"
        res = {
            "people": people.find_people([(url, html)], dom, f"Example Dental {i}"),
            "menu": people.menu_links(html, url),
            "emails": people.emails_on_page(html),
            "tech": tech_detect.detect_tech(html),
            "yc": profile.yc_backed(html, dom),
            "acc": profile.accelerators(html, dom),
            "fund": profile.funding_round(html, dom, url),
            "board": repr(ats.detect_board(html, dom)),
            "site": discover.site_name_from_html(html, dom),
            "junk": discover.is_junk(dom, f"Example Dental {i}"),
            "titles": [people.title_matches(tt, ["owner", "practice manager"]) for tt in TITLES],
            "rank": [people.owner_rank(tt) for tt in TITLES],
            "style": email_style.style_problems("Quick idea", "Hi Alex,\n\nI noticed your site has no online booking. That costs you new patients every week.\n\nWant a mockup?\n\nSam", step=1),
        }
        if r == 0: out.append(res)
el = time.perf_counter() - t
h = hashlib.sha256(json.dumps(out, sort_keys=True, default=str).encode()).hexdigest()[:16]
json.dump({"ms": el * 1000, "hash": h}, open(sys.argv[3], "w"))
