<img src="https://erikdarling.com/wp-content/uploads/2025/08/darling-data-logo_RGB.jpg" width="300px" />

# ProtectSession

A watchdog that keeps a specific session alive when it's blocked on lock waits. Run it from a *separate* connection, point it at the session you care about, and it cycles every `@check_interval_seconds` deciding what to do.

The rule it follows is straightforward: if your session is blocked on an `LCK_M_*` wait for at least `@block_threshold_seconds`, look at what's holding the lock. If killing the blocker is cheap (a read, or a temp-table modification), kill it. If killing it would roll back permanent data changes, leave it alone -- or, if you've set `@abort_on_modification_block = 1`, kill your own session instead. You can also flip `@kill_modification_blockers = 1` to be more aggressive.

It is **not** a general-purpose blocking killer; it watches exactly one session you've designated.

## Parameters

| parameter_name                  | data_type     | description                                                                              | valid_inputs                | defaults             |
|---------------------------------|---------------|------------------------------------------------------------------------------------------|-----------------------------|----------------------|
| @protected_session_id           | integer       | the session_id you want kept alive (watched, not run from)                               | a session_id of another spid | NULL (required)      |
| @block_threshold_seconds        | integer       | how long the protected session must wait on an LCK before any action                     | a positive integer           | 5                    |
| @check_interval_seconds         | integer       | how often each cycle samples and acts                                                    | a positive integer           | 1                    |
| @abort_on_modification_block    | bit           | when blocked by a permanent-data modification, kill the protected session instead of the blocker | 0 or 1                       | 0                    |
| @kill_modification_blockers     | bit           | kill permanent-data modification blockers too (rolls back their work)                    | 0 or 1                       | 0                    |
| @abort_reason                   | nvarchar(2048)| free-text reason printed when the protected session is aborted                           | any string or NULL           | NULL                 |
| @debug                          | bit           | print each cycle's `#blockers` contents                                                  | 0 or 1                       | 0                    |
| @help                           | bit           | how you got here                                                                         | 0 or 1                       | 0                    |
| @version                        | varchar(5)    | OUTPUT; for support                                                                      | none                         | none; OUTPUT         |
| @version_date                   | datetime      | OUTPUT; for support                                                                      | none                         | none; OUTPUT         |

## Examples

```sql
-- Defaults: watch session 73, kill SELECT-like blockers after a 5-second wait
EXECUTE dbo.ProtectSession
    @protected_session_id = 73;

-- More patient (wait 30 s) and quieter polling (every 5 s)
EXECUTE dbo.ProtectSession
    @protected_session_id = 73,
    @block_threshold_seconds = 30,
    @check_interval_seconds = 5;

-- Be aggressive: kill permanent-data modification blockers too
EXECUTE dbo.ProtectSession
    @protected_session_id = 73,
    @kill_modification_blockers = 1;

-- The opposite: if a permanent modification is blocking us, kill OURSELF
-- (e.g. when the protected session is a reporting query that should yield)
EXECUTE dbo.ProtectSession
    @protected_session_id = 73,
    @abort_on_modification_block = 1,
    @abort_reason = N'reporting query yielding to nightly ETL';

-- Watch a cycle's classification without acting on anything
EXECUTE dbo.ProtectSession
    @protected_session_id = 73,
    @debug = 1;
```

## How a blocker gets classified

For each cycle, the proc snapshots the protected session's `LCK_M_*` wait into a `#blockers` table and decides whether the immediate blocker is a *permanent-data modification* by inspecting `sys.dm_tran_locks` -- **not** by looking at the blocker's current command.

A blocker is classified `is_modification = 1` when it holds a modification or schema-change lock (`X` / `IX` / `U` / `SIX` / `BU` / `Sch-M`) on an `OBJECT` resource in a database other than tempdb (`resource_database_id <> 2`). The decision is held-lock-based for two reasons that the obvious "look at `command`" approach gets wrong:

1. A blocker can be currently running a `SELECT` while still holding `X` locks from an `UPDATE` earlier in the same open transaction. The current command says `SELECT`; the actual modification footprint is `IX` on a user-database object.
2. `SELECT ... INTO dbo.RealTable` shows `command = 'SELECT'` but is a real modification of permanent data.

