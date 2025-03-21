<img src="https://erikdarling.com/wp-content/uploads/2025/08/darling-data-logo_RGB.jpg" width="300px" />

# sp_PressureDetector

Is your client/server relationship on the rocks? Are queries timing out, dragging along, or causing CPU fans to spin out of control?

All you need to do is hit F5 to get information about:
* Wait stats since startup
* Database file size, stall, and activity
* tempdb configuration details
* Memory consumers
* Low memory indicators
* Memory configuration and allocation
* Current query memory grants, along with other execution details
* CPU configuration and retained utilization details
* Thread count and current usage 
* Any current THREADPOOL waits (best observed with the DAC)
* Currently executing queries, along with other execution details

## Parameters

|       parameter_name       | data_type |                                  description                                   |                     valid_inputs                     |   defaults   |
|----------------------------|-----------|--------------------------------------------------------------------------------|------------------------------------------------------|--------------|
| @what_to_check             | varchar   | areas to check for pressure                                                    | "all", "cpu", and "memory"                           | all          |
| @skip_queries              | bit       | if you want to skip looking at running queries                                 | 0 or 1                                               | 0            |
| @skip_plan_xml             | bit       | if you want to skip getting plan XML                                           | 0 or 1                                               | 0            |
| @minimum_disk_latency_ms   | smallint  | low bound for reporting disk latency                                           | a reasonable number of milliseconds for disk latency | 100          |
| @cpu_utilization_threshold | smallint  | low bound for reporting high cpu utlization                                    | a reasonable cpu utlization percentage               | 50           |
| @skip_waits                | bit       | skips waits when you do not need them on every run                             | 0 or 1                                               | 0            |
| @skip_perfmon              | bit       | skips perfmon counters when you do not need them on every run                  | a valid tinyint: 0-255                               | 0            |
| @sample_seconds            | tinyint   | take a sample of your server's metrics                                         | 0 or 1                                               | 0            |
| @log_to_table              | bit       | enable logging to permanent tables                                             | 0 or 1                                               | 0            |
| @log_database_name         | sysname   | database to store logging tables                                               | valid database name                                  | NULL         |
| @log_schema_name           | sysname   | schema to store logging tables                                                 | valid schema name                                    | NULL         |
| @log_table_name_prefix     | sysname   | prefix for all logging tables                                                  | valid table name prefix                               | 'PressureDetector' |
| @log_retention_days        | integer   | Number of days to keep logs, 0 = keep indefinitely                             | integer                                              | 30           |
| @help                      | bit       | how you got here                                                               | 0 or 1                                               | 0            |
| @debug                     | bit       | prints dynamic sql, displays parameter and variable values, and table contents | 0 or 1                                               | 0            |
| @version                   | varchar   | OUTPUT; for support                                                            | none                                                 | none; OUTPUT |
| @version_date              | datetime  | OUTPUT; for support                                                            | none                                                 | none; OUTPUT |

## Examples

```sql
-- Basic execution to check all pressure types
EXECUTE dbo.sp_PressureDetector;

-- Check only CPU pressure
EXECUTE dbo.sp_PressureDetector
    @what_to_check = 'cpu';

-- Check only memory pressure
EXECUTE dbo.sp_PressureDetector
    @what_to_check = 'memory';

-- Skip looking at executing queries
EXECUTE dbo.sp_PressureDetector
    @skip_queries = 1;

-- Take a 10-second sample of server metrics
EXECUTE dbo.sp_PressureDetector
    @sample_seconds = 10;

-- Log results to a table
EXECUTE dbo.sp_PressureDetector
    @log_to_table = 1,
    @log_database_name = 'DBA',
    @log_schema_name = 'dbo';
```

## Resources
* [Video walkthrough](https://www.erikdarling.com/sp_pressuredetector/)