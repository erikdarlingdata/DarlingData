USE StackOverflow2013;
SET NOCOUNT ON;
EXECUTE dbo.DropIndexes;
DBCC FREEPROCCACHE;
ALTER DATABASE StackOverflow2013 
SET COMPATIBILITY_LEVEL = 160;
GO 

/*
Notes for Erik:
 * Start creating the below indexes
 * Set font percentage to 205%
 * Turn on execution plans!
 * Make sure *you're* connected to Wi-Fi
 * Double check VM network is using Wi-Fi

*/

CREATE INDEX
    VoteTypeId_UserId_PostId
ON dbo.Votes
    (VoteTypeId, UserId, PostId)
INCLUDE
    (BountyAmount, CreationDate)
WITH
    (SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);
GO

CREATE INDEX
    Score
ON dbo.Comments
    (Score)
INCLUDE
    (UserId, PostId)
WITH
    (SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);
GO

CREATE INDEX
    UserId
ON dbo.Badges
    (UserId)
WITH
    (SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);
GO

CREATE INDEX
    ParentId
ON dbo.Posts
    (ParentId)
WITH
    (SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);
GO


/*                                                                                                                                                                                                                     
██████╗  █████╗ ██████╗  █████╗ ███╗   ███╗███████╗████████╗███████╗██████╗    
██╔══██╗██╔══██╗██╔══██╗██╔══██╗████╗ ████║██╔════╝╚══██╔══╝██╔════╝██╔══██╗   
██████╔╝███████║██████╔╝███████║██╔████╔██║█████╗     ██║   █████╗  ██████╔╝   
██╔═══╝ ██╔══██║██╔══██╗██╔══██║██║╚██╔╝██║██╔══╝     ██║   ██╔══╝  ██╔══██╗   
██║     ██║  ██║██║  ██║██║  ██║██║ ╚═╝ ██║███████╗   ██║   ███████╗██║  ██║   
╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝   ╚═╝   ╚══════╝╚═╝  ╚═╝   
                                                                               
███████╗███████╗███╗   ██╗███████╗██╗████████╗██╗██╗   ██╗██╗████████╗██╗   ██╗
██╔════╝██╔════╝████╗  ██║██╔════╝██║╚══██╔══╝██║██║   ██║██║╚══██╔══╝╚██╗ ██╔╝
███████╗█████╗  ██╔██╗ ██║███████╗██║   ██║   ██║██║   ██║██║   ██║    ╚████╔╝ 
╚════██║██╔══╝  ██║╚██╗██║╚════██║██║   ██║   ██║╚██╗ ██╔╝██║   ██║     ╚██╔╝  
███████║███████╗██║ ╚████║███████║██║   ██║   ██║ ╚████╔╝ ██║   ██║      ██║   
╚══════╝╚══════╝╚═╝  ╚═══╝╚══════╝╚═╝   ╚═╝   ╚═╝  ╚═══╝  ╚═╝   ╚═╝      ╚═╝   
                                                                               
████████╗██████╗  █████╗ ██╗███╗   ██╗██╗███╗   ██╗ ██████╗                    
╚══██╔══╝██╔══██╗██╔══██╗██║████╗  ██║██║████╗  ██║██╔════╝                    
   ██║   ██████╔╝███████║██║██╔██╗ ██║██║██╔██╗ ██║██║  ███╗                   
   ██║   ██╔══██╗██╔══██║██║██║╚██╗██║██║██║╚██╗██║██║   ██║                   
   ██║   ██║  ██║██║  ██║██║██║ ╚████║██║██║ ╚████║╚██████╔╝                   
   ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝╚═╝╚═╝  ╚═══╝ ╚═════╝                                                                                                        

               Erik Darling                
(Consultare Maximus - Rationabile Pretium)

W: https://erikdarling.com
E: mailto:erik@erikdarling.com
T: https://twitter.com/erikdarlingdata
T: https://www.tiktok.com/@darling.data
L: https://www.linkedin.com/company/darling-data/
Y: https://www.youtube.com/@ErikDarlingData

Demos: 
Database: https://go.erikdarling.com/Stack2013 

*/


/*
Let's start by defining some important terms here:

Parameter Sniffing:
 * When the optimizer uses the value(s) assigned
   to one or more formal parameters for cardinality 
   estimation in order to compile (and cache!) a 
   query's execution plan for reuse in the future.
   
   This is generally a good thing, as it reduces
   plan compilation overhead on busy OLTP systems. 


Parameter Sensitivity:
 * When a cached execution plan involving one or 
   more formal parameter values has far different
   cardinality estimates than the current runtime 
   parameter value(s) would produce, to the point 
   that a different query execution plan would be 
   more appropriate and perform better than current.
   
   This is the problem that we're talking about today.
   

General Performance Issues:
 * When people do all manner of terrible things to
   their SQL Server, and spend all day wondering if 
   it's parameter sniffing, including but not limited 
   to: local variables, table variables, scalar UDFs, 
   multi-statement table valued functions, non-SARGable
   predicates, implicit conversions, XML, JSON, string 
   splitting, any ORM, and poorly conceived tables, 
   columns, and indexes (or lack of indexes, probably),
   and not keeping statistics reasonably up to date.
   
   We also need to separate "sometimes slow" queries 
   that are "sometimes slow" for other reasons, like
   being blocked, reading from disk, and many others.

For example:

*/

