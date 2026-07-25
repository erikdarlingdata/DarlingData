/*
sp_IndexCleanup Test Fixtures - Unique Constraint and Dedupe Rule Cases
=======================================================================
Builds a numbered set of dedupe cases on the real StackOverflow2013.dbo.Users
table, each annotated with the behavior it is supposed to produce. This is the
higher-value fixture set of the two: it is the only one that covers unique
CONSTRAINTS (cases 7a/7b/7c) alongside unique INDEXES (cases 3 and 5), and that
distinction drives real branches in the procedure.

The "Expected:" comments are the specification. They earn their keep - two of
them caught real bugs that shipped and that neither compiling nor the
adversarial suite noticed:

  - Case 7c: the procedure used to emit a merge into the unique constraint
    (CREATE INDEX ... WITH (DROP_EXISTING = ON) against a constraint-backed
    index, which SQL Server rejects with Msg 1907) while still emitting a
    runnable DISABLE of ix_c3 - losing that index's LastAccessDate include with
    nothing absorbing it.
  - Case 3: the procedure disabled ix_test_5 with uq_test_1 as the target but
    never merged ix_test_5's include into it, silently dropping LastAccessDate
    coverage. Unlike a constraint, a plain unique index does accept
    DROP_EXISTING with an added INCLUDE, so the merge is legal and now happens.

Nothing here asserts automatically. Verifying still means running sp_IndexCleanup
and reading the output against the comments. See README.md.

Prerequisites:
  - StackOverflow2013 database
  - dbo.DropIndexes helper procedure

WARNING: starts by dropping every nonclustered index on the database via
dbo.DropIndexes. Only run against a scratch copy of StackOverflow2013.
*/
USE StackOverflow2013;
GO

EXECUTE dbo.DropIndexes;
GO

/* 1. Exact duplicates, not unique */

/* Test Case 1: Exact duplicates (same keys, same includes) */
CREATE INDEX ix_test_1 ON dbo.Users(DisplayName) INCLUDE(Reputation);
CREATE INDEX ix_test_2 ON dbo.Users(DisplayName) INCLUDE(Reputation);
/* Expected: One index should be kept, other should be disabled */

/* 2. Key duplicates, not unique */

/* Test Case 2: Key duplicates with different includes */
CREATE INDEX ix_test_3 ON dbo.Users(AccountId) INCLUDE(Reputation);
CREATE INDEX ix_test_4 ON dbo.Users(AccountId) INCLUDE(UpVotes);
/* Expected: One index should be kept with includes merged, other should be disabled */

/* 3. Key duplicates, one unique */

/* Test Case 3: Matching key columns, one unique */
CREATE UNIQUE INDEX uq_test_1 ON dbo.Users(Location, Id);
CREATE INDEX ix_test_5 ON dbo.Users(Location, Id) INCLUDE(LastAccessDate);
/* Expected: Unique index should be kept, includes should be merged in */

/* 4. Superset/subset key columns */

/* Test Case 4: Superset/subset keys (not unique) */
CREATE INDEX ix_test_6 ON dbo.Users(Age);
CREATE INDEX ix_test_7 ON dbo.Users(Age, CreationDate);
/* Expected: Wider index (Age, CreationDate) kept, narrower index disabled */

/* 5. Superset/subset with uniqueness */

/* Test Case 5: Superset/subset with unique narrower index */
CREATE UNIQUE INDEX uq_test_2 ON dbo.Users(EmailHash, Id);
CREATE INDEX ix_test_8 ON dbo.Users(EmailHash, Id, WebsiteUrl);
/* Expected: Both kept (unique index should not be combined with wider non-unique index) */

/* 6. Mismatched key orders */

/* Test Case 6: Mismatched key orders */
CREATE INDEX ix_test_9 ON dbo.Users(CreationDate, LastAccessDate, Views);
CREATE INDEX ix_test_10 ON dbo.Users(CreationDate, Views, LastAccessDate);
/*
Expected: Marked as "Same Keys Different Order" for review (Rule 8). This shows
up in the analysis report rows, not as a generated script, so look past the
script output when checking this one.
*/

/* 7. Unique constraint vs. nonclustered index */

