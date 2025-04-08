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
    @min_executions INTEGER = 1, /*Minimum number of executions to include*/
    @min_cpu_ms INTEGER = 0, /*Minimum CPU time in milliseconds to include*/
    @min_logical_reads INTEGER = 0, /*Minimum logical reads to include*/
    @min_elapsed_time_ms INTEGER = 0, /*Minimum elapsed time in milliseconds to include*/
    @include_query_text BIT = 1, /*Include procedure text in the collection*/
    @use_database_list BIT = 1, /*Use database list from system.database_collection_config*/
    @include_databases NVARCHAR(MAX) = NULL, /*Optional: Comma-separated list of databases to include*/
    @exclude_databases NVARCHAR(MAX) = NULL, /*Optional: Comma-separated list of databases to exclude*/
    @exclude_system_databases BIT = 1 /*Exclude system databases*/
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
            CREATE TABLE
                collection.procedure_stats
            (
                collection_id BIGINT IDENTITY(1,1) NOT NULL,
                collection_time DATETIME2(7) NOT NULL,
                database_id INTEGER NOT NULL,
                database_name NVARCHAR(128) NOT NULL,
                object_id INTEGER NOT NULL,
                object_name NVARCHAR(386) NULL,
                sql_handle VARBINARY(64) NOT NULL,
                cached_time DATETIME NOT NULL,
                last_execution_time DATETIME NOT NULL,
                execution_count BIGINT NOT NULL,
                total_worker_time BIGINT NOT NULL,
                avg_worker_time BIGINT NULL,
                last_worker_time BIGINT NOT NULL,
                min_worker_time BIGINT NOT NULL,
                max_worker_time BIGINT NOT NULL,
                total_physical_reads BIGINT NOT NULL,
                avg_physical_reads BIGINT NULL,
                last_physical_reads BIGINT NOT NULL,
                min_physical_reads BIGINT NOT NULL,
                max_physical_reads BIGINT NOT NULL,
                total_logical_writes BIGINT NOT NULL,
                avg_logical_writes BIGINT NULL,
                last_logical_writes BIGINT NOT NULL,
                min_logical_writes BIGINT NOT NULL,
                max_logical_writes BIGINT NOT NULL,
                total_logical_reads BIGINT NOT NULL,
                avg_logical_reads BIGINT NULL,
                last_logical_reads BIGINT NOT NULL,
                min_logical_reads BIGINT NOT NULL,
                max_logical_reads BIGINT NOT NULL,
                total_elapsed_time BIGINT NOT NULL,
                avg_elapsed_time BIGINT NULL,
                last_elapsed_time BIGINT NOT NULL,
                min_elapsed_time BIGINT NOT NULL,
                max_elapsed_time BIGINT NOT NULL,
                procedure_text NVARCHAR(MAX) NULL,
                CONSTRAINT pk_procedure_stats PRIMARY KEY CLUSTERED (collection_id, database_id, object_id)
            );
            
            IF @debug = 1
            BEGIN
                RAISERROR(N'Created collection.procedure_stats table', 0, 1) WITH NOWAIT;
            END;
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
        Collect procedure stats information
        */
        INSERT
            collection.procedure_stats
        (
            collection_time,
            database_id,
            database_name,
            object_id,
            object_name,
            sql_handle,
            cached_time,
            last_execution_time,
            execution_count,
            total_worker_time,
            avg_worker_time,
            last_worker_time,
            min_worker_time,
            max_worker_time,
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
            total_elapsed_time,
            avg_elapsed_time,
            last_elapsed_time,
            min_elapsed_time,
            max_elapsed_time,
            procedure_text
        )
        SELECT
            collection_time = SYSDATETIME(),
            ps.database_id,
            database_name = DB_NAME(ps.database_id),
            ps.object_id,
            object_name = 
                QUOTENAME(OBJECT_SCHEMA_NAME(ps.object_id, ps.database_id)) + N'.' + 
                QUOTENAME(OBJECT_NAME(ps.object_id, ps.database_id)),
            ps.sql_handle,
            ps.cached_time,
            ps.last_execution_time,
            ps.execution_count,
            ps.total_worker_time,
            avg_worker_time = ps.total_worker_time / ps.execution_count,
            ps.last_worker_time,
            ps.min_worker_time,
            ps.max_worker_time,
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
            ps.total_elapsed_time,
            avg_elapsed_time = ps.total_elapsed_time / ps.execution_count,
            ps.last_elapsed_time,
            ps.min_elapsed_time,
            ps.max_elapsed_time,
            procedure_text = 
                CASE WHEN @include_query_text = 1 
                    THEN st.text
                    ELSE NULL 
                END
        FROM sys.dm_exec_procedure_stats AS ps
        OUTER APPLY sys.dm_exec_sql_text(ps.sql_handle) AS st
        WHERE ps.execution_count >= @min_executions
        AND ps.total_worker_time >= @min_cpu_ms * 1000
        AND ps.total_logical_reads >= @min_logical_reads
        AND ps.total_elapsed_time >= @min_elapsed_time_ms * 1000
        AND 
        (
            -- Use include list if specified
            (
                EXISTS (SELECT 1 FROM @include_database_list)
                AND DB_NAME(ps.database_id) IN (SELECT database_name FROM @include_database_list)
            )
            OR 
            (
                -- Otherwise use all databases except excluded ones
                NOT EXISTS (SELECT 1 FROM @include_database_list)
                AND 
                (
                    -- Skip system databases if specified
                    (@exclude_system_databases = 0 OR ps.database_id > 4)
                    -- Skip excluded databases
                    AND DB_NAME(ps.database_id) NOT IN (SELECT database_name FROM @exclude_database_list)
                )
            )
        );
        
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