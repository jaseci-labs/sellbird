impl _utcnow -> datetime {
    return datetime.now(timezone.utc).replace(tzinfo=None);
}

impl Prospect._normalize_email(v: builtins.str) -> builtins.str {
    return (v or "").strip().lower();
}

impl Prospect._strip_linkedin(v: builtins.str) -> builtins.str {
    return (v or "").strip();
}

impl Prospect.full_name -> builtins.str {
    name: any = f"{self.first_name} {self.last_name}".strip();
    if not name and self.is_company_inbox {
        return f"{self.company} team" if self.company else "the team";
    }
    return name;
}

impl Prospect.is_valid -> builtins.bool {
    if self.is_company_inbox {
        return `bool(self.email and self.title);
    }
    return `bool(self.first_name and self.last_name and self.title);
}
