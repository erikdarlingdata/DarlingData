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
| @slow_read_ms | decimal(10, 2) | 20.0 | Flag data-file reads slower than this many ms; High at 5x this value |
| @slow_write_ms | decimal(10, 2) | 20.0 | Flag data-file writes slower than this many ms; High at 5x this value |
| @significant_wait_threshold_pct | decimal(38, 2) | 10.0 | Minimum percent of uptime for a wait to be reported |
| @wait_high_pct | decimal(38, 2) | 50.0 | A resource wait at or above this percent of uptime is High priority |
| @wait_medium_pct | decimal(38, 2) | 20.0 | A resource wait at or above this percent of uptime is Medium priority |
| @memory_grant_warning | integer | 100 | Forced memory grants at or above this cumulative count are Medium |
| @memory_grant_critical | integer | 10000 | Forced memory grants at or above this cumulative count are High |
| @memory_grant_timeout_warning | decimal(38, 2) | 10.0 | Memory grant timeouts above this cumulative count are Medium |
| @memory_grant_timeout_critical | decimal(38, 2) | 100.0 | Memory grant timeouts above this cumulative count are High |
| @help | bit | 0 | Displays help information |
| @debug | bit | 0 | Print diagnostic messages and intermediate query results |
| @version | varchar(30) | NULL OUTPUT | Returns version number |
| @version_date | datetime | NULL OUTPUT | Returns version date |

The wait percentages are measured against server uptime and are deliberately wide
(`decimal(38, 2)`): cumulative wait time across all schedulers routinely exceeds
100% of wall-clock uptime on a many-core server.

Any of the threshold parameters left NULL or set to a negative number falls back
to its default, so you can override only the ones you care about.

## Usage

```sql
/* Basic check on all databases */
EXECUTE dbo.sp_PerfCheck;

/* Check a specific database only */
EXECUTE dbo.sp_PerfCheck
    @database_name = 'YourDatabaseName';

/* Loosen the storage thresholds for a busy, latency-tolerant system */
EXECUTE dbo.sp_PerfCheck
    @slow_read_ms = 50.0,
    @slow_write_ms = 50.0;

/* Run with debug information */
EXECUTE dbo.sp_PerfCheck
    @debug = 1;
```

## Priority System

All findings are assigned a priority level indicating severity and urgency:

| Priority | Label | Meaning |
|----------|-------|---------|
| 10 | **Critical** | Server instability: crashes, offline resources, pending configuration changes |
| 20 | **High** | Active performance degradation: severe I/O latency, memory pressure, high deadlock rates |
| 30 | **Medium** | Moderate impact or risky configuration that will likely cause problems |
| 40 | **Low** | Best practice recommendations that improve reliability |
| 50 | **Informational** | Awareness items and non-default settings that may be intentional |

Results include a `priority_label` column for readability and are sorted by priority (lowest number first).

## Performance Checks

### Server Configuration

| Check | Finding | Priority | Description |
|-------|---------|----------|-------------|
| 1001 | Min Server Memory Too Close To Max | Low (40) | Min server memory >= 90% of max server memory |
| 1002 | Max Server Memory Too Close To Physical Memory | High (20) | Max server memory >= 95% of physical memory, starving the OS |
| 1003 | MAXDOP Not Configured | Low (40) | Default MAXDOP (0) on a server with more than 8 logical processors |
| 1004 | Cost Threshold for Parallelism Too Low | High (20) / Low (40) | Fires below 50; High when still at or under the default of 5 |
| 1005 | Priority Boost Enabled | High (20) | Dangerous setting affecting Windows scheduling |
| 1006 | Lightweight Pooling Enabled | Low (40) | Fiber mode rarely beneficial |
| 1007 | Configuration Pending Reconfigure | Critical (10) | Server not running its intended configuration |
| 1008 | Affinity Mask Configured | Informational (50) | Manual CPU binding |
| 1009 | Affinity I/O Mask Configured | Informational (50) | Manual I/O CPU binding |
| 1010 | Affinity64 Mask Configured | Informational (50) | CPU binding for processors 33-64 |
| 1011 | Affinity64 I/O Mask Configured | Informational (50) | I/O binding for processors 33-64 |
| 1012 | Notable Global Trace Flag | High (20) / Medium (30) / Low (40) | Interprets notable global trace flags; see below |

