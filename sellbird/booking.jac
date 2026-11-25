"""What the reply should offer, from the ``product.offer`` you configured.

``sellbird.yaml`` asks what happens when someone is interested: book a call
with your calendar link, suggest concrete times, ask for their preference,
start a trial, or just keep the conversation going. Until now only
``booking_url`` was read (the pre-send gate allows it); the rest was dead
config and every reply was told to "propose 2-3 specific times" whether or
not that fit the offer.

``booking_instruction`` turns the offer into instruction for the model. It
is never the email body itself: the caller puts the returned paragraph in
the handler prompt.
"""

import builtins;

import from datetime { datetime, time, timedelta }

import from urllib.parse { urlparse }

import pytz;

glob DEFAULT_START: any = time(9, 0);

glob DEFAULT_END: any = time(17, 0);

glob SUGGESTED_TIMES: any = 3;

glob LOOKAHEAD_DAYS: any = 14;

def _parse_clock(value, fallback: time) -> time {
    try {
        return time.fromisoformat(`str(value));
    } except (TypeError, ValueError) {
        return fallback;
    }
}

"""The send window's hours, or sensible office hours when none is set.

    A reply is not held to the window, but a time inside it is a time the
    prospect is more likely to answer."""
def _hours(config) -> builtins.tuple[time, time] {
    window: any = send_window_of(config);
    if window is None {
        return (DEFAULT_START, DEFAULT_END);
    }
    start: any = _parse_clock(window.start, DEFAULT_START);
    end: any = _parse_clock(window.end, DEFAULT_END);
    return (start, end) if start < end else (DEFAULT_START, DEFAULT_END);
}

"""One or two clock times inside the window, spread across the day."""
def _slot_times(config) -> builtins.list[time] {
    start: any;
    end: any;
    (start, end) = _hours(config) as any;
    start_min: any = start.hour * 60 + start.minute;
    end_min: any = end.hour * 60 + end.minute;
    span: any = end_min - start_min;
    if span >= 120 {
        minutes: any = [start_min + 60, end_min - 60];
    } elif span >= 60 {
        minutes = [start_min + 30, end_min - 30];
    } else {
        minutes = [start_min];
    }
    out: any = [];
    for value in minutes {
        slot: any = time(value // 60, value % 60);
        if slot not in out and start <= slot < end {
            out.append(slot);
        }
    }
    return out or [start];
}

"""``now`` on the recipient's clock. A naive ``now`` is taken as wall
    time in ``zone``, so tests and callers that already resolved the zone
    don't need to build an aware datetime."""
def _local(now: datetime, zone: builtins.str) -> datetime {
    if not zone {
        return now;
    }
    try {
        tz: any = pytz.timezone(zone);
    } except pytz.UnknownTimeZoneError {
        return now;
    }
    if now.tzinfo is None {
        return tz.localize(now);
    }
    return now.astimezone(tz);
}

def _format(day: datetime, at: time) -> builtins.str {
    clock: any = at.strftime("%I:%M %p");
    if clock.startswith("0") {
        clock = clock[1:];
    }
    return f"{day:%A}, {day:%B} {day.day} at {clock}";
}

"""Two or three upcoming weekday slots, starting tomorrow."""
def _suggested_times(config, now: datetime) -> builtins.list[builtins.str] {
    window: any = send_window_of(config);
    weekdays_only: any = window.weekdays_only if window is not None else True;
    times: any = _slot_times(config);
    day: any = now;
    slots: any = [];
    for offset in range(1, LOOKAHEAD_DAYS + 1) {
        candidate: any = day + timedelta(days=offset);
        if weekdays_only and candidate.weekday() >= 5 {
            continue;
        }
        slots.append(_format(candidate, times[len(slots) % len(times)]));
        if len(slots) == SUGGESTED_TIMES {
            break;
        }
    }
    return slots;
}

def _join(items: builtins.list[builtins.str]) -> builtins.str {
    if len(items) <= 1 {
        return items[0] if items else "";
    }
    if len(items) == 2 {
        return f"{items[0]} or {items[1]}";
    }
    return ", ".join(items[:-1]) + f", or {items[-1]}";
}

def _valid_url(value: builtins.str) -> builtins.str {
    url: any = `str(value or "").strip();
    parsed: any = urlparse(url);
    if parsed.scheme not in ("http", "https") or not parsed.netloc {
        return "";
    }
    return url;
}

def _meeting(config) -> builtins.str {
    offer: any = getattr(getattr(config, "product", None), "offer", None);
    duration: any = `str(getattr(offer, "meeting_duration", "") or "15 minutes").strip();
    owner: any = `str(getattr(offer, "meeting_owner", "") or "").strip();
    if owner {
        return f"The call is {duration} with {owner}.";
    }
    return f"The call is {duration}.";
}

def _time_instruction(
    config, now: datetime, zone: builtins.str, zone_known: builtins.bool
) -> builtins.str {
    slots: any = _suggested_times(config, now);
    if not slots {
        return "Ask what time works for them in the next week. Do not invent a specific time. "
            + _meeting(config);
    }
    where: any = f"These are already in the recipient's local time ({zone}); write them as given."
        if zone_known
        else "Write these times as given and do not name a time zone.";
    return f"Propose these times: {_join(slots)}. {where} Offer no other time. " + _meeting(config);
}

"""Instruction for the next step this reply should offer.

    ``zone`` is the recipient's IANA time zone, when Sellbird knows it. With
    no zone the dates are worked out on the operator's clock and the text
    avoids naming one."""
def booking_instruction(config, now: datetime, zone: builtins.str = "") -> builtins.str {
    offer: any = getattr(getattr(config, "product", None), "offer", None);
    goal: any = `str(getattr(offer, "goal", "") or "book_call");
    `entry: any = `str(getattr(offer, "entry", "") or "").strip();

    if goal == "get_reply" {
        return "Keep this reply conversational: answer them and ask one question about their situation. Do not propose a call, a meeting, a trial, or a link.";
    }

    if goal == "start_trial" and `entry {
        return f"Offer this as the next step: {`entry}. Keep it to one sentence and one action, and do not ask for a call or invent a different trial.";
    }

    zone = `str(zone or "").strip();
    local: any = _local(now, zone or operator_timezone(config));
    zone_known: any = `bool(zone) and zone in pytz.all_timezones_set;

    method: any = `str(getattr(offer, "booking_method", "") or "calendar_link");
    url: any = _valid_url(getattr(offer, "booking_url", ""));
    if method == "calendar_link" and url {
        return f"Offer this booking link: {url}\nLet them pick a time on that page. Do not invent times or offer to compare calendars yourself. {_meeting(config)}";
    }
    if method == "ask_preference" {
        return "Ask what time works for them in the next week. Do not invent specific times or paste a link. "
            + _meeting(config);
    }
    return _time_instruction(config, now=local, zone=zone, zone_known=zone_known);
}
