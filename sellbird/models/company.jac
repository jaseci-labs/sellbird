import builtins;

import from datetime { datetime, timezone }

import from pydantic { BaseModel, Field, field_validator }

def _utcnow -> datetime {
    return datetime.now(timezone.utc).replace(tzinfo=None);
}

class Company(BaseModel) {
    has id: str = "",
        name: str = "",
        domain: str = "",
        website: str = "",
        description: str = "",
        industry: str = "",
        company_size: str = "",
        location: str = "",
        phone: str = "",
        source: str = "",
        source_url: str = "",
        external_id: str = "",
        notes: str = "",
        tech_stack: list[str] = Field(default_factory=builtins.list),
        signals: list[dict[str, any]] = Field(default_factory=builtins.list),
        created_at: datetime = Field(default_factory=_utcnow),
        updated_at: datetime = Field(default_factory=_utcnow);

    @field_validator("domain")
    @builtins.classmethod
    class def _normalize_domain(v: str) -> str {
        return (v or "").strip().lower();
    }
}
