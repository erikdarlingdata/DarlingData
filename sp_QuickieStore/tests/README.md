# sp_QuickieStore Tests

**Run before and after any change to `sp_QuickieStore.sql`.** Compiling proves
very little here: the procedure is ~16,000 lines that assemble a large dynamic
SQL statement whose *shape* changes with almost every one of its 60 parameters.
The statement that breaks is built at run time from string fragments, so it only
fails when it executes.

## Automated

| Script | What it does |
| --- | --- |
| `run_tests.py` | Builds a Query Store scratch database, then runs a parameter matrix asserting each combination executes cleanly and reaches completion, plus bidirectional filter checks. It also checks regression mode and wait stats against Query Store's own numbers. 215 assertions. |

```
cd sp_QuickieStore/tests
python run_tests.py --server SQL2022
```

Takes `--server` and `--password` (default `SQL2022` / the standard local sa
password). Expect `215`.

## What it actually covers

The matrix is the point. Every axis below rewrites the generated statement, and
each run *executes* what it built:

- **All 39 `@sort_order` values** — the highest-value axis. Each builds a
  different `ORDER BY`, and the wait sorts additionally join
  `query_store_wait_stats`.
- **9 `@wait_filter` values**, **4 `@execution_type_desc`**, **4 `@query_type`**.
- The **`@expert_mode` x `@format_output` grid**, which rewrites the column list,
  plus several sort orders combined with expert mode.
- **`@find_parameter_sensitive`**, the plan-shape volatility mode: ranking by
  each volatility metric (work-weighted), the mode grids, floors,
  mode-conflict guard errors, the hash-based include/ignore lists filtering
  shapes bidirectionally (ignore removes the sniffed shape's hash from the
  detail rows, include keeps only it, a hash nobody has returns zero shapes),
  and a fixture procedure (`qs_sniff_proc`) skewed hard enough that the
  `parameter sensitive` signal must fire on a real conviction.

On top of that, **bidirectional** assertions prove the filters actually filter
rather than being silently ignored — `@query_text_search` on a known string vs
nonsense, `@query_type` partitioning proc from ad hoc, `@top`, and
`@execution_count` set impossibly high. Every absence assertion is paired with a
completion check so an errored or empty run cannot pass vacuously.

The case-insensitive text search checks run in a second scratch database
with a case-sensitive collation (`Latin1_General_100_CS_AS`). It holds one
query with the marker `qs_Case_Marker`. A search for the marker in other cases
must find that query, and `@query_text_search_not` in another case must remove
it. `query_sql_text` is `SQL_Latin1_General_CP1_CI_AS` in every database, so a
text search ignores case whatever the database collation is.

Regression mode and wait stats need data in more than one Query Store
interval, so they get their own scratch database with one-minute intervals.
Its workload runs in two slots: slot A when the harness starts, and slot B
after the other tests, in a later interval. In each slot, one `rm_q1`
execution waits on a lock that a second session holds. Slot A runs that
execution last, and slot B runs it first. `rm_q2` never waits. It gets a new
index between the slots, so it has a different plan in each slot.

The checks compare the procedure's output with Query Store's own numbers:

- **Regression mode**, with slot A as the baseline and slot B as the current
  period. Each plan has one row per period. Each period has its own
  execution count and Lock wait. Its last duration comes from its own last
  run.
- **Both slots in one window**, without regression mode. Each plan has one
  row, with its execution count. The `rm_q1` Lock wait covers both slots,
  not just the latest interval.
- **Both runs**: `top_waits` shows the Lock wait for `rm_q1` and none for
  `rm_q2`, and `compilation_stats` and `resource_stats` have one row per
  query.
- **Regression mode with `@log_to_table = 1`**. Each wait row in the
  `WaitStatsByQuery` log table names its period, and the `rm_q1` Lock wait
  for each period matches. This runs twice. The first run logs to tables the
  procedure creates. The second logs to a `WaitStatsByQuery` table built the
  way older versions of the procedure built it, without the period column.
  The procedure has to add the column first.

## Fixture

The harness creates its own `quickiestore_test` database with Query Store on,
runs a small varied workload (ad hoc queries at different costs plus a stored
procedure, so `@query_type` has both kinds to separate), flushes Query Store, and
drops the database in a `finally` block that runs even if assertions fail.
Three smaller scratch databases get the same `finally` cleanup. The `@debug`
check uses `quickiestore_test_empty`, which has Query Store on and no queries.
The text search checks use `quickiestore_test_cs`, which is case sensitive.
The regression and wait checks use `quickiestore_test_rm`, and the logging
checks create their log tables there. Nothing outside these four databases is
touched.

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
