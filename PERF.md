# Performance: the Jac rewrite against the original Python

This compares three builds of Sellbird on the same inputs:

- **Python**: the original code, commit `b21238525`, run from its source tree.
- **Jac before**: the neojac rewrite as this branch started (`0768dc2`, the head of `neojac-deslop`).
- **Jac after**: this branch (`neojac-perf`).

The short version: the rewrite started out slower nearly everywhere: by 5–9% on most commands, 45%
on dashboard start-up, 31–93% on the company register and 7.7x on the checks every outgoing email
goes through. After this branch it is at the Python's speed on start-up, commands, page reading and
the send gate, and faster on the company register (1.14x for the command, 1.37–1.49x on the
dashboard). Every part of Sellbird still runs in a `cpython` space. Moving code to a native space
made each candidate slower, for reasons measured below.

## How it was measured

- **Same interpreter and packages.** Both sides run on neojac's CPython 3.15.2 with the project's
  `.jac/venv`. The Python side has the original source tree on `PYTHONPATH`; the Jac side has
  the build, `.jac/build/pypi/top/site`. So the difference measured is the code, not the
  interpreter or the dependencies.
- **Same data.** `scripts/perf/setup.sh` seeds one database with the original code: 1,500
  fictional companies (`exampleN.example.com`), 1,576 prospects, 17,317 observations and 500
  queued emails. Each side gets its own copy of it, with the shipped `sellbird.yaml`, prompts
  and skills. `HOME` points at an empty folder, so the live Claude quota and the user's own
  settings stay out of it.
- **Alternated, medians.** Each round runs every side once, and the order rotates from round to
  round. The figures are medians: 9 rounds for commands, 5 for in-process workloads (each of
  which repeats its requests 5 times and takes the median of those), 3 for the test suite.
- **Outputs compared.** Commands: exit code and stdout, with the home folder's path masked.
  Endpoints: status and body. Page reading and gate: every result, hashed. `companies` and
  `export`: the CSV files, byte for byte.
- **Machine.** A shared Intel i9-10850K (20 threads, 62 GB). The 1-minute load average was
  2.5–3.5 throughout, from other users' work. Run-to-run noise on a 200 ms command was about
  ±3 ms.

Commands to rerun everything are at the end.

## Results

Times in milliseconds. "Python / after" above 1.00x means the Jac is faster.

### Start-up and commands (9 rounds, load 2.5–2.8)

| Workload | Python | Jac before | Jac after | Python / after | Output |
|---|---:|---:|---:|---:|---|
| `python -c pass` (the interpreter alone) | 21 | 21 | 21 | 1.00x | same |
| `import sellbird.cli` | 65 | 67 | 68 | 0.96x | same |
| `import sellbird.dashboard` | 337 | 490 | 339 | 1.00x | same |
| `import sellbird.mcp_server` | 595 | 589 | 592 | 1.01x | same |
| `import sellbird.main` (the `run` loop) | 186 | 231 | 194 | 0.96x | same |
| `sellbird --help` | 227 | 242 | 230 | 0.99x | same |
| `sellbird status` | 445 | 466 | 452 | 0.98x | same |
| `sellbird signals` | 243 | 259 | 247 | 0.98x | same |
| `sellbird export --all` | 238 | 254 | 241 | 0.99x | same |
| `sellbird companies` (1,500-row register) | 478 | 627 | 420 | **1.14x** | same |
| `sellbird discover --providers` | 249 | 273 | 253 | 0.99x | same |
| `sellbird outbox` | 227 | 244 | 228 | 0.99x | same |
| `sellbird suppressions` | 219 | 238 | 222 | 0.99x | same |
| `sellbird sending status` | 213 | 232 | 216 | 0.99x | same |

### Dashboard endpoints, in process (5 rounds × 5 requests, load 2.8)

