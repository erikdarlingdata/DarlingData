# Implementation Plan - DarlingDataCollector

## Core Collection Procedures

This document contains pseudocode and implementation details for the core collection procedures.

### Wait Stats Collection

```sql
CREATE OR ALTER PROCEDURE 
    collection.collect_wait_stats
(
    @debug bit = 0, /*Print detailed information*/
    @sample_seconds integer = NULL /*Optional: Collect sample over time period*/
)
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
    
    DECLARE
        @collection_time datetime2(7) = SYSDATETIME(),
        @sql nvarchar(max),
        @params nvarchar(max),
        @rows_collected integer = 0,
        @error_message nvarchar(4000),
        @has_wait_info bit = 0;
        
    /* Environment detection */
    IF NOT EXISTS (SELECT 1/0 FROM sys.all_objects WHERE name = 'dm_os_wait_stats')
    BEGIN
        RAISERROR('Required DMV sys.dm_os_wait_stats does not exist in this environment.', 10, 1) WITH NOWAIT;
        RETURN;
    END;
    
    /* Optional sample mode */
    IF @sample_seconds IS NOT NULL AND @sample_seconds > 0
    BEGIN
        /* Clear wait stats and capture after N seconds */
        DBCC SQLPERF(N'sys.dm_os_wait_stats', CLEAR) WITH NO_INFOMSGS;
        
        /* Wait for the specified period */
        WAITFOR DELAY CAST(CONCAT('00:00:', RIGHT('00' + CAST(@sample_seconds AS varchar(2)), 2)) AS time);
        
        /* Recapture collection time to reflect sample end */
        SET @collection_time = SYSDATETIME();
    END;
    
    /* Build and execute dynamic collection query */
    SET @sql = N'
    INSERT collection.wait_stats
    (
        collection_time,
        server_uptime_seconds,
        wait_type,
        waiting_tasks_count,
        wait_time_ms,
        max_wait_time_ms,
        signal_wait_time_ms
    )
    SELECT
        collection_time = @collection_time,
        server_uptime_seconds = DATEDIFF(SECOND, sqlserver_start_time, SYSDATETIME()),
        wait_type,
        waiting_tasks_count,
        wait_time_ms,
        max_wait_time_ms,
        signal_wait_time_ms
    FROM sys.dm_os_wait_stats AS ws
    CROSS JOIN sys.dm_os_sys_info AS si
    WHERE wait_type NOT IN (
        /* System waits that can be safely filtered */
        N''LAZYWRITER_SLEEP'',
        N''SQLTRACE_BUFFER_FLUSH'',
        N''SQLTRACE_INCREMENTAL_FLUSH_SLEEP'',
        N''WAITFOR'',
        N''SLEEP_TASK'',
        N''REQUEST_FOR_DEADLOCK_SEARCH'',
        N''XE_TIMER_EVENT'',
        N''XE_DISPATCHER_WAIT'',
        N''LOGMGR_QUEUE'',
        N''CHECKPOINT_QUEUE'',
        N''BROKER_TASK_STOP'',
        N''BROKER_TO_FLUSH'',
        N''BROKER_EVENTHANDLER'',
        N''FT_IFTS_SCHEDULER_IDLE_WAIT'',
        N''SQLTRACE_WAIT_ENTRIES'',
        N''CLR_AUTO_EVENT'',
        N''CLR_MANUAL_EVENT'',
        N''DIRTY_PAGE_POLL'',
        N''HADR_FILESTREAM_IOMGR_IOCOMPLETION''
    )
    OR wait_type LIKE N''LATCH_%''
    OR wait_type LIKE N''PAGEIOLATCH_%''
    OR wait_type LIKE N''PAGELATCH_%'';';
    
    SET @params = N'@collection_time datetime2(7)';
    
    IF @debug = 1
        PRINT @sql;
        
    BEGIN TRY
        EXECUTE sp_executesql
            @sql,
            @params,
            @collection_time = @collection_time;
            
        SET @rows_collected = @@ROWCOUNT;
        
        /* Run delta calculation procedure */
        EXECUTE collection.calculate_wait_stats_delta 
            @collection_time = @collection_time;
            
        IF @debug = 1
            RAISERROR('Wait stats collection complete. Rows collected: %d', 10, 1, @rows_collected) WITH NOWAIT;
    END TRY
    BEGIN CATCH
        SET @error_message = 
            CONCAT('Error collecting wait stats: ', 
                   ERROR_MESSAGE(), 
                   ' (Line: ', ERROR_LINE(), ')');
                   
        RAISERROR(@error_message, 11, 1) WITH NOWAIT;
    END CATCH;
END;
```

