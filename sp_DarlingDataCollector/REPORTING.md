# DarlingDataCollector Reporting System

This document outlines the reporting capabilities of the DarlingDataCollector solution, designed to provide clear visualizations and insights from the collected performance data.

## Supported Environments

DarlingDataCollector Reporting supports the following SQL Server environments:

- On-premises SQL Server
- Azure SQL Managed Instance
- Amazon RDS for SQL Server

> **Note**: Azure SQL Database is **not** supported due to its limitations with SQL Agent jobs and specific system-level DMVs required for proper collection.

## Reporting Architecture

The reporting system consists of several components:

1. **Reporting Views**
   - Simplified data access for reporting tools
   - Pre-aggregated metrics for common reporting needs
   - Delta calculations and trend analysis

2. **Data Export**
   - Functions to export data to CSV or JSON
   - Integration with external reporting tools
   - Scheduled report generation

3. **Dashboard Queries**
   - Pre-built queries for common performance dashboards
   - Parameter-driven reporting for flexible analysis
   - Historical comparisons

## Core Reporting Views

### 1. Wait Statistics Overview

```sql
CREATE OR ALTER VIEW
    reporting.wait_stats_summary
AS
SELECT
    collection_date = CAST(collection_time AS DATE),
    collection_hour = DATEPART(HOUR, collection_time),
    wait_type,
    wait_category = 
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
        END,
    total_wait_time_ms = SUM(wait_time_ms_delta),
    total_wait_time_seconds = SUM(wait_time_ms_delta) / 1000.0,
    total_signal_wait_time_ms = SUM(signal_wait_time_ms_delta),
    waiting_tasks_count = SUM(waiting_tasks_count_delta),
    avg_wait_time_ms = 
        CASE
            WHEN SUM(waiting_tasks_count_delta) > 0 
            THEN SUM(wait_time_ms_delta) / SUM(waiting_tasks_count_delta)
            ELSE 0
        END,
    avg_signal_wait_time_ms = 
        CASE
            WHEN SUM(waiting_tasks_count_delta) > 0 
            THEN SUM(signal_wait_time_ms_delta) / SUM(waiting_tasks_count_delta)
            ELSE 0
        END,
    sample_count = COUNT(*)
FROM collection.wait_stats
WHERE wait_time_ms_delta IS NOT NULL
GROUP BY
    CAST(collection_time AS DATE),
    DATEPART(HOUR, collection_time),
    wait_type,
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
    END;
GO

CREATE OR ALTER VIEW
    reporting.wait_category_summary
AS
SELECT
    collection_date,
    collection_hour,
    wait_category,
    total_wait_time_seconds = SUM(total_wait_time_seconds),
    waiting_tasks_count = SUM(waiting_tasks_count),
    avg_wait_time_ms = 
        CASE
            WHEN SUM(waiting_tasks_count) > 0 
            THEN SUM(total_wait_time_ms) / SUM(waiting_tasks_count)
            ELSE 0
        END
FROM reporting.wait_stats_summary
GROUP BY
    collection_date,
    collection_hour,
    wait_category;
GO
```

### 2. Memory Usage Overview

```sql
CREATE OR ALTER VIEW
    reporting.memory_usage_summary
AS
WITH memory_by_clerk AS
(
    SELECT
        collection_date = CAST(collection_time AS DATE),
        collection_hour = DATEPART(HOUR, collection_time),
        clerk_category = 
            CASE
                WHEN clerk_name LIKE '%CACHESTORE%' THEN 'Cache Store'
                WHEN clerk_name LIKE '%MEMORYCLERK_SQLBUFFERPOOL%' THEN 'Buffer Pool'
                WHEN clerk_name LIKE '%MEMORYCLERK_SQLPLAN%' THEN 'Plan Cache'
                WHEN clerk_name LIKE '%MEMORYCLERK_SQLOPTIMIZER%' THEN 'Optimizer'
                WHEN clerk_name LIKE '%MEMORYCLERK_SQLQERYEXEC%' THEN 'Query Execution'
                WHEN clerk_name LIKE '%MEMORYCLERK_SQLSTORENG%' THEN 'Storage Engine'
                WHEN clerk_name LIKE '%MEMORYCLERK_XE%' THEN 'Extended Events'
                WHEN clerk_name LIKE '%MEMORYCLERK_SQLHTTP%' THEN 'HTTP'
                WHEN clerk_name LIKE '%OBJECTSTORE%' THEN 'Object Store'
                ELSE 'Other'
            END,
        total_kb = SUM(pages_kb),
        virtual_reserved_kb = SUM(virtual_memory_reserved_kb),
        virtual_committed_kb = SUM(virtual_memory_committed_kb)
    FROM collection.memory_clerks
    GROUP BY
        CAST(collection_time AS DATE),
        DATEPART(HOUR, collection_time),
        CASE
            WHEN clerk_name LIKE '%CACHESTORE%' THEN 'Cache Store'
            WHEN clerk_name LIKE '%MEMORYCLERK_SQLBUFFERPOOL%' THEN 'Buffer Pool'
            WHEN clerk_name LIKE '%MEMORYCLERK_SQLPLAN%' THEN 'Plan Cache'
            WHEN clerk_name LIKE '%MEMORYCLERK_SQLOPTIMIZER%' THEN 'Optimizer'
            WHEN clerk_name LIKE '%MEMORYCLERK_SQLQERYEXEC%' THEN 'Query Execution'
            WHEN clerk_name LIKE '%MEMORYCLERK_SQLSTORENG%' THEN 'Storage Engine'
            WHEN clerk_name LIKE '%MEMORYCLERK_XE%' THEN 'Extended Events'
            WHEN clerk_name LIKE '%MEMORYCLERK_SQLHTTP%' THEN 'HTTP'
            WHEN clerk_name LIKE '%OBJECTSTORE%' THEN 'Object Store'
            ELSE 'Other'
        END
),
total_memory AS
(
    SELECT
        collection_date,
        collection_hour,
        total_kb = SUM(total_kb)
    FROM memory_by_clerk
    GROUP BY
        collection_date,
        collection_hour
)
SELECT
    m.collection_date,
    m.collection_hour,
    m.clerk_category,
    m.total_kb,
    total_mb = m.total_kb / 1024.0,
    percentage_of_total = 
        CASE
            WHEN t.total_kb > 0 
            THEN CAST((m.total_kb * 100.0 / t.total_kb) AS DECIMAL(5,2))
            ELSE 0
        END,
    m.virtual_reserved_kb,
    m.virtual_committed_kb
FROM memory_by_clerk AS m
JOIN total_memory AS t
  ON m.collection_date = t.collection_date
  AND m.collection_hour = t.collection_hour;
GO

CREATE OR ALTER VIEW
    reporting.buffer_pool_summary
AS
SELECT
    collection_date = CAST(collection_time AS DATE),
    collection_hour = DATEPART(HOUR, collection_time),
    database_name,
    file_type,
    total_cached_mb = SUM(cached_size_mb),
    total_pages = SUM(page_count)
FROM collection.buffer_pool
GROUP BY
    CAST(collection_time AS DATE),
    DATEPART(HOUR, collection_time),
    database_name,
    file_type;
GO
```

### 3. I/O Performance Overview

