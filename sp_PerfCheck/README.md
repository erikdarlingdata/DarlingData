# sp_PerfCheck: SQL Server Performance Health Check

`sp_PerfCheck` is a comprehensive SQL Server performance diagnostic tool that quickly identifies configuration issues, capacity problems, and performance bottlenecks at both server and database levels.

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
| @database_name | sysname | NULL | Specific database to check; NULL checks all accessible user databases |
| @debug | bit | 0 | Print diagnostic messages and intermediate query results |
| @version | varchar(30) | NULL OUTPUT | Returns version number |
| @version_date | datetime | NULL OUTPUT | Returns version date |

## Usage

```sql
-- Basic check on all databases
EXEC dbo.sp_PerfCheck;

-- Check a specific database only
EXEC dbo.sp_PerfCheck
    @database_name = 'YourDatabaseName';

-- Run with debug information
EXEC dbo.sp_PerfCheck
    @debug = 1;
```

## Priority System

All findings are assigned a priority level indicating severity and urgency:

| Priority | Label | Meaning |
|----------|-------|---------|
| 10 | **Critical** | Server instability — crashes, offline resources, pending configuration changes |
| 20 | **High** | Active performance degradation — severe I/O latency, memory pressure, high deadlock rates |
| 30 | **Medium** | Moderate impact or risky configuration that will likely cause problems |
| 40 | **Low** | Best practice recommendations that improve reliability |
| 50 | **Informational** | Awareness items and non-default settings that may be intentional |

Results include a `priority_label` column for readability and are sorted by priority (lowest number first).

## Performance Checks

### Server Configuration

| Check | Finding | Priority | Description |
|-------|---------|----------|-------------|
| 1000 | Non-Default Configuration | Informational (50) | Reports sp_configure options changed from default |
| 1001 | Min Memory Too Close To Max | Low (40) | Min server memory >= 90% of max |
| 1003 | MAXDOP Not Configured | Low (40) | Default MAXDOP (0) on multi-processor system |
| 1004 | Low Cost Threshold | Low (40) | Cost threshold for parallelism <= 5 |
| 1005 | Priority Boost Enabled | High (20) | Dangerous setting affecting Windows scheduling |
| 1006 | Lightweight Pooling Enabled | Low (40) | Fiber mode rarely beneficial |
| 1007 | Config Pending Reconfigure | Critical (10) | Server not running intended configuration |
| 1008 | Affinity Mask Configured | Informational (50) | Manual CPU binding |
| 1009 | Affinity I/O Mask Configured | Informational (50) | Manual I/O CPU binding |
| 1010 | Affinity64 Mask Configured | Informational (50) | CPU binding for processors 33-64 |
| 1011 | Affinity64 I/O Mask Configured | Informational (50) | I/O binding for processors 33-64 |

### TempDB Configuration

| Check | Finding | Priority | Description |
|-------|---------|----------|-------------|
| 2001 | Single TempDB Data File | Medium (30) | Single file causes allocation contention |
| 2002 | Odd Number of TempDB Files | Informational (50) | File count not optimal for CPU count |
| 2003 | More TempDB Files Than CPUs | Informational (50) | More data files than logical processors |
| 2004 | Uneven TempDB File Sizes | Low (40) | Data files vary in size by >10% |
| 2005 | Mixed TempDB Autogrowth | Low (40) | Inconsistent growth settings across files |
| 2006 | Percentage Growth in TempDB | Low (40) | Percentage-based growth in TempDB files |
| 2010 | TempDB Allocation Contention | Medium (30) | Active pagelatch contention detected |

### Storage Performance

| Check | Finding | Priority | Description |
|-------|---------|----------|-------------|
| 3001 | Slow Read Latency | High (20) / Medium (30) | >1000 ms = High, >500 ms = Medium per file |
| 3002 | Slow Write Latency | High (20) / Medium (30) | >1000 ms = High, >500 ms = Medium per file |
| 3003 | Multiple Slow Files on Storage Location | High (20) | Systemic storage problem on a drive |

### Server Health

