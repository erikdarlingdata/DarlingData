# DarlingDataCollector Analysis Engine

This document outlines the analysis capabilities of the DarlingDataCollector solution, designed to provide actionable insights and recommendations from collected performance data.

## Supported Environments

DarlingDataCollector Analysis supports the following SQL Server environments:

- On-premises SQL Server
- Azure SQL Managed Instance
- Amazon RDS for SQL Server

> **Note**: Azure SQL Database is **not** supported due to its limitations with SQL Agent jobs and specific system-level DMVs required for proper collection.

## Analysis Architecture

The analysis engine consists of several components:

1. **Delta Calculation Functions**
   - Calculate changes between collection points
   - Account for SQL Server restarts 
   - Handle cumulative counter wraparounds

2. **Pattern Detection Procedures**
   - Identify common performance issues
   - Correlate data across different DMVs
   - Apply threshold-based detection rules

3. **Recommendation Engine**
   - Generate specific actionable recommendations
   - Prioritize recommendations by impact
   - Include T-SQL scripts for remediation where applicable

4. **Narrative Generation**
   - Provide human-readable explanations
   - Connect different symptoms into a cohesive story
   - Highlight root causes rather than symptoms

## Analysis Categories

### 1. Memory Analysis

```sql
CREATE OR ALTER PROCEDURE
    analysis.analyze_memory_pressure
(
    @start_time DATETIME2(7),
    @end_time DATETIME2(7),
    @debug BIT = 0 /*Print debugging information*/
)
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
    
    DECLARE
        @threshold_pct DECIMAL(5,2) = 90.0,
        @has_pressure BIT = 0,
        @buffer_pool_mb DECIMAL(19,2),
        @total_memory_mb DECIMAL(19,2),
        @narrative NVARCHAR(MAX);
    
    /*
    Check for memory pressure signals
    */
    
    /* Buffer Pool Size */
    SELECT
        @buffer_pool_mb = SUM(cached_size_mb)
    FROM collection.buffer_pool
    WHERE collection_time BETWEEN @start_time AND @end_time
    GROUP BY collection_id
    ORDER BY collection_id DESC
    OFFSET 0 ROWS
    FETCH NEXT 1 ROWS ONLY;
    
    /* Total Available Memory */
    SELECT
        @total_memory_mb = physical_memory_mb
    FROM system.server_info;
    
    /* Check memory clerks for pressure signals */
    IF EXISTS
    (
        SELECT 1
        FROM collection.memory_clerks
        WHERE collection_time BETWEEN @start_time AND @end_time
        AND clerk_name = 'MEMORYCLERK_SQLBUFFERPOOL'
        AND pages_kb > (@threshold_pct * @total_memory_mb * 1024 / 100)
    )
    BEGIN
        SET @has_pressure = 1;
    END;
    
    /* Check for significant memory grants outstanding */
    IF EXISTS
    (
        SELECT 1
        FROM collection.wait_stats
        WHERE collection_time BETWEEN @start_time AND @end_time
        AND wait_type = 'RESOURCE_SEMAPHORE'
        AND wait_time_ms_delta > 1000
        AND waiting_tasks_count_delta > 0
    )
    BEGIN
        SET @has_pressure = 1;
    END;
    
    /* Generate narrative */
    IF @has_pressure = 1
    BEGIN
        SET @narrative = N'
        Memory pressure detected during the analysis period:
        
        ';
        
        /* Buffer pool analysis */
        SET @narrative = @narrative + N'
        - Buffer pool currently using ' + CAST(@buffer_pool_mb AS NVARCHAR(20)) + N' MB out of ' + 
        CAST(@total_memory_mb AS NVARCHAR(20)) + N' MB total server memory (' + 
        CAST(CAST((@buffer_pool_mb / @total_memory_mb * 100) AS DECIMAL(5,2)) AS NVARCHAR(10)) + N'%).
        ';
        
        /* Memory grant issues */
        IF EXISTS
        (
            SELECT 1
            FROM collection.wait_stats
            WHERE collection_time BETWEEN @start_time AND @end_time
            AND wait_type = 'RESOURCE_SEMAPHORE'
            AND wait_time_ms_delta > 1000
            AND waiting_tasks_count_delta > 0
        )
        BEGIN
            SET @narrative = @narrative + N'
            - Memory grant issues detected:
              Queries are waiting for memory grants (RESOURCE_SEMAPHORE waits), indicating competition for query memory.
              This can be caused by queries requesting excessive memory or general memory pressure on the server.
            ';
        END;
        
        /* Paging issues */
        IF EXISTS
        (
            SELECT 1
            FROM collection.wait_stats
            WHERE collection_time BETWEEN @start_time AND @end_time
            AND wait_type = 'PAGEIOLATCH_SH'
            AND wait_time_ms_delta > 5000
        )
        BEGIN
            SET @narrative = @narrative + N'
            - Page I/O latch waits detected:
              Pages are being read from disk rather than memory, indicating buffer pool pressure.
              The server may benefit from additional memory or query tuning to reduce memory requirements.
            ';
        END;
        
        /* Recommendations */
        SET @narrative = @narrative + N'
        Recommendations:
        
        1. Review largest consumers of buffer pool memory:
        ```sql
        SELECT TOP 10
            database_name,
            SUM(cached_size_mb) AS cached_mb,
            SUM(page_count) AS page_count
        FROM collection.buffer_pool
        WHERE collection_id = (SELECT MAX(collection_id) FROM collection.buffer_pool)
        GROUP BY database_name
        ORDER BY cached_mb DESC;
        ```
        
        2. If RESOURCE_SEMAPHORE waits are high, identify queries requesting large memory grants:
        ```sql
        SELECT TOP 10
            query_text,
            total_elapsed_time_delta / execution_count_delta AS avg_elapsed_time,
            execution_count_delta,
            qs.collection_time
        FROM collection.query_stats AS qs
        CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
        WHERE qs.collection_time BETWEEN ''' + CONVERT(NVARCHAR(30), @start_time, 121) + ''' AND ''' + CONVERT(NVARCHAR(30), @end_time, 121) + '''
        AND query_text LIKE ''%SORT%'' OR query_text LIKE ''%HASH%''
        ORDER BY total_elapsed_time_delta DESC;
        ```
        
        3. Consider adding memory to the server if consistently near capacity
        
        4. Evaluate index coverage to reduce query memory requirements
        ';
    END;
    ELSE
    BEGIN
        SET @narrative = N'No significant memory pressure detected during the analysis period.';
    END;
    
    /*
    Return results
    */
    SELECT
        analysis_type = 'Memory Pressure',
        detected = @has_pressure,
        current_buffer_pool_mb = @buffer_pool_mb,
        total_server_memory_mb = @total_memory_mb,
        buffer_pool_percentage = CAST((@buffer_pool_mb / @total_memory_mb * 100) AS DECIMAL(5,2)),
        narrative = @narrative;
END;
GO
```