```sql
CREATE OR ALTER VIEW
    reporting.io_performance_summary
AS
SELECT
    collection_date = CAST(collection_time AS DATE),
    collection_hour = DATEPART(HOUR, collection_time),
    database_name,
    file_type = type_desc,
    reads_per_second = SUM(num_of_reads_delta) / (SUM(sample_seconds) / 1.0),
    writes_per_second = SUM(num_of_writes_delta) / (SUM(sample_seconds) / 1.0),
    read_mb_per_second = SUM(num_of_bytes_read_delta) / (SUM(sample_seconds) * 1048576.0),
    write_mb_per_second = SUM(num_of_bytes_written_delta) / (SUM(sample_seconds) * 1048576.0),
    avg_read_latency_ms = 
        CASE
            WHEN SUM(num_of_reads_delta) > 0 
            THEN SUM(io_stall_read_ms_delta) / SUM(num_of_reads_delta)
            ELSE 0
        END,
    avg_write_latency_ms = 
        CASE
            WHEN SUM(num_of_writes_delta) > 0 
            THEN SUM(io_stall_write_ms_delta) / SUM(num_of_writes_delta)
            ELSE 0
        END,
    avg_latency_ms = 
        CASE
            WHEN (SUM(num_of_reads_delta) + SUM(num_of_writes_delta)) > 0 
            THEN SUM(io_stall_delta) / (SUM(num_of_reads_delta) + SUM(num_of_writes_delta))
            ELSE 0
        END,
    total_read_mb = SUM(num_of_bytes_read_delta) / 1048576.0,
    total_write_mb = SUM(num_of_bytes_written_delta) / 1048576.0
FROM collection.io_stats
WHERE sample_seconds IS NOT NULL
GROUP BY
    CAST(collection_time AS DATE),
    DATEPART(HOUR, collection_time),
    database_name,
    type_desc;
GO
```

### 4. Query Performance Overview

```sql
CREATE OR ALTER VIEW
    reporting.query_performance_summary
AS
SELECT
    collection_date = CAST(collection_time AS DATE),
    collection_hour = DATEPART(HOUR, collection_time),
    query_hash,
    execution_count = SUM(execution_count_delta),
    total_worker_time_ms = SUM(total_worker_time_delta),
    total_elapsed_time_ms = SUM(total_elapsed_time_delta),
    total_logical_reads = SUM(total_logical_reads_delta),
    total_physical_reads = SUM(total_physical_reads_delta),
    total_logical_writes = SUM(total_logical_writes_delta),
    total_spills = SUM(total_spills_delta),
    avg_worker_time_ms = 
        CASE 
            WHEN SUM(execution_count_delta) > 0 
            THEN SUM(total_worker_time_delta) / SUM(execution_count_delta)
            ELSE 0
        END,
    avg_elapsed_time_ms = 
        CASE 
            WHEN SUM(execution_count_delta) > 0 
            THEN SUM(total_elapsed_time_delta) / SUM(execution_count_delta)
            ELSE 0
        END,
    avg_logical_reads = 
        CASE 
            WHEN SUM(execution_count_delta) > 0 
            THEN SUM(total_logical_reads_delta) / SUM(execution_count_delta)
            ELSE 0
        END,
    avg_physical_reads = 
        CASE 
            WHEN SUM(execution_count_delta) > 0 
            THEN SUM(total_physical_reads_delta) / SUM(execution_count_delta)
            ELSE 0
        END,
    avg_logical_writes = 
        CASE 
            WHEN SUM(execution_count_delta) > 0 
            THEN SUM(total_logical_writes_delta) / SUM(execution_count_delta)
            ELSE 0
        END,
    avg_spills = 
        CASE 
            WHEN SUM(execution_count_delta) > 0 
            THEN SUM(total_spills_delta) / SUM(execution_count_delta)
            ELSE 0
        END,
    sample_query_text = MAX(LEFT(query_text, 1000))
FROM collection.query_stats
WHERE sample_seconds IS NOT NULL
GROUP BY
    CAST(collection_time AS DATE),
    DATEPART(HOUR, collection_time),
    query_hash;
GO

CREATE OR ALTER VIEW
    reporting.top_cpu_queries
AS
SELECT TOP 100
    qps.collection_date,
    qps.collection_hour,
    qps.query_hash,
    qps.execution_count,
    qps.total_worker_time_ms,
    worker_time_seconds = qps.total_worker_time_ms / 1000.0,
    qps.avg_worker_time_ms,
    cpu_percentage = 
        CAST((qps.total_worker_time_ms * 100.0 / 
        SUM(qps.total_worker_time_ms) OVER(PARTITION BY qps.collection_date, qps.collection_hour)) 
        AS DECIMAL(5,2)),
    qps.avg_logical_reads,
    qps.avg_physical_reads,
    qps.sample_query_text
FROM reporting.query_performance_summary AS qps
ORDER BY
    qps.collection_date DESC,
    qps.collection_hour DESC,
    qps.total_worker_time_ms DESC;
GO

CREATE OR ALTER VIEW
    reporting.top_io_queries
AS
SELECT TOP 100
    qps.collection_date,
    qps.collection_hour,
    qps.query_hash,
    qps.execution_count,
    qps.total_logical_reads,
    qps.total_physical_reads,
    qps.avg_logical_reads,
    qps.avg_physical_reads,
    io_percentage = 
        CAST((qps.total_logical_reads * 100.0 / 
        SUM(qps.total_logical_reads) OVER(PARTITION BY qps.collection_date, qps.collection_hour)) 
        AS DECIMAL(5,2)),
    qps.avg_worker_time_ms,
    qps.sample_query_text
FROM reporting.query_performance_summary AS qps
ORDER BY
    qps.collection_date DESC,
    qps.collection_hour DESC,
    qps.total_logical_reads DESC;
GO
```

### 5. Blocking Overview

```sql
CREATE OR ALTER VIEW
    reporting.blocking_summary
AS
SELECT
    collection_date = CAST(collection_time AS DATE),
    collection_hour = DATEPART(HOUR, collection_time),
    blocking_session_id,
    blocked_session_count = COUNT(DISTINCT blocked_session_id),
    max_wait_duration_ms = MAX(wait_duration_ms),
    avg_wait_duration_ms = AVG(wait_duration_ms),
    max_blocking_duration_seconds = MAX(wait_duration_ms) / 1000.0,
    wait_types = STRING_AGG(DISTINCT wait_type, ', '),
    resource_types = STRING_AGG(DISTINCT resource_description, ', '),
    blocking_login_name,
    blocking_program_name,
    blocking_sql_text = MAX(LEFT(blocking_sql_text, 1000))
FROM collection.blocking
GROUP BY
    CAST(collection_time AS DATE),
    DATEPART(HOUR, collection_time),
    blocking_session_id,
    blocking_login_name,
    blocking_program_name;
GO
```

## Dashboard Queries

The following queries are designed to power performance dashboards and provide meaningful insights into the collected data.

### 1. Wait Stats Dashboard

```sql
-- Top Wait Categories by Day/Hour
SELECT
    collection_date,
    collection_hour,
    wait_category,
    total_wait_time_seconds,
    percentage = 
        CAST((total_wait_time_seconds * 100.0 / 
        SUM(total_wait_time_seconds) OVER(PARTITION BY collection_date, collection_hour)) 
        AS DECIMAL(5,2)),
    waiting_tasks_count,
    avg_wait_time_ms
FROM reporting.wait_category_summary
WHERE collection_date >= DATEADD(DAY, -7, GETDATE())
ORDER BY
    collection_date DESC,
    collection_hour DESC,
    total_wait_time_seconds DESC;

-- Wait Category Trends (Daily)
SELECT
    collection_date,
    wait_category,
    total_wait_time_seconds = SUM(total_wait_time_seconds),
    percentage = 
        CAST((SUM(total_wait_time_seconds) * 100.0 / 
        SUM(SUM(total_wait_time_seconds)) OVER(PARTITION BY collection_date)) 
        AS DECIMAL(5,2)),
    waiting_tasks_count = SUM(waiting_tasks_count)
FROM reporting.wait_category_summary
WHERE collection_date >= DATEADD(DAY, -30, GETDATE())
GROUP BY
    collection_date,
    wait_category
ORDER BY
    collection_date DESC,
    total_wait_time_seconds DESC;

-- Top Individual Wait Types
SELECT TOP 10
    collection_date,
    collection_hour,
    wait_type,
    wait_category,
    total_wait_time_seconds,
    waiting_tasks_count,
    avg_wait_time_ms
FROM reporting.wait_stats_summary
WHERE 
    collection_date >= DATEADD(DAY, -1, GETDATE())
ORDER BY
    collection_date DESC,
    collection_hour DESC,
    total_wait_time_seconds DESC;
```

### 2. Memory Dashboard

