/*
=============================================================================
sp_IndexCleanup test fixture: a scratch StackOverflow2013 for CI
=============================================================================

Erik's lab boxes already have the real StackOverflow2013 (~2.4M-row Users),
which the harness assumes. The CI containers do not, so this builds a
faithful-schema, synthetic-data stand-in that lets the whole IndexCleanup
suite run anywhere.

What the harness actually needs from this database:

  - run_tests.py       connects here and builds its own test_ic_* tables, so
                       it only needs the database to EXIST.
  - fixture_cases_test needs dbo.Users (exact schema) and dbo.DropIndexes.
  - rule_coverage_test builds its own Crap/CrapA/CrapB databases.
  - no_access_test     creates and drops its own login.

No assertion depends on the row VALUES: reads are forced with WITH (INDEX =)
hints and every rule is structural (dedupe / overlap / usage-floor). The data
only needs the right schema, a unique Id (identity), populated NOT NULL
columns, and enough rows for indexes to carry real pages. EmailHash is left
all-NULL to match the real database, so the filtered EmailHash indexes behave
identically.

This is test infrastructure, not shipped product code. dbo.DropIndexes is
Brent Ozar's helper from the Stack Overflow sample-database tooling, embedded
verbatim so the fixtures drop the same way they do on a real box.

Safe to re-run: it drops and rebuilds StackOverflow2013 from scratch. Do not
point it at a database you care about.
=============================================================================
*/

USE master;
GO

/*
Drop any existing copy first so the fixture is idempotent.
*/
IF DB_ID(N'StackOverflow2013') IS NOT NULL
BEGIN
    ALTER DATABASE StackOverflow2013 SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE StackOverflow2013;
END;
GO

CREATE DATABASE StackOverflow2013;
GO

/*
SIMPLE recovery keeps the log from bloating during the bulk load.
*/
ALTER DATABASE StackOverflow2013 SET RECOVERY SIMPLE;
GO

USE StackOverflow2013;
GO

/*
The Users table, matching the real StackOverflow2013 schema exactly:
column order, types, nullability, and the clustered primary key on Id.
*/
CREATE TABLE
    dbo.Users
(
    Id integer NOT NULL IDENTITY(1, 1),
    AboutMe nvarchar(max) NULL,
    Age integer NULL,
    CreationDate datetime NOT NULL,
    DisplayName nvarchar(40) NOT NULL,
    DownVotes integer NOT NULL,
    EmailHash nvarchar(40) NULL,
    LastAccessDate datetime NOT NULL,
    Location nvarchar(100) NULL,
    Reputation integer NOT NULL,
    UpVotes integer NOT NULL,
    Views integer NOT NULL,
    WebsiteUrl nvarchar(200) NULL,
    AccountId integer NULL,
    CONSTRAINT PK_Users_Id
        PRIMARY KEY CLUSTERED (Id)
);
GO

/*
Populate the table set-based from a tally. Values are deterministic and
varied across the columns the fixtures index and filter on (Reputation spans
the 1000/2000/10000 thresholds, CreationDate spans 2008-2013, DisplayName
varies its first letter for LIKE 'A%'/'B%'). EmailHash stays NULL to match
the real data. AboutMe stays NULL to keep the LOB column lean; the fixtures
only need it to exist as an includable column, not to carry data.

Row count: 500k is a balance -- large enough that every index carries real
pages, small enough that fixture_cases_test's index builds and generated-
script executions stay fast in a container. Tune @row_target if needed.
*/
DECLARE
    @row_target integer = 500000;

WITH
    tally AS
(
    SELECT TOP (@row_target)
        n =
            ROW_NUMBER() OVER
            (
                ORDER BY
                    (SELECT NULL)
            )
    FROM sys.all_columns AS a
    CROSS JOIN sys.all_columns AS b
)
INSERT INTO
    dbo.Users
WITH
    (TABLOCK)