| Endpoint | Python | Jac before | Jac after | Python / after | Output |
|---|---:|---:|---:|---:|---|
| `/api/companies` | 208 | 345 | 152 | **1.37x** | same |
| `/api/export/companies.csv` | 161 | 311 | 107 | **1.49x** | same |
| `/api/export/prospects.csv` | 5,975 | 24 | 24 | 250x | same (see note 1) |
| `/api/outbox` | 22.8 | 24.3 | 23.5 | 0.97x | same |
| `/api/today` | 47.0 | 45.8 | 46.4 | 1.01x | same |
| `/api/cohort.csv?require=SERP_RANK` | 51.7 | 52.2 | 53.2 | 0.97x | same |
| `/api/signals` | 33.4 | 33.6 | 34.2 | 0.98x | same |
| `/api/campaigns` | 22.0 | 22.4 | 22.4 | 0.98x | same |
| `/api/setup-status` | 14.7 | 14.7 | 14.7 | 1.00x | same |
| `/api/usage` | 13.2 | 13.0 | 13.1 | 1.01x | same |
| `/api/stats` | 12.9 | 13.0 | 13.0 | 0.99x | same |
| `/api/prospects` | 12.4 | 12.4 | 12.4 | 1.00x | same |
| `/api/company` | 8.8 | 8.9 | 8.9 | 0.99x | same |
| `/api/sending-mode` | 8.8 | 8.9 | 8.9 | 0.99x | same |
| `/api/offer` | 6.9 | 7.0 | 7.1 | 0.98x | same |
| `/api/settings` | 6.8 | 6.9 | 6.9 | 0.99x | same JSON, key order differs (note 2) |
| `/api/discover/providers` | 6.5 | 6.5 | 6.1 | 1.08x | same |
| `/api/trend` | 3.9 | 3.8 | 3.8 | 1.03x | same |
| `/api/runs` | 3.3 | 3.5 | 3.5 | 0.96x | same |
| `/api/sellbird/status` | 2.7 | 2.7 | 2.6 | 1.03x | same |
| `/api/conversations` | 1.9 | 1.7 | 1.8 | 1.09x | same |
| `/api/activity` | 1.8 | 1.7 | 1.7 | 1.07x | same |
| `/` (index page) | 1.2 | 1.2 | 1.2 | 1.02x | same |

### Prospecting and sending work, in process (5 rounds, load 2.8)

| Workload | Python | Jac before | Jac after | Python / after | Output |
|---|---:|---:|---:|---:|---|
| Reading 40 fictional sites twice (people, owners, menus, emails, tech stack, YC/accelerator/funding claims, job boards, style check) | 3,103 | 3,263 | 3,103 | 1.00x | same |
| Gate checks on 200 emails (`pre_send_check` + `autopilot_review`) | 97 | 745 | 100 | 0.97x | same |

### Test suite (3 rounds)

| Workload | Python | Jac before | Jac after | Python / after | Result |
|---|---:|---:|---:|---:|---|
| Full suite, wall time (s), load 3.4 | 261.8 | 266.2 | 263.0 | 1.00x | 3,700 passed, 29 skipped on all three |

The suite's time goes to waiting (subprocess fakes, timeouts and retries under test), so it
moves little either way. The runs ranged 260.9–262.4 s (Python), 262.7–263.3 s (after) and
264.3–267.9 s (before).

Notes:

1. The Python's prospect CSV export re-reads `sellbird.yaml` once per prospect to get the
   do-not-contact list. The rewrite already read it once per export, before this branch. That
   is a code fix made during the rewrite, not something neojac did.
2. The rewrite returns `gmail_authorized` and `m365_authorized` last in `/api/settings`. Same
   keys and values. It was like that before this branch, and the dashboard reads the object by
   key.
3. Where "after" is 1–4% behind the Python, most of the gap is the fixed cost of neojac's
   runtime module (about 2 ms a process, blocker 1) and `_jac.held` wrappers (blocker 2).

## What made the difference

Everything that changed is in the `cpython` space Sellbird already ran in. Each step kept the
outputs identical and the test suite at 3,700 passed, 29 skipped, the same as before.

### 1. Imports the Python made at call time are made at call time again

The rewrite turned the Python's in-function imports into archwire wires, which bind at module
load. Importing `sellbird.dashboard` pulled in 198 more modules than the Python, among them
`main`, the writer, discovery, offer, brain, codex, uvicorn, dnspython and aiosmtplib: +150 ms.
Each handler now writes `import from <module> { ... }` in its body, as the Python did. The wire
stays in `archwire.jac`, and an in-body import is emitted as a call-time import.

| Entry point | Modules loaded: Python | Jac before | Jac after |
|---|---:|---:|---:|
| `import sellbird.dashboard` | 470 | 669 | 471 |
| `import sellbird.main` | 277 | 359 | 294 |
| `sellbird --help` | 322 | 349 | 323 |
| `sellbird discover --providers` | 376 | 381 | 377 |

The one extra module everywhere is neojac's runtime, `_jac_sellbird`. The same treatment went to
`brain` (codex, quota, claude_runtime, home), `mail_provider` (http.server, webbrowser, the
signature module), `inbox_cli`, `inbox_routes` and `desktop_cli` (SMTP and log redaction),
discovery (ATS, gate, signals), `gate` (untrusted) and `mcp_server` (extensions). The OAuth
loopback server moved to its own module, `sellbird/integrations/loopback.jac`, because a class
cannot subclass a module imported in a function body (blocker 4).

Six test files had been changed during the rewrite to patch `sellbird.dashboard.load_config` and
similar names. With call-time imports, the patch target is the source module again, so they went
back to the original tests' targets. Five of them are now identical to the original;
`test_pidfile.py` keeps the rewrite's `LOCK_FILE` patches, which still apply.

