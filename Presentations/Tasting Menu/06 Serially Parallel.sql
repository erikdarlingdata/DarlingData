USE StackOverflow2013;
EXEC dbo.DropIndexes;
SET NOCOUNT ON;
DBCC FREEPROCCACHE;
GO 

CREATE INDEX 
    pq
ON 
    dbo.Posts
    ( 
        CreationDate, 
        ClosedDate, 
        AcceptedAnswerId 
    )
INCLUDE
    (Score)
WHERE
    (Score > 0)
WITH
    (SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);
GO 


/*
███████╗███████╗██████╗ ██╗ █████╗ ██╗     ██╗  ██╗   ██╗
██╔════╝██╔════╝██╔══██╗██║██╔══██╗██║     ██║  ╚██╗ ██╔╝
███████╗█████╗  ██████╔╝██║███████║██║     ██║   ╚████╔╝ 
╚════██║██╔══╝  ██╔══██╗██║██╔══██║██║     ██║    ╚██╔╝  
███████║███████╗██║  ██║██║██║  ██║███████╗███████╗██║   
╚══════╝╚══════╝╚═╝  ╚═╝╚═╝╚═╝  ╚═╝╚══════╝╚══════╝╚═╝                     
                                                                
██████╗  █████╗ ██████╗  █████╗ ██╗     ██╗     ███████╗██╗     
██╔══██╗██╔══██╗██╔══██╗██╔══██╗██║     ██║     ██╔════╝██║     
██████╔╝███████║██████╔╝███████║██║     ██║     █████╗  ██║     
██╔═══╝ ██╔══██║██╔══██╗██╔══██║██║     ██║     ██╔══╝  ██║     
██║     ██║  ██║██║  ██║██║  ██║███████╗███████╗███████╗███████╗
╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝╚══════╝
*/



SELECT
    pbs.flat_date, 
    pbs.answers_or_something
FROM dbo.parallel_but_serial AS pbs
ORDER BY 
    pbs.flat_date
OPTION(MAXDOP 8);

SELECT
    pbs.flat_date, 
    pbs.answers_or_something
FROM dbo.parallel_but_serial AS pbs
ORDER BY 
    pbs.flat_date
OPTION(MAXDOP 1);



/*
CREATE OR ALTER VIEW
    dbo.parallel_but_serial
AS
SELECT 
    flat_date = 
        DATEFROMPARTS
        ( 
            DATEPART
            (
                YEAR,  
                q.CreationDate
            ),
            DATEPART
            (
                MONTH, 
                q.CreationDate
            ), 
            1 
        ),
    answers_or_something = 
        COUNT_BIG(*)
FROM dbo.Posts AS q
JOIN dbo.Posts AS a
  ON q.AcceptedAnswerId = a.Id
CROSS JOIN
(
    SELECT tsNow = 
        MAX(p.CreationDate) 
    FROM dbo.Posts AS p 
    WHERE p.Score > 0
) AS tsNow
WHERE q.CreationDate < tsNow.tsNow
AND   q.ClosedDate IS NULL
AND   q.Score > 0
AND   a.Score > 0
AND   q.OwnerUserId = 22656
GROUP BY     
    DATEFROMPARTS
    ( 
        DATEPART
        (
            YEAR,  
            q.CreationDate
        ),
        DATEPART
        (
            MONTH, 
            q.CreationDate
        ), 
        1 
    )

*/