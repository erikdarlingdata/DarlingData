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
        @version = N'1.0.4',
        @version_date = N'20250404';

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
        @autogrow_summary nvarchar(max),
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
        /* Format the output properly without XML PATH which causes spacing issues */
        @wait_summary nvarchar(1000) = N'',
        /* CPU scheduling variables */
        @signal_wait_time_ms bigint,
        @total_wait_time_ms bigint,
        @sos_scheduler_yield_ms bigint,
        @signal_wait_ratio decimal(10, 2),
        @sos_scheduler_yield_pct_of_uptime decimal(10, 2),
        /* I/O stalls variables */
        @io_stall_summary nvarchar(1000) = N'',
        /* Enhanced wait stats analysis variables */
        @wait_stats_uptime_hours decimal(18, 2),
        @signal_wait_pct decimal(18, 2),
        @resource_wait_pct decimal(18, 2),
        @cpu_pressure_threshold decimal(5, 2) = 20.0, /* Signal waits > 20% indicate CPU pressure */
        @io_pressure_threshold decimal(5, 2) = 40.0, /* IO waits > 40% indicate IO subsystem pressure */
        @lock_pressure_threshold decimal(5, 2) = 20.0, /* Lock waits > 20% indicate concurrency issues */
        @high_avg_wait_ms decimal(10, 2) = 100.0, /* High average wait threshold in ms */
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
    Azure SQL DB Resource Utilization Checks
    Only run these if we're in Azure SQL DB
    */
    IF @azure_sql_db = 1
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Running Azure SQL DB specific checks', 0, 1) WITH NOWAIT;
        END;

        /* Use dynamic SQL to check for Azure SQL DB resource limits being hit */
        BEGIN TRY
            SET @sql = N'
            SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
            
            /* 
            Check for DTU/vCore resource limits being hit 
            Uses sys.dm_db_resource_stats which keeps 1 hour of history at 15-second intervals
            */
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
                check_id = 8001,
                priority = 
                    CASE
                        WHEN MAX(avg_cpu_percent) > 95 THEN 20 /* Critical priority */
                        WHEN MAX(avg_cpu_percent) > 80 THEN 30 /* High priority */
                        ELSE 40 /* Medium priority */
                    END,
                category = N''Azure SQL DB'',
                finding = N''Resource Limits Approached or Exceeded'',
                details = 
                    N''In the last hour, CPU utilization peaked at '' +
                    CONVERT(nvarchar(10), MAX(avg_cpu_percent)) + N''%, '' +
                    N''Data IO at '' +
                    CONVERT(nvarchar(10), MAX(avg_data_io_percent)) + N''%, '' +
                    N''Log Write at '' +
                    CONVERT(nvarchar(10), MAX(avg_log_write_percent)) + N''%. '' +
                    CASE
                        WHEN MAX(avg_cpu_percent) > 95 OR MAX(avg_data_io_percent) > 95 OR MAX(avg_log_write_percent) > 95
                        THEN N''Resources are being throttled. Consider upgrading service tier or optimizing workload.''
                        WHEN MAX(avg_cpu_percent) > 80 OR MAX(avg_data_io_percent) > 80 OR MAX(avg_log_write_percent) > 80
                        THEN N''Resources are approaching limits. Monitor closely and plan for potential upgrade.''
                        ELSE N''Resource utilization is high but within acceptable limits.''
                    END,
                url = N''https://erikdarling.com/sp_PerfCheck#AzureResources''
            FROM sys.dm_db_resource_stats
            HAVING
                MAX(avg_cpu_percent) > 70 OR
                MAX(avg_data_io_percent) > 70 OR
                MAX(avg_log_write_percent) > 70;';
                
            IF @debug = 1
            BEGIN
                PRINT @sql;
            END;
            
            EXECUTE sys.sp_executesql @sql;
            
            /* Check for throttling events (queries waiting on resources) */
            SET @sql = N'
            SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
            
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
                check_id = 8002,
                priority = 30, /* High priority */
                category = N''Azure SQL DB'',
                finding = N''Resource Throttling Detected'',
                details =
                    N''Found '' + CONVERT(nvarchar(10), COUNT_BIG(*)) + 
                    N'' queries waiting on resource throttling: '' +
                    STUFF((
                        SELECT TOP 3 N'', '' + wait_type
                        FROM sys.dm_exec_requests AS r
                        WHERE wait_type LIKE ''RESOURCE_%''
                        AND wait_time_ms > 1000
                        GROUP BY wait_type
                        ORDER BY COUNT(*) DESC
                        FOR XML PATH(''''), TYPE).value(''.'', ''nvarchar(max)''), 1, 2, '''') +
                    N''. Resource governance is limiting performance.'',
                url = N''https://erikdarling.com/sp_PerfCheck#AzureThrottling''
            FROM sys.dm_exec_requests AS r
            WHERE wait_type LIKE ''RESOURCE_%''
            AND wait_time_ms > 1000
            HAVING
                COUNT_BIG(*) > 0;';
                
            IF @debug = 1
            BEGIN
                PRINT @sql;
            END;
            
            EXECUTE sys.sp_executesql @sql;
            
            /* Check for connection pooling issues */
            SET @sql = N'
            SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
            
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
                check_id = 8003,
                priority = 40, /* Medium priority */
                category = N''Azure SQL DB'',
                finding = N''Connection Pool Inefficiency'',
                details =
                    N''There are currently '' + 
                    CONVERT(nvarchar(10), COUNT_BIG(*)) + 
                    N'' active connections with '' +
                    CONVERT(nvarchar(10), 
                        (SELECT COUNT(*) FROM sys.dm_exec_connections 
                         WHERE connection_id NOT IN (SELECT connection_id FROM sys.dm_exec_sessions WHERE is_user_process = 1))
                    ) +
                    N'' system connections and '' +
                    CONVERT(nvarchar(10), 
                        (SELECT COUNT(*) FROM sys.dm_exec_connections 
                         WHERE connection_id IN (SELECT connection_id FROM sys.dm_exec_sessions WHERE is_user_process = 1))
                    ) +
                    N'' user connections. This may indicate connection pooling issues.'',
                url = N''https://erikdarling.com/sp_PerfCheck#AzureConnections''
            FROM sys.dm_exec_connections
            HAVING
                COUNT_BIG(*) > 100;';
                
            IF @debug = 1
            BEGIN
                PRINT @sql;
            END;
            
            EXECUTE sys.sp_executesql @sql;
            
            /* Check for storage space approaching limits */
            SET @sql = N'
            SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
            
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
                check_id = 8004,
                priority = 
                    CASE
                        WHEN (SUM(size) * 8.0 / 1024 / 1024) > (SELECT CAST(DATABASEPROPERTYEX(DB_NAME(), ''MaxSizeInBytes'') AS decimal(18,2)) / 1024 / 1024 / 1024 * 0.9)
                        THEN 20 /* Critical priority */
                        WHEN (SUM(size) * 8.0 / 1024 / 1024) > (SELECT CAST(DATABASEPROPERTYEX(DB_NAME(), ''MaxSizeInBytes'') AS decimal(18,2)) / 1024 / 1024 / 1024 * 0.8)
                        THEN 30 /* High priority */
                        ELSE 50 /* Medium priority */
                    END,
                category = N''Azure SQL DB'',
                finding = N''Database Approaching Storage Limit'',
                details =
                    N''Database is using '' +
                    CONVERT(nvarchar(20), CONVERT(decimal(18,2), (SUM(size) * 8.0 / 1024 / 1024))) +
                    N'' GB of '' +
                    CONVERT(nvarchar(20), CONVERT(decimal(18,2), (SELECT CAST(DATABASEPROPERTYEX(DB_NAME(), ''MaxSizeInBytes'') AS decimal(18,2)) / 1024 / 1024 / 1024))) +
                    N'' GB allowed ('' +
                    CONVERT(nvarchar(20), CONVERT(decimal(18,2), (SUM(size) * 8.0 / 1024 / 1024) / 
                        (SELECT CAST(DATABASEPROPERTYEX(DB_NAME(), ''MaxSizeInBytes'') AS decimal(18,2)) / 1024 / 1024 / 1024) * 100)) +
                    N''%). '' +
                    CASE
                        WHEN (SUM(size) * 8.0 / 1024 / 1024) > (SELECT CAST(DATABASEPROPERTYEX(DB_NAME(), ''MaxSizeInBytes'') AS decimal(18,2)) / 1024 / 1024 / 1024 * 0.9)
                        THEN N''Critical: Database is nearly at storage limit. Immediate action required.''
                        WHEN (SUM(size) * 8.0 / 1024 / 1024) > (SELECT CAST(DATABASEPROPERTYEX(DB_NAME(), ''MaxSizeInBytes'') AS decimal(18,2)) / 1024 / 1024 / 1024 * 0.8)
                        THEN N''Warning: Database is approaching storage limit. Plan for cleanup or tier upgrade.''
                        ELSE N''Monitor: Space usage is high but not critical.''
                    END,
                url = N''https://erikdarling.com/sp_PerfCheck#AzureStorage''
            FROM sys.database_files
            WHERE type_desc IN (''ROWS'', ''LOG'')
            HAVING
                (SUM(size) * 8.0 / 1024 / 1024) > (SELECT CAST(DATABASEPROPERTYEX(DB_NAME(), ''MaxSizeInBytes'') AS decimal(18,2)) / 1024 / 1024 / 1024 * 0.7);';
                
            IF @debug = 1
            BEGIN
                PRINT @sql;
            END;
            
            EXECUTE sys.sp_executesql @sql;
        END TRY
        BEGIN CATCH
            IF @debug = 1
            BEGIN
                SET @error_message = N'Error checking Azure SQL DB specific metrics: ' + ERROR_MESSAGE();
                RAISERROR(@error_message, 0, 1) WITH NOWAIT;
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
                9990,
                70, /* Medium priority */
                N'Errors',
                N'Error Checking Azure SQL DB Metrics',
                N'Unable to check Azure SQL DB specific metrics: ' + ERROR_MESSAGE()
            );
        END CATCH;
    END;
    
    /*
    Azure Managed Instance specific checks
    Only run these if we're in Azure Managed Instance
    */
    IF @azure_managed_instance = 1
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Running Azure Managed Instance specific checks', 0, 1) WITH NOWAIT;
        END;
        
        /* Use dynamic SQL to check for Azure MI-specific issues */
        BEGIN TRY
            /* Check for TempDB usage that might impact performance */
            SET @sql = N'
            SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
            
            WITH tempdb_space_usage AS
            (
                SELECT
                    SUM(CASE WHEN f.type_desc = ''ROWS'' THEN f.size ELSE 0 END) * 8.0 / 1024 AS data_size_mb,
                    SUM(CASE WHEN f.type_desc = ''LOG'' THEN f.size ELSE 0 END) * 8.0 / 1024 AS log_size_mb,
                    SUM(f.size) * 8.0 / 1024 AS total_size_mb,
                    SUM(f.max_size) * 8.0 / 1024 AS max_size_mb
                FROM tempdb.sys.database_files AS f
            )
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
                check_id = 8101,
                priority = 
                    CASE
                        WHEN (tsu.total_size_mb / NULLIF(tsu.max_size_mb, 0)) * 100 > 85 THEN 30 /* High priority */
                        WHEN (tsu.total_size_mb / NULLIF(tsu.max_size_mb, 0)) * 100 > 70 THEN 40 /* Medium-high priority */
                        ELSE 50 /* Medium priority */
                    END,
                category = N''Azure Managed Instance'',
                finding = N''High TempDB Usage'',
                details =
                    N''TempDB is using '' +
                    CONVERT(nvarchar(20), CONVERT(decimal(18,2), tsu.data_size_mb)) +
                    N'' MB data space, '' +
                    CONVERT(nvarchar(20), CONVERT(decimal(18,2), tsu.log_size_mb)) +
                    N'' MB log space ('' +
                    CONVERT(nvarchar(20), CONVERT(decimal(18,2), (tsu.total_size_mb / NULLIF(tsu.max_size_mb, 0)) * 100)) +
                    N''% of allowed size). '' +
                    CASE
                        WHEN (tsu.total_size_mb / NULLIF(tsu.max_size_mb, 0)) * 100 > 85
                        THEN N''TempDB is approaching size limits, which may lead to performance problems.''
                        ELSE N''High TempDB usage may impact performance on Azure MI.''
                    END,
                url = N''https://erikdarling.com/sp_PerfCheck#AzureMITempDB''
            FROM tempdb_space_usage AS tsu
            WHERE (tsu.total_size_mb / NULLIF(tsu.max_size_mb, 0)) * 100 > 60
            OR tsu.data_size_mb > 1024 * 10; /* More than 10 GB of TempDB usage */';
                
            IF @debug = 1
            BEGIN
                PRINT @sql;
            END;
            
            EXECUTE sys.sp_executesql @sql;
            
            /* Check for SQL Agent jobs that could be consuming resources */
            SET @sql = N'
            SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
            
            WITH long_running_jobs AS
            (
                SELECT
                    job_name = j.name,
                    average_duration_seconds = AVG(DATEDIFF(SECOND, h.run_requested_date, 
                        CASE WHEN h.run_status = 1 THEN h.run_date ELSE GETDATE() END)),
                    max_duration_seconds = MAX(DATEDIFF(SECOND, h.run_requested_date, 
                        CASE WHEN h.run_status = 1 THEN h.run_date ELSE GETDATE() END)),
                    failed_count = SUM(CASE WHEN h.run_status = 0 THEN 1 ELSE 0 END),
                    total_runs = COUNT(*)
                FROM msdb.dbo.sysjobs AS j
                JOIN msdb.dbo.sysjobhistory AS h
                    ON j.job_id = h.job_id
                WHERE h.step_id = 0 /* Job outcome */
                AND h.run_date >= DATEADD(DAY, -7, GETDATE()) /* Last 7 days */
                GROUP BY j.name
                HAVING 
                    /* More than 10 minutes average OR more than 30 minute max runtime */
                    AVG(DATEDIFF(SECOND, h.run_requested_date, 
                        CASE WHEN h.run_status = 1 THEN h.run_date ELSE GETDATE() END)) > 600
                    OR
                    MAX(DATEDIFF(SECOND, h.run_requested_date, 
                        CASE WHEN h.run_status = 1 THEN h.run_date ELSE GETDATE() END)) > 1800
            )
            INSERT INTO
                #results
            (
                check_id,
                priority,
                category,
                finding,
                object_name,
                details,
                url
            )
            SELECT
                check_id = 8102,
                priority = 
                    CASE
                        WHEN lrj.failed_count > 0 THEN 40 /* Medium-high priority if failures */
                        ELSE 50 /* Medium priority */
                    END,
                category = N''Azure Managed Instance'',
                finding = N''Long-Running Agent Job'',
                object_name = lrj.job_name,
                details =
                    N''Job runs for an average of '' +
                    CONVERT(nvarchar(20), CONVERT(decimal(18,2), lrj.average_duration_seconds / 60.0)) +
                    N'' minutes (max: '' +
                    CONVERT(nvarchar(20), CONVERT(decimal(18,2), lrj.max_duration_seconds / 60.0)) +
                    N'' minutes). '' +
                    CASE
                        WHEN lrj.failed_count > 0
                        THEN N''Has failed '' + CONVERT(nvarchar(10), lrj.failed_count) + N'' times out of '' +
                             CONVERT(nvarchar(10), lrj.total_runs) + N'' runs. ''
                        ELSE N''No failures in the last 7 days. ''
                    END +
                    N''Long-running jobs may consume valuable resources on Azure MI.'',
                url = N''https://erikdarling.com/sp_PerfCheck#AzureMIJobs''
            FROM long_running_jobs AS lrj;';
                
            IF @debug = 1
            BEGIN
                PRINT @sql;
            END;
            
            EXECUTE sys.sp_executesql @sql;
            
            /* Check for instance-level resource usage (works for both MI and SQL DB with different thresholds) */
            IF @azure_managed_instance = 1 OR @azure_sql_db = 1
            BEGIN
                SET @sql = N'
                SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
                
                WITH resource_usage AS
                (
                    SELECT
                        -- Memory metrics
                        physical_memory_kb = osi.physical_memory_kb,
                        committed_kb = 
                            (SELECT SUM(CONVERT(bigint, cntr_value))
                             FROM sys.dm_os_performance_counters
                             WHERE counter_name = ''SQL Server Memory Manager: Total Server Memory (KB)''),
                        committed_target_kb = 
                            (SELECT SUM(CONVERT(bigint, cntr_value))
                             FROM sys.dm_os_performance_counters
                             WHERE counter_name = ''SQL Server Memory Manager: Target Server Memory (KB)''),
                        available_physical_memory_kb = osi.available_physical_memory_kb,
                        system_memory_state_desc = osi.system_memory_state_desc,
                        -- CPU metrics 
                        average_cpu_percent = 
                            AVG(CONVERT(decimal(5,2), r.avg_cpu_percent))
                    FROM sys.dm_os_sys_info AS osi
                    CROSS JOIN
                    (
                        SELECT
                            AVG(avg_cpu_percent) AS avg_cpu_percent
                        FROM ' + 
                        CASE 
                            WHEN @azure_sql_db = 1 
                            THEN N'sys.dm_db_resource_stats' 
                            ELSE N'sys.server_resource_stats' 
                        END + N'
                        WHERE 
                            end_time >= DATEADD(HOUR, -1, GETDATE())
                    ) AS r
                    GROUP BY
                        osi.physical_memory_kb,
                        osi.available_physical_memory_kb,
                        osi.system_memory_state_desc
                )
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
                    check_id = 8103,
                    priority = 
                        CASE
                            WHEN ru.system_memory_state_desc = N''Available physical memory is low'' 
                                 OR (ru.physical_memory_kb - ru.available_physical_memory_kb) * 100.0 / ru.physical_memory_kb > 90
                                 OR ru.average_cpu_percent > 90
                            THEN 20 /* Critical priority */
                            
                            WHEN ru.system_memory_state_desc = N''Physical memory usage is steady''
                                 OR (ru.physical_memory_kb - ru.available_physical_memory_kb) * 100.0 / ru.physical_memory_kb > 80
                                 OR ru.average_cpu_percent > 80
                            THEN 30 /* High priority */
                            
                            ELSE 40 /* Medium-high priority */
                        END,
                    category = ' + 
                        CASE 
                            WHEN @azure_sql_db = 1 
                            THEN N'''Azure SQL DB''' 
                            ELSE N'''Azure Managed Instance''' 
                        END + N',
                    finding = N''High Resource Utilization'',
                    details =
                        N''Instance memory: '' +
                        CONVERT(nvarchar(20), CONVERT(decimal(18,2), ru.physical_memory_kb / 1024.0 / 1024.0)) +
                        N'' GB total, '' +
                        CONVERT(nvarchar(20), CONVERT(decimal(18,2), ru.available_physical_memory_kb / 1024.0 / 1024.0)) +
                        N'' GB available. Memory state: '' + ru.system_memory_state_desc +
                        N''. Average CPU utilization: '' +
                        CONVERT(nvarchar(10), CONVERT(decimal(5,2), ru.average_cpu_percent)) + N''%. '' +
                        CASE
                            WHEN ru.system_memory_state_desc = N''Available physical memory is low''
                                 OR (ru.physical_memory_kb - ru.available_physical_memory_kb) * 100.0 / ru.physical_memory_kb > 90
                                 OR ru.average_cpu_percent > 90
                            THEN N''CRITICAL: Instance is under extreme resource pressure!''
                            
                            WHEN ru.system_memory_state_desc = N''Physical memory usage is steady''
                                 OR (ru.physical_memory_kb - ru.available_physical_memory_kb) * 100.0 / ru.physical_memory_kb > 80
                                 OR ru.average_cpu_percent > 80
                            THEN N''WARNING: Instance is experiencing significant resource pressure.''
                            
                            ELSE N''Instance is using high resources but may not yet be experiencing performance issues.''
                        END,
                    url = ' + 
                        CASE 
                            WHEN @azure_sql_db = 1 
                            THEN N'''https://erikdarling.com/sp_PerfCheck#AzureDBResources''' 
                            ELSE N'''https://erikdarling.com/sp_PerfCheck#AzureMIResources''' 
                        END + N'
                FROM resource_usage AS ru
                WHERE 
                    ru.system_memory_state_desc IN (N''Available physical memory is low'', N''Physical memory usage is steady'')
                    OR (ru.physical_memory_kb - ru.available_physical_memory_kb) * 100.0 / ru.physical_memory_kb > 70 /* Memory usage > 70% */
                    OR ru.average_cpu_percent > 70; /* CPU usage > 70% */';
                    
                IF @debug = 1
                BEGIN
                    PRINT @sql;
                END;
                
                EXECUTE sys.sp_executesql @sql;
            END;
        END TRY
        BEGIN CATCH
            IF @debug = 1
            BEGIN
                SET @error_message = N'Error checking Azure MI specific metrics: ' + ERROR_MESSAGE();
                RAISERROR(@error_message, 0, 1) WITH NOWAIT;
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
                9991,
                70, /* Medium priority */
                N'Errors',
                N'Error Checking Azure MI Metrics',
                N'Unable to check Azure MI specific metrics: ' + ERROR_MESSAGE()
            );
        END CATCH;
    END;
    
    /*
    AWS RDS for SQL Server specific checks
    Only run these if we're on AWS RDS
    */
    IF @aws_rds = 1
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Running AWS RDS for SQL Server specific checks', 0, 1) WITH NOWAIT;
        END;
        
        /* Use dynamic SQL to check for AWS RDS-specific issues */
        BEGIN TRY
            /* Check for storage usage relative to allocated storage */
            SET @sql = N'
            SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
            
            WITH db_size AS
            (
                SELECT
                    total_size_mb = SUM(size) * 8.0 / 1024,
                    data_size_mb = SUM(CASE WHEN type_desc = ''ROWS'' THEN size ELSE 0 END) * 8.0 / 1024,
                    log_size_mb = SUM(CASE WHEN type_desc = ''LOG'' THEN size ELSE 0 END) * 8.0 / 1024
                FROM sys.master_files
            ),
            instance_info AS
            (
                SELECT
                    -- RDS does not expose allocated size directly via T-SQL
                    -- We can estimate from max_size of master database
                    estimated_allocated_storage_gb = 
                        (SELECT MAX(max_size) * 8.0 / 1024 / 1024
                         FROM sys.master_files 
                         WHERE database_id = 1 AND type_desc = ''ROWS'')
                FROM sys.databases
                WHERE database_id = 1
            )
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
                check_id = 8201,
                priority = 
                    CASE
                        WHEN (db.total_size_mb / 1024) > (i.estimated_allocated_storage_gb * 0.9) THEN 20 /* Critical priority */
                        WHEN (db.total_size_mb / 1024) > (i.estimated_allocated_storage_gb * 0.8) THEN 30 /* High priority */
                        ELSE 40 /* Medium-high priority */
                    END,
                category = N''AWS RDS SQL Server'',
                finding = N''High Storage Utilization'',
                details =
                    N''Instance is using approximately '' +
                    CONVERT(nvarchar(20), CONVERT(decimal(18,2), db.total_size_mb / 1024)) +
                    N'' GB of an estimated '' +
                    CONVERT(nvarchar(20), CONVERT(decimal(18,2), i.estimated_allocated_storage_gb)) +
                    N'' GB allocated storage ('' +
                    CONVERT(nvarchar(20), CONVERT(decimal(18,2), (db.total_size_mb / 1024) / i.estimated_allocated_storage_gb * 100)) +
                    N''%). '' +
                    CASE
                        WHEN (db.total_size_mb / 1024) > (i.estimated_allocated_storage_gb * 0.9)
                        THEN N''CRITICAL: Instance is approaching storage limits. Immediate action required.''
                        WHEN (db.total_size_mb / 1024) > (i.estimated_allocated_storage_gb * 0.8)
                        THEN N''WARNING: Instance is approaching storage limits. Plan for storage increase or cleanup.''
                        ELSE N''Instance has high storage utilization. Monitor growth and plan accordingly.''
                    END,
                url = N''https://erikdarling.com/sp_PerfCheck#AWSRDS''
            FROM db_size AS db
            CROSS JOIN instance_info AS i
            WHERE (db.total_size_mb / 1024) > (i.estimated_allocated_storage_gb * 0.7);
            ';
                
            IF @debug = 1
            BEGIN
                PRINT @sql;
            END;
            
            EXECUTE sys.sp_executesql @sql;
            
            /* Check for missing native backup features */
            SET @sql = N'
            SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
            
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
                8202,
                60, /* Informational priority */
                N''AWS RDS SQL Server'',
                N''Limited Native Backup Options'',
                N''AWS RDS for SQL Server uses RDS-specific backup procedures instead of native SQL Server commands. '' +
                N''To perform database backups, use the AWS RDS console, AWS CLI, or native BACKUP TO URL for S3. '' +
                N''BACKUP DATABASE and BACKUP LOG commands to local disk are not supported.'',
                N''https://erikdarling.com/sp_PerfCheck#AWSRDSBackup''
            );';
                
            IF @debug = 1
            BEGIN
                PRINT @sql;
            END;
            
            EXECUTE sys.sp_executesql @sql;
            
            /* Check for IOPS utilization - have to infer from wait stats since AWS doesn't expose directly */
            SET @sql = N'
            SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
            
            WITH io_waits AS
            (
                SELECT
                    io_wait_ms = 
                        SUM(CASE 
                            WHEN wait_type IN (''IO_COMPLETION'', ''WRITE_COMPLETION'', ''ASYNC_IO_COMPLETION'') THEN wait_time_ms
                            WHEN wait_type LIKE ''PAGEIOLATCH_%'' THEN wait_time_ms
                            ELSE 0 
                        END),
                    log_wait_ms = 
                        SUM(CASE 
                            WHEN wait_type IN (''WRITELOG'') THEN wait_time_ms
                            ELSE 0 
                        END),
                    total_wait_ms = SUM(wait_time_ms),
                    sample_ms = DATEDIFF(ms, MIN(wait_time_ms), MAX(wait_time_ms))
                FROM sys.dm_os_wait_stats
            )
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
                check_id = 8203,
                priority = 
                    CASE
                        WHEN (iw.io_wait_ms * 100.0 / NULLIF(iw.total_wait_ms, 0)) > 60 
                             OR (iw.log_wait_ms * 100.0 / NULLIF(iw.total_wait_ms, 0)) > 30
                        THEN 30 /* High priority */
                        WHEN (iw.io_wait_ms * 100.0 / NULLIF(iw.total_wait_ms, 0)) > 40 
                             OR (iw.log_wait_ms * 100.0 / NULLIF(iw.total_wait_ms, 0)) > 20
                        THEN 40 /* Medium-high priority */
                        ELSE 50 /* Medium priority */
                    END,
                category = N''AWS RDS SQL Server'',
                finding = N''High I/O Wait Times'',
                details =
                    N''Instance is experiencing significant I/O wait times: '' +
                    CONVERT(nvarchar(20), CONVERT(decimal(18,2), iw.io_wait_ms * 100.0 / NULLIF(iw.total_wait_ms, 0))) +
                    N''% of all waits are I/O related, with log waits accounting for '' +
                    CONVERT(nvarchar(20), CONVERT(decimal(18,2), iw.log_wait_ms * 100.0 / NULLIF(iw.total_wait_ms, 0))) +
                    N''%. '' +
                    CASE
                        WHEN (iw.io_wait_ms * 100.0 / NULLIF(iw.total_wait_ms, 0)) > 60 
                             OR (iw.log_wait_ms * 100.0 / NULLIF(iw.total_wait_ms, 0)) > 30
                        THEN N''This indicates that your RDS instance may be IOPS-constrained. Consider increasing provisioned IOPS or upgrading storage type.''
                        ELSE N''Monitor these values to ensure they don''t increase further, which could indicate IOPS constraints on your RDS instance.''
                    END,
                url = N''https://erikdarling.com/sp_PerfCheck#AWSRDSIOPS''
            FROM io_waits AS iw
            WHERE (iw.io_wait_ms * 100.0 / NULLIF(iw.total_wait_ms, 0)) > 40 
               OR (iw.log_wait_ms * 100.0 / NULLIF(iw.total_wait_ms, 0)) > 20;';
                
            IF @debug = 1
            BEGIN
                PRINT @sql;
            END;
            
            EXECUTE sys.sp_executesql @sql;
            
            /* Check for multi-AZ configuration */
            SET @sql = N'
            SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
            
            /* RDS doesn''t expose multi-AZ status directly via T-SQL, but we can look for indicators */
            WITH mirroring_indicators AS
            (
                SELECT 
                    mirroring_enabled = 
                        CASE 
                            WHEN EXISTS (
                                SELECT 1 
                                FROM sys.database_mirroring 
                                WHERE mirroring_guid IS NOT NULL
                                AND mirroring_role = 1 /* Principal */
                            )
                            THEN 1
                            ELSE 0
                        END
            )
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
                check_id = 8204,
                priority = 50, /* Medium priority */
                category = N''AWS RDS SQL Server'',
                finding = N''Possible Multi-AZ Configuration'',
                details =
                    CASE 
                        WHEN mi.mirroring_enabled = 1
                        THEN N''Instance appears to be using database mirroring for Multi-AZ deployment, which is good for availability but may impact performance.''
                        ELSE N''Instance may not be using Multi-AZ deployment. This reduces availability but may offer better performance.''
                    END +
                    N'' On AWS RDS, Multi-AZ uses database mirroring to maintain a hot standby.'',
                url = N''https://erikdarling.com/sp_PerfCheck#AWSRDSMultiAZ''
            FROM mirroring_indicators AS mi;';
                
            IF @debug = 1
            BEGIN
                PRINT @sql;
            END;
            
            EXECUTE sys.sp_executesql @sql;
            
            /* Check for potentially misconfigured instance class */
            SET @sql = N'
            SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
            
            WITH perf_metrics AS
            (
                SELECT
                    -- CPU metrics
                    cpu_count = osi.cpu_count,
                    -- Memory metrics
                    memory_gb = CAST(osi.physical_memory_kb / 1024.0 / 1024.0 AS decimal(18,2)),
                    -- Database size metrics
                    total_db_size_gb = (SELECT SUM(size) * 8.0 / 1024 / 1024 FROM sys.master_files),
                    -- Performance metrics
                    page_life_expectancy = (
                        SELECT cntr_value
                        FROM sys.dm_os_performance_counters
                        WHERE counter_name = ''Page life expectancy''
                        AND object_name LIKE ''%:Buffer Manager%''
                    ),
                    -- Buffer pool metrics
                    buffer_pool_size_gb = (
                        SELECT CAST(cntr_value / 1024.0 / 1024.0 / 128.0 AS decimal(18,2))
                        FROM sys.dm_os_performance_counters
                        WHERE counter_name = ''Database pages''
                        AND object_name LIKE ''%:Buffer Manager%''
                    ),
                    -- Signal waits - indication of CPU pressure
                    signal_wait_pct = (
                        SELECT CAST(100.0 * SUM(signal_wait_time_ms) / SUM(wait_time_ms) AS decimal(18,2))
                        FROM sys.dm_os_wait_stats
                        WHERE wait_time_ms > 0
                    ),
                    -- Compile:Execute Ratio
                    compile_ratio = (
                        SELECT CAST((1.0 * c1.cntr_value / NULLIF(c2.cntr_value, 0)) * 100 AS decimal(18,2))
                        FROM sys.dm_os_performance_counters c1
                        CROSS JOIN sys.dm_os_performance_counters c2
                        WHERE c1.counter_name = ''SQL Compilations/sec''
                        AND c2.counter_name = ''Batch Requests/sec''
                        AND c1.object_name LIKE ''%:SQL Statistics%''
                        AND c2.object_name LIKE ''%:SQL Statistics%''
                    )
                FROM sys.dm_os_sys_info AS osi
            )
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
                check_id = 8205,
                priority = 
                    CASE
                        WHEN (pm.page_life_expectancy < 300 OR pm.signal_wait_pct > 25) THEN 30 /* High priority */
                        WHEN (pm.buffer_pool_size_gb / NULLIF(pm.total_db_size_gb, 0) < 0.2
                              OR pm.page_life_expectancy < 900
                              OR pm.signal_wait_pct > 15) THEN 40 /* Medium-high priority */
                        ELSE 50 /* Medium priority */
                    END,
                category = N''AWS RDS SQL Server'',
                finding = N''Potential Instance Class Mismatch'',
                details =
                    N''RDS instance has '' +
                    CONVERT(nvarchar(10), pm.cpu_count) + N'' vCPUs, '' +
                    CONVERT(nvarchar(20), pm.memory_gb) + N'' GB memory, and '' +
                    CONVERT(nvarchar(20), pm.buffer_pool_size_gb) + N'' GB buffer pool for '' +
                    CONVERT(nvarchar(20), pm.total_db_size_gb) + N'' GB of databases. '' +
                    CASE
                        WHEN pm.buffer_pool_size_gb / NULLIF(pm.total_db_size_gb, 0) < 0.2
                        THEN N''Buffer pool is less than 20% of total database size. ''
                        ELSE N''''
                    END +
                    CASE
                        WHEN pm.page_life_expectancy < 300
                        THEN N''Page life expectancy is critically low at '' + CONVERT(nvarchar(20), pm.page_life_expectancy) + N'' seconds. ''
                        WHEN pm.page_life_expectancy < 900
                        THEN N''Page life expectancy is low at '' + CONVERT(nvarchar(20), pm.page_life_expectancy) + N'' seconds. ''
                        ELSE N''''
                    END +
                    CASE
                        WHEN pm.signal_wait_pct > 25
                        THEN N''CPU pressure is high with signal waits at '' + CONVERT(nvarchar(20), pm.signal_wait_pct) + N''%. ''
                        WHEN pm.signal_wait_pct > 15
                        THEN N''CPU pressure is moderate with signal waits at '' + CONVERT(nvarchar(20), pm.signal_wait_pct) + N''%. ''
                        ELSE N''''
                    END +
                    CASE
                        WHEN pm.compile_ratio > 15
                        THEN N''High compilation ratio of '' + CONVERT(nvarchar(20), pm.compile_ratio) + N''% indicates frequent recompilations. ''
                        ELSE N''''
                    END +
                    N''Consider whether your instance class provides adequate resources for your workload.'',
                url = N''https://erikdarling.com/sp_PerfCheck#AWSRDSInstance''
            FROM perf_metrics AS pm
            WHERE pm.buffer_pool_size_gb / NULLIF(pm.total_db_size_gb, 0) < 0.2
               OR pm.page_life_expectancy < 900
               OR pm.signal_wait_pct > 15
               OR pm.compile_ratio > 15;';
                
            IF @debug = 1
            BEGIN
                PRINT @sql;
            END;
            
            EXECUTE sys.sp_executesql @sql;
            
        END TRY
        BEGIN CATCH
            IF @debug = 1
            BEGIN
                SET @error_message = N'Error checking AWS RDS specific metrics: ' + ERROR_MESSAGE();
                RAISERROR(@error_message, 0, 1) WITH NOWAIT;
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
                9992,
                70, /* Medium priority */
                N'Errors',
                N'Error Checking AWS RDS Metrics',
                N'Unable to check AWS RDS specific metrics: ' + ERROR_MESSAGE()
            );
        END CATCH;
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

    /* Create temp table for wait stats analysis */
    CREATE TABLE
        #wait_stats
    (
        wait_type nvarchar(60) NOT NULL,
        waiting_tasks_count bigint NOT NULL,
        wait_time_ms bigint NOT NULL,
        max_wait_time_ms bigint NOT NULL,
        signal_wait_time_ms bigint NOT NULL,
        wait_time_minutes AS CAST(wait_time_ms / 1000.0 / 60.0 AS decimal(18, 2)),
        wait_time_hours AS CAST(wait_time_ms / 1000.0 / 60.0 / 60.0 AS decimal(18, 2)),
        wait_pct decimal(18, 2) NOT NULL,
        signal_wait_pct decimal(18, 2) NOT NULL,
        resource_wait_ms AS wait_time_ms - signal_wait_time_ms,
        avg_wait_ms AS CASE WHEN waiting_tasks_count = 0 THEN 0 ELSE wait_time_ms / waiting_tasks_count END,
        category nvarchar(30) NOT NULL
    );
    
    /* Create temp table for wait category summary */
    CREATE TABLE
        #wait_summary
    (
        category nvarchar(30) NOT NULL,
        total_waits bigint NOT NULL,
        total_wait_time_ms bigint NOT NULL,
        wait_pct decimal(18, 2) NOT NULL,
        avg_wait_ms decimal(18, 2) NOT NULL,
        signal_wait_pct decimal(18, 2) NOT NULL
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
        #server_info 
        (info_type, value)
    VALUES
        (N'sp_PerfCheck', N'Brought to you by Darling Data');

    INSERT INTO
        #server_info 
        (info_type, value)
    VALUES
        (N'https://code.erikdarling.com', N'https://erikdarling.com');

    INSERT INTO
        #server_info 
        (info_type, value)
    VALUES
        (
            N'Version', 
            @version + 
            N' (' + 
            CONVERT(varchar(10), @version_date, 101) + 
            N')'
        );

    INSERT INTO
        #server_info 
        (info_type, value)
    VALUES
        (N'Server Name', CONVERT(sysname, SERVERPROPERTY(N'ServerName')));

    INSERT INTO
        #server_info 
        (info_type, value)
    VALUES
        (
            N'SQL Server Version',
            CONVERT(sysname, SERVERPROPERTY(N'ProductVersion')) +
            N' (' +
            CONVERT(sysname, SERVERPROPERTY(N'ProductLevel')) +
            N')'
        );

    INSERT INTO
        #server_info 
        (info_type, value)
    VALUES
        (N'SQL Server Edition', CONVERT(sysname, SERVERPROPERTY(N'Edition')));

    /* Environment information - Already detected earlier */
    INSERT INTO
        #server_info 
        (info_type, value)
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

    /* Uptime information - works on all platforms */
    INSERT INTO
        #server_info 
        (info_type, value)
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

    /* CPU information - works on all platforms */
    INSERT INTO
        #server_info 
        (info_type, value)
    SELECT
        N'CPU',
        CONVERT(nvarchar(10), osi.cpu_count) + 
        N' logical processors, ' +
        CONVERT(nvarchar(10), osi.hyperthread_ratio) + 
        N' physical cores, ' +
        CONVERT(nvarchar(10), ISNULL(osi.numa_node_count, 1)) + 
        N' NUMA node(s)'
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
            category = N'CPU Configuration',
            finding = N'Offline CPU Schedulers',
            details =
                CONVERT(nvarchar(10), COUNT_BIG(*)) +
                N' CPU scheduler(s) are offline out of ' +
                CONVERT(nvarchar(10), (SELECT cpu_count FROM sys.dm_os_sys_info)) +
                N' logical processors. This reduces available processing power. ' +
                N'Check affinity mask configuration, licensing, or VM CPU cores/sockets',
            url = N'https://erikdarling.com/sp_PerfCheck#OfflineCPU'
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

    /* Check for memory grant timeouts */
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
        finding = N'Memory Grant Timeouts Detected',
        details =
            N'dm_exec_query_resource_semaphores has ' +
            CONVERT(nvarchar(10), MAX(ders.timeout_error_count)) +
            N' grants timeouts. ' +
            N'Queries are waiting for memory for a long time and giving up.',
        url = N'https://erikdarling.com/sp_PerfCheck#MemoryStarved'
    FROM sys.dm_exec_query_resource_semaphores AS ders
    WHERE ders.timeout_error_count > 0
    HAVING
        MAX(ders.timeout_error_count) > 0; /* Only if there are actually timeout errors */

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
    END;

    /* Check if Instant File Initialization is enabled (on-prem only) */
    IF  @azure_sql_db = 0
    AND @azure_managed_instance = 0
    AND @aws_rds = 0
    AND @has_view_server_state = 1
    BEGIN
        INSERT INTO
            #server_info 
            (info_type, value)
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
                (info_type, value)
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
                (info_type, value)
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
                (info_type, value)
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
        (info_type, value)
    SELECT
        N'Memory',
        N'Total: ' +
        CONVERT(nvarchar(20), CONVERT(decimal(10, 2), osi.physical_memory_kb / 1024.0 / 1024.0)) +
        N' GB, ' +
        N'Target: ' +
        CONVERT(nvarchar(20), CONVERT(decimal(10, 2), osi.committed_target_kb / 1024.0 / 1024.0)) +
        N' GB' +
        N', ' +
        osi.sql_memory_model_desc +
        N' enabled'
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
                NULL, 
                NULL, 
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
                (event_class, event_name, category_name)
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
                N'https://erikdarling.com/sp_perfcheck/#DisruptiveDBCC'
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
                        SELECT TOP (10)
                            N', ' +
                            CONVERT(nvarchar(50), COUNT_BIG(*)) +
                            N' slow ' +
                            CASE
                                WHEN te.event_class = 92
                                THEN N'data file'
                                WHEN te.event_class = 93
                                THEN N'log file'
                            END +
                            N' autogrows' +
                            N' (avg ' +
                            CONVERT(nvarchar(20), AVG(te.duration_ms) / 1000.0) +
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
                    (info_type, value)
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
                    THEN DATEDIFF(SECOND, osi.sqlserver_start_time, SYSDATETIME()) * 1000
                    ELSE DATEDIFF(MILLISECOND, osi.sqlserver_start_time, SYSDATETIME())
                END
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
            percentage = 
                CONVERT(decimal(5,2), dows.wait_time_ms * 100.0 / @total_waits),
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

        INSERT INTO
            #wait_summary 
            (category, pct_of_uptime)
        SELECT TOP (5)
            ws.category,
            pct_of_uptime = 
                SUM(ws.wait_time_percent_of_uptime)
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
                #server_info 
                (info_type, value)
            VALUES
                (N'Wait Stats Summary', N'See Wait Statistics section in results for details.');

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
            SELECT TOP (10)
                6000,
                priority =
                    CASE
                        WHEN ws.pct_of_uptime > 100
                        THEN 40 /* Medium-high priority */
                        WHEN ws.pct_of_uptime > 50
                        THEN 50 /* Medium priority */
                        ELSE 60 /* Lower priority */
                    END,
                category = N'Wait Statistics Summary',
                finding = N'Wait Category: ' + ws.category,
                details =
                    N'This category represents ' +
                    CONVERT(nvarchar(10), CONVERT(decimal(10, 2), ws.pct_of_uptime)) +
                    N'% of server uptime. ' +
                    CASE
                        WHEN ws.category = N'Query Execution'
                        THEN N'This includes various query processing waits and can indicate poorly optimized queries or procedure cache issues.'
                        WHEN ws.category = N'Parallelism'
                        THEN N'This indicates time spent coordinating parallel query execution. Consider reviewing MAXDOP settings.'
                        WHEN ws.category = N'CPU'
                        THEN N'This indicates CPU pressure. Server may benefit from more CPU resources or query optimization.'
                        WHEN ws.category = N'Memory'
                        THEN N'This indicates memory pressure. Consider increasing server memory or optimizing memory-intensive queries.'
                        WHEN ws.category = N'I/O'
                        THEN N'This indicates storage performance issues. Check for slow disks or I/O-intensive queries.'
                        WHEN ws.category = N'TempDB Contention'
                        THEN N'This indicates contention in TempDB. Consider adding more TempDB files or optimizing queries that use TempDB.'
                        WHEN ws.category = N'Transaction Log'
                        THEN N'This indicates log write pressure. Check for long-running transactions or log file performance issues.'
                        WHEN ws.category = N'Locking'
                        THEN N'This indicates contention from locks. Look for blocking chains or query isolation level issues.'
                        WHEN ws.category = N'Network'
                        THEN N'This indicates network bottlenecks or slow client applications not consuming results quickly.'
                        WHEN ws.category = N'Azure SQL Throttling'
                        THEN N'This indicates resource limits imposed by Azure SQL DB. Consider upgrading to a higher service tier.'
                        ELSE N'This category may require further investigation.'
                    END,
                url = N'https://erikdarling.com/sp_PerfCheck#WaitStats'
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
            @signal_wait_time_ms = 
                SUM(osw.signal_wait_time_ms),
            @total_wait_time_ms = 
                SUM(osw.wait_time_ms),
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
                (info_type, value)
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
                    (info_type, value)
                VALUES
                (
                    N'SOS_SCHEDULER_YIELD',
                    CONVERT(nvarchar(10), CONVERT(decimal(10, 2), @sos_scheduler_yield_pct_of_uptime)) +
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
            SET @stolen_memory_pct =
                    (@stolen_memory_gb / (@buffer_pool_size_gb + @stolen_memory_gb)) * 100.0;

            /* Add buffer pool info to server_info */
            INSERT INTO
                #server_info 
                (info_type, value)
            VALUES
            (
                N'Buffer Pool Size',
                CONVERT(nvarchar(20), @buffer_pool_size_gb) +
                N' GB'
            );

            INSERT INTO
                #server_info 
                (info_type, value)
            VALUES
            (
                N'Stolen Memory',
                CONVERT(nvarchar(20), @stolen_memory_gb) +
                N' GB (' +
                CONVERT(nvarchar(10), CONVERT(decimal(10, 1), @stolen_memory_pct)) +
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
                    SUM(domc.pages_kb) / 1024.0 / 1024.0 > 1.0 /* Only show clerks using more than 1 GB */
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
            total_size_mb = CONVERT(decimal(18, 2), SUM(mf.size) * 8.0 / 1024.0)
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
        IF  @io_stall_summary IS NOT NULL
        AND LEN(@io_stall_summary) > 0
        BEGIN
            INSERT INTO
                #server_info 
                (info_type, value)
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
                CONVERT(nvarchar(20), CONVERT(decimal(10, 2), io.read_io_mb)) +
                N' MB, Total write: ' +
                CONVERT(nvarchar(20), CONVERT(decimal(10, 2), io.write_io_mb)) +
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
                (info_type, value)
            EXECUTE sys.sp_executesql 
                @db_size_sql;
        END;
    END TRY
    BEGIN CATCH
        /* If we can't access the files due to permissions */
        INSERT INTO
            #server_info 
            (info_type, value)
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
            @min_server_memory = CONVERT(bigint, c1.value_in_use),
            @max_server_memory = CONVERT(bigint, c2.value_in_use)
        FROM sys.configurations AS c1
        CROSS JOIN sys.configurations AS c2
        WHERE c1.name = N'min server memory (MB)'
        AND   c2.name = N'max server memory (MB)';

        /* Get physical memory for comparison */
        SELECT
            @physical_memory_gb =
                CONVERT(decimal(10, 2), osi.physical_memory_kb / 1024.0 / 1024.0)
        FROM sys.dm_os_sys_info AS osi;

        /* Add min/max server memory info */
        INSERT INTO
            #server_info 
            (info_type, value)
        VALUES
            (N'Min Server Memory', CONVERT(nvarchar(20), @min_server_memory) + N' MB');

        INSERT INTO
            #server_info 
            (info_type, value)
        VALUES
            (N'Max Server Memory', CONVERT(nvarchar(20), @max_server_memory) + N' MB');

        /* Collect MAXDOP and CTFP settings */
        SELECT
            @max_dop = CONVERT(integer, c1.value_in_use),
            @cost_threshold = CONVERT(integer, c2.value_in_use)
        FROM sys.configurations AS c1
        CROSS JOIN sys.configurations AS c2
        WHERE c1.name = N'max degree of parallelism'
        AND   c2.name = N'cost threshold for parallelism';

        INSERT INTO
            #server_info 
            (info_type, value)
        VALUES
            (N'MAXDOP', CONVERT(nvarchar(10), @max_dop));

        INSERT INTO
            #server_info 
            (info_type, value)
        VALUES
            (N'Cost Threshold for Parallelism', CONVERT(nvarchar(10), @cost_threshold));

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
                N'Unable to collect TempDB file information: ' + ERROR_MESSAGE()
            );
        END CATCH;

        /* Get file counts and size range */
        SELECT
            @tempdb_data_file_count = 
                SUM(CASE WHEN tf.type_desc = N'ROWS' THEN 1 ELSE 0 END),
            @tempdb_log_file_count = 
                SUM(CASE WHEN tf.type_desc = N'LOG' THEN 1 ELSE 0 END),
            @min_data_file_size = 
                MIN(CASE WHEN tf.type_desc = N'ROWS' THEN tf.size_mb / 1024 ELSE NULL END),
            @max_data_file_size = 
                MAX(CASE WHEN tf.type_desc = N'ROWS' THEN tf.size_mb / 1024 ELSE NULL END),
            @has_percent_growth = 
                MAX(CASE WHEN tf.type_desc = N'ROWS' AND tf.is_percent_growth = 1 THEN 1 ELSE 0 END),
            @has_fixed_growth = 
                MAX(CASE WHEN tf.type_desc = N'ROWS' AND tf.is_percent_growth = 0 THEN 1 ELSE 0 END)
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
                N'TempDB Configuration',
                N'Single TempDB Data File',
                N'TempDB has only one data file. Multiple files can reduce allocation page contention. ' +
                N'Recommendation: Use multiple files (equal to number of logical processors up to 8).',
                N'https://erikdarling.com/sp_PerfCheck#TempDB'
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
                N'https://erikdarling.com/sp_PerfCheck#TempDB'
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
                N'https://erikdarling.com/sp_PerfCheck#TempDB'
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
                N'https://erikdarling.com/sp_PerfCheck#TempDB'
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
                N'https://erikdarling.com/sp_PerfCheck#TempDB'
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
                N'https://erikdarling.com/sp_perfcheck/#MinMaxMemory'
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
                N'https://erikdarling.com/sp_perfcheck/#MinMaxMemory'
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
                N'https://erikdarling.com/sp_perfcheck/#MAXDOP'
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
                N'https://erikdarling.com/sp_perfcheck/#CostThreshold'
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
                N'https://erikdarling.com/sp_perfcheck/#PriorityBoost'
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
                N'https://erikdarling.com/sp_perfcheck/#LightweightPooling'
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
                    THEN N'Auto create statistics is disabled. This can lead to suboptimal query plans for columns without statistics.'
                    WHEN d.is_auto_update_stats_on = 0
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
        AND   d.is_query_store_on = 0;

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
                PRINT REPLICATE('=', 128);
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
                    ''%). This can lead to increasingly larger growth events as the file grows,
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
                    CONVERT(nvarchar(20), CONVERT(decimal(18, 2), mf.growth * 8.0 / 1024 / 1024)) +
                    '' GB. Very large growth increments can lead to excessive space allocation. '' +
                    CASE
                        WHEN mf.type_desc = N''ROWS'' THEN N''Even with instant file initialization, consider using smaller increments for more controlled growth.''
                        WHEN mf.type_desc = N''LOG'' THEN N''This can cause significant stalls as log files must be zeroed out during growth operations.''
                    END,
                url = N''https://erikdarling.com/sp_PerfCheck#LargeGrowth''
            FROM ' + QUOTENAME(@current_database_name) + N'.sys.database_files AS mf
            WHERE mf.is_percent_growth = 0
            AND   mf.growth * 8.0 / 1024 / 1024 > 10; /* Growth > 10GB */';

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
        (info_type, value)
    VALUES
        (N'Run Date', CONVERT(varchar(25), @start_time, 121));

    /*
    Enhanced Wait Statistics Analysis
    */
    IF @debug = 1
    BEGIN
        RAISERROR('Analyzing wait statistics patterns', 0, 1) WITH NOWAIT;
    END;
    
    /* Get server uptime in milliseconds for wait stats analysis */
    SELECT
        @uptime_ms = 
            DATEDIFF(MILLISECOND, osi.sqlserver_start_time, GETDATE())
    FROM sys.dm_os_sys_info AS osi;
    
    /* Convert to hours for human-readable output */
    SET @wait_stats_uptime_hours = @uptime_ms / 1000.0 / 60.0 / 60.0;
    
    /* Populate wait stats table with categorized data from sys.dm_os_wait_stats */
    WITH categorized_waits AS
    (
        SELECT
            wait_type = ws.wait_type,
            waiting_tasks_count = ws.waiting_tasks_count,
            wait_time_ms = ws.wait_time_ms,
            max_wait_time_ms = ws.max_wait_time_ms,
            signal_wait_time_ms = ws.signal_wait_time_ms,
            wait_pct = 
                CONVERT(decimal(18, 2), 
                    100.0 * ws.wait_time_ms / NULLIF(SUM(ws.wait_time_ms) OVER(), 0)),
            signal_wait_pct = 
                CONVERT(decimal(18, 2), 
                    100.0 * ws.signal_wait_time_ms / NULLIF(ws.wait_time_ms, 0)),
            category = 
                CASE
                    /* CPU waits */
                    WHEN ws.wait_type IN ('SOS_SCHEDULER_YIELD', 'THREADPOOL', 'CPU_USAGE_EXCEEDED') OR 
                         ws.wait_type LIKE 'CX%' THEN 'CPU'
                         
                    /* Lock waits */
                    WHEN ws.wait_type IN ('LCK_M_%', 'LOCK_MANAGER', 'DEADLOCK_ENUM_SEARCH',
                         'ASYNC_NETWORK_IO', 'OLEDB', 'SQLSORT_SORTMUTEX') OR 
                         ws.wait_type LIKE 'LCK[_]%' OR
                         ws.wait_type LIKE 'HADR_SYNC_COMMIT' THEN 'Lock'
                         
                    /* I/O waits */
                    WHEN ws.wait_type IN ('ASYNC_IO_COMPLETION', 'IO_COMPLETION',
                         'WRITE_COMPLETION', 'IO_QUEUE_LIMIT', 'LOGMGR', 'CHECKPOINT_QUEUE',
                         'CHKPT', 'WRITELOG') OR
                         ws.wait_type LIKE 'PAGEIOLATCH_%' OR 
                         ws.wait_type LIKE 'PAGIOLATCH_%' OR
                         ws.wait_type LIKE 'IO_RETRY%' THEN 'I/O'
                         
                    /* Memory waits */ 
                    WHEN ws.wait_type IN ('RESOURCE_SEMAPHORE', 'CMEMTHREAD', 'RESOURCE_SEMAPHORE_QUERY_COMPILE',
                         'RESOURCE_QUEUE', 'DBMIRROR_DBM_MUTEX', 'DBMIRROR_EVENTS_QUEUE',
                         'XACT_OWNING_TRANSACTION', 'XACT_STATE_MUTEX') OR
                         ws.wait_type LIKE 'RESOURCE_SEMAPHORE%' OR
                         ws.wait_type LIKE 'PAGELATCH%' OR 
                         ws.wait_type LIKE 'ACCESS_METHODS%' OR
                         ws.wait_type LIKE 'MEMORY_ALLOCATION%' THEN 'Memory'
                         
                    /* Network waits */
                    WHEN ws.wait_type IN ('NETWORK_IO', 'EXTERNAL_SCRIPT_NETWORK_IOF') OR
                         ws.wait_type LIKE 'DTC_%' OR
                         ws.wait_type LIKE 'SNI_HTTP%' OR
                         ws.wait_type LIKE 'NETWORK_%' THEN 'Network'
                         
                    /* CLR waits */
                    WHEN ws.wait_type LIKE 'CLR_%' THEN 'CLR'
                    
                    /* SQLOS waits */
                    WHEN ws.wait_type LIKE 'SOSHOST_%' OR 
                         ws.wait_type LIKE 'VDI_CLIENT_%' OR
                         ws.wait_type LIKE 'BACKUP_%' OR 
                         ws.wait_type LIKE 'BACKUPTHREAD%' OR
                         ws.wait_type LIKE 'DISKIO_%' THEN 'SQLOS'
                         
                    /* Idle waits - typically ignore these */
                    WHEN ws.wait_type IN ('BROKER_TASK_STOP', 'BROKER_EVENTHANDLER', 'BROKER_TRANSMITTER',
                         'BROKER_TO_FLUSH', 'CHECKPOINT_QUEUE', 'CHECPOINT', 'CLOSE_ITERATOR',
                         'DREAMLINER_PROFILER_FLUSH', 'FSAGENT', 'FT_IFTS_SCHEDULER_IDLE_WAIT',
                         'FT_IFTSHC_MUTEX', 'HADR_FILESTREAM_IOMGR_IOCOMPLETION',
                         'IMPPROV_IOWAIT', 'INTERNAL_PERIODIC_MAINTENANCE', 'LAZYWRITER_SLEEP',
                         'LOGMGR_QUEUE', 'ONDEMAND_TASK_QUEUE', 'REQUEST_FOR_DEADLOCK_SEARCH',
                         'RESOURCE_QUEUE', 'SERVER_IDLE_CHECK', 'SLEEP_BPOOL_FLUSH',
                         'SLEEP_DBSTARTUP', 'SLEEP_DCOMSTARTUP', 'SLEEP_MSDBSTARTUP',
                         'SLEEP_SYSTEMTASK', 'SLEEP_TASK', 'SLEEP_TEMPDBSTARTUP',
                         'SNI_HTTP_ACCEPT', 'SQLTRACE_BUFFER_FLUSH', 'SQLTRACE_INCREMENTAL_FLUSH_SLEEP',
                         'SQLTRACE_WAIT_ENTRIES', 'WAIT_FOR_RESULTS', 'WAITFOR',
                         'WAITFOR_TASKSHUTDOWN', 'WAIT_XTP_OFFLINE_CKPT_NEW_LOG', 'WAITFOR_CKPT_NEW_LOG',
                         'XE_DISPATCHER_WAIT', 'XE_LIVE_TARGET_TVF', 'XE_TIMER_EVENT', 'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP',
                         'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP') OR
                         ws.wait_type LIKE 'WAIT_FOR%' OR
                         ws.wait_type LIKE 'WAITFOR%' OR 
                         ws.wait_type LIKE 'PREEMPTIVE%' OR
                         ws.wait_type LIKE 'BROKER%' OR
                         ws.wait_type LIKE 'SLEEP%' OR
                         ws.wait_type LIKE 'IDLE%' THEN 'Idle'
                         
                    ELSE 'Other'
                END
        FROM sys.dm_os_wait_stats AS ws
        WHERE ws.wait_type NOT IN (
            'RESOURCE_QUEUE', 'SQLTRACE_INCREMENTAL_FLUSH_SLEEP', 'LOGMGR_QUEUE', 
            'CHECKPOINT_QUEUE', 'REQUEST_FOR_DEADLOCK_SEARCH', 'XE_TIMER_EVENT',
            'BROKER_TASK_STOP', 'CLR_AUTO_EVENT', 'CLR_MANUAL_EVENT', 'LAZYWRITER_SLEEP',
            'SLEEP_TASK', 'SLEEP_SYSTEMTASK', 'SQLTRACE_BUFFER_FLUSH', 'WAITFOR_TASKSHUTDOWN',
            'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP', 'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP',
            'RBPEX_PAUSED_WAIT', 'XE_LIVE_TARGET_TVF', 'XE_DISPATCHER_WAIT'
        )
    )
    INSERT INTO #wait_stats
    (
        wait_type,
        waiting_tasks_count,
        wait_time_ms,
        max_wait_time_ms,
        signal_wait_time_ms,
        wait_pct,
        signal_wait_pct,
        category
    )
    SELECT
        wait_type,
        waiting_tasks_count,
        wait_time_ms,
        max_wait_time_ms,
        signal_wait_time_ms,
        wait_pct,
        signal_wait_pct,
        category
    FROM categorized_waits
    ORDER BY 
        wait_time_ms DESC;
    
    /* Calculate category-based summary */
    INSERT INTO #wait_summary
    (
        category,
        total_waits,
        total_wait_time_ms,
        wait_pct,
        avg_wait_ms,
        signal_wait_pct
    )
    SELECT
        category = ws.category,
        total_waits = SUM(ws.waiting_tasks_count),
        total_wait_time_ms = SUM(ws.wait_time_ms),
        wait_pct = 
            CONVERT(decimal(18, 2), 
                100.0 * SUM(ws.wait_time_ms) / NULLIF((SELECT SUM(wait_time_ms) FROM #wait_stats), 0)),
        avg_wait_ms = 
            CONVERT(decimal(18, 2), 
                SUM(ws.wait_time_ms) * 1.0 / NULLIF(SUM(ws.waiting_tasks_count), 0)),
        signal_wait_pct = 
            CONVERT(decimal(18, 2), 
                100.0 * SUM(ws.signal_wait_time_ms) / NULLIF(SUM(ws.wait_time_ms), 0))
    FROM #wait_stats AS ws
    WHERE ws.category <> 'Idle' /* Exclude idle waits from summary */
    GROUP BY 
        ws.category
    ORDER BY 
        SUM(ws.wait_time_ms) DESC;
    
    /* Calculate overall signal wait percentage for CPU pressure check */
    SELECT
        @signal_wait_pct =
            CONVERT(decimal(18, 2), 
                100.0 * SUM(ws.signal_wait_time_ms) / NULLIF(SUM(ws.wait_time_ms), 0))
    FROM #wait_stats AS ws
    WHERE ws.category <> 'Idle';
    
    /* Calculate overall resource wait percentage */
    SET @resource_wait_pct = 100.0 - @signal_wait_pct;
    
    /* Add wait_stats summary to server_info */
    INSERT INTO #server_info
    (
        info_type,
        value
    )
    SELECT
        info_type = N'Wait Stats Last Reset',
        value = 
            CASE
                WHEN @wait_stats_uptime_hours < 2 THEN N'DMV data may be unreliable - recently reset'
                ELSE N'Uptime: ' + CONVERT(nvarchar(10), CONVERT(decimal(18, 2), @wait_stats_uptime_hours)) + N' hours'
            END;
    
    /* Add wait patterns to results when significant */
    
    /* CPU Pressure Detection - High signal wait percentage */
    IF @signal_wait_pct >= @cpu_pressure_threshold
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
            5001,
            CASE
                WHEN @signal_wait_pct >= 30 THEN 20 /* Critical */
                WHEN @signal_wait_pct >= 25 THEN 30 /* High */
                ELSE 40 /* Medium */
            END,
            N'Wait Statistics',
            N'CPU Pressure Detected',
            N'Signal wait percentage is ' + CONVERT(nvarchar(10), @signal_wait_pct) + 
            N'% of all waits. Signal waits represent time spent waiting to get on the CPU after resources are available. ' +
            N'High signal wait percentage indicates CPU pressure. ' +
            CASE
                WHEN @signal_wait_pct >= 30 THEN N'CRITICAL: Severe CPU pressure is affecting performance.'
                WHEN @signal_wait_pct >= 25 THEN N'WARNING: Significant CPU pressure may be affecting performance.'
                ELSE N'MONITOR: CPU pressure is higher than optimal but may not be severely impacting performance yet.'
            END,
            N'https://erikdarling.com/sp_PerfCheck#CPUPressure'
        );
    END;
    
    /* Check for dominant wait categories */
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
        check_id = 
            CASE 
                WHEN ws.category = 'I/O' THEN 5002
                WHEN ws.category = 'Lock' THEN 5003
                WHEN ws.category = 'Memory' THEN 5004
                WHEN ws.category = 'Network' THEN 5005
                ELSE 5006
            END,
        priority = 
            CASE
                WHEN ws.wait_pct >= 60 THEN 30 /* Critical */
                WHEN ws.wait_pct >= 40 THEN 40 /* High */
                ELSE 50 /* Medium */
            END,
        category = N'Wait Statistics',
        finding = ws.category + N' Bottleneck Detected',
        details =
            ws.category + N' related waits account for ' + 
            CONVERT(nvarchar(10), ws.wait_pct) + N'% of all non-idle waits ' +
            N'with an average duration of ' + CONVERT(nvarchar(10), ws.avg_wait_ms) + N' ms per wait. ' +
            CASE ws.category
                WHEN 'I/O' THEN 
                    CASE 
                        WHEN ws.wait_pct >= 60 THEN N'CRITICAL: Severe I/O bottleneck. Check storage subsystem performance and database file layout.'
                        ELSE N'Optimize I/O configuration, database file layout and index strategy to reduce I/O pressure.'
                    END
                WHEN 'Lock' THEN 
                    CASE 
                        WHEN ws.wait_pct >= 60 THEN N'CRITICAL: Severe locking or blocking issues may be causing performance problems.'
                        ELSE N'Review long-running transactions, isolation levels, and lock escalation settings.'
                    END
                WHEN 'Memory' THEN 
                    CASE 
                        WHEN ws.wait_pct >= 60 THEN N'CRITICAL: Memory pressure is severe. Check for memory-intensive queries and optimize memory configuration.'
                        ELSE N'Review memory configuration, query memory grants, and plan cache efficiency.'
                    END
                WHEN 'Network' THEN 
                    CASE 
                        WHEN ws.wait_pct >= 60 THEN N'CRITICAL: Network bottleneck detected. Check for network configuration issues or app design problems.'
                        ELSE N'Review network configuration, client connectivity patterns, and data transfer volumes.'
                    END
                ELSE 
                    CASE 
                        WHEN ws.wait_pct >= 60 THEN N'CRITICAL: Review wait types within this category for specific bottlenecks.'
                        ELSE N'Monitor these waits for patterns to identify specific bottlenecks.'
                    END
            END,
        url = N'https://erikdarling.com/sp_PerfCheck#WaitStats'
    FROM #wait_summary AS ws
    WHERE ws.wait_pct >= @io_pressure_threshold
    AND ws.category <> 'Idle'
    AND ws.category <> 'Other';
    
    /* Check for specific problematic wait types with high average duration */
    INSERT INTO
        #results
    (
        check_id,
        priority,
        category,
        finding,
        object_name,
        details,
        url
    )
    SELECT TOP 5 /* Focus on top 5 highest impact waits */
        check_id = 5007,
        priority = 
            CASE
                WHEN ws.avg_wait_ms >= 500 THEN 30 /* Critical */
                WHEN ws.avg_wait_ms >= 100 THEN 40 /* High */
                ELSE 50 /* Medium */
            END,
        category = N'Wait Statistics',
        finding = N'High Duration Waits Detected',
        object_name = ws.wait_type,
        details =
            N'Wait type ' + ws.wait_type + N' has an unusually high average wait time of ' +
            CONVERT(nvarchar(10), ws.avg_wait_ms) + N' ms (' +
            CONVERT(nvarchar(10), ws.wait_pct) + N'% of total wait time). ' +
            CASE
                WHEN ws.category = 'I/O' THEN N'This indicates potential I/O subsystem performance issues.'
                WHEN ws.category = 'Lock' THEN N'This indicates potential locking or blocking issues.'
                WHEN ws.category = 'Memory' THEN N'This indicates potential memory pressure or configuration issues.'
                WHEN ws.category = 'CPU' THEN N'This indicates potential CPU pressure or parallelism issues.'
                WHEN ws.category = 'Network' THEN N'This indicates potential network or client connectivity issues.'
                ELSE N'Review this wait type for potential bottlenecks.'
            END +
            CASE
                WHEN ws.avg_wait_ms >= 500 THEN N' CRITICAL: Extremely high wait durations severely impact performance.'
                WHEN ws.avg_wait_ms >= 100 THEN N' WARNING: High wait durations impact performance.'
                ELSE N' MONITOR: Moderate wait durations - monitor for changes.'
            END,
        url = N'https://erikdarling.com/sp_PerfCheck#WaitTypes'
    FROM #wait_stats AS ws
    WHERE ws.category <> 'Idle'
    AND ws.avg_wait_ms >= @high_avg_wait_ms
    AND ws.wait_pct >= 1.0 /* Only significant waits */
    ORDER BY 
        ws.avg_wait_ms * ws.wait_pct DESC; /* Order by impact (duration * percentage) */
    
    /* Check for abnormal wait relationships */
    
    /* I/O waits distribution - PAGEIOLATCH vs WRITELOG */
    WITH io_waits AS 
    (
        SELECT
            pageio_pct = 
                100.0 * SUM(CASE WHEN wait_type LIKE 'PAGEIOLATCH_%' THEN wait_time_ms ELSE 0 END) / 
                NULLIF(SUM(CASE WHEN category = 'I/O' THEN wait_time_ms ELSE 0 END), 0),
            writelog_pct = 
                100.0 * SUM(CASE WHEN wait_type = 'WRITELOG' THEN wait_time_ms ELSE 0 END) / 
                NULLIF(SUM(CASE WHEN category = 'I/O' THEN wait_time_ms ELSE 0 END), 0)
        FROM #wait_stats
        WHERE category = 'I/O'
    )
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
        check_id = 5008,
        priority = 40, /* High */
        category = N'Wait Statistics',
        finding = N'Unbalanced I/O Wait Pattern',
        details =
            N'I/O wait patterns show ' +
            CONVERT(nvarchar(10), CONVERT(decimal(18, 2), iow.pageio_pct)) + N'% for data reads/writes and ' +
            CONVERT(nvarchar(10), CONVERT(decimal(18, 2), iow.writelog_pct)) + N'% for log writes. ' +
            CASE
                WHEN iow.writelog_pct > 40 THEN N'High log write waits indicate potential transaction log bottlenecks. Check log file configuration and heavy write workloads.'
                WHEN iow.pageio_pct > 90 THEN N'Almost all I/O waits are for data files. Check data file configuration and read-heavy workloads.'
                ELSE N'The I/O wait distribution indicates potential I/O subsystem imbalance or configuration issues.'
            END,
        url = N'https://erikdarling.com/sp_PerfCheck#IOWaits'
    FROM io_waits AS iow
    WHERE iow.writelog_pct > 40 OR iow.pageio_pct > 90;
    
    /* Parallelism waits pattern - CXPACKET vs CXCONSUMER vs SOS_SCHEDULER_YIELD */
    WITH parallelism_waits AS
    (
        SELECT
            cxpacket_pct = 
                100.0 * SUM(CASE WHEN wait_type = 'CXPACKET' THEN wait_time_ms ELSE 0 END) / 
                NULLIF(SUM(CASE WHEN category = 'CPU' THEN wait_time_ms ELSE 0 END), 0),
            cxconsumer_pct = 
                100.0 * SUM(CASE WHEN wait_type = 'CXCONSUMER' THEN wait_time_ms ELSE 0 END) / 
                NULLIF(SUM(CASE WHEN category = 'CPU' THEN wait_time_ms ELSE 0 END), 0),
            cxpacket_to_cxconsumer_ratio = 
                NULLIF(SUM(CASE WHEN wait_type = 'CXPACKET' THEN wait_time_ms ELSE 0 END), 0) / 
                NULLIF(SUM(CASE WHEN wait_type = 'CXCONSUMER' THEN wait_time_ms ELSE 0 END), 0),
            scheduler_yield_pct = 
                100.0 * SUM(CASE WHEN wait_type = 'SOS_SCHEDULER_YIELD' THEN wait_time_ms ELSE 0 END) / 
                NULLIF(SUM(CASE WHEN category = 'CPU' THEN wait_time_ms ELSE 0 END), 0),
            signal_pct = AVG(signal_wait_pct)
        FROM #wait_stats
        WHERE category = 'CPU'
    )
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
        check_id = 5009,
        priority = 40, /* High */
        category = N'Wait Statistics',
        finding = N'Parallelism Configuration Issues',
        details =
            N'Parallelism-related waits show: ' +
            CONVERT(nvarchar(10), CONVERT(decimal(18, 2), pw.cxpacket_pct)) + N'% CXPACKET, ' +
            CONVERT(nvarchar(10), CONVERT(decimal(18, 2), pw.cxconsumer_pct)) + N'% CXCONSUMER, and ' +
            CONVERT(nvarchar(10), CONVERT(decimal(18, 2), pw.scheduler_yield_pct)) + N'% SOS_SCHEDULER_YIELD. ' +
            CASE
                WHEN pw.cxconsumer_pct > 40 THEN 
                    N'High CXCONSUMER waits indicate unbalanced parallelism where some threads finish work before others. ' +
                    N'This suggests skewed data distribution or non-uniform CPU performance. '
                WHEN pw.cxpacket_pct > 40 AND ISNULL(pw.cxpacket_to_cxconsumer_ratio, 999) > 5 THEN
                    N'High CXPACKET waits with low CXCONSUMER waits indicate thread synchronization issues. ' +
                    N'This is common on older SQL versions, but on newer versions may indicate inefficient parallelism. '
                WHEN pw.scheduler_yield_pct > 25 THEN 
                    N'High SOS_SCHEDULER_YIELD waits indicate CPU pressure or MAXDOP settings that do not match workload. '
                ELSE N''
            END +
            CASE
                WHEN (@product_version_major >= 13 OR (@product_version_major = 12 AND @product_version_minor >= 50)) 
                     AND ISNULL(pw.cxpacket_to_cxconsumer_ratio, 999) > 5 AND pw.cxpacket_pct > 20
                THEN N'Your SQL Server version should show more CXCONSUMER waits relative to CXPACKET. ' +
                     N'The imbalance may indicate outdated trace flags (like 8649) or other parallelism issues. '
                ELSE N''
            END +
            CASE
                WHEN pw.cxpacket_pct > 40 AND @max_dop > 4 
                THEN N'Consider reducing MAXDOP from ' + CONVERT(nvarchar(10), @max_dop) + 
                     N' and/or increasing cost threshold for parallelism from ' + CONVERT(nvarchar(10), @cost_threshold) + N'. '
                ELSE N''
            END,
        url = N'https://erikdarling.com/sp_PerfCheck#Parallelism'
    FROM parallelism_waits AS pw
    WHERE pw.cxpacket_pct > 30 OR pw.cxconsumer_pct > 30 OR pw.scheduler_yield_pct > 25 OR 
         (ISNULL(pw.cxpacket_to_cxconsumer_ratio, 999) > 5 AND pw.cxpacket_pct > 20 AND 
          (@product_version_major >= 13 OR (@product_version_major = 12 AND @product_version_minor >= 50)));
    
    /* Add wait stats analysis summary to server_info */
    INSERT INTO
        #server_info
    (
        info_type,
        value
    )
    SELECT
        info_type = N'Wait Stats Pattern',
        value = 
            N'Signal waits: ' + CONVERT(nvarchar(10), @signal_wait_pct) + 
            N'%, Resource waits: ' + CONVERT(nvarchar(10), @resource_wait_pct) + N'% ' +
            N'(Top waits: ' + 
            (SELECT TOP 3 wait_type + ' (' + CONVERT(nvarchar(10), CONVERT(decimal(18, 1), wait_pct)) + '%), ' 
             FROM #wait_stats 
             WHERE category <> 'Idle'
             ORDER BY wait_pct DESC
             FOR XML PATH(''), TYPE).value('.', 'nvarchar(max)') +
            N')'
    WHERE @signal_wait_pct IS NOT NULL;

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
