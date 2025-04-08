/*
██╗ ██████╗     ███████╗████████╗ █████╗ ████████╗███████╗     ██████╗ ██████╗ ██╗     ██╗     ███████╗ ██████╗████████╗ ██████╗ ██████╗ 
██║██╔═══██╗    ██╔════╝╚══██╔══╝██╔══██╗╚══██╔══╝██╔════╝    ██╔════╝██╔═══██╗██║     ██║     ██╔════╝██╔════╝╚══██╔══╝██╔═══██╗██╔══██╗
██║██║   ██║    ███████╗   ██║   ███████║   ██║   ███████╗    ██║     ██║   ██║██║     ██║     █████╗  ██║        ██║   ██║   ██║██████╔╝
██║██║   ██║    ╚════██║   ██║   ██╔══██║   ██║   ╚════██║    ██║     ██║   ██║██║     ██║     ██╔══╝  ██║        ██║   ██║   ██║██╔══██╗
██║╚██████╔╝    ███████║   ██║   ██║  ██║   ██║   ███████║    ╚██████╗╚██████╔╝███████╗███████╗███████╗╚██████╗   ██║   ╚██████╔╝██║  ██║
╚═╝ ╚═════╝     ╚══════╝   ╚═╝   ╚═╝  ╚═╝   ╚═╝   ╚══════╝     ╚═════╝ ╚═════╝ ╚══════╝╚══════╝╚══════╝ ╚═════╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝
                                                                                                                                           
Copyright (c) Darling Data, LLC
https://www.erikdarling.com/

--===== IO STATS COLLECTOR NOTES ====--
This procedure collects I/O statistics from virtual file stats DMVs.
It supports different SQL Server environments (on-premises, Azure SQL MI, AWS RDS)
with environment-specific code paths. You can collect point-in-time statistics
or gather a sample over a specified period to calculate delta values.
*/

CREATE OR ALTER PROCEDURE
    collection.collect_io_stats
