SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
SET IMPLICIT_TRANSACTIONS OFF;
SET STATISTICS TIME, IO OFF;
GO

/*
██████╗ ███████╗██████╗ ███████╗
██╔══██╗██╔════╝██╔══██╗██╔════╝
██████╔╝█████╗  ██████╔╝█████╗
██╔═══╝ ██╔══╝  ██╔══██╗██╔══╝
██║     ███████╗██║  ██║██║
╚═╝     ╚══════╝╚═╝  ╚═╝╚═╝

 ██████╗██╗  ██╗███████╗ ██████╗██╗  ██╗
██╔════╝██║  ██║██╔════╝██╔════╝██║ ██╔╝
██║     ███████║█████╗  ██║     █████╔╝
██║     ██╔══██║██╔══╝  ██║     ██╔═██╗
╚██████╗██║  ██║███████╗╚██████╗██║  ██╗
 ╚═════╝╚═╝  ╚═╝╚══════╝ ╚═════╝╚═╝  ╚═╝

Copyright 2025 Darling Data, LLC
https://www.erikdarling.com/

For usage and licensing details, run:
EXECUTE sp_PerfCheck
    @help = 1;

For working through errors:
EXECUTE sp_PerfCheck
    @debug = 1;

For support, head over to GitHub:
https://code.erikdarling.com

*/

IF OBJECT_ID(N'dbo.sp_PerfCheck', N'P') IS NULL
BEGIN
    EXECUTE(N'CREATE PROCEDURE dbo.sp_PerfCheck AS RETURN 138;');
END;
GO

ALTER PROCEDURE
    dbo.sp_PerfCheck
