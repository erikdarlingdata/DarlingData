SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

IF OBJECT_ID('dbo.sp_HumanEvents') IS  NULL
    EXEC ('CREATE PROCEDURE dbo.sp_HumanEvents AS RETURN 138;');
GO

ALTER PROCEDURE dbo.sp_HumanEvents( @event_type sysname = N'query',
                                    @query_duration_ms INTEGER = 500,
                                    @query_sort_order NVARCHAR(10) = N'cpu',
                                    @blocking_duration_ms INTEGER = 500,
                                    @wait_type NVARCHAR(4000) = N'all',
                                    @wait_duration_ms INTEGER = 10,
                                    @capture_plans BIT = 1,
                                    @client_app_name sysname = N'',
                                    @client_hostname sysname = N'',
                                    @database_name sysname = N'',
                                    @session_id NVARCHAR(7) = N'',
                                    @sample_divisor INT = 5,
                                    @username sysname = N'',
                                    @object_name sysname = N'',
                                    @object_schema sysname = N'dbo', 
                                    @requested_memory_mb INTEGER = 0,
                                    @seconds_sample INTEGER = 10,
                                    @gimme_danger BIT = 0,
                                    @keep_alive BIT = 0,
                                    @version VARCHAR(30) = NULL OUTPUT,
                                    @versiondate DATETIME = NULL OUTPUT,
                                    @debug BIT = 0,
                                    @help BIT = 0 )
WITH RECOMPILE
AS
BEGIN

SET NOCOUNT, XACT_ABORT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

SELECT @version = '1.0', @versiondate = '20200301';

IF @help = 1
BEGIN
    /*Warnings, I guess*/
    SELECT N'warning! achtung! peligro! chardonnay!' AS [WARNING WARNING WARNING] UNION ALL 
    SELECT N'misuse of this procedure can harm performance' UNION ALL
    SELECT N'be very careful about introducing observer overhead, especially when gathering query plans' UNION ALL
    SELECT N'for additional support: http://bit.ly/sp_HumanEvents';
 
 
    /*Introduction*/
    SELECT N'allow me to reintroduce myself' AS introduction UNION ALL
    SELECT N'this can be used to start a time-limited extended event session to capture various things:' UNION ALL
    SELECT N'  * blocking' UNION ALL 
    SELECT N'  * query performance and plans' UNION ALL 
    SELECT N'  * query compilations' UNION ALL 
    SELECT N'  * query recompilations' UNION ALL 
    SELECT N'  * wait stats'; 


    /*Limitations*/
    SELECT N'frigid shortcomings' AS limitations UNION ALL
    SELECT N'you need to be on at least SQL Server 2012 or higher to run this' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'sp_HumanEvents is designed to make getting information from common extended events easier. with that in mind,' UNION ALL
    SELECT N'some of the customization is limited, and right now you can''t just choose your own adventure.' UNION ALL    
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'because i don''t want to create files, i''m using the ring buffer, which also has some pesky limitations.' UNION ALL
    SELECT N'https://techcommunity.microsoft.com/t5/sql-server-support/you-may-not-see-the-data-you-expect-in-extended-event-ring/ba-p/315838' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'in order to use the "blocking" session, you must enable the blocked process report' UNION ALL
    SELECT N'https://docs.microsoft.com/en-us/sql/database-engine/configure-windows/blocked-process-threshold-server-configuration-option';   
 
 
    /*Usage*/
    SELECT ap.name AS parameter,
           t.name,
           CASE ap.name WHEN N'@event_type' THEN N'used to pick which session you want to run'
                        WHEN N'@query_duration_ms' THEN N'(>=) used to set a minimum query duration to collect data for'
                        WHEN N'@query_sort_order' THEN 'when you use the "query" event, lets you choose which metrics to sort results by'
                        WHEN N'@blocking_duration_ms' THEN N'(>=) used to set a minimum blocking duration to collect data for'
                        WHEN N'@wait_type' THEN N'(inclusive) filter to only specific wait types'
                        WHEN N'@wait_duration_ms' THEN N'(>=) used to set a minimum time per wait to collect data for'
                        WHEN N'@capture_plans' THEN N'if you also want to capture query plans'
                        WHEN N'@client_app_name' THEN N'(inclusive) filter to only specific app names'
                        WHEN N'@client_hostname' THEN N'(inclusive) filter to only specific host names'
                        WHEN N'@database_name' THEN N'(inclusive) filter to only specific databases'
                        WHEN N'@session_id' THEN N'(inclusive) filter to only a specific session id, or a sample of session ids'
                        WHEN N'@sample_divisor' THEN N'the divisor for session ids when sampling a workload, e.g. SPID % 5'
                        WHEN N'@username' THEN N'(inclusive) filter to only a specific user'
                        WHEN N'@object_name' THEN N'(inclusive) to only filter to a specific object name'
                        WHEN N'@object_schema' THEN N'(inclusive) the schema of the object you want to filter to; only needed with blocking events'
                        WHEN N'@requested_memory_mb' THEN N'(>=) the memory grant a query must ask for to have data collected'
                        WHEN N'@seconds_sample' THEN N'the duration in seconds to run the event session for'
                        WHEN N'@gimme_danger' THEN N'used in some circumstances to override me trying to protect you from yourself'
                        WHEN N'@debug' THEN N'use to print out dynamic SQL'
                        WHEN N'@keep_alive' THEN N'not functional; will eventually be used to create permanent sessions'
                        WHEN N'@help' THEN N'well you''re here so you figured this one out'
                        WHEN N'@version' THEN N'to make sure you have the most recent bits'
                        WHEN N'@versiondate' THEN N'to make sure you have the most recent bits'
                        ELSE N'????' 
           END AS description,
           CASE ap.name WHEN N'@event_type' THEN N'"blocking", "query", "waits", "recompiles", "compiles" and certain variations on those words'
                        WHEN N'@query_duration_ms' THEN N'an integer'
                        WHEN N'@query_sort_order' THEN '"cpu", "reads", "writes", "duration", "memory", "spills"'
                        WHEN N'@blocking_duration_ms' THEN N'an integer'
                        WHEN N'@wait_type' THEN N'a single wait type, or a CSV list of wait types'
                        WHEN N'@wait_duration_ms' THEN N'an integer'
                        WHEN N'@capture_plans' THEN N'1 or 0'
                        WHEN N'@client_app_name' THEN N'a stringy thing'
                        WHEN N'@client_hostname' THEN N'a stringy thing'
                        WHEN N'@database_name' THEN N'a stringy thing'
                        WHEN N'@session_id' THEN N'an integer, or "sample" to sample a workload'
                        WHEN N'@sample_divisor' THEN N'an integer'
                        WHEN N'@username' THEN N'a stringy thing'
                        WHEN N'@object_name' THEN N'a stringy thing'
                        WHEN N'@object_schema' THEN N'a stringy thing'
                        WHEN N'@requested_memory_mb' THEN N'an integer'
                        WHEN N'@seconds_sample' THEN N'an integer'
                        WHEN N'@gimme_danger' THEN N'1 or 0'
                        WHEN N'@debug' THEN N'1 or 0'
                        WHEN N'@keep_alive' THEN N'1 or 0'
                        WHEN N'@help' THEN N'1 or 0'
                        WHEN N'@version' THEN N'none, output'
                        WHEN N'@versiondate' THEN N'none, output'
                        ELSE N'????' 
           END AS valid_inputs,
           CASE ap.name WHEN N'@event_type' THEN N'"query"'
                        WHEN N'@query_duration_ms' THEN N'500 (ms)'
                        WHEN N'@query_sort_order' THEN N'"cpu"'
                        WHEN N'@blocking_duration_ms' THEN N'500 (ms)'
                        WHEN N'@wait_type' THEN N'"all", which uses a list of "interesting" waits'
                        WHEN N'@wait_duration_ms' THEN N'10 (ms)'
                        WHEN N'@capture_plans' THEN N'default is to collect plans'
                        WHEN N'@client_app_name' THEN N'intentionally left blank'
                        WHEN N'@client_hostname' THEN N'intentionally left blank'
                        WHEN N'@database_name' THEN N'intentionally left blank'
                        WHEN N'@session_id' THEN N'intentionally left blank'
                        WHEN N'@sample_divisor' THEN N'5'
                        WHEN N'@username' THEN N'intentionally left blank'
                        WHEN N'@object_name' THEN N'intentionally left blank'
                        WHEN N'@object_schema' THEN N'dbo'
                        WHEN N'@requested_memory_mb' THEN N'0'
                        WHEN N'@seconds_sample' THEN N'10'
                        WHEN N'@gimme_danger' THEN N'0'
                        WHEN N'@keep_alive' THEN N'0'
                        WHEN N'@debug' THEN N'0'
                        WHEN N'@help' THEN N'0'
                        WHEN N'@version' THEN N'none, output'
                        WHEN N'@versiondate' THEN N'none, output'
                        ELSE N'????' 
           END AS defaults
    FROM sys.all_parameters AS ap
    INNER JOIN sys.all_objects AS o
        ON ap.object_id = o.object_id
    INNER JOIN sys.types AS t
        ON  ap.system_type_id = t.system_type_id
        AND ap.user_type_id = t.user_type_id
    WHERE o.name = N'sp_HumanEvents';


    SELECT N'EXAMPLE CALLS' AS example_calls UNION ALL    
    SELECT N'note that not all filters are compatible with all sessions' UNION ALL
    SELECT N'this is handled dynamically, but please don''t think you''re crazy if one "doesn''t work"' UNION ALL
    SELECT N'to capture all types of "completed" queries that have run for at least one second for 20 seconds from a specific database' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'EXEC dbo.sp_HumanEvents @event_type = ''query'', @query_duration_ms = 1000, @seconds_sample = 20, @database_name = ''YourMom'';' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'or that have asked for 1gb of memory' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'EXEC dbo.sp_HumanEvents @event_type = ''query'', @query_duration_ms = 1000, @seconds_sample = 20, @requested_memory_mb = 1024;' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'maybe you want to find unparameterized queries from a poorly written app' UNION ALL
    SELECT N'newer versions will use sql_statement_post_compile, older versions will use uncached_sql_batch_statistics and sql_statement_recompile' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'EXEC dbo.sp_HumanEvents @event_type = ''compilations'', @client_app_name = N''GL00SNIFЯ'', @session_id = ''sample'', @sample_divisor = 3;' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'perhaps you think queries recompiling are the cause of your problems!' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'EXEC dbo.sp_HumanEvents @event_type = ''recompilations'', @seconds_sample = 30;' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'look, blocking is annoying. just turn on RCSI, you goblin.' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'EXEC dbo.sp_HumanEvents @event_type = ''blocking'', @seconds_sample = 60, @blocking_duration_ms = 5000;' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'i mean wait stats are probably a meme but whatever' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'EXEC dbo.sp_HumanEvents @event_type = ''waits'', @wait_duration_ms = 10, @seconds_sample = 100, @wait_type = N''all'';' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'note that THREADPOOL is SOS_WORKER in xe-land. why? i dunno.' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'EXEC dbo.sp_HumanEvents @event_type = ''waits'', @wait_duration_ms = 10, @seconds_sample = 100, @wait_type = N''SOS_WORKER,RESOURCE_SEMAPHORE,YOUR_MOM'';' UNION ALL
    SELECT REPLICATE(N'-', 100);


    /*License to F5*/
    SELECT N'i am MIT licensed, so like, do whatever' AS mit_license_yo UNION ALL
    SELECT N'see printed messages for full license';
    RAISERROR(N'
MIT License

Copyright 2020 Darling Data, LLC https://www.erikdarlingdata.com/

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), 
to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute,
sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the 
following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF 
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE 
FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION 
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
    ', 16, 1) WITH NOWAIT; 

