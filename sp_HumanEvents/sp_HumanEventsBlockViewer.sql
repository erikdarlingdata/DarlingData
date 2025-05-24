SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
SET IMPLICIT_TRANSACTIONS OFF;
SET STATISTICS TIME, IO OFF;
GO

/*
██╗  ██╗██╗   ██╗███╗   ███╗ █████╗ ███╗   ██╗
██║  ██║██║   ██║████╗ ████║██╔══██╗████╗  ██║
███████║██║   ██║██╔████╔██║███████║██╔██╗ ██║
██╔══██║██║   ██║██║╚██╔╝██║██╔══██║██║╚██╗██║
██║  ██║╚██████╔╝██║ ╚═╝ ██║██║  ██║██║ ╚████║
╚═╝  ╚═╝ ╚═════╝ ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝

███████╗██╗   ██╗███████╗███╗   ██╗████████╗███████╗
██╔════╝██║   ██║██╔════╝████╗  ██║╚══██╔══╝██╔════╝
█████╗  ██║   ██║█████╗  ██╔██╗ ██║   ██║   ███████╗
██╔══╝  ╚██╗ ██╔╝██╔══╝  ██║╚██╗██║   ██║   ╚════██║
███████╗ ╚████╔╝ ███████╗██║ ╚████║   ██║   ███████║
╚══════╝  ╚═══╝  ╚══════╝╚═╝  ╚═══╝   ╚═╝   ╚══════╝

██████╗ ██╗      ██████╗  ██████╗██╗  ██╗
██╔══██╗██║     ██╔═══██╗██╔════╝██║ ██╔╝
██████╔╝██║     ██║   ██║██║     █████╔╝
██╔══██╗██║     ██║   ██║██║     ██╔═██╗
██████╔╝███████╗╚██████╔╝╚██████╗██║  ██╗
╚═════╝ ╚══════╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝

██╗   ██╗██╗███████╗██╗    ██╗███████╗██████╗
██║   ██║██║██╔════╝██║    ██║██╔════╝██╔══██╗
██║   ██║██║█████╗  ██║ █╗ ██║█████╗  ██████╔╝
╚██╗ ██╔╝██║██╔══╝  ██║███╗██║██╔══╝  ██╔══██╗
 ╚████╔╝ ██║███████╗╚███╔███╔╝███████╗██║  ██║
  ╚═══╝  ╚═╝╚══════╝ ╚══╝╚══╝ ╚══════╝╚═╝  ╚═╝

Copyright 2025 Darling Data, LLC
https://www.erikdarling.com/

For usage and licensing details, run:
EXECUTE sp_HumanEventsBlockViewer
    @help = 1;

For working through errors:
EXECUTE sp_HumanEventsBlockViewer
    @debug = 1;

For support, head over to GitHub:
https://code.erikdarling.com
*/

IF OBJECT_ID(N'dbo.sp_HumanEventsBlockViewer', N'P') IS NULL
   BEGIN
       EXECUTE (N'CREATE PROCEDURE dbo.sp_HumanEventsBlockViewer AS RETURN 138;');
   END;
GO

ALTER PROCEDURE
    dbo.sp_HumanEventsBlockViewer
(
    @session_name sysname = N'keeper_HumanEvents_blocking', /*Event session name*/
    @target_type sysname = NULL, /*ring buffer, file, or table*/
    @start_date datetime2 = NULL, /*when to start looking for blocking*/
    @end_date datetime2 = NULL, /*when to stop looking for blocking*/
    @database_name sysname = NULL, /*target a specific database*/
    @object_name sysname = NULL, /*target a specific schema-prefixed table*/
    @target_database sysname = NULL, /*database containing the table with BPR data*/
    @target_schema sysname = NULL, /*schema of the table*/
    @target_table sysname = NULL, /*table name*/
    @target_column sysname = NULL, /*column containing XML data*/
    @timestamp_column sysname = NULL, /*column containing timestamp (optional)*/
    @log_to_table bit = 0, /*enable logging to permanent tables*/
    @log_database_name sysname = NULL, /*database to store logging tables*/
    @log_schema_name sysname = NULL, /*schema to store logging tables*/
    @log_table_name_prefix sysname = 'HumanEventsBlockViewer', /*prefix for all logging tables*/
    @log_retention_days integer = 30, /*Number of days to keep logs, 0 = keep indefinitely*/
    @help bit = 0, /*get help with this procedure*/
    @debug bit = 0, /*print dynamic sql and select temp table contents*/
    @version varchar(30) = NULL OUTPUT, /*check the version number*/
    @version_date datetime = NULL OUTPUT /*check the version date*/
)
WITH RECOMPILE
AS
BEGIN
SET STATISTICS XML OFF;
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

SELECT
    @version = '4.5',
    @version_date = '20250501';

