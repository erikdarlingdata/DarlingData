USE StackOverflow2013;
EXECUTE dbo.DropIndexes;
ALTER DATABASE StackOverflow2013
SET COMPATIBILITY_LEVEL = 160;
SET NOCOUNT ON;
DBCC FREEPROCCACHE;
GO

DROP TABLE IF EXISTS
    dbo.HighRepUsers;

/*Preamble*/
SELECT
    u.Id,
    u.DisplayName,
    u.LastAccessDate,
    u.Reputation
INTO dbo.HighRepUsers
FROM dbo.Users AS u
WHERE u.Reputation >= 100000;
GO

ALTER TABLE
    dbo.HighRepUsers
ADD CONSTRAINT
    PK_HighRepUsers
PRIMARY KEY CLUSTERED
    (Id)
WITH
    (SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);
GO

CREATE INDEX
    [DisplayName, Reputation]
ON dbo.HighRepUsers
    (DisplayName, Reputation)
WITH
    (SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);
GO

CREATE INDEX
    [UserId]
ON dbo.Badges
    (UserId)
WITH
    (SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);
GO

CREATE INDEX
    [OwnerUserId, LastActivityDate]
ON dbo.Posts
    (OwnerUserId, LastActivityDate)
INCLUDE
    (Score)
WITH
    (SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);
GO

CREATE INDEX
    [OwnerUserId, Score]
ON dbo.Posts
    (OwnerUserId, Score)
INCLUDE
    (PostTypeId)
WHERE
    (PostTypeId = 2)
WITH
    (SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);
GO

CREATE INDEX
    [CreationDate, Reputation, Id]
ON dbo.Users
    (CreationDate, Reputation, Id)
INCLUDE
    (DisplayName)
WITH
    (SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);
GO

CREATE INDEX
    [PostId, Score]
ON dbo.Comments
    (PostId, Score)
WITH
    (SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);
GO

CREATE INDEX
    [VoteTypeId, PostId]
ON dbo.Votes
    (VoteTypeId, PostId)
WITH
    (SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);
GO

CREATE INDEX
    [PostTypeId]
ON dbo.Posts
    (PostTypeId)
WHERE
    (PostTypeId = 1)
WITH
    (SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);


/*
██████╗  ██████╗ ██╗    ██╗
██╔══██╗██╔═══██╗██║    ██║
██████╔╝██║   ██║██║ █╗ ██║
██╔══██╗██║   ██║██║███╗██║
██║  ██║╚██████╔╝╚███╔███╔╝
╚═╝  ╚═╝ ╚═════╝  ╚══╝╚══╝

 ██████╗  ██████╗  █████╗ ██╗     ███████╗
██╔════╝ ██╔═══██╗██╔══██╗██║     ██╔════╝
██║  ███╗██║   ██║███████║██║     ███████╗
██║   ██║██║   ██║██╔══██║██║     ╚════██║
╚██████╔╝╚██████╔╝██║  ██║███████╗███████║
 ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚══════╝╚══════╝

I'm Erik!
(Consultare Maximus - Rationabile Pretium)

W: https://erikdarling.com
E: mailto:erik@erikdarling.com
T: https://twitter.com/erikdarlingdata
T: https://www.tiktok.com/@darling.data
L: https://www.linkedin.com/company/darling-data/
Y: https://www.youtube.com/@ErikDarlingData

Demos: https://go.erikdarling.com/RowGoals
Database: https://go.erikdarling.com/Stack2013

*/


