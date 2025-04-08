# sp_DarlingDataCollector

A comprehensive SQL Server performance data collection and analysis solution.

## Overview

sp_DarlingDataCollector is a modular SQL Server performance monitoring tool that collects data from Dynamic Management Views (DMVs) and stores it in a central repository for historical analysis. This enables DBAs to identify performance trends, bottlenecks, and recommend solutions.

## Supported Environments

- SQL Server 2016 (13.x) and later
- On-premises SQL Server
- Azure SQL Managed Instance
- AWS RDS SQL Server

**Not supported:** Azure SQL Database

## Features

- Lightweight collection with minimal overhead
- Comprehensive metrics collection (wait stats, memory, CPU, I/O, queries, etc.)
- Automatic data retention management
- Historical performance trend analysis
- Multi-database support for Query Store and index usage collection
- Blocking and deadlock detection
- Active session monitoring similar to sp_whoisactive
- Platform-aware collection that detects and adapts to different SQL Server environments

## Architecture

The solution consists of several integrated components:

1. **Data Collection**: Modular procedures that gather metrics from DMVs
2. **Repository**: Central database that stores collected data
3. **Analysis Engine**: Interprets collected data to identify patterns and issues
4. **System Management**: Controls data retention and database configuration

## Installation

1. Run the `collector_installation.sql` script in your target database
2. Configure database collection settings using `system.manage_databases`
3. Optionally adjust the retention period using `system.data_retention`
4. Create SQL Agent jobs with `system.create_collection_jobs`

## Configuration

### Managing Database Collection

The `system.manage_databases` procedure allows you to control which databases are included in specific collection types. This is particularly useful for Query Store and index usage collection, which can be targeted to specific databases.

```sql
-- Add a database for index usage collection
EXECUTE system.manage_databases 
    @action = 'ADD', 
    @database_name = 'YourDatabase', 
    @collection_type = 'INDEX',
    @debug = 1;

-- Add a database for query store collection
EXECUTE system.manage_databases 
    @action = 'ADD', 
    @database_name = 'YourDatabase', 
    @collection_type = 'QUERY_STORE',
    @debug = 1;

-- Add a database for all collection types
EXECUTE system.manage_databases 
    @action = 'ADD', 
    @database_name = 'YourDatabase', 
    @collection_type = 'ALL',
    @debug = 1;

-- List configured databases
EXECUTE system.manage_databases 
    @action = 'LIST',
    @debug = 1;
```

### Data Retention

The `system.data_retention` procedure manages how long collected data is kept in the repository. You can set different retention periods for specific tables or exclude certain tables completely from the cleanup process.

```sql
-- Set custom retention period (90 days)
EXECUTE system.data_retention 
    @retention_days = 90,
    @debug = 1;

-- Exclude specific tables from data retention
EXECUTE system.data_retention 
    @retention_days = 30,
    @exclude_tables = 'query_store_queries,query_store_plans',
    @debug = 1;
```

## Available Collectors

- `collection.collect_wait_stats` - Collects wait statistics with optional sampling
- `collection.collect_memory_clerks` - Captures memory usage by clerk type
- `collection.collect_buffer_pool` - Monitors database pages in buffer pool
- `collection.collect_io_stats` - Captures file I/O statistics and throughput
- `collection.collect_index_usage_stats` - Tracks index usage statistics from configured databases
- `collection.collect_query_stats` - Collects query performance metrics from plan cache
- `collection.collect_connections` - Captures active session details
- `collection.collect_blocking` - Monitors blocking chains
- `collection.collect_deadlocks` - Collects deadlock information from extended events
- `collection.collect_query_store` - Gathers Query Store data from configured databases

Each collection procedure has detailed help information available:

```sql
-- View help for a collection procedure
EXECUTE collection.collect_query_store @help = 1;
```

## Query Store Collection

The `collection.collect_query_store` procedure collects detailed information from the Query Store in SQL Server 2016 and later. This includes:

- Query text and details
- Execution plans
- Runtime statistics (CPU, I/O, memory usage, etc.)
- Wait statistics by query

You can configure collection thresholds to focus on resource-intensive queries:

```sql
-- Collect queries with at least 5 seconds of CPU time or 10,000 logical reads
EXECUTE collection.collect_query_store 
    @min_cpu_time_ms = 5000, 
    @min_logical_io_reads = 10000,
    @include_query_plans = 1,
    @debug = 1;
```

The collected data provides deep insights into query performance across multiple databases and enables historical trend analysis that complements the point-in-time data from the plan cache.

## Environment Detection

The collector automatically detects the SQL Server environment (on-premises, Azure MI, or AWS RDS) and adjusts its collection methods accordingly. This ensures compatibility across different platforms while maintaining consistent data collection.

```sql
-- View current environment information
SELECT * FROM system.server_info;
```

## Components

- **Repository Database**: Stores collected metrics in the collection schema
- **Collection Procedures**: Gather metrics from various DMVs
- **System Procedures**: Manage configuration and data retention
- **SQL Agent Jobs**: Schedule and manage collection tasks

## SQL Agent Jobs

The collector creates and manages the following SQL Agent jobs:

1. **DarlingDataCollector - Master Collection**: Parent job for all collection activities
2. **DarlingDataCollector - Regular Collections**: Collects core metrics (wait stats, memory, buffer pool)
3. **DarlingDataCollector - Hourly Collections**: Collects hourly metrics (query stats, index usage)
4. **DarlingDataCollector - Daily Collections**: Performs daily collection and maintenance

You can customize the job schedules using:

```sql
EXECUTE system.create_collection_jobs 
    @minute_frequency = 15,   -- For regular collections (default: 15 minutes)
    @hourly_frequency = 60,   -- For hourly collections (default: 60 minutes)
    @daily_frequency = 1440,  -- For daily collections (default: 1440 minutes/24 hours)
    @debug = 1;
```

## Requirements

- SQL Server 2016 or newer
- SQL Agent for scheduling collections (not available in Azure SQL Database)
- 100-500 MB of storage space for the repository database

## Credits

Developed by Erik Darling (Darling Data, LLC).

## License

MIT License