Check 1012 reports on global trace flags 1211, 1224, 3608, 3609, 834, 4199, 8048,
1117, 1118, and 2371, with an explanation of what each one does and whether it is
still needed on modern versions. Flags 1211, 3608, and 3609 are High; 1224 and 834
are Medium; the rest are Low. The complete list of enabled global trace flags is
always reported in the server information result set, so benign flags are visible
without being raised as findings.

### TempDB Configuration

| Check | Finding | Priority | Description |
|-------|---------|----------|-------------|
| 2001 | Single TempDB Data File | Medium (30) | Single file causes allocation contention |
| 2002 | Odd Number of TempDB Files | Informational (50) | File count not optimal for CPU count |
| 2003 | More TempDB Files Than CPUs | Informational (50) | More data files than logical processors |
| 2004 | Uneven TempDB Data File Sizes | Low (40) | Data files vary in size by more than 10% |
| 2005 | Mixed TempDB Autogrowth Settings | Low (40) | Inconsistent growth settings across files |
| 2006 | Percentage Auto-Growth Setting in TempDB | Low (40) | Percentage-based growth in TempDB files |
| 2010 | TempDB Allocation Contention Detected | Medium (30) | Active pagelatch contention detected |

### Storage Performance

| Check | Finding | Priority | Description |
|-------|---------|----------|-------------|
| 3001 | Slow Read Latency | High (20) / Medium (30) | Medium above @slow_read_ms (20 ms default), High above 5x that (100 ms default) |
| 3002 | Slow Write Latency | High (20) / Medium (30) | Medium above @slow_write_ms (20 ms default), High above 5x that (100 ms default) |
| 3003 | Multiple Slow Files on Storage Location | High (20) | More than one slow file sharing a drive or volume |

Checks 3001 and 3002 only fire for files with more than 1,000 reads or writes
respectively, so a barely-used file cannot trip them on a handful of slow samples.

### Server Health

| Check | Finding | Priority | Description |
|-------|---------|----------|-------------|
| 4001 | Offline CPU Schedulers | Critical (10) | CPUs offline, reducing processing power |
| 4101 | Memory-Starved Queries: Forced Grants | High (20) / Medium (30) / Low (40) | Graduated on @memory_grant_critical (10000) and @memory_grant_warning (100) |
| 4102 | Memory Dumps Detected In Last 90 Days | Critical (10) | Server crashing in the last 90 days |
| 4103 | Memory-Starved Queries: Grant Timeouts | High (20) / Medium (30) / Low (40) | Graduated on @memory_grant_timeout_critical (100.0) and @memory_grant_timeout_warning (10.0) |
| 4104 | Large Security Token Cache | High (20) / Medium (30) / Low (40) | Over 5 GB = High, over 2 GB = Medium, fires at 1 GB |
| 4105 | Lock Pages in Memory Not Enabled | Low (40) | Best practice for servers with 32 GB or more of RAM |
| 4106 | Instant File Initialization Disabled | Low (40) | Best practice for file creation and growth operations |

Checks 4105 and 4106 are on-premises only. Azure SQL Managed Instance and AWS RDS
do not expose the underlying Windows user rights, so flagging them there would be
unactionable.

### Trace Events

| Check | Finding | Priority | Description |
|-------|---------|----------|-------------|
| 5000 | Inadequate permissions | Informational (50) | `sys.traces` is not readable by the current login, so trace checks are skipped |
| 5001 | Slow Data File / Log File Auto Grow | Medium (30) / Low (40) | Log grows = Medium, data grows = Low |
| 5002 | Data File / Log File Auto Shrink | Low (40) | Harmful config actually executing |
| 5003 | Potentially Disruptive DBCC Commands | Medium (30) / Informational (50) | Cache-clearing and WRITEPAGE = Medium, other = Informational |
| 5004 | Default Trace Not Readable | Informational (50) | Default trace is registered but cannot be read; expected on Linux |
| 5103 | High Number of Deadlocks | High (20) / Medium (30) | More than 50/day = High, more than 9/day = Medium |

Checks 5001 through 5003 read the default trace and look back at most 7 days.
Check 5004 exists so that a server where the default trace cannot be read is
distinguishable from a server that genuinely has nothing to report: on Linux,
`fn_trace_gettable` cannot read the default trace at all.

### Resource Performance