### Memory Collection

```sql
CREATE OR ALTER PROCEDURE 
    collection.collect_memory_clerks
(
    @debug bit = 0, /*Print detailed information*/
    @include_node_details bit = 0 /*Include memory node details*/
)
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
    
    DECLARE
        @collection_time datetime2(7) = SYSDATETIME(),
        @sql nvarchar(max),
        @params nvarchar(max),
        @rows_collected integer = 0,
        @error_message nvarchar(4000);
        
    /* Environment detection */
    IF NOT EXISTS (SELECT 1/0 FROM sys.all_objects WHERE name = 'dm_os_memory_clerks')
    BEGIN
        RAISERROR('Required DMV sys.dm_os_memory_clerks does not exist in this environment.', 10, 1) WITH NOWAIT;
        RETURN;
    END;
    
    /* Clean up previous temporary results if needed */
    IF OBJECT_ID('tempdb..#memory_clerks') IS NOT NULL
        DROP TABLE #memory_clerks;
    
    /* Build and execute dynamic collection query */
    SET @sql = N'
    SELECT
        collection_time = @collection_time,
        clerk_type = mc.type,
        memory_node_id = mc.memory_node_id,
        single_pages_kb = SUM(mc.single_pages_kb),
        multi_pages_kb = SUM(mc.multi_pages_kb),
        virtual_memory_reserved_kb = SUM(mc.virtual_memory_reserved_kb),
        virtual_memory_committed_kb = SUM(mc.virtual_memory_committed_kb),
        awe_allocated_kb = SUM(mc.awe_allocated_kb),
        shared_memory_reserved_kb = SUM(mc.shared_memory_reserved_kb),
        shared_memory_committed_kb = SUM(mc.shared_memory_committed_kb)
    INTO #memory_clerks
    FROM sys.dm_os_memory_clerks AS mc
    GROUP BY
        mc.type,
        mc.memory_node_id
    OPTION(RECOMPILE);

    /* Insert aggregated results */
    INSERT collection.memory_clerks
    (
        collection_time,
        clerk_type,
        memory_node_id,
        single_pages_kb,
        multi_pages_kb,
        virtual_memory_reserved_kb,
        virtual_memory_committed_kb,
        awe_allocated_kb,
        shared_memory_reserved_kb,
        shared_memory_committed_kb
    )';
    
    /* Either include all node details or aggregate by clerk type */
    IF @include_node_details = 1
    BEGIN
        SET @sql = @sql + N'
        SELECT
            collection_time,
            clerk_type,
            memory_node_id,
            single_pages_kb,
            multi_pages_kb,
            virtual_memory_reserved_kb,
            virtual_memory_committed_kb,
            awe_allocated_kb,
            shared_memory_reserved_kb,
            shared_memory_committed_kb
        FROM #memory_clerks;';
    END
    ELSE
    BEGIN
        SET @sql = @sql + N'
        SELECT
            collection_time,
            clerk_type,
            memory_node_id = -1, /* Aggregate across all nodes */
            single_pages_kb = SUM(single_pages_kb),
            multi_pages_kb = SUM(multi_pages_kb),
            virtual_memory_reserved_kb = SUM(virtual_memory_reserved_kb),
            virtual_memory_committed_kb = SUM(virtual_memory_committed_kb),
            awe_allocated_kb = SUM(awe_allocated_kb),
            shared_memory_reserved_kb = SUM(shared_memory_reserved_kb),
            shared_memory_committed_kb = SUM(shared_memory_committed_kb)
        FROM #memory_clerks
        GROUP BY
            collection_time,
            clerk_type;';
    END;
    
    SET @params = N'@collection_time datetime2(7)';
    
    IF @debug = 1
        PRINT @sql;
        
    BEGIN TRY
        EXECUTE sp_executesql
            @sql,
            @params,
            @collection_time = @collection_time;
            
        SET @rows_collected = @@ROWCOUNT;
            
        IF @debug = 1
            RAISERROR('Memory clerks collection complete. Rows collected: %d', 10, 1, @rows_collected) WITH NOWAIT;
            
        /* Also collect memory summary */
        EXECUTE collection.collect_memory_summary
            @collection_time = @collection_time,
            @debug = @debug;
    END TRY
    BEGIN CATCH
        SET @error_message = 
            CONCAT('Error collecting memory clerks: ', 
                   ERROR_MESSAGE(), 
                   ' (Line: ', ERROR_LINE(), ')');
                   
        RAISERROR(@error_message, 11, 1) WITH NOWAIT;
    END CATCH;
    
    /* Clean up */
    IF OBJECT_ID('tempdb..#memory_clerks') IS NOT NULL
        DROP TABLE #memory_clerks;
END;
```

