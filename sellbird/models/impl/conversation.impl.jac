impl Conversation.thread_json -> str {
    return json.dumps([m.model_dump(mode="json") for m in self.thread]);
}

impl Conversation.thread_from_json(data: str | None) -> list[Message] {
    try {
        rows = json.loads(data) if data else [];
        if not all(isinstance(row, dict) for row in rows) {
            return [];
        }
        return [Message.model_validate(row) for row in rows];
    } except (json.JSONDecodeError, TypeError) {
        return [];
    }
}
