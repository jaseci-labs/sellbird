import builtins;
import json;
import logging;
import re;
import from datetime { datetime, timezone }

glob NO_TIP_STATUS = "no_tip",
     logger = logging.getLogger("sellbird.writer"),
     MAX_WRITE_ATTEMPTS = 3,
     WRITE_ATTEMPTS_KEY = "write_attempts:",
     PERSON_VAR = re.compile(r"\{\{\s*(first_?name|last_?name|title)\s*\}\}", re.IGNORECASE),
     _SIGNAL_SECTIONS = {
         "### Hiring signal": "hiring|job post|is hiring|open role|careers",
         "#### Using a job posting": "hiring|job post|open role",
         "### Tech-stack signal": "tools detected|uses |built on|shopify|hubspot|wordpress",
         "### Funding signal": "raised|funding|seed|series a|series b|y combinator|accelerator",
         "### New-domain": "new domain|registered|just launched|new business",
         "### Search-rank signal": "searched|search|came up|ranks|google|maps|local pack",
     },
     MERGE_VAR = re.compile(r"\{\{\s*\w+\s*\}\}"),
     NATIVE_BATCH_CAP = 8,
     LEGACY_BATCH_CAP = 50,
     PERSONAL_SHAPE = """- 60 words at most, and aim for 30-50. Every word you cut raises the reply rate.
- One specific finding from the FACTS, what it likely costs them in one plain
  sentence, then YOUR OFFER below as the one question. Don't name the product.
- Write the actual text (no merge variables: you know their name/company).
- No sign-off and no name at the end: Sellbird adds the sender's first name.
- Subject: lowercase, 2-5 words.""",
     SEQUENCE_SHAPE = f"""- Email 1: One specific finding about them, what it costs them, then YOUR OFFER below as
  the one question. {FIRST_EMAIL_MAX_WORDS} words at most, aim for 30-50. Don't name the product.
- Email 2: 3 days later. A different angle: one concrete proof point or result from the
  product info, then the offer again or a short call as the ask. {FOLLOW_UP_MAX_WORDS} words at most, aim for 20-40.
- Email 3: 4 days after that. Close the loop in one or two plain sentences, and leave
  the offer open. {BREAKUP_MAX_WORDS} words at most, aim for 10-20. No guilt.
- No sign-off and no name at the end of any email: Sellbird adds the sender's first name.""",
     SEQUENCE_STYLE = """- Never be pushy or salesy. Be consultative and value-driven.
- Subject lines: lowercase, 2-5 words.""",
     EMAIL_RULES_PROBLEM_KEY = "email_rules_problem",
     BUILT_IN_FOOTER = "- No postal address, unsubscribe or opt-out line: Sellbird adds them when it sends.";

def _sections(markdown: str) -> dict[str, str];
def _names(prospect: any) -> list[str];
def _fields(result: any) -> tuple[str, str] | None;
def operator_rules_block(rules: str) -> str;
def offer_block(config: any) -> str;
def footer_rule(config: any, rules: str) -> str;

class Writer {
    has brain: any = None,
        state: any = None,
        config: any = None,
        env: any = None,
        skills: str = "",
        email_rules: str = "",
        _no_reply: bool = False;

    def init(brain: Brain, state: StateManager, config: SellbirdConfig, env: any = None);

    @builtins.property
    def is_native -> bool;

    async def run;
    async def _site_facts(company_id: any) -> list[str];
    async def _has_tip_basis(prospect: any) -> bool;
    async def _company(company_id: any) -> any;
    async def _count_failed_attempt(batch_name: str, prospects: list[any]);
    async def _personalize_first_emails(campaign_id: str, prospects: list[any]);
    async def _startup(company_id: any) -> any;
    def _signal_guide(facts: str) -> str;
    async def _guidance(facts: str, startup: bool, prospect_ids: list[str]) -> str;
    def _base_prompt -> str;
    async def _write_personal_email(prospect: any) -> dict[str, any] | None;
    async def _write_sequence(prospects: list[any]) -> list[EmailStep];
    async def _keep_to_rules(draft: dict[str, any], *, step: int, names: any = ()) -> dict[str, any]
        | None;
    def _finish(draft: dict[str, any], shape: bool) -> dict[str, any];
    async def _rewrite_to_rules(
        draft: dict[str, any], found: list[str], step: int, shape: bool
    ) -> dict[str, any] | None;
    def _parse_sequence(result: any) -> list[EmailStep];
    def _group_prospects(prospects: list[any]) -> dict[str, list[any]];
}