```sql
-- Memory Usage by Clerk Category
SELECT
    collection_date,
    collection_hour,
    clerk_category,
    total_mb,
    percentage_of_total
FROM reporting.memory_usage_summary
WHERE collection_date >= DATEADD(DAY, -7, GETDATE())
ORDER BY
    collection_date DESC,
    collection_hour DESC,
    total_mb DESC;

-- Buffer Pool Usage by Database
SELECT
    collection_date,
    collection_hour,
    database_name,
    file_type,
    total_cached_mb,
    buffer_pool_percentage = 
        CAST((total_cached_mb * 100.0 / 
        SUM(total_cached_mb) OVER(PARTITION BY collection_date, collection_hour)) 
        AS DECIMAL(5,2))
FROM reporting.buffer_pool_summary
WHERE collection_date >= DATEADD(DAY, -7, GETDATE())
ORDER BY
    collection_date DESC,
    collection_hour DESC,
    total_cached_mb DESC;

-- Memory Pressure Indicators
SELECT
    w.collection_date,
    w.collection_hour,
    memory_pressure_indicator = 
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM reporting.wait_stats_summary AS ws
                WHERE 
                    ws.collection_date = w.collection_date
                    AND ws.collection_hour = w.collection_hour
                    AND ws.wait_type = 'RESOURCE_SEMAPHORE'
                    AND ws.total_wait_time_ms > 1000
            ) THEN 'Memory Grant Pressure'
            WHEN EXISTS (
                SELECT 1
                FROM reporting.wait_stats_summary AS ws
                WHERE 
                    ws.collection_date = w.collection_date
                    AND ws.collection_hour = w.collection_hour
                    AND ws.wait_type = 'PAGEIOLATCH_SH'
                    AND ws.total_wait_time_ms > 5000
            ) THEN 'Buffer Pool Pressure'
            ELSE 'Normal'
        END,
    resource_semaphore_wait_time_ms = 
        (SELECT ISNULL(SUM(ws.total_wait_time_ms), 0)
         FROM reporting.wait_stats_summary AS ws
         WHERE 
             ws.collection_date = w.collection_date
             AND ws.collection_hour = w.collection_hour
             AND ws.wait_type = 'RESOURCE_SEMAPHORE'),
    page_io_latch_wait_time_ms = 
        (SELECT ISNULL(SUM(ws.total_wait_time_ms), 0)
         FROM reporting.wait_stats_summary AS ws
         WHERE 
             ws.collection_date = w.collection_date
             AND ws.collection_hour = w.collection_hour
             AND ws.wait_type LIKE 'PAGEIOLATCH%'),
    buffer_pool_size_mb = 
        (SELECT ISNULL(SUM(m.total_mb), 0)
         FROM reporting.memory_usage_summary AS m
         WHERE 
             m.collection_date = w.collection_date
             AND m.collection_hour = w.collection_hour
             AND m.clerk_category = 'Buffer Pool')
FROM (
    SELECT DISTINCT
        collection_date,
        collection_hour
    FROM reporting.wait_stats_summary
    WHERE collection_date >= DATEADD(DAY, -7, GETDATE())
) AS w
ORDER BY
    w.collection_date DESC,
    w.collection_hour DESC;
```

### 3. I/O Dashboard

```sql
-- I/O Performance by Database
SELECT
    collection_date,
    collection_hour,
    database_name,
    file_type,
    reads_per_second,
    writes_per_second,
    read_mb_per_second,
    write_mb_per_second,
    avg_read_latency_ms,
    avg_write_latency_ms,
    avg_latency_ms,
    total_read_mb,
    total_write_mb
FROM reporting.io_performance_summary
WHERE collection_date >= DATEADD(DAY, -7, GETDATE())
ORDER BY
    collection_date DESC,
    collection_hour DESC,
    (read_mb_per_second + write_mb_per_second) DESC;

-- High Latency Files
SELECT
    collection_date,
    collection_hour,
    database_name,
    file_type,
    avg_read_latency_ms,
    avg_write_latency_ms,
    reads_per_second,
    writes_per_second,
    read_mb_per_second,
    write_mb_per_second
FROM reporting.io_performance_summary
WHERE 
    collection_date >= DATEADD(DAY, -7, GETDATE())
    AND (avg_read_latency_ms > 20 OR avg_write_latency_ms > 20)
ORDER BY
    collection_date DESC,
    collection_hour DESC,
    CASE WHEN avg_read_latency_ms > avg_write_latency_ms 
         THEN avg_read_latency_ms 
         ELSE avg_write_latency_ms 
    END DESC;

-- I/O Wait Stats
SELECT
    w.collection_date,
    w.collection_hour,
    wait_type,
    total_wait_time_seconds,
    waiting_tasks_count,
    avg_wait_time_ms
FROM reporting.wait_stats_summary AS w
WHERE 
    w.collection_date >= DATEADD(DAY, -7, GETDATE())
    AND w.wait_type IN ('PAGEIOLATCH_SH', 'PAGEIOLATCH_EX', 'PAGEIOLATCH_UP', 'WRITELOG', 'IO_COMPLETION')
ORDER BY
    w.collection_date DESC,
    w.collection_hour DESC,
    total_wait_time_seconds DESC;
```

### 4. Query Performance Dashboard

```sql
-- Top CPU Consuming Queries
SELECT
    collection_date,
    collection_hour,
    query_hash,
    execution_count,
    worker_time_seconds,
    avg_worker_time_ms,
    cpu_percentage,
    avg_logical_reads,
    avg_physical_reads,
    sample_query_text
FROM reporting.top_cpu_queries
WHERE collection_date >= DATEADD(DAY, -1, GETDATE())
ORDER BY
    collection_date DESC,
    collection_hour DESC,
    worker_time_seconds DESC;

-- Top I/O Consuming Queries
SELECT
    collection_date,
    collection_hour,
    query_hash,
    execution_count,
    total_logical_reads,
    total_physical_reads,
    avg_logical_reads,
    avg_physical_reads,
    io_percentage,
    avg_worker_time_ms,
    sample_query_text
FROM reporting.top_io_queries
WHERE collection_date >= DATEADD(DAY, -1, GETDATE())
ORDER BY
    collection_date DESC,
    collection_hour DESC,
    total_logical_reads DESC;

-- Query Execution Trends
WITH query_trends AS
(
    SELECT
        collection_date,
        collection_hour,
        hour_bucket = collection_date + CAST(collection_hour AS FLOAT) / 24,
        SUM(execution_count) AS total_executions,
        SUM(total_worker_time_ms) / 1000.0 AS total_cpu_seconds,
        SUM(total_elapsed_time_ms) / 1000.0 AS total_duration_seconds,
        SUM(total_logical_reads) AS total_logical_reads,
        SUM(total_physical_reads) AS total_physical_reads
    FROM reporting.query_performance_summary
    WHERE collection_date >= DATEADD(DAY, -7, GETDATE())
    GROUP BY
        collection_date,
        collection_hour
)
SELECT
    collection_date,
    collection_hour,
    hour_bucket,
    total_executions,
    total_cpu_seconds,
    total_duration_seconds,
    total_logical_reads,
    total_physical_reads,
    cpu_per_execution_ms = 
        CASE 
            WHEN total_executions > 0 
            THEN (total_cpu_seconds * 1000) / total_executions
            ELSE 0
        END,
    duration_per_execution_ms = 
        CASE 
            WHEN total_executions > 0 
            THEN (total_duration_seconds * 1000) / total_executions
            ELSE 0
        END,
    reads_per_execution = 
        CASE 
            WHEN total_executions > 0 
            THEN total_logical_reads / total_executions
            ELSE 0
        END
FROM query_trends
ORDER BY
    hour_bucket DESC;
```

### 5. Blocking Dashboard

