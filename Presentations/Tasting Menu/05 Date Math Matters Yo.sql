USE StackOverflow2013;
EXEC dbo.DropIndexes;
SET NOCOUNT ON;
DBCC FREEPROCCACHE;
GO 

CREATE INDEX 
    p
ON dbo.Posts
    (Id) 
INCLUDE
    (OwnerUserId)
WITH
    (SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);

/*
██████╗  █████╗ ████████╗███████╗    ███╗   ███╗ █████╗ ████████╗██╗  ██╗
██╔══██╗██╔══██╗╚══██╔══╝██╔════╝    ████╗ ████║██╔══██╗╚══██╔══╝██║  ██║
██║  ██║███████║   ██║   █████╗      ██╔████╔██║███████║   ██║   ███████║
██║  ██║██╔══██║   ██║   ██╔══╝      ██║╚██╔╝██║██╔══██║   ██║   ██╔══██║
██████╔╝██║  ██║   ██║   ███████╗    ██║ ╚═╝ ██║██║  ██║   ██║   ██║  ██║
╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝    ╚═╝     ╚═╝╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝
                                                                         
███╗   ███╗ █████╗ ████████╗████████╗███████╗██████╗ ███████╗            
████╗ ████║██╔══██╗╚══██╔══╝╚══██╔══╝██╔════╝██╔══██╗██╔════╝            
██╔████╔██║███████║   ██║      ██║   █████╗  ██████╔╝███████╗            
██║╚██╔╝██║██╔══██║   ██║      ██║   ██╔══╝  ██╔══██╗╚════██║            
██║ ╚═╝ ██║██║  ██║   ██║      ██║   ███████╗██║  ██║███████║            
╚═╝     ╚═╝╚═╝  ╚═╝   ╚═╝      ╚═╝   ╚══════╝╚═╝  ╚═╝╚══════╝            
*/




/*
My only index right now:

CREATE INDEX p
    ON dbo.Posts(Id) 
    INCLUDE(OwnerUserId);
*/

SELECT 
    u.Id, 
    u.DisplayName, 
    v.*
FROM dbo.Users AS u
JOIN 
    (
        SELECT 
            p2.OwnerUserId,
            MaybePostVotes = 
                COUNT_BIG(*)
        FROM dbo.Votes AS v
        JOIN dbo.Posts AS p2
          ON p2.Id = v.PostId
        WHERE DATEDIFF(DAY, v.CreationDate, '20140101') <= 30
        GROUP BY 
            p2.OwnerUserId
        HAVING 
            COUNT_BIG(p2.Id) >= 50
    ) AS v 
      ON v.OwnerUserId = u.Id
ORDER BY 
    u.Id;


SELECT 
    u.Id, 
    u.DisplayName, 
    v.*
FROM dbo.Users AS u
JOIN 
    (
        SELECT 
            p2.OwnerUserId,
            MaybePostVotes = 
                COUNT_BIG(*)
        FROM dbo.Votes AS v
        JOIN dbo.Posts AS p2
          ON p2.Id = v.PostId
        WHERE v.CreationDate >= DATEADD(DAY, -30, '20140101')
        GROUP BY 
            p2.OwnerUserId
        HAVING 
            COUNT(p2.Id) >= 50
    ) AS v 
      ON v.OwnerUserId = u.Id
ORDER BY 
    u.Id;



/*
Break in case of

CREATE NONCLUSTERED INDEX v
    ON dbo.Votes( CreationDate, PostId );

*/