impl redact(text: str) -> str {
    return _SECRET_PARAM.sub(lambda (m) -> any { m.group(1) + MASK }, text);
}

impl RedactSecrets.filter(record: logging.LogRecord) -> bool {
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
