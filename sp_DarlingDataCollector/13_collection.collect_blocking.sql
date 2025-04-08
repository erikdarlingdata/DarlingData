/*
██████╗ ██╗      ██████╗  ██████╗██╗  ██╗██╗███╗   ██╗ ██████╗      ██████╗ ██████╗ ██╗     ██╗     ███████╗ ██████╗████████╗ ██████╗ ██████╗ 
██╔══██╗██║     ██╔═══██╗██╔════╝██║ ██╔╝██║████╗  ██║██╔════╝     ██╔════╝██╔═══██╗██║     ██║     ██╔════╝██╔════╝╚══██╔══╝██╔═══██╗██╔══██╗
██████╔╝██║     ██║   ██║██║     █████╔╝ ██║██╔██╗ ██║██║  ███╗    ██║     ██║   ██║██║     ██║     █████╗  ██║        ██║   ██║   ██║██████╔╝
██╔══██╗██║     ██║   ██║██║     ██╔═██╗ ██║██║╚██╗██║██║   ██║    ██║     ██║   ██║██║     ██║     ██╔══╝  ██║        ██║   ██║   ██║██╔══██╗
██████╔╝███████╗╚██████╔╝╚██████╗██║  ██╗██║██║ ╚████║╚██████╔╝    ╚██████╗╚██████╔╝███████╗███████╗███████╗╚██████╗   ██║   ╚██████╔╝██║  ██║
╚═════╝ ╚══════╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝ ╚═════╝      ╚═════╝ ╚═════╝ ╚══════╝╚══════╝╚══════╝ ╚═════╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝
                                                                                                                                              
Copyright (c) Darling Data, LLC
https://www.erikdarling.com/

--===== BLOCKHOUND NOTES ====--
This procedure relies on the blocked process report Extended Event
to capture blocking information. You must configure the blocked process
threshold appropriately for your environment.

For most environments, a value between 5-15 seconds is appropriate:
EXEC sp_configure 'blocked process threshold (s)', 5;
RECONFIGURE;

Note: When this procedure is called for the first time after the DarlingDataCollector
is initialized, it will attempt to create the appropriate Extended Event session
if it doesn't already exist.
*/

CREATE OR ALTER PROCEDURE
    collection.collect_blocking
