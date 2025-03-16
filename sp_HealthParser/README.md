<img src="https://erikdarling.com/wp-content/uploads/2025/08/darling-data-logo_RGB.jpg" width="300px" />

# sp_HealthParser

The system health extended event has been around for a while, hiding in the shadows, and collecting all sorts of crazy information about your SQL Server.

The problem is, hardly anyone ever looks at it, and when they do, they realize how awful the Extended Events GUI is. Or that if they want to dig deeper into anything, they're going to have to parse XML. 

This stored procedure takes all that pain away.

Note that it focuses on performance data, and does not output errors or security details, or any of the other non-performance related data.

## Results

Typical result set will show you:
* Queries with significant waits
* Waits by count
* Waits by duration
* Potential I/O issues
* CPU task details
* Memory conditions
* Overall system health
* A limited version of the blocked process report
* XML deadlock report
* Query plans for queries involved in blocking and deadlocks (when available)

## Parameters

|        parameter_name        |   data_type    |                             description                             |                             valid_inputs                              |    defaults     |
|------------------------------|----------------|---------------------------------------------------------------------|-----------------------------------------------------------------------|-----------------|
| @what_to_check               | varchar        | areas of system health to check                                     | all, waits, disk, cpu, memory, system, locking                        | all             |
| @start_date                  | datetimeoffset | earliest date to show data for, will be internally converted to UTC | a reasonable date                                                     | seven days back |
| @end_date                    | datetimeoffset | latest date to show data for, will be internally converted to UTC   | a reasonable date                                                     | current date    |
| @warnings_only               | bit            | only show rows where a warning was reported                         | NULL, 0, 1                                                            | 0               |
| @database_name               | sysname        | database name to show blocking events for                           | the name of a database                                                | NULL            |
| @wait_duration_ms            | bigint         | minimum wait duration                                               | the minimum duration of a wait for queries with interesting waits     | 0               |
| @wait_round_interval_minutes | bigint         | interval to round minutes to for wait stats                         | interval to round minutes to for top wait stats by count and duration | 60              |
| @skip_locks                  | bit            | skip the blocking and deadlocking section                           | 0 or 1                                                                | 0               |
| @pending_task_threshold      | integer        | minimum number of pending tasks to display                          | a valid integer                                                       | 10              |
| @log_to_table                | bit            | enable logging to permanent tables                                  | 0 or 1                                                                | 0               |
| @log_database_name           | sysname        | database to store logging tables                                    | valid database name                                                   | NULL            |
| @log_schema_name             | sysname        | schema to store logging tables                                      | valid schema name                                                     | NULL            |
| @log_table_name_prefix       | sysname        | prefix for all logging tables                                       | valid table name prefix                                               | 'HealthParser'  |
| @log_retention_days          | integer        | Number of days to keep logs, 0 = keep indefinitely                  | integer                                                               | 30              |
| @debug                       | bit            | prints dynamic sql, selects from temp tables                        | 0 or 1                                                                | 0               |
| @help                        | bit            | how you got here                                                    | 0 or 1                                                                | 0               |
| @version                     | varchar        | OUTPUT; for support                                                 | none                                                                  | none; OUTPUT    |
| @version_date                | datetime       | OUTPUT; for support                                                 | none                                                                  | none; OUTPUT    |

## Examples

```sql
-- Basic execution for all health checks
EXECUTE dbo.sp_HealthParser;

-- Check only memory-related issues
EXECUTE dbo.sp_HealthParser 
    @what_to_check = 'memory';

-- Look at health issues for a specific time period
EXECUTE dbo.sp_HealthParser
    @start_date = '2025-01-01 00:00:00',
    @end_date = '2025-01-02 00:00:00';

-- Show only health events with warnings
EXECUTE dbo.sp_HealthParser
    @warnings_only = 1;

-- Focus on blocking issues for a specific database
EXECUTE dbo.sp_HealthParser
    @what_to_check = 'locking',
    @database_name = 'YourDatabaseName';

-- Log results to table instead of returning result sets
EXECUTE dbo.sp_HealthParser
    @log_to_table = 1,
    @log_database_name = 'DBA',
    @log_schema_name = 'dbo',
    @log_table_name_prefix = 'HealthParser';
```

## Resources
* [YouTube introduction](https://youtu.be/1kH-aJcCVxs)