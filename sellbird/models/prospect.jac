"""Contact data model — a person at a company."""

import builtins;

import operator;

import from datetime { datetime, timezone }

import from pydantic { BaseModel, Field, field_validator }

glob COMPANY_INBOX_SOURCE: any = "company_inbox";

"""Naive UTC now (consistent with DB storage; avoids deprecated utcnow)."""
def _utcnow -> datetime;

class Prospect(BaseModel) {
    has id: builtins.str = "";

    has company_id: builtins.str = "";

    has first_name: builtins.str = "";

    has last_name: builtins.str = "";

    has email: builtins.str = "";

    has email_verified: builtins.bool = False;

    has email_status: builtins.str = "";

    has phone: builtins.str = "";

    has phone_verified: builtins.bool = False;

    has linkedin_url: builtins.str = "";

    has title: builtins.str = "";

    has seniority: builtins.str = "";

    has department: builtins.str = "";

    has source: builtins.str = "";

    has source_url: builtins.str = "";

    has status: builtins.str = "new";

    has score: builtins.int = 0;

    has personalization_notes: builtins.str = "";

    has timezone: builtins.str = "";

    has company: builtins.str = "";

    has industry: builtins.str = "";

    has company_size: builtins.str = "";

    has created_at: datetime = Field(default_factory=_utcnow);

    has updated_at: datetime = Field(default_factory=_utcnow);

    """Emails are dedup keys — normalize so 'Jane@X.com' == 'jane@x.com'."""
    @field_validator("email")
    @builtins.classmethod
    class def _normalize_email(v: builtins.str) -> builtins.str;

    @field_validator("linkedin_url")
    @builtins.classmethod
    class def _strip_linkedin(v: builtins.str) -> builtins.str;

    """A company's published general address (info@, office@) with no named person."""
    has is_company_inbox: builtins.bool {
        getter {
            return operator.eq(self.source, COMPANY_INBOX_SOURCE);
        }
    }

    def full_name -> builtins.str;

    """A contact must have a name and title — or be a company inbox with an address."""
    def is_valid -> builtins.bool;
}
