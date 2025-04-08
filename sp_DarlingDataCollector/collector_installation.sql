/*
██████╗  █████╗ ██████╗ ██╗     ██╗███╗   ██╗ ██████╗ ██████╗  █████╗ ████████╗ █████╗  ██████╗ ██████╗ ██╗     ██╗     ███████╗ ██████╗████████╗ ██████╗ ██████╗ 
██╔══██╗██╔══██╗██╔══██╗██║     ██║████╗  ██║██╔════╝ ██╔══██╗██╔══██╗╚══██╔══╝██╔══██╗██╔════╝ ██╔══██╗██║     ██║     ██╔════╝██╔════╝╚══██╔══╝██╔═══██╗██╔══██╗
██║  ██║███████║██████╔╝██║     ██║██╔██╗ ██║██║  ███╗██║  ██║███████║   ██║   ███████║██║      ██║  ██║██║     ██║     █████╗  ██║        ██║   ██║   ██║██████╔╝
██║  ██║██╔══██║██╔══██╗██║     ██║██║╚██╗██║██║   ██║██║  ██║██╔══██║   ██║   ██╔══██║██║      ██║  ██║██║     ██║     ██╔══╝  ██║        ██║   ██║   ██║██╔══██╗
██████╔╝██║  ██║██║  ██║███████╗██║██║ ╚████║╚██████╔╝██████╔╝██║  ██║   ██║   ██║  ██║╚██████╗ ██████╔╝███████╗███████╗███████╗╚██████╗   ██║   ╚██████╔╝██║  ██║
╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚══════╝╚══════╝╚══════╝ ╚═════╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝
                                                                                                                                                                   
Copyright (c) Darling Data, LLC
https://www.erikdarling.com/

Installation script for the DarlingDataCollector solution.
This script creates the repository database, all schemas, tables, and collection procedures.

Supported environments:
- On-premises SQL Server
- Azure SQL Managed Instance
- Amazon RDS for SQL Server

Note: Azure SQL Database is NOT supported due to its limitations with SQL Agent and other system-level features.
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
Create database collection configuration table for managing which databases to collect from
*/
CREATE TABLE
    system.database_collection_config
