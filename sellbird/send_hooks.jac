"""Send hooks: rules an extension adds to the decision to send one email, and
headers it adds to it.

The sender's own checks (stop-on-reply, suppressions, do-not-contact, the
pre-send gate, the autopilot review) always run first. Then each registered
send rule may hold the email (it stays approved and is tried again next
cycle) or cancel it, with a reason the Outbox shows. A rule can never send
an email the built-in checks stopped.

A header hook returns extra headers for an email, such as List-Unsubscribe.
A provider that can't carry custom headers (Microsoft Graph sets its own) is
never handed an email that needs them: the email is held instead, so it
never goes out without them.

Register both through an extension (sellbird.extensions):

    def install(registry):
        registry.add_send_rule("myext.warm", warm_enough)
        registry.add_send_headers("myext.unsubscribe", unsubscribe_headers)
"""

import builtins;

import operator;

import from __future__ { annotations }

import logging;

import re;

import from collections.abc { Awaitable, Callable, Iterable }

import from dataclasses { dataclass }

import from typing { Any }

glob logger: any = logging.getLogger("sellbird.send_hooks");

glob HeaderHook: any = Callable[[dict[any, any]], Iterable[builtins.tuple[str, str]]];

glob RESERVED_HEADERS: any = frozenset({
    "from",
    "to",
    "cc",
    "bcc",
    "subject",
    "date",
    "message-id",
    "in-reply-to",
    "references",
    "reply-to",
    "sender",
    "return-path",
    "mime-version",
    "content-type",
    "content-transfer-encoding",
});

glob _HEADER_NAME: any = re.compile("^[A-Za-z0-9-]{1,76}$");

glob NO_HEADERS_HOLD: any = "this inbox can't carry the headers this email needs";

"""One email about to go out, as a send rule sees it."""
@dataclass(frozen=True)
class SendCheck {
    has item: dict;

    has prospect: Any;

    has config: Any;

    has state: Any;

    has cold: bool {
        getter {
            return operator.eq(self.item.get("kind"), "sequence");
        }
    }
}

glob SendRule: any;

with entry {
    SendRule = Callable[[SendCheck], Awaitable["Hold | Cancel | None"]];
}

"""Not now: the email stays approved and is tried again next cycle."""
@dataclass(frozen=True)
class Hold {
    has reason: str;
}

"""Never: the email is cancelled."""
@dataclass(frozen=True)
class Cancel {
    has reason: str;
}

"""A hook returned something that can't be sent."""
obj SendHookError(ValueError) {
    def __repr__ -> str;

    def __eq__(other: any) -> bool;

    def __hash__ -> int;
}

"""The first rule that holds or cancels, as (status, error) for the outbox,
    or None when every rule lets it through. A rule that raises holds the email:
    an extension's bug must never be what lets an email out."""
async def first_verdict(rules: dict[str, SendRule], check: SendCheck) -> tuple[str, str] | None;

"""Every hook's headers for this email, checked. Raises SendHookError on a
    reserved or malformed header, so the email is held rather than sent wrong."""
def extra_headers(hooks: dict[str, HeaderHook], item: dict) -> list[tuple[str, str]];
