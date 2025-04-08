# DarlingData Repository Database Schema

## Database Creation

```sql
/*
Create the DarlingData repository database
*/
IF DB_ID(N'DarlingData') IS NULL
BEGIN
    CREATE DATABASE 
        DarlingData
    ON PRIMARY
    (
        NAME = N'DarlingData',
        FILENAME = N'YOUR_DATA_PATH\DarlingData.mdf',
        SIZE = 1024MB,
        FILEGROWTH = 256MB
    )
    LOG ON
    (
        NAME = N'DarlingData_log',
        FILENAME = N'YOUR_LOG_PATH\DarlingData_log.ldf',
        SIZE = 256MB,
        FILEGROWTH = 128MB
    );
    
    ALTER DATABASE
        DarlingData
    SET
        RECOVERY SIMPLE,
        AUTO_CREATE_STATISTICS ON,
        AUTO_UPDATE_STATISTICS ON,
        AUTO_UPDATE_STATISTICS_ASYNC ON;
END;
GO

USE DarlingData;
GO

/*
Create schemas for organization
*/
IF NOT EXISTS (SELECT 1/0 FROM sys.schemas WHERE name = N'collection')
    EXEC(N'CREATE SCHEMA collection;');
    
IF NOT EXISTS (SELECT 1/0 FROM sys.schemas WHERE name = N'analysis')
    EXEC(N'CREATE SCHEMA analysis;');
    
IF NOT EXISTS (SELECT 1/0 FROM sys.schemas WHERE name = N'system')
    EXEC(N'CREATE SCHEMA system;');
    
IF NOT EXISTS (SELECT 1/0 FROM sys.schemas WHERE name = N'maintenance')
    EXEC(N'CREATE SCHEMA maintenance;');
    
IF NOT EXISTS (SELECT 1/0 FROM sys.schemas WHERE name = N'reporting')
    EXEC(N'CREATE SCHEMA reporting;');
GO
```

## System Tables