/*
Row goals come in two forms:
 * Ones that you *may* introduce
  * Commonly with TOP, OFFSET/FETCH, or FAST n
 * Ones that the optimizer introduces
  * Commonly with (NOT*) EXISTS or IN clauses
      *Sometimes, sometimes NOT, ha ha ha

A row goal is a bit of a short circuit for the
optimizer, because rather than coming up with a
plan to process and return all rows, it can come
up with a plan that's more well-suited to meet
the row goal, which is usually fewer rows.

You can also think of a row goal as a promise
that only N number of rows will be produced, or that
you'll run out of rows to produce. Because of that,
row goals can also act as optimization fences
when used in table expressions (derived or common)
to "force" the optimizer towards to a preferred
execution plan shape. They give you some control.

It's important to establish the difference between
a row goal and a row limit early on. The terms may
feel interchangeable, but consider first that many
SQL dialects use the LIMIT keyword instead of the
TOP keyword. There's also an important distinction
between *you* limiting rows to a certain number,
like "I only want the first 100 rows" and the
optimizer setting a row goal like "I only need to
find one matching row", for example...


/*You, with a row limit*/
SELECT TOP (100)
    e.columns
FROM dbo.Example AS e
ORDER BY
    e.a_column;


/*You, with a row goal*/
SELECT
    e.columns
FROM dbo.Example AS e
ORDER BY
    e.a_column
OPTION(FAST 1);


/*The optimizer, with a row goal*/
SELECT
    e.*
FROM dbo.Example AS e
WHERE EXISTS
(
    SELECT
        1/0
    FROM dbo.AnotherExample AS a
    WHERE a.a_column = e.a_column
);


Query optimization is largely driven by how many
rows are expected to come from tables, survive
where and join clauses, or get past group by clauses.
and row goals are a way to influence optimization
choices without query or table hints being used,
because the number of estimated rows has a huge
impact on SQL Server's cost-based optimizer.

A slight digression...

What are query costs?
 * Estimates! Nothing but estimates!

Cost does not equal time, measure speed or efficiency,
or anything else useful. They are unitless metrics.
 * Even in actual execution plans costs are all estimates
 * There are no *actual* equivalents for costs derived
   *after* queries execute like other metrics

*/

SELECT DISTINCT TOP (10)
    u.Reputation
FROM dbo.Users AS u
ORDER BY
    u.Reputation DESC;

/*
Costs are only how we *got* the plan we're looking at.
 * The optimizer costed and compared choices, and
   you got the cheapest combination of operators.
 * If you're looking at a slow query, there's a good
   chance those costs were incorrect for your query

You tell SQL Server:
 * Which tables you want (from/join)
 * Which rows you want (where/on)
 * Which columns you want (select)
 * Which columns to summarize (group by)
 * Which order you want them in (order by)

*/

SELECT TOP (100)
    a.company_name,
    a.contact_name,
    a.email_address,
    a.consulting_budget
FROM dbo.Attendees AS a
WHERE a.consulting_budget >= $.99
ORDER BY
    a.consulting_budget DESC;

/*
Queries are just descriptions of what you *want* to see.
The optimizer figures out *how* best-enough to do it.

Sort of like how indexes contain data and statistics
describe data. Databases contain data, and we describe
what data we want to see from them with our queries.

Costs are based on a bunch of internal algorithms that
SQL Server uses to shape and choose execution plans for
queries, in the hopes that those costing mechanisms are
correct-enough and have correct-enough information to
get you a good-enough plan to answer the question your
query is asking quickly and efficiently.

Costing considers:
 * Rows
   * Cardinality Estimates from where/join, grouping...
   * Data distribution from statistics histograms
 * I/O type
   * Random I/O like Key Lookups/Loops is costed higher
     than sequential I/O like scans
   * Random I/O costs scale back when you perform many
     of them. This reflects the fact that previous random
     fetches *might* have already brought in the currently
     needed page. The more random I/O you perform, the
     higher this chance becomes.
 * CPU effort
   * Parallelism may reduce costs overall
 * Memory requirements
   * Buffer Pool, row sizes, etc.

Cost is generalized
 * Based on one very old piece of hardware, not your
   *specific* hardware setup
 * https://go.erikdarling.com/Nick
 * Meant to come up with good-enough plans on *any*
   set of hardware, not just *your* hardware

All plan decisions are based on those costs
 * Some costs are fixed per unit (CPU, I/O)
 * Many have a higher first-row cost, or other
   complexities, but number of rows is important

Other costs are based on statistics and metadata
 * Table size
 * Histograms
 * Uniqueness

Some things can really help the optimizer make
better-enough plan choices in general, like...
 * Useful Indexes
 * SARGable predicates
 * Unique constraints
 * Enforced foreign keys
 * A well-designed relational schema
 * Value constraints
 * Up to date statistics
 * Limited query complexity
 * Avoiding things without good costing support
   * XML
   * JSON
   * String splitting
   * Built-in functions
   * User-defined functions
   * Local variables
   * Table variables

*/

