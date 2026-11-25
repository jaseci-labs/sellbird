"""Keep credentials out of Sellbird's log.

Some vendors take the API key in the query string (Hunter, Reoon,
ZeroBounce), and httpx logs every request URL at INFO. A log the dashboard
shows (data/sellbird.log) would put a key in a URL on screen. Two layers: httpx and httpcore only log warnings, and the
log file's handler masks any query value whose name looks like a secret.
"""

import from __future__ { annotations }

import logging;

import re;

glob _SECRET_PARAM: any;

glob MASK: any;

with entry {
    _SECRET_PARAM = re.compile(
        "([?&][^=&\\s#\\\"'<>]*(?:key|token|secret|password)[^=&\\s#\\\"'<>]*=)[^&\\s#\\\"'<>]+",
        re.IGNORECASE,
    );

    MASK = "***";
}

"""Mask the values of secret-looking query parameters in text."""
def redact(text: str) -> str;

"""Rewrites each record so no secret query value reaches the handler."""
class RedactSecrets(logging.Filter) {
    def filter(record: logging.LogRecord) -> bool;
}
