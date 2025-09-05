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

Copyright 2025 Darling Data, LLC
https://www.erikdarling.com/

For usage and licensing details, run:
EXECUTE sp_PressureDetector
    @help = 1;

For working through errors:
EXECUTE sp_PressureDetector
    @debug = 1;

For support, head over to GitHub:
https://code.erikdarling.com

*/


IF OBJECT_ID(N'dbo.sp_PressureDetector', N'P') IS NULL
    EXECUTE (N'CREATE PROCEDURE dbo.sp_PressureDetector AS RETURN 138;');
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
    @log_to_table bit = 0, /*enable logging to permanent tables*/
    @log_database_name sysname = NULL, /*database to store logging tables*/
    @log_schema_name sysname = NULL, /*schema to store logging tables*/
    @log_table_name_prefix sysname = 'PressureDetector', /*prefix for all logging tables*/
    @log_retention_days integer = 30, /*Number of days to keep logs, 0 = keep indefinitely*/
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
    @version = '5.6',
    @version_date = '20250601';


IF @help = 1
BEGIN
    /*
    Introduction
    */
    SELECT
        introduction =
           'hi, i''m sp_PressureDetector!' UNION ALL
    SELECT 'you got me from https://code.erikdarling.com' UNION ALL
    SELECT 'i''m a lightweight tool for monitoring cpu and memory pressure' UNION ALL
    SELECT 'i''ll tell you: ' UNION ALL
    SELECT ' * what''s currently consuming memory on your server' UNION ALL
    SELECT ' * wait stats relevant to cpu, memory, and disk pressure, along with query performance' UNION ALL
    SELECT ' * how many worker threads and how much memory you have available' UNION ALL
    SELECT ' * running queries that are using cpu and memory' UNION ALL
    SELECT 'from https://erikdarling.com';

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
                WHEN N'@log_to_table' THEN N'enable logging to permanent tables instead of returning results'
                WHEN N'@log_database_name' THEN N'database to store logging tables'
                WHEN N'@log_schema_name' THEN N'schema to store logging tables'
                WHEN N'@log_table_name_prefix' THEN N'prefix for all logging tables'
                WHEN N'@log_retention_days' THEN N'how many days of data to retain'
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
                WHEN N'@log_to_table' THEN N'0 or 1'
                WHEN N'@log_database_name' THEN N'any valid database name'
                WHEN N'@log_schema_name' THEN N'any valid schema name'
                WHEN N'@log_table_name_prefix' THEN N'any valid identifier'
                WHEN N'@log_retention_days' THEN N'a positive integer'
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
                WHEN N'@log_to_table' THEN N'0'
                WHEN N'@log_database_name' THEN N'NULL (current database)'
                WHEN N'@log_schema_name' THEN N'NULL (dbo)'
                WHEN N'@log_table_name_prefix' THEN N'PressureDetector'
                WHEN N'@log_retention_days' THEN N'30'
                WHEN N'@help' THEN N'0'
                WHEN N'@debug' THEN N'0'
                WHEN N'@version' THEN N'none; OUTPUT'
                WHEN N'@version_date' THEN N'none; OUTPUT'
            END
    FROM sys.all_parameters AS ap
    JOIN sys.all_objects AS o
      ON ap.object_id = o.object_id
    JOIN sys.types AS t
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

    IF  @log_to_table = 1
    AND @cpu_utilization_threshold > 0
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Setting @cpu_utilization_threshold to 0 to capture all CPU utilization data when logging to tables', 0, 1) WITH NOWAIT;
        END;
        SELECT
            @cpu_utilization_threshold = 0;
    END;

    IF  @log_to_table = 1
    AND @sample_seconds <> 0
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Logging to tables is not compatible with @sample_seconds. Using @sample_seconds = 0', 0, 1) WITH NOWAIT;
        END;
        SELECT
            @sample_seconds = 0;
    END;

    IF   @log_to_table = 1
    AND @what_to_check <> 'all'
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('@what_to_check was set to %s, setting to all when logging to tables', 0, 1, @what_to_check) WITH NOWAIT;
        END;
        SELECT
            @what_to_check = 'all';
    END;

    IF   @log_to_table = 1
    AND
    (
           @skip_queries = 1
        OR @skip_plan_xml = 1
        OR @skip_waits = 1
        OR @skip_perfmon = 1
    )
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('reverting skip options for table logging', 0, 1, @what_to_check) WITH NOWAIT;
        END;
        SELECT
            @skip_queries = 0,
            @skip_plan_xml = 0,
            @skip_waits = 0,
            @skip_perfmon = 0;
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
        @pool_sql nvarchar(max) = N'',
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
        @mem_sql nvarchar(max) = N'',
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
        @cpu_sql nvarchar(max) = N'',
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
        @reserved_worker_count nvarchar(max) = N'
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

SELECT
    @reserved_worker_count_out =
        SUM(deqmg.reserved_worker_count)
FROM sys.dm_exec_query_memory_grants AS deqmg
OPTION(MAXDOP 1, RECOMPILE);
            ',
        @cpu_details nvarchar(max) = N'',
        @cpu_details_output xml = N'',
        @cpu_details_columns nvarchar(max) = N'',
        @cpu_details_select nvarchar(max) = N'
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

SELECT
    @cpu_details_output =
        (
            SELECT
                offline_cpus =
                    (SELECT COUNT_BIG(*) FROM sys.dm_os_schedulers dos WHERE dos.is_online = 0),
',
        @cpu_details_from nvarchar(max) = N'
            FROM sys.dm_os_sys_info AS osi
            FOR XML
                PATH(''cpu_details''),
                TYPE
        )