SELECT TOP (10)
    hru.*
FROM dbo.HighRepUsers AS hru;


SELECT TOP (10)
    hru.*
FROM dbo.HighRepUsers AS hru
ORDER BY
    hru.Reputation DESC;


/*
People act ridiculously with EXISTS.

There is already a row goal of one.

A semi join row goal only appears if the semi join is
an apply (correlated join). Nested loops semi join does
*not* come with a row goal on the inner side.

*/

SELECT
    hru.*
FROM dbo.HighRepUsers AS hru
WHERE EXISTS
(
    SELECT
        1/0
    FROM dbo.Badges AS b
    WHERE b.UserId = hru.Id
);


/*
All of this is useless typing.

What do you not see in the query plan?
 * A TOP operator.
 * Any signs of aggregation or distinct-ing

*/

SELECT
    hru.*
FROM dbo.HighRepUsers AS hru
WHERE EXISTS
(
    SELECT DISTINCT TOP (1)
        1/0
    FROM dbo.Badges AS b
    WHERE b.UserId = hru.Id
    GROUP BY
        b.UserId
);


/*
IN is the same as EXISTS

It's another way to express a logical semi join.

*/

SELECT
    hru.*
FROM dbo.HighRepUsers AS hru
WHERE hru.Id IN
(
    SELECT
        b.UserId
    FROM dbo.Badges AS b
)
ORDER BY
    hru.Id;

SELECT
    hru.*
FROM dbo.HighRepUsers AS hru
WHERE hru.Id = ANY /*IN equivalent*/
(
    SELECT
        b.UserId
    FROM dbo.Badges AS b
)
ORDER BY
    hru.Id;

SELECT
    hru.*
FROM dbo.HighRepUsers AS hru
WHERE hru.Id = SOME /*ANY equivalent*/
(
    SELECT
        b.UserId
    FROM dbo.Badges AS b
)
ORDER BY
    hru.Id;

SELECT
    hru.*
FROM dbo.HighRepUsers AS hru
WHERE hru.Id = ALL /*Strange bird*/
(
    SELECT
        b.UserId
    FROM dbo.Badges AS b
)
ORDER BY
    hru.Id;


/*
DECLARE
    @t1 table
(
    id integer NOT NULL
)

DECLARE
    @t2 table
(
    id integer NOT NULL
)

INSERT
    @t1
(
    id
)
VALUES
    (1)--, (2)

INSERT
    @t2
(
    id
)
VALUES
    (1)--, (3)

SELECT
    t1.*
FROM @t1 AS t1
WHERE t1.id = ALL
(
    SELECT
        t2.id
    FROM @t2 AS t2
);

NOT IN of course has some quirks that make it
not equivalent to NOT EXISTS (NULL handling).
 * https://go.erikdarling.com/NotInNotExists

Be careful with that one. And this one, too.

TOP 100 PERCENT:
 * Useless. Optimizer has ignored these since
   ~2005. Often used in views by misled developers.

*/
GO

CREATE OR ALTER VIEW
    dbo.TheMiseducationOfSQLDevelopers
AS
    SELECT TOP (100) PERCENT
        hru.*
    FROM dbo.HighRepUsers AS hru
    ORDER BY
        hru.Reputation DESC,
        hru.Id;
GO


SELECT
    t.*
FROM dbo.TheMiseducationOfSQLDevelopers AS t

