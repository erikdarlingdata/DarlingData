/*
MIT License

Copyright (c) 2024 Darling Data, LLC

https://www.erikdarling.com/

For support, head over to GitHub:
https://github.com/erikdarlingdata/DarlingData


Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/


/*

Example executions

EXEC dbo.make_big_stack_cs
    @loops = 25,
    @truncate_tables = 1,
    @count_when_done = 1,
    @rebuild_when_done = 1;

EXEC dbo.make_big_stack_cs
    @loops = 25,
    @truncate_tables = 0,
    @count_when_done = 1,
    @rebuild_when_done = 1;

*/


/*Assumes this database exists and has the right tables in it.*/
USE StackOverflowCS;
/*Just to be sure*/
ALTER DATABASE
    StackOverflowCS
SET RECOVERY SIMPLE;
GO

/*Creating a temporary proc for now*/
CREATE OR ALTER PROCEDURE
    dbo.make_big_stack_cs
(
   @loops int = 1,
   @truncate_tables bit = 1,
   @rebuild_when_done bit = 1,
   @count_when_done bit = 1
)
AS
BEGIN
SET NOCOUNT ON;

DECLARE
    @i int = 1, --Loop counter
    @umaxid bigint = 0, --Max Id in Users
    @bmaxid bigint = 0, --Max Id in Badges
    @cmaxid bigint = 0, --Max Id in Comments
    @pmaxid bigint = 0, --Max Id in Posts
    @vmaxid bigint = 0, --Max Id in Votes
    @msg nvarchar(2000) = N'', --For RAISERROR
    @starttime datetime = 1, --Timing things
    @rc nvarchar(20) = N'', --Row counts
    @loopstart datetime= 1, --Timing loops
    @loopsec nvarchar(20) = N'', --Loop time as a string for RAISERROR
    @looprows bigint = 0, --Numbers of rows per loop total
    @looprowsmsg nvarchar(20) = N''; --Numbers of rows per loop total as a string for RAISERROR

IF @truncate_tables = 1
BEGIN
    RAISERROR('Truncating tables', 0, 1) WITH NOWAIT;
    TRUNCATE TABLE StackOverflowCS.dbo.Badges;
    TRUNCATE TABLE StackOverflowCS.dbo.Comments;
    TRUNCATE TABLE StackOverflowCS.dbo.Posts;
    TRUNCATE TABLE StackOverflowCS.dbo.Users;
    TRUNCATE TABLE StackOverflowCS.dbo.Votes;
END;