IF @help = 1
BEGIN
    SELECT
        introduction =
            'hi, i''m sp_HumanEventsBlockViewer!' UNION ALL
    SELECT  'you can use me in conjunction with sp_HumanEvents to quickly parse the sqlserver.blocked_process_report event' UNION ALL
    SELECT  'EXECUTE sp_HumanEvents @event_type = N''blocking'', @keep_alive = 1;' UNION ALL
    SELECT  'it will also work with any other extended event session that captures blocking' UNION ALL
    SELECT  'just use the @session_name parameter to point me there' UNION ALL
    SELECT  'EXECUTE dbo.sp_HumanEventsBlockViewer @session_name = N''blocked_process_report'';' UNION ALL
    SELECT  'the system_health session also works, if you are okay with its lousy blocked process report'
    SELECT  'all scripts and documentation are available here: https://code.erikdarling.com' UNION ALL
    SELECT  'from your loving sql server consultant, erik darling: https://erikdarling.com';

    SELECT
        parameter_name =
            ap.name,
        data_type = t.name,
        description =
            CASE ap.name
                 WHEN N'@session_name' THEN 'name of the extended event session to pull from'
                 WHEN N'@target_type' THEN 'target type of the extended event session (ring buffer, file) or ''table'' to read from a table'
                 WHEN N'@start_date' THEN 'filter by date'
                 WHEN N'@end_date' THEN 'filter by date'
                 WHEN N'@database_name' THEN 'filter by database name'
                 WHEN N'@object_name' THEN 'filter by table name'
                 WHEN N'@target_database' THEN 'database containing the table with blocked process report data'
                 WHEN N'@target_schema' THEN 'schema of the table containing blocked process report data'
                 WHEN N'@target_table' THEN 'table containing blocked process report data'
                 WHEN N'@target_column' THEN 'column containing blocked process report XML'
                 WHEN N'@timestamp_column' THEN 'column containing timestamp for filtering (optional)'
                 WHEN N'@log_to_table' THEN N'enable logging to permanent tables instead of returning results'
                 WHEN N'@log_database_name' THEN N'database to store logging tables'
                 WHEN N'@log_schema_name' THEN N'schema to store logging tables'
                 WHEN N'@log_table_name_prefix' THEN N'prefix for all logging tables'
                 WHEN N'@log_retention_days' THEN N'how many days of data to retain'
                 WHEN N'@help' THEN 'how you got here'
                 WHEN N'@debug' THEN 'dumps raw temp table contents'
                 WHEN N'@version' THEN 'OUTPUT; for support'
                 WHEN N'@version_date' THEN 'OUTPUT; for support'
            END,
        valid_inputs =
            CASE ap.name
                 WHEN N'@session_name' THEN 'extended event session name capturing sqlserver.blocked_process_report, system_health also works'
                 WHEN N'@target_type' THEN 'event_file or ring_buffer or table'
                 WHEN N'@start_date' THEN 'a reasonable date'
                 WHEN N'@end_date' THEN 'a reasonable date'
                 WHEN N'@database_name' THEN 'a database that exists on this server'
                 WHEN N'@object_name' THEN 'a schema-prefixed table name'
                 WHEN N'@target_database' THEN 'a database that exists on this server'
                 WHEN N'@target_schema' THEN 'a schema in the target database'
                 WHEN N'@target_table' THEN 'a table in the target schema'
                 WHEN N'@target_column' THEN 'an XML column containing blocked process report data'
                 WHEN N'@timestamp_column' THEN 'a datetime column for filtering by date range'
                 WHEN N'@log_to_table' THEN N'0 or 1'
                 WHEN N'@log_database_name' THEN N'any valid database name'
                 WHEN N'@log_schema_name' THEN N'any valid schema name'
                 WHEN N'@log_table_name_prefix' THEN N'any valid identifier'
                 WHEN N'@log_retention_days' THEN N'a positive integer'
                 WHEN N'@help' THEN '0 or 1'
                 WHEN N'@debug' THEN '0 or 1'
                 WHEN N'@version' THEN 'none; OUTPUT'
                 WHEN N'@version_date' THEN 'none; OUTPUT'
            END,
        defaults =
            CASE ap.name
                 WHEN N'@session_name' THEN 'keeper_HumanEvents_blocking'
                 WHEN N'@target_type' THEN 'NULL'
                 WHEN N'@start_date' THEN 'NULL; will shortcut to last 7 days'
                 WHEN N'@end_date' THEN 'NULL'
                 WHEN N'@database_name' THEN 'NULL'
                 WHEN N'@object_name' THEN 'NULL'
                 WHEN N'@target_database' THEN 'NULL'
                 WHEN N'@target_schema' THEN 'NULL'
                 WHEN N'@target_table' THEN 'NULL'
                 WHEN N'@target_column' THEN 'NULL'
                 WHEN N'@timestamp_column' THEN 'NULL'
                 WHEN N'@log_to_table' THEN N'0'
                 WHEN N'@log_database_name' THEN N'NULL (current database)'
                 WHEN N'@log_schema_name' THEN N'NULL (dbo)'
                 WHEN N'@log_table_name_prefix' THEN N'HumanEventsBlockViewer'
                 WHEN N'@log_retention_days' THEN N'30'
                 WHEN N'@help' THEN '0'
                 WHEN N'@debug' THEN '0'
                 WHEN N'@version' THEN 'none; OUTPUT'
                 WHEN N'@version_date' THEN 'none; OUTPUT'
            END
    FROM sys.all_parameters AS ap
    JOIN sys.all_objects AS o
      ON ap.object_id = o.object_id
    JOIN sys.types AS t
      ON  ap.system_type_id = t.system_type_id
      AND ap.user_type_id = t.user_type_id
    WHERE o.name = N'sp_HumanEventsBlockViewer'
    OPTION(RECOMPILE);

    SELECT
        blocked_process_report_setup =
            N'check the messages tab for setup commands';

    RAISERROR('
Unless you want to use the lousy version in system_health, the blocked process report needs to be enabled:
EXECUTE sys.sp_configure ''show advanced options'', 1;
EXECUTE sys.sp_configure ''blocked process threshold'', 5; /* Seconds of blocking before a report is generated */
RECONFIGURE;', 0, 1) WITH NOWAIT;

    RAISERROR('
/*Create an extended event to log the blocked process report*/
/*
This won''t work in Azure SQLDB, you need to customize it to create:
 * ON DATABASE instead of ON SERVER
 * With a ring_buffer target
*/
CREATE EVENT SESSION
    blocked_process_report
ON SERVER
    ADD EVENT
        sqlserver.blocked_process_report
    ADD TARGET
        package0.event_file
    (
        SET filename = N''bpr''
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
    STATE = START; ', 0, 1) WITH NOWAIT;

    SELECT
        mit_license_yo = 'i am MIT licensed, so like, do whatever'

    UNION ALL

    SELECT
        mit_license_yo = 'see printed messages for full license';

    RAISERROR('
MIT License

Copyright 2025 Darling Data, LLC

https://www.erikdarling.com/

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"),
to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute,
sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the
following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE
FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
', 0, 1) WITH NOWAIT;

    RETURN;
END;

IF @debug = 1
BEGIN
    RAISERROR('Check if we are using system_health', 0, 1) WITH NOWAIT;
END;
DECLARE
    @is_system_health bit = 0,
    @is_system_health_msg nchar(1);

SELECT
    @is_system_health =
        CASE
            WHEN @session_name LIKE N'system%health'
            THEN 1
            ELSE 0
        END,
    @is_system_health_msg =
        CONVERT(nchar(1), @is_system_health);

IF @debug = 1
AND @is_system_health = 0
BEGIN
    RAISERROR('We are not using system_health', 0, 1) WITH NOWAIT;
END;

IF @is_system_health = 1
BEGIN
    RAISERROR('For best results, consider not using system_health as your target. Re-run with @help = 1 for guidance.', 0, 1) WITH NOWAIT;
END

/*
Note: I do not allow logging to a table from system_health, because the set of columns
and available data is too incomplete, and I don't want to juggle multiple
table definitions.

Logging to a table is only allowed from a blocked_process_report Extended Event,
but it can either be ring buffer or file target. I don't care about that.
*/
IF @is_system_health = 1
AND
(
  LOWER(@target_type) = N'table'
  OR @log_to_table = 1
)
BEGIN
    RAISERROR('Logging system_health to a table is not supported.
Either pick a different session or change both
@target_type to be ''event_file'' or ''ring_buffer''
and @log_to_table to be 0.', 11, 0) WITH NOWAIT;
    RETURN;
END

IF @is_system_health = 1
AND @target_type IS NULL
BEGIN
    RAISERROR('No @target_type specified, using ''event_file''.', 0, 1) WITH NOWAIT;
    SELECT
        @target_type = 'event_file';
END

/*Check if the blocked process report is on at all*/
IF EXISTS
(
    SELECT
        1/0
    FROM sys.configurations AS c
    WHERE c.name = N'blocked process threshold (s)'
    AND   CONVERT(int, c.value_in_use) = 0
    AND   @is_system_health = 0
)
BEGIN
    RAISERROR(N'Unless you want to use the lousy version in system_health, the blocked process report needs to be enabled:
EXECUTE sys.sp_configure ''show advanced options'', 1;
EXECUTE sys.sp_configure ''blocked process threshold'', 5; /* Seconds of blocking before a report is generated */
RECONFIGURE;',
    11, 0) WITH NOWAIT;
    RETURN;
END;

/*Check if the blocked process report is well-configured*/
IF EXISTS
(
    SELECT
        1/0
    FROM sys.configurations AS c
    WHERE c.name = N'blocked process threshold (s)'
    AND   CONVERT(int, c.value_in_use) <> 5
    AND   @is_system_health = 0
)
BEGIN
    RAISERROR(N'For best results, set up the blocked process report like this:
EXECUTE sys.sp_configure ''show advanced options'', 1;
EXECUTE sys.sp_configure ''blocked process threshold'', 5; /* Seconds of blocking before a report is generated */
RECONFIGURE;',
    10, 0) WITH NOWAIT;
END;

/*Set some variables for better decision-making later*/
IF @debug = 1
BEGIN
    RAISERROR('Declaring variables', 0, 1) WITH NOWAIT;
END;
DECLARE
    @azure bit =
        CASE
            WHEN CONVERT
                 (
                     integer,
                     SERVERPROPERTY('EngineEdition')
                 ) = 5
            THEN 1
            ELSE 0
        END,
    @azure_msg nchar(1),
    @session_id integer,
    @target_session_id integer,
    @file_name nvarchar(4000),
    @inputbuf_bom nvarchar(1) =
        CONVERT(nvarchar(1), 0x0a00, 0),
    @start_date_original datetime2 = @start_date,
    @end_date_original datetime2 = @end_date,
    @validation_sql nvarchar(max),
    @extract_sql nvarchar(max),
    /*Log to table stuff*/
    @log_table_blocking sysname,
    @cleanup_date datetime2(7),
    @check_sql nvarchar(max) = N'',
    @create_sql nvarchar(max) = N'',
    @insert_sql nvarchar(max) = N'',
    @log_database_schema nvarchar(1024),
    @max_event_time datetime2(7),
    @dsql nvarchar(max) = N'',
    @mdsql nvarchar(max) = N'';

/*Use some sane defaults for input parameters*/
IF @debug = 1
BEGIN
    RAISERROR('Setting variables', 0, 1) WITH NOWAIT;
END;
SELECT
    @start_date =
        CASE
            WHEN @start_date IS NULL
            THEN
                DATEADD
                (
                    MINUTE,
                    DATEDIFF
                    (
                        MINUTE,
                        SYSDATETIME(),
                        GETUTCDATE()
                    ),
                    DATEADD
                        (
                            DAY,
                            -7,
                            SYSDATETIME()
                        )
                )
            ELSE
                DATEADD
                (
                    MINUTE,
                    DATEDIFF
                    (
                        MINUTE,
                        SYSDATETIME(),
                        GETUTCDATE()
                    ),
                    @start_date
                )
        END,
    @end_date =
        CASE
            WHEN @end_date IS NULL
            THEN
                DATEADD
                (
                    MINUTE,
                    DATEDIFF
                    (
                        MINUTE,
                        SYSDATETIME(),
                        GETUTCDATE()
                    ),
                    SYSDATETIME()
                )
            ELSE
                DATEADD
                (
                    MINUTE,
                    DATEDIFF
                    (
                        MINUTE,
                        SYSDATETIME(),
                        GETUTCDATE()
                    ),
                    @end_date
                )
        END,
    @mdsql = N'
IF OBJECT_ID(''{table_check}'', ''U'') IS NOT NULL
BEGIN
    SELECT
        @max_event_time =
            ISNULL
            (
                MAX({date_column}),
                DATEADD
                (
                    MINUTE,
                    DATEDIFF
                    (
                        MINUTE,
                        SYSDATETIME(),
                        GETUTCDATE()
                    ),
                    DATEADD
                    (
                        DAY,
                        -1,
                        SYSDATETIME()
                    )
                )
            )
    FROM {table_check};
END;';

SELECT
    @azure_msg =
        CONVERT(nchar(1), @azure);

/*Change this here in case someone leave it NULL*/
IF  ISNULL(@target_database, DB_NAME()) IS NOT NULL
AND ISNULL(@target_schema, N'dbo') IS NOT NULL
AND @target_table IS NOT NULL
AND @target_column IS NOT NULL
AND @is_system_health = 0
BEGIN
    SET @target_type = N'table';
END;

/* Check for table input early and validate */
IF LOWER(@target_type) = N'table'
BEGIN
    IF @debug = 1
    BEGIN
        RAISERROR('Table source detected, validating parameters', 0, 1) WITH NOWAIT;
    END;

    IF @target_database IS NULL
    BEGIN
        SET @target_database = DB_NAME();
    END;

    IF @target_schema IS NULL
    BEGIN
        SET @target_schema = N'dbo'
    END;

    /* Parameter validation  */
    IF @target_table IS NULL
    OR @target_column IS NULL
    BEGIN
        RAISERROR(N'
        When @target_type is ''table'', you must specify @target_table and @target_column.
        When @target_database or @target_schema is NULL, they default to DB_NAME() and dbo.
        ',
        11, 1) WITH NOWAIT;
        RETURN;
    END;

    /* Check if target database exists */
    IF NOT EXISTS
    (
        SELECT
            1/0
        FROM sys.databases AS d
        WHERE d.name = @target_database
    )
    BEGIN
        RAISERROR(N'The specified @target_database ''%s'' does not exist.', 11, 1, @target_database) WITH NOWAIT;
        RETURN;
    END;

    /* Use dynamic SQL to validate schema, table, and column existence */
    SET @validation_sql = N'
    /*Validate schema exists*/
    IF NOT EXISTS
    (
        SELECT
            1/0
        FROM ' + QUOTENAME(@target_database) + N'.sys.schemas AS s
        WHERE s.name = @schema
    )
    BEGIN
        RAISERROR(N''The specified @target_schema %s does not exist in @database %s'', 11, 1, @schema, @database) WITH NOWAIT;
        RETURN;
    END;

    /*Validate table exists*/
    IF NOT EXISTS
    (
        SELECT
            1/0
        FROM ' + QUOTENAME(@target_database) + N'.sys.tables AS t
        JOIN ' + QUOTENAME(@target_database) + N'.sys.schemas AS s
          ON t.schema_id = s.schema_id
        WHERE t.name = @table
        AND   s.name = @schema
    )
    BEGIN
        RAISERROR(N''The specified @target_table %s does not exist in @schema %s in database %s'', 11, 1, @table, @schema, @database) WITH NOWAIT;
        RETURN;
    END;

    /*Validate column name exists*/
    IF NOT EXISTS
    (
        SELECT
            1/0
        FROM ' + QUOTENAME(@target_database) + N'.sys.columns AS c
        JOIN ' + QUOTENAME(@target_database) + N'.sys.tables AS t
          ON c.object_id = t.object_id
        JOIN ' + QUOTENAME(@target_database) + N'.sys.schemas AS s
          ON t.schema_id = s.schema_id
        WHERE c.name = @column
        AND   t.name = @table
        AND   s.name = @schema
    )
    BEGIN
        RAISERROR(N''The specified @target_column %s does not exist in table %s.%s in database %s'', 11, 1, @column, @schema, @table, @database) WITH NOWAIT;
        RETURN;
    END;

    /* Validate column is XML type */
    IF NOT EXISTS
    (
        SELECT
            1/0
        FROM ' + QUOTENAME(@target_database) + N'.sys.columns AS c
        JOIN ' + QUOTENAME(@target_database) + N'.sys.types AS ty
          ON c.user_type_id = ty.user_type_id
        JOIN ' + QUOTENAME(@target_database) + N'.sys.tables AS t
          ON c.object_id = t.object_id
        JOIN ' + QUOTENAME(@target_database) + N'.sys.schemas AS s
          ON t.schema_id = s.schema_id
        WHERE c.name = @column
        AND   t.name = @table
        AND   s.name = @schema
        AND   ty.name = ''xml''
    )
    BEGIN
        RAISERROR(N''The specified @target_column %s must be of XML data type.'', 11, 1, @column) WITH NOWAIT;
        RETURN;
    END;
    ';

    /* Validate timestamp_column if specified */
    IF @timestamp_column IS NOT NULL
    BEGIN
        SET @validation_sql = @validation_sql + N'
    IF NOT EXISTS
    (
        SELECT
            1/0
        FROM ' + QUOTENAME(@target_database) + N'.sys.columns AS c
        JOIN ' + QUOTENAME(@target_database) + N'.sys.tables AS t
          ON c.object_id = t.object_id
        JOIN ' + QUOTENAME(@target_database) + N'.sys.schemas AS s
          ON t.schema_id = s.schema_id
        WHERE c.name = @timestamp_column
        AND   t.name = @table
        AND   s.name = @schema
    )
    BEGIN
        RAISERROR(N''The specified @timestamp_column %s does not exist in table %s.%s in database %s'', 11, 1, @timestamp_column, @schema, @table, @database) WITH NOWAIT;
        RETURN;
    END;

    /* Validate timestamp column is date-ish type */
    IF NOT EXISTS
    (
        SELECT
            1/0
        FROM ' + QUOTENAME(@target_database) + N'.sys.columns AS c
        JOIN ' + QUOTENAME(@target_database) + N'.sys.types AS ty
          ON c.user_type_id = ty.user_type_id
        JOIN ' + QUOTENAME(@target_database) + N'.sys.tables AS t
          ON c.object_id = t.object_id
        JOIN ' + QUOTENAME(@target_database) + N'.sys.schemas AS s
          ON t.schema_id = s.schema_id
        WHERE c.name = @timestamp_column
        AND   t.name = @table
        AND   s.name = @schema
        AND   ty.name LIKE N''%date%''
    )
    BEGIN
        RAISERROR(N''The specified @timestamp_column %s must be of datetime data type.'', 11, 1, @timestamp_column) WITH NOWAIT;
        RETURN;
    END;';
    END;

    IF @debug = 1
    BEGIN
        PRINT @validation_sql;
    END;

    EXECUTE sys.sp_executesql
        @validation_sql,
        N'
        @database sysname,
        @schema sysname,
        @table sysname,
        @column sysname,
        @timestamp_column sysname
        ',
        @target_database,
        @target_schema,
        @target_table,
        @target_column,
        @timestamp_column;
END;

/* Validate logging parameters */
IF @log_to_table = 1
BEGIN
    SELECT
        /* Default database name to current database if not specified */
        @log_database_name = ISNULL(@log_database_name, DB_NAME()),
        /* Default schema name to dbo if not specified */
        @log_schema_name = ISNULL(@log_schema_name, N'dbo'),
        @log_retention_days =
            CASE
                WHEN @log_retention_days < 0
                THEN ABS(@log_retention_days)
                ELSE @log_retention_days
            END;

    /* Validate database exists */
    IF NOT EXISTS
    (
        SELECT
            1/0
        FROM sys.databases AS d
        WHERE d.name = @log_database_name
    )
    BEGIN
        RAISERROR('The specified logging database %s does not exist. Logging will be disabled.', 11, 1, @log_database_name) WITH NOWAIT;
        RETURN;
    END;

    SET
        @log_database_schema =
            QUOTENAME(@log_database_name) +
            N'.' +
            QUOTENAME(@log_schema_name) +
            N'.';

    /* Generate fully qualified table names */
    SELECT
        @log_table_blocking =
            @log_database_schema +
            QUOTENAME(@log_table_name_prefix + N'_BlockedProcessReport');

    /* Check if schema exists and create it if needed */
    SET @check_sql = N'
        IF NOT EXISTS
        (
            SELECT
                1/0
            FROM ' + QUOTENAME(@log_database_name) + N'.sys.schemas AS s
            WHERE s.name = @schema_name
        )
        BEGIN
            DECLARE
                @create_schema_sql nvarchar(max) = N''CREATE SCHEMA '' + QUOTENAME(@schema_name);

            EXECUTE ' + QUOTENAME(@log_database_name) + N'.sys.sp_executesql @create_schema_sql;
            IF @debug = 1 BEGIN RAISERROR(''Created schema %s in database %s for logging.'', 0, 1, @schema_name, @db_name) WITH NOWAIT; END;
        END';

    EXECUTE sys.sp_executesql
        @check_sql,
      N'@schema_name sysname,
        @db_name sysname,
        @debug bit',
        @log_schema_name,
        @log_database_name,
        @debug;

    SET @create_sql = N'
        IF NOT EXISTS
        (
            SELECT
                1/0
            FROM ' + QUOTENAME(@log_database_name) + N'.sys.tables AS t
            JOIN ' + QUOTENAME(@log_database_name) + N'.sys.schemas AS s
              ON t.schema_id = s.schema_id
            WHERE t.name = @table_name + N''_BlockedProcessReport''
            AND   s.name = @schema_name
        )
        BEGIN
            CREATE TABLE ' + @log_table_blocking + N'
            (
                id bigint IDENTITY,
                collection_time datetime2(7) NOT NULL DEFAULT SYSDATETIME(),
                blocked_process_report varchar(22) NOT NULL,
                event_time datetime2(7) NULL,
                database_name nvarchar(128) NULL,
                currentdbname nvarchar(256) NULL,
                contentious_object nvarchar(4000) NULL,
                activity varchar(8) NULL,
                blocking_tree varchar(8000) NULL,
                spid int NULL,
                ecid int NULL,
                query_text xml NULL,
                wait_time_ms bigint NULL,
                status nvarchar(10) NULL,
                isolation_level nvarchar(50) NULL,
                lock_mode nvarchar(10) NULL,
                resource_owner_type nvarchar(256) NULL,
                transaction_count int NULL,
                transaction_name nvarchar(1024) NULL,
                last_transaction_started datetime2(7) NULL,
                last_transaction_completed datetime2(7) NULL,
                client_option_1 varchar(261) NULL,
                client_option_2 varchar(307) NULL,
                wait_resource nvarchar(1024) NULL,
                priority int NULL,
                log_used bigint NULL,
                client_app nvarchar(256) NULL,
                host_name nvarchar(256) NULL,
                login_name nvarchar(256) NULL,
                transaction_id bigint NULL,
                blocked_process_report_xml xml NULL
                PRIMARY KEY CLUSTERED (collection_time, id)
            );
            IF @debug = 1 BEGIN RAISERROR(''Created table %s for significant waits logging.'', 0, 1, ''' + @log_table_blocking + N''') WITH NOWAIT; END;
        END';

    EXECUTE sys.sp_executesql
        @create_sql,
      N'@schema_name sysname,
        @table_name sysname,
        @debug bit',
        @log_schema_name,
        @log_table_name_prefix,
        @debug;

    /* Handle log retention if specified */
    IF @log_to_table = 1 AND @log_retention_days > 0
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Cleaning up log tables older than %i days', 0, 1, @log_retention_days) WITH NOWAIT;
        END;

        SET @cleanup_date =
            DATEADD
            (
                DAY,
                -@log_retention_days,
                SYSDATETIME()
            );

        /* Clean up each log table */
        SET @dsql = N'
        DELETE FROM ' + @log_table_blocking + '
        WHERE collection_time < @cleanup_date;';

        IF @debug = 1 BEGIN PRINT @dsql; END;

        EXECUTE sys.sp_executesql
            @dsql,
          N'@cleanup_date datetime2(7)',
            @cleanup_date;

        IF @debug = 1
        BEGIN
            RAISERROR('Log cleanup complete', 0, 1) WITH NOWAIT;
        END;
    END;
END;

/*Temp tables for staging results*/
IF @debug = 1
BEGIN
    RAISERROR('Creating temp tables', 0, 1) WITH NOWAIT;
END;
CREATE TABLE
    #x
(
    x xml
);

CREATE TABLE
    #blocking_xml
(
    human_events_xml xml
);

CREATE TABLE
    #block_findings
(
    id integer IDENTITY PRIMARY KEY CLUSTERED,
    check_id integer NOT NULL,
    database_name nvarchar(256) NULL,
    object_name nvarchar(1000) NULL,
    finding_group nvarchar(100) NULL,
    finding nvarchar(4000) NULL,
    sort_order bigint
);

IF LOWER(@target_type) = N'table'
BEGIN
    GOTO TableMode;
    RETURN;
END;

/*Look to see if the session exists and is running*/
IF @debug = 1
BEGIN
    RAISERROR('Checking if the session exists', 0, 1) WITH NOWAIT;
END;
IF @azure = 0
BEGIN
    IF NOT EXISTS
    (
        SELECT
            1/0
        FROM sys.server_event_sessions AS ses
        JOIN sys.dm_xe_sessions AS dxs
          ON dxs.name = ses.name
        WHERE ses.name = @session_name
        AND   dxs.create_time IS NOT NULL
    )
    BEGIN
        RAISERROR('A session with the name %s does not exist or is not currently active.', 11, 1, @session_name) WITH NOWAIT;
        RETURN;
    END;
END;

IF @azure = 1
BEGIN
    IF NOT EXISTS
    (
        SELECT
            1/0
        FROM sys.database_event_sessions AS ses
        JOIN sys.dm_xe_database_sessions AS dxs
          ON dxs.name = ses.name
        WHERE ses.name = @session_name
        AND   dxs.create_time IS NOT NULL
    )
    BEGIN
        RAISERROR('A session with the name %s does not exist or is not currently active.', 11, 1, @session_name) WITH NOWAIT;
        RETURN;
    END;
END;

/*Figure out if we have a file or ring buffer target*/
IF @debug = 1
BEGIN
    RAISERROR('What kind of target does %s have?', 0, 1, @session_name) WITH NOWAIT;
END;
IF  @target_type IS NULL
AND @is_system_health = 0
BEGIN
    IF @azure = 0
    BEGIN
        SELECT TOP (1)
            @target_type =
                t.target_name
        FROM sys.dm_xe_sessions AS s
        JOIN sys.dm_xe_session_targets AS t
          ON s.address = t.event_session_address
        WHERE s.name = @session_name
        ORDER BY t.target_name
        OPTION(RECOMPILE);
    END;

    IF @azure = 1
    BEGIN
        SELECT TOP (1)
            @target_type =
                t.target_name
        FROM sys.dm_xe_database_sessions AS s
        JOIN sys.dm_xe_database_session_targets AS t
          ON s.address = t.event_session_address
        WHERE s.name = @session_name
        ORDER BY t.target_name
        OPTION(RECOMPILE);
    END;
END;

/* Dump whatever we got into a temp table */
IF  LOWER(@target_type) = N'ring_buffer'
AND @is_system_health = 0
BEGIN
    IF @azure = 0
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Azure: %s', 0, 1, @azure_msg) WITH NOWAIT;
            RAISERROR('Inserting to #x for target type: %s and system health: %s', 0, 1, @target_type, @is_system_health_msg) WITH NOWAIT;
        END;

        INSERT
            #x WITH(TABLOCKX)
        (
            x
        )
        SELECT
            x = TRY_CAST(t.target_data AS xml)
        FROM sys.dm_xe_session_targets AS t
        JOIN sys.dm_xe_sessions AS s
          ON s.address = t.event_session_address
        WHERE s.name = @session_name
        AND   t.target_name = N'ring_buffer'
        OPTION(RECOMPILE);
    END;

    IF @azure = 1
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Azure: %s', 0, 1, @azure_msg) WITH NOWAIT;
            RAISERROR('Inserting to #x for target type: %s and system health: %s', 0, 1, @target_type, @is_system_health_msg) WITH NOWAIT;
        END;

        INSERT
            #x WITH(TABLOCKX)
        (
            x
        )
        SELECT
            x = TRY_CAST(t.target_data AS xml)
        FROM sys.dm_xe_database_session_targets AS t
        JOIN sys.dm_xe_database_sessions AS s
          ON s.address = t.event_session_address
        WHERE s.name = @session_name
        AND   t.target_name = N'ring_buffer'
        OPTION(RECOMPILE);
    END;
END;

IF  LOWER(@target_type) = N'event_file'
AND @is_system_health = 0
BEGIN
    IF @azure = 0
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Azure: %s', 0, 1, @azure_msg) WITH NOWAIT;
            RAISERROR('Inserting to #x for target type: %s and system health: %s', 0, 1, @target_type, @is_system_health_msg) WITH NOWAIT;
        END;

        SELECT
            @session_id =
                t.event_session_id,
            @target_session_id =
                t.target_id
        FROM sys.server_event_session_targets t
        JOIN sys.server_event_sessions s
          ON s.event_session_id = t.event_session_id
        WHERE t.name = @target_type
        AND   s.name = @session_name
        OPTION(RECOMPILE);

        SELECT
            @file_name =
                CASE
                    WHEN f.file_name LIKE N'%.xel'
                    THEN REPLACE(f.file_name, N'.xel', N'*.xel')
                    ELSE f.file_name + N'*.xel'
                END
        FROM
        (
            SELECT
                file_name =
                    CONVERT
                    (
                        nvarchar(4000),
                        f.value
                    )
            FROM sys.server_event_session_fields AS f
            WHERE f.event_session_id = @session_id
            AND   f.object_id = @target_session_id
            AND   f.name = N'filename'
        ) AS f
        OPTION(RECOMPILE);
    END;

    IF @azure = 1
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Azure: %s', 0, 1, @azure_msg) WITH NOWAIT;
            RAISERROR('Inserting to #x for target type: %s and system health: %s', 0, 1, @target_type, @is_system_health_msg) WITH NOWAIT;
        END;

        SELECT
            @session_id =
                t.event_session_address,
            @target_session_id =
                t.target_name
        FROM sys.dm_xe_database_session_targets t
        JOIN sys.dm_xe_database_sessions s
          ON s.address = t.event_session_address
        WHERE t.target_name = @target_type
        AND   s.name = @session_name
        OPTION(RECOMPILE);

        SELECT
            @file_name =
                CASE
                    WHEN f.file_name LIKE N'%.xel'
                    THEN REPLACE(f.file_name, N'.xel', N'*.xel')
                    ELSE f.file_name + N'*.xel'
                END
        FROM
        (
            SELECT
                file_name =
                    CONVERT
                    (
                        nvarchar(4000),
                        f.value
                    )
            FROM sys.server_event_session_fields AS f
            WHERE f.event_session_id = @session_id
            AND   f.object_id = @target_session_id
            AND   f.name = N'filename'
        ) AS f
        OPTION(RECOMPILE);
    END;

    IF @debug = 1
    BEGIN
        RAISERROR('Azure: %s', 0, 1, @azure_msg) WITH NOWAIT;
        RAISERROR('Inserting to #x for target type: %s and system health: %s', 0, 1, @target_type, @is_system_health_msg) WITH NOWAIT;
        RAISERROR('File name: %s', 0, 1, @file_name) WITH NOWAIT;
    END;

    INSERT
        #x WITH(TABLOCKX)
    (
        x
    )
    SELECT
        x = TRY_CAST(f.event_data AS xml)
    FROM sys.fn_xe_file_target_read_file
         (
             @file_name,
             NULL,
             NULL,
             NULL
         ) AS f
    OPTION(RECOMPILE);
END;


IF  LOWER(@target_type) = N'ring_buffer'
AND @is_system_health = 0
BEGIN
    IF @debug = 1
    BEGIN
        RAISERROR('Inserting to #blocking_xml for target type: %s and system health: %s', 0, 1, @target_type, @is_system_health_msg) WITH NOWAIT;
    END;

    INSERT
        #blocking_xml
    WITH
        (TABLOCKX)
    (
        human_events_xml
    )
    SELECT
        human_events_xml = e.x.query('.')
    FROM #x AS x
    CROSS APPLY x.x.nodes('/RingBufferTarget/event') AS e(x)
    WHERE e.x.exist('@name[ .= "blocked_process_report"]') = 1
    AND   e.x.exist('@timestamp[. >= sql:variable("@start_date") and .< sql:variable("@end_date")]') = 1
    OPTION(RECOMPILE);
END;

IF  LOWER(@target_type) = N'event_file'
AND @is_system_health = 0
BEGIN
    IF @debug = 1
    BEGIN
        RAISERROR('Inserting to #blocking_xml for target type: %s and system health: %s', 0, 1, @target_type, @is_system_health_msg) WITH NOWAIT;
    END;

    INSERT
        #blocking_xml
    WITH
        (TABLOCKX)
    (
        human_events_xml
    )
    SELECT
        human_events_xml = e.x.query('.')
    FROM #x AS x
    CROSS APPLY x.x.nodes('/event') AS e(x)
    WHERE e.x.exist('@name[ .= "blocked_process_report"]') = 1
    AND   e.x.exist('@timestamp[. >= sql:variable("@start_date") and .< sql:variable("@end_date")]') = 1
    OPTION(RECOMPILE);
END;

/*
This section is special for the well-hidden and much less comprehensive blocked
process report stored in the system health extended event session.

We disallow many features here.
See where @is_system_health was declared for details.
That is also where we error out if somebody tries to use an unsupported feature.
*/
IF  @is_system_health = 1
BEGIN
    IF @debug = 1
    BEGIN
        RAISERROR('Inserting to #sp_server_diagnostics_component_result for system health: %s', 0, 1, @is_system_health_msg) WITH NOWAIT;
    END;

    SELECT
        xml.sp_server_diagnostics_component_result
    INTO #sp_server_diagnostics_component_result
    FROM
    (
        SELECT
            sp_server_diagnostics_component_result =
                TRY_CAST(fx.event_data AS xml)
        FROM sys.fn_xe_file_target_read_file(N'system_health*.xel', NULL, NULL, NULL) AS fx
        WHERE fx.object_name = N'sp_server_diagnostics_component_result'
    ) AS xml
    CROSS APPLY xml.sp_server_diagnostics_component_result.nodes('/event') AS e(x)
    WHERE e.x.exist('//data[@name="data"]/value/queryProcessing/blockingTasks/blocked-process-report') = 1
    AND   e.x.exist('@timestamp[. >= sql:variable("@start_date") and .< sql:variable("@end_date")]') = 1
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#sp_server_diagnostics_component_result',
            ssdcr.*
        FROM #sp_server_diagnostics_component_result AS ssdcr
        OPTION(RECOMPILE);

        RAISERROR('Inserting to #blocking_xml_sh', 0, 1) WITH NOWAIT;
    END;

    SELECT
        event_time =
            DATEADD
            (
                MINUTE,
                DATEDIFF
                (
                    MINUTE,
                    GETUTCDATE(),
                    SYSDATETIME()
                ),
                w.x.value('(//@timestamp)[1]', 'datetime2')
            ),
        human_events_xml = w.x.query('//data[@name="data"]/value/queryProcessing/blockingTasks/blocked-process-report')
    INTO #blocking_xml_sh
    FROM #sp_server_diagnostics_component_result AS wi
    CROSS APPLY wi.sp_server_diagnostics_component_result.nodes('//event') AS w(x)
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#blocking_xml',
            bxs.*
        FROM #blocking_xml_sh AS bxs
        OPTION(RECOMPILE);

        RAISERROR('Inserting to #blocked_sh', 0, 1) WITH NOWAIT;
    END;

    SELECT
        bx.event_time,
        currentdbname = bd.value('(process/@currentdbname)[1]', 'nvarchar(128)'),
        spid = bd.value('(process/@spid)[1]', 'integer'),
        ecid = bd.value('(process/@ecid)[1]', 'integer'),
        query_text_pre = bd.value('(process/inputbuf/text())[1]', 'nvarchar(max)'),
        wait_time = bd.value('(process/@waittime)[1]', 'bigint'),
        lastbatchstarted = bd.value('(process/@lastbatchstarted)[1]', 'datetime2'),
        lastbatchcompleted = bd.value('(process/@lastbatchcompleted)[1]', 'datetime2'),
        wait_resource = bd.value('(process/@waitresource)[1]', 'nvarchar(1024)'),
        status = bd.value('(process/@status)[1]', 'nvarchar(10)'),
        priority = bd.value('(process/@priority)[1]', 'integer'),
        transaction_count = bd.value('(process/@trancount)[1]', 'integer'),
        client_app = bd.value('(process/@clientapp)[1]', 'nvarchar(256)'),
        host_name = bd.value('(process/@hostname)[1]', 'nvarchar(256)'),
        login_name = bd.value('(process/@loginname)[1]', 'nvarchar(256)'),
        isolation_level = bd.value('(process/@isolationlevel)[1]', 'nvarchar(50)'),
        log_used = bd.value('(process/@logused)[1]', 'bigint'),
        clientoption1 = bd.value('(process/@clientoption1)[1]', 'bigint'),
        clientoption2 = bd.value('(process/@clientoption1)[1]', 'bigint'),
        activity = CASE WHEN bd.exist('//blocked-process-report/blocked-process') = 1 THEN 'blocked' END,
        blocked_process_report = bd.query('.')
    INTO #blocked_sh
    FROM #blocking_xml_sh AS bx
    OUTER APPLY bx.human_events_xml.nodes('/event') AS oa(c)
    OUTER APPLY oa.c.nodes('//blocked-process-report/blocked-process') AS bd(bd)
    WHERE bd.exist('process/@spid') = 1
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        RAISERROR('Adding query_text to #blocked_sh', 0, 1) WITH NOWAIT;
    END;

    ALTER TABLE #blocked_sh
    ADD query_text AS
       REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
       REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
       REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
           query_text_pre COLLATE Latin1_General_BIN2,
       NCHAR(31),N'?'),NCHAR(30),N'?'),NCHAR(29),N'?'),NCHAR(28),N'?'),NCHAR(27),N'?'),NCHAR(26),N'?'),NCHAR(25),N'?'),NCHAR(24),N'?'),NCHAR(23),N'?'),NCHAR(22),N'?'),
       NCHAR(21),N'?'),NCHAR(20),N'?'),NCHAR(19),N'?'),NCHAR(18),N'?'),NCHAR(17),N'?'),NCHAR(16),N'?'),NCHAR(15),N'?'),NCHAR(14),N'?'),NCHAR(12),N'?'),
       NCHAR(11),N'?'),NCHAR(8),N'?'),NCHAR(7),N'?'),NCHAR(6),N'?'),NCHAR(5),N'?'),NCHAR(4),N'?'),NCHAR(3),N'?'),NCHAR(2),N'?'),NCHAR(1),N'?'),NCHAR(0),N'?')
    PERSISTED;

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#blocking_sh',
            bxs.*
        FROM #blocking_xml_sh AS bxs
        OPTION(RECOMPILE);

        RAISERROR('Inserting to #blocking_sh', 0, 1) WITH NOWAIT;
    END;

    /*Blocking queries*/
    SELECT
        bx.event_time,
        currentdbname = bg.value('(process/@currentdbname)[1]', 'nvarchar(128)'),
        spid = bg.value('(process/@spid)[1]', 'integer'),
        ecid = bg.value('(process/@ecid)[1]', 'integer'),
        query_text_pre = bg.value('(process/inputbuf/text())[1]', 'nvarchar(max)'),
        wait_time = bg.value('(process/@waittime)[1]', 'bigint'),
        last_transaction_started = bg.value('(process/@lastbatchstarted)[1]', 'datetime2'),
        last_transaction_completed = bg.value('(process/@lastbatchcompleted)[1]', 'datetime2'),
        wait_resource = bg.value('(process/@waitresource)[1]', 'nvarchar(1024)'),
        status = bg.value('(process/@status)[1]', 'nvarchar(10)'),
        priority = bg.value('(process/@priority)[1]', 'integer'),
        transaction_count = bg.value('(process/@trancount)[1]', 'integer'),
        client_app = bg.value('(process/@clientapp)[1]', 'nvarchar(256)'),
        host_name = bg.value('(process/@hostname)[1]', 'nvarchar(256)'),
        login_name = bg.value('(process/@loginname)[1]', 'nvarchar(256)'),
        isolation_level = bg.value('(process/@isolationlevel)[1]', 'nvarchar(50)'),
        log_used = bg.value('(process/@logused)[1]', 'bigint'),
        clientoption1 = bg.value('(process/@clientoption1)[1]', 'bigint'),
        clientoption2 = bg.value('(process/@clientoption1)[1]', 'bigint'),
        activity = CASE WHEN bg.exist('//blocked-process-report/blocking-process') = 1 THEN 'blocking' END,
        blocked_process_report = bg.query('.')
    INTO #blocking_sh
    FROM #blocking_xml_sh AS bx
    OUTER APPLY bx.human_events_xml.nodes('/event') AS oa(c)
    OUTER APPLY oa.c.nodes('//blocked-process-report/blocking-process') AS bg(bg)
    WHERE bg.exist('process/@spid') = 1
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        RAISERROR('Adding query_text to #blocking_sh', 0, 1) WITH NOWAIT;
    END;

    ALTER TABLE #blocking_sh
    ADD query_text AS
       REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
       REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
       REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
           query_text_pre COLLATE Latin1_General_BIN2,
       NCHAR(31),N'?'),NCHAR(30),N'?'),NCHAR(29),N'?'),NCHAR(28),N'?'),NCHAR(27),N'?'),NCHAR(26),N'?'),NCHAR(25),N'?'),NCHAR(24),N'?'),NCHAR(23),N'?'),NCHAR(22),N'?'),
       NCHAR(21),N'?'),NCHAR(20),N'?'),NCHAR(19),N'?'),NCHAR(18),N'?'),NCHAR(17),N'?'),NCHAR(16),N'?'),NCHAR(15),N'?'),NCHAR(14),N'?'),NCHAR(12),N'?'),
       NCHAR(11),N'?'),NCHAR(8),N'?'),NCHAR(7),N'?'),NCHAR(6),N'?'),NCHAR(5),N'?'),NCHAR(4),N'?'),NCHAR(3),N'?'),NCHAR(2),N'?'),NCHAR(1),N'?'),NCHAR(0),N'?')
    PERSISTED;

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#blocking_sh',
            bs.*
        FROM #blocking_sh AS bs
        OPTION(RECOMPILE);

        RAISERROR('Inserting to #blocks_sh', 0, 1) WITH NOWAIT;
    END;

    /*Put it together*/
    SELECT
        kheb.event_time,
        kheb.currentdbname,
        kheb.activity,
        kheb.spid,
        kheb.ecid,
        query_text =
            CASE
                WHEN kheb.query_text
                     LIKE @inputbuf_bom + N'Proc |[Database Id = %' ESCAPE N'|'
                THEN
                    (
                        SELECT
                            [processing-instruction(query)] =
                                OBJECT_SCHEMA_NAME
                                (
                                        SUBSTRING
                                        (
                                            kheb.query_text,
                                            CHARINDEX(N'Object Id = ', kheb.query_text) + 12,
                                            LEN(kheb.query_text) - (CHARINDEX(N'Object Id = ', kheb.query_text) + 12)
                                        )
                                        ,
                                        SUBSTRING
                                        (
                                            kheb.query_text,
                                            CHARINDEX(N'Database Id = ', kheb.query_text) + 14,
                                            CHARINDEX(N'Object Id', kheb.query_text) - (CHARINDEX(N'Database Id = ', kheb.query_text) + 14)
                                        )
                                ) +
                                N'.' +
                                OBJECT_NAME
                                (
                                     SUBSTRING
                                     (
                                         kheb.query_text,
                                         CHARINDEX(N'Object Id = ', kheb.query_text) + 12,
                                         LEN(kheb.query_text) - (CHARINDEX(N'Object Id = ', kheb.query_text) + 12)
                                     )
                                     ,
                                     SUBSTRING
                                     (
                                         kheb.query_text,
                                         CHARINDEX(N'Database Id = ', kheb.query_text) + 14,
                                         CHARINDEX(N'Object Id', kheb.query_text) - (CHARINDEX(N'Database Id = ', kheb.query_text) + 14)
                                     )
                                )
                        FOR XML
                            PATH(N''),
                            TYPE
                    )
                ELSE
                    (
                        SELECT
                            [processing-instruction(query)] =
                                kheb.query_text
                        FOR XML
                            PATH(N''),
                            TYPE
                    )
            END,
        wait_time_ms =
            kheb.wait_time,
        kheb.status,
        kheb.isolation_level,
        kheb.transaction_count,
        kheb.last_transaction_started,
        kheb.last_transaction_completed,
        client_option_1 =
            SUBSTRING
            (
                CASE WHEN kheb.clientoption1 & 1 = 1 THEN ', DISABLE_DEF_CNST_CHECK' ELSE '' END +
                CASE WHEN kheb.clientoption1 & 2 = 2 THEN ', IMPLICIT_TRANSACTIONS' ELSE '' END +
                CASE WHEN kheb.clientoption1 & 4 = 4 THEN ', CURSOR_CLOSE_ON_COMMIT' ELSE '' END +
                CASE WHEN kheb.clientoption1 & 8 = 8 THEN ', ANSI_WARNINGS' ELSE '' END +
                CASE WHEN kheb.clientoption1 & 16 = 16 THEN ', ANSI_PADDING' ELSE '' END +
                CASE WHEN kheb.clientoption1 & 32 = 32 THEN ', ANSI_NULLS' ELSE '' END +
                CASE WHEN kheb.clientoption1 & 64 = 64 THEN ', ARITHABORT' ELSE '' END +
                CASE WHEN kheb.clientoption1 & 128 = 128 THEN ', ARITHIGNORE' ELSE '' END +
                CASE WHEN kheb.clientoption1 & 256 = 256 THEN ', QUOTED_IDENTIFIER' ELSE '' END +
                CASE WHEN kheb.clientoption1 & 512 = 512 THEN ', NOCOUNT' ELSE '' END +
                CASE WHEN kheb.clientoption1 & 1024 = 1024 THEN ', ANSI_NULL_DFLT_ON' ELSE '' END +
                CASE WHEN kheb.clientoption1 & 2048 = 2048 THEN ', ANSI_NULL_DFLT_OFF' ELSE '' END +
                CASE WHEN kheb.clientoption1 & 4096 = 4096 THEN ', CONCAT_NULL_YIELDS_NULL' ELSE '' END +
                CASE WHEN kheb.clientoption1 & 8192 = 8192 THEN ', NUMERIC_ROUNDABORT' ELSE '' END +
                CASE WHEN kheb.clientoption1 & 16384 = 16384 THEN ', XACT_ABORT' ELSE '' END,
                3,
                8000
            ),
        client_option_2 =
            SUBSTRING
            (
                CASE WHEN kheb.clientoption2 & 1024 = 1024 THEN ', DB CHAINING' ELSE '' END +
                CASE WHEN kheb.clientoption2 & 2048 = 2048 THEN ', NUMERIC ROUNDABORT' ELSE '' END +
                CASE WHEN kheb.clientoption2 & 4096 = 4096 THEN ', ARITHABORT' ELSE '' END +
                CASE WHEN kheb.clientoption2 & 8192 = 8192 THEN ', ANSI PADDING' ELSE '' END +
                CASE WHEN kheb.clientoption2 & 16384 = 16384 THEN ', ANSI NULL DEFAULT' ELSE '' END +
                CASE WHEN kheb.clientoption2 & 65536 = 65536 THEN ', CONCAT NULL YIELDS NULL' ELSE '' END +
                CASE WHEN kheb.clientoption2 & 131072 = 131072 THEN ', RECURSIVE TRIGGERS' ELSE '' END +
                CASE WHEN kheb.clientoption2 & 1048576 = 1048576 THEN ', DEFAULT TO LOCAL CURSOR' ELSE '' END +
                CASE WHEN kheb.clientoption2 & 8388608 = 8388608 THEN ', QUOTED IDENTIFIER' ELSE '' END +
                CASE WHEN kheb.clientoption2 & 16777216 = 16777216 THEN ', AUTO CREATE STATISTICS' ELSE '' END +
                CASE WHEN kheb.clientoption2 & 33554432 = 33554432 THEN ', CURSOR CLOSE ON COMMIT' ELSE '' END +
                CASE WHEN kheb.clientoption2 & 67108864 = 67108864 THEN ', ANSI NULLS' ELSE '' END +
                CASE WHEN kheb.clientoption2 & 268435456 = 268435456 THEN ', ANSI WARNINGS' ELSE '' END +
                CASE WHEN kheb.clientoption2 & 536870912 = 536870912 THEN ', FULL TEXT ENABLED' ELSE '' END +
                CASE WHEN kheb.clientoption2 & 1073741824 = 1073741824 THEN ', AUTO UPDATE STATISTICS' ELSE '' END +
                CASE WHEN kheb.clientoption2 & 1469283328 = 1469283328 THEN ', ALL SETTABLE OPTIONS' ELSE '' END,
                3,
                8000
            ),
        kheb.wait_resource,
        kheb.priority,
        kheb.log_used,
        kheb.client_app,
        kheb.host_name,
        kheb.login_name,
        kheb.blocked_process_report
    INTO #blocks_sh
    FROM
    (
        SELECT
            bg.*
        FROM #blocking_sh AS bg
        WHERE (bg.currentdbname = @database_name
               OR @database_name IS NULL)

        UNION ALL

        SELECT
            bd.*
        FROM #blocked_sh AS bd
        WHERE (bd.currentdbname = @database_name
               OR @database_name IS NULL)
    ) AS kheb
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#blocks_sh',
            bs.*
        FROM #blocks_sh AS bs
        OPTION(RECOMPILE);
    END;

    SELECT
        b.event_time,
        b.currentdbname,
        b.activity,
        b.spid,
        b.ecid,
        b.query_text,
        b.wait_time_ms,
        b.status,
        b.isolation_level,
        b.transaction_count,
        b.last_transaction_started,
        b.last_transaction_completed,
        b.client_option_1,
        b.client_option_2,
        b.wait_resource,
        b.priority,
        b.log_used,
        b.client_app,
        b.host_name,
        b.login_name,
        b.blocked_process_report
    FROM #blocks_sh AS b
    ORDER BY
        b.event_time DESC,
        CASE
            WHEN b.activity = 'blocking'
            THEN -1
            ELSE +1
        END
    OPTION(RECOMPILE);

    BEGIN
        RAISERROR('Inserting to #available_plans_sh', 0, 1) WITH NOWAIT;
    END;

    SELECT DISTINCT
        b.*
    INTO #available_plans_sh
    FROM
    (
        SELECT
            available_plans =
                'available_plans',
            b.currentdbname,
            query_text =
                TRY_CAST(b.query_text AS nvarchar(max)),
            sql_handle =
                CONVERT(varbinary(64), n.c.value('@sqlhandle', 'varchar(130)'), 1),
            stmtstart =
                ISNULL(n.c.value('@stmtstart', 'integer'), 0),
            stmtend =
                ISNULL(n.c.value('@stmtend', 'integer'), -1)
        FROM #blocks_sh AS b
        CROSS APPLY b.blocked_process_report.nodes('/blocked-process/process/executionStack/frame[not(@sqlhandle = "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")]') AS n(c)
        WHERE (b.currentdbname = @database_name
                OR @database_name IS NULL)

        UNION ALL

        SELECT
            available_plans =
                'available_plans',
            b.currentdbname,
            query_text =
                TRY_CAST(b.query_text AS nvarchar(max)),
            sql_handle =
                CONVERT(varbinary(64), n.c.value('@sqlhandle', 'varchar(130)'), 1),
            stmtstart =
                ISNULL(n.c.value('@stmtstart', 'integer'), 0),
            stmtend =
                ISNULL(n.c.value('@stmtend', 'integer'), -1)
        FROM #blocks_sh AS b
        CROSS APPLY b.blocked_process_report.nodes('/blocking-process/process/executionStack/frame[not(@sqlhandle = "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")]') AS n(c)
        WHERE (b.currentdbname = @database_name
                OR @database_name IS NULL)
    ) AS b
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#available_plans_sh',
            aps.*
        FROM #available_plans_sh AS aps
        OPTION(RECOMPILE);

        RAISERROR('Inserting to #dm_exec_query_stats_sh', 0, 1) WITH NOWAIT;
    END;

    SELECT
        deqs.sql_handle,
        deqs.plan_handle,
        deqs.statement_start_offset,
        deqs.statement_end_offset,
        deqs.creation_time,
        deqs.last_execution_time,
        deqs.execution_count,
        total_worker_time_ms =
            deqs.total_worker_time / 1000.,
        avg_worker_time_ms =
            CONVERT(decimal(38, 6), deqs.total_worker_time / 1000. / deqs.execution_count),
        total_elapsed_time_ms =
            deqs.total_elapsed_time / 1000.,
        avg_elapsed_time_ms =
            CONVERT(decimal(38, 6), deqs.total_elapsed_time / 1000. / deqs.execution_count),
        executions_per_second =
            ISNULL
            (
                deqs.execution_count /
                    NULLIF
                    (
                        DATEDIFF
                        (
                            SECOND,
                            deqs.creation_time,
                            NULLIF(deqs.last_execution_time, '1900-01-01 00:00:00.000')
                        ),
                        0
                    ),
                    0
            ),
        total_physical_reads_mb =
            deqs.total_physical_reads * 8. / 1024.,
        total_logical_writes_mb =
            deqs.total_logical_writes * 8. / 1024.,
        total_logical_reads_mb =
            deqs.total_logical_reads * 8. / 1024.,
        min_grant_mb =
            deqs.min_grant_kb * 8. / 1024.,
        max_grant_mb =
            deqs.max_grant_kb * 8. / 1024.,
        min_used_grant_mb =
            deqs.min_used_grant_kb * 8. / 1024.,
        max_used_grant_mb =
            deqs.max_used_grant_kb * 8. / 1024.,
        deqs.min_reserved_threads,
        deqs.max_reserved_threads,
        deqs.min_used_threads,
        deqs.max_used_threads,
        deqs.total_rows,
        max_worker_time_ms =
            deqs.max_worker_time / 1000.,
        max_elapsed_time_ms =
            deqs.max_elapsed_time / 1000.
    INTO #dm_exec_query_stats_sh
    FROM sys.dm_exec_query_stats AS deqs
    WHERE EXISTS
    (
        SELECT
            1/0
        FROM #available_plans_sh AS ap
        WHERE ap.sql_handle = deqs.sql_handle
    )
    AND deqs.query_hash IS NOT NULL
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        RAISERROR('Creating clustered index on #dm_exec_query_stats_sh', 0, 1) WITH NOWAIT;
    END;

    CREATE CLUSTERED INDEX
        deqs_sh
    ON #dm_exec_query_stats_sh
    (
        sql_handle,
        plan_handle
    );

    SELECT
        ap.available_plans,
        ap.currentdbname,
        query_text =
            TRY_CAST(ap.query_text AS xml),
        ap.query_plan,
        ap.creation_time,
        ap.last_execution_time,
        ap.execution_count,
        ap.executions_per_second,
        ap.total_worker_time_ms,
        ap.avg_worker_time_ms,
        ap.max_worker_time_ms,
        ap.total_elapsed_time_ms,
        ap.avg_elapsed_time_ms,
        ap.max_elapsed_time_ms,
        ap.total_logical_reads_mb,
        ap.total_physical_reads_mb,
        ap.total_logical_writes_mb,
        ap.min_grant_mb,
        ap.max_grant_mb,
        ap.min_used_grant_mb,
        ap.max_used_grant_mb,
        ap.min_reserved_threads,
        ap.max_reserved_threads,
        ap.min_used_threads,
        ap.max_used_threads,
        ap.total_rows,
        ap.sql_handle,
        ap.statement_start_offset,
        ap.statement_end_offset
    FROM
    (
        SELECT
            ap.*,
            c.statement_start_offset,
            c.statement_end_offset,
            c.creation_time,
            c.last_execution_time,
            c.execution_count,
            c.total_worker_time_ms,
            c.avg_worker_time_ms,
            c.total_elapsed_time_ms,
            c.avg_elapsed_time_ms,
            c.executions_per_second,
            c.total_physical_reads_mb,
            c.total_logical_writes_mb,
            c.total_logical_reads_mb,
            c.min_grant_mb,
            c.max_grant_mb,
            c.min_used_grant_mb,
            c.max_used_grant_mb,
            c.min_reserved_threads,
            c.max_reserved_threads,
            c.min_used_threads,
            c.max_used_threads,
            c.total_rows,
            c.query_plan,
            c.max_worker_time_ms,
            c.max_elapsed_time_ms
        FROM #available_plans_sh AS ap
        OUTER APPLY
        (
            SELECT
                deqs.*,
                query_plan =
                    TRY_CAST(deps.query_plan AS xml)
            FROM #dm_exec_query_stats_sh AS deqs
            OUTER APPLY sys.dm_exec_text_query_plan
            (
                deqs.plan_handle,
                deqs.statement_start_offset,
                deqs.statement_end_offset
            ) AS deps
            WHERE deqs.sql_handle = ap.sql_handle
        ) AS c
    ) AS ap
    WHERE ap.query_plan IS NOT NULL
    ORDER BY
        ap.avg_worker_time_ms DESC
    OPTION(RECOMPILE, LOOP JOIN, HASH JOIN);
    RETURN;
    /*End system health section, skips checks because most of them won't run*/
