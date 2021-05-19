CREATE OR ALTER PROCEDURE dbo.tempdb_tester
AS
SET NOCOUNT, XACT_ABORT ON;
BEGIN;
    
WITH x1 (n) AS 
( 
    SELECT 1 UNION ALL SELECT 1 UNION ALL 
    SELECT 1 UNION ALL SELECT 1 UNION ALL 
    SELECT 1 UNION ALL SELECT 1 UNION ALL 
    SELECT 1 UNION ALL SELECT 1 UNION ALL  
    SELECT 1 UNION ALL SELECT 1 
),                          
     x2(n) AS 
( 
    SELECT 
        1 
    FROM x1 AS x, 
         x1 AS xx 
), 
     x4(n) AS 
( 
    SELECT 
        1 
    FROM x2 AS x, 
         x2 AS xx 
)
SELECT 
    ROW_NUMBER() OVER 
    (
        ORDER BY 
           ( SELECT 1/0 )
    ) AS x,
    CONVERT
    (
        varchar(100), 
        REPLICATE('A', 10)
    ) AS textual
INTO #t
FROM x4;

UPDATE #t 
    SET 
        textual = 
            CONVERT
            (
                varchar(100), 
                REPLICATE('Z', 100)
            )
WHERE x <= 2000;

DELETE 
FROM #t 
WHERE x > 8000;

INSERT 
    #t WITH(TABLOCK)
(
    x,
    textual
)
SELECT
    t.x, 
    t.textual
FROM #t AS t;

END;
GO 
