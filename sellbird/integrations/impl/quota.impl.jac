impl _token_from_json_blob(blob: str) -> str | None {
    try {
        data = json.loads(blob);
    } except (json.JSONDecodeError, TypeError) {
        return None;
    }
    oauth = data.get("claudeAiOauth") if isinstance(data, dict) else None;
    token = oauth.get("accessToken") if isinstance(oauth, dict) else None;
    return token if isinstance(token, str) and token else None;
}

impl get_oauth_token -> str | None {
    creds_file = claude_config_dir() / ".credentials.json";
    default_creds = Path.home() / ".claude" / ".credentials.json";
    for path in [creds_file] + ([default_creds] if default_creds != creds_file else []) {
        try {
            token = _token_from_json_blob(path.read_text(encoding="utf-8"))
                if path.is_file()
                else None;
            if token {
                return token;
            }
        } except OSError as e {
            if path is creds_file {
                logger.debug(f"Could not read {creds_file}: {e}");
            }
        }
    }
    if sys.platform == "darwin" {
        for service in _keychain_services() {
            try {
                result = subprocess.run(
                    ["security", "find-generic-password", "-s", service, "-w"],
                    capture_output=True,
                    text=True,
                    timeout=5,
                );
            } except (subprocess.TimeoutExpired, OSError) as e {
                logger.debug(f"Keychain lookup failed for {service}: {e}");
                continue;
            }
            token = _token_from_json_blob(result.stdout.strip())
                if result.returncode == 0
                else None;
            if token {
                return token;
            }
        }
    }
    return None;
}

impl _keychain_services -> list[str] {
    services = [KEYCHAIN_SERVICE];
    marker = "\"svce\"<blob>=\"";
    try {
        dump = subprocess.run(
            ["security", "dump-keychain"], capture_output=True, text=True, timeout=10
        );
        if dump.returncode == 0 {
            for line in dump.stdout.splitlines() {
                name = line.split(marker, 1)[1].rstrip("\"") if marker in line else "";
                if name.startswith(KEYCHAIN_SERVICE) and name not in services {
                    services.append(name);
                }
            }
        }
    } except (subprocess.TimeoutExpired, OSError) as e {
        logger.debug(f"Keychain enumeration failed: {e}");
    }
    return services;
}

impl _parse_window(value: any) -> dict[str, any] | None {
    utilization = value.get("utilization") if isinstance(value, dict) else None;
    if not isinstance(utilization, (int, float)) {
        return None;
    }
    resets_at = value.get("resets_at") or value.get("resetsAt") or "";
    return {"utilization": float(utilization), "resets_at": str(resets_at) if resets_at else ""};
}

impl QuotaClient.init {
    self._lock = asyncio.Lock();
}

impl QuotaClient.get_utilization -> dict[str, any] | None {
    async with self._lock {
        now = time.monotonic();
        if self._cache_at and now - self._cache_at < self._cache_ttl {
            return self._cache;
        }
        result = await self._fetch();
        self._cache = result;
        self._cache_at = now;
        self._cache_ttl = CACHE_TTL_OK if result else CACHE_TTL_FAIL;
        return result;
    }
}

impl QuotaClient._fetch -> dict[str, any] | None {
    token = await asyncio.get_event_loop().run_in_executor(None, get_oauth_token);
    if not token {
        logger.debug("Quota: no Claude OAuth token found; falling back.");
        return None;
    }
    try {
        async with httpx.AsyncClient(timeout=REQUEST_TIMEOUT) as client {
            resp = await client.get(
                USAGE_URL,
                headers={"Authorization": f"Bearer {token}", "anthropic-beta": OAUTH_BETA_HEADER},
            );
        }
    } except httpx.HTTPError as e {
        logger.debug(f"Quota fetch failed: {e}");
        return None;
    }
    if resp.status_code != 200 {
        logger.debug(f"Quota endpoint returned {resp.status_code}.");
        return None;
    }
    try {
        payload = resp.json();
    } except ValueError {
        return None;
    }
    if not isinstance(payload, dict) {
        return None;
    }
    windows = {key: _parse_window(payload.get(key)) for key in ("five_hour", "seven_day")};
    return {k: v for (k, v) in windows.items() if v} or None;
}
