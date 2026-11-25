"""What Sellbird has already read off a company's own website, for the writer.

The free homepage signals (missing structured data, a site nobody has
touched in months, ...) sit in ``observations`` and show up
in cohorts and the dashboard, but the writer's prompt only carried the
company's description, detected tools and a few other signals. An email that
should name one concrete thing the sender would change had nothing true to
name, so it said it hadn't looked.

This turns the findings that are actually true into fact lines. Every line
says how it was found and that the check can miss things, so the writer
hedges instead of presenting a scan as an audit. A signal checked and found
absent is not a fact and is left out.

NO_ONLINE_BOOKING is deliberately not here. A booking widget that loads late,
or a "book" button on another page, is invisible to a read of the homepage
HTML: against real sites it called a bookable business unbookable in about
half of the cases checked, and an email telling an owner to add what they
already have is the worst first impression. It stays a signal for cohorts and
the dashboard, where a human reads it as a lead to check, not as a claim.
"""

import builtins;

glob STALE_DAYS: any = 180;

glob THIN_PAGES: any = 5;

glob HEADER: any = "- Site checks (an automated read of their public pages; it can miss things). Use at most ONE, only if it fits this kind of business, put it as what you would do in their place, and never call it an audit or say you went through the site:";

"""Fact lines for the writer's prompt, or [] when nothing true is known.

    A failed read is just "nothing known", never a reason not to write.
    """
async def site_facts(state, company_id: builtins.str) -> builtins.list[builtins.str];
