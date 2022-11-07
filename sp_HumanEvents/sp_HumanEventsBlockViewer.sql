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
    SELECT  'you can use me in conjunction with sp_HumanEvents to quickly parse the sqlserver.blocked_process_report event' UNION ALL
    SELECT  'EXEC sp_HumanEvents @event_type = N''blocking'', @keep_alive = 1;' UNION ALL
    SELECT  'it will also work with another extended event session using the ring buffer as a target to capture blocking' UNION ALL
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
    WHERE o.name = N'sp_HumanEventsBlockViewer';

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
    @target_type sysname = '',
    @session_id int,
    @target_session_id int,
    @file_name nvarchar(4000);

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

/*Look to see if the session exists and is running*/
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
        AND   dxs.create_time IS NOT NULL
    )
    BEGIN
        RAISERROR('A session with the name %s does not exist or is not currently active.', 0, 1, @session_name) WITH NOWAIT;
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
        LEFT JOIN sys.dm_xe_database_sessions AS dxs 
            ON dxs.name = ses.name
        WHERE ses.name = @session_name
        AND   dxs.create_time IS NOT NULL
    )
    BEGIN
        RAISERROR('A session with the name %s does not exist or is not currently active.', 0, 1, @session_name) WITH NOWAIT;
        RETURN;
    END;
END;

/*Figure out if we have a file or ring buffer target*/
IF @azure = 0
BEGIN
    SELECT 
        @target_type = 
            t.target_name
    FROM sys.dm_xe_sessions AS s
    JOIN sys.dm_xe_session_targets AS t
      ON s.address = t.event_session_address
    WHERE s.name = @session_name;
END;
IF @azure = 1
BEGIN
    SELECT 
        @target_type = 
            t.target_name
    FROM sys.dm_xe_database_sessions AS s
    JOIN sys.dm_xe_database_session_targets AS t
      ON s.address = t.event_session_address
    WHERE s.name = @session_name;
END;

/* Dump whatever we got into a temp table */
IF (@azure = 0 AND @target_type = 'ring_buffer')
BEGIN   
    INSERT
        #x
    (
        x
    )
    SELECT 
        x = 
            TRY_CAST
            (
                t.target_data
                AS xml
            )
    FROM sys.dm_xe_session_targets AS t
    JOIN sys.dm_xe_sessions AS s
        ON s.address = t.event_session_address
    WHERE s.name = @session_name
    AND   t.target_name = N'ring_buffer';
END;
IF (@azure = 1 AND @target_type = 'ring_buffer')
BEGIN
    INSERT
        #x
    (
        x
    )
    SELECT 
        x = 
            TRY_CAST
            (
                t.target_data
                AS xml
            )
    FROM sys.dm_xe_database_session_targets AS t
    JOIN sys.dm_xe_database_sessions AS s
        ON s.address = t.event_session_address
    WHERE s.name = @session_name
    AND   t.target_name = N'ring_buffer';
END;

IF @target_type = 'event_file'
BEGIN   
    IF @azure = 0
    BEGIN
        SELECT
            @session_id = t.event_session_id,
            @target_session_id = t.target_id
        FROM sys.server_event_session_targets t
        JOIN sys.server_event_sessions s
            ON s.event_session_id = t.event_session_id
        WHERE t.name = @target_type 
        AND   s.name = @session_name;

        SELECT
            @file_name =
                CASE 
                    WHEN f.file_name LIKE '%.xel'
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
        ) AS f;
    END;
    IF @azure = 1
    BEGIN
        SELECT
            @session_id = t.event_session_id,
            @target_session_id = t.target_id
        FROM sys.dm_xe_database_session_targets t
        JOIN sys.dm_xe_database_sessions s 
            ON s.event_session_id = t.event_session_id
        WHERE t.name = @target_type 
        AND   s.name = @session_name;

        SELECT
            @file_name =
                CASE 
                    WHEN f.file_name LIKE '%.xel'
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
        ) AS f;
    END;

    INSERT
        #x
    (
        x
    )    
    SELECT
        x = 
            TRY_CAST
            (
                f.event_data
                AS xml
            )
    FROM sys.fn_xe_file_target_read_file
         (
             @file_name, 
             NULL, 
             NULL, 
             NULL
         ) AS f;
