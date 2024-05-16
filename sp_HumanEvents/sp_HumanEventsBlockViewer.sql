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

Copyright 2024 Darling Data, LLC
https://www.erikdarling.com/

For usage and licensing details, run:
EXEC sp_HumanEventsBlockViewer
    @help = 1;

For working through errors:
EXEC sp_HumanEventsBlockViewer
    @debug = 1;

For support, head over to GitHub:
https://github.com/erikdarlingdata/DarlingData
*/

IF OBJECT_ID('dbo.sp_HumanEventsBlockViewer') IS NULL
   BEGIN
       EXEC ('CREATE PROCEDURE dbo.sp_HumanEventsBlockViewer AS RETURN 138;');
   END;
GO

ALTER PROCEDURE
    dbo.sp_HumanEventsBlockViewer
(
    @session_name nvarchar(256) = N'keeper_HumanEvents_blocking',
    @target_type sysname = NULL,
    @start_date datetime2 = NULL,
    @end_date datetime2 = NULL,
    @database_name sysname = NULL,
    @object_name sysname = NULL,
    @help bit = 0,
    @debug bit = 0,
    @version varchar(30) = NULL OUTPUT,
    @version_date datetime = NULL OUTPUT
)
WITH RECOMPILE
AS
BEGIN
SET STATISTICS XML OFF;
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

SELECT
    @version = '3.5',
    @version_date = '20240401';

IF @help = 1
BEGIN
    SELECT
        introduction =
            'hi, i''m sp_HumanEventsBlockViewer!' UNION ALL
    SELECT  'you can use me in conjunction with sp_HumanEvents to quickly parse the sqlserver.blocked_process_report event' UNION ALL
    SELECT  'EXEC sp_HumanEvents @event_type = N''blocking'', @keep_alive = 1;' UNION ALL
    SELECT  'it will also work with any other extended event session that captures blocking' UNION ALL
    SELECT  'just use the @session_name parameter to point me there' UNION ALL
    SELECT  'EXEC dbo.sp_HumanEventsBlockViewer @session_name = N''blocked_process_report'';' UNION ALL
    SELECT  'all scripts and documentation are available here: https://github.com/erikdarlingdata/DarlingData/tree/main/sp_HumanEvents' UNION ALL
    SELECT  'from your loving sql server consultant, erik darling: https://erikdarling.com';

    SELECT
        parameter_name =
            ap.name,
        data_type = t.name,
        description =
            CASE ap.name
                 WHEN N'@session_name' THEN 'name of the extended event session to pull from'
                 WHEN N'@target_type' THEN 'target of the extended event session'
                 WHEN N'@start_date' THEN 'filter by date'
                 WHEN N'@end_date' THEN 'filter by date'
                 WHEN N'@database_name' THEN 'filter by database name'
                 WHEN N'@object_name' THEN 'filter by table name'
                 WHEN N'@help' THEN 'how you got here'
                 WHEN N'@debug' THEN 'dumps raw temp table contents'
                 WHEN N'@version' THEN 'OUTPUT; for support'
                 WHEN N'@version_date' THEN 'OUTPUT; for support'
            END,
        valid_inputs =
            CASE ap.name
                 WHEN N'@session_name' THEN 'extended event session name capturing sqlserver.blocked_process_report'
                 WHEN N'@target_type' THEN 'event_file or ring_buffer'
                 WHEN N'@start_date' THEN 'a reasonable date'
                 WHEN N'@end_date' THEN 'a reasonable date'
                 WHEN N'@database_name' THEN 'a database that exists on this server'
                 WHEN N'@object_name' THEN 'a schema-prefixed table name'
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
The blocked process report needs to be enabled:
EXEC sys.sp_configure ''show advanced options'', 1;
EXEC sys.sp_configure ''blocked process threshold'', 5; /* Seconds of blocking before a report is generated */
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

Copyright 2024 Darling Data, LLC

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

/*Check if the blocked process report is on at all*/
IF EXISTS
(
    SELECT
        1/0
    FROM sys.configurations AS c
    WHERE c.name = N'blocked process threshold (s)'
    AND   CONVERT(int, c.value_in_use) = 0
)
BEGIN
    RAISERROR(N'The blocked process report needs to be enabled:
EXEC sys.sp_configure ''show advanced options'', 1;
EXEC sys.sp_configure ''blocked process threshold'', 5; /* Seconds of blocking before a report is generated */
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
)
BEGIN
    RAISERROR(N'For best results, set up the blocked process report like this:
EXEC sys.sp_configure ''show advanced options'', 1;
EXEC sys.sp_configure ''blocked process threshold'', 5; /* Seconds of blocking before a report is generated */
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
                     int,
                     SERVERPROPERTY('EngineEdition')
                 ) = 5
            THEN 1
            ELSE 0
        END,
    @azure_msg nchar(1),
    @session_id integer,
    @target_session_id integer,
    @file_name nvarchar(4000),
    @is_system_health bit = 0,
    @is_system_health_msg nchar(1),
    @inputbuf_bom nvarchar(1) =
        CONVERT(nvarchar(1), 0x0a00, 0),
    @start_date_original datetime2 = @start_date,
    @end_date_original datetime2 = @end_date;

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
    @is_system_health =
        CASE
            WHEN @session_name LIKE N'system%health'
            THEN 1
            ELSE 0
        END;

