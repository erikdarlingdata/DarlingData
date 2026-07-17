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
| `run_tests.py` | Drives `dbo.sp_PerfCheck` over `sqlcmd`, parses the two result sets, and asserts **48** expectations across three groups: 11 structural/smoke, 26 forced server-configuration, 11 forced database-configuration. Self-cleaning and idempotent. |

```
cd sp_PerfCheck/tests
python run_tests.py --server SQL2022
```

`--server` and `--password` default to `SQL2022` / the standard local `sa`
password. Expect `48 passed, 0 failed`. The proc must be installed in `master`
on the target instance (there is a preflight that fails fast if it is not).

The suite has been run green on SQL Server 2016, 2017, 2019, 2022, and 2025.

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

**2. Forced server-configuration (26).** The "Non-Default Configuration" check
(`check_id 1000`) reads `sys.configurations`. For three options that are **safe
to flip on a test instance** the harness proves the finding **bidirectionally**:

| Option | Default | Forced to | Proven |
| --- | --- | --- | --- |
| `cost threshold for parallelism` | 5 | 55 | absent at 5, present at 55 |
| `optimize for ad hoc workloads` | 0 | 1 | absent at 0, present at 1 |
| `access check cache bucket count` | 0 | 256 | absent at 0, present at 256 |

For each option the harness asserts the finding is absent at the default value,
present when forced (with `check_id 1000`, `priority 50`,
`category = Server Configuration`, and the option name plus forced value in
`details`), and that no severe error occurred. Each **absence** assertion is
paired with a **positive control** -- `#server_info` is populated on the same run
-- so an empty or failed result set cannot pass vacuously; the matching presence
assertion is the proof that the check itself actually runs.

These three options were chosen because none require a restart, none are
dangerous (no `max server memory`, no affinity, no MAXDOP), and nothing the CI
depends on reads them. Each option's **original `value_in_use` is captured first
and restored precisely** in a `finally` block that runs even on assertion
failure, and the harness dumps the entire `sys.configurations` table before and
after and asserts **zero net change**. The suite is idempotent: run it twice,
same result, no leaked config.

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

- Offline CPU Schedulers (`check_id 935`)
- Memory-Starved Queries Detected (`967`, `994`) -- depends on live resource
  semaphore waits
- Memory Dumps Detected In Last 90 Days (`1029`) -- depends on dump history
- High Number of Deadlocks (`1106`) -- depends on the deadlock counter
- Large Security Token Cache (`1172`)
- Slow Read Latency / Slow Write Latency (`2834`, `2877`) -- from
  `sys.dm_io_virtual_file_stats`; latency cannot be dialed to a threshold on
  demand
- Everything in the **Wait Statistics** and **Memory Usage** categories --
  cumulative since restart, uncontrollable

**Environment / OS state (would require an OS privilege change and a service
restart, which CI cannot do):**

- Lock Pages in Memory Not Enabled (`1220`)
- Instant File Initialization Disabled (`1279`)

**Deliberately-not-touched because forcing them is disruptive, dangerous, or
requires a restart:**

- TempDB Configuration checks (file count / size / growth parity) -- changing
  tempdb's file layout needs a restart to take effect and destabilizes a shared
  instance
- Configuration Pending Reconfigure (`3826`) -- forcing it means deliberately
  leaving a `RECONFIGURE`-pending dirty state on the box
- Resource Governor Enabled (`1322`) -- toggling Resource Governor affects
  workload classification for every session on the instance
- `max server memory`, affinity masks, `max degree of parallelism`, priority
  boost, query governor cost limit -- excluded from the forced-config set even
  though check `1000` reads them, because they are dangerous, destabilizing, or
  something a real workload may depend on

**Additional database-level checks that ARE forceable but are not asserted
(representative coverage only):** Auto-Close Enabled (`7002`), Query Store Not
Enabled (`7005` region), ANSI Settings Require Review, Non-Default Target
Recovery Time, Delayed Durability, Accelerated Database Recovery / RCSI, Ledger,
and the file auto-growth checks (`7101`-`7104`) could each be forced on a scratch
database. The harness asserts a representative pair (Auto-Shrink, Auto Update
Statistics) to exercise the per-database cursor path and the `database_name`
scoping without turning the suite into an exhaustive per-setting matrix. See the
Auto-Close note below for why that specific one was dropped.

### A real fragility this harness surfaced: AUTO_CLOSE on SQL Server 2025

The database-scoped group was originally written to force **AUTO_CLOSE** as its
second toggle. On **SQL Server 2025**, forcing `AUTO_CLOSE ON` and then scoping
`sp_PerfCheck` to that (now closed) database makes `sys.databases` return `NULL`
for `collation_name`, `target_recovery_time_in_seconds`, and
`delayed_durability_desc`, which the procedure's `#databases` insert rejects with
`Msg 515` (`Cannot insert the value NULL`). The database is never analyzed and
the run aborts. On 2016-2022 the same test passed, so this is a genuine,
version-dependent fragility in `sp_PerfCheck` itself, not a test artifact.

Rather than assert around a procedure error (which would make the suite flake by
version) or edit the procedure, the harness **switched its second toggle to
AUTO_UPDATE_STATISTICS**, which keeps the database open and behaves identically
on every version. The AUTO_CLOSE behavior is documented here so it is not lost.

## Not wired into CI

Like the other DarlingData behavioral suites, this is **not** part of any GitHub
Actions workflow -- it reconfigures a live instance (and briefly restores it),
which is not something to run against shared CI infrastructure. Run it by hand
against a test instance you own. It always restores every option it touches and
drops every object it creates, but it is still a "run it on a box you control"
tool by nature.