END;

TableMode:
IF LOWER(@target_type) = N'table'
BEGIN
    IF @debug = 1
    BEGIN
        RAISERROR('Extracting blocked process reports from table %s.%s.%s', 0, 1, @target_database, @target_schema, @target_table) WITH NOWAIT;
    END;

    /* Build dynamic SQL to extract the XML */
    SET @extract_sql = N'
    SELECT
        human_events_xml = ' +
        QUOTENAME(@target_column) +
        N'
    FROM ' +
    QUOTENAME(@target_database) +
    N'.' +
    QUOTENAME(@target_schema) +
    N'.' +
    QUOTENAME(@target_table) +
    N' AS x
    CROSS APPLY x.' +
    QUOTENAME(@target_column) +
    N'.nodes(''/event'') AS e(x)
    WHERE e.x.exist(''@name[ .= "blocked_process_report"]'') = 1';

    /* Add timestamp filtering if specified*/
    IF @timestamp_column IS NOT NULL
    BEGIN
            SET @extract_sql = @extract_sql + N'
    AND   x.' + QUOTENAME(@timestamp_column) + N' >= @start_date
    AND   x.' + QUOTENAME(@timestamp_column) + N' < @end_date';
    END;

    IF @timestamp_column IS NULL
    BEGIN
        BEGIN
            SET @extract_sql = @extract_sql + N'
    AND   e.x.exist(''@timestamp[. >= sql:variable("@start_date") and . < sql:variable("@end_date")]'') = 1';
        END;
    END;

    SET @extract_sql = @extract_sql + N'
    OPTION(RECOMPILE);
    ';

    IF @debug = 1
    BEGIN
        PRINT @extract_sql;
    END;

    /* Execute the dynamic SQL*/
    INSERT
        #blocking_xml
    WITH
        (TABLOCKX)
    (
        human_events_xml
    )
    EXECUTE sys.sp_executesql
        @extract_sql,
      N'@start_date datetime2,
        @end_date datetime2',
        @start_date,
        @end_date;
