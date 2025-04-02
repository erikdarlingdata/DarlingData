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
        @product_version sysname,
        @product_version_major decimal(10, 2),
        @product_version_minor decimal(10, 2),
        @error_message nvarchar(4000),
        @start_time datetime2(0),
        @sql nvarchar(max) = N'',
        @engine_edition integer,
        @azure_sql_db bit = 0,
        @azure_managed_instance bit = 0,
        @aws_rds bit = 0,
        @is_sysadmin bit,
        @has_view_server_state bit,
        @current_database_name sysname,
        @current_database_id integer,
        @processors integer,
        @numa_nodes integer,
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
        @mirroring_count integer,
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
        @autogrow_summary nvarchar(max),
        @has_tables bit;
    
    /* Set start time for runtime tracking */
    SET @start_time = SYSDATETIME();
    
    /* Store version properties for later use */
    SELECT 
        @product_version = CAST(SERVERPROPERTY('ProductVersion') AS sysname), 
        @product_version_major = SUBSTRING(@product_version, 1, CHARINDEX('.', @product_version) + 1),
        @product_version_minor = PARSENAME(CONVERT(varchar(32), @product_version), 2),
        @engine_edition = CAST(SERVERPROPERTY('EngineEdition') AS integer);
    
    /* Check permissions */
    SELECT 
        @is_sysadmin = ISNULL(IS_SRVROLEMEMBER('sysadmin'), 0);
    
    /* Check for VIEW SERVER STATE permission */
    BEGIN TRY
        EXECUTE ('DECLARE @c bigint; SELECT @c = 1 FROM sys.dm_os_sys_info AS osi;');
        SET @has_view_server_state = 1;
    END TRY
    BEGIN CATCH
        SET @has_view_server_state = 0;
    END CATCH;
    
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
    */
    CREATE TABLE 
        #databases
    (
        name sysname NOT NULL,
        database_id integer NOT NULL,
        compatibility_level tinyint NOT NULL,
        collation_name sysname NOT NULL,
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
        target_recovery_time_in_seconds integer NOT NULL,
        delayed_durability_desc nvarchar(60) NOT NULL,
        is_accelerated_database_recovery_on bit NOT NULL,
        is_memory_optimized_enabled bit NOT NULL,
        is_ledger_on bit NULL
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
        id integer IDENTITY(1, 1) PRIMARY KEY CLUSTERED,
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
        drive_letter nchar(1) NULL,
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
        text_data nvarchar(max) NULL,
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
        CONVERT(nvarchar(30), DATEDIFF(DAY, osi.sqlserver_start_time, GETDATE())) + ' days, ' +
        CONVERT(nvarchar(8), CONVERT(time, DATEADD(SECOND, DATEDIFF(SECOND, osi.sqlserver_start_time, GETDATE()) % 86400, '00:00:00')), 108) + ' (hh:mm:ss)'
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
                'Check affinity mask configuration, and licensing.',
            url = 'https://erikdarling.com/'
        FROM sys.dm_os_schedulers AS dos
        WHERE dos.scheduler_id < 255 /* Only CPU schedulers, not internal or hidden schedulers */
        AND   dos.status = N'VISIBLE OFFLINE'
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
            CONVERT(nvarchar(10), MAX(forced_grant_count)) + 
            ' forced grants. ' +
            'Target memory: ' + CONVERT(nvarchar(20), MAX(ders.target_memory_kb) / 1024) + ' MB, ' +
            'Available memory: ' + CONVERT(nvarchar(20), MAX(ders.available_memory_kb) / 1024) + ' MB, ' +
            'Granted memory: ' + CONVERT(nvarchar(20), MAX(ders.granted_memory_kb) / 1024) + ' MB. ' +
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
                WHEN (1.0 * p.cntr_value / NULLIF(DATEDIFF(DAY, osi.sqlserver_start_time, GETDATE()), 0)) > 100 THEN 20 /* Very high priority */
                WHEN (1.0 * p.cntr_value / NULLIF(DATEDIFF(DAY, osi.sqlserver_start_time, GETDATE()), 0)) > 50 THEN 30 /* High priority */
                ELSE 40 /* Medium-high priority */
            END,
        category = 'Concurrency',
        finding = 'High Number of Deadlocks',
        details = 
            'Server is averaging ' + 
            CONVERT(nvarchar(20), CONVERT(DECIMAL(10, 2), 1.0 * p.cntr_value / NULLIF(DATEDIFF(DAY, osi.sqlserver_start_time, GETDATE()), 0))) + 
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
    AND   (1.0 * p.cntr_value / NULLIF(DATEDIFF(DAY, osi.sqlserver_start_time, GETDATE()), 0)) > 9; /* More than 9 deadlocks per day */
    
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
                WHEN CONVERT(DECIMAL(10, 2), (domc.pages_kb / 1024.0 / 1024.0)) > 5 THEN 20 /* Very high priority >5GB */
                WHEN CONVERT(DECIMAL(10, 2), (domc.pages_kb / 1024.0 / 1024.0)) > 2 THEN 30 /* High priority >2GB */
                WHEN CONVERT(DECIMAL(10, 2), (domc.pages_kb / 1024.0 / 1024.0)) > 1 THEN 40 /* Medium-high priority >1GB */
                ELSE 50 /* Medium priority */
            END,
        category = 'Memory Usage',
        finding = 'Large Security Token Cache',
        details = 
            'TokenAndPermUserStore cache size is ' + 
            CONVERT(nvarchar(20), CONVERT(DECIMAL(10, 2), (domc.pages_kb / 1024.0 / 1024.0))) + 
            ' GB. Large security caches can consume significant memory and may indicate security-related issues ' +
            'such as excessive application role usage or frequent permission changes. ' +
            'Consider using dbo.ClearTokenPerm stored procedure to manage this issue.',
        url = 'https://www.erikdarling.com/troubleshooting-security-cache-issues-userstore_tokenperm-and-tokenandpermuserstore/'
    FROM sys.dm_os_memory_clerks AS domc
    WHERE domc.type = N'USERSTORE_TOKENPERM'
    AND   domc.name = N'TokenAndPermUserStore'
    AND   CONVERT(DECIMAL(10, 2), (domc.pages_kb / 1024.0 / 1024.0)) > 0.5; /* Only if bigger than 500MB */
    
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
                'For production SQL Servers with more than 8GB of memory, LPIM should be enabled.',
            url = 'https://erikdarling.com/'
        FROM sys.dm_os_sys_info AS osi
        WHERE osi.sql_memory_model_desc = N'CONVENTIONAL' /* Conventional means not using LPIM */
        AND   @physical_memory_gb > 8 /* Only recommend for servers with >8GB RAM */;
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
        FROM sys.dm_server_services
        WHERE filename LIKE N'%sqlservr.exe%'
        AND   servicename LIKE N'SQL Server%'
        AND   instant_file_initialization_enabled = N'N';
    END;
    
    /* Check for globally enabled trace flags (not in Azure) */
    IF  @azure_sql_db = 0
    AND @azure_managed_instance = 0
    BEGIN        
        /* Capture trace flags */
        INSERT INTO #trace_flags
        EXEC ('DBCC TRACESTATUS WITH NO_INFOMSGS');
        
        /* Add trace flags to server info */
        IF EXISTS (SELECT 1 FROM #trace_flags WHERE global = 1)
        BEGIN
            INSERT INTO
                #server_info (info_type, value)
            SELECT
                'Global Trace Flags',
                STUFF
                (
                    (
                        SELECT 
                            ', ' + CONVERT(varchar(10), trace_flag)
                        FROM #trace_flags
                        WHERE global = 1
                        ORDER BY trace_flag
                        FOR XML PATH('')
                    ), 1, 2, ''
                );
        END;
    END;
    
    /* Memory information - works on all platforms */
    INSERT INTO 
        #server_info (info_type, value)
    SELECT 
        'Memory', 
        'Total: ' + 
        CONVERT(nvarchar(20), CONVERT(decimal(10, 2), osi.physical_memory_kb / 1024.0 / 1024.0)) + ' GB, ' +
        'Target: ' + 
        CONVERT(nvarchar(20), CONVERT(decimal(10, 2), osi.committed_target_kb / 1024.0 / 1024.0)) + ' GB' +
        N', ' +
        osi.sql_memory_model_desc +
        N' enabled'
    FROM sys.dm_os_sys_info AS osi;
    
    /* Check for important events in default trace (Windows only for now) */
    IF  @azure_sql_db = 0
    BEGIN            
        /* Get default trace path */
        SELECT 
            @trace_path = REVERSE(SUBSTRING(REVERSE([path]), 
            CHARINDEX(CHAR(92), REVERSE([path])), 260)) + N'log.trc'
        FROM sys.traces
        WHERE is_default = 1;
        
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
                (137, 'Server Memory Change', 'Server'),
                (164, 'Object Altered', 'Object'),
                (166, 'Object Created', 'Object');
                
            /* Get relevant events from default trace */
            INSERT INTO #trace_events
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
                OR (t.EventClass = 116 
                    AND t.TextData LIKE '%DBCC%' 
                    AND (
                        t.TextData LIKE '%CHECKDB%' 
                        OR t.TextData LIKE '%CHECKTABLE%'
                        OR t.TextData LIKE '%FREEPROCCACHE%'
                        OR t.TextData LIKE '%FREESYSTEMCACHE%'
                        OR t.TextData LIKE '%DBCC DROPCLEANBUFFERS%'
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
            UPDATE te
            SET 
                event_name = m.event_name,
                category_name = m.category_name
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
                        WHEN event_class = 93 THEN 40 /* Log file autogrow (higher priority) */
                        ELSE 50 /* Data file autogrow */
                    END,
                category = 'Database File Configuration',
                finding = 
                    CASE
                        WHEN event_class = 92 THEN 'Slow Data File Auto Grow'
                        WHEN event_class = 93 THEN 'Slow Log File Auto Grow'
                        ELSE 'Slow File Auto Grow'
                    END,
                database_name = te.database_name,
                object_name = te.file_name,
                details = 
                    'Auto grow operation took ' + 
                    CONVERT(nvarchar(20), te.duration_ms) + ' ms (' + 
                    CONVERT(nvarchar(20), te.duration_ms / 1000.0) + ' seconds) on ' +
                    CONVERT(nvarchar(30), te.event_time, 120) + '. ' +
                    'Growth amount: ' + 
                    CONVERT(nvarchar(20), te.file_growth) + ' KB. ' +
                    'Slow auto-growth events indicate potential performance issues. Consider proactively growing files or using larger growth increments.',
                url = 'https://erikdarling.com/'
            FROM #trace_events AS te
            WHERE (event_class IN (92, 93)) /* Auto-grow events */
            AND duration_ms > @slow_autogrow_ms
            ORDER BY duration_ms DESC;
            
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
                        WHEN event_class = 94 THEN 'Data File Auto Shrink'
                        WHEN event_class = 95 THEN 'Log File Auto Shrink'
                        ELSE 'File Auto Shrink'
                    END,
                database_name = te.database_name,
                object_name = te.file_name,
                details = 
                    'Auto shrink operation occurred on ' +
                    CONVERT(nvarchar(30), te.event_time, 120) + '. ' +
                    'Auto-shrink is generally not recommended as it can lead to file fragmentation and ' +
                    'repeated grow/shrink cycles. Consider disabling auto-shrink on this database.',
                url = 'https://erikdarling.com/'
            FROM #trace_events AS te
            WHERE event_class IN (94, 95) /* Auto-shrink events */
            ORDER BY event_time DESC;
            
            /* Check for potentially problematic DBCC commands */
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
                check_id = 5003,
                priority = 
                    CASE
                        WHEN text_data LIKE '%FREEPROCCACHE%' 
                             OR text_data LIKE '%FREESYSTEMCACHE%'
                             OR text_data LIKE '%DROPCLEANBUFFERS%' THEN 40 /* Higher priority */
                        ELSE 60 /* Medium priority */
                    END,
                category = 'System Management',
                finding = 'Potentially Disruptive DBCC Command',
                database_name = te.database_name,
                details = 
                    'DBCC command executed on ' +
                    CONVERT(nvarchar(30), te.event_time, 120) + ': ' +
                    te.text_data + '. ' +
                    'This command can impact server performance or database integrity. ' +
                    'Review why these commands are being executed, especially if on a production system.',
                url = 'https://erikdarling.com/'
            FROM #trace_events AS te
            WHERE event_class = 116 /* DBCC events */
            AND text_data IS NOT NULL
            ORDER BY 
                event_time DESC;
                
            /* Get summary of autogrow events for server_info */           
            SELECT @autogrow_summary = 
                STUFF(
                (
                    SELECT 
                        N', ' + CONVERT(nvarchar(50), COUNT(*)) + 
                        N' ' + 
                        CASE 
                            WHEN event_class = 92 THEN 'data file'
                            WHEN event_class = 93 THEN 'log file'
                        END + 
                        ' autogrows'
                    FROM #trace_events
                    WHERE event_class IN (92, 93) /* Auto-grow events */
                    GROUP BY event_class
                    ORDER BY event_class
                    FOR XML PATH('')
                ), 1, 2, '');
                
            IF @autogrow_summary IS NOT NULL
            BEGIN
                INSERT INTO
                    #server_info (info_type, value)
                VALUES
                    ('Recent Autogrow Events (7 days)', @autogrow_summary);
            END;
        END;
    END;
    
    /* Check for significant wait stats */
    IF @has_view_server_state = 1
    BEGIN
        /* Create temp table for wait stats */
        CREATE TABLE #wait_stats
        (
            id integer IDENTITY(1,1) PRIMARY KEY CLUSTERED,
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
        
        /* Determine total waits, uptime, and significant waits */
        DECLARE 
            @total_waits bigint,
            @uptime_ms bigint,
            @significant_wait_threshold_pct decimal(5, 2) = 0.5, /* Only waits above 0.5% */
            @significant_wait_threshold_avg decimal(10, 2) = 10.0; /* Or avg wait time > 10ms */
            
        /* Get uptime */
        SELECT 
            @uptime_ms = DATEDIFF(MILLISECOND, sqlserver_start_time, GETDATE())
        FROM sys.dm_os_sys_info;
        
        /* Get total wait time */
        SELECT 
            @total_waits = SUM(wait_time_ms)
        FROM sys.dm_os_wait_stats
        WHERE wait_type NOT IN (
            /* Skip benign waits based on sys.dm_os_wait_stats documentation */
            N'BROKER_TASK_STOP',
            N'BROKER_TO_FLUSH',
            N'BROKER_TRANSMITTER',
            N'CHECKPOINT_QUEUE',
            N'CLR_AUTO_EVENT',
            N'CLR_MANUAL_EVENT',
            N'DIRTY_PAGE_POLL',
            N'DISPATCHER_QUEUE_SEMAPHORE',
            N'EXECSYNC',
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
            N'SLEEP_BPOOL_FLUSH',
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
        INSERT INTO #wait_stats
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
        WHERE dows.wait_type NOT IN (
            /* Skip benign waits based on sys.dm_os_wait_stats documentation */
            N'BROKER_TASK_STOP',
            N'BROKER_TO_FLUSH',
            N'BROKER_TRANSMITTER',
            N'CHECKPOINT_QUEUE',
            N'CLR_AUTO_EVENT',
            N'CLR_MANUAL_EVENT',
            N'DIRTY_PAGE_POLL',
            N'DISPATCHER_QUEUE_SEMAPHORE',
            N'EXECSYNC',
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
            N'SLEEP_BPOOL_FLUSH',
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
        )
        /* Only include specific wait types identified as important */
        AND (
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
        /* Only include waits that are significant in terms of total wait percentage or average wait time */
        AND (
            (dows.wait_time_ms * 1.0 / @total_waits) > (@significant_wait_threshold_pct / 100.0)
            OR (dows.wait_time_ms * 1.0 / NULLIF(dows.waiting_tasks_count, 0)) > @significant_wait_threshold_avg
        );
        
        /* Calculate wait time as percentage of uptime */
        UPDATE #wait_stats
        SET wait_time_percent_of_uptime = (wait_time_ms * 100.0 / @uptime_ms);
        
        /* Add top wait stats to results */
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
        SELECT TOP (10) /* Only report top 10 waits */
            check_id = 6001,
            priority = 
                CASE
                    WHEN wait_time_percent_of_uptime > 40 OR percentage > 30 THEN 30 /* High priority */
                    WHEN wait_time_percent_of_uptime > 20 OR percentage > 15 THEN 40 /* Medium-high priority */
                    ELSE 50 /* Medium priority */
                END,
            category = 'Wait Statistics',
            finding = 'Significant Wait Type: ' + wait_type + ' (' + ws.category + ')',
            details = 
                'Wait type: ' + wait_type + 
                ' represents ' + CONVERT(nvarchar(10), CONVERT(decimal(5,2), percentage)) + '% of all waits' +
                ' (' + CONVERT(nvarchar(20), CONVERT(decimal(10, 2), wait_time_minutes)) + ' minutes). ' +
                'Average wait: ' + CONVERT(nvarchar(10), CONVERT(decimal(10, 2), avg_wait_ms)) + ' ms per wait. ' +
                'This wait type represents ' + CONVERT(nvarchar(10), CONVERT(decimal(5, 2), wait_time_percent_of_uptime)) + '% of server uptime. ' +
                'Description: ' + description,
            url = 'https://erikdarling.com/'
        FROM #wait_stats AS ws
        ORDER BY 
            percentage DESC, 
            wait_time_ms DESC;
            
        /* Add wait stats summary to server info */
        INSERT INTO
            #server_info (info_type, value)
        SELECT TOP (1)
            'Wait Stats Summary',
            'Top categories: ' +
            STUFF(
            (
                SELECT 
                    TOP (3) /* Only include top 3 categories */
                    ', ' + category + ' (' + 
                    CONVERT(nvarchar(10), CONVERT(decimal(5,2), 
                        SUM(percentage))) + '%)'
                FROM #wait_stats
                GROUP BY 
                    category
                ORDER BY 
                    SUM(percentage) DESC
                FOR XML PATH('')
            ), 1, 2, '')
        FROM #wait_stats
        WHERE percentage > 0;
    END;
    
    /* Check for stolen memory from buffer pool */
    IF @has_view_server_state = 1
    BEGIN
        /* Threshold settings for stolen memory alert */
        DECLARE 
            @buffer_pool_size_gb decimal(38, 2),
            @stolen_memory_gb decimal(38, 2),
            @stolen_memory_pct decimal(10, 2),
            @stolen_memory_threshold_pct decimal(10, 2) = 25.0; /* Alert if more than 25% memory is stolen */
        
        /* Get buffer pool size */
        SELECT 
            @buffer_pool_size_gb = CONVERT(decimal(38, 2), 
                SUM(
                    CASE
                        /* Handle different SQL Server versions */
                        WHEN EXISTS (SELECT 1 FROM sys.all_columns 
                                     WHERE object_id = OBJECT_ID('sys.dm_os_memory_clerks') 
                                     AND name = 'pages_kb')
                        THEN domc.pages_kb
                        ELSE domc.single_pages_kb + domc.multi_pages_kb
                    END
                ) / 1024.0 / 1024.0
            )
        FROM sys.dm_os_memory_clerks AS domc
        WHERE domc.type = N'MEMORYCLERK_SQLBUFFERPOOL'
        AND domc.memory_node_id < 64;
        
        /* Get stolen memory */
        SELECT
            @stolen_memory_gb = CONVERT(decimal(38, 2), dopc.cntr_value / 1024.0 / 1024.0)
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
                ('Buffer Pool Size', CONVERT(nvarchar(20), @buffer_pool_size_gb) + ' GB');
                
            INSERT INTO
                #server_info (info_type, value)
            VALUES
                ('Stolen Memory', CONVERT(nvarchar(20), @stolen_memory_gb) + ' GB (' + 
                 CONVERT(nvarchar(10), CONVERT(decimal(10, 1), @stolen_memory_pct)) + '%)');
            
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
                    check_id = 6002,
                    priority = 
                        CASE
                            WHEN @stolen_memory_pct > 40 THEN 30 /* High priority if >40% stolen */
                            WHEN @stolen_memory_pct > 30 THEN 40 /* Medium-high priority if >30% stolen */
                            ELSE 50 /* Medium priority */
                        END,
                    category = 'Memory Usage',
                    finding = 'High Stolen Memory Percentage',
                    details = 
                        'Memory stolen from buffer pool: ' + CONVERT(nvarchar(20), @stolen_memory_gb) + 
                        ' GB (' + CONVERT(nvarchar(10), CONVERT(decimal(10, 1), @stolen_memory_pct)) + 
                        '% of total memory). This reduces memory available for data caching and can impact performance. ' +
                        'Consider investigating memory usage by CLR, extended stored procedures, linked servers, or other memory clerks.',
                    url = 'https://erikdarling.com/'
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
                        'Memory clerk "' + domc.type + '" is using ' + 
                        CONVERT(nvarchar(20), 
                            CONVERT(decimal(38, 2),
                                SUM(
                                    CASE
                                        /* Handle different SQL Server versions */
                                        WHEN EXISTS (SELECT 1 FROM sys.all_columns 
                                                    WHERE object_id = OBJECT_ID('sys.dm_os_memory_clerks') 
                                                    AND name = 'pages_kb')
                                        THEN domc.pages_kb
                                        ELSE domc.single_pages_kb + domc.multi_pages_kb
                                    END
                                ) / 1024.0 / 1024.0
                            )
                        ) + ' GB of memory. This is one of the top consumers of memory outside the buffer pool.',
                    url = 'https://erikdarling.com/'
                FROM sys.dm_os_memory_clerks AS domc
                WHERE domc.type <> N'MEMORYCLERK_SQLBUFFERPOOL'
                GROUP BY domc.type
                HAVING SUM(
                        CASE
                            /* Handle different SQL Server versions */
                            WHEN EXISTS (SELECT 1 FROM sys.all_columns 
                                        WHERE object_id = OBJECT_ID('sys.dm_os_memory_clerks') 
                                        AND name = 'pages_kb')
                            THEN domc.pages_kb
                            ELSE domc.single_pages_kb + domc.multi_pages_kb
                        END
                    ) / 1024.0 / 1024.0 > 0.1 /* Only show clerks using more than 100 MB */
                ORDER BY
                    SUM(
                        CASE
                            /* Handle different SQL Server versions */
                            WHEN EXISTS (SELECT 1 FROM sys.all_columns 
                                        WHERE object_id = OBJECT_ID('sys.dm_os_memory_clerks') 
                                        AND name = 'pages_kb')
                            THEN domc.pages_kb
                            ELSE domc.single_pages_kb + domc.multi_pages_kb
                        END
                    ) DESC
                OFFSET 0 ROWS
                FETCH NEXT 5 ROWS ONLY;
            END;
        END;
    END;
    
    /* Get database sizes - safely handles permissions */
    BEGIN TRY
        IF @azure_sql_db = 1
        BEGIN
            /* For Azure SQL DB, we only have access to the current database */
            INSERT INTO 
                #server_info (info_type, value)
            SELECT 
                'Database Size',
                'Allocated: ' + CONVERT(nvarchar(20), CONVERT(decimal(10, 2), SUM(df.size * 8.0 / 1024.0 / 1024.0))) + ' GB'
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
                'Allocated: ' + CONVERT(nvarchar(20), CONVERT(decimal(10, 2), SUM(mf.size * 8.0 / 1024.0 / 1024.0))) + ' GB'
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
            OR (c.name = N'ADR cleaner retry timeout (min)' AND c.value_in_use <> 120)
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
            @min_data_file_size = MIN(CASE WHEN tf.type_desc = 'ROWS' THEN tf.size_mb ELSE NULL END),
            @max_data_file_size = MAX(CASE WHEN tf.type_desc = 'ROWS' THEN tf.size_mb ELSE NULL END),
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
                2003,
                70, /* Informational */
                'TempDB Configuration',
                'More TempDB Files Than CPUs',
                'TempDB has ' + CONVERT(nvarchar(10), @tempdb_data_file_count) + 
                ' data files, which is more than the ' +
                CONVERT(nvarchar(10), @processors) + ' logical processors. ' +
                'This is not necessarily a problem, but typically not needed for systems with more than 8 cores.',
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
                'TempDB data files vary in size by ' + CONVERT(nvarchar(10), CONVERT(integer, @size_difference_pct)) + 
                '%. Smallest: ' + CONVERT(nvarchar(10), CONVERT(integer, @min_data_file_size)) + 
                ' MB, Largest: ' + CONVERT(nvarchar(10), CONVERT(integer, @max_data_file_size)) + 
                ' MB. For best performance, TempDB data files should be the same size.',
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
        
        /*
        Storage Performance Checks - I/O Latency for database files
        */
        IF @debug = 1
        BEGIN
            RAISERROR('Checking storage performance', 0, 1) WITH NOWAIT;
        END;        
        /* Gather IO Stats */
        INSERT INTO #io_stats
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
            drive_letter,
            physical_name
        )
        SELECT
            database_name = DB_NAME(fs.database_id),
            fs.database_id,
            file_name = mf.name,
            mf.type_desc,
            io_stall_read_ms = fs.io_stall_read_ms,
            num_of_reads = fs.num_of_reads,
            avg_read_latency_ms = CASE 
                                    WHEN fs.num_of_reads = 0 THEN 0
                                    ELSE fs.io_stall_read_ms * 1.0 / fs.num_of_reads
                                  END,
            io_stall_write_ms = fs.io_stall_write_ms,
            num_of_writes = fs.num_of_writes,
            avg_write_latency_ms = CASE
                                     WHEN fs.num_of_writes = 0 THEN 0
                                     ELSE fs.io_stall_write_ms * 1.0 / fs.num_of_writes
                                   END,
            io_stall_ms = fs.io_stall,
            total_io = fs.num_of_reads + fs.num_of_writes,
            avg_io_latency_ms = CASE
                                  WHEN (fs.num_of_reads + fs.num_of_writes) = 0 THEN 0
                                  ELSE fs.io_stall * 1.0 / (fs.num_of_reads + fs.num_of_writes)
                                END,
            size_mb = mf.size * 8.0 / 1024,
            drive_letter = UPPER(LEFT(mf.physical_name, 1)),
            physical_name = mf.physical_name
        FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS fs
        JOIN sys.master_files AS mf
          ON fs.database_id = mf.database_id
          AND fs.file_id = mf.file_id
        WHERE (fs.num_of_reads > 0 OR fs.num_of_writes > 0); /* Only include files with some activity */
        
        /* Add results for slow reads */
        INSERT INTO #results
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
            priority = CASE 
                          WHEN avg_read_latency_ms > @slow_read_ms * 2 THEN 40 /* Very slow */
                          ELSE 50 /* Moderately slow */
                       END,
            category = 'Storage Performance',
            finding = 'Slow Read Latency',
            database_name = database_name,
            object_name = file_name + ' (' + type_desc + ')',
            details = 'Average read latency of ' + CONVERT(nvarchar(20), CONVERT(decimal(10, 2), avg_read_latency_ms)) + 
                      ' ms for ' + CONVERT(nvarchar(20), num_of_reads) + ' reads. ' +
                      'This is above the ' + CONVERT(nvarchar(10), CONVERT(integer, @slow_read_ms)) + 
                      ' ms threshold and may indicate storage performance issues.',
            url = 'https://erikdarling.com/'
        FROM #io_stats
        WHERE avg_read_latency_ms > @slow_read_ms
        AND num_of_reads > 1000; /* Only alert if there's been a significant number of reads */
        
        /* Add results for slow writes */
        INSERT INTO #results
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
            priority = CASE 
                          WHEN avg_write_latency_ms > @slow_write_ms * 2 THEN 40 /* Very slow */
                          ELSE 50 /* Moderately slow */
                       END,
            category = 'Storage Performance',
            finding = 'Slow Write Latency',
            database_name = database_name,
            object_name = file_name + ' (' + type_desc + ')',
            details = 'Average write latency of ' + CONVERT(nvarchar(20), CONVERT(decimal(10, 2), avg_write_latency_ms)) + 
                      ' ms for ' + CONVERT(nvarchar(20), num_of_writes) + ' writes. ' +
                      'This is above the ' + CONVERT(nvarchar(10), CONVERT(integer, @slow_write_ms)) + 
                      ' ms threshold and may indicate storage performance issues.',
            url = 'https://erikdarling.com/'
        FROM #io_stats
        WHERE avg_write_latency_ms > @slow_write_ms
        AND num_of_writes > 1000; /* Only alert if there's been a significant number of writes */
        
        /* Add drive level warnings if we have multiple slow files on same drive */
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
            check_id = 3003,
            priority = 40, /* High priority */
            category = 'Storage Performance',
            finding = 'Multiple Slow Files on Drive ' + i.drive_letter,
            details = 
                'Drive ' + 
                i.drive_letter + 
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
        AND i.drive_letter IS NOT NULL
        GROUP BY 
            i.drive_letter
        HAVING 
            COUNT_BIG(*) > 1;
        
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
        AND @processors > 1
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
            AND d.state = 0; /* Only online databases */
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
            AND d.state = 0; /* Only online databases */
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
                SET @sql = N'SELECT @has_tables = CASE WHEN EXISTS(SELECT TOP 1 1 FROM ' + QUOTENAME(@current_database_name) + '.sys.tables) THEN 1 ELSE 0 END';
                EXEC sys.sp_executesql @sql, N'@has_tables BIT OUTPUT', @has_tables = @has_tables OUTPUT;
            END TRY
            BEGIN CATCH
                /* If we can't access it, mark it */
                UPDATE #database_list
                SET can_access = 0
                WHERE database_id = @current_database_id;
                
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
        
        /* Database settings check example */
        SET @sql = N'
        /* Check auto-shrink setting */
        INSERT 
            #results
        (
            check_id,
            priority,
            category,
            finding,
            database_name,
            url,
            details
        )
        SELECT 
            check_id = 3001,
            priority = 50,
            category = ''Database Configuration'',
            finding = ''Auto-Shrink Enabled'',
            database_name = N''' + @current_database_name + ''',
            url = ''https://erikdarling.com/'',
            details = ''Database has auto-shrink enabled, which can cause significant performance problems and fragmentation.''
        FROM ' + QUOTENAME(@current_database_name) + '.sys.databases d
        WHERE d.name = N''' + @current_database_name + '''
        AND d.is_auto_shrink_on = 1;';
        
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