### 2. I/O Analysis

```sql
CREATE OR ALTER PROCEDURE
    analysis.analyze_io_bottlenecks
(
    @start_time DATETIME2(7),
    @end_time DATETIME2(7),
    @debug BIT = 0 /*Print debugging information*/
)
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
    
    DECLARE
        @read_latency_threshold_ms INTEGER = 20,
        @write_latency_threshold_ms INTEGER = 20,
        @has_bottleneck BIT = 0,
        @narrative NVARCHAR(MAX);
    
    /*
    Identify files with high I/O latency
    */
    IF EXISTS
    (
        SELECT 1
        FROM collection.io_stats
        WHERE collection_time BETWEEN @start_time AND @end_time
        AND (
            (io_stall_read_ms_delta > 0 AND num_of_reads_delta > 0 AND (io_stall_read_ms_delta / num_of_reads_delta) > @read_latency_threshold_ms)
            OR
            (io_stall_write_ms_delta > 0 AND num_of_writes_delta > 0 AND (io_stall_write_ms_delta / num_of_writes_delta) > @write_latency_threshold_ms)
        )
    )
    BEGIN
        SET @has_bottleneck = 1;
    END;
    
    /*
    Check for PAGEIOLATCH waits
    */
    IF EXISTS
    (
        SELECT 1
        FROM collection.wait_stats
        WHERE collection_time BETWEEN @start_time AND @end_time
        AND wait_type LIKE 'PAGEIOLATCH_%'
        AND wait_time_ms_delta > 5000
    )
    BEGIN
        SET @has_bottleneck = 1;
    END;
    
    /*
    Generate narrative
    */
    IF @has_bottleneck = 1
    BEGIN
        SET @narrative = N'
        I/O bottlenecks detected during the analysis period:
        
        ';
        
        /* File latency information */
        SET @narrative = @narrative + N'
        Files with high I/O latency:
        
        ';
        
        WITH high_latency_files AS
        (
            SELECT
                database_name,
                file_name,
                type_desc,
                CASE
                    WHEN num_of_reads_delta > 0 THEN io_stall_read_ms_delta / num_of_reads_delta
                    ELSE 0
                END AS avg_read_latency_ms,
                CASE
                    WHEN num_of_writes_delta > 0 THEN io_stall_write_ms_delta / num_of_writes_delta
                    ELSE 0
                END AS avg_write_latency_ms,
                io_stall_read_ms_delta,
                io_stall_write_ms_delta,
                num_of_reads_delta,
                num_of_writes_delta,
                CAST(num_of_bytes_read_delta / 1048576.0 AS DECIMAL(19,2)) AS read_mb,
                CAST(num_of_bytes_written_delta / 1048576.0 AS DECIMAL(19,2)) AS written_mb
            FROM collection.io_stats
            WHERE collection_time BETWEEN @start_time AND @end_time
            AND (
                (io_stall_read_ms_delta > 0 AND num_of_reads_delta > 0 AND (io_stall_read_ms_delta / num_of_reads_delta) > @read_latency_threshold_ms)
                OR
                (io_stall_write_ms_delta > 0 AND num_of_writes_delta > 0 AND (io_stall_write_ms_delta / num_of_writes_delta) > @write_latency_threshold_ms)
            )
        )
        SELECT
            @narrative = @narrative + 
            '- Database: ' + database_name + 
            ', File: ' + ISNULL(file_name, 'Unknown') + 
            ' (' + type_desc + ')' +
            ', Read Latency: ' + CAST(avg_read_latency_ms AS NVARCHAR(10)) + ' ms' +
            ', Write Latency: ' + CAST(avg_write_latency_ms AS NVARCHAR(10)) + ' ms' +
            ', Read: ' + CAST(read_mb AS NVARCHAR(20)) + ' MB' +
            ', Written: ' + CAST(written_mb AS NVARCHAR(20)) + ' MB' +
            CHAR(13) + CHAR(10)
        FROM high_latency_files;
        
        /* PAGEIOLATCH waits */
        IF EXISTS
        (
            SELECT 1
            FROM collection.wait_stats
            WHERE collection_time BETWEEN @start_time AND @end_time
            AND wait_type LIKE 'PAGEIOLATCH_%'
            AND wait_time_ms_delta > 5000
        )
        BEGIN
            SET @narrative = @narrative + N'
            PAGEIOLATCH waits detected, indicating that processes are waiting for data pages to be read from disk.
            This can be caused by:
            - Insufficient memory forcing pages to be read from disk
            - Inefficient queries scanning large amounts of data
            - Slow I/O subsystem performance
            ';
        END;
        
        /* Recommendations */
        SET @narrative = @narrative + N'
        Recommendations:
        
        1. Review storage configuration for affected files:
           - Check if files with high latency are on the same physical disks
           - Verify disk health and RAID configuration
           - Consider moving high-activity files to faster storage
        
        2. For data files with high read latency:
           - Evaluate index usage and coverage
           - Identify queries performing table scans
           - Consider adding appropriate indexes or optimizing existing queries
        
        3. For log files with high write latency:
           - Review transaction sizes and commit frequency
           - Ensure log files are on dedicated, high-performance storage
           - Check for frequent auto-growth events
        
        4. If available, review storage metrics to identify periods of high contention
        
        5. Run the following query to identify queries generating high I/O:
        ```sql
        SELECT TOP 10
            query_text,
            total_logical_reads_delta,
            total_physical_reads_delta,
            execution_count_delta,
            total_logical_reads_delta / execution_count_delta AS avg_logical_reads,
            total_physical_reads_delta / execution_count_delta AS avg_physical_reads,
            qs.collection_time
        FROM collection.query_stats AS qs
        CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
        WHERE qs.collection_time BETWEEN ''' + CONVERT(NVARCHAR(30), @start_time, 121) + ''' AND ''' + CONVERT(NVARCHAR(30), @end_time, 121) + '''
        ORDER BY total_physical_reads_delta DESC;
        ```
        ';
    END;
    ELSE
    BEGIN
        SET @narrative = N'No significant I/O bottlenecks detected during the analysis period.';
    END;
    
    /*
    Return results
    */
    SELECT
        analysis_type = 'I/O Bottlenecks',
        detected = @has_bottleneck,
        narrative = @narrative;
END;
GO
```