(
    database_name NVARCHAR(128) NOT NULL,
    collection_type NVARCHAR(50) NOT NULL,
    added_date DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
    active BIT NOT NULL DEFAULT 1,
    CONSTRAINT PK_database_collection_config PRIMARY KEY (database_name, collection_type)
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
    instance_type NVARCHAR(50) NOT NULL, /* Regular, AzureMI, AWSRDS */
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
    ('sys.dm_exec_query_plan', 'Queries', 1, NULL, 'Returns the showplan in XML format for the batch specified by the plan handle', 90, 'All'),
    ('sys.query_store_query', 'Query Store', 1, 'collection.collect_query_store', 'Contains information about queries in the Query Store', 130, 'All'),
    ('sys.query_store_query_text', 'Query Store', 1, 'collection.collect_query_store', 'Contains the query text for queries in the Query Store', 130, 'All'),
    ('sys.query_store_plan', 'Query Store', 1, 'collection.collect_query_store', 'Contains execution plan information for queries in the Query Store', 130, 'All'),
    ('sys.query_store_runtime_stats', 'Query Store', 1, 'collection.collect_query_store', 'Contains runtime execution statistics information for queries in the Query Store', 130, 'All'),
    ('sys.query_store_wait_stats', 'Query Store', 1, 'collection.collect_query_store', 'Contains wait statistics information for queries in the Query Store', 130, 'All'),
    ('sys.database_query_store_options', 'Query Store', 1, NULL, 'Contains the options for the Query Store in a database', 130, 'All');
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
    
    -- Get edition as integer for more reliable detection
    DECLARE @engine_edition INTEGER = CONVERT(INTEGER, SERVERPROPERTY('EngineEdition'));
    
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
        SET @unsupported_message = 'Azure SQL Database is not supported by DarlingDataCollector due to limitations with SQL Agent and other system-level features.';
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
The following collection procedures have been moved to individual files:
- collection.collect_wait_stats.sql
- collection.collect_memory_clerks.sql 
- collection.collect_buffer_pool.sql
*//*
██╗ ██████╗     ███████╗████████╗ █████╗ ████████╗███████╗     ██████╗ ██████╗ ██╗     ██╗     ███████╗ ██████╗████████╗ ██████╗ ██████╗ 
██║██╔═══██╗    ██╔════╝╚══██╔══╝██╔══██╗╚══██╔══╝██╔════╝    ██╔════╝██╔═══██╗██║     ██║     ██╔════╝██╔════╝╚══██╔══╝██╔═══██╗██╔══██╗
██║██║   ██║    ███████╗   ██║   ███████║   ██║   ███████╗    ██║     ██║   ██║██║     ██║     █████╗  ██║        ██║   ██║   ██║██████╔╝
██║██║   ██║    ╚════██║   ██║   ██╔══██║   ██║   ╚════██║    ██║     ██║   ██║██║     ██║     ██╔══╝  ██║        ██║   ██║   ██║██╔══██╗
██║╚██████╔╝    ███████║   ██║   ██║  ██║   ██║   ███████║    ╚██████╗╚██████╔╝███████╗███████╗███████╗╚██████╗   ██║   ╚██████╔╝██║  ██║
╚═╝ ╚═════╝     ╚══════╝   ╚═╝   ╚═╝  ╚═╝   ╚═╝   ╚══════╝     ╚═════╝ ╚═════╝ ╚══════╝╚══════╝╚══════╝ ╚═════╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝
                                                                                                                                           
Copyright (c) Darling Data, LLC
https://www.erikdarling.com/
*/

CREATE OR ALTER PROCEDURE
    collection.collect_io_stats
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
        @error_number INTEGER,
        @error_message NVARCHAR(4000);
    
    BEGIN TRY
        /*
        If sampling is requested, collect first sample
        */
        IF @sample_seconds IS NOT NULL
        BEGIN
            /*
            Create temporary table for collecting I/O stats samples
            */
            CREATE TABLE
                #io_stats_before
            (
                database_id INTEGER NOT NULL,
                file_id INTEGER NOT NULL,
                io_stall_read_ms BIGINT NOT NULL,
                io_stall_write_ms BIGINT NOT NULL,
                io_stall BIGINT NOT NULL,
                num_of_reads BIGINT NOT NULL,
                num_of_writes BIGINT NOT NULL,
                num_of_bytes_read BIGINT NOT NULL,
                num_of_bytes_written BIGINT NOT NULL,
                PRIMARY KEY (database_id, file_id)
            );
            
            /*
            Collect first sample
            */
            INSERT
                #io_stats_before
            (
                database_id,
                file_id,
                io_stall_read_ms,
                io_stall_write_ms,
                io_stall,
                num_of_reads,
                num_of_writes,
                num_of_bytes_read,
                num_of_bytes_written
            )
            SELECT
                database_id,
                file_id,
                io_stall_read_ms,
                io_stall_write_ms,
                io_stall,
                num_of_reads,
                num_of_writes,
                num_of_bytes_read,
                num_of_bytes_written
            FROM sys.dm_io_virtual_file_stats(NULL, NULL);
            
            /*
            Wait for the specified sample period
            */
            WAITFOR DELAY CONVERT(CHAR(8), DATEADD(SECOND, @sample_seconds, 0), 114);
            
            /*
            Insert data with delta values
            */
            INSERT
                collection.io_stats
            (
                collection_time,
                database_id,
                database_name,
                file_id,
                file_name,
                type_desc,
                io_stall_read_ms,
                io_stall_write_ms,
                io_stall,
                num_of_reads,
                num_of_writes,
                num_of_bytes_read,
                num_of_bytes_written,
                io_stall_read_ms_delta,
                io_stall_write_ms_delta,
                io_stall_delta,
                num_of_reads_delta,
                num_of_writes_delta,
                num_of_bytes_read_delta,
                num_of_bytes_written_delta,
                sample_seconds
            )
            SELECT
                collection_time = SYSDATETIME(),
                fs.database_id,
                database_name = DB_NAME(fs.database_id),
                fs.file_id,
                file_name = mf.physical_name,
                mf.type_desc,
                fs.io_stall_read_ms,
                fs.io_stall_write_ms,
                fs.io_stall,
                fs.num_of_reads,
                fs.num_of_writes,
                fs.num_of_bytes_read,
                fs.num_of_bytes_written,
                io_stall_read_ms_delta = fs.io_stall_read_ms - fsb.io_stall_read_ms,
                io_stall_write_ms_delta = fs.io_stall_write_ms - fsb.io_stall_write_ms,
                io_stall_delta = fs.io_stall - fsb.io_stall,
                num_of_reads_delta = fs.num_of_reads - fsb.num_of_reads,
                num_of_writes_delta = fs.num_of_writes - fsb.num_of_writes,
                num_of_bytes_read_delta = fs.num_of_bytes_read - fsb.num_of_bytes_read,
                num_of_bytes_written_delta = fs.num_of_bytes_written - fsb.num_of_bytes_written,
                sample_seconds = @sample_seconds
            FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS fs
            JOIN #io_stats_before AS fsb
              ON fs.database_id = fsb.database_id
              AND fs.file_id = fsb.file_id
            LEFT JOIN sys.master_files AS mf
              ON fs.database_id = mf.database_id
              AND fs.file_id = mf.file_id;
        END;
        ELSE
        BEGIN
            /*
            Collect current I/O stats without sampling
            */
            INSERT
                collection.io_stats
            (
                collection_time,
                database_id,
                database_name,
                file_id,
                file_name,
                type_desc,
                io_stall_read_ms,
                io_stall_write_ms,
                io_stall,
                num_of_reads,
                num_of_writes,
                num_of_bytes_read,
                num_of_bytes_written
            )
            SELECT
                collection_time = SYSDATETIME(),
                fs.database_id,
                database_name = DB_NAME(fs.database_id),
                fs.file_id,
                file_name = mf.physical_name,
                mf.type_desc,
                fs.io_stall_read_ms,
                fs.io_stall_write_ms,
                fs.io_stall,
                fs.num_of_reads,
                fs.num_of_writes,
                fs.num_of_bytes_read,
                fs.num_of_bytes_written
            FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS fs
            LEFT JOIN sys.master_files AS mf
              ON fs.database_id = mf.database_id
              AND fs.file_id = mf.file_id;
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
            'collection.collect_io_stats',
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
                N'I/O Stats Collected' AS collection_type,
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
            'collection.collect_io_stats',
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
GO/*
██╗███╗   ██╗██████╗ ███████╗██╗  ██╗    ██╗   ██╗███████╗ █████╗  ██████╗ ███████╗    ███████╗████████╗ █████╗ ████████╗███████╗
██║████╗  ██║██╔══██╗██╔════╝╚██╗██╔╝    ██║   ██║██╔════╝██╔══██╗██╔════╝ ██╔════╝    ██╔════╝╚══██╔══╝██╔══██╗╚══██╔══╝██╔════╝
██║██╔██╗ ██║██║  ██║█████╗   ╚███╔╝     ██║   ██║███████╗███████║██║  ███╗█████╗      ███████╗   ██║   ███████║   ██║   ███████╗
██║██║╚██╗██║██║  ██║██╔══╝   ██╔██╗     ██║   ██║╚════██║██╔══██║██║   ██║██╔══╝      ╚════██║   ██║   ██╔══██║   ██║   ╚════██║
██║██║ ╚████║██████╔╝███████╗██╔╝ ██╗    ╚██████╔╝███████║██║  ██║╚██████╔╝███████╗    ███████║   ██║   ██║  ██║   ██║   ███████║
╚═╝╚═╝  ╚═══╝╚═════╝ ╚══════╝╚═╝  ╚═╝     ╚═════╝ ╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝    ╚══════╝   ╚═╝   ╚═╝  ╚═╝   ╚═╝   ╚══════╝
                                                                                                                                  
Copyright (c) Darling Data, LLC
https://www.erikdarling.com/
*/

CREATE OR ALTER PROCEDURE
    collection.collect_index_usage_stats
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
        @error_number INTEGER,
        @error_message NVARCHAR(4000),
        @sql NVARCHAR(MAX);
    
    BEGIN TRY
        /*
        If sampling is requested, collect first sample
        */
        IF @sample_seconds IS NOT NULL
        BEGIN
            /*
            Create temporary table for collecting index usage stats samples
            */
            CREATE TABLE
                #index_usage_stats_before
            (
                database_id INTEGER NOT NULL,
                object_id INTEGER NOT NULL,
                index_id INTEGER NOT NULL,
                user_seeks BIGINT NOT NULL,
                user_scans BIGINT NOT NULL,
                user_lookups BIGINT NOT NULL,
                user_updates BIGINT NOT NULL,
                last_user_seek DATETIME2(7) NULL,
                last_user_scan DATETIME2(7) NULL,
                last_user_lookup DATETIME2(7) NULL,
                last_user_update DATETIME2(7) NULL,
                PRIMARY KEY (database_id, object_id, index_id)
            );
            
            /*
            Collect first sample
            */
            INSERT
                #index_usage_stats_before
            (
                database_id,
                object_id,
                index_id,
                user_seeks,
                user_scans,
                user_lookups,
                user_updates,
                last_user_seek,
                last_user_scan,
                last_user_lookup,
                last_user_update
            )
            SELECT
                database_id,
                object_id,
                index_id,
                user_seeks,
                user_scans,
                user_lookups,
                user_updates,
                last_user_seek,
                last_user_scan,
                last_user_lookup,
                last_user_update
            FROM sys.dm_db_index_usage_stats;
            
            /*
            Wait for the specified sample period
            */
            WAITFOR DELAY CONVERT(CHAR(8), DATEADD(SECOND, @sample_seconds, 0), 114);
            
            /*
            Insert data with delta values
            */
            INSERT
                collection.index_usage_stats
            (
                collection_time,
                database_id,
                database_name,
                object_id,
                schema_name,
                object_name,
                index_id,
                index_name,
                user_seeks,
                user_scans,
                user_lookups,
                user_updates,
                last_user_seek,
                last_user_scan,
                last_user_lookup,
                last_user_update,
                user_seeks_delta,
                user_scans_delta,
                user_lookups_delta,
                user_updates_delta,
                sample_seconds
            )
            SELECT
                collection_time = SYSDATETIME(),
                ius.database_id,
                database_name = DB_NAME(ius.database_id),
                ius.object_id,
                schema_name = OBJECT_SCHEMA_NAME(ius.object_id, ius.database_id),
                object_name = OBJECT_NAME(ius.object_id, ius.database_id),
                ius.index_id,
                index_name = i.name,
                ius.user_seeks,
                ius.user_scans,
                ius.user_lookups,
                ius.user_updates,
                ius.last_user_seek,
                ius.last_user_scan,
                ius.last_user_lookup,
                ius.last_user_update,
                user_seeks_delta = ius.user_seeks - ISNULL(iusb.user_seeks, 0),
                user_scans_delta = ius.user_scans - ISNULL(iusb.user_scans, 0),
                user_lookups_delta = ius.user_lookups - ISNULL(iusb.user_lookups, 0),
                user_updates_delta = ius.user_updates - ISNULL(iusb.user_updates, 0),
                sample_seconds = @sample_seconds
            FROM sys.dm_db_index_usage_stats AS ius
            LEFT JOIN #index_usage_stats_before AS iusb
              ON ius.database_id = iusb.database_id
              AND ius.object_id = iusb.object_id
              AND ius.index_id = iusb.index_id
            LEFT JOIN sys.indexes AS i
              ON ius.object_id = i.object_id
              AND ius.index_id = i.index_id;
        END;
        ELSE
        BEGIN
            /*
            Collect current index usage stats without sampling
            */
            INSERT
                collection.index_usage_stats
            (
                collection_time,
                database_id,
                database_name,
                object_id,
                schema_name,
                object_name,
                index_id,
                index_name,
                user_seeks,
                user_scans,
                user_lookups,
                user_updates,
                last_user_seek,
                last_user_scan,
                last_user_lookup,
                last_user_update
            )
            SELECT
                collection_time = SYSDATETIME(),
                ius.database_id,
                database_name = DB_NAME(ius.database_id),
                ius.object_id,
                schema_name = OBJECT_SCHEMA_NAME(ius.object_id, ius.database_id),
                object_name = OBJECT_NAME(ius.object_id, ius.database_id),
                ius.index_id,
                index_name = i.name,
                ius.user_seeks,
                ius.user_scans,
                ius.user_lookups,
                ius.user_updates,
                ius.last_user_seek,
                ius.last_user_scan,
                ius.last_user_lookup,
                ius.last_user_update
            FROM sys.dm_db_index_usage_stats AS ius
            LEFT JOIN sys.indexes AS i
              ON ius.object_id = i.object_id
              AND ius.index_id = i.index_id;
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
            'collection.collect_index_usage_stats',
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
                N'Index Usage Stats Collected' AS collection_type,
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
            'collection.collect_index_usage_stats',
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
GO/*
 ██████╗ ██╗   ██╗███████╗██████╗ ██╗   ██╗    ███████╗████████╗ █████╗ ████████╗███████╗     ██████╗ ██████╗ ██╗     ██╗     ███████╗ ██████╗████████╗ ██████╗ ██████╗ 
██╔═══██╗██║   ██║██╔════╝██╔══██╗╚██╗ ██╔╝    ██╔════╝╚══██╔══╝██╔══██╗╚══██╔══╝██╔════╝    ██╔════╝██╔═══██╗██║     ██║     ██╔════╝██╔════╝╚══██╔══╝██╔═══██╗██╔══██╗
██║   ██║██║   ██║█████╗  ██████╔╝ ╚████╔╝     ███████╗   ██║   ███████║   ██║   ███████╗    ██║     ██║   ██║██║     ██║     █████╗  ██║        ██║   ██║   ██║██████╔╝
██║▄▄ ██║██║   ██║██╔══╝  ██╔══██╗  ╚██╔╝      ╚════██║   ██║   ██╔══██║   ██║   ╚════██║    ██║     ██║   ██║██║     ██║     ██╔══╝  ██║        ██║   ██║   ██║██╔══██╗
╚██████╔╝╚██████╔╝███████╗██║  ██║   ██║       ███████║   ██║   ██║  ██║   ██║   ███████║    ╚██████╗╚██████╔╝███████╗███████╗███████╗╚██████╗   ██║   ╚██████╔╝██║  ██║
 ╚══▀▀═╝  ╚═════╝ ╚══════╝╚═╝  ╚═╝   ╚═╝       ╚══════╝   ╚═╝   ╚═╝  ╚═╝   ╚═╝   ╚══════╝     ╚═════╝ ╚═════╝ ╚══════╝╚══════╝╚══════╝ ╚═════╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝
                                                                                                                                                                          
Copyright (c) Darling Data, LLC
https://www.erikdarling.com/
*/

CREATE OR ALTER PROCEDURE
    collection.collect_query_stats
(
    @debug BIT = 0, /*Print debugging information*/
    @sample_seconds INTEGER = NULL, /*Optional: Collect sample over time period*/
    @collect_query_text BIT = 1, /*Collect query text*/
    @collect_query_plan BIT = 0, /*Collect query plans (can be expensive)*/
    @min_executions INTEGER = 2, /*Minimum executions to collect*/
    @min_worker_time_ms INTEGER = 1000 /*Minimum worker time in milliseconds*/
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
        @error_message NVARCHAR(4000),
        @sql NVARCHAR(MAX),
        @has_query_spill_column BIT = 0;
    
    BEGIN TRY
        /*
        Check for total_spills column availability (SQL Server 2017+)
        */
        IF EXISTS
        (
            SELECT 1
            FROM sys.dm_exec_query_stats
            WHERE total_spills IS NOT NULL
        )
        BEGIN
            SET @has_query_spill_column = 1;
        END;
        
        /*
        If sampling is requested, collect first sample
        */
        IF @sample_seconds IS NOT NULL
        BEGIN
            /*
            Create temporary table for collecting query stats samples
            */
            CREATE TABLE
                #query_stats_before
            (
                sql_handle VARBINARY(64) NOT NULL,
                plan_handle VARBINARY(64) NOT NULL,
                statement_start_offset INTEGER NOT NULL,
                statement_end_offset INTEGER NOT NULL,
                execution_count BIGINT NOT NULL,
                total_worker_time BIGINT NOT NULL,
                total_physical_reads BIGINT NOT NULL,
                total_logical_reads BIGINT NOT NULL,
                total_logical_writes BIGINT NOT NULL,
                total_elapsed_time BIGINT NOT NULL,
                total_spills BIGINT NULL,
                PRIMARY KEY 
                (
                    sql_handle, 
                    plan_handle,
                    statement_start_offset,
                    statement_end_offset
                )
            );
            
            /*
            Collect first sample
            */
            IF @has_query_spill_column = 1
            BEGIN
                INSERT
                    #query_stats_before
                (
                    sql_handle,
                    plan_handle,
                    statement_start_offset,
                    statement_end_offset,
                    execution_count,
                    total_worker_time,
                    total_physical_reads,
                    total_logical_reads,
                    total_logical_writes,
                    total_elapsed_time,
                    total_spills
                )
                SELECT
                    sql_handle,
                    plan_handle,
                    statement_start_offset,
                    statement_end_offset,
                    execution_count,
                    total_worker_time,
                    total_physical_reads,
                    total_logical_reads,
                    total_logical_writes,
                    total_elapsed_time,
                    total_spills
                FROM sys.dm_exec_query_stats
                WHERE execution_count >= @min_executions
                AND total_worker_time >= (@min_worker_time_ms * 1000);
            END;
            ELSE
            BEGIN
                INSERT
                    #query_stats_before
                (
                    sql_handle,
                    plan_handle,
                    statement_start_offset,
                    statement_end_offset,
                    execution_count,
                    total_worker_time,
                    total_physical_reads,
                    total_logical_reads,
                    total_logical_writes,
                    total_elapsed_time,
                    total_spills
                )
                SELECT
                    sql_handle,
                    plan_handle,
                    statement_start_offset,
                    statement_end_offset,
                    execution_count,
                    total_worker_time,
                    total_physical_reads,
                    total_logical_reads,
                    total_logical_writes,
                    total_elapsed_time,
                    NULL AS total_spills
                FROM sys.dm_exec_query_stats
                WHERE execution_count >= @min_executions
                AND total_worker_time >= (@min_worker_time_ms * 1000);
            END;
            
            /*
            Wait for the specified sample period
            */
            WAITFOR DELAY CONVERT(CHAR(8), DATEADD(SECOND, @sample_seconds, 0), 114);
            
            /*
            Insert data with delta values
            */
            IF @has_query_spill_column = 1
            BEGIN
                INSERT
                    collection.query_stats
                (
                    collection_time,
                    sql_handle,
                    plan_handle,
                    query_hash,
                    query_plan_hash,
                    statement_start_offset,
                    statement_end_offset,
                    execution_count,
                    total_worker_time,
                    total_physical_reads,
                    total_logical_reads,
                    total_logical_writes,
                    total_elapsed_time,
                    total_spills,
                    creation_time,
                    last_execution_time,
                    execution_count_delta,
                    total_worker_time_delta,
                    total_physical_reads_delta,
                    total_logical_reads_delta,
                    total_logical_writes_delta,
                    total_elapsed_time_delta,
                    total_spills_delta,
                    sample_seconds,
                    query_text,
                    query_plan
                )
                SELECT
                    collection_time = SYSDATETIME(),
                    qs.sql_handle,
                    qs.plan_handle,
                    qs.query_hash,
                    qs.query_plan_hash,
                    qs.statement_start_offset,
                    qs.statement_end_offset,
                    qs.execution_count,
                    qs.total_worker_time,
                    qs.total_physical_reads,
                    qs.total_logical_reads,
                    qs.total_logical_writes,
                    qs.total_elapsed_time,
                    qs.total_spills,
                    qs.creation_time,
                    qs.last_execution_time,
                    execution_count_delta = qs.execution_count - qsb.execution_count,
                    total_worker_time_delta = qs.total_worker_time - qsb.total_worker_time,
                    total_physical_reads_delta = qs.total_physical_reads - qsb.total_physical_reads,
                    total_logical_reads_delta = qs.total_logical_reads - qsb.total_logical_reads,
                    total_logical_writes_delta = qs.total_logical_writes - qsb.total_logical_writes,
                    total_elapsed_time_delta = qs.total_elapsed_time - qsb.total_elapsed_time,
                    total_spills_delta = qs.total_spills - qsb.total_spills,
                    sample_seconds = @sample_seconds,
                    query_text = 
                        CASE
                            WHEN @collect_query_text = 1
                            THEN (
                                SELECT
                                    text
                                FROM sys.dm_exec_sql_text(qs.sql_handle)
                            )
                            ELSE NULL
                        END,
                    query_plan = 
                        CASE
                            WHEN @collect_query_plan = 1
                            THEN (
                                SELECT
                                    query_plan
                                FROM sys.dm_exec_query_plan(qs.plan_handle)
                            )
                            ELSE NULL
                        END
                FROM sys.dm_exec_query_stats AS qs
                JOIN #query_stats_before AS qsb
                  ON qs.sql_handle = qsb.sql_handle
                  AND qs.plan_handle = qsb.plan_handle
                  AND qs.statement_start_offset = qsb.statement_start_offset
                  AND qs.statement_end_offset = qsb.statement_end_offset
                WHERE (qs.execution_count - qsb.execution_count) > 0
                AND qs.execution_count >= @min_executions
                AND qs.total_worker_time >= (@min_worker_time_ms * 1000);
            END;
            ELSE
            BEGIN
                INSERT
                    collection.query_stats
                (
                    collection_time,
                    sql_handle,
                    plan_handle,
                    query_hash,
                    query_plan_hash,
                    statement_start_offset,
                    statement_end_offset,
                    execution_count,
                    total_worker_time,
                    total_physical_reads,
                    total_logical_reads,
                    total_logical_writes,
                    total_elapsed_time,
                    creation_time,
                    last_execution_time,
                    execution_count_delta,
                    total_worker_time_delta,
                    total_physical_reads_delta,
                    total_logical_reads_delta,
                    total_logical_writes_delta,
                    total_elapsed_time_delta,
                    sample_seconds,
                    query_text,
                    query_plan
                )
                SELECT
                    collection_time = SYSDATETIME(),
                    qs.sql_handle,
                    qs.plan_handle,
                    qs.query_hash,
                    qs.query_plan_hash,
                    qs.statement_start_offset,
                    qs.statement_end_offset,
                    qs.execution_count,
                    qs.total_worker_time,
                    qs.total_physical_reads,
                    qs.total_logical_reads,
                    qs.total_logical_writes,
                    qs.total_elapsed_time,
                    qs.creation_time,
                    qs.last_execution_time,
                    execution_count_delta = qs.execution_count - qsb.execution_count,
                    total_worker_time_delta = qs.total_worker_time - qsb.total_worker_time,
                    total_physical_reads_delta = qs.total_physical_reads - qsb.total_physical_reads,
                    total_logical_reads_delta = qs.total_logical_reads - qsb.total_logical_reads,
                    total_logical_writes_delta = qs.total_logical_writes - qsb.total_logical_writes,
                    total_elapsed_time_delta = qs.total_elapsed_time - qsb.total_elapsed_time,
                    sample_seconds = @sample_seconds,
                    query_text = 
                        CASE
                            WHEN @collect_query_text = 1
                            THEN (
                                SELECT
                                    text
                                FROM sys.dm_exec_sql_text(qs.sql_handle)
                            )
                            ELSE NULL
                        END,
                    query_plan = 
                        CASE
                            WHEN @collect_query_plan = 1
                            THEN (
                                SELECT
                                    query_plan
                                FROM sys.dm_exec_query_plan(qs.plan_handle)
                            )
                            ELSE NULL
                        END
                FROM sys.dm_exec_query_stats AS qs
                JOIN #query_stats_before AS qsb
                  ON qs.sql_handle = qsb.sql_handle
                  AND qs.plan_handle = qsb.plan_handle
                  AND qs.statement_start_offset = qsb.statement_start_offset
                  AND qs.statement_end_offset = qsb.statement_end_offset
                WHERE (qs.execution_count - qsb.execution_count) > 0
                AND qs.execution_count >= @min_executions
                AND qs.total_worker_time >= (@min_worker_time_ms * 1000);
            END;
        END;
        ELSE
        BEGIN
            /*
            Collect current query stats without sampling
            */
            IF @has_query_spill_column = 1
            BEGIN
                INSERT
                    collection.query_stats
                (
                    collection_time,
                    sql_handle,
                    plan_handle,
                    query_hash,
                    query_plan_hash,
                    statement_start_offset,
                    statement_end_offset,
                    execution_count,
                    total_worker_time,
                    total_physical_reads,
                    total_logical_reads,
                    total_logical_writes,
                    total_elapsed_time,
                    total_spills,
                    creation_time,
                    last_execution_time,
                    query_text,
                    query_plan
                )
                SELECT
                    collection_time = SYSDATETIME(),
                    qs.sql_handle,
                    qs.plan_handle,
                    qs.query_hash,
                    qs.query_plan_hash,
                    qs.statement_start_offset,
                    qs.statement_end_offset,
                    qs.execution_count,
                    qs.total_worker_time,
                    qs.total_physical_reads,
                    qs.total_logical_reads,
                    qs.total_logical_writes,
                    qs.total_elapsed_time,
                    qs.total_spills,
                    qs.creation_time,
                    qs.last_execution_time,
                    query_text = 
                        CASE
                            WHEN @collect_query_text = 1
                            THEN (
                                SELECT
                                    text
                                FROM sys.dm_exec_sql_text(qs.sql_handle)
                            )
                            ELSE NULL
                        END,
                    query_plan = 
                        CASE
                            WHEN @collect_query_plan = 1
                            THEN (
                                SELECT
                                    query_plan
                                FROM sys.dm_exec_query_plan(qs.plan_handle)
                            )
                            ELSE NULL
                        END
                FROM sys.dm_exec_query_stats AS qs
                WHERE qs.execution_count >= @min_executions
                AND qs.total_worker_time >= (@min_worker_time_ms * 1000);
            END;
            ELSE
            BEGIN
                INSERT
                    collection.query_stats
                (
                    collection_time,
                    sql_handle,
                    plan_handle,
                    query_hash,
                    query_plan_hash,
                    statement_start_offset,
                    statement_end_offset,
                    execution_count,
                    total_worker_time,
                    total_physical_reads,
                    total_logical_reads,
                    total_logical_writes,
                    total_elapsed_time,
                    creation_time,
                    last_execution_time,
                    query_text,
                    query_plan
                )
                SELECT
                    collection_time = SYSDATETIME(),
                    qs.sql_handle,
                    qs.plan_handle,
                    qs.query_hash,
                    qs.query_plan_hash,
                    qs.statement_start_offset,
                    qs.statement_end_offset,
                    qs.execution_count,
                    qs.total_worker_time,
                    qs.total_physical_reads,
                    qs.total_logical_reads,
                    qs.total_logical_writes,
                    qs.total_elapsed_time,
                    qs.creation_time,
                    qs.last_execution_time,
                    query_text = 
                        CASE
                            WHEN @collect_query_text = 1
                            THEN (
                                SELECT
                                    text
                                FROM sys.dm_exec_sql_text(qs.sql_handle)
                            )
                            ELSE NULL
                        END,
                    query_plan = 
                        CASE
                            WHEN @collect_query_plan = 1
                            THEN (
                                SELECT
                                    query_plan
                                FROM sys.dm_exec_query_plan(qs.plan_handle)
                            )
                            ELSE NULL
                        END
                FROM sys.dm_exec_query_stats AS qs
                WHERE qs.execution_count >= @min_executions
                AND qs.total_worker_time >= (@min_worker_time_ms * 1000);
            END;
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
            'collection.collect_query_stats',
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
                N'Query Stats Collected' AS collection_type,
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
            'collection.collect_query_stats',
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
GO/*
 ██████╗ ██████╗ ███╗   ██╗███╗   ██╗███████╗ ██████╗████████╗██╗ ██████╗ ███╗   ██╗███████╗
██╔════╝██╔═══██╗████╗  ██║████╗  ██║██╔════╝██╔════╝╚══██╔══╝██║██╔═══██╗████╗  ██║██╔════╝
██║     ██║   ██║██╔██╗ ██║██╔██╗ ██║█████╗  ██║        ██║   ██║██║   ██║██╔██╗ ██║███████╗
██║     ██║   ██║██║╚██╗██║██║╚██╗██║██╔══╝  ██║        ██║   ██║██║   ██║██║╚██╗██║╚════██║
╚██████╗╚██████╔╝██║ ╚████║██║ ╚████║███████╗╚██████╗   ██║   ██║╚██████╔╝██║ ╚████║███████║
 ╚═════╝ ╚═════╝ ╚═╝  ╚═══╝╚═╝  ╚═══╝╚══════╝ ╚═════╝   ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝
                                                                                             
Copyright (c) Darling Data, LLC
https://www.erikdarling.com/
*/

CREATE OR ALTER PROCEDURE
    collection.collect_connections
(
    @debug BIT = 0, /*Print debugging information*/
    @include_system_sessions BIT = 0 /*Include system sessions*/
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
        Collect connection information
        */
        INSERT
            collection.connections
        (
            collection_time,
            session_id,
            login_name,
            host_name,
            program_name,
            client_interface_name,
            login_time,
            status,
            cpu_time,
            memory_usage,
            total_elapsed_time,
            last_request_start_time,
            last_request_end_time,
            reads,
            writes,
            logical_reads,
            transaction_isolation_level,
            lock_timeout,
            deadlock_priority,
            row_count,
            is_user_process
        )
        SELECT
            collection_time = SYSDATETIME(),
            s.session_id,
            login_name = s.login_name,
            host_name = s.host_name,
            program_name = s.program_name,
            client_interface_name = s.client_interface_name,
            login_time = s.login_time,
            status = s.status,
            cpu_time = s.cpu_time,
            memory_usage = s.memory_usage,
            total_elapsed_time = s.total_elapsed_time,
            last_request_start_time = s.last_request_start_time,
            last_request_end_time = s.last_request_end_time,
            reads = s.reads,
            writes = s.writes,
            logical_reads = s.logical_reads,
            transaction_isolation_level = s.transaction_isolation_level,
            lock_timeout = s.lock_timeout,
            deadlock_priority = s.deadlock_priority,
            row_count = s.row_count,
            is_user_process = s.is_user_process
        FROM sys.dm_exec_sessions AS s
        WHERE s.is_user_process = 1
        OR @include_system_sessions = 1;
        
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
            'collection.collect_connections',
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
                N'Connections Collected' AS collection_type,
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
            'collection.collect_connections',
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
GO/*
██████╗ ██╗      ██████╗  ██████╗██╗  ██╗██╗███╗   ██╗ ██████╗      ██████╗ ██████╗ ██╗     ██╗     ███████╗ ██████╗████████╗ ██████╗ ██████╗ 
██╔══██╗██║     ██╔═══██╗██╔════╝██║ ██╔╝██║████╗  ██║██╔════╝     ██╔════╝██╔═══██╗██║     ██║     ██╔════╝██╔════╝╚══██╔══╝██╔═══██╗██╔══██╗
██████╔╝██║     ██║   ██║██║     █████╔╝ ██║██╔██╗ ██║██║  ███╗    ██║     ██║   ██║██║     ██║     █████╗  ██║        ██║   ██║   ██║██████╔╝
██╔══██╗██║     ██║   ██║██║     ██╔═██╗ ██║██║╚██╗██║██║   ██║    ██║     ██║   ██║██║     ██║     ██╔══╝  ██║        ██║   ██║   ██║██╔══██╗
██████╔╝███████╗╚██████╔╝╚██████╗██║  ██╗██║██║ ╚████║╚██████╔╝    ╚██████╗╚██████╔╝███████╗███████╗███████╗╚██████╗   ██║   ╚██████╔╝██║  ██║
╚═════╝ ╚══════╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝ ╚═════╝      ╚═════╝ ╚═════╝ ╚══════╝╚══════╝╚══════╝ ╚═════╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝
                                                                                                                                              
Copyright (c) Darling Data, LLC
https://www.erikdarling.com/
*/

CREATE OR ALTER PROCEDURE
    collection.collect_blocking
(
    @debug BIT = 0, /*Print debugging information*/
    @min_block_duration_ms INTEGER = 1000, /*Minimum blocking duration in milliseconds*/
    @collect_sql_text BIT = 1 /*Collect SQL text for blocked and blocking sessions*/
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
        Collect blocking information
        */
        INSERT
            collection.blocking
        (
            collection_time,
            blocked_session_id,
            blocking_session_id,
            blocking_tree,
            blocked_sql_text,
            blocking_sql_text,
            wait_type,
            wait_duration_ms,
            wait_resource,
            resource_description,
            transaction_name,
            transaction_isolation_level,
            lock_mode,
            status,
            blocked_login_name,
            blocked_host_name,
            blocked_program_name,
            blocking_login_name,
            blocking_host_name,
            blocking_program_name
        )
        SELECT
            collection_time = SYSDATETIME(),
            blocked_session_id = waits.session_id,
            blocking_session_id = waits.blocking_session_id,
            blocking_tree = (
                WITH RECURSIVE blocking_hierarchy AS
                (
                    SELECT
                        session_id,
                        blocking_session_id,
                        CAST(CONCAT(session_id, ' <- ', blocking_session_id) AS NVARCHAR(4000)) AS hierarchy_path,
                        1 AS level
                    FROM sys.dm_os_waiting_tasks AS wt
                    WHERE wt.blocking_session_id IS NOT NULL
                    AND wt.blocking_session_id <> wt.session_id
                    AND wt.wait_duration_ms >= @min_block_duration_ms
                    
                    UNION ALL
                    
                    SELECT
                        wt.session_id,
                        wt.blocking_session_id,
                        CAST(CONCAT(bh.hierarchy_path, ' <- ', wt.blocking_session_id) AS NVARCHAR(4000)),
                        bh.level + 1
                    FROM sys.dm_os_waiting_tasks AS wt
                    JOIN blocking_hierarchy AS bh
                      ON wt.session_id = bh.blocking_session_id
                    WHERE wt.blocking_session_id IS NOT NULL
                    AND wt.blocking_session_id <> wt.session_id
                    AND wt.wait_duration_ms >= @min_block_duration_ms
                )
                SELECT TOP (1) hierarchy_path
                FROM blocking_hierarchy
                WHERE session_id = waits.session_id
                ORDER BY level DESC
            ),
            blocked_sql_text = 
                CASE
                    WHEN @collect_sql_text = 1
                    THEN (
                        SELECT
                            text
                        FROM sys.dm_exec_sql_text(blocked_er.sql_handle)
                    )
                    ELSE NULL
                END,
            blocking_sql_text = 
                CASE
                    WHEN @collect_sql_text = 1
                    THEN (
                        SELECT
                            text
                        FROM sys.dm_exec_sql_text(blocking_er.sql_handle)
                    )
                    ELSE NULL
                END,
            wait_type = waits.wait_type,
            wait_duration_ms = waits.wait_duration_ms,
            wait_resource = waits.resource_description,
            resource_description = CASE
                WHEN waits.wait_type LIKE 'LCK%' AND waits.resource_description LIKE 'KEY%'
                THEN (
                    SELECT
                        CONCAT(
                            'Database: ', DB_NAME(tl.resource_database_id),
                            ', Table: ', OBJECT_NAME(tl.resource_associated_entity_id, tl.resource_database_id),
                            ', Index: ', si.name,
                            ', Lock Type: ', tl.resource_description
                        )
                    FROM sys.dm_tran_locks AS tl
                    LEFT JOIN sys.indexes AS si
                      ON tl.resource_associated_entity_id = si.object_id
                      AND tl.resource_database_id = DB_ID()
                    WHERE tl.request_session_id = waits.session_id
                    AND tl.resource_type = 'KEY'
                    AND tl.request_status = 'WAIT'
                )
                WHEN waits.wait_type LIKE 'LCK%' AND waits.resource_description LIKE 'PAGE%'
                THEN (
                    SELECT TOP (1)
                        CONCAT(
                            'Database: ', DB_NAME(tl.resource_database_id),
                            ', File: ', mf.name,
                            ', PageID: ', SUBSTRING(tl.resource_description, 6, LEN(tl.resource_description) - 5),
                            ', Lock Type: ', tl.resource_description
                        )
                    FROM sys.dm_tran_locks AS tl
                    JOIN sys.master_files AS mf
                      ON tl.resource_database_id = mf.database_id
                      AND SUBSTRING(tl.resource_description, 1, 1) = mf.file_id
                    WHERE tl.request_session_id = waits.session_id
                    AND tl.resource_type = 'PAGE'
                    AND tl.request_status = 'WAIT'
                )
                WHEN waits.wait_type LIKE 'LCK%' AND waits.resource_description LIKE 'OBJECT%'
                THEN (
                    SELECT
                        CONCAT(
                            'Database: ', DB_NAME(tl.resource_database_id),
                            ', Object: ', OBJECT_NAME(tl.resource_associated_entity_id, tl.resource_database_id),
                            ', Lock Type: ', tl.resource_description
                        )
                    FROM sys.dm_tran_locks AS tl
                    WHERE tl.request_session_id = waits.session_id
                    AND tl.resource_type = 'OBJECT'
                    AND tl.request_status = 'WAIT'
                )
                ELSE NULL
            END,
            transaction_name = 
                CASE 
                    WHEN blocked_tst.name IS NOT NULL THEN blocked_tst.name
                    ELSE blocked_at.name
                END,
            transaction_isolation_level = 
                CASE blocked_es.transaction_isolation_level
                    WHEN 0 THEN 'Unspecified'
                    WHEN 1 THEN 'ReadUncommitted'
                    WHEN 2 THEN 'ReadCommitted'
                    WHEN 3 THEN 'Repeatable'
                    WHEN 4 THEN 'Serializable'
                    WHEN 5 THEN 'Snapshot'
                    ELSE CAST(blocked_es.transaction_isolation_level AS NVARCHAR(30))
                END,
            lock_mode = 
                CASE 
                    WHEN tl.request_mode = 'S' THEN 'S'
                    WHEN tl.request_mode = 'X' THEN 'X'
                    WHEN tl.request_mode = 'U' THEN 'U'
                    WHEN tl.request_mode = 'IS' THEN 'IS'
                    WHEN tl.request_mode = 'IX' THEN 'IX'
                    WHEN tl.request_mode = 'SIX' THEN 'SIX'
                    WHEN tl.request_mode = 'SIU' THEN 'SIU'
                    WHEN tl.request_mode = 'UIX' THEN 'UIX'
                    WHEN tl.request_mode = 'BU' THEN 'BU'
                    WHEN tl.request_mode = 'RangeS_S' THEN 'RangeS_S'
                    WHEN tl.request_mode = 'RangeS_U' THEN 'RangeS_U'
                    WHEN tl.request_mode = 'RangeI_N' THEN 'RangeI_N'
                    WHEN tl.request_mode = 'RangeI_S' THEN 'RangeI_S'
                    WHEN tl.request_mode = 'RangeI_U' THEN 'RangeI_U'
                    WHEN tl.request_mode = 'RangeI_X' THEN 'RangeI_X'
                    WHEN tl.request_mode = 'RangeX_S' THEN 'RangeX_S'
                    WHEN tl.request_mode = 'RangeX_U' THEN 'RangeX_U'
                    WHEN tl.request_mode = 'RangeX_X' THEN 'RangeX_X'
                    ELSE tl.request_mode
                END,
            status = blocked_es.status,
            blocked_login_name = blocked_es.login_name,
            blocked_host_name = blocked_es.host_name,
            blocked_program_name = blocked_es.program_name,
            blocking_login_name = blocking_es.login_name,
            blocking_host_name = blocking_es.host_name,
            blocking_program_name = blocking_es.program_name
        FROM sys.dm_os_waiting_tasks AS waits
        JOIN sys.dm_exec_sessions AS blocked_es
          ON waits.session_id = blocked_es.session_id
        LEFT JOIN sys.dm_exec_sessions AS blocking_es
          ON waits.blocking_session_id = blocking_es.session_id
        LEFT JOIN sys.dm_exec_requests AS blocked_er
          ON waits.session_id = blocked_er.session_id
        LEFT JOIN sys.dm_exec_requests AS blocking_er
          ON waits.blocking_session_id = blocking_er.session_id
        LEFT JOIN sys.dm_tran_active_transactions AS blocked_at
          ON blocked_er.transaction_id = blocked_at.transaction_id
        LEFT JOIN sys.dm_tran_session_transactions AS blocked_tst
          ON waits.session_id = blocked_tst.session_id
        LEFT JOIN sys.dm_tran_locks AS tl
          ON waits.session_id = tl.request_session_id
        WHERE waits.blocking_session_id IS NOT NULL
        AND waits.blocking_session_id <> waits.session_id
        AND waits.wait_duration_ms >= @min_block_duration_ms;
        
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
            'collection.collect_blocking',
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
                N'Blocking Information Collected' AS collection_type,
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
            'collection.collect_blocking',
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
            @on_success_action = 3,
            @on_fail_action = 3;
            
        EXECUTE msdb.dbo.sp_add_jobstep
            @job_id = @job_id,
            @step_name = 'Collect I/O Stats',
            @step_id = 4,
            @subsystem = 'TSQL',
            @command = 'EXECUTE DarlingData.collection.collect_io_stats @sample_seconds = 60;',
            @database_name = 'DarlingData',
            @on_success_action = 3,
            @on_fail_action = 3;
            
        EXECUTE msdb.dbo.sp_add_jobstep
            @job_id = @job_id,
            @step_name = 'Collect Index Usage Stats',
            @step_id = 5,
            @subsystem = 'TSQL',
            @command = 'EXECUTE DarlingData.collection.collect_index_usage_stats @sample_seconds = 60;',
            @database_name = 'DarlingData',
            @on_success_action = 3,
            @on_fail_action = 3;
            
        EXECUTE msdb.dbo.sp_add_jobstep
            @job_id = @job_id,
            @step_name = 'Collect Connections',
            @step_id = 6,
            @subsystem = 'TSQL',
            @command = 'EXECUTE DarlingData.collection.collect_connections;',
            @database_name = 'DarlingData',
            @on_success_action = 3,
            @on_fail_action = 3;
            
        EXECUTE msdb.dbo.sp_add_jobstep
            @job_id = @job_id,
            @step_name = 'Collect Blocking',
            @step_id = 7,
            @subsystem = 'TSQL',
            @command = 'EXECUTE DarlingData.collection.collect_blocking;',
            @database_name = 'DarlingData',
            @on_success_action = 3,
            @on_fail_action = 3;
            
        EXECUTE msdb.dbo.sp_add_jobstep
            @job_id = @job_id,
            @step_name = 'Collect Query Stats',
            @step_id = 8,
            @subsystem = 'TSQL',
            @command = 'EXECUTE DarlingData.collection.collect_query_stats @sample_seconds = 60;',
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
        WHERE name LIKE 'DarlingDataCollector/*
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
            @on_success_action = 3,
            @on_fail_action = 3;
            
        EXECUTE msdb.dbo.sp_add_jobstep
            @job_id = @job_id,
            @step_name = 'Collect I/O Stats',
            @step_id = 4,
            @subsystem = 'TSQL',
            @command = 'EXECUTE DarlingData.collection.collect_io_stats @sample_seconds = 60;',
            @database_name = 'DarlingData',
            @on_success_action = 3,
            @on_fail_action = 3;
            
        EXECUTE msdb.dbo.sp_add_jobstep
            @job_id = @job_id,
            @step_name = 'Collect Index Usage Stats',
            @step_id = 5,
            @subsystem = 'TSQL',
            @command = 'EXECUTE DarlingData.collection.collect_index_usage_stats @sample_seconds = 60;',
            @database_name = 'DarlingData',
            @on_success_action = 3,
            @on_fail_action = 3;
            
        EXECUTE msdb.dbo.sp_add_jobstep
            @job_id = @job_id,
            @step_name = 'Collect Connections',
            @step_id = 6,
            @subsystem = 'TSQL',
            @command = 'EXECUTE DarlingData.collection.collect_connections;',
            @database_name = 'DarlingData',
            @on_success_action = 3,
            @on_fail_action = 3;
            
        EXECUTE msdb.dbo.sp_add_jobstep
            @job_id = @job_id,
            @step_name = 'Collect Blocking',
            @step_id = 7,
            @subsystem = 'TSQL',
            @command = 'EXECUTE DarlingData.collection.collect_blocking;',
            @database_name = 'DarlingData',
            @on_success_action = 3,
            @on_fail_action = 3;
            
        EXECUTE msdb.dbo.sp_add_jobstep
            @job_id = @job_id,
            @step_name = 'Collect Query Stats',
            @step_id = 8,
            @subsystem = 'TSQL',
            @command = 'EXECUTE DarlingData.collection.collect_query_stats @sample_seconds = 60;',
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

/*
░█▀▄░█▀█░▀█▀░█▀█░█▀▄░█▀█░█▀▀░█▀▀░   ▄█▄   ░█▀▀░█░█░█▀▀░█▀▄░█░█░   ░█▀▀░▀█▀░█▀█░█▀▄░█▀▀
░█░█░█▀█░░█░░█▀█░█▀▄░█▀█░▀▀█░█▀▀░   ░█░░   ░▀▀█░▀▄▀░█▀▀░█▀▄░░█░░   ░▀▀█░░█░░█░█░█▀▄░█▀▀
░▀▀░░▀░▀░░▀░░▀░▀░▀▀░░▀░▀░▀▀▀░█▀▀░   ░▀░░   ░▀▀▀░░▀░░▀▀▀░▀░▀░░▀░░   ░▀▀▀░░▀░░▀▀▀░▀░▀░▀▀▀

Copyright (c) Darling Data, LLC
https://www.erikdarling.com/
*/

CREATE OR ALTER PROCEDURE
    system.manage_databases
(
    @action NVARCHAR(10) = NULL, /*ADD, REMOVE, LIST*/
    @database_name NVARCHAR(128) = NULL, /*Database to add or remove*/
    @collection_type NVARCHAR(50) = NULL, /*Type of collection: INDEX, QUERY_STORE, ALL*/
    @debug BIT = 0, /*Print debugging information*/
    @help BIT = 0 /*Prints help information*/
)
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
    
    BEGIN TRY
        /*
        Variable declarations
        */
        DECLARE
            @sql NVARCHAR(MAX) = N'',
            @error_number INTEGER = 0,
            @error_severity INTEGER = 0,
            @error_state INTEGER = 0,
            @error_line INTEGER = 0,
            @error_message NVARCHAR(4000) = N'',
            @database_id INTEGER = NULL,
            @online_status BIT = NULL,
            @readonly_status BIT = NULL;
            
        /*
        Create collection type table
        */
        DECLARE
            @collection_types TABLE
            (
                type_id INTEGER NOT NULL,
                type_name NVARCHAR(50) NOT NULL
            );
            
        INSERT @collection_types
        (
            type_id,
            type_name
        )
        VALUES
            (1, N'INDEX'),
            (2, N'QUERY_STORE'),
            (3, N'ALL');
            
        /*
        Parameter validation
        */
        IF @help = 1
        BEGIN
            SELECT
                help = N'This procedure manages databases for specific collection types.
                
Parameters:
  @action = Action to perform: ADD, REMOVE, LIST (required)
  @database_name = Database to add or remove (required for ADD, REMOVE)
  @collection_type = Collection type: INDEX, QUERY_STORE, ALL (required for ADD, REMOVE)
  @debug = 1 to print detailed information, 0 for normal operation
  @help = 1 to show this help information

Example usage:
  -- Add a database for index collection
  EXECUTE system.manage_databases @action = ''ADD'', @database_name = ''AdventureWorks'', @collection_type = ''INDEX'';
  
  -- Remove a database from query store collection
  EXECUTE system.manage_databases @action = ''REMOVE'', @database_name = ''AdventureWorks'', @collection_type = ''QUERY_STORE'';
  
  -- List all databases in collection
  EXECUTE system.manage_databases @action = ''LIST'';';
            
            RETURN;
        END;
        
        IF @action IS NULL
        OR @action NOT IN (N'ADD', N'REMOVE', N'LIST')
        BEGIN
            RAISERROR(N'@action must be ADD, REMOVE, or LIST', 11, 1) WITH NOWAIT;
            RETURN;
        END;
        
        IF @action IN (N'ADD', N'REMOVE')
        AND (@database_name IS NULL OR @collection_type IS NULL)
        BEGIN
            RAISERROR(N'@database_name and @collection_type are required for ADD and REMOVE actions', 11, 1) WITH NOWAIT;
            RETURN;
        END;
        
        IF @collection_type IS NOT NULL
        AND NOT EXISTS
        (
            SELECT
                1
            FROM @collection_types AS ct
            WHERE ct.type_name = @collection_type
        )
        BEGIN
            RAISERROR(N'@collection_type must be INDEX, QUERY_STORE, or ALL', 11, 1) WITH NOWAIT;
            RETURN;
        END;
        
        /*
        Validate database exists and is accessible
        */
        IF @database_name IS NOT NULL
        BEGIN
            SELECT
                @database_id = d.database_id,
                @online_status = CASE WHEN d.state = 0 THEN 1 ELSE 0 END,
                @readonly_status = CASE 
                                      WHEN d.is_read_only = 1 
                                      OR d.user_access = 1 -- Single user
                                      OR d.state = 1 -- Restoring
                                      OR d.state = 2 -- Recovering
                                      OR d.state = 3 -- Recovery pending
                                      OR d.state = 4 -- Suspect
                                      OR d.state = 5 -- Emergency
                                      OR d.state = 6 -- Offline
                                      OR d.state = 7 -- Copying
                                      OR d.state_desc = N'STANDBY' -- Log restore with standby
                                   THEN 1
                                   ELSE 0
                                END
            FROM sys.databases AS d
            WHERE d.name = @database_name;
            
            IF @database_id IS NULL
            BEGIN
                RAISERROR(N'Database %s does not exist', 11, 1, @database_name) WITH NOWAIT;
                RETURN;
            END;
            
            IF @online_status = 0
            BEGIN
                RAISERROR(N'Database %s is not online', 11, 1, @database_name) WITH NOWAIT;
                RETURN;
            END;
        END;
        
        /*
        Process the requested action
        */
        IF @action = N'ADD'
        BEGIN
            IF @collection_type = N'ALL'
            BEGIN
                MERGE system.database_collection_config AS target
                USING 
                (
                    SELECT
                        type_name
                    FROM @collection_types
                    WHERE type_name <> N'ALL'
                ) AS source
                ON target.database_name = @database_name
                AND target.collection_type = source.type_name
                WHEN MATCHED THEN
                    UPDATE SET
                        active = 1,
                        added_date = SYSDATETIME()
                WHEN NOT MATCHED THEN
                    INSERT
                    (
                        database_name,
                        collection_type,
                        added_date,
                        active
                    )
                    VALUES
                    (
                        @database_name,
                        source.type_name,
                        SYSDATETIME(),
                        1
                    );
            END;
            ELSE
            BEGIN
                MERGE system.database_collection_config AS target
                USING 
                (
                    SELECT
                        @database_name AS database_name,
                        @collection_type AS collection_type
                ) AS source
                ON target.database_name = source.database_name
                AND target.collection_type = source.collection_type
                WHEN MATCHED THEN
                    UPDATE SET
                        active = 1,
                        added_date = SYSDATETIME()
                WHEN NOT MATCHED THEN
                    INSERT
                    (
                        database_name,
                        collection_type,
                        added_date,
                        active
                    )
                    VALUES
                    (
                        source.database_name,
                        source.collection_type,
                        SYSDATETIME(),
                        1
                    );
            END;
            
            IF @debug = 1
            BEGIN
                RAISERROR(N'Added database %s for %s collection', 0, 1, @database_name, @collection_type) WITH NOWAIT;
            END;
        END;
        ELSE IF @action = N'REMOVE'
        BEGIN
            IF @collection_type = N'ALL'
            BEGIN
                UPDATE
                    system.database_collection_config
                SET
                    active = 0
                WHERE
                    database_name = @database_name;
            END;
            ELSE
            BEGIN
                UPDATE
                    system.database_collection_config
                SET
                    active = 0
                WHERE
                    database_name = @database_name
                AND collection_type = @collection_type;
            END;
            
            IF @debug = 1
            BEGIN
                RAISERROR(N'Removed database %s from %s collection', 0, 1, @database_name, @collection_type) WITH NOWAIT;
            END;
        END;
        ELSE IF @action = N'LIST'
        BEGIN
            -- Extra validation checks for query store readiness
            IF @collection_type = N'QUERY_STORE' OR @collection_type IS NULL
            BEGIN
                SELECT
                    @sql = N'
                    WITH QueryStoreStatus AS
                    (
                        SELECT
                            database_name = DB_NAME(d.database_id),
                            query_store_enabled = CAST(ISNULL(DATABASEPROPERTYEX(DB_NAME(d.database_id), ''IsQueryStoreOn''), 0) AS BIT),
                            query_store_readonly = CAST(0 AS BIT)
                        FROM sys.databases AS d
                        WHERE d.state = 0 -- Online databases only
                        AND d.database_id > 4 -- Exclude system databases
                        AND d.is_read_only = 0
                    )
                    UPDATE qs
                    SET query_store_readonly = 
                        (
                            SELECT
                                CONVERT(BIT, 
                                    CASE
                                        WHEN actual_state = 1 THEN 0
                                        WHEN actual_state = 2 THEN 0
                                        WHEN actual_state = 3 THEN 1
                                        ELSE 1
                                    END
                                )
                            FROM (
                                SELECT
                                    actual_state = TRY_CAST(actual_state AS INTEGER)
                                FROM
                                (
                                    SELECT
                                        actual_state
                                    FROM OPENDATASOURCE(
                                        ''SQLNCLI'',
                                        ''Data Source=(local);Integrated Security=SSPI'').' 
                                        + QUOTENAME(qs.database_name) 
                                        + '.sys.database_query_store_options
                                ) AS x
                            ) AS y
                        )
                    FROM QueryStoreStatus AS qs
                    OPTION (RECOMPILE);
                    
                    SELECT
                        database_name,
                        query_store_enabled,
                        query_store_readonly
                    FROM QueryStoreStatus;
                    ';
            END;
            
            IF @sql <> N''
            BEGIN
                BEGIN TRY
                    EXECUTE sys.sp_executesql @sql;
                END TRY
                BEGIN CATCH
                    -- Gracefully handle query store check failures
                    RAISERROR(N'Could not validate Query Store status: %s', 0, 1, ERROR_MESSAGE()) WITH NOWAIT;
                END CATCH;
            END;
            
            SELECT
                dc.database_name,
                dc.collection_type,
                dc.added_date,
                dc.active,
                database_exists = CASE WHEN DB_ID(dc.database_name) IS NOT NULL THEN 1 ELSE 0 END,
                db_online = CASE WHEN DB_ID(dc.database_name) IS NOT NULL 
                              AND EXISTS (
                                 SELECT 1 FROM sys.databases 
                                 WHERE name = dc.database_name 
                                 AND state = 0
                              ) 
                              THEN 1 ELSE 0 END,
                db_readonly = CASE WHEN DB_ID(dc.database_name) IS NOT NULL 
                               AND EXISTS (
                                  SELECT 1 FROM sys.databases 
                                  WHERE name = dc.database_name 
                                  AND (
                                     is_read_only = 1
                                     OR user_access = 1
                                     OR state > 0
                                     OR state_desc = N'STANDBY'
                                  )
                               ) 
                               THEN 1 ELSE 0 END
            FROM system.database_collection_config AS dc
            WHERE dc.active = 1
            AND (@collection_type IS NULL OR dc.collection_type = @collection_type)
            ORDER BY
                dc.database_name,
                dc.collection_type;
        END;
    END TRY
    BEGIN CATCH
        SET @error_number = ERROR_NUMBER();
        SET @error_severity = ERROR_SEVERITY();
        SET @error_state = ERROR_STATE();
        SET @error_line = ERROR_LINE();
        SET @error_message = ERROR_MESSAGE();
        
        RAISERROR(N'Error %d at line %d: %s', 11, 1, @error_number, @error_line, @error_message) WITH NOWAIT;
        THROW;
    END CATCH;
END;
GO

/*
 ██████╗ ██╗   ██╗███████╗██████╗ ██╗   ██╗    ███████╗████████╗ ██████╗ ██████╗ ███████╗
██╔═══██╗██║   ██║██╔════╝██╔══██╗╚██╗ ██╔╝    ██╔════╝╚══██╔══╝██╔═══██╗██╔══██╗██╔════╝
██║   ██║██║   ██║█████╗  ██████╔╝ ╚████╔╝     ███████╗   ██║   ██║   ██║██████╔╝█████╗  
██║▄▄ ██║██║   ██║██╔══╝  ██╔══██╗  ╚██╔╝      ╚════██║   ██║   ██║   ██║██╔══██╗██╔══╝  
╚██████╔╝╚██████╔╝███████╗██║  ██║   ██║       ███████║   ██║   ╚██████╔╝██║  ██║███████╗
 ╚══▀▀═╝  ╚═════╝ ╚══════╝╚═╝  ╚═╝   ╚═╝       ╚══════╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚══════╝
                                                                                          
Copyright (c) Darling Data, LLC
https://www.erikdarling.com/
*/

CREATE OR ALTER PROCEDURE
    collection.collect_query_store
(
    @debug BIT = 0, /*Print debugging information*/
    @use_database_list BIT = 1, /*Use database list from system.database_collection_config*/
    @include_databases NVARCHAR(MAX) = NULL, /*Optional: Comma-separated list of databases to include*/
    @exclude_databases NVARCHAR(MAX) = NULL, /*Optional: Comma-separated list of databases to exclude*/
    @exclude_system_databases BIT = 1, /*Exclude system databases*/
    @include_query_text BIT = 1, /*Include query text*/
    @include_query_plans BIT = 0, /*Include query plans (can be expensive)*/
    @include_runtime_stats BIT = 1, /*Include runtime statistics*/
    @include_wait_stats BIT = 1, /*Include wait statistics*/
    @min_cpu_time_ms INTEGER = 1000, /*Minimum CPU time threshold*/
    @min_logical_io_reads INTEGER = 1000, /*Minimum logical IO reads threshold*/
    @min_logical_io_writes INTEGER = 0, /*Minimum logical IO writes threshold*/
    @min_physical_io_reads INTEGER = 0, /*Minimum physical IO reads threshold*/
    @min_clr_time_ms INTEGER = 0, /*Minimum CLR time threshold*/
    @min_dop INTEGER = 0, /*Minimum degree of parallelism threshold*/
    @min_query_max_used_memory INTEGER = 0, /*Minimum memory grant threshold*/
    @min_rowcount INTEGER = 0, /*Minimum row count threshold*/
    @min_tempdb_space INTEGER = 0, /*Minimum tempdb space used threshold*/
    @min_log_bytes_used INTEGER = 0, /*Minimum log bytes used threshold*/
    @start_time DATETIME2(7) = NULL, /*Query runtime start time filter*/
    @end_time DATETIME2(7) = NULL, /*Query runtime end time filter*/
    @help BIT = 0 /*Prints help information*/
)
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
    
    BEGIN TRY
        /*
        Variable declarations
        */
        DECLARE
            @sql NVARCHAR(MAX) = N'',
            @database_name NVARCHAR(128) = N'',
            @collection_count INTEGER = 0,
            @error_number INTEGER = 0,
            @error_severity INTEGER = 0,
            @error_state INTEGER = 0,
            @error_line INTEGER = 0,
            @error_message NVARCHAR(4000) = N'',
            @collection_starting DATETIME2(7) = SYSDATETIME(),
            @collection_ending DATETIME2(7) = NULL;
            
        DECLARE
            @include_database_list TABLE
            (
                database_name NVARCHAR(128) NOT NULL PRIMARY KEY
            );
            
        DECLARE
            @exclude_database_list TABLE
            (
                database_name NVARCHAR(128) NOT NULL PRIMARY KEY
            );
            
        DECLARE
            @database_list TABLE
            (
                database_id INTEGER NOT NULL PRIMARY KEY,
                database_name NVARCHAR(128) NOT NULL,
                qs_enabled BIT NOT NULL DEFAULT 0,
                qs_readonly BIT NOT NULL DEFAULT 0
            );
            
        /*
        Parameter validation
        */
        IF @help = 1
        BEGIN
            SELECT
                help = N'This procedure collects Query Store data from databases.
                
Parameters:
  @debug = 1 to print detailed information, 0 for normal operation
  @use_database_list = 1 to use database list from system.database_collection_config, 0 to use include/exclude lists
  @include_databases = Comma-separated list of databases to include (used if @use_database_list = 0)
  @exclude_databases = Comma-separated list of databases to exclude
  @exclude_system_databases = 1 to exclude system databases (master, model, msdb, tempdb)
  @include_query_text = 1 to include query text, 0 to exclude
  @include_query_plans = 1 to include query plans, 0 to exclude (can be expensive)
  @include_runtime_stats = 1 to include runtime statistics, 0 to exclude
  @include_wait_stats = 1 to include wait statistics, 0 to exclude
  @min_cpu_time_ms = Minimum CPU time threshold (default 1000ms)
  @min_logical_io_reads = Minimum logical IO reads threshold (default 1000)
  @min_logical_io_writes = Minimum logical IO writes threshold (default 0)
  @min_physical_io_reads = Minimum physical IO reads threshold (default 0)
  @min_clr_time_ms = Minimum CLR time threshold (default 0)
  @min_dop = Minimum degree of parallelism threshold (default 0)
  @min_query_max_used_memory = Minimum memory grant threshold (default 0)
  @min_rowcount = Minimum row count threshold (default 0)
  @min_tempdb_space = Minimum tempdb space used threshold (default 0)
  @min_log_bytes_used = Minimum log bytes used threshold (default 0)
  @start_time = Query runtime start time filter (default NULL for all time)
  @end_time = Query runtime end time filter (default NULL for all time)
  @help = 1 to show this help information

Example usage:
  EXECUTE collection.collect_query_store @debug = 1, @min_cpu_time_ms = 5000;';
            
            RETURN;
        END;
        
        IF @start_time IS NOT NULL AND @end_time IS NOT NULL
        AND @start_time > @end_time
        BEGIN
            RAISERROR(N'@start_time cannot be greater than @end_time', 11, 1) WITH NOWAIT;
            RETURN;
        END;
        
        /*
        Build database lists
        */
        IF @use_database_list = 1
        BEGIN
            INSERT @include_database_list
            (
                database_name
            )
            SELECT
                database_name
            FROM system.database_collection_config
            WHERE collection_type = N'QUERY_STORE'
            AND active = 1;
            
            IF @debug = 1
            BEGIN
                SELECT
                    list_source = N'Using configured database list',
                    database_count = COUNT(*)
                FROM @include_database_list;
            END;
        END;
        ELSE IF @include_databases IS NOT NULL
        BEGIN
            INSERT @include_database_list
            (
                database_name
            )
            SELECT
                database_name = LTRIM(RTRIM(value))
            FROM STRING_SPLIT(@include_databases, N',');
            
            IF @debug = 1
            BEGIN
                SELECT
                    list_source = N'Using @include_databases parameter',
                    database_count = COUNT(*)
                FROM @include_database_list;
            END;
        END;
        
        IF @exclude_databases IS NOT NULL
        BEGIN
            INSERT @exclude_database_list
            (
                database_name
            )
            SELECT
                database_name = LTRIM(RTRIM(value))
            FROM STRING_SPLIT(@exclude_databases, N',');
            
            IF @debug = 1
            BEGIN
                SELECT
                    list_source = N'Using @exclude_databases parameter',
                    database_count = COUNT(*)
                FROM @exclude_database_list;
            END;
        END;
        
        /*
        Build final database list
        */
        INSERT @database_list
        (
            database_id,
            database_name,
            qs_enabled,
            qs_readonly
        )
        SELECT
            d.database_id,
            database_name = d.name,
            qs_enabled = ISNULL(CONVERT(BIT, ISNULL(DATABASEPROPERTYEX(d.name, 'IsQueryStoreOn'), 0)), 0),
            qs_readonly = 0
        FROM sys.databases AS d
        WHERE d.state = 0 -- Only online databases
        AND 
        (
            -- Use include list if specified
            (
                EXISTS (SELECT 1 FROM @include_database_list)
                AND d.name IN (SELECT database_name FROM @include_database_list)
            )
            OR 
            (
                -- Otherwise use all databases except excluded ones
                NOT EXISTS (SELECT 1 FROM @include_database_list)
                AND 
                (
                    -- Skip system databases if specified
                    (@exclude_system_databases = 0 OR d.database_id > 4)
                    -- Skip excluded databases
                    AND d.name NOT IN (SELECT database_name FROM @exclude_database_list)
                )
            )
        )
        AND d.is_read_only = 0;
        
        /*
        Validate query store status
        */
        SELECT
            @sql = N'
            BEGIN TRY
                UPDATE dl
                SET qs_enabled = ISNULL(CONVERT(BIT, ISNULL(DATABASEPROPERTYEX(dl.database_name, ''IsQueryStoreOn''), 0)), 0),
                    qs_readonly = 
                    (
                        SELECT
                            CONVERT(BIT, 
                                CASE
                                    WHEN actual_state = 1 THEN 0
                                    WHEN actual_state = 2 THEN 0
                                    WHEN actual_state = 3 THEN 1
                                    ELSE 1
                                END
                            )
                        FROM (
                            SELECT
                                actual_state = TRY_CAST(actual_state AS INTEGER)
                            FROM
                            (
                                SELECT
                                    actual_state
                                FROM OPENDATASOURCE(
                                    ''SQLNCLI'',
                                    ''Data Source=(local);Integrated Security=SSPI'').'
                                    + QUOTENAME(dl.database_name) 
                                    + '.sys.database_query_store_options
                            ) AS x
                        ) AS y
                    )
                FROM @database_list AS dl
                OPTION (RECOMPILE);
            END TRY
            BEGIN CATCH
                -- Ignore errors because we will recheck individual databases
            END CATCH;
            ';
                    
        EXECUTE sys.sp_executesql 
            @sql,
            N'@database_list @database_list READONLY',
            @database_list;
        
        -- Remove databases with query store disabled
        DELETE 
            @database_list
        WHERE
            qs_enabled = 0
        OR  qs_readonly = 1;
        
        IF @debug = 1
        BEGIN
            SELECT
                db_list = N'Final database list',
                dl.database_id,
                dl.database_name,
                dl.qs_enabled,
                dl.qs_readonly
            FROM @database_list AS dl
            ORDER BY
                dl.database_name;
                
            IF NOT EXISTS (SELECT 1 FROM @database_list)
            BEGIN
                RAISERROR(N'No databases with active query store found, collection skipped', 11, 1) WITH NOWAIT;
                RETURN;
            END;
        END;
        
        /*
        Create collection tables if they don't exist
        */
        IF OBJECT_ID('collection.query_store_queries') IS NULL
        BEGIN
            CREATE TABLE
                collection.query_store_queries
            (
                collection_time DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
                database_name NVARCHAR(128) NOT NULL,
                query_id BIGINT NOT NULL,
                query_text_id BIGINT NOT NULL,
                query_hash BINARY(8) NULL,
                query_parameterization_type_desc NVARCHAR(60) NULL,
                initial_compile_start_time DATETIME2(7) NULL,
                last_compile_start_time DATETIME2(7) NULL,
                last_execution_time DATETIME2(7) NULL,
                object_id BIGINT NULL,
                object_name NVARCHAR(256) NULL,
                is_internal_query BIT NULL,
                query_text NVARCHAR(MAX) NULL,
                INDEX CIX_query_store_queries
                (
                    collection_time,
                    database_name,
                    query_id
                )
            );
            
            IF @debug = 1
            BEGIN
                RAISERROR(N'Created collection.query_store_queries', 0, 1) WITH NOWAIT;
            END;
        END;
        
        IF OBJECT_ID('collection.query_store_plans') IS NULL
        BEGIN
            CREATE TABLE
                collection.query_store_plans
            (
                collection_time DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
                database_name NVARCHAR(128) NOT NULL,
                plan_id BIGINT NOT NULL,
                query_id BIGINT NOT NULL,
                plan_group_id BIGINT NULL,
                engine_version NVARCHAR(32) NULL,
                compatibility_level INTEGER NULL,
                query_plan_hash BINARY(8) NULL,
                query_plan XML NULL,
                is_online_index_plan BIT NULL,
                is_trivial_plan BIT NULL,
                is_parallel_plan BIT NULL,
                is_forced_plan BIT NULL,
                force_failure_count BIGINT NULL,
                last_force_failure_reason_desc NVARCHAR(128) NULL,
                count_compiles BIGINT NULL,
                initial_compile_start_time DATETIME2(7) NULL,
                last_compile_start_time DATETIME2(7) NULL,
                last_execution_time DATETIME2(7) NULL,
                INDEX CIX_query_store_plans
                (
                    collection_time,
                    database_name,
                    plan_id
                )
            );
            
            IF @debug = 1
            BEGIN
                RAISERROR(N'Created collection.query_store_plans', 0, 1) WITH NOWAIT;
            END;
        END;
        
        IF OBJECT_ID('collection.query_store_runtime_stats') IS NULL
        BEGIN
            CREATE TABLE
                collection.query_store_runtime_stats
            (
                collection_time DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
                database_name NVARCHAR(128) NOT NULL,
                runtime_stats_id BIGINT NOT NULL,
                plan_id BIGINT NOT NULL,
                runtime_stats_interval_id BIGINT NOT NULL,
                start_time DATETIME2(7) NULL,
                end_time DATETIME2(7) NULL,
                execution_type_desc NVARCHAR(60) NULL,
                count_executions BIGINT NULL,
                cpu_time_min BIGINT NULL,
                cpu_time_max BIGINT NULL,
                cpu_time_avg BIGINT NULL,
                duration_min BIGINT NULL,
                duration_max BIGINT NULL,
                duration_avg BIGINT NULL,
                physical_io_reads_min BIGINT NULL,
                physical_io_reads_max BIGINT NULL,
                physical_io_reads_avg BIGINT NULL,
                logical_io_reads_min BIGINT NULL,
                logical_io_reads_max BIGINT NULL,
                logical_io_reads_avg BIGINT NULL,
                logical_io_writes_min BIGINT NULL,
                logical_io_writes_max BIGINT NULL,
                logical_io_writes_avg BIGINT NULL,
                clr_time_min BIGINT NULL,
                clr_time_max BIGINT NULL,
                clr_time_avg BIGINT NULL,
                dop_min BIGINT NULL,
                dop_max BIGINT NULL,
                dop_avg BIGINT NULL,
                query_max_used_memory_min BIGINT NULL,
                query_max_used_memory_max BIGINT NULL,
                query_max_used_memory_avg BIGINT NULL,
                rowcount_min BIGINT NULL,
                rowcount_max BIGINT NULL,
                rowcount_avg BIGINT NULL,
                tempdb_space_used_min BIGINT NULL,
                tempdb_space_used_max BIGINT NULL,
                tempdb_space_used_avg BIGINT NULL,
                log_bytes_used_min BIGINT NULL,
                log_bytes_used_max BIGINT NULL,
                log_bytes_used_avg BIGINT NULL,
                memory_consumption_min BIGINT NULL,
                memory_consumption_max BIGINT NULL,
                memory_consumption_avg BIGINT NULL,
                NUM_PHYSICAL_IO_READS BIGINT NULL,
                INDEX CIX_query_store_runtime_stats
                (
                    collection_time,
                    database_name,
                    runtime_stats_id
                )
            );
            
            IF @debug = 1
            BEGIN
                RAISERROR(N'Created collection.query_store_runtime_stats', 0, 1) WITH NOWAIT;
            END;
        END;
        
        IF OBJECT_ID('collection.query_store_wait_stats') IS NULL
        BEGIN
            CREATE TABLE
                collection.query_store_wait_stats
            (
                collection_time DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
                database_name NVARCHAR(128) NOT NULL,
                wait_stats_id BIGINT NOT NULL,
                plan_id BIGINT NOT NULL,
                runtime_stats_interval_id BIGINT NOT NULL,
                wait_category_desc NVARCHAR(60) NULL,
                execution_type_desc NVARCHAR(60) NULL,
                total_query_wait_time_ms BIGINT NULL,
                avg_query_wait_time_ms BIGINT NULL,
                last_query_wait_time_ms BIGINT NULL,
                min_query_wait_time_ms BIGINT NULL,
                max_query_wait_time_ms BIGINT NULL,
                stdev_query_wait_time_ms BIGINT NULL,
                INDEX CIX_query_store_wait_stats
                (
                    collection_time,
                    database_name,
                    wait_stats_id
                )
            );
            
            IF @debug = 1
            BEGIN
                RAISERROR(N'Created collection.query_store_wait_stats', 0, 1) WITH NOWAIT;
            END;
        END;
        
        /*
        Loop through each database and collect query store data
        */
        DECLARE
            db_cursor CURSOR LOCAL FORWARD_ONLY STATIC READ_ONLY
        FOR
            SELECT
                database_name
            FROM @database_list
            ORDER BY
                database_name;
                
        OPEN db_cursor;
        
        FETCH NEXT FROM
            db_cursor
        INTO
            @database_name;
            
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @collection_count = @collection_count + 1;
            
            IF @debug = 1
            BEGIN
                RAISERROR(N'Processing database %s (%d of %d)', 0, 1, 
                @database_name, @collection_count, 
                (SELECT COUNT(*) FROM @database_list)) WITH NOWAIT;
            END;
            
            BEGIN TRY
                /*
                Collect query store data
                */
                
                -- Query and text collection
                IF @include_query_text = 1
                BEGIN
                    SELECT
                        @sql = N'
                        INSERT
                            collection.query_store_queries
                        (
                            collection_time,
                            database_name,
                            query_id,
                            query_text_id,
                            query_hash,
                            query_parameterization_type_desc,
                            initial_compile_start_time,
                            last_compile_start_time,
                            last_execution_time,
                            object_id,
                            object_name,
                            is_internal_query,
                            query_text
                        )
                        SELECT
                            collection_time = SYSDATETIME(),
                            database_name = N''' + @database_name + N''',
                            q.query_id,
                            q.query_text_id,
                            q.query_hash,
                            q.query_parameterization_type_desc,
                            q.initial_compile_start_time,
                            q.last_compile_start_time,
                            q.last_execution_time,
                            q.object_id,
                            object_name = QUOTENAME(ISNULL(OBJECT_SCHEMA_NAME(q.object_id, DB_ID(''' + @database_name + N''')), N'''')) + N''.'' + 
                                       QUOTENAME(ISNULL(OBJECT_NAME(q.object_id, DB_ID(''' + @database_name + N''')), N'''')),
                            q.is_internal_query,
                            query_text = qt.query_sql_text
                        FROM OPENDATASOURCE(
                            ''SQLNCLI'',
                            ''Data Source=(local);Integrated Security=SSPI'').'
                            + QUOTENAME(@database_name) 
                            + '.sys.query_store_query AS q
                        JOIN OPENDATASOURCE(
                            ''SQLNCLI'',
                            ''Data Source=(local);Integrated Security=SSPI'').'
                            + QUOTENAME(@database_name) 
                            + '.sys.query_store_query_text AS qt
                          ON q.query_text_id = qt.query_text_id
                        JOIN OPENDATASOURCE(
                            ''SQLNCLI'',
                            ''Data Source=(local);Integrated Security=SSPI'').'
                            + QUOTENAME(@database_name) 
                            + '.sys.query_store_plan AS p
                          ON q.query_id = p.query_id
                        JOIN OPENDATASOURCE(
                            ''SQLNCLI'',
                            ''Data Source=(local);Integrated Security=SSPI'').'
                            + QUOTENAME(@database_name) 
                            + '.sys.query_store_runtime_stats AS rs
                          ON p.plan_id = rs.plan_id
                        WHERE rs.avg_cpu_time >= ' + CONVERT(NVARCHAR(20), @min_cpu_time_ms) + N' * 1000
                        OR rs.avg_logical_io_reads >= ' + CONVERT(NVARCHAR(20), @min_logical_io_reads) + N'
                        OR rs.avg_logical_io_writes >= ' + CONVERT(NVARCHAR(20), @min_logical_io_writes) + N'
                        OR rs.avg_physical_io_reads >= ' + CONVERT(NVARCHAR(20), @min_physical_io_reads) + N'
                        OR rs.avg_clr_time >= ' + CONVERT(NVARCHAR(20), @min_clr_time_ms) + N' * 1000
                        OR rs.avg_dop >= ' + CONVERT(NVARCHAR(20), @min_dop) + N'
                        OR rs.avg_query_max_used_memory >= ' + CONVERT(NVARCHAR(20), @min_query_max_used_memory) + N'
                        OR rs.avg_rowcount >= ' + CONVERT(NVARCHAR(20), @min_rowcount) + N'
                        OR rs.avg_tempdb_space_used >= ' + CONVERT(NVARCHAR(20), @min_tempdb_space) + N'
                        OR rs.avg_log_bytes_used >= ' + CONVERT(NVARCHAR(20), @min_log_bytes_used) + N'
                        ';
                        
                        IF @start_time IS NOT NULL
                        BEGIN
                            SET @sql = @sql + N'
                            AND rs.last_execution_time >= ''' + CONVERT(NVARCHAR(34), @start_time, 126) + N'''';
                        END;
                        
                        IF @end_time IS NOT NULL
                        BEGIN
                            SET @sql = @sql + N'
                            AND rs.last_execution_time <= ''' + CONVERT(NVARCHAR(34), @end_time, 126) + N'''';
                        END;
                        
                        SET @sql = @sql + N'
                        GROUP BY
                            q.query_id,
                            q.query_text_id,
                            q.query_hash,
                            q.query_parameterization_type_desc,
                            q.initial_compile_start_time,
                            q.last_compile_start_time,
                            q.last_execution_time,
                            q.object_id,
                            q.is_internal_query,
                            qt.query_sql_text;
                        ';
                        
                    EXECUTE sys.sp_executesql @sql;
                    
                    IF @debug = 1
                    BEGIN
                        RAISERROR(N'Collected %d queries from %s', 0, 1, @@ROWCOUNT, @database_name) WITH NOWAIT;
                    END;
                END;
                
                -- Plan collection
                IF @include_query_plans = 1
                BEGIN
                    SELECT
                        @sql = N'
                        INSERT
                            collection.query_store_plans
                        (
                            collection_time,
                            database_name,
                            plan_id,
                            query_id,
                            plan_group_id,
                            engine_version,
                            compatibility_level,
                            query_plan_hash,
                            query_plan,
                            is_online_index_plan,
                            is_trivial_plan,
                            is_parallel_plan,
                            is_forced_plan,
                            force_failure_count,
                            last_force_failure_reason_desc,
                            count_compiles,
                            initial_compile_start_time,
                            last_compile_start_time,
                            last_execution_time
                        )
                        SELECT
                            collection_time = SYSDATETIME(),
                            database_name = N''' + @database_name + N''',
                            p.plan_id,
                            p.query_id,
                            p.plan_group_id,
                            p.engine_version,
                            p.compatibility_level,
                            p.query_plan_hash,
                            p.query_plan,
                            p.is_online_index_plan,
                            p.is_trivial_plan,
                            p.is_parallel_plan,
                            p.is_forced_plan,
                            p.force_failure_count,
                            p.last_force_failure_reason_desc,
                            p.count_compiles,
                            p.initial_compile_start_time,
                            p.last_compile_start_time,
                            p.last_execution_time
                        FROM OPENDATASOURCE(
                            ''SQLNCLI'',
                            ''Data Source=(local);Integrated Security=SSPI'').'
                            + QUOTENAME(@database_name) 
                            + '.sys.query_store_plan AS p
                        JOIN OPENDATASOURCE(
                            ''SQLNCLI'',
                            ''Data Source=(local);Integrated Security=SSPI'').'
                            + QUOTENAME(@database_name) 
                            + '.sys.query_store_runtime_stats AS rs
                          ON p.plan_id = rs.plan_id
                        WHERE rs.avg_cpu_time >= ' + CONVERT(NVARCHAR(20), @min_cpu_time_ms) + N' * 1000
                        OR rs.avg_logical_io_reads >= ' + CONVERT(NVARCHAR(20), @min_logical_io_reads) + N'
                        OR rs.avg_logical_io_writes >= ' + CONVERT(NVARCHAR(20), @min_logical_io_writes) + N'
                        OR rs.avg_physical_io_reads >= ' + CONVERT(NVARCHAR(20), @min_physical_io_reads) + N'
                        OR rs.avg_clr_time >= ' + CONVERT(NVARCHAR(20), @min_clr_time_ms) + N' * 1000
                        OR rs.avg_dop >= ' + CONVERT(NVARCHAR(20), @min_dop) + N'
                        OR rs.avg_query_max_used_memory >= ' + CONVERT(NVARCHAR(20), @min_query_max_used_memory) + N'
                        OR rs.avg_rowcount >= ' + CONVERT(NVARCHAR(20), @min_rowcount) + N'
                        OR rs.avg_tempdb_space_used >= ' + CONVERT(NVARCHAR(20), @min_tempdb_space) + N'
                        OR rs.avg_log_bytes_used >= ' + CONVERT(NVARCHAR(20), @min_log_bytes_used) + N'
                        ';
                        
                        IF @start_time IS NOT NULL
                        BEGIN
                            SET @sql = @sql + N'
                            AND rs.last_execution_time >= ''' + CONVERT(NVARCHAR(34), @start_time, 126) + N'''';
                        END;
                        
                        IF @end_time IS NOT NULL
                        BEGIN
                            SET @sql = @sql + N'
                            AND rs.last_execution_time <= ''' + CONVERT(NVARCHAR(34), @end_time, 126) + N'''';
                        END;
                        
                        SET @sql = @sql + N'
                        GROUP BY
                            p.plan_id,
                            p.query_id,
                            p.plan_group_id,
                            p.engine_version,
                            p.compatibility_level,
                            p.query_plan_hash,
                            p.query_plan,
                            p.is_online_index_plan,
                            p.is_trivial_plan,
                            p.is_parallel_plan,
                            p.is_forced_plan,
                            p.force_failure_count,
                            p.last_force_failure_reason_desc,
                            p.count_compiles,
                            p.initial_compile_start_time,
                            p.last_compile_start_time,
                            p.last_execution_time;
                        ';
                        
                    EXECUTE sys.sp_executesql @sql;
                    
                    IF @debug = 1
                    BEGIN
                        RAISERROR(N'Collected %d plans from %s', 0, 1, @@ROWCOUNT, @database_name) WITH NOWAIT;
                    END;
                END;
                
                -- Runtime stats collection
                IF @include_runtime_stats = 1
                BEGIN
                    SELECT
                        @sql = N'
                        INSERT
                            collection.query_store_runtime_stats
                        (
                            collection_time,
                            database_name,
                            runtime_stats_id,
                            plan_id,
                            runtime_stats_interval_id,
                            start_time,
                            end_time,
                            execution_type_desc,
                            count_executions,
                            cpu_time_min,
                            cpu_time_max,
                            cpu_time_avg,
                            duration_min,
                            duration_max,
                            duration_avg,
                            physical_io_reads_min,
                            physical_io_reads_max,
                            physical_io_reads_avg,
                            logical_io_reads_min,
                            logical_io_reads_max,
                            logical_io_reads_avg,
                            logical_io_writes_min,
                            logical_io_writes_max,
                            logical_io_writes_avg,
                            clr_time_min,
                            clr_time_max,
                            clr_time_avg,
                            dop_min,
                            dop_max,
                            dop_avg,
                            query_max_used_memory_min,
                            query_max_used_memory_max,
                            query_max_used_memory_avg,
                            rowcount_min,
                            rowcount_max,
                            rowcount_avg,
                            tempdb_space_used_min,
                            tempdb_space_used_max,
                            tempdb_space_used_avg,
                            log_bytes_used_min,
                            log_bytes_used_max,
                            log_bytes_used_avg,
                            memory_consumption_min,
                            memory_consumption_max,
                            memory_consumption_avg,
                            NUM_PHYSICAL_IO_READS
                        )
                        SELECT
                            collection_time = SYSDATETIME(),
                            database_name = N''' + @database_name + N''',
                            rs.runtime_stats_id,
                            rs.plan_id,
                            rs.runtime_stats_interval_id,
                            i.start_time,
                            i.end_time,
                            rs.execution_type_desc,
                            rs.count_executions,
                            rs.min_cpu_time,
                            rs.max_cpu_time,
                            rs.avg_cpu_time,
                            rs.min_duration,
                            rs.max_duration,
                            rs.avg_duration,
                            rs.min_physical_io_reads,
                            rs.max_physical_io_reads,
                            rs.avg_physical_io_reads,
                            rs.min_logical_io_reads,
                            rs.max_logical_io_reads,
                            rs.avg_logical_io_reads,
                            rs.min_logical_io_writes,
                            rs.max_logical_io_writes,
                            rs.avg_logical_io_writes,
                            rs.min_clr_time,
                            rs.max_clr_time,
                            rs.avg_clr_time,
                            rs.min_dop,
                            rs.max_dop,
                            rs.avg_dop,
                            rs.min_query_max_used_memory,
                            rs.max_query_max_used_memory,
                            rs.avg_query_max_used_memory,
                            rs.min_rowcount,
                            rs.max_rowcount,
                            rs.avg_rowcount,
                            rs.min_tempdb_space_used,
                            rs.max_tempdb_space_used,
                            rs.avg_tempdb_space_used,
                            rs.min_log_bytes_used,
                            rs.max_log_bytes_used,
                            rs.avg_log_bytes_used,
                            rs.min_memory_consumption,
                            rs.max_memory_consumption,
                            rs.avg_memory_consumption,
                            rs.last_physical_io_reads
                        FROM OPENDATASOURCE(
                            ''SQLNCLI'',
                            ''Data Source=(local);Integrated Security=SSPI'').'
                            + QUOTENAME(@database_name) 
                            + '.sys.query_store_runtime_stats AS rs
                        JOIN OPENDATASOURCE(
                            ''SQLNCLI'',
                            ''Data Source=(local);Integrated Security=SSPI'').'
                            + QUOTENAME(@database_name) 
                            + '.sys.query_store_runtime_stats_interval AS i
                          ON rs.runtime_stats_interval_id = i.runtime_stats_interval_id
                        WHERE rs.avg_cpu_time >= ' + CONVERT(NVARCHAR(20), @min_cpu_time_ms) + N' * 1000
                        OR rs.avg_logical_io_reads >= ' + CONVERT(NVARCHAR(20), @min_logical_io_reads) + N'
                        OR rs.avg_logical_io_writes >= ' + CONVERT(NVARCHAR(20), @min_logical_io_writes) + N'
                        OR rs.avg_physical_io_reads >= ' + CONVERT(NVARCHAR(20), @min_physical_io_reads) + N'
                        OR rs.avg_clr_time >= ' + CONVERT(NVARCHAR(20), @min_clr_time_ms) + N' * 1000
                        OR rs.avg_dop >= ' + CONVERT(NVARCHAR(20), @min_dop) + N'
                        OR rs.avg_query_max_used_memory >= ' + CONVERT(NVARCHAR(20), @min_query_max_used_memory) + N'
                        OR rs.avg_rowcount >= ' + CONVERT(NVARCHAR(20), @min_rowcount) + N'
                        OR rs.avg_tempdb_space_used >= ' + CONVERT(NVARCHAR(20), @min_tempdb_space) + N'
                        OR rs.avg_log_bytes_used >= ' + CONVERT(NVARCHAR(20), @min_log_bytes_used) + N'
                        ';
                        
                        IF @start_time IS NOT NULL
                        BEGIN
                            SET @sql = @sql + N'
                            AND i.end_time >= ''' + CONVERT(NVARCHAR(34), @start_time, 126) + N'''';
                        END;
                        
                        IF @end_time IS NOT NULL
                        BEGIN
                            SET @sql = @sql + N'
                            AND i.start_time <= ''' + CONVERT(NVARCHAR(34), @end_time, 126) + N'''';
                        END;
                        
                    EXECUTE sys.sp_executesql @sql;
                    
                    IF @debug = 1
                    BEGIN
                        RAISERROR(N'Collected %d runtime stats from %s', 0, 1, @@ROWCOUNT, @database_name) WITH NOWAIT;
                    END;
                END;
                
                -- Wait stats collection
                IF @include_wait_stats = 1
                BEGIN
                    SELECT
                        @sql = N'
                        INSERT
                            collection.query_store_wait_stats
                        (
                            collection_time,
                            database_name,
                            wait_stats_id,
                            plan_id,
                            runtime_stats_interval_id,
                            wait_category_desc,
                            execution_type_desc,
                            total_query_wait_time_ms,
                            avg_query_wait_time_ms,
                            last_query_wait_time_ms,
                            min_query_wait_time_ms,
                            max_query_wait_time_ms,
                            stdev_query_wait_time_ms
                        )
                        SELECT
                            collection_time = SYSDATETIME(),
                            database_name = N''' + @database_name + N''',
                            ws.wait_stats_id,
                            ws.plan_id,
                            ws.runtime_stats_interval_id,
                            ws.wait_category_desc,
                            ws.execution_type_desc,
                            ws.total_query_wait_time_ms,
                            ws.avg_query_wait_time_ms,
                            ws.last_query_wait_time_ms,
                            ws.min_query_wait_time_ms,
                            ws.max_query_wait_time_ms,
                            ws.stdev_query_wait_time_ms
                        FROM OPENDATASOURCE(
                            ''SQLNCLI'',
                            ''Data Source=(local);Integrated Security=SSPI'').'
                            + QUOTENAME(@database_name) 
                            + '.sys.query_store_wait_stats AS ws
                        JOIN OPENDATASOURCE(
                            ''SQLNCLI'',
                            ''Data Source=(local);Integrated Security=SSPI'').'
                            + QUOTENAME(@database_name) 
                            + '.sys.query_store_runtime_stats AS rs
                          ON ws.plan_id = rs.plan_id
                          AND ws.runtime_stats_interval_id = rs.runtime_stats_interval_id
                        JOIN OPENDATASOURCE(
                            ''SQLNCLI'',
                            ''Data Source=(local);Integrated Security=SSPI'').'
                            + QUOTENAME(@database_name) 
                            + '.sys.query_store_runtime_stats_interval AS i
                          ON rs.runtime_stats_interval_id = i.runtime_stats_interval_id
                        WHERE rs.avg_cpu_time >= ' + CONVERT(NVARCHAR(20), @min_cpu_time_ms) + N' * 1000
                        OR rs.avg_logical_io_reads >= ' + CONVERT(NVARCHAR(20), @min_logical_io_reads) + N'
                        OR rs.avg_logical_io_writes >= ' + CONVERT(NVARCHAR(20), @min_logical_io_writes) + N'
                        OR rs.avg_physical_io_reads >= ' + CONVERT(NVARCHAR(20), @min_physical_io_reads) + N'
                        OR rs.avg_clr_time >= ' + CONVERT(NVARCHAR(20), @min_clr_time_ms) + N' * 1000
                        OR rs.avg_dop >= ' + CONVERT(NVARCHAR(20), @min_dop) + N'
                        OR rs.avg_query_max_used_memory >= ' + CONVERT(NVARCHAR(20), @min_query_max_used_memory) + N'
                        OR rs.avg_rowcount >= ' + CONVERT(NVARCHAR(20), @min_rowcount) + N'
                        OR rs.avg_tempdb_space_used >= ' + CONVERT(NVARCHAR(20), @min_tempdb_space) + N'
                        OR rs.avg_log_bytes_used >= ' + CONVERT(NVARCHAR(20), @min_log_bytes_used) + N'
                        ';
                        
                        IF @start_time IS NOT NULL
                        BEGIN
                            SET @sql = @sql + N'
                            AND i.end_time >= ''' + CONVERT(NVARCHAR(34), @start_time, 126) + N'''';
                        END;
                        
                        IF @end_time IS NOT NULL
                        BEGIN
                            SET @sql = @sql + N'
                            AND i.start_time <= ''' + CONVERT(NVARCHAR(34), @end_time, 126) + N'''';
                        END;
                        
                    EXECUTE sys.sp_executesql @sql;
                    
                    IF @debug = 1
                    BEGIN
                        RAISERROR(N'Collected %d wait stats from %s', 0, 1, @@ROWCOUNT, @database_name) WITH NOWAIT;
                    END;
                END;
            END TRY
            BEGIN CATCH
                SET @error_number = ERROR_NUMBER();
                SET @error_severity = ERROR_SEVERITY();
                SET @error_state = ERROR_STATE();
                SET @error_line = ERROR_LINE();
                SET @error_message = ERROR_MESSAGE();
                
                RAISERROR(N'Error collecting query store data from database %s: Error %d at line %d - %s', 
                    11, 1, @database_name, @error_number, @error_line, @error_message) WITH NOWAIT;
            END CATCH;
            
            FETCH NEXT FROM
                db_cursor
            INTO
                @database_name;
        END;
        
        CLOSE db_cursor;
        DEALLOCATE db_cursor;
        
        SET @collection_ending = SYSDATETIME();
        
        IF @debug = 1
        BEGIN
            RAISERROR(N'Query store collection completed at %s', 0, 1, @collection_ending) WITH NOWAIT;
            RAISERROR(N'Total execution time: %d seconds', 0, 1, 
                DATEDIFF(SECOND, @collection_starting, @collection_ending)) WITH NOWAIT;
        END;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
        BEGIN
            ROLLBACK TRANSACTION;
        END;
        
        IF CURSOR_STATUS('local', 'db_cursor') <> -3
        BEGIN
            CLOSE db_cursor;
            DEALLOCATE db_cursor;
        END;
        
        SET @error_number = ERROR_NUMBER();
        SET @error_severity = ERROR_SEVERITY();
        SET @error_state = ERROR_STATE();
        SET @error_line = ERROR_LINE();
        SET @error_message = ERROR_MESSAGE();
        
        RAISERROR(N'Error %d at line %d: %s', 11, 1, @error_number, @error_line, @error_message) WITH NOWAIT;
        THROW;
    END CATCH;
END;
GO

PRINT 'DarlingDataCollector installation complete.';
GO
