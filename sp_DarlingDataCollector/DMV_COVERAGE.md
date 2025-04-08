# DMV Coverage Plan

## DMV Tracking System

To ensure comprehensive coverage of all important SQL Server DMVs, we maintain a tracking system in the `system.dmv_coverage` table:

```sql
CREATE TABLE
    system.dmv_coverage
(
    dmv_name nvarchar(128) NOT NULL,
    category varchar(50) NOT NULL,
    collection_procedure sysname NULL,
    is_implemented bit NOT NULL DEFAULT (0),
    on_prem_supported bit NOT NULL DEFAULT (1),
    azure_mi_supported bit NOT NULL DEFAULT (0),
    aws_rds_supported bit NOT NULL DEFAULT (1),
    minimum_version varchar(20) NULL,
    notes nvarchar(1000) NULL,
    create_date datetime2(7) NOT NULL DEFAULT (SYSDATETIME()),
    last_updated datetime2(7) NOT NULL DEFAULT (SYSDATETIME()),
    PRIMARY KEY (dmv_name)
);
```

## DMV Categories

### Server Memory

| DMV | Description | On-Prem | Azure MI | AWS RDS | Min Version |
|-----|-------------|:-------:|:--------:|:-------:|:-----------:|
| sys.dm_os_memory_clerks | Memory usage by clerk type | ✓ | ✓ | ✓ | 2008 |
| sys.dm_os_memory_brokers | Memory broker states | ✓ | ✓ | ✓ | 2008 |
| sys.dm_os_memory_broker_clerks | Broker clerk details | ✓ | ✓ | ✓ | 2016 |
| sys.dm_os_memory_node_access_stats | NUMA node memory access | ✓ | ✓ | ✓ | 2012 |
| sys.dm_os_memory_pools | Memory pool allocation | ✓ | ✓ | ✓ | 2012 |
| sys.dm_os_process_memory | Process memory summary | ✓ | ✓ | ✓ | 2012 |
| sys.dm_os_buffer_descriptors | Buffer pool content | ✓ | ✓ | ✓ | 2008 |
| sys.dm_exec_query_resource_semaphores | Memory grant semaphores | ✓ | ✓ | ✓ | 2008 |
| sys.dm_exec_query_memory_grants | Active memory grants | ✓ | ✓ | ✓ | 2008 |

### CPU & Schedulers

| DMV | Description | On-Prem | Azure MI | AWS RDS | Min Version |
|-----|-------------|:-------:|:--------:|:-------:|:-----------:|
| sys.dm_os_schedulers | SQL scheduler state | ✓ | ✓ | ✓ | 2008 |
| sys.dm_os_nodes | NUMA node information | ✓ | ✓ | ✓ | 2008 |
| sys.dm_os_sys_info | System information | ✓ | ✓ | ✓ | 2008 |
| sys.dm_os_performance_counters | Performance counters | ✓ | ✓ | ✓ | 2008 |

### Wait Statistics

| DMV | Description | On-Prem | Azure MI | AWS RDS | Min Version |
|-----|-------------|:-------:|:--------:|:-------:|:-----------:|
| sys.dm_os_wait_stats | Cumulative wait statistics | ✓ | ✓ | ✓ | 2008 |
| sys.dm_os_waiting_tasks | Currently waiting tasks | ✓ | ✓ | ✓ | 2008 |
| sys.dm_exec_session_wait_stats | Session-specific wait stats | ✓ | ✓ | ✓ | 2016 |
| sys.dm_os_latch_stats | Latch wait statistics | ✓ | ✓ | ✓ | 2008 |

### I/O Performance