```sql
/*
System metadata tables
*/

-- Server information (for current server only)
CREATE TABLE
    system.server_info
(
    collection_id bigint IDENTITY(1,1) NOT NULL,
    collection_time datetime2(7) NOT NULL,
    server_name sysname NOT NULL,
    instance_name sysname NULL,
    machine_name sysname NOT NULL,
    server_version varchar(128) NOT NULL,
    edition varchar(128) NOT NULL,
    product_level varchar(128) NOT NULL,
    engine_edition integer NOT NULL,
    sql_start_time datetime2(7) NOT NULL,
    total_physical_memory_kb bigint NOT NULL,
    available_physical_memory_kb bigint NOT NULL,
    cpu_count integer NOT NULL,
    hyperthread_ratio integer NOT NULL,
    PRIMARY KEY (collection_id)
);

-- Collection job status and configuration
CREATE TABLE
    system.collection_jobs
(
    job_id integer IDENTITY(1,1) NOT NULL,
    job_name varchar(100) NOT NULL,
    collection_type varchar(20) NOT NULL, -- all, waits, memory, cpu, io, blocking
    collection_frequency_minutes integer NOT NULL,
    is_enabled bit NOT NULL DEFAULT (1),
    last_run_time datetime2(7) NULL,
    next_run_time datetime2(7) NULL,
    last_run_status varchar(20) NULL, -- success, failed, running
    last_run_duration_seconds integer NULL,
    created_date datetime2(7) NOT NULL DEFAULT (SYSDATETIME()),
    created_by sysname NOT NULL DEFAULT (SUSER_SNAME()),
    modified_date datetime2(7) NOT NULL DEFAULT (SYSDATETIME()),
    modified_by sysname NOT NULL DEFAULT (SUSER_SNAME()),
    PRIMARY KEY (job_id),
    UNIQUE (job_name)
);

-- Collection types and configurations
CREATE TABLE
    system.collection_types
(
    collection_type_id integer IDENTITY(1,1) NOT NULL,
    collection_type varchar(20) NOT NULL, -- all, waits, memory, cpu, io, blocking
    description varchar(200) NOT NULL,
    default_frequency_minutes integer NOT NULL,
    is_enabled bit NOT NULL DEFAULT (1),
    retention_days integer NOT NULL DEFAULT (30),
    created_date datetime2(7) NOT NULL DEFAULT (SYSDATETIME()),
    modified_date datetime2(7) NOT NULL DEFAULT (SYSDATETIME()),
    PRIMARY KEY (collection_type_id),
    UNIQUE (collection_type)
);

-- Global system settings
CREATE TABLE
    system.settings
(
    setting_name varchar(100) NOT NULL,
    setting_value varchar(max) NOT NULL,
    description varchar(1000) NOT NULL,
    is_encrypted bit NOT NULL DEFAULT (0),
    created_date datetime2(7) NOT NULL DEFAULT (SYSDATETIME()),
    created_by sysname NOT NULL DEFAULT (SUSER_SNAME()),
    modified_date datetime2(7) NOT NULL DEFAULT (SYSDATETIME()),
    modified_by sysname NOT NULL DEFAULT (SUSER_SNAME()),
    PRIMARY KEY (setting_name)
);

-- Component versions and update history
CREATE TABLE
    system.version_history
(
    version_id integer IDENTITY(1,1) NOT NULL,
    component_name varchar(100) NOT NULL,
    version varchar(20) NOT NULL,
    version_date datetime2(7) NOT NULL,
    updated_date datetime2(7) NOT NULL DEFAULT (SYSDATETIME()),
    updated_by sysname NOT NULL DEFAULT (SUSER_SNAME()),
    update_notes nvarchar(max) NULL,
    PRIMARY KEY (version_id)
);

-- DMV coverage tracking
CREATE TABLE
    system.dmv_coverage
(
    dmv_name nvarchar(128) NOT NULL,
    category varchar(50) NOT NULL,
    collection_procedure sysname NULL,
    is_implemented bit NOT NULL DEFAULT (0),
    on_prem_supported bit NOT NULL DEFAULT (1),
    azure_db_supported bit NOT NULL DEFAULT (0),
    azure_mi_supported bit NOT NULL DEFAULT (0),
    aws_rds_supported bit NOT NULL DEFAULT (1),
    minimum_version varchar(20) NULL,
    notes nvarchar(1000) NULL,
    create_date datetime2(7) NOT NULL DEFAULT (SYSDATETIME()),
    last_updated datetime2(7) NOT NULL DEFAULT (SYSDATETIME()),
    PRIMARY KEY (dmv_name)
);

-- Collection errors
CREATE TABLE
    system.collection_errors
(
    error_id bigint IDENTITY(1,1) NOT NULL,
    collection_time datetime2(7) NOT NULL,
    collection_type varchar(50) NOT NULL,
    error_message nvarchar(4000) NOT NULL,
    error_number integer NULL,
    error_line integer NULL,
    PRIMARY KEY (error_id)
);
```

## Collection Tables - Wait Statistics

```sql
/*
Wait statistics collection
*/

-- Raw wait stats collection
CREATE TABLE
    collection.wait_stats
(
    collection_id bigint IDENTITY(1,1) NOT NULL,
    collection_time datetime2(7) NOT NULL,
    server_uptime_seconds bigint NOT NULL,
    wait_type nvarchar(60) NOT NULL,
    waiting_tasks_count bigint NOT NULL,
    wait_time_ms bigint NOT NULL,
    max_wait_time_ms bigint NOT NULL,
    signal_wait_time_ms bigint NOT NULL,
    PRIMARY KEY (collection_id),
    UNIQUE (collection_time, wait_type)
);

-- Wait stats with calculated deltas
CREATE TABLE
    collection.wait_stats_delta
(
    delta_id bigint IDENTITY(1,1) NOT NULL,
    collection_time datetime2(7) NOT NULL,
    wait_type nvarchar(60) NOT NULL,
    interval_seconds integer NOT NULL,
    waiting_tasks_count_delta bigint NOT NULL,
    wait_time_ms_delta bigint NOT NULL,
    signal_wait_time_ms_delta bigint NOT NULL,
    wait_time_ms_per_second decimal(18,2) NOT NULL,
    signal_wait_time_ms_per_second decimal(18,2) NOT NULL,
    PRIMARY KEY (delta_id),
    UNIQUE (collection_time, wait_type)
);

-- Categorized wait stats (for analysis)
CREATE TABLE
    analysis.wait_categories
(
    wait_type nvarchar(60) NOT NULL,
    wait_category varchar(30) NOT NULL, -- CPU, IO, Lock, Memory, Network, etc.
    is_ignorable bit NOT NULL DEFAULT (0),
    notes varchar(1000) NULL,
    PRIMARY KEY (wait_type)
);
```

