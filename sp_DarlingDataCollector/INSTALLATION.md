# DarlingDataCollector Installation Guide

This document outlines the installation process for the DarlingDataCollector solution. The collector supports dynamic table creation through a centralized system procedure.

## Supported Environments

DarlingDataCollector supports the following SQL Server environments:

- On-premises SQL Server
- Azure SQL Managed Instance
- Amazon RDS for SQL Server

> **Note**: Azure SQL Database is **not** supported due to its limitations with SQL Agent and other system-level features required by this solution.

## Installation Options

### Option 1: Using the SQLCMD Installer (Recommended)

The simplest way to install DarlingDataCollector is to use the SQLCMD-mode installer:

1. Open a command prompt with administrative privileges
2. Navigate to the DarlingDataCollector directory
3. Run the following command:

```
sqlcmd -S [server_name] -i .\install-darling-data-collector.sql -v TargetDB = "[database_name]"
```

Replace `[server_name]` with your SQL Server instance name and `[database_name]` with the name of the database where you want to install the collector (create it first if it doesn't exist).

This installer will:
- Create all required schemas (collection, system, analysis)
- Create system tables for logging and configuration
- Create the table creator procedure for dynamic table creation
- Install all collector procedures
- Create SQL Agent jobs for scheduling collections (except on Azure SQL Database)

## Installation Script

```sql
/*
██████╗  █████╗ ██████╗ ██╗     ██╗███╗   ██╗ ██████╗ ██████╗  █████╗ ████████╗ █████╗  ██████╗ ██████╗ ██╗     ██╗     ███████╗ ██████╗████████╗ ██████╗ ██████╗ 
██╔══██╗██╔══██╗██╔══██╗██║     ██║████╗  ██║██╔════╝ ██╔══██╗██╔══██╗╚══██╔══╝██╔══██╗██╔════╝ ██╔══██╗██║     ██║     ██╔════╝██╔════╝╚══██╔══╝██╔═══██╗██╔══██╗
██║  ██║███████║██████╔╝██║     ██║██╔██╗ ██║██║  ███╗██║  ██║███████║   ██║   ███████║██║      ██║  ██║██║     ██║     █████╗  ██║        ██║   ██║   ██║██████╔╝
██║  ██║██╔══██║██╔══██╗██║     ██║██║╚██╗██║██║   ██║██║  ██║██╔══██║   ██║   ██╔══██║██║      ██║  ██║██║     ██║     ██╔══╝  ██║        ██║   ██║   ██║██╔══██╗
██████╔╝██║  ██║██║  ██║███████╗██║██║ ╚████║╚██████╔╝██████╔╝██║  ██║   ██║   ██║  ██║╚██████╗ ██████╔╝███████╗███████╗███████╗╚██████╗   ██║   ╚██████╔╝██║  ██║
╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚══════╝╚══════╝╚══════╝ ╚═════╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝
                                                                                                                                                                   
Copyright (c) Darling Data, LLC
https://www.erikdarling.com/
*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/*
Create the repository database
*/
IF DB_ID('DarlingData') IS NULL
BEGIN
    CREATE DATABASE
        DarlingData;
END;
GO

USE DarlingData;
GO

/*
Create database schemas
*/
IF SCHEMA_ID('collection') IS NULL
BEGIN
    EXECUTE ('CREATE SCHEMA collection;');
END;
GO

IF SCHEMA_ID('analysis') IS NULL
BEGIN
    EXECUTE ('CREATE SCHEMA analysis;');
END;
GO

IF SCHEMA_ID('system') IS NULL
BEGIN
    EXECUTE ('CREATE SCHEMA system;');
END;
GO

IF SCHEMA_ID('maintenance') IS NULL
BEGIN
    EXECUTE ('CREATE SCHEMA maintenance;');
END;
GO

IF SCHEMA_ID('reporting') IS NULL
BEGIN
    EXECUTE ('CREATE SCHEMA reporting;');
END;
GO

/*
Create configuration table for global settings
*/
CREATE TABLE
    system.configuration
(
    config_id INTEGER IDENTITY(1,1) NOT NULL,
    config_name NVARCHAR(100) NOT NULL,
    config_value NVARCHAR(4000) NOT NULL,
    config_description NVARCHAR(4000) NULL,
    created_date DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
    modified_date DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT pk_configuration PRIMARY KEY CLUSTERED (config_id),
    CONSTRAINT uq_configuration_name UNIQUE (config_name)
);
GO

/*
Create DMV coverage tracking table
*/
CREATE TABLE
    system.dmv_coverage
(
    dmv_id INTEGER IDENTITY(1,1) NOT NULL,
    dmv_name NVARCHAR(400) NOT NULL,
    dmv_category NVARCHAR(100) NOT NULL,
    is_implemented BIT NOT NULL DEFAULT 0,
    collection_procedure NVARCHAR(400) NULL,
    analysis_procedure NVARCHAR(400) NULL,
    description NVARCHAR(4000) NULL,
    minimum_compatibility_level INTEGER NULL,
    supported_editions NVARCHAR(1000) NULL,
    created_date DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
    modified_date DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT pk_dmv_coverage PRIMARY KEY CLUSTERED (dmv_id),
    CONSTRAINT uq_dmv_coverage_name UNIQUE (dmv_name)
);
GO

/*
Create collection log table
*/
CREATE TABLE
    system.collection_log
(
    log_id BIGINT IDENTITY(1,1) NOT NULL,
    procedure_name NVARCHAR(400) NOT NULL,
    collection_start DATETIME2(7) NOT NULL,
    collection_end DATETIME2(7) NOT NULL,
    rows_collected BIGINT NOT NULL,
    status NVARCHAR(100) NOT NULL,
    error_number INTEGER NULL,
    error_message NVARCHAR(4000) NULL,
    CONSTRAINT pk_collection_log PRIMARY KEY CLUSTERED (log_id)
);
GO

/*
Create server information table
*/
CREATE TABLE
    system.server_info
(
    server_id INTEGER IDENTITY(1,1) NOT NULL,
    collection_time DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
    server_name NVARCHAR(128) NOT NULL,
    product_version NVARCHAR(128) NOT NULL,
    edition NVARCHAR(128) NOT NULL,
    platform NVARCHAR(50) NOT NULL, /* OnPrem, Azure, AWS */
    instance_type NVARCHAR(50) NOT NULL, /* Regular, AzureDB, AzureMI, AWSRDS */
    compatibility_level INTEGER NOT NULL,
    product_level NVARCHAR(128) NOT NULL,
    product_update_level NVARCHAR(128) NULL,
    physical_memory_mb BIGINT NULL,
    cpu_count INTEGER NOT NULL,
    scheduler_count INTEGER NOT NULL,
    CONSTRAINT pk_server_info PRIMARY KEY CLUSTERED (server_id)
);
GO

/*
Create wait stats table
*/
CREATE TABLE
    collection.wait_stats
(
    collection_id BIGINT IDENTITY(1,1) NOT NULL,
    collection_time DATETIME2(7) NOT NULL,
    server_uptime_seconds BIGINT NOT NULL,
    wait_type NVARCHAR(128) NOT NULL,
    waiting_tasks_count BIGINT NOT NULL,
    wait_time_ms BIGINT NOT NULL,
    max_wait_time_ms BIGINT NOT NULL,
    signal_wait_time_ms BIGINT NOT NULL,
    waiting_tasks_count_delta BIGINT NULL,
    wait_time_ms_delta BIGINT NULL,
    max_wait_time_ms_delta BIGINT NULL,
    signal_wait_time_ms_delta BIGINT NULL,
    sample_seconds INTEGER NULL,
    CONSTRAINT pk_wait_stats PRIMARY KEY CLUSTERED (collection_id, wait_type)
);
GO

/*
Create memory stats table
*/
CREATE TABLE
    collection.memory_clerks
(
    collection_id BIGINT IDENTITY(1,1) NOT NULL,
    collection_time DATETIME2(7) NOT NULL,
    clerk_name NVARCHAR(128) NOT NULL,
    memory_node_id INTEGER NOT NULL,
    pages_kb BIGINT NOT NULL,
    virtual_memory_reserved_kb BIGINT NOT NULL,
    virtual_memory_committed_kb BIGINT NOT NULL,
    awe_allocated_kb BIGINT NOT NULL,
    shared_memory_reserved_kb BIGINT NOT NULL,
    shared_memory_committed_kb BIGINT NOT NULL,
    CONSTRAINT pk_memory_clerks PRIMARY KEY CLUSTERED (collection_id, clerk_name, memory_node_id)
);
GO

/*
Create buffer pool table
*/
CREATE TABLE
    collection.buffer_pool
(
    collection_id BIGINT IDENTITY(1,1) NOT NULL,
    collection_time DATETIME2(7) NOT NULL,
    database_id INTEGER NOT NULL,
    database_name NVARCHAR(128) NULL,
    file_id INTEGER NOT NULL,
    file_type NVARCHAR(60) NULL,
    page_count BIGINT NOT NULL,
    cached_size_mb DECIMAL(19,2) NOT NULL,
    CONSTRAINT pk_buffer_pool PRIMARY KEY CLUSTERED (collection_id, database_id, file_id)
);
GO

/*
Create I/O stats table
*/
CREATE TABLE
    collection.io_stats
(
    collection_id BIGINT IDENTITY(1,1) NOT NULL,
    collection_time DATETIME2(7) NOT NULL,
    database_id INTEGER NOT NULL,
    database_name NVARCHAR(128) NULL,
    file_id INTEGER NOT NULL,
    file_name NVARCHAR(260) NULL,
    type_desc NVARCHAR(60) NULL,
    io_stall_read_ms BIGINT NOT NULL,
    io_stall_write_ms BIGINT NOT NULL,
    io_stall BIGINT NOT NULL,
    num_of_reads BIGINT NOT NULL,
    num_of_writes BIGINT NOT NULL,
    num_of_bytes_read BIGINT NOT NULL,
    num_of_bytes_written BIGINT NOT NULL,
    io_stall_read_ms_delta BIGINT NULL,
    io_stall_write_ms_delta BIGINT NULL,
    io_stall_delta BIGINT NULL,
    num_of_reads_delta BIGINT NULL,
    num_of_writes_delta BIGINT NULL,
    num_of_bytes_read_delta BIGINT NULL,
    num_of_bytes_written_delta BIGINT NULL,
    sample_seconds INTEGER NULL,
    CONSTRAINT pk_io_stats PRIMARY KEY CLUSTERED (collection_id, database_id, file_id)
);
GO

/*
Create index usage stats table
*/
CREATE TABLE
    collection.index_usage_stats
(
    collection_id BIGINT IDENTITY(1,1) NOT NULL,
    collection_time DATETIME2(7) NOT NULL,
    database_id INTEGER NOT NULL,
    database_name NVARCHAR(128) NULL,
    object_id INTEGER NOT NULL,
    schema_name NVARCHAR(128) NULL,
    object_name NVARCHAR(128) NULL,
    index_id INTEGER NOT NULL,
    index_name NVARCHAR(128) NULL,
    user_seeks BIGINT NOT NULL,
    user_scans BIGINT NOT NULL,
    user_lookups BIGINT NOT NULL,
    user_updates BIGINT NOT NULL,
    last_user_seek DATETIME2(7) NULL,
    last_user_scan DATETIME2(7) NULL,
    last_user_lookup DATETIME2(7) NULL,
    last_user_update DATETIME2(7) NULL,
    user_seeks_delta BIGINT NULL,
    user_scans_delta BIGINT NULL,
    user_lookups_delta BIGINT NULL,
    user_updates_delta BIGINT NULL,
    sample_seconds INTEGER NULL,
    CONSTRAINT pk_index_usage_stats PRIMARY KEY CLUSTERED (collection_id, database_id, object_id, index_id)
);
GO

/*
Create query stats table
*/
CREATE TABLE
    collection.query_stats
(
    collection_id BIGINT IDENTITY(1,1) NOT NULL,
    collection_time DATETIME2(7) NOT NULL,
    sql_handle VARBINARY(64) NOT NULL,
    plan_handle VARBINARY(64) NOT NULL,
    query_hash BINARY(8) NULL,
    query_plan_hash BINARY(8) NULL,
    statement_start_offset INTEGER NOT NULL,
    statement_end_offset INTEGER NOT NULL,
    execution_count BIGINT NOT NULL,
    total_worker_time BIGINT NOT NULL,
    total_physical_reads BIGINT NOT NULL,
    total_logical_reads BIGINT NOT NULL,
    total_logical_writes BIGINT NOT NULL,
    total_elapsed_time BIGINT NOT NULL,
    total_spills BIGINT NULL,
    creation_time DATETIME NULL,
    last_execution_time DATETIME NULL,
    execution_count_delta BIGINT NULL,
    total_worker_time_delta BIGINT NULL,
    total_physical_reads_delta BIGINT NULL,
    total_logical_reads_delta BIGINT NULL,
    total_logical_writes_delta BIGINT NULL,
    total_elapsed_time_delta BIGINT NULL,
    total_spills_delta BIGINT NULL,
    sample_seconds INTEGER NULL,
    query_text NVARCHAR(MAX) NULL,
    query_plan XML NULL,
    CONSTRAINT pk_query_stats PRIMARY KEY CLUSTERED (collection_id, sql_handle, plan_handle, statement_start_offset, statement_end_offset)
);
GO

/*
Create connections table
*/
CREATE TABLE
    collection.connections
(
    collection_id BIGINT IDENTITY(1,1) NOT NULL,
    collection_time DATETIME2(7) NOT NULL,
    session_id INTEGER NOT NULL,
    login_name NVARCHAR(128) NOT NULL,
    host_name NVARCHAR(128) NULL,
    program_name NVARCHAR(128) NULL,
    client_interface_name NVARCHAR(32) NULL,
    login_time DATETIME2 NOT NULL,
    status NVARCHAR(30) NOT NULL,
    cpu_time BIGINT NOT NULL,
    memory_usage BIGINT NOT NULL,
    total_elapsed_time BIGINT NOT NULL,
    last_request_start_time DATETIME2 NULL,
    last_request_end_time DATETIME2 NULL,
    reads BIGINT NOT NULL,
    writes BIGINT NOT NULL,
    logical_reads BIGINT NOT NULL,
    transaction_isolation_level INTEGER NOT NULL,
    lock_timeout INTEGER NOT NULL,
    deadlock_priority INTEGER NOT NULL,
    row_count BIGINT NOT NULL,
    is_user_process BIT NOT NULL,
    CONSTRAINT pk_connections PRIMARY KEY CLUSTERED (collection_id, session_id)
);
GO

/*
Create blocking table
*/
CREATE TABLE
    collection.blocking
(
    collection_id BIGINT IDENTITY(1,1) NOT NULL,
    collection_time DATETIME2(7) NOT NULL,
    blocked_session_id INTEGER NOT NULL,
    blocking_session_id INTEGER NOT NULL,
    blocking_tree NVARCHAR(MAX) NULL,
    blocked_sql_text NVARCHAR(MAX) NULL,
    blocking_sql_text NVARCHAR(MAX) NULL,
    wait_type NVARCHAR(60) NULL,
    wait_duration_ms BIGINT NULL,
    wait_resource NVARCHAR(256) NULL,
    resource_description NVARCHAR(512) NULL,
    transaction_name NVARCHAR(32) NULL,
    transaction_isolation_level NVARCHAR(32) NULL,
    lock_mode NVARCHAR(5) NULL,
    status NVARCHAR(60) NULL,
    blocked_login_name NVARCHAR(128) NULL,
    blocked_host_name NVARCHAR(128) NULL,
    blocked_program_name NVARCHAR(128) NULL,
    blocking_login_name NVARCHAR(128) NULL,
    blocking_host_name NVARCHAR(128) NULL,
    blocking_program_name NVARCHAR(128) NULL,
    CONSTRAINT pk_blocking PRIMARY KEY CLUSTERED (collection_id, blocked_session_id, blocking_session_id)
);
GO

/*
Create collected DMV lists for environment detection
*/
INSERT
    system.dmv_coverage
(
    dmv_name,
    dmv_category,
    is_implemented,
    collection_procedure,
    description,
    minimum_compatibility_level,
    supported_editions
)
VALUES
    ('sys.dm_os_wait_stats', 'Wait Statistics', 1, 'collection.collect_wait_stats', 'Provides information about all the waits encountered by threads executing in SQL Server', 90, 'All'),
    ('sys.dm_os_memory_clerks', 'Memory', 1, 'collection.collect_memory_clerks', 'Returns memory clerks that are used by SQL Server to allocate memory', 90, 'All'),
    ('sys.dm_os_buffer_descriptors', 'Memory', 1, 'collection.collect_buffer_pool', 'Returns information about all the data pages that are currently in the SQL Server buffer pool', 90, 'All'),
    ('sys.dm_io_virtual_file_stats', 'I/O', 1, 'collection.collect_io_stats', 'Returns I/O statistics for data and log files', 90, 'All'),
    ('sys.dm_db_index_usage_stats', 'Indexes', 1, 'collection.collect_index_usage_stats', 'Returns counts of different types of index operations and the time each type of operation was last performed', 90, 'All'),
    ('sys.dm_exec_query_stats', 'Queries', 1, 'collection.collect_query_stats', 'Returns aggregate performance statistics for cached query plans', 90, 'All'),
    ('sys.dm_exec_sessions', 'Connections', 1, 'collection.collect_connections', 'Returns one row per authenticated session on SQL Server', 90, 'All'),
    ('sys.dm_exec_requests', 'Connections', 1, 'collection.collect_connections', 'Returns information about each request that is executing within SQL Server', 90, 'All'),
    ('sys.dm_tran_locks', 'Blocking', 1, 'collection.collect_blocking', 'Returns information about currently active lock manager resources', 90, 'All'),
    ('sys.dm_exec_sql_text', 'Queries', 1, NULL, 'Returns the text of the SQL batch that is identified by the specified sql_handle', 90, 'All'),
    ('sys.dm_exec_query_plan', 'Queries', 1, NULL, 'Returns the showplan in XML format for the batch specified by the plan handle', 90, 'All');
GO

/*
Create environment detection procedure
*/
CREATE OR ALTER PROCEDURE
    system.detect_environment
(
    @debug BIT = 0 /*Print debugging information*/
)
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
    
    DECLARE
        @platform NVARCHAR(50),
        @instance_type NVARCHAR(50),
        @product_version NVARCHAR(128),
        @edition NVARCHAR(128),
        @compatibility_level INTEGER,
        @product_level NVARCHAR(128),
        @product_update_level NVARCHAR(128),
        @physical_memory_mb BIGINT,
        @cpu_count INTEGER,
        @scheduler_count INTEGER,
        @is_supported BIT = 1,
        @unsupported_message NVARCHAR(512) = NULL;
    
    /*
    Get product information
    */
    SELECT
        @product_version = CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(128)),
        @edition = CAST(SERVERPROPERTY('Edition') AS NVARCHAR(128)),
        @compatibility_level = compatibility_level,
        @product_level = CAST(SERVERPROPERTY('ProductLevel') AS NVARCHAR(128)),
        @product_update_level = CAST(SERVERPROPERTY('ProductUpdateLevel') AS NVARCHAR(128))
    FROM sys.databases
    WHERE database_id = DB_ID();
    
    /*
    Determine platform and instance type
    */
    IF @edition LIKE '%Azure%'
    BEGIN
        SET @platform = 'Azure';
        
        IF @edition LIKE '%Database%'
        BEGIN
            SET @instance_type = 'AzureDB';
            SET @is_supported = 0;
            SET @unsupported_message = 'Azure SQL Database is not supported by DarlingDataCollector due to limitations with SQL Agent and other system-level features.';
        END;
        ELSE IF @edition LIKE '%Managed%'
        BEGIN
            SET @instance_type = 'AzureMI';
        END;
    END;
    ELSE IF EXISTS (SELECT 1 FROM sys.dm_os_host_info WHERE host_platform = 'Windows' AND host_distribution LIKE '%Amazon%')
    BEGIN
        SET @platform = 'AWS';
        SET @instance_type = 'AWSRDS';
    END;
    ELSE
    BEGIN
        SET @platform = 'OnPrem';
        SET @instance_type = 'Regular';
    END;
    
    /* 
    Check for unsupported environment and print message
    */
    IF @is_supported = 0
    BEGIN
        RAISERROR('ENVIRONMENT NOT SUPPORTED: %s', 16, 1, @unsupported_message);
        RETURN;
    END;
    
    /*
    Get system information
    */
    SELECT
        @cpu_count = cpu_count,
        @scheduler_count = scheduler_count
    FROM sys.dm_os_sys_info;
    
    /*
    Get physical memory if available
    */
    IF @instance_type IN ('Regular', 'AWSRDS')
    BEGIN
        SELECT
            @physical_memory_mb = physical_memory_kb / 1024
        FROM sys.dm_os_sys_info;
    END;
    
    /*
    Store or update server information
    */
    IF EXISTS (SELECT 1 FROM system.server_info)
    BEGIN
        UPDATE
            system.server_info
        SET
            collection_time = SYSDATETIME(),
            server_name = @@SERVERNAME,
            product_version = @product_version,
            edition = @edition,
            platform = @platform,
            instance_type = @instance_type,
            compatibility_level = @compatibility_level,
            product_level = @product_level,
            product_update_level = @product_update_level,
            physical_memory_mb = @physical_memory_mb,
            cpu_count = @cpu_count,
            scheduler_count = @scheduler_count;
    END;
    ELSE
    BEGIN
        INSERT
            system.server_info
        (
            collection_time,
            server_name,
            product_version,
            edition,
            platform,
            instance_type,
            compatibility_level,
            product_level, 
            product_update_level,
            physical_memory_mb,
            cpu_count,
            scheduler_count
        )
        VALUES
        (
            SYSDATETIME(),
            @@SERVERNAME,
            @product_version,
            @edition,
            @platform,
            @instance_type,
            @compatibility_level,
            @product_level,
            @product_update_level,
            @physical_memory_mb,
            @cpu_count,
            @scheduler_count
        );
    END;
    
    /*
    Print debugging information if requested
    */
    IF @debug = 1
    BEGIN
        SELECT
            server_name,
            product_version,
            edition,
            platform,
            instance_type,
            compatibility_level,
            product_level,
            product_update_level,
            physical_memory_mb,
            cpu_count,
            scheduler_count
        FROM system.server_info;
    END;
END;
GO

/*
Create wait stats collection procedure
*/
CREATE OR ALTER PROCEDURE
    collection.collect_wait_stats
(
    @debug BIT = 0, /*Print debugging information*/
    @sample_seconds INTEGER = NULL /*Optional: Collect sample over time period*/
)
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
    
    DECLARE
        @collection_start DATETIME2(7) = SYSDATETIME(),
        @collection_end DATETIME2(7),
        @rows_collected BIGINT = 0,
        @server_uptime_seconds BIGINT,
        @sql NVARCHAR(MAX) = N'',
        @error_number INTEGER,
        @error_message NVARCHAR(4000);
    
    BEGIN TRY
        /*
        Get SQL Server uptime in seconds
        */
        SELECT
            @server_uptime_seconds = DATEDIFF(SECOND, sqlserver_start_time, GETDATE())
        FROM sys.dm_os_sys_info;
        
        /*
        If sampling is requested, collect first sample
        */
        IF @sample_seconds IS NOT NULL
        BEGIN
            /*
            Create temporary table for collecting wait stats samples
            */
            CREATE TABLE
                #wait_stats_before
            (
                wait_type NVARCHAR(128) NOT NULL,
                waiting_tasks_count BIGINT NOT NULL,
                wait_time_ms BIGINT NOT NULL,
                max_wait_time_ms BIGINT NOT NULL,
                signal_wait_time_ms BIGINT NOT NULL,
                PRIMARY KEY (wait_type)
            );
            
            /*
            Collect first sample
            */
            INSERT
                #wait_stats_before
            (
                wait_type,
                waiting_tasks_count,
                wait_time_ms,
                max_wait_time_ms,
                signal_wait_time_ms
            )
            SELECT
                wait_type,
                waiting_tasks_count,
                wait_time_ms,
                max_wait_time_ms,
                signal_wait_time_ms
            FROM sys.dm_os_wait_stats
            WHERE wait_type NOT IN 
            (
                /* Filter out benign waits */
                N'BROKER_TASK_STOP',
                N'DIRTY_PAGE_POLL',
                N'CLR_AUTO_EVENT',
                N'CLR_MANUAL_EVENT',
                N'CLR_QUANTUM_TASK',
                N'REQUEST_FOR_DEADLOCK_SEARCH',
                N'SLEEP_TASK',
                N'SLEEP_SYSTEMTASK',
                N'SQLTRACE_BUFFER_FLUSH',
                N'WAITFOR',
                N'XE_DISPATCHER_WAIT',
                N'XE_TIMER_EVENT',
                N'LAZYWRITER_SLEEP',
                N'BROKER_EVENTHANDLER',
                N'BROKER_RECEIVE_WAITFOR',
                N'CHECKPOINT_QUEUE',
                N'CHKPT',
                N'HADR_FILESTREAM_IOMGR_IOCOMPLETION'
            );
            
            /*
            Wait for the specified sample period
            */
            WAITFOR DELAY CONVERT(CHAR(8), DATEADD(SECOND, @sample_seconds, 0), 114);
            
            /*
            Insert data with delta values
            */
            INSERT
                collection.wait_stats
            (
                collection_time,
                server_uptime_seconds,
                wait_type,
                waiting_tasks_count,
                wait_time_ms,
                max_wait_time_ms,
                signal_wait_time_ms,
                waiting_tasks_count_delta,
                wait_time_ms_delta,
                max_wait_time_ms_delta,
                signal_wait_time_ms_delta,
                sample_seconds
            )
            SELECT
                collection_time = SYSDATETIME(),
                server_uptime_seconds = @server_uptime_seconds,
                ws.wait_type,
                ws.waiting_tasks_count,
                ws.wait_time_ms,
                ws.max_wait_time_ms,
                ws.signal_wait_time_ms,
                waiting_tasks_count_delta = ws.waiting_tasks_count - wsb.waiting_tasks_count,
                wait_time_ms_delta = ws.wait_time_ms - wsb.wait_time_ms,
                max_wait_time_ms_delta = 
                    CASE 
                        WHEN ws.max_wait_time_ms > wsb.max_wait_time_ms 
                        THEN ws.max_wait_time_ms - wsb.max_wait_time_ms
                        ELSE 0
                    END,
                signal_wait_time_ms_delta = ws.signal_wait_time_ms - wsb.signal_wait_time_ms,
                sample_seconds = @sample_seconds
            FROM sys.dm_os_wait_stats AS ws
            JOIN #wait_stats_before AS wsb
              ON ws.wait_type = wsb.wait_type
            WHERE ws.wait_type NOT IN 
            (
                /* Filter out benign waits */
                N'BROKER_TASK_STOP',
                N'DIRTY_PAGE_POLL',
                N'CLR_AUTO_EVENT',
                N'CLR_MANUAL_EVENT',
                N'CLR_QUANTUM_TASK',
                N'REQUEST_FOR_DEADLOCK_SEARCH',
                N'SLEEP_TASK',
                N'SLEEP_SYSTEMTASK',
                N'SQLTRACE_BUFFER_FLUSH',
                N'WAITFOR',
                N'XE_DISPATCHER_WAIT',
                N'XE_TIMER_EVENT',
                N'LAZYWRITER_SLEEP',
                N'BROKER_EVENTHANDLER',
                N'BROKER_RECEIVE_WAITFOR',
                N'CHECKPOINT_QUEUE',
                N'CHKPT',
                N'HADR_FILESTREAM_IOMGR_IOCOMPLETION'
            );
        END;
        ELSE
        BEGIN
            /*
            Collect current wait stats without sampling
            */
            INSERT
                collection.wait_stats
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
                collection_time = SYSDATETIME(),
                server_uptime_seconds = @server_uptime_seconds,
                wait_type,
                waiting_tasks_count,
                wait_time_ms,
                max_wait_time_ms,
                signal_wait_time_ms
            FROM sys.dm_os_wait_stats
            WHERE wait_type NOT IN 
            (
                /* Filter out benign waits */
                N'BROKER_TASK_STOP',
                N'DIRTY_PAGE_POLL',
                N'CLR_AUTO_EVENT',
                N'CLR_MANUAL_EVENT',
                N'CLR_QUANTUM_TASK',
                N'REQUEST_FOR_DEADLOCK_SEARCH',
                N'SLEEP_TASK',
                N'SLEEP_SYSTEMTASK',
                N'SQLTRACE_BUFFER_FLUSH',
                N'WAITFOR',
                N'XE_DISPATCHER_WAIT',
                N'XE_TIMER_EVENT',
                N'LAZYWRITER_SLEEP',
                N'BROKER_EVENTHANDLER',
                N'BROKER_RECEIVE_WAITFOR',
                N'CHECKPOINT_QUEUE',
                N'CHKPT',
                N'HADR_FILESTREAM_IOMGR_IOCOMPLETION'
            );
        END;
        
        SET @rows_collected = @@ROWCOUNT;
        SET @collection_end = SYSDATETIME();
        
        /*
        Log collection results
        */
        INSERT
            system.collection_log
        (
            procedure_name,
            collection_start,
            collection_end,
            rows_collected,
            status
        )
        VALUES
        (
            'collection.collect_wait_stats',
            @collection_start,
            @collection_end,
            @rows_collected,
            'Success'
        );
        
        /*
        Print debug information
        */
        IF @debug = 1
        BEGIN
            SELECT
                N'Wait Stats Collected' AS collection_type,
                @rows_collected AS rows_collected,
                CAST(DATEDIFF(MILLISECOND, @collection_start, @collection_end) / 1000.0 AS DECIMAL(18,2)) AS duration_seconds;
        END;
    END TRY
    BEGIN CATCH
        SET @error_number = ERROR_NUMBER();
        SET @error_message = ERROR_MESSAGE();
        
        /*
        Log error
        */
        INSERT
            system.collection_log
        (
            procedure_name,
            collection_start,
            collection_end,
            rows_collected,
            status,
            error_number,
            error_message
        )
        VALUES
        (
            'collection.collect_wait_stats',
            @collection_start,
            SYSDATETIME(),
            0,
            'Error',
            @error_number,
            @error_message
        );
        
        /*
        Re-throw error
        */
        THROW;
    END CATCH;
END;
GO

/*
Create memory clerks collection procedure
*/
CREATE OR ALTER PROCEDURE
    collection.collect_memory_clerks
(
    @debug BIT = 0 /*Print debugging information*/
)
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
    
    DECLARE
        @collection_start DATETIME2(7) = SYSDATETIME(),
        @collection_end DATETIME2(7),
        @rows_collected BIGINT = 0,
        @error_number INTEGER,
        @error_message NVARCHAR(4000);
    
    BEGIN TRY
        /*
        Collect memory clerks information
        */
        INSERT
            collection.memory_clerks
        (
            collection_time,
            clerk_name,
            memory_node_id,
            pages_kb,
            virtual_memory_reserved_kb,
            virtual_memory_committed_kb,
            awe_allocated_kb,
            shared_memory_reserved_kb,
            shared_memory_committed_kb
        )
        SELECT
            collection_time = SYSDATETIME(),
            clerk_name = type,
            memory_node_id,
            pages_kb,
            virtual_memory_reserved_kb,
            virtual_memory_committed_kb,
            awe_allocated_kb,
            shared_memory_reserved_kb,
            shared_memory_committed_kb
        FROM sys.dm_os_memory_clerks
        WHERE pages_kb > 0
        OR virtual_memory_committed_kb > 0;
        
        SET @rows_collected = @@ROWCOUNT;
        SET @collection_end = SYSDATETIME();
        
        /*
        Log collection results
        */
        INSERT
            system.collection_log
        (
            procedure_name,
            collection_start,
            collection_end,
            rows_collected,
            status
        )
        VALUES
        (
            'collection.collect_memory_clerks',
            @collection_start,
            @collection_end,
            @rows_collected,
            'Success'
        );
        
        /*
        Print debug information
        */
        IF @debug = 1
        BEGIN
            SELECT
                N'Memory Clerks Collected' AS collection_type,
                @rows_collected AS rows_collected,
                CAST(DATEDIFF(MILLISECOND, @collection_start, @collection_end) / 1000.0 AS DECIMAL(18,2)) AS duration_seconds;
        END;
    END TRY
    BEGIN CATCH
        SET @error_number = ERROR_NUMBER();
        SET @error_message = ERROR_MESSAGE();
        
        /*
        Log error
        */
        INSERT
            system.collection_log
        (
            procedure_name,
            collection_start,
            collection_end,
            rows_collected,
            status,
            error_number,
            error_message
        )
        VALUES
        (
            'collection.collect_memory_clerks',
            @collection_start,
            SYSDATETIME(),
            0,
            'Error',
            @error_number,
            @error_message
        );
        
        /*
        Re-throw error
        */
        THROW;
    END CATCH;
END;
GO

/*
Create buffer pool collection procedure
*/
CREATE OR ALTER PROCEDURE
    collection.collect_buffer_pool
(
    @debug BIT = 0 /*Print debugging information*/
)
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
    
    DECLARE
        @collection_start DATETIME2(7) = SYSDATETIME(),
        @collection_end DATETIME2(7),
        @rows_collected BIGINT = 0,
        @error_number INTEGER,
        @error_message NVARCHAR(4000);
    
    BEGIN TRY
        /*
        Collect buffer pool information
        */
        INSERT
            collection.buffer_pool
        (
            collection_time,
            database_id,
            database_name,
            file_id,
            file_type,
            page_count,
            cached_size_mb
        )
        SELECT
            collection_time = SYSDATETIME(),
            bd.database_id,
            database_name = DB_NAME(bd.database_id),
            bd.file_id,
            file_type = 
                CASE 
                    WHEN mf.type = 0 THEN 'DATA'
                    WHEN mf.type = 1 THEN 'LOG'
                    ELSE 'OTHER'
                END,
            page_count = COUNT(bd.page_id),
            cached_size_mb = COUNT(bd.page_id) * 8.0 / 1024
        FROM sys.dm_os_buffer_descriptors AS bd
        LEFT JOIN sys.master_files AS mf
          ON bd.database_id = mf.database_id
          AND bd.file_id = mf.file_id
        GROUP BY
            bd.database_id,
            bd.file_id,
            CASE 
                WHEN mf.type = 0 THEN 'DATA'
                WHEN mf.type = 1 THEN 'LOG'
                ELSE 'OTHER'
            END;
        
        SET @rows_collected = @@ROWCOUNT;
        SET @collection_end = SYSDATETIME();
        
        /*
        Log collection results
        */
        INSERT
            system.collection_log
        (
            procedure_name,
            collection_start,
            collection_end,
            rows_collected,
            status
        )
        VALUES
        (
            'collection.collect_buffer_pool',
            @collection_start,
            @collection_end,
            @rows_collected,
            'Success'
        );
        
        /*
        Print debug information
        */
        IF @debug = 1
        BEGIN
            SELECT
                N'Buffer Pool Collected' AS collection_type,
                @rows_collected AS rows_collected,
                CAST(DATEDIFF(MILLISECOND, @collection_start, @collection_end) / 1000.0 AS DECIMAL(18,2)) AS duration_seconds;
        END;
    END TRY
    BEGIN CATCH
        SET @error_number = ERROR_NUMBER();
        SET @error_message = ERROR_MESSAGE();
        
        /*
        Log error
        */
        INSERT
            system.collection_log
        (
            procedure_name,
            collection_start,
            collection_end,
            rows_collected,
            status,
            error_number,
            error_message
        )
        VALUES
        (
            'collection.collect_buffer_pool',
            @collection_start,
            SYSDATETIME(),
            0,
            'Error',
            @error_number,
            @error_message
        );
        
        /*
        Re-throw error
        */
        THROW;
    END CATCH;
END;
GO

/*
Create SQL Agent job creation procedure
*/
CREATE OR ALTER PROCEDURE
    system.create_collection_jobs
(
    @debug BIT = 0, /*Print debugging information*/
    @minute_frequency INTEGER = 15, /*Frequency in minutes for regular collections*/
    @hourly_frequency INTEGER = 60, /*Frequency in minutes for hourly collections*/
    @daily_frequency INTEGER = 1440 /*Frequency in minutes for daily collections*/
)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE
        @job_exists INTEGER,
        @job_id UNIQUEIDENTIFIER,
        @platform NVARCHAR(50),
        @instance_type NVARCHAR(50),
        @is_supported BIT = 1;
    
    /*
    Check environment type
    */
    SELECT TOP 1
        @platform = platform,
        @instance_type = instance_type
    FROM system.server_info
    ORDER BY collection_time DESC;
    
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
    IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE name = 'sysjobs' AND type = 'U')
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
            @command = 'EXECUTE DarlingData.collection.collect_wait_stats @sample_seconds = 60;',
            @database_name = 'DarlingData',
            @on_success_action = 3,
            @on_fail_action = 3;
            
        EXECUTE msdb.dbo.sp_add_jobstep
            @job_id = @job_id,
            @step_name = 'Collect Memory Clerks',
            @step_id = 2,
            @subsystem = 'TSQL',
            @command = 'EXECUTE DarlingData.collection.collect_memory_clerks;',
            @database_name = 'DarlingData',
            @on_success_action = 3,
            @on_fail_action = 3;
            
        EXECUTE msdb.dbo.sp_add_jobstep
            @job_id = @job_id,
            @step_name = 'Collect Buffer Pool',
            @step_id = 3,
            @subsystem = 'TSQL',
            @command = 'EXECUTE DarlingData.collection.collect_buffer_pool;',
            @database_name = 'DarlingData',
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
    Print debug information
    */
    IF @debug = 1
    BEGIN
        SELECT
            'Collection jobs created' AS status;
            
        SELECT
            name,
            enabled
        FROM msdb.dbo.sysjobs
        WHERE name LIKE 'DarlingDataCollector%';
    END;
END;
GO

PRINT 'DarlingDataCollector installation complete.';
```

## Post-Installation Steps

1. After running the installation script, connect to the DarlingData database:

```sql
USE DarlingData;
```

2. Run the environment detection procedure to identify your environment type:

```sql
EXECUTE system.detect_environment @debug = 1;
```

> **Note**: If you are running on Azure SQL Database, the procedure will exit with an error informing you that this environment is not supported.

3. On supported environments (On-prem, Azure MI, AWS RDS), create the collection jobs:

```sql
EXECUTE system.create_collection_jobs 
    @debug = 1, 
    @minute_frequency = 15, 
    @hourly_frequency = 60, 
    @daily_frequency = 1440;
```

4. Configure databases for collection (if using Query Store or index usage collection):

```sql
-- Add a database for Query Store collection
EXECUTE system.manage_databases
    @action = 'ADD',
    @database_name = 'YourDatabase',
    @collection_type = 'QUERY_STORE',
    @debug = 1;
    
-- Add a database for index usage collection
EXECUTE system.manage_databases
    @action = 'ADD',
    @database_name = 'YourDatabase',
    @collection_type = 'INDEX',
    @debug = 1;
    
-- Or add for all collection types at once
EXECUTE system.manage_databases
    @action = 'ADD',
    @database_name = 'AnotherDatabase',
    @collection_type = 'ALL',
    @debug = 1;
```

5. Configure data retention (optional):

```sql
-- Set a custom retention period (e.g., 60 days)
EXECUTE system.data_retention
    @retention_days = 60,
    @debug = 1;
```

6. Test the collection procedures:

```sql
-- Test core collectors
EXECUTE collection.collect_wait_stats @debug = 1, @sample_seconds = 10;
EXECUTE collection.collect_memory_clerks @debug = 1;
EXECUTE collection.collect_buffer_pool @debug = 1;

-- Test Query Store collection (if applicable)
EXECUTE collection.collect_query_store @debug = 1, @use_database_list = 1;
```

7. Review the collected data:

```sql
-- Core metrics
SELECT TOP 10 * FROM collection.wait_stats ORDER BY collection_id DESC;
SELECT TOP 10 * FROM collection.memory_clerks ORDER BY collection_id DESC;
SELECT TOP 10 * FROM collection.buffer_pool ORDER BY collection_id DESC;

-- Query Store data (if collected)
SELECT TOP 10 * FROM collection.query_store_queries ORDER BY collection_time DESC;
```

## Configuring Query Store Collection

The Query Store collector can be configured with various thresholds to focus on resource-intensive queries:

```sql
EXECUTE collection.collect_query_store
    @debug = 1,
    @use_database_list = 1,              -- Use databases configured with system.manage_databases
    @include_query_text = 1,             -- Include the full query text
    @include_query_plans = 1,            -- Include execution plans (can be expensive)
    @include_runtime_stats = 1,          -- Include runtime performance statistics
    @include_wait_stats = 1,             -- Include wait statistics by query
    @min_cpu_time_ms = 5000,             -- Min CPU time threshold in milliseconds
    @min_logical_io_reads = 10000,       -- Min logical IO reads threshold
    @min_physical_io_reads = 1000,       -- Min physical IO reads threshold
    @start_time = '2025-01-01T00:00:00', -- Optional: Filter by execution time range
    @end_time = '2025-01-31T23:59:59';   -- Optional: Filter by execution time range
```

## Advanced Configuration

### Environment-Specific Features

DarlingDataCollector automatically detects and adapts to different SQL Server environments:

- **On-premises SQL Server**: Full functionality
- **Azure SQL Managed Instance**: Full functionality
- **AWS RDS for SQL Server**: Full functionality

You can view the current environment information:

```sql
SELECT * FROM system.server_info;
```

### Job Schedules

The default job schedules are:
- Regular collections: Every 15 minutes
- Hourly collections: Every 60 minutes
- Daily collections: Every 24 hours

You can customize these schedules when creating the jobs or modify them later using SQL Server Agent job management.

## Troubleshooting

If you encounter any issues during installation or data collection:

1. Check the collection log for errors:
```sql
SELECT TOP 100 * 
FROM system.collection_log 
WHERE status = 'Error'
ORDER BY collection_start DESC;
```

2. Verify environment detection is correct:
```sql
EXECUTE system.detect_environment @debug = 1;
```

3. For Query Store collection issues, verify that Query Store is enabled in your databases:
```sql
SELECT name, is_query_store_on
FROM sys.databases
WHERE database_id > 4; -- User databases only
```