END;

IF @debug = 1
BEGIN
    SELECT
        table_name = N'#blocking_xml',
        bx.*
    FROM #blocking_xml AS bx
    OPTION(RECOMPILE);

    RAISERROR('Inserting to #blocked', 0, 1) WITH NOWAIT;
END;

SELECT
    event_time =
        DATEADD
        (
            MINUTE,
            DATEDIFF
            (
                MINUTE,
                GETUTCDATE(),
                SYSDATETIME()
            ),
            c.value('@timestamp', 'datetime2')
        ),
    database_name = DB_NAME(c.value('(data[@name="database_id"]/value/text())[1]', 'integer')),
    database_id = c.value('(data[@name="database_id"]/value/text())[1]', 'integer'),
    object_id = c.value('(data[@name="object_id"]/value/text())[1]', 'integer'),
    transaction_id = c.value('(data[@name="transaction_id"]/value/text())[1]', 'bigint'),
    resource_owner_type = c.value('(data[@name="resource_owner_type"]/text)[1]', 'nvarchar(256)'),
    monitor_loop = c.value('(//@monitorLoop)[1]', 'integer'),
    blocking_spid = bg.value('(process/@spid)[1]', 'integer'),
    blocking_ecid = bg.value('(process/@ecid)[1]', 'integer'),
    blocked_spid = bd.value('(process/@spid)[1]', 'integer'),
    blocked_ecid = bd.value('(process/@ecid)[1]', 'integer'),
    query_text_pre = bd.value('(process/inputbuf/text())[1]', 'nvarchar(max)'),
    wait_time = bd.value('(process/@waittime)[1]', 'bigint'),
    transaction_name = bd.value('(process/@transactionname)[1]', 'nvarchar(1024)'),
    last_transaction_started = bd.value('(process/@lasttranstarted)[1]', 'datetime2'),
    last_transaction_completed = CONVERT(datetime2, NULL),
    wait_resource = bd.value('(process/@waitresource)[1]', 'nvarchar(1024)'),
    lock_mode = bd.value('(process/@lockMode)[1]', 'nvarchar(10)'),
    status = bd.value('(process/@status)[1]', 'nvarchar(10)'),
    priority = bd.value('(process/@priority)[1]', 'integer'),
    transaction_count = bd.value('(process/@trancount)[1]', 'integer'),
    client_app = bd.value('(process/@clientapp)[1]', 'nvarchar(256)'),
    host_name = bd.value('(process/@hostname)[1]', 'nvarchar(256)'),
    login_name = bd.value('(process/@loginname)[1]', 'nvarchar(256)'),
    isolation_level = bd.value('(process/@isolationlevel)[1]', 'nvarchar(50)'),
    log_used = bd.value('(process/@logused)[1]', 'bigint'),
    clientoption1 = bd.value('(process/@clientoption1)[1]', 'bigint'),
    clientoption2 = bd.value('(process/@clientoption1)[1]', 'bigint'),
    currentdbname = bd.value('(process/@currentdbname)[1]', 'nvarchar(256)'),
    currentdbid = bd.value('(process/@currentdb)[1]', 'integer'),
    blocking_level = 0,
    sort_order = CAST('' AS varchar(400)),
    activity = CASE WHEN oa.c.exist('//blocked-process-report/blocked-process') = 1 THEN 'blocked' END,
    blocked_process_report = c.query('.')
