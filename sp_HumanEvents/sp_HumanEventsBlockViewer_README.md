# sp_HumanEventsBlockViewer

This was originally a companion script to analyze the blocked process report Extended Event created by sp_HumanEvents, but has since turned into its own monster.

It will work on any Extended Event that captures the blocked process report. If you need to set that up, run these two pieces of code.

## Setup

Enable the blocked process report:
```sql
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

## Examples

```sql
-- Basic usage with default session name
EXEC dbo.sp_HumanEventsBlockViewer;

-- Use with a custom extended event session name
EXEC dbo.sp_HumanEventsBlockViewer
    @session_name = N'blocked_process_report';

-- Filter by a specific database
EXEC dbo.sp_HumanEventsBlockViewer
    @database_name = 'YourDatabase';

-- Analyze blocking events for a specific time period
EXEC dbo.sp_HumanEventsBlockViewer
    @start_date = '2025-01-01 08:00',
    @end_date = '2025-01-01 17:00';

-- Log results to permanent tables
EXEC dbo.sp_HumanEventsBlockViewer
    @log_to_table = 1,
    @log_database_name = 'DBA',
    @log_schema_name = 'dbo';
```