## Collection Tables - Memory

```sql
/*
Memory metrics collection
*/

-- Memory clerks detail
CREATE TABLE
    collection.memory_clerks
(
    collection_id bigint IDENTITY(1,1) NOT NULL,
    collection_time datetime2(7) NOT NULL,
    clerk_type nvarchar(60) NOT NULL,
    memory_node_id smallint NOT NULL,
    single_pages_kb bigint NOT NULL,
    multi_pages_kb bigint NOT NULL,
    virtual_memory_reserved_kb bigint NOT NULL,
    virtual_memory_committed_kb bigint NOT NULL,
    awe_allocated_kb bigint NOT NULL,
    shared_memory_reserved_kb bigint NOT NULL,
    shared_memory_committed_kb bigint NOT NULL,
    PRIMARY KEY (collection_id),
    UNIQUE (collection_time, clerk_type, memory_node_id)
);

-- Memory usage summary
CREATE TABLE
    collection.memory_summary
(
    collection_id bigint IDENTITY(1,1) NOT NULL,
    collection_time datetime2(7) NOT NULL,
    total_physical_memory_kb bigint NOT NULL,
    available_physical_memory_kb bigint NOT NULL,
    total_page_file_kb bigint NOT NULL,
    available_page_file_kb bigint NOT NULL,
    system_cache_kb bigint NOT NULL,
    system_memory_state varchar(50) NOT NULL, -- Normal, Low, etc.
    page_life_expectancy integer NULL,
    buffer_cache_hit_ratio decimal(5,2) NULL,
    buffer_pool_size_kb bigint NULL,
    buffer_pool_used_kb bigint NULL,
    plan_cache_size_kb bigint NULL,
    PRIMARY KEY (collection_id)
);
```

## Collection Tables - CPU

```sql
/*
CPU metrics collection
*/

-- Scheduler statistics
CREATE TABLE
    collection.schedulers
(
    collection_id bigint IDENTITY(1,1) NOT NULL,
    collection_time datetime2(7) NOT NULL,
    scheduler_id integer NOT NULL,
    cpu_id integer NOT NULL,
    status nvarchar(60) NOT NULL,
    is_online bit NOT NULL,
    is_idle bit NOT NULL,
    current_tasks_count integer NOT NULL,
    runnable_tasks_count integer NOT NULL,
    current_workers_count integer NOT NULL,
    active_workers_count integer NOT NULL,
    work_queue_count integer NOT NULL,
    pending_disk_io_count integer NOT NULL,
    load_factor integer NOT NULL,
    yield_count bigint NOT NULL,
    last_timer_activity bigint NOT NULL,
    failed_to_create_worker bit NOT NULL,
    active_scheduler_count integer NOT NULL,
    PRIMARY KEY (collection_id),
    UNIQUE (collection_time, scheduler_id)
);

-- CPU usage counters
CREATE TABLE
    collection.cpu_usage
(
    collection_id bigint IDENTITY(1,1) NOT NULL,
    collection_time datetime2(7) NOT NULL,
    sql_cpu_utilization_pct decimal(5,2) NOT NULL,
    system_cpu_utilization_pct decimal(5,2) NOT NULL,
    idle_cpu_utilization_pct decimal(5,2) NOT NULL,
    other_cpu_utilization_pct decimal(5,2) NOT NULL,
    signal_waits_pct decimal(5,2) NULL,
    compiles_sec integer NULL,
    recompiles_sec integer NULL,
    batch_requests_sec integer NULL,
    PRIMARY KEY (collection_id)
);
```

## Collection Tables - I/O

