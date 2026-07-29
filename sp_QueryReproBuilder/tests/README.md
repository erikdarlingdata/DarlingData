# sp_QueryReproBuilder Tests

`sp_QueryReproBuilder` reads a query plan and emits a **runnable** reproduction
script -- the T-SQL in `#repro_queries.executable_query`, surfaced in the primary
result set keyed `table_name = 'results'`. The generated repro is the whole
product. Compiling the procedure proves nothing about it; a repro that reads
correctly but will not run is worse than useless, because someone will paste it
into a window expecting it to work.

So the suite here does not stop at "a repro came back." It feeds a plan in,
pulls the emitted repro out, and **actually executes it**, because many of the
ways this generator can go wrong are semantic, not syntactic, and only surface
when the script runs.

**Run the suite before and after any change to `sp_QueryReproBuilder.sql`.**

```
cd sp_QueryReproBuilder/tests
python run_tests.py --server SQL2022
python mutation_check.py --server SQL2022
```

Both take `--server` and `--password` (default `SQL2022` / the standard local sa
password). Expect `237 passed, 0 failed` and `5 of 5 mutations caught`.

## What is here

| File | What it does |
| --- | --- |
| `run_tests.py` | 44 cases, 237 assertions. Each embeds a ShowPlanXML, drives it through `@query_plan_xml`, extracts the emitted repro, executes it, and asserts it built, is correct, and RAN. Self-contained and self-cleaning. |
| `mutation_check.py` | Plants five plausible generation bugs in a scratch copy of the procedure, installs each, and asserts `run_tests.py` goes RED on every one -- proof the suite has teeth. Restores the real build afterward. |
| `template_generate.sql` | The generation half: runs the procedure in `@query_plan_xml` mode and lets its result set print so the repro can be read off stdout. Driven by `run_tests.py`. |
| `template_execute.sql` | The execution half: takes the repro back (as base64) into a real `nvarchar(max)` variable and runs it with `sys.sp_executesql` inside `BEGIN TRANSACTION ... ROLLBACK` and `TRY/CATCH`. Driven by `run_tests.py`. |

Everything is embedded or synthesized. There is no dependency on a captured plan
cache, on `StackOverflow2013`, or on any particular user database. Plans
reference `sys` objects, which are always present; the single case that needs a
real user table (a parameterized `UPDATE`) uses a small fixture the harness
creates in `tempdb` and drops on the way out.

## The execute check is the one that earns its keep

Every generated repro is run for real, each in its own rolled-back transaction,
via `sys.sp_executesql` on the repro held in a variable. Three things about that
are deliberate:

- **It runs, it does not just parse.** `SET PARSEONLY ON` would sail past a repro
  that parses but cannot bind -- a parameter declared with the wrong type, a
  value that will not convert. Those are the characteristic bugs of a generator
  like this, and only running the script catches them.
- **The repro lives in a variable, executed with `sp_executesql`.** That defers
  its compile, so a broken repro (say, an unbalanced quote from a botched
  apostrophe-doubling change) is a *catchable* error reported as
  `EXEC_RESULT: FAIL`, not a batch-killing parse error that takes the harness
  down with it. Pasting the repro verbatim into a batch would misclassify that
  same bug as an uncatchable syntax error of a different severity.
- **The hand-off is base64.** `run_tests.py` passes the repro back as base64 of
  its utf-16-le bytes, so there is no quote-escaping to get wrong and no
  8000-character string-literal limit to trip over on the long-repro cases.

The generation half deliberately does **not** use `INSERT ... EXECUTE`.
`sp_QueryReproBuilder` returns different result-set shapes -- the wide `results`
set when a repro is built versus the single-column `#repro_queries is empty`
diagnostic when nothing lands -- and a fixed-shape `INSERT ... EXECUTE` target
cannot absorb both. The repro is read off stdout instead, from the
`executable_query` processing instruction that renders as `<?_ ... ?>`.

## Coverage

The battery carries over the assertions that matter and holds each generated
repro to both "is it correct?" and "does it run?":

- **Parameterized plans** -- explicit `sp_executesql`-style parameters, and the
  many-parameter (`@1..@12`, 399-parameter) cases.
