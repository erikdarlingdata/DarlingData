"""
sp_IndexCleanup Rule Coverage Tests
===================================
Covers things nothing else in this directory tests: Rule 1 (unused index
detection), the @min_reads / @min_writes index-level screen, and four ways the
procedure can emit a script that is wrong.

The ranking that decides what is worth asserting here: this procedure emits DDL
that people run against production. A script that ERRORS is nearly harmless --
it stops, and nobody's data moves. A script that SUCCEEDS while being wrong is
the real hazard, because there is nothing to notice. Groups C, D, E and F all
target that class, so they assert on the script text the procedure produces
rather than on whether some execution raised an error.

Every absence assertion below is paired with a positive control. "No DISABLE
script named the PK" is trivially true if the PK was never analyzed, so each
group first proves the index was in play.

Builds its own synthetic fixture in the Crap database -- three ~20,000 row tables,
scoped with @table_name so each procedure run is fast. It deliberately does not
touch StackOverflow2013: fixture_cases_test.py already spends two minutes there,
and this one is meant to be quick. Drops its tables afterward.

Group F additionally builds two throwaway databases, because the defect it
covers only exists across the database loop and cannot be reproduced inside a
single database. They are dropped unconditionally afterward, including when an
assertion fails or the fixture itself does not build.

(a) Rule 1, unused index detection.

    The procedure auto-enables @dedupe_only when server uptime is <= 7 days, and
    Rule 1 only runs when @dedupe_only = 0. So on a recently restarted instance
    Rule 1 cannot be reached through the public interface at all. That is correct,
    deliberate behavior: usage data on a freshly started instance is worthless,
    and recommending index drops from it would be actively harmful.

    Rather than skip, this asserts whichever statement is true on the instance in
    front of it:

      - uptime > 7 days:  the never-read index gets a DISABLE with a consolidation
                          rule of 'Unused Index'.
      - uptime <= 7 days: the GUARD holds. @dedupe_only was auto-enabled (proven
                          by the procedure's own @debug message) and no 'Unused
                          Index' rows appear anywhere.

    The guard branch is a real assertion, not a silent pass. It is kept honest by
    positive controls: the harness first proves the index was analyzed (it appears
    in the output) and that it genuinely has zero reads, so the absence of an
    'Unused Index' row is the guard doing its job rather than the index being
    invisible for some unrelated reason.

(b) The @min_reads / @min_writes index-level screen.

    The screen gates DEDUPE ONLY. It must not take compression recommendations
    with it -- an index can be far too cold to bother deduping and still be worth
    compressing. It is also an OR: an index clears by meeting EITHER floor.

    The write-floor cases run against a table whose clustered PK carries reads
    (an UPDATE seeks it) while ix_w1/ix_w2 have none. The table therefore clears
    the object-level filter on its own, which means these cases exercise the
    index-level screen specifically rather than the coarser per-table filter.

(c) Nonclustered PRIMARY KEYs are constraint-backed.

    is_primary_key is not is_unique_constraint: the latter is 0 for a primary
    key, so a rule that guards only on is_unique_constraint leaves PKs exposed.
    A nonclustered PK is type = 2, which is also why it used to look like an
    ordinary unique index to the dedupe rules.

    Two proven consequences, both fixed:
      - a key duplicate earned the PK a MERGE (CREATE UNIQUE INDEX ...
        DROP_EXISTING against a constraint -> Msg 1907) while the paired DISABLE
        of the other index succeeded, silently dropping a covering column.
      - an exact duplicate with tied priorities put the PK on the losing side of
        an alphabetical tiebreak and emitted ALTER INDEX [pk...] DISABLE. That
        one does not error. It succeeds, disables every inbound foreign key, and
        orphan rows insert cleanly afterward.

    The compression positive controls are the other half: the fix must not work
    by making primary keys invisible.

(d) Sort direction is part of an index's identity.

    Rule 2 and Rule 3 each carry an explicit is_descending_key comparison.
    Rule 5 carries none -- the ' DESC' embedded into key_columns is the only
    thing keeping (col_a, col_b) and (col_a, col_b DESC) from hashing alike.
    Without it they become a false Key Duplicate whose DISABLE runs cleanly.

(e) A merged index may not INCLUDE its own key column.

    Rule 6 merges a subset's includes into the superset absorbing it. If the
    subset's include is already a key of the superset, the emitted CREATE INDEX
    lists the column twice (Msg 1909) while the subset's DISABLE still runs.

(f) #index_details is per-database. #index_analysis is not.

    Under @get_all_databases the procedure TRUNCATES #index_details for each
    database in the loop, while #index_analysis ACCUMULATES across all of them
    to build the final output. Every rule therefore re-runs over rows belonging
    to databases that were already processed.

    Rules 2/3/5/7 survive that because of their shape: each requires
    EXISTS (#index_details ... is_eligible_for_dedupe = 1), which finds nothing
    for a stale row and so fails CLOSED. Rule 7.6 carried only a
    NOT EXISTS (... is_unique_constraint = 1), and a NOT EXISTS against an
    emptied table passes VACUOUSLY. On the second database's pass it therefore
    paired the FIRST database's leftover MAKE UNIQUE winner with that database's
    primary key and marked the PK DISABLE. The script-generation backstops read
    #index_details too, so they passed vacuously in turn and this shipped:

        ALTER INDEX [pk_mdb] ON [CrapA].[dbo].[mdb_test] DISABLE;

    It executes cleanly, silently disables every inbound foreign key, and orphan
    rows then insert with no error. A NOT EXISTS fails open on a stale row where
    an EXISTS fails closed, which is the whole reason the guard has that shape.

    This is the only group that needs more than one database, so it builds two.
    The defect IS the loop, and a single-database fixture cannot express it.

    The positive controls carry more weight here than anywhere else in this file,
    because every assertion is an assertion of absence and the bug has four
    preconditions -- CrapA processed first, CrapA's table analyzed, Rule 7.5
    actually producing the MAKE UNIQUE winner, and CrapB reached so a second
    iteration happens. If any one of them silently stopped being true, every
    assertion below would go green while testing nothing at all.

Usage:
    python rule_coverage_test.py [--server SQL2022] [--password "L!nt0044"]
"""

import os
import re
import subprocess
import sys
import tempfile


TEST_DATABASE = "Crap"

# Group F's two throwaway databases. CrapA is processed FIRST and is the one
# whose leftover rows go stale during CrapB's pass, so CrapA owns the primary
# key the bug used to disable. See MDB_SETUP_SQL for why the order is by
# creation and not by name.
MDB_DATABASE_FIRST = "CrapA"
MDB_DATABASE_SECOND = "CrapB"
MDB_TABLE = "mdb_test"
MDB_PK = "pk_mdb"

# Group G reuses the very same CrapA/CrapB (CrapA processed first is exactly the
# property both groups need) but adds two of its own tables. The two defects it
# covers live in SEPARATE tables analyzed in SEPARATE @table_name scoped runs on
# purpose: with both in one table the unique-constraint rules reshuffle the merge
# dedup and the include strip stops being deterministic. See MDB_G_SETUP_SQL.
MDB_MERGE_TABLE = "icg_merge"        # superset/subset include-merge pair (bug 1)
MDB_MERGE_WINNER = "ix_merge_super"  # the Key Superset that must keep its INCLUDE
MDB_MERGE_SUBSET = "ix_merge_sub"    # the subset it absorbs and disables
MDB_UC_TABLE = "icg_uc"              # unique constraint + same-key index (bug 2)
MDB_UC_CONSTRAINT = "uq_icg"         # the constraint that must not get ALTER..DISABLE
MDB_UC_PLAIN = "ix_uc_plain"         # the index promoted to replace it

# Rows that represent a dedupe action. A COMPRESSION SCRIPT row is not one.
DEDUPE_SCRIPT_TYPES = ("DISABLE SCRIPT", "MERGE SCRIPT", "DISABLE CONSTRAINT SCRIPT")

GUARD_MESSAGE = "Automatically enabling @dedupe_only mode"