```sql
/*
I/O metrics collection
*/

-- File statistics
CREATE TABLE
    collection.io_file_stats
(
    collection_id bigint IDENTITY(1,1) NOT NULL,
    collection_time datetime2(7) NOT NULL,
    database_id integer NOT NULL,
    database_name sysname NOT NULL,
    file_id integer NOT NULL,
    file_name sysname NOT NULL,
    file_type varchar(10) NOT NULL, -- data, log
    file_size_mb decimal(18,2) NOT NULL,
    file_used_mb decimal(18,2) NOT NULL,
    io_stall_read_ms bigint NOT NULL,
    io_stall_write_ms bigint NOT NULL,
    num_of_reads bigint NOT NULL,
    num_of_writes bigint NOT NULL,
    num_of_bytes_read bigint NOT NULL,
    num_of_bytes_written bigint NOT NULL,
    io_stall_queued_read_ms bigint NULL,
    io_stall_queued_write_ms bigint NULL,
    PRIMARY KEY (collection_id),
    UNIQUE (collection_time, database_id, file_id)
);

-- I/O stats with calculated deltas
CREATE TABLE
    collection.io_file_stats_delta
(
    delta_id bigint IDENTITY(1,1) NOT NULL,
    collection_time datetime2(7) NOT NULL,
    database_id integer NOT NULL,
    database_name sysname NOT NULL,
    file_id integer NOT NULL,
    file_name sysname NOT NULL,
    file_type varchar(10) NOT NULL, -- data, log
    interval_seconds integer NOT NULL,
    io_stall_read_ms_delta bigint NOT NULL,
    io_stall_write_ms_delta bigint NOT NULL,
    num_of_reads_delta bigint NOT NULL,
    num_of_writes_delta bigint NOT NULL,
    bytes_read_delta bigint NOT NULL,
    bytes_written_delta bigint NOT NULL,
    avg_read_latency_ms decimal(10,2) NULL,
    avg_write_latency_ms decimal(10,2) NULL,
    PRIMARY KEY (delta_id),
    UNIQUE (collection_time, database_id, file_id)
);
```

## Collection Tables - Query Performance

```sql
/*
Query performance collection
*/

-- Query stats
CREATE TABLE
    collection.query_stats
(
    collection_id bigint IDENTITY(1,1) NOT NULL,
    collection_time datetime2(7) NOT NULL,
    sql_handle varbinary(64) NOT NULL,
    statement_start_offset integer NOT NULL,
    statement_end_offset integer NOT NULL,
    plan_handle varbinary(64) NOT NULL,
    query_hash binary(8) NULL,
    query_plan_hash binary(8) NULL,
    execution_count bigint NOT NULL,
    total_worker_time bigint NOT NULL,
    total_physical_reads bigint NOT NULL,
    total_logical_reads bigint NOT NULL,
    total_logical_writes bigint NOT NULL,
    total_elapsed_time bigint NOT NULL,
    total_rows bigint NOT NULL,
    total_spills bigint NULL,
    total_used_memory bigint NULL,
    total_used_threads bigint NULL,
    total_grant_kb bigint NULL,
    last_execution_time datetime2(7) NULL,
    min_worker_time bigint NULL,
    max_worker_time bigint NULL,
    min_elapsed_time bigint NULL,
    max_elapsed_time bigint NULL,
    plan_generation_num bigint NULL,
    PRIMARY KEY (collection_id),
    UNIQUE (collection_time, sql_handle, statement_start_offset, statement_end_offset, plan_handle)
);

-- Query texts (normalized)
CREATE TABLE
    collection.query_texts
(
    query_text_id bigint IDENTITY(1,1) NOT NULL,
    sql_handle varbinary(64) NOT NULL,
    statement_start_offset integer NOT NULL,
    statement_end_offset integer NOT NULL,
    query_hash binary(8) NULL,
    database_id integer NULL,
    object_id integer NULL,
    statement_text nvarchar(max) NULL,
    normalized_text nvarchar(max) NULL,
    parameterized_text nvarchar(max) NULL,
    is_procedure bit NULL,
    is_trigger bit NULL,
    PRIMARY KEY (query_text_id),
    UNIQUE (sql_handle, statement_start_offset, statement_end_offset)
);

-- Query plans
CREATE TABLE
    collection.query_plans
(
    query_plan_id bigint IDENTITY(1,1) NOT NULL,
    plan_handle varbinary(64) NOT NULL,
    query_plan_hash binary(8) NULL,
    query_plan xml NULL,
    is_forced_plan bit NULL,
    is_parallel_plan bit NULL,
    is_trivial_plan bit NULL,
    first_observed_time datetime2(7) NOT NULL DEFAULT (SYSDATETIME()),
    last_observed_time datetime2(7) NOT NULL DEFAULT (SYSDATETIME()),
    PRIMARY KEY (query_plan_id),
    UNIQUE (plan_handle)
);
```