SELECT
    @azure_msg =
        CONVERT(nchar(1), @azure),
    @is_system_health_msg =
        CONVERT(nchar(1), @is_system_health);

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
    id int IDENTITY PRIMARY KEY,
    check_id int NOT NULL,
    database_name nvarchar(256) NULL,
    object_name nvarchar(1000) NULL,
    finding_group nvarchar(100) NULL,
    finding nvarchar(4000) NULL,
    sort_order bigint
);

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
IF @target_type IS NULL AND @is_system_health = 0
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
IF @target_type = N'ring_buffer' AND @is_system_health = 0
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

IF @target_type = N'event_file' AND @is_system_health = 0
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


IF @target_type = N'ring_buffer' AND @is_system_health = 0
BEGIN
    IF @debug = 1
    BEGIN
        RAISERROR('Inserting to #blocking_xml for target type: %s and system health: %s', 0, 1, @target_type, @is_system_health_msg) WITH NOWAIT;
    END;

    INSERT
        #blocking_xml WITH(TABLOCKX)
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

IF @target_type = N'event_file' AND @is_system_health = 0
BEGIN
    IF @debug = 1
    BEGIN
        RAISERROR('Inserting to #blocking_xml for target type: %s and system health: %s', 0, 1, @target_type, @is_system_health_msg) WITH NOWAIT;
    END;

    INSERT
        #blocking_xml WITH(TABLOCKX)
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
process report stored in the system health extended event session
*/
IF @is_system_health = 1
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
        spid = bd.value('(process/@spid)[1]', 'int'),
        ecid = bd.value('(process/@ecid)[1]', 'int'),
        query_text_pre = bd.value('(process/inputbuf/text())[1]', 'nvarchar(MAX)'),
        wait_time = bd.value('(process/@waittime)[1]', 'bigint'),
        lastbatchstarted = bd.value('(process/@lastbatchstarted)[1]', 'datetime2'),
        lastbatchcompleted = bd.value('(process/@lastbatchcompleted)[1]', 'datetime2'),
        wait_resource = bd.value('(process/@waitresource)[1]', 'nvarchar(100)'),
        status = bd.value('(process/@status)[1]', 'nvarchar(10)'),
        priority = bd.value('(process/@priority)[1]', 'int'),
        transaction_count = bd.value('(process/@trancount)[1]', 'int'),
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
        spid = bg.value('(process/@spid)[1]', 'int'),
        ecid = bg.value('(process/@ecid)[1]', 'int'),
        query_text_pre = bg.value('(process/inputbuf/text())[1]', 'nvarchar(MAX)'),
        wait_time = bg.value('(process/@waittime)[1]', 'bigint'),
        last_transaction_started = bg.value('(process/@lastbatchstarted)[1]', 'datetime2'),
        last_transaction_completed = bg.value('(process/@lastbatchcompleted)[1]', 'datetime2'),
        wait_resource = bg.value('(process/@waitresource)[1]', 'nvarchar(100)'),
        status = bg.value('(process/@status)[1]', 'nvarchar(10)'),
        priority = bg.value('(process/@priority)[1]', 'int'),
        transaction_count = bg.value('(process/@trancount)[1]', 'int'),
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
                     LIKE CONVERT(nvarchar(1), 0x0a00, 0) + N'Proc |[Database Id = %' ESCAPE N'|'
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
                TRY_CAST(b.query_text AS nvarchar(MAX)),
            sql_handle =
                CONVERT(varbinary(64), n.c.value('@sqlhandle', 'varchar(130)'), 1),
            stmtstart =
                ISNULL(n.c.value('@stmtstart', 'int'), 0),
            stmtend =
                ISNULL(n.c.value('@stmtend', 'int'), -1)
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
                TRY_CAST(b.query_text AS nvarchar(MAX)),
            sql_handle =
                CONVERT(varbinary(64), n.c.value('@sqlhandle', 'varchar(130)'), 1),
            stmtstart =
                ISNULL(n.c.value('@stmtstart', 'int'), 0),
            stmtend =
                ISNULL(n.c.value('@stmtend', 'int'), -1)
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
        deqs.total_rows
    INTO #dm_exec_query_stats_sh
    FROM sys.dm_exec_query_stats AS deqs
    WHERE EXISTS
    (
        SELECT
            1/0
        FROM #available_plans_sh AS ap
        WHERE ap.sql_handle = deqs.sql_handle
    )
    AND deqs.query_hash IS NOT NULL;

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
        ap.total_elapsed_time_ms,
        ap.avg_elapsed_time_ms,
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
            c.query_plan
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
    database_name = DB_NAME(c.value('(data[@name="database_id"]/value/text())[1]', 'int')),
    database_id = c.value('(data[@name="database_id"]/value/text())[1]', 'int'),
    object_id = c.value('(data[@name="object_id"]/value/text())[1]', 'int'),
    transaction_id = c.value('(data[@name="transaction_id"]/value/text())[1]', 'bigint'),
    resource_owner_type = c.value('(data[@name="resource_owner_type"]/text)[1]', 'nvarchar(256)'),
    monitor_loop = c.value('(//@monitorLoop)[1]', 'int'),
    blocking_spid = bg.value('(process/@spid)[1]', 'int'),
    blocking_ecid = bg.value('(process/@ecid)[1]', 'int'),
    blocked_spid = bd.value('(process/@spid)[1]', 'int'),
    blocked_ecid = bd.value('(process/@ecid)[1]', 'int'),
    query_text_pre = bd.value('(process/inputbuf/text())[1]', 'nvarchar(MAX)'),
    wait_time = bd.value('(process/@waittime)[1]', 'bigint'),
    transaction_name = bd.value('(process/@transactionname)[1]', 'nvarchar(512)'),
    last_transaction_started = bd.value('(process/@lasttranstarted)[1]', 'datetime2'),
    last_transaction_completed = CONVERT(datetime2, NULL),
    wait_resource = bd.value('(process/@waitresource)[1]', 'nvarchar(100)'),
    lock_mode = bd.value('(process/@lockMode)[1]', 'nvarchar(10)'),
    status = bd.value('(process/@status)[1]', 'nvarchar(10)'),
    priority = bd.value('(process/@priority)[1]', 'int'),
    transaction_count = bd.value('(process/@trancount)[1]', 'int'),
    client_app = bd.value('(process/@clientapp)[1]', 'nvarchar(256)'),
    host_name = bd.value('(process/@hostname)[1]', 'nvarchar(256)'),
    login_name = bd.value('(process/@loginname)[1]', 'nvarchar(256)'),
    isolation_level = bd.value('(process/@isolationlevel)[1]', 'nvarchar(50)'),
    log_used = bd.value('(process/@logused)[1]', 'bigint'),
    clientoption1 = bd.value('(process/@clientoption1)[1]', 'bigint'),
    clientoption2 = bd.value('(process/@clientoption1)[1]', 'bigint'),
    currentdbname = bd.value('(process/@currentdbname)[1]', 'nvarchar(256)'),
    currentdbid = bd.value('(process/@currentdb)[1]', 'int'),
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
    database_name = DB_NAME(c.value('(data[@name="database_id"]/value/text())[1]', 'int')),
    database_id = c.value('(data[@name="database_id"]/value/text())[1]', 'int'),
    object_id = c.value('(data[@name="object_id"]/value/text())[1]', 'int'),
    transaction_id = c.value('(data[@name="transaction_id"]/value/text())[1]', 'bigint'),
    resource_owner_type = c.value('(data[@name="resource_owner_type"]/text)[1]', 'nvarchar(256)'),
    monitor_loop = c.value('(//@monitorLoop)[1]', 'int'),
    blocking_spid = bg.value('(process/@spid)[1]', 'int'),
    blocking_ecid = bg.value('(process/@ecid)[1]', 'int'),
    blocked_spid = bd.value('(process/@spid)[1]', 'int'),
    blocked_ecid = bd.value('(process/@ecid)[1]', 'int'),
    query_text_pre = bg.value('(process/inputbuf/text())[1]', 'nvarchar(MAX)'),
    wait_time = bg.value('(process/@waittime)[1]', 'bigint'),
    transaction_name = bg.value('(process/@transactionname)[1]', 'nvarchar(512)'),
    last_transaction_started = bg.value('(process/@lastbatchstarted)[1]', 'datetime2'),
    last_transaction_completed = bg.value('(process/@lastbatchcompleted)[1]', 'datetime2'),
    wait_resource = bg.value('(process/@waitresource)[1]', 'nvarchar(100)'),
    lock_mode = bg.value('(process/@lockMode)[1]', 'nvarchar(10)'),
    status = bg.value('(process/@status)[1]', 'nvarchar(10)'),
    priority = bg.value('(process/@priority)[1]', 'int'),
    transaction_count = bg.value('(process/@trancount)[1]', 'int'),
    client_app = bg.value('(process/@clientapp)[1]', 'nvarchar(256)'),
    host_name = bg.value('(process/@hostname)[1]', 'nvarchar(256)'),
    login_name = bg.value('(process/@loginname)[1]', 'nvarchar(256)'),
    isolation_level = bg.value('(process/@isolationlevel)[1]', 'nvarchar(50)'),
    log_used = bg.value('(process/@logused)[1]', 'bigint'),
    clientoption1 = bg.value('(process/@clientoption1)[1]', 'bigint'),
    clientoption2 = bg.value('(process/@clientoption1)[1]', 'bigint'),
    currentdbname = bg.value('(process/@currentdbname)[1]', 'nvarchar(128)'),
    currentdbid = bg.value('(process/@currentdb)[1]', 'int'),
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
                ' <-- ' +
                blocked_desc AS varchar(400)
            )
    FROM #blocking b
    WHERE NOT EXISTS
    (
        SELECT
            1/0
        FROM #blocking b2
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
                ' <-- ' +
                bg.blocked_desc AS varchar(400)
            )
    FROM hierarchy h
    JOIN #blocking bg
      ON  bg.monitor_loop = h.monitor_loop
      AND bg.blocking_desc = h.blocked_desc
)
UPDATE #blocked
SET
    blocking_level = h.level,
    sort_order = h.sort_order