| Check | Finding | Priority | Description |
|-------|---------|----------|-------------|
| 4001 | Offline CPU Schedulers | Critical (10) | CPUs offline, reducing processing power |
| 4101 | Memory-Starved Queries (forced) | High (20) | Forced grants causing tempdb spills |
| 4102 | Memory Dumps Detected | Critical (10) | Server crashing in last 90 days |
| 4103 | Memory Grant Timeouts | High (20) | Queries can't get memory |
| 4104 | Large Security Token Cache | High/Medium/Low | >5 GB=20, >2 GB=30, >1 GB=40 |
| 4105 | Lock Pages Not Enabled | Low (40) | Best practice for >=32 GB RAM |
| 4106 | IFI Disabled | Low (40) | Best practice for file operations |
| 4107 | Resource Governor Enabled | Informational (50) | May be intentional |

### Trace Events

| Check | Finding | Priority | Description |
|-------|---------|----------|-------------|
| 5001 | Slow Auto-Growth | Medium (30) / Low (40) | Log grows = Medium, data grows = Low |
| 5002 | Auto-Shrink Events | Low (40) | Harmful config executing |
| 5003 | Disruptive DBCC Commands | Medium (30) / Informational (50) | Destructive = Medium, other = Informational |
| 5103 | High Deadlock Rate | High (20) / Medium (30) | >50/day = High, >9/day = Medium |

### Resource Performance

| Check | Finding | Priority | Description |
|-------|---------|----------|-------------|
| 6001 | High Impact Wait Types | High (20) / Medium (30) / Low (40) | Top 10 waits by % of uptime |
| 6002 | High Stolen Memory | High (20) / Medium (30) / Low (40) | Buffer pool starvation |
| 6003 | Top Memory Consumers | Informational (50) | Top 5 non-buffer pool memory clerks |
| 6101 | High Signal Wait Ratio | High (20) / Medium (30) / Low (40) | CPU scheduler contention |
| 6102 | High SOS_SCHEDULER_YIELD | High (20) / Medium (30) / Low (40) | CPU pressure from frequent yields |

### Database Configuration

| Check | Finding | Priority | Description |
|-------|---------|----------|-------------|
| 7001 | Auto-Shrink Enabled | Medium (30) | Actively harmful config |
| 7002 | Auto-Close Enabled | Low (40) | Causes connection delays |
| 7003 | Restricted Access Mode | High (20) | Apps can't connect |
| 7004 | Auto Stats Disabled | Medium (30) | Causes stale statistics |
| 7005 | ANSI Settings | Informational (50) | Non-standard ANSI settings |
| 7006 | Query Store Not Enabled | Informational (50) | Missed opportunity |
| 7007 | Non-Default Recovery Time | Informational (50) | Awareness |
| 7008 | Delayed Durability | Medium (30) | Data loss risk on crash |
| 7009 | ADR Not Enabled | Low (40) | Recommendation for SI/RCSI databases |
| 7010 | Ledger Feature Enabled | Informational (50) | Awareness of overhead |
| 7011 | Query Store State Mismatch | Medium (30) | QS not working as intended |
| 7012 | Query Store Suboptimal Config | Low (40) | Tuning recommendation |
| 7020 | Non-Default DB Scoped Config | Informational (50) | Awareness |

### Database File Settings

| Check | Finding | Priority | Description |
|-------|---------|----------|-------------|
| 7101 | % Growth on Data File | Low (40) | Reports growth % and current file size |
| 7102 | % Growth on Log File | Medium (30) | Reports growth % and current file size |
| 7103 | Non-Optimal Log Growth | Low (40) | Not 64 MB on SQL 2022+/Azure |
| 7104 | Extremely Large Growth | Low (40) | Fixed growth >10 GB |

## Results Organization

Results are organized by check_id ranges:

- **1000-series**: Server configuration settings
- **2000-series**: TempDB configuration
- **3000-series**: Storage performance (file-level I/O)
- **4000-series**: Server health (memory, CPU, stability)
- **5000-series**: Trace events (auto-growth, deadlocks, DBCC)
- **6000-series**: Resource performance (waits, I/O, memory)
- **7000-series**: Database configuration

Results are returned in two result sets:

1. **Server Information**: General server metrics and configuration details
2. **Performance Check Results**: Specific findings sorted by priority, with a `priority_label` column for readability

## Documentation

Full documentation: [erikdarling.com/sp_perfcheck](https://erikdarling.com/sp_perfcheck/)

## Credits

sp_PerfCheck is developed and maintained by Erik Darling of Darling Data, LLC.

For more information, visit: [erikdarling.com](https://erikdarling.com)
