# sp_PerfCheck: SQL Server Performance Health Check

`sp_PerfCheck` is a comprehensive SQL Server performance diagnostic tool that quickly identifies configuration issues, capacity problems, and performance bottlenecks.

This procedure collects key health metrics and configuration settings at both the server and database level, providing actionable insights without overwhelming you with irrelevant information.

## Features

- Fast, lightweight server-level health check
- Database-specific checks for all accessible user databases
- Identifies misconfigurations impacting performance
- Detects resource pressure signals (CPU, memory, I/O)
- Analyzes wait statistics to identify bottlenecks
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

### Wait Statistics Analysis (6000-series)

- **High Impact Wait Types** (check_id 6001)
  - Analyzes sys.dm_os_wait_stats to identify performance bottlenecks
  - Calculates wait time as a percentage of SQL Server uptime
  - Categorizes waits by resource type (CPU, I/O, Memory, etc.)
  - Identifies abnormal wait patterns indicating specific resource pressure
  - Filters out benign or expected wait types

### Server Configuration (4000-series)

#### Memory Configuration
- **Lock Pages in Memory Status** (check_id 4105)
  - Identifies if SQL Server is using locked pages in memory
  - Recommends enabling for production environments with >32GB RAM

- **Memory Pressure Indicators** (check_id 4001-4002)
  - Detects high buffer pool churn, memory grants issues, external memory pressure
  - Provides specific thresholds based on server class

- **Memory Pressure Analysis** (check_id 4101)
  - Detects forced memory grants that can impact query performance
  - Analyzes memory clerk distribution and pressure points

- **Security Token Cache Size** (check_id 4104)
  - Analyzes TokenAndPermUserStore cache size
  - Identifies excessive security token cache which can consume significant memory
  - Provides recommendations for high-connection environments

- **Instant File Initialization** (check_id 4106)
  - Verifies if IFI is enabled for data file operations
  - Critical for fast file growths and database restores

- **Min and Max Server Memory** (check_id 1001-1002)
  - Check for min server memory too close to max (≥90%)
  - Identifies max server memory set too close to physical memory (≥95%)
  - Prevents SQL Server from dynamically adjusting memory usage

- **High Stolen Memory** (check_id 6002)
  - Identifies high percentage of memory stolen from buffer pool
  - Calculates impact on data caching capability
  - Suggests investigating memory usage by CLR, extended stored procedures, or linked servers

#### CPU Configuration
- **CPU Scheduling Pressure** (check_id 6101-6102)
  - High signal waits ratio (>25%) indicating CPU scheduler contention
  - Excessive SOS_SCHEDULER_YIELD waits showing CPU pressure

- **Offline CPU Schedulers** (check_id 4001)
  - Detects when CPU schedulers are offline
  - Identifies potential affinity mask misconfigurations
  - Checks for licensing or VM configuration issues limiting processor availability

- **MAXDOP Settings** (check_id 1003)
  - Identifies default MAXDOP setting (0) on multi-processor systems
  - Warns about potential excessive parallelism issues
  - Provides recommendations based on logical processor count

- **Cost Threshold for Parallelism** (check_id 1004)
  - Detects low cost threshold settings that may cause excessive parallelism
  - Analyzes impact on small query performance
  - Recommends appropriate values based on workload characteristics

#### Server Stability
- **Memory Dumps Analysis** (check_id 4102)
  - Detects SQL Server memory dumps indicating stability issues
  - Calculates frequency of dumps relative to uptime
  - Provides guidance for dump analysis and resolution

- **Deadlock Detection** (check_id 4103)
  - Identifies deadlock frequency and patterns
  - Tracks deadlocks per day since server startup
  - Indicates potential application concurrency issues

#### Advanced Configuration Settings
- **Priority Boost** (check_id 1005)
  - Detects when priority boost is enabled
  - Warns about potential issues with Windows scheduling priorities
  - Provides guidance on recommended settings

- **Lightweight Pooling** (check_id 1006)
  - Identifies when lightweight pooling (fiber mode) is enabled
  - Warns about potential compatibility issues with OLEDB providers
  - Explains performance implications and alternatives

- **Affinity Mask** (check_id 1008)
  - Detects when the affinity mask has been manually configured
  - Warns about potential limitations on SQL Server CPU usage
  - Provides guidance for CPU binding scenarios

- **Affinity I/O Mask** (check_id 1009)
  - Identifies when the affinity I/O mask has been manually configured
  - Warns about binding I/O completion to specific CPUs
  - Explains when this specialized configuration might be appropriate

- **Affinity64 Mask** (check_id 1010)
  - Detects when affinity64 mask has been manually configured
  - Identifies potential CPU usage limitations on high-CPU systems
  - Provides guidance for proper configuration

- **Affinity64 I/O Mask** (check_id 1011)
  - Identifies when affinity64 I/O mask has been manually configured
  - Warns about binding I/O completion on high-CPU systems
  - Explains performance implications and alternatives

#### Resource Governor
- **Resource Governor State** (check_id 4107)
  - Detects if Resource Governor is enabled
  - Provides scripts to examine resource pool and workload group settings
  - Analyzes impact on workload performance

#### Server-level Settings
- **SQL Server Edition and Configuration Options** (server_info)
  - Documents product version, edition, and key server properties
  - Shows non-default global configuration settings
  - Lists globally enabled trace flags
  - Identifies offline CPU schedulers or other configuration issues

#### TempDB Configuration
- **TempDB Files and Settings** (check_id 5000-5003)
  - Verifies proper number of TempDB data files based on CPU count
  - Checks for equal file sizes and settings
  - Identifies suboptimal growth settings
  - Analyzes TempDB contention indicators

- **Potentially Disruptive DBCC Commands** (check_id 5003)
  - Detects execution of DBCC FREEPROCCACHE, FREESYSTEMCACHE, DROPCLEANBUFFERS
  - Identifies DBCC SHRINKDATABASE and SHRINKFILE operations
  - Warns about performance impact on production environments

### Storage Performance (6000-series)

- **I/O Stall Statistics** (check_id 6201)
  - Tracks read/write stalls per database
  - Identifies databases experiencing I/O bottlenecks
  - Calculates average stall times for reads and writes
  - Differentiates between data and log file performance issues

- **Storage Performance by File** (check_id 6202-6204)
  - Analyzes performance metrics for each database file
  - Identifies specific files causing I/O bottlenecks

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

## Results Organization

Results are organized by check_id ranges to help prioritize focus areas:

- **4000-series**: Server configuration issues (memory, CPU, stability)
- **5000-series**: TempDB configuration problems
- **6000-series**: Resource-specific performance issues (waits, I/O, CPU)
- **7000-series**: Database configuration issues

## Results Interpretation

Results are returned in two sections:

1. **Server Information**: General server metrics and configuration details
   - Displays as info_type/value pairs
   - Includes version, resource usage, configuration settings
   - Shows wait statistics summary and resource utilization

2. **Performance Check Results**: Specific findings from all checks
   - Sorted by priority (lower numbers = higher priority)
   - Grouped by category for easier analysis
   - Includes details with explanations and recommendations
   - Contains URLs to documentation and troubleshooting guidance

## Credits

sp_PerfCheck is developed and maintained by Erik Darling of Darling Data, LLC.

For more information, visit: [erikdarling.com](https://erikdarling.com)