WHILE @i <= @loops
    BEGIN
        SET @loopstart = SYSDATETIME();

        IF
        (
            @i > 1
         OR @truncate_tables = 0
        )--If we're not truncating first, we should check base tables
        BEGIN
            RAISERROR('Getting new max Ids...', 0, 1) WITH NOWAIT;

            SELECT
                @umaxid = ISNULL(MAX(u.Id) + 2, 0)
            /*Need to offset because there's a -1 in Id*/
            /*If the table is empty it doesn't matter because MAX returns a NULL*/
            FROM StackOverflowCS.dbo.Users AS u;

            SELECT
                @bmaxid = ISNULL(MAX(b.Id), 0)
            FROM StackOverflowCS.dbo.Badges AS b;

            SELECT
                @cmaxid = ISNULL(MAX(c.Id), 0)
            FROM StackOverflowCS.dbo.Comments AS c;

            SELECT
                @pmaxid = ISNULL(MAX(p.Id), 0)
            FROM StackOverflowCS.dbo.Posts AS p;

            SELECT
                @vmaxid = ISNULL(MAX(v.Id), 0)
            FROM StackOverflowCS.dbo.Votes AS v;
        END;

        RAISERROR('Inserting to Users...', 0, 1) WITH NOWAIT;
        SET @starttime = SYSDATETIME();

        INSERT
            StackOverflowCS.dbo.Users WITH (TABLOCKX)
        (
            Id, Age, CreationDate, DisplayName, DownVotes, EmailHash, LastAccessDate,
            Location, Reputation, UpVotes, Views, WebsiteUrl, AccountId
        )
        SELECT
            u.Id + @umaxid, u.Age, u.CreationDate, u.DisplayName, u.DownVotes, u.EmailHash, u.LastAccessDate,
            u.Location, u.Reputation, u.UpVotes, u.Views, u.WebsiteUrl, u.AccountId + @umaxid
        FROM StackOverflow.dbo.Users AS u;

        SET @rc = @@ROWCOUNT;
        SET @looprows += @rc;

        SELECT @msg = DATEDIFF(SECOND, @starttime, SYSDATETIME());
        RAISERROR('Inserting to %s rows to Users took %s seconds', 0, 1, @rc, @msg) WITH NOWAIT;

        CHECKPOINT;

        RAISERROR('Inserting to Posts...', 0, 1) WITH NOWAIT;
        SET @starttime = SYSDATETIME();

        INSERT
            StackOverflowCS.dbo.Posts WITH (TABLOCKX)
        (
            Id, AcceptedAnswerId, AnswerCount, ClosedDate, CommentCount, CommunityOwnedDate,
            CreationDate, FavoriteCount, LastActivityDate, LastEditDate, LastEditorDisplayName,
            LastEditorUserId, OwnerUserId, ParentId, PostTypeId, Score, Tags, ViewCount
        )
        SELECT
            p.Id + @pmaxid, p.AcceptedAnswerId + @pmaxid, p.AnswerCount, p.ClosedDate, p.CommentCount, p.CommunityOwnedDate,
            p.CreationDate, p.FavoriteCount, p.LastActivityDate, p.LastEditDate, p.LastEditorDisplayName,
            p.LastEditorUserId + @umaxid, p.OwnerUserId + @umaxid, p.ParentId + @pmaxid, p.PostTypeId, p.Score, p.Tags, p.ViewCount
        FROM StackOverflow.dbo.Posts AS p;

        SET @rc = @@ROWCOUNT;
        SET @looprows += @rc;

        SELECT @msg = DATEDIFF(SECOND, @starttime, SYSDATETIME());
        RAISERROR('Inserting to %s rows to Posts took %s seconds', 0, 1, @rc, @msg) WITH NOWAIT;

        CHECKPOINT;

        RAISERROR('Inserting to Badges...', 0, 1) WITH NOWAIT;
        SET @starttime = SYSDATETIME();

        INSERT
            StackOverflowCS.dbo.Badges WITH (TABLOCKX)
        (
            Id, Name, UserId, Date
        )
        SELECT
            b.Id + @bmaxid, b.Name, b.UserId + @umaxid, b.Date
        FROM StackOverflow.dbo.Badges AS b;

        SET @rc = @@ROWCOUNT;
        SET @looprows += @rc;

        SELECT @msg = DATEDIFF(SECOND, @starttime, SYSDATETIME());
        RAISERROR('Inserting to %s rows to Badges took %s seconds', 0, 1, @rc, @msg) WITH NOWAIT;

        CHECKPOINT;

        RAISERROR('Inserting to Comments...', 0, 1) WITH NOWAIT;
        SET @starttime = SYSDATETIME();

        INSERT
            StackOverflowCS.dbo.Comments WITH (TABLOCKX)
        (
            Id, CreationDate, PostId, Score, UserId
        )
        SELECT
            c.Id + @cmaxid, c.CreationDate, c.PostId + @pmaxid, c.Score, c.UserId + @umaxid
        FROM StackOverflow.dbo.Comments AS c;

        SET @rc = @@ROWCOUNT;
        SET @looprows += @rc;

        SELECT @msg = DATEDIFF(SECOND, @starttime, SYSDATETIME());
        RAISERROR('Inserting to %s rows to Comments took %s seconds', 0, 1, @rc, @msg) WITH NOWAIT;

        CHECKPOINT;

        RAISERROR('Inserting to Votes...', 0, 1) WITH NOWAIT;
        SET @starttime = SYSDATETIME();

        INSERT
            StackOverflowCS.dbo.Votes WITH (TABLOCKX)
        (
            Id, PostId, UserId, BountyAmount, VoteTypeId, CreationDate
        )
        SELECT
            v.Id + @vmaxid, v.PostId + @pmaxid, v.UserId + @umaxid,
            v.BountyAmount, v.VoteTypeId, v.CreationDate
        FROM StackOverflow.dbo.Votes AS v;

        SET @rc = @@ROWCOUNT;
        SET @looprows += @rc;

        SELECT @msg = DATEDIFF(SECOND, @starttime, SYSDATETIME());
        RAISERROR('Inserting to %s rows to Votes took %s seconds', 0, 1, @rc, @msg) WITH NOWAIT;

        CHECKPOINT;

        SET @msg = RTRIM(@i);
        SET @loopsec = DATEDIFF(SECOND, @loopstart, SYSDATETIME());
        SET @looprowsmsg = @looprows;
        RAISERROR('Loop #%s done in %s seconds, %s total rows inserted', 0, 1, @msg, @loopsec, @looprowsmsg) WITH NOWAIT;
        SET @i += 1;
        SET @looprows = 0;

        RAISERROR('Resetting loop....', 0, 1) WITH NOWAIT;

    END;

    RAISERROR('Checking for incorrect VoteTypeId and PostTypeId rows', 0, 1) WITH NOWAIT;
    IF EXISTS
    (
        SELECT
            1/0
        FROM StackOverflowCS.dbo.Posts AS p
        JOIN StackOverflowCS.dbo.Votes AS v
          ON  p.Id = v.PostId
        WHERE v.VoteTypeId = 1
        AND   p.PostTypeId = 1
    )
    BEGIN
        RAISERROR('Found incorrect VoteTypeId and PostTypeId rows', 0, 1) WITH NOWAIT;

        SELECT
            v.Id
        INTO #t
        FROM StackOverflowCS.dbo.Posts AS p
        JOIN StackOverflowCS.dbo.Votes AS v
          ON  p.Id = v.PostId
        WHERE v.VoteTypeId = 1
        AND   p.PostTypeId = 1;

        DELETE v
        FROM StackOverflowCS.dbo.Votes AS v
        WHERE EXISTS
        (
            SELECT
                1/0
            FROM #t AS t
            WHERE t.Id = v.Id
        );

        DROP TABLE #t;
    END;

