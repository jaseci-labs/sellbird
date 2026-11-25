impl parse_brain_status(raw: str) -> dict[str, any] {
    try {
        value: any = json.loads(raw) if raw else {};
    } except ValueError {
        return {};
    }
    return value if isinstance(value, dict) else {};
}

impl active_brain_status(raw: str, provider: str) -> dict[str, any] {
    status = parse_brain_status(raw);
    return status if status.get("provider") == provider else {};
}

impl _read_knowledge(folder: str, name: str) -> str {
    mine = getattr(current_home(), f"{folder}_dir") / f"{name}.md";
    try {
        return read_user_text(mine);
    } except FileNotFoundError {
        shipped = bundled_defaults();
        if shipped is None or shipped / folder / f"{name}.md" == mine {
            raise;
        }
        return read_user_text(shipped / folder / f"{name}.md");
    }
}

impl _load(folder: str, name: str, kind: str) -> str {
    try {
        return _read_knowledge(folder, name);
    } except FileNotFoundError {
        logger.warning(f"{kind} file not found: {name}.md");
    } except OSError as e {
        logger.error(f"Could not read {kind.lower()} file {name}.md: {e}");
    }
    return "";
}

impl _agent_of(agent: str, label: str) -> str {
    if not agent and label.startswith("sellbird-") {
        return label[len("sellbird-"):].split("-")[0];
    }
    return agent;
}

impl _usage_row(model: str, usage: dict[str, any], keys: list[str], cost: any) -> dict[str, any] {
    tokens = [int(usage.get(k) or 0) for k in keys];
    return {"model": model, "cost_usd": float(cost or 0.0)} | dict(zip(_ROW_KEYS, tokens));
}

impl _backoff(what: str, attempt: int, max_retries: int) {
    if attempt > 0 {
        delay = RETRY_BASE_DELAY * (2 ** (attempt - 1));
        logger.info(
            f"Retrying {what} call in {delay:.0f}s (attempt {attempt + 1}/{max_retries + 1})..."
        );
        await asyncio.sleep(delay);
    }
}

impl _kill(process: any) -> bool {
    try {
        process.kill();
        return True;
    } except ProcessLookupError {
        return False;
    }
}

impl _account(counter: any, record: any, **kwargs: any) {
    try {
        await counter(**kwargs);
    } except Exception as e {
        logger.warning(f"Failed to record usage counter: {e}");
    }
    try {
        await record;
    } except Exception as e {
        logger.warning(f"Failed to record usage event: {e}");
    }
}

impl Brain.init(state: StateManager, brain_config: any = None, transport: any = None) {
    self.state = state;
    self.transport = transport;
    self.config = brain_config or BrainConfig();
    self.provider = self.config.provider;
    self.model = self.config.model;
    if self.provider == "codex" {
        self.codex = CodexClient(model=self.model, reasoning_effort=self.config.reasoning_effort);
        self.quota = CodexQuotaClient(self.codex);
    } else {
        self.quota = QuotaClient();
    }
}

impl Brain.provider_label -> str {
    return PROVIDER_LABELS[self.provider];
}

impl Brain.paused_reason -> str {
    if self.transport is not None and str(getattr(self.transport, "paused_reason", "") or "") {
        return str(self.transport.paused_reason);
    }
    if self.unavailable {
        return self.unavailable;
    }
    if time.monotonic() < self._usage_limited_until {
        return f"{self.provider_label} usage limit reached for this plan";
    }
    return "";
}

impl Brain.preflight -> str {
    if self.provider != "codex" {
        return "" if (await self._claude_ready()) is not None else self.unavailable;
    }
    await self._expire_usage_pause();
    if self.unavailable
        and self.codex.fingerprint() == self._unavailable_fingerprint
        and time.monotonic() - self._unavailable_at < PROVIDER_RECHECK_SECONDS
    {
        return self.unavailable;
    }
    try {
        await self.codex.preflight();
    } except CodexError as e {
        if e.kind in _PERSISTENT_CODEX_KINDS {
            await self._mark_unavailable(e);
            return self.unavailable;
        }
        return str(e);
    } except Exception as e {
        return f"Codex preflight failed unexpectedly ({type(e).__name__}).";
    }
    if self.unavailable {
        await self._mark_available();
    } elif not self._status_synced {
        logger.info(
            f"Codex ready: supported CLI, isolation verified, login and account valid, model {self.model or 'auto'} usable with no tools (no prompt sent).",
        );
        self._status_synced = True;
        try {
            stored = parse_brain_status(await self.state.get_setting(BRAIN_STATUS_KEY));
        } except Exception {
            stored = {};
        }
        until = stored.get("until");
        if stored.get("status") == "paused"
            and stored.get("kind") == "usage_limit"
            and isinstance(until, (int, float))
            and until > time.time()
        {
            self._usage_limited_until = time.monotonic() + (until - time.time());
            self._usage_pause_recorded = True;
        } elif stored.get("status") == "paused" {
            await self._mark_available();
        }
    }
    return "";
}