CHECKPOINT;
DBCC DROPCLEANBUFFERS;
GO

EXECUTE sys.sp_executesql
    N'
    SELECT
        c = COUNT_BIG(*)
    FROM dbo.Posts AS p
    WHERE p.Score = @Score;
    ',
    N'@Score integer',
    -166;
GO

EXECUTE sys.sp_executesql
    N'
    SELECT
        c = COUNT_BIG(*)
    FROM dbo.Posts AS p
    WHERE p.Score = @Score;
    ',
    N'@Score integer',
    -146;
GO

/*
Query 1:
 * Reads from disk, look at:
   * Operator times?
    * ~6.5 seconds
   * Wait stats?
    * ~40 seconds PAGEIOLATCH_SH

Query 2:
 * Reads from buffer pool!
   * Operator times?
    * ~630ms
   * Wait stats?
    * ~630ms CXSYNC_PORT

Is this sort of performance difference worrying?

Yes, of course.

But it's not parameter sensitivity.
 * There was nothing ill-fitting about the plan
   * Okay there's an obvious missing index but...
 * The only detriment was cached data availability
 * This query really just needs an index

What kind of code is parameter sensitive?
 * Touches tables with skewed data in them, or
   search arguments use some form of range search:
   * >, >=, <, <=, LIKE, IN/NOT IN(list), etc.
 * Uses formal parameters, not local variables
   * Literal values would also qualify if forced
     parameterization is enabled for the database,
     or if simple parameterization is used, but...
 * We're not too concerned with simple parameterization
   * It's for queries that qualify for trivial plans
   * There usually aren't cost-based choices in those

Having choices is really what messes the optimizer up.

*/

SELECT
    c = COUNT_BIG(*)
FROM dbo.Users AS u
WHERE u.Reputation = 2;

SELECT
    c = COUNT_BIG(*)
FROM dbo.Users AS u
WHERE u.Reputation = 1;


/*
The two most common vehicles for parameterized code
in SQL Server are Stored Procedures and queries that
are executed via sp_executesql (dynamic or application).

The main distinction between formal parameters & local 
variables is an important one for our purposes, since 
values assigned to variables are not currently sniffed 
at compile or execution time (without recompiling, yes).

*/ 

/*We've got this index.*/
CREATE INDEX
    ParentId
ON dbo.Posts
    (ParentId)
WITH
    (SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);


/*Sometimes it matters.*/
DECLARE
    @ParentId integer = 0;

SELECT
    s = SUM(p.Score),
    c = COUNT_BIG(*)
FROM dbo.Posts AS p
WHERE p.ParentId = @ParentId;
GO 

/*Sometimes it doesn't.*/
DECLARE
    @ParentId integer = 184618;

SELECT
    s = SUM(p.Score),
    c = COUNT_BIG(*)
FROM dbo.Posts AS p
WHERE p.ParentId = @ParentId;
GO

/*Distribution?*/
SELECT TOP (10)
    p.ParentId,
    Total = FORMAT(COUNT_BIG(*), 'N0')
FROM dbo.Posts AS p
GROUP BY
    p.ParentId
ORDER BY
    COUNT_BIG(*) DESC;
GO


/*Clean up*/
EXECUTE dbo.DropIndexes
    @TableName = N'Posts';

/*
How it works, in great detail:
 * https://go.erikdarling.com/LocalVariables
 
But Why?

What actually happens now:
 * Compile an executable plan faster, but with
   an unknown estimate for the COUNT query that
   uses it in the where clause (cardinality!)
 
What could happen in the future:
 * Defer compilation: Don't compile a plan for the
   COUNT query until the variable has been assigned.
    * Doing this every time: Lots of recompiling
    * Doing this once: Feels like parameter sniffing

The internals are there to do the second option, but 
it has not been exposed to us yet. This does the same 
general thing as table variable deferred compilation.

People historically used local variables to avoid 
sniffing, so T.P.T.B. decided not to break this.

Despite having no problem breaking many other things.

Before we move on, it's worth talking about the thing
everyone always talks about when talking about the 
thing we're talking about: RECOMPILE!

I am very much in favor of the recompile technique.

But there's something people frequently mess up:
 * Where to RECOMPILE
   * Procedure level?
   * Statement level?
   * What's the difference?

*/

CREATE INDEX 
    OwnerUserId_Score
ON dbo.Posts
    (OwnerUserId, Score DESC)
INCLUDE
    (PostTypeId) 
WITH
    (SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);
GO


CREATE OR ALTER PROCEDURE 
    dbo.WhereToRecompile 
