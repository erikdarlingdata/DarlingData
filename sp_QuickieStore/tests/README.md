# sp_QuickieStore Tests

**Run before and after any change to `sp_QuickieStore.sql`.** Compiling proves
very little here: the procedure is ~20,000 lines that assemble a large dynamic
SQL statement whose *shape* changes with almost every one of its 60 parameters.
The statement that breaks is built at run time from string fragments, so it only
fails when it executes.

## Automated

| Script | What it does |
| --- | --- |
| `run_tests.py` | Builds a Query Store scratch database, then runs a parameter matrix asserting each combination executes cleanly and reaches completion, plus bidirectional filter checks. It also checks regression mode and wait stats against Query Store's own numbers. 350 assertions. |

Install `sp_QuickieStore.sql` into `master` on the target server first. The
script stops with an error if `dbo.sp_QuickieStore` is not there.

```
cd sp_QuickieStore/tests
python run_tests.py --server SQL2022
```

Takes `--server` and `--password` (default `SQL2022` / the standard local sa
password). Expect `346` (`347` on SQL Server 2017, which skips the rule 14 check at
compatibility level 150 and up but runs two more rule 1 checks, because before SQL Server 2019 the
suggested table variable index has no inline INCLUDE).

The harness needs go-sqlcmd: it passes `-W` together with `-y`, which the older ODBC
`sqlcmd` rejects.

To run only the multi-database group, add `--only multidb`. To run only the
plan findings group, add `--only plan_parsing`.

## What it actually covers

The matrix is the point. Every axis below rewrites the generated statement, and
each run *executes* what it built:

- **38 `@sort_order` values** — the highest-value axis. Each builds a
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
- **`@find_high_impact`**: the default run, the absolute total columns, and
  the hash-based include and ignore lists filtering bidirectionally.
- **`@plan_parsing`**, the plan findings result set. A scratch database with a
  1,000,000 row table and one query per rule (0 to 14, 16 and 18), each found
  in Query Store by a marker comment. Each rule must show up for its query
  with its `rule_id` and `rule_name`. A primary key seek, a cheap serial query
  and a UDF query must stay quiet where the rules say so, and rule 3 must not say a UDF forced
  a serial plan that is serial for MAXDOP 1. Rule 7 must pass its
  executions per day gate with a short `@start_date` and fail it with the
  default window. Rule 14 must fire below compatibility level 150 and stay
  quiet at 150 and up. The column list is pinned, `@plan_parsing = 0` must
  return no findings, and each rejected combination must raise an error. A
  failed rule check prints the fixture query's operator list (NodeId,
  PhysicalOp/LogicalOp) from its Query Store plan. Regression fixtures cover
  the review findings: rule 1 must suggest the inline `INDEX` for a spool on a table variable, and must script a valid `CREATE INDEX` (bracketed,
  comma separated, no duplicates, no `Expr` columns, parses under
  `PARSEONLY`), rule 4 must separate the fetched columns and name the column its own predicate reads, and stay quiet for a lookup into a system table, rule 5 must fire for a
  `NOT NULL` key `NOT IN` a nullable indexed column (the `IS NULL` test is the
  seek or its residual predicate), and stay quiet for `NOT IN` over `NOT NULL`
  keys, for `NOT EXISTS` with a time range on a nullable column, and for a
  hand-written wildcard (`n = x OR n IS NULL`) with no `NOT IN` in the text,
  rule 2 must flag `MaxDOPSetToOne` for a plan compiled under a database MAXDOP of 1 once the setting is back at 0, with a finding that says MAXDOP may have been 1 when the plan compiled, and must ignore `OPTION (MAXDOP 1)` in a comment and the fetch step of a
  `DYNAMIC` cursor (the fixture asserts it has the CPU), rule 10 must fire for a
  function over a table variable column, rule 1's `INCLUDE` must cover the column
  behind a computed spool output, `@workdays = 1` must run cleanly, `@troubleshoot_performance = 1` must time the plan parsing steps, `@debug = 1` must dump without Msg 208 on the
  early exits (a missing database, a bad time zone), rules 8 and 12 must stay quiet for the
  optimizer's own filter and Top, rule 8 must stay quiet for a filter on an aggregate result, for `HAVING` and for a filter on `ROW_NUMBER()`, and must fire for a filter on a Compute Scalar over table columns and for a mixed predicate (a table column and a window aggregate), and rule 8 must stay quiet for the index key change Filter over a Split in a wide `UPDATE` (`QUERYTRACEON 8790`), and for a filter on the probe result of a semi join (a Merge Join and a Nested Loops plan), and for an `OR` whose other part reads a batch mode `COUNT_BIG(*) OVER` (skipped below compatibility level 150), while the `AND` form still says part of it reads a window result, rule 0 must not fire for a plan that is only
  an `IF` condition, and `STATIC`, `KEYSET` and `DYNAMIC` cursors list each node id with its
  phase (`10 (populate)`), the phase has that operator, and the `KEYSET`
  lookup finding names the right table, and in a self-join does not list the outer alias's column. Rule 1 on a table variable must
  parse as suggested: before SQL Server 2019 with the include column at the end of the key. The rule 18 fixture is pinned with trace flag 8690, `FORCE ORDER` and
  `MAXDOP 1`, because a small machine puts a spool over the scan. Rules
  15 (needs a linked server), 17 (needs Standard Edition) and 19 (needs a
  compile of 1 second or more) are not covered.