| DMV | Description | On-Prem | Azure MI | AWS RDS | Min Version |
|-----|-------------|:-------:|:--------:|:-------:|:-----------:|
| sys.dm_io_virtual_file_stats | File I/O statistics | ✓ | ✓ | ✓ | 2008 |
| sys.dm_io_pending_io_requests | Current pending I/O | ✓ | ✓ | ✓ | 2008 |
| sys.database_files | Database file information | ✓ | ✓ | ✓ | 2008 |
| sys.dm_db_file_space_usage | File space usage | ✓ | ✓ | ✓ | 2008 |
| sys.dm_db_log_info | Database log information | ✓ | ✓ | ✓ | 2016 |
| sys.dm_db_log_space_usage | Log space usage | ✓ | ✓ | ✓ | 2016 |
| sys.dm_db_page_info | Page information | ✓ | ✗ | ✓ | 2019 |

### Query Execution

| DMV | Description | On-Prem | Azure MI | AWS RDS | Min Version |
|-----|-------------|:-------:|:--------:|:-------:|:-----------:|
| sys.dm_exec_requests | Currently executing requests | ✓ | ✓ | ✓ | 2008 |
| sys.dm_exec_sessions | Session information | ✓ | ✓ | ✓ | 2008 |
| sys.dm_exec_query_stats | Query performance statistics | ✓ | ✓ | ✓ | 2008 |
| sys.dm_exec_procedure_stats | Stored procedure statistics | ✓ | ✓ | ✓ | 2008 |
| sys.dm_exec_function_stats | Function statistics | ✓ | ✓ | ✓ | 2016 |
| sys.dm_exec_trigger_stats | Trigger execution statistics | ✓ | ✓ | ✓ | 2016 |
| sys.dm_exec_query_plan | Execution plan for query | ✓ | ✓ | ✓ | 2008 |
| sys.dm_exec_query_statistics_xml | Live query execution statistics | ✓ | ✓ | ✓ | 2016SP1 |
| sys.dm_exec_sql_text | SQL text by handle | ✓ | ✓ | ✓ | 2008 |
| sys.dm_exec_text_query_plan | Text format execution plan | ✓ | ✓ | ✓ | 2008 |
| sys.dm_exec_cached_plans | Cached query plans | ✓ | ✓ | ✓ | 2008 |
| sys.dm_exec_plan_attributes | Plan attributes | ✓ | ✓ | ✓ | 2008 |

### Indexes & Statistics

| DMV | Description | On-Prem | Azure MI | AWS RDS | Min Version |
|-----|-------------|:-------:|:--------:|:-------:|:-----------:|
| sys.dm_db_index_usage_stats | Index usage statistics | ✓ | ✓ | ✓ | 2008 |
| sys.dm_db_index_physical_stats | Index physical structure | ✓ | ✓ | ✓ | 2008 |
| sys.dm_db_index_operational_stats | Index operational stats | ✓ | ✓ | ✓ | 2008 |
| sys.dm_db_missing_index_details | Missing index details | ✓ | ✓ | ✓ | 2008 |
| sys.dm_db_missing_index_groups | Missing index grouping | ✓ | ✓ | ✓ | 2008 |
| sys.dm_db_missing_index_group_stats | Missing index statistics | ✓ | ✓ | ✓ | 2008 |
| sys.dm_db_stats_properties | Statistics information | ✓ | ✓ | ✓ | 2016 |
| sys.dm_db_incremental_stats_properties | Incremental stats info | ✓ | ✓ | ✓ | 2016 |

### Transactions

| DMV | Description | On-Prem | Azure MI | AWS RDS | Min Version |
|-----|-------------|:-------:|:--------:|:-------:|:-----------:|
| sys.dm_tran_active_transactions | Active transactions | ✓ | ✓ | ✓ | 2008 |
| sys.dm_tran_database_transactions | Database transactions | ✓ | ✓ | ✓ | 2008 |
| sys.dm_tran_locks | Active lock information | ✓ | ✓ | ✓ | 2008 |
| sys.dm_tran_session_transactions | Session transaction mapping | ✓ | ✓ | ✓ | 2008 |
| sys.dm_tran_active_snapshot_database_transactions | Active snapshot transactions | ✓ | ✓ | ✓ | 2008 |
| sys.dm_tran_current_transaction | Current transaction info | ✓ | ✓ | ✓ | 2008 |
| sys.dm_tran_transactions_snapshot | Snapshot transactions | ✓ | ✓ | ✓ | 2008 |