INTO #blocked
FROM #blocking_xml AS bx
OUTER APPLY bx.human_events_xml.nodes('/event') AS oa(c)
OUTER APPLY oa.c.nodes('//blocked-process-report/blocked-process') AS bd(bd)
OUTER APPLY oa.c.nodes('//blocked-process-report/blocking-process') AS bg(bg)
OPTION(RECOMPILE);

IF @debug = 1
BEGIN
    RAISERROR('Adding query_text to #blocked', 0, 1) WITH NOWAIT;
END;

ALTER TABLE
    #blocked
ADD query_text AS
   REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
   REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
   REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
       query_text_pre COLLATE Latin1_General_BIN2,
   NCHAR(31),N'?'),NCHAR(30),N'?'),NCHAR(29),N'?'),NCHAR(28),N'?'),NCHAR(27),N'?'),NCHAR(26),N'?'),NCHAR(25),N'?'),NCHAR(24),N'?'),NCHAR(23),N'?'),NCHAR(22),N'?'),
   NCHAR(21),N'?'),NCHAR(20),N'?'),NCHAR(19),N'?'),NCHAR(18),N'?'),NCHAR(17),N'?'),NCHAR(16),N'?'),NCHAR(15),N'?'),NCHAR(14),N'?'),NCHAR(12),N'?'),
   NCHAR(11),N'?'),NCHAR(8),N'?'),NCHAR(7),N'?'),NCHAR(6),N'?'),NCHAR(5),N'?'),NCHAR(4),N'?'),NCHAR(3),N'?'),NCHAR(2),N'?'),NCHAR(1),N'?'),NCHAR(0),N'?')
PERSISTED;

IF @debug = 1
BEGIN
    RAISERROR('Adding blocking_desc to #blocked', 0, 1) WITH NOWAIT;
END;

ALTER TABLE
    #blocked
ADD blocking_desc AS
        ISNULL
        (
            '(' +
            CAST(blocking_spid AS varchar(10)) +
            ':' +
            CAST(blocking_ecid AS varchar(10)) +
            ')',
            'unresolved process'
        ) PERSISTED,
    blocked_desc AS
        '(' +
        CAST(blocked_spid AS varchar(10)) +
        ':' +
        CAST(blocked_ecid AS varchar(10)) +
        ')' PERSISTED;

IF @debug = 1
BEGIN
    RAISERROR('Adding indexes to to #blocked', 0, 1) WITH NOWAIT;
END;

CREATE CLUSTERED INDEX
    blocking
ON #blocked
    (monitor_loop, blocking_desc, blocked_desc);

CREATE INDEX
    blocked
ON #blocked
    (monitor_loop, blocked_desc, blocking_desc);

IF @debug = 1
BEGIN
    SELECT
        '#blocked' AS table_name,
        wa.*
    FROM #blocked AS wa
    OPTION(RECOMPILE);

    RAISERROR('Inserting to #blocking', 0, 1) WITH NOWAIT;
END;

SELECT
    event_time =
        DATEADD
        (
            MINUTE,
            DATEDIFF
            (
                MINUTE,
                GETUTCDATE(),
                SYSDATETIME()
            ),
            c.value('@timestamp', 'datetime2')
        ),
    database_name = DB_NAME(c.value('(data[@name="database_id"]/value/text())[1]', 'integer')),
    database_id = c.value('(data[@name="database_id"]/value/text())[1]', 'integer'),
    object_id = c.value('(data[@name="object_id"]/value/text())[1]', 'integer'),
    transaction_id = c.value('(data[@name="transaction_id"]/value/text())[1]', 'bigint'),
    resource_owner_type = c.value('(data[@name="resource_owner_type"]/text)[1]', 'nvarchar(256)'),
    monitor_loop = c.value('(//@monitorLoop)[1]', 'integer'),
    blocking_spid = bg.value('(process/@spid)[1]', 'integer'),
    blocking_ecid = bg.value('(process/@ecid)[1]', 'integer'),
    blocked_spid = bd.value('(process/@spid)[1]', 'integer'),
    blocked_ecid = bd.value('(process/@ecid)[1]', 'integer'),
    query_text_pre = bg.value('(process/inputbuf/text())[1]', 'nvarchar(max)'),
    wait_time = bg.value('(process/@waittime)[1]', 'bigint'),
    transaction_name = bg.value('(process/@transactionname)[1]', 'nvarchar(1024)'),
    last_transaction_started = bg.value('(process/@lastbatchstarted)[1]', 'datetime2'),
    last_transaction_completed = bg.value('(process/@lastbatchcompleted)[1]', 'datetime2'),
    wait_resource = bg.value('(process/@waitresource)[1]', 'nvarchar(1024)'),
    lock_mode = bg.value('(process/@lockMode)[1]', 'nvarchar(10)'),
    status = bg.value('(process/@status)[1]', 'nvarchar(10)'),
    priority = bg.value('(process/@priority)[1]', 'integer'),
    transaction_count = bg.value('(process/@trancount)[1]', 'integer'),
    client_app = bg.value('(process/@clientapp)[1]', 'nvarchar(256)'),
    host_name = bg.value('(process/@hostname)[1]', 'nvarchar(256)'),
    login_name = bg.value('(process/@loginname)[1]', 'nvarchar(256)'),
    isolation_level = bg.value('(process/@isolationlevel)[1]', 'nvarchar(50)'),
    log_used = bg.value('(process/@logused)[1]', 'bigint'),
    clientoption1 = bg.value('(process/@clientoption1)[1]', 'bigint'),
    clientoption2 = bg.value('(process/@clientoption1)[1]', 'bigint'),
    currentdbname = bg.value('(process/@currentdbname)[1]', 'nvarchar(128)'),
    currentdbid = bg.value('(process/@currentdb)[1]', 'integer'),
    blocking_level = 0,
    sort_order = CAST('' AS varchar(400)),
    activity = CASE WHEN oa.c.exist('//blocked-process-report/blocking-process') = 1 THEN 'blocking' END,
    blocked_process_report = c.query('.')
INTO #blocking
FROM #blocking_xml AS bx
OUTER APPLY bx.human_events_xml.nodes('/event') AS oa(c)
OUTER APPLY oa.c.nodes('//blocked-process-report/blocked-process') AS bd(bd)
OUTER APPLY oa.c.nodes('//blocked-process-report/blocking-process') AS bg(bg)
OPTION(RECOMPILE);

IF @debug = 1
BEGIN
    RAISERROR('Adding query_text to to #blocking', 0, 1) WITH NOWAIT;
END;

ALTER TABLE
    #blocking
ADD query_text AS
   REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
   REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
   REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
       query_text_pre COLLATE Latin1_General_BIN2,
   NCHAR(31),N'?'),NCHAR(30),N'?'),NCHAR(29),N'?'),NCHAR(28),N'?'),NCHAR(27),N'?'),NCHAR(26),N'?'),NCHAR(25),N'?'),NCHAR(24),N'?'),NCHAR(23),N'?'),NCHAR(22),N'?'),
   NCHAR(21),N'?'),NCHAR(20),N'?'),NCHAR(19),N'?'),NCHAR(18),N'?'),NCHAR(17),N'?'),NCHAR(16),N'?'),NCHAR(15),N'?'),NCHAR(14),N'?'),NCHAR(12),N'?'),
   NCHAR(11),N'?'),NCHAR(8),N'?'),NCHAR(7),N'?'),NCHAR(6),N'?'),NCHAR(5),N'?'),NCHAR(4),N'?'),NCHAR(3),N'?'),NCHAR(2),N'?'),NCHAR(1),N'?'),NCHAR(0),N'?')
