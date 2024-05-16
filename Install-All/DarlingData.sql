-- Compile Date: 05/16/2024 20:15:31 UTC
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
██╗  ██╗██╗   ██╗███╗   ███╗ █████╗ ███╗   ██╗
██║  ██║██║   ██║████╗ ████║██╔══██╗████╗  ██║
███████║██║   ██║██╔████╔██║███████║██╔██╗ ██║
██╔══██║██║   ██║██║╚██╔╝██║██╔══██║██║╚██╗██║
██║  ██║╚██████╔╝██║ ╚═╝ ██║██║  ██║██║ ╚████║
╚═╝  ╚═╝ ╚═════╝ ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝

███████╗██╗   ██╗███████╗███╗   ██╗████████╗███████╗
██╔════╝██║   ██║██╔════╝████╗  ██║╚══██╔══╝██╔════╝
█████╗  ██║   ██║█████╗  ██╔██╗ ██║   ██║   ███████╗
██╔══╝  ╚██╗ ██╔╝██╔══╝  ██║╚██╗██║   ██║   ╚════██║
███████╗ ╚████╔╝ ███████╗██║ ╚████║   ██║   ███████║
╚══════╝  ╚═══╝  ╚══════╝╚═╝  ╚═══╝   ╚═╝   ╚══════╝

Copyright 2024 Darling Data, LLC
https://www.erikdarling.com/

For usage and licensing details, run:
EXEC sp_HumanEvents
    @help = 1;

For working through errors:
EXEC sp_HumanEvents
    @debug = 1;

For support, head over to GitHub:
https://github.com/erikdarlingdata/DarlingData

*/

IF OBJECT_ID('dbo.sp_HumanEvents') IS NULL
   BEGIN
       EXEC ('CREATE PROCEDURE dbo.sp_HumanEvents AS RETURN 138;');
   END;
GO

ALTER PROCEDURE
    dbo.sp_HumanEvents
(
    @event_type sysname = N'query',
    @query_duration_ms integer = 500,
    @query_sort_order nvarchar(10) = N'cpu',
    @skip_plans bit = 0,
    @blocking_duration_ms integer = 500,
    @wait_type nvarchar(4000) = N'ALL',
    @wait_duration_ms integer = 10,
    @client_app_name sysname = N'',
    @client_hostname sysname = N'',
    @database_name sysname = N'',
    @session_id nvarchar(7) = N'',
    @sample_divisor integer = 5,
    @username sysname = N'',
    @object_name sysname = N'',
    @object_schema sysname = N'dbo',
    @requested_memory_mb integer = 0,
    @seconds_sample integer = 10,
    @gimme_danger bit = 0,
    @keep_alive bit = 0,
    @custom_name nvarchar(256) = N'',
    @output_database_name sysname = N'',
    @output_schema_name sysname = N'dbo',
    @delete_retention_days integer = 3,
    @cleanup bit = 0,
    @max_memory_kb bigint = 102400,
    @version varchar(30) = NULL OUTPUT,
    @version_date datetime = NULL OUTPUT,
    @debug bit = 0,
    @help bit = 0
)
AS
BEGIN
SET STATISTICS XML OFF;
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

SELECT
    @version = '5.5',
    @version_date = '20240401';

IF @help = 1
BEGIN
    /*Warnings, I guess*/
    SELECT [WARNING WARNING WARNING] =
        N'warning! achtung! peligro! chardonnay!' UNION ALL
    SELECT N'misuse of this procedure can harm performance' UNION ALL
    SELECT N'be very careful about introducing observer overhead, especially when gathering query plans' UNION ALL
    SELECT N'be even more careful when setting up permanent sessions!' UNION ALL
    SELECT N'for additional support: https://github.com/erikdarlingdata/DarlingData/tree/main/sp_HumanEvents' UNION ALL
    SELECT N'from your loving sql server consultant, erik darling: https://erikdarling.com';


    /*Introduction*/
    SELECT
        introduction = N'allow me to reintroduce myself' UNION ALL
    SELECT N'this can be used to start a time-limited extended event session to capture various things:' UNION ALL
    SELECT N'  * blocking' UNION ALL
    SELECT N'  * query performance and plans' UNION ALL
    SELECT N'  * compilations' UNION ALL
    SELECT N'  * recompilations' UNION ALL
    SELECT N'  * wait stats';


    /*Limitations*/
    SELECT
        limitations = N'frigid shortcomings' UNION ALL
    SELECT N'you need to be on at least SQL Server 2012 SP4 or higher to run this' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'if your version isn''t patched to where query_hash_signed is an available xe action, this won''t run' UNION ALL
    SELECT N'sp_HumanEvents is designed to make getting information from common extended events easier. with that in mind,' UNION ALL
    SELECT N'some of the customization is limited, and right now you can''t just choose your own adventure.' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'because i don''t want to create files, i''m using the ring buffer, which also has some pesky limitations.' UNION ALL
    SELECT N'https://techcommunity.microsoft.com/t5/sql-server-support/you-may-not-see-the-data-you-expect-in-extended-event-ring/ba-p/315838' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'in order to use the "blocking" session, you must enable the blocked process report' UNION ALL
    SELECT N'https://docs.microsoft.com/en-us/sql/database-engine/configure-windows/blocked-process-threshold-server-configuration-option';


    /*Usage*/
    SELECT
        parameter =
            ap.name,
        t.name,
        description =
            CASE ap.name
                WHEN N'@event_type' THEN N'used to pick which session you want to run'
                WHEN N'@query_duration_ms' THEN N'(>=) used to set a minimum query duration to collect data for'
                WHEN N'@query_sort_order' THEN 'when you use the "query" event, lets you choose which metrics to sort results by'
                WHEN N'@skip_plans' THEN 'when you use the "query" event, lets you skip collecting actual execution plans'
                WHEN N'@blocking_duration_ms' THEN N'(>=) used to set a minimum blocking duration to collect data for'
                WHEN N'@wait_type' THEN N'(inclusive) filter to only specific wait types'
                WHEN N'@wait_duration_ms' THEN N'(>=) used to set a minimum time per wait to collect data for'
                WHEN N'@client_app_name' THEN N'(inclusive) filter to only specific app names'
                WHEN N'@client_hostname' THEN N'(inclusive) filter to only specific host names'
                WHEN N'@database_name' THEN N'(inclusive) filter to only specific databases'
                WHEN N'@session_id' THEN N'(inclusive) filter to only a specific session id, or a sample of session ids'
                WHEN N'@sample_divisor' THEN N'the divisor for session ids when sampling a workload, e.g. SPID % 5'
                WHEN N'@username' THEN N'(inclusive) filter to only a specific user'
                WHEN N'@object_name' THEN N'(inclusive) to only filter to a specific object name'
                WHEN N'@object_schema' THEN N'(inclusive) the schema of the object you want to filter to; only needed with blocking events'
                WHEN N'@requested_memory_mb' THEN N'(>=) the memory grant a query must ask for to have data collected'
                WHEN N'@seconds_sample' THEN N'the duration in seconds to run the event session for'
                WHEN N'@gimme_danger' THEN N'used to override default minimums for query, wait, and blocking durations. only use if you''re okay with potentially adding a lot of observer overhead on your system, or for testing purposes.'
                WHEN N'@debug' THEN N'use to print out dynamic SQL'
                WHEN N'@keep_alive' THEN N'creates a permanent session, either to watch live or log to a table from'
                WHEN N'@custom_name' THEN N'if you want to custom name a permanent session'
                WHEN N'@output_database_name' THEN N'the database you want to log data to'
                WHEN N'@output_schema_name' THEN N'the schema you want to log data to'
                WHEN N'@delete_retention_days' THEN N'how many days of logged data you want to keep'
                WHEN N'@cleanup' THEN N'deletes all sessions, tables, and views. requires output database and schema.'
                WHEN N'@max_memory_kb' THEN N'set a max ring buffer size to log data to'
                WHEN N'@help' THEN N'well you''re here so you figured this one out'
                WHEN N'@version' THEN N'to make sure you have the most recent bits'
                WHEN N'@version_date' THEN N'to make sure you have the most recent bits'
                ELSE N'????'
            END,
        valid_inputs =
           CASE ap.name
               WHEN N'@event_type' THEN N'"blocking", "query", "waits", "recompiles", "compiles" and certain variations on those words'
               WHEN N'@query_duration_ms' THEN N'an integer'
               WHEN N'@query_sort_order' THEN '"cpu", "reads", "writes", "duration", "memory", "spills", and you can add "avg" to sort by averages, e.g. "avg cpu"'
               WHEN N'@skip_plans' THEN '1 or 0'
               WHEN N'@blocking_duration_ms' THEN N'an integer'
               WHEN N'@wait_type' THEN N'a single wait type, or a CSV list of wait types'
               WHEN N'@wait_duration_ms' THEN N'an integer'
               WHEN N'@client_app_name' THEN N'a stringy thing'
               WHEN N'@client_hostname' THEN N'a stringy thing'
               WHEN N'@database_name' THEN N'a stringy thing'
               WHEN N'@session_id' THEN N'an integer, or "sample" to sample a workload'
               WHEN N'@sample_divisor' THEN N'an integer'
               WHEN N'@username' THEN N'a stringy thing'
               WHEN N'@object_name' THEN N'a stringy thing'
               WHEN N'@object_schema' THEN N'a stringy thing'
               WHEN N'@requested_memory_mb' THEN N'an integer'
               WHEN N'@seconds_sample' THEN N'an integer'
               WHEN N'@gimme_danger' THEN N'1 or 0'
               WHEN N'@debug' THEN N'1 or 0'
               WHEN N'@keep_alive' THEN N'1 or 0'
               WHEN N'@custom_name' THEN N'a stringy thing'
               WHEN N'@output_database_name' THEN N'a valid database name'
               WHEN N'@output_schema_name' THEN N'a valid schema'
               WHEN N'@delete_retention_days' THEN N'a POSITIVE integer'
               WHEN N'@cleanup' THEN N'1 or 0'
               WHEN N'@max_memory_kb' THEN N'an integer'
               WHEN N'@help' THEN N'1 or 0'
               WHEN N'@version' THEN N'none, output'
               WHEN N'@version_date' THEN N'none, output'
               ELSE N'????'
           END,
        defaults =
           CASE ap.name
               WHEN N'@event_type' THEN N'"query"'
               WHEN N'@query_duration_ms' THEN N'500 (ms)'
               WHEN N'@query_sort_order' THEN N'"cpu"'
               WHEN N'@skip_plans' THEN '0'
               WHEN N'@blocking_duration_ms' THEN N'500 (ms)'
               WHEN N'@wait_type' THEN N'"all", which uses a list of "interesting" waits'
               WHEN N'@wait_duration_ms' THEN N'10 (ms)'
               WHEN N'@client_app_name' THEN N'intentionally left blank'
               WHEN N'@client_hostname' THEN N'intentionally left blank'
               WHEN N'@database_name' THEN N'intentionally left blank'
               WHEN N'@session_id' THEN N'intentionally left blank'
               WHEN N'@sample_divisor' THEN N'5'
               WHEN N'@username' THEN N'intentionally left blank'
               WHEN N'@object_name' THEN N'intentionally left blank'
               WHEN N'@object_schema' THEN N'dbo'
               WHEN N'@requested_memory_mb' THEN N'0'
               WHEN N'@seconds_sample' THEN N'10'
               WHEN N'@gimme_danger' THEN N'0'
               WHEN N'@keep_alive' THEN N'0'
               WHEN N'@custom_name' THEN N'intentionally left blank'
               WHEN N'@output_database_name' THEN N'intentionally left blank'
               WHEN N'@output_schema_name' THEN N'dbo'
               WHEN N'@delete_retention_days' THEN N'3 (days)'
               WHEN N'@debug' THEN N'0'
               WHEN N'@cleanup' THEN N'0'
               WHEN N'@max_memory_kb' THEN N'102400'
               WHEN N'@help' THEN N'0'
               WHEN N'@version' THEN N'none, output'
               WHEN N'@version_date' THEN N'none, output'
               ELSE N'????'
           END
    FROM sys.all_parameters AS ap
    JOIN sys.all_objects AS o
      ON ap.object_id = o.object_id
    JOIN sys.types AS t
      ON  ap.system_type_id = t.system_type_id
      AND ap.user_type_id = t.user_type_id
    WHERE o.name = N'sp_HumanEvents';


    /*Example calls*/
    SELECT
        example_calls = N'EXAMPLE CALLS' UNION ALL
    SELECT N'note that not all filters are compatible with all sessions' UNION ALL
    SELECT N'this is handled dynamically, but please don''t think you''re crazy if one "doesn''t work"' UNION ALL
    SELECT N'to capture all types of "completed" queries that have run for at least one second for 20 seconds from a specific database' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'EXEC dbo.sp_HumanEvents @event_type = ''query'', @query_duration_ms = 1000, @seconds_sample = 20, @database_name = ''YourMom'';' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'or that have asked for 1gb of memory' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'EXEC dbo.sp_HumanEvents @event_type = ''query'', @query_duration_ms = 1000, @seconds_sample = 20, @requested_memory_mb = 1024;' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'maybe you want to find unparameterized queries from a poorly written app' UNION ALL
    SELECT N'newer versions will use sql_statement_post_compile, older versions will use uncached_sql_batch_statistics and sql_statement_recompile' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'EXEC dbo.sp_HumanEvents @event_type = ''compilations'', @client_app_name = N''GL00SNIFЯ'', @session_id = ''sample'', @sample_divisor = 3;' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'perhaps you think queries recompiling are the cause of your problems!' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'EXEC dbo.sp_HumanEvents @event_type = ''recompilations'', @seconds_sample = 30;' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'look, blocking is annoying. just turn on RCSI, you goblin.' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'EXEC dbo.sp_HumanEvents @event_type = ''blocking'', @seconds_sample = 60, @blocking_duration_ms = 5000;' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'i mean wait stats are probably a meme but whatever' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'EXEC dbo.sp_HumanEvents @event_type = ''waits'', @wait_duration_ms = 10, @seconds_sample = 100, @wait_type = N''all'';' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'note that THREADPOOL is SOS_WORKER in xe-land. why? i dunno.' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'EXEC dbo.sp_HumanEvents @event_type = ''waits'', @wait_duration_ms = 10, @seconds_sample = 100, @wait_type = N''SOS_WORKER,RESOURCE_SEMAPHORE,YOUR_MOM'';' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'to set up a permanent session for compiles, but you can specify any of the session types here' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'EXEC sp_HumanEvents @event_type = N''compiles'', @debug = 1, @keep_alive = 1;' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'to log to a database named whatever, and a schema called dbo' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'EXEC sp_HumanEvents @debug = 1, @output_database_name = N''whatever'', @output_schema_name = N''dbo'';' UNION ALL
    SELECT REPLICATE(N'-', 100);


    /*Views*/
    SELECT
        views_and_stuff = N'views that get created when you log to tables' UNION ALL
    SELECT N'these will get created in the same database that your output tables get created in for simplicity' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'HumanEvents_Queries: View to look at data pulled from logged queries' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'HumanEvents_WaitsByQueryAndDatabase: waits generated grouped by query and database. this is best effort, as the query grouping relies on them being present in the plan cache' UNION ALL
    SELECT N'HumanEvents_WaitsByDatabase: waits generated grouped by database' UNION ALL
    SELECT N'HumanEvents_WaitsTotal: total waits' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'HumanEvents_Blocking: view to assemble blocking chains' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'HumanEvents_CompilesByDatabaseAndObject: compiles by database and object' UNION ALL
    SELECT N'HumanEvents_CompilesByQuery: compiles by query' UNION ALL
    SELECT N'HumanEvents_CompilesByDuration: compiles by duration length' UNION ALL
    SELECT N'HumanEvents_Compiles_Legacy: compiles on older versions that don''t support new events' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'HumanEvents_Parameterization: data collected from the parameterization event' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'HumanEvents_RecompilesByDatabaseAndObject: recompiles by database and object' UNION ALL
    SELECT N'HumanEvents_RecompilesByQuery: recompiles by query' UNION ALL
    SELECT N'HumanEvents_RecompilesByDuration: recompiles by long duration' UNION ALL
    SELECT N'HumanEvents_Recompiles_Legacy: recompiles on older versions that don''t support new events' UNION ALL
    SELECT REPLICATE(N'-', 100);


    /*License to F5*/
    SELECT
        mit_license_yo = N'i am MIT licensed, so like, do whatever' UNION ALL
    SELECT N'see printed messages for full license';
    RAISERROR(N'
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
END;

BEGIN TRY
CREATE TABLE
    #x
(
    x xml
);

CREATE TABLE
    #drop_commands
(
    id integer IDENTITY PRIMARY KEY,
    drop_command nvarchar(1000)
);

CREATE TABLE
    #user_waits
(
    wait_type nvarchar(60)
);

CREATE TABLE
    #papers_please
(
    ahem sysname
);

CREATE TABLE
    #human_events_xml_internal
(
    human_events_xml xml
);

CREATE TABLE
    #wait
(
    wait_type sysname
);

CREATE TABLE
    #human_events_worker
(
    id integer NOT NULL PRIMARY KEY IDENTITY,
    event_type sysname NOT NULL,
    event_type_short sysname NOT NULL,
    is_table_created bit NOT NULL DEFAULT 0,
    is_view_created bit NOT NULL DEFAULT 0,
    last_checked datetime NOT NULL DEFAULT '19000101',
    last_updated datetime NOT NULL DEFAULT '19000101',
    output_database sysname NOT NULL,
    output_schema sysname NOT NULL,
    output_table nvarchar(400) NOT NULL
);

CREATE UNIQUE NONCLUSTERED INDEX
    no_dupes
ON #human_events_worker
    (output_table)
WITH
    (IGNORE_DUP_KEY = ON);

CREATE TABLE
    #view_check
(
    id integer PRIMARY KEY IDENTITY,
    view_name sysname NOT NULL,
    view_definition varbinary(MAX) NOT NULL,
    output_database sysname NOT NULL DEFAULT N'',
    output_schema sysname NOT NULL DEFAULT N'',
    output_table sysname NOT NULL DEFAULT N'',
    view_converted AS
        CONVERT
        (
            nvarchar(MAX),
            view_definition
        ),
    view_converted_length AS
        DATALENGTH
        (
            CONVERT
            (
                nvarchar(MAX),
                view_definition
            )
        )
);


/*
I mean really stop it with the unsupported versions
*/
DECLARE
    @v decimal(5,0) =
        PARSENAME
        (
            CONVERT
            (
                nvarchar(128),
                SERVERPROPERTY('ProductVersion')
            ),
            4
        ),
    @mv integer =
        PARSENAME
        (
            CONVERT
            (
                nvarchar(128),
                SERVERPROPERTY('ProductVersion')
            ),
            2
        ),
    @azure bit =
        CASE
            WHEN CONVERT
                 (
                     int,
                     SERVERPROPERTY('EngineEdition')
                 ) = 5
            THEN 1
            ELSE 0
        END,
    @drop_old_sql nvarchar(1000) = N'',
    @waitfor nvarchar(20) = N'',
    @session_name nvarchar(512) = N'',
    @session_with nvarchar(MAX) = N'',
    @session_sql nvarchar(MAX) = N'',
    @start_sql nvarchar(MAX) = N'',
    @stop_sql  nvarchar(MAX) = N'',
    @drop_sql  nvarchar(MAX) = N'',
    @session_filter nvarchar(MAX) = N'',
    @session_filter_limited nvarchar(MAX) = N'',
    @session_filter_query_plans nvarchar(MAX) = N'',
    @session_filter_waits nvarchar(MAX) = N'',
    @session_filter_recompile nvarchar(MAX)= N'',
    @session_filter_statement_completed nvarchar(MAX) = N'',
    @session_filter_blocking nvarchar(MAX) = N'',
    @session_filter_parameterization nvarchar(MAX) = N'',
    @query_duration_filter nvarchar(MAX) = N'',
    @blocking_duration_ms_filter nvarchar(MAX) = N'',
    @wait_type_filter nvarchar(MAX) = N'',
    @wait_duration_filter nvarchar(MAX) = N'',
    @client_app_name_filter nvarchar(MAX) = N'',
    @client_hostname_filter nvarchar(MAX) = N'',
    @database_name_filter nvarchar(MAX) = N'',
    @session_id_filter nvarchar(MAX) = N'',
    @username_filter nvarchar(MAX) = N'',
    @object_name_filter nvarchar(MAX) = N'',
    @requested_memory_mb_filter nvarchar(MAX) = N'',
    @compile_events bit = 0,
    @parameterization_events bit = 0,
    @fully_formed_babby nvarchar(1000) = N'',
    @s_out int,
    @s_sql nvarchar(MAX) = N'',
    @s_params nvarchar(MAX) = N'',
    @object_id sysname = N'',
    @requested_memory_kb nvarchar(11) = N'',
    @the_sleeper_must_awaken nvarchar(MAX) = N'',
    @min_id int,
    @max_id int,
    @event_type_check sysname,
    @object_name_check nvarchar(1000) = N'',
    @table_sql nvarchar(MAX) = N'',
    @view_tracker bit,
    @spe nvarchar(MAX) = N'.sys.sp_executesql ',
    @view_sql nvarchar(MAX) = N'',
    @view_database sysname = N'',
    @date_filter datetime,
    @Time time,
    @delete_tracker int,
    @the_deleter_must_awaken nvarchar(MAX) = N'',
    @executer nvarchar(MAX),
    @cleanup_sessions nvarchar(MAX) = N'',
    @cleanup_tables nvarchar(MAX) = N'',
    @drop_holder nvarchar(MAX) = N'',
    @cleanup_views nvarchar(MAX) = N'',
    @nc10 nvarchar(2) = NCHAR(10),
    @inputbuf_bom nvarchar(1) = CONVERT(nvarchar(1), 0x0a00, 0);

/*check to make sure we're on a usable version*/
IF
(
    @v < 11
      OR (@v = 11
           AND @mv < 7001)
)
    BEGIN
        RAISERROR(N'This darn thing doesn''t seem to work on versions older than 2012 SP4.', 11, 1) WITH NOWAIT;
        RETURN;
    END;

/*one more check here for old versions. loiterers should arrested.*/
IF NOT EXISTS
(
    SELECT
        1/0
    FROM sys.dm_xe_packages AS xp
    JOIN sys.dm_xe_objects AS xo
      ON xp.guid = xo.package_guid
    WHERE (xo.capabilities IS NULL
             OR xo.capabilities & 1 = 0)
    AND   (xp.capabilities IS NULL
             OR xp.capabilities & 1 = 0)
    AND xo.object_type = N'action'
    AND xo.name = N'query_hash_signed'
)
    BEGIN
        RAISERROR(N'This server hasn''t been patched up to a supported version that has the query_hash_signed action.', 11, 1) WITH NOWAIT;
        RETURN;
    END;

/*clean up any old/dormant sessions*/
IF @azure = 0
BEGIN
    INSERT
        #drop_commands WITH(TABLOCK)
    (
        drop_command
    )
    SELECT
        N'DROP EVENT SESSION ' +
        ses.name +
        N' ON SERVER;'
    FROM sys.server_event_sessions AS ses
    LEFT JOIN sys.dm_xe_sessions AS dxe
      ON dxe.name = ses.name
    WHERE ses.name LIKE N'HumanEvents%'
    AND   (dxe.create_time < DATEADD(MINUTE, -1, SYSDATETIME())
    OR     dxe.create_time IS NULL);
END;

IF @azure = 1
BEGIN
    INSERT
        #drop_commands WITH(TABLOCK)
    (
        drop_command
    )
    SELECT
        N'DROP EVENT SESSION ' +
        ses.name +
        N' ON DATABASE;'
    FROM sys.database_event_sessions AS ses
    LEFT JOIN sys.dm_xe_database_sessions AS dxe
      ON dxe.name = ses.name
    WHERE ses.name LIKE N'HumanEvents%'
    AND   (dxe.create_time < DATEADD(MINUTE, -1, SYSDATETIME())
    OR     dxe.create_time IS NULL);
END;

IF EXISTS
(
    SELECT
        1/0
    FROM #drop_commands AS dc
)
BEGIN
    RAISERROR(N'Found old sessions, dropping those.', 0, 1) WITH NOWAIT;

    DECLARE
        drop_cursor CURSOR
        LOCAL STATIC FOR

    SELECT
        drop_command
    FROM #drop_commands;

    OPEN drop_cursor;

    FETCH NEXT
    FROM drop_cursor
    INTO @drop_old_sql;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        PRINT @drop_old_sql;
        EXEC(@drop_old_sql);

        FETCH NEXT
        FROM drop_cursor
        INTO @drop_old_sql;
    END;

    CLOSE drop_cursor;
    DEALLOCATE drop_cursor;
END;

RAISERROR(N'Setting up some variables', 0, 1) WITH NOWAIT;

/* Give sessions super unique names in case more than one person uses it at a time */
IF @keep_alive = 0
BEGIN
    SET @session_name +=
            REPLACE
            (
                N'HumanEvents_' +
                @event_type +
                N'_' +
                CONVERT
                (
                    nvarchar(36),
                    NEWID()
                ),
                N'-',
                N''
            );
END;

IF @keep_alive = 1
BEGIN
    SET @session_name +=
            N'keeper_HumanEvents_'  +
            @event_type +
            CASE
                WHEN @custom_name <> N''
                THEN N'_' + @custom_name
                ELSE N''
            END;
END;


/* set a lower max memory setting for azure */
IF @azure = 1
BEGIN
    SELECT TOP (1)
        @max_memory_kb =
            CONVERT
            (
                bigint,
                (max_memory * .10) * 1024
            )
    FROM sys.dm_user_db_resource_governance
    WHERE UPPER(database_name) = UPPER(QUOTENAME(@database_name))
    OR    @database_name = ''
    ORDER BY
        max_memory DESC;

    RAISERROR(N'Setting lower max memory for ringbuffer due to Azure, setting to %m kb',  0, 1, @max_memory_kb) WITH NOWAIT;
END;

/* session create options */
SET @session_with = N'
ADD TARGET package0.ring_buffer
        ( SET max_memory = ' + RTRIM(@max_memory_kb) + N' )
WITH
        (
            MAX_MEMORY = ' + RTRIM(@max_memory_kb) + N'KB,
            EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS,
            MAX_DISPATCH_LATENCY = 5 SECONDS,
            MAX_EVENT_SIZE = 0KB,
            MEMORY_PARTITION_MODE = PER_CPU,
            TRACK_CAUSALITY = OFF,
            STARTUP_STATE = OFF
        );' + @nc10;

/* azure can't create on server, just database */
SET @session_sql =
    N'
CREATE EVENT SESSION ' +
@session_name +
    CASE
        WHEN @azure = 0
        THEN N'
    ON SERVER '
        ELSE N'
    ON DATABASE '
    END;

/* STOP. DROP. SHUT'EM DOWN OPEN UP SHOP. */
SET @start_sql =
    N'ALTER EVENT SESSION ' +
    @session_name +
    N' ON ' +
    CASE
        WHEN @azure = 1
        THEN 'DATABASE'
        ELSE 'SERVER'
    END +
    ' STATE = START;' +
    @nc10;

SET @stop_sql  =
    N'ALTER EVENT SESSION ' +
    @session_name +
    N' ON ' +
    CASE
        WHEN @azure = 1
        THEN N'DATABASE'
        ELSE N'SERVER'
    END +
    N' STATE = STOP;' +
    @nc10;

SET @drop_sql  =
    N'DROP EVENT SESSION '  +
    @session_name +
    N' ON ' +
    CASE
        WHEN @azure = 1
        THEN N'DATABASE'
        ELSE N'SERVER'
    END +
    N';' +
    @nc10;


/*Some sessions can use all general filters*/
SET @session_filter = @nc10 + N'            sqlserver.is_system = 0 ' + @nc10;
/*Others can't use all of them, like app and host name*/
SET @session_filter_limited = @nc10 + N'            sqlserver.is_system = 0 ' + @nc10;
/*query plans can filter on requested memory, too, along with the limited filters*/
SET @session_filter_query_plans = @nc10 + N'            sqlserver.is_system = 0 ' + @nc10;
/*only wait stats can filter on wait types, but can filter on everything else*/
SET @session_filter_waits = @nc10 + N'            sqlserver.is_system = 0 ' + @nc10;
/*only wait stats can filter on wait types, but can filter on everything else*/
SET @session_filter_recompile = @nc10 + N'            sqlserver.is_system = 0 ' + @nc10;
/*sql_statement_completed can do everything except object name*/
SET @session_filter_statement_completed = @nc10 + N'            sqlserver.is_system = 0 ' + @nc10;
/*for blocking because blah blah*/
SET @session_filter_blocking = @nc10 + N'         sqlserver.is_system = 1 ' + @nc10;
/*for parameterization because blah blah*/
SET @session_filter_parameterization = @nc10 + N'            sqlserver.is_system = 0 ' + @nc10;


RAISERROR(N'Checking for some event existence', 0, 1) WITH NOWAIT;
/* Determines if we use the new event or the old event(s) to track compiles */
IF EXISTS
(
    SELECT
        1/0
    FROM sys.dm_xe_objects AS dxo
    WHERE dxo.name = N'sql_statement_post_compile'
)
BEGIN
    SET @compile_events = 1;
END;


/* Or if we use this event at all! */
IF EXISTS
(
    SELECT
        1/0
    FROM sys.dm_xe_objects AS dxo
    WHERE dxo.name = N'query_parameterization_data'
)
BEGIN
    SET @parameterization_events = 1;
END;


/* You know what I don't wanna deal with? NULLs. */
RAISERROR(N'Nixing NULLs', 0, 1) WITH NOWAIT;
SET @event_type            = ISNULL(@event_type, N'');
SET @client_app_name       = ISNULL(@client_app_name, N'');
SET @client_hostname       = ISNULL(@client_hostname, N'');
SET @database_name         = ISNULL(@database_name, N'');
SET @session_id            = ISNULL(@session_id, N'');
SET @username              = ISNULL(@username, N'');
SET @object_name           = ISNULL(@object_name, N'');
SET @object_schema         = ISNULL(@object_schema, N'');
SET @custom_name           = ISNULL(@custom_name, N'');
SET @output_database_name  = ISNULL(@output_database_name, N'');
SET @output_schema_name    = ISNULL(@output_schema_name, N'');

/*I'm also very forgiving of some white space*/
SET @database_name = RTRIM(LTRIM(@database_name));

/*Assemble the full object name for easier wrangling*/
SET @fully_formed_babby =
        QUOTENAME(@database_name) +
        N'.' +
        QUOTENAME(@object_schema) +
        N'.' +
        QUOTENAME(@object_name);

/*Some sanity checking*/
RAISERROR(N'Sanity checking event types', 0, 1) WITH NOWAIT;
/* You can only do this right now. */
IF LOWER(@event_type) NOT IN
        (
            N'waits',
            N'blocking',
            N'locking',
            N'queries',
            N'compiles',
            N'recompiles',
            N'wait',
            N'block',
            N'blocks',
            N'lock',
            N'locks',
            N'query',
            N'compile',
            N'recompile',
            N'compilation',
            N'recompilation',
            N'compilations',
            N'recompilations'
        )
BEGIN
    RAISERROR(N'
You have chosen a value for @event_type... poorly. use @help = 1 to see valid arguments.
What on earth is %s?', 11, 1, @event_type) WITH NOWAIT;
    RETURN;
END;


RAISERROR(N'Checking query sort order', 0, 1) WITH NOWAIT;
IF @query_sort_order NOT IN
(
    N'cpu',
    N'reads',
    N'writes',
    N'duration',
    N'memory',
    N'spills',
    N'avg cpu',
    N'avg reads',
    N'avg writes',
    N'avg duration',
    N'avg memory',
    N'avg spills'
)
BEGIN
   RAISERROR(N'That sort order (%s) you chose is so out of this world that i''m ignoring it', 0, 1, @query_sort_order) WITH NOWAIT;
   SET @query_sort_order = N'avg cpu';
END;


RAISERROR(N'Parsing any supplied waits', 0, 1) WITH NOWAIT;
SET @wait_type = UPPER(@wait_type);
/* This will hold the CSV list of wait types someone passes in */

INSERT
    #user_waits WITH(TABLOCK)
SELECT
    wait_type =
        LTRIM
        (
            RTRIM
            (
                waits.wait_type
            )
        )
FROM
(
    SELECT
        wait_type =
            x.x.value
                (
                    '(./text())[1]',
                    'nvarchar(60)'
                )
    FROM
    (
      SELECT
          wait_type =
              CONVERT
              (
                  xml,
                  N'<x>' +
                  REPLACE
                  (
                      REPLACE
                      (
                          @wait_type,
                          N',',
                          N'</x><x>'
                      ),
                      N' ',
                      N''
                  ) +
                  N'</x>'
              ).query(N'.')
    ) AS w
    CROSS APPLY wait_type.nodes(N'x') AS x(x)
) AS waits
WHERE @wait_type <> N'ALL';


/*
If someone is passing in specific waits, let's make sure that
they're valid waits by checking them against what's available.
*/
IF @wait_type <> N'ALL'
BEGIN
RAISERROR(N'Checking wait validity', 0, 1) WITH NOWAIT;

    /* There's no THREADPOOL in XE map values, it gets registered as SOS_WORKER */
    SET @wait_type =
            REPLACE
            (
                @wait_type,
                N'THREADPOOL',
                N'SOS_WORKER'
            );

    SELECT DISTINCT
        invalid_waits =
             uw.wait_type
    INTO #invalid_waits
    FROM #user_waits AS uw
    WHERE NOT EXISTS
          (
              SELECT
                  1/0
              FROM sys.dm_xe_map_values AS dxmv
              WHERE dxmv.map_value COLLATE Latin1_General_BIN2 = uw.wait_type COLLATE Latin1_General_BIN2
              AND   dxmv.name = N'wait_types'
          );

    /* If we find any invalid waits, let people know */
    IF @@ROWCOUNT > 0
    BEGIN
        SELECT
            invalid_waits =
                N'You have chosen some invalid wait types'

        UNION ALL

        SELECT
            iw.invalid_waits
        FROM #invalid_waits AS iw;

        RAISERROR(N'Waidaminnithataintawait', 11, 1) WITH NOWAIT;
        RETURN;
    END;

END;


/* I just don't want anyone to be disappointed */
RAISERROR(N'Avoiding disappointment', 0, 1) WITH NOWAIT;
IF
(
        @wait_type <> N''
    AND @wait_type <> N'ALL'
    AND LOWER(@event_type) NOT LIKE N'%wait%'
)
BEGIN
    RAISERROR(N'You can''t filter on wait stats unless you use the wait stats event.', 11, 1) WITH NOWAIT;
    RETURN;
END;


/* This is probably important, huh? */
RAISERROR(N'Are we trying to filter for a blocking session?', 0, 1) WITH NOWAIT;

/* blocking events need a database name to resolve objects */
IF
(
        LOWER(@event_type) LIKE N'%lock%'
    AND DB_ID(@database_name) IS NULL
    AND @object_name <> N''
)
BEGIN
    RAISERROR(N'The blocking event can only filter on an object_id, and we need a valid @database_name to resolve it correctly.', 11, 1) WITH NOWAIT;
    RETURN;
END;

/* but could we resolve the object name? */
IF
(
        LOWER(@event_type) LIKE N'%lock%'
    AND @object_name <> N''
    AND OBJECT_ID(@fully_formed_babby) IS NULL
)
BEGIN
    RAISERROR(N'We couldn''t find the object you''re trying to find: %s', 11, 1, @fully_formed_babby) WITH NOWAIT;
    RETURN;
END;

/* no blocked process report, no love */
RAISERROR(N'Validating if the Blocked Process Report is on, if the session is for blocking', 0, 1) WITH NOWAIT;
IF @event_type LIKE N'%lock%'
AND EXISTS
(
    SELECT
        1/0
    FROM sys.configurations AS c
    WHERE c.name = N'blocked process threshold (s)'
    AND   CONVERT(int, c.value_in_use) = 0
)
BEGIN
        RAISERROR(N'You need to set up the blocked process report in order to use this:
    EXEC sys.sp_configure ''show advanced options'', 1;
    EXEC sys.sp_configure ''blocked process threshold'', 5; /* Seconds of blocking before a report is generated */
    RECONFIGURE;',
    11, 0) WITH NOWAIT;
    RETURN;
END;

/* validatabase name */
RAISERROR(N'If there''s a database filter, is the name valid?', 0, 1) WITH NOWAIT;
IF @database_name <> N''
BEGIN
    IF DB_ID(@database_name) IS NULL
    BEGIN
        RAISERROR(N'It looks like you''re looking for a database that doesn''t wanna be looked for (%s); check that spelling!', 11, 1, @database_name) WITH NOWAIT;
        RETURN;
    END;
END;


/* session id has be be "sampled" or a number. */
RAISERROR(N'If there''s a session id filter, is it valid?', 0, 1) WITH NOWAIT;
IF
(
        LOWER(@session_id) NOT LIKE N'%sample%'
    AND @session_id LIKE N'%[^0-9]%'
    AND LOWER(@session_id) <> N''
)
BEGIN
   RAISERROR(N'That @session_id doesn''t look proper (%s). double check it for me.', 11, 1, @session_id) WITH NOWAIT;
   RETURN;
END;


/* some numbers won't be effective as sample divisors */
RAISERROR(N'No dividing by zero', 0, 1) WITH NOWAIT;
IF
(
        @sample_divisor < 2
    AND LOWER(@session_id) LIKE N'%sample%'
)
BEGIN
    RAISERROR(N'
@sample_divisor is used to divide @session_id when taking a sample of a workload.
we can''t really divide by zero, and dividing by 1 would be useless.', 11, 1) WITH NOWAIT;
    RETURN;
END;


/* CH-CH-CH-CHECK-IT-OUT */

/* check for existing session with the same name */
RAISERROR(N'Make sure the session doesn''t exist already', 0, 1) WITH NOWAIT;

IF @azure = 0
BEGIN
    IF EXISTS
    (
        SELECT
            1/0
        FROM sys.server_event_sessions AS ses
        LEFT JOIN sys.dm_xe_sessions AS dxs
          ON dxs.name = ses.name
        WHERE ses.name = @session_name
    )
    BEGIN
        RAISERROR(N'A session with the name %s already exists. dropping.', 0, 1, @session_name) WITH NOWAIT;

        EXEC sys.sp_executesql
            @drop_sql;
    END;
END;
ELSE
BEGIN
    IF EXISTS
    (
        SELECT
            1/0
        FROM sys.database_event_sessions AS ses
        LEFT JOIN sys.dm_xe_database_sessions AS dxs
          ON dxs.name = ses.name
        WHERE ses.name = @session_name
    )
    BEGIN
        RAISERROR(N'A session with the name %s already exists. dropping.', 0, 1, @session_name) WITH NOWAIT;

        EXEC sys.sp_executesql
            @drop_sql;
    END;
END;

/* check that the output database exists */
RAISERROR(N'Does the output database exist?', 0, 1) WITH NOWAIT;
IF @output_database_name <> N''
BEGIN
    IF DB_ID(@output_database_name) IS NULL
    BEGIN
        RAISERROR(N'It looks like you''re looking for a database (%s) that doesn''t wanna be looked for; check that spelling!', 11, 1, @output_database_name) WITH NOWAIT;
        RETURN;
    END;
END;


/* check that the output schema exists */
RAISERROR(N'Does the output schema exist?', 0, 1) WITH NOWAIT;
IF @output_schema_name NOT IN (N'dbo', N'')
BEGIN
    SELECT
        @s_sql = N'
    SELECT
        @is_out =
            COUNT_BIG(*)
    FROM ' + QUOTENAME(@output_database_name) + N'.sys.schemas AS s
    WHERE s.name = ' + QUOTENAME(@output_schema_name, '''') + N';',
        @s_params  =
            N'@is_out integer OUTPUT';

    EXEC sys.sp_executesql
        @s_sql,
        @s_params,
        @is_out = @s_out OUTPUT;

    IF @s_out = 0
    BEGIN
        RAISERROR(N'It looks like the schema %s doesn''t exist in the database %s', 11, 1, @output_schema_name, @output_database_name);
        RETURN;
    END;
END;


/* we need an output schema and database */
RAISERROR(N'Is output database OR schema filled in?', 0, 1) WITH NOWAIT;
IF
(
     LEN(@output_database_name + @output_schema_name) > 0
    AND  @output_schema_name <> N'dbo'
    AND (@output_database_name  = N''
    OR   @output_schema_name = N'')
)
BEGIN
    IF @output_database_name = N''
        BEGIN
            RAISERROR(N'@output_database_name can''t blank when outputting to tables or cleaning up', 11, 1) WITH NOWAIT;
            RETURN;
        END;

    IF @output_schema_name = N''
        BEGIN
            RAISERROR(N'@output_schema_name can''t blank when outputting to tables or cleaning up', 11, 1) WITH NOWAIT;
            RETURN;
        END;
END;


/* no goofballing in custom names */
RAISERROR(N'Is custom name something stupid?', 0, 1) WITH NOWAIT;
IF
(
    PATINDEX(N'%[^a-zA-Z0-9]%', @custom_name) > 0
      OR @custom_name LIKE N'[0-9]%'
)
BEGIN
    RAISERROR(N'
Dunno if I like the looks of @custom_name: %s
You can''t use special characters, or leading numbers.', 11, 1, @custom_name) WITH NOWAIT;
    RETURN;
END;


/* I'M LOOKING AT YOU */
RAISERROR(N'Someone is going to try it.', 0, 1) WITH NOWAIT;
IF @delete_retention_days < 0
BEGIN
    SET @delete_retention_days *= -1;
    RAISERROR(N'Stay positive', 0, 1) WITH NOWAIT;
END;

/*
We need to do some seconds math here, because WAITFOR is very stupid
*/
RAISERROR(N'Wait For It! Wait For it!', 0, 1) WITH NOWAIT;
IF @seconds_sample > 0
BEGIN
    /* I really don't want this running for more than 10 minutes right now. */
    IF
    (
            @seconds_sample > 600
        AND @gimme_danger = 0
    )
    BEGIN
        RAISERROR(N'Yeah nah not more than 10 minutes', 10, 1) WITH NOWAIT;
        RAISERROR(N'(unless you set @gimme_danger = 1)', 10, 1) WITH NOWAIT;
        RETURN;
    END;

    SELECT
        @waitfor =
            CONVERT
            (
                nvarchar(20),
                DATEADD
                (
                    SECOND,
                    @seconds_sample,
                    '19000101'
                 ),
                 114
            );
END;

/*
If we're writing to a table, we don't want to do anything else
Or anything else after this, really
We want the session to get set up
*/
RAISERROR(N'Do we skip to the GOTO and log tables?', 0, 1) WITH NOWAIT;
IF
(
        @output_database_name <> N''
    AND @output_schema_name <> N''
    AND @cleanup = 0
)
BEGIN
    RAISERROR(N'Skipping all the other stuff and going to data logging', 0, 1) WITH NOWAIT;
    GOTO output_results;
    RETURN;
END;


/* just finishing up the second coat now */
RAISERROR(N'Do we skip to the GOTO and cleanup?', 0, 1) WITH NOWAIT;
IF
(
        @output_database_name <> N''
    AND @output_schema_name <> N''
    AND @cleanup = 1
)
BEGIN
    RAISERROR(N'Skipping all the other stuff and going to cleanup', 0, 1) WITH NOWAIT;
    GOTO cleanup;
    RETURN;
END;


/* Start setting up individual filters */
RAISERROR(N'Setting up individual filters', 0, 1) WITH NOWAIT;
IF @query_duration_ms > 0
BEGIN
    IF LOWER(@event_type) NOT LIKE N'%comp%' /* compile and recompile durations are tiny */
    BEGIN
        SET @query_duration_filter += N'     AND duration >= ' + CONVERT(nvarchar(20), (@query_duration_ms * 1000)) + @nc10;
    END;
END;

IF @blocking_duration_ms > 0
BEGIN
    SET @blocking_duration_ms_filter += N'     AND duration >= ' + CONVERT(nvarchar(20), (@blocking_duration_ms * 1000)) + @nc10;
END;

IF @wait_duration_ms > 0
BEGIN
    SET @wait_duration_filter += N'     AND duration >= ' + CONVERT(nvarchar(20), (@wait_duration_ms)) + @nc10;
END;

IF @client_app_name <> N''
BEGIN
    SET @client_app_name_filter += N'     AND sqlserver.client_app_name = N' + QUOTENAME(@client_app_name, N'''') + @nc10;
END;

IF @client_hostname <> N''
BEGIN
    SET @client_hostname_filter += N'     AND sqlserver.client_hostname = N' + QUOTENAME(@client_hostname, N'''') + @nc10;
END;

IF @database_name <> N''
BEGIN
    IF LOWER(@event_type) NOT LIKE N'%lock%'
    BEGIN
        SET @database_name_filter += N'     AND sqlserver.database_name = N' + QUOTENAME(@database_name, N'''') + @nc10;
    END;
    IF LOWER(@event_type) LIKE N'%lock%'
    BEGIN
        SET @database_name_filter += N'     AND database_name = N' + QUOTENAME(@database_name, N'''') + @nc10;
    END;
END;

IF @session_id <> N''
BEGIN
    IF LOWER(@session_id) NOT LIKE N'%sample%'
        BEGIN
            SET @session_id_filter += N'     AND sqlserver.session_id = ' + CONVERT(nvarchar(11), @session_id) + @nc10;
        END;
    IF LOWER(@session_id) LIKE N'%sample%'
        BEGIN
            SET @session_id_filter += N'     AND package0.divides_by_uint64(sqlserver.session_id, ' + CONVERT(nvarchar(11), @sample_divisor) + N') ' + @nc10;
        END;
END;

IF @username <> N''
BEGIN
    SET @username_filter += N'     AND sqlserver.username = N' + QUOTENAME(@username, '''') + @nc10;
END;

IF @object_name <> N''
BEGIN
    IF @event_type LIKE N'%lock%'
    BEGIN
        SET @object_id = OBJECT_ID(@fully_formed_babby);
        SET @object_name_filter += N'     AND object_id = ' + @object_id + @nc10;
    END;
    IF @event_type NOT LIKE N'%lock%'
    BEGIN
        SET @object_name_filter += N'     AND object_name = N' + QUOTENAME(@object_name, N'''') + @nc10;
    END;
END;

IF @requested_memory_mb > 0
BEGIN
    SET @requested_memory_kb = @requested_memory_mb / 1024.;
    SET @requested_memory_mb_filter += N'     AND requested_memory_kb >= ' + @requested_memory_kb + @nc10;
END;


/* At this point we'll either put my list of interesting waits in a temp table,
   or a list of user defined waits */
IF LOWER(@event_type) LIKE N'%wait%'
BEGIN
    INSERT
        #wait
    (
        wait_type
    )
    SELECT
        x.wait_type
    FROM
    (
        VALUES
            (N'LCK_M_SCH_S'),
            (N'LCK_M_SCH_M'),
            (N'LCK_M_S'),
            (N'LCK_M_U'),
            (N'LCK_M_X'),
            (N'LCK_M_IS'),
            (N'LCK_M_IU'),
            (N'LCK_M_IX'),
            (N'LCK_M_SIU'),
            (N'LCK_M_SIX'),
            (N'LCK_M_UIX'),
            (N'LCK_M_BU'),
            (N'LCK_M_RS_S'),
            (N'LCK_M_RS_U'),
            (N'LCK_M_RIn_NL'),
            (N'LCK_M_RIn_S'),
            (N'LCK_M_RIn_U'),
            (N'LCK_M_RIn_X'),
            (N'LCK_M_RX_S'),
            (N'LCK_M_RX_U'),
            (N'LCK_M_RX_X'),
            (N'LATCH_NL'),
            (N'LATCH_KP'),
            (N'LATCH_SH'),
            (N'LATCH_UP'),
            (N'LATCH_EX'),
            (N'LATCH_DT'),
            (N'PAGELATCH_NL'),
            (N'PAGELATCH_KP'),
            (N'PAGELATCH_SH'),
            (N'PAGELATCH_UP'),
            (N'PAGELATCH_EX'),
            (N'PAGELATCH_DT'),
            (N'PAGEIOLATCH_NL'),
            (N'PAGEIOLATCH_KP'),
            (N'PAGEIOLATCH_SH'),
            (N'PAGEIOLATCH_UP'),
            (N'PAGEIOLATCH_EX'),
            (N'PAGEIOLATCH_DT'),
            (N'IO_COMPLETION'),
            (N'ASYNC_IO_COMPLETION'),
            (N'NETWORK_IO'),
            (N'WRITE_COMPLETION'),
            (N'RESOURCE_SEMAPHORE'),
            (N'RESOURCE_SEMAPHORE_QUERY_COMPILE'),
            (N'RESOURCE_SEMAPHORE_MUTEX'),
            (N'CMEMTHREAD'),
            (N'CXCONSUMER'),
            (N'CXPACKET'),
            (N'EXECSYNC'),
            (N'SOS_WORKER'),
            (N'SOS_SCHEDULER_YIELD'),
            (N'LOGBUFFER'),
            (N'WRITELOG')
    ) AS x (wait_type)
    WHERE @wait_type = N'all'

    UNION ALL

    SELECT
        uw.wait_type
    FROM #user_waits AS uw
    WHERE @wait_type <> N'all';

    /* This section creates a dynamic WHERE clause based on wait types
       The problem is that wait type IDs change frequently, which sucks. */
    WITH maps AS
    (
        SELECT
            dxmv.map_key,
            dxmv.map_value,
            rn =
                dxmv.map_key -
                ROW_NUMBER()
                OVER
                (
                    ORDER BY
                        dxmv.map_key
                )
        FROM sys.dm_xe_map_values AS dxmv
        WHERE dxmv.name = N'wait_types'
        AND   dxmv.map_value IN
              (
                  SELECT
                      w.wait_type
                  FROM #wait AS w
              )
    ),
         grps AS
    (
        SELECT
            minkey =
                MIN(maps.map_key),
            maxkey =
                MAX(maps.map_key)
            FROM maps
            GROUP BY
                maps.rn
    )
    SELECT
        @wait_type_filter +=
            SUBSTRING
            (
                (
                    SELECT
                        N'      AND  ((' +
                        STUFF
                        (
                            (
                                SELECT
                                    N'         OR ' +
                                    CASE
                                        WHEN grps.minkey < grps.maxkey
                                        THEN +
                                        N'(wait_type >= ' +
                                        CONVERT
                                        (
                                            nvarchar(11),
                                            grps.minkey
                                        ) +
                                        N' AND wait_type <= ' +
                                        CONVERT
                                        (
                                            nvarchar(11),
                                            grps.maxkey
                                        ) +
                                        N')' +
                                        @nc10
                                        ELSE N'(wait_type = ' +
                                        CONVERT
                                        (
                                            nvarchar(11),
                                            grps.minkey
                                        ) +
                                        N')' +
                                        @nc10
                                    END
                                FROM grps FOR XML PATH(N''), TYPE
                            ).value('./text()[1]', 'nvarchar(max)')
                            ,
                            1,
                            13,
                            N''
                        )
                ),
                0,
                8000
            ) +
            N')';
END;

/* End individual filters */

/* This section sets event-dependent filters */

RAISERROR(N'Combining session filters', 0, 1) WITH NOWAIT;
/* For full filter-able sessions */
SET @session_filter +=
    (
        ISNULL(@query_duration_filter, N'') +
        ISNULL(@client_app_name_filter, N'') +
        ISNULL(@client_hostname_filter, N'') +
        ISNULL(@database_name_filter, N'') +
        ISNULL(@session_id_filter, N'') +
        ISNULL(@username_filter, N'') +
        ISNULL(@object_name_filter, N'')
    );

/* For waits specifically, because they also need to filter on wait type and wait duration */
SET @session_filter_waits +=
    (
        ISNULL(@wait_duration_filter, N'') +
        ISNULL(@wait_type_filter, N'') +
        ISNULL(@client_app_name_filter, N'') +
        ISNULL(@client_hostname_filter, N'') +
        ISNULL(@database_name_filter, N'') +
        ISNULL(@session_id_filter, N'') +
        ISNULL(@username_filter, N'') +
        ISNULL(@object_name_filter, N'')
    );

/* For sessions that can't filter on client app or host name */
SET @session_filter_limited +=
    (
        ISNULL(@query_duration_filter, N'') +
        ISNULL(@database_name_filter, N'') +
        ISNULL(@session_id_filter, N'') +
        ISNULL(@username_filter, N'') +
        ISNULL(@object_name_filter, N'')
    );

/* For query plans, which can also filter on memory required */
SET @session_filter_query_plans +=
    (
        ISNULL(@query_duration_filter, N'') +
        ISNULL(@database_name_filter, N'') +
        ISNULL(@session_id_filter, N'') +
        ISNULL(@username_filter, N'') +
        ISNULL(@object_name_filter, N'')
    );

/* Recompile can have almost everything except... duration */
SET @session_filter_recompile +=
    (
        ISNULL(@client_app_name_filter, N'') +
        ISNULL(@client_hostname_filter, N'') +
        ISNULL(@database_name_filter, N'') +
        ISNULL(@session_id_filter, N'') +
        ISNULL(@object_name_filter, N'') +
        ISNULL(@username_filter, N'')
    );

/* Apparently statement completed can't filter on an object name so that's fun */
SET @session_filter_statement_completed +=
    (
        ISNULL(@query_duration_filter, N'') +
        ISNULL(@client_app_name_filter, N'') +
        ISNULL(@client_hostname_filter, N'') +
        ISNULL(@database_name_filter, N'') +
        ISNULL(@session_id_filter, N'') +
        ISNULL(@username_filter, N'')
    );

/* Blocking woighoiughuohaeripugbapiouergb */
SET @session_filter_blocking +=
    (
        ISNULL(@blocking_duration_ms_filter, N'') +
        ISNULL(@database_name_filter, N'') +
        ISNULL(@session_id_filter, N'') +
        ISNULL(@username_filter, N'') +
        ISNULL(@object_name_filter, N'') +
        ISNULL(@requested_memory_mb_filter, N'')
    );

/* The parameterization event is pretty limited in weird ways */
SET @session_filter_parameterization +=
    (
        ISNULL(@client_app_name_filter, N'') +
        ISNULL(@client_hostname_filter, N'') +
        ISNULL(@database_name_filter, N'') +
        ISNULL(@session_id_filter, N'') +
        ISNULL(@username_filter, N'')
    );


/* This section sets up the event session definition */
RAISERROR(N'Setting up the event session', 0, 1) WITH NOWAIT;
SET @session_sql +=
        CASE WHEN LOWER(@event_type) LIKE N'%lock%'
             THEN N'
      ADD EVENT sqlserver.blocked_process_report
        (WHERE ( ' + @session_filter_blocking + N' ))'
             WHEN LOWER(@event_type) LIKE N'%quer%'
             THEN N'
      ADD EVENT sqlserver.module_end
        (SET collect_statement = 1
         ACTION (sqlserver.database_name, sqlserver.sql_text, sqlserver.plan_handle, sqlserver.query_hash_signed, sqlserver.query_plan_hash_signed)
         WHERE ( ' + @session_filter + N' )),
      ADD EVENT sqlserver.rpc_completed
        (SET collect_statement = 1
         ACTION(sqlserver.database_name, sqlserver.sql_text, sqlserver.plan_handle, sqlserver.query_hash_signed, sqlserver.query_plan_hash_signed)
         WHERE ( ' + @session_filter + N' )),
      ADD EVENT sqlserver.sp_statement_completed
        (SET collect_object_name = 1, collect_statement = 1
         ACTION(sqlserver.database_name, sqlserver.sql_text, sqlserver.plan_handle, sqlserver.query_hash_signed, sqlserver.query_plan_hash_signed)
         WHERE ( ' + @session_filter + N' )),
      ADD EVENT sqlserver.sql_statement_completed
        (SET collect_statement = 1
         ACTION(sqlserver.database_name, sqlserver.sql_text, sqlserver.plan_handle, sqlserver.query_hash_signed, sqlserver.query_plan_hash_signed)
         WHERE ( ' + @session_filter_statement_completed + N' ))'
                   + CASE WHEN @skip_plans = 0
                          THEN N',
      ADD EVENT sqlserver.query_post_execution_showplan
        (
         ACTION(sqlserver.database_name, sqlserver.sql_text, sqlserver.plan_handle, sqlserver.query_hash_signed, sqlserver.query_plan_hash_signed)
         WHERE ( ' + @session_filter_query_plans + N' ))'
                          ELSE N''
                    END
             WHEN LOWER(@event_type) LIKE N'%wait%'
                    AND @v > 11
             THEN N'
      ADD EVENT sqlos.wait_completed
        (SET collect_wait_resource = 1
         ACTION (sqlserver.database_name, sqlserver.plan_handle, sqlserver.query_hash_signed, sqlserver.query_plan_hash_signed)
         WHERE ( ' + @session_filter_waits + N' ))'
             WHEN LOWER(@event_type) LIKE N'%wait%'
                    AND @v = 11
             THEN N'
      ADD EVENT sqlos.wait_info
        (
         ACTION (sqlserver.database_name, sqlserver.plan_handle, sqlserver.query_hash_signed, sqlserver.query_plan_hash_signed)
         WHERE ( ' + @session_filter_waits + N' ))'
             WHEN LOWER(@event_type) LIKE N'%recomp%'
             THEN CASE WHEN @compile_events = 1
                       THEN N'
      ADD EVENT sqlserver.sql_statement_post_compile
        (SET collect_object_name = 1, collect_statement = 1
         ACTION(sqlserver.database_name)
         WHERE ( ' + @session_filter + N' ))'
                       ELSE N'
      ADD EVENT sqlserver.sql_statement_recompile
        (SET collect_object_name = 1, collect_statement = 1
         ACTION(sqlserver.database_name)
         WHERE ( ' + @session_filter_recompile + N' ))'
                 END
             WHEN (LOWER(@event_type) LIKE N'%comp%'
                     AND LOWER(@event_type) NOT LIKE N'%re%')
             THEN CASE WHEN @compile_events = 1
                       THEN N'
      ADD EVENT sqlserver.sql_statement_post_compile
        (SET collect_object_name = 1, collect_statement = 1
         ACTION(sqlserver.database_name)
         WHERE ( ' + @session_filter + N' ))'
                       ELSE N'
      ADD EVENT sqlserver.uncached_sql_batch_statistics
        (
         ACTION(sqlserver.database_name)
         WHERE ( ' + @session_filter_recompile + N' )),
      ADD EVENT sqlserver.sql_statement_recompile
        (SET collect_object_name = 1, collect_statement = 1
         ACTION(sqlserver.database_name)
         WHERE ( ' + @session_filter_recompile + N' ))'
                  END
                + CASE WHEN @parameterization_events = 1
                       THEN N',
      ADD EVENT sqlserver.query_parameterization_data
        (
         ACTION (sqlserver.database_name, sqlserver.plan_handle, sqlserver.sql_text)
         WHERE ( ' + @session_filter_parameterization + N' ))'
                       ELSE N''
                  END
            ELSE N'i have no idea what i''m doing.'
        END;
/* End event session definition */


/* This creates the event session */
SET @session_sql +=
        @session_with;

IF @debug = 1 BEGIN RAISERROR(@session_sql, 0, 1) WITH NOWAIT; END;
EXEC (@session_sql);

/* This starts the event session */
IF @debug = 1 BEGIN RAISERROR(@start_sql, 0, 1) WITH NOWAIT; END;
EXEC (@start_sql);

/* bail out here if we want to keep the session */
IF @keep_alive = 1
BEGIN
    RAISERROR(N'Session %s created, exiting.', 0, 1, @session_name) WITH NOWAIT;
    RAISERROR(N'To collect data from it, run this proc from an agent job with an output database and schema name', 0, 1) WITH NOWAIT;
    RAISERROR(N'Alternately, you can watch live data stream in by accessing the GUI', 0, 1) WITH NOWAIT;
    RAISERROR(N'Just don''t forget to stop it when you''re done with it!', 0, 1) WITH NOWAIT;
    RETURN;
END;


/* NOW WE WAIT, MR. BOND */
WAITFOR DELAY @waitfor;


/* Dump whatever we got into a temp table */
IF @azure = 0
BEGIN
    INSERT
        #x WITH(TABLOCK)
    (
        x
    )
    SELECT
        x =
            CONVERT
            (
                xml,
                t.target_data
            )
    FROM sys.dm_xe_session_targets AS t
    JOIN sys.dm_xe_sessions AS s
      ON s.address = t.event_session_address
    WHERE s.name = @session_name
    AND   t.target_name = N'ring_buffer';
END;
ELSE
BEGIN
    INSERT
        #x WITH(TABLOCK)
    (
        x
    )
    SELECT
        x =
            CONVERT
            (
                xml,
                t.target_data
            )
    FROM sys.dm_xe_database_session_targets AS t
    JOIN sys.dm_xe_database_sessions AS s
      ON s.address = t.event_session_address
    WHERE s.name = @session_name
    AND   t.target_name = N'ring_buffer';
END;


SELECT
    human_events_xml = e.x.query('.')
INTO #human_events_xml
FROM #x AS x
CROSS APPLY x.x.nodes('/RingBufferTarget/event') AS e(x);


IF @debug = 1
BEGIN
    SELECT N'#human_events_xml' AS table_name, * FROM #human_events_xml AS hex;
END;


/*
This is where magic will happen
*/
IF LOWER(@event_type) LIKE N'%quer%'
BEGIN
    WITH
        queries AS
    (
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
                    oa.c.value('@timestamp', 'datetime2')
                ),
            event_type = oa.c.value('@name', 'nvarchar(256)'),
            database_name = oa.c.value('(action[@name="database_name"]/value/text())[1]', 'nvarchar(256)'),
            object_name = oa.c.value('(data[@name="object_name"]/value/text())[1]', 'nvarchar(256)'),
            sql_text = oa.c.value('(action[@name="sql_text"]/value/text())[1]', 'nvarchar(MAX)'),
            statement = oa.c.value('(data[@name="statement"]/value/text())[1]', 'nvarchar(MAX)'),
            showplan_xml = CASE WHEN @skip_plans = 0 THEN oa.c.query('(data[@name="showplan_xml"]/value/*)[1]') ELSE N'<skip>Skipped Plans</skip>' END,
            cpu_ms = oa.c.value('(data[@name="cpu_time"]/value/text())[1]', 'bigint') / 1000.,
            logical_reads = (oa.c.value('(data[@name="logical_reads"]/value/text())[1]', 'bigint') * 8) / 1024.,
            physical_reads = (oa.c.value('(data[@name="physical_reads"]/value/text())[1]', 'bigint') * 8) / 1024.,
            duration_ms = oa.c.value('(data[@name="duration"]/value/text())[1]', 'bigint') / 1000.,
            writes = (oa.c.value('(data[@name="writes"]/value/text())[1]', 'bigint') * 8) / 1024.,
            spills_mb = (oa.c.value('(data[@name="spills"]/value/text())[1]', 'bigint') * 8) / 1024.,
            row_count = oa.c.value('(data[@name="row_count"]/value/text())[1]', 'bigint'),
            estimated_rows = oa.c.value('(data[@name="estimated_rows"]/value/text())[1]', 'bigint'),
            dop = oa.c.value('(data[@name="dop"]/value/text())[1]', 'int'),
            serial_ideal_memory_mb = oa.c.value('(data[@name="serial_ideal_memory_kb"]/value/text())[1]', 'bigint') / 1024.,
            requested_memory_mb = oa.c.value('(data[@name="requested_memory_kb"]/value/text())[1]', 'bigint') / 1024.,
            used_memory_mb = oa.c.value('(data[@name="used_memory_kb"]/value/text())[1]', 'bigint') / 1024.,
            ideal_memory_mb = oa.c.value('(data[@name="ideal_memory_kb"]/value/text())[1]', 'bigint') / 1024.,
            granted_memory_mb = oa.c.value('(data[@name="granted_memory_kb"]/value/text())[1]', 'bigint') / 1024.,
            query_plan_hash_signed =
                CONVERT
                (
                    binary(8),
                    oa.c.value('(action[@name="query_plan_hash_signed"]/value/text())[1]', 'bigint')
                ),
            query_hash_signed =
                CONVERT
                (
                    binary(8),
                    oa.c.value('(action[@name="query_hash_signed"]/value/text())[1]', 'bigint')
                ),
            plan_handle = oa.c.value('xs:hexBinary((action[@name="plan_handle"]/value/text())[1])', 'varbinary(64)')
        FROM #human_events_xml AS xet
        OUTER APPLY xet.human_events_xml.nodes('//event') AS oa(c)
        WHERE oa.c.exist('(action[@name="query_hash_signed"]/value[. != 0])') = 1
    )
    SELECT
        q.*
    INTO #queries
    FROM queries AS q;

    IF @debug = 1 BEGIN SELECT N'#queries' AS table_name, * FROM #queries AS q; END;

    /* Add attribute StatementId to query plan if it is missing (versions before 2019) */
    IF @skip_plans = 0
    BEGIN
        WITH
            XMLNAMESPACES(DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
        UPDATE q1
            SET showplan_xml.modify('insert attribute StatementId {"1"}
                                     into (/ShowPlanXML/BatchSequence/Batch/Statements/StmtSimple)[1]')
        FROM #queries AS q1
        CROSS APPLY
        (
            SELECT TOP (1)
                statement_text = q2.statement
            FROM #queries AS q2
            WHERE q1.query_hash_signed = q2.query_hash_signed
            AND   q1.query_plan_hash_signed = q2.query_plan_hash_signed
            AND   q2.statement IS NOT NULL
            ORDER BY
                q2.event_time DESC
        ) AS q2
        WHERE q1.showplan_xml IS NOT NULL
        AND   q1.showplan_xml.exist('/ShowPlanXML/BatchSequence/Batch/Statements/StmtSimple/@StatementId') = 0;

        /* Add attribute StatementText to query plan if it is missing (all versions) */
        WITH
            XMLNAMESPACES(DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
        UPDATE q1
            SET showplan_xml.modify('insert attribute StatementText {sql:column("q2.statement_text")}
                                     into (/ShowPlanXML/BatchSequence/Batch/Statements/StmtSimple)[1]')
        FROM #queries AS q1
        CROSS APPLY
        (
            SELECT TOP (1)
                statement_text = q2.statement
            FROM #queries AS q2
            WHERE q1.query_hash_signed = q2.query_hash_signed
            AND   q1.query_plan_hash_signed = q2.query_plan_hash_signed
            AND   q2.statement IS NOT NULL
            ORDER BY
                q2.event_time DESC
        ) AS q2
        WHERE q1.showplan_xml IS NOT NULL
        AND   q1.showplan_xml.exist('/ShowPlanXML/BatchSequence/Batch/Statements/StmtSimple/@StatementText') = 0;
    END;

    WITH
        query_agg AS
    (
       SELECT
           q.query_plan_hash_signed,
           q.query_hash_signed,
           plan_handle = q.plan_handle,
           /*totals*/
           total_cpu_ms = ISNULL(q.cpu_ms, 0.),
           total_logical_reads = ISNULL(q.logical_reads, 0.),
           total_physical_reads = ISNULL(q.physical_reads, 0.),
           total_duration_ms = ISNULL(q.duration_ms, 0.),
           total_writes = ISNULL(q.writes, 0.),
           total_spills_mb = ISNULL(q.spills_mb, 0.),
           total_used_memory_mb = NULL,
           total_granted_memory_mb = NULL,
           total_rows = ISNULL(q.row_count, 0.),
           /*averages*/
           avg_cpu_ms = ISNULL(q.cpu_ms, 0.),
           avg_logical_reads = ISNULL(q.logical_reads, 0.),
           avg_physical_reads = ISNULL(q.physical_reads, 0.),
           avg_duration_ms = ISNULL(q.duration_ms, 0.),
           avg_writes = ISNULL(q.writes, 0.),
           avg_spills_mb = ISNULL(q.spills_mb, 0.),
           avg_used_memory_mb = NULL,
           avg_granted_memory_mb = NULL,
           avg_rows = ISNULL(q.row_count, 0)
       FROM #queries AS q
       WHERE q.event_type <> N'query_post_execution_showplan'

       UNION ALL

       SELECT
           q.query_plan_hash_signed,
           q.query_hash_signed,
           q.plan_handle,
           /*totals*/
           total_cpu_ms = NULL,
           total_logical_reads = NULL,
           total_physical_reads = NULL,
           total_duration_ms = NULL,
           total_writes = NULL,
           total_spills_mb = NULL,
           total_used_memory_mb = ISNULL(q.used_memory_mb, 0.),
           total_granted_memory_mb = ISNULL(q.granted_memory_mb, 0.),
           total_rows = NULL,
           /*averages*/
           avg_cpu_ms = NULL,
           avg_logical_reads = NULL,
           avg_physical_reads = NULL,
           avg_duration_ms = NULL,
           avg_writes = NULL,
           avg_spills_mb = NULL,
           avg_used_memory_mb = ISNULL(q.used_memory_mb, 0.),
           avg_granted_memory_mb = ISNULL(q.granted_memory_mb, 0.),
           avg_rows = NULL
       FROM #queries AS q
       WHERE q.event_type = N'query_post_execution_showplan'
       AND   @skip_plans = 0
    )
    SELECT
        qa.query_plan_hash_signed,
        qa.query_hash_signed,
        plan_handle = MAX(qa.plan_handle),
        total_cpu_ms = SUM(qa.total_cpu_ms),
        total_logical_reads_mb = SUM(qa.total_logical_reads),
        total_physical_reads_mb = SUM(qa.total_physical_reads),
        total_duration_ms = SUM(qa.total_duration_ms),
        total_writes_mb = SUM(qa.total_writes),
        total_spills_mb = SUM(qa.total_spills_mb),
        total_used_memory_mb = SUM(qa.total_used_memory_mb),
        total_granted_memory_mb = SUM(qa.total_granted_memory_mb),
        total_rows = SUM(qa.total_rows),
        avg_cpu_ms = AVG(qa.avg_cpu_ms),
        avg_logical_reads_mb = AVG(qa.avg_logical_reads),
        avg_physical_reads_mb = AVG(qa.avg_physical_reads),
        avg_duration_ms = AVG(qa.avg_duration_ms),
        avg_writes_mb = AVG(qa.avg_writes),
        avg_spills_mb = AVG(qa.avg_spills_mb),
        avg_used_memory_mb = AVG(qa.avg_used_memory_mb),
        avg_granted_memory_mb = AVG(qa.avg_granted_memory_mb),
        avg_rows = AVG(qa.avg_rows),
        executions = COUNT_BIG(qa.plan_handle)
    INTO #totals
    FROM query_agg AS qa
    GROUP BY
        qa.query_plan_hash_signed,
        qa.query_hash_signed;

    IF @debug = 1 BEGIN SELECT N'#totals' AS table_name, * FROM #totals AS t; END;

    WITH
        query_results AS
    (
        SELECT
            q.event_time,
            q.database_name,
            q.object_name,
            q2.statement_text,
            q.sql_text,
            q.showplan_xml,
            t.executions,
            t.total_cpu_ms,
            t.avg_cpu_ms,
            t.total_logical_reads_mb,
            t.avg_logical_reads_mb,
            t.total_physical_reads_mb,
            t.avg_physical_reads_mb,
            t.total_duration_ms,
            t.avg_duration_ms,
            t.total_writes_mb,
            t.avg_writes_mb,
            t.total_spills_mb,
            t.avg_spills_mb,
            t.total_used_memory_mb,
            t.avg_used_memory_mb,
            t.total_granted_memory_mb,
            t.avg_granted_memory_mb,
            t.total_rows,
            t.avg_rows,
            q.serial_ideal_memory_mb,
            q.requested_memory_mb,
            q.ideal_memory_mb,
            q.estimated_rows,
            q.dop,
            q.query_plan_hash_signed,
            q.query_hash_signed,
            q.plan_handle,
            n =
                ROW_NUMBER() OVER
                (
                    PARTITION BY
                        q.query_plan_hash_signed,
                        q.query_hash_signed,
                        q.plan_handle
                    ORDER BY
                        q.query_plan_hash_signed,
                        q.query_hash_signed,
                        q.plan_handle
                )
        FROM #queries AS q
        JOIN #totals AS t
          ON  q.query_hash_signed = t.query_hash_signed
          AND q.query_plan_hash_signed = t.query_plan_hash_signed
          AND (q.plan_handle = t.plan_handle OR @skip_plans = 1)
        CROSS APPLY
        (
            SELECT TOP (1)
                statement_text =
                    q2.statement
            FROM #queries AS q2
            WHERE q.query_hash_signed = q2.query_hash_signed
            AND   q.query_plan_hash_signed = q2.query_plan_hash_signed
            AND   q2.statement IS NOT NULL
            ORDER BY
                q2.event_time DESC
        ) AS q2
        WHERE q.showplan_xml.exist('*') = 1
    )
    SELECT
        q.event_time,
        q.database_name,
        q.object_name,
        statement_text =
            (
                SELECT
                    [processing-instruction(statement_text)] =
                        REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                        REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                        REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                            q.statement_text COLLATE Latin1_General_BIN2,
                        NCHAR(31),N'?'),NCHAR(30),N'?'),NCHAR(29),N'?'),NCHAR(28),N'?'),NCHAR(27),N'?'),NCHAR(26),N'?'),NCHAR(25),N'?'),NCHAR(24),N'?'),NCHAR(23),N'?'),NCHAR(22),N'?'),
                        NCHAR(21),N'?'),NCHAR(20),N'?'),NCHAR(19),N'?'),NCHAR(18),N'?'),NCHAR(17),N'?'),NCHAR(16),N'?'),NCHAR(15),N'?'),NCHAR(14),N'?'),NCHAR(12),N'?'),
                        NCHAR(11),N'?'),NCHAR(8),N'?'),NCHAR(7),N'?'),NCHAR(6),N'?'),NCHAR(5),N'?'),NCHAR(4),N'?'),NCHAR(3),N'?'),NCHAR(2),N'?'),NCHAR(1),N'?'),NCHAR(0),N'?')
                FOR XML
                    PATH(N''),
                    TYPE
            ),
        sql_text =
            (
                SELECT
                    [processing-instruction(sql_text)] =
                        REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                        REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                        REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                            q.sql_text COLLATE Latin1_General_BIN2,
                        NCHAR(31),N'?'),NCHAR(30),N'?'),NCHAR(29),N'?'),NCHAR(28),N'?'),NCHAR(27),N'?'),NCHAR(26),N'?'),NCHAR(25),N'?'),NCHAR(24),N'?'),NCHAR(23),N'?'),NCHAR(22),N'?'),
                        NCHAR(21),N'?'),NCHAR(20),N'?'),NCHAR(19),N'?'),NCHAR(18),N'?'),NCHAR(17),N'?'),NCHAR(16),N'?'),NCHAR(15),N'?'),NCHAR(14),N'?'),NCHAR(12),N'?'),
                        NCHAR(11),N'?'),NCHAR(8),N'?'),NCHAR(7),N'?'),NCHAR(6),N'?'),NCHAR(5),N'?'),NCHAR(4),N'?'),NCHAR(3),N'?'),NCHAR(2),N'?'),NCHAR(1),N'?'),NCHAR(0),N'?')
                FOR XML
                    PATH(N''),
                    TYPE
            ),
        q.showplan_xml,
        q.executions,
        q.total_cpu_ms,
        q.avg_cpu_ms,
        q.total_logical_reads_mb,
        q.avg_logical_reads_mb,
        q.total_physical_reads_mb,
        q.avg_physical_reads_mb,
        q.total_duration_ms,
        q.avg_duration_ms,
        q.total_writes_mb,
        q.avg_writes_mb,
        q.total_spills_mb,
        q.avg_spills_mb,
        q.total_used_memory_mb,
        q.avg_used_memory_mb,
        q.total_granted_memory_mb,
        q.avg_granted_memory_mb,
        q.total_rows,
        q.avg_rows,
        q.serial_ideal_memory_mb,
        q.requested_memory_mb,
        q.ideal_memory_mb,
        q.estimated_rows,
        q.dop,
        q.query_plan_hash_signed,
        q.query_hash_signed,
        q.plan_handle
    FROM query_results AS q
    WHERE q.n = 1
    ORDER BY
         CASE @query_sort_order
              WHEN N'cpu' THEN q.total_cpu_ms
              WHEN N'reads' THEN q.total_logical_reads_mb + q.total_physical_reads_mb
              WHEN N'writes' THEN q.total_writes_mb
              WHEN N'duration' THEN q.total_duration_ms
              WHEN N'spills' THEN q.total_spills_mb
              WHEN N'memory' THEN q.total_granted_memory_mb
              WHEN N'avg cpu' THEN q.avg_cpu_ms
              WHEN N'avg reads' THEN q.avg_logical_reads_mb + q.avg_physical_reads_mb
              WHEN N'avg writes' THEN q.avg_writes_mb
              WHEN N'avg duration' THEN q.avg_duration_ms
              WHEN N'avg spills' THEN q.avg_spills_mb
              WHEN N'avg memory' THEN q.avg_granted_memory_mb
              ELSE N'cpu'
         END DESC
     OPTION(RECOMPILE);
END;


IF LOWER(@event_type) LIKE N'%comp%' AND LOWER(@event_type) NOT LIKE N'%re%'
BEGIN
    IF @compile_events = 1
    BEGIN
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
                    oa.c.value('@timestamp', 'datetime2')
                ),
            event_type = oa.c.value('@name', 'nvarchar(256)'),
            database_name = oa.c.value('(action[@name="database_name"]/value/text())[1]', 'nvarchar(256)'),
            object_name = oa.c.value('(data[@name="object_name"]/value/text())[1]', 'nvarchar(256)'),
            statement_text = oa.c.value('(data[@name="statement"]/value/text())[1]', 'nvarchar(MAX)'),
            compile_cpu_ms = oa.c.value('(data[@name="cpu_time"]/value/text())[1]', 'bigint'),
            compile_duration_ms = oa.c.value('(data[@name="duration"]/value/text())[1]', 'bigint')
        INTO #compiles_1
        FROM #human_events_xml AS xet
        OUTER APPLY xet.human_events_xml.nodes('//event') AS oa(c)
        WHERE oa.c.exist('(data[@name="is_recompile"]/value[. = "false"])') = 1
        AND   oa.c.exist('@name[.= "sql_statement_post_compile"]') = 1
        ORDER BY
            event_time;

        ALTER TABLE #compiles_1 ADD statement_text_checksum AS CHECKSUM(database_name + statement_text) PERSISTED;

        IF @debug = 1 BEGIN SELECT N'#compiles_1' AS table_name, * FROM #compiles_1 AS c; END;

        WITH
            cbq AS
        (
            SELECT
                statement_text_checksum,
                total_compiles = COUNT_BIG(*),
                total_compile_cpu = SUM(compile_cpu_ms),
                avg_compile_cpu = AVG(compile_cpu_ms),
                max_compile_cpu = MAX(compile_cpu_ms),
                total_compile_duration = SUM(compile_duration_ms),
                avg_compile_duration = AVG(compile_duration_ms),
                max_compile_duration = MAX(compile_duration_ms)
            FROM #compiles_1
            GROUP BY
                statement_text_checksum
        )
        SELECT
            pattern = N'total compiles',
            k.database_name,
            k.object_name,
            statement_text =
                (
                    SELECT
                        [processing-instruction(statement_text)] =
                            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                k.statement_text COLLATE Latin1_General_BIN2,
                            NCHAR(31),N'?'),NCHAR(30),N'?'),NCHAR(29),N'?'),NCHAR(28),N'?'),NCHAR(27),N'?'),NCHAR(26),N'?'),NCHAR(25),N'?'),NCHAR(24),N'?'),NCHAR(23),N'?'),NCHAR(22),N'?'),
                            NCHAR(21),N'?'),NCHAR(20),N'?'),NCHAR(19),N'?'),NCHAR(18),N'?'),NCHAR(17),N'?'),NCHAR(16),N'?'),NCHAR(15),N'?'),NCHAR(14),N'?'),NCHAR(12),N'?'),
                            NCHAR(11),N'?'),NCHAR(8),N'?'),NCHAR(7),N'?'),NCHAR(6),N'?'),NCHAR(5),N'?'),NCHAR(4),N'?'),NCHAR(3),N'?'),NCHAR(2),N'?'),NCHAR(1),N'?'),NCHAR(0),N'?')
                    FOR XML
                        PATH(N''),
                        TYPE
                ),
            c.total_compiles,
            c.total_compile_cpu,
            c.avg_compile_cpu,
            c.max_compile_cpu,
            c.total_compile_duration,
            c.avg_compile_duration,
            c.max_compile_duration
        FROM cbq AS c
        CROSS APPLY
        (
            SELECT TOP (1)
                k.*
            FROM #compiles_1 AS k
            WHERE c.statement_text_checksum = k.statement_text_checksum
            ORDER BY
                k.event_time DESC
        ) AS k
        ORDER BY
            c.total_compiles DESC;

    END;
    IF @compile_events = 0
    BEGIN
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
                    oa.c.value('@timestamp', 'datetime2')
                ),
            event_type = oa.c.value('@name', 'nvarchar(256)'),
            database_name = oa.c.value('(action[@name="database_name"]/value/text())[1]', 'nvarchar(256)'),
            object_name = oa.c.value('(data[@name="object_name"]/value/text())[1]', 'nvarchar(256)'),
            statement_text = oa.c.value('(data[@name="statement"]/value/text())[1]', 'nvarchar(MAX)')
        INTO #compiles_0
        FROM #human_events_xml AS xet
        OUTER APPLY xet.human_events_xml.nodes('//event') AS oa(c)
        ORDER BY
            event_time;

        IF @debug = 1 BEGIN SELECT N'#compiles_0' AS table_name, * FROM #compiles_0 AS c; END;

        SELECT
            c.event_time,
            c.event_type,
            c.database_name,
            c.object_name,
            statement_text =
                (
                    SELECT
                        [processing-instruction(statement_text)] =
                            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                c.statement_text COLLATE Latin1_General_BIN2,
                            NCHAR(31),N'?'),NCHAR(30),N'?'),NCHAR(29),N'?'),NCHAR(28),N'?'),NCHAR(27),N'?'),NCHAR(26),N'?'),NCHAR(25),N'?'),NCHAR(24),N'?'),NCHAR(23),N'?'),NCHAR(22),N'?'),
                            NCHAR(21),N'?'),NCHAR(20),N'?'),NCHAR(19),N'?'),NCHAR(18),N'?'),NCHAR(17),N'?'),NCHAR(16),N'?'),NCHAR(15),N'?'),NCHAR(14),N'?'),NCHAR(12),N'?'),
                            NCHAR(11),N'?'),NCHAR(8),N'?'),NCHAR(7),N'?'),NCHAR(6),N'?'),NCHAR(5),N'?'),NCHAR(4),N'?'),NCHAR(3),N'?'),NCHAR(2),N'?'),NCHAR(1),N'?'),NCHAR(0),N'?')
                    FOR XML
                        PATH(N''),
                        TYPE
                )
        FROM #compiles_0 AS c
        ORDER BY
            c.event_time;

    END;

    IF @parameterization_events  = 1
    BEGIN
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
                    oa.c.value('@timestamp', 'datetime2')
                ),
            event_type = oa.c.value('@name', 'nvarchar(256)'),
            database_name = oa.c.value('(action[@name="database_name"]/value/text())[1]', 'nvarchar(256)'),
            sql_text = oa.c.value('(action[@name="sql_text"]/value/text())[1]', 'nvarchar(MAX)'),
            compile_cpu_time_ms = oa.c.value('(data[@name="compile_cpu_time"]/value/text())[1]', 'bigint') / 1000.,
            compile_duration_ms = oa.c.value('(data[@name="compile_duration"]/value/text())[1]', 'bigint') / 1000.,
            query_param_type = oa.c.value('(data[@name="query_param_type"]/value/text())[1]', 'int'),
            is_cached = oa.c.value('(data[@name="is_cached"]/value/text())[1]', 'bit'),
            is_recompiled = oa.c.value('(data[@name="is_recompiled"]/value/text())[1]', 'bit'),
            compile_code = oa.c.value('(data[@name="compile_code"]/text)[1]', 'nvarchar(256)'),
            has_literals = oa.c.value('(data[@name="has_literals"]/value/text())[1]', 'bit'),
            is_parameterizable = oa.c.value('(data[@name="is_parameterizable"]/value/text())[1]', 'bit'),
            parameterized_values_count = oa.c.value('(data[@name="parameterized_values_count"]/value/text())[1]', 'bigint'),
            query_plan_hash = oa.c.value('xs:hexBinary((data[@name="query_plan_hash"]/value/text())[1])', 'binary(8)'),
            query_hash = oa.c.value('xs:hexBinary((data[@name="query_hash"]/value/text())[1])', 'binary(8)'),
            plan_handle = oa.c.value('xs:hexBinary((action[@name="plan_handle"]/value/text())[1])', 'varbinary(64)'),
            statement_sql_hash = oa.c.value('xs:hexBinary((data[@name="statement_sql_hash"]/value/text())[1])', 'varbinary(64)')
        INTO #parameterization
        FROM #human_events_xml AS xet
        OUTER APPLY xet.human_events_xml.nodes('//event') AS oa(c)
        WHERE oa.c.exist('@name[. = "query_parameterization_data"]') = 1
        AND   oa.c.exist('(data[@name="is_recompiled"]/value[. = "false"])') = 1
        ORDER BY
            event_time;

        IF @debug = 1 BEGIN SELECT N'#parameterization' AS table_name, * FROM #parameterization AS p; END;

        WITH
            cpq AS
        (
            SELECT
                database_name,
                query_hash,
                total_compiles = COUNT_BIG(*),
                plan_count = COUNT_BIG(DISTINCT query_plan_hash),
                total_compile_cpu = SUM(compile_cpu_time_ms),
                avg_compile_cpu = AVG(compile_cpu_time_ms),
                max_compile_cpu = MAX(compile_cpu_time_ms),
                total_compile_duration = SUM(compile_duration_ms),
                avg_compile_duration = AVG(compile_duration_ms),
                max_compile_duration = MAX(compile_duration_ms)
            FROM #parameterization
            GROUP BY
                database_name,
                query_hash
           )
           SELECT
               pattern = N'parameterization opportunities',
               c.database_name,
               sql_text =
                   (
                       SELECT
                           [processing-instruction(sql_text)] =
                               REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                               REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                               REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                   k.sql_text COLLATE Latin1_General_BIN2,
                               NCHAR(31),N'?'),NCHAR(30),N'?'),NCHAR(29),N'?'),NCHAR(28),N'?'),NCHAR(27),N'?'),NCHAR(26),N'?'),NCHAR(25),N'?'),NCHAR(24),N'?'),NCHAR(23),N'?'),NCHAR(22),N'?'),
                               NCHAR(21),N'?'),NCHAR(20),N'?'),NCHAR(19),N'?'),NCHAR(18),N'?'),NCHAR(17),N'?'),NCHAR(16),N'?'),NCHAR(15),N'?'),NCHAR(14),N'?'),NCHAR(12),N'?'),
                               NCHAR(11),N'?'),NCHAR(8),N'?'),NCHAR(7),N'?'),NCHAR(6),N'?'),NCHAR(5),N'?'),NCHAR(4),N'?'),NCHAR(3),N'?'),NCHAR(2),N'?'),NCHAR(1),N'?'),NCHAR(0),N'?')
                       FOR XML
                           PATH(N''),
                           TYPE
                   ),
               k.is_parameterizable,
               c.total_compiles,
               c.plan_count,
               c.total_compile_cpu,
               c.avg_compile_cpu,
               c.max_compile_cpu,
               c.total_compile_duration,
               c.avg_compile_duration,
               c.max_compile_duration,
               k.query_param_type,
               k.is_cached,
               k.is_recompiled,
               k.compile_code,
               k.has_literals,
               k.parameterized_values_count
           FROM cpq AS c
           CROSS APPLY
           (
               SELECT TOP (1)
                   k.*
               FROM #parameterization AS k
               WHERE k.query_hash = c.query_hash
               ORDER BY
                   k.event_time DESC
           ) AS k
        ORDER BY
            c.total_compiles DESC;
    END;
END;

IF LOWER(@event_type) LIKE N'%recomp%'
BEGIN
IF @compile_events = 1
    BEGIN
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
                    oa.c.value('@timestamp', 'datetime2')
                ),
            event_type = oa.c.value('@name', 'nvarchar(256)'),
            database_name = oa.c.value('(action[@name="database_name"]/value/text())[1]', 'nvarchar(256)'),
            object_name = oa.c.value('(data[@name="object_name"]/value/text())[1]', 'nvarchar(256)'),
            recompile_cause = oa.c.value('(data[@name="recompile_cause"]/text)[1]', 'nvarchar(256)'),
            statement_text = oa.c.value('(data[@name="statement"]/value/text())[1]', 'nvarchar(MAX)'),
            recompile_cpu_ms = oa.c.value('(data[@name="cpu_time"]/value/text())[1]', 'bigint'),
            recompile_duration_ms = oa.c.value('(data[@name="duration"]/value/text())[1]', 'bigint')
        INTO #recompiles_1
        FROM #human_events_xml AS xet
        OUTER APPLY xet.human_events_xml.nodes('//event') AS oa(c)
        WHERE oa.c.exist('(data[@name="is_recompile"]/value[. = "false"])') = 0
        ORDER BY
            event_time;

        ALTER TABLE #recompiles_1 ADD statement_text_checksum AS CHECKSUM(database_name + statement_text) PERSISTED;

        IF @debug = 1 BEGIN SELECT N'#recompiles_1' AS table_name, * FROM #recompiles_1 AS r; END;

        WITH
            cbq AS
        (
            SELECT
                statement_text_checksum,
                total_recompiles = COUNT_BIG(*),
                total_recompile_cpu = SUM(recompile_cpu_ms),
                avg_recompile_cpu = AVG(recompile_cpu_ms),
                max_recompile_cpu = MAX(recompile_cpu_ms),
                total_recompile_duration = SUM(recompile_duration_ms),
                avg_recompile_duration = AVG(recompile_duration_ms),
                max_recompile_duration = MAX(recompile_duration_ms)
            FROM #recompiles_1
            GROUP BY
                statement_text_checksum
        )
        SELECT
            pattern = N'total recompiles',
            k.recompile_cause,
            k.database_name,
            k.object_name,
            statement_text =
                (
                    SELECT
                        [processing-instruction(statement_text)] =
                            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                k.statement_text COLLATE Latin1_General_BIN2,
                            NCHAR(31),N'?'),NCHAR(30),N'?'),NCHAR(29),N'?'),NCHAR(28),N'?'),NCHAR(27),N'?'),NCHAR(26),N'?'),NCHAR(25),N'?'),NCHAR(24),N'?'),NCHAR(23),N'?'),NCHAR(22),N'?'),
                            NCHAR(21),N'?'),NCHAR(20),N'?'),NCHAR(19),N'?'),NCHAR(18),N'?'),NCHAR(17),N'?'),NCHAR(16),N'?'),NCHAR(15),N'?'),NCHAR(14),N'?'),NCHAR(12),N'?'),
                            NCHAR(11),N'?'),NCHAR(8),N'?'),NCHAR(7),N'?'),NCHAR(6),N'?'),NCHAR(5),N'?'),NCHAR(4),N'?'),NCHAR(3),N'?'),NCHAR(2),N'?'),NCHAR(1),N'?'),NCHAR(0),N'?')
                    FOR XML
                        PATH(N''),
                        TYPE
                ),
            c.total_recompiles,
            c.total_recompile_cpu,
            c.avg_recompile_cpu,
            c.max_recompile_cpu,
            c.total_recompile_duration,
            c.avg_recompile_duration,
            c.max_recompile_duration
        FROM cbq AS c
        CROSS APPLY
        (
            SELECT TOP(1) *
            FROM #recompiles_1 AS k
            WHERE c.statement_text_checksum = k.statement_text_checksum
            ORDER BY
                k.event_time DESC
        ) AS k
        ORDER BY
            c.total_recompiles DESC;

    END;
    IF @compile_events = 0
    BEGIN
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
                    oa.c.value('@timestamp', 'datetime2')
                ),
            event_type = oa.c.value('@name', 'nvarchar(256)'),
            database_name = oa.c.value('(action[@name="database_name"]/value/text())[1]', 'nvarchar(256)'),
            object_name = oa.c.value('(data[@name="object_name"]/value/text())[1]', 'nvarchar(256)'),
            recompile_cause = oa.c.value('(data[@name="recompile_cause"]/text)[1]', 'nvarchar(256)'),
            statement_text = oa.c.value('(data[@name="statement"]/value/text())[1]', 'nvarchar(MAX)')
        INTO #recompiles_0
        FROM #human_events_xml AS xet
        OUTER APPLY xet.human_events_xml.nodes('//event') AS oa(c)
        ORDER BY
            event_time;

        IF @debug = 1 BEGIN SELECT N'#recompiles_0' AS table_name, * FROM #recompiles_0 AS r; END;

        SELECT
            r.event_time,
            r.event_type,
            r.database_name,
            r.object_name,
            r.recompile_cause,
            statement_text =
                (
                    SELECT
                        [processing-instruction(statement_text)] =
                            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                r.statement_text COLLATE Latin1_General_BIN2,
                            NCHAR(31),N'?'),NCHAR(30),N'?'),NCHAR(29),N'?'),NCHAR(28),N'?'),NCHAR(27),N'?'),NCHAR(26),N'?'),NCHAR(25),N'?'),NCHAR(24),N'?'),NCHAR(23),N'?'),NCHAR(22),N'?'),
                            NCHAR(21),N'?'),NCHAR(20),N'?'),NCHAR(19),N'?'),NCHAR(18),N'?'),NCHAR(17),N'?'),NCHAR(16),N'?'),NCHAR(15),N'?'),NCHAR(14),N'?'),NCHAR(12),N'?'),
                            NCHAR(11),N'?'),NCHAR(8),N'?'),NCHAR(7),N'?'),NCHAR(6),N'?'),NCHAR(5),N'?'),NCHAR(4),N'?'),NCHAR(3),N'?'),NCHAR(2),N'?'),NCHAR(1),N'?'),NCHAR(0),N'?')
                    FOR XML
                        PATH(N''),
                        TYPE
                )
        FROM #recompiles_0 AS r
        ORDER BY
            r.event_time;
    END;
END;


IF LOWER(@event_type) LIKE N'%wait%'
BEGIN
    WITH
        waits AS
    (
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
                    oa.c.value('@timestamp', 'datetime2')
                ),
            event_type = oa.c.value('@name', 'nvarchar(256)'),
            database_name = oa.c.value('(action[@name="database_name"]/value/text())[1]', 'nvarchar(256)'),
            wait_type = oa.c.value('(data[@name="wait_type"]/text)[1]', 'nvarchar(256)'),
            duration_ms = oa.c.value('(data[@name="duration"]/value/text())[1]', 'bigint') ,
            signal_duration_ms = oa.c.value('(data[@name="signal_duration"]/value/text())[1]', 'bigint'),
            wait_resource =
                CASE
                    WHEN @v = 11
                    THEN N'Not Available < 2014'
                    ELSE oa.c.value('(data[@name="wait_resource"]/value/text())[1]', 'nvarchar(256)')
                END,
           query_plan_hash_signed =
               CONVERT
               (
                   binary(8),
                   oa.c.value('(action[@name="query_plan_hash_signed"]/value/text())[1]', 'bigint')
               ),
            query_hash_signed =
                CONVERT
                (
                    binary(8),
                    oa.c.value('(action[@name="query_hash_signed"]/value/text())[1]', 'bigint')
                ),
            plan_handle = oa.c.value('xs:hexBinary((action[@name="plan_handle"]/value/text())[1])', 'varbinary(64)')
        FROM
        (
            SELECT TOP (2147483647)
                xet.human_events_xml
            FROM #human_events_xml AS xet
            WHERE (xet.human_events_xml.exist('(//event/data[@name="duration"]/value[. > 0])') = 1
              OR   @gimme_danger = 1)
        ) AS c
        OUTER APPLY c.human_events_xml.nodes('//event') AS oa(c)
    )
    SELECT
        w.*
    INTO #waits_agg
    FROM waits AS w;

    IF @debug = 1 BEGIN SELECT N'#waits_agg' AS table_name, * FROM #waits_agg AS wa; END;

    SELECT
        wait_pattern = N'total waits',
        min_event_time = MIN(wa.event_time),
        max_event_time = MAX(wa.event_time),
        wa.wait_type,
        total_waits = COUNT_BIG(*),
        sum_duration_ms = SUM(wa.duration_ms),
        sum_signal_duration_ms = SUM(wa.signal_duration_ms),
        avg_ms_per_wait = SUM(wa.duration_ms) / COUNT_BIG(*)
    FROM #waits_agg AS wa
    GROUP BY
        wa.wait_type
    ORDER BY
        sum_duration_ms DESC;

    SELECT
        wait_pattern = N'total waits by database',
        min_event_time = MIN(wa.event_time),
        max_event_time = MAX(wa.event_time),
        wa.database_name,
        wa.wait_type,
        total_waits = COUNT_BIG(*),
        sum_duration_ms = SUM(wa.duration_ms),
        sum_signal_duration_ms = SUM(wa.signal_duration_ms),
        avg_ms_per_wait = SUM(wa.duration_ms) / COUNT_BIG(*)
    FROM #waits_agg AS wa
    GROUP BY
        wa.database_name,
        wa.wait_type
    ORDER BY
        sum_duration_ms DESC;

    WITH
        plan_waits AS
    (
        SELECT
            wait_pattern =
                N'total waits by query and database',
            min_event_time =
                MIN(wa.event_time),
            max_event_time =
                MAX(wa.event_time),
            wa.database_name,
            wa.wait_type,
            total_waits =
                COUNT_BIG(*),
            wa.plan_handle,
            sum_duration_ms =
                SUM(wa.duration_ms),
            sum_signal_duration_ms =
                SUM(wa.signal_duration_ms),
            avg_ms_per_wait =
                SUM(wa.duration_ms) / COUNT_BIG(*)
        FROM #waits_agg AS wa
        GROUP BY
            wa.database_name,
            wa.wait_type,
            wa.plan_handle
    )
    SELECT
        pw.wait_pattern,
        pw.min_event_time,
        pw.max_event_time,
        pw.database_name,
        pw.wait_type,
        pw.total_waits,
        pw.sum_duration_ms,
        pw.sum_signal_duration_ms,
        pw.avg_ms_per_wait,
        statement_text =
            (
                SELECT
                    [processing-instruction(statement_text)] =
                        REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                        REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                        REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                            st.text COLLATE Latin1_General_BIN2,
                        NCHAR(31),N'?'),NCHAR(30),N'?'),NCHAR(29),N'?'),NCHAR(28),N'?'),NCHAR(27),N'?'),NCHAR(26),N'?'),NCHAR(25),N'?'),NCHAR(24),N'?'),NCHAR(23),N'?'),NCHAR(22),N'?'),
                        NCHAR(21),N'?'),NCHAR(20),N'?'),NCHAR(19),N'?'),NCHAR(18),N'?'),NCHAR(17),N'?'),NCHAR(16),N'?'),NCHAR(15),N'?'),NCHAR(14),N'?'),NCHAR(12),N'?'),
                        NCHAR(11),N'?'),NCHAR(8),N'?'),NCHAR(7),N'?'),NCHAR(6),N'?'),NCHAR(5),N'?'),NCHAR(4),N'?'),NCHAR(3),N'?'),NCHAR(2),N'?'),NCHAR(1),N'?'),NCHAR(0),N'?')
                FOR XML
                    PATH(N''),
                    TYPE
            ),
           qp.query_plan
    FROM plan_waits AS pw
    OUTER APPLY sys.dm_exec_query_plan(pw.plan_handle) AS qp
    OUTER APPLY sys.dm_exec_sql_text(pw.plan_handle) AS st
    ORDER BY
        pw.sum_duration_ms DESC;
END;


IF LOWER(@event_type) LIKE N'%lock%'
BEGIN
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
                oa.c.value('@timestamp', 'datetime2')
            ),
        database_name = DB_NAME(c.value('(data[@name="database_id"]/value/text())[1]', 'int')),
        database_id = oa.c.value('(data[@name="database_id"]/value/text())[1]', 'int'),
        object_id = oa.c.value('(data[@name="object_id"]/value/text())[1]', 'int'),
        transaction_id = oa.c.value('(data[@name="transaction_id"]/value/text())[1]', 'bigint'),
        resource_owner_type = oa.c.value('(data[@name="resource_owner_type"]/text)[1]', 'nvarchar(256)'),
        monitor_loop = oa.c.value('(//@monitorLoop)[1]', 'int'),
        blocking_spid = bg.value('(process/@spid)[1]', 'int'),
        blocking_ecid = bg.value('(process/@ecid)[1]', 'int'),
        blocked_spid = bd.value('(process/@spid)[1]', 'int'),
        blocked_ecid = bd.value('(process/@ecid)[1]', 'int'),
        query_text_pre = bd.value('(process/inputbuf/text())[1]', 'nvarchar(MAX)'),
        wait_time = bd.value('(process/@waittime)[1]', 'bigint'),
        transaction_name = bd.value('(process/@transactionname)[1]', 'nvarchar(256)'),
        last_transaction_started = bd.value('(process/@lasttranstarted)[1]', 'datetime2'),
        last_transaction_completed = CONVERT(datetime2, NULL),
        wait_resource = bd.value('(process/@waitresource)[1]', 'nvarchar(100)'),
        lock_mode = bd.value('(process/@lockMode)[1]', 'nvarchar(10)'),
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
        currentdbname = bd.value('(process/@currentdbname)[1]', 'nvarchar(256)'),
        currentdbid = bd.value('(process/@currentdb)[1]', 'int'),
        blocking_level = 0,
        sort_order = CAST('' AS varchar(400)),
        activity = CASE WHEN oa.c.exist('//blocked-process-report/blocked-process') = 1 THEN 'blocked' END,
        blocked_process_report = oa.c.query('.')
    INTO #blocked
    FROM #human_events_xml AS bx
    OUTER APPLY bx.human_events_xml.nodes('/event') AS oa(c)
    OUTER APPLY oa.c.nodes('//blocked-process-report/blocked-process') AS bd(bd)
    OUTER APPLY oa.c.nodes('//blocked-process-report/blocking-process') AS bg(bg)
    OPTION(RECOMPILE);

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

    ALTER TABLE #blocked
    ADD blocking_desc AS
            ISNULL
            (
                '(' +
                CAST(blocking_spid AS varchar(10)) +
                ':' +
                CAST(blocking_ecid AS varchar(10)) +
                ')',
                'unresolved process'
            ) PERSISTED,
        blocked_desc AS
            '(' +
            CAST(blocked_spid AS varchar(10)) +
            ':' +
            CAST(blocked_ecid AS varchar(10)) +
            ')' PERSISTED;

    CREATE CLUSTERED INDEX
        blocking
    ON #blocked
        (monitor_loop, blocking_desc);

    CREATE INDEX
        blocked
    ON #blocked
        (monitor_loop, blocked_desc);

    IF @debug = 1 BEGIN SELECT '#blocked' AS table_name, * FROM #blocked AS wa; END;

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
                oa.c.value('@timestamp', 'datetime2')
            ),
        database_name = DB_NAME(c.value('(data[@name="database_id"]/value/text())[1]', 'int')),
        database_id = oa.c.value('(data[@name="database_id"]/value/text())[1]', 'int'),
        object_id = oa.c.value('(data[@name="object_id"]/value/text())[1]', 'int'),
        transaction_id = oa.c.value('(data[@name="transaction_id"]/value/text())[1]', 'bigint'),
        resource_owner_type = oa.c.value('(data[@name="resource_owner_type"]/text)[1]', 'nvarchar(256)'),
        monitor_loop = oa.c.value('(//@monitorLoop)[1]', 'int'),
        blocking_spid = bg.value('(process/@spid)[1]', 'int'),
        blocking_ecid = bg.value('(process/@ecid)[1]', 'int'),
        blocked_spid = bd.value('(process/@spid)[1]', 'int'),
        blocked_ecid = bd.value('(process/@ecid)[1]', 'int'),
        query_text_pre = bg.value('(process/inputbuf/text())[1]', 'nvarchar(MAX)'),
        wait_time = bg.value('(process/@waittime)[1]', 'bigint'),
        transaction_name = bg.value('(process/@transactionname)[1]', 'nvarchar(256)'),
        last_transaction_started = bg.value('(process/@lastbatchstarted)[1]', 'datetime2'),
        last_transaction_completed = bg.value('(process/@lastbatchcompleted)[1]', 'datetime2'),
        wait_resource = bg.value('(process/@waitresource)[1]', 'nvarchar(100)'),
        lock_mode = bg.value('(process/@lockMode)[1]', 'nvarchar(10)'),
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
        currentdbname = bg.value('(process/@currentdbname)[1]', 'nvarchar(128)'),
        currentdbid = bg.value('(process/@currentdb)[1]', 'int'),
        blocking_level = 0,
        sort_order = CAST('' AS varchar(400)),
        activity = CASE WHEN oa.c.exist('//blocked-process-report/blocking-process') = 1 THEN 'blocking' END,
        blocked_process_report = oa.c.query('.')
    INTO #blocking
    FROM #human_events_xml AS bx
    OUTER APPLY bx.human_events_xml.nodes('/event') AS oa(c)
    OUTER APPLY oa.c.nodes('//blocked-process-report/blocking-process') AS bg(bg)
    OUTER APPLY oa.c.nodes('//blocked-process-report/blocked-process') AS bd(bd)
    OPTION(RECOMPILE);

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

    ALTER TABLE #blocking
    ADD blocking_desc AS
            ISNULL
            (
                '(' +
                CAST(blocking_spid AS varchar(10)) +
                ':' +
                CAST(blocking_ecid AS varchar(10)) +
                ')',
                'unresolved process'
            ) PERSISTED,
        blocked_desc AS
            '(' +
            CAST(blocked_spid AS varchar(10)) +
            ':' +
            CAST(blocked_ecid AS varchar(10)) +
            ')' PERSISTED;

    CREATE CLUSTERED INDEX
        blocking
    ON #blocking
        (monitor_loop, blocking_desc);

    CREATE INDEX
        blocked
    ON #blocking
        (monitor_loop, blocked_desc);

    IF @debug = 1 BEGIN SELECT '#blocking' AS table_name, * FROM #blocking AS wa; END;

    WITH
        hierarchy AS
    (
        SELECT
            b.monitor_loop,
            blocking_desc,
            blocked_desc,
            level = 0,
            sort_order =
                CAST
                (
                    blocking_desc +
                    ' <-- ' +
                    blocked_desc AS varchar(400)
                )
        FROM #blocking b
        WHERE NOT EXISTS
        (
            SELECT
                1/0
            FROM #blocking b2
            WHERE b2.monitor_loop = b.monitor_loop
            AND   b2.blocked_desc = b.blocking_desc
        )

        UNION ALL

        SELECT
            bg.monitor_loop,
            bg.blocking_desc,
            bg.blocked_desc,
            h.level + 1,
            sort_order =
                CAST
                (
                    h.sort_order +
                    ' ' +
                    bg.blocking_desc +
                    ' <-- ' +
                    bg.blocked_desc AS varchar(400)
                )
        FROM hierarchy h
        JOIN #blocking bg
          ON  bg.monitor_loop = h.monitor_loop
          AND bg.blocking_desc = h.blocked_desc
    )
    UPDATE #blocked
    SET
        blocking_level = h.level,
        sort_order = h.sort_order
    FROM #blocked b
    JOIN hierarchy h
      ON  h.monitor_loop = b.monitor_loop
      AND h.blocking_desc = b.blocking_desc
      AND h.blocked_desc = b.blocked_desc
    OPTION(RECOMPILE);

    UPDATE #blocking
    SET
        blocking_level = bd.blocking_level,
        sort_order = bd.sort_order
    FROM #blocking bg
    JOIN #blocked bd
      ON  bd.monitor_loop = bg.monitor_loop
      AND bd.blocking_desc = bg.blocking_desc
      AND bd.blocked_desc = bg.blocked_desc
    OPTION(RECOMPILE);

    SELECT
        kheb.event_time,
        kheb.database_name,
        contentious_object =
            ISNULL
            (
                kheb.contentious_object,
                N'Unresolved: ' +
                N'database: ' +
                kheb.database_name +
                N' object_id: ' +
                RTRIM(kheb.object_id)
            ),
        kheb.activity,
        blocking_tree =
            REPLICATE(' > ', kheb.blocking_level) +
            CASE kheb.activity
                 WHEN 'blocking'
                 THEN '(' + kheb.blocking_desc + ') is blocking (' + kheb.blocked_desc + ')'
                 ELSE ' > (' + kheb.blocked_desc + ') is blocked by (' + kheb.blocking_desc + ')'
            END,
        spid =
            CASE kheb.activity
                 WHEN 'blocking'
                 THEN kheb.blocking_spid
                 ELSE kheb.blocked_spid
            END,
        ecid =
            CASE kheb.activity
                 WHEN 'blocking'
                 THEN kheb.blocking_ecid
                 ELSE kheb.blocked_ecid
            END,
        query_text =
            CASE
                WHEN kheb.query_text
                     LIKE @inputbuf_bom + N'Proc |[Database Id = %' ESCAPE N'|'
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
        kheb.lock_mode,
        kheb.resource_owner_type,
        kheb.transaction_count,
        kheb.transaction_name,
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
        kheb.transaction_id,
        kheb.database_id,
        kheb.currentdbname,
        kheb.currentdbid,
        kheb.blocked_process_report,
        kheb.sort_order
    INTO #blocks
    FROM
    (
        SELECT
            bg.*,
            contentious_object =
                OBJECT_NAME
                (
                    bg.object_id,
                    bg.database_id
                )
        FROM #blocking AS bg
        WHERE (bg.database_name = @database_name
               OR @database_name IS NULL)

        UNION ALL

        SELECT
            bd.*,
            contentious_object =
                OBJECT_NAME
                (
                    bd.object_id,
                    bd.database_id
                )
        FROM #blocked AS bd
        WHERE (bd.database_name = @database_name
               OR @database_name IS NULL)
    ) AS kheb
    OPTION(RECOMPILE);

    SELECT
        blocked_process_report =
            'blocked_process_report',
        b.event_time,
        b.database_name,
        b.currentdbname,
        b.contentious_object,
        b.activity,
        b.blocking_tree,
        b.spid,
        b.ecid,
        b.query_text,
        b.wait_time_ms,
        b.status,
        b.isolation_level,
        b.lock_mode,
        b.resource_owner_type,
        b.transaction_count,
        b.transaction_name,
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
        b.transaction_id,
        b.blocked_process_report
    FROM
    (
        SELECT
            b.*,
            n =
                ROW_NUMBER() OVER
                (
                    PARTITION BY
                        b.transaction_id,
                        b.spid,
                        b.ecid
                    ORDER BY
                        b.event_time DESC
                )
        FROM #blocks AS b
    ) AS b
    WHERE b.n = 1
    AND   (b.contentious_object = @object_name
           OR @object_name IS NULL)
    ORDER BY
        b.sort_order,
        CASE
            WHEN b.activity = 'blocking'
            THEN -1
            ELSE +1
        END
    OPTION(RECOMPILE);

    SELECT DISTINCT
        b.*
    INTO #available_plans
    FROM
    (
        SELECT
            available_plans =
                'available_plans',
            b.database_name,
            b.database_id,
            b.currentdbname,
            b.currentdbid,
            b.contentious_object,
            query_text =
                TRY_CAST(b.query_text AS nvarchar(MAX)),
            sql_handle =
                CONVERT(varbinary(64), n.c.value('@sqlhandle', 'varchar(130)'), 1),
            stmtstart =
                ISNULL(n.c.value('@stmtstart', 'int'), 0),
            stmtend =
                ISNULL(n.c.value('@stmtend', 'int'), -1)
        FROM #blocks AS b
        CROSS APPLY b.blocked_process_report.nodes('/event/data/value/blocked-process-report/blocking-process/process/executionStack/frame[not(@sqlhandle = "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")]') AS n(c)
        WHERE (b.database_name = @database_name
                OR @database_name IS NULL)
        AND  (b.contentious_object = @object_name
                OR @object_name IS NULL)

        UNION ALL

        SELECT
            available_plans =
                'available_plans',
            b.database_name,
            b.database_id,
            b.currentdbname,
            b.currentdbid,
            b.contentious_object,
            query_text =
                TRY_CAST(b.query_text AS nvarchar(MAX)),
            sql_handle =
                CONVERT(varbinary(64), n.c.value('@sqlhandle', 'varchar(130)'), 1),
            stmtstart =
                ISNULL(n.c.value('@stmtstart', 'int'), 0),
            stmtend =
                ISNULL(n.c.value('@stmtend', 'int'), -1)
        FROM #blocks AS b
        CROSS APPLY b.blocked_process_report.nodes('/event/data/value/blocked-process-report/blocking-process/process/executionStack/frame[not(@sqlhandle = "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")]') AS n(c)
        WHERE (b.database_name = @database_name
                OR @database_name IS NULL)
        AND  (b.contentious_object = @object_name
                OR @object_name IS NULL)
    ) AS b
    OPTION(RECOMPILE);

    IF @debug = 1 BEGIN SELECT '#available_plans' AS table_name, * FROM #available_plans AS wa OPTION(RECOMPILE); END;

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
    INTO #dm_exec_query_stats
    FROM sys.dm_exec_query_stats AS deqs
    WHERE EXISTS
    (
        SELECT
            1/0
        FROM #available_plans AS ap
        WHERE ap.sql_handle = deqs.sql_handle
    )
    AND deqs.query_hash IS NOT NULL;

    CREATE CLUSTERED INDEX
        deqs
    ON #dm_exec_query_stats
    (
        sql_handle,
        plan_handle
    );

    SELECT
        ap.available_plans,
        ap.database_name,
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
            FROM #dm_exec_query_stats deqs
            OUTER APPLY sys.dm_exec_text_query_plan
            (
                deqs.plan_handle,
                deqs.statement_start_offset,
                deqs.statement_end_offset
            ) AS deps
            WHERE deqs.sql_handle = ap.sql_handle
            AND   deps.dbid IN (ap.database_id, ap.currentdbid)
        ) AS c
    ) AS ap
    WHERE ap.query_plan IS NOT NULL
    ORDER BY
        ap.avg_worker_time_ms DESC
    OPTION(RECOMPILE, LOOP JOIN, HASH JOIN);
END;

/* End magic happening */

IF @keep_alive = 0
BEGIN
    IF @debug = 1 BEGIN RAISERROR(@stop_sql, 0, 1) WITH NOWAIT; END;
    RAISERROR(N'all done, stopping session', 0, 1) WITH NOWAIT;
    EXEC (@stop_sql);

    IF @debug = 1 BEGIN RAISERROR(@drop_sql, 0, 1) WITH NOWAIT; END;
   RAISERROR(N'and dropping session', 0, 1) WITH NOWAIT;
   EXEC (@drop_sql);
END;
RETURN;


/*This section handles outputting data to tables*/
output_results:
RAISERROR(N'Starting data collection.', 0, 1) WITH NOWAIT;

WHILE 1 = 1
BEGIN
    IF @azure = 0
    BEGIN
        IF NOT EXISTS
        (
            /*If we don't find any sessions to poll from, wait 5 seconds and restart loop*/
            SELECT
                1/0
            FROM sys.server_event_sessions AS ses
            LEFT JOIN sys.dm_xe_sessions AS dxs
              ON dxs.name = ses.name
            WHERE ses.name LIKE N'keeper_HumanEvents_%'
            AND   dxs.create_time IS NOT NULL
        )
        BEGIN
            RAISERROR(N'No matching active session names found starting with keeper_HumanEvents', 0, 1) WITH NOWAIT;
        END;

        /*If we find any stopped sessions, turn them back on*/
        SELECT
            @the_sleeper_must_awaken +=
                N'ALTER EVENT SESSION ' +
                ses.name +
                N' ON SERVER STATE = START;' +
                @nc10
        FROM sys.server_event_sessions AS ses
        LEFT JOIN sys.dm_xe_sessions AS dxs
          ON dxs.name = ses.name
        WHERE ses.name LIKE N'keeper_HumanEvents_%'
        AND   dxs.create_time IS NULL;
    END;
    ELSE
    BEGIN
        /*If we don't find any sessions to poll from, wait 5 seconds and restart loop*/
        IF NOT EXISTS
        (
            SELECT
                1/0
            FROM sys.database_event_sessions AS ses
            JOIN sys.dm_xe_database_sessions AS dxs
              ON dxs.name = ses.name
            WHERE ses.name LIKE N'keeper_HumanEvents_%'
        )
        BEGIN
            RAISERROR(N'No matching active session names found starting with keeper_HumanEvents', 0, 1) WITH NOWAIT;
        END;

        /*If we find any stopped sessions, turn them back on*/
        SELECT
            @the_sleeper_must_awaken +=
                N'ALTER EVENT SESSION ' +
                ses.name +
                N' ON DATABASE STATE = START;' +
                @nc10
        FROM sys.database_event_sessions AS ses
        JOIN sys.dm_xe_database_sessions AS dxs
          ON dxs.name = ses.name
        WHERE ses.name LIKE N'keeper_HumanEvents_%';
    END;

    IF LEN(@the_sleeper_must_awaken) > 0
    BEGIN
     IF @debug = 1 BEGIN RAISERROR(@the_sleeper_must_awaken, 0, 1) WITH NOWAIT; END;
     RAISERROR(N'Starting keeper_HumanEvents... inactive sessions', 0, 1) WITH NOWAIT;

     EXEC sys.sp_executesql
         @the_sleeper_must_awaken;
    END;

    IF
    (
        SELECT
            COUNT_BIG(*)
        FROM #human_events_worker AS hew
    ) = 0
    BEGIN
    /*Insert any sessions we find*/
    IF @azure = 0
        BEGIN
            INSERT
                #human_events_worker WITH(TABLOCK)
            (
                event_type,
                event_type_short,
                is_table_created,
                is_view_created,
                last_checked,
                last_updated,
                output_database,
                output_schema,
                output_table
            )
            SELECT
                s.name,
                N'',
                0,
                0,
                '19000101',
                '19000101',
                @output_database_name,
                @output_schema_name,
                s.name
            FROM sys.server_event_sessions AS s
            JOIN sys.dm_xe_sessions AS r
              ON r.name = s.name
            WHERE s.name LIKE N'keeper_HumanEvents_%';
        END;
        ELSE
        BEGIN
            INSERT
                #human_events_worker WITH(TABLOCK)
            (
                event_type,
                event_type_short,
                is_table_created,
                is_view_created,
                last_checked,
                last_updated,
                output_database,
                output_schema,
                output_table
            )
            SELECT
                s.name,
                N'',
                0,
                0,
                '19000101',
                '19000101',
                @output_database_name,
                @output_schema_name,
                s.name
            FROM sys.database_event_sessions AS s
            JOIN sys.dm_xe_database_sessions AS r
              ON r.name = s.name
            WHERE s.name LIKE N'keeper_HumanEvents_%';
        END;

        /*If we're getting compiles, and the parameterization event is available*/
        /*Add a row to the table so we account for it*/
        IF @parameterization_events = 1
           AND EXISTS
           (
               SELECT
                   1/0
               FROM #human_events_worker
               WHERE event_type LIKE N'keeper_HumanEvents_compiles%'
           )
        BEGIN
            INSERT
                #human_events_worker WITH(TABLOCK)
            (
                event_type,
                event_type_short,
                is_table_created,
                is_view_created,
                last_checked,
                last_updated,
                output_database,
                output_schema,
                output_table
            )
            SELECT
                event_type +
                N'_parameterization',
                N'',
                1,
                0,
                last_checked,
                last_updated,
                output_database,
                output_schema,
                output_table + N'_parameterization'
            FROM #human_events_worker
            WHERE event_type LIKE N'keeper_HumanEvents_compiles%';
        END;

        /*Update this column for when we see if we need to create views.*/
        UPDATE hew
            SET
                hew.event_type_short =
                    CASE
                        WHEN hew.event_type LIKE N'%block%'
                        THEN N'[_]Blocking'
                        WHEN ( hew.event_type LIKE N'%comp%'
                                 AND hew.event_type NOT LIKE N'%re%' )
                        THEN N'[_]Compiles'
                        WHEN hew.event_type LIKE N'%quer%'
                        THEN N'[_]Queries'
                        WHEN hew.event_type LIKE N'%recomp%'
                        THEN N'[_]Recompiles'
                        WHEN hew.event_type LIKE N'%wait%'
                        THEN N'[_]Waits'
                        ELSE N'?'
                    END
        FROM #human_events_worker AS hew
        WHERE hew.event_type_short = N'';

        IF @debug = 1 BEGIN SELECT N'#human_events_worker' AS table_name, * FROM #human_events_worker; END;

    END;

    /*This section is where tables that need tables get created*/
    IF EXISTS
    (
        SELECT
            1/0
        FROM #human_events_worker AS hew
        WHERE hew.is_table_created = 0
    )
    BEGIN
        RAISERROR(N'Sessions without tables found, starting loop.', 0, 1) WITH NOWAIT;

        SELECT
            @min_id =
                MIN(hew.id),
            @max_id =
                MAX(hew.id)
        FROM #human_events_worker AS hew
        WHERE hew.is_table_created = 0;

        RAISERROR(N'While, while, while...', 0, 1) WITH NOWAIT;
        WHILE @min_id <= @max_id
        BEGIN
            SELECT
                @event_type_check  =
                    hew.event_type,
                @object_name_check =
                    QUOTENAME(hew.output_database) +
                    N'.' +
                    QUOTENAME(hew.output_schema) +
                    N'.' +
                    hew.output_table
            FROM #human_events_worker AS hew
            WHERE hew.id = @min_id
            AND   hew.is_table_created = 0;

            IF OBJECT_ID(@object_name_check) IS NULL
            BEGIN
            RAISERROR(N'Generating create table statement for %s', 0, 1, @event_type_check) WITH NOWAIT;
                SELECT
                    @table_sql =
                        CASE
                            WHEN @event_type_check LIKE N'%wait%'
                            THEN N'CREATE TABLE ' + @object_name_check + @nc10 +
                                 N'( id bigint PRIMARY KEY IDENTITY, server_name sysname NULL, event_time datetime2 NULL, event_type sysname NULL,  ' + @nc10 +
                                 N'  database_name sysname NULL, wait_type nvarchar(60) NULL, duration_ms bigint NULL, signal_duration_ms bigint NULL, ' + @nc10 +
                                 N'  wait_resource nvarchar(256) NULL, query_plan_hash_signed binary(8) NULL, query_hash_signed binary(8) NULL, plan_handle varbinary(64) NULL );'
                            WHEN @event_type_check LIKE N'%lock%'
                            THEN N'CREATE TABLE ' + @object_name_check + @nc10 +
                                 N'( id bigint PRIMARY KEY IDENTITY, server_name sysname NULL, event_time datetime2 NULL, ' + @nc10 +
                                 N'  activity nvarchar(20) NULL, database_name sysname NULL, database_id integer NULL, object_id bigint NULL, contentious_object AS OBJECT_NAME(object_id, database_id), ' + @nc10 +
                                 N'  transaction_id bigint NULL, resource_owner_type nvarchar(256) NULL, monitor_loop integer NULL, spid integer NULL, ecid integer NULL, query_text nvarchar(MAX) NULL, ' +
                                 N'  wait_time bigint NULL, transaction_name nvarchar(256) NULL, last_transaction_started nvarchar(30) NULL, wait_resource nvarchar(100) NULL, ' + @nc10 +
                                 N'  lock_mode nvarchar(10) NULL, status nvarchar(10) NULL, priority integer NULL, transaction_count integer NULL, ' + @nc10 +
                                 N'  client_app sysname NULL, host_name sysname NULL, login_name sysname NULL, isolation_level nvarchar(30) NULL, sql_handle varbinary(64) NULL, blocked_process_report XML NULL );'
                            WHEN @event_type_check LIKE N'%quer%'
                            THEN N'CREATE TABLE ' + @object_name_check + @nc10 +
                                 N'( id bigint PRIMARY KEY IDENTITY, server_name sysname NULL, event_time datetime2 NULL, event_type sysname NULL, ' + @nc10 +
                                 N'  database_name sysname NULL, object_name nvarchar(512) NULL, sql_text nvarchar(MAX) NULL, statement nvarchar(MAX) NULL, ' + @nc10 +
                                 N'  showplan_xml XML NULL, cpu_ms decimal(18,2) NULL, logical_reads decimal(18,2) NULL, ' + @nc10 +
                                 N'  physical_reads decimal(18,2) NULL, duration_ms decimal(18,2) NULL, writes_mb decimal(18,2) NULL,' + @nc10 +
                                 N'  spills_mb decimal(18,2) NULL, row_count decimal(18,2) NULL, estimated_rows decimal(18,2) NULL, dop integer NULL,  ' + @nc10 +
                                 N'  serial_ideal_memory_mb decimal(18,2) NULL, requested_memory_mb decimal(18,2) NULL, used_memory_mb decimal(18,2) NULL, ideal_memory_mb decimal(18,2) NULL, ' + @nc10 +
                                 N'  granted_memory_mb decimal(18,2) NULL, query_plan_hash_signed binary(8) NULL, query_hash_signed binary(8) NULL, plan_handle varbinary(64) NULL );'
                            WHEN @event_type_check LIKE N'%recomp%'
                            THEN N'CREATE TABLE ' + @object_name_check + @nc10 +
                                 N'( id bigint PRIMARY KEY IDENTITY, server_name sysname NULL, event_time datetime2 NULL, event_type sysname NULL,  ' + @nc10 +
                                 N'  database_name sysname NULL, object_name nvarchar(512) NULL, recompile_cause nvarchar(256) NULL, statement_text nvarchar(MAX) NULL, statement_text_checksum AS CHECKSUM(database_name + statement_text) PERSISTED '
                                 + CASE WHEN @compile_events = 1 THEN N', compile_cpu_ms bigint NULL, compile_duration_ms bigint NULL );' ELSE N' );' END
                            WHEN @event_type_check LIKE N'%comp%' AND @event_type_check NOT LIKE N'%re%'
                            THEN N'CREATE TABLE ' + @object_name_check + @nc10 +
                                 N'( id bigint PRIMARY KEY IDENTITY, server_name sysname NULL, event_time datetime2 NULL, event_type sysname NULL,  ' + @nc10 +
                                 N'  database_name sysname NULL, object_name nvarchar(512) NULL, statement_text nvarchar(MAX) NULL, statement_text_checksum AS CHECKSUM(database_name + statement_text) PERSISTED '
                                 + CASE WHEN @compile_events = 1 THEN N', compile_cpu_ms bigint NULL, compile_duration_ms bigint NULL );' ELSE N' );' END
                                 + CASE WHEN @parameterization_events = 1
                                        THEN
                                 @nc10 +
                                 N'CREATE TABLE ' + @object_name_check + N'_parameterization' + @nc10 +
                                 N'( id bigint PRIMARY KEY IDENTITY, server_name sysname NULL, event_time datetime2 NULL,  event_type sysname NULL,  ' + @nc10 +
                                 N'  database_name sysname NULL, sql_text nvarchar(MAX) NULL, compile_cpu_time_ms bigint NULL, compile_duration_ms bigint NULL, query_param_type integer NULL,  ' + @nc10 +
                                 N'  is_cached bit NULL, is_recompiled bit NULL, compile_code nvarchar(256) NULL, has_literals bit NULL, is_parameterizable bit NULL, parameterized_values_count bigint NULL, ' + @nc10 +
                                 N'  query_plan_hash binary(8) NULL, query_hash binary(8) NULL, plan_handle varbinary(64) NULL, statement_sql_hash varbinary(64) NULL );'
                                        ELSE N''
                                   END
                            ELSE N''
                      END;
            END;

            IF @debug = 1 BEGIN RAISERROR(@table_sql, 0, 1) WITH NOWAIT; END;
            EXEC sys.sp_executesql
                @table_sql;

            RAISERROR(N'Updating #human_events_worker to set is_table_created for %s', 0, 1, @event_type_check) WITH NOWAIT;
            UPDATE #human_events_worker
                SET is_table_created = 1
            WHERE id = @min_id
            AND is_table_created = 0;

            IF @debug = 1 BEGIN RAISERROR(N'@min_id: %i', 0, 1, @min_id) WITH NOWAIT; END;

            RAISERROR(N'Setting next id after %i out of %i total', 0, 1, @min_id, @max_id) WITH NOWAIT;

            SET @min_id =
            (
                SELECT TOP (1)
                    hew.id
                FROM #human_events_worker AS hew
                WHERE hew.id > @min_id
                AND   hew.is_table_created = 0
                ORDER BY
                    hew.id
            );

            IF @debug = 1 BEGIN RAISERROR(N'new @min_id: %i', 0, 1, @min_id) WITH NOWAIT; END;

            IF @min_id IS NULL BREAK;

        END;
    END;

/*This section handles creating or altering views*/
IF EXISTS
(   /* Any views not created */
    SELECT
        1/0
    FROM #human_events_worker AS hew
    WHERE hew.is_table_created = 1
    AND   hew.is_view_created = 0
)
OR
(   /* If the proc has been modified, maybe views have been added or changed? */
    SELECT
        modify_date
    FROM sys.all_objects
    WHERE type = N'P'
    AND name = N'sp_HumanEvents'
) < DATEADD(HOUR, -1, SYSDATETIME())
BEGIN
    RAISERROR(N'Found views to create, beginning!', 0, 1) WITH NOWAIT;
    IF
    (
        SELECT
            COUNT_BIG(*)
        FROM #view_check AS vc
    ) = 0
    BEGIN
        RAISERROR(N'#view_check was empty, creating and populating', 0, 1) WITH NOWAIT;
        /* These binary values are the view definitions. If I didn't do this, I would have been adding >50k lines of code in here. */
        INSERT #view_check (view_name, view_definition)
        SELECT N'HumanEvents_Blocking', 0x430052004500410054004500200056004900450057002000640062006F002E00480075006D0061006E004500760065006E00740073005F0042006C006F0063006B0069006E0067000D000A00410053000D000A00530045004C00450043005400200054004F00500020002800320031003400370034003800330036003400370029000D000A0020002000200020006B006800650062002E006500760065006E0074005F00740069006D0065002C000D000A0020002000200020006B006800650062002E00640061007400610062006100730065005F006E0061006D0065002C000D000A0020002000200020006B006800650062002E0063006F006E00740065006E00740069006F00750073005F006F0062006A006500630074002C000D000A0020002000200020006B006800650062002E00610063007400690076006900740079002C000D000A0020002000200020006B006800650062002E0073007000690064002C000D000A0020002000200020006B006800650062002E00710075006500720079005F0074006500780074002C000D000A0020002000200020006B006800650062002E0077006100690074005F00740069006D0065002C000D000A0020002000200020006B006800650062002E007300740061007400750073002C000D000A0020002000200020006B006800650062002E00690073006F006C006100740069006F006E005F006C006500760065006C002C000D000A0020002000200020006B006800650062002E006C006100730074005F007400720061006E00730061006300740069006F006E005F0073007400610072007400650064002C000D000A0020002000200020006B006800650062002E007400720061006E00730061006300740069006F006E005F006E0061006D0065002C000D000A0020002000200020006B006800650062002E006C006F0063006B005F006D006F00640065002C000D000A0020002000200020006B006800650062002E007000720069006F0072006900740079002C000D000A0020002000200020006B006800650062002E007400720061006E00730061006300740069006F006E005F0063006F0075006E0074002C000D000A0020002000200020006B006800650062002E0063006C00690065006E0074005F006100700070002C000D000A0020002000200020006B006800650062002E0068006F00730074005F006E0061006D0065002C000D000A0020002000200020006B006800650062002E006C006F00670069006E005F006E0061006D0065002C000D000A0020002000200020006B006800650062002E0062006C006F0063006B00650064005F00700072006F0063006500730073005F007200650070006F00720074000D000A00460052004F004D0020005B007200650070006C006100630065005F006D0065005D0020004100530020006B006800650062000D000A004F0052004400450052002000420059000D000A0020002000200020006B006800650062002E006500760065006E0074005F00740069006D0065002C000D000A00200020002000200043004100530045000D000A00200020002000200020002000200020005700480045004E0020006B006800650062002E006100630074006900760069007400790020003D002000270062006C006F0063006B0069006E00670027000D000A00200020002000200020002000200020005400480045004E00200031000D000A002000200020002000200020002000200045004C005300450020003900390039000D000A00200020002000200045004E0044003B00;
        INSERT #view_check (view_name, view_definition)
        SELECT N'HumanEvents_CompilesByDatabaseAndObject', 0x430052004500410054004500200056004900450057002000640062006F002E00480075006D0061006E004500760065006E00740073005F0043006F006D00700069006C0065007300420079004400610074006100620061007300650041006E0064004F0062006A006500630074000D000A00410053000D000A00530045004C00450043005400200054004F00500020002800320031003400370034003800330036003400380029000D000A0020002000200020006D0069006E005F006500760065006E0074005F00740069006D00650020003D0020004D0049004E0028006500760065006E0074005F00740069006D00650029002C000D000A0020002000200020006D00610078005F006500760065006E0074005F00740069006D00650020003D0020004D004100580028006500760065006E0074005F00740069006D00650029002C000D000A002000200020002000640061007400610062006100730065005F006E0061006D0065002C000D000A0020002000200020006F0062006A006500630074005F006E0061006D00650020003D0020000D000A002000200020002000200020002000200043004100530045000D000A002000200020002000200020002000200020002000200020005700480045004E0020006F0062006A006500630074005F006E0061006D00650020003D0020004E00270027000D000A002000200020002000200020002000200020002000200020005400480045004E0020004E0027004E002F00410027000D000A0020002000200020002000200020002000200020002000200045004C005300450020006F0062006A006500630074005F006E0061006D0065000D000A002000200020002000200020002000200045004E0044002C000D000A00200020002000200074006F00740061006C005F0063006F006D00700069006C006500730020003D00200043004F0055004E0054005F0042004900470028002A0029002C000D000A00200020002000200074006F00740061006C005F0063006F006D00700069006C0065005F0063007000750020003D002000530055004D00280063006F006D00700069006C0065005F006300700075005F006D00730029002C000D000A0020002000200020006100760067005F0063006F006D00700069006C0065005F0063007000750020003D002000410056004700280063006F006D00700069006C0065005F006300700075005F006D00730029002C000D000A0020002000200020006D00610078005F0063006F006D00700069006C0065005F0063007000750020003D0020004D0041005800280063006F006D00700069006C0065005F006300700075005F006D00730029002C000D000A00200020002000200074006F00740061006C005F0063006F006D00700069006C0065005F006400750072006100740069006F006E0020003D002000530055004D00280063006F006D00700069006C0065005F006400750072006100740069006F006E005F006D00730029002C000D000A0020002000200020006100760067005F0063006F006D00700069006C0065005F006400750072006100740069006F006E0020003D002000410056004700280063006F006D00700069006C0065005F006400750072006100740069006F006E005F006D00730029002C000D000A0020002000200020006D00610078005F0063006F006D00700069006C0065005F006400750072006100740069006F006E0020003D0020004D0041005800280063006F006D00700069006C0065005F006400750072006100740069006F006E005F006D00730029000D000A00460052004F004D0020005B007200650070006C006100630065005F006D0065005D000D000A00470052004F00550050002000420059000D000A002000200020002000640061007400610062006100730065005F006E0061006D0065002C000D000A0020002000200020006F0062006A006500630074005F006E0061006D0065000D000A004F00520044004500520020004200590020000D000A00200020002000200074006F00740061006C005F0063006F006D00700069006C0065007300200044004500530043003B00
        WHERE @compile_events = 1;
        INSERT #view_check (view_name, view_definition)
        SELECT N'HumanEvents_CompilesByDuration', 0x430052004500410054004500200056004900450057002000640062006F002E00480075006D0061006E004500760065006E00740073005F0043006F006D00700069006C0065007300420079004400750072006100740069006F006E000D000A00410053000D000A0057004900540048000D000A0020002000200020006300620071002000410053000D000A0028000D000A002000200020002000530045004C004500430054000D000A0020002000200020002000200020002000730074006100740065006D0065006E0074005F0074006500780074005F0063006800650063006B00730075006D002C000D000A002000200020002000200020002000200074006F00740061006C005F0063006F006D00700069006C006500730020003D00200043004F0055004E0054005F0042004900470028002A0029002C000D000A002000200020002000200020002000200074006F00740061006C005F0063006F006D00700069006C0065005F0063007000750020003D002000530055004D00280063006F006D00700069006C0065005F006300700075005F006D00730029002C000D000A00200020002000200020002000200020006100760067005F0063006F006D00700069006C0065005F0063007000750020003D002000410056004700280063006F006D00700069006C0065005F006300700075005F006D00730029002C000D000A00200020002000200020002000200020006D00610078005F0063006F006D00700069006C0065005F0063007000750020003D0020004D0041005800280063006F006D00700069006C0065005F006300700075005F006D00730029002C000D000A002000200020002000200020002000200074006F00740061006C005F0063006F006D00700069006C0065005F006400750072006100740069006F006E0020003D002000530055004D00280063006F006D00700069006C0065005F006400750072006100740069006F006E005F006D00730029002C000D000A00200020002000200020002000200020006100760067005F0063006F006D00700069006C0065005F006400750072006100740069006F006E0020003D002000410056004700280063006F006D00700069006C0065005F006400750072006100740069006F006E005F006D00730029002C000D000A00200020002000200020002000200020006D00610078005F0063006F006D00700069006C0065005F006400750072006100740069006F006E0020003D0020004D0041005800280063006F006D00700069006C0065005F006400750072006100740069006F006E005F006D00730029000D000A002000200020002000460052004F004D0020005B007200650070006C006100630065005F006D0065005D000D000A002000200020002000470052004F005500500020004200590020000D000A0020002000200020002000200020002000730074006100740065006D0065006E0074005F0074006500780074005F0063006800650063006B00730075006D000D000A00200020002000200048004100560049004E00470020000D000A0020002000200020002000200020002000410056004700280063006F006D00700069006C0065005F006400750072006100740069006F006E005F006D007300290020003E00200031003000300030000D000A0029000D000A00530045004C00450043005400200054004F00500020002800320031003400370034003800330036003400380029000D000A0020002000200020006B002E006F0062006A006500630074005F006E0061006D0065002C000D000A0020002000200020006B002E00730074006100740065006D0065006E0074005F0074006500780074002C000D000A00200020002000200063002E0074006F00740061006C005F0063006F006D00700069006C00650073002C000D000A00200020002000200063002E0074006F00740061006C005F0063006F006D00700069006C0065005F006300700075002C000D000A00200020002000200063002E006100760067005F0063006F006D00700069006C0065005F006300700075002C000D000A00200020002000200063002E006D00610078005F0063006F006D00700069006C0065005F006300700075002C000D000A00200020002000200063002E0074006F00740061006C005F0063006F006D00700069006C0065005F006400750072006100740069006F006E002C000D000A00200020002000200063002E006100760067005F0063006F006D00700069006C0065005F006400750072006100740069006F006E002C000D000A00200020002000200063002E006D00610078005F0063006F006D00700069006C0065005F006400750072006100740069006F006E000D000A00460052004F004D002000630062007100200041005300200063000D000A00430052004F005300530020004100500050004C0059000D000A0028000D000A002000200020002000530045004C00450043005400200054004F00500020002800310029000D000A00200020002000200020002000200020006B002E002A000D000A002000200020002000460052004F004D0020005B007200650070006C006100630065005F006D0065005D0020004100530020006B000D000A00200020002000200057004800450052004500200063002E00730074006100740065006D0065006E0074005F0074006500780074005F0063006800650063006B00730075006D0020003D0020006B002E00730074006100740065006D0065006E0074005F0074006500780074005F0063006800650063006B00730075006D000D000A0020002000200020004F00520044004500520020004200590020000D000A00200020002000200020002000200020006B002E0069006400200044004500530043000D000A00290020004100530020006B000D000A004F00520044004500520020004200590020000D000A00200020002000200063002E006100760067005F0063006F006D00700069006C0065005F006400750072006100740069006F006E00200044004500530043003B00
        WHERE @compile_events = 1;
        INSERT #view_check (view_name, view_definition)
        SELECT N'HumanEvents_CompilesByQuery', 0x430052004500410054004500200056004900450057002000640062006F002E00480075006D0061006E004500760065006E00740073005F0043006F006D00700069006C006500730042007900510075006500720079000D000A00410053000D000A0057004900540048000D000A0020002000200020006300620071002000410053000D000A0028000D000A002000200020002000530045004C004500430054000D000A0020002000200020002000200020002000730074006100740065006D0065006E0074005F0074006500780074005F0063006800650063006B00730075006D002C000D000A002000200020002000200020002000200074006F00740061006C005F0063006F006D00700069006C006500730020003D00200043004F0055004E0054005F0042004900470028002A0029002C000D000A002000200020002000200020002000200074006F00740061006C005F0063006F006D00700069006C0065005F0063007000750020003D002000530055004D00280063006F006D00700069006C0065005F006300700075005F006D00730029002C000D000A00200020002000200020002000200020006100760067005F0063006F006D00700069006C0065005F0063007000750020003D002000410056004700280063006F006D00700069006C0065005F006300700075005F006D00730029002C000D000A00200020002000200020002000200020006D00610078005F0063006F006D00700069006C0065005F0063007000750020003D0020004D0041005800280063006F006D00700069006C0065005F006300700075005F006D00730029002C000D000A002000200020002000200020002000200074006F00740061006C005F0063006F006D00700069006C0065005F006400750072006100740069006F006E0020003D002000530055004D00280063006F006D00700069006C0065005F006400750072006100740069006F006E005F006D00730029002C000D000A00200020002000200020002000200020006100760067005F0063006F006D00700069006C0065005F006400750072006100740069006F006E0020003D002000410056004700280063006F006D00700069006C0065005F006400750072006100740069006F006E005F006D00730029002C000D000A00200020002000200020002000200020006D00610078005F0063006F006D00700069006C0065005F006400750072006100740069006F006E0020003D0020004D0041005800280063006F006D00700069006C0065005F006400750072006100740069006F006E005F006D00730029000D000A002000200020002000460052004F004D0020005B007200650070006C006100630065005F006D0065005D000D000A002000200020002000470052004F005500500020004200590020000D000A0020002000200020002000200020002000730074006100740065006D0065006E0074005F0074006500780074005F0063006800650063006B00730075006D000D000A00200020002000200048004100560049004E00470020000D000A002000200020002000200020002000200043004F0055004E0054005F0042004900470028002A00290020003E003D002000310030000D000A0029000D000A00530045004C00450043005400200054004F00500020002800320031003400370034003800330036003400380029000D000A0020002000200020006B002E006F0062006A006500630074005F006E0061006D0065002C000D000A0020002000200020006B002E00730074006100740065006D0065006E0074005F0074006500780074002C000D000A00200020002000200063002E0074006F00740061006C005F0063006F006D00700069006C00650073002C000D000A00200020002000200063002E0074006F00740061006C005F0063006F006D00700069006C0065005F006300700075002C000D000A00200020002000200063002E006100760067005F0063006F006D00700069006C0065005F006300700075002C000D000A00200020002000200063002E006D00610078005F0063006F006D00700069006C0065005F006300700075002C000D000A00200020002000200063002E0074006F00740061006C005F0063006F006D00700069006C0065005F006400750072006100740069006F006E002C000D000A00200020002000200063002E006100760067005F0063006F006D00700069006C0065005F006400750072006100740069006F006E002C000D000A00200020002000200063002E006D00610078005F0063006F006D00700069006C0065005F006400750072006100740069006F006E000D000A00460052004F004D002000630062007100200041005300200063000D000A00430052004F005300530020004100500050004C0059000D000A0028000D000A002000200020002000530045004C00450043005400200054004F00500020002800310029000D000A00200020002000200020002000200020006B002E002A000D000A002000200020002000460052004F004D0020005B007200650070006C006100630065005F006D0065005D0020004100530020006B000D000A00200020002000200057004800450052004500200063002E00730074006100740065006D0065006E0074005F0074006500780074005F0063006800650063006B00730075006D0020003D0020006B002E00730074006100740065006D0065006E0074005F0074006500780074005F0063006800650063006B00730075006D000D000A0020002000200020004F00520044004500520020004200590020006B002E0069006400200044004500530043000D000A00290020004100530020006B000D000A004F00520044004500520020004200590020000D000A00200020002000200063002E0074006F00740061006C005F0063006F006D00700069006C0065007300200044004500530043003B00
        WHERE @compile_events = 1;
        INSERT #view_check (view_name, view_definition)
        SELECT N'HumanEvents_Parameterization', 0x430052004500410054004500200056004900450057002000640062006F002E00480075006D0061006E004500760065006E00740073005F0050006100720061006D00650074006500720069007A006100740069006F006E000D000A00410053000D000A0057004900540048000D000A0020002000200020006300700071002000410053000D000A0028000D000A002000200020002000530045004C004500430054000D000A0020002000200020002000200020002000640061007400610062006100730065005F006E0061006D0065002C000D000A0020002000200020002000200020002000710075006500720079005F0068006100730068002C000D000A002000200020002000200020002000200074006F00740061006C005F0063006F006D00700069006C006500730020003D00200043004F0055004E0054005F0042004900470028002A0029002C000D000A002000200020002000200020002000200070006C0061006E005F0063006F0075006E00740020003D00200043004F0055004E0054002800440049005300540049004E00430054002000710075006500720079005F0070006C0061006E005F00680061007300680029002C000D000A002000200020002000200020002000200074006F00740061006C005F0063006F006D00700069006C0065005F0063007000750020003D002000530055004D00280063006F006D00700069006C0065005F006300700075005F00740069006D0065005F006D00730029002C000D000A00200020002000200020002000200020006100760067005F0063006F006D00700069006C0065005F0063007000750020003D002000410056004700280063006F006D00700069006C0065005F006300700075005F00740069006D0065005F006D00730029002C000D000A00200020002000200020002000200020006D00610078005F0063006F006D00700069006C0065005F0063007000750020003D0020004D0041005800280063006F006D00700069006C0065005F006300700075005F00740069006D0065005F006D00730029002C000D000A002000200020002000200020002000200074006F00740061006C005F0063006F006D00700069006C0065005F006400750072006100740069006F006E0020003D002000530055004D00280063006F006D00700069006C0065005F006400750072006100740069006F006E005F006D00730029002C000D000A00200020002000200020002000200020006100760067005F0063006F006D00700069006C0065005F006400750072006100740069006F006E0020003D002000410056004700280063006F006D00700069006C0065005F006400750072006100740069006F006E005F006D00730029002C000D000A00200020002000200020002000200020006D00610078005F0063006F006D00700069006C0065005F006400750072006100740069006F006E0020003D0020004D0041005800280063006F006D00700069006C0065005F006400750072006100740069006F006E005F006D00730029000D000A002000200020002000460052004F004D0020005B007200650070006C006100630065005F006D0065005D000D000A002000200020002000470052004F00550050002000420059000D000A0020002000200020002000200020002000640061007400610062006100730065005F006E0061006D0065002C000D000A0020002000200020002000200020002000710075006500720079005F0068006100730068000D000A0029000D000A00530045004C00450043005400200054004F00500020002800320031003400370034003800330036003400380029000D000A00200020002000200063002E00640061007400610062006100730065005F006E0061006D0065002C000D000A0020002000200020006B002E00730071006C005F0074006500780074002C000D000A0020002000200020006B002E00690073005F0070006100720061006D00650074006500720069007A00610062006C0065002C000D000A00200020002000200063002E0074006F00740061006C005F0063006F006D00700069006C00650073002C000D000A00200020002000200063002E0070006C0061006E005F0063006F0075006E0074002C000D000A00200020002000200063002E0074006F00740061006C005F0063006F006D00700069006C0065005F006300700075002C000D000A00200020002000200063002E006100760067005F0063006F006D00700069006C0065005F006300700075002C000D000A00200020002000200063002E006D00610078005F0063006F006D00700069006C0065005F006300700075002C000D000A00200020002000200063002E0074006F00740061006C005F0063006F006D00700069006C0065005F006400750072006100740069006F006E002C000D000A00200020002000200063002E006100760067005F0063006F006D00700069006C0065005F006400750072006100740069006F006E002C000D000A00200020002000200063002E006D00610078005F0063006F006D00700069006C0065005F006400750072006100740069006F006E002C000D000A0020002000200020006B002E00710075006500720079005F0070006100720061006D005F0074007900700065002C000D000A0020002000200020006B002E00690073005F006300610063006800650064002C000D000A0020002000200020006B002E00690073005F007200650063006F006D00700069006C00650064002C000D000A0020002000200020006B002E0063006F006D00700069006C0065005F0063006F00640065002C000D000A0020002000200020006B002E006800610073005F006C00690074006500720061006C0073002C000D000A0020002000200020006B002E0070006100720061006D00650074006500720069007A00650064005F00760061006C007500650073005F0063006F0075006E0074000D000A00460052004F004D002000630070007100200041005300200063000D000A00430052004F005300530020004100500050004C0059000D000A0028000D000A002000200020002000530045004C00450043005400200054004F00500020002800310029000D000A00200020002000200020002000200020006B002E002A000D000A002000200020002000460052004F004D0020005B007200650070006C006100630065005F006D0065005D0020004100530020006B000D000A0020002000200020005700480045005200450020006B002E00710075006500720079005F00680061007300680020003D00200063002E00710075006500720079005F0068006100730068000D000A0020002000200020004F00520044004500520020004200590020006B002E0069006400200044004500530043000D000A00290020004100530020006B000D000A004F00520044004500520020004200590020000D000A00200020002000200063002E0074006F00740061006C005F0063006F006D00700069006C0065007300200044004500530043003B00
        WHERE @parameterization_events = 1;
        INSERT #view_check (view_name, view_definition)
        SELECT N'HumanEvents_Queries', 0x430052004500410054004500200056004900450057002000640062006F002E00480075006D0061006E004500760065006E00740073005F0051007500650072006900650073000D000A00410053000D000A0057004900540048000D000A002000200020002000710075006500720079005F006100670067002000410053000D000A0028000D000A002000200020002000530045004C004500430054000D000A002000200020002000200020002000200071002E00710075006500720079005F0070006C0061006E005F0068006100730068005F007300690067006E00650064002C000D000A002000200020002000200020002000200071002E00710075006500720079005F0068006100730068005F007300690067006E00650064002C000D000A002000200020002000200020002000200071002E0070006C0061006E005F00680061006E0064006C0065002C000D000A002000200020002000200020002000200074006F00740061006C005F006300700075005F006D00730020003D002000490053004E0055004C004C00280071002E006300700075005F006D0073002C00200030002E0029002C000D000A002000200020002000200020002000200074006F00740061006C005F006C006F0067006900630061006C005F007200650061006400730020003D002000490053004E0055004C004C00280071002E006C006F0067006900630061006C005F00720065006100640073002C00200030002E0029002C000D000A002000200020002000200020002000200074006F00740061006C005F0070006800790073006900630061006C005F007200650061006400730020003D002000490053004E0055004C004C00280071002E0070006800790073006900630061006C005F00720065006100640073002C00200030002E0029002C000D000A002000200020002000200020002000200074006F00740061006C005F006400750072006100740069006F006E005F006D00730020003D002000490053004E0055004C004C00280071002E006400750072006100740069006F006E005F006D0073002C00200030002E0029002C000D000A002000200020002000200020002000200074006F00740061006C005F007700720069007400650073005F006D00620020003D002000490053004E0055004C004C00280071002E007700720069007400650073005F006D0062002C00200030002E0029002C000D000A002000200020002000200020002000200074006F00740061006C005F007300700069006C006C0073005F006D00620020003D002000490053004E0055004C004C00280071002E007300700069006C006C0073005F006D0062002C00200030002E0029002C000D000A002000200020002000200020002000200074006F00740061006C005F0075007300650064005F006D0065006D006F00720079005F006D00620020003D0020004E0055004C004C002C000D000A002000200020002000200020002000200074006F00740061006C005F006700720061006E007400650064005F006D0065006D006F00720079005F006D00620020003D0020004E0055004C004C002C000D000A002000200020002000200020002000200074006F00740061006C005F0072006F007700730020003D002000490053004E0055004C004C00280071002E0072006F0077005F0063006F0075006E0074002C00200030002E0029002C000D000A00200020002000200020002000200020006100760067005F006300700075005F006D00730020003D002000490053004E0055004C004C00280071002E006300700075005F006D0073002C00200030002E0029002C000D000A00200020002000200020002000200020006100760067005F006C006F0067006900630061006C005F007200650061006400730020003D002000490053004E0055004C004C00280071002E006C006F0067006900630061006C005F00720065006100640073002C00200030002E0029002C000D000A00200020002000200020002000200020006100760067005F0070006800790073006900630061006C005F007200650061006400730020003D002000490053004E0055004C004C00280071002E0070006800790073006900630061006C005F00720065006100640073002C00200030002E0029002C000D000A00200020002000200020002000200020006100760067005F006400750072006100740069006F006E005F006D00730020003D002000490053004E0055004C004C00280071002E006400750072006100740069006F006E005F006D0073002C00200030002E0029002C000D000A00200020002000200020002000200020006100760067005F007700720069007400650073005F006D00620020003D002000490053004E0055004C004C00280071002E007700720069007400650073005F006D0062002C00200030002E0029002C000D000A00200020002000200020002000200020006100760067005F007300700069006C006C0073005F006D00620020003D002000490053004E0055004C004C00280071002E007300700069006C006C0073005F006D0062002C00200030002E0029002C000D000A00200020002000200020002000200020006100760067005F0075007300650064005F006D0065006D006F00720079005F006D00620020003D0020004E0055004C004C002C000D000A00200020002000200020002000200020006100760067005F006700720061006E007400650064005F006D0065006D006F00720079005F006D00620020003D0020004E0055004C004C002C000D000A00200020002000200020002000200020006100760067005F0072006F007700730020003D002000490053004E0055004C004C00280071002E0072006F0077005F0063006F0075006E0074002C002000300029000D000A002000200020002000460052004F004D0020005B007200650070006C006100630065005F006D0065005D00200041005300200071000D000A00200020002000200057004800450052004500200071002E006500760065006E0074005F00740079007000650020003C003E0020004E002700710075006500720079005F0070006F00730074005F0065007800650063007500740069006F006E005F00730068006F00770070006C0061006E0027000D000A0020002000200020000D000A00200020002000200055004E0049004F004E00200041004C004C000D000A0020002000200020000D000A002000200020002000530045004C004500430054000D000A002000200020002000200020002000200071002E00710075006500720079005F0070006C0061006E005F0068006100730068005F007300690067006E00650064002C000D000A002000200020002000200020002000200071002E00710075006500720079005F0068006100730068005F007300690067006E00650064002C000D000A002000200020002000200020002000200071002E0070006C0061006E005F00680061006E0064006C0065002C000D000A00200020002000200020002000200020002F002A0074006F00740061006C0073002A002F000D000A002000200020002000200020002000200074006F00740061006C005F006300700075005F006D00730020003D0020004E0055004C004C002C000D000A002000200020002000200020002000200074006F00740061006C005F006C006F0067006900630061006C005F007200650061006400730020003D0020004E0055004C004C002C000D000A002000200020002000200020002000200074006F00740061006C005F0070006800790073006900630061006C005F007200650061006400730020003D0020004E0055004C004C002C000D000A002000200020002000200020002000200074006F00740061006C005F006400750072006100740069006F006E005F006D00730020003D0020004E0055004C004C002C000D000A002000200020002000200020002000200074006F00740061006C005F0077007200690074006500730020003D0020004E0055004C004C002C000D000A002000200020002000200020002000200074006F00740061006C005F007300700069006C006C0073005F006D00620020003D0020004E0055004C004C002C000D000A002000200020002000200020002000200074006F00740061006C005F0075007300650064005F006D0065006D006F00720079005F006D00620020003D002000490053004E0055004C004C00280071002E0075007300650064005F006D0065006D006F00720079005F006D0062002C00200030002E0029002C000D000A002000200020002000200020002000200074006F00740061006C005F006700720061006E007400650064005F006D0065006D006F00720079005F006D00620020003D002000490053004E0055004C004C00280071002E006700720061006E007400650064005F006D0065006D006F00720079005F006D0062002C00200030002E0029002C000D000A002000200020002000200020002000200074006F00740061006C005F0072006F007700730020003D0020004E0055004C004C002C000D000A00200020002000200020002000200020002F002A00610076006500720061006700650073002A002F000D000A00200020002000200020002000200020006100760067005F006300700075005F006D00730020003D0020004E0055004C004C002C000D000A00200020002000200020002000200020006100760067005F006C006F0067006900630061006C005F007200650061006400730020003D0020004E0055004C004C002C000D000A00200020002000200020002000200020006100760067005F0070006800790073006900630061006C005F007200650061006400730020003D0020004E0055004C004C002C000D000A00200020002000200020002000200020006100760067005F006400750072006100740069006F006E005F006D00730020003D0020004E0055004C004C002C000D000A00200020002000200020002000200020006100760067005F007700720069007400650073005F006D00620020003D0020004E0055004C004C002C000D000A00200020002000200020002000200020006100760067005F007300700069006C006C0073005F006D00620020003D0020004E0055004C004C002C000D000A00200020002000200020002000200020006100760067005F0075007300650064005F006D0065006D006F00720079005F006D00620020003D002000490053004E0055004C004C00280071002E0075007300650064005F006D0065006D006F00720079005F006D0062002C00200030002E0029002C000D000A00200020002000200020002000200020006100760067005F006700720061006E007400650064005F006D0065006D006F00720079005F006D00620020003D002000490053004E0055004C004C00280071002E006700720061006E007400650064005F006D0065006D006F00720079005F006D0062002C00200030002E0029002C000D000A00200020002000200020002000200020006100760067005F0072006F007700730020003D0020004E0055004C004C000D000A002000200020002000460052004F004D0020005B007200650070006C006100630065005F006D0065005D00200041005300200071000D000A00200020002000200057004800450052004500200071002E006500760065006E0074005F00740079007000650020003D0020004E002700710075006500720079005F0070006F00730074005F0065007800650063007500740069006F006E005F00730068006F00770070006C0061006E0027000D000A0029002C000D000A00200020002000200074006F00740061006C0073002000410053000D000A0028000D000A002000200020002000530045004C00450043005400200054004F00500020002800320031003400370034003800330036003400380029000D000A002000200020002000200020002000200071002E00710075006500720079005F0070006C0061006E005F0068006100730068005F007300690067006E00650064002C000D000A002000200020002000200020002000200071002E00710075006500720079005F0068006100730068005F007300690067006E00650064002C000D000A002000200020002000200020002000200071002E0070006C0061006E005F00680061006E0064006C0065002C000D000A002000200020002000200020002000200065007800650063007500740069006F006E00730020003D0020000D000A0020002000200020002000200020002000200020002000200043004F0055004E0054005F0042004900470028002A00290020004F0056004500520020000D000A0020002000200020002000200020002000200020002000200028000D000A00200020002000200020002000200020002000200020002000200020002000200050004100520054004900540049004F004E002000420059000D000A002000200020002000200020002000200020002000200020002000200020002000200020002000200071002E00710075006500720079005F0070006C0061006E005F0068006100730068005F007300690067006E00650064002C000D000A002000200020002000200020002000200020002000200020002000200020002000200020002000200071002E00710075006500720079005F0068006100730068005F007300690067006E00650064002C000D000A002000200020002000200020002000200020002000200020002000200020002000200020002000200071002E0070006C0061006E005F00680061006E0064006C0065000D000A0020002000200020002000200020002000200020002000200029002C000D000A00200020002000200020002000200020002F002A0074006F00740061006C0073002A002F000D000A002000200020002000200020002000200074006F00740061006C005F006300700075005F006D00730020003D002000530055004D002800490053004E0055004C004C00280071002E0074006F00740061006C005F006300700075005F006D0073002C00200030002E00290029002C000D000A002000200020002000200020002000200074006F00740061006C005F006C006F0067006900630061006C005F007200650061006400730020003D002000530055004D002800490053004E0055004C004C00280071002E0074006F00740061006C005F006C006F0067006900630061006C005F00720065006100640073002C00200030002E00290029002C000D000A002000200020002000200020002000200074006F00740061006C005F0070006800790073006900630061006C005F007200650061006400730020003D002000530055004D002800490053004E0055004C004C00280071002E0074006F00740061006C005F0070006800790073006900630061006C005F00720065006100640073002C00200030002E00290029002C000D000A002000200020002000200020002000200074006F00740061006C005F006400750072006100740069006F006E005F006D00730020003D002000530055004D002800490053004E0055004C004C00280071002E0074006F00740061006C005F006400750072006100740069006F006E005F006D0073002C00200030002E00290029002C000D000A002000200020002000200020002000200074006F00740061006C005F0077007200690074006500730020003D002000530055004D002800490053004E0055004C004C00280071002E0074006F00740061006C005F007700720069007400650073005F006D0062002C00200030002E00290029002C000D000A002000200020002000200020002000200074006F00740061006C005F007300700069006C006C0073005F006D00620020003D002000530055004D002800490053004E0055004C004C00280071002E0074006F00740061006C005F007300700069006C006C0073005F006D0062002C00200030002E00290029002C000D000A002000200020002000200020002000200074006F00740061006C005F0075007300650064005F006D0065006D006F00720079005F006D00620020003D002000530055004D002800490053004E0055004C004C00280071002E0074006F00740061006C005F0075007300650064005F006D0065006D006F00720079005F006D0062002C00200030002E00290029002C000D000A002000200020002000200020002000200074006F00740061006C005F006700720061006E007400650064005F006D0065006D006F00720079005F006D00620020003D002000530055004D002800490053004E0055004C004C00280071002E0074006F00740061006C005F006700720061006E007400650064005F006D0065006D006F00720079005F006D0062002C00200030002E00290029002C000D000A002000200020002000200020002000200074006F00740061006C005F0072006F007700730020003D002000530055004D002800490053004E0055004C004C00280071002E0074006F00740061006C005F0072006F00770073002C00200030002E00290029002C000D000A00200020002000200020002000200020002F002A00610076006500720061006700650073002A002F000D000A00200020002000200020002000200020006100760067005F006300700075005F006D00730020003D0020004100560047002800490053004E0055004C004C00280071002E006100760067005F006300700075005F006D0073002C00200030002E00290029002C000D000A00200020002000200020002000200020006100760067005F006C006F0067006900630061006C005F007200650061006400730020003D0020004100560047002800490053004E0055004C004C00280071002E006100760067005F006C006F0067006900630061006C005F00720065006100640073002C00200030002E00290029002C000D000A00200020002000200020002000200020006100760067005F0070006800790073006900630061006C005F007200650061006400730020003D0020004100560047002800490053004E0055004C004C00280071002E006100760067005F0070006800790073006900630061006C005F00720065006100640073002C00200030002E00290029002C000D000A00200020002000200020002000200020006100760067005F006400750072006100740069006F006E005F006D00730020003D0020004100560047002800490053004E0055004C004C00280071002E006100760067005F006400750072006100740069006F006E005F006D0073002C00200030002E00290029002C000D000A00200020002000200020002000200020006100760067005F0077007200690074006500730020003D0020004100560047002800490053004E0055004C004C00280071002E006100760067005F007700720069007400650073005F006D0062002C00200030002E00290029002C000D000A00200020002000200020002000200020006100760067005F007300700069006C006C0073005F006D00620020003D0020004100560047002800490053004E0055004C004C00280071002E006100760067005F007300700069006C006C0073005F006D0062002C00200030002E00290029002C000D000A00200020002000200020002000200020006100760067005F0075007300650064005F006D0065006D006F00720079005F006D00620020003D0020004100560047002800490053004E0055004C004C00280071002E006100760067005F0075007300650064005F006D0065006D006F00720079005F006D0062002C00200030002E00290029002C000D000A00200020002000200020002000200020006100760067005F006700720061006E007400650064005F006D0065006D006F00720079005F006D00620020003D0020004100560047002800490053004E0055004C004C00280071002E006100760067005F006700720061006E007400650064005F006D0065006D006F00720079005F006D0062002C00200030002E00290029002C000D000A00200020002000200020002000200020006100760067005F0072006F007700730020003D0020004100560047002800490053004E0055004C004C00280071002E006100760067005F0072006F00770073002C0020003000290029000D000A002000200020002000460052004F004D002000710075006500720079005F00610067006700200041005300200071000D000A002000200020002000470052004F00550050002000420059000D000A002000200020002000200020002000200071002E00710075006500720079005F0070006C0061006E005F0068006100730068005F007300690067006E00650064002C000D000A002000200020002000200020002000200071002E00710075006500720079005F0068006100730068005F007300690067006E00650064002C000D000A002000200020002000200020002000200071002E0070006C0061006E005F00680061006E0064006C0065000D000A0029002C000D000A002000200020002000710075006500720079005F0072006500730075006C00740073002000410053000D000A0028000D000A002000200020002000530045004C00450043005400200054004F00500020002800320031003400370034003800330036003400380029000D000A002000200020002000200020002000200071002E006500760065006E0074005F00740069006D0065002C000D000A002000200020002000200020002000200071002E00640061007400610062006100730065005F006E0061006D0065002C000D000A002000200020002000200020002000200071002E006F0062006A006500630074005F006E0061006D0065002C000D000A0020002000200020002000200020002000710032002E00730074006100740065006D0065006E0074005F0074006500780074002C000D000A002000200020002000200020002000200071002E00730071006C005F0074006500780074002C000D000A002000200020002000200020002000200071002E00730068006F00770070006C0061006E005F0078006D006C002C000D000A002000200020002000200020002000200074002E0065007800650063007500740069006F006E0073002C000D000A002000200020002000200020002000200074002E0074006F00740061006C005F006300700075005F006D0073002C000D000A002000200020002000200020002000200074002E006100760067005F006300700075005F006D0073002C000D000A002000200020002000200020002000200074002E0074006F00740061006C005F006C006F0067006900630061006C005F00720065006100640073002C000D000A002000200020002000200020002000200074002E006100760067005F006C006F0067006900630061006C005F00720065006100640073002C000D000A002000200020002000200020002000200074002E0074006F00740061006C005F0070006800790073006900630061006C005F00720065006100640073002C000D000A002000200020002000200020002000200074002E006100760067005F0070006800790073006900630061006C005F00720065006100640073002C000D000A002000200020002000200020002000200074002E0074006F00740061006C005F006400750072006100740069006F006E005F006D0073002C000D000A002000200020002000200020002000200074002E006100760067005F006400750072006100740069006F006E005F006D0073002C000D000A002000200020002000200020002000200074002E0074006F00740061006C005F007700720069007400650073002C000D000A002000200020002000200020002000200074002E006100760067005F007700720069007400650073002C000D000A002000200020002000200020002000200074002E0074006F00740061006C005F007300700069006C006C0073005F006D0062002C000D000A002000200020002000200020002000200074002E006100760067005F007300700069006C006C0073005F006D0062002C000D000A002000200020002000200020002000200074002E0074006F00740061006C005F0075007300650064005F006D0065006D006F00720079005F006D0062002C000D000A002000200020002000200020002000200074002E006100760067005F0075007300650064005F006D0065006D006F00720079005F006D0062002C000D000A002000200020002000200020002000200074002E0074006F00740061006C005F006700720061006E007400650064005F006D0065006D006F00720079005F006D0062002C000D000A002000200020002000200020002000200074002E006100760067005F006700720061006E007400650064005F006D0065006D006F00720079005F006D0062002C000D000A002000200020002000200020002000200074002E0074006F00740061006C005F0072006F00770073002C000D000A002000200020002000200020002000200074002E006100760067005F0072006F00770073002C000D000A002000200020002000200020002000200071002E00730065007200690061006C005F0069006400650061006C005F006D0065006D006F00720079005F006D0062002C000D000A002000200020002000200020002000200071002E007200650071007500650073007400650064005F006D0065006D006F00720079005F006D0062002C000D000A002000200020002000200020002000200071002E0069006400650061006C005F006D0065006D006F00720079005F006D0062002C000D000A002000200020002000200020002000200071002E0065007300740069006D0061007400650064005F0072006F00770073002C000D000A002000200020002000200020002000200071002E0064006F0070002C000D000A002000200020002000200020002000200071002E00710075006500720079005F0070006C0061006E005F0068006100730068005F007300690067006E00650064002C000D000A002000200020002000200020002000200071002E00710075006500720079005F0068006100730068005F007300690067006E00650064002C000D000A002000200020002000200020002000200071002E0070006C0061006E005F00680061006E0064006C0065002C000D000A00200020002000200020002000200020006E0020003D00200052004F0057005F004E0055004D004200450052002800290020004F0056004500520020000D000A0020002000200020002000200020002000200020002000200028000D000A00200020002000200020002000200020002000200020002000200020002000200050004100520054004900540049004F004E002000420059000D000A002000200020002000200020002000200020002000200020002000200020002000200020002000200071002E00710075006500720079005F0070006C0061006E005F0068006100730068005F007300690067006E00650064002C000D000A002000200020002000200020002000200020002000200020002000200020002000200020002000200071002E00710075006500720079005F0068006100730068005F007300690067006E00650064002C000D000A002000200020002000200020002000200020002000200020002000200020002000200020002000200071002E0070006C0061006E005F00680061006E0064006C0065000D000A0020002000200020002000200020002000200020002000200020002000200020004F0052004400450052002000420059000D000A002000200020002000200020002000200020002000200020002000200020002000200020002000200071002E00710075006500720079005F0070006C0061006E005F0068006100730068005F007300690067006E00650064002C000D000A002000200020002000200020002000200020002000200020002000200020002000200020002000200071002E00710075006500720079005F0068006100730068005F007300690067006E00650064002C000D000A002000200020002000200020002000200020002000200020002000200020002000200020002000200071002E0070006C0061006E005F00680061006E0064006C0065000D000A0020002000200020002000200020002000200020002000200029000D000A002000200020002000460052004F004D0020005B007200650070006C006100630065005F006D0065005D00200041005300200071000D000A0020002000200020004A004F0049004E00200074006F00740061006C007300200041005300200074000D000A00200020002000200020002000200020004F004E002000200071002E00710075006500720079005F0068006100730068005F007300690067006E006500640020003D00200074002E00710075006500720079005F0068006100730068005F007300690067006E00650064000D000A002000200020002000200020002000200041004E004400200071002E00710075006500720079005F0070006C0061006E005F0068006100730068005F007300690067006E006500640020003D00200074002E00710075006500720079005F0070006C0061006E005F0068006100730068005F007300690067006E00650064000D000A002000200020002000200020002000200041004E004400200071002E0070006C0061006E005F00680061006E0064006C00650020003D00200074002E0070006C0061006E005F00680061006E0064006C0065000D000A002000200020002000430052004F005300530020004100500050004C0059000D000A00200020002000200028000D000A0020002000200020002000200020002000530045004C00450043005400200054004F00500020002800310029000D000A00200020002000200020002000200020002000200020002000730074006100740065006D0065006E0074005F00740065007800740020003D002000710032002E00730074006100740065006D0065006E0074000D000A0020002000200020002000200020002000460052004F004D0020005B007200650070006C006100630065005F006D0065005D002000410053002000710032000D000A002000200020002000200020002000200057004800450052004500200071002E00710075006500720079005F0068006100730068005F007300690067006E006500640020003D002000710032002E00710075006500720079005F0068006100730068005F007300690067006E00650064000D000A002000200020002000200020002000200041004E00440020002000200071002E00710075006500720079005F0070006C0061006E005F0068006100730068005F007300690067006E006500640020003D002000710032002E00710075006500720079005F0070006C0061006E005F0068006100730068005F007300690067006E00650064000D000A002000200020002000200020002000200041004E00440020002000200071002E0070006C0061006E005F00680061006E0064006C00650020003D002000710032002E0070006C0061006E005F00680061006E0064006C0065000D000A002000200020002000200020002000200041004E004400200020002000710032002E00730074006100740065006D0065006E00740020004900530020004E004F00540020004E0055004C004C000D000A00200020002000200020002000200020004F00520044004500520020004200590020000D000A00200020002000200020002000200020002000200020002000710032002E006500760065006E0074005F00740069006D006500200044004500530043000D000A00200020002000200029002000410053002000710032000D000A00200020002000200057004800450052004500200071002E00730068006F00770070006C0061006E005F0078006D006C002E0065007800690073007400280027002A002700290020003D00200031000D000A0029000D000A00530045004C00450043005400200054004F00500020002800320031003400370034003800330036003400380029000D000A00200020002000200071002E006500760065006E0074005F00740069006D0065002C000D000A00200020002000200071002E00640061007400610062006100730065005F006E0061006D0065002C000D000A00200020002000200071002E006F0062006A006500630074005F006E0061006D0065002C000D000A002000200020002000730074006100740065006D0065006E0074005F00740065007800740020003D0020000D000A00200020002000200020002000200020005400520059005F004300410053005400280071002E00730074006100740065006D0065006E0074005F007400650078007400200041005300200078006D006C0029002C000D000A002000200020002000730071006C005F00740065007800740020003D0020000D000A00200020002000200020002000200020005400520059005F004300410053005400280071002E00730071006C005F007400650078007400200041005300200078006D006C0029002C000D000A00200020002000200071002E00730068006F00770070006C0061006E005F0078006D006C002C000D000A00200020002000200071002E0065007800650063007500740069006F006E0073002C000D000A00200020002000200071002E0074006F00740061006C005F006300700075005F006D0073002C000D000A00200020002000200071002E006100760067005F006300700075005F006D0073002C000D000A00200020002000200071002E0074006F00740061006C005F006C006F0067006900630061006C005F00720065006100640073002C000D000A00200020002000200071002E006100760067005F006C006F0067006900630061006C005F00720065006100640073002C000D000A00200020002000200071002E0074006F00740061006C005F0070006800790073006900630061006C005F00720065006100640073002C000D000A00200020002000200071002E006100760067005F0070006800790073006900630061006C005F00720065006100640073002C000D000A00200020002000200071002E0074006F00740061006C005F006400750072006100740069006F006E005F006D0073002C000D000A00200020002000200071002E006100760067005F006400750072006100740069006F006E005F006D0073002C000D000A00200020002000200071002E0074006F00740061006C005F007700720069007400650073002C000D000A00200020002000200071002E006100760067005F007700720069007400650073002C000D000A00200020002000200071002E0074006F00740061006C005F007300700069006C006C0073005F006D0062002C000D000A00200020002000200071002E006100760067005F007300700069006C006C0073005F006D0062002C000D000A00200020002000200071002E0074006F00740061006C005F0075007300650064005F006D0065006D006F00720079005F006D0062002C000D000A00200020002000200071002E006100760067005F0075007300650064005F006D0065006D006F00720079005F006D0062002C000D000A00200020002000200071002E0074006F00740061006C005F006700720061006E007400650064005F006D0065006D006F00720079005F006D0062002C000D000A00200020002000200071002E006100760067005F006700720061006E007400650064005F006D0065006D006F00720079005F006D0062002C000D000A00200020002000200071002E0074006F00740061006C005F0072006F00770073002C000D000A00200020002000200071002E006100760067005F0072006F00770073002C000D000A00200020002000200071002E00730065007200690061006C005F0069006400650061006C005F006D0065006D006F00720079005F006D0062002C000D000A00200020002000200071002E007200650071007500650073007400650064005F006D0065006D006F00720079005F006D0062002C000D000A00200020002000200071002E0069006400650061006C005F006D0065006D006F00720079005F006D0062002C000D000A00200020002000200071002E0065007300740069006D0061007400650064005F0072006F00770073002C000D000A00200020002000200071002E0064006F0070002C000D000A00200020002000200071002E00710075006500720079005F0070006C0061006E005F0068006100730068005F007300690067006E00650064002C000D000A00200020002000200071002E00710075006500720079005F0068006100730068005F007300690067006E00650064002C000D000A00200020002000200071002E0070006C0061006E005F00680061006E0064006C0065000D000A00460052004F004D002000710075006500720079005F0072006500730075006C0074007300200041005300200071000D000A0057004800450052004500200071002E006E0020003D00200031003B00
        WHERE @skip_plans = 0;
        INSERT #view_check (view_name, view_definition)
        SELECT N'HumanEvents_Queries', 0x430052004500410054004500200056004900450057002000640062006F002E00480075006D0061006E004500760065006E00740073005F0051007500650072006900650073005F006E0070000D000A00410053000D000A0057004900540048000D000A002000200020002000710075006500720079005F006100670067002000410053000D000A0028000D000A002000200020002000530045004C004500430054000D000A002000200020002000200020002000200071002E00710075006500720079005F0070006C0061006E005F0068006100730068005F007300690067006E00650064002C000D000A002000200020002000200020002000200071002E00710075006500720079005F0068006100730068005F007300690067006E00650064002C000D000A002000200020002000200020002000200071002E0070006C0061006E005F00680061006E0064006C0065002C000D000A002000200020002000200020002000200074006F00740061006C005F006300700075005F006D00730020003D002000490053004E0055004C004C00280071002E006300700075005F006D0073002C00200030002E0029002C000D000A002000200020002000200020002000200074006F00740061006C005F006C006F0067006900630061006C005F007200650061006400730020003D002000490053004E0055004C004C00280071002E006C006F0067006900630061006C005F00720065006100640073002C00200030002E0029002C000D000A002000200020002000200020002000200074006F00740061006C005F0070006800790073006900630061006C005F007200650061006400730020003D002000490053004E0055004C004C00280071002E0070006800790073006900630061006C005F00720065006100640073002C00200030002E0029002C000D000A002000200020002000200020002000200074006F00740061006C005F006400750072006100740069006F006E005F006D00730020003D002000490053004E0055004C004C00280071002E006400750072006100740069006F006E005F006D0073002C00200030002E0029002C000D000A002000200020002000200020002000200074006F00740061006C005F007700720069007400650073005F006D00620020003D002000490053004E0055004C004C00280071002E007700720069007400650073005F006D0062002C00200030002E0029002C000D000A002000200020002000200020002000200074006F00740061006C005F007300700069006C006C0073005F006D00620020003D002000490053004E0055004C004C00280071002E007300700069006C006C0073005F006D0062002C00200030002E0029002C000D000A002000200020002000200020002000200074006F00740061006C005F0075007300650064005F006D0065006D006F00720079005F006D00620020003D0020004E0055004C004C002C000D000A002000200020002000200020002000200074006F00740061006C005F006700720061006E007400650064005F006D0065006D006F00720079005F006D00620020003D0020004E0055004C004C002C000D000A002000200020002000200020002000200074006F00740061006C005F0072006F007700730020003D002000490053004E0055004C004C00280071002E0072006F0077005F0063006F0075006E0074002C00200030002E0029002C000D000A00200020002000200020002000200020006100760067005F006300700075005F006D00730020003D002000490053004E0055004C004C00280071002E006300700075005F006D0073002C00200030002E0029002C000D000A00200020002000200020002000200020006100760067005F006C006F0067006900630061006C005F007200650061006400730020003D002000490053004E0055004C004C00280071002E006C006F0067006900630061006C005F00720065006100640073002C00200030002E0029002C000D000A00200020002000200020002000200020006100760067005F0070006800790073006900630061006C005F007200650061006400730020003D002000490053004E0055004C004C00280071002E0070006800790073006900630061006C005F00720065006100640073002C00200030002E0029002C000D000A00200020002000200020002000200020006100760067005F006400750072006100740069006F006E005F006D00730020003D002000490053004E0055004C004C00280071002E006400750072006100740069006F006E005F006D0073002C00200030002E0029002C000D000A00200020002000200020002000200020006100760067005F007700720069007400650073005F006D00620020003D002000490053004E0055004C004C00280071002E007700720069007400650073005F006D0062002C00200030002E0029002C000D000A00200020002000200020002000200020006100760067005F007300700069006C006C0073005F006D00620020003D002000490053004E0055004C004C00280071002E007300700069006C006C0073005F006D0062002C00200030002E0029002C000D000A00200020002000200020002000200020006100760067005F0075007300650064005F006D0065006D006F00720079005F006D00620020003D0020004E0055004C004C002C000D000A00200020002000200020002000200020006100760067005F006700720061006E007400650064005F006D0065006D006F00720079005F006D00620020003D0020004E0055004C004C002C000D000A00200020002000200020002000200020006100760067005F0072006F007700730020003D002000490053004E0055004C004C00280071002E0072006F0077005F0063006F0075006E0074002C002000300029000D000A002000200020002000460052004F004D0020005B007200650070006C006100630065005F006D0065005D00200041005300200071000D000A00200020002000200057004800450052004500200071002E006500760065006E0074005F00740079007000650020003C003E0020004E002700710075006500720079005F0070006F00730074005F0065007800650063007500740069006F006E005F00730068006F00770070006C0061006E0027000D000A0029002C000D000A00200020002000200074006F00740061006C0073002000410053000D000A0028000D000A002000200020002000530045004C00450043005400200054004F00500020002800320031003400370034003800330036003400380029000D000A002000200020002000200020002000200071002E00710075006500720079005F0070006C0061006E005F0068006100730068005F007300690067006E00650064002C000D000A002000200020002000200020002000200071002E00710075006500720079005F0068006100730068005F007300690067006E00650064002C000D000A002000200020002000200020002000200071002E0070006C0061006E005F00680061006E0064006C0065002C000D000A002000200020002000200020002000200065007800650063007500740069006F006E00730020003D0020000D000A0020002000200020002000200020002000200020002000200043004F0055004E0054005F0042004900470028002A00290020004F0056004500520020000D000A0020002000200020002000200020002000200020002000200028000D000A00200020002000200020002000200020002000200020002000200020002000200050004100520054004900540049004F004E002000420059000D000A002000200020002000200020002000200020002000200020002000200020002000200020002000200071002E00710075006500720079005F0070006C0061006E005F0068006100730068005F007300690067006E00650064002C000D000A002000200020002000200020002000200020002000200020002000200020002000200020002000200071002E00710075006500720079005F0068006100730068005F007300690067006E00650064002C000D000A002000200020002000200020002000200020002000200020002000200020002000200020002000200071002E0070006C0061006E005F00680061006E0064006C0065000D000A0020002000200020002000200020002000200020002000200029002C000D000A00200020002000200020002000200020002F002A0074006F00740061006C0073002A002F000D000A002000200020002000200020002000200074006F00740061006C005F006300700075005F006D00730020003D002000530055004D002800490053004E0055004C004C00280071002E0074006F00740061006C005F006300700075005F006D0073002C00200030002E00290029002C000D000A002000200020002000200020002000200074006F00740061006C005F006C006F0067006900630061006C005F007200650061006400730020003D002000530055004D002800490053004E0055004C004C00280071002E0074006F00740061006C005F006C006F0067006900630061006C005F00720065006100640073002C00200030002E00290029002C000D000A002000200020002000200020002000200074006F00740061006C005F0070006800790073006900630061006C005F007200650061006400730020003D002000530055004D002800490053004E0055004C004C00280071002E0074006F00740061006C005F0070006800790073006900630061006C005F00720065006100640073002C00200030002E00290029002C000D000A002000200020002000200020002000200074006F00740061006C005F006400750072006100740069006F006E005F006D00730020003D002000530055004D002800490053004E0055004C004C00280071002E0074006F00740061006C005F006400750072006100740069006F006E005F006D0073002C00200030002E00290029002C000D000A002000200020002000200020002000200074006F00740061006C005F0077007200690074006500730020003D002000530055004D002800490053004E0055004C004C00280071002E0074006F00740061006C005F007700720069007400650073005F006D0062002C00200030002E00290029002C000D000A002000200020002000200020002000200074006F00740061006C005F007300700069006C006C0073005F006D00620020003D002000530055004D002800490053004E0055004C004C00280071002E0074006F00740061006C005F007300700069006C006C0073005F006D0062002C00200030002E00290029002C000D000A002000200020002000200020002000200074006F00740061006C005F0075007300650064005F006D0065006D006F00720079005F006D00620020003D002000530055004D002800490053004E0055004C004C00280071002E0074006F00740061006C005F0075007300650064005F006D0065006D006F00720079005F006D0062002C00200030002E00290029002C000D000A002000200020002000200020002000200074006F00740061006C005F006700720061006E007400650064005F006D0065006D006F00720079005F006D00620020003D002000530055004D002800490053004E0055004C004C00280071002E0074006F00740061006C005F006700720061006E007400650064005F006D0065006D006F00720079005F006D0062002C00200030002E00290029002C000D000A002000200020002000200020002000200074006F00740061006C005F0072006F007700730020003D002000530055004D002800490053004E0055004C004C00280071002E0074006F00740061006C005F0072006F00770073002C00200030002E00290029002C000D000A00200020002000200020002000200020002F002A00610076006500720061006700650073002A002F000D000A00200020002000200020002000200020006100760067005F006300700075005F006D00730020003D0020004100560047002800490053004E0055004C004C00280071002E006100760067005F006300700075005F006D0073002C00200030002E00290029002C000D000A00200020002000200020002000200020006100760067005F006C006F0067006900630061006C005F007200650061006400730020003D0020004100560047002800490053004E0055004C004C00280071002E006100760067005F006C006F0067006900630061006C005F00720065006100640073002C00200030002E00290029002C000D000A00200020002000200020002000200020006100760067005F0070006800790073006900630061006C005F007200650061006400730020003D0020004100560047002800490053004E0055004C004C00280071002E006100760067005F0070006800790073006900630061006C005F00720065006100640073002C00200030002E00290029002C000D000A00200020002000200020002000200020006100760067005F006400750072006100740069006F006E005F006D00730020003D0020004100560047002800490053004E0055004C004C00280071002E006100760067005F006400750072006100740069006F006E005F006D0073002C00200030002E00290029002C000D000A00200020002000200020002000200020006100760067005F0077007200690074006500730020003D0020004100560047002800490053004E0055004C004C00280071002E006100760067005F007700720069007400650073005F006D0062002C00200030002E00290029002C000D000A00200020002000200020002000200020006100760067005F007300700069006C006C0073005F006D00620020003D0020004100560047002800490053004E0055004C004C00280071002E006100760067005F007300700069006C006C0073005F006D0062002C00200030002E00290029002C000D000A00200020002000200020002000200020006100760067005F0075007300650064005F006D0065006D006F00720079005F006D00620020003D0020004100560047002800490053004E0055004C004C00280071002E006100760067005F0075007300650064005F006D0065006D006F00720079005F006D0062002C00200030002E00290029002C000D000A00200020002000200020002000200020006100760067005F006700720061006E007400650064005F006D0065006D006F00720079005F006D00620020003D0020004100560047002800490053004E0055004C004C00280071002E006100760067005F006700720061006E007400650064005F006D0065006D006F00720079005F006D0062002C00200030002E00290029002C000D000A00200020002000200020002000200020006100760067005F0072006F007700730020003D0020004100560047002800490053004E0055004C004C00280071002E006100760067005F0072006F00770073002C0020003000290029000D000A002000200020002000460052004F004D002000710075006500720079005F00610067006700200041005300200071000D000A002000200020002000470052004F00550050002000420059000D000A002000200020002000200020002000200071002E00710075006500720079005F0070006C0061006E005F0068006100730068005F007300690067006E00650064002C000D000A002000200020002000200020002000200071002E00710075006500720079005F0068006100730068005F007300690067006E00650064002C000D000A002000200020002000200020002000200071002E0070006C0061006E005F00680061006E0064006C0065000D000A0029002C000D000A002000200020002000710075006500720079005F0072006500730075006C00740073002000410053000D000A0028000D000A002000200020002000530045004C00450043005400200054004F00500020002800320031003400370034003800330036003400380029000D000A002000200020002000200020002000200071002E006500760065006E0074005F00740069006D0065002C000D000A002000200020002000200020002000200071002E00640061007400610062006100730065005F006E0061006D0065002C000D000A002000200020002000200020002000200071002E006F0062006A006500630074005F006E0061006D0065002C000D000A0020002000200020002000200020002000710032002E00730074006100740065006D0065006E0074005F0074006500780074002C000D000A002000200020002000200020002000200071002E00730071006C005F0074006500780074002C000D000A002000200020002000200020002000200071002E00730068006F00770070006C0061006E005F0078006D006C002C000D000A002000200020002000200020002000200074002E0065007800650063007500740069006F006E0073002C000D000A002000200020002000200020002000200074002E0074006F00740061006C005F006300700075005F006D0073002C000D000A002000200020002000200020002000200074002E006100760067005F006300700075005F006D0073002C000D000A002000200020002000200020002000200074002E0074006F00740061006C005F006C006F0067006900630061006C005F00720065006100640073002C000D000A002000200020002000200020002000200074002E006100760067005F006C006F0067006900630061006C005F00720065006100640073002C000D000A002000200020002000200020002000200074002E0074006F00740061006C005F0070006800790073006900630061006C005F00720065006100640073002C000D000A002000200020002000200020002000200074002E006100760067005F0070006800790073006900630061006C005F00720065006100640073002C000D000A002000200020002000200020002000200074002E0074006F00740061006C005F006400750072006100740069006F006E005F006D0073002C000D000A002000200020002000200020002000200074002E006100760067005F006400750072006100740069006F006E005F006D0073002C000D000A002000200020002000200020002000200074002E0074006F00740061006C005F007700720069007400650073002C000D000A002000200020002000200020002000200074002E006100760067005F007700720069007400650073002C000D000A002000200020002000200020002000200074002E0074006F00740061006C005F007300700069006C006C0073005F006D0062002C000D000A002000200020002000200020002000200074002E006100760067005F007300700069006C006C0073005F006D0062002C000D000A002000200020002000200020002000200074002E0074006F00740061006C005F0075007300650064005F006D0065006D006F00720079005F006D0062002C000D000A002000200020002000200020002000200074002E006100760067005F0075007300650064005F006D0065006D006F00720079005F006D0062002C000D000A002000200020002000200020002000200074002E0074006F00740061006C005F006700720061006E007400650064005F006D0065006D006F00720079005F006D0062002C000D000A002000200020002000200020002000200074002E006100760067005F006700720061006E007400650064005F006D0065006D006F00720079005F006D0062002C000D000A002000200020002000200020002000200074002E0074006F00740061006C005F0072006F00770073002C000D000A002000200020002000200020002000200074002E006100760067005F0072006F00770073002C000D000A002000200020002000200020002000200071002E00730065007200690061006C005F0069006400650061006C005F006D0065006D006F00720079005F006D0062002C000D000A002000200020002000200020002000200071002E007200650071007500650073007400650064005F006D0065006D006F00720079005F006D0062002C000D000A002000200020002000200020002000200071002E0069006400650061006C005F006D0065006D006F00720079005F006D0062002C000D000A002000200020002000200020002000200071002E0065007300740069006D0061007400650064005F0072006F00770073002C000D000A002000200020002000200020002000200071002E0064006F0070002C000D000A002000200020002000200020002000200071002E00710075006500720079005F0070006C0061006E005F0068006100730068005F007300690067006E00650064002C000D000A002000200020002000200020002000200071002E00710075006500720079005F0068006100730068005F007300690067006E00650064002C000D000A002000200020002000200020002000200071002E0070006C0061006E005F00680061006E0064006C0065002C000D000A00200020002000200020002000200020006E0020003D00200052004F0057005F004E0055004D004200450052002800290020004F0056004500520020000D000A0020002000200020002000200020002000200020002000200028000D000A00200020002000200020002000200020002000200020002000200020002000200050004100520054004900540049004F004E002000420059000D000A002000200020002000200020002000200020002000200020002000200020002000200020002000200071002E00710075006500720079005F0070006C0061006E005F0068006100730068005F007300690067006E00650064002C000D000A002000200020002000200020002000200020002000200020002000200020002000200020002000200071002E00710075006500720079005F0068006100730068005F007300690067006E00650064002C000D000A002000200020002000200020002000200020002000200020002000200020002000200020002000200071002E0070006C0061006E005F00680061006E0064006C0065000D000A0020002000200020002000200020002000200020002000200020002000200020004F0052004400450052002000420059000D000A002000200020002000200020002000200020002000200020002000200020002000200020002000200071002E00710075006500720079005F0070006C0061006E005F0068006100730068005F007300690067006E00650064002C000D000A002000200020002000200020002000200020002000200020002000200020002000200020002000200071002E00710075006500720079005F0068006100730068005F007300690067006E00650064002C000D000A002000200020002000200020002000200020002000200020002000200020002000200020002000200071002E0070006C0061006E005F00680061006E0064006C0065000D000A0020002000200020002000200020002000200020002000200029000D000A002000200020002000460052004F004D0020005B007200650070006C006100630065005F006D0065005D00200041005300200071000D000A0020002000200020004A004F0049004E00200074006F00740061006C007300200041005300200074000D000A002000200020002000200020004F004E002000200071002E00710075006500720079005F0068006100730068005F007300690067006E006500640020003D00200074002E00710075006500720079005F0068006100730068005F007300690067006E00650064000D000A0020002000200020002000200041004E004400200071002E00710075006500720079005F0070006C0061006E005F0068006100730068005F007300690067006E006500640020003D00200074002E00710075006500720079005F0070006C0061006E005F0068006100730068005F007300690067006E00650064000D000A0020002000200020004F00550054004500520020004100500050004C0059000D000A00200020002000200028000D000A0020002000200020002000200020002000530045004C00450043005400200054004F00500020002800310029000D000A00200020002000200020002000200020002000200020002000730074006100740065006D0065006E0074005F00740065007800740020003D002000710032002E00730074006100740065006D0065006E0074000D000A0020002000200020002000200020002000460052004F004D0020005B007200650070006C006100630065005F006D0065005D002000410053002000710032000D000A002000200020002000200020002000200057004800450052004500200071002E00710075006500720079005F0068006100730068005F007300690067006E006500640020003D002000710032002E00710075006500720079005F0068006100730068005F007300690067006E00650064000D000A002000200020002000200020002000200041004E00440020002000200071002E00710075006500720079005F0070006C0061006E005F0068006100730068005F007300690067006E006500640020003D002000710032002E00710075006500720079005F0070006C0061006E005F0068006100730068005F007300690067006E00650064000D000A002000200020002000200020002000200041004E004400200020002000710032002E00730074006100740065006D0065006E00740020004900530020004E004F00540020004E0055004C004C000D000A00200020002000200020002000200020004F00520044004500520020004200590020000D000A00200020002000200020002000200020002000200020002000710032002E006500760065006E0074005F00740069006D006500200044004500530043000D000A00200020002000200029002000410053002000710032000D000A0029000D000A00530045004C00450043005400200054004F00500020002800320031003400370034003800330036003400380029000D000A00200020002000200071002E006500760065006E0074005F00740069006D0065002C000D000A00200020002000200071002E00640061007400610062006100730065005F006E0061006D0065002C000D000A002000200020002000730074006100740065006D0065006E0074005F00740065007800740020003D0020000D000A00200020002000200020002000200020005400520059005F004300410053005400280071002E00730074006100740065006D0065006E0074005F007400650078007400200041005300200078006D006C0029002C000D000A002000200020002000730071006C005F00740065007800740020003D0020000D000A00200020002000200020002000200020005400520059005F004300410053005400280071002E00730071006C005F007400650078007400200041005300200078006D006C0029002C000D000A00200020002000200071002E0065007800650063007500740069006F006E0073002C000D000A00200020002000200071002E0074006F00740061006C005F006300700075005F006D0073002C000D000A00200020002000200071002E006100760067005F006300700075005F006D0073002C000D000A00200020002000200071002E0074006F00740061006C005F006C006F0067006900630061006C005F00720065006100640073002C000D000A00200020002000200071002E006100760067005F006C006F0067006900630061006C005F00720065006100640073002C000D000A00200020002000200071002E0074006F00740061006C005F0070006800790073006900630061006C005F00720065006100640073002C000D000A00200020002000200071002E006100760067005F0070006800790073006900630061006C005F00720065006100640073002C000D000A00200020002000200071002E0074006F00740061006C005F006400750072006100740069006F006E005F006D0073002C000D000A00200020002000200071002E006100760067005F006400750072006100740069006F006E005F006D0073002C000D000A00200020002000200071002E0074006F00740061006C005F007700720069007400650073002C000D000A00200020002000200071002E006100760067005F007700720069007400650073002C000D000A00200020002000200071002E0074006F00740061006C005F007300700069006C006C0073005F006D0062002C000D000A00200020002000200071002E006100760067005F007300700069006C006C0073005F006D0062002C000D000A00200020002000200071002E0074006F00740061006C005F0075007300650064005F006D0065006D006F00720079005F006D0062002C000D000A00200020002000200071002E006100760067005F0075007300650064005F006D0065006D006F00720079005F006D0062002C000D000A00200020002000200071002E0074006F00740061006C005F006700720061006E007400650064005F006D0065006D006F00720079005F006D0062002C000D000A00200020002000200071002E006100760067005F006700720061006E007400650064005F006D0065006D006F00720079005F006D0062002C000D000A00200020002000200071002E0074006F00740061006C005F0072006F00770073002C000D000A00200020002000200071002E006100760067005F0072006F00770073002C000D000A00200020002000200071002E00710075006500720079005F0070006C0061006E005F0068006100730068005F007300690067006E00650064002C000D000A00200020002000200071002E00710075006500720079005F0068006100730068005F007300690067006E00650064002C000D000A00200020002000200071002E0070006C0061006E005F00680061006E0064006C0065000D000A00460052004F004D002000710075006500720079005F0072006500730075006C0074007300200041005300200071000D000A0057004800450052004500200071002E006E0020003D00200031003B00
        WHERE @skip_plans = 1;
        INSERT #view_check (view_name, view_definition)
        SELECT N'HumanEvents_RecompilesByDatabaseAndObject', 0x430052004500410054004500200056004900450057002000640062006F002E00480075006D0061006E004500760065006E00740073005F005200650063006F006D00700069006C0065007300420079004400610074006100620061007300650041006E0064004F0062006A006500630074000D000A00410053000D000A00530045004C00450043005400200054004F00500020002800320031003400370034003800330036003400380029000D000A0020002000200020006D0069006E005F006500760065006E0074005F00740069006D00650020003D0020004D0049004E0028006500760065006E0074005F00740069006D00650029002C000D000A0020002000200020006D00610078005F006500760065006E0074005F00740069006D00650020003D0020004D004100580028006500760065006E0074005F00740069006D00650029002C000D000A002000200020002000640061007400610062006100730065005F006E0061006D0065002C000D000A0020002000200020006F0062006A006500630074005F006E0061006D00650020003D0020000D000A002000200020002000200020002000200043004100530045000D000A002000200020002000200020002000200020002000200020005700480045004E0020006F0062006A006500630074005F006E0061006D00650020003D0020004E00270027000D000A002000200020002000200020002000200020002000200020005400480045004E0020004E0027004E002F00410027000D000A0020002000200020002000200020002000200020002000200045004C005300450020006F0062006A006500630074005F006E0061006D0065000D000A002000200020002000200020002000200045004E0044002C000D000A00200020002000200074006F00740061006C005F0063006F006D00700069006C006500730020003D00200043004F0055004E0054005F0042004900470028002A0029002C000D000A00200020002000200074006F00740061006C005F0063006F006D00700069006C0065005F0063007000750020003D002000530055004D00280063006F006D00700069006C0065005F006300700075005F006D00730029002C000D000A0020002000200020006100760067005F0063006F006D00700069006C0065005F0063007000750020003D002000410056004700280063006F006D00700069006C0065005F006300700075005F006D00730029002C000D000A0020002000200020006D00610078005F0063006F006D00700069006C0065005F0063007000750020003D0020004D0041005800280063006F006D00700069006C0065005F006300700075005F006D00730029002C000D000A00200020002000200074006F00740061006C005F0063006F006D00700069006C0065005F006400750072006100740069006F006E0020003D002000530055004D00280063006F006D00700069006C0065005F006400750072006100740069006F006E005F006D00730029002C000D000A0020002000200020006100760067005F0063006F006D00700069006C0065005F006400750072006100740069006F006E0020003D002000410056004700280063006F006D00700069006C0065005F006400750072006100740069006F006E005F006D00730029002C000D000A0020002000200020006D00610078005F0063006F006D00700069006C0065005F006400750072006100740069006F006E0020003D0020004D0041005800280063006F006D00700069006C0065005F006400750072006100740069006F006E005F006D00730029000D000A00460052004F004D0020005B007200650070006C006100630065005F006D0065005D000D000A00470052004F00550050002000420059000D000A002000200020002000640061007400610062006100730065005F006E0061006D0065002C000D000A0020002000200020006F0062006A006500630074005F006E0061006D0065000D000A004F005200440045005200200042005900200074006F00740061006C005F0063006F006D00700069006C0065007300200044004500530043003B00
        WHERE @compile_events = 1;
        INSERT #view_check (view_name, view_definition)
        SELECT N'HumanEvents_RecompilesByDuration', 0x430052004500410054004500200056004900450057002000640062006F002E00480075006D0061006E004500760065006E00740073005F005200650063006F006D00700069006C0065007300420079004400750072006100740069006F006E000D000A00410053000D000A0057004900540048000D000A0020002000200020006300620071002000410053000D000A0028000D000A002000200020002000530045004C004500430054000D000A0020002000200020002000200020002000730074006100740065006D0065006E0074005F0074006500780074005F0063006800650063006B00730075006D002C000D000A002000200020002000200020002000200074006F00740061006C005F0063006F006D00700069006C006500730020003D00200043004F0055004E0054005F0042004900470028002A0029002C000D000A002000200020002000200020002000200074006F00740061006C005F0063006F006D00700069006C0065005F0063007000750020003D002000530055004D00280063006F006D00700069006C0065005F006300700075005F006D00730029002C000D000A00200020002000200020002000200020006100760067005F0063006F006D00700069006C0065005F0063007000750020003D002000410056004700280063006F006D00700069006C0065005F006300700075005F006D00730029002C000D000A00200020002000200020002000200020006D00610078005F0063006F006D00700069006C0065005F0063007000750020003D0020004D0041005800280063006F006D00700069006C0065005F006300700075005F006D00730029002C000D000A002000200020002000200020002000200074006F00740061006C005F0063006F006D00700069006C0065005F006400750072006100740069006F006E0020003D002000530055004D00280063006F006D00700069006C0065005F006400750072006100740069006F006E005F006D00730029002C000D000A00200020002000200020002000200020006100760067005F0063006F006D00700069006C0065005F006400750072006100740069006F006E0020003D002000410056004700280063006F006D00700069006C0065005F006400750072006100740069006F006E005F006D00730029002C000D000A00200020002000200020002000200020006D00610078005F0063006F006D00700069006C0065005F006400750072006100740069006F006E0020003D0020004D0041005800280063006F006D00700069006C0065005F006400750072006100740069006F006E005F006D00730029000D000A002000200020002000460052004F004D0020005B007200650070006C006100630065005F006D0065005D000D000A002000200020002000470052004F005500500020004200590020000D000A0020002000200020002000200020002000730074006100740065006D0065006E0074005F0074006500780074005F0063006800650063006B00730075006D000D000A00200020002000200048004100560049004E00470020000D000A0020002000200020002000200020002000410056004700280063006F006D00700069006C0065005F006400750072006100740069006F006E005F006D007300290020003E00200031003000300030000D000A0029000D000A00530045004C00450043005400200054004F00500020002800320031003400370034003800330036003400380029000D000A0020002000200020006B002E006F0062006A006500630074005F006E0061006D0065002C000D000A0020002000200020006B002E00730074006100740065006D0065006E0074005F0074006500780074002C000D000A00200020002000200063002E0074006F00740061006C005F0063006F006D00700069006C00650073002C000D000A00200020002000200063002E0074006F00740061006C005F0063006F006D00700069006C0065005F006300700075002C000D000A00200020002000200063002E006100760067005F0063006F006D00700069006C0065005F006300700075002C000D000A00200020002000200063002E006D00610078005F0063006F006D00700069006C0065005F006300700075002C000D000A00200020002000200063002E0074006F00740061006C005F0063006F006D00700069006C0065005F006400750072006100740069006F006E002C000D000A00200020002000200063002E006100760067005F0063006F006D00700069006C0065005F006400750072006100740069006F006E002C000D000A00200020002000200063002E006D00610078005F0063006F006D00700069006C0065005F006400750072006100740069006F006E000D000A00460052004F004D002000630062007100200041005300200063000D000A00430052004F005300530020004100500050004C0059000D000A0028000D000A002000200020002000530045004C00450043005400200054004F00500020002800310029000D000A00200020002000200020002000200020006B002E002A000D000A002000200020002000460052004F004D0020005B007200650070006C006100630065005F006D0065005D0020004100530020006B000D000A00200020002000200057004800450052004500200063002E00730074006100740065006D0065006E0074005F0074006500780074005F0063006800650063006B00730075006D0020003D0020006B002E00730074006100740065006D0065006E0074005F0074006500780074005F0063006800650063006B00730075006D000D000A0020002000200020004F00520044004500520020004200590020006B002E0069006400200044004500530043000D000A00290020004100530020006B000D000A004F00520044004500520020004200590020000D000A00200020002000200063002E006100760067005F0063006F006D00700069006C0065005F006400750072006100740069006F006E00200044004500530043003B00
        WHERE @compile_events = 1;
        INSERT #view_check (view_name, view_definition)
        SELECT N'HumanEvents_RecompilesByQuery', 0x430052004500410054004500200056004900450057002000640062006F002E00480075006D0061006E004500760065006E00740073005F005200650063006F006D00700069006C006500730042007900510075006500720079000D000A00410053000D000A0057004900540048000D000A0020002000200020006300620071002000410053000D000A0028000D000A002000200020002000530045004C004500430054000D000A0020002000200020002000200020002000730074006100740065006D0065006E0074005F0074006500780074005F0063006800650063006B00730075006D002C000D000A002000200020002000200020002000200074006F00740061006C005F007200650063006F006D00700069006C006500730020003D00200043004F0055004E0054005F0042004900470028002A0029002C000D000A002000200020002000200020002000200074006F00740061006C005F0063006F006D00700069006C0065005F0063007000750020003D002000530055004D00280063006F006D00700069006C0065005F006300700075005F006D00730029002C000D000A00200020002000200020002000200020006100760067005F0063006F006D00700069006C0065005F0063007000750020003D002000410056004700280063006F006D00700069006C0065005F006300700075005F006D00730029002C000D000A00200020002000200020002000200020006D00610078005F0063006F006D00700069006C0065005F0063007000750020003D0020004D0041005800280063006F006D00700069006C0065005F006300700075005F006D00730029002C000D000A002000200020002000200020002000200074006F00740061006C005F0063006F006D00700069006C0065005F006400750072006100740069006F006E0020003D002000530055004D00280063006F006D00700069006C0065005F006400750072006100740069006F006E005F006D00730029002C000D000A00200020002000200020002000200020006100760067005F0063006F006D00700069006C0065005F006400750072006100740069006F006E0020003D002000410056004700280063006F006D00700069006C0065005F006400750072006100740069006F006E005F006D00730029002C000D000A00200020002000200020002000200020006D00610078005F0063006F006D00700069006C0065005F006400750072006100740069006F006E0020003D0020004D0041005800280063006F006D00700069006C0065005F006400750072006100740069006F006E005F006D00730029000D000A002000200020002000460052004F004D0020005B007200650070006C006100630065005F006D0065005D000D000A002000200020002000470052004F005500500020004200590020000D000A0020002000200020002000200020002000730074006100740065006D0065006E0074005F0074006500780074005F0063006800650063006B00730075006D000D000A00200020002000200048004100560049004E00470020000D000A002000200020002000200020002000200043004F0055004E0054005F0042004900470028002A00290020003E003D002000310030000D000A0029000D000A00530045004C00450043005400200054004F00500020002800320031003400370034003800330036003400380029000D000A0020002000200020006B002E006F0062006A006500630074005F006E0061006D0065002C000D000A0020002000200020006B002E00730074006100740065006D0065006E0074005F0074006500780074002C000D000A00200020002000200063002E0074006F00740061006C005F007200650063006F006D00700069006C00650073002C000D000A00200020002000200063002E0074006F00740061006C005F0063006F006D00700069006C0065005F006300700075002C000D000A00200020002000200063002E006100760067005F0063006F006D00700069006C0065005F006300700075002C000D000A00200020002000200063002E006D00610078005F0063006F006D00700069006C0065005F006300700075002C000D000A00200020002000200063002E0074006F00740061006C005F0063006F006D00700069006C0065005F006400750072006100740069006F006E002C000D000A00200020002000200063002E006100760067005F0063006F006D00700069006C0065005F006400750072006100740069006F006E002C000D000A00200020002000200063002E006D00610078005F0063006F006D00700069006C0065005F006400750072006100740069006F006E000D000A00460052004F004D002000630062007100200041005300200063000D000A00430052004F005300530020004100500050004C0059000D000A0028000D000A002000200020002000530045004C00450043005400200054004F00500020002800310029000D000A00200020002000200020002000200020006B002E002A000D000A002000200020002000460052004F004D0020005B007200650070006C006100630065005F006D0065005D0020004100530020006B000D000A00200020002000200057004800450052004500200063002E00730074006100740065006D0065006E0074005F0074006500780074005F0063006800650063006B00730075006D0020003D0020006B002E00730074006100740065006D0065006E0074005F0074006500780074005F0063006800650063006B00730075006D000D000A0020002000200020004F00520044004500520020004200590020006B002E0069006400200044004500530043000D000A00290020004100530020006B000D000A004F005200440045005200200042005900200063002E0074006F00740061006C005F007200650063006F006D00700069006C0065007300200044004500530043003B000D000A00
        WHERE @compile_events = 1;
        INSERT #view_check (view_name, view_definition)
        SELECT N'HumanEvents_WaitsByDatabase', 0x430052004500410054004500200056004900450057002000640062006F002E00480075006D0061006E004500760065006E00740073005F005700610069007400730042007900440061007400610062006100730065000D000A00410053000D000A0057004900540048000D000A002000200020002000770061006900740073002000410053000D000A0028000D000A002000200020002000530045004C004500430054000D000A002000200020002000200020002000200077006100690074005F007000610074007400650072006E0020003D0020004E00270074006F00740061006C0020007700610069007400730020006200790020006400610074006100620061007300650027002C000D000A00200020002000200020002000200020006D0069006E005F006500760065006E0074005F00740069006D00650020003D0020004D0049004E002800770061002E006500760065006E0074005F00740069006D00650029002C000D000A00200020002000200020002000200020006D00610078005F006500760065006E0074005F00740069006D00650020003D0020004D00410058002800770061002E006500760065006E0074005F00740069006D00650029002C000D000A0020002000200020002000200020002000770061002E00640061007400610062006100730065005F006E0061006D0065002C000D000A0020002000200020002000200020002000770061002E0077006100690074005F0074007900700065002C000D000A002000200020002000200020002000200074006F00740061006C005F007700610069007400730020003D00200043004F0055004E0054005F0042004900470028002A0029002C000D000A0020002000200020002000200020002000730075006D005F006400750072006100740069006F006E005F006D00730020003D002000530055004D002800770061002E006400750072006100740069006F006E005F006D00730029002C000D000A0020002000200020002000200020002000730075006D005F007300690067006E0061006C005F006400750072006100740069006F006E005F006D00730020003D002000530055004D002800770061002E007300690067006E0061006C005F006400750072006100740069006F006E005F006D00730029002C000D000A00200020002000200020002000200020006100760067005F006D0073005F007000650072005F00770061006900740020003D002000530055004D002800770061002E006400750072006100740069006F006E005F006D007300290020002F00200043004F0055004E0054005F0042004900470028002A0029000D000A002000200020002000460052004F004D0020005B007200650070006C006100630065005F006D0065005D002000410053002000770061000D000A002000200020002000470052004F00550050002000420059000D000A0020002000200020002000200020002000770061002E00640061007400610062006100730065005F006E0061006D0065002C000D000A0020002000200020002000200020002000770061002E0077006100690074005F0074007900700065000D000A0029000D000A00530045004C00450043005400200054004F00500020002800320031003400370034003800330036003400380029000D000A002000200020002000770061006900740073002E0077006100690074005F007000610074007400650072006E002C000D000A002000200020002000770061006900740073002E006D0069006E005F006500760065006E0074005F00740069006D0065002C000D000A002000200020002000770061006900740073002E006D00610078005F006500760065006E0074005F00740069006D0065002C000D000A002000200020002000770061006900740073002E00640061007400610062006100730065005F006E0061006D0065002C000D000A002000200020002000770061006900740073002E0077006100690074005F0074007900700065002C000D000A002000200020002000770061006900740073002E0074006F00740061006C005F00770061006900740073002C000D000A002000200020002000770061006900740073002E00730075006D005F006400750072006100740069006F006E005F006D0073002C000D000A002000200020002000770061006900740073002E00730075006D005F007300690067006E0061006C005F006400750072006100740069006F006E005F006D0073002C000D000A002000200020002000770061006900740073002E006100760067005F006D0073005F007000650072005F0077006100690074002C000D000A002000200020002000770061006900740073005F007000650072005F007300650063006F006E00640020003D0020000D000A0020002000200020002000200020002000490053004E0055004C004C00280043004F0055004E0054005F0042004900470028002A00290020002F0020004E0055004C004C004900460028004400410054004500440049004600460028005300450043004F004E0044002C002000770061006900740073002E006D0069006E005F006500760065006E0074005F00740069006D0065002C002000770061006900740073002E006D00610078005F006500760065006E0074005F00740069006D00650029002C002000300029002C002000300029002C000D000A002000200020002000770061006900740073005F007000650072005F0068006F007500720020003D0020000D000A0020002000200020002000200020002000490053004E0055004C004C00280043004F0055004E0054005F0042004900470028002A00290020002F0020004E0055004C004C0049004600280044004100540045004400490046004600280048004F00550052002C002000770061006900740073002E006D0069006E005F006500760065006E0074005F00740069006D0065002C002000770061006900740073002E006D00610078005F006500760065006E0074005F00740069006D00650029002C002000300029002C002000300029002C000D000A002000200020002000770061006900740073005F007000650072005F0064006100790020003D0020000D000A0020002000200020002000200020002000490053004E0055004C004C00280043004F0055004E0054005F0042004900470028002A00290020002F0020004E0055004C004C004900460028004400410054004500440049004600460028004400410059002C002000770061006900740073002E006D0069006E005F006500760065006E0074005F00740069006D0065002C002000770061006900740073002E006D00610078005F006500760065006E0074005F00740069006D00650029002C002000300029002C002000300029000D000A00460052004F004D002000770061006900740073000D000A00470052004F00550050002000420059000D000A002000200020002000770061006900740073002E0077006100690074005F007000610074007400650072006E002C000D000A002000200020002000770061006900740073002E006D0069006E005F006500760065006E0074005F00740069006D0065002C000D000A002000200020002000770061006900740073002E006D00610078005F006500760065006E0074005F00740069006D0065002C000D000A002000200020002000770061006900740073002E00640061007400610062006100730065005F006E0061006D0065002C000D000A002000200020002000770061006900740073002E0077006100690074005F0074007900700065002C000D000A002000200020002000770061006900740073002E0074006F00740061006C005F00770061006900740073002C000D000A002000200020002000770061006900740073002E00730075006D005F006400750072006100740069006F006E005F006D0073002C000D000A002000200020002000770061006900740073002E00730075006D005F007300690067006E0061006C005F006400750072006100740069006F006E005F006D0073002C000D000A002000200020002000770061006900740073002E006100760067005F006D0073005F007000650072005F0077006100690074000D000A004F00520044004500520020004200590020000D000A002000200020002000770061006900740073002E00730075006D005F006400750072006100740069006F006E005F006D007300200044004500530043003B00;
        INSERT #view_check (view_name, view_definition)
        SELECT N'HumanEvents_WaitsByQueryAndDatabase', 0x430052004500410054004500200056004900450057002000640062006F002E00480075006D0061006E004500760065006E00740073005F0057006100690074007300420079005100750065007200790041006E006400440061007400610062006100730065000D000A00410053000D000A0057004900540048000D000A00200020002000200070006C0061006E005F00770061006900740073002000410053000D000A0028000D000A002000200020002000530045004C004500430054000D000A002000200020002000200020002000200077006100690074005F007000610074007400650072006E0020003D0020004E00270077006100690074007300200062007900200071007500650072007900200061006E00640020006400610074006100620061007300650027002C000D000A00200020002000200020002000200020006D0069006E005F006500760065006E0074005F00740069006D00650020003D0020004D0049004E002800770061002E006500760065006E0074005F00740069006D00650029002C000D000A00200020002000200020002000200020006D00610078005F006500760065006E0074005F00740069006D00650020003D0020004D00410058002800770061002E006500760065006E0074005F00740069006D00650029002C000D000A0020002000200020002000200020002000770061002E00640061007400610062006100730065005F006E0061006D0065002C000D000A0020002000200020002000200020002000770061002E0077006100690074005F0074007900700065002C000D000A002000200020002000200020002000200074006F00740061006C005F007700610069007400730020003D00200043004F0055004E0054005F0042004900470028002A0029002C000D000A0020002000200020002000200020002000770061002E0070006C0061006E005F00680061006E0064006C0065002C000D000A0020002000200020002000200020002000770061002E00710075006500720079005F0070006C0061006E005F0068006100730068005F007300690067006E00650064002C000D000A0020002000200020002000200020002000770061002E00710075006500720079005F0068006100730068005F007300690067006E00650064002C000D000A0020002000200020002000200020002000730075006D005F006400750072006100740069006F006E005F006D00730020003D002000530055004D002800770061002E006400750072006100740069006F006E005F006D00730029002C000D000A0020002000200020002000200020002000730075006D005F007300690067006E0061006C005F006400750072006100740069006F006E005F006D00730020003D002000530055004D002800770061002E007300690067006E0061006C005F006400750072006100740069006F006E005F006D00730029002C000D000A00200020002000200020002000200020006100760067005F006D0073005F007000650072005F00770061006900740020003D002000530055004D002800770061002E006400750072006100740069006F006E005F006D007300290020002F00200043004F0055004E0054005F0042004900470028002A0029000D000A002000200020002000460052004F004D0020005B007200650070006C006100630065005F006D0065005D002000410053002000770061000D000A002000200020002000470052004F00550050002000420059000D000A0020002000200020002000200020002000770061002E00640061007400610062006100730065005F006E0061006D0065002C000D000A0020002000200020002000200020002000770061002E0077006100690074005F0074007900700065002C000D000A0020002000200020002000200020002000770061002E00710075006500720079005F0068006100730068005F007300690067006E00650064002C000D000A0020002000200020002000200020002000770061002E00710075006500720079005F0070006C0061006E005F0068006100730068005F007300690067006E00650064002C000D000A0020002000200020002000200020002000770061002E0070006C0061006E005F00680061006E0064006C0065000D000A0029000D000A00530045004C00450043005400200054004F00500020002800320031003400370034003800330036003400380029000D000A002000200020002000700077002E0077006100690074005F007000610074007400650072006E002C000D000A002000200020002000700077002E006D0069006E005F006500760065006E0074005F00740069006D0065002C000D000A002000200020002000700077002E006D00610078005F006500760065006E0074005F00740069006D0065002C000D000A002000200020002000700077002E00640061007400610062006100730065005F006E0061006D0065002C000D000A002000200020002000700077002E0077006100690074005F0074007900700065002C000D000A002000200020002000700077002E0074006F00740061006C005F00770061006900740073002C000D000A002000200020002000700077002E00730075006D005F006400750072006100740069006F006E005F006D0073002C000D000A002000200020002000700077002E00730075006D005F007300690067006E0061006C005F006400750072006100740069006F006E005F006D0073002C000D000A002000200020002000700077002E006100760067005F006D0073005F007000650072005F0077006100690074002C000D000A002000200020002000730074002E0074006500780074002C000D000A002000200020002000710070002E00710075006500720079005F0070006C0061006E000D000A00460052004F004D00200070006C0061006E005F00770061006900740073002000410053002000700077000D000A004F00550054004500520020004100500050004C00590020007300790073002E0064006D005F0065007800650063005F00710075006500720079005F0070006C0061006E002800700077002E0070006C0061006E005F00680061006E0064006C00650029002000410053002000710070000D000A004F00550054004500520020004100500050004C00590020007300790073002E0064006D005F0065007800650063005F00730071006C005F0074006500780074002800700077002E0070006C0061006E005F00680061006E0064006C00650029002000410053002000730074000D000A004F00520044004500520020004200590020000D000A002000200020002000700077002E00730075006D005F006400750072006100740069006F006E005F006D007300200044004500530043003B00;
        INSERT #view_check (view_name, view_definition)
        SELECT N'HumanEvents_WaitsTotal', 0x430052004500410054004500200056004900450057002000640062006F002E00480075006D0061006E004500760065006E00740073005F005700610069007400730054006F00740061006C000D000A00410053000D000A00530045004C00450043005400200054004F00500020002800320031003400370034003800330036003400380029000D000A00200020002000200077006100690074005F007000610074007400650072006E0020003D0020004E00270074006F00740061006C0020007700610069007400730027002C000D000A0020002000200020006D0069006E005F006500760065006E0074005F00740069006D00650020003D0020004D0049004E002800770061002E006500760065006E0074005F00740069006D00650029002C000D000A0020002000200020006D00610078005F006500760065006E0074005F00740069006D00650020003D0020004D00410058002800770061002E006500760065006E0074005F00740069006D00650029002C000D000A002000200020002000770061002E0077006100690074005F0074007900700065002C000D000A00200020002000200074006F00740061006C005F007700610069007400730020003D00200043004F0055004E0054005F0042004900470028002A0029002C000D000A002000200020002000730075006D005F006400750072006100740069006F006E005F006D00730020003D002000530055004D002800770061002E006400750072006100740069006F006E005F006D00730029002C000D000A002000200020002000730075006D005F007300690067006E0061006C005F006400750072006100740069006F006E005F006D00730020003D002000530055004D002800770061002E007300690067006E0061006C005F006400750072006100740069006F006E005F006D00730029002C000D000A0020002000200020006100760067005F006D0073005F007000650072005F00770061006900740020003D002000530055004D002800770061002E006400750072006100740069006F006E005F006D007300290020002F00200043004F0055004E0054005F0042004900470028002A0029000D000A00460052004F004D0020005B007200650070006C006100630065005F006D0065005D002000410053002000770061000D000A00470052004F005500500020004200590020000D000A002000200020002000770061002E0077006100690074005F0074007900700065000D000A004F00520044004500520020004200590020000D000A002000200020002000730075006D005F006400750072006100740069006F006E005F006D007300200044004500530043003B00;
        INSERT #view_check (view_name, view_definition)
        SELECT N'HumanEvents_Compiles_Legacy', 0x430052004500410054004500200056004900450057002000640062006F002E00480075006D0061006E004500760065006E00740073005F0043006F006D00700069006C00650073005F004C00650067006100630079000D000A00410053000D000A00530045004C00450043005400200054004F00500020002800320031003400370034003800330036003400380029000D000A0020002000200020006500760065006E0074005F00740069006D0065002C000D000A0020002000200020006500760065006E0074005F0074007900700065002C000D000A002000200020002000640061007400610062006100730065005F006E0061006D0065002C000D000A0020002000200020006F0062006A006500630074005F006E0061006D0065002C000D000A002000200020002000730074006100740065006D0065006E0074005F0074006500780074000D000A00460052004F004D0020005B007200650070006C006100630065005F006D0065005D000D000A004F00520044004500520020004200590020000D000A0020002000200020006500760065006E0074005F00740069006D0065003B00
        WHERE @compile_events = 0;
        INSERT #view_check (view_name, view_definition)
        SELECT N'HumanEvents_Recompiles_Legacy', 0x430052004500410054004500200056004900450057002000640062006F002E00480075006D0061006E004500760065006E00740073005F005200650063006F006D00700069006C00650073005F004C00650067006100630079000D000A00410053000D000A00530045004C00450043005400200054004F00500020002800320031003400370034003800330036003400380029000D000A0020002000200020006500760065006E0074005F00740069006D0065002C000D000A0020002000200020006500760065006E0074005F0074007900700065002C000D000A002000200020002000640061007400610062006100730065005F006E0061006D0065002C000D000A0020002000200020006F0062006A006500630074005F006E0061006D0065002C000D000A0020002000200020007200650063006F006D00700069006C0065005F00630061007500730065002C000D000A002000200020002000730074006100740065006D0065006E0074005F0074006500780074000D000A00460052004F004D0020005B007200650070006C006100630065005F006D0065005D000D000A004F00520044004500520020004200590020000D000A0020002000200020006500760065006E0074005F00740069006D0065003B00
        WHERE @compile_events = 0;

        RAISERROR(N'Updating #view_check with output database (%s) and schema (%s)', 0, 1, @output_database_name, @output_schema_name) WITH NOWAIT;
        UPDATE #view_check
            SET
                output_database = @output_database_name,
                output_schema = @output_schema_name;

        RAISERROR(N'Updating #view_check with table names', 0, 1) WITH NOWAIT;
        UPDATE vc
            SET
                vc.output_table = hew.output_table
        FROM #view_check AS vc
        JOIN #human_events_worker AS hew
          ON  vc.view_name LIKE N'%' + hew.event_type_short + N'%'
          AND hew.is_table_created = 1
          AND hew.is_view_created = 0;

        UPDATE vc
            SET
                vc.output_table = hew.output_table + N'_parameterization'
        FROM #view_check AS vc
        JOIN #human_events_worker AS hew
          ON  vc.view_name = N'HumanEvents_Parameterization'
          AND hew.output_table LIKE N'keeper_HumanEvents_compiles%'
          AND hew.is_table_created = 1
          AND hew.is_view_created = 0;

        IF @debug = 1 BEGIN SELECT N'#view_check' AS table_name, * FROM #view_check AS vc; END;
    END;

    IF
    (
           @view_tracker IS NULL
        OR @view_tracker = 0
    )
    BEGIN
        RAISERROR(N'Starting view creation loop', 0, 1) WITH NOWAIT;

        SELECT
           @min_id = MIN(vc.id),
           @max_id = MAX(vc.id)
        FROM #view_check AS vc
        WHERE vc.output_table <> N''
        AND   EXISTS
        (
            SELECT
                1/0
            FROM #human_events_worker AS hew
            WHERE vc.view_name LIKE N'%' + hew.event_type_short + N'%'
            AND hew.is_table_created = 1
            AND hew.is_view_created = 0
        );

        WHILE @min_id <= @max_id
        BEGIN
            SELECT
                @event_type_check  =
                    LOWER(vc.view_name),
                @object_name_check =
                    QUOTENAME(vc.output_database) +
                    N'.' +
                    QUOTENAME(vc.output_schema) +
                    N'.' +
                    QUOTENAME(vc.view_name),
                @view_database =
                    QUOTENAME(vc.output_database),
                @view_sql =
                    REPLACE
                    (
                        REPLACE
                        (
                            REPLACE
                            (
                                vc.view_converted,
                                N'[replace_me]',
                                QUOTENAME(vc.output_schema)  +
                                N'.'  +
                                vc.output_table
                            ),
                            N'[dbo]' +
                            '.' +
                            QUOTENAME(vc.view_name),
                            QUOTENAME(vc.output_schema) +
                            '.' +
                            QUOTENAME(vc.view_name)
                        ),
                        N'',
                        N''''
                    )
            FROM #view_check AS vc
            WHERE vc.id = @min_id
            AND   vc.output_table <> N'';

            IF OBJECT_ID(@object_name_check) IS NOT NULL
            BEGIN
              RAISERROR(N'Uh oh, found a view', 0, 1) WITH NOWAIT;
              SET
                  @view_sql =
                      REPLACE
                      (
                          @view_sql,
                          N'CREATE VIEW',
                          N'ALTER VIEW'
                      );
            END;

            SELECT
                @spe =
                    @view_database +
                    @spe;

            IF @debug = 1 BEGIN RAISERROR(@spe, 0, 1) WITH NOWAIT; END;

            IF @debug = 1
            BEGIN
                PRINT SUBSTRING(@view_sql, 0,     4000);
                PRINT SUBSTRING(@view_sql, 4000,  8000);
                PRINT SUBSTRING(@view_sql, 8000,  12000);
                PRINT SUBSTRING(@view_sql, 12000, 16000);
                PRINT SUBSTRING(@view_sql, 16000, 20000);
                PRINT SUBSTRING(@view_sql, 20000, 24000);
                PRINT SUBSTRING(@view_sql, 24000, 28000);
                PRINT SUBSTRING(@view_sql, 28000, 32000);
                PRINT SUBSTRING(@view_sql, 32000, 36000);
                PRINT SUBSTRING(@view_sql, 36000, 40000);
            END;

            RAISERROR(N'creating view %s', 0, 1, @event_type_check) WITH NOWAIT;
            EXEC @spe @view_sql;

            IF @debug = 1 BEGIN RAISERROR(N'@min_id: %i', 0, 1, @min_id) WITH NOWAIT; END;

            RAISERROR(N'Setting next id after %i out of %i total', 0, 1, @min_id, @max_id) WITH NOWAIT;

            SET @min_id =
            (
                SELECT TOP (1)
                    vc.id
                FROM #view_check AS vc
                WHERE vc.id > @min_id
                AND   vc.output_table <> N''
                ORDER BY
                    vc.id
            );

            IF @debug = 1 BEGIN RAISERROR(N'new @min_id: %i', 0, 1, @min_id) WITH NOWAIT; END;

            IF @min_id IS NULL BREAK;

            SET @spe = N'.sys.sp_executesql ';
        END;

        UPDATE #human_events_worker
            SET
                is_view_created = 1;

        SET @view_tracker = 1;
    END;
END;

    /*This section handles inserting data into tables*/
    IF EXISTS
    (
        SELECT
            1/0
        FROM #human_events_worker AS hew
        WHERE hew.is_table_created = 1
        AND   hew.last_checked < DATEADD(SECOND, -5, SYSDATETIME())
    )
    BEGIN
        RAISERROR(N'Sessions that need data found, starting loop.', 0, 1) WITH NOWAIT;

        SELECT
            @min_id = MIN(hew.id),
            @max_id = MAX(hew.id)
        FROM #human_events_worker AS hew
        WHERE hew.is_table_created = 1;

        WHILE @min_id <= @max_id
        BEGIN
            SELECT
                @event_type_check  =
                    hew.event_type,
                @object_name_check =
                    QUOTENAME(hew.output_database) +
                    N'.' +
                    QUOTENAME(hew.output_schema) +
                    N'.' +
                    hew.output_table,
                @date_filter =
                    DATEADD
                    (
                        MINUTE,
                        DATEDIFF
                        (
                            MINUTE,
                            SYSDATETIME(),
                            GETUTCDATE()
                        ),
                        hew.last_checked
                    )
            FROM #human_events_worker AS hew
            WHERE hew.id = @min_id
            AND   hew.is_table_created = 1;

            IF OBJECT_ID(@object_name_check) IS NOT NULL
            BEGIN
            RAISERROR(N'Generating insert table statement for %s', 0, 1, @event_type_check) WITH NOWAIT;
                SELECT
                    @table_sql = CONVERT
                                 (
                                     nvarchar(MAX),
                        CASE
                        WHEN @event_type_check LIKE N'%wait%' /*Wait stats!*/
                        THEN CONVERT
                             (
                                 nvarchar(MAX),
                             N'INSERT INTO ' + @object_name_check + N' WITH(TABLOCK) ' + @nc10 +
                             N'( server_name, event_time, event_type, database_name, wait_type, duration_ms, ' + @nc10 +
                             N'  signal_duration_ms, wait_resource,  query_plan_hash_signed, query_hash_signed, plan_handle )' + @nc10 +
                             N'SELECT
        @@SERVERNAME,
        DATEADD
        (
            MINUTE,
            DATEDIFF
            (
                 MINUTE,
                 GETUTCDATE(),
                 SYSDATETIME()
             ),
             c.value(''@timestamp'', ''datetime2'')
        ) AS event_time,
        c.value(''@name'', ''nvarchar(256)'') AS event_type,
        c.value(''(action[@name="database_name"]/value/text())[1]'', ''nvarchar(256)'') AS database_name,
        c.value(''(data[@name="wait_type"]/text)[1]'', ''nvarchar(256)'') AS wait_type,
        c.value(''(data[@name="duration"]/value/text())[1]'', ''bigint'')  AS duration_ms,
        c.value(''(data[@name="signal_duration"]/value/text())[1]'', ''bigint'') AS signal_duration_ms,' + @nc10 +
CONVERT
(
    nvarchar(MAX),
CASE
    WHEN @v = 11 /*We can't get the wait resource on older versions of SQL Server*/
    THEN N'        ''Not Available < 2014'', ' + @nc10
    ELSE N'        c.value(''(data[@name="wait_resource"]/value/text())[1]'', ''nvarchar(256)'')  AS wait_resource, ' + @nc10
END
) + CONVERT(nvarchar(MAX), N'        CONVERT
                (
                    binary(8),
                    c.value(''(action[@name="query_plan_hash_signed"]/value/text())[1]'', ''bigint'')
                ) AS query_plan_hash_signed,
        CONVERT
        (
            binary(8),
            c.value(''(action[@name="query_hash_signed"]/value/text())[1]'', ''bigint'')
        ) AS query_hash_signed,
        c.value(''xs:hexBinary((action[@name="plan_handle"]/value/text())[1])'', ''varbinary(64)'') AS plan_handle
FROM #human_events_xml_internal AS xet
OUTER APPLY xet.human_events_xml.nodes(''//event'') AS oa(c)
WHERE c.exist(''(data[@name="duration"]/value/text()[. > 0])'') = 1
AND   c.exist(''@timestamp[. > sql:variable("@date_filter")]'') = 1;')
                             )
                        WHEN @event_type_check LIKE N'%lock%' /*Blocking!*/
                                                              /*To cut down on nonsense, I'm only inserting new blocking scenarios*/
                                                              /*Any existing blocking scenarios will update the blocking duration*/
                        THEN CONVERT
                             (
                                 nvarchar(MAX),
                             N'INSERT INTO ' + @object_name_check + N' WITH(TABLOCK) ' + @nc10 +
                             N'( server_name, event_time, activity, database_name, database_id, object_id, ' + @nc10 +
                             N'  transaction_id, resource_owner_type, monitor_loop, spid, ecid, query_text, wait_time, ' + @nc10 +
                             N'  transaction_name,  last_transaction_started, wait_resource, lock_mode, status, priority, ' + @nc10 +
                             N'  transaction_count, client_app, host_name, login_name, isolation_level, sql_handle, blocked_process_report )' + @nc10 +
CONVERT(nvarchar(MAX), N'
SELECT server_name, event_time, activity, database_name, database_id, object_id,
       transaction_id, resource_owner_type, monitor_loop, spid, ecid, text, waittime,
       transactionname,  lasttranstarted, wait_resource, lockmode, status, priority,
       trancount, clientapp, hostname, loginname, isolationlevel, sqlhandle, process_report
FROM
(
    SELECT
        x.*,
        x =
            ROW_NUMBER()
                OVER
                (
                    PARTITION BY
                        x.spid,
                        x.ecid,
                        x.transaction_id,
                        x.activity
                    ORDER BY
                        x.spid,
                        x.ecid,
                        x.transaction_id,
                        x.activity
                )
    FROM
    (
        SELECT
            @@SERVERNAME AS server_name,
            DATEADD
            (
                MINUTE,
                DATEDIFF
                (
                    MINUTE,
                    GETUTCDATE(),
                    SYSDATETIME()
                ), oa.c.value(''@timestamp'', ''datetime2'')
            ) AS event_time,
            ''blocked'' AS activity,
            DB_NAME(oa.c.value(''(data[@name="database_id"]/value/text())[1]'', ''int'')) AS database_name,
            oa.c.value(''(data[@name="database_id"]/value/text())[1]'', ''int'') AS database_id,
            oa.c.value(''(data[@name="object_id"]/value/text())[1]'', ''int'') AS object_id,
            oa.c.value(''(data[@name="transaction_id"]/value/text())[1]'', ''bigint'') AS transaction_id,
            oa.c.value(''(data[@name="resource_owner_type"]/text)[1]'', ''nvarchar(256)'') AS resource_owner_type,
            oa.c.value(''(//@monitorLoop)[1]'', ''int'') AS monitor_loop,
            bd.value(''(process/@spid)[1]'', ''int'') AS spid,
            bd.value(''(process/@ecid)[1]'', ''int'') AS ecid,
            bd.value(''(process/inputbuf/text())[1]'', ''nvarchar(MAX)'') AS text,
            bd.value(''(process/@waittime)[1]'', ''bigint'') AS waittime,
            bd.value(''(process/@transactionname)[1]'', ''nvarchar(256)'') AS transactionname,
            bd.value(''(process/@lasttranstarted)[1]'', ''datetime2'') AS lasttranstarted,
            bd.value(''(process/@waitresource)[1]'', ''nvarchar(100)'') AS wait_resource,
            bd.value(''(process/@lockMode)[1]'', ''nvarchar(10)'') AS lockmode,
            bd.value(''(process/@status)[1]'', ''nvarchar(10)'') AS status,
            bd.value(''(process/@priority)[1]'', ''int'') AS priority,
            bd.value(''(process/@trancount)[1]'', ''int'') AS trancount,
            bd.value(''(process/@clientapp)[1]'', ''nvarchar(256)'') AS clientapp,
            bd.value(''(process/@hostname)[1]'', ''nvarchar(256)'') AS hostname,
            bd.value(''(process/@loginname)[1]'', ''nvarchar(256)'') AS loginname,
            bd.value(''(process/@isolationlevel)[1]'', ''nvarchar(50)'') AS isolationlevel,
            CONVERT
            (
                varbinary(64),
                bd.value(''(process/executionStack/frame/@sqlhandle)[1]'', ''nvarchar(260)'')
            ) AS sqlhandle,
            oa.c.query(''.'') AS process_report
        FROM #human_events_xml_internal AS xet
        OUTER APPLY xet.human_events_xml.nodes(''//event'') AS oa(c)
        OUTER APPLY oa.c.nodes(''//blocked-process-report/blocked-process'') AS bd(bd)
        WHERE oa.c.exist(''@timestamp[. > sql:variable("@date_filter")]'') = 1

        UNION ALL

        SELECT
            @@SERVERNAME AS server_name,
            DATEADD
            (
                MINUTE,
                DATEDIFF
                (
                    MINUTE,
                    GETUTCDATE(),
                    SYSDATETIME()
                ),
                oa.c.value(''@timestamp'', ''datetime2'')
            ) AS event_time,
            ''blocking'' AS activity,
            DB_NAME(oa.c.value(''(data[@name="database_id"]/value/text())[1]'', ''int'')) AS database_name,
            oa.c.value(''(data[@name="database_id"]/value/text())[1]'', ''int'') AS database_id,
            oa.c.value(''(data[@name="object_id"]/value/text())[1]'', ''int'') AS object_id,
            oa.c.value(''(data[@name="transaction_id"]/value/text())[1]'', ''bigint'') AS transaction_id,
            oa.c.value(''(data[@name="resource_owner_type"]/text)[1]'', ''nvarchar(256)'') AS resource_owner_type,
            oa.c.value(''(//@monitorLoop)[1]'', ''int'') AS monitor_loop,
            bg.value(''(process/@spid)[1]'', ''int'') AS spid,
            bg.value(''(process/@ecid)[1]'', ''int'') AS ecid,
            bg.value(''(process/inputbuf/text())[1]'', ''nvarchar(MAX)'') AS text,
            NULL AS waittime,
            NULL AS transactionname,
            NULL AS lasttranstarted,
            NULL AS wait_resource,
            NULL AS lockmode,
            bg.value(''(process/@status)[1]'', ''nvarchar(10)'') AS status,
            bg.value(''(process/@priority)[1]'', ''int'') AS priority,
            bg.value(''(process/@trancount)[1]'', ''int'') AS trancount,
            bg.value(''(process/@clientapp)[1]'', ''nvarchar(256)'') AS clientapp,
            bg.value(''(process/@hostname)[1]'', ''nvarchar(256)'') AS hostname,
            bg.value(''(process/@loginname)[1]'', ''nvarchar(256)'') AS loginname,
            bg.value(''(process/@isolationlevel)[1]'', ''nvarchar(50)'') AS isolationlevel,
            NULL AS sqlhandle,
            oa.c.query(''.'') AS process_report
        FROM #human_events_xml_internal AS xet
        OUTER APPLY xet.human_events_xml.nodes(''//event'') AS oa(c)
        OUTER APPLY oa.c.nodes(''//blocked-process-report/blocking-process'') AS bg(bg)
        WHERE oa.c.exist(''@timestamp[. > sql:variable("@date_filter")]'') = 1
    ) AS x
) AS x
WHERE NOT EXISTS
(
    SELECT
        1/0
    FROM ' + @object_name_check + N' AS x2
    WHERE x.database_id = x2.database_id
    AND   x.object_id = x2.object_id
    AND   x.transaction_id = x2.transaction_id
    AND   x.spid = x2.spid
    AND   x.ecid = x2.ecid
    AND   x.clientapp = x2.client_app
    AND   x.hostname = x2.host_name
    AND   x.loginname = x2.login_name
)
AND x.x = 1;

UPDATE x2
    SET
        x2.wait_time = x.waittime
FROM ' + @object_name_check + N' AS x2
JOIN
(
    SELECT
        @@SERVERNAME AS server_name,
        ''blocked'' AS activity,
        oa.c.value(''(data[@name="database_id"]/value/text())[1]'', ''int'') AS database_id,
        oa.c.value(''(data[@name="object_id"]/value/text())[1]'', ''int'') AS object_id,
        oa.c.value(''(data[@name="transaction_id"]/value/text())[1]'', ''bigint'') AS transaction_id,
        oa.c.value(''(//@monitorLoop)[1]'', ''int'') AS monitor_loop,
        bd.value(''(process/@spid)[1]'', ''int'') AS spid,
        bd.value(''(process/@ecid)[1]'', ''int'') AS ecid,
        bd.value(''(process/@waittime)[1]'', ''bigint'') AS waittime,
        bd.value(''(process/@clientapp)[1]'', ''nvarchar(256)'') AS clientapp,
        bd.value(''(process/@hostname)[1]'', ''nvarchar(256)'') AS hostname,
        bd.value(''(process/@loginname)[1]'', ''nvarchar(256)'') AS loginname
    FROM #human_events_xml_internal AS xet
    OUTER APPLY xet.human_events_xml.nodes(''//event'') AS oa(c)
    OUTER APPLY oa.c.nodes(''//blocked-process-report/blocked-process'') AS bd(bd)
    WHERE oa.c.exist(''@timestamp[. > sql:variable("@date_filter")]'') = 1
) AS x
    ON    x.database_id = x2.database_id
    AND   x.object_id = x2.object_id
    AND   x.transaction_id = x2.transaction_id
    AND   x.spid = x2.spid
    AND   x.ecid = x2.ecid
    AND   x.clientapp = x2.client_app
    AND   x.hostname = x2.host_name
    AND   x.loginname = x2.login_name;
'                                ))
                       WHEN @event_type_check LIKE N'%quer%' /*Queries!*/
                       THEN
                            CONVERT
                            (
                                nvarchar(MAX),
                            N'INSERT INTO ' + @object_name_check + N' WITH(TABLOCK) ' + @nc10 +
                            N'( server_name, event_time, event_type, database_name, object_name, sql_text, statement, ' + @nc10 +
                            N'  showplan_xml, cpu_ms, logical_reads, physical_reads, duration_ms, writes_mb, ' + @nc10 +
                            N'  spills_mb, row_count, estimated_rows, dop,  serial_ideal_memory_mb, ' + @nc10 +
                            N'  requested_memory_mb, used_memory_mb, ideal_memory_mb, granted_memory_mb, ' + @nc10 +
                            N'  query_plan_hash_signed, query_hash_signed, plan_handle )' + @nc10 +
                            CONVERT(nvarchar(MAX), N'SELECT
    @@SERVERNAME,
    DATEADD
    (
        MINUTE,
        DATEDIFF
        (
            MINUTE,
            GETUTCDATE(),
            SYSDATETIME()
        ),
        oa.c.value(''@timestamp'', ''datetime2'')
    ) AS event_time,
    oa.c.value(''@name'', ''nvarchar(256)'') AS event_type,
    oa.c.value(''(action[@name="database_name"]/value/text())[1]'', ''nvarchar(256)'') AS database_name,
    oa.c.value(''(data[@name="object_name"]/value/text())[1]'', ''nvarchar(256)'') AS [object_name],
    oa.c.value(''(action[@name="sql_text"]/value/text())[1]'', ''nvarchar(MAX)'') AS sql_text,
    oa.c.value(''(data[@name="statement"]/value/text())[1]'', ''nvarchar(MAX)'') AS statement,
    oa.c.query(''(data[@name="showplan_xml"]/value/*)[1]'') AS [showplan_xml],
    oa.c.value(''(data[@name="cpu_time"]/value/text())[1]'', ''bigint'') / 1000. AS cpu_ms,
   (oa.c.value(''(data[@name="logical_reads"]/value/text())[1]'', ''bigint'') * 8) / 1024. AS logical_reads,
   (oa.c.value(''(data[@name="physical_reads"]/value/text())[1]'', ''bigint'') * 8) / 1024. AS physical_reads,
    oa.c.value(''(data[@name="duration"]/value/text())[1]'', ''bigint'') / 1000. AS duration_ms,
   (oa.c.value(''(data[@name="writes"]/value/text())[1]'', ''bigint'') * 8) / 1024. AS writes_mb,
   (oa.c.value(''(data[@name="spills"]/value/text())[1]'', ''bigint'') * 8) / 1024. AS spills_mb,
    oa.c.value(''(data[@name="row_count"]/value/text())[1]'', ''bigint'') AS row_count,
    oa.c.value(''(data[@name="estimated_rows"]/value/text())[1]'', ''bigint'') AS estimated_rows,
    oa.c.value(''(data[@name="dop"]/value/text())[1]'', ''int'') AS dop,
    oa.c.value(''(data[@name="serial_ideal_memory_kb"]/value/text())[1]'', ''bigint'') / 1024. AS serial_ideal_memory_mb,
    oa.c.value(''(data[@name="requested_memory_kb"]/value/text())[1]'', ''bigint'') / 1024. AS requested_memory_mb,
    oa.c.value(''(data[@name="used_memory_kb"]/value/text())[1]'', ''bigint'') / 1024. AS used_memory_mb,
    oa.c.value(''(data[@name="ideal_memory_kb"]/value/text())[1]'', ''bigint'') / 1024. AS ideal_memory_mb,
    oa.c.value(''(data[@name="granted_memory_kb"]/value/text())[1]'', ''bigint'') / 1024. AS granted_memory_mb,
    CONVERT
    (
        binary(8),
        oa.c.value(''(action[@name="query_plan_hash_signed"]/value/text())[1]'', ''bigint'')
    ) AS query_plan_hash_signed,
    CONVERT
    (
        binary(8),
        oa.c.value(''(action[@name="query_hash_signed"]/value/text())[1]'', ''bigint'')
    ) AS query_hash_signed,
    oa.c.value(''xs:hexBinary((action[@name="plan_handle"]/value/text())[1])'', ''varbinary(64)'') AS plan_handle
FROM #human_events_xml_internal AS xet
OUTER APPLY xet.human_events_xml.nodes(''//event'') AS oa(c)
WHERE oa.c.exist(''@timestamp[. > sql:variable("@date_filter")]'') = 1
AND   oa.c.exist(''(action[@name="query_hash_signed"]/value[. != 0])'') = 1; '
                            ))
                       WHEN @event_type_check LIKE N'%recomp%' /*Recompiles!*/
                       THEN
                            CONVERT
                            (
                                nvarchar(MAX),
                            N'INSERT INTO ' + @object_name_check + N' WITH(TABLOCK) ' + @nc10 +
                            N'( server_name, event_time,  event_type,  ' + @nc10 +
                            N'  database_name, object_name, recompile_cause, statement_text '
                            + CONVERT(nvarchar(MAX), CASE WHEN @compile_events = 1 THEN N', compile_cpu_ms, compile_duration_ms )' ELSE N' )' END) + @nc10 +
                            CONVERT(nvarchar(MAX), N'SELECT
    @@SERVERNAME,
    DATEADD
    (
        MINUTE,
        DATEDIFF
        (
            MINUTE,
            GETUTCDATE(),
            SYSDATETIME()
        ), oa.c.value(''@timestamp'', ''datetime2'')
    ) AS event_time,
    oa.c.value(''@name'', ''nvarchar(256)'') AS event_type,
    oa.c.value(''(action[@name="database_name"]/value/text())[1]'', ''nvarchar(256)'') AS database_name,
    oa.c.value(''(data[@name="object_name"]/value/text())[1]'', ''nvarchar(256)'') AS [object_name],
    oa.c.value(''(data[@name="recompile_cause"]/text)[1]'', ''nvarchar(256)'') AS recompile_cause,
    oa.c.value(''(data[@name="statement"]/value/text())[1]'', ''nvarchar(MAX)'') AS statement_text '
   + CONVERT(nvarchar(MAX), CASE WHEN @compile_events = 1 /*Only get these columns if we're using the newer XE: sql_statement_post_compile*/
          THEN
   N'  ,
    oa.c.value(''(data[@name="cpu_time"]/value/text())[1]'', ''bigint'') AS compile_cpu_ms,
    oa.c.value(''(data[@name="duration"]/value/text())[1]'', ''bigint'') AS compile_duration_ms'
          ELSE N''
     END) + N'
FROM #human_events_xml_internal AS xet
OUTER APPLY xet.human_events_xml.nodes(''//event'') AS oa(c)
WHERE 1 = 1 '
      + CONVERT(nvarchar(MAX), CASE WHEN @compile_events = 1 /*Same here, where we need to filter data*/
             THEN
N'
AND oa.c.exist(''(data[@name="is_recompile"]/value[. = "false"])'') = 0 '
             ELSE N''
        END) + CONVERT(nvarchar(MAX), N'
AND oa.c.exist(''@timestamp[. > sql:variable("@date_filter")]'') = 1
ORDER BY
    event_time;'
                            )))
                       WHEN @event_type_check LIKE N'%comp%' AND @event_type_check NOT LIKE N'%re%' /*Compiles!*/
                       THEN
                            CONVERT
                            (
                                nvarchar(MAX),
                            N'INSERT INTO ' + REPLACE(@object_name_check, N'_parameterization', N'') + N' WITH(TABLOCK) ' + @nc10 +
                            N'( server_name, event_time,  event_type,  ' + @nc10 +
                            N'  database_name, object_name, statement_text '
                            + CONVERT(nvarchar(MAX), CASE WHEN @compile_events = 1 THEN N', compile_cpu_ms, compile_duration_ms )' ELSE N' )' END) + @nc10 +
                            CONVERT(nvarchar(MAX), N'SELECT
    @@SERVERNAME,
    DATEADD
    (
        MINUTE,
        DATEDIFF
        (
            MINUTE,
            GETUTCDATE(),
            SYSDATETIME()
        ),
        oa.c.value(''@timestamp'', ''datetime2'')
    ) AS event_time,
    oa.c.value(''@name'', ''nvarchar(256)'') AS event_type,
    oa.c.value(''(action[@name="database_name"]/value/text())[1]'', ''nvarchar(256)'') AS database_name,
    oa.c.value(''(data[@name="object_name"]/value/text())[1]'', ''nvarchar(256)'') AS [object_name],
    oa.c.value(''(data[@name="statement"]/value/text())[1]'', ''nvarchar(MAX)'') AS statement_text '
   + CONVERT(nvarchar(MAX), CASE WHEN @compile_events = 1 /*Only get these columns if we're using the newer XE: sql_statement_post_compile*/
          THEN
   N'  ,
    oa.c.value(''(data[@name="cpu_time"]/value/text())[1]'', ''bigint'') AS compile_cpu_ms,
    oa.c.value(''(data[@name="duration"]/value/text())[1]'', ''bigint'') AS compile_duration_ms'
          ELSE N''
     END) + N'
FROM #human_events_xml_internal AS xet
OUTER APPLY xet.human_events_xml.nodes(''//event'') AS oa(c)
WHERE 1 = 1 '
      + CONVERT(nvarchar(MAX), CASE WHEN @compile_events = 1 /*Just like above*/
             THEN
N'
AND oa.c.exist(''(data[@name="is_recompile"]/value[. = "false"])'') = 1 '
             ELSE N''
        END) + CONVERT(nvarchar(MAX), N'
AND   oa.c.exist(''@name[.= "sql_statement_post_compile"]'') = 1
AND   oa.c.exist(''@timestamp[. > sql:variable("@date_filter")]'') = 1
ORDER BY
    event_time;' + @nc10
        )))
                            + CASE WHEN @parameterization_events = 1 /*The query_parameterization_data XE is only 2017+*/
                                   THEN
                            @nc10 +
                                CONVERT
                                (
                                    nvarchar(MAX),
                            N'INSERT INTO ' + REPLACE(@object_name_check, N'_parameterization', N'') + N'_parameterization' + N' WITH(TABLOCK) ' + @nc10 +
                            N'( server_name, event_time,  event_type, database_name, sql_text, compile_cpu_time_ms, ' + @nc10 +
                            N'  compile_duration_ms, query_param_type, is_cached, is_recompiled, compile_code, has_literals, ' + @nc10 +
                            N'  is_parameterizable, parameterized_values_count, query_plan_hash, query_hash, plan_handle, statement_sql_hash ) ' + @nc10 +
                            CONVERT(nvarchar(MAX), N'SELECT
    @@SERVERNAME,
    DATEADD
    (
        MINUTE,
        DATEDIFF
        (
            MINUTE,
            GETUTCDATE(),
            SYSDATETIME()
        ),
        oa.c.value(''@timestamp'', ''datetime2'')
    ) AS event_time,
    oa.c.value(''@name'', ''nvarchar(256)'') AS event_type,
    oa.c.value(''(action[@name="database_name"]/value/text())[1]'', ''nvarchar(256)'') AS database_name,
    oa.c.value(''(action[@name="sql_text"]/value/text())[1]'', ''nvarchar(MAX)'') AS sql_text,
    oa.c.value(''(data[@name="compile_cpu_time"]/value/text())[1]'', ''bigint'') / 1000. AS compile_cpu_time_ms,
    oa.c.value(''(data[@name="compile_duration"]/value/text())[1]'', ''bigint'') / 1000. AS compile_duration_ms,
    oa.c.value(''(data[@name="query_param_type"]/value/text())[1]'', ''int'') AS query_param_type,
    oa.c.value(''(data[@name="is_cached"]/value/text())[1]'', ''bit'') AS is_cached,
    oa.c.value(''(data[@name="is_recompiled"]/value/text())[1]'', ''bit'') AS is_recompiled,
    oa.c.value(''(data[@name="compile_code"]/text)[1]'', ''nvarchar(256)'') AS compile_code,
    oa.c.value(''(data[@name="has_literals"]/value/text())[1]'', ''bit'') AS has_literals,
    oa.c.value(''(data[@name="is_parameterizable"]/value/text())[1]'', ''bit'') AS is_parameterizable,
    oa.c.value(''(data[@name="parameterized_values_count"]/value/text())[1]'', ''bigint'') AS parameterized_values_count,
    oa.c.value(''xs:hexBinary((data[@name="query_plan_hash"]/value/text())[1])'', ''binary(8)'') AS query_plan_hash,
    oa.c.value(''xs:hexBinary((data[@name="query_hash"]/value/text())[1])'', ''binary(8)'') AS query_hash,
    oa.c.value(''xs:hexBinary((action[@name="plan_handle"]/value/text())[1])'', ''varbinary(64)'') AS plan_handle,
    oa.c.value(''xs:hexBinary((data[@name="statement_sql_hash"]/value/text())[1])'', ''varbinary(64)'') AS statement_sql_hash
FROM #human_events_xml_internal AS xet
OUTER APPLY xet.human_events_xml.nodes(''//event'') AS oa(c)
WHERE oa.c.exist(''@name[.= "query_parameterization_data"]'') = 1
AND   oa.c.exist(''(data[@name="is_recompiled"]/value[. = "false"])'') = 1
AND   oa.c.exist(''@timestamp[. > sql:variable("@date_filter")]'') = 1
ORDER BY
    event_time;'))
                                   ELSE N''
                              END
                       ELSE N''
                  END
                  );

            /* this table is only used for the inserts, hence the "internal" in the name */
            IF @azure = 0
            BEGIN
                INSERT
                    #x WITH(TABLOCK)
                (
                    x
                )
                SELECT
                    x =
                        CONVERT
                        (
                            xml,
                            t.target_data
                        )
                FROM   sys.dm_xe_session_targets AS t
                JOIN   sys.dm_xe_sessions AS s
                  ON s.address = t.event_session_address
                WHERE s.name = @event_type_check
                AND   t.target_name = N'ring_buffer';
            END;
            ELSE
            BEGIN
                INSERT
                    #x WITH(TABLOCK)
                (
                    x
                )
                SELECT
                    x =
                        CONVERT
                        (
                            xml,
                            t.target_data
                        )
                FROM   sys.dm_xe_database_session_targets AS t
                JOIN   sys.dm_xe_database_sessions AS s
                  ON s.address = t.event_session_address
                WHERE s.name = @event_type_check
                AND   t.target_name = N'ring_buffer';
            END;

            INSERT
                #human_events_xml_internal WITH(TABLOCK)
            (
                human_events_xml
            )
            SELECT
                human_events_xml =
                    e.x.query('.')
                FROM #x AS x
            CROSS APPLY x.x.nodes('/RingBufferTarget/event') AS e(x)
            WHERE e.x.exist('@timestamp[. > sql:variable("@date_filter")]') = 1;

            IF @debug = 1
            BEGIN
                PRINT SUBSTRING(@table_sql, 0, 4000);
                PRINT SUBSTRING(@table_sql, 4000, 8000);
                PRINT SUBSTRING(@table_sql, 8000, 12000);
                PRINT SUBSTRING(@table_sql, 12000, 16000);
                PRINT SUBSTRING(@table_sql, 16000, 20000);
                PRINT SUBSTRING(@table_sql, 20000, 24000);
                PRINT SUBSTRING(@table_sql, 24000, 28000);
                PRINT SUBSTRING(@table_sql, 28000, 32000);
                PRINT SUBSTRING(@table_sql, 32000, 36000);
                PRINT SUBSTRING(@table_sql, 36000, 40000);
            END;

            /* this executes the insert */
            EXEC sys.sp_executesql
                @table_sql,
              N'@date_filter DATETIME',
                @date_filter;

            /*Update the worker table's last checked, and conditionally, updated dates*/
            UPDATE hew
                SET
                    hew.last_checked =
                        SYSDATETIME(),
                    hew.last_updated =
                        CASE
                            WHEN @@ROWCOUNT > 0
                            THEN SYSDATETIME()
                            ELSE hew.last_updated
                        END
            FROM #human_events_worker AS hew
            WHERE hew.id = @min_id;

            IF @debug = 1 BEGIN SELECT N'#human_events_worker' AS table_name, * FROM #human_events_worker AS hew; END;
            IF @debug = 1 BEGIN SELECT N'#human_events_xml_internal' AS table_name, * FROM #human_events_xml_internal AS hew; END;

            /*Clear the table out between runs*/
            TRUNCATE TABLE #human_events_xml_internal;
            TRUNCATE TABLE #x;

            IF @debug = 1 BEGIN RAISERROR(N'@min_id: %i', 0, 1, @min_id) WITH NOWAIT; END;

            RAISERROR(N'Setting next id after %i out of %i total', 0, 1, @min_id, @max_id) WITH NOWAIT;

            SET @min_id =
            (
                SELECT TOP (1)
                    hew.id
                FROM #human_events_worker AS hew
                WHERE hew.id > @min_id
                AND   hew.is_table_created = 1
                ORDER BY
                    hew.id
            );

            IF @debug = 1 BEGIN RAISERROR(N'new @min_id: %i', 0, 1, @min_id) WITH NOWAIT; END;

            IF @min_id IS NULL BREAK;
            END;
        END;
    END;


/*This section handles deleting data from tables older than the retention period*/
/*The idea is to only check once an hour so we're not constantly purging*/
SET @Time = SYSDATETIME();
IF
(
    DATEPART
    (
        MINUTE,
        @Time
    ) <= 5
)
BEGIN
    IF
    (
           @delete_tracker IS NULL
        OR @delete_tracker <> DATEPART(HOUR, @Time)
    )
    BEGIN
        SELECT
            @the_deleter_must_awaken +=
                N' DELETE FROM ' +
                QUOTENAME(hew.output_database) +
                N'.' +
                QUOTENAME(hew.output_schema) +
                N'.' +
                QUOTENAME(hew.event_type) +
                N' WHERE event_time < DATEADD
                                      (
                                          DAY,
                                          (-1 * @delete_retention_days),
                                          SYSDATETIME()
                                      ); ' + @nc10
        FROM #human_events_worker AS hew;

        IF @debug = 1 BEGIN RAISERROR(@the_deleter_must_awaken, 0, 1) WITH NOWAIT; END;

        /* execute the delete */
        EXEC sys.sp_executesql
            @the_deleter_must_awaken,
          N'@delete_retention_days INT',
            @delete_retention_days;

        /* set this to the hour it was last checked */
        SET @delete_tracker = DATEPART(HOUR, SYSDATETIME());
    END;
END;

/*Wait 5 seconds, then start the output loop again*/
WAITFOR DELAY '00:00:05.000';
END;

/*This section handles cleaning up stuff.*/
cleanup:
BEGIN
    RAISERROR(N'CLEAN UP PARTY TONIGHT', 0, 1) WITH NOWAIT;

    SET @executer = QUOTENAME(@output_database_name) + N'.sys.sp_executesql ';

    /*Clean up sessions, this isn't database-specific*/
    SELECT
        @cleanup_sessions +=
            N'DROP EVENT SESSION ' +
            ses.name +
            N' ON SERVER;' +
            @nc10
    FROM sys.server_event_sessions AS ses
    LEFT JOIN sys.dm_xe_sessions AS dxs
      ON dxs.name = ses.name
    WHERE ses.name LIKE N'%HumanEvents_%';

    EXEC sys.sp_executesql
        @cleanup_sessions;

    IF @debug = 1 BEGIN RAISERROR(@cleanup_sessions, 0, 1) WITH NOWAIT; END;


    /*Clean up tables*/
    RAISERROR(N'CLEAN UP PARTY TONIGHT', 0, 1) WITH NOWAIT;

    SELECT
        @cleanup_tables += N'
            SELECT
                @i_cleanup_tables +=
                    N''DROP TABLE '' +
                    SCHEMA_NAME(s.schema_id) +
                    N''.'' +
                    QUOTENAME(s.name) +
                    ''; '' +
                    NCHAR(10)
            FROM ' + QUOTENAME(@output_database_name) + N'.sys.tables AS s
            WHERE s.name LIKE ''' + '%HumanEvents%' + N''';';

    EXEC sys.sp_executesql
        @cleanup_tables,
      N'@i_cleanup_tables nvarchar(MAX) OUTPUT',
        @i_cleanup_tables = @drop_holder OUTPUT;

    IF @debug = 1
    BEGIN
        RAISERROR(@executer, 0, 1) WITH NOWAIT;
        RAISERROR(@drop_holder, 0, 1) WITH NOWAIT;
    END;

    EXEC @executer @drop_holder;

    /*Cleanup views*/
    RAISERROR(N'CLEAN UP PARTY TONIGHT', 0, 1) WITH NOWAIT;

    SET @drop_holder = N'';

    SELECT
        @cleanup_views += N'
            SELECT
                @i_cleanup_views +=
                    N''DROP VIEW '' +
                    SCHEMA_NAME(v.schema_id) +
                    N''.'' +
                    QUOTENAME(v.name) +
                    ''; '' +
                    NCHAR(10)
            FROM ' + QUOTENAME(@output_database_name) + N'.sys.views AS v
            WHERE v.name LIKE ''' + '%HumanEvents%' + N''';';

    EXEC sys.sp_executesql
        @cleanup_views,
      N'@i_cleanup_views nvarchar(MAX) OUTPUT',
        @i_cleanup_views = @drop_holder OUTPUT;

    IF @debug = 1
    BEGIN
        RAISERROR(@executer, 0, 1) WITH NOWAIT;
        RAISERROR(@drop_holder, 0, 1) WITH NOWAIT;
    END;

    EXEC @executer @drop_holder;

    RETURN;
END;
END TRY

/*Very professional error handling*/
BEGIN CATCH
    BEGIN
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

            /*Only try to drop a session if we're not outputting*/
            IF (@output_database_name = N''
                  AND @output_schema_name = N'')
            BEGIN
                IF @debug = 1 BEGIN RAISERROR(@stop_sql, 0, 1) WITH NOWAIT; END;
                RAISERROR(N'all done, stopping session', 0, 1) WITH NOWAIT;
                EXEC (@stop_sql);

                IF @debug = 1 BEGIN RAISERROR(@drop_sql, 0, 1) WITH NOWAIT; END;
                RAISERROR(N'and dropping session', 0, 1) WITH NOWAIT;
                EXEC (@drop_sql);
            END;

            THROW;

            RETURN -138;
    END;
END CATCH;
END;
GO
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
██╗  ██╗██╗   ██╗███╗   ███╗ █████╗ ███╗   ██╗
██║  ██║██║   ██║████╗ ████║██╔══██╗████╗  ██║
███████║██║   ██║██╔████╔██║███████║██╔██╗ ██║
██╔══██║██║   ██║██║╚██╔╝██║██╔══██║██║╚██╗██║
██║  ██║╚██████╔╝██║ ╚═╝ ██║██║  ██║██║ ╚████║
╚═╝  ╚═╝ ╚═════╝ ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝

███████╗██╗   ██╗███████╗███╗   ██╗████████╗███████╗
██╔════╝██║   ██║██╔════╝████╗  ██║╚══██╔══╝██╔════╝
█████╗  ██║   ██║█████╗  ██╔██╗ ██║   ██║   ███████╗
██╔══╝  ╚██╗ ██╔╝██╔══╝  ██║╚██╗██║   ██║   ╚════██║
███████╗ ╚████╔╝ ███████╗██║ ╚████║   ██║   ███████║
╚══════╝  ╚═══╝  ╚══════╝╚═╝  ╚═══╝   ╚═╝   ╚══════╝

██████╗ ██╗      ██████╗  ██████╗██╗  ██╗
██╔══██╗██║     ██╔═══██╗██╔════╝██║ ██╔╝
██████╔╝██║     ██║   ██║██║     █████╔╝
██╔══██╗██║     ██║   ██║██║     ██╔═██╗
██████╔╝███████╗╚██████╔╝╚██████╗██║  ██╗
╚═════╝ ╚══════╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝

██╗   ██╗██╗███████╗██╗    ██╗███████╗██████╗
██║   ██║██║██╔════╝██║    ██║██╔════╝██╔══██╗
██║   ██║██║█████╗  ██║ █╗ ██║█████╗  ██████╔╝
╚██╗ ██╔╝██║██╔══╝  ██║███╗██║██╔══╝  ██╔══██╗
 ╚████╔╝ ██║███████╗╚███╔███╔╝███████╗██║  ██║
  ╚═══╝  ╚═╝╚══════╝ ╚══╝╚══╝ ╚══════╝╚═╝  ╚═╝

Copyright 2024 Darling Data, LLC
https://www.erikdarling.com/

For usage and licensing details, run:
EXEC sp_HumanEventsBlockViewer
    @help = 1;

For working through errors:
EXEC sp_HumanEventsBlockViewer
    @debug = 1;

For support, head over to GitHub:
https://github.com/erikdarlingdata/DarlingData
*/

IF OBJECT_ID('dbo.sp_HumanEventsBlockViewer') IS NULL
   BEGIN
       EXEC ('CREATE PROCEDURE dbo.sp_HumanEventsBlockViewer AS RETURN 138;');
   END;
GO

ALTER PROCEDURE
    dbo.sp_HumanEventsBlockViewer
(
    @session_name nvarchar(256) = N'keeper_HumanEvents_blocking',
    @target_type sysname = NULL,
    @start_date datetime2 = NULL,
    @end_date datetime2 = NULL,
    @database_name sysname = NULL,
    @object_name sysname = NULL,
    @help bit = 0,
    @debug bit = 0,
    @version varchar(30) = NULL OUTPUT,
    @version_date datetime = NULL OUTPUT
)
WITH RECOMPILE
AS
BEGIN
SET STATISTICS XML OFF;
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

SELECT
    @version = '3.5',
    @version_date = '20240401';

IF @help = 1
BEGIN
    SELECT
        introduction =
            'hi, i''m sp_HumanEventsBlockViewer!' UNION ALL
    SELECT  'you can use me in conjunction with sp_HumanEvents to quickly parse the sqlserver.blocked_process_report event' UNION ALL
    SELECT  'EXEC sp_HumanEvents @event_type = N''blocking'', @keep_alive = 1;' UNION ALL
    SELECT  'it will also work with any other extended event session that captures blocking' UNION ALL
    SELECT  'just use the @session_name parameter to point me there' UNION ALL
    SELECT  'EXEC dbo.sp_HumanEventsBlockViewer @session_name = N''blocked_process_report'';' UNION ALL
    SELECT  'all scripts and documentation are available here: https://github.com/erikdarlingdata/DarlingData/tree/main/sp_HumanEvents' UNION ALL
    SELECT  'from your loving sql server consultant, erik darling: https://erikdarling.com';

    SELECT
        parameter_name =
            ap.name,
        data_type = t.name,
        description =
            CASE ap.name
                 WHEN N'@session_name' THEN 'name of the extended event session to pull from'
                 WHEN N'@target_type' THEN 'target of the extended event session'
                 WHEN N'@start_date' THEN 'filter by date'
                 WHEN N'@end_date' THEN 'filter by date'
                 WHEN N'@database_name' THEN 'filter by database name'
                 WHEN N'@object_name' THEN 'filter by table name'
                 WHEN N'@help' THEN 'how you got here'
                 WHEN N'@debug' THEN 'dumps raw temp table contents'
                 WHEN N'@version' THEN 'OUTPUT; for support'
                 WHEN N'@version_date' THEN 'OUTPUT; for support'
            END,
        valid_inputs =
            CASE ap.name
                 WHEN N'@session_name' THEN 'extended event session name capturing sqlserver.blocked_process_report'
                 WHEN N'@target_type' THEN 'event_file or ring_buffer'
                 WHEN N'@start_date' THEN 'a reasonable date'
                 WHEN N'@end_date' THEN 'a reasonable date'
                 WHEN N'@database_name' THEN 'a database that exists on this server'
                 WHEN N'@object_name' THEN 'a schema-prefixed table name'
                 WHEN N'@help' THEN '0 or 1'
                 WHEN N'@debug' THEN '0 or 1'
                 WHEN N'@version' THEN 'none; OUTPUT'
                 WHEN N'@version_date' THEN 'none; OUTPUT'
            END,
        defaults =
            CASE ap.name
                 WHEN N'@session_name' THEN 'keeper_HumanEvents_blocking'
                 WHEN N'@target_type' THEN 'NULL'
                 WHEN N'@start_date' THEN 'NULL; will shortcut to last 7 days'
                 WHEN N'@end_date' THEN 'NULL'
                 WHEN N'@database_name' THEN 'NULL'
                 WHEN N'@object_name' THEN 'NULL'
                 WHEN N'@help' THEN '0'
                 WHEN N'@debug' THEN '0'
                 WHEN N'@version' THEN 'none; OUTPUT'
                 WHEN N'@version_date' THEN 'none; OUTPUT'
            END
    FROM sys.all_parameters AS ap
    JOIN sys.all_objects AS o
      ON ap.object_id = o.object_id
    JOIN sys.types AS t
      ON  ap.system_type_id = t.system_type_id
      AND ap.user_type_id = t.user_type_id
    WHERE o.name = N'sp_HumanEventsBlockViewer'
    OPTION(RECOMPILE);

    SELECT
        blocked_process_report_setup =
            N'check the messages tab for setup commands';

    RAISERROR('
The blocked process report needs to be enabled:
EXEC sys.sp_configure ''show advanced options'', 1;
EXEC sys.sp_configure ''blocked process threshold'', 5; /* Seconds of blocking before a report is generated */
RECONFIGURE;', 0, 1) WITH NOWAIT;

    RAISERROR('
/*Create an extended event to log the blocked process report*/
/*
This won''t work in Azure SQLDB, you need to customize it to create:
 * ON DATABASE instead of ON SERVER
 * With a ring_buffer target
*/
CREATE EVENT SESSION
    blocked_process_report
ON SERVER
    ADD EVENT
        sqlserver.blocked_process_report
    ADD TARGET
        package0.event_file
    (
        SET filename = N''bpr''
    )
WITH
(
    MAX_MEMORY = 4096KB,
    EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS,
    MAX_DISPATCH_LATENCY = 5 SECONDS,
    MAX_EVENT_SIZE = 0KB,
    MEMORY_PARTITION_MODE = NONE,
    TRACK_CAUSALITY = OFF,
    STARTUP_STATE = ON
);

ALTER EVENT SESSION
    blocked_process_report
ON SERVER
    STATE = START; ', 0, 1) WITH NOWAIT;

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
END;

/*Check if the blocked process report is on at all*/
IF EXISTS
(
    SELECT
        1/0
    FROM sys.configurations AS c
    WHERE c.name = N'blocked process threshold (s)'
    AND   CONVERT(int, c.value_in_use) = 0
)
BEGIN
    RAISERROR(N'The blocked process report needs to be enabled:
EXEC sys.sp_configure ''show advanced options'', 1;
EXEC sys.sp_configure ''blocked process threshold'', 5; /* Seconds of blocking before a report is generated */
RECONFIGURE;',
    11, 0) WITH NOWAIT;
    RETURN;
END;

/*Check if the blocked process report is well-configured*/
IF EXISTS
(
    SELECT
        1/0
    FROM sys.configurations AS c
    WHERE c.name = N'blocked process threshold (s)'
    AND   CONVERT(int, c.value_in_use) <> 5
)
BEGIN
    RAISERROR(N'For best results, set up the blocked process report like this:
EXEC sys.sp_configure ''show advanced options'', 1;
EXEC sys.sp_configure ''blocked process threshold'', 5; /* Seconds of blocking before a report is generated */
RECONFIGURE;',
    10, 0) WITH NOWAIT;
END;

/*Set some variables for better decision-making later*/
IF @debug = 1
BEGIN
    RAISERROR('Declaring variables', 0, 1) WITH NOWAIT;
END;
DECLARE
    @azure bit =
        CASE
            WHEN CONVERT
                 (
                     int,
                     SERVERPROPERTY('EngineEdition')
                 ) = 5
            THEN 1
            ELSE 0
        END,
    @azure_msg nchar(1),
    @session_id integer,
    @target_session_id integer,
    @file_name nvarchar(4000),
    @is_system_health bit = 0,
    @is_system_health_msg nchar(1),
    @inputbuf_bom nvarchar(1) =
        CONVERT(nvarchar(1), 0x0a00, 0),
    @start_date_original datetime2 = @start_date,
    @end_date_original datetime2 = @end_date;

/*Use some sane defaults for input parameters*/
IF @debug = 1
BEGIN
    RAISERROR('Setting variables', 0, 1) WITH NOWAIT;
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
    @is_system_health =
        CASE
            WHEN @session_name LIKE N'system%health'
            THEN 1
            ELSE 0
        END;

SELECT
    @azure_msg =
        CONVERT(nchar(1), @azure),
    @is_system_health_msg =
        CONVERT(nchar(1), @is_system_health);

/*Temp tables for staging results*/
IF @debug = 1
BEGIN
    RAISERROR('Creating temp tables', 0, 1) WITH NOWAIT;
END;
CREATE TABLE
    #x
(
    x xml
);

CREATE TABLE
    #blocking_xml
(
    human_events_xml xml
);

CREATE TABLE
    #block_findings
(
    id int IDENTITY PRIMARY KEY,
    check_id int NOT NULL,
    database_name nvarchar(256) NULL,
    object_name nvarchar(1000) NULL,
    finding_group nvarchar(100) NULL,
    finding nvarchar(4000) NULL,
    sort_order bigint
);

/*Look to see if the session exists and is running*/
IF @debug = 1
BEGIN
    RAISERROR('Checking if the session exists', 0, 1) WITH NOWAIT;
END;
IF @azure = 0
BEGIN
    IF NOT EXISTS
    (
        SELECT
            1/0
        FROM sys.server_event_sessions AS ses
        JOIN sys.dm_xe_sessions AS dxs
          ON dxs.name = ses.name
        WHERE ses.name = @session_name
        AND   dxs.create_time IS NOT NULL
    )
    BEGIN
        RAISERROR('A session with the name %s does not exist or is not currently active.', 11, 1, @session_name) WITH NOWAIT;
        RETURN;
    END;
END;

IF @azure = 1
BEGIN
    IF NOT EXISTS
    (
        SELECT
            1/0
        FROM sys.database_event_sessions AS ses
        JOIN sys.dm_xe_database_sessions AS dxs
          ON dxs.name = ses.name
        WHERE ses.name = @session_name
        AND   dxs.create_time IS NOT NULL
    )
    BEGIN
        RAISERROR('A session with the name %s does not exist or is not currently active.', 11, 1, @session_name) WITH NOWAIT;
        RETURN;
    END;
END;

/*Figure out if we have a file or ring buffer target*/
IF @debug = 1
BEGIN
    RAISERROR('What kind of target does %s have?', 0, 1, @session_name) WITH NOWAIT;
END;
IF @target_type IS NULL AND @is_system_health = 0
BEGIN
    IF @azure = 0
    BEGIN
        SELECT TOP (1)
            @target_type =
                t.target_name
        FROM sys.dm_xe_sessions AS s
        JOIN sys.dm_xe_session_targets AS t
          ON s.address = t.event_session_address
        WHERE s.name = @session_name
        ORDER BY t.target_name
        OPTION(RECOMPILE);
    END;

    IF @azure = 1
    BEGIN
        SELECT TOP (1)
            @target_type =
                t.target_name
        FROM sys.dm_xe_database_sessions AS s
        JOIN sys.dm_xe_database_session_targets AS t
          ON s.address = t.event_session_address
        WHERE s.name = @session_name
        ORDER BY t.target_name
        OPTION(RECOMPILE);
    END;
END;

/* Dump whatever we got into a temp table */
IF @target_type = N'ring_buffer' AND @is_system_health = 0
BEGIN
    IF @azure = 0
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Azure: %s', 0, 1, @azure_msg) WITH NOWAIT;
            RAISERROR('Inserting to #x for target type: %s and system health: %s', 0, 1, @target_type, @is_system_health_msg) WITH NOWAIT;
        END;

        INSERT
            #x WITH(TABLOCKX)
        (
            x
        )
        SELECT
            x = TRY_CAST(t.target_data AS xml)
        FROM sys.dm_xe_session_targets AS t
        JOIN sys.dm_xe_sessions AS s
          ON s.address = t.event_session_address
        WHERE s.name = @session_name
        AND   t.target_name = N'ring_buffer'
        OPTION(RECOMPILE);
    END;

    IF @azure = 1
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Azure: %s', 0, 1, @azure_msg) WITH NOWAIT;
            RAISERROR('Inserting to #x for target type: %s and system health: %s', 0, 1, @target_type, @is_system_health_msg) WITH NOWAIT;
        END;

        INSERT
            #x WITH(TABLOCKX)
        (
            x
        )
        SELECT
            x = TRY_CAST(t.target_data AS xml)
        FROM sys.dm_xe_database_session_targets AS t
        JOIN sys.dm_xe_database_sessions AS s
          ON s.address = t.event_session_address
        WHERE s.name = @session_name
        AND   t.target_name = N'ring_buffer'
        OPTION(RECOMPILE);
    END;
END;

IF @target_type = N'event_file' AND @is_system_health = 0
BEGIN
    IF @azure = 0
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Azure: %s', 0, 1, @azure_msg) WITH NOWAIT;
            RAISERROR('Inserting to #x for target type: %s and system health: %s', 0, 1, @target_type, @is_system_health_msg) WITH NOWAIT;
        END;

        SELECT
            @session_id =
                t.event_session_id,
            @target_session_id =
                t.target_id
        FROM sys.server_event_session_targets t
        JOIN sys.server_event_sessions s
          ON s.event_session_id = t.event_session_id
        WHERE t.name = @target_type
        AND   s.name = @session_name
        OPTION(RECOMPILE);

        SELECT
            @file_name =
                CASE
                    WHEN f.file_name LIKE N'%.xel'
                    THEN REPLACE(f.file_name, N'.xel', N'*.xel')
                    ELSE f.file_name + N'*.xel'
                END
        FROM
        (
            SELECT
                file_name =
                    CONVERT
                    (
                        nvarchar(4000),
                        f.value
                    )
            FROM sys.server_event_session_fields AS f
            WHERE f.event_session_id = @session_id
            AND   f.object_id = @target_session_id
            AND   f.name = N'filename'
        ) AS f
        OPTION(RECOMPILE);
    END;

    IF @azure = 1
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Azure: %s', 0, 1, @azure_msg) WITH NOWAIT;
            RAISERROR('Inserting to #x for target type: %s and system health: %s', 0, 1, @target_type, @is_system_health_msg) WITH NOWAIT;
        END;

        SELECT
            @session_id =
                t.event_session_address,
            @target_session_id =
                t.target_name
        FROM sys.dm_xe_database_session_targets t
        JOIN sys.dm_xe_database_sessions s
          ON s.address = t.event_session_address
        WHERE t.target_name = @target_type
        AND   s.name = @session_name
        OPTION(RECOMPILE);

        SELECT
            @file_name =
                CASE
                    WHEN f.file_name LIKE N'%.xel'
                    THEN REPLACE(f.file_name, N'.xel', N'*.xel')
                    ELSE f.file_name + N'*.xel'
                END
        FROM
        (
            SELECT
                file_name =
                    CONVERT
                    (
                        nvarchar(4000),
                        f.value
                    )
            FROM sys.server_event_session_fields AS f
            WHERE f.event_session_id = @session_id
            AND   f.object_id = @target_session_id
            AND   f.name = N'filename'
        ) AS f
        OPTION(RECOMPILE);
    END;

    IF @debug = 1
    BEGIN
        RAISERROR('Azure: %s', 0, 1, @azure_msg) WITH NOWAIT;
        RAISERROR('Inserting to #x for target type: %s and system health: %s', 0, 1, @target_type, @is_system_health_msg) WITH NOWAIT;
        RAISERROR('File name: %s', 0, 1, @file_name) WITH NOWAIT;
    END;

    INSERT
        #x WITH(TABLOCKX)
    (
        x
    )
    SELECT
        x = TRY_CAST(f.event_data AS xml)
    FROM sys.fn_xe_file_target_read_file
         (
             @file_name,
             NULL,
             NULL,
             NULL
         ) AS f
    OPTION(RECOMPILE);
END;


IF @target_type = N'ring_buffer' AND @is_system_health = 0
BEGIN
    IF @debug = 1
    BEGIN
        RAISERROR('Inserting to #blocking_xml for target type: %s and system health: %s', 0, 1, @target_type, @is_system_health_msg) WITH NOWAIT;
    END;

    INSERT
        #blocking_xml WITH(TABLOCKX)
    (
        human_events_xml
    )
    SELECT
        human_events_xml = e.x.query('.')
    FROM #x AS x
    CROSS APPLY x.x.nodes('/RingBufferTarget/event') AS e(x)
    WHERE e.x.exist('@name[ .= "blocked_process_report"]') = 1
    AND   e.x.exist('@timestamp[. >= sql:variable("@start_date") and .< sql:variable("@end_date")]') = 1
    OPTION(RECOMPILE);
END;

IF @target_type = N'event_file' AND @is_system_health = 0
BEGIN
    IF @debug = 1
    BEGIN
        RAISERROR('Inserting to #blocking_xml for target type: %s and system health: %s', 0, 1, @target_type, @is_system_health_msg) WITH NOWAIT;
    END;

    INSERT
        #blocking_xml WITH(TABLOCKX)
    (
        human_events_xml
    )
    SELECT
        human_events_xml = e.x.query('.')
    FROM #x AS x
    CROSS APPLY x.x.nodes('/event') AS e(x)
    WHERE e.x.exist('@name[ .= "blocked_process_report"]') = 1
    AND   e.x.exist('@timestamp[. >= sql:variable("@start_date") and .< sql:variable("@end_date")]') = 1
    OPTION(RECOMPILE);
END;

/*
This section is special for the well-hidden and much less comprehensive blocked
process report stored in the system health extended event session
*/
IF @is_system_health = 1
BEGIN
    IF @debug = 1
    BEGIN
        RAISERROR('Inserting to #sp_server_diagnostics_component_result for system health: %s', 0, 1, @is_system_health_msg) WITH NOWAIT;
    END;

    SELECT
        xml.sp_server_diagnostics_component_result
    INTO #sp_server_diagnostics_component_result
    FROM
    (
        SELECT
            sp_server_diagnostics_component_result =
                TRY_CAST(fx.event_data AS xml)
        FROM sys.fn_xe_file_target_read_file(N'system_health*.xel', NULL, NULL, NULL) AS fx
        WHERE fx.object_name = N'sp_server_diagnostics_component_result'
    ) AS xml
    CROSS APPLY xml.sp_server_diagnostics_component_result.nodes('/event') AS e(x)
    WHERE e.x.exist('//data[@name="data"]/value/queryProcessing/blockingTasks/blocked-process-report') = 1
    AND   e.x.exist('@timestamp[. >= sql:variable("@start_date") and .< sql:variable("@end_date")]') = 1
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#sp_server_diagnostics_component_result',
            ssdcr.*
        FROM #sp_server_diagnostics_component_result AS ssdcr
        OPTION(RECOMPILE);

        RAISERROR('Inserting to #blocking_xml_sh', 0, 1) WITH NOWAIT;
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
    INTO #blocking_xml_sh
    FROM #sp_server_diagnostics_component_result AS wi
    CROSS APPLY wi.sp_server_diagnostics_component_result.nodes('//event') AS w(x)
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#blocking_xml',
            bxs.*
        FROM #blocking_xml_sh AS bxs
        OPTION(RECOMPILE);

        RAISERROR('Inserting to #blocked_sh', 0, 1) WITH NOWAIT;
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
    INTO #blocked_sh
    FROM #blocking_xml_sh AS bx
    OUTER APPLY bx.human_events_xml.nodes('/event') AS oa(c)
    OUTER APPLY oa.c.nodes('//blocked-process-report/blocked-process') AS bd(bd)
    WHERE bd.exist('process/@spid') = 1
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        RAISERROR('Adding query_text to #blocked_sh', 0, 1) WITH NOWAIT;
    END;

    ALTER TABLE #blocked_sh
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
        SELECT
            table_name = '#blocking_sh',
            bxs.*
        FROM #blocking_xml_sh AS bxs
        OPTION(RECOMPILE);

        RAISERROR('Inserting to #blocking_sh', 0, 1) WITH NOWAIT;
    END;

    /*Blocking queries*/
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
    INTO #blocking_sh
    FROM #blocking_xml_sh AS bx
    OUTER APPLY bx.human_events_xml.nodes('/event') AS oa(c)
    OUTER APPLY oa.c.nodes('//blocked-process-report/blocking-process') AS bg(bg)
    WHERE bg.exist('process/@spid') = 1
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        RAISERROR('Adding query_text to #blocking_sh', 0, 1) WITH NOWAIT;
    END;

    ALTER TABLE #blocking_sh
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
        SELECT
            table_name = '#blocking_sh',
            bs.*
        FROM #blocking_sh AS bs
        OPTION(RECOMPILE);

        RAISERROR('Inserting to #blocks_sh', 0, 1) WITH NOWAIT;
    END;

    /*Put it together*/
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
    INTO #blocks_sh
    FROM
    (
        SELECT
            bg.*
        FROM #blocking_sh AS bg
        WHERE (bg.currentdbname = @database_name
               OR @database_name IS NULL)

        UNION ALL

        SELECT
            bd.*
        FROM #blocked_sh AS bd
        WHERE (bd.currentdbname = @database_name
               OR @database_name IS NULL)
    ) AS kheb
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#blocks_sh',
            bs.*
        FROM #blocks_sh AS bs
        OPTION(RECOMPILE);
    END;

    SELECT
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
    FROM #blocks_sh AS b
    ORDER BY
        b.event_time DESC,
        CASE
            WHEN b.activity = 'blocking'
            THEN -1
            ELSE +1
        END
    OPTION(RECOMPILE);

    BEGIN
        RAISERROR('Inserting to #available_plans_sh', 0, 1) WITH NOWAIT;
    END;

    SELECT DISTINCT
        b.*
    INTO #available_plans_sh
    FROM
    (
        SELECT
            available_plans =
                'available_plans',
            b.currentdbname,
            query_text =
                TRY_CAST(b.query_text AS nvarchar(MAX)),
            sql_handle =
                CONVERT(varbinary(64), n.c.value('@sqlhandle', 'varchar(130)'), 1),
            stmtstart =
                ISNULL(n.c.value('@stmtstart', 'int'), 0),
            stmtend =
                ISNULL(n.c.value('@stmtend', 'int'), -1)
        FROM #blocks_sh AS b
        CROSS APPLY b.blocked_process_report.nodes('/blocked-process/process/executionStack/frame[not(@sqlhandle = "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")]') AS n(c)
        WHERE (b.currentdbname = @database_name
                OR @database_name IS NULL)

        UNION ALL

        SELECT
            available_plans =
                'available_plans',
            b.currentdbname,
            query_text =
                TRY_CAST(b.query_text AS nvarchar(MAX)),
            sql_handle =
                CONVERT(varbinary(64), n.c.value('@sqlhandle', 'varchar(130)'), 1),
            stmtstart =
                ISNULL(n.c.value('@stmtstart', 'int'), 0),
            stmtend =
                ISNULL(n.c.value('@stmtend', 'int'), -1)
        FROM #blocks_sh AS b
        CROSS APPLY b.blocked_process_report.nodes('/blocking-process/process/executionStack/frame[not(@sqlhandle = "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")]') AS n(c)
        WHERE (b.currentdbname = @database_name
                OR @database_name IS NULL)
    ) AS b
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#available_plans_sh',
            aps.*
        FROM #available_plans_sh AS aps
        OPTION(RECOMPILE);

        RAISERROR('Inserting to #dm_exec_query_stats_sh', 0, 1) WITH NOWAIT;
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
        avg_elapsed_time_ms =
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
        FROM #available_plans_sh AS ap
        WHERE ap.sql_handle = deqs.sql_handle
    )
    AND deqs.query_hash IS NOT NULL;

    IF @debug = 1
    BEGIN
        RAISERROR('Creating clustered index on #dm_exec_query_stats_sh', 0, 1) WITH NOWAIT;
    END;

    CREATE CLUSTERED INDEX
        deqs_sh
    ON #dm_exec_query_stats_sh
    (
        sql_handle,
        plan_handle
    );

    SELECT
        ap.available_plans,
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
        ap.avg_elapsed_time_ms,
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
            c.avg_elapsed_time_ms,
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
        FROM #available_plans_sh AS ap
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
    OPTION(RECOMPILE, LOOP JOIN, HASH JOIN);
    RETURN;
    /*End system health section, skips checks because most of them won't run*/
END;


IF @debug = 1
BEGIN
    SELECT
        table_name = N'#blocking_xml',
        bx.*
    FROM #blocking_xml AS bx
    OPTION(RECOMPILE);

    RAISERROR('Inserting to #blocked', 0, 1) WITH NOWAIT;
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
            c.value('@timestamp', 'datetime2')
        ),
    database_name = DB_NAME(c.value('(data[@name="database_id"]/value/text())[1]', 'int')),
    database_id = c.value('(data[@name="database_id"]/value/text())[1]', 'int'),
    object_id = c.value('(data[@name="object_id"]/value/text())[1]', 'int'),
    transaction_id = c.value('(data[@name="transaction_id"]/value/text())[1]', 'bigint'),
    resource_owner_type = c.value('(data[@name="resource_owner_type"]/text)[1]', 'nvarchar(256)'),
    monitor_loop = c.value('(//@monitorLoop)[1]', 'int'),
    blocking_spid = bg.value('(process/@spid)[1]', 'int'),
    blocking_ecid = bg.value('(process/@ecid)[1]', 'int'),
    blocked_spid = bd.value('(process/@spid)[1]', 'int'),
    blocked_ecid = bd.value('(process/@ecid)[1]', 'int'),
    query_text_pre = bd.value('(process/inputbuf/text())[1]', 'nvarchar(MAX)'),
    wait_time = bd.value('(process/@waittime)[1]', 'bigint'),
    transaction_name = bd.value('(process/@transactionname)[1]', 'nvarchar(512)'),
    last_transaction_started = bd.value('(process/@lasttranstarted)[1]', 'datetime2'),
    last_transaction_completed = CONVERT(datetime2, NULL),
    wait_resource = bd.value('(process/@waitresource)[1]', 'nvarchar(100)'),
    lock_mode = bd.value('(process/@lockMode)[1]', 'nvarchar(10)'),
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
    currentdbname = bd.value('(process/@currentdbname)[1]', 'nvarchar(256)'),
    currentdbid = bd.value('(process/@currentdb)[1]', 'int'),
    blocking_level = 0,
    sort_order = CAST('' AS varchar(400)),
    activity = CASE WHEN oa.c.exist('//blocked-process-report/blocked-process') = 1 THEN 'blocked' END,
    blocked_process_report = c.query('.')
INTO #blocked
FROM #blocking_xml AS bx
OUTER APPLY bx.human_events_xml.nodes('/event') AS oa(c)
OUTER APPLY oa.c.nodes('//blocked-process-report/blocked-process') AS bd(bd)
OUTER APPLY oa.c.nodes('//blocked-process-report/blocking-process') AS bg(bg)
OPTION(RECOMPILE);

IF @debug = 1
BEGIN
    RAISERROR('Adding query_text to #blocked', 0, 1) WITH NOWAIT;
END;

ALTER TABLE
    #blocked
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
    RAISERROR('Adding blocking_desc to #blocked', 0, 1) WITH NOWAIT;
END;

ALTER TABLE
    #blocked
ADD blocking_desc AS
        ISNULL
        (
            '(' +
            CAST(blocking_spid AS varchar(10)) +
            ':' +
            CAST(blocking_ecid AS varchar(10)) +
            ')',
            'unresolved process'
        ) PERSISTED,
    blocked_desc AS
        '(' +
        CAST(blocked_spid AS varchar(10)) +
        ':' +
        CAST(blocked_ecid AS varchar(10)) +
        ')' PERSISTED;

IF @debug = 1
BEGIN
    RAISERROR('Adding indexes to to #blocked', 0, 1) WITH NOWAIT;
END;

CREATE CLUSTERED INDEX
    blocking
ON #blocked
    (monitor_loop, blocking_desc, blocked_desc);

CREATE INDEX
    blocked
ON #blocked
    (monitor_loop, blocked_desc, blocking_desc);

IF @debug = 1
BEGIN
    SELECT
        '#blocked' AS table_name,
        wa.*
    FROM #blocked AS wa
    OPTION(RECOMPILE);

    RAISERROR('Inserting to #blocking', 0, 1) WITH NOWAIT;
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
            c.value('@timestamp', 'datetime2')
        ),
    database_name = DB_NAME(c.value('(data[@name="database_id"]/value/text())[1]', 'int')),
    database_id = c.value('(data[@name="database_id"]/value/text())[1]', 'int'),
    object_id = c.value('(data[@name="object_id"]/value/text())[1]', 'int'),
    transaction_id = c.value('(data[@name="transaction_id"]/value/text())[1]', 'bigint'),
    resource_owner_type = c.value('(data[@name="resource_owner_type"]/text)[1]', 'nvarchar(256)'),
    monitor_loop = c.value('(//@monitorLoop)[1]', 'int'),
    blocking_spid = bg.value('(process/@spid)[1]', 'int'),
    blocking_ecid = bg.value('(process/@ecid)[1]', 'int'),
    blocked_spid = bd.value('(process/@spid)[1]', 'int'),
    blocked_ecid = bd.value('(process/@ecid)[1]', 'int'),
    query_text_pre = bg.value('(process/inputbuf/text())[1]', 'nvarchar(MAX)'),
    wait_time = bg.value('(process/@waittime)[1]', 'bigint'),
    transaction_name = bg.value('(process/@transactionname)[1]', 'nvarchar(512)'),
    last_transaction_started = bg.value('(process/@lastbatchstarted)[1]', 'datetime2'),
    last_transaction_completed = bg.value('(process/@lastbatchcompleted)[1]', 'datetime2'),
    wait_resource = bg.value('(process/@waitresource)[1]', 'nvarchar(100)'),
    lock_mode = bg.value('(process/@lockMode)[1]', 'nvarchar(10)'),
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
    currentdbname = bg.value('(process/@currentdbname)[1]', 'nvarchar(128)'),
    currentdbid = bg.value('(process/@currentdb)[1]', 'int'),
    blocking_level = 0,
    sort_order = CAST('' AS varchar(400)),
    activity = CASE WHEN oa.c.exist('//blocked-process-report/blocking-process') = 1 THEN 'blocking' END,
    blocked_process_report = c.query('.')
INTO #blocking
FROM #blocking_xml AS bx
OUTER APPLY bx.human_events_xml.nodes('/event') AS oa(c)
OUTER APPLY oa.c.nodes('//blocked-process-report/blocked-process') AS bd(bd)
OUTER APPLY oa.c.nodes('//blocked-process-report/blocking-process') AS bg(bg)
OPTION(RECOMPILE);

IF @debug = 1
BEGIN
    RAISERROR('Adding query_text to to #blocking', 0, 1) WITH NOWAIT;
END;

ALTER TABLE
    #blocking
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
    RAISERROR('Adding blocking_desc to to #blocking', 0, 1) WITH NOWAIT;
END;

ALTER TABLE
    #blocking
ADD blocking_desc AS
        ISNULL
        (
            '(' +
            CAST(blocking_spid AS varchar(10)) +
            ':' +
            CAST(blocking_ecid AS varchar(10)) +
            ')',
            'unresolved process'
        ) PERSISTED,
    blocked_desc AS
        '(' +
        CAST(blocked_spid AS varchar(10)) +
        ':' +
        CAST(blocked_ecid AS varchar(10)) +
        ')' PERSISTED;

IF @debug = 1
BEGIN
    RAISERROR('Creating indexes on #blocking', 0, 1) WITH NOWAIT;
END;

CREATE CLUSTERED INDEX
    blocking
ON #blocking
    (monitor_loop, blocking_desc, blocked_desc);

CREATE INDEX
    blocked
ON #blocking
    (monitor_loop, blocked_desc, blocking_desc);

IF @debug = 1
BEGIN
    SELECT
        '#blocking' AS table_name,
        wa.*
    FROM #blocking AS wa
    OPTION(RECOMPILE);

    RAISERROR('Updating #blocked', 0, 1) WITH NOWAIT;
END;

WITH
    hierarchy AS
(
    SELECT
        b.monitor_loop,
        blocking_desc,
        blocked_desc,
        level = 0,
        sort_order =
            CAST
            (
                blocking_desc +
                ' <-- ' +
                blocked_desc AS varchar(400)
            )
    FROM #blocking b
    WHERE NOT EXISTS
    (
        SELECT
            1/0
        FROM #blocking b2
        WHERE b2.monitor_loop = b.monitor_loop
        AND   b2.blocked_desc = b.blocking_desc
    )

    UNION ALL

    SELECT
        bg.monitor_loop,
        bg.blocking_desc,
        bg.blocked_desc,
        h.level + 1,
        sort_order =
            CAST
            (
                h.sort_order +
                ' ' +
                bg.blocking_desc +
                ' <-- ' +
                bg.blocked_desc AS varchar(400)
            )
    FROM hierarchy h
    JOIN #blocking bg
      ON  bg.monitor_loop = h.monitor_loop
      AND bg.blocking_desc = h.blocked_desc
)
UPDATE #blocked
SET
    blocking_level = h.level,
    sort_order = h.sort_order
FROM #blocked b
JOIN hierarchy h
  ON  h.monitor_loop = b.monitor_loop
  AND h.blocking_desc = b.blocking_desc
  AND h.blocked_desc = b.blocked_desc
OPTION(RECOMPILE, MAXRECURSION 0);

IF @debug = 1
BEGIN
    RAISERROR('Updating #blocking', 0, 1) WITH NOWAIT;
END;

UPDATE #blocking
SET
    blocking_level = bd.blocking_level,
    sort_order = bd.sort_order
FROM #blocking bg
JOIN #blocked bd
  ON  bd.monitor_loop = bg.monitor_loop
  AND bd.blocking_desc = bg.blocking_desc
  AND bd.blocked_desc = bg.blocked_desc
OPTION(RECOMPILE);

IF @debug = 1
BEGIN
    RAISERROR('Inserting #blocks', 0, 1) WITH NOWAIT;
END;

SELECT
    kheb.event_time,
    kheb.database_name,
    kheb.object_id,
    contentious_object = CONVERT(nvarchar(4000), NULL),
    kheb.activity,
    blocking_tree =
        REPLICATE(' > ', kheb.blocking_level) +
        CASE kheb.activity
             WHEN 'blocking'
             THEN '(' + kheb.blocking_desc + ') is blocking (' + kheb.blocked_desc + ')'
             ELSE ' > (' + kheb.blocked_desc + ') is blocked by (' + kheb.blocking_desc + ')'
        END,
    spid =
        CASE kheb.activity
             WHEN 'blocking'
             THEN kheb.blocking_spid
             ELSE kheb.blocked_spid
        END,
    ecid =
        CASE kheb.activity
             WHEN 'blocking'
             THEN kheb.blocking_ecid
             ELSE kheb.blocked_ecid
        END,
    query_text =
        CASE
            WHEN kheb.query_text
                 LIKE @inputbuf_bom + N'Proc |[Database Id = %' ESCAPE N'|'
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
    kheb.lock_mode,
    kheb.resource_owner_type,
    kheb.transaction_count,
    kheb.transaction_name,
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
    kheb.transaction_id,
    kheb.database_id,
    kheb.currentdbname,
    kheb.currentdbid,
    kheb.blocked_process_report,
    kheb.sort_order
INTO #blocks
FROM
(
    SELECT
        bg.*
    FROM #blocking AS bg
    WHERE (bg.database_name = @database_name
           OR @database_name IS NULL)

    UNION ALL

    SELECT
        bd.*
    FROM #blocked AS bd
    WHERE (bd.database_name = @database_name
           OR @database_name IS NULL)
) AS kheb
OPTION(RECOMPILE);

IF @debug = 1
BEGIN
    RAISERROR('Updating #blocks contentious_object column', 0, 1) WITH NOWAIT;
END;
UPDATE b
    SET b.contentious_object =
        ISNULL
        (
            co.contentious_object,
            N'Unresolved: ' +
            N'database: ' +
            b.database_name +
            N' object_id: ' +
            RTRIM(b.object_id)
        )
FROM #blocks AS b
CROSS APPLY
(
    SELECT
        contentious_object =
            OBJECT_SCHEMA_NAME
            (
                b.object_id,
                b.database_id
            ) +
            N'.' +
            OBJECT_NAME
            (
                b.object_id,
                b.database_id
            )
) AS co
OPTION(RECOMPILE);

SELECT
    blocked_process_report =
        'blocked_process_report',
    b.event_time,
    b.database_name,
    b.currentdbname,
    b.contentious_object,
    b.activity,
    b.blocking_tree,
    b.spid,
    b.ecid,
    b.query_text,
    b.wait_time_ms,
    b.status,
    b.isolation_level,
    b.lock_mode,
    b.resource_owner_type,
    b.transaction_count,
    b.transaction_name,
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
    b.transaction_id,
    b.blocked_process_report
FROM
(
    SELECT
        b.*,
        n =
            ROW_NUMBER() OVER
            (
                PARTITION BY
                    b.transaction_id,
                    b.spid,
                    b.ecid
                ORDER BY
                    b.event_time DESC
            )
    FROM #blocks AS b
) AS b
WHERE b.n = 1
AND   (b.contentious_object = @object_name
       OR @object_name IS NULL)
ORDER BY
    b.sort_order,
    CASE
        WHEN b.activity = 'blocking'
        THEN -1
        ELSE +1
    END
OPTION(RECOMPILE);

IF @debug = 1
BEGIN
    RAISERROR('Inserting #available_plans', 0, 1) WITH NOWAIT;
END;

SELECT DISTINCT
    b.*
INTO #available_plans
FROM
(
    SELECT
        available_plans =
            'available_plans',
        b.database_name,
        b.database_id,
        b.currentdbname,
        b.currentdbid,
        b.contentious_object,
        query_text =
            TRY_CAST(b.query_text AS nvarchar(MAX)),
        sql_handle =
            CONVERT(varbinary(64), n.c.value('@sqlhandle', 'varchar(130)'), 1),
        stmtstart =
            ISNULL(n.c.value('@stmtstart', 'int'), 0),
        stmtend =
            ISNULL(n.c.value('@stmtend', 'int'), -1)
    FROM #blocks AS b
    CROSS APPLY b.blocked_process_report.nodes('/event/data/value/blocked-process-report/blocking-process/process/executionStack/frame[not(@sqlhandle = "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")]') AS n(c)
    WHERE (b.database_name = @database_name
            OR @database_name IS NULL)
    AND  (b.contentious_object = @object_name
            OR @object_name IS NULL)

    UNION ALL

    SELECT
        available_plans =
            'available_plans',
        b.database_name,
        b.database_id,
        b.currentdbname,
        b.currentdbid,
        b.contentious_object,
        query_text =
            TRY_CAST(b.query_text AS nvarchar(MAX)),
        sql_handle =
            CONVERT(varbinary(64), n.c.value('@sqlhandle', 'varchar(130)'), 1),
        stmtstart =
            ISNULL(n.c.value('@stmtstart', 'int'), 0),
        stmtend =
            ISNULL(n.c.value('@stmtend', 'int'), -1)
    FROM #blocks AS b
    CROSS APPLY b.blocked_process_report.nodes('/event/data/value/blocked-process-report/blocking-process/process/executionStack/frame[not(@sqlhandle = "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")]') AS n(c)
    WHERE (b.database_name = @database_name
            OR @database_name IS NULL)
    AND  (b.contentious_object = @object_name
            OR @object_name IS NULL)
) AS b
OPTION(RECOMPILE);

IF @debug = 1
BEGIN
    SELECT
        '#available_plans' AS table_name,
        ap.*
    FROM #available_plans AS ap
    OPTION(RECOMPILE);

    RAISERROR('Inserting #dm_exec_query_stats', 0, 1) WITH NOWAIT;
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
    avg_elapsed_time_ms =
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
INTO #dm_exec_query_stats
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
    RAISERROR('Creating index on #dm_exec_query_stats', 0, 1) WITH NOWAIT;
END;

CREATE CLUSTERED INDEX
    deqs
ON #dm_exec_query_stats
(
    sql_handle,
    plan_handle
);

SELECT
    ap.available_plans,
    ap.database_name,
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
    ap.avg_elapsed_time_ms,
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
        c.avg_elapsed_time_ms,
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
        FROM #dm_exec_query_stats deqs
        OUTER APPLY sys.dm_exec_text_query_plan
        (
            deqs.plan_handle,
            deqs.statement_start_offset,
            deqs.statement_end_offset
        ) AS deps
        WHERE deqs.sql_handle = ap.sql_handle
        AND   deps.dbid IN (ap.database_id, ap.currentdbid)
    ) AS c
) AS ap
WHERE ap.query_plan IS NOT NULL
ORDER BY
    ap.avg_worker_time_ms DESC
OPTION(RECOMPILE, LOOP JOIN, HASH JOIN);

IF @debug = 1
BEGIN
    RAISERROR('Inserting #block_findings, check_id -1', 0, 1) WITH NOWAIT;
END;

INSERT
    #block_findings
(
    check_id,
    database_name,
    object_name,
    finding_group,
    finding,
    sort_order
)
SELECT
    check_id = -1,
    database_name = N'erikdarling.com',
    object_name = N'sp_HumanEventsBlockViewer version ' + CONVERT(nvarchar(30), @version) + N'.',
    finding_group = N'https://github.com/erikdarlingdata/DarlingData',
    finding = N'blocking for period ' + CONVERT(nvarchar(30), @start_date_original, 126) + N' through ' + CONVERT(nvarchar(30), @end_date_original, 126) + N'.',
    1;

IF @debug = 1
BEGIN
    RAISERROR('Inserting #block_findings, check_id 1', 0, 1) WITH NOWAIT;
END;

INSERT
    #block_findings
(
    check_id,
    database_name,
    object_name,
    finding_group,
    finding,
    sort_order
)
SELECT
    check_id =
        1,
    database_name =
        b.database_name,
    object_name =
        N'-',
    finding_group =
        N'Database Locks',
    finding =
        N'The database ' +
        b.database_name +
        N' has been involved in ' +
        CONVERT(nvarchar(20), COUNT_BIG(DISTINCT b.transaction_id)) +
        N' blocking sessions.',
   sort_order =
       ROW_NUMBER() OVER (ORDER BY COUNT_BIG(DISTINCT b.transaction_id) DESC)
FROM #blocks AS b
WHERE (b.database_name = @database_name
       OR @database_name IS NULL)
AND   (b.contentious_object = @object_name
       OR @object_name IS NULL)
GROUP BY
    b.database_name
OPTION(RECOMPILE);

IF @debug = 1
BEGIN
    RAISERROR('Inserting #block_findings, check_id 2', 0, 1) WITH NOWAIT;
END;

INSERT
    #block_findings
(
    check_id,
    database_name,
    object_name,
    finding_group,
    finding,
    sort_order
)
SELECT
    check_id =
        2,
    database_name =
        b.database_name,
    object_name =
        b.contentious_object,
    finding_group =
        N'Object Locks',
    finding =
        N'The object ' +
        b.contentious_object +
        CASE
            WHEN b.contentious_object LIKE N'Unresolved%'
            THEN N''
            ELSE N' in database ' +
                 b.database_name
        END +
        N' has been involved in ' +
        CONVERT(nvarchar(20), COUNT_BIG(DISTINCT b.transaction_id)) +
        N' blocking sessions.',
   sort_order =
       ROW_NUMBER() OVER (ORDER BY COUNT_BIG(DISTINCT b.transaction_id) DESC)
FROM #blocks AS b
WHERE (b.database_name = @database_name
       OR @database_name IS NULL)
AND   (b.contentious_object = @object_name
       OR @object_name IS NULL)
GROUP BY
    b.database_name,
    b.contentious_object
OPTION(RECOMPILE);

IF @debug = 1
BEGIN
    RAISERROR('Inserting #block_findings, check_id 3', 0, 1) WITH NOWAIT;
END;

INSERT
    #block_findings
(
    check_id,
    database_name,
    object_name,
    finding_group,
    finding,
    sort_order
)
SELECT
    check_id =
        3,
    database_name =
        b.database_name,
    object_name =
        CASE
            WHEN EXISTS
                 (
                     SELECT
                         1/0
                     FROM sys.databases AS d
                     WHERE d.name COLLATE DATABASE_DEFAULT = b.database_name COLLATE DATABASE_DEFAULT
                     AND   d.is_read_committed_snapshot_on = 1
                 )
            THEN N'You already enabled RCSI, but...'
            ELSE N'You Might Need RCSI'
        END,
    finding_group =
        N'Blocking Involving Selects',
    finding =
        N'There have been ' +
        CONVERT(nvarchar(20), COUNT_BIG(DISTINCT b.transaction_id)) +
        N' select queries involved in blocking sessions in ' +
        b.database_name +
        N'.',
   sort_order =
       ROW_NUMBER() OVER (ORDER BY COUNT_BIG(DISTINCT b.transaction_id) DESC)
FROM #blocks AS b
WHERE b.lock_mode IN
      (
          N'S',
          N'IS'
      )
AND   (b.database_name = @database_name
       OR @database_name IS NULL)
AND   (b.contentious_object = @object_name
       OR @object_name IS NULL)
GROUP BY
    b.database_name
HAVING
    COUNT_BIG(DISTINCT b.transaction_id) > 1
OPTION(RECOMPILE);

IF @debug = 1
BEGIN
    RAISERROR('Inserting #block_findings, check_id 4', 0, 1) WITH NOWAIT;
END;

INSERT
    #block_findings
(
    check_id,
    database_name,
    object_name,
    finding_group,
    finding,
    sort_order
)
SELECT
    check_id =
        4,
    database_name =
        b.database_name,
    object_name =
        N'-',
    finding_group =
        N'Repeatable Read Blocking',
    finding =
        N'There have been ' +
        CONVERT(nvarchar(20), COUNT_BIG(DISTINCT b.transaction_id)) +
        N' repeatable read queries involved in blocking sessions in ' +
        b.database_name +
        N'.',
   sort_order =
       ROW_NUMBER() OVER (ORDER BY COUNT_BIG(DISTINCT b.transaction_id) DESC)
FROM #blocks AS b
WHERE b.isolation_level LIKE N'repeatable%'
AND   (b.database_name = @database_name
       OR @database_name IS NULL)
AND   (b.contentious_object = @object_name
       OR @object_name IS NULL)
GROUP BY
    b.database_name
OPTION(RECOMPILE);

IF @debug = 1
BEGIN
    RAISERROR('Inserting #block_findings, check_id 5', 0, 1) WITH NOWAIT;
END;

INSERT
    #block_findings
(
    check_id,
    database_name,
    object_name,
    finding_group,
    finding,
    sort_order
)
SELECT
    check_id =
        5,
    database_name =
        b.database_name,
    object_name =
        N'-',
    finding_group =
        N'Serializable Blocking',
    finding =
        N'There have been ' +
        CONVERT(nvarchar(20), COUNT_BIG(DISTINCT b.transaction_id)) +
        N' serializable queries involved in blocking sessions in ' +
        b.database_name +
        N'.',
   sort_order =
       ROW_NUMBER() OVER (ORDER BY COUNT_BIG(DISTINCT b.transaction_id) DESC)
FROM #blocks AS b
WHERE b.isolation_level LIKE N'serializable%'
AND   (b.database_name = @database_name
       OR @database_name IS NULL)
AND   (b.contentious_object = @object_name
       OR @object_name IS NULL)
GROUP BY
    b.database_name
OPTION(RECOMPILE);

IF @debug = 1
BEGIN
    RAISERROR('Inserting #block_findings, check_id 6.1', 0, 1) WITH NOWAIT;
END;

INSERT
    #block_findings
(
    check_id,
    database_name,
    object_name,
    finding_group,
    finding,
    sort_order
)
SELECT
    check_id =
        6,
    database_name =
        b.database_name,
    object_name =
        N'-',
    finding_group =
        N'Sleeping Query Blocking',
    finding =
        N'There have been ' +
        CONVERT(nvarchar(20), COUNT_BIG(DISTINCT b.transaction_id)) +
        N' sleeping queries involved in blocking sessions in ' +
        b.database_name +
        N'.',
   sort_order =
       ROW_NUMBER() OVER (ORDER BY COUNT_BIG(DISTINCT b.transaction_id) DESC)
FROM #blocks AS b
WHERE b.status = N'sleeping'
AND   (b.database_name = @database_name
       OR @database_name IS NULL)
AND   (b.contentious_object = @object_name
       OR @object_name IS NULL)
GROUP BY
    b.database_name
OPTION(RECOMPILE);

IF @debug = 1
BEGIN
    RAISERROR('Inserting #block_findings, check_id 6.2', 0, 1) WITH NOWAIT;
END;

INSERT
    #block_findings
(
    check_id,
    database_name,
    object_name,
    finding_group,
    finding,
    sort_order
)
SELECT
    check_id =
        6,
    database_name =
        b.database_name,
    object_name =
        N'-',
    finding_group =
        N'Background Query Blocking',
    finding =
        N'There have been ' +
        CONVERT(nvarchar(20), COUNT_BIG(DISTINCT b.transaction_id)) +
        N' background tasks involved in blocking sessions in ' +
        b.database_name +
        N'.',
   sort_order =
       ROW_NUMBER() OVER (ORDER BY COUNT_BIG(DISTINCT b.transaction_id) DESC)
FROM #blocks AS b
WHERE b.status = N'background'
AND   (b.database_name = @database_name
       OR @database_name IS NULL)
AND   (b.contentious_object = @object_name
       OR @object_name IS NULL)
GROUP BY
    b.database_name
OPTION(RECOMPILE);

IF @debug = 1
BEGIN
    RAISERROR('Inserting #block_findings, check_id 6.3', 0, 1) WITH NOWAIT;
END;

INSERT
    #block_findings
(
    check_id,
    database_name,
    object_name,
    finding_group,
    finding,
    sort_order
)
SELECT
    check_id =
        6,
    database_name =
        b.database_name,
    object_name =
        N'-',
    finding_group =
        N'Done Query Blocking',
    finding =
        N'There have been ' +
        CONVERT(nvarchar(20), COUNT_BIG(DISTINCT b.transaction_id)) +
        N' background tasks involved in blocking sessions in ' +
        b.database_name +
        N'.',
   sort_order =
       ROW_NUMBER() OVER (ORDER BY COUNT_BIG(DISTINCT b.transaction_id) DESC)
FROM #blocks AS b
WHERE b.status = N'done'
AND   (b.database_name = @database_name
       OR @database_name IS NULL)
AND   (b.contentious_object = @object_name
       OR @object_name IS NULL)
GROUP BY
    b.database_name
OPTION(RECOMPILE);

IF @debug = 1
BEGIN
    RAISERROR('Inserting #block_findings, check_id 6.4', 0, 1) WITH NOWAIT;
END;

INSERT
    #block_findings
(
    check_id,
    database_name,
    object_name,
    finding_group,
    finding,
    sort_order
)
SELECT
    check_id =
        6,
    database_name =
        b.database_name,
    object_name =
        N'-',
    finding_group =
        N'Compile Lock Blocking',
    finding =
        N'There have been ' +
        CONVERT(nvarchar(20), COUNT_BIG(DISTINCT b.transaction_id)) +
        N' compile locks blocking sessions in ' +
        b.database_name +
        N'.',
   sort_order =
       ROW_NUMBER() OVER (ORDER BY COUNT_BIG(DISTINCT b.transaction_id) DESC)
FROM #blocks AS b
WHERE b.wait_resource LIKE N'%COMPILE%'
AND   (b.database_name = @database_name
       OR @database_name IS NULL)
AND   (b.contentious_object = @object_name
       OR @object_name IS NULL)
GROUP BY
    b.database_name
OPTION(RECOMPILE);

IF @debug = 1
BEGIN
    RAISERROR('Inserting #block_findings, check_id 6.5', 0, 1) WITH NOWAIT;
END;

INSERT
    #block_findings
(
    check_id,
    database_name,
    object_name,
    finding_group,
    finding,
    sort_order
)
SELECT
    check_id =
        6,
    database_name =
        b.database_name,
    object_name =
        N'-',
    finding_group =
        N'Application Lock Blocking',
    finding =
        N'There have been ' +
        CONVERT(nvarchar(20), COUNT_BIG(DISTINCT b.transaction_id)) +
        N' application locks blocking sessions in ' +
        b.database_name +
        N'.',
   sort_order =
       ROW_NUMBER() OVER (ORDER BY COUNT_BIG(DISTINCT b.transaction_id) DESC)
FROM #blocks AS b
WHERE b.wait_resource LIKE N'APPLICATION%'
AND   (b.database_name = @database_name
       OR @database_name IS NULL)
AND   (b.contentious_object = @object_name
       OR @object_name IS NULL)
GROUP BY
    b.database_name
OPTION(RECOMPILE);

IF @debug = 1
BEGIN
    RAISERROR('Inserting #block_findings, check_id 7.1', 0, 1) WITH NOWAIT;
END;

INSERT
    #block_findings
(
    check_id,
    database_name,
    object_name,
    finding_group,
    finding,
    sort_order
)
SELECT
    check_id =
        7,
    database_name =
        b.database_name,
    object_name =
        N'-',
    finding_group =
        N'Implicit Transaction Blocking',
    finding =
        N'There have been ' +
        CONVERT(nvarchar(20), COUNT_BIG(DISTINCT b.transaction_id)) +
        N' implicit transaction queries involved in blocking sessions in ' +
        b.database_name +
        N'.',
   sort_order =
       ROW_NUMBER() OVER (ORDER BY COUNT_BIG(DISTINCT b.transaction_id) DESC)
FROM #blocks AS b
WHERE b.transaction_name = N'implicit_transaction'
AND   (b.database_name = @database_name
       OR @database_name IS NULL)
AND   (b.contentious_object = @object_name
       OR @object_name IS NULL)
GROUP BY
    b.database_name
OPTION(RECOMPILE);

IF @debug = 1
BEGIN
    RAISERROR('Inserting #block_findings, check_id 7.2', 0, 1) WITH NOWAIT;
END;

INSERT
    #block_findings
(
    check_id,
    database_name,
    object_name,
    finding_group,
    finding,
    sort_order
)
SELECT
    check_id =
        7,
    database_name =
        b.database_name,
    object_name =
        N'-',
    finding_group =
        N'User Transaction Blocking',
    finding =
        N'There have been ' +
        CONVERT(nvarchar(20), COUNT_BIG(DISTINCT b.transaction_id)) +
        N' user transaction queries involved in blocking sessions in ' +
        b.database_name +
        N'.',
   sort_order =
       ROW_NUMBER() OVER (ORDER BY COUNT_BIG(DISTINCT b.transaction_id) DESC)
FROM #blocks AS b
WHERE b.transaction_name = N'user_transaction'
AND   (b.database_name = @database_name
       OR @database_name IS NULL)
AND   (b.contentious_object = @object_name
       OR @object_name IS NULL)
GROUP BY
    b.database_name
OPTION(RECOMPILE);

IF @debug = 1
BEGIN
    RAISERROR('Inserting #block_findings, check_id 8', 0, 1) WITH NOWAIT;
END;

INSERT
    #block_findings
(
    check_id,
    database_name,
    object_name,
    finding_group,
    finding,
    sort_order
)
SELECT
    check_id = 8,
    b.database_name,
    object_name = N'-',
    finding_group = N'Login, App, and Host blocking',
    finding =
        N'This database has had ' +
        CONVERT
        (
            nvarchar(20),
            COUNT_BIG(DISTINCT b.transaction_id)
        ) +
        N' instances of blocking involving the login ' +
        ISNULL
        (
            b.login_name,
            N'UNKNOWN'
        ) +
        N' from the application ' +
        ISNULL
        (
            b.client_app,
            N'UNKNOWN'
        ) +
        N' on host ' +
        ISNULL
        (
            b.host_name,
            N'UNKNOWN'
        ) +
        N'.',
   sort_order =
       ROW_NUMBER() OVER (ORDER BY COUNT_BIG(DISTINCT b.transaction_id) DESC)
FROM #blocks AS b
WHERE (b.database_name = @database_name
       OR @database_name IS NULL)
AND   (b.contentious_object = @object_name
       OR @object_name IS NULL)
GROUP BY
    b.database_name,
    b.login_name,
    b.client_app,
    b.host_name
OPTION(RECOMPILE);

IF @debug = 1
BEGIN
    RAISERROR('Inserting #block_findings, check_id 1000', 0, 1) WITH NOWAIT;
END;

WITH
    b AS
(
    SELECT
        b.database_name,
        b.transaction_id,
        wait_time_ms =
            MAX(b.wait_time_ms)
    FROM #blocks AS b
    WHERE (b.database_name = @database_name
           OR @database_name IS NULL)
    AND   (b.contentious_object = @object_name
           OR @object_name IS NULL)
    GROUP BY
        b.database_name,
        b.transaction_id
)
INSERT
    #block_findings
(
    check_id,
    database_name,
    object_name,
    finding_group,
    finding,
    sort_order
)
SELECT
    check_id =
        1000,
    b.database_name,
    object_name =
        N'-',
    finding_group =
        N'Total database block wait time',
    finding =
        N'This database has had ' +
        CONVERT
        (
            nvarchar(30),
            (
                SUM
                (
                    CONVERT
                    (
                        bigint,
                        b.wait_time_ms
                    )
                ) / 1000 / 86400
            )
        ) +
        N' ' +
        CONVERT
          (
              nvarchar(30),
              DATEADD
              (
                  MILLISECOND,
                  (
                      SUM
                      (
                          CONVERT
                          (
                              bigint,
                              b.wait_time_ms
                          )
                      )
                  ),
                  '19000101'
              ),
              14
          ) +
        N' [dd hh:mm:ss:ms] of lock wait time.',
   sort_order =
       ROW_NUMBER() OVER (ORDER BY SUM(CONVERT(bigint, b.wait_time_ms)) DESC)
FROM b AS b
WHERE (b.database_name = @database_name
       OR @database_name IS NULL)
GROUP BY
    b.database_name
OPTION(RECOMPILE);

IF @debug = 1
BEGIN
    RAISERROR('Inserting #block_findings, check_id 1001', 0, 1) WITH NOWAIT;
END;

WITH
    b AS
(
    SELECT
        b.database_name,
        b.transaction_id,
        b.contentious_object,
        wait_time_ms =
            MAX(b.wait_time_ms)
    FROM #blocks AS b
    WHERE (b.database_name = @database_name
           OR @database_name IS NULL)
    AND   (b.contentious_object = @object_name
           OR @object_name IS NULL)
    GROUP BY
        b.database_name,
        b.contentious_object,
        b.transaction_id
)
INSERT
    #block_findings
(
    check_id,
    database_name,
    object_name,
    finding_group,
    finding,
    sort_order
)
SELECT
    check_id =
        1001,
    b.database_name,
    object_name =
        b.contentious_object,
    finding_group =
        N'Total database and object block wait time',
    finding =
        N'This object has had ' +
        CONVERT
        (
            nvarchar(30),
            (
                SUM
                (
                    CONVERT
                    (
                        bigint,
                        b.wait_time_ms
                    )
                ) / 1000 / 86400
            )
        ) +
        N' ' +
        CONVERT
          (
              nvarchar(30),
              DATEADD
              (
                  MILLISECOND,
                  (
                      SUM
                      (
                          CONVERT
                          (
                              bigint,
                              b.wait_time_ms
                          )
                      )
                  ),
                  '19000101'
              ),
              14
          ) +
        N' [dd hh:mm:ss:ms] of lock wait time in database ' +
        b.database_name,
   sort_order =
       ROW_NUMBER() OVER (ORDER BY SUM(CONVERT(bigint, b.wait_time_ms)) DESC)
FROM b AS b
WHERE (b.database_name = @database_name
       OR @database_name IS NULL)
AND   (b.contentious_object = @object_name
       OR @object_name IS NULL)
GROUP BY
    b.database_name,
    b.contentious_object
OPTION(RECOMPILE);

IF @debug = 1
BEGIN
    RAISERROR('Inserting #block_findings, check_id 2147483647', 0, 1) WITH NOWAIT;
END;

INSERT
    #block_findings
(
    check_id,
    database_name,
    object_name,
    finding_group,
    finding,
    sort_order
)
SELECT
    check_id = 2147483647,
    database_name = N'erikdarling.com',
    object_name = N'sp_HumanEventsBlockViewer version ' + CONVERT(nvarchar(30), @version) + N'.',
    finding_group = N'https://github.com/erikdarlingdata/DarlingData',
    finding = N'thanks for using me!',
    2147483647;

SELECT
    findings =
         'findings',
    bf.check_id,
    bf.database_name,
    bf.object_name,
    bf.finding_group,
    bf.finding
FROM #block_findings AS bf
ORDER BY
    bf.check_id,
    bf.finding_group,
    bf.sort_order
OPTION(RECOMPILE);
END; --Final End
GO
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
██╗      ██████╗  ██████╗                        
██║     ██╔═══██╗██╔════╝                        
██║     ██║   ██║██║  ███╗                       
██║     ██║   ██║██║   ██║                       
███████╗╚██████╔╝╚██████╔╝                       
╚══════╝ ╚═════╝  ╚═════╝                        
                                                 
██╗  ██╗██╗   ██╗███╗   ██╗████████╗███████╗██████╗
██║  ██║██║   ██║████╗  ██║╚══██╔══╝██╔════╝██╔══██╗
███████║██║   ██║██╔██╗ ██║   ██║   █████╗  ██████╔╝
██╔══██║██║   ██║██║╚██╗██║   ██║   ██╔══╝  ██╔══██╗
██║  ██║╚██████╔╝██║ ╚████║   ██║   ███████╗██║  ██║
╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝   ╚═╝   ╚══════╝╚═╝  ╚═╝
  
Copyright 2024 Darling Data, LLC
https://www.erikdarling.com/

For usage and licensing details, run:
EXEC sp_LogHunter
    @help = 1;

For working through errors:
EXEC sp_LogHunter
    @debug = 1;

For support, head over to GitHub:
https://github.com/erikdarlingdata/DarlingData

EXEC sp_LogHunter;

*/

IF OBJECT_ID('dbo.sp_LogHunter') IS NULL  
   BEGIN  
       EXEC ('CREATE PROCEDURE dbo.sp_LogHunter AS RETURN 138;');  
   END;  
GO

ALTER PROCEDURE
    dbo.sp_LogHunter
(
    @days_back int = -7, /*How many days back you want to look in the error logs*/
    @start_date datetime = NULL, /*If you want to search a specific time frame*/
    @end_date datetime = NULL, /*If you want to search a specific time frame*/
    @custom_message nvarchar(4000) = NULL, /*If there's something you specifically want to search for*/
    @custom_message_only bit = 0, /*If you only want to search for this specific thing*/
    @first_log_only bit = 0, /*If you only want to search the first log file*/
    @language_id int = 1033, /*If you want to use a language other than English*/
    @help bit = 0, /*Get help*/
    @debug bit = 0, /*Prints messages and selects from temp tables*/
    @version varchar(30) = NULL OUTPUT,
    @version_date datetime = NULL OUTPUT
)
WITH RECOMPILE
AS
SET STATISTICS XML OFF;  
SET NOCOUNT ON;
SET XACT_ABORT ON;  
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

BEGIN
    SELECT
        @version = '1.5',
        @version_date = '20240401';

    IF @help = 1
    BEGIN
        SELECT
            introduction =
                'hi, i''m sp_LogHunter!' UNION ALL
        SELECT  'you can use me to look through your error logs for bad stuff' UNION ALL
        SELECT  'all scripts and documentation are available here: https://github.com/erikdarlingdata/DarlingData/tree/main/sp_LogHunter' UNION ALL
        SELECT  'from your loving sql server consultant, erik darling: https://erikdarling.com';
  
        SELECT
            parameter_name =
                ap.name,
            data_type = t.name,
            description =
                CASE ap.name
                     WHEN N'@days_back' THEN 'how many days back you want to search the logs'
                     WHEN N'@start_date' THEN 'if you want to search a specific time frame'
                     WHEN N'@end_date' THEN 'if you want to search a specific time frame'
                     WHEN N'@custom_message' THEN 'if you want to search for a custom string'
                     WHEN N'@custom_message_only' THEN 'only search for the custom string'
                     WHEN N'@first_log_only' THEN 'only search through the first error log'
                     WHEN N'@language_id' THEN 'to use something other than English'
                     WHEN N'@help' THEN 'how you got here'
                     WHEN N'@debug' THEN 'dumps raw temp table contents'
                     WHEN N'@version' THEN 'OUTPUT; for support'
                     WHEN N'@version_date' THEN 'OUTPUT; for support'
                END,
            valid_inputs =
                CASE ap.name
                     WHEN N'@days_back' THEN 'an integer; will be converted to a negative number automatically'
                     WHEN N'@start_date' THEN 'a datetime value'
                     WHEN N'@end_date' THEN 'a datetime value'
                     WHEN N'@custom_message' THEN 'something specific you want to search for. no wildcards or substitions.'
                     WHEN N'@custom_message_only' THEN 'NULL, 0, 1'
                     WHEN N'@first_log_only' THEN 'NULL, 0, 1'
                     WHEN N'@language_id' THEN 'SELECT DISTINCT m.language_id FROM sys.messages AS m ORDER BY m.language_id;'
                     WHEN N'@help' THEN 'NULL, 0, 1'
                     WHEN N'@debug' THEN 'NULL, 0, 1'
                     WHEN N'@version' THEN 'OUTPUT; for support'
                     WHEN N'@version_date' THEN 'OUTPUT; for support'
                END,
            defaults =
                CASE ap.name
                     WHEN N'@days_back' THEN '-7'
                     WHEN N'@start_date' THEN 'NULL'
                     WHEN N'@end_date' THEN 'NULL'
                     WHEN N'@custom_message' THEN 'NULL'
                     WHEN N'@custom_message_only' THEN '0'
                     WHEN N'@first_log_only' THEN '0'
                     WHEN N'@language_id' THEN '1033'
                     WHEN N'@help' THEN '0'
                     WHEN N'@debug' THEN '0'
                     WHEN N'@version' THEN 'none; OUTPUT'
                     WHEN N'@version_date' THEN 'none; OUTPUT'
                END
        FROM sys.all_parameters AS ap
        JOIN sys.all_objects AS o
          ON ap.object_id = o.object_id
        JOIN sys.types AS t
          ON  ap.system_type_id = t.system_type_id
          AND ap.user_type_id = t.user_type_id
        WHERE o.name = N'sp_LogHunter'
        OPTION(RECOMPILE);
  
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
    END;
   
    /*Check if we have sa permissisions*/
    IF
    (
        SELECT
            sa = ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0)
    ) = 0
    BEGIN
       RAISERROR(N'Current user is not a member of sysadmin, so we can''t read the error log', 11, 1) WITH NOWAIT;
       RETURN;
    END;

    /*Check if we're using RDS*/
    IF OBJECT_ID(N'rdsadmin.dbo.rds_read_error_log') IS NOT NULL
    BEGIN
       RAISERROR(N'This will not run on Amazon RDS with rdsadmin.dbo.rds_read_error_log because it doesn''t support search strings', 11, 1) WITH NOWAIT;
       RETURN;
    END;

    /*Check if we're unfortunate*/
    IF
    (
        SELECT
            CONVERT
            (
                integer,
                SERVERPROPERTY('EngineEdition')
            )
    ) = 5
    BEGIN
       RAISERROR(N'This will not run on Azure SQL DB because it''s horrible.', 11, 1) WITH NOWAIT;
       RETURN;
    END;

    /*Validate the language id*/
    IF NOT EXISTS
    (
        SELECT
            1/0
        FROM sys.messages AS m
        WHERE m.language_id = @language_id
    )
    BEGIN
       RAISERROR(N'%i is not not a valid language_id in sys.messages.', 11, 1, @language_id) WITH NOWAIT;
       RETURN;
    END;
  
    /*Fix days back a little bit*/
    IF @days_back = 0
    BEGIN
        SELECT
            @days_back = -1;
    END;

    IF @days_back > 0
    BEGIN
        SELECT
            @days_back *= -1;
    END;
  
    IF  @start_date IS NOT NULL
    AND @end_date   IS NOT NULL
    AND @days_back  IS NOT NULL
    BEGIN
        SELECT
            @days_back = NULL;
    END;

    /*Fix custom message only if NULL*/
    IF @custom_message_only IS NULL
    BEGIN
        SELECT
            @custom_message_only = 0;
    END;

    /*Fix @end_date*/
    IF  @start_date IS NOT NULL
    AND @end_date IS NULL
    BEGIN
        SELECT
             @end_date = SYSDATETIME();
    END;

    /*Fix @start_date*/
    IF  @start_date IS NULL
    AND @end_date IS NOT NULL
    BEGIN
        SELECT
             @start_date = DATEADD(DAY, -7, @end_date);
    END;

    /*Debuggo*/
    IF @debug = 1
    BEGIN
        SELECT
            days_back = @days_back,
            start_date = @start_date,
            end_date = @end_date;
    END;

    /*variables for the variable gods*/
    DECLARE
        @c nvarchar(4000) /*holds the command to execute*/,
        @l_log int = 0 /*low log file id*/,
        @h_log int = 0 /*high log file id*/,
        @t_searches int = 0 /*total number of searches to run*/,
        @l_count int = 1 /*loop count*/,
        @stopper bit = 0 /*stop loop execution safety*/;
  
    /*temp tables for holding temporary things*/
    CREATE TABLE
        #error_log
    (
        log_date datetime,
        process_info nvarchar(100),
        text nvarchar(4000)
    );
 
    CREATE TABLE
        #enum
    (
        archive int
            PRIMARY KEY,
        log_date date,
        log_size bigint
    );

    CREATE TABLE
        #search
    (
        id integer
            IDENTITY
            PRIMARY KEY,
        search_string nvarchar(4000) DEFAULT N'""',
        days_back nvarchar(30) NULL,
        start_date nvarchar(30) NULL,
        end_date nvarchar(30) NULL,
        [current_date] nvarchar(10)
            DEFAULT N'"' + CONVERT(nvarchar(10), DATEADD(DAY, 1, SYSDATETIME()), 112) + N'"',
        search_order nvarchar(10)
            DEFAULT N'"DESC"',
        command AS
            CONVERT
            (
                nvarchar(4000),
                N'EXEC master.dbo.xp_readerrorlog [@@@], 1, '
                + search_string
                + N', '
                + N'" "'
                + N', '
                + ISNULL(start_date, days_back)
                + N', '
                + ISNULL(end_date, [current_date])
                + N', '
                + search_order
                + N';'
            ) PERSISTED
    );

    CREATE TABLE
        #errors
    (
        id int PRIMARY KEY IDENTITY,
        command nvarchar(4000) NOT NULL
    );

    /*get all the error logs*/
    INSERT
        #enum
    (
        archive,
        log_date,
        log_size
    )
    EXEC sys.sp_enumerrorlogs;

    IF @debug = 1 BEGIN SELECT table_name = '#enum before delete', e.* FROM #enum AS e; END;

    /*filter out log files we won't use, if @days_back is set*/
    IF @days_back IS NOT NULL
    BEGIN
        DELETE
            e WITH(TABLOCKX)
        FROM #enum AS e
        WHERE e.log_date < DATEADD(DAY, @days_back, SYSDATETIME())
        AND   e.archive > 0
        OPTION(RECOMPILE);
    END;
  
    /*filter out log files we won't use, if @start_date and @end_date are set*/
    IF  @start_date IS NOT NULL
    AND @end_date IS NOT NULL
    BEGIN
        DELETE
            e WITH(TABLOCKX)
        FROM #enum AS e
        WHERE e.log_date < CONVERT(date, @start_date)
        OR    e.log_date > CONVERT(date, @end_date)
        OPTION(RECOMPILE);
    END;

    /*maybe you only want the first one anyway*/
    IF @first_log_only = 1
    BEGIN
        DELETE
            e WITH(TABLOCKX)
        FROM #enum AS e
        WHERE e.archive > 1
        OPTION(RECOMPILE);
    END;

    IF @debug = 1 BEGIN SELECT table_name = '#enum after delete', e.* FROM #enum AS e; END;

    /*insert some canary values for things that we should always hit. look a little further back for these.*/
    INSERT
        #search
    (
        search_string,
        days_back,
        start_date,
        end_date
    )
    SELECT
        x.search_string,
        c.days_back,
        c.start_date,
        c.end_date
    FROM
    (
        VALUES
            (N'"Microsoft SQL Server"'),
            (N'"detected"'),
            (N'"SQL Server has encountered"'),
            (N'"Warning: Enterprise Server/CAL license used for this instance"')
    ) AS x (search_string)
    CROSS JOIN
    (
        SELECT
            days_back =
                N'"' + CONVERT(nvarchar(10), DATEADD(DAY, CASE WHEN @days_back > -90 THEN -90 ELSE @days_back END, SYSDATETIME()), 112) + N'"',
            start_date =
                N'"' + CONVERT(nvarchar(30), @start_date) + N'"',
            end_date =
                N'"' + CONVERT(nvarchar(30), @end_date) + N'"'
    ) AS c
    WHERE @custom_message_only = 0
    OPTION(RECOMPILE);

    /*these are the search strings we currently care about*/
    INSERT
        #search
    (
        search_string,
        days_back,
        start_date,
        end_date
    )
    SELECT
        search_string =
            N'"' +
            v.search_string +
            N'"',
        c.days_back,
        c.start_date,
        c.end_date
    FROM
    (
        VALUES
            ('error'), ('corrupt'), ('insufficient'), ('DBCC CHECKDB'), ('Attempt to fetch logical page'), ('Total Log Writer threads'),
            ('Wait for redo catchup for the database'), ('Restart the server to resolve this problem'), ('running low'), ('unexpected'),
            ('fail'), ('contact'), ('incorrect'), ('allocate'), ('allocation'), ('Timeout occurred'), ('memory manager'), ('operating system'),
            ('cannot obtain a LOCK resource'), ('Server halted'), ('spawn'), ('BobMgr'), ('Sort is retrying the read'), ('service'),
            ('resumed'), ('repair the database'), ('buffer'), ('I/O Completion Port'), ('assert'), ('integrity'), ('latch'), ('SQL Server is exiting'),
            ('SQL Server is unable to run'), ('suspect'), ('restore the database'), ('checkpoint'), ('version store is full'), ('Setting database option'),
            ('Perform a restore if necessary'), ('Autogrow of file'), ('Bringing down database'), ('hot add'), ('Server shut down'),
            ('stack'), ('inconsistency.'), ('invalid'), ('time out occurred'), ('The transaction log for database'), ('The virtual log file sequence'),
            ('Cannot accept virtual log file sequence'), ('The transaction in database'), ('Shutting down'), ('thread pool'), ('debug'), ('resolving'),
            ('Cannot load the Query Store metadata'), ('Cannot acquire'), ('SQL Server evaluation period has expired'), ('terminat'), ('currently busy'),
            ('SQL Server has been configured for lightweight pooling'), ('IOCP'), ('Not enough memory for the configured number of locks'),
            ('The tempdb database data files are not configured with the same initial size and autogrowth settings'), ('The SQL Server image'), ('affinity'),
            ('SQL Server is starting'), ('Ignoring trace flag '), ('20 physical cores'), ('No free space'), ('Warning ******************'),
            ('SQL Server should be restarted'), ('Server name is'), ('Could not connect'), ('yielding'), ('worker thread'), ('A new connection was rejected'),
            ('A significant part of sql server process memory has been paged out'), ('Dispatcher'), ('I/O requests taking longer than'), ('killed'),
            ('SQL Server could not start'), ('SQL Server cannot start'), ('System Manufacturer:'), ('columnstore'), ('timed out'), ('inconsistent'),
            ('flushcache'), ('Recovery for availability database')
    ) AS v (search_string)
    CROSS JOIN
    (
        SELECT
            days_back =
                N'"' + CONVERT(nvarchar(10), DATEADD(DAY, @days_back, SYSDATETIME()), 112) + N'"',
            start_date =
                N'"' + CONVERT(nvarchar(30), @start_date) + N'"',
            end_date =
                N'"' + CONVERT(nvarchar(30), @end_date) + N'"'
    ) AS c
    WHERE @custom_message_only = 0
    OPTION(RECOMPILE); 

    /*deal with a custom search string here*/
    INSERT
        #search
    (
        search_string,
        days_back,
        start_date,
        end_date
    )
    SELECT
        x.search_string,
        x.days_back,
        x.start_date,
        x.end_date
    FROM
    (
        VALUES
           (
                N'"' + @custom_message + '"',
                N'"' + CONVERT(nvarchar(10), DATEADD(DAY, @days_back, SYSDATETIME()), 112) + N'"',
                N'"' + CONVERT(nvarchar(30), @start_date) + N'"',
                N'"' + CONVERT(nvarchar(30), @end_date) + N'"'
           )
    ) AS x (search_string, days_back, start_date, end_date)
    WHERE @custom_message LIKE N'_%'
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        SELECT table_name = '#search', s.* FROM #search AS s;
    END;
  
    /*Set the min and max logs we're getting for the loop*/
    SELECT
        @l_log = MIN(e.archive),
        @h_log = MAX(e.archive),
        @t_searches = (SELECT COUNT_BIG(*) FROM #search AS s)
    FROM #enum AS e
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        RAISERROR('@l_log: %i', 0, 1, @l_log) WITH NOWAIT;
        RAISERROR('@h_log: %i', 0, 1, @h_log) WITH NOWAIT;
        RAISERROR('@t_searches: %i', 0, 1, @t_searches) WITH NOWAIT;
    END;

    IF @debug = 1 BEGIN RAISERROR('Declaring cursor', 0, 1) WITH NOWAIT; END;
 
    /*start the loops*/
    WHILE @l_log <= @h_log
    BEGIN
        DECLARE
            c
        CURSOR
            LOCAL
            SCROLL
            DYNAMIC
            READ_ONLY
        FOR
        SELECT
            command
        FROM #search;
      
        IF @debug = 1 BEGIN RAISERROR('Opening cursor', 0, 1) WITH NOWAIT; END;
       
        OPEN c;
      
        FETCH FIRST
        FROM c
        INTO @c;

        IF @debug = 1 BEGIN RAISERROR('Entering WHILE loop', 0, 1) WITH NOWAIT; END;
        WHILE @@FETCH_STATUS = 0 AND @stopper = 0         
        BEGIN
            IF @debug = 1 BEGIN RAISERROR('Entering cursor', 0, 1) WITH NOWAIT; END;
            /*Replace the canary value with the log number we're working in*/
            SELECT
                @c =
                    REPLACE
                    (
                        @c,
                        N'[@@@]',
                        @l_log
                    );

            IF @debug = 1
            BEGIN
                RAISERROR('log %i of %i', 0, 1, @l_log, @h_log) WITH NOWAIT;
                RAISERROR('search %i of %i', 0, 1, @l_count, @t_searches) WITH NOWAIT;
                RAISERROR('@c: %s', 0, 1, @c) WITH NOWAIT;       
            END;
         
            IF @debug = 1 BEGIN RAISERROR('Inserting to error log', 0, 1) WITH NOWAIT; END;
            BEGIN
                BEGIN TRY
                    /*Insert any log entries we find that match the search*/
                    INSERT
                        #error_log
                    (
                        log_date,
                        process_info,
                        text
                    )
                    EXEC sys.sp_executesql
                        @c;
                END TRY
                BEGIN CATCH
                    /*Insert any searches that throw an error here*/
                    INSERT
                        #errors
                    (
                        command
                    )
                    VALUES
                    (
                        @c
                    );         
                END CATCH;
            END;
         
            IF @debug = 1 BEGIN RAISERROR('Fetching next', 0, 1) WITH NOWAIT; END;
            /*Get the next search command*/
            FETCH NEXT
            FROM c
            INTO @c;

            /*Increment our loop counter*/
            SELECT
                @l_count += 1;

        END;
         
        IF @debug = 1 BEGIN RAISERROR('Getting next log', 0, 1) WITH NOWAIT; END;
        /*Increment the log numbers*/
        SELECT
            @l_log = MIN(e.archive),
            @l_count = 1
        FROM #enum AS e
        WHERE e.archive > @l_log
        OPTION(RECOMPILE);

        IF @debug = 1
        BEGIN
            RAISERROR('log %i of %i', 0, 1, @l_log, @h_log) WITH NOWAIT;   
        END;

        /*Stop the loop if this is NULL*/
        IF @l_log IS NULL
        BEGIN
            IF @debug = 1 BEGIN RAISERROR('Breaking', 0, 1) WITH NOWAIT; END;        
            SET @stopper = 1;
            BREAK;
        END;             
        IF @debug = 1 BEGIN RAISERROR('Ended WHILE loop', 0, 1) WITH NOWAIT; END;
 
        /*Close out the cursor*/
        CLOSE c;
        DEALLOCATE c;
    END;
    IF @debug = 1 BEGIN RAISERROR('Ended cursor', 0, 1) WITH NOWAIT; END;

    /*get rid of some messages we don't care about*/
    DELETE
        el WITH(TABLOCKX)
    FROM #error_log AS el
    WHERE el.text LIKE N'DBCC TRACEON 3604%'
    OR    el.text LIKE N'DBCC TRACEOFF 3604%'
    OR    el.text LIKE N'This instance of SQL Server has been using a process ID of%'
    OR    el.text LIKE N'Could not connect because the maximum number of ''1'' dedicated administrator connections already exists%'
    OR    el.text LIKE N'Login failed%'
    OR    el.text LIKE N'Backup(%'
    OR    el.text LIKE N'[[]INFO]%'
    OR    el.text LIKE N'[[]DISK_SPACE_TO_RESERVE_PROPERTY]%'
    OR    el.text LIKE N'[[]CFabricCommonUtils::GetFabricPropertyInternalWithRef]%'
    OR    el.text LIKE N'CHECKDB for database % finished without errors%'
    OR    el.text LIKE N'Parallel redo is shutdown for database%'
    OR    el.text LIKE N'%This is an informational message only. No user action is required.%'
    OR    el.text LIKE N'%SPN%'
    OR    el.text LIKE N'Service Broker manager has started.%'
    OR    el.text LIKE N'Parallel redo is started for database%'
    OR    el.text LIKE N'Starting up database%'
    OR    el.text LIKE N'Buffer pool extension is already disabled%'
    OR    el.text LIKE N'Buffer Pool: Allocating % bytes for % hashPages.'
    OR    el.text LIKE N'The client was unable to reuse a session with%'
    OR    el.text LIKE N'SSPI%'
    OR    el.text LIKE N'%Severity: 1[0-8]%'
    OR    el.text IN
          (
              N'The Database Mirroring endpoint is in disabled or stopped state.',
              N'The Service Broker endpoint is in disabled or stopped state.'
          )
    OPTION(RECOMPILE);

    /*Return the search results*/
    SELECT
        table_name =
            '#error_log',
        el.*
    FROM #error_log AS el
    ORDER BY
        el.log_date DESC
    OPTION(RECOMPILE);

    /*If we hit any errors, show which searches failed here*/
    IF EXISTS
    (
        SELECT
            1/0
        FROM #errors AS e
    )
    BEGIN     
        SELECT
            table_name =
                '#errors',
            e.*
        FROM #errors AS e
        ORDER BY
            e.id
        OPTION(RECOMPILE);
    END;
END;
GO
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

██████╗ ██████╗ ███████╗███████╗███████╗██╗   ██╗██████╗ ███████╗
██╔══██╗██╔══██╗██╔════╝██╔════╝██╔════╝██║   ██║██╔══██╗██╔════╝
██████╔╝██████╔╝█████╗  ███████╗███████╗██║   ██║██████╔╝█████╗
██╔═══╝ ██╔══██╗██╔══╝  ╚════██║╚════██║██║   ██║██╔══██╗██╔══╝
██║     ██║  ██║███████╗███████║███████║╚██████╔╝██║  ██║███████╗
╚═╝     ╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝

██████╗ ███████╗████████╗███████╗ ██████╗████████╗ ██████╗ ██████╗
██╔══██╗██╔════╝╚══██╔══╝██╔════╝██╔════╝╚══██╔══╝██╔═══██╗██╔══██╗
██║  ██║█████╗     ██║   █████╗  ██║        ██║   ██║   ██║██████╔╝
██║  ██║██╔══╝     ██║   ██╔══╝  ██║        ██║   ██║   ██║██╔══██╗
██████╔╝███████╗   ██║   ███████╗╚██████╗   ██║   ╚██████╔╝██║  ██║
╚═════╝ ╚══════╝   ╚═╝   ╚══════╝ ╚═════╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝

Copyright 2024 Darling Data, LLC
https://www.erikdarling.com/

For usage and licensing details, run:
EXEC sp_PressureDetector
    @help = 1;

For working through errors:
EXEC sp_PressureDetector
    @debug = 1;

For support, head over to GitHub:
https://github.com/erikdarlingdata/DarlingData

*/


IF OBJECT_ID('dbo.sp_PressureDetector') IS NULL
    EXEC ('CREATE PROCEDURE dbo.sp_PressureDetector AS RETURN 138;');
GO

ALTER PROCEDURE
    dbo.sp_PressureDetector
(
    @what_to_check varchar(6) = 'all', /*areas to check for pressure*/
    @skip_queries bit = 0, /*if you want to skip looking at running queries*/
    @skip_plan_xml bit = 0, /*if you want to skip getting plan XML*/
    @minimum_disk_latency_ms smallint = 100, /*low bound for reporting disk latency*/
    @cpu_utilization_threshold smallint = 50, /*low bound for reporting high cpu utlization*/
    @skip_waits bit = 0, /*skips waits when you do not need them on every run*/
    @skip_perfmon bit = 0, /*skips perfmon counters when you do not need them on every run*/
    @sample_seconds tinyint = 0, /*take a sample of your server's metrics*/
    @help bit = 0, /*how you got here*/
    @debug bit = 0, /*prints dynamic sql, displays parameter and variable values, and table contents*/
    @version varchar(5) = NULL OUTPUT, /*OUTPUT; for support*/
    @version_date datetime = NULL OUTPUT /*OUTPUT; for support*/
)
WITH RECOMPILE
AS
BEGIN
SET STATISTICS XML OFF;   
SET NOCOUNT ON;
SET XACT_ABORT ON;   
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

SELECT
    @version = '4.5',
    @version_date = '20240401';


IF @help = 1
BEGIN
    /*
    Introduction
    */
    SELECT
        introduction =
           'hi, i''m sp_PressureDetector!' UNION ALL
    SELECT 'you got me from https://github.com/erikdarlingdata/DarlingData/tree/main/sp_PressureDetector' UNION ALL
    SELECT 'i''m a lightweight tool for monitoring cpu and memory pressure' UNION ALL
    SELECT 'i''ll tell you: ' UNION ALL
    SELECT ' * what''s currently consuming memory on your server' UNION ALL
    SELECT ' * wait stats relevant to cpu, memory, and disk pressure, along with query performance' UNION ALL
    SELECT ' * how many worker threads and how much memory you have available' UNION ALL
    SELECT ' * running queries that are using cpu and memory' UNION ALL
    SELECT 'from your loving sql server consultant, erik darling: https://erikdarling.com';

    /*
    Parameters
    */
    SELECT
        parameter_name =
            ap.name,
        data_type = t.name,
        description =
            CASE
                ap.name
                WHEN N'@what_to_check' THEN N'areas to check for pressure'
                WHEN N'@skip_queries' THEN N'if you want to skip looking at running queries'
                WHEN N'@skip_plan_xml' THEN N'if you want to skip getting plan XML'
                WHEN N'@minimum_disk_latency_ms' THEN N'low bound for reporting disk latency'
                WHEN N'@cpu_utilization_threshold' THEN N'low bound for reporting high cpu utlization'
                WHEN N'@skip_waits' THEN N'skips waits when you do not need them on every run'
                WHEN N'@skip_perfmon' THEN N'skips perfmon counters when you do not need them on every run'
                WHEN N'@sample_seconds' THEN N'take a sample of your server''s metrics'
                WHEN N'@help' THEN N'how you got here'
                WHEN N'@debug' THEN N'prints dynamic sql, displays parameter and variable values, and table contents'
                WHEN N'@version' THEN N'OUTPUT; for support'
                WHEN N'@version_date' THEN N'OUTPUT; for support'
            END,
        valid_inputs =
            CASE
                ap.name
                WHEN N'@what_to_check' THEN N'"all", "cpu", and "memory"'
                WHEN N'@skip_queries' THEN N'0 or 1'
                WHEN N'@skip_plan_xml' THEN N'0 or 1'
                WHEN N'@minimum_disk_latency_ms' THEN N'a reasonable number of milliseconds for disk latency'
                WHEN N'@cpu_utilization_threshold' THEN N'a reasonable cpu utlization percentage'
                WHEN N'@skip_waits' THEN N'0 or 1'
                WHEN N'@skip_perfmon' THEN N'0 or 1'
                WHEN N'@sample_seconds' THEN N'a valid tinyint: 0-255'
                WHEN N'@help' THEN N'0 or 1'
                WHEN N'@debug' THEN N'0 or 1'
                WHEN N'@version' THEN N'none'
                WHEN N'@version_date' THEN N'none'
            END,
        defaults =
            CASE
                ap.name
                WHEN N'@what_to_check' THEN N'all'
                WHEN N'@skip_queries' THEN N'0'
                WHEN N'@skip_plan_xml' THEN N'0'
                WHEN N'@minimum_disk_latency_ms' THEN N'100'
                WHEN N'@cpu_utilization_threshold' THEN N'50'
                WHEN N'@skip_waits' THEN N'0'
                WHEN N'@skip_perfmon' THEN N'0'
                WHEN N'@sample_seconds' THEN N'0'
                WHEN N'@help' THEN N'0'
                WHEN N'@debug' THEN N'0'
                WHEN N'@version' THEN N'none; OUTPUT'
                WHEN N'@version_date' THEN N'none; OUTPUT'
            END
    FROM sys.all_parameters AS ap
    INNER JOIN sys.all_objects AS o
      ON ap.object_id = o.object_id
    INNER JOIN sys.types AS t
      ON  ap.system_type_id = t.system_type_id
      AND ap.user_type_id = t.user_type_id
    WHERE o.name = N'sp_PressureDetector'
    OPTION(MAXDOP 1, RECOMPILE);

    SELECT
        mit_license_yo =
           'i am MIT licensed, so like, do whatever'
  
    UNION ALL
  
    SELECT
        mit_license_yo =
            'see printed messages for full license';

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

    /*
    Fix parameters and check the values, etc.
    */
    SELECT
        @what_to_check = ISNULL(@what_to_check, 'all'),
        @skip_queries = ISNULL(@skip_queries, 0),
        @skip_plan_xml = ISNULL(@skip_plan_xml, 0),
        @minimum_disk_latency_ms = ISNULL(@minimum_disk_latency_ms, 100),
        @cpu_utilization_threshold = ISNULL(@cpu_utilization_threshold, 50),
        @skip_waits = ISNULL(@skip_waits, 0),
        @sample_seconds = ISNULL(@sample_seconds, 0),
        @help = ISNULL(@help, 0),
        @debug = ISNULL(@debug, 0);

    SELECT
        @what_to_check = LOWER(@what_to_check);

    IF @what_to_check NOT IN ('cpu', 'memory', 'all')
    BEGIN
        RAISERROR('@what_to_check was set to %s, setting to all', 0, 1, @what_to_check) WITH NOWAIT;
        
        SELECT
            @what_to_check = 'all';
    END;
    
    
    /*
    Declarations of Variablependence
    */
    IF @debug = 1
    BEGIN
        RAISERROR('Declaring variables and temporary tables', 0, 1) WITH NOWAIT;
    END;

    DECLARE
        @azure bit =
            CASE
                WHEN
                    CONVERT
                    (
                        integer,
                        SERVERPROPERTY('EngineEdition')
                    ) = 5
                THEN 1
                ELSE 0
            END,
        @pool_sql nvarchar(MAX) = N'',
        @pages_kb bit =
            CASE
                WHEN
                (
                    SELECT
                        COUNT_BIG(*)
                    FROM sys.all_columns AS ac
                    WHERE ac.object_id = OBJECT_ID(N'sys.dm_os_memory_clerks')
                    AND   ac.name = N'pages_kb'
                ) = 1
                THEN 1
                ELSE 0
            END,
        @mem_sql nvarchar(MAX) = N'',
        @helpful_new_columns bit =
            CASE
                WHEN
                (
                    SELECT
                        COUNT_BIG(*)
                    FROM sys.all_columns AS ac
                    WHERE ac.object_id = OBJECT_ID(N'sys.dm_exec_query_memory_grants')
                    AND   ac.name IN
                          (
                              N'reserved_worker_count',
                              N'used_worker_count'
                          )
                ) = 2
                THEN 1
                ELSE 0
            END,
        @cpu_sql nvarchar(MAX) = N'',
        @cool_new_columns bit =
            CASE
                WHEN
                (
                    SELECT
                        COUNT_BIG(*)
                    FROM sys.all_columns AS ac
                    WHERE ac.object_id = OBJECT_ID(N'sys.dm_exec_requests')
                    AND ac.name IN
                        (
                            N'dop',
                            N'parallel_worker_count'
                        )
                ) = 2
                THEN 1
                ELSE 0
            END,
        @reserved_worker_count_out varchar(10) = '0',
        @reserved_worker_count nvarchar(MAX) = N'
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

SELECT
    @reserved_worker_count_out =
        SUM(deqmg.reserved_worker_count)
FROM sys.dm_exec_query_memory_grants AS deqmg
OPTION(MAXDOP 1, RECOMPILE);
            ',
        @cpu_details nvarchar(MAX) = N'',
        @cpu_details_output xml = N'',
        @cpu_details_columns nvarchar(MAX) = N'',
        @cpu_details_select nvarchar(MAX) = N'
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

SELECT
    @cpu_details_output =
        (
            SELECT
                offline_cpus =
                    (SELECT COUNT_BIG(*) FROM sys.dm_os_schedulers dos WHERE dos.is_online = 0),
',
        @cpu_details_from nvarchar(MAX) = N'
            FROM sys.dm_os_sys_info AS osi
            FOR XML
                PATH(''cpu_details''),
                TYPE
        )
OPTION(MAXDOP 1, RECOMPILE);',
        @database_size_out nvarchar(MAX) = N'',
        @database_size_out_gb varchar(10) = '0',
        @total_physical_memory_gb bigint,
        @cpu_utilization xml = N'',
        @low_memory xml = N'',
        @disk_check nvarchar(MAX) = N'',
        @live_plans bit =
            CASE
                WHEN OBJECT_ID('sys.dm_exec_query_statistics_xml') IS NOT NULL
                THEN CONVERT(bit, 1)
                ELSE 0
            END,
        @waitfor varchar(20) =
            CONVERT   
            (   
                nvarchar(20),    
                DATEADD   
                (   
                    SECOND,    
                    @sample_seconds,    
                    '19000101'   
                 ),    
                 114   
            ),
        @pass tinyint = 
            CASE @sample_seconds
                 WHEN 0 
                 THEN 1
                 ELSE 0
            END,
        @prefix sysname = 
            CASE 
                WHEN @@SERVICENAME = N'MSSQLSERVER'
                THEN N'SQLServer:'
                ELSE N'MSSQL$' + 
                     @@SERVICENAME + 
                     N':'
            END +
            N'%',
        @memory_grant_cap xml

    DECLARE
        @waits table
    (
        hours_uptime integer,
        hours_cpu_time decimal(38,2),
        wait_type nvarchar(60),
        description nvarchar(60),
        hours_wait_time decimal(38,2),
        avg_ms_per_wait decimal(38,2),
        percent_signal_waits decimal(38,2),
        waiting_tasks_count_n bigint,
        sample_time datetime,
        sorting bigint,
        waiting_tasks_count AS 
            REPLACE
            (
                CONVERT
                (
                    nvarchar(30),
                    CONVERT
                    (
                        money,
                        waiting_tasks_count_n
                    ),
                    1
                ),
                N'.00',
                N''
            )
    );

    DECLARE
        @file_metrics table
    (
        hours_uptime integer,
        drive nvarchar(255),
        database_name nvarchar(128),
        database_file_details nvarchar(1000),
        file_size_gb decimal(38,2),
        total_gb_read decimal(38,2),
        total_mb_read decimal(38,2),
        total_read_count bigint,
        avg_read_stall_ms decimal(38,2),
        total_gb_written decimal(38,2),
        total_mb_written decimal(38,2),
        total_write_count bigint,
        avg_write_stall_ms decimal(38,2),
        io_stall_read_ms bigint,
        io_stall_write_ms bigint,
        sample_time datetime
    );

    DECLARE
        @dm_os_performance_counters table
        
    (
        sample_time datetime,
        object_name sysname,
        counter_name sysname,
        counter_name_clean sysname,
        instance_name sysname,
        cntr_value bigint,
        cntr_type bigint
    );

    DECLARE
        @threadpool_waits table
    (
        session_id smallint,
        wait_duration_ms bigint,
        threadpool_waits sysname
    );
  
    /*Use a GOTO to avoid writing all the code again*/
    DO_OVER:;
    
    /*
    Check to see if the DAC is enabled.
    If it's not, give people some helpful information.
    */
    IF 
    (
        @what_to_check = 'all' 
    AND @pass = 1
    )
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Checking DAC status, etc.', 0, 1) WITH NOWAIT;
        END;

        IF
        (
            SELECT
                c.value_in_use
            FROM sys.configurations AS c
            WHERE c.name = N'remote admin connections'
        ) = 0
        BEGIN
            SELECT
                message =
                    'This works a lot better on a troublesome server with the DAC enabled',
                command_to_run =
                    'EXEC sp_configure ''remote admin connections'', 1; RECONFIGURE;',
                how_to_use_the_dac =
                    'https://bit.ly/RemoteDAC';
        END;
      
        /*
        See if someone else is using the DAC.
        Return some helpful information if they are.
        */
        IF @azure = 0
        BEGIN
            IF EXISTS
            (
                SELECT
                    1/0
                FROM sys.endpoints AS ep
                JOIN sys.dm_exec_sessions AS ses
                  ON ep.endpoint_id = ses.endpoint_id
                WHERE ep.name = N'Dedicated Admin Connection'
                AND   ses.session_id <> @@SPID
            )
            BEGIN
                SELECT
                    dac_thief =
                       'who stole the dac?',
                    ses.session_id,
                    ses.login_time,
                    ses.host_name,
                    ses.program_name,
                    ses.login_name,
                    ses.nt_domain,
                    ses.nt_user_name,
                    ses.status,
                    ses.last_request_start_time,
                    ses.last_request_end_time
                FROM sys.endpoints AS ep
                JOIN sys.dm_exec_sessions AS ses
                  ON ep.endpoint_id = ses.endpoint_id
                WHERE ep.name = N'Dedicated Admin Connection'
                AND   ses.session_id <> @@SPID
                OPTION(MAXDOP 1, RECOMPILE);
            END;
        END;
    END; /*End DAC section*/

    /*
    Look at wait stats related to performance only
    */
    IF @skip_waits = 0
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Checking waits stats', 0, 1) WITH NOWAIT;
        END;

        INSERT
            @waits
        (
            hours_uptime,
            hours_cpu_time,
            wait_type,
            description,
            hours_wait_time,
            avg_ms_per_wait,
            percent_signal_waits,
            waiting_tasks_count_n,
            sample_time,
            sorting
        )
        SELECT
            hours_uptime =
                (
                    SELECT
                        DATEDIFF
                        (
                            HOUR,
                            osi.sqlserver_start_time,
                            SYSDATETIME()
                        )
                    FROM sys.dm_os_sys_info AS osi
                ),
            hours_cpu_time =
                (
                    SELECT            
                        CONVERT
                        (
                            decimal(38, 2),
                            SUM(wg.total_cpu_usage_ms) / 
                                CASE 
                                    WHEN
                                        @sample_seconds > 0
                                        THEN 1
                                        ELSE (1000. * 60. * 60.)
                                    END
                        )
                    FROM sys.dm_resource_governor_workload_groups AS wg
                ),
            dows.wait_type,
            description =
                CASE
                    WHEN dows.wait_type = N'PAGEIOLATCH_SH'
                    THEN N'Selects reading pages from disk into memory'
                    WHEN dows.wait_type = N'PAGEIOLATCH_EX'
                    THEN N'Modifications reading pages from disk into memory'
                    WHEN dows.wait_type = N'RESOURCE_SEMAPHORE'
                    THEN N'Queries waiting to get memory to run'
                    WHEN dows.wait_type = N'RESOURCE_SEMAPHORE_QUERY_COMPILE'
                    THEN N'Queries waiting to get memory to compile'
                    WHEN dows.wait_type = N'CXPACKET'
                    THEN N'Query parallelism'
                    WHEN dows.wait_type = N'CXCONSUMER'
                    THEN N'Query parallelism'
                    WHEN dows.wait_type = N'CXSYNC_PORT'
                    THEN N'Query parallelism'
                    WHEN dows.wait_type = N'CXSYNC_CONSUMER'
                    THEN N'Query parallelism'
                    WHEN dows.wait_type = N'SOS_SCHEDULER_YIELD'
                    THEN N'Query scheduling'
                    WHEN dows.wait_type = N'THREADPOOL'
                    THEN N'Potential worker thread exhaustion'
                    WHEN dows.wait_type = N'CMEMTHREAD'
                    THEN N'Tasks waiting on memory objects'
                    WHEN dows.wait_type = N'PAGELATCH_EX'
                    THEN N'Potential tempdb contention'
                    WHEN dows.wait_type = N'PAGELATCH_SH'
                    THEN N'Potential tempdb contention'
                    WHEN dows.wait_type = N'PAGELATCH_UP'
                    THEN N'Potential tempdb contention'
                    WHEN dows.wait_type LIKE N'LCK%'
                    THEN N'Queries waiting to acquire locks'
                    WHEN dows.wait_type = N'WRITELOG'
                    THEN N'Transaction Log writes'
                    WHEN dows.wait_type = N'LOGBUFFER'
                    THEN N'Transaction Log buffering'
                    WHEN dows.wait_type = N'LOG_RATE_GOVERNOR'
                    THEN N'Azure Transaction Log throttling'
                    WHEN dows.wait_type = N'POOL_LOG_RATE_GOVERNOR'
                    THEN N'Azure Transaction Log throttling'
                    WHEN dows.wait_type = N'SLEEP_TASK'
                    THEN N'Potential Hash spills'
                    WHEN dows.wait_type = N'BPSORT'
                    THEN N'Potential batch mode sort performance issues'
                    WHEN dows.wait_type = N'EXECSYNC'
                    THEN N'Potential eager index spool creation'
                    WHEN dows.wait_type = N'IO_COMPLETION'
                    THEN N'Potential sort spills'
                    WHEN dows.wait_type = N'ASYNC_NETWORK_IO'
                    THEN N'Potential client issues'
                    WHEN dows.wait_type = N'SLEEP_BPOOL_STEAL'
                    THEN N'Potential buffer pool pressure'
                    WHEN dows.wait_type = N'PWAIT_QRY_BPMEMORY'
                    THEN N'Potential batch mode performance issues'
                    WHEN dows.wait_type = N'HTREPARTITION'
                    THEN N'Potential batch mode performance issues'
                    WHEN dows.wait_type = N'HTBUILD'
                    THEN N'Potential batch mode performance issues'
                    WHEN dows.wait_type = N'HTMEMO'
                    THEN N'Potential batch mode performance issues'
                    WHEN dows.wait_type = N'HTDELETE'
                    THEN N'Potential batch mode performance issues'
                    WHEN dows.wait_type = N'HTREINIT'
                    THEN N'Potential batch mode performance issues'
                END,
            hours_wait_time =
                CASE 
                    WHEN @sample_seconds > 0
                    THEN dows.wait_time_ms
                    ELSE 
                        CONVERT
                        (
                            decimal(38, 2),
                            dows.wait_time_ms / (1000. * 60. * 60.)
                        )
                END,
            avg_ms_per_wait =
                ISNULL
                (
                   CONVERT
                   (
                       decimal(38, 2),
                       dows.wait_time_ms /
                           NULLIF
                           (
                               1.*
                               dows.waiting_tasks_count,
                               0.
                           )
                    ),
                    0.
                ),
            percent_signal_waits =
                CONVERT
                (
                    decimal(38, 2),
                    ISNULL
                    (
                        100.0 * dows.signal_wait_time_ms
                           / NULLIF(dows.wait_time_ms, 0),
                        0.
                    )
                ),
            dows.waiting_tasks_count,
            sample_time = 
                GETDATE(),
            sorting =
                ROW_NUMBER() OVER (ORDER BY dows.wait_time_ms DESC)
        FROM sys.dm_os_wait_stats AS dows
        WHERE
        (
          (      
                  dows.waiting_tasks_count > 0
              AND dows.wait_type <> N'SLEEP_TASK'
          )
        OR    
          (       
                 dows.wait_type = N'SLEEP_TASK'
             AND ISNULL(CONVERT(decimal(38, 2), dows.wait_time_ms /
                   NULLIF(1.* dows.waiting_tasks_count, 0.)), 0.) > 1000.
          )
        )
        AND
        (
            dows.wait_type IN
                 (
                     /*Disk*/
                     N'PAGEIOLATCH_SH',
                     N'PAGEIOLATCH_EX',
                     /*Memory*/
                     N'RESOURCE_SEMAPHORE',
                     N'RESOURCE_SEMAPHORE_QUERY_COMPILE',
                     N'CMEMTHREAD',
                     N'SLEEP_BPOOL_STEAL',
                     /*Parallelism*/
                     N'CXPACKET',
                     N'CXCONSUMER',
                     N'CXSYNC_PORT',
                     N'CXSYNC_CONSUMER',
                     /*CPU*/
                     N'SOS_SCHEDULER_YIELD',
                     N'THREADPOOL',
                     /*tempdb (potentially)*/
                     N'PAGELATCH_EX',
                     N'PAGELATCH_SH',
                     N'PAGELATCH_UP',
                     /*Transaction log*/
                     N'WRITELOG',
                     N'LOGBUFFER',
                     N'LOG_RATE_GOVERNOR',
                     N'POOL_LOG_RATE_GOVERNOR',
                     /*Some query performance stuff, spills and spools mostly*/
                     N'ASYNC_NETWORK_IO',
                     N'EXECSYNC',
                     N'IO_COMPLETION',                
                     N'SLEEP_TASK',
                     /*Batch Mode*/
                     N'HTBUILD',
                     N'HTDELETE',
                     N'HTMEMO',
                     N'HTREINIT',
                     N'HTREPARTITION',
                     N'PWAIT_QRY_BPMEMORY',
                     N'BPSORT'
                 )
            OR dows.wait_type LIKE N'LCK%' --Locking
        )
        ORDER BY
            dows.wait_time_ms DESC,
            dows.waiting_tasks_count DESC
        OPTION(MAXDOP 1, RECOMPILE);

        IF @sample_seconds = 0
        BEGIN
            SELECT
                w.wait_type,
                w.description,
                w.hours_uptime,
                w.hours_cpu_time,
                w.hours_wait_time,
                w.avg_ms_per_wait,
                w.percent_signal_waits,
                waiting_tasks_count =                
                    REPLACE
                    (
                        CONVERT
                        (
                            nvarchar(30),
                            CONVERT
                            (
                                money,
                                w.waiting_tasks_count
                            ),
                            1
                        ),
                        N'.00',
                        N''
                    )
            FROM @waits AS w
            ORDER BY
                w.sorting;
        END;

        IF 
        (
            @sample_seconds > 0
        AND @pass = 1
        )
        BEGIN
            SELECT
                w.wait_type,
                w.description,
                sample_cpu_time_seconds =
                    CONVERT
                    (
                        decimal(38,2),
                        (w2.hours_cpu_time - w.hours_cpu_time) / 1000.
                    ),
                wait_time_seconds = 
                    CONVERT
                    (
                        decimal(38,2),
                        (w2.hours_wait_time - w.hours_wait_time) / 1000.
                    ),
                avg_ms_per_wait =
                    CONVERT
                    (
                        decimal(38,1),
                        (w2.avg_ms_per_wait + w.avg_ms_per_wait) / 2
                    ),
                percent_signal_waits =
                    CONVERT
                    (
                        decimal(38,1),
                        (w2.percent_signal_waits + w.percent_signal_waits) / 2
                    ),
                waiting_tasks_count =                            
                    REPLACE
                    (
                        CONVERT
                        (
                            nvarchar(30),
                            CONVERT
                            (
                                money,
                                (w2.waiting_tasks_count_n - w.waiting_tasks_count_n)
                            ),
                            1
                        ),
                        N'.00',
                        N''
                    ),
                sample_seconds =
                    DATEDIFF(SECOND, w.sample_time, w2.sample_time)
            FROM @waits AS w
            JOIN @waits AS w2
              ON  w.wait_type = w2.wait_type
              AND w.sample_time < w2.sample_time
              AND (w2.waiting_tasks_count_n - w.waiting_tasks_count_n) > 0
            ORDER BY
                wait_time_seconds DESC;
        END;
    END;
    /*
    This section looks at disk metrics
    */
    IF @what_to_check = 'all'
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Checking file stats', 0, 1) WITH NOWAIT;
        END;

        SET @disk_check = N'
        SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
         
        SELECT
            hours_uptime =
                (
                    SELECT
                        DATEDIFF
                        (
                            HOUR,
                            osi.sqlserver_start_time,
                            SYSDATETIME()
                        )
                    FROM sys.dm_os_sys_info AS osi
                ),
            drive =
                CASE
                    WHEN f.physical_name LIKE N''http%''
                    THEN f.physical_name
                    ELSE
                        UPPER
                        (
                            LEFT
                            (
                                f.physical_name,
                                2
                            )
                        )
                    END,
            database_name =
                 DB_NAME(vfs.database_id),
            database_file_details =
                ISNULL
                (
                    f.name COLLATE DATABASE_DEFAULT,
                    N''''
                ) +
                SPACE(1) +
                ISNULL
                (
                    CASE f.type
                         WHEN 0
                         THEN N''(data file)''
                         WHEN 1
                         THEN N''(transaction log)''
                         WHEN 2
                         THEN N''(filestream)''
                         WHEN 4
                         THEN N''(full-text)''
                         ELSE QUOTENAME
                              (
                                  f.type_desc COLLATE DATABASE_DEFAULT,
                                  N''()''
                              )
                    END,
                    N''''
                ) +
                SPACE(1) +
                ISNULL
                (
                    QUOTENAME
                    (
                        f.physical_name COLLATE DATABASE_DEFAULT,
                        N''()''
                    ),
                    N''''
                ),
            file_size_gb =
                CONVERT
                (
                    decimal(38, 2),
                    vfs.size_on_disk_bytes / 1073741824.
                ),
            total_gb_read =
                CASE
                    WHEN vfs.num_of_bytes_read > 0
                    THEN CONVERT
                         (
                             decimal(38, 2),
                             vfs.num_of_bytes_read / 1073741824.
                         )
                    ELSE 0
                END,
            total_mb_read =
                CASE
                    WHEN vfs.num_of_bytes_read > 0
                    THEN CONVERT
                         (
                             decimal(38, 2),
                             vfs.num_of_bytes_read / 1048576.
                         )
                    ELSE 0
                END,                
            total_read_count =  
                vfs.num_of_reads,
            avg_read_stall_ms =
                CONVERT
                (
                    decimal(38, 2),
                    ISNULL
                    (
                        vfs.io_stall_read_ms / 
                          (NULLIF(vfs.num_of_reads, 0)), 
                        0
                    )
                ),
            total_gb_written =
                CASE
                    WHEN vfs.num_of_bytes_written > 0
                    THEN CONVERT
                         (
                             decimal(38, 2),
                             vfs.num_of_bytes_written / 1073741824.
                         )
                    ELSE 0
                END,
            total_mb_written =
                CASE
                    WHEN vfs.num_of_bytes_written > 0
                    THEN CONVERT
                         (
                             decimal(38, 2),
                             vfs.num_of_bytes_written / 1048576.
                         )
                    ELSE 0
                END,
            total_write_count =
                vfs.num_of_writes,
            avg_write_stall_ms =
                CONVERT
                (
                    decimal(38, 2),
                    ISNULL
                    (
                        vfs.io_stall_write_ms / 
                          (NULLIF(vfs.num_of_writes, 0)), 
                        0
                    )
                ),
            io_stall_read_ms,
            io_stall_write_ms,
            sample_time = 
                GETDATE()
        FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS vfs
        JOIN ' +
        CONVERT
        (
            nvarchar(MAX),
            CASE
                WHEN @azure = 1
                THEN N'sys.database_files AS f
          ON  vfs.file_id = f.file_id
          AND vfs.database_id = DB_ID()'
                ELSE N'sys.master_files AS f
          ON  vfs.file_id = f.file_id
          AND vfs.database_id = f.database_id'
        END +
        N'
        WHERE 
        (
             vfs.num_of_reads  > 0
          OR vfs.num_of_writes > 0
        );'
        );
      
        IF @debug = 1
        BEGIN
            PRINT SUBSTRING(@disk_check, 1, 4000);
            PRINT SUBSTRING(@disk_check, 4000, 8000);
        END;
      
        INSERT
            @file_metrics
        (
            hours_uptime,
            drive,
            database_name,
            database_file_details,
            file_size_gb,
            total_gb_read,
            total_mb_read,
            total_read_count,
            avg_read_stall_ms,
            total_gb_written,
            total_mb_written,
            total_write_count,
            avg_write_stall_ms,
            io_stall_read_ms,
            io_stall_write_ms,
            sample_time
        )
        EXEC sys.sp_executesql
            @disk_check;

        IF @sample_seconds = 0
        BEGIN
            WITH 
                file_metrics AS
            (
                SELECT
                    fm.hours_uptime,
                    fm.drive,
                    fm.database_name,
                    fm.database_file_details,
                    fm.file_size_gb,
                    fm.avg_read_stall_ms,
                    fm.avg_write_stall_ms,
                    fm.total_gb_read,
                    fm.total_gb_written,
                    total_read_count =
                        REPLACE
                        (
                            CONVERT
                            (
                                nvarchar(30),
                                CONVERT
                                (
                                    money,
                                    fm.total_read_count
                                ),
                                1
                            ),
                            N'.00',
                            N''
                        ),
                    total_write_count =
                        REPLACE
                        (
                            CONVERT
                            (
                                nvarchar(30),
                                CONVERT
                                (
                                    money,
                                    fm.total_write_count
                                ),
                                1
                            ),
                            N'.00',
                            N''
                        ),
                    total_avg_stall_ms = 
                        fm.avg_read_stall_ms +
                        fm.avg_write_stall_ms
                FROM @file_metrics AS fm
                WHERE fm.avg_read_stall_ms  > @minimum_disk_latency_ms
                OR    fm.avg_write_stall_ms > @minimum_disk_latency_ms
            )
            SELECT
                fm.drive,
                fm.database_name,
                fm.database_file_details,
                fm.hours_uptime,
                fm.file_size_gb,
                fm.avg_read_stall_ms,
                fm.avg_write_stall_ms,
                fm.total_avg_stall_ms,
                fm.total_gb_read,
                fm.total_gb_written,
                fm.total_read_count,
                fm.total_write_count
            FROM file_metrics AS fm
            
            UNION ALL
            
            SELECT
                drive = N'Nothing to see here',
                database_name = N'By default, only >100 ms latency is reported',
                database_file_details = N'Use the @minimum_disk_latency_ms parameter to adjust what you see',
                hours_uptime = 0,
                file_size_gb = 0,
                avg_read_stall_ms = 0,
                avg_write_stall_ms = 0,
                total_avg_stall = 0,
                total_gb_read = 0,
                total_gb_written = 0,
                total_read_count = N'0',
                total_write_count = N'0'
            WHERE NOT EXISTS
            (
                SELECT
                    1/0
                FROM file_metrics AS fm
            )
            ORDER BY
                total_avg_stall_ms DESC; 
        END;

        IF
        (
            @sample_seconds > 0
        AND @pass = 1
        )
        BEGIN
            WITH
                f AS
            (
                SELECT
                    fm.drive,
                    fm.database_name,
                    fm.database_file_details,
                    fm.file_size_gb,
                    avg_read_stall_ms =
                        CASE 
                            WHEN (fm2.total_read_count - fm.total_read_count) = 0
                            THEN 0.00
                            ELSE
                                CONVERT
                                (
                                    decimal(38, 2),                                    
                                    (fm2.io_stall_read_ms - fm.io_stall_read_ms) /
                                    (fm2.total_read_count  - fm.total_read_count) 
                                )
                        END,
                    avg_write_stall_ms =
                        CASE
                            WHEN (fm2.total_write_count - fm.total_write_count) = 0
                            THEN 0.00
                            ELSE
                                CONVERT
                                (
                                    decimal(38, 2),
                                    (fm2.io_stall_write_ms - fm.io_stall_write_ms) /
                                    (fm2.total_write_count  - fm.total_write_count) 
                                )
                        END,
                    total_avg_stall = 
                        CASE
                            WHEN (fm2.total_read_count  - fm.total_read_count) +
                                 (fm2.total_write_count - fm.total_write_count) = 0
                            THEN 0.00
                            ELSE
                                CONVERT
                                (
                                    decimal(38,2),
                                    (
                                        (fm2.io_stall_read_ms  - fm.io_stall_read_ms) +
                                        (fm2.io_stall_write_ms - fm.io_stall_write_ms) 
                                    ) /                                
                                    (
                                        (fm2.total_read_count  - fm.total_read_count) +
                                        (fm2.total_write_count - fm.total_write_count) 
                                    ) 
                                )
                        END,
                    total_mb_read =
                        (fm2.total_mb_read - fm.total_mb_read),
                    total_mb_written = 
                        (fm2.total_mb_written - fm.total_mb_written),                
                    total_read_count = 
                        (fm2.total_read_count - fm.total_read_count),
                    total_write_count = 
                        (fm2.total_write_count - fm.total_write_count),
                    sample_time_o =
                        fm.sample_time,
                    sample_time_t =
                        fm2.sample_time
                FROM @file_metrics AS fm
                JOIN @file_metrics AS fm2
                  ON  fm.drive = fm2.drive
                  AND fm.database_name = fm2.database_name
                  AND fm.database_file_details = fm2.database_file_details
                  AND fm.sample_time < fm2.sample_time
            )
            SELECT
                f.drive,
                f.database_name,
                f.database_file_details,
                f.file_size_gb,
                f.avg_read_stall_ms,
                f.avg_write_stall_ms,
                f.total_avg_stall,
                total_mb_read =
                    REPLACE
                    (
                        CONVERT
                        (
                            nvarchar(30),
                            CONVERT
                            (
                                money,
                                f.total_mb_read
                            ),
                            1
                        ),
                        N'.00',
                        N''
                    ),
                total_mb_written =
                    REPLACE
                    (
                        CONVERT
                        (
                            nvarchar(30),
                            CONVERT
                            (
                                money,
                                f.total_mb_written
                            ),
                            1
                        ),
                        N'.00',
                        N''
                    ),
                total_read_count =
                    REPLACE
                    (
                        CONVERT
                        (
                            nvarchar(30),
                            CONVERT
                            (
                                money,
                                f.total_read_count
                            ),
                            1
                        ),
                        N'.00',
                        N''
                    ),
                total_write_count =
                    REPLACE
                    (
                        CONVERT
                        (
                            nvarchar(30),
                            CONVERT
                            (
                                money,
                                f.total_write_count
                            ),
                            1
                        ),
                        N'.00',
                        N''
                    ),
                sample_seconds =
                    DATEDIFF(SECOND, f.sample_time_o, f.sample_time_t)
            FROM f
            WHERE 
            (
                 f.total_read_count  > 0
              OR f.total_write_count > 0
            )
            ORDER BY
                f.total_avg_stall DESC;
        END
    END; /*End file stats*/

    /*
    This section looks at perfmon stuff I care about
    */
    IF @skip_perfmon = 0
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Checking perfmon counters', 0, 1) WITH NOWAIT;
        END;

        WITH
            p AS
        (
            SELECT
                sample_time = 
                    CASE
                        WHEN @sample_seconds = 0
                        THEN 
                            (
                                SELECT 
                                    dosi.sqlserver_start_time 
                                FROM sys.dm_os_sys_info AS dosi
                            )
                        ELSE GETDATE()
                    END,
                object_name = 
                    RTRIM(LTRIM(dopc.object_name)),
                counter_name = 
                    RTRIM(LTRIM(dopc.counter_name)),
                counter_name_clean = 
                    REPLACE(RTRIM(LTRIM(dopc.counter_name)),' (ms)', ''),
                instance_name = 
                    RTRIM(LTRIM(dopc.instance_name)),
                dopc.cntr_value,
                dopc.cntr_type
            FROM sys.dm_os_performance_counters AS dopc
        )
        INSERT 
            @dm_os_performance_counters
        (
            sample_time,
            object_name,
            counter_name,
            counter_name_clean,
            instance_name,
            cntr_value,
            cntr_type
        )
        SELECT
            p.sample_time,
            p.object_name,
            p.counter_name,
            p.counter_name_clean,
            instance_name =
                CASE 
                    WHEN LEN(p.instance_name) > 0
                    THEN p.instance_name
                    ELSE N'_Total'
                END,
            p.cntr_value,
            p.cntr_type
        FROM p
        WHERE p.object_name LIKE @prefix
        AND   p.instance_name NOT IN 
        (
            N'internal', N'master', N'model', N'msdb', N'model_msdb', N'model_replicatedmaster', N'mssqlsystemresource'
        )
        AND   p.counter_name IN 
        (
            N'Forwarded Records/sec', N'Table Lock Escalations/sec', N'Page reads/sec', N'Page writes/sec', N'Checkpoint pages/sec', N'Requests completed/sec',
            N'Transactions/sec', N'Lock Requests/sec', N'Lock Wait Time (ms)', N'Lock Waits/sec', N'Number of Deadlocks/sec', N'Log Flushes/sec', N'Page lookups/sec',
            N'Granted Workspace Memory (KB)', N'Lock Memory (KB)', N'Memory Grants Pending', N'SQL Cache Memory (KB)', N'Background writer pages/sec',
            N'Stolen Server Memory (KB)', N'Target Server Memory (KB)', N'Total Server Memory (KB)', N'Lazy writes/sec', N'Readahead pages/sec',
            N'Batch Requests/sec', N'SQL Compilations/sec', N'SQL Re-Compilations/sec', N'Longest Transaction Running Time', N'Log Bytes Flushed/sec',
            N'Lock waits', N'Log buffer waits', N'Log write waits', N'Memory grant queue waits', N'Network IO waits', N'Log Flush Write Time (ms)',
            N'Non-Page latch waits', N'Page IO latch waits', N'Page latch waits', N'Thread-safe memory objects waits', N'Wait for the worker', 
            N'Active parallel threads', N'Active requests', N'Blocked tasks', N'Query optimizations/sec', N'Queued requests', N'Reduced memory grants/sec'
        );

        IF @sample_seconds = 0
        BEGIN
            WITH 
                p AS
            (
                SELECT
                    hours_uptime =
                        (
                            SELECT
                                DATEDIFF
                                (
                                    HOUR,
                                    dopc.sample_time,
                                    SYSDATETIME()
                                )
                        ),
                    dopc.object_name,
                    dopc.counter_name,
                    dopc.instance_name,
                    dopc.cntr_value,
                    total =
                        FORMAT(dopc.cntr_value, 'N0'),
                    total_per_second = 
                        FORMAT(dopc.cntr_value / DATEDIFF(SECOND, dopc.sample_time, GETDATE()), 'N0')
                FROM @dm_os_performance_counters AS dopc
            )
            SELECT
                p.object_name,
                p.counter_name,
                p.instance_name,
                p.hours_uptime,
                p.total,
                p.total_per_second
            FROM p
            WHERE p.cntr_value > 0
            ORDER BY
                p.object_name,
                p.counter_name,
                p.cntr_value DESC;
        END;

        IF 
        (
            @sample_seconds > 0
        AND @pass = 1
        )
        BEGIN
            WITH 
                p AS
            (
                SELECT
                    dopc.object_name,
                    dopc.counter_name,
                    dopc.instance_name,
                    first_cntr_value =
                        FORMAT(dopc.cntr_value, 'N0'),
                    second_cntr_value =
                        FORMAT(dopc2.cntr_value, 'N0'),
                    total_difference = 
                        FORMAT((dopc2.cntr_value - dopc.cntr_value), 'N0'),
                    total_difference_per_second = 
                        FORMAT((dopc2.cntr_value - dopc.cntr_value) / 
                         DATEDIFF(SECOND, dopc.sample_time, dopc2.sample_time), 'N0'),
                    sample_seconds = 
                        DATEDIFF(SECOND, dopc.sample_time, dopc2.sample_time),
                    first_sample_time = 
                        dopc.sample_time,
                    second_sample_time = 
                        dopc2.sample_time,
                    total_difference_i = 
                        (dopc2.cntr_value - dopc.cntr_value)
                FROM @dm_os_performance_counters AS dopc
                JOIN @dm_os_performance_counters AS dopc2
                  ON  dopc.object_name = dopc2.object_name
                  AND dopc.counter_name = dopc2.counter_name
                  AND dopc.instance_name = dopc2.instance_name
                  AND dopc.sample_time < dopc2.sample_time
                WHERE (dopc2.cntr_value - dopc.cntr_value) <> 0
            )
            SELECT
                p.object_name,
                p.counter_name,
                p.instance_name,
                p.first_cntr_value,
                p.second_cntr_value,
                p.total_difference,
                p.total_difference_per_second,
                p.sample_seconds
            FROM p
            ORDER BY
                p.object_name,
                p.counter_name,
                p.total_difference_i DESC;
        END;
    END; /*End Perfmon*/

    /*
    This section looks at tempdb config and usage
    */
    IF
    (
        @azure = 0
    AND @what_to_check = 'all'
    AND @pass = 1
    )
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Checking tempdb config and usage', 0, 1) WITH NOWAIT;
        END;

        SELECT
            tempdb_info =
                (
                    SELECT
                        tempdb_configuration =
                            (
                                SELECT
                                    total_data_files =
                                        COUNT_BIG(*),
                                    min_size_gb =
                                        MIN(mf.size * 8) / 1024 / 1024,
                                    max_size_gb =
                                        MAX(mf.size * 8) / 1024 / 1024,
                                    min_growth_increment_gb =
                                        MIN(mf.growth * 8) / 1024 / 1024,
                                    max_growth_increment_gb =
                                        MAX(mf.growth * 8) / 1024 / 1024,
                                    scheduler_total_count =
                                        (
                                            SELECT
                                                osi.cpu_count
                                            FROM sys.dm_os_sys_info AS osi
                                        )
                                FROM sys.master_files AS mf
                                WHERE mf.database_id = 2
                                AND   mf.type = 0
                                FOR XML
                                    PATH('tempdb_configuration'),
                                    TYPE
                            ),
                        tempdb_space_used =
                            (
                                SELECT
                                    free_space_gb =
                                        CONVERT
                                        (
                                            decimal(38, 2),
                                            SUM(d.unallocated_extent_page_count * 8.) / 1024. / 1024.
                                        ),
                                    user_objects_gb =
                                        CONVERT
                                        (
                                            decimal(38, 2),
                                            SUM(d.user_object_reserved_page_count * 8.) / 1024. / 1024.
                                        ),
                                    version_store_gb =
                                        CONVERT
                                        (
                                            decimal(38, 2),
                                            SUM(d.version_store_reserved_page_count * 8.) / 1024. / 1024.
                                        ),
                                    internal_objects_gb =
                                        CONVERT
                                        (
                                            decimal(38, 2),
                                            SUM(d.internal_object_reserved_page_count * 8.) / 1024. / 1024.
                                        )
                                FROM tempdb.sys.dm_db_file_space_usage AS d
                                WHERE d.database_id = 2
                                FOR XML
                                    PATH('tempdb_space_used'),
                                    TYPE
                            ),
                        tempdb_query_activity =
                            (
                                SELECT
                                    t.session_id,
                                    tempdb_allocations_gb =
                                        CONVERT
                                        (
                                            decimal(38, 2),
                                            SUM(t.tempdb_allocations * 8.) / 1024. / 1024.
                                        ),
                                    tempdb_current_gb =
                                        CONVERT
                                        (
                                            decimal(38, 2),
                                            SUM(t.tempdb_current * 8.) / 1024. / 1024.
                                        )
                                FROM
                                (
                                    SELECT
                                        t.session_id,
                                        tempdb_allocations =
                                            t.user_objects_alloc_page_count +
                                            t.internal_objects_alloc_page_count,
                                        tempdb_current =
                                            t.user_objects_alloc_page_count +
                                            t.internal_objects_alloc_page_count -
                                            t.user_objects_dealloc_page_count -
                                            t.internal_objects_dealloc_page_count
                                    FROM sys.dm_db_task_space_usage AS t
        
                                    UNION ALL
        
                                    SELECT
                                        s.session_id,
                                        tempdb_allocations =
                                            s.user_objects_alloc_page_count +
                                            s.internal_objects_alloc_page_count,
                                        tempdb_current =
                                            s.user_objects_alloc_page_count +
                                            s.internal_objects_alloc_page_count -
                                            s.user_objects_dealloc_page_count -
                                            s.internal_objects_dealloc_page_count
                                    FROM sys.dm_db_session_space_usage AS s
                                ) AS t
                                WHERE t.session_id > 50
                                GROUP BY
                                    t.session_id
                                HAVING
                                    (SUM(t.tempdb_allocations) * 8.) / 1024. > 0.
                                ORDER BY
                                    SUM(t.tempdb_allocations) DESC
                                FOR XML
                                    PATH('tempdb_query_activity'),
                                    TYPE
        
                            )
                        FOR XML
                            PATH('tempdb'),
                            TYPE
                )
        OPTION(RECOMPILE, MAXDOP 1);
    END; /*End tempdb check*/

    /*Memory info, utilization and usage*/
    IF 
    (
        @what_to_check IN ('all', 'memory')
    AND @pass = 1
    )
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Checking memory pressure', 0, 1) WITH NOWAIT;
        END;

        /*
        See buffer pool size, along with stolen memory
        and top non-buffer pool consumers
        */
        SET @pool_sql += N'
        SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

        SELECT
            memory_source =
                N''Buffer Pool Memory'',
            memory_consumer =
                domc.type,
            memory_consumed_gb =
                CONVERT
                (
                    decimal(38, 2),
                    SUM
                    (
                        ' +
            CONVERT
               (
                   nvarchar(MAX),
                          CASE @pages_kb
                               WHEN 1
                               THEN
                        N'domc.pages_kb + '
                               ELSE
                        N'domc.single_pages_kb +
                        domc.multi_pages_kb + '
                          END
                            )
                        + N'
                        domc.virtual_memory_committed_kb +
                        domc.awe_allocated_kb +
                        domc.shared_memory_committed_kb
                    ) / 1024. / 1024.
                )
        FROM sys.dm_os_memory_clerks AS domc
        WHERE domc.type = N''MEMORYCLERK_SQLBUFFERPOOL''
        AND   domc.memory_node_id < 64
        GROUP BY
            domc.type

        UNION ALL

        SELECT
            memory_source =
                N''Non-Buffer Pool Memory: Total'',
            memory_consumer =
                REPLACE
                (
                    dopc.counter_name,
                    N'' (KB)'',
                    N''''
                ),
            memory_consumed_gb =
                CONVERT
                (
                    decimal(38, 2),
                    dopc.cntr_value / 1024. / 1024.
                )
        FROM sys.dm_os_performance_counters AS dopc
        WHERE dopc.counter_name LIKE N''Stolen Server%''

        UNION ALL

        SELECT
            memory_source =
                N''Non-Buffer Pool Memory: Top Five'',
            memory_consumer =
                x.type,
            memory_consumed_gb =
                x.memory_used_gb
        FROM
        (
            SELECT TOP (5)
                domc.type,
                memory_used_gb =
                    CONVERT
                    (
                        decimal(38, 2),
                        SUM
                        (
                        ' + CASE @pages_kb
                                 WHEN 1
                                 THEN
                        N'    domc.pages_kb '
                                 ELSE
                        N'    domc.single_pages_kb +
                            domc.multi_pages_kb '
                            END + N'
                        ) / 1024. / 1024.
                    )
            FROM sys.dm_os_memory_clerks AS domc
            WHERE domc.type <> N''MEMORYCLERK_SQLBUFFERPOOL''
            GROUP BY
                domc.type
            HAVING
               SUM
               (
                   ' +
                      CASE @pages_kb
                           WHEN 1
                           THEN
                    N'domc.pages_kb '
                           ELSE
                    N'domc.single_pages_kb +
                    domc.multi_pages_kb '
                      END + N'
               ) / 1024. / 1024. > 0.
            ORDER BY
                memory_used_gb DESC
        ) AS x
        OPTION(MAXDOP 1, RECOMPILE);
        ';

        IF @debug = 1
        BEGIN
            PRINT @pool_sql;
        END;

        EXEC sys.sp_executesql
            @pool_sql;

        /*Checking total database size*/
        IF @azure = 1
        BEGIN
            SELECT
                @database_size_out = N'
                SELECT
                    @database_size_out_gb =
                        SUM
                        (
                            CONVERT
                            (
                                bigint,
                                df.size
                            )
                        ) * 8 / 1024 / 1024
                FROM sys.database_files AS df
                OPTION(MAXDOP 1, RECOMPILE);';
        END;
        IF @azure = 0
        BEGIN
            SELECT
                @database_size_out = N'
                SELECT
                    @database_size_out_gb =
                        SUM
                        (
                            CONVERT
                            (
                                bigint,
                                mf.size
                            )
                        ) * 8 / 1024 / 1024
                FROM sys.master_files AS mf
                WHERE mf.database_id > 4
                OPTION(MAXDOP 1, RECOMPILE);';
        END;

        EXEC sys.sp_executesql
            @database_size_out,
          N'@database_size_out_gb varchar(10) OUTPUT',
            @database_size_out_gb OUTPUT;

        /*Check physical memory in the server*/
        IF @azure = 0
        BEGIN
            SELECT
                @total_physical_memory_gb =
                    CEILING(dosm.total_physical_memory_kb / 1024. / 1024.)
                FROM sys.dm_os_sys_memory AS dosm;
        END;
        IF @azure = 1
        BEGIN
            SELECT
                @total_physical_memory_gb =
                    SUM(osi.committed_target_kb / 1024. / 1024.)
            FROM sys.dm_os_sys_info osi;
        END;

        /*Checking for low memory indicators*/
        SELECT
            @low_memory =
                x.low_memory
        FROM
        (
            SELECT
                sample_time =
                    CONVERT
                    (
                        datetime,
                        DATEADD
                        (
                            SECOND,
                            (t.timestamp - osi.ms_ticks) / 1000,
                            SYSDATETIME()
                        )
                    ),
                notification_type =
                    t.record.value('(/Record/ResourceMonitor/Notification)[1]', 'varchar(50)'),
                indicators_process =
                    t.record.value('(/Record/ResourceMonitor/IndicatorsProcess)[1]', 'int'),
                indicators_system =
                    t.record.value('(/Record/ResourceMonitor/IndicatorsSystem)[1]', 'int'),
                physical_memory_available_gb =
                    t.record.value('(/Record/MemoryRecord/AvailablePhysicalMemory)[1]', 'bigint') / 1024 / 1024,
                virtual_memory_available_gb =
                    t.record.value('(/Record/MemoryRecord/AvailableVirtualAddressSpace)[1]', 'bigint') / 1024 / 1024
            FROM sys.dm_os_sys_info AS osi
            CROSS JOIN
            (
                SELECT
                    dorb.timestamp,
                    record =
                        CONVERT(xml, dorb.record)
                FROM sys.dm_os_ring_buffers AS dorb
                WHERE dorb.ring_buffer_type = N'RING_BUFFER_RESOURCE_MONITOR'
            ) AS t
            WHERE 
              (
                  t.record.exist('(Record/ResourceMonitor/Notification[. = "RESOURCE_MEMPHYSICAL_LOW"])') = 1
               OR t.record.exist('(Record/ResourceMonitor/Notification[. = "RESOURCE_MEMVIRTUAL_LOW"])') = 1
              )
            AND
              (
                  t.record.exist('(Record/ResourceMonitor/IndicatorsProcess[. > 1])') = 1
               OR t.record.exist('(Record/ResourceMonitor/IndicatorsSystem[. > 1])') = 1
              )
            ORDER BY
                sample_time DESC
            FOR XML
                PATH('memory'),
                TYPE
        ) AS x (low_memory)
        OPTION(MAXDOP 1, RECOMPILE);

        IF @low_memory IS NULL
        BEGIN
            SELECT
                @low_memory =
                (
                    SELECT
                        N'No RESOURCE_MEMPHYSICAL_LOW indicators detected'
                    FOR XML
                        PATH(N'memory'),
                        TYPE
                );
        END;

        SELECT
            low_memory =
               @low_memory;
            
        SELECT
            @memory_grant_cap = 
            (
                SELECT 
                    group_name =
                        drgwg.name,
                    max_grant_percent = 
                        drgwg.request_max_memory_grant_percent
                FROM sys.dm_resource_governor_workload_groups AS drgwg
                FOR XML 
                    PATH(''), 
                    TYPE                 
            );

        IF @memory_grant_cap IS NULL
        BEGIN
            SELECT
                @memory_grant_cap = 
                (
                    
                    SELECT
                        x.*
                    FROM 
                    (
                        SELECT
                            group_name =
                                N'internal',
                            max_grant_percent =
                                25
                        
                        UNION ALL
                        
                        SELECT
                            group_name =
                                N'default',
                            max_grant_percent =
                                25
                    ) AS x
                    FOR XML 
                        PATH(''), 
                        TYPE  
                );
        END;

        SELECT
            deqrs.resource_semaphore_id,
            total_database_size_gb =
                @database_size_out_gb,
            total_physical_memory_gb =
                @total_physical_memory_gb,
            max_server_memory_gb =
                (
                    SELECT
                        CONVERT
                        (
                            bigint,
                            c.value_in_use
                        )
                    FROM sys.configurations AS c
                    WHERE c.name = N'max server memory (MB)'
                ) / 1024,
            max_memory_grant_cap =
                @memory_grant_cap,
            memory_model =
                (
                    SELECT
                        osi.sql_memory_model_desc
                    FROM sys.dm_os_sys_info AS osi
                ),
            target_memory_gb =
                CONVERT
                (
                    decimal(38, 2),
                    (deqrs.target_memory_kb / 1024. / 1024.)
                ),
            max_target_memory_gb =
                CONVERT(
                    decimal(38, 2),
                    (deqrs.max_target_memory_kb / 1024. / 1024.)
                ),
            total_memory_gb =
                CONVERT
                (
                    decimal(38, 2),
                    (deqrs.total_memory_kb / 1024. / 1024.)
                ),
            available_memory_gb =
                CONVERT
                (
                    decimal(38, 2),
                    (deqrs.available_memory_kb / 1024. / 1024.)
                ),
            granted_memory_gb =
                CONVERT
                (
                    decimal(38, 2),
                    (deqrs.granted_memory_kb / 1024. / 1024.)
                ),
            used_memory_gb =
                CONVERT
                (
                    decimal(38, 2),
                    (deqrs.used_memory_kb / 1024. / 1024.)
                ),
            deqrs.grantee_count,
            deqrs.waiter_count,
            deqrs.timeout_error_count,
            deqrs.forced_grant_count,
            wg.total_reduced_memory_grant_count,
            deqrs.pool_id
        FROM sys.dm_exec_query_resource_semaphores AS deqrs
        CROSS APPLY
        (
            SELECT TOP (1)
                total_reduced_memory_grant_count =
                    wg.total_reduced_memgrant_count
            FROM sys.dm_resource_governor_workload_groups AS wg
            WHERE wg.pool_id = deqrs.pool_id
            ORDER BY
                wg.total_reduced_memgrant_count DESC
        ) AS wg
        WHERE deqrs.max_target_memory_kb IS NOT NULL
        ORDER BY
            deqrs.pool_id
        OPTION(MAXDOP 1, RECOMPILE);
    END; /*End memory checks*/

    /*
    Track down queries currently asking for memory grants
    */
    IF
    (
        @skip_queries = 0
    AND @what_to_check IN ('all', 'memory')
    AND @pass = 1
    )
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Checking queries with memory grants', 0, 1) WITH NOWAIT;
        END;

        SET @mem_sql += N'
        SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
      
        SELECT
            deqmg.session_id,
            database_name =
                DB_NAME(deqp.dbid),
            [dd hh:mm:ss.mss] =
                RIGHT
                (
                    ''00'' +
                    CONVERT
                    (
                        varchar(10),
                        DATEDIFF
                        (
                            DAY,
                            deqmg.request_time,
                            SYSDATETIME()
                        )
                    ),
                    2
                ) +
                '' '' +
                CONVERT
                (
                    varchar(20),
                    CASE
                        WHEN
                            DATEDIFF
                            (
                                DAY,
                                deqmg.request_time,
                                SYSDATETIME()
                            ) >= 24
                        THEN
                            DATEADD
                            (
                                SECOND,
                                DATEDIFF
                                (
                                    SECOND,
                                    deqmg.request_time,
                                    SYSDATETIME()
                                ),
                                ''19000101''                           
                            )                      
                        ELSE
                            DATEADD
                            (
                                MILLISECOND,
                                DATEDIFF
                                (
                                    MILLISECOND,
                                    deqmg.request_time,
                                    SYSDATETIME()
                                ),
                                ''19000101''
                            )
                        END,
                        14
                ),
            query_text =
                (
                    SELECT
                        [processing-instruction(query)] =
                            SUBSTRING
                            (
                                REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                    dest.text COLLATE Latin1_General_BIN2,
                                NCHAR(31),N''?''),NCHAR(30),N''?''),NCHAR(29),N''?''),NCHAR(28),N''?''),NCHAR(27),N''?''),NCHAR(26),N''?''),NCHAR(25),N''?''),NCHAR(24),N''?''),NCHAR(23),N''?''),NCHAR(22),N''?''),
                                NCHAR(21),N''?''),NCHAR(20),N''?''),NCHAR(19),N''?''),NCHAR(18),N''?''),NCHAR(17),N''?''),NCHAR(16),N''?''),NCHAR(15),N''?''),NCHAR(14),N''?''),NCHAR(12),N''?''),
                                NCHAR(11),N''?''),NCHAR(8),N''?''),NCHAR(7),N''?''),NCHAR(6),N''?''),NCHAR(5),N''?''),NCHAR(4),N''?''),NCHAR(3),N''?''),NCHAR(2),N''?''),NCHAR(1),N''?''),NCHAR(0),N''''),
                                (der.statement_start_offset / 2) + 1,
                                (
                                    (
                                        CASE
                                            der.statement_end_offset
                                            WHEN -1
                                            THEN DATALENGTH(dest.text)
                                            ELSE der.statement_end_offset
                                        END
                                        - der.statement_start_offset
                                    ) / 2
                                ) + 1
                            )
                       FROM sys.dm_exec_requests AS der
                       WHERE der.session_id = deqmg.session_id
                            FOR XML
                                PATH(''''),
                                TYPE
                ),'
            + CONVERT
              (
                  nvarchar(MAX),
              CASE
                  WHEN @skip_plan_xml = 0
                  THEN N'
            deqp.query_plan,' +
                  CASE
                      WHEN @live_plans = 1
                      THEN N'
            live_query_plan =
                deqs.query_plan,'
                      ELSE N''
                  END
              END +
                      N'
            deqmg.request_time,
            deqmg.grant_time,
            wait_time_seconds =
                (deqmg.wait_time_ms / 1000.),
            requested_memory_gb =
                CONVERT(decimal(38, 2), (deqmg.requested_memory_kb / 1024. / 1024.)),
            granted_memory_gb =
                CONVERT(decimal(38, 2), (deqmg.granted_memory_kb / 1024. / 1024.)),
            used_memory_gb =
                CONVERT(decimal(38, 2), (deqmg.used_memory_kb / 1024. / 1024.)),
            max_used_memory_gb =
                CONVERT(decimal(38, 2), (deqmg.max_used_memory_kb / 1024. / 1024.)),
            ideal_memory_gb =
                CONVERT(decimal(38, 2), (deqmg.ideal_memory_kb / 1024. / 1024.)),
            required_memory_gb =
                CONVERT(decimal(38, 2), (deqmg.required_memory_kb / 1024. / 1024.)),
            deqmg.queue_id,
            deqmg.wait_order,
            deqmg.is_next_candidate,
            waits.wait_type,
            wait_duration_seconds =
                (waits.wait_duration_ms / 1000.),
            deqmg.dop,' +
                CASE
                    WHEN @helpful_new_columns = 1
                    THEN N'
            deqmg.reserved_worker_count,
            deqmg.used_worker_count,'
                    ELSE N''
                END + N'
            deqmg.plan_handle
        FROM sys.dm_exec_query_memory_grants AS deqmg
        OUTER APPLY
        (
            SELECT TOP (1)
                dowt.*
            FROM sys.dm_os_waiting_tasks AS dowt
            WHERE dowt.session_id = deqmg.session_id
            ORDER BY dowt.wait_duration_ms DESC
        ) AS waits
        OUTER APPLY sys.dm_exec_query_plan(deqmg.plan_handle) AS deqp
        OUTER APPLY sys.dm_exec_sql_text(deqmg.plan_handle) AS dest' +
            CASE
                WHEN @live_plans = 1
                THEN N'
        OUTER APPLY sys.dm_exec_query_statistics_xml(deqmg.plan_handle) AS deqs'
                ELSE N''
            END +
       N'
        WHERE deqmg.session_id <> @@SPID
        ORDER BY
            requested_memory_gb DESC,
            deqmg.request_time
        OPTION(MAXDOP 1, RECOMPILE);
        '
                  );
      
        IF @debug = 1
        BEGIN
            PRINT SUBSTRING(@mem_sql, 1, 4000);
            PRINT SUBSTRING(@mem_sql, 4000, 8000);
        END;
      
        EXEC sys.sp_executesql
            @mem_sql;
    END;

    /*
    Looking at CPU config and indicators
    */
    IF 
    (
        @what_to_check IN ('all', 'cpu')
    AND @pass = 1
    )
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Checking CPU config', 0, 1) WITH NOWAIT;
        END;

        IF @helpful_new_columns = 1
        BEGIN
            IF @debug = 1
            BEGIN
                PRINT @reserved_worker_count;
            END;

            EXEC sys.sp_executesql
                @reserved_worker_count,
              N'@reserved_worker_count_out varchar(10) OUTPUT',
                @reserved_worker_count_out OUTPUT;
        END;

        SELECT
            @cpu_details_columns += N'' +
                CASE
                    WHEN ac.name = N'socket_count'
                    THEN N'                osi.socket_count, ' + NCHAR(10)
                    WHEN ac.name = N'numa_node_count'
                    THEN N'                osi.numa_node_count, ' + NCHAR(10)
                    WHEN ac.name = N'cpu_count'
                    THEN N'                osi.cpu_count, ' + NCHAR(10)
                    WHEN ac.name = N'cores_per_socket'
                    THEN N'                osi.cores_per_socket, ' + NCHAR(10)
                    WHEN ac.name = N'hyperthread_ratio'
                    THEN N'                osi.hyperthread_ratio, ' + NCHAR(10)
                    WHEN ac.name = N'softnuma_configuration_desc'
                    THEN N'                osi.softnuma_configuration_desc, ' + NCHAR(10)
                    WHEN ac.name = N'scheduler_total_count'
                    THEN N'                osi.scheduler_total_count, ' + NCHAR(10)
                    WHEN ac.name = N'scheduler_count'
                    THEN N'                osi.scheduler_count, ' + NCHAR(10)
                    ELSE N''
                END
        FROM
        (
            SELECT
                ac.name
            FROM sys.all_columns AS ac
            WHERE ac.object_id = OBJECT_ID(N'sys.dm_os_sys_info')
            AND   ac.name IN
                  (
                      N'socket_count',
                      N'numa_node_count',
                      N'cpu_count',
                      N'cores_per_socket',
                      N'hyperthread_ratio',
                      N'softnuma_configuration_desc',
                      N'scheduler_total_count',
                      N'scheduler_count'
                  )
        ) AS ac
        OPTION(MAXDOP 1, RECOMPILE);

        SELECT
            @cpu_details =
                @cpu_details_select +
                SUBSTRING
                (
                    @cpu_details_columns,
                    1,
                    LEN(@cpu_details_columns) -3
                ) +
                @cpu_details_from;

        IF @debug = 1
        BEGIN
            PRINT @cpu_details;
        END;

        EXEC sys.sp_executesql
            @cpu_details,
          N'@cpu_details_output xml OUTPUT',
            @cpu_details_output OUTPUT;

        /*
        Checking for high CPU utilization periods
        */
        SELECT
            @cpu_utilization =
                x.cpu_utilization
        FROM
        (
            SELECT
                sample_time =
                    CONVERT
                    (
                        datetime,
                        DATEADD
                        (
                            SECOND,
                            (t.timestamp - osi.ms_ticks) / 1000,
                            SYSDATETIME()
                        )
                    ),
                sqlserver_cpu_utilization =
                    t.record.value('(Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]','int'),
                other_process_cpu_utilization =
                    (100 - t.record.value('(Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]','int')
                     - t.record.value('(Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]','int')),
                total_cpu_utilization =
                    (100 - t.record.value('(Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int'))
            FROM sys.dm_os_sys_info AS osi
            CROSS JOIN
            (
                SELECT
                    dorb.timestamp,
                    record =
                        CONVERT(xml, dorb.record)
                FROM sys.dm_os_ring_buffers AS dorb
                WHERE dorb.ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR'
            ) AS t
            WHERE t.record.exist('(Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization[.>= sql:variable("@cpu_utilization_threshold")])') = 1
            ORDER BY
                sample_time DESC
            FOR XML
                PATH('cpu_utilization'),
                TYPE
        ) AS x (cpu_utilization)
        OPTION(MAXDOP 1, RECOMPILE);

        IF @cpu_utilization IS NULL
        BEGIN
            SELECT
                @cpu_utilization =
                (
                    SELECT
                        N'No significant CPU usage data available.'
                    FOR XML
                        PATH(N'cpu_utilization'),
                        TYPE
                );
        END;

        SELECT
            cpu_details_output =
                @cpu_details_output,
            cpu_utilization_over_threshold =
                @cpu_utilization;      
      
        /*Thread usage*/
        SELECT
            total_threads =
                MAX(osi.max_workers_count),
            used_threads =
                SUM(dos.active_workers_count),
            available_threads =
                MAX(osi.max_workers_count) - SUM(dos.active_workers_count),
            reserved_worker_count =
                CASE @helpful_new_columns
                     WHEN 1
                     THEN ISNULL
                          (
                              @reserved_worker_count_out,
                              N'0'
                          )
                     ELSE N'N/A'
                END,
            threads_waiting_for_cpu =
                SUM(dos.runnable_tasks_count),
            requests_waiting_for_threads =
                SUM(dos.work_queue_count),
            current_workers =
                SUM(dos.current_workers_count),
            total_active_request_count =
                SUM(wg.active_request_count),
            total_queued_request_count =
                SUM(wg.queued_request_count),
            total_blocked_task_count =
                SUM(wg.blocked_task_count),
            total_active_parallel_thread_count =
                SUM(wg.active_parallel_thread_count),
            avg_runnable_tasks_count =
                AVG(dos.runnable_tasks_count),
            high_runnable_percent =
                MAX(ISNULL(r.high_runnable_percent, 0))
        FROM sys.dm_os_schedulers AS dos
        CROSS JOIN sys.dm_os_sys_info AS osi
        CROSS JOIN
        (
            SELECT
                wg.active_request_count,
                wg.queued_request_count,
                wg.blocked_task_count,
                wg.active_parallel_thread_count
            FROM sys.dm_resource_governor_workload_groups AS wg      
        ) AS wg
        OUTER APPLY
        (
            SELECT
                high_runnable_percent =
                    '' +
                    RTRIM(y.runnable_pct) +
                    '% of your queries are waiting to get on a CPU.'
            FROM
            (
                SELECT
                    x.total,
                    x.runnable,
                    runnable_pct =
                        CONVERT
                        (
                            decimal(38,2),
                            (
                                x.runnable / (1. * NULLIF(x.total, 0))
                            )
                        ) * 100.
                FROM
                (
                    SELECT
                        total =
                            COUNT_BIG(*),
                        runnable =
                            SUM
                            (
                                CASE
                                    WHEN der.status = N'runnable'
                                    THEN 1
                                    ELSE 0
                                END
                            )
                    FROM sys.dm_exec_requests AS der
                    WHERE der.session_id > 50
                ) AS x
            ) AS y
            WHERE y.runnable_pct >= 10
            AND   y.total >= 10
        ) AS r
        WHERE dos.status = N'VISIBLE ONLINE'
        OPTION(MAXDOP 1, RECOMPILE);


        /*
        Any current threadpool waits?
        */      
        INSERT
            @threadpool_waits
        (
            session_id,
            wait_duration_ms,
            threadpool_waits
        )
        SELECT
            dowt.session_id,
            dowt.wait_duration_ms,
            threadpool_waits =
                dowt.wait_type
        FROM sys.dm_os_waiting_tasks AS dowt
        WHERE dowt.wait_type = N'THREADPOOL'
        ORDER BY
            dowt.wait_duration_ms DESC
        OPTION(MAXDOP 1, RECOMPILE);

        IF @@ROWCOUNT = 0
        BEGIN
            SELECT
                THREADPOOL = N'No current THREADPOOL waits';
        END;
        ELSE
        BEGIN
            SELECT
                dowt.session_id,
                dowt.wait_duration_ms,
                threadpool_waits =
                    dowt.wait_type
            FROM sys.dm_os_waiting_tasks AS dowt
            WHERE dowt.wait_type = N'THREADPOOL'
            ORDER BY
                dowt.wait_duration_ms DESC
            OPTION(MAXDOP 1, RECOMPILE);
        END;


        /*
        Figure out who's using a lot of CPU
        */
        IF
        (
            @skip_queries = 0
        AND @what_to_check IN ('all', 'cpu')
        )
        BEGIN
            IF @debug = 1
            BEGIN
                RAISERROR('Checking CPU queries', 0, 1) WITH NOWAIT;
            END;

            SET @cpu_sql += N'
            SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
          
            SELECT
                der.session_id,
                database_name =
                    DB_NAME(der.database_id),
                [dd hh:mm:ss.mss] =
                    RIGHT
                    (
                        ''00'' +
                        CONVERT
                        (
                            varchar(10),
                            DATEDIFF
                            (
                                DAY,
                                der.start_time,
                                SYSDATETIME()
                            )
                        ),
                        2
                    ) +
                    '' '' +
                    CONVERT
                    (
                        varchar(20),
                        CASE
                            WHEN
                                DATEDIFF
                                (
                                    DAY,
                                    der.start_time,
                                    SYSDATETIME()
                                ) >= 24
                            THEN
                                DATEADD
                                (
                                    SECOND,
                                    DATEDIFF
                                    (
                                        SECOND,
                                        der.start_time,
                                        SYSDATETIME()
                                    ),
                                    ''19000101''                           
                                )                      
                            ELSE
                                DATEADD
                                (
                                    MILLISECOND,
                                    DATEDIFF
                                    (
                                        MILLISECOND,
                                        der.start_time,
                                        SYSDATETIME()
                                    ),
                                    ''19000101''
                                )
                            END,
                            14
                    ),
                query_text =
                    (
                        SELECT
                            [processing-instruction(query)] =
                                SUBSTRING
                                (
                                    REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                    REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                    REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                        dest.text COLLATE Latin1_General_BIN2,
                                    NCHAR(31),N''?''),NCHAR(30),N''?''),NCHAR(29),N''?''),NCHAR(28),N''?''),NCHAR(27),N''?''),NCHAR(26),N''?''),NCHAR(25),N''?''),NCHAR(24),N''?''),NCHAR(23),N''?''),NCHAR(22),N''?''),
                                    NCHAR(21),N''?''),NCHAR(20),N''?''),NCHAR(19),N''?''),NCHAR(18),N''?''),NCHAR(17),N''?''),NCHAR(16),N''?''),NCHAR(15),N''?''),NCHAR(14),N''?''),NCHAR(12),N''?''),
                                    NCHAR(11),N''?''),NCHAR(8),N''?''),NCHAR(7),N''?''),NCHAR(6),N''?''),NCHAR(5),N''?''),NCHAR(4),N''?''),NCHAR(3),N''?''),NCHAR(2),N''?''),NCHAR(1),N''?''),NCHAR(0),N''''),
                                    (der.statement_start_offset / 2) + 1,
                                    (
                                        (
                                            CASE
                                                der.statement_end_offset
                                                WHEN -1
                                                THEN DATALENGTH(dest.text)
                                                ELSE der.statement_end_offset
                                            END
                                            - der.statement_start_offset
                                        ) / 2
                                    ) + 1
                                )
                                FOR XML PATH(''''),
                                TYPE
                    ),'
                +
                CONVERT
                (
                    nvarchar(MAX),              
                CASE
                      WHEN @skip_plan_xml = 0
                      THEN N'
                deqp.query_plan,' +
                          CASE
                              WHEN @live_plans = 1
                              THEN
                           N'
                live_query_plan =
                    deqs.query_plan,'
                              ELSE N''
                          END
                      ELSE N''
                  END
                )
                + CONVERT
                  (
                      nvarchar(MAX),
                      N'
                statement_start_offset =
                    (der.statement_start_offset / 2) + 1,
                statement_end_offset =
                    (
                        (
                            CASE der.statement_end_offset
                                WHEN -1
                                THEN DATALENGTH(dest.text)
                                ELSE der.statement_end_offset
                            END
                            - der.statement_start_offset
                        ) / 2
                    ) + 1,
                der.plan_handle,
                der.status,
                der.blocking_session_id,
                der.wait_type,
                wait_time_ms = der.wait_time,
                der.wait_resource,
                cpu_time_ms = der.cpu_time,
                total_elapsed_time_ms = der.total_elapsed_time,
                der.reads,
                der.writes,
                der.logical_reads,
                granted_query_memory_gb =
                    CONVERT(decimal(38, 2), (der.granted_query_memory / 128. / 1024.)),
                transaction_isolation_level =
                    CASE
                        WHEN der.transaction_isolation_level = 0
                        THEN ''Unspecified''
                        WHEN der.transaction_isolation_level = 1
                        THEN ''Read Uncommitted''
                        WHEN der.transaction_isolation_level = 2
                        AND  EXISTS
                             (
                                 SELECT
                                     1/0
                                 FROM sys.dm_tran_active_snapshot_database_transactions AS trn
                                 WHERE der.session_id = trn.session_id
                                 AND   trn.is_snapshot = 0
                             )
                        THEN ''Read Committed Snapshot Isolation''
                        WHEN der.transaction_isolation_level = 2
                        AND  NOT EXISTS
                             (
                                 SELECT
                                     1/0
                                 FROM sys.dm_tran_active_snapshot_database_transactions AS trn
                                 WHERE der.session_id = trn.session_id
                                 AND   trn.is_snapshot = 0
                             )
                        THEN ''Read Committed''
                        WHEN der.transaction_isolation_level = 3
                        THEN ''Repeatable Read''
                        WHEN der.transaction_isolation_level = 4
                        THEN ''Serializable''
                        WHEN der.transaction_isolation_level = 5
                        THEN ''Snapshot''
                        ELSE ''???''
                    END'
                  )
                + CASE
                      WHEN @cool_new_columns = 1
                      THEN CONVERT
                           (
                               nvarchar(MAX),
                               N',
                der.dop,
                der.parallel_worker_count'
                           )
                      ELSE N''
                  END
                + CONVERT
                  (
                      nvarchar(MAX),
                      N'
            FROM sys.dm_exec_requests AS der
            OUTER APPLY sys.dm_exec_sql_text(der.plan_handle) AS dest
            OUTER APPLY sys.dm_exec_query_plan(der.plan_handle) AS deqp' +
                CASE
                    WHEN @live_plans = 1
                    THEN N'
            OUTER APPLY sys.dm_exec_query_statistics_xml(der.plan_handle) AS deqs'
                    ELSE N''
                END +
            N'
            WHERE der.session_id <> @@SPID
            AND   der.session_id >= 50
            AND   dest.text LIKE N''_%''
            ORDER BY '
            + CASE
                  WHEN @cool_new_columns = 1
                  THEN N'
                der.cpu_time DESC,
                der.parallel_worker_count DESC
            OPTION(MAXDOP 1, RECOMPILE);'
                  ELSE N'
                der.cpu_time DESC
            OPTION(MAXDOP 1, RECOMPILE);'
              END
                  );
          
            IF @debug = 1
            BEGIN
                PRINT SUBSTRING(@cpu_sql, 0, 4000);
                PRINT SUBSTRING(@cpu_sql, 4000, 8000);
            END;
          
            EXEC sys.sp_executesql
                @cpu_sql;
        END; /*End not skipping queries*/
    END; /*End CPU checks*/

    IF  
    (
        @sample_seconds > 0
    AND @pass = 0
    )
    BEGIN
        SELECT
            @pass = 1;

        WAITFOR DELAY @waitfor;
        GOTO DO_OVER;
    END;

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '@waits',
            x.*
        FROM @waits AS x
        ORDER BY
            x.wait_type
        OPTION(RECOMPILE);

        SELECT
            table_name = '@file_metrics',
            x.*
        FROM @file_metrics AS x
        ORDER BY
            x.database_name,
            x.sample_time
        OPTION(RECOMPILE);

        SELECT
            table_name = '@dm_os_performance_counters',
            x.*
        FROM @dm_os_performance_counters AS x
        ORDER BY
            x.counter_name
        OPTION(RECOMPILE);

        SELECT
            table_name = '@threadpool_waits',
            x.*
        FROM @threadpool_waits AS x
        ORDER BY
            x.wait_duration_ms DESC
        OPTION(RECOMPILE);
       
        SELECT
            pattern =
                'parameters',
            what_to_check =
                @what_to_check,
            skip_queries =
                @skip_queries,
            skip_plan_xml =
                @skip_plan_xml,
            minimum_disk_latency_ms =
                @minimum_disk_latency_ms,
            cpu_utilization_threshold =
                @cpu_utilization_threshold,
            skip_waits =
                @skip_waits,
            skip_perfmon =
                @skip_perfmon,
            sample_seconds =
                @sample_seconds,
            help =
                @help,
            debug =
                @debug,
            version =
                @version,
            version_date =
                @version_date;
               
        SELECT
            pattern =
                'variables',
            azure =
                @azure,
            pool_sql =
                @pool_sql,
            pages_kb =
                @pages_kb,
            mem_sql =
                @mem_sql,
            helpful_new_columns =
                @helpful_new_columns,
            cpu_sql =
                @cpu_sql,
            cool_new_columns =
                @cool_new_columns,
            reserved_worker_count_out =
                @reserved_worker_count_out,
            reserved_worker_count =
                @reserved_worker_count,
            cpu_details =
                @cpu_details,
            cpu_details_output =
                @cpu_details_output,
            cpu_details_columns =
                @cpu_details_columns,
            cpu_details_select =
                @cpu_details_select,
            cpu_details_from =
                @cpu_details_from,
            database_size_out =
                @database_size_out,
            database_size_out_gb =
                @database_size_out_gb,
            total_physical_memory_gb =
                @total_physical_memory_gb,
            cpu_utilization =
                @cpu_utilization,
            low_memory =
                @low_memory,
            disk_check =
                @disk_check,
            live_plans =
                @live_plans,
            pass =
                @pass,
            [waitfor] = 
                @waitfor,
            prefix =
                @prefix,
            memory_grant_cap =
                @memory_grant_cap;
       
    END; /*End Debug*/
END; /*Final End*/
GO
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

 ██████╗ ██╗   ██╗██╗ ██████╗██╗  ██╗██╗███████╗
██╔═══██╗██║   ██║██║██╔════╝██║ ██╔╝██║██╔════╝
██║   ██║██║   ██║██║██║     █████╔╝ ██║█████╗
██║▄▄ ██║██║   ██║██║██║     ██╔═██╗ ██║██╔══╝
╚██████╔╝╚██████╔╝██║╚██████╗██║  ██╗██║███████╗
 ╚══▀▀═╝  ╚═════╝ ╚═╝ ╚═════╝╚═╝  ╚═╝╚═╝╚══════╝

███████╗████████╗ ██████╗ ██████╗ ███████╗██╗
██╔════╝╚══██╔══╝██╔═══██╗██╔══██╗██╔════╝██║
███████╗   ██║   ██║   ██║██████╔╝█████╗  ██║
╚════██║   ██║   ██║   ██║██╔══██╗██╔══╝  ╚═╝
███████║   ██║   ╚██████╔╝██║  ██║███████╗██╗
╚══════╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝

Copyright 2024 Darling Data, LLC
https://www.erikdarling.com/

For usage and licensing details, run:
EXEC sp_QuickieStore
    @help = 1;

For working through errors:
EXEC sp_QuickieStore
    @debug = 1;

For performance issues:
EXEC sp_QuickieStore
    @troubleshoot_performance = 1;

For support, head over to GitHub:
https://github.com/erikdarlingdata/DarlingData

*/

IF OBJECT_ID('dbo.sp_QuickieStore') IS NULL
   BEGIN
       EXEC ('CREATE PROCEDURE dbo.sp_QuickieStore AS RETURN 138;');
   END;
GO

ALTER PROCEDURE
    dbo.sp_QuickieStore
(
    @database_name sysname = NULL, /*the name of the database you want to look at query store in*/
    @sort_order varchar(20) = 'cpu', /*the runtime metric you want to prioritize results by*/
    @top bigint = 10, /*the number of queries you want to pull back*/
    @start_date datetimeoffset(7) = NULL, /*the begin date of your search, will be converted to UTC internally*/
    @end_date datetimeoffset(7) = NULL, /*the end date of your search, will be converted to UTC internally*/
    @timezone sysname = NULL, /*user specified time zone to override dates displayed in results*/
    @execution_count bigint = NULL, /*the minimum number of executions a query must have*/
    @duration_ms bigint = NULL, /*the minimum duration a query must have to show up in results*/
    @execution_type_desc nvarchar(60) = NULL, /*the type of execution you want to filter by (success, failure)*/
    @procedure_schema sysname = NULL, /*the schema of the procedure you're searching for*/
    @procedure_name sysname = NULL, /*the name of the programmable object you're searching for*/
    @include_plan_ids nvarchar(4000) = NULL, /*a list of plan ids to search for*/
    @include_query_ids nvarchar(4000) = NULL, /*a list of query ids to search for*/
    @include_query_hashes nvarchar(4000) = NULL, /*a list of query hashes to search for*/
    @include_plan_hashes nvarchar(4000) = NULL, /*a list of query plan hashes to search for*/
    @include_sql_handles nvarchar(4000) = NULL, /*a list of sql handles to search for*/
    @ignore_plan_ids nvarchar(4000) = NULL, /*a list of plan ids to ignore*/
    @ignore_query_ids nvarchar(4000) = NULL, /*a list of query ids to ignore*/
    @ignore_query_hashes nvarchar(4000) = NULL, /*a list of query hashes to ignore*/
    @ignore_plan_hashes nvarchar(4000) = NULL, /*a list of query plan hashes to ignore*/
    @ignore_sql_handles nvarchar(4000) = NULL, /*a list of sql handles to ignore*/
    @query_text_search nvarchar(4000) = NULL, /*query text to search for*/
    @escape_brackets bit = 0, /*Set this bit to 1 to search for query text containing square brackets (common in .NET Entity Framework and other ORM queries)*/
    @escape_character nchar(1) = N'\', /*Sets the ESCAPE character for special character searches, defaults to the SQL standard backslash (\) character*/
    @only_queries_with_hints bit = 0, /*Set this bit to 1 to retrieve only queries with query hints*/
    @only_queries_with_feedback bit = 0, /*Set this bit to 1 to retrieve only queries with query feedback*/
    @only_queries_with_variants bit = 0, /*Set this bit to 1 to retrieve only queries with query variants*/
    @only_queries_with_forced_plans bit = 0, /*Set this bit to 1 to retrieve only queries with forced plans*/
    @only_queries_with_forced_plan_failures bit = 0, /*Set this bit to 1 to retrieve only queries with forced plan failures*/
    @wait_filter varchar(20) = NULL, /*wait category to search for; category details are below*/
    @query_type varchar(11) = NULL, /*filter for only ad hoc queries or only from queries from modules*/
    @expert_mode bit = 0, /*returns additional columns and results*/
    @format_output bit = 1, /*returns numbers formatted with commas*/
    @get_all_databases bit = 0, /*looks for query store enabled databases and returns combined results from all of them*/
    @workdays bit = 0, /*Use this to filter out weekends and after-hours queries*/
    @work_start time(0) = '9am', /*Use this to set a specific start of your work days*/
    @work_end time(0) = '5pm', /*Use this to set a specific end of your work days*/
    @help bit = 0, /*return available parameter details, etc.*/
    @debug bit = 0, /*prints dynamic sql, statement length, parameter and variable values, and raw temp table contents*/
    @troubleshoot_performance bit = 0, /*set statistics xml on for queries against views*/
    @version varchar(30) = NULL OUTPUT, /*OUTPUT; for support*/
    @version_date datetime = NULL OUTPUT /*OUTPUT; for support*/
)
WITH RECOMPILE
AS
BEGIN
SET STATISTICS XML OFF;
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

BEGIN TRY
/*
If this column doesn't exist, you're not on a good version of SQL Server
*/
IF NOT EXISTS
   (
       SELECT
           1/0
       FROM sys.all_columns AS ac
       WHERE ac.object_id = OBJECT_ID(N'sys.dm_exec_query_stats', N'V')
       AND   ac.name = N'total_spills'
   )
BEGIN
    RAISERROR('This procedure only runs on supported versions of SQL Server:
* 2016 SP2+
* 2017 CU3+
* 2019+
* Probably Azure?', 11, 1) WITH NOWAIT;

    RETURN;
END;

/*
These are for your outputs.
*/
SELECT
    @version = '4.5',
    @version_date = '20240401';

/*
Helpful section! For help.
*/
IF @help = 1
BEGIN
    /*
    Introduction
    */
    SELECT
        introduction =
           'hi, i''m sp_QuickieStore!' UNION ALL
    SELECT 'you got me from https://github.com/erikdarlingdata/DarlingData/tree/main/sp_QuickieStore' UNION ALL
    SELECT 'i can be used to quickly grab misbehaving queries from query store' UNION ALL
    SELECT 'the plan analysis is up to you; there will not be any XML shredding here' UNION ALL
    SELECT 'so what can you do, and how do you do it? read below!' UNION ALL
    SELECT  'from your loving sql server consultant, erik darling: https://erikdarling.com';

    /*
    Parameters
    */
    SELECT
        parameter_name =
            ap.name,
        data_type = t.name,
        description =
            CASE
                ap.name
                WHEN N'@database_name' THEN 'the name of the database you want to look at query store in'
                WHEN N'@sort_order' THEN 'the runtime metric you want to prioritize results by'
                WHEN N'@top' THEN 'the number of queries you want to pull back'
                WHEN N'@start_date' THEN 'the begin date of your search, will be converted to UTC internally'
                WHEN N'@end_date' THEN 'the end date of your search, will be converted to UTC internally'
                WHEN N'@timezone' THEN 'user specified time zone to override dates displayed in results'
                WHEN N'@execution_count' THEN 'the minimum number of executions a query must have'
                WHEN N'@duration_ms' THEN 'the minimum duration a query must have to show up in results'
                WHEN N'@execution_type_desc' THEN 'the type of execution you want to filter by (success, failure)'
                WHEN N'@procedure_schema' THEN 'the schema of the procedure you''re searching for'
                WHEN N'@procedure_name' THEN 'the name of the programmable object you''re searching for'
                WHEN N'@include_plan_ids' THEN 'a list of plan ids to search for'
                WHEN N'@include_query_ids' THEN 'a list of query ids to search for'
                WHEN N'@include_query_hashes' THEN 'a list of query hashes to search for'
                WHEN N'@include_plan_hashes' THEN 'a list of query plan hashes to search for'
                WHEN N'@include_sql_handles' THEN 'a list of sql handles to search for'
                WHEN N'@ignore_plan_ids' THEN 'a list of plan ids to ignore'
                WHEN N'@ignore_query_ids' THEN 'a list of query ids to ignore'
                WHEN N'@ignore_query_hashes' THEN 'a list of query hashes to ignore'
                WHEN N'@ignore_plan_hashes' THEN 'a list of query plan hashes to ignore'
                WHEN N'@ignore_sql_handles' THEN 'a list of sql handles to ignore'
                WHEN N'@query_text_search' THEN 'query text to search for'
                WHEN N'@escape_brackets' THEN 'Set this bit to 1 to search for query text containing square brackets (common in .NET Entity Framework and other ORM queries)'
                WHEN N'@escape_character' THEN 'Sets the ESCAPE character for special character searches, defaults to the SQL standard backslash (\) character'
                WHEN N'@only_queries_with_hints' THEN 'only return queries with query hints'
                WHEN N'@only_queries_with_feedback' THEN 'only return queries with query feedback'
                WHEN N'@only_queries_with_variants' THEN 'only return queries with query variants'
                WHEN N'@only_queries_with_forced_plans' THEN 'only return queries with forced plans'
                WHEN N'@only_queries_with_forced_plan_failures' THEN 'only return queries with forced plan failures'
                WHEN N'@wait_filter' THEN 'wait category to search for; category details are below'
                WHEN N'@query_type' THEN 'filter for only ad hoc queries or only from queries from modules'
                WHEN N'@expert_mode' THEN 'returns additional columns and results'
                WHEN N'@format_output' THEN 'returns numbers formatted with commas'
                WHEN N'@get_all_databases' THEN 'looks for query store enabled databases and returns combined results from all of them'
                WHEN N'@workdays' THEN 'use this to filter out weekends and after-hours queries'
                WHEN N'@work_start' THEN 'use this to set a specific start of your work days'
                WHEN N'@work_end' THEN 'use this to set a specific end of your work days'
                WHEN N'@help' THEN 'how you got here'
                WHEN N'@debug' THEN 'prints dynamic sql, statement length, parameter and variable values, and raw temp table contents'
                WHEN N'@troubleshoot_performance' THEN 'set statistics xml on for queries against views'
                WHEN N'@version' THEN 'OUTPUT; for support'
                WHEN N'@version_date' THEN 'OUTPUT; for support'
            END,
        valid_inputs =
            CASE
                ap.name
                WHEN N'@database_name' THEN 'a database name with query store enabled'
                WHEN N'@sort_order' THEN 'cpu, logical reads, physical reads, writes, duration, memory, tempdb, executions, recent'
                WHEN N'@top' THEN 'a positive integer between 1 and 9,223,372,036,854,775,807'
                WHEN N'@start_date' THEN 'January 1, 1753, through December 31, 9999'
                WHEN N'@end_date' THEN 'January 1, 1753, through December 31, 9999'
                WHEN N'@timezone' THEN 'SELECT tzi.* FROM sys.time_zone_info AS tzi;'
                WHEN N'@execution_count' THEN 'a positive integer between 1 and 9,223,372,036,854,775,807'
                WHEN N'@duration_ms' THEN 'a positive integer between 1 and 9,223,372,036,854,775,807'
                WHEN N'@execution_type_desc' THEN 'regular, aborted, exception'
                WHEN N'@procedure_schema' THEN 'a valid schema in your database'
                WHEN N'@procedure_name' THEN 'a valid programmable object in your database'
                WHEN N'@include_plan_ids' THEN 'a string; comma separated for multiple ids'
                WHEN N'@include_query_ids' THEN 'a string; comma separated for multiple ids'
                WHEN N'@include_query_hashes' THEN 'a string; comma separated for multiple hashes'
                WHEN N'@include_plan_hashes' THEN 'a string; comma separated for multiple hashes'
                WHEN N'@include_sql_handles' THEN 'a string; comma separated for multiple handles'
                WHEN N'@ignore_plan_ids' THEN 'a string; comma separated for multiple ids'
                WHEN N'@ignore_query_ids' THEN 'a string; comma separated for multiple ids'
                WHEN N'@ignore_query_hashes' THEN 'a string; comma separated for multiple hashes'
                WHEN N'@ignore_plan_hashes' THEN 'a string; comma separated for multiple hashes'
                WHEN N'@ignore_sql_handles' THEN 'a string; comma separated for multiple handles'
                WHEN N'@query_text_search' THEN 'a string; leading and trailing wildcards will be added if missing'
                WHEN N'@escape_brackets' THEN '0 or 1'
                WHEN N'@escape_character' THEN 'some escape character, SQL standard is backslash (\)'
                WHEN N'@only_queries_with_hints' THEN '0 or 1'
                WHEN N'@only_queries_with_feedback' THEN '0 or 1'
                WHEN N'@only_queries_with_variants' THEN '0 or 1'
                WHEN N'@only_queries_with_forced_plans' THEN '0 or 1'
                WHEN N'@only_queries_with_forced_plan_failures' THEN '0 or 1'
                WHEN N'@wait_filter' THEN 'cpu, lock, latch, buffer latch, buffer io, log io, network io, parallelism, memory'
                WHEN N'@query_type' THEN 'ad hoc, adhoc, proc, procedure, whatever.'
                WHEN N'@expert_mode' THEN '0 or 1'
                WHEN N'@format_output' THEN '0 or 1'
                WHEN N'@get_all_databases' THEN '0 or 1'
                WHEN N'@workdays' THEN '0 or 1'
                WHEN N'@work_start' THEN 'a time like 8am, 9am or something'
                WHEN N'@work_end' THEN 'a time like 5pm, 6pm or something'
                WHEN N'@help' THEN '0 or 1'
                WHEN N'@debug' THEN '0 or 1'
                WHEN N'@troubleshoot_performance' THEN '0 or 1'
                WHEN N'@version' THEN 'none; OUTPUT'
                WHEN N'@version_date' THEN 'none; OUTPUT'
            END,
        defaults =
            CASE
                ap.name
                WHEN N'@database_name' THEN 'NULL; current non-system database name if NULL'
                WHEN N'@sort_order' THEN 'cpu'
                WHEN N'@top' THEN '10'
                WHEN N'@start_date' THEN 'the last seven days'
                WHEN N'@end_date' THEN 'NULL'
                WHEN N'@timezone' THEN 'NULL'
                WHEN N'@execution_count' THEN 'NULL'
                WHEN N'@duration_ms' THEN 'NULL'
                WHEN N'@execution_type_desc' THEN 'NULL'
                WHEN N'@procedure_schema' THEN 'NULL; dbo if NULL and procedure name is not NULL'
                WHEN N'@procedure_name' THEN 'NULL'
                WHEN N'@include_plan_ids' THEN 'NULL'
                WHEN N'@include_query_ids' THEN 'NULL'
                WHEN N'@include_query_hashes' THEN 'NULL'
                WHEN N'@include_plan_hashes' THEN 'NULL'
                WHEN N'@include_sql_handles' THEN 'NULL'
                WHEN N'@ignore_plan_ids' THEN 'NULL'
                WHEN N'@ignore_query_ids' THEN 'NULL'
                WHEN N'@ignore_query_hashes' THEN 'NULL'
                WHEN N'@ignore_plan_hashes' THEN 'NULL'
                WHEN N'@ignore_sql_handles' THEN 'NULL'
                WHEN N'@query_text_search' THEN 'NULL'
                WHEN N'@escape_brackets' THEN '0'
                WHEN N'@escape_character' THEN '\'
                WHEN N'@only_queries_with_hints' THEN '0'
                WHEN N'@only_queries_with_feedback' THEN '0'
                WHEN N'@only_queries_with_variants' THEN '0'
                WHEN N'@only_queries_with_forced_plans' THEN '0'
                WHEN N'@only_queries_with_forced_plan_failures' THEN '0'
                WHEN N'@wait_filter' THEN 'NULL'
                WHEN N'@query_type' THEN 'NULL'
                WHEN N'@expert_mode' THEN '0'
                WHEN N'@format_output' THEN '1'
                WHEN N'@get_all_databases' THEN '0'
                WHEN N'@workdays' THEN '0'
                WHEN N'@work_start' THEN '9am'
                WHEN N'@work_end' THEN '5pm'
                WHEN N'@debug' THEN '0'
                WHEN N'@help' THEN '0'
                WHEN N'@troubleshoot_performance' THEN '0'
                WHEN N'@version' THEN 'none; OUTPUT'
                WHEN N'@version_date' THEN 'none; OUTPUT'
            END
    FROM sys.all_parameters AS ap
    INNER JOIN sys.all_objects AS o
      ON ap.object_id = o.object_id
    INNER JOIN sys.types AS t
      ON  ap.system_type_id = t.system_type_id
      AND ap.user_type_id = t.user_type_id
    WHERE o.name = N'sp_QuickieStore'
    OPTION(RECOMPILE);

    /*
    Wait categories: Only 2017+
    */
    IF EXISTS
    (
        SELECT
            1/0
        FROM sys.all_objects AS ao
        WHERE ao.name = N'query_store_wait_stats'
    )
    BEGIN
        SELECT
            wait_categories =
               'cpu (1): SOS_SCHEDULER_YIELD' UNION ALL
        SELECT 'lock (3): LCK_M_%' UNION ALL
        SELECT 'latch (4): LATCH_%' UNION ALL
        SELECT 'buffer latch (5): PAGELATCH_%' UNION ALL
        SELECT 'buffer io (6): PAGEIOLATCH_%' UNION ALL
        SELECT 'log io (14): LOGMGR, LOGBUFFER, LOGMGR_RESERVE_APPEND, LOGMGR_FLUSH, LOGMGR_PMM_LOG, CHKPT, WRITELOG' UNION ALL
        SELECT 'network io (15): ASYNC_NETWORK_IO, NET_WAITFOR_PACKET, PROXY_NETWORK_IO, EXTERNAL_SCRIPT_NETWORK_IOF' UNION ALL
        SELECT 'parallelism (16): CXPACKET, EXCHANGE, HT%, BMP%, BP%' UNION ALL
        SELECT 'memory (17): RESOURCE_SEMAPHORE, CMEMTHREAD, CMEMPARTITIONED, EE_PMOLOCK, MEMORY_ALLOCATION_EXT, RESERVED_MEMORY_ALLOCATION_EXT, MEMORY_GRANT_UPDATE';
    END;

    /*
    Results
    */
    SELECT
        results =
           'results returned at the end of the procedure:' UNION ALL
    SELECT REPLICATE('-', 100) UNION ALL
    SELECT 'Runtime Stats: data from query_store_runtime_stats, along with query plan, query text, wait stats (2017+, when enabled), and parent object' UNION ALL
    SELECT REPLICATE('-', 100) UNION ALL
    SELECT 'Compilation Stats (expert mode only): data from query_store_query about compilation metrics' UNION ALL
    SELECT REPLICATE('-', 100) UNION ALL
    SELECT 'Resource Stats (expert mode only): data from dm_exec_query_stats, when available' UNION ALL
    SELECT 'query store does not currently track some details about memory grants and thread usage' UNION ALL
    SELECT 'so i go back to a plan cache view to try to track it down' UNION ALL
    SELECT REPLICATE('-', 100) UNION ALL
    SELECT 'Query Store Plan Feedback (2022+, expert mode, or when using only_queries_with_feedback): Lists queries that have been adjusted based on automated feedback mechanisms' UNION ALL
    SELECT REPLICATE('-', 100) UNION ALL
    SELECT 'Query Store Hints (2022+, expert mode or when using @only_queries_with_hints): lists hints applied to queries from automated feedback mechanisms' UNION ALL
    SELECT REPLICATE('-', 100) UNION ALL
    SELECT 'Query Variants (2022+, expert mode or when using @only_queries_with_variants): lists plan variants from the Parameter Sensitive Plan feedback mechanism' UNION ALL
    SELECT REPLICATE('-', 100) UNION ALL
    SELECT 'Query Store Waits By Query (2017+, expert mode only): information about query duration and logged wait stats' UNION ALL
    SELECT 'it can sometimes be useful to compare query duration to query wait times' UNION ALL
    SELECT REPLICATE('-', 100) UNION ALL
    SELECT 'Query Store Waits Total (2017+, expert mode only): total wait stats for the chosen date range only' UNION ALL
    SELECT REPLICATE('-', 100) UNION ALL
    SELECT 'Query Replicas (2022+, expert mode only): lists plans forced on AG replicas' UNION ALL
    SELECT REPLICATE('-', 100) UNION ALL
    SELECT 'Query Store Options (expert mode only): details about current query store configuration';

    /*
    Limitations
    */
    SELECT
        limitations =
           'frigid shortcomings:'  UNION ALL
    SELECT 'you need to be on at least SQL Server 2016 SP2, 2017 CU3, or any higher version to run this' UNION ALL
    SELECT 'if you''re on azure sql db then you''ll need to be in compat level 130' UNION ALL
    SELECT 'i do not currently support synapse or edge or other memes, and azure sql db support is not guaranteed';

    /*
    License to F5
    */
    SELECT
        mit_license_yo =
           'i am MIT licensed, so like, do whatever'
    UNION ALL

    SELECT
        mit_license_yo =
            'see printed messages for full license';

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
END; /*End @help section*/

/*
These are the tables that we'll use to grab data from query store
It will be fun
You'll love it
*/

/*
Plans we'll be working on
*/
CREATE TABLE
    #distinct_plans
(
    plan_id bigint PRIMARY KEY
);

/*
Hold plan_ids for procedures we're searching
*/
CREATE TABLE
    #procedure_plans
(
    plan_id bigint PRIMARY KEY
);

/*
Hold plan_ids for ad hoc or procedures we're searching for
*/
CREATE TABLE
    #query_types
(
    plan_id bigint PRIMARY KEY
);

/*
Hold plan_ids for plans we want
*/
CREATE TABLE
    #include_plan_ids
(
    plan_id bigint PRIMARY KEY WITH (IGNORE_DUP_KEY = ON)
);

/*
Hold query_ids for plans we want
*/
CREATE TABLE
    #include_query_ids
(
    query_id bigint PRIMARY KEY
);

/*
Hold plan_ids for ignored plans
*/
CREATE TABLE
    #ignore_plan_ids
(
    plan_id bigint PRIMARY KEY WITH (IGNORE_DUP_KEY = ON)
);

/*
Hold query_ids for ignored plans
*/
CREATE TABLE
    #ignore_query_ids
(
    query_id bigint PRIMARY KEY
);

/*
Hold query hashes for plans we want
*/
CREATE TABLE
    #include_query_hashes
(
    query_hash_s varchar(131),
    query_hash AS
        CONVERT
        (
            binary(8),
            query_hash_s,
            1
        ) PERSISTED NOT NULL PRIMARY KEY
);

/*
Hold plan hashes for plans we want
*/
CREATE TABLE
    #include_plan_hashes
(
    plan_hash_s varchar(131),
    plan_hash AS
        CONVERT
        (
            binary(8),
            plan_hash_s,
            1
        ) PERSISTED NOT NULL PRIMARY KEY
);

/*
Hold query hashes for ignored plans
*/
CREATE TABLE
    #ignore_query_hashes
(
    query_hash_s varchar(131),
    query_hash AS
        CONVERT
        (
            binary(8),
            query_hash_s,
            1
        ) PERSISTED NOT NULL PRIMARY KEY
);

/*
Hold plan hashes for ignored plans
*/
CREATE TABLE
    #ignore_plan_hashes
(
    plan_hash_s varchar(131),
    plan_hash AS
        CONVERT
        (
            binary(8),
            plan_hash_s,
            1
        ) PERSISTED NOT NULL PRIMARY KEY
);

/*
Hold sql handles for plans we want
*/
CREATE TABLE
    #include_sql_handles
(
    sql_handle_s varchar(131),
    sql_handle AS
        CONVERT
        (
            varbinary(64),
            sql_handle_s,
            1
        ) PERSISTED NOT NULL PRIMARY KEY
);

/*
Hold sql handles for ignored plans
*/
CREATE TABLE
    #ignore_sql_handles
(
    sql_handle_s varchar(131),
    sql_handle AS
        CONVERT
        (
            varbinary(64),
            sql_handle_s,
            1
        ) PERSISTED NOT NULL PRIMARY KEY
);

/*
Hold plan_ids for only query with hints
*/
CREATE TABLE
    #only_queries_with_hints
(
    plan_id bigint PRIMARY KEY
);

/*
Hold plan_ids for only query with feedback
*/
CREATE TABLE
    #only_queries_with_feedback
(
    plan_id bigint PRIMARY KEY
);

/*
Hold plan_ids for only query with variants
*/
CREATE TABLE
    #only_queries_with_variants
(
    plan_id bigint PRIMARY KEY
);

/*
Hold plan_ids for forced plans and/or forced plan failures
I'm overloading this a bit for simplicity, since searching for
failures is just an extension of searching for forced plans
*/

CREATE TABLE
    #forced_plans_failures
(
    plan_id bigint PRIMARY KEY
);

/*
Hold plan_ids for matching query text
*/
CREATE TABLE
    #query_text_search
(
    plan_id bigint PRIMARY KEY
);

/*
Hold plan_ids for matching wait filter
*/
CREATE TABLE
    #wait_filter
(
    plan_id bigint PRIMARY KEY
);

/*
Index and statistics entries to avoid
*/
CREATE TABLE
    #maintenance_plans
(
    plan_id bigint PRIMARY KEY
);

/*
Query Store Setup
*/
CREATE TABLE
    #database_query_store_options
(
    database_id int NOT NULL,
    desired_state_desc nvarchar(60) NULL,
    actual_state_desc nvarchar(60) NULL,
    readonly_reason nvarchar(100) NULL,
    current_storage_size_mb bigint NULL,
    flush_interval_seconds bigint NULL,
    interval_length_minutes bigint NULL,
    max_storage_size_mb bigint NULL,
    stale_query_threshold_days bigint NULL,
    max_plans_per_query bigint NULL,
    query_capture_mode_desc nvarchar(60) NULL,
    capture_policy_execution_count int NULL,
    capture_policy_total_compile_cpu_time_ms bigint NULL,
    capture_policy_total_execution_cpu_time_ms bigint NULL,
    capture_policy_stale_threshold_hours int NULL,
    size_based_cleanup_mode_desc nvarchar(60) NULL,
    wait_stats_capture_mode_desc nvarchar(60) NULL
);

/*
Query Store Trouble
*/
CREATE TABLE
    #query_store_trouble
(
    database_id int NOT NULL,
    desired_state_desc nvarchar(60) NULL,
    actual_state_desc nvarchar(60) NULL,
    readonly_reason nvarchar(100) NULL,
    current_storage_size_mb bigint NULL,
    flush_interval_seconds bigint NULL,
    interval_length_minutes bigint NULL,
    max_storage_size_mb bigint NULL,
    stale_query_threshold_days bigint NULL,
    max_plans_per_query bigint NULL,
    query_capture_mode_desc nvarchar(60) NULL,
    size_based_cleanup_mode_desc nvarchar(60) NULL
);

/*
Plans and Plan information
*/
CREATE TABLE
    #query_store_plan
(
    database_id int NOT NULL,
    plan_id bigint NOT NULL,
    query_id bigint NOT NULL,
    all_plan_ids varchar(MAX),
    plan_group_id bigint NULL,
    engine_version nvarchar(32) NULL,
    compatibility_level smallint NOT NULL,
    query_plan_hash binary(8) NOT NULL,
    query_plan nvarchar(MAX) NULL,
    is_online_index_plan bit NOT NULL,
    is_trivial_plan bit NOT NULL,
    is_parallel_plan bit NOT NULL,
    is_forced_plan bit NOT NULL,
    is_natively_compiled bit NOT NULL,
    force_failure_count bigint NOT NULL,
    last_force_failure_reason_desc nvarchar(128) NULL,
    count_compiles bigint NULL,
    initial_compile_start_time datetimeoffset(7) NOT NULL,
    last_compile_start_time datetimeoffset(7) NULL,
    last_execution_time datetimeoffset(7) NULL,
    avg_compile_duration_ms float NULL,
    last_compile_duration_ms bigint NULL,
    plan_forcing_type_desc nvarchar(60) NULL,
    has_compile_replay_script bit NULL,
    is_optimized_plan_forcing_disabled bit NULL,
    plan_type_desc nvarchar(120) NULL
);

/*
Queries and Compile Information
*/
CREATE TABLE
    #query_store_query
(
    database_id int NOT NULL,
    query_id bigint NOT NULL,
    query_text_id bigint NOT NULL,
    context_settings_id bigint NOT NULL,
    object_id bigint NULL,
    object_name AS
        ISNULL
        (
            QUOTENAME
            (
                OBJECT_SCHEMA_NAME
                (
                    object_id,
                    database_id
                )
            ) +
            N'.' +
            QUOTENAME
            (
                OBJECT_NAME
                (
                    object_id,
                    database_id
                )
            ),
            N'Adhoc'
        ),
    batch_sql_handle varbinary(64) NULL,
    query_hash binary(8) NOT NULL,
    is_internal_query bit NOT NULL,
    query_parameterization_type_desc nvarchar(60) NULL,
    initial_compile_start_time datetimeoffset(7) NOT NULL,
    last_compile_start_time datetimeoffset(7) NULL,
    last_execution_time datetimeoffset(7) NULL,
    last_compile_batch_sql_handle varbinary(64) NULL,
    last_compile_batch_offset_start bigint NULL,
    last_compile_batch_offset_end bigint NULL,
    count_compiles bigint NULL,
    avg_compile_duration_ms float NULL,
    total_compile_duration_ms AS
        (count_compiles * avg_compile_duration_ms),
    last_compile_duration_ms bigint NULL,
    avg_bind_duration_ms float NULL,
    total_bind_duration_ms AS
        (count_compiles * avg_bind_duration_ms),
    last_bind_duration_ms bigint NULL,
    avg_bind_cpu_time_ms float NULL,
    total_bind_cpu_time_ms AS
        (count_compiles * avg_bind_cpu_time_ms),
    last_bind_cpu_time_ms bigint NULL,
    avg_optimize_duration_ms float NULL,
    total_optimize_duration_ms AS
        (count_compiles * avg_optimize_duration_ms),
    last_optimize_duration_ms bigint NULL,
    avg_optimize_cpu_time_ms float NULL,
    total_optimize_cpu_time_ms AS
        (count_compiles * avg_optimize_cpu_time_ms),
    last_optimize_cpu_time_ms bigint NULL,
    avg_compile_memory_mb float NULL,
    total_compile_memory_mb AS
        (count_compiles * avg_compile_memory_mb),
    last_compile_memory_mb bigint NULL,
    max_compile_memory_mb bigint NULL,
    is_clouddb_internal_query bit NULL
);

/*
Query Text And Columns From sys.dm_exec_query_stats
*/
CREATE TABLE
    #query_store_query_text
(
    database_id int NOT NULL,
    query_text_id bigint NOT NULL,
    query_sql_text xml NULL,
    statement_sql_handle varbinary(64) NULL,
    is_part_of_encrypted_module bit NOT NULL,
    has_restricted_text bit NOT NULL,
    total_grant_mb bigint NULL,
    last_grant_mb bigint NULL,
    min_grant_mb bigint NULL,
    max_grant_mb bigint NULL,
    total_used_grant_mb bigint NULL,
    last_used_grant_mb bigint NULL,
    min_used_grant_mb bigint NULL,
    max_used_grant_mb bigint NULL,
    total_ideal_grant_mb bigint NULL,
    last_ideal_grant_mb bigint NULL,
    min_ideal_grant_mb bigint NULL,
    max_ideal_grant_mb bigint NULL,
    total_reserved_threads bigint NULL,
    last_reserved_threads bigint NULL,
    min_reserved_threads bigint NULL,
    max_reserved_threads bigint NULL,
    total_used_threads bigint NULL,
    last_used_threads bigint NULL,
    min_used_threads bigint NULL,
    max_used_threads bigint NULL
);

/*
Figure it out.
*/
CREATE TABLE
    #dm_exec_query_stats
(
    statement_sql_handle varbinary(64) NOT NULL,
    total_grant_mb bigint NULL,
    last_grant_mb bigint NULL,
    min_grant_mb bigint NULL,
    max_grant_mb bigint NULL,
    total_used_grant_mb bigint NULL,
    last_used_grant_mb bigint NULL,
    min_used_grant_mb bigint NULL,
    max_used_grant_mb bigint NULL,
    total_ideal_grant_mb bigint NULL,
    last_ideal_grant_mb bigint NULL,
    min_ideal_grant_mb bigint NULL,
    max_ideal_grant_mb bigint NULL,
    total_reserved_threads bigint NULL,
    last_reserved_threads bigint NULL,
    min_reserved_threads bigint NULL,
    max_reserved_threads bigint NULL,
    total_used_threads bigint NULL,
    last_used_threads bigint NULL,
    min_used_threads bigint NULL,
    max_used_threads bigint NULL
);

/*
Runtime stats information
*/
CREATE TABLE
    #query_store_runtime_stats
(
    database_id int NOT NULL,
    runtime_stats_id bigint NOT NULL,
    plan_id bigint NOT NULL,
    runtime_stats_interval_id bigint NOT NULL,
    execution_type_desc nvarchar(60) NULL,
    first_execution_time datetimeoffset(7) NOT NULL,
    last_execution_time datetimeoffset(7) NOT NULL,
    count_executions bigint NOT NULL,
    executions_per_second AS
        ISNULL
        (
            count_executions /
                NULLIF
                (
                    DATEDIFF
                    (
                        SECOND,
                        first_execution_time,
                        last_execution_time
                    ),
                    0
                ),
                0
        ),
    avg_duration_ms float NULL,
    last_duration_ms bigint NOT NULL,
    min_duration_ms bigint NOT NULL,
    max_duration_ms bigint NOT NULL,
    total_duration_ms AS
        (avg_duration_ms * count_executions),
    avg_cpu_time_ms float NULL,
    last_cpu_time_ms bigint NOT NULL,
    min_cpu_time_ms bigint NOT NULL,
    max_cpu_time_ms bigint NOT NULL,
    total_cpu_time_ms AS
        (avg_cpu_time_ms * count_executions),
    avg_logical_io_reads_mb float NULL,
    last_logical_io_reads_mb bigint NOT NULL,
    min_logical_io_reads_mb bigint NOT NULL,
    max_logical_io_reads_mb bigint NOT NULL,
    total_logical_io_reads_mb AS
        (avg_logical_io_reads_mb * count_executions),
    avg_logical_io_writes_mb float NULL,
    last_logical_io_writes_mb bigint NOT NULL,
    min_logical_io_writes_mb bigint NOT NULL,
    max_logical_io_writes_mb bigint NOT NULL,
    total_logical_io_writes_mb AS
        (avg_logical_io_writes_mb * count_executions),
    avg_physical_io_reads_mb float NULL,
    last_physical_io_reads_mb bigint NOT NULL,
    min_physical_io_reads_mb bigint NOT NULL,
    max_physical_io_reads_mb bigint NOT NULL,
    total_physical_io_reads_mb AS
        (avg_physical_io_reads_mb * count_executions),
    avg_clr_time_ms float NULL,
    last_clr_time_ms bigint NOT NULL,
    min_clr_time_ms bigint NOT NULL,
    max_clr_time_ms bigint NOT NULL,
    total_clr_time_ms AS
        (avg_clr_time_ms * count_executions),
    last_dop bigint NOT NULL,
    min_dop bigint NOT NULL,
    max_dop bigint NOT NULL,
    avg_query_max_used_memory_mb float NULL,
    last_query_max_used_memory_mb bigint NOT NULL,
    min_query_max_used_memory_mb bigint NOT NULL,
    max_query_max_used_memory_mb bigint NOT NULL,
    total_query_max_used_memory_mb AS
        (avg_query_max_used_memory_mb * count_executions),
    avg_rowcount float NULL,
    last_rowcount bigint NOT NULL,
    min_rowcount bigint NOT NULL,
    max_rowcount bigint NOT NULL,
    total_rowcount AS
        (avg_rowcount * count_executions),
    avg_num_physical_io_reads_mb float NULL,
    last_num_physical_io_reads_mb bigint NULL,
    min_num_physical_io_reads_mb bigint NULL,
    max_num_physical_io_reads_mb bigint NULL,
    total_num_physical_io_reads_mb AS
        (avg_num_physical_io_reads_mb * count_executions),
    avg_log_bytes_used_mb float NULL,
    last_log_bytes_used_mb bigint NULL,
    min_log_bytes_used_mb bigint NULL,
    max_log_bytes_used_mb bigint NULL,
    total_log_bytes_used_mb AS
        (avg_log_bytes_used_mb * count_executions),
    avg_tempdb_space_used_mb float NULL,
    last_tempdb_space_used_mb bigint NULL,
    min_tempdb_space_used_mb bigint NULL,
    max_tempdb_space_used_mb bigint NULL,
    total_tempdb_space_used_mb AS
        (avg_tempdb_space_used_mb * count_executions),
    context_settings nvarchar(256) NULL
);

/*
Wait Stats, When Available (2017+)
*/
CREATE TABLE
    #query_store_wait_stats
(
    database_id int NOT NULL,
    plan_id bigint NOT NULL,
    wait_category_desc nvarchar(60) NOT NULL,
    total_query_wait_time_ms bigint NOT NULL,
    avg_query_wait_time_ms float NULL,
    last_query_wait_time_ms bigint NOT NULL,
    min_query_wait_time_ms bigint NOT NULL,
    max_query_wait_time_ms bigint NOT NULL
);

/*
Context is everything
*/
CREATE TABLE
    #query_context_settings
(
    database_id int NOT NULL,
    context_settings_id bigint NOT NULL,
    set_options varbinary(8) NULL,
    language_id smallint NOT NULL,
    date_format smallint NOT NULL,
    date_first tinyint NOT NULL,
    status varbinary(2) NULL,
    required_cursor_options int NOT NULL,
    acceptable_cursor_options int NOT NULL,
    merge_action_type smallint NOT NULL,
    default_schema_id int NOT NULL,
    is_replication_specific bit NOT NULL,
    is_contained varbinary(1) NULL
);

/*
Feed me Seymour
*/
CREATE TABLE
    #query_store_plan_feedback
(
    database_id int NOT NULL,
    plan_feedback_id bigint,
    plan_id bigint,
    feature_desc nvarchar(120),
    feedback_data nvarchar(MAX),
    state_desc nvarchar(120),
    create_time datetimeoffset(7),
    last_updated_time datetimeoffset(7)
);

/*
America's Most Hinted
*/
CREATE TABLE
    #query_store_query_hints
(
    database_id int NOT NULL,
    query_hint_id bigint,
    query_id bigint,
    query_hint_text nvarchar(MAX),
    last_query_hint_failure_reason_desc nvarchar(256),
    query_hint_failure_count bigint,
    source_desc nvarchar(256)
);

/*
Variant? Deviant? You decide!
*/
CREATE TABLE
    #query_store_query_variant
(
    database_id int NOT NULL,
    query_variant_query_id bigint,
    parent_query_id bigint,
    dispatcher_plan_id bigint
);

/*
Replicants
*/
CREATE TABLE
    #query_store_replicas
(
    database_id int NOT NULL,
    replica_group_id bigint,
    role_type smallint,
    replica_name nvarchar(1288)
);

/*
Location, location, location
*/
CREATE TABLE
    #query_store_plan_forcing_locations
(
    database_id int NOT NULL,
    plan_forcing_location_id bigint,
    query_id bigint,
    plan_id bigint,
    replica_group_id bigint
);

/*
Trouble Loves Me
*/
CREATE TABLE
    #troubleshoot_performance
(
    id bigint IDENTITY,
    current_table nvarchar(100),
    start_time datetime,
    end_time datetime,
    runtime_ms AS
        FORMAT
        (
            DATEDIFF
            (
                MILLISECOND,
                start_time,
                end_time
            ),
            'N0'
        )
);

/*GET ALL THOSE DATABASES*/
CREATE TABLE
    #databases
(
    database_name sysname PRIMARY KEY
);

/*
Try to be helpful by subbing in a database name if null
*/
IF
  (
      @database_name IS NULL
      AND LOWER(DB_NAME())
          NOT IN
          (
              N'master',
              N'model',
              N'msdb',
              N'tempdb',
              N'dbatools',
              N'dbadmin',
              N'dbmaintenance',
              N'rdsadmin',
              N'other_memes'
          )
      AND @get_all_databases = 0
  )
BEGIN
    SELECT
        @database_name =
            DB_NAME();
END;

/*
Variables for the variable gods
*/
DECLARE
    @azure bit,
    @engine int,
    @product_version int,
    @database_id int,
    @database_name_quoted sysname,
    @procedure_name_quoted sysname,
    @collation sysname,
    @new bit,
    @sql nvarchar(MAX),
    @isolation_level nvarchar(MAX),
    @parameters nvarchar(4000),
    @plans_top bigint,
    @queries_top bigint,
    @nc10 nvarchar(2),
    @where_clause nvarchar(MAX),
    @query_text_search_original_value nvarchar(4000),
    @procedure_exists bit,
    @query_store_exists bit,
    @query_store_trouble bit,
    @query_store_waits_enabled bit,
    @sql_2022_views bit,
    @ags_present bit,
    @string_split_ints nvarchar(1500),
    @string_split_strings nvarchar(1500),
    @current_table nvarchar(100),
    @troubleshoot_insert nvarchar(MAX),
    @troubleshoot_update nvarchar(MAX),
    @troubleshoot_info nvarchar(MAX),
    @rc bigint,
    @em tinyint,
    @fo tinyint,
    @start_date_original datetimeoffset(7),
    @end_date_original datetimeoffset(7),
    @utc_minutes_difference bigint,
    @utc_minutes_original bigint,
    @df integer,
    @work_start_utc time(0),
    @work_end_utc time(0);

/*
In cases where we are escaping @query_text_search and
looping over multiple databases, we need to make sure
to not escape the string more than once.

The solution is to reset to the original value each loop.
This therefore needs to be done before the cursor.
*/
IF
(
    @get_all_databases = 1
AND @escape_brackets = 1
)
BEGIN
    SELECT
         @query_text_search_original_value = @query_text_search;
END;

/*
This section is in a cursor whether we
hit one database, or multiple

I do all the variable assignment in the
cursor block because some of them
are assigned for the specific database
that is currently being looked at
*/

IF
(
SELECT
    CONVERT
    (
        sysname,
        SERVERPROPERTY('EngineEdition')
    )
) IN (5, 8)
BEGIN
    INSERT INTO
        #databases WITH(TABLOCK)
    (
        database_name
    )
    SELECT
        database_name =
            ISNULL(@database_name, DB_NAME())
    WHERE @get_all_databases = 0

    UNION ALL

    SELECT
        database_name =
            d.name
    FROM sys.databases AS d
    WHERE @get_all_databases = 1
    AND   d.is_query_store_on = 1
    AND   d.database_id > 4
    AND   d.state = 0
    AND   d.is_in_standby = 0
    AND   d.is_read_only = 0
    OPTION(RECOMPILE);
END
ELSE
BEGIN
    INSERT
        #databases WITH(TABLOCK)
    (
        database_name
    )
    SELECT
        database_name =
            ISNULL(@database_name, DB_NAME())
    WHERE @get_all_databases = 0

    UNION ALL

    SELECT
        database_name =
            d.name
    FROM sys.databases AS d
    WHERE @get_all_databases = 1
    AND   d.is_query_store_on = 1
    AND   d.database_id > 4
    AND   d.state = 0
    AND   d.is_in_standby = 0
    AND   d.is_read_only = 0
    AND   NOT EXISTS
    (
        SELECT
            1/0
        FROM sys.dm_hadr_availability_replica_states AS s
        JOIN sys.availability_databases_cluster AS c
          ON  s.group_id = c.group_id
          AND d.name = c.database_name
        WHERE s.is_local <> 1
        AND   s.role_desc <> N'PRIMARY'
        AND   DATABASEPROPERTYEX(c.database_name, N'Updateability') <> N'READ_WRITE'
    )
    OPTION(RECOMPILE);
END;

DECLARE
    database_cursor CURSOR
    LOCAL
    SCROLL
    DYNAMIC
    READ_ONLY
FOR
SELECT
    d.database_name
FROM #databases AS d;

OPEN database_cursor;

FETCH FIRST
FROM database_cursor
INTO @database_name;

WHILE @@FETCH_STATUS = 0
BEGIN
/*
Some variable assignment, because why not?
*/
IF @debug = 1
BEGIN
    RAISERROR('Starting analysis for database %s', 0, 1, @database_name) WITH NOWAIT;
END;

SELECT
    @azure =
        CASE
            WHEN
                CONVERT
                (
                    sysname,
                    SERVERPROPERTY('EDITION')
                ) = N'SQL Azure'
            THEN 1
            ELSE 0
        END,
    @engine =
        CONVERT
        (
            int,
            SERVERPROPERTY('ENGINEEDITION')
        ),
    @product_version =
        CONVERT
        (
            int,
            PARSENAME
            (
                CONVERT
                (
                    sysname,
                    SERVERPROPERTY('PRODUCTVERSION')
                ),
                4
            )
        ),
    @database_id =
        DB_ID(@database_name),
    @database_name_quoted =
        QUOTENAME(@database_name),
    @procedure_name_quoted =
         QUOTENAME(@database_name) +
         N'.' +
         QUOTENAME
         (
             ISNULL
             (
                 @procedure_schema,
                 N'dbo'
             )
         ) +
         N'.' +
         QUOTENAME(@procedure_name),
    @collation =
        CONVERT
        (
            sysname,
            DATABASEPROPERTYEX
            (
                @database_name,
                'Collation'
            )
        ),
    @new = 0,
    @sql = N'',
    @isolation_level =
        N'
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;',
    @parameters =
        N'@top bigint,
          @start_date datetimeoffset(7),
          @end_date datetimeoffset(7),
          @execution_count bigint,
          @duration_ms bigint,
          @execution_type_desc nvarchar(60),
          @database_id int,
          @queries_top bigint,
          @work_start_utc time(0),
          @work_end_utc time(0)',
    @plans_top =
        9223372036854775807,
    @queries_top =
        9223372036854775807,
    @nc10 = NCHAR(10),
    @where_clause = N'',
    @query_text_search =
        CASE
            WHEN @get_all_databases = 1 AND @escape_brackets = 1
            THEN @query_text_search_original_value
            ELSE @query_text_search
         END,
    @procedure_exists = 0,
    @query_store_exists = 0,
    @query_store_trouble = 0,
    @query_store_waits_enabled = 0,
    @sql_2022_views = 0,
    @ags_present = 0,
    @current_table = N'',
    @string_split_ints = N'
        SELECT DISTINCT
            ids =
                LTRIM
                (
                    RTRIM
                    (
                        ids.ids
                    )
                )
        FROM
        (
            SELECT
                ids =
                    x.x.value
                        (
                            ''(./text())[1]'',
                            ''bigint''
                        )
            FROM
            (
                SELECT
                    ids =
                        CONVERT
                        (
                            xml,
                            ''<x>'' +
                            REPLACE
                            (
                                REPLACE
                                (
                                    @ids,
                                    '','',
                                    ''</x><x>''
                                ),
                                '' '',
                                ''''
                            ) +
                            ''</x>''
                        ).query(''.'')
            ) AS ids
                CROSS APPLY ids.nodes(''x'') AS x (x)
        ) AS ids
        OPTION(RECOMPILE);',
    @string_split_strings = N'
        SELECT DISTINCT
            ids =
                LTRIM
                (
                    RTRIM
                    (
                        ids.ids
                    )
                )
        FROM
        (
            SELECT
                ids =
                    x.x.value
                        (
                            ''(./text())[1]'',
                            ''varchar(131)''
                        )
            FROM
            (
                SELECT
                    ids =
                        CONVERT
                        (
                            xml,
                            ''<x>'' +
                            REPLACE
                            (
                                REPLACE
                                (
                                    @ids,
                                    '','',
                                    ''</x><x>''
                                ),
                                '' '',
                                ''''
                            ) +
                            ''</x>''
                        ).query(''.'')
            ) AS ids
                CROSS APPLY ids.nodes(''x'') AS x (x)
        ) AS ids
        OPTION(RECOMPILE);',
    @troubleshoot_insert = N'
        INSERT
            #troubleshoot_performance WITH(TABLOCK)
        (
            current_table,
            start_time
        )
        VALUES
        (
            @current_table,
            GETDATE()
        )
        OPTION(RECOMPILE);',
    @troubleshoot_update = N'
        UPDATE
            tp
        SET
            tp.end_time = GETDATE()
        FROM #troubleshoot_performance AS tp
        WHERE tp.current_table = @current_table
        OPTION(RECOMPILE);',
    @troubleshoot_info = N'
        SELECT
            (
                SELECT
                    runtime_ms =
                        tp.runtime_ms,
                    current_table =
                        tp.current_table,
                    query_length =
                        FORMAT(LEN(@sql), ''N0''),
                    ''processing-instruction(statement_text)'' =
                        @sql
                FROM #troubleshoot_performance AS tp
                WHERE tp.current_table = @current_table
                FOR XML
                    PATH(N''''),
                    TYPE
            ).query(''.[1]'') AS current_query
        OPTION(RECOMPILE);',
    @rc = 0,
    @em = @expert_mode,
    @fo = @format_output,
    @start_date_original =
        ISNULL
        (
            @start_date,
            DATEADD
            (
                DAY,
                -7,
                DATEDIFF
                (
                    DAY,
                    '19000101',
                    SYSUTCDATETIME()
                )
            )
        ),
    @end_date_original =
        ISNULL
        (
            @end_date,
            DATEADD
            (
                DAY,
                1,
                DATEADD
                (
                    MINUTE,
                    0,
                    DATEDIFF
                    (
                        DAY,
                        '19000101',
                        SYSUTCDATETIME()
                    )
                )
            )
        ),
    @utc_minutes_difference =
        DATEDIFF
        (
            MINUTE,
            SYSDATETIME(),
            SYSUTCDATETIME()
        ),
    @utc_minutes_original =
        DATEDIFF
        (
            MINUTE,
            SYSUTCDATETIME(),
            SYSDATETIME()
        ),
    @df = @@DATEFIRST,
    @work_start_utc = @work_start,
    @work_end_utc = @work_end;

/*
Some parameters can't be NULL,
and some shouldn't be empty strings
*/
SELECT
    @sort_order =
        ISNULL(@sort_order, 'cpu'),
    @top =
        ISNULL(@top, 10),
    @expert_mode =
        ISNULL(@expert_mode, 0),
    @procedure_schema =
        NULLIF(@procedure_schema, ''),
    @procedure_name =
        NULLIF(@procedure_name, ''),
    @include_plan_ids =
        NULLIF(@include_plan_ids, ''),
    @include_query_ids =
        NULLIF(@include_query_ids, ''),
    @ignore_plan_ids =
        NULLIF(@ignore_plan_ids, ''),
    @ignore_query_ids =
        NULLIF(@ignore_query_ids, ''),
    @include_query_hashes =
        NULLIF(@include_query_hashes, ''),
    @include_plan_hashes =
        NULLIF(@include_plan_hashes, ''),
    @include_sql_handles =
        NULLIF(@include_sql_handles, ''),
    @ignore_query_hashes =
        NULLIF(@ignore_query_hashes, ''),
    @ignore_plan_hashes =
        NULLIF(@ignore_plan_hashes, ''),
    @ignore_sql_handles =
        NULLIF(@ignore_sql_handles, ''),
    @only_queries_with_hints =
        ISNULL(@only_queries_with_hints, 0),
    @only_queries_with_feedback =
        ISNULL(@only_queries_with_feedback, 0),
    @only_queries_with_variants =
        ISNULL(@only_queries_with_variants, 0),
    @only_queries_with_forced_plans =
        ISNULL(@only_queries_with_forced_plans, 0),
    @only_queries_with_forced_plan_failures =
        ISNULL(@only_queries_with_forced_plan_failures, 0),
    @wait_filter =
        NULLIF(@wait_filter, ''),
    @format_output =
        ISNULL(@format_output, 1),
    @help =
        ISNULL(@help, 0),
    @debug =
        ISNULL(@debug, 0),
    @troubleshoot_performance =
        ISNULL(@troubleshoot_performance, 0),
    @get_all_databases =
        ISNULL(@get_all_databases, 0),
    @workdays =
        ISNULL(@workdays, 0),
    /*
        doing start and end date last because they're more complicated
        if start or end date is null,
    */
    @start_date =
        CASE
            WHEN @start_date IS NULL
            THEN
                DATEADD
                (
                    DAY,
                    -7,
                    DATEDIFF
                    (
                        DAY,
                        '19000101',
                        SYSUTCDATETIME()
                    )
                )
            WHEN @start_date IS NOT NULL
            THEN
                DATEADD
                (
                    MINUTE,
                    @utc_minutes_difference,
                    @start_date
                )
        END,
    @end_date =
        CASE
            WHEN @end_date IS NULL
            THEN
                DATEADD
                (
                    DAY,
                    1,
                    DATEADD
                    (
                        MINUTE,
                        0,
                        DATEDIFF
                        (
                            DAY,
                            '19000101',
                            SYSUTCDATETIME()
                        )
                    )
                )
            WHEN @end_date IS NOT NULL
            THEN
                DATEADD
                (
                    MINUTE,
                    @utc_minutes_difference,
                    @end_date
                )
        END;

/*
I need to tweak this so the WHERE clause on the last execution column
works correctly as >= @start_date and < @end_date, otherwise there are no results
*/
IF @start_date >= @end_date
BEGIN
    SELECT
        @end_date =
            DATEADD
            (
                DAY,
                7,
                @start_date
            ),
        @end_date_original =
            DATEADD
            (
                DAY,
                1,
                @start_date_original
            );
END;

/*
Let's make sure things will work
*/

/*
Database are you there?
*/
IF
(
   @database_id IS NULL
OR @collation IS NULL
)
BEGIN
    RAISERROR('Database %s does not exist', 10, 1, @database_name) WITH NOWAIT;

    IF @get_all_databases = 0
    BEGIN
        RETURN;
    END;
END;

/*
Database what are you?
*/
IF
(
    @azure = 1
AND @engine NOT IN (5, 8)
)
BEGIN
    RAISERROR('Not all Azure offerings are supported, please try avoiding memes', 11, 1) WITH NOWAIT;
    RETURN;
END;

/*
Database are you compatible?
*/
IF
(
    @azure = 1
    AND EXISTS
        (
            SELECT
                1/0
             FROM sys.databases AS d
             WHERE d.database_id = @database_id
             AND   d.compatibility_level < 130
        )
)
BEGIN
    RAISERROR('Azure databases in compatibility levels under 130 are not supported', 11, 1) WITH NOWAIT;
    RETURN;
END;

/*
Sometimes sys.databases will report Query Store being on, but it's really not
*/
SELECT
    @current_table = 'checking query store existence',
    @sql = @isolation_level;

IF @troubleshoot_performance = 1
BEGIN

    EXEC sys.sp_executesql
        @troubleshoot_insert,
      N'@current_table nvarchar(100)',
        @current_table;

    SET STATISTICS XML ON;
END;

SELECT
    @sql += N'
SELECT
    @query_store_exists =
        CASE
            WHEN EXISTS
                 (
                     SELECT
                         1/0
                     FROM ' + @database_name_quoted + N'.sys.database_query_store_options AS dqso
                     WHERE
                     (
                          dqso.actual_state = 0
                       OR dqso.actual_state IS NULL
                     )
                 )
            OR   NOT EXISTS
                 (
                     SELECT
                         1/0
                     FROM ' + @database_name_quoted + N'.sys.database_query_store_options AS dqso
                 )
            THEN 0
            ELSE 1
        END
OPTION(RECOMPILE);' + @nc10;

IF @debug = 1
BEGIN
    PRINT LEN(@sql);
    PRINT @sql;
END;

EXEC sys.sp_executesql
    @sql,
  N'@query_store_exists bit OUTPUT',
    @query_store_exists OUTPUT;

IF @troubleshoot_performance = 1
BEGIN
    SET STATISTICS XML OFF;

    EXEC sys.sp_executesql
        @troubleshoot_update,
      N'@current_table nvarchar(100)',
        @current_table;

    EXEC sys.sp_executesql
        @troubleshoot_info,
      N'@sql nvarchar(max),
        @current_table nvarchar(100)',
        @sql,
        @current_table;
END;

IF @query_store_exists = 0
BEGIN
    RAISERROR('Query Store doesn''t seem to be enabled for database: %s', 10, 1, @database_name) WITH NOWAIT;

    IF @get_all_databases = 0
    BEGIN
        RETURN;
    END;
END;

/*
If Query Store is enabled, but in read only mode for some reason, return some information about why
*/
SELECT
    @current_table = 'checking for query store trouble',
    @sql = @isolation_level;

IF @troubleshoot_performance = 1
BEGIN

    EXEC sys.sp_executesql
        @troubleshoot_insert,
      N'@current_table nvarchar(100)',
        @current_table;

    SET STATISTICS XML ON;
END;

SELECT
    @sql += N'
SELECT
    database_id =
        @database_id,
    desired_state_desc,
    actual_state_desc,
    readonly_reason =
        CASE dqso.readonly_reason
             WHEN 0
             THEN ''None''
             WHEN 2
             THEN ''Database in single user mode''
             WHEN 4
             THEN ''Database is in emergency mode''
             WHEN 8
             THEN ''Database is AG secondary''
             WHEN 65536
             THEN ''Reached max size: '' +
                  FORMAT(dqso.current_storage_size_mb, ''N0'') +
                  '' of '' +
                  FORMAT(dqso.max_storage_size_mb, ''N0'') +
                  ''.''
             WHEN 131072
             THEN ''The number of different statements in Query Store has reached the internal memory limit''
             WHEN 262144
             THEN ''Size of in-memory items waiting to be persisted on disk has reached the internal memory limit''
             WHEN 524288
             THEN ''Database has reached disk size limit''
             ELSE ''WOAH''
        END,
    current_storage_size_mb,
    flush_interval_seconds,
    interval_length_minutes,
    max_storage_size_mb,
    stale_query_threshold_days,
    max_plans_per_query,
    query_capture_mode_desc,
    size_based_cleanup_mode_desc
FROM ' + @database_name_quoted + N'.sys.database_query_store_options AS dqso
WHERE
(
     dqso.desired_state <> 4
  OR dqso.readonly_reason <> 8
)
AND
(
      dqso.desired_state = 1
   OR dqso.actual_state IN (1, 3)
   OR dqso.desired_state <> dqso.actual_state
)
OPTION(RECOMPILE);' + @nc10;

IF @debug = 1
BEGIN
    PRINT LEN(@sql);
    PRINT @sql;
END;

INSERT
    #query_store_trouble WITH (TABLOCK)
(
    database_id,
    desired_state_desc,
    actual_state_desc,
    readonly_reason,
    current_storage_size_mb,
    flush_interval_seconds,
    interval_length_minutes,
    max_storage_size_mb,
    stale_query_threshold_days,
    max_plans_per_query,
    query_capture_mode_desc,
    size_based_cleanup_mode_desc
)
EXEC sys.sp_executesql
    @sql,
  N'@database_id integer',
    @database_id;

IF @@ROWCOUNT > 0
BEGIN
    SELECT
        @query_store_trouble = 1;
END;

IF @troubleshoot_performance = 1
BEGIN
    SET STATISTICS XML OFF;

    EXEC sys.sp_executesql
        @troubleshoot_update,
      N'@current_table nvarchar(100)',
        @current_table;

    EXEC sys.sp_executesql
        @troubleshoot_info,
      N'@sql nvarchar(max),
        @current_table nvarchar(100)',
        @sql,
        @current_table;
END;

IF @query_store_trouble = 1
BEGIN
    SELECT
        query_store_trouble =
             'Query Store may be in a disagreeable state',
        database_name =
            DB_NAME(qst.database_id),
        qst.desired_state_desc,
        qst.actual_state_desc,
        qst.readonly_reason,
        qst.current_storage_size_mb,
        qst.flush_interval_seconds,
        qst.interval_length_minutes,
        qst.max_storage_size_mb,
        qst.stale_query_threshold_days,
        qst.max_plans_per_query,
        qst.query_capture_mode_desc,
        qst.size_based_cleanup_mode_desc
    FROM #query_store_trouble AS qst
    OPTION(RECOMPILE);
END;

/*
If you specified a procedure name, we need to figure out if there are any plans for it available
*/
IF @procedure_name IS NOT NULL
BEGIN
    SELECT
        @current_table = 'checking procedure existence',
        @sql = @isolation_level;

    IF @troubleshoot_performance = 1
    BEGIN
        EXEC sys.sp_executesql
            @troubleshoot_insert,
          N'@current_table nvarchar(100)',
            @current_table;

        SET STATISTICS XML ON;
    END;

    SELECT
        @sql += N'
SELECT
    @procedure_exists =
        CASE
            WHEN EXISTS
                 (
                     SELECT
                         1/0
                     FROM ' + @database_name_quoted + N'.sys.query_store_query AS qsq
                     WHERE qsq.object_id = OBJECT_ID(@procedure_name_quoted)
                 )
            THEN 1
            ELSE 0
        END
OPTION(RECOMPILE);' + @nc10;

    IF @debug = 1
    BEGIN
        PRINT LEN(@sql);
        PRINT @sql;
    END;

    EXEC sys.sp_executesql
        @sql,
      N'@procedure_exists bit OUTPUT,
        @procedure_name_quoted sysname',
        @procedure_exists OUTPUT,
        @procedure_name_quoted;

    IF @troubleshoot_performance = 1
    BEGIN
        SET STATISTICS XML OFF;

        EXEC sys.sp_executesql
            @troubleshoot_update,
          N'@current_table nvarchar(100)',
            @current_table;

        EXEC sys.sp_executesql
            @troubleshoot_info,
          N'@sql nvarchar(max),
            @current_table nvarchar(100)',
            @sql,
            @current_table;
    END;

    IF
    (
        @procedure_exists = 0
    AND @get_all_databases = 1
    )
    BEGIN
        RAISERROR('The stored procedure %s does not appear to have any entries in Query Store for database %s
Check that you spelled everything correctly and you''re in the right database
We will skip this database and continue',
                       10, 1, @procedure_name, @database_name) WITH NOWAIT;
        FETCH NEXT
        FROM database_cursor
        INTO @database_name;

        CONTINUE;
    END;

    IF
    (
        @procedure_exists = 0
    AND @get_all_databases = 0
    )
        BEGIN
            RAISERROR('The stored procedure %s does not appear to have any entries in Query Store for database %s
Check that you spelled everything correctly and you''re in the right database',
                       10, 1, @procedure_name, @database_name) WITH NOWAIT;

        IF @get_all_databases = 0
        BEGIN
            RETURN;
        END;
    END;
END; /*End procedure existence checking*/

/*
Some things are version dependent.
Normally, I'd check for object existence, but the documentation
leads me to believe that certain things won't be back-ported,
like the wait stats DMV, and tempdb spills columns
*/
IF
(
   @product_version > 13
OR @engine IN (5, 8)
)
BEGIN
   SELECT
       @new = 1;
END;

/*
Validate Sort Order
*/
IF @sort_order NOT IN
   (
       'cpu',
       'logical reads',
       'physical reads',
       'writes',
       'duration',
       'memory',
       'tempdb',
       'executions',
       'recent'
   )
BEGIN
   RAISERROR('The sort order (%s) you chose is so out of this world that I''m using cpu instead', 10, 1, @sort_order) WITH NOWAIT;

   SELECT
       @sort_order = 'cpu';
END;

/*
These columns are only available in 2017+
*/
IF
(
    @sort_order = 'tempdb'
AND @new = 0
)
BEGIN
   RAISERROR('The sort order (%s) you chose is invalid in product version %i, reverting to cpu', 10, 1, @sort_order, @product_version) WITH NOWAIT;

   SELECT
       @sort_order = N'cpu';
END;

/*
See if our cool new 2022 views exist.
May have to tweak this if views aren't present in some cloudy situations.
*/
SELECT
    @sql_2022_views =
        CASE
            WHEN COUNT_BIG(*) = 5
            THEN 1
            ELSE 0
        END
FROM sys.all_objects AS ao
WHERE ao.name IN
      (
          N'query_store_plan_feedback',
          N'query_store_query_hints',
          N'query_store_query_variant',
          N'query_store_replicas',
          N'query_store_plan_forcing_locations'
      )
OPTION(RECOMPILE);

/*
Hints aren't in Query Store until 2022, so we can't do that on television
*/
IF
(
    (
         @only_queries_with_hints    = 1
      OR @only_queries_with_feedback = 1
      OR @only_queries_with_variants = 1
    )
AND @sql_2022_views = 0
)
BEGIN
    RAISERROR('Query Store hints, feedback, and variants are not available prior to SQL Server 2022', 10, 1) WITH NOWAIT;

    IF @get_all_databases = 0
    BEGIN
        RETURN;
    END;
END;

/*
Wait stats aren't in Query Store until 2017, so we can't do that on television
*/
IF
(
    @wait_filter IS NOT NULL
AND @new = 0
)
BEGIN
    RAISERROR('Query Store wait stats are not available prior to SQL Server 2017', 10, 1) WITH NOWAIT;

    IF @get_all_databases = 0
    BEGIN
        RETURN;
    END;
END;

/*
Make sure the wait filter is valid
*/
IF
(
    @new = 1
AND @wait_filter NOT IN
    (
        'cpu',
        'lock',
        'locks',
        'latch',
        'latches',
        'buffer latch',
        'buffer latches',
        'buffer io',
        'log',
        'log io',
        'network',
        'network io',
        'parallel',
        'parallelism',
        'memory'
    )
)
BEGIN
    RAISERROR('The wait category (%s) you chose is invalid', 10, 1, @wait_filter) WITH NOWAIT;

    IF @get_all_databases = 0
    BEGIN
        RETURN;
    END;
END;

/*
One last check: wait stat capture can be enabled or disabled in settings
*/
IF
(
   @wait_filter IS NOT NULL
OR @new = 1
)
BEGIN
    SELECT
        @current_table = 'checking query store waits are enabled',
        @sql = @isolation_level;

    IF @troubleshoot_performance = 1
    BEGIN

        EXEC sys.sp_executesql
            @troubleshoot_insert,
          N'@current_table nvarchar(100)',
            @current_table;

        SET STATISTICS XML ON;
    END;

    SELECT
        @sql += N'
SELECT
    @query_store_waits_enabled =
        CASE
            WHEN EXISTS
                 (
                     SELECT
                         1/0
                     FROM ' + @database_name_quoted + N'.sys.database_query_store_options AS dqso
                     WHERE dqso.wait_stats_capture_mode = 1
                 )
            THEN 1
            ELSE 0
        END
OPTION(RECOMPILE);' + @nc10;

    IF @debug = 1
    BEGIN
        PRINT LEN(@sql);
        PRINT @sql;
    END;

    EXEC sys.sp_executesql
        @sql,
      N'@query_store_waits_enabled bit OUTPUT',
        @query_store_waits_enabled OUTPUT;

    IF @troubleshoot_performance = 1
    BEGIN
        SET STATISTICS XML OFF;

        EXEC sys.sp_executesql
            @troubleshoot_update,
          N'@current_table nvarchar(100)',
            @current_table;

        EXEC sys.sp_executesql
            @troubleshoot_info,
          N'@sql nvarchar(max),
            @current_table nvarchar(100)',
            @sql,
            @current_table;
    END;

    IF @query_store_waits_enabled = 0
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Query Store wait stats are not enabled for database %s', 10, 1, @database_name_quoted) WITH NOWAIT;
        END
    END;
END; /*End wait stats checks*/

/*Check that the selected @timezone is valid*/
IF @timezone IS NOT NULL
BEGIN
    IF NOT EXISTS
       (
           SELECT
               1/0
           FROM sys.time_zone_info AS tzi
           WHERE tzi.name = @timezone
       )
       BEGIN
           RAISERROR('The time zone you chose (%s) is not valid. Please check sys.time_zone_info for a valid list.', 10, 1, @timezone) WITH NOWAIT;
           RETURN;
       END;
END;

/*
See if AGs are a thing so we can skip the checks for replica stuff
*/
IF (@azure = 1)
BEGIN
    SELECT
        @ags_present = 0;
END;
ELSE
BEGIN
    IF
    (
        SELECT
            CONVERT
            (
                sysname,
                SERVERPROPERTY('EngineEdition')
            )
    ) NOT IN (5, 8)
    BEGIN
        SELECT
            @ags_present =
                CASE
                    WHEN EXISTS
                         (
                             SELECT
                                 1/0
                             FROM sys.availability_groups AS ag
                         )
                    THEN 1
                    ELSE 0
                END
        OPTION(RECOMPILE);
    END
END;

/*
Get filters ready, or whatever
We're only going to pull some stuff from runtime stats and plans
*/
IF (@start_date <= @end_date)
BEGIN
    SELECT
        @where_clause += N'AND   qsrs.last_execution_time >= @start_date
AND   qsrs.last_execution_time <  @end_date' + @nc10;
END;

/*Other filters*/
IF @execution_count IS NOT NULL
BEGIN
    SELECT
        @where_clause += N'AND   qsrs.count_executions >= @execution_count' + @nc10;
END;

IF @duration_ms IS NOT NULL
BEGIN
    SELECT
        @where_clause += N'AND   qsrs.avg_duration >= (@duration_ms * 1000.)' + @nc10;
END;

IF @execution_type_desc IS NOT NULL
BEGIN
    SELECT
        @where_clause += N'AND   qsrs.execution_type_desc = @execution_type_desc' + @nc10;
END;

IF @workdays = 1
BEGIN
    IF  @work_start_utc IS NULL
    AND @work_end_utc   IS NULL
    BEGIN
         SELECT
             @work_start_utc = '09:00',
             @work_end_utc = '17:00';
    END;

    IF  @work_start_utc IS NOT NULL
    AND @work_end_utc   IS NULL
    BEGIN
        SELECT
            @work_end_utc =
                DATEADD
                (
                    HOUR,
                    8,
                    @work_start_utc
                );
    END;

    IF  @work_start_utc IS NULL
    AND @work_end_utc   IS NOT NULL
    BEGIN
        SELECT
            @work_start_utc =
                DATEADD
                (
                    HOUR,
                    -8,
                    @work_end_utc
                );
    END;

    SELECT
        @work_start_utc =
            DATEADD
            (
                MINUTE,
                @utc_minutes_difference,
                @work_start_utc
            ),
        @work_end_utc =
            DATEADD
            (
                MINUTE,
                @utc_minutes_difference,
                @work_end_utc
            );

    IF @df = 1
    BEGIN
       SELECT
           @where_clause += N'AND   DATEPART(WEEKDAY, qsrs.last_execution_time) BETWEEN 1 AND 5' + @nc10;
    END;/*df 1*/

    IF @df = 7
    BEGIN
       SELECT
           @where_clause += N'AND   DATEPART(WEEKDAY, qsrs.last_execution_time) BETWEEN 2 AND 6' + @nc10;
    END;/*df 7*/

    IF  @work_start_utc IS NOT NULL
    AND @work_end_utc IS NOT NULL
    BEGIN
        /*
          depending on local TZ, work time might span midnight UTC;
          account for that by splitting the interval into before/after midnight.
          for example:
              [09:00 - 17:00] PST
           =  [17:00 - 01:00] UTC
           =  [17:00 - 00:00) + [00:00 - 01:00] UTC

          NB: because we don't have the benefit of the context of what day midnight
          is occurring on, we have to rely on the behavior from the documentation of
          the time DT of higher to lower precision resulting in truncation to split
          the interval. i.e. 23:59:59.9999999 -> 23:59:59. which should make that
          value safe to use as the endpoint for our "before midnight" interval.
        */
        IF (@work_start_utc < @work_end_utc)
        SELECT
            @where_clause += N'AND   CONVERT(time(0), qsrs.last_execution_time) BETWEEN @work_start_utc AND @work_end_utc' + @nc10;
        ELSE
        SELECT
            @where_clause += N'AND
(' + @nc10 +
N'      CONVERT(time(0), qsrs.last_execution_time) BETWEEN @work_start_utc AND ''23:59:59'' ' + @nc10 +
N'   OR CONVERT(time(0), qsrs.last_execution_time) BETWEEN ''00:00:00'' AND @work_end_utc' + @nc10 +
N')' + @nc10;
    END; /*Work hours*/
END; /*Final end*/

/*
In this section we set up the filter if someone's searching for
a single stored procedure in Query Store.
*/
IF
(
    @procedure_name IS NOT NULL
AND @procedure_exists = 1
)
BEGIN
    SELECT
        @current_table = 'inserting #procedure_plans',
        @sql = @isolation_level;

    IF @troubleshoot_performance = 1
    BEGIN
        EXEC sys.sp_executesql
            @troubleshoot_insert,
          N'@current_table nvarchar(100)',
            @current_table;

        SET STATISTICS XML ON;
    END;

    SELECT
        @sql += N'
SELECT DISTINCT
    qsp.plan_id
FROM ' + @database_name_quoted + N'.sys.query_store_query AS qsq
JOIN ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
   ON qsq.query_id = qsp.query_id
WHERE qsq.object_id = OBJECT_ID(@procedure_name_quoted)
OPTION(RECOMPILE);' + @nc10;

    IF @debug = 1
    BEGIN
        PRINT LEN(@sql);
        PRINT @sql;
    END;

    INSERT
        #procedure_plans WITH(TABLOCK)
    (
        plan_id
    )
    EXEC sys.sp_executesql
        @sql,
      N'@procedure_name_quoted sysname',
        @procedure_name_quoted;

    IF @troubleshoot_performance = 1
    BEGIN
        SET STATISTICS XML OFF;

        EXEC sys.sp_executesql
            @troubleshoot_update,
          N'@current_table nvarchar(100)',
            @current_table;

        EXEC sys.sp_executesql
            @troubleshoot_info,
          N'@sql nvarchar(max),
            @current_table nvarchar(100)',
            @sql,
            @current_table;
    END;

    SELECT
        @where_clause += N'AND   EXISTS
        (
            SELECT
                1/0
            FROM #procedure_plans AS pp
            WHERE pp.plan_id = qsrs.plan_id
        )'  + @nc10;
END; /*End procedure filter table population*/


/*
In this section we set up the filter if someone's searching for
either ad hoc queries or queries from modules.
*/
IF LEN(@query_type) > 0
BEGIN
    SELECT
        @current_table = 'inserting #query_types',
        @sql = @isolation_level;

    IF @troubleshoot_performance = 1
    BEGIN
        EXEC sys.sp_executesql
            @troubleshoot_insert,
          N'@current_table nvarchar(100)',
            @current_table;

        SET STATISTICS XML ON;
    END;

    SELECT
        @sql += N'
SELECT DISTINCT
    qsp.plan_id
FROM ' + @database_name_quoted + N'.sys.query_store_query AS qsq
JOIN ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
  ON qsq.query_id = qsp.query_id
WHERE qsq.object_id ' +
CASE
    WHEN LOWER(@query_type) LIKE 'a%'
    THEN N'= 0'
    ELSE N'<> 0'
END
+ N'
OPTION(RECOMPILE);' + @nc10;

    IF @debug = 1
    BEGIN
        PRINT LEN(@sql);
        PRINT @sql;
    END;

    INSERT
        #query_types WITH(TABLOCK)
    (
        plan_id
    )
    EXEC sys.sp_executesql
        @sql;

    IF @troubleshoot_performance = 1
    BEGIN
        SET STATISTICS XML OFF;

        EXEC sys.sp_executesql
            @troubleshoot_update,
          N'@current_table nvarchar(100)',
            @current_table;

        EXEC sys.sp_executesql
            @troubleshoot_info,
          N'@sql nvarchar(max),
            @current_table nvarchar(100)',
            @sql,
            @current_table;
    END;

    SELECT
        @where_clause += N'AND   EXISTS
        (
            SELECT
                1/0
            FROM #query_types AS qt
            WHERE qt.plan_id = qsrs.plan_id
        )'  + @nc10;
END; /*End query type filter table population*/


/*
This section filters query or plan ids, both inclusive and exclusive
*/
IF
(
   @include_plan_ids  IS NOT NULL
OR @include_query_ids IS NOT NULL
OR @ignore_plan_ids   IS NOT NULL
OR @ignore_query_ids  IS NOT NULL
)
BEGIN
    IF @include_plan_ids IS NOT NULL
    BEGIN
        SELECT
            @include_plan_ids =
                REPLACE(REPLACE(REPLACE(REPLACE(
                    LTRIM(RTRIM(@include_plan_ids)),
                 CHAR(10), N''),  CHAR(13), N''),
                NCHAR(10), N''), NCHAR(13), N'');

        SELECT
            @current_table = 'inserting #include_plan_ids';

        INSERT
            #include_plan_ids WITH(TABLOCK)
        (
            plan_id
        )
        EXEC sys.sp_executesql
            @string_split_ints,
          N'@ids nvarchar(4000)',
            @include_plan_ids;

        SELECT
            @where_clause += N'AND   EXISTS
      (
         SELECT
            1/0
         FROM #include_plan_ids AS idi
         WHERE idi.plan_id = qsrs.plan_id
      )' + @nc10;
    END; /*End include plan ids*/

    IF @ignore_plan_ids IS NOT NULL
    BEGIN
        SELECT
            @ignore_plan_ids =
                REPLACE(REPLACE(REPLACE(REPLACE(
                    LTRIM(RTRIM(@ignore_plan_ids)),
                 CHAR(10), N''),  CHAR(13), N''),
                NCHAR(10), N''), NCHAR(13), N'');

        SELECT
            @current_table = 'inserting #ignore_plan_ids';

        INSERT
            #ignore_plan_ids WITH(TABLOCK)
        (
            plan_id
        )
        EXEC sys.sp_executesql
            @string_split_ints,
          N'@ids nvarchar(4000)',
            @ignore_plan_ids;

        SELECT
            @where_clause += N'AND   NOT EXISTS
      (
         SELECT
            1/0
         FROM #ignore_plan_ids AS idi
         WHERE idi.plan_id = qsrs.plan_id
      )' + @nc10;
    END; /*End ignore plan ids*/

    IF @include_query_ids IS NOT NULL
    BEGIN
        SELECT
            @include_query_ids =
                REPLACE(REPLACE(REPLACE(REPLACE(
                    LTRIM(RTRIM(@include_query_ids)),
                 CHAR(10), N''),  CHAR(13), N''),
                NCHAR(10), N''), NCHAR(13), N'');
        SELECT
            @current_table = 'inserting #include_query_ids',
            @sql = @isolation_level;

        INSERT
            #include_query_ids WITH(TABLOCK)
        (
            query_id
        )
        EXEC sys.sp_executesql
            @string_split_ints,
          N'@ids nvarchar(4000)',
            @include_query_ids;

        SELECT
            @current_table = 'inserting #include_plan_ids for included query ids';

        IF @troubleshoot_performance = 1
        BEGIN
            EXEC sys.sp_executesql
                @troubleshoot_insert,
              N'@current_table nvarchar(100)',
                @current_table;

            SET STATISTICS XML ON;
        END;

        SELECT
            @sql += N'
SELECT DISTINCT
    qsp.plan_id
FROM ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
WHERE EXISTS
      (
          SELECT
              1/0
          FROM #include_query_ids AS iqi
          WHERE iqi.query_id = qsp.query_id
      )
OPTION(RECOMPILE);' + @nc10;

        IF @debug = 1
        BEGIN
            PRINT LEN(@sql);
            PRINT @sql;
        END;

        INSERT
            #include_plan_ids
        (
            plan_id
        )
        EXEC sys.sp_executesql
            @sql;

        IF @troubleshoot_performance = 1
        BEGIN
            SET STATISTICS XML OFF;

            EXEC sys.sp_executesql
                @troubleshoot_update,
              N'@current_table nvarchar(100)',
                @current_table;

            EXEC sys.sp_executesql
                @troubleshoot_info,
              N'@sql nvarchar(max),
                @current_table nvarchar(100)',
                @sql,
                @current_table;
        END;

        /*
        This section of code confused me when I came back to it,
        so I'm going to add a note here about why I do this:

        If @include_plan_ids is NULL at this point, it's because
        the user didn't populate the parameter.

        We need to do this because it's how we figure
        out which plans to keep in the main query
        */
        IF @include_plan_ids IS NULL
        BEGIN
            SELECT
                @where_clause += N'AND   EXISTS
          (
             SELECT
                1/0
             FROM #include_plan_ids AS idi
             WHERE idi.plan_id = qsrs.plan_id
          )' + @nc10;
        END;
    END; /*End include query ids*/

    IF @ignore_query_ids IS NOT NULL
    BEGIN
        SELECT
            @ignore_query_ids =
                REPLACE(REPLACE(REPLACE(REPLACE(
                    LTRIM(RTRIM(@ignore_query_ids)),
                 CHAR(10), N''),  CHAR(13), N''),
                NCHAR(10), N''), NCHAR(13), N'');
        SELECT
            @current_table = 'inserting #ignore_query_ids',
            @sql = @isolation_level;

        INSERT
            #ignore_query_ids WITH(TABLOCK)
        (
            query_id
        )
        EXEC sys.sp_executesql
            @string_split_ints,
          N'@ids nvarchar(4000)',
            @ignore_query_ids;

        SELECT
            @current_table = 'inserting #ignore_plan_ids for ignored query ids';

        IF @troubleshoot_performance = 1
        BEGIN
            EXEC sys.sp_executesql
                @troubleshoot_insert,
              N'@current_table nvarchar(100)',
                @current_table;

            SET STATISTICS XML ON;
        END;

        SELECT
            @sql += N'
SELECT DISTINCT
    qsp.plan_id
FROM ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
WHERE EXISTS
      (
          SELECT
              1/0
          FROM #ignore_query_ids AS iqi
          WHERE iqi.query_id = qsp.query_id
      )
OPTION(RECOMPILE);' + @nc10;

        IF @debug = 1
        BEGIN
            PRINT LEN(@sql);
            PRINT @sql;
        END;

        INSERT
            #ignore_plan_ids
        (
            plan_id
        )
        EXEC sys.sp_executesql
            @sql;

        IF @troubleshoot_performance = 1
        BEGIN
            SET STATISTICS XML OFF;

            EXEC sys.sp_executesql
                @troubleshoot_update,
              N'@current_table nvarchar(100)',
                @current_table;

            EXEC sys.sp_executesql
                @troubleshoot_info,
              N'@sql nvarchar(max),
                @current_table nvarchar(100)',
                @sql,
                @current_table;
        END;

        /*
        This section of code confused me when I came back to it,
        so I'm going to add a note here about why I do this:

        If @ignore_plan_ids is NULL at this point, it's because
        the user didn't populate the parameter.

        We need to do this because it's how we figure
        out which plans to keep in the main query
        */
        IF @ignore_plan_ids IS NULL
        BEGIN
            SELECT
                @where_clause += N'AND   NOT EXISTS
          (
             SELECT
                1/0
             FROM #ignore_plan_ids AS idi
             WHERE idi.plan_id = qsrs.plan_id
          )' + @nc10;
        END;
    END; /*End ignore query ids*/
END; /*End query and plan id filtering*/

/*
This section filters query or plan hashes
*/
IF
(
   @include_query_hashes IS NOT NULL
OR @include_plan_hashes  IS NOT NULL
OR @include_sql_handles  IS NOT NULL
OR @ignore_query_hashes  IS NOT NULL
OR @ignore_plan_hashes   IS NOT NULL
OR @ignore_sql_handles   IS NOT NULL
)
BEGIN
    IF @include_query_hashes IS NOT NULL
    BEGIN
        SELECT
            @include_query_hashes =
                REPLACE(REPLACE(REPLACE(REPLACE(
                    LTRIM(RTRIM(@include_query_hashes)),
                 CHAR(10), N''),  CHAR(13), N''),
                NCHAR(10), N''), NCHAR(13), N'');

        SELECT
            @current_table = 'inserting #include_query_hashes',
            @sql = @isolation_level;

        INSERT
            #include_query_hashes WITH(TABLOCK)
        (
            query_hash_s
        )
        EXEC sys.sp_executesql
            @string_split_strings,
          N'@ids nvarchar(4000)',
            @include_query_hashes;

        SELECT
            @current_table = 'inserting #include_plan_ids for included query hashes';

        IF @troubleshoot_performance = 1
        BEGIN
            EXEC sys.sp_executesql
                @troubleshoot_insert,
              N'@current_table nvarchar(100)',
                @current_table;

            SET STATISTICS XML ON;
        END;

        SELECT
            @sql += N'
SELECT DISTINCT
    qsp.plan_id
FROM ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
WHERE EXISTS
      (
          SELECT
              1/0
          FROM ' + @database_name_quoted + N'.sys.query_store_query AS qsq
          WHERE qsq.query_id = qsp.query_id
          AND   EXISTS
                (
                    SELECT
                        1/0
                    FROM #include_query_hashes AS iqh
                    WHERE iqh.query_hash = qsq.query_hash
                )
      )
OPTION(RECOMPILE);' + @nc10;

        IF @debug = 1
        BEGIN
            PRINT LEN(@sql);
            PRINT @sql;
        END;

        INSERT
            #include_plan_ids
        (
            plan_id
        )
        EXEC sys.sp_executesql
            @sql;

        IF @troubleshoot_performance = 1
        BEGIN
            SET STATISTICS XML OFF;

            EXEC sys.sp_executesql
                @troubleshoot_update,
              N'@current_table nvarchar(100)',
                @current_table;

            EXEC sys.sp_executesql
                @troubleshoot_info,
              N'@sql nvarchar(max),
                @current_table nvarchar(100)',
                @sql,
                @current_table;
        END;

        /*
        This section of code confused me when I came back to it,
        so I'm going to add a note here about why I do this:

        If @include_plan_ids is NULL at this point, it's because
        the user didn't populate the parameter.

        We need to do this because it's how we figure
        out which plans to keep in the main query
        */
        IF @include_plan_ids IS NULL
        BEGIN
            SELECT
               @where_clause += N'AND   EXISTS
          (
             SELECT
                1/0
             FROM #include_plan_ids AS idi
             WHERE idi.plan_id = qsrs.plan_id
          )' + @nc10;
        END;
    END; /*End include query hashes*/

    IF @ignore_query_hashes IS NOT NULL
    BEGIN
        SELECT
            @ignore_query_hashes =
                REPLACE(REPLACE(REPLACE(REPLACE(
                    LTRIM(RTRIM(@ignore_query_hashes)),
                 CHAR(10), N''),  CHAR(13), N''),
                NCHAR(10), N''), NCHAR(13), N'');

        SELECT
            @current_table = 'inserting #ignore_query_hashes',
            @sql = @isolation_level;

        INSERT
            #ignore_query_hashes WITH(TABLOCK)
        (
            query_hash_s
        )
        EXEC sys.sp_executesql
            @string_split_strings,
          N'@ids nvarchar(4000)',
            @ignore_query_hashes;

        SELECT
            @current_table = 'inserting #ignore_plan_ids for ignored query hashes';

        IF @troubleshoot_performance = 1
        BEGIN
            EXEC sys.sp_executesql
                @troubleshoot_insert,
              N'@current_table nvarchar(100)',
                @current_table;

            SET STATISTICS XML ON;
        END;

        SELECT
            @sql += N'
SELECT DISTINCT
    qsp.plan_id
FROM ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
WHERE EXISTS
      (
          SELECT
              1/0
          FROM ' + @database_name_quoted + N'.sys.query_store_query AS qsq
          WHERE qsq.query_id = qsp.query_id
          AND   EXISTS
                (
                    SELECT
                        1/0
                    FROM #ignore_query_hashes AS iqh
                    WHERE iqh.query_hash = qsq.query_hash
                )
      )
OPTION(RECOMPILE);' + @nc10;

        IF @debug = 1
        BEGIN
            PRINT LEN(@sql);
            PRINT @sql;
        END;

        INSERT
            #ignore_plan_ids
        (
            plan_id
        )
        EXEC sys.sp_executesql
            @sql;

        IF @troubleshoot_performance = 1
        BEGIN
            SET STATISTICS XML OFF;

            EXEC sys.sp_executesql
                @troubleshoot_update,
              N'@current_table nvarchar(100)',
                @current_table;

            EXEC sys.sp_executesql
                @troubleshoot_info,
              N'@sql nvarchar(max),
                @current_table nvarchar(100)',
                @sql,
                @current_table;
        END;

        /*
        This section of code confused me when I came back to it,
        so I'm going to add a note here about why I do this:

        If @ignore_plan_ids is NULL at this point, it's because
        the user didn't populate the parameter.

        We need to do this because it's how we figure
        out which plans to keep in the main query
        */
        IF @ignore_plan_ids IS NULL
        BEGIN
            SELECT
               @where_clause += N'AND   NOT EXISTS
          (
             SELECT
                1/0
             FROM #ignore_plan_ids AS idi
             WHERE idi.plan_id = qsrs.plan_id
          )' + @nc10;
          END;
    END; /*End ignore query hashes*/

    IF @include_plan_hashes IS NOT NULL
    BEGIN
        SELECT
            @include_plan_hashes =
                REPLACE(REPLACE(REPLACE(REPLACE(
                    LTRIM(RTRIM(@include_plan_hashes)),
                 CHAR(10), N''),  CHAR(13), N''),
                NCHAR(10), N''), NCHAR(13), N'');

        SELECT
            @current_table = 'inserting #include_plan_hashes',
            @sql = @isolation_level;

        INSERT
            #include_plan_hashes WITH(TABLOCK)
        (
            plan_hash_s
        )
        EXEC sys.sp_executesql
            @string_split_strings,
          N'@ids nvarchar(4000)',
            @include_plan_hashes;

        SELECT
            @current_table = 'inserting #include_plan_ids for included plan hashes';

        IF @troubleshoot_performance = 1
        BEGIN
            EXEC sys.sp_executesql
                @troubleshoot_insert,
              N'@current_table nvarchar(100)',
                @current_table;

            SET STATISTICS XML ON;
        END;

        SELECT
            @sql += N'
SELECT DISTINCT
    qsp.plan_id
FROM ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
WHERE EXISTS
      (
          SELECT
              1/0
          FROM #include_plan_hashes AS iph
          WHERE iph.plan_hash = qsp.query_plan_hash
      )
OPTION(RECOMPILE);' + @nc10;

        IF @debug = 1
        BEGIN
            PRINT LEN(@sql);
            PRINT @sql;
        END;

        INSERT
            #include_plan_ids
        (
            plan_id
        )
        EXEC sys.sp_executesql
            @sql;

        IF @troubleshoot_performance = 1
        BEGIN
            SET STATISTICS XML OFF;

            EXEC sys.sp_executesql
                @troubleshoot_update,
              N'@current_table nvarchar(100)',
                @current_table;

            EXEC sys.sp_executesql
                @troubleshoot_info,
              N'@sql nvarchar(max),
                @current_table nvarchar(100)',
                @sql,
                @current_table;
        END;

        /*
        This section of code confused me when I came back to it,
        so I'm going to add a note here about why I do this:

        If @include_plan_ids is NULL at this point, it's because
        the user didn't populate the parameter.

        We need to do this because it's how we figure
        out which plans to keep in the main query
        */
        IF @include_plan_ids IS NULL
        BEGIN
            SELECT
               @where_clause += N'AND   EXISTS
          (
             SELECT
                1/0
             FROM #include_plan_ids AS idi
             WHERE idi.plan_id = qsrs.plan_id
          )' + @nc10;
        END;
    END; /*End include plan hashes*/

    IF @ignore_plan_hashes IS NOT NULL
    BEGIN
        SELECT
            @ignore_plan_hashes =
                REPLACE(REPLACE(REPLACE(REPLACE(
                    LTRIM(RTRIM(@ignore_plan_hashes)),
                 CHAR(10), N''),  CHAR(13), N''),
                NCHAR(10), N''), NCHAR(13), N'');

        SELECT
            @current_table = 'inserting #ignore_plan_hashes',
            @sql = @isolation_level;

        INSERT
            #ignore_plan_hashes WITH(TABLOCK)
        (
            plan_hash_s
        )
        EXEC sys.sp_executesql
            @string_split_strings,
          N'@ids nvarchar(4000)',
            @ignore_plan_hashes;

        SELECT
            @current_table = 'inserting #ignore_plan_ids for ignored query hashes';

        IF @troubleshoot_performance = 1
        BEGIN
            EXEC sys.sp_executesql
                @troubleshoot_insert,
              N'@current_table nvarchar(100)',
                @current_table;

            SET STATISTICS XML ON;
        END;

        SELECT
            @sql += N'
SELECT DISTINCT
    qsp.plan_id
FROM ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
WHERE EXISTS
      (
          SELECT
              1/0
          FROM #ignore_plan_hashes AS iph
          WHERE iph.plan_hash = qsp.query_plan_hash
      )
OPTION(RECOMPILE);' + @nc10;

        IF @debug = 1
        BEGIN
            PRINT LEN(@sql);
            PRINT @sql;
        END;

        INSERT
            #ignore_plan_ids
        (
            plan_id
        )
        EXEC sys.sp_executesql
            @sql;

        IF @troubleshoot_performance = 1
        BEGIN
            SET STATISTICS XML OFF;

            EXEC sys.sp_executesql
                @troubleshoot_update,
              N'@current_table nvarchar(100)',
                @current_table;

            EXEC sys.sp_executesql
                @troubleshoot_info,
              N'@sql nvarchar(max),
                @current_table nvarchar(100)',
                @sql,
                @current_table;
        END;

        /*
        This section of code confused me when I came back to it,
        so I'm going to add a note here about why I do this:

        If @ignore_plan_ids is NULL at this point, it's because
        the user didn't populate the parameter.

        We need to do this because it's how we figure
        out which plans to keep in the main query
        */
        IF @ignore_plan_ids IS NULL
        BEGIN
            SELECT
               @where_clause += N'AND   NOT EXISTS
          (
             SELECT
                1/0
             FROM #ignore_plan_ids AS idi
             WHERE idi.plan_id = qsrs.plan_id
          )' + @nc10;
          END;
    END; /*End ignore plan hashes*/

    IF @include_sql_handles IS NOT NULL
    BEGIN
        SELECT
            @include_sql_handles =
                REPLACE(REPLACE(REPLACE(REPLACE(
                    LTRIM(RTRIM(@include_sql_handles)),
                 CHAR(10), N''),  CHAR(13), N''),
                NCHAR(10), N''), NCHAR(13), N'');

        SELECT
            @current_table = 'inserting #include_sql_handles',
            @sql = @isolation_level;

        INSERT
            #include_sql_handles WITH(TABLOCK)
        (
            sql_handle_s
        )
        EXEC sys.sp_executesql
            @string_split_strings,
          N'@ids nvarchar(4000)',
            @include_sql_handles;

        SELECT
            @current_table = 'inserting #include_sql_handles for included sql handles';

        IF @troubleshoot_performance = 1
        BEGIN

            EXEC sys.sp_executesql
                @troubleshoot_insert,
              N'@current_table nvarchar(100)',
                @current_table;

            SET STATISTICS XML ON;
        END;

        SELECT
            @sql += N'
SELECT DISTINCT
    qsp.plan_id
FROM ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
WHERE EXISTS
      (
          SELECT
              1/0
          FROM ' + @database_name_quoted + N'.sys.query_store_query AS qsq
          WHERE qsp.query_id = qsq.query_id
          AND EXISTS
              (
                  SELECT
                      1/0
                  FROM ' + @database_name_quoted + N'.sys.query_store_query_text AS qsqt
                  WHERE qsqt.query_text_id = qsq.query_text_id
                  AND   EXISTS
                        (
                            SELECT
                                1/0
                            FROM #include_sql_handles AS ish
                            WHERE ish.sql_handle = qsqt.statement_sql_handle
                        )
              )
      )
OPTION(RECOMPILE);' + @nc10;

        IF @debug = 1
        BEGIN
            PRINT LEN(@sql);
            PRINT @sql;
        END;

        INSERT
            #include_plan_ids
        (
            plan_id
        )
        EXEC sys.sp_executesql
            @sql;

        IF @troubleshoot_performance = 1
        BEGIN
            SET STATISTICS XML OFF;

            EXEC sys.sp_executesql
                @troubleshoot_update,
              N'@current_table nvarchar(100)',
                @current_table;

            EXEC sys.sp_executesql
                @troubleshoot_info,
              N'@sql nvarchar(max),
                @current_table nvarchar(100)',
                @sql,
                @current_table;
        END;

        /*
        This section of code confused me when I came back to it,
        so I'm going to add a note here about why I do this:

        If @include_plan_ids is NULL at this point, it's because
        the user didn't populate the parameter.

        We need to do this because it's how we figure
        out which plans to keep in the main query
        */
        IF @include_plan_ids IS NULL
        BEGIN
            SELECT
                @where_clause += N'AND   EXISTS
          (
             SELECT
                1/0
             FROM #include_plan_ids AS idi
             WHERE idi.plan_id = qsrs.plan_id
          )' + @nc10;
        END;
    END; /*End include plan hashes*/

    IF @ignore_sql_handles IS NOT NULL
    BEGIN
        SELECT
            @ignore_sql_handles =
                REPLACE(REPLACE(REPLACE(REPLACE(
                    LTRIM(RTRIM(@ignore_sql_handles)),
                 CHAR(10), N''),  CHAR(13), N''),
                NCHAR(10), N''), NCHAR(13), N'');

        SELECT
            @current_table = 'inserting #ignore_sql_handles',
            @sql = @isolation_level;

        INSERT
            #ignore_sql_handles WITH(TABLOCK)
        (
            sql_handle_s
        )
        EXEC sys.sp_executesql
            @string_split_strings,
          N'@ids nvarchar(4000)',
            @ignore_sql_handles;

        SELECT
            @current_table = 'inserting #ignore_plan_ids for ignored sql handles';

        IF @troubleshoot_performance = 1
        BEGIN
            EXEC sys.sp_executesql
                @troubleshoot_insert,
              N'@current_table nvarchar(100)',
                @current_table;

            SET STATISTICS XML ON;
        END;

        SELECT
            @sql += N'
SELECT DISTINCT
    qsp.plan_id
FROM ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
WHERE EXISTS
      (
          SELECT
              1/0
          FROM ' + @database_name_quoted + N'.sys.query_store_query AS qsq
          WHERE qsp.query_id = qsq.query_id
          AND EXISTS
              (
                  SELECT
                      1/0
                  FROM ' + @database_name_quoted + N'.sys.query_store_query_text AS qsqt
                  WHERE qsqt.query_text_id = qsq.query_text_id
                  AND   EXISTS
                        (
                            SELECT
                                1/0
                            FROM #ignore_sql_handles AS ish
                            WHERE ish.sql_handle = qsqt.statement_sql_handle
                        )
              )
      )
OPTION(RECOMPILE);' + @nc10;

        IF @debug = 1
        BEGIN
            PRINT LEN(@sql);
            PRINT @sql;
        END;

        INSERT
            #ignore_plan_ids
        (
            plan_id
        )
        EXEC sys.sp_executesql
            @sql;

        IF @troubleshoot_performance = 1
        BEGIN
            SET STATISTICS XML OFF;

            EXEC sys.sp_executesql
                @troubleshoot_update,
              N'@current_table nvarchar(100)',
                @current_table;

            EXEC sys.sp_executesql
                @troubleshoot_info,
              N'@sql nvarchar(max),
                @current_table nvarchar(100)',
                @sql,
                @current_table;
        END;

        /*
        This section of code confused me when I came back to it,
        so I'm going to add a note here about why I do this:

        If @ignore_plan_ids is NULL at this point, it's because
        the user didn't populate the parameter.

        We need to do this because it's how we figure
        out which plans to keep in the main query
        */
        IF @ignore_plan_ids IS NULL
        BEGIN
            SELECT
                @where_clause += N'AND   NOT EXISTS
          (
             SELECT
                1/0
             FROM #ignore_plan_ids AS idi
             WHERE idi.plan_id = qsrs.plan_id
          )' + @nc10;
          END;
    END; /*End ignore plan hashes*/
END; /*End hash and handle filtering*/

IF @sql_2022_views = 1
BEGIN
    IF @only_queries_with_hints = 1
    BEGIN
        SELECT
            @current_table = 'inserting #only_queries_with_hints',
            @sql = @isolation_level;

        IF @troubleshoot_performance = 1
        BEGIN
            EXEC sys.sp_executesql
                @troubleshoot_insert,
              N'@current_table nvarchar(100)',
                @current_table;

            SET STATISTICS XML ON;
        END;

        SELECT
            @sql += N'
    SELECT DISTINCT
        qsp.plan_id
    FROM ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
    WHERE EXISTS
          (
              SELECT
                  1/0
              FROM ' + @database_name_quoted + N'.sys.query_store_query_hints AS qsqh
              WHERE qsqh.query_id = qsp.query_id
          )';

        SELECT
            @sql += N'
    OPTION(RECOMPILE);' + @nc10;

        IF @debug = 1
        BEGIN
            PRINT LEN(@sql);
            PRINT @sql;
        END;

        INSERT
            #only_queries_with_hints WITH(TABLOCK)
        (
            plan_id
        )
        EXEC sys.sp_executesql
            @sql

        IF @troubleshoot_performance = 1
        BEGIN
            SET STATISTICS XML OFF;

            EXEC sys.sp_executesql
                @troubleshoot_update,
              N'@current_table nvarchar(100)',
                @current_table;

            EXEC sys.sp_executesql
                @troubleshoot_info,
              N'@sql nvarchar(max),
                @current_table nvarchar(100)',
                @sql,
                @current_table;
        END;

        SELECT
            @where_clause += N'AND   EXISTS
           (
               SELECT
                   1/0
               FROM #only_queries_with_hints AS qst
               WHERE qst.plan_id = qsrs.plan_id
           )' + @nc10;
    END;

    IF @only_queries_with_feedback = 1
    BEGIN
        SELECT
            @current_table = 'inserting #only_queries_with_feedback',
            @sql = @isolation_level;

        IF @troubleshoot_performance = 1
        BEGIN
            EXEC sys.sp_executesql
                @troubleshoot_insert,
              N'@current_table nvarchar(100)',
                @current_table;

            SET STATISTICS XML ON;
        END;

        SELECT
            @sql += N'
    SELECT DISTINCT
        qsp.plan_id
    FROM ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
    WHERE EXISTS
          (
              SELECT
                  1/0
              FROM ' + @database_name_quoted + N'.sys.query_store_plan_feedback AS qsqf
              WHERE qsqf.plan_id = qsp.plan_id
          )';

        SELECT
            @sql += N'
    OPTION(RECOMPILE);' + @nc10;

        IF @debug = 1
        BEGIN
            PRINT LEN(@sql);
            PRINT @sql;
        END;

        INSERT
            #only_queries_with_feedback WITH(TABLOCK)
        (
            plan_id
        )
        EXEC sys.sp_executesql
            @sql

        IF @troubleshoot_performance = 1
        BEGIN
            SET STATISTICS XML OFF;

            EXEC sys.sp_executesql
                @troubleshoot_update,
              N'@current_table nvarchar(100)',
                @current_table;

            EXEC sys.sp_executesql
                @troubleshoot_info,
              N'@sql nvarchar(max),
                @current_table nvarchar(100)',
                @sql,
                @current_table;
        END;

        SELECT
            @where_clause += N'AND   EXISTS
           (
               SELECT
                   1/0
               FROM #only_queries_with_feedback AS qst
               WHERE qst.plan_id = qsrs.plan_id
           )' + @nc10;
    END;

    IF @only_queries_with_variants = 1
    BEGIN
        SELECT
            @current_table = 'inserting #only_queries_with_variants',
            @sql = @isolation_level;

        IF @troubleshoot_performance = 1
        BEGIN
            EXEC sys.sp_executesql
                @troubleshoot_insert,
              N'@current_table nvarchar(100)',
                @current_table;

            SET STATISTICS XML ON;
        END;

        SELECT
            @sql += N'
    SELECT DISTINCT
        qsp.plan_id
    FROM ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
    WHERE EXISTS
          (
              SELECT
                  1/0
              FROM ' + @database_name_quoted + N'.sys.query_store_query_variant AS qsqv
              WHERE qsqv.query_variant_query_id = qsp.query_id
          )';

        SELECT
            @sql += N'
    OPTION(RECOMPILE);' + @nc10;

        IF @debug = 1
        BEGIN
            PRINT LEN(@sql);
            PRINT @sql;
        END;

        INSERT
            #only_queries_with_variants WITH(TABLOCK)
        (
            plan_id
        )
        EXEC sys.sp_executesql
            @sql

        IF @troubleshoot_performance = 1
        BEGIN
            SET STATISTICS XML OFF;

            EXEC sys.sp_executesql
                @troubleshoot_update,
              N'@current_table nvarchar(100)',
                @current_table;

            EXEC sys.sp_executesql
                @troubleshoot_info,
              N'@sql nvarchar(max),
                @current_table nvarchar(100)',
                @sql,
                @current_table;
        END;

        SELECT
            @where_clause += N'AND   EXISTS
           (
               SELECT
                   1/0
               FROM #only_queries_with_variants AS qst
               WHERE qst.plan_id = qsrs.plan_id
           )' + @nc10;
    END;
END;

IF
(
     @only_queries_with_forced_plans = 1
  OR @only_queries_with_forced_plan_failures = 1
)
BEGIN
    SELECT
        @current_table = 'inserting #forced_plans_failures',
        @sql = @isolation_level;

    IF @troubleshoot_performance = 1
    BEGIN
        EXEC sys.sp_executesql
            @troubleshoot_insert,
          N'@current_table nvarchar(100)',
            @current_table;

        SET STATISTICS XML ON;
    END;

    SELECT
        @sql += N'
SELECT DISTINCT
    qsp.plan_id
FROM ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
WHERE qsp.is_forced_plan = 1';

IF @only_queries_with_forced_plan_failures = 1
BEGIN
    SELECT
        @sql += N'
AND   qsp.last_force_failure_reason > 0'
END

    SELECT
        @sql += N'
OPTION(RECOMPILE);' + @nc10;

    IF @debug = 1
    BEGIN
        PRINT LEN(@sql);
        PRINT @sql;
    END;

    INSERT
        #forced_plans_failures WITH(TABLOCK)
    (
        plan_id
    )
    EXEC sys.sp_executesql
        @sql

    IF @troubleshoot_performance = 1
    BEGIN
        SET STATISTICS XML OFF;

        EXEC sys.sp_executesql
            @troubleshoot_update,
          N'@current_table nvarchar(100)',
            @current_table;

        EXEC sys.sp_executesql
            @troubleshoot_info,
          N'@sql nvarchar(max),
            @current_table nvarchar(100)',
            @sql,
            @current_table;
    END;

    SELECT
        @where_clause += N'AND   EXISTS
       (
           SELECT
               1/0
           FROM #forced_plans_failures AS fpf
           WHERE fpf.plan_id = qsrs.plan_id
       )' + @nc10;
END;

IF @query_text_search IS NOT NULL
BEGIN
    IF
    (
        LEFT
        (
            @query_text_search,
            1
        ) <> N'%'
    )
    BEGIN
        SELECT
            @query_text_search =
                N'%' + @query_text_search;
    END;

    IF
    (
        LEFT
        (
            REVERSE
            (
                @query_text_search
            ),
            1
        ) <> N'%'
    )
    BEGIN
        SELECT
            @query_text_search =
                @query_text_search + N'%';
    END;

    /* If our query texts contains square brackets (common in Entity Framework queries), add a leading escape character to each bracket character */
    IF @escape_brackets = 1
    BEGIN
        SELECT
            @query_text_search =
                REPLACE(REPLACE(REPLACE(
                    @query_text_search,
                N'[', @escape_character + N'['),
                N']', @escape_character + N']'),
                N'_', @escape_character + N'_');
    END;

    SELECT
        @current_table = 'inserting #query_text_search',
        @sql = @isolation_level;

    IF @troubleshoot_performance = 1
    BEGIN
        EXEC sys.sp_executesql
            @troubleshoot_insert,
          N'@current_table nvarchar(100)',
            @current_table;

        SET STATISTICS XML ON;
    END;

    SELECT
        @sql += N'
SELECT DISTINCT
    qsp.plan_id
FROM ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
WHERE EXISTS
      (
          SELECT
              1/0
          FROM ' + @database_name_quoted + N'.sys.query_store_query AS qsq
          WHERE qsp.query_id = qsq.query_id
          AND EXISTS
              (
                  SELECT
                      1/0
                  FROM ' + @database_name_quoted + N'.sys.query_store_query_text AS qsqt
                  WHERE qsqt.query_text_id = qsq.query_text_id
                  AND   qsqt.query_sql_text LIKE @query_text_search
              )
      )';

    /* If we are escaping bracket character in our query text search, add the ESCAPE clause and character to the LIKE subquery*/
    IF @escape_brackets = 1
    BEGIN
        SELECT
            @sql =
                REPLACE
                (
                    @sql,
                    N'@query_text_search',
                    N'@query_text_search ESCAPE ''' + @escape_character + N''''
                );
    END;

/*If we're searching by a procedure name, limit the text search to it */
IF
(
    @procedure_name IS NOT NULL
AND @procedure_exists = 1
)
BEGIN
    SELECT
        @sql += N'
AND   EXISTS
      (
          SELECT
              1/0
          FROM #procedure_plans AS pp
          WHERE pp.plan_id = qsp.plan_id
      )';
END;

    SELECT
        @sql += N'
    OPTION(RECOMPILE);' + @nc10;

    IF @debug = 1
    BEGIN
        PRINT LEN(@sql);
        PRINT @sql;
    END;

    INSERT
        #query_text_search WITH(TABLOCK)
    (
        plan_id
    )
    EXEC sys.sp_executesql
        @sql,
      N'@query_text_search nvarchar(4000)',
        @query_text_search;

    IF @troubleshoot_performance = 1
    BEGIN
        SET STATISTICS XML OFF;

        EXEC sys.sp_executesql
            @troubleshoot_update,
          N'@current_table nvarchar(100)',
            @current_table;

        EXEC sys.sp_executesql
            @troubleshoot_info,
          N'@sql nvarchar(max),
            @current_table nvarchar(100)',
            @sql,
            @current_table;
    END;

    SELECT
        @where_clause += N'AND   EXISTS
       (
           SELECT
               1/0
           FROM #query_text_search AS qst
           WHERE qst.plan_id = qsrs.plan_id
       )' + @nc10;
END;

/*
Validate wait stats stuff
*/
IF @wait_filter IS NOT NULL
BEGIN
    BEGIN
        SELECT
            @current_table = 'inserting #wait_filter',
            @sql = @isolation_level;

        IF @troubleshoot_performance = 1
        BEGIN
            EXEC sys.sp_executesql
                @troubleshoot_insert,
              N'@current_table nvarchar(100)',
                @current_table;

            SET STATISTICS XML ON;
        END;

        SELECT
            @sql += N'
SELECT TOP (@top)
    qsws.plan_id
FROM  ' + @database_name_quoted + N'.sys.query_store_wait_stats AS qsws
WHERE 1 = 1
AND   qsws.wait_category = ' +
CASE @wait_filter
     WHEN 'cpu' THEN N'1'
     WHEN 'lock' THEN N'3'
     WHEN 'locks' THEN N'3'
     WHEN 'latch' THEN N'4'
     WHEN 'latches' THEN N'4'
     WHEN 'buffer latch' THEN N'5'
     WHEN 'buffer latches' THEN N'5'
     WHEN 'buffer io' THEN N'6'
     WHEN 'log' THEN N'14'
     WHEN 'log io' THEN N'14'
     WHEN 'network' THEN N'15'
     WHEN 'network io' THEN N'15'
     WHEN 'parallel' THEN N'16'
     WHEN 'parallelism' THEN N'16'
     WHEN 'memory' THEN N'17'
END
+ N'
GROUP BY
    qsws.plan_id
HAVING
    SUM(qsws.avg_query_wait_time_ms) > 1000.
ORDER BY
    SUM(qsws.avg_query_wait_time_ms) DESC
OPTION(RECOMPILE, OPTIMIZE FOR (@top = 9223372036854775807));' + @nc10;
    END;

    IF @debug = 1
    BEGIN
        PRINT LEN(@sql);
        PRINT @sql;
    END;

    INSERT
        #wait_filter WITH(TABLOCK)
    (
        plan_id
    )
    EXEC sys.sp_executesql
        @sql,
      N'@top bigint',
        @top;

    IF @troubleshoot_performance = 1
    BEGIN
        SET STATISTICS XML OFF;

        EXEC sys.sp_executesql
            @troubleshoot_update,
          N'@current_table nvarchar(100)',
            @current_table;

        EXEC sys.sp_executesql
            @troubleshoot_info,
          N'@sql nvarchar(max),
            @current_table nvarchar(100)',
            @sql,
            @current_table;
    END;

    SELECT
        @where_clause += N'AND   EXISTS
       (
           SELECT
               1/0
           FROM #wait_filter AS wf
           WHERE wf.plan_id = qsrs.plan_id
       )' + @nc10;
END;


/*
This section screens out index create and alter statements because who cares
*/

SELECT
    @current_table = 'inserting #maintenance_plans',
    @sql = @isolation_level;

IF @troubleshoot_performance = 1
BEGIN
    EXEC sys.sp_executesql
        @troubleshoot_insert,
      N'@current_table nvarchar(100)',
        @current_table;

    SET STATISTICS XML ON;
END;

SELECT
    @sql += N'
SELECT DISTINCT
   qsp.plan_id
FROM ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
WHERE NOT EXISTS
      (
          SELECT
             1/0
          FROM ' + @database_name_quoted + N'.sys.query_store_query AS qsq
          JOIN ' + @database_name_quoted + N'.sys.query_store_query_text AS qsqt
            ON qsqt.query_text_id = qsq.query_text_id
          WHERE qsq.query_id = qsp.query_id
          AND   qsqt.query_sql_text NOT LIKE N''ALTER INDEX%''
          AND   qsqt.query_sql_text NOT LIKE N''ALTER TABLE%''
          AND   qsqt.query_sql_text NOT LIKE N''CREATE%INDEX%''
          AND   qsqt.query_sql_text NOT LIKE N''CREATE STATISTICS%''
          AND   qsqt.query_sql_text NOT LIKE N''UPDATE STATISTICS%''
          AND   qsqt.query_sql_text NOT LIKE N''SELECT StatMan%''
          AND   qsqt.query_sql_text NOT LIKE N''DBCC%''
          AND   qsqt.query_sql_text NOT LIKE N''(@[_]msparam%''
      )
OPTION(RECOMPILE);' + @nc10;

IF @debug = 1
BEGIN
    PRINT LEN(@sql);
    PRINT @sql;
END;

INSERT
    #maintenance_plans WITH(TABLOCK)
(
    plan_id
)
EXEC sys.sp_executesql
    @sql;

IF @troubleshoot_performance = 1
BEGIN
    SET STATISTICS XML OFF;

    EXEC sys.sp_executesql
        @troubleshoot_update,
      N'@current_table nvarchar(100)',
        @current_table;

    EXEC sys.sp_executesql
        @troubleshoot_info,
      N'@sql nvarchar(max),
        @current_table nvarchar(100)',
        @sql,
        @current_table;
END;

SELECT
    @where_clause += N'AND   NOT EXISTS
      (
          SELECT
              1/0
          FROM #maintenance_plans AS mp
          WHERE mp.plan_id = qsrs.plan_id
      )' + @nc10;

/*
Tidy up the where clause a bit
*/
SELECT
    @where_clause =
        SUBSTRING
        (
            @where_clause,
            1,
            LEN(@where_clause) - 1
        );

/*
This gets the plan_ids we care about
*/
SELECT
    @current_table = 'inserting #distinct_plans',
    @sql = @isolation_level;

IF @troubleshoot_performance = 1
BEGIN
    EXEC sys.sp_executesql
        @troubleshoot_insert,
      N'@current_table nvarchar(100)',
        @current_table;

    SET STATISTICS XML ON;
END;

SELECT
    @sql += N'
SELECT TOP (@top)
    qsrs.plan_id
FROM ' + @database_name_quoted + N'.sys.query_store_runtime_stats AS qsrs
WHERE 1 = 1
' + @where_clause
  + N'
GROUP
    BY qsrs.plan_id
ORDER BY
    MAX(' +
CASE @sort_order
     WHEN 'cpu' THEN N'qsrs.avg_cpu_time'
     WHEN 'logical reads' THEN N'qsrs.avg_logical_io_reads'
     WHEN 'physical reads' THEN N'qsrs.avg_physical_io_reads'
     WHEN 'writes' THEN N'qsrs.avg_logical_io_writes'
     WHEN 'duration' THEN N'qsrs.avg_duration'
     WHEN 'memory' THEN N'qsrs.avg_query_max_used_memory'
     WHEN 'tempdb' THEN CASE WHEN @new = 1 THEN N'qsrs.avg_tempdb_space_used' ELSE N'qsrs.avg_cpu_time' END
     WHEN 'executions' THEN N'qsrs.count_executions'
     WHEN 'recent' THEN N'qsrs.last_execution_time'
     ELSE N'qsrs.avg_cpu_time'
END +
N') DESC
OPTION(RECOMPILE, OPTIMIZE FOR (@top = 9223372036854775807));' + @nc10;

IF @debug = 1
BEGIN
    PRINT LEN(@sql);
    PRINT @sql;
END;

INSERT
    #distinct_plans WITH(TABLOCK)
(
    plan_id
)
EXEC sys.sp_executesql
    @sql,
    @parameters,
    @top,
    @start_date,
    @end_date,
    @execution_count,
    @duration_ms,
    @execution_type_desc,
    @database_id,
    @queries_top,
    @work_start_utc,
    @work_end_utc;

IF @troubleshoot_performance = 1
BEGIN
    SET STATISTICS XML OFF;

    EXEC sys.sp_executesql
        @troubleshoot_update,
      N'@current_table nvarchar(100)',
        @current_table;

    EXEC sys.sp_executesql
        @troubleshoot_info,
      N'@sql nvarchar(max),
        @current_table nvarchar(100)',
        @sql,
        @current_table;
END; /*End gathering plan ids*/

/*
This gets the runtime stats for the plans we care about
*/
SELECT
    @current_table = 'inserting #query_store_runtime_stats',
    @sql = @isolation_level;

IF @troubleshoot_performance = 1
BEGIN
    EXEC sys.sp_executesql
        @troubleshoot_insert,
      N'@current_table nvarchar(100)',
        @current_table;

    SET STATISTICS XML ON;
END;

SELECT
    @sql += N'
SELECT
    @database_id,
    MAX(qsrs.runtime_stats_id),
    qsrs.plan_id,
    MAX(qsrs.runtime_stats_interval_id),
    MAX(qsrs.execution_type_desc),
    MIN(qsrs.first_execution_time),
    MAX(qsrs.last_execution_time),
    SUM(qsrs.count_executions),
    AVG((qsrs.avg_duration / 1000.)),
    MAX((qsrs.last_duration / 1000.)),
    MIN((qsrs.min_duration / 1000.)),
    MAX((qsrs.max_duration / 1000.)),
    AVG((qsrs.avg_cpu_time / 1000.)),
    MAX((qsrs.last_cpu_time / 1000.)),
    MIN((qsrs.min_cpu_time / 1000.)),
    MAX((qsrs.max_cpu_time / 1000.)),
    AVG(((qsrs.avg_logical_io_reads * 8.) / 1024.)),
    MAX(((qsrs.last_logical_io_reads * 8.) / 1024.)),
    MIN(((qsrs.min_logical_io_reads * 8.) / 1024.)),
    MAX(((qsrs.max_logical_io_reads * 8.) / 1024.)),
    AVG(((qsrs.avg_logical_io_writes * 8.) / 1024.)),
    MAX(((qsrs.last_logical_io_writes * 8.) / 1024.)),
    MIN(((qsrs.min_logical_io_writes * 8.) / 1024.)),
    MAX(((qsrs.max_logical_io_writes * 8.) / 1024.)),
    AVG(((qsrs.avg_physical_io_reads * 8.) / 1024.)),
    MAX(((qsrs.last_physical_io_reads * 8.) / 1024.)),
    MIN(((qsrs.min_physical_io_reads * 8.) / 1024.)),
    MAX(((qsrs.max_physical_io_reads * 8.) / 1024.)),
    AVG((qsrs.avg_clr_time / 1000.)),
    MAX((qsrs.last_clr_time / 1000.)),
    MIN((qsrs.min_clr_time / 1000.)),
    MAX((qsrs.max_clr_time / 1000.)),
    MAX(qsrs.last_dop),
    MIN(qsrs.min_dop),
    MAX(qsrs.max_dop),
    AVG(((qsrs.avg_query_max_used_memory * 8.) / 1024.)),
    MAX(((qsrs.last_query_max_used_memory * 8.) / 1024.)),
    MIN(((qsrs.min_query_max_used_memory * 8.) / 1024.)),
    MAX(((qsrs.max_query_max_used_memory * 8.) / 1024.)),
    AVG(qsrs.avg_rowcount),
    MAX(qsrs.last_rowcount),
    MIN(qsrs.min_rowcount),
    MAX(qsrs.max_rowcount),';

IF @new = 1
    BEGIN
        SELECT
            @sql += N'
    AVG(((qsrs.avg_num_physical_io_reads * 8.) / 1024.)),
    MAX(((qsrs.last_num_physical_io_reads * 8.) / 1024.)),
    MIN(((qsrs.min_num_physical_io_reads * 8.) / 1024.)),
    MAX(((qsrs.max_num_physical_io_reads * 8.) / 1024.)),
    AVG((qsrs.avg_log_bytes_used / 100000000.)),
    MAX((qsrs.last_log_bytes_used / 100000000.)),
    MIN((qsrs.min_log_bytes_used / 100000000.)),
    MAX((qsrs.max_log_bytes_used / 100000000.)),
    AVG(((qsrs.avg_tempdb_space_used * 8) / 1024.)),
    MAX(((qsrs.last_tempdb_space_used * 8) / 1024.)),
    MIN(((qsrs.min_tempdb_space_used * 8) / 1024.)),
    MAX(((qsrs.max_tempdb_space_used * 8) / 1024.)),';
    END;

IF @new = 0
    BEGIN
        SELECT
            @sql += N'
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,';
    END;

SELECT
    @sql += N'
    context_settings = NULL
FROM #distinct_plans AS dp
CROSS APPLY
(
    SELECT TOP (@queries_top)
        qsrs.*
    FROM ' + @database_name_quoted + N'.sys.query_store_runtime_stats AS qsrs
    WHERE qsrs.plan_id = dp.plan_id
    AND   1 = 1
    ' + @where_clause
  + N'
    ORDER BY ' +
CASE @sort_order
     WHEN 'cpu' THEN N'qsrs.avg_cpu_time'
     WHEN 'logical reads' THEN N'qsrs.avg_logical_io_reads'
     WHEN 'physical reads' THEN N'qsrs.avg_physical_io_reads'
     WHEN 'writes' THEN N'qsrs.avg_logical_io_writes'
     WHEN 'duration' THEN N'qsrs.avg_duration'
     WHEN 'memory' THEN N'qsrs.avg_query_max_used_memory'
     WHEN 'tempdb' THEN CASE WHEN @new = 1 THEN N'qsrs.avg_tempdb_space_used' ELSE N'qsrs.avg_cpu_time' END
     WHEN 'executions' THEN N'qsrs.count_executions'
     WHEN 'recent' THEN N'qsrs.last_execution_time'
     ELSE N'qsrs.avg_cpu_time'
END + N' DESC
) AS qsrs
GROUP BY
    qsrs.plan_id
OPTION(RECOMPILE, OPTIMIZE FOR (@queries_top = 9223372036854775807));' + @nc10;

IF @debug = 1
BEGIN
    PRINT LEN(@sql);
    PRINT @sql;
END;

INSERT
    #query_store_runtime_stats WITH(TABLOCK)
(
    database_id, runtime_stats_id, plan_id, runtime_stats_interval_id, execution_type_desc,
    first_execution_time, last_execution_time, count_executions,
    avg_duration_ms, last_duration_ms, min_duration_ms, max_duration_ms,
    avg_cpu_time_ms, last_cpu_time_ms, min_cpu_time_ms, max_cpu_time_ms,
    avg_logical_io_reads_mb, last_logical_io_reads_mb, min_logical_io_reads_mb, max_logical_io_reads_mb,
    avg_logical_io_writes_mb, last_logical_io_writes_mb, min_logical_io_writes_mb, max_logical_io_writes_mb,
    avg_physical_io_reads_mb, last_physical_io_reads_mb, min_physical_io_reads_mb, max_physical_io_reads_mb,
    avg_clr_time_ms, last_clr_time_ms, min_clr_time_ms, max_clr_time_ms,
    last_dop, min_dop, max_dop,
    avg_query_max_used_memory_mb, last_query_max_used_memory_mb, min_query_max_used_memory_mb, max_query_max_used_memory_mb,
    avg_rowcount, last_rowcount, min_rowcount, max_rowcount,
    avg_num_physical_io_reads_mb, last_num_physical_io_reads_mb, min_num_physical_io_reads_mb, max_num_physical_io_reads_mb,
    avg_log_bytes_used_mb, last_log_bytes_used_mb, min_log_bytes_used_mb, max_log_bytes_used_mb,
    avg_tempdb_space_used_mb, last_tempdb_space_used_mb, min_tempdb_space_used_mb, max_tempdb_space_used_mb,
    context_settings
)
EXEC sys.sp_executesql
    @sql,
    @parameters,
    @top,
    @start_date,
    @end_date,
    @execution_count,
    @duration_ms,
    @execution_type_desc,
    @database_id,
    @queries_top,
    @work_start_utc,
    @work_end_utc;

IF @troubleshoot_performance = 1
BEGIN
    SET STATISTICS XML OFF;

    EXEC sys.sp_executesql
        @troubleshoot_update,
      N'@current_table nvarchar(100)',
        @current_table;

    EXEC sys.sp_executesql
        @troubleshoot_info,
      N'@sql nvarchar(max),
        @current_table nvarchar(100)',
        @sql,
        @current_table;
END; /*End getting runtime stats*/

/*
This gets the query plans we're after
*/
SELECT
    @current_table = 'inserting #query_store_plan',
    @sql = @isolation_level;

IF @troubleshoot_performance = 1
BEGIN
    EXEC sys.sp_executesql
        @troubleshoot_insert,
      N'@current_table nvarchar(100)',
        @current_table;

    SET STATISTICS XML ON;
END;

SELECT
    @sql += N'
SELECT
    @database_id,
    qsp.plan_id,
    qsp.query_id,
    all_plan_ids =
        STUFF
        (
            (
                SELECT DISTINCT
                    '', '' +
                    RTRIM
                        (qsp_plans.plan_id)
                FROM ' + @database_name_quoted + N'.sys.query_store_plan AS qsp_plans
                WHERE qsp_plans.query_id = qsp.query_id
                FOR XML PATH(''''), TYPE
            ).value(''./text()[1]'', ''varchar(max)''),
            1,
            2,
            ''''
        ),
    qsp.plan_group_id,
    qsp.engine_version,
    qsp.compatibility_level,
    qsp.query_plan_hash,
    qsp.query_plan,
    qsp.is_online_index_plan,
    qsp.is_trivial_plan,
    qsp.is_parallel_plan,
    qsp.is_forced_plan,
    qsp.is_natively_compiled,
    qsp.force_failure_count,
    qsp.last_force_failure_reason_desc,
    qsp.count_compiles,
    qsp.initial_compile_start_time,
    qsp.last_compile_start_time,
    qsp.last_execution_time,
    (qsp.avg_compile_duration / 1000.),
    (qsp.last_compile_duration / 1000.),';

IF
(
      @new = 0
  AND @sql_2022_views = 0
)
BEGIN
    SELECT
        @sql += N'
    NULL,
    NULL,
    NULL,
    NULL';
END;

IF
(
      @new = 1
  AND @sql_2022_views = 0
)
BEGIN
    SELECT
        @sql += N'
    qsp.plan_forcing_type_desc,
    NULL,
    NULL,
    NULL';
END;

IF
(
      @new = 1
  AND @sql_2022_views = 1
)
BEGIN
    SELECT
        @sql += N'
    qsp.plan_forcing_type_desc,
    qsp.has_compile_replay_script,
    qsp.is_optimized_plan_forcing_disabled,
    qsp.plan_type_desc';
END;

SELECT
    @sql += N'
FROM #query_store_runtime_stats AS qsrs
CROSS APPLY
(
    SELECT TOP (@plans_top)
        qsp.*
    FROM ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
    WHERE qsp.plan_id = qsrs.plan_id
    AND   qsp.is_online_index_plan = 0
    ORDER BY
        qsp.last_execution_time DESC
) AS qsp
WHERE qsrs.database_id = @database_id
OPTION(RECOMPILE, OPTIMIZE FOR (@plans_top = 9223372036854775807));' + @nc10;

IF @debug = 1
BEGIN
    PRINT LEN(@sql);
    PRINT @sql;
END;

INSERT
    #query_store_plan WITH(TABLOCK)
(
    database_id,
    plan_id,
    query_id,
    all_plan_ids,
    plan_group_id,
    engine_version,
    compatibility_level,
    query_plan_hash,
    query_plan,
    is_online_index_plan,
    is_trivial_plan,
    is_parallel_plan,
    is_forced_plan,
    is_natively_compiled,
    force_failure_count,
    last_force_failure_reason_desc,
    count_compiles,
    initial_compile_start_time,
    last_compile_start_time,
    last_execution_time,
    avg_compile_duration_ms,
    last_compile_duration_ms,
    plan_forcing_type_desc,
    has_compile_replay_script,
    is_optimized_plan_forcing_disabled,
    plan_type_desc
)
EXEC sys.sp_executesql
    @sql,
  N'@plans_top bigint,
    @database_id int',
    @plans_top,
    @database_id;

IF @troubleshoot_performance = 1
BEGIN
    SET STATISTICS XML OFF;

    EXEC sys.sp_executesql
        @troubleshoot_update,
      N'@current_table nvarchar(100)',
        @current_table;

    EXEC sys.sp_executesql
        @troubleshoot_info,
      N'@sql nvarchar(max),
        @current_table nvarchar(100)',
        @sql,
        @current_table;
END; /*End getting query plans*/

/*
This gets some query information
*/
SELECT
    @current_table = 'inserting #query_store_query',
    @sql = @isolation_level;

IF @troubleshoot_performance = 1
BEGIN
    EXEC sys.sp_executesql
        @troubleshoot_insert,
      N'@current_table nvarchar(100)',
        @current_table;

    SET STATISTICS XML ON;
END;

SELECT
    @sql += N'
SELECT
    @database_id,
    qsq.query_id,
    qsq.query_text_id,
    qsq.context_settings_id,
    qsq.object_id,
    qsq.batch_sql_handle,
    qsq.query_hash,
    qsq.is_internal_query,
    qsq.query_parameterization_type_desc,
    qsq.initial_compile_start_time,
    qsq.last_compile_start_time,
    qsq.last_execution_time,
    qsq.last_compile_batch_sql_handle,
    qsq.last_compile_batch_offset_start,
    qsq.last_compile_batch_offset_end,
    qsq.count_compiles,
    (qsq.avg_compile_duration / 1000.),
    (qsq.last_compile_duration / 1000.),
    (qsq.avg_bind_duration / 1000.),
    (qsq.last_bind_duration / 1000.),
    (qsq.avg_bind_cpu_time / 1000.),
    (qsq.last_bind_cpu_time / 1000.),
    (qsq.avg_optimize_duration / 1000.),
    (qsq.last_optimize_duration / 1000.),
    (qsq.avg_optimize_cpu_time / 1000.),
    (qsq.last_optimize_cpu_time / 1000.),
    ((qsq.avg_compile_memory_kb * 8) / 1024.),
    ((qsq.last_compile_memory_kb * 8) / 1024.),
    ((qsq.max_compile_memory_kb * 8) / 1024.),
    qsq.is_clouddb_internal_query
FROM #query_store_plan AS qsp
CROSS APPLY
(
    SELECT TOP (1)
        qsq.*
    FROM ' + @database_name_quoted + N'.sys.query_store_query AS qsq
    WHERE qsq.query_id = qsp.query_id
    ORDER
        BY qsq.last_execution_time DESC
) AS qsq
WHERE qsp.database_id = @database_id
OPTION(RECOMPILE);' + @nc10;

IF @debug = 1
BEGIN
    PRINT LEN(@sql);
    PRINT @sql;
END;

INSERT
    #query_store_query WITH(TABLOCK)
(
    database_id,
    query_id,
    query_text_id,
    context_settings_id,
    object_id,
    batch_sql_handle,
    query_hash,
    is_internal_query,
    query_parameterization_type_desc,
    initial_compile_start_time,
    last_compile_start_time,
    last_execution_time,
    last_compile_batch_sql_handle,
    last_compile_batch_offset_start,
    last_compile_batch_offset_end,
    count_compiles,
    avg_compile_duration_ms,
    last_compile_duration_ms,
    avg_bind_duration_ms,
    last_bind_duration_ms,
    avg_bind_cpu_time_ms,
    last_bind_cpu_time_ms,
    avg_optimize_duration_ms,
    last_optimize_duration_ms,
    avg_optimize_cpu_time_ms,
    last_optimize_cpu_time_ms,
    avg_compile_memory_mb,
    last_compile_memory_mb,
    max_compile_memory_mb,
    is_clouddb_internal_query
)
EXEC sys.sp_executesql
    @sql,
  N'@database_id int',
    @database_id;

IF @troubleshoot_performance = 1
BEGIN
    SET STATISTICS XML OFF;

    EXEC sys.sp_executesql
        @troubleshoot_update,
      N'@current_table nvarchar(100)',
        @current_table;

    EXEC sys.sp_executesql
        @troubleshoot_info,
      N'@sql nvarchar(max),
        @current_table nvarchar(100)',
        @sql,
        @current_table;
END; /*End getting query details*/

/*
This gets the query text for them!
*/
SELECT
    @current_table = 'inserting #query_store_query_text',
    @sql = @isolation_level;

IF @troubleshoot_performance = 1
BEGIN
    EXEC sys.sp_executesql
        @troubleshoot_insert,
      N'@current_table nvarchar(100)',
        @current_table;

    SET STATISTICS XML ON;
END;


SELECT
    @sql += N'
SELECT
    @database_id,
    qsqt.query_text_id,
    query_sql_text =
        (
             SELECT
                 [processing-instruction(query)] =
                     REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                     REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                     REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                         qsqt.query_sql_text COLLATE Latin1_General_BIN2,
                     NCHAR(31),N''?''),NCHAR(30),N''?''),NCHAR(29),N''?''),NCHAR(28),N''?''),NCHAR(27),N''?''),NCHAR(26),N''?''),NCHAR(25),N''?''),NCHAR(24),N''?''),NCHAR(23),N''?''),NCHAR(22),N''?''),
                     NCHAR(21),N''?''),NCHAR(20),N''?''),NCHAR(19),N''?''),NCHAR(18),N''?''),NCHAR(17),N''?''),NCHAR(16),N''?''),NCHAR(15),N''?''),NCHAR(14),N''?''),NCHAR(12),N''?''),
                     NCHAR(11),N''?''),NCHAR(8),N''?''),NCHAR(7),N''?''),NCHAR(6),N''?''),NCHAR(5),N''?''),NCHAR(4),N''?''),NCHAR(3),N''?''),NCHAR(2),N''?''),NCHAR(1),N''?''),NCHAR(0),N'''')
             FOR XML
                 PATH(''''),
                 TYPE
        ),
    qsqt.statement_sql_handle,
    qsqt.is_part_of_encrypted_module,
    qsqt.has_restricted_text
FROM #query_store_query AS qsq
CROSS APPLY
(
    SELECT TOP (1)
        qsqt.*
    FROM ' + @database_name_quoted + N'.sys.query_store_query_text AS qsqt
    WHERE qsqt.query_text_id = qsq.query_text_id
) AS qsqt
WHERE qsq.database_id = @database_id
OPTION(RECOMPILE);' + @nc10;

IF @debug = 1
BEGIN
    PRINT LEN(@sql);
    PRINT @sql;
END;

INSERT
    #query_store_query_text WITH(TABLOCK)
(
    database_id,
    query_text_id,
    query_sql_text,
    statement_sql_handle,
    is_part_of_encrypted_module,
    has_restricted_text
)
EXEC sys.sp_executesql
    @sql,
  N'@database_id int',
    @database_id;

IF @troubleshoot_performance = 1
BEGIN
    SET STATISTICS XML OFF;

    EXEC sys.sp_executesql
        @troubleshoot_update,
      N'@current_table nvarchar(100)',
        @current_table;

    EXEC sys.sp_executesql
        @troubleshoot_info,
      N'@sql nvarchar(max),
        @current_table nvarchar(100)',
        @sql,
        @current_table;
END; /*End getting query text*/

/*
Here we try to get some data from the "plan cache"
that isn't available in Query Store :(
*/
SELECT
    @sql = N'',
    @current_table = 'inserting #dm_exec_query_stats';

IF @troubleshoot_performance = 1
BEGIN
    EXEC sys.sp_executesql
        @troubleshoot_insert,
      N'@current_table nvarchar(100)',
        @current_table;

    SET STATISTICS XML ON;
END;

INSERT
    #dm_exec_query_stats WITH(TABLOCK)
(
    statement_sql_handle,
    total_grant_mb,
    last_grant_mb,
    min_grant_mb,
    max_grant_mb,
    total_used_grant_mb,
    last_used_grant_mb,
    min_used_grant_mb,
    max_used_grant_mb,
    total_ideal_grant_mb,
    last_ideal_grant_mb,
    min_ideal_grant_mb,
    max_ideal_grant_mb,
    total_reserved_threads,
    last_reserved_threads,
    min_reserved_threads,
    max_reserved_threads,
    total_used_threads,
    last_used_threads,
    min_used_threads,
    max_used_threads
)
SELECT
    deqs.statement_sql_handle,
    MAX(deqs.total_grant_kb) / 1024.,
    MAX(deqs.last_grant_kb) / 1024.,
    MAX(deqs.min_grant_kb) / 1024.,
    MAX(deqs.max_grant_kb) / 1024.,
    MAX(deqs.total_used_grant_kb) / 1024.,
    MAX(deqs.last_used_grant_kb) / 1024.,
    MAX(deqs.min_used_grant_kb) / 1024.,
    MAX(deqs.max_used_grant_kb) / 1024.,
    MAX(deqs.total_ideal_grant_kb) / 1024.,
    MAX(deqs.last_ideal_grant_kb) / 1024.,
    MAX(deqs.min_ideal_grant_kb) / 1024.,
    MAX(deqs.max_ideal_grant_kb) / 1024.,
    MAX(deqs.total_reserved_threads),
    MAX(deqs.last_reserved_threads),
    MAX(deqs.min_reserved_threads),
    MAX(deqs.max_reserved_threads),
    MAX(deqs.total_used_threads),
    MAX(deqs.last_used_threads),
    MAX(deqs.min_used_threads),
    MAX(deqs.max_used_threads)
FROM sys.dm_exec_query_stats AS deqs
WHERE EXISTS
      (
          SELECT
              1/0
          FROM #query_store_query_text AS qsqt
          WHERE qsqt.statement_sql_handle = deqs.statement_sql_handle
      )
GROUP BY
    deqs.statement_sql_handle
OPTION(RECOMPILE);

SELECT
    @rc = @@ROWCOUNT;

IF @troubleshoot_performance = 1
BEGIN
    SET STATISTICS XML OFF;

    EXEC sys.sp_executesql
        @troubleshoot_update,
      N'@current_table nvarchar(100)',
        @current_table;

    EXEC sys.sp_executesql
        @troubleshoot_info,
      N'@sql nvarchar(max),
        @current_table nvarchar(100)',
        @sql,
        @current_table;
END; /*End getting runtime stats*/

/*Only update if we got anything*/
IF @rc > 0
BEGIN
    SELECT
        @current_table = 'updating #dm_exec_query_stats';

    IF @troubleshoot_performance = 1
    BEGIN
        EXEC sys.sp_executesql
            @troubleshoot_insert,
          N'@current_table nvarchar(100)',
            @current_table;

        SET STATISTICS XML ON;
    END;

    UPDATE
        qsqt
    SET
        qsqt.total_grant_mb = deqs.total_grant_mb,
        qsqt.last_grant_mb = deqs.last_grant_mb,
        qsqt.min_grant_mb = deqs.min_grant_mb,
        qsqt.max_grant_mb = deqs.max_grant_mb,
        qsqt.total_used_grant_mb = deqs.total_used_grant_mb,
        qsqt.last_used_grant_mb = deqs.last_used_grant_mb,
        qsqt.min_used_grant_mb = deqs.min_used_grant_mb,
        qsqt.max_used_grant_mb = deqs.max_used_grant_mb,
        qsqt.total_ideal_grant_mb = deqs.total_ideal_grant_mb,
        qsqt.last_ideal_grant_mb = deqs.last_ideal_grant_mb,
        qsqt.min_ideal_grant_mb = deqs.min_ideal_grant_mb,
        qsqt.max_ideal_grant_mb = deqs.max_ideal_grant_mb,
        qsqt.total_reserved_threads = deqs.total_reserved_threads,
        qsqt.last_reserved_threads = deqs.last_reserved_threads,
        qsqt.min_reserved_threads = deqs.min_reserved_threads,
        qsqt.max_reserved_threads = deqs.max_reserved_threads,
        qsqt.total_used_threads = deqs.total_used_threads,
        qsqt.last_used_threads = deqs.last_used_threads,
        qsqt.min_used_threads = deqs.min_used_threads,
        qsqt.max_used_threads = deqs.max_used_threads
    FROM #query_store_query_text AS qsqt
    JOIN #dm_exec_query_stats AS deqs
      ON qsqt.statement_sql_handle = deqs.statement_sql_handle
    OPTION(RECOMPILE);

    IF @troubleshoot_performance = 1
    BEGIN
        SET STATISTICS XML OFF;

        EXEC sys.sp_executesql
            @troubleshoot_update,
          N'@current_table nvarchar(100)',
            @current_table;

        EXEC sys.sp_executesql
            @troubleshoot_info,
          N'@sql nvarchar(max),
            @current_table nvarchar(100)',
            @sql,
            @current_table;
    END;
END; /*End updating runtime stats*/

/*
Let's check on settings, etc.
We do this first so we can see if wait stats capture mode is true more easily
*/
SELECT
    @current_table = 'inserting #database_query_store_options',
    @sql = @isolation_level;

IF @troubleshoot_performance = 1
BEGIN
    EXEC sys.sp_executesql
        @troubleshoot_insert,
      N'@current_table nvarchar(100)',
        @current_table;

    SET STATISTICS XML ON;
END;

SELECT
    @sql += N'
SELECT
    @database_id,
    dqso.desired_state_desc,
    dqso.actual_state_desc,
    readonly_reason =
        CASE dqso.readonly_reason
             WHEN 0
             THEN ''None''
             WHEN 2
             THEN ''Database in single user mode''
             WHEN 4
             THEN ''Database is in emergency mode''
             WHEN 8
             THEN ''Database is AG secondary''
             WHEN 65536
             THEN ''Reached max size: '' +
                  FORMAT(dqso.current_storage_size_mb, ''N0'') +
                  '' of '' +
                  FORMAT(dqso.max_storage_size_mb, ''N0'') +
                  ''.''
             WHEN 131072
             THEN ''The number of different statements in Query Store has reached the internal memory limit''
             WHEN 262144
             THEN ''Size of in-memory items waiting to be persisted on disk has reached the internal memory limit''
             WHEN 524288
             THEN ''Database has reached disk size limit''
             ELSE ''WOAH''
        END,
    dqso.current_storage_size_mb,
    dqso.flush_interval_seconds,
    dqso.interval_length_minutes,
    dqso.max_storage_size_mb,
    dqso.stale_query_threshold_days,
    dqso.max_plans_per_query,
    dqso.query_capture_mode_desc,'
    +
    CASE
        WHEN
        (
             @product_version > 14
          OR @azure = 1
        )
        THEN N'
    dqso.capture_policy_execution_count,
    dqso.capture_policy_total_compile_cpu_time_ms,
    dqso.capture_policy_total_execution_cpu_time_ms,
    dqso.capture_policy_stale_threshold_hours,'
        ELSE N'
    NULL,
    NULL,
    NULL,
    NULL,'
    END
    + N'
    dqso.size_based_cleanup_mode_desc,'
    +
    CASE
        WHEN (@product_version = 13
              AND @azure = 0)
        THEN N'
    NULL'
        ELSE N'
    dqso.wait_stats_capture_mode_desc'
    END
    + N'
FROM ' + @database_name_quoted + N'.sys.database_query_store_options AS dqso
OPTION(RECOMPILE);' + @nc10;

IF @debug = 1
BEGIN
    PRINT LEN(@sql);
    PRINT @sql;
END;

INSERT
    #database_query_store_options WITH(TABLOCK)
(
    database_id,
    desired_state_desc,
    actual_state_desc,
    readonly_reason,
    current_storage_size_mb,
    flush_interval_seconds,
    interval_length_minutes,
    max_storage_size_mb,
    stale_query_threshold_days,
    max_plans_per_query,
    query_capture_mode_desc,
    capture_policy_execution_count,
    capture_policy_total_compile_cpu_time_ms,
    capture_policy_total_execution_cpu_time_ms,
    capture_policy_stale_threshold_hours,
    size_based_cleanup_mode_desc,
    wait_stats_capture_mode_desc
)
EXEC sys.sp_executesql
    @sql,
  N'@database_id int',
    @database_id;

IF @troubleshoot_performance = 1
BEGIN
    SET STATISTICS XML OFF;

    EXEC sys.sp_executesql
        @troubleshoot_update,
      N'@current_table nvarchar(100)',
        @current_table;

    EXEC sys.sp_executesql
        @troubleshoot_info,
      N'@sql nvarchar(max),
        @current_table nvarchar(100)',
        @sql,
        @current_table;
END; /*End getting query store settings*/

/*
If wait stats are available, we'll grab them here
*/
IF
(
    @new = 1
    AND EXISTS
        (
            SELECT
                1/0
            FROM #database_query_store_options AS dqso
            WHERE dqso.wait_stats_capture_mode_desc = N'ON'
        )
)
BEGIN
    SELECT
        @current_table = 'inserting #query_store_wait_stats',
        @sql = @isolation_level;

    IF @troubleshoot_performance = 1
    BEGIN
        EXEC sys.sp_executesql
            @troubleshoot_insert,
          N'@current_table nvarchar(100)',
            @current_table;

        SET STATISTICS XML ON;
    END;

    SELECT
        @sql += N'
SELECT
    @database_id,
    qsws.plan_id,
    qsws.wait_category_desc,
    total_query_wait_time_ms =
        SUM(qsws.total_query_wait_time_ms),
    avg_query_wait_time_ms =
        SUM(qsws.avg_query_wait_time_ms),
    last_query_wait_time_ms =
        SUM(qsws.last_query_wait_time_ms),
    min_query_wait_time_ms =
        SUM(qsws.min_query_wait_time_ms),
    max_query_wait_time_ms =
        SUM(qsws.max_query_wait_time_ms)
FROM #query_store_runtime_stats AS qsrs
CROSS APPLY
(
    SELECT TOP (5)
        qsws.*
    FROM ' + @database_name_quoted + N'.sys.query_store_wait_stats AS qsws
    WHERE qsws.runtime_stats_interval_id = qsrs.runtime_stats_interval_id
    AND   qsws.plan_id = qsrs.plan_id
    AND   qsws.wait_category > 0
    AND   qsws.min_query_wait_time_ms > 0
    ORDER BY
        qsws.avg_query_wait_time_ms DESC
) AS qsws
WHERE qsrs.database_id = @database_id
GROUP BY
    qsws.plan_id,
    qsws.wait_category_desc
HAVING
    SUM(qsws.min_query_wait_time_ms) > 0.
OPTION(RECOMPILE);' + @nc10;

    IF @debug = 1
    BEGIN
        PRINT LEN(@sql);
        PRINT @sql;
    END;

    INSERT
        #query_store_wait_stats WITH(TABLOCK)
    (
        database_id,
        plan_id,
        wait_category_desc,
        total_query_wait_time_ms,
        avg_query_wait_time_ms,
        last_query_wait_time_ms,
        min_query_wait_time_ms,
        max_query_wait_time_ms
    )
    EXEC sys.sp_executesql
        @sql,
      N'@database_id int',
        @database_id;

    IF @troubleshoot_performance = 1
    BEGIN
        SET STATISTICS XML OFF;

        EXEC sys.sp_executesql
            @troubleshoot_update,
          N'@current_table nvarchar(100)',
            @current_table;

        EXEC sys.sp_executesql
            @troubleshoot_info,
          N'@sql nvarchar(max),
            @current_table nvarchar(100)',
            @sql,
            @current_table;
    END;
END; /*End getting wait stats*/

/*
This gets context info and settings
*/
SELECT
    @current_table = 'inserting #query_context_settings',
    @sql = @isolation_level;

IF @troubleshoot_performance = 1
BEGIN
    EXEC sys.sp_executesql
        @troubleshoot_insert,
      N'@current_table nvarchar(100)',
        @current_table;

    SET STATISTICS XML ON;
END;

SELECT
    @sql += N'
SELECT
    @database_id,
    context_settings_id,
    set_options,
    language_id,
    date_format,
    date_first,
    status,
    required_cursor_options,
    acceptable_cursor_options,
    merge_action_type,
    default_schema_id,
    is_replication_specific,
    is_contained
FROM ' + @database_name_quoted + N'.sys.query_context_settings AS qcs
WHERE EXISTS
      (
          SELECT
              1/0
          FROM #query_store_runtime_stats AS qsrs
          JOIN #query_store_plan AS qsp
            ON  qsrs.plan_id = qsp.plan_id
            AND qsrs.database_id = qsp.database_id
          JOIN #query_store_query AS qsq
            ON  qsp.query_id = qsq.query_id
            AND qsp.database_id = qsq.database_id
          WHERE qsq.context_settings_id = qcs.context_settings_id
      )
OPTION(RECOMPILE);';

INSERT
    #query_context_settings WITH(TABLOCK)
(
    database_id,
    context_settings_id,
    set_options,
    language_id,
    date_format,
    date_first,
    status,
    required_cursor_options,
    acceptable_cursor_options,
    merge_action_type,
    default_schema_id,
    is_replication_specific,
    is_contained
)
EXEC sys.sp_executesql
    @sql,
  N'@database_id int',
    @database_id;

IF @troubleshoot_performance = 1
BEGIN
    SET STATISTICS XML OFF;

    EXEC sys.sp_executesql
        @troubleshoot_update,
      N'@current_table nvarchar(100)',
        @current_table;

    EXEC sys.sp_executesql
        @troubleshoot_info,
      N'@sql nvarchar(max),
        @current_table nvarchar(100)',
        @sql,
        @current_table;
END; /*End getting context settings*/

/*
Update things to get the context settings for each query
*/
SELECT
    @current_table = 'updating context_settings in #query_store_runtime_stats';

UPDATE
    qsrs
SET
    qsrs.context_settings =
        SUBSTRING
        (
            CASE
                WHEN
                    CONVERT
                    (
                        int,
                        qcs.set_options
                    ) & 1 = 1
                THEN ', ANSI_PADDING'
                ELSE ''
            END +
            CASE
                WHEN
                    CONVERT
                    (
                        int,
                        qcs.set_options
                    ) & 8 = 8
                THEN ', CONCAT_NULL_YIELDS_NULL'
                ELSE ''
            END +
            CASE
                WHEN
                    CONVERT
                    (
                        int,
                        qcs.set_options
                    ) & 16 = 16
                THEN ', ANSI_WARNINGS'
                ELSE ''
            END +
            CASE
                WHEN
                    CONVERT
                    (
                        int,
                        qcs.set_options
                    ) & 32 = 32
                THEN ', ANSI_NULLS'
                ELSE ''
            END +
            CASE
                WHEN
                    CONVERT
                    (
                        int,
                        qcs.set_options
                    ) & 64 = 64
                THEN ', QUOTED_IDENTIFIER'
                ELSE ''
            END +
            CASE
                WHEN
                    CONVERT
                    (
                        int,
                        qcs.set_options
                    ) & 4096 = 4096
                THEN ', ARITH_ABORT'
                ELSE ''
            END +
            CASE
                WHEN
                    CONVERT
                    (
                        int,
                        qcs.set_options
                    ) & 8192 = 8192
                THEN ', NUMERIC_ROUNDABORT'
                ELSE ''
            END,
            2,
            256
        )
FROM #query_store_runtime_stats AS qsrs
JOIN #query_store_plan AS qsp
  ON  qsrs.plan_id = qsp.plan_id
  AND qsrs.database_id = qsp.database_id
JOIN #query_store_query AS qsq
  ON  qsp.query_id = qsq.query_id
  AND qsp.database_id = qsq.database_id
JOIN #query_context_settings AS qcs
  ON  qsq.context_settings_id = qcs.context_settings_id
  AND qsq.database_id = qcs.database_id
OPTION(RECOMPILE);

IF @sql_2022_views = 1
BEGIN
    /*query_store_plan_feedback*/
    SELECT
        @current_table = 'inserting #query_store_plan_feedback',
        @sql = @isolation_level;

    IF @troubleshoot_performance = 1
    BEGIN
        EXEC sys.sp_executesql
            @troubleshoot_insert,
          N'@current_table nvarchar(100)',
            @current_table;

        SET STATISTICS XML ON;
    END;

    SELECT
        @sql += N'
SELECT
    @database_id,
    qspf.plan_feedback_id,
    qspf.plan_id,
    qspf.feature_desc,
    qspf.feedback_data,
    qspf.state_desc,
    qspf.create_time,
    qspf.last_updated_time
FROM ' + @database_name_quoted + N'.sys.query_store_plan_feedback AS qspf
WHERE EXISTS
      (
          SELECT
              1/0
          FROM #query_store_plan AS qsp
          WHERE qspf.plan_id = qsp.plan_id
      )
OPTION(RECOMPILE);' + @nc10;

    IF @debug = 1
    BEGIN
        PRINT LEN(@sql);
        PRINT @sql;
    END;

    INSERT
        #query_store_plan_feedback WITH(TABLOCK)
    (
        database_id,
        plan_feedback_id,
        plan_id,
        feature_desc,
        feedback_data,
        state_desc,
        create_time,
        last_updated_time
    )
    EXEC sys.sp_executesql
        @sql,
      N'@database_id int',
        @database_id;

    IF @troubleshoot_performance = 1
    BEGIN
        SET STATISTICS XML OFF;

        EXEC sys.sp_executesql
            @troubleshoot_update,
          N'@current_table nvarchar(100)',
            @current_table;

        EXEC sys.sp_executesql
            @troubleshoot_info,
          N'@sql nvarchar(max),
            @current_table nvarchar(100)',
            @sql,
            @current_table;
    END;

    /*query_store_query_variant*/
    SELECT
        @current_table = 'inserting #query_store_query_variant',
        @sql = @isolation_level;

    IF @troubleshoot_performance = 1
    BEGIN
        EXEC sys.sp_executesql
            @troubleshoot_insert,
          N'@current_table nvarchar(100)',
            @current_table;

        SET STATISTICS XML ON;
    END;

    SELECT
        @sql += N'
SELECT
    @database_id,
    qsqv.query_variant_query_id,
    qsqv.parent_query_id,
    qsqv.dispatcher_plan_id
FROM ' + @database_name_quoted + N'.sys.query_store_query_variant AS qsqv
WHERE EXISTS
      (
          SELECT
              1/0
          FROM #query_store_plan AS qsp
          WHERE qsqv.query_variant_query_id = qsp.query_id
          AND   qsqv.dispatcher_plan_id = qsp.plan_id
      )
OPTION(RECOMPILE);' + @nc10;

    IF @debug = 1
    BEGIN
        PRINT LEN(@sql);
        PRINT @sql;
    END;

    INSERT
        #query_store_query_variant WITH(TABLOCK)
    (
        database_id,
        query_variant_query_id,
        parent_query_id,
        dispatcher_plan_id
    )
    EXEC sys.sp_executesql
        @sql,
      N'@database_id int',
        @database_id;

    IF @troubleshoot_performance = 1
    BEGIN
        SET STATISTICS XML OFF;

        EXEC sys.sp_executesql
            @troubleshoot_update,
          N'@current_table nvarchar(100)',
            @current_table;

        EXEC sys.sp_executesql
            @troubleshoot_info,
          N'@sql nvarchar(max),
            @current_table nvarchar(100)',
            @sql,
            @current_table;
    END;

    /*query_store_query_hints*/
    SELECT
        @current_table = 'inserting #query_store_query_hints',
        @sql = @isolation_level;

    IF @troubleshoot_performance = 1
    BEGIN
        EXEC sys.sp_executesql
            @troubleshoot_insert,
          N'@current_table nvarchar(100)',
            @current_table;

        SET STATISTICS XML ON;
    END;

    SELECT
        @sql += N'
SELECT
    @database_id,
    qsqh.query_hint_id,
    qsqh.query_id,
    qsqh.query_hint_text,
    qsqh.last_query_hint_failure_reason_desc,
    qsqh.query_hint_failure_count,
    qsqh.source_desc
FROM ' + @database_name_quoted + N'.sys.query_store_query_hints AS qsqh
WHERE EXISTS
      (
          SELECT
              1/0
          FROM #query_store_plan AS qsp
          WHERE qsqh.query_id = qsp.query_id
      )
OPTION(RECOMPILE);' + @nc10;

    IF @debug = 1
    BEGIN
        PRINT LEN(@sql);
        PRINT @sql;
    END;

    INSERT
        #query_store_query_hints WITH(TABLOCK)
    (
        database_id,
        query_hint_id,
        query_id,
        query_hint_text,
        last_query_hint_failure_reason_desc,
        query_hint_failure_count,
        source_desc
    )
    EXEC sys.sp_executesql
        @sql,
      N'@database_id int',
        @database_id;

    IF @troubleshoot_performance = 1
    BEGIN
        SET STATISTICS XML OFF;

        EXEC sys.sp_executesql
            @troubleshoot_update,
          N'@current_table nvarchar(100)',
            @current_table;

        EXEC sys.sp_executesql
            @troubleshoot_info,
          N'@sql nvarchar(max),
            @current_table nvarchar(100)',
            @sql,
            @current_table;
    END;

    IF @ags_present = 1
    BEGIN
        /*query_store_plan_forcing_locations*/
        SELECT
            @current_table = 'inserting #query_store_plan_forcing_locations',
            @sql = @isolation_level;

        IF @troubleshoot_performance = 1
        BEGIN
            EXEC sys.sp_executesql
                @troubleshoot_insert,
              N'@current_table nvarchar(100)',
                @current_table;

            SET STATISTICS XML ON;
        END;

        SELECT
            @sql += N'
SELECT
    @database_id,
    qspfl.plan_forcing_location_id,
    qspfl.query_id,
    qspfl.plan_id,
    qspfl.replica_group_id
FROM ' + @database_name_quoted + N'.sys.query_store_plan_forcing_locations AS qspfl
WHERE EXISTS
      (
          SELECT
              1/0
          FROM #query_store_plan AS qsp
          WHERE qspfl.query_id = qsp.query_id
          AND   qspfl.plan_id = qsp.plan_id
      )
OPTION(RECOMPILE);' + @nc10;

        IF @debug = 1
        BEGIN
            PRINT LEN(@sql);
            PRINT @sql;
        END;

        INSERT
            #query_store_plan_forcing_locations WITH(TABLOCK)
        (
            database_id,
            plan_forcing_location_id,
            query_id,
            plan_id,
            replica_group_id
        )
        EXEC sys.sp_executesql
            @sql,
          N'@database_id int',
            @database_id;

        IF @troubleshoot_performance = 1
        BEGIN
            SET STATISTICS XML OFF;

            EXEC sys.sp_executesql
                @troubleshoot_update,
              N'@current_table nvarchar(100)',
                @current_table;

            EXEC sys.sp_executesql
                @troubleshoot_info,
              N'@sql nvarchar(max),
                @current_table nvarchar(100)',
                @sql,
                @current_table;
        END;

        /*query_store_replicas*/
        SELECT
            @current_table = 'inserting #query_store_replicas',
            @sql = @isolation_level;

        IF @troubleshoot_performance = 1
        BEGIN
            EXEC sys.sp_executesql
                @troubleshoot_insert,
              N'@current_table nvarchar(100)',
                @current_table;

            SET STATISTICS XML ON;
        END;

        SELECT
            @sql += N'
SELECT
    @database_id,
    qsr.replica_group_id,
    qsr.role_type,
    qsr.replica_name
FROM ' + @database_name_quoted + N'.sys.query_store_replicas AS qsr
WHERE EXISTS
      (
          SELECT
              1/0
          FROM #query_store_plan_forcing_locations AS qspfl
          WHERE qspfl.replica_group_id = qsr.replica_group_id
      )
OPTION(RECOMPILE);' + @nc10;

        IF @debug = 1
        BEGIN
            PRINT LEN(@sql);
            PRINT @sql;
        END;

        INSERT
            #query_store_replicas WITH(TABLOCK)
        (
            database_id,
            replica_group_id,
            role_type,
            replica_name
        )
        EXEC sys.sp_executesql
            @sql,
          N'@database_id int',
            @database_id;

        IF @troubleshoot_performance = 1
        BEGIN
            SET STATISTICS XML OFF;

            EXEC sys.sp_executesql
                @troubleshoot_update,
              N'@current_table nvarchar(100)',
                @current_table;

            EXEC sys.sp_executesql
                @troubleshoot_info,
              N'@sql nvarchar(max),
                @current_table nvarchar(100)',
                @sql,
                @current_table;
        END;
    END; /*End AG queries*/
END; /*End SQL 2022 views*/

/*
These tables need to get cleared out
to avoid result pollution and
primary key violations
*/
IF @get_all_databases = 1
BEGIN
    TRUNCATE TABLE
        #distinct_plans;
    TRUNCATE TABLE
        #procedure_plans;
    TRUNCATE TABLE
        #maintenance_plans;
    TRUNCATE TABLE
        #query_text_search;
    TRUNCATE TABLE
        #dm_exec_query_stats;
    TRUNCATE TABLE
        #query_types;
    TRUNCATE TABLE
        #wait_filter;
    TRUNCATE TABLE
        #only_queries_with_hints;
    TRUNCATE TABLE
        #only_queries_with_feedback;
    TRUNCATE TABLE
        #only_queries_with_variants;
    TRUNCATE TABLE
        #forced_plans_failures;
END;

FETCH NEXT
FROM database_cursor
INTO @database_name;
END;

CLOSE database_cursor;
DEALLOCATE database_cursor;

/*
This is where we start returning results
*/
IF EXISTS
   (
      SELECT
          1/0
      FROM #query_store_runtime_stats AS qsrs
   )
BEGIN
    SELECT
        @sql = @isolation_level,
        @current_table = 'selecting final results';

    SELECT
        @sql +=
        CONVERT
        (
            nvarchar(MAX),
        N'
SELECT
    x.*
FROM
('
        );

    /*
    Expert mode returns more columns from runtime stats
    */
    IF
    (
        @expert_mode = 1
    AND @format_output = 0
    )
    BEGIN
        SELECT
            @sql +=
        CONVERT
        (
            nvarchar(MAX),
            N'
    SELECT
        source =
            ''runtime_stats'',
        database_name =
            DB_NAME(qsrs.database_id),
        qsp.query_id,
        qsrs.plan_id,
        qsp.all_plan_ids,'
        +
            CASE
                WHEN @include_plan_hashes IS NOT NULL
                THEN
        N'
        qsp.query_plan_hash,'
                WHEN @include_query_hashes IS NOT NULL
                THEN
        N'
        qsq.query_hash,'
                WHEN @include_sql_handles IS NOT NULL
                THEN
        N'
        qsqt.statement_sql_handle,'
                ELSE
        N''
            END + N'
        qsrs.execution_type_desc,
        qsq.object_name,
        qsqt.query_sql_text,
        query_plan =
             CASE
                 WHEN TRY_CAST(qsp.query_plan AS XML) IS NOT NULL
                 THEN TRY_CAST(qsp.query_plan AS XML)
                 WHEN TRY_CAST(qsp.query_plan AS XML) IS NULL
                 THEN
                     (
                         SELECT
                             [processing-instruction(query_plan)] =
                                 N''-- '' + NCHAR(13) + NCHAR(10) +
                                 N''-- This is a huge query plan.'' + NCHAR(13) + NCHAR(10) +
                                 N''-- Remove the headers and footers, save it as a .sqlplan file, and re-open it.'' + NCHAR(13) + NCHAR(10) +
                                 NCHAR(13) + NCHAR(10) +
                                 REPLACE(qsp.query_plan, N''<RelOp'', NCHAR(13) + NCHAR(10) + N''<RelOp'') +
                                 NCHAR(13) + NCHAR(10) COLLATE Latin1_General_Bin2
                         FOR XML PATH(N''''),
                                 TYPE
                     )
             END,
        qsp.compatibility_level,'
        +
            CASE @sql_2022_views
                 WHEN 1
                 THEN
        N'
        has_query_feedback =
            CASE WHEN EXISTS (SELECT 1/0 FROM #query_store_plan_feedback AS qspf WHERE qspf.plan_id = qsp.plan_id) THEN ''Yes'' ELSE ''No'' END,
        has_query_store_hints =
            CASE WHEN EXISTS (SELECT 1/0 FROM #query_store_query_hints AS qsqh WHERE qsqh.query_id = qsp.query_id) THEN ''Yes'' ELSE ''No'' END,
        has_plan_variants =
            CASE WHEN EXISTS (SELECT 1/0 FROM #query_store_query_variant AS qsqv WHERE qsqv.query_variant_query_id = qsp.query_id) THEN ''Yes'' ELSE ''No'' END,
        qsp.has_compile_replay_script,
        qsp.is_optimized_plan_forcing_disabled,
        qsp.plan_type_desc,'
                 ELSE
        N''
                 END +
        N'
        qsp.force_failure_count,
        qsp.last_force_failure_reason_desc,'
        +
        CONVERT
        (
            nvarchar(MAX),
            CASE @new
                 WHEN 1
                 THEN
        N'
        qsp.plan_forcing_type_desc,
        w.top_waits,'
                 ELSE
        N''
            END
        )
        + N'
        first_execution_time =
            CASE
                WHEN @timezone IS NULL
                THEN
                    DATEADD
                    (
                        MINUTE,
                        @utc_minutes_original,
                        qsrs.first_execution_time
                    )
                WHEN @timezone IS NOT NULL
                THEN qsrs.first_execution_time AT TIME ZONE @timezone
            END,
        first_execution_time_utc =
            qsrs.first_execution_time,
        last_execution_time =
            CASE
                WHEN @timezone IS NULL
                THEN
                    DATEADD
                    (
                        MINUTE,
                        @utc_minutes_original,
                        qsrs.last_execution_time
                    )
                WHEN @timezone IS NOT NULL
                THEN qsrs.last_execution_time AT TIME ZONE @timezone
            END,
        last_execution_time_utc =
            qsrs.last_execution_time,
        qsrs.count_executions,
        qsrs.executions_per_second,
        qsrs.avg_duration_ms,
        qsrs.total_duration_ms,
        qsrs.last_duration_ms,
        qsrs.min_duration_ms,
        qsrs.max_duration_ms,
        qsrs.avg_cpu_time_ms,
        qsrs.total_cpu_time_ms,
        qsrs.last_cpu_time_ms,
        qsrs.min_cpu_time_ms,
        qsrs.max_cpu_time_ms,
        qsrs.avg_logical_io_reads_mb,
        qsrs.total_logical_io_reads_mb,
        qsrs.last_logical_io_reads_mb,
        qsrs.min_logical_io_reads_mb,
        qsrs.max_logical_io_reads_mb,
        qsrs.avg_logical_io_writes_mb,
        qsrs.total_logical_io_writes_mb,
        qsrs.last_logical_io_writes_mb,
        qsrs.min_logical_io_writes_mb,
        qsrs.max_logical_io_writes_mb,
        qsrs.avg_physical_io_reads_mb,
        qsrs.total_physical_io_reads_mb,
        qsrs.last_physical_io_reads_mb,
        qsrs.min_physical_io_reads_mb,
        qsrs.max_physical_io_reads_mb,
        qsrs.avg_clr_time_ms,
        qsrs.total_clr_time_ms,
        qsrs.last_clr_time_ms,
        qsrs.min_clr_time_ms,
        qsrs.max_clr_time_ms,
        qsrs.last_dop,
        qsrs.min_dop,
        qsrs.max_dop,
        qsrs.avg_query_max_used_memory_mb,
        qsrs.total_query_max_used_memory_mb,
        qsrs.last_query_max_used_memory_mb,
        qsrs.min_query_max_used_memory_mb,
        qsrs.max_query_max_used_memory_mb,
        qsrs.avg_rowcount,
        qsrs.total_rowcount,
        qsrs.last_rowcount,
        qsrs.min_rowcount,
        qsrs.max_rowcount,'
        +
            CASE @new
                 WHEN 1
                 THEN
        N'
        qsrs.avg_num_physical_io_reads_mb,
        qsrs.total_num_physical_io_reads_mb,
        qsrs.last_num_physical_io_reads_mb,
        qsrs.min_num_physical_io_reads_mb,
        qsrs.max_num_physical_io_reads_mb,
        qsrs.avg_log_bytes_used_mb,
        qsrs.total_log_bytes_used_mb,
        qsrs.last_log_bytes_used_mb,
        qsrs.min_log_bytes_used_mb,
        qsrs.max_log_bytes_used_mb,
        qsrs.avg_tempdb_space_used_mb,
        qsrs.total_tempdb_space_used_mb,
        qsrs.last_tempdb_space_used_mb,
        qsrs.min_tempdb_space_used_mb,
        qsrs.max_tempdb_space_used_mb,'
                 ELSE
        N''
            END +
            CONVERT
            (
                nvarchar(MAX),
                N'
        qsrs.context_settings,
        n =
            ROW_NUMBER() OVER
            (
                PARTITION BY
                    qsrs.plan_id
                ORDER BY
                    ' +
        CASE @sort_order
            WHEN 'cpu' THEN N'qsrs.avg_cpu_time_ms'
            WHEN 'logical reads' THEN N'qsrs.avg_logical_io_reads_mb'
            WHEN 'physical reads' THEN N'qsrs.avg_physical_io_reads_mb'
            WHEN 'writes' THEN N'qsrs.avg_logical_io_writes_mb'
            WHEN 'duration' THEN N'qsrs.avg_duration_ms'
            WHEN 'memory' THEN N'qsrs.avg_query_max_used_memory_mb'
            WHEN 'tempdb' THEN CASE WHEN @new = 1 THEN N'qsrs.avg_tempdb_space_used_mb' ELSE N'qsrs.avg_cpu_time' END
            WHEN 'executions' THEN N'qsrs.count_executions'
            WHEN 'recent' THEN N'qsrs.last_execution_time'
            ELSE N'qsrs.avg_cpu_time_ms'
        END + N' DESC
            )'
            )
        );
    END; /*End expert mode 1, format output 0 columns*/

    /*
    Do we want to format things?
    */
    IF
    (
        @expert_mode = 1
    AND @format_output = 1
    )
    BEGIN
        SELECT
            @sql +=
        CONVERT
        (
            nvarchar(MAX),
            N'
    SELECT
        source =
            ''runtime_stats'',
        database_name =
            DB_NAME(qsrs.database_id),
        qsp.query_id,
        qsrs.plan_id,
        qsp.all_plan_ids,'
        +
            CASE
                WHEN @include_plan_hashes IS NOT NULL
                THEN
        N'
        qsp.query_plan_hash,'
                WHEN @include_query_hashes IS NOT NULL
                THEN
        N'
        qsq.query_hash,'
                WHEN @include_sql_handles IS NOT NULL
                THEN
        N'
        qsqt.statement_sql_handle,'
                ELSE
        N''
            END + N'
        qsrs.execution_type_desc,
        qsq.object_name,
        qsqt.query_sql_text,
        query_plan =
             CASE
                 WHEN TRY_CAST(qsp.query_plan AS XML) IS NOT NULL
                 THEN TRY_CAST(qsp.query_plan AS XML)
                 WHEN TRY_CAST(qsp.query_plan AS XML) IS NULL
                 THEN
                     (
                         SELECT
                             [processing-instruction(query_plan)] =
                                 N''-- '' + NCHAR(13) + NCHAR(10) +
                                 N''-- This is a huge query plan.'' + NCHAR(13) + NCHAR(10) +
                                 N''-- Remove the headers and footers, save it as a .sqlplan file, and re-open it.'' + NCHAR(13) + NCHAR(10) +
                                 NCHAR(13) + NCHAR(10) +
                                 REPLACE(qsp.query_plan, N''<RelOp'', NCHAR(13) + NCHAR(10) + N''<RelOp'') +
                                 NCHAR(13) + NCHAR(10) COLLATE Latin1_General_Bin2
                         FOR XML PATH(N''''),
                                 TYPE
                     )
             END,
        qsp.compatibility_level,'
        +
            CASE @sql_2022_views
                 WHEN 1
                 THEN
        N'
        has_query_feedback =
            CASE WHEN EXISTS (SELECT 1/0 FROM #query_store_plan_feedback AS qspf WHERE qspf.plan_id = qsp.plan_id) THEN ''Yes'' ELSE ''No'' END,
        has_query_store_hints =
            CASE WHEN EXISTS (SELECT 1/0 FROM #query_store_query_hints AS qsqh WHERE qsqh.query_id = qsp.query_id) THEN ''Yes'' ELSE ''No'' END,
        has_plan_variants =
            CASE WHEN EXISTS (SELECT 1/0 FROM #query_store_query_variant AS qsqv WHERE qsqv.query_variant_query_id = qsp.query_id) THEN ''Yes'' ELSE ''No'' END,
        qsp.has_compile_replay_script,
        qsp.is_optimized_plan_forcing_disabled,
        qsp.plan_type_desc,'
                 ELSE
        N''
                 END +
        N'
        qsp.force_failure_count,
        qsp.last_force_failure_reason_desc,'
        +
        CONVERT
        (
            nvarchar(MAX),
            CASE @new
                 WHEN 1
                 THEN
        N'
        qsp.plan_forcing_type_desc,
        w.top_waits,'
                 ELSE
        N''
            END
        ) +
        CONVERT
        (
            nvarchar(MAX),
            N'
        first_execution_time =
            CASE
                WHEN @timezone IS NULL
                THEN
                    DATEADD
                    (
                        MINUTE,
                        @utc_minutes_original,
                        qsrs.first_execution_time
                    )
                WHEN @timezone IS NOT NULL
                THEN qsrs.first_execution_time AT TIME ZONE @timezone
            END,
        first_execution_time_utc =
            qsrs.first_execution_time,
        last_execution_time =
            CASE
                WHEN @timezone IS NULL
                THEN
                    DATEADD
                    (
                        MINUTE,
                        @utc_minutes_original,
                        qsrs.last_execution_time
                    )
                WHEN @timezone IS NOT NULL
                THEN qsrs.last_execution_time AT TIME ZONE @timezone
            END,
        last_execution_time_utc =
            qsrs.last_execution_time,
        count_executions = FORMAT(qsrs.count_executions, ''N0''),
        executions_per_second = FORMAT(qsrs.executions_per_second, ''N0''),
        avg_duration_ms = FORMAT(qsrs.avg_duration_ms, ''N0''),
        total_duration_ms = FORMAT(qsrs.total_duration_ms, ''N0''),
        last_duration_ms = FORMAT(qsrs.last_duration_ms, ''N0''),
        min_duration_ms = FORMAT(qsrs.min_duration_ms, ''N0''),
        max_duration_ms = FORMAT(qsrs.max_duration_ms, ''N0''),
        avg_cpu_time_ms = FORMAT(qsrs.avg_cpu_time_ms, ''N0''),
        total_cpu_time_ms = FORMAT(qsrs.total_cpu_time_ms, ''N0''),
        last_cpu_time_ms = FORMAT(qsrs.last_cpu_time_ms, ''N0''),
        min_cpu_time_ms = FORMAT(qsrs.min_cpu_time_ms, ''N0''),
        max_cpu_time_ms = FORMAT(qsrs.max_cpu_time_ms, ''N0''),
        avg_logical_io_reads_mb = FORMAT(qsrs.avg_logical_io_reads_mb, ''N0''),
        total_logical_io_reads_mb = FORMAT(qsrs.total_logical_io_reads_mb, ''N0''),
        last_logical_io_reads_mb = FORMAT(qsrs.last_logical_io_reads_mb, ''N0''),
        min_logical_io_reads_mb = FORMAT(qsrs.min_logical_io_reads_mb, ''N0''),
        max_logical_io_reads_mb = FORMAT(qsrs.max_logical_io_reads_mb, ''N0''),
        avg_logical_io_writes_mb = FORMAT(qsrs.avg_logical_io_writes_mb, ''N0''),
        total_logical_io_writes_mb = FORMAT(qsrs.total_logical_io_writes_mb, ''N0''),
        last_logical_io_writes_mb = FORMAT(qsrs.last_logical_io_writes_mb, ''N0''),
        min_logical_io_writes_mb = FORMAT(qsrs.min_logical_io_writes_mb, ''N0''),
        max_logical_io_writes_mb = FORMAT(qsrs.max_logical_io_writes_mb, ''N0''),
        avg_physical_io_reads_mb = FORMAT(qsrs.avg_physical_io_reads_mb, ''N0''),
        total_physical_io_reads_mb = FORMAT(qsrs.total_physical_io_reads_mb, ''N0''),
        last_physical_io_reads_mb = FORMAT(qsrs.last_physical_io_reads_mb, ''N0''),
        min_physical_io_reads_mb = FORMAT(qsrs.min_physical_io_reads_mb, ''N0''),
        max_physical_io_reads_mb = FORMAT(qsrs.max_physical_io_reads_mb, ''N0''),
        avg_clr_time_ms = FORMAT(qsrs.avg_clr_time_ms, ''N0''),
        total_clr_time_ms = FORMAT(qsrs.total_clr_time_ms, ''N0''),
        last_clr_time_ms = FORMAT(qsrs.last_clr_time_ms, ''N0''),
        min_clr_time_ms = FORMAT(qsrs.min_clr_time_ms, ''N0''),
        max_clr_time_ms = FORMAT(qsrs.max_clr_time_ms, ''N0''),
        qsrs.last_dop,
        qsrs.min_dop,
        qsrs.max_dop,
        avg_query_max_used_memory_mb = FORMAT(qsrs.avg_query_max_used_memory_mb, ''N0''),
        total_query_max_used_memory_mb = FORMAT(qsrs.total_query_max_used_memory_mb, ''N0''),
        last_query_max_used_memory_mb = FORMAT(qsrs.last_query_max_used_memory_mb, ''N0''),
        min_query_max_used_memory_mb = FORMAT(qsrs.min_query_max_used_memory_mb, ''N0''),
        max_query_max_used_memory_mb = FORMAT(qsrs.max_query_max_used_memory_mb, ''N0''),
        avg_rowcount = FORMAT(qsrs.avg_rowcount, ''N0''),
        total_rowcount = FORMAT(qsrs.total_rowcount, ''N0''),
        last_rowcount = FORMAT(qsrs.last_rowcount, ''N0''),
        min_rowcount = FORMAT(qsrs.min_rowcount, ''N0''),
        max_rowcount = FORMAT(qsrs.max_rowcount, ''N0''),'
        )
        +
            CASE @new
                 WHEN 1
                 THEN
        N'
        avg_num_physical_io_reads_mb = FORMAT(qsrs.avg_num_physical_io_reads_mb, ''N0''),
        total_num_physical_io_reads_mb = FORMAT(qsrs.total_num_physical_io_reads_mb, ''N0''),
        last_num_physical_io_reads_mb = FORMAT(qsrs.last_num_physical_io_reads_mb, ''N0''),
        min_num_physical_io_reads_mb = FORMAT(qsrs.min_num_physical_io_reads_mb, ''N0''),
        max_num_physical_io_reads_mb = FORMAT(qsrs.max_num_physical_io_reads_mb, ''N0''),
        avg_log_bytes_used_mb = FORMAT(qsrs.avg_log_bytes_used_mb, ''N0''),
        total_log_bytes_used_mb = FORMAT(qsrs.total_log_bytes_used_mb, ''N0''),
        last_log_bytes_used_mb = FORMAT(qsrs.last_log_bytes_used_mb, ''N0''),
        min_log_bytes_used_mb = FORMAT(qsrs.min_log_bytes_used_mb, ''N0''),
        max_log_bytes_used_mb = FORMAT(qsrs.max_log_bytes_used_mb, ''N0''),
        avg_tempdb_space_used_mb = FORMAT(qsrs.avg_tempdb_space_used_mb, ''N0''),
        total_tempdb_space_used_mb = FORMAT(qsrs.total_tempdb_space_used_mb, ''N0''),
        last_tempdb_space_used_mb = FORMAT(qsrs.last_tempdb_space_used_mb, ''N0''),
        min_tempdb_space_used_mb = FORMAT(qsrs.min_tempdb_space_used_mb, ''N0''),
        max_tempdb_space_used_mb = FORMAT(qsrs.max_tempdb_space_used_mb, ''N0''),'
                 ELSE
        N''
            END +
            CONVERT
            (
                nvarchar(MAX),
                N'
        qsrs.context_settings,
        n =
            ROW_NUMBER() OVER
            (
                PARTITION BY
                    qsrs.plan_id
                ORDER BY
                    ' +
        CASE @sort_order
            WHEN 'cpu' THEN N'qsrs.avg_cpu_time_ms'
            WHEN 'logical reads' THEN N'qsrs.avg_logical_io_reads_mb'
            WHEN 'physical reads' THEN N'qsrs.avg_physical_io_reads_mb'
            WHEN 'writes' THEN N'qsrs.avg_logical_io_writes_mb'
            WHEN 'duration' THEN N'qsrs.avg_duration_ms'
            WHEN 'memory' THEN N'qsrs.avg_query_max_used_memory_mb'
            WHEN 'tempdb' THEN CASE WHEN @new = 1 THEN N'qsrs.avg_tempdb_space_used_mb' ELSE N'qsrs.avg_cpu_time' END
            WHEN 'executions' THEN N'qsrs.count_executions'
            WHEN 'recent' THEN N'qsrs.last_execution_time'
            ELSE N'qsrs.avg_cpu_time_ms'
        END + N' DESC
            )'
            )
        );
    END; /*End expert mode = 1, format output = 1*/

    /*
    For non-experts only!
    */
    IF
    (
        @expert_mode = 0
    AND @format_output = 0
    )
    BEGIN
        SELECT
            @sql +=
        CONVERT
        (
            nvarchar(MAX),
            N'
    SELECT
        source =
            ''runtime_stats'',
        database_name =
            DB_NAME(qsrs.database_id),
        qsp.query_id,
        qsrs.plan_id,
        qsp.all_plan_ids,'
        +
            CASE
                WHEN @include_plan_hashes IS NOT NULL
                THEN
        N'
        qsp.query_plan_hash,'
                WHEN @include_query_hashes IS NOT NULL
                THEN
        N'
        qsq.query_hash,'
                WHEN @include_sql_handles IS NOT NULL
                THEN
        N'
        qsqt.statement_sql_handle,'
                ELSE
        N''
            END + N'
        qsrs.execution_type_desc,
        qsq.object_name,
        qsqt.query_sql_text,
        query_plan =
             CASE
                 WHEN TRY_CAST(qsp.query_plan AS XML) IS NOT NULL
                 THEN TRY_CAST(qsp.query_plan AS XML)
                 WHEN TRY_CAST(qsp.query_plan AS XML) IS NULL
                 THEN
                     (
                         SELECT
                             [processing-instruction(query_plan)] =
                                 N''-- '' + NCHAR(13) + NCHAR(10) +
                                 N''-- This is a huge query plan.'' + NCHAR(13) + NCHAR(10) +
                                 N''-- Remove the headers and footers, save it as a .sqlplan file, and re-open it.'' + NCHAR(13) + NCHAR(10) +
                                 NCHAR(13) + NCHAR(10) +
                                 REPLACE(qsp.query_plan, N''<RelOp'', NCHAR(13) + NCHAR(10) + N''<RelOp'') +
                                 NCHAR(13) + NCHAR(10) COLLATE Latin1_General_Bin2
                         FOR XML PATH(N''''),
                                 TYPE
                     )
             END,
        qsp.compatibility_level,'
        +
            CASE @sql_2022_views
                 WHEN 1
                 THEN
        N'
        has_query_feedback =
            CASE WHEN EXISTS (SELECT 1/0 FROM #query_store_plan_feedback AS qspf WHERE qspf.plan_id = qsp.plan_id) THEN ''Yes'' ELSE ''No'' END,
        has_query_store_hints =
            CASE WHEN EXISTS (SELECT 1/0 FROM #query_store_query_hints AS qsqh WHERE qsqh.query_id = qsp.query_id) THEN ''Yes'' ELSE ''No'' END,
        has_plan_variants =
            CASE WHEN EXISTS (SELECT 1/0 FROM #query_store_query_variant AS qsqv WHERE qsqv.query_variant_query_id = qsp.query_id) THEN ''Yes'' ELSE ''No'' END,
        qsp.has_compile_replay_script,
        qsp.is_optimized_plan_forcing_disabled,
        qsp.plan_type_desc,'
                 ELSE
        N''
                 END +
        N'
        qsp.force_failure_count,
        qsp.last_force_failure_reason_desc,'
        +
        CONVERT
        (
            nvarchar(MAX),
            CASE @new
                 WHEN 1
                 THEN
        N'
        qsp.plan_forcing_type_desc,
        w.top_waits,'
                 ELSE
        N''
            END
        )
        + N'
        first_execution_time =
            CASE
                WHEN @timezone IS NULL
                THEN
                    DATEADD
                    (
                        MINUTE,
                        @utc_minutes_original,
                        qsrs.first_execution_time
                    )
                WHEN @timezone IS NOT NULL
                THEN qsrs.first_execution_time AT TIME ZONE @timezone
            END,
        first_execution_time_utc =
            qsrs.first_execution_time,
        last_execution_time =
            CASE
                WHEN @timezone IS NULL
                THEN
                    DATEADD
                    (
                        MINUTE,
                        @utc_minutes_original,
                        qsrs.last_execution_time
                    )
                WHEN @timezone IS NOT NULL
                THEN qsrs.last_execution_time AT TIME ZONE @timezone
            END,
        last_execution_time_utc =
            qsrs.last_execution_time,
        qsrs.count_executions,
        qsrs.executions_per_second,
        qsrs.avg_duration_ms,
        qsrs.total_duration_ms,
        qsrs.avg_cpu_time_ms,
        qsrs.total_cpu_time_ms,
        qsrs.avg_logical_io_reads_mb,
        qsrs.total_logical_io_reads_mb,
        qsrs.avg_logical_io_writes_mb,
        qsrs.total_logical_io_writes_mb,
        qsrs.avg_physical_io_reads_mb,
        qsrs.total_physical_io_reads_mb,
        qsrs.avg_clr_time_ms,
        qsrs.total_clr_time_ms,
        qsrs.min_dop,
        qsrs.max_dop,
        qsrs.avg_query_max_used_memory_mb,
        qsrs.total_query_max_used_memory_mb,
        qsrs.avg_rowcount,
        qsrs.total_rowcount,'
        +
            CASE @new
                 WHEN 1
                 THEN
        N'
        qsrs.avg_num_physical_io_reads_mb,
        qsrs.total_num_physical_io_reads_mb,
        qsrs.avg_log_bytes_used_mb,
        qsrs.total_log_bytes_used_mb,
        qsrs.avg_tempdb_space_used_mb,
        qsrs.total_tempdb_space_used_mb,'
                 ELSE
        N''
            END +
            CONVERT
            (
                nvarchar(MAX),
                N'
        qsrs.context_settings,
        n =
            ROW_NUMBER() OVER
            (
                PARTITION BY
                    qsrs.plan_id
                ORDER BY
                    '
        +
        CASE @sort_order
            WHEN 'cpu' THEN N'qsrs.avg_cpu_time_ms'
            WHEN 'logical reads' THEN N'qsrs.avg_logical_io_reads_mb'
            WHEN 'physical reads' THEN N'qsrs.avg_physical_io_reads_mb'
            WHEN 'writes' THEN N'qsrs.avg_logical_io_writes_mb'
            WHEN 'duration' THEN N'qsrs.avg_duration_ms'
            WHEN 'memory' THEN N'qsrs.avg_query_max_used_memory_mb'
            WHEN 'tempdb' THEN CASE WHEN @new = 1 THEN N'qsrs.avg_tempdb_space_used_mb' ELSE N'qsrs.avg_cpu_time' END
            WHEN 'executions' THEN N'qsrs.count_executions'
            WHEN 'recent' THEN N'qsrs.last_execution_time'
            ELSE N'qsrs.avg_cpu_time_ms'
        END + N' DESC
            )'
            )
        );
    END; /*End expert mode = 0, format output = 0*/

    /*
    Formatted but not still not expert output
    */
    IF
    (
        @expert_mode = 0
    AND @format_output = 1
    )
    BEGIN
        SELECT
            @sql +=
        CONVERT
        (
            nvarchar(MAX),
            N'
    SELECT
        source =
            ''runtime_stats'',
        database_name =
            DB_NAME(qsrs.database_id),
        qsp.query_id,
        qsrs.plan_id,
        qsp.all_plan_ids,'
        +
            CASE
                WHEN @include_plan_hashes IS NOT NULL
                THEN
        N'
        qsp.query_plan_hash,'
                WHEN @include_query_hashes IS NOT NULL
                THEN
        N'
        qsq.query_hash,'
                WHEN @include_sql_handles IS NOT NULL
                THEN
        N'
        qsqt.statement_sql_handle,'
                ELSE
        N''
            END
        + N'
        qsrs.execution_type_desc,
        qsq.object_name,
        qsqt.query_sql_text,
        query_plan =
             CASE
                 WHEN TRY_CAST(qsp.query_plan AS XML) IS NOT NULL
                 THEN TRY_CAST(qsp.query_plan AS XML)
                 WHEN TRY_CAST(qsp.query_plan AS XML) IS NULL
                 THEN
                     (
                         SELECT
                             [processing-instruction(query_plan)] =
                                 N''-- '' + NCHAR(13) + NCHAR(10) +
                                 N''-- This is a huge query plan.'' + NCHAR(13) + NCHAR(10) +
                                 N''-- Remove the headers and footers, save it as a .sqlplan file, and re-open it.'' + NCHAR(13) + NCHAR(10) +
                                 NCHAR(13) + NCHAR(10) +
                                 REPLACE(qsp.query_plan, N''<RelOp'', NCHAR(13) + NCHAR(10) + N''<RelOp'') +
                                 NCHAR(13) + NCHAR(10) COLLATE Latin1_General_Bin2
                         FOR XML PATH(N''''),
                                 TYPE
                     )
             END,
        qsp.compatibility_level,'
        +
            CASE @sql_2022_views
                 WHEN 1
                 THEN
        N'
        has_query_feedback =
            CASE WHEN EXISTS (SELECT 1/0 FROM #query_store_plan_feedback AS qspf WHERE qspf.plan_id = qsp.plan_id) THEN ''Yes'' ELSE ''No'' END,
        has_query_store_hints =
            CASE WHEN EXISTS (SELECT 1/0 FROM #query_store_query_hints AS qsqh WHERE qsqh.query_id = qsp.query_id) THEN ''Yes'' ELSE ''No'' END,
        has_plan_variants =
            CASE WHEN EXISTS (SELECT 1/0 FROM #query_store_query_variant AS qsqv WHERE qsqv.query_variant_query_id = qsp.query_id) THEN ''Yes'' ELSE ''No'' END,
        qsp.has_compile_replay_script,
        qsp.is_optimized_plan_forcing_disabled,
        qsp.plan_type_desc,'
                 ELSE
        N''
                 END +
        N'
        qsp.force_failure_count,
        qsp.last_force_failure_reason_desc,'
        +
        CONVERT
        (
            nvarchar(MAX),
            CASE @new
                 WHEN 1
                 THEN
        N'
        qsp.plan_forcing_type_desc,
        w.top_waits,'
                 ELSE
        N''
            END
        )
        + N'
        first_execution_time =
            CASE
                WHEN @timezone IS NULL
                THEN
                    DATEADD
                    (
                        MINUTE,
                        @utc_minutes_original,
                        qsrs.first_execution_time
                    )
                WHEN @timezone IS NOT NULL
                THEN qsrs.first_execution_time AT TIME ZONE @timezone
            END,
        first_execution_time_utc =
            qsrs.first_execution_time,
        last_execution_time =
            CASE
                WHEN @timezone IS NULL
                THEN
                    DATEADD
                    (
                        MINUTE,
                        @utc_minutes_original,
                        qsrs.last_execution_time
                    )
                WHEN @timezone IS NOT NULL
                THEN qsrs.last_execution_time AT TIME ZONE @timezone
            END,
        last_execution_time_utc =
            qsrs.last_execution_time,
        count_executions = FORMAT(qsrs.count_executions, ''N0''),
        executions_per_second = FORMAT(qsrs.executions_per_second, ''N0''),
        avg_duration_ms = FORMAT(qsrs.avg_duration_ms, ''N0''),
        total_duration_ms = FORMAT(qsrs.total_duration_ms, ''N0''),
        avg_cpu_time_ms = FORMAT(qsrs.avg_cpu_time_ms, ''N0''),
        total_cpu_time_ms = FORMAT(qsrs.total_cpu_time_ms, ''N0''),
        avg_logical_io_reads_mb = FORMAT(qsrs.avg_logical_io_reads_mb, ''N0''),
        total_logical_io_reads_mb = FORMAT(qsrs.total_logical_io_reads_mb, ''N0''),
        avg_logical_io_writes_mb = FORMAT(qsrs.avg_logical_io_writes_mb, ''N0''),
        total_logical_io_writes_mb = FORMAT(qsrs.total_logical_io_writes_mb, ''N0''),
        avg_physical_io_reads_mb = FORMAT(qsrs.avg_physical_io_reads_mb, ''N0''),
        total_physical_io_reads_mb = FORMAT(qsrs.total_physical_io_reads_mb, ''N0''),
        avg_clr_time_ms = FORMAT(qsrs.avg_clr_time_ms, ''N0''),
        total_clr_time_ms = FORMAT(qsrs.total_clr_time_ms, ''N0''),
        min_dop = FORMAT(qsrs.min_dop, ''N0''),
        max_dop = FORMAT(qsrs.max_dop, ''N0''),
        avg_query_max_used_memory_mb = FORMAT(qsrs.avg_query_max_used_memory_mb, ''N0''),
        total_query_max_used_memory_mb = FORMAT(qsrs.total_query_max_used_memory_mb, ''N0''),
        avg_rowcount = FORMAT(qsrs.avg_rowcount, ''N0''),
        total_rowcount = FORMAT(qsrs.total_rowcount, ''N0''),'
        +
            CASE @new
                 WHEN 1
                 THEN
        N'
        avg_num_physical_io_reads_mb = FORMAT(qsrs.avg_num_physical_io_reads_mb, ''N0''),
        total_num_physical_io_reads_mb = FORMAT(qsrs.total_num_physical_io_reads_mb, ''N0''),
        avg_log_bytes_used_mb = FORMAT(qsrs.avg_log_bytes_used_mb, ''N0''),
        total_log_bytes_used_mb = FORMAT(qsrs.total_log_bytes_used_mb, ''N0''),
        avg_tempdb_space_used_mb = FORMAT(qsrs.avg_tempdb_space_used_mb, ''N0''),
        total_tempdb_space_used_mb = FORMAT(qsrs.total_tempdb_space_used_mb, ''N0''),'
                 ELSE
        N''
            END +
            CONVERT
            (
                nvarchar(MAX),
                N'
        qsrs.context_settings,
        n =
            ROW_NUMBER() OVER
            (
                PARTITION BY
                    qsrs.plan_id
                ORDER BY
                    '
        +
        CASE @sort_order
             WHEN 'cpu' THEN N'qsrs.avg_cpu_time_ms'
             WHEN 'logical reads' THEN N'qsrs.avg_logical_io_reads_mb'
             WHEN 'physical reads' THEN N'qsrs.avg_physical_io_reads_mb'
             WHEN 'writes' THEN N'qsrs.avg_logical_io_writes_mb'
             WHEN 'duration' THEN N'qsrs.avg_duration_ms'
             WHEN 'memory' THEN N'qsrs.avg_query_max_used_memory_mb'
             WHEN 'tempdb' THEN CASE WHEN @new = 1 THEN N'qsrs.avg_tempdb_space_used_mb' ELSE N'qsrs.avg_cpu_time' END
             WHEN 'executions' THEN N'qsrs.count_executions'
             WHEN 'recent' THEN N'qsrs.last_execution_time'
             ELSE N'qsrs.avg_cpu_time_ms'
        END + N' DESC
            )'
            )
        );
    END; /*End expert mode = 0, format output = 1*/

    /*
    Add on the from and stuff
    */
    SELECT
        @sql +=
    CONVERT
    (
        nvarchar(MAX),
        N'
    FROM #query_store_runtime_stats AS qsrs
    CROSS APPLY
    (
        SELECT
            x.*
        FROM
        (
            SELECT
                qsp.*,
                pn =
                    ROW_NUMBER() OVER
                    (
                        PARTITION BY
                            qsp.query_plan_hash
                        ORDER BY
                            qsp.last_execution_time DESC
                    )
            FROM #query_store_plan AS qsp
            WHERE qsp.plan_id = qsrs.plan_id
            AND   qsp.database_id = qsrs.database_id
        ) AS x
        WHERE x.pn = 1
    ) AS qsp
    CROSS APPLY
    (
        SELECT TOP (1)
            qsqt.*
        FROM #query_store_query AS qsq
        JOIN #query_store_query_text AS qsqt
          ON qsqt.query_text_id = qsq.query_text_id
        WHERE qsq.query_id = qsp.query_id
        AND   qsq.query_id = qsp.query_id
        ORDER BY
            qsq.last_execution_time DESC
    ) AS qsqt
    CROSS APPLY
    (
        SELECT TOP (1)
            qsq.*
        FROM #query_store_query AS qsq
        WHERE qsq.query_id = qsp.query_id
        AND   qsq.database_id = qsp.database_id
        ORDER
            BY qsq.last_execution_time DESC
    ) AS qsq'
    );

    /*
    Get wait stats if we can
    */
    IF
    (
        @new = 1
    AND @format_output = 0
    )
    BEGIN
        SELECT
            @sql +=
        CONVERT
        (
            nvarchar(MAX),
            N'
    CROSS APPLY
    (
        SELECT TOP (1)
            top_waits =
                STUFF
                (
                    (
                       SELECT TOP (5)
                            '', '' +
                            qsws.wait_category_desc +
                            '' ('' +
                            CONVERT
                            (
                                varchar(20),
                                SUM
                                (
                                    CONVERT
                                    (
                                        bigint,
                                        qsws.avg_query_wait_time_ms
                                    )
                                )
                            ) +
                            '' ms)''
                       FROM #query_store_wait_stats AS qsws
                       WHERE qsws.plan_id = qsrs.plan_id
                       AND   qsws.database_id = qsrs.database_id
                       GROUP BY
                           qsws.wait_category_desc
                       ORDER BY
                           SUM(qsws.avg_query_wait_time_ms) DESC
                       FOR XML PATH(''''), TYPE
                    ).value(''./text()[1]'', ''varchar(max)''),
                    1,
                    2,
                    ''''
                )
    ) AS w'
    );
    END; /*End format output = 0 wait stats query*/

    IF
    (
        @new = 1
    AND @format_output = 1
    )
    BEGIN
        SELECT
            @sql +=
        CONVERT
        (
            nvarchar(MAX),
            N'
    CROSS APPLY
    (
        SELECT TOP (1)
            top_waits =
                STUFF
                (
                    (
                       SELECT TOP (5)
                            '', '' +
                            qsws.wait_category_desc +
                            '' ('' +
                            FORMAT
                            (
                                SUM
                                (
                                    CONVERT
                                    (
                                        bigint,
                                        qsws.avg_query_wait_time_ms
                                    )
                                ), ''N0''
                            ) +
                            '' ms)''
                       FROM #query_store_wait_stats AS qsws
                       WHERE qsws.plan_id = qsrs.plan_id
                       AND   qsws.database_id = qsrs.database_id
                       GROUP BY
                           qsws.wait_category_desc
                       ORDER BY
                           SUM(qsws.avg_query_wait_time_ms) DESC
                       FOR XML PATH(''''), TYPE
                    ).value(''./text()[1]'', ''varchar(max)''),
                    1,
                    2,
                    ''''
                )
    ) AS w'
    );
    END; /*End format output = 1 wait stats query*/

    SELECT
        @sql +=
    CONVERT
    (
        nvarchar(MAX),
        N'
) AS x
WHERE x.n = 1
ORDER BY ' +
    CASE @format_output
         WHEN 0
         THEN
             CASE @sort_order
                  WHEN 'cpu' THEN N'x.avg_cpu_time_ms'
                  WHEN 'logical reads' THEN N'x.avg_logical_io_reads_mb'
                  WHEN 'physical reads' THEN N'x.avg_physical_io_reads_mb'
                  WHEN 'writes' THEN N'x.avg_logical_io_writes_mb'
                  WHEN 'duration' THEN N'x.avg_duration_ms'
                  WHEN 'memory' THEN N'x.avg_query_max_used_memory_mb'
                  WHEN 'tempdb' THEN CASE WHEN @new = 1 THEN N'x.avg_tempdb_space_used_mb' ELSE N'x.avg_cpu_time' END
                  WHEN 'executions' THEN N'x.count_executions'
                  WHEN 'recent' THEN N'x.last_execution_time'
                  ELSE N'x.avg_cpu_time_ms'
             END
         WHEN 1
         THEN
             CASE @sort_order
                  WHEN 'cpu' THEN N'CONVERT(money, x.avg_cpu_time_ms)'
                  WHEN 'logical reads' THEN N'CONVERT(money, x.avg_logical_io_reads_mb)'
                  WHEN 'physical reads' THEN N'CONVERT(money, x.avg_physical_io_reads_mb)'
                  WHEN 'writes' THEN N'CONVERT(money, x.avg_logical_io_writes_mb)'
                  WHEN 'duration' THEN N'CONVERT(money, x.avg_duration_ms)'
                  WHEN 'memory' THEN N'CONVERT(money, x.avg_query_max_used_memory_mb)'
                  WHEN 'tempdb' THEN CASE WHEN @new = 1 THEN N'CONVERT(money, x.avg_tempdb_space_used_mb)' ELSE N'CONVERT(money, x.avg_cpu_time)' END
                  WHEN 'executions' THEN N'CONVERT(money, x.count_executions)'
                  WHEN 'recent' THEN N'x.last_execution_time'
                  ELSE N'CONVERT(money, x.avg_cpu_time_ms)'
             END
    END
             + N' DESC
OPTION(RECOMPILE);'
    + @nc10
    );

    IF @debug = 1
    BEGIN
        PRINT LEN(@sql);
        PRINT SUBSTRING(@sql, 0, 4000);
        PRINT SUBSTRING(@sql, 4000, 8000);
        PRINT SUBSTRING(@sql, 8000, 16000);
    END;

    EXEC sys.sp_executesql
        @sql,
      N'@utc_minutes_original bigint,
        @timezone sysname',
        @utc_minutes_original,
        @timezone;
END; /*End runtime stats main query*/
ELSE
    BEGIN
        SELECT
            result =
                '#query_store_runtime_stats is empty';
    END;

/*
Return special things, unformatted
*/
IF
(
    (
         @expert_mode = 1
      OR
      (
           @only_queries_with_hints = 1
        OR @only_queries_with_feedback = 1
        OR @only_queries_with_variants = 1
      )
    )
AND @format_output = 0
)
BEGIN
    IF @sql_2022_views = 1
    BEGIN
        IF @expert_mode = 1
        BEGIN
            IF EXISTS
            (
                SELECT
                    1/0
                FROM #query_store_plan_feedback AS qspf
            )
            BEGIN
                SELECT
                    @current_table = 'selecting plan feedback';

                SELECT
                    database_name =
                        DB_NAME(qspf.database_id),
                    qspf.plan_feedback_id,
                    qspf.plan_id,
                    qspf.feature_desc,
                    qspf.feedback_data,
                    qspf.state_desc,
                    create_time =
                        CASE
                            WHEN @timezone IS NULL
                            THEN
                                DATEADD
                                (
                                    MINUTE,
                                    @utc_minutes_original,
                                    qspf.create_time
                                )
                            WHEN @timezone IS NOT NULL
                            THEN qspf.create_time AT TIME ZONE @timezone
                        END,
                    create_time_utc =
                        qspf.create_time,
                    last_updated_time =
                        CASE
                            WHEN @timezone IS NULL
                            THEN
                                DATEADD
                                (
                                    MINUTE,
                                    @utc_minutes_original,
                                    qspf.last_updated_time
                                )
                            WHEN @timezone IS NOT NULL
                            THEN qspf.last_updated_time AT TIME ZONE @timezone
                        END,
                    last_updated_time_utc =
                        qspf.last_updated_time
                FROM #query_store_plan_feedback AS qspf
                ORDER BY
                    qspf.plan_id
                OPTION(RECOMPILE);
            END;
            ELSE
            BEGIN
                SELECT
                    result = '#query_store_plan_feedback is empty';
            END;
        END;

        IF EXISTS
        (
            SELECT
                1/0
            FROM #query_store_query_hints AS qsqh
        )
        BEGIN
            SELECT
                @current_table = 'selecting query hints';

            SELECT
                database_name =
                    DB_NAME(qsqh.database_id),
                qsqh.query_hint_id,
                qsqh.query_id,
                qsqh.query_hint_text,
                qsqh.last_query_hint_failure_reason_desc,
                qsqh.query_hint_failure_count,
                qsqh.source_desc
            FROM #query_store_query_hints AS qsqh
            ORDER BY
                qsqh.query_id
            OPTION(RECOMPILE);
        END;
        ELSE
        BEGIN
            SELECT
                result = '#query_store_query_hints is empty';
        END;

        IF @expert_mode = 1
        BEGIN
            IF EXISTS
            (
                SELECT
                    1/0
                FROM #query_store_query_variant AS qsqv
            )
            BEGIN
                SELECT
                    @current_table = 'selecting query variants';

                SELECT
                    database_name =
                        DB_NAME(qsqv.database_id),
                    qsqv.query_variant_query_id,
                    qsqv.parent_query_id,
                    qsqv.dispatcher_plan_id
                FROM #query_store_query_variant AS qsqv
                ORDER BY
                    qsqv.parent_query_id
                OPTION(RECOMPILE);
            END;
            ELSE
            BEGIN
                SELECT
                    result = '#query_store_query_variant is empty';
            END;
        END;
    END;

    IF @expert_mode = 1
    BEGIN
        IF EXISTS
        (
            SELECT
                1/0
                FROM #query_store_query AS qsq
        )
        BEGIN
            SELECT
                @current_table = 'selecting compilation stats';

            SELECT
                x.*
            FROM
            (
                SELECT
                    source =
                        'compilation_stats',
                    database_name =
                        DB_NAME(qsq.database_id),
                    qsq.query_id,
                    qsq.object_name,
                    qsq.query_text_id,
                    qsq.query_parameterization_type_desc,
                    initial_compile_start_time =
                        CASE
                            WHEN @timezone IS NULL
                            THEN
                                DATEADD
                                (
                                    MINUTE,
                                    @utc_minutes_original,
                                    qsq.initial_compile_start_time
                                )
                            WHEN @timezone IS NOT NULL
                            THEN qsq.initial_compile_start_time AT TIME ZONE @timezone
                        END,
                    initial_compile_start_time_utc =
                        qsq.initial_compile_start_time,
                    last_compile_start_time =
                        CASE
                            WHEN @timezone IS NULL
                            THEN
                                DATEADD
                                (
                                    MINUTE,
                                    @utc_minutes_original,
                                    qsq.last_compile_start_time
                                )
                            WHEN @timezone IS NOT NULL
                            THEN qsq.last_compile_start_time AT TIME ZONE @timezone
                        END,
                    last_compile_start_time_utc =
                        qsq.last_compile_start_time,
                    last_execution_time =
                        CASE
                            WHEN @timezone IS NULL
                            THEN
                                DATEADD
                                (
                                    MINUTE,
                                    @utc_minutes_original,
                                    qsq.last_execution_time
                                )
                            WHEN @timezone IS NOT NULL
                            THEN qsq.last_execution_time AT TIME ZONE @timezone
                        END,
                    last_execution_time_utc =
                        qsq.last_execution_time,
                    qsq.count_compiles,
                    qsq.avg_compile_duration_ms,
                    qsq.total_compile_duration_ms,
                    qsq.last_compile_duration_ms,
                    qsq.avg_bind_duration_ms,
                    qsq.total_bind_duration_ms,
                    qsq.last_bind_duration_ms,
                    qsq.avg_bind_cpu_time_ms,
                    qsq.total_bind_cpu_time_ms,
                    qsq.last_bind_cpu_time_ms,
                    qsq.avg_optimize_duration_ms,
                    qsq.total_optimize_duration_ms,
                    qsq.last_optimize_duration_ms,
                    qsq.avg_optimize_cpu_time_ms,
                    qsq.total_optimize_cpu_time_ms,
                    qsq.last_optimize_cpu_time_ms,
                    qsq.avg_compile_memory_mb,
                    qsq.total_compile_memory_mb,
                    qsq.last_compile_memory_mb,
                    qsq.max_compile_memory_mb,
                    qsq.query_hash,
                    qsq.batch_sql_handle,
                    qsqt.statement_sql_handle,
                    qsq.last_compile_batch_sql_handle,
                    qsq.last_compile_batch_offset_start,
                    qsq.last_compile_batch_offset_end,
                    ROW_NUMBER() OVER
                    (
                        PARTITION BY
                            qsq.query_id,
                            qsq.query_text_id
                        ORDER BY
                            qsq.query_id
                    ) AS n
                FROM #query_store_query AS qsq
                CROSS APPLY
                (
                    SELECT TOP (1)
                        qsqt.*
                    FROM #query_store_query_text AS qsqt
                    WHERE qsqt.query_text_id = qsq.query_text_id
                    AND   qsqt.database_id = qsq.database_id
                ) AS qsqt
            ) AS x
            WHERE x.n = 1
            ORDER BY
                x.query_id
            OPTION(RECOMPILE);

        END; /*End compilation stats query*/
        ELSE
        BEGIN
            SELECT
                result =
                    '#query_store_query is empty';
        END;
    END;

    IF @expert_mode = 1
    BEGIN
        IF @rc > 0
        BEGIN
            SELECT
                @current_table = 'selecting resource stats';

            SELECT
                source =
                    'resource_stats',
                database_name =
                    DB_NAME(qsq.database_id),
                qsq.query_id,
                qsq.object_name,
                qsqt.total_grant_mb,
                qsqt.last_grant_mb,
                qsqt.min_grant_mb,
                qsqt.max_grant_mb,
                qsqt.total_used_grant_mb,
                qsqt.last_used_grant_mb,
                qsqt.min_used_grant_mb,
                qsqt.max_used_grant_mb,
                qsqt.total_ideal_grant_mb,
                qsqt.last_ideal_grant_mb,
                qsqt.min_ideal_grant_mb,
                qsqt.max_ideal_grant_mb,
                qsqt.total_reserved_threads,
                qsqt.last_reserved_threads,
                qsqt.min_reserved_threads,
                qsqt.max_reserved_threads,
                qsqt.total_used_threads,
                qsqt.last_used_threads,
                qsqt.min_used_threads,
                qsqt.max_used_threads
            FROM #query_store_query AS qsq
            JOIN #query_store_query_text AS qsqt
            ON  qsq.query_text_id = qsqt.query_text_id
            AND qsq.database_id = qsqt.database_id
            WHERE
            (
                qsqt.total_grant_mb IS NOT NULL
            OR qsqt.total_reserved_threads IS NOT NULL
            )
            ORDER BY
                qsq.query_id
            OPTION(RECOMPILE);

        END; /*End resource stats query*/
        ELSE
        BEGIN
            SELECT
                result =
                    '#dm_exec_query_stats is empty';
        END;
    END;

    IF @new = 1
    BEGIN
        IF @expert_mode = 1
        BEGIN
            IF EXISTS
            (
                SELECT
                    1/0
                    FROM #query_store_wait_stats AS qsws
            )
            BEGIN
                SELECT
                    @current_table = 'selecting wait stats by query';

                SELECT DISTINCT
                    source =
                        'query_store_wait_stats_by_query',
                    database_name =
                        DB_NAME(qsws.database_id),
                    qsws.plan_id,
                    x.object_name,
                    qsws.wait_category_desc,
                    qsws.total_query_wait_time_ms,
                    total_query_duration_ms =
                        x.total_duration_ms,
                    qsws.avg_query_wait_time_ms,
                    avg_query_duration_ms =
                        x.avg_duration_ms,
                    qsws.last_query_wait_time_ms,
                    last_query_duration_ms =
                        x.last_duration_ms,
                    qsws.min_query_wait_time_ms,
                    min_query_duration_ms =
                        x.min_duration_ms,
                    qsws.max_query_wait_time_ms,
                    max_query_duration_ms =
                        x.max_duration_ms
                FROM #query_store_wait_stats AS qsws
                CROSS APPLY
                (
                    SELECT
                        qsrs.avg_duration_ms,
                        qsrs.last_duration_ms,
                        qsrs.min_duration_ms,
                        qsrs.max_duration_ms,
                        qsrs.total_duration_ms,
                        qsq.object_name
                    FROM #query_store_runtime_stats AS qsrs
                    JOIN #query_store_plan AS qsp
                    ON  qsrs.plan_id = qsp.plan_id
                    AND qsrs.database_id = qsp.database_id
                    JOIN #query_store_query AS qsq
                    ON  qsp.query_id = qsq.query_id
                    AND qsp.database_id = qsq.database_id
                    WHERE qsws.plan_id = qsrs.plan_id
                    AND   qsws.database_id = qsrs.database_id
                ) AS x
                ORDER BY
                    qsws.plan_id,
                    qsws.total_query_wait_time_ms DESC
                OPTION(RECOMPILE);

                SELECT
                    @current_table = 'selecting wait stats in total';

                SELECT
                    source =
                        'query_store_wait_stats_total',
                    database_name =
                        DB_NAME(qsws.database_id),
                    qsws.wait_category_desc,
                    total_query_wait_time_ms =
                        SUM(qsws.total_query_wait_time_ms),
                    total_query_duration_ms =
                        SUM(x.total_duration_ms),
                    avg_query_wait_time_ms =
                        SUM(qsws.avg_query_wait_time_ms),
                    avg_query_duration_ms =
                        SUM(x.avg_duration_ms),
                    last_query_wait_time_ms =
                        SUM(qsws.last_query_wait_time_ms),
                    last_query_duration_ms =
                        SUM(x.last_duration_ms),
                    min_query_wait_time_ms =
                        SUM(qsws.min_query_wait_time_ms),
                    min_query_duration_ms =
                        SUM(x.min_duration_ms),
                    max_query_wait_time_ms =
                        SUM(qsws.max_query_wait_time_ms),
                    max_query_duration_ms =
                        SUM(x.max_duration_ms)
                FROM #query_store_wait_stats AS qsws
                CROSS APPLY
                (
                    SELECT
                        qsrs.avg_duration_ms,
                        qsrs.last_duration_ms,
                        qsrs.min_duration_ms,
                        qsrs.max_duration_ms,
                        qsrs.total_duration_ms,
                        qsq.object_name
                    FROM #query_store_runtime_stats AS qsrs
                    JOIN #query_store_plan AS qsp
                    ON  qsrs.plan_id = qsp.plan_id
                    AND qsrs.database_id = qsp.database_id
                    JOIN #query_store_query AS qsq
                    ON  qsp.query_id = qsq.query_id
                    AND qsp.database_id = qsq.database_id
                    WHERE qsws.plan_id = qsrs.plan_id
                ) AS x
                GROUP BY
                    qsws.wait_category_desc,
                    qsws.database_id
                ORDER BY
                    SUM(qsws.total_query_wait_time_ms) DESC
                OPTION(RECOMPILE);

            END; /*End unformatted wait stats*/
            ELSE
            BEGIN
                SELECT
                    result =
                        '#query_store_wait_stats is empty' +
                        CASE
                            WHEN
                            (
                                    @product_version = 13
                                AND @azure = 0
                            )
                            THEN ' because it''s not available < 2017'
                            WHEN EXISTS
                                (
                                    SELECT
                                        1/0
                                    FROM #database_query_store_options AS dqso
                                    WHERE dqso.wait_stats_capture_mode_desc <> 'ON'
                                )
                            THEN ' because you have it disabled in your Query Store options'
                            ELSE ' for the queries in the results'
                        END;
            END;
        END;
    END; /*End wait stats queries*/

    IF
    (
        @sql_2022_views = 1
    AND @ags_present = 1
    )
    BEGIN
        IF @expert_mode = 1
        BEGIN
            IF EXISTS
            (
                SELECT
                    1/0
                FROM #query_store_replicas AS qsr
                JOIN #query_store_plan_forcing_locations AS qspfl
                    ON  qsr.replica_group_id = qspfl.replica_group_id
                    AND qsr.database_id = qspfl.database_id
            )
            BEGIN
                SELECT
                    @current_table = 'selecting #query_store_replicas and #query_store_plan_forcing_locations';

                SELECT
                    database_name =
                        DB_NAME(qsr.database_id),
                    qsr.replica_group_id,
                    qsr.role_type,
                    qsr.replica_name,
                    qspfl.plan_forcing_location_id,
                    qspfl.query_id,
                    qspfl.plan_id,
                    qspfl.replica_group_id
                FROM #query_store_replicas AS qsr
                JOIN #query_store_plan_forcing_locations AS qspfl
                ON qsr.replica_group_id = qspfl.replica_group_id
                ORDER BY
                    qsr.replica_group_id;
            END;
            ELSE
                BEGIN
                    SELECT
                        result = 'Availability Group information is empty';
            END;
        END;
    END;

    IF @expert_mode = 1
    BEGIN
        SELECT
            @current_table = 'selecting query store options',
            @sql = N'';

        SELECT
            @sql +=
        CONVERT
        (
            nvarchar(MAX),
            N'
        SELECT
            source =
                ''query_store_options'',
            database_name =
                DB_NAME(dqso.database_id),
            dqso.desired_state_desc,
            dqso.actual_state_desc,
            dqso.readonly_reason,
            dqso.current_storage_size_mb,
            dqso.flush_interval_seconds,
            dqso.interval_length_minutes,
            dqso.max_storage_size_mb,
            dqso.stale_query_threshold_days,
            dqso.max_plans_per_query,
            dqso.query_capture_mode_desc,'
            +
            CASE
                WHEN
                (
                    @azure = 1
                OR @product_version > 13
                )
                THEN N'
            dqso.wait_stats_capture_mode_desc,'
                ELSE N''
            END
            +
            CASE
                WHEN
                (
                    @azure = 1
                OR @product_version > 14
                )
                THEN N'
            dqso.capture_policy_execution_count,
            dqso.capture_policy_total_compile_cpu_time_ms,
            dqso.capture_policy_total_execution_cpu_time_ms,
            dqso.capture_policy_stale_threshold_hours,'
                ELSE N''
            END
        );

        SELECT
            @sql +=
        CONVERT
        (
            nvarchar(MAX),
            N'
        dqso.size_based_cleanup_mode_desc
        FROM #database_query_store_options AS dqso
        OPTION(RECOMPILE);'
        );

        IF @debug = 1
        BEGIN
            PRINT LEN(@sql);
            PRINT @sql;
        END;

        EXEC sys.sp_executesql
            @sql;
    END;
END; /*End expert mode format output = 0*/

/*
Return special things, formatted
*/
IF
(
    (
        @expert_mode = 1
      OR
      (
           @only_queries_with_hints = 1
        OR @only_queries_with_feedback = 1
        OR @only_queries_with_variants = 1
      )
    )
AND @format_output = 1
)
BEGIN
    IF @sql_2022_views = 1
    BEGIN
        IF @expert_mode = 1
        BEGIN
            IF EXISTS
               (
                   SELECT
                       1/0
                   FROM #query_store_plan_feedback AS qspf
               )
            BEGIN
                SELECT
                    @current_table = 'selecting plan feedback';

                SELECT
                    database_name =
                        DB_NAME(qspf.database_id),
                    qspf.plan_feedback_id,
                    qspf.plan_id,
                    qspf.feature_desc,
                    qspf.feedback_data,
                    qspf.state_desc,
                    create_time =
                        CASE
                            WHEN @timezone IS NULL
                            THEN
                                DATEADD
                                (
                                    MINUTE,
                                    @utc_minutes_original,
                                    qspf.create_time
                                )
                            WHEN @timezone IS NOT NULL
                            THEN qspf.create_time AT TIME ZONE @timezone
                        END,
                    create_time_utc =
                        qspf.create_time,
                    last_updated_time =
                        CASE
                            WHEN @timezone IS NULL
                            THEN
                                DATEADD
                                (
                                    MINUTE,
                                    @utc_minutes_original,
                                    qspf.last_updated_time
                                )
                            WHEN @timezone IS NOT NULL
                            THEN qspf.last_updated_time AT TIME ZONE @timezone
                        END,
                    last_updated_time_utc =
                        qspf.last_updated_time
                FROM #query_store_plan_feedback AS qspf
                ORDER BY
                    qspf.plan_id
                OPTION(RECOMPILE);
            END;
            ELSE
            BEGIN
                SELECT
                    result = '#query_store_plan_feedback is empty';
            END;
        END

        IF EXISTS
           (
               SELECT
                   1/0
               FROM #query_store_query_hints AS qsqh
           )
        BEGIN
            SELECT
                @current_table = 'selecting query hints';

            SELECT
                database_name =
                    DB_NAME(qsqh.database_id),
                qsqh.query_hint_id,
                qsqh.query_id,
                qsqh.query_hint_text,
                qsqh.last_query_hint_failure_reason_desc,
                qsqh.query_hint_failure_count,
                qsqh.source_desc
            FROM #query_store_query_hints AS qsqh
            ORDER BY
                qsqh.query_id
            OPTION(RECOMPILE);
        END;
        ELSE
        BEGIN
            SELECT
                result = '#query_store_query_hints is empty';
        END;

        IF @expert_mode = 1
        BEGIN
            IF EXISTS
               (
                   SELECT
                       1/0
                   FROM #query_store_query_variant AS qsqv
               )
            BEGIN
                SELECT
                    @current_table = 'selecting query variants';

                SELECT
                    database_name =
                        DB_NAME(qsqv.database_id),
                    qsqv.query_variant_query_id,
                    qsqv.parent_query_id,
                    qsqv.dispatcher_plan_id
                FROM #query_store_query_variant AS qsqv
                ORDER BY
                    qsqv.parent_query_id
                OPTION(RECOMPILE);
            END;
            ELSE
            BEGIN
                SELECT
                    result = '#query_store_query_variant is empty';
            END;
        END;
    END;

    IF @expert_mode = 1
    BEGIN
        IF EXISTS
           (
              SELECT
                  1/0
              FROM #query_store_query AS qsq
           )
        BEGIN
            SELECT
                @current_table = 'selecting compilation stats';

            SELECT
                x.*
            FROM
            (
                SELECT
                    source =
                        'compilation_stats',
                    database_name =
                        DB_NAME(qsq.database_id),
                    qsq.query_id,
                    qsq.object_name,
                    qsq.query_text_id,
                    qsq.query_parameterization_type_desc,
                    initial_compile_start_time =
                        CASE
                            WHEN @timezone IS NULL
                            THEN
                                DATEADD
                                (
                                    MINUTE,
                                    @utc_minutes_original,
                                    qsq.initial_compile_start_time
                                )
                            WHEN @timezone IS NOT NULL
                            THEN qsq.initial_compile_start_time AT TIME ZONE @timezone
                        END,
                    initial_compile_start_time_utc =
                        qsq.initial_compile_start_time,
                    last_compile_start_time =
                        CASE
                            WHEN @timezone IS NULL
                            THEN
                                DATEADD
                                (
                                    MINUTE,
                                    @utc_minutes_original,
                                    qsq.last_compile_start_time
                                )
                            WHEN @timezone IS NOT NULL
                            THEN qsq.last_compile_start_time AT TIME ZONE @timezone
                        END,
                    last_compile_start_time_utc =
                        qsq.last_compile_start_time,
                    last_execution_time =
                        CASE
                            WHEN @timezone IS NULL
                            THEN
                                DATEADD
                                (
                                    MINUTE,
                                    @utc_minutes_original,
                                    qsq.last_execution_time
                                )
                            WHEN @timezone IS NOT NULL
                            THEN qsq.last_execution_time AT TIME ZONE @timezone
                        END,
                    last_execution_time_utc =
                        qsq.last_execution_time,
                    count_compiles =
                        FORMAT(qsq.count_compiles, 'N0'),
                    avg_compile_duration_ms =
                        FORMAT(qsq.avg_compile_duration_ms, 'N0'),
                    total_compile_duration_ms =
                        FORMAT(qsq.total_compile_duration_ms, 'N0'),
                    last_compile_duration_ms =
                        FORMAT(qsq.last_compile_duration_ms, 'N0'),
                    avg_bind_duration_ms =
                        FORMAT(qsq.avg_bind_duration_ms, 'N0'),
                    total_bind_duration_ms =
                        FORMAT(qsq.total_bind_duration_ms, 'N0'),
                    last_bind_duration_ms =
                        FORMAT(qsq.last_bind_duration_ms, 'N0'),
                    avg_bind_cpu_time_ms =
                        FORMAT(qsq.avg_bind_cpu_time_ms, 'N0'),
                    total_bind_cpu_time_ms =
                        FORMAT(qsq.total_bind_cpu_time_ms, 'N0'),
                    last_bind_cpu_time_ms =
                        FORMAT(qsq.last_bind_cpu_time_ms, 'N0'),
                    avg_optimize_duration_ms =
                        FORMAT(qsq.avg_optimize_duration_ms, 'N0'),
                    total_optimize_duration_ms =
                        FORMAT(qsq.total_optimize_duration_ms, 'N0'),
                    last_optimize_duration_ms =
                        FORMAT(qsq.last_optimize_duration_ms, 'N0'),
                    avg_optimize_cpu_time_ms =
                        FORMAT(qsq.avg_optimize_cpu_time_ms, 'N0'),
                    total_optimize_cpu_time_ms =
                        FORMAT(qsq.total_optimize_cpu_time_ms, 'N0'),
                    last_optimize_cpu_time_ms =
                        FORMAT(qsq.last_optimize_cpu_time_ms, 'N0'),
                    avg_compile_memory_mb =
                        FORMAT(qsq.avg_compile_memory_mb, 'N0'),
                    total_compile_memory_mb =
                        FORMAT(qsq.total_compile_memory_mb, 'N0'),
                    last_compile_memory_mb =
                        FORMAT(qsq.last_compile_memory_mb, 'N0'),
                    max_compile_memory_mb =
                        FORMAT(qsq.max_compile_memory_mb, 'N0'),
                    qsq.query_hash,
                    qsq.batch_sql_handle,
                    qsqt.statement_sql_handle,
                    qsq.last_compile_batch_sql_handle,
                    qsq.last_compile_batch_offset_start,
                    qsq.last_compile_batch_offset_end,
                    ROW_NUMBER() OVER
                    (
                        PARTITION BY
                            qsq.query_id,
                            qsq.query_text_id
                        ORDER BY
                            qsq.query_id
                    ) AS n
                FROM #query_store_query AS qsq
                CROSS APPLY
                (
                    SELECT TOP (1)
                        qsqt.*
                    FROM #query_store_query_text AS qsqt
                    WHERE qsqt.query_text_id = qsq.query_text_id
                    AND   qsqt.database_id = qsq.database_id
                ) AS qsqt
            ) AS x
            WHERE x.n = 1
            ORDER BY
                x.query_id
            OPTION(RECOMPILE);

        END; /*End query store query, format output = 1*/
        ELSE
        BEGIN
            SELECT
                result =
                    '#query_store_query is empty';
        END;
    END;

    IF @expert_mode = 1
    BEGIN
        IF @rc > 0
        BEGIN
            SELECT
                @current_table = 'selecting resource stats';

            SELECT
                source =
                    'resource_stats',
                database_name =
                    DB_NAME(qsq.database_id),
                qsq.query_id,
                qsq.object_name,
                total_grant_mb =
                    FORMAT(qsqt.total_grant_mb, 'N0'),
                last_grant_mb =
                    FORMAT(qsqt.last_grant_mb, 'N0'),
                min_grant_mb =
                    FORMAT(qsqt.min_grant_mb, 'N0'),
                max_grant_mb =
                    FORMAT(qsqt.max_grant_mb, 'N0'),
                total_used_grant_mb =
                    FORMAT(qsqt.total_used_grant_mb, 'N0'),
                last_used_grant_mb =
                    FORMAT(qsqt.last_used_grant_mb, 'N0'),
                min_used_grant_mb =
                    FORMAT(qsqt.min_used_grant_mb, 'N0'),
                max_used_grant_mb =
                    FORMAT(qsqt.max_used_grant_mb, 'N0'),
                total_ideal_grant_mb =
                    FORMAT(qsqt.total_ideal_grant_mb, 'N0'),
                last_ideal_grant_mb =
                    FORMAT(qsqt.last_ideal_grant_mb, 'N0'),
                min_ideal_grant_mb =
                    FORMAT(qsqt.min_ideal_grant_mb, 'N0'),
                max_ideal_grant_mb =
                    FORMAT(qsqt.max_ideal_grant_mb, 'N0'),
                qsqt.total_reserved_threads,
                qsqt.last_reserved_threads,
                qsqt.min_reserved_threads,
                qsqt.max_reserved_threads,
                qsqt.total_used_threads,
                qsqt.last_used_threads,
                qsqt.min_used_threads,
                qsqt.max_used_threads
            FROM #query_store_query AS qsq
            JOIN #query_store_query_text AS qsqt
              ON  qsq.query_text_id = qsqt.query_text_id
              AND qsq.database_id = qsqt.database_id
            WHERE
            (
                 qsqt.total_grant_mb IS NOT NULL
              OR qsqt.total_reserved_threads IS NOT NULL
            )
            ORDER BY
                qsq.query_id
            OPTION(RECOMPILE);

        END; /*End resource stats, format output = 1*/
        ELSE
        BEGIN
            SELECT
                result =
                    '#dm_exec_query_stats is empty';
        END;
    END;

    IF @new = 1
    BEGIN
        IF EXISTS
           (
               SELECT
                   1/0
                FROM #query_store_wait_stats AS qsws
           )
        AND @expert_mode = 1
        BEGIN
            SELECT
                @current_table = 'selecting wait stats by query';

            SELECT
                source =
                    'query_store_wait_stats_by_query',
                database_name =
                    DB_NAME(qsws.database_id),
                qsws.plan_id,
                x.object_name,
                qsws.wait_category_desc,
                total_query_wait_time_ms =
                    FORMAT(qsws.total_query_wait_time_ms, 'N0'),
                total_query_duration_ms =
                    FORMAT(x.total_duration_ms, 'N0'),
                avg_query_wait_time_ms =
                    FORMAT(qsws.avg_query_wait_time_ms, 'N0'),
                avg_query_duration_ms =
                    FORMAT(x.avg_duration_ms, 'N0'),
                last_query_wait_time_ms =
                    FORMAT(qsws.last_query_wait_time_ms, 'N0'),
                last_query_duration_ms =
                    FORMAT(x.last_duration_ms, 'N0'),
                min_query_wait_time_ms =
                    FORMAT(qsws.min_query_wait_time_ms, 'N0'),
                min_query_duration_ms =
                    FORMAT(x.min_duration_ms, 'N0'),
                max_query_wait_time_ms =
                    FORMAT(qsws.max_query_wait_time_ms, 'N0'),
                max_query_duration_ms =
                    FORMAT(x.max_duration_ms, 'N0')
            FROM #query_store_wait_stats AS qsws
            CROSS APPLY
            (
                SELECT DISTINCT
                    qsrs.avg_duration_ms,
                    qsrs.last_duration_ms,
                    qsrs.min_duration_ms,
                    qsrs.max_duration_ms,
                    qsrs.total_duration_ms,
                    qsq.object_name
                FROM #query_store_runtime_stats AS qsrs
                JOIN #query_store_plan AS qsp
                  ON  qsrs.plan_id = qsp.plan_id
                  AND qsrs.database_id = qsp.database_id
                JOIN #query_store_query AS qsq
                  ON  qsp.query_id = qsq.query_id
                  AND qsp.database_id = qsq.database_id
                WHERE qsws.plan_id = qsrs.plan_id
                AND   qsws.database_id = qsrs.database_id
            ) AS x
            ORDER BY
                qsws.plan_id,
                qsws.total_query_wait_time_ms DESC
            OPTION(RECOMPILE);

            SELECT
                @current_table = 'selecting wait stats in total';

            SELECT
                source =
                    'query_store_wait_stats_total',
                database_name =
                    DB_NAME(qsws.database_id),
                qsws.wait_category_desc,
                total_query_wait_time_ms =
                    FORMAT(SUM(qsws.total_query_wait_time_ms), 'N0'),
                total_query_duration_ms =
                    FORMAT(SUM(x.total_duration_ms), 'N0'),
                avg_query_wait_time_ms =
                    FORMAT(SUM(qsws.avg_query_wait_time_ms), 'N0'),
                avg_query_duration_ms =
                    FORMAT(SUM(x.avg_duration_ms), 'N0'),
                last_query_wait_time_ms =
                    FORMAT(SUM(qsws.last_query_wait_time_ms), 'N0'),
                last_query_duration_ms =
                    FORMAT(SUM(x.last_duration_ms), 'N0'),
                min_query_wait_time_ms =
                    FORMAT(SUM(qsws.min_query_wait_time_ms), 'N0'),
                min_query_duration_ms =
                    FORMAT(SUM(x.min_duration_ms), 'N0'),
                max_query_wait_time_ms =
                    FORMAT(SUM(qsws.max_query_wait_time_ms), 'N0'),
                max_query_duration_ms =
                    FORMAT(SUM(x.max_duration_ms), 'N0')
            FROM #query_store_wait_stats AS qsws
            CROSS APPLY
            (
                SELECT
                    qsrs.avg_duration_ms,
                    qsrs.last_duration_ms,
                    qsrs.min_duration_ms,
                    qsrs.max_duration_ms,
                    qsrs.total_duration_ms,
                    qsq.object_name
                FROM #query_store_runtime_stats AS qsrs
                JOIN #query_store_plan AS qsp
                  ON  qsrs.plan_id = qsp.plan_id
                  AND qsrs.database_id = qsp.database_id
                JOIN #query_store_query AS qsq
                  ON  qsp.query_id = qsq.query_id
                  AND qsp.database_id = qsq.database_id
                WHERE qsws.plan_id = qsrs.plan_id
                AND   qsws.database_id = qsrs.database_id
            ) AS x
            GROUP BY
                qsws.wait_category_desc,
                qsws.database_id
            ORDER BY
                SUM(qsws.total_query_wait_time_ms) DESC
            OPTION(RECOMPILE);

        END;

    END; /*End wait stats, format output = 1*/
    ELSE
    BEGIN
        SELECT
            result =
                '#query_store_wait_stats is empty' +
                CASE
                    WHEN (
                             @product_version = 13
                         AND @azure = 0
                         )
                    THEN ' because it''s not available < 2017'
                    WHEN EXISTS
                         (
                             SELECT
                                 1/0
                             FROM #database_query_store_options AS dqso
                             WHERE dqso.wait_stats_capture_mode_desc <> 'ON'
                         )
                    THEN ' because you have it disabled in your Query Store options'
                    ELSE ' for the queries in the results'
                END;
    END;

    IF
    (
        @sql_2022_views = 1
    AND @ags_present = 1
    )
    BEGIN
        IF @expert_mode = 1
        BEGIN
            IF EXISTS
            (
                SELECT
                    1/0
                FROM #query_store_replicas AS qsr
                JOIN #query_store_plan_forcing_locations AS qspfl
                    ON  qsr.replica_group_id = qspfl.replica_group_id
                    AND qsr.replica_group_id = qspfl.database_id
            )
            BEGIN
                SELECT
                    @current_table = '#query_store_replicas and #query_store_plan_forcing_locations';

                SELECT
                    database_name =
                        DB_NAME(qsr.database_id),
                    qsr.replica_group_id,
                    qsr.role_type,
                    qsr.replica_name,
                    qspfl.plan_forcing_location_id,
                    qspfl.query_id,
                    qspfl.plan_id,
                    qspfl.replica_group_id
                FROM #query_store_replicas AS qsr
                JOIN #query_store_plan_forcing_locations AS qspfl
                ON  qsr.replica_group_id = qspfl.replica_group_id
                AND qsr.database_id = qspfl.database_id
                ORDER BY
                    qsr.replica_group_id
                OPTION(RECOMPILE);
            END;
            ELSE
            BEGIN
                SELECT
                    result = 'Availability Group information is empty';
            END;
        END;
    END;

    IF @expert_mode = 1
    BEGIN
        SELECT
            @current_table = 'selecting query store options',
            @sql = N'';

        SELECT
            @sql +=
        CONVERT
        (
            nvarchar(MAX),
            N'
        SELECT
            source =
                ''query_store_options'',
            database_name =
                DB_NAME(dqso.database_id),
            dqso.desired_state_desc,
            dqso.actual_state_desc,
            dqso.readonly_reason,
            current_storage_size_mb =
                FORMAT(dqso.current_storage_size_mb, ''N0''),
            flush_interval_seconds =
                FORMAT(dqso.flush_interval_seconds, ''N0''),
            interval_length_minutes =
                FORMAT(dqso.interval_length_minutes, ''N0''),
            max_storage_size_mb =
                FORMAT(dqso.max_storage_size_mb, ''N0''),
            dqso.stale_query_threshold_days,
            max_plans_per_query =
                FORMAT(dqso.max_plans_per_query, ''N0''),
            dqso.query_capture_mode_desc,'
            +
            CASE
                WHEN
                (
                    @azure = 1
                    OR @product_version > 13
                )
                THEN N'
            dqso.wait_stats_capture_mode_desc,'
                ELSE N''
            END
            +
            CASE
                WHEN
                (
                     @azure = 1
                  OR @product_version > 14
                )
                THEN N'
            capture_policy_execution_count =
                FORMAT(dqso.capture_policy_execution_count, ''N0''),
            capture_policy_total_compile_cpu_time_ms =
                FORMAT(dqso.capture_policy_total_compile_cpu_time_ms, ''N0''),
            capture_policy_total_execution_cpu_time_ms =
               FORMAT(dqso.capture_policy_total_execution_cpu_time_ms, ''N0''),
            capture_policy_stale_threshold_hours =
                FORMAT(dqso.capture_policy_stale_threshold_hours, ''N0''),'
                ELSE N''
            END
            );

        SELECT
            @sql += N'
        dqso.size_based_cleanup_mode_desc
        FROM #database_query_store_options AS dqso
        OPTION(RECOMPILE);';


        IF @debug = 1
        BEGIN
            PRINT LEN(@sql);
            PRINT @sql;
        END;

        EXEC sys.sp_executesql
            @sql;
    END;

END; /*End expert mode = 1, format output = 1*/

SELECT
    x.all_done,
    x.period,
    x.support,
    x.help,
    x.problems,
    x.performance,
    x.version_and_date,
    x.thanks
FROM
(
    SELECT
        sort =
            1,
        period =
            N'query store data for period ' +
            CONVERT
            (
                nvarchar(10),
                ISNULL
                (
                    @start_date_original,
                    DATEADD
                    (
                        DAY,
                        -7,
                        DATEDIFF
                        (
                            DAY,
                            '19000101',
                            SYSDATETIME()
                        )
                    )
                ),
                23
            ) +
            N' through ' +
            CONVERT
            (
                nvarchar(10),
                ISNULL
                (
                    @end_date_original,
                    SYSDATETIME()
                ),
                23
            ),
        all_done =
            'brought to you by darling data!',
        support =
            'for support, head over to github',
        help =
            'for local help, use @help = 1',
        problems =
            'to debug issues, use @debug = 1;',
        performance =
            'if this runs slowly, use to get query plans',
        version_and_date =
            N'version: ' + CONVERT(nvarchar(10), @version),
        thanks =
            'thanks for using sp_QuickieStore!'

    UNION ALL

    SELECT
        sort =
            2,
        period =
            N'query store data for period ' +
            CONVERT
            (
                nvarchar(10),
                ISNULL
                (
                    @start_date_original,
                    DATEADD
                    (
                        DAY,
                        -7,
                        DATEDIFF
                        (
                            DAY,
                            '19000101',
                            SYSDATETIME()
                        )
                    )
                ),
                23
            ) +
            N' through ' +
            CONVERT
            (
                nvarchar(10),
                ISNULL
                (
                    @end_date_original,
                    SYSDATETIME()
                ),
                23
            ),
        all_done =
            'https://www.erikdarling.com/',
        support =
            'https://github.com/erikdarlingdata/DarlingData',
        help =
            'EXEC sp_QuickieStore @help = 1;',
        problems =
            'EXEC sp_QuickieStore @debug = 1;',
        performance =
            'EXEC sp_QuickieStore @troubleshoot_performance = 1;',
        version_and_date =
            N'version date: ' + CONVERT(nvarchar(10), @version_date, 23),
        thanks =
            'i hope you find it useful, or whatever'
) AS x
ORDER BY
    x.sort;

END TRY

/*Error handling!*/
BEGIN CATCH
    /*
    Where the error happened and the message
    */
    IF @current_table IS NOT NULL
    BEGIN
        RAISERROR('error while %s with @expert mode = %i and format_output = %i', 11, 1, @current_table, @em, @fo) WITH NOWAIT;
    END;

        /*
        Query that caused the error
        */
    IF @sql IS NOT NULL
    BEGIN
        RAISERROR('offending query:', 10, 1) WITH NOWAIT;
        RAISERROR('%s', 10, 1, @sql) WITH NOWAIT;
    END;

    /*
    This reliably throws the actual error from dynamic SQL
    */
    THROW;
END CATCH;

/*
Debug elements!
*/
IF @debug = 1
BEGIN
    SELECT
        parameter_type =
            'procedure_parameters',
        database_name =
            @database_name,
        sort_order =
            @sort_order,
        [top] =
            @top,
        start_date =
            @start_date,
        end_date =
            @end_date,
        timezone =
            @timezone,
        execution_count =
            @execution_count,
        duration_ms =
            @duration_ms,
        execution_type_desc =
            @execution_type_desc,
        procedure_schema =
            @procedure_schema,
        procedure_name =
            @procedure_name,
        include_plan_ids =
            @include_plan_ids,
        include_query_ids =
            @include_query_ids,
        include_query_hashes =
            @include_query_hashes,
        include_plan_hashes =
            @include_plan_hashes,
        include_sql_handles =
            @include_sql_handles,
        ignore_plan_ids =
            @ignore_plan_ids,
        ignore_query_ids =
            @ignore_query_ids,
        ignore_query_hashes =
            @ignore_query_hashes,
        ignore_plan_hashes =
            @ignore_plan_hashes,
        ignore_sql_handles =
            @ignore_sql_handles,
        query_text_search =
            @query_text_search,
        escape_brackets =
            @escape_brackets,
        escape_character =
            @escape_character,
        only_query_with_hints =
            @only_queries_with_hints,
        only_query_with_feedback =
            @only_queries_with_feedback,
        only_query_with_hints =
            @only_queries_with_variants,
        only_queries_with_forced_plans =
            @only_queries_with_forced_plans,
        only_queries_with_forced_plan_failures =
            @only_queries_with_forced_plan_failures,
        wait_filter =
            @wait_filter,
        query_type =
            @query_type,
        expert_mode =
            @expert_mode,
        format_output =
            @format_output,
        get_all_databases =
            @get_all_databases,
        workdays =
            @workdays,
        work_start =
            @work_start,
        work_end =
            @work_end,
        help =
            @help,
        debug =
            @debug,
        troubleshoot_performance =
            @troubleshoot_performance,
        version =
            @version,
        version_date =
            @version_date;

    SELECT
        parameter_type =
            'declared_variables',
        azure =
            @azure,
        engine =
            @engine,
        product_version =
            @product_version,
        database_id =
            @database_id,
        database_name_quoted =
            @database_name_quoted,
        procedure_name_quoted =
            @procedure_name_quoted,
        collation =
            @collation,
        new =
            @new,
        sql =
            @sql,
         len_sql =
             LEN(@sql),
        isolation_level =
            @isolation_level,
        parameters =
            @parameters,
        plans_top =
            @plans_top,
        queries_top =
            @queries_top,
        nc10 =
            @nc10,
        where_clause =
            @where_clause,
        procedure_exists =
            @procedure_exists,
        query_store_exists =
            @query_store_exists,
        query_store_trouble =
            @query_store_trouble,
        query_store_waits_enabled =
            @query_store_waits_enabled,
        sql_2022_views =
            @sql_2022_views,
        ags_present =
            @ags_present,
        string_split_ints =
            @string_split_ints,
        string_split_strings =
            @string_split_strings,
        current_table =
            @current_table,
        troubleshoot_insert =
            @troubleshoot_insert,
        troubleshoot_update =
            @troubleshoot_update,
        troubleshoot_info =
            @troubleshoot_info,
        rc =
            @rc,
       em =
           @em,
       fo =
          @fo,
       start_date_original =
           @start_date_original,
       end_date_original =
           @end_date_original,
       timezone =
           @timezone,
       utc_minutes_difference =
           @utc_minutes_difference,
       utc_minutes_original =
           @utc_minutes_original,
        df =
            @df,
        work_start_utc =
            @work_start_utc,
        work_end_utc =
            @work_end_utc;

    IF EXISTS
       (
           SELECT
               1/0
           FROM #databases AS d
       )
    BEGIN
        SELECT
            table_name =
                '#databases',
            d.*
        FROM #databases AS d
        ORDER BY
            d.database_name
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#databases is empty';
    END;

    IF EXISTS
       (
           SELECT
               1/0
           FROM #distinct_plans AS dp
       )
    BEGIN
        SELECT
            table_name =
                '#distinct_plans',
            dp.*
        FROM #distinct_plans AS dp
        ORDER BY
            dp.plan_id
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#distinct_plans is empty';
    END;

    IF EXISTS
       (
           SELECT
               1/0
           FROM #procedure_plans AS pp
       )
    BEGIN
        SELECT
            table_name =
                '#procedure_plans',
            pp.*
        FROM #procedure_plans AS pp
        ORDER BY
            pp.plan_id
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#procedure_plans is empty';
    END;

    IF EXISTS
       (
           SELECT
               1/0
           FROM #query_types AS qt
       )
    BEGIN
        SELECT
            table_name =
                '#query_types',
            qt.*
        FROM #query_types AS qt
        ORDER BY
            qt.plan_id
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#query_types is empty';
    END;

    IF EXISTS
       (
           SELECT
               1/0
           FROM #include_plan_ids AS ipi
       )
    BEGIN
        SELECT
            table_name =
                '#include_plan_ids',
            ipi.*
        FROM #include_plan_ids AS ipi
        ORDER BY
            ipi.plan_id
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#include_plan_ids is empty';
    END;

    IF EXISTS
       (
           SELECT
               1/0
           FROM #include_query_ids AS iqi
       )
    BEGIN
        SELECT
            table_name =
                '#include_query_ids',
            iqi.*
        FROM #include_query_ids AS iqi
        ORDER BY
            iqi.query_id
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#include_query_ids is empty';
    END;

    IF EXISTS
       (
           SELECT
               1/0
           FROM #include_query_hashes AS iqh
       )
    BEGIN
        SELECT
            table_name =
                '#include_query_hashes',
            iqh.*
        FROM #include_query_hashes AS iqh
        ORDER BY
            iqh.query_hash
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#include_query_hashes is empty';
    END;

    IF EXISTS
       (
           SELECT
               1/0
           FROM #include_plan_hashes AS iph
       )
    BEGIN
        SELECT
            table_name =
                '#include_plan_hashes',
            iph.*
        FROM #include_plan_hashes AS iph
        ORDER BY
            iph.plan_hash
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#include_plan_hashes is empty';
    END;

    IF EXISTS
       (
           SELECT
               1/0
           FROM #include_sql_handles AS ish
       )
    BEGIN
        SELECT
            table_name =
                '#include_sql_handles',
            ish.*
        FROM #include_sql_handles AS ish
        ORDER BY
            ish.sql_handle
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#include_sql_handles is empty';
    END;

    IF EXISTS
       (
           SELECT
               1/0
           FROM #ignore_plan_ids AS ipi
       )
    BEGIN
        SELECT
            table_name =
                '#ignore_plan_ids',
            ipi.*
        FROM #ignore_plan_ids AS ipi
        ORDER BY
            ipi.plan_id
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#ignore_plan_ids is empty';
    END;

    IF EXISTS
       (
           SELECT
               1/0
           FROM #ignore_query_ids AS iqi
       )
    BEGIN
        SELECT
            table_name =
                '#ignore_query_ids',
            iqi.*
        FROM #ignore_query_ids AS iqi
        ORDER BY
            iqi.query_id
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#ignore_query_ids is empty';
    END;

    IF EXISTS
       (
           SELECT
               1/0
           FROM #ignore_query_hashes AS iqh
       )
    BEGIN
        SELECT
            table_name =
                '#ignore_query_hashes',
            iqh.*
        FROM #ignore_query_hashes AS iqh
        ORDER BY
            iqh.query_hash
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#ignore_query_hashes is empty';
    END;

    IF EXISTS
       (
           SELECT
               1/0
           FROM #ignore_plan_hashes AS iph
       )
    BEGIN
        SELECT
            table_name =
                '#ignore_plan_hashes',
            iph.*
        FROM #ignore_plan_hashes AS iph
        ORDER BY
            iph.plan_hash
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#ignore_plan_hashes is empty';
    END;

    IF EXISTS
       (
           SELECT
               1/0
           FROM #ignore_sql_handles AS ish
       )
    BEGIN
        SELECT
            table_name =
                '#ignore_sql_handles',
            ish.*
        FROM #ignore_sql_handles AS ish
        ORDER BY
            ish.sql_handle
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#ignore_sql_handles is empty';
    END;

    IF EXISTS
       (
          SELECT
              1/0
          FROM #query_text_search AS qst
       )
    BEGIN
        SELECT
            table_name =
                '#query_text_search',
            qst.*
        FROM #query_text_search AS qst
        ORDER BY
            qst.plan_id
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#query_text_search is empty';
    END;

    IF EXISTS
       (
          SELECT
              1/0
          FROM #wait_filter AS wf
       )
    BEGIN
        SELECT
            table_name =
                '#wait_filter',
            wf.*
        FROM #wait_filter AS wf
        ORDER BY
            wf.plan_id
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#wait_filter is empty';
    END;

    IF EXISTS
       (
          SELECT
              1/0
          FROM #maintenance_plans AS mp
       )
    BEGIN
        SELECT
            table_name =
                '#maintenance_plans',
            mp.*
        FROM #maintenance_plans AS mp
        ORDER BY
            mp.plan_id
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#maintenance_plans is empty';
    END;

    IF EXISTS
       (
          SELECT
              1/0
          FROM #database_query_store_options AS qst
       )
    BEGIN
        SELECT
            table_name =
                '#database_query_store_options',
            dqso.*
        FROM #database_query_store_options AS dqso
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#database_query_store_options is empty';
    END;

    IF EXISTS
       (
          SELECT
              1/0
          FROM #query_store_trouble AS qst
       )
    BEGIN
        SELECT
            table_name =
                '#query_store_trouble',
            qst.*
        FROM #query_store_trouble AS qst
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#database_query_store_options is empty';
    END;

    IF EXISTS
       (
          SELECT
              1/0
          FROM #query_store_plan AS qsp
       )
    BEGIN
        SELECT
            table_name =
                '#query_store_plan',
            qsp.*
        FROM #query_store_plan AS qsp
        ORDER BY
            qsp.plan_id, qsp.query_id
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#query_store_plan is empty';
    END;

    IF EXISTS
       (
          SELECT
              1/0
          FROM #query_store_query AS qsq
       )
    BEGIN
        SELECT
            table_name =
                '#query_store_query',
            qsq.*
        FROM #query_store_query AS qsq
        ORDER BY
            qsq.query_id,
            qsq.query_text_id
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#query_store_query is empty';
    END;

    IF EXISTS
       (
          SELECT
              1/0
          FROM #query_store_query_text AS qsqt
       )
    BEGIN
        SELECT
            table_name =
                '#query_store_query_text',
            qsqt.*
        FROM #query_store_query_text AS qsqt
        ORDER BY
            qsqt.query_text_id
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#query_store_query_text is empty';
    END;

    IF EXISTS
       (
          SELECT
              1/0
          FROM #dm_exec_query_stats AS deqs
       )
    BEGIN
        SELECT
            table_name =
                '#dm_exec_query_stats ',
            deqs.*
        FROM #dm_exec_query_stats AS deqs
        ORDER BY
            deqs.statement_sql_handle
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#dm_exec_query_stats is empty';
    END;

    IF EXISTS
       (
          SELECT
              1/0
          FROM #query_store_runtime_stats AS qsrs
       )
    BEGIN
        SELECT
            table_name =
                '#query_store_runtime_stats',
            qsrs.*
        FROM #query_store_runtime_stats AS qsrs
        ORDER BY
            qsrs.plan_id
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#query_store_runtime_stats is empty';
    END;

    IF
      (
          @new = 1
          AND EXISTS
              (
                 SELECT
                     1/0
                 FROM #query_store_wait_stats AS qsws
              )
      )
    BEGIN
        SELECT
            table_name =
                '#query_store_wait_stats',
            qsws.*
        FROM #query_store_wait_stats AS qsws
        ORDER BY
            qsws.plan_id
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#query_store_wait_stats is empty' +
                CASE
                    WHEN (
                                @product_version = 13
                            AND @azure = 0
                         )
                    THEN ' because it''s not available < 2017'
                    WHEN EXISTS
                         (
                             SELECT
                                 1/0
                             FROM #database_query_store_options AS dqso
                             WHERE dqso.wait_stats_capture_mode_desc <> 'ON'
                         )
                    THEN ' because you have it disabled in your Query Store options'
                    ELSE ' for the queries in the results'
                END;
    END;

    IF EXISTS
       (
          SELECT
              1/0
          FROM #query_context_settings AS qcs
       )
    BEGIN
        SELECT
            table_name =
                '#query_context_settings',
            qcs.*
        FROM #query_context_settings AS qcs
        ORDER BY
            qcs.context_settings_id
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#query_context_settings is empty';
    END;

    IF @sql_2022_views = 1
    BEGIN
        IF EXISTS
           (
              SELECT
                  1/0
              FROM #query_store_plan_feedback AS qspf
           )
        BEGIN
            SELECT
                table_name =
                    '#query_store_plan_feedback',
                qspf.*
            FROM #query_store_plan_feedback AS qspf
            ORDER BY
                qspf.plan_feedback_id
            OPTION(RECOMPILE);
        END;
        ELSE
        BEGIN
            SELECT
                result =
                    '#query_store_plan_feedback is empty';
        END;

        IF EXISTS
           (
              SELECT
                  1/0
              FROM #query_store_query_hints AS qsqh
           )
        BEGIN
            SELECT
                table_name =
                    '#query_store_query_hints',
                qsqh.*
            FROM #query_store_query_hints AS qsqh
            ORDER BY
                qsqh.query_hint_id
            OPTION(RECOMPILE);
        END;
        ELSE
        BEGIN
            SELECT
                result =
                    '#query_store_query_hints is empty';
        END;

        IF EXISTS
           (
              SELECT
                  1/0
              FROM #query_store_query_variant AS qsqv
           )
        BEGIN
            SELECT
                table_name =
                    '#query_store_query_variant',
                qsqv.*
            FROM #query_store_query_variant AS qsqv
            ORDER BY
                qsqv.query_variant_query_id
            OPTION(RECOMPILE);
        END;
        ELSE
        BEGIN
            SELECT
                result =
                    '#query_store_query_variant is empty';
        END;

        IF @ags_present = 1
        BEGIN
            IF EXISTS
               (
                  SELECT
                      1/0
                  FROM #query_store_replicas AS qsr
               )
            BEGIN
                SELECT
                    table_name =
                        '#query_store_replicas',
                    qsr.*
                FROM #query_store_replicas AS qsr
                ORDER BY
                    qsr.replica_group_id
                OPTION(RECOMPILE);
            END;
            ELSE
            BEGIN
                SELECT
                    result =
                        '#query_store_replicas is empty';
            END;

            IF EXISTS
               (
                  SELECT
                      1/0
                  FROM #query_store_plan_forcing_locations AS qspfl
               )
            BEGIN
                SELECT
                    table_name =
                        '#query_store_plan_forcing_locations',
                    qspfl.*
                FROM #query_store_plan_forcing_locations AS qspfl
                ORDER BY
                    qspfl.plan_forcing_location_id
                OPTION(RECOMPILE);
            END;
            ELSE
            BEGIN
                SELECT
                    result =
                        '#query_store_plan_forcing_locations is empty';
            END;
        END;

        IF EXISTS
           (
              SELECT
                  1/0
              FROM #only_queries_with_hints AS oqwh
           )
        BEGIN
            SELECT
                table_name =
                    '#only_queries_with_hints',
                oqwh.*
            FROM #only_queries_with_hints AS oqwh
            ORDER BY
                oqwh.plan_id
            OPTION(RECOMPILE);
        END;
        ELSE
        BEGIN
            SELECT
                result =
                    '#only_queries_with_hints is empty';
        END;

        IF EXISTS
           (
              SELECT
                  1/0
              FROM #only_queries_with_feedback AS oqwf
           )
        BEGIN
            SELECT
                table_name =
                    '#only_queries_with_feedback',
                oqwf.*
            FROM #only_queries_with_feedback AS oqwf
            ORDER BY
                oqwf.plan_id
            OPTION(RECOMPILE);
        END;
        ELSE
        BEGIN
            SELECT
                result =
                    '#only_queries_with_feedback is empty';
        END;

        IF EXISTS
           (
              SELECT
                  1/0
              FROM #only_queries_with_variants AS oqwv
           )
        BEGIN
            SELECT
                table_name =
                    '#only_queries_with_variants',
                oqwv.*
            FROM #only_queries_with_variants AS oqwv
            ORDER BY
                oqwv.plan_id
            OPTION(RECOMPILE);
        END;
        ELSE
        BEGIN
            SELECT
                result =
                    '#only_queries_with_variants is empty';
        END;
    END;

    IF EXISTS
       (
          SELECT
              1/0
          FROM #forced_plans_failures AS fpf
       )
    BEGIN
        SELECT
            table_name =
                '#forced_plans_failures',
            fpf.*
        FROM #forced_plans_failures AS fpf
        ORDER BY
            fpf.plan_id
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#forced_plans_failures is empty';
    END;

    IF EXISTS
       (
          SELECT
              1/0
          FROM #troubleshoot_performance AS tp
       )
    BEGIN
        SELECT
            table_name =
                '#troubleshoot_performance',
            tp.*
        FROM #troubleshoot_performance AS tp
        ORDER BY
            tp.id
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#troubleshoot_performance is empty';
    END;
    RETURN; /*Stop doing anything, I guess*/
END; /*End debug*/
RETURN; /*Yeah sure why not?*/
END;/*Final End*/
GO