## System Views

```sql
/*
Important system views
*/

-- Wait stats trend
CREATE VIEW
    reporting.vw_wait_stats_trend
AS
SELECT
    collection_time,
    wait_category,
    SUM(wait_time_ms_per_second) AS wait_time_ms_per_second,
    SUM(signal_wait_time_ms_per_second) AS signal_wait_time_ms_per_second,
    SUM(waiting_tasks_count_delta) AS waiting_tasks_count_delta
FROM collection.wait_stats_delta AS wsd
JOIN analysis.wait_categories AS wc
  ON wsd.wait_type = wc.wait_type
WHERE wc.is_ignorable = 0
GROUP BY
    collection_time,
    wait_category;
GO

-- Memory pressure indicators
CREATE VIEW
    reporting.vw_memory_pressure_indicators
AS
SELECT
    collection_time,
    total_physical_memory_kb / 1024 AS total_physical_memory_mb,
    available_physical_memory_kb / 1024 AS available_physical_memory_mb,
    (total_physical_memory_kb - available_physical_memory_kb) * 100.0 / 
        NULLIF(total_physical_memory_kb, 0) AS memory_utilization_pct,
    page_life_expectancy,
    buffer_cache_hit_ratio,
    buffer_pool_size_kb / 1024 AS buffer_pool_size_mb,
    buffer_pool_used_kb / 1024 AS buffer_pool_used_mb
FROM collection.memory_summary;
GO

-- I/O performance
CREATE VIEW
    reporting.vw_io_performance
AS
SELECT
    collection_time,
    database_name,
    file_name,
    file_type,
    file_size_mb,
    file_used_mb,
    avg_read_latency_ms,
    avg_write_latency_ms,
    num_of_reads_delta / interval_seconds AS reads_per_second,
    num_of_writes_delta / interval_seconds AS writes_per_second,
    bytes_read_delta / (1024 * 1024) / interval_seconds AS read_mb_per_second,
    bytes_written_delta / (1024 * 1024) / interval_seconds AS write_mb_per_second
FROM collection.io_file_stats_delta;
GO
```

## Maintenance Procedures

```sql
-- Data retention procedure
CREATE OR ALTER PROCEDURE
    maintenance.sp_purge_old_data
(
    @retention_days integer = 30, /*Days of data to keep*/
    @debug bit = 0 /*Print operations instead of executing them*/
)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE
        @collection_tables TABLE 
        (
            table_name sysname
        );
        
    INSERT @collection_tables (table_name)
    VALUES
        ('collection.wait_stats'),
        ('collection.wait_stats_delta'),
        ('collection.memory_clerks'),
        ('collection.memory_summary'),
        -- Add all other collection tables
        ('collection.io_file_stats'),
        ('collection.io_file_stats_delta');
    
    DECLARE
        @sql nvarchar(max),
        @table_name sysname,
        @cutoff_date datetime2(7) = DATEADD(DAY, -@retention_days, SYSDATETIME());
    
    DECLARE tables_cursor CURSOR LOCAL FAST_FORWARD
    FOR
        SELECT table_name
        FROM @collection_tables;
    
    OPEN tables_cursor;
    
    FETCH NEXT FROM tables_cursor INTO @table_name;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @sql = N'
        DELETE FROM ' + @table_name + '
        WHERE collection_time < @cutoff_date;';
        
        IF @debug = 1
        BEGIN
            PRINT @sql;
        END
        ELSE
        BEGIN
            EXECUTE sp_executesql 
                @sql, 
                N'@cutoff_date datetime2(7)', 
                @cutoff_date;
                
            PRINT 'Deleted from ' + @table_name + ': ' + CAST(@@ROWCOUNT AS varchar(20)) + ' rows';
        END
        
        FETCH NEXT FROM tables_cursor INTO @table_name;
    END
    
    CLOSE tables_cursor;
    DEALLOCATE tables_cursor;
END;
GO
```