### 3. Blocking Analysis

```sql
CREATE OR ALTER PROCEDURE
    analysis.analyze_blocking
(
    @start_time DATETIME2(7),
    @end_time DATETIME2(7),
    @debug BIT = 0 /*Print debugging information*/
)
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
    
    DECLARE
        @has_blocking BIT = 0,
        @narrative NVARCHAR(MAX);
    
    /*
    Check for significant blocking
    */
    IF EXISTS
    (
        SELECT 1
        FROM collection.blocking
        WHERE collection_time BETWEEN @start_time AND @end_time
        AND wait_duration_ms > 5000
    )
    BEGIN
        SET @has_blocking = 1;
    END;
    
    /*
    Generate narrative
    */
    IF @has_blocking = 1
    BEGIN
        SET @narrative = N'
        Significant blocking detected during the analysis period:
        
        ';
        
        /* Blocking chains */
        SET @narrative = @narrative + N'
        Blocking Chains:
        
        ';
        
        WITH significant_blocking AS
        (
            SELECT
                collection_time,
                blocked_session_id,
                blocking_session_id,
                wait_duration_ms,
                wait_type,
                resource_description,
                transaction_isolation_level,
                blocked_sql_text,
                blocking_sql_text,
                blocked_program_name,
                blocking_program_name
            FROM collection.blocking
            WHERE collection_time BETWEEN @start_time AND @end_time
            AND wait_duration_ms > 5000
        )
        SELECT
            @narrative = @narrative + 
            '- Time: ' + CONVERT(NVARCHAR(30), collection_time, 121) +
            ', Duration: ' + CAST(wait_duration_ms / 1000.0 AS NVARCHAR(10)) + ' seconds' +
            ', Blocker: Session ' + CAST(blocking_session_id AS NVARCHAR(10)) +
            ' (' + ISNULL(blocking_program_name, 'Unknown') + ')' +
            ', Blocked: Session ' + CAST(blocked_session_id AS NVARCHAR(10)) +
            ' (' + ISNULL(blocked_program_name, 'Unknown') + ')' +
            ', Wait Type: ' + wait_type +
            ', Isolation Level: ' + ISNULL(transaction_isolation_level, 'Unknown') +
            CHAR(13) + CHAR(10) +
            'Blocker SQL: ' + ISNULL(LEFT(blocking_sql_text, 200) + '...', 'Unknown') +
            CHAR(13) + CHAR(10) +
            'Blocked SQL: ' + ISNULL(LEFT(blocked_sql_text, 200) + '...', 'Unknown') +
            CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10)
        FROM significant_blocking
        ORDER BY wait_duration_ms DESC;
        
        /* Patterns */
        
        /* Check for isolation level issues */
        IF EXISTS
        (
            SELECT 1
            FROM collection.blocking
            WHERE collection_time BETWEEN @start_time AND @end_time
            AND transaction_isolation_level IN ('REPEATABLE READ', 'SERIALIZABLE')
        )
        BEGIN
            SET @narrative = @narrative + N'
            Pattern: Strict Isolation Level
            Blocking involving REPEATABLE READ or SERIALIZABLE isolation levels detected.
            These isolation levels hold locks longer than needed for many workloads.
            ';
        END;
        
        /* Check for key lookups */
        IF EXISTS
        (
            SELECT 1
            FROM collection.blocking
            WHERE collection_time BETWEEN @start_time AND @end_time
            AND (
                blocked_sql_text LIKE '%RID%Lookup%'
                OR blocked_sql_text LIKE '%Key%Lookup%'
                OR blocking_sql_text LIKE '%RID%Lookup%' 
                OR blocking_sql_text LIKE '%Key%Lookup%'
            )
        )
        BEGIN
            SET @narrative = @narrative + N'
            Pattern: Key Lookup Operations
            Blocking involving key lookup operations detected.
            Key lookups often require acquiring locks on more rows than necessary.
            ';
        END;
        
        /* Recommendations */
        SET @narrative = @narrative + N'
        Recommendations:
        
        1. Review application transaction management:
           - Ensure transactions are kept as short as possible
           - Verify that transactions are properly committed or rolled back
           - Consider breaking large transactions into smaller units of work
        
        2. Review isolation levels:
           - Use the lowest isolation level appropriate for each workload
           - Consider using READ COMMITTED SNAPSHOT ISOLATION (RCSI) for databases with frequent blocking
        
        3. Optimize indexes for blocking queries:
           - Create covering indexes to eliminate key lookups
           - Add missing indexes for frequently blocked queries
        
        4. For frequent blocking patterns, consider:
           - Implementing an application queuing system
           - Adding retry logic with exponential backoff
           - Scheduling conflicting operations at different times
        
        5. Run the following query to review recent blocking events:
        ```sql
        SELECT
            collection_time,
            blocked_session_id,
            blocking_session_id,
            wait_duration_ms,
            wait_type,
            blocked_program_name,
            blocking_program_name,
            LEFT(blocked_sql_text, 100) AS blocked_sql_preview,
            LEFT(blocking_sql_text, 100) AS blocking_sql_preview
        FROM collection.blocking
        WHERE collection_time BETWEEN ''' + CONVERT(NVARCHAR(30), @start_time, 121) + ''' AND ''' + CONVERT(NVARCHAR(30), @end_time, 121) + '''
        ORDER BY wait_duration_ms DESC;
        ```
        ';
    END;
    ELSE
    BEGIN
        SET @narrative = N'No significant blocking detected during the analysis period.';
    END;
    
    /*
    Return results
    */
    SELECT
        analysis_type = 'Blocking',
        detected = @has_blocking,
        narrative = @narrative;
END;
GO
```