SETUP_SQL = """
SET NOCOUNT ON;

DROP TABLE IF EXISTS dbo.ic_min_reads_test;
DROP TABLE IF EXISTS dbo.ic_min_writes_test;
DROP TABLE IF EXISTS dbo.ic_unused_test;
DROP TABLE IF EXISTS dbo.ic_pk_key_test;
DROP TABLE IF EXISTS dbo.ic_pk_exact_test;
DROP TABLE IF EXISTS dbo.ic_sort_dir_test;
DROP TABLE IF EXISTS dbo.ic_key_include_test;
GO

/*
ic_min_reads_test: ix_hot (~200 reads), ix_warm (~5 reads, a key duplicate of
ix_hot with different includes so the two pair), clustered PK (0 reads).
*/
CREATE TABLE
    dbo.ic_min_reads_test
(
    id integer NOT NULL,
    col_a integer NOT NULL,
    col_b integer NOT NULL,
    col_c integer NOT NULL,
    filler varchar(100) NOT NULL,
    CONSTRAINT pk_ic_min_reads_test PRIMARY KEY CLUSTERED (id)
);

/*
ic_min_writes_test: ix_w1 / ix_w2 are a key-duplicate pair that is never read but
is written to. The clustered PK picks up reads from the UPDATE seeks, which lets
the table clear the object-level filter so the index-level screen is what gets
tested.
*/
CREATE TABLE
    dbo.ic_min_writes_test
(
    id integer NOT NULL,
    col_a integer NOT NULL,
    col_b integer NOT NULL,
    col_c integer NOT NULL,
    filler varchar(100) NOT NULL,
    CONSTRAINT pk_ic_min_writes_test PRIMARY KEY CLUSTERED (id)
);

/*
ic_unused_test: ix_never_read has distinct keys so no dedupe rule can fire on it.
The only thing that can flag it is Rule 1.
*/
CREATE TABLE
    dbo.ic_unused_test
(
    id integer NOT NULL,
    col_a integer NOT NULL,
    col_b integer NOT NULL,
    filler varchar(100) NOT NULL,
    CONSTRAINT pk_ic_unused_test PRIMARY KEY CLUSTERED (id)
);

/*
ic_pk_key_test: a NONCLUSTERED primary key with a key duplicate next to it.
Same keys, different includes, so Rule 5 pairs them. The PK is unique and the
plain index is not, which makes the PK the "winner" and earns it MERGE
INCLUDES -> CREATE UNIQUE INDEX ... WITH (DROP_EXISTING = ON) against a
constraint-backed index. That fails with Msg 1907 while the paired DISABLE of
ix_pk_key_dupe succeeds, silently dropping col_b coverage.

is_primary_key is NOT is_unique_constraint: it is 0 for a primary key, so every
rule that guards only on is_unique_constraint leaves a PK exposed.
*/
CREATE TABLE
    dbo.ic_pk_key_test
(
    id integer NOT NULL,
    col_b integer NOT NULL,
    filler varchar(100) NOT NULL,
    CONSTRAINT pk_ic_pk_key_test PRIMARY KEY NONCLUSTERED (id)
);

/*
ic_pk_exact_test: a NONCLUSTERED primary key with an exact duplicate.

The names matter. Rule 2 breaks a priority tie alphabetically and disables the
LATER name, so the PK is deliberately named to sort after the plain index. Both
indexes are given exactly one seek below so their priorities genuinely tie
(500 unique + 200 seeks) and the tiebreak is what decides -- without that the
PK wins on its own and the bug never shows.

ALTER INDEX ... DISABLE against a PK does not error. It succeeds, disables every
inbound foreign key with it, and orphan rows then insert cleanly. A script that
succeeds while being wrong is the worst thing this procedure can emit, which is
why this asserts on the script text rather than on an execution error.
*/
CREATE TABLE
    dbo.ic_pk_exact_test
(
    id integer NOT NULL,
    filler varchar(100) NOT NULL,
    CONSTRAINT zz_pk_ic_pk_exact_test PRIMARY KEY NONCLUSTERED (id)
);

/*
ic_sort_dir_test: two indexes identical but for the sort direction of the
second key column, with different includes so they land in Rule 5 rather than
Rule 2.

Rule 2 and Rule 3 each carry an explicit is_descending_key comparison. Rule 5
carries NONE: its only defense is that key_columns embeds ' DESC' into the
string the key_filter_hash is built from. Delete that embedding and these two
become a false Key Duplicate -- the DESC index gets a cleanly-executing DISABLE
and the survivor is ASC-only, so every query depending on the DESC ordering
silently regresses. Nothing errors.

Both indexes are given reads so Rule 1 can never claim either on a
long-uptime server, which would make the assertions below pass vacuously.
ix_sort_asc gets seeks AND scans (200 + 100) while ix_sort_desc gets seeks
only (200), so priorities differ and the loser is deterministic.
*/
CREATE TABLE
    dbo.ic_sort_dir_test
(
    id integer NOT NULL,
    col_a integer NOT NULL,
    col_b integer NOT NULL,
    col_c integer NOT NULL,
    col_d integer NOT NULL,
    filler varchar(100) NOT NULL,
    CONSTRAINT pk_ic_sort_dir_test PRIMARY KEY CLUSTERED (id)
);

/*
ic_key_include_test: a key subset whose include is already a key column of the
superset that absorbs it.

Rule 3 disables ix_ki_subset (col_a) in favor of ix_ki_superset (col_a, col_b),
and Rule 6 merges the subset's includes into the superset. col_b is already in
the superset's KEY, and SQL Server rejects an index that includes its own key
column with Msg 1909. Rule 6's key-column exclusion is the only thing that
keeps col_b out of the INCLUDE list.
*/
CREATE TABLE
    dbo.ic_key_include_test
(
    id integer NOT NULL,
    col_a integer NOT NULL,
    col_b integer NOT NULL,
    filler varchar(100) NOT NULL,
    CONSTRAINT pk_ic_key_include_test PRIMARY KEY CLUSTERED (id)
);
GO

INSERT INTO
    dbo.ic_min_reads_test
(
    id,
    col_a,
    col_b,
    col_c,
    filler
)
SELECT TOP (20000)
    id = ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),
    col_a = ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) % 500,
    col_b = ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) % 100,
    col_c = ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) % 250,
    filler = REPLICATE('x', 100)
FROM sys.all_columns AS ac1
CROSS JOIN sys.all_columns AS ac2
OPTION(MAXDOP 1);

INSERT INTO
    dbo.ic_min_writes_test
(
    id,
    col_a,
    col_b,
    col_c,
    filler
)
SELECT TOP (20000)
    id = ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),
    col_a = ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) % 500,
    col_b = ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) % 100,
    col_c = ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) % 250,
    filler = REPLICATE('x', 100)
FROM sys.all_columns AS ac1
CROSS JOIN sys.all_columns AS ac2
OPTION(MAXDOP 1);

INSERT INTO
    dbo.ic_unused_test
(
    id,
    col_a,
    col_b,
    filler
)
SELECT TOP (20000)
    id = ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),
    col_a = ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) % 500,
    col_b = ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) % 100,
    filler = REPLICATE('x', 100)
FROM sys.all_columns AS ac1
CROSS JOIN sys.all_columns AS ac2
OPTION(MAXDOP 1);

INSERT INTO
    dbo.ic_pk_key_test
(
    id,
    col_b,
    filler
)
SELECT TOP (20000)
    id = ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),
    col_b = ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) % 100,
    filler = REPLICATE('x', 100)
FROM sys.all_columns AS ac1
CROSS JOIN sys.all_columns AS ac2
OPTION(MAXDOP 1);

INSERT INTO
    dbo.ic_pk_exact_test
(
    id,
    filler
)
SELECT TOP (20000)
    id = ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),
    filler = REPLICATE('x', 100)
FROM sys.all_columns AS ac1
CROSS JOIN sys.all_columns AS ac2
OPTION(MAXDOP 1);

INSERT INTO
    dbo.ic_sort_dir_test
(
    id,
    col_a,
    col_b,
    col_c,
    col_d,
    filler
)
SELECT TOP (20000)
    id = ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),
    col_a = ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) % 500,
    col_b = ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) % 100,
    col_c = ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) % 250,
    col_d = ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) % 50,
    filler = REPLICATE('x', 100)
FROM sys.all_columns AS ac1
CROSS JOIN sys.all_columns AS ac2
OPTION(MAXDOP 1);

INSERT INTO
    dbo.ic_key_include_test
(
    id,
    col_a,
    col_b,
    filler
)
SELECT TOP (20000)
    id = ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),
    col_a = ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) % 500,
    col_b = ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) % 100,
    filler = REPLICATE('x', 100)
FROM sys.all_columns AS ac1
CROSS JOIN sys.all_columns AS ac2
OPTION(MAXDOP 1);
GO

CREATE INDEX ix_hot ON dbo.ic_min_reads_test (col_a) INCLUDE (col_b);
CREATE INDEX ix_warm ON dbo.ic_min_reads_test (col_a) INCLUDE (col_c);

CREATE INDEX ix_w1 ON dbo.ic_min_writes_test (col_a) INCLUDE (col_b);
CREATE INDEX ix_w2 ON dbo.ic_min_writes_test (col_a) INCLUDE (col_c);

CREATE INDEX ix_never_read ON dbo.ic_unused_test (col_a);

/* Key duplicate of the nonclustered PK: same key, different includes -> Rule 5 */
CREATE INDEX ix_pk_key_dupe ON dbo.ic_pk_key_test (id) INCLUDE (col_b);

/* Exact duplicate of the nonclustered PK, named to sort BEFORE it */
CREATE UNIQUE INDEX aa_ix_pk_exact_dupe ON dbo.ic_pk_exact_test (id);

/* Identical but for the direction of col_b, and with different includes */
CREATE INDEX ix_sort_asc ON dbo.ic_sort_dir_test (col_a, col_b) INCLUDE (col_c);
CREATE INDEX ix_sort_desc ON dbo.ic_sort_dir_test (col_a, col_b DESC) INCLUDE (col_d);

/* Subset whose include (col_b) is already a key column of the superset */
CREATE INDEX ix_ki_subset ON dbo.ic_key_include_test (col_a) INCLUDE (col_b);
CREATE INDEX ix_ki_superset ON dbo.ic_key_include_test (col_a, col_b);
GO

/*
Drive reads so no index below is left cold enough for Rule 1 to claim it as
unused on a long-uptime server, which would make the absence assertions pass
for the wrong reason.

ix_sort_asc gets seeks AND scans (+200 +100) while ix_sort_desc gets seeks only
(+200). That gap is what makes ix_sort_desc the deterministic loser if the two
ever pair up, rather than leaving a priority tie to resolve arbitrarily.
*/
DECLARE
    @c bigint,
    @i integer = 0;

WHILE @i < 10
BEGIN
    /* PK key-duplicate pair: both sides read */
    SELECT @c = COUNT_BIG(*) FROM dbo.ic_pk_key_test AS t WITH (INDEX = pk_ic_pk_key_test) WHERE t.id = @i OPTION(MAXDOP 1);
    SELECT @c = COUNT_BIG(*) FROM dbo.ic_pk_key_test AS t WITH (INDEX = ix_pk_key_dupe) WHERE t.id = @i OPTION(MAXDOP 1);

    /* PK exact-duplicate pair: one seek each, so index_priority ties */
    SELECT @c = COUNT_BIG(*) FROM dbo.ic_pk_exact_test AS t WITH (INDEX = zz_pk_ic_pk_exact_test) WHERE t.id = @i OPTION(MAXDOP 1);
    SELECT @c = COUNT_BIG(*) FROM dbo.ic_pk_exact_test AS t WITH (INDEX = aa_ix_pk_exact_dupe) WHERE t.id = @i OPTION(MAXDOP 1);

    /* Sort-direction pair: seeks on both */
    SELECT @c = COUNT_BIG(*) FROM dbo.ic_sort_dir_test AS t WITH (INDEX = ix_sort_asc) WHERE t.col_a = @i OPTION(MAXDOP 1);
    SELECT @c = COUNT_BIG(*) FROM dbo.ic_sort_dir_test AS t WITH (INDEX = ix_sort_desc) WHERE t.col_a = @i OPTION(MAXDOP 1);

    /* Key-subset/superset pair: reads on both */
    SELECT @c = COUNT_BIG(*) FROM dbo.ic_key_include_test AS t WITH (INDEX = ix_ki_subset) WHERE t.col_a = @i OPTION(MAXDOP 1);
    SELECT @c = COUNT_BIG(*) FROM dbo.ic_key_include_test AS t WITH (INDEX = ix_ki_superset) WHERE t.col_a = @i OPTION(MAXDOP 1);

    SELECT @i += 1;
END;

/* Scans for ix_sort_asc only, so it outranks ix_sort_desc */
SELECT @i = 0;

WHILE @i < 3
BEGIN
    SELECT @c = COUNT_BIG(*) FROM dbo.ic_sort_dir_test AS t WITH (INDEX = ix_sort_asc) WHERE t.col_c >= 0 OPTION(MAXDOP 1);
    SELECT @i += 1;
END;
GO

/*
Drive reads with forced index hints, bounded: ix_hot ~200, ix_warm ~5, PK 0.
Nothing reads ic_unused_test at all.
*/
DECLARE
    @c bigint,
    @i integer = 0;

WHILE @i < 200
BEGIN
    SELECT @c = COUNT_BIG(*) FROM dbo.ic_min_reads_test AS t WITH (INDEX = ix_hot) WHERE t.col_a = @i % 500 OPTION(MAXDOP 1);
    SELECT @i += 1;
END;

SELECT @i = 0;

WHILE @i < 5
BEGIN
    SELECT @c = COUNT_BIG(*) FROM dbo.ic_min_reads_test AS t WITH (INDEX = ix_warm) WHERE t.col_a = @i % 500 OPTION(MAXDOP 1);
    SELECT @i += 1;
END;
GO

/*
Drive writes on ic_min_writes_test. Updating col_a maintains both ix_w1 and ix_w2
(it is the key of both), so both collect writes while collecting no reads.
*/
DECLARE
    @i integer = 0;

WHILE @i < 60
BEGIN
    UPDATE
        t
    SET
        t.col_a = (t.col_a + 1) % 500
    FROM dbo.ic_min_writes_test AS t
    WHERE t.id = @i
    OPTION(MAXDOP 1);

    SELECT @i += 1;
END;
GO
"""

