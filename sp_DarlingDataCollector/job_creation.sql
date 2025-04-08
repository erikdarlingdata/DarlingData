/*
██████╗  █████╗ ██████╗ ██╗     ██╗███╗   ██╗ ██████╗ ██████╗  █████╗ ████████╗ █████╗  ██████╗ ██████╗ ██╗     ██╗     ███████╗ ██████╗████████╗ ██████╗ ██████╗ 
██╔══██╗██╔══██╗██╔══██╗██║     ██║████╗  ██║██╔════╝ ██╔══██╗██╔══██╗╚══██╔══╝██╔══██╗██╔════╝██╔═══██╗██║     ██║     ██╔════╝██╔════╝╚══██╔══╝██╔═══██╗██╔══██╗
██║  ██║███████║██████╔╝██║     ██║██╔██╗ ██║██║  ███╗██║  ██║███████║   ██║   ███████║██║     ██║   ██║██║     ██║     █████╗  ██║        ██║   ██║   ██║██████╔╝
██║  ██║██╔══██║██╔══██╗██║     ██║██║╚██╗██║██║   ██║██║  ██║██╔══██║   ██║   ██╔══██║██║     ██║   ██║██║     ██║     ██╔══╝  ██║        ██║   ██║   ██║██╔══██╗
██████╔╝██║  ██║██║  ██║███████╗██║██║ ╚████║╚██████╔╝██████╔╝██║  ██║   ██║   ██║  ██║╚██████╗╚██████╔╝███████╗███████╗███████╗╚██████╗   ██║   ╚██████╔╝██║  ██║
╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚══════╝╚══════╝╚══════╝ ╚═════╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝
                                                                                                                                                                  
Copyright (c) Darling Data, LLC
https://www.erikdarling.com/

--===== JOB CREATION NOTES ====--
This procedure creates SQL Agent jobs for the DarlingDataCollector.
It verifies the environment is supported (must have SQL Agent)
and creates both collection jobs and data retention jobs.

Supported environments:
- On-premises SQL Server
- Azure SQL Managed Instance
- Amazon RDS for SQL Server (with Agent enabled)
*/

CREATE OR ALTER PROCEDURE
    system.create_collection_jobs
