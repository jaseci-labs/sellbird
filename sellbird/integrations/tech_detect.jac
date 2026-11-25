"""Tech-stack detection — what tools a company's website reveals.

A curated subset of Wappalyzer-style fingerprints matched against HTML
Sellbird already downloads while researching a company. Zero extra network
requests, zero dependencies. Knowing a prospect runs Shopify / HubSpot /
Intercom (or conspicuously lacks something) is a concrete, verifiable
personalization hook — the kind that actually earns replies.

Patterns are intentionally conservative: match distinctive script hosts,
cookie names, or generator tags — not generic words — so false positives
stay rare.
"""

import builtins;

import re;

glob FINGERPRINTS: builtins.dict[builtins.str, builtins.list[builtins.str]];

glob _compiled: builtins.dict[builtins.str, builtins.list[re.Pattern]] | None;

with entry {
    FINGERPRINTS = {
        "WordPress": [
            "wp-content/",
            "wp-includes/",
            "<meta name=\"generator\" content=\"WordPress",
        ],
        "Shopify": ["cdn\\.shopify\\.com", "myshopify\\.com"],
        "Wix": ["static\\.parastorage\\.com", "wix\\.com/website-builder"],
        "Squarespace": ["static1\\.squarespace\\.com", "<!-- This is Squarespace"],
        "Webflow": ["assets\\.website-files\\.com", "data-wf-domain"],
        "Framer": ["framerusercontent\\.com"],
        "Drupal": ["<meta name=\"generator\" content=\"Drupal", "sites/default/files"],
        "Ghost": ["<meta name=\"generator\" content=\"Ghost"],
        "Next.js": ["/_next/static/"],
        "Gatsby": ["/page-data/app-data\\.json", "id=\\\"___gatsby\\\""],
        "Google Analytics": [
            "googletagmanager\\.com/gtag",
            "google-analytics\\.com/analytics\\.js",
        ],
        "Google Tag Manager": ["googletagmanager\\.com/gtm\\.js"],
        "Segment": ["cdn\\.segment\\.com/analytics\\.js"],
        "Mixpanel": ["cdn\\.mxpnl\\.com"],
        "Hotjar": ["static\\.hotjar\\.com"],
        "Plausible": ["plausible\\.io/js"],
        "Meta Pixel": ["connect\\.facebook\\.net/[^\\\"']*fbevents\\.js"],
        "HubSpot": ["js\\.hs-scripts\\.com", "js\\.hsforms\\.net", "hubspot\\.com/api"],
        "Marketo": ["munchkin\\.marketo\\.net"],
        "Mailchimp": ["chimpstatic\\.com", "list-manage\\.com/subscribe"],
        "Klaviyo": ["static\\.klaviyo\\.com"],
        "ActiveCampaign": ["trackcmp\\.net"],
        "Salesforce": ["force\\.com", "salesforce\\.com/embeddedservice"],
        "Intercom": ["widget\\.intercom\\.io", "js\\.intercomcdn\\.com"],
        "Drift": ["js\\.driftt\\.com"],
        "Zendesk": ["static\\.zdassets\\.com", "zendesk\\.com/embeddable"],
        "Crisp": ["client\\.crisp\\.chat"],
        "Tidio": ["code\\.tidio\\.co"],
        "LiveChat": ["cdn\\.livechatinc\\.com"],
        "Calendly": ["assets\\.calendly\\.com", "calendly\\.com/[\\w\\-]+/"],
        "Stripe": ["js\\.stripe\\.com"],
        "Typeform": ["embed\\.typeform\\.com"],
        "WooCommerce": ["woocommerce", "wc-ajax"],
        "BigCommerce": ["cdn\\d*\\.bigcommerce\\.com"],
        "Cloudflare": ["/cdn-cgi/"],
        "Vercel": ["vercel\\.app", "x-vercel"],
    };

    _compiled = None;
}

def _get_compiled -> builtins.dict[builtins.str, builtins.list[re.Pattern]];

"""Return the tools detectable in a page's HTML, alphabetized."""
def detect_tech(
    html: builtins.str, max_bytes: builtins.int = 300000
) -> builtins.list[builtins.str];
