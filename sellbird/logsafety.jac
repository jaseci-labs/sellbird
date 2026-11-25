import logging;
import re;

glob _SECRET_PARAM = re.compile(
         "([?&][^=&\\s#\\\"'<>]*(?:key|token|secret|password)[^=&\\s#\\\"'<>]*=)[^&\\s#\\\"'<>]+",
         re.IGNORECASE,
     ),
     MASK = "***";

def redact(text: str) -> str {
    return _SECRET_PARAM.sub(lambda (m: any) -> str { m.group(1) + MASK }, text);
}

class RedactSecrets(logging.Filter) {
    def filter(record: logging.LogRecord) -> bool {
        try {
            message = record.getMessage();
        } except Exception {
            return True;
        }
        cleaned = redact(message);
        if cleaned != message {
            (record.msg, record.args) = (cleaned, None);
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