(
    @OwnerUserId integer = NULL, 
    @CreationDate datetime = NULL, 
    @PostTypeId integer = NULL,
    @Score integer = NULL
)
WITH 
    RECOMPILE /*This sucks.*/
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
  
    SELECT TOP (5000) 
        p.OwnerUserId,
        p.Score,
        Tags = ISNULL(p.Tags, N'N/A: Question'),
        Title = ISNULL(p.Title, N'N/A: Question'), 
        p.CreationDate, 
        p.LastActivityDate, 
        p.Body
    FROM dbo.Posts AS p
    WHERE (p.OwnerUserId = @OwnerUserId OR @OwnerUserId IS NULL)
    AND   (p.CreationDate >= @CreationDate OR @CreationDate IS NULL)
    AND   (p.PostTypeId = @PostTypeId OR @PostTypeId IS NULL)
    AND   (p.Score >= @Score OR @Score IS NULL)
    ORDER BY 
        p.Score DESC,
        p.Id;

    SELECT TOP (5000) 
        p.OwnerUserId,
        p.Score,
        Tags = ISNULL(p.Tags, N'N/A: Question'),
        Title = ISNULL(p.Title, N'N/A: Question'), 
        p.CreationDate, 
        p.LastActivityDate, 
        p.Body
    FROM dbo.Posts AS p
    WHERE (p.OwnerUserId = @OwnerUserId OR @OwnerUserId IS NULL)
    AND   (p.CreationDate >= @CreationDate OR @CreationDate IS NULL)
    AND   (p.PostTypeId = @PostTypeId OR @PostTypeId IS NULL)
    AND   (p.Score >= @Score OR @Score IS NULL)
    ORDER BY 
        p.Score DESC,
        p.Id
    OPTION(RECOMPILE); /*This doesn't suck.*/
END;
GO 

/*Example executions to get both query plans here.*/
EXECUTE dbo.WhereToRecompile 
    @OwnerUserId = 22656;
GO 

/*Changes.*/
EXECUTE dbo.WhereToRecompile 
    @CreationDate = '20131231'; 
GO

/*
This is the parameter embedding optimization, and it's
only available with statement level recompile. This is an 
important difference, and why procedure level recompiles
(while they do recompile all plans) do not embed values.

SQL Server 2025 has a new feature called OPPO, short for
the Optional Parameter Plan Optimization. I've had mixed
results with it in my testing, but maybe I'm just picky.

We'll see how things go after a few cumulative updates.

It's meant to address code patterns like the one above,
and it uses a similar framework to another feature (PSPO).

*/

/*Show option recompile effect on cached values*/
DECLARE
    @start_date date = 
        CONVERT
        (
            date, 
            SYSDATETIME()
        );

EXECUTE dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @procedure_name = 'WhereToRecompile',
    @query_text_search = 'OPTION(RECOMPILE)',
    @start_date = @start_date;


/*
Let's look at a minor parameter sensitivity example.

What I'm going to show you how to do:
 * Use Query Store to reproduce parameter problems

*/

CREATE INDEX
    DisplayName
ON dbo.Users
   (DisplayName)
WITH
    (SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);
GO

/*Our hero*/
CREATE OR ALTER PROCEDURE
    dbo.DisplayNameSearcher
(
    @DisplayName nvarchar(40)
)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;

    SELECT
        u.Id,
        u.DisplayName,
        TotalScore = SUM(p.Score)
    FROM dbo.Users AS u
    JOIN dbo.Posts AS p
      ON p.OwnerUserId = u.Id
    WHERE u.DisplayName LIKE @DisplayName
    AND   p.Score > 0
    GROUP BY 
        u.Id,
        u.DisplayName
    HAVING
        SUM(p.Score) >= 5000
    ORDER BY
        TotalScore DESC;
END;
GO 


/*Resetter*/
EXECUTE sys.sp_recompile
    @objname = N'dbo.DisplayNameSearcher';

/*John: 15k*/
EXECUTE dbo.DisplayNameSearcher
    @DisplayName = N'John%';

/*User: 595k*/
EXECUTE dbo.DisplayNameSearcher
    @DisplayName = N'User%';

/*bbum: 1*/
EXECUTE dbo.DisplayNameSearcher
    @DisplayName = N'bbum%';

/*Resetter*/
EXECUTE sys.sp_recompile
    @objname = N'dbo.DisplayNameSearcher';

/*User: 595k*/
EXECUTE dbo.DisplayNameSearcher
    @DisplayName = N'User%';

/*John: 15k*/
EXECUTE dbo.DisplayNameSearcher
    @DisplayName = N'John%';

/*bbum: 1*/
EXECUTE dbo.DisplayNameSearcher
    @DisplayName = N'bbum%';


/*
This isn't possible with with plan cache
 * Query Store makes it easy(er)

*/

DECLARE
    @start_date date = 
        CONVERT
        (
            date, 
            SYSDATETIME()
        );

EXECUTE dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @procedure_name = 'DisplayNameSearcher',
    @start_date = @start_date;

/*
Here are some tips:
 1. Use Query Store
 2. Use Query Store
 3. Use Query Store
 4. Don't use the GUI, it's useless
    * Whoever designed it hates people
 5. Use sp_QuickieStore (code.erikdarling.com)
 6. Look for the procedure/query
 7. Look at avg/min/max duration and CPU
 8. Look for different plan_ids for the same query_id
 9. Look at their compile time parameters
10. Don't test the code with local variables
11. Don't test the code with local variables
12. Don't test the code with local variables

*/

DECLARE
    --@DisplayName nvarchar(40) = N'John%'
    @DisplayName nvarchar(40) = N'User%';

SELECT
    u.Id,
    u.DisplayName,
    TotalScore = SUM(p.Score)
FROM dbo.Users AS u
JOIN dbo.Posts AS p
  ON p.OwnerUserId = u.Id
WHERE u.DisplayName LIKE @DisplayName
AND   p.Score > 0
GROUP BY 
    u.Id,
    u.DisplayName
HAVING
    SUM(p.Score) >= 5000
ORDER BY
    TotalScore DESC;
GO 

