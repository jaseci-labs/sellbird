impl Campaign.sequence_json -> str {
    return json.dumps([s.model_dump() for s in self.sequence]);
}

impl Campaign.sequence_from_json(data: str | None) -> list[EmailStep] {
    try {
        rows = json.loads(data) if data else [];
        if not all(isinstance(row, dict) for row in rows) {
            return [];
        }
        return [EmailStep.model_validate(row) for row in rows];
    } except (json.JSONDecodeError, TypeError) {
        return [];
    }
}