END;


IF @target_type = 'ring_buffer'
BEGIN
    INSERT
        #blocking_xml
    (
        human_events_xml
    )
    SELECT 
        human_events_xml = 
                e.x.query('.')
    FROM #x AS x
    CROSS APPLY x.x.nodes('/RingBufferTarget/event') AS e(x);
END;

IF @target_type = 'event_file'
BEGIN
    INSERT
        #blocking_xml
    (
        human_events_xml
    )
    SELECT 
        human_events_xml = 
                e.x.query('.')
    FROM #x AS x
    CROSS APPLY x.x.nodes('/event') AS e(x);
END;

IF @debug = 1
BEGIN
    SELECT table_name = N'#blocking_xml', bx.* FROM #blocking_xml AS bx;
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
                activity = 'blocked',
                blocked_process_report = c.query('.')
            INTO #blocked
            FROM #blocking_xml AS bx
            OUTER APPLY bx.human_events_xml.nodes('//event') AS oa(c)
            OUTER APPLY oa.c.nodes('//blocked-process-report/blocked-process') AS bd(bd);

            IF @debug = 1 BEGIN SELECT '#blocked' AS table_name, * FROM #blocked AS wa; END;

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
                wait_time = bg.value('(process/@waittime)[1]', 'bigint'),
                transaction_name = bg.value('(process/@transactionname)[1]', 'nvarchar(256)'),
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
                activity = 'blocking',
                blocked_process_report = c.query('.')
            INTO #blocking
            FROM #blocking_xml AS bx
            OUTER APPLY bx.human_events_xml.nodes('//event') AS oa(c)
            OUTER APPLY oa.c.nodes('//blocked-process-report/blocking-process') AS bg(bg);

            IF @debug = 1 BEGIN SELECT '#blocking' AS table_name, * FROM #blocking AS wa; END;

            SELECT
                kheb.event_time,
                kheb.database_name,
                contentious_object = 
                    ISNULL
                    (
                        kheb.contentious_object, 
                        N'Unresolved'
                    ),
                kheb.activity,
                kheb.monitor_loop,
                kheb.spid,
                kheb.ecid,
                query_text =
                    CASE 
                        WHEN kheb.query_text LIKE 'Proc [[]Database Id = %'
                        THEN 
                            (
                                SELECT
                                    [processing-instruction(query)] =                                       
                                           OBJECT_NAME
                                           (
                                               SUBSTRING
                                               (
                                                   REPLACE(REPLACE(query_text, '[', ''), ']', ''),
                                                   CHARINDEX('Object Id = ', query_text) + LEN('Object Id = '),
                                                   LEN(query_text)
                                               ),
                                               kheb.database_id
                                           )
                                FOR XML
                                    PATH(N'query'),
                                    TYPE
                            )
                        ELSE
                            (
                                SELECT 
                                    [processing-instruction(query)] = 
                                        kheb.query_text
                                FOR XML
                                    PATH(N'query'),
                                    TYPE
                            )
                    END,
                wait_time_ms = 
                    kheb.wait_time,
                kheb.status,
                kheb.isolation_level,
                c.sql_handles,
                kheb.resource_owner_type,
                kheb.lock_mode,
                kheb.transaction_count,
                kheb.transaction_name,
                kheb.last_transaction_started,
                kheb.last_transaction_completed,
                client_option_1 = 
                      SUBSTRING
                      (    
                          CASE WHEN kheb.clientoption1 & 0x20 = 0x20 THEN ', QUOTED IDENTIFIER ON' ELSE '' END +
                          CASE WHEN kheb.clientoption1 & 0x40 = 0x40 THEN ', ARITHABORT' ELSE '' END +
                          CASE WHEN kheb.clientoption1 & 0x800 = 0x800 THEN ', USER SET ARITHABORT' ELSE '' END +
                          CASE WHEN kheb.clientoption1 & 0x8000 = 0x8000 THEN ', NUMERIC ROUNDABORT ON' ELSE '' END +
                          CASE WHEN kheb.clientoption1 & 0x10000 = 0x10000 THEN ', USER SET NUMERIC ROUNDABORT ON' ELSE '' END +
                          CASE WHEN kheb.clientoption1 & 0x20000 = 0x20000 THEN ', SET XACT ABORT ON' ELSE '' END +
                          CASE WHEN kheb.clientoption1 & 0x80000 = 0x80000 THEN ', NOCOUNT OFF' ELSE '' END +
                          CASE WHEN kheb.clientoption1 & 0x200000 = 0x200000 THEN ', NOCOUNT ON' ELSE '' END +
                          CASE WHEN kheb.clientoption1 & 0x8000000 = 8000000 THEN ', USER SET QUOTED IDENTIFIER' ELSE '' END +
                          CASE WHEN kheb.clientoption1 & 0x20000000 = 0x20000000 THEN ', ANSI NULL DEFAULT ON' ELSE '' END +
                          CASE WHEN kheb.clientoption1 & 0x40000000 = 0x40000000 THEN ', ANSI NULL DEFAULT OFF' ELSE '' END,
                          3,
                          8000
                      ),
                  client_option_2 = 
                      SUBSTRING
                      (
                          CASE WHEN kheb.clientoption2 & 2 = 2 THEN ', IMPLICIT TRANSACTION' ELSE '' END +
                          CASE WHEN kheb.clientoption2 & 8 = 8 THEN ', ANSI WARNINGS' ELSE '' END +
                          CASE WHEN kheb.clientoption2 & 0x10 = 0x10 THEN ', ANSI PADDING' ELSE '' END +
                          CASE WHEN kheb.clientoption2 & 0x20 = 0x20 THEN ', ANSI NULLS' ELSE '' END +
                          CASE WHEN kheb.clientoption2 & 0x1000 = 0x1000 THEN ', USER CONCAT NULL YIELDS NULL' ELSE '' END +
                          CASE WHEN kheb.clientoption2 & 0x2000 = 0x2000 THEN ', CONCAT NULL YIELDS NULL' ELSE '' END +
                          CASE WHEN kheb.clientoption2 & 0x4000 = 0x4000 THEN ', USER ANSI NULLS' ELSE '' END +
                          CASE WHEN kheb.clientoption2 & 0x8000 = 0x8000 THEN ', USER ANSI WARNINGS' ELSE '' END,
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
                kheb.blocked_process_report
            INTO #blocks
            FROM 
            (                
                SELECT 
                    bg.*, 
                    contentious_object = 
                        OBJECT_NAME
                        (
                            bg.object_id, 
                            bg.database_id
                        )
                FROM #blocking AS bg
                
                UNION ALL 
                
                SELECT 
                    bd.*, 
                    contentious_object = 
                        OBJECT_NAME
                        (
                            bd.object_id, 
                            bd.database_id
                        ) 
                FROM #blocked AS bd           
            ) AS kheb
            CROSS APPLY 
            (
              SELECT 
                  sql_handles = 
                      STUFF
                      (
                          (
                              SELECT DISTINCT
                                  ',' +
                                  RTRIM
                                  (
                                      n.c.value('@sqlhandle', 'varchar(130)')
                                  )
                              FROM kheb.blocked_process_report.nodes('//executionStack/frame') AS n(c)
                              FOR XML
                                  PATH(''),
                                  TYPE
                          ).value('./text()[1]', 'varchar(max)'),
                          1,
                          1,
                          ''
                      )                    
             ) AS c;

            SELECT
                b.*
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
            ORDER BY 
                b.event_time DESC,
                CASE 
                    WHEN b.activity = 'blocking' 
                    THEN 1
                    ELSE 999 
                END;
END; --Final End