Effect: dashboard start-up 490 → 339 ms; `import sellbird.main` 231 → 194 ms; every command
12–16 ms faster.

### 2. No runtime conversion of row lists at typed boundaries

In a `cpython` space every value from a Python library is `any`. When one reaches a typed slot
(a parameter, a return type, an annotated local), neojac emits `_jac.convert(value, type)`. For
`str` that is about 250 ns. For a container it walks the whole thing: 20 rows into a
`list[dict[str, any]]` parameter cost 42.7 µs a call, against 0.04 µs for `any` (blocker 2 has
the repro).

The rewrite had typed many helpers that receive database rows:

- **Gate, per outgoing email.** `gate._instruction_runs` caches an index of word runs from the
  prompts and skills, to catch emails that quote Sellbird's own instructions. The cache was a
  `dict[str, any]` and the function returned `dict[any, str]`, so every call converted the whole
  index: about 3.7 ms per email, where the Python does one dictionary lookup. The index is now a
  typed glob. 200 emails: 745 → 100 ms.
- **Company register.** `company_fit`, `current_roles`, `company_status`'s `_has`, `_contact`,
  `_csv_row` and `to_csv` now take rows as `any`, which is what the Python had. The CSV export
  had converted all 1,500 row dicts per request.
- **Outbox.** `_signal_value` and `_context` converted every observation and prospect row.
- **Text from `re`, `html` and `unicodedata`.** Where a typed result comes straight from one of
  these, the code says `str(...)`. That is Python's own `str` (33 ns on a `str`), which neojac's
  docs give as the way to convert.

### 3. Slow code: the rewrite's, and some the Python had too

- The rewrite stored six regular expressions as strings (`_SENTENCE_RE`, `_BLOCK_TAG_RE`,
  `_ATTR_TEXT_RE`, `_HONORIFIC`, `_CREDENTIAL_TAIL`, `_LINE_BREAK`), so each use went through
  `re`'s cache. They are compiled once again, as the Python had them. (`re._compile` calls in
  page reading: 386k → 261k; the Python: 250k.)
- `people._norm_title` ran a Python callback on every lowercase word of a title, to rewrite
  French feminine titles. That was 100k callbacks for one register. It now matches only the
  words it rewrites, `(?<![a-z])(?:presidente|directrice|...)(?![a-z])`. That replaces exactly
  what the old `[a-z]+` callback replaced, since every key is pure `[a-z]`. `_norm_title`,
  `_family_key` and `_clean_for_target` are pure functions of their strings and run on the same
  few ICP titles thousands of times, so they now remember up to 4,096 recent answers. The
  Python has the same cost; this is where the register gets ahead of it.
- `company_fit` stops at the first decision-maker title that matches, instead of testing every
  observed title and keeping the first match.

## Which space each part runs in

`archwire.jac` puts the whole package in one `cpython` space (`space sellbird: cpython { "."; }`)
and the tests and scripts in another (`sellbird_dev`). Nothing runs in a native space, before or
after this branch. That isn't for lack of trying.

**How it would work.** A `cpython` package can carry native code: `[extensions."sellbird/_x"]
jac = "native/x.jac"` in `jac.toml` builds a Jac module to machine code as a CPython extension
module. I built one into Sellbird's wheel and called it from Python; it works. The wheel's tag
becomes `cp315-cp315-linux_x86_64` instead of `cp315-none-any`.

**Why nothing moved.** Measured on neojac 0.5.1, against the same work in Python
(`scripts/perf/repro/native_vs_cpython`):

| Work | CPython | Native | |
|---|---:|---:|---|
| `re.sub` normalising 20,000 titles | 48.6 ms | 74.2 ms | native 1.5x slower |
| `re.search` on 20,000 titles | 18.4 ms | 23.1 ms | native 1.3x slower |
| Summing word counts over a 20,000-string list passed in, ×20 | 107 ms | 437 ms | native 4x slower: the list is converted at the crossing |
| A per-character loop over 88 KB, one call | 6.9 ms | 1.3 ms | native 5.3x faster |
| A dict counting loop, 300k steps, one call | 68.7 ms | 43.1 ms | native 1.6x faster |
| Loading the extension module | — | 3.4 ms | per process; the `.so` is 6.1 MB for one function |

Sellbird's hot code is regular expressions, `str` methods, `html`, `unicodedata`, sqlite and
JSON. In CPython all of those already run in C. The only per-character loops are a dashboard
token check and a dash check per email, worth microseconds a call, under the 3.4 ms the
extension costs to load. Native code wins only on loops written in Jac that make few crossings.
Sellbird has none worth that load cost, so every module stays in the `cpython` space.

