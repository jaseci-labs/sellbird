import builtins;
import json;
import from pydantic { BaseModel, Field }
import from datetime { datetime }

glob STAGES = "initial_outreach engaged qualifying presenting negotiating closing closed_won closed_lost".split();

class Message(BaseModel) {
    has sender: str,
        content: str,
        timestamp: datetime = Field(default_factory=_utcnow);
}

class Conversation(BaseModel) {
    has id: str,
        prospect_id: str,
        campaign_id: str = "",
        channel: str = "email",
        thread: list[Message] = Field(default_factory=list[any]),
        intent: str = "",
        stage: str = "initial_outreach",
        status: str = "open",
        created_at: datetime = Field(default_factory=_utcnow),
        updated_at: datetime = Field(default_factory=_utcnow);

    def thread_json -> str;

    @builtins.classmethod
    class def thread_from_json(data: str | None) -> list[Message];
}
