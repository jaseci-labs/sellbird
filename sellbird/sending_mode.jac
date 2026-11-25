import logging;

glob logger = logging.getLogger("sellbird.sending_mode"),
     SIGNATURE_HOLD_PREFIX = "email signature: ",
     _RETRY = "Sellbird tries again every cycle; if this lasts, check the log.",
     _INBOX_FIXES = (
         ("sellbird gmail auth", "Run `sellbird gmail auth` to sign in again."),
         ("sellbird microsoft auth", "Run `sellbird microsoft auth` to sign in again."),
         (
             "refusing a partial read",
             "The mailbox got more mail in the last week than Sellbird reads, so it can't be sure it saw every reply. Send from a dedicated mailbox, or archive old mail.",
         ),
     );

async def sync_sending_mode(config: any, state: any) -> bool {
    if not refresh_sending_mode(config) {
        return False;
    }
    if config.channels.email.require_approval {
        back = await state.requeue_autopilot_approved();
        came = f" {back} queued by autopilot came back to the Outbox." if back else "";
        logger.warning(
            f"Sending mode is now APPROVAL: every email waits in the Outbox for you.{came}"
        );
    } else {
        logger.warning(
            "Sending mode is now AUTOPILOT: Sellbird sends on its own (emails it holds still wait for you).",
        );
    }
    return True;
}

def held_message(hold: dict[str, any], waiting: int) -> tuple[str, str] {
    reason = str(hold.get("reason") or "replies couldn't all be read").strip().rstrip(".");
    low = reason.lower();
    emails = "1 email is waiting" if waiting == 1 else f"{waiting} emails are waiting";
    if low.startswith(SIGNATURE_HOLD_PREFIX) {
        return (
            "Sellbird isn't sending: your email logo can't be used",
            f"{reason[len(SIGNATURE_HOLD_PREFIX):]}. Fix the file, or clear channels.email.signature.logo to send plain text. {emails}.",
        );
    }
    if low.startswith("a reply from") {
        (title, fix) = ("Sellbird isn't sending: it couldn't handle a reply", _RETRY);
    } else {
        title = "Sellbird isn't sending: it couldn't read your inbox";
        fix = next((f for (k, f) in _INBOX_FIXES if k in low), _RETRY);
    }
    since = str(hold.get("since", "?"))[:16].replace("T", " ");
    return (
        title,
        f"{reason}. {fix} {emails}: replies are read first, so an opt-out stops its follow-up before anything goes. Held since {since} UTC.",
    );
}