So:

| Blocker shape                                                                  | `is_modification` | Default action                |
|--------------------------------------------------------------------------------|-------------------|-------------------------------|
| Plain `SELECT` (`IS` / `S` / `RangeS-S` only)                                  | 0                 | killed past threshold         |
| `INSERT` / `UPDATE` / `DELETE` / `MERGE` / `TRUNCATE` against `#temp` only     | 0                 | killed past threshold         |
| `INSERT` / `UPDATE` / `DELETE` / `MERGE` / `TRUNCATE` / DDL on a permanent obj | 1                 | left alone (override with flags) |
| Sleeping blocker that earlier modified a permanent object (still holds `X`)    | 1                 | left alone (override with flags) |
| `SELECT WITH (UPDLOCK)` (holds `IX` on a permanent object)                     | 1                 | left alone (conservative)     |

A blocker holding *only* tempdb locks (`#temp`, `##temp`, table variables, work tables) is treated like a `SELECT` blocker: killing it rolls back nothing durable.

## Chain diagnostics

The proc walks the blocking chain upstream from the immediate blocker and records `chain_depth` plus the lead blocker session id. **This is diagnostic only.** The `KILL` target is always the *immediate* blocker -- that is the session holding the lock the protected session is actually waiting on, and the only kill that directly frees the protected session. Killing further up the chain would just wake the immediate blocker; its locks would still be held until it committed.

The chain info shows up in `@debug` output and in every kill / abort message. Example output for a 5-deep chain:

```
ProtectSession: killing session 66 (UPDATE blocker of session 67;
protected session has been waiting 81357 ms on KEY in [Crap];
immediate blocker in a chain of depth 5, lead blocker is session 52).
```

## Contended resource naming

The proc looks at `sys.dm_tran_locks` for the protected session's `WAIT`-status row and reports:

- `contended_db_name` (always, when there is a wait row)
- `contended_resource_type` (`OBJECT` / `KEY` / `RID` / `PAGE` / `HOBT` / etc.)
- `contended_object_name` (only for `OBJECT`-type contention, via `OBJECT_NAME(...)`)

For row-level locks the object name isn't directly available without crossing into the contended database; the resource type and database name are still reported.

## Spid-reuse defense

SQL Server recycles freed `session_id`s aggressively -- a connection that closes can have its spid handed to a brand-new connection within microseconds. Without protection, that creates a narrow but real race: ProtectSession could snapshot blocker N, N could die, a new unrelated session could acquire spid N, and the proc would `KILL N` against the innocent new session.

The proc defends against this by capturing `login_time` along with `session_id` -- once at proc start for the protected session, and per blocker in the snapshot. Immediately before any `KILL`, it re-verifies `(session_id, login_time)` matches. On mismatch the kill is skipped and a `skipping KILL of session N -- login_time changed since snapshot` message is logged instead.

## Permissions

* `VIEW SERVER STATE` -- to read `sys.dm_exec_sessions`, `sys.dm_exec_requests`, `sys.dm_tran_locks`, `sys.dm_exec_sql_text`.
* `ALTER ANY CONNECTION` (or `sysadmin`) -- to run `KILL`. Without this the proc still cycles and classifies correctly; the `KILL` attempts simply fail and are caught.

The proc degrades gracefully without `KILL` permission -- it just logs the failures.

## Notes

* Run from a *separate* connection from the one you're protecting. The proc raises an error if you try to point it at its own `@@SPID`.
* `SET XACT_ABORT ON` is **deliberately omitted**. The proc is a long-running watchdog; transient errors from a session dying between sample and kill, or brief DMV unavailability, are meant to be caught by the inner `BEGIN CATCH` and ignored so the next cycle can recover. `XACT_ABORT ON` would terminate the loop on the first such hiccup.
* The proc loops until the protected session ends (commit, disconnect, or external kill). When it does, the outer `WHILE EXISTS` falls through and the proc returns.
* `@check_interval_seconds = 1` is fine on idle systems but the per-cycle `dm_tran_locks` scan grows with lock-manager population; on very busy servers consider raising it.

Copyright 2026 Darling Data, LLC
Released under MIT license
