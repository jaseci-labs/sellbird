import builtins;
import from datetime { datetime }
import from pydantic { BaseModel, Field, field_validator }

glob COMPANY_INBOX_SOURCE = "company_inbox";

class Prospect(BaseModel) {
    has id: str = "",
        company_id: str = "",
        first_name: str = "",
        last_name: str = "",
        email: str = "",
        email_verified: bool = False,
        email_status: str = "",
        phone: str = "",
        phone_verified: bool = False,
        linkedin_url: str = "",
        title: str = "",
        seniority: str = "",
        department: str = "",
        source: str = "",
        source_url: str = "",
        status: str = "new",
        score: int = 0,
        personalization_notes: str = "",
        timezone: str = "",
        company: str = "",
        industry: str = "",
        company_size: str = "",
        created_at: datetime = Field(default_factory=_utcnow),
        updated_at: datetime = Field(default_factory=_utcnow);

    @field_validator("email")
    @builtins.classmethod
    class def _normalize_email(v: str) -> str {
        return (v or "").strip().lower();
    }

    @field_validator("linkedin_url")
    @builtins.classmethod
    class def _strip_linkedin(v: str) -> str {
        return (v or "").strip();
    }

    has is_company_inbox: bool {
        getter {
            return self.source == COMPANY_INBOX_SOURCE;
        }
    }

    def full_name -> str {
        name = f"{self.first_name} {self.last_name}".strip();
        if not name and self.is_company_inbox {
            return f"{self.company} team" if self.company else "the team";
        }
        return name;
    }

    def is_valid -> bool {
        named = self.email if self.is_company_inbox else self.first_name and self.last_name;
        return bool(named and self.title);
    }
}
