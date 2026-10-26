<img src="https://erikdarling.com/wp-content/uploads/2025/08/darling-data-logo_RGB.jpg" width="300px" />

# sp_IndexCleanup

## Overview

This stored procedure helps identify unused and duplicate indexes in your SQL Server databases that could be candidates for removal. It analyzes index usage statistics and can generate scripts for removing unnecessary indexes. It also finds uncompressed indexes that are candidates for page compression.

**IMPORTANT: This is currently a BETA VERSION.** It needs extensive testing in real environments with real indexes to address several issues:
* Data collection accuracy
* Deduping logic
* Result correctness
* Edge cases

## Warning

Misuse of this procedure can potentially harm your database. If you run this, only use the output to validate result correctness. **Do not run any of the output scripts without thorough review and testing**, as doing so may be harmful to your database performance.

The procedure requires SQL Server 2012 (11.0) or later due to the use of FORMAT and CONCAT functions.

## Parameters

| Parameter Name | Data Type | Default Value | Description |
|----------------|-----------|---------------|-------------|
| @database_name | sysname | NULL | The name of the database you wish to analyze. Defaults to the current database when that is a user database |
| @schema_name | sysname | NULL | The schema name to filter indexes by - limits analysis to tables in the specified schema when used without @table_name |
| @table_name | sysname | NULL | The table or view name to filter indexes by. The schema defaults to dbo if @schema_name is NULL |
| @min_reads | bigint | 0 | Minimum reads for an index to be deduped. Applied per table and per index. An index clears by meeting this or @min_writes. Does not affect unused-index detection or compression |
| @min_writes | bigint | 0 | Minimum writes for an index to be deduped. Applied per table and per index. An index clears by meeting this or @min_reads. Does not affect unused-index detection or compression |
| @min_size_gb | decimal(10,2) | 0 | Minimum size in GB for an index to be analyzed |
| @min_rows | bigint | 0 | Minimum number of rows for a table to be analyzed |
| @dedupe_only | bit | 0 | When set to 1, only performs index deduplication but does not mark unused indexes for removal |
| @get_all_databases | bit | 0 | When set to 1, analyzes all eligible databases on the server |
| @include_databases | nvarchar(max) | NULL | Comma-separated list of databases to include (used with @get_all_databases = 1) |
| @exclude_databases | nvarchar(max) | NULL | Comma-separated list of databases to exclude (used with @get_all_databases = 1) |
| @sort_order | varchar(20) | default | Controls final result ordering: default groups by script type within each database, object groups all rows for the same index together (Key Subset disables sort under their replacement index) |
| @help | bit | 0 | Displays help information |
| @debug | bit | 0 | Prints debug information during execution |
| @version | varchar(20) | NULL | OUTPUT parameter that returns the version number of the procedure |
| @version_date | datetime | NULL | OUTPUT parameter that returns the date this version was released |

## Usage Examples

```sql
-- Basic usage to analyze all indexes in a database
EXECUTE dbo.sp_IndexCleanup
    @database_name = 'YourDatabase';

-- Analyze a specific table with debug information
EXECUTE dbo.sp_IndexCleanup
    @database_name = 'YourDatabase',
    @table_name = 'YourTable',
    @debug = 1;

-- Only perform deduplication without marking unused indexes for removal
EXECUTE dbo.sp_IndexCleanup
    @database_name = 'YourDatabase',
    @dedupe_only = 1;

-- Analyze tables in a specific schema only
EXECUTE dbo.sp_IndexCleanup
    @database_name = 'YourDatabase',
    @schema_name = 'YourSchema';

-- Filter indexes by minimum usage thresholds
EXECUTE dbo.sp_IndexCleanup
    @database_name = 'YourDatabase',
    @min_reads = 100,
    @min_writes = 10;

-- Analyze all user databases on the server
EXECUTE dbo.sp_IndexCleanup
    @get_all_databases = 1,
    @debug = 1;

-- Analyze only specific databases
EXECUTE dbo.sp_IndexCleanup
    @get_all_databases = 1,
    @include_databases = 'Database1,Database2,Database3';

-- Analyze all databases except specific ones
EXECUTE dbo.sp_IndexCleanup
    @get_all_databases = 1,
    @exclude_databases = 'ReportServer,TempDB2';

-- Show help information
EXECUTE dbo.sp_IndexCleanup
    @help = 1;
```

## Notes

- Index usage statistics start over when SQL Server restarts. They also start over when a database is restored or created.
- The `DATABASE` row in the summary shows `usage_since` and `usage_since_reason`. `usage_since` is the latest of the server start, the last restore of the database in `msdb.dbo.restorehistory`, and the `create_date` of the database. `usage_since_reason` says which of those it was.
- If the usage window of a database is 7 days or less, Rule 1 (unused indexes) is skipped for that database only. Its `DATABASE` row says so.
- If the server started 7 days ago or less, `@dedupe_only` is turned on automatically for every database. This prevents removing unused indexes with insufficient usage data.
- Unused Index rows carry a warning while server uptime or the database usage window is under 14 days. Index usage stats are not representative over a short window.
- `daily_write_ops_saved`, `daily_lock_waits_saved` and `daily_latch_waits_saved` on TABLE rows divide by the usage window of the database, not by server uptime.
- On an availability group primary with readable secondaries, the `DATABASE` row notes that reads on the secondaries are not counted.
- Online index operations need Enterprise, Azure SQL DB or Managed Instance. Compression needs those, or Standard edition on SQL Server 2016 or later.
- It is recommended to have a recent backup before making any index changes
- The multi-database processing feature (@get_all_databases) analyzes each database sequentially for better performance and resource management
- System databases (master, model, msdb, tempdb, rdsadmin) are always excluded from processing
- When using @get_all_databases, results for all databases are combined in a single result set
- The index_count column on TABLE, DATABASE and SUMMARY rows counts only analyzed indexes. Clustered indexes, heaps, xml indexes and similar are not counted. The SUMMARY value is the sum of the DATABASE values.

Copyright 2026 Darling Data, LLC  
Released under MIT license