impl Brain._claude_ready -> any {
    try {
        executable = await asyncio.to_thread(check_cli);
    } except ClaudeRuntimeError as e {
        await self._mark_unavailable(e);
        return None;
    }
    if self.unavailable {
        await self._mark_available();
    }
    return executable;
}

impl Brain._fingerprint -> any {
    return self.codex.fingerprint() if self.provider == "codex" else fingerprint();
}

impl Brain._expire_usage_pause {
    if self._usage_pause_recorded and time.monotonic() >= self._usage_limited_until {
        self._usage_pause_recorded = False;
        if not self.unavailable {
            logger.info(f"{self.provider_label} usage-limit pause is over; resuming.");
            await self._record_status("ok", "");
        }
    }
}

impl Brain._mark_unavailable(error: any) {
    first = not self.unavailable or self.unavailable != str(error);
    self.unavailable = str(error);
    self._unavailable_at = time.monotonic();
    self._unavailable_fingerprint = self._fingerprint();
    if first {
        await self._record_status("paused", self.unavailable, kind=getattr(error, "kind", "setup"));
    }
}

impl Brain._mark_available {
    logger.info(f"{self.provider_label} is available again; resuming.");
    self.unavailable = "";
    self._unavailable_fingerprint = None;
    await self._record_status("ok", "");
}

impl Brain._record_status(status: str, reason: str, **extra: any) {
    since = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime());
    try {
        await self.state.set_setting(
            BRAIN_STATUS_KEY,
            json.dumps({
                "provider": self.provider,
                "status": status,
                "reason": reason[:500],
                "since": since,
                **extra,
            }),
        );
    } except Exception as e {
        logger.warning(f"Failed to record brain status: {e}");
    }
}

impl Brain.think(
    prompt: str,
    session_id: str | None = None,
    expect_json: bool = False,
    timeout: float = DEFAULT_TIMEOUT_SECONDS,
    max_retries: int = DEFAULT_MAX_RETRIES,
    agent: str = "",
    task: str = "",
) -> str {
    if self.transport is not None {
        if self.paused_reason {
            return "";
        }
        try {
            text = await asyncio.wait_for(
                self.transport(
                    prompt, agent=agent, task=task, timeout=timeout, expect_json=expect_json
                ),
                timeout=timeout,
            );
        } except Exception as e {
            logger.warning(
                f"Brain transport call failed ({agent}/{task}): {type(e).__name__}: {e}"
            );
            return "";
        }
        return str(text or "");
    }
    if self.provider == "codex" {
        return await self._think_codex(prompt, session_id, timeout, max_retries, agent, task);
    }
    executable = await self._claude_ready();
    if executable is None {
        logger.error(f"Claude call not sent: {self.unavailable}");
        return "";
    }
    cmd = build_command(executable, self.model, session_id);
    logger.debug(f"Brain call (session={session_id}): {prompt[:100]}...");
    last_error: any = "";
    for attempt in range(max_retries + 1) {
        await _backoff("brain", attempt, max_retries);
        process: any = None;
        try {
            with isolated_cwd() as cwd {
                process = await asyncio.create_subprocess_exec(
                    *cmd,
                    cwd=cwd,
                    env=runtime_env(cwd),
                    stdin=asyncio.subprocess.PIPE,
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE,
                );
                try {
                    (stdout, stderr) = await asyncio.wait_for(
                        process.communicate(prompt.encode("utf-8")), timeout=timeout
                    );
                } except asyncio.TimeoutError {
                    logger.error(f"Claude call timed out after {timeout:.0f}s. Killing process.");
                    if _kill(process) {
                        await process.wait();
                    }
                    stdout = None;
                } except BaseException {
                    _kill(process);
                    try {
                        await asyncio.wait_for(process.wait(), timeout=KILL_REAP_SECONDS);
                    } except Exception as e {
                        logger.warning(f"Claude child not reaped on shutdown: {e!r}");
                    }
                    raise;
                }
            }
            if stdout is None {
                last_error = "timeout";
                continue;
            }
            if process.returncode != 0 {
                last_error = stderr.decode(errors="replace").strip();
                logger.error(f"Claude exited with code {process.returncode}: {last_error[:300]}");
                if any(p in last_error.lower() for p in _NON_RETRYABLE_PATTERNS) {
                    logger.error(
                        "Non-retryable Claude error (auth). Run 'claude login' and restart Sellbird.",
                    );
                    return "";
                }
                continue;
            }
            (response, payload) = self._parse_result_payload(
                stdout.decode(errors="replace").strip()
            );
            await _account(
                self.state.increment_usage,
                self._record_usage(payload, agent=agent, task=task, label=session_id or ""),
            );
            if payload and payload.get("is_error") {
                logger.error(f"Claude reported an error: {response[:300]}");
                last_error = response;
                continue;
            }
            logger.debug(f"Brain response: {response[:200]}...");
            return response;
        } except FileNotFoundError {
            logger.error("Claude CLI not found. Install it: https://code.claude.com/docs/en/setup");
            return "";
        } except asyncio.CancelledError {
            if process is not None and process.returncode is None {
                _kill(process);
            }
            raise;
        } except Exception as e {
            logger.error(f"Brain error: {e}");
            last_error = str(e);
        }
    }
    logger.error(
        f"Brain call failed after {max_retries + 1} attempts. Last error: {str(last_error)[:200]}"
    );
    return "";
}