### 4. Wait Stats Analysis

```sql
CREATE OR ALTER PROCEDURE
    analysis.analyze_wait_stats
(
    @start_time DATETIME2(7),
    @end_time DATETIME2(7),
    @debug BIT = 0 /*Print debugging information*/
)
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
    
    DECLARE
        @narrative NVARCHAR(MAX);
    
    /*
    Get top wait types for the period
    */
    CREATE TABLE
        #top_waits
    (
        wait_type NVARCHAR(128),
        wait_time_ms_delta BIGINT,
        wait_time_percent DECIMAL(5,2),
        waiting_tasks_count_delta BIGINT,
        avg_wait_time_ms DECIMAL(19,2),
        category NVARCHAR(60)
    );
    
    /* 
    Calculate total wait time
    */
    DECLARE
        @total_wait_time_ms BIGINT;
        
    SELECT
        @total_wait_time_ms = SUM(wait_time_ms_delta)
    FROM collection.wait_stats
    WHERE collection_time BETWEEN @start_time AND @end_time
    AND wait_type NOT IN (
        /* Add benign waits not filtered in collection */
        N'KSOURCE_WAKEUP',
        N'SOS_SCHEDULER_YIELD'
    );
    
    /*
    Get top wait types with categorization
    */
    INSERT
        #top_waits
    (
        wait_type,
        wait_time_ms_delta,
        wait_time_percent,
        waiting_tasks_count_delta,
        avg_wait_time_ms,
        category
    )
    SELECT TOP 10
        wait_type,
        wait_time_ms_delta,
        wait_time_percent = CAST((wait_time_ms_delta * 100.0 / @total_wait_time_ms) AS DECIMAL(5,2)),
        waiting_tasks_count_delta,
        avg_wait_time_ms = CAST((wait_time_ms_delta * 1.0 / waiting_tasks_count_delta) AS DECIMAL(19,2)),
        category = 
            CASE
                WHEN wait_type LIKE 'LCK%' THEN 'Locks'
                WHEN wait_type LIKE 'PAGEIOLATCH%' THEN 'Buffer I/O'
                WHEN wait_type LIKE 'PAGELATCH%' THEN 'Buffer Latches'
                WHEN wait_type LIKE 'WRITELOG' THEN 'Log Write'
                WHEN wait_type LIKE 'ASYNC_NETWORK%' THEN 'Network'
                WHEN wait_type LIKE 'CXPACKET' THEN 'Parallelism'
                WHEN wait_type LIKE 'RESOURCE_SEMAPHORE' THEN 'Memory Grant'
                WHEN wait_type LIKE 'CMEMTHREAD' THEN 'Memory'
                WHEN wait_type LIKE 'SOS_SCHEDULER_YIELD' THEN 'CPU'
                WHEN wait_type LIKE 'LOGBUFFER' THEN 'Log Buffer'
                ELSE 'Other'
            END
    FROM collection.wait_stats
    WHERE collection_time BETWEEN @start_time AND @end_time
    AND wait_type NOT IN (
        /* Add benign waits not filtered in collection */
        N'KSOURCE_WAKEUP',
        N'SOS_SCHEDULER_YIELD'
    )
    AND waiting_tasks_count_delta > 0
    ORDER BY wait_time_ms_delta DESC;
    
    /*
    Generate narrative
    */
    SET @narrative = N'
    Wait Statistics Analysis for the period ' + CONVERT(NVARCHAR(30), @start_time, 121) + 
    ' to ' + CONVERT(NVARCHAR(30), @end_time, 121) + ':
    
    Top Wait Types:
    ';
    
    /* Add top waits to narrative */
    SELECT
        @narrative = @narrative +
        '- ' + wait_type + ': ' + 
        CAST(wait_time_ms_delta / 1000.0 AS NVARCHAR(20)) + ' seconds (' +
        CAST(wait_time_percent AS NVARCHAR(10)) + '% of total), ' +
        CAST(waiting_tasks_count_delta AS NVARCHAR(20)) + ' waits, ' +
        CAST(avg_wait_time_ms AS NVARCHAR(20)) + ' ms avg wait time, ' +
        'Category: ' + category +
        CHAR(13) + CHAR(10)
    FROM #top_waits
    ORDER BY wait_time_ms_delta DESC;
    
    /*
    Add category analysis
    */
    SET @narrative = @narrative + N'
    
    Wait Category Analysis:
    ';
    
    WITH wait_categories AS
    (
        SELECT
            category,
            SUM(wait_time_ms_delta) AS total_wait_time_ms,
            SUM(wait_time_percent) AS total_wait_percent,
            SUM(waiting_tasks_count_delta) AS total_waiting_tasks
        FROM #top_waits
        GROUP BY category
    )
    SELECT
        @narrative = @narrative +
        '- ' + category + ': ' + 
        CAST(total_wait_time_ms / 1000.0 AS NVARCHAR(20)) + ' seconds (' +
        CAST(total_wait_percent AS NVARCHAR(10)) + '% of total), ' +
        CAST(total_waiting_tasks AS NVARCHAR(20)) + ' waits' +
        CHAR(13) + CHAR(10)
    FROM wait_categories
    ORDER BY total_wait_time_ms DESC;
    
    /*
    Add specific wait type analysis
    */
    
    /* PAGEIOLATCH - Buffer I/O */
    IF EXISTS (SELECT 1 FROM #top_waits WHERE category = 'Buffer I/O')
    BEGIN
        SET @narrative = @narrative + N'
        Buffer I/O Wait Analysis:
        High PAGEIOLATCH waits indicate that SQL Server is waiting for data pages to be read from disk.
        This can be caused by:
        - Insufficient memory forcing pages to be read from disk
        - Inefficient queries scanning large amounts of data
        - Slow I/O subsystem performance
        
        Recommendations:
        - Review queries with high physical reads
        - Check buffer pool usage and memory pressure
        - Verify I/O subsystem performance
        - Consider adding appropriate indexes
        ';
    END;
    
    /* Locks */
    IF EXISTS (SELECT 1 FROM #top_waits WHERE category = 'Locks')
    BEGIN
        SET @narrative = @narrative + N'
        Lock Wait Analysis:
        High lock waits indicate contention between transactions.
        This can be caused by:
        - Long-running transactions holding locks
        - Strict isolation levels (REPEATABLE READ, SERIALIZABLE)
        - Hotspots in the data or index design
        - Lock escalation
        
        Recommendations:
        - Review transaction design to minimize duration
        - Consider using READ COMMITTED SNAPSHOT ISOLATION
        - Identify and resolve hotspots in data access patterns
        - Review indexes for queries involved in blocking
        ';
    END;
    
    /* Memory Grant */
    IF EXISTS (SELECT 1 FROM #top_waits WHERE category = 'Memory Grant')
    BEGIN
        SET @narrative = @narrative + N'
        Memory Grant Wait Analysis:
        RESOURCE_SEMAPHORE waits indicate that queries are waiting for memory grants.
        This can be caused by:
        - Queries requesting excessive memory
        - General memory pressure on the server
        - Poor cardinality estimates leading to inefficient execution plans
        
        Recommendations:
        - Review queries with large memory grants
        - Update statistics for tables with skewed data
        - Consider adding memory to the server
        - Implement query hints or plan guides for problematic queries
        ';
    END;
    
    /*
    Return results
    */
    SELECT
        analysis_type = 'Wait Statistics',
        narrative = @narrative;
END;
GO
```