(
    @debug BIT = 0, /*Print debugging information*/
    @minute_frequency INTEGER = 15, /*Frequency in minutes for regular collections*/
    @hourly_frequency INTEGER = 60, /*Frequency in minutes for hourly collections*/
    @daily_frequency INTEGER = 1440, /*Frequency in minutes for daily collections*/
    @retention_days INTEGER = 30, /*Number of days to retain collected data*/
    @default_database_name NVARCHAR(128) = 'DarlingData' /*Database name for collection*/
)
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
    
    DECLARE
        @job_exists INTEGER,
        @job_id UNIQUEIDENTIFIER,
        @platform NVARCHAR(50),
        @instance_type NVARCHAR(50),
        @engine_edition INTEGER,
        @is_supported BIT = 1;
    
    /*
    Detect environment
    */
    SELECT
        @engine_edition = CONVERT(INTEGER, SERVERPROPERTY('EngineEdition'));
        
    -- Azure SQL MI has EngineEdition = 8
    IF @engine_edition = 8
    BEGIN
        SET @platform = 'Azure';
        SET @instance_type = 'AzureMI';
    END;
    -- Azure SQL DB has EngineEdition = 5 (not supported)
    ELSE IF @engine_edition = 5
    BEGIN
        SET @platform = 'Azure';
        SET @instance_type = 'AzureDB';
        SET @is_supported = 0;
    END;
    -- Check for AWS RDS using the presence of rdsadmin database
    ELSE IF DB_ID('rdsadmin') IS NOT NULL
    BEGIN
        SET @platform = 'AWS';
        SET @instance_type = 'AWSRDS';
    END;
    -- Default to on-premises
    ELSE
    BEGIN
        SET @platform = 'OnPrem';
        SET @instance_type = 'Regular';
    END;
    
    /*
    Verify we're not in Azure SQL DB
    */
    IF @instance_type = 'AzureDB'
    BEGIN
        RAISERROR('SQL Agent jobs cannot be created in Azure SQL Database. Please use an external scheduling mechanism.', 16, 1);
        RETURN;
    END;
    
    /*
    Check if SQL Agent is available
    */
    IF NOT EXISTS (SELECT 1 FROM sys.all_objects WHERE name = 'sysjobs' AND type = 'U')
    BEGIN
        RAISERROR('SQL Agent is not available in this environment. Job creation skipped.', 16, 1);
        RETURN;
    END;
    
    /*
    Create master collection job
    */
    SELECT
        @job_exists = 0;
        
    IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = 'DarlingDataCollector - Master Collection')
    BEGIN
        SELECT
            @job_exists = 1,
            @job_id = job_id
        FROM msdb.dbo.sysjobs
        WHERE name = 'DarlingDataCollector - Master Collection';
    END;
    
    IF @job_exists = 0
    BEGIN
        EXECUTE msdb.dbo.sp_add_job
            @job_name = 'DarlingDataCollector - Master Collection',
            @description = 'Master job for all DarlingDataCollector activities',
            @category_name = 'Data Collector',
            @owner_login_name = 'sa',
            @enabled = 1,
            @job_id = @job_id OUTPUT;
        
        EXECUTE msdb.dbo.sp_add_jobserver
            @job_id = @job_id,
            @server_name = @@SERVERNAME;
    END;
    
    /*
    Create regular collection job
    */
    SELECT
        @job_exists = 0;
        
    IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = 'DarlingDataCollector - Regular Collections')
    BEGIN
        SELECT
            @job_exists = 1,
            @job_id = job_id
        FROM msdb.dbo.sysjobs
        WHERE name = 'DarlingDataCollector - Regular Collections';
    END;
    
    IF @job_exists = 0
    BEGIN
        DECLARE
            @cmd_wait_stats NVARCHAR(512),
            @cmd_memory_clerks NVARCHAR(512),
            @cmd_buffer_pool NVARCHAR(512),
            @cmd_io_stats NVARCHAR(512),
            @cmd_index_usage_stats NVARCHAR(512),
            @cmd_connections NVARCHAR(512),
            @cmd_blocking NVARCHAR(512),
            @cmd_deadlocks NVARCHAR(512),
            @cmd_query_stats NVARCHAR(512),
            @cmd_query_store NVARCHAR(512);
            
        SELECT
            @cmd_wait_stats = N'EXECUTE ' + QUOTENAME(@default_database_name) + N'.collection.collect_wait_stats @sample_seconds = 60;',
            @cmd_memory_clerks = N'EXECUTE ' + QUOTENAME(@default_database_name) + N'.collection.collect_memory_clerks;',
            @cmd_buffer_pool = N'EXECUTE ' + QUOTENAME(@default_database_name) + N'.collection.collect_buffer_pool;',
            @cmd_io_stats = N'EXECUTE ' + QUOTENAME(@default_database_name) + N'.collection.collect_io_stats @sample_seconds = 60;',
            @cmd_index_usage_stats = N'EXECUTE ' + QUOTENAME(@default_database_name) + N'.collection.collect_index_usage_stats @sample_seconds = 60;',
            @cmd_connections = N'EXECUTE ' + QUOTENAME(@default_database_name) + N'.collection.collect_connections;',
            @cmd_blocking = N'EXECUTE ' + QUOTENAME(@default_database_name) + N'.collection.collect_blocking;',
            @cmd_deadlocks = N'EXECUTE ' + QUOTENAME(@default_database_name) + N'.collection.collect_deadlocks;',
            @cmd_query_stats = N'EXECUTE ' + QUOTENAME(@default_database_name) + N'.collection.collect_query_stats @sample_seconds = 60;',
            @cmd_query_store = N'EXECUTE ' + QUOTENAME(@default_database_name) + N'.collection.collect_query_store @use_database_list = 1;';
            
        EXECUTE msdb.dbo.sp_add_job
            @job_name = 'DarlingDataCollector - Regular Collections',
            @description = 'Collects regular performance metrics (wait stats, memory, blocking)',
            @category_name = 'Data Collector',
            @owner_login_name = 'sa',
            @enabled = 1,
            @job_id = @job_id OUTPUT;
        
        EXECUTE msdb.dbo.sp_add_jobserver
            @job_id = @job_id,
            @server_name = @@SERVERNAME;
            
        /*
        Add job steps
        */
        EXECUTE msdb.dbo.sp_add_jobstep
            @job_id = @job_id,
            @step_name = 'Collect Wait Stats',
            @step_id = 1,
            @subsystem = 'TSQL',
            @command = @cmd_wait_stats,
            @database_name = @default_database_name,
            @on_success_action = 3,
            @on_fail_action = 3;
            
        EXECUTE msdb.dbo.sp_add_jobstep
            @job_id = @job_id,
            @step_name = 'Collect Memory Clerks',
            @step_id = 2,
            @subsystem = 'TSQL',
            @command = @cmd_memory_clerks,
            @database_name = @default_database_name,
            @on_success_action = 3,
            @on_fail_action = 3;
            
        EXECUTE msdb.dbo.sp_add_jobstep
            @job_id = @job_id,
            @step_name = 'Collect Buffer Pool',
            @step_id = 3,
            @subsystem = 'TSQL',
            @command = @cmd_buffer_pool,
            @database_name = @default_database_name,
            @on_success_action = 3,
            @on_fail_action = 3;
            
        EXECUTE msdb.dbo.sp_add_jobstep
            @job_id = @job_id,
            @step_name = 'Collect I/O Stats',
            @step_id = 4,
            @subsystem = 'TSQL',
            @command = @cmd_io_stats,
            @database_name = @default_database_name,
            @on_success_action = 3,
            @on_fail_action = 3;
            
        EXECUTE msdb.dbo.sp_add_jobstep
            @job_id = @job_id,
            @step_name = 'Collect Index Usage Stats',
            @step_id = 5,
            @subsystem = 'TSQL',
            @command = @cmd_index_usage_stats,
            @database_name = @default_database_name,
            @on_success_action = 3,
            @on_fail_action = 3;
            
        EXECUTE msdb.dbo.sp_add_jobstep
            @job_id = @job_id,
            @step_name = 'Collect Connections',
            @step_id = 6,
            @subsystem = 'TSQL',
            @command = @cmd_connections,
            @database_name = @default_database_name,
            @on_success_action = 3,
            @on_fail_action = 3;
            
        EXECUTE msdb.dbo.sp_add_jobstep
            @job_id = @job_id,
            @step_name = 'Collect Blocking',
            @step_id = 7,
            @subsystem = 'TSQL',
            @command = @cmd_blocking,
            @database_name = @default_database_name,
            @on_success_action = 3,
            @on_fail_action = 3;
            
        EXECUTE msdb.dbo.sp_add_jobstep
            @job_id = @job_id,
            @step_name = 'Collect Deadlocks',
            @step_id = 8,
            @subsystem = 'TSQL',
            @command = @cmd_deadlocks,
            @database_name = @default_database_name,
            @on_success_action = 3,
            @on_fail_action = 3;
            
        EXECUTE msdb.dbo.sp_add_jobstep
            @job_id = @job_id,
            @step_name = 'Collect Query Stats',
            @step_id = 9,
            @subsystem = 'TSQL',
            @command = @cmd_query_stats,
            @database_name = @default_database_name,
            @on_success_action = 3,
            @on_fail_action = 2;
            
        EXECUTE msdb.dbo.sp_add_jobstep
            @job_id = @job_id,
            @step_name = 'Collect Query Store',
            @step_id = 10,
            @subsystem = 'TSQL',
            @command = @cmd_query_store,
            @database_name = @default_database_name,
            @on_success_action = 1,
            @on_fail_action = 2;
            
        /*
        Create schedule
        */
        EXECUTE msdb.dbo.sp_add_jobschedule
            @job_id = @job_id,
            @name = 'Regular Collection Schedule',
            @enabled = 1,
            @freq_type = 4, -- Daily
            @freq_interval = 1,
            @freq_subday_type = 4, -- Minutes
            @freq_subday_interval = @minute_frequency,
            @active_start_date = 20250101,
            @active_end_date = 99991231,
            @active_start_time = 0,
            @active_end_time = 235959;
    END;
    
    /*
    Create data retention job
    */
    SELECT
        @job_exists = 0;
        
    IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = 'DarlingDataCollector - Data Retention')
    BEGIN
        SELECT
            @job_exists = 1,
            @job_id = job_id
        FROM msdb.dbo.sysjobs
        WHERE name = 'DarlingDataCollector - Data Retention';
    END;
    
    IF @job_exists = 0
    BEGIN
        DECLARE
            @cmd_data_retention NVARCHAR(512);
            
        SELECT
            @cmd_data_retention = N'EXECUTE ' + QUOTENAME(@default_database_name) + N'.system.data_retention @retention_days = ' + CAST(@retention_days AS NVARCHAR(10)) + N';';
            
        EXECUTE msdb.dbo.sp_add_job
            @job_name = 'DarlingDataCollector - Data Retention',
            @description = 'Purges old data from the DarlingDataCollector repository',
            @category_name = 'Data Collector',
            @owner_login_name = 'sa',
            @enabled = 1,
            @job_id = @job_id OUTPUT;
        
        EXECUTE msdb.dbo.sp_add_jobserver
            @job_id = @job_id,
            @server_name = @@SERVERNAME;
            
        /*
        Add job steps
        */
        EXECUTE msdb.dbo.sp_add_jobstep
            @job_id = @job_id,
            @step_name = 'Run Data Retention Procedure',
            @step_id = 1,
            @subsystem = 'TSQL',
            @command = @cmd_data_retention,
            @database_name = @default_database_name,
            @on_success_action = 1,
            @on_fail_action = 2;
            
        /*
        Create schedule
        */
        EXECUTE msdb.dbo.sp_add_jobschedule
            @job_id = @job_id,
            @name = 'Data Retention Schedule',
            @enabled = 1,
            @freq_type = 4, -- Daily
            @freq_interval = 1,
            @freq_subday_type = 1, -- At specified time
            @freq_subday_interval = 0,
            @active_start_date = 20250101,
            @active_end_date = 99991231,
            @active_start_time = 10000, -- 1:00 AM
            @active_end_time = 235959;
    END;
    
    /*
    Print debug information
    */
    IF @debug = 1
    BEGIN
        SELECT
            'Collection and retention jobs created' AS status,
            @platform AS platform,
            @instance_type AS instance_type;
            
        SELECT
            name,
            enabled,
            description
        FROM msdb.dbo.sysjobs
        WHERE name LIKE 'DarlingDataCollector%';
        
        SELECT
            j.name AS job_name,
            s.step_id,
            s.step_name,
            s.database_name,
            s.command
        FROM msdb.dbo.sysjobs AS j
        JOIN msdb.dbo.sysjobsteps AS s
            ON j.job_id = s.job_id
        WHERE j.name LIKE 'DarlingDataCollector%'
        ORDER BY j.name, s.step_id;
    END;
END;
GO