| Check | Finding | Priority | Description |
|-------|---------|----------|-------------|
| 6001 | Per-category wait findings | High (20) / Medium (30) / Low (40) | Top 10 waits by percent of uptime; see below |
| 6002 | High Stolen Memory Percentage | High (20) / Medium (30) / Low (40) | Over 30% = High, over 15% = Medium |
| 6003 | Top Memory Consumer | Informational (50) | Top 5 non-buffer-pool memory clerks using 1 GB or more |
| 6101 | High Signal Wait Ratio | High (20) / Medium (30) / Low (40) | CPU scheduler contention; 50% = High, 30% = Medium, fires at 25% |
| 6102 | High SOS_SCHEDULER_YIELD Waits | High (20) / Medium (30) / Low (40) | CPU pressure from frequent yields; same 50/30/25 thresholds |

Check 6001 does not emit a generic "high wait" finding. It names each finding by
what the wait means for the server: `Storage-Related Waits`, `Memory-Related Waits`,
`Lock / Blocking Waits`, `TempDB Contention Waits`, `Transaction Log Waits`,
`CPU / Scheduling Waits`, `Parallelism Waits`, `Query Execution Waits`,
`Network / Client Waits`, `Availability Group Waits`, `Azure SQL Throttling Waits`,
`Index Maintenance Waits`, `Statistics Update Waits`, or `Other Significant Waits`.
The specific wait type and its plain-English meaning go in `object_name`.

Severity is calibrated by category rather than applied flat. Resource-pressure
waits (locking, memory, storage, tempdb, transaction log, CPU) reach High at
`@wait_high_pct` of uptime or an average wait of 1 second, and Medium at
`@wait_medium_pct` or an average wait of 250 ms. Parallelism waits are usually a
cost threshold or MAXDOP symptom, so they need 100% of uptime just to reach
Medium. Everything else stays Low.

### Database Configuration

| Check | Finding | Priority | Description |
|-------|---------|----------|-------------|
| 7001 | Auto-Shrink Enabled | Medium (30) | Actively harmful config |
| 7002 | Auto-Close Enabled | Low (40) | Causes connection delays |
| 7003 | Restricted Access Mode | High (20) | Database is not in MULTI_USER mode, so apps cannot connect |
| 7004 | Auto Create / Update Statistics Disabled | Medium (30) | Causes missing or stale statistics |
| 7006 | Query Store Not Enabled | Informational (50) | Missed opportunity |
| 7008 | Delayed Durability | Medium (30) | Data loss risk on crash |
| 7009 | Accelerated Database Recovery Not Enabled With Snapshot Isolation | Low (40) | Recommendation for SI/RCSI databases; SQL Server 2019+ only |
| 7010 | Ledger Feature Enabled | Informational (50) | Awareness of overhead |
| 7011 | Query Store State Mismatch | Medium (30) | Query Store is not in the state it was asked to be in |
| 7012 | Query Store Suboptimal Configuration | Low (40) | Tuning recommendation |
| 7020 | Non-Default Database Scoped Configuration | Informational (50) | Awareness |

### Database File Settings

| Check | Finding | Priority | Description |
|-------|---------|----------|-------------|
| 7101 | Percentage Auto-Growth Setting on Data File | Low (40) | Reports growth percent and current file size |
| 7102 | Percentage Auto-Growth Setting on Log File | Medium (30) | Reports growth percent and current file size |
| 7103 | Non-Optimal Log File Growth Increment | Low (40) | Not exactly 64 MB on SQL Server 2022+, Azure SQL DB, or Azure MI |
| 7104 | Extremely Large Auto-Growth Setting | Low (40) | Fixed growth over 10 GB |

## Results Organization

Results are organized by check_id ranges:

- **1000-series**: Server configuration settings and global trace flags
- **2000-series**: TempDB configuration and contention
- **3000-series**: Storage performance (file-level I/O)
- **4000-series**: Server health (memory, CPU, stability)
- **5000-series**: Default trace events (auto-growth, auto-shrink, DBCC) and deadlocks
- **6000-series**: Resource performance (waits, CPU scheduling, memory)
- **7000-series**: Database configuration, with 7100-series covering database file settings

Findings in the `Errors` category are not health checks. They record that a
collection step could not run (missing permissions, an unreadable DMV) so that a
skipped check is never mistaken for a clean result.

Results are returned in two result sets:

1. **Server Information**: General server metrics and configuration details
2. **Performance Check Results**: Specific findings sorted by priority, with a `priority_label` column for readability

## Documentation

Full documentation: [erikdarling.com/sp_perfcheck](https://erikdarling.com/sp_perfcheck/)

## Credits

sp_PerfCheck is developed and maintained by Erik Darling of Darling Data, LLC.

For more information, visit: [erikdarling.com](https://erikdarling.com)