/*
Getting the same plan for both values isn't helpful.

This isn't sniffing, this is local variable behavior.
The values are just not sniffed at all. Remember that.

Either make a copy of the procedure for testing, a 
temporary stored procedure, or parameterized dynamic
SQL to test things out. Local variables <> Adequate.

*/

CREATE OR ALTER PROCEDURE
    #DisplayNameSearcher
(
    @DisplayName nvarchar(40)
)
AS
BEGIN
    SELECT
        c = COUNT_BIG(*)
    FROM dbo.Users AS u
    WHERE u.DisplayName LIKE @DisplayName;
END;
GO 

EXECUTE #DisplayNameSearcher
    @DisplayName = N'John%';

/*Or...*/

EXECUTE sys.sp_executesql
N'
    SELECT
        c = COUNT_BIG(*)
    FROM dbo.Users AS u
    WHERE u.DisplayName LIKE @DisplayName;
',
N'@DisplayName nvarchar(40)',
N'John%';


/*
Get it done quickly
 * code.erikdarling.com
*/

DECLARE
    @start_date date = 
        CONVERT
        (
            date, 
            SYSDATETIME()
        );

EXECUTE dbo.sp_QueryReproBuilder
    @database_name = 'StackOverflow2013',
    @procedure_name = 'DisplayNameSearcher',
    @start_date = @start_date;


/*Clean Up*/
EXECUTE dbo.DropIndexes
    @TableName = N'Posts';

EXECUTE dbo.DropIndexes
    @TableName = N'Users';


/*
We live in rather funny times for parameter sniffing.
 * SQL Server 2022:
   * Parameter Sensitive Plan Optimization (PSPO)
     * Compatibility Level 160
     * Enterprise Only
     * Equality predicates only
     * Three different plans for row ranges:
         * Unusually common: 3
         * Very uncommon: 1
         * Everything in between: 2
       * Per qualifying parameter (up to 3)
       * Per qualifying table reference (up to 3)
         * That means a total of 27 plan variants
         * If you have 3 qualifying parameters
     * Kicks in ~heuristically~
       * Skewness: is the most common value 100k times 
         more common than the least common value is?
       * 1:100k ratio, so if the least common value
         has 10 rows, most common needs 1 million rows.
       * Many other things
     * No built-in way to force the issue
*/

SELECT 
    mv.map_value 
FROM sys.dm_xe_map_values AS mv
WHERE mv.name = N'psp_skipped_reason_enum' 
ORDER BY 
    mv.map_key;

/*
There are three kinds of queries we still need to fix:
 * Ones where the sensitivity isn't an equality search
   * >, >=, <, <=, LIKE, IN/NOT IN(list), etc.
 * Ones where the feature does not kick in on its own
   * We need to be tricky to change its mind
 * Ones where the feature buckets things poorly
   * No way to control the range buckets


First, inequality predicates:

Here's our stored procedure, which has predicates
on Score and CreationDate. Nothing too crazy here.

*/

/*Already created*/
CREATE INDEX
    Score
ON dbo.Comments
    (Score)
INCLUDE
    (UserId, PostId)
WITH
    (SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);
GO

CREATE OR ALTER PROCEDURE
    dbo.InequalitySniffing
(
    @CreationDate datetime,
    @Score integer
)
AS
BEGIN
    SET XACT_ABORT, NOCOUNT ON;

    SELECT TOP (10000)
        c.*
    FROM dbo.Comments AS c
    WHERE c.Score BETWEEN @Score AND @Score
    AND   c.CreationDate >= @CreationDate
    ORDER BY
        c.Score,
        c.CreationDate,
        c.Id;
END;
GO

/*
This is fast, because both predicates are selective.

But please take note of the predicate in the Lookup.

*/

EXECUTE dbo.InequalitySniffing
    @CreationDate = '20131231',
    @Score = 6;

/*
This is not so fast of course, because many Comments
(rightly) have a Score of zero. Hilarity ensues.

Performance isn't too horrible at ~3.5 seconds, but
you can see the extra time spent in the Seek into
the Clustered index, ~2.9 seconds, and that the Sort 
now spills because the memory grant was insufficient.

*/

EXECUTE dbo.InequalitySniffing
    @CreationDate = '20131231',
    @Score = 0;


/*Create this before proceeding, ~40 seconds*/
CREATE INDEX
    Score_CreationDate
ON dbo.Comments
    (Score, CreationDate)
WITH
    (SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);


/*
The reason why this procedure is parameter-sensitive
is that we don't have one index for both predicates.

Lookups can often be faster than clustered index scans, 
so you shouldn't focus on fixing all of them. Always
get the actual execution plan and validate slow points.

Look at operator times. Do not trust costs. Not even
in Actual Execution Plans. They're still estimates,
and not durable performance metrics. Useless liars.

Predicate lookups are different, because they're a sign 
you have incomplete indexes for what your queries need
to accomplish. These are usually worth noting when doing
execution plan analysis for parameter sensitivity issues.

These are now reasonably fast, even with a Lookup,
because all the filtering is done within one index.

*/

EXECUTE dbo.InequalitySniffing
    @Score = 6,
    @CreationDate = '20131231';

EXECUTE dbo.InequalitySniffing
    @Score = 0,
    @CreationDate = '20131231';
GO


