import from datetime { datetime, time, timedelta }
import from urllib.parse { urlparse }
import pytz;

glob DEFAULT_START = time(9, 0),
     DEFAULT_END = time(17, 0),
     SUGGESTED_TIMES = 3,
     LOOKAHEAD_DAYS = 14;

def _parse_clock(value: any, fallback: time) -> time {
    try {
        return time.fromisoformat(str(value));
    } except (TypeError, ValueError) {
        return fallback;
    }
}

def _hours(config: any) -> tuple[time, time] {
    window = send_window_of(config);
    if window is None {
        return (DEFAULT_START, DEFAULT_END);
    }
    start = _parse_clock(window.start, DEFAULT_START);
    end = _parse_clock(window.end, DEFAULT_END);
    return (start, end) if start < end else (DEFAULT_START, DEFAULT_END);
}

def _slot_times(config: any) -> list[time] {
    (start, end) = _hours(config) as any;
    (start_min, end_min) = (start.hour * 60 + start.minute, end.hour * 60 + end.minute);
    pad = 60 if end_min - start_min >= 120 else 30 if end_min - start_min >= 60 else 0;
    out: list[time] = [];
    for value in ([start_min + pad, end_min - pad] if pad else [start_min]) {
        slot = time(value // 60, value % 60);
        if slot not in out and start <= slot and slot < end {
            out.append(slot);
        }
    }
    return out or [start];
}

def _local(now: datetime, zone: str) -> datetime {
    if not zone {
        return now;
    }
    try {
        tz = pytz.timezone(zone);
    } except pytz.UnknownTimeZoneError {
        return now;
    }
    return tz.localize(now) if now.tzinfo is None else now.astimezone(tz);
}

def _format(day: datetime, at: time) -> str {
    return f"{day:%A}, {day:%B} {day.day} at {at.strftime('%I:%M %p').removeprefix('0')}";
}

def _suggested_times(config: any, now: datetime) -> list[str] {
    window = send_window_of(config);
    weekdays_only = window.weekdays_only if window is not None else True;
    times = _slot_times(config);
    days = [now + timedelta(days=offset) for offset in range(1, LOOKAHEAD_DAYS + 1)];
    days = [d for d in days if not (weekdays_only and d.weekday() >= 5)][:SUGGESTED_TIMES];
    return [_format(d, times[i % len(times)]) for (i, d) in enumerate(days)];
}

def _join(items: list[str]) -> str {
    return " or ".join(items) if len(items) <= 2 else ", ".join(items[:-1]) + f", or {items[-1]}";
}

def _valid_url(value: str) -> str {
    url = str(value or "").strip();
    parsed = urlparse(url);
    return url if parsed.scheme in ("http", "https") and parsed.netloc else "";
}

def _meeting(config: any) -> str {
    offer = getattr(getattr(config, "product", None), "offer", None);
    duration = str(getattr(offer, "meeting_duration", "") or "15 minutes").strip();
    owner = str(getattr(offer, "meeting_owner", "") or "").strip();
    return f"The call is {duration} with {owner}." if owner else f"The call is {duration}.";
}

def _time_instruction(config: any, now: datetime, zone: str, zone_known: bool) -> str {
    slots = _suggested_times(config, now);
    if not slots {
        return "Ask what time works for them in the next week. Do not invent a specific time. "
            + _meeting(config);
    }
    where = f"These are already in the recipient's local time ({zone}); write them as given."
        if zone_known
        else "Write these times as given and do not name a time zone.";
    return f"Propose these times: {_join(slots)}. {where} Offer no other time. " + _meeting(config);
}

def booking_instruction(config: any, now: datetime, zone: str = "") -> str {
    offer = getattr(getattr(config, "product", None), "offer", None);
    goal = str(getattr(offer, "goal", "") or "book_call");
    `entry = str(getattr(offer, "entry", "") or "").strip();
    if goal == "get_reply" {
        return "Keep this reply conversational: answer them and ask one question about their situation. Do not propose a call, a meeting, a trial, or a link.";
    }
    if goal == "start_trial" and `entry {
        return f"Offer this as the next step: {`entry}. Keep it to one sentence and one action, and do not ask for a call or invent a different trial.";
    }
    zone = str(zone or "").strip();
    local = _local(now, zone or operator_timezone(config));
    method = str(getattr(offer, "booking_method", "") or "calendar_link");
    url = _valid_url(getattr(offer, "booking_url", ""));
    if method == "calendar_link" and url {
        return f"Offer this booking link: {url}\nLet them pick a time on that page. Do not invent times or offer to compare calendars yourself. {_meeting(config)}";
    }
    if method == "ask_preference" {
        return "Ask what time works for them in the next week. Do not invent specific times or paste a link. "
            + _meeting(config);
    }
    return _time_instruction(config, local, zone, bool(zone) and zone in pytz.all_timezones_set);
}
