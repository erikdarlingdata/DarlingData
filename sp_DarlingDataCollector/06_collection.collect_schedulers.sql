SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('collection.collect_schedulers', 'P') IS NULL
BEGIN
    EXECUTE ('CREATE PROCEDURE collection.collect_schedulers AS RETURN 0;');
END;
GO

/*
/**************************************************************
* 
* Schedulers Collection Procedure for DarlingDataCollector
* 
* Copyright (C) Darling Data, LLC
* 
* Collects scheduler information from sys.dm_os_schedulers
* 
**************************************************************/
*/

CREATE OR ALTER PROCEDURE
    collection.collect_schedulers
(
    @debug BIT = 0 /*Print debugging information*/
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
        Create schedulers table if it doesn't exist
        */
        IF OBJECT_ID('collection.schedulers') IS NULL
        BEGIN
            EXECUTE system.create_collector_table
                @table_name = 'schedulers',
                @debug = @debug;
        END;
        
        /*
        Collect scheduler information
        */
        INSERT
            collection.schedulers
        (
            collection_time,
            scheduler_id,
            cpu_id,
            parent_node_id,
            status,
            is_online,
            is_idle,
            preemptive_switches_count,
            context_switches_count,
            yield_count,
            current_tasks_count,
            runnable_tasks_count,
            current_workers_count,
            active_workers_count,
            work_queue_count,
            pending_disk_io_count,
            load_factor,
            scheduler_total_cpu_usage_ms,
            scheduler_total_scheduler_delay_ms
        )
        SELECT
            collection_time = SYSDATETIME(),
            s.scheduler_id,
            s.cpu_id,
            s.parent_node_id,
            s.status,
            s.is_online,
            s.is_idle,
            s.preemptive_switches_count,
            s.context_switches_count,
            s.yield_count,
            s.current_tasks_count,
            s.runnable_tasks_count,
            s.current_workers_count,
            s.active_workers_count,
            s.work_queue_count,
            s.pending_disk_io_count,
            s.load_factor,
            s.total_cpu_usage_ms,
            s.total_scheduler_delay_ms
        FROM sys.dm_os_schedulers AS s
        WHERE s.scheduler_id < 255; -- Only capture user schedulers, not internal ones
        
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
            'collection.collect_schedulers',
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
                N'Schedulers Collected' AS collection_type,
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
            'collection.collect_schedulers',
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