RETURN;
END;

BEGIN TRY

/*
I mean really stop it with the unsupported versions
*/
DECLARE @v DECIMAL(5,0);
SELECT @v =
    SUBSTRING( CONVERT(NVARCHAR(128), SERVERPROPERTY('ProductVersion')), 1,
               CHARINDEX('.', CONVERT(NVARCHAR(128), SERVERPROPERTY('ProductVersion'))) + 1 );
IF @v < 11
    BEGIN
        RAISERROR(N'This darn thing doesn''t seem to work on versions older than 2012.', 16, 1) WITH NOWAIT;
        RETURN;
    END;


/*clean up any old/dormant sessions*/
IF EXISTS
(    
    SELECT 1/0
    FROM sys.server_event_sessions AS s
    LEFT JOIN sys.dm_xe_sessions AS r 
        ON r.name = s.name
    WHERE s.name LIKE 'HumanEvents%'
    AND   ( r.create_time < DATEADD(MINUTE, -2, SYSDATETIME())
    OR      r.create_time IS NULL ) 
)
BEGIN 
    RAISERROR(N'Found old sessions, dropping those.', 0, 1) WITH NOWAIT;
    
    DECLARE @drop_old_sql  NVARCHAR(1000) = N'';
    
    CREATE TABLE #drop_commands (id INT IDENTITY PRIMARY KEY, drop_command NVARCHAR(1000));
    INSERT #drop_commands WITH (TABLOCK) (drop_command)
    SELECT N'DROP EVENT SESSION '  + s.name + N' ON SERVER;'
    FROM sys.server_event_sessions AS s
    LEFT JOIN sys.dm_xe_sessions AS r 
        ON r.name = s.name
    WHERE s.name LIKE N'HumanEvents%'
    AND   ( r.create_time < DATEADD(MINUTE, -2, SYSDATETIME())
    OR      r.create_time IS NULL ); 

    DECLARE drop_cursor CURSOR LOCAL STATIC FOR
    SELECT  drop_command FROM #drop_commands;
    
    OPEN drop_cursor;
    FETCH NEXT FROM drop_cursor 
        INTO @drop_old_sql;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN             
        PRINT @drop_old_sql;
        EXEC(@drop_old_sql);    
        FETCH NEXT FROM drop_cursor 
            INTO @drop_old_sql;
    END;
    
    CLOSE drop_cursor;
    DEALLOCATE drop_cursor;
END;


/*helper variables*/
--How long we let the session run
DECLARE @waitfor NVARCHAR(20) = N'';
--Give sessions super unique names in case more than one person uses it at a time
DECLARE @session_name NVARCHAR(100) = REPLACE(N'HumanEvents' + @event_type + CONVERT(NVARCHAR(36), NEWID()), N'-', N''); 
--Universal, yo
DECLARE @session_with NVARCHAR(MAX) = N'    
ADD TARGET package0.ring_buffer
        ( SET max_memory = 102400 )
WITH
        (
            MAX_MEMORY = 102400KB,
            EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS,
            MAX_DISPATCH_LATENCY = 5 SECONDS,
            MAX_EVENT_SIZE = 0KB,
            MEMORY_PARTITION_MODE = PER_CPU,
            TRACK_CAUSALITY = OFF,
            STARTUP_STATE = OFF
        );' + NCHAR(10);
--I guess we need to do this, too
DECLARE @session_sql NVARCHAR(MAX) = N'
CREATE EVENT SESSION ' + @session_name + N'
    ON SERVER ';

-- STOP. DROP. SHUT'EM DOWN OPEN UP SHOP.
DECLARE @start_sql NVARCHAR(MAX) = N'ALTER EVENT SESSION ' + @session_name + N' ON SERVER STATE = START;' + NCHAR(10);
DECLARE @stop_sql  NVARCHAR(MAX) = N'ALTER EVENT SESSION ' + @session_name + N' ON SERVER STATE = STOP;' + NCHAR(10);
DECLARE @drop_sql  NVARCHAR(MAX) = N'DROP EVENT SESSION '  + @session_name + N' ON SERVER;' + NCHAR(10);


/*Some sessions can use all general filters*/
DECLARE @session_filter NVARCHAR(MAX) = NCHAR(10) + N'            sqlserver.is_system = 0 ' + NCHAR(10);
/*Others can't use all of them, like app and host name*/
DECLARE @session_filter_limited NVARCHAR(MAX) = NCHAR(10) + N'            sqlserver.is_system = 0 ' + NCHAR(10);
/*batch_completed is especially limited, it can't even use object name*/
DECLARE @session_filter_batch_completed NVARCHAR(MAX) = NCHAR(10) + N'            sqlserver.is_system = 0 ' + NCHAR(10);
/*query plans can filter on requested memory, too, along with the limited filters*/
DECLARE @session_filter_query_plans NVARCHAR(MAX) = NCHAR(10) + N'            sqlserver.is_system = 0 ' + NCHAR(10);
/*only wait stats can filter on wait types, but can filter on everything else*/
DECLARE @session_filter_waits NVARCHAR(MAX) = NCHAR(10) + N'            sqlserver.is_system = 0 ' + NCHAR(10);
/*only wait stats can filter on wait types, but can filter on everything else*/
DECLARE @session_filter_recompile NVARCHAR(MAX) = NCHAR(10) + N'            sqlserver.is_system = 0 ' + NCHAR(10);
/*sql_statement_completed can do everything except object name*/
DECLARE @session_filter_statement_completed NVARCHAR(MAX) = NCHAR(10) + N'            sqlserver.is_system = 0 ' + NCHAR(10);
/*for blocking because blah blah*/
DECLARE @session_filter_blocking NVARCHAR(MAX) = NCHAR(10) + N'         sqlserver.is_system = 1 ' + NCHAR(10);
/*for parameterization because blah blah*/
DECLARE @session_filter_parameterization NVARCHAR(MAX) = NCHAR(10) + N'            sqlserver.is_system = 0 ' + NCHAR(10);

/*
Create one filter per possible input.
This allows us to construct specific filters later.
*/
DECLARE @query_duration_filter NVARCHAR(MAX) = N'';
DECLARE @blocking_duration_ms_filter NVARCHAR(MAX) = N'';
DECLARE @wait_type_filter NVARCHAR(MAX) = N'';
DECLARE @wait_duration_filter NVARCHAR(MAX) = N'';
DECLARE @client_app_name_filter NVARCHAR(MAX) = N'';
DECLARE @client_hostname_filter NVARCHAR(MAX) = N'';
DECLARE @database_name_filter NVARCHAR(MAX) = N'';
DECLARE @session_id_filter NVARCHAR(MAX) = N'';
DECLARE @username_filter NVARCHAR(MAX) = N'';
DECLARE @object_name_filter NVARCHAR(MAX) = N'';
DECLARE @requested_memory_mb_filter NVARCHAR(MAX) = N'';

--Determines if we use the new event or the old event(s) to track compiles
DECLARE @compile_events BIT = 0;
IF EXISTS
(
    SELECT 1/0 
    FROM sys.dm_xe_objects AS dxo 
    WHERE dxo.name = N'sql_statement_post_compile'
)
BEGIN 
    SET @compile_events = 1; 
END;

DECLARE @parameterization_events BIT = 0;
IF EXISTS
(
    SELECT 1/0 
    FROM sys.dm_xe_objects AS dxo 
    WHERE dxo.name = N'query_parameterization_data'
)
BEGIN 
    SET @parameterization_events = 1; 
END;


 /*
 You know what I don't wanna deal with? NULLs.
 */
 SET @event_type      = ISNULL(@event_type, N'');
 SET @client_app_name = ISNULL(@client_app_name, N'');
 SET @client_hostname = ISNULL(@client_hostname, N'');
 SET @database_name   = ISNULL(@database_name, N'');
 SET @session_id      = ISNULL(@session_id, N'');
 SET @username        = ISNULL(@username, N'');
 SET @object_name     = ISNULL(@object_name, N'');
 SET @object_schema   = ISNULL(@object_schema, N'');

 /*I'm also very forgiving of some white space*/
 SET @database_name = RTRIM(LTRIM(@database_name));

 DECLARE @fully_formed_babby NVARCHAR(1000) = @database_name + N'.' + @object_schema + N'.' + @object_name;