/*
Now we'll look at problems with PSPO.
 * This could have been cool.
 * Instead we got Fabric.

One might think that with a feature name like the
 ~*~*~PARAMETER SENSITIVE PLAN OPTIMIZATION~*~*~
that it would act sanely and rationally in its effort
to optimize parameter sensitive plans. One might 
need reminding that Availability Groups rarely make
things more available. Usually they're less so.

The two main problems we'll look at here:
 * Heuristic weaknesses
 * Poor bucketing practices

*/


/*Just create this*/
CREATE INDEX
    OwnerUserId_PostTypeId
ON dbo.Posts
    (OwnerUserId, PostTypeId)
WHERE
    (PostTypeId = 1)
WITH
    (SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);

/*Already Created*/
CREATE INDEX
    UserId
ON dbo.Badges
    (UserId)
WITH
    (SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);

CREATE INDEX
    VoteTypeId_UserId_PostId
ON dbo.Votes
    (VoteTypeId, UserId, PostId)
INCLUDE
    (BountyAmount, CreationDate)
WITH
    (SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);
GO

/*
This is one of my favorite parameter sensitivity demos.

*/

CREATE OR ALTER PROCEDURE
   dbo.VoteSniffing
(
    @VoteTypeId integer
)
AS
BEGIN
    SET XACT_ABORT, NOCOUNT ON;

    SELECT
        UserId = ISNULL(v.UserId, 0),
        Votes2013 = 
            SUM
            (
                CASE
                    WHEN v.CreationDate >= CONVERT(datetime, '20130101', 112)
                    AND  v.CreationDate <  CONVERT(datetime, '20140101', 112)
                    THEN 1
                    ELSE 0
                END
            ),
        TotalBounty = 
            SUM
            (
                CASE
                    WHEN v.BountyAmount IS NULL
                    THEN 0
                    ELSE 1
                END
            ),
        PostCount = COUNT(DISTINCT v.PostId),
        VoteTypeId = @VoteTypeId
    FROM dbo.Votes AS v
    WHERE v.VoteTypeId = @VoteTypeId
    AND NOT EXISTS
        (
            SELECT
                1/0
            FROM dbo.Posts AS p
            JOIN dbo.Badges AS b
              ON b.UserId = p.OwnerUserId
            WHERE  p.OwnerUserId = v.UserId
            AND    p.PostTypeId = 1
        )
    GROUP BY 
        v.UserId
    ORDER BY
        PostCount DESC;
END;
GO


/*
This seems sensitive to me.
*/

DBCC SHOW_STATISTICS
(
    N'dbo.Votes',
    N'VoteTypeId_UserId_PostId'
)
WITH
    HISTOGRAM;
GO 

/*Oh, right.*/
SELECT
    EQ_ROWS = 
        FORMAT
        (
            CONVERT(bigint, 3.733213E+07),
            'N0'
        );


/*
But because the least frequent value in the histogram
is VoteTypeId 4 at 733 rows, and the most frequent is
VoteTypeId 2 at 37,332,130 rows, we do not meet the
minimum skewness threshold. Sadness ensues, as usual.

Shorter:
  733 * 100,000 = 73,300,000
  and
  73,300,000 > 37,332,130

*/


/*This kinda sucks, going from small to big*/
EXECUTE sys.sp_recompile
    @objname = N'dbo.VoteSniffing';


/*Does fine to start!*/
EXECUTE dbo.VoteSniffing
    @VoteTypeId = 4; 

/*For a little texture. Not bad.*/
EXECUTE dbo.VoteSniffing
    @VoteTypeId = 1; 

/*
Show saved plan, totally eats it.
 * That Batch Mode spill is a mess
 * Microsoft hides BPSORT waits
 * What are they ashamed of here?
 * https://go.erikdarling.com/SlowSortSpills
 * Instead we got Fabric.

*/
EXECUTE dbo.VoteSniffing
    @VoteTypeId = 2; 


/*This really sucks*/
EXECUTE sys.sp_recompile
    @objname = N'dbo.VoteSniffing';


/*Much better start, I think.*/
EXECUTE dbo.VoteSniffing
    @VoteTypeId = 2; 

/*For a little texture. Much better!*/
EXECUTE dbo.VoteSniffing
    @VoteTypeId = 1; 

/*This plan is a total waste.*/
EXECUTE dbo.VoteSniffing
    @VoteTypeId = 4; 
GO

/*
It's not that it's "slow", but it takes around
100ms, when the original plan for 4 took 0ms, 
and used very little resource-wise. This is a big
ol' parallel plan that uses ~3GB for a memory grant.

We can make SQL Server change its mind about this by
adding a dummy row to the votes table! Sketchy, huh?

Now we'll meet the skewness threshold, statistically.

  1 * 100,000 = 100,000
  
  37,332,130 > 100,000

*/

SET IDENTITY_INSERT 
  dbo.Votes ON;

INSERT
    dbo.Votes
(
    Id,
    PostId,
    UserId,
    BountyAmount,
    VoteTypeId,
    CreationDate
)
VALUES
(
    -2147483648,
    -2147483648,
    -2147483648,
    NULL,
    0, /*VoteTypeId*/
    '99991231'
);

SET IDENTITY_INSERT 
  dbo.Votes OFF;


/*This is to avoid anything dumb*/
UPDATE STATISTICS 
    dbo.Votes 
    VoteTypeId_UserId_PostId
WITH
    FULLSCAN;

EXECUTE sys.sp_recompile
    @objname = N'dbo.VoteSniffing';


/*QueryVariantID = 1!*/
EXECUTE dbo.VoteSniffing
    @VoteTypeId = 0; 