(
    @debug BIT = 0, /*Print debugging information*/
    @session_name NVARCHAR(128) = N'DarlingDataCollector_Blocking', /*Name of the XE session to create/use*/
    @min_block_duration_ms INTEGER = 1000, /*Minimum blocking duration to collect in milliseconds*/
    @history_start_period_minutes INTEGER = NULL, /*How far back to look for blocking events (NULL = all available)*/
    @history_end_period_minutes INTEGER = NULL, /*How recent to look for blocking events (NULL = up to current time)*/
    @target_shutdown BIT = 0, /*Set to 1 to stop the XE session after collection*/
    @target_data_file NVARCHAR(4000) = NULL /*Location of XE target file if not using ring buffer*/
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
        @xe_exists BIT = 0,
        @is_running BIT = 0,
        @sql NVARCHAR(MAX) = N'',
        @start_date DATETIMEOFFSET,
        @end_date DATETIMEOFFSET,
        @blocked_process_threshold_seconds INTEGER;
    
    BEGIN TRY
        /*
        Check the blocked process threshold setting
        */
        SELECT 
            @blocked_process_threshold_seconds = CONVERT(INTEGER, value_in_use) 
        FROM 
            sys.configurations 
        WHERE 
            name = N'blocked process threshold (s)';
    
        IF @blocked_process_threshold_seconds = 0
        BEGIN
            /*
            Warn about blocked process threshold not being configured,
            but continue as we might be collecting historical data
            */
            IF @debug = 1
            BEGIN
                RAISERROR('WARNING: Blocked process threshold is not set. No new blocking events will be captured.
To set it, run: EXEC sp_configure ''blocked process threshold (s)'', 5; RECONFIGURE;', 10, 1) WITH NOWAIT;
            END;
        END;
    
        /*
        Check if the XE session exists
        */
        SELECT 
            @xe_exists = 
                CASE 
                    WHEN EXISTS 
                    (
                        SELECT 
                            1 
                        FROM 
                            sys.server_event_sessions 
                        WHERE 
                            name = @session_name
                    )
                    THEN 1
                    ELSE 0
                END;
        
        /*
        If XE session doesn't exist, create it
        */
        IF @xe_exists = 0
        BEGIN
            /*
            Create the XE session
            */
            SET @sql = N'
            CREATE EVENT SESSION ' + QUOTENAME(@session_name) + N' ON SERVER 
            ADD EVENT sqlserver.blocked_process_report
            (
                ACTION
                (
                    sqlserver.client_app_name,
                    sqlserver.client_hostname,
                    sqlserver.database_id,
                    sqlserver.database_name,
                    sqlserver.plan_handle,
                    sqlserver.session_id,
                    sqlserver.sql_text,
                    sqlserver.username
                )
                WHERE duration >= ' + CAST(@min_block_duration_ms * 1000 AS NVARCHAR(20)) + N'
            )';
            
            /*
            Add the target based on configuration
            */
            IF @target_data_file IS NOT NULL
            BEGIN
                SET @sql += N'
                ADD TARGET package0.event_file
                (
                    SET filename = N''' + @target_data_file + N''',
                    max_file_size = 500, /* MB */
                    max_rollover_files = 10
                )';
            END;
            ELSE
            BEGIN
                SET @sql += N'
                ADD TARGET package0.ring_buffer
                (
                    SET max_memory = 4096 /* KB */
                )';
            END;
            
            SET @sql += N'
            WITH 
            (
                MAX_MEMORY = 4096 KB,
                EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS,
                MAX_DISPATCH_LATENCY = 5 SECONDS,
                MAX_EVENT_SIZE = 0 KB,
                MEMORY_PARTITION_MODE = NONE,
                TRACK_CAUSALITY = OFF,
                STARTUP_STATE = ON
            );';
            
            EXEC sp_executesql @sql;
            
            SET @xe_exists = 1;
        END;
        
        /*
        Check if the XE session is running
        */
        SELECT 
            @is_running = 
                CASE 
                    WHEN EXISTS 
                    (
                        SELECT 
                            1 
                        FROM 
                            sys.dm_xe_sessions 
                        WHERE 
                            name = @session_name
                    )
                    THEN 1
                    ELSE 0
                END;
        
        /*
        Start the XE session if it's not running
        */
        IF @xe_exists = 1 AND @is_running = 0
        BEGIN
            EXECUTE('ALTER EVENT SESSION ' + QUOTENAME(@session_name) + ' ON SERVER STATE = START;');
            SET @is_running = 1;
        END;
        
        /*
        Calculate date range for historical data if specified
        */
        IF @history_start_period_minutes IS NOT NULL
        BEGIN
            SET @start_date = DATEADD(MINUTE, -1 * @history_start_period_minutes, SYSDATETIME());
        END;
        
        IF @history_end_period_minutes IS NOT NULL
        BEGIN
            SET @end_date = DATEADD(MINUTE, -1 * @history_end_period_minutes, SYSDATETIME());
        END;
        
        /*
        Collect blocking data from the XE session - different approaches based on target
        */
        IF @target_data_file IS NOT NULL
        BEGIN
            /*
            Collect from event_file target
            */
            INSERT INTO collection.blocking
            (
                collection_time,
                event_time,
                blocked_session_id,
                blocking_session_id,
                database_name,
                wait_resource,
                wait_time_ms,
                blocked_process_report,
                blocked_query,
                blocking_query,
                blocked_client_app,
                blocked_client_hostname,
                blocked_login_name,
                blocking_client_app,
                blocking_client_hostname,
                blocking_login_name
            )
            SELECT 
                collection_time = @collection_start,
                event_time = DATEADD(mi, 
                              DATEDIFF(mi, GETUTCDATE(), CURRENT_TIMESTAMP), 
                              event_data.value('(/event/@timestamp)[1]', 'datetime2')),
                blocked_session_id = event_data.value('(/event/data[@name="blocked_process"]/value/blocked-process-report/blocked-process/process/@spid)[1]', 'int'),
                blocking_session_id = event_data.value('(/event/data[@name="blocked_process"]/value/blocked-process-report/blocking-process/process/@spid)[1]', 'int'),
                database_name = DB_NAME(event_data.value('(/event/action[@name="database_id"]/value)[1]', 'int')),
                wait_resource = event_data.value('(/event/data[@name="blocked_process"]/value/blocked-process-report/blocked-process/process/@waitresource)[1]', 'nvarchar(100)'),
                wait_time_ms = event_data.value('(/event/data[@name="blocked_process"]/value/blocked-process-report/blocked-process/process/@waittime)[1]', 'bigint'),
                blocked_process_report = CAST(event_data.query('/event/data[@name="blocked_process"]/value/blocked-process-report') AS XML),
                blocked_query = ISNULL(
                    event_data.value('(/event/data[@name="blocked_process"]/value/blocked-process-report/blocked-process/process/inputbuf)[1]', 'nvarchar(max)'),
                    event_data.value('(/event/action[@name="sql_text"]/value)[1]', 'nvarchar(max)')
                ),
                blocking_query = event_data.value('(/event/data[@name="blocked_process"]/value/blocked-process-report/blocking-process/process/inputbuf)[1]', 'nvarchar(max)'),
                blocked_client_app = event_data.value('(/event/action[@name="client_app_name"]/value)[1]', 'nvarchar(256)'),
                blocked_client_hostname = event_data.value('(/event/action[@name="client_hostname"]/value)[1]', 'nvarchar(256)'),
                blocked_login_name = event_data.value('(/event/action[@name="username"]/value)[1]', 'nvarchar(256)'),
                blocking_client_app = event_data.value('(/event/data[@name="blocked_process"]/value/blocked-process-report/blocking-process/process/@clientapp)[1]', 'nvarchar(256)'),
                blocking_client_hostname = event_data.value('(/event/data[@name="blocked_process"]/value/blocked-process-report/blocking-process/process/@hostname)[1]', 'nvarchar(256)'),
                blocking_login_name = event_data.value('(/event/data[@name="blocked_process"]/value/blocked-process-report/blocking-process/process/@loginname)[1]', 'nvarchar(256)')
            FROM 
            (
                SELECT 
                    CAST(event_data AS XML) AS event_data
                FROM 
                    sys.fn_xe_file_target_read_file(@target_data_file, NULL, NULL, NULL)
                WHERE 
                    object_name = 'blocked_process_report'
                    AND (
                        @start_date IS NULL 
                        OR DATEADD(mi, DATEDIFF(mi, GETUTCDATE(), CURRENT_TIMESTAMP), 
                           CAST(timestamp_utc AS datetime2)) >= @start_date
                    )
                    AND (
                        @end_date IS NULL 
                        OR DATEADD(mi, DATEDIFF(mi, GETUTCDATE(), CURRENT_TIMESTAMP), 
                           CAST(timestamp_utc AS datetime2)) <= @end_date
                    )
            ) AS bpr;
        END;
        ELSE
        BEGIN
            /*
            Collect from ring_buffer target
            */
            INSERT INTO collection.blocking
            (
                collection_time,
                event_time,
                blocked_session_id,
                blocking_session_id,
                database_name,
                wait_resource,
                wait_time_ms,
                blocked_process_report,
                blocked_query,
                blocking_query,
                blocked_client_app,
                blocked_client_hostname,
                blocked_login_name,
                blocking_client_app,
                blocking_client_hostname,
                blocking_login_name
            )
            SELECT 
                collection_time = @collection_start,
                event_time = DATEADD(mi, 
                              DATEDIFF(mi, GETUTCDATE(), CURRENT_TIMESTAMP), 
                              event_data.value('(/event/@timestamp)[1]', 'datetime2')),
                blocked_session_id = event_data.value('(/event/data[@name="blocked_process"]/value/blocked-process-report/blocked-process/process/@spid)[1]', 'int'),
                blocking_session_id = event_data.value('(/event/data[@name="blocked_process"]/value/blocked-process-report/blocking-process/process/@spid)[1]', 'int'),
                database_name = DB_NAME(event_data.value('(/event/action[@name="database_id"]/value)[1]', 'int')),
                wait_resource = event_data.value('(/event/data[@name="blocked_process"]/value/blocked-process-report/blocked-process/process/@waitresource)[1]', 'nvarchar(100)'),
                wait_time_ms = event_data.value('(/event/data[@name="blocked_process"]/value/blocked-process-report/blocked-process/process/@waittime)[1]', 'bigint'),
                blocked_process_report = CAST(event_data.query('/event/data[@name="blocked_process"]/value/blocked-process-report') AS XML),
                blocked_query = ISNULL(
                    event_data.value('(/event/data[@name="blocked_process"]/value/blocked-process-report/blocked-process/process/inputbuf)[1]', 'nvarchar(max)'),
                    event_data.value('(/event/action[@name="sql_text"]/value)[1]', 'nvarchar(max)')
                ),
                blocking_query = event_data.value('(/event/data[@name="blocked_process"]/value/blocked-process-report/blocking-process/process/inputbuf)[1]', 'nvarchar(max)'),
                blocked_client_app = event_data.value('(/event/action[@name="client_app_name"]/value)[1]', 'nvarchar(256)'),
                blocked_client_hostname = event_data.value('(/event/action[@name="client_hostname"]/value)[1]', 'nvarchar(256)'),
                blocked_login_name = event_data.value('(/event/action[@name="username"]/value)[1]', 'nvarchar(256)'),
                blocking_client_app = event_data.value('(/event/data[@name="blocked_process"]/value/blocked-process-report/blocking-process/process/@clientapp)[1]', 'nvarchar(256)'),
                blocking_client_hostname = event_data.value('(/event/data[@name="blocked_process"]/value/blocked-process-report/blocking-process/process/@hostname)[1]', 'nvarchar(256)'),
                blocking_login_name = event_data.value('(/event/data[@name="blocked_process"]/value/blocked-process-report/blocking-process/process/@loginname)[1]', 'nvarchar(256)')
            FROM 
            (
                SELECT 
                    CAST(target_data.value('(event[@name="blocked_process_report"]/data[@name="blocked_process"]/value)[1]', 'nvarchar(max)') AS XML) AS event_data
                FROM 
                (
                    SELECT 
                        CAST(xet.target_data AS XML) AS target_data
                    FROM 
                        sys.dm_xe_session_targets AS xet
                    JOIN 
                        sys.dm_xe_sessions AS xe
                        ON xe.address = xet.event_session_address
                    WHERE 
                        xe.name = @session_name
                    AND 
                        xet.target_name = N'ring_buffer'
                ) AS xem
                CROSS APPLY target_data.nodes('RingBufferTarget/event') AS xn(target_data)
                WHERE 
                    target_data.value('@name', 'nvarchar(128)') = 'blocked_process_report'
                    AND (
                        @start_date IS NULL 
                        OR DATEADD(mi, DATEDIFF(mi, GETUTCDATE(), CURRENT_TIMESTAMP), 
                           target_data.value('@timestamp', 'datetime2')) >= @start_date
                    )
                    AND (
                        @end_date IS NULL 
                        OR DATEADD(mi, DATEDIFF(mi, GETUTCDATE(), CURRENT_TIMESTAMP), 
                           target_data.value('@timestamp', 'datetime2')) <= @end_date
                    )
            ) AS bpr;
        END;
        
        SET @rows_collected = @@ROWCOUNT;
        SET @collection_end = SYSDATETIME();
        
        /*
        Shutdown the XE session if requested
        */
        IF @target_shutdown = 1 AND @is_running = 1
        BEGIN
            EXECUTE('ALTER EVENT SESSION ' + QUOTENAME(@session_name) + ' ON SERVER STATE = STOP;');
        END;
        
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
            'collection.collect_blocking',
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
                N'Blocking Information Collected' AS collection_type,
                @rows_collected AS rows_collected,
                CAST(DATEDIFF(MILLISECOND, @collection_start, @collection_end) / 1000.0 AS DECIMAL(18,2)) AS duration_seconds,
                @xe_exists AS xe_session_exists,
                @is_running AS xe_session_running,
                @blocked_process_threshold_seconds AS blocked_process_threshold_seconds;
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
            'collection.collect_blocking',
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