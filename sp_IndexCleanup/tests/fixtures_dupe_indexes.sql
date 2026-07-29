/*
sp_IndexCleanup Test Fixtures - Duplicate Indexes on dbo.Users
==============================================================
Builds a broad set of edge-case indexes on the real StackOverflow2013.dbo.Users
table (~2.4 million rows), covering duplicates, subsets, sort directions,
filters, include merges, and never-used indexes.

Unlike adversarial_test.sql, which builds small synthetic test_ic_* tables, this
runs against a real table with real data distribution and real sizes.

Prerequisites:
  - StackOverflow2013 database
  - dbo.DropIndexes helper procedure (drops all nonclustered indexes)

Order:
  1. fixtures_dupe_indexes.sql   <-- you are here
  2. generate_index_reads.sql    (so the indexes have usage stats)
  3. manual_test_runs.sql        (execute sp_IndexCleanup various ways)

WARNING: starts by dropping every nonclustered index on the database via
dbo.DropIndexes. Only run against a scratch copy of StackOverflow2013.
*/
USE StackOverflow2013;
EXECUTE dbo.DropIndexes;
GO

/* Baseline index - this is a good index that should be kept */
CREATE INDEX IX_Users_Reputation
ON dbo.Users (Reputation DESC)
INCLUDE (DisplayName, CreationDate);

/* Exact duplicate of the baseline index - should be identified as redundant */
CREATE INDEX IX_Users_Reputation_Dup
ON dbo.Users (Reputation DESC)
INCLUDE (DisplayName, CreationDate);

/* Subset of the baseline index - should be identified as redundant */
CREATE INDEX IX_Users_Reputation_Subset
ON dbo.Users (Reputation DESC);

/* Same leading column but different sort order - should be kept separate */
CREATE INDEX IX_Users_Reputation_ASC
ON dbo.Users (Reputation ASC)
INCLUDE (DisplayName, CreationDate);

/* Different column order - should be kept separate */
CREATE INDEX IX_Users_DisplayName_Reputation
ON dbo.Users (DisplayName, Reputation);

/* Subset of another index but different sort order - should be kept */
CREATE INDEX IX_Users_DisplayName
ON dbo.Users (DisplayName);

/* Index with overlapping columns - candidate for merging */
CREATE INDEX IX_Users_CreationDate
ON dbo.Users (CreationDate)
INCLUDE (Reputation);

/* Complementary index - candidate for merging */
CREATE INDEX IX_Users_CreationDate_DisplayName
ON dbo.Users (CreationDate)
INCLUDE (DisplayName);

/* Unique constraint index - should be kept */
CREATE UNIQUE INDEX UQ_Users_EmailHash
ON dbo.Users (EmailHash)
WHERE EmailHash IS NOT NULL;

/* Similar to unique index but not unique - should be identified as redundant */
CREATE INDEX IX_Users_EmailHash
ON dbo.Users (EmailHash)
WHERE EmailHash IS NOT NULL;

/* Filtered index - should be kept */
CREATE INDEX IX_Users_Reputation_HighRep
ON dbo.Users (Reputation)
WHERE Reputation > 10000;

/* Filtered index with same column but different filter - should be kept */
CREATE INDEX IX_Users_Reputation_MediumRep
ON dbo.Users (Reputation)
WHERE Reputation >= 1000 AND Reputation <= 10000;

/* Index with included columns that overlap with another index - mergeable */
CREATE INDEX IX_Users_LastAccessDate
ON dbo.Users (LastAccessDate)
INCLUDE (Location, WebsiteUrl);

/* Index with one additional include column - candidate to supersede the above */
CREATE INDEX IX_Users_LastAccessDate_Extended
ON dbo.Users (LastAccessDate)
INCLUDE (Location, WebsiteUrl, Age);

/* Index that will never be used - should be detected as unused */
CREATE INDEX IX_Users_Unused
ON dbo.Users (DownVotes, UpVotes);

/* Another unused index but with includes - should be detected as unused */
CREATE INDEX IX_Users_Unused_WithIncludes
ON dbo.Users (Views)
INCLUDE (AccountId);

/* Index that partially overlaps - might be kept */
CREATE INDEX IX_Users_Location_Age
ON dbo.Users (Location, Age);

/* Composite key index that could be useful - should be kept */
CREATE INDEX IX_Users_AccountId_DisplayName
ON dbo.Users (AccountId, DisplayName);

/* Another candidate for merging */
CREATE INDEX IX_Users_AccountId_Reputation
ON dbo.Users (AccountId)
INCLUDE (Reputation);

/* Same key columns in different order (Rule 7) */
CREATE INDEX IX_Users_Age_Location
ON dbo.Users (Age, Location);

/* Superset key with additional columns compared to IX_Users_Reputation */
CREATE INDEX IX_Users_Reputation_CreationDate
ON dbo.Users (Reputation DESC, CreationDate)
INCLUDE (DisplayName);

/* Similar index with more includes (extended) but without the naming convention */
CREATE INDEX IX_Users_LastAccessDate_Full
ON dbo.Users (LastAccessDate)
INCLUDE (Location, WebsiteUrl, Age, DisplayName, Reputation);

/* Index with exact same columns as IX_Users_DisplayName_Reputation but different order after first */
CREATE INDEX IX_Users_DisplayName_RepAge
ON dbo.Users (DisplayName, Age, Reputation);

/* Index with mismatched filter predicate that's a subset of another */
CREATE INDEX IX_Users_Reputation_VeryHighRep
ON dbo.Users (Reputation)
WHERE Reputation > 50000;

/* Index with mismatched filter predicate that's different */
CREATE INDEX IX_Users_Reputation_Equals_One
ON dbo.Users (Reputation)
WHERE Reputation = 1;
GO
