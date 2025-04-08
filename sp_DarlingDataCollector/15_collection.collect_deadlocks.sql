/*
██████╗ ███████╗ █████╗ ██████╗ ██╗      ██████╗  ██████╗██╗  ██╗      ██████╗ ██████╗ ██╗     ██╗     ███████╗ ██████╗████████╗ ██████╗ ██████╗ 
██╔══██╗██╔════╝██╔══██╗██╔══██╗██║     ██╔═══██╗██╔════╝██║ ██╔╝     ██╔════╝██╔═══██╗██║     ██║     ██╔════╝██╔════╝╚══██╔══╝██╔═══██╗██╔══██╗
██║  ██║█████╗  ███████║██║  ██║██║     ██║   ██║██║     █████╔╝      ██║     ██║   ██║██║     ██║     █████╗  ██║        ██║   ██║   ██║██████╔╝
██║  ██║██╔══╝  ██╔══██║██║  ██║██║     ██║   ██║██║     ██╔═██╗      ██║     ██║   ██║██║     ██║     ██╔══╝  ██║        ██║   ██║   ██║██╔══██╗
██████╔╝███████╗██║  ██║██████╔╝███████╗╚██████╔╝╚██████╗██║  ██╗     ╚██████╗╚██████╔╝███████╗███████╗███████╗╚██████╗   ██║   ╚██████╔╝██║  ██║
╚═════╝ ╚══════╝╚═╝  ╚═╝╚═════╝ ╚══════╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝      ╚═════╝ ╚═════╝ ╚══════╝╚══════╝╚══════╝ ╚═════╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝
                                                                                                                                              
Copyright (c) Darling Data, LLC
https://www.erikdarling.com/

--===== DEADLOCK COLLECTOR NOTES ====--
This procedure relies on the xml_deadlock_report Extended Event
to capture deadlock information. In most SQL Server environments,
deadlocks are captured automatically in the system_health session.

For specific deadlock detection, we also create our own XE session
that can be tailored to your needs.

*/

CREATE OR ALTER PROCEDURE
    collection.collect_deadlocks
