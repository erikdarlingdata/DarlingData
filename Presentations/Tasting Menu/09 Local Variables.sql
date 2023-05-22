USE StackOverflow2013;
EXEC dbo.DropIndexes;
SET NOCOUNT ON;
DBCC FREEPROCCACHE;
GO

/*
██╗      ██████╗  ██████╗ █████╗ ██╗                                
██║     ██╔═══██╗██╔════╝██╔══██╗██║                                
██║     ██║   ██║██║     ███████║██║                                
██║     ██║   ██║██║     ██╔══██║██║                                
███████╗╚██████╔╝╚██████╗██║  ██║███████╗                           
╚══════╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝╚══════╝                           
                                                                    
██╗   ██╗ █████╗ ██████╗ ██╗ █████╗ ██████╗ ██╗     ███████╗███████╗
██║   ██║██╔══██╗██╔══██╗██║██╔══██╗██╔══██╗██║     ██╔════╝██╔════╝
██║   ██║███████║██████╔╝██║███████║██████╔╝██║     █████╗  ███████╗
╚██╗ ██╔╝██╔══██║██╔══██╗██║██╔══██║██╔══██╗██║     ██╔══╝  ╚════██║
 ╚████╔╝ ██║  ██║██║  ██║██║██║  ██║██████╔╝███████╗███████╗███████║
  ╚═══╝  ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═╝╚═════╝ ╚══════╝╚══════╝╚══════╝
*/

/*

For maximum detail, go here:
 * https://bit.ly/LocalVariables

*/

/*
When we create indexes, we create statistics, too
*/
CREATE INDEX 
    flubber 
ON dbo.Posts 
    (OwnerUserId)
WITH
    (MAXDOP = 8, SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);

/*
They have histograms with (hopefully) good information
*/
DBCC SHOW_STATISTICS(Posts, flubber);

/*
Local variables don't use that information.
*/
DECLARE 
    @oui INT = 22656;

SELECT 
    records = COUNT_BIG(*)
FROM dbo.Posts AS p
WHERE p.OwnerUserId = @oui;

/*
They use "less precise" estimation techniques
*/
SELECT 
    [💩] = (6.968291E-07 * 17142169);

DBCC SHOW_STATISTICS(Posts, flubber);

/* How all density is calculated */
SELECT 
    [All Density] =
        (
            1 / 
            CONVERT
            (
                float, 
                COUNT_BIG(DISTINCT p.OwnerUserId)
             )
        )
FROM dbo.Posts AS p;
GO








/*
Code that uses literals, parameters, and other sniff-able forms of predicates 
use the statistics histogram, which typically has far more valuable information 
about data distribution for a column. 

No, they’re not always perfect, and sure, estimates can still be off if we use this, 
but that’s a chance I’m willing to take.
*/

CREATE OR ALTER PROCEDURE 
    dbo.game_time 
(
    @id int
)
AS
BEGIN
    
    DECLARE 
        @id_fix INT;

    SET @id_fix = 
        CASE 
            WHEN @id < 0 
            THEN 1
            ELSE @id
        END;

    DECLARE 
        @sql nvarchar(MAX) = N'';

    SET @sql += N'
    /*dbo.game_time*/
    SELECT 
        records = 
            COUNT_BIG(*)
    FROM dbo.Posts AS p 
    WHERE p.OwnerUserId = @id;';

    /*What's the estimate for this one?*/
    EXEC sys.sp_executesql 
        @sql, 
      N'@id INT', 
        @id_fix;

    /*How about this one?*/
    SELECT 
        records = 
            COUNT_BIG(*)
    FROM dbo.Posts AS p 
    WHERE p.OwnerUserId = @id;

    /*How about this one?*/
    SELECT 
        records = 
            COUNT_BIG(*)
    FROM dbo.Posts AS p 
    WHERE p.OwnerUserId = @id_fix;

END;
GO

/* Accurate guess! */
EXEC dbo.game_time 
    @id = 22656;



/*
What happened?
 * Local variables often lead to bad cardinality estimates
 * They're the same thing as OPTIMIZE FOR UNKNOWN
 * People often talk about them "fixing parameter sniffing",
   but they really just prevent parameters from being sniffed
 * Variables can be passed to dynamic SQL, stored procs, and functions,
   which magically turns them into parameters

For maximum detail, go here:
 * https://bit.ly/LocalVariables

*/

