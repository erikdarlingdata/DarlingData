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


Copyright 2025 Darling Data, LLC
https://www.erikdarling.com/

For support, head over to GitHub:
https://code.erikdarling.com
*/

IF OBJECT_ID(N'dbo.sp_HealthParser', N'P') IS NULL
   BEGIN
       EXECUTE (N'CREATE PROCEDURE dbo.sp_HealthParser AS RETURN 138;');
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
    @log_to_table bit = 0, /*enable logging to permanent tables*/
    @log_database_name sysname = NULL, /*database to store logging tables*/
    @log_schema_name sysname = NULL, /*schema to store logging tables*/
    @log_table_name_prefix sysname = 'HealthParser', /*prefix for all logging tables*/
    @log_retention_days integer = 30, /*Number of days to keep logs, 0 = keep indefinitely*/
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
        @version = '2.6',
        @version_date = '20250601';

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
                    WHEN N'@log_to_table' THEN N'enable logging to permanent tables instead of returning results'
                    WHEN N'@log_database_name' THEN N'database to store logging tables'
                    WHEN N'@log_schema_name' THEN N'schema to store logging tables'
                    WHEN N'@log_table_name_prefix' THEN N'prefix for all logging tables'
                    WHEN N'@log_retention_days' THEN N'how many days of data to retain'
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
                    WHEN N'@log_to_table' THEN N'0 or 1'
                    WHEN N'@log_database_name' THEN N'any valid database name'
                    WHEN N'@log_schema_name' THEN N'any valid schema name'
                    WHEN N'@log_table_name_prefix' THEN N'any valid identifier'
                    WHEN N'@log_retention_days' THEN N'a positive integer'
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
                    WHEN N'@log_to_table' THEN N'0'
                    WHEN N'@log_database_name' THEN N'NULL (current database)'
                    WHEN N'@log_schema_name' THEN N'NULL (dbo)'
                    WHEN N'@log_table_name_prefix' THEN N'HealthParser'
                    WHEN N'@log_retention_days' THEN N'30'
                    WHEN N'@version' THEN N'none; OUTPUT'
                    WHEN N'@version_date' THEN N'none; OUTPUT'
                    WHEN N'@help' THEN N'0'
                    WHEN N'@debug' THEN N'0'
                END
        FROM sys.all_parameters AS ap
        JOIN sys.all_objects AS o
          ON ap.object_id = o.object_id
        JOIN sys.types AS t
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

Copyright 2025 Darling Data, LLC

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
', 0, 0) WITH NOWAIT;

        RETURN;
    END; /*End help section*/

    IF @debug = 1
    BEGIN
        RAISERROR('Declaring variables', 0, 0) WITH NOWAIT;
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
                        integer,
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
                        integer,
                        SERVERPROPERTY('EngineEdition')
                    ) = 8
                THEN 1
                ELSE 0
            END,
        @mi_msg nchar(1),
        @dbid integer =
            DB_ID(@database_name),
        @timestamp_utc_mode tinyint,
        @sql_template nvarchar(max) = N'',
        @time_filter nvarchar(max) = N'',
        @cross_apply nvarchar(max) = N'',
        @collection_cursor CURSOR,
        @area_name varchar(20),
        @object_name sysname,
        @temp_table sysname,
        @insert_list sysname,
        @collection_sql nvarchar(max),
        /*Log to table stuff*/
        @log_table_significant_waits sysname,
        @log_table_waits_by_count sysname,
        @log_table_waits_by_duration sysname,
        @log_table_io_issues sysname,
        @log_table_cpu_tasks sysname,
        @log_table_memory_conditions sysname,
        @log_table_memory_broker sysname,
        @log_table_memory_node_oom sysname,
        @log_table_system_health sysname,
        @log_table_scheduler_issues sysname,
        @log_table_severe_errors sysname,
        @cleanup_date datetime2(7),
        @check_sql nvarchar(max) = N'',
        @create_sql nvarchar(max) = N'',
        @insert_sql nvarchar(max) = N'',
        @log_database_schema nvarchar(1024),
        @max_event_time datetime2(7),
        @dsql nvarchar(max) = N'',
        @mdsql_template nvarchar(max) = N'',
        @mdsql_execute nvarchar(MAX) = N'';

    IF @azure = 1
    BEGIN
        RAISERROR('This won''t work in Azure because it''s horrible', 11, 1) WITH NOWAIT;
        RETURN;
    END;

    IF @debug = 1
    BEGIN
        RAISERROR('Fixing parameters and variables', 0, 0) WITH NOWAIT;
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
            CONVERT(nchar(1), @mi),
        @timestamp_utc_mode =
            CASE
                WHEN EXISTS
                (
                    SELECT
                        1/0
                    FROM sys.all_columns AS ac
                    WHERE ac.object_id = OBJECT_ID(N'sys.fn_xe_file_target_read_file')
                    AND   ac.name = N'timestamp_utc'
                )
                THEN 1 +
                    CASE
                        WHEN
                            PARSENAME
                            (
                                CONVERT
                                (
                                    sysname,
                                    SERVERPROPERTY('PRODUCTVERSION')
                                ),
                                4
                            ) > 16
                        THEN 1
                        ELSE 0
                    END +
                    CASE
                        WHEN @mi = 1
                        THEN 1
                        ELSE 0
                    END
                ELSE 0
            END,
        @sql_template += N'
    INSERT INTO
        {temp_table}
    WITH
        (TABLOCK)
    (
        {insert_list}
    )
    SELECT
        {object_name} =
            ISNULL
            (
                xml.{object_name},
                CONVERT(xml, N''<event>event</event>'')
            )
    FROM
    (
        SELECT
            {object_name} =
                TRY_CAST(fx.event_data AS xml)
        FROM sys.fn_xe_file_target_read_file(N''system_health*.xel'', NULL, NULL, NULL) AS fx
        WHERE fx.object_name = N''{object_name}'' {time_filter}
    ) AS xml
    {cross_apply}
    OPTION(RECOMPILE);
',
        @mdsql_template = N'
            IF OBJECT_ID(''{table_check}'', ''U'') IS NOT NULL
            BEGIN
                SELECT
                    @max_event_time =
                        ISNULL
                        (
                            MAX({date_column}),
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
                                    -1,
                                    SYSDATETIME()
                                )
                            )
                        )
                FROM {table_check};
            END;
            ';

    IF @timestamp_utc_mode = 0
    BEGIN
        /* Pre-2017 handling */
        SET @time_filter = N'';
        SET @cross_apply = N'CROSS APPLY xml.{object_name}.nodes(''/event'') AS e(x)
