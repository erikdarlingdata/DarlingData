SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'dbo.sp_PerfCheck', N'P') IS NULL
BEGIN
    EXECUTE(N'CREATE PROCEDURE dbo.sp_PerfCheck AS RETURN 138;');
END;
GO

ALTER PROCEDURE
    dbo.sp_PerfCheck
(
    @database_name sysname = NULL, /* Database to check, NULL for all user databases */
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
        @version = '1.0', 
        @version_date = '20250401';
    
    /*
    Variable Declarations
    */
    DECLARE
        @product_version sysname = 
            CONVERT(sysname, SERVERPROPERTY(N'ProductVersion')),
        @product_version_major decimal(10, 2) = 
            SUBSTRING
            (
                CONVERT(sysname, SERVERPROPERTY(N'ProductVersion')), 
                1, 
                CHARINDEX
                (
                    '.', 
                    CONVERT(sysname, SERVERPROPERTY(N'ProductVersion'))
                ) + 1
            ),
        @product_version_minor decimal(10, 2) = 
            PARSENAME
            (
                CONVERT
                (
                    varchar(32), 
                    CONVERT(sysname, SERVERPROPERTY(N'ProductVersion'))
                ), 
                2
            ),
        @engine_edition integer = 
            CONVERT(integer, SERVERPROPERTY(N'EngineEdition')),
        @start_time datetime2(0) = SYSDATETIME(),
        @error_message nvarchar(4000) = N'',
        @sql nvarchar(MAX) = N'',
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
        /*I'm using this as a shortcut here so I don't have to do anything else later if not sa*/    
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
        /* TempDB configuration variables */
        @tempdb_data_file_count integer,
        @tempdb_log_file_count integer,
        @min_data_file_size decimal(18, 2),
        @max_data_file_size decimal(18, 2),
        @size_difference_pct decimal(18, 2),
        @has_percent_growth bit,
        @has_fixed_growth bit,
        /* Storage performance variables */
        @slow_read_ms decimal(10, 2) = 20.0, /* Threshold for slow reads (ms) */
        @slow_write_ms decimal(10, 2) = 20.0, /* Threshold for slow writes (ms) */
        /* Set threshold for "slow" autogrowth (in ms) */
        @slow_autogrow_ms integer = 1000,  /* 1 second */
        @trace_path nvarchar(260),
        @autogrow_summary nvarchar(MAX),
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
        @stolen_memory_threshold_pct decimal(10, 2) = 25.0, /* Alert if more than 25% memory is stolen */
        /* Format the output properly without XML PATH which causes spacing issues */
        @wait_summary nvarchar(1000) = N'',
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
        @has_is_accelerated_database_recovery bit = 0;
    
    
    /* Check for VIEW SERVER STATE permission */
    IF @is_sysadmin = 0
    BEGIN
        BEGIN TRY
            EXECUTE sys.sp_executesql
                N'
                    DECLARE 
                        @c bigint; 
                    
                    SELECT 
                        @c = 1 
                    FROM sys.dm_os_sys_info AS osi;
                ';

            SET @has_view_server_state = 1;
        END TRY
        BEGIN CATCH
            SET @has_view_server_state = 0;
        END CATCH;
    END;
    
    IF @debug = 1
    BEGIN
        SELECT
            permission_check = 'Permission Check',
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
            environment_check = 'Environment Check',
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
        name sysname NOT NULL,              /* Database name */
        database_id integer NOT NULL,       /* Database ID */
        compatibility_level tinyint NOT NULL, /* Informational */
        collation_name sysname NOT NULL,    /* Informational */
        user_access_desc nvarchar(60) NOT NULL, /* Warn if not MULTI_USER */
        is_read_only bit NOT NULL,          /* Informational - can we write there? */
        is_auto_close_on bit NOT NULL,      /* Warn if ON */
        is_auto_shrink_on bit NOT NULL,     /* Warn if ON */
        state_desc nvarchar(60) NOT NULL,   /* Warn if not ONLINE */
        snapshot_isolation_state_desc nvarchar(60) NOT NULL, /* Notify if ON */
        is_read_committed_snapshot_on bit NOT NULL, /* Notify if ON */
        is_auto_create_stats_on bit NOT NULL, /* Warn if not ON */
        is_auto_create_stats_incremental_on bit NOT NULL, /* Informational */
        is_auto_update_stats_on bit NOT NULL, /* Warn if not ON */
        is_auto_update_stats_async_on bit NOT NULL, /* Informational */
        is_ansi_null_default_on bit NOT NULL, /* Warn if ON */
        is_ansi_nulls_on bit NOT NULL,      /* Warn if ON */
        is_ansi_padding_on bit NOT NULL,    /* Warn if ON */
        is_ansi_warnings_on bit NOT NULL,   /* Warn if ON */
        is_arithabort_on bit NOT NULL,      /* Warn if ON */
        is_concat_null_yields_null_on bit NOT NULL, /* Warn if ON */
        is_numeric_roundabort_on bit NOT NULL, /* Warn if ON */
        is_quoted_identifier_on bit NOT NULL, /* Warn if ON */
        is_parameterization_forced bit NOT NULL, /* Informational */
        is_query_store_on bit NOT NULL,     /* List databases where it's OFF */
        is_distributor bit NOT NULL,        /* Informational */
        is_cdc_enabled bit NOT NULL,        /* Informational */
        target_recovery_time_in_seconds integer NOT NULL, /* List if not 60 */
        delayed_durability_desc nvarchar(60) NOT NULL, /* Informational if ALLOWED or FORCED */
        is_accelerated_database_recovery_on bit NOT NULL, /* Suggest turning ON if OFF, especially if SI/RCSI */
        is_ledger_on bit NULL               /* Question sanity if ON */
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
        id integer IDENTITY(1, 1) PRIMARY KEY CLUSTERED,
        check_id integer NOT NULL,
        priority integer NOT NULL,
        category nvarchar(50) NOT NULL,
        finding nvarchar(200) NOT NULL,
        database_name sysname NULL,
        object_name sysname NULL,
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
        drive_location nvarchar(255) NULL, /* Changed from drive_letter to handle cloud storage */
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
        wait_time_percent_of_uptime decimal(5, 2) NULL,
        category nvarchar(50) NOT NULL
    );

    /* Add wait stats summary to server info - focus on uptime impact */
    /* First get top wait categories in a temp table to format properly */
    CREATE TABLE 
        #wait_summary
    (
        category nvarchar(60) NOT NULL,
        pct_of_uptime decimal(10, 2) NOT NULL
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
        #server_info (info_type, value)
    VALUES 
        ('sp_PerfCheck', 'Brought to you by Darling Data');
        
    INSERT INTO 
        #server_info (info_type, value)
    VALUES 
        ('Website', 'https://erikdarling.com');
        
    INSERT INTO 
        #server_info (info_type, value)
    VALUES 
        ('Version', @version + ' (' + CONVERT(varchar(10), @version_date, 101) + ')');
        
    INSERT INTO 
        #server_info (info_type, value)
    VALUES 
        ('Server Name', CONVERT(sysname, SERVERPROPERTY('ServerName')));
    
    INSERT INTO 
        #server_info (info_type, value)
    VALUES 
        (
            'SQL Server Version', 
            CONVERT(sysname, SERVERPROPERTY('ProductVersion')) + 
            ' (' + 
            CONVERT(sysname, SERVERPROPERTY('ProductLevel')) + 
            ')'
        );
    
    INSERT INTO 
        #server_info (info_type, value)
    VALUES 
        ('SQL Server Edition', CONVERT(sysname, SERVERPROPERTY('Edition')));
    
    /* Environment information - Already detected earlier */
    INSERT INTO 
        #server_info (info_type, value)
    SELECT 
        'Environment', 
        CASE 
            WHEN @azure_sql_db = 1 THEN 'Azure SQL Database'
            WHEN @azure_managed_instance = 1 THEN 'Azure SQL Managed Instance'
            WHEN @aws_rds = 1 THEN 'AWS RDS SQL Server'
            ELSE 'On-premises or IaaS SQL Server'
        END;
           
    /* Uptime information - works on all platforms */
    INSERT INTO 
        #server_info (info_type, value)
    SELECT 
        'Uptime', 
        CONVERT
        (
            nvarchar(30), 
            DATEDIFF(DAY, osi.sqlserver_start_time, GETDATE())
        ) + 
        ' days, ' +
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
                        GETDATE()
                    ) % 86400, 
                    '00:00:00'
                )
            ), 
            108
        ) + 
        ' (hh:mm:ss)'
    FROM sys.dm_os_sys_info AS osi;
    
    /* CPU information - works on all platforms */
    INSERT INTO 
        #server_info (info_type, value)
    SELECT 
        'CPU', 
        CONVERT(nvarchar(10), osi.cpu_count) + ' logical processors, ' +
        CONVERT(nvarchar(10), osi.hyperthread_ratio) + ' physical cores, ' +
        CONVERT(nvarchar(10), ISNULL(osi.numa_node_count, 1)) + ' NUMA node(s)'
    FROM sys.dm_os_sys_info AS osi;
    
    /* Check for offline schedulers */
    IF @azure_sql_db = 0 /* Not applicable to Azure SQL DB */
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
            category = 'CPU Configuration',
            finding = 'Offline CPU Schedulers',
            details = 
                CONVERT(nvarchar(10), COUNT_BIG(*)) + 
                ' CPU scheduler(s) are offline out of ' +
                CONVERT(nvarchar(10), (SELECT cpu_count FROM sys.dm_os_sys_info)) +
                ' logical processors. This reduces available processing power. ' +
                'Check affinity mask configuration, licensing, or VM CPU cores/sockets',
            url = 'https://erikdarling.com/'
        FROM sys.dm_os_schedulers AS dos
        WHERE dos.is_online = 0
        HAVING 
            COUNT_BIG(*) > 0; /* Only if there are offline schedulers */
    END;
    
    /* Check for memory-starved queries */
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
        category = 'Memory Pressure',
        finding = 'Memory-Starved Queries Detected',
        details = 
            'Resource semaphore has ' + 
            CONVERT(nvarchar(10), MAX(ders.forced_grant_count)) + 
            ' forced grants. ' +
            'Target memory: ' + CONVERT(nvarchar(20), MAX(ders.target_memory_kb) / 1024 / 1024) + ' GB, ' +
            'Available memory: ' + CONVERT(nvarchar(20), MAX(ders.available_memory_kb) / 1024 / 1024) + ' GB, ' +
            'Granted memory: ' + CONVERT(nvarchar(20), MAX(ders.granted_memory_kb) / 1024 / 1024) + ' GB. ' +
            'Queries are being forced to run with less memory than requested, which can cause spills to tempdb and poor performance.',
        url = 'https://erikdarling.com/'
    FROM sys.dm_exec_query_resource_semaphores AS ders
    WHERE ders.forced_grant_count > 0
    HAVING 
        MAX(ders.forced_grant_count) > 0; /* Only if there are actually forced grants */
    
    /* Check for SQL Server memory dumps (on-prem only) */
    IF  @azure_sql_db = 0
    AND @azure_managed_instance = 0
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
                category = 'Server Stability',
                finding = 'Memory Dumps Detected',
                details = 
                    CONVERT(nvarchar(10), COUNT_BIG(*)) + 
                    ' memory dump(s) found. Most recent: ' + 
                    CONVERT(nvarchar(30), MAX(dsmd.creation_time), 120) + 
                    ', ' 
                    +
                    ' at ' +
                    MAX(dsmd.filename) +
                    '. Check the SQL Server error log and Windows event logs.',
                url = 'https://erikdarling.com/'
            FROM sys.dm_server_memory_dumps AS dsmd
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
                WHEN (1.0 * p.cntr_value / NULLIF(DATEDIFF(DAY, osi.sqlserver_start_time, GETDATE()), 0)) > 100 
                THEN 20 /* Very high priority */
                WHEN (1.0 * p.cntr_value / NULLIF(DATEDIFF(DAY, osi.sqlserver_start_time, GETDATE()), 0)) > 50 
                THEN 30 /* High priority */
                ELSE 40 /* Medium-high priority */
            END,
        category = 'Concurrency',
        finding = 'High Number of Deadlocks',
        details = 
            'Server is averaging ' + 
            CONVERT(nvarchar(20), CONVERT(decimal(10, 2), 1.0 * p.cntr_value / NULLIF(DATEDIFF(DAY, osi.sqlserver_start_time, GETDATE()), 0))) + 
            ' deadlocks per day since startup (' + 
            CONVERT(nvarchar(20), p.cntr_value) + ' total deadlocks over ' + 
            CONVERT(nvarchar(10), DATEDIFF(DAY, osi.sqlserver_start_time, GETDATE())) + ' days). ' +
            'High deadlock rates indicate concurrency issues that should be investigated.',
        url = 'https://erikdarling.com/'
    FROM sys.dm_os_performance_counters AS p
    CROSS JOIN sys.dm_os_sys_info AS osi
    WHERE RTRIM(p.counter_name) = 'Number of Deadlocks/sec'
    AND   RTRIM(p.instance_name) = '_Total'
    AND   p.cntr_value > 0
    AND   
    (
        1.0 * p.cntr_value / 
          NULLIF
          (
              DATEDIFF
              (
                  DAY, 
                  osi.sqlserver_start_time, 
                  GETDATE()
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
                WHEN CONVERT(decimal(10, 2), (domc.pages_kb / 1024.0 / 1024.0)) > 2 
                THEN 30 /* High priority >2GB */
                WHEN CONVERT(decimal(10, 2), (domc.pages_kb / 1024.0 / 1024.0)) > 1 
                THEN 40 /* Medium-high priority >1GB */
                ELSE 50 /* Medium priority */
            END,
        category = 'Memory Usage',
        finding = 'Large Security Token Cache',
        details = 
            'TokenAndPermUserStore cache size is ' + 
            CONVERT(nvarchar(20), CONVERT(decimal(10, 2), (domc.pages_kb / 1024.0 / 1024.0))) + 
            ' GB. Large security caches can consume significant memory and may indicate security-related issues ' +
            'such as excessive application role usage or frequent permission changes. ' +
            'Consider using dbo.ClearTokenPerm stored procedure to manage this issue.',
        url = 'https://www.erikdarling.com/troubleshooting-security-cache-issues-userstore_tokenperm-and-tokenandpermuserstore/'
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
            category = 'Memory Configuration',
            finding = 'Lock Pages in Memory Not Enabled',
            details = 
                'SQL Server is not using locked pages in memory (LPIM). This can lead to Windows ' +
                'taking memory away from SQL Server under memory pressure, causing performance issues. ' +
                'For production SQL Servers with more than 64GB of memory, LPIM should be enabled.',
            url = 'https://erikdarling.com/'
        FROM sys.dm_os_sys_info AS osi
        WHERE osi.sql_memory_model_desc = N'CONVENTIONAL' /* Conventional means not using LPIM */
        AND   @physical_memory_gb >= 32 /* Only recommend for servers with >=32GB RAM */;
    END;
    
    /* Check if Instant File Initialization is enabled (on-prem and managed instances only) */
    IF  @azure_sql_db = 0 
    AND @has_view_server_state = 1
    BEGIN
        INSERT INTO
            #server_info (info_type, value)
        SELECT
            'Instant File Initialization',
            CASE 
                WHEN dss.instant_file_initialization_enabled = N'Y' 
                THEN 'Enabled'
                ELSE 'Disabled'
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
            category = 'Storage Configuration',
            finding = 'Instant File Initialization Disabled',
            details = 
                'Instant File Initialization is not enabled. This can significantly slow down database file ' +
                'creation and growth operations, as SQL Server must zero out data files before using them. ' +
                'Enable this feature by granting the "Perform Volume Maintenance Tasks" permission to the SQL Server service account.',
            url = 'https://erikdarling.com/'
        FROM sys.dm_server_services AS dss
        WHERE dss.filename LIKE N'%sqlservr.exe%'
        AND   dss.servicename LIKE N'SQL Server%'
        AND   dss.instant_file_initialization_enabled = N'N';
    END;
    
    /* Check if Resource Governor is enabled */
    IF @has_view_server_state = 1
    BEGIN
        /* First, add Resource Governor status to server info */
        IF EXISTS (SELECT 1/0 FROM sys.resource_governor_configuration WHERE is_enabled = 1)
        BEGIN
            INSERT INTO
                #server_info (info_type, value)
            SELECT
                'Resource Governor',
                'Enabled';
            
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
                category = 'Resource Governor',
                finding = 'Resource Governor Enabled',
                details = 
                    'Resource Governor is enabled on this instance. This affects workload resource allocation and may ' +
                    'impact performance by limiting resources available to various workloads. ' +
                    'For more details, run these queries to explore your configuration:' + CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10) +
                    '/* Resource Governor configuration */' + CHAR(13) + CHAR(10) +
                    'SELECT * FROM sys.resource_governor_configuration;' + CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10) +
                    '/* Resource pools and their settings */' + CHAR(13) + CHAR(10) +
                    'SELECT * FROM sys.dm_resource_governor_resource_pools;' + CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10) +
                    '/* Workload groups and their settings */' + CHAR(13) + CHAR(10) +
                    'SELECT * FROM sys.dm_resource_governor_workload_groups;' + CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10) +
                    '/* Classifier function (if configured) */' + CHAR(13) + CHAR(10) +
                    'SELECT * FROM sys.resource_governor_configuration ' + CHAR(13) + CHAR(10) +
                    'CROSS APPLY (SELECT OBJECT_NAME(classifier_function_id) AS classifier_function_name) AS cf;',
                url = 'https://erikdarling.com/'
            FROM sys.resource_governor_configuration
            WHERE is_enabled = 1;
        END
        ELSE
        BEGIN
            INSERT INTO
                #server_info (info_type, value)
            SELECT
                'Resource Governor',
                'Disabled';
        END;
    END;
    
    /* Check for globally enabled trace flags (not in Azure) */
    IF  @azure_sql_db = 0
    AND @azure_managed_instance = 0
    BEGIN        
        /* Capture trace flags */
        INSERT INTO 
            #trace_flags
        EXECUTE sys.sp_executesql 
            N'DBCC TRACESTATUS WITH NO_INFOMSGS';
        
        /* Add trace flags to server info */
        IF EXISTS (SELECT 1/0 FROM #trace_flags AS tf WHERE tf.global = 1)
        BEGIN
            INSERT INTO
                #server_info (info_type, value)
            SELECT
                'Global Trace Flags',
                STUFF
                (
                    (
                        SELECT 
                            ', ' + 
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
                    ''
                );
        END;
    END;
    
    /* Memory information - works on all platforms */
    INSERT INTO 
        #server_info (info_type, value)
    SELECT 
        'Memory', 
        'Total: ' + 
        CONVERT(nvarchar(20), CONVERT(decimal(10, 2), osi.physical_memory_kb / 1024.0 / 1024.0)) + 
        ' GB, ' +
        'Target: ' + 
        CONVERT(nvarchar(20), CONVERT(decimal(10, 2), osi.committed_target_kb / 1024.0 / 1024.0)) + 
        ' GB' +
        N', ' +
        osi.sql_memory_model_desc +
        N' enabled'
    FROM sys.dm_os_sys_info AS osi;
    
    /* Check for important events in default trace (Windows only for now) */
    IF  @azure_sql_db = 0
    BEGIN            
        /* Get default trace path */
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
        
        IF @trace_path IS NOT NULL
        BEGIN            
            /* Insert common event classes we're interested in */
            INSERT INTO 
                #event_class_map (event_class, event_name, category_name)
            VALUES
                (92, 'Data File Auto Grow', 'Database'),
                (93, 'Log File Auto Grow', 'Database'),
                (94, 'Data File Auto Shrink', 'Database'),
                (95, 'Log File Auto Shrink', 'Database'),
                (116, 'DBCC Event', 'Database'),
                (137, 'Server Memory Change', 'Server');
                
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
                         t.TextData LIKE '%FREEPROCCACHE%'
                      OR t.TextData LIKE '%FREESYSTEMCACHE%'
                      OR t.TextData LIKE '%DROPCLEANBUFFERS%'
                      OR t.TextData LIKE '%SHRINKDATABASE%'
                      OR t.TextData LIKE '%SHRINKFILE%'
                  )
                )
                /* Server memory change events */
                OR (t.EventClass = 137)
                /* Deadlock events - typically not in default trace but including for completeness */
                OR (t.EventClass = 148)
                /* Look back at the past 7 days of events at most */
                AND t.StartTime > DATEADD(DAY, -7, GETDATE());
                
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
            SELECT
                check_id = 5001,
                priority = 
                    CASE
                        WHEN te.event_class = 93 
                        THEN 40 /* Log file autogrow (higher priority) */
                        ELSE 50 /* Data file autogrow */
                    END,
                category = 'Database File Configuration',
                finding = 
                    CASE
                        WHEN te.event_class = 92 
                        THEN 'Slow Data File Auto Grow'
                        WHEN te.event_class = 93 
                        THEN 'Slow Log File Auto Grow'
                        ELSE 'Slow File Auto Grow'
                    END,
                database_name = te.database_name,
                object_name = te.file_name,
                details = 
                    'Auto grow operation took ' + 
                    CONVERT(nvarchar(20), te.duration_ms) + 
                    ' ms (' + 
                    CONVERT(nvarchar(20), te.duration_ms / 1000.0) + 
                    ' seconds) on ' +
                    CONVERT(nvarchar(30), te.event_time, 120) + 
                    '. ' +
                    'Growth amount: ' + 
                    CONVERT(nvarchar(20), te.file_growth / 1048576) + 
                    ' GB. ',
                url = 'https://erikdarling.com/'
            FROM #trace_events AS te
            WHERE (te.event_class IN (92, 93)) /* Auto-grow events */
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
            SELECT
                check_id = 5002,
                priority = 60, /* Medium priority */
                category = 'Database File Configuration',
                finding = 
                    CASE
                        WHEN te.event_class = 94 
                        THEN 'Data File Auto Shrink'
                        WHEN te.event_class = 95 
                        THEN 'Log File Auto Shrink'
                        ELSE 'File Auto Shrink'
                    END,
                database_name = te.database_name,
                object_name = te.file_name,
                details = 
                    'Auto shrink operation occurred on ' +
                    CONVERT(nvarchar(30), te.event_time, 120) + 
                    '. ' +
                    'Auto-shrink is generally not recommended as it can lead to file fragmentation and ' +
                    'repeated grow/shrink cycles. Consider disabling auto-shrink on this database.',
                url = 'https://erikdarling.com/'
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
            SELECT 
                5003,
                priority = 
                    CASE
                        WHEN dbcc_cmd.dbcc_pattern LIKE '%FREEPROCCACHE%' 
                        OR   dbcc_cmd.dbcc_pattern LIKE '%FREESYSTEMCACHE%'
                        OR   dbcc_cmd.dbcc_pattern LIKE '%DROPCLEANBUFFERS%' 
                        THEN 40 /* Higher priority */
                        ELSE 60 /* Medium priority */
                    END,
                'System Management',
                'Potentially Disruptive DBCC Commands',
                MAX(te.database_name),
                'Found ' + 
                CONVERT(nvarchar(20), COUNT_BIG(*)) + 
                ' instances of "' + 
                CASE
                    WHEN te.text_data LIKE '%FREEPROCCACHE%' THEN 'DBCC FREEPROCCACHE'
                    WHEN te.text_data LIKE '%FREESYSTEMCACHE%' THEN 'DBCC FREESYSTEMCACHE'
                    WHEN te.text_data LIKE '%DROPCLEANBUFFERS%' THEN 'DBCC DROPCLEANBUFFERS'
                    WHEN te.text_data LIKE '%SHRINKDATABASE%' THEN 'DBCC SHRINKDATABASE' 
                    WHEN te.text_data LIKE '%SHRINKFILE%' THEN 'DBCC SHRINKFILE'
                    ELSE LEFT(te.text_data, 40) /* Take first 40 chars for other commands just in case */
                END + 
                '" between ' + 
                CONVERT(nvarchar(30), MIN(te.event_time), 120) + 
                ' and ' + 
                CONVERT(nvarchar(30), MAX(te.event_time), 120) + 
                '. These commands can impact server performance or database integrity. ' +
                'Review why these commands are being executed, especially if on a production system.',
                'https://erikdarling.com/'
            FROM #trace_events AS te
            CROSS APPLY
            (
                SELECT dbcc_pattern = 
                    CASE
                        WHEN te.text_data LIKE '%FREEPROCCACHE%' THEN 'DBCC FREEPROCCACHE'
                        WHEN te.text_data LIKE '%FREESYSTEMCACHE%' THEN 'DBCC FREESYSTEMCACHE'
                        WHEN te.text_data LIKE '%DROPCLEANBUFFERS%' THEN 'DBCC DROPCLEANBUFFERS'
                        WHEN te.text_data LIKE '%SHRINKDATABASE%' THEN 'DBCC SHRINKDATABASE' 
                        WHEN te.text_data LIKE '%SHRINKFILE%' THEN 'DBCC SHRINKFILE'
                        ELSE LEFT(te.text_data, 40) /* Take first 40 chars for other commands just in case*/
                    END
            ) AS dbcc_cmd
            WHERE te.event_class = 116 /* DBCC events */
            AND   te.text_data IS NOT NULL
            GROUP BY 
                dbcc_cmd.dbcc_pattern,
                CASE
                    WHEN te.text_data LIKE '%FREEPROCCACHE%' THEN 'DBCC FREEPROCCACHE'
                    WHEN te.text_data LIKE '%FREESYSTEMCACHE%' THEN 'DBCC FREESYSTEMCACHE'
                    WHEN te.text_data LIKE '%DROPCLEANBUFFERS%' THEN 'DBCC DROPCLEANBUFFERS'
                    WHEN te.text_data LIKE '%SHRINKDATABASE%' THEN 'DBCC SHRINKDATABASE' 
                    WHEN te.text_data LIKE '%SHRINKFILE%' THEN 'DBCC SHRINKFILE'
                    ELSE LEFT(te.text_data, 40) /* Take first 40 chars for other commands just i case*/
                END 
            ORDER BY 
                COUNT_BIG(*) DESC;
                
            /* Get summary of SLOW autogrow events for server_info */           
            SELECT @autogrow_summary = 
                STUFF
                (
                    (
                        SELECT 
                            N', ' + 
                            CONVERT(nvarchar(50), COUNT_BIG(*)) + 
                            N' slow ' + 
                            CASE 
                                WHEN te.event_class = 92 
                                THEN 'data file'
                                WHEN te.event_class = 93 
                                THEN 'log file'
                            END + 
                            ' autogrows' +
                            ' (avg ' + 
                            CONVERT(nvarchar(20), AVG(te.duration_ms) / 1000.0) + 
                            ' sec)'
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
                    ''
                );
                
            IF @autogrow_summary IS NOT NULL
            BEGIN
                INSERT INTO
                    #server_info (info_type, value)
                VALUES
                    ('Slow Autogrow Events (7 days)', @autogrow_summary);
            END;
        END;
    END;
    
    /* Check for significant wait stats */
    IF @has_view_server_state = 1
    BEGIN                    
        /* Get uptime */
        SELECT 
            @uptime_ms = 
                DATEDIFF(MILLISECOND, osi.sqlserver_start_time, GETDATE())
        FROM sys.dm_os_sys_info AS osi;
        
        /* Get total wait time */
        SELECT 
            @total_waits = SUM(osw.wait_time_ms)
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
            percentage = CONVERT(decimal(5,2), dows.wait_time_ms * 100.0 / @total_waits),
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
        /* Only include waits that are significant in terms of total wait percentage or average wait time (>1 second) */
        AND 
        (
             (dows.wait_time_ms * 1.0 / @total_waits) > (@significant_wait_threshold_pct / 100.0)
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
            category = 'Wait Statistics',
            finding = 
                'High Impact Wait Type: ' + 
                ws.wait_type + 
                ' (' + 
                ws.category + 
                ')',
            details = 
                'Wait type: ' + 
                ws.wait_type + 
                ' represents ' + 
                CONVERT(nvarchar(10), CONVERT(decimal(10, 2), ws.wait_time_percent_of_uptime)) + 
                '% of server uptime (' + 
                CONVERT(nvarchar(20), CONVERT(decimal(10, 2), ws.wait_time_minutes)) + 
                ' minutes). ' +
                'Average wait: ' + 
                CONVERT(nvarchar(10), CONVERT(decimal(10, 2), ws.avg_wait_ms)) + 
                ' ms per wait. ' +
                'Description: ' + 
                ws.description,
            url = 'https://erikdarling.com/'
        FROM #wait_stats AS ws
        WHERE 
            (
                ws.wait_time_percent_of_uptime >= 50.0 /* Only include waits that are at least 50% of uptime */
                OR ws.avg_wait_ms >= 1000.0 /* Or have average wait time > 1 second */
            )
        AND   ws.wait_type <> N'SLEEP_TASK'
        ORDER BY 
            ws.wait_time_percent_of_uptime DESC;
                    
        INSERT INTO 
            #wait_summary (category, pct_of_uptime)
        SELECT 
            ws.category,
            pct_of_uptime = SUM(ws.wait_time_percent_of_uptime)
        FROM #wait_stats AS ws
        WHERE ws.wait_time_percent_of_uptime >= 10.0 /* Only include categories with at least 10% impact on uptime */
        GROUP BY 
            ws.category
        ORDER BY 
            SUM(ws.wait_time_percent_of_uptime) DESC;
        
        SELECT @wait_summary = 
            CASE 
                WHEN @wait_summary = N'' 
                THEN ws.category + 
                     N' (' + 
                     CONVERT(nvarchar(10), ws.pct_of_uptime) + 
                     N'% of uptime)'
                ELSE @wait_summary + 
                     N', ' + 
                     ws.category + 
                     N' (' + 
                     CONVERT(nvarchar(10), ws.pct_of_uptime) + 
                     N'% of uptime)'
            END
        FROM #wait_summary AS ws;
        
        /* Add wait summary to server info if any significant waits were found */
        IF @wait_summary <> N''
        BEGIN
            /* Replace the result set in the server_info table with a clearer explanation */
            INSERT INTO
                #server_info (info_type, value)
            VALUES
                ('Wait Stats Summary', 'See Wait Statistics section in results for details.');
                
            /* Add the detailed wait categories as separate entries in the results table */
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
                6000,
                priority = 
                    CASE
                        WHEN ws.pct_of_uptime > 100 
                        THEN 40 /* Medium-high priority */
                        WHEN ws.pct_of_uptime > 50 
                        THEN 50 /* Medium priority */
                        ELSE 60 /* Lower priority */
                    END,
                category = 'Wait Statistics Summary',
                finding = 'Wait Category: ' + ws.category,
                details = 
                    'This category represents ' + 
                    CONVERT(nvarchar(10), CONVERT(decimal(10, 2), ws.pct_of_uptime)) + 
                    '% of server uptime. ' +
                    CASE 
                        WHEN ws.category = 'Query Execution' 
                        THEN 'This includes various query processing waits and can indicate poorly optimized queries or procedure cache issues.'
                        WHEN ws.category = 'Parallelism' 
                        THEN 'This indicates time spent coordinating parallel query execution. Consider reviewing MAXDOP settings.'
                        WHEN ws.category = 'CPU' 
                        THEN 'This indicates CPU pressure. Server may benefit from more CPU resources or query optimization.'
                        WHEN ws.category = 'Memory' 
                        THEN 'This indicates memory pressure. Consider increasing server memory or optimizing memory-intensive queries.'
                        WHEN ws.category = 'I/O' 
                        THEN 'This indicates storage performance issues. Check for slow disks or I/O-intensive queries.'
                        WHEN ws.category = 'TempDB Contention' 
                        THEN 'This indicates contention in TempDB. Consider adding more TempDB files or optimizing queries that use TempDB.'
                        WHEN ws.category = 'Transaction Log' 
                        THEN 'This indicates log write pressure. Check for long-running transactions or log file performance issues.'
                        WHEN ws.category = 'Locking' 
                        THEN 'This indicates contention from locks. Look for blocking chains or query isolation level issues.'
                        WHEN ws.category = 'Network' 
                        THEN 'This indicates network bottlenecks or slow client applications not consuming results quickly.'
                        WHEN ws.category = 'Azure SQL Throttling' 
                        THEN 'This indicates resource limits imposed by Azure SQL DB. Consider upgrading to a higher service tier.'
                        ELSE 'This category may require further investigation.'
                    END,
                url = 'https://erikdarling.com/'
            FROM #wait_summary AS ws
            ORDER BY 
                ws.pct_of_uptime DESC;
        END;
    END;

    /* Check for CPU scheduling pressure (signal wait ratio) */
    IF @has_view_server_state = 1
    BEGIN
        /* Get total and signal wait times */
        SELECT 
            @signal_wait_time_ms = SUM(osw.signal_wait_time_ms),
            @total_wait_time_ms = SUM(osw.wait_time_ms),
            @sos_scheduler_yield_ms = 
                SUM
                (
                    CASE 
                        WHEN osw.wait_type = N'SOS_SCHEDULER_YIELD' 
                        THEN osw.wait_time_ms 
                        ELSE 0 
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
            SET @signal_wait_ratio = (@signal_wait_time_ms * 100.0) / @total_wait_time_ms;
            
            /* Calculate SOS_SCHEDULER_YIELD percentage of uptime */
            IF @uptime_ms > 0 AND @sos_scheduler_yield_ms > 0
            BEGIN
                SET @sos_scheduler_yield_pct_of_uptime = (@sos_scheduler_yield_ms * 100.0) / @uptime_ms;
            END;
            
            /* Add CPU scheduling info to server_info */
            INSERT INTO
                #server_info (info_type, value)
            VALUES
            (
                 'Signal Wait Ratio', 
                 CONVERT(nvarchar(10), CONVERT(decimal(10, 2), @signal_wait_ratio)) + 
                 '%' +
                 CASE 
                     WHEN @signal_wait_ratio >= 25.0 
                     THEN ' (High - CPU pressure detected)'
                     WHEN @signal_wait_ratio >= 15.0 
                     THEN ' (Moderate - CPU pressure likely)'
                     ELSE ' (Normal)'
                 END
            );
            
            IF @sos_scheduler_yield_pct_of_uptime > 0
            BEGIN
                INSERT INTO
                    #server_info (info_type, value)
                VALUES
                (
                    'SOS_SCHEDULER_YIELD', 
                    CONVERT(nvarchar(10), CONVERT(decimal(10, 2), @sos_scheduler_yield_pct_of_uptime)) + 
                    '% of server uptime'
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
                        WHEN @signal_wait_ratio >= 40.0 
                        THEN 20 /* Very high priority if >=40% signal waits */
                        WHEN @signal_wait_ratio >= 30.0 
                        THEN 30 /* High priority if >=30% signal waits */
                        ELSE 40 /* Medium-high priority */
                    END,
                    'CPU Scheduling',
                    'High Signal Wait Ratio',
                    'Signal wait ratio is ' + 
                    CONVERT(nvarchar(10), CONVERT(decimal(10, 2), @signal_wait_ratio)) + 
                    '%. This indicates significant CPU scheduling pressure. ' +
                    'Processes are waiting to get scheduled on the CPU, which can impact query performance. ' +
                    'Consider investigating high-CPU queries, reducing server load, or adding CPU resources.',
                    'https://erikdarling.com/'
                );
            END;
            
            /* Add finding for significant SOS_SCHEDULER_YIELD waits */
            IF @sos_scheduler_yield_pct_of_uptime >= 10.0 
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
                        WHEN @sos_scheduler_yield_pct_of_uptime >= 30.0 
                        THEN 30 /* High priority if >=30% of uptime */
                        WHEN @sos_scheduler_yield_pct_of_uptime >= 20.0 
                        THEN 40 /* Medium-high priority if >=20% of uptime */
                        ELSE 50 /* Medium priority */
                    END,
                    'CPU Scheduling',
                    'High SOS_SCHEDULER_YIELD Waits',
                    'SOS_SCHEDULER_YIELD waits account for ' + 
                    CONVERT(nvarchar(10), CONVERT(decimal(10, 2), @sos_scheduler_yield_pct_of_uptime)) + 
                    '% of server uptime. This indicates tasks frequently giving up their quantum of CPU time. ' +
                    'This can be caused by CPU-intensive queries, causing threads to context switch frequently. ' +
                    'Consider tuning queries with high CPU usage or adding CPU resources.',
                    'https://erikdarling.com/'
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
        WHERE domc.type = N'MEMORYCLERK_SQLBUFFERPOOL'
        AND   domc.memory_node_id < 64;
        
        /* Get stolen memory */
        SELECT
            @stolen_memory_gb = 
                CONVERT(decimal(38, 2), dopc.cntr_value / 1024.0 / 1024.0)
        FROM sys.dm_os_performance_counters AS dopc
        WHERE dopc.counter_name LIKE N'Stolen Server%';
        
        /* Calculate stolen memory percentage */
        IF @buffer_pool_size_gb > 0
        BEGIN
            SET @stolen_memory_pct = (@stolen_memory_gb / (@buffer_pool_size_gb + @stolen_memory_gb)) * 100.0;
            
            /* Add buffer pool info to server_info */
            INSERT INTO
                #server_info (info_type, value)
            VALUES
            (
                'Buffer Pool Size', 
                CONVERT(nvarchar(20), @buffer_pool_size_gb) + ' GB'
            );
                
            INSERT INTO
                #server_info (info_type, value)
            VALUES
            (
                'Stolen Memory', 
                CONVERT(nvarchar(20), @stolen_memory_gb) + 
                ' GB (' + 
                CONVERT(nvarchar(10), CONVERT(decimal(10, 1), @stolen_memory_pct)) + 
                '%)'
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
                        WHEN @stolen_memory_pct > 40 
                        THEN 30 /* High priority if >40% stolen */
                        WHEN @stolen_memory_pct > 30 
                        THEN 40 /* Medium-high priority if >30% stolen */
                        ELSE 50 /* Medium priority */
                    END,
                    'Memory Usage',
                    'High Stolen Memory Percentage',
                    'Memory stolen from buffer pool: ' + 
                    CONVERT(nvarchar(20), @stolen_memory_gb) + 
                    ' GB (' + 
                    CONVERT(nvarchar(10), CONVERT(decimal(10, 1), @stolen_memory_pct)) + 
                    '% of total memory). This reduces memory available for data caching and can impact performance. ' +
                    'Consider investigating memory usage by CLR, extended stored procedures, linked servers, or other memory clerks.',
                    'https://erikdarling.com/'
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
                SELECT 
                    check_id = 6003,
                    priority = 60, /* Informational priority */
                    category = 'Memory Usage',
                    finding = 'Top Memory Consumer: ' + domc.type,
                    details = 
                        'Memory clerk "' + 
                        domc.type + 
                        '" is using ' + 
                        CONVERT
                        (
                            nvarchar(20), 
                            CONVERT
                            (
                                decimal(38, 2),
                                SUM(domc.pages_kb) / 1024.0 / 1024.0
                            )
                        ) + 
                        ' GB of memory. This is one of the top consumers of memory outside the buffer pool.',
                    url = 'https://erikdarling.com/'
                FROM sys.dm_os_memory_clerks AS domc
                WHERE domc.type <> N'MEMORYCLERK_SQLBUFFERPOOL'
                GROUP BY 
                    domc.type
                HAVING 
                    SUM(domc.pages_kb) / 1024.0 / 1024.0 > 1.0 /* Only show clerks using more than 1 GB */
                ORDER BY
                    SUM(domc.pages_kb) DESC
                OFFSET 0 ROWS
                FETCH NEXT 5 ROWS ONLY;
            END;
        END;
    END;
        
    /* Check for I/O stalls per database */
    IF @has_view_server_state = 1
    BEGIN
        /* First clear any existing data */
        DELETE FROM #io_stalls_by_db;
        
        /* Get database-level I/O stall statistics */
        IF @azure_sql_db = 1
        BEGIN
            /* Azure SQL DB - only current database is accessible */
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
            SELECT
                database_name = DB_NAME(),
                database_id = DB_ID(),
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
                total_size_mb = CONVERT(decimal(18, 2), SUM(df.size) * 8 / 1024.0)
            FROM sys.dm_io_virtual_file_stats(DB_ID(), NULL) AS fs
            JOIN sys.database_files AS df 
              ON fs.file_id = df.file_id;
        END;
        ELSE
        BEGIN
            /* Non-Azure SQL DB - get stats for all databases */
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
                total_size_mb = CONVERT(decimal(18, 2), SUM(mf.size) * 8 / 1024.0)
            FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS fs
            JOIN sys.master_files AS mf 
              ON  fs.database_id = mf.database_id
              AND fs.file_id = mf.file_id
            WHERE 
            (
                 fs.database_id > 4 
              OR fs.database_id = 2
            ) /* User databases or TempDB */
            GROUP BY
                fs.database_id
            HAVING
                /* Skip idle databases and system databases except tempdb */
                (SUM(fs.num_of_reads + fs.num_of_writes) > 0);
        END;
        
        /* Format a summary of the worst databases by I/O stalls */
        WITH io_stall_summary AS
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
                    SELECT 
                        N', ' + 
                        db.database_name + 
                        N' (' + 
                        CONVERT(nvarchar(10), CONVERT(decimal(10, 2), db.avg_io_stall_ms)) + 
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
        IF @io_stall_summary IS NOT NULL AND LEN(@io_stall_summary) > 0
        BEGIN
            INSERT INTO
                #server_info (info_type, value)
            VALUES
                ('Database I/O Stalls', 'Top databases with high I/O latency: ' + @io_stall_summary);
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
        SELECT
            check_id = 6201,
            priority = 
                CASE
                    WHEN io.avg_io_stall_ms >= 100.0 
                    THEN 30 /* High priority if >100ms */
                    WHEN io.avg_io_stall_ms >= 50.0 
                    THEN 40 /* Medium-high priority if >50ms */
                    ELSE 50 /* Medium priority */
                END,
            category = 'Storage Performance',
            finding = 'High Database I/O Stalls',
            database_name = io.database_name,
            details = 
                'Database ' + 
                io.database_name + 
                ' has average I/O stall of ' + 
                CONVERT(nvarchar(10), CONVERT(decimal(10, 2), io.avg_io_stall_ms)) + 
                ' ms. ' +
                'Read latency: ' + 
                CONVERT(nvarchar(10), CONVERT(decimal(10, 2), io.avg_read_stall_ms)) + 
                ' ms, Write latency: ' + 
                CONVERT(nvarchar(10), CONVERT(decimal(10, 2), io.avg_write_stall_ms)) + 
                ' ms. ' +
                'Total read: ' + 
                CONVERT(nvarchar(20), CONVERT(decimal(10, 2), io.read_io_mb)) + 
                ' MB, Total write: ' + 
                CONVERT(nvarchar(20), CONVERT(decimal(10, 2), io.write_io_mb)) + 
                ' MB. ' +
                'This indicates slow I/O subsystem performance for this database.',
            url = 'https://erikdarling.com/'
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
        /* Gather IO Stats */
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
                    WHEN mf.physical_name LIKE N'http%'
                    THEN mf.physical_name
                    WHEN mf.physical_name LIKE N'\\%'
                    THEN N'UNC: ' + SUBSTRING(mf.physical_name, 3, CHARINDEX(N'\', mf.physical_name, 3) - 3)
                    ELSE UPPER(LEFT(mf.physical_name, 2))
                END,
            physical_name = mf.physical_name
        FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS fs
        JOIN sys.master_files AS mf
          ON  fs.database_id = mf.database_id
          AND fs.file_id = mf.file_id
        WHERE (fs.num_of_reads > 0 OR fs.num_of_writes > 0); /* Only include files with some activity */
        
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
            category = 'Storage Performance',
            finding = 'Slow Read Latency',
            database_name = i.database_name,
            object_name = 
                i.file_name + 
                ' (' + 
                i.type_desc + 
                ')',
            details = 
                'Average read latency of ' + 
                CONVERT(nvarchar(20), CONVERT(decimal(10, 2), i.avg_read_latency_ms)) + 
                ' ms for ' + 
                CONVERT(nvarchar(20), i.num_of_reads) + ' reads. ' +
                'This is above the ' + 
                CONVERT(nvarchar(10), CONVERT(integer, @slow_read_ms)) + 
                ' ms threshold and may indicate storage performance issues.',
            url = 'https://erikdarling.com/'
        FROM #io_stats AS i
        WHERE i.avg_read_latency_ms > @slow_read_ms
        AND i.num_of_reads > 1000; /* Only alert if there's been a significant number of reads */
        
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
            category = 'Storage Performance',
            finding = 'Slow Write Latency',
            database_name = i.database_name,
            object_name = 
                i.file_name + 
                ' (' + 
                i.type_desc + 
                ')',
            details = 
                'Average write latency of ' + 
                CONVERT(nvarchar(20), CONVERT(decimal(10, 2), i.avg_write_latency_ms)) + 
                ' ms for ' + 
                CONVERT(nvarchar(20), i.num_of_writes) + 
                ' writes. ' +
                'This is above the ' + 
                CONVERT(nvarchar(10), CONVERT(integer, @slow_write_ms)) + 
                ' ms threshold and may indicate storage performance issues.',
            url = 'https://erikdarling.com/'
        FROM #io_stats AS i
        WHERE i.avg_write_latency_ms > @slow_write_ms
        AND i.num_of_writes > 1000; /* Only alert if there's been a significant number of writes */
        
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
            category = 'Storage Performance',
            finding = 
                'Multiple Slow Files on Storage Location ' + 
                i.drive_location,
            details = 
                'Storage location ' + 
                i.drive_location + 
                ' has ' + 
                CONVERT(nvarchar(10), COUNT_BIG(*)) + 
                ' database files with slow I/O. ' +
                'Average overall latency: ' + 
                CONVERT(nvarchar(10), CONVERT(decimal(10, 2), AVG(i.avg_io_latency_ms))) + 
                ' ms. ' +
                'This may indicate an overloaded drive or underlying storage issue.',
            url = 'https://erikdarling.com/'
        FROM #io_stats AS i
        WHERE 
        (
             i.avg_read_latency_ms > @slow_read_ms 
          OR i.avg_write_latency_ms > @slow_write_ms
        )
        AND i.drive_location IS NOT NULL
        GROUP BY 
            i.drive_location
        HAVING 
            COUNT_BIG(*) > 1;
    
    /* Get database sizes - safely handles permissions */
    BEGIN TRY
        IF @azure_sql_db = 1
        BEGIN
            /* For Azure SQL DB, we only have access to the current database */
            INSERT INTO 
                #server_info (info_type, value)
            SELECT 
                'Database Size',
                'Allocated: ' + 
                CONVERT(nvarchar(20), CONVERT(decimal(10, 2), SUM(df.size * 8.0 / 1024.0 / 1024.0))) +
                ' GB'
            FROM sys.database_files AS df
            WHERE df.type_desc = N'ROWS';
        END;
        ELSE
        BEGIN
            /* For non-Azure SQL DB, get size across all accessible databases */
            INSERT INTO 
                #server_info (info_type, value)
            SELECT 
                'Total Database Size',
                'Allocated: ' + 
                CONVERT(nvarchar(20), CONVERT(decimal(10, 2), SUM(mf.size * 8.0 / 1024.0 / 1024.0))) + 
                ' GB'
            FROM sys.master_files AS mf
            WHERE mf.type_desc = N'ROWS';
        END;
    END TRY
    BEGIN CATCH
        /* If we can't access the files due to permissions */
        INSERT INTO 
            #server_info (info_type, value)
        VALUES 
            ('Database Size', 'Unable to determine (permission error)');
    END CATCH;
    
    /*
    Collect Instance-level Configuration Settings - Platform aware
    */
    IF @azure_sql_db = 0 /* Skip some checks for Azure SQL DB */
    BEGIN
        /* Collect memory settings */
        SELECT 
            @min_server_memory = CONVERT(bigint, c1.value_in_use),
            @max_server_memory = CONVERT(bigint, c2.value_in_use)
        FROM sys.configurations AS c1
        CROSS JOIN sys.configurations AS c2
        WHERE c1.name = N'min server memory (MB)'
        AND   c2.name = N'max server memory (MB)';
        
        /* Get physical memory for comparison */
        SELECT 
            @physical_memory_gb = CONVERT(decimal(10, 2), osi.physical_memory_kb / 1024.0 / 1024.0)
        FROM sys.dm_os_sys_info AS osi;
        
        /* Add min/max server memory info */
        INSERT INTO 
            #server_info (info_type, value)
        VALUES 
            ('Min Server Memory', CONVERT(nvarchar(20), @min_server_memory) + ' MB');
        
        INSERT INTO 
            #server_info (info_type, value)
        VALUES 
            ('Max Server Memory', CONVERT(nvarchar(20), @max_server_memory) + ' MB');
        
        /* Collect MAXDOP and CTFP settings */            
        SELECT 
            @max_dop = CONVERT(integer, c1.value_in_use),
            @cost_threshold = CONVERT(integer, c2.value_in_use)
        FROM sys.configurations AS c1
        CROSS JOIN sys.configurations AS c2
        WHERE c1.name = N'max degree of parallelism'
        AND   c2.name = N'cost threshold for parallelism';
        
        INSERT INTO 
            #server_info (info_type, value)
        VALUES 
            ('MAXDOP', CONVERT(nvarchar(10), @max_dop));
        
        INSERT INTO 
            #server_info (info_type, value)
        VALUES 
            ('Cost Threshold for Parallelism', CONVERT(nvarchar(10), @cost_threshold));
        
        /* Collect other significant configuration values */
        SELECT 
            @priority_boost = CONVERT(bit, c1.value_in_use),
            @lightweight_pooling = CONVERT(bit, c2.value_in_use)
        FROM sys.configurations AS c1
        CROSS JOIN sys.configurations AS c2
        WHERE c1.name = N'priority boost'
        AND   c2.name = N'lightweight pooling';
    END;
    
    /*
    Server Configuration Checks (separated from information gathering)
    */
    IF @azure_sql_db = 0 /* Skip these checks for Azure SQL DB */
    BEGIN
        /* Check for non-default configuration values */
        INSERT INTO #results
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
            category = 'Server Configuration',
            finding = 'Non-Default Configuration: ' + c.name,
            details = 
                'Configuration option "' + c.name + 
                '" has been changed from the default. Current: ' + 
                CONVERT(nvarchar(50), c.value_in_use) + 
                CASE 
                    /* Configuration options from your lists */
                    WHEN c.name = N'access check cache bucket count' THEN ', Default: 0'
                    WHEN c.name = N'access check cache quota' THEN ', Default: 0'
                    WHEN c.name = N'Ad Hoc Distributed Queries' THEN ', Default: 0'
                    WHEN c.name = N'ADR cleaner retry timeout (min)' THEN ', Default: 120'
                    WHEN c.name = N'ADR Cleaner Thread Count' THEN ', Default: 1'
                    WHEN c.name = N'ADR Preallocation Factor' THEN ', Default: 4'
                    WHEN c.name = N'affinity mask' THEN ', Default: 0'
                    WHEN c.name = N'affinity I/O mask' THEN ', Default: 0'
                    WHEN c.name = N'affinity64 mask' THEN ', Default: 0'
                    WHEN c.name = N'affinity64 I/O mask' THEN ', Default: 0'
                    WHEN c.name = N'cost threshold for parallelism' THEN ', Default: 5'
                    WHEN c.name = N'max degree of parallelism' THEN ', Default: 0'
                    WHEN c.name = N'max server memory (MB)' THEN ', Default: 2147483647'
                    WHEN c.name = N'max worker threads' THEN ', Default: 0'
                    WHEN c.name = N'min memory per query (KB)' THEN ', Default: 1024'
                    WHEN c.name = N'min server memory (MB)' THEN ', Default: 0'
                    WHEN c.name = N'optimize for ad hoc workloads' THEN ', Default: 0'
                    WHEN c.name = N'priority boost' THEN ', Default: 0'
                    WHEN c.name = N'query governor cost limit' THEN ', Default: 0'
                    WHEN c.name = N'recovery interval (min)' THEN ', Default: 0'
                    WHEN c.name = N'tempdb metadata memory-optimized' THEN ', Default: 0'
                    WHEN c.name = N'lightweight pooling' THEN ', Default: 0'
                    ELSE ', Default: Unknown'
                END,
            url = 'https://erikdarling.com/'
        FROM sys.configurations AS c
        WHERE 
            /* Access check cache settings */
               (c.name = N'access check cache bucket count' AND c.value_in_use <> 0)
            OR (c.name = N'access check cache quota' AND c.value_in_use <> 0)
            OR (c.name = N'Ad Hoc Distributed Queries' AND c.value_in_use <> 0)
            
            /* ADR settings */
            OR (c.name = N'ADR cleaner retry timeout (min)' AND c.value_in_use NOT IN (15, 120))
            OR (c.name = N'ADR Cleaner Thread Count' AND c.value_in_use <> 1)
            OR (c.name = N'ADR Preallocation Factor' AND c.value_in_use <> 4)
            
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
        
        /* Get TempDB file information */
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
        FROM sys.master_files AS mf
        WHERE mf.database_id = 2; /* TempDB */
        
        /* Get file counts and size range */
        SELECT
            @tempdb_data_file_count = SUM(CASE WHEN tf.type_desc = 'ROWS' THEN 1 ELSE 0 END),
            @tempdb_log_file_count = SUM(CASE WHEN tf.type_desc = 'LOG' THEN 1 ELSE 0 END),
            @min_data_file_size = MIN(CASE WHEN tf.type_desc = 'ROWS' THEN tf.size_mb / 1024 ELSE NULL END),
            @max_data_file_size = MAX(CASE WHEN tf.type_desc = 'ROWS' THEN tf.size_mb / 1024 ELSE NULL END),
            @has_percent_growth = MAX(CASE WHEN tf.type_desc = 'ROWS' AND tf.is_percent_growth = 1 THEN 1 ELSE 0 END),
            @has_fixed_growth = MAX(CASE WHEN tf.type_desc = 'ROWS' AND tf.is_percent_growth = 0 THEN 1 ELSE 0 END)
        FROM #tempdb_files AS tf;
        
        /* Calculate size difference percentage */
        IF  @max_data_file_size > 0 
        AND @min_data_file_size > 0
        BEGIN
            SET @size_difference_pct = 
                    ((@max_data_file_size - @min_data_file_size) / @min_data_file_size) * 100;
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
                'TempDB Configuration',
                'Single TempDB Data File',
                'TempDB has only one data file. Multiple files can reduce allocation page contention. ' + 
                'Recommendation: Use multiple files (equal to number of logical processors up to 8).',
                'https://erikdarling.com/'
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
                'TempDB Configuration',
                'Odd Number of TempDB Files',
                'TempDB has ' + CONVERT(nvarchar(10), @tempdb_data_file_count) + 
                ' data files. This is an odd number and not equal to the ' +
                CONVERT(nvarchar(10), @processors) + ' logical processors. ' +
                'Consider using an even number of files for better performance.',
                'https://erikdarling.com/'
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
                'TempDB Configuration',
                'More TempDB Files Than CPUs',
                'TempDB has ' + CONVERT(nvarchar(10), @tempdb_data_file_count) + 
                ' data files, which is more than the ' +
                CONVERT(nvarchar(10), @processors) + 
                ' logical processors. ',
                'https://erikdarling.com/'
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
                'TempDB Configuration',
                'Uneven TempDB Data File Sizes',
                'TempDB data files vary in size by ' + 
                CONVERT(nvarchar(10), CONVERT(integer, @size_difference_pct)) + 
                '%. Smallest: ' + 
                CONVERT(nvarchar(10), CONVERT(integer, @min_data_file_size)) + 
                ' gB, Largest: ' + 
                CONVERT(nvarchar(10), CONVERT(integer, @max_data_file_size)) + 
                ' gB. For best performance, TempDB data files should be the same size.',
                'https://erikdarling.com/'
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
                'TempDB Configuration',
                'Mixed TempDB Autogrowth Settings',
                'TempDB data files have inconsistent autogrowth settings - some use percentage growth and others use fixed size growth. ' +
                'This can lead to uneven file sizes over time. Use consistent settings for all files.',
                'https://erikdarling.com/'
            );
        END;
                
        /* Memory configuration checks */
        IF @min_server_memory >= @max_server_memory * 0.9 /* Within 10% */
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
                'Server Configuration',
                'Min Server Memory Too Close To Max',
                'Min server memory (' + CONVERT(nvarchar(20), @min_server_memory) + 
                ' MB) is >= 90% of max server memory (' + CONVERT(nvarchar(20), @max_server_memory) + 
                ' MB). This prevents SQL Server from dynamically adjusting memory.',
                'https://erikdarling.com/'
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
                'Server Configuration',
                'Max Server Memory Too Close To Physical Memory',
                'Max server memory (' + CONVERT(nvarchar(20), @max_server_memory) + 
                ' MB) is >= 95% of physical memory (' + CONVERT(nvarchar(20), CONVERT(bigint, @physical_memory_gb * 1024)) + 
                ' MB). This may not leave enough memory for the OS and other processes.',
                'https://erikdarling.com/'
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
                'Server Configuration',
                'MAXDOP Not Configured',
                'Max degree of parallelism is set to 0 (default) on a server with ' + 
                CONVERT(nvarchar(10), @processors) + 
                ' logical processors. This can lead to excessive parallelism.',
                'https://erikdarling.com/'
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
                'Server Configuration',
                'Low Cost Threshold for Parallelism',
                'Cost threshold for parallelism is set to ' + CONVERT(nvarchar(10), @cost_threshold) + 
                '. Low values can cause excessive parallelism for small queries.',
                'https://erikdarling.com/'
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
                'Server Configuration',
                'Priority Boost Enabled',
                'Priority boost is enabled. This can cause issues with Windows scheduling priorities and is not recommended.',
                'https://erikdarling.com/'
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
                'Server Configuration',
                'Lightweight Pooling Enabled',
                'Lightweight pooling (fiber mode) is enabled. This is rarely beneficial and can cause issues with OLEDB providers and other components.',
                'https://erikdarling.com/'
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
            category = 'Server Configuration',
            finding = 'Configuration Pending Restart',
            details = 
                'The configuration option "' + 
                c.name + 
                '" has been changed but requires a restart to take effect. ' +
                'Current value: ' + CONVERT(nvarchar(50), c.value) + ', ' +
                'Pending value: ' + CONVERT(nvarchar(50), c.value_in_use),
            url = 'https://erikdarling.com/'
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
            feature_check = 'Database columns',
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
            database_name = DB_NAME(),
            database_id = DB_ID(),
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
        DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT database_name, database_id
            FROM #database_list;
            
        OPEN db_cursor;
        FETCH NEXT FROM db_cursor INTO @current_database_name, @current_database_id;
        
        WHILE @@FETCH_STATUS = 0
        BEGIN
            /* Try to access database using three-part naming to ensure we have proper permissions */
            BEGIN TRY                
                SET @sql = N'
                SELECT 
                    @has_tables = 
                        CASE 
                            WHEN EXISTS (SELECT 1/0 FROM ' + QUOTENAME(@current_database_name) + '.sys.tables AS t) 
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
                    SET @message = N'Cannot access database: ' + @current_database_name;
                    RAISERROR(@message, 0, 1) WITH NOWAIT;
                END;
            END CATCH;
            
            FETCH NEXT FROM db_cursor INTO @current_database_name, @current_database_id;
        END;
        
        CLOSE db_cursor;
        DEALLOCATE db_cursor;
    END;
    
    IF @debug = 1
    BEGIN
        SELECT * FROM #database_list;
    END;
    
    /*
    Database Iteration and Checks
    */
    DECLARE database_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT database_name, database_id
        FROM #database_list
        WHERE can_access = 1;
        
    OPEN database_cursor;
    FETCH NEXT FROM database_cursor INTO @current_database_name, @current_database_id;
    
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
        
        /* Analyze database configuration settings */
        
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
            category = 'Database Configuration',
            finding = 'Auto-Shrink Enabled',
            database_name = d.name,
            details = 
                'Database has auto-shrink enabled, which can cause significant performance problems and fragmentation. 
                 This setting can lead to performance issues.',
            url = 'https://erikdarling.com/'
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
            category = 'Database Configuration',
            finding = 'Auto-Close Enabled',
            database_name = d.name,
            details = 
                'Database has auto-close enabled, which can cause connection delays while the database is reopened. 
                 This setting can impact performance for applications that frequently connect to and disconnect from the database.',
            url = 'https://erikdarling.com/'
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
            category = 'Database Configuration',
            finding = 
                'Restricted Access Mode: ' + 
                d.user_access_desc,
            database_name = d.name,
            details = 
                'Database is not in MULTI_USER mode. Current mode: ' + 
                d.user_access_desc + '. 
                This restricts normal database access and may prevent applications from connecting.',
            url = 'https://erikdarling.com/'
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
            category = 'Database Configuration',
            finding = 
                CASE 
                    WHEN d.is_auto_create_stats_on = 0 AND d.is_auto_update_stats_on = 0
                    THEN 'Auto Create and Update Statistics Disabled'
                    WHEN d.is_auto_create_stats_on = 0
                    THEN 'Auto Create Statistics Disabled'
                    WHEN d.is_auto_update_stats_on = 0
                    THEN 'Auto Update Statistics Disabled'
                END,
            database_name = d.name,
            details = 
                CASE 
                    WHEN d.is_auto_create_stats_on = 0 
                    AND  d.is_auto_update_stats_on = 0
                    THEN 'Both auto create and auto update statistics are disabled. This can lead to poor query performance due to outdated or missing statistics.'
                    WHEN d.is_auto_create_stats_on = 0
                    THEN 'Auto create statistics is disabled. This can lead to suboptimal query plans for columns without statistics.'
                    WHEN d.is_auto_update_stats_on = 0
                    THEN 'Auto update statistics is disabled. This can lead to poor query performance due to outdated statistics.'
                END,
            url = 'https://erikdarling.com/'
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
            category = 'Database Configuration',
            finding = 'Non-Standard ANSI Settings',
            database_name = d.name,
            details = 
                'Database has non-standard ANSI settings: ' +
                      CASE WHEN d.is_ansi_null_default_on = 1 THEN 'ANSI_NULL_DEFAULT ON, ' ELSE '' END +
                      CASE WHEN d.is_ansi_nulls_on = 1 THEN 'ANSI_NULLS OFF, ' ELSE '' END +
                      CASE WHEN d.is_ansi_padding_on = 1 THEN 'ANSI_PADDING OFF, ' ELSE '' END +
                      CASE WHEN d.is_ansi_warnings_on = 1 THEN 'ANSI_WARNINGS OFF, ' ELSE '' END +
                      CASE WHEN d.is_arithabort_on = 1 THEN 'ARITHABORT OFF, ' ELSE '' END +
                      CASE WHEN d.is_concat_null_yields_null_on = 1 THEN 'CONCAT_NULL_YIELDS_NULL OFF, ' ELSE '' END +
                      CASE WHEN d.is_numeric_roundabort_on = 1 THEN 'NUMERIC_ROUNDABORT ON, ' ELSE '' END +
                      CASE WHEN d.is_quoted_identifier_on = 1 THEN 'QUOTED_IDENTIFIER OFF, ' ELSE '' END +
                'which can cause unexpected application behavior and compatibility issues.',
            url = 'https://erikdarling.com/'
        FROM #databases AS d
        WHERE d.database_id = @current_database_id
        AND 
        (
             d.is_ansi_null_default_on = 1
          OR d.is_ansi_nulls_on = 1
          OR d.is_ansi_padding_on = 2
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
            category = 'Database Configuration',
            finding = 'Query Store Not Enabled',
            database_name = d.name,
            details = 'Query Store is not enabled. Consider enabling Query Store to track query performance over time and identify regression issues.',
            url = 'https://erikdarling.com/'
        FROM #databases AS d
        WHERE d.database_id = @current_database_id
        AND   d.is_query_store_on = 0;
        
        /* Check for Query Store in problematic state */
        BEGIN TRY
            SET @sql = N'
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
                check_id = 7011,
                priority = 40, /* Medium-high priority */
                category = ''Database Configuration'',
                finding = ''Query Store State Mismatch'',
                database_name = DB_NAME(),
                details = 
                    ''Query Store desired state ('' + 
                    qso.desired_state_desc + 
                    '') does not match actual state ('' + 
                    qso.actual_state_desc + ''). '' +
                    CASE qso.readonly_reason
                        WHEN 0 THEN ''No specific reason identified.''
                        WHEN 2 THEN ''Database is in single user mode.''
                        WHEN 4 THEN ''Database is in emergency mode.''
                        WHEN 8 THEN ''Database is an Availability Group secondary.''
                        WHEN 65536 THEN ''Query Store has reached maximum size: '' + 
                                        CONVERT(nvarchar(20), qso.current_storage_size_mb) + 
                                        '' of '' + 
                                        CONVERT(nvarchar(20), qso.max_storage_size_mb) + 
                                        '' MB.''
                        WHEN 131072 THEN ''The number of different statements in Query Store has reached the internal memory limit.''
                        WHEN 262144 THEN ''Size of in-memory items waiting to be persisted on disk has reached the internal memory limit.''
                        WHEN 524288 THEN ''Database has reached disk size limit.''
                        ELSE ''Unknown reason code: '' + CONVERT(nvarchar(20), qso.readonly_reason)
                    END,
                url = ''https://erikdarling.com/''
            FROM ' + QUOTENAME(@current_database_name) + '.sys.database_query_store_options AS qso
            WHERE qso.desired_state <> 0 /* Not intentionally OFF */
            AND   qso.readonly_reason <> 8 /* Ignore AG secondaries */
            AND   qso.desired_state <> qso.actual_state /* States don''t match */
            AND   qso.actual_state IN (0, 3); /* Either OFF or READ_ONLY when it shouldn''t be */';
            
            IF @debug = 1
            BEGIN
                PRINT @sql;
            END;
            
            EXECUTE sys.sp_executesql 
                @sql;
            
            /* Check for Query Store with potentially problematic settings */
            SET @sql = N'
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
                check_id = 7012,
                priority = 50, /* Medium priority */
                category = ''Database Configuration'',
                finding = ''Query Store Suboptimal Configuration'',
                database_name = DB_NAME(),
                details = 
                    CASE
                        WHEN qso.max_storage_size_mb < 1024 
                        THEN ''Query Store max size ('' + 
                             CONVERT(nvarchar(20), qso.max_storage_size_mb) + 
                             '' MB) is less than 1 GB. This may be too small for production databases.''
                        WHEN qso.query_capture_mode_desc = ''NONE'' 
                        THEN ''Query Store capture mode is set to NONE. No new queries will be captured.''
                        WHEN qso.size_based_cleanup_mode_desc = ''OFF'' 
                        THEN ''Size-based cleanup is disabled. Query Store may fill up and become read-only.''
                        WHEN qso.stale_query_threshold_days < 3 
                        THEN ''Stale query threshold is only '' + 
                             CONVERT(nvarchar(20), qso.stale_query_threshold_days) + 
                             '' days. Short retention periods may lose historical performance data.''
                        WHEN qso.max_plans_per_query < 10 
                        THEN ''Max plans per query is only '' + 
                             CONVERT(nvarchar(20), qso.max_plans_per_query) + 
                             ''. This may cause relevant plans to be purged prematurely.''
                    END,
                url = ''https://erikdarling.com/''
            FROM ' + QUOTENAME(@current_database_name) + '.sys.database_query_store_options AS qso
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
            
            EXECUTE sys.sp_executesql 
                @sql;
            
            /* Check for non-default database scoped configurations */
            /* First check if the sys.database_scoped_configurations view exists */
            SET @sql = N'
            IF EXISTS (SELECT 1/0 FROM ' + QUOTENAME(@current_database_name) + '.sys.all_objects AS ao WHERE ao.name = N''database_scoped_configurations'')
            BEGIN
                /* Delete any existing values for this database */
                DELETE FROM #database_scoped_configs 
                WHERE database_id = ' + CONVERT(nvarchar(10), @current_database_id) + ';
                
                /* Insert default values as reference for comparison */
                INSERT INTO #database_scoped_configs 
                    (database_id, database_name, configuration_id, name, value, value_for_secondary, is_value_default)
                VALUES
                    (' + CONVERT(nvarchar(10), @current_database_id) + ', N''' + @current_database_name + ''', 1, N''MAXDOP'', NULL, NULL, 1),
                    (' + CONVERT(nvarchar(10), @current_database_id) + ', N''' + @current_database_name + ''', 2, N''LEGACY_CARDINALITY_ESTIMATION'', NULL, NULL, 1),
                    (' + CONVERT(nvarchar(10), @current_database_id) + ', N''' + @current_database_name + ''', 3, N''PARAMETER_SNIFFING'', NULL, NULL, 1),
                    (' + CONVERT(nvarchar(10), @current_database_id) + ', N''' + @current_database_name + ''', 4, N''QUERY_OPTIMIZER_HOTFIXES'', NULL, NULL, 1),
                    (' + CONVERT(nvarchar(10), @current_database_id) + ', N''' + @current_database_name + ''', 7, N''INTERLEAVED_EXECUTION_TVF'', NULL, NULL, 1),
                    (' + CONVERT(nvarchar(10), @current_database_id) + ', N''' + @current_database_name + ''', 8, N''BATCH_MODE_MEMORY_GRANT_FEEDBACK'', NULL, NULL, 1),
                    (' + CONVERT(nvarchar(10), @current_database_id) + ', N''' + @current_database_name + ''', 9, N''BATCH_MODE_ADAPTIVE_JOINS'', NULL, NULL, 1),
                    (' + CONVERT(nvarchar(10), @current_database_id) + ', N''' + @current_database_name + ''', 10, N''TSQL_SCALAR_UDF_INLINING'', NULL, NULL, 1),
                    (' + CONVERT(nvarchar(10), @current_database_id) + ', N''' + @current_database_name + ''', 13, N''OPTIMIZE_FOR_AD_HOC_WORKLOADS'', NULL, NULL, 1),
                    (' + CONVERT(nvarchar(10), @current_database_id) + ', N''' + @current_database_name + ''', 16, N''ROW_MODE_MEMORY_GRANT_FEEDBACK'', NULL, NULL, 1),
                    (' + CONVERT(nvarchar(10), @current_database_id) + ', N''' + @current_database_name + ''', 17, N''ISOLATE_SECURITY_POLICY_CARDINALITY'', NULL, NULL, 1),
                    (' + CONVERT(nvarchar(10), @current_database_id) + ', N''' + @current_database_name + ''', 18, N''BATCH_MODE_ON_ROWSTORE'', NULL, NULL, 1),
                    (' + CONVERT(nvarchar(10), @current_database_id) + ', N''' + @current_database_name + ''', 19, N''DEFERRED_COMPILATION_TV'', NULL, NULL, 1),
                    (' + CONVERT(nvarchar(10), @current_database_id) + ', N''' + @current_database_name + ''', 20, N''ACCELERATED_PLAN_FORCING'', NULL, NULL, 1),
                    (' + CONVERT(nvarchar(10), @current_database_id) + ', N''' + @current_database_name + ''', 24, N''LAST_QUERY_PLAN_STATS'', NULL, NULL, 1),
                    (' + CONVERT(nvarchar(10), @current_database_id) + ', N''' + @current_database_name + ''', 27, N''EXEC_QUERY_STATS_FOR_SCALAR_FUNCTIONS'', NULL, NULL, 1),
                    (' + CONVERT(nvarchar(10), @current_database_id) + ', N''' + @current_database_name + ''', 28, N''PARAMETER_SENSITIVE_PLAN_OPTIMIZATION'', NULL, NULL, 1),
                    (' + CONVERT(nvarchar(10), @current_database_id) + ', N''' + @current_database_name + ''', 31, N''CE_FEEDBACK'', NULL, NULL, 1),
                    (' + CONVERT(nvarchar(10), @current_database_id) + ', N''' + @current_database_name + ''', 33, N''MEMORY_GRANT_FEEDBACK_PERSISTENCE'', NULL, NULL, 1),
                    (' + CONVERT(nvarchar(10), @current_database_id) + ', N''' + @current_database_name + ''', 34, N''MEMORY_GRANT_FEEDBACK_PERCENTILE_GRANT'', NULL, NULL, 1),
                    (' + CONVERT(nvarchar(10), @current_database_id) + ', N''' + @current_database_name + ''', 35, N''OPTIMIZED_PLAN_FORCING'', NULL, NULL, 1),
                    (' + CONVERT(nvarchar(10), @current_database_id) + ', N''' + @current_database_name + ''', 37, N''DOP_FEEDBACK'', NULL, NULL, 1),
                    (' + CONVERT(nvarchar(10), @current_database_id) + ', N''' + @current_database_name + ''', 39, N''FORCE_SHOWPLAN_RUNTIME_PARAMETER_COLLECTION'', NULL, NULL, 1);
                
                /* Get actual non-default settings */
                INSERT INTO #database_scoped_configs 
                    (database_id, database_name, configuration_id, name, value, value_for_secondary, is_value_default)
                SELECT 
                    ' + CONVERT(nvarchar(10), @current_database_id) + ', 
                    N''' + @current_database_name + ''', 
                    sc.configuration_id, 
                    sc.name, 
                    sc.value, 
                    sc.value_for_secondary, 
                    CASE
                        WHEN sc.name = ''MAXDOP'' AND CAST(sc.value AS integer) = 0 THEN 1
                        WHEN sc.name = ''LEGACY_CARDINALITY_ESTIMATION'' AND CAST(sc.value AS integer) = 0 THEN 1
                        WHEN sc.name = ''PARAMETER_SNIFFING'' AND CAST(sc.value AS integer) = 1 THEN 1
                        WHEN sc.name = ''QUERY_OPTIMIZER_HOTFIXES'' AND CAST(sc.value AS integer) = 0 THEN 1
                        WHEN sc.name = ''INTERLEAVED_EXECUTION_TVF'' AND CAST(sc.value AS integer) = 1 THEN 1
                        WHEN sc.name = ''BATCH_MODE_MEMORY_GRANT_FEEDBACK'' AND CAST(sc.value AS integer) = 1 THEN 1
                        WHEN sc.name = ''BATCH_MODE_ADAPTIVE_JOINS'' AND CAST(sc.value AS integer) = 1 THEN 1
                        WHEN sc.name = ''TSQL_SCALAR_UDF_INLINING'' AND CAST(sc.value AS integer) = 1 THEN 1
                        WHEN sc.name = ''OPTIMIZE_FOR_AD_HOC_WORKLOADS'' AND CAST(sc.value AS integer) = 0 THEN 1
                        WHEN sc.name = ''ROW_MODE_MEMORY_GRANT_FEEDBACK'' AND CAST(sc.value AS integer) = 1 THEN 1
                        WHEN sc.name = ''ISOLATE_SECURITY_POLICY_CARDINALITY'' AND CAST(sc.value AS integer) = 0 THEN 1
                        WHEN sc.name = ''BATCH_MODE_ON_ROWSTORE'' AND CAST(sc.value AS integer) = 1 THEN 1
                        WHEN sc.name = ''DEFERRED_COMPILATION_TV'' AND CAST(sc.value AS integer) = 1 THEN 1
                        WHEN sc.name = ''ACCELERATED_PLAN_FORCING'' AND CAST(sc.value AS integer) = 1 THEN 1
                        WHEN sc.name = ''LAST_QUERY_PLAN_STATS'' AND CAST(sc.value AS integer) = 0 THEN 1
                        WHEN sc.name = ''EXEC_QUERY_STATS_FOR_SCALAR_FUNCTIONS'' AND CAST(sc.value AS integer) = 1 THEN 1
                        WHEN sc.name = ''PARAMETER_SENSITIVE_PLAN_OPTIMIZATION'' AND CAST(sc.value AS integer) = 1 THEN 1
                        WHEN sc.name = ''CE_FEEDBACK'' AND CAST(sc.value AS integer) = 1 THEN 1
                        WHEN sc.name = ''MEMORY_GRANT_FEEDBACK_PERSISTENCE'' AND CAST(sc.value AS integer) = 1 THEN 1
                        WHEN sc.name = ''MEMORY_GRANT_FEEDBACK_PERCENTILE_GRANT'' AND CAST(sc.value AS integer) = 1 THEN 1
                        WHEN sc.name = ''OPTIMIZED_PLAN_FORCING'' AND CAST(sc.value AS integer) = 1 THEN 1
                        WHEN sc.name = ''DOP_FEEDBACK'' AND CAST(sc.value AS integer) = 0 THEN 1
                        WHEN sc.name = ''FORCE_SHOWPLAN_RUNTIME_PARAMETER_COLLECTION'' AND CAST(sc.value AS integer) = 0 THEN 1
                        ELSE 0 /* Non-default */
                    END
                FROM ' + QUOTENAME(@current_database_name) + '.sys.database_scoped_configurations AS sc;
            END;';
                
            IF @debug = 1
            BEGIN
                PRINT @sql;
            END;
                
            EXECUTE sys.sp_executesql 
                @sql;
                
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
                    category = 'Database Configuration',
                    finding = 'Non-Default Database Scoped Configuration',
                    database_name = dsc.database_name,
                    object_name = dsc.name,
                    details = 
                        'Database uses non-default setting for ' + 
                        dsc.name + 
                        ': ' + 
                        ISNULL(CONVERT(nvarchar(100), dsc.value), 'NULL') + 
                        CASE 
                            WHEN dsc.value_for_secondary IS NOT NULL 
                            THEN ' (Secondary: ' + 
                            CONVERT(nvarchar(100), dsc.value_for_secondary) + 
                            ')'
                            ELSE ''
                        END + 
                        '. ' +
                        CASE dsc.name
                             WHEN 'MAXDOP' THEN 'Controls degree of parallelism for queries in this database.'
                             WHEN 'LEGACY_CARDINALITY_ESTIMATION' THEN 'Controls whether the query optimizer uses the SQL Server 2014 or earlier cardinality estimation model.'
                             WHEN 'PARAMETER_SNIFFING' THEN 'Controls parameter sniffing behavior for the database.'
                             WHEN 'QUERY_OPTIMIZER_HOTFIXES' THEN 'Controls whether query optimizer hotfixes are enabled.'
                             WHEN 'OPTIMIZE_FOR_AD_HOC_WORKLOADS' THEN 'Controls caching behavior for single-use query plans.'
                             WHEN 'ACCELERATED_PLAN_FORCING' THEN 'Controls whether query plans can be forced in an accelerated way.'
                             WHEN 'BATCH_MODE_ON_ROWSTORE' THEN 'Controls whether batch mode processing can be used on rowstore indexes.'
                             ELSE 'Controls ' + REPLACE(LOWER(dsc.name), '_', ' ') + ' behavior.'
                        END,
                    url = 'https://erikdarling.com/'
                FROM #database_scoped_configs AS dsc
                WHERE dsc.database_id = @current_database_id
                AND   dsc.is_value_default = 0;
        END TRY
        BEGIN CATCH
            IF @debug = 1
            BEGIN
                SET @message = N'Error checking database configuration for ' + @current_database_name + ': ' + ERROR_MESSAGE();
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
            category = 'Database Configuration',
            finding = 'Non-Default Target Recovery Time',
            database_name = d.name,
            details = 
                'Database target recovery time is ' + 
                CONVERT(nvarchar(20), d.target_recovery_time_in_seconds) + 
                ' seconds, which differs from the default of 60 seconds. This affects checkpoint frequency and recovery time.',
            url = 'https://erikdarling.com/'
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
            category = 'Database Configuration',
            finding = 'Delayed Durability: ' + d.delayed_durability_desc,
            database_name = d.name,
            details = 
                'Database uses ' + 
                d.delayed_durability_desc + 
                ' durability mode. This can improve performance but increases the risk of data loss during a server failure.',
            url = 'https://erikdarling.com/'
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
            category = 'Database Configuration',
            finding = 'Accelerated Database Recovery Not Enabled With Snapshot Isolation',
            database_name = d.name,
            details = 
                'Database has Snapshot Isolation or RCSI enabled but Accelerated Database Recovery (ADR) is disabled. ' +
                'ADR can significantly improve performance with these isolation levels by reducing version store cleanup overhead.',
            url = 'https://erikdarling.com/'
        FROM #databases AS d
        WHERE d.database_id = @current_database_id
        AND   d.is_accelerated_database_recovery_on = 0
        AND  (d.snapshot_isolation_state_desc = N'ON' OR d.is_read_committed_snapshot_on = 1);
        
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
            category = 'Database Configuration',
            finding = 'Ledger Feature Enabled',
            database_name = d.name,
            details = 
                'Database has the ledger feature enabled, which adds blockchain-like capabilities 
                 but may impact performance due to additional overhead for maintaining cryptographic verification.',
            url = 'https://erikdarling.com/'
        FROM #databases AS d
        WHERE d.database_id = @current_database_id
        AND   d.is_ledger_on = 1;
        
        /* Check for database file growth settings */
        BEGIN TRY
            /* Check for percentage growth settings on data files */
            SET @sql = N'
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
                check_id = 7101,
                priority = 40, /* Medium-high priority */
                category = ''Database Files'',
                finding = ''Percentage Auto-Growth Setting on Data File'',
                database_name = DB_NAME(),
                object_name = mf.name,
                details = 
                    ''Database data file is using percentage growth setting ('' + 
                    CONVERT(nvarchar(20), mf.growth) + 
                    ''%). This can lead to increasingly larger growth events as the file grows, 
                    potentially causing larger file sizes than intended. Even with instant file initialization enabled, 
                    consider using a fixed size instead for more predictable growth.'',
                url = ''https://erikdarling.com/''
            FROM ' + QUOTENAME(@current_database_name) + '.sys.database_files AS mf
            WHERE mf.is_percent_growth = 1
            AND   mf.type_desc = N''ROWS'';';
            
            IF @debug = 1
            BEGIN
                PRINT @sql;
            END;
            
            EXECUTE sys.sp_executesql 
                @sql;
            
            /* Check for percentage growth settings on log files */
            SET @sql = N'
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
                check_id = 7102,
                priority = 30, /* High priority */
                category = ''Database Files'',
                finding = ''Percentage Auto-Growth Setting on Log File'',
                database_name = DB_NAME(),
                object_name = mf.name,
                details = 
                    ''Transaction log file is using percentage growth setting ('' + 
                    CONVERT(nvarchar(20), mf.growth) + 
                    ''%). This can lead to increasingly larger growth events and significant stalls 
                    as log files must be zeroed out during auto-growth operations. 
                    Always use fixed size growth for log files.'',
                url = ''https://erikdarling.com/''
            FROM ' + QUOTENAME(@current_database_name) + '.sys.database_files AS mf
            WHERE mf.is_percent_growth = 1
            AND   mf.type_desc = N''LOG'';';
            
            IF @debug = 1
            BEGIN
                PRINT @sql;
            END;
            
            EXECUTE sys.sp_executesql 
                @sql;

            /* Check for non-optimal log growth increments in SQL Server 2022, Azure SQL DB, or Azure MI */
            IF @product_version_major >= 16 OR @azure_sql_db = 1 OR @azure_managed_instance = 1
            BEGIN
                SET @sql = N'
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
                    check_id = 7103,
                    priority = 40, /* Medium-high priority */
                    category = ''Database Files'',
                    finding = ''Non-Optimal Log File Growth Increment'',
                    database_name = DB_NAME(),
                    object_name = mf.name,
                    details = 
                        ''Transaction log file is using a growth increment of '' + 
                        CONVERT(nvarchar(20), CONVERT(decimal(18, 2), mf.growth * 8.0 / 1024)) + '' MB. '' +
                        ''On SQL Server 2022, Azure SQL DB, or Azure MI, transaction logs can use instant file initialization when set to exactly 64 MB. '' +
                        ''Consider changing the growth increment to 64 MB for improved performance.'',
                    url = ''https://erikdarling.com/''
                FROM ' + QUOTENAME(@current_database_name) + '.sys.database_files AS mf
                WHERE mf.is_percent_growth = 0
                AND   mf.type_desc = N''LOG''
                AND   mf.growth * 8.0 / 1024 <> 64;';
                
                IF @debug = 1
                BEGIN
                    PRINT @sql;
                END;
                
                EXECUTE sys.sp_executesql 
                    @sql;
            END;
            
            /* Check for very large fixed growth settings (>10GB) */
            SET @sql = N'
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
                check_id = 7104,
                priority = 40, /* Medium-high priority */
                category = ''Database Files'',
                finding = ''Extremely Large Auto-Growth Setting'',
                database_name = DB_NAME(),
                object_name = mf.name,
                details = 
                    ''Database file is using a very large fixed growth increment of '' + 
                    CONVERT(nvarchar(20), CONVERT(decimal(18, 2), mf.growth * 8.0 / 1024 / 1024)) + 
                    '' GB. Very large growth increments can lead to excessive space allocation. '' +
                    CASE 
                        WHEN mf.type_desc = ''ROWS'' THEN ''Even with instant file initialization, consider using smaller increments for more controlled growth.''
                        WHEN mf.type_desc = ''LOG'' THEN ''This can cause significant stalls as log files must be zeroed out during growth operations.''
                    END,
                url = ''https://erikdarling.com/''
            FROM ' + QUOTENAME(@current_database_name) + '.sys.database_files AS mf
            WHERE mf.is_percent_growth = 0
            AND   mf.growth * 8.0 / 1024 / 1024 > 10; /* Growth > 10GB */';
            
            IF @debug = 1
            BEGIN
                PRINT @sql;
            END;
            
            EXECUTE sys.sp_executesql 
                @sql;
        END TRY
        BEGIN CATCH
            IF @debug = 1
            BEGIN
                SET @message = N'Error checking database file growth settings for ' + @current_database_name + ': ' + ERROR_MESSAGE();
                RAISERROR(@message, 0, 1) WITH NOWAIT;
            END;
        END CATCH;
        
        /* 
        Execute the dynamic SQL - this is just a placeholder.
        In your actual implementation, you would include all your database-level 
        performance checks here, using three-part naming for all system objects.
        */
        BEGIN TRY
            EXEC(@sql);
        END TRY
        BEGIN CATCH
            IF @debug = 1
            BEGIN
                SET @message = N'Error checking database ' + @current_database_name + ': ' + ERROR_MESSAGE();
                RAISERROR(@message, 0, 1) WITH NOWAIT;
            END;
        END CATCH;
        
        /* 
        Object-level checks would follow a similar pattern:
        1. Build dynamic SQL using three-part naming
        2. Execute within TRY/CATCH
        3. Move to next database
        */
        
        FETCH NEXT FROM database_cursor INTO @current_database_name, @current_database_id;
    END;
    
    CLOSE database_cursor;
    DEALLOCATE database_cursor;
    
    /*
    Return Server Info First
    */
    SELECT
        info_type AS [Server Information],
        value AS [Details]
    FROM #server_info
    ORDER BY
        id;
        
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