CLEANUP_SQL = """
SET NOCOUNT ON;
DROP TABLE IF EXISTS dbo.ic_min_reads_test;
DROP TABLE IF EXISTS dbo.ic_min_writes_test;
DROP TABLE IF EXISTS dbo.ic_unused_test;
DROP TABLE IF EXISTS dbo.ic_pk_key_test;
DROP TABLE IF EXISTS dbo.ic_pk_exact_test;
DROP TABLE IF EXISTS dbo.ic_sort_dir_test;
DROP TABLE IF EXISTS dbo.ic_key_include_test;
"""

# Group F's fixture. Unlike everything above it, this one needs two databases:
# the defect only exists across iterations of the @get_all_databases loop.
#
# CrapA MUST be created before CrapB. The procedure's database cursor is
# ORDER BY database_id, NOT by name, so processing order is CREATION order and
# the names are a convenience rather than the mechanism. CrapA therefore has to
# be the first database processed, so that its rows are the stale ones still
# sitting in #index_analysis when CrapB's pass truncates #index_details out from
# under them. run_tests asserts that this actually held rather than trusting it.
#
# CrapA gets PRIMARY KEY NONCLUSTERED (col_a) + UNIQUE (col_a) + ix_mdb (col_a).
# The unique constraint is what gives Rule 7.5 something to replace, which is
# what leaves a MAKE UNIQUE winner (ix_mdb) behind in #index_analysis. Without it
# there is no winner for the stale PK to pair with and the bug cannot fire.
#
# CrapB only has to exist, contain the table so the loop does real work for it,
# and be processed after CrapA. Its own indexes are uninteresting; the second
# iteration itself is the point.
#
# Both databases are pre-dropped so a run that died before its cleanup cannot
# leave a half-built fixture that quietly changes what is being tested.
MDB_SETUP_SQL = """
SET NOCOUNT ON;
GO

IF DB_ID('%(first)s') IS NOT NULL
BEGIN
    ALTER DATABASE %(first)s SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE %(first)s;
END;
GO

IF DB_ID('%(second)s') IS NOT NULL
BEGIN
    ALTER DATABASE %(second)s SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE %(second)s;
END;
GO

/* Creation order is processing order. This one has to come first. */
CREATE DATABASE %(first)s;
GO

CREATE DATABASE %(second)s;
GO

USE %(first)s;
GO

/*
The unique constraint is the load-bearing part: Rule 7.5 replaces it with ix_mdb
and marks ix_mdb MAKE UNIQUE, and that leftover winner is what the stale primary
key used to get paired against on the next database's pass.
*/
CREATE TABLE
    dbo.mdb_test
(
    col_a integer NOT NULL,
    col_b integer NOT NULL,
    CONSTRAINT pk_mdb PRIMARY KEY NONCLUSTERED (col_a),
    CONSTRAINT uq_mdb UNIQUE (col_a)
);

INSERT INTO
    dbo.mdb_test
(
    col_a,
    col_b
)
SELECT TOP (20000)
    col_a = ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),
    col_b = 1
FROM sys.all_columns AS ac1
CROSS JOIN sys.all_columns AS ac2
OPTION(MAXDOP 1);

CREATE INDEX ix_mdb ON dbo.mdb_test (col_a);
GO

USE %(second)s;
GO

/*
Deliberately plain. All this database has to do is exist and be processed after
CrapA, so that a second loop iteration happens at all.
*/
CREATE TABLE
    dbo.mdb_test
(
    col_a integer NOT NULL,
    col_b integer NOT NULL
);

INSERT INTO
    dbo.mdb_test
(
    col_a,
    col_b
)
SELECT TOP (20000)
    col_a = ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),
    col_b = 1
FROM sys.all_columns AS ac1
CROSS JOIN sys.all_columns AS ac2
OPTION(MAXDOP 1);

CREATE INDEX ix_mdb_b ON dbo.mdb_test (col_a);
GO
""" % {"first": MDB_DATABASE_FIRST, "second": MDB_DATABASE_SECOND}