### I/O Stats Collection

```sql
CREATE OR ALTER PROCEDURE 
    collection.collect_io_stats
(
    @debug bit = 0 /*Print detailed information*/
)
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
    
    DECLARE
        @collection_time datetime2(7) = SYSDATETIME(),
        @sql nvarchar(max),
        @params nvarchar(max),
        @rows_collected integer = 0,
        @error_message nvarchar(4000);
        
    /* Environment detection */
    IF NOT EXISTS (SELECT 1/0 FROM sys.all_objects WHERE name = 'dm_io_virtual_file_stats')
    BEGIN
        RAISERROR('Required DMV sys.dm_io_virtual_file_stats does not exist in this environment.', 10, 1) WITH NOWAIT;
        RETURN;
    END;
    
    /* Build dynamic collection query */
    SET @sql = N'
    INSERT collection.io_file_stats
    (
        collection_time,
        database_id,
        database_name,
        file_id,
        file_name,
        file_type,
        file_size_mb,
        file_used_mb,
        io_stall_read_ms,
        io_stall_write_ms,
        num_of_reads,
        num_of_writes,
        num_of_bytes_read,
        num_of_bytes_written,
        io_stall_queued_read_ms,
        io_stall_queued_write_ms
    )
    SELECT
        collection_time = @collection_time,
        database_id = fs.database_id,
        database_name = DB_NAME(fs.database_id),
        file_id = fs.file_id,
        file_name = f.name,
        file_type = CASE WHEN f.type = 0 THEN ''data'' ELSE ''log'' END,
        file_size_mb = f.size * 8 / 1024, -- Convert 8KB pages to MB
        file_used_mb = FILEPROPERTY(f.name, ''SpaceUsed'') * 8 / 1024,
        io_stall_read_ms = fs.io_stall_read_ms,
        io_stall_write_ms = fs.io_stall_write_ms,
        num_of_reads = fs.num_of_reads,
        num_of_writes = fs.num_of_writes,
        num_of_bytes_read = fs.num_of_bytes_read,
        num_of_bytes_written = fs.num_of_bytes_written,';
    
    /* Check if the DMV has queue columns (SQL Server 2017+ and some Azure) */
    IF EXISTS (
        SELECT 1/0 
        FROM sys.all_columns 
        WHERE object_id = OBJECT_ID('sys.dm_io_virtual_file_stats')
        AND name = 'io_stall_queued_read_ms'
    )
    BEGIN
        SET @sql = @sql + N'
        io_stall_queued_read_ms = fs.io_stall_queued_read_ms,
        io_stall_queued_write_ms = fs.io_stall_queued_write_ms';
    END
    ELSE
    BEGIN
        SET @sql = @sql + N'
        io_stall_queued_read_ms = NULL,
        io_stall_queued_write_ms = NULL';
    END;
    
    SET @sql = @sql + N'
    FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS fs
    JOIN sys.master_files AS f
      ON fs.database_id = f.database_id
      AND fs.file_id = f.file_id
    WHERE fs.database_id > 4 -- Skip system databases
    AND DB_NAME(fs.database_id) IS NOT NULL; -- Skip databases that might be in the process of being dropped';
    
    SET @params = N'@collection_time datetime2(7)';
    
    IF @debug = 1
        PRINT @sql;
        
    BEGIN TRY
        EXECUTE sp_executesql
            @sql,
            @params,
            @collection_time = @collection_time;
            
        SET @rows_collected = @@ROWCOUNT;
            
        /* Calculate IO deltas */
        EXECUTE collection.calculate_io_stats_delta
            @collection_time = @collection_time,
            @debug = @debug;
            
        IF @debug = 1
            RAISERROR('IO stats collection complete. Rows collected: %d', 10, 1, @rows_collected) WITH NOWAIT;
    END TRY
    BEGIN CATCH
        SET @error_message = 
            CONCAT('Error collecting IO stats: ', 
                   ERROR_MESSAGE(), 
                   ' (Line: ', ERROR_LINE(), ')');
                   
        RAISERROR(@error_message, 11, 1) WITH NOWAIT;
    END CATCH;
END;
```

## SQL Agent Jobs

Job creation script for the core collection jobs:

```sql
CREATE OR ALTER PROCEDURE
    system.sp_create_collection_jobs
(
    @enable_jobs bit = 0, /*Create jobs enabled or disabled*/
    @owner_login_name sysname = NULL, /*Job owner*/
    @email_operator sysname = NULL, /*Email operator for notifications*/
    @debug bit = 0 /*Print job creation commands*/
)
AS
BEGIN
    SET NOCOUNT ON;
    
    /* Default the job owner if not specified */
    IF @owner_login_name IS NULL
    BEGIN
        SELECT @owner_login_name = SUSER_SNAME();
    END;
    
    DECLARE 
        @job_cmd nvarchar(max),
        @category_exists bit,
        @enabled tinyint = CASE WHEN @enable_jobs = 1 THEN 1 ELSE 0 END;
    
    /* Create job category if it doesn't exist */
    SELECT @category_exists = 0;
    
    IF EXISTS(SELECT 1 FROM msdb.dbo.syscategories WHERE name = N'DarlingData')
    BEGIN
        SELECT @category_exists = 1;
    END;
    
    IF @category_exists = 0
    BEGIN
        IF @debug = 1
        BEGIN
            PRINT 'EXEC msdb.dbo.sp_add_category @class = N''JOB'', @type = N''LOCAL'', @name = N''DarlingData''';
        END
        ELSE
        BEGIN
            EXEC msdb.dbo.sp_add_category 
                @class = N'JOB', 
                @type = N'LOCAL', 
                @name = N'DarlingData';
        END;
    END;
    
    /* Create jobs */
    
    /* Wait Stats Collection - Every 5 Minutes */
    SET @job_cmd = N'-- Create wait stats collection job
    EXEC msdb.dbo.sp_add_job @job_name = N''DarlingData - Wait Stats Collection'',
        @enabled = ' + CAST(@enabled AS nvarchar(1)) + N',
        @description = N''Collects wait statistics every 5 minutes'',
        @category_name = N''DarlingData'',
        @owner_login_name = N''' + @owner_login_name + N''',
        @notify_level_eventlog = 2;
    
    EXEC msdb.dbo.sp_add_jobstep @job_name = N''DarlingData - Wait Stats Collection'',
        @step_name = N''Collect Wait Stats'',
        @subsystem = N''TSQL'',
        @command = N''EXECUTE DarlingData.collection.collect_wait_stats;'',
        @database_name = N''master'',
        @retry_attempts = 3,
        @retry_interval = 1;
    
    EXEC msdb.dbo.sp_add_jobschedule @job_name = N''DarlingData - Wait Stats Collection'',
        @name = N''Every 5 Minutes'',
        @freq_type = 4, -- Daily
        @freq_interval = 1,
        @freq_subday_type = 4, -- Minutes
        @freq_subday_interval = 5;
    
    EXEC msdb.dbo.sp_add_jobserver @job_name = N''DarlingData - Wait Stats Collection'';
    ';
    
    IF @debug = 1
    BEGIN
        PRINT @job_cmd;
    END
    ELSE
    BEGIN
        EXEC sp_executesql @job_cmd;
    END;
    
    /* Memory Collection - Every 5 Minutes */
    SET @job_cmd = N'-- Create memory collection job
    EXEC msdb.dbo.sp_add_job @job_name = N''DarlingData - Memory Collection'',
        @enabled = ' + CAST(@enabled AS nvarchar(1)) + N',
        @description = N''Collects memory usage every 5 minutes'',
        @category_name = N''DarlingData'',
        @owner_login_name = N''' + @owner_login_name + N''',
        @notify_level_eventlog = 2;
    
    EXEC msdb.dbo.sp_add_jobstep @job_name = N''DarlingData - Memory Collection'',
        @step_name = N''Collect Memory Stats'',
        @subsystem = N''TSQL'',
        @command = N''EXECUTE DarlingData.collection.collect_memory_clerks;'',
        @database_name = N''master'',
        @retry_attempts = 3,
        @retry_interval = 1;
    
    EXEC msdb.dbo.sp_add_jobschedule @job_name = N''DarlingData - Memory Collection'',
        @name = N''Every 5 Minutes'',
        @freq_type = 4, -- Daily
        @freq_interval = 1,
        @freq_subday_type = 4, -- Minutes
        @freq_subday_interval = 5;
    
    EXEC msdb.dbo.sp_add_jobserver @job_name = N''DarlingData - Memory Collection'';
    ';
    
    IF @debug = 1
    BEGIN
        PRINT @job_cmd;
    END
    ELSE
    BEGIN
        EXEC sp_executesql @job_cmd;
    END;
    
    /* IO Stats Collection - Every 15 Minutes */
    SET @job_cmd = N'-- Create I/O collection job
    EXEC msdb.dbo.sp_add_job @job_name = N''DarlingData - IO Collection'',
        @enabled = ' + CAST(@enabled AS nvarchar(1)) + N',
        @description = N''Collects I/O statistics every 15 minutes'',
        @category_name = N''DarlingData'',
        @owner_login_name = N''' + @owner_login_name + N''',
        @notify_level_eventlog = 2;
    
    EXEC msdb.dbo.sp_add_jobstep @job_name = N''DarlingData - IO Collection'',
        @step_name = N''Collect IO Stats'',
        @subsystem = N''TSQL'',
        @command = N''EXECUTE DarlingData.collection.collect_io_stats;'',
        @database_name = N''master'',
        @retry_attempts = 3,
        @retry_interval = 1;
    
    EXEC msdb.dbo.sp_add_jobschedule @job_name = N''DarlingData - IO Collection'',
        @name = N''Every 15 Minutes'',
        @freq_type = 4, -- Daily
        @freq_interval = 1,
        @freq_subday_type = 4, -- Minutes
        @freq_subday_interval = 15;
    
    EXEC msdb.dbo.sp_add_jobserver @job_name = N''DarlingData - IO Collection'';
    ';
    
    IF @debug = 1
    BEGIN
        PRINT @job_cmd;
    END
    ELSE
    BEGIN
        EXEC sp_executesql @job_cmd;
    END;
    
    /* Maintenance - Daily at 1:00 AM */
    SET @job_cmd = N'-- Create maintenance job
    EXEC msdb.dbo.sp_add_job @job_name = N''DarlingData - Maintenance'',
        @enabled = ' + CAST(@enabled AS nvarchar(1)) + N',
        @description = N''Performs data retention and maintenance tasks'',
        @category_name = N''DarlingData'',
        @owner_login_name = N''' + @owner_login_name + N''',
        @notify_level_eventlog = 2;
    
    EXEC msdb.dbo.sp_add_jobstep @job_name = N''DarlingData - Maintenance'',
        @step_name = N''Run Retention'',
        @subsystem = N''TSQL'',
        @command = N''EXECUTE DarlingData.maintenance.sp_purge_old_data;'',
        @database_name = N''master'',
        @retry_attempts = 3,
        @retry_interval = 1;
    
    EXEC msdb.dbo.sp_add_jobschedule @job_name = N''DarlingData - Maintenance'',
        @name = N''Daily at 1 AM'',
        @freq_type = 4, -- Daily
        @freq_interval = 1,
        @active_start_time = 10000; -- 1:00 AM
    
    EXEC msdb.dbo.sp_add_jobserver @job_name = N''DarlingData - Maintenance'';
    ';
    
    IF @debug = 1
    BEGIN
        PRINT @job_cmd;
    END
    ELSE
    BEGIN
        EXEC sp_executesql @job_cmd;
    END;
    
    /* Configure email notifications if specified */
    IF @email_operator IS NOT NULL
    BEGIN
        SET @job_cmd = N'-- Configure email notifications
        EXEC msdb.dbo.sp_update_job @job_name = N''DarlingData - Wait Stats Collection'',
            @notify_level_email = 2, -- On failure
            @notify_email_operator_name = N''' + @email_operator + N''';
            
        EXEC msdb.dbo.sp_update_job @job_name = N''DarlingData - Memory Collection'',
            @notify_level_email = 2, -- On failure
            @notify_email_operator_name = N''' + @email_operator + N''';
            
        EXEC msdb.dbo.sp_update_job @job_name = N''DarlingData - IO Collection'',
            @notify_level_email = 2, -- On failure
            @notify_email_operator_name = N''' + @email_operator + N''';
            
        EXEC msdb.dbo.sp_update_job @job_name = N''DarlingData - Maintenance'',
            @notify_level_email = 2, -- On failure
            @notify_email_operator_name = N''' + @email_operator + N''';
        ';
        
        IF @debug = 1
        BEGIN
            PRINT @job_cmd;
        END
        ELSE
        BEGIN
            EXEC sp_executesql @job_cmd;
        END;
    END;
END;
```

## Next Steps

1. Implement remaining collection procedures
2. Create full installation script
3. Develop data analysis queries
4. Build reporting dashboard views
5. Test in various SQL Server environments