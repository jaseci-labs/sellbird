"""Keep credentials out of Sellbird's log.

Some vendors take the API key in the query string (Hunter, Reoon,
ZeroBounce), and httpx logs every request URL at INFO. A log the dashboard
shows (data/sellbird.log) would put a key in a URL on screen. Two layers: httpx and httpcore only log warnings, and the
log file's handler masks any query value whose name looks like a secret.
"""

import from __future__ { annotations }

import logging;

import re;

glob _SECRET_PARAM: any = re.compile(
    "([?&][^=&\\s#\\\"'<>]*(?:key|token|secret|password)[^=&\\s#\\\"'<>]*=)[^&\\s#\\\"'<>]+",
    re.IGNORECASE,
);

glob MASK: any = "***";

"""Mask the values of secret-looking query parameters in text."""
def redact(text: str) -> str {
    return _SECRET_PARAM.sub(lambda (m) -> any { m.group(1) + MASK }, text);
}

"""Rewrites each record so no secret query value reaches the handler."""
class RedactSecrets(logging.Filter) {
    def filter(record: logging.LogRecord) -> bool {
        try {
            message: any = record.getMessage();
        } except Exception {
            return True;
        }
        cleaned: any = redact(message);
        if cleaned != message {
            items_: any = list((cleaned, None));
            if len(items_) != 2 {
                raise ValueError(
                    f"too many values to unpack (expected 2, got {len(items_)})"
                        if len(items_) > 2
                        else f"not enough values to unpack (expected 2, got {len(items_)})",
                );
            }
            record.msg = items_[0];
            record.args = items_[1];
        }
        if record.exc_info and not record.exc_text {
            record.exc_text = logging.Formatter().formatException(record.exc_info);
        }
        if record.exc_text {
            record.exc_text = redact(record.exc_text);
        }
        if record.stack_info {
            record.stack_info = redact(record.stack_info);
        }
        return True;
    }
}