# Runs unconditionally, including when the fixture failed to build or an
# assertion failed. Leaving stray databases on the instance is not acceptable,
# so this takes them SINGLE_USER first rather than letting a stray session block
# the drop and leak the database.
MDB_CLEANUP_SQL = """
SET NOCOUNT ON;
GO

IF DB_ID('%(first)s') IS NOT NULL
BEGIN
    ALTER DATABASE %(first)s SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE %(first)s;
END;
GO

IF DB_ID('%(second)s') IS NOT NULL
BEGIN
    ALTER DATABASE %(second)s SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE %(second)s;
END;
GO
""" % {"first": MDB_DATABASE_FIRST, "second": MDB_DATABASE_SECOND}


# Group G's fixture. Runs AFTER MDB_SETUP_SQL has created CrapA and CrapB, and
# just adds two tables to each. Kept separate from MDB_SETUP_SQL so Group F's
# narrative stays about mdb_test alone; the shared teardown (MDB_CLEANUP_SQL drops
# both databases) already carries these tables away.
#
# The bug material goes in CrapA because it is processed first, so its rows are
# the stale ones still sitting in #index_analysis when CrapB's pass truncates
# #index_details. CrapB gets plain copies so the loop takes a real second
# iteration for whichever table each scoped run targets.
#
# icg_merge: a Key Superset (col_a, col_b) INCLUDE (col_c) over a subset
# (col_a) INCLUDE (col_d). Rule 4/6 merges the subset's col_d into the superset,
# whose correct merged script is INCLUDE (col_c, col_d). On CrapB's pass the
# include-merge recomputes CrapA's superset from an emptied #index_details, gets
# NULL, and overwrites it -- the merge-script insert then emits a stripped row
# with no INCLUDE that can win the final ROW_NUMBER tie.
#
# icg_uc: a UNIQUE constraint uq_icg (col_a, id) with a same-key plain index
# ix_uc_plain. Rule 7.5 promotes the index to replace the constraint and drops
# the constraint. On CrapB's pass the DISABLE-script insert's
# NOT EXISTS (#index_details ... is_unique_constraint = 1) guard passes vacuously
# for stale uq_icg and emits ALTER INDEX [uq_icg] ... DISABLE on top of the
# correct DROP CONSTRAINT.
#
# No modulo (%) anywhere in the DDL: this string is %-formatted for the database
# names, so a literal % would be read as a format specifier.
MDB_G_SETUP_SQL = """
SET NOCOUNT ON;
GO

USE %(first)s;
GO

/* Bug 1: superset/subset include-merge pair. */
CREATE TABLE
    dbo.icg_merge
(
    id integer NOT NULL,
    col_a integer NOT NULL,
    col_b integer NOT NULL,
    col_c integer NOT NULL,
    col_d integer NOT NULL,
    CONSTRAINT pk_icg_merge PRIMARY KEY CLUSTERED (id)
);

INSERT INTO
    dbo.icg_merge
(
    id,
    col_a,
    col_b,
    col_c,
    col_d
)
SELECT TOP (20000)
    id = ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),
    col_a = ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),
    col_b = 1,
    col_c = 2,
    col_d = 3
FROM sys.all_columns AS ac1
CROSS JOIN sys.all_columns AS ac2
OPTION(MAXDOP 1);

CREATE INDEX ix_merge_super ON dbo.icg_merge (col_a, col_b) INCLUDE (col_c);
CREATE INDEX ix_merge_sub   ON dbo.icg_merge (col_a) INCLUDE (col_d);
GO

/* Bug 2: unique constraint + same-key plain index. */
CREATE TABLE
    dbo.icg_uc
(
    id integer NOT NULL,
    col_a integer NOT NULL,
    col_c integer NOT NULL,
    CONSTRAINT pk_icg_uc PRIMARY KEY CLUSTERED (id)
);

INSERT INTO
    dbo.icg_uc
(
    id,
    col_a,
    col_c
)
SELECT TOP (20000)
    id = ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),
    col_a = ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),
    col_c = 1
FROM sys.all_columns AS ac1
CROSS JOIN sys.all_columns AS ac2
OPTION(MAXDOP 1);

ALTER TABLE dbo.icg_uc ADD CONSTRAINT uq_icg UNIQUE (col_a, id);
CREATE INDEX ix_uc_plain ON dbo.icg_uc (col_a, id) INCLUDE (col_c);
GO

USE %(second)s;
GO

/* Plain copies so the second iteration does real work for the scoped table. */
CREATE TABLE
    dbo.icg_merge
(
    id integer NOT NULL,
    col_a integer NOT NULL,
    col_b integer NOT NULL
);

INSERT INTO
    dbo.icg_merge
(
    id,
    col_a,
    col_b
)
SELECT TOP (20000)
    id = ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),
    col_a = 1,
    col_b = 2
FROM sys.all_columns AS ac1
CROSS JOIN sys.all_columns AS ac2
OPTION(MAXDOP 1);

CREATE INDEX ix_merge_b ON dbo.icg_merge (col_a);
GO

CREATE TABLE
    dbo.icg_uc
(
    id integer NOT NULL,
    col_a integer NOT NULL,
    col_c integer NOT NULL
);

INSERT INTO
    dbo.icg_uc
(
    id,
    col_a,
    col_c
)
SELECT TOP (20000)
    id = ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),
    col_a = 1,
    col_c = 2
FROM sys.all_columns AS ac1
CROSS JOIN sys.all_columns AS ac2
OPTION(MAXDOP 1);

CREATE INDEX ix_uc_b ON dbo.icg_uc (col_a);
GO
""" % {"first": MDB_DATABASE_FIRST, "second": MDB_DATABASE_SECOND}


def run_sqlcmd(server, password, input_file=None, query=None,
               database=TEST_DATABASE, timeout=600):
    """Run SQL from a file or a query string and capture output."""
    cmd = [
        "sqlcmd", "-S", server, "-U", "sa", "-P", password,
        "-d", database,
        "-W",  # trim trailing spaces
        "-s", "\t",  # tab delimiter
    ]
    if input_file is not None:
        cmd += ["-i", input_file]
    else:
        cmd += ["-Q", query]

    result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    return result.stdout, result.stderr


def run_sql_script(server, password, sql, database=TEST_DATABASE, timeout=600):
    """Run a multi-batch script (one containing GO) through a temp file."""
    path = None
    try:
        handle, path = tempfile.mkstemp(suffix=".sql", prefix="ic_rule_cov_")
        with os.fdopen(handle, "w") as f:
            f.write(sql)
        return run_sqlcmd(server, password, input_file=path,
                          database=database, timeout=timeout)
    finally:
        if path and os.path.exists(path):
            os.remove(path)