- **No-parameter plans.**
- **Scaled / precision types**, each with the *authentic* `ParameterCompiledValue`
  serialization captured from real sniffed plans: `numeric(38,2)` as `(12.50)`,
  `decimal(38,10)`, `money` as `($99.9500)`, `float`/`real` in scientific
  notation, `varchar(8000)`, `nvarchar(max)`, `datetime2(7)`,
  `datetimeoffset(7)` (note the ` +05:30` with its leading space), `datetime`,
  `date`, `time(7)`, `uniqueidentifier` as `{guid'...'}`, `varbinary(8)`, `bit`,
  `bigint`.
- **Entity characters** (`&` `<` `>` `'`) in statement text and in a parameter's
  compiled value.
- **Apostrophes** in both a parameterized statement (must be re-doubled inside
  the outer `N'...'`) and a raw statement.
- **Unicode / N-literals** (round-tripped through the repro, not just declared).
- **Long statement text** both `> 4000` and `> 8000` characters, plus a long
  parameterized statement `> 8000`.
- **Parameter/value alignment** -- declaration order versus ParameterList order,
  asserting value *i* binds to declaration *i*.
- **Control characters** (CR, LF) embedded in a parameter's sniffed value.
- **Echo cases** that execute the repro and read back the *actually-bound*
  values, catching a silent reorder or misbind that still runs.

### The documented `?` fill-in behavior

When a parameter is declared in the query text but is **absent from the plan's
ParameterList**, the procedure cannot know its value. It does the safe thing: it
sets the value to `?` and emits a warning ("... were not found in the plan
ParameterList ..."). The repro then fails **loud** (`Msg 102` near `?`) if run
as-is, rather than silently executing with a wrong value.

The suite asserts exactly that contract: the warning fires, the `?` placeholder
is present, and execution does **not** silently pass. This is the intended
behavior, not a bug -- you are meant to fill in the value before running. The
`mutation_check.py` `M6` mutation (making that path emit `NULL` instead of `?`)
proves the assertion has teeth: it would let the repro run silently with a wrong
value, and the suite catches it.

The same safe degradation covers the **first-ParameterList-wins** hazard: when a
decoy `ParameterList` (as XML-reader / UDF operators emit) precedes the query's
own, the procedure's substring extraction grabs the decoy, the real parameter is
lost, and the case falls back to the warned `?` path -- loud failure, not a
silent wrong result. That is asserted (`decoy:decoy_first_degrades_loud`) rather
than papered over.

## mutation_check.py -- proving the teeth

A green suite is only worth trusting if it goes red when the generator breaks.
`mutation_check.py` plants five bugs, one at a time, in a scratch copy of the
procedure (it **never** edits the repo file), installs each mutant, runs
`run_tests.py`, and asserts it goes red:

| Mutation | Broken behavior | Caught by |
| --- | --- | --- |
| `M1` | value list re-sorted independently of the declaration list | echo cases (wrong bound values / bind error) |
| `M2` | every parameter's declared type forced to `int` | type round-trip assertions **and** execution (numeric/date/binary values will not bind to `int`) |
| `M3` | fill-in path splits scaled types like `numeric(10,2)` on the internal comma | the `?` scaled-fill-in case (`numeric(10,2)` no longer intact in the declaration) |
| `M4` | statement-apostrophe doubling removed | execution (broken outer `N'...'` literal) |
| `M6` | `?` fill-in emitted as `NULL` | the `?`-path assertions (silent run instead of loud fail) |

`M4` and `M1` are caught **only** because the repros are executed -- there is no
static check that would notice them -- which is the whole argument for the
execute check. After the run, `mutation_check.py` restores the real build from
`sp_QueryReproBuilder.sql` and leaves it installed. Run `--dry` to verify the
mutation patterns still anchor to the current procedure (each must match exactly
once) after editing it.

## Not wired into CI

Like the `sp_IndexCleanup` suite, these run by hand against a live instance.
They install the procedure and execute generated SQL, so they need a real SQL
Server, not a syntax check. Run them yourself before shipping a change to
`sp_QueryReproBuilder.sql`.
