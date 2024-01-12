USE StackOverflow2013;
EXEC dbo.DropIndexes;
SET NOCOUNT ON;
DBCC FREEPROCCACHE;
GO 
    


/*
██████╗ ██╗████████╗███╗   ███╗ █████╗ ██████╗ ███████╗
██╔══██╗██║╚══██╔══╝████╗ ████║██╔══██╗██╔══██╗██╔════╝
██████╔╝██║   ██║   ██╔████╔██║███████║██████╔╝███████╗
██╔══██╗██║   ██║   ██║╚██╔╝██║██╔══██║██╔═══╝ ╚════██║
██████╔╝██║   ██║   ██║ ╚═╝ ██║██║  ██║██║     ███████║
╚═════╝ ╚═╝   ╚═╝   ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝     ╚══════╝                                                                                                                                                        
*/

/*

TURN ON QUERY PLANS DUMMY

*/


/*
We've all seen them.

Bitmaps.

Sup with that?
*/




/*
When are they useful?
*/
WITH 
    comment_count AS 
(
    SELECT 
        c.UserId, 
        records = COUNT_BIG(*)
    FROM dbo.Comments AS c
    WHERE c.Score > 9
    GROUP BY c.UserId
)
SELECT TOP (100)
    u.DisplayName,
    cc.records
FROM dbo.Users AS u
JOIN comment_count AS cc
  ON cc.UserId = u.Id
ORDER BY 
    u.Reputation DESC;

/*
When they reduce a good number of rows.

On the inner side of the scan, pay attention to:
 * Estimated rows, Rows to be read
 * Number of rows read
 * Actual number of rows

Like here.

*/






/*
When are they not so useful?
*/
WITH 
    badge_count AS
(
    SELECT 
        b.UserId, 
        records = COUNT_BIG(*)
    FROM dbo.Badges AS b
    GROUP BY 
        b.UserId
)
SELECT TOP (100)
    u.DisplayName,
    bc.records
FROM dbo.Users AS u
JOIN badge_count AS bc
  ON bc.UserId = u.Id
ORDER BY 
    u.Reputation DESC;

/*
Well, here.

Every row passes the Bitmap.
*/






/*
Not every Bitmap hits the Scan

Some only get to the Repartition Streams
*/
SELECT 
    records = COUNT_BIG(*)
FROM dbo.Users AS u
WHERE u.Reputation > 1000
AND EXISTS
( 
    SELECT 
        1/0
    FROM dbo.Comments AS c
    WHERE c.UserId = u.Id 
);



/*
Bitmaps go well with:
 * Early semi join row reductions!
 * When they actually reduce rows
 * No real overhead or downside to using them

*/