/*Rebuilding indexes after we're done to make sure everything is fully compressed*/
IF @rebuild_when_done = 1
BEGIN
    RAISERROR('Rebuilding Badges...', 0, 1) WITH NOWAIT;
    SET @starttime = SYSDATETIME();

        ALTER INDEX ccsi_Badges ON StackOverflowCS.dbo.Badges REBUILD;
        CHECKPOINT;

    SELECT @msg = DATEDIFF(SECOND, @starttime, SYSDATETIME());
    RAISERROR('Rebuilding Badges took %s seconds', 0, 1, @msg) WITH NOWAIT;

    RAISERROR('Rebuilding Comments...', 0, 1) WITH NOWAIT;
    SET @starttime = SYSDATETIME();

        ALTER INDEX ccsi_Comments ON StackOverflowCS.dbo.Comments REBUILD;
        CHECKPOINT;

    SELECT @msg = DATEDIFF(SECOND, @starttime, SYSDATETIME());
    RAISERROR('Rebuilding Comments took %s seconds', 0, 1, @msg) WITH NOWAIT;

    RAISERROR('Rebuilding Posts...', 0, 1) WITH NOWAIT;
    SET @starttime = SYSDATETIME();

        ALTER INDEX ccsi_Posts ON StackOverflowCS.dbo.Posts REBUILD;
        CHECKPOINT;

    SELECT @msg = DATEDIFF(SECOND, @starttime, SYSDATETIME());
    RAISERROR('Rebuilding Posts took %s seconds', 0, 1, @msg) WITH NOWAIT;

    RAISERROR('Rebuilding Users...', 0, 1) WITH NOWAIT;
    SET @starttime = SYSDATETIME();

        ALTER INDEX ccsi_Users ON StackOverflowCS.dbo.Users REBUILD;
        CHECKPOINT;

    SELECT @msg = DATEDIFF(SECOND, @starttime, SYSDATETIME());
    RAISERROR('Rebuilding Users took %s seconds', 0, 1, @msg) WITH NOWAIT;

    RAISERROR('Rebuilding Votes...', 0, 1) WITH NOWAIT;
    SET @starttime = SYSDATETIME();

        ALTER INDEX ccsi_Votes ON StackOverflowCS.dbo.Votes REBUILD;
        CHECKPOINT;

    SELECT @msg = DATEDIFF(SECOND, @starttime, SYSDATETIME());
    RAISERROR('Rebuilding Votes took %s seconds', 0, 1, @msg) WITH NOWAIT;
END;

IF @count_when_done = 1
BEGIN
    RAISERROR('Getting counts!', 0, 1, @msg) WITH NOWAIT;
    SELECT FORMAT(COUNT_BIG(*), 'N0') AS badges_count FROM StackOverflowCS.dbo.Badges AS bc;
    SELECT FORMAT(COUNT_BIG(*), 'N0') AS comments_count FROM StackOverflowCS.dbo.Comments AS cc;
    SELECT FORMAT(COUNT_BIG(*), 'N0') AS posts_count FROM StackOverflowCS.dbo.Posts AS pc;
    SELECT FORMAT(COUNT_BIG(*), 'N0') AS users_count FROM StackOverflowCS.dbo.Users AS uc;
    SELECT FORMAT(COUNT_BIG(*), 'N0') AS votes_count FROM StackOverflowCS.dbo.Votes AS vc;
END;

END;
GO