/* Test Case 7a: Exact match between unique constraint and nonclustered index */
ALTER TABLE dbo.Users ADD CONSTRAINT uq_test_c1 UNIQUE (DownVotes, Id);
CREATE INDEX ix_c1 ON dbo.Users(DownVotes, Id) INCLUDE(AboutMe);
/* Expected: Constraint disabled, index should be made unique */

/* Test Case 7b: Unique constraint vs. wider nonclustered index (should NOT match) */
ALTER TABLE dbo.Users ADD CONSTRAINT uq_test_c2 UNIQUE (UpVotes, Id);
CREATE INDEX ix_c2 ON dbo.Users(UpVotes, Id, Reputation);
/* Expected: No action - keys don't match exactly */

/* Test Case 7c: Unique constraint wider than nonclustered index (should NOT match) */
ALTER TABLE dbo.Users ADD CONSTRAINT uq_test_c3 UNIQUE (Id, DisplayName);
CREATE INDEX ix_c3 ON dbo.Users(Id) INCLUDE(LastAccessDate);
/* Expected: No action - keys don't match exactly */

/* 8. Testing Edge Cases */

/* Test Case 8a: Filtered indexes */
CREATE INDEX ix_filtered_1 ON dbo.Users(Reputation) WHERE (Reputation > 1000);
CREATE INDEX ix_filtered_2 ON dbo.Users(Reputation) WHERE (Reputation > 1000);
/* Expected: One index kept, one disabled (matching filters) */

/* Test Case 8b: Filtered indexes with different filters (should NOT match) */
CREATE INDEX ix_filtered_3 ON dbo.Users(Reputation) WHERE (Reputation > 2000);
/* Expected: Not matched with the above indexes due to different filter */

/* Test Case 8c: Descending key sort orders */
CREATE INDEX ix_desc_1 ON dbo.Users(Reputation DESC);
CREATE INDEX ix_desc_2 ON dbo.Users(Reputation DESC);
/* Expected: One kept, one disabled (matching sort directions) */

/* Test Case 8d: Different sort directions (should NOT match) */
CREATE INDEX ix_desc_3 ON dbo.Users(Reputation ASC);
/* Expected: Not matched with above indexes due to different sort direction */
GO

/*
Give every fixture index usage so none of them look never-used.

The original working copy of this script drove reads with WHILE 1 = 1 loops meant
to be cancelled by hand. That is fine at a keyboard and a trap in a repository,
so this is bounded. Raise @iterations if a test needs bigger read counts - for
example when exercising @min_reads, which needs indexes on both sides of the
floor to be interesting.
*/
DECLARE
    @c bigint,
    @i integer = 0,
    @iterations integer = 50;