FROM #blocked b
JOIN hierarchy h
  ON  h.monitor_loop = b.monitor_loop
  AND h.blocking_desc = b.blocking_desc
  AND h.blocked_desc = b.blocked_desc
OPTION(RECOMPILE, MAXRECURSION 0);

IF @debug = 1
BEGIN
    RAISERROR('Updating #blocking', 0, 1) WITH NOWAIT;
END;

UPDATE #blocking
SET
    blocking_level = bd.blocking_level,
    sort_order = bd.sort_order
FROM #blocking bg
JOIN #blocked bd
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
    WHERE (bg.database_name = @database_name
           OR @database_name IS NULL)

    UNION ALL

    SELECT
        bd.*
    FROM #blocked AS bd
    WHERE (bd.database_name = @database_name
           OR @database_name IS NULL)
) AS kheb
OPTION(RECOMPILE);

IF @debug = 1
BEGIN
    RAISERROR('Updating #blocks contentious_object column', 0, 1) WITH NOWAIT;
END;
UPDATE b
    SET b.contentious_object =
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

SELECT
    blocked_process_report =
        'blocked_process_report',
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
AND   (b.contentious_object = @object_name
       OR @object_name IS NULL)
ORDER BY
    b.sort_order,
    CASE
        WHEN b.activity = 'blocking'
        THEN -1
        ELSE +1
    END
