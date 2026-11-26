import asyncio, random, sys
from datetime import datetime, timedelta, timezone
from sellbird.state import StateManager
from sellbird.signals import seed_signal_catalog, SIGNAL_CATALOG
from sellbird.models.company import Company
from sellbird.models.prospect import Prospect

R = random.Random(42)
INDS = ["dental clinic", "roofing contractor", "law firm", "bakery", "saas startup", "accounting"]
CITIES = ["Springfield, IL", "Riverton, WY", "Lakeside, CA", "Fairview, TX", "Greenville, SC"]
FIRST = ["Alex", "Sam", "Jordan", "Taylor", "Casey", "Morgan", "Riley", "Jamie"]
LAST = ["Example", "Sample", "Tester", "Demo", "Placeholder", "Fictional"]
TITLES = ["Owner", "Founder", "CEO", "Practice Manager", "Office Manager"]

async def main(path, nco):
    st = StateManager(path)
    await st.init_db()
    await seed_signal_catalog(st)
    for s in SIGNAL_CATALOG:
        await st.set_signal_status(s["code"], "confirmed")
    base = datetime(2026, 1, 1, tzinfo=timezone.utc)
    for i in range(nco):
        ind = R.choice(INDS)
        c = Company(name=f"Example Co {i}", domain=f"example{i}.example.com",
                    website=f"https://example{i}.example.com", industry=ind,
                    location=R.choice(CITIES), description=f"A fictional {ind} number {i}.",
                    source="seed", tech_stack=R.sample(["WordPress", "HubSpot", "Shopify", "Intercom"], 2))
        cid = await st.add_company(c)
        rows = []
        for s in SIGNAL_CATALOG:
            if R.random() < 0.4:
                vt = s["value_type"]
                rows.append(dict(company_id=cid, signal_code=s["code"], collector="seed",
                                 value_num=(R.randint(1, 40) if vt == "num" else (1 if vt == "bool" else None)),
                                 value_text=(f"text {R.randint(1, 9)}" if vt == "text" else ""),
                                 confidence=0.9))
        await st.add_observations(rows, run_id="seed")
        for j in range(R.randint(0, 2)):
            st_ = R.choice(["verified", "risky", "guess"])
            p = Prospect(company_id=cid, first_name=R.choice(FIRST), last_name=R.choice(LAST),
                         email=f"p{j}@example{i}.example.com", email_status=st_, email_verified=st_ == "verified",
                         title=R.choice(TITLES), source="seed", score=R.randint(0, 100),
                         company=c.name, industry=ind, personalization_notes="Fictional note.")
            pid = await st.add_prospect(p)
            if R.random() < 0.3:
                await st.add_outbox_item(prospect_id=pid, to_email=p.email, subject=f"Quick idea {i}",
                                         body="Hi there,\n\nA fictional body.\n\nThanks", 
                                         send_at=(base + timedelta(hours=i)).isoformat(),
                                         campaign_id=f"camp{i % 7}", step=1)
asyncio.run(main(sys.argv[1], int(sys.argv[2])))
