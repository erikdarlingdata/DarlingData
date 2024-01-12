USE StackOverflow2013;
EXEC dbo.DropIndexes;
SET NOCOUNT ON;
DBCC FREEPROCCACHE;
GO 

CREATE INDEX 
    whatever 
ON dbo.Votes 
    (CreationDate, VoteTypeId)
WITH
    (MAXDOP = 8, SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);
GO 


/*
██████╗ ███████╗ █████╗ ██████╗      ██████╗ ██████╗ ███╗   ███╗███╗   ███╗██╗████████╗████████╗███████╗██████╗ 
██╔══██╗██╔════╝██╔══██╗██╔══██╗    ██╔════╝██╔═══██╗████╗ ████║████╗ ████║██║╚══██╔══╝╚══██╔══╝██╔════╝██╔══██╗
██████╔╝█████╗  ███████║██║  ██║    ██║     ██║   ██║██╔████╔██║██╔████╔██║██║   ██║      ██║   █████╗  ██║  ██║
██╔══██╗██╔══╝  ██╔══██║██║  ██║    ██║     ██║   ██║██║╚██╔╝██║██║╚██╔╝██║██║   ██║      ██║   ██╔══╝  ██║  ██║
██║  ██║███████╗██║  ██║██████╔╝    ╚██████╗╚██████╔╝██║ ╚═╝ ██║██║ ╚═╝ ██║██║   ██║      ██║   ███████╗██████╔╝
╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═════╝      ╚═════╝ ╚═════╝ ╚═╝     ╚═╝╚═╝     ╚═╝╚═╝   ╚═╝      ╚═╝   ╚══════╝╚═════╝ 
                                                                                                                
██╗███████╗     █████╗      ██████╗  █████╗ ██████╗ ██████╗  █████╗  ██████╗ ███████╗                           
██║██╔════╝    ██╔══██╗    ██╔════╝ ██╔══██╗██╔══██╗██╔══██╗██╔══██╗██╔════╝ ██╔════╝                           
██║███████╗    ███████║    ██║  ███╗███████║██████╔╝██████╔╝███████║██║  ███╗█████╗                             
██║╚════██║    ██╔══██║    ██║   ██║██╔══██║██╔══██╗██╔══██╗██╔══██║██║   ██║██╔══╝                             
██║███████║    ██║  ██║    ╚██████╔╝██║  ██║██║  ██║██████╔╝██║  ██║╚██████╔╝███████╗                           
╚═╝╚══════╝    ╚═╝  ╚═╝     ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚══════╝                           
                                                                                                                
██╗███████╗ ██████╗ ██╗      █████╗ ████████╗██╗ ██████╗ ███╗   ██╗    ██╗     ███████╗██╗   ██╗███████╗██╗     
██║██╔════╝██╔═══██╗██║     ██╔══██╗╚══██╔══╝██║██╔═══██╗████╗  ██║    ██║     ██╔════╝██║   ██║██╔════╝██║     
██║███████╗██║   ██║██║     ███████║   ██║   ██║██║   ██║██╔██╗ ██║    ██║     █████╗  ██║   ██║█████╗  ██║     
██║╚════██║██║   ██║██║     ██╔══██║   ██║   ██║██║   ██║██║╚██╗██║    ██║     ██╔══╝  ╚██╗ ██╔╝██╔══╝  ██║     
██║███████║╚██████╔╝███████╗██║  ██║   ██║   ██║╚██████╔╝██║ ╚████║    ███████╗███████╗ ╚████╔╝ ███████╗███████╗
╚═╝╚══════╝ ╚═════╝ ╚══════╝╚═╝  ╚═╝   ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝    ╚══════╝╚══════╝  ╚═══╝  ╚══════╝╚══════╝
*/



/*

Reads blocking writes

*/

/*For a real reason...*/
CREATE OR ALTER PROCEDURE 
    dbo.ReadBlocker 
(
    @StartDate datetime 
)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;

    DECLARE 
        @i int;
    
    SELECT   
        @i = v.PostId
    FROM dbo.Votes AS v 
    WHERE v.CreationDate >= @StartDate
    AND   v.VoteTypeId > 5
    GROUP BY 
        v.PostId
    ORDER BY 
        v.PostId;
END;
GO

/*Get a "bad" plan*/
EXEC dbo.ReadBlocker 
    @StartDate = '20131231';

/*Trivia!*/
EXEC dbo.ReadBlocker 
    @StartDate = '17530101';



/*New window -- Look at locks, dangit*/
EXEC dbo.sp_WhoIsActive 
    @get_locks = 1;



/*YET ANOTHER NEW WINDOW GOSH*/
BEGIN TRAN;

    UPDATE dbo.Votes
        SET UserId = 2147483647
    WHERE 1 = 1;

ROLLBACK;


/*

Reads deadlocking writes

*/

/*Create a non-covering index*/
EXEC dbo.DropIndexes;
CREATE INDEX 
    dethklok 
ON 
dbo.Votes
    (VoteTypeId)
WITH
    (MAXDOP = 8, SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);


/* Select query with a predicate on our index key */ 
SET NOCOUNT ON;
DECLARE 
    @i int = 0,
    @PostId int;

WHILE 
    @i < 100000
BEGIN
    SELECT 
        @PostId = v.PostId,
        @i += 1
    FROM dbo.Votes AS v
    WHERE v.VoteTypeId = 8;
END;
GO


/* Update query that just flips the VoteTypeId back and forth */
/* Put this in a new window and start running it first */
SET NOCOUNT ON;
DECLARE 
    @i int = 0;
WHILE 
    @i < 100000
BEGIN
    UPDATE v
      SET 
        v.VoteTypeId = 8 - v.VoteTypeId,
        @i += 1
    FROM dbo.Votes AS v
    WHERE v.Id = 55537618;
END;
GO


/* If you time this just right, 
   you can see both queries blocking each other */
EXEC dbo.sp_WhoIsActive 
    @get_locks = 1;












/* Great reset */
UPDATE v
    SET v.VoteTypeId = 8
FROM dbo.Votes AS v
WHERE v.Id = 55537618
AND   v.VoteTypeId <> 8;








/*
What happened?

Our query did a key lookup
 * The nested loop join used the unordered prefetch optimization
 * That caused locks to be held on the clustered index until the query finished
 * Object level S locks will block IX and X locks

HA HA HA!

To fix it:
 * Create a covering index:
       CREATE INDEX 
           whatever 
       ON dbo.Votes 
           (CreationDate, VoteTypeId)
       INCLUDE
           (PostId);

 * Use an optimistic isolation level, like RCSI or SI:
       ALTER DATABASE [?] SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;
       ALTER DATABASE [?] SET ALLOW_SNAPSHOT_ISOLATION ON WITH ROLLBACK IMMEDIATE;
 
 * Write the query to do a self join, with a hint to use a merge or hash join:
       SELECT 
           @PostId = v2.PostId
       FROM dbo.Votes AS v
       
       INNER MERGE JOIN dbo.Votes AS v2
       INNER HASH JOIN dbo.Votes AS v2
       
       ON v.Id = v2.Id
       WHERE v.VoteTypeId = 8;

*/