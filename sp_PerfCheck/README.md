# sp_PerfCheck: SQL Server Performance Health Check

`sp_PerfCheck` is a comprehensive SQL Server performance diagnostic tool that quickly identifies configuration issues, capacity problems, and performance bottlenecks.

This procedure collects key health metrics and configuration settings at both the server and database level, providing actionable insights without overwhelming you with irrelevant information.

## Features

- Fast, lightweight server-level health check
- Database-specific checks for all accessible user databases
- Identifies misconfigurations impacting performance
- Detects resource pressure signals (CPU, memory, I/O)
- Finds suboptimal database settings
- Works with SQL Server 2016+ and Azure SQL options

## Requirements

- SQL Server 2016 SP2 or newer
- VIEW SERVER STATE permissions for full functionality
- Database access permissions for database-level checks

## Parameters

| Parameter | Data Type | Default | Description |
|-----------|-----------|---------|-------------|
| @database_name | sysname | NULL | Specific database to check; NULL runs against all accessible user databases |
| @debug | bit | 0 | Print diagnostic messages and intermediate query results |
| @version | varchar(30) | NULL OUTPUT | Returns version number |
| @version_date | datetime | NULL OUTPUT | Returns version date |

## Usage Examples

### Basic check on all databases
```sql
EXEC dbo.sp_PerfCheck;
```

### Check a specific database only
```sql
EXEC dbo.sp_PerfCheck
    @database_name = 'YourDatabaseName';
```

### Run with debug information
```sql
EXEC dbo.sp_PerfCheck
    @debug = 1;
```

## Performance Checks

### Server Configuration (4000-series)

#### Memory Configuration
- **Lock Pages in Memory Status** (check_id 4105)
  - Identifies if SQL Server is using locked pages in memory
  - Recommends enabling for production environments with >32GB RAM

- **Memory Pressure Indicators** (check_id 4001-4002)
  - Detects high buffer pool churn, memory grants issues, external memory pressure
  - Provides specific thresholds based on server class

- **Instant File Initialization** (check_id 4106)
  - Verifies if IFI is enabled for data file operations
  - Critical for fast file growths and database restores

#### CPU Configuration
- **CPU Scheduling Pressure** (check_id 6101-6102)
  - High signal waits ratio (>25%)
  - Excessive SOS_SCHEDULER_YIELD waits

#### Resource Governor
- **Resource Governor State** (check_id 4107)
  - Detects if Resource Governor is enabled
  - Provides scripts to examine resource pool and workload group settings

#### Server-level Settings
- **SQL Server Edition and Configuration Options** (server_info)
  - Documents product version, edition, and key server properties
  - Shows non-default global configuration settings
  - Lists globally enabled trace flags

#### TempDB Configuration
- **TempDB Files and Settings** (check_id 5000-5003)
  - Verifies proper number of TempDB data files based on CPU count
  - Checks for equal file sizes and settings
  - Identifies suboptimal growth settings

### Storage Performance (6000-series)

- **I/O Stall Statistics** (check_id 6201)
  - Tracks read/write stalls per database
  - Identifies databases experiencing I/O bottlenecks
  - Calculates average stall times for reads and writes

- **Auto-growth Events** (server_info)
  - Captures slow auto-growth events for data and log files
  - Reports frequency and average duration

### Database Configuration (7000-series)

- **Basic Database Settings** (check_id 7001-7010)
  - Auto-shrink (7001): Performance impact of cyclic shrink/grow operations
  - Auto-close (7002): Connection delay impact
  - Restricted access mode (7003): Non-multi-user modes
  - Statistics settings (7004): Auto create/update statistics disabled
  - ANSI settings (7005): Non-standard ANSI settings
  - Query Store status (7006): Not enabled
  - Recovery time target (7007): Non-default settings
  - Transaction durability (7008): Delayed durability modes
  - Accelerated Database Recovery (7009): Missing ADR with snapshot isolation
  - Ledger feature (7010): Performance overhead of blockchain features

- **Query Store Health** (check_id 7011-7012)
  - State mismatch (7011): Desired state doesn't match actual state
  - Suboptimal configuration (7012): Identifies settings that might limit effectiveness

- **Database Scoped Configurations** (check_id 7020)
  - Identifies non-default DSC settings
  - Explains the performance impact of each setting

- **Database File Settings** (check_id 7101-7104)
  - Percentage growth for data files (7101): Risk of increasingly larger growth events
  - Percentage growth for log files (7102): Higher priority due to zeroing impact
  - Non-optimal log growth increments (7103): Missing 64MB setting for instant log initialization
  - Extremely large growth increments (7104): Growth settings >10GB that may cause stalls

## Results Interpretation

Results are returned in two sections:

1. **Server Information**: General server metrics and configuration details
   - Displays as info_type/value pairs
   - Includes version, resource usage, configuration settings

2. **Performance Check Results**: Specific findings from all checks
   - Sorted by priority (lower numbers = higher priority)
   - Grouped by category for easier analysis
   - Includes details with explanations and recommendations

## Credits

sp_PerfCheck is developed and maintained by Erik Darling of Darling Data, LLC.

For more information, visit: [erikdarling.com](https://erikdarling.com)