PERSISTED;

IF @debug = 1
BEGIN
    RAISERROR('Adding blocking_desc to to #blocking', 0, 1) WITH NOWAIT;
END;

ALTER TABLE
    #blocking
ADD blocking_desc AS
        ISNULL
        (
            '(' +
            CAST(blocking_spid AS varchar(10)) +
            ':' +
            CAST(blocking_ecid AS varchar(10)) +
            ')',
            'unresolved process'
        ) PERSISTED,
    blocked_desc AS
        '(' +
        CAST(blocked_spid AS varchar(10)) +
        ':' +
        CAST(blocked_ecid AS varchar(10)) +
        ')' PERSISTED;

IF @debug = 1
BEGIN
    RAISERROR('Creating indexes on #blocking', 0, 1) WITH NOWAIT;
END;

CREATE CLUSTERED INDEX
    blocking
ON #blocking
    (monitor_loop, blocking_desc, blocked_desc);

CREATE INDEX
    blocked
ON #blocking
    (monitor_loop, blocked_desc, blocking_desc);

IF @debug = 1
BEGIN
    SELECT
        '#blocking' AS table_name,
        wa.*
    FROM #blocking AS wa
    OPTION(RECOMPILE);

    RAISERROR('Updating #blocked', 0, 1) WITH NOWAIT;
END;

WITH
    hierarchy AS
(
    SELECT
        b.monitor_loop,
        blocking_desc,
        blocked_desc,
        level = 0,
        sort_order =
            CAST
            (
                blocking_desc +
                ' </* ' +
                blocked_desc AS varchar(400)
            )
    FROM #blocking AS b
    WHERE NOT EXISTS
    (
        SELECT
            1/0
        FROM #blocking AS b2
        WHERE b2.monitor_loop = b.monitor_loop
        AND   b2.blocked_desc = b.blocking_desc
    )

    UNION ALL

    SELECT
        bg.monitor_loop,
        bg.blocking_desc,
        bg.blocked_desc,
        h.level + 1,
        sort_order =
            CAST
            (
                h.sort_order +
                ' ' +
                bg.blocking_desc +
                ' </* ' +
                bg.blocked_desc AS varchar(400)
            )
    FROM hierarchy AS h
    JOIN #blocking AS bg
      ON  bg.monitor_loop = h.monitor_loop
      AND bg.blocking_desc = h.blocked_desc
)
UPDATE
    #blocked
SET
    blocking_level = h.level,
    sort_order = h.sort_order
FROM #blocked AS b
JOIN hierarchy AS h
  ON  h.monitor_loop = b.monitor_loop
  AND h.blocking_desc = b.blocking_desc
  AND h.blocked_desc = b.blocked_desc
OPTION(RECOMPILE, MAXRECURSION 0);

IF @debug = 1
BEGIN
    RAISERROR('Updating #blocking', 0, 1) WITH NOWAIT;
END;

UPDATE
    #blocking
SET
    blocking_level = bd.blocking_level,
    sort_order = bd.sort_order
FROM #blocking AS bg
JOIN #blocked AS bd
  ON  bd.monitor_loop = bg.monitor_loop
  AND bd.blocking_desc = bg.blocking_desc
  AND bd.blocked_desc = bg.blocked_desc
OPTION(RECOMPILE);

IF @debug = 1
BEGIN
    RAISERROR('Inserting #blocks', 0, 1) WITH NOWAIT;
END;

SELECT
    kheb.event_time,
    kheb.database_name,
    kheb.object_id,
    contentious_object = CONVERT(nvarchar(4000), NULL),
    kheb.activity,
    blocking_tree =
        REPLICATE(' > ', kheb.blocking_level) +
        CASE kheb.activity
             WHEN 'blocking'
             THEN '(' + kheb.blocking_desc + ') is blocking (' + kheb.blocked_desc + ')'
             ELSE ' > (' + kheb.blocked_desc + ') is blocked by (' + kheb.blocking_desc + ')'
        END,
    spid =
        CASE kheb.activity
             WHEN 'blocking'
             THEN kheb.blocking_spid
             ELSE kheb.blocked_spid
        END,
    ecid =
        CASE kheb.activity
             WHEN 'blocking'
             THEN kheb.blocking_ecid
             ELSE kheb.blocked_ecid
        END,
    query_text =
        CONVERT(xml, NULL),
    query_text_pre = kheb.query_text,
    wait_time_ms =
        kheb.wait_time,
    kheb.status,
    kheb.isolation_level,
    kheb.lock_mode,
    kheb.resource_owner_type,
    kheb.transaction_count,
    kheb.transaction_name,
    kheb.last_transaction_started,
    kheb.last_transaction_completed,
    client_option_1 =
        SUBSTRING
        (
            CASE WHEN kheb.clientoption1 & 1 = 1 THEN ', DISABLE_DEF_CNST_CHECK' ELSE '' END +
            CASE WHEN kheb.clientoption1 & 2 = 2 THEN ', IMPLICIT_TRANSACTIONS' ELSE '' END +
            CASE WHEN kheb.clientoption1 & 4 = 4 THEN ', CURSOR_CLOSE_ON_COMMIT' ELSE '' END +
            CASE WHEN kheb.clientoption1 & 8 = 8 THEN ', ANSI_WARNINGS' ELSE '' END +
            CASE WHEN kheb.clientoption1 & 16 = 16 THEN ', ANSI_PADDING' ELSE '' END +
            CASE WHEN kheb.clientoption1 & 32 = 32 THEN ', ANSI_NULLS' ELSE '' END +
            CASE WHEN kheb.clientoption1 & 64 = 64 THEN ', ARITHABORT' ELSE '' END +
            CASE WHEN kheb.clientoption1 & 128 = 128 THEN ', ARITHIGNORE' ELSE '' END +
            CASE WHEN kheb.clientoption1 & 256 = 256 THEN ', QUOTED_IDENTIFIER' ELSE '' END +
            CASE WHEN kheb.clientoption1 & 512 = 512 THEN ', NOCOUNT' ELSE '' END +
            CASE WHEN kheb.clientoption1 & 1024 = 1024 THEN ', ANSI_NULL_DFLT_ON' ELSE '' END +
            CASE WHEN kheb.clientoption1 & 2048 = 2048 THEN ', ANSI_NULL_DFLT_OFF' ELSE '' END +
            CASE WHEN kheb.clientoption1 & 4096 = 4096 THEN ', CONCAT_NULL_YIELDS_NULL' ELSE '' END +
            CASE WHEN kheb.clientoption1 & 8192 = 8192 THEN ', NUMERIC_ROUNDABORT' ELSE '' END +
            CASE WHEN kheb.clientoption1 & 16384 = 16384 THEN ', XACT_ABORT' ELSE '' END,
            3,
            8000
        ),
    client_option_2 =
        SUBSTRING
        (
            CASE WHEN kheb.clientoption2 & 1024 = 1024 THEN ', DB CHAINING' ELSE '' END +
            CASE WHEN kheb.clientoption2 & 2048 = 2048 THEN ', NUMERIC ROUNDABORT' ELSE '' END +
            CASE WHEN kheb.clientoption2 & 4096 = 4096 THEN ', ARITHABORT' ELSE '' END +
            CASE WHEN kheb.clientoption2 & 8192 = 8192 THEN ', ANSI PADDING' ELSE '' END +
            CASE WHEN kheb.clientoption2 & 16384 = 16384 THEN ', ANSI NULL DEFAULT' ELSE '' END +
            CASE WHEN kheb.clientoption2 & 65536 = 65536 THEN ', CONCAT NULL YIELDS NULL' ELSE '' END +
            CASE WHEN kheb.clientoption2 & 131072 = 131072 THEN ', RECURSIVE TRIGGERS' ELSE '' END +
            CASE WHEN kheb.clientoption2 & 1048576 = 1048576 THEN ', DEFAULT TO LOCAL CURSOR' ELSE '' END +
            CASE WHEN kheb.clientoption2 & 8388608 = 8388608 THEN ', QUOTED IDENTIFIER' ELSE '' END +
            CASE WHEN kheb.clientoption2 & 16777216 = 16777216 THEN ', AUTO CREATE STATISTICS' ELSE '' END +
            CASE WHEN kheb.clientoption2 & 33554432 = 33554432 THEN ', CURSOR CLOSE ON COMMIT' ELSE '' END +
            CASE WHEN kheb.clientoption2 & 67108864 = 67108864 THEN ', ANSI NULLS' ELSE '' END +
            CASE WHEN kheb.clientoption2 & 268435456 = 268435456 THEN ', ANSI WARNINGS' ELSE '' END +
            CASE WHEN kheb.clientoption2 & 536870912 = 536870912 THEN ', FULL TEXT ENABLED' ELSE '' END +
            CASE WHEN kheb.clientoption2 & 1073741824 = 1073741824 THEN ', AUTO UPDATE STATISTICS' ELSE '' END +
            CASE WHEN kheb.clientoption2 & 1469283328 = 1469283328 THEN ', ALL SETTABLE OPTIONS' ELSE '' END,
            3,
            8000
        ),
    kheb.wait_resource,
    kheb.priority,
    kheb.log_used,
    kheb.client_app,
    kheb.host_name,
    kheb.login_name,
    kheb.transaction_id,
    kheb.database_id,
    kheb.currentdbname,
    kheb.currentdbid,
    kheb.blocked_process_report,
    kheb.sort_order
INTO #blocks
FROM
(
    SELECT
        bg.*
    FROM #blocking AS bg
    WHERE
    (
         @database_name IS NULL
      OR bg.database_name = @database_name
      OR bg.currentdbname = @database_name
    )

    UNION ALL

    SELECT
        bd.*
    FROM #blocked AS bd
    WHERE
    (
         @database_name IS NULL
      OR bd.database_name = @database_name
      OR bd.currentdbname = @database_name
    )
) AS kheb
OPTION(RECOMPILE);

IF @debug = 1
BEGIN
    RAISERROR('Updating #blocks query_text column', 0, 1) WITH NOWAIT;
END;

UPDATE
    kheb
SET
    kheb.query_text = qt.query_text
FROM #blocks AS kheb
CROSS APPLY
(
    SELECT
        query_text =
        CASE
            WHEN kheb.query_text_pre LIKE @inputbuf_bom + N'Proc |[Database Id = %' ESCAPE N'|'
            THEN
                (
                    SELECT
                        [processing-instruction(query)] =
                            OBJECT_SCHEMA_NAME
                            (
                                    SUBSTRING
                                    (
                                        kheb.query_text_pre,
                                        CHARINDEX(N'Object Id = ', kheb.query_text_pre) + 12,
                                        LEN(kheb.query_text_pre) - (CHARINDEX(N'Object Id = ', kheb.query_text_pre) + 12)
                                    )
                                    ,
                                    SUBSTRING
                                    (
                                        kheb.query_text_pre,
                                        CHARINDEX(N'Database Id = ', kheb.query_text_pre) + 14,
                                        CHARINDEX(N'Object Id', kheb.query_text_pre) - (CHARINDEX(N'Database Id = ', kheb.query_text_pre) + 14)
                                    )
                            ) +
                            N'.' +
                            OBJECT_NAME
                            (
                                 SUBSTRING
                                 (
                                     kheb.query_text_pre,
                                     CHARINDEX(N'Object Id = ', kheb.query_text_pre) + 12,
                                     LEN(kheb.query_text_pre) - (CHARINDEX(N'Object Id = ', kheb.query_text_pre) + 12)
                                 )
                                 ,
                                 SUBSTRING
                                 (
                                     kheb.query_text_pre,
                                     CHARINDEX(N'Database Id = ', kheb.query_text_pre) + 14,
                                     CHARINDEX(N'Object Id', kheb.query_text_pre) - (CHARINDEX(N'Database Id = ', kheb.query_text_pre) + 14)
                                 )
                            )
                    FOR XML
                        PATH(N''),
                        TYPE
                )
            ELSE
                (
                    SELECT
                        [processing-instruction(query)] =
                            kheb.query_text_pre
                    FOR XML
                        PATH(N''),
                        TYPE
                )
        END
) AS qt
OPTION(RECOMPILE);

IF @debug = 1
BEGIN
    RAISERROR('Updating #blocks contentious_object column', 0, 1) WITH NOWAIT;
END;

UPDATE
    b
SET
    b.contentious_object =
    ISNULL
    (
        co.contentious_object,
        N'Unresolved: ' +
        N'database: ' +
        b.database_name +
        N' object_id: ' +
        RTRIM(b.object_id)
    )
FROM #blocks AS b
CROSS APPLY
(
    SELECT
        contentious_object =
            OBJECT_SCHEMA_NAME
            (
                b.object_id,
                b.database_id
            ) +
            N'.' +
            OBJECT_NAME
            (
                b.object_id,
                b.database_id
            )
) AS co
OPTION(RECOMPILE);

/*Either return results or log to a table*/
SET @dsql = N'
SELECT
    blocked_process_report =
        ''blocked_process_report'',
    b.event_time,
    b.database_name,
    b.currentdbname,
    b.contentious_object,
    b.activity,
    b.blocking_tree,
    b.spid,
    b.ecid,
    b.query_text,
    b.wait_time_ms,
    b.status,
    b.isolation_level,
    b.lock_mode,
    b.resource_owner_type,
    b.transaction_count,
    b.transaction_name,
    b.last_transaction_started,
    b.last_transaction_completed,
    b.client_option_1,
    b.client_option_2,
    b.wait_resource,
    b.priority,
    b.log_used,
    b.client_app,
    b.host_name,
    b.login_name,
    b.transaction_id,
    blocked_process_report_xml =
        b.blocked_process_report
FROM
(
    SELECT
        b.*,
        n =
            ROW_NUMBER() OVER
            (
                PARTITION BY
                    b.transaction_id,
                    b.spid,
                    b.ecid
                ORDER BY
                    b.event_time DESC
            )
    FROM #blocks AS b
) AS b
WHERE b.n = 1
AND  (b.contentious_object = @object_name
      OR @object_name IS NULL)';

/* Add the WHERE clause only for table logging */
IF @log_to_table = 1
BEGIN
    SET @mdsql =
        REPLACE
        (
            REPLACE
            (
                @mdsql,
                '{table_check}',
                @log_table_blocking
            ),
            '{date_column}',
            'event_time'
        );

    IF @debug = 1 BEGIN PRINT @mdsql; END;

    EXECUTE sys.sp_executesql
        @mdsql,
      N'@max_event_time datetime2(7) OUTPUT',
        @max_event_time OUTPUT;

    SET @mdsql =
        REPLACE
        (
            REPLACE
            (
                @mdsql,
                @log_table_blocking,
                '{table_check}'
            ),
            'event_time',
            '{date_column}'
        );

    SET @dsql += N'