- **`@include_query_hash_totals`**: the `by_query_hash` columns are in the
  output, and a date window with no queries returns no detail rows.
- **Id lists**: ids separated by commas, spaces, or line breaks return the
  same rows. A list of 380 plan ids is split without Msg 9400.
- **Escape characters**: each escape character finds `qs_Case_Marker`, and the
  underscore is not a wildcard.
- **Multiple databases**: `@get_all_databases = 1` with `@expert_mode` against
  two scratch databases whose Query Store ids collide. The output must have
  the compilation stats row of every query.

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
execution last, and slot B runs it first.

`rm_q3` reads the same row and also waits once in each slot. It waits after
`rm_q1` in slot A, and before it in slot B. So the latest Lock wait comes
from a different query in each period. `rm_q2` never waits. It gets a new
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
- **Wait stats in total**, in both runs. Each wait category has one row, and
  in regression mode one row per period. The Lock total covers `rm_q1` and
  `rm_q3`, and it matches. Each total row also matches the by-query rows for
  its category and period. Totals are the sum, and averages are the average
  of the plan averages. Minimums and maximums are the lowest and the highest.
  The last wait and the last duration come from the plan with the latest
  wait in the category. That plan is `rm_q3` in the baseline period, and
  `rm_q1` in the current period and in the whole window.
- **Regression mode with `@log_to_table = 1`**. Each wait row in the
  `WaitStatsByQuery` log table names its period, and the `rm_q1` Lock wait
  for each period matches. The `WaitStatsTotal` log table has one Lock row
  per period, and its total for `rm_q1` and `rm_q3` matches. This runs twice.
  The first run logs to tables the procedure creates. The second logs to
  `WaitStatsByQuery` and `WaitStatsTotal` tables built the way older versions
  of the procedure built them, without the period column. The procedure has
  to add the column first.

## Fixture

The harness creates its own `quickiestore_test` database with Query Store on,
runs a small varied workload (ad hoc queries at different costs plus a stored
procedure, so `@query_type` has both kinds to separate), flushes Query Store, and
drops the database in a `finally` block that runs even if assertions fail.
Five smaller scratch databases get the same `finally` cleanup. The `@debug`
check uses `quickiestore_test_empty`, which has Query Store on and no queries.
The text search checks use `quickiestore_test_cs`, which is case sensitive.
The regression and wait checks use `quickiestore_test_rm`, and the logging
checks create their log tables there. The multi-database checks use
`quickiestore_test_md1` and `quickiestore_test_md2`, which have colliding
Query Store ids. Nothing outside these six databases is touched.

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