def sql_errors(stdout, stderr):
    """
    Every SQL error worth failing a fixture over, from both streams.

    go-sqlcmd reports SQL errors on stdout, and severities 17-19 matter as much
    as 16 -- an earlier version of this looked for the literal "Level 16" on
    stderr only, which is how adversarial_test.sql managed to fail on every run
    for months while the suite stayed green.
    """
    return (re.findall(r"Msg \d+, Level 1[6-9][^\n]*", stdout or "") +
            re.findall(r"Msg \d+, Level 1[6-9][^\n]*", stderr or ""))


def parse_output(stdout):
    """
    Parse sp_IndexCleanup tab-delimited output into rows.

    Bounded to the script result set: the procedure emits several result sets and
    the later ones share nothing but a tab delimiter, so parsing stops at the
    blank line that ends this one. That bound matters here because most of the
    assertions below are assertions of absence.

    Column order, verified empirically against the running procedure:
        script_type, additional_info, database_name, schema_name, table_name,
        index_name, consolidation_rule, target_index_name, superseded_info,
        index_size_gb, index_rows, index_reads, index_writes,
        original_index_definition, script
    """
    rows = []
    lines = stdout.split("\n")
    headers = None
    started = False

    for line in lines:
        if headers is None:
            if "script_type" in line and "index_name" in line:
                headers = [h.strip() for h in line.split("\t")]
            continue

        if line.startswith("---"):
            continue

        if not line.strip():
            if started:
                break
            continue

        cols = [c.strip() for c in line.split("\t")]
        if len(cols) >= len(headers):
            rows.append(dict(zip(headers, cols)))
            started = True

    return rows


def find_rows(rows, **filters):
    """Find rows matching all filter criteria."""
    matches = []
    for row in rows:
        match = True
        for key, value in filters.items():
            if key.endswith("__like"):
                col = key[:-6]
                if col not in row or value.lower() not in row[col].lower():
                    match = False
                    break
            elif key.endswith("__in"):
                col = key[:-4]
                if col not in row or row[col] not in value:
                    match = False
                    break
            else:
                if key not in row or row[key] != value:
                    match = False
                    break
        if match:
            matches.append(row)
    return matches


def dedupe_rows(rows, index_name):
    """Every dedupe-action row for an index. Compression rows are not included."""
    return [
        r for r in rows
        if r.get("index_name") == index_name
        and r.get("script_type") in DEDUPE_SCRIPT_TYPES
    ]


def get_uptime_days(server, password):
    """Server uptime in days, as the procedure itself computes it."""
    stdout, _ = run_sqlcmd(
        server, password, database="master",
        query="SET NOCOUNT ON; SELECT uptime = DATEDIFF(DAY, osi.sqlserver_start_time,"
              " SYSDATETIME()) FROM sys.dm_os_sys_info AS osi;",
    )
    for line in stdout.split("\n"):
        line = line.strip()
        if line.isdigit():
            return int(line)
    raise RuntimeError("Could not read server uptime:\n%s" % stdout)


def get_database_id(server, password, database_name):
    """
    A database's database_id, or None if it does not exist.

    Group F needs this because the procedure's database cursor is
    ORDER BY database_id: the id, not the name, is what decides which database
    the loop processes first.
    """
    stdout, _ = run_sqlcmd(
        server, password, database="master",
        query="SET NOCOUNT ON; SELECT database_id = DB_ID('%s');" % database_name,
    )
    for line in stdout.split("\n"):
        line = line.strip()
        if line.isdigit():
            return int(line)
    return None


def run_proc(server, password, table_name, extra="", debug=False):
    """Run sp_IndexCleanup scoped to one table and return (rows, stdout)."""
    query = (
        "EXECUTE master.dbo.sp_IndexCleanup "
        "@database_name = '%s', @schema_name = 'dbo', @table_name = '%s'%s%s;"
        % (TEST_DATABASE, table_name, extra, ", @debug = 1" if debug else "")
    )
    stdout, _ = run_sqlcmd(server, password, database="master", query=query)
    return parse_output(stdout), stdout


def run_proc_all_databases(server, password, table_name):
    """
    Run sp_IndexCleanup across every database on the instance, scoped to one
    table, and return (rows, stdout).

    @get_all_databases = 1 is the entire point: it is the only way to make the
    procedure loop, and the loop is what Group F is testing. @table_name keeps it
    cheap -- every database without that table is dismissed immediately.
    """
    query = (
        "EXECUTE master.dbo.sp_IndexCleanup "
        "@get_all_databases = 1, @schema_name = 'dbo', @table_name = '%s';"
        % table_name
    )
    stdout, _ = run_sqlcmd(server, password, database="master", query=query)
    return parse_output(stdout), stdout


