/*
sp_IndexCleanup Test Fixtures - Generate Index Usage
====================================================
Drives reads through each index built by fixtures_dupe_indexes.sql so
sys.dm_db_index_usage_stats has something to report. Without this every index
looks never-used and the usage-based rules and filters have nothing to work on.

Each index gets one read per iteration, so after the default 100 iterations
every hinted index carries ~100 reads and the object total is ~2000. That
matters when testing @min_reads: the object-level screen sums usage across all
indexes on the table, while the index-level screen compares each index on its
own.

IX_Users_Unused and IX_Users_Unused_WithIncludes are deliberately left out so
the unused-index rules have something to find.

Prerequisites: run fixtures_dupe_indexes.sql first.

Runtime: roughly 2 minutes against StackOverflow2013 on a local instance.
*/
USE StackOverflow2013;
GO

DECLARE
    @i integer = 0,
    @c bigint = 0;

WHILE
    @i < 100
BEGIN
    /* Generate reads for IX_Users_Reputation */
    SELECT @c = COUNT_BIG(*)
    FROM dbo.Users WITH (INDEX = IX_Users_Reputation)
    WHERE Reputation > 1000
    OPTION (MAXDOP 1);

    /* Generate reads for IX_Users_Reputation_ASC */
    SELECT @c = COUNT_BIG(*)
    FROM dbo.Users WITH (INDEX = IX_Users_Reputation_ASC)
    WHERE Reputation < 1000
    OPTION (MAXDOP 1);

    /* Generate reads for IX_Users_DisplayName_Reputation */
    SELECT @c = COUNT_BIG(*)
    FROM dbo.Users WITH (INDEX = IX_Users_DisplayName_Reputation)
    WHERE DisplayName LIKE 'A%' AND Reputation > 5000
    OPTION (MAXDOP 1);

    /* Generate reads for IX_Users_DisplayName */
    SELECT @c = COUNT_BIG(*)
    FROM dbo.Users WITH (INDEX = IX_Users_DisplayName)
    WHERE DisplayName LIKE 'B%'
    OPTION (MAXDOP 1);

    /* Generate reads for IX_Users_CreationDate */
    SELECT @c = COUNT_BIG(*)
    FROM dbo.Users WITH (INDEX = IX_Users_CreationDate)
    WHERE CreationDate > '20100101'
    OPTION (MAXDOP 1);

    /* Generate reads for IX_Users_CreationDate_DisplayName */
    SELECT @c = COUNT_BIG(*)
    FROM dbo.Users WITH (INDEX = IX_Users_CreationDate_DisplayName)
    WHERE CreationDate > '20120101'
    OPTION (MAXDOP 1);

    /* Generate reads for UQ_Users_EmailHash */
    SELECT @c = COUNT_BIG(*)
    FROM dbo.Users WITH (INDEX = UQ_Users_EmailHash)
    WHERE EmailHash = 123456
    OPTION (MAXDOP 1);

    /* Generate reads for IX_Users_Reputation_HighRep */
    SELECT @c = COUNT_BIG(*)
    FROM dbo.Users WITH (INDEX = IX_Users_Reputation_HighRep)
    WHERE Reputation > 50000
    OPTION (MAXDOP 1);

    /* Generate reads for IX_Users_Reputation_MediumRep */
    SELECT @c = COUNT_BIG(*)
    FROM dbo.Users WITH (INDEX = IX_Users_Reputation_MediumRep)
    WHERE Reputation = 5000
    OPTION (MAXDOP 1);

    /*
    Generate reads for IX_Users_LastAccessDate. StackOverflow2013 data stops in
    2013, so these later date predicates match nothing - that is fine, the seek
    still registers as a read, which is all this needs.
    */
    SELECT @c = COUNT_BIG(*)
    FROM dbo.Users WITH (INDEX = IX_Users_LastAccessDate)
    WHERE LastAccessDate > '20200101'
    OPTION (MAXDOP 1);

    /* Generate reads for IX_Users_LastAccessDate_Extended */
    SELECT @c = COUNT_BIG(*)
    FROM dbo.Users WITH (INDEX = IX_Users_LastAccessDate_Extended)
    WHERE LastAccessDate > '20210101'
    OPTION (MAXDOP 1);

    /* Generate reads for IX_Users_Location_Age */
    SELECT @c = COUNT_BIG(*)
    FROM dbo.Users WITH (INDEX = IX_Users_Location_Age)
    WHERE Location LIKE '%United States%' AND Age > 30
    OPTION (MAXDOP 1);

    /* Generate reads for IX_Users_AccountId_DisplayName */
    SELECT @c = COUNT_BIG(*)
    FROM dbo.Users WITH (INDEX = IX_Users_AccountId_DisplayName)
    WHERE AccountId = 1234 AND DisplayName LIKE 'C%'
    OPTION (MAXDOP 1);

    /* Generate reads for IX_Users_AccountId_Reputation */
    SELECT @c = COUNT_BIG(*)
    FROM dbo.Users WITH (INDEX = IX_Users_AccountId_Reputation)
    WHERE AccountId = 5678
    OPTION (MAXDOP 1);

    /* Generate reads for IX_Users_Age_Location */
    SELECT @c = COUNT_BIG(*)
    FROM dbo.Users WITH (INDEX = IX_Users_Age_Location)
    WHERE Age > 25 AND Location LIKE 'S%'
    OPTION (MAXDOP 1);

    /* Generate reads for IX_Users_Reputation_CreationDate */
    SELECT @c = COUNT_BIG(*)
    FROM dbo.Users WITH (INDEX = IX_Users_Reputation_CreationDate)
    WHERE Reputation > 5000 AND CreationDate > '20190101'
    OPTION (MAXDOP 1);

    /* Generate reads for IX_Users_LastAccessDate_Full */
    SELECT @c = COUNT_BIG(*)
    FROM dbo.Users WITH (INDEX = IX_Users_LastAccessDate_Full)
    WHERE LastAccessDate > '20230101'
    OPTION (MAXDOP 1);

    /* Generate reads for IX_Users_DisplayName_RepAge */
    SELECT @c = COUNT_BIG(*)
    FROM dbo.Users WITH (INDEX = IX_Users_DisplayName_RepAge)
    WHERE DisplayName LIKE 'D%' AND Age > 40
    OPTION (MAXDOP 1);

    /* Generate reads for IX_Users_Reputation_VeryHighRep */
    SELECT @c = COUNT_BIG(*)
    FROM dbo.Users WITH (INDEX = IX_Users_Reputation_VeryHighRep)
    WHERE Reputation > 75000
    OPTION (MAXDOP 1);

    SELECT @i += 1;

    IF @i % 10 = 0
    BEGIN
        RAISERROR('iteration %d', 0, 0, @i) WITH NOWAIT;
    END;
END;
GO

/* Confirm the indexes actually accumulated usage */
SELECT
    index_name = i.name,
    reads = ius.user_seeks + ius.user_scans + ius.user_lookups,
    writes = ius.user_updates
FROM sys.indexes AS i
LEFT JOIN sys.dm_db_index_usage_stats AS ius
  ON  ius.object_id = i.object_id
  AND ius.index_id = i.index_id
  AND ius.database_id = DB_ID()
WHERE i.object_id = OBJECT_ID(N'dbo.Users')
AND   i.index_id > 1
ORDER BY
    reads DESC;
GO
