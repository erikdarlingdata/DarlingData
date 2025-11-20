USE StackOverflow2013;

/*Bye*/
DROP TABLE IF EXISTS
    #DBCCShowStatistics;

/*Hi*/
CREATE TABLE
    #DBCCShowStatistics
(
    range_high_key bigint NOT NULL,
    range_rows bigint NOT NULL,
    equality_rows bigint NOT NULL,
    distinct_range_rows bigint NOT NULL,
    average_range_rows bigint NOT NULL
)

/*Making it easier*/
INSERT
    #DBCCShowStatistics
(
    range_high_key,
    range_rows,
    equality_rows,
    distinct_range_rows,
    average_range_rows
)
EXECUTE sys.sp_executesql
N'
DBCC SHOW_STATISTICS
(
    N''dbo.Comments'',
    N''Score''
)
WITH
    HISTOGRAM;
';

/*Results for sanity*/
SELECT
    dss.*
FROM #DBCCShowStatistics AS dss
ORDER BY
    dss.range_high_key;

/*
Any value that appears fewer than 100 times (according to
statistics) is considered very uncommon.

That means that if the *least* common value appears 100 times, 
it will *not* be considered very uncommon and will get the 
'everything else' variant.

Only values that don't appear in the histogram or are otherwise 
estimated (between steps) to match fewer than 100 times would 
trigger the 'very uncommon' variant in that scenario.

1. Very uncommon = fewer than 100 times
2. Very common = 100,000 * least common
3. Everything else

*/


/*Some heuristics stuff*/
SELECT
    EqualityLow = 
       MIN(dss.equality_rows),
    EqualityHigh = 
        MAX(dss.equality_rows),
    IsEligible =
        CASE 
            WHEN MAX(dss.equality_rows) > 
                 MIN(dss.equality_rows) * 100000
            THEN 'Yes'
            ELSE 'No'
        END,
    VeryUncommon = 
        '< 100',
    VeryCommon = 
        POWER
        (
            10, 
            FLOOR
            (
                LOG10
                (
                    MAX(dss.equality_rows)
                )
            )
        )
FROM #DBCCShowStatistics AS dss;


/*This query gets PSPO*/
EXECUTE sys.sp_executesql
N'
SELECT
    c = COUNT_BIG(*)
FROM dbo.Comments AS c
WHERE c.Score = @Score;
',
N'@Score integer',
0;

/* 
Optional extra examples (might be mundane)
*/

-- Very uncommon
EXECUTE sys.sp_executesql
N'
SELECT
    c = COUNT_BIG(*)
FROM dbo.Comments AS c
WHERE c.Score = @Score
',
N'@Score integer',
81;

-- Everything else
EXECUTE sys.sp_executesql
N'
SELECT
    c = COUNT_BIG(*)
FROM dbo.Comments AS c
WHERE c.Score = @Score
',
N'@Score integer',
74;

/*
This does not because the predicate
on Id restricts things below the
threshold of 99,999 rows.

*/
EXECUTE sys.sp_executesql
N'
SELECT
    c = COUNT_BIG(*)
FROM dbo.Comments AS c
WHERE c.Score = @Score
AND   c.Id BETWEEN 1 AND 167991
',
N'@Score integer',
0;


/*
Lone Id predicate to demonstrate
The estimate is rounded to 100k
in the graphic plan, but in the
tooltip you'll see 99,999.5 rows.

*/
EXECUTE sys.sp_executesql
N'
SELECT
    c = COUNT_BIG(*)
FROM dbo.Comments AS c
WHERE c.Id BETWEEN 1 AND 167991
';


/* 
Make sure you set this up to be repeatable 4 u.
With DOP 1 FULLSCAN stats on Comments, I found 
the tipping point to be (163769, 163770)

*/

UPDATE STATISTICS
    dbo.Comments
    PK_Comments_Id
WITH
    FULLSCAN,
    MAXDOP = 1;

/*This gets PSPO, one more row*/
EXECUTE sys.sp_executesql
N'
SELECT
    c = COUNT_BIG(*)
FROM dbo.Comments AS c
WHERE c.Score = @Score
AND   c.Id BETWEEN 1 AND 167992
',
N'@Score integer',
0;


/*
This should get QueryVariantId 27.

Note that only the first three of
the parameters (up to @Score3) get
a "plan per value". 3 * 9 = 27, so
that math all checks out. There are
27 possible plans for this query.

*/
EXECUTE sys.sp_executesql
N'
SELECT
    c = COUNT_BIG(*)
FROM dbo.Comments AS c
WHERE c.Score = @Score1

UNION ALL

SELECT
    c = COUNT_BIG(*)
FROM dbo.Comments AS c
WHERE c.Score = @Score2

UNION ALL

SELECT
    c = COUNT_BIG(*)
FROM dbo.Comments AS c
WHERE c.Score = @Score3

UNION ALL

SELECT
    c = COUNT_BIG(*)
FROM dbo.Comments AS c
WHERE c.Score = @Score4
',
N'
@Score1 integer,
@Score2 integer,
@Score3 integer,
@Score4 integer
',
0, 
0, 
0,
0;

/* 
Also variant 27, just more compact:

*/

EXECUTE sys.sp_executesql
N'
SELECT c = COUNT_BIG(*)
FROM dbo.Comments AS c
WHERE c.Score = @Score
UNION
SELECT c = COUNT_BIG(*)
FROM dbo.Comments AS c
WHERE c.Score = @Score
UNION
SELECT c = COUNT_BIG(*)
FROM dbo.Comments AS c
WHERE c.Score = @Score;
',
N'@Score integer',
0;


/*
This query does not get PSPO
because the predicate is...
backwards! (@Score = c.Score)

Quite silly. Foolish even. Hm.

*/
EXECUTE sys.sp_executesql
N'
SELECT
    c = COUNT_BIG(*)
FROM dbo.Comments AS c
WHERE @Score = c.Score
',
N'@Score integer',
0;

/* 
The other main reason you might not see PSPO
is a compilation time exceeding 1000ms.

*/
