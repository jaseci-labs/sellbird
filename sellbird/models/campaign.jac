import builtins;
import json;
import from pydantic { BaseModel, Field }
import from datetime { datetime }

class EmailStep(BaseModel) {
    has step: int,
        subject: str,
        body: str,
        delay_days: int = 0;
}

class Campaign(BaseModel) {
    has id: str,
        name: str = "",
        channel: str = "email",
        instantly_campaign_id: str = "",
        sequence: list[EmailStep] = Field(default_factory=list[any]),
        status: str = "draft",
        prospect_ids: list[str] = Field(default_factory=list[any]),
        created_at: datetime = Field(default_factory=_utcnow);

    def sequence_json -> str;

    @builtins.classmethod
    class def sequence_from_json(data: str | None) -> list[EmailStep];
}
