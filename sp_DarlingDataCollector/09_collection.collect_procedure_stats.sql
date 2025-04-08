SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('collection.collect_procedure_stats', 'P') IS NULL
BEGIN
    EXECUTE ('CREATE PROCEDURE collection.collect_procedure_stats AS RETURN 0;');
END;
GO

/*
/**************************************************************
* 
* Procedure Stats Collection Procedure for DarlingDataCollector
* 
* Copyright (C) Darling Data, LLC
* 
* Collects stored procedure execution statistics from 
* sys.dm_exec_procedure_stats
* 
**************************************************************/
*/

CREATE OR ALTER PROCEDURE
    collection.collect_procedure_stats
(
    @debug BIT = 0, /*Print debugging information*/
    @use_database_list BIT = 0, /*Use database list from system.database_collection_config*/
    @include_databases NVARCHAR(MAX) = NULL, /*Optional: Comma-separated list of databases to include*/
    @exclude_databases NVARCHAR(MAX) = NULL, /*Optional: Comma-separated list of databases to exclude*/
    @include_system_databases BIT = 0, /*Include system databases*/
    @min_executions INTEGER = 0, /*Minimum number of executions to include*/
    @min_worker_time_ms INTEGER = 0, /*Minimum worker time in milliseconds to include*/
    @min_logical_reads INTEGER = 0, /*Minimum logical reads to include*/
    @min_logical_writes INTEGER = 0, /*Minimum logical writes to include*/
    @min_elapsed_time_ms INTEGER = 0 /*Minimum elapsed time in milliseconds to include*/
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
        @error_message NVARCHAR(4000);
    
    DECLARE
        @include_database_list TABLE
        (
            database_name NVARCHAR(128) NOT NULL PRIMARY KEY
        );
        
    DECLARE
        @exclude_database_list TABLE
        (
            database_name NVARCHAR(128) NOT NULL PRIMARY KEY
        );
    
    BEGIN TRY
        /*
        Create procedure_stats table if it doesn't exist
        */
        IF OBJECT_ID('collection.procedure_stats') IS NULL
        BEGIN
            EXECUTE system.create_collector_table
                @table_name = 'procedure_stats',
                @debug = @debug;
        END;
        
        /*
        Build database lists
        */
        IF @use_database_list = 1
        BEGIN
            INSERT @include_database_list
            (
                database_name
            )
            SELECT
                database_name
            FROM system.database_collection_config
            WHERE collection_type IN (N'PROCEDURE_STATS', N'ALL')
            AND active = 1;
            
            IF @debug = 1
            BEGIN
                SELECT
                    list_source = N'Using configured database list',
                    database_count = COUNT(*)
                FROM @include_database_list;
            END;
        END;
        ELSE IF @include_databases IS NOT NULL
        BEGIN
            INSERT @include_database_list
            (
                database_name
            )
            SELECT
                database_name = LTRIM(RTRIM(value))
            FROM STRING_SPLIT(@include_databases, N',');
            
            IF @debug = 1
            BEGIN
                SELECT
                    list_source = N'Using @include_databases parameter',
                    database_count = COUNT(*)
                FROM @include_database_list;
            END;
        END;
        
        IF @exclude_databases IS NOT NULL
        BEGIN
            INSERT @exclude_database_list
            (
                database_name
            )
            SELECT
                database_name = LTRIM(RTRIM(value))
            FROM STRING_SPLIT(@exclude_databases, N',');
            
            IF @debug = 1
            BEGIN
                SELECT
                    list_source = N'Using @exclude_databases parameter',
                    database_count = COUNT(*)
                FROM @exclude_database_list;
            END;
        END;
        
        /*
        Collect procedure stats
        */
        INSERT
            collection.procedure_stats
        (
            collection_time,
            database_id,
            database_name,
            object_id,
            object_name,
            type,
            cached_time,
            last_execution_time,
            execution_count,
            total_worker_time_ms,
            avg_worker_time_ms,
            last_worker_time_ms,
            min_worker_time_ms,
            max_worker_time_ms,
            total_physical_reads,
            avg_physical_reads,
            last_physical_reads,
            min_physical_reads,
            max_physical_reads,
            total_logical_writes,
            avg_logical_writes,
            last_logical_writes,
            min_logical_writes,
            max_logical_writes,
            total_logical_reads,
            avg_logical_reads,
            last_logical_reads,
            min_logical_reads,
            max_logical_reads,
            total_elapsed_time_ms,
            avg_elapsed_time_ms,
            last_elapsed_time_ms,
            min_elapsed_time_ms,
            max_elapsed_time_ms,
            plan_handle,
            sql_handle
        )
        SELECT
            collection_time = @collection_start,
            ps.database_id,
            database_name = DB_NAME(ps.database_id),
            ps.object_id,
            object_name = QUOTENAME(DB_NAME(ps.database_id)) + '.' + 
                         QUOTENAME(OBJECT_SCHEMA_NAME(ps.object_id, ps.database_id)) + '.' +
                         QUOTENAME(OBJECT_NAME(ps.object_id, ps.database_id)),
            type = 'StoredProcedure',
            ps.cached_time,
            ps.last_execution_time,
            ps.execution_count,
            total_worker_time_ms = ps.total_worker_time / 1000,
            avg_worker_time_ms = ps.total_worker_time / 1000 / ps.execution_count,
            last_worker_time_ms = ps.last_worker_time / 1000,
            min_worker_time_ms = ps.min_worker_time / 1000,
            max_worker_time_ms = ps.max_worker_time / 1000,
            ps.total_physical_reads,
            avg_physical_reads = ps.total_physical_reads / ps.execution_count,
            ps.last_physical_reads,
            ps.min_physical_reads,
            ps.max_physical_reads,
            ps.total_logical_writes,
            avg_logical_writes = ps.total_logical_writes / ps.execution_count,
            ps.last_logical_writes,
            ps.min_logical_writes,
            ps.max_logical_writes,
            ps.total_logical_reads,
            avg_logical_reads = ps.total_logical_reads / ps.execution_count,
            ps.last_logical_reads,
            ps.min_logical_reads,
            ps.max_logical_reads,
            total_elapsed_time_ms = ps.total_elapsed_time / 1000,
            avg_elapsed_time_ms = ps.total_elapsed_time / 1000 / ps.execution_count,
            last_elapsed_time_ms = ps.last_elapsed_time / 1000,
            min_elapsed_time_ms = ps.min_elapsed_time / 1000,
            max_elapsed_time_ms = ps.max_elapsed_time / 1000,
            ps.plan_handle,
            ps.sql_handle
        FROM sys.dm_exec_procedure_stats AS ps
        WHERE ps.database_id > 0
        AND ps.execution_count >= @min_executions
        AND ps.total_worker_time / 1000 >= @min_worker_time_ms
        AND ps.total_logical_reads >= @min_logical_reads
        AND ps.total_logical_writes >= @min_logical_writes
        AND ps.total_elapsed_time / 1000 >= @min_elapsed_time_ms
        AND ((@include_databases IS NULL AND @use_database_list = 0) -- If no includes specified, use all databases
             OR DB_NAME(ps.database_id) IN (SELECT database_name FROM @include_database_list))
        AND ((ps.database_id > 4) OR @include_system_databases = 1) -- User databases or if system databases are included
        AND DB_NAME(ps.database_id) NOT IN (SELECT database_name FROM @exclude_database_list) -- Not in exclude list
        ORDER BY ps.total_worker_time DESC;
        
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
            'collection.collect_procedure_stats',
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
                N'Procedure Stats Collected' AS collection_type,
                @rows_collected AS rows_collected,
                CAST(DATEDIFF(MILLISECOND, @collection_start, @collection_end) / 1000.0 AS DECIMAL(18,2)) AS duration_seconds;
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
            'collection.collect_procedure_stats',
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