/*
Some sanity checking
*/

--You can only do this right now.
IF @event_type NOT IN 
        ( N'waits',
          N'blocking',
          N'locking',
          N'queries',
          N'compiles',
          N'recompiles',
          N'wait',
          N'block',
          N'blocks',
          N'lock',
          N'lock',
          N'query',
          N'compile',
          N'recompile',
          N'compilation',
          N'recompilation',
          N'compilations',
          N'recompilations' )
BEGIN
    RAISERROR(N'you have chosen a value for @event_type... poorly. use @help = 1 to see valid arguments.', 16, 1) WITH NOWAIT;
    RETURN;
END;

--Set these durations to non-crazy numbers unless someone asks for @gimme_danger = 1
IF ( LOWER(@event_type) LIKE N'%quer%' AND @event_type NOT LIKE N'%comp%' --ignore compile and recompile because this is a filter on query compilation time 🙄
     AND @gimme_danger = 0 )
     AND (@query_duration_ms < 500 OR @query_duration_ms IS NULL )
BEGIN
    RAISERROR(N'you chose a really dangerous value for @query_duration', 0, 1) WITH NOWAIT;
    RAISERROR(N'if you really want that, please set @gimme_danger = 1, and re-run', 0, 1) WITH NOWAIT;
    RAISERROR(N'setting @query_duration to 500', 16, 1) WITH NOWAIT;
    SET @query_duration_ms = 500;
END;

IF ( LOWER(@event_type) LIKE N'%wait%' 
     AND @gimme_danger = 0 )
     AND (@wait_duration_ms < 10 OR @wait_duration_ms IS NULL ) 
BEGIN
    RAISERROR(N'you chose a really dangerous value for @wait_duration_ms', 0, 1) WITH NOWAIT;
    RAISERROR(N'if you really want that, please set @gimme_danger = 1, and re-run', 0, 1) WITH NOWAIT;
    RAISERROR(N'setting @wait_duration_ms to 10', 16, 1) WITH NOWAIT;
    SET @wait_duration_ms = 10;
END;

IF ( LOWER(@event_type) LIKE N'%lock%' 
     AND @gimme_danger = 0 )
     AND (@blocking_duration_ms < 500 OR @blocking_duration_ms IS NULL ) 
BEGIN
    RAISERROR(N'you chose a really dangerous value for @blocking_duration_ms', 0, 1) WITH NOWAIT;
    RAISERROR(N'if you really want that, please set @gimme_danger = 1, and re-run', 0, 1) WITH NOWAIT;
    RAISERROR(N'setting @blocking_duration_ms to 500', 16, 1) WITH NOWAIT;
    SET @blocking_duration_ms = 500;
END;

IF @query_sort_order NOT IN (N'cpu', N'reads', N'writes', N'duration', N'memory', N'spills')
BEGIN
   RAISERROR(N'that sort order you chose is so out of this world that i''m ignoring it', 0, 1) WITH NOWAIT;
   SET @query_sort_order = N'cpu';
END;



--This will hold the CSV list of wait types someone passes in
CREATE TABLE #user_waits(wait_type NVARCHAR(60));
INSERT #user_waits
SELECT waits.wait_type
FROM
(
    SELECT wait_type = x.x.value('(./text())[1]', 'NVARCHAR(60)')
    FROM 
    ( 
      SELECT wait_type = CONVERT(XML, N'<x>' 
                         + REPLACE(REPLACE(@wait_type, N',', N'</x><x>'), N' ', N'') 
                         + N'</x>').query('.')
    ) AS w 
        CROSS APPLY wait_type.nodes('x') AS x(x)
) AS waits
WHERE @wait_type <> N'all';

/*
If someone is passing in specific waits, let's make sure that
they're valid waits by checking them against what's available.
*/
IF @wait_type <> N'all'
BEGIN

    SET @wait_type = REPLACE(@wait_type, N'THREADPOOL', N'SOS_WORKER');

    SELECT DISTINCT uw.wait_type AS invalid_waits
    INTO #invalid_waits
    FROM #user_waits AS uw
    WHERE NOT EXISTS
    (
        SELECT 1/0
        FROM sys.dm_xe_map_values AS dxmv
        WHERE  dxmv.map_value COLLATE Latin1_General_BIN = uw.wait_type COLLATE Latin1_General_BIN
        AND    dxmv.name = N'wait_types'
    );
    
    IF @@ROWCOUNT > 0    
    BEGIN
        SELECT N'You have chosen some invalid wait types' AS invalid_waits
        UNION ALL
        SELECT iw.invalid_waits
        FROM #invalid_waits AS iw;
        RETURN;
    END;

END;


/*
If someone is passing in non-blank values, let's try to limit our SQL injection exposure a little bit
*/
IF 
    ( @client_app_name <> N''
      OR @client_hostname <> N''
      OR @database_name <> N''
      OR @session_id <> N''
      OR @username <> N''
      OR @object_name <> N''
      OR @object_name <> N'dbo')
BEGIN

    CREATE TABLE #papers_please(ahem sysname);
    INSERT #papers_please
    SELECT UPPER(pp.ahem)
    FROM (
    VALUES
        (@client_app_name),
        (@client_hostname),
        (@database_name),
        (@session_id),
        (@username),
        (@object_name),
        (@object_schema)
    ) AS pp (ahem)
    WHERE pp.ahem <> N''
    AND   pp.ahem <> N'dbo';

    IF EXISTS
    (
        SELECT 1/0
        FROM #papers_please AS pp
        WHERE pp.ahem LIKE N'%SELECT%'
        OR    pp.ahem LIKE N'%INSERT%'
        OR    pp.ahem LIKE N'%UPDATE%'
        OR    pp.ahem LIKE N'%DELETE%'
        OR    pp.ahem LIKE N'%DROP%'
        OR    pp.ahem LIKE N'%EXEC%'
        OR    pp.ahem LIKE N'%BACKUP%'
        OR    pp.ahem LIKE N'%RESTORE%'
        OR    pp.ahem LIKE N'%ALTER%'
        OR    pp.ahem LIKE N'%CREATE%'
        OR    pp.ahem LIKE N'%SHUTDOWN%'
        OR    pp.ahem LIKE N'%DBCC%'
        OR    pp.ahem LIKE N'%CONFIGURE%'
    )

    BEGIN
        RAISERROR(N'Say... you wouldn''t happen to be trying some funny business, would you?', 16, 1) WITH NOWAIT;
        RETURN;
    END;

END;


/*
I just don't want anyone to be disappointed
*/
IF ( @wait_type <> N'' AND @wait_type <> N'all' AND LOWER(@event_type) NOT LIKE N'%wait%' AND LOWER(@event_type) NOT LIKE N'%all%' )
BEGIN
    RAISERROR(N'You can''t filter on wait stats unless you use the wait stats event.', 16, 1) WITH NOWAIT;
    RETURN;
END;

/*
This is probably important, huh?
*/
IF ( LOWER(@event_type) LIKE N'%lock%' AND DB_ID(@database_name) IS NULL AND @object_name <> N'' )
BEGIN
    RAISERROR(N'The blocking event can only filter on an object_id, and we need a valid @database_name to resolve it correctly.', 16, 1) WITH NOWAIT;
    RETURN;
END;

IF ( LOWER(@event_type) LIKE N'%lock%' AND @object_name <> N'' AND OBJECT_ID(@fully_formed_babby) IS NULL )
BEGIN
    RAISERROR(N'we couldn''t find the object you''re trying to ', 16, 1) WITH NOWAIT;
    RETURN;
END;


