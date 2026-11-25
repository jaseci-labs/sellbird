import re;

glob FINGERPRINTS: dict[str, list[str]] = {
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
     },
     _COMPILED = {
         name: re.compile("|".join(patterns), re.IGNORECASE)
         for (name, patterns) in FINGERPRINTS.items()
     };

def detect_tech(html: str, max_bytes: int = 300000) -> list[str] {
    sample = (html or "")[:max_bytes];
    return sorted([name for (name, rx) in _COMPILED.items() if sample and rx.search(sample)]);
}