(
    AboutMe,
    Age,
    CreationDate,
    DisplayName,
    DownVotes,
    EmailHash,
    LastAccessDate,
    Location,
    Reputation,
    UpVotes,
    Views,
    WebsiteUrl,
    AccountId
)
SELECT
    AboutMe = CONVERT(nvarchar(max), NULL),
    Age =
        CASE
            WHEN t.n % 7 = 0
            THEN NULL
            ELSE 13 + (t.n % 80)
        END,
    CreationDate = DATEADD(DAY, t.n % 2000, CONVERT(datetime, N'20080731')),
    DisplayName = NCHAR(65 + (t.n % 26)) + N'ser_' + CONVERT(nvarchar(20), t.n),
    DownVotes = t.n % 50,
    EmailHash = CONVERT(nvarchar(40), NULL),
    LastAccessDate = DATEADD(DAY, t.n % 2000, CONVERT(datetime, N'20080801')),
    Location =
        CASE t.n % 5
            WHEN 0 THEN N'New York'
            WHEN 1 THEN N'San Francisco'
            WHEN 2 THEN N'London'
            WHEN 3 THEN NULL
            ELSE N'Seattle'
        END,
    Reputation = 1 + (t.n % 1000000),
    UpVotes = t.n % 200,
    Views = t.n % 1000,
    WebsiteUrl =
        CASE
            WHEN t.n % 3 = 0
            THEN N'https://example.com/' + CONVERT(nvarchar(20), t.n)
            ELSE NULL
        END,
    AccountId = t.n
FROM tally AS t
OPTION(MAXDOP 1);
GO

/*
dbo.DropIndexes -- Brent Ozar's helper from the Stack Overflow sample-database
tooling, embedded verbatim (CREATE changed to CREATE OR ALTER). The fixtures
begin with EXECUTE dbo.DropIndexes to reset to a clean clustered-only Users
between runs. With its defaults it drops nonclustered indexes and unique
constraints but leaves the clustered primary key in place.
*/
CREATE OR ALTER PROCEDURE
    dbo.DropIndexes
(
    @SchemaName sysname = 'dbo',
    @TableName sysname = NULL,
    @WhatToDrop varchar(10) = 'Everything',
    @ExceptIndexNames nvarchar(MAX) = NULL,
    @Debug bit = 'false'
)
  AS