### 5. Comprehensive Analysis

```sql
CREATE OR ALTER PROCEDURE
    analysis.generate_performance_report
(
    @hours_to_analyze INTEGER = 24,
    @debug BIT = 0 /*Print debugging information*/
)
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
    
    DECLARE
        @start_time DATETIME2(7),
        @end_time DATETIME2(7),
        @report NVARCHAR(MAX),
        @memory_narrative NVARCHAR(MAX),
        @io_narrative NVARCHAR(MAX),
        @blocking_narrative NVARCHAR(MAX),
        @wait_narrative NVARCHAR(MAX),
        @memory_issue BIT,
        @io_issue BIT,
        @blocking_issue BIT;
    
    /*
    Set analysis time range
    */
    SELECT
        @end_time = SYSDATETIME(),
        @start_time = DATEADD(HOUR, -@hours_to_analyze, SYSDATETIME());
    
    /*
    Get memory analysis
    */
    DECLARE @memory_results TABLE
    (
        analysis_type NVARCHAR(100),
        detected BIT,
        current_buffer_pool_mb DECIMAL(19,2),
        total_server_memory_mb DECIMAL(19,2),
        buffer_pool_percentage DECIMAL(5,2),
        narrative NVARCHAR(MAX)
    );
    
    INSERT @memory_results
    EXECUTE analysis.analyze_memory_pressure
        @start_time = @start_time,
        @end_time = @end_time,
        @debug = @debug;
    
    SELECT
        @memory_issue = detected,
        @memory_narrative = narrative
    FROM @memory_results;
    
    /*
    Get I/O analysis
    */
    DECLARE @io_results TABLE
    (
        analysis_type NVARCHAR(100),
        detected BIT,
        narrative NVARCHAR(MAX)
    );
    
    INSERT @io_results
    EXECUTE analysis.analyze_io_bottlenecks
        @start_time = @start_time,
        @end_time = @end_time,
        @debug = @debug;
    
    SELECT
        @io_issue = detected,
        @io_narrative = narrative
    FROM @io_results;
    
    /*
    Get blocking analysis
    */
    DECLARE @blocking_results TABLE
    (
        analysis_type NVARCHAR(100),
        detected BIT,
        narrative NVARCHAR(MAX)
    );
    
    INSERT @blocking_results
    EXECUTE analysis.analyze_blocking
        @start_time = @start_time,
        @end_time = @end_time,
        @debug = @debug;
    
    SELECT
        @blocking_issue = detected,
        @blocking_narrative = narrative
    FROM @blocking_results;
    
    /*
    Get wait stats analysis
    */
    DECLARE @wait_results TABLE
    (
        analysis_type NVARCHAR(100),
        narrative NVARCHAR(MAX)
    );
    
    INSERT @wait_results
    EXECUTE analysis.analyze_wait_stats
        @start_time = @start_time,
        @end_time = @end_time,
        @debug = @debug;
    
    SELECT
        @wait_narrative = narrative
    FROM @wait_results;
    
    /*
    Generate comprehensive report
    */
    SELECT
        @report = N'
    ██████╗  █████╗ ██████╗ ██╗     ██╗███╗   ██╗ ██████╗ ██████╗  █████╗ ████████╗ █████╗ 
    ██╔══██╗██╔══██╗██╔══██╗██║     ██║████╗  ██║██╔════╝ ██╔══██╗██╔══██╗╚══██╔══╝██╔══██╗
    ██║  ██║███████║██████╔╝██║     ██║██╔██╗ ██║██║  ███╗██║  ██║███████║   ██║   ███████║
    ██║  ██║██╔══██║██╔══██╗██║     ██║██║╚██╗██║██║   ██║██║  ██║██╔══██║   ██║   ██╔══██║
    ██████╔╝██║  ██║██║  ██║███████╗██║██║ ╚████║╚██████╔╝██████╔╝██║  ██║   ██║   ██║  ██║
    ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝
                                                                                     
    SQL Server Performance Analysis Report
    Generated: ' + CONVERT(NVARCHAR(30), SYSDATETIME(), 121) + '
    Analysis Period: ' + CONVERT(NVARCHAR(30), @start_time, 121) + ' to ' + CONVERT(NVARCHAR(30), @end_time, 121) + '
    ';
    
    /*
    Add system information
    */
    DECLARE
        @server_name NVARCHAR(128),
        @product_version NVARCHAR(128),
        @edition NVARCHAR(128),
        @physical_memory_mb BIGINT,
        @cpu_count INTEGER;
    
    SELECT
        @server_name = server_name,
        @product_version = product_version,
        @edition = edition,
        @physical_memory_mb = physical_memory_mb,
        @cpu_count = cpu_count
    FROM system.server_info;
    
    SET @report = @report + N'
    
    System Information:
    Server: ' + @server_name + '
    Version: ' + @product_version + '
    Edition: ' + @edition + '
    Memory: ' + CAST(@physical_memory_mb AS NVARCHAR(20)) + ' MB
    CPUs: ' + CAST(@cpu_count AS NVARCHAR(10)) + '
    ';
    
    /*
    Add executive summary based on findings
    */
    SET @report = @report + N'
    
    Executive Summary:
    ';
    
    IF @memory_issue = 1 OR @io_issue = 1 OR @blocking_issue = 1
    BEGIN
        SET @report = @report + N'
        Performance issues detected during the analysis period:
        ';
        
        IF @memory_issue = 1
        BEGIN
            SET @report = @report + N'
        - Memory pressure: ' + CAST(100.0 * @memory_issue AS NVARCHAR(10)) + '% buffer pool usage
            ';
        END;
        
        IF @io_issue = 1
        BEGIN
            SET @report = @report + N'
        - I/O bottlenecks: High latency detected on one or more database files
            ';
        END;
        
        IF @blocking_issue = 1
        BEGIN
            SET @report = @report + N'
        - Blocking: Significant blocking chains detected
            ';
        END;
    END;
    ELSE
    BEGIN
        SET @report = @report + N'
        No significant performance issues detected during the analysis period.
        ';
    END;
    
    /*
    Add detailed analysis sections
    */
    
    /* Wait Stats */
    SET @report = @report + N'
    
    ================================
    Wait Statistics Analysis
    ================================
    ' + @wait_narrative;
    
    /* Memory */
    SET @report = @report + N'
    
    ================================
    Memory Analysis
    ================================
    ' + @memory_narrative;
    
    /* I/O */
    SET @report = @report + N'
    
    ================================
    I/O Analysis
    ================================
    ' + @io_narrative;
    
    /* Blocking */
    SET @report = @report + N'
    
    ================================
    Blocking Analysis
    ================================
    ' + @blocking_narrative;
    
    /*
    Return the report
    */
    SELECT
        report_date = SYSDATETIME(),
        analysis_period_start = @start_time,
        analysis_period_end = @end_time,
        memory_issue = @memory_issue,
        io_issue = @io_issue,
        blocking_issue = @blocking_issue,
        performance_report = @report;
END;
GO
```

