impl _signal(row: str) -> dict[str, any] {
    sig: dict[str, any] = dict(zip(_COLUMNS, row.split("|")));
    sig["confidence_floor"] = float(sig["confidence_floor"]);
    return {k: sig[k] for k in _KEY_ORDER};
}

impl _seeded(row: any, sig: dict[str, any]) -> bool {
    if row is None or any((row.get(f) or "") != (sig.get(f) or "") for f in _SEEDED_FIELDS) {
        return False;
    }
    return float(row.get("confidence_floor") or 0.0) == float(sig.get("confidence_floor", 0.0));
}

impl seed_signal_catalog(state: any) -> int {
    have = {row["code"]: row for row in await state.get_signal_codes()};
    for sig in SIGNAL_CATALOG {
        if not _seeded(have.get(sig["code"]), sig) {
            await state.upsert_signal_code(
                sig["code"], **{k: v for (k, v) in sig.items() if k != "code"}
            );
        }
    }
    return len(SIGNAL_CATALOG);
}
