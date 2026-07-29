# sp_PerfCheck Tests

`sp_PerfCheck` is a read-only server-health diagnostic. It inspects DMVs,
`sys.configurations`, and server state and returns two result sets:

1. `#server_info` -- columns `[Server Information]`, `[Details]`
2. `#results` -- columns `check_id`, `priority`, `priority_label`, `category`,
   `finding`, `database_name`, `object_name`, `details`, `url`

**Run the automated suite before and after any change to `sp_PerfCheck.sql`.**
Compiling proves nothing about behavior. This suite catches crashes, output-shape
regressions, and regressions in the checks whose firing conditions can be created
deterministically.

## The hard problem: determinism on a shared instance

Almost every `sp_PerfCheck` finding depends on **volatile server state** you
cannot control on a shared test box -- offline schedulers, read/write latency,
memory-starved queries, deadlock counts, memory dumps, accumulated wait
statistics. Asserting on any of those produces a suite that flakes, and a suite
that flakes is worse than no suite. So this harness asserts **only** on things
that are controllable or structurally invariant, and it is honest (below) about
the large surface it therefore does not cover.

## Automated

| Script | What it does |
| --- | --- |
| `run_tests.py` | Drives `dbo.sp_PerfCheck` over `sqlcmd`, parses the two result sets, and asserts **39** expectations across four groups: 11 structural/smoke, 12 forced server-configuration, 11 forced database-configuration, 5 inaccessible-database regression. Self-cleaning and idempotent. |

```
cd sp_PerfCheck/tests
python run_tests.py --server SQL2022
```

`--server` and `--password` default to `SQL2022` / the standard local `sa`
password. Expect `39 passed, 0 failed`. The proc must be installed in `master`
on the target instance (there is a preflight that fails fast if it is not).

### What it covers

**1. Structural / smoke (11).** These catch crashes and output-shape regressions
across versions, and are always valid regardless of instance state:

- default run raises no severe SQL error (severity 16+);
- default run populates `#server_info` (the always-present `Run Date` row);
- default run emits the `#results` set with all nine expected column names;
- every `#results` row is well formed -- carries a `check_id`, `priority`,
  `category`, and `finding`;
- `@help = 1` returns help text and short-circuits (no findings, no
  `#server_info`);
- `@debug = 1` runs clean, prints diagnostics, and still completes.

**2. Forced server-configuration (12).** The "Cost Threshold for Parallelism Too
Low" check (`check_id 1004`) reads `sys.configurations`, and cost threshold for
parallelism is an advanced option that needs no restart, so it is safe to flip on
a test instance. The harness drives it to three values and proves both the
finding **and its severity escalation**:

| `cost threshold for parallelism` | Expected |
| --- | --- |
| 55 (sane, >= 50) | finding **absent** |
| 5 (the bad default) | finding **present** at High (priority 20) |
| 25 (low, but not the default) | finding **present** at Low (priority 40) |

The presence assertions also check the row is well formed (`check_id 1004`,
`category = Server Configuration`) and that `details` names the configured value.
The **absence** assertion is paired with a **positive control** -- `#server_info`
is populated on the same run -- so an empty or failed result set cannot pass
vacuously; the matching presence assertions are the proof that the check itself
actually runs. The three-value design is what makes the graduated priority
testable: a harness that only proved "fires below 50" would not notice the High
and Low bands collapsing into one.

The option's **original `value_in_use` is captured first and restored precisely**
in a `finally` block that runs even on assertion failure, and the harness dumps
the entire `sys.configurations` table before and after and asserts **zero net
change**. `show advanced options` is set while configuring and restored the same
way. The suite is idempotent: run it twice, same result, no leaked config.

Before baselining, the harness issues a bare `RECONFIGURE` to flush any
pre-existing pending config change. Some images ship one (the SQL Server 2017 CI
container has `clr strict security` configured on but not yet in use), and
without the flush the harness's own `RECONFIGURE` calls would apply that staged
change mid-run and it would surface as a net change the harness never made.

**3. Forced database-configuration (11).** Two database-level checks read pure,
instantly-reversible metadata, so a **throwaway scratch database**
(`perfcheck_test_scratch`, created and dropped by the harness) can force each on
and off:

| Check | check_id | Forced via |
| --- | --- | --- |
| Auto-Shrink Enabled | 7001 | `ALTER DATABASE ... SET AUTO_SHRINK ON/OFF` |
| Auto Update Statistics Disabled | 7004 | `ALTER DATABASE ... SET AUTO_UPDATE_STATISTICS OFF/ON` |

The two toggles control each other's positive control: in each of two runs one
finding is present (scoped to the scratch database **by name**, which proves the
database was actually analyzed) while the other is absent (a real absence, not a
skipped database). Across the two runs each toggle is proven both present and
absent. The scratch database is dropped in a `finally` block, and setup is
idempotent (it drops any leaked copy first).

**4. Inaccessible-database regression (5).** A separate scratch database
(`perfcheck_test_inaccessible`) is closed with `AUTO_CLOSE` and then taken
`OFFLINE`, and the harness asserts that a scoped run against each state, plus a
**whole-instance run with the offline database present**, all complete without a
severe error. See the section below for what this is guarding.

### Why the forced-condition assertions are trusted

