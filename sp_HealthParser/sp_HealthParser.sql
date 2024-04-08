SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
SET IMPLICIT_TRANSACTIONS OFF;
SET STATISTICS TIME, IO OFF;
GO

/*
██╗  ██╗███████╗ █████╗ ██╗  ████████╗██╗  ██╗
██║  ██║██╔════╝██╔══██╗██║  ╚══██╔══╝██║  ██║
███████║█████╗  ███████║██║     ██║   ███████║
██╔══██║██╔══╝  ██╔══██║██║     ██║   ██╔══██║
██║  ██║███████╗██║  ██║███████╗██║   ██║  ██║
╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚══════╝╚═╝   ╚═╝  ╚═╝

██████╗  █████╗ ██████╗ ███████╗███████╗██████╗
██╔══██╗██╔══██╗██╔══██╗██╔════╝██╔════╝██╔══██╗
██████╔╝███████║██████╔╝███████╗█████╗  ██████╔╝
██╔═══╝ ██╔══██║██╔══██╗╚════██║██╔══╝  ██╔══██╗
██║     ██║  ██║██║  ██║███████║███████╗██║  ██║
╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚══════╝╚═╝  ╚═╝


Copyright 2024 Darling Data, LLC
https://www.erikdarling.com/

For support, head over to GitHub:
https://github.com/erikdarlingdata/DarlingData
*/

IF OBJECT_ID('dbo.sp_HealthParser') IS NULL
   BEGIN
       EXEC ('CREATE PROCEDURE dbo.sp_HealthParser AS RETURN 138;');
   END;
GO

ALTER PROCEDURE
    dbo.sp_HealthParser