/*
What do you not see in the query plan?
 * A TOP operator.

Removing the TOP (100) PERCENT is done most
deliberately to alert the user to potential
dumbness, or reliance on behavior that is not
guaranteed, in any way, at all. Ever. Really.

Thanks, optimizer. You're the best.

*/


/*
Other ways that row goals can sneak in:
 * Window function row number filtering

*/

SELECT
    hru2.*
FROM
(
    SELECT
        hru.*,
        n = ROW_NUMBER() OVER
            (
                ORDER BY
                    hru.Reputation DESC
            )
    FROM dbo.HighRepUsers AS hru
) AS hru2
WHERE hru2.n BETWEEN 1 AND 10
ORDER BY
    hru2.Id;


/*
Most people read plans going from right
to left, which is how data flows, but query
plans execute physically from left to right.

The reason why row goals (with TOP) work the
way that they do is because of that. The TOP
operator will keep asking for rows until either
 * The TOP specification is met
 * The subtree runs out of rows to send

*/

SELECT TOP (10)
    hru.*
FROM dbo.HighRepUsers AS hru
ORDER BY
    hru.Reputation DESC;


/*
Other things that set row goals
  * OFFSET/FETCH
  * FAST n hints

There is a query plan difference though:
  * OFFSET/FETCH produces a TOP operator
  * FAST n hint produces a row goal at the plan root

Look at the operator properties for the
EstimateRowsWithoutRowGoal attribute, especially in
table or index access operators (seek or scan).

Of course, FAST n hints don't limit query results like
SET ROWCOUNT n does, they only add a row goal to the
execution plan. The query behaves like it will return
a limited number of rows, no matter how many come back.

*/

SELECT
    hru.*
FROM dbo.HighRepUsers AS hru
ORDER BY
    hru.Id
OFFSET 0 ROWS
FETCH NEXT 10 ROWS ONLY;


SELECT
    hru.*
FROM dbo.HighRepUsers AS hru
ORDER BY
    hru.Id
OPTION(FAST 1);


/*
TOP accepts any positive number from (1)
to the bigint maximum value. Good luck
remembering that. I use these shortcuts.

*/

SELECT
    int_max = POWER(2., 31) -1,
    bigint_max = POWER(2., 63) -1;


/*
These two plans are "identical", shape-wise.

Top + Sort = Top N Sort

*/

SELECT TOP (1)
    hru.*
FROM dbo.HighRepUsers AS hru
WHERE hru.DisplayName = N'Jon Skeet'
ORDER BY
    hru.Reputation DESC;


SELECT TOP (9223372036854775807)
    hru.*
FROM dbo.HighRepUsers AS hru
WHERE hru.DisplayName = N'Jon Skeet'
ORDER BY
    hru.Reputation DESC;


/*
This one gets weird.

Row limits are so powerful that SQL Server's
optimizer will honor them to the detriment of
performance, by not pushing a predicate past
the TOP operator in a query's execution plan.

Note to you: Do not write queries like this.

There's no row goal here because the number of
rows in the limit exceeds the maximum rows
expected from the Top's subtree. To me, row
limits and row goals are separate things.

On the specific example: Pushing a filter past
a TOP might change the results in general. The
optimizer won't do that. Wouldn't be right.

Finding Jon Skeet among the first n high rep users
(in no particular order) is not the same as finding
the first n users named Jon Skeet in the high rep user
table.

It *is* the same if you use bigint max in the TOP, but
we can still take advantage of that knowledge in other
places, to change query plans for our delight/amusement.

*/

SELECT
    hru2.*
FROM
(
    SELECT TOP (9223372036854775807)
        hru.*
    FROM dbo.HighRepUsers AS hru
) AS hru2
WHERE hru2.DisplayName = N'Jon Skeet'
ORDER BY
    hru2.Reputation DESC;


/*
One thing almost everyone messes up
when using TOP (or OFFSET/FETCH):
 * Deterministic ordering

There is no guaranteed ordering without
an ORDER BY that includes a unique column
(or combination of columns) as a tie-breaker
for a non-unique column.

*/