### Extended Events

| DMV | Description | On-Prem | Azure MI | AWS RDS | Min Version |
|-----|-------------|:-------:|:--------:|:-------:|:-----------:|
| sys.dm_xe_sessions | XE session information | ✓ | ✓ | ✓ | 2008 |
| sys.dm_xe_session_targets | XE session targets | ✓ | ✓ | ✓ | 2008 |
| sys.dm_xe_session_events | XE session events | ✓ | ✓ | ✓ | 2008 |

## Environment-Specific Limitations

### Azure SQL Managed Instance (MI) Limitations

- **sys.dm_db_page_info**: Not available in Azure SQL MI
- Some DMVs may provide different information or have slightly different columns

### AWS RDS Limitations

- All standard DMVs generally work the same as on-premises
- Instance-level configuration differences may exist

## Query Store Coverage

Beginning with SQL Server 2016, Query Store provides a rich set of data for query performance analysis. 
DarlingDataCollector implements the following Query Store components:

| DMV | Description | On-Prem | Azure MI | AWS RDS | Min Version |
|-----|-------------|:-------:|:--------:|:-------:|:-----------:|
| sys.query_store_query | Query information | ✓ | ✓ | ✓ | 2016 |
| sys.query_store_query_text | Query text | ✓ | ✓ | ✓ | 2016 |
| sys.query_store_plan | Execution plans | ✓ | ✓ | ✓ | 2016 |
| sys.query_store_runtime_stats | Performance metrics | ✓ | ✓ | ✓ | 2016 |
| sys.query_store_wait_stats | Wait statistics by query | ✓ | ✓ | ✓ | 2017 |
| sys.query_store_runtime_stats_interval | Time intervals | ✓ | ✓ | ✓ | 2016 |

The Query Store collector (`collection.collect_query_store`) provides:

- Configurable thresholds for CPU, I/O, and other resource metrics
- Time-based filtering
- Database-level targeting via `system.manage_databases`
- Historical trend analysis
- Correlation with traditional DMV data

## Implementation Strategy

The implementation strategy prioritizes:

1. Core DMVs that work across all environments
2. High-value monitoring DMVs with significant diagnostic value
3. Environment-specific code paths for different platforms
4. Historical trend analysis through delta calculations

Each DMV collection procedure includes appropriate environment detection to ensure compatibility with the target SQL Server platform.

## Environment Detection

To ensure proper DMV coverage based on the SQL Server environment, we use the following standardized detection logic:

```sql
-- Engine edition detection
DECLARE @engine_edition INTEGER = CONVERT(INTEGER, SERVERPROPERTY('EngineEdition'));

-- Azure SQL MI detection (EngineEdition = 8)
DECLARE @is_azure_mi BIT = CASE WHEN @engine_edition = 8 THEN 1 ELSE 0 END;

-- AWS RDS detection using the presence of rdsadmin database
DECLARE @is_aws_rds BIT = CASE
    WHEN DB_ID('rdsadmin') IS NOT NULL THEN 1
    ELSE 0
END;
```

## Collection Process

Based on the environment detection, our collection procedures:

1. Only collect from DMVs supported in the current environment
2. Use environment-specific coding paths where needed
3. Adjust collection parameters based on environment capabilities
4. Skip unsupported DMVs or features
5. Calculate deltas to track performance changes over time

This approach ensures that DarlingDataCollector works consistently across on-premises SQL Server, Azure SQL Managed Instance, and AWS RDS environments.

## Platform-Specific Considerations

### AWS RDS

The collector adapts to AWS RDS limitations by:
- Using appropriate RDS-specific DMVs
- Using `rdsadmin` database presence as a reliable detection method
- Working within AWS RDS access limitations for system tables

### Azure SQL Managed Instance

The collector adapts to Azure MI by:
- Filtering DMVs and metrics that are not relevant in Azure MI
- Using appropriate MI-specific query patterns
- Detecting edition via engine edition=8