<img src="https://erikdarling.com/wp-content/uploads/2025/08/darling-data-logo_RGB.jpg" width="300px" />

# sp_IndexCleanup

## Overview

This stored procedure helps identify unused and duplicate indexes in your SQL Server databases that could be candidates for removal. It analyzes index usage statistics and can generate scripts for removing unnecessary indexes.

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
| @database_name | sysname | NULL | The name of the database you wish to analyze |
| @schema_name | sysname | NULL | The schema name to filter indexes by - limits analysis to tables in the specified schema |
| @table_name | sysname | NULL | The table name to filter indexes by |
| @min_reads | bigint | 0 | Minimum number of reads for an index to be considered used |
| @min_writes | bigint | 0 | Minimum number of writes for an index to be considered used |
| @min_size_gb | decimal(10,2) | 0 | Minimum size in GB for an index to be analyzed |
| @min_rows | bigint | 0 | Minimum number of rows for a table to be analyzed |
| @dedupe_only | bit | 0 | When set to 1, only performs index deduplication but does not mark unused indexes for removal |
| @get_all_databases | bit | 0 | When set to 1, analyzes all eligible databases on the server |
| @include_databases | nvarchar(max) | NULL | Comma-separated list of databases to include (used with @get_all_databases = 1) |
| @exclude_databases | nvarchar(max) | NULL | Comma-separated list of databases to exclude (used with @get_all_databases = 1) |
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

- The procedure issues a warning when server uptime is less than 14 days, as index usage stats may not be representative
- When server uptime is less than 7 days, @dedupe_only mode is automatically enabled to prevent removing unused indexes with insufficient usage data
- Certain features like online index operations and compression are only available in specific SQL Server editions (Enterprise, Azure SQL DB, Managed Instance)
- It is recommended to have a recent backup before making any index changes
- The multi-database processing feature (@get_all_databases) analyzes each database sequentially for better performance and resource management
- System databases (master, model, msdb, tempdb, rdsadmin) are always excluded from processing
- When using @get_all_databases, results for all databases are combined in a single result set
- The index_count column for the SUMMARY row in the output table will likely indicate a lower number than is shown at the DATABASE level.  The SUMMARY level only includes indexes that have been analyzed; excluding things like clustered indexes, heaps, xml indexes, etc.  The DATABASE level index_count value is the total number of indexes in the database.

Copyright 2024 Darling Data, LLC  
Released under MIT license