BEGIN
   SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
   SET NOCOUNT ON;
   SET STATISTICS XML OFF;

   CREATE TABLE
       #commands
   (
       ID integer IDENTITY PRIMARY KEY,
       Command nvarchar(4000) NOT NULL
   );
   CREATE TABLE
       #errors
   (
       ID integer IDENTITY PRIMARY KEY,
       Command nvarchar(4000) NOT NULL,
       ErrorMessage nvarchar(4000) NOT NULL
   );

   CREATE TABLE
       #ExceptIndexNames
   (
       IndexName nvarchar(4000) NOT NULL
   );

   INSERT INTO
       #ExceptIndexNames
   (
       IndexName
   )
   SELECT DISTINCT
       IndexName = UPPER(LTRIM(RTRIM(s.value)))
   FROM STRING_SPLIT(@ExceptIndexNames, N',') AS s
   WHERE s.value LIKE N'_%';

   DECLARE
       @CurrentCommand nvarchar(4000);

   IF
   (
     UPPER(@WhatToDrop) LIKE 'C%'
     OR UPPER(@WhatToDrop) LIKE 'E%'
   )
   BEGIN
       INSERT INTO
           #commands
       (
           Command
       )
       SELECT
           N'ALTER TABLE '
           + QUOTENAME(s.name)
           + N'.'
           + QUOTENAME(t.name)
           + N' DROP CONSTRAINT '
           + QUOTENAME(o.name)
           + N';'
       FROM sys.objects AS o
       JOIN sys.schemas AS s
         ON o.schema_id = s.schema_id
       JOIN sys.tables AS t
         ON o.parent_object_id = t.object_id
       WHERE o.type IN (N'C', N'F', N'UQ')
       AND   s.name = ISNULL(@SchemaName, s.name) COLLATE DATABASE_DEFAULT
       AND   t.name = ISNULL(@TableName,  t.name) COLLATE DATABASE_DEFAULT
       AND   UPPER(o.name) NOT IN
             (
                 SELECT
                     e.IndexName COLLATE DATABASE_DEFAULT
                 FROM #ExceptIndexNames AS e
                 WHERE e.IndexName IS NOT NULL
             );
   END;

   IF
   (
     UPPER(@WhatToDrop) LIKE 'I%'
     OR UPPER(@WhatToDrop) LIKE 'E%'
   )
   BEGIN
       INSERT INTO
           #commands
       (
           Command
       )
       SELECT
           N'DROP INDEX '
           + QUOTENAME(i.name)
           + N' ON '
           + QUOTENAME(s.name)
           + N'.'
           + QUOTENAME(t.name)
           + N';'
       FROM sys.tables t
       JOIN sys.schemas AS s
         ON t.schema_id = s.schema_id
       JOIN sys.indexes i
         ON t.object_id = i.object_id
       WHERE i.type NOT IN (0, 1, 5)
       AND   s.name = ISNULL(@SchemaName, s.name) COLLATE DATABASE_DEFAULT
       AND   t.name = ISNULL(@TableName, t.name) COLLATE DATABASE_DEFAULT
       AND   UPPER(i.name) NOT IN
             (
                 SELECT
                     e.IndexName COLLATE DATABASE_DEFAULT
                 FROM #ExceptIndexNames AS e
                 WHERE e.IndexName IS NOT NULL
             );

       INSERT INTO
           #commands
       (
           Command
       )
       SELECT
           N'DROP STATISTICS '
           + QUOTENAME(sc.name)
           + N'.'
           + QUOTENAME(t.name)
           + N'.'
           + QUOTENAME(s.name)
           + N';'
       FROM sys.stats AS s
       JOIN sys.tables AS t
         ON s.object_id = t.object_id
       JOIN sys.schemas AS sc
         ON t.schema_id = sc.schema_id
       WHERE NOT EXISTS
       (
           SELECT
               1/0
           FROM sys.indexes AS i
           WHERE i.name = s.name
       )
       AND sc.name = ISNULL(@SchemaName, s.name)
       AND t.name = ISNULL(@TableName, t.name)
       AND t.name NOT LIKE N'sys%';
   END;
   IF @Debug = 1
   BEGIN
       SELECT
           c.*
       FROM #commands AS c
       ORDER BY
           c.ID;
   END;

   DECLARE
       @result_cursor CURSOR

   SET @result_cursor =
       CURSOR
       LOCAL
       SCROLL
       DYNAMIC
       READ_ONLY
   FOR
   SELECT
       c.Command
   FROM #commands AS c;

   OPEN @result_cursor;

   FETCH FIRST
   FROM @result_cursor
   INTO @CurrentCommand;

   WHILE @@FETCH_STATUS = 0
   BEGIN
       BEGIN TRY
           PRINT @CurrentCommand;

           EXECUTE sys.sp_executesql
               @CurrentCommand;
       END TRY
       BEGIN CATCH
           INSERT
               #errors
           (
               Command,
               ErrorMessage
           )
           VALUES
           (
               @CurrentCommand,
               ERROR_MESSAGE()
           );
       END CATCH

       FETCH NEXT
       FROM @result_cursor
       INTO @CurrentCommand;
   END;
   IF EXISTS
   (
       SELECT
           1/0
       FROM #errors AS e
   )
   BEGIN
       SELECT
           e.ID,
           e.Command,
           e.ErrorMessage
       FROM #errors AS e
       ORDER BY
           e.ID;
   END;
END;
GO
