SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('collection.collect_memory_grants', 'P') IS NULL
BEGIN
    EXECUTE ('CREATE PROCEDURE collection.collect_memory_grants AS RETURN 0;');
END;
GO

/*
/**************************************************************
* 
* Memory Grants Collection Procedure for DarlingDataCollector
* 
* Copyright (C) Darling Data, LLC
* 
* Collects memory grant information from sys.dm_exec_query_memory_grants
* 
**************************************************************/
*/

CREATE OR ALTER PROCEDURE
    collection.collect_memory_grants
(
    @debug BIT = 0, /*Print debugging information*/
    @include_query_text BIT = 1, /*Include query text in the collection*/
    @include_plan_handle BIT = 1, /*Include plan handle in the collection*/
    @min_requested_mb INTEGER = 0 /*Minimum requested memory in MB to include*/
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
    
    BEGIN TRY
        /*
        Create memory_grants table if it doesn't exist
        */
        IF OBJECT_ID('collection.memory_grants') IS NULL
        BEGIN
            CREATE TABLE
                collection.memory_grants
            (
                collection_id BIGINT IDENTITY(1,1) NOT NULL,
                collection_time DATETIME2(7) NOT NULL,
                session_id INTEGER NOT NULL,
                request_id INTEGER NOT NULL,
                scheduler_id INTEGER NULL,
                dop INTEGER NULL,
                request_time DATETIME NULL,
                grant_time DATETIME NULL,
                requested_memory_kb BIGINT NULL,
                granted_memory_kb BIGINT NULL,
                required_memory_kb BIGINT NULL,
                used_memory_kb BIGINT NULL,
                max_used_memory_kb BIGINT NULL,
                ideal_memory_kb BIGINT NULL,
                grant_ratio DECIMAL(5,2) NULL,
                grant_wait_ms BIGINT NULL,
                query_cost FLOAT NULL,
                timeout_sec INTEGER NULL,
                resource_semaphore_id INTEGER NULL,
                pool_id INTEGER NULL,
                is_small BIT NULL,
                plan_handle VARBINARY(64) NULL,
                sql_handle VARBINARY(64) NULL,
                statement_start_offset INTEGER NULL,
                statement_end_offset INTEGER NULL,
                query_text NVARCHAR(MAX) NULL,
                CONSTRAINT pk_memory_grants PRIMARY KEY CLUSTERED (collection_id, session_id, request_id)
            );
            
            IF @debug = 1
            BEGIN
                RAISERROR(N'Created collection.memory_grants table', 0, 1) WITH NOWAIT;
            END;
        END;
        
        /*
        Collect memory grants information
        */
        INSERT
            collection.memory_grants
        (
            collection_time,
            session_id,
            request_id,
            scheduler_id,
            dop,
            request_time,
            grant_time,
            requested_memory_kb,
            granted_memory_kb,
            required_memory_kb,
            used_memory_kb,
            max_used_memory_kb,
            ideal_memory_kb,
            grant_ratio,
            grant_wait_ms,
            query_cost,
            timeout_sec,
            resource_semaphore_id,
            pool_id,
            is_small,
            plan_handle,
            sql_handle,
            statement_start_offset,
            statement_end_offset,
            query_text
        )
        SELECT
            collection_time = SYSDATETIME(),
            mg.session_id,
            mg.request_id,
            mg.scheduler_id,
            mg.dop,
            mg.request_time,
            mg.grant_time,
            mg.requested_memory_kb,
            mg.granted_memory_kb,
            mg.required_memory_kb,
            mg.used_memory_kb,
            mg.max_used_memory_kb,
            mg.ideal_memory_kb,
            grant_ratio = 
                CASE 
                    WHEN mg.requested_memory_kb > 0 
                    THEN CONVERT(DECIMAL(5,2), mg.granted_memory_kb * 1.0 / mg.requested_memory_kb) 
                    ELSE NULL 
                END,
            grant_wait_ms = 
                CASE 
                    WHEN mg.grant_time IS NOT NULL 
                    THEN DATEDIFF(MILLISECOND, mg.request_time, mg.grant_time)
                    ELSE NULL
                END,
            mg.query_cost,
            mg.timeout_sec,
            mg.resource_semaphore_id,
            mg.pool_id,
            mg.is_small,
            plan_handle = CASE WHEN @include_plan_handle = 1 THEN mg.plan_handle ELSE NULL END,
            sql_handle = CASE WHEN @include_query_text = 1 THEN mg.sql_handle ELSE NULL END,
            statement_start_offset = CASE WHEN @include_query_text = 1 THEN mg.statement_start_offset ELSE NULL END,
            statement_end_offset = CASE WHEN @include_query_text = 1 THEN mg.statement_end_offset ELSE NULL END,
            query_text = 
                CASE WHEN @include_query_text = 1 
                    THEN 
                        SUBSTRING(
                            st.text, 
                            (mg.statement_start_offset/2) + 1,
                            ((CASE mg.statement_end_offset
                                WHEN -1 THEN DATALENGTH(st.text)
                                ELSE mg.statement_end_offset
                            END - mg.statement_start_offset)/2) + 1
                        )
                    ELSE NULL 
                END
        FROM sys.dm_exec_query_memory_grants AS mg
        OUTER APPLY sys.dm_exec_sql_text(mg.sql_handle) AS st
        WHERE mg.requested_memory_kb >= @min_requested_mb * 1024;
        
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
            'collection.collect_memory_grants',
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
                N'Memory Grants Collected' AS collection_type,
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
            'collection.collect_memory_grants',
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