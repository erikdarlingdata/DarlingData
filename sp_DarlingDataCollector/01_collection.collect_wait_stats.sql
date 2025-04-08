SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('collection.collect_wait_stats', 'P') IS NULL
BEGIN
    EXECUTE ('CREATE PROCEDURE collection.collect_wait_stats AS RETURN 0;');
END;
GO

/*
/**************************************************************
* 
* Wait Stats Collection Procedure for DarlingDataCollector
* 
* Copyright (C) Darling Data, LLC
* 
* Collects wait statistics from sys.dm_os_wait_stats
* 
**************************************************************/
*/

CREATE OR ALTER PROCEDURE
    collection.collect_wait_stats
(
    @debug BIT = 0, /*Print debugging information*/
    @sample_seconds INTEGER = NULL /*Optional: Collect sample over time period*/
)
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
    
    DECLARE
        @collection_start DATETIME2(7) = SYSDATETIME(),
        @collection_end DATETIME2(7),
        @rows_collected BIGINT = 0,
        @server_uptime_seconds BIGINT,
        @sql NVARCHAR(MAX) = N'',
        @error_number INTEGER,
        @error_message NVARCHAR(4000);
    
    BEGIN TRY
        /*
        Get SQL Server uptime in seconds
        */
        SELECT
            @server_uptime_seconds = DATEDIFF(SECOND, sqlserver_start_time, GETDATE())
        FROM sys.dm_os_sys_info;
        
        /*
        If sampling is requested, collect first sample
        */
        IF @sample_seconds IS NOT NULL
        BEGIN
            /*
            Create temporary table for collecting wait stats samples
            */
            CREATE TABLE
                #wait_stats_before
            (
                wait_type NVARCHAR(128) NOT NULL,
                waiting_tasks_count BIGINT NOT NULL,
                wait_time_ms BIGINT NOT NULL,
                max_wait_time_ms BIGINT NOT NULL,
                signal_wait_time_ms BIGINT NOT NULL,
                PRIMARY KEY (wait_type)
            );
            
            /*
            Collect first sample
            */
            INSERT
                #wait_stats_before
            (
                wait_type,
                waiting_tasks_count,
                wait_time_ms,
                max_wait_time_ms,
                signal_wait_time_ms
            )
            SELECT
                wait_type,
                waiting_tasks_count,
                wait_time_ms,
                max_wait_time_ms,
                signal_wait_time_ms
            FROM sys.dm_os_wait_stats
            WHERE wait_type NOT IN 
            (
                /* Filter out benign waits */
                N'BROKER_TASK_STOP',
                N'DIRTY_PAGE_POLL',
                N'CLR_AUTO_EVENT',
                N'CLR_MANUAL_EVENT',
                N'CLR_QUANTUM_TASK',
                N'REQUEST_FOR_DEADLOCK_SEARCH',
                N'SLEEP_TASK',
                N'SLEEP_SYSTEMTASK',
                N'SQLTRACE_BUFFER_FLUSH',
                N'WAITFOR',
                N'XE_DISPATCHER_WAIT',
                N'XE_TIMER_EVENT',
                N'LAZYWRITER_SLEEP',
                N'BROKER_EVENTHANDLER',
                N'BROKER_RECEIVE_WAITFOR',
                N'CHECKPOINT_QUEUE',
                N'CHKPT',
                N'HADR_FILESTREAM_IOMGR_IOCOMPLETION'
            );
            
            /*
            Wait for the specified sample period
            */
            WAITFOR DELAY CONVERT(CHAR(8), DATEADD(SECOND, @sample_seconds, 0), 114);
            
            /*
            Insert data with delta values
            */
            INSERT
                collection.wait_stats
            (
                collection_time,
                server_uptime_seconds,
                wait_type,
                waiting_tasks_count,
                wait_time_ms,
                max_wait_time_ms,
                signal_wait_time_ms,
                waiting_tasks_count_delta,
                wait_time_ms_delta,
                max_wait_time_ms_delta,
                signal_wait_time_ms_delta,
                sample_seconds
            )
            SELECT
                collection_time = SYSDATETIME(),
                server_uptime_seconds = @server_uptime_seconds,
                ws.wait_type,
                ws.waiting_tasks_count,
                ws.wait_time_ms,
                ws.max_wait_time_ms,
                ws.signal_wait_time_ms,
                waiting_tasks_count_delta = ws.waiting_tasks_count - wsb.waiting_tasks_count,
                wait_time_ms_delta = ws.wait_time_ms - wsb.wait_time_ms,
                max_wait_time_ms_delta = 
                    CASE 
                        WHEN ws.max_wait_time_ms > wsb.max_wait_time_ms 
                        THEN ws.max_wait_time_ms - wsb.max_wait_time_ms
                        ELSE 0
                    END,
                signal_wait_time_ms_delta = ws.signal_wait_time_ms - wsb.signal_wait_time_ms,
                sample_seconds = @sample_seconds
            FROM sys.dm_os_wait_stats AS ws
            JOIN #wait_stats_before AS wsb
              ON ws.wait_type = wsb.wait_type
            WHERE ws.wait_type NOT IN 
            (
                /* Filter out benign waits */
                N'BROKER_TASK_STOP',
                N'DIRTY_PAGE_POLL',
                N'CLR_AUTO_EVENT',
                N'CLR_MANUAL_EVENT',
                N'CLR_QUANTUM_TASK',
                N'REQUEST_FOR_DEADLOCK_SEARCH',
                N'SLEEP_TASK',
                N'SLEEP_SYSTEMTASK',
                N'SQLTRACE_BUFFER_FLUSH',
                N'WAITFOR',
                N'XE_DISPATCHER_WAIT',
                N'XE_TIMER_EVENT',
                N'LAZYWRITER_SLEEP',
                N'BROKER_EVENTHANDLER',
                N'BROKER_RECEIVE_WAITFOR',
                N'CHECKPOINT_QUEUE',
                N'CHKPT',
                N'HADR_FILESTREAM_IOMGR_IOCOMPLETION'
            );
        END;
        ELSE
        BEGIN
            /*
            Collect current wait stats without sampling
            */
            INSERT
                collection.wait_stats
            (
                collection_time,
                server_uptime_seconds,
                wait_type,
                waiting_tasks_count,
                wait_time_ms,
                max_wait_time_ms,
                signal_wait_time_ms
            )
            SELECT
                collection_time = SYSDATETIME(),
                server_uptime_seconds = @server_uptime_seconds,
                wait_type,
                waiting_tasks_count,
                wait_time_ms,
                max_wait_time_ms,
                signal_wait_time_ms
            FROM sys.dm_os_wait_stats
            WHERE wait_type NOT IN 
            (
                /* Filter out benign waits */
                N'BROKER_TASK_STOP',
                N'DIRTY_PAGE_POLL',
                N'CLR_AUTO_EVENT',
                N'CLR_MANUAL_EVENT',
                N'CLR_QUANTUM_TASK',
                N'REQUEST_FOR_DEADLOCK_SEARCH',
                N'SLEEP_TASK',
                N'SLEEP_SYSTEMTASK',
                N'SQLTRACE_BUFFER_FLUSH',
                N'WAITFOR',
                N'XE_DISPATCHER_WAIT',
                N'XE_TIMER_EVENT',
                N'LAZYWRITER_SLEEP',
                N'BROKER_EVENTHANDLER',
                N'BROKER_RECEIVE_WAITFOR',
                N'CHECKPOINT_QUEUE',
                N'CHKPT',
                N'HADR_FILESTREAM_IOMGR_IOCOMPLETION'
            );
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
            'collection.collect_wait_stats',
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
                N'Wait Stats Collected' AS collection_type,
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
            'collection.collect_wait_stats',
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