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
async def sync_sending_mode(config, state) -> builtins.bool;

"""What Today and `sellbird status` say while sending is held because
    replies couldn't all be read or handled: (title, detail)."""
def held_message(
    hold: builtins.dict, waiting: builtins.int
) -> builtins.tuple[builtins.str, builtins.str];