AND   b.event_time > @max_event_time';
END;

/* Add the ORDER BY clause */
SET @dsql += N'
ORDER BY
    b.event_time,
    b.sort_order,
    CASE
        WHEN b.activity = ''blocking''
        THEN -1
        ELSE +1
    END
OPTION(RECOMPILE);';

/* Handle table logging */
IF @log_to_table = 1
BEGIN
    SET @insert_sql = N'
INSERT INTO
    ' + @log_table_blocking + N'
(
    blocked_process_report,
    event_time,
    database_name,
    currentdbname,
    contentious_object,
    activity,
    blocking_tree,
    spid,
    ecid,
    query_text,
    wait_time_ms,
    status,
    isolation_level,
    lock_mode,
    resource_owner_type,
    transaction_count,
    transaction_name,
    last_transaction_started,
    last_transaction_completed,
    client_option_1,
    client_option_2,
    wait_resource,
    priority,
    log_used,
    client_app,
    host_name,
    login_name,
    transaction_id,
    blocked_process_report_xml
)' +
    @dsql;

    IF @debug = 1 BEGIN PRINT @insert_sql; END;

    EXECUTE sys.sp_executesql
        @insert_sql,
      N'@max_event_time datetime2(7),
        @object_name sysname',
        @max_event_time,
        @object_name;
END;

/* Execute the query for client results */
IF @log_to_table = 0
BEGIN

    IF @debug = 1 BEGIN PRINT @dsql; END;

    EXECUTE sys.sp_executesql
        @dsql,
      N'@object_name sysname',
        @object_name;
END;

