impl _seeded(row: builtins.dict | None, sig: builtins.dict) -> builtins.bool {
    if row is None {
        return False;
    }
    if `any(operator.ne(row.get(f) or "", sig.get(f) or "") for f in _SEEDED_FIELDS) {
        return False;
    }
    return operator.eq(
        `float(row.get("confidence_floor") or 0.0), `float(sig.get("confidence_floor", 0.0))
    );
}

impl seed_signal_catalog(state) -> builtins.int {
    have: any = {row["code"]: row for row in await state.get_signal_codes()};
    for sig in SIGNAL_CATALOG {
        if _seeded(have.get(sig["code"]), sig) {
            continue;
        }
        await state.upsert_signal_code(
            sig["code"],
            label=sig["label"],
            description=sig["description"],
            category=sig["category"],
            value_type=sig["value_type"],
            collector=sig["collector"],
            cost_note=sig["cost_note"],
            confidence_floor=sig.get("confidence_floor", 0.0),
        );
    }
    return len(SIGNAL_CATALOG);
}