## Recommendation Engine

The recommendation engine uses the results from the analysis procedures to generate specific, actionable recommendations. These recommendations are prioritized based on their potential impact and include specific T-SQL scripts that can be used for remediation.

## Narrative Generation

The narrative generation engine takes the raw data and analysis results and creates human-readable explanations that tell a cohesive story about the server's performance. This includes:

1. **Executive Summary**
   - Brief overview of the server's health
   - List of top issues identified
   - Overall assessment of performance

2. **Detailed Analysis**
   - In-depth explanation of each issue
   - Correlation between different symptoms
   - Historical context for recurring issues

3. **Recommendations**
   - Specific actions to resolve issues
   - Prioritized list of improvements
   - Sample scripts for implementation

## Usage Examples

To run a comprehensive performance analysis:

```sql
EXECUTE analysis.generate_performance_report
    @hours_to_analyze = 24,
    @debug = 0;
```

To analyze a specific area of concern:

```sql
DECLARE
    @start_time DATETIME2(7) = DATEADD(HOUR, -4, GETDATE()),
    @end_time DATETIME2(7) = GETDATE();

EXECUTE analysis.analyze_memory_pressure
    @start_time = @start_time,
    @end_time = @end_time,
    @debug = 1;
```

## Next Steps

1. Implement additional analysis procedures:
   - Query performance analysis
   - CPU utilization analysis
   - Index usage analysis
   - TempDB contention analysis
   - Parameter sniffing detection

2. Create reporting views and dashboards:
   - Performance trend dashboards
   - Resource utilization charts
   - Top query analysis

3. Integrate with existing monitoring systems:
   - Export results to external systems
   - Create alerting mechanisms
   - Schedule periodic analysis reports