```sql
-- Top Blocking Sessions
SELECT
    collection_date,
    collection_hour,
    blocking_session_id,
    blocked_session_count,
    max_blocking_duration_seconds,
    avg_wait_duration_ms,
    wait_types,
    resource_types,
    blocking_login_name,
    blocking_program_name,
    blocking_sql_text
FROM reporting.blocking_summary
WHERE collection_date >= DATEADD(DAY, -7, GETDATE())
ORDER BY
    collection_date DESC,
    collection_hour DESC,
    max_wait_duration_ms DESC;

-- Blocking Trends
SELECT
    collection_date,
    blocking_hour = collection_hour,
    blocking_count = COUNT(DISTINCT blocking_session_id),
    blocked_session_count = SUM(blocked_session_count),
    max_blocking_duration_seconds = MAX(max_blocking_duration_seconds),
    avg_blocking_duration_seconds = AVG(max_blocking_duration_seconds)
FROM reporting.blocking_summary
WHERE collection_date >= DATEADD(DAY, -30, GETDATE())
GROUP BY
    collection_date,
    collection_hour
ORDER BY
    collection_date DESC,
    collection_hour DESC;
```

## Data Export Functions

### CSV Export

```sql
CREATE OR ALTER PROCEDURE
    reporting.export_data_to_csv
(
    @start_date DATE,
    @end_date DATE,
    @report_type VARCHAR(50), /*Options: 'WaitStats', 'Memory', 'IO', 'Queries', 'Blocking'*/
    @file_path VARCHAR(500),
    @debug BIT = 0 /*Print debugging information*/
)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE
        @sql NVARCHAR(MAX),
        @cmd NVARCHAR(4000);
    
    /*
    Build query based on report type
    */
    IF @report_type = 'WaitStats'
    BEGIN
        SET @sql = N'
        SELECT
            collection_date,
            collection_hour,
            wait_category,
            total_wait_time_seconds,
            waiting_tasks_count,
            avg_wait_time_ms
        FROM reporting.wait_category_summary
        WHERE collection_date BETWEEN @start_date AND @end_date
        ORDER BY
            collection_date,
            collection_hour,
            total_wait_time_seconds DESC
        FOR XML PATH(''row''), ROOT(''data''), ELEMENTS';
    END;
    ELSE IF @report_type = 'Memory'
    BEGIN
        SET @sql = N'
        SELECT
            collection_date,
            collection_hour,
            clerk_category,
            total_mb,
            percentage_of_total
        FROM reporting.memory_usage_summary
        WHERE collection_date BETWEEN @start_date AND @end_date
        ORDER BY
            collection_date,
            collection_hour,
            total_mb DESC
        FOR XML PATH(''row''), ROOT(''data''), ELEMENTS';
    END;
    ELSE IF @report_type = 'IO'
    BEGIN
        SET @sql = N'
        SELECT
            collection_date,
            collection_hour,
            database_name,
            file_type,
            reads_per_second,
            writes_per_second,
            read_mb_per_second,
            write_mb_per_second,
            avg_read_latency_ms,
            avg_write_latency_ms,
            avg_latency_ms
        FROM reporting.io_performance_summary
        WHERE collection_date BETWEEN @start_date AND @end_date
        ORDER BY
            collection_date,
            collection_hour,
            (read_mb_per_second + write_mb_per_second) DESC
        FOR XML PATH(''row''), ROOT(''data''), ELEMENTS';
    END;
    ELSE IF @report_type = 'Queries'
    BEGIN
        SET @sql = N'
        SELECT TOP 1000
            collection_date,
            collection_hour,
            query_hash,
            execution_count,
            total_worker_time_ms,
            total_elapsed_time_ms,
            total_logical_reads,
            total_physical_reads,
            avg_worker_time_ms,
            avg_logical_reads,
            CONVERT(VARCHAR(1000), sample_query_text) AS sample_query_text
        FROM reporting.query_performance_summary
        WHERE collection_date BETWEEN @start_date AND @end_date
        ORDER BY
            collection_date,
            collection_hour,
            total_worker_time_ms DESC
        FOR XML PATH(''row''), ROOT(''data''), ELEMENTS';
    END;
    ELSE IF @report_type = 'Blocking'
    BEGIN
        SET @sql = N'
        SELECT
            collection_date,
            collection_hour,
            blocking_session_id,
            blocked_session_count,
            max_blocking_duration_seconds,
            avg_wait_duration_ms,
            wait_types,
            resource_types,
            blocking_login_name,
            blocking_program_name,
            CONVERT(VARCHAR(1000), blocking_sql_text) AS blocking_sql_text
        FROM reporting.blocking_summary
        WHERE collection_date BETWEEN @start_date AND @end_date
        ORDER BY
            collection_date,
            collection_hour,
            max_wait_duration_ms DESC
        FOR XML PATH(''row''), ROOT(''data''), ELEMENTS';
    END;
    ELSE
    BEGIN
        RAISERROR('Invalid report type. Valid options are: WaitStats, Memory, IO, Queries, Blocking', 16, 1);
        RETURN;
    END;
    
    /*
    Execute query and export to CSV
    */
    SET @cmd = N'
    SET @xml = (
        ' + @sql + N'
    );
    
    SELECT
        @csv = ''collection_date,collection_hour,'' + 
        CASE @report_type
            WHEN ''WaitStats'' THEN ''wait_category,total_wait_time_seconds,waiting_tasks_count,avg_wait_time_ms''
            WHEN ''Memory'' THEN ''clerk_category,total_mb,percentage_of_total''
            WHEN ''IO'' THEN ''database_name,file_type,reads_per_second,writes_per_second,read_mb_per_second,write_mb_per_second,avg_read_latency_ms,avg_write_latency_ms,avg_latency_ms''
            WHEN ''Queries'' THEN ''query_hash,execution_count,total_worker_time_ms,total_elapsed_time_ms,total_logical_reads,total_physical_reads,avg_worker_time_ms,avg_logical_reads,sample_query_text''
            WHEN ''Blocking'' THEN ''blocking_session_id,blocked_session_count,max_blocking_duration_seconds,avg_wait_duration_ms,wait_types,resource_types,blocking_login_name,blocking_program_name,blocking_sql_text''
        END + CHAR(13) + CHAR(10);
    
    SELECT
        @csv = @csv + 
        CONVERT(VARCHAR(10), T.c.value(''collection_date[1]'', ''date''), 120) + '','' +
        CAST(T.c.value(''collection_hour[1]'', ''int'') AS VARCHAR(10)) + '','' +
        CASE @report_type
            WHEN ''WaitStats'' THEN
                ISNULL(T.c.value(''wait_category[1]'', ''varchar(100)''), '''') + '','' +
                ISNULL(CAST(T.c.value(''total_wait_time_seconds[1]'', ''decimal(19,2)'') AS VARCHAR(20)), ''0'') + '','' +
                ISNULL(CAST(T.c.value(''waiting_tasks_count[1]'', ''bigint'') AS VARCHAR(20)), ''0'') + '','' +
                ISNULL(CAST(T.c.value(''avg_wait_time_ms[1]'', ''decimal(19,2)'') AS VARCHAR(20)), ''0'')
            WHEN ''Memory'' THEN
                ISNULL(T.c.value(''clerk_category[1]'', ''varchar(100)''), '''') + '','' +
                ISNULL(CAST(T.c.value(''total_mb[1]'', ''decimal(19,2)'') AS VARCHAR(20)), ''0'') + '','' +
                ISNULL(CAST(T.c.value(''percentage_of_total[1]'', ''decimal(5,2)'') AS VARCHAR(10)), ''0'')
            WHEN ''IO'' THEN
                ISNULL(T.c.value(''database_name[1]'', ''varchar(128)''), '''') + '','' +
                ISNULL(T.c.value(''file_type[1]'', ''varchar(60)''), '''') + '','' +
                ISNULL(CAST(T.c.value(''reads_per_second[1]'', ''decimal(19,2)'') AS VARCHAR(20)), ''0'') + '','' +
                ISNULL(CAST(T.c.value(''writes_per_second[1]'', ''decimal(19,2)'') AS VARCHAR(20)), ''0'') + '','' +
                ISNULL(CAST(T.c.value(''read_mb_per_second[1]'', ''decimal(19,2)'') AS VARCHAR(20)), ''0'') + '','' +
                ISNULL(CAST(T.c.value(''write_mb_per_second[1]'', ''decimal(19,2)'') AS VARCHAR(20)), ''0'') + '','' +
                ISNULL(CAST(T.c.value(''avg_read_latency_ms[1]'', ''decimal(19,2)'') AS VARCHAR(20)), ''0'') + '','' +
                ISNULL(CAST(T.c.value(''avg_write_latency_ms[1]'', ''decimal(19,2)'') AS VARCHAR(20)), ''0'') + '','' +
                ISNULL(CAST(T.c.value(''avg_latency_ms[1]'', ''decimal(19,2)'') AS VARCHAR(20)), ''0'')
            WHEN ''Queries'' THEN
                ISNULL(CAST(T.c.value(''query_hash[1]'', ''varchar(50)'') AS VARCHAR(50)), '''') + '','' +
                ISNULL(CAST(T.c.value(''execution_count[1]'', ''bigint'') AS VARCHAR(20)), ''0'') + '','' +
                ISNULL(CAST(T.c.value(''total_worker_time_ms[1]'', ''bigint'') AS VARCHAR(20)), ''0'') + '','' +
                ISNULL(CAST(T.c.value(''total_elapsed_time_ms[1]'', ''bigint'') AS VARCHAR(20)), ''0'') + '','' +
                ISNULL(CAST(T.c.value(''total_logical_reads[1]'', ''bigint'') AS VARCHAR(20)), ''0'') + '','' +
                ISNULL(CAST(T.c.value(''total_physical_reads[1]'', ''bigint'') AS VARCHAR(20)), ''0'') + '','' +
                ISNULL(CAST(T.c.value(''avg_worker_time_ms[1]'', ''decimal(19,2)'') AS VARCHAR(20)), ''0'') + '','' +
                ISNULL(CAST(T.c.value(''avg_logical_reads[1]'', ''decimal(19,2)'') AS VARCHAR(20)), ''0'') + '','' +
                REPLACE(ISNULL(T.c.value(''sample_query_text[1]'', ''varchar(1000)''), ''''), ''"'', ''""'')
            WHEN ''Blocking'' THEN
                ISNULL(CAST(T.c.value(''blocking_session_id[1]'', ''int'') AS VARCHAR(10)), ''0'') + '','' +
                ISNULL(CAST(T.c.value(''blocked_session_count[1]'', ''int'') AS VARCHAR(10)), ''0'') + '','' +
                ISNULL(CAST(T.c.value(''max_blocking_duration_seconds[1]'', ''decimal(19,2)'') AS VARCHAR(20)), ''0'') + '','' +
                ISNULL(CAST(T.c.value(''avg_wait_duration_ms[1]'', ''decimal(19,2)'') AS VARCHAR(20)), ''0'') + '','' +
                ISNULL(T.c.value(''wait_types[1]'', ''varchar(500)''), '''') + '','' +
                ISNULL(T.c.value(''resource_types[1]'', ''varchar(500)''), '''') + '','' +
                ISNULL(T.c.value(''blocking_login_name[1]'', ''varchar(128)''), '''') + '','' +
                ISNULL(T.c.value(''blocking_program_name[1]'', ''varchar(128)''), '''') + '','' +
                REPLACE(ISNULL(T.c.value(''blocking_sql_text[1]'', ''varchar(1000)''), ''''), ''"'', ''""'')
        END + CHAR(13) + CHAR(10)
    FROM @xml.nodes(''/data/row'') T(c);
    ';
    
    DECLARE
        @xml XML,
        @csv NVARCHAR(MAX);
    
    DECLARE @params NVARCHAR(500) = N'@start_date DATE, @end_date DATE, @report_type VARCHAR(50), @xml XML OUTPUT, @csv NVARCHAR(MAX) OUTPUT';
    
    EXECUTE sp_executesql
        @cmd,
        @params,
        @start_date = @start_date,
        @end_date = @end_date,
        @report_type = @report_type,
        @xml = @xml OUTPUT,
        @csv = @csv OUTPUT;
    
    /*
    Write to file using xp_cmdshell if available
    */
    IF EXISTS (SELECT 1 FROM sys.configurations WHERE name = 'xp_cmdshell' AND value_in_use = 1)
    BEGIN
        DECLARE @file_cmd NVARCHAR(4000);
        SET @file_cmd = 'ECHO ' + REPLACE(@csv, CHAR(13) + CHAR(10), ' & ECHO ') + ' > "' + @file_path + '"';
        
        IF @debug = 1
        BEGIN
            PRINT 'Executing command: ' + LEFT(@file_cmd, 1000) + '...';
        END;
        
        EXEC xp_cmdshell @file_cmd;
        
        IF @debug = 1
        BEGIN
            PRINT 'Export completed to: ' + @file_path;
        END;
    END;
    ELSE
    BEGIN
        /*
        Return result for manual export if xp_cmdshell not available
        */
        SELECT
            @csv AS csv_data,
            'xp_cmdshell is not enabled. Copy the csv_data to a file manually.' AS instructions;
    END;
END;
GO
```