IF @event_type LIKE N'%lock%'
AND  EXISTS
(
    SELECT 1/0
    FROM sys.configurations AS c
    WHERE c.name = N'blocked process threshold (s)'
    AND CONVERT(INT, c.value_in_use) = 0
)
BEGIN
        RAISERROR(N'You need to set up the blocked process report in order to use this:
    EXEC sys.sp_configure ''show advanced options'', 1;
    GO
    RECONFIGURE
    GO
    EXEC sys.sp_configure ''blocked process threshold'', 5; --Seconds of blocking before a report is generated
    GO
    RECONFIGURE
    GO', 1, 0) WITH NOWAIT;
    RETURN;
END;

IF @database_name <> N''
BEGIN
    IF DB_ID(@database_name) IS NULL
    BEGIN
        RAISERROR(N'it looks like you''re looking for a database that doesn''t wanna be looked for -- check that spelling!', 16, 1) WITH NOWAIT;
        RETURN;
    END;
END;

IF LOWER(@session_id) NOT LIKE N'%sample%' AND @session_id LIKE '%[^0-9]%' AND LOWER(@session_id) <> N''
BEGIN
   RAISERROR(N'that @session_id doesn''t look proper. double check that for me.', 16, 1) WITH NOWAIT;
   RETURN;
END;

IF @sample_divisor < 2
BEGIN
    RAISERROR(N'@sample_divisor is used to divide session @session_id when taking a sample of a workload.', 16, 1) WITH NOWAIT;
    RAISERROR(N'we can''t really divide by zero, and dividing by 1 would be uh... bad.', 16, 1) WITH NOWAIT;
    RETURN;
END;

IF @username NOT IN 
(
    SELECT sp.name
    FROM sys.server_principals AS sp
    LEFT JOIN sys.sql_logins AS sl
        ON sp.principal_id = sl.principal_id
    WHERE sp.type NOT IN ( 'G', 'R' ) 
    AND   sp.is_disabled = 0
) AND @username <> N''
BEGIN
    RAISERROR(N'that username doesn''t exist in sys.server_principals', 16, 1) WITH NOWAIT;
    RETURN;
END;



/*
We need to do some seconds math here, because WAITFOR is very stupid
*/
IF @seconds_sample > 1
BEGIN
DECLARE @math INT = 0;
SET @math = @seconds_sample / 60;
    
    --I really don't want this running for more than 10 minutes right now.
    IF ( @math > 9 AND @gimme_danger = 0 )
    BEGIN
        RAISERROR(N'Yeah nah not more than 10 minutes', 16, 1) WITH NOWAIT;
        RAISERROR(N'(unless you set @gimme_danger = 1)', 16, 1) WITH NOWAIT;
        RETURN;
    END;
    
    --Fun fact: running WAITFOR DELAY '00:00:60.000' throws an error
    -- If we have over 60 seconds, we need to populate the minutes section
    IF ( @math < 10 AND @math >= 1 )
    BEGIN
        DECLARE @minutes INT;
        DECLARE @seconds INT;
        SET @minutes = @seconds_sample / 60;
        SET @seconds = @seconds_sample % 60;
        SET @waitfor = N'00:' 
                     + CONVERT(NVARCHAR(11), RIGHT(N'00' + RTRIM(@minutes), 2))
                     + N':'
                     + CONVERT(NVARCHAR(11), RIGHT(N'00' + RTRIM(@seconds), 2))
                     + N'.000';
    END;
    
    --Only if we have 59 seconds or less can we use seconds only
    IF ( @math = 0 )
    BEGIN
        DECLARE @seconds_ INT;        
        SET @seconds_ = @seconds_sample % 60;        
        SET @waitfor = N'00:' 
                     + N'00'
                     + N':'
                     + CONVERT(NVARCHAR(11), RIGHT(N'00' + RTRIM(@seconds_), 2))
                     + N'.000';        
    END;
END;


/*
Start setting up individual filters
*/

IF @query_duration_ms > 0
BEGIN
    IF LOWER(@event_type) NOT LIKE N'%comp%'
    BEGIN
        SET @query_duration_filter += N'     AND duration >= ' + CONVERT(NVARCHAR(20), (@query_duration_ms * 1000)) + NCHAR(10);
    END;
END;

IF @blocking_duration_ms > 0
BEGIN
    SET @blocking_duration_ms_filter += N'     AND duration >= ' + CONVERT(NVARCHAR(20), (@blocking_duration_ms * 1000)) + NCHAR(10);
END;

IF @wait_duration_ms > 0
BEGIN
    SET @wait_duration_filter += N'     AND duration >= ' + CONVERT(NVARCHAR(20), (@wait_duration_ms)) + NCHAR(10);
END;

IF @client_app_name <> N''
BEGIN
    SET @client_app_name_filter += N'     AND sqlserver.client_app_name = N' + QUOTENAME(@client_app_name, '''') + NCHAR(10);
END;

IF @client_hostname <> N''
BEGIN
    SET @client_hostname_filter += N'     AND sqlserver.client_hostname = N' + QUOTENAME(@client_hostname, '''') + NCHAR(10);
END;

IF @database_name <> N''
BEGIN
    IF LOWER(@event_type) NOT LIKE N'%lock%'
    BEGIN
        SET @database_name_filter += N'     AND sqlserver.database_name = N' + QUOTENAME(@database_name, '''') + NCHAR(10);
    END;
    IF LOWER(@event_type) LIKE N'%lock%'
    BEGIN
        SET @database_name_filter += N'     AND database_name = N' + QUOTENAME(@database_name, '''') + NCHAR(10);
    END;
END;

IF @session_id <> N''
BEGIN
    IF LOWER(@session_id) NOT LIKE N'%sample%'
        BEGIN
            SET @session_id_filter += N'     AND sqlserver.session_id = ' + CONVERT(NVARCHAR(11), @session_id) + NCHAR(10);
        END;
    IF LOWER(@session_id) LIKE N'%sample%'
        BEGIN
            SET @session_id_filter += N'     AND package0.divides_by_uint64(sqlserver.session_id, ' + CONVERT(NVARCHAR(11), @sample_divisor) + N') ' + NCHAR(10);
        END;
END;

IF @username <> N''
BEGIN
    SET @username_filter += N'     AND sqlserver.username = N' + QUOTENAME(@username, '''') + NCHAR(10);
END;

IF @object_name <> N''
BEGIN
    IF @event_type LIKE N'%lock%'
    BEGIN
        DECLARE @object_id sysname;
        SET @object_id = OBJECT_ID(@fully_formed_babby);
        SET @object_name_filter += N'     AND object_id = ' + @object_id;
    END;
    IF @event_type NOT LIKE N'%lock%'
    BEGIN
        SET @object_name_filter += N'     AND object_name = N' + QUOTENAME(@object_name, '''') + NCHAR(10);
    END;
END;

IF @requested_memory_mb > 0
BEGIN
    DECLARE @requested_memory_kb NVARCHAR(11) = @requested_memory_mb / 1024.;
    SET @requested_memory_mb_filter += N'     AND requested_memory_kb >= ' + @requested_memory_kb + NCHAR(10);
END;

--At this point we'll either put my list of interesting waits in a temp table, 
--or a list of user defined waits
IF LOWER(@event_type) LIKE N'%wait%'
BEGIN
    CREATE TABLE #wait(wait_type sysname);
    
    INSERT #wait( wait_type )
    SELECT x.wait_type
    FROM (
    VALUES 
        (N'LCK_M_SCH_S'), 
        (N'LCK_M_SCH_M'), 
        (N'LCK_M_S'),
        (N'LCK_M_U'), 
        (N'LCK_M_X'), 
        (N'LCK_M_IS'),
        (N'LCK_M_IU'), 
        (N'LCK_M_IX'), 
        (N'LCK_M_SIU'),
        (N'LCK_M_SIX'), 
        (N'LCK_M_UIX'), 
        (N'LCK_M_BU'),
        (N'LCK_M_RS_S'), 
        (N'LCK_M_RS_U'), 
        (N'LCK_M_RIn_NL'),
        (N'LCK_M_RIn_S'), 
        (N'LCK_M_RIn_U'),
        (N'LCK_M_RIn_X'), 
        (N'LCK_M_RX_S'), 
        (N'LCK_M_RX_U'),
        (N'LCK_M_RX_X'), 
        (N'LATCH_NL'), 
        (N'LATCH_KP'),
        (N'LATCH_SH'), 
        (N'LATCH_UP'), 
        (N'LATCH_EX'),
        (N'LATCH_DT'), 
        (N'PAGELATCH_NL'), 
        (N'PAGELATCH_KP'),
        (N'PAGELATCH_SH'), 
        (N'PAGELATCH_UP'),
        (N'PAGELATCH_EX'), 
        (N'PAGELATCH_DT'),
        (N'PAGEIOLATCH_NL'), 
        (N'PAGEIOLATCH_KP'),
        (N'PAGEIOLATCH_SH'), 
        (N'PAGEIOLATCH_UP'),
        (N'PAGEIOLATCH_EX'), 
        (N'PAGEIOLATCH_DT'),
        (N'IO_COMPLETION'), 
        (N'ASYNC_IO_COMPLETION'),
        (N'NETWORK_IO'),
        (N'WRITE_COMPLETION'), 
        (N'RESOURCE_SEMAPHORE'),
        (N'RESOURCE_SEMAPHORE_QUERY_COMPILE'),
        (N'RESOURCE_SEMAPHORE_MUTEX'),
        (N'CMEMTHREAD'), 
        (N'CXCONSUMER'),
        (N'CXPACKET'),
        (N'EXECSYNC'),
        (N'SOS_WORKER'),
        (N'SOS_SCHEDULER_YIELD'), 
        (N'LOGBUFFER'),
        (N'WRITELOG') 
    ) AS x (wait_type)
    WHERE @wait_type = N'all'
        
    UNION ALL
    
    SELECT uw.wait_type
    FROM #user_waits AS uw
    WHERE @wait_type <> N'all';
    
    --This section creates a dynamic WHERE clause based on wait types
    --The problem is that wait type IDs change frequently, which sucks.
    WITH     maps
              AS ( SELECT   dxmv.map_key,
                            dxmv.map_value,
                            dxmv.map_key
                            - ROW_NUMBER() OVER ( ORDER BY dxmv.map_key ) AS rn
                   FROM     sys.dm_xe_map_values AS dxmv
                   WHERE    dxmv.name = N'wait_types'
                            AND dxmv.map_value IN (SELECT w.wait_type FROM #wait AS w)
                    ),
            grps
              AS ( SELECT   MIN(maps.map_key) AS minkey,
                            MAX(maps.map_key) AS maxkey
                   FROM     maps
                   GROUP BY maps.rn)
         SELECT @wait_type_filter += SUBSTRING(( SELECT N'      AND  (('
                                                 + STUFF((SELECT N'         OR '
                                                                 + CASE WHEN grps.minkey < grps.maxkey
                                                                        THEN + N'(wait_type >= '
                                                                             + CAST(grps.minkey AS NVARCHAR(11))
                                                                             + N' AND wait_type <= '
                                                                             + CAST(grps.maxkey AS NVARCHAR(11))
                                                                             + N')' + CHAR(10)
                                                                        ELSE N'(wait_type = '
                                                                             + CAST(grps.minkey AS NVARCHAR(11))
                                                                             + N')'  + NCHAR(10)
                                                                   END
                                                          FROM   grps
                                                     FOR XML PATH(''), TYPE).value('.[1]', 'NVARCHAR(MAX)')
                                             , 1, 13, N'') ), 0,
                                          8000) + N')';
END; 


--This section sets event-dependent filters

/*For full filter-able sessions*/
SET @session_filter += ( ISNULL(@query_duration_filter, N'') +
                         ISNULL(@client_app_name_filter, N'') +
                         ISNULL(@client_hostname_filter, N'') +
                         ISNULL(@database_name_filter, N'') +
                         ISNULL(@session_id_filter, N'') +
                         ISNULL(@username_filter, N'') +
                         ISNULL(@object_name_filter, N'') );

/*For waits specifically, because they also need to filter on wait type and wait duration*/
SET @session_filter_waits += ( ISNULL(@wait_duration_filter, N'') +
                               ISNULL(@wait_type_filter, N'') +
                               ISNULL(@client_app_name_filter, N'') +
                               ISNULL(@client_hostname_filter, N'') +
                               ISNULL(@database_name_filter, N'') +
                               ISNULL(@session_id_filter, N'') +
                               ISNULL(@username_filter, N'') +
                               ISNULL(@object_name_filter, N'') );

/*For sessions that can't filter on client app or host name*/
SET @session_filter_limited += ( ISNULL(@query_duration_filter, N'') +
                                 ISNULL(@database_name_filter, N'') +
                                 ISNULL(@session_id_filter, N'') +
                                 ISNULL(@username_filter, N'') +
                                 ISNULL(@object_name_filter, N'') );

/*For query plans, which can also filter on memory required*/
SET @session_filter_query_plans += ( ISNULL(@query_duration_filter, N'') +
                                     ISNULL(@database_name_filter, N'') +
                                     ISNULL(@session_id_filter, N'') +
                                     ISNULL(@username_filter, N'') +
                                     ISNULL(@object_name_filter, N'') +
                                     ISNULL(@requested_memory_mb_filter, N'') );

/*Specific for batch completed, because it is a blah*/
SET @session_filter_batch_completed += ( ISNULL(@query_duration_filter, N'') +
                                         ISNULL(@database_name_filter, N'') +
                                         ISNULL(@session_id_filter, N'') +
                                         ISNULL(@username_filter, N'') );

/*Recompile can have almost everything except... duration.*/
SET @session_filter_recompile += ( ISNULL(@client_app_name_filter, N'') +
                                   ISNULL(@client_hostname_filter, N'') +
                                   ISNULL(@database_name_filter, N'') +
                                   ISNULL(@session_id_filter, N'') +
                                   ISNULL(@object_name_filter, N'') +
                                   ISNULL(@username_filter, N'')  );

/*Apparently statement completed can't filter on an object name so that's fun*/
SET @session_filter_statement_completed += ( ISNULL(@query_duration_filter, N'') +
                                             ISNULL(@client_app_name_filter, N'') +
                                             ISNULL(@client_hostname_filter, N'') +
                                             ISNULL(@database_name_filter, N'') +
                                             ISNULL(@session_id_filter, N'') +
                                             ISNULL(@username_filter, N'') );

/*Blocking woighoiughuohaeripugbapiouergb*/
SET @session_filter_blocking += ( ISNULL(@blocking_duration_ms_filter, N'') +
                                  ISNULL(@database_name_filter, N'') +
                                  ISNULL(@session_id_filter, N'') +
                                  ISNULL(@username_filter, N'') +
                                  ISNULL(@object_name_filter, N'') +
                                  ISNULL(@requested_memory_mb_filter, N'') );

/*The parameterization event is pretty limited in weird ways*/
SET @session_filter_parameterization += ( ISNULL(@client_app_name_filter, N'') +
                                          ISNULL(@client_hostname_filter, N'') +
                                          ISNULL(@database_name_filter, N'') +
                                          ISNULL(@session_id_filter, N'') +
                                          ISNULL(@username_filter, N'') );

--This section sets up the event session definition
SET @session_sql += 
    CASE WHEN LOWER(@event_type) LIKE N'%lock%'
         THEN N' 
  ADD EVENT sqlserver.blocked_process_report 
    (WHERE ( ' + @session_filter_blocking + N' ))'
         WHEN LOWER(@event_type) LIKE N'%quer%'
         THEN N' 
  ADD EVENT sqlserver.module_end 
    (SET collect_statement = 1
    ACTION (sqlserver.database_name, sqlserver.sql_text, sqlserver.plan_handle, sqlserver.query_hash_signed, sqlserver.query_plan_hash_signed)
     WHERE ( ' + @session_filter + N' )),
  ADD EVENT sqlserver.rpc_completed 
    (SET collect_statement = 1
    ACTION(sqlserver.database_name, sqlserver.sql_text, sqlserver.plan_handle, sqlserver.query_hash_signed, sqlserver.query_plan_hash_signed)
     WHERE ( ' + @session_filter + N' )),
  ADD EVENT sqlserver.sp_statement_completed 
     (SET collect_object_name = 1, collect_statement = 1
      ACTION(sqlserver.database_name, sqlserver.sql_text, sqlserver.plan_handle, sqlserver.query_hash_signed, sqlserver.query_plan_hash_signed) 
      WHERE ( ' + @session_filter + N' )),
  ADD EVENT sqlserver.sql_batch_completed 
    (SET collect_batch_text = 1
    ACTION(sqlserver.database_name, sqlserver.sql_text, sqlserver.plan_handle, sqlserver.query_hash_signed, sqlserver.query_plan_hash_signed)
    WHERE ( ' + @session_filter_batch_completed + N' )),
  ADD EVENT sqlserver.sql_statement_completed 
   (SET collect_statement = 1
    ACTION(sqlserver.database_name, sqlserver.sql_text, sqlserver.plan_handle, sqlserver.query_hash_signed, sqlserver.query_plan_hash_signed)
    WHERE ( ' + @session_filter_statement_completed + N' ))'            
            + CASE WHEN @capture_plans = 1 
              THEN N',
  ADD EVENT sqlserver.query_post_execution_showplan
    (
    ACTION(sqlserver.database_name, sqlserver.sql_text, sqlserver.plan_handle, sqlserver.query_hash_signed, sqlserver.query_plan_hash_signed)
    WHERE ( ' + @session_filter_query_plans + N' ))'
              ELSE N''
              END
         WHEN LOWER(@event_type) LIKE N'%wait%' AND @v > 11
         THEN N' 
  ADD EVENT sqlos.wait_completed
    (SET collect_wait_resource = 1
    ACTION (sqlserver.database_name, sqlserver.plan_handle, sqlserver.query_hash_signed, sqlserver.query_plan_hash_signed)
    WHERE ( ' + @session_filter_waits + N' ))'
         WHEN LOWER(@event_type) LIKE N'%wait%' AND @v = 11
         THEN N' 
  ADD EVENT sqlos.wait_info
    (ACTION (sqlserver.database_name, sqlserver.plan_handle, sqlserver.query_hash_signed, sqlserver.query_plan_hash_signed)
     WHERE ( ' + @session_filter_waits + N' ))'
         WHEN LOWER(@event_type) LIKE N'%recomp%'
         THEN CASE WHEN @compile_events = 1
         THEN N' 
  ADD EVENT sqlserver.sql_statement_post_compile 
    (SET collect_object_name = 1, collect_statement = 1
    ACTION(sqlserver.database_name)
    WHERE ( ' + @session_filter + N' ))'
             ELSE N' 
  ADD EVENT sqlserver.sql_statement_recompile 
    (SET collect_object_name = 1, collect_statement = 1
    ACTION(sqlserver.database_name)
    WHERE ( ' + @session_filter_recompile + N' ))'
             END
        WHEN (LOWER(@event_type) LIKE N'%comp%' AND LOWER(@event_type) NOT LIKE N'%re%')
        THEN CASE WHEN @compile_events = 1
             THEN N' 
  ADD EVENT sqlserver.sql_statement_post_compile 
    (SET collect_object_name = 1, collect_statement = 1
    ACTION(sqlserver.database_name)
    WHERE ( ' + @session_filter + N' ))'
             ELSE N'
  ADD EVENT sqlserver.uncached_sql_batch_statistics(
    ACTION(sqlserver.database_name)
    WHERE ( ' + @session_filter_recompile + N' )),             
  ADD EVENT sqlserver.sql_statement_recompile 
    (SET collect_object_name = 1, collect_statement = 1
    ACTION(sqlserver.database_name)
    WHERE ( ' + @session_filter_recompile + N' ))'
            END
            + CASE WHEN @parameterization_events = 1
            THEN N',
  ADD EVENT sqlserver.query_parameterization_data(
    ACTION (sqlserver.database_name, sqlserver.plan_handle, sqlserver.sql_text)
    WHERE ( ' + @session_filter_parameterization + N' ))'
             ELSE N''
             END 
        ELSE N'i have no idea what i''m doing.'
    END;
               

--This creates the event session
SET @session_sql += @session_with;
    IF @debug = 1 BEGIN RAISERROR(@session_sql, 0, 1) WITH NOWAIT; END;
EXEC (@session_sql);

--This starts the event session
IF @debug = 1 BEGIN RAISERROR(@start_sql, 0, 1) WITH NOWAIT; END;
EXEC (@start_sql);


--NOW WE WAIT, MR. BOND
WAITFOR DELAY @waitfor;

--Dump whatever we got into a temp table
SELECT CONVERT(XML, human_events_xml.human_events_xml) AS human_events_xml
INTO #human_events_xml
FROM ( SELECT CONVERT(XML, t.target_data) AS human_events_xml
       FROM sys.dm_xe_session_targets AS t
       JOIN sys.dm_xe_sessions AS s
           ON s.address = t.event_session_address
       WHERE s.name = @session_name 
       AND   t.target_name = N'ring_buffer') AS human_events_xml;

IF @debug = 1
BEGIN
    SELECT N'#human_events_xml' AS table_name, * FROM #human_events_xml AS hex;
END;


/*
This is where magic will happen
*/

IF LOWER(@event_type) LIKE N'%quer%'
BEGIN;
         WITH queries AS 
         (
            SELECT DATEADD(MINUTE, DATEDIFF(MINUTE, GETUTCDATE(), SYSDATETIME()), c.value('@timestamp', 'DATETIME2')) AS event_time,
                   c.value('@name', 'NVARCHAR(256)') AS event_type,
                   c.value('(action[@name="database_name"]/value)[1]', 'NVARCHAR(256)') AS database_name,                
                   c.value('(data[@name="object_name"]/value)[1]', 'NVARCHAR(256)') AS [object_name],
                   c.value('(data[@name="batch_text"]/value)[1]', 'NVARCHAR(MAX)') AS batch_text,
                   c.value('(action[@name="sql_text"]/value)[1]', 'NVARCHAR(MAX)') AS sql_text,
                   c.value('(data[@name="statement"]/value)[1]', 'NVARCHAR(MAX)') AS statement,
                   c.query('(data[@name="showplan_xml"]/value/*)[1]') AS [showplan_xml],
                   c.value('(data[@name="cpu_time"]/value)[1]', 'INT') / 1000. AS cpu_ms,
                  (c.value('(data[@name="logical_reads"]/value)[1]', 'INT') * 8) / 1024. AS logical_reads,
                  (c.value('(data[@name="physical_reads"]/value)[1]', 'INT') * 8) / 1024. AS physical_reads,
                   c.value('(data[@name="duration"]/value)[1]', 'INT') / 1000. AS duration_ms,
                  (c.value('(data[@name="writes"]/value)[1]', 'INT') * 8) / 1024. AS writes,
                  (c.value('(data[@name="spills"]/value)[1]', 'INT') * 8) / 1024. AS spills_mb,
                   c.value('(data[@name="row_count"]/value)[1]', 'INT') AS row_count,
                   c.value('(data[@name="estimated_rows"]/value)[1]', 'INT') AS estimated_rows,
                   c.value('(data[@name="dop"]/value)[1]', 'INT') AS dop,
                   c.value('(data[@name="serial_ideal_memory_kb"]/value)[1]', 'BIGINT') / 1024. AS serial_ideal_memory_mb,
                   c.value('(data[@name="requested_memory_kb"]/value)[1]', 'BIGINT') / 1024. AS requested_memory_mb,
                   c.value('(data[@name="used_memory_kb"]/value)[1]', 'BIGINT') / 1024. AS used_memory_mb,
                   c.value('(data[@name="ideal_memory_kb"]/value)[1]', 'BIGINT') / 1024. AS ideal_memory_mb,
                   c.value('(data[@name="granted_memory_kb"]/value)[1]', 'BIGINT') / 1024. AS granted_memory_mb,
                   CONVERT(BINARY(8), c.value('(action[@name="query_plan_hash_signed"]/value)[1]', 'BIGINT')) AS query_plan_hash_signed,
                   CONVERT(BINARY(8), c.value('(action[@name="query_hash_signed"]/value)[1]', 'BIGINT')) AS query_hash_signed,
                   c.value('xs:hexBinary((action[@name="plan_handle"]/value/text())[1])', 'VARBINARY(64)') AS plan_handle
            FROM #human_events_xml AS xet
            OUTER APPLY xet.human_events_xml.nodes('//event') AS oa(c)
         )
         SELECT *
         INTO #queries
         FROM queries AS q
         WHERE ( q.object_name <> N'sp_HumanEvents'
                 OR q.object_name IS NULL )
         OPTION (RECOMPILE);
         
         IF @debug = 1 BEGIN SELECT * FROM #queries AS q OPTION (RECOMPILE); END;


         SELECT MIN(q.event_time) AS event_time,
                COUNT_BIG(*) AS executions,
                /*totals*/
                SUM(ISNULL(q.cpu_ms, 0.)) AS total_cpu_ms,
                SUM(ISNULL(q.logical_reads, 0.)) AS total_logical_reads,
                SUM(ISNULL(q.physical_reads, 0.)) AS total_physical_reads,
                SUM(ISNULL(q.duration_ms, 0.)) AS total_duration_ms,
                SUM(ISNULL(q.writes, 0.)) AS total_writes,
                SUM(ISNULL(q.spills_mb, 0.)) AS total_spills_mb,
                SUM(ISNULL(q.used_memory_mb, 0.)) AS total_used_memory_mb,
                SUM(ISNULL(q.granted_memory_mb, 0.)) AS total_granted_memory_mb,
                /*averages*/
                SUM(ISNULL(q.cpu_ms, 0.)) / COUNT_BIG(*) AS avg_cpu_ms,
                SUM(ISNULL(q.logical_reads, 0.)) / COUNT_BIG(*) AS avg_logical_reads,
                SUM(ISNULL(q.physical_reads, 0.)) / COUNT_BIG(*) AS avg_physical_reads,
                SUM(ISNULL(q.duration_ms, 0.)) / COUNT_BIG(*) AS avg_duration_ms,
                SUM(ISNULL(q.writes, 0.)) / COUNT_BIG(*) AS avg_writes,
                SUM(ISNULL(q.spills_mb, 0.)) / COUNT_BIG(*) AS avg_spills_mb,
                SUM(ISNULL(q.used_memory_mb, 0.)) / COUNT_BIG(*) AS avg_used_memory_mb,
                SUM(ISNULL(q.granted_memory_mb, 0.)) / COUNT_BIG(*) AS avg_granted_memory_mb,
                MAX(ISNULL(q.row_count, 0)) AS row_count,
                    q.query_plan_hash_signed,
                    q.query_hash_signed,
                    q.plan_handle
         INTO #totals
         FROM #queries AS q
         GROUP BY q.query_plan_hash_signed,
                  q.query_hash_signed,
                  q.plan_handle
         OPTION (RECOMPILE);

         
         IF @debug = 1 BEGIN SELECT * FROM #totals AS t OPTION (RECOMPILE); END;


         SELECT q.event_time,
                q.database_name,
                q.object_name,
                q2.batch_statement_text,
                q.sql_text,
                q.showplan_xml,
                t.executions,
                t.total_cpu_ms,
                t.avg_cpu_ms,
                t.total_logical_reads,
                t.avg_logical_reads,
                t.total_physical_reads,
                t.avg_physical_reads,
                t.total_duration_ms,
                t.avg_duration_ms,
                t.total_writes,
                t.avg_writes,
                t.total_spills_mb,
                t.avg_spills_mb,
                t.total_used_memory_mb,
                t.total_granted_memory_mb,
                t.avg_used_memory_mb,
                t.avg_granted_memory_mb,
                q.serial_ideal_memory_mb,
                q.requested_memory_mb,
                q.ideal_memory_mb,
                t.row_count,
                q.estimated_rows,
                q.dop,
                q.query_plan_hash_signed,
                q.query_hash_signed,
                q.plan_handle
         FROM #queries AS q
         JOIN #totals AS t
             ON  q.query_hash_signed = t.query_hash_signed
             AND q.query_plan_hash_signed = t.query_plan_hash_signed
             AND q.plan_handle = t.plan_handle
             AND q.event_time = t.event_time
         CROSS APPLY
         (
             SELECT TOP (1) 
                        ISNULL(q2.batch_text, q2.statement) AS batch_statement_text
             FROM #queries AS q2
             WHERE q.query_hash_signed = q2.query_hash_signed
             AND   q.query_plan_hash_signed = q2.query_plan_hash_signed
             AND   q.plan_handle = q2.plan_handle
             AND   q.event_time = q2.event_time
             AND   ISNULL(q2.batch_text, q2.statement) IS NOT NULL
             ORDER BY q2.event_time DESC
         ) AS q2
         WHERE q.showplan_xml.exist('*') = 1
         ORDER BY CASE @query_sort_order
                       WHEN N'cpu' THEN q.cpu_ms
                       WHEN N'reads' THEN q.logical_reads + q.physical_reads
                       WHEN N'writes' THEN q.writes
                       WHEN N'duration' THEN q.duration_ms
                       WHEN N'spills' THEN q.spills_mb
                       WHEN N'memory' THEN q.granted_memory_mb
                       ELSE N'cpu'
                  END DESC
         OPTION (RECOMPILE);
END
;


IF LOWER(@event_type) LIKE N'%comp%' AND LOWER(@event_type) NOT LIKE N'%re%'
BEGIN

IF @compile_events = 1
    BEGIN
            SELECT DATEADD(MINUTE, DATEDIFF(MINUTE, GETUTCDATE(), SYSDATETIME()), c.value('@timestamp', 'DATETIME2')) AS event_time,
                   c.value('@name', 'NVARCHAR(256)') AS event_type,
                   c.value('(action[@name="database_name"]/value)[1]', 'NVARCHAR(256)') AS database_name,                
                   c.value('(data[@name="object_name"]/value)[1]', 'NVARCHAR(256)') AS [object_name],
                   c.value('(data[@name="statement"]/value)[1]', 'NVARCHAR(MAX)') AS statement_text,
                   c.value('(data[@name="is_recompile"]/value)[1]', 'BIT') AS is_recompile,
                   c.value('(data[@name="cpu_time"]/value)[1]', 'INT') compile_cpu_ms,
                   c.value('(data[@name="duration"]/value)[1]', 'INT') compile_duration_ms
            FROM #human_events_xml AS xet
            OUTER APPLY xet.human_events_xml.nodes('//event') AS oa(c)
            WHERE c.exist('(data[@name="is_recompile"]/value[.="false"])') = 1
            AND   c.value('@name', 'NVARCHAR(256)') = N'sql_statement_post_compile'
            ORDER BY event_time
            OPTION (RECOMPILE);
    END;

IF @compile_events = 0
    BEGIN
            SELECT DATEADD(MINUTE, DATEDIFF(MINUTE, GETUTCDATE(), SYSDATETIME()), c.value('@timestamp', 'DATETIME2')) AS event_time,
                   c.value('@name', 'NVARCHAR(256)') AS event_type,
                   c.value('(action[@name="database_name"]/value)[1]', 'NVARCHAR(256)') AS database_name,                
                   c.value('(data[@name="object_name"]/value)[1]', 'NVARCHAR(256)') AS [object_name],
                   c.value('(data[@name="statement"]/value)[1]', 'NVARCHAR(MAX)') AS statement_text
            FROM #human_events_xml AS xet
            OUTER APPLY xet.human_events_xml.nodes('//event') AS oa(c)
            ORDER BY event_time
            OPTION (RECOMPILE);
    END;

IF @parameterization_events  = 1
    BEGIN

            SELECT DATEADD(MINUTE, DATEDIFF(MINUTE, GETUTCDATE(), SYSDATETIME()), c.value('@timestamp', 'DATETIME2')) AS event_time,
                   c.value('@name', 'NVARCHAR(256)') AS event_type,
                   c.value('(action[@name="database_name"]/value)[1]', 'NVARCHAR(256)') AS database_name,                
                   c.value('(action[@name="sql_text"]/value)[1]', 'NVARCHAR(256)') AS sql_text,
                   c.value('(data[@name="compile_cpu_time"]/value)[1]', 'BIGINT') / 1000. AS compile_cpu_time_ms,
                   c.value('(data[@name="compile_duration"]/value)[1]', 'BIGINT') / 1000. AS compile_duration_ms,
                   c.value('(data[@name="query_param_type"]/value)[1]', 'INT') AS query_param_type,
                   c.value('(data[@name="is_cached"]/value)[1]', 'BIT') AS is_cached,
                   c.value('(data[@name="is_recompiled"]/value)[1]', 'BIT') AS is_recompiled,
                   c.value('(data[@name="compile_code"]/text)[1]', 'NVARCHAR(256)') AS compile_code,                  
                   c.value('(data[@name="has_literals"]/value)[1]', 'BIT') AS has_literals,
                   c.value('(data[@name="is_parameterizable"]/value)[1]', 'BIT') AS is_parameterizable,
                   c.value('(data[@name="parameterized_values_count"]/value)[1]', 'BIGINT') AS parameterized_values_count,
                   c.value('xs:hexBinary((data[@name="query_plan_hash"]/value/text())[1])', 'BINARY(8)') AS query_plan_hash,
                   c.value('xs:hexBinary((data[@name="query_hash"]/value/text())[1])', 'BINARY(8)') AS query_hash,
                   c.value('xs:hexBinary((action[@name="plan_handle"]/value/text())[1])', 'VARBINARY(64)') AS plan_handle, 
                   c.value('xs:hexBinary((data[@name="statement_sql_hash"]/value/text())[1])', 'VARBINARY(64)') AS statement_sql_hash
            FROM #human_events_xml AS xet
            OUTER APPLY xet.human_events_xml.nodes('//event') AS oa(c)
            WHERE c.value('@name', 'NVARCHAR(256)') = N'query_parameterization_data'
            ORDER BY event_time
            OPTION (RECOMPILE);
    END;


END;


IF LOWER(@event_type) LIKE N'%recomp%'
BEGIN

IF @compile_events = 1
    BEGIN
            SELECT DATEADD(MINUTE, DATEDIFF(MINUTE, GETUTCDATE(), SYSDATETIME()), c.value('@timestamp', 'DATETIME2')) AS event_time,
                   c.value('@name', 'NVARCHAR(256)') AS event_type,
                   c.value('(action[@name="database_name"]/value)[1]', 'NVARCHAR(256)') AS database_name,                
                   c.value('(data[@name="object_name"]/value)[1]', 'NVARCHAR(256)') AS [object_name],
                   c.value('(data[@name="statement"]/value)[1]', 'NVARCHAR(MAX)') AS statement_text,
                   c.value('(data[@name="is_recompile"]/value)[1]', 'BIT') AS is_recompile,
                   c.value('(data[@name="cpu_time"]/value)[1]', 'INT') / 1000. AS compile_cpu_ms,
                   c.value('(data[@name="duration"]/value)[1]', 'INT') / 1000. AS compile_duration_ms
            FROM #human_events_xml AS xet
            OUTER APPLY xet.human_events_xml.nodes('//event') AS oa(c)
            WHERE c.exist('(data[@name="is_recompile"]/value[.="false"])') = 0
            ORDER BY event_time
            OPTION (RECOMPILE);
    END;

IF @compile_events = 0
    BEGIN
            SELECT DATEADD(MINUTE, DATEDIFF(MINUTE, GETUTCDATE(), SYSDATETIME()), c.value('@timestamp', 'DATETIME2')) AS event_time,
                   c.value('@name', 'NVARCHAR(256)') AS event_type,
                   c.value('(action[@name="database_name"]/value)[1]', 'NVARCHAR(256)') AS database_name,                
                   c.value('(data[@name="object_name"]/value)[1]', 'NVARCHAR(256)') AS [object_name],
                   c.value('(data[@name="statement"]/value)[1]', 'NVARCHAR(MAX)') AS statement_text,
                   c.value('(data[@name="recompile_cause"]/text)[1]', 'NVARCHAR(256)') AS recompile_cause
            FROM #human_events_xml AS xet
            OUTER APPLY xet.human_events_xml.nodes('//event') AS oa(c)
            WHERE c.exist('(data[@name="is_recompile"]/value[.="false"])') = 0
            ORDER BY event_time
            OPTION (RECOMPILE);
    END;
END;


IF LOWER(@event_type) LIKE N'%wait%'
BEGIN;

WITH waits AS (
            SELECT DATEADD(MINUTE, DATEDIFF(MINUTE, GETUTCDATE(), SYSDATETIME()), c.value('@timestamp', 'DATETIME2')) AS event_time,
                   c.value('@name', 'NVARCHAR(256)') AS event_type,
                   c.value('(action[@name="database_name"]/value)[1]', 'NVARCHAR(256)') AS database_name,                
                   c.value('(data[@name="wait_type"]/text)[1]', 'NVARCHAR(256)') AS wait_type,
                   c.value('(data[@name="duration"]/value)[1]', 'BIGINT')  AS duration_ms,
                   c.value('(data[@name="signal_duration"]/value)[1]', 'BIGINT') AS signal_duration_ms,
                   CASE WHEN @v = 11 THEN N'Not Available < 2014' ELSE c.value('(data[@name="wait_resource"]/value)[1]', 'NVARCHAR(256)') END AS wait_resource,
                   CONVERT(BINARY(8), c.value('(action[@name="query_plan_hash_signed"]/value)[1]', 'BIGINT')) AS query_plan_hash_signed,
                   CONVERT(BINARY(8), c.value('(action[@name="query_hash_signed"]/value)[1]', 'BIGINT')) AS query_hash_signed,
                   c.value('xs:hexBinary((action[@name="plan_handle"]/value/text())[1])', 'VARBINARY(64)') AS plan_handle
            FROM #human_events_xml AS xet
            OUTER APPLY xet.human_events_xml.nodes('//event') AS oa(c)
            WHERE (c.exist('(data[@name="duration"]/value[. > 0])') = 1 OR @gimme_danger = 1)
            )
            SELECT *
            INTO #waits_agg
            FROM waits
            OPTION(RECOMPILE);
            
            IF @debug = 1 BEGIN SELECT * FROM #waits_agg AS wa; END;

            SELECT 'total_waits' AS wait_pattern,
                   MIN(wa.event_time) AS min_event_time,
                   MAX(wa.event_time) AS max_event_time,
                   wa.wait_type,
                   COUNT_BIG(*) AS total_waits,
                   SUM(wa.duration_ms) AS sum_duration_ms,
                   SUM(wa.signal_duration_ms) AS sum_signal_duration_ms,
                   SUM(wa.duration_ms) / COUNT_BIG(*) AS avg_ms_per_wait
            FROM #waits_agg AS wa
            GROUP BY wa.wait_type
            ORDER BY sum_duration_ms DESC
            OPTION (RECOMPILE);            

            SELECT 'total_waits_by_database' AS wait_pattern,
                   MIN(wa.event_time) AS min_event_time,
                   MAX(wa.event_time) AS max_event_time,
                   wa.database_name,
                   wa.wait_type,
                   COUNT_BIG(*) AS total_waits,
                   SUM(wa.duration_ms) AS sum_duration_ms,
                   SUM(wa.signal_duration_ms) AS sum_signal_duration_ms,
                   SUM(wa.duration_ms) / COUNT_BIG(*) AS avg_ms_per_wait
            FROM #waits_agg AS wa
            GROUP BY wa.database_name, wa.wait_type
            ORDER BY sum_duration_ms DESC
            OPTION (RECOMPILE); 

            WITH plan_waits AS (
            SELECT 'waits by query' AS wait_pattern,
                   MIN(wa.event_time) AS min_event_time,
                   MAX(wa.event_time) AS max_event_time,
                   wa.wait_type,
                   COUNT_BIG(*) AS total_waits,
                   wa.plan_handle,
                   wa.query_plan_hash_signed,
                   wa.query_hash_signed,
                   SUM(wa.duration_ms) AS sum_duration_ms,
                   SUM(wa.signal_duration_ms) AS sum_signal_duration_ms,
                   SUM(wa.duration_ms) / COUNT_BIG(*) AS avg_ms_per_wait
            FROM #waits_agg AS wa
            GROUP BY wa.wait_type, 
                     wa.query_hash_signed, 
                     wa.query_plan_hash_signed, 
                     wa.plan_handle
            
            )
            SELECT pw.wait_pattern,
                   pw.min_event_time,
                   pw.max_event_time,
                   pw.wait_type,
                   pw.total_waits,
                   pw.sum_duration_ms,
                   pw.sum_signal_duration_ms,
                   pw.avg_ms_per_wait,
                   qp.query_plan,
                   st.text
            FROM plan_waits AS pw
            OUTER APPLY sys.dm_exec_query_plan(pw.plan_handle) AS qp
            OUTER APPLY sys.dm_exec_sql_text(pw.plan_handle) AS st
            ORDER BY pw.sum_duration_ms DESC
            OPTION (RECOMPILE);
END;


IF LOWER(@event_type) LIKE N'%lock%'
BEGIN

            SELECT DATEADD(MINUTE, DATEDIFF(MINUTE, GETUTCDATE(), SYSDATETIME()), c.value('@timestamp', 'DATETIME2')) AS event_time,        
                   DB_NAME(c.value('(data[@name="database_id"]/value)[1]', 'INT')) AS database_name,
                   c.value('(data[@name="database_id"]/value)[1]', 'INT') AS database_id,
                   c.value('(data[@name="object_id"]/value)[1]', 'INT') AS object_id,
                   c.value('(data[@name="transaction_id"]/value)[1]', 'BIGINT') AS transaction_id,
                   c.value('(data[@name="resource_owner_type"]/text)[1]', 'NVARCHAR(256)') AS resource_owner_type,
                   c.value('(//@monitorLoop)[1]', 'INT') AS monitor_loop,
                   bd.value('(process/@spid)[1]', 'INT') AS blocked_spid,
                   bd.value('(process/@ecid)[1]', 'INT') AS blocked_ecid,
                   bd.value('(process/inputbuf/text())[1]', 'NVARCHAR(MAX)') AS blocked_text,
                   bd.value('(process/@waittime)[1]', 'NVARCHAR(100)') AS blocked_waittime,
                   bd.value('(process/@transactionname)[1]', 'NVARCHAR(100)') AS blocked_transactionname,
                   bd.value('(process/@lasttranstarted)[1]', 'NVARCHAR(100)') AS blocked_lasttranstarted,
                   bd.value('(process/@lockMode)[1]', 'NVARCHAR(100)') AS blocked_lockmode,
                   bd.value('(process/@status)[1]', 'NVARCHAR(100)') AS blocked_status,
                   bd.value('(process/@priority)[1]', 'NVARCHAR(100)') AS blocked_priority,
                   bd.value('(process/@trancount)[1]', 'NVARCHAR(100)') AS blocked_trancount,
                   bd.value('(process/@clientapp)[1]', 'NVARCHAR(100)') AS blocked_clientapp,
                   bd.value('(process/@hostname)[1]', 'NVARCHAR(100)') AS blocked_hostname,
                   bd.value('(process/@loginname)[1]', 'NVARCHAR(100)') AS blocked_loginname,
                   bd.value('(process/@isolationlevel)[1]', 'NVARCHAR(100)') AS blocked_isolationlevel,
                   bd.value('(process/executionStack/frame/@sqlhandle)[1]', 'NVARCHAR(100)') AS blocked_sqlhandle,
                   bd.value('(process/executionStack/frame/@stmtstart)[1]', 'INT') AS blocked_stmtstart,
                   bd.value('(process/executionStack/frame/@stmtend)[1]', 'INT') AS blocked_stmtend,
                   c.query('.') AS blocked_process_report
            INTO #blocked
            FROM #human_events_xml AS xet
            OUTER APPLY xet.human_events_xml.nodes('//event') AS oa(c)
            OUTER APPLY oa.c.nodes('//blocked-process-report/blocked-process') AS bd(bd)
            OPTION (RECOMPILE);


            SELECT DATEADD(MINUTE, DATEDIFF(MINUTE, GETUTCDATE(), SYSDATETIME()), c.value('@timestamp', 'DATETIME2')) AS event_time,        
                   DB_NAME(c.value('(data[@name="database_id"]/value)[1]', 'INT')) AS database_name,
                   c.value('(data[@name="database_id"]/value)[1]', 'INT') AS database_id,
                   c.value('(data[@name="object_id"]/value)[1]', 'INT') AS object_id,
                   c.value('(data[@name="transaction_id"]/value)[1]', 'BIGINT') AS transaction_id,
                   c.value('(data[@name="resource_owner_type"]/text)[1]', 'NVARCHAR(256)') AS resource_owner_type,
                   c.value('(//@monitorLoop)[1]', 'INT') AS monitor_loop,
                   bg.value('(process/@spid)[1]', 'INT') AS blocking_spid,
                   bg.value('(process/@ecid)[1]', 'INT') AS blocking_ecid,
                   bg.value('(process/inputbuf/text())[1]', 'NVARCHAR(MAX)') AS blocking_blocking_text,
                   bg.value('(process/@status)[1]', 'NVARCHAR(100)') AS blocking_status,
                   bg.value('(process/@priority)[1]', 'NVARCHAR(100)') AS blocking_priority,
                   bg.value('(process/@trancount)[1]', 'NVARCHAR(100)') AS blocking_trancount,
                   bg.value('(process/@clientapp)[1]', 'NVARCHAR(100)') AS blocking_clientapp,
                   bg.value('(process/@hostname)[1]', 'NVARCHAR(100)') AS blocking_hostname,
                   bg.value('(process/@loginname)[1]', 'NVARCHAR(100)') AS blocking_loginname,
                   bg.value('(process/@isolationlevel)[1]', 'NVARCHAR(100)') AS blocking_isolationlevel,
                   c.query('.') AS blocked_process_report
            INTO #blocking
            FROM #human_events_xml AS xet
            OUTER APPLY xet.human_events_xml.nodes('//event') AS oa(c)
            OUTER APPLY oa.c.nodes('//blocked-process-report/blocking-process') AS bg(bg)
            OPTION (RECOMPILE);

           WITH pablo_blanco AS
            (
               SELECT DISTINCT
                      b.event_time,
                      b.object_id,
                      b.transaction_id,
                      b.monitor_loop,
                      b.blocking_spid,
                      b.blocking_ecid
               FROM #blocking AS b

               UNION ALL 
                
               SELECT x.event_time,
                      x.object_id,
                      x.transaction_id,
                      x.monitor_loop,
                      x.blocked_spid,
                      x.blocked_ecid
               FROM (
               SELECT b.event_time,
                      b.object_id,
                      b.transaction_id,
                      b.monitor_loop,
                      b.blocked_spid,
                      b.blocked_ecid,
                      ROW_NUMBER() OVER 
                        ( PARTITION BY b.event_time, b.object_id, b.transaction_id, b.monitor_loop, b.blocked_spid, b.blocked_ecid
                          ORDER BY     b.event_time, b.object_id, b.transaction_id, b.monitor_loop, b.blocked_spid, b.blocked_ecid ) AS n
               FROM #blocked AS b
               JOIN pablo_blanco AS p
                   ON p.event_time = b.event_time
                   AND p.object_id = b.object_id
                   AND p.monitor_loop = b.monitor_loop
                   AND p.blocking_spid <> b.blocked_spid
               ) AS x
               WHERE x.n = 1
            ), 
            and_another_thing AS 
           (
            SELECT bg.event_time,
                   bg.database_name,
                   OBJECT_NAME(bg.object_id, bg.database_id) AS contentious_object,
                   1 AS ordering,
                   N'blocking' AS activity,
                   bg.blocking_spid AS spid,
                   bg.blocking_blocking_text AS query_text,
                   0 AS wait_time,
                   bg.blocking_status AS status,
                   bg.blocking_isolationlevel AS isolation_level,
                   'unknown' AS last_transaction_startted,
                   'unknown' AS transaction_name,
                   'unknown' AS lock_mode,
                   bg.blocking_priority AS priority,
                   bg.blocking_trancount AS transaction_count,
                   bg.blocking_clientapp AS client_app,
                   bg.blocking_hostname AS host_name,
                   bg.blocking_loginname AS login_name,
                   bg.blocked_process_report 
                   FROM pablo_blanco AS pb
                   CROSS APPLY(SELECT TOP 1 * FROM #blocking AS b WHERE b.blocking_spid = pb.blocking_spid) AS bg

                   UNION ALL 

            SELECT bl.event_time,
                   bl.database_name,
                   OBJECT_NAME(bl.object_id, bl.database_id) AS contentious_object,
                   2 AS ordering,
                   N'blocked' AS activity,
                   bl.blocked_spid,
                   bl.blocked_text,
                   bl.blocked_waittime,
                   bl.blocked_status,
                   bl.blocked_isolationlevel,
                   CONVERT(NVARCHAR(30), bl.blocked_lasttranstarted, 127),
                   bl.blocked_transactionname,
                   bl.blocked_lockmode,
                   bl.blocked_priority,
                   bl.blocked_trancount,
                   bl.blocked_clientapp,
                   bl.blocked_hostname,
                   bl.blocked_loginname,
                   bl.blocked_process_report
                   FROM pablo_blanco AS pb
                   CROSS APPLY(SELECT TOP 1 * FROM #blocked AS b WHERE b.blocked_spid = pb.blocking_spid) AS bl
            )
           SELECT att.event_time,
                  att.database_name,
                  att.contentious_object,
                  att.activity,
                  att.spid,
                  att.query_text,
                  att.wait_time,
                  att.status,
                  att.isolation_level,
                  att.last_transaction_startted,
                  att.transaction_name,
                  att.lock_mode,
                  att.priority,
                  att.transaction_count,
                  att.client_app,
                  att.host_name,
                  att.login_name,
                  att.blocked_process_report 
           FROM and_another_thing AS att
           ORDER BY att.event_time, att.ordering
           OPTION(RECOMPILE);

END;


--Stop the event session
IF @debug = 1 BEGIN RAISERROR(@stop_sql, 0, 1) WITH NOWAIT; END;
EXEC (@stop_sql);

--Drop the event session
IF @debug = 1 BEGIN RAISERROR(@drop_sql, 0, 1) WITH NOWAIT; END;
EXEC (@drop_sql);

END TRY
BEGIN CATCH
    BEGIN
    
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    
    DECLARE @msg NVARCHAR(2048) = N'';
    SELECT @msg += N'Error number '
          + RTRIM(ERROR_NUMBER()) 
          + N' with severity '
          + RTRIM(ERROR_SEVERITY()) 
          + N' and a state of '
          + RTRIM(ERROR_STATE()) 
          + N' in procedure ' 
          + ERROR_PROCEDURE() 
          + N' on line '  
          + RTRIM(ERROR_LINE())
          + N' '
          + ERROR_MESSAGE(); 
          
        RAISERROR (@msg, 16, 1) WITH NOWAIT;

        --Stop the event session
        IF @debug = 1 BEGIN RAISERROR(@stop_sql, 0, 1) WITH NOWAIT; END;
        EXEC (@stop_sql);
        
        --Drop the event session
        IF @debug = 1 BEGIN RAISERROR(@drop_sql, 0, 1) WITH NOWAIT; END;
        EXEC (@drop_sql);

        RETURN -138;
    END;
END CATCH;

END;