Every forced-condition assertion was watched fail-to-fire at the non-triggering
state and fire at the triggering state before being trusted. The pairing is what
makes it non-vacuous: if detection were broken so the finding never appeared, the
**present** assertion would fail; if it always appeared, the **absent** assertion
would fail. Both passing means detection is correct and bidirectional. A harness
built with `forced == default` (so the "present" run could never fire) was
confirmed to go red, proving the assertions are not rubber-stamps.

## What is NOT covered, and why

This is the honest part, and it is a required part. The following checks read
**volatile or environment-bound state that cannot be created and reset
deterministically** on a shared instance, so this harness deliberately does not
assert on them. Do not read a green run as "all of `sp_PerfCheck` works" -- it
means the covered surface works.

**Volatile runtime state (cannot be forced without destabilizing the box, and
would flake run-to-run):**

- Offline CPU Schedulers (`4001`)
- Memory-Starved Queries: Forced Grants (`4101`) and Grant Timeouts (`4103`) --
  both depend on live resource semaphore counters
- Memory Dumps Detected In Last 90 Days (`4102`) -- depends on dump history
- High Number of Deadlocks (`5103`) -- depends on the deadlock counter
- Large Security Token Cache (`4104`)
- Slow Read Latency / Slow Write Latency (`3001`, `3002`) and the drive-level
  rollup (`3003`) -- from `sys.dm_io_virtual_file_stats`; latency cannot be
  dialed to a threshold on demand
- Everything in the **Wait Statistics** (`6001`), **CPU Scheduling**
  (`6101`, `6102`), and **Memory Usage** (`6002`, `6003`) categories --
  cumulative since restart, uncontrollable
- The default-trace findings (`5001` slow auto-grow, `5002` auto-shrink events,
  `5003` disruptive DBCC) -- these read events that already happened, and
  `5000` / `5004` fire only when the trace cannot be read at all

**Environment / OS state (would require an OS privilege change and a service
restart, which CI cannot do):**

- Lock Pages in Memory Not Enabled (`4105`)
- Instant File Initialization Disabled (`4106`)

**Deliberately-not-touched because forcing them is disruptive, dangerous, or
requires a restart:**

- TempDB Configuration checks (`2001`-`2006`, `2010`) -- changing tempdb's file
  layout needs a restart to take effect and destabilizes a shared instance
- Configuration Pending Reconfigure (`1007`) -- forcing it means deliberately
  leaving a `RECONFIGURE`-pending dirty state on the box, which is exactly the
  state the harness flushes before it starts
- Notable Global Trace Flag (`1012`) -- setting a global trace flag with
  `DBCC TRACEON (..., -1)` changes behavior for every session on the instance
- `max server memory` (`1002`), affinity masks (`1008`-`1011`), `max degree of
  parallelism` (`1003`), and priority boost (`1005`) -- dangerous,
  destabilizing, or something a real workload may depend on

**Additional database-level checks that ARE forceable but are not asserted
(representative coverage only):** Auto-Close Enabled (`7002`), Restricted Access
Mode (`7003`), Query Store Not Enabled (`7006`), Delayed Durability (`7008`),
Accelerated Database Recovery with SI/RCSI (`7009`), Ledger (`7010`), Query Store
health (`7011`, `7012`), non-default database scoped configurations (`7020`), and
the file auto-growth checks (`7101`-`7104`) could each be forced on a scratch
database. The harness asserts a representative pair (Auto-Shrink, Auto Update
Statistics) to exercise the per-database cursor path and the `database_name`
scoping without turning the suite into an exhaustive per-setting matrix. See the
Auto-Close note below for why that specific one was dropped.

### A real fragility this harness surfaced, now fixed and asserted

The database-scoped group was originally written to force **AUTO_CLOSE** as its
second toggle, and it uncovered a crash: a closed (`AUTO_CLOSE`) or `OFFLINE`
database returns `NULL` for `is_accelerated_database_recovery_on` in
`sys.databases` -- ADR state lives with the database, not master metadata, so it
cannot be read while the database is shut -- and that column was `NOT NULL` in the
procedure's `#databases` table, so the collection `INSERT` rejected the `NULL`
with `Msg 515` and aborted the whole run. Because the collection has no state
filter, a single inaccessible database could take down a full-instance run. It
showed up on SQL Server 2025 first, but the mechanism is version-independent.

The column is now nullable, and the `Inaccessible` group asserts the fix stays in:
it closes and then offlines a scratch database and confirms scoped runs and a
whole-instance run all complete without `Msg 515`. The database-scoped toggle
group uses `AUTO_UPDATE_STATISTICS` instead of `AUTO_CLOSE` for a separate reason
-- it keeps the database open, so the finding it forces is actually assessable.

## Running in CI

This suite runs in GitHub Actions as part of `.github/workflows/sql-tests.yml`,
against SQL Server **2017, 2019, 2022, and 2025** containers. It reconfigures the
instance and restores it, which is acceptable against a throwaway per-job
container but is still a "run it on a box you control" tool by nature -- it always
restores every option it touches and drops every database it creates, but do not
point it at a shared instance somebody else depends on.

CI overrides two environment variables the harness reads: `SQLCMD_BIN` (the path
to the container's `sqlcmd`) and `SQLCMD_CONN_ARGS`, set to `-C -N disable` so the
modern Go TLS stack does not reject the SQL Server 2017 container's self-signed
certificate outright. Locally both default to plain `sqlcmd` on `PATH` with no
extra connection arguments.