### HTML Report Generation

```sql
CREATE OR ALTER PROCEDURE
    reporting.generate_html_report
(
    @start_date DATE,
    @end_date DATE = NULL,
    @report_types VARCHAR(100) = 'All', /*Options: 'All', 'WaitStats', 'Memory', 'IO', 'Queries', 'Blocking'*/
    @file_path VARCHAR(500) = NULL,
    @debug BIT = 0 /*Print debugging information*/
)
AS
BEGIN
    SET NOCOUNT ON;
    
    /*
    Set default end date to today if not specified
    */
    IF @end_date IS NULL
    BEGIN
        SET @end_date = CAST(GETDATE() AS DATE);
    END;
    
    DECLARE
        @html NVARCHAR(MAX),
        @server_info NVARCHAR(MAX),
        @wait_stats_section NVARCHAR(MAX),
        @memory_section NVARCHAR(MAX),
        @io_section NVARCHAR(MAX),
        @query_section NVARCHAR(MAX),
        @blocking_section NVARCHAR(MAX);
    
    /*
    Get server information
    */
    SELECT
        @server_info = N'
        <h2>Server Information</h2>
        <table class="info-table">
            <tr><th>Server</th><td>' + server_name + '</td></tr>
            <tr><th>Version</th><td>' + product_version + '</td></tr>
            <tr><th>Edition</th><td>' + edition + '</td></tr>
            <tr><th>Memory</th><td>' + CAST(physical_memory_mb AS NVARCHAR(20)) + ' MB</td></tr>
            <tr><th>CPUs</th><td>' + CAST(cpu_count AS NVARCHAR(10)) + '</td></tr>
        </table>'
    FROM system.server_info;
    
    /*
    Generate wait stats section
    */
    IF @report_types = 'All' OR @report_types LIKE '%WaitStats%'
    BEGIN
        SET @wait_stats_section = N'
        <h2>Wait Statistics Summary</h2>
        <p>Top wait categories by total wait time during the analysis period.</p>
        <table class="data-table">
            <tr>
                <th>Date</th>
                <th>Hour</th>
                <th>Wait Category</th>
                <th>Wait Time (sec)</th>
                <th>Percentage</th>
                <th>Waiting Tasks</th>
                <th>Avg Wait (ms)</th>
            </tr>';
            
        WITH wait_data AS
        (
            SELECT
                collection_date,
                collection_hour,
                wait_category,
                total_wait_time_seconds,
                percentage = 
                    CAST((total_wait_time_seconds * 100.0 / 
                    SUM(total_wait_time_seconds) OVER(PARTITION BY collection_date, collection_hour)) 
                    AS DECIMAL(5,2)),
                waiting_tasks_count,
                avg_wait_time_ms
            FROM reporting.wait_category_summary
            WHERE collection_date BETWEEN @start_date AND @end_date
        )
        SELECT TOP 1000
            @wait_stats_section = @wait_stats_section + 
            N'<tr>' +
            N'<td>' + CONVERT(NVARCHAR(10), collection_date, 120) + N'</td>' +
            N'<td>' + CAST(collection_hour AS NVARCHAR(2)) + N'</td>' +
            N'<td>' + wait_category + N'</td>' +
            N'<td>' + CAST(CAST(total_wait_time_seconds AS DECIMAL(19,2)) AS NVARCHAR(20)) + N'</td>' +
            N'<td>' + CAST(CAST(percentage AS DECIMAL(5,2)) AS NVARCHAR(10)) + N'%</td>' +
            N'<td>' + CAST(waiting_tasks_count AS NVARCHAR(20)) + N'</td>' +
            N'<td>' + CAST(CAST(avg_wait_time_ms AS DECIMAL(19,2)) AS NVARCHAR(20)) + N'</td>' +
            N'</tr>'
        FROM wait_data
        ORDER BY
            collection_date DESC,
            collection_hour DESC,
            percentage DESC;
            
        SET @wait_stats_section = @wait_stats_section + N'
        </table>';
    END;
    
    /*
    Generate memory section
    */
    IF @report_types = 'All' OR @report_types LIKE '%Memory%'
    BEGIN
        SET @memory_section = N'
        <h2>Memory Usage Summary</h2>
        <p>Memory usage by clerk category during the analysis period.</p>
        <table class="data-table">
            <tr>
                <th>Date</th>
                <th>Hour</th>
                <th>Clerk Category</th>
                <th>Memory (MB)</th>
                <th>Percentage</th>
            </tr>';
            
        SELECT TOP 1000
            @memory_section = @memory_section + 
            N'<tr>' +
            N'<td>' + CONVERT(NVARCHAR(10), collection_date, 120) + N'</td>' +
            N'<td>' + CAST(collection_hour AS NVARCHAR(2)) + N'</td>' +
            N'<td>' + clerk_category + N'</td>' +
            N'<td>' + CAST(CAST(total_mb AS DECIMAL(19,2)) AS NVARCHAR(20)) + N'</td>' +
            N'<td>' + CAST(CAST(percentage_of_total AS DECIMAL(5,2)) AS NVARCHAR(10)) + N'%</td>' +
            N'</tr>'
        FROM reporting.memory_usage_summary
        WHERE collection_date BETWEEN @start_date AND @end_date
        ORDER BY
            collection_date DESC,
            collection_hour DESC,
            total_mb DESC;
            
        SET @memory_section = @memory_section + N'
        </table>';
    END;
    
    /*
    Generate I/O section
    */
    IF @report_types = 'All' OR @report_types LIKE '%IO%'
    BEGIN
        SET @io_section = N'
        <h2>I/O Performance Summary</h2>
        <p>I/O metrics by database during the analysis period.</p>
        <table class="data-table">
            <tr>
                <th>Date</th>
                <th>Hour</th>
                <th>Database</th>
                <th>File Type</th>
                <th>Reads/sec</th>
                <th>Writes/sec</th>
                <th>Read MB/sec</th>
                <th>Write MB/sec</th>
                <th>Read Latency (ms)</th>
                <th>Write Latency (ms)</th>
                <th>Avg Latency (ms)</th>
            </tr>';
            
        SELECT TOP 1000
            @io_section = @io_section + 
            N'<tr>' +
            N'<td>' + CONVERT(NVARCHAR(10), collection_date, 120) + N'</td>' +
            N'<td>' + CAST(collection_hour AS NVARCHAR(2)) + N'</td>' +
            N'<td>' + ISNULL(database_name, 'Unknown') + N'</td>' +
            N'<td>' + ISNULL(file_type, 'Unknown') + N'</td>' +
            N'<td>' + CAST(CAST(reads_per_second AS DECIMAL(19,2)) AS NVARCHAR(20)) + N'</td>' +
            N'<td>' + CAST(CAST(writes_per_second AS DECIMAL(19,2)) AS NVARCHAR(20)) + N'</td>' +
            N'<td>' + CAST(CAST(read_mb_per_second AS DECIMAL(19,2)) AS NVARCHAR(20)) + N'</td>' +
            N'<td>' + CAST(CAST(write_mb_per_second AS DECIMAL(19,2)) AS NVARCHAR(20)) + N'</td>' +
            N'<td>' + CAST(CAST(avg_read_latency_ms AS DECIMAL(19,2)) AS NVARCHAR(20)) + N'</td>' +
            N'<td>' + CAST(CAST(avg_write_latency_ms AS DECIMAL(19,2)) AS NVARCHAR(20)) + N'</td>' +
            N'<td>' + CAST(CAST(avg_latency_ms AS DECIMAL(19,2)) AS NVARCHAR(20)) + N'</td>' +
            N'</tr>'
        FROM reporting.io_performance_summary
        WHERE collection_date BETWEEN @start_date AND @end_date
        ORDER BY
            collection_date DESC,
            collection_hour DESC,
            (read_mb_per_second + write_mb_per_second) DESC;
            
        SET @io_section = @io_section + N'
        </table>';
    END;
    
    /*
    Generate query section
    */
    IF @report_types = 'All' OR @report_types LIKE '%Queries%'
    BEGIN
        SET @query_section = N'
        <h2>Top CPU Consuming Queries</h2>
        <p>Queries with highest CPU usage during the analysis period.</p>
        <table class="data-table">
            <tr>
                <th>Date</th>
                <th>Hour</th>
                <th>Query Hash</th>
                <th>Executions</th>
                <th>CPU Time (sec)</th>
                <th>Avg CPU (ms)</th>
                <th>CPU %</th>
                <th>Avg Reads</th>
                <th>Query Text</th>
            </tr>';
            
        SELECT TOP 100
            @query_section = @query_section + 
            N'<tr>' +
            N'<td>' + CONVERT(NVARCHAR(10), collection_date, 120) + N'</td>' +
            N'<td>' + CAST(collection_hour AS NVARCHAR(2)) + N'</td>' +
            N'<td>' + CAST(query_hash AS NVARCHAR(20)) + N'</td>' +
            N'<td>' + CAST(execution_count AS NVARCHAR(20)) + N'</td>' +
            N'<td>' + CAST(worker_time_seconds AS NVARCHAR(20)) + N'</td>' +
            N'<td>' + CAST(CAST(avg_worker_time_ms AS DECIMAL(19,2)) AS NVARCHAR(20)) + N'</td>' +
            N'<td>' + CAST(CAST(cpu_percentage AS DECIMAL(5,2)) AS NVARCHAR(10)) + N'%</td>' +
            N'<td>' + CAST(CAST(avg_logical_reads AS DECIMAL(19,2)) AS NVARCHAR(20)) + N'</td>' +
            N'<td class="query-text">' + REPLACE(REPLACE(LEFT(sample_query_text, 300), '<', '&lt;'), '>', '&gt;') + N'</td>' +
            N'</tr>'
        FROM reporting.top_cpu_queries
        WHERE collection_date BETWEEN @start_date AND @end_date
        ORDER BY
            collection_date DESC,
            collection_hour DESC,
            worker_time_seconds DESC;
            
        SET @query_section = @query_section + N'
        </table>';
    END;
    
    /*
    Generate blocking section
    */
    IF @report_types = 'All' OR @report_types LIKE '%Blocking%'
    BEGIN
        SET @blocking_section = N'
        <h2>Blocking Summary</h2>
        <p>Significant blocking events during the analysis period.</p>
        <table class="data-table">
            <tr>
                <th>Date</th>
                <th>Hour</th>
                <th>Blocker</th>
                <th>Blocked Sessions</th>
                <th>Max Duration (sec)</th>
                <th>Avg Wait (ms)</th>
                <th>Wait Types</th>
                <th>Login Name</th>
                <th>Program</th>
                <th>SQL Text</th>
            </tr>';
            
        SELECT TOP 100
            @blocking_section = @blocking_section + 
            N'<tr>' +
            N'<td>' + CONVERT(NVARCHAR(10), collection_date, 120) + N'</td>' +
            N'<td>' + CAST(collection_hour AS NVARCHAR(2)) + N'</td>' +
            N'<td>' + CAST(blocking_session_id AS NVARCHAR(10)) + N'</td>' +
            N'<td>' + CAST(blocked_session_count AS NVARCHAR(10)) + N'</td>' +
            N'<td>' + CAST(CAST(max_blocking_duration_seconds AS DECIMAL(19,2)) AS NVARCHAR(20)) + N'</td>' +
            N'<td>' + CAST(CAST(avg_wait_duration_ms AS DECIMAL(19,2)) AS NVARCHAR(20)) + N'</td>' +
            N'<td>' + LEFT(wait_types, 100) + N'</td>' +
            N'<td>' + ISNULL(blocking_login_name, 'Unknown') + N'</td>' +
            N'<td>' + ISNULL(blocking_program_name, 'Unknown') + N'</td>' +
            N'<td class="query-text">' + REPLACE(REPLACE(LEFT(blocking_sql_text, 300), '<', '&lt;'), '>', '&gt;') + N'</td>' +
            N'</tr>'
        FROM reporting.blocking_summary
        WHERE collection_date BETWEEN @start_date AND @end_date
        ORDER BY
            collection_date DESC,
            collection_hour DESC,
            max_blocking_duration_seconds DESC;
            
        SET @blocking_section = @blocking_section + N'
        </table>';
    END;
    
    /*
    Combine all sections into final HTML
    */
    SET @html = N'
    <!DOCTYPE html>
    <html>
    <head>
        <title>SQL Server Performance Report</title>
        <style>
            body { font-family: Arial, sans-serif; margin: 20px; }
            h1 { color: #1a237e; }
            h2 { color: #283593; margin-top: 30px; }
            table { border-collapse: collapse; width: 100%; margin-bottom: 20px; }
            th { background-color: #e8eaf6; text-align: left; padding: 8px; }
            td { padding: 8px; border-bottom: 1px solid #ddd; }
            tr:hover { background-color: #f5f5f5; }
            .info-table { width: auto; }
            .info-table th { width: 120px; }
            .data-table { font-size: 0.9em; }
            .query-text { font-family: monospace; font-size: 0.8em; max-width: 500px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
            .header { background-color: #3f51b5; color: white; padding: 20px; margin-bottom: 20px; }
            .footer { font-size: 0.8em; color: #666; margin-top: 40px; text-align: center; }
        </style>
    </head>
    <body>
        <div class="header">
            <h1>SQL Server Performance Report</h1>
            <p>Analysis Period: ' + CONVERT(NVARCHAR(10), @start_date, 120) + ' to ' + CONVERT(NVARCHAR(10), @end_date, 120) + '</p>
        </div>
        
        ' + @server_info + '
        
        ' + ISNULL(@wait_stats_section, '') + '
        
        ' + ISNULL(@memory_section, '') + '
        
        ' + ISNULL(@io_section, '') + '
        
        ' + ISNULL(@query_section, '') + '
        
        ' + ISNULL(@blocking_section, '') + '
        
        <div class="footer">
            <p>Generated by DarlingDataCollector on ' + CONVERT(NVARCHAR(30), SYSDATETIME(), 120) + '</p>
            <p>Darling Data, LLC - https://www.erikdarling.com/</p>
        </div>
    </body>
    </html>
    ';
    
    /*
    Write to file using xp_cmdshell if available and a file path was specified
    */
    IF @file_path IS NOT NULL AND EXISTS (SELECT 1 FROM sys.configurations WHERE name = 'xp_cmdshell' AND value_in_use = 1)
    BEGIN
        DECLARE @file_cmd NVARCHAR(MAX);
        
        /*
        Split HTML into chunks to write to file
        */
        DECLARE
            @chunk_size INT = 4000,
            @pos INT = 1,
            @len INT = LEN(@html);
            
        /*
        Create an empty file first
        */
        SET @file_cmd = 'ECHO ' + '>' + ' "' + @file_path + '"';
        EXEC xp_cmdshell @file_cmd;
        
        /*
        Append each chunk to the file
        */
        WHILE @pos <= @len
        BEGIN
            DECLARE @chunk NVARCHAR(4000);
            SET @chunk = SUBSTRING(@html, @pos, @chunk_size);
            SET @chunk = REPLACE(@chunk, '"', '""');
            SET @file_cmd = 'ECHO ' + @chunk + '>>' + ' "' + @file_path + '"';
            EXEC xp_cmdshell @file_cmd;
            SET @pos = @pos + @chunk_size;
        END;
        
        IF @debug = 1
        BEGIN
            PRINT 'HTML report exported to: ' + @file_path;
        END;
    END;
    ELSE
    BEGIN
        /*
        Return HTML for browser display if no file path or xp_cmdshell not available
        */
        SELECT @html AS html_report;
    END;
END;
GO
```

