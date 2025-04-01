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
        @slow_write_ms decimal(10, 2) = 20.0; /* Threshold for slow writes (ms) */
    
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
                CONVERT(nvarchar(10), COUNT(*)) + 
                ' CPU scheduler(s) are offline out of ' +
                CONVERT(nvarchar(10), (SELECT cpu_count FROM sys.dm_os_sys_info)) +
                ' logical processors. This reduces available processing power. ' +
                'Check MAXDOP settings, affinity mask configuration, and licensing.',
            url = 'https://erikdarling.com/'
        FROM sys.dm_os_schedulers
        WHERE scheduler_id < 255 /* Only CPU schedulers, not internal or hidden schedulers */
        AND status = 'VISIBLE OFFLINE'
        HAVING COUNT(*) > 0; /* Only if there are offline schedulers */
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
        
        /* Create temp table for IO stats */
        CREATE TABLE #io_stats
        (
            database_name sysname,
            database_id integer,
            file_name sysname,
            type_desc nvarchar(60),
            io_stall_read_ms bigint,
            num_of_reads bigint,
            avg_read_latency_ms decimal(18, 2),
            io_stall_write_ms bigint,
            num_of_writes bigint,
            avg_write_latency_ms decimal(18, 2),
            io_stall_ms bigint,
            total_io bigint,
            avg_io_latency_ms decimal(18, 2),
            size_mb decimal(18, 2),
            drive_letter nchar(1),
            physical_name nvarchar(260)
        );
        
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
        WHERE c.value <> c.value_in_use;
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
                DECLARE @has_tables BIT;
                SET @sql = N'SELECT @has_tables = CASE WHEN EXISTS(SELECT TOP 1 1 FROM ' + QUOTENAME(@current_database_name) + '.sys.tables) THEN 1 ELSE 0 END';
                EXEC sp_executesql @sql, N'@has_tables BIT OUTPUT', @has_tables = @has_tables OUTPUT;
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