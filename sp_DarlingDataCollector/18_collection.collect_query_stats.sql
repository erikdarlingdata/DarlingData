/*
 ██████╗ ██╗   ██╗███████╗██████╗ ██╗   ██╗    ███████╗████████╗ █████╗ ████████╗███████╗     ██████╗ ██████╗ ██╗     ██╗     ███████╗ ██████╗████████╗ ██████╗ ██████╗ 
██╔═══██╗██║   ██║██╔════╝██╔══██╗╚██╗ ██╔╝    ██╔════╝╚══██╔══╝██╔══██╗╚══██╔══╝██╔════╝    ██╔════╝██╔═══██╗██║     ██║     ██╔════╝██╔════╝╚══██╔══╝██╔═══██╗██╔══██╗
██║   ██║██║   ██║█████╗  ██████╔╝ ╚████╔╝     ███████╗   ██║   ███████║   ██║   ███████╗    ██║     ██║   ██║██║     ██║     █████╗  ██║        ██║   ██║   ██║██████╔╝
██║▄▄ ██║██║   ██║██╔══╝  ██╔══██╗  ╚██╔╝      ╚════██║   ██║   ██╔══██║   ██║   ╚════██║    ██║     ██║   ██║██║     ██║     ██╔══╝  ██║        ██║   ██║   ██║██╔══██╗
╚██████╔╝╚██████╔╝███████╗██║  ██║   ██║       ███████║   ██║   ██║  ██║   ██║   ███████║    ╚██████╗╚██████╔╝███████╗███████╗███████╗╚██████╗   ██║   ╚██████╔╝██║  ██║
 ╚══▀▀═╝  ╚═════╝ ╚══════╝╚═╝  ╚═╝   ╚═╝       ╚══════╝   ╚═╝   ╚═╝  ╚═╝   ╚═╝   ╚══════╝     ╚═════╝ ╚═════╝ ╚══════╝╚══════╝╚══════╝ ╚═════╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝
                                                                                                                                                                          
Copyright (c) Darling Data, LLC
https://www.erikdarling.com/

--===== QUERY STATS COLLECTOR NOTES ====--
This procedure collects query performance metrics from the plan cache.
It captures metrics for ad-hoc queries, stored procedures, functions, and triggers.
You can collect point-in-time statistics or gather delta values over a specified period.
*/

CREATE OR ALTER PROCEDURE
    collection.collect_query_stats