/*QueryVariantID = 2!*/
EXECUTE dbo.VoteSniffing
    @VoteTypeId = 4; 

/*QueryVariantID = 3!*/
EXECUTE dbo.VoteSniffing
    @VoteTypeId = 2; 

/*QueryVariantID = ?!*/
EXECUTE dbo.VoteSniffing
    @VoteTypeId = 1; 


/*Unfortunate*/
SELECT
    v.VoteTypeId,
    Total = FORMAT(COUNT_BIG(*), 'N0'),
    QueryVariantId = 
        CASE
            WHEN v.VoteTypeId = 2
            THEN '3: Unusually Common'
            WHEN v.VoteTypeId = 0
            THEN '1: Very Uncommon'
            ELSE '2: Everything Else'
        END
FROM dbo.Votes AS v
GROUP BY
    v.VoteTypeId
ORDER BY
    COUNT_BIG(*) DESC;


/*Remove Dummy*/
DELETE 
    v
FROM dbo.Votes AS v
WHERE v.VoteTypeId = 0
AND   v.CreationDate >= CONVERT(datetime, '99991231', 112);


/*Remove Dummy*/
UPDATE STATISTICS 
    dbo.Votes 
    VoteTypeId_UserId_PostId
WITH
    FULLSCAN;
GO 

/*Dummy Removal Check*/
DBCC SHOW_STATISTICS
(
    N'dbo.Votes',
    N'VoteTypeId_UserId_PostId'
)
WITH
    HISTOGRAM;
GO 

/*
I know what you're thinking here! 

Erik! Query Store! Surely we can just force one of 
these queries to use a different variant. Surely! 

Wrong.

*/

DECLARE
    @start_date date = 
        CONVERT
        (
            date, 
            SYSDATETIME()
        );

EXECUTE dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @only_queries_with_variants = 1,
    @query_text_search = 'UserId = ISNULL(v.UserId, 0)',
    @start_date = @start_date;

/*
Things to note here:
 * Every query has a different query_id
 * We can't force plans across query_ids

*/

EXECUTE sys.sp_query_store_force_plan
    @query_id = NULL,
    @plan_id =  NULL;
GO


/*
We've done a fair bit of character assassination in
our dealings with PSPO. It's not intentional, it's
just me trying to use the feature. But don't worry,
I'm sure it will work great for you! You're special.

Most of the time with parameter sniffing, it's just a
matter of comparing different plan choices, and then
making some query or index adjustment to give the
optimizer fewer choices. After all, it's human like us.

The more choices it has, the more likely it is to make
a bad one that it would regret if it had those feelings.

Some common things to be aware of in sensitive plans:
 * Join type
 * Join order
 * Seek/Scan + Lookup vs Clustered/Table Scan
 * Parallel vs Serial plan
 * Memory grants

For this procedure, we have a rather convenient tactic.

There's one parameter that causes all of our problems, 
and this may be true of procedures you deal with too. 
It might just be less obvious because you have more 
than one parameter. Like I've said, this is a tough 
problem to solve because of all the *stuff* people 
do at once to their queries. But I have faith in you!

We can isolate the parameter sensitive portion of the 
query by sticking it into a #temp table... sometimes. 

More on that in a moment.

*/

CREATE OR ALTER PROCEDURE
    dbo.VoteSniffing
(
    @VoteTypeId int
)
AS
BEGIN
    SET XACT_ABORT, NOCOUNT ON;

    CREATE TABLE
        #votes
    (
        UserId integer NULL UNIQUE CLUSTERED,
        Votes2013 integer NOT NULL,
        TotalBounty integer NOT NULL,
        PostCount integer NOT NULL
    );

    INSERT
        #votes 
    (
        UserId,
        Votes2013,
        TotalBounty,
        PostCount
    )
    SELECT
        UserId = v.UserId,
        Votes2013 = 
           SUM
           (
               CASE
                   WHEN v.CreationDate >= CONVERT(datetime, '20130101', 112)
                   AND  v.CreationDate <  CONVERT(datetime, '20140101', 112)
                   THEN 1
                   ELSE 0
               END
           ),
        TotalBounty = 
            SUM
            (
                CASE
                    WHEN v.BountyAmount IS NULL
                    THEN 0
                    ELSE 1
                END
            ),
        PostCount = COUNT(DISTINCT v.PostId)
    FROM dbo.Votes AS v
    WHERE v.VoteTypeId = @VoteTypeId
    GROUP BY 
        v.UserId;

    SELECT
        UserId = ISNULL(v.UserId, 0),
        v.Votes2013,
        v.TotalBounty,
        v.PostCount,
        VoteTypeId  = @VoteTypeId
    FROM #votes AS v
    WHERE NOT EXISTS
          (
              SELECT
                  1/0
              FROM dbo.Posts AS p
              JOIN dbo.Badges AS b
                ON b.UserId = p.OwnerUserId
              WHERE  p.OwnerUserId = v.UserId
              AND    p.PostTypeId = 1
          )
    ORDER BY 
        v.PostCount DESC;
END;
GO


/*This is fine*/
EXECUTE sys.sp_recompile
    @objname = N'dbo.VoteSniffing';

EXECUTE dbo.VoteSniffing
    @VoteTypeId = 1;

EXECUTE dbo.VoteSniffing
    @VoteTypeId = 4;


