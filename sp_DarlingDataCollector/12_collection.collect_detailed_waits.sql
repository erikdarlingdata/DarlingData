SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('collection.collect_detailed_waits', 'P') IS NULL
BEGIN
    EXECUTE ('CREATE PROCEDURE collection.collect_detailed_waits AS RETURN 0;');
END;
GO

/*
/**************************************************************
* 
* Detailed Waits Collection Procedure for DarlingDataCollector
* 
* Copyright (C) Darling Data, LLC
* 
* Collects detailed wait information from
* sys.dm_os_waiting_tasks
* sys.dm_exec_session_wait_stats
* 
**************************************************************/
*/

CREATE OR ALTER PROCEDURE
    collection.collect_detailed_waits
(
    @debug BIT = 0, /*Print debugging information*/
    @include_query_text BIT = 1, /*Include query text for waiting tasks*/
    @min_wait_time_ms INTEGER = 0, /*Minimum wait time in milliseconds to include*/
    @collect_waiting_tasks BIT = 1, /*Collect from dm_os_waiting_tasks*/
    @collect_session_waits BIT = 1 /*Collect from dm_exec_session_wait_stats*/
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
        Create the collection table if it doesn't exist
        */
        IF OBJECT_ID('collection.detailed_waits') IS NULL
        BEGIN
            EXECUTE system.create_collector_table
                @table_name = 'detailed_waits',
                @debug = @debug;
        END;
        
        /*
        Collect waiting tasks information if enabled
        */
        IF @collect_waiting_tasks = 1
        BEGIN
            INSERT
                collection.detailed_waits
            (
                collection_time,
                session_id,
                wait_type,
                wait_duration_ms,
                resource_description,
                blocking_session_id,
                blocking_exec_context_id,
                resource_address,
                sql_text,
                database_name,
                wait_resource_type
            )
            SELECT
                collection_time = SYSDATETIME(),
                wt.session_id,
                wt.wait_type,
                wt.wait_duration_ms,
                resource_description = SUBSTRING(wt.resource_description, 1, 3072),
                wt.blocking_session_id,
                wt.blocking_exec_context_id,
                wt.waiting_task_address,
                sql_text = 
                    CASE WHEN @include_query_text = 1 
                        THEN 
                            SUBSTRING(
                                er_text.text, 
                                (er.statement_start_offset/2) + 1,
                                ((CASE er.statement_end_offset
                                    WHEN -1 THEN DATALENGTH(er_text.text)
                                    ELSE er.statement_end_offset
                                  END - er.statement_start_offset)/2) + 1
                            )
                        ELSE NULL 
                    END,
                database_name = DB_NAME(es.database_id),
                wait_resource_type = COALESCE(DB_NAME(ase.wait_resource), ase.wait_resource)
            FROM sys.dm_os_waiting_tasks AS wt
            LEFT JOIN sys.dm_exec_sessions AS es
                ON wt.session_id = es.session_id
            LEFT JOIN sys.all_services AS ase
                WITH (NOLOCK) ON wt.resource_description = ase.service_name
            LEFT JOIN sys.dm_tran_session_transactions AS st
                ON wt.session_id = st.session_id
            LEFT JOIN sys.dm_tran_active_transactions AS at
                ON st.transaction_id = at.transaction_id
            LEFT JOIN sys.dm_tran_database_transactions AS dt
                ON at.transaction_id = dt.transaction_id
            LEFT JOIN sys.dm_exec_requests AS er
                ON wt.session_id = er.session_id
            OUTER APPLY sys.dm_exec_sql_text(er.sql_handle) AS er_text
            WHERE wt.session_id > 50 -- Skip system sessions
            AND wt.session_id <> @@SPID -- Skip our own session
            AND wt.wait_duration_ms >= @min_wait_time_ms;
            
            SET @rows_collected = @@ROWCOUNT;
            
            IF @debug = 1
            BEGIN
                RAISERROR(N'Collected %d waiting tasks', 0, 1, @rows_collected) WITH NOWAIT;
            END;
        END;
        
        /*
        Collect session wait stats if enabled
        */
        IF @collect_session_waits = 1
        BEGIN
            INSERT
                collection.detailed_waits
            (
                collection_time,
                session_id,
                wait_type,
                wait_duration_ms,
                database_name,
                sql_text
            )
            SELECT
                collection_time = SYSDATETIME(),
                sws.session_id,
                sws.wait_type,
                sws.wait_time_ms,
                database_name = DB_NAME(es.database_id),
                sql_text = CONCAT('Session wait stat: ', sws.waiting_tasks_count, ' waiting tasks, ',
                                 sws.max_wait_time_ms, ' ms max wait, ',
                                 sws.signal_wait_time_ms, ' ms signal wait')
            FROM sys.dm_exec_session_wait_stats AS sws
            LEFT JOIN sys.dm_exec_sessions AS es
                ON sws.session_id = es.session_id
            WHERE sws.session_id > 50 -- Skip system sessions
            AND sws.session_id <> @@SPID -- Skip our own session
            AND sws.wait_time_ms >= @min_wait_time_ms
            AND sws.wait_type NOT IN 
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
            
            SET @rows_collected = @rows_collected + @@ROWCOUNT;
            
            IF @debug = 1
            BEGIN
                RAISERROR(N'Collected %d session wait stats', 0, 1, @@ROWCOUNT) WITH NOWAIT;
            END;
        END;
        
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
            'collection.collect_detailed_waits',
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
                N'Detailed Waits Collected' AS collection_type,
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
            'collection.collect_detailed_waits',
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