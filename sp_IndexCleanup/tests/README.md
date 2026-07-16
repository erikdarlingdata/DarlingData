# sp_IndexCleanup Tests

Two kinds of thing live here: an automated suite that asserts, and fixture
scripts that set up realistic scenarios for you to inspect by hand.

**Run the automated suite before and after any change to `sp_IndexCleanup.sql`.**
Compiling proves nothing about behavior. The procedure's whole output is
generated DDL, and a script that looks right but cannot execute is worse than no
script at all -- the paired `DISABLE` still runs.

## Automated

| Script | What it does |
| --- | --- |
| `run_tests.py` | Runs `adversarial_test.sql`, parses the output, asserts 28 expectations across 12 rule groups. |
| `adversarial_test.sql` | Builds synthetic `test_ic_*` tables covering unique constraints, sort directions, filters, include merges, indexed views, heaps, and rule interactions. Self-cleaning. Driven by `run_tests.py`; run it directly only to eyeball output. |
| `fixture_cases_test.py` | Drives `fixtures_more_dupe_indexes.sql` and asserts the `Expected:` comments in it -- cases 1 through 8d -- against the real `Users` table. **Also executes every generated MERGE/DISABLE script** inside a rolled-back transaction. ~2 minutes. |
| `rule_coverage_test.py` | Small synthetic fixture in `Crap`. Covers unused-index detection (or the uptime guard, see below) and the `@min_reads`/`@min_writes` index-level screen. Fast. |
| `no_access_test.py` | Creates a login with no user-database access and asserts the `HAS_DBACCESS` preflight returns instead of spinning at 100% CPU forever (PerformanceMonitor #915). Drops the login afterward. |

```
cd sp_IndexCleanup/tests
python run_tests.py --server SQL2022
python fixture_cases_test.py --server SQL2022
python rule_coverage_test.py --server SQL2022
python no_access_test.py --server SQL2022
```

All take `--server` and `--password` (default `SQL2022` / the standard local sa
password). Expect `28`, `31`, `11`, and `4` passed.

### The execute check is the one that earns its keep

`fixture_cases_test.py` runs every generated script for real, each in its own
`BEGIN TRANSACTION ... ROLLBACK`. That is not belt-and-braces -- it is the check
that catches this procedure's characteristic bug.

Every defect found in it so far has had the same shape: **a merge script that
cannot execute, paired with a `DISABLE` that can**, so the loser's covering
column disappears with nothing absorbing it. Compiling does not catch it. Reading
the output does not catch it. Only running the script does.

Pointed at the build from before those fixes, this suite goes red on exactly
those bugs, including `Msg 1907 - Cannot recreate index ... does not match the
constraint being enforced by the existing index` surfacing purely from the
execute check. `SET PARSEONLY ON` would sail straight past it: 1907 is a semantic
error, not a syntax one.

### Uptime guard: unused-index detection cannot run on a fresh instance

`sp_IndexCleanup` auto-enables `@dedupe_only` when server uptime is <= 7 days,
which skips Rule 1 entirely. That is deliberate -- usage stats are meaningless on
a just-restarted server -- and it is not overridable by parameter.

The practical consequence: **on a freshly restarted instance, unused-index
detection will look broken when it is not.** Run with `@debug = 1` and you will
see the procedure say so: `Server uptime is less than 7 days. Automatically
enabling @dedupe_only mode.` Check that before concluding Rule 1 is broken.

`rule_coverage_test.py` handles this by asserting whichever is true: on a
long-uptime instance it asserts Rule 1 flags the unused index; on a fresh one it
asserts the guard fired and suppressed it. It never silently skips, and it proves
the index was analyzed and genuinely has zero reads first, so the absence of an
`Unused Index` row means the guard, not an invisible index.

These are **not** wired into CI. `.github/workflows/sql-tests.yml` only runs
basic-execution and help-output smoke tests, which is why behavioral regressions
have shipped before. Run these by hand.

## Fixtures (manual)

These build indexes on the real `StackOverflow2013.dbo.Users` table (~2.4M rows),
so unlike the synthetic suite they exercise real data distribution and sizes.

| Script | What it does |
| --- | --- |
| `fixtures_dupe_indexes.sql` | ~24 indexes covering duplicates, subsets, sort directions, filters, mergeable includes, and deliberately unused indexes. |
| `generate_index_reads.sql` | Drives ~100 reads through each of the above so usage stats exist. ~2 minutes. |
| `fixtures_more_dupe_indexes.sql` | Numbered cases 1-8d, each annotated with its expected behavior. The only fixtures covering unique **constraints** (7a/7b/7c) next to unique **indexes** (3, 5). Self-contained: builds, generates reads, and runs the procedure. |
| `manual_test_runs.sql` | Assorted invocations -- scoping, filters, `@dedupe_only`, `@help`. |

Order for the first set:

```
fixtures_dupe_indexes.sql  ->  generate_index_reads.sql  ->  manual_test_runs.sql
```

`fixtures_more_dupe_indexes.sql` stands alone.

### Prerequisites

- A **scratch** `StackOverflow2013`. Both fixture scripts begin with
  `EXECUTE dbo.DropIndexes`, which drops every nonclustered index in the
  database. Do not point them at anything you care about.
- A `dbo.DropIndexes` helper procedure in that database.
- `fixtures_more_dupe_indexes.sql` adds three unique constraints
  (`uq_test_c1`/`c2`/`c3`). `DropIndexes` does not remove constraints -- drop
  them explicitly with `ALTER TABLE dbo.Users DROP CONSTRAINT ...` when
  cleaning up.

### The `Expected:` comments are the specification

They are not decoration. Two of them caught bugs that shipped, that compiled
cleanly, and that the automated suite did not cover:

- **Case 7c** -- the procedure emitted a merge into a unique *constraint*:
  `CREATE INDEX ... WITH (DROP_EXISTING = ON)` against a constraint-backed
  index, which SQL Server refuses with **Msg 1907**. The paired `DISABLE` of
  `ix_c3` ran fine, so the net effect was losing an index whose include nothing
  absorbed.
- **Case 3** -- `ix_test_5` was disabled with `uq_test_1` as its target, but
  nothing merged `ix_test_5`'s include into it, so `LastAccessDate` coverage
  vanished. A plain unique *index* does accept `DROP_EXISTING` with an added
  `INCLUDE` (unlike a constraint), so the merge is legal and now happens.

Both were found by diffing output against these comments by hand. They are now
asserted automatically by `fixture_cases_test.py`, so a regression against either
fails a test rather than waiting to be noticed.

## Verifying a change

The technique that catches regressions is a **baseline diff**: identical
database state, two builds, compare output.

```
git show <base>:sp_IndexCleanup/sp_IndexCleanup.sql > /tmp/base.sql
```

Build fixtures once, generate reads once, then install each build in turn and
capture output. Normalize the `run date:` stamp before diffing, and compare rows
as a set -- a removed row shifts every line after it and makes a positional diff
useless.

Then ask of every difference: intended, or a regression? A change with no
explanation is the finding.

Finally, for anything that alters generated DDL: **execute the generated script**
against the fixture and confirm the result. That is the check that distinguishes
a script that reads correctly from one that runs.
