# sp_HumanEvents Tests

`sp_HumanEvents` builds an Extended Events session out of dynamic SQL, samples
events for `@seconds_sample` seconds, then shreds and returns what it captured.
Event types it understands (confirmed against the validation list in the proc):

| Category | Accepted `@event_type` spellings | Events the session adds (SQL 2022) |
| --- | --- | --- |
| query | `query`, `queries` | `module_end`, `rpc_completed`, `sp_statement_completed`, `sql_statement_completed`, `query_post_execution_showplan` (unless `@skip_plans = 1`) |
| waits | `waits`, `wait` | `wait_completed` (2014+) / `wait_info` (2012) |
| blocking | `blocking`, `locking`, `block`, `blocks`, `lock`, `locks` | `blocked_process_report` |
| compiles | `compiles`, `compile`, `compilation`, `compilations` | `sql_statement_post_compile` (2017+) or `uncached_sql_batch_statistics` + `sql_statement_recompile` (older); plus `query_parameterization_data` where available |
| recompiles | `recompiles`, `recompile`, `recompilation`, `recompilations` | `sql_statement_post_compile` (2017+) or `sql_statement_recompile` (older) |

**Run the automated suite before and after any change to `sp_HumanEvents.sql`.**
Compiling proves nothing about behavior. This suite catches the proc's
characteristic failure directly: **a generated `CREATE EVENT SESSION` that will
not run** for some event-type / filter-parameter combination on the target
server version.

## The hard problem: don't test live event content

Almost everything `sp_HumanEvents` *returns* depends on **volatile, timing-bound
workload** -- which queries happened to run, which waits happened to fire, which
blocking happened to occur during the few-second sample. Asserting on captured
rows produces a suite that flakes, and a flaky suite is worse than none. So this
harness does **not** assert on captured event rows. It asserts on the thing that
actually breaks when the proc regresses: **whether the dynamic DDL it generates
is valid and is accepted by SQL Server**, plus strict **session hygiene**.

Two levers in the proc make that deterministic and fast, with no slow captures:

- **`@keep_alive = 1`** creates a *permanent* session and `RETURN`s immediately
  -- no `WAITFOR` sample, no drop (the `@keep_alive = 1` branch near line 1777).
  A session that CREATEs successfully is proof the generated DDL is valid on this
  server version. This is the high-value core.
- **`@debug = 1`** prints the generated `@session_sql` via `RAISERROR` (near line
  1768), so the exact DDL can be captured from stdout and inspected.

## Automated

| Script | What it does |
| --- | --- |
| `run_tests.py` | Drives `dbo.sp_HumanEvents` over `sqlcmd`, exercising every accepted `@event_type` and a representative filter matrix with `@keep_alive = 1`, and asserts **195** expectations across seven groups. Self-cleaning and idempotent. |

```
cd sp_HumanEvents/tests
python run_tests.py --server SQL2022
```

`--server` and `--password` default to `SQL2022` / the standard local `sa`
password. Expect `195 passed, 0 failed`. The proc must be installed in `master`
on the target instance (there is a preflight that fails fast if it is not, and a
guard that refuses Azure SQL DB, whose sessions are database-scoped).

The suite has been run green on **SQL Server 2016, 2022, and 2025** (and the
structural + DDL matrix is version-parameterized for 2017/2019 as well). The
expected event set for each `@event_type` is not hard-coded to a version: the
harness **probes the server** for `sql_statement_post_compile`,
`query_parameterization_data`, and the version number, and computes the expected
events accordingly, so it stays correct whether or not a given build exposes the
newer compile/parameterization events.

### What it covers

**1. Structural / smoke (6).** `@help = 1` returns help text and creates no
session; an invalid `@event_type` is rejected with the proc's validation message
(severity 11) and creates no session -- a bidirectional check that validation
actually fires, not just that valid input works.

**2. DDL-validity matrix -- base (90).** For **each of the 18 accepted
`@event_type` spellings**, the harness runs `@keep_alive = 1` and asserts, five
ways: the call raised no severe SQL error; the proc itself raised no error; a
session with the expected generated name now exists in
`sys.server_event_sessions`; the session carries **exactly** the set of events
that event type is supposed to add (read from the authoritative catalog
`sys.server_event_session_events`, which cannot be truncated and proves SQL
Server actually *accepted* each event); and the session is then dropped and
confirmed gone.

**3. DDL-validity matrix -- filters (60).** Twelve representative
filter-parameter combinations across the categories, each asserted the same five
ways. Between them they exercise `@query_duration_ms`, `@database_name`,
`@requested_memory_mb`, `@client_app_name`, `@client_hostname`, `@username`,
`@session_id = 'sample'` + `@sample_divisor`, `@object_name` (+ `@object_schema`
for the blocking object-id path), `@skip_plans = 1` (asserts the showplan event
is **dropped** -- four events, not five), `@custom_name` (asserts the session
name gains the custom suffix), `@wait_type` as a CSV and as `ALL`,
`@wait_duration_ms`, `@gimme_danger`, and `@blocking_duration_ms`.

**4. Debug-DDL capture (21).** For each of the five categories, `@debug = 1` is
captured and the generated `@session_sql` is asserted to contain
`CREATE EVENT SESSION` plus each event the category adds. (`RAISERROR` truncates
a long message near 2044 characters, so the untruncated
`sys.server_event_session_events` check in groups 2 and 3 is the authoritative
one; this group is a secondary guard, plus a check that `@debug` emits its
diagnostic markers.)

