SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
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

Copyright 2022 Darling Data, LLC
https://www.erikdarlingdata.com/

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
    @version varchar(30) = NULL OUTPUT,
    @version_date datetime = NULL OUTPUT,
    @help bit = 0,
    @debug bit = 0
)
WITH RECOMPILE
AS
BEGIN

SET STATISTICS XML OFF;
SET NOCOUNT, XACT_ABORT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

SELECT 
    @version = '1.00', 
    @version_date = '20220901';

IF @help = 1
BEGIN

    SELECT
        introduction = 
		    'hi, i''m sp_HumanEventsBlockViewer!' UNION ALL
	SELECT  'you can use me in conjunction with sp_HumanEvents to quickly parse a blocking event session' UNION ALL
	SELECT  'EXEC sp_HumanEvents @event_type = N''blocking'', @keep_alive = 1;' UNION ALL
	SELECT  'all scripts and documentation are available here: https://github.com/erikdarlingdata/DarlingData/tree/main/sp_HumanEvents' UNION ALL
	SELECT  'from your loving sql server consultant, erik darling: erikdarlingdata.com';

    SELECT
        parameter_name =
            ap.name,
        data_type = t.name,
        description =
            CASE ap.name
                 WHEN '@session_name' THEN 'The name of the Extended Event session to pull blocking data from'
                 WHEN '@version' THEN 'OUTPUT; for support'
                 WHEN '@version_date' THEN 'OUTPUT; for support'
                 WHEN '@help' THEN 'how you got here'
                 WHEN '@debug' THEN 'dumps raw temp table contents'
			END,
		valid_inputs =
            CASE ap.name
                 WHEN '@session_name' THEN 'An Extended Event session name that is capturing the sqlserver.blocked_process_report'
                 WHEN '@version' THEN 'none; OUTPUT'
                 WHEN '@version_date' THEN 'none; OUTPUT'
                 WHEN '@help' THEN '0 or 1'
                 WHEN '@debug' THEN '0 or 1'
			END,
        defaults =
            CASE ap.name
                 WHEN '@session_name' THEN 'keeper_HumanEvents_blocking'
                 WHEN '@version' THEN 'none; OUTPUT'
                 WHEN '@version_date' THEN 'none; OUTPUT'
                 WHEN '@help' THEN '0'
                 WHEN '@debug' THEN '0'
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
        mit_license_yo = N'i am MIT licensed, so like, do whatever' UNION ALL
    SELECT N'see printed messages for full license';
    RAISERROR(N'
MIT License

Copyright 2022 Darling Data, LLC 

https://www.erikdarlingdata.com/

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
    @x xml = NULL;

/*Look to see if the session exists*/
IF @azure = 0
BEGIN
    IF NOT EXISTS
    (
        SELECT 
            1/0
        FROM sys.server_event_sessions AS ses
        LEFT JOIN sys.dm_xe_sessions AS dxs 
            ON dxs.name = ses.name
        WHERE ses.name = @session_name
    )
    BEGIN
        RAISERROR('A session with the name %s does not exist.', 0, 1, @session_name) WITH NOWAIT;
        RETURN;
    END;
END;
ELSE
BEGIN
    IF NOT EXISTS
    (
        SELECT 
            1/0
        FROM sys.database_event_sessions AS ses
        LEFT JOIN sys.dm_xe_database_sessions AS dxs 
            ON dxs.name = ses.name
        WHERE ses.name = @session_name
    )
    BEGIN
        RAISERROR('A session with the name %s does not exist.', 0, 1, @session_name) WITH NOWAIT;
        RETURN;
    END;
END;

/* Dump whatever we got into a temp table */
IF @azure = 0
BEGIN
    SELECT 
        @x = 
            CONVERT
            (
                xml, 
                t.target_data
            )
    FROM sys.dm_xe_session_targets AS t
    JOIN sys.dm_xe_sessions AS s
        ON s.address = t.event_session_address
    WHERE s.name = @session_name
    AND   t.target_name = N'ring_buffer';
END;
ELSE
BEGIN
    SELECT 
        @x = 
            CONVERT
            (
                xml, 
                t.target_data
            )
    FROM sys.dm_xe_database_session_targets AS t
    JOIN sys.dm_xe_database_sessions AS s
        ON s.address = t.event_session_address
    WHERE s.name = @session_name
    AND   t.target_name = N'ring_buffer';
END;

SELECT 
    human_events_xml = 
        e.x.query('.')
INTO   #blocking_xml
FROM   @x.nodes('/RingBufferTarget/event') AS e(x)
OPTION(RECOMPILE);

IF @debug = 1
BEGIN
    SELECT table_name = N'#human_events_xml', bx.* FROM #blocking_xml AS bx;
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
                database_name = DB_NAME(c.value('(data[@name="database_id"]/value)[1]', 'int')),
                database_id = c.value('(data[@name="database_id"]/value)[1]', 'int'),
                object_id = c.value('(data[@name="object_id"]/value)[1]', 'int'),
                transaction_id = c.value('(data[@name="transaction_id"]/value)[1]', 'bigint'),
                resource_owner_type = c.value('(data[@name="resource_owner_type"]/text)[1]', 'nvarchar(256)'),
                monitor_loop = c.value('(//@monitorLoop)[1]', 'int'),
                spid = bd.value('(process/@spid)[1]', 'int'),
                ecid = bd.value('(process/@ecid)[1]', 'int'),
                query_text = bd.value('(process/inputbuf/text())[1]', 'nvarchar(MAX)'),
                wait_time = bd.value('(process/@waittime)[1]', 'bigint'),
                transaction_name = bd.value('(process/@transactionname)[1]', 'nvarchar(256)'),
                last_transaction_started = bd.value('(process/@lasttranstarted)[1]', 'datetime2'),
                wait_resource = bd.value('(process/@waitresource)[1]', 'nvarchar(100)'),
                lock_mode = bd.value('(process/@lockMode)[1]', 'nvarchar(10)'),
                status = bd.value('(process/@status)[1]', 'nvarchar(10)'),
                priority = bd.value('(process/@priority)[1]', 'int'),
                transaction_count = bd.value('(process/@trancount)[1]', 'int'),
                client_app = bd.value('(process/@clientapp)[1]', 'nvarchar(256)'),
                host_name = bd.value('(process/@hostname)[1]', 'nvarchar(256)'),
                login_name = bd.value('(process/@loginname)[1]', 'nvarchar(256)'),
                isolation_level = bd.value('(process/@isolationlevel)[1]', 'nvarchar(50)'),
                sqlhandle = bd.value('(process/executionStack/frame/@sqlhandle)[1]', 'nvarchar(260)'),
                activity = 'blocked',
                blocked_process_report = c.query('.')
            INTO #blocked
            FROM #blocking_xml AS bx
            OUTER APPLY bx.human_events_xml.nodes('//event') AS oa(c)
            OUTER APPLY oa.c.nodes('//blocked-process-report/blocked-process') AS bd(bd)
            OPTION(RECOMPILE);

            IF @debug = 1 BEGIN SELECT N'#blocked' AS table_name, * FROM #blocked AS wa OPTION(RECOMPILE); END;

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
                database_name = DB_NAME(c.value('(data[@name="database_id"]/value)[1]', 'int')),
                database_id = c.value('(data[@name="database_id"]/value)[1]', 'int'),
                object_id = c.value('(data[@name="object_id"]/value)[1]', 'int'),
                transaction_id = c.value('(data[@name="transaction_id"]/value)[1]', 'bigint'),
                resource_owner_type = c.value('(data[@name="resource_owner_type"]/text)[1]', 'nvarchar(256)'),
                monitor_loop = c.value('(//@monitorLoop)[1]', 'int'),
                spid = bg.value('(process/@spid)[1]', 'int'),
                ecid = bg.value('(process/@ecid)[1]', 'int'),
                query_text = bg.value('(process/inputbuf/text())[1]', 'nvarchar(MAX)'),
                wait_time = CONVERT(int, NULL),
                transaction_name = CONVERT(nvarchar(256), NULL),
                last_transaction_started = CONVERT(datetime2, NULL),
                wait_resource = CONVERT(nvarchar(100), NULL),
                lock_mode = CONVERT(nvarchar(10), NULL),
                status = bg.value('(process/@status)[1]', 'nvarchar(10)'),
                priority = bg.value('(process/@priority)[1]', 'int'),
                transaction_count = bg.value('(process/@trancount)[1]', 'int'),
                client_app = bg.value('(process/@clientapp)[1]', 'nvarchar(256)'),
                host_name = bg.value('(process/@hostname)[1]', 'nvarchar(256)'),
                login_name = bg.value('(process/@loginname)[1]', 'nvarchar(256)'),
                isolation_level = bg.value('(process/@isolationlevel)[1]', 'nvarchar(50)'),
                sqlhandle = CONVERT(nvarchar(260), NULL),
                activity = 'blocking',
                blocked_process_report = c.query('.')
            INTO #blocking
            FROM #blocking_xml AS bx
            OUTER APPLY bx.human_events_xml.nodes('//event') AS oa(c)
            OUTER APPLY oa.c.nodes('//blocked-process-report/blocking-process') AS bg(bg)
            OPTION(RECOMPILE);

            IF @debug = 1 BEGIN SELECT N'#blocking' AS table_name, * FROM #blocking AS wa OPTION(RECOMPILE); END;

            SELECT TOP (2147483647)
                kheb.event_time,
                kheb.database_name,
                kheb.contentious_object,
                kheb.activity,
                kheb.spid,
                kheb.query_text,
                kheb.wait_time,
                kheb.status,
                kheb.isolation_level,
                kheb.last_transaction_started,
                kheb.transaction_name,
                kheb.wait_resource,
                kheb.lock_mode,
                kheb.priority,
                kheb.transaction_count,
                kheb.client_app,
                kheb.host_name,
                kheb.login_name,
                kheb.blocked_process_report
            FROM 
            (
                
                SELECT 
                    bg.*, 
                    OBJECT_NAME
                    (
                        bg.object_id, 
                        bg.database_id
                    ) AS contentious_object 
                    FROM #blocking AS bg
                
                UNION ALL 
                
                SELECT 
                    bd.*, 
                    OBJECT_NAME
                    (
                        bd.object_id, 
                        bd.database_id
                    ) AS contentious_object 
                FROM #blocked AS bd
            
            ) AS kheb
            ORDER BY 
                kheb.event_time DESC,
                CASE 
                    WHEN kheb.activity = 'blocking' 
                    THEN 1
                    ELSE 999 
                END
            OPTION(RECOMPILE);

END; --Final End