/*Order by a non-unique column only*/
SELECT TOP (5)
    c.*
FROM dbo.Comments AS c
ORDER BY
    c.Score;


/*Order by a non-unique + a unique column*/
SELECT TOP (5)
    c.*
FROM dbo.Comments AS c
ORDER BY
    c.Score,
    c.Id;


/*
One place row goals can be useful is for
reshaping subquery execution plans to
make them more efficient. Let's look at one!

This isn't terrible, but there's a lot
of extra work done on the outer side of
the execution plan to make it work.

*/

SELECT
    u.Id,
    u.DisplayName,
    u.Reputation
FROM dbo.Users AS u
WHERE u.Reputation >= 1000
AND
    (
        SELECT
            MAX(p.LastActivityDate)
        FROM dbo.Posts AS p
        WHERE p.OwnerUserId = u.Id
    ) <= CONVERT(datetime, '20091031', 112)
ORDER BY
    u.Id;


/*
Adding a TOP (1) to the aggregate, which
can only ever return a single row anyway,
leads to a much more efficient query plan.

*/

SELECT
    u.Id,
    u.DisplayName,
    u.Reputation
FROM dbo.Users AS u
WHERE u.Reputation >= 1000
AND
    (
        SELECT TOP (1)
            MAX(p.LastActivityDate)
        FROM dbo.Posts AS p
        WHERE p.OwnerUserId = u.Id
        --GROUP BY ()
        /*Unquote this to see two TOPs*/
    ) <= CONVERT(datetime, '20091031', 112)
ORDER BY
    u.Id;



/*
Row goals tend to work well when data
is relatively easy to find, either because
it naturally occurs often, or you have a
reasonable set of indexes to search with.

This query has neither one available.

*/

/*What's the problem here?*/
IF EXISTS
(
    SELECT
        1/0
    FROM dbo.Posts AS p
    JOIN dbo.Votes AS v
      ON p.Id = v.PostId
    WHERE v.VoteTypeId = 1
    AND   p.PostTypeId = 1
)
BEGIN
    SELECT
        x = 1;
END;
/*Look at estimated rows, properties*/


/*How to fix it.*/
IF EXISTS
(
    SELECT
        1/0
    FROM dbo.Posts AS p
    JOIN dbo.Votes AS v
      ON p.Id = v.PostId
    WHERE v.VoteTypeId = 1
    AND   p.PostTypeId = 1
    HAVING
        COUNT_BIG(*) > 0
)
BEGIN
    SELECT
        x = 1;
END;


/*
Seeing a TOP operator immediately above
an index scan is almost always a query
plan anti-pattern. You may be able to get
away with it sometimes, but it's often not
worth the risk, unless all tables involved
are very small (a few thousand rows at best)
because each execution of the TOP operator
represents a scan of the data to either find,
or in this case, not find, a matching row.

As always, get an actual execution plan to
judge performance accurately for the query.

A TOP above a scan will almost always be the
result of row goals introduced either by an
outer TOP or OFFSET/FETCH, or by the use of:
EXISTS, NOT EXISTS, or an IN clause, like this.

Look at estimated plan first.

*/

SELECT TOP (1)
    p.Id
FROM dbo.Posts AS p
WHERE NOT EXISTS
(
    SELECT
        1/0
    FROM dbo.Votes AS v
    WHERE v.PostId = p.Id
)
ORDER BY
    p.Id DESC;


/*
The estimated execution plan looks rather
harmless, all tiny thin little lines!

But if you look at the estimated number of
rows to be read, you might stop liking things.

*/

SELECT TOP (1)
    p.Id
FROM dbo.Posts AS p
WHERE NOT EXISTS
(
    SELECT
        1/0
    FROM dbo.Votes AS v
    WHERE v.PostId = p.Id
)
ORDER BY
    p.Id;


