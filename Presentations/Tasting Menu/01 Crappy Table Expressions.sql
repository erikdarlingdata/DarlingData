USE StackOverflow2013;
EXEC dbo.DropIndexes;
SET NOCOUNT ON;
DBCC FREEPROCCACHE;
GO

/*
    Create these ahead of time, if you can
*/
CREATE INDEX 
    users 
ON dbo.Users 
    (CreationDate, Reputation, Id)
WITH
    (SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);
GO

CREATE INDEX 
    posts
ON dbo.Posts 
    (OwnerUserId, Id)
INCLUDE 
    (PostTypeId)
WHERE 
    PostTypeId = 1;
GO

/*
 ██████╗████████╗███████╗███████╗
██╔════╝╚══██╔══╝██╔════╝██╔════╝
██║        ██║   █████╗  ███████╗
██║        ██║   ██╔══╝  ╚════██║
╚██████╗   ██║   ███████╗███████║
 ╚═════╝   ╚═╝   ╚══════╝╚══════╝                                 
*/

/*
Turn on query plans!
*/

/*
Why do we have them?
*/

/*
Derived tables have limitations.
*/

SELECT
    x.*
FROM
(
    SELECT 
        u.Id 
    FROM dbo.Users AS u 
    WHERE u.Id = 22656
) AS x
JOIN x AS x2
  ON x.Id = x2.Id;


/*Forehsadowing...*/
SELECT
    x.*
FROM
(
    SELECT 
        u.Id 
    FROM dbo.Users AS u 
    WHERE u.Id = 22656
) AS x
JOIN 
(
    SELECT 
        u.Id 
    FROM dbo.Users AS u 
    WHERE u.Id = 22656
) AS x2
  ON x.Id = x2.Id;



/*
CTEs don't have that problem.
*/
WITH
    x AS
(
    SELECT 
        u.Id 
    FROM dbo.Users AS u 
    WHERE u.Id = 22656
)
SELECT 
    x.* 
FROM x 
JOIN x AS x2 
  ON x.Id = x2.Id;

/*
CTEs have other problems.

Make sure query plans are on.
*/
WITH
    cte AS
(
    SELECT 
        u.* 
    FROM dbo.Users AS u 
    WHERE u.Id = 22656
)
SELECT cte.* FROM cte
UNION ALL
SELECT cte.* FROM cte
UNION ALL
SELECT cte.* FROM cte;

WITH
    cte AS
(
    SELECT 
        u.Id 
    FROM dbo.Users AS u 
    WHERE u.Id = 22656
)
SELECT
    c1.*
FROM
    cte AS c1
JOIN cte AS c2
JOIN cte AS c3
  ON c3.Id = c2.Id
  ON c2.Id = c1.Id;

/*
  This gets worse as your query gets more complicated
  Just grab the estimated plan, here   
*/
WITH
    cte AS
(
    SELECT
        Id = p.OwnerUserId
    FROM
        dbo.Users AS u
    JOIN dbo.Badges AS b
      ON b.UserId = u.Id
    JOIN dbo.Comments AS c
      ON c.UserId = b.UserId
    JOIN dbo.Posts AS p
      ON p.OwnerUserId = c.UserId
    JOIN dbo.Votes AS v
      ON v.UserId = p.OwnerUserId
)
SELECT
    *
FROM
    cte AS c1
JOIN cte AS c2
  ON c2.Id = c1.Id
JOIN cte AS c3
  ON c3.Id = c2.Id;


/*
CTEs are dumb.
* Don't materialize
* Unsupported tricks to "fence" them off
* Can be okay to focus on small amounts of data

Long select lists are brutal
* Nice narrow indexes don't get used
* Optimizer has some bias against key lookups
* Writing your own key lookups can be faster

Temp tables are often the better choice!

*/
