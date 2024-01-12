USE StackOverflow2013;
EXEC dbo.DropIndexes;
SET NOCOUNT ON;
DBCC FREEPROCCACHE;
GO 

/*
███████╗██████╗  ██████╗  ██████╗ ██╗  ██╗██╗   ██╗
██╔════╝██╔══██╗██╔═══██╗██╔═══██╗██║ ██╔╝╚██╗ ██╔╝
███████╗██████╔╝██║   ██║██║   ██║█████╔╝  ╚████╔╝ 
╚════██║██╔═══╝ ██║   ██║██║   ██║██╔═██╗   ╚██╔╝  
███████║██║     ╚██████╔╝╚██████╔╝██║  ██╗   ██║   
╚══════╝╚═╝      ╚═════╝  ╚═════╝ ╚═╝  ╚═╝   ╚═╝   
                                                   
██╗  ██╗ █████╗ ███╗   ██╗██████╗ ███████╗         
██║  ██║██╔══██╗████╗  ██║██╔══██╗██╔════╝         
███████║███████║██╔██╗ ██║██║  ██║███████╗         
██╔══██║██╔══██║██║╚██╗██║██║  ██║╚════██║         
██║  ██║██║  ██║██║ ╚████║██████╔╝███████║         
╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═════╝ ╚══════╝                                                            
*/





/*Reset things*/
UPDATE t WITH(TABLOCKX)
    SET t.MaxScore = NULL
FROM dbo.TotalScoreByUser AS t
WHERE t.MaxScore IS NOT NULL;



/*

Turn on query plans

*/





/*
Run a silly update!
*/
UPDATE t 
    SET t.MaxScore = 
        (
            SELECT 
                MAX(Score)
            FROM 
            (
                SELECT 
                    tsbu.QuestionScore 
                FROM dbo.TotalScoreByUser AS tsbu 
                WHERE tsbu.Id = t.Id
                
                UNION ALL
                
                SELECT 
                    tsbu2.AnswerScore 
                FROM dbo.TotalScoreByUser AS tsbu2 
                WHERE tsbu2.Id = t.Id
            ) AS x (Score)
        )
FROM dbo.TotalScoreByUser AS t
WHERE 1 = 1;



/*
What's in the query plan?

Where are we spending our time?

What's the spool for?
*/



/*Reset things*/
UPDATE t WITH(TABLOCKX)
    SET t.MaxScore = NULL
FROM dbo.TotalScoreByUser AS t
WHERE t.MaxScore IS NOT NULL;




/*
DIY Halloween Protection
*/
DROP TABLE IF EXISTS 
    #update;
GO

CREATE TABLE 
   #update
(
    Id INT PRIMARY KEY CLUSTERED, 
    MaxScore INT
);

INSERT 
    #update WITH(TABLOCK)
( 
    Id, 
    MaxScore 
)
SELECT 
    Id, 
    MaxScore = 
        MAX(Score)
FROM 
(
    SELECT 
        tsbu.Id, 
        tsbu.QuestionScore 
    FROM dbo.TotalScoreByUser AS tsbu 
    
    UNION ALL
    
    SELECT 
        tsbu2.Id, 
        tsbu2.AnswerScore 
    FROM dbo.TotalScoreByUser AS tsbu2
) AS x (Id, Score)
GROUP BY 
    x.Id;

UPDATE tsbu 
    SET tsbu.MaxScore = u.MaxScore
FROM dbo.TotalScoreByUser AS tsbu
JOIN #update AS u 
  ON u.Id = tsbu.Id
WHERE 1 = 1;



UPDATE 
    t WITH(TABLOCKX)
SET 
    t.MaxScore = NULL
FROM dbo.TotalScoreByUser AS t
WHERE t.MaxScore IS NOT NULL;

/*
What happened?
 * When the table you're modifying is also the source of the modification,
   The optimizer will often use a Spool (Halloween Protection)
   to keep track of rows that it needs to modify, so you don't
   get stuck in an infinite loop, etc.

Why was the temp table better?
 * Manual phase separation! Loading into #temp tables
   is way more efficient than data being loaded into spools.
   Putting data into spools is a row-by-row venture, with
   none of the more recent tempdb optimizations 

*/