CROSS APPLY (SELECT x.value( ''(@timestamp)[1]'', ''datetimeoffset'' )) ca ([utc_timestamp])
WHERE ca.utc_timestamp >= @start_date
AND   ca.utc_timestamp < @end_date';
    END;
    ELSE
    BEGIN
        /* 2017+ handling */
        SET @cross_apply = N'CROSS APPLY xml.{object_name}.nodes(''/event'') AS e(x)';

        IF @timestamp_utc_mode = 1
            SET @time_filter = N'
    AND   CONVERT(datetimeoffset(7), fx.timestamp_utc) BETWEEN @start_date AND @end_date';
        ELSE
            SET @time_filter = '
    AND   fx.timestamp_utc BETWEEN @start_date AND @end_date';
    END;

    SET @sql_template =
        REPLACE
        (
            REPLACE
            (
                @sql_template,
                '{time_filter}',
                @time_filter
            ),
            '{cross_apply}',
            @cross_apply
        );

    /*If any parameters that expect non-NULL default values get passed in with NULLs, fix them*/
    SELECT
        @what_to_check = LOWER(ISNULL(@what_to_check, 'all')),
        @warnings_only = ISNULL(@warnings_only, 0),
        @wait_duration_ms = ISNULL(@wait_duration_ms, 0),
        @wait_round_interval_minutes = ISNULL(@wait_round_interval_minutes, 60),
        @skip_locks = ISNULL(@skip_locks, 0),
        @pending_task_threshold = ISNULL(@pending_task_threshold, 10);

    /*Validate what to check*/
    IF @what_to_check NOT IN
        (
            'all',
            'cpu',
            'disk',
            'locking',
            'memory',
            'system',
            'waits'
        )
    BEGIN
        SELECT
            @what_to_check =
                CASE
                    WHEN @what_to_check = 'wait'
                    THEN 'waits'
                    WHEN @what_to_check IN
                         (
                           'blocking', 'blocks',
                           'deadlock', 'deadlocks',
                           'lock', 'locks'
                         )
                    THEN 'locking'
                    ELSE 'all'
                END;
    END;

    /* Validate logging parameters */
    IF @log_to_table = 1
    BEGIN
        SELECT
            /* Default database name to current database if not specified */
            @log_database_name = ISNULL(@log_database_name, DB_NAME()),
            /* Default schema name to dbo if not specified */
            @log_schema_name = ISNULL(@log_schema_name, N'dbo'),
            @log_retention_days =
                CASE
                    WHEN @log_retention_days < 0
                    THEN ABS(@log_retention_days)
                    ELSE @log_retention_days
                END;

        /* Validate database exists */
        IF NOT EXISTS
        (
            SELECT
                1/0
            FROM sys.databases AS d
            WHERE d.name = @log_database_name
        )
        BEGIN
            RAISERROR('The specified logging database %s does not exist. Logging will be disabled.', 11, 1, @log_database_name) WITH NOWAIT;
            RETURN;
        END;

        SET
            @log_database_schema =
                QUOTENAME(@log_database_name) +
                N'.' +
                QUOTENAME(@log_schema_name) +
                N'.';

        /* Generate fully qualified table names */
        SELECT
            @log_table_significant_waits =
                @log_database_schema +
                QUOTENAME(@log_table_name_prefix + N'_SignificantWaits'),
            @log_table_waits_by_count =
                @log_database_schema +
                QUOTENAME(@log_table_name_prefix + N'_WaitsByCount'),
            @log_table_waits_by_duration =
                @log_database_schema +
                QUOTENAME(@log_table_name_prefix + N'_WaitsByDuration'),
            @log_table_io_issues =
                @log_database_schema +
                QUOTENAME(@log_table_name_prefix + N'_IOIssues'),
            @log_table_cpu_tasks =
                @log_database_schema +
                QUOTENAME(@log_table_name_prefix + N'_CPUTasks'),
            @log_table_memory_conditions =
                @log_database_schema +
                QUOTENAME(@log_table_name_prefix + N'_MemoryConditions'),
            @log_table_memory_broker =
                @log_database_schema +
                QUOTENAME(@log_table_name_prefix + N'_MemoryBroker'),
            @log_table_memory_node_oom =
                @log_database_schema +
                QUOTENAME(@log_table_name_prefix + N'_MemoryNodeOOM'),
            @log_table_system_health =
                @log_database_schema +
                QUOTENAME(@log_table_name_prefix + N'_SystemHealth'),
            @log_table_scheduler_issues =
                @log_database_schema +
                QUOTENAME(@log_table_name_prefix + N'_SchedulerIssues'),
            @log_table_severe_errors =
                @log_database_schema +
                QUOTENAME(@log_table_name_prefix + N'_SevereErrors');

        /* Check if schema exists and create it if needed */
        SET @check_sql = N'
            IF NOT EXISTS
            (
                SELECT
                    1/0
                FROM ' + QUOTENAME(@log_database_name) + N'.sys.schemas AS s
                WHERE s.name = @schema_name
            )
            BEGIN
                DECLARE
                    @create_schema_sql nvarchar(max) = N''CREATE SCHEMA '' + QUOTENAME(@schema_name);

                EXECUTE ' + QUOTENAME(@log_database_name) + N'.sys.sp_executesql @create_schema_sql;
                IF @debug = 1 BEGIN RAISERROR(''Created schema %s in database %s for logging.'', 0, 1, @schema_name, @db_name) WITH NOWAIT; END;
            END';

        EXECUTE sys.sp_executesql
            @check_sql,
          N'@schema_name sysname,
            @db_name sysname,
            @debug bit',
            @log_schema_name,
            @log_database_name,
            @debug;

        SET @create_sql = N'
            IF NOT EXISTS
            (
                SELECT
                    1/0
                FROM ' + QUOTENAME(@log_database_name) + N'.sys.tables AS t
                JOIN ' + QUOTENAME(@log_database_name) + N'.sys.schemas AS s
                  ON t.schema_id = s.schema_id
                WHERE t.name = @table_name + N''_SignificantWaits''
                AND   s.name = @schema_name
            )
            BEGIN
                CREATE TABLE ' + @log_table_significant_waits + N'
                (
                    id bigint IDENTITY,
                    collection_time datetime2(7) NOT NULL DEFAULT SYSDATETIME(),
                    event_time datetime2(7) NULL,
                    wait_type nvarchar(60) NULL,
                    duration_ms nvarchar(30) NULL,
                    signal_duration_ms nvarchar(30) NULL,
                    wait_resource nvarchar(256) NULL,
                    query_text xml NULL,
                    session_id integer NULL,
                    PRIMARY KEY CLUSTERED (collection_time, id)
                );
                IF @debug = 1 BEGIN RAISERROR(''Created table %s for significant waits logging.'', 0, 1, ''' + @log_table_significant_waits + N''') WITH NOWAIT; END;
            END';

        EXECUTE sys.sp_executesql
            @create_sql,
          N'@schema_name sysname,
            @table_name sysname,
            @debug bit',
            @log_schema_name,
            @log_table_name_prefix,
            @debug;

        /* Create WaitsByCount table if it doesn't exist */
        SET @create_sql = N'
            IF NOT EXISTS
            (
                SELECT
                    1/0
                FROM ' + QUOTENAME(@log_database_name) + N'.sys.tables AS t
                JOIN ' + QUOTENAME(@log_database_name) + N'.sys.schemas AS s
                  ON t.schema_id = s.schema_id
                WHERE t.name = @table_name + N''_WaitsByCount''
                AND   s.name = @schema_name
            )
            BEGIN
                CREATE TABLE ' + @log_table_waits_by_count + N'
                (
                    id bigint IDENTITY,
                    collection_time datetime2(7) NOT NULL DEFAULT SYSDATETIME(),
                    event_time_rounded datetime2(7) NULL,
                    wait_type nvarchar(60) NULL,
                    waits nvarchar(30) NULL,
                    average_wait_time_ms nvarchar(30) NULL,
                    max_wait_time_ms nvarchar(30) NULL,
                    PRIMARY KEY CLUSTERED (collection_time, id)
                );
                IF @debug = 1 BEGIN RAISERROR(''Created table %s for waits by count logging.'', 0, 1, ''' + @log_table_waits_by_count + N''') WITH NOWAIT; END;
            END';

        EXECUTE sys.sp_executesql
            @create_sql,
          N'@schema_name sysname,
            @table_name sysname,
            @debug bit',
            @log_schema_name,
            @log_table_name_prefix,
            @debug;

        /* Create WaitsByDuration table if it doesn't exist */
        SET @create_sql = N'
            IF NOT EXISTS
            (
                SELECT
                    1/0
                FROM ' + QUOTENAME(@log_database_name) + N'.sys.tables AS t
                JOIN ' + QUOTENAME(@log_database_name) + N'.sys.schemas AS s
                  ON t.schema_id = s.schema_id
                WHERE t.name = @table_name + N''_WaitsByDuration''
                AND   s.name = @schema_name
            )
            BEGIN
                CREATE TABLE ' + @log_table_waits_by_duration + N'
                (
                    id bigint IDENTITY,
                    collection_time datetime2(7) NOT NULL DEFAULT SYSDATETIME(),
                    event_time_rounded datetime2(7) NULL,
                    wait_type nvarchar(60) NULL,
                    average_wait_time_ms nvarchar(30) NULL,
                    max_wait_time_ms nvarchar(30) NULL,
                    PRIMARY KEY CLUSTERED (collection_time, id)
                );
                IF @debug = 1 BEGIN RAISERROR(''Created table %s for waits by duration logging.'', 0, 1, ''' + @log_table_waits_by_duration + N''') WITH NOWAIT; END;
            END';

        EXECUTE sys.sp_executesql
            @create_sql,
          N'@schema_name sysname,
            @table_name sysname,
            @debug bit',
            @log_schema_name,
            @log_table_name_prefix,
            @debug;

        /* Create IOIssues table if it doesn't exist */
        SET @create_sql = N'
            IF NOT EXISTS
            (
                SELECT
                    1/0
                FROM ' + QUOTENAME(@log_database_name) + N'.sys.tables AS t
                JOIN ' + QUOTENAME(@log_database_name) + N'.sys.schemas AS s
                  ON t.schema_id = s.schema_id
                WHERE t.name = @table_name + N''_IOIssues''
                AND   s.name = @schema_name
            )
            BEGIN
                CREATE TABLE ' + @log_table_io_issues + N'
                (
                    id bigint IDENTITY,
                    collection_time datetime2(7) NOT NULL DEFAULT SYSDATETIME(),
                    event_time datetime2(7) NULL,
                    state nvarchar(256) NULL,
                    ioLatchTimeouts bigint NULL,
                    intervalLongIos bigint NULL,
                    totalLongIos bigint NULL,
                    longestPendingRequests_duration_ms nvarchar(30) NULL,
                    longestPendingRequests_filePath nvarchar(500) NULL,
                    PRIMARY KEY CLUSTERED (collection_time, id)
                );
                IF @debug = 1 BEGIN RAISERROR(''Created table %s for IO issues logging.'', 0, 1, ''' + @log_table_io_issues + N''') WITH NOWAIT; END;
            END';

        EXECUTE sys.sp_executesql
            @create_sql,
          N'@schema_name sysname,
            @table_name sysname,
            @debug bit',
            @log_schema_name,
            @log_table_name_prefix,
            @debug;

        /* Create CPUTasks table if it doesn't exist */
        SET @create_sql = N'
            IF NOT EXISTS
            (
                SELECT
                    1/0
                FROM ' + QUOTENAME(@log_database_name) + N'.sys.tables AS t
                JOIN ' + QUOTENAME(@log_database_name) + N'.sys.schemas AS s
                  ON t.schema_id = s.schema_id
                WHERE t.name = @table_name + N''_CPUTasks''
                AND   s.name = @schema_name
            )
            BEGIN
                CREATE TABLE ' + @log_table_cpu_tasks + N'
                (
                    id bigint IDENTITY,
                    collection_time datetime2(7) NOT NULL DEFAULT SYSDATETIME(),
                    event_time datetime2(7) NULL,
                    state nvarchar(256) NULL,
                    maxWorkers bigint NULL,
                    workersCreated bigint NULL,
                    workersIdle bigint NULL,
                    tasksCompletedWithinInterval bigint NULL,
                    pendingTasks bigint NULL,
                    oldestPendingTaskWaitingTime bigint NULL,
                    hasUnresolvableDeadlockOccurred bit NULL,
                    hasDeadlockedSchedulersOccurred bit NULL,
                    didBlockingOccur bit NULL,
                    PRIMARY KEY CLUSTERED (collection_time, id)
                );
                IF @debug = 1 BEGIN RAISERROR(''Created table %s for CPU tasks logging.'', 0, 1, ''' + @log_table_cpu_tasks + N''') WITH NOWAIT; END;
            END';

        EXECUTE sys.sp_executesql
            @create_sql,
          N'@schema_name sysname,
            @table_name sysname,
            @debug bit',
            @log_schema_name,
            @log_table_name_prefix,
            @debug;

        /* Create MemoryConditions table if it doesn't exist */
        SET @create_sql = N'
            IF NOT EXISTS
            (
                SELECT
                    1/0
                FROM ' + QUOTENAME(@log_database_name) + N'.sys.tables AS t
                JOIN ' + QUOTENAME(@log_database_name) + N'.sys.schemas AS s
                  ON t.schema_id = s.schema_id
                WHERE t.name = @table_name + N''_MemoryConditions''
                AND   s.name = @schema_name
            )
            BEGIN
                CREATE TABLE ' + @log_table_memory_conditions + N'
                (
                    id bigint IDENTITY,
                    collection_time datetime2(7) NOT NULL DEFAULT SYSDATETIME(),
                    event_time datetime2(7) NULL,
                    lastNotification nvarchar(128) NULL,
                    outOfMemoryExceptions bigint NULL,
                    isAnyPoolOutOfMemory bit NULL,
                    processOutOfMemoryPeriod bigint NULL,
                    name nvarchar(128) NULL,
                    available_physical_memory_gb bigint NULL,
                    available_virtual_memory_gb bigint NULL,
                    available_paging_file_gb bigint NULL,
                    working_set_gb bigint NULL,
                    percent_of_committed_memory_in_ws bigint NULL,
                    page_faults bigint NULL,
                    system_physical_memory_high bigint NULL,
                    system_physical_memory_low bigint NULL,
                    process_physical_memory_low bigint NULL,
                    process_virtual_memory_low bigint NULL,
                    vm_reserved_gb bigint NULL,
                    vm_committed_gb bigint NULL,
                    locked_pages_allocated bigint NULL,
                    large_pages_allocated bigint NULL,
                    emergency_memory_gb bigint NULL,
                    emergency_memory_in_use_gb bigint NULL,
                    target_committed_gb bigint NULL,
                    current_committed_gb bigint NULL,
                    pages_allocated bigint NULL,
                    pages_reserved bigint NULL,
                    pages_free bigint NULL,
                    pages_in_use bigint NULL,
                    page_alloc_potential bigint NULL,
                    numa_growth_phase bigint NULL,
                    last_oom_factor bigint NULL,
                    last_os_error bigint NULL,
                    PRIMARY KEY CLUSTERED (collection_time, id)
                );
                IF @debug = 1 BEGIN RAISERROR(''Created table %s for memory conditions logging.'', 0, 1, ''' + @log_table_memory_conditions + N''') WITH NOWAIT; END;
            END';

        EXECUTE sys.sp_executesql
            @create_sql,
          N'@schema_name sysname,
            @table_name sysname,
            @debug bit',
            @log_schema_name,
            @log_table_name_prefix,
            @debug;

        /* Create MemoryBroker table if it doesn't exist */
        SET @create_sql = N'
            IF NOT EXISTS
            (
                SELECT
                    1/0
                FROM ' + QUOTENAME(@log_database_name) + N'.sys.tables AS t
                JOIN ' + QUOTENAME(@log_database_name) + N'.sys.schemas AS s
                  ON t.schema_id = s.schema_id
                WHERE t.name = @table_name + N''_MemoryBroker''
                AND   s.name = @schema_name
            )
            BEGIN
                CREATE TABLE ' + @log_table_memory_broker + N'
                (
                    id bigint IDENTITY,
                    collection_time datetime2(7) NOT NULL DEFAULT SYSDATETIME(),
                    event_time datetime2(7) NULL,
                    broker_id integer NULL,
                    pool_metadata_id integer NULL,
                    delta_time bigint NULL,
                    memory_ratio integer NULL,
                    new_target bigint NULL,
                    overall bigint NULL,
                    rate bigint NULL,
                    currently_predicated bigint NULL,
                    currently_allocated bigint NULL,
                    previously_allocated bigint NULL,
                    broker nvarchar(256) NULL,
                    notification nvarchar(256) NULL,
                    PRIMARY KEY CLUSTERED (collection_time, id)
                );
                IF @debug = 1 BEGIN RAISERROR(''Created table %s for memory broker logging.'', 0, 1, ''' + @log_table_memory_broker + N''') WITH NOWAIT; END;
            END';

        EXECUTE sys.sp_executesql
            @create_sql,
          N'@schema_name sysname,
            @table_name sysname,
            @debug bit',
            @log_schema_name,
            @log_table_name_prefix,
            @debug;

        /* Create MemoryNodeOOM table if it doesn't exist */
        SET @create_sql = N'
            IF NOT EXISTS
            (
                SELECT
                    1/0
                FROM ' + QUOTENAME(@log_database_name) + N'.sys.tables AS t
                JOIN ' + QUOTENAME(@log_database_name) + N'.sys.schemas AS s
                  ON t.schema_id = s.schema_id
                WHERE t.name = @table_name + N''_MemoryNodeOOM''
                AND   s.name = @schema_name
            )
            BEGIN
                CREATE TABLE ' + @log_table_memory_node_oom + N'
                (
                    id bigint IDENTITY,
                    collection_time datetime2(7) NOT NULL DEFAULT SYSDATETIME(),
                    event_time datetime2(7) NULL,
                    node_id integer NULL,
                    memory_node_id integer NULL,
                    memory_utilization_pct integer NULL,
                    total_physical_memory_kb bigint NULL,
                    available_physical_memory_kb bigint NULL,
                    total_page_file_kb bigint NULL,
                    available_page_file_kb bigint NULL,
                    total_virtual_address_space_kb bigint NULL,
                    available_virtual_address_space_kb bigint NULL,
                    target_kb bigint NULL,
                    reserved_kb bigint NULL,
                    committed_kb bigint NULL,
                    shared_committed_kb bigint NULL,
                    awe_kb bigint NULL,
                    pages_kb bigint NULL,
                    failure_type nvarchar(256) NULL,
                    failure_value integer NULL,
                    resources integer NULL,
                    factor_text nvarchar(256) NULL,
                    factor_value integer NULL,
                    last_error integer NULL,
                    pool_metadata_id integer NULL,
                    is_process_in_job nvarchar(10) NULL,
                    is_system_physical_memory_high nvarchar(10) NULL,
                    is_system_physical_memory_low nvarchar(10) NULL,
                    is_process_physical_memory_low nvarchar(10) NULL,
                    is_process_virtual_memory_low nvarchar(10) NULL,
                    PRIMARY KEY CLUSTERED (collection_time, id)
                );
                IF @debug = 1 BEGIN RAISERROR(''Created table %s for memory node OOM logging.'', 0, 1, ''' + @log_table_memory_node_oom + N''') WITH NOWAIT; END;
            END';

        EXECUTE sys.sp_executesql
            @create_sql,
          N'@schema_name sysname,
            @table_name sysname,
            @debug bit',
            @log_schema_name,
            @log_table_name_prefix,
            @debug;

        /* Create SystemHealth table if it doesn't exist */
        SET @create_sql = N'
            IF NOT EXISTS
            (
                SELECT
                    1/0
                FROM ' + QUOTENAME(@log_database_name) + N'.sys.tables AS t
                JOIN ' + QUOTENAME(@log_database_name) + N'.sys.schemas AS s
                  ON t.schema_id = s.schema_id
                WHERE t.name = @table_name + N''_SystemHealth''
                AND   s.name = @schema_name
            )
            BEGIN
                CREATE TABLE ' + @log_table_system_health + N'
                (
                    id bigint IDENTITY,
                    collection_time datetime2(7) NOT NULL DEFAULT SYSDATETIME(),
                    event_time datetime2(7) NULL,
                    state nvarchar(256) NULL,
                    spinlockBackoffs bigint NULL,
                    sickSpinlockType nvarchar(256) NULL,
                    sickSpinlockTypeAfterAv nvarchar(256) NULL,
                    latchWarnings bigint NULL,
                    isAccessViolationOccurred bigint NULL,
                    writeAccessViolationCount bigint NULL,
                    totalDumpRequests bigint NULL,
                    intervalDumpRequests bigint NULL,
                    nonYieldingTasksReported bigint NULL,
                    pageFaults bigint NULL,
                    systemCpuUtilization bigint NULL,
                    sqlCpuUtilization bigint NULL,
                    BadPagesDetected bigint NULL,
                    BadPagesFixed bigint NULL,
                    PRIMARY KEY CLUSTERED (collection_time, id)
                );
                IF @debug = 1 BEGIN RAISERROR(''Created table %s for system health logging.'', 0, 1, ''' + @log_table_system_health + N''') WITH NOWAIT; END;
            END';

        EXECUTE sys.sp_executesql
            @create_sql,
          N'@schema_name sysname,
            @table_name sysname,
            @debug bit',
            @log_schema_name,
            @log_table_name_prefix,
            @debug;

        /* Create SchedulerIssues table if it doesn't exist */
        SET @create_sql = N'
            IF NOT EXISTS
            (
                SELECT
                    1/0
                FROM ' + QUOTENAME(@log_database_name) + N'.sys.tables AS t
                JOIN ' + QUOTENAME(@log_database_name) + N'.sys.schemas AS s
                  ON t.schema_id = s.schema_id
                WHERE t.name = @table_name + N''_SchedulerIssues''
                AND   s.name = @schema_name
            )
            BEGIN
                CREATE TABLE ' + @log_table_scheduler_issues + N'
                (
                    id bigint IDENTITY,
                    collection_time datetime2(7) NOT NULL DEFAULT SYSDATETIME(),
                    event_time datetime2(7) NULL,
                    scheduler_id int NULL,
                    cpu_id int NULL,
                    status nvarchar(256) NULL,
                    is_online bit NULL,
                    is_runnable bit NULL,
                    is_running bit NULL,
                    non_yielding_time_ms nvarchar(30) NULL,
                    thread_quantum_ms nvarchar(30) NULL,
                    PRIMARY KEY CLUSTERED (collection_time, id)
                );
                IF @debug = 1 BEGIN RAISERROR(''Created table %s for scheduler issues logging.'', 0, 1, ''' + @log_table_scheduler_issues + N''') WITH NOWAIT; END;
            END';

        EXECUTE sys.sp_executesql
            @create_sql,
          N'@schema_name sysname,
            @table_name sysname,
            @debug bit',
            @log_schema_name,
            @log_table_name_prefix,
            @debug;

        /* Create SevereErrors table if it doesn't exist */
        SET @create_sql = N'
            IF NOT EXISTS
            (
                SELECT
                    1/0
                FROM ' + QUOTENAME(@log_database_name) + N'.sys.tables AS t
                JOIN ' + QUOTENAME(@log_database_name) + N'.sys.schemas AS s
                  ON t.schema_id = s.schema_id
                WHERE t.name = @table_name + N''_SevereErrors''
                AND   s.name = @schema_name
            )
            BEGIN
                CREATE TABLE ' + @log_table_severe_errors + N'
                (
                    id bigint IDENTITY,
                    collection_time datetime2(7) NOT NULL DEFAULT SYSDATETIME(),
                    event_time datetime2(7) NULL,
                    error_number integer NULL,
                    severity integer NULL,
                    state integer NULL,
                    message nvarchar(max) NULL,
                    database_name sysname NULL,
                    database_id integer NULL,
                    PRIMARY KEY CLUSTERED (collection_time, id)
                );
                IF @debug = 1 BEGIN RAISERROR(''Created table %s for severe errors logging.'', 0, 1, ''' + @log_table_severe_errors + N''') WITH NOWAIT; END;
            END';

        EXECUTE sys.sp_executesql
            @create_sql,
          N'@schema_name sysname,
            @table_name sysname,
            @debug bit',
            @log_schema_name,
            @log_table_name_prefix,
            @debug;

        /* Handle log retention if specified */
        IF @log_to_table = 1 AND @log_retention_days > 0
        BEGIN
            IF @debug = 1
            BEGIN
                RAISERROR('Cleaning up log tables older than %i days', 0, 1, @log_retention_days) WITH NOWAIT;
            END;

            SET @cleanup_date =
                DATEADD
                (
                    DAY,
                    -@log_retention_days,
                    SYSDATETIME()
                );

            /* Clean up each log table */
            SET @dsql = N'
    DELETE FROM ' + @log_table_significant_waits + '
    WHERE collection_time < @cleanup_date;

    DELETE FROM ' + @log_table_waits_by_count + '
    WHERE collection_time < @cleanup_date;

    DELETE FROM ' + @log_table_waits_by_duration + '
    WHERE collection_time < @cleanup_date;

    DELETE FROM ' + @log_table_io_issues + '
    WHERE collection_time < @cleanup_date;

    DELETE FROM ' + @log_table_cpu_tasks + '
    WHERE collection_time < @cleanup_date;

    DELETE FROM ' + @log_table_memory_conditions + '
    WHERE collection_time < @cleanup_date;

    DELETE FROM ' + @log_table_memory_broker + '
    WHERE collection_time < @cleanup_date;

    DELETE FROM ' + @log_table_memory_node_oom + '
    WHERE collection_time < @cleanup_date;

    DELETE FROM ' + @log_table_system_health + '
    WHERE collection_time < @cleanup_date;

    DELETE FROM ' + @log_table_scheduler_issues + '
    WHERE collection_time < @cleanup_date;

    DELETE FROM ' + @log_table_severe_errors + '
    WHERE collection_time < @cleanup_date;
            ';

            IF @debug = 1
            BEGIN
                PRINT @dsql;
            END;

            EXECUTE sys.sp_executesql
                @dsql,
              N'@cleanup_date datetime2(7)',
                @cleanup_date;

            IF @debug = 1
            BEGIN
                RAISERROR('Log cleanup complete', 0, 0) WITH NOWAIT;
            END;
        END;
    END;

    IF @debug = 1
    BEGIN
        RAISERROR('Creating temp tables', 0, 0) WITH NOWAIT;
    END;

    DECLARE
        @collection_areas table
    (
        id tinyint IDENTITY PRIMARY KEY CLUSTERED,
        area_name varchar(20) NOT NULL,
        object_name sysname NOT NULL,
        temp_table sysname NOT NULL,
        insert_list sysname NOT NULL,
        should_collect bit NOT NULL DEFAULT 0,
        is_processed bit NOT NULL DEFAULT 0
    );

    INSERT INTO
        @collection_areas
    (
        area_name,
        object_name,
        temp_table,
        insert_list,
        should_collect
    )
    SELECT
        v.area_name,
        v.object_name,
        v.temp_table,
        v.insert_list,
        should_collect =
            CASE
                WHEN @what_to_check = 'all'
                THEN
                    CASE
                        WHEN v.area_name = 'locking'
                        AND  @skip_locks = 1
                        THEN 0
                        ELSE 1
                    END
                WHEN @what_to_check = v.area_name
                THEN 1
                ELSE 0
            END
    FROM
    (
    VALUES
        ('cpu', 'scheduler_monitor_system_health', '#scheduler_monitor', 'scheduler_monitor'),
        ('disk', 'sp_server_diagnostics_component_result', '#sp_server_diagnostics_component_result', 'sp_server_diagnostics_component_result'),
        ('locking', 'xml_deadlock_report', '#xml_deadlock_report', 'xml_deadlock_report'),
        ('locking', 'sp_server_diagnostics_component_result', '#sp_server_diagnostics_component_result', 'sp_server_diagnostics_component_result'),
        ('waits', 'wait_info', '#wait_info', 'wait_info'),
        ('system', 'sp_server_diagnostics_component_result', '#sp_server_diagnostics_component_result', 'sp_server_diagnostics_component_result'),
        ('system', 'error_reported', '#error_reported', 'error_reported'),
        ('memory', 'memory_broker_ring_buffer_recorded', '#memory_broker', 'memory_broker'),
        ('memory', 'memory_node_oom_ring_buffer_recorded', '#memory_node_oom', 'memory_node_oom')
    ) AS v(area_name, object_name, temp_table, insert_list);

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '@collection_areas',
            ca.*
        FROM @collection_areas AS ca
        ORDER BY
            ca.id
        OPTION(RECOMPILE);
    END;

    CREATE TABLE
        #ignore_waits
    (
        wait_type nvarchar(60) NOT NULL
    );

    CREATE TABLE
        #ignore_errors
    (
        error_number integer NOT NULL
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
        #blocking_xml
    (
        event_time datetime2 NOT NULL,
        human_events_xml xml NOT NULL
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

    CREATE TABLE
        #scheduler_monitor
    (
        scheduler_monitor xml NOT NULL
    );

    CREATE TABLE
        #error_reported
    (
        error_reported xml NOT NULL
    );

    CREATE TABLE
        #memory_broker
    (
        memory_broker xml NOT NULL
    );

    CREATE TABLE
        #memory_node_oom
    (
        memory_node_oom xml NOT NULL
    );

    /*The more you ignore waits, the worser they get*/
    IF @what_to_check IN ('all', 'waits')
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Inserting ignorable waits to #ignore_waits', 0, 0) WITH NOWAIT;
        END;

        INSERT
            #ignore_waits
        WITH
            (TABLOCKX)
        (
            wait_type
        )
        SELECT
            dows.wait_type
        FROM sys.dm_os_wait_stats AS dows
        WHERE dows.wait_type IN
        (
            N'ASYNC_IO_COMPLETION', N'AZURE_IMDS_VERSIONS', N'BROKER_EVENTHANDLER', N'BROKER_RECEIVE_WAITFOR',
            N'BROKER_TASK_STOP', N'BROKER_TO_FLUSH', N'BROKER_TRANSMITTER', N'CHECKPOINT_QUEUE',
            N'CHKPT', N'CLR_AUTO_EVENT', N'CLR_MANUAL_EVENT', N'CLR_SEMAPHORE',
            N'DBMIRROR_DBM_EVENT', N'DBMIRROR_DBM_MUTEX', N'DBMIRROR_EVENTS_QUEUE', N'DBMIRROR_SEND',
            N'DBMIRROR_WORKER_QUEUE', N'DBMIRRORING_CMD', N'DIRTY_PAGE_POLL', N'DISPATCHER_QUEUE_SEMAPHORE',
            N'FSAGENT', N'FT_IFTS_SCHEDULER_IDLE_WAIT', N'FT_IFTSHC_MUTEX', N'HADR_CLUSAPI_CALL',
            N'HADR_FILESTREAM_IOMGR_IOCOMPLETION', N'HADR_LOGCAPTURE_WAIT', N'HADR_NOTIFICATION_DEQUEUE', N'HADR_TIMER_TASK',
            N'HADR_WORK_QUEUE', N'KSOURCE_WAKEUP', N'LAZYWRITER_SLEEP', N'LOGMGR_QUEUE',
            N'MEMORY_ALLOCATION_EXT', N'ONDEMAND_TASK_QUEUE', N'PARALLEL_REDO_DRAIN_WORKER', N'PARALLEL_REDO_LOG_CACHE',
            N'PARALLEL_REDO_TRAN_LIST', N'PARALLEL_REDO_WORKER_SYNC', N'PARALLEL_REDO_WORKER_WAIT_WORK', N'PREEMPTIVE_OS_FLUSHFILEBUFFERS',
            N'PREEMPTIVE_XE_GETTARGETSTATE', N'PVS_PREALLOCATE', N'PWAIT_ALL_COMPONENTS_INITIALIZED', N'PWAIT_DIRECTLOGCONSUMER_GETNEXT',
            N'PWAIT_EXTENSIBILITY_CLEANUP_TASK', N'QDS_ASYNC_QUEUE', N'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP', N'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP',
            N'QDS_SHUTDOWN_QUEUE', N'REDO_THREAD_PENDING_WORK', N'REQUEST_FOR_DEADLOCK_SEARCH', N'RESOURCE_QUEUE',
            N'SERVER_IDLE_CHECK', N'SLEEP_DBSTARTUP', N'SLEEP_DCOMSTARTUP', N'SLEEP_MASTERDBREADY',
            N'SLEEP_MASTERMDREADY', N'SLEEP_MASTERUPGRADED', N'SLEEP_MSDBSTARTUP', N'SLEEP_SYSTEMTASK',
            N'SLEEP_TEMPDBSTARTUP', N'SNI_HTTP_ACCEPT', N'SOS_WORK_DISPATCHER', N'SP_SERVER_DIAGNOSTICS_SLEEP',
            N'SQLTRACE_BUFFER_FLUSH', N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP', N'SQLTRACE_WAIT_ENTRIES', N'UCS_SESSION_REGISTRATION',
            N'VDI_CLIENT_OTHER', N'WAIT_FOR_RESULTS', N'WAIT_XTP_CKPT_CLOSE', N'WAIT_XTP_HOST_WAIT',
            N'WAIT_XTP_OFFLINE_CKPT_NEW_LOG', N'WAIT_XTP_RECOVERY', N'WAITFOR', N'WAITFOR_TASKSHUTDOWN',
            N'XE_DISPATCHER_JOIN', N'XE_DISPATCHER_WAIT', N'XE_FILE_TARGET_TVF', N'XE_LIVE_TARGET_TVF', N'XE_TIMER_EVENT'
        )
        OPTION(RECOMPILE);
    END; /*End waits ignore*/

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#ignore_waits',
            i.*
        FROM #ignore_waits AS i ORDER BY i.wait_type
        OPTION(RECOMPILE);
    END;

    /* First, ensure we're working with the correct collection areas */
    IF @debug = 1
    BEGIN
        RAISERROR('Beginning collection loop for system_health data', 0, 0) WITH NOWAIT;
    END;

    /* Declare a cursor to process each collection area */
    SET @collection_cursor =
        CURSOR
        LOCAL
        SCROLL
        DYNAMIC
        READ_ONLY
    FOR
    SELECT
        ca.area_name,
        ca.object_name,
        ca.temp_table,
        ca.insert_list
    FROM @collection_areas AS ca
    WHERE ca.should_collect = 1
    AND   ca.is_processed = 0
    ORDER BY
        ca.id;

    OPEN @collection_cursor;

    FETCH NEXT
    FROM @collection_cursor
    INTO
        @area_name,
        @object_name,
        @temp_table,
        @insert_list;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        /* Build the SQL statement for this collection area */
        SET
            @collection_sql =
                REPLACE
                (
                    REPLACE
                    (
                        REPLACE
                        (
                            @sql_template,
                            '{object_name}',
                            @object_name
                        ),
                        '{temp_table}',
                        @temp_table
                    ),
                    '{insert_list}',
                    @insert_list
                );

        IF @debug = 1
        BEGIN
            RAISERROR('Collecting data for area: %s, object: %s, target table: %s', 0, 1, @area_name, @object_name, @temp_table) WITH NOWAIT;
            PRINT @collection_sql;
        END;

        IF @debug = 1
        BEGIN
            RAISERROR('Executing collection SQL', 0, 0) WITH NOWAIT;
            SET STATISTICS XML ON;
        END;

        EXECUTE sys.sp_executesql
            @collection_sql,
            @params,
            @start_date,
            @end_date;

        IF @debug = 1
        BEGIN
            SET STATISTICS XML OFF;
        END;

        UPDATE
            @collection_areas
        SET
            is_processed = 1
        WHERE temp_table = @temp_table
        AND   should_collect = 1;

        FETCH NEXT
        FROM @collection_cursor
        INTO
            @area_name,
            @object_name,
            @temp_table,
            @insert_list;
    END;

    IF @debug = 1
    BEGIN
        RAISERROR('Data collection complete', 0, 0) WITH NOWAIT;
    END;

    IF @mi = 1
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Starting Managed Instance analysis', 0, 0) WITH NOWAIT;
            RAISERROR('Inserting #x', 0, 0) WITH NOWAIT;
        END;

        INSERT
            #x
        WITH
            (TABLOCKX)
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
            RAISERROR('Inserting #ring_buffer', 0, 0) WITH NOWAIT;
        END;

        INSERT
            #ring_buffer
        WITH
            (TABLOCKX)
        (
            ring_buffer
        )
        SELECT
            x = e.x.query('.')
        FROM #x AS x
        CROSS APPLY x.x.nodes('//event') AS e(x)
        WHERE 1 = 1
        AND   e.x.exist('@timestamp[.>= sql:variable("@start_date") and .< sql:variable("@end_date")]') = 1
        AND   e.x.exist('@name[.= "security_error_ring_buffer_recorded"]') = 0
        AND   e.x.exist('@name[.= "connectivity_ring_buffer_recorded"]') = 0
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
                RAISERROR('Checking Managed Instance waits', 0, 0) WITH NOWAIT;
                RAISERROR('Inserting #wait_info', 0, 0) WITH NOWAIT;
            END;

            INSERT
                #wait_info
            WITH
                (TABLOCKX)
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
        IF @what_to_check IN ('all', 'disk', 'locking', 'system', 'memory')
        BEGIN
            IF @debug = 1
            BEGIN
                RAISERROR('Checking Managed Instance sp_server_diagnostics_component_result', 0, 0) WITH NOWAIT;
                RAISERROR('Inserting #sp_server_diagnostics_component_result', 0, 0) WITH NOWAIT;
            END;

            INSERT
                #sp_server_diagnostics_component_result
            WITH
                (TABLOCKX)
            (
                sp_server_diagnostics_component_result
            )
            SELECT
                e.x.query('.')
            FROM #ring_buffer AS rb
            CROSS APPLY rb.ring_buffer.nodes('/event') AS e(x)
            WHERE e.x.exist('@name[.= "sp_server_diagnostics_component_result"]') = 1
            OPTION(RECOMPILE);
        END;

        IF
        (
             @what_to_check IN ('all', 'locking')
         AND @skip_locks = 0
        )
        BEGIN
            IF @debug = 1
            BEGIN
                RAISERROR('Checking Managed Instance deadlocks', 0, 0) WITH NOWAIT;
                RAISERROR('Inserting #xml_deadlock_report', 0, 0) WITH NOWAIT;
            END;

            INSERT
                #xml_deadlock_report
            WITH
                (TABLOCKX)
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

        /* Add scheduler_monitor collection for MI */
        IF @what_to_check IN ('all', 'system', 'cpu')
        BEGIN
            IF @debug = 1
            BEGIN
                RAISERROR('Checking Managed Instance scheduler monitor', 0, 0) WITH NOWAIT;
                RAISERROR('Inserting #scheduler_monitor', 0, 0) WITH NOWAIT;
            END;

            INSERT
                #scheduler_monitor
            WITH
                (TABLOCKX)
            (
                scheduler_monitor
            )
            SELECT
                e.x.query('.')
            FROM #ring_buffer AS rb
            CROSS APPLY rb.ring_buffer.nodes('/event') AS e(x)
            WHERE e.x.exist('@name[.= "scheduler_monitor_system_health"]') = 1
            OPTION(RECOMPILE);
        END;

        /* Add error_reported collection for MI */
        IF @what_to_check IN ('all', 'system')
        BEGIN
            IF @debug = 1
            BEGIN
                RAISERROR('Checking Managed Instance error reported events', 0, 0) WITH NOWAIT;
                RAISERROR('Inserting #error_reported', 0, 0) WITH NOWAIT;
            END;

            INSERT
                #error_reported
            WITH
                (TABLOCKX)
            (
                error_reported
            )
            SELECT
                e.x.query('.')
            FROM #ring_buffer AS rb
            CROSS APPLY rb.ring_buffer.nodes('/event') AS e(x)
            WHERE e.x.exist('@name[.= "error_reported"]') = 1
            OPTION(RECOMPILE);
        END;

        /* Add memory_broker collection for MI */
        IF @what_to_check IN ('all', 'memory')
        BEGIN
            IF @debug = 1
            BEGIN
                RAISERROR('Checking Managed Instance memory broker events', 0, 0) WITH NOWAIT;
                RAISERROR('Inserting #memory_broker', 0, 0) WITH NOWAIT;
            END;

            INSERT
                #memory_broker
            WITH
                (TABLOCKX)
            (
                memory_broker
            )
            SELECT
                e.x.query('.')
            FROM #ring_buffer AS rb
            CROSS APPLY rb.ring_buffer.nodes('/event') AS e(x)
            WHERE e.x.exist('@name[.= "memory_broker_ring_buffer_recorded"]') = 1
            OPTION(RECOMPILE);
        END;

        /* Add memory node OOM collection for MI */
        IF @what_to_check IN ('all', 'memory')
        BEGIN
            IF @debug = 1
            BEGIN
                RAISERROR('Checking Managed Instance memory node OOM events', 0, 0) WITH NOWAIT;
                RAISERROR('Inserting #memory_node_oom', 0, 0) WITH NOWAIT;
            END;

            INSERT
                #memory_node_oom
            WITH
                (TABLOCKX)
            (
                memory_node_oom
            )
            SELECT
                e.x.query('.')
            FROM #ring_buffer AS rb
            CROSS APPLY rb.ring_buffer.nodes('/event') AS e(x)
            WHERE e.x.exist('@name[.= "memory_node_oom_ring_buffer_recorded"]') = 1
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

        SELECT TOP (100)
            table_name = '#scheduler_monitor, top 100 rows',
            x.*
        FROM #scheduler_monitor AS x;

        SELECT TOP (100)
            table_name = '#error_reported, top 100 rows',
            x.*
        FROM #error_reported AS x;

        SELECT TOP (100)
            table_name = '#memory_broker, top 100 rows',
            x.*
        FROM #memory_broker AS x;

        SELECT TOP (100)
            table_name = '#memory_node_oom, top 100 rows',
            x.*
        FROM #memory_node_oom AS x;
    END;

    /*Parse out the wait_info data*/
    IF @what_to_check IN ('all', 'waits')
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Parsing queries with significant waits', 0, 0) WITH NOWAIT;
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
        AND   w.x.exist('(action[@name="sql_text"]/value/text()[contains(upper-case(.), "BACKUP")] )') = 0
        AND   w.x.exist('(data[@name="duration"]/value/text())[.>= sql:variable("@wait_duration_ms")]') = 1
        AND   NOT EXISTS
              (
                  SELECT
                      1/0
                  FROM #ignore_waits AS i
                  WHERE w.x.exist('(data[@name="wait_type"]/text/text())[1][.= sql:column("i.wait_type")]') = 1
              )
        OPTION(RECOMPILE);

        IF @debug = 1
        BEGIN
            RAISERROR('Adding query_text to #waits_queries', 0, 0) WITH NOWAIT;
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

        /* First logging section, queries with significant waits*/
        IF NOT EXISTS
        (
            SELECT
                1/0
            FROM #waits_queries AS wq
        )
        BEGIN
            IF @log_to_table = 0
            BEGIN
                /* No results logic, only return if not logging */
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

                RAISERROR('No queries with significant waits found', 0, 0) WITH NOWAIT;
            END;
        END;
        ELSE
        BEGIN
            /* Build the query */
            SET @dsql = N'
            SELECT
                ' + CASE
                        WHEN @log_to_table = 1
                        THEN N''
                        ELSE N'finding = ''queries with significant waits'','
                    END +
              N'
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
                    N''.00'',
                    N''''
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
                    N''.00'',
                    N''''
                    ),
                wq.wait_resource,
                query_text =
                    (
                        SELECT
                            [processing-instruction(query)] =
                                wq.query_text
                        FOR XML
                            PATH(N''''),
                            TYPE
                    ),
                wq.session_id
            FROM #waits_queries AS wq';

            /* Add the WHERE clause only for table logging */
            IF @log_to_table = 1
            BEGIN
                SET @mdsql_execute =
                    REPLACE
                    (
                        REPLACE
                        (
                            @mdsql_template,
                            '{table_check}',
                            @log_table_significant_waits
                        ),
                        '{date_column}',
                        'event_time'
                    );

                IF @debug = 1
                BEGIN
                    PRINT @mdsql_execute;
                END;

                EXECUTE sys.sp_executesql
                    @mdsql_execute,
                  N'@max_event_time datetime2(7) OUTPUT',
                    @max_event_time OUTPUT;

                SET @dsql += N'
            WHERE wq.event_time > @max_event_time';
            END;

            /* Add the ORDER BY clause */
            SET @dsql += N'
            ORDER BY
                wq.duration_ms DESC
            OPTION(RECOMPILE);
            ';

            /* Handle table logging */
            IF @log_to_table = 1
            BEGIN
                SET @insert_sql = N'
            INSERT INTO
                ' + @log_table_significant_waits + N'
            (
                event_time,
                wait_type,
                duration_ms,
                signal_duration_ms,
                wait_resource,
                query_text,
                session_id
            )' +
                @dsql;

                IF @debug = 1
                BEGIN
                    PRINT @insert_sql;
                END;

                EXECUTE sys.sp_executesql
                    @insert_sql,
                  N'@max_event_time datetime2(7)',
                    @max_event_time;
            END;

            /* Execute the query for client results */
            IF @log_to_table = 0
            BEGIN
                IF @debug = 1
                BEGIN
                    PRINT @dsql;
                END;

                EXECUTE sys.sp_executesql
                    @dsql;
            END;
        END;

        /*Waits by count*/
        IF @debug = 1
        BEGIN
            RAISERROR('Parsing #waits_by_count', 0, 0) WITH NOWAIT;
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
                  FROM #ignore_waits AS i
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

        /* Waits by count logging section */
        IF NOT EXISTS
        (
            SELECT
                1/0
            FROM #tc AS t
        )
        BEGIN
            IF @log_to_table = 0
            BEGIN
                /* No results logic, only return if not logging */
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
                        END

                RAISERROR('No waits by count found', 0, 0) WITH NOWAIT;
            END;
        END;
        ELSE
        BEGIN
            /* Build the query */
            SET @dsql = N'
            SELECT
                ' + CASE
                        WHEN @log_to_table = 1
                        THEN N''
                        ELSE N'finding = ''waits by count'','
                    END +
              N'
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
                    N''.00'',
                    N''''
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
                    N''.00'',
                    N''''
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
                    N''.00'',
                    N''''
                    )
            FROM #tc AS t';

            /* Add the WHERE clause only for table logging */
            IF @log_to_table = 1
            BEGIN
                SET @mdsql_execute =
                    REPLACE
                    (
                        REPLACE
                        (
                            @mdsql_template,
                            '{table_check}',
                            @log_table_waits_by_count
                        ),
                        '{date_column}',
                        'event_time_rounded'
                    );

                IF @debug = 1
                BEGIN
                    PRINT @mdsql_execute;
                END;

                EXECUTE sys.sp_executesql
                    @mdsql_execute,
                  N'@max_event_time datetime2(7) OUTPUT',
                    @max_event_time OUTPUT;

                SET @dsql += N'
            WHERE t.event_time_rounded > @max_event_time';
            END;

            /* Add the ORDER BY clause */
            SET @dsql += N'
            ORDER BY
                t.event_time_rounded DESC,
                t.waits DESC
            OPTION(RECOMPILE);
            ';

            /* Handle table logging */
            IF @log_to_table = 1
            BEGIN
                SET @insert_sql = N'
            INSERT INTO
                ' + @log_table_waits_by_count + N'
            (
                event_time_rounded,
                wait_type,
                waits,
                average_wait_time_ms,
                max_wait_time_ms
            )' +
                @dsql;

                IF @debug = 1
                BEGIN
                    PRINT @insert_sql;
                END;

                EXECUTE sys.sp_executesql
                    @insert_sql,
                  N'@max_event_time datetime2(7)',
                    @max_event_time;
            END;

            /* Execute the query for client results */
            IF @log_to_table = 0
            BEGIN
                IF @debug = 1
                BEGIN
                    PRINT @dsql;
                END;

                EXECUTE sys.sp_executesql
                    @dsql;
            END;
        END;

        /*Grab waits by duration*/
        IF @debug = 1
        BEGIN
            RAISERROR('Parsing waits by duration', 0, 0) WITH NOWAIT;
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
                  FROM #ignore_waits AS i
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

        /* Waits by duration logging section */
        IF NOT EXISTS
        (
            SELECT
                1/0
            FROM #td AS t
        )
        BEGIN
            IF @log_to_table = 0
            BEGIN
                /* No results logic, only return if not logging */
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
                        END

                RAISERROR('No waits by duration', 0, 0) WITH NOWAIT;
            END;
        END;
        ELSE
        BEGIN
            /* Build the query */
            SET @dsql = N'
            SELECT
                ' + CASE
                        WHEN @log_to_table = 1
                        THEN N''
                        ELSE N'finding = ''waits by duration'','
                    END +
              N'
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
                        N''.00'',
                        N''''
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
                        N''.00'',
                        N''''
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
                        N''.00'',
                        N''''
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
            WHERE x.n = 1';

            /* Add the WHERE clause only for table logging */
            IF @log_to_table = 1
            BEGIN
                SET @mdsql_execute =
                    REPLACE
                    (
                        REPLACE
                        (
                            @mdsql_template,
                            '{table_check}',
                            @log_table_waits_by_duration
                        ),
                        '{date_column}',
                        'event_time_rounded'
                    );

                IF @debug = 1
                BEGIN
                    PRINT @mdsql_execute;
                END;

                EXECUTE sys.sp_executesql
                    @mdsql_execute,
                  N'@max_event_time datetime2(7) OUTPUT',
                    @max_event_time OUTPUT;

                SET @dsql += N'
            AND x.event_time_rounded > @max_event_time';
            END;

            /* Add the ORDER BY clause */
            SET @dsql += N'
            ORDER BY
                x.s
            OPTION(RECOMPILE);
            ';

            /* Handle table logging */
            IF @log_to_table = 1
            BEGIN
                SET @insert_sql = N'
            INSERT INTO
                ' + @log_table_waits_by_duration + N'
            (
                event_time_rounded,
                wait_type,
                average_wait_time_ms,
                max_wait_time_ms
            )' +
                @dsql;

                IF @debug = 1
                BEGIN
                    PRINT @insert_sql;
                END;

                EXECUTE sys.sp_executesql
                    @insert_sql,
                  N'@max_event_time datetime2(7)',
                    @max_event_time;
            END;

            /* Execute the query for client results */
            IF @log_to_table = 0
            BEGIN
                IF @debug = 1
                BEGIN
                    PRINT @dsql;
                END;

                EXECUTE sys.sp_executesql
                    @dsql;
            END;
        END;
    END; /*End wait stats*/

    /*Grab IO stuff*/
    IF @what_to_check IN ('all', 'disk')
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Parsing disk stuff', 0, 0) WITH NOWAIT;
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
                SUM(i.longestPendingRequests_duration_ms),
            longestPendingRequests_filePath =
                ISNULL(i.longestPendingRequests_filePath, 'N/A')
        INTO #i
        FROM #io AS i
        WHERE i.longestPendingRequests_duration_ms IS NOT NULL
        GROUP BY
            i.event_time,
            i.state,
            i.ioLatchTimeouts,
            i.intervalLongIos,
            i.totalLongIos,
            ISNULL(i.longestPendingRequests_filePath, 'N/A')
        OPTION(RECOMPILE);

        /* Potential IO issues logging section */
        IF NOT EXISTS
        (
            SELECT
                1/0
            FROM #i AS i
        )
        BEGIN
            IF @log_to_table = 0
            BEGIN
                /* No results logic, only return if not logging */
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
                        END
                RAISERROR('No io data found', 0, 0) WITH NOWAIT;
            END;
        END;
        ELSE
        BEGIN
            /* Build the query */
            SET @dsql = N'
            SELECT
                ' + CASE
                        WHEN @log_to_table = 1
                        THEN N''
                        ELSE N'finding = ''potential io issues'','
                    END +
              N'
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
                    N''.00'',
                    N''''
                    ),
                i.longestPendingRequests_filePath
            FROM #i AS i';

            /* Add the WHERE clause only for table logging */
            IF @log_to_table = 1
            BEGIN
                /* Get max event_time for IO issues */
                SET @mdsql_execute =
                    REPLACE
                    (
                        REPLACE
                        (
                            @mdsql_template,
                            '{table_check}',
                            @log_table_io_issues
                        ),
                        '{date_column}',
                        'event_time'
                    );

                IF @debug = 1
                BEGIN
                    PRINT @mdsql_execute;
                END;

                EXECUTE sys.sp_executesql
                    @mdsql_execute,
                  N'@max_event_time datetime2(7) OUTPUT',
                    @max_event_time OUTPUT;

                SET @dsql += N'
            WHERE i.event_time > @max_event_time';
            END;

            /* Add the ORDER BY clause */
            SET @dsql += N'
            ORDER BY
                i.event_time DESC
            OPTION(RECOMPILE);
            ';

            /* Handle table logging */
            IF @log_to_table = 1
            BEGIN
                SET @insert_sql = N'
            INSERT INTO
                ' + @log_table_io_issues + N'
            (
                event_time,
                state,
                ioLatchTimeouts,
                intervalLongIos,
                totalLongIos,
                longestPendingRequests_duration_ms,
                longestPendingRequests_filePath
            )'
                + @dsql;

                IF @debug = 1
                BEGIN
                    PRINT @insert_sql;
                END;

                EXECUTE sys.sp_executesql
                    @insert_sql,
                  N'@max_event_time datetime2(7)',
                    @max_event_time;
            END;

            /* Execute the query for client results */
            IF @log_to_table = 0
            BEGIN
                IF @debug = 1
                BEGIN
                    PRINT @dsql;
                END;

                EXECUTE sys.sp_executesql
                    @dsql;
            END;
        END;
    END; /*End disk*/

    /*Grab CPU details*/
    IF @what_to_check IN ('all', 'cpu')
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Parsing CPU stuff', 0, 0) WITH NOWAIT;
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

END;

    /* CPU task details logging section */
    IF NOT EXISTS
    (
        SELECT
            1/0
        FROM #scheduler_details AS sd
    )
    BEGIN
        IF @log_to_table = 0
            BEGIN
            /* No results logic, only return if not logging */
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
                    END

            RAISERROR('No scheduler data found', 0, 0) WITH NOWAIT;
        END;
    END;
    ELSE
    BEGIN
        /* Build the query */
        SET @dsql = N'
            SELECT
                ' + CASE
                        WHEN @log_to_table = 1
                        THEN N''
                        ELSE N'finding = ''cpu task details'','
                    END +
              N'
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
            FROM #scheduler_details AS sd';

        /* Add the WHERE clause only for table logging */
        IF @log_to_table = 1
        BEGIN
            /* Get max event_time for CPU task details */
            SET @mdsql_execute =
                REPLACE
                (
                    REPLACE
                    (
                        @mdsql_template,
                        '{table_check}',
                        @log_table_cpu_tasks
                    ),
                    '{date_column}',
                    'event_time'
                );

            IF @debug = 1
            BEGIN
                PRINT @mdsql_execute;
            END;

            EXECUTE sys.sp_executesql
                @mdsql_execute,
              N'@max_event_time datetime2(7) OUTPUT',
                @max_event_time OUTPUT;

            SET @dsql += N'
        WHERE sd.event_time > @max_event_time';
        END;

        /* Add the ORDER BY clause */
        SET @dsql += N'
        ORDER BY
            sd.event_time DESC
        OPTION(RECOMPILE);
        ';

        /* Handle table logging */
        IF @log_to_table = 1
        BEGIN
            SET @insert_sql = N'
            INSERT INTO
                ' + @log_table_cpu_tasks + N'
            (
                event_time,
                state,
                maxWorkers,
                workersCreated,
                workersIdle,
                tasksCompletedWithinInterval,
                pendingTasks,
                oldestPendingTaskWaitingTime,
                hasUnresolvableDeadlockOccurred,
                hasDeadlockedSchedulersOccurred,
                didBlockingOccur
            )' +
                @dsql;

            IF @debug = 1
            BEGIN
                PRINT @insert_sql;
            END;

            EXECUTE sys.sp_executesql
                @insert_sql,
              N'@max_event_time datetime2(7)',
                @max_event_time;
        END;

        /* Execute the query for client results */
        IF @log_to_table = 0
        BEGIN
            IF @debug = 1
            BEGIN
                PRINT @dsql;
            END;

            EXECUTE sys.sp_executesql
                @dsql;
        END;
    END; /*End CPU*/

    /*Grab memory details*/
    IF @what_to_check IN ('all', 'memory')
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Parsing memory stuff', 0, 0) WITH NOWAIT;
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

        /* Memory conditions logging section */
        IF NOT EXISTS
        (
            SELECT
                1/0
            FROM #memory AS m
        )
        BEGIN
            IF @log_to_table = 0
            BEGIN
                /* No results logic, only return if not logging */
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
                        END

                RAISERROR('No memory condition data found', 0, 0) WITH NOWAIT;
            END;
        END;
        ELSE
        BEGIN
            /* Build the query */
            SET @dsql = N'
            SELECT
                ' + CASE
                        WHEN @log_to_table = 1
                        THEN N''
                        ELSE N'finding = ''memory conditions'','
                    END +
              N'm.event_time,
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
            FROM #memory AS m';

            /* Add the WHERE clause only for table logging */
            IF @log_to_table = 1
            BEGIN
                /* Get max event_time for memory conditions */
                SET @mdsql_execute =
                    REPLACE
                    (
                        REPLACE
                        (
                            @mdsql_template,
                            '{table_check}',
                            @log_table_memory_conditions
                        ),
                        '{date_column}',
                        'event_time'
                    );

                IF @debug = 1
                BEGIN
                    PRINT @mdsql_execute;
                END;

                EXECUTE sys.sp_executesql
                    @mdsql_execute,
                  N'@max_event_time datetime2(7) OUTPUT',
                    @max_event_time OUTPUT;

                SET @dsql += N'
            WHERE m.event_time > @max_event_time';
            END;

            /* Add the ORDER BY clause */
            SET @dsql += N'
            ORDER BY
                m.event_time DESC
            OPTION(RECOMPILE);
            ';

            /* Handle table logging */
            IF @log_to_table = 1
            BEGIN
                SET @insert_sql = N'
            INSERT INTO
                ' + @log_table_memory_conditions + N'
            (
                event_time,
                lastNotification,
                outOfMemoryExceptions,
                isAnyPoolOutOfMemory,
                processOutOfMemoryPeriod,
                name,
                available_physical_memory_gb,
                available_virtual_memory_gb,
                available_paging_file_gb,
                working_set_gb,
                percent_of_committed_memory_in_ws,
                page_faults,
                system_physical_memory_high,
                system_physical_memory_low,
                process_physical_memory_low,
                process_virtual_memory_low,
                vm_reserved_gb,
                vm_committed_gb,
                locked_pages_allocated,
                large_pages_allocated,
                emergency_memory_gb,
                emergency_memory_in_use_gb,
                target_committed_gb,
                current_committed_gb,
                pages_allocated,
                pages_reserved,
                pages_free,
                pages_in_use,
                page_alloc_potential,
                numa_growth_phase,
                last_oom_factor,
                last_os_error
            )'
            +
                @dsql;

                IF @debug = 1
                BEGIN
                    PRINT @insert_sql;
                END;

                EXECUTE sys.sp_executesql
                    @insert_sql,
                  N'@max_event_time datetime2(7)',
                    @max_event_time;
            END;

            /* Execute the query for client results */
            IF @log_to_table = 0
            BEGIN
                IF @debug = 1
                BEGIN
                    PRINT @dsql;
                END;

                EXECUTE sys.sp_executesql
                    @dsql;
            END;
        END;
    END; /*End memory*/

    /*Parse memory broker data*/
    IF @what_to_check IN ('all', 'memory')
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Parsing memory broker data', 0, 0) WITH NOWAIT;
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
            broker_id = w.x.value('(data[@name="id"]/value)[1]', 'integer'),
            pool_metadata_id = w.x.value('(data[@name="pool_metadata_id"]/value)[1]', 'integer'),
            delta_time = w.x.value('(data[@name="delta_time"]/value)[1]', 'bigint'),
            memory_ratio = w.x.value('(data[@name="memory_ratio"]/value)[1]', 'integer'),
            new_target = w.x.value('(data[@name="new_target"]/value)[1]', 'bigint'),
            overall = w.x.value('(data[@name="overall"]/value)[1]', 'bigint'),
            rate = w.x.value('(data[@name="rate"]/value)[1]', 'bigint'),
            currently_predicated = w.x.value('(data[@name="currently_predicated"]/value)[1]', 'bigint'),
            currently_allocated = w.x.value('(data[@name="currently_allocated"]/value)[1]', 'bigint'),
            previously_allocated = w.x.value('(data[@name="previously_allocated"]/value)[1]', 'bigint'),
            broker = w.x.value('(data[@name="broker"]/value)[1]', 'nvarchar(256)'),
            notification = w.x.value('(data[@name="notification"]/value)[1]', 'nvarchar(256)'),
            xml = w.x.query('.')
        INTO #memory_broker_info
        FROM #memory_broker AS mb
        CROSS APPLY mb.memory_broker.nodes('//event') AS w(x)
        WHERE (w.x.exist('(data[@name="notification"]/value[.= "RESOURCE_MEMPHYSICAL_LOW"])') = @warnings_only OR @warnings_only = 0)
        OPTION(RECOMPILE);

        IF @debug = 1
        BEGIN
            SELECT TOP (100)
                table_name = '#memory_broker_info, top 100 rows',
                x.*
            FROM #memory_broker_info AS x
            ORDER BY
                x.event_time DESC;
        END;

        /* Memory broker notifications logging section */
        IF NOT EXISTS
        (
            SELECT
                1/0
            FROM #memory_broker_info AS mbi
        )
        BEGIN
            IF @log_to_table = 0
            BEGIN
                /* No results logic, only return if not logging */
                SELECT
                    finding =
                        CASE
                            WHEN @what_to_check NOT IN ('all', 'memory')
                            THEN 'memory broker skipped, @what_to_check set to ' +
                                 @what_to_check
                            WHEN @what_to_check IN ('all', 'memory')
                            THEN 'no memory pressure events found between ' +
                                 RTRIM(CONVERT(date, @start_date)) +
                                 ' and ' +
                                 RTRIM(CONVERT(date, @end_date)) +
                                 ' with @warnings_only set to ' +
                                 RTRIM(@warnings_only) +
                                 '.'
                            ELSE 'no memory pressure events found!'
                        END

                RAISERROR('No memory broker data found', 0, 0) WITH NOWAIT;
            END;
        END;
        ELSE
        BEGIN
            /* Build the query for memory broker notifications */
            SET @dsql = N'
            SELECT
                ' + CASE
                        WHEN @log_to_table = 1
                        THEN N'mbi.event_time,
                mbi.broker_id,
                mbi.pool_metadata_id,
                mbi.delta_time,
                mbi.memory_ratio,
                mbi.new_target,
                mbi.overall,
                mbi.rate,
                mbi.currently_predicated,
                mbi.currently_allocated,
                mbi.previously_allocated,
                mbi.broker,
                mbi.notification'
                        ELSE N'finding = ''memory broker notifications'',
                mbi.event_time,
                mbi.broker_id,
                mbi.pool_metadata_id,
                mbi.delta_time,
                mbi.memory_ratio,
                new_target_gb =
                    REPLACE
                    (
                        CONVERT
                        (
                            nvarchar(30),
                            CONVERT
                            (
                                money,
                                mbi.new_target / 1024.0 / 1024.0
                            ),
                            1
                        ),
                    N''.00'',
                    N''''
                    ),
                overall_gb =
                    REPLACE
                    (
                        CONVERT
                        (
                            nvarchar(30),
                            CONVERT
                            (
                                money,
                                mbi.overall / 1024.0 / 1024.0
                            ),
                            1
                        ),
                    N''.00'',
                    N''''
                    ),
                mbi.rate,
                currently_predicated_gb =
                    REPLACE
                    (
                        CONVERT
                        (
                            nvarchar(30),
                            CONVERT
                            (
                                money,
                                mbi.currently_predicated / 1024.0 / 1024.0
                            ),
                            1
                        ),
                    N''.00'',
                    N''''
                    ),
                currently_allocated_gb =
                    REPLACE
                    (
                        CONVERT
                        (
                            nvarchar(30),
                            CONVERT
                            (
                                money,
                                mbi.currently_allocated / 1024.0 / 1024.0
                            ),
                            1
                        ),
                    N''.00'',
                    N''''
                    ),
                previously_allocated_gb =
                    REPLACE
                    (
                        CONVERT
                        (
                            nvarchar(30),
                            CONVERT
                            (
                                money,
                                mbi.previously_allocated / 1024.0 / 1024.0
                            ),
                            1
                        ),
                    N''.00'',
                    N''''
                    ),
                mbi.broker,
                mbi.notification'
                    END +
              N'
            FROM #memory_broker_info AS mbi';

            /* Add the WHERE clause only for table logging */
            IF @log_to_table = 1
            BEGIN
                /* Get max event_time for memory broker */
                SET @mdsql_execute =
                    REPLACE
                    (
                        REPLACE
                        (
                            @mdsql_template,
                            '{table_check}',
                            @log_table_memory_broker
                        ),
                        '{date_column}',
                        'event_time'
                    );

                IF @debug = 1
                BEGIN
                    PRINT @mdsql_execute;
                END;

                EXECUTE sys.sp_executesql
                    @mdsql_execute,
                  N'@max_event_time datetime2(7) OUTPUT',
                    @max_event_time OUTPUT;

                SET @dsql += N'
            WHERE mbi.event_time > @max_event_time';
            END;

            /* Add the ORDER BY clause */
            SET @dsql += N'
            ORDER BY
                mbi.event_time DESC
            OPTION(RECOMPILE);
            ';

            /* Handle table logging */
            IF @log_to_table = 1
            BEGIN
                SET @insert_sql = N'
            INSERT INTO '
                + @log_table_memory_broker + N'
            (
                event_time,
                broker_id,
                pool_metadata_id,
                delta_time,
                memory_ratio,
                new_target,
                overall,
                rate,
                currently_predicated,
                currently_allocated,
                previously_allocated,
                broker,
                notification
            )' +
                @dsql;

                IF @debug = 1
                BEGIN
                    PRINT @insert_sql;
                END;

                EXECUTE sys.sp_executesql
                    @insert_sql,
                  N'@max_event_time datetime2(7)',
                    @max_event_time;
            END;

            /* Execute the query for client results */
            IF @log_to_table = 0
            BEGIN
                IF @debug = 1
                BEGIN
                    PRINT @dsql;
                END;

                EXECUTE sys.sp_executesql
                    @dsql;
            END;
        END;
    END; /*End memory broker analysis*/

    /*Parse memory node OOM data*/
    IF @what_to_check IN ('all', 'memory')
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Parsing memory node OOM data', 0, 0) WITH NOWAIT;
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
            node_id = w.x.value('(data[@name="id"]/value)[1]', 'integer'),
            memory_node_id = w.x.value('(data[@name="memory_node_id"]/value)[1]', 'integer'),
            memory_utilization_pct = w.x.value('(data[@name="memory_utilization_pct"]/value)[1]', 'integer'),
            total_physical_memory_kb = w.x.value('(data[@name="total_physical_memory_kb"]/value)[1]', 'bigint'),
            available_physical_memory_kb = w.x.value('(data[@name="available_physical_memory_kb"]/value)[1]', 'bigint'),
            total_page_file_kb = w.x.value('(data[@name="total_page_file_kb"]/value)[1]', 'bigint'),
            available_page_file_kb = w.x.value('(data[@name="available_page_file_kb"]/value)[1]', 'bigint'),
            total_virtual_address_space_kb = w.x.value('(data[@name="total_virtual_address_space_kb"]/value)[1]', 'bigint'),
            available_virtual_address_space_kb = w.x.value('(data[@name="available_virtual_address_space_kb"]/value)[1]', 'bigint'),
            target_kb = w.x.value('(data[@name="target_kb"]/value)[1]', 'bigint'),
            reserved_kb = w.x.value('(data[@name="reserved_kb"]/value)[1]', 'bigint'),
            committed_kb = w.x.value('(data[@name="committed_kb"]/value)[1]', 'bigint'),
            shared_committed_kb = w.x.value('(data[@name="shared_committed_kb"]/value)[1]', 'bigint'),
            awe_kb = w.x.value('(data[@name="awe_kb"]/value)[1]', 'bigint'),
            pages_kb = w.x.value('(data[@name="pages_kb"]/value)[1]', 'bigint'),
            failure_type = w.x.value('(data[@name="failure"]/text)[1]', 'nvarchar(256)'),
            failure_value = w.x.value('(data[@name="failure"]/value)[1]', 'integer'),
            resources = w.x.value('(data[@name="resources"]/value)[1]', 'integer'),
            factor_text = w.x.value('(data[@name="factor"]/text)[1]', 'nvarchar(256)'),
            factor_value = w.x.value('(data[@name="factor"]/value)[1]', 'integer'),
            last_error = w.x.value('(data[@name="last_error"]/value)[1]', 'integer'),
            pool_metadata_id = w.x.value('(data[@name="pool_metadata_id"]/value)[1]', 'integer'),
            is_process_in_job = w.x.value('(data[@name="is_process_in_job"]/value)[1]', 'nvarchar(10)'),
            is_system_physical_memory_high = w.x.value('(data[@name="is_system_physical_memory_high"]/value)[1]', 'nvarchar(10)'),
            is_system_physical_memory_low = w.x.value('(data[@name="is_system_physical_memory_low"]/value)[1]', 'nvarchar(10)'),
            is_process_physical_memory_low = w.x.value('(data[@name="is_process_physical_memory_low"]/value)[1]', 'nvarchar(10)'),
            is_process_virtual_memory_low = w.x.value('(data[@name="is_process_virtual_memory_low"]/value)[1]', 'nvarchar(10)'),
            xml = w.x.query('.')
        INTO #memory_node_oom_info
        FROM #memory_node_oom AS mno
        CROSS APPLY mno.memory_node_oom.nodes('//event') AS w(x)
        OPTION(RECOMPILE);

        IF @debug = 1
        BEGIN
            SELECT TOP (100)
                table_name = '#memory_node_oom_info, top 100 rows',
                x.*
            FROM #memory_node_oom_info AS x
            ORDER BY
                x.event_time DESC;
        END;

        /* Memory node OOM events logging section */
        IF NOT EXISTS
        (
            SELECT
                1/0
            FROM #memory_node_oom_info AS mnoi
        )
        BEGIN
            IF @log_to_table = 0
            BEGIN
                /* No results logic, only return if not logging */
                SELECT
                    finding =
                        CASE
                            WHEN @what_to_check NOT IN ('all', 'memory')
                            THEN 'memory node OOM skipped, @what_to_check set to ' +
                                 @what_to_check
                            WHEN @what_to_check IN ('all', 'memory')
                            THEN 'no memory node OOM events found between ' +
                                 RTRIM(CONVERT(date, @start_date)) +
                                 ' and ' +
                                 RTRIM(CONVERT(date, @end_date)) +
                                 '.'
                            ELSE 'no memory node OOM events found!'
                        END

                RAISERROR('No memory oom data found', 0, 0) WITH NOWAIT;
            END;
        END;
        ELSE
        BEGIN
            /* Build the query for memory node OOM events */
            SET @dsql = N'
            SELECT
                ' + CASE
                        WHEN @log_to_table = 1
                        THEN N'mnoi.event_time,
                mnoi.node_id,
                mnoi.memory_node_id,
                mnoi.memory_utilization_pct,
                mnoi.total_physical_memory_kb,
                mnoi.available_physical_memory_kb,
                mnoi.total_page_file_kb,
                mnoi.available_page_file_kb,
                mnoi.total_virtual_address_space_kb,
                mnoi.available_virtual_address_space_kb,
                mnoi.target_kb,
                mnoi.reserved_kb,
                mnoi.committed_kb,
                mnoi.shared_committed_kb,
                mnoi.awe_kb,
                mnoi.pages_kb,
                mnoi.failure_type,
                mnoi.failure_value,
                mnoi.resources,
                mnoi.factor_text,
                mnoi.factor_value,
                mnoi.last_error,
                mnoi.pool_metadata_id,
                mnoi.is_process_in_job,
                mnoi.is_system_physical_memory_high,
                mnoi.is_system_physical_memory_low,
                mnoi.is_process_physical_memory_low,
                mnoi.is_process_virtual_memory_low'
                        ELSE N'finding = ''memory node OOM events'',
                mnoi.event_time,
                mnoi.node_id,
                mnoi.memory_node_id,
                mnoi.memory_utilization_pct,
                total_physical_memory_gb =
                    REPLACE
                    (
                        CONVERT
                        (
                            nvarchar(30),
                            CONVERT
                            (
                                money,
                                mnoi.total_physical_memory_kb / 1024.0 / 1024.0
                            ),
                            1
                        ),
                    N''.00'',
                    N''''
                    ),
                available_physical_memory_gb =
                    REPLACE
                    (
                        CONVERT
                        (
                            nvarchar(30),
                            CONVERT
                            (
                                money,
                                mnoi.available_physical_memory_kb / 1024.0 / 1024.0
                            ),
                            1
                        ),
                    N''.00'',
                    N''''
                    ),
                total_page_file_gb =
                    REPLACE
                    (
                        CONVERT
                        (
                            nvarchar(30),
                            CONVERT
                            (
                                money,
                                mnoi.total_page_file_kb / 1024.0 / 1024.0
                            ),
                            1
                        ),
                    N''.00'',
                    N''''
                    ),
                available_page_file_gb =
                    REPLACE
                    (
                        CONVERT
                        (
                            nvarchar(30),
                            CONVERT
                            (
                                money,
                                mnoi.available_page_file_kb / 1024.0 / 1024.0
                            ),
                            1
                        ),
                    N''.00'',
                    N''''
                    ),
                target_gb =
                    REPLACE
                    (
                        CONVERT
                        (
                            nvarchar(30),
                            CONVERT
                            (
                                money,
                                mnoi.target_kb / 1024.0 / 1024.0
                            ),
                            1
                        ),
                    N''.00'',
                    N''''
                    ),
                reserved_gb =
                    REPLACE
                    (
                        CONVERT
                        (
                            nvarchar(30),
                            CONVERT
                            (
                                money,
                                mnoi.reserved_kb / 1024.0 / 1024.0
                            ),
                            1
                        ),
                    N''.00'',
                    N''''
                    ),
                committed_gb =
                    REPLACE
                    (
                        CONVERT
                        (
                            nvarchar(30),
                            CONVERT
                            (
                                money,
                                mnoi.committed_kb / 1024.0 / 1024.0
                            ),
                            1
                        ),
                    N''.00'',
                    N''''
                    ),
                shared_committed_gb =
                    REPLACE
                    (
                        CONVERT
                        (
                            nvarchar(30),
                            CONVERT
                            (
                                money,
                                mnoi.shared_committed_kb / 1024.0 / 1024.0
                            ),
                            1
                        ),
                    N''.00'',
                    N''''
                    ),
                awe_gb =
                    REPLACE
                    (
                        CONVERT
                        (
                            nvarchar(30),
                            CONVERT
                            (
                                money,
                                mnoi.awe_kb / 1024.0 / 1024.0
                            ),
                            1
                        ),
                    N''.00'',
                    N''''
                    ),
                pages_gb =
                    REPLACE
                    (
                        CONVERT
                        (
                            nvarchar(30),
                            CONVERT
                            (
                                money,
                                mnoi.pages_kb / 1024.0 / 1024.0
                            ),
                            1
                        ),
                    N''.00'',
                    N''''
                    ),
                mnoi.failure_type,
                mnoi.failure_value,
                mnoi.resources,
                mnoi.factor_text,
                mnoi.factor_value,
                mnoi.last_error,
                mnoi.pool_metadata_id,
                mnoi.is_process_in_job,
                mnoi.is_system_physical_memory_high,
                mnoi.is_system_physical_memory_low,
                mnoi.is_process_physical_memory_low,
                mnoi.is_process_virtual_memory_low'
                    END +
              N'
            FROM #memory_node_oom_info AS mnoi';

            /* Add the WHERE clause only for table logging */
            IF @log_to_table = 1
            BEGIN
                /* Get max event_time for memory node OOM */
                SET @mdsql_execute =
                    REPLACE
                    (
                        REPLACE
                        (
                            @mdsql_template,
                            '{table_check}',
                            @log_table_memory_node_oom
                        ),
                        '{date_column}',
                        'event_time'
                    );

                IF @debug = 1
                BEGIN
                    PRINT @mdsql_execute;
                END;

                EXECUTE sys.sp_executesql
                    @mdsql_execute,
                  N'@max_event_time datetime2(7) OUTPUT',
                    @max_event_time OUTPUT;

                SET @dsql += N'
            WHERE mnoi.event_time > @max_event_time';
            END;

            /* Add the ORDER BY clause */
            SET @dsql += N'
            ORDER BY
                mnoi.event_time DESC
            OPTION(RECOMPILE);
            ';

            /* Handle table logging */
            IF @log_to_table = 1
            BEGIN
                SET @insert_sql = N'
            INSERT INTO
                ' + @log_table_memory_node_oom + N'
            (
                event_time,
                node_id,
                memory_node_id,
                memory_utilization_pct,
                total_physical_memory_kb,
                available_physical_memory_kb,
                total_page_file_kb,
                available_page_file_kb,
                total_virtual_address_space_kb,
                available_virtual_address_space_kb,
                target_kb,
                reserved_kb,
                committed_kb,
                shared_committed_kb,
                awe_kb,
                pages_kb,
                failure_type,
                failure_value,
                resources,
                factor_text,
                factor_value,
                last_error,
                pool_metadata_id,
                is_process_in_job,
                is_system_physical_memory_high,
                is_system_physical_memory_low,
                is_process_physical_memory_low,
                is_process_virtual_memory_low
            )' +
                @dsql;

                IF @debug = 1
                BEGIN
                    PRINT @insert_sql;
                END;

                EXECUTE sys.sp_executesql
                    @insert_sql,
                  N'@max_event_time datetime2(7)',
                    @max_event_time;
            END;

            /* Execute the query for client results */
            IF @log_to_table = 0
            BEGIN
                IF @debug = 1
                BEGIN
                    PRINT @dsql;
                END;

                EXECUTE sys.sp_executesql
                    @dsql;
            END;
        END;
    END; /*End memory node OOM analysis*/

    /*Grab health stuff*/
    IF @what_to_check IN ('all', 'system')
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Parsing system stuff', 0, 0) WITH NOWAIT;
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

        /* Overall system health logging section */
        IF NOT EXISTS
        (
            SELECT
                1/0
            FROM #health AS h
        )
        BEGIN
            IF @log_to_table = 0
            BEGIN
                /* No results logic, only return if not logging */
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
                        END

                RAISERROR('No system health data found', 0, 0) WITH NOWAIT;
            END;
        END;
        ELSE
        BEGIN
            /* Build the query */
            SET @dsql = N'
            SELECT
                ' + CASE
                        WHEN @log_to_table = 1
                        THEN N''
                        ELSE N'finding = ''overall system health'','
                    END +
              N'
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
            FROM #health AS h';

            /* Add the WHERE clause only for table logging */
            IF @log_to_table = 1
            BEGIN
                /* Get max event_time for system health */
                SET @mdsql_execute =
                    REPLACE
                    (
                        REPLACE
                        (
                            @mdsql_template,
                            '{table_check}',
                            @log_table_system_health
                        ),
                        '{date_column}',
                        'event_time'
                    );

                IF @debug = 1
                BEGIN
                    PRINT @mdsql_execute;
                END;

                EXECUTE sys.sp_executesql
                    @mdsql_execute,
                  N'@max_event_time datetime2(7) OUTPUT',
                    @max_event_time OUTPUT;

                SET @dsql = @dsql + N'
            WHERE h.event_time > @max_event_time';
            END;

            /* Add the ORDER BY clause */
            SET @dsql = @dsql + N'
            ORDER BY
                h.event_time DESC
            OPTION(RECOMPILE);
            ';

            /* Handle table logging */
            IF @log_to_table = 1
            BEGIN
                SET @insert_sql = N'
            INSERT INTO
                ' + @log_table_system_health + N'
            (
                event_time,
                state,
                spinlockBackoffs,
                sickSpinlockType,
                sickSpinlockTypeAfterAv,
                latchWarnings,
                isAccessViolationOccurred,
                writeAccessViolationCount,
                totalDumpRequests,
                intervalDumpRequests,
                nonYieldingTasksReported,
                pageFaults,
                systemCpuUtilization,
                sqlCpuUtilization,
                BadPagesDetected,
                BadPagesFixed
            )' +
                @dsql;

                IF @debug = 1
                BEGIN
                    PRINT @insert_sql;
                END;

                EXECUTE sys.sp_executesql
                    @insert_sql,
                  N'@max_event_time datetime2(7)',
                    @max_event_time;
            END;

            /* Execute the query for client results */
            IF @log_to_table = 0
            BEGIN
                IF @debug = 1
                BEGIN
                    PRINT @dsql;
                END;

                EXECUTE sys.sp_executesql
                    @dsql;
            END;
        END;
    END; /*End system*/

    /*Parse scheduler monitor data*/
    IF @what_to_check IN ('all', 'system', 'cpu')
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Parsing scheduler monitor data', 0, 0) WITH NOWAIT;
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
            scheduler_id = w.x.value('(data[@name="scheduler_id"]/value)[1]', 'integer'),
            cpu_id = w.x.value('(data[@name="cpu_id"]/value)[1]', 'integer'),
            status = w.x.value('(data[@name="status"]/text)[1]', 'nvarchar(256)'),
            is_online = w.x.value('(data[@name="is_online"]/value)[1]', 'bit'),
            is_runnable = w.x.value('(data[@name="is_runnable"]/value)[1]', 'bit'),
            is_running = w.x.value('(data[@name="is_running"]/value)[1]', 'bit'),
            non_yielding_time_ms = w.x.value('(data[@name="non_yielding_time"]/value)[1]', 'bigint'),
            thread_quantum_ms = w.x.value('(data[@name="thread_quantum"]/value)[1]', 'bigint'),
            xml = w.x.query('.')
        INTO #scheduler_issues
        FROM #scheduler_monitor AS sm
        CROSS APPLY sm.scheduler_monitor.nodes('//event') AS w(x)
        WHERE (w.x.exist('(data[@name="status"]/text[.= "WARNING"])') = @warnings_only OR @warnings_only = 0)
        OPTION(RECOMPILE);

        IF @debug = 1
        BEGIN
            SELECT TOP (100)
                table_name = '#scheduler_issues, top 100 rows',
                x.*
            FROM #scheduler_issues AS x
            ORDER BY
                x.event_time DESC;
        END;

        /* Scheduler monitor issues logging section */
        IF NOT EXISTS
        (
            SELECT
                1/0
            FROM #scheduler_issues AS si
        )
        BEGIN
            IF @log_to_table = 0
            BEGIN
                /* No results logic, only return if not logging */
                SELECT
                    finding =
                        CASE
                            WHEN @what_to_check NOT IN ('all', 'system', 'cpu')
                            THEN 'scheduler monitoring skipped, @what_to_check set to ' +
                                 @what_to_check
                            WHEN @what_to_check IN ('all', 'system', 'cpu')
                            THEN 'no scheduler issues found between ' +
                                 RTRIM(CONVERT(date, @start_date)) +
                                 ' and ' +
                                 RTRIM(CONVERT(date, @end_date)) +
                                 ' with @warnings_only set to ' +
                                 RTRIM(@warnings_only) +
                                 '.'
                            ELSE 'no scheduler issues found!'
                        END

                RAISERROR('No scheduler issues data found', 0, 0) WITH NOWAIT;
            END;
        END;
        ELSE
        BEGIN
            /* Build the query */
            SET @dsql = N'
            SELECT
                ' + CASE
                        WHEN @log_to_table = 1
                        THEN N''
                        ELSE N'finding = ''scheduler monitor issues'','
                    END +
              N'
                si.event_time,
                si.scheduler_id,
                si.cpu_id,
                si.status,
                si.is_online,
                si.is_runnable,
                si.is_running,
                non_yielding_time_ms =
                    REPLACE
                    (
                        CONVERT
                        (
                            nvarchar(30),
                            CONVERT
                            (
                                money,
                                si.non_yielding_time_ms
                            ),
                            1
                        ),
                    N''.00'',
                    N''''
                    ),
                thread_quantum_ms =
                    REPLACE
                    (
                        CONVERT
                        (
                            nvarchar(30),
                            CONVERT
                            (
                                money,
                                si.thread_quantum_ms
                            ),
                            1
                        ),
                    N''.00'',
                    N''''
                    )
            FROM #scheduler_issues AS si';

            /* Add the WHERE clause only for table logging */
            IF @log_to_table = 1
            BEGIN
                /* Get max event_time for scheduler issues */
                SET @mdsql_execute =
                    REPLACE
                    (
                        REPLACE
                        (
                            @mdsql_template,
                            '{table_check}',
                            @log_table_scheduler_issues
                        ),
                        '{date_column}',
                        'event_time'
                    );

                IF @debug = 1
                BEGIN
                    PRINT @mdsql_execute;
                END;

                EXECUTE sys.sp_executesql
                    @mdsql_execute,
                  N'@max_event_time datetime2(7) OUTPUT',
                    @max_event_time OUTPUT;

                SET @dsql = @dsql + N'
            WHERE si.event_time > @max_event_time';
            END;

            /* Add the ORDER BY clause */
            SET @dsql = @dsql + N'
            ORDER BY
                si.event_time DESC
            OPTION(RECOMPILE);
            ';

            /* Handle table logging */
            IF @log_to_table = 1
            BEGIN
                SET @insert_sql = N'
            INSERT INTO
                ' + @log_table_scheduler_issues + N'
            (
                event_time,
                scheduler_id,
                cpu_id,
                status,
                is_online,
                is_runnable,
                is_running,
                non_yielding_time_ms,
                thread_quantum_ms
            )' +
                @dsql;

                IF @debug = 1
                BEGIN
                    PRINT @insert_sql;
                END;

                EXECUTE sys.sp_executesql
                    @insert_sql,
                  N'@max_event_time datetime2(7)',
                    @max_event_time;
            END;

            /* Execute the query for client results */
            IF @log_to_table = 0
            BEGIN
                IF @debug = 1
                BEGIN
                    PRINT @dsql;
                END;

                EXECUTE sys.sp_executesql
                    @dsql;
            END;
        END;

    END; /*End scheduler monitor analysis*/

    /*Parse error_reported data*/
    IF @what_to_check IN ('all', 'system')
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Parsing error_reported data', 0, 0) WITH NOWAIT;
        END;

        INSERT
            #ignore_errors
        (
            error_number
        )
        VALUES
            (17830),
            (18056);

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
            error_number = w.x.value('(data[@name="error_number"]/value)[1]', 'integer'),
            severity = w.x.value('(data[@name="severity"]/value)[1]', 'integer'),
            state = w.x.value('(data[@name="state"]/value)[1]', 'integer'),
            message = w.x.value('(data[@name="message"]/value)[1]', 'nvarchar(max)'),
            database_name = DB_NAME(w.x.value('(data[@name="database_id"]/value)[1]', 'integer')),
            database_id = w.x.value('(data[@name="database_id"]/value)[1]', 'integer'),
            xml = w.x.query('.')
        INTO #error_info
        FROM #error_reported AS er
        CROSS APPLY er.error_reported.nodes('//event') AS w(x)
        WHERE w.x.exist('(data[@name="severity"]/value)[. >= 16]') = 1
        AND (@warnings_only = 0 OR w.x.exist('(data[@name="severity"]/value)[. >= 19]') = 1)
        AND NOT EXISTS
        (
            SELECT
                1/0
            FROM #ignore_errors AS ie
            WHERE w.x.value('(data[@name="error_number"]/value)[1]', 'integer') = ie.error_number
        )
        OPTION(RECOMPILE);

        IF @debug = 1
        BEGIN
            SELECT TOP (100)
                table_name = '#error_info, top 100 rows',
                x.*
            FROM #error_info AS x
            ORDER BY
                x.event_time DESC;
        END;

        /* Severe errors reported logging section */
        IF NOT EXISTS
        (
            SELECT
                1/0
            FROM #error_info AS ei
        )
        BEGIN
            IF @log_to_table = 0
            BEGIN
                /* No results logic, only return if not logging */
                SELECT
                    finding =
                        CASE
                            WHEN @what_to_check NOT IN ('all', 'system')
                            THEN 'error reporting skipped, @what_to_check set to ' +
                                 @what_to_check
                            WHEN @what_to_check IN ('all', 'system')
                            THEN 'no severe errors found between ' +
                                 RTRIM(CONVERT(date, @start_date)) +
                                 ' and ' +
                                 RTRIM(CONVERT(date, @end_date)) +
                                 ' with @warnings_only set to ' +
                                 RTRIM(@warnings_only) +
                                 '.'
                            ELSE 'no severe errors found!'
                        END

                RAISERROR('No error data found', 0, 0) WITH NOWAIT;
            END;
        END;
        ELSE
        BEGIN
            /* Build the query */
            SET @dsql = N'
            SELECT
                ' + CASE
                        WHEN @log_to_table = 1
                        THEN N''
                        ELSE N'finding = ''severe errors reported'','
                    END +
              N'
                ei.event_time,
                ei.error_number,
                ei.severity,
                ei.state,
                ei.message,
                ei.database_name,
                ei.database_id
            FROM #error_info AS ei';

            /* Add the WHERE clause only for table logging */
            IF @log_to_table = 1
            BEGIN
                /* Get max event_time for severe errors */
                SET @mdsql_execute =
                    REPLACE
                    (
                        REPLACE
                        (
                            @mdsql_template,
                            '{table_check}',
                            @log_table_severe_errors
                        ),
                        '{date_column}',
                        'event_time'
                    );

                IF @debug = 1
                BEGIN
                    PRINT @mdsql_execute;
                END;

                EXECUTE sys.sp_executesql
                    @mdsql_execute,
                  N'@max_event_time datetime2(7) OUTPUT',
                    @max_event_time OUTPUT;

                SET @dsql = @dsql + N'
            WHERE ei.event_time > @max_event_time';
            END;

            /* Add the ORDER BY clause */
            SET @dsql = @dsql + N'
            ORDER BY
                ei.event_time DESC,
                ei.severity DESC
            OPTION(RECOMPILE);
            ';

            /* Handle table logging */
            IF @log_to_table = 1
            BEGIN
                SET @insert_sql = N'
            INSERT INTO
                ' + @log_table_severe_errors + N'
            (
                event_time,
                error_number,
                severity,
                state,
                message,
                database_name,
                database_id
            )' +
                @dsql;

                IF @debug = 1
                BEGIN
                    PRINT @insert_sql;
                END;

                EXECUTE sys.sp_executesql
                    @insert_sql,
                  N'@max_event_time datetime2(7)',
                    @max_event_time;
            END;

            /* Execute the query for client results */
            IF @log_to_table = 0
            BEGIN
                IF @debug = 1
                BEGIN
                    PRINT @dsql;
                END;

                EXECUTE sys.sp_executesql
                    @dsql;
            END;

            /* For ignored errors, only display to client */
            IF  @log_to_table = 0
            AND @debug = 1
            BEGIN
                SELECT
                    error_numbers_ignored =
                        N'Error Number Ignored: ' +
                        CONVERT(nvarchar(100), ie.error_number)
                FROM #ignore_errors AS ie;
            END;
        END;
    END; /*End error_reported analysis*/

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
    AND @log_to_table = 0
    )
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Parsing locking stuff', 0, 0) WITH NOWAIT;
        END;

        INSERT
            #blocking_xml
        WITH
            (TABLOCK)
        (
            event_time,
            human_events_xml
        )
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
            RAISERROR('Parsing blocked queries', 0, 0) WITH NOWAIT;
        END;

        SELECT
            bx.event_time,
            currentdbname = bd.value('(process/@currentdbname)[1]', 'nvarchar(128)'),
            spid = bd.value('(process/@spid)[1]', 'integer'),
            ecid = bd.value('(process/@ecid)[1]', 'integer'),
            query_text_pre = bd.value('(process/inputbuf/text())[1]', 'nvarchar(max)'),
            wait_time = bd.value('(process/@waittime)[1]', 'bigint'),
            lastbatchstarted = bd.value('(process/@lastbatchstarted)[1]', 'datetime2'),
            lastbatchcompleted = bd.value('(process/@lastbatchcompleted)[1]', 'datetime2'),
            wait_resource = bd.value('(process/@waitresource)[1]', 'nvarchar(100)'),
            status = bd.value('(process/@status)[1]', 'nvarchar(10)'),
            priority = bd.value('(process/@priority)[1]', 'integer'),
            transaction_count = bd.value('(process/@trancount)[1]', 'integer'),
            client_app = bd.value('(process/@clientapp)[1]', 'nvarchar(256)'),
            host_name = bd.value('(process/@hostname)[1]', 'nvarchar(256)'),
            login_name = bd.value('(process/@loginname)[1]', 'nvarchar(256)'),
            isolation_level = bd.value('(process/@isolationlevel)[1]', 'nvarchar(50)'),
            log_used = bd.value('(process/@logused)[1]', 'bigint'),
            clientoption1 = bd.value('(process/@clientoption1)[1]', 'bigint'),
            clientoption2 = bd.value('(process/@clientoption2)[1]', 'bigint'),
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
            RAISERROR('Adding query_text to #blocked', 0, 0) WITH NOWAIT;
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
            RAISERROR('Parsing blocking queries', 0, 0) WITH NOWAIT;
        END;

        SELECT
            bx.event_time,
            currentdbname = bg.value('(process/@currentdbname)[1]', 'nvarchar(128)'),
            spid = bg.value('(process/@spid)[1]', 'integer'),
            ecid = bg.value('(process/@ecid)[1]', 'integer'),
            query_text_pre = bg.value('(process/inputbuf/text())[1]', 'nvarchar(max)'),
            wait_time = bg.value('(process/@waittime)[1]', 'bigint'),
            last_transaction_started = bg.value('(process/@lastbatchstarted)[1]', 'datetime2'),
            last_transaction_completed = bg.value('(process/@lastbatchcompleted)[1]', 'datetime2'),
            wait_resource = bg.value('(process/@waitresource)[1]', 'nvarchar(100)'),
            status = bg.value('(process/@status)[1]', 'nvarchar(10)'),
            priority = bg.value('(process/@priority)[1]', 'integer'),
            transaction_count = bg.value('(process/@trancount)[1]', 'integer'),
            client_app = bg.value('(process/@clientapp)[1]', 'nvarchar(256)'),
            host_name = bg.value('(process/@hostname)[1]', 'nvarchar(256)'),
            login_name = bg.value('(process/@loginname)[1]', 'nvarchar(256)'),
            isolation_level = bg.value('(process/@isolationlevel)[1]', 'nvarchar(50)'),
            log_used = bg.value('(process/@logused)[1]', 'bigint'),
            clientoption1 = bg.value('(process/@clientoption1)[1]', 'bigint'),
            clientoption2 = bg.value('(process/@clientoption2)[1]', 'bigint'),
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
            RAISERROR('Adding query_text to #blocking', 0, 0) WITH NOWAIT;
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
            RAISERROR('Inserting to #blocks', 0, 0) WITH NOWAIT;
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

        IF EXISTS
        (
            SELECT
                1/0
            FROM #blocks AS b
        )
        BEGIN
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
        END;
        ELSE
        BEGIN
            SELECT
                finding = CASE
                    WHEN @what_to_check NOT IN ('all', 'locking')
                    THEN 'blocking skipped, @what_to_check set to ' + @what_to_check
                    WHEN @skip_locks = 1
                    THEN 'blocking skipped, @skip_locks set to 1'
                    WHEN @what_to_check IN ('all', 'locking')
                    THEN 'no blocking found between ' +
                         RTRIM(CONVERT(date, @start_date)) +
                         ' and ' +
                         RTRIM(CONVERT(date, @end_date)) +
                         ' with @warnings_only set to ' +
                         RTRIM(@warnings_only)
                    ELSE 'no blocking found!'
                END;
        END;

        /*Grab available plans from the cache*/
        IF @debug = 1
        BEGIN
            RAISERROR('Inserting to #available_plans (blocking)', 0, 0) WITH NOWAIT;
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
                    TRY_CAST(b.query_text AS nvarchar(max)),
                sql_handle =
                    CONVERT(varbinary(64), n.c.value('@sqlhandle', 'varchar(130)'), 1),
                stmtstart =
                    ISNULL(n.c.value('@stmtstart', 'integer'), 0),
                stmtend =
                    ISNULL(n.c.value('@stmtend', 'integer'), -1)
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
                    TRY_CAST(b.query_text AS nvarchar(max)),
                sql_handle =
                    CONVERT(varbinary(64), n.c.value('@sqlhandle', 'varchar(130)'), 1),
                stmtstart =
                    ISNULL(n.c.value('@stmtstart', 'integer'), 0),
                stmtend =
                    ISNULL(n.c.value('@stmtend', 'integer'), -1)
            FROM #blocks AS b
            CROSS APPLY b.blocked_process_report.nodes('/blocking-process/process/executionStack/frame[not(@sqlhandle = "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")]') AS n(c)
            WHERE (b.currentdbname = @database_name
                    OR @database_name IS NULL)
        ) AS b
        OPTION(RECOMPILE);

        IF @debug = 1
        BEGIN
            RAISERROR('Inserting to #deadlocks', 0, 0) WITH NOWAIT;
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
            RAISERROR('Inserting to #deadlocks_parsed', 0, 0) WITH NOWAIT;
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
            RAISERROR('Adding query_text to #deadlocks_parsed', 0, 0) WITH NOWAIT;
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
            RAISERROR('Returning deadlocks', 0, 0) WITH NOWAIT;
        END;

        IF EXISTS
        (
            SELECT
                1/0
            FROM #deadlocks_parsed AS dp
        )
        BEGIN
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
        END;
        ELSE
        BEGIN
            SELECT
                finding = CASE
                    WHEN @what_to_check NOT IN ('all', 'locking')
                    THEN 'deadlocks skipped, @what_to_check set to ' + @what_to_check
                    WHEN @skip_locks = 1
                    THEN 'deadlocks skipped, @skip_locks set to 1'
                    WHEN @what_to_check IN ('all', 'locking')
                    THEN 'no deadlocks found between ' +
                         RTRIM(CONVERT(date, @start_date)) +
                         ' and ' +
                         RTRIM(CONVERT(date, @end_date))
                    ELSE 'no deadlocks found!'
                END;
        END;

        IF @debug = 1
        BEGIN
            RAISERROR('Inserting #available_plans (deadlocks)', 0, 0) WITH NOWAIT;
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
            RAISERROR('Inserting #dm_exec_query_stats_sh', 0, 0) WITH NOWAIT;
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
            RAISERROR('Indexing #dm_exec_query_stats_sh', 0, 0) WITH NOWAIT;
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
            RAISERROR('Inserting #all_available_plans (deadlocks)', 0, 0) WITH NOWAIT;
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

        IF EXISTS
        (
            SELECT
                1/0
            FROM #all_avalable_plans AS ap
            WHERE ap.finding = 'available plans for blocking'
        )
        BEGIN
            SELECT
                aap.*
            FROM #all_avalable_plans AS aap
            WHERE aap.finding = 'available plans for blocking'
            ORDER BY
                aap.avg_worker_time_ms DESC
            OPTION(RECOMPILE);
        END;
        ELSE
        BEGIN
            /* Only show this message if we found blocking but no plans */
            IF EXISTS
            (
                SELECT
                    1/0
                FROM #blocks AS b
            )
            BEGIN
                SELECT
                    finding = 'no cached plans found for blocking queries';
            END;
        END;

        IF EXISTS
        (
            SELECT
                1/0
            FROM #all_avalable_plans AS ap
            WHERE ap.finding = 'available plans for deadlocks'
        )
        BEGIN
            SELECT
                aap.*
            FROM #all_avalable_plans AS aap
            WHERE aap.finding = 'available plans for deadlocks'
            ORDER BY
                aap.avg_worker_time_ms DESC
            OPTION(RECOMPILE);
        END;
        ELSE
        BEGIN
            /* Only show this message if we found deadlocks but no plans */
            IF EXISTS
            (
                SELECT
                    1/0
                FROM #deadlocks_parsed AS dp
            )
            BEGIN
                SELECT
                    finding = 'no cached plans found for deadlock queries';
            END;
        END;
    END; /*End locks*/
END; /*Final End*/
GO