(
    @database_name sysname = NULL, /* Database to check, NULL for all user databases */
    @help bit = 0, /*For helpfulness*/
    @debug bit = 0, /* Print diagnostic messages */
    @version varchar(30) = NULL OUTPUT, /* Returns version */
    @version_date datetime = NULL OUTPUT /* Returns version date */
)
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    /*
    Set version information
    */
    SELECT
        @version = N'1.6',
        @version_date = N'20250601';

    /*
    Help section, for help.
    Will become more helpful when out of beta.
    */
    IF @help = 1
    BEGIN
        SELECT
            help = N'hello, i am sp_PerfCheck'
          UNION ALL
        SELECT
            help = N'i look at important performance settings and metrics'
          UNION ALL
        SELECT
            help = N'don''t hate me because i''m beautiful.'
          UNION ALL
        SELECT
            help = N'brought to you by erikdarling.com / code.erikdarling.com';

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
                    WHEN N'@database_name' THEN 'the name of the database you wish to analyze'
                    WHEN N'@help' THEN 'displays this help information'
                    WHEN N'@debug' THEN 'prints debug information during execution'
                    WHEN N'@version' THEN 'returns the version number of the procedure'
                    WHEN N'@version_date' THEN 'returns the date this version was released'
                    ELSE NULL
                END,
            valid_inputs =
                CASE
                    ap.name
                    WHEN N'@database_name' THEN 'the name of a database you care about indexes in'
                    WHEN N'@help' THEN '0 or 1'
                    WHEN N'@debug' THEN '0 or 1'
                    WHEN N'@version' THEN 'OUTPUT parameter'
                    WHEN N'@version_date' THEN 'OUTPUT parameter'
                    ELSE NULL
                END,
            defaults =
                CASE
                    ap.name
                    WHEN N'@database_name' THEN 'NULL'
                    WHEN N'@help' THEN 'false'
                    WHEN N'@debug' THEN 'true'
                    WHEN N'@version' THEN 'NULL'
                    WHEN N'@version_date' THEN 'NULL'
                    ELSE NULL
                END
        FROM sys.all_parameters AS ap
        JOIN sys.all_objects AS o
          ON ap.object_id = o.object_id
        JOIN sys.types AS t
          ON  ap.system_type_id = t.system_type_id
          AND ap.user_type_id = t.user_type_id
        WHERE o.name = N'sp_PerfCheck'
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
', 0, 1) WITH NOWAIT;

        RETURN;
    END;

    /*
    Variable Declarations
    */
    DECLARE
        @product_version sysname =
            CONVERT
            (
                sysname,
                SERVERPROPERTY(N'ProductVersion')
            ),
        @product_version_major decimal(10, 2) =
            SUBSTRING
            (
                CONVERT
                (
                    sysname,
                    SERVERPROPERTY(N'ProductVersion')
                ),
                1,
                CHARINDEX
                (
                    '.',
                    CONVERT
                    (
                        sysname,
                        SERVERPROPERTY(N'ProductVersion')
                    )
                ) + 1
            ),
        @product_version_minor decimal(10, 2) =
            PARSENAME
            (
                CONVERT
                (
                    varchar(32),
                    CONVERT
                    (
                        sysname,
                        SERVERPROPERTY(N'ProductVersion')
                    )
                ),
                2
            ),
        @product_level sysname =
            CONVERT
            (
                sysname,
                SERVERPROPERTY(N'ProductLevel')
            ),
        @product_edition sysname =
            CONVERT
            (
                sysname,
                SERVERPROPERTY(N'Edition')
            ),
        @server_name sysname =
            CONVERT
            (
                sysname,
                SERVERPROPERTY(N'ServerName')
            ),
        @engine_edition integer =
            CONVERT
            (
                integer,
                SERVERPROPERTY(N'EngineEdition')
            ),
        @start_time datetime2(0) = SYSDATETIME(),
        @error_message nvarchar(4000) = N'',
        @sql nvarchar(max) = N'',
        @azure_sql_db bit = 0,
        @azure_managed_instance bit = 0,
        @aws_rds bit = 0,
        @is_sysadmin bit =
            ISNULL
            (
                IS_SRVROLEMEMBER(N'sysadmin'),
                0
            ),
        @has_view_server_state bit =
        /*
            I'm using this as a shortcut here so I don't
            have to do anything else later if not sa
        */
            ISNULL
            (
                IS_SRVROLEMEMBER(N'sysadmin'),
                0
            ),
        @current_database_name sysname,
        @current_database_id integer,
        @processors integer,
        @message nvarchar(4000),
        /* Memory configuration variables */
        @min_server_memory bigint,
        @max_server_memory bigint,
        @physical_memory_gb decimal(10, 2),
        /* MAXDOP and CTFP variables */
        @max_dop integer,
        @cost_threshold integer,
        /* Other configuration variables */
        @priority_boost bit,
        @lightweight_pooling bit,
        @affinity_mask bigint,
        @affinity_io_mask bigint,
        @affinity64_mask bigint,
        @affinity64_io_mask bigint,
        /* TempDB configuration variables */
        @tempdb_data_file_count integer,
        @tempdb_log_file_count integer,
        @min_data_file_size decimal(18, 2),
        @max_data_file_size decimal(18, 2),
        @size_difference_pct decimal(18, 2),
        @has_percent_growth bit,
        @has_fixed_growth bit,
        /* Storage performance variables */
        @slow_read_ms decimal(10, 2) = 100.0, /* Threshold for slow reads (ms) */
        @slow_write_ms decimal(10, 2) = 100.0, /* Threshold for slow writes (ms) */
        /* Set threshold for "slow" autogrowth (in ms) */
        @slow_autogrow_ms integer = 1000,  /* 1 second */
        @trace_path nvarchar(260),
        @autogrow_summary nvarchar(max) = N'',
        @has_tables bit = 0,
        /* Determine total waits, uptime, and significant waits */
        @total_waits bigint,
        @uptime_ms bigint,
        @significant_wait_threshold_pct decimal(5, 2) = 0.5, /* Only waits above 0.5% */
        @significant_wait_threshold_avg decimal(10, 2) = 10.0, /* Or avg wait time > 10ms */
        /* Threshold settings for stolen memory alert */
        @buffer_pool_size_gb decimal(38, 2),
        @stolen_memory_gb decimal(38, 2),
        @stolen_memory_pct decimal(10, 2),
        @stolen_memory_threshold_pct decimal(10, 2) = 15.0, /* Alert if more than 15% memory is stolen */
        /* CPU scheduling variables */
        @signal_wait_time_ms bigint,
        @total_wait_time_ms bigint,
        @sos_scheduler_yield_ms bigint,
        @signal_wait_ratio decimal(10, 2),
        @sos_scheduler_yield_pct_of_uptime decimal(10, 2),
        /* I/O stalls variables */
        @io_stall_summary nvarchar(1000),
        /* First check what columns exist in sys.databases to handle version differences */
        @has_is_ledger bit = 0,
        @has_is_accelerated_database_recovery bit = 0,
        /*SQLDB stuff for IO stats*/
        @io_sql nvarchar(max) = N'',
        @file_io_sql nvarchar(max) = N'',
        @db_size_sql nvarchar(max) = N'',
        @tempdb_files_sql nvarchar(max) = N'';


    /* Check for VIEW SERVER STATE permission */
    IF @is_sysadmin = 0
    BEGIN
        BEGIN TRY
            EXECUTE sys.sp_executesql
                N'
                    SELECT
                        @has_view_server_state = 1
                    FROM sys.dm_os_sys_info AS osi;
                ',
                N'@has_view_server_state bit OUTPUT',
                  @has_view_server_state OUTPUT;
        END TRY
        BEGIN CATCH
            SET @has_view_server_state = 0;
        END CATCH;
    END;

    IF @debug = 1
    BEGIN
        SELECT
            permission_check = N'Permission Check',
            is_sysadmin = @is_sysadmin,
            has_view_server_state = @has_view_server_state;
    END;

    /*
    Environment Detection
    */

    /* Is this Azure SQL DB? */
    IF @engine_edition = 5
    BEGIN
        SET @azure_sql_db = 1;
    END;

    /* Is this Azure Managed Instance? */
    IF @engine_edition = 8
    BEGIN
        SET @azure_managed_instance = 1;
    END;

    /* Is this AWS RDS? Only check if not Azure */
    IF  @azure_sql_db = 0
    AND @azure_managed_instance = 0
    BEGIN
        IF DB_ID('rdsadmin') IS NOT NULL
        BEGIN
            SET @aws_rds = 1;
        END;
    END;

    IF @debug = 1
    BEGIN
        SELECT
            environment_check = N'Environment Check',
            product_version = @product_version,
            product_version_major = @product_version_major,
            engine_edition = @engine_edition,
            is_azure = @azure_sql_db,
            is_azure_managed_instance = @azure_managed_instance,
            is_aws_rds = @aws_rds;
    END;

    /*
    Create a table for stuff I care about from sys.databases
    With comments on what we want to check
    */
    CREATE TABLE
        #databases
    (
        name sysname NOT NULL,
        database_id integer NOT NULL,
        compatibility_level tinyint NOT NULL,
        collation_name sysname NULL,
        user_access_desc nvarchar(60) NOT NULL,
        is_read_only bit NOT NULL,
        is_auto_close_on bit NOT NULL,
        is_auto_shrink_on bit NOT NULL,
        state_desc nvarchar(60) NOT NULL,
        snapshot_isolation_state_desc nvarchar(60) NOT NULL,
        is_read_committed_snapshot_on bit NOT NULL,
        is_auto_create_stats_on bit NOT NULL,
        is_auto_create_stats_incremental_on bit NOT NULL,
        is_auto_update_stats_on bit NOT NULL,
        is_auto_update_stats_async_on bit NOT NULL,
        is_ansi_null_default_on bit NOT NULL,
        is_ansi_nulls_on bit NOT NULL,
        is_ansi_padding_on bit NOT NULL,
        is_ansi_warnings_on bit NOT NULL,
        is_arithabort_on bit NOT NULL,
        is_concat_null_yields_null_on bit NOT NULL,
        is_numeric_roundabort_on bit NOT NULL,
        is_quoted_identifier_on bit NOT NULL,
        is_parameterization_forced bit NOT NULL,
        is_query_store_on bit NOT NULL,
        is_distributor bit NOT NULL,
        is_cdc_enabled bit NOT NULL,
        target_recovery_time_in_seconds integer NULL,
        delayed_durability_desc nvarchar(60) NULL,
        is_accelerated_database_recovery_on bit NOT NULL,
        is_ledger_on bit NULL
    );

    /* Create table for database scoped configurations */
    CREATE TABLE
        #database_scoped_configs
    (
        database_id integer NOT NULL,
        database_name sysname NOT NULL,
        configuration_id integer NOT NULL,
        name nvarchar(60) NOT NULL,
        value sql_variant NULL,
        value_for_secondary sql_variant NULL,
        is_value_default bit NOT NULL
    );

    /*
    Create Results Table
    */
    CREATE TABLE
        #results
    (
        id integer IDENTITY PRIMARY KEY CLUSTERED,
        check_id integer NOT NULL,
        priority integer NOT NULL,
        category nvarchar(50) NOT NULL,
        finding nvarchar(200) NOT NULL,
        database_name sysname NOT NULL DEFAULT N'N/A',
        object_name sysname NOT NULL DEFAULT N'N/A',
        details nvarchar(4000) NULL,
        url nvarchar(200) NULL
    );

    /*
    Create Server Info Table
    */
    CREATE TABLE
        #server_info
    (
        id integer IDENTITY PRIMARY KEY CLUSTERED,
        info_type nvarchar(100) NOT NULL,
        value nvarchar(4000) NULL
    );

    /* Create temp table to store TempDB file info */
    CREATE TABLE
        #tempdb_files
    (
        file_id integer NOT NULL,
        file_name sysname NOT NULL,
        type_desc nvarchar(60) NOT NULL,
        size_mb decimal(18, 2) NOT NULL,
        max_size_mb decimal(18, 2) NOT NULL,
        growth_mb decimal(18, 2) NOT NULL,
        is_percent_growth bit NOT NULL
    );

    /* Create temp table for IO stats */
    CREATE TABLE
        #io_stats
    (
        database_name sysname NOT NULL,
        database_id integer NOT NULL,
        file_name sysname NOT NULL,
        type_desc nvarchar(60) NOT NULL,
        io_stall_read_ms bigint NOT NULL,
        num_of_reads bigint NOT NULL,
        avg_read_latency_ms decimal(18, 2) NOT NULL,
        io_stall_write_ms bigint NOT NULL,
        num_of_writes bigint NOT NULL,
        avg_write_latency_ms decimal(18, 2) NOT NULL,
        io_stall_ms bigint NOT NULL,
        total_io bigint NOT NULL,
        avg_io_latency_ms decimal(18, 2) NOT NULL,
        size_mb decimal(18, 2) NOT NULL,
        drive_location nvarchar(260) NULL,
        physical_name nvarchar(260) NOT NULL
    );

    /*
    Create Database List for Iteration
    */
    CREATE TABLE
        #database_list
    (
        id integer IDENTITY PRIMARY KEY CLUSTERED,
        database_name sysname NOT NULL,
        database_id integer NOT NULL,
        state integer NOT NULL,
        state_desc nvarchar(60) NOT NULL,
        compatibility_level integer NOT NULL,
        recovery_model_desc nvarchar(60) NOT NULL,
        is_read_only bit NOT NULL,
        is_in_standby bit NOT NULL,
        is_encrypted bit NOT NULL,
        create_date datetime NOT NULL,
        can_access bit NOT NULL
    );

    /* Create a temp table for trace flags */
    CREATE TABLE
        #trace_flags
    (
        trace_flag integer NOT NULL,
        status integer NOT NULL,
        global integer NOT NULL,
        session integer NOT NULL
    );

    /* Create temp table for trace events */
    CREATE TABLE
        #trace_events
    (
        id integer IDENTITY PRIMARY KEY CLUSTERED,
        event_time datetime NOT NULL,
        event_class integer NOT NULL,
        event_subclass integer NULL,
        event_name sysname NULL,
        category_name sysname NULL,
        database_name sysname NULL,
        database_id integer NULL,
        file_name nvarchar(260) NULL,
        object_name sysname NULL,
        object_type integer NULL,
        duration_ms bigint NULL,
        severity integer NULL,
        success bit NULL,
        error integer NULL,
        text_data nvarchar(MAX) NULL,
        file_growth bigint NULL,
        is_auto bit NULL,
        spid integer NOT NULL
    );

    /* Define event class mapping for more readable output */
    CREATE TABLE
        #event_class_map
    (
        event_class integer PRIMARY KEY CLUSTERED,
        event_name sysname NOT NULL,
        category_name sysname NOT NULL
    );

    /* Create temp table for wait stats */
    CREATE TABLE
        #wait_stats
    (
        id integer IDENTITY PRIMARY KEY CLUSTERED,
        wait_type nvarchar(60) NOT NULL,
        description nvarchar(100) NOT NULL,
        wait_time_ms bigint NOT NULL,
        wait_time_minutes AS (wait_time_ms / 1000.0 / 60.0),
        wait_time_hours AS (wait_time_ms / 1000.0 / 60.0 / 60.0),
        waiting_tasks_count bigint NOT NULL,
        avg_wait_ms AS (wait_time_ms / NULLIF(waiting_tasks_count, 0)),
        percentage decimal(5, 2) NOT NULL,
        signal_wait_time_ms bigint NOT NULL,
        wait_time_percent_of_uptime decimal(6, 2) NULL,
        category nvarchar(50) NOT NULL
    );

    /* Create temp table for database I/O stalls */
    CREATE TABLE
        #io_stalls_by_db
    (
        database_name sysname NOT NULL,
        database_id integer NOT NULL,
        total_io_stall_ms bigint NOT NULL,
        total_io_mb decimal(18, 2) NOT NULL,
        avg_io_stall_ms decimal(18, 2) NOT NULL,
        read_io_stall_ms bigint NOT NULL,
        read_io_mb decimal(18, 2) NOT NULL,
        avg_read_stall_ms decimal(18, 2) NOT NULL,
        write_io_stall_ms bigint NOT NULL,
        write_io_mb decimal(18, 2) NOT NULL,
        avg_write_stall_ms decimal(18, 2) NOT NULL,
        total_size_mb decimal(18, 2) NOT NULL
    );

    /*
    Collect basic server information (works on all platforms)
    */
    IF @debug = 1
    BEGIN
        RAISERROR('Collecting server information', 0, 1) WITH NOWAIT;
    END;

    /* Basic server information that works across all platforms */
    INSERT INTO
        #server_info
    (
        info_type,
        value
    )
    VALUES
        (N'sp_PerfCheck', N'Brought to you by Darling Data');

    INSERT INTO
        #server_info
    (
        info_type,
        value
    )
    VALUES
        (N'https://code.erikdarling.com', N'https://erikdarling.com');

    INSERT INTO
        #server_info
    (
        info_type,
        value
    )
    VALUES
    (
        N'Version',
        @version +
        N' (' +
        CONVERT
        (
            varchar(10),
            @version_date,
            101
        ) +
        N')'
    );

    /* Using server name variable declared earlier */
    INSERT INTO
        #server_info
    (
        info_type,
        value
    )
    VALUES
        (N'Server Name', @server_name);

    /* Using product version and level variables declared earlier */
    INSERT INTO
        #server_info
    (
        info_type,
        value
    )
    VALUES
    (
        N'SQL Server Version',
        @product_version +
        N' (' +
        @product_level +
        N')'
    );

    /* Using product edition variable declared earlier */
    INSERT INTO
        #server_info
    (
        info_type,
        value
    )
    VALUES
        (N'SQL Server Edition', @product_edition);

    /* Environment information - Already detected earlier */
    INSERT INTO
        #server_info
    (
        info_type,
        value
    )
    SELECT
        N'Environment',
        CASE
            WHEN @azure_sql_db = 1
            THEN N'Azure SQL Database'
            WHEN @azure_managed_instance = 1
            THEN N'Azure SQL Managed Instance'
            WHEN @aws_rds = 1
            THEN N'AWS RDS SQL Server'
            ELSE N'On-premises or IaaS SQL Server'
        END;

    /* Uptime information - works on all platforms if permissions allow */
    IF @has_view_server_state = 1
    BEGIN
        INSERT INTO
            #server_info
        (
            info_type,
            value
        )
        SELECT
            N'Uptime',
            CONVERT
            (
                nvarchar(30),
                DATEDIFF
                (
                    DAY,
                    osi.sqlserver_start_time,
                    SYSDATETIME()
                )
            ) +
            N' days, ' +
            CONVERT
            (
                nvarchar(8),
                CONVERT
                (
                    time,
                    DATEADD
                    (
                        SECOND,
                        DATEDIFF
                        (
                            SECOND,
                            osi.sqlserver_start_time,
                            SYSDATETIME()
                        ) % 86400,
                        '00:00:00'
                    )
                ),
                108
            ) +
            N' (hh:mm:ss)'
        FROM sys.dm_os_sys_info AS osi;
    END
    ELSE
    BEGIN
        INSERT INTO
            #server_info
        (
            info_type,
            value
        )
        VALUES
            (N'Uptime', N'Information unavailable (requires VIEW SERVER STATE permission)');
    END;

    /* CPU information - works on all platforms if permissions allow */
    IF @has_view_server_state = 1
    BEGIN
        INSERT INTO
            #server_info
        (
            info_type,
            value
        )
        SELECT
            N'CPU',
            CONVERT(nvarchar(10), osi.cpu_count) +
            N' logical processors, ' +
            CONVERT(nvarchar(10), osi.hyperthread_ratio) +
            N' physical cores, ' +
            CONVERT(nvarchar(10), ISNULL(osi.numa_node_count, 1)) +
            N' NUMA node(s)'
        FROM sys.dm_os_sys_info AS osi;
    END
    ELSE
    BEGIN
        INSERT INTO
            #server_info
        (
            info_type,
            value
        )
        VALUES
            (N'CPU', N'Information unavailable (requires VIEW SERVER STATE permission)');
    END;

    /* Check for offline schedulers */
    IF @azure_sql_db = 0 /* Not applicable to Azure SQL DB */
    AND @has_view_server_state = 1 /* Requires VIEW SERVER STATE permission */
    BEGIN
        INSERT INTO
            #results
        (
            check_id,
            priority,
            category,
            finding,
            details,
            url
        )
        SELECT
            check_id = 4001,
            priority = 20, /* Very high priority */
            category = N'CPU Configuration',
            finding = N'Offline CPU Schedulers',
            details =
                CONVERT(nvarchar(10), COUNT_BIG(*)) +
                N' CPU scheduler(s) are offline out of ' +
                CONVERT(nvarchar(10), (SELECT cpu_count FROM sys.dm_os_sys_info)) +
                N' logical processors. This reduces available processing power. ' +
                N'Check affinity mask configuration, licensing, or VM CPU cores/sockets',
            url = N'https://erikdarling.com/sp_PerfCheck/#OfflineCPU'
        FROM sys.dm_os_schedulers AS dos
        WHERE dos.is_online = 0
        HAVING
            COUNT_BIG(*) > 0; /* Only if there are offline schedulers */
    END;

    /* Check for forced grants - requires VIEW SERVER STATE permission */
    IF @has_view_server_state = 1
    BEGIN
        INSERT INTO
            #results
        (
            check_id,
            priority,
            category,
            finding,
            details,
            url
        )
        SELECT
            check_id = 4101,
            priority = 30, /* High priority */
            category = N'Memory Pressure',
            finding = N'Memory-Starved Queries Detected',
            details =
                N'dm_exec_query_resource_semaphores has ' +
                CONVERT(nvarchar(10), MAX(ders.forced_grant_count)) +
                N' forced memory grants. ' +
                N'Queries are being forced to run with less memory than requested, which can cause spills to tempdb and poor performance.',
            url = N'https://erikdarling.com/sp_PerfCheck#MemoryStarved'
        FROM sys.dm_exec_query_resource_semaphores AS ders
        WHERE ders.forced_grant_count > 0
        HAVING
            MAX(ders.forced_grant_count) > 0; /* Only if there are actually forced grants */
    END;

    /* Check for memory grant timeouts - requires VIEW SERVER STATE permission */
    IF @has_view_server_state = 1
    BEGIN
        INSERT INTO
            #results
        (
            check_id,
            priority,
            category,
            finding,
            details,
            url
        )
        SELECT
            check_id = 4103,
            priority = 30, /* High priority */
            category = N'Memory Pressure',
            finding = N'Memory-Starved Queries Detected',
            details =
                N'dm_exec_query_resource_semaphores has ' +
                CONVERT(nvarchar(10), MAX(ders.timeout_error_count)) +
                N' memory grant timeouts. ' +
                N'Queries are waiting for memory for a long time and giving up.',
            url = N'https://erikdarling.com/sp_PerfCheck#MemoryStarved'
        FROM sys.dm_exec_query_resource_semaphores AS ders
        WHERE ders.timeout_error_count > 0
        HAVING
            MAX(ders.timeout_error_count) > 0; /* Only if there are actually forced grants */
    END;

    /* Check for SQL Server memory dumps (on-prem only) */
    IF  @azure_sql_db = 0
    AND @azure_managed_instance = 0
    AND @has_view_server_state = 1 /* Requires sysadmin permission */
    BEGIN
        /* First check if the DMV exists (SQL 2008+) */
        IF OBJECT_ID('sys.dm_server_memory_dumps') IS NOT NULL
        BEGIN
            INSERT INTO
                #results
            (
                check_id,
                priority,
                category,
                finding,
                details,
                url
            )
            SELECT
                check_id = 4102,
                priority = 20, /* Very high priority */
                category = N'Server Stability',
                finding = N'Memory Dumps Detected In Last 90 Days',
                details =
                    CONVERT(nvarchar(10), COUNT_BIG(*)) +
                    N' memory dump(s) found. Most recent: ' +
                    CONVERT(nvarchar(30), MAX(dsmd.creation_time), 120) +
                    N', ' +
                    N' at ' +
                    MAX(dsmd.filename) +
                    N'. Check the SQL Server error log and Windows event logs.',
                url = N'https://erikdarling.com/sp_PerfCheck#MemoryDumps'
            FROM sys.dm_server_memory_dumps AS dsmd
            WHERE dsmd.creation_time >= DATEADD(DAY, -90, SYSDATETIME())
            HAVING
                COUNT_BIG(*) > 0; /* Only if there are memory dumps */
        END;
    END;

    /* Check for high number of deadlocks */
    INSERT INTO
        #results
    (
        check_id,
        priority,
        category,
        finding,
        details,
        url
    )
    SELECT
        check_id = 4103,
        priority =
            CASE
                WHEN
                (
                    1.0 *
                    p.cntr_value /
                    NULLIF
                    (
                        DATEDIFF
                        (
                            DAY,
                            osi.sqlserver_start_time,
                            SYSDATETIME()
                        ),
                        0
                    )
                ) > 100
                THEN 20 /* Very high priority */
                WHEN
                (
                    1.0 *
                    p.cntr_value /
                    NULLIF
                    (
                        DATEDIFF
                        (
                            DAY,
                            osi.sqlserver_start_time,
                            SYSDATETIME()
                        ),
                        0
                    )
                ) > 50
                THEN 30 /* High priority */
                ELSE 40 /* Medium-high priority */
            END,
        category = N'Concurrency',
        finding = N'High Number of Deadlocks',
        details =
            N'Server is averaging ' +
            CONVERT(nvarchar(20), CONVERT(decimal(10, 2), 1.0 * p.cntr_value /
              NULLIF(DATEDIFF(DAY, osi.sqlserver_start_time, SYSDATETIME()), 0))) +
            N' deadlocks per day since startup (' +
            CONVERT(nvarchar(20), p.cntr_value) +
            ' total deadlocks over ' +
            CONVERT(nvarchar(10), DATEDIFF(DAY, osi.sqlserver_start_time, SYSDATETIME())) +
            N' days). ' +
            N'High deadlock rates indicate concurrency issues that should be investigated.',
        url = N'https://erikdarling.com/sp_PerfCheck#Deadlocks'
    FROM sys.dm_os_performance_counters AS p
    CROSS JOIN sys.dm_os_sys_info AS osi
    WHERE RTRIM(p.counter_name) = N'Number of Deadlocks/sec'
    AND   RTRIM(p.instance_name) = N'_Total'
    AND   p.cntr_value > 0
    AND
    (
        1.0 *
        p.cntr_value /
        NULLIF
        (
            DATEDIFF
            (
                DAY,
                osi.sqlserver_start_time,
                SYSDATETIME()
            ),
            0
        )
    ) > 9; /* More than 9 deadlocks per day */

    /* Check for large USERSTORE_TOKENPERM (security cache) */
    INSERT INTO
        #results
    (
        check_id,
        priority,
        category,
        finding,
        details,
        url
    )
    SELECT
        check_id = 4104,
        priority =
            CASE
                WHEN CONVERT(decimal(10, 2), (domc.pages_kb / 1024.0 / 1024.0)) > 5
                THEN 20 /* Very high priority >5GB */
                WHEN CONVERT(decimal(10, 2), (domc.pages_kb / 1024.0 / 1024.0)) BETWEEN 3 AND 5
                THEN 30 /* High priority >2GB */
                WHEN CONVERT(decimal(10, 2), (domc.pages_kb / 1024.0 / 1024.0)) BETWEEN 1 AND 2
                THEN 40 /* Medium-high priority >1GB */
                ELSE 50 /* Medium priority */
            END,
        category = N'Memory Usage',
        finding = N'Large Security Token Cache',
        details =
            N'TokenAndPermUserStore cache size is ' +
            CONVERT(nvarchar(20), CONVERT(decimal(10, 2), (domc.pages_kb / 1024.0 / 1024.0))) +
            N' GB. Large security caches can consume significant memory and may indicate security-related issues ' +
            N'such as excessive application role usage or frequent permission changes. ' +
            N'Consider using dbo.ClearTokenPerm stored procedure to manage this issue.',
        url = N'https://erikdarling.com/sp_PerfCheck#SecurityToken'
    FROM sys.dm_os_memory_clerks AS domc
    WHERE domc.type = N'USERSTORE_TOKENPERM'
    AND   domc.name = N'TokenAndPermUserStore'
    AND   domc.pages_kb >= 500000; /* Only if bigger than 500MB */

    /* Check if Lock Pages in Memory is enabled (on-prem and managed instances only) */
    IF  @azure_sql_db = 0
    AND @has_view_server_state = 1
    BEGIN
        INSERT INTO
            #results
        (
            check_id,
            priority,
            category,
            finding,
            details,
            url
        )
        SELECT
            check_id = 4105,
            priority = 50, /* Medium priority */
            category = N'Memory Configuration',
            finding = N'Lock Pages in Memory Not Enabled',
            details =
                N'SQL Server is not using locked pages in memory (LPIM). This can lead to Windows ' +
                N'taking memory away from SQL Server under memory pressure, causing performance issues. ' +
                N'For production SQL Servers with more than 64GB of memory, LPIM should be enabled.',
            url = N'https://erikdarling.com/sp_PerfCheck#LPIM'
        FROM sys.dm_os_sys_info AS osi
        WHERE osi.sql_memory_model_desc = N'CONVENTIONAL' /* Conventional means not using LPIM */
        AND   @physical_memory_gb >= 32 /* Only recommend for servers with >=32GB RAM */;

        INSERT
            #server_info
        (
            info_type,
            value
        )
        SELECT
            N'Memory Model',
            osi.sql_memory_model_desc
        FROM sys.dm_os_sys_info AS osi;
    END;

    /* Check if Instant File Initialization is enabled (on-prem only) */
    IF  @azure_sql_db = 0
    AND @azure_managed_instance = 0
    AND @aws_rds = 0
    AND @has_view_server_state = 1
    BEGIN
        INSERT INTO
            #server_info
        (
            info_type,
            value
        )
        SELECT
            N'Instant File Initialization',
            CASE
                WHEN dss.instant_file_initialization_enabled = N'Y'
                THEN N'Enabled'
                ELSE N'Disabled'
            END
        FROM sys.dm_server_services AS dss
        WHERE dss.filename LIKE N'%sqlservr.exe%'
        AND   dss.servicename LIKE N'SQL Server%';

        INSERT INTO
            #results
        (
            check_id,
            priority,
            category,
            finding,
            details,
            url
        )
        SELECT TOP (1)
            check_id = 4106,
            priority = 50, /* Medium priority */
            category = N'Storage Configuration',
            finding = N'Instant File Initialization Disabled',
            details =
                N'Instant File Initialization is not enabled. This can significantly slow down database file ' +
                N'creation and growth operations, as SQL Server must zero out data files before using them. ' +
                N'Enable this feature by granting the "Perform Volume Maintenance Tasks" permission to the SQL Server service account.',
            url = N'https://erikdarling.com/sp_PerfCheck#IFI'
        FROM sys.dm_server_services AS dss
        WHERE dss.filename LIKE N'%sqlservr.exe%'
        AND   dss.servicename LIKE N'SQL Server%'
        AND   dss.instant_file_initialization_enabled = N'N';
    END;

    /* Check if Resource Governor is enabled, leaving this check open for all versions */
    IF @has_view_server_state = 1
    BEGIN
        /* First, add Resource Governor status to server info */
        IF EXISTS (SELECT 1/0 FROM sys.resource_governor_configuration AS rgc WHERE rgc.is_enabled = 1)
        BEGIN
            INSERT INTO
                #server_info
            (
                info_type,
                value
            )
            SELECT
                N'Resource Governor',
                N'Enabled';

            /* Add informational message about Resource Governor with query suggestion */
            INSERT INTO
                #results
            (
                check_id,
                priority,
                category,
                finding,
                details,
                url
            )
            SELECT
                check_id = 4107,
                priority = 50, /* Medium priority */
                category = N'Resource Governor',
                finding = N'Resource Governor Enabled',
                details =
                    N'Resource Governor is enabled on this instance. This affects workload resource allocation and may ' +
                    N'impact performance by limiting resources available to various workloads. ' +
                    N'For more details, run these queries to explore your configuration:' + NCHAR(13) + NCHAR(10) +
                    N'/* Resource Governor configuration */' + NCHAR(13) + NCHAR(10) +
                    N'SELECT c.* FROM sys.resource_governor_configuration AS c;' + NCHAR(13) + NCHAR(10) +
                    N'/* Resource pools and their settings */' + NCHAR(13) + NCHAR(10) +
                    N'SELECT p.* FROM sys.dm_resource_governor_resource_pools AS p;' + NCHAR(13) + NCHAR(10) +
                    N'/* Workload groups and their settings */' + NCHAR(13) + NCHAR(10) +
                    N'SELECT wg.* FROM sys.dm_resource_governor_workload_groups AS wg;' + NCHAR(13) + NCHAR(10) +
                    N'/* Classifier function (if configured) */' + NCHAR(13) + NCHAR(10) +
                    N'SELECT cf.* FROM sys.resource_governor_configuration AS gc' + NCHAR(13) + NCHAR(10) +
                    N'CROSS APPLY (SELECT OBJECT_NAME(gc.classifier_function_id) AS classifier_function_name) AS cf;',
                url = N'https://erikdarling.com/sp_PerfCheck#ResourceGovernor'
            FROM sys.resource_governor_configuration AS rgc
            WHERE rgc.is_enabled = 1;
        END
        ELSE
        BEGIN
            INSERT INTO
                #server_info
            (
                info_type,
                value
            )
            SELECT
                N'Resource Governor',
                N'Disabled';
        END;
    END;

    /* Check for globally enabled trace flags (not in Azure) */
    IF  @azure_sql_db = 0
    AND @azure_managed_instance = 0
    AND @aws_rds = 0
    BEGIN
        /* Capture trace flags */
        BEGIN TRY
            INSERT INTO
                #trace_flags
            (
                trace_flag,
                status,
                global,
                session
            )
            EXECUTE sys.sp_executesql
                N'DBCC TRACESTATUS WITH NO_INFOMSGS';
        END TRY
        BEGIN CATCH
            IF @debug = 1
            BEGIN
                SET @error_message = N'Error capturing trace flags: ' + ERROR_MESSAGE();
                PRINT @error_message;
            END;

            /* Log error in results */
            INSERT INTO #results
            (
                check_id,
                priority,
                category,
                finding,
                details
            )
            VALUES
            (
                9998,
                90, /* Low priority informational */
                N'Errors',
                N'Error Capturing Trace Flags',
                N'Unable to capture trace flags: ' + ERROR_MESSAGE()
            );
        END CATCH;

        /* Add trace flags to server info */
        IF EXISTS (SELECT 1/0 FROM #trace_flags AS tf WHERE tf.global = 1)
        BEGIN
            INSERT INTO
                #server_info
            (
                info_type,
                value
            )
            SELECT
                N'Global Trace Flags',
                STUFF
                (
                    (
                        SELECT
                            N', ' +
                            CONVERT(varchar(10), tf.trace_flag)
                        FROM #trace_flags AS tf
                        WHERE tf.global = 1
                        ORDER BY
                            tf.trace_flag
                        FOR
                            XML
                            PATH('')
                    ),
                    1,
                    2,
                    N''
                );
        END;
    END;

    /* Memory information - works on all platforms */
    INSERT INTO
        #server_info
    (
        info_type,
        value
    )
    SELECT
        N'Memory',
        N'Total: ' +
        CONVERT
        (
            nvarchar(20),
            CONVERT
            (
                decimal(10, 2),
                osi.physical_memory_kb / 1024.0 / 1024.0
            )
        ) +
        N' GB, ' +
        N'Target: ' +
        CONVERT
        (
            nvarchar(20),
            CONVERT
            (
                decimal(10, 2),
                osi.committed_target_kb / 1024.0 / 1024.0
            )
        ) +
        N' GB'
    FROM sys.dm_os_sys_info AS osi;

    /* Check for important events in default trace (Windows only for now) */
    IF  @azure_sql_db = 0
    BEGIN
        /* Get default trace path */
        BEGIN TRY
            SELECT
                @trace_path =
                    REVERSE
                    (
                        SUBSTRING
                        (
                            REVERSE(t.path),
                            CHARINDEX
                            (
                                CHAR(92),
                                REVERSE(t.path)
                            ),
                            260
                        )
                    ) + N'log.trc'
            FROM sys.traces AS t
            WHERE t.is_default = 1;
        END TRY
        BEGIN CATCH
            SET @trace_path = NULL;

            INSERT
                #results
            (
                check_id,
                priority,
                category,
                finding,
                database_name,
                object_name,
                details,
                url
            )
            VALUES
            (
                5001,
                50,
                N'Default Trace Permissions',
                N'Inadequate permissions',
                N'N/A',
                N'System Trace',
                N'Access to sys.traces is only available to accounts with elevated privileges, or when explicitly granted',
                N'GRANT ALTER TRACE TO ' +
                SUSER_NAME() +
                N';'
            );
        END CATCH;

        IF @trace_path IS NOT NULL
        BEGIN
            /* Insert common event classes we're interested in */
            INSERT INTO
                #event_class_map
            (
                event_class,
                event_name,
                category_name
            )
            VALUES
                (92,  N'Data File Auto Grow',   N'Database'),
                (93,  N'Log File Auto Grow',    N'Database'),
                (94,  N'Data File Auto Shrink', N'Database'),
                (95,  N'Log File Auto Shrink',  N'Database'),
                (116, N'DBCC Event',            N'Database'),
                (137, N'Server Memory Change',  N'Server');

            /* Get relevant events from default trace */
            INSERT INTO
                #trace_events
            (
                event_time,
                event_class,
                event_subclass,
                database_name,
                database_id,
                file_name,
                object_name,
                object_type,
                duration_ms,
                severity,
                success,
                error,
                text_data,
                file_growth,
                is_auto,
                spid
            )
            SELECT
                event_time = t.StartTime,
                event_class = t.EventClass,
                event_subclass = t.EventSubClass,
                database_name = DB_NAME(t.DatabaseID),
                database_id = t.DatabaseID,
                file_name = t.FileName,
                object_name = t.ObjectName,
                object_type = t.ObjectType,
                duration_ms = t.Duration / 1000, /* Duration is in microseconds, convert to ms */
                severity = t.Severity,
                success = t.Success,
                error = t.Error,
                text_data = t.TextData,
                file_growth = t.IntegerData, /* Size of growth in Data/Log Auto Grow event */
                is_auto = t.IsSystem,
                spid = t.SPID
            FROM sys.fn_trace_gettable(@trace_path, DEFAULT) AS t
            WHERE
                /* Auto-grow and auto-shrink events */
                t.EventClass IN (92, 93, 94, 95)
                /* DBCC Events */
                OR
                (
                      t.EventClass = 116
                  AND
                  (
                         t.TextData LIKE N'%FREEPROCCACHE%'
                      OR t.TextData LIKE N'%FREESYSTEMCACHE%'
                      OR t.TextData LIKE N'%DROPCLEANBUFFERS%'
                      OR t.TextData LIKE N'%SHRINKDATABASE%'
                      OR t.TextData LIKE N'%SHRINKFILE%'
                      OR t.TextData LIKE N'%WRITEPAGE%'
                  )
                )
                /* Server memory change events */
                OR t.EventClass = 137
                /* Deadlock events - typically not in default trace but including for completeness */
                OR t.EventClass = 148
                /* Look back at the past 7 days of events at most */
                AND t.StartTime > DATEADD(DAY, -7, SYSDATETIME());

            /* Update event names from map */
            UPDATE
                te
            SET
                te.event_name = m.event_name,
                te.category_name = m.category_name
            FROM #trace_events AS te
            JOIN #event_class_map AS m
              ON te.event_class = m.event_class;

            /* Check for slow autogrow events */
            INSERT INTO
                #results
            (
                check_id,
                priority,
                category,
                finding,
                database_name,
                object_name,
                details,
                url
            )
            SELECT TOP (10)
                check_id = 5001,
                priority =
                    CASE
                        WHEN te.event_class = 93
                        THEN 40 /* Log file autogrow (higher priority) */
                        ELSE 50 /* Data file autogrow */
                    END,
                category = N'Database File Configuration',
                finding =
                    CASE
                        WHEN te.event_class = 92
                        THEN N'Slow Data File Auto Grow'
                        WHEN te.event_class = 93
                        THEN N'Slow Log File Auto Grow'
                        ELSE N'Slow File Auto Grow'
                    END,
                database_name = te.database_name,
                object_name = te.file_name,
                details =
                    N'Auto grow operation took ' +
                    CONVERT(nvarchar(20), te.duration_ms) +
                    N' ms (' +
                    CONVERT(nvarchar(20), te.duration_ms / 1000.0) +
                    N' seconds) on ' +
                    CONVERT(nvarchar(30), te.event_time, 120) +
                    N'. ' +
                    N'Growth amount: ' +
                    CONVERT(nvarchar(20), te.file_growth / 1048576) +
                    N' GB. ',
                url = N'https://erikdarling.com/sp_PerfCheck#AutoGrowth'
            FROM #trace_events AS te
            WHERE te.event_class IN (92, 93) /* Auto-grow events */
            AND   te.duration_ms > @slow_autogrow_ms
            ORDER BY
                te.duration_ms DESC;

            /* Check for auto-shrink events */
            INSERT INTO
                #results
            (
                check_id,
                priority,
                category,
                finding,
                database_name,
                object_name,
                details,
                url
            )
            SELECT TOP (10)
                check_id = 5002,
                priority = 60, /* Medium priority */
                category = N'Database File Configuration',
                finding =
                    CASE
                        WHEN te.event_class = 94
                        THEN N'Data File Auto Shrink'
                        WHEN te.event_class = 95
                        THEN N'Log File Auto Shrink'
                        ELSE N'File Auto Shrink'
                    END,
                database_name = te.database_name,
                object_name = te.file_name,
                details =
                    N'Auto shrink operation occurred on ' +
                    CONVERT(nvarchar(30), te.event_time, 120) +
                    N'. ' +
                    N'Auto-shrink is generally not recommended as it can lead to file fragmentation and ' +
                    N'repeated grow/shrink cycles. Consider disabling auto-shrink on this database.',
                url = N'https://erikdarling.com/sp_PerfCheck#AutoShrink'
            FROM #trace_events AS te
            WHERE te.event_class IN (94, 95) /* Auto-shrink events */
            ORDER BY
                te.event_time DESC;

            /* Check for potentially problematic DBCC commands - group by command type */
            INSERT INTO
                #results
            (
                check_id,
                priority,
                category,
                finding,
                database_name,
                details,
                url
            )
            SELECT TOP (10)
                5003,
                priority =
                    CASE
                        WHEN dbcc_cmd.dbcc_pattern LIKE N'%FREEPROCCACHE%'
                        OR   dbcc_cmd.dbcc_pattern LIKE N'%FREESYSTEMCACHE%'
                        OR   dbcc_cmd.dbcc_pattern LIKE N'%DROPCLEANBUFFERS%'
                        OR   dbcc_cmd.dbcc_pattern LIKE N'%WRITEPAGE%'
                        THEN 40 /* Higher priority */
                        ELSE 60 /* Medium priority */
                    END,
                N'System Management',
                N'Potentially Disruptive DBCC Commands',
                MAX(te.database_name),
                N'Found ' +
                CONVERT(nvarchar(20), COUNT_BIG(*)) +
                N' instances of "' +
                CASE
                    WHEN te.text_data LIKE N'%FREEPROCCACHE%' THEN N'DBCC FREEPROCCACHE'
                    WHEN te.text_data LIKE N'%FREESYSTEMCACHE%' THEN N'DBCC FREESYSTEMCACHE'
                    WHEN te.text_data LIKE N'%DROPCLEANBUFFERS%' THEN N'DBCC DROPCLEANBUFFERS'
                    WHEN te.text_data LIKE N'%SHRINKDATABASE%' THEN N'DBCC SHRINKDATABASE'
                    WHEN te.text_data LIKE N'%SHRINKFILE%' THEN N'DBCC SHRINKFILE'
                    WHEN te.text_data LIKE N'%WRITEPAGE%' THEN N'DBCC WRITEPAGE'
                    ELSE LEFT(te.text_data, 40) /* Take first 40 chars for other commands just in case */
                END +
                N'" between ' +
                CONVERT(nvarchar(30), MIN(te.event_time), 120) +
                N' and ' +
                CONVERT(nvarchar(30), MAX(te.event_time), 120) +
                N'. These commands can impact server performance or database integrity. ' +
                N'Review why these commands are being executed, especially if on a production system.',
                N'https://erikdarling.com/sp_PerfCheck/#DisruptiveDBCC'
            FROM #trace_events AS te
            CROSS APPLY
            (
                SELECT dbcc_pattern =
                    CASE
                        WHEN te.text_data LIKE N'%FREEPROCCACHE%' THEN N'DBCC FREEPROCCACHE'
                        WHEN te.text_data LIKE N'%FREESYSTEMCACHE%' THEN N'DBCC FREESYSTEMCACHE'
                        WHEN te.text_data LIKE N'%DROPCLEANBUFFERS%' THEN N'DBCC DROPCLEANBUFFERS'
                        WHEN te.text_data LIKE N'%SHRINKDATABASE%' THEN N'DBCC SHRINKDATABASE'
                        WHEN te.text_data LIKE N'%SHRINKFILE%' THEN N'DBCC SHRINKFILE'
                        WHEN te.text_data LIKE N'%WRITEPAGE%' THEN N'DBCC WRITEPAGE'
                        ELSE LEFT(te.text_data, 40) /* Take first 40 chars for other commands just in case*/
                    END
            ) AS dbcc_cmd
            WHERE te.event_class = 116 /* DBCC events */
            AND   te.text_data IS NOT NULL
            GROUP BY
                dbcc_cmd.dbcc_pattern,
                CASE
                    WHEN te.text_data LIKE N'%FREEPROCCACHE%' THEN N'DBCC FREEPROCCACHE'
                    WHEN te.text_data LIKE N'%FREESYSTEMCACHE%' THEN N'DBCC FREESYSTEMCACHE'
                    WHEN te.text_data LIKE N'%DROPCLEANBUFFERS%' THEN N'DBCC DROPCLEANBUFFERS'
                    WHEN te.text_data LIKE N'%SHRINKDATABASE%' THEN N'DBCC SHRINKDATABASE'
                    WHEN te.text_data LIKE N'%SHRINKFILE%' THEN N'DBCC SHRINKFILE'
                    WHEN te.text_data LIKE N'%WRITEPAGE%' THEN N'DBCC WRITEPAGE'
                    ELSE LEFT(te.text_data, 40) /* Take first 40 chars for other commands just i case*/
                END
            ORDER BY
                COUNT_BIG(*) DESC;

            /* Get summary of SLOW autogrow events for server_info */
            SELECT @autogrow_summary =
                STUFF
                (
                    (
                        SELECT TOP (5)
                            N', ' +
                            CONVERT
                            (
                                nvarchar(50),
                                COUNT_BIG(*)
                            ) +
                            N' slow ' +
                            CASE
                                WHEN te.event_class = 92
                                THEN N'data file'
                                WHEN te.event_class = 93
                                THEN N'log file'
                            END +
                            N' autogrows' +
                            N' (avg ' +
                            CONVERT
                            (
                                nvarchar(20),
                                AVG(te.duration_ms) / 1000.0
                            ) +
                            N' sec)'
                        FROM #trace_events AS te
                        WHERE te.event_class IN (92, 93) /* Auto-grow events */
                        AND   te.duration_ms > @slow_autogrow_ms /* Only slow auto-grows */
                        GROUP BY
                            te.event_class
                        ORDER BY
                            te.event_class
                        FOR
                            XML
                            PATH('')
                    ),
                    1,
                    2,
                    N''
                );

            IF @autogrow_summary IS NOT NULL
            BEGIN
                INSERT INTO
                    #server_info
                (
                    info_type,
                    value
                )
                VALUES
                    (N'Slow Autogrow Events (7 days)', @autogrow_summary);
            END;
        END;
    END;

    /* Check for significant wait stats */
    IF @has_view_server_state = 1
    BEGIN
        /* Get uptime */
        SELECT
            @uptime_ms =
                CASE
                    WHEN DATEDIFF(DAY, osi.sqlserver_start_time, SYSDATETIME()) >= 24
                    THEN DATEDIFF(SECOND, osi.sqlserver_start_time, SYSDATETIME()) * 1000.
                    ELSE DATEDIFF(MILLISECOND, osi.sqlserver_start_time, SYSDATETIME())
                END
        FROM sys.dm_os_sys_info AS osi;

        /* Get total wait time */
        SELECT
            @total_waits =
                SUM
                (
                    CONVERT
                    (
                        bigint,
                        osw.wait_time_ms
                    )
                )
        FROM sys.dm_os_wait_stats AS osw
        WHERE osw.wait_type NOT IN
        (
            /* Skip benign waits based on sys.dm_os_wait_stats documentation */
            N'BROKER_TASK_STOP',
            N'BROKER_TO_FLUSH',
            N'BROKER_TRANSMITTER',
            N'CHECKPOINT_QUEUE',
            N'CLR_AUTO_EVENT',
            N'CLR_MANUAL_EVENT',
            N'DIRTY_PAGE_POLL',
            N'DISPATCHER_QUEUE_SEMAPHORE',
            N'FSAGENT',
            N'FT_IFTS_SCHEDULER_IDLE_WAIT',
            N'FT_IFTSHC_MUTEX',
            N'HADR_FILESTREAM_IOMGR_IOCOMPLETION',
            N'HADR_LOGCAPTURE_WAIT',
            N'HADR_TIMER_TASK',
            N'HADR_WORK_QUEUE',
            N'LAZYWRITER_SLEEP',
            N'LOGMGR_QUEUE',
            N'MEMORY_ALLOCATION_EXT',
            N'PREEMPTIVE_XE_GETTARGETSTATE',
            N'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP',
            N'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP',
            N'REQUEST_FOR_DEADLOCK_SEARCH',
            N'RESOURCE_QUEUE',
            N'SERVER_IDLE_CHECK',
            N'SLEEP_DBSTARTUP',
            N'SLEEP_DCOMSTARTUP',
            N'SLEEP_MASTERDBREADY',
            N'SLEEP_MASTERMDREADY',
            N'SLEEP_MASTERUPGRADED',
            N'SLEEP_MSDBSTARTUP',
            N'SLEEP_SYSTEMTASK',
            N'SLEEP_TEMPDBSTARTUP',
            N'SNI_HTTP_ACCEPT',
            N'SP_SERVER_DIAGNOSTICS_SLEEP',
            N'SQLTRACE_BUFFER_FLUSH',
            N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP',
            N'SQLTRACE_WAIT_ENTRIES',
            N'STARTUP_DEPENDENCY_MANAGER',
            N'WAIT_FOR_RESULTS',
            N'WAITFOR',
            N'WAITFOR_TASKSHUTDOWN',
            N'WAIT_XTP_HOST_WAIT',
            N'WAIT_XTP_OFFLINE_CKPT_NEW_LOG',
            N'WAIT_XTP_CKPT_CLOSE',
            N'XE_DISPATCHER_JOIN',
            N'XE_DISPATCHER_WAIT',
            N'XE_LIVE_TARGET_TVF',
            N'XE_TIMER_EVENT'
        );

        /* Insert important waits into the temp table */
        INSERT INTO
            #wait_stats
        (
            wait_type,
            description,
            wait_time_ms,
            waiting_tasks_count,
            signal_wait_time_ms,
            percentage,
            category
        )
        SELECT
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
                    ELSE N'Other significant wait type'
                END,
            wait_time_ms = dows.wait_time_ms,
            waiting_tasks_count = dows.waiting_tasks_count,
            signal_wait_time_ms = dows.signal_wait_time_ms,
            percentage =
                CONVERT
                (
                    decimal(5,2),
                    dows.wait_time_ms * 100.0 / @total_waits
                ),
            category =
                CASE
                    WHEN dows.wait_type IN (N'PAGEIOLATCH_SH', N'PAGEIOLATCH_EX', N'IO_COMPLETION', N'IO_RETRY')
                    THEN N'I/O'
                    WHEN dows.wait_type IN (N'RESOURCE_SEMAPHORE', N'RESOURCE_SEMAPHORE_QUERY_COMPILE', N'CMEMTHREAD', N'SLEEP_BPOOL_STEAL')
                    THEN N'Memory'
                    WHEN dows.wait_type IN (N'CXPACKET', N'CXCONSUMER', N'CXSYNC_PORT', N'CXSYNC_CONSUMER')
                    THEN N'Parallelism'
                    WHEN dows.wait_type IN (N'SOS_SCHEDULER_YIELD', N'THREADPOOL', N'RESOURCE_GOVERNOR_IDLE')
                    THEN N'CPU'
                    WHEN dows.wait_type IN (N'PAGELATCH_EX', N'PAGELATCH_SH', N'PAGELATCH_UP')
                    THEN N'TempDB Contention'
                    WHEN dows.wait_type LIKE N'LCK%'
                    THEN N'Locking'
                    WHEN dows.wait_type IN (N'WRITELOG', N'LOGBUFFER', N'LOG_RATE_GOVERNOR', N'POOL_LOG_RATE_GOVERNOR')
                    THEN N'Transaction Log'
                    WHEN dows.wait_type IN (N'SLEEP_TASK', N'BPSORT', N'PWAIT_QRY_BPMEMORY', N'HTREPARTITION', N'HTBUILD', N'HTMEMO', N'HTDELETE', N'HTREINIT')
                    THEN N'Query Execution'
                    WHEN dows.wait_type = N'ASYNC_NETWORK_IO'
                    THEN N'Network'
                    WHEN dows.wait_type IN (N'HADR_SYNC_COMMIT', N'HADR_GROUP_COMMIT')
                    THEN N'Availability Groups'
                    WHEN dows.wait_type IN (N'IO_QUEUE_LIMIT', N'RESMGR_THROTTLED')
                    THEN N'Azure SQL Throttling'
                    WHEN dows.wait_type = N'BTREE_INSERT_FLOW_CONTROL'
                    THEN N'Index Management'
                    WHEN dows.wait_type = N'WAIT_ON_SYNC_STATISTICS_REFRESH'
                    THEN N'Statistics'
                    ELSE N'Other'
                END
        FROM sys.dm_os_wait_stats AS dows
        WHERE
        /* Only include specific wait types identified as important */
        (
               dows.wait_type = N'PAGEIOLATCH_SH'
            OR dows.wait_type = N'PAGEIOLATCH_EX'
            OR dows.wait_type = N'RESOURCE_SEMAPHORE'
            OR dows.wait_type = N'RESOURCE_SEMAPHORE_QUERY_COMPILE'
            OR dows.wait_type = N'CXPACKET'
            OR dows.wait_type = N'CXCONSUMER'
            OR dows.wait_type = N'CXSYNC_PORT'
            OR dows.wait_type = N'CXSYNC_CONSUMER'
            OR dows.wait_type = N'SOS_SCHEDULER_YIELD'
            OR dows.wait_type = N'THREADPOOL'
            OR dows.wait_type = N'RESOURCE_GOVERNOR_IDLE'
            OR dows.wait_type = N'CMEMTHREAD'
            OR dows.wait_type = N'PAGELATCH_EX'
            OR dows.wait_type = N'PAGELATCH_SH'
            OR dows.wait_type = N'PAGELATCH_UP'
            OR dows.wait_type LIKE N'LCK%'
            OR dows.wait_type = N'WRITELOG'
            OR dows.wait_type = N'LOGBUFFER'
            OR dows.wait_type = N'LOG_RATE_GOVERNOR'
            OR dows.wait_type = N'POOL_LOG_RATE_GOVERNOR'
            OR dows.wait_type = N'SLEEP_TASK'
            OR dows.wait_type = N'BPSORT'
            OR dows.wait_type = N'EXECSYNC'
            OR dows.wait_type = N'IO_COMPLETION'
            OR dows.wait_type = N'ASYNC_NETWORK_IO'
            OR dows.wait_type = N'SLEEP_BPOOL_STEAL'
            OR dows.wait_type = N'PWAIT_QRY_BPMEMORY'
            OR dows.wait_type = N'HTREPARTITION'
            OR dows.wait_type = N'HTBUILD'
            OR dows.wait_type = N'HTMEMO'
            OR dows.wait_type = N'HTDELETE'
            OR dows.wait_type = N'HTREINIT'
            OR dows.wait_type = N'BTREE_INSERT_FLOW_CONTROL'
            OR dows.wait_type = N'HADR_SYNC_COMMIT'
            OR dows.wait_type = N'HADR_GROUP_COMMIT'
            OR dows.wait_type = N'WAIT_ON_SYNC_STATISTICS_REFRESH'
            OR dows.wait_type = N'IO_QUEUE_LIMIT'
            OR dows.wait_type = N'IO_RETRY'
            OR dows.wait_type = N'RESMGR_THROTTLED'
        )
        /* Only include waits that are significant in terms of percentage of uptime or average wait time (>1 second) */
        AND
        (
             (dows.wait_time_ms * 100.0 / @uptime_ms) > @significant_wait_threshold_pct
          OR (dows.wait_time_ms * 1.0 / NULLIF(dows.waiting_tasks_count, 0)) > 1000.0 /* Average wait time > 1 second */
        );

        /* Calculate wait time as percentage of uptime */
        UPDATE
            #wait_stats
        SET
            #wait_stats.wait_time_percent_of_uptime =
                (wait_time_ms * 100.0 / @uptime_ms);

        /* Add only waits that represent >=50% of server uptime */
        INSERT INTO
            #results
        (
            check_id,
            priority,
            category,
            finding,
            details,
            url
        )
        SELECT TOP (10) /* Limit to top 10 most significant waits */
            6001,
            priority =
                CASE
                    WHEN ws.wait_time_percent_of_uptime > 100
                    THEN 20 /* Very high priority if >100% of uptime */
                    WHEN ws.wait_time_percent_of_uptime > 75
                    THEN 30 /* High priority if >75% of uptime */
                    ELSE 40 /* Medium-high priority otherwise */
                END,
            category = N'Wait Statistics',
            finding =
                N'High Impact Wait Type: ' +
                ws.wait_type +
                N' (' +
                ws.category +
                N')',
            details =
                N'Wait type: ' +
                ws.wait_type +
                N' represents ' +
                CONVERT(nvarchar(10), CONVERT(decimal(10, 2), ws.wait_time_percent_of_uptime)) +
                N'% of server uptime (' +
                CONVERT(nvarchar(20), CONVERT(decimal(10, 2), ws.wait_time_minutes)) +
                N' minutes). ' +
                N'Average wait: ' +
                CONVERT(nvarchar(10), CONVERT(decimal(10, 2), ws.avg_wait_ms)) +
                N' ms per wait. ' +
                N'Description: ' +
                ws.description,
            url = N'https://erikdarling.com/sp_PerfCheck#WaitStats'
        FROM #wait_stats AS ws
        WHERE
            (
                 ws.wait_time_percent_of_uptime >= 50.0 /* Only include waits that are at least 50% of uptime */
              OR ws.avg_wait_ms >= 1000.0 /* Or have average wait time > 1 second */
            )
        AND   ws.wait_type <> N'SLEEP_TASK'
        ORDER BY
            ws.wait_time_percent_of_uptime DESC;
    END;

    /* Check for CPU scheduling pressure (signal wait ratio) */
    IF @has_view_server_state = 1
    BEGIN
        /* Get total and signal wait times */
        SELECT
            @signal_wait_time_ms =
                SUM(CONVERT(bigint, osw.signal_wait_time_ms)),
            @total_wait_time_ms =
                SUM(CONVERT(bigint, osw.wait_time_ms)),
            @sos_scheduler_yield_ms =
                SUM
                (
                    CASE
                        WHEN osw.wait_type = N'SOS_SCHEDULER_YIELD'
                        THEN CONVERT(bigint, osw.wait_time_ms)
                        ELSE CONVERT(bigint, 0)
                    END
                )
        FROM sys.dm_os_wait_stats AS osw
        WHERE osw.wait_type NOT IN
        (
            /* Skip benign waits based on sys.dm_os_wait_stats documentation */
            N'BROKER_TASK_STOP',
            N'BROKER_TO_FLUSH',
            N'BROKER_TRANSMITTER',
            N'CHECKPOINT_QUEUE',
            N'CLR_AUTO_EVENT',
            N'CLR_MANUAL_EVENT',
            N'DIRTY_PAGE_POLL',
            N'DISPATCHER_QUEUE_SEMAPHORE',
            N'FSAGENT',
            N'FT_IFTS_SCHEDULER_IDLE_WAIT',
            N'FT_IFTSHC_MUTEX',
            N'HADR_FILESTREAM_IOMGR_IOCOMPLETION',
            N'HADR_LOGCAPTURE_WAIT',
            N'HADR_TIMER_TASK',
            N'HADR_WORK_QUEUE',
            N'LAZYWRITER_SLEEP',
            N'LOGMGR_QUEUE',
            N'MEMORY_ALLOCATION_EXT',
            N'PREEMPTIVE_XE_GETTARGETSTATE',
            N'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP',
            N'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP',
            N'REQUEST_FOR_DEADLOCK_SEARCH',
            N'RESOURCE_QUEUE',
            N'SERVER_IDLE_CHECK',
            N'SLEEP_DBSTARTUP',
            N'SLEEP_DCOMSTARTUP',
            N'SLEEP_MASTERDBREADY',
            N'SLEEP_MASTERMDREADY',
            N'SLEEP_MASTERUPGRADED',
            N'SLEEP_MSDBSTARTUP',
            N'SLEEP_SYSTEMTASK',
            N'SLEEP_TEMPDBSTARTUP',
            N'SNI_HTTP_ACCEPT',
            N'SP_SERVER_DIAGNOSTICS_SLEEP',
            N'SQLTRACE_BUFFER_FLUSH',
            N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP',
            N'SQLTRACE_WAIT_ENTRIES',
            N'STARTUP_DEPENDENCY_MANAGER',
            N'WAIT_FOR_RESULTS',
            N'WAITFOR',
            N'WAITFOR_TASKSHUTDOWN',
            N'WAIT_XTP_HOST_WAIT',
            N'WAIT_XTP_OFFLINE_CKPT_NEW_LOG',
            N'WAIT_XTP_CKPT_CLOSE',
            N'XE_DISPATCHER_JOIN',
            N'XE_DISPATCHER_WAIT',
            N'XE_LIVE_TARGET_TVF',
            N'XE_TIMER_EVENT'
        );

        /* Calculate signal wait ratio (time spent waiting for CPU vs. total wait time) */
        IF @total_wait_time_ms > 0
        BEGIN
            SET @signal_wait_ratio =
                    (@signal_wait_time_ms * 100.0) / @total_wait_time_ms;

            /* Calculate SOS_SCHEDULER_YIELD percentage of uptime */
            IF  @uptime_ms > 0
            AND @sos_scheduler_yield_ms > 0
            BEGIN
                SET @sos_scheduler_yield_pct_of_uptime =
                        (@sos_scheduler_yield_ms * 100.0) / @uptime_ms;
            END;

            /* Add CPU scheduling info to server_info */
            INSERT INTO
                #server_info
             (
                 info_type,
                 value
             )
            VALUES
            (
                 N'Signal Wait Ratio',
                 CONVERT(nvarchar(10), CONVERT(decimal(10, 2), @signal_wait_ratio)) +
                 N'%' +
                 CASE
                     WHEN @signal_wait_ratio >= 50.0
                     THEN N' (High - CPU pressure detected)'
                     WHEN @signal_wait_ratio >= 25.0
                     THEN N' (Moderate - CPU pressure likely)'
                     ELSE N' (Normal)'
                 END
            );

            IF @sos_scheduler_yield_pct_of_uptime > 0
            BEGIN
                INSERT INTO
                    #server_info
                (
                    info_type,
                    value
                )
                VALUES
                (
                    N'SOS_SCHEDULER_YIELD',
                    CONVERT
                    (
                        nvarchar(10),
                        CONVERT
                        (
                            decimal(10, 2),
                            @sos_scheduler_yield_pct_of_uptime
                        )
                    ) +
                    N'% of server uptime'
                );
            END;

            /* Add finding if signal wait ratio exceeds threshold */
            IF @signal_wait_ratio >= 25.0
            BEGIN
                INSERT INTO
                    #results
                (
                    check_id,
                    priority,
                    category,
                    finding,
                    details,
                    url
                )
                VALUES
                (
                    6101,
                    CASE
                        WHEN @signal_wait_ratio >= 50.0
                        THEN 20 /* Very high priority if >=50% signal waits */
                        WHEN @signal_wait_ratio >= 30.0
                        THEN 30 /* High priority if >=30% signal waits */
                        ELSE 40 /* Medium-high priority */
                    END,
                    N'CPU Scheduling',
                    N'High Signal Wait Ratio',
                    N'Signal wait ratio is ' +
                    CONVERT(nvarchar(10), CONVERT(decimal(10, 2), @signal_wait_ratio)) +
                    N'%. This indicates significant CPU scheduling pressure. ' +
                    N'Processes are waiting to get scheduled on the CPU, which can impact query performance. ' +
                    N'Consider investigating high-CPU queries, reducing server load, or adding CPU resources.',
                    N'https://erikdarling.com/sp_PerfCheck#CPUPressure'
                );
            END;

            /* Add finding for significant SOS_SCHEDULER_YIELD waits */
            IF @sos_scheduler_yield_pct_of_uptime >= 25.0
            BEGIN
                INSERT INTO
                    #results
                (
                    check_id,
                    priority,
                    category,
                    finding,
                    details,
                    url
                )
                VALUES
                (
                    6102,
                    CASE
                        WHEN @sos_scheduler_yield_pct_of_uptime >= 50.0
                        THEN 30 /* High priority if >=50% of uptime */
                        WHEN @sos_scheduler_yield_pct_of_uptime >= 30.0
                        THEN 40 /* Medium-high priority if >=30% of uptime */
                        ELSE 50 /* Medium priority */
                    END,
                    N'CPU Scheduling',
                    N'High SOS_SCHEDULER_YIELD Waits',
                    N'SOS_SCHEDULER_YIELD waits account for ' +
                    CONVERT(nvarchar(10), CONVERT(decimal(10, 2), @sos_scheduler_yield_pct_of_uptime)) +
                    N'% of server uptime. This indicates tasks frequently giving up their quantum of CPU time. ' +
                    N'This can be caused by CPU-intensive queries, causing threads to context switch frequently. ' +
                    N'Consider tuning queries with high CPU usage or adding CPU resources.',
                    N'https://erikdarling.com/sp_PerfCheck#CPUPressure'
                );
            END;
        END;
    END;

    /* Check for stolen memory from buffer pool */
    IF @has_view_server_state = 1
    BEGIN
        /* Get buffer pool size */
        SELECT
            @buffer_pool_size_gb =
                CONVERT
                (
                    decimal(38, 2),
                    SUM(domc.pages_kb) / 1024.0 / 1024.0
                )
        FROM sys.dm_os_memory_clerks AS domc
        WHERE domc.type = N'MEMORYCLERK_SQLBUFFERPOOL';

        /* Get stolen memory */
        SELECT
            @stolen_memory_gb =
                CONVERT
                (
                    decimal(38, 2),
                    dopc.cntr_value / 1024.0 / 1024.0
                )
        FROM sys.dm_os_performance_counters AS dopc
        WHERE dopc.counter_name LIKE N'Stolen Server%';

        /* Calculate stolen memory percentage */
        IF @buffer_pool_size_gb > 0
        BEGIN
            SET @stolen_memory_pct =
                    (@stolen_memory_gb / (@buffer_pool_size_gb + @stolen_memory_gb)) * 100.0;

            /* Add buffer pool info to server_info */
            INSERT INTO
                #server_info
            (
                info_type,
                value
            )
            VALUES
            (
                N'Buffer Pool Size',
                CONVERT
                (
                    nvarchar(20),
                    @buffer_pool_size_gb
                ) +
                N' GB'
            );

            INSERT INTO
                #server_info
            (
                info_type,
                value
            )
            VALUES
            (
                N'Stolen Memory',
                CONVERT
                (
                    nvarchar(20),
                    @stolen_memory_gb
                ) +
                N' GB (' +
                CONVERT
                (
                    nvarchar(10),
                    CONVERT
                    (
                        decimal(10, 1),
                        @stolen_memory_pct
                    )
                ) +
                N'%)'
            );

            /* Add finding if stolen memory exceeds threshold */
            IF @stolen_memory_pct > @stolen_memory_threshold_pct
            BEGIN
                INSERT INTO
                    #results
                (
                    check_id,
                    priority,
                    category,
                    finding,
                    details,
                    url
                )
                VALUES
                (
                    6002,
                    CASE
                        WHEN @stolen_memory_pct > 30
                        THEN 30 /* High priority if >30% stolen */
                        WHEN @stolen_memory_pct > 15
                        THEN 40 /* Medium-high priority if >15% stolen */
                        ELSE 50 /* Medium priority */
                    END,
                    N'Memory Usage',
                    N'High Stolen Memory Percentage',
                    N'Memory stolen from buffer pool: ' +
                    CONVERT(nvarchar(20), @stolen_memory_gb) +
                    N' GB (' +
                    CONVERT(nvarchar(10), CONVERT(decimal(10, 1), @stolen_memory_pct)) +
                    N'% of total memory). This reduces memory available for data caching and can impact performance. ' +
                    N'Consider investigating memory usage by CLR, extended stored procedures, linked servers, or other memory clerks.',
                    N'https://erikdarling.com/sp_PerfCheck#MemoryStarved'
                );

                /* Also add the top 5 non-buffer pool memory consumers for visibility */
                INSERT INTO
                    #results
                (
                    check_id,
                    priority,
                    category,
                    finding,
                    details,
                    url
                )
                SELECT TOP (5)
                    check_id = 6003,
                    priority = 60, /* Informational priority */
                    category = N'Memory Usage',
                    finding =
                        N'Top Memory Consumer: ' +
                        domc.type,
                    details =
                        N'Memory clerk "' +
                        domc.type +
                        N'" is using ' +
                        CONVERT
                        (
                            nvarchar(20),
                            CONVERT
                            (
                                decimal(38, 2),
                                SUM(domc.pages_kb) / 1024.0 / 1024.0
                            )
                        ) +
                        N' GB of memory. This is one of the top consumers of memory outside the buffer pool.',
                    url = N'https://erikdarling.com/sp_PerfCheck#MemoryStarved'
                FROM sys.dm_os_memory_clerks AS domc
                WHERE domc.type <> N'MEMORYCLERK_SQLBUFFERPOOL'
                GROUP BY
                    domc.type
                HAVING
                    SUM(domc.pages_kb) / 1024.0 / 1024.0 >= 1.0 /* Only show clerks using more than 1 GB */
                ORDER BY
                    SUM(domc.pages_kb) DESC;
            END;
        END;
    END;

    /* Check for I/O stalls per database */
    IF @has_view_server_state = 1
    BEGIN
        /* First clear any existing data */
        TRUNCATE TABLE
            #io_stalls_by_db;

        /* Get database-level I/O stall statistics */
        SET @io_sql = N'
        SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

        SELECT
            database_name = DB_NAME(fs.database_id),
            database_id = fs.database_id,
            total_io_stall_ms = SUM(fs.io_stall),
            total_io_mb =
                CONVERT(decimal(18, 2), SUM(fs.num_of_bytes_read + fs.num_of_bytes_written) / 1024.0 / 1024.0),
            avg_io_stall_ms =
                CASE
                    WHEN SUM(fs.num_of_reads + fs.num_of_writes) = 0
                    THEN 0
                    ELSE CONVERT(decimal(18, 2), SUM(fs.io_stall) * 1.0 / SUM(fs.num_of_reads + fs.num_of_writes))
                END,
            read_io_stall_ms = SUM(fs.io_stall_read_ms),
            read_io_mb =
                CONVERT(decimal(18, 2), SUM(fs.num_of_bytes_read) / 1024.0 / 1024.0),
            avg_read_stall_ms =
                CASE
                    WHEN SUM(fs.num_of_reads) = 0
                    THEN 0
                    ELSE CONVERT(decimal(18, 2), SUM(fs.io_stall_read_ms) * 1.0 / SUM(fs.num_of_reads))
                END,
            write_io_stall_ms = SUM(fs.io_stall_write_ms),
            write_io_mb =
                CONVERT(decimal(18, 2), SUM(fs.num_of_bytes_written) / 1024.0 / 1024.0),
            avg_write_stall_ms =
                CASE
                    WHEN SUM(fs.num_of_writes) = 0
                    THEN 0
                    ELSE CONVERT(decimal(18, 2), SUM(fs.io_stall_write_ms) * 1.0 / SUM(fs.num_of_writes))
                END,
            total_size_mb = CONVERT(decimal(18, 2), SUM(CONVERT(bigint, mf.size)) * 8.0 / 1024.0)
        FROM sys.dm_io_virtual_file_stats
        (' +
        CASE
            WHEN @azure_sql_db = 1
            THEN N'
            DB_ID()'
            ELSE N'
            NULL'
        END + N',
            NULL
        ) AS fs
        JOIN ' +
        CASE
            WHEN @azure_sql_db = 1
            THEN N'sys.database_files AS mf
          ON  fs.file_id = mf.file_id
          AND fs.database_id = DB_ID()'
            ELSE N'sys.master_files AS mf
          ON  fs.database_id = mf.database_id
          AND fs.file_id = mf.file_id'
        END + N'
        WHERE
        (
            ' +
        CASE
            WHEN @azure_sql_db = 1
            THEN N'1 = 1' /* Always true for Azure SQL DB since we only have the current database */
            ELSE N'fs.database_id > 4
          OR fs.database_id = 2'
        END +
        N'
        ) /* User databases or TempDB */
        GROUP BY
            fs.database_id
        HAVING
            /* Skip idle databases and system databases except tempdb */
            (SUM(fs.num_of_reads + fs.num_of_writes) > 0);';

        IF @debug = 1
        BEGIN
            PRINT @io_sql;
        END;

        BEGIN TRY
            INSERT INTO
                #io_stalls_by_db
            (
                database_name,
                database_id,
                total_io_stall_ms,
                total_io_mb,
                avg_io_stall_ms,
                read_io_stall_ms,
                read_io_mb,
                avg_read_stall_ms,
                write_io_stall_ms,
                write_io_mb,
                avg_write_stall_ms,
                total_size_mb
            )
            EXECUTE sys.sp_executesql
                @io_sql;
        END TRY
        BEGIN CATCH
            IF @debug = 1
            BEGIN
                SET @error_message = N'Error collecting IO stall stats: ' + ERROR_MESSAGE();
                PRINT @error_message;
            END;

            /* Log error in results */
            INSERT INTO #results
            (
                check_id,
                priority,
                category,
                finding,
                details
            )
            VALUES
            (
                9997,
                70, /* Medium priority */
                N'Errors',
                N'Error Collecting IO Statistics',
                N'Unable to collect IO stall statistics: ' + ERROR_MESSAGE()
            );
        END CATCH;

        /* Format a summary of the worst databases by I/O stalls */
        WITH
            io_stall_summary AS
        (
            SELECT TOP (5)
                i.database_name,
                i.total_io_stall_ms,
                i.total_io_mb,
                i.avg_io_stall_ms,
                i.read_io_stall_ms,
                i.read_io_mb,
                i.avg_read_stall_ms,
                i.write_io_stall_ms,
                i.write_io_mb,
                i.avg_write_stall_ms,
                i.total_size_mb
            FROM #io_stalls_by_db AS i
            WHERE
            (
                 i.avg_read_stall_ms >= @slow_read_ms
              OR i.avg_write_stall_ms >= @slow_write_ms
            )
            ORDER BY
                i.avg_io_stall_ms DESC
        )
        SELECT @io_stall_summary =
            STUFF
            (
                (
                    SELECT TOP (5)
                        N', ' +
                        db.database_name +
                        N' (' +
                        CONVERT
                        (
                            nvarchar(10),
                            CONVERT
                            (
                                decimal(10, 2),
                                db.avg_io_stall_ms
                            )
                        ) +
                        N' ms)'
                    FROM io_stall_summary AS db
                    ORDER BY
                        db.avg_io_stall_ms DESC
                    FOR
                        XML
                        PATH('')
                ),
                1,
                2,
                ''
            );

        /* Add I/O stall summary to server_info if any significant stalls were found */
        IF  @io_stall_summary IS NOT NULL
        AND LEN(@io_stall_summary) > 0
        BEGIN
            INSERT INTO
                #server_info
            (
                info_type,
                value
            )
            VALUES
            (
                N'Database I/O Stalls',
                N'Top databases with high I/O latency: ' +
                @io_stall_summary
            );
        END;

        /* Add findings for significant I/O stalls */
        INSERT INTO
            #results
        (
            check_id,
            priority,
            category,
            finding,
            database_name,
            details,
            url
        )
        SELECT TOP (10)
            check_id = 6201,
            priority =
                CASE
                    WHEN io.avg_io_stall_ms >= 100.0
                    THEN 30 /* High priority if >100ms */
                    WHEN io.avg_io_stall_ms >= 50.0
                    THEN 40 /* Medium-high priority if >50ms */
                    ELSE 50 /* Medium priority */
                END,
            category = N'Storage Performance',
            finding = N'High Database I/O Stalls',
            database_name = io.database_name,
            details =
                N'Database ' +
                io.database_name +
                N' has average I/O stall of ' +
                CONVERT(nvarchar(10), CONVERT(decimal(10, 2), io.avg_io_stall_ms)) +
                N' ms. ' +
                N'Read latency: ' +
                CONVERT(nvarchar(10), CONVERT(decimal(10, 2), io.avg_read_stall_ms)) +
                N' ms, Write latency: ' +
                CONVERT(nvarchar(10), CONVERT(decimal(10, 2), io.avg_write_stall_ms)) +
                N' ms. ' +
                N'Total read: ' +
                CONVERT(nvarchar(20), CONVERT(decimal(18, 2), io.read_io_mb)) +
                N' MB, Total write: ' +
                CONVERT(nvarchar(20), CONVERT(decimal(18, 2), io.write_io_mb)) +
                N' MB. ' +
                N'This indicates slow I/O subsystem performance for this database.',
            url = N'https://erikdarling.com/sp_PerfCheck#IOStalls'
        FROM #io_stalls_by_db AS io
        WHERE
            /* Only include databases with significant I/O and significant stalls */
            io.total_io_mb > 1024.0 /* Only databases with at least 1024MB total I/O */
        AND
        (
             io.avg_read_stall_ms >= @slow_read_ms
          OR io.avg_write_stall_ms >= @slow_write_ms
        )
        ORDER BY
            io.avg_io_stall_ms DESC;
    END;

    /*
    Storage Performance Checks - I/O Latency for database files
    */
    IF @debug = 1
    BEGIN
        RAISERROR('Checking storage performance', 0, 1) WITH NOWAIT;
    END;

    SET @file_io_sql = N'
    SELECT
        database_name = DB_NAME(fs.database_id),
        fs.database_id,
        file_name = mf.name,
        mf.type_desc,
        io_stall_read_ms = fs.io_stall_read_ms,
        num_of_reads = fs.num_of_reads,
        avg_read_latency_ms =
            CASE
                WHEN fs.num_of_reads = 0
                THEN 0
                ELSE fs.io_stall_read_ms * 1.0 / fs.num_of_reads
            END,
        io_stall_write_ms = fs.io_stall_write_ms,
        num_of_writes = fs.num_of_writes,
        avg_write_latency_ms =
            CASE
                WHEN fs.num_of_writes = 0
                THEN 0
                ELSE fs.io_stall_write_ms * 1.0 / fs.num_of_writes
            END,
        io_stall_ms = fs.io_stall,
        total_io = fs.num_of_reads + fs.num_of_writes,
        avg_io_latency_ms =
            CASE
                WHEN (fs.num_of_reads + fs.num_of_writes) = 0
                THEN 0
                ELSE fs.io_stall * 1.0 / (fs.num_of_reads + fs.num_of_writes)
            END,
        size_mb = mf.size * 8.0 / 1024,
        drive_location =
            CASE
                WHEN mf.physical_name LIKE N''http%''
                THEN mf.physical_name
                WHEN mf.physical_name LIKE N''\\\\%''
                THEN N''UNC: '' +
                     SUBSTRING(mf.physical_name, 3, CHARINDEX(N''\\'', mf.physical_name, 3) - 3)
                ELSE UPPER(LEFT(mf.physical_name, 2))
            END,
        physical_name = mf.physical_name
    FROM sys.dm_io_virtual_file_stats
    (' +
    CASE
        WHEN @azure_sql_db = 1
        THEN N'
        DB_ID()'
        ELSE N'
        NULL'
    END + N',
        NULL
    ) AS fs
    JOIN ' +
    CASE
        WHEN @azure_sql_db = 1
        THEN N'sys.database_files AS mf
      ON  fs.file_id = mf.file_id
      AND fs.database_id = DB_ID()'
        ELSE N'sys.master_files AS mf
      ON  fs.database_id = mf.database_id
      AND fs.file_id = mf.file_id'
    END + N'
    WHERE
    (
         fs.num_of_reads > 0
      OR fs.num_of_writes > 0
    ); /* Only include files with some activity */';

    IF @debug = 1
    BEGIN
        PRINT @file_io_sql;
    END;

    /* Gather IO Stats */
    BEGIN TRY
        INSERT INTO
            #io_stats
        (
            database_name,
            database_id,
            file_name,
            type_desc,
            io_stall_read_ms,
            num_of_reads,
            avg_read_latency_ms,
            io_stall_write_ms,
            num_of_writes,
            avg_write_latency_ms,
            io_stall_ms,
            total_io,
            avg_io_latency_ms,
            size_mb,
            drive_location,
            physical_name
        )
        EXECUTE sys.sp_executesql
            @file_io_sql;
    END TRY
    BEGIN CATCH
        IF @debug = 1
        BEGIN
            SET @error_message = N'Error collecting file IO stats: ' + ERROR_MESSAGE();
            PRINT @error_message;
        END;

        /* Log error in results */
        INSERT INTO #results
        (
            check_id,
            priority,
            category,
            finding,
            details
        )
        VALUES
        (
            9996,
            70, /* Medium priority */
            N'Errors',
            N'Error Collecting File IO Statistics',
            N'Unable to collect file IO statistics: ' + ERROR_MESSAGE()
        );
    END CATCH;

    /* Add results for slow reads */
    INSERT INTO
        #results
    (
        check_id,
        priority,
        category,
        finding,
        database_name,
        object_name,
        details,
        url
    )
    SELECT
        check_id = 3001,
        priority =
            CASE
                WHEN i.avg_read_latency_ms > @slow_read_ms * 2
                THEN 40 /* Very slow */
                ELSE 50 /* Moderately slow */
            END,
        category = N'Storage Performance',
        finding = N'Slow Read Latency',
        database_name = i.database_name,
        object_name =
            i.file_name +
            N' (' +
            i.type_desc +
            N')',
        details =
            N'Average read latency of ' +
            CONVERT(nvarchar(20), CONVERT(decimal(10, 2), i.avg_read_latency_ms)) +
            N' ms for ' +
            CONVERT(nvarchar(20), i.num_of_reads) +
            N' reads. ' +
            N'This is above the ' +
            CONVERT(nvarchar(10), CONVERT(integer, @slow_read_ms)) +
            N' ms threshold and may indicate storage performance issues.',
        url = N'https://erikdarling.com/sp_PerfCheck#StoragePerformance'
    FROM #io_stats AS i
    WHERE i.avg_read_latency_ms > @slow_read_ms
    AND   i.num_of_reads > 1000; /* Only alert if there's been a significant number of reads */

    /* Add results for slow writes */
    INSERT INTO
        #results
    (
        check_id,
        priority,
        category,
        finding,
        database_name,
        object_name,
        details,
        url
    )
    SELECT
        check_id = 3002,
        priority =
            CASE
                WHEN i.avg_write_latency_ms > @slow_write_ms * 2
                THEN 40 /* Very slow */
                ELSE 50 /* Moderately slow */
            END,
        category = N'Storage Performance',
        finding = N'Slow Write Latency',
        database_name = i.database_name,
        object_name =
            i.file_name +
            N' (' +
            i.type_desc +
            N')',
        details =
            N'Average write latency of ' +
            CONVERT(nvarchar(20), CONVERT(decimal(10, 2), i.avg_write_latency_ms)) +
            N' ms for ' +
            CONVERT(nvarchar(20), i.num_of_writes) +
            N' writes. ' +
            N'This is above the ' +
            CONVERT(nvarchar(10), CONVERT(integer, @slow_write_ms)) +
            N' ms threshold and may indicate storage performance issues.',
        url = N'https://erikdarling.com/sp_PerfCheck#StoragePerformance'
    FROM #io_stats AS i
    WHERE i.avg_write_latency_ms > @slow_write_ms
    AND   i.num_of_writes > 1000; /* Only alert if there's been a significant number of writes */

    /* Add drive level warnings if we have multiple slow files on same drive */
    INSERT INTO
        #results
    (
        check_id,
        priority,
        category,
        finding,
        details,
        url
    )
    SELECT
        check_id = 3003,
        priority = 40, /* High priority */
        category = N'Storage Performance',
        finding =
            N'Multiple Slow Files on Storage Location ' +
            i.drive_location,
        details =
            N'Storage location ' +
            i.drive_location +
            N' has ' +
            CONVERT(nvarchar(10), COUNT_BIG(*)) +
            N' database files with slow I/O. ' +
            N'Average overall latency: ' +
            CONVERT(nvarchar(10), CONVERT(decimal(10, 2), AVG(i.avg_io_latency_ms))) +
            N' ms. ' +
            N'This may indicate an overloaded drive or underlying storage issue.',
        url = N'https://erikdarling.com/sp_PerfCheck#StoragePerformance'
    FROM #io_stats AS i
    WHERE
    (
         i.avg_read_latency_ms > @slow_read_ms
      OR i.avg_write_latency_ms > @slow_write_ms
    )
    AND  i.drive_location IS NOT NULL
    GROUP BY
        i.drive_location
    HAVING
        COUNT_BIG(*) > 1;

    /* Get database sizes - safely handles permissions */
    BEGIN TRY
        BEGIN
            SET @db_size_sql = N'
            SELECT
                N''Total Database Size'',
                N''Allocated: '' +
                CONVERT(nvarchar(20), CONVERT(decimal(10, 2), SUM(f.size * 8.0 / 1024.0 / 1024.0))) +
                N'' GB''
            FROM ' +
            CASE
                WHEN @azure_sql_db = 1
                THEN N'sys.database_files AS f
            WHERE f.type_desc = N''ROWS'''
                ELSE N'sys.master_files AS f
            WHERE f.type_desc = N''ROWS'''
            END;

            IF @debug = 1
            BEGIN
                PRINT @file_io_sql;
            END;

            /* For non-Azure SQL DB, get size across all accessible databases */
            INSERT INTO
                #server_info
            (
                info_type,
                value
            )
            EXECUTE sys.sp_executesql
                @db_size_sql;
        END;
    END TRY
    BEGIN CATCH
        /* If we can't access the files due to permissions */
        INSERT INTO
            #server_info
        (
            info_type,
            value
        )
        VALUES
            (N'Database Size', N'Unable to determine (permission error)');
    END CATCH;

    /*
    Collect Instance-level Configuration Settings - Platform aware
    */
    IF @azure_sql_db = 0 /* Skip some checks for Azure SQL DB */
    BEGIN
        /* Collect memory settings */
        SELECT
            @min_server_memory =
                CONVERT(bigint, c1.value_in_use),
            @max_server_memory =
                CONVERT(bigint, c2.value_in_use)
        FROM sys.configurations AS c1
        CROSS JOIN sys.configurations AS c2
        WHERE c1.name = N'min server memory (MB)'
        AND   c2.name = N'max server memory (MB)';

        /* Get physical memory for comparison */
        SELECT
            @physical_memory_gb =
                CONVERT
                (
                    decimal(10, 2),
                    osi.physical_memory_kb / 1024.0 / 1024.0
                )
        FROM sys.dm_os_sys_info AS osi;

        /* Add min/max server memory info */
        INSERT INTO
            #server_info
        (
            info_type,
            value
        )
        VALUES
        (
            N'Min Server Memory',
            CONVERT(nvarchar(20), @min_server_memory) +
            N' MB'
        );

        INSERT INTO
            #server_info
        (
            info_type,
            value
        )
        VALUES
        (
            N'Max Server Memory',
            CONVERT(nvarchar(20), @max_server_memory) +
            N' MB'
        );

        /* Collect MAXDOP and CTFP settings */
        SELECT
            @max_dop =
                CONVERT(integer, c1.value_in_use),
            @cost_threshold =
                CONVERT(integer, c2.value_in_use)
        FROM sys.configurations AS c1
        CROSS JOIN sys.configurations AS c2
        WHERE c1.name = N'max degree of parallelism'
        AND   c2.name = N'cost threshold for parallelism';

        INSERT INTO
            #server_info
        (
            info_type,
            value
        )
        VALUES
        (
            N'MAXDOP',
            CONVERT(nvarchar(10), @max_dop)
        );

        INSERT INTO
            #server_info
        (
            info_type,
            value
        )
        VALUES
        (
            N'Cost Threshold for Parallelism',
            CONVERT(nvarchar(10), @cost_threshold)
        );

        /* Collect other significant configuration values */
        SELECT
            @priority_boost =
                CONVERT(bit, c1.value_in_use),
            @lightweight_pooling =
                CONVERT(bit, c2.value_in_use)
        FROM sys.configurations AS c1
        CROSS JOIN sys.configurations AS c2
        WHERE c1.name = N'priority boost'
        AND   c2.name = N'lightweight pooling';

        /* Collect affinity mask settings */
        SELECT
            @affinity_mask =
                CONVERT(bigint, c1.value_in_use),
            @affinity_io_mask =
                CONVERT(bigint, c2.value_in_use),
            @affinity64_mask =
                CONVERT(bigint, c3.value_in_use),
            @affinity64_io_mask =
                CONVERT(bigint, c4.value_in_use)
        FROM sys.configurations AS c1
        CROSS JOIN sys.configurations AS c2
        CROSS JOIN sys.configurations AS c3
        CROSS JOIN sys.configurations AS c4
        WHERE c1.name = N'affinity mask'
        AND   c2.name = N'affinity I/O mask'
        AND   c3.name = N'affinity64 mask'
        AND   c4.name = N'affinity64 I/O mask';
    END;

    /*
    Server Configuration Checks (separated from information gathering)
    */
    IF @azure_sql_db = 0 /* Skip these checks for Azure SQL DB */
    BEGIN
        /* Check for non-default configuration values */
        INSERT INTO
            #results
        (
            check_id,
            priority,
            category,
            finding,
            details,
            url
        )
        SELECT
            check_id = 1000,
            priority = 70, /* Informational priority */
            category = N'Server Configuration',
            finding = N'Non-Default Configuration: ' + c.name,
            details =
                N'Configuration option "' + c.name +
                N'" has been changed from the default. Current: ' +
                CONVERT(nvarchar(50), c.value_in_use) +
                CASE
                    /* Configuration options from your lists */
                    WHEN c.name = N'access check cache bucket count' THEN N', Default: 0'
                    WHEN c.name = N'access check cache quota' THEN N', Default: 0'
                    WHEN c.name = N'Ad Hoc Distributed Queries' THEN N', Default: 0'
                    WHEN c.name = N'ADR cleaner retry timeout (min)' THEN N', Default: 120'
                    WHEN c.name = N'ADR Cleaner Thread Count' THEN N', Default: 1'
                    WHEN c.name = N'ADR Preallocation Factor' THEN N', Default: 4'
                    WHEN c.name = N'affinity mask' THEN N', Default: 0'
                    WHEN c.name = N'affinity I/O mask' THEN N', Default: 0'
                    WHEN c.name = N'affinity64 mask' THEN N', Default: 0'
                    WHEN c.name = N'affinity64 I/O mask' THEN N', Default: 0'
                    WHEN c.name = N'cost threshold for parallelism' THEN N', Default: 5'
                    WHEN c.name = N'max degree of parallelism' THEN N', Default: 0'
                    WHEN c.name = N'max server memory (MB)' THEN N', Default: 2147483647'
                    WHEN c.name = N'max worker threads' THEN N', Default: 0'
                    WHEN c.name = N'min memory per query (KB)' THEN N', Default: 1024'
                    WHEN c.name = N'min server memory (MB)' THEN N', Default: 0'
                    WHEN c.name = N'optimize for ad hoc workloads' THEN N', Default: 0'
                    WHEN c.name = N'priority boost' THEN N', Default: 0'
                    WHEN c.name = N'query governor cost limit' THEN N', Default: 0'
                    WHEN c.name = N'recovery interval (min)' THEN N', Default: 0'
                    WHEN c.name = N'tempdb metadata memory-optimized' THEN N', Default: 0'
                    WHEN c.name = N'lightweight pooling' THEN N', Default: 0'
                    ELSE N', Default: Unknown'
                END,
            url = N'https://erikdarling.com/sp_PerfCheck#ServerSettings'
        FROM sys.configurations AS c
        WHERE
            /* Access check cache settings */
               (c.name = N'access check cache bucket count' AND c.value_in_use <> 0)
            OR (c.name = N'access check cache quota' AND c.value_in_use <> 0)
            OR (c.name = N'Ad Hoc Distributed Queries' AND c.value_in_use <> 0)
            /* ADR settings */
            OR (c.name = N'ADR cleaner retry timeout (min)' AND c.value_in_use NOT IN (0, 15, 120))
            OR (c.name = N'ADR Cleaner Thread Count' AND c.value_in_use <> 1)
            OR (c.name = N'ADR Preallocation Factor' AND c.value_in_use NOT IN (0, 4))
            /* Affinity settings */
            OR (c.name = N'affinity mask' AND c.value_in_use <> 0)
            OR (c.name = N'affinity I/O mask' AND c.value_in_use <> 0)
            OR (c.name = N'affinity64 mask' AND c.value_in_use <> 0)
            OR (c.name = N'affinity64 I/O mask' AND c.value_in_use <> 0)
            /* Common performance settings */
            OR (c.name = N'cost threshold for parallelism' AND c.value_in_use <> 5)
            OR (c.name = N'max degree of parallelism' AND c.value_in_use <> 0)
            OR (c.name = N'max server memory (MB)' AND c.value_in_use <> 2147483647)
            OR (c.name = N'max worker threads' AND c.value_in_use <> 0)
            OR (c.name = N'min memory per query (KB)' AND c.value_in_use <> 1024)
            OR (c.name = N'min server memory (MB)' AND c.value_in_use NOT IN (0, 16))
            OR (c.name = N'optimize for ad hoc workloads' AND c.value_in_use <> 0)
            OR (c.name = N'priority boost' AND c.value_in_use <> 0)
            OR (c.name = N'query governor cost limit' AND c.value_in_use <> 0)
            OR (c.name = N'recovery interval (min)' AND c.value_in_use <> 0)
            OR (c.name = N'tempdb metadata memory-optimized' AND c.value_in_use <> 0)
            OR (c.name = N'lightweight pooling' AND c.value_in_use <> 0);

        /*
        TempDB Configuration Checks (not applicable to Azure SQL DB)
        */
        IF @debug = 1
        BEGIN
            RAISERROR('Checking TempDB configuration', 0, 1) WITH NOWAIT;
        END;

        SET @tempdb_files_sql = N'
        SELECT
            mf.file_id,
            mf.name,
            mf.type_desc,
            size_mb = CONVERT(decimal(18, 2), mf.size * 8.0 / 1024),
            max_size_mb =
                CASE
                    WHEN mf.max_size = -1
                    THEN -1 -- Unlimited
                    ELSE CONVERT(decimal(18, 2), mf.max_size * 8.0 / 1024)
                END,
            growth_mb =
                CASE
                    WHEN mf.is_percent_growth = 1
                    THEN CONVERT(decimal(18, 2), mf.growth) -- Percent
                    ELSE CONVERT(decimal(18, 2), mf.growth * 8.0 / 1024) -- MB
                END,
            mf.is_percent_growth
        FROM ' +
        CASE
            WHEN @azure_sql_db = 1
            THEN N'sys.database_files AS mf
        WHERE DB_NAME() = N''tempdb'';'
            ELSE N'sys.master_files AS mf
        WHERE mf.database_id = 2;'
        END;

        IF @debug = 1
        BEGIN
            PRINT @tempdb_files_sql;
        END;

        /* Get TempDB file information */
        BEGIN TRY
            INSERT INTO
                #tempdb_files
            (
                file_id,
                file_name,
                type_desc,
                size_mb,
                max_size_mb,
                growth_mb,
                is_percent_growth
            )
            EXECUTE sys.sp_executesql
                @tempdb_files_sql;
        END TRY
        BEGIN CATCH
            IF @debug = 1
            BEGIN
                SET @error_message = N'Error collecting TempDB file information: ' + ERROR_MESSAGE();
                PRINT @error_message;
            END;

            /* Log error in results */
            INSERT INTO #results
            (
                check_id,
                priority,
                category,
                finding,
                details
            )
            VALUES
            (
                9995,
                70, /* Medium priority */
                N'Errors',
                N'Error Collecting TempDB File Information',
                N'Unable to collect TempDB file information: ' +
                ERROR_MESSAGE()
            );
        END CATCH;

        /* Get file counts and size range */
        SELECT
            @tempdb_data_file_count =
                SUM
                (
                    CASE
                        WHEN tf.type_desc = N'ROWS'
                        THEN 1
                        ELSE 0
                    END
                ),
            @tempdb_log_file_count =
                SUM
                (
                    CASE
                        WHEN tf.type_desc = N'LOG'
                        THEN 1
                        ELSE 0
                    END
                ),
            @min_data_file_size =
                MIN
                (
                    CASE
                        WHEN tf.type_desc = N'ROWS'
                        THEN tf.size_mb / 1024
                        ELSE NULL
                    END
                ),
            @max_data_file_size =
                MAX
                (
                    CASE
                        WHEN tf.type_desc = N'ROWS'
                        THEN tf.size_mb / 1024
                        ELSE NULL
                    END
                ),
            @has_percent_growth =
                MAX
                (
                    CASE
                        WHEN tf.type_desc = N'ROWS'
                        AND  tf.is_percent_growth = 1
                        THEN 1
                        ELSE 0
                    END
                ),
            @has_fixed_growth =
                MAX
                (
                    CASE
                        WHEN tf.type_desc = N'ROWS'
                        AND  tf.is_percent_growth = 0
                        THEN 1
                        ELSE 0
                    END
                )
        FROM #tempdb_files AS tf;

        /* Calculate size difference percentage */
        IF  @max_data_file_size > 0
        AND @min_data_file_size > 0
        BEGIN
            SET @size_difference_pct =
                    (
                      (@max_data_file_size - @min_data_file_size) /
                       @min_data_file_size
                    ) * 100;
        END;
        ELSE
        BEGIN
            SET @size_difference_pct = 0;
        END;

        /* Check for single data file */
        IF @tempdb_data_file_count = 1
        BEGIN
            INSERT INTO
                #results
            (
                check_id,
                priority,
                category,
                finding,
                details,
                url
            )
            VALUES
            (
                2001,
                50, /* High priority */
                N'TempDB Configuration',
                N'Single TempDB Data File',
                N'TempDB has only one data file. Multiple files can reduce allocation page contention. ' +
                N'Recommendation: Use multiple files (equal to number of logical processors up to 8).',
                N'https://erikdarling.com/sp_PerfCheck#tempdb'
            );
        END;

        /* Check for odd number of files compared to CPUs */
        IF  @tempdb_data_file_count % 2 <> 0
        AND @tempdb_data_file_count <> @processors
        AND @processors > 1
        BEGIN
            INSERT INTO #results
            (
                check_id,
                priority,
                category,
                finding,
                details,
                url
            )
            VALUES
            (
                2002,
                65, /* Medium priority */
                N'TempDB Configuration',
                N'Odd Number of TempDB Files',
                N'TempDB has ' + CONVERT(nvarchar(10), @tempdb_data_file_count) +
                N' data files. This is an odd number and not equal to the ' +
                CONVERT(nvarchar(10), @processors) + ' logical processors. ' +
                N'Consider using an even number of files for better performance.',
                N'https://erikdarling.com/sp_PerfCheck#tempdb'
            );
        END;

        /* Check for more files than CPUs */
        IF  @tempdb_data_file_count > @processors
        BEGIN
            INSERT INTO
                #results
            (
                check_id,
                priority,
                category,
                finding,
                details,
                url
            )
            VALUES
            (
                2003,
                70, /* Informational */
                N'TempDB Configuration',
                N'More TempDB Files Than CPUs',
                N'TempDB has ' +
                CONVERT(nvarchar(10), @tempdb_data_file_count) +
                N' data files, which is more than the ' +
                CONVERT(nvarchar(10), @processors) +
                N' logical processors. ',
                N'https://erikdarling.com/sp_PerfCheck#tempdb'
            );
        END;

        /* Check for uneven file sizes (if difference > 10%) */
        IF @size_difference_pct > 10.0
        BEGIN
            INSERT INTO
                #results
            (
                check_id,
                priority,
                category,
                finding,
                details,
                url
            )
            VALUES
            (
                2004,
                55, /* High-medium priority */
                N'TempDB Configuration',
                N'Uneven TempDB Data File Sizes',
                N'TempDB data files vary in size by ' +
                CONVERT(nvarchar(10), CONVERT(integer, @size_difference_pct)) +
                N'%. Smallest: ' +
                CONVERT(nvarchar(10), CONVERT(integer, @min_data_file_size)) +
                N' GB, Largest: ' +
                CONVERT(nvarchar(10), CONVERT(integer, @max_data_file_size)) +
                N' GB. For best performance, TempDB data files should be the same size.',
                N'https://erikdarling.com/sp_PerfCheck#tempdb'
            );
        END;

        /* Check for mixed autogrowth settings */
        IF  @has_percent_growth = 1
        AND @has_fixed_growth = 1
        BEGIN
            INSERT INTO
                #results
            (
                check_id,
                priority,
                category,
                finding,
                details,
                url
            )
            VALUES
            (
                2005,
                55, /* High-medium priority */
                N'TempDB Configuration',
                N'Mixed TempDB Autogrowth Settings',
                N'TempDB data files have inconsistent autogrowth settings - some use percentage growth and others use fixed size growth. ' +
                N'This can lead to uneven file sizes over time. Use consistent settings for all files.',
                N'https://erikdarling.com/sp_PerfCheck#tempdb'
            );
        END;

        /* Check for percentage growth in tempdb */
        IF @has_percent_growth = 1
        BEGIN
            INSERT INTO
                #results
            (
                check_id,
                priority,
                category,
                finding,
                details,
                url
            )
            VALUES
            (
                2006,
                50, /* High-medium priority */
                N'TempDB Configuration',
                N'Percentage Auto-Growth Setting in TempDB',
                N'TempDB data files are using percentage growth settings. This can lead to increasingly larger growth events as files grow. ' +
                N'TempDB is recreated on server restart, so using predictable fixed-size growth is recommended for better performance.',
                N'https://erikdarling.com/sp_PerfCheck#tempdb'
            );
        END;

        /* Memory configuration checks */
        IF @min_server_memory >= (@max_server_memory * 0.9) /* Within 10% */
        BEGIN
            INSERT INTO
                #results
            (
                check_id,
                priority,
                category,
                finding,
                details,
                url
            )
            VALUES
            (
                1001,
                50, /* High priority */
                N'Server Configuration',
                N'Min Server Memory Too Close To Max',
                N'Min server memory (' +
                CONVERT(nvarchar(20), @min_server_memory) +
                N' MB) is >= 90% of max server memory (' +
                CONVERT(nvarchar(20), @max_server_memory) +
                N' MB). This prevents SQL Server from dynamically adjusting memory.',
                N'https://erikdarling.com/sp_PerfCheck/#MinMaxMemory'
            );
        END;

        /* Check if max server memory is too close to physical memory */
        IF @max_server_memory >= (@physical_memory_gb * 1024 * 0.95) /* Within 5% */
        BEGIN
            INSERT INTO
                #results
            (
                check_id,
                priority,
                category,
                finding,
                details,
                url
            )
            VALUES
            (
                1002,
                40, /* High priority */
                N'Server Configuration',
                N'Max Server Memory Too Close To Physical Memory',
                N'Max server memory (' +
                CONVERT(nvarchar(20), @max_server_memory) +
                N' MB) is >= 95% of physical memory (' +
                CONVERT(nvarchar(20), CONVERT(bigint, @physical_memory_gb * 1024)) +
                N' MB). This may not leave enough memory for the OS and other processes.',
                N'https://erikdarling.com/sp_PerfCheck/#MinMaxMemory'
            );
        END;

        /* MAXDOP check */
        IF  @max_dop = 0
        AND @processors > 8
        BEGIN
            INSERT INTO
                #results
            (
                check_id,
                priority,
                category,
                finding,
                details,
                url
            )
            VALUES
            (
                1003,
                60, /* Medium priority */
                N'Server Configuration',
                N'MAXDOP Not Configured',
                N'Max degree of parallelism is set to 0 (default) on a server with ' +
                CONVERT(nvarchar(10), @processors) +
                N' logical processors. This can lead to excessive parallelism.',
                N'https://erikdarling.com/sp_PerfCheck/#MAXDOP'
            );
        END;

        /* Cost Threshold for Parallelism check */
        IF @cost_threshold <= 5
        BEGIN
            INSERT INTO
                #results
            (
                check_id,
                priority,
                category,
                finding,
                details,
                url
            )
            VALUES
            (
                1004,
                60, /* Medium priority */
                N'Server Configuration',
                N'Low Cost Threshold for Parallelism',
                N'Cost threshold for parallelism is set to ' +
                CONVERT(nvarchar(10), @cost_threshold) +
                N'. Low values can cause excessive parallelism for small queries.',
                N'https://erikdarling.com/sp_PerfCheck/#CostThreshold'
            );
        END;

        /* Priority Boost check */
        IF @priority_boost = 1
        BEGIN
            INSERT INTO
                #results
            (
                check_id,
                priority,
                category,
                finding,
                details,
                url
            )
            VALUES
            (
                1005,
                30, /* High priority */
                N'Server Configuration',
                N'Priority Boost Enabled',
                N'Priority boost is enabled.
                  This can cause issues with Windows scheduling priorities and is not recommended.',
                N'https://erikdarling.com/sp_PerfCheck/#PriorityBoost'
            );
        END;

        /* Lightweight Pooling check */
        IF @lightweight_pooling = 1
        BEGIN
            INSERT INTO
                #results
            (
                check_id,
                priority,
                category,
                finding,
                details,
                url
            )
            VALUES
            (
                1006,
                50, /* Medium priority */
                N'Server Configuration',
                N'Lightweight Pooling Enabled',
                N'Lightweight pooling (fiber mode) is enabled.
                  This is rarely beneficial and can cause issues with OLEDB providers and other components.',
                N'https://erikdarling.com/sp_PerfCheck/#LightweightPooling'
            );
        END;

        /* Affinity Mask check */
        IF @affinity_mask <> 0
        BEGIN
            INSERT INTO
                #results
            (
                check_id,
                priority,
                category,
                finding,
                details,
                url
            )
            VALUES
            (
                1008,
                50, /* Medium priority */
                N'Server Configuration',
                N'Affinity Mask Configured',
                N'Affinity mask has been manually configured to ' +
                CONVERT(nvarchar(20), @affinity_mask) +
                N'. This can limit SQL Server CPU usage and should only be used when necessary for specific CPU binding scenarios.',
                N'https://erikdarling.com/sp_PerfCheck/#AffinityMask'
            );
        END;

        /* Affinity I/O Mask check */
        IF @affinity_io_mask <> 0
        BEGIN
            INSERT INTO
                #results
            (
                check_id,
                priority,
                category,
                finding,
                details,
                url
            )
            VALUES
            (
                1009,
                50, /* Medium priority */
                N'Server Configuration',
                N'Affinity I/O Mask Configured',
                N'Affinity I/O mask has been manually configured to ' +
                CONVERT(nvarchar(20), @affinity_io_mask) +
                N'. This binds I/O completion to specific CPUs and should only be used for specialized workloads.',
                N'https://erikdarling.com/sp_PerfCheck/#AffinityIOMask'
            );
        END;

        /* Affinity64 Mask check */
        IF @affinity64_mask <> 0
        BEGIN
            INSERT INTO
                #results
            (
                check_id,
                priority,
                category,
                finding,
                details,
                url
            )
            VALUES
            (
                1010,
                50, /* Medium priority */
                N'Server Configuration',
                N'Affinity64 Mask Configured',
                N'Affinity64 mask has been manually configured to ' +
                CONVERT(nvarchar(20), @affinity64_mask) +
                N'. This can limit SQL Server CPU usage on high-CPU systems and should be carefully evaluated.',
                N'https://erikdarling.com/sp_PerfCheck/#Affinity64Mask'
            );
        END;

        /* Affinity64 I/O Mask check */
        IF @affinity64_io_mask <> 0
        BEGIN
            INSERT INTO
                #results
            (
                check_id,
                priority,
                category,
                finding,
                details,
                url
            )
            VALUES
            (
                1011,
                50, /* Medium priority */
                N'Server Configuration',
                N'Affinity64 I/O Mask Configured',
                N'Affinity64 I/O mask has been manually configured to ' +
                CONVERT(nvarchar(20), @affinity64_io_mask) +
                N'. This binds I/O completion on high-CPU systems and should be carefully evaluated.',
                N'https://erikdarling.com/sp_PerfCheck/#Affinity64Mask'
            );
        END;

        /* Check for value_in_use <> running_value */
        INSERT INTO
            #results
        (
            check_id,
            priority,
            category,
            finding,
            details,
            url
        )
        SELECT
            check_id = 1007,
            priority = 20, /* Very high priority */
            category = N'Server Configuration',
            finding = N'Configuration Pending Reconfigure',
            details =
                N'The configuration option "' +
                c.name +
                N'" has been changed but requires a reconfigure to take effect. ' +
                N'Current value: ' +
                CONVERT(nvarchar(50), c.value_in_use) +
                N', ' +
                N'Pending value: ' +
                CONVERT(nvarchar(50), c.value),
            url = N'https://erikdarling.com/sp_PerfCheck#ServerSettings'
        FROM sys.configurations AS c
        WHERE c.value <> c.value_in_use
        AND
        (
              c.name <> N'min server memory (MB)'
          AND c.value_in_use <> 16
        );
    END;

    /* Populate #databases table with version-aware dynamic SQL */
    IF COL_LENGTH(N'sys.databases', N'is_ledger_on') IS NOT NULL
    BEGIN
        SET @has_is_ledger = 1;
    END;

    IF COL_LENGTH(N'sys.databases', N'is_accelerated_database_recovery_on') IS NOT NULL
    BEGIN
        SET @has_is_accelerated_database_recovery = 1;
    END;

    IF @debug = 1
    BEGIN
        SELECT
            feature_check = N'Database columns',
            has_is_ledger = @has_is_ledger,
            has_is_accelerated_database_recovery = @has_is_accelerated_database_recovery;
    END;

    SET @sql += N'
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    SELECT
        d.name,
        d.database_id,
        d.compatibility_level,
        d.collation_name,
        d.user_access_desc,
        d.is_read_only,
        d.is_auto_close_on,
        d.is_auto_shrink_on,
        d.state_desc,
        d.snapshot_isolation_state_desc,
        d.is_read_committed_snapshot_on,
        d.is_auto_create_stats_on,
        d.is_auto_create_stats_incremental_on,
        d.is_auto_update_stats_on,
        d.is_auto_update_stats_async_on,
        d.is_ansi_null_default_on,
        d.is_ansi_nulls_on,
        d.is_ansi_padding_on,
        d.is_ansi_warnings_on,
        d.is_arithabort_on,
        d.is_concat_null_yields_null_on,
        d.is_numeric_roundabort_on,
        d.is_quoted_identifier_on,
        d.is_parameterization_forced,
        d.is_query_store_on,
        d.is_distributor,
        d.is_cdc_enabled,
        d.target_recovery_time_in_seconds,
        d.delayed_durability_desc,';

    /* Handle accelerated database recovery column */
    IF @has_is_accelerated_database_recovery = 1
    BEGIN
        SET @sql += N'
        d.is_accelerated_database_recovery_on';
    END
    ELSE
    BEGIN
        SET @sql += N'
        is_accelerated_database_recovery_on = CONVERT(bit, 0)';
    END;

    /* Add is_ledger_on if it exists */
    IF @has_is_ledger = 1
    BEGIN
        SET @sql += N',
        d.is_ledger_on';
    END;
    ELSE
    BEGIN
        SET @sql += N',
        is_ledger_on = CONVERT(bit, 0)'
    END

    /* Apply appropriate filters based on environment */
    IF @azure_sql_db = 1
    BEGIN
        SET @sql += N'
    FROM sys.databases AS d
    WHERE d.database_id = DB_ID();';
    END
    ELSE
    BEGIN
        IF @database_name IS NULL
        BEGIN
            SET @sql += N'
    FROM sys.databases AS d
    WHERE d.database_id > 4;'; /* Skip system databases */
        END
        ELSE
        BEGIN
            SET @sql += N'
    FROM sys.databases AS d
    WHERE d.name = @database_name;';
        END
    END;

    IF @debug = 1
    BEGIN
        RAISERROR('SQL for #databases: %s', 0, 1, @sql) WITH NOWAIT;
        PRINT REPLICATE(N'=', 128);
        PRINT @sql;
    END;

    INSERT INTO
        #databases
    (
        name,
        database_id,
        compatibility_level,
        collation_name,
        user_access_desc,
        is_read_only,
        is_auto_close_on,
        is_auto_shrink_on,
        state_desc,
        snapshot_isolation_state_desc,
        is_read_committed_snapshot_on,
        is_auto_create_stats_on,
        is_auto_create_stats_incremental_on,
        is_auto_update_stats_on,
        is_auto_update_stats_async_on,
        is_ansi_null_default_on,
        is_ansi_nulls_on,
        is_ansi_padding_on,
        is_ansi_warnings_on,
        is_arithabort_on,
        is_concat_null_yields_null_on,
        is_numeric_roundabort_on,
        is_quoted_identifier_on,
        is_parameterization_forced,
        is_query_store_on,
        is_distributor,
        is_cdc_enabled,
        target_recovery_time_in_seconds,
        delayed_durability_desc,
        is_accelerated_database_recovery_on,
        is_ledger_on
    )
    EXECUTE sys.sp_executesql
        @sql,
      N'@database_name sysname',
        @database_name;

    IF @debug = 1
    BEGIN
        SELECT
            d.*
        FROM #databases AS d
        ORDER BY
            d.database_id;
    END;

    /* Build database list based on context */
    IF @azure_sql_db = 1
    BEGIN
        /* In Azure SQL DB, just use current database */
        INSERT
            #database_list
        (
            database_name,
            database_id,
            state,
            state_desc,
            compatibility_level,
            recovery_model_desc,
            is_read_only,
            is_in_standby,
            is_encrypted,
            create_date,
            can_access
        )
        SELECT
            database_name = d.name,
            database_id = d.database_id,
            state = d.state,
            state_desc = d.state_desc,
            compatibility_level = d.compatibility_level,
            recovery_model_desc = d.recovery_model_desc,
            is_read_only = d.is_read_only,
            is_in_standby = d.is_in_standby,
            is_encrypted = d.is_encrypted,
            create_date = d.create_date,
            can_access = 1
        FROM sys.databases AS d
        WHERE d.database_id = DB_ID();
    END;
    ELSE
    BEGIN
        /* For non-Azure SQL DB, build list from all accessible databases */
        IF @database_name IS NULL
        BEGIN
            /* All user databases */
            INSERT
                #database_list
            (
                database_name,
                database_id,
                state,
                state_desc,
                compatibility_level,
                recovery_model_desc,
                is_read_only,
                is_in_standby,
                is_encrypted,
                create_date,
                can_access
            )
            SELECT
                database_name = d.name,
                database_id = d.database_id,
                state = d.state,
                state_desc = d.state_desc,
                compatibility_level = d.compatibility_level,
                recovery_model_desc = d.recovery_model_desc,
                is_read_only = d.is_read_only,
                is_in_standby = d.is_in_standby,
                is_encrypted = d.is_encrypted,
                create_date = d.create_date,
                can_access = 1 /* Default to accessible, will check individually later */
            FROM sys.databases AS d
            WHERE d.database_id > 4 /* Skip system databases */
            AND   d.state = 0; /* Only online databases */
        END;
        ELSE
        BEGIN
            /* Specific database */
            INSERT
                #database_list
            (
                database_name,
                database_id,
                state,
                state_desc,
                compatibility_level,
                recovery_model_desc,
                is_read_only,
                is_in_standby,
                is_encrypted,
                create_date,
                can_access
            )
            SELECT
                database_name = d.name,
                database_id = d.database_id,
                state = d.state,
                state_desc = d.state_desc,
                compatibility_level = d.compatibility_level,
                recovery_model_desc = d.recovery_model_desc,
                is_read_only = d.is_read_only,
                is_in_standby = d.is_in_standby,
                is_encrypted = d.is_encrypted,
                create_date = d.create_date,
                can_access = 1 /* Default to accessible, will check individually later */
            FROM sys.databases AS d
            WHERE d.name = @database_name
            AND   d.state = 0; /* Only online databases */
        END;

        /* Check each database for accessibility using three-part naming */
        DECLARE
            db_cursor
                CURSOR
                LOCAL
                FAST_FORWARD
                READ_ONLY
            FOR
            SELECT
                dl.database_name,
                dl.database_id
            FROM #database_list AS dl;

        OPEN db_cursor;

        FETCH NEXT
        FROM db_cursor
        INTO
            @current_database_name,
            @current_database_id;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            /* Try to access database using three-part naming to ensure we have proper permissions */
            BEGIN TRY
                SET @sql = N'
                SELECT
                    @has_tables =
                        CASE
                            WHEN EXISTS
                            (
                                SELECT
                                    1/0
                                FROM ' +
                                QUOTENAME(@current_database_name) +
                                N'.sys.tables AS t
                            )
                            THEN 1
                            ELSE 0
                        END;';

                IF @debug = 1
                BEGIN
                    PRINT @sql;
                END;

                EXECUTE sys.sp_executesql
                    @sql,
                  N'@has_tables bit OUTPUT',
                    @has_tables OUTPUT;
            END TRY
            BEGIN CATCH
                /* If we can't access it, mark it */
                UPDATE
                    #database_list
                SET
                    #database_list.can_access = 0
                WHERE #database_list.database_id = @current_database_id;

                IF @debug = 1
                BEGIN
                    SET @message =
                        N'Cannot access database: ' +
                        @current_database_name;

                    RAISERROR(@message, 0, 1) WITH NOWAIT;
                END;
            END CATCH;

            FETCH NEXT
            FROM db_cursor
            INTO
                @current_database_name,
                @current_database_id;
        END;

        CLOSE db_cursor;
        DEALLOCATE db_cursor;
    END;

    IF @debug = 1
    BEGIN
        SELECT
            dl.*
        FROM #database_list AS dl;
    END;

    /*
    Database Iteration and Checks
    */
    DECLARE
        database_cursor
            CURSOR
            LOCAL
            FAST_FORWARD
            READ_ONLY
        FOR
        SELECT
            dl.database_name,
            dl.database_id
        FROM #database_list AS dl
        WHERE dl.can_access = 1;

    OPEN database_cursor;

    FETCH NEXT
    FROM database_cursor
    INTO
        @current_database_name,
        @current_database_id;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF @debug = 1
        BEGIN
            SET @message = N'Processing database: ' + @current_database_name;
            RAISERROR(@message, 0, 1) WITH NOWAIT;
        END;

        /*
        Database-specific checks using three-part naming to maintain context
        */

        /* Check for auto-shrink enabled */
        INSERT INTO
            #results
        (
            check_id,
            priority,
            category,
            finding,
            database_name,
            details,
            url
        )
        SELECT
            check_id = 7001,
            priority = 50,
            category = N'Database Configuration',
            finding = N'Auto-Shrink Enabled',
            database_name = d.name,
            details =
                N'Database has auto-shrink enabled, which can cause significant performance problems.',
            url = N'https://erikdarling.com/sp_PerfCheck#AutoShrink'
        FROM #databases AS d
        WHERE d.database_id = @current_database_id
        AND   d.is_auto_shrink_on = 1;

        /* Check for auto-close enabled */
        INSERT INTO
            #results
        (
            check_id,
            priority,
            category,
            finding,
            database_name,
            details,
            url
        )
        SELECT
            check_id = 7002,
            priority = 50,
            category = N'Database Configuration',
            finding = N'Auto-Close Enabled',
            database_name = d.name,
            details =
                N'Database has auto-close enabled, which can cause connection delays while the database is reopened.
                 This setting can impact performance for applications that frequently connect to and disconnect from the database.',
            url = N'https://erikdarling.com/sp_PerfCheck#AutoClose'
        FROM #databases AS d
        WHERE d.database_id = @current_database_id
        AND   d.is_auto_close_on = 1;

        /* Check for non-MULTI_USER access mode */
        INSERT INTO
            #results
        (
            check_id,
            priority,
            category,
            finding,
            database_name,
            details,
            url
        )
        SELECT
            check_id = 7003,
            priority = 30, /* High priority */
            category = N'Database Configuration',
            finding =
                N'Restricted Access Mode: ' +
                d.user_access_desc,
            database_name = d.name,
            details =
                N'Database is not in MULTI_USER mode. Current mode: ' +
                d.user_access_desc +
                N'. This restricts normal database access and may prevent applications from connecting.',
            url = N'https://erikdarling.com/sp_PerfCheck#RestrictedAccess'
        FROM #databases AS d
        WHERE d.database_id = @current_database_id
        AND   d.user_access_desc <> N'MULTI_USER';

        /* Check for disabled auto-statistics settings */
        INSERT INTO
            #results
        (
            check_id,
            priority,
            category,
            finding,
            database_name,
            details,
            url
        )
        SELECT
            check_id = 7004,
            priority = 40, /* Medium-high priority */
            category = N'Database Configuration',
            finding =
                CASE
                    WHEN d.is_auto_create_stats_on = 0
                    AND  d.is_auto_update_stats_on = 0
                    THEN N'Auto Create and Update Statistics Disabled'
                    WHEN d.is_auto_create_stats_on = 0
                    THEN N'Auto Create Statistics Disabled'
                    WHEN d.is_auto_update_stats_on = 0
                    THEN N'Auto Update Statistics Disabled'
                END,
            database_name = d.name,
            details =
                CASE
                    WHEN d.is_auto_create_stats_on = 0
                    AND  d.is_auto_update_stats_on = 0
                    THEN N'Both auto create and auto update statistics are disabled. This can lead to poor query performance due to outdated or missing statistics.'
                    WHEN d.is_auto_create_stats_on = 0
                    AND  d.is_auto_update_stats_on = 1
                    THEN N'Auto create statistics is disabled. This can lead to suboptimal query plans for columns without statistics.'
                    WHEN d.is_auto_update_stats_on = 0
                    AND  d.is_auto_create_stats_on = 1
                    THEN N'Auto update statistics is disabled. This can lead to poor query performance due to outdated statistics.'
                END,
            url = N'https://erikdarling.com/sp_PerfCheck#Statistics'
        FROM #databases AS d
        WHERE d.database_id = @current_database_id
        AND
        (
             d.is_auto_create_stats_on = 0
          OR d.is_auto_update_stats_on = 0
        );

        /* Check ANSI settings that might cause issues */
        INSERT INTO
            #results
        (
            check_id,
            priority,
            category,
            finding,
            database_name,
            details,
            url
        )
        SELECT
            check_id = 7005,
            priority = 50, /* Medium priority */
            category = N'Database Configuration',
            finding = N'Non-Standard ANSI Settings',
            database_name = d.name,
            details =
                N'Database has non-standard ANSI settings: ' +
                      CASE WHEN d.is_ansi_null_default_on = 1 THEN N'ANSI_NULL_DEFAULT ON, ' ELSE N'' END +
                      CASE WHEN d.is_ansi_nulls_on = 1 THEN N'ANSI_NULLS ON, ' ELSE N'' END +
                      CASE WHEN d.is_ansi_padding_on = 1 THEN N'ANSI_PADDING ON, ' ELSE N'' END +
                      CASE WHEN d.is_ansi_warnings_on = 1 THEN N'ANSI_WARNINGS ON, ' ELSE N'' END +
                      CASE WHEN d.is_arithabort_on = 1 THEN N'ARITHABORT ON, ' ELSE N'' END +
                      CASE WHEN d.is_concat_null_yields_null_on = 1 THEN N'CONCAT_NULL_YIELDS_NULL ON, ' ELSE N'' END +
                      CASE WHEN d.is_numeric_roundabort_on = 1 THEN N'NUMERIC_ROUNDABORT ON, ' ELSE N'' END +
                      CASE WHEN d.is_quoted_identifier_on = 1 THEN N'QUOTED_IDENTIFIER ON, ' ELSE N'' END +
                N'which can cause unexpected application behavior and compatibility issues.',
            url = N'https://erikdarling.com/sp_PerfCheck#ANSISettings'
        FROM #databases AS d
        WHERE d.database_id = @current_database_id
        AND
        (
             d.is_ansi_null_default_on = 1
          OR d.is_ansi_nulls_on = 1
          OR d.is_ansi_padding_on = 1
          OR d.is_ansi_warnings_on = 1
          OR d.is_arithabort_on = 1
          OR d.is_concat_null_yields_null_on = 1
          OR d.is_numeric_roundabort_on = 1
          OR d.is_quoted_identifier_on = 1
        );

        /* Check Query Store Status */
        INSERT INTO
            #results
        (
            check_id,
            priority,
            category,
            finding,
            database_name,
            details,
            url
        )
        SELECT
            check_id = 7006,
            priority = 60, /* Informational priority */
            category = N'Database Configuration',
            finding = N'Query Store Not Enabled',
            database_name = d.name,
            details = N'Query Store is not enabled.
                        Consider enabling Query Store to track query performance
                        over time and identify regression issues.',
            url = N'https://erikdarling.com/sp_PerfCheck#QueryStore'
        FROM #databases AS d
        WHERE d.database_id = @current_database_id
        AND   d.is_query_store_on = 0
        /* Skip this check for Azure SQL DB since Query Store is typically always enabled
           and Azure might be reporting is_query_store_on incorrectly */
        AND   @azure_sql_db = 0;

        /* For Azure SQL DB, explicitly check Query Store status since is_query_store_on might be incorrect */
        IF @azure_sql_db = 1
        BEGIN
            SET @sql = N'
            SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

            SELECT
                check_id = 7006,
                priority = 60, /* Informational priority */
                category = N''Database Configuration'',
                finding = N''Query Store Not Enabled'',
                database_name = @current_database_name,
                details = N''Query Store is not enabled.
                          Consider enabling Query Store to track query performance
                          over time and identify regression issues.'',
                url = N''https://erikdarling.com/sp_PerfCheck#QueryStore''
            FROM ' + QUOTENAME(@current_database_name) + N'.sys.database_query_store_options AS qso
            WHERE qso.actual_state = 0 /* OFF */;';

            IF @debug = 1
            BEGIN
                PRINT @sql;
            END;

            INSERT INTO
                #results
            (
                check_id,
                priority,
                category,
                finding,
                database_name,
                details,
                url
            )
            EXECUTE sys.sp_executesql
                @sql,
              N'@current_database_name sysname',
                @current_database_name;
        END;

        /* Check for Query Store in problematic state */
        BEGIN TRY
            SET @sql = N'
            SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

            SELECT
                check_id = 7011,
                priority = 40, /* Medium-high priority */
                category = N''Database Configuration'',
                finding = N''Query Store State Mismatch'',
                database_name = @current_database_name,
                details =
                    ''Query Store desired state ('' +
                    qso.desired_state_desc +
                    '') does not match actual state ('' +
                    qso.actual_state_desc + ''). '' +
                    CASE qso.readonly_reason
                        WHEN 0 THEN N''No specific reason identified.''
                        WHEN 2 THEN N''Database is in single user mode.''
                        WHEN 4 THEN N''Database is in emergency mode.''
                        WHEN 8 THEN N''Database is an Availability Group secondary.''
                        WHEN 65536 THEN N''Query Store has reached maximum size: '' +
                                        CONVERT(nvarchar(20), qso.current_storage_size_mb) +
                                        '' of '' +
                                        CONVERT(nvarchar(20), qso.max_storage_size_mb) +
                                        '' MB.''
                        WHEN 131072 THEN N''The number of different statements in Query Store has reached the internal memory limit.''
                        WHEN 262144 THEN N''Size of in-memory items waiting to be persisted on disk has reached the internal memory limit.''
                        WHEN 524288 THEN N''Database has reached disk size limit.''
                        ELSE N''Unknown reason code: '' + CONVERT(nvarchar(20), qso.readonly_reason)
                    END,
                url = N''https://erikdarling.com/sp_PerfCheck#QueryStoreHealth''
            FROM ' + QUOTENAME(@current_database_name) + N'.sys.database_query_store_options AS qso
            WHERE qso.desired_state <> 0 /* Not intentionally OFF */
            AND   qso.readonly_reason <> 8 /* Ignore AG secondaries */
            AND   qso.desired_state <> qso.actual_state /* States don''t match */
            AND   qso.actual_state IN (0, 3); /* Either OFF or READ_ONLY when it shouldn''t be */';

            IF @debug = 1
            BEGIN
                PRINT @sql;
            END;

            INSERT INTO
                #results
            (
                check_id,
                priority,
                category,
                finding,
                database_name,
                details,
                url
            )
            EXECUTE sys.sp_executesql
                @sql,
              N'@current_database_name sysname',
                @current_database_name;

            /* Check for Query Store with potentially problematic settings */
            SET @sql = N'
            SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

            SELECT
                check_id = 7012,
                priority = 50, /* Medium priority */
                category = N''Database Configuration'',
                finding = N''Query Store Suboptimal Configuration'',
                database_name = @current_database_name,
                details =
                    CASE
                        WHEN qso.max_storage_size_mb < 1024
                        THEN N''Query Store max size ('' +
                             CONVERT(nvarchar(20), qso.max_storage_size_mb) +
                             '' MB) is less than 1 GB. This may be too small for production databases.''
                        WHEN qso.query_capture_mode_desc = N''NONE''
                        THEN N''Query Store capture mode is set to NONE. No new queries will be captured.''
                        WHEN qso.size_based_cleanup_mode_desc = N''OFF''
                        THEN N''Size-based cleanup is disabled. Query Store may fill up and become read-only.''
                        WHEN qso.stale_query_threshold_days < 3
                        THEN N''Stale query threshold is only '' +
                             CONVERT(nvarchar(20), qso.stale_query_threshold_days) +
                             '' days. Short retention periods may lose historical performance data.''
                        WHEN qso.max_plans_per_query < 10
                        THEN N''Max plans per query is only '' +
                             CONVERT(nvarchar(20), qso.max_plans_per_query) +
                             ''. This may cause relevant plans to be purged prematurely.''
                    END,
                url = N''https://erikdarling.com/sp_PerfCheck#QueryStoreHealth''
            FROM ' + QUOTENAME(@current_database_name) + N'.sys.database_query_store_options AS qso
            WHERE qso.actual_state = 2 /* Query Store is ON */
            AND
            (
                   qso.max_storage_size_mb < 1000
                OR qso.query_capture_mode_desc = N''NONE''
                OR qso.size_based_cleanup_mode_desc = N''OFF''
                OR qso.stale_query_threshold_days < 3
                OR qso.max_plans_per_query < 10
            );';

            IF @debug = 1
            BEGIN
                PRINT @sql;
            END;

            INSERT INTO
                #results
            (
                check_id,
                priority,
                category,
                finding,
                database_name,
                details,
                url
            )
            EXECUTE sys.sp_executesql
                @sql,
              N'@current_database_name sysname',
                @current_database_name;

            /* Check for non-default database scoped configurations */
            /* First check if the sys.database_scoped_configurations view exists */
            SET @sql = N'
            IF EXISTS
            (
                SELECT
                    1/0
                FROM ' +
                QUOTENAME(@current_database_name) +
                N'.sys.all_objects AS ao
                WHERE ao.name = N''database_scoped_configurations''
            )
            BEGIN
                /* Delete any existing values for this database */
                TRUNCATE TABLE
                    #database_scoped_configs;

                /* Insert default values as reference for comparison */
                INSERT INTO
                    #database_scoped_configs
                (
                    database_id,
                    database_name,
                    configuration_id,
                    name,
                    value,
                    value_for_secondary,
                    is_value_default
                )
                VALUES
                    (@current_database_id, @current_database_name, 1,  N''MAXDOP'', NULL, NULL, 1),
                    (@current_database_id, @current_database_name, 2,  N''LEGACY_CARDINALITY_ESTIMATION'', NULL, NULL, 1),
                    (@current_database_id, @current_database_name, 3,  N''PARAMETER_SNIFFING'', NULL, NULL, 1),
                    (@current_database_id, @current_database_name, 4,  N''QUERY_OPTIMIZER_HOTFIXES'', NULL, NULL, 1),
                    (@current_database_id, @current_database_name, 7,  N''INTERLEAVED_EXECUTION_TVF'', NULL, NULL, 1),
                    (@current_database_id, @current_database_name, 8,  N''BATCH_MODE_MEMORY_GRANT_FEEDBACK'', NULL, NULL, 1),
                    (@current_database_id, @current_database_name, 9,  N''BATCH_MODE_ADAPTIVE_JOINS'', NULL, NULL, 1),
                    (@current_database_id, @current_database_name, 10, N''TSQL_SCALAR_UDF_INLINING'', NULL, NULL, 1),
                    (@current_database_id, @current_database_name, 13, N''OPTIMIZE_FOR_AD_HOC_WORKLOADS'', NULL, NULL, 1),
                    (@current_database_id, @current_database_name, 16, N''ROW_MODE_MEMORY_GRANT_FEEDBACK'', NULL, NULL, 1),
                    (@current_database_id, @current_database_name, 18, N''BATCH_MODE_ON_ROWSTORE'', NULL, NULL, 1),
                    (@current_database_id, @current_database_name, 19, N''DEFERRED_COMPILATION_TV'', NULL, NULL, 1),
                    (@current_database_id, @current_database_name, 20, N''ACCELERATED_PLAN_FORCING'', NULL, NULL, 1),
                    (@current_database_id, @current_database_name, 24, N''LAST_QUERY_PLAN_STATS'', NULL, NULL, 1),
                    (@current_database_id, @current_database_name, 27, N''EXEC_QUERY_STATS_FOR_SCALAR_FUNCTIONS'', NULL, NULL, 1),
                    (@current_database_id, @current_database_name, 28, N''PARAMETER_SENSITIVE_PLAN_OPTIMIZATION'', NULL, NULL, 1),
                    (@current_database_id, @current_database_name, 31, N''CE_FEEDBACK'', NULL, NULL, 1),
                    (@current_database_id, @current_database_name, 33, N''MEMORY_GRANT_FEEDBACK_PERSISTENCE'', NULL, NULL, 1),
                    (@current_database_id, @current_database_name, 34, N''MEMORY_GRANT_FEEDBACK_PERCENTILE_GRANT'', NULL, NULL, 1),
                    (@current_database_id, @current_database_name, 35, N''OPTIMIZED_PLAN_FORCING'', NULL, NULL, 1),
                    (@current_database_id, @current_database_name, 37, N''DOP_FEEDBACK'', NULL, NULL, 1),
                    (@current_database_id, @current_database_name, 39, N''FORCE_SHOWPLAN_RUNTIME_PARAMETER_COLLECTION'', NULL, NULL, 1);

                /* Get actual non-default settings */
                INSERT INTO
                    #database_scoped_configs
                (
                    database_id,
                    database_name,
                    configuration_id,
                    name,
                    value,
                    value_for_secondary,
                    is_value_default
                )
                SELECT
                    @current_database_id,
                    @current_database_name,
                    sc.configuration_id,
                    sc.name,
                    sc.value,
                    sc.value_for_secondary,
                    CASE
                        WHEN sc.name = N''MAXDOP'' AND CONVERT(integer, sc.value) = 0 THEN 1
                        WHEN sc.name = N''LEGACY_CARDINALITY_ESTIMATION'' AND CONVERT(integer, sc.value) = 0 THEN 1
                        WHEN sc.name = N''PARAMETER_SNIFFING'' AND CONVERT(integer, sc.value) = 1 THEN 1
                        WHEN sc.name = N''QUERY_OPTIMIZER_HOTFIXES'' AND CONVERT(integer, sc.value) = 0 THEN 1
                        WHEN sc.name = N''INTERLEAVED_EXECUTION_TVF'' AND CONVERT(integer, sc.value) = 1 THEN 1
                        WHEN sc.name = N''BATCH_MODE_MEMORY_GRANT_FEEDBACK'' AND CONVERT(integer, sc.value) = 1 THEN 1
                        WHEN sc.name = N''BATCH_MODE_ADAPTIVE_JOINS'' AND CONVERT(integer, sc.value) = 1 THEN 1
                        WHEN sc.name = N''TSQL_SCALAR_UDF_INLINING'' AND CONVERT(integer, sc.value) = 1 THEN 1
                        WHEN sc.name = N''OPTIMIZE_FOR_AD_HOC_WORKLOADS'' AND CONVERT(integer, sc.value) = 0 THEN 1
                        WHEN sc.name = N''ROW_MODE_MEMORY_GRANT_FEEDBACK'' AND CONVERT(integer, sc.value) = 1 THEN 1
                        WHEN sc.name = N''ISOLATE_SECURITY_POLICY_CARDINALITY'' AND CONVERT(integer, sc.value) = 0 THEN 1
                        WHEN sc.name = N''BATCH_MODE_ON_ROWSTORE'' AND CONVERT(integer, sc.value) = 1 THEN 1
                        WHEN sc.name = N''DEFERRED_COMPILATION_TV'' AND CONVERT(integer, sc.value) = 1 THEN 1
                        WHEN sc.name = N''ACCELERATED_PLAN_FORCING'' AND CONVERT(integer, sc.value) = 1 THEN 1
                        WHEN sc.name = N''LAST_QUERY_PLAN_STATS'' AND CONVERT(integer, sc.value) = 0 THEN 1
                        WHEN sc.name = N''EXEC_QUERY_STATS_FOR_SCALAR_FUNCTIONS'' AND CONVERT(integer, sc.value) = 1 THEN 1
                        WHEN sc.name = N''PARAMETER_SENSITIVE_PLAN_OPTIMIZATION'' AND CONVERT(integer, sc.value) = 1 THEN 1
                        WHEN sc.name = N''CE_FEEDBACK'' AND CONVERT(integer, sc.value) = 1 THEN 1
                        WHEN sc.name = N''MEMORY_GRANT_FEEDBACK_PERSISTENCE'' AND CONVERT(integer, sc.value) = 1 THEN 1
                        WHEN sc.name = N''MEMORY_GRANT_FEEDBACK_PERCENTILE_GRANT'' AND CONVERT(integer, sc.value) = 1 THEN 1
                        WHEN sc.name = N''OPTIMIZED_PLAN_FORCING'' AND CONVERT(integer, sc.value) = 1 THEN 1
                        WHEN sc.name = N''DOP_FEEDBACK'' AND CONVERT(integer, sc.value) = 0 THEN 1
                        WHEN sc.name = N''FORCE_SHOWPLAN_RUNTIME_PARAMETER_COLLECTION'' AND CONVERT(integer, sc.value) = 0 THEN 1
                        ELSE 0 /* Non-default */
                    END
                FROM ' + QUOTENAME(@current_database_name) + N'.sys.database_scoped_configurations AS sc
                WHERE sc.configuration_id IN
                      (
                        1, 2, 3, 4, 7, 8, 9,
                        10, 13, 16, 18, 19, 20, 24,
                        27, 28, 31, 33, 34, 35, 37, 39
                      );
            END;';

            IF @debug = 1
            BEGIN
                SELECT
                    dsc.*
                FROM #database_scoped_configs AS dsc
                ORDER BY
                    dsc.database_id,
                    dsc.configuration_id;

                PRINT @current_database_id;
                PRINT @current_database_name;
                PRINT REPLICATE('=', 64);
                PRINT SUBSTRING(@sql, 1, 4000);
                PRINT SUBSTRING(@sql, 4001, 8000);
            END;

            EXECUTE sys.sp_executesql
                @sql,
              N'@current_database_id integer,
                @current_database_name sysname',
                @current_database_id,
                @current_database_name;

                /* Add results for non-default configurations */
                INSERT INTO
                    #results
                (
                    check_id,
                    priority,
                    category,
                    finding,
                    database_name,
                    object_name,
                    details,
                    url
                )
                SELECT
                    check_id = 7020,
                    priority = 60, /* Informational priority */
                    category = N'Database Configuration',
                    finding = N'Non-Default Database Scoped Configuration',
                    database_name = dsc.database_name,
                    object_name = dsc.name,
                    details =
                        N'Database uses non-default setting for ' +
                        dsc.name +
                        N': ' +
                        ISNULL(CONVERT(nvarchar(100), dsc.value), N'NULL') +
                        CASE
                            WHEN dsc.value_for_secondary IS NOT NULL
                            THEN N' (Secondary: ' +
                            CONVERT(nvarchar(100), dsc.value_for_secondary) +
                            N')'
                            ELSE N''
                        END +
                        N'. ',
                    url = N'https://erikdarling.com/sp_PerfCheck#DSC'
                FROM #database_scoped_configs AS dsc
                WHERE dsc.database_id = @current_database_id
                AND   dsc.is_value_default = 0;
        END TRY
        BEGIN CATCH
            IF @debug = 1
            BEGIN
                SET @message =
                    N'Error checking database configuration for ' +
                    @current_database_name +
                    N': ' +
                    ERROR_MESSAGE();

                RAISERROR(@message, 0, 1) WITH NOWAIT;
            END;
        END CATCH;

        /* Check for non-default target recovery time */
        INSERT INTO
            #results
        (
            check_id,
            priority,
            category,
            finding,
            database_name,
            details,
            url
        )
        SELECT
            check_id = 7007,
            priority = 60, /* Informational priority */
            category = N'Database Configuration',
            finding = N'Non-Default Target Recovery Time',
            database_name = d.name,
            details =
                N'Database target recovery time is ' +
                CONVERT(nvarchar(20), d.target_recovery_time_in_seconds) +
                N' seconds, which differs from the default of 60 seconds. This affects checkpoint frequency and recovery time.',
            url = N'https://erikdarling.com/sp_PerfCheck#RecoveryTime'
        FROM #databases AS d
        WHERE d.database_id = @current_database_id
        AND   d.target_recovery_time_in_seconds <> 60;

        /* Check transaction durability */
        INSERT INTO
            #results
        (
            check_id,
            priority,
            category,
            finding,
            database_name,
            details,
            url
        )
        SELECT
            check_id = 7008,
            priority = 50, /* Medium priority */
            category = N'Database Configuration',
            finding = N'Delayed Durability: ' + d.delayed_durability_desc,
            database_name = d.name,
            details =
                N'Database uses ' +
                d.delayed_durability_desc +
                N' durability mode. This can improve performance but increases the risk of data loss during a server failure.',
            url = N'https://erikdarling.com/sp_PerfCheck#TransactionDurability'
        FROM #databases AS d
        WHERE d.database_id = @current_database_id
        AND   d.delayed_durability_desc <> N'DISABLED';

        /* Check if the database has accelerated database recovery disabled with SI/RCSI enabled */
        INSERT INTO
            #results
        (
            check_id,
            priority,
            category,
            finding,
            database_name,
            details,
            url
        )
        SELECT
            check_id = 7009,
            priority = 50, /* Medium priority */
            category = N'Database Configuration',
            finding = N'Accelerated Database Recovery Not Enabled With Snapshot Isolation',
            database_name = d.name,
            details =
                N'Database has Snapshot Isolation or RCSI enabled but Accelerated Database Recovery (ADR) is disabled. ' +
                N'ADR can significantly improve performance with these isolation levels by reducing version store cleanup overhead.',
            url = N'https://erikdarling.com/sp_PerfCheck#ADR'
        FROM #databases AS d
        WHERE d.database_id = @current_database_id
        AND   d.is_accelerated_database_recovery_on = 0
        AND
        (
              d.snapshot_isolation_state_desc = N'ON'
           OR d.is_read_committed_snapshot_on = 1
        );

        /* Check if ledger is enabled */
        INSERT INTO
            #results
        (
            check_id,
            priority,
            category,
            finding,
            database_name,
            details,
            url
        )
        SELECT
            check_id = 7010,
            priority = 60, /* Informational priority */
            category = N'Database Configuration',
            finding = N'Ledger Feature Enabled',
            database_name = d.name,
            details =
                N'Database has the ledger feature enabled, which adds blockchain-like capabilities
                 but may impact performance due to additional overhead for maintaining cryptographic verification.',
            url = N'https://erikdarling.com/sp_PerfCheck#Ledger'
        FROM #databases AS d
        WHERE d.database_id = @current_database_id
        AND   d.is_ledger_on = 1;

        /* Check for database file growth settings */
        BEGIN TRY
            /* Check for percentage growth settings on data files */
            SET @sql = N'
            SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

            SELECT
                check_id = 7101,
                priority = 40, /* Medium-high priority */
                category = N''Database Files'',
                finding = N''Percentage Auto-Growth Setting on Data File'',
                database_name = @current_database_name,
                object_name = mf.name,
                details =
                    ''Database data file is using percentage growth setting ('' +
                    CONVERT(nvarchar(20), mf.growth) +
                    ''%). Current file size is '' +
                    CONVERT(nvarchar(20), CONVERT(decimal(18, 2), mf.size * 8.0 / 1024 / 1024)) +
                    '' GB. This can lead to increasingly larger growth events as the file grows,
                    potentially causing larger file sizes than intended. Even with instant file initialization enabled,
                    consider using a fixed size instead for more predictable growth.'',
                url = N''https://erikdarling.com/sp_PerfCheck#DataFileGrowth''
            FROM ' + QUOTENAME(@current_database_name) + N'.sys.database_files AS mf
            WHERE mf.is_percent_growth = 1
            AND   mf.type_desc = N''ROWS'';';

            IF @debug = 1
            BEGIN
                PRINT @sql;
            END;

            INSERT INTO
                #results
            (
                check_id,
                priority,
                category,
                finding,
                database_name,
                object_name,
                details,
                url
            )
            EXECUTE sys.sp_executesql
                @sql,
              N'@current_database_name sysname',
                @current_database_name;

            /* Check for percentage growth settings on log files */
            SET @sql = N'
            SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

            SELECT
                check_id = 7102,
                priority = 30, /* High priority */
                category = N''Database Files'',
                finding = N''Percentage Auto-Growth Setting on Log File'',
                database_name = @current_database_name,
                object_name = mf.name,
                details =
                    ''Transaction log file is using percentage growth setting ('' +
                    CONVERT(nvarchar(20), mf.growth) +
                    ''%). This can lead to increasingly larger growth events and significant stalls
                    as log files must be zeroed out during auto-growth operations.
                    Always use fixed size growth for log files.'',
                url = N''https://erikdarling.com/sp_PerfCheck#LogFileGrowth''
            FROM ' + QUOTENAME(@current_database_name) + N'.sys.database_files AS mf
            WHERE mf.is_percent_growth = 1
            AND   mf.type_desc = N''LOG'';';

            IF @debug = 1
            BEGIN
                PRINT @sql;
            END;

            INSERT INTO
                #results
            (
                check_id,
                priority,
                category,
                finding,
                database_name,
                object_name,
                details,
                url
            )
            EXECUTE sys.sp_executesql
                @sql,
              N'@current_database_name sysname',
                @current_database_name;

            /* Check for non-optimal log growth increments in SQL Server 2022, Azure SQL DB, or Azure MI */
            IF @product_version_major >= 16 OR @azure_sql_db = 1 OR @azure_managed_instance = 1
            BEGIN
                SET @sql = N'
                SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

                SELECT
                    check_id = 7103,
                    priority = 40, /* Medium-high priority */
                    category = N''Database Files'',
                    finding = N''Non-Optimal Log File Growth Increment'',
                    database_name = @current_database_name,
                    object_name = mf.name,
                    details =
                        ''Transaction log file is using a growth increment of '' +
                        CONVERT(nvarchar(20), CONVERT(decimal(18, 2), mf.growth * 8.0 / 1024)) + '' MB. '' +
                        ''On SQL Server 2022, Azure SQL DB, or Azure MI, transaction logs can use instant file initialization when set to exactly 64 MB. '' +
                        ''Consider changing the growth increment to 64 MB for improved performance.'',
                    url = N''https://erikdarling.com/sp_PerfCheck#LogGrowthSize''
                FROM ' + QUOTENAME(@current_database_name) + N'.sys.database_files AS mf
                WHERE mf.is_percent_growth = 0
                AND   mf.type_desc = N''LOG''
                AND   mf.growth * 8.0 / 1024 <> 64;';

                IF @debug = 1
                BEGIN
                    PRINT @sql;
                END;

                INSERT INTO
                    #results
                (
                    check_id,
                    priority,
                    category,
                    finding,
                    database_name,
                    object_name,
                    details,
                    url
                )
                EXECUTE sys.sp_executesql
                    @sql,
                  N'@current_database_name sysname',
                    @current_database_name;
            END;

            /* Check for very large fixed growth settings (>10GB) */
            SET @sql = N'
            SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

            SELECT
                check_id = 7104,
                priority = 40, /* Medium-high priority */
                category = N''Database Files'',
                finding = N''Extremely Large Auto-Growth Setting'',
                database_name = @current_database_name,
                object_name = mf.name,
                details =
                    ''Database file is using a very large fixed growth increment of '' +
                    CONVERT(nvarchar(20),
                    CONVERT(decimal(18, 2), mf.growth *
                    CONVERT(decimal(18, 2), 8.0) /
                    CONVERT(decimal(18, 2), 1024.0) /
                    CONVERT(decimal(18, 2), 1024.0))) +
                    '' GB. Very large growth increments can lead to excessive space allocation. '' +
                    CASE
                        WHEN mf.type_desc = N''ROWS''
                        THEN N''Even with instant file initialization, consider using smaller increments for more controlled growth.''
                        WHEN mf.type_desc = N''LOG''
                        THEN N''This can cause significant stalls as log files must be zeroed out during growth operations.''
                    END,
                url = N''https://erikdarling.com/sp_PerfCheck#LargeGrowth''
            FROM ' + QUOTENAME(@current_database_name) + N'.sys.database_files AS mf
            WHERE mf.is_percent_growth = 0
            AND   mf.growth * CONVERT(decimal(18, 2), 8.0) /
                  CONVERT(decimal(18, 2), 1024.0) /
                  CONVERT(decimal(18, 2), 1024.0) > 10.0; /* Growth > 10GB */';

            IF @debug = 1
            BEGIN
                PRINT @sql;
            END;

            INSERT INTO
                #results
            (
                check_id,
                priority,
                category,
                finding,
                database_name,
                object_name,
                details,
                url
            )
            EXECUTE sys.sp_executesql
                @sql,
              N'@current_database_name sysname',
                @current_database_name;
        END TRY
        BEGIN CATCH
            IF @debug = 1
            BEGIN
                SET @message =
                    N'Error checking database file growth settings for ' +
                    @current_database_name +
                    N': ' +
                    ERROR_MESSAGE();

                RAISERROR(@message, 0, 1) WITH NOWAIT;
            END;
        END CATCH;

        FETCH NEXT
        FROM database_cursor
        INTO
            @current_database_name,
            @current_database_id;
    END;

    CLOSE database_cursor;
    DEALLOCATE database_cursor;

    /* Add scan time footer to server info */
    INSERT INTO
        #server_info
    (
        info_type,
        value
    )
    VALUES
        (N'Run Date', CONVERT(varchar(25), @start_time, 121));

    /*
    Return Server Info First
    */
    SELECT
        [Server Information] =
            si.info_type,
        [Details] =
            si.value
    FROM #server_info AS si
    ORDER BY
        si.id;

    /*
    Return Performance Check Results
    */
    SELECT
        r.check_id,
        r.priority,
        r.category,
        r.finding,
        r.database_name,
        r.object_name,
        r.details,
        r.url
    FROM #results r
    ORDER BY
        r.priority,
        r.category,
        r.finding,
        r.database_name,
        r.check_id;
END;
GO
