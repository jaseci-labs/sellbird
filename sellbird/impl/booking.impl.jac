impl _parse_clock(value, fallback: time) -> time {
    try {
        return time.fromisoformat(`str(value));
    } except (TypeError, ValueError) {
        return fallback;
    }
}

impl _hours(config) -> builtins.tuple[time, time] {
    window: any = send_window_of(config);
    if window is None {
        return (DEFAULT_START, DEFAULT_END);
    }
    start: any = _parse_clock(window.start, DEFAULT_START);
    end: any = _parse_clock(window.end, DEFAULT_END);
    return (start, end) if start < end else (DEFAULT_START, DEFAULT_END);
}

impl _slot_times(config) -> builtins.list[time] {
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

impl _local(now: datetime, zone: builtins.str) -> datetime {
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

impl _format(day: datetime, at: time) -> builtins.str {
    clock: any = at.strftime("%I:%M %p");
    if clock.startswith("0") {
        clock = clock[1:];
    }
    return f"{day:%A}, {day:%B} {day.day} at {clock}";
}

impl _suggested_times(config, now: datetime) -> builtins.list[builtins.str] {
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

impl _join(items: builtins.list[builtins.str]) -> builtins.str {
    if len(items) <= 1 {
        return items[0] if items else "";
    }
    if len(items) == 2 {
        return f"{items[0]} or {items[1]}";
    }
    return ", ".join(items[:-1]) + f", or {items[-1]}";
}

impl _valid_url(value: builtins.str) -> builtins.str {
    url: any = `str(value or "").strip();
    parsed: any = urlparse(url);
    if parsed.scheme not in ("http", "https") or not parsed.netloc {
        return "";
    }
    return url;
}

impl _meeting(config) -> builtins.str {
    offer: any = getattr(getattr(config, "product", None), "offer", None);
    duration: any = `str(getattr(offer, "meeting_duration", "") or "15 minutes").strip();
    owner: any = `str(getattr(offer, "meeting_owner", "") or "").strip();
    if owner {
        return f"The call is {duration} with {owner}.";
    }
    return f"The call is {duration}.";
}

impl _time_instruction(
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

impl booking_instruction(config, now: datetime, zone: builtins.str = "") -> builtins.str {
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