OPTION(RECOMPILE);

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
            TRY_CAST(b.query_text AS nvarchar(MAX)),
        sql_handle =
            CONVERT(varbinary(64), n.c.value('@sqlhandle', 'varchar(130)'), 1),
        stmtstart =
            ISNULL(n.c.value('@stmtstart', 'int'), 0),
        stmtend =
            ISNULL(n.c.value('@stmtend', 'int'), -1)
    FROM #blocks AS b
    CROSS APPLY b.blocked_process_report.nodes('/event/data/value/blocked-process-report/blocking-process/process/executionStack/frame[not(@sqlhandle = "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")]') AS n(c)
    WHERE (b.database_name = @database_name
            OR @database_name IS NULL)
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
            TRY_CAST(b.query_text AS nvarchar(MAX)),
        sql_handle =
            CONVERT(varbinary(64), n.c.value('@sqlhandle', 'varchar(130)'), 1),
        stmtstart =
            ISNULL(n.c.value('@stmtstart', 'int'), 0),
        stmtend =
            ISNULL(n.c.value('@stmtend', 'int'), -1)
    FROM #blocks AS b
    CROSS APPLY b.blocked_process_report.nodes('/event/data/value/blocked-process-report/blocking-process/process/executionStack/frame[not(@sqlhandle = "0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")]') AS n(c)
    WHERE (b.database_name = @database_name
            OR @database_name IS NULL)
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
    deqs.total_rows
INTO #dm_exec_query_stats
FROM sys.dm_exec_query_stats AS deqs
WHERE EXISTS
(
   SELECT
       1/0
   FROM #available_plans AS ap
   WHERE ap.sql_handle = deqs.sql_handle
)
AND deqs.query_hash IS NOT NULL;

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
    ap.total_elapsed_time_ms,
    ap.avg_elapsed_time_ms,
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
        c.query_plan
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
    finding_group = N'https://github.com/erikdarlingdata/DarlingData',
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
    finding_group = N'https://github.com/erikdarlingdata/DarlingData',
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
END; --Final End
GO
