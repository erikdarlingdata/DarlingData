# sp_QuickieStore Tests

**Run before and after any change to `sp_QuickieStore.sql`.** Compiling proves
very little here: the procedure is ~16,000 lines that assemble a large dynamic
SQL statement whose *shape* changes with almost every one of its 59 parameters.
The statement that breaks is built at run time from string fragments, so it only
fails when it executes.

## Automated

| Script | What it does |
| --- | --- |
| `run_tests.py` | Builds a Query Store scratch database, then runs a parameter matrix asserting each combination executes cleanly and reaches completion, plus bidirectional filter checks. 134 assertions. |

```
cd sp_QuickieStore/tests
python run_tests.py --server SQL2022
```

Takes `--server` and `--password` (default `SQL2022` / the standard local sa
password). Expect `134`.

## What it actually covers

The matrix is the point. Every axis below rewrites the generated statement, and
each run *executes* what it built:

- **All 39 `@sort_order` values** — the highest-value axis. Each builds a
  different `ORDER BY`, and the wait sorts additionally join
  `query_store_wait_stats`.
- **9 `@wait_filter` values**, **4 `@execution_type_desc`**, **4 `@query_type`**.
- The **`@expert_mode` x `@format_output` grid**, which rewrites the column list,
  plus several sort orders combined with expert mode.

On top of that, **bidirectional** assertions prove the filters actually filter
rather than being silently ignored — `@query_text_search` on a known string vs
nonsense, `@query_type` partitioning proc from ad hoc, `@top`, and
`@execution_count` set impossibly high. Every absence assertion is paired with a
completion check so an errored or empty run cannot pass vacuously.

## Fixture

The harness creates its own `quickiestore_test` database with Query Store on,
runs a small varied workload (ad hoc queries at different costs plus a stored
procedure, so `@query_type` has both kinds to separate), flushes Query Store, and
drops the database in a `finally` block that runs even if assertions fail.
Nothing outside that database is touched.

## Known client limitation: `@debug = 1`

`@debug = 1` is exercised against a database with **no** Query Store data on
purpose. With data, debug mode returns the generated SQL as an **XML column** (so
it is clickable in SSMS), and **go-sqlcmd renders XML columns pathologically
slowly** — capturing the output takes minutes and looks exactly like the
procedure hanging, with the server parked in `ASYNC_NETWORK_IO` waiting for the
client to drain the result set.

This is a client limitation, not a procedure defect: the same run is instant in
SSMS, and a non-debug run against the same populated database returns at full
width in well under a second. Do not "fix" this by widening timeouts.