/*
Problems this pattern solves:
 * We get stable performance from most executions
 * The parameter sensitive part of the query is fenced off
 * Fewer choices for the second part of the query

Problems this pattern doesn’t solve:
 * Large result sets dumped into temp tables can be bad

*/


/*This is not so great*/
EXECUTE sys.sp_recompile
    @objname = N'dbo.VoteSniffing';

EXECUTE dbo.VoteSniffing
    @VoteTypeId = 2;
GO 

/*
What do we do here?

For an outlier of this size (37 million rows),
we probably don't want to use a #temp table anyway.

That's a pretty big darn #temp table.

A hybrid approach?
 * For VoteTypeId 2, run the regular query
 * For all other VoteTypeIds, use the #temp table
 * Two Stored procedures
  * One executes for VoteTypeId 2
  * One executes for all other VoteTypeIds

*/

CREATE OR ALTER PROCEDURE
    dbo.VoteSniffingOuter
(
    @VoteTypeId integer
)
AS
BEGIN
    SET XACT_ABORT, NOCOUNT ON;

    IF @VoteTypeId = 2
    BEGIN
        EXECUTE dbo.VoteSniffingProcedure
            @VoteTypeId = @VoteTypeId;        
    END;
    
    IF @VoteTypeId <> 2
    BEGIN
        EXECUTE dbo.VoteSniffingTempTable
            @VoteTypeId = @VoteTypeId;        
    END;
END;
GO 


/*A normal procedure call*/
CREATE OR ALTER PROCEDURE
    dbo.VoteSniffingProcedure
(
    @VoteTypeId integer
)
AS
BEGIN
    SET XACT_ABORT, NOCOUNT ON;
    
    SELECT
        UserId = ISNULL(v.UserId, 0),
        Votes2013 = 
            SUM
            (
                CASE
                    WHEN v.CreationDate >= CONVERT(datetime, '20130101', 112)
                    AND  v.CreationDate <  CONVERT(datetime, '20140101', 112)
                    THEN 1
                    ELSE 0
                END
            ),
        TotalBounty = 
            SUM
            (
                CASE
                    WHEN v.BountyAmount IS NULL
                    THEN 0
                    ELSE 1
                END
            ),
        PostCount = COUNT(DISTINCT v.PostId),
        VoteTypeId = @VoteTypeId
    FROM dbo.Votes AS v
    WHERE v.VoteTypeId = @VoteTypeId
    AND NOT EXISTS
        (
            SELECT
                1/0
            FROM dbo.Posts AS p
            JOIN dbo.Badges AS b
              ON b.UserId = p.OwnerUserId
            WHERE p.OwnerUserId = v.UserId
            AND   p.PostTypeId = 1
        )
    GROUP BY 
        v.UserId
    ORDER BY
        PostCount DESC;
END;
GO


/*The temp table from before*/
CREATE OR ALTER PROCEDURE
    dbo.VoteSniffingTempTable
(
    @VoteTypeId integer
)
AS
BEGIN
    SET XACT_ABORT, NOCOUNT ON;

    CREATE TABLE
        #votes
    (
        UserId integer NULL UNIQUE CLUSTERED,
        Votes2013 integer NOT NULL,
        TotalBounty integer NOT NULL,
        PostCount integer NOT NULL
    );

    INSERT
        #votes
    (
        UserId,
        Votes2013,
        TotalBounty,
        PostCount
    )
    SELECT
        UserId = v.UserId,
        Votes2013 =
           SUM
           (
               CASE
                    WHEN v.CreationDate >= CONVERT(datetime, '20130101', 112)
                    AND  v.CreationDate <  CONVERT(datetime, '20140101', 112)
                   THEN 1
                   ELSE 0
               END
           ),
        TotalBounty =
            SUM
            (
                CASE
                    WHEN v.BountyAmount IS NULL
                    THEN 0
                    ELSE 1
                END
            ),
        PostCount = COUNT(DISTINCT v.PostId)
    FROM dbo.Votes AS v
    WHERE v.VoteTypeId = @VoteTypeId
    GROUP BY
        v.UserId;

    SELECT
        UserId = ISNULL(v.UserId, 0),
        v.Votes2013,
        v.TotalBounty,
        v.PostCount,
        VoteTypeId = @VoteTypeId
    FROM #votes AS v
    WHERE NOT EXISTS
          (
              SELECT
                  1/0
              FROM dbo.Posts AS p
              JOIN dbo.Badges AS b
                ON b.UserId = p.OwnerUserId
              WHERE p.OwnerUserId = v.UserId
              AND   p.PostTypeId = 1
          )
    ORDER BY
        v.PostCount DESC;
END;
GO


/*This is fine*/
EXECUTE sys.sp_recompile
    @objname = N'dbo.VoteSniffingOuter';

EXECUTE dbo.VoteSniffingOuter
    @VoteTypeId = 1;

EXECUTE dbo.VoteSniffingOuter
    @VoteTypeId = 4;

/*Now this is fine, too*/
EXECUTE dbo.VoteSniffingOuter
    @VoteTypeId = 2;
GO


/*
We have a somewhat creative solution here that gets
us good performance across the outliers in our data:
 * Very big, PostTypeId 2
 * Relatively big, PostTypeId 1
 * Very small, PostTypeId 4

There are even more things you can do with dynamic SQL.
 * It's like PSPO, but you control:
   * The bucketing
   * Hints applied
   * Indexes used
   * And more!

The deeper you get into parameter sensitivity problems,
the more often you'll lean on dynamic SQL (usually).

You may also learn to lean on OPTION(RECOMPILE) often.

*/