def run_tests(server, password, uptime_days):
    """Run all assertions and return results."""
    results = []

    def assert_test(group, name, condition, detail=""):
        results.append({
            "group": group,
            "name": name,
            "passed": condition,
            "detail": detail,
        })

    # ---- Group A: Rule 1, unused index detection ----

    rows, _ = run_proc(server, password, "ic_unused_test")
    unused_rows = [
        r for r in rows
        if "unused index" in (r.get("consolidation_rule") or "").lower()
    ]

    if uptime_days > 7:
        # Rule 1 is reachable: @dedupe_only defaults to 0 and stays there.
        matches = find_rows(rows, index_name="ix_never_read",
                            script_type="DISABLE SCRIPT",
                            consolidation_rule__like="Unused Index")
        assert_test("A-Rule1", "ix_never_read disabled as Unused Index",
                    len(matches) == 1,
                    "found %d (uptime %d days, Rule 1 reachable)"
                    % (len(matches), uptime_days))
    else:
        # Rule 1 is unreachable by design. Assert the guard instead.
        #
        # Positive controls first: without them "no Unused Index rows" would be
        # true for any number of uninteresting reasons.
        present = find_rows(rows, index_name="ix_never_read")
        assert_test("A-Guard", "positive control: ix_never_read was analyzed",
                    len(present) >= 1,
                    "found %d rows for the index (%s)"
                    % (len(present), [p["script_type"] for p in present]))

        reads = present[0].get("index_reads") if present else None
        assert_test("A-Guard", "positive control: ix_never_read has zero reads",
                    reads == "0", "index_reads=%s" % reads)

        # The procedure says so itself when asked with @debug = 1.
        _, debug_stdout = run_proc(server, password, "ic_unused_test", debug=True)
        assert_test("A-Guard", "@dedupe_only auto-enabled by the uptime guard",
                    GUARD_MESSAGE in debug_stdout,
                    "procedure reported the auto-enable"
                    if GUARD_MESSAGE in debug_stdout
                    else "guard message never appeared with @debug = 1")

        # Therefore Rule 1 never ran, and nothing is recommended as unused.
        assert_test("A-Guard", "no Unused Index rows while the guard is active",
                    len(unused_rows) == 0,
                    "found %d unused rows (expected 0)" % len(unused_rows))

    # ---- Group B: @min_reads / @min_writes index-level screen ----

    # B1: no floor. ix_hot and ix_warm are key duplicates and should pair up.
    rows, _ = run_proc(server, password, "ic_min_reads_test", extra=", @min_reads = 0")

    hot = dedupe_rows(rows, "ix_hot")
    warm = dedupe_rows(rows, "ix_warm")
    assert_test("B-MinReads", "@min_reads = 0: ix_hot/ix_warm get a dedupe recommendation",
                len(hot) >= 1 and len(warm) >= 1,
                "ix_hot=%s ix_warm=%s"
                % ([h["script_type"] for h in hot], [w["script_type"] for w in warm]))

    # B2: floor above ix_warm's 5 reads. ix_warm is below it, so the pair cannot
    # be deduped -- both sides must clear the floor on their own.
    rows, _ = run_proc(server, password, "ic_min_reads_test", extra=", @min_reads = 100")

    warm = dedupe_rows(rows, "ix_warm")
    assert_test("B-MinReads", "@min_reads = 100: ix_warm not deduped (5 reads, below floor)",
                len(warm) == 0,
                "found %d (%s)" % (len(warm), [w["script_type"] for w in warm]))

    # And the half that actually matters: the screen gates dedupe ONLY. Losing a
    # compression recommendation to a reads floor would be a bug -- compression
    # eligibility has nothing to do with how often an index is read.
    matches = find_rows(rows, index_name="ix_warm", script_type="COMPRESSION SCRIPT")
    assert_test("B-MinReads", "@min_reads = 100: ix_warm still gets COMPRESSION SCRIPT",
                len(matches) == 1, "found %d" % len(matches))

    matches = find_rows(rows, index_name="pk_ic_min_reads_test",
                        script_type="COMPRESSION SCRIPT")
    assert_test("B-MinReads", "@min_reads = 100: PK still gets COMPRESSION SCRIPT",
                len(matches) == 1, "found %d" % len(matches))

    # B3: write floor only. ix_w1/ix_w2 have 60 writes and zero reads, so they
    # clear on the write side alone.
    rows, _ = run_proc(server, password, "ic_min_writes_test", extra=", @min_writes = 50")

    w1 = dedupe_rows(rows, "ix_w1")
    w2 = dedupe_rows(rows, "ix_w2")
    assert_test("B-MinWrites", "@min_writes = 50, no reads floor: write-only pair still dedupes",
                len(w1) >= 1 and len(w2) >= 1,
                "ix_w1=%s ix_w2=%s"
                % ([w["script_type"] for w in w1], [w["script_type"] for w in w2]))

    # B4: the same pair against a reads floor it cannot meet. Together with B3
    # this is what makes the floors an OR rather than an AND: identical indexes,
    # identical usage, deduped under the write floor and not under the read floor.
    rows, _ = run_proc(server, password, "ic_min_writes_test", extra=", @min_reads = 50")

    w1 = dedupe_rows(rows, "ix_w1")
    w2 = dedupe_rows(rows, "ix_w2")
    assert_test("B-MinWrites", "@min_reads = 50 alone: same pair not deduped (0 reads)",
                len(w1) == 0 and len(w2) == 0,
                "ix_w1=%s ix_w2=%s"
                % ([w["script_type"] for w in w1], [w["script_type"] for w in w2]))

    # Compression survives this screen too.
    matches = find_rows(rows, index_name="ix_w1", script_type="COMPRESSION SCRIPT")
    assert_test("B-MinWrites", "@min_reads = 50 alone: ix_w1 still gets COMPRESSION SCRIPT",
                len(matches) == 1, "found %d" % len(matches))

    # ---- Group C: nonclustered PRIMARY KEYs are constraint-backed ----
    #
    # A PK cannot be rebuilt via DROP_EXISTING with different includes (Msg 1907)
    # and must never be disabled (it succeeds, and takes every inbound foreign key
    # down with it). is_primary_key is not is_unique_constraint -- the latter is 0
    # for a primary key -- so a PK needs its own protection everywhere a unique
    # constraint gets it.

    # C1: PK with a key duplicate. Nothing may target the PK for a rebuild.
    rows, _ = run_proc(server, password, "ic_pk_key_test")

    pk = "pk_ic_pk_key_test"

    merge_rows = find_rows(rows, index_name=pk, script_type="MERGE SCRIPT")
    assert_test("C-PrimaryKey", "PK with a key duplicate gets no MERGE SCRIPT",
                len(merge_rows) == 0,
                "found %d (any is CREATE UNIQUE INDEX ... DROP_EXISTING vs a PK -> Msg 1907)"
                % len(merge_rows))

    # Nothing may name the PK in ANY dedupe action, merge or disable.
    pk_dedupe = dedupe_rows(rows, pk)
    assert_test("C-PrimaryKey", "PK with a key duplicate gets no dedupe action at all",
                len(pk_dedupe) == 0,
                "found %s" % [r["script_type"] for r in pk_dedupe])

    # No OTHER index may claim the PK as its merge/disable target either: that is
    # the half that silently drops a covering column when the rebuild fails.
    targeting = [
        r for r in rows
        if r.get("target_index_name") == pk
        and r.get("script_type") in DEDUPE_SCRIPT_TYPES
    ]
    assert_test("C-PrimaryKey", "no script targets the PK as a consolidation winner",
                len(targeting) == 0,
                "found %s" % [(r["index_name"], r["script_type"]) for r in targeting])

    # Positive control: proving the PK is protected is only meaningful if the
    # procedure actually looked at it. Compression is the proof it is still in
    # play and was not made invisible to fix the bug above.
    matches = find_rows(rows, index_name=pk, script_type="COMPRESSION SCRIPT")
    assert_test("C-PrimaryKey", "positive control: PK still gets COMPRESSION SCRIPT",
                len(matches) == 1, "found %d" % len(matches))

    # C2: PK with an exact duplicate, priorities tied, PK sorting later. This is
    # the case that used to emit ALTER INDEX [pk...] DISABLE -- a script that
    # executes cleanly and silently turns off referential integrity.
    rows, _ = run_proc(server, password, "ic_pk_exact_test")

    pk = "zz_pk_ic_pk_exact_test"

    disable_rows = find_rows(rows, index_name=pk, script_type="DISABLE SCRIPT")
    assert_test("C-PrimaryKey", "PK with an exact duplicate gets no DISABLE SCRIPT",
                len(disable_rows) == 0,
                "found %d (a PK DISABLE succeeds and disables inbound FKs)"
                % len(disable_rows))

    pk_dedupe = dedupe_rows(rows, pk)
    assert_test("C-PrimaryKey", "PK with an exact duplicate gets no dedupe action at all",
                len(pk_dedupe) == 0,
                "found %s" % [r["script_type"] for r in pk_dedupe])

    matches = find_rows(rows, index_name=pk, script_type="COMPRESSION SCRIPT")
    assert_test("C-PrimaryKey", "positive control: tied PK still gets COMPRESSION SCRIPT",
                len(matches) == 1, "found %d" % len(matches))

    # ---- Group D: sort direction is part of an index's identity ----
    #
    # Rule 5 has no is_descending_key comparison of its own. The ' DESC' embedded
    # in key_columns is the entire reason (col_a, col_b) and (col_a, col_b DESC)
    # do not hash alike, and a false Key Duplicate here disables a real index
    # with a script that runs without complaint.
    rows, _ = run_proc(server, password, "ic_sort_dir_test")

    for name in ("ix_sort_asc", "ix_sort_desc"):
        actions = dedupe_rows(rows, name)
        assert_test("D-SortDirection",
                    "%s: ASC/DESC pair is not a duplicate (no dedupe action)" % name,
                    len(actions) == 0,
                    "found %s" % [(r["script_type"], r["consolidation_rule"])
                                  for r in actions])

    # Positive control: both were analyzed, so the absence above is the direction
    # check holding rather than the indexes never being considered.
    for name in ("ix_sort_asc", "ix_sort_desc"):
        matches = find_rows(rows, index_name=name)
        assert_test("D-SortDirection", "positive control: %s was analyzed" % name,
                    len(matches) >= 1,
                    "found %d rows (%s)"
                    % (len(matches), [m["script_type"] for m in matches]))

    # ---- Group E: a merged index may not INCLUDE its own key column ----
    #
    # Rule 6 merges a subset's includes into the superset that absorbs it. When
    # the subset's include is already a KEY of the superset, keeping it emits
    # CREATE INDEX (col_a, col_b) INCLUDE (col_b), which SQL Server rejects with
    # Msg 1909 -- while the paired DISABLE of the subset still runs.
    rows, _ = run_proc(server, password, "ic_key_include_test")

    merge = find_rows(rows, index_name="ix_ki_superset", script_type="MERGE SCRIPT")
    assert_test("E-KeyInclude", "positive control: the superset gets a MERGE SCRIPT",
                len(merge) == 1, "found %d" % len(merge))

    if merge:
        script = merge[0].get("script") or ""
        include_part = script.split("INCLUDE", 1)[1] if "INCLUDE" in script else ""
        assert_test("E-KeyInclude",
                    "merged superset does not INCLUDE its own key column col_b",
                    "[col_b]" not in include_part,
                    "INCLUDE clause was '%s' in: %s"
                    % (include_part.strip()[:60], script[:110]))

    # And the subset really was disabled in its favor, so the merge above is the
    # live code path rather than a rule that never fired.
    subset = find_rows(rows, index_name="ix_ki_subset", script_type="DISABLE SCRIPT")
    assert_test("E-KeyInclude", "positive control: the key subset is disabled",
                len(subset) == 1, "found %d" % len(subset))

    # ---- Group F: #index_details is per-database, #index_analysis is not ----
    #
    # Under @get_all_databases, #index_details is TRUNCATED for each database in
    # the loop while #index_analysis ACCUMULATES across all of them for the final
    # output, so every rule re-runs over rows belonging to databases that were
    # already processed.
    #
    # Rules 2/3/5/7 survive it: each requires EXISTS (#index_details ...
    # is_eligible_for_dedupe = 1), which finds nothing for a stale row and fails
    # CLOSED. Rule 7.6 had only NOT EXISTS (... is_unique_constraint = 1), which
    # passes VACUOUSLY once the table is empty -- so on CrapB's pass it paired
    # CrapA's leftover MAKE UNIQUE winner with CrapA's primary key and marked the
    # PK DISABLE. The script-generation backstops read #index_details too, so
    # they passed vacuously in turn and the script shipped:
    #
    #     ALTER INDEX [pk_mdb] ON [CrapA].[dbo].[mdb_test] DISABLE;
    #
    # which runs cleanly and silently disables every inbound foreign key.
    rows, _ = run_proc_all_databases(server, password, MDB_TABLE)

    # Positive controls FIRST, because every assertion in this group is an
    # assertion of absence and each control below is a precondition the bug needs
    # in order to fire at all. If any of them stops holding, "no DISABLE named the
    # PK" becomes true for a reason that has nothing to do with the guard, and
    # this group would pass while testing nothing.

    # F-PC1: CrapA has to be processed BEFORE CrapB or there is no stale-row pass.
    # The cursor is ORDER BY database_id, not by name, so this is creation order.
    # Asserted rather than assumed: the names sorting the "right" way is a
    # coincidence, not the mechanism, and nothing would announce it if it flipped.
    id_first = get_database_id(server, password, MDB_DATABASE_FIRST)
    id_second = get_database_id(server, password, MDB_DATABASE_SECOND)
    assert_test("F-MultiDatabase",
                "positive control: %s is processed before %s"
                % (MDB_DATABASE_FIRST, MDB_DATABASE_SECOND),
                id_first is not None
                and id_second is not None
                and id_first < id_second,
                "database_id %s=%s %s=%s (cursor is ORDER BY database_id)"
                % (MDB_DATABASE_FIRST, id_first, MDB_DATABASE_SECOND, id_second))

    # F-PC2: CrapA's table was really analyzed and its PK is visible to the
    # procedure. This is the control that stops "no DISABLE named the PK" from
    # passing because the fixture never built or the database was never reached.
    # It is also the half that keeps the fix honest: protecting the PK must not
    # be implemented by making primary keys invisible.
    pk_compression = find_rows(rows, database_name=MDB_DATABASE_FIRST,
                               index_name=MDB_PK, script_type="COMPRESSION SCRIPT")
    assert_test("F-MultiDatabase",
                "positive control: %s.%s gets a COMPRESSION SCRIPT"
                % (MDB_DATABASE_FIRST, MDB_PK),
                len(pk_compression) == 1, "found %d" % len(pk_compression))

    # F-PC3: Rule 7.5 fired and left a MAKE UNIQUE winner behind. This is the
    # precondition that matters most. The bug pairs a stale PK against exactly
    # this winner, so if the unique constraint stopped being replaced there would
    # be nothing to pair with and the absence assertions below would be vacuous.
    winner = find_rows(rows, database_name=MDB_DATABASE_FIRST, index_name="ix_mdb",
                       script_type="MERGE SCRIPT",
                       consolidation_rule__like="Unique Constraint Replacement")
    assert_test("F-MultiDatabase",
                "positive control: ix_mdb is the MAKE UNIQUE winner (Rule 7.5 fired)",
                len(winner) == 1,
                "found %d -- without this winner the bug has nothing to pair a "
                "stale PK against" % len(winner))

    # F-PC4: CrapB was actually reached, so the loop genuinely took a second
    # iteration. One database processed means #index_details is never truncated
    # out from under anything and the whole scenario evaporates.
    second_db = find_rows(rows, database_name=MDB_DATABASE_SECOND)
    assert_test("F-MultiDatabase",
                "positive control: %s was reached (a second loop iteration happened)"
                % MDB_DATABASE_SECOND,
                len(second_db) >= 1,
                "found %d rows for %s (%s)"
                % (len(second_db), MDB_DATABASE_SECOND,
                   [r["index_name"] for r in second_db]))

    # The assertions. Not scoped to a database: a primary key must not be
    # disabled in ANY of them, and the bug's victim is whichever database the
    # loop happened to process first.
    disable_rows = find_rows(rows, index_name=MDB_PK, script_type="DISABLE SCRIPT")
    assert_test("F-MultiDatabase",
                "no DISABLE SCRIPT names the primary key, in any database",
                len(disable_rows) == 0,
                "found %d (a PK DISABLE succeeds and disables inbound FKs) %s"
                % (len(disable_rows),
                   [(r["database_name"], r["consolidation_rule"]) for r in disable_rows]))

    # Broader than the DISABLE above: no dedupe action of any kind may name the
    # PK. A MERGE against a constraint-backed index is Msg 1907, and a DISABLE
    # CONSTRAINT would drop the key outright.
    pk_dedupe = dedupe_rows(rows, MDB_PK)
    assert_test("F-MultiDatabase",
                "no dedupe action of any kind targets the primary key",
                len(pk_dedupe) == 0,
                "found %s"
                % [(r["database_name"], r["script_type"], r["consolidation_rule"])
                   for r in pk_dedupe])

    # And nothing may claim the PK as its consolidation winner either -- the
    # other direction of the same pairing.
    targeting = [
        r for r in rows
        if r.get("target_index_name") == MDB_PK
        and r.get("script_type") in DEDUPE_SCRIPT_TYPES
    ]
    assert_test("F-MultiDatabase",
                "no script targets the primary key as a consolidation winner",
                len(targeting) == 0,
                "found %s" % [(r["database_name"], r["index_name"], r["script_type"])
                              for r in targeting])

    # ---- Group G: include-merge scripts and unique-constraint DISABLE survive the loop ----
    #
    # Same defect class as Group F -- per-database temp tables are truncated each
    # iteration while #index_analysis accumulates, so every rule and every
    # script-generation statement re-runs over rows belonging to databases
    # already processed. Group F caught the primary-key DISABLE. These are two
    # other ways it surfaced before the per-database scoping fix, both in CrapA
    # (processed first, so its rows are the stale ones during CrapB's pass):
    #
    #   Bug 1: the include-merge machinery recomputes CrapA's superset winner from
    #   an emptied #index_details on CrapB's pass, gets NULL, and overwrites its
    #   merged includes. The merge-script insert then emits a SECOND, stripped row
    #   (no INCLUDE, no DATA_COMPRESSION, no ON [filegroup]) and the final
    #   ROW_NUMBER ties it against the good one. Run, the stripped pair rebuilds
    #   the winner with every covering column gone while its subset is disabled --
    #   and it executes without error.
    #
    #   Bug 2: the DISABLE-script insert excludes unique constraints with
    #   NOT EXISTS (#index_details ... is_unique_constraint = 1), which passes
    #   VACUOUSLY for a stale row whose #index_details was truncated. So CrapA's
    #   uq_icg got ALTER INDEX ... DISABLE in addition to its correct
    #   DROP CONSTRAINT -- and ALTER INDEX DISABLE on a unique constraint's index
    #   silently disables every inbound foreign key.
    #
    # Every assertion below is an assertion of absence, so each is preceded by
    # positive controls: the rule fired, the winner was produced, and CrapB was
    # reached. Without those a green result could just mean the fixture never
    # built or the rule silently stopped matching.

    # --- Bug 1: the include-merge winner must keep its INCLUDE list ---
    merge_rows, _ = run_proc_all_databases(server, password, MDB_MERGE_TABLE)

    # G-PC1: the merge winner was produced at all (Rule 4/6 fired for CrapA). If
    # it were not, "no merge script is missing its INCLUDE" would pass vacuously.
    merge_winner = find_rows(merge_rows, database_name=MDB_DATABASE_FIRST,
                             index_name=MDB_MERGE_WINNER, script_type="MERGE SCRIPT")
    assert_test("G-MultiDatabase",
                "positive control: %s.%s gets a MERGE SCRIPT (include-merge fired)"
                % (MDB_DATABASE_FIRST, MDB_MERGE_WINNER),
                len(merge_winner) == 1, "found %d" % len(merge_winner))

    # G-PC2: its subset really was disabled -- the other half of the pair whose
    # includes the merge is supposed to absorb. No subset, no merge to strip.
    merge_subset = find_rows(merge_rows, database_name=MDB_DATABASE_FIRST,
                             index_name=MDB_MERGE_SUBSET, script_type="DISABLE SCRIPT")
    assert_test("G-MultiDatabase",
                "positive control: %s.%s (the subset) is disabled"
                % (MDB_DATABASE_FIRST, MDB_MERGE_SUBSET),
                len(merge_subset) == 1, "found %d" % len(merge_subset))

    # G-PC3: CrapB was reached for this table, so the loop took a real second
    # iteration and #index_details was truncated out from under CrapA's rows.
    merge_second = find_rows(merge_rows, database_name=MDB_DATABASE_SECOND)
    assert_test("G-MultiDatabase",
                "positive control: %s was reached for %s (a second iteration happened)"
                % (MDB_DATABASE_SECOND, MDB_MERGE_TABLE),
                len(merge_second) >= 1,
                "found %d rows for %s" % (len(merge_second), MDB_DATABASE_SECOND))

    # The assertion. The surviving merge script must still carry an INCLUDE. The
    # stripped row the bug produced has the INCLUDE clause gone entirely, so any
    # merge row for the winner whose script has no INCLUDE is the defect.
    merge_stripped = [
        r for r in merge_winner
        if "include" not in r.get("script", "").lower()
    ]
    assert_test("G-MultiDatabase",
                "no merge script for %s is missing its INCLUDE list, in any database"
                % MDB_MERGE_WINNER,
                len(merge_stripped) == 0,
                "found %d stripped (winner rebuilt without its covering columns): %s"
                % (len(merge_stripped), [r.get("script") for r in merge_stripped]))

    # --- Bug 2: a unique constraint must never get ALTER INDEX ... DISABLE ---
    uc_rows, _ = run_proc_all_databases(server, password, MDB_UC_TABLE)

    # G-PC4: the constraint really was replaced -- it gets its correct
    # DROP CONSTRAINT. This is what makes the absence assertion meaningful:
    # uq_icg WAS in play as a droppable constraint, the tool just must not ALSO
    # ALTER INDEX it.
    uc_drop = find_rows(uc_rows, database_name=MDB_DATABASE_FIRST,
                        index_name=MDB_UC_CONSTRAINT,
                        script_type="DISABLE CONSTRAINT SCRIPT")
    assert_test("G-MultiDatabase",
                "positive control: %s.%s gets a DISABLE CONSTRAINT SCRIPT"
                % (MDB_DATABASE_FIRST, MDB_UC_CONSTRAINT),
                len(uc_drop) == 1, "found %d" % len(uc_drop))

    # G-PC5: the plain index that replaces it was promoted (Rule 7.5 fired). This
    # is the winner the stale constraint used to get paired against.
    uc_winner = find_rows(uc_rows, database_name=MDB_DATABASE_FIRST,
                          index_name=MDB_UC_PLAIN, script_type="MERGE SCRIPT")
    assert_test("G-MultiDatabase",
                "positive control: %s.%s is the MAKE UNIQUE replacement (Rule 7.5 fired)"
                % (MDB_DATABASE_FIRST, MDB_UC_PLAIN),
                len(uc_winner) == 1, "found %d" % len(uc_winner))

    # G-PC6: CrapB was reached for this table too.
    uc_second = find_rows(uc_rows, database_name=MDB_DATABASE_SECOND)
    assert_test("G-MultiDatabase",
                "positive control: %s was reached for %s (a second iteration happened)"
                % (MDB_DATABASE_SECOND, MDB_UC_TABLE),
                len(uc_second) >= 1,
                "found %d rows for %s" % (len(uc_second), MDB_DATABASE_SECOND))

    # The assertion. A unique CONSTRAINT must never be named by an
    # ALTER INDEX ... DISABLE (a DISABLE SCRIPT row), in any database.
    uc_disable = find_rows(uc_rows, index_name=MDB_UC_CONSTRAINT,
                           script_type="DISABLE SCRIPT")
    assert_test("G-MultiDatabase",
                "no DISABLE SCRIPT names the unique constraint, in any database",
                len(uc_disable) == 0,
                "found %d (ALTER INDEX DISABLE on a UC silently disables inbound FKs) %s"
                % (len(uc_disable),
                   [(r["database_name"], r["script"]) for r in uc_disable]))

    return results


