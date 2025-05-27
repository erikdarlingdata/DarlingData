<img src="https://erikdarling.com/wp-content/uploads/2025/08/darling-data-logo_RGB.jpg" width="300px" />

# Human Events Toolkit

This directory contains two stored procedures for managing and analyzing Extended Events in SQL Server:

- **[sp_HumanEvents](#sp_humanevents)**: Makes extended events easy to use for common scenarios
- **[sp_HumanEventsBlockViewer](#sp_humaneventsblockviewer)**: Analyzes blocked process reports

## Table of Contents

- [sp_HumanEvents](#sp_humanevents)
  - [Overview](#overview)
  - [Warning](#warning)
  - [Parameters](#parameters)
  - [Usage Examples](#usage-examples)
  - [Resources](#resources)
- [sp_HumanEventsBlockViewer](#sp_humaneventsblockviewer)
  - [Overview](#overview-1)
  - [Setup](#setup)
  - [Parameters](#parameters-1)
  - [Usage Examples](#usage-examples-1)

---

# sp_HumanEvents

## Overview

Extended Events are hard. You don't know which ones to use, when to use them, or how to get useful information out of them.

This procedure is designed to make them easier for you, by creating event sessions to help you troubleshoot common scenarios:
* Blocking: blocked process report
* Query performance: query execution metrics an actual execution plans
* Compiles: catch query compilations
* Recompiles: catch query recompilations
* Wait Stats: server wait stats, broken down by query and database

The default behavior is to run a session for a set period of time to capture information, but you can also set sessions up to data to permanent tables.

## Warning

Misuse of this procedure can harm performance. Be very careful about introducing observer overhead, especially when gathering query plans. Be even more careful when setting up permanent sessions!

## Parameters

|       parameter        |   data_type    |                                         description                                          |                                                    valid_inputs                                                     |                    defaults                     |
|------------------------|----------------|----------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------|-------------------------------------------------|
| @event_type            | sysname        | used to pick which session you want to run                                                   | "blocking", "query", "waits", "recompiles", "compiles" and certain variations on those words                        | "query"                                         |
| @query_duration_ms     | integer        | (>=) used to set a minimum query duration to collect data for                                | an integer                                                                                                          | 500 (ms)                                        |
| @query_sort_order      | nvarchar       | when you use the "query" event, lets you choose which metrics to sort results by             | "cpu", "reads", "writes", "duration", "memory", "spills", and you can add "avg" to sort by averages, e.g. "avg cpu" | "cpu"                                           |
| @skip_plans            | bit            | when you use the "query" event, lets you skip collecting actual execution plans              |1 or 0                                                                                                               | 0                                               |
| @blocking_duration_ms  | integer        | (>=) used to set a minimum blocking duration to collect data for                             | an integer                                                                                                          | 500 (ms)                                        |
| @wait_type             | nvarchar       | (inclusive) filter to only specific wait types                                               | a single wait type, or a CSV list of wait types                                                                     | "all", which uses a list of "interesting" waits |
| @wait_duration_ms      | integer        | (>=) used to set a minimum time per wait to collect data for                                 | an integer                                                                                                          | 10 (ms)                                         |
| @client_app_name       | sysname        | (inclusive) filter to only specific app names                                                | a stringy thing                                                                                                     | intentionally left blank                        |
| @client_hostname       | sysname        | (inclusive) filter to only specific host names                                               | a stringy thing                                                                                                     | intentionally left blank                        |
| @database_name         | sysname        | (inclusive) filter to only specific databases                                                | a stringy thing                                                                                                     | intentionally left blank                        |
| @session_id            | nvarchar       | (inclusive) filter to only a specific session id, or a sample of session ids                 | an integer, or "sample" to sample a workload                                                                        | intentionally left blank                        |
| @sample_divisor        | integer        | the divisor for session ids when sampling a workload, e.g. SPID % 5                          | an integer                                                                                                          | 5                                               |
| @username              | sysname        | (inclusive) filter to only a specific user                                                   | a stringy thing                                                                                                     | intentionally left blank                        |
| @object_name           | sysname        | (inclusive) to only filter to a specific object name                                         | a stringy thing                                                                                                     | intentionally left blank                        |
| @object_schema         | sysname        | (inclusive) the schema of the object you want to filter to; only needed with blocking events | a stringy thing                                                                                                     | dbo                                             |
| @requested_memory_mb   | integer        | (>=) the memory grant a query must ask for to have data collected                            | an integer                                                                                                          | 0                                               |
| @seconds_sample        | tinyint        | the duration in seconds to run the event session for                                         | an integer                                                                                                          | 10                                              |
| @gimme_danger          | bit            | used to override default minimums for query, wait, and blocking durations.                   | 1 or 0                                                                                                              | 0                                               |
| @keep_alive            | bit            | creates a permanent session, either to watch live or log to a table from                     | 1 or 0                                                                                                              | 0                                               |
| @custom_name           | sysname        | if you want to custom name a permanent session                                               | a stringy thing                                                                                                     | intentionally left blank                        |
| @output_database_name  | sysname        | the database you want to log data to                                                         | a valid database name                                                                                               | intentionally left blank                        |
| @output_schema_name    | sysname        | the schema you want to log data to                                                           | a valid schema                                                                                                      | dbo                                             |
| @delete_retention_days | integer        | how many days of logged data you want to keep                                                | a POSITIVE integer                                                                                                  | 3 (days)                                        |
| @cleanup               | bit            | deletes all sessions, tables, and views. requires output database and schema.                | 1 or 0                                                                                                              | 0                                               |
| @max_memory_kb         | bigint         | set a max ring buffer size to log data to                                                    | an integer                                                                                                          | 102400                                          |
| @version               | varchar        | to make sure you have the most recent bits                                                   | none, output                                                                                                        | none, output                                    |
| @version_date          | datetime       | to make sure you have the most recent bits                                                   | none, output                                                                                                        | none, output                                    |
| @debug                 | bit            | use to print out dynamic SQL                                                                 | 1 or 0                                                                                                              | 0                                               |
| @help                  | bit            | well you're here so you figured this one out                                                 | 1 or 0                                                                                                              | 0                                               |

## Usage Examples

If you set up sessions to capture long term data, you'll need an agent job set up to poll them. You can find an example of that here: [sp_Human Events Agent Job Example.sql](sp_Human%20Events%20Agent%20Job%20Example.sql)

Here are some basic usage examples:

```sql
-- Basic execution to capture queries
EXECUTE dbo.sp_HumanEvents;

-- Capture blocking events for at least 1 second
EXECUTE dbo.sp_HumanEvents
    @event_type = 'blocking',
    @blocking_duration_ms = 1000;

-- Capture waits in a specific database
EXECUTE dbo.sp_HumanEvents
    @event_type = 'waits',
    @database_name = 'YourDatabase';

-- Set up a permanent session for logging
EXECUTE dbo.sp_HumanEvents
    @event_type = 'query',
    @keep_alive = 1,
    @output_database_name = 'DBA',
    @output_schema_name = 'dbo';

-- Clean up all sessions and tables
EXECUTE dbo.sp_HumanEvents
    @cleanup = 1,
    @output_database_name = 'DBA',
    @output_schema_name = 'dbo';
```

## Resources
* [YouTube playlist](https://www.youtube.com/playlist?list=PLt4QZ-7lfQifgpvqsa21WLt-u2tZlyoC_)
* [Blog post](https://www.erikdarling.com/sp_humanevents/)

---

# sp_HumanEventsBlockViewer

## Overview

This was originally a companion script to analyze the blocked process report Extended Event created by sp_HumanEvents, but has since turned into its own monster.

It will work on any Extended Event that captures the blocked process report. If you need to set that up, run the next two pieces of code.

The system_health Extended Event works, but its blocked process report is much less comprehensive than the real thing. I do not allow logging to a table from this, because the set of columns and available data is too incomplete, and I don't want to juggle multiple table definitions.

## Setup

Enable the blocked process report:
```sql
EXECUTE sys.sp_configure
    N'show advanced options',
    1;
RECONFIGURE;
GO

EXECUTE sys.sp_configure
    N'blocked process threshold',
    5; --Seconds
RECONFIGURE;
GO
```

Set up the Extended Event:
```sql
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

## Parameters

| parameter_name        | data_type |                   description                      |                              valid_inputs                                                        |              defaults              |
|-----------------------|-----------|----------------------------------------------------|--------------------------------------------------------------------------------------------------|------------------------------------|
| @session_name         | sysname   | name of the extended event session to pull from    | extended event session name capturing sqlserver.blocked_process_report, system_health also works | keeper_HumanEvents_blocking        |
| @target_type          | sysname   | target of the extended event session               | event_file or ring_buffer or table                                                               | NULL                               |
| @start_date           | datetime2 | filter by date                                     | a reasonable date                                                                                | NULL; will shortcut to last 7 days |
| @end_date             | datetime2 | filter by date                                     | a reasonable date                                                                                | NULL                               |
| @database_name        | sysname   | filter by database name                            | a database that exists on this server                                                            | NULL                               |
| @object_name          | sysname   | filter by table name                               | a schema-prefixed table name                                                                     | NULL                               |
| @target_database      | sysname   | database containing the table with BPR data        | a valid database name                                                                            | NULL                               |
| @target_schema        | sysname   | schema of the table                                | a valid schema name                                                                              | NULL                               |
| @target_table         | sysname   | table name                                         | a valid table name                                                                               | NULL                               |
| @target_column        | sysname   | column containing XML data                         | a valid column name                                                                              | NULL                               |
| @timestamp_column     | sysname   | column containing timestamp (optional)             | a valid column name                                                                              | NULL                               |
| @log_to_table         | bit       | enable logging to permanent tables                 | 0 or 1                                                                                           | 0                                  |
| @log_database_name    | sysname   | database to store logging tables                   | a valid database name                                                                            | NULL                               |
| @log_schema_name      | sysname   | schema to store logging tables                     | a valid schema name                                                                              | NULL                               |
| @log_table_name_prefix| sysname   | prefix for all logging tables                      | a valid table name prefix                                                                        | 'HumanEventsBlockViewer'           |
| @log_retention_days   | integer   | Number of days to keep logs, 0 = keep indefinitely | a valid integer                                                                                  | 30                                 |
| @help                 | bit       | how you got here                                   | 0 or 1                                                                                           | 0                                  |
| @debug                | bit       | dumps raw temp table contents                      | 0 or 1                                                                                           | 0                                  |
| @version              | varchar   | OUTPUT; for support                                | none; OUTPUT                                                                                     | none; OUTPUT                       |
| @version_date         | datetime  | OUTPUT; for support                                | none; OUTPUT                                                                                     | none; OUTPUT                       |

## Usage Examples

```sql
-- Basic usage with default session name
EXECUTE dbo.sp_HumanEventsBlockViewer;

-- Use with a custom extended event session name
EXECUTE dbo.sp_HumanEventsBlockViewer
    @session_name = N'blocked_process_report';

-- Filter by a specific database
EXECUTE dbo.sp_HumanEventsBlockViewer
    @database_name = 'YourDatabase';

-- Analyze blocking events for a specific time period
EXECUTE dbo.sp_HumanEventsBlockViewer
    @start_date = '2025-01-01 08:00',
    @end_date = '2025-01-01 17:00';

-- Log results to permanent tables
EXECUTE dbo.sp_HumanEventsBlockViewer
    @log_to_table = 1,
    @log_database_name = 'DBA',
    @log_schema_name = 'dbo';
```