impl Brain._think_codex(
    prompt: str, session_id: str | None, timeout: float, max_retries: int, agent: str, task: str
) -> str {
    paused = self.paused_reason;
    if paused {
        logger.debug(f"Codex call skipped: {paused}");
        return "";
    }
    logger.debug(f"Brain call via Codex (label={session_id})");
    last_error = "";
    for attempt in range(max_retries + 1) {
        await _backoff("Codex", attempt, max_retries);
        try {
            result = await self.codex.run(
                prompt, timeout=timeout, skip_if=lambda -> str { return self.paused_reason; }
            );
        } except CodexError as e {
            if e.kind == "paused" {
                logger.debug(f"Codex call skipped: {e}");
                return "";
            }
            last_error = str(e);
            if e.retryable {
                logger.warning(f"Codex call failed: {e}");
                continue;
            }
            logger.error(f"Codex call failed: {e}");
            if e.kind in _PERSISTENT_CODEX_KINDS {
                await self._mark_unavailable(e);
            } elif e.kind == "usage_limit" {
                self._usage_limited_until = time.monotonic() + USAGE_LIMIT_PAUSE_SECONDS;
                until = time.time() + USAGE_LIMIT_PAUSE_SECONDS;
                resume = time.strftime("%H:%M UTC", time.gmtime(until));
                await self._record_status(
                    "paused",
                    f"{self.provider_label} usage limit reached for this plan; calls resume after {resume}.",
                    kind="usage_limit",
                    until=until,
                );
                self._usage_pause_recorded = True;
                invalidate = getattr(self.quota, "invalidate", None);
                if invalidate {
                    invalidate();
                }
            }
            return "";
        } except Exception as e {
            logger.error(f"Codex call failed unexpectedly ({type(e).__name__}).");
            return "";
        }
        await _account(
            self.state.increment_usage,
            self.state.record_usage_event(
                agent=_agent_of(agent, session_id or ""),
                task=task or session_id or "",
                session_id=result.thread_id,
                model=result.model,
                duration_ms=result.duration_ms,
                num_turns=1,
                source="codex_app_server",
                provider="codex",
                **result.usage,
            ),
            provider="codex",
        );
        return result.text;
    }
    logger.error(
        f"Codex call failed after {max_retries + 1} attempts. Last error: {last_error[:200]}"
    );
    return "";
}

impl Brain._parse_result_payload(raw: str) -> tuple[str, dict[str, any] | None] {
    try {
        payload = json.loads(raw);
    } except json.JSONDecodeError {
        return (raw, None);
    }
    if not isinstance(payload, dict) or payload.get("type") != "result" {
        return (raw, None);
    }
    return (str(payload.get("result") or ""), payload);
}