OPTION(MAXDOP 1, RECOMPILE);',
        @database_size_out nvarchar(max) = N'',
        @database_size_out_gb nvarchar(10) = '0',
        @total_physical_memory_gb bigint,
        @cpu_utilization xml = N'',
        @low_memory xml = N'',
        @disk_check nvarchar(max) = N'',
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
        (
            SELECT TOP (1)
                SUBSTRING
                (
                    dopc.object_name,
                    1,
                    CHARINDEX(N':', dopc.object_name)
                )
            FROM sys.dm_os_performance_counters AS dopc
        ) +
        N'%',
        @memory_grant_cap xml,
        @cache_xml xml,
        @cache_sql nvarchar(max) = N'',
        @resource_semaphores nvarchar(max) = N'',
        @cpu_threads nvarchar(max) = N'',
        /*Log to table stuff*/
        @log_table_waits sysname,
        @log_table_file_metrics sysname,
        @log_table_perfmon sysname,
        @log_table_memory sysname,
        @log_table_cpu sysname,
        @log_table_memory_consumers sysname,
        @log_table_memory_queries sysname,
        @log_table_cpu_queries sysname,
        @log_table_cpu_events sysname,
        @cleanup_date datetime2(7),
        @max_sample_time datetime,
        @check_sql nvarchar(max) = N'',
        @create_sql nvarchar(max) = N'',
        @insert_sql nvarchar(max) = N'',
        @delete_sql nvarchar(max) = N'',
        @log_database_schema nvarchar(1024);

    /* Validate logging parameters */
    IF @log_to_table = 1
    BEGIN

        SELECT
            /* Default database name to current database if not specified */
            @log_database_name = ISNULL(@log_database_name, DB_NAME()),
            /* Default schema name to dbo if not specified */
            @log_schema_name = ISNULL(@log_schema_name, N'dbo');

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

        SELECT
            @log_database_schema =
                QUOTENAME(@log_database_name) +
                N'.' +
                QUOTENAME(@log_schema_name) +
                N'.';

        /* Generate fully qualified table names */
        SELECT
            @log_table_waits =
                @log_database_schema +
                QUOTENAME(@log_table_name_prefix + N'_Waits'),
            @log_table_file_metrics =
                @log_database_schema +
                QUOTENAME(@log_table_name_prefix + N'_FileMetrics'),
            @log_table_perfmon =
                @log_database_schema +
                QUOTENAME(@log_table_name_prefix + N'_Perfmon'),
            @log_table_memory =
                @log_database_schema +
                QUOTENAME(@log_table_name_prefix + N'_Memory'),
            @log_table_cpu =
                @log_database_schema +
                QUOTENAME(@log_table_name_prefix + N'_CPU'),
            @log_table_memory_consumers =
                @log_database_schema +
                QUOTENAME(@log_table_name_prefix + N'_MemoryConsumers'),
            @log_table_memory_queries =
                @log_database_schema +
                QUOTENAME(@log_table_name_prefix + N'_MemoryQueries'),
            @log_table_cpu_queries =
                @log_database_schema +
                QUOTENAME(@log_table_name_prefix + N'_CPUQueries'),
            @log_table_cpu_events =
                @log_database_schema +
                QUOTENAME(@log_table_name_prefix + N'_CPUEvents');

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
                WHERE t.name = @table_name + N''_Waits''
                AND   s.name = @schema_name
            )
            BEGIN
                CREATE TABLE ' + @log_table_waits + N'
                (
                    id bigint IDENTITY,
                    collection_time datetime2(7) NOT NULL DEFAULT SYSDATETIME(),
                    server_hours_uptime integer NULL,
                    server_hours_cpu_time decimal(38,2) NULL,
                    wait_type nvarchar(60) NOT NULL,
                    description nvarchar(60) NULL,
                    hours_wait_time decimal(38,2) NULL,
                    avg_ms_per_wait decimal(38,2) NULL,
                    percent_signal_waits decimal(38,2) NULL,
                    waiting_tasks_count bigint NULL,
                    PRIMARY KEY CLUSTERED (collection_time, id)
                );
                IF @debug = 1 BEGIN RAISERROR(''Created table %s for wait stats logging.'', 0, 1, ''' + @log_table_waits + N''') WITH NOWAIT; END;
            END';

        EXECUTE sys.sp_executesql
            @create_sql,
          N'@schema_name sysname,
            @table_name sysname,
            @debug bit',
            @log_schema_name,
            @log_table_name_prefix,
            @debug;

        SET @create_sql = N'
            IF NOT EXISTS
            (
                SELECT
                    1/0
                FROM ' + QUOTENAME(@log_database_name) + N'.sys.tables AS t
                JOIN ' + QUOTENAME(@log_database_name) + N'.sys.schemas AS s
                  ON t.schema_id = s.schema_id
                WHERE t.name = @table_name + N''_FileMetrics''
                AND   s.name = @schema_name
            )
            BEGIN
                CREATE TABLE ' + @log_table_file_metrics + N'
                (
                    id bigint IDENTITY,
                    collection_time datetime2(7) NOT NULL DEFAULT SYSDATETIME(),
                    server_hours_uptime integer NULL,
                    drive nvarchar(255) NOT NULL,
                    database_name nvarchar(128) NOT NULL,
                    database_file_details nvarchar(1000) NULL,
                    file_size_gb decimal(38,2) NULL,
                    total_gb_read decimal(38,2) NULL,
                    total_mb_read decimal(38,2) NULL,
                    total_read_count bigint NULL,
                    avg_read_stall_ms decimal(38,2) NULL,
                    total_gb_written decimal(38,2) NULL,
                    total_mb_written decimal(38,2) NULL,
                    total_write_count bigint NULL,
                    avg_write_stall_ms decimal(38,2) NULL,
                    io_stall_read_ms bigint NULL,
                    io_stall_write_ms bigint NULL,
                    PRIMARY KEY CLUSTERED (collection_time, id)
                );
                IF @debug = 1 BEGIN RAISERROR(''Created table %s for file metrics logging.'', 0, 1, ''' + @log_table_file_metrics + N''') WITH NOWAIT; END;
            END';

        EXECUTE sys.sp_executesql
            @create_sql,
          N'@schema_name sysname,
            @table_name sysname,
            @debug bit',
            @log_schema_name,
            @log_table_name_prefix,
            @debug;

        SET @create_sql = N'
            IF NOT EXISTS
            (
                SELECT
                    1/0
                FROM ' + QUOTENAME(@log_database_name) + N'.sys.tables AS t
                JOIN ' + QUOTENAME(@log_database_name) + N'.sys.schemas AS s
                  ON t.schema_id = s.schema_id
                WHERE t.name = @table_name + N''_Perfmon''
                AND   s.name = @schema_name
            )
            BEGIN
                CREATE TABLE ' + @log_table_perfmon + N'
                (
                    id bigint IDENTITY,
                    collection_time datetime2(7) NOT NULL DEFAULT SYSDATETIME(),
                    object_name sysname NOT NULL,
                    counter_name sysname NOT NULL,
                    counter_name_clean sysname NULL,
                    instance_name sysname NOT NULL,
                    cntr_value bigint NULL,
                    cntr_type bigint NULL,
                    PRIMARY KEY CLUSTERED (collection_time, id)
                );
                IF @debug = 1 BEGIN RAISERROR(''Created table %s for perfmon logging.'', 0, 1, ''' + @log_table_perfmon + N''') WITH NOWAIT; END;
            END';

        EXECUTE sys.sp_executesql
            @create_sql,
          N'@schema_name sysname,
            @table_name sysname,
            @debug bit',
            @log_schema_name,
            @log_table_name_prefix,
            @debug;

        SET @create_sql = N'
            IF NOT EXISTS
            (
                SELECT
                    1/0
                FROM ' + QUOTENAME(@log_database_name) + N'.sys.tables AS t
                JOIN ' + QUOTENAME(@log_database_name) + N'.sys.schemas AS s
                  ON t.schema_id = s.schema_id
                WHERE t.name = @table_name + N''_Memory''
                AND   s.name = @schema_name
            )
            BEGIN
                CREATE TABLE ' + @log_table_memory + N'
                (
                    id bigint IDENTITY,
                    collection_time datetime2(7) NOT NULL DEFAULT SYSDATETIME(),
                    resource_semaphore_id integer NOT NULL,
                    total_database_size_gb varchar(20) NULL,
                    total_physical_memory_gb bigint NULL,
                    max_server_memory_gb bigint NULL,
                    max_memory_grant_cap xml NULL,
                    memory_model nvarchar(128) NULL,
                    target_memory_gb decimal(38,2) NULL,
                    max_target_memory_gb decimal(38,2) NULL,
                    total_memory_gb decimal(38,2) NULL,
                    available_memory_gb decimal(38,2) NULL,
                    granted_memory_gb decimal(38,2) NULL,
                    used_memory_gb decimal(38,2) NULL,
                    grantee_count integer NULL,
                    waiter_count integer NULL,
                    timeout_error_count integer NULL,
                    forced_grant_count integer NULL,
                    total_reduced_memory_grant_count bigint NULL,
                    pool_id integer NULL,
                    PRIMARY KEY CLUSTERED (collection_time, id)
                );
                IF @debug = 1 BEGIN RAISERROR(''Created table %s for memory logging.'', 0, 1, ''' + @log_table_memory + N''') WITH NOWAIT; END;
            END';

        EXECUTE sys.sp_executesql
            @create_sql,
          N'@schema_name sysname,
            @table_name sysname,
            @debug bit',
            @log_schema_name,
            @log_table_name_prefix,
            @debug;

        SET @create_sql = N'
            IF NOT EXISTS
            (
                SELECT
                    1/0
                FROM ' + QUOTENAME(@log_database_name) + N'.sys.tables AS t
                JOIN ' + QUOTENAME(@log_database_name) + N'.sys.schemas AS s
                  ON t.schema_id = s.schema_id
                WHERE t.name = @table_name + N''_CPU''
                AND   s.name = @schema_name
            )
            BEGIN
                CREATE TABLE ' + @log_table_cpu + N'
                (
                    id bigint IDENTITY,
                    collection_time datetime2(7) NOT NULL DEFAULT SYSDATETIME(),
                    total_threads integer NULL,
                    used_threads integer NULL,
                    available_threads integer NULL,
                    reserved_worker_count varchar(10) NULL,
                    threads_waiting_for_cpu integer NULL,
                    requests_waiting_for_threads integer NULL,
                    current_workers integer NULL,
                    total_active_request_count integer NULL,
                    total_queued_request_count integer NULL,
                    total_blocked_task_count integer NULL,
                    total_active_parallel_thread_count integer NULL,
                    avg_runnable_tasks_count float NULL,
                    high_runnable_percent varchar(100) NULL,
                    cpu_details_output xml NULL,
                    cpu_utilization_over_threshold xml NULL,
                    PRIMARY KEY CLUSTERED (collection_time, id)
                );
                IF @debug = 1 BEGIN RAISERROR(''Created table %s for CPU logging.'', 0, 1, ''' + @log_table_cpu + N''') WITH NOWAIT; END;
            END';

        EXECUTE sys.sp_executesql
            @create_sql,
          N'@schema_name sysname,
            @table_name sysname,
            @debug bit',
            @log_schema_name,
            @log_table_name_prefix,
            @debug;

        /* Memory Consumers table */
        SET @create_sql = N'
            IF NOT EXISTS
            (
                SELECT
                    1/0
                FROM ' + QUOTENAME(@log_database_name) + N'.sys.tables AS t
                JOIN ' + QUOTENAME(@log_database_name) + N'.sys.schemas AS s
                  ON t.schema_id = s.schema_id
                WHERE t.name = @table_name + N''_MemoryConsumers''
                AND   s.name = @schema_name
            )
            BEGIN
                CREATE TABLE ' + @log_table_memory_consumers + N'
                (
                    id bigint IDENTITY,
                    collection_time datetime2(7) NOT NULL DEFAULT SYSDATETIME(),
                    memory_source nvarchar(128) NOT NULL,
                    memory_consumer nvarchar(128) NOT NULL,
                    memory_consumed_gb decimal(38,2) NULL,
                    PRIMARY KEY CLUSTERED (collection_time, id)
                );
                IF @debug = 1 BEGIN RAISERROR(''Created table %s for memory consumers logging.'', 0, 1, ''' + @log_database_schema + QUOTENAME(@log_table_name_prefix + N'_MemoryConsumers') + N''') WITH NOWAIT; END;
            END';

        EXECUTE sys.sp_executesql
            @create_sql,
          N'@schema_name sysname,
            @table_name sysname,
            @debug bit',
            @log_schema_name,
            @log_table_name_prefix,
            @debug;

        /* Memory Query Grants table */
        SET @create_sql = N'
            IF NOT EXISTS
            (
                SELECT
                    1/0
                FROM ' + QUOTENAME(@log_database_name) + N'.sys.tables AS t
                JOIN ' + QUOTENAME(@log_database_name) + N'.sys.schemas AS s
                  ON t.schema_id = s.schema_id
                WHERE t.name = @table_name + N''_MemoryQueries''
                AND   s.name = @schema_name
            )
            BEGIN
                CREATE TABLE ' + @log_table_memory_queries + N'
                (
                    id bigint IDENTITY,
                    collection_time datetime2(7) NOT NULL DEFAULT SYSDATETIME(),
                    session_id integer NOT NULL,
                    database_name nvarchar(128) NULL,
                    duration varchar(30) NULL,
                    request_time datetime NULL,
                    grant_time datetime NULL,
                    wait_time_seconds decimal(38,2) NULL,
                    requested_memory_gb decimal(38,2) NULL,
                    granted_memory_gb decimal(38,2) NULL,
                    used_memory_gb decimal(38,2) NULL,
                    max_used_memory_gb decimal(38,2) NULL,
                    ideal_memory_gb decimal(38,2) NULL,
                    required_memory_gb decimal(38,2) NULL,
                    queue_id integer NULL,
                    wait_order integer NULL,
                    is_next_candidate bit NULL,
                    wait_type nvarchar(60) NULL,
                    wait_duration_seconds decimal(38,2) NULL,
                    dop integer NULL,
                    reserved_worker_count integer NULL,
                    used_worker_count integer NULL,
                    plan_handle varbinary(64) NULL,
                    sql_text xml NULL,
                    query_plan_xml xml NULL,
                    live_query_plan xml NULL
                    PRIMARY KEY CLUSTERED (collection_time, id)
                );
                IF @debug = 1 BEGIN RAISERROR(''Created table %s for memory queries logging.'', 0, 1, ''' + @log_database_schema + QUOTENAME(@log_table_name_prefix + N'_MemoryQueries') + N''') WITH NOWAIT; END;
            END';

        EXECUTE sys.sp_executesql
            @create_sql,
          N'@schema_name sysname,
            @table_name sysname,
            @debug bit',
            @log_schema_name,
            @log_table_name_prefix,
            @debug;

        /* CPU Queries table */
        SET @create_sql = N'
            IF NOT EXISTS
            (
                SELECT
                    1/0
                FROM ' + QUOTENAME(@log_database_name) + N'.sys.tables AS t
                JOIN ' + QUOTENAME(@log_database_name) + N'.sys.schemas AS s
                  ON t.schema_id = s.schema_id
                WHERE t.name = @table_name + N''_CPUQueries''
                AND   s.name = @schema_name
            )
            BEGIN
                CREATE TABLE ' + @log_table_cpu_queries + N'
                (
                    id bigint IDENTITY,
                    collection_time datetime2(7) NOT NULL DEFAULT SYSDATETIME(),
                    session_id integer NOT NULL,
                    database_name nvarchar(128) NULL,
                    duration varchar(30) NULL,
                    status nvarchar(30) NULL,
                    blocking_session_id integer NULL,
                    wait_type nvarchar(60) NULL,
                    wait_time_ms bigint NULL,
                    wait_resource nvarchar(512) NULL,
                    cpu_time_ms bigint NULL,
                    total_elapsed_time_ms bigint NULL,
                    reads bigint NULL,
                    writes bigint NULL,
                    logical_reads bigint NULL,
                    granted_query_memory_gb decimal(38,2) NULL,
                    transaction_isolation_level sysname NULL,
                    dop integer NULL,
                    parallel_worker_count integer NULL,
                    plan_handle varbinary(64) NULL,
                    sql_text xml NULL,
                    query_plan_xml xml NULL,
                    live_query_plan xml NULL,
                    statement_start_offset integer NULL,
                    statement_end_offset integer NULL,
                    PRIMARY KEY CLUSTERED (collection_time, id)
                );
                IF @debug = 1 BEGIN RAISERROR(''Created table %s for CPU queries logging.'', 0, 1, ''' + @log_database_schema + QUOTENAME(@log_table_name_prefix + N'_CPUQueries') + N''') WITH NOWAIT; END;
            END';

        EXECUTE sys.sp_executesql
            @create_sql,
          N'@schema_name sysname,
            @table_name sysname,
            @debug bit',
            @log_schema_name,
            @log_table_name_prefix,
            @debug;

        EXECUTE sys.sp_executesql
            @create_sql,
          N'@schema_name sysname,
            @table_name sysname,
            @debug bit',
            @log_schema_name,
            @log_table_name_prefix,
            @debug;

        /* CPU Utilization Events table */
        SET @create_sql = N'
            IF NOT EXISTS
            (
                SELECT
                    1/0
                FROM ' + QUOTENAME(@log_database_name) + N'.sys.tables AS t
                JOIN ' + QUOTENAME(@log_database_name) + N'.sys.schemas AS s
                  ON t.schema_id = s.schema_id
                WHERE t.name = @table_name + N''_CPUEvents''
                AND   s.name = @schema_name
            )
            BEGIN
                CREATE TABLE ' + @log_table_cpu_events + N'
                (
                    id bigint IDENTITY,
                    collection_time datetime2(7) NOT NULL DEFAULT SYSDATETIME(),
                    sample_time datetime NULL,
                    sqlserver_cpu_utilization integer NULL,
                    other_process_cpu_utilization integer NULL,
                    total_cpu_utilization integer NULL,
                    PRIMARY KEY CLUSTERED (collection_time, id)
                );
                IF @debug = 1 BEGIN RAISERROR(''Created table %s for CPU utilization events logging.'', 0, 1, ''' + @log_database_schema + QUOTENAME(@log_table_name_prefix + N'_CPUEvents') + N''') WITH NOWAIT; END;
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
            SET @delete_sql = N'
            DELETE FROM ' + @log_table_waits + '
            WHERE collection_time < @cleanup_date;

            DELETE FROM ' + @log_table_file_metrics + '
            WHERE collection_time < @cleanup_date;

            DELETE FROM ' + @log_table_perfmon + '
            WHERE collection_time < @cleanup_date;

            DELETE FROM ' + @log_table_memory + '
            WHERE collection_time < @cleanup_date;

            DELETE FROM ' + @log_table_cpu + '
            WHERE collection_time < @cleanup_date;

            DELETE FROM ' + @log_table_memory_consumers + '
            WHERE collection_time < @cleanup_date;

            DELETE FROM ' + @log_table_memory_queries + '
            WHERE collection_time < @cleanup_date;

            DELETE FROM ' + @log_table_cpu_queries + '
            WHERE collection_time < @cleanup_date;

            DELETE FROM ' + @log_table_cpu_events + '
            WHERE collection_time < @cleanup_date;';

            IF @debug = 1 BEGIN PRINT @delete_sql; END;

            EXECUTE sys.sp_executesql
                @delete_sql,
              N'@cleanup_date datetime2(7)',
                @cleanup_date;

            IF @debug = 1
            BEGIN
                RAISERROR('Log cleanup complete', 0, 1) WITH NOWAIT;
            END;
        END;

    END; /*End log to tables validation checks here*/

    DECLARE
        @waits table
    (
        server_hours_uptime integer,
        server_hours_cpu_time decimal(38,2),
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
        server_hours_uptime integer,
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
    AND @log_to_table = 0
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
                    'EXECUTE sp_configure ''remote admin connections'', 1; RECONFIGURE;',
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
            server_hours_uptime,
            server_hours_cpu_time,
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
            server_hours_uptime =
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
            server_hours_cpu_time =
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
                    WHEN dows.wait_type = N'RESOURCE_GOVERNOR_IDLE'
                    THEN N'Potential CPU cap waits'
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
                    WHEN dows.wait_type = N'HTREINIT'
                    THEN N'Potential batch mode performance issues'
                    WHEN dows.wait_type = N'BTREE_INSERT_FLOW_CONTROL'
                    THEN N'Optimize For Sequential Key'
                    WHEN dows.wait_type = N'HADR_SYNC_COMMIT'
                    THEN N'Potential Availability Group Issues'
                    WHEN dows.wait_type = N'HADR_GROUP_COMMIT'
                    THEN N'Potential Availability Group Issues'
                    WHEN dows.wait_type = N'WAIT_ON_SYNC_STATISTICS_REFRESH'
                    THEN N'Waiting on sync stats updates (compilation)'
                    WHEN dows.wait_type = N'IO_QUEUE_LIMIT'
                    THEN N'Azure SQLDB Throttling'
                    WHEN dows.wait_type = N'IO_RETRY'
                    THEN N'I/O Failures retried'
                    WHEN dows.wait_type = N'RESMGR_THROTTLED'
                    THEN N'Azure SQLDB Throttling'
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
                SYSDATETIME(),
            sorting =
                ROW_NUMBER() OVER
                (
                    ORDER BY
                        dows.wait_time_ms DESC
                )
        FROM sys.dm_os_wait_stats AS dows
        WHERE
        (
          (
                  dows.waiting_tasks_count > -1
              AND dows.wait_type <> N'SLEEP_TASK'
          )
        OR
          (
                 dows.wait_type = N'SLEEP_TASK'
             AND ISNULL(CONVERT(decimal(38, 2), dows.wait_time_ms /
                   NULLIF(1.* dows.waiting_tasks_count, 0.)), 0.) >=
                     CASE WHEN @sample_seconds > 0 THEN 0. ELSE 1000. END
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
                     N'RESOURCE_GOVERNOR_IDLE',
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
                     N'BPSORT',
                     /*Optimize For Sequential Key*/
                     N'BTREE_INSERT_FLOW_CONTROL',
                     /*Availability Group*/
                     N'HADR_SYNC_COMMIT',
                     N'HADR_GROUP_COMMIT',
                     /*Stats/Compilation*/
                     N'WAIT_ON_SYNC_STATISTICS_REFRESH',
                     /*Throttling*/
                     N'IO_QUEUE_LIMIT',
                     N'IO_RETRY',
                     N'RESMGR_THROTTLED'
                 )
            /*Locking*/
            OR dows.wait_type LIKE N'LCK%'
        )
        ORDER BY
            dows.wait_time_ms DESC,
            dows.waiting_tasks_count DESC
        OPTION(MAXDOP 1, RECOMPILE);

        IF @log_to_table = 0
        BEGIN
            IF @sample_seconds = 0
            BEGIN
                SELECT
                    w.wait_type,
                    w.description,
                    w.server_hours_uptime,
                    w.server_hours_cpu_time,
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
                WHERE w.waiting_tasks_count_n > 0
                ORDER BY
                    w.sorting
                OPTION(MAXDOP 1, RECOMPILE);
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
                            (w2.server_hours_cpu_time - w.server_hours_cpu_time) / 1000.
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
                        DATEDIFF
                        (
                            SECOND,
                            w.sample_time,
                            w2.sample_time
                        )
                FROM @waits AS w
                JOIN @waits AS w2
                  ON  w.wait_type = w2.wait_type
                  AND w.sample_time < w2.sample_time
                  AND (w2.waiting_tasks_count_n - w.waiting_tasks_count_n) > 0
                ORDER BY
                    wait_time_seconds DESC
                OPTION(MAXDOP 1, RECOMPILE);
            END;
        END;

            IF @log_to_table = 1
            BEGIN

                SELECT
                    w.*
                INTO #waits
                FROM @waits AS w
                OPTION(RECOMPILE);

                SET @insert_sql = N'
                    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
                    INSERT INTO ' + @log_table_waits + N'
                    (
                        server_hours_uptime,
                        server_hours_cpu_time,
                        wait_type,
                        description,
                        hours_wait_time,
                        avg_ms_per_wait,
                        percent_signal_waits,
                        waiting_tasks_count
                    )
                    SELECT
                        w.server_hours_uptime,
                        w.server_hours_cpu_time,
                        w.wait_type,
                        w.description,
                        w.hours_wait_time,
                        w.avg_ms_per_wait,
                        w.percent_signal_waits,
                        w.waiting_tasks_count_n
                    FROM #waits AS w;
                    ';

                IF @debug = 1
                BEGIN
                    PRINT @insert_sql;
                END;

                EXECUTE sys.sp_executesql
                    @insert_sql;

                IF OBJECT_ID(N'tempdb..#waits', N'U') IS NOT NULL
                BEGIN
                    DROP TABLE #waits;
                END;
            END;
    END; /*End wait stats*/
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
            server_hours_uptime =
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
                          CONVERT
                          (
                              decimal(38, 2),
                              NULLIF(vfs.num_of_reads, 0.)
                          ),
                        0.
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
                          CONVERT
                          (
                              decimal(38, 2),
                              NULLIF(vfs.num_of_writes, 0.)
                          ),
                        0.
                    )
                ),
            io_stall_read_ms,
            io_stall_write_ms,
            sample_time =
                SYSDATETIME()
        FROM sys.dm_io_virtual_file_stats
        (' +
        CASE
            WHEN @azure = 1
            THEN N'
            DB_ID()'
            ELSE N'
            NULL'
        END + N',
            NULL
        ) AS vfs
        JOIN ' +
        CONVERT
        (
            nvarchar(max),
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
        )
        OPTION(MAXDOP 1, RECOMPILE);'
        );

        IF @debug = 1
        BEGIN
            PRINT SUBSTRING(@disk_check, 1, 4000);
            PRINT SUBSTRING(@disk_check, 4001, 8000);
        END;

        INSERT
            @file_metrics
        (
            server_hours_uptime,
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
        EXECUTE sys.sp_executesql
            @disk_check;

        IF @log_to_table = 0
        BEGIN
            IF @sample_seconds = 0
            BEGIN
                WITH
                    file_metrics AS
                (
                    SELECT
                        fm.server_hours_uptime,
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
                    fm.server_hours_uptime,
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
                    server_hours_uptime = 0,
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
                    total_avg_stall_ms DESC
                OPTION(MAXDOP 1, RECOMPILE);
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
                        DATEDIFF
                        (
                            SECOND,
                            f.sample_time_o,
                            f.sample_time_t
                        )
                FROM f
                WHERE
                (
                     f.total_read_count  > 0
                  OR f.total_write_count > 0
                )
                ORDER BY
                    f.total_avg_stall DESC
                OPTION(MAXDOP 1, RECOMPILE);
            END;
        END;

        IF @log_to_table = 1
        BEGIN

           SELECT
               fm.*
           INTO #file_metrics
           FROM @file_metrics AS fm
           OPTION(RECOMPILE);

           SET @insert_sql = N'
               SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
               INSERT INTO ' + @log_table_file_metrics + N'
               (
                   server_hours_uptime,
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
                   io_stall_write_ms
               )
               SELECT
                   fm.server_hours_uptime,
                   fm.drive,
                   fm.database_name,
                   fm.database_file_details,
                   fm.file_size_gb,
                   fm.total_gb_read,
                   fm.total_mb_read,
                   fm.total_read_count,
                   fm.avg_read_stall_ms,
                   fm.total_gb_written,
                   fm.total_mb_written,
                   fm.total_write_count,
                   fm.avg_write_stall_ms,
                   fm.io_stall_read_ms,
                   fm.io_stall_write_ms
               FROM #file_metrics AS fm;
               ';

           IF @debug = 1
           BEGIN
               PRINT @insert_sql;
           END;

           EXECUTE sys.sp_executesql
               @insert_sql;

           IF OBJECT_ID(N'tempdb..#file_metrics', N'U') IS NOT NULL
           BEGIN
               DROP TABLE #file_metrics;
           END;
        END;
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
                        ELSE SYSDATETIME()
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
            N'internal', N'master', N'model', N'msdb', N'model_msdb',
            N'model_replicatedmaster', N'mssqlsystemresource'
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


        IF @log_to_table = 0
        BEGIN
            IF @sample_seconds = 0
            BEGIN
                WITH
                    p AS
                (
                    SELECT
                        server_hours_uptime =
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
                            FORMAT
                            (
                                dopc.cntr_value /
                                DATEDIFF
                                (
                                    SECOND,
                                    dopc.sample_time,
                                    SYSDATETIME()
                                ),
                                'N0'
                            )
                    FROM @dm_os_performance_counters AS dopc
                )
                SELECT
                    p.object_name,
                    p.counter_name,
                    p.instance_name,
                    p.server_hours_uptime,
                    p.total,
                    p.total_per_second
                FROM p
                WHERE p.cntr_value > 0
                ORDER BY
                    p.object_name,
                    p.counter_name,
                    p.cntr_value DESC
                OPTION(MAXDOP 1, RECOMPILE);
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
                    p.total_difference_i DESC
                OPTION(MAXDOP 1, RECOMPILE);
            END;
        END;

       IF @log_to_table = 1
       BEGIN

           SELECT
               dopc.*
           INTO #dm_os_performance_counters
           FROM @dm_os_performance_counters AS dopc
           OPTION(RECOMPILE);

           SET @insert_sql = N'
               SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
               INSERT INTO ' + @log_table_perfmon + N'
               (
                   object_name,
                   counter_name,
                   counter_name_clean,
                   instance_name,
                   cntr_value,
                   cntr_type
               )
               SELECT
                   dopc.object_name,
                   dopc.counter_name,
                   dopc.counter_name_clean,
                   dopc.instance_name,
                   dopc.cntr_value,
                   dopc.cntr_type
               FROM #dm_os_performance_counters AS dopc;
               ';

           IF @debug = 1
           BEGIN
               PRINT @insert_sql;
           END;

           EXECUTE sys.sp_executesql
               @insert_sql;


           IF OBJECT_ID(N'tempdb..#dm_os_performance_counters', N'U') IS NOT NULL
           BEGIN
               DROP TABLE #dm_os_performance_counters;
           END;
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
    AND @log_to_table = 0
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
                   nvarchar(max),
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
                        ' + CONVERT
                            (
                                nvarchar(max),
                            CASE @pages_kb
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
                      END ) + N'
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

        IF @log_to_table = 0
        BEGIN
            EXECUTE sys.sp_executesql
                @pool_sql;
        END;

        IF @log_to_table = 1
        BEGIN
            SET @insert_sql = N'
                SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
                INSERT INTO ' + @log_table_memory_consumers + N'
                (
                    memory_source,
                    memory_consumer,
                    memory_consumed_gb
                )
                ' +
                REPLACE
                (
                    @pool_sql,
                    N'SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;',
                    N''
                );

            IF @debug = 1
            BEGIN
                PRINT @insert_sql;
            END;

            EXECUTE sys.sp_executesql
                @insert_sql;
        END;

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

        EXECUTE sys.sp_executesql
            @database_size_out,
          N'@database_size_out_gb nvarchar(10) OUTPUT',
            @database_size_out_gb OUTPUT;

        /*Check physical memory in the server*/
        IF @azure = 0
        BEGIN
            SELECT
                @total_physical_memory_gb =
                    CEILING(dosm.total_physical_memory_kb / 1024. / 1024.)
                FROM sys.dm_os_sys_memory AS dosm
                OPTION(MAXDOP 1, RECOMPILE);
        END;
        IF @azure = 1
        BEGIN
            SELECT
                @total_physical_memory_gb =
                    SUM(osi.committed_target_kb / 1024. / 1024.)
            FROM sys.dm_os_sys_info osi
            OPTION(MAXDOP 1, RECOMPILE);
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
                    t.record.value('(/Record/ResourceMonitor/IndicatorsProcess)[1]', 'integer'),
                indicators_system =
                    t.record.value('(/Record/ResourceMonitor/IndicatorsSystem)[1]', 'integer'),
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
            @cache_sql += N'
        SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

        SELECT
            @cache_xml =
                x.c
        FROM
        (
            SELECT TOP (20)
                name =
                    CASE
                        WHEN domcc.name LIKE N''%UserStore%''
                        THEN N''UserStore''
                        WHEN domcc.name LIKE N''ObjPerm%''
                        THEN N''ObjPerm''
                        ELSE domcc.name
                    END,
                pages_gb =
                    CONVERT
                    (
                        decimal(38, 2),
                        SUM
                        (' +
                            CASE
                                @pages_kb
                                WHEN 1
                                THEN N'
                            domcc.pages_kb'
                                ELSE N'
                            domcc.single_pages_kb +
                            domcc.multi_pages_kb'
                            END + N'
                        ) / 1024. / 1024.
                    ),
                pages_in_use_gb =
                    ISNULL
                    (
                        CONVERT
                        (
                            decimal(38, 2),
                            SUM
                            (' +
                                CASE
                                    @pages_kb
                                    WHEN 1
                                    THEN N'
                                domcc.pages_in_use_kb'
                                    ELSE N'
                                domcc.single_pages_in_use_kb +
                                domcc.multi_pages_in_use_kb'
                                END + N'
                            ) / 1024. / 1024.
                        ),
                        N''0.00''
                    ),
                entries_count =
                    REPLACE
                    (
                        CONVERT
                        (
                            nvarchar(30),
                            CONVERT
                            (
                                money,
                                SUM(domcc.entries_count)
                            ),
                            1
                        ),
                        N''.00'',
                        N''''
                    ),
                entries_in_use_count =
                    REPLACE
                    (
                        CONVERT
                        (
                            nvarchar(30),
                            CONVERT
                            (
                                money,
                                SUM(domcc.entries_in_use_count)
                            ),
                            1
                        ),
                        N''.00'',
                        N''''
                    )
            FROM sys.dm_os_memory_cache_counters AS domcc
            WHERE domcc.name NOT IN
            (
                N''msdb'',
                N''model_replicatedmaster'',
                N''model_msdb'',
                N''model'',
                N''master'',
                N''mssqlsystemresource''
            )
            GROUP BY
                    CASE
                        WHEN domcc.name LIKE N''%UserStore%''
                        THEN N''UserStore''
                        WHEN domcc.name LIKE N''ObjPerm%''
                        THEN N''ObjPerm''
                        ELSE domcc.name
                    END
            HAVING
                SUM
                (' +
                    CASE
                        @pages_kb
                        WHEN 1
                        THEN N'
                    domcc.pages_in_use_kb'
                        ELSE N'
                    domcc.single_pages_in_use_kb +
                    domcc.multi_pages_in_use_kb'
                    END + N'
                ) / 1024. / 1024. > 0
            ORDER BY
                pages_gb DESC
            FOR XML
                PATH(''cache''),
                TYPE
        ) AS x (c)
        OPTION(MAXDOP 1, RECOMPILE);
        ';

        IF @debug = 1
        BEGIN
            PRINT @cache_sql;
        END;

        IF @log_to_table = 0
        BEGIN
        EXECUTE sys.sp_executesql
            @cache_sql,
          N'@cache_xml xml OUTPUT',
            @cache_xml OUTPUT;
        END;

        IF @cache_xml IS NULL
        BEGIN
            SELECT
                @cache_xml =
                (
                    SELECT
                        N'No significant caches detected'
                    FOR XML
                        PATH(N'cache'),
                        TYPE
                );
        END;

        IF @log_to_table = 0
        BEGIN
            SELECT
                low_memory =
                   @low_memory,
                cache_memory =
                    @cache_xml;
        END;

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
            )
        OPTION(MAXDOP 1, RECOMPILE);

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
            @resource_semaphores += N'
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
                    WHERE c.name = N''max server memory (MB)''
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
        ';

        IF @log_to_table = 0
        BEGIN
            EXECUTE sys.sp_executesql
                @resource_semaphores,
              N'@database_size_out_gb nvarchar(10),
                @total_physical_memory_gb bigint,
                @memory_grant_cap xml',
                @database_size_out_gb,
                @total_physical_memory_gb,
                @memory_grant_cap;
        END

        IF @log_to_table = 1
        BEGIN
            SET @insert_sql = N'
                SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
                INSERT INTO ' + @log_table_memory + N'
                (
                    resource_semaphore_id,
                    total_database_size_gb,
                    total_physical_memory_gb,
                    max_server_memory_gb,
                    max_memory_grant_cap,
                    memory_model,
                    target_memory_gb,
                    max_target_memory_gb,
                    total_memory_gb,
                    available_memory_gb,
                    granted_memory_gb,
                    used_memory_gb,
                    grantee_count,
                    waiter_count,
                    timeout_error_count,
                    forced_grant_count,
                    total_reduced_memory_grant_count,
                    pool_id
                )' +
                @resource_semaphores;

            IF @debug = 1
            BEGIN
                PRINT @insert_sql;
            END;

            EXECUTE sys.sp_executesql
                @insert_sql,
              N'@database_size_out_gb nvarchar(10),
                @total_physical_memory_gb bigint,
                @memory_grant_cap xml',
                @database_size_out_gb,
                @total_physical_memory_gb,
                @memory_grant_cap;
        END;
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
        SET LOCK_TIMEOUT 1000;

        SELECT
            deqmg.session_id,
            database_name =
                DB_NAME(deqp.dbid),
            [dd hh:mm:ss.mss] =
                CASE
                    WHEN e.elapsed_time_ms < 0
                    THEN RIGHT(REPLICATE(''0'', 2) + CONVERT(varchar(10), (-1 * e.elapsed_time_ms) / 86400), 2) +
                         '' '' +
                         RIGHT(CONVERT(varchar(30), DATEADD(second, (-1 * e.elapsed_time_ms), 0), 120), 9) +
                         ''.000''
                    ELSE RIGHT(REPLICATE(''0'', 2) +
                         CONVERT(varchar(10), e.elapsed_time_ms / 86400000), 2) +
                         '' '' +
                         RIGHT(convert(varchar(30), DATEADD(second, e.elapsed_time_ms / 1000, 0), 120), 9) +
                         ''.'' +
                         RIGHT(''000'' + CONVERT(varchar(3), e.elapsed_time_ms % 1000), 3)
                END,
            query_text =
                (
                    SELECT
                        [processing-instruction(query)] =
                            SUBSTRING
                            (
                                REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                REPLACE(
                                    dest.text COLLATE Latin1_General_BIN2,
                                NCHAR(31),N''?''),NCHAR(30),N''?''),NCHAR(29),N''?''),NCHAR(28),N''?''),NCHAR(27),N''?''),NCHAR(26),N''?''),NCHAR(25),N''?''),NCHAR(24),N''?''),NCHAR(23),N''?''),NCHAR(22),N''?''),
                                NCHAR(21),N''?''),NCHAR(20),N''?''),NCHAR(19),N''?''),NCHAR(18),N''?''),NCHAR(17),N''?''),NCHAR(16),N''?''),NCHAR(15),N''?''),NCHAR(14),N''?''),NCHAR(12),N''?''),
                                NCHAR(11),N''?''),NCHAR(8),N''?''),NCHAR(7),N''?''),NCHAR(6),N''?''),NCHAR(5),N''?''),NCHAR(4),N''?''),NCHAR(3),N''?''),NCHAR(2),N''?''),NCHAR(1),N''?''),NCHAR(0),N''''),
                                N''<?'', N''??''), N''?>'', N''??''),
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
                            FOR XML
                                PATH(''''),
                                TYPE
                ),'
            + CONVERT
              (
                  nvarchar(max),
              CASE
                  WHEN @skip_plan_xml = 0
                  THEN N'
            query_plan =
                 CASE
                     WHEN TRY_CAST(deqp.query_plan AS xml) IS NOT NULL
                     THEN TRY_CAST(deqp.query_plan AS xml)
                     WHEN TRY_CAST(deqp.query_plan AS xml) IS NULL
                     THEN
                         (
                             SELECT
                                 [processing-instruction(query_plan)] =
                                     N''-- '' + NCHAR(13) + NCHAR(10) +
                                     N''-- This is a huge query plan.'' + NCHAR(13) + NCHAR(10) +
                                     N''-- Remove the headers and footers, save it as a .sqlplan file, and re-open it.'' + NCHAR(13) + NCHAR(10) +
                                     NCHAR(13) + NCHAR(10) +
                                     REPLACE(deqp.query_plan, N''<RelOp'', NCHAR(13) + NCHAR(10) + N''<RelOp'') +
                                     NCHAR(13) + NCHAR(10) COLLATE Latin1_General_Bin2
                             FOR XML PATH(N''''),
                                     TYPE
                         )
                 END,' +
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
        LEFT JOIN sys.dm_exec_requests AS der
          ON der.session_id = deqmg.session_id
        OUTER APPLY
        (
            SELECT
                elapsed_time_ms =
                    CASE
                        WHEN DATEDIFF(HOUR, der.start_time, SYSDATETIME()) > 576
                        THEN DATEDIFF(SECOND, SYSDATETIME(), der.start_time)
                        ELSE DATEDIFF(MILLISECOND, der.start_time, SYSDATETIME())
                    END
        ) AS e
        OUTER APPLY
        (
            SELECT TOP (1)
                dowt.*
            FROM sys.dm_os_waiting_tasks AS dowt
            WHERE dowt.session_id = deqmg.session_id
            ORDER BY
                dowt.wait_duration_ms DESC
        ) AS waits
        OUTER APPLY sys.dm_exec_text_query_plan
        (
            deqmg.plan_handle,
            der.statement_start_offset,
            der.statement_end_offset
        ) AS deqp
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

        SET LOCK_TIMEOUT -1;
        '
                  );

        IF @debug = 1
        BEGIN
            PRINT SUBSTRING(@mem_sql, 1, 4000);
            PRINT SUBSTRING(@mem_sql, 4001, 8000);
        END;

        IF @log_to_table = 0
        BEGIN
        EXECUTE sys.sp_executesql
            @mem_sql;
        END

        IF @log_to_table = 1
        BEGIN
            SET @insert_sql = N'
                SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
                INSERT INTO ' + @log_table_memory_queries + N'
                (
                    session_id,
                    database_name,
                    duration,
                    sql_text,
                    query_plan_xml' +
                    CASE
                        WHEN @live_plans = 1
                        THEN N',
                    live_query_plan'
                        ELSE N''
                    END + N',
                    request_time,
                    grant_time,
                    wait_time_seconds,
                    requested_memory_gb,
                    granted_memory_gb,
                    used_memory_gb,
                    max_used_memory_gb,
                    ideal_memory_gb,
                    required_memory_gb,
                    queue_id,
                    wait_order,
                    is_next_candidate,
                    wait_type,
                    wait_duration_seconds,
                    dop' +
                    CASE
                        WHEN @helpful_new_columns = 1
                        THEN N',
                    reserved_worker_count,
                    used_worker_count'
                        ELSE N''
                    END + N',
                    plan_handle
                ) ' +
                REPLACE
                (
                    REPLACE
                    (
                        REPLACE
                        (
                            @mem_sql,
                            N'SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;',
                            N''
                        ),
                        N'SET LOCK_TIMEOUT 1000;',
                        N''
                    ),
                    N'SET LOCK_TIMEOUT -1;',
                    N''
                );

            IF @debug = 1
            BEGIN
                PRINT @insert_sql;
            END;

            EXECUTE sys.sp_executesql
                @insert_sql;
        END;
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

            EXECUTE sys.sp_executesql
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

        EXECUTE sys.sp_executesql
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
                    t.record.value('(Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]','integer'),
                other_process_cpu_utilization =
                    (100 - t.record.value('(Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]','integer')
                     - t.record.value('(Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]','integer')),
                total_cpu_utilization =
                    (100 - t.record.value('(Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'integer'))
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

        IF @log_to_table = 0
        BEGIN
            SELECT
                cpu_details_output =
                    @cpu_details_output,
                cpu_utilization_over_threshold =
                    @cpu_utilization;
        END;
        IF @log_to_table = 1
        BEGIN
            /* Get the maximum sample_time from the CPU events table */
            SET @insert_sql = N'
                SELECT
                    @max_sample_time_out =
                        ISNULL
                        (
                            MAX(sample_time),
                            ''19000101''
                        )
                FROM ' + @log_table_cpu_events + N'
                OPTION(RECOMPILE);';

            IF @debug = 1
            BEGIN
                PRINT @insert_sql;
            END;

            EXECUTE sys.sp_executesql
                @insert_sql,
                N'@max_sample_time_out datetime OUTPUT',
                @max_sample_time OUTPUT;

            SET @insert_sql = N'
                SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
                INSERT INTO ' + @log_table_cpu_events + N'
                (
                    sample_time,
                    sqlserver_cpu_utilization,
                    other_process_cpu_utilization,
                    total_cpu_utilization
                )
                SELECT
                    sample_time = event.value(''(./sample_time)[1]'', ''datetime''),
                    sqlserver_cpu_utilization = event.value(''(./sqlserver_cpu_utilization)[1]'', ''integer''),
                    other_process_cpu_utilization = event.value(''(./other_process_cpu_utilization)[1]'', ''integer''),
                    total_cpu_utilization = event.value(''(./total_cpu_utilization)[1]'', ''integer'')
                FROM @cpu_utilization.nodes(''/cpu_utilization'') AS cpu(event)
                WHERE event.exist(''(./sample_time)[. > sql:variable("@max_sample_time")]'') = 1;';

            IF @debug = 1
            BEGIN
                PRINT @insert_sql;
            END;

            EXECUTE sys.sp_executesql
                @insert_sql,
              N'@cpu_utilization xml,
                @max_sample_time datetime',
                @cpu_utilization,
                @max_sample_time;
        END;

        /*Thread usage*/
        SELECT
            @cpu_threads += N'
        SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
        SELECT
            total_threads =
                MAX(osi.max_workers_count),
            used_threads =
                SUM(dos.active_workers_count),
            available_threads =
                MAX(osi.max_workers_count) - SUM(dos.active_workers_count),
            reserved_worker_count = ' +
                CASE @helpful_new_columns
                     WHEN 1
                     THEN ISNULL
                          (
                              @reserved_worker_count_out,
                              N'0'
                          )
                     ELSE N'''N/A'''
                END + N',
            threads_waiting_for_cpu =
                SUM(dos.runnable_tasks_count),
            requests_waiting_for_threads =
                SUM(dos.work_queue_count),
            current_workers =
                SUM(dos.current_workers_count),
            total_active_request_count =
                MAX(wg.active_request_count),
            total_queued_request_count =
                MAX(wg.queued_request_count),
            total_blocked_task_count =
                MAX(wg.blocked_task_count),
            total_active_parallel_thread_count =
                MAX(wg.active_parallel_thread_count),
            avg_runnable_tasks_count =
                AVG(dos.runnable_tasks_count),
            high_runnable_percent =
                MAX(ISNULL(r.high_runnable_percent, 0))
        FROM sys.dm_os_schedulers AS dos
        CROSS JOIN sys.dm_os_sys_info AS osi
        CROSS JOIN
        (
            SELECT
                active_request_count =
                    SUM(wg.active_request_count),
                queued_request_count =
                    SUM(wg.queued_request_count),
                blocked_task_count =
                    SUM(wg.blocked_task_count),
                active_parallel_thread_count =
                    SUM(wg.active_parallel_thread_count)
            FROM sys.dm_resource_governor_workload_groups AS wg
        ) AS wg
        OUTER APPLY
        (
            SELECT
                high_runnable_percent =
                    '''' +
                    RTRIM(y.runnable_pct) +
                    ''% of '' +
                    RTRIM(y.total) +
                    '' queries are waiting to get on a CPU.''
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
                                x.runnable /
                                (1. * NULLIF(x.total, 0))
                            )
                        ) * 100.
                FROM
                (
                    SELECT
                        total = COUNT_BIG(*),
                        runnable =
                            SUM
                            (
                                CASE
                                    WHEN der.status = N''runnable''
                                    THEN 1
                                    ELSE 0
                                END
                            )
                    FROM sys.dm_exec_requests AS der
                    WHERE der.session_id > 50
                    AND   der.session_id <> @@SPID
                    AND   der.status NOT IN (N''background'', N''sleeping'')
                ) AS x
            ) AS y
            WHERE y.runnable_pct >= 10
            AND   y.total >= 4
        ) AS r
        WHERE dos.status = N''VISIBLE ONLINE''
        OPTION(MAXDOP 1, RECOMPILE);
        ';

        IF @log_to_table = 0
        BEGIN
            IF @debug = 1
            BEGIN
                PRINT @cpu_threads;
            END;

            EXECUTE sys.sp_executesql
                @cpu_threads;
        END;

        IF @log_to_table = 1
        BEGIN
            SET @insert_sql = N'
                SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
                INSERT INTO ' + @log_table_cpu + N'
                (
                    total_threads,
                    used_threads,
                    available_threads,
                    reserved_worker_count,
                    threads_waiting_for_cpu,
                    requests_waiting_for_threads,
                    current_workers,
                    total_active_request_count,
                    total_queued_request_count,
                    total_blocked_task_count,
                    total_active_parallel_thread_count,
                    avg_runnable_tasks_count,
                    high_runnable_percent
                )' +
                REPLACE
                (
                    @cpu_threads,
                    N'SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;',
                    N''
                );

            IF @debug = 1
            BEGIN
                PRINT @insert_sql;
            END;

            EXECUTE sys.sp_executesql
                @insert_sql;
        END;


        /*
        Any current threadpool waits?
        */
        IF @log_to_table = 0
        BEGIN
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
            SET LOCK_TIMEOUT 1000;

            SELECT
                der.session_id,
                database_name =
                    DB_NAME(der.database_id),
                [dd hh:mm:ss.mss] =
                    CASE
                        WHEN e.elapsed_time_ms < 0
                        THEN RIGHT(REPLICATE(''0'', 2) + CONVERT(varchar(10), (-1 * e.elapsed_time_ms) / 86400), 2) +
                             '' '' +
                             RIGHT(CONVERT(varchar(30), DATEADD(second, (-1 * e.elapsed_time_ms), 0), 120), 9) +
                             ''.000''
                        ELSE RIGHT(REPLICATE(''0'', 2) +
                             CONVERT(varchar(10), e.elapsed_time_ms / 86400000), 2) +
                             '' '' +
                             RIGHT(convert(varchar(30), DATEADD(second, e.elapsed_time_ms / 1000, 0), 120), 9) +
                             ''.'' +
                             RIGHT(''000'' + CONVERT(varchar(3), e.elapsed_time_ms % 1000), 3)
                    END,
                query_text =
                    (
                        SELECT
                            [processing-instruction(query)] =
                                SUBSTRING
                                (
                                    REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                    REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                    REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                    REPLACE(
                                        dest.text COLLATE Latin1_General_BIN2,
                                    NCHAR(31),N''?''),NCHAR(30),N''?''),NCHAR(29),N''?''),NCHAR(28),N''?''),NCHAR(27),N''?''),NCHAR(26),N''?''),NCHAR(25),N''?''),NCHAR(24),N''?''),NCHAR(23),N''?''),NCHAR(22),N''?''),
                                    NCHAR(21),N''?''),NCHAR(20),N''?''),NCHAR(19),N''?''),NCHAR(18),N''?''),NCHAR(17),N''?''),NCHAR(16),N''?''),NCHAR(15),N''?''),NCHAR(14),N''?''),NCHAR(12),N''?''),
                                    NCHAR(11),N''?''),NCHAR(8),N''?''),NCHAR(7),N''?''),NCHAR(6),N''?''),NCHAR(5),N''?''),NCHAR(4),N''?''),NCHAR(3),N''?''),NCHAR(2),N''?''),NCHAR(1),N''?''),NCHAR(0),N''''),
                                    N''<?'', N''??''), N''?>'', N''??''),
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
                    nvarchar(max),
                CASE
                      WHEN @skip_plan_xml = 0
                      THEN N'
                query_plan =
                     CASE
                         WHEN TRY_CAST(deqp.query_plan AS xml) IS NOT NULL
                         THEN TRY_CAST(deqp.query_plan AS xml)
                         WHEN TRY_CAST(deqp.query_plan AS xml) IS NULL
                         THEN
                             (
                                 SELECT
                                     [processing-instruction(query_plan)] =
                                         N''-- '' + NCHAR(13) + NCHAR(10) +
                                         N''-- This is a huge query plan.'' + NCHAR(13) + NCHAR(10) +
                                         N''-- Remove the headers and footers, save it as a .sqlplan file, and re-open it.'' + NCHAR(13) + NCHAR(10) +
                                         NCHAR(13) + NCHAR(10) +
                                         REPLACE(deqp.query_plan, N''<RelOp'', NCHAR(13) + NCHAR(10) + N''<RelOp'') +
                                         NCHAR(13) + NCHAR(10) COLLATE Latin1_General_Bin2
                                 FOR XML PATH(N''''),
                                         TYPE
                             )
                     END,' +
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
                      nvarchar(max),
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
                               nvarchar(max),
                               N',
                der.dop,
                der.parallel_worker_count'
                           )
                      ELSE N''
                  END
                + CONVERT
                  (
                      nvarchar(max),
                      N'
            FROM sys.dm_exec_requests AS der
            OUTER APPLY
            (
                SELECT
                    elapsed_time_ms =
                        CASE
                            WHEN DATEDIFF(HOUR, der.start_time, SYSDATETIME()) > 576
                            THEN DATEDIFF(SECOND, SYSDATETIME(), der.start_time)
                            ELSE DATEDIFF(MILLISECOND, der.start_time, SYSDATETIME())
                        END
            ) AS e
            OUTER APPLY sys.dm_exec_sql_text(der.plan_handle) AS dest
            OUTER APPLY sys.dm_exec_text_query_plan
            (
                der.plan_handle,
                der.statement_start_offset,
                der.statement_end_offset
            ) AS deqp' +
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
            OPTION(MAXDOP 1, RECOMPILE);

            SET LOCK_TIMEOUT -1;
            '
              END
                  );

            IF @debug = 1
            BEGIN
                PRINT SUBSTRING(@cpu_sql, 0, 4000);
                PRINT SUBSTRING(@cpu_sql, 4001, 8000);
            END;

            IF @log_to_table = 0
            BEGIN
                EXECUTE sys.sp_executesql
                    @cpu_sql;
            END;

            IF @log_to_table = 1
            BEGIN
                SET @insert_sql = N'
                    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
                    INSERT INTO ' + @log_table_cpu_queries + N'
                    (
                        session_id,
                        database_name,
                        duration,
                        sql_text,
                        query_plan_xml' +
                        CASE
                            WHEN @live_plans = 1
                            THEN N',
                        live_query_plan'
                            ELSE N''
                        END + N',
                        statement_start_offset,
                        statement_end_offset,
                        plan_handle,
                        status,
                        blocking_session_id,
                        wait_type,
                        wait_time_ms,
                        wait_resource,
                        cpu_time_ms,
                        total_elapsed_time_ms,
                        reads,
                        writes,
                        logical_reads,
                        granted_query_memory_gb,
                        transaction_isolation_level' +
                        CASE
                            WHEN @cool_new_columns = 1
                            THEN N',
                        dop,
                        parallel_worker_count'
                            ELSE N''
                        END + N'
                    )' +
                    REPLACE
                    (
                        REPLACE
                        (
                            REPLACE
                            (
                                @cpu_sql,
                                N'SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;',
                                N''
                            ),
                            N'SET LOCK_TIMEOUT 1000;',
                            N''
                        ),
                        N'SET LOCK_TIMEOUT -1;',
                        N''
                    );

                IF @debug = 1
                BEGIN
                    PRINT @insert_sql;
                END;

                EXECUTE sys.sp_executesql
                    @insert_sql;
            END;
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

        SELECT
            pattern =
                'logging parameters',
            log_to_table =
                @log_to_table,
            log_database_name =
                @log_database_name,
            log_schema_name =
                @log_schema_name,
            log_table_name_prefix =
                @log_table_name_prefix,
            log_database_schema =
                @log_database_schema,
            log_table_waits =
                @log_table_waits,
            log_table_file_metrics =
                @log_table_file_metrics,
            log_table_perfmon =
                @log_table_perfmon,
            log_table_memory =
                @log_table_memory,
            log_table_cpu =
                @log_table_cpu,
            log_table_memory_consumers =
                @log_table_memory_consumers,
            log_table_memory_queries =
                @log_table_memory_queries,
            log_table_cpu_queries =
                @log_table_cpu_queries,
            log_table_cpu_events =
                @log_table_cpu_events;

    END; /*End Debug*/
END; /*Final End*/
GO
