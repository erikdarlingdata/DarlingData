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
        Create waiting_tasks table if it doesn't exist and we're collecting waiting tasks
        */
        IF @collect_waiting_tasks = 1 AND OBJECT_ID('collection.waiting_tasks') IS NULL
        BEGIN
            CREATE TABLE
                collection.waiting_tasks
            (
                collection_id BIGINT IDENTITY(1,1) NOT NULL,
                collection_time DATETIME2(7) NOT NULL,
                session_id INTEGER NOT NULL,
                waiting_task_address VARBINARY(8) NOT NULL,
                blocking_session_id INTEGER NULL,
                blocking_task_address VARBINARY(8) NULL,
                blocking_exec_context_id INTEGER NULL,
                wait_type NVARCHAR(60) NULL,
                wait_duration_ms BIGINT NULL,
                resource_description NVARCHAR(3072) NULL,
                wait_resource NVARCHAR(256) NULL,
                wait_duration_seconds DECIMAL(18, 2) NULL,
                database_id INTEGER NULL,
                database_name NVARCHAR(128) NULL,
                login_name NVARCHAR(128) NULL,
                program_name NVARCHAR(128) NULL,
                host_name NVARCHAR(128) NULL,
                transaction_name NVARCHAR(32) NULL,
                transaction_isolation_level NVARCHAR(32) NULL,
                wait_query_text NVARCHAR(MAX) NULL,
                CONSTRAINT pk_waiting_tasks PRIMARY KEY CLUSTERED (collection_id, session_id, waiting_task_address)
            );
            
            IF @debug = 1
            BEGIN
                RAISERROR(N'Created collection.waiting_tasks table', 0, 1) WITH NOWAIT;
            END;
        END;
        
        /*
        Create session_wait_stats table if it doesn't exist and we're collecting session wait stats
        */
        IF @collect_session_waits = 1 AND OBJECT_ID('collection.session_wait_stats') IS NULL
        BEGIN
            CREATE TABLE
                collection.session_wait_stats
            (
                collection_id BIGINT IDENTITY(1,1) NOT NULL,
                collection_time DATETIME2(7) NOT NULL,
                session_id INTEGER NOT NULL,
                wait_type NVARCHAR(60) NOT NULL,
                waiting_tasks_count BIGINT NOT NULL,
                wait_time_ms BIGINT NOT NULL,
                max_wait_time_ms BIGINT NOT NULL,
                signal_wait_time_ms BIGINT NOT NULL,
                login_name NVARCHAR(128) NULL,
                program_name NVARCHAR(128) NULL,
                host_name NVARCHAR(128) NULL,
                database_id INTEGER NULL,
                database_name NVARCHAR(128) NULL,
                CONSTRAINT pk_session_wait_stats PRIMARY KEY CLUSTERED (collection_id, session_id, wait_type)
            );
            
            IF @debug = 1
            BEGIN
                RAISERROR(N'Created collection.session_wait_stats table', 0, 1) WITH NOWAIT;
            END;
        END;
        
        /*
        Collect waiting tasks information if enabled
        */
        IF @collect_waiting_tasks = 1
        BEGIN
            INSERT
                collection.waiting_tasks
            (
                collection_time,
                session_id,
                waiting_task_address,
                blocking_session_id,
                blocking_task_address,
                blocking_exec_context_id,
                wait_type,
                wait_duration_ms,
                resource_description,
                wait_resource,
                wait_duration_seconds,
                database_id,
                database_name,
                login_name,
                program_name,
                host_name,
                transaction_name,
                transaction_isolation_level,
                wait_query_text
            )
            SELECT
                collection_time = SYSDATETIME(),
                wt.session_id,
                wt.waiting_task_address,
                wt.blocking_session_id,
                wt.blocking_task_address,
                wt.blocking_exec_context_id,
                wt.wait_type,
                wt.wait_duration_ms,
                resource_description = SUBSTRING(wt.resource_description, 1, 3072),
                wait_resource = COALESCE(DB_NAME(ase.wait_resource), ase.wait_resource),
                wait_duration_seconds = wt.wait_duration_ms / 1000.0,
                es.database_id,
                database_name = DB_NAME(es.database_id),
                es.login_name,
                es.program_name,
                es.host_name,
                at.name,
                transaction_isolation_level = 
                    CASE dt.database_transaction_isolation_level
                        WHEN 0 THEN 'Unspecified'
                        WHEN 1 THEN 'ReadUncommitted'
                        WHEN 2 THEN 'ReadCommitted'
                        WHEN 3 THEN 'Repeatable'
                        WHEN 4 THEN 'Serializable'
                        WHEN 5 THEN 'Snapshot'
                        ELSE 'Unknown'
                    END,
                wait_query_text = 
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
                    END
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
                collection.session_wait_stats
            (
                collection_time,
                session_id,
                wait_type,
                waiting_tasks_count,
                wait_time_ms,
                max_wait_time_ms,
                signal_wait_time_ms,
                login_name,
                program_name,
                host_name,
                database_id,
                database_name
            )
            SELECT
                collection_time = SYSDATETIME(),
                sws.session_id,
                sws.wait_type,
                sws.waiting_tasks_count,
                sws.wait_time_ms,
                sws.max_wait_time_ms,
                sws.signal_wait_time_ms,
                es.login_name,
                es.program_name,
                es.host_name,
                es.database_id,
                database_name = DB_NAME(es.database_id)
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