impl Brain._record_usage(payload: dict[str, any] | None, agent: str, task: str, label: str) {
    if not payload {
        return;
    }
    common = {
        "agent": _agent_of(agent, label),
        "task": task or label,
        "session_id": str(payload.get("session_id") or ""),
        "duration_ms": int(payload.get("duration_ms") or 0),
        "num_turns": int(payload.get("num_turns") or 0),
        "is_error": bool(payload.get("is_error")),
        "source": "result_json",
        "provider": "claude",
    };
    model_usage = payload.get("modelUsage");
    usage = payload.get("usage");
    if isinstance(model_usage, dict) and model_usage {
        rows = [
            _usage_row(str(m), mu, _MODEL_USAGE_KEYS, mu.get("costUSD"))
            for (m, mu) in model_usage.items()
            if isinstance(mu, dict)
        ];
    } else {
        rows = [_usage_row("", usage, _FLAT_USAGE_KEYS, payload.get("total_cost_usd"))]
            if isinstance(usage, dict)
            else [];
    }
    for row in rows {
        await self.state.record_usage_event(**common, **row);
    }
}

impl Brain.think_json(
    prompt: str, session_id: str | None = None, agent: str = "", task: str = ""
) -> dict[str, any] | list[any] | None {
    response = await self.think(
        prompt + "\n\nRespond ONLY with valid JSON. No markdown, no explanation.",
        session_id=session_id,
        agent=agent,
        task=task,
    );
    self.last_reply_empty = not response;
    if not response {
        return None;
    }
    parsed = self._extract_json(response);
    if parsed is None {
        logger.error(f"Failed to parse JSON from brain: {response[:200]}");
    }
    return parsed;
}

impl Brain._extract_json(text: str) -> dict[str, any] | list[any] | None {
    cleaned = re.sub("\\s*```$", "", re.sub("^```(?:json)?\\s*", "", text.strip()));
    candidates = [cleaned];
    for (open_ch, close_ch) in (("{", "}"), ("[", "]")) {
        (start, end) = (cleaned.find(open_ch), cleaned.rfind(close_ch));
        if start != -1 and end > start {
            candidates.append(cleaned[start:end + 1]);
        }
    }
    for candidate in candidates {
        try {
            return json.loads(candidate);
        } except json.JSONDecodeError {}
    }
    return None;
}

impl Brain.check_usage -> float {
    try {
        return await self.state.get_usage_today(provider=self.provider);
    } except Exception as e {
        logger.warning(f"Could not read usage from state: {e}");
        return 0.0;
    }
}

impl Brain.is_within_budget(max_daily_calls: int = 200, max_percent: float | None = None) -> bool {
    await self._expire_usage_pause();
    if time.monotonic() < self._usage_limited_until {
        logger.info(f"{self.paused_reason}; waiting for it to reset.");
        return False;
    }
    if max_percent is not None {
        try {
            windows = await self.quota.get_utilization();
        } except Exception as e {
            logger.debug(f"Quota check errored: {e}");
            windows = None;
        }
        if windows {
            worst = max((w["utilization"] for w in windows.values()), default=0.0);
            if worst >= max_percent {
                resets = ", ".join(
                    f"{name} resets {w['resets_at']}"
                    for (name, w) in windows.items()
                    if w.get("resets_at"),
                );
                logger.info(
                    f"{self.provider_label} quota gate: utilization {worst:.0f}% >= {max_percent:.0f}% limit. {resets}",
                );
            }
            return worst < max_percent;
        }
    }
    return await self.check_usage() < max_daily_calls;
}

impl Brain.load_prompt(prompt_name: str, **kwargs: any) -> str {
    template = _load("prompts", prompt_name, "Prompt");
    for (key, value) in kwargs.items() {
        template = template.replace(f"{{{{{key}}}}}", str(value));
    }
    leftover = re.findall("\\{\\{(\\w+)\\}\\}", template);
    if leftover {
        logger.warning(f"Prompt '{prompt_name}' has unfilled variables: {sorted(set(leftover))}");
    }
    return template;
}

impl Brain.load_skill(skill_name: str) -> str {
    return _load("skills", skill_name, "Skill");
}

impl Brain.load_skills_for_agent(agent_name: str) -> str {
    skill_map = {
        "scout": [
            "prospecting_tactics",
            "lead_qualification",
            "account_navigation",
            "signal_playbook",
            "product_knowledge",
        ],
        "writer": ["product_knowledge", "competitive_intel"],
        "handler": [
            "objection_handling",
            "sales_methodology",
            "offer_strategy",
            "product_knowledge",
            "competitive_intel",
        ],
        "sender": ["email_frameworks", "product_knowledge"],
        "linkedin": ["linkedin_outreach", "prospecting_tactics", "product_knowledge"],
    };
    sections = [s for s in map(self.load_skill, skill_map.get(agent_name, [])) if s];
    if not sections {
        return "";
    }
    return "\n\n---\n## FOUNDATIONAL KNOWLEDGE\nUse the following frameworks and best practices to guide your work:\n\n"
        + "\n\n---\n\n".join(sections);
}