(
    @debug BIT = 0, /*Print debugging information*/
    @session_name NVARCHAR(128) = N'DarlingDataCollector_Deadlocks', /*Name of the XE session to create/use*/
    @use_system_health BIT = 1, /*Set to 1 to also check system_health session for deadlocks*/
    @history_start_period_minutes INTEGER = NULL, /*How far back to look for deadlock events (NULL = all available)*/
    @history_end_period_minutes INTEGER = NULL, /*How recent to look for deadlock events (NULL = up to current time)*/
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
        @end_date DATETIMEOFFSET;
    
    BEGIN TRY
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
        Check if a dedicated deadlock XE session exists
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
        IF @xe_exists = 0 AND (@use_system_health = 0 OR @target_data_file IS NOT NULL)
        BEGIN
            /*
            Create the XE session
            */
            SET @sql = N'
            CREATE EVENT SESSION ' + QUOTENAME(@session_name) + N' ON SERVER 
            ADD EVENT sqlserver.xml_deadlock_report
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
        IF @xe_exists = 1  
        BEGIN
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
            IF @is_running = 0 AND (@use_system_health = 0 OR @target_data_file IS NOT NULL)
            BEGIN
                EXECUTE('ALTER EVENT SESSION ' + QUOTENAME(@session_name) + ' ON SERVER STATE = START;');
                SET @is_running = 1;
            END;
        END;
                
        /*
        Collect deadlock data from custom XE session if specified
        */
        IF @use_system_health = 0 OR @target_data_file IS NOT NULL
        BEGIN
            IF @target_data_file IS NOT NULL
            BEGIN
                /*
                Collect from event_file target
                */
                INSERT INTO collection.deadlocks
                (
                    collection_time,
                    event_time,
                    deadlock_graph,
                    victim_spid,
                    deadlock_xml,
                    is_victim,
                    process_spid,
                    process_database_id,
                    process_database_name,
                    process_priority,
                    process_log_used,
                    process_wait_resource,
                    process_wait_time_ms,
                    process_transaction_name,
                    process_last_tran_started,
                    process_last_batch_started,
                    process_last_batch_completed,
                    process_lock_mode,
                    process_status,
                    process_transaction_count,
                    process_client_app,
                    process_client_hostname,
                    process_login_name,
                    process_isolation_level,
                    process_query
                )
                SELECT 
                    collection_time = @collection_start,
                    event_time = DATEADD(MINUTE, 
                                 DATEDIFF(MINUTE, GETUTCDATE(), CURRENT_TIMESTAMP), 
                                 event_data.value('(/event/@timestamp)[1]', 'datetime2')),
                    deadlock_graph = CAST(event_data.query('/event/data/value/deadlock') AS XML),
                    victim_spid = event_data.value('(/event/data/value/deadlock/victim-list/victimProcess/@spid)[1]', 'int'),
                    deadlock_xml = event_data,
                    is_victim = 
                        CASE 
                            WHEN process.value('@spid', 'int') = 
                                 event_data.value('(/event/data/value/deadlock/victim-list/victimProcess/@spid)[1]', 'int')
                            THEN 1
                            ELSE 0
                        END,
                    process_spid = process.value('@spid', 'int'),
                    process_database_id = process.value('@currentdb', 'int'),
                    process_database_name = DB_NAME(process.value('@currentdb', 'int')),
                    process_priority = process.value('@priority', 'int'),
                    process_log_used = process.value('@logused', 'int'),
                    process_wait_resource = process.value('@waitresource', 'nvarchar(256)'),
                    process_wait_time_ms = process.value('@waittime', 'int'),
                    process_transaction_name = process.value('@transactionname', 'nvarchar(256)'),
                    process_last_tran_started = process.value('@lasttranstarted', 'datetime'),
                    process_last_batch_started = process.value('@lastbatchstarted', 'datetime'),
                    process_last_batch_completed = process.value('@lastbatchcompleted', 'datetime'),
                    process_lock_mode = process.value('@lockMode', 'nvarchar(32)'),
                    process_status = process.value('@status', 'nvarchar(32)'),
                    process_transaction_count = process.value('@trancount', 'int'),
                    process_client_app = process.value('@clientapp', 'nvarchar(256)'),
                    process_client_hostname = process.value('@hostname', 'nvarchar(256)'),
                    process_login_name = process.value('@loginname', 'nvarchar(256)'),
                    process_isolation_level = process.value('@isolationlevel', 'nvarchar(32)'),
                    process_query = process.value('(executionStack/frame/@sqlhandle)[1]', 'nvarchar(max)')
                FROM 
                (
                    SELECT 
                        CAST(event_data AS XML) AS event_data
                    FROM 
                        sys.fn_xe_file_target_read_file(@target_data_file, NULL, NULL, NULL)
                    WHERE 
                        object_name = 'xml_deadlock_report'
                        AND (
                            @start_date IS NULL 
                            OR DATEADD(MINUTE, DATEDIFF(MINUTE, GETUTCDATE(), CURRENT_TIMESTAMP), 
                               CAST(timestamp_utc AS datetime2)) >= @start_date
                        )
                        AND (
                            @end_date IS NULL 
                            OR DATEADD(MINUTE, DATEDIFF(MINUTE, GETUTCDATE(), CURRENT_TIMESTAMP), 
                               CAST(timestamp_utc AS datetime2)) <= @end_date
                        )
                ) AS xd
                CROSS APPLY event_data.nodes('/event/data/value/deadlock/process-list/process') AS nodes(process);
            END;
            ELSE
            BEGIN
                /*
                Collect from ring_buffer target
                */
                INSERT INTO collection.deadlocks
                (
                    collection_time,
                    event_time,
                    deadlock_graph,
                    victim_spid,
                    deadlock_xml,
                    is_victim,
                    process_spid,
                    process_database_id,
                    process_database_name,
                    process_priority,
                    process_log_used,
                    process_wait_resource,
                    process_wait_time_ms,
                    process_transaction_name,
                    process_last_tran_started,
                    process_last_batch_started,
                    process_last_batch_completed,
                    process_lock_mode,
                    process_status,
                    process_transaction_count,
                    process_client_app,
                    process_client_hostname,
                    process_login_name,
                    process_isolation_level,
                    process_query
                )
                SELECT 
                    collection_time = @collection_start,
                    event_time = DATEADD(MINUTE, 
                                 DATEDIFF(MINUTE, GETUTCDATE(), CURRENT_TIMESTAMP), 
                                 CAST(xevents.event_data.value('(@timestamp)[1]', 'datetime2') AS datetime2)),
                    deadlock_graph = CAST(xevents.event_data.query('(data[@name="xml_report"]/value/deadlock)[1]') AS XML),
                    victim_spid = xevents.event_data.value('(data[@name="xml_report"]/value/deadlock/victim-list/victimProcess/@spid)[1]', 'int'),
                    deadlock_xml = xevents.event_data,
                    is_victim = 
                        CASE 
                            WHEN process.value('@spid', 'int') = 
                                 xevents.event_data.value('(data[@name="xml_report"]/value/deadlock/victim-list/victimProcess/@spid)[1]', 'int')
                            THEN 1
                            ELSE 0
                        END,
                    process_spid = process.value('@spid', 'int'),
                    process_database_id = process.value('@currentdb', 'int'),
                    process_database_name = DB_NAME(process.value('@currentdb', 'int')),
                    process_priority = process.value('@priority', 'int'),
                    process_log_used = process.value('@logused', 'int'),
                    process_wait_resource = process.value('@waitresource', 'nvarchar(256)'),
                    process_wait_time_ms = process.value('@waittime', 'int'),
                    process_transaction_name = process.value('@transactionname', 'nvarchar(256)'),
                    process_last_tran_started = process.value('@lasttranstarted', 'datetime'),
                    process_last_batch_started = process.value('@lastbatchstarted', 'datetime'),
                    process_last_batch_completed = process.value('@lastbatchcompleted', 'datetime'),
                    process_lock_mode = process.value('@lockMode', 'nvarchar(32)'),
                    process_status = process.value('@status', 'nvarchar(32)'),
                    process_transaction_count = process.value('@trancount', 'int'),
                    process_client_app = process.value('@clientapp', 'nvarchar(256)'),
                    process_client_hostname = process.value('@hostname', 'nvarchar(256)'),
                    process_login_name = process.value('@loginname', 'nvarchar(256)'),
                    process_isolation_level = process.value('@isolationlevel', 'nvarchar(32)'),
                    process_query = process.value('(executionStack/frame/@sqlhandle)[1]', 'nvarchar(max)')
                FROM 
                (
                    SELECT 
                        CAST(target_data.query('.') AS XML) as event_data
                    FROM
                    (
                        SELECT
                            CAST(t.target_data AS XML) AS target_data
                        FROM 
                            sys.dm_xe_session_targets AS t
                        JOIN 
                            sys.dm_xe_sessions AS s
                            ON s.address = t.event_session_address
                        WHERE 
                            s.name = @session_name
                        AND 
                            t.target_name = N'ring_buffer'
                    ) AS targets
                    CROSS APPLY target_data.nodes('RingBufferTarget/event[@name="xml_deadlock_report"]') AS xeNodes(target_data)
                    WHERE 
                        (
                            @start_date IS NULL 
                            OR DATEADD(MINUTE, DATEDIFF(MINUTE, GETUTCDATE(), CURRENT_TIMESTAMP), 
                               CAST(target_data.value('@timestamp', 'datetime2') AS datetime2)) >= @start_date
                        )
                        AND (
                            @end_date IS NULL 
                            OR DATEADD(MINUTE, DATEDIFF(MINUTE, GETUTCDATE(), CURRENT_TIMESTAMP), 
                               CAST(target_data.value('@timestamp', 'datetime2') AS datetime2)) <= @end_date
                        )
                ) AS xevents
                CROSS APPLY event_data.nodes('(data[@name="xml_report"]/value/deadlock/process-list/process)') AS deadlock_nodes(process);
            END;
        END;

        /*
        Collect deadlock data from system_health session if specified
        */
        IF @use_system_health = 1
        BEGIN
            /*
            Collect from system_health session
            */
            INSERT INTO collection.deadlocks
            (
                collection_time,
                event_time,
                deadlock_graph,
                victim_spid,
                deadlock_xml,
                is_victim,
                process_spid,
                process_database_id,
                process_database_name,
                process_priority,
                process_log_used,
                process_wait_resource,
                process_wait_time_ms,
                process_transaction_name,
                process_last_tran_started,
                process_last_batch_started,
                process_last_batch_completed,
                process_lock_mode,
                process_status,
                process_transaction_count,
                process_client_app,
                process_client_hostname,
                process_login_name,
                process_isolation_level,
                process_query
            )
            SELECT 
                collection_time = @collection_start,
                event_time = DATEADD(MINUTE, 
                             DATEDIFF(MINUTE, GETUTCDATE(), CURRENT_TIMESTAMP), 
                             CAST(event_data.value('(@timestamp)[1]', 'datetime2') AS datetime2)),
                deadlock_graph = CAST(event_data.query('/event/data/value/deadlock') AS XML),
                victim_spid = event_data.value('(/event/data/value/deadlock/victim-list/victimProcess/@spid)[1]', 'int'),
                deadlock_xml = event_data,
                is_victim = 
                    CASE 
                        WHEN process.value('@spid', 'int') = 
                             event_data.value('(/event/data/value/deadlock/victim-list/victimProcess/@spid)[1]', 'int')
                        THEN 1
                        ELSE 0
                    END,
                process_spid = process.value('@spid', 'int'),
                process_database_id = process.value('@currentdb', 'int'),
                process_database_name = DB_NAME(process.value('@currentdb', 'int')),
                process_priority = process.value('@priority', 'int'),
                process_log_used = process.value('@logused', 'int'),
                process_wait_resource = process.value('@waitresource', 'nvarchar(256)'),
                process_wait_time_ms = process.value('@waittime', 'int'),
                process_transaction_name = process.value('@transactionname', 'nvarchar(256)'),
                process_last_tran_started = process.value('@lasttranstarted', 'datetime'),
                process_last_batch_started = process.value('@lastbatchstarted', 'datetime'),
                process_last_batch_completed = process.value('@lastbatchcompleted', 'datetime'),
                process_lock_mode = process.value('@lockMode', 'nvarchar(32)'),
                process_status = process.value('@status', 'nvarchar(32)'),
                process_transaction_count = process.value('@trancount', 'int'),
                process_client_app = process.value('@clientapp', 'nvarchar(256)'),
                process_client_hostname = process.value('@hostname', 'nvarchar(256)'),
                process_login_name = process.value('@loginname', 'nvarchar(256)'),
                process_isolation_level = process.value('@isolationlevel', 'nvarchar(32)'),
                process_query = process.value('(executionStack/frame/@sqlhandle)[1]', 'nvarchar(max)')
            FROM 
            (
                SELECT 
                    CAST(event_data AS XML) AS event_data
                FROM 
                (
                    SELECT
                        CAST(target_data AS XML) AS target_data
                    FROM 
                    (
                        SELECT 
                            target_data = CONVERT(XML, target_data)
                        FROM sys.dm_xe_session_targets AS t
                        JOIN sys.dm_xe_sessions AS s
                          ON s.address = t.event_session_address
                        WHERE s.name = N'system_health'
                        AND   t.target_name = N'ring_buffer'
                    ) AS t
                ) AS src
                CROSS APPLY target_data.nodes('RingBufferTarget/event[@name="xml_deadlock_report"]') AS q(event_data)
                WHERE 
                    (
                        @start_date IS NULL 
                        OR DATEADD(MINUTE, DATEDIFF(MINUTE, GETUTCDATE(), CURRENT_TIMESTAMP), 
                           CAST(event_data.value('@timestamp', 'datetime2') AS datetime2)) >= @start_date
                    )
                    AND (
                        @end_date IS NULL 
                        OR DATEADD(MINUTE, DATEDIFF(MINUTE, GETUTCDATE(), CURRENT_TIMESTAMP), 
                           CAST(event_data.value('@timestamp', 'datetime2') AS datetime2)) <= @end_date
                    )
            ) AS xd
            CROSS APPLY event_data.nodes('/event/data/value/deadlock/process-list/process') AS nodes(process);
        END;

        SET @rows_collected = @@ROWCOUNT;
        SET @collection_end = SYSDATETIME();
        
        /*
        Shutdown the XE session if requested
        */
        IF @target_shutdown = 1 AND @is_running = 1 AND @use_system_health = 0
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
            'collection.collect_deadlocks',
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
                N'Deadlock Information Collected' AS collection_type,
                @rows_collected AS rows_collected,
                CAST(DATEDIFF(MILLISECOND, @collection_start, @collection_end) / 1000.0 AS DECIMAL(18,2)) AS duration_seconds,
                @xe_exists AS xe_session_exists,
                @is_running AS xe_session_running,
                @use_system_health AS using_system_health;
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
            'collection.collect_deadlocks',
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