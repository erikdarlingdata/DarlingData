# <img src="https://erikdarling.com/wp-content/uploads/2025/08/darling-data-logo_RGB.jpg" alt="Darling Data Logo" width="300"/>

# Darling Data: SQL Server Troubleshooting Scripts
<a name="header1"></a>
![licence badge]

# Navigatory 
 - Scripts:
    - [sp_PressureDetector](#pressure-detector): Quickly detect CPU and memory pressure
    - [sp_PerfCheck](#perf-check): Comprehensive SQL Server performance health check
    - [sp_HumanEvents](#human-events): Use Extended Events to track down various query performance issues
    - [sp_HumanEventsBlockViewer](#human-events-block-viewer): Analyze the blocked process report
    - [sp_QuickieStore](#quickie-store): The fastest and most configurable way to navigate Query Store data
    - [sp_HealthParser](#health-parser): Pull all the performance-related data from the system health Extended Event
    - [sp_LogHunter](#log-hunter): Get all of the worst stuff out of your error log
    - [sp_IndexCleanup](#index-cleanup): Identify unused and duplicate indexes

## Who are these scripts for?
You need to troubleshoot performance problems with SQL Server, and you need to do it now. 

You don't have time to track down a bunch of DMVs, figure out Extended Events, wrestle with terrible SSMS interfaces, or learn XML.

These scripts aren't a replacement for a mature monitoring tool, but they do a good job of capturing important issues and reporting on existing diagnostic data

## Support
Right now, all support and Q&A is handled on GitHub. Please be patient; it's just me over here answering questions, fixing bugs, and adding new features.

As far as compatibility goes, they're only guaranted to work on Microsoft-supported SQL Server versions.

Older versions are either missing too much information, or simply aren't compatible (Hello, Extended Events. Hello, Query Store) with the intent of the script.

If you have questions about performance tuning, or SQL Server in general, you'll wanna hit a Q&A site:
 * [Top Answers](https://topanswers.xyz/databases)
 * [DBA Stack Exchange](https://dba.stackexchange.com/)

[*Back to top*](#navigatory)

## Pressure Detector

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

For a video walkthrough of the script and the results, [head over here](https://www.erikdarling.com/sp_pressuredetector/).

Current valid parameter details:

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



[*Back to top*](#navigatory)

## Human Events

Extended Events are hard. You don't know which ones to use, when to use them, or how to get useful information out of them.

This procedure is designed to make them easier for you, by creating event sessions to help you troubleshoot common scenarios:
 * Blocking: blocked process report
 * Query performance: query execution metrics an actual execution plans
 * Compiles: catch query compilations
 * Recompiles: catch query recompilations
 * Wait Stats: server wait stats, broken down by query and database

The default behavior is to run a session for a set period of time to capture information, but you can also set sessions up to data to permanent tables.

For execution examples, see here: [Examples](https://github.com/erikdarlingdata/DarlingData/blob/main/sp_HumanEvents/Examples.sql)

If you set up sessions to capture long term data, you'll need an agent job set up to poll them. You can find an example of that here: [Examples](https://github.com/erikdarlingdata/DarlingData/blob/main/sp_HumanEvents/sp_Human%20Events%20Agent%20Job%20Example.sql)

Misuse of this procedure can harm performance. Be very careful about introducing observer overhead, especially when gathering query plans. Be even more careful when setting up permanent sessions!

More resources:
 * For a video walkthrough of the procedure, code, etc. there's a [YouTube playlist here](https://www.youtube.com/playlist?list=PLt4QZ-7lfQifgpvqsa21WLt-u2tZlyoC_).
 * For a text-based adventure, head to [my site here](https://www.erikdarling.com/sp_humanevents/).

Current valid parameter details:
|       parameter        |   name   |                                         description                                          |                                                    valid_inputs                                                     |                    defaults                     |
|------------------------|----------|----------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------|-------------------------------------------------|
| @event_type            | sysname  | used to pick which session you want to run                                                   | "blocking", "query", "waits", "recompiles", "compiles" and certain variations on those words                        | "query"                                         |
| @query_duration_ms     | integer  | (>=) used to set a minimum query duration to collect data for                                | an integer                                                                                                          | 500 (ms)                                        |
| @query_sort_order      | nvarchar | when you use the "query" event, lets you choose which metrics to sort results by             | "cpu", "reads", "writes", "duration", "memory", "spills", and you can add "avg" to sort by averages, e.g. "avg cpu" | "cpu"                                           |
| @skip_plans            | bit      | when you use the "query" event, lets you skip collecting actual execution plans              |1 or 0                                                                                                               | 0                                               |
| @blocking_duration_ms  | integer  | (>=) used to set a minimum blocking duration to collect data for                             | an integer                                                                                                          | 500 (ms)                                        |
| @wait_type             | nvarchar | (inclusive) filter to only specific wait types                                               | a single wait type, or a CSV list of wait types                                                                     | "all", which uses a list of "interesting" waits |
| @wait_duration_ms      | integer  | (>=) used to set a minimum time per wait to collect data for                                 | an integer                                                                                                          | 10 (ms)                                         |
| @client_app_name       | sysname  | (inclusive) filter to only specific app names                                                | a stringy thing                                                                                                     | intentionally left blank                        |
| @client_hostname       | sysname  | (inclusive) filter to only specific host names                                               | a stringy thing                                                                                                     | intentionally left blank                        |
| @database_name         | sysname  | (inclusive) filter to only specific databases                                                | a stringy thing                                                                                                     | intentionally left blank                        |
| @session_id            | nvarchar | (inclusive) filter to only a specific session id, or a sample of session ids                 | an integer, or "sample" to sample a workload                                                                        | intentionally left blank                        |
| @sample_divisor        | integer  | the divisor for session ids when sampling a workload, e.g. SPID % 5                          | an integer                                                                                                          | 5                                               |
| @username              | sysname  | (inclusive) filter to only a specific user                                                   | a stringy thing                                                                                                     | intentionally left blank                        |
| @object_name           | sysname  | (inclusive) to only filter to a specific object name                                         | a stringy thing                                                                                                     | intentionally left blank                        |
| @object_schema         | sysname  | (inclusive) the schema of the object you want to filter to; only needed with blocking events | a stringy thing                                                                                                     | dbo                                             |
| @requested_memory_mb   | integer  | (>=) the memory grant a query must ask for to have data collected                            | an integer                                                                                                          | 0                                               |
| @seconds_sample        | tinyint  | the duration in seconds to run the event session for                                         | an integer                                                                                                          | 10                                              |
| @gimme_danger          | bit      | used to override default minimums for query, wait, and blocking durations.                   | 1 or 0                                                                                                              | 0                                               |
| @keep_alive            | bit      | creates a permanent session, either to watch live or log to a table from                     | 1 or 0                                                                                                              | 0                                               |
| @custom_name           | nvarchar | if you want to custom name a permanent session                                               | a stringy thing                                                                                                     | intentionally left blank                        |
| @output_database_name  | sysname  | the database you want to log data to                                                         | a valid database name                                                                                               | intentionally left blank                        |
| @output_schema_name    | sysname  | the schema you want to log data to                                                           | a valid schema                                                                                                      | dbo                                             |
| @delete_retention_days | integer  | how many days of logged data you want to keep                                                | a POSITIVE integer                                                                                                  | 3 (days)                                        |
| @cleanup               | bit      | deletes all sessions, tables, and views. requires output database and schema.                | 1 or 0                                                                                                              | 0                                               |
| @max_memory_kb         | bigint   | set a max ring buffer size to log data to                                                    | an integer                                                                                                          | 102400                                          |
| @version               | varchar  | to make sure you have the most recent bits                                                   | none, output                                                                                                        | none, output                                    |
| @version_date          | datetime | to make sure you have the most recent bits                                                   | none, output                                                                                                        | none, output                                    |
| @debug                 | bit      | use to print out dynamic SQL                                                                 | 1 or 0                                                                                                              | 0                                               |
| @help                  | bit      | well you're here so you figured this one out                                                 | 1 or 0                                                                                                              | 0                                               |

[*Back to top*](#navigatory)

## Human Events Block Viewer

This was originally a companion script to analyze the blocked process report Extended Event created by sp_HumanEvents, but has since turned into its own monster.

It will work on any Extended Event that captures the blocked process report. If you need to set that up, run these two pieces of code.

Enable the blocked process report:
```
EXEC sys.sp_configure
    N'show advanced options',
    1;
RECONFIGURE;
GO

EXEC sys.sp_configure
    N'blocked process threshold',
    5; --Seconds
RECONFIGURE;
GO
```
Set up the Extended Event:
```
CREATE EVENT SESSION 
    blocked_process_report
ON SERVER
    ADD EVENT 
        sqlserver.blocked_process_report
    ADD TARGET 
        package0.event_file
    (
        SET filename = N'bpr'
    )
WITH
(
    MAX_MEMORY = 4096KB,
    EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS,
    MAX_DISPATCH_LATENCY = 5 SECONDS,
    MAX_EVENT_SIZE = 0KB,
    MEMORY_PARTITION_MODE = NONE,
    TRACK_CAUSALITY = OFF,
    STARTUP_STATE = ON
);

ALTER EVENT SESSION
    blocked_process_report
ON SERVER 
    STATE = START;
```

Once it has data collected, you can analyze it using this command:

```
EXECUTE dbo.sp_HumanEventsBlockViewer
    @session_name = N'blocked_process_report';
```


Current valid parameter details:

| parameter_name        | data_type |                   description                   |                              valid_inputs                              |              defaults              |
|-----------------------|-----------|-------------------------------------------------|------------------------------------------------------------------------|------------------------------------|
| @session_name         | sysname   | name of the extended event session to pull from | extended event session name capturing sqlserver.blocked_process_report | keeper_HumanEvents_blocking        |
| @target_type          | sysname   | target of the extended event session            | event_file or ring_buffer                                              | NULL                               |
| @start_date           | datetime2 | filter by date                                  | a reasonable date                                                      | NULL; will shortcut to last 7 days |
| @end_date             | datetime2 | filter by date                                  | a reasonable date                                                      | NULL                               |
| @database_name        | sysname   | filter by database name                         | a database that exists on this server                                  | NULL                               |
| @object_name          | sysname   | filter by table name                            | a schema-prefixed table name                                           | NULL                               |
| @target_database      | sysname   | database containing the table with BPR data     | a valid database name                                                  | NULL                               |
| @target_schema        | sysname   | schema of the table                             | a valid schema name                                                    | NULL                               |
| @target_table         | sysname   | table name                                      | a valid table name                                                     | NULL                               |
| @target_column        | sysname   | column containing XML data                      | a valid column name                                                    | NULL                               |
| @timestamp_column     | sysname   | column containing timestamp (optional)          | a valid column name                                                    | NULL                               |
| @log_to_table         | bit       | enable logging to permanent tables              | 0 or 1                                                                 | 0                                  |
| @log_database_name    | sysname   | database to store logging tables                | a valid database name                                                  | NULL                               |
| @log_schema_name      | sysname   | schema to store logging tables                  | a valid schema name                                                    | NULL                               |
| @log_table_name_prefix| sysname   | prefix for all logging tables                   | a valid table name prefix                                              | 'HumanEventsBlockViewer'           |
| @log_retention_days   | integer   | Number of days to keep logs, 0 = keep indefinitely | a valid integer                                                    | 30                                 |
| @help                 | bit       | how you got here                                | 0 or 1                                                                 | 0                                  |
| @debug                | bit       | dumps raw temp table contents                   | 0 or 1                                                                 | 0                                  |
| @version              | varchar   | OUTPUT; for support                             | none; OUTPUT                                                           | none; OUTPUT                       |
| @version_date         | datetime  | OUTPUT; for support                             | none; OUTPUT                                                           | none; OUTPUT                       |

[*Back to top*](#navigatory)

## Quickie Store

This procedure will dig into Query Store data for a specific database, or all databases with Query Store enabled. 

It's designed to run as quickly as possible, but there are some circumstances that prevent me from realizing my ultimate dream.

The big upside of using this stored procedure over the GUI is that you can search for specific items in Query Store, by:
 * query_id
 * plan_id
 * query hash
 * sql handle
 * module name
 * query text
 * query type (ad hoc or from a module)

 You can also choose to filter out specific queries by those, too.

And you can do all that without worrying about incorrect data from the GUI, which doesn't handle UTC conversion correctly when filtering data.

By default, it will return the top 10 queries by average CPU. You can configure all sorts of things to look at queries by other metrics, or just specific queries.

Use the `@expert_mode` parameter to return additional details.

More examples can be found here: [Examples](https://github.com/erikdarlingdata/DarlingData/blob/main/sp_QuickieStore/Examples.sql)

More resources:
 * For a video walkthrough of the procedure, code, etc. there's a [YouTube playlist here](https://www.youtube.com/playlist?list=PLt4QZ-7lfQie1XZHEm0HN-Zt1S7LFEx1P).
 * For a text-based adventure, head to [my site here](https://www.erikdarling.com/sp_quickiestore/).

Current valid parameter details:


|             parameter_name              |   data_type    |                                                                    description                                                                    |                                                                                                                                                                           valid_inputs                                                                                                                                                                            |                                 defaults                                  |
|-----------------------------------------|----------------|---------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------|
| @database_name                          | sysname        | the name of the database you want to look at query store in                                                                                       | a database name with query store enabled                                                                                                                                                                                                                                                                                                                          | NULL; current database name if NULL                                       |
| @sort_order                             | varchar        | the runtime metric you want to prioritize results by                                                                                              | cpu, logical reads, physical reads, writes, duration, memory, tempdb, executions, recent, plan count by hashes, cpu waits, lock waits, locks waits, latch waits, latches waits, buffer latch waits, buffer latches waits, buffer io waits, log waits, log io waits, network waits, network io waits, parallel waits, parallelism waits, memory waits, total waits, rows | cpu                                                                       |
| @top                                    | bigint         | the number of queries you want to pull back                                                                                                       | a positive integer between 1 and 9,223,372,036,854,775,807                                                                                                                                                                                                                                                                                                        | 10                                                                        |
| @start_date                             | datetimeoffset | the begin date of your search, will be converted to UTC internally                                                                                | January 1, 1753, through December 31, 9999                                                                                                                                                                                                                                                                                                                        | the last seven days                                                       |
| @end_date                               | datetimeoffset | the end date of your search, will be converted to UTC internally                                                                                  | January 1, 1753, through December 31, 9999                                                                                                                                                                                                                                                                                                                        | NULL                                                                      |
| @timezone                               | sysname        | user specified time zone to override dates displayed in results                                                                                   | SELECT tzi.* FROM sys.time_zone_info AS tzi;                                                                                                                                                                                                                                                                                                                      | NULL                                                                      |
| @execution_count                        | bigint         | the minimum number of executions a query must have                                                                                                | a positive integer between 1 and 9,223,372,036,854,775,807                                                                                                                                                                                                                                                                                                        | NULL                                                                      |
| @duration_ms                            | bigint         | the minimum duration a query must have to show up in results                                                                                      | a positive integer between 1 and 9,223,372,036,854,775,807                                                                                                                                                                                                                                                                                                        | NULL                                                                      |
| @execution_type_desc                    | nvarchar       | the type of execution you want to filter by (regular, aborted, exception)                                                                                    | regular, aborted, exception                                                                                                                                                                                                                                                                                                                                       | NULL                                                                      |
| @procedure_schema                       | sysname        | the schema of the procedure you're searching for                                                                                                  | a valid schema in your database                                                                                                                                                                                                                                                                                                                                   | NULL; dbo if NULL and procedure name is not NULL                          |
| @procedure_name                         | sysname        | the name of the programmable object you're searching for                                                                                          | a valid programmable object in your database, can use wildcards                                                                                                                                                                                                                                                                                                   | NULL                                                                      |
| @include_plan_ids                       | nvarchar       | a list of plan ids to search for                                                                                                                  | a string; comma separated for multiple ids                                                                                                                                                                                                                                                                                                                        | NULL                                                                      |
| @include_query_ids                      | nvarchar       | a list of query ids to search for                                                                                                                 | a string; comma separated for multiple ids                                                                                                                                                                                                                                                                                                                        | NULL                                                                      |
| @include_query_hashes                   | nvarchar       | a list of query hashes to search for                                                                                                              | a string; comma separated for multiple hashes                                                                                                                                                                                                                                                                                                                     | NULL                                                                      |
| @include_plan_hashes                    | nvarchar       | a list of query plan hashes to search for                                                                                                         | a string; comma separated for multiple hashes                                                                                                                                                                                                                                                                                                                     | NULL                                                                      |
| @include_sql_handles                    | nvarchar       | a list of sql handles to search for                                                                                                               | a string; comma separated for multiple handles                                                                                                                                                                                                                                                                                                                    | NULL                                                                      |
| @ignore_plan_ids                        | nvarchar       | a list of plan ids to ignore                                                                                                                      | a string; comma separated for multiple ids                                                                                                                                                                                                                                                                                                                        | NULL                                                                      |
| @ignore_query_ids                       | nvarchar       | a list of query ids to ignore                                                                                                                     | a string; comma separated for multiple ids                                                                                                                                                                                                                                                                                                                        | NULL                                                                      |
| @ignore_query_hashes                    | nvarchar       | a list of query hashes to ignore                                                                                                                  | a string; comma separated for multiple hashes                                                                                                                                                                                                                                                                                                                     | NULL                                                                      |
| @ignore_plan_hashes                     | nvarchar       | a list of query plan hashes to ignore                                                                                                             | a string; comma separated for multiple hashes                                                                                                                                                                                                                                                                                                                     | NULL                                                                      |
| @ignore_sql_handles                     | nvarchar       | a list of sql handles to ignore                                                                                                                   | a string; comma separated for multiple handles                                                                                                                                                                                                                                                                                                                    | NULL                                                                      |
| @query_text_search                      | nvarchar       | query text to search for                                                                                                                          | a string; leading and trailing wildcards will be added if missing                                                                                                                                                                                                                                                                                                 | NULL                                                                      |
| @query_text_search_not                  | nvarchar       | query text to exclude                                                                                                                             | a string; leading and trailing wildcards will be added if missing                                                                                                                                                                                                                                                                                                 | NULL                                                                      |
| @escape_brackets                        | bit            | Set this bit to 1 to search for query text containing square brackets (common in .NET Entity Framework and other ORM queries)                     | 0 or 1                                                                                                                                                                                                                                                                                                                                                            | 0                                                                         |
| @escape_character                       | nchar          | Sets the ESCAPE character for special character searches, defaults to the SQL standard backslash (\) character                                    | some escape character, SQL standard is backslash (\)                                                                                                                                                                                                                                                                                                              | \                                                                         |
| @only_queries_with_hints                | bit            | only return queries with query hints                                                                                                              | 0 or 1                                                                                                                                                                                                                                                                                                                                                            | 0                                                                         |
| @only_queries_with_feedback             | bit            | only return queries with query feedback                                                                                                           | 0 or 1                                                                                                                                                                                                                                                                                                                                                            | 0                                                                         |
| @only_queries_with_variants             | bit            | only return queries with query variants                                                                                                           | 0 or 1                                                                                                                                                                                                                                                                                                                                                            | 0                                                                         |
| @only_queries_with_forced_plans         | bit            | only return queries with forced plans                                                                                                             | 0 or 1                                                                                                                                                                                                                                                                                                                                                            | 0                                                                         |
| @only_queries_with_forced_plan_failures | bit            | only return queries with forced plan failures                                                                                                     | 0 or 1                                                                                                                                                                                                                                                                                                                                                            | 0                                                                         |
| @wait_filter                            | varchar        | wait category to search for; category details are below                                                                                           | cpu, lock, latch, buffer latch, buffer io, log io, network io, parallelism, memory                                                                                                                                                                                                                                                                                | NULL                                                                      |
| @query_type                             | varchar        | filter for only ad hoc queries or only from queries from modules                                                                                  | ad hoc, adhoc, proc, procedure, whatever.                                                                                                                                                                                                                                                                                                                         | NULL                                                                      |
| @expert_mode                            | bit            | returns additional columns and results                                                                                                            | 0 or 1                                                                                                                                                                                                                                                                                                                                                            | 0                                                                         |
| @hide_help_table                        | bit            | hides the "bottom table" that shows help and support information                                                                                  | 0 or 1                                                                                                                                                                                                                                                                                                                                                            | 0                                                                         |
| @format_output                          | bit            | returns numbers formatted with commas                                                                                                             | 0 or 1                                                                                                                                                                                                                                                                                                                                                            | 1                                                                         |
| @get_all_databases                      | bit            | looks for query store enabled user databases and returns combined results from all of them                                                        | 0 or 1                                                                                                                                                                                                                                                                                                                                                            | 0                                                                         |
| @include_databases                      | nvarchar(4000) | comma-separated list of databases to include (only when @get_all_databases = 1)                                                                            | a string; comma separated database names                                                                                                                                                                                                                                                                                                                          | NULL                                                                      |
| @exclude_databases                      | nvarchar(4000) | comma-separated list of databases to exclude (only when @get_all_databases = 1)                                                                            | a string; comma separated database names                                                                                                                                                                                                                                                                                                                          | NULL                                                                      |
| @workdays                               | bit            | use this to filter out weekends and after-hours queries                                                                                           | 0 or 1                                                                                                                                                                                                                                                                                                                                                            | 0                                                                         |
| @work_start                             | time           | use this to set a specific start of your work days                                                                                                | a time like 8am, 9am or something                                                                                                                                                                                                                                                                                                                                 | 9am                                                                       |
| @work_end                               | time           | use this to set a specific end of your work days                                                                                                  | a time like 5pm, 6pm or something                                                                                                                                                                                                                                                                                                                                 | 5pm                                                                       |
| @regression_baseline_start_date         | datetimeoffset | the begin date of the baseline that you are checking for regressions against (if any), will be converted to UTC internally                        | January 1, 1753, through December 31, 9999                                                                                                                                                                                                                                                                                                                        | NULL                                                                      |
| @regression_baseline_end_date           | datetimeoffset | the end date of the baseline that you are checking for regressions against (if any), will be converted to UTC internally                          | January 1, 1753, through December 31, 9999                                                                                                                                                                                                                                                                                                                        | NULL; One week after @regression_baseline_start_date if that is specified |
| @regression_comparator                  | varchar        | what difference to use ('relative' or 'absolute') when comparing @sort_order's metric for the normal time period with any regression time period. | relative, absolute                                                                                                                                                                                                                                                                                                                                                | NULL; absolute if @regression_baseline_start_date is specified            |
| @regression_direction                   | varchar        | when comparing against any regression baseline, what do you want the results sorted by ('magnitude', 'improved', or 'regressed')?                 | regressed, worse, improved, better, magnitude, absolute, whatever                                                                                                                                                                                                                                                                                                 | NULL; regressed if @regression_baseline_start_date is specified           |
| @include_query_hash_totals             | bit            | will add an additional column to final output with total resource usage by query hash                                                             | 0 or 1                                                                                                                                                                                                                                                                                                                                                            | 0                                                                         |
| @help                                   | bit            | how you got here                                                                                                                                  | 0 or 1                                                                                                                                                                                                                                                                                                                                                            | 0                                                                         |
| @debug                                  | bit            | prints dynamic sql, statement length, parameter and variable values, and raw temp table contents                                                  | 0 or 1                                                                                                                                                                                                                                                                                                                                                            | 0                                                                         |
| @troubleshoot_performance               | bit            | set statistics xml on for queries against views                                                                                                   | 0 or 1                                                                                                                                                                                                                                                                                                                                                            | 0                                                                         |
| @version                                | varchar        | OUTPUT; for support                                                                                                                               | none; OUTPUT                                                                                                                                                                                                                                                                                                                                                      | none; OUTPUT                                                              |
| @version_date                           | datetime       | OUTPUT; for support                                                                                                                               | none; OUTPUT                                                                                                                                                                                                                                                                                                                                                      | none; OUTPUT                                                              |


[*Back to top*](#navigatory)

## Health Parser

The system health extended event has been around for a while, hiding in the shadows, and collecting all sorts of crazy information about your SQL Server.

The problem is, hardly anyone ever looks at it, and when they do, they realize how awful the Extended Events GUI is. Or that if they want to dig deeper into anything, they're going to have to parse XML. 

This stored procedure takes all that pain away.

Note that it focuses on performance data, and does not output errors or security details, or any of the other non-performance related data.

Typical result set will show you
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

More resources:
 * [YouTube introduction](https://youtu.be/1kH-aJcCVxs)

Current valid parameter details:

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

[*Back to top*](#navigatory)

## Log Hunter

The SQL Server error log can have a lot of good information in it about what's goin on, whether it's right or wrong.

The problem is that it's hard to know *what* to look for, and what else was going on once you filter it.

It's another notoriously bad Microsoft GUI, just like Query Store and Extended Events.

I created sp_LogHunter to search through your error logs for the important stuff, with some configurability for you, and return everything ordered by log entry time.

It helps you give you a fuller, better picture of any bad stuff happening.

More resources:
 * [YouTube introduction](https://youtu.be/L_yJ6zPjHfs)

Current valid parameter details:

|    parameter_name    | data_type |                  description                   |                                 valid_inputs                                 |   defaults   |
|----------------------|-----------|------------------------------------------------|------------------------------------------------------------------------------|--------------|
| @days_back           | integer   | how many days back you want to search the logs | an integer; will be converted to a negative number automatically             | -7           |
| @start_date          | datetime  | if you want to search a specific time frame    | a datetime value                                                             | NULL         |
| @end_date            | datetime  | if you want to search a specific time frame    | a datetime value                                                             | NULL         |
| @custom_message      | nvarchar  | if you want to search for a custom string      | something specific you want to search for. no wildcards or substitions.      | NULL         |
| @custom_message_only | bit       | only search for the custom string              | NULL, 0, 1                                                                   | 0            |
| @first_log_only      | bit       | only search through the first error log        | NULL, 0, 1                                                                   | 0            |
| @language_id         | integer   | to use something other than English            | SELECT DISTINCT m.language_id FROM sys.messages AS m ORDER BY m.language_id; | 1033         |
| @help                | bit       | how you got here                               | NULL, 0, 1                                                                   | 0            |
| @debug               | bit       | dumps raw temp table contents                  | NULL, 0, 1                                                                   | 0            |
| @version             | varchar   | OUTPUT; for support                            | OUTPUT; for support                                                          | none; OUTPUT |
| @version_date        | datetime  | OUTPUT; for support                            | OUTPUT; for support                                                          | none; OUTPUT |

[*Back to top*](#navigatory)

## Perf Check

sp_PerfCheck is a comprehensive SQL Server performance diagnostic tool that quickly identifies configuration issues, capacity problems, and performance bottlenecks at both the server and database level.

The procedure performs extensive checks in multiple categories:
- Server configuration and resource usage
- Memory configuration and pressure indicators
- CPU scheduling and pressure
- Storage performance and I/O bottlenecks
- TempDB configuration
- Database configuration settings
- Database file auto-growth settings
- Query Store health and configuration

Results are returned in a prioritized list, with the most critical issues displayed first. The procedure works on SQL Server 2016+ and Azure SQL DB.

Current valid parameter details:

| Parameter | Data Type | Default | Description |
|-----------|-----------|---------|-------------|
| @database_name | sysname | NULL | Specific database to check; NULL runs against all accessible user databases |
| @debug | bit | 0 | Print diagnostic messages and intermediate query results |
| @version | varchar(30) | NULL OUTPUT | Returns version number |
| @version_date | datetime | NULL OUTPUT | Returns version date |

[*Back to top*](#navigatory)

## Index Cleanup

This stored procedure helps identify unused and duplicate indexes in your SQL Server databases that could be candidates for removal. It analyzes index usage statistics and can generate scripts for removing unnecessary indexes.

**IMPORTANT: This is currently a BETA VERSION.** It needs extensive testing in real environments with real indexes to address several issues:
* Data collection accuracy
* Deduping logic
* Result correctness
* Edge cases

Misuse of this procedure can potentially harm your database. If you run this, only use the output to validate result correctness. **Do not run any of the output scripts without thorough review and testing**, as doing so may be harmful to your database performance.

The procedure requires SQL Server 2012 (11.0) or later due to the use of FORMAT and CONCAT functions.

Current valid parameter details:

| Parameter Name | Data Type | Default Value | Description |
|----------------|-----------|---------------|-------------|
| @database_name | sysname | NULL | The name of the database you wish to analyze |
| @schema_name | sysname | NULL | The schema name to filter indexes by |
| @table_name | sysname | NULL | The table name to filter indexes by |
| @min_reads | bigint | 0 | Minimum number of reads for an index to be considered used |
| @min_writes | bigint | 0 | Minimum number of writes for an index to be considered used |
| @min_size_gb | decimal(10,2) | 0 | Minimum size in GB for an index to be analyzed |
| @min_rows | bigint | 0 | Minimum number of rows for a table to be analyzed |
| @get_all_databases | bit | 0 | When set to 1, analyzes all eligible databases on the server |
| @include_databases | nvarchar(max) | NULL | Comma-separated list of databases to include (used with @get_all_databases = 1) |
| @exclude_databases | nvarchar(max) | NULL | Comma-separated list of databases to exclude (used with @get_all_databases = 1) |
| @help | bit | 0 | Displays help information |
| @debug | bit | 0 | Prints debug information during execution |
| @version | varchar(20) | NULL | OUTPUT parameter that returns the version number of the procedure |
| @version_date | datetime | NULL | OUTPUT parameter that returns the date this version was released |

[*Back to top*](#navigatory)

[licence badge]:https://img.shields.io/badge/license-MIT-blue.svg