/*
The actual execution plan has even less to
like about it. The estimates were not off
by any orders of magnitude, but the amount
of work that goes into each scan to locate
a missing row is quite obvious for this plan.

A total of 244,689,052 rows are read from the
Votes table. Since this is a NOT EXISTS query,
and we want to find the first row from the Posts
table that doesn't have a Vote, some Posts will
locate a Vote sooner than others. Nature of data.

The Votes table is ~52 million rows total, so in
practice we end up reading ~2x the number of rows
while locating matching PostId rows. Not every scan
is a full scan, of course, but the obvious answer
here is an index to align the correlated column.

If you want to try this on your own, go for it.

CREATE INDEX
   PostId
ON dbo.Votes
    (PostId)
WITH
    (SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);


This pattern is fairly easy to spot in an
estimated execution plan. If you have some
contextual performance information about the
query, either from Query Store, the plan cache,
or from Your Favorite Monitoring Tool, you may
not need to get an actual execution plan to
know that there's a problem, but getting one
can be a fun and exciting time for you anyway.

*/


/*
Different types of row goals
 * Top-level row goal
 * Intra-query row goal

FAST n hints are always a top-level row goal.

Quote the intra-query TOP out to see how
the query plan changes. Row goals are cool.

The performance change isn't very interesting
here, it's just to differentiate between the two.

*/

SELECT TOP (10)
       /*Outer row goal*/
    u.DisplayName,
    PostScore,
    CommentScore
FROM dbo.Users AS u
CROSS APPLY
(
    SELECT --TOP (9223372036854775807)
           /*Intra-query row goal*/
        PostScore = p.Score,
        CommentScore = c.Score
    FROM dbo.Posts AS p
    JOIN dbo.Comments AS c
      ON c.PostId = p.Id
     AND p.Score > 1
     AND c.Score > p.Score
     AND p.OwnerUserId = u.Id
) AS p
WHERE u.Reputation >= 200000
ORDER BY
    CommentScore DESC;



/*
Where there is a reasonable performance
difference is when the optimizer makes
sort of weird choices. Take this plan
for example. The Posts table is the
outer-most table in the joins. Scanning
it single-threaded takes most of the ~900ms
that the query executes for. Then Users gets
joined to, and then Comments gets anti-joined
to for the NOT EXISTS. Why oh why oh why?

*/

SELECT
    u.DisplayName,
    PostId = p.Id
FROM dbo.Users AS u
JOIN dbo.Posts AS p
  --WITH(FORCESEEK)
  ON p.OwnerUserId = u.Id
WHERE u.CreationDate > CONVERT(datetime, '20131210', 112)
AND   u.Reputation > 100
AND   p.PostTypeId = 2
AND   p.Score > 1000
AND   NOT EXISTS
      (
          SELECT
              1/0
          FROM dbo.Comments AS c
          WHERE c.PostId = p.Id
      )
ORDER BY
    u.Id;


/*
Same as above, if you quote out the TOP
clause, you get the same plan again. Ick.

But with the TOP in there, and a row goal
introduced, we get a much faster query plan.

Part of it is getting a parallel plan, but
even with the MAXDOP 1 hint it's much faster.

Why? We start with the Users table instead,
and that drives a Nested Loops join to the
Posts table, with all filters applied to it.

*/

SELECT
    u.DisplayName,
    PostId = p.Id
FROM dbo.Users AS u
CROSS APPLY
(
    SELECT TOP (9223372036854775807)
        p.*
    FROM dbo.Posts AS p
    WHERE p.OwnerUserId = u.Id
    AND   p.PostTypeId = 2
    AND   p.Score > 1000
    AND   NOT EXISTS
          (
              SELECT
                  1/0
              FROM dbo.Comments AS c
              WHERE c.PostId = p.Id
          )
) AS p
WHERE u.CreationDate > CONVERT(datetime, '20131210', 112)
AND   u.Reputation > 100
ORDER BY
    u.Id
OPTION(MAXDOP 1);


