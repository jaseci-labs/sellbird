"""Approval or autopilot, picked up while Sellbird runs.

The dashboard switch (or a hand edit) changes channels.email.require_approval
in the config file. Whatever part of Sellbird notices first, the loop, the
sender, the writer or the handler, calls sync_sending_mode, so going back to
approval always brings what autopilot approved (and hasn't sent) back to the
Outbox, whoever noticed.
"""

import builtins;

import logging;

glob logger: any = logging.getLogger("sellbird.sending_mode");

glob SIGNATURE_HOLD_PREFIX: any = "email signature: ";

"""Bring ``config`` in line with its file. True when the mode changed."""
async def sync_sending_mode(config, state) -> builtins.bool {
    if not refresh_sending_mode(config) {
        return False;
    }
    if config.channels.email.require_approval {
        back: any = await state.requeue_autopilot_approved();
        logger.warning(
            "Sending mode is now APPROVAL: every email waits in the Outbox for you."
                + (f" {back} queued by autopilot came back to the Outbox." if back else ""),
        );
    } else {
        logger.warning(
            "Sending mode is now AUTOPILOT: Sellbird sends on its own (emails it holds still wait for you).",
        );
    }
    return True;
}

"""What Today and `sellbird status` say while sending is held because
    replies couldn't all be read or handled: (title, detail)."""
def held_message(
    hold: builtins.dict, waiting: builtins.int
) -> builtins.tuple[builtins.str, builtins.str] {
    reason: any = `str(hold.get("reason") or "replies couldn't all be read").strip().rstrip(".");
    low: any = reason.lower();
    emails: any = "1 email is waiting" if waiting == 1 else f"{waiting} emails are waiting";
    if low.startswith(SIGNATURE_HOLD_PREFIX) {
        return (
            "Sellbird isn't sending: your email logo can't be used",
            f"{reason[len(SIGNATURE_HOLD_PREFIX):]}. Fix the file, or clear channels.email.signature.logo to send plain text. {emails}.",
        );
    }
    if low.startswith("a reply from") {
        title: any = "Sellbird isn't sending: it couldn't handle a reply";
        fix: any = "Sellbird tries again every cycle; if this lasts, check the log.";
    } else {
        title = "Sellbird isn't sending: it couldn't read your inbox";
        if "sellbird gmail auth" in low {
            fix = "Run `sellbird gmail auth` to sign in again.";
        } elif "sellbird microsoft auth" in low {
            fix = "Run `sellbird microsoft auth` to sign in again.";
        } elif "refusing a partial read" in low {
            fix = "The mailbox got more mail in the last week than Sellbird reads, so it can't be sure it saw every reply. Send from a dedicated mailbox, or archive old mail.";
        } else {
            fix = "Sellbird tries again every cycle; if this lasts, check the log.";
        }
    }
    return (
        title,
        format(reason, "")
            + ". "
            + format(fix, "")
            + " "
            + format(emails, "")
            + ": replies are read first, so an opt-out stops its follow-up before anything goes. Held since "
            + format(`str(hold.get("since", "?"))[:16].replace("T", " "), "")
            + " UTC.",
    );
}
