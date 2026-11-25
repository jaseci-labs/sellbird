import json;
import re;

glob AGENT_ROUTES: tuple[tuple[str, str], ...] = tuple(
         (line.split()[0], line.split()[1]) for line in """
        GET /api/today
        GET /api/stats
        GET /api/trend
        GET /api/activity
        GET /api/usage
        GET /api/live-status
        GET /api/setup-status
        GET /api/sending-mode
        GET /api/sellbird/status
        GET /api/runs
        GET /api/campaigns
        GET /api/companies
        GET /api/companies/[^/]+/contacts
        GET /api/companies/[^/]+/profile
        GET /api/prospects
        GET /api/conversations
        GET /api/outbox
        GET /api/signals
        GET /api/discover/providers
        GET /api/inboxes
        POST /api/discover/estimate
        POST /api/sending/pause
        GET /api/company
        GET /api/offers/accepted
        POST /api/offer/suggest
        POST /api/offer/preview
        POST /api/offer/propose
        POST /api/inboxes/[^/]+/pause
    """.strip().splitlines()
     ),
     USER_ONLY = {
         "error": "user_only",
         "message": "Only the user can do this, in the Sellbird dashboard.",
     },
     _BUILT_IN = _compile(AGENT_ROUTES);

def _compile(routes: any) -> list[tuple[str, re.Pattern]];

def agent_may(method: str, path: str, extra: any = ()) -> bool;

class AgentPolicy {
    has app: any;

    async def __call__(scope: any, receive: any, send: any);
}