WHILE @i < @iterations
BEGIN
    /* Test Case 1: Exact duplicates */
    SELECT @c = COUNT_BIG(*) FROM dbo.Users AS u WITH (INDEX = ix_test_1) WHERE u.DisplayName LIKE 'A%' OPTION(MAXDOP 1);
    SELECT @c = COUNT_BIG(*) FROM dbo.Users AS u WITH (INDEX = ix_test_2) WHERE u.DisplayName LIKE 'B%' OPTION(MAXDOP 1);

    /* Test Case 2: Key duplicates with different includes */
    SELECT @c = COUNT_BIG(*) FROM dbo.Users AS u WITH (INDEX = ix_test_3) WHERE u.AccountId > 1000 OPTION(MAXDOP 1);
    SELECT @c = COUNT_BIG(*) FROM dbo.Users AS u WITH (INDEX = ix_test_4) WHERE u.AccountId < 5000 OPTION(MAXDOP 1);

    /* Test Case 3: Matching key columns, one unique */
    SELECT @c = COUNT_BIG(*) FROM dbo.Users AS u WITH (INDEX = uq_test_1) WHERE u.Location = 'New York' OPTION(MAXDOP 1);
    SELECT @c = COUNT_BIG(*) FROM dbo.Users AS u WITH (INDEX = ix_test_5) WHERE u.Location LIKE 'San%' OPTION(MAXDOP 1);

    /* Test Case 4: Superset/subset keys */
    SELECT @c = COUNT_BIG(*) FROM dbo.Users AS u WITH (INDEX = ix_test_6) WHERE u.Age = 30 OPTION(MAXDOP 1);
    SELECT @c = COUNT_BIG(*) FROM dbo.Users AS u WITH (INDEX = ix_test_7) WHERE u.Age = 30 AND u.CreationDate > '20100101' OPTION(MAXDOP 1);

    /* Test Case 5: Superset/subset with unique narrower index */
    SELECT @c = COUNT_BIG(*) FROM dbo.Users AS u WITH (INDEX = uq_test_2) WHERE u.EmailHash = 1 OPTION(MAXDOP 1);
    SELECT @c = COUNT_BIG(*) FROM dbo.Users AS u WITH (INDEX = ix_test_8) WHERE u.EmailHash = 2 AND u.WebsiteUrl IS NOT NULL OPTION(MAXDOP 1);

    /* Test Case 6: Mismatched key orders */
    SELECT @c = COUNT_BIG(*) FROM dbo.Users AS u WITH (INDEX = ix_test_9) WHERE u.CreationDate > '20100101' AND u.LastAccessDate < '20200101' OPTION(MAXDOP 1);
    SELECT @c = COUNT_BIG(*) FROM dbo.Users AS u WITH (INDEX = ix_test_10) WHERE u.CreationDate > '20100101' AND u.Views > 1000 OPTION(MAXDOP 1);

    /* Test Case 7a: Unique constraint and its exact-match nonclustered index */
    SELECT @c = COUNT_BIG(*) FROM dbo.Users AS u WITH (INDEX = uq_test_c1) WHERE u.DownVotes = 10 OPTION(MAXDOP 1);
    SELECT @c = COUNT_BIG(*) FROM dbo.Users AS u WITH (INDEX = ix_c1) WHERE u.DownVotes = 20 OPTION(MAXDOP 1);

    /* Test Case 7b: Unique constraint vs. wider nonclustered index */
    SELECT @c = COUNT_BIG(*) FROM dbo.Users AS u WITH (INDEX = uq_test_c2) WHERE u.UpVotes = 100 OPTION(MAXDOP 1);
    SELECT @c = COUNT_BIG(*) FROM dbo.Users AS u WITH (INDEX = ix_c2) WHERE u.UpVotes = 200 AND u.Reputation > 1000 OPTION(MAXDOP 1);

    /* Test Case 7c: Unique constraint wider than nonclustered index */
    SELECT @c = COUNT_BIG(*) FROM dbo.Users AS u WITH (INDEX = uq_test_c3) WHERE u.DisplayName = 'A' OPTION(MAXDOP 1);
    SELECT @c = COUNT_BIG(*) FROM dbo.Users AS u WITH (INDEX = ix_c3) WHERE u.Id = 2 OPTION(MAXDOP 1);

    /* Test Case 8a/8b: Filtered indexes */
    SELECT @c = COUNT_BIG(*) FROM dbo.Users AS u WITH (INDEX = ix_filtered_1) WHERE u.Reputation > 1000 OPTION(MAXDOP 1);
    SELECT @c = COUNT_BIG(*) FROM dbo.Users AS u WITH (INDEX = ix_filtered_2) WHERE u.Reputation > 1000 OPTION(MAXDOP 1);
    SELECT @c = COUNT_BIG(*) FROM dbo.Users AS u WITH (INDEX = ix_filtered_3) WHERE u.Reputation > 2000 OPTION(MAXDOP 1);

    /* Test Case 8c/8d: Sort directions */
    SELECT @c = COUNT_BIG(*) FROM dbo.Users AS u WITH (INDEX = ix_desc_1) OPTION(MAXDOP 1);
    SELECT @c = COUNT_BIG(*) FROM dbo.Users AS u WITH (INDEX = ix_desc_2) OPTION(MAXDOP 1);
    SELECT @c = COUNT_BIG(*) FROM dbo.Users AS u WITH (INDEX = ix_desc_3) OPTION(MAXDOP 1);

    SELECT @i += 1;
END;
GO

/* Now look at what the procedure makes of them */
EXECUTE dbo.sp_IndexCleanup
    @database_name = 'StackOverflow2013',
    @dedupe_only = 1;
GO