/*
One thing worth noting here is that the
SELECT p.* makes no difference inside the
CROSS APPLY, because the outer query only
gets one column from within it, which SQL
Server is thankfully smart enough to handle.

*/


/*
You've probably seen a lot of stuff about
using the OPTIMIZE FOR UNKNOWN hint to
"fix parameter sniffing", or the equivalent
technique of declaring local variables inside
of stored procedures, and setting them to the
formal parameter values passed in on execution.

That's all well and stupid, but there is one
good use for OPTIMIZE FOR, along with a TOP
that's parameterized: You can set the value
to some high number of rows, but have a plan
optimized for a very low number of rows.

*/

SELECT
    u.*,
    PostId = p.Id
FROM dbo.Users AS u
JOIN dbo.Posts AS p
  ON p.OwnerUserId = u.Id
WHERE u.CreationDate > CONVERT(datetime, '20131210', 112)
AND   u.Reputation > 100
AND   p.PostTypeId = 2
AND   p.Score > 1000
AND   NOT EXISTS
      (
          SELECT
              1/0
          FROM dbo.Comments AS c
          WHERE c.PostId = p.Id
      )
ORDER BY
    u.CreationDate;


DECLARE
    @Top bigint = POWER(2., 63) -1;

SELECT
    u.*,
    PostId = p.Id
FROM
(
    SELECT TOP (@Top)
        u.*
    FROM dbo.Users AS u
    WHERE u.CreationDate > CONVERT(datetime, '20131210', 112)
    AND   u.Reputation > 100
) AS u
JOIN dbo.Posts AS p
  ON p.OwnerUserId = u.Id
WHERE p.PostTypeId = 2
AND   p.Score > 1000
AND   NOT EXISTS
      (
          SELECT
              1/0
          FROM dbo.Comments AS c
          WHERE c.PostId = p.Id
      )
ORDER BY
    u.CreationDate
OPTION
(
    OPTIMIZE FOR
    (
        @Top = 1
    )
);


/*
Row Goals

What they are:
 * Promises from the optimizer about how many rows
   will be produced
 * Set explicitly (TOP, OFFSET/FETCH, FAST n) or
   implicitly (EXISTS, IN)
 * Optimization fences that reshape execution plans

Why they matter:
 * Change how the optimizer costs and builds plans
 * Can make impossible queries fast by forcing
   better join orders
 * Give you control without hints

You oughtta know:
 * EXISTS already has a row goal of 1 - don't
   add useless stuff
 * TOP 100 PERCENT is ignored - stop using it
 * Always use deterministic ordering with TOP

Trickery:
 * CROSS APPLY + TOP forces nested loops from
   outer table
 * Use HAVING COUNT_BIG(*) for EXISTS on missing
   data
 * OPTIMIZE FOR with parameterized TOP for consistent
   plans

Bottom line (get it?): Row goals can help the optimizer
make better choices when it knows you don't need every row.

Use them wisely.

My rates are reasonable.

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

W: https://erikdarling.com
E: mailto:erik@erikdarling.com
T: https://twitter.com/erikdarlingdata
T: https://www.tiktok.com/@darling.data
L: https://www.linkedin.com/company/darling-data/
Y: https://www.youtube.com/@ErikDarlingData

Demos:https://go.erikdarling.com/RowGoals
Database: https://go.erikdarling.com/Stack2013


Important material:
 * https://www.sql.kiwi/2010/08/inside-the-optimiser-row-goals-in-depth/
 * https://www.sql.kiwi/2010/08/row-goals-and-grouping/
 * https://www.sql.kiwi/2010/08/sorting-row-goals-and-the-top-100-problem/
 * https://www.sql.kiwi/2018/02/setting-and-identifying-row-goals/
 * https://www.sql.kiwi/2018/02/row-goals-part-2-semi-joins/
 * https://www.sql.kiwi/2018/03/row-goals-part-3-anti-joins/
 * https://www.sql.kiwi/2018/03/row-goals-part-4-anti-join-anti-pattern/

*/