(
    @debug BIT = 0, /*Print debugging information*/
    @sample_seconds INTEGER = NULL, /*Optional: Collect sample over time period*/
    @collect_query_text BIT = 1, /*Collect query text*/
    @collect_query_plan BIT = 0, /*Collect query plans (can be expensive)*/
    @min_executions INTEGER = 2, /*Minimum executions to collect*/
    @min_worker_time_ms INTEGER = 1000, /*Minimum worker time in milliseconds*/
    @collect_procedure_stats BIT = 1, /*Collect stored procedure statistics*/
    @collect_trigger_stats BIT = 1, /*Collect trigger statistics*/
    @collect_function_stats BIT = 1, /*Collect function statistics*/
    @engine_edition INTEGER = NULL /*Engine edition override for testing*/
)
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
    
    DECLARE
        @collection_start DATETIME2(7) = SYSDATETIME(),
        @collection_end DATETIME2(7),
        @rows_collected BIGINT = 0,
        @error_number INTEGER,
        @error_message NVARCHAR(4000),
        @sql NVARCHAR(MAX),
        @has_query_spill_column BIT = 0,
        @has_function_stats BIT = 0,
        @has_trigger_stats BIT = 0,
        @server_name NVARCHAR(256),
        @is_azure_mi BIT,
        @is_aws_rds BIT;
    
    BEGIN TRY
        /*
        Detect environment
        */
        IF @engine_edition IS NULL
        BEGIN
            SELECT
                @engine_edition = CONVERT(INTEGER, SERVERPROPERTY('EngineEdition')),
                @server_name = CONVERT(NVARCHAR(256), SERVERPROPERTY('ServerName'));
        END;
        
        -- Azure SQL MI has EngineEdition = 8
        SET @is_azure_mi = CASE WHEN @engine_edition = 8 THEN 1 ELSE 0 END;
        
        -- AWS RDS detection using the presence of rdsadmin database
        SET @is_aws_rds = CASE
            WHEN DB_ID('rdsadmin') IS NOT NULL THEN 1
            ELSE 0
        END;
        
        /*
        Check for feature availability based on SQL Server version
        */
        
        -- Check for total_spills column availability (SQL Server 2017+)
        IF EXISTS
        (
            SELECT 1
            FROM sys.dm_exec_query_stats
            WHERE total_spills IS NOT NULL
        )
        BEGIN
            SET @has_query_spill_column = 1;
        END;
        
        -- Check for function stats availability (SQL Server 2016+)
        IF @collect_function_stats = 1 
        AND OBJECT_ID('sys.dm_exec_function_stats') IS NOT NULL
        BEGIN
            SET @has_function_stats = 1;
        END;
        
        -- Check for trigger stats availability (SQL Server 2016+)
        IF @collect_trigger_stats = 1 
        AND EXISTS (SELECT 1 FROM sys.all_objects WHERE name = 'dm_exec_trigger_stats' AND type = 'V')
        BEGIN
            SET @has_trigger_stats = 1;
        END;
        
        /*
        If sampling is requested, collect first sample
        */
        IF @sample_seconds IS NOT NULL
        BEGIN
            /*
            Create temporary table for collecting query stats samples
            */
            CREATE TABLE
                #query_stats_before
            (
                sql_handle VARBINARY(64) NOT NULL,
                plan_handle VARBINARY(64) NOT NULL,
                statement_start_offset INTEGER NOT NULL,
                statement_end_offset INTEGER NOT NULL,
                execution_count BIGINT NOT NULL,
                total_worker_time BIGINT NOT NULL,
                total_physical_reads BIGINT NOT NULL,
                total_logical_reads BIGINT NOT NULL,
                total_logical_writes BIGINT NOT NULL,
                total_elapsed_time BIGINT NOT NULL,
                total_spills BIGINT NULL,
                object_type CHAR(2) NULL, -- QS, PS, FS, TS for query, proc, function, trigger
                object_id INTEGER NULL,
                database_id INTEGER NULL,
                object_name NVARCHAR(386) NULL,
                PRIMARY KEY 
                (
                    sql_handle, 
                    plan_handle,
                    statement_start_offset,
                    statement_end_offset,
                    ISNULL(object_type, 'QS')
                )
            );
            
            /*
            Collect first sample - Query Stats
            */
            IF @has_query_spill_column = 1
            BEGIN
                INSERT
                    #query_stats_before
                (
                    sql_handle,
                    plan_handle,
                    statement_start_offset,
                    statement_end_offset,
                    execution_count,
                    total_worker_time,
                    total_physical_reads,
                    total_logical_reads,
                    total_logical_writes,
                    total_elapsed_time,
                    total_spills,
                    object_type
                )
                SELECT
                    sql_handle,
                    plan_handle,
                    statement_start_offset,
                    statement_end_offset,
                    execution_count,
                    total_worker_time,
                    total_physical_reads,
                    total_logical_reads,
                    total_logical_writes,
                    total_elapsed_time,
                    total_spills,
                    object_type = 'QS'
                FROM sys.dm_exec_query_stats
                WHERE execution_count >= @min_executions
                AND total_worker_time >= (@min_worker_time_ms * 1000);
            END;
            ELSE
            BEGIN
                INSERT
                    #query_stats_before
                (
                    sql_handle,
                    plan_handle,
                    statement_start_offset,
                    statement_end_offset,
                    execution_count,
                    total_worker_time,
                    total_physical_reads,
                    total_logical_reads,
                    total_logical_writes,
                    total_elapsed_time,
                    total_spills,
                    object_type
                )
                SELECT
                    sql_handle,
                    plan_handle,
                    statement_start_offset,
                    statement_end_offset,
                    execution_count,
                    total_worker_time,
                    total_physical_reads,
                    total_logical_reads,
                    total_logical_writes,
                    total_elapsed_time,
                    NULL AS total_spills,
                    object_type = 'QS'
                FROM sys.dm_exec_query_stats
                WHERE execution_count >= @min_executions
                AND total_worker_time >= (@min_worker_time_ms * 1000);
            END;
            
            /*
            Collect first sample - Procedure Stats
            */
            IF @collect_procedure_stats = 1
            BEGIN
                INSERT
                    #query_stats_before
                (
                    sql_handle,
                    plan_handle,
                    statement_start_offset,
                    statement_end_offset,
                    execution_count,
                    total_worker_time,
                    total_physical_reads,
                    total_logical_reads,
                    total_logical_writes,
                    total_elapsed_time,
                    total_spills,
                    object_type,
                    object_id,
                    database_id,
                    object_name
                )
                SELECT
                    sql_handle,
                    plan_handle,
                    0 AS statement_start_offset, -- Proc stats don't have this
                    0 AS statement_end_offset,  -- Proc stats don't have this
                    execution_count,
                    total_worker_time,
                    total_physical_reads,
                    total_logical_reads,
                    total_logical_writes,
                    total_elapsed_time,
                    NULL AS total_spills,
                    object_type = 'PS',
                    object_id,
                    database_id,
                    object_name = QUOTENAME(DB_NAME(database_id)) + '.' + 
                                  QUOTENAME(OBJECT_SCHEMA_NAME(object_id, database_id)) + '.' +
                                  QUOTENAME(OBJECT_NAME(object_id, database_id))
                FROM sys.dm_exec_procedure_stats
                WHERE execution_count >= @min_executions
                AND total_worker_time >= (@min_worker_time_ms * 1000);
            END;
            
            /*
            Collect first sample - Function Stats
            */
            IF @has_function_stats = 1
            BEGIN
                INSERT
                    #query_stats_before
                (
                    sql_handle,
                    plan_handle,
                    statement_start_offset,
                    statement_end_offset,
                    execution_count,
                    total_worker_time,
                    total_physical_reads,
                    total_logical_reads,
                    total_logical_writes,
                    total_elapsed_time,
                    total_spills,
                    object_type,
                    object_id,
                    database_id,
                    object_name
                )
                SELECT
                    sql_handle,
                    plan_handle,
                    0 AS statement_start_offset,
                    0 AS statement_end_offset,
                    execution_count,
                    total_worker_time,
                    total_physical_reads,
                    total_logical_reads,
                    total_logical_writes,
                    total_elapsed_time,
                    NULL AS total_spills,
                    object_type = 'FS',
                    object_id,
                    database_id,
                    object_name = QUOTENAME(DB_NAME(database_id)) + '.' + 
                                  QUOTENAME(OBJECT_SCHEMA_NAME(object_id, database_id)) + '.' +
                                  QUOTENAME(OBJECT_NAME(object_id, database_id))
                FROM sys.dm_exec_function_stats
                WHERE execution_count >= @min_executions
                AND total_worker_time >= (@min_worker_time_ms * 1000);
            END;
            
            /*
            Collect first sample - Trigger Stats
            */
            IF @has_trigger_stats = 1
            BEGIN
                INSERT
                    #query_stats_before
                (
                    sql_handle,
                    plan_handle,
                    statement_start_offset,
                    statement_end_offset,
                    execution_count,
                    total_worker_time,
                    total_physical_reads,
                    total_logical_reads,
                    total_logical_writes,
                    total_elapsed_time,
                    total_spills,
                    object_type,
                    object_id,
                    database_id,
                    object_name
                )
                SELECT
                    sql_handle,
                    plan_handle,
                    0 AS statement_start_offset,
                    0 AS statement_end_offset,
                    execution_count,
                    total_worker_time,
                    total_physical_reads,
                    total_logical_reads,
                    total_logical_writes,
                    total_elapsed_time,
                    NULL AS total_spills,
                    object_type = 'TS',
                    object_id,
                    database_id,
                    object_name = QUOTENAME(DB_NAME(database_id)) + '.' + 
                                  QUOTENAME(OBJECT_SCHEMA_NAME(object_id, database_id)) + '.' +
                                  QUOTENAME(OBJECT_NAME(object_id, database_id))
                FROM sys.dm_exec_trigger_stats
                WHERE execution_count >= @min_executions
                AND total_worker_time >= (@min_worker_time_ms * 1000);
            END;
            
            /*
            Wait for the specified sample period
            */
            WAITFOR DELAY CONVERT(CHAR(8), DATEADD(SECOND, @sample_seconds, 0), 114);
            
            /*
            Insert data with delta values - QUERY STATS
            */
            IF @has_query_spill_column = 1
            BEGIN
                INSERT
                    collection.query_stats
                (
                    collection_time,
                    server_name,
                    sql_handle,
                    plan_handle,
                    query_hash,
                    query_plan_hash,
                    statement_start_offset,
                    statement_end_offset,
                    execution_count,
                    total_worker_time,
                    total_physical_reads,
                    total_logical_reads,
                    total_logical_writes,
                    total_elapsed_time,
                    total_spills,
                    creation_time,
                    last_execution_time,
                    execution_count_delta,
                    total_worker_time_delta,
                    total_physical_reads_delta,
                    total_logical_reads_delta,
                    total_logical_writes_delta,
                    total_elapsed_time_delta,
                    total_spills_delta,
                    sample_seconds,
                    object_type,
                    object_name,
                    database_id,
                    database_name,
                    query_text,
                    query_plan
                )
                SELECT
                    collection_time = SYSDATETIME(),
                    server_name = @server_name,
                    qs.sql_handle,
                    qs.plan_handle,
                    qs.query_hash,
                    qs.query_plan_hash,
                    qs.statement_start_offset,
                    qs.statement_end_offset,
                    qs.execution_count,
                    qs.total_worker_time,
                    qs.total_physical_reads,
                    qs.total_logical_reads,
                    qs.total_logical_writes,
                    qs.total_elapsed_time,
                    qs.total_spills,
                    qs.creation_time,
                    qs.last_execution_time,
                    execution_count_delta = qs.execution_count - qsb.execution_count,
                    total_worker_time_delta = qs.total_worker_time - qsb.total_worker_time,
                    total_physical_reads_delta = qs.total_physical_reads - qsb.total_physical_reads,
                    total_logical_reads_delta = qs.total_logical_reads - qsb.total_logical_reads,
                    total_logical_writes_delta = qs.total_logical_writes - qsb.total_logical_writes,
                    total_elapsed_time_delta = qs.total_elapsed_time - qsb.total_elapsed_time,
                    total_spills_delta = qs.total_spills - qsb.total_spills,
                    sample_seconds = @sample_seconds,
                    object_type = 'Query',
                    object_name = NULL,
                    database_id = 
                        CASE
                            WHEN qs.sql_handle IS NOT NULL
                            THEN DB_ID(PARSENAME(DB_NAME(CONVERT(smallint, 
                                SUBSTRING(qs.sql_handle, 6, 2))), 3))
                            ELSE NULL
                        END,
                    database_name = 
                        CASE
                            WHEN qs.sql_handle IS NOT NULL
                            THEN DB_NAME(CONVERT(smallint, 
                                SUBSTRING(qs.sql_handle, 6, 2)))
                            ELSE NULL
                        END,
                    query_text = 
                        CASE
                            WHEN @collect_query_text = 1
                            THEN (
                                SELECT
                                    text = 
                                        SUBSTRING
                                        (
                                            st.text,
                                            (qs.statement_start_offset / 2) + 1,
                                            CASE
                                                WHEN qs.statement_end_offset = -1 
                                                THEN LEN(CONVERT(nvarchar(max), st.text)) * 2
                                                ELSE (qs.statement_end_offset - qs.statement_start_offset) / 2
                                            END
                                        )
                                FROM sys.dm_exec_sql_text(qs.sql_handle) AS st
                            )
                            ELSE NULL
                        END,
                    query_plan = 
                        CASE
                            WHEN @collect_query_plan = 1
                            THEN (
                                SELECT
                                    query_plan
                                FROM sys.dm_exec_query_plan(qs.plan_handle)
                            )
                            ELSE NULL
                        END
                FROM sys.dm_exec_query_stats AS qs
                JOIN #query_stats_before AS qsb
                  ON qs.sql_handle = qsb.sql_handle
                  AND qs.plan_handle = qsb.plan_handle
                  AND qs.statement_start_offset = qsb.statement_start_offset
                  AND qs.statement_end_offset = qsb.statement_end_offset
                  AND qsb.object_type = 'QS'
                WHERE (qs.execution_count - qsb.execution_count) > 0
                AND qs.execution_count >= @min_executions
                AND qs.total_worker_time >= (@min_worker_time_ms * 1000);
            END;
            ELSE
            BEGIN
                INSERT
                    collection.query_stats
                (
                    collection_time,
                    server_name,
                    sql_handle,
                    plan_handle,
                    query_hash,
                    query_plan_hash,
                    statement_start_offset,
                    statement_end_offset,
                    execution_count,
                    total_worker_time,
                    total_physical_reads,
                    total_logical_reads,
                    total_logical_writes,
                    total_elapsed_time,
                    creation_time,
                    last_execution_time,
                    execution_count_delta,
                    total_worker_time_delta,
                    total_physical_reads_delta,
                    total_logical_reads_delta,
                    total_logical_writes_delta,
                    total_elapsed_time_delta,
                    sample_seconds,
                    object_type,
                    object_name,
                    database_id,
                    database_name,
                    query_text,
                    query_plan
                )
                SELECT
                    collection_time = SYSDATETIME(),
                    server_name = @server_name,
                    qs.sql_handle,
                    qs.plan_handle,
                    qs.query_hash,
                    qs.query_plan_hash,
                    qs.statement_start_offset,
                    qs.statement_end_offset,
                    qs.execution_count,
                    qs.total_worker_time,
                    qs.total_physical_reads,
                    qs.total_logical_reads,
                    qs.total_logical_writes,
                    qs.total_elapsed_time,
                    qs.creation_time,
                    qs.last_execution_time,
                    execution_count_delta = qs.execution_count - qsb.execution_count,
                    total_worker_time_delta = qs.total_worker_time - qsb.total_worker_time,
                    total_physical_reads_delta = qs.total_physical_reads - qsb.total_physical_reads,
                    total_logical_reads_delta = qs.total_logical_reads - qsb.total_logical_reads,
                    total_logical_writes_delta = qs.total_logical_writes - qsb.total_logical_writes,
                    total_elapsed_time_delta = qs.total_elapsed_time - qsb.total_elapsed_time,
                    sample_seconds = @sample_seconds,
                    object_type = 'Query',
                    object_name = NULL,
                    database_id = 
                        CASE
                            WHEN qs.sql_handle IS NOT NULL
                            THEN DB_ID(PARSENAME(DB_NAME(CONVERT(smallint, 
                                SUBSTRING(qs.sql_handle, 6, 2))), 3))
                            ELSE NULL
                        END,
                    database_name = 
                        CASE
                            WHEN qs.sql_handle IS NOT NULL
                            THEN DB_NAME(CONVERT(smallint, 
                                SUBSTRING(qs.sql_handle, 6, 2)))
                            ELSE NULL
                        END,
                    query_text = 
                        CASE
                            WHEN @collect_query_text = 1
                            THEN (
                                SELECT
                                    text = 
                                        SUBSTRING
                                        (
                                            st.text,
                                            (qs.statement_start_offset / 2) + 1,
                                            CASE
                                                WHEN qs.statement_end_offset = -1 
                                                THEN LEN(CONVERT(nvarchar(max), st.text)) * 2
                                                ELSE (qs.statement_end_offset - qs.statement_start_offset) / 2
                                            END
                                        )
                                FROM sys.dm_exec_sql_text(qs.sql_handle) AS st
                            )
                            ELSE NULL
                        END,
                    query_plan = 
                        CASE
                            WHEN @collect_query_plan = 1
                            THEN (
                                SELECT
                                    query_plan
                                FROM sys.dm_exec_query_plan(qs.plan_handle)
                            )
                            ELSE NULL
                        END
                FROM sys.dm_exec_query_stats AS qs
                JOIN #query_stats_before AS qsb
                  ON qs.sql_handle = qsb.sql_handle
                  AND qs.plan_handle = qsb.plan_handle
                  AND qs.statement_start_offset = qsb.statement_start_offset
                  AND qs.statement_end_offset = qsb.statement_end_offset
                  AND qsb.object_type = 'QS'
                WHERE (qs.execution_count - qsb.execution_count) > 0
                AND qs.execution_count >= @min_executions
                AND qs.total_worker_time >= (@min_worker_time_ms * 1000);
            END;
            
            /*
            Insert data with delta values - PROCEDURE STATS
            */
            IF @collect_procedure_stats = 1
            BEGIN
                INSERT
                    collection.query_stats
                (
                    collection_time,
                    server_name,
                    sql_handle,
                    plan_handle,
                    query_hash,
                    query_plan_hash,
                    statement_start_offset,
                    statement_end_offset,
                    execution_count,
                    total_worker_time,
                    total_physical_reads,
                    total_logical_reads,
                    total_logical_writes,
                    total_elapsed_time,
                    creation_time,
                    last_execution_time,
                    execution_count_delta,
                    total_worker_time_delta,
                    total_physical_reads_delta,
                    total_logical_reads_delta,
                    total_logical_writes_delta,
                    total_elapsed_time_delta,
                    sample_seconds,
                    object_type,
                    object_name,
                    database_id,
                    database_name,
                    query_text,
                    query_plan
                )
                SELECT
                    collection_time = SYSDATETIME(),
                    server_name = @server_name,
                    ps.sql_handle,
                    ps.plan_handle,
                    NULL AS query_hash,
                    NULL AS query_plan_hash,
                    0 AS statement_start_offset,
                    0 AS statement_end_offset,
                    ps.execution_count,
                    ps.total_worker_time,
                    ps.total_physical_reads,
                    ps.total_logical_reads,
                    ps.total_logical_writes,
                    ps.total_elapsed_time,
                    ps.cached_time AS creation_time,
                    ps.last_execution_time,
                    execution_count_delta = ps.execution_count - qsb.execution_count,
                    total_worker_time_delta = ps.total_worker_time - qsb.total_worker_time,
                    total_physical_reads_delta = ps.total_physical_reads - qsb.total_physical_reads,
                    total_logical_reads_delta = ps.total_logical_reads - qsb.total_logical_reads,
                    total_logical_writes_delta = ps.total_logical_writes - qsb.total_logical_writes,
                    total_elapsed_time_delta = ps.total_elapsed_time - qsb.total_elapsed_time,
                    sample_seconds = @sample_seconds,
                    object_type = 'Procedure',
                    object_name = QUOTENAME(DB_NAME(ps.database_id)) + '.' + 
                                  QUOTENAME(OBJECT_SCHEMA_NAME(ps.object_id, ps.database_id)) + '.' +
                                  QUOTENAME(OBJECT_NAME(ps.object_id, ps.database_id)),
                    ps.database_id,
                    database_name = DB_NAME(ps.database_id),
                    query_text = 
                        CASE
                            WHEN @collect_query_text = 1
                            THEN (
                                SELECT
                                    text
                                FROM sys.dm_exec_sql_text(ps.sql_handle)
                            )
                            ELSE NULL
                        END,
                    query_plan = 
                        CASE
                            WHEN @collect_query_plan = 1
                            THEN (
                                SELECT
                                    query_plan
                                FROM sys.dm_exec_query_plan(ps.plan_handle)
                            )
                            ELSE NULL
                        END
                FROM sys.dm_exec_procedure_stats AS ps
                JOIN #query_stats_before AS qsb
                  ON ps.sql_handle = qsb.sql_handle
                  AND ps.plan_handle = qsb.plan_handle
                  AND qsb.object_type = 'PS'
                  AND ps.database_id = qsb.database_id
                  AND ps.object_id = qsb.object_id
                WHERE (ps.execution_count - qsb.execution_count) > 0
                AND ps.execution_count >= @min_executions
                AND ps.total_worker_time >= (@min_worker_time_ms * 1000);
            END;
            
            /*
            Insert data with delta values - FUNCTION STATS
            */
            IF @has_function_stats = 1
            BEGIN
                INSERT
                    collection.query_stats
                (
                    collection_time,
                    server_name,
                    sql_handle,
                    plan_handle,
                    query_hash,
                    query_plan_hash,
                    statement_start_offset,
                    statement_end_offset,
                    execution_count,
                    total_worker_time,
                    total_physical_reads,
                    total_logical_reads,
                    total_logical_writes,
                    total_elapsed_time,
                    creation_time,
                    last_execution_time,
                    execution_count_delta,
                    total_worker_time_delta,
                    total_physical_reads_delta,
                    total_logical_reads_delta,
                    total_logical_writes_delta,
                    total_elapsed_time_delta,
                    sample_seconds,
                    object_type,
                    object_name,
                    database_id,
                    database_name,
                    query_text,
                    query_plan
                )
                SELECT
                    collection_time = SYSDATETIME(),
                    server_name = @server_name,
                    fs.sql_handle,
                    fs.plan_handle,
                    NULL AS query_hash,
                    NULL AS query_plan_hash,
                    0 AS statement_start_offset,
                    0 AS statement_end_offset,
                    fs.execution_count,
                    fs.total_worker_time,
                    fs.total_physical_reads,
                    fs.total_logical_reads,
                    fs.total_logical_writes,
                    fs.total_elapsed_time,
                    fs.cached_time AS creation_time,
                    fs.last_execution_time,
                    execution_count_delta = fs.execution_count - qsb.execution_count,
                    total_worker_time_delta = fs.total_worker_time - qsb.total_worker_time,
                    total_physical_reads_delta = fs.total_physical_reads - qsb.total_physical_reads,
                    total_logical_reads_delta = fs.total_logical_reads - qsb.total_logical_reads,
                    total_logical_writes_delta = fs.total_logical_writes - qsb.total_logical_writes,
                    total_elapsed_time_delta = fs.total_elapsed_time - qsb.total_elapsed_time,
                    sample_seconds = @sample_seconds,
                    object_type = 'Function',
                    object_name = QUOTENAME(DB_NAME(fs.database_id)) + '.' + 
                                  QUOTENAME(OBJECT_SCHEMA_NAME(fs.object_id, fs.database_id)) + '.' +
                                  QUOTENAME(OBJECT_NAME(fs.object_id, fs.database_id)),
                    fs.database_id,
                    database_name = DB_NAME(fs.database_id),
                    query_text = 
                        CASE
                            WHEN @collect_query_text = 1
                            THEN (
                                SELECT
                                    text
                                FROM sys.dm_exec_sql_text(fs.sql_handle)
                            )
                            ELSE NULL
                        END,
                    query_plan = 
                        CASE
                            WHEN @collect_query_plan = 1
                            THEN (
                                SELECT
                                    query_plan
                                FROM sys.dm_exec_query_plan(fs.plan_handle)
                            )
                            ELSE NULL
                        END
                FROM sys.dm_exec_function_stats AS fs
                JOIN #query_stats_before AS qsb
                  ON fs.sql_handle = qsb.sql_handle
                  AND fs.plan_handle = qsb.plan_handle
                  AND qsb.object_type = 'FS'
                  AND fs.database_id = qsb.database_id
                  AND fs.object_id = qsb.object_id
                WHERE (fs.execution_count - qsb.execution_count) > 0
                AND fs.execution_count >= @min_executions
                AND fs.total_worker_time >= (@min_worker_time_ms * 1000);
            END;
            
            /*
            Insert data with delta values - TRIGGER STATS
            */
            IF @has_trigger_stats = 1
            BEGIN
                INSERT
                    collection.query_stats
                (
                    collection_time,
                    server_name,
                    sql_handle,
                    plan_handle,
                    query_hash,
                    query_plan_hash,
                    statement_start_offset,
                    statement_end_offset,
                    execution_count,
                    total_worker_time,
                    total_physical_reads,
                    total_logical_reads,
                    total_logical_writes,
                    total_elapsed_time,
                    creation_time,
                    last_execution_time,
                    execution_count_delta,
                    total_worker_time_delta,
                    total_physical_reads_delta,
                    total_logical_reads_delta,
                    total_logical_writes_delta,
                    total_elapsed_time_delta,
                    sample_seconds,
                    object_type,
                    object_name,
                    database_id,
                    database_name,
                    query_text,
                    query_plan
                )
                SELECT
                    collection_time = SYSDATETIME(),
                    server_name = @server_name,
                    ts.sql_handle,
                    ts.plan_handle,
                    NULL AS query_hash,
                    NULL AS query_plan_hash,
                    0 AS statement_start_offset,
                    0 AS statement_end_offset,
                    ts.execution_count,
                    ts.total_worker_time,
                    ts.total_physical_reads,
                    ts.total_logical_reads,
                    ts.total_logical_writes,
                    ts.total_elapsed_time,
                    ts.cached_time AS creation_time,
                    ts.last_execution_time,
                    execution_count_delta = ts.execution_count - qsb.execution_count,
                    total_worker_time_delta = ts.total_worker_time - qsb.total_worker_time,
                    total_physical_reads_delta = ts.total_physical_reads - qsb.total_physical_reads,
                    total_logical_reads_delta = ts.total_logical_reads - qsb.total_logical_reads,
                    total_logical_writes_delta = ts.total_logical_writes - qsb.total_logical_writes,
                    total_elapsed_time_delta = ts.total_elapsed_time - qsb.total_elapsed_time,
                    sample_seconds = @sample_seconds,
                    object_type = 'Trigger',
                    object_name = QUOTENAME(DB_NAME(ts.database_id)) + '.' + 
                                  QUOTENAME(OBJECT_SCHEMA_NAME(ts.object_id, ts.database_id)) + '.' +
                                  QUOTENAME(OBJECT_NAME(ts.object_id, ts.database_id)),
                    ts.database_id,
                    database_name = DB_NAME(ts.database_id),
                    query_text = 
                        CASE
                            WHEN @collect_query_text = 1
                            THEN (
                                SELECT
                                    text
                                FROM sys.dm_exec_sql_text(ts.sql_handle)
                            )
                            ELSE NULL
                        END,
                    query_plan = 
                        CASE
                            WHEN @collect_query_plan = 1
                            THEN (
                                SELECT
                                    query_plan
                                FROM sys.dm_exec_query_plan(ts.plan_handle)
                            )
                            ELSE NULL
                        END
                FROM sys.dm_exec_trigger_stats AS ts
                JOIN #query_stats_before AS qsb
                  ON ts.sql_handle = qsb.sql_handle
                  AND ts.plan_handle = qsb.plan_handle
                  AND qsb.object_type = 'TS'
                  AND ts.database_id = qsb.database_id
                  AND ts.object_id = qsb.object_id
                WHERE (ts.execution_count - qsb.execution_count) > 0
                AND ts.execution_count >= @min_executions
                AND ts.total_worker_time >= (@min_worker_time_ms * 1000);
            END;
        END;
        ELSE
        BEGIN
            /*
            Collect current query stats without sampling - QUERY STATS
            */
            IF @has_query_spill_column = 1
            BEGIN
                INSERT
                    collection.query_stats
                (
                    collection_time,
                    server_name,
                    sql_handle,
                    plan_handle,
                    query_hash,
                    query_plan_hash,
                    statement_start_offset,
                    statement_end_offset,
                    execution_count,
                    total_worker_time,
                    total_physical_reads,
                    total_logical_reads,
                    total_logical_writes,
                    total_elapsed_time,
                    total_spills,
                    creation_time,
                    last_execution_time,
                    object_type,
                    object_name,
                    database_id,
                    database_name,
                    query_text,
                    query_plan
                )
                SELECT
                    collection_time = SYSDATETIME(),
                    server_name = @server_name,
                    qs.sql_handle,
                    qs.plan_handle,
                    qs.query_hash,
                    qs.query_plan_hash,
                    qs.statement_start_offset,
                    qs.statement_end_offset,
                    qs.execution_count,
                    qs.total_worker_time,
                    qs.total_physical_reads,
                    qs.total_logical_reads,
                    qs.total_logical_writes,
                    qs.total_elapsed_time,
                    qs.total_spills,
                    qs.creation_time,
                    qs.last_execution_time,
                    object_type = 'Query',
                    object_name = NULL,
                    database_id = 
                        CASE
                            WHEN qs.sql_handle IS NOT NULL
                            THEN DB_ID(PARSENAME(DB_NAME(CONVERT(smallint, 
                                SUBSTRING(qs.sql_handle, 6, 2))), 3))
                            ELSE NULL
                        END,
                    database_name = 
                        CASE
                            WHEN qs.sql_handle IS NOT NULL
                            THEN DB_NAME(CONVERT(smallint, 
                                SUBSTRING(qs.sql_handle, 6, 2)))
                            ELSE NULL
                        END,
                    query_text = 
                        CASE
                            WHEN @collect_query_text = 1
                            THEN (
                                SELECT
                                    text = 
                                        SUBSTRING
                                        (
                                            st.text,
                                            (qs.statement_start_offset / 2) + 1,
                                            CASE
                                                WHEN qs.statement_end_offset = -1 
                                                THEN LEN(CONVERT(nvarchar(max), st.text)) * 2
                                                ELSE (qs.statement_end_offset - qs.statement_start_offset) / 2
                                            END
                                        )
                                FROM sys.dm_exec_sql_text(qs.sql_handle) AS st
                            )
                            ELSE NULL
                        END,
                    query_plan = 
                        CASE
                            WHEN @collect_query_plan = 1
                            THEN (
                                SELECT
                                    query_plan
                                FROM sys.dm_exec_query_plan(qs.plan_handle)
                            )
                            ELSE NULL
                        END
                FROM sys.dm_exec_query_stats AS qs
                WHERE qs.execution_count >= @min_executions
                AND qs.total_worker_time >= (@min_worker_time_ms * 1000);
            END;
            ELSE
            BEGIN
                INSERT
                    collection.query_stats
                (
                    collection_time,
                    server_name,
                    sql_handle,
                    plan_handle,
                    query_hash,
                    query_plan_hash,
                    statement_start_offset,
                    statement_end_offset,
                    execution_count,
                    total_worker_time,
                    total_physical_reads,
                    total_logical_reads,
                    total_logical_writes,
                    total_elapsed_time,
                    creation_time,
                    last_execution_time,
                    object_type,
                    object_name,
                    database_id,
                    database_name,
                    query_text,
                    query_plan
                )
                SELECT
                    collection_time = SYSDATETIME(),
                    server_name = @server_name,
                    qs.sql_handle,
                    qs.plan_handle,
                    qs.query_hash,
                    qs.query_plan_hash,
                    qs.statement_start_offset,
                    qs.statement_end_offset,
                    qs.execution_count,
                    qs.total_worker_time,
                    qs.total_physical_reads,
                    qs.total_logical_reads,
                    qs.total_logical_writes,
                    qs.total_elapsed_time,
                    qs.creation_time,
                    qs.last_execution_time,
                    object_type = 'Query',
                    object_name = NULL,
                    database_id = 
                        CASE
                            WHEN qs.sql_handle IS NOT NULL
                            THEN DB_ID(PARSENAME(DB_NAME(CONVERT(smallint, 
                                SUBSTRING(qs.sql_handle, 6, 2))), 3))
                            ELSE NULL
                        END,
                    database_name = 
                        CASE
                            WHEN qs.sql_handle IS NOT NULL
                            THEN DB_NAME(CONVERT(smallint, 
                                SUBSTRING(qs.sql_handle, 6, 2)))
                            ELSE NULL
                        END,
                    query_text = 
                        CASE
                            WHEN @collect_query_text = 1
                            THEN (
                                SELECT
                                    text = 
                                        SUBSTRING
                                        (
                                            st.text,
                                            (qs.statement_start_offset / 2) + 1,
                                            CASE
                                                WHEN qs.statement_end_offset = -1 
                                                THEN LEN(CONVERT(nvarchar(max), st.text)) * 2
                                                ELSE (qs.statement_end_offset - qs.statement_start_offset) / 2
                                            END
                                        )
                                FROM sys.dm_exec_sql_text(qs.sql_handle) AS st
                            )
                            ELSE NULL
                        END,
                    query_plan = 
                        CASE
                            WHEN @collect_query_plan = 1
                            THEN (
                                SELECT
                                    query_plan
                                FROM sys.dm_exec_query_plan(qs.plan_handle)
                            )
                            ELSE NULL
                        END
                FROM sys.dm_exec_query_stats AS qs
                WHERE qs.execution_count >= @min_executions
                AND qs.total_worker_time >= (@min_worker_time_ms * 1000);
            END;
            
            /*
            Collect current procedure stats without sampling
            */
            IF @collect_procedure_stats = 1
            BEGIN
                INSERT
                    collection.query_stats
                (
                    collection_time,
                    server_name,
                    sql_handle,
                    plan_handle,
                    query_hash,
                    query_plan_hash,
                    statement_start_offset,
                    statement_end_offset,
                    execution_count,
                    total_worker_time,
                    total_physical_reads,
                    total_logical_reads,
                    total_logical_writes,
                    total_elapsed_time,
                    creation_time,
                    last_execution_time,
                    object_type,
                    object_name,
                    database_id,
                    database_name,
                    query_text,
                    query_plan
                )
                SELECT
                    collection_time = SYSDATETIME(),
                    server_name = @server_name,
                    ps.sql_handle,
                    ps.plan_handle,
                    NULL AS query_hash,
                    NULL AS query_plan_hash,
                    0 AS statement_start_offset,
                    0 AS statement_end_offset,
                    ps.execution_count,
                    ps.total_worker_time,
                    ps.total_physical_reads,
                    ps.total_logical_reads,
                    ps.total_logical_writes,
                    ps.total_elapsed_time,
                    ps.cached_time AS creation_time,
                    ps.last_execution_time,
                    object_type = 'Procedure',
                    object_name = QUOTENAME(DB_NAME(ps.database_id)) + '.' + 
                                  QUOTENAME(OBJECT_SCHEMA_NAME(ps.object_id, ps.database_id)) + '.' +
                                  QUOTENAME(OBJECT_NAME(ps.object_id, ps.database_id)),
                    ps.database_id,
                    database_name = DB_NAME(ps.database_id),
                    query_text = 
                        CASE
                            WHEN @collect_query_text = 1
                            THEN (
                                SELECT
                                    text
                                FROM sys.dm_exec_sql_text(ps.sql_handle)
                            )
                            ELSE NULL
                        END,
                    query_plan = 
                        CASE
                            WHEN @collect_query_plan = 1
                            THEN (
                                SELECT
                                    query_plan
                                FROM sys.dm_exec_query_plan(ps.plan_handle)
                            )
                            ELSE NULL
                        END
                FROM sys.dm_exec_procedure_stats AS ps
                WHERE ps.execution_count >= @min_executions
                AND ps.total_worker_time >= (@min_worker_time_ms * 1000);
            END;
            
            /*
            Collect current function stats without sampling
            */
            IF @has_function_stats = 1
            BEGIN
                INSERT
                    collection.query_stats
                (
                    collection_time,
                    server_name,
                    sql_handle,
                    plan_handle,
                    query_hash,
                    query_plan_hash,
                    statement_start_offset,
                    statement_end_offset,
                    execution_count,
                    total_worker_time,
                    total_physical_reads,
                    total_logical_reads,
                    total_logical_writes,
                    total_elapsed_time,
                    creation_time,
                    last_execution_time,
                    object_type,
                    object_name,
                    database_id,
                    database_name,
                    query_text,
                    query_plan
                )
                SELECT
                    collection_time = SYSDATETIME(),
                    server_name = @server_name,
                    fs.sql_handle,
                    fs.plan_handle,
                    NULL AS query_hash,
                    NULL AS query_plan_hash,
                    0 AS statement_start_offset,
                    0 AS statement_end_offset,
                    fs.execution_count,
                    fs.total_worker_time,
                    fs.total_physical_reads,
                    fs.total_logical_reads,
                    fs.total_logical_writes,
                    fs.total_elapsed_time,
                    fs.cached_time AS creation_time,
                    fs.last_execution_time,
                    object_type = 'Function',
                    object_name = QUOTENAME(DB_NAME(fs.database_id)) + '.' + 
                                  QUOTENAME(OBJECT_SCHEMA_NAME(fs.object_id, fs.database_id)) + '.' +
                                  QUOTENAME(OBJECT_NAME(fs.object_id, fs.database_id)),
                    fs.database_id,
                    database_name = DB_NAME(fs.database_id),
                    query_text = 
                        CASE
                            WHEN @collect_query_text = 1
                            THEN (
                                SELECT
                                    text
                                FROM sys.dm_exec_sql_text(fs.sql_handle)
                            )
                            ELSE NULL
                        END,
                    query_plan = 
                        CASE
                            WHEN @collect_query_plan = 1
                            THEN (
                                SELECT
                                    query_plan
                                FROM sys.dm_exec_query_plan(fs.plan_handle)
                            )
                            ELSE NULL
                        END
                FROM sys.dm_exec_function_stats AS fs
                WHERE fs.execution_count >= @min_executions
                AND fs.total_worker_time >= (@min_worker_time_ms * 1000);
            END;
            
            /*
            Collect current trigger stats without sampling
            */
            IF @has_trigger_stats = 1
            BEGIN
                INSERT
                    collection.query_stats
                (
                    collection_time,
                    server_name,
                    sql_handle,
                    plan_handle,
                    query_hash,
                    query_plan_hash,
                    statement_start_offset,
                    statement_end_offset,
                    execution_count,
                    total_worker_time,
                    total_physical_reads,
                    total_logical_reads,
                    total_logical_writes,
                    total_elapsed_time,
                    creation_time,
                    last_execution_time,
                    object_type,
                    object_name,
                    database_id,
                    database_name,
                    query_text,
                    query_plan
                )
                SELECT
                    collection_time = SYSDATETIME(),
                    server_name = @server_name,
                    ts.sql_handle,
                    ts.plan_handle,
                    NULL AS query_hash,
                    NULL AS query_plan_hash,
                    0 AS statement_start_offset,
                    0 AS statement_end_offset,
                    ts.execution_count,
                    ts.total_worker_time,
                    ts.total_physical_reads,
                    ts.total_logical_reads,
                    ts.total_logical_writes,
                    ts.total_elapsed_time,
                    ts.cached_time AS creation_time,
                    ts.last_execution_time,
                    object_type = 'Trigger',
                    object_name = QUOTENAME(DB_NAME(ts.database_id)) + '.' + 
                                  QUOTENAME(OBJECT_SCHEMA_NAME(ts.object_id, ts.database_id)) + '.' +
                                  QUOTENAME(OBJECT_NAME(ts.object_id, ts.database_id)),
                    ts.database_id,
                    database_name = DB_NAME(ts.database_id),
                    query_text = 
                        CASE
                            WHEN @collect_query_text = 1
                            THEN (
                                SELECT
                                    text
                                FROM sys.dm_exec_sql_text(ts.sql_handle)
                            )
                            ELSE NULL
                        END,
                    query_plan = 
                        CASE
                            WHEN @collect_query_plan = 1
                            THEN (
                                SELECT
                                    query_plan
                                FROM sys.dm_exec_query_plan(ts.plan_handle)
                            )
                            ELSE NULL
                        END
                FROM sys.dm_exec_trigger_stats AS ts
                WHERE ts.execution_count >= @min_executions
                AND ts.total_worker_time >= (@min_worker_time_ms * 1000);
            END;
        END;
        
        SET @rows_collected = @@ROWCOUNT;
        SET @collection_end = SYSDATETIME();
        
        /*
        Log collection results
        */
        INSERT
            system.collection_log
        (
            procedure_name,
            collection_start,
            collection_end,
            rows_collected,
            status
        )
        VALUES
        (
            'collection.collect_query_stats',
            @collection_start,
            @collection_end,
            @rows_collected,
            'Success'
        );
        
        /*
        Print debug information
        */
        IF @debug = 1
        BEGIN
            SELECT
                N'Query Stats Collected' AS collection_type,
                @rows_collected AS rows_collected,
                CAST(DATEDIFF(MILLISECOND, @collection_start, @collection_end) / 1000.0 AS DECIMAL(18,2)) AS duration_seconds,
                server_name = @server_name,
                environment = CASE
                                WHEN @is_azure_mi = 1 THEN 'Azure SQL MI'
                                WHEN @is_aws_rds = 1 THEN 'AWS RDS'
                                ELSE 'On-Premises SQL Server'
                              END,
                has_query_spill_column = @has_query_spill_column,
                has_function_stats = @has_function_stats,
                has_trigger_stats = @has_trigger_stats,
                include_procedures = @collect_procedure_stats,
                include_functions = @collect_function_stats,
                include_triggers = @collect_trigger_stats;
        END;
    END TRY
    BEGIN CATCH
        SET @error_number = ERROR_NUMBER();
        SET @error_message = ERROR_MESSAGE();
        
        /*
        Log error
        */
        INSERT
            system.collection_log
        (
            procedure_name,
            collection_start,
            collection_end,
            rows_collected,
            status,
            error_number,
            error_message
        )
        VALUES
        (
            'collection.collect_query_stats',
            @collection_start,
            SYSDATETIME(),
            0,
            'Error',
            @error_number,
            @error_message
        );
        
        /*
        Re-throw error
        */
        THROW;
    END CATCH;
END;
GO