(
    @what_to_check varchar(10) = 'all', /*Specify which portion of the data to check*/
    @start_date datetimeoffset(7) = NULL, /*Begin date for events*/
    @end_date datetimeoffset(7) = NULL, /*End date for events*/
    @warnings_only bit = 0, /*Only show results from recorded warnings*/
    @database_name sysname = NULL, /*Filter to a specific database for blocking)*/
    @wait_duration_ms bigint = 500, /*Minimum duration to show query waits*/
    @wait_round_interval_minutes bigint = 60, /*Nearest interval to round wait stats to*/
    @skip_locks bit = 0, /*Skip the blocking and deadlocks*/
    @pending_task_threshold integer = 10, /*Minimum number of pending tasks to care about*/
    @debug bit = 0, /*Select from temp tables to get event data in raw xml*/
    @help bit = 0, /*Get help*/
    @version varchar(30) = NULL OUTPUT, /*Script version*/
    @version_date datetime = NULL OUTPUT /*Script date*/
)
WITH
RECOMPILE
AS
BEGIN
    SET STATISTICS XML OFF;
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    SELECT
        @version = '1.5',
        @version_date = '20240401';

    IF @help = 1
    BEGIN
        SELECT
            introduction =
                'hi, i''m sp_HealthParser!' UNION ALL
        SELECT  'you can use me to examine the contents of the system_health extended event session' UNION ALL
        SELECT  'i apologize if i take a long time, i have to do a lot of XML processing' UNION ALL
        SELECT  'from your loving sql server consultant, erik darling: erikdarling.com';

        /*
        Parameters
        */
        SELECT
            parameter_name =
                ap.name,
            data_type =
                t.name,
            description =
                CASE
                    ap.name
                    WHEN N'@what_to_check' THEN N'areas of system health to check'
                    WHEN N'@start_date' THEN N'earliest date to show data for, will be internally converted to UTC'
                    WHEN N'@end_date' THEN N'latest date to show data for, will be internally converted to UTC'
                    WHEN N'@warnings_only' THEN N'only show rows where a warning was reported'
                    WHEN N'@database_name' THEN N'database name to show blocking events for'
                    WHEN N'@wait_duration_ms' THEN N'minimum wait duration'
                    WHEN N'@wait_round_interval_minutes' THEN N'interval to round minutes to for wait stats'
                    WHEN N'@skip_locks' THEN N'skip the blocking and deadlocking section'
                    WHEN N'@pending_task_threshold' THEN N'minimum number of pending tasks to display'
                    WHEN N'@version' THEN N'OUTPUT; for support'
                    WHEN N'@version_date' THEN N'OUTPUT; for support'
                    WHEN N'@help' THEN N'how you got here'
                    WHEN N'@debug' THEN N'prints dynamic sql, selects from temp tables'
                END,
            valid_inputs =
                CASE
                    ap.name
                    WHEN N'@what_to_check' THEN N'all, waits, disk, cpu, memory, system, locking'
                    WHEN N'@start_date' THEN N'a reasonable date'
                    WHEN N'@end_date' THEN N'a reasonable date'
                    WHEN N'@warnings_only' THEN N'NULL, 0, 1'
                    WHEN N'@database_name' THEN N'the name of a database'
                    WHEN N'@wait_duration_ms' THEN N'the minimum duration of a wait for queries with interesting waits'
                    WHEN N'@wait_round_interval_minutes' THEN N'interval to round minutes to for top wait stats by count and duration'
                    WHEN N'@skip_locks' THEN N'0 or 1'
                    WHEN N'@pending_task_threshold' THEN N'a valid integer'
                    WHEN N'@version' THEN N'none'
                    WHEN N'@version_date' THEN N'none'
                    WHEN N'@help' THEN N'0 or 1'
                    WHEN N'@debug' THEN N'0 or 1'
                END,
            defaults =
                CASE
                    ap.name
                    WHEN N'@what_to_check' THEN N'all'
                    WHEN N'@start_date' THEN N'seven days back'
                    WHEN N'@end_date' THEN N'current date'
                    WHEN N'@warnings_only' THEN N'0'
                    WHEN N'@database_name' THEN N'NULL'
                    WHEN N'@wait_duration_ms' THEN N'0'
                    WHEN N'@wait_round_interval_minutes' THEN N'60'
                    WHEN N'@skip_locks' THEN N'0'
                    WHEN N'@pending_task_threshold' THEN N'10'
                    WHEN N'@version' THEN N'none; OUTPUT'
                    WHEN N'@version_date' THEN N'none; OUTPUT'
                    WHEN N'@help' THEN N'0'
                    WHEN N'@debug' THEN N'0'
                END
        FROM sys.all_parameters AS ap
        INNER JOIN sys.all_objects AS o
          ON ap.object_id = o.object_id
        INNER JOIN sys.types AS t
          ON  ap.system_type_id = t.system_type_id
          AND ap.user_type_id = t.user_type_id
        WHERE o.name = N'sp_HealthParser'
        OPTION(MAXDOP 1, RECOMPILE);

        SELECT
            mit_license_yo = 'i am MIT licensed, so like, do whatever'

        UNION ALL

        SELECT
            mit_license_yo = 'see printed messages for full license';

        RAISERROR('
MIT License

Copyright 2024 Darling Data, LLC

https://www.erikdarling.com/

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"),
to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute,
sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the
following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE
FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
', 0, 1) WITH NOWAIT;

        RETURN;
    END; /*End help section*/

    IF @debug = 1
    BEGIN
        RAISERROR('Declaring variables', 0, 1) WITH NOWAIT;
    END;

    DECLARE
        @sql nvarchar(MAX) =
            N'',
        @params nvarchar(MAX) =
            N'@start_date datetimeoffset(7),
              @end_date datetimeoffset(7)',
        @azure bit  =
            CASE
                WHEN
                    CONVERT
                    (
                        int,
                        SERVERPROPERTY('EngineEdition')
                    ) = 5
                THEN 1
                ELSE 0
            END,
        @azure_msg nchar(1),
        @mi bit  =
            CASE
                WHEN
                    CONVERT
                    (
                        int,
                        SERVERPROPERTY('EngineEdition')
                    ) = 8
                THEN 1
                ELSE 0
            END,
        @mi_msg nchar(1),
        @dbid integer =
            DB_ID(@database_name);

    IF @azure = 1
    BEGIN
        RAISERROR('This won''t work in Azure because it''s horrible', 11, 1) WITH NOWAIT;
        RETURN;
    END;

    IF @debug = 1
    BEGIN
        RAISERROR('Fixing variables', 0, 1) WITH NOWAIT;
    END;

    SELECT
        @start_date =
            CASE
                WHEN @start_date IS NULL
                THEN
                    DATEADD
                    (
                        MINUTE,
                        DATEDIFF
                        (
                            MINUTE,
                            SYSDATETIME(),
                            GETUTCDATE()
                        ),
                        DATEADD
                        (
                            DAY,
                            -7,
                            SYSDATETIME()
                        )
                    )
                ELSE
                    DATEADD
                    (
                        MINUTE,
                        DATEDIFF
                        (
                            MINUTE,
                            SYSDATETIME(),
                            GETUTCDATE()
                        ),
                        @start_date
                    )
            END,
        @end_date =
            CASE
                WHEN @end_date IS NULL
                THEN
                    DATEADD
                    (
                        MINUTE,
                        DATEDIFF
                        (
                            MINUTE,
                            SYSDATETIME(),
                            GETUTCDATE()
                        ),
                        SYSDATETIME()
                    )
                ELSE
                    DATEADD
                    (
                        MINUTE,
                        DATEDIFF
                        (
                            MINUTE,
                            SYSDATETIME(),
                            GETUTCDATE()
                        ),
                        @end_date
                    )
            END,
        @wait_round_interval_minutes = /*do this i guess?*/
            CASE
                WHEN @wait_round_interval_minutes < 1
                THEN 1
                ELSE @wait_round_interval_minutes
            END,
        @azure_msg =
            CONVERT(nchar(1), @azure),
        @mi_msg =
            CONVERT(nchar(1), @mi);

    /*If any parameters that expect non-NULL default values get passed in with NULLs, fix them*/
    SELECT
        @what_to_check = ISNULL(@what_to_check, 'all'),
        @warnings_only = ISNULL(@warnings_only, 0),
        @wait_duration_ms = ISNULL(@wait_duration_ms, 0),
        @wait_round_interval_minutes = ISNULL(@wait_round_interval_minutes, 60),
        @skip_locks = ISNULL(@skip_locks, 0),
        @pending_task_threshold = ISNULL(@pending_task_threshold, 10);

    SELECT
       @what_to_check = LOWER(@what_to_check);

    IF @what_to_check NOT IN
       (
           'all',
           'waits',
           'disk',
           'cpu',
           'memory',
           'system',
           'blocking',
           'blocks',
           'deadlock',
           'deadlocks',
           'locking',
           'locks'
       )
    BEGIN
        SELECT
            @what_to_check =
                CASE
                    WHEN @what_to_check = 'wait'
                    THEN 'waits'
                    WHEN @what_to_check IN
                         ('blocking', 'blocks', 'deadlock', 'deadlocks', 'lock', 'locks')
                    THEN 'locking'
                    ELSE 'all'
                END;
    END;

    IF @debug = 1
    BEGIN
        RAISERROR('Creating temp tables', 0, 1) WITH NOWAIT;
    END;

    CREATE TABLE
        #ignore
    (
        wait_type nvarchar(60)
    );

    CREATE TABLE
        #wait_info
    (
        wait_info xml NOT NULL
    );

    CREATE TABLE
        #sp_server_diagnostics_component_result
    (
        sp_server_diagnostics_component_result xml NOT NULL
    );

    CREATE TABLE
        #xml_deadlock_report
    (
        xml_deadlock_report xml NOT NULL
    );

    CREATE TABLE
        #x
    (
        x xml NOT NULL
    );

    CREATE TABLE
        #ring_buffer
    (
        ring_buffer xml NOT NULL
    );

    /*The more you ignore waits, the worser they get*/
    IF @what_to_check IN ('all', 'waits')
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Inserting ignorable waits to #ignore', 0, 1) WITH NOWAIT;
        END;

        INSERT
            #ignore WITH(TABLOCKX)
        (
            wait_type
        )
        SELECT
            dows.wait_type
        FROM sys.dm_os_wait_stats AS dows
        WHERE dows.wait_type IN
        (
            N'BROKER_EVENTHANDLER', N'BROKER_RECEIVE_WAITFOR', N'BROKER_TASK_STOP', N'BROKER_TO_FLUSH', N'BROKER_TRANSMITTER', N'CHECKPOINT_QUEUE', N'CHKPT',
            N'CLR_AUTO_EVENT', N'CLR_MANUAL_EVENT', N'CLR_SEMAPHORE', N'DBMIRROR_DBM_EVENT', N'DBMIRROR_EVENTS_QUEUE', N'DBMIRROR_WORKER_QUEUE', N'DBMIRRORING_CMD',
            N'DIRTY_PAGE_POLL', N'DISPATCHER_QUEUE_SEMAPHORE', N'FSAGENT', N'FT_IFTS_SCHEDULER_IDLE_WAIT', N'FT_IFTSHC_MUTEX', N'HADR_CLUSAPI_CALL',
            N'HADR_FILESTREAM_IOMGR_IOCOMPLETION', N'HADR_LOGCAPTURE_WAIT', N'HADR_NOTIFICATION_DEQUEUE', N'HADR_TIMER_TASK', N'HADR_WORK_QUEUE',
            N'KSOURCE_WAKEUP', N'LAZYWRITER_SLEEP', N'LOGMGR_QUEUE', N'MEMORY_ALLOCATION_EXT', N'ONDEMAND_TASK_QUEUE', N'PARALLEL_REDO_DRAIN_WORKER',
            N'PARALLEL_REDO_LOG_CACHE', N'PARALLEL_REDO_TRAN_LIST', N'PARALLEL_REDO_WORKER_SYNC', N'PARALLEL_REDO_WORKER_WAIT_WORK', N'PREEMPTIVE_OS_FLUSHFILEBUFFERS',
            N'PREEMPTIVE_XE_GETTARGETSTATE', N'PVS_PREALLOCATE', N'PWAIT_ALL_COMPONENTS_INITIALIZED', N'PWAIT_DIRECTLOGCONSUMER_GETNEXT',
            N'PWAIT_EXTENSIBILITY_CLEANUP_TASK', N'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP', N'QDS_ASYNC_QUEUE', N'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP',
            N'QDS_SHUTDOWN_QUEUE', N'REDO_THREAD_PENDING_WORK', N'REQUEST_FOR_DEADLOCK_SEARCH', N'RESOURCE_QUEUE', N'SERVER_IDLE_CHECK', N'SLEEP_DBSTARTUP',
            N'SLEEP_DCOMSTARTUP', N'SLEEP_MASTERDBREADY', N'SLEEP_MASTERMDREADY', N'SLEEP_MASTERUPGRADED', N'SLEEP_MSDBSTARTUP', N'SLEEP_SYSTEMTASK', N'SLEEP_TEMPDBSTARTUP',
            N'SNI_HTTP_ACCEPT', N'SOS_WORK_DISPATCHER', N'SP_SERVER_DIAGNOSTICS_SLEEP', N'SQLTRACE_BUFFER_FLUSH',  N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP',
            N'SQLTRACE_WAIT_ENTRIES', N'UCS_SESSION_REGISTRATION', N'VDI_CLIENT_OTHER', N'WAIT_FOR_RESULTS', N'WAITFOR', N'WAITFOR_TASKSHUTDOWN', N'WAIT_XTP_RECOVERY',
            N'WAIT_XTP_HOST_WAIT', N'WAIT_XTP_OFFLINE_CKPT_NEW_LOG', N'WAIT_XTP_CKPT_CLOSE', N'XE_DISPATCHER_JOIN', N'XE_DISPATCHER_WAIT', N'XE_TIMER_EVENT',
            N'AZURE_IMDS_VERSIONS', N'XE_FILE_TARGET_TVF', N'XE_LIVE_TARGET_TVF', N'DBMIRROR_DBM_MUTEX', N'DBMIRROR_SEND', N'ASYNC_NETWORK_IO'
        )
        OPTION(RECOMPILE);
    END; /*End waits ignore*/

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#ignore',
            i.*
        FROM #ignore AS i ORDER BY i.wait_type
        OPTION(RECOMPILE);
    END;

    /*
    The column timestamp_utc is 2017+ only, but terribly broken:
    https://dba.stackexchange.com/q/323147/32281
    https://feedback.azure.com/d365community/idea/5f8e52d6-f3d2-ec11-a81b-6045bd7ac9f9
    */
    IF EXISTS
    (
        SELECT
            1/0
        FROM sys.all_columns AS ac
        WHERE ac.object_id = OBJECT_ID(N'sys.fn_xe_file_target_read_file')
        AND   ac.name = N'timestamp_utc'
    )
    AND @mi = 0
    BEGIN
        /*Grab data from the wait info component*/
        IF @what_to_check IN ('all', 'waits')
        BEGIN
            IF @debug = 1
            BEGIN
                RAISERROR('Checking waits for not Managed Instance, 2017+', 0, 1) WITH NOWAIT;
            END;

            SELECT
                @sql = N'
            SELECT
                wait_info =
                    ISNULL
                    (
                        xml.wait_info,
                        CONVERT(xml, N''<event>event</event>'')
                    )
            FROM
            (
                SELECT
                    wait_info =
                        TRY_CAST(fx.event_data AS xml)
                FROM sys.fn_xe_file_target_read_file(N''system_health*.xel'', NULL, NULL, NULL) AS fx
                WHERE fx.object_name = N''wait_info''
                AND   CONVERT(datetimeoffset(7), fx.timestamp_utc) BETWEEN @start_date AND @end_date
            ) AS xml
            CROSS APPLY xml.wait_info.nodes(''/event'') AS e(x)
            OPTION(RECOMPILE);';

            IF @debug = 1
            BEGIN
                PRINT @sql;
                RAISERROR('Inserting #wait_info', 0, 1) WITH NOWAIT;
                SET STATISTICS XML ON;
            END;

            INSERT INTO
                #wait_info WITH (TABLOCKX)
            (
                wait_info
            )
            EXEC sys.sp_executesql
                @sql,
                @params,
                @start_date,
                @end_date;

            IF @debug = 1
            BEGIN
                SET STATISTICS XML OFF;
            END;
        END;

        /*Grab data from the sp_server_diagnostics_component_result component*/
        SELECT
            @sql = N'
        SELECT
            sp_server_diagnostics_component_result =
                ISNULL
                (
                    xml.sp_server_diagnostics_component_result,
                    CONVERT(xml, N''<event>event</event>'')
                )
        FROM
        (
            SELECT
                sp_server_diagnostics_component_result =
                    TRY_CAST(fx.event_data AS xml)
            FROM sys.fn_xe_file_target_read_file(N''system_health*.xel'', NULL, NULL, NULL) AS fx
            WHERE fx.object_name = N''sp_server_diagnostics_component_result''
            AND   CONVERT(datetimeoffset(7), fx.timestamp_utc) BETWEEN @start_date AND @end_date
        ) AS xml
        CROSS APPLY xml.sp_server_diagnostics_component_result.nodes(''/event'') AS e(x)
        OPTION(RECOMPILE);';

        IF @debug = 1
        BEGIN
            PRINT @sql;
            RAISERROR('Inserting #sp_server_diagnostics_component_result', 0, 1) WITH NOWAIT;
            SET STATISTICS XML ON;
        END;

        INSERT INTO
            #sp_server_diagnostics_component_result WITH(TABLOCKX)
        (
            sp_server_diagnostics_component_result
        )
        EXEC sys.sp_executesql
            @sql,
            @params,
            @start_date,
            @end_date;

        IF @debug = 1
        BEGIN
            SET STATISTICS XML OFF;
        END;

        /*Grab data from the xml_deadlock_report component*/
        IF
        (
             @what_to_check IN ('all', 'locking')
         AND @skip_locks = 0
        )
        BEGIN
            IF @debug = 1
            BEGIN
                RAISERROR('Checking locking for not Managed Instance, 2017+', 0, 1) WITH NOWAIT;
            END;

            SELECT
                @sql = N'
            SELECT
                xml_deadlock_report =
                    ISNULL
                    (
                        xml.xml_deadlock_report,
                        CONVERT(xml, N''<event>event</event>'')
                    )
            FROM
            (
                SELECT
                    xml_deadlock_report =
                        TRY_CAST(fx.event_data AS xml)
                FROM sys.fn_xe_file_target_read_file(N''system_health*.xel'', NULL, NULL, NULL) AS fx
                WHERE fx.object_name = N''xml_deadlock_report''
                AND   CONVERT(datetimeoffset(7), fx.timestamp_utc) BETWEEN @start_date AND @end_date
            ) AS xml
            CROSS APPLY xml.xml_deadlock_report.nodes(''/event'') AS e(x)
            OPTION(RECOMPILE);';

            IF @debug = 1
            BEGIN
                PRINT @sql;
                RAISERROR('Inserting #xml_deadlock_report', 0, 1) WITH NOWAIT;
                SET STATISTICS XML ON;
            END;

            INSERT INTO
                #xml_deadlock_report WITH(TABLOCKX)
            (
                xml_deadlock_report
            )
            EXEC sys.sp_executesql
                @sql,
                @params,
                @start_date,
                @end_date;

            IF @debug = 1
            BEGIN
                SET STATISTICS XML OFF;
            END;
        END;
    END; /*End 2016+ data collection*/

    IF NOT EXISTS
    (
        SELECT
            1/0
        FROM sys.all_columns AS ac
        WHERE ac.object_id = OBJECT_ID(N'sys.fn_xe_file_target_read_file')
        AND   ac.name = N'timestamp_utc'
    )
    AND @mi = 0
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Checking waits for not Managed Instance, up to 2016', 0, 1) WITH NOWAIT;
        END;

        /*Grab data from the wait info component*/
        IF @what_to_check IN ('all', 'waits')
        BEGIN
           SELECT
               @sql = N'
           SELECT
               wait_info =
                   ISNULL
                   (
                       xml.wait_info,
                       CONVERT(xml, N''<event>event</event>'')
                   )
           FROM
           (
               SELECT
                   wait_info =
                       TRY_CAST(fx.event_data AS xml)
               FROM sys.fn_xe_file_target_read_file(N''system_health*.xel'', NULL, NULL, NULL) AS fx
               WHERE fx.object_name = N''wait_info''
           ) AS xml
           CROSS APPLY xml.wait_info.nodes(''/event'') AS e(x)
           CROSS APPLY (SELECT x.value( ''(@timestamp)[1]'', ''datetimeoffset'' )) ca ([utc_timestamp])
           WHERE ca.utc_timestamp >= @start_date
           AND   ca.utc_timestamp < @end_date
           OPTION(RECOMPILE);';

            IF @debug = 1
            BEGIN
                PRINT @sql;
                RAISERROR('Inserting #wait_info', 0, 1) WITH NOWAIT;
                SET STATISTICS XML ON;
            END;

           INSERT INTO
               #wait_info WITH (TABLOCKX)
           (
               wait_info
           )
           EXEC sys.sp_executesql
               @sql,
               @params,
               @start_date,
               @end_date;

           IF @debug = 1 BEGIN SET STATISTICS XML OFF; END;
       END;

        /*Grab data from the sp_server_diagnostics_component_result component*/
        IF @debug = 1
        BEGIN
            RAISERROR('Checking sp_server_diagnostics_component_result for not Managed Instance, 2017+', 0, 1) WITH NOWAIT;
        END;

        SELECT
            @sql = N'
        SELECT
            sp_server_diagnostics_component_result =
                ISNULL
                (
                    xml.sp_server_diagnostics_component_result,
                    CONVERT(xml, N''<event>event</event>'')
                )
        FROM
        (
            SELECT
                sp_server_diagnostics_component_result =
                    TRY_CAST(fx.event_data AS xml)
            FROM sys.fn_xe_file_target_read_file(N''system_health*.xel'', NULL, NULL, NULL) AS fx
            WHERE fx.object_name = N''sp_server_diagnostics_component_result''
        ) AS xml
        CROSS APPLY xml.sp_server_diagnostics_component_result.nodes(''/event'') AS e(x)
        CROSS APPLY (SELECT x.value( ''(@timestamp)[1]'', ''datetimeoffset'' )) ca ([utc_timestamp])
        WHERE ca.utc_timestamp >= @start_date
        AND   ca.utc_timestamp < @end_date
        OPTION(RECOMPILE);';

        IF @debug = 1
        BEGIN
            RAISERROR('Inserting #sp_server_diagnostics_component_result', 0, 1) WITH NOWAIT;
            PRINT @sql;
            SET STATISTICS XML ON;
        END;

        INSERT INTO
            #sp_server_diagnostics_component_result WITH(TABLOCKX)
        (
            sp_server_diagnostics_component_result
        )
        EXEC sys.sp_executesql
            @sql,
            @params,
            @start_date,
            @end_date;

        IF @debug = 1
        BEGIN
            SET STATISTICS XML OFF;
        END;

        /*Grab data from the xml_deadlock_report component*/
        IF
        (
             @what_to_check IN ('all', 'locking')
         AND @skip_locks = 0
        )
        BEGIN
            IF @debug = 1
            BEGIN
                RAISERROR('Checking locking for not Managed Instance', 0, 1) WITH NOWAIT;
            END;

            SELECT
                @sql = N'
            SELECT
                xml_deadlock_report =
                    ISNULL
                    (
                        xml.xml_deadlock_report,
                        CONVERT(xml, N''<event>event</event>'')
                    )
            FROM
            (
                SELECT
                    xml_deadlock_report =
                        TRY_CAST(fx.event_data AS xml)
                FROM sys.fn_xe_file_target_read_file(N''system_health*.xel'', NULL, NULL, NULL) AS fx
                WHERE fx.object_name = N''xml_deadlock_report''
            ) AS xml
            CROSS APPLY xml.xml_deadlock_report.nodes(''/event'') AS e(x)
            CROSS APPLY (SELECT x.value( ''(@timestamp)[1]'', ''datetimeoffset'' )) ca ([utc_timestamp])
            WHERE ca.utc_timestamp >= @start_date
            AND   ca.utc_timestamp < @end_date
            OPTION(RECOMPILE);';

            IF @debug = 1
            BEGIN
                PRINT @sql;
                RAISERROR('Inserting #xml_deadlock_report', 0, 1) WITH NOWAIT;
                SET STATISTICS XML ON;
            END;

            INSERT INTO
                #xml_deadlock_report WITH(TABLOCKX)
            (
                xml_deadlock_report
            )
            EXEC sys.sp_executesql
                @sql,
                @params,
                @start_date,
                @end_date;

            IF @debug = 1
            BEGIN
                SET STATISTICS XML OFF;
            END;
        END;
    END; /*End < 2017 collection*/

    IF @mi = 1
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Starting Managed Instance analysis', 0, 1) WITH NOWAIT;
            RAISERROR('Inserting #x', 0, 1) WITH NOWAIT;
        END;

        INSERT
            #x WITH(TABLOCKX)
        (
            x
        )
        SELECT
            x =
                ISNULL
                (
                    TRY_CAST(t.target_data AS xml),
                    CONVERT(xml, N'<event>event</event>')
                )
        FROM sys.dm_xe_session_targets AS t
        JOIN sys.dm_xe_sessions AS s
          ON s.address = t.event_session_address
        WHERE s.name = N'system_health'
        AND   t.target_name = N'ring_buffer'
        OPTION(RECOMPILE);

        IF @debug = 1
        BEGIN
            SELECT TOP (100)
                table_name = '#x, top 100 rows',
                x.*
            FROM #x AS x;
        END;

        IF @debug = 1
        BEGIN
            RAISERROR('Inserting #ring_buffer', 0, 1) WITH NOWAIT;
        END;

        INSERT
            #ring_buffer WITH(TABLOCKX)
        (
            ring_buffer
        )
        SELECT
            x = e.x.query('.')
        FROM
        (
            SELECT
                x
            FROM #x
        ) AS x
        CROSS APPLY x.x.nodes('//event') AS e(x)
        WHERE 1 = 1
        AND   e.x.exist('@timestamp[.>= sql:variable("@start_date") and .< sql:variable("@end_date")]') = 1
        AND   e.x.exist('@name[.= "security_error_ring_buffer_recorded"]') = 0
        AND   e.x.exist('@name[.= "error_reported"]') = 0
        AND   e.x.exist('@name[.= "memory_broker_ring_buffer_recorded"]') = 0
        AND   e.x.exist('@name[.= "connectivity_ring_buffer_recorded"]') = 0
        AND   e.x.exist('@name[.= "scheduler_monitor_system_health_ring_buffer_recorded"]') = 0
        OPTION(RECOMPILE);

        IF @debug = 1
        BEGIN
            SELECT TOP (100)
                table_name = '#ring_buffer, top 100 rows',
                x.*
            FROM #ring_buffer AS x;
        END;

        IF @what_to_check IN ('all', 'waits')
        BEGIN
            IF @debug = 1
            BEGIN
                RAISERROR('Checking Managed Instance waits', 0, 1) WITH NOWAIT;
                RAISERROR('Inserting #wait_info', 0, 1) WITH NOWAIT;
            END;

            INSERT
                #wait_info WITH(TABLOCKX)
            (
                wait_info
            )
            SELECT
                e.x.query('.')
            FROM #ring_buffer AS rb
            CROSS APPLY rb.ring_buffer.nodes('/event') AS e(x)
            WHERE e.x.exist('@name[.= "wait_info"]') = 1
            OPTION(RECOMPILE);
        END;

        IF @debug = 1
        BEGIN
            RAISERROR('Checking Managed Instance sp_server_diagnostics_component_result', 0, 1) WITH NOWAIT;
            RAISERROR('Inserting #sp_server_diagnostics_component_result', 0, 1) WITH NOWAIT;
        END;

        INSERT
            #sp_server_diagnostics_component_result WITH(TABLOCKX)
        (
            sp_server_diagnostics_component_result
        )
        SELECT
            e.x.query('.')
        FROM #ring_buffer AS rb
        CROSS APPLY rb.ring_buffer.nodes('/event') AS e(x)
        WHERE e.x.exist('@name[.= "sp_server_diagnostics_component_result"]') = 1
        OPTION(RECOMPILE);

        IF
        (
             @what_to_check IN ('all', 'locking')
         AND @skip_locks = 0
        )
        BEGIN
        IF @debug = 1
            BEGIN
                RAISERROR('Checking Managed Instance deadlocks', 0, 1) WITH NOWAIT;
                RAISERROR('Inserting #xml_deadlock_report', 0, 1) WITH NOWAIT;
            END;

            INSERT
                #xml_deadlock_report WITH(TABLOCKX)
            (
                xml_deadlock_report
            )
            SELECT
                e.x.query('.')
            FROM #ring_buffer AS rb
            CROSS APPLY rb.ring_buffer.nodes('/event') AS e(x)
            WHERE e.x.exist('@name[.= "xml_deadlock_report"]') = 1
            OPTION(RECOMPILE);
        END;
    END; /*End Managed Instance collection*/

    IF @debug = 1
    BEGIN
        SELECT TOP (100)
            table_name = '#wait_info, top 100 rows',
            x.*
        FROM #wait_info AS x;

        SELECT TOP (100)
            table_name = '#sp_server_diagnostics_component_result, top 100 rows',
            x.*
        FROM #sp_server_diagnostics_component_result AS x;

        SELECT TOP (100)
            table_name = '#xml_deadlock_report, top 100 rows',
            x.*
        FROM #xml_deadlock_report AS x;
    END;

    /*Parse out the wait_info data*/
    IF @what_to_check IN ('all', 'waits')
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Parsing queries with significant waits', 0, 1) WITH NOWAIT;
        END;

        SELECT
            event_time =
                DATEADD
                (
                    MINUTE,
                    DATEDIFF
                    (
                        MINUTE,
                        GETUTCDATE(),
                        SYSDATETIME()
                    ),
                    w.x.value('@timestamp', 'datetime2')
                ),
            wait_type = w.x.value('(data[@name="wait_type"]/text/text())[1]', 'nvarchar(60)'),
            duration_ms = CONVERT(bigint, w.x.value('(data[@name="duration"]/value/text())[1]', 'bigint')),
            signal_duration_ms = CONVERT(bigint, w.x.value('(data[@name="signal_duration"]/value/text())[1]', 'bigint')),
            wait_resource = w.x.value('(data[@name="wait_resource"]/value/text())[1]', 'nvarchar(256)'),
            sql_text_pre = w.x.value('(action[@name="sql_text"]/value/text())[1]', 'nvarchar(max)'),
            session_id = w.x.value('(action[@name="session_id"]/value/text())[1]', 'integer'),
            xml = w.x.query('.')
        INTO #waits_queries
        FROM #wait_info AS wi
        CROSS APPLY wi.wait_info.nodes('//event') AS w(x)
        WHERE w.x.exist('(action[@name="session_id"]/value/text())[.= 0]') = 0
        AND   w.x.exist('(action[@name="sql_text"]/value/text())') = 1
        AND   w.x.exist('(action[@name="sql_text"]/value/text()[contains(., "BACKUP")] )') = 0
        AND   w.x.exist('(data[@name="duration"]/value/text())[.>= sql:variable("@wait_duration_ms")]') = 1
        AND   NOT EXISTS
              (
                  SELECT
                      1/0
                  FROM #ignore AS i
                  WHERE w.x.exist('(data[@name="wait_type"]/text/text())[1][.= sql:column("i.wait_type")]') = 1
              )
        OPTION(RECOMPILE);

        IF @debug = 1
        BEGIN
            RAISERROR('Adding query_text to #waits_queries', 0, 1) WITH NOWAIT;
        END;

        ALTER TABLE #waits_queries
        ADD query_text AS
            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                sql_text_pre COLLATE Latin1_General_BIN2,
            NCHAR(31),N'?'),NCHAR(30),N'?'),NCHAR(29),N'?'),NCHAR(28),N'?'),NCHAR(27),N'?'),NCHAR(26),N'?'),NCHAR(25),N'?'),NCHAR(24),N'?'),NCHAR(23),N'?'),NCHAR(22),N'?'),
            NCHAR(21),N'?'),NCHAR(20),N'?'),NCHAR(19),N'?'),NCHAR(18),N'?'),NCHAR(17),N'?'),NCHAR(16),N'?'),NCHAR(15),N'?'),NCHAR(14),N'?'),NCHAR(12),N'?'),
            NCHAR(11),N'?'),NCHAR(8),N'?'),NCHAR(7),N'?'),NCHAR(6),N'?'),NCHAR(5),N'?'),NCHAR(4),N'?'),NCHAR(3),N'?'),NCHAR(2),N'?'),NCHAR(1),N'?'),NCHAR(0),N'?')
        PERSISTED;

        IF @debug = 1
        BEGIN
            SELECT TOP (100)
                table_name = '#waits_queries, top 100 rows',
                x.*
            FROM #waits_queries AS x
            ORDER BY
                x.event_time DESC;
        END;

        IF NOT EXISTS
        (
            SELECT
                1/0
            FROM #waits_queries AS wq
        )
        BEGIN
            SELECT
                finding =
                    CASE
                        WHEN @what_to_check NOT IN ('all', 'waits')
                        THEN 'waits skipped, @what_to_check set to ' +
                             @what_to_check
                        WHEN @what_to_check IN ('all', 'waits')
                        THEN 'no queries with significant waits found between ' +
                             RTRIM(CONVERT(date, @start_date)) +
                             ' and ' +
                             RTRIM(CONVERT(date, @end_date)) +
                             ' with a minimum duration of ' +
                             RTRIM(@wait_duration_ms) +
                             '.'
                        ELSE 'no queries with significant waits found!'
                    END;
        END;
        ELSE
        BEGIN
            SELECT
                finding = 'queries with significant waits',
                wq.event_time,
                wq.wait_type,
                duration_ms =
                    REPLACE
                    (
                        CONVERT
                        (
                            nvarchar(30),
                            CONVERT
                            (
                                money,
                                wq.duration_ms
                            ),
                            1
                        ),
                    N'.00',
                    N''
                    ),
                signal_duration_ms =
                    REPLACE
                    (
                        CONVERT
                        (
                            nvarchar(30),
                            CONVERT
                            (
                                money,
                                wq.signal_duration_ms
                            ),
                            1
                        ),
                    N'.00',
                    N''
                    ),
                wq.wait_resource,
                query_text =
                    (
                        SELECT
                            [processing-instruction(query)] =
                                wq.query_text
                        FOR XML
                            PATH(N''),
                            TYPE
                    ),
                wq.session_id
            FROM #waits_queries AS wq
            ORDER BY
                wq.duration_ms DESC
            OPTION(RECOMPILE);
        END;

        /*Waits by count*/
        IF @debug = 1
        BEGIN
            RAISERROR('Parsing #waits_by_count', 0, 1) WITH NOWAIT;
        END;

        SELECT
            event_time =
                DATEADD
                (
                    MINUTE,
                    DATEDIFF
                    (
                        MINUTE,
                        GETUTCDATE(),
                        SYSDATETIME()
                    ),
                    w.x.value('@timestamp', 'datetime2')
                ),
            wait_type = w2.x2.value('@waitType', 'nvarchar(60)'),
            waits = w2.x2.value('@waits', 'bigint'),
            average_wait_time_ms = CONVERT(bigint, w2.x2.value('@averageWaitTime', 'bigint')),
            max_wait_time_ms = CONVERT(bigint, w2.x2.value('@maxWaitTime', 'bigint')),
            xml = w.x.query('.')
        INTO #topwaits_count
        FROM #sp_server_diagnostics_component_result AS wi
        CROSS APPLY wi.sp_server_diagnostics_component_result.nodes('/event') AS w(x)
        CROSS APPLY w.x.nodes('/event/data/value/queryProcessing/topWaits/nonPreemptive/byCount/wait') AS w2(x2)
        WHERE w.x.exist('(data[@name="component"]/text[.= "QUERY_PROCESSING"])') = 1
        AND  (w.x.exist('(data[@name="state"]/text[.= "WARNING"])') = @warnings_only OR @warnings_only = 0)
        AND   NOT EXISTS
              (
                  SELECT
                      1/0
                  FROM #ignore AS i
                  WHERE w2.x2.exist('@waitType[.= sql:column("i.wait_type")]') = 1
              )
        OPTION(RECOMPILE);

        IF @debug = 1
        BEGIN
            SELECT TOP (100)
                table_name = '#topwaits_count, top 100 rows',
                x.*
            FROM #topwaits_count AS x
            ORDER BY
                x.event_time DESC;
        END;

        SELECT
            finding = 'waits by count',
            event_time_rounded =
                DATEADD
                (
                    MINUTE,
                    DATEDIFF
                    (
                        MINUTE,
                        '19000101',
                        tc.event_time
                    ) / @wait_round_interval_minutes *
                        @wait_round_interval_minutes,
                    '19000101'
                ),
            tc.wait_type,
            waits = SUM(CONVERT(bigint, tc.waits)),
            average_wait_time_ms = CONVERT(bigint, AVG(tc.average_wait_time_ms)),
            max_wait_time_ms = CONVERT(bigint, MAX(tc.max_wait_time_ms))
        INTO #tc
        FROM #topwaits_count AS tc
        GROUP BY
            tc.wait_type,
            DATEADD
            (
                MINUTE,
                DATEDIFF
                (
                    MINUTE,
                    '19000101',
                    tc.event_time
                ) / @wait_round_interval_minutes *
                    @wait_round_interval_minutes,
                '19000101'
            )
        OPTION(RECOMPILE);

        IF NOT EXISTS
        (
            SELECT
                1/0
            FROM #tc AS t
        )
        BEGIN
            SELECT
                finding =
                    CASE
                        WHEN @what_to_check NOT IN ('all', 'waits')
                        THEN 'waits skipped, @what_to_check set to ' +
                             @what_to_check
                        WHEN @what_to_check IN ('all', 'waits')
                        THEN 'no significant waits found between ' +
                             RTRIM(CONVERT(date, @start_date)) +
                             ' and ' +
                             RTRIM(CONVERT(date, @end_date)) +
                             '.'
                        ELSE 'no significant waits found!'
                    END;
        END;
        ELSE
        BEGIN
            SELECT
                t.finding,
                t.event_time_rounded,
                t.wait_type,
                waits =
                    REPLACE
                    (
                        CONVERT
                        (
                            nvarchar(30),
                            CONVERT
                            (
                                money,
                                t.waits
                            ),
                            1
                        ),
                    N'.00',
                    N''
                    ),
                average_wait_time_ms =
                    REPLACE
                    (
                        CONVERT
                        (
                            nvarchar(30),
                            CONVERT
                            (
                                money,
                                t.average_wait_time_ms
                            ),
                            1
                        ),
                    N'.00',
                    N''
                    ),
                max_wait_time_ms =
                    REPLACE
                    (
                        CONVERT
                        (
                            nvarchar(30),
                            CONVERT
                            (
                                money,
                                t.max_wait_time_ms
                            ),
                            1
                        ),
                    N'.00',
                    N''
                    )
            FROM #tc AS t
            ORDER BY
                t.event_time_rounded DESC,
                t.waits DESC
            OPTION(RECOMPILE);
        END;

        /*Grab waits by duration*/
        IF @debug = 1
        BEGIN
            RAISERROR('Parsing waits by duration', 0, 1) WITH NOWAIT;
        END;

        SELECT
            event_time =
                DATEADD
                (
                    MINUTE,
                    DATEDIFF
                    (
                        MINUTE,
                        GETUTCDATE(),
                        SYSDATETIME()
                    ),
                    w.x.value('@timestamp', 'datetime2')
                ),
            wait_type = w2.x2.value('@waitType', 'nvarchar(60)'),
            waits = w2.x2.value('@waits', 'bigint'),
            average_wait_time_ms = CONVERT(bigint, w2.x2.value('@averageWaitTime', 'bigint')),
            max_wait_time_ms = CONVERT(bigint, w2.x2.value('@maxWaitTime', 'bigint')),
            xml = w.x.query('.')
        INTO #topwaits_duration
        FROM #sp_server_diagnostics_component_result AS wi
        CROSS APPLY wi.sp_server_diagnostics_component_result.nodes('/event') AS w(x)
        CROSS APPLY w.x.nodes('/event/data/value/queryProcessing/topWaits/nonPreemptive/byDuration/wait') AS w2(x2)
        WHERE w.x.exist('(data[@name="component"]/text[.= "QUERY_PROCESSING"])') = 1
        AND  (w.x.exist('(data[@name="state"]/text[.= "WARNING"])') = @warnings_only OR @warnings_only = 0)
        AND   w2.x2.exist('@averageWaitTime[.>= sql:variable("@wait_duration_ms")]') = 1
        AND   NOT EXISTS
              (
                  SELECT
                      1/0
                  FROM #ignore AS i
                  WHERE w2.x2.exist('@waitType[.= sql:column("i.wait_type")]') = 1
              )
        OPTION(RECOMPILE);

        IF @debug = 1
        BEGIN
            SELECT TOP (100)
                table_name = '#topwaits_duration, top 100 rows',
                x.*
            FROM #topwaits_duration AS x
            ORDER BY
                x.event_time DESC;
        END;

        SELECT
            finding = 'waits by duration',
            event_time_rounded =
                DATEADD
                (
                    MINUTE,
                    DATEDIFF
                    (
                        MINUTE,
                        '19000101',
                        td.event_time
                    ) / @wait_round_interval_minutes *
                        @wait_round_interval_minutes,
                    '19000101'
                ),
            td.wait_type,
            td.waits,
            td.average_wait_time_ms,
            td.max_wait_time_ms
        INTO #td
        FROM #topwaits_duration AS td
        GROUP BY
            td.wait_type,
            DATEADD
            (
                MINUTE,
                DATEDIFF
                (
                    MINUTE,
                    '19000101',
                    td.event_time
                ) / @wait_round_interval_minutes *
                    @wait_round_interval_minutes,
                '19000101'
            ),
            td.waits,
            td.average_wait_time_ms,
            td.max_wait_time_ms
        OPTION(RECOMPILE);

        IF NOT EXISTS
        (
            SELECT
                1/0
            FROM #td AS t
        )
        BEGIN
            SELECT
                finding =
                    CASE
                        WHEN @what_to_check NOT IN ('all', 'waits')
                        THEN 'waits skipped, @what_to_check set to ' +
                             @what_to_check
                        WHEN @what_to_check IN ('all', 'waits')
                        THEN 'no significant waits found between ' +
                             RTRIM(CONVERT(date, @start_date)) +
                             ' and ' +
                             RTRIM(CONVERT(date, @end_date)) +
                             ' with a minimum average duration of ' +
                             RTRIM(@wait_duration_ms) +
                             '.'
                        ELSE 'no significant waits found!'
                    END;
        END;
        ELSE
        BEGIN
            SELECT
                x.finding,
                x.event_time_rounded,
                x.wait_type,
                x.average_wait_time_ms,
                x.max_wait_time_ms
            FROM
            (
                SELECT
                    t.finding,
                    t.event_time_rounded,
                    t.wait_type,
                    waits =
                        REPLACE
                        (
                            CONVERT
                            (
                                nvarchar(30),
                                CONVERT
                                (
                                    money,
                                    t.waits
                                ),
                                1
                            ),
                        N'.00',
                        N''
                        ),
                    average_wait_time_ms =
                        REPLACE
                        (
                            CONVERT
                            (
                                nvarchar(30),
                                CONVERT
                                (
                                    money,
                                    t.average_wait_time_ms
                                ),
                                1
                            ),
                        N'.00',
                        N''
                        ),
                    max_wait_time_ms =
                        REPLACE
                        (
                            CONVERT
                            (
                                nvarchar(30),
                                CONVERT
                                (
                                    money,
                                    t.max_wait_time_ms
                                ),
                                1
                            ),
                        N'.00',
                        N''
                        ),
                    s =
                        ROW_NUMBER() OVER
                        (
                            ORDER BY
                                t.event_time_rounded DESC,
                                t.waits DESC
                        ),
                    n =
                        ROW_NUMBER() OVER
                        (
                            PARTITION BY
                                t.wait_type,
                                t.waits,
                                t.average_wait_time_ms,
                                t.max_wait_time_ms
                            ORDER BY
                                t.event_time_rounded
                        )
                FROM #td AS t
            ) AS x
            WHERE x.n = 1
            ORDER BY
                x.s
            OPTION(RECOMPILE);
        END;
    END; /*End wait stats*/

    /*Grab IO stuff*/
    IF @what_to_check IN ('all', 'disk')
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Parsing disk stuff', 0, 1) WITH NOWAIT;
        END;

        SELECT
            event_time =
                DATEADD
                (
                    MINUTE,
                    DATEDIFF
                    (
                        MINUTE,
                        GETUTCDATE(),
                        SYSDATETIME()
                    ),
                    w.x.value('@timestamp', 'datetime2')
                ),
            state = w.x.value('(data[@name="state"]/text/text())[1]', 'nvarchar(256)'),
            ioLatchTimeouts = w.x.value('(/event/data[@name="data"]/value/ioSubsystem/@ioLatchTimeouts)[1]', 'bigint'),
            intervalLongIos = w.x.value('(/event/data[@name="data"]/value/ioSubsystem/@intervalLongIos)[1]', 'bigint'),
            totalLongIos = w.x.value('(/event/data[@name="data"]/value/ioSubsystem/@totalLongIos)[1]', 'bigint'),
            longestPendingRequests_duration_ms = CONVERT(bigint, w2.x2.value('@duration', 'bigint')),
            longestPendingRequests_filePath = w2.x2.value('@filePath', 'nvarchar(500)'),
            xml = w.x.query('.')
        INTO #io
        FROM #sp_server_diagnostics_component_result AS wi
        CROSS APPLY wi.sp_server_diagnostics_component_result.nodes('//event') AS w(x)
        OUTER APPLY w.x.nodes('/event/data/value/ioSubsystem/longestPendingRequests/pendingRequest') AS w2(x2)
        WHERE w.x.exist('(data[@name="component"]/text[.= "IO_SUBSYSTEM"])') = 1
        AND  (w.x.exist('(data[@name="state"]/text[.= "WARNING"])') = @warnings_only OR @warnings_only = 0)
        OPTION(RECOMPILE);

        IF @debug = 1
        BEGIN
            SELECT TOP (100)
                table_name = '#io, top 100 rows',
                x.*
            FROM #io AS x
            ORDER BY
                x.event_time DESC;
        END;

        SELECT
            finding = 'potential io issues',
            i.event_time,
            i.state,
            i.ioLatchTimeouts,
            i.intervalLongIos,
            i.totalLongIos,
            longestPendingRequests_duration_ms =
                ISNULL(SUM(i.longestPendingRequests_duration_ms), 0),
            longestPendingRequests_filePath =
                ISNULL(i.longestPendingRequests_filePath, 'N/A')
        INTO #i
        FROM #io AS i
        GROUP BY
            i.event_time,
            i.state,
            i.ioLatchTimeouts,
            i.intervalLongIos,
            i.totalLongIos,
            ISNULL(i.longestPendingRequests_filePath, 'N/A')
        OPTION(RECOMPILE);

        IF NOT EXISTS
        (
            SELECT
                1/0
            FROM #i AS i
        )
        BEGIN
            SELECT
                finding =
                    CASE
                        WHEN @what_to_check NOT IN ('all', 'disk')
                        THEN 'disk skipped, @what_to_check set to ' +
                             @what_to_check
                        WHEN @what_to_check IN ('all', 'disk')
                        THEN 'no io issues found between ' +
                             RTRIM(CONVERT(date, @start_date)) +
                             ' and ' +
                             RTRIM(CONVERT(date, @end_date)) +
                             ' with @warnings_only set to ' +
                             RTRIM(@warnings_only) +
                             '.'
                        ELSE 'no io issues found!'
                    END;
        END;
        ELSE
        BEGIN
            SELECT
                i.finding,
                i.event_time,
                i.state,
                i.ioLatchTimeouts,
                i.intervalLongIos,
                i.totalLongIos,
                longestPendingRequests_duration_ms =
                    REPLACE
                    (
                        CONVERT
                        (
                            nvarchar(30),
                            CONVERT
                            (
                                money,
                                i.longestPendingRequests_duration_ms
                            ),
                            1
                        ),
                    N'.00',
                    N''
                    ),
                i.longestPendingRequests_filePath
            FROM #i AS i
            ORDER BY
                i.event_time DESC
            OPTION(RECOMPILE);
        END;
    END; /*End disk*/

    /*Grab CPU details*/
    IF @what_to_check IN ('all', 'cpu')
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Parsing CPU stuff', 0, 1) WITH NOWAIT;
        END;

        SELECT
            event_time =
                DATEADD
                (
                    MINUTE,
                    DATEDIFF
                    (
                        MINUTE,
                        GETUTCDATE(),
                        SYSDATETIME()
                    ),
                    w.x.value('@timestamp', 'datetime2')
                ),
            name = w.x.value('@name', 'nvarchar(256)'),
            component = w.x.value('(data[@name="component"]/text/text())[1]', 'nvarchar(256)'),
            state = w.x.value('(data[@name="state"]/text/text())[1]', 'nvarchar(256)'),
            maxWorkers = w.x.value('(/event/data[@name="data"]/value/queryProcessing/@maxWorkers)[1]', 'bigint'),
            workersCreated = w.x.value('(/event/data[@name="data"]/value/queryProcessing/@workersCreated)[1]', 'bigint'),
            workersIdle = w.x.value('(/event/data[@name="data"]/value/queryProcessing/@workersIdle)[1]', 'bigint'),
            tasksCompletedWithinInterval = w.x.value('(//data[@name="data"]/value/queryProcessing/@tasksCompletedWithinInterval)[1]', 'bigint'),
            pendingTasks = w.x.value('(/event/data[@name="data"]/value/queryProcessing/@pendingTasks)[1]', 'bigint'),
            oldestPendingTaskWaitingTime = w.x.value('(/event/data[@name="data"]/value/queryProcessing/@oldestPendingTaskWaitingTime)[1]', 'bigint'),
            hasUnresolvableDeadlockOccurred = w.x.value('(/event/data[@name="data"]/value/queryProcessing/@hasUnresolvableDeadlockOccurred)[1]', 'bit'),
            hasDeadlockedSchedulersOccurred = w.x.value('(/event/data[@name="data"]/value/queryProcessing/@hasDeadlockedSchedulersOccurred)[1]', 'bit'),
            didBlockingOccur = w.x.exist('//data[@name="data"]/value/queryProcessing/blockingTasks/blocked-process-report'),
            xml = w.x.query('.')
        INTO #scheduler_details
        FROM #sp_server_diagnostics_component_result AS wi
        CROSS APPLY wi.sp_server_diagnostics_component_result.nodes('/event') AS w(x)
        WHERE w.x.exist('(data[@name="component"]/text[.= "QUERY_PROCESSING"])') = 1
        AND  (w.x.exist('(data[@name="state"]/text[.= "WARNING"])') = @warnings_only OR @warnings_only IS NULL)
        AND  (w.x.exist('(/event/data[@name="data"]/value/queryProcessing/@pendingTasks[.>= sql:variable("@pending_task_threshold")])') = 1 OR @warnings_only = 0)
        OPTION(RECOMPILE);

        IF @debug = 1
        BEGIN
            SELECT TOP (100)
                table_name = '#scheduler_details, top 100 rows',
                x.*
            FROM #scheduler_details AS x
            ORDER BY
                x.event_time DESC;
        END;

        IF NOT EXISTS
        (
            SELECT
                1/0
            FROM #scheduler_details AS sd
        )
        BEGIN
            SELECT
                finding =
                    CASE
                        WHEN @what_to_check NOT IN ('all', 'cpu')
                        THEN 'cpu skipped, @what_to_check set to ' +
                             @what_to_check
                        WHEN @what_to_check IN ('all', 'cpu')
                        THEN 'no cpu issues found between ' +
                             RTRIM(CONVERT(date, @start_date)) +
                             ' and ' +
                             RTRIM(CONVERT(date, @end_date)) +
                             ' with @warnings_only set to ' +
                             RTRIM(@warnings_only) +
                             '.'
                        ELSE 'no cpu issues found!'
                    END;
        END;
        ELSE
        BEGIN
            SELECT
                finding = 'cpu task details',
                sd.event_time,
                sd.state,
                sd.maxWorkers,
                sd.workersCreated,
                sd.workersIdle,
                sd.tasksCompletedWithinInterval,
                sd.pendingTasks,
                sd.oldestPendingTaskWaitingTime,
                sd.hasUnresolvableDeadlockOccurred,
                sd.hasDeadlockedSchedulersOccurred,
                sd.didBlockingOccur
            FROM #scheduler_details AS sd
            ORDER BY
                sd.event_time DESC
            OPTION(RECOMPILE);
        END;
    END; /*End CPU*/

    /*Grab memory details*/
    IF @what_to_check IN ('all', 'memory')
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Parsing memory stuff', 0, 1) WITH NOWAIT;
        END;

        SELECT
            event_time =
                DATEADD
                (
                    MINUTE,
                    DATEDIFF
                    (
                        MINUTE,
                        GETUTCDATE(),
                        SYSDATETIME()
                    ),
                    s.sp_server_diagnostics_component_result.value('(//@timestamp)[1]', 'datetime2')
                ),
            lastNotification = r.c.value('@lastNotification', 'varchar(128)'),
            outOfMemoryExceptions = r.c.value('@outOfMemoryExceptions', 'bigint'),
            isAnyPoolOutOfMemory = r.c.value('@isAnyPoolOutOfMemory', 'bit'),
            processOutOfMemoryPeriod = r.c.value('@processOutOfMemoryPeriod', 'bigint'),
            name = r.c.value('(//memoryReport/@name)[1]', 'varchar(128)'),
            available_physical_memory_gb = CONVERT(bigint, r.c.value('(//memoryReport/entry[@description[.="Available Physical Memory"]]/@value)[1]', 'bigint') / 1024 / 1024 / 1024),
            available_virtual_memory_gb =  CONVERT(bigint, r.c.value('(//memoryReport/entry[@description[.="Available Virtual Memory"]]/@value)[1]', 'bigint') / 1024 / 1024 / 1024),
            available_paging_file_gb = CONVERT(bigint, r.c.value('(//memoryReport/entry[@description[.="Available Paging File"]]/@value)[1]', 'bigint') / 1024 / 1024 / 1024),
            working_set_gb = CONVERT(bigint, r.c.value('(//memoryReport/entry[@description[.="Working Set"]]/@value)[1]', 'bigint') / 1024 / 1024 / 1024),
            percent_of_committed_memory_in_ws = r.c.value('(//memoryReport/entry[@description[.="Percent of Committed Memory in WS"]]/@value)[1]', 'bigint'),
            page_faults = r.c.value('(//memoryReport/entry[@description[.="Page Faults"]]/@value)[1]', 'bigint'),
            system_physical_memory_high = r.c.value('(//memoryReport/entry[@description[.="System physical memory high"]]/@value)[1]', 'bigint'),
            system_physical_memory_low = r.c.value('(//memoryReport/entry[@description[.="System physical memory low"]]/@value)[1]', 'bigint'),
            process_physical_memory_low = r.c.value('(//memoryReport/entry[@description[.="Process physical memory low"]]/@value)[1]', 'bigint'),
            process_virtual_memory_low = r.c.value('(//memoryReport/entry[@description[.="Process virtual memory low"]]/@value)[1]', 'bigint'),
            vm_reserved_gb = CONVERT(bigint, r.c.value('(//memoryReport/entry[@description[.="VM Reserved"]]/@value)[1]', 'bigint') / 1024 / 1024),
            vm_committed_gb = CONVERT(bigint, r.c.value('(//memoryReport/entry[@description[.="VM Committed"]]/@value)[1]', 'bigint') / 1024 / 1024),
            locked_pages_allocated = r.c.value('(//memoryReport/entry[@description[.="Locked Pages Allocated"]]/@value)[1]', 'bigint'),
            large_pages_allocated = r.c.value('(//memoryReport/entry[@description[.="Large Pages Allocated"]]/@value)[1]', 'bigint'),
            emergency_memory_gb = CONVERT(bigint, r.c.value('(//memoryReport/entry[@description[.="Emergency Memory"]]/@value)[1]', 'bigint') / 1024 / 1024),
            emergency_memory_in_use_gb = CONVERT(bigint, r.c.value('(//memoryReport/entry[@description[.="Emergency Memory In Use"]]/@value)[1]', 'bigint') / 1024 / 1024),
            target_committed_gb = CONVERT(bigint, r.c.value('(//memoryReport/entry[@description[.="Target Committed"]]/@value)[1]', 'bigint') / 1024 / 1024),
            current_committed_gb = CONVERT(bigint, r.c.value('(//memoryReport/entry[@description[.="Current Committed"]]/@value)[1]', 'bigint') / 1024 / 1024),
            pages_allocated = r.c.value('(//memoryReport/entry[@description[.="Pages Allocated"]]/@value)[1]', 'bigint'),
            pages_reserved = r.c.value('(//memoryReport/entry[@description[.="Pages Reserved"]]/@value)[1]', 'bigint'),
            pages_free = r.c.value('(//memoryReport/entry[@description[.="Pages Free"]]/@value)[1]', 'bigint'),
            pages_in_use = r.c.value('(//memoryReport/entry[@description[.="Pages In Use"]]/@value)[1]', 'bigint'),
            page_alloc_potential = r.c.value('(//memoryReport/entry[@description[.="Page Alloc Potential"]]/@value)[1]', 'bigint'),
            numa_growth_phase = r.c.value('(//memoryReport/entry[@description[.="NUMA Growth Phase"]]/@value)[1]', 'bigint'),
            last_oom_factor = r.c.value('(//memoryReport/entry[@description[.="Last OOM Factor"]]/@value)[1]', 'bigint'),
            last_os_error = r.c.value('(//memoryReport/entry[@description[.="Last OS Error"]]/@value)[1]', 'bigint'),
            xml = r.c.query('.')
        INTO #memory
        FROM #sp_server_diagnostics_component_result AS s
        CROSS APPLY s.sp_server_diagnostics_component_result.nodes('/event/data/value/resource') AS r(c)
        WHERE (r.c.exist('@lastNotification[.= "RESOURCE_MEMPHYSICAL_LOW"]') = @warnings_only OR @warnings_only = 0)
        OPTION(RECOMPILE);

        IF @debug = 1
        BEGIN
            SELECT TOP (100)
                table_name = '#memory, top 100 rows',
                x.*
            FROM #memory AS x
            ORDER BY
                x.event_time DESC;
        END;

        IF NOT EXISTS
        (
            SELECT
                1/0
            FROM #memory AS m
        )
        BEGIN
            SELECT
                finding =
                    CASE
                        WHEN @what_to_check NOT IN ('all', 'memory')
                        THEN 'memory skipped, @what_to_check set to ' +
                             @what_to_check
                        WHEN @what_to_check IN ('all', 'memory')
                        THEN 'no memory issues found between ' +
                             RTRIM(CONVERT(date, @start_date)) +
                             ' and ' +
                             RTRIM(CONVERT(date, @end_date)) +
                             ' with @warnings_only set to ' +
                             RTRIM(@warnings_only) +
                             '.'
                        ELSE 'no memory issues found!'
                    END;
        END;
        ELSE
        BEGIN
            SELECT
                finding = 'memory conditions',
                m.event_time,
                m.lastNotification,
                m.outOfMemoryExceptions,
                m.isAnyPoolOutOfMemory,
                m.processOutOfMemoryPeriod,
                m.name,
                m.available_physical_memory_gb,
                m.available_virtual_memory_gb,
                m.available_paging_file_gb,
                m.working_set_gb,
                m.percent_of_committed_memory_in_ws,
                m.page_faults,
                m.system_physical_memory_high,
                m.system_physical_memory_low,
                m.process_physical_memory_low,
                m.process_virtual_memory_low,
                m.vm_reserved_gb,
                m.vm_committed_gb,
                m.locked_pages_allocated,
                m.large_pages_allocated,
                m.emergency_memory_gb,
                m.emergency_memory_in_use_gb,
                m.target_committed_gb,
                m.current_committed_gb,
                m.pages_allocated,
                m.pages_reserved,
                m.pages_free,
                m.pages_in_use,
                m.page_alloc_potential,
                m.numa_growth_phase,
                m.last_oom_factor,
                m.last_os_error
            FROM #memory AS m
            ORDER BY
                m.event_time DESC
            OPTION(RECOMPILE);
        END;
    END; /*End memory*/

    /*Grab health stuff*/
    IF @what_to_check IN ('all', 'system')
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Parsing system stuff', 0, 1) WITH NOWAIT;
        END;

        SELECT
            event_time =
                DATEADD
                (
                    MINUTE,
                    DATEDIFF
                    (
                        MINUTE,
                        GETUTCDATE(),
                        SYSDATETIME()
                    ),
                    w.x.value('@timestamp', 'datetime2')
                ),
            state = w.x.value('(data[@name="state"]/text/text())[1]', 'nvarchar(256)'),
            spinlockBackoffs = w.x.value('(/event/data[@name="data"]/value/system/@spinlockBackoffs)[1]', 'bigint'),
            sickSpinlockType = w.x.value('(/event/data[@name="data"]/value/system/@sickSpinlockType)[1]', 'nvarchar(256)'),
            sickSpinlockTypeAfterAv = w.x.value('(/event/data[@name="data"]/value/system/@sickSpinlockTypeAfterAv)[1]', 'nvarchar(256)'),
            latchWarnings = w.x.value('(/event/data[@name="data"]/value/system/@latchWarnings)[1]', 'bigint'),
            isAccessViolationOccurred = w.x.value('(/event/data[@name="data"]/value/system/@isAccessViolationOccurred)[1]', 'bigint'),
            writeAccessViolationCount = w.x.value('(/event/data[@name="data"]/value/system/@writeAccessViolationCount)[1]', 'bigint'),
            totalDumpRequests = w.x.value('(/event/data[@name="data"]/value/system/@totalDumpRequests)[1]', 'bigint'),
            intervalDumpRequests = w.x.value('(/event/data[@name="data"]/value/system/@intervalDumpRequests)[1]', 'bigint'),
            nonYieldingTasksReported = w.x.value('(/event/data[@name="data"]/value/system/@nonYieldingTasksReported)[1]', 'bigint'),
            pageFaults = w.x.value('(/event/data[@name="data"]/value/system/@pageFaults)[1]', 'bigint'),
            systemCpuUtilization = w.x.value('(/event/data[@name="data"]/value/system/@systemCpuUtilization)[1]', 'bigint'),
            sqlCpuUtilization = w.x.value('(/event/data[@name="data"]/value/system/@sqlCpuUtilization)[1]', 'bigint'),
            BadPagesDetected = w.x.value('(/event/data[@name="data"]/value/system/@BadPagesDetected)[1]', 'bigint'),
            BadPagesFixed = w.x.value('(/event/data[@name="data"]/value/system/@BadPagesFixed)[1]', 'bigint'),
            xml = w.x.query('.')
        INTO #health
        FROM #sp_server_diagnostics_component_result AS wi
        CROSS APPLY wi.sp_server_diagnostics_component_result.nodes('//event') AS w(x)
        WHERE w.x.exist('(data[@name="component"]/text[.= "SYSTEM"])') = 1
        AND  (w.x.exist('(data[@name="state"]/text[.= "WARNING"])') = @warnings_only OR @warnings_only = 0)
        OPTION(RECOMPILE);

        IF @debug = 1
        BEGIN
            SELECT TOP (100)
                table_name = '#health, top 100 rows',
                x.*
            FROM #health AS x
            ORDER BY
                x.event_time DESC;
        END;

        IF NOT EXISTS
        (
            SELECT
                1/0
            FROM #health AS h
        )
        BEGIN
            SELECT
                finding =
                    CASE
                        WHEN @what_to_check NOT IN ('all', 'system')
                        THEN 'system health skipped, @what_to_check set to ' +
                             @what_to_check
                        WHEN @what_to_check IN ('all', 'system')
                        THEN 'no system health issues found between ' +
                             RTRIM(CONVERT(date, @start_date)) +
                             ' and ' +
                             RTRIM(CONVERT(date, @end_date)) +
                             ' with @warnings_only set to ' +
                             RTRIM(@warnings_only) +
                             '.'
                        ELSE 'no system health issues found!'
                    END;
        END;
        ELSE
        BEGIN
            SELECT
                finding = 'overall system health',
                h.event_time,
                h.state,
                h.spinlockBackoffs,
                h.sickSpinlockType,
                h.sickSpinlockTypeAfterAv,
                h.latchWarnings,
                h.isAccessViolationOccurred,
                h.writeAccessViolationCount,
                h.totalDumpRequests,
                h.intervalDumpRequests,
                h.nonYieldingTasksReported,
                h.pageFaults,
                h.systemCpuUtilization,
                h.sqlCpuUtilization,
                h.BadPagesDetected,
                h.BadPagesFixed
            FROM #health AS h
            ORDER BY
                h.event_time DESC
            OPTION(RECOMPILE);
        END;
    END; /*End system*/

    /*Grab useless stuff*/

    /*
    I'm pulling this out for now, until I find a good use for it.
    SELECT
        event_time =
            DATEADD
            (
                MINUTE,
                DATEDIFF
                (
                    MINUTE,
                    GETUTCDATE(),
                    SYSDATETIME()
                ),
                w.x.value('(//@timestamp)[1]', 'datetime2')
            ),
        sessionId =
            w2.x2.value('@sessionId', 'bigint'),
        requestId =
            w2.x2.value('@requestId', 'bigint'),
        command =
            w2.x2.value('@command', 'nvarchar(256)'),
        taskAddress =
            CONVERT
            (
                binary(8),
                RIGHT
                (
                    '0000000000000000' +
                    SUBSTRING
                    (
                        w2.x2.value('@taskAddress', 'varchar(18)'),
                        3,
                        18
                    ),
                    16
                ),
                2
            ),
        cpuUtilization =
            w2.x2.value('@cpuUtilization', 'bigint'),
        cpuTimeMs =
            w2.x2.value('@cpuTimeMs', 'bigint'),
        xml = w2.x2.query('.')
    INTO #useless
    FROM #sp_server_diagnostics_component_result AS wi
    CROSS APPLY wi.sp_server_diagnostics_component_result.nodes('//event') AS w(x)
    CROSS APPLY w.x.nodes('//data[@name="data"]/value/queryProcessing/cpuIntensiveRequests/request') AS w2(x2)
    WHERE w.x.exist('(data[@name="component"]/text[.= "QUERY_PROCESSING"])') = 1
    AND   w.x.exist('//data[@name="data"]/value/queryProcessing/cpuIntensiveRequests/request') = 1
    AND  (w.x.exist('(data[@name="state"]/text[.= "WARNING"])') = @warnings_only OR @warnings_only IS NULL)
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        SELECT TOP (100) table_name = '#useless, top 100 rows', x.* FROM #useless AS x ORDER BY x.event_time DESC;
    END;

    SELECT
        finding = 'cpu intensive requests',
        u.event_time,
        u.sessionId,
        u.requestId,
        u.command,
        u.taskAddress,
        u.cpuUtilization,
        u.cpuTimeMs
    FROM #useless AS u
    ORDER BY
        u.cpuTimeMs DESC
    OPTION(RECOMPILE);
    */

    /*Grab blocking stuff*/
    IF
    (
        @what_to_check IN ('all', 'locking')
    AND @skip_locks = 0
    )
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Parsing locking stuff', 0, 1) WITH NOWAIT;
        END;

        SELECT
            event_time =
                DATEADD
                (
                    MINUTE,
                    DATEDIFF
                    (
                        MINUTE,
                        GETUTCDATE(),
                        SYSDATETIME()
                    ),
                    w.x.value('(//@timestamp)[1]', 'datetime2')
                ),
            human_events_xml = w.x.query('//data[@name="data"]/value/queryProcessing/blockingTasks/blocked-process-report')
        INTO #blocking_xml
        FROM #sp_server_diagnostics_component_result AS wi
        CROSS APPLY wi.sp_server_diagnostics_component_result.nodes('//event') AS w(x)
        WHERE w.x.exist('(data[@name="component"]/text[.= "QUERY_PROCESSING"])') = 1
        AND   w.x.exist('//data[@name="data"]/value/queryProcessing/blockingTasks/blocked-process-report') = 1
        AND  (w.x.exist('(data[@name="state"]/text[.= "WARNING"])') = @warnings_only OR @warnings_only = 0)
        OPTION(RECOMPILE);

        IF @debug = 1
        BEGIN
            SELECT TOP (100)
                table_name = '#blocking_xml, top 100 rows',
                x.*
            FROM #blocking_xml AS x
            ORDER BY
                x.event_time DESC;
        END;

        /*Blocked queries*/
        IF @debug = 1
        BEGIN
            RAISERROR('Parsing blocked queries', 0, 1) WITH NOWAIT;
        END;

        SELECT
            bx.event_time,
            currentdbname = bd.value('(process/@currentdbname)[1]', 'nvarchar(128)'),
            spid = bd.value('(process/@spid)[1]', 'int'),
            ecid = bd.value('(process/@ecid)[1]', 'int'),
            query_text_pre = bd.value('(process/inputbuf/text())[1]', 'nvarchar(MAX)'),
            wait_time = bd.value('(process/@waittime)[1]', 'bigint'),
            lastbatchstarted = bd.value('(process/@lastbatchstarted)[1]', 'datetime2'),
            lastbatchcompleted = bd.value('(process/@lastbatchcompleted)[1]', 'datetime2'),
            wait_resource = bd.value('(process/@waitresource)[1]', 'nvarchar(100)'),
            status = bd.value('(process/@status)[1]', 'nvarchar(10)'),
            priority = bd.value('(process/@priority)[1]', 'int'),
            transaction_count = bd.value('(process/@trancount)[1]', 'int'),
            client_app = bd.value('(process/@clientapp)[1]', 'nvarchar(256)'),
            host_name = bd.value('(process/@hostname)[1]', 'nvarchar(256)'),
            login_name = bd.value('(process/@loginname)[1]', 'nvarchar(256)'),
            isolation_level = bd.value('(process/@isolationlevel)[1]', 'nvarchar(50)'),
            log_used = bd.value('(process/@logused)[1]', 'bigint'),
            clientoption1 = bd.value('(process/@clientoption1)[1]', 'bigint'),
            clientoption2 = bd.value('(process/@clientoption1)[1]', 'bigint'),
            activity = CASE WHEN bd.exist('//blocked-process-report/blocked-process') = 1 THEN 'blocked' END,
            blocked_process_report = bd.query('.')
        INTO #blocked
        FROM #blocking_xml AS bx
        OUTER APPLY bx.human_events_xml.nodes('/event') AS oa(c)
        OUTER APPLY oa.c.nodes('//blocked-process-report/blocked-process') AS bd(bd)
        WHERE bd.exist('process/@spid') = 1
        OPTION(RECOMPILE);

        IF @debug = 1
        BEGIN
            RAISERROR('Adding query_text to #blocked', 0, 1) WITH NOWAIT;
        END;

        ALTER TABLE #blocked
        ADD query_text AS
           REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
           REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
           REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
               query_text_pre COLLATE Latin1_General_BIN2,
           NCHAR(31),N'?'),NCHAR(30),N'?'),NCHAR(29),N'?'),NCHAR(28),N'?'),NCHAR(27),N'?'),NCHAR(26),N'?'),NCHAR(25),N'?'),NCHAR(24),N'?'),NCHAR(23),N'?'),NCHAR(22),N'?'),
           NCHAR(21),N'?'),NCHAR(20),N'?'),NCHAR(19),N'?'),NCHAR(18),N'?'),NCHAR(17),N'?'),NCHAR(16),N'?'),NCHAR(15),N'?'),NCHAR(14),N'?'),NCHAR(12),N'?'),
           NCHAR(11),N'?'),NCHAR(8),N'?'),NCHAR(7),N'?'),NCHAR(6),N'?'),NCHAR(5),N'?'),NCHAR(4),N'?'),NCHAR(3),N'?'),NCHAR(2),N'?'),NCHAR(1),N'?'),NCHAR(0),N'?')
        PERSISTED;

        IF @debug = 1
        BEGIN
            SELECT TOP (100)
                table_name = '#blocked, top 100 rows',
                x.*
            FROM #blocked AS x
            ORDER BY
                x.event_time DESC;
        END;

        /*Blocking queries*/
        IF @debug = 1
        BEGIN
            RAISERROR('Parsing blocking queries', 0, 1) WITH NOWAIT;
        END;

        SELECT
            bx.event_time,
            currentdbname = bg.value('(process/@currentdbname)[1]', 'nvarchar(128)'),
            spid = bg.value('(process/@spid)[1]', 'int'),
            ecid = bg.value('(process/@ecid)[1]', 'int'),
            query_text_pre = bg.value('(process/inputbuf/text())[1]', 'nvarchar(MAX)'),
            wait_time = bg.value('(process/@waittime)[1]', 'bigint'),
            last_transaction_started = bg.value('(process/@lastbatchstarted)[1]', 'datetime2'),
            last_transaction_completed = bg.value('(process/@lastbatchcompleted)[1]', 'datetime2'),
            wait_resource = bg.value('(process/@waitresource)[1]', 'nvarchar(100)'),
            status = bg.value('(process/@status)[1]', 'nvarchar(10)'),
            priority = bg.value('(process/@priority)[1]', 'int'),
            transaction_count = bg.value('(process/@trancount)[1]', 'int'),
            client_app = bg.value('(process/@clientapp)[1]', 'nvarchar(256)'),
            host_name = bg.value('(process/@hostname)[1]', 'nvarchar(256)'),
            login_name = bg.value('(process/@loginname)[1]', 'nvarchar(256)'),
            isolation_level = bg.value('(process/@isolationlevel)[1]', 'nvarchar(50)'),
            log_used = bg.value('(process/@logused)[1]', 'bigint'),
            clientoption1 = bg.value('(process/@clientoption1)[1]', 'bigint'),
            clientoption2 = bg.value('(process/@clientoption1)[1]', 'bigint'),
            activity = CASE WHEN bg.exist('//blocked-process-report/blocking-process') = 1 THEN 'blocking' END,
            blocked_process_report = bg.query('.')
        INTO #blocking
        FROM #blocking_xml AS bx
        OUTER APPLY bx.human_events_xml.nodes('/event') AS oa(c)
        OUTER APPLY oa.c.nodes('//blocked-process-report/blocking-process') AS bg(bg)
        WHERE bg.exist('process/@spid') = 1
        OPTION(RECOMPILE);

        IF @debug = 1
        BEGIN
            RAISERROR('Adding query_text to #blocking', 0, 1) WITH NOWAIT;
        END;

        ALTER TABLE #blocking
        ADD query_text AS
           REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
           REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
           REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
               query_text_pre COLLATE Latin1_General_BIN2,
           NCHAR(31),N'?'),NCHAR(30),N'?'),NCHAR(29),N'?'),NCHAR(28),N'?'),NCHAR(27),N'?'),NCHAR(26),N'?'),NCHAR(25),N'?'),NCHAR(24),N'?'),NCHAR(23),N'?'),NCHAR(22),N'?'),
           NCHAR(21),N'?'),NCHAR(20),N'?'),NCHAR(19),N'?'),NCHAR(18),N'?'),NCHAR(17),N'?'),NCHAR(16),N'?'),NCHAR(15),N'?'),NCHAR(14),N'?'),NCHAR(12),N'?'),
           NCHAR(11),N'?'),NCHAR(8),N'?'),NCHAR(7),N'?'),NCHAR(6),N'?'),NCHAR(5),N'?'),NCHAR(4),N'?'),NCHAR(3),N'?'),NCHAR(2),N'?'),NCHAR(1),N'?'),NCHAR(0),N'?')
        PERSISTED;

        IF @debug = 1
        BEGIN
            SELECT TOP (100)
                table_name = '#blocking, top 100 rows',
                x.*
            FROM #blocking AS x
            ORDER BY
                x.event_time DESC;
        END;

        /*Put it together*/
        IF @debug = 1
        BEGIN
            RAISERROR('Inserting to #blocks', 0, 1) WITH NOWAIT;
        END;

        SELECT
            kheb.event_time,
            kheb.currentdbname,
            kheb.activity,
            kheb.spid,
            kheb.ecid,
            query_text =
                CASE
                    WHEN kheb.query_text
                         LIKE CONVERT(nvarchar(1), 0x0a00, 0) + N'Proc |[Database Id = %' ESCAPE N'|'
                    THEN
                        (
                            SELECT
                                [processing-instruction(query)] =
                                    OBJECT_SCHEMA_NAME
                                    (
                                            SUBSTRING
                                            (
                                                kheb.query_text,
                                                CHARINDEX(N'Object Id = ', kheb.query_text) + 12,
                                                LEN(kheb.query_text) - (CHARINDEX(N'Object Id = ', kheb.query_text) + 12)
                                            )
                                            ,
                                            SUBSTRING
                                            (
                                                kheb.query_text,
                                                CHARINDEX(N'Database Id = ', kheb.query_text) + 14,
                                                CHARINDEX(N'Object Id', kheb.query_text) - (CHARINDEX(N'Database Id = ', kheb.query_text) + 14)
                                            )
                                    ) +
                                    N'.' +
                                    OBJECT_NAME
                                    (
                                         SUBSTRING
                                         (
                                             kheb.query_text,
                                             CHARINDEX(N'Object Id = ', kheb.query_text) + 12,
                                             LEN(kheb.query_text) - (CHARINDEX(N'Object Id = ', kheb.query_text) + 12)
                                         )
                                         ,
                                         SUBSTRING
                                         (
                                             kheb.query_text,
                                             CHARINDEX(N'Database Id = ', kheb.query_text) + 14,
                                             CHARINDEX(N'Object Id', kheb.query_text) - (CHARINDEX(N'Database Id = ', kheb.query_text) + 14)
                                         )
                                    )
                            FOR XML
                                PATH(N''),
                                TYPE
                        )
                    ELSE
                        (
                            SELECT
                                [processing-instruction(query)] =
                                    kheb.query_text
                            FOR XML
                                PATH(N''),
                                TYPE
                        )
                END,
            wait_time_ms =
                kheb.wait_time,
            kheb.status,
            kheb.isolation_level,
            kheb.transaction_count,
            kheb.last_transaction_started,
            kheb.last_transaction_completed,
            client_option_1 =
                SUBSTRING
                (
                    CASE WHEN kheb.clientoption1 & 1 = 1 THEN ', DISABLE_DEF_CNST_CHECK' ELSE '' END +
                    CASE WHEN kheb.clientoption1 & 2 = 2 THEN ', IMPLICIT_TRANSACTIONS' ELSE '' END +
                    CASE WHEN kheb.clientoption1 & 4 = 4 THEN ', CURSOR_CLOSE_ON_COMMIT' ELSE '' END +
                    CASE WHEN kheb.clientoption1 & 8 = 8 THEN ', ANSI_WARNINGS' ELSE '' END +
                    CASE WHEN kheb.clientoption1 & 16 = 16 THEN ', ANSI_PADDING' ELSE '' END +
                    CASE WHEN kheb.clientoption1 & 32 = 32 THEN ', ANSI_NULLS' ELSE '' END +
                    CASE WHEN kheb.clientoption1 & 64 = 64 THEN ', ARITHABORT' ELSE '' END +
                    CASE WHEN kheb.clientoption1 & 128 = 128 THEN ', ARITHIGNORE' ELSE '' END +
                    CASE WHEN kheb.clientoption1 & 256 = 256 THEN ', QUOTED_IDENTIFIER' ELSE '' END +
                    CASE WHEN kheb.clientoption1 & 512 = 512 THEN ', NOCOUNT' ELSE '' END +
                    CASE WHEN kheb.clientoption1 & 1024 = 1024 THEN ', ANSI_NULL_DFLT_ON' ELSE '' END +
                    CASE WHEN kheb.clientoption1 & 2048 = 2048 THEN ', ANSI_NULL_DFLT_OFF' ELSE '' END +
                    CASE WHEN kheb.clientoption1 & 4096 = 4096 THEN ', CONCAT_NULL_YIELDS_NULL' ELSE '' END +
                    CASE WHEN kheb.clientoption1 & 8192 = 8192 THEN ', NUMERIC_ROUNDABORT' ELSE '' END +
                    CASE WHEN kheb.clientoption1 & 16384 = 16384 THEN ', XACT_ABORT' ELSE '' END,
                    3,
                    8000
                ),
            client_option_2 =
                SUBSTRING
                (
                    CASE WHEN kheb.clientoption2 & 1024 = 1024 THEN ', DB CHAINING' ELSE '' END +
                    CASE WHEN kheb.clientoption2 & 2048 = 2048 THEN ', NUMERIC ROUNDABORT' ELSE '' END +
                    CASE WHEN kheb.clientoption2 & 4096 = 4096 THEN ', ARITHABORT' ELSE '' END +
                    CASE WHEN kheb.clientoption2 & 8192 = 8192 THEN ', ANSI PADDING' ELSE '' END +
                    CASE WHEN kheb.clientoption2 & 16384 = 16384 THEN ', ANSI NULL DEFAULT' ELSE '' END +
                    CASE WHEN kheb.clientoption2 & 65536 = 65536 THEN ', CONCAT NULL YIELDS NULL' ELSE '' END +
                    CASE WHEN kheb.clientoption2 & 131072 = 131072 THEN ', RECURSIVE TRIGGERS' ELSE '' END +
                    CASE WHEN kheb.clientoption2 & 1048576 = 1048576 THEN ', DEFAULT TO LOCAL CURSOR' ELSE '' END +
                    CASE WHEN kheb.clientoption2 & 8388608 = 8388608 THEN ', QUOTED IDENTIFIER' ELSE '' END +
                    CASE WHEN kheb.clientoption2 & 16777216 = 16777216 THEN ', AUTO CREATE STATISTICS' ELSE '' END +
                    CASE WHEN kheb.clientoption2 & 33554432 = 33554432 THEN ', CURSOR CLOSE ON COMMIT' ELSE '' END +
                    CASE WHEN kheb.clientoption2 & 67108864 = 67108864 THEN ', ANSI NULLS' ELSE '' END +
                    CASE WHEN kheb.clientoption2 & 268435456 = 268435456 THEN ', ANSI WARNINGS' ELSE '' END +
                    CASE WHEN kheb.clientoption2 & 536870912 = 536870912 THEN ', FULL TEXT ENABLED' ELSE '' END +
                    CASE WHEN kheb.clientoption2 & 1073741824 = 1073741824 THEN ', AUTO UPDATE STATISTICS' ELSE '' END +
                    CASE WHEN kheb.clientoption2 & 1469283328 = 1469283328 THEN ', ALL SETTABLE OPTIONS' ELSE '' END,
                    3,
                    8000
                ),
            kheb.wait_resource,
            kheb.priority,
            kheb.log_used,
            kheb.client_app,
            kheb.host_name,
            kheb.login_name,
            kheb.blocked_process_report
        INTO #blocks
        FROM
        (
            SELECT
                bg.*
            FROM #blocking AS bg
            WHERE (bg.currentdbname = @database_name
                   OR @database_name IS NULL)

            UNION ALL

            SELECT
                bd.*
            FROM #blocked AS bd
            WHERE (bd.currentdbname = @database_name
                   OR @database_name IS NULL)
        ) AS kheb
        OPTION(RECOMPILE);

        IF @debug = 1
        BEGIN
            SELECT TOP (100)
                table_name = '#blocks, top 100 rows',
                x.*
            FROM #blocks AS x
            ORDER BY
                x.event_time DESC;
        END;

        SELECT
            finding = 'blocked process report',
            b.event_time,
            b.currentdbname,
            b.activity,
            b.spid,
            b.ecid,
            b.query_text,
            b.wait_time_ms,
            b.status,
            b.isolation_level,
            b.transaction_count,
            b.last_transaction_started,
            b.last_transaction_completed,
            b.client_option_1,
            b.client_option_2,
            b.wait_resource,
            b.priority,
            b.log_used,
            b.client_app,
            b.host_name,
            b.login_name,
            b.blocked_process_report
        FROM #blocks AS b
        ORDER BY
            b.event_time DESC,
            CASE
                WHEN b.activity = 'blocking'
                THEN -1
                ELSE +1
            END
        OPTION(RECOMPILE);

        /*Grab available plans from the cache*/
        IF @debug = 1
        BEGIN
            RAISERROR('Inserting to #available_plans (blocking)', 0, 1) WITH NOWAIT;
        END;

        SELECT DISTINCT
            b.*
        INTO #available_plans
        FROM
        (
            SELECT
                finding =
                    'available plans for blocking',
                b.currentdbname,
                query_text =
                    TRY_CAST(b.query_text AS nvarchar(MAX)),
                sql_handle =
                    CONVERT(varbinary(64), n.c.value('@sqlhandle', 'varchar(130)'), 1),
                stmtstart =
                    ISNULL(n.c.value('@stmtstart', 'int'), 0),
                stmtend =
                    ISNULL(n.c.value('@stmtend', 'int'), -1)
            FROM #blocks AS b
            CROSS APPLY b.blocked_process_report.nodes('/blocked-process/process/executionStack/frame[not(@sqlhandle = "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")]') AS n(c)
            WHERE (b.currentdbname = @database_name
                    OR @database_name IS NULL)

            UNION ALL

            SELECT
                finding =
                    CONVERT(varchar(30), 'available plans for blocking'),
                b.currentdbname,
                query_text =
                    TRY_CAST(b.query_text AS nvarchar(MAX)),
                sql_handle =
                    CONVERT(varbinary(64), n.c.value('@sqlhandle', 'varchar(130)'), 1),
                stmtstart =
                    ISNULL(n.c.value('@stmtstart', 'int'), 0),
                stmtend =
                    ISNULL(n.c.value('@stmtend', 'int'), -1)
            FROM #blocks AS b
            CROSS APPLY b.blocked_process_report.nodes('/blocking-process/process/executionStack/frame[not(@sqlhandle = "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")]') AS n(c)
            WHERE (b.currentdbname = @database_name
                    OR @database_name IS NULL)
        ) AS b
        OPTION(RECOMPILE);

        IF @debug = 1
        BEGIN
            RAISERROR('Inserting to #deadlocks', 0, 1) WITH NOWAIT;
        END;

        SELECT
            x.xml_deadlock_report,
            event_date = x.xml_deadlock_report.value('(event/@timestamp)[1]', 'datetime2'),
            victim_id = x.xml_deadlock_report.value('(//deadlock/victim-list/victimProcess/@id)[1]', 'nvarchar(256)'),
            deadlock_graph = x.xml_deadlock_report.query('/event/data/value/deadlock')
        INTO #deadlocks
        FROM #xml_deadlock_report AS x
        OPTION(RECOMPILE);

        IF @debug = 1
        BEGIN
            SELECT TOP (100)
                table_name = '#deadlocks, top 100 rows',
                x.*
            FROM #deadlocks AS x;
        END;

        IF @debug = 1
        BEGIN
            RAISERROR('Inserting to #deadlocks_parsed', 0, 1) WITH NOWAIT;
        END;

        SELECT
            x.event_date,
            x.id,
            x.victim_id,
            database_name =
                ISNULL
                (
                    DB_NAME(x.database_id),
                    N'UNKNOWN'
                ),
            x.current_database_name,
            x.query_text_pre,
            x.priority,
            x.log_used,
            x.wait_time,
            x.transaction_name,
            x.last_tran_started,
            x.last_batch_started,
            x.last_batch_completed,
            x.lock_mode,
            x.status,
            x.transaction_count,
            x.client_app,
            x.host_name,
            x.login_name,
            x.isolation_level,
            client_option_1 =
                SUBSTRING
                (
                    CASE WHEN x.clientoption1 & 1 = 1 THEN ', DISABLE_DEF_CNST_CHECK' ELSE '' END +
                    CASE WHEN x.clientoption1 & 2 = 2 THEN ', IMPLICIT_TRANSACTIONS' ELSE '' END +
                    CASE WHEN x.clientoption1 & 4 = 4 THEN ', CURSOR_CLOSE_ON_COMMIT' ELSE '' END +
                    CASE WHEN x.clientoption1 & 8 = 8 THEN ', ANSI_WARNINGS' ELSE '' END +
                    CASE WHEN x.clientoption1 & 16 = 16 THEN ', ANSI_PADDING' ELSE '' END +
                    CASE WHEN x.clientoption1 & 32 = 32 THEN ', ANSI_NULLS' ELSE '' END +
                    CASE WHEN x.clientoption1 & 64 = 64 THEN ', ARITHABORT' ELSE '' END +
                    CASE WHEN x.clientoption1 & 128 = 128 THEN ', ARITHIGNORE' ELSE '' END +
                    CASE WHEN x.clientoption1 & 256 = 256 THEN ', QUOTED_IDENTIFIER' ELSE '' END +
                    CASE WHEN x.clientoption1 & 512 = 512 THEN ', NOCOUNT' ELSE '' END +
                    CASE WHEN x.clientoption1 & 1024 = 1024 THEN ', ANSI_NULL_DFLT_ON' ELSE '' END +
                    CASE WHEN x.clientoption1 & 2048 = 2048 THEN ', ANSI_NULL_DFLT_OFF' ELSE '' END +
                    CASE WHEN x.clientoption1 & 4096 = 4096 THEN ', CONCAT_NULL_YIELDS_NULL' ELSE '' END +
                    CASE WHEN x.clientoption1 & 8192 = 8192 THEN ', NUMERIC_ROUNDABORT' ELSE '' END +
                    CASE WHEN x.clientoption1 & 16384 = 16384 THEN ', XACT_ABORT' ELSE '' END,
                    3,
                    500
                ),
            client_option_2 =
                SUBSTRING
                (
                    CASE WHEN x.clientoption2 & 1024 = 1024 THEN ', DB CHAINING' ELSE '' END +
                    CASE WHEN x.clientoption2 & 2048 = 2048 THEN ', NUMERIC ROUNDABORT' ELSE '' END +
                    CASE WHEN x.clientoption2 & 4096 = 4096 THEN ', ARITHABORT' ELSE '' END +
                    CASE WHEN x.clientoption2 & 8192 = 8192 THEN ', ANSI PADDING' ELSE '' END +
                    CASE WHEN x.clientoption2 & 16384 = 16384 THEN ', ANSI NULL DEFAULT' ELSE '' END +
                    CASE WHEN x.clientoption2 & 65536 = 65536 THEN ', CONCAT NULL YIELDS NULL' ELSE '' END +
                    CASE WHEN x.clientoption2 & 131072 = 131072 THEN ', RECURSIVE TRIGGERS' ELSE '' END +
                    CASE WHEN x.clientoption2 & 1048576 = 1048576 THEN ', DEFAULT TO LOCAL CURSOR' ELSE '' END +
                    CASE WHEN x.clientoption2 & 8388608 = 8388608 THEN ', QUOTED IDENTIFIER' ELSE '' END +
                    CASE WHEN x.clientoption2 & 16777216 = 16777216 THEN ', AUTO CREATE STATISTICS' ELSE '' END +
                    CASE WHEN x.clientoption2 & 33554432 = 33554432 THEN ', CURSOR CLOSE ON COMMIT' ELSE '' END +
                    CASE WHEN x.clientoption2 & 67108864 = 67108864 THEN ', ANSI NULLS' ELSE '' END +
                    CASE WHEN x.clientoption2 & 268435456 = 268435456 THEN ', ANSI WARNINGS' ELSE '' END +
                    CASE WHEN x.clientoption2 & 536870912 = 536870912 THEN ', FULL TEXT ENABLED' ELSE '' END +
                    CASE WHEN x.clientoption2 & 1073741824 = 1073741824 THEN ', AUTO UPDATE STATISTICS' ELSE '' END +
                    CASE WHEN x.clientoption2 & 1469283328 = 1469283328 THEN ', ALL SETTABLE OPTIONS' ELSE '' END,
                    3,
                    500
                ),
            x.deadlock_resources,
            x.deadlock_graph,
            x.process_xml
        INTO #deadlocks_parsed
        FROM
        (
            SELECT
                event_date =
                    DATEADD
                    (
                        MINUTE,
                        DATEDIFF
                        (
                            MINUTE,
                            GETUTCDATE(),
                            SYSDATETIME()
                        ),
                        d.event_date
                    ),
                d.victim_id,
                d.deadlock_graph,
                id = e.x.value('@id', 'nvarchar(256)'),
                database_id = e.x.value('@currentdb', 'bigint'),
                current_database_name = e.x.value('@currentdbname', 'nvarchar(256)'),
                priority = e.x.value('@priority', 'smallint'),
                log_used = e.x.value('@logused', 'bigint'),
                wait_time = e.x.value('@waittime', 'bigint'),
                transaction_name = e.x.value('@transactionname', 'nvarchar(256)'),
                last_tran_started = e.x.value('@lasttranstarted', 'datetime'),
                last_batch_started = e.x.value('@lastbatchstarted', 'datetime'),
                last_batch_completed = e.x.value('@lastbatchcompleted', 'datetime'),
                lock_mode = e.x.value('@lockMode', 'nvarchar(256)'),
                status = e.x.value('@status', 'nvarchar(256)'),
                transaction_count = e.x.value('@trancount', 'bigint'),
                client_app = e.x.value('@clientapp', 'nvarchar(1024)'),
                host_name = e.x.value('@hostname', 'nvarchar(256)'),
                login_name = e.x.value('@loginname', 'nvarchar(256)'),
                isolation_level = e.x.value('@isolationlevel', 'nvarchar(256)'),
                clientoption1 = e.x.value('@clientoption1', 'bigint'),
                clientoption2 = e.x.value('@clientoption2', 'bigint'),
                query_text_pre = e.x.value('(//process/inputbuf/text())[1]', 'nvarchar(max)'),
                process_xml = e.x.query(N'.'),
                deadlock_resources = d.xml_deadlock_report.query('//deadlock/resource-list')
            FROM #deadlocks AS d
            CROSS APPLY d.xml_deadlock_report.nodes('//deadlock/process-list/process') AS e(x)
        ) AS x
        WHERE (x.database_id = @dbid
               OR @dbid IS NULL)
        OR    (x.current_database_name = @database_name
               OR @database_name IS NULL)
        OPTION(RECOMPILE);

        IF @debug = 1
        BEGIN
            RAISERROR('Adding query_text to #deadlocks_parsed', 0, 1) WITH NOWAIT;
        END;

        ALTER TABLE #deadlocks_parsed
        ADD query_text AS
           REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
           REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
           REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
               query_text_pre COLLATE Latin1_General_BIN2,
           NCHAR(31),N'?'),NCHAR(30),N'?'),NCHAR(29),N'?'),NCHAR(28),N'?'),NCHAR(27),N'?'),NCHAR(26),N'?'),NCHAR(25),N'?'),NCHAR(24),N'?'),NCHAR(23),N'?'),NCHAR(22),N'?'),
           NCHAR(21),N'?'),NCHAR(20),N'?'),NCHAR(19),N'?'),NCHAR(18),N'?'),NCHAR(17),N'?'),NCHAR(16),N'?'),NCHAR(15),N'?'),NCHAR(14),N'?'),NCHAR(12),N'?'),
           NCHAR(11),N'?'),NCHAR(8),N'?'),NCHAR(7),N'?'),NCHAR(6),N'?'),NCHAR(5),N'?'),NCHAR(4),N'?'),NCHAR(3),N'?'),NCHAR(2),N'?'),NCHAR(1),N'?'),NCHAR(0),N'?')
        PERSISTED;

        IF @debug = 1
        BEGIN
            SELECT TOP (100)
                table_name = '#deadlocks_parsed, top 100 rows',
                x.*
            FROM #deadlocks_parsed AS x;
        END;

        IF @debug = 1
        BEGIN
            RAISERROR('Returning deadlocks', 0, 1) WITH NOWAIT;
        END;

        SELECT
            finding = 'xml deadlock report',
            dp.event_date,
            is_victim =
                CASE
                    WHEN dp.id = dp.victim_id
                    THEN 1
                    ELSE 0
                END,
            dp.database_name,
            dp.current_database_name,
            query_text =
                CASE
                    WHEN dp.query_text
                         LIKE CONVERT(nvarchar(1), 0x0a00, 0) + N'Proc |[Database Id = %' ESCAPE N'|'
                    THEN
                        (
                            SELECT
                                [processing-instruction(query)] =
                                    OBJECT_SCHEMA_NAME
                                    (
                                            SUBSTRING
                                            (
                                                dp.query_text,
                                                CHARINDEX(N'Object Id = ', dp.query_text) + 12,
                                                LEN(dp.query_text) - (CHARINDEX(N'Object Id = ', dp.query_text) + 12)
                                            )
                                            ,
                                            SUBSTRING
                                            (
                                                dp.query_text,
                                                CHARINDEX(N'Database Id = ', dp.query_text) + 14,
                                                CHARINDEX(N'Object Id', dp.query_text) - (CHARINDEX(N'Database Id = ', dp.query_text) + 14)
                                            )
                                    ) +
                                    N'.' +
                                    OBJECT_NAME
                                    (
                                         SUBSTRING
                                         (
                                             dp.query_text,
                                             CHARINDEX(N'Object Id = ', dp.query_text) + 12,
                                             LEN(dp.query_text) - (CHARINDEX(N'Object Id = ', dp.query_text) + 12)
                                         )
                                         ,
                                         SUBSTRING
                                         (
                                             dp.query_text,
                                             CHARINDEX(N'Database Id = ', dp.query_text) + 14,
                                             CHARINDEX(N'Object Id', dp.query_text) - (CHARINDEX(N'Database Id = ', dp.query_text) + 14)
                                         )
                                    )
                            FOR XML
                                PATH(N''),
                                TYPE
                        )
                    ELSE
                        (
                            SELECT
                                [processing-instruction(query)] =
                                    dp.query_text
                            FOR XML
                                PATH(N''),
                                TYPE
                        )
                END,
            dp.deadlock_resources,
            dp.isolation_level,
            dp.lock_mode,
            dp.status,
            dp.wait_time,
            dp.log_used,
            dp.transaction_name,
            dp.transaction_count,
            dp.client_option_1,
            dp.client_option_2,
            dp.last_tran_started,
            dp.last_batch_started,
            dp.last_batch_completed,
            dp.client_app,
            dp.host_name,
            dp.login_name,
            dp.priority,
            dp.deadlock_graph
        FROM #deadlocks_parsed AS dp
        ORDER BY
            dp.event_date,
            is_victim
        OPTION(RECOMPILE);

        IF @debug = 1
        BEGIN
            RAISERROR('Inserting #available_plans (deadlocks)', 0, 1) WITH NOWAIT;
        END;

        INSERT
            #available_plans WITH (TABLOCKX)
        (
            finding,
            currentdbname,
            query_text,
            sql_handle,
            stmtstart,
            stmtend
        )
        SELECT
            finding =
                'available plans for deadlocks',
            dp.database_name,
            dp.query_text,
            sql_handle =
                CONVERT(varbinary(64), e.x.value('@sqlhandle', 'varchar(130)'), 1),
            stmtstart =
                0,
            stmtend =
                0
        FROM #deadlocks_parsed AS dp
        CROSS APPLY dp.process_xml.nodes('//executionStack/frame[not(@sqlhandle = "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")]') AS e(x)
        OPTION(RECOMPILE);

        IF @debug = 1
        BEGIN
            SELECT TOP (100)
                table_name = '#available_plans, top 100 rows',
                x.*
            FROM #available_plans AS x;
        END;

        IF @debug = 1
        BEGIN
            RAISERROR('Inserting #dm_exec_query_stats_sh', 0, 1) WITH NOWAIT;
        END;

        SELECT
            deqs.sql_handle,
            deqs.plan_handle,
            deqs.statement_start_offset,
            deqs.statement_end_offset,
            deqs.creation_time,
            deqs.last_execution_time,
            deqs.execution_count,
            total_worker_time_ms =
                deqs.total_worker_time / 1000.,
            avg_worker_time_ms =
                CONVERT(decimal(38, 6), deqs.total_worker_time / 1000. / deqs.execution_count),
            total_elapsed_time_ms =
                deqs.total_elapsed_time / 1000.,
            avg_elapsed_time =
                CONVERT(decimal(38, 6), deqs.total_elapsed_time / 1000. / deqs.execution_count),
            executions_per_second =
                ISNULL
                (
                    deqs.execution_count /
                        NULLIF
                        (
                            DATEDIFF
                            (
                                SECOND,
                                deqs.creation_time,
                                NULLIF(deqs.last_execution_time, '1900-01-01 00:00:00.000')
                            ),
                            0
                        ),
                        0
                ),
            total_physical_reads_mb =
                deqs.total_physical_reads * 8. / 1024.,
            total_logical_writes_mb =
                deqs.total_logical_writes * 8. / 1024.,
            total_logical_reads_mb =
                deqs.total_logical_reads * 8. / 1024.,
            min_grant_mb =
                deqs.min_grant_kb * 8. / 1024.,
            max_grant_mb =
                deqs.max_grant_kb * 8. / 1024.,
            min_used_grant_mb =
                deqs.min_used_grant_kb * 8. / 1024.,
            max_used_grant_mb =
                deqs.max_used_grant_kb * 8. / 1024.,
            deqs.min_reserved_threads,
            deqs.max_reserved_threads,
            deqs.min_used_threads,
            deqs.max_used_threads,
            deqs.total_rows
        INTO #dm_exec_query_stats_sh
        FROM sys.dm_exec_query_stats AS deqs
        WHERE EXISTS
        (
            SELECT
                1/0
            FROM #available_plans AS ap
            WHERE ap.sql_handle = deqs.sql_handle
        )
        AND deqs.query_hash IS NOT NULL;

        IF @debug = 1
        BEGIN
            RAISERROR('Indexing #dm_exec_query_stats_sh', 0, 1) WITH NOWAIT;
        END;

        CREATE CLUSTERED INDEX
            deqs_sh
        ON #dm_exec_query_stats_sh
        (
            sql_handle,
            plan_handle
        );

        IF @debug = 1
        BEGIN
            RAISERROR('Inserting #all_available_plans (deadlocks)', 0, 1) WITH NOWAIT;
        END;

        SELECT
            ap.finding,
            ap.currentdbname,
            query_text =
                TRY_CAST(ap.query_text AS xml),
            ap.query_plan,
            ap.creation_time,
            ap.last_execution_time,
            ap.execution_count,
            ap.executions_per_second,
            ap.total_worker_time_ms,
            ap.avg_worker_time_ms,
            ap.total_elapsed_time_ms,
            ap.avg_elapsed_time,
            ap.total_logical_reads_mb,
            ap.total_physical_reads_mb,
            ap.total_logical_writes_mb,
            ap.min_grant_mb,
            ap.max_grant_mb,
            ap.min_used_grant_mb,
            ap.max_used_grant_mb,
            ap.min_reserved_threads,
            ap.max_reserved_threads,
            ap.min_used_threads,
            ap.max_used_threads,
            ap.total_rows,
            ap.sql_handle,
            ap.statement_start_offset,
            ap.statement_end_offset
        INTO #all_avalable_plans
        FROM
        (
            SELECT
                ap.*,
                c.statement_start_offset,
                c.statement_end_offset,
                c.creation_time,
                c.last_execution_time,
                c.execution_count,
                c.total_worker_time_ms,
                c.avg_worker_time_ms,
                c.total_elapsed_time_ms,
                c.avg_elapsed_time,
                c.executions_per_second,
                c.total_physical_reads_mb,
                c.total_logical_writes_mb,
                c.total_logical_reads_mb,
                c.min_grant_mb,
                c.max_grant_mb,
                c.min_used_grant_mb,
                c.max_used_grant_mb,
                c.min_reserved_threads,
                c.max_reserved_threads,
                c.min_used_threads,
                c.max_used_threads,
                c.total_rows,
                c.query_plan
            FROM #available_plans AS ap
            OUTER APPLY
            (
                SELECT
                    deqs.*,
                    query_plan =
                        TRY_CAST(deps.query_plan AS xml)
                FROM #dm_exec_query_stats_sh AS deqs
                OUTER APPLY sys.dm_exec_text_query_plan
                (
                    deqs.plan_handle,
                    deqs.statement_start_offset,
                    deqs.statement_end_offset
                ) AS deps
                WHERE deqs.sql_handle = ap.sql_handle
            ) AS c
        ) AS ap
        WHERE ap.query_plan IS NOT NULL
        ORDER BY
            ap.avg_worker_time_ms DESC
        OPTION(RECOMPILE);

        SELECT
            aap.*
        FROM #all_avalable_plans AS aap
        WHERE aap.finding = 'available plans for blocking'
        ORDER BY
            aap.avg_worker_time_ms DESC
        OPTION(RECOMPILE);

        SELECT
            aap.*
        FROM #all_avalable_plans AS aap
        WHERE aap.finding = 'available plans for deadlocks'
        ORDER BY
            aap.avg_worker_time_ms DESC
        OPTION(RECOMPILE);
    END; /*End locks*/
END; /*Final End*/
GO
