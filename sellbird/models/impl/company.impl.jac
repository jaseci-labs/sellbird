impl _utcnow -> datetime {
    return datetime.now(timezone.utc).replace(tzinfo=None);
}

impl Company._normalize_domain(v: builtins.str) -> builtins.str {
    return (v or "").strip().lower();
}