(
    @debug BIT = 0, /*Print debugging information*/
    @sample_seconds INTEGER = NULL, /*Optional: Collect sample over time period*/
    @collect_io_details BIT = 1, /*Collect detailed I/O information where available*/
    @collect_drive_stats BIT = 1, /*Collect drive-level statistics on supported platforms*/
    @exclude_databases NVARCHAR(MAX) = NULL /*Optional: Comma-separated list of databases to exclude*/
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
        @is_azure_mi BIT,
        @is_aws_rds BIT,
        @engine_edition INTEGER,
        @server_name NVARCHAR(256),
        @excluded_databases TABLE 
        (
            database_name NVARCHAR(128) PRIMARY KEY
        );
    
    BEGIN TRY
        /*
        Detect environment
        */
        SELECT
            @engine_edition = CONVERT(INTEGER, SERVERPROPERTY('EngineEdition')),
            @server_name = CONVERT(NVARCHAR(256), SERVERPROPERTY('ServerName'));
        
        -- Azure SQL MI has EngineEdition = 8
        SET @is_azure_mi = CASE WHEN @engine_edition = 8 THEN 1 ELSE 0 END;
        
        -- AWS RDS detection using the presence of rdsadmin database
        SET @is_aws_rds = CASE
            WHEN DB_ID('rdsadmin') IS NOT NULL THEN 1
            ELSE 0
        END;
        
        /*
        Parse exclusion list
        */
        IF @exclude_databases IS NOT NULL
        BEGIN
            INSERT
                @excluded_databases
            (
                database_name
            )
            SELECT
                LTRIM(RTRIM(value))
            FROM
                STRING_SPLIT(@exclude_databases, ',');
        END;
        
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
                size_on_disk_bytes BIGINT NULL,
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
                num_of_bytes_written,
                size_on_disk_bytes
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
                num_of_bytes_written,
                size_on_disk_bytes
            FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS fs
            WHERE NOT EXISTS 
            (
                SELECT 1 
                FROM @excluded_databases AS ed 
                WHERE DB_NAME(fs.database_id) = ed.database_name
            );
            
            /*
            Wait for the specified sample period
            */
            WAITFOR DELAY CONVERT(CHAR(8), DATEADD(SECOND, @sample_seconds, 0), 114);
            
            /*
            Insert data with delta values - environment-specific approach
            */
            IF @is_azure_mi = 1
            BEGIN
                /*
                Azure SQL MI specific collection
                */
                INSERT
                    collection.io_stats
                (
                    collection_time,
                    server_name,
                    environment,
                    database_id,
                    database_name,
                    file_id,
                    file_name,
                    file_path,
                    type_desc,
                    state_desc,
                    size_mb,
                    max_size_mb,
                    growth,
                    is_percent_growth,
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
                    sample_seconds,
                    read_latency_ms,
                    write_latency_ms,
                    avg_read_stall_ms,
                    avg_write_stall_ms,
                    size_on_disk_bytes,
                    size_on_disk_mb
                )
                SELECT
                    collection_time = SYSDATETIME(),
                    server_name = @server_name,
                    environment = N'Azure SQL MI',
                    fs.database_id,
                    database_name = DB_NAME(fs.database_id),
                    fs.file_id,
                    file_name = mf.name,
                    file_path = mf.physical_name,
                    mf.type_desc,
                    state_desc = mf.state_desc,
                    size_mb = mf.size * 8.0 / 1024, -- Convert from 8KB pages to MB
                    max_size_mb = CASE 
                                    WHEN mf.max_size = -1 THEN -1 -- Unlimited
                                    WHEN mf.max_size = 268435456 THEN -1 -- Unlimited
                                    ELSE mf.max_size * 8.0 / 1024 -- Convert from 8KB pages to MB
                                  END,
                    growth = CASE 
                               WHEN mf.is_percent_growth = 1 THEN mf.growth
                               ELSE mf.growth * 8.0 / 1024 -- Convert from 8KB pages to MB
                             END,
                    is_percent_growth = mf.is_percent_growth,
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
                    sample_seconds = @sample_seconds,
                    read_latency_ms = CASE 
                                        WHEN (fs.num_of_reads - fsb.num_of_reads) = 0 THEN 0
                                        ELSE (fs.io_stall_read_ms - fsb.io_stall_read_ms) / (fs.num_of_reads - fsb.num_of_reads)
                                      END,
                    write_latency_ms = CASE 
                                         WHEN (fs.num_of_writes - fsb.num_of_writes) = 0 THEN 0
                                         ELSE (fs.io_stall_write_ms - fsb.io_stall_write_ms) / (fs.num_of_writes - fsb.num_of_writes)
                                       END,
                    avg_read_stall_ms = CASE 
                                          WHEN (fs.num_of_reads - fsb.num_of_reads) = 0 THEN 0
                                          ELSE (fs.io_stall_read_ms - fsb.io_stall_read_ms) / (fs.num_of_reads - fsb.num_of_reads)
                                        END,
                    avg_write_stall_ms = CASE 
                                           WHEN (fs.num_of_writes - fsb.num_of_writes) = 0 THEN 0
                                           ELSE (fs.io_stall_write_ms - fsb.io_stall_write_ms) / (fs.num_of_writes - fsb.num_of_writes)
                                         END,
                    fs.size_on_disk_bytes,
                    size_on_disk_mb = fs.size_on_disk_bytes / 1024.0 / 1024.0
                FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS fs
                JOIN #io_stats_before AS fsb
                  ON fs.database_id = fsb.database_id
                  AND fs.file_id = fsb.file_id
                JOIN sys.master_files AS mf
                  ON fs.database_id = mf.database_id
                  AND fs.file_id = mf.file_id
                WHERE NOT EXISTS 
                (
                    SELECT 1 
                    FROM @excluded_databases AS ed 
                    WHERE DB_NAME(fs.database_id) = ed.database_name
                );
            END
            ELSE IF @is_aws_rds = 1
            BEGIN
                /*
                AWS RDS specific collection
                */
                INSERT
                    collection.io_stats
                (
                    collection_time,
                    server_name,
                    environment,
                    database_id,
                    database_name,
                    file_id,
                    file_name,
                    file_path,
                    type_desc,
                    state_desc,
                    size_mb,
                    max_size_mb,
                    growth,
                    is_percent_growth,
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
                    sample_seconds,
                    read_latency_ms,
                    write_latency_ms,
                    avg_read_stall_ms,
                    avg_write_stall_ms,
                    size_on_disk_bytes,
                    size_on_disk_mb
                )
                SELECT
                    collection_time = SYSDATETIME(),
                    server_name = @server_name,
                    environment = N'AWS RDS',
                    fs.database_id,
                    database_name = DB_NAME(fs.database_id),
                    fs.file_id,
                    file_name = mf.name,
                    file_path = mf.physical_name,
                    mf.type_desc,
                    state_desc = mf.state_desc,
                    size_mb = mf.size * 8.0 / 1024, -- Convert from 8KB pages to MB
                    max_size_mb = CASE 
                                    WHEN mf.max_size = -1 THEN -1 -- Unlimited
                                    WHEN mf.max_size = 268435456 THEN -1 -- Unlimited
                                    ELSE mf.max_size * 8.0 / 1024 -- Convert from 8KB pages to MB
                                  END,
                    growth = CASE 
                               WHEN mf.is_percent_growth = 1 THEN mf.growth
                               ELSE mf.growth * 8.0 / 1024 -- Convert from 8KB pages to MB
                             END,
                    is_percent_growth = mf.is_percent_growth,
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
                    sample_seconds = @sample_seconds,
                    read_latency_ms = CASE 
                                        WHEN (fs.num_of_reads - fsb.num_of_reads) = 0 THEN 0
                                        ELSE (fs.io_stall_read_ms - fsb.io_stall_read_ms) / (fs.num_of_reads - fsb.num_of_reads)
                                      END,
                    write_latency_ms = CASE 
                                         WHEN (fs.num_of_writes - fsb.num_of_writes) = 0 THEN 0
                                         ELSE (fs.io_stall_write_ms - fsb.io_stall_write_ms) / (fs.num_of_writes - fsb.num_of_writes)
                                       END,
                    avg_read_stall_ms = CASE 
                                          WHEN (fs.num_of_reads - fsb.num_of_reads) = 0 THEN 0
                                          ELSE (fs.io_stall_read_ms - fsb.io_stall_read_ms) / (fs.num_of_reads - fsb.num_of_reads)
                                        END,
                    avg_write_stall_ms = CASE 
                                           WHEN (fs.num_of_writes - fsb.num_of_writes) = 0 THEN 0
                                           ELSE (fs.io_stall_write_ms - fsb.io_stall_write_ms) / (fs.num_of_writes - fsb.num_of_writes)
                                         END,
                    fs.size_on_disk_bytes,
                    size_on_disk_mb = fs.size_on_disk_bytes / 1024.0 / 1024.0
                FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS fs
                JOIN #io_stats_before AS fsb
                  ON fs.database_id = fsb.database_id
                  AND fs.file_id = fsb.file_id
                JOIN sys.master_files AS mf
                  ON fs.database_id = mf.database_id
                  AND fs.file_id = mf.file_id
                WHERE NOT EXISTS 
                (
                    SELECT 1 
                    FROM @excluded_databases AS ed 
                    WHERE DB_NAME(fs.database_id) = ed.database_name
                );
            END
            ELSE
            BEGIN
                /*
                On-premises SQL Server specific collection
                */
                INSERT
                    collection.io_stats
                (
                    collection_time,
                    server_name,
                    environment,
                    database_id,
                    database_name,
                    file_id,
                    file_name,
                    file_path,
                    drive_letter,
                    type_desc,
                    state_desc,
                    size_mb,
                    max_size_mb,
                    growth,
                    is_percent_growth,
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
                    sample_seconds,
                    read_latency_ms,
                    write_latency_ms,
                    avg_read_stall_ms,
                    avg_write_stall_ms,
                    size_on_disk_bytes,
                    size_on_disk_mb
                )
                SELECT
                    collection_time = SYSDATETIME(),
                    server_name = @server_name,
                    environment = N'On-Premises SQL Server',
                    fs.database_id,
                    database_name = DB_NAME(fs.database_id),
                    fs.file_id,
                    file_name = mf.name,
                    file_path = mf.physical_name,
                    drive_letter = UPPER(LEFT(mf.physical_name, 1)),
                    mf.type_desc,
                    state_desc = mf.state_desc,
                    size_mb = mf.size * 8.0 / 1024, -- Convert from 8KB pages to MB
                    max_size_mb = CASE 
                                    WHEN mf.max_size = -1 THEN -1 -- Unlimited
                                    WHEN mf.max_size = 268435456 THEN -1 -- Unlimited
                                    ELSE mf.max_size * 8.0 / 1024 -- Convert from 8KB pages to MB
                                  END,
                    growth = CASE 
                               WHEN mf.is_percent_growth = 1 THEN mf.growth
                               ELSE mf.growth * 8.0 / 1024 -- Convert from 8KB pages to MB
                             END,
                    is_percent_growth = mf.is_percent_growth,
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
                    sample_seconds = @sample_seconds,
                    read_latency_ms = CASE 
                                        WHEN (fs.num_of_reads - fsb.num_of_reads) = 0 THEN 0
                                        ELSE (fs.io_stall_read_ms - fsb.io_stall_read_ms) / (fs.num_of_reads - fsb.num_of_reads)
                                      END,
                    write_latency_ms = CASE 
                                         WHEN (fs.num_of_writes - fsb.num_of_writes) = 0 THEN 0
                                         ELSE (fs.io_stall_write_ms - fsb.io_stall_write_ms) / (fs.num_of_writes - fsb.num_of_writes)
                                       END,
                    avg_read_stall_ms = CASE 
                                          WHEN (fs.num_of_reads - fsb.num_of_reads) = 0 THEN 0
                                          ELSE (fs.io_stall_read_ms - fsb.io_stall_read_ms) / (fs.num_of_reads - fsb.num_of_reads)
                                        END,
                    avg_write_stall_ms = CASE 
                                           WHEN (fs.num_of_writes - fsb.num_of_writes) = 0 THEN 0
                                           ELSE (fs.io_stall_write_ms - fsb.io_stall_write_ms) / (fs.num_of_writes - fsb.num_of_writes)
                                         END,
                    fs.size_on_disk_bytes,
                    size_on_disk_mb = fs.size_on_disk_bytes / 1024.0 / 1024.0
                FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS fs
                JOIN #io_stats_before AS fsb
                  ON fs.database_id = fsb.database_id
                  AND fs.file_id = fsb.file_id
                JOIN sys.master_files AS mf
                  ON fs.database_id = mf.database_id
                  AND fs.file_id = mf.file_id
                WHERE NOT EXISTS 
                (
                    SELECT 1 
                    FROM @excluded_databases AS ed 
                    WHERE DB_NAME(fs.database_id) = ed.database_name
                );
            END;
        END
        ELSE
        BEGIN
            /*
            Collect current I/O stats without sampling - environment-specific approach
            */
            IF @is_azure_mi = 1
            BEGIN
                /*
                Azure SQL MI specific collection
                */
                INSERT
                    collection.io_stats
                (
                    collection_time,
                    server_name,
                    environment,
                    database_id,
                    database_name,
                    file_id,
                    file_name,
                    file_path,
                    type_desc,
                    state_desc,
                    size_mb,
                    max_size_mb,
                    growth,
                    is_percent_growth,
                    io_stall_read_ms,
                    io_stall_write_ms,
                    io_stall,
                    num_of_reads,
                    num_of_writes,
                    num_of_bytes_read,
                    num_of_bytes_written,
                    size_on_disk_bytes,
                    size_on_disk_mb
                )
                SELECT
                    collection_time = SYSDATETIME(),
                    server_name = @server_name,
                    environment = N'Azure SQL MI',
                    fs.database_id,
                    database_name = DB_NAME(fs.database_id),
                    fs.file_id,
                    file_name = mf.name,
                    file_path = mf.physical_name,
                    mf.type_desc,
                    state_desc = mf.state_desc,
                    size_mb = mf.size * 8.0 / 1024, -- Convert from 8KB pages to MB
                    max_size_mb = CASE 
                                    WHEN mf.max_size = -1 THEN -1 -- Unlimited
                                    WHEN mf.max_size = 268435456 THEN -1 -- Unlimited
                                    ELSE mf.max_size * 8.0 / 1024 -- Convert from 8KB pages to MB
                                  END,
                    growth = CASE 
                               WHEN mf.is_percent_growth = 1 THEN mf.growth
                               ELSE mf.growth * 8.0 / 1024 -- Convert from 8KB pages to MB
                             END,
                    is_percent_growth = mf.is_percent_growth,
                    fs.io_stall_read_ms,
                    fs.io_stall_write_ms,
                    fs.io_stall,
                    fs.num_of_reads,
                    fs.num_of_writes,
                    fs.num_of_bytes_read,
                    fs.num_of_bytes_written,
                    fs.size_on_disk_bytes,
                    size_on_disk_mb = fs.size_on_disk_bytes / 1024.0 / 1024.0
                FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS fs
                JOIN sys.master_files AS mf
                  ON fs.database_id = mf.database_id
                  AND fs.file_id = mf.file_id
                WHERE NOT EXISTS 
                (
                    SELECT 1 
                    FROM @excluded_databases AS ed 
                    WHERE DB_NAME(fs.database_id) = ed.database_name
                );
            END
            ELSE IF @is_aws_rds = 1
            BEGIN
                /*
                AWS RDS specific collection
                */
                INSERT
                    collection.io_stats
                (
                    collection_time,
                    server_name,
                    environment,
                    database_id,
                    database_name,
                    file_id,
                    file_name,
                    file_path,
                    type_desc,
                    state_desc,
                    size_mb,
                    max_size_mb,
                    growth,
                    is_percent_growth,
                    io_stall_read_ms,
                    io_stall_write_ms,
                    io_stall,
                    num_of_reads,
                    num_of_writes,
                    num_of_bytes_read,
                    num_of_bytes_written,
                    size_on_disk_bytes,
                    size_on_disk_mb
                )
                SELECT
                    collection_time = SYSDATETIME(),
                    server_name = @server_name,
                    environment = N'AWS RDS',
                    fs.database_id,
                    database_name = DB_NAME(fs.database_id),
                    fs.file_id,
                    file_name = mf.name,
                    file_path = mf.physical_name,
                    mf.type_desc,
                    state_desc = mf.state_desc,
                    size_mb = mf.size * 8.0 / 1024, -- Convert from 8KB pages to MB
                    max_size_mb = CASE 
                                    WHEN mf.max_size = -1 THEN -1 -- Unlimited
                                    WHEN mf.max_size = 268435456 THEN -1 -- Unlimited
                                    ELSE mf.max_size * 8.0 / 1024 -- Convert from 8KB pages to MB
                                  END,
                    growth = CASE 
                               WHEN mf.is_percent_growth = 1 THEN mf.growth
                               ELSE mf.growth * 8.0 / 1024 -- Convert from 8KB pages to MB
                             END,
                    is_percent_growth = mf.is_percent_growth,
                    fs.io_stall_read_ms,
                    fs.io_stall_write_ms,
                    fs.io_stall,
                    fs.num_of_reads,
                    fs.num_of_writes,
                    fs.num_of_bytes_read,
                    fs.num_of_bytes_written,
                    fs.size_on_disk_bytes,
                    size_on_disk_mb = fs.size_on_disk_bytes / 1024.0 / 1024.0
                FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS fs
                JOIN sys.master_files AS mf
                  ON fs.database_id = mf.database_id
                  AND fs.file_id = mf.file_id
                WHERE NOT EXISTS 
                (
                    SELECT 1 
                    FROM @excluded_databases AS ed 
                    WHERE DB_NAME(fs.database_id) = ed.database_name
                );
            END
            ELSE
            BEGIN
                /*
                On-premises SQL Server specific collection
                */
                INSERT
                    collection.io_stats
                (
                    collection_time,
                    server_name,
                    environment,
                    database_id,
                    database_name,
                    file_id,
                    file_name,
                    file_path,
                    drive_letter,
                    type_desc,
                    state_desc,
                    size_mb,
                    max_size_mb,
                    growth,
                    is_percent_growth,
                    io_stall_read_ms,
                    io_stall_write_ms,
                    io_stall,
                    num_of_reads,
                    num_of_writes,
                    num_of_bytes_read,
                    num_of_bytes_written,
                    size_on_disk_bytes,
                    size_on_disk_mb
                )
                SELECT
                    collection_time = SYSDATETIME(),
                    server_name = @server_name,
                    environment = N'On-Premises SQL Server',
                    fs.database_id,
                    database_name = DB_NAME(fs.database_id),
                    fs.file_id,
                    file_name = mf.name,
                    file_path = mf.physical_name,
                    drive_letter = UPPER(LEFT(mf.physical_name, 1)),
                    mf.type_desc,
                    state_desc = mf.state_desc,
                    size_mb = mf.size * 8.0 / 1024, -- Convert from 8KB pages to MB
                    max_size_mb = CASE 
                                    WHEN mf.max_size = -1 THEN -1 -- Unlimited
                                    WHEN mf.max_size = 268435456 THEN -1 -- Unlimited
                                    ELSE mf.max_size * 8.0 / 1024 -- Convert from 8KB pages to MB
                                  END,
                    growth = CASE 
                               WHEN mf.is_percent_growth = 1 THEN mf.growth
                               ELSE mf.growth * 8.0 / 1024 -- Convert from 8KB pages to MB
                             END,
                    is_percent_growth = mf.is_percent_growth,
                    fs.io_stall_read_ms,
                    fs.io_stall_write_ms,
                    fs.io_stall,
                    fs.num_of_reads,
                    fs.num_of_writes,
                    fs.num_of_bytes_read,
                    fs.num_of_bytes_written,
                    fs.size_on_disk_bytes,
                    size_on_disk_mb = fs.size_on_disk_bytes / 1024.0 / 1024.0
                FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS fs
                JOIN sys.master_files AS mf
                  ON fs.database_id = mf.database_id
                  AND fs.file_id = mf.file_id
                WHERE NOT EXISTS 
                (
                    SELECT 1 
                    FROM @excluded_databases AS ed 
                    WHERE DB_NAME(fs.database_id) = ed.database_name
                );
            END;
        END;
        
        /*
        Collect drive-level I/O stats on supported platforms
        */
        IF @collect_drive_stats = 1 AND @is_azure_mi = 0 AND @is_aws_rds = 0
        BEGIN
            WITH
                io_per_drive AS
            (
                SELECT
                    drive_letter = UPPER(LEFT(mf.physical_name, 1)),
                    io_stall_read_ms = SUM(fs.io_stall_read_ms),
                    io_stall_write_ms = SUM(fs.io_stall_write_ms),
                    io_stall = SUM(fs.io_stall),
                    num_of_reads = SUM(fs.num_of_reads),
                    num_of_writes = SUM(fs.num_of_writes),
                    num_of_bytes_read = SUM(fs.num_of_bytes_read),
                    num_of_bytes_written = SUM(fs.num_of_bytes_written),
                    size_on_disk_bytes = SUM(fs.size_on_disk_bytes)
                FROM 
                    sys.dm_io_virtual_file_stats(NULL, NULL) AS fs
                JOIN 
                    sys.master_files AS mf
                    ON fs.database_id = mf.database_id
                    AND fs.file_id = mf.file_id
                WHERE 
                    mf.physical_name IS NOT NULL
                    AND LEFT(mf.physical_name, 1) LIKE '[A-Za-z]'
                    AND NOT EXISTS 
                    (
                        SELECT 1 
                        FROM @excluded_databases AS ed 
                        WHERE DB_NAME(fs.database_id) = ed.database_name
                    )
                GROUP BY
                    UPPER(LEFT(mf.physical_name, 1))
            )
            INSERT
                collection.drive_stats
            (
                collection_time,
                server_name,
                drive_letter,
                io_stall_read_ms,
                io_stall_write_ms,
                io_stall,
                num_of_reads,
                num_of_writes,
                num_of_bytes_read,
                num_of_bytes_written,
                read_latency_ms,
                write_latency_ms,
                total_mb_read,
                total_mb_written,
                size_on_disk_bytes,
                size_on_disk_gb
            )
            SELECT
                collection_time = SYSDATETIME(),
                server_name = @server_name,
                drive_letter,
                io_stall_read_ms,
                io_stall_write_ms,
                io_stall,
                num_of_reads,
                num_of_writes,
                num_of_bytes_read,
                num_of_bytes_written,
                read_latency_ms = CASE WHEN num_of_reads = 0 THEN 0 ELSE io_stall_read_ms / num_of_reads END,
                write_latency_ms = CASE WHEN num_of_writes = 0 THEN 0 ELSE io_stall_write_ms / num_of_writes END,
                total_mb_read = CAST(num_of_bytes_read / 1024.0 / 1024.0 AS DECIMAL(18, 2)),
                total_mb_written = CAST(num_of_bytes_written / 1024.0 / 1024.0 AS DECIMAL(18, 2)),
                size_on_disk_bytes,
                size_on_disk_gb = CAST(size_on_disk_bytes / 1024.0 / 1024.0 / 1024.0 AS DECIMAL(18, 2))
            FROM
                io_per_drive;
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
                CAST(DATEDIFF(MILLISECOND, @collection_start, @collection_end) / 1000.0 AS DECIMAL(18,2)) AS duration_seconds,
                environment = CASE
                              WHEN @is_azure_mi = 1 THEN 'Azure SQL MI'
                              WHEN @is_aws_rds = 1 THEN 'AWS RDS'
                              ELSE 'On-Premises SQL Server'
                              END,
                is_sampled = CASE WHEN @sample_seconds IS NOT NULL THEN 1 ELSE 0 END,
                excluded_databases = 
                (
                    SELECT
                        STRING_AGG(database_name, N', ') WITHIN GROUP (ORDER BY database_name)
                    FROM
                        @excluded_databases
                ),
                drive_stats_included = CASE 
                                       WHEN @collect_drive_stats = 1 AND @is_azure_mi = 0 AND @is_aws_rds = 0 
                                       THEN 1 
                                       ELSE 0 
                                       END;
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
GO