## Blockers and limits, with reproductions

Each reproduction is a small project under `scripts/perf/repro/`. Copy it out and run
`neojac build` there; for the program ones, then `./dist/repro/repro`.

1. **The runtime module costs about 2 ms a process.** Every `cpython` space build imports
   `_jac_<package>.py`, which imports `json`, `enum`, `threading`, `contextvars`, `weakref` and
   `marshal` at module level: 0.74 ms of its own, 7.8 ms with what it imports. In Sellbird about
   2 ms of that is modules the Python wouldn't have loaded by then (`json` 1.3 ms, `datetime`).
   It is generated by neojac, so this branch cannot change it.
   Repro: `python -X importtime -c "import _jac_sellbird"` with the build on `PYTHONPATH`.

2. **Typed boundaries convert at run time, and containers are walked.** No construct declares
   an `any` from Python to be a `str` or a `list[dict[str, any]]` without a runtime check.
   `str(x)` is cheap for strings. For containers the only cheap option is typing them `any`,
   which gives up the static types. Every read through an `any` is also wrapped in `_jac.held()`
   (an `isinstance` check for structs, about 0.2 µs), even in a `cpython` space, which has no
   structs: 147k calls in one cohort CSV request. Converting `list[T]` to `list[any]` walks the
   list too.
   Repro: `repro/convert_cost` prints `20 rows into list[dict[str, any]]: 42.73 us a call; into
   any: 0.04 us` and `any -> str by annotation: 250 ns; by str(): 33 ns`. `neojac emit-py`
   shows `rows_typed(_jac.convert(rows, (list, (dict, str, None))))`.

3. **A bound method taken from a comprehension-captured loop variable is the `Cell`'s.**
   `[v for v in map(r.get, cols)]` inside `for r in rows` raises `AttributeError: 'Cell' object
   has no attribute 'get'`, while `[r.get(k) for k in cols]` works. I found this trying to cut
   the `held` calls in the cohort export and reverted it. Miscompilation, neojac 0.5.1.
   Repro: `repro/bound_method_of_cell`.

4. **A class can't subclass a module imported in a function body.** `import http.server;` (or
   `import from http.server { BaseHTTPRequestHandler }`) inside a `def`, then
   `class Handler(http.server.BaseHTTPRequestHandler) {}`, is
   `error[E2018]: unknown base 'http.server.BaseHTTPRequestHandler'`. Python allows it, and the
   original did it to keep `http.server` out of start-up. Worked around by moving the loopback
   server into its own module.
   Repro: `repro/class_base_in_body`.

5. **Glob initialisers run before decorated functions exist.** A glob whose initialiser calls an
   `@functools.lru_cache` function fails at import with `NameError: name 'key' is not defined`.
   Undecorated functions are fine. So memoising `_family_key`, which a glob calls, with
   `lru_cache` was impossible; small explicit memo dicts do the job.
   Repro: `repro/decorated_glob`.

6. **Native code: regex slower, and crossings pay for collections.** As in the table above,
   neojac's native `re` is 1.3–1.5x slower than CPython's, a `list[str]` argument is copied
   element by element, and an extension module costs 3.4 ms and 6 MB to load. Not a defect;
   it is why no Sellbird code moved to a native space.
   Repro: `repro/native_vs_cpython`. Build, then run `bench/bench_re_and_lists.py` and
   `bench/bench_loops.py` with `.jac/build/pypi/top/site` on `PYTHONPATH`.

Two smaller things met on the way:

- `neojac check` passed with `.py` files under `scripts/` importing modules no wire declared;
  only `neojac build` reported them (E1575).
- `neojac fmt` moves the in-body imports a script inserts to the body's indentation. Running it
  after such an edit is enough.

## Rerunning it

```sh
export SELLBIRD_BASE=/path/to/original/checkout   # commit b21238525
export PERF_DIR=/tmp/sbperf                       # scratch: seeded homes and results
neojac install && neojac build
scripts/perf/setup.sh                             # seed 1,500 companies, one home per side
. scripts/perf/common.sh
$PY scripts/perf/cli_bench.py 9 $PERF_DIR/cli.json        # start-up and commands
$PY scripts/perf/inproc_bench.py 5 $PERF_DIR/inproc.json  # endpoints, page reading, gate
$PY scripts/perf/tests_bench.py 3 $PERF_DIR/tests.json    # the test suite
```

To add the third side, set `JAC_BEFORE` to another checkout's `.jac/build/pypi/top/site` (and
`JAC_BEFORE_CHECKOUT` to that checkout, for the tests) before `setup.sh`.
`scripts/perf/convert_profile.py <script or -m module> ...` ranks `_jac.convert` call sites by
time. It is how the boundaries in section 2 were found.
