"""Company data model."""

import builtins;

import from datetime { datetime, timezone }

import from pydantic { BaseModel, Field, field_validator }

"""Naive UTC now (consistent with DB storage; avoids deprecated utcnow)."""
def _utcnow -> datetime;

class Company(BaseModel) {
    has id: builtins.str = "";

    has name: builtins.str = "";

    has domain: builtins.str = "";

    has website: builtins.str = "";

    has description: builtins.str = "";

    has industry: builtins.str = "";

    has company_size: builtins.str = "";

    has location: builtins.str = "";

    has phone: builtins.str = "";

    has source: builtins.str = "";

    has source_url: builtins.str = "";

    has external_id: builtins.str = "";

    has notes: builtins.str = "";

    has tech_stack: builtins.list[builtins.str] = Field(default_factory=list[any]);

    has signals: builtins.list[builtins.dict] = Field(default_factory=list[any]);

    has created_at: datetime = Field(default_factory=_utcnow);

    has updated_at: datetime = Field(default_factory=_utcnow);

    """Domains are dedup keys — normalize case/whitespace."""
    @field_validator("domain")
    @builtins.classmethod
    class def _normalize_domain(v: builtins.str) -> builtins.str;
}