DECLARE
    @VoteTypeId integer = NULL,
    @sql nvarchar(max) = N'
SELECT
    c = COUNT_BIG(*)
FROM dbo.Votes AS v
WHERE v.VoteTypeId = @VoteTypeId';

IF @VoteTypeId IN (1, 3, 5, 6, 10, 16)
BEGIN
    SELECT
        @sql + N'
AND  1 = (SELECT 1);';
END;

IF @VoteTypeId = 2
BEGIN
    SELECT
        @sql + N'
AND  2 = (SELECT 2);';
END;

IF @VoteTypeId IN (4, 7, 8, 9, 11, 12, 15)
BEGIN
    SELECT
        @sql + N'
AND  3 = (SELECT 3);';
END;
GO


/*Add in different hints depending on values*/
DECLARE
    @VoteTypeId integer = NULL,
    @sql nvarchar(max) = N'
SELECT
    c = COUNT_BIG(*)
FROM dbo.Votes AS v
JOIN dbo.Posts AS p
  ON p.Id = v.PostId
WHERE v.VoteTypeId = @VoteTypeId';

IF @VoteTypeId IN (1, 3, 5, 6, 10, 16)
BEGIN
    SELECT
        @sql + N'
OPTON(MERGE JOIN);';
END;

IF @VoteTypeId = 2
BEGIN
    SELECT
        @sql + N'
OPTION(HASH JOIN);';
END;

IF @VoteTypeId IN (4, 7, 8, 9, 11, 12, 15)
BEGIN
    SELECT
        @sql + N'
OPTION(LOOP JOIN);';
END;
GO


/*Optimize for bucketized or even specific values*/
DECLARE
    @VoteTypeId integer = NULL,
    @sql nvarchar(max) = N'
SELECT
    c = COUNT_BIG(*)
FROM dbo.Votes AS v
WHERE v.VoteTypeId = @VoteTypeId';

IF @VoteTypeId IN (1, 3, 5, 6, 10, 16)
BEGIN
    SELECT
        @sql + N'
OPTION
(
    OPTIMIZE FOR 
    (
        @VoteTypeId = 1
    )
);';
END;

IF @VoteTypeId = 2
BEGIN
    SELECT
        @sql + N'
OPTION
(
    OPTIMIZE FOR 
    (
        @VoteTypeId = 2
    )
);';
END;

IF @VoteTypeId IN (4, 7, 8, 9, 11, 12, 15)
BEGIN
    SELECT
        @sql + N'
OPTION
(
    OPTIMIZE FOR 
    (
        @VoteTypeId = 15
    )
);';
END;
GO

/*Plan per value?*/
DECLARE
    @VoteTypeId integer = NULL,
    @sql nvarchar(max) = N'
SELECT
    c = COUNT_BIG(*)
FROM dbo.Votes AS v
WHERE v.VoteTypeId = @VoteTypeId
OPTION
(
    OPTIMIZE FOR 
    (
        @VoteTypeId = {@VoteTypeId}
    )
);';

SELECT
    @sql =
    REPLACE
    (
        @sql,
     N'{@VoteTypeId}',
        @VoteTypeId
    );
GO


/*Wider date ranges?*/
DECLARE
    @StartDate datetime = NULL,
    @EndDate datetime = NULL,
    @sql nvarchar(max) = N'
SELECT
    c = COUNT_BIG(*)
FROM dbo.Votes AS v
WHERE v.CreationDate >= @StartDate
AND   v.CreationDate <  @EndDate';

IF DATEDIFF
(
    MONTH,
    @StartDate,
    @EndDate
) >= 3
BEGIN
    SELECT
        @sql + N'
OPTION(RECOMPILE);';
END;


/*
Dynamic SQL is your friend.
 * Make sure it's parameterized
 * Make sure objects use QUOTENAME()
 * Make sure it's formatted nicely
 * Make sure you add a comment with the
   module name that creates/runs the query
   so that you know where it comes from.

*/


/*
████████╗██╗  ██╗ █████╗ ███╗   ██╗██╗  ██╗
╚══██╔══╝██║  ██║██╔══██╗████╗  ██║██║ ██╔╝
   ██║   ███████║███████║██╔██╗ ██║█████╔╝
   ██║   ██╔══██║██╔══██║██║╚██╗██║██╔═██╗
   ██║   ██║  ██║██║  ██║██║ ╚████║██║  ██╗
   ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝
                                          
██╗   ██╗ ██████╗ ██╗   ██╗██╗            
╚██╗ ██╔╝██╔═══██╗██║   ██║██║            
 ╚████╔╝ ██║   ██║██║   ██║██║            
  ╚██╔╝  ██║   ██║██║   ██║╚═╝            
   ██║   ╚██████╔╝╚██████╔╝██╗            
   ╚═╝    ╚═════╝  ╚═════╝ ╚═╝

               Erik Darling                
(Consultare Maximus - Rationabile Pretium)
                                          
W: https://erikdarling.com
E: mailto:erik@erikdarling.com
T: https://twitter.com/erikdarlingdata
T: https://www.tiktok.com/@darling.data
L: https://www.linkedin.com/company/darling-data/
Y: https://www.youtube.com/@ErikDarlingData

*/