**5. Short live sample (6).** Two event types (`waits`, `query`) are run for real
with `@seconds_sample = 3` and `@keep_alive = 0` -- the full
create / sample / query / drop path. Each asserts no severe error, that the proc
**completed on an empty capture without erroring** (the common failure mode for a
quiet instance), and that the proc **dropped its own throwaway session**: the
global count of `HumanEvents%` / `keeper_HumanEvents%` sessions is snapshotted
before and after the call and must be equal.

**6. Logging-to-table + cleanup (10).** `@keep_alive = 1` with
`@output_database_name` enters an **unbounded** collector loop that creates
permanent tables/views for keeper sessions and harvests into them forever. The
tables are created in the first pass (well under a second), so the harness runs
it with a `sqlcmd` query timeout (`-t`), which sends an attention that cancels
the loop **server-side** (verified: a batch cancelled this way does not keep
running). It then asserts the base table `keeper_HumanEvents_waits` and the three
`HumanEvents_Waits*` views were created, exercises the proc's own `@cleanup = 1`
teardown, and asserts the proc removed the session, tables, and views itself.
Everything is created in and dropped with a throwaway scratch database
(`sp_HumanEvents_test_scratch`).

**7. Session hygiene (2).** Around the whole run, `sys.server_event_sessions` is
diffed and the suite asserts **zero net new sessions**, then confirms nothing
remains after the final sweep. The before/after lists and the diff are printed.

### Session hygiene -- non-negotiable

Extended Events sessions are server-global; a leaked running session is a real
problem. The harness treats that as a first-class requirement:

- `sp_HumanEvents` names its sessions predictably --
  `HumanEvents_<event_type>_<guid>` (one-shot) and
  `keeper_HumanEvents_<event_type>[_<custom_name>]` (`@keep_alive = 1`). The
  harness **sweeps both patterns at start** (idempotency: reap anything a prior
  aborted run left) and **in a `finally` block at the end** (so leaks are cleaned
  even when an assertion fails -- verified: a deliberately failing run still left
  zero sessions behind).
- Each `@keep_alive` matrix case **drops its own session immediately** after its
  assertions, so at most one session exists at a time. This is not just tidiness:
  each session reserves a 100 MB ring buffer, and creating all 18 at once demanded
  ~1.8 GB and drew `Msg 701` (out of memory). That is a **test artifact, not a
  proc bug**; dropping-each-first avoids it.
- The short-sample cases assert the proc cleaned up **its own** session.
- The run prints the before/after session lists and asserts they are identical.

### Why the assertions are trusted

The event-set assertions are not rubber-stamps. The `@skip_plans = 1` case
expects **four** events and the plain query case expects **five**; both pass,
which is only possible if the comparison actually discriminates. As an explicit
negative control, injecting a bogus expected event was confirmed to turn the
suite **red** on exactly the affected cases (9 failures) -- and the `finally`
sweep still left **zero** leaked sessions on that failing run. Every event type
was also watched to create a real session and report its real event list before
the expected sets were written.

## What is NOT covered, and why

This is the honest part. A green run means the covered surface -- DDL validity
and hygiene -- works; it does not mean every behavior of `sp_HumanEvents` is
exercised.

- **Captured event content.** By design (see above): which rows come back is
  timing- and workload-bound and cannot be forced deterministically on a shared
  instance. The live-sample group asserts the path *runs and cleans up*, not what
  it returns. This is the large, deliberate gap.
- **`@target_output = 'event_file'`.** Only the default `ring_buffer` target is
  exercised. The `event_file` target writes `.xel` files to the SQL Server's own
  filesystem, and the `@keep_alive` path does not delete them (only the one-shot
  path calls `xp_delete_files`). The harness cannot reliably locate and remove a
  server-side file, so asserting on this target would either leave disk artifacts
  or be flaky. Its DDL differs only in the `ADD TARGET` clause.
- **Azure SQL Database / Managed Instance.** The proc uses database-scoped
  sessions and a different catalog there; the harness refuses to run against an
  Azure engine edition rather than assert box-product invariants that do not hold.
- **The pre-2017 event fallbacks specifically.** The expected-event logic *is*
  version-aware (it would expect `uncached_sql_batch_statistics` /
  `sql_statement_recompile` / `wait_info` on a build that lacks the newer events),
  but every instance available here -- including the 2016 build (13.0.6300) --
  exposes the newer `sql_statement_post_compile` / `query_parameterization_data`
  events, so those specific fallback DDL strings were not observed to CREATE on a
  box that actually lacks them. On a bare RTM 2016/2012 the harness would compute
  the fallback set; that path has not been watched create.
- **Non-`dbo` `@output_schema_name`.** The logging tests use `dbo`. The proc's
  branch that validates a non-default output schema is not exercised.
- **Blocking actually captured.** The blocking session's DDL validity is covered;
  inducing a real blocked-process-report event is not.

## Not wired into CI

Like the other DarlingData behavioral suites, this is **not** part of any GitHub
Actions workflow. It creates and drops server-global Extended Events sessions
(and, for the blocking cases, will briefly set `blocked process threshold` if it
is `0`, restoring it afterward), which is not something to run against shared CI
infrastructure. Run it by hand against a test instance you own. It sweeps every
session it creates and drops every object it creates, but it is a "run it on a
box you control" tool by nature.
