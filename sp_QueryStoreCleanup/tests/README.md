# sp_QueryStoreCleanup Tests

Run this harness before and after any change to `sp_QueryStoreCleanup.sql`. A bug here
does not show a wrong number on a screen. It removes the wrong queries from
Query Store, or refuses to remove the right ones. This harness builds Query
Store scratch databases with a known set of queries. It asserts on what the
procedure reports and what it actually removes.

## Automated

| Script | What it does |
| --- | --- |
| `run_tests.py` | Builds several Query Store scratch databases, then asserts on reported and actual removal counts across parameters, report modes, compat levels, and edge cases. 100 assertions on SQL Server 2025. |

```
cd sp_QueryStoreCleanup/tests
python run_tests.py --server SQL2025
```

Takes `--server` and `--password` (default `SQL2025` / the standard local
`sa` password). Expect these totals:

| Version | Passed | Skipped |
| --- | --- | --- |
| SQL Server 2025 | 100 | 0 |
| SQL Server 2022 | 96 | 0 |
| SQL Server 2019 | 85 | 1 |
| SQL Server 2017 | 81 | 1 |

Older versions support fewer compat levels, so they run fewer checks. Versions
before SQL Server 2022 skip the PSP test.

The CI bundle leaves `sp_QueryStoreCleanup` out, so the harness installs the
procedure itself. Pass `--proc-file` to test a version other than the repo
copy, for example a historical commit:

```
python run_tests.py --server SQL2025 --proc-file path/to/sp_QueryStoreCleanup.sql
```

## What it actually covers

- `@help`, and every parameter check: each bad value raises an error, and
  trimmed values are still accepted.
- Report mode counts on a duplicate fixture, for the default call, each
  `@cleanup_targets` value, and each `@dedupe_by` value, plus the result set
  count.
- Text search ignores case in a case-sensitive database (#882).
- The procedure is installed at every compat level the server supports,
  from 100 up to 170. At each level, the default call runs without Msg 8622,
  finds the same 20 queries, and uses HASH JOIN in Step 4 (#867).
- A forced plan is never removed.
- A real removal removes exactly the listed query IDs and nothing else, in
  both `@sort_direction` orders.
- A Query Store in `READ_ONLY`: the error without `@compact_tables`,
  parameter checks with it (#886), and compaction.
- Msg 12402 counts as skipped, not failed (#875). This test uses a generated
  copy of the procedure that removes each query twice.
- On SQL Server 2022 and up: a parameter sensitive plan (PSP) parent and its
  variants. Report mode prints no NULL-aggregate warning, and its
  `oldest_last_execution` and `newest_last_execution` values match Query
  Store exactly (#883). Removal takes the variants before the parent, with
  no Msg 12465.

## Fixture

The harness creates and drops these databases, all prefixed `qsc_`:

| Database | Purpose |
| --- | --- |
| `qsc_dupes` | The duplicate fixture, in a case-sensitive collation. Most report and removal tests run here. |
| `qsc_psp` | A parameter sensitive plan parent query and its variants (SQL Server 2022 and up only). |
| `qsc_readonly` | A Query Store forced into `READ_ONLY`. |
| `qsc_noqs` | Query Store off, for the "not enabled" error. |
| `qsc_tools_100` to `qsc_tools_170` | The procedure installed at one compat level each, for the HASH JOIN test. The harness only creates the levels the server supports. `qsc_tools_140` also holds the copy for the Msg 12402 test. |

`qsc_missing_db` is named in one test but never created, to check the
"database not found" error. A `finally` block drops every database above
even if an assertion fails, so a failed run does not leave scratch databases
behind.

## Two fixture problems

Building a Query Store fixture that gives predictable counts took solving
two problems that have nothing to do with the procedure under test.

### A monitoring tool's own queries land in Query Store

Any tool that polls a database while Query Store is on adds its own queries
to the same capture. This includes a monitoring tool watching the test
server. Without a marker, those extra queries change the counts the tests
check. Every fixture query in `run_tests.py` carries a marker such as
`/* qsc_psp_rows */` in its text. Once the fixture workload has run,
`freeze_and_purge()` stops capture. It then removes every query whose text
does not carry the expected marker, so only the fixture's own queries
remain.

### Query Store reports `READ_WRITE` before it captures anything

`ALTER DATABASE ... SET QUERY_STORE = ON` returns as soon as the setting is
recorded, but Query Store enables itself asynchronously. `query_store_on()`
polls `sys.database_query_store_options.actual_state_desc` for up to 30
seconds and only returns once the state the caller asked for is the actual
state. Query Store only sees a query when it compiles. Even after
`actual_state_desc` says `READ_WRITE`, a plan already sitting in the cache
from the gap before that point is never captured. Each PSP and duplicate
fixture workload attempt clears that database's plan cache first, so every
fixture query compiles again with capture already on.
