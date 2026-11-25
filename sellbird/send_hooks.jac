import builtins;
import logging;
import re;
import from collections.abc { Awaitable, Callable, Iterable }
import from dataclasses { dataclass }

glob logger = logging.getLogger("sellbird.send_hooks"),
     HeaderHook = Callable[[dict[any, any]], Iterable[builtins.tuple[str, str]]],
     RESERVED_HEADERS = frozenset(
         "from to cc bcc subject date message-id in-reply-to references reply-to sender return-path mime-version content-type content-transfer-encoding".split(),
     ),
     _HEADER_NAME = re.compile("^[A-Za-z0-9-]{1,76}$"),
     NO_HEADERS_HOLD = "this inbox can't carry the headers this email needs";

@dataclass(frozen=True)
class SendCheck {
    has item: dict[str, any],
        prospect: any,
        config: any,
        state: any;

    has cold: bool {
        getter {
            return self.item.get("kind") == "sequence";
        }
    }
}

@dataclass(frozen=True)
class Hold {
    has reason: str;
}

@dataclass(frozen=True)
class Cancel {
    has reason: str;
}

glob SendRule: any;

with entry {
    SendRule = Callable[[SendCheck], Awaitable["Hold | Cancel | None"]];
}

class SendHookError(ValueError) {}

async def first_verdict(rules: dict[str, SendRule], check: SendCheck) -> tuple[str, str] | None {
    for (name, rule) in rules.items() {
        try {
            verdict = await rule(check);
        } except Exception as e {
            logger.error(f"Send rule {name!r} failed; holding the email: {e}", exc_info=True);
            return ("approved", f"held: {name} couldn't check it");
        }
        if verdict is None {
            continue;
        }
        if isinstance(verdict, Cancel) {
            return ("cancelled", f"{name}: {verdict.reason}"[:300]);
        }
        if isinstance(verdict, Hold) {
            return ("approved", f"held: {name}: {verdict.reason}"[:300]);
        }
        logger.error(f"Send rule {name!r} returned {verdict!r}; holding the email.");
        return ("approved", f"held: {name} gave no clear answer");
    }
    return None;
}

def extra_headers(hooks: dict[str, HeaderHook], item: dict[str, any]) -> list[tuple[str, str]] {
    out: list[tuple[str, str]] = [];
    for (name, hook) in hooks.items() {
        for (header, value) in hook(item) or () {
            (header, value) = (str(header), str(value));
            if not _HEADER_NAME.match(header) or header.lower() in RESERVED_HEADERS {
                raise SendHookError(f"{name} added a header Sellbird can't send: {header!r}");
            }
            if "\r" in value or "\n" in value {
                raise SendHookError(f"{name} added a header value with a line break: {header}");
            }
            out.append((header, value));
        }
    }
    return out;
}
