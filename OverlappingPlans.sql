CREATE OR ALTER FUNCTION dbo.OverlappingPlans (@Start DATETIME, @End DATETIME, @DatabaseName sysname)
RETURNS TABLE
AS RETURN
WITH starter AS (
    SELECT ds.last_execution_time,
           DATEADD(MILLISECOND, (ds.last_elapsed_time / 1000.), ds.last_execution_time) AS last_execution_end_time
    FROM sys.dm_exec_query_stats AS ds
    CROSS APPLY sys.dm_exec_query_plan(plan_handle) AS qp
    WHERE qp.dbid = DB_ID(@DatabaseName)
    AND   ds.last_execution_time >= @Start
    AND   ds.last_execution_time < @End
)
SELECT TOP (2147483647)
       SUBSTRING(tx.text, (ds.statement_start_offset / 2) +1,   
                 ((CASE ds.statement_end_offset  
                       WHEN -1 
				       THEN DATALENGTH(tx.text)  
                       ELSE ds.statement_end_offset  
                   END - ds.statement_start_offset) / 2) +1) AS text,
       qp.query_plan,
       ds.execution_count,
       ds.last_execution_time,
	   DATEADD(MILLISECOND, (ds.last_elapsed_time / 1000.), ds.last_execution_time) AS last_execution_end_time,
	   ds.last_worker_time,
       ds.last_physical_reads,
       ds.last_logical_writes,
       ds.last_logical_reads,
       ds.last_clr_time,
       ds.last_elapsed_time,
       ds.last_rows,
       ds.last_dop,
       ds.last_grant_kb,
       ds.last_used_grant_kb,
       ds.last_ideal_grant_kb,
       ds.last_reserved_threads,
       ds.last_used_threads,
       ds.last_columnstore_segment_reads,
       ds.last_columnstore_segment_skips,
       ds.last_spills
FROM starter AS st
JOIN sys.dm_exec_query_stats AS ds
ON ds.last_execution_time 
    BETWEEN st.last_execution_time AND st.last_execution_end_time
CROSS APPLY sys.dm_exec_sql_text(ds.plan_handle) AS tx
CROSS APPLY sys.dm_exec_query_plan(plan_handle) AS qp
WHERE qp.dbid = DB_ID(@DatabaseName)
ORDER BY ds.last_execution_time;
GO 

/*
SELECT * 
FROM dbo.OverlappingPlans('2019-02-09 14:30:00.003', 
                          '2019-02-09 14:45:00.997', 
						  'StackOverflow2010')
*/