USE StackOverflow2013;
EXEC dbo.DropIndexes;
SET NOCOUNT ON;
DBCC FREEPROCCACHE;
GO 



/*                                                       

Words of wisdom for windowing functions
 * Index partition by and then order by columns in the key
 * Cover other columns in the includes
*/


/*
██████╗ ██╗   ██╗███████╗██╗  ██╗██╗   ██╗                                  
██╔══██╗██║   ██║██╔════╝██║  ██║╚██╗ ██╔╝                                  
██████╔╝██║   ██║███████╗███████║ ╚████╔╝                                   
██╔═══╝ ██║   ██║╚════██║██╔══██║  ╚██╔╝                                    
██║     ╚██████╔╝███████║██║  ██║   ██║                                     
╚═╝      ╚═════╝ ╚══════╝╚═╝  ╚═╝   ╚═╝                                     
                                                                            
██████╗ ██████╗ ███████╗██████╗ ██╗ ██████╗ █████╗ ████████╗███████╗███████╗
██╔══██╗██╔══██╗██╔════╝██╔══██╗██║██╔════╝██╔══██╗╚══██╔══╝██╔════╝██╔════╝
██████╔╝██████╔╝█████╗  ██║  ██║██║██║     ███████║   ██║   █████╗  ███████╗
██╔═══╝ ██╔══██╗██╔══╝  ██║  ██║██║██║     ██╔══██║   ██║   ██╔══╝  ╚════██║
██║     ██║  ██║███████╗██████╔╝██║╚██████╗██║  ██║   ██║   ███████╗███████║
╚═╝     ╚═╝  ╚═╝╚══════╝╚═════╝ ╚═╝ ╚═════╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝
  
We stick this query in a view to let people get ranked posts for a user
*/

/*ayy*/
CREATE INDEX 
   chunk 
ON dbo.Posts 
    (OwnerUserId, Score DESC) 
INCLUDE  
    (CreationDate, LastActivityDate)
WITH
    (MAXDOP = 8, SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);
GO 

CREATE OR ALTER VIEW 
    dbo.PushyPaul
WITH SCHEMABINDING
AS
    SELECT 
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        p.LastActivityDate,
        PostRank = 
            DENSE_RANK() OVER
            ( 
                PARTITION BY 
                   p.OwnerUserId 
                ORDER BY     
                   p.Score DESC 
            )
    FROM dbo.Posts AS p;
GO 


/*

Turn on query plans, dummy!

*/


/*
This is nice and fast even for Jon Skeet. 

Good job, us.
*/
SELECT 
    p.* 
FROM dbo.PushyPaul AS p
WHERE p.OwnerUserId = 22656;
GO 















/*
We'll wrap it in a stored procedure.

I hear they make everything better.
*/
CREATE OR ALTER PROCEDURE 
    dbo.StinkyPete 
(
    @UserId int
)
AS 
SET NOCOUNT, XACT_ABORT ON;
BEGIN
    SELECT 
        p.* 
    FROM dbo.PushyPaul AS p
    WHERE p.OwnerUserId = @UserId;
END;
GO 


/*
Don't believe me just wat--
*/
EXEC dbo.StinkyPete 
    @UserId = 22656;









/*
██╗      ██╗
╚██╗ ██╗██╔╝
 ╚██╗╚═╝██║ 
 ██╔╝▄█╗██║ 
██╔╝ ▀═╝╚██╗
╚═╝      ╚═╝
            
What the hell just happened?
*/
EXEC dbo.StinkyPete 
    @UserId = 22656;
GO 

SELECT 
    p.* 
FROM dbo.PushyPaul AS p
WHERE p.OwnerUserId = 22656;
GO 
















/*
██╗   ██╗██╗███████╗██╗    ██╗███████╗
██║   ██║██║██╔════╝██║    ██║██╔════╝
██║   ██║██║█████╗  ██║ █╗ ██║███████╗
╚██╗ ██╔╝██║██╔══╝  ██║███╗██║╚════██║
 ╚████╔╝ ██║███████╗╚███╔███╔╝███████║
  ╚═══╝  ╚═╝╚══════╝ ╚══╝╚══╝ ╚══════╝
                                      
View can't do that!

The problem with views?
    * They can't accept parameters.
    * The optimizer can't push parameters past Sequence operators.
    * It can only do that with constant values (literals).
    * Recompile would work if we were desperate.
    * But we're smarter than that.
*/























/*
███████╗██╗   ██╗███╗   ██╗ ██████╗████████╗██╗ ██████╗ ███╗   ██╗██╗
██╔════╝██║   ██║████╗  ██║██╔════╝╚══██╔══╝██║██╔═══██╗████╗  ██║██║
█████╗  ██║   ██║██╔██╗ ██║██║        ██║   ██║██║   ██║██╔██╗ ██║██║
██╔══╝  ██║   ██║██║╚██╗██║██║        ██║   ██║██║   ██║██║╚██╗██║╚═╝
██║     ╚██████╔╝██║ ╚████║╚██████╗   ██║   ██║╚██████╔╝██║ ╚████║██╗
╚═╝      ╚═════╝ ╚═╝  ╚═══╝ ╚═════╝   ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚═╝                                                                     
*/

GO 

CREATE OR ALTER FUNCTION 
    dbo.PusherPaul 
(
    @UserId int
)
RETURNS table 
WITH SCHEMABINDING
AS
RETURN
    SELECT 
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        p.LastActivityDate,
        PostRank = 
            DENSE_RANK() OVER
            ( 
                PARTITION BY 
                    p.OwnerUserId 
                ORDER BY     
                    p.Score DESC 
            )
    FROM dbo.Posts AS p
    WHERE p.OwnerUserId = @UserId;
GO 

CREATE OR ALTER PROCEDURE 
    dbo.SneakyPete 
(
    @UserId int
)
AS 
SET NOCOUNT, XACT_ABORT ON;
BEGIN
    SELECT 
        p.*
    FROM dbo.PusherPaul(@UserId) AS p;
END;
GO 



EXEC dbo.SneakyPete 
    @UserId = 22656;
GO 





/*

SQL Server 2017 CU 30
SQL Server 2019 CU 17

Trace Flag 4199 fixes this issue.

*/

CREATE OR ALTER PROCEDURE 
    dbo.StinkyPete_4199
(
    @UserId int
)
AS 
SET NOCOUNT, XACT_ABORT ON;
BEGIN
    SELECT 
        p.* 
    FROM dbo.PushyPaul AS p
    WHERE p.OwnerUserId = @UserId
    OPTION(QUERYTRACEON 4199);
END;
GO 



EXEC dbo.StinkyPete 
    @UserId = 22656;
GO 

EXEC dbo.StinkyPete_4199 
    @UserId = 22656;
GO 


/*
   
A view is just a query
 * They can't accept parameters
 * Parameters can't be pushed past Sequence Project
 * Constants can, recompile hints can help
 * iTVFs can accept parameters
 * Which can be pushed to the index access                              

*/