def main():
    server = "SQL2022"
    password = "L!nt0044"

    # Parse args
    args = sys.argv[1:]
    for i, arg in enumerate(args):
        if arg == "--server" and i + 1 < len(args):
            server = args[i + 1]
        elif arg == "--password" and i + 1 < len(args):
            password = args[i + 1]

    print("Running rule coverage tests against %s..." % server)
    print()

    uptime_days = get_uptime_days(server, password)
    print("Server uptime: %d days" % uptime_days)

    if uptime_days > 7:
        print("Uptime is over 7 days, so @dedupe_only stays off and Rule 1 is")
        print("reachable. Asserting that the never-read index is flagged unused.")
    else:
        print("Uptime is 7 days or less, so sp_IndexCleanup auto-enables")
        print("@dedupe_only and Rule 1 cannot run. This is deliberate: usage data")
        print("from a freshly started instance is not worth acting on. Rule 1")
        print("itself is therefore not testable on this instance, so what gets")
        print("asserted instead is THE GUARD -- that @dedupe_only really was")
        print("auto-enabled and that no index is recommended as unused. This is a")
        print("verification, not a skip.")
    print()

    print("Building synthetic fixture in %s..." % TEST_DATABASE)
    stdout, stderr = run_sql_script(server, password, SETUP_SQL)

    # Same check the other harnesses use.
    errors = sql_errors(stdout, stderr)

    if errors:
        print("ERROR: SQL errors during fixture setup:")
        for e in errors:
            print("  " + e)
        print()
        print("The fixture did not build, so the assertions below would be")
        print("testing something other than what they claim.")
        sys.exit(1)

    print("Building multi-database fixture (%s, %s) for Groups F and G..."
          % (MDB_DATABASE_FIRST, MDB_DATABASE_SECOND))
    print()

    # Everything from here down is inside the try. The databases must come off
    # this instance whatever happens next -- a failed assertion, a failed fixture
    # build, or an exception nobody predicted. sys.exit raises SystemExit, so the
    # error path below unwinds through the same finally as a passing run does.
    try:
        stdout, stderr = run_sql_script(server, password, MDB_SETUP_SQL,
                                        database="master")
        errors = sql_errors(stdout, stderr)

        if errors:
            print("ERROR: SQL errors during multi-database fixture setup:")
            for e in errors:
                print("  " + e)
            print()
            print("Group F's fixture did not build, so its assertions of absence")
            print("would pass for the wrong reason.")
            sys.exit(1)

        # Group G's tables ride on the same CrapA/CrapB the block above created.
        stdout, stderr = run_sql_script(server, password, MDB_G_SETUP_SQL,
                                        database="master")
        errors = sql_errors(stdout, stderr)

        if errors:
            print("ERROR: SQL errors during Group G fixture setup:")
            for e in errors:
                print("  " + e)
            print()
            print("Group G's fixture did not build, so its assertions of absence")
            print("would pass for the wrong reason.")
            sys.exit(1)

        results = run_tests(server, password, uptime_days)
    finally:
        run_sql_script(server, password, CLEANUP_SQL)
        run_sql_script(server, password, MDB_CLEANUP_SQL, database="master")

    # Report
    passed = sum(1 for r in results if r["passed"])
    failed = sum(1 for r in results if not r["passed"])

    for r in results:
        status = "PASS" if r["passed"] else "FAIL"
        print("  [%s] %s: %s  (%s)" % (status, r["group"], r["name"], r["detail"]))

    print()
    print("Results: %d passed, %d failed, %d total" % (passed, failed, len(results)))

    if failed > 0:
        print()
        print("FAILED TESTS:")
        for r in results:
            if not r["passed"]:
                print("  %s: %s  (%s)" % (r["group"], r["name"], r["detail"]))
        sys.exit(1)
    else:
        print("All tests passed!")


if __name__ == "__main__":
    main()