/*
Only run query plan and check stuff
when not logging to a table
*/
IF @log_to_table = 0
BEGIN
    IF @debug = 1
    BEGIN
        RAISERROR('Inserting #available_plans', 0, 1) WITH NOWAIT;
    END;

    SELECT DISTINCT
        b.*
    INTO #available_plans
    FROM
    (
        SELECT
            available_plans =
                'available_plans',
            b.database_name,
            b.database_id,
            b.currentdbname,
            b.currentdbid,
            b.contentious_object,
            query_text =
                TRY_CAST(b.query_text AS nvarchar(max)),
            sql_handle =
                CONVERT(varbinary(64), n.c.value('@sqlhandle', 'varchar(130)'), 1),
            stmtstart =
                ISNULL(n.c.value('@stmtstart', 'integer'), 0),
            stmtend =
                ISNULL(n.c.value('@stmtend', 'integer'), -1)
        FROM #blocks AS b
        CROSS APPLY b.blocked_process_report.nodes('/event/data/value/blocked-process-report/blocking-process/process/executionStack/frame[not(@sqlhandle = "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")]') AS n(c)
        WHERE
        (
            (b.database_name = @database_name
                OR @database_name IS NULL)
         OR (b.currentdbname = @database_name
                OR @database_name IS NULL)
        )
        AND  (b.contentious_object = @object_name
                OR @object_name IS NULL)

        UNION ALL

        SELECT
            available_plans =
                'available_plans',
            b.database_name,
            b.database_id,
            b.currentdbname,
            b.currentdbid,
            b.contentious_object,
            query_text =
                TRY_CAST(b.query_text AS nvarchar(max)),
            sql_handle =
                CONVERT(varbinary(64), n.c.value('@sqlhandle', 'varchar(130)'), 1),
            stmtstart =
                ISNULL(n.c.value('@stmtstart', 'integer'), 0),
            stmtend =
                ISNULL(n.c.value('@stmtend', 'integer'), -1)
        FROM #blocks AS b
        CROSS APPLY b.blocked_process_report.nodes('/event/data/value/blocked-process-report/blocking-process/process/executionStack/frame[not(@sqlhandle = "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")]') AS n(c)
        WHERE
        (
            (b.database_name = @database_name
                OR @database_name IS NULL)
         OR (b.currentdbname = @database_name
                OR @database_name IS NULL)
        )
        AND  (b.contentious_object = @object_name
                OR @object_name IS NULL)
    ) AS b
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        SELECT
            '#available_plans' AS table_name,
            ap.*
        FROM #available_plans AS ap
        OPTION(RECOMPILE);

        RAISERROR('Inserting #dm_exec_query_stats', 0, 1) WITH NOWAIT;
    END;

    SELECT
        deqs.sql_handle,
        deqs.plan_handle,
        deqs.statement_start_offset,
        deqs.statement_end_offset,
        deqs.creation_time,
        deqs.last_execution_time,
        deqs.execution_count,
        total_worker_time_ms =
            deqs.total_worker_time / 1000.,
        avg_worker_time_ms =
            CONVERT(decimal(38, 6), deqs.total_worker_time / 1000. / deqs.execution_count),
        total_elapsed_time_ms =
            deqs.total_elapsed_time / 1000.,
        avg_elapsed_time_ms =
            CONVERT(decimal(38, 6), deqs.total_elapsed_time / 1000. / deqs.execution_count),
        executions_per_second =
            ISNULL
            (
                deqs.execution_count /
                    NULLIF
                    (
                        DATEDIFF
                        (
                            SECOND,
                            deqs.creation_time,
                            NULLIF(deqs.last_execution_time, '1900-01-01 00:00:00.000')
                        ),
                        0
                    ),
                    0
            ),
        total_physical_reads_mb =
            deqs.total_physical_reads * 8. / 1024.,
        total_logical_writes_mb =
            deqs.total_logical_writes * 8. / 1024.,
        total_logical_reads_mb =
            deqs.total_logical_reads * 8. / 1024.,
        min_grant_mb =
            deqs.min_grant_kb * 8. / 1024.,
        max_grant_mb =
            deqs.max_grant_kb * 8. / 1024.,
        min_used_grant_mb =
            deqs.min_used_grant_kb * 8. / 1024.,
        max_used_grant_mb =
            deqs.max_used_grant_kb * 8. / 1024.,
        deqs.min_reserved_threads,
        deqs.max_reserved_threads,
        deqs.min_used_threads,
        deqs.max_used_threads,
        deqs.total_rows,
        max_worker_time_ms =
            deqs.max_worker_time / 1000.,
        max_elapsed_time_ms =
            deqs.max_elapsed_time / 1000.
    INTO #dm_exec_query_stats
    FROM sys.dm_exec_query_stats AS deqs
    WHERE EXISTS
    (
       SELECT
           1/0
       FROM #available_plans AS ap
       WHERE ap.sql_handle = deqs.sql_handle
    )
    AND deqs.query_hash IS NOT NULL
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        RAISERROR('Creating index on #dm_exec_query_stats', 0, 1) WITH NOWAIT;
    END;

    CREATE CLUSTERED INDEX
        deqs
    ON #dm_exec_query_stats
    (
        sql_handle,
        plan_handle
    );

    SELECT
        ap.available_plans,
        ap.database_name,
        ap.currentdbname,
        query_text =
            TRY_CAST(ap.query_text AS xml),
        ap.query_plan,
        ap.creation_time,
        ap.last_execution_time,
        ap.execution_count,
        ap.executions_per_second,
        ap.total_worker_time_ms,
        ap.avg_worker_time_ms,
        ap.max_worker_time_ms,
        ap.total_elapsed_time_ms,
        ap.avg_elapsed_time_ms,
        ap.max_elapsed_time_ms,
        ap.total_logical_reads_mb,
        ap.total_physical_reads_mb,
        ap.total_logical_writes_mb,
        ap.min_grant_mb,
        ap.max_grant_mb,
        ap.min_used_grant_mb,
        ap.max_used_grant_mb,
        ap.min_reserved_threads,
        ap.max_reserved_threads,
        ap.min_used_threads,
        ap.max_used_threads,
        ap.total_rows,
        ap.sql_handle,
        ap.statement_start_offset,
        ap.statement_end_offset
    FROM
    (

        SELECT
            ap.*,
            c.statement_start_offset,
            c.statement_end_offset,
            c.creation_time,
            c.last_execution_time,
            c.execution_count,
            c.total_worker_time_ms,
            c.avg_worker_time_ms,
            c.total_elapsed_time_ms,
            c.avg_elapsed_time_ms,
            c.executions_per_second,
            c.total_physical_reads_mb,
            c.total_logical_writes_mb,
            c.total_logical_reads_mb,
            c.min_grant_mb,
            c.max_grant_mb,
            c.min_used_grant_mb,
            c.max_used_grant_mb,
            c.min_reserved_threads,
            c.max_reserved_threads,
            c.min_used_threads,
            c.max_used_threads,
            c.total_rows,
            c.query_plan,
            c.max_worker_time_ms,
            c.max_elapsed_time_ms
        FROM #available_plans AS ap
        OUTER APPLY
        (
            SELECT
                deqs.*,
                query_plan =
                    TRY_CAST(deps.query_plan AS xml)
            FROM #dm_exec_query_stats deqs
            OUTER APPLY sys.dm_exec_text_query_plan
            (
                deqs.plan_handle,
                deqs.statement_start_offset,
                deqs.statement_end_offset
            ) AS deps
            WHERE deqs.sql_handle = ap.sql_handle
            AND   deps.dbid IN (ap.database_id, ap.currentdbid)
        ) AS c
    ) AS ap
    WHERE ap.query_plan IS NOT NULL
    ORDER BY
        ap.avg_worker_time_ms DESC
    OPTION(RECOMPILE, LOOP JOIN, HASH JOIN);

    IF @debug = 1
    BEGIN
        RAISERROR('Inserting #block_findings, check_id -1', 0, 1) WITH NOWAIT;
    END;

    INSERT
        #block_findings
    (
        check_id,
        database_name,
        object_name,
        finding_group,
        finding,
        sort_order
    )
    SELECT
        check_id = -1,
        database_name = N'erikdarling.com',
        object_name = N'sp_HumanEventsBlockViewer version ' + CONVERT(nvarchar(30), @version) + N'.',
        finding_group = N'https://code.erikdarling.com',
        finding = N'blocking for period ' + CONVERT(nvarchar(30), @start_date_original, 126) + N' through ' + CONVERT(nvarchar(30), @end_date_original, 126) + N'.',
        1;

    IF @debug = 1
    BEGIN
        RAISERROR('Inserting #block_findings, check_id 1', 0, 1) WITH NOWAIT;
    END;

    INSERT
        #block_findings
    (
        check_id,
        database_name,
        object_name,
        finding_group,
        finding,
        sort_order
    )
    SELECT
        check_id =
            1,
        database_name =
            b.database_name,
        object_name =
            N'-',
        finding_group =
            N'Database Locks',
        finding =
            N'The database ' +
            b.database_name +
            N' has been involved in ' +
            CONVERT(nvarchar(20), COUNT_BIG(DISTINCT b.transaction_id)) +
            N' blocking sessions.',
       sort_order =
           ROW_NUMBER() OVER (ORDER BY COUNT_BIG(DISTINCT b.transaction_id) DESC)
    FROM #blocks AS b
    WHERE (b.database_name = @database_name
           OR @database_name IS NULL)
    AND   (b.contentious_object = @object_name
           OR @object_name IS NULL)
    GROUP BY
        b.database_name
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        RAISERROR('Inserting #block_findings, check_id 2', 0, 1) WITH NOWAIT;
    END;

    INSERT
        #block_findings
    (
        check_id,
        database_name,
        object_name,
        finding_group,
        finding,
        sort_order
    )
    SELECT
        check_id =
            2,
        database_name =
            b.database_name,
        object_name =
            b.contentious_object,
        finding_group =
            N'Object Locks',
        finding =
            N'The object ' +
            b.contentious_object +
            CASE
                WHEN b.contentious_object LIKE N'Unresolved%'
                THEN N''
                ELSE N' in database ' +
                     b.database_name
            END +
            N' has been involved in ' +
            CONVERT(nvarchar(20), COUNT_BIG(DISTINCT b.transaction_id)) +
            N' blocking sessions.',
       sort_order =
           ROW_NUMBER() OVER (ORDER BY COUNT_BIG(DISTINCT b.transaction_id) DESC)
    FROM #blocks AS b
    WHERE (b.database_name = @database_name
           OR @database_name IS NULL)
    AND   (b.contentious_object = @object_name
           OR @object_name IS NULL)
    GROUP BY
        b.database_name,
        b.contentious_object
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        RAISERROR('Inserting #block_findings, check_id 3', 0, 1) WITH NOWAIT;
    END;

    INSERT
        #block_findings
    (
        check_id,
        database_name,
        object_name,
        finding_group,
        finding,
        sort_order
    )
    SELECT
        check_id =
            3,
        database_name =
            b.database_name,
        object_name =
            CASE
                WHEN EXISTS
                     (
                         SELECT
                             1/0
                         FROM sys.databases AS d
                         WHERE d.name COLLATE DATABASE_DEFAULT = b.database_name COLLATE DATABASE_DEFAULT
                         AND   d.is_read_committed_snapshot_on = 1
                     )
                THEN N'You already enabled RCSI, but...'
                ELSE N'You Might Need RCSI'
            END,
        finding_group =
            N'Blocking Involving Selects',
        finding =
            N'There have been ' +
            CONVERT(nvarchar(20), COUNT_BIG(DISTINCT b.transaction_id)) +
            N' select queries involved in blocking sessions in ' +
            b.database_name +
            N'.',
       sort_order =
           ROW_NUMBER() OVER (ORDER BY COUNT_BIG(DISTINCT b.transaction_id) DESC)
    FROM #blocks AS b
    WHERE b.lock_mode IN
          (
              N'S',
              N'IS'
          )
    AND   (b.database_name = @database_name
           OR @database_name IS NULL)
    AND   (b.contentious_object = @object_name
           OR @object_name IS NULL)
    GROUP BY
        b.database_name
    HAVING
        COUNT_BIG(DISTINCT b.transaction_id) > 1
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        RAISERROR('Inserting #block_findings, check_id 4', 0, 1) WITH NOWAIT;
    END;

    INSERT
        #block_findings
    (
        check_id,
        database_name,
        object_name,
        finding_group,
        finding,
        sort_order
    )
    SELECT
        check_id =
            4,
        database_name =
            b.database_name,
        object_name =
            N'-',
        finding_group =
            N'Repeatable Read Blocking',
        finding =
            N'There have been ' +
            CONVERT(nvarchar(20), COUNT_BIG(DISTINCT b.transaction_id)) +
            N' repeatable read queries involved in blocking sessions in ' +
            b.database_name +
            N'.',
       sort_order =
           ROW_NUMBER() OVER (ORDER BY COUNT_BIG(DISTINCT b.transaction_id) DESC)
    FROM #blocks AS b
    WHERE b.isolation_level LIKE N'repeatable%'
    AND   (b.database_name = @database_name
           OR @database_name IS NULL)
    AND   (b.contentious_object = @object_name
           OR @object_name IS NULL)
    GROUP BY
        b.database_name
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        RAISERROR('Inserting #block_findings, check_id 5', 0, 1) WITH NOWAIT;
    END;

    INSERT
        #block_findings
    (
        check_id,
        database_name,
        object_name,
        finding_group,
        finding,
        sort_order
    )
    SELECT
        check_id =
            5,
        database_name =
            b.database_name,
        object_name =
            N'-',
        finding_group =
            N'Serializable Blocking',
        finding =
            N'There have been ' +
            CONVERT(nvarchar(20), COUNT_BIG(DISTINCT b.transaction_id)) +
            N' serializable queries involved in blocking sessions in ' +
            b.database_name +
            N'.',
       sort_order =
           ROW_NUMBER() OVER (ORDER BY COUNT_BIG(DISTINCT b.transaction_id) DESC)
    FROM #blocks AS b
    WHERE b.isolation_level LIKE N'serializable%'
    AND   (b.database_name = @database_name
           OR @database_name IS NULL)
    AND   (b.contentious_object = @object_name
           OR @object_name IS NULL)
    GROUP BY
        b.database_name
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        RAISERROR('Inserting #block_findings, check_id 6.1', 0, 1) WITH NOWAIT;
    END;

    INSERT
        #block_findings
    (
        check_id,
        database_name,
        object_name,
        finding_group,
        finding,
        sort_order
    )
    SELECT
        check_id =
            6,
        database_name =
            b.database_name,
        object_name =
            N'-',
        finding_group =
            N'Sleeping Query Blocking',
        finding =
            N'There have been ' +
            CONVERT(nvarchar(20), COUNT_BIG(DISTINCT b.transaction_id)) +
            N' sleeping queries involved in blocking sessions in ' +
            b.database_name +
            N'.',
       sort_order =
           ROW_NUMBER() OVER (ORDER BY COUNT_BIG(DISTINCT b.transaction_id) DESC)
    FROM #blocks AS b
    WHERE b.status = N'sleeping'
    AND   (b.database_name = @database_name
           OR @database_name IS NULL)
    AND   (b.contentious_object = @object_name
           OR @object_name IS NULL)
    GROUP BY
        b.database_name
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        RAISERROR('Inserting #block_findings, check_id 6.2', 0, 1) WITH NOWAIT;
    END;

    INSERT
        #block_findings
    (
        check_id,
        database_name,
        object_name,
        finding_group,
        finding,
        sort_order
    )
    SELECT
        check_id =
            6,
        database_name =
            b.database_name,
        object_name =
            N'-',
        finding_group =
            N'Background Query Blocking',
        finding =
            N'There have been ' +
            CONVERT(nvarchar(20), COUNT_BIG(DISTINCT b.transaction_id)) +
            N' background tasks involved in blocking sessions in ' +
            b.database_name +
            N'.',
       sort_order =
           ROW_NUMBER() OVER (ORDER BY COUNT_BIG(DISTINCT b.transaction_id) DESC)
    FROM #blocks AS b
    WHERE b.status = N'background'
    AND   (b.database_name = @database_name
           OR @database_name IS NULL)
    AND   (b.contentious_object = @object_name
           OR @object_name IS NULL)
    GROUP BY
        b.database_name
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        RAISERROR('Inserting #block_findings, check_id 6.3', 0, 1) WITH NOWAIT;
    END;

    INSERT
        #block_findings
    (
        check_id,
        database_name,
        object_name,
        finding_group,
        finding,
        sort_order
    )
    SELECT
        check_id =
            6,
        database_name =
            b.database_name,
        object_name =
            N'-',
        finding_group =
            N'Done Query Blocking',
        finding =
            N'There have been ' +
            CONVERT(nvarchar(20), COUNT_BIG(DISTINCT b.transaction_id)) +
            N' background tasks involved in blocking sessions in ' +
            b.database_name +
            N'.',
       sort_order =
           ROW_NUMBER() OVER (ORDER BY COUNT_BIG(DISTINCT b.transaction_id) DESC)
    FROM #blocks AS b
    WHERE b.status = N'done'
    AND   (b.database_name = @database_name
           OR @database_name IS NULL)
    AND   (b.contentious_object = @object_name
           OR @object_name IS NULL)
    GROUP BY
        b.database_name
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        RAISERROR('Inserting #block_findings, check_id 6.4', 0, 1) WITH NOWAIT;
    END;

    INSERT
        #block_findings
    (
        check_id,
        database_name,
        object_name,
        finding_group,
        finding,
        sort_order
    )
    SELECT
        check_id =
            6,
        database_name =
            b.database_name,
        object_name =
            N'-',
        finding_group =
            N'Compile Lock Blocking',
        finding =
            N'There have been ' +
            CONVERT(nvarchar(20), COUNT_BIG(DISTINCT b.transaction_id)) +
            N' compile locks blocking sessions in ' +
            b.database_name +
            N'.',
       sort_order =
           ROW_NUMBER() OVER (ORDER BY COUNT_BIG(DISTINCT b.transaction_id) DESC)
    FROM #blocks AS b
    WHERE b.wait_resource LIKE N'%COMPILE%'
    AND   (b.database_name = @database_name
           OR @database_name IS NULL)
    AND   (b.contentious_object = @object_name
           OR @object_name IS NULL)
    GROUP BY
        b.database_name
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        RAISERROR('Inserting #block_findings, check_id 6.5', 0, 1) WITH NOWAIT;
    END;

    INSERT
        #block_findings
    (
        check_id,
        database_name,
        object_name,
        finding_group,
        finding,
        sort_order
    )
    SELECT
        check_id =
            6,
        database_name =
            b.database_name,
        object_name =
            N'-',
        finding_group =
            N'Application Lock Blocking',
        finding =
            N'There have been ' +
            CONVERT(nvarchar(20), COUNT_BIG(DISTINCT b.transaction_id)) +
            N' application locks blocking sessions in ' +
            b.database_name +
            N'.',
       sort_order =
           ROW_NUMBER() OVER (ORDER BY COUNT_BIG(DISTINCT b.transaction_id) DESC)
    FROM #blocks AS b
    WHERE b.wait_resource LIKE N'APPLICATION%'
    AND   (b.database_name = @database_name
           OR @database_name IS NULL)
    AND   (b.contentious_object = @object_name
           OR @object_name IS NULL)
    GROUP BY
        b.database_name
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        RAISERROR('Inserting #block_findings, check_id 7.1', 0, 1) WITH NOWAIT;
    END;

    INSERT
        #block_findings
    (
        check_id,
        database_name,
        object_name,
        finding_group,
        finding,
        sort_order
    )
    SELECT
        check_id =
            7,
        database_name =
            b.database_name,
        object_name =
            N'-',
        finding_group =
            N'Implicit Transaction Blocking',
        finding =
            N'There have been ' +
            CONVERT(nvarchar(20), COUNT_BIG(DISTINCT b.transaction_id)) +
            N' implicit transaction queries involved in blocking sessions in ' +
            b.database_name +
            N'.',
       sort_order =
           ROW_NUMBER() OVER (ORDER BY COUNT_BIG(DISTINCT b.transaction_id) DESC)
    FROM #blocks AS b
    WHERE b.transaction_name = N'implicit_transaction'
    AND   (b.database_name = @database_name
           OR @database_name IS NULL)
    AND   (b.contentious_object = @object_name
           OR @object_name IS NULL)
    GROUP BY
        b.database_name
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        RAISERROR('Inserting #block_findings, check_id 7.2', 0, 1) WITH NOWAIT;
    END;

    INSERT
        #block_findings
    (
        check_id,
        database_name,
        object_name,
        finding_group,
        finding,
        sort_order
    )
    SELECT
        check_id =
            7,
        database_name =
            b.database_name,
        object_name =
            N'-',
        finding_group =
            N'User Transaction Blocking',
        finding =
            N'There have been ' +
            CONVERT(nvarchar(20), COUNT_BIG(DISTINCT b.transaction_id)) +
            N' user transaction queries involved in blocking sessions in ' +
            b.database_name +
            N'.',
       sort_order =
           ROW_NUMBER() OVER (ORDER BY COUNT_BIG(DISTINCT b.transaction_id) DESC)
    FROM #blocks AS b
    WHERE b.transaction_name = N'user_transaction'
    AND   (b.database_name = @database_name
           OR @database_name IS NULL)
    AND   (b.contentious_object = @object_name
           OR @object_name IS NULL)
    GROUP BY
        b.database_name
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        RAISERROR('Inserting #block_findings, check_id 7.3', 0, 1) WITH NOWAIT;
    END;

    INSERT
        #block_findings
    (
        check_id,
        database_name,
        object_name,
        finding_group,
        finding,
        sort_order
    )
    SELECT
        check_id =
            7,
        database_name =
            b.database_name,
        object_name =
            N'-',
        finding_group =
            N'Auto-Stats Update Blocking',
        finding =
            N'There have been ' +
            CONVERT(nvarchar(20), COUNT_BIG(DISTINCT b.transaction_id)) +
            N' auto stats updates involved in blocking sessions in ' +
            b.database_name +
            N'.',
       sort_order =
           ROW_NUMBER() OVER (ORDER BY COUNT_BIG(DISTINCT b.transaction_id) DESC)
    FROM #blocks AS b
    WHERE b.transaction_name = N'sqlsource_transform'
    AND   (b.database_name = @database_name
           OR @database_name IS NULL)
    AND   (b.contentious_object = @object_name
           OR @object_name IS NULL)
    GROUP BY
        b.database_name
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        RAISERROR('Inserting #block_findings, check_id 8', 0, 1) WITH NOWAIT;
    END;

    INSERT
        #block_findings
    (
        check_id,
        database_name,
        object_name,
        finding_group,
        finding,
        sort_order
    )
    SELECT
        check_id = 8,
        b.database_name,
        object_name = N'-',
        finding_group = N'Login, App, and Host blocking',
        finding =
            N'This database has had ' +
            CONVERT
            (
                nvarchar(20),
                COUNT_BIG(DISTINCT b.transaction_id)
            ) +
            N' instances of blocking involving the login ' +
            ISNULL
            (
                b.login_name,
                N'UNKNOWN'
            ) +
            N' from the application ' +
            ISNULL
            (
                b.client_app,
                N'UNKNOWN'
            ) +
            N' on host ' +
            ISNULL
            (
                b.host_name,
                N'UNKNOWN'
            ) +
            N'.',
       sort_order =
           ROW_NUMBER() OVER (ORDER BY COUNT_BIG(DISTINCT b.transaction_id) DESC)
    FROM #blocks AS b
    WHERE (b.database_name = @database_name
           OR @database_name IS NULL)
    AND   (b.contentious_object = @object_name
           OR @object_name IS NULL)
    GROUP BY
        b.database_name,
        b.login_name,
        b.client_app,
        b.host_name
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        RAISERROR('Inserting #block_findings, check_id 1000', 0, 1) WITH NOWAIT;
    END;

    WITH
        b AS
    (
        SELECT
            b.database_name,
            b.transaction_id,
            wait_time_ms =
                MAX(b.wait_time_ms)
        FROM #blocks AS b
        WHERE (b.database_name = @database_name
               OR @database_name IS NULL)
        AND   (b.contentious_object = @object_name
               OR @object_name IS NULL)
        GROUP BY
            b.database_name,
            b.transaction_id
    )
    INSERT
        #block_findings
    (
        check_id,
        database_name,
        object_name,
        finding_group,
        finding,
        sort_order
    )
    SELECT
        check_id =
            1000,
        b.database_name,
        object_name =
            N'-',
        finding_group =
            N'Total database block wait time',
        finding =
            N'This database has had ' +
            CONVERT
            (
                nvarchar(30),
                (
                    SUM
                    (
                        CONVERT
                        (
                            bigint,
                            b.wait_time_ms
                        )
                    ) / 1000 / 86400
                )
            ) +
            N' ' +
            CONVERT
              (
                  nvarchar(30),
                  DATEADD
                  (
                      MILLISECOND,
                      (
                          SUM
                          (
                              CONVERT
                              (
                                  bigint,
                                  b.wait_time_ms
                              )
                          )
                      ),
                      '19000101'
                  ),
                  14
              ) +
            N' [dd hh:mm:ss:ms] of lock wait time.',
       sort_order =
           ROW_NUMBER() OVER (ORDER BY SUM(CONVERT(bigint, b.wait_time_ms)) DESC)
    FROM b AS b
    WHERE (b.database_name = @database_name
           OR @database_name IS NULL)
    GROUP BY
        b.database_name
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        RAISERROR('Inserting #block_findings, check_id 1001', 0, 1) WITH NOWAIT;
    END;

    WITH
        b AS
    (
        SELECT
            b.database_name,
            b.transaction_id,
            b.contentious_object,
            wait_time_ms =
                MAX(b.wait_time_ms)
        FROM #blocks AS b
        WHERE (b.database_name = @database_name
               OR @database_name IS NULL)
        AND   (b.contentious_object = @object_name
               OR @object_name IS NULL)
        GROUP BY
            b.database_name,
            b.contentious_object,
            b.transaction_id
    )
    INSERT
        #block_findings
    (
        check_id,
        database_name,
        object_name,
        finding_group,
        finding,
        sort_order
    )
    SELECT
        check_id =
            1001,
        b.database_name,
        object_name =
            b.contentious_object,
        finding_group =
            N'Total database and object block wait time',
        finding =
            N'This object has had ' +
            CONVERT
            (
                nvarchar(30),
                (
                    SUM
                    (
                        CONVERT
                        (
                            bigint,
                            b.wait_time_ms
                        )
                    ) / 1000 / 86400
                )
            ) +
            N' ' +
            CONVERT
              (
                  nvarchar(30),
                  DATEADD
                  (
                      MILLISECOND,
                      (
                          SUM
                          (
                              CONVERT
                              (
                                  bigint,
                                  b.wait_time_ms
                              )
                          )
                      ),
                      '19000101'
                  ),
                  14
              ) +
            N' [dd hh:mm:ss:ms] of lock wait time in database ' +
            b.database_name,
       sort_order =
           ROW_NUMBER() OVER (ORDER BY SUM(CONVERT(bigint, b.wait_time_ms)) DESC)
    FROM b AS b
    WHERE (b.database_name = @database_name
           OR @database_name IS NULL)
    AND   (b.contentious_object = @object_name
           OR @object_name IS NULL)
    GROUP BY
        b.database_name,
        b.contentious_object
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        RAISERROR('Inserting #block_findings, check_id 2147483647', 0, 1) WITH NOWAIT;
    END;

    INSERT
        #block_findings
    (
        check_id,
        database_name,
        object_name,
        finding_group,
        finding,
        sort_order
    )
    SELECT
        check_id = 2147483647,
        database_name = N'erikdarling.com',
        object_name = N'sp_HumanEventsBlockViewer version ' + CONVERT(nvarchar(30), @version) + N'.',
        finding_group = N'https://code.erikdarling.com',
        finding = N'thanks for using me!',
        2147483647;

    SELECT
        findings =
             'findings',
        bf.check_id,
        bf.database_name,
        bf.object_name,
        bf.finding_group,
        bf.finding
    FROM #block_findings AS bf
    ORDER BY
        bf.check_id,
        bf.finding_group,
        bf.sort_order
    OPTION(RECOMPILE);
END;
END; --Final End
GO