## Scheduled Report Generation

```sql
CREATE OR ALTER PROCEDURE
    system.schedule_report_generation
(
    @report_type VARCHAR(50), /*Options: 'DailyHTML', 'WeeklyHTML', 'DailyCSV'*/
    @file_directory VARCHAR(500),
    @recipients VARCHAR(1000) = NULL, /*Email recipients, comma separated*/
    @debug BIT = 0 /*Print debugging information*/
)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE
        @job_name VARCHAR(128),
        @job_exists BIT,
        @job_id UNIQUEIDENTIFIER,
        @start_date DATE,
        @file_path VARCHAR(500),
        @cmd NVARCHAR(4000),
        @platform NVARCHAR(50),
        @instance_type NVARCHAR(50);
    
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
    Set file path based on report type
    */
    IF @report_type = 'DailyHTML'
    BEGIN
        SET @job_name = 'DarlingDataCollector - Daily HTML Report';
        SET @file_path = @file_directory + '/SQLPerformance_Daily_' + REPLACE(CONVERT(VARCHAR(10), GETDATE(), 120), '-', '') + '.html';
        
        /*
        Create T-SQL command for job
        */
        SET @cmd = '
        EXECUTE reporting.generate_html_report
            @start_date = DATEADD(DAY, -1, CAST(GETDATE() AS DATE)),
            @end_date = CAST(GETDATE() AS DATE),
            @report_types = ''All'',
            @file_path = ''' + @file_path + ''',
            @debug = 0;
        ';
        
        /*
        Add email steps if recipients specified
        */
        IF @recipients IS NOT NULL
        BEGIN
            SET @cmd = @cmd + '
            
            EXECUTE msdb.dbo.sp_send_dbmail
                @profile_name = ''DarlingDataCollector'',
                @recipients = ''' + @recipients + ''',
                @subject = ''SQL Server Daily Performance Report'',
                @body = ''Daily SQL Server performance report is attached.'',
                @file_attachments = ''' + @file_path + ''';
            ';
        END;
    END;
    ELSE IF @report_type = 'WeeklyHTML'
    BEGIN
        SET @job_name = 'DarlingDataCollector - Weekly HTML Report';
        SET @file_path = @file_directory + '/SQLPerformance_Weekly_' + REPLACE(CONVERT(VARCHAR(10), GETDATE(), 120), '-', '') + '.html';
        
        /*
        Create T-SQL command for job
        */
        SET @cmd = '
        EXECUTE reporting.generate_html_report
            @start_date = DATEADD(DAY, -7, CAST(GETDATE() AS DATE)),
            @end_date = CAST(GETDATE() AS DATE),
            @report_types = ''All'',
            @file_path = ''' + @file_path + ''',
            @debug = 0;
        ';
        
        /*
        Add email steps if recipients specified
        */
        IF @recipients IS NOT NULL
        BEGIN
            SET @cmd = @cmd + '
            
            EXECUTE msdb.dbo.sp_send_dbmail
                @profile_name = ''DarlingDataCollector'',
                @recipients = ''' + @recipients + ''',
                @subject = ''SQL Server Weekly Performance Report'',
                @body = ''Weekly SQL Server performance report is attached.'',
                @file_attachments = ''' + @file_path + ''';
            ';
        END;
    END;
    ELSE IF @report_type = 'DailyCSV'
    BEGIN
        SET @job_name = 'DarlingDataCollector - Daily CSV Export';
        
        /*
        Create T-SQL command for job
        */
        SET @start_date = DATEADD(DAY, -1, CAST(GETDATE() AS DATE));
        
        SET @cmd = '
        -- Wait Stats Export
        EXECUTE reporting.export_data_to_csv
            @start_date = ''' + CONVERT(VARCHAR(10), @start_date, 120) + ''',
            @end_date = ''' + CONVERT(VARCHAR(10), @start_date, 120) + ''',
            @report_type = ''WaitStats'',
            @file_path = ''' + @file_directory + '/WaitStats_' + REPLACE(CONVERT(VARCHAR(10), @start_date, 120), '-', '') + '.csv'',
            @debug = 0;
            
        -- Memory Export
        EXECUTE reporting.export_data_to_csv
            @start_date = ''' + CONVERT(VARCHAR(10), @start_date, 120) + ''',
            @end_date = ''' + CONVERT(VARCHAR(10), @start_date, 120) + ''',
            @report_type = ''Memory'',
            @file_path = ''' + @file_directory + '/Memory_' + REPLACE(CONVERT(VARCHAR(10), @start_date, 120), '-', '') + '.csv'',
            @debug = 0;
            
        -- I/O Export
        EXECUTE reporting.export_data_to_csv
            @start_date = ''' + CONVERT(VARCHAR(10), @start_date, 120) + ''',
            @end_date = ''' + CONVERT(VARCHAR(10), @start_date, 120) + ''',
            @report_type = ''IO'',
            @file_path = ''' + @file_directory + '/IO_' + REPLACE(CONVERT(VARCHAR(10), @start_date, 120), '-', '') + '.csv'',
            @debug = 0;
            
        -- Queries Export
        EXECUTE reporting.export_data_to_csv
            @start_date = ''' + CONVERT(VARCHAR(10), @start_date, 120) + ''',
            @end_date = ''' + CONVERT(VARCHAR(10), @start_date, 120) + ''',
            @report_type = ''Queries'',
            @file_path = ''' + @file_directory + '/Queries_' + REPLACE(CONVERT(VARCHAR(10), @start_date, 120), '-', '') + '.csv'',
            @debug = 0;
            
        -- Blocking Export
        EXECUTE reporting.export_data_to_csv
            @start_date = ''' + CONVERT(VARCHAR(10), @start_date, 120) + ''',
            @end_date = ''' + CONVERT(VARCHAR(10), @start_date, 120) + ''',
            @report_type = ''Blocking'',
            @file_path = ''' + @file_directory + '/Blocking_' + REPLACE(CONVERT(VARCHAR(10), @start_date, 120), '-', '') + '.csv'',
            @debug = 0;
        ';
        
        /*
        Add email steps if recipients specified
        */
        IF @recipients IS NOT NULL
        BEGIN
            SET @cmd = @cmd + '
            
            EXECUTE msdb.dbo.sp_send_dbmail
                @profile_name = ''DarlingDataCollector'',
                @recipients = ''' + @recipients + ''',
                @subject = ''SQL Server Daily Performance Data Export'',
                @body = ''Daily SQL Server performance data exports are attached.'',
                @file_attachments = ''' + 
                    @file_directory + '/WaitStats_' + REPLACE(CONVERT(VARCHAR(10), @start_date, 120), '-', '') + '.csv;' +
                    @file_directory + '/Memory_' + REPLACE(CONVERT(VARCHAR(10), @start_date, 120), '-', '') + '.csv;' +
                    @file_directory + '/IO_' + REPLACE(CONVERT(VARCHAR(10), @start_date, 120), '-', '') + '.csv;' +
                    @file_directory + '/Queries_' + REPLACE(CONVERT(VARCHAR(10), @start_date, 120), '-', '') + '.csv;' +
                    @file_directory + '/Blocking_' + REPLACE(CONVERT(VARCHAR(10), @start_date, 120), '-', '') + '.csv' + 
                ''';
            ';
        END;
    END;
    ELSE
    BEGIN
        RAISERROR('Invalid report type. Valid options are: DailyHTML, WeeklyHTML, DailyCSV', 16, 1);
        RETURN;
    END;
    
    /*
    Check if job exists
    */
    SELECT
        @job_exists = 0;
        
    IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @job_name)
    BEGIN
        SELECT
            @job_exists = 1,
            @job_id = job_id
        FROM msdb.dbo.sysjobs
        WHERE name = @job_name;
    END;
    
    /*
    Create or update job
    */
    IF @job_exists = 0
    BEGIN
        EXECUTE msdb.dbo.sp_add_job
            @job_name = @job_name,
            @description = 'DarlingDataCollector Scheduled Report',
            @category_name = 'Report Server',
            @owner_login_name = 'sa',
            @enabled = 1,
            @job_id = @job_id OUTPUT;
        
        EXECUTE msdb.dbo.sp_add_jobserver
            @job_id = @job_id,
            @server_name = @@SERVERNAME;
    END;
    ELSE
    BEGIN
        /*
        Delete existing job steps
        */
        EXECUTE msdb.dbo.sp_delete_jobstep
            @job_id = @job_id,
            @step_id = 0;
    END;
    
    /*
    Add job step
    */
    EXECUTE msdb.dbo.sp_add_jobstep
        @job_id = @job_id,
        @step_name = 'Generate Report',
        @step_id = 1,
        @subsystem = 'TSQL',
        @command = @cmd,
        @database_name = 'DarlingData',
        @on_success_action = 1,
        @on_fail_action = 2;
    
    /*
    Create schedule based on report type
    */
    IF @report_type = 'DailyHTML' OR @report_type = 'DailyCSV'
    BEGIN
        /*
        Delete existing schedules
        */
        EXECUTE msdb.dbo.sp_delete_jobschedule
            @job_id = @job_id,
            @name = 'Daily Schedule';
            
        /*
        Create daily schedule
        */
        EXECUTE msdb.dbo.sp_add_jobschedule
            @job_id = @job_id,
            @name = 'Daily Schedule',
            @enabled = 1,
            @freq_type = 4, -- Daily
            @freq_interval = 1,
            @freq_subday_type = 1, -- Once
            @active_start_time = 70000, -- 7:00 AM
            @active_start_date = 20250101,
            @active_end_date = 99991231;
    END;
    ELSE IF @report_type = 'WeeklyHTML'
    BEGIN
        /*
        Delete existing schedules
        */
        EXECUTE msdb.dbo.sp_delete_jobschedule
            @job_id = @job_id,
            @name = 'Weekly Schedule';
            
        /*
        Create weekly schedule
        */
        EXECUTE msdb.dbo.sp_add_jobschedule
            @job_id = @job_id,
            @name = 'Weekly Schedule',
            @enabled = 1,
            @freq_type = 8, -- Weekly
            @freq_interval = 2, -- Monday
            @freq_subday_type = 1, -- Once
            @active_start_time = 70000, -- 7:00 AM
            @active_start_date = 20250101,
            @active_end_date = 99991231;
    END;
    
    /*
    Print debug information
    */
    IF @debug = 1
    BEGIN
        PRINT 'Created job: ' + @job_name;
        PRINT 'Job ID: ' + CAST(@job_id AS VARCHAR(50));
        PRINT 'Command: ' + LEFT(@cmd, 1000) + '...';
    END;
END;
GO
```

## Integration with External Tools

The reporting system is designed to integrate with external tools through the following methods:

1. **CSV exports** - For integration with Excel, Tableau, Power BI, and other reporting tools
2. **HTML reports** - For email distribution and web-based viewing
3. **Database views** - For direct connection from reporting tools

## Dashboard Examples

### Power BI Integration

To connect DarlingDataCollector to Power BI:

1. Use the reporting views directly via a direct query connection
2. Create a connection to the SQL Server instance
3. Select the reporting views from the DarlingData database
4. Create visualizations based on the wait statistics, memory usage, I/O performance, and other metrics

### SQL Server Reporting Services (SSRS)

The reporting views can be used as data sources for SSRS reports, providing a web-based dashboard for monitoring SQL Server performance metrics.

## Next Steps

1. Create additional reporting views for specific performance metrics:
   - Index fragmentation analysis
   - Query plan stability monitoring
   - TempDB usage tracking
   - Partitioning effectiveness

2. Build custom performance dashboards:
   - Executive summary dashboard
   - DBA operational dashboard
   - Developer query performance dashboard

3. Integrate with alerting systems:
   - Create alert procedures for critical metrics
   - Set up monitoring thresholds
   - Implement proactive notifications