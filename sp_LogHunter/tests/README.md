# sp_LogHunter Tests

**Run before and after any change to `sp_LogHunter.sql`.** Compiling proves
almost nothing here. sp_LogHunter is a *generator*: it never queries the error
log directly, it builds an `EXECUTE master.dbo.xp_readerrorlog ...` command
string in the PERSISTED computed column `#search.command` -- one per search
string -- and runs each through `sys.sp_executesql` in a nested loop over every
log archive. A command that concatenates cleanly and reads correctly can still
fail the moment it executes.

Worse, that failure is **silent by design**. The EXECUTE is wrapped in
`BEGIN TRY`/`BEGIN CATCH`, and any command that throws is swallowed into
`#errors` rather than raised. A broken search string therefore produces a
clean-looking but quietly incomplete result set: the procedure reports a
healthy server because it never managed to read the log.

## Automated

| Script | What it does |
| --- | --- |
| `run_tests.py` | Runs the parameter matrix, asserting `#errors` stays empty, plus bidirectional marker and date-range checks. 78 assertions. |

```
cd sp_LogHunter/tests
python run_tests.py --server SQL2022
```

Takes `--server` and `--password` (default `SQL2022` / the standard local sa
password). Expect `78`. A full run takes a few seconds.

## What it actually covers

**`#errors` must be empty.** This is the core assertion and it runs on every
case in the matrix. The source documents four bugs already fixed this way -- a
stray literal space silently ANDed into every search, a NULL date argument in
date-range mode, an unescaped quote closing the argument early, and an absurd
`@days_back` overflowing `DATEADD`. Every one of them landed in `#errors`
instead of on the user's screen, so asserting that table is empty
regression-tests all four at once and anything else of the same shape.

**A real positive control.** `RAISERROR('<marker>', 10, 1) WITH LOG` writes a
known string to the error log. Severity 10 is deliberate: it reaches the log
without emitting a client-side `Msg ..., Level 12+` that the error detector
would flag. The marker is chosen so none of the ~88 canned search strings match
it and none of the noise filters delete it, which makes the pair meaningful:

- `@custom_message` = the marker -> the row **is** returned
- `@custom_message` = a string never written -> **not** returned, run still clean
- a default run with no `@custom_message` -> **not** returned

The same shape covers date ranges (a window containing the write returns it, a
window 30 days earlier does not) and `@custom_message_only` (0 runs the canned
sweep *and* the custom search; 1 returns strictly fewer rows). Every absence
assertion is paired with a presence assertion on the same machinery, so nothing
passes vacuously by returning an empty set.

## Bug found and fixed by this harness

A `@custom_message` longer than **128 characters** silently returned nothing.

Search arguments were wrapped in double quotes, and under `QUOTED_IDENTIFIER ON`
a double-quoted argument parses as an **identifier** -- which SQL Server caps at
128 characters. Anything longer failed with `Msg 103 ... The identifier that
starts with ... is too long`, was swallowed into `#errors`, and handed the
caller an empty result set that reads exactly like a clean bill of health. A
150-character search string is not exotic; pasting in an error message fragment
gets you there easily.

The fix emits `N'...'` instead. Both halves matter, and the second one is why
the original code used double quotes in the first place: `xp_readerrorlog` is an
extended stored procedure and does **not** implicitly convert, so a bare
single-quoted (varchar) argument fails with `Msg 22004 ... Invalid Parameter
Type` at severity 12 -- quiet enough to look like simply finding nothing. Quoted
identifiers happened to satisfy the Unicode requirement; `N'...'` satisfies it
deliberately, and has no length limit.

Because that failure is severity **12**, this harness checks for `Level 12` and
above rather than the `Level 16` its siblings use. Severity 11 is still
excluded: sp_LogHunter's own parameter guards raise at 11 by design.

## Side effect

This harness writes a handful of informational lines to the SQL Server error
log (the markers). That cannot be undone without cycling the log, which would be
far more disruptive than the lines themselves, so it does not try. The marker
text is fixed rather than random so repeated runs do not accumulate distinct
junk. Nothing else on the instance is touched: no databases, no configuration,
no sessions, no server settings.
