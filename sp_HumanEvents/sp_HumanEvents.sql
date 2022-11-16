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

Copyright 2022 Darling Data, LLC
https://www.erikdarlingdata.com/

For usage and licensing details, run:
EXEC sp_HumanEvents
    @help = 1;

For working through errors:
EXEC sp_HumanEvents
    @debug = 1;

For support, head over to GitHub:
https://github.com/erikdarlingdata/DarlingData    

*/

IF OBJECT_ID('dbo.sp_HumanEvents') IS NULL
   BEGIN
       EXEC ('CREATE PROCEDURE dbo.sp_HumanEvents AS RETURN 138;');
   END;
GO

ALTER PROCEDURE 
    dbo.sp_HumanEvents
( 
    @event_type sysname = N'query',
    @query_duration_ms integer = 500,
    @query_sort_order nvarchar(10) = N'cpu',
    @blocking_duration_ms integer = 500,
    @wait_type nvarchar(4000) = N'ALL',
    @wait_duration_ms integer = 10,
    @client_app_name sysname = N'',
    @client_hostname sysname = N'',
    @database_name sysname = N'',
    @session_id nvarchar(7) = N'',
    @sample_divisor integer = 5,
    @username sysname = N'',
    @object_name sysname = N'',
    @object_schema sysname = N'dbo', 
    @requested_memory_mb integer = 0,
    @seconds_sample integer = 10,
    @gimme_danger bit = 0,
    @keep_alive bit = 0,
    @custom_name nvarchar(256) = N'',
    @output_database_name sysname = N'',
    @output_schema_name sysname = N'dbo',
    @delete_retention_days integer = 3,
    @cleanup bit = 0,
    @max_memory_kb bigint = 102400,
    @version varchar(30) = NULL OUTPUT,
    @version_date datetime = NULL OUTPUT,
    @debug bit = 0,
    @help bit = 0 
)
AS
BEGIN

SET STATISTICS XML OFF;
SET NOCOUNT, XACT_ABORT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

SELECT 
    @version = '3.33', 
    @version_date = '20220701';

IF @help = 1
BEGIN
    /*Warnings, I guess*/
    SELECT [WARNING WARNING WARNING] = 
        N'warning! achtung! peligro! chardonnay!' UNION ALL 
    SELECT N'misuse of this procedure can harm performance' UNION ALL
    SELECT N'be very careful about introducing observer overhead, especially when gathering query plans' UNION ALL
    SELECT N'be even more careful when setting up permanent sessions!' UNION ALL
    SELECT N'for additional support: http://bit.ly/sp_HumanEvents';
 
 
    /*Introduction*/
    SELECT
        introduction = N'allow me to reintroduce myself' UNION ALL
    SELECT N'this can be used to start a time-limited extended event session to capture various things:' UNION ALL
    SELECT N'  * blocking' UNION ALL 
    SELECT N'  * query performance and plans' UNION ALL 
    SELECT N'  * compilations' UNION ALL 
    SELECT N'  * recompilations' UNION ALL 
    SELECT N'  * wait stats'; 


    /*Limitations*/
    SELECT
        limitations = N'frigid shortcomings' UNION ALL
    SELECT N'you need to be on at least SQL Server 2012 SP4 or higher to run this' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'if your version isn''t patched to where query_hash_signed is an available xe action, this won''t run' UNION ALL
    SELECT N'sp_HumanEvents is designed to make getting information from common extended events easier. with that in mind,' UNION ALL
    SELECT N'some of the customization is limited, and right now you can''t just choose your own adventure.' UNION ALL    
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'because i don''t want to create files, i''m using the ring buffer, which also has some pesky limitations.' UNION ALL
    SELECT N'https://techcommunity.microsoft.com/t5/sql-server-support/you-may-not-see-the-data-you-expect-in-extended-event-ring/ba-p/315838' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'in order to use the "blocking" session, you must enable the blocked process report' UNION ALL
    SELECT N'https://docs.microsoft.com/en-us/sql/database-engine/configure-windows/blocked-process-threshold-server-configuration-option';   
 
 
    /*Usage*/
    SELECT 
        parameter = 
            ap.name,
        t.name,
        description = 
            CASE ap.name WHEN N'@event_type' THEN N'used to pick which session you want to run'
                         WHEN N'@query_duration_ms' THEN N'(>=) used to set a minimum query duration to collect data for'
                         WHEN N'@query_sort_order' THEN 'when you use the "query" event, lets you choose which metrics to sort results by'
                         WHEN N'@blocking_duration_ms' THEN N'(>=) used to set a minimum blocking duration to collect data for'
                         WHEN N'@wait_type' THEN N'(inclusive) filter to only specific wait types'
                         WHEN N'@wait_duration_ms' THEN N'(>=) used to set a minimum time per wait to collect data for'
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
                         WHEN N'@gimme_danger' THEN N'used to override default minimums for query, wait, and blocking durations. only use if you''re okay with potentially adding a lot of observer overhead on your system, or for testing purposes.'
                         WHEN N'@debug' THEN N'use to print out dynamic SQL'
                         WHEN N'@keep_alive' THEN N'creates a permanent session, either to watch live or log to a table from'
                         WHEN N'@custom_name' THEN N'if you want to custom name a permanent session'
                         WHEN N'@output_database_name' THEN N'the database you want to log data to'
                         WHEN N'@output_schema_name' THEN N'the schema you want to log data to'
                         WHEN N'@delete_retention_days' THEN N'how many days of logged data you want to keep'
                         WHEN N'@cleanup' THEN N'deletes all sessions, tables, and views. requires output database and schema.'
                         WHEN N'@max_memory_kb' THEN N'set a max ring buffer size to log data to'
                         WHEN N'@help' THEN N'well you''re here so you figured this one out'
                         WHEN N'@version' THEN N'to make sure you have the most recent bits'
                         WHEN N'@version_date' THEN N'to make sure you have the most recent bits'
                         ELSE N'????' 
            END,
        valid_inputs = 
           CASE ap.name WHEN N'@event_type' THEN N'"blocking", "query", "waits", "recompiles", "compiles" and certain variations on those words'
                        WHEN N'@query_duration_ms' THEN N'an integer'
                        WHEN N'@query_sort_order' THEN '"cpu", "reads", "writes", "duration", "memory", "spills", and you can add "avg" to sort by averages, e.g. "avg cpu"'
                        WHEN N'@blocking_duration_ms' THEN N'an integer'
                        WHEN N'@wait_type' THEN N'a single wait type, or a CSV list of wait types'
                        WHEN N'@wait_duration_ms' THEN N'an integer'
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
                        WHEN N'@custom_name' THEN N'a stringy thing'
                        WHEN N'@output_database_name' THEN N'a valid database name'
                        WHEN N'@output_schema_name' THEN N'a valid schema'
                        WHEN N'@delete_retention_days' THEN N'a POSITIVE integer'
                        WHEN N'@cleanup' THEN N'1 or 0'
                        WHEN N'@max_memory_kb' THEN N'an integer'
                        WHEN N'@help' THEN N'1 or 0'
                        WHEN N'@version' THEN N'none, output'
                        WHEN N'@version_date' THEN N'none, output'
                        ELSE N'????' 
           END,
        defaults = 
           CASE ap.name WHEN N'@event_type' THEN N'"query"'
                        WHEN N'@query_duration_ms' THEN N'500 (ms)'
                        WHEN N'@query_sort_order' THEN N'"cpu"'
                        WHEN N'@blocking_duration_ms' THEN N'500 (ms)'
                        WHEN N'@wait_type' THEN N'"all", which uses a list of "interesting" waits'
                        WHEN N'@wait_duration_ms' THEN N'10 (ms)'
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
                        WHEN N'@custom_name' THEN N'intentionally left blank'
                        WHEN N'@output_database_name' THEN N'intentionally left blank'
                        WHEN N'@output_schema_name' THEN N'dbo'
                        WHEN N'@delete_retention_days' THEN N'3 (days)'
                        WHEN N'@debug' THEN N'0'
                        WHEN N'@cleanup' THEN N'0'
                        WHEN N'@max_memory_kb' THEN N'102400'
                        WHEN N'@help' THEN N'0'
                        WHEN N'@version' THEN N'none, output'
                        WHEN N'@version_date' THEN N'none, output'
                        ELSE N'????' 
           END 
    FROM sys.all_parameters AS ap
    JOIN sys.all_objects AS o
        ON ap.object_id = o.object_id
    JOIN sys.types AS t
        ON  ap.system_type_id = t.system_type_id
        AND ap.user_type_id = t.user_type_id
    WHERE o.name = N'sp_HumanEvents';


    /*Example calls*/
    SELECT 
        example_calls = N'EXAMPLE CALLS' UNION ALL    
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
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'to set up a permanent session for compiles, but you can specify any of the session types here' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL    
    SELECT N'EXEC sp_HumanEvents @event_type = N''compiles'', @debug = 1, @keep_alive = 1;' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'to log to a database named whatever, and a schema called dbo' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL    
    SELECT N'EXEC sp_HumanEvents @debug = 1, @output_database_name = N''whatever'', @output_schema_name = N''dbo'';' UNION ALL
    SELECT REPLICATE(N'-', 100);


    /*Views*/
    SELECT 
        views_and_stuff = N'views that get created when you log to tables' UNION ALL
    SELECT N'these will get created in the same database that your output tables get created in for simplicity' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'HumanEvents_Queries: View to look at data pulled from logged queries' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'HumanEvents_WaitsByQueryAndDatabase: waits generated grouped by query and database. this is best effort, as the query grouping relies on them being present in the plan cache' UNION ALL
    SELECT N'HumanEvents_WaitsByDatabase: waits generated grouped by database' UNION ALL
    SELECT N'HumanEvents_WaitsTotal: total waits' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'HumanEvents_Blocking: view to assemble blocking chains' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'HumanEvents_CompilesByDatabaseAndObject: compiles by database and object' UNION ALL
    SELECT N'HumanEvents_CompilesByQuery: compiles by query' UNION ALL
    SELECT N'HumanEvents_CompilesByDuration: compiles by duration length' UNION ALL
    SELECT N'HumanEvents_Compiles_Legacy: compiles on older versions that don''t support new events' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'HumanEvents_Parameterization: data collected from the parameterization event' UNION ALL
    SELECT REPLICATE(N'-', 100) UNION ALL
    SELECT N'HumanEvents_RecompilesByDatabaseAndObject: recompiles by database and object' UNION ALL
    SELECT N'HumanEvents_RecompilesByQuery: recompiles by query' UNION ALL
    SELECT N'HumanEvents_RecompilesByDuration: recompiles by long duration' UNION ALL
    SELECT N'HumanEvents_Recompiles_Legacy: recompiles on older versions that don''t support new events' UNION ALL
    SELECT REPLICATE(N'-', 100);


    /*License to F5*/
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

BEGIN TRY

CREATE TABLE
    #x
(
    x xml
);

CREATE TABLE 
    #drop_commands 
( 
    id integer IDENTITY PRIMARY KEY, 
    drop_command nvarchar(1000) 
);

CREATE TABLE 
    #user_waits
(
    wait_type nvarchar(60)
);

CREATE TABLE 
    #papers_please
(
    ahem sysname
);

CREATE TABLE 
    #human_events_xml_internal 
(
    human_events_xml xml
);  

CREATE TABLE 
    #wait
(
    wait_type sysname
);

CREATE TABLE 
    #human_events_worker
(
    id integer NOT NULL PRIMARY KEY IDENTITY,
    event_type sysname NOT NULL,
    event_type_short sysname NOT NULL,
    is_table_created bit NOT NULL DEFAULT 0,
    is_view_created bit NOT NULL DEFAULT 0,
    last_checked datetime NOT NULL DEFAULT '19000101',
    last_updated datetime NOT NULL DEFAULT '19000101',
    output_database sysname NOT NULL,
    output_schema sysname NOT NULL,
    output_table nvarchar(400) NOT NULL
);

CREATE UNIQUE NONCLUSTERED INDEX 
    no_dupes 
ON #human_events_worker 
    (output_table) 
WITH 
    (IGNORE_DUP_KEY = ON);

CREATE TABLE 
    #view_check 
(
    id integer PRIMARY KEY IDENTITY, 
    view_name sysname NOT NULL, 
    view_definition varbinary(MAX) NOT NULL,
    output_database sysname NOT NULL DEFAULT N'',
    output_schema sysname NOT NULL DEFAULT N'',
    output_table sysname NOT NULL DEFAULT N'',
    view_converted AS 
        CONVERT
        (
            nvarchar(MAX), 
            view_definition
        ), 
    view_converted_length AS 
        DATALENGTH
        (
            CONVERT
            (
                nvarchar(MAX), 
                view_definition
            )
        )
);


/*
I mean really stop it with the unsupported versions
*/
DECLARE 
    @v decimal(5,0) = 
        PARSENAME
        (
            CONVERT
            (
                nvarchar(128), 
                SERVERPROPERTY('ProductVersion')
            ), 
            4 
        ),
    @mv integer = 
        PARSENAME
        (
            CONVERT
            (
                nvarchar(128), 
                SERVERPROPERTY('ProductVersion')
            ), 
            2 
        ),
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
    @drop_old_sql nvarchar(1000) = N'',
    @waitfor nvarchar(20) = N'',
    @session_name nvarchar(512) = N'',
    @session_with nvarchar(MAX) = N'',
    @session_sql nvarchar(MAX) = N'',
    @start_sql nvarchar(MAX) = N'',
    @stop_sql  nvarchar(MAX) = N'',
    @drop_sql  nvarchar(MAX) = N'',
    @session_filter nvarchar(MAX) = N'',
    @session_filter_limited nvarchar(MAX) = N'',
    @session_filter_query_plans nvarchar(MAX) = N'',
    @session_filter_waits nvarchar(MAX) = N'',
    @session_filter_recompile nvarchar(MAX)= N'',
    @session_filter_statement_completed nvarchar(MAX) = N'',
    @session_filter_blocking nvarchar(MAX) = N'',
    @session_filter_parameterization nvarchar(MAX) = N'',
    @query_duration_filter nvarchar(MAX) = N'',
    @blocking_duration_ms_filter nvarchar(MAX) = N'',
    @wait_type_filter nvarchar(MAX) = N'',
    @wait_duration_filter nvarchar(MAX) = N'',
    @client_app_name_filter nvarchar(MAX) = N'',
    @client_hostname_filter nvarchar(MAX) = N'',
    @database_name_filter nvarchar(MAX) = N'',
    @session_id_filter nvarchar(MAX) = N'',
    @username_filter nvarchar(MAX) = N'',
    @object_name_filter nvarchar(MAX) = N'',
    @requested_memory_mb_filter nvarchar(MAX) = N'',
    @compile_events bit = 0,
    @parameterization_events bit = 0,
    @fully_formed_babby nvarchar(1000) = N'',
    @s_out int,
    @s_sql nvarchar(MAX) = N'',
    @s_params nvarchar(MAX) = N'',
    @object_id sysname = N'',
    @requested_memory_kb nvarchar(11) = N'',
    @the_sleeper_must_awaken nvarchar(MAX) = N'',
    @min_id int,
    @max_id int,
    @event_type_check sysname,
    @object_name_check nvarchar(1000) = N'',
    @table_sql nvarchar(MAX) = N'',
    @view_tracker bit,
    @spe nvarchar(MAX) = N'.sys.sp_executesql ',
    @view_sql nvarchar(MAX) = N'',
    @view_database sysname = N'',
    @date_filter datetime,
    @Time time,
    @delete_tracker int,
    @the_deleter_must_awaken nvarchar(MAX) = N'',
    @executer nvarchar(MAX),
    @cleanup_sessions nvarchar(MAX) = N'',
    @cleanup_tables nvarchar(MAX) = N'',
    @drop_holder nvarchar(MAX) = N'',
    @cleanup_views nvarchar(MAX) = N'',
    @nc10 nvarchar(2) = NCHAR(10),
    @inputbuf_bom nvarchar(1) = CONVERT(nvarchar(1), 0x0a00, 0);

/*check to make sure we're on a usable version*/
IF 
( 
    @v < 11
      OR (@v = 11 
           AND @mv < 7001) 
)
    BEGIN
        RAISERROR(N'This darn thing doesn''t seem to work on versions older than 2012 SP4.', 11, 1) WITH NOWAIT;
        RETURN;
    END;

/*one more check here for old versions. loiterers should arrested.*/
IF NOT EXISTS
(
    SELECT
        1/0
    FROM sys.dm_xe_packages AS xp
    JOIN sys.dm_xe_objects AS xo
        ON xp.guid = xo.package_guid
    WHERE (xo.capabilities IS NULL
             OR xo.capabilities & 1 = 0)
    AND   (xp.capabilities IS NULL
             OR xp.capabilities & 1 = 0)
    AND xo.object_type = N'action'
    AND xo.name = N'query_hash_signed'
)
    BEGIN
        RAISERROR(N'This server hasn''t been patched up to a supported version that has the query_hash_signed action.', 11, 1) WITH NOWAIT;
        RETURN;
    END;

/*clean up any old/dormant sessions*/    
IF @azure = 0
BEGIN
    INSERT 
        #drop_commands WITH (TABLOCK) 
    (
        drop_command
    )
    SELECT 
        N'DROP EVENT SESSION ' + 
        ses.name + 
        N' ON SERVER;'
    FROM sys.server_event_sessions AS ses
    LEFT JOIN sys.dm_xe_sessions AS dxe
        ON dxe.name = ses.name
    WHERE ses.name LIKE N'HumanEvents%'
    AND   (dxe.create_time < DATEADD(MINUTE, -1, SYSDATETIME())
      OR    dxe.create_time IS NULL);
END;

IF @azure = 1
BEGIN
    INSERT 
        #drop_commands WITH (TABLOCK) 
    (
        drop_command
    )
    SELECT 
        N'DROP EVENT SESSION ' +
        ses.name + 
        N' ON DATABASE;'
    FROM sys.database_event_sessions AS ses
    LEFT JOIN sys.dm_xe_database_sessions AS dxe
        ON dxe.name = ses.name
    WHERE ses.name LIKE N'HumanEvents%'
    AND   (dxe.create_time < DATEADD(MINUTE, -1, SYSDATETIME())
      OR     dxe.create_time IS NULL);
END;

IF EXISTS
(    
    SELECT 
        1/0
    FROM #drop_commands AS dc
)
BEGIN 
    RAISERROR(N'Found old sessions, dropping those.', 0, 1) WITH NOWAIT;
    
    DECLARE 
        drop_cursor CURSOR 
        LOCAL STATIC FOR
    
    SELECT  
        drop_command 
    FROM #drop_commands;
    
    OPEN drop_cursor;
    
    FETCH NEXT 
    FROM drop_cursor 
    INTO @drop_old_sql;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN             
        PRINT @drop_old_sql;
        EXEC(@drop_old_sql);    
        
        FETCH NEXT 
        FROM drop_cursor 
        INTO @drop_old_sql;
    END;
    
    CLOSE drop_cursor;
    DEALLOCATE drop_cursor;
END;

RAISERROR(N'Setting up some variables', 0, 1) WITH NOWAIT;

/* Give sessions super unique names in case more than one person uses it at a time */
IF @keep_alive = 0
BEGIN
    SET @session_name += 
            REPLACE
            (
                N'HumanEvents_' + 
                @event_type + 
                N'_' + 
                CONVERT
                (
                    nvarchar(36), 
                    NEWID()
                ), 
                N'-', 
                N''
            ); 
END;

IF @keep_alive = 1
BEGIN
    SET @session_name += 
            N'keeper_HumanEvents_'  + 
            @event_type + 
            CASE 
                WHEN @custom_name <> N'' 
                THEN N'_' + @custom_name 
                ELSE N'' 
            END;
END;


/* set a lower max memory setting for azure */
IF @azure = 1
BEGIN
    SELECT TOP (1) 
        @max_memory_kb = 
            CONVERT
            (
                bigint, 
                (max_memory * .10) * 1024
            )
    FROM sys.dm_user_db_resource_governance
    WHERE UPPER(database_name) = UPPER(QUOTENAME(@database_name))
    OR    @database_name = ''
    ORDER BY max_memory DESC;

    RAISERROR(N'Setting lower max memory for ringbuffer due to Azure, setting to %m kb',  0, 1, @max_memory_kb) WITH NOWAIT;
END;

/* session create options */
SET @session_with = N'    
ADD TARGET package0.ring_buffer
        ( SET max_memory = ' + RTRIM(@max_memory_kb) + N' )
WITH
        (
            MAX_MEMORY = ' + RTRIM(@max_memory_kb) + N'KB,
            EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS,
            MAX_DISPATCH_LATENCY = 5 SECONDS,
            MAX_EVENT_SIZE = 0KB,
            MEMORY_PARTITION_MODE = PER_CPU,
            TRACK_CAUSALITY = OFF,
            STARTUP_STATE = OFF
        );' + @nc10;

/* azure can't create on server, just database */
SET @session_sql = 
    N'
CREATE EVENT SESSION ' + 
@session_name +
    CASE 
        WHEN @azure = 0
        THEN N'
    ON SERVER '
        ELSE N'
    ON DATABASE '
    END;

/* STOP. DROP. SHUT'EM DOWN OPEN UP SHOP. */
SET @start_sql = 
    N'ALTER EVENT SESSION ' + 
    @session_name + 
    N' ON ' + 
    CASE 
        WHEN @azure = 1 
        THEN 'DATABASE' 
        ELSE 'SERVER' 
    END + 
    ' STATE = START;' + 
    @nc10;

SET @stop_sql  = 
    N'ALTER EVENT SESSION ' + 
    @session_name + 
    N' ON ' + 
    CASE 
        WHEN @azure = 1 
        THEN 'DATABASE' 
        ELSE 'SERVER' 
    END + 
    ' STATE = STOP;' + 
    @nc10;

SET @drop_sql  = 
    N'DROP EVENT SESSION '  + 
    @session_name + 
    N' ON ' + 
    CASE 
        WHEN @azure = 1 
        THEN 'DATABASE' 
        ELSE 'SERVER' 
    END + 
    ';' + 
    @nc10;


/*Some sessions can use all general filters*/
SET @session_filter = @nc10 + N'            sqlserver.is_system = 0 ' + @nc10;
/*Others can't use all of them, like app and host name*/
SET @session_filter_limited = @nc10 + N'            sqlserver.is_system = 0 ' + @nc10;
/*query plans can filter on requested memory, too, along with the limited filters*/
SET @session_filter_query_plans = @nc10 + N'            sqlserver.is_system = 0 ' + @nc10;
/*only wait stats can filter on wait types, but can filter on everything else*/
SET @session_filter_waits = @nc10 + N'            sqlserver.is_system = 0 ' + @nc10;
/*only wait stats can filter on wait types, but can filter on everything else*/
SET @session_filter_recompile = @nc10 + N'            sqlserver.is_system = 0 ' + @nc10;
/*sql_statement_completed can do everything except object name*/
SET @session_filter_statement_completed = @nc10 + N'            sqlserver.is_system = 0 ' + @nc10;
/*for blocking because blah blah*/
SET @session_filter_blocking = @nc10 + N'         sqlserver.is_system = 1 ' + @nc10;
/*for parameterization because blah blah*/
SET @session_filter_parameterization = @nc10 + N'            sqlserver.is_system = 0 ' + @nc10;


RAISERROR(N'Checking for some event existence', 0, 1) WITH NOWAIT;
/* Determines if we use the new event or the old event(s) to track compiles */
IF EXISTS
(
    SELECT 
        1/0 
    FROM sys.dm_xe_objects AS dxo 
    WHERE dxo.name = N'sql_statement_post_compile'
)
BEGIN 
    SET @compile_events = 1; 
END;


/* Or if we use this event at all! */
IF EXISTS
(
    SELECT 
        1/0 
    FROM sys.dm_xe_objects AS dxo 
    WHERE dxo.name = N'query_parameterization_data'
)
BEGIN 
    SET @parameterization_events = 1; 
END;


/* You know what I don't wanna deal with? NULLs. */
RAISERROR(N'Nixing NULLs', 0, 1) WITH NOWAIT;
SET @event_type            = ISNULL(@event_type, N'');
SET @client_app_name       = ISNULL(@client_app_name, N'');
SET @client_hostname       = ISNULL(@client_hostname, N'');
SET @database_name         = ISNULL(@database_name, N'');
SET @session_id            = ISNULL(@session_id, N'');
SET @username              = ISNULL(@username, N'');
SET @object_name           = ISNULL(@object_name, N'');
SET @object_schema         = ISNULL(@object_schema, N'');
SET @custom_name           = ISNULL(@custom_name, N'');
SET @output_database_name  = ISNULL(@output_database_name, N'');
SET @output_schema_name    = ISNULL(@output_schema_name, N'');

/*I'm also very forgiving of some white space*/
SET @database_name = RTRIM(LTRIM(@database_name));

/*Assemble the full object name for easier wrangling*/
SET @fully_formed_babby = 
        QUOTENAME(@database_name) + 
        N'.' + 
        QUOTENAME(@object_schema) + 
        N'.' + 
        QUOTENAME(@object_name);

/*Some sanity checking*/
RAISERROR(N'Sanity checking event types', 0, 1) WITH NOWAIT;
/* You can only do this right now. */
IF LOWER(@event_type) NOT IN 
        ( 
            N'waits',
            N'blocking',
            N'locking',
            N'queries',
            N'compiles',
            N'recompiles',
            N'wait',
            N'block',
            N'blocks',
            N'lock',
            N'locks',
            N'query',
            N'compile',
            N'recompile',
            N'compilation',
            N'recompilation',
            N'compilations',
            N'recompilations' 
        )
BEGIN
    RAISERROR(N'You have chosen a value for @event_type... poorly. use @help = 1 to see valid arguments.', 11, 1) WITH NOWAIT;
    RAISERROR(N'What on earth is %s?', 11, 1, @event_type) WITH NOWAIT;
    RETURN;
END;


RAISERROR(N'Checking query duration filter', 0, 1) WITH NOWAIT;
/* Set these durations to non-crazy numbers unless someone asks for @gimme_danger = 1
   ignore compile and recompile because this is a filter on query compilation time 🙄 */
IF 
( 
        LOWER(@event_type) LIKE N'%quer%' 
    AND @event_type NOT LIKE N'%comp%'
    AND @gimme_danger = 0 
)
      AND 
(
    @query_duration_ms < 500 
      OR @query_duration_ms IS NULL 
)
BEGIN
    RAISERROR(N'You chose a really dangerous value for @query_duration', 0, 1) WITH NOWAIT;
    RAISERROR(N'If you really want that, please set @gimme_danger = 1, and re-run', 0, 1) WITH NOWAIT;
    RAISERROR(N'Setting @query_duration to 500', 0, 1) WITH NOWAIT;
    SET @query_duration_ms = 500;
END;


RAISERROR(N'Checking wait duration filter', 0, 1) WITH NOWAIT;
IF 
( 
        LOWER(@event_type) LIKE N'%wait%' 
    AND @gimme_danger = 0 
)
      AND 
(   @wait_duration_ms < 10 
      OR @wait_duration_ms IS NULL 
) 
BEGIN
    RAISERROR(N'You chose a really dangerous value for @wait_duration_ms', 0, 1) WITH NOWAIT;
    RAISERROR(N'If you really want that, please set @gimme_danger = 1, and re-run', 0, 1) WITH NOWAIT;
    RAISERROR(N'Setting @wait_duration_ms to 10', 0, 1) WITH NOWAIT;
    SET @wait_duration_ms = 10;
END;


RAISERROR(N'Checking block duration filter', 0, 1) WITH NOWAIT;
IF 
( 
        LOWER(@event_type) LIKE N'%lock%' 
    AND @gimme_danger = 0 
)
      AND 
(
    @blocking_duration_ms < 500 
      OR @blocking_duration_ms IS NULL 
) 
BEGIN
    RAISERROR(N'You chose a really dangerous value for @blocking_duration_ms', 0, 1) WITH NOWAIT;
    RAISERROR(N'If you really want that, please set @gimme_danger = 1, and re-run', 0, 1) WITH NOWAIT;
    RAISERROR(N'Setting @blocking_duration_ms to 500', 0, 1) WITH NOWAIT;
    SET @blocking_duration_ms = 500;
END;


RAISERROR(N'Checking query sort order', 0, 1) WITH NOWAIT;
IF @query_sort_order NOT IN 
( 
    N'cpu', 
    N'reads', 
    N'writes', 
    N'duration', 
    N'memory', 
    N'spills',    
    N'avg cpu', 
    N'avg reads', 
    N'avg writes', 
    N'avg duration', 
    N'avg memory', 
    N'avg spills' 
)
BEGIN
   RAISERROR(N'That sort order (%s) you chose is so out of this world that i''m ignoring it', 0, 1, @query_sort_order) WITH NOWAIT;
   SET @query_sort_order = N'cpu';
END;


RAISERROR(N'Parsing any supplied waits', 0, 1) WITH NOWAIT;
SET @wait_type = UPPER(@wait_type);
/* This will hold the CSV list of wait types someone passes in */

INSERT 
    #user_waits WITH(TABLOCK)
SELECT 
    LTRIM
    (
        RTRIM
        (
            waits.wait_type
        )
    ) AS wait_type
FROM
(
    SELECT 
        wait_type = 
            x.x.value
                (
                    '(./text())[1]', 
                    'nvarchar(60)'
                )
    FROM 
    ( 
      SELECT 
          wait_type = 
              CONVERT
              (
                  xml, 
                  N'<x>' + 
                  REPLACE
                  (
                      REPLACE
                      (
                          @wait_type, 
                          N',', 
                          N'</x><x>'
                      ), 
                      N' ', 
                      N''
                  ) + 
                  N'</x>'
              ).query('.')
    ) AS w 
    CROSS APPLY wait_type.nodes('x') AS x(x)
) AS waits
WHERE @wait_type <> N'ALL';


/*
If someone is passing in specific waits, let's make sure that
they're valid waits by checking them against what's available.
*/
IF @wait_type <> N'ALL'
BEGIN
RAISERROR(N'Checking wait validity', 0, 1) WITH NOWAIT;

    /* There's no THREADPOOL in XE map values, it gets registered as SOS_WORKER */
    SET @wait_type = 
            REPLACE
            (
                @wait_type, 
                N'THREADPOOL', 
                N'SOS_WORKER'
            );

    SELECT DISTINCT 
        invalid_waits = 
             uw.wait_type
    INTO #invalid_waits
    FROM #user_waits AS uw
    WHERE NOT EXISTS
          (
              SELECT 
                  1/0
              FROM sys.dm_xe_map_values AS dxmv
              WHERE  dxmv.map_value COLLATE Latin1_General_BIN = uw.wait_type COLLATE Latin1_General_BIN
              AND    dxmv.name = N'wait_types'
          );
    
    /* If we find any invalid waits, let people know */
    IF @@ROWCOUNT > 0    
    BEGIN
        SELECT 
            invalid_waits = 
                N'You have chosen some invalid wait types'
        
        UNION ALL
        
        SELECT 
            iw.invalid_waits
        FROM #invalid_waits AS iw;
        
        RAISERROR(N'Waidaminnithataintawait', 11, 1) WITH NOWAIT;
        RETURN;
    END;

END;


/*
If someone is passing in non-blank values, let's try to limit our SQL injection exposure a little bit
*/
IF 
( 
       @client_app_name <> N''
    OR @client_hostname <> N''
    OR @database_name <> N''
    OR @session_id <> N''
    OR @username <> N''
    OR @object_name <> N''
    OR @object_schema NOT IN (N'dbo', N'') 
    OR @custom_name <> N''       
    OR @output_database_name <> N''
    OR @output_schema_name NOT IN (N'dbo', N'') 
)
BEGIN
RAISERROR(N'Checking for unsanitary inputs', 0, 1) WITH NOWAIT;
    
    INSERT 
        #papers_please WITH(TABLOCK)
    (
        ahem
    )
    SELECT 
        UPPER(pp.ahem)
    FROM 
    (
        VALUES
            (@client_app_name),
            (@client_hostname),
            (@database_name),
            (@session_id),
            (@username),
            (@object_name),
            (@object_schema),
            (@custom_name),
            (@output_database_name),
            (@output_schema_name)
    ) AS pp (ahem)
    WHERE pp.ahem NOT IN 
          (
              N'', 
              N'dbo'
          );

    IF EXISTS
    (
        SELECT 
            1/0
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
        OR    pp.ahem LIKE N'%XP[_]CMDSHELL%'
    )
    BEGIN
        RAISERROR(N'Say... you wouldn''t happen to be trying some funny business, would you?', 11, 1) WITH NOWAIT;
        RETURN;
    END;

END;


/* I just don't want anyone to be disappointed */
RAISERROR(N'Avoiding disappointment', 0, 1) WITH NOWAIT;
IF 
( 
        @wait_type <> N'' 
    AND @wait_type <> N'ALL' 
    AND LOWER(@event_type) NOT LIKE N'%wait%' 
)
BEGIN
    RAISERROR(N'You can''t filter on wait stats unless you use the wait stats event.', 11, 1) WITH NOWAIT;
    RETURN;
END;


/* This is probably important, huh? */
RAISERROR(N'Are we trying to filter for a blocking session?', 0, 1) WITH NOWAIT;

/* blocking events need a database name to resolve objects */
IF 
( 
        LOWER(@event_type) LIKE N'%lock%' 
    AND DB_ID(@database_name) IS NULL 
    AND @object_name <> N'' 
)
BEGIN
    RAISERROR(N'The blocking event can only filter on an object_id, and we need a valid @database_name to resolve it correctly.', 11, 1) WITH NOWAIT;
    RETURN;
END;

/* but could we resolve the object name? */
IF 
( 
        LOWER(@event_type) LIKE N'%lock%' 
    AND @object_name <> N'' 
    AND OBJECT_ID(@fully_formed_babby) IS NULL 
)
BEGIN
    RAISERROR(N'We couldn''t find the object you''re trying to find: %s', 11, 1, @fully_formed_babby) WITH NOWAIT;
    RETURN;
END;

/* no blocked process report, no love */
RAISERROR(N'Validating if the Blocked Process Report is on, if the session is for blocking', 0, 1) WITH NOWAIT;
IF @event_type LIKE N'%lock%'
AND  EXISTS
(
    SELECT 
        1/0
    FROM sys.configurations AS c
    WHERE c.name = N'blocked process threshold (s)'
    AND CONVERT(int, c.value_in_use) = 0
)
BEGIN
        RAISERROR(N'You need to set up the blocked process report in order to use this:
    EXEC sys.sp_configure ''show advanced options'', 1;
    RECONFIGURE
    EXEC sys.sp_configure ''blocked process threshold'', 5; /* Seconds of blocking before a report is generated */
    RECONFIGURE
    GO', 1, 0) WITH NOWAIT;
    RETURN;
END;

/* validatabase name */
RAISERROR(N'If there''s a database filter, is the name valid?', 0, 1) WITH NOWAIT;
IF @database_name <> N''
BEGIN
    IF DB_ID(@database_name) IS NULL
    BEGIN
        RAISERROR(N'It looks like you''re looking for a database that doesn''t wanna be looked for (%s); check that spelling!', 11, 1, @database_name) WITH NOWAIT;
        RETURN;
    END;
END;


/* session id has be be "sampled" or a number. */
RAISERROR(N'If there''s a session id filter, is it valid?', 0, 1) WITH NOWAIT;
IF
(
        LOWER(@session_id) NOT LIKE N'%sample%' 
    AND @session_id LIKE '%[^0-9]%' 
    AND LOWER(@session_id) <> N''
)
BEGIN
   RAISERROR(N'That @session_id doesn''t look proper (%s). double check it for me.', 11, 1, @session_id) WITH NOWAIT;
   RETURN;
END;


/* some numbers won't be effective as sample divisors */
RAISERROR(N'No dividing by zero', 0, 1) WITH NOWAIT;
IF 
(
        @sample_divisor < 2 
    AND LOWER(@session_id) LIKE N'%sample%'
)
BEGIN
    RAISERROR(N'@sample_divisor is used to divide @session_id when taking a sample of a workload.', 11, 1) WITH NOWAIT;
    RAISERROR(N'we can''t really divide by zero, and dividing by 1 would be useless.', 11, 1) WITH NOWAIT;
    RETURN;
END;


/*
We need to do some seconds math here, because WAITFOR is very stupid
*/
RAISERROR(N'Wait For It! Wait For it!', 0, 1) WITH NOWAIT;
IF @seconds_sample > 1
BEGIN
    /* I really don't want this running for more than 10 minutes right now. */
    IF 
    ( 
            @seconds_sample > 600 
        AND @gimme_danger = 0 
    )
    BEGIN
        RAISERROR(N'Yeah nah not more than 10 minutes', 10, 1) WITH NOWAIT;
        RAISERROR(N'(unless you set @gimme_danger = 1)', 10, 1) WITH NOWAIT;
        RETURN;
    END;
    
    SELECT 
        @waitfor = 
            CONVERT
            (
                nvarchar(20), 
                DATEADD
                (
                    SECOND, 
                    @seconds_sample, 
                    0
                 ), 
                 114
            );
END;

/* CH-CH-CH-CHECK-IT-OUT */

/* check for existing session with the same name */
RAISERROR(N'Make sure the session doesn''t exist already', 0, 1) WITH NOWAIT;

IF @azure = 0
BEGIN
    IF EXISTS
    (
        SELECT 
            1/0
        FROM sys.server_event_sessions AS ses
        LEFT JOIN sys.dm_xe_sessions AS dxs 
            ON dxs.name = ses.name
        WHERE ses.name = @session_name
    )
    BEGIN
        RAISERROR('A session with the name %s already exists. dropping.', 0, 1, @session_name) WITH NOWAIT;
        
        EXEC sys.sp_executesql 
            @drop_sql;
    END;
END;
ELSE
BEGIN
    IF EXISTS
    (
        SELECT 
            1/0
        FROM sys.database_event_sessions AS ses
        LEFT JOIN sys.dm_xe_database_sessions AS dxs 
            ON dxs.name = ses.name
        WHERE ses.name = @session_name
    )
    BEGIN
        RAISERROR('A session with the name %s already exists. dropping.', 0, 1, @session_name) WITH NOWAIT;
        
        EXEC sys.sp_executesql 
            @drop_sql;
    END;
END;

/* check that the output database exists */
RAISERROR(N'Does the output database exist?', 0, 1) WITH NOWAIT;
IF @output_database_name <> N''
BEGIN
    IF DB_ID(@output_database_name) IS NULL
    BEGIN
        RAISERROR(N'It looks like you''re looking for a database (%s) that doesn''t wanna be looked for; check that spelling!', 11, 1, @output_database_name) WITH NOWAIT;
        RETURN;
    END;
END;


/* check that the output schema exists */
RAISERROR(N'Does the output schema exist?', 0, 1) WITH NOWAIT;
IF @output_schema_name NOT IN (N'dbo', N'')
BEGIN
    SELECT 
        @s_sql = N'
    SELECT 
        @is_out = 
            COUNT_BIG(*) 
    FROM ' + QUOTENAME(@output_database_name) + N'.sys.schemas AS s
    WHERE s.name = ' + QUOTENAME(@output_schema_name, '''') + N';',
        @s_params  = 
            N'@is_out integer OUTPUT';
    
    EXEC sys.sp_executesql 
        @s_sql, 
        @s_params, 
        @is_out = @s_out OUTPUT;
    
    IF @s_out = 0
    BEGIN
        RAISERROR(N'It looks like the schema %s doesn''t exist in the database %s', 11, 1, @output_schema_name, @output_database_name);
        RETURN;
    END;
END;
 

/* we need an output schema and database */
RAISERROR(N'Is output database OR schema filled in?', 0, 1) WITH NOWAIT;
IF 
(
        LEN(@output_database_name + @output_schema_name) > 0
    AND @output_schema_name <> N'dbo'
    AND (@output_database_name  = N'' 
      OR @output_schema_name = N'')
)
BEGIN
    IF @output_database_name = N''
        BEGIN
            RAISERROR(N'@output_database_name can''t blank when outputting to tables or cleaning up', 11, 1) WITH NOWAIT;
            RETURN;
        END;
    
    IF @output_schema_name = N''
        BEGIN
            RAISERROR(N'@output_schema_name can''t blank when outputting to tables or cleaning up', 11, 1) WITH NOWAIT;
            RETURN;
        END;
END;


/* no goofballing in custom names */
RAISERROR(N'Is custom name something stupid?', 0, 1) WITH NOWAIT;
IF 
( 
    PATINDEX(N'%[^a-zA-Z0-9]%', @custom_name) > 0 
      OR @custom_name LIKE N'[0-9]%' 
)
BEGIN
    RAISERROR(N'Dunno if I like the looks of @custom_name: %s', 11, 1, @custom_name) WITH NOWAIT;
    RAISERROR(N'You can''t use special characters, or leading numbers.', 11, 1, @custom_name) WITH NOWAIT;
    RETURN;
END;


/* I'M LOOKING AT YOU */
RAISERROR(N'Someone is going to try it.', 0, 1) WITH NOWAIT;
IF @delete_retention_days < 0
BEGIN
    SET @delete_retention_days *= -1;
    RAISERROR(N'Stay positive', 0, 1) WITH NOWAIT;
END;


/*
If we're writing to a table, we don't want to do anything else
Or anything else after this, really
We want the session to get set up
*/
RAISERROR(N'Do we skip to the GOTO and log tables?', 0, 1) WITH NOWAIT;
IF 
( 
        @output_database_name <> N''
    AND @output_schema_name <> N''
    AND @cleanup = 0 
)
BEGIN
    RAISERROR(N'Skipping all the other stuff and going to data logging', 0, 1) WITH NOWAIT;    
        
    GOTO output_results;
    RETURN;
END;


/* just finishing up the second coat now */
RAISERROR(N'Do we skip to the GOTO and cleanup?', 0, 1) WITH NOWAIT;
IF 
( 
        @output_database_name <> N''
    AND @output_schema_name <> N''
    AND @cleanup = 1 
)
BEGIN
    RAISERROR(N'Skipping all the other stuff and going to cleanup', 0, 1) WITH NOWAIT;       
    
    GOTO cleanup;
    RETURN;
END;


/* Start setting up individual filters */
RAISERROR(N'Setting up individual filters', 0, 1) WITH NOWAIT;
IF @query_duration_ms > 0
BEGIN
    IF LOWER(@event_type) NOT LIKE N'%comp%' /* compile and recompile durations are tiny */
    BEGIN
        SET @query_duration_filter += N'     AND duration >= ' + CONVERT(nvarchar(20), (@query_duration_ms * 1000)) + @nc10;
    END;
END;

IF @blocking_duration_ms > 0
BEGIN
    SET @blocking_duration_ms_filter += N'     AND duration >= ' + CONVERT(nvarchar(20), (@blocking_duration_ms * 1000)) + @nc10;
END;

IF @wait_duration_ms > 0
BEGIN
    SET @wait_duration_filter += N'     AND duration >= ' + CONVERT(nvarchar(20), (@wait_duration_ms)) + @nc10;
END;

IF @client_app_name <> N''
BEGIN
    SET @client_app_name_filter += N'     AND sqlserver.client_app_name = N' + QUOTENAME(@client_app_name, '''') + @nc10;
END;

IF @client_hostname <> N''
BEGIN
    SET @client_hostname_filter += N'     AND sqlserver.client_hostname = N' + QUOTENAME(@client_hostname, '''') + @nc10;
END;

IF @database_name <> N''
BEGIN
    IF LOWER(@event_type) NOT LIKE N'%lock%'
    BEGIN
        SET @database_name_filter += N'     AND sqlserver.database_name = N' + QUOTENAME(@database_name, '''') + @nc10;
    END;
    IF LOWER(@event_type) LIKE N'%lock%'
    BEGIN
        SET @database_name_filter += N'     AND database_name = N' + QUOTENAME(@database_name, '''') + @nc10;
    END;
END;

IF @session_id <> N''
BEGIN
    IF LOWER(@session_id) NOT LIKE N'%sample%'
        BEGIN
            SET @session_id_filter += N'     AND sqlserver.session_id = ' + CONVERT(nvarchar(11), @session_id) + @nc10;
        END;
    IF LOWER(@session_id) LIKE N'%sample%'
        BEGIN
            SET @session_id_filter += N'     AND package0.divides_by_uint64(sqlserver.session_id, ' + CONVERT(nvarchar(11), @sample_divisor) + N') ' + @nc10;
        END;
END;

IF @username <> N''
BEGIN
    SET @username_filter += N'     AND sqlserver.username = N' + QUOTENAME(@username, '''') + @nc10;
END;

IF @object_name <> N''
BEGIN
    IF @event_type LIKE N'%lock%'
    BEGIN
        SET @object_id = OBJECT_ID(@fully_formed_babby);
        SET @object_name_filter += N'     AND object_id = ' + @object_id + @nc10;
    END;
    IF @event_type NOT LIKE N'%lock%'
    BEGIN
        SET @object_name_filter += N'     AND object_name = N' + QUOTENAME(@object_name, '''') + @nc10;
    END;
END;

IF @requested_memory_mb > 0
BEGIN
    SET @requested_memory_kb = @requested_memory_mb / 1024.;
    SET @requested_memory_mb_filter += N'     AND requested_memory_kb >= ' + @requested_memory_kb + @nc10;
END;


/* At this point we'll either put my list of interesting waits in a temp table, 
   or a list of user defined waits */
IF LOWER(@event_type) LIKE N'%wait%'
BEGIN    
    
    INSERT 
        #wait
    (
        wait_type 
    )
    SELECT 
        x.wait_type
    FROM 
    (
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
    
    SELECT 
        uw.wait_type
    FROM #user_waits AS uw
    WHERE @wait_type <> N'all';
    
    /* This section creates a dynamic WHERE clause based on wait types
       The problem is that wait type IDs change frequently, which sucks. */
    WITH maps AS 
    ( 
        SELECT   
            dxmv.map_key,
            dxmv.map_value,
            dxmv.map_key
                - ROW_NUMBER() 
                      OVER 
                      ( 
                          ORDER BY 
                              dxmv.map_key 
                      ) AS rn
        FROM sys.dm_xe_map_values AS dxmv
        WHERE dxmv.name = N'wait_types'
        AND   dxmv.map_value IN 
              ( 
                  SELECT 
                      w.wait_type 
                  FROM #wait AS w 
              )
    ),
         grps AS 
    ( 
        SELECT   
            minkey = 
                MIN(maps.map_key),
            maxkey = 
                MAX(maps.map_key)
            FROM maps
            GROUP BY maps.rn 
    )
    SELECT 
        @wait_type_filter += 
            SUBSTRING
            (
                ( 
                    SELECT 
                        N'      AND  ((' +
                        STUFF
                        (
                            ( 
                                SELECT 
                                    N'         OR ' + 
                                    CASE 
                                        WHEN grps.minkey < grps.maxkey
                                        THEN + 
                                        N'(wait_type >= ' + 
                                        CONVERT
                                        (
                                            nvarchar(11), 
                                            grps.minkey
                                        ) + 
                                        N' AND wait_type <= ' + 
                                        CONVERT
                                        (
                                            nvarchar(11), 
                                            grps.maxkey
                                        ) + 
                                        N')' + 
                                        @nc10
                                        ELSE N'(wait_type = ' + 
                                        CONVERT
                                        (
                                            nvarchar(11), 
                                            grps.minkey
                                        ) + 
                                        N')' + 
                                        @nc10
                                    END
                                FROM grps FOR XML PATH(''), TYPE
                            ).value('./text()[1]', 'nvarchar(max)')
                            , 
                            1, 
                            13, 
                            N''
                        ) 
                ), 
                0, 
                8000
            ) + 
            N')';
END; 

/* End individual filters */

/* This section sets event-dependent filters */

RAISERROR(N'Combining session filters', 0, 1) WITH NOWAIT;
/* For full filter-able sessions */
SET @session_filter += 
    ( 
        ISNULL(@query_duration_filter, N'') +
        ISNULL(@client_app_name_filter, N'') +
        ISNULL(@client_hostname_filter, N'') +
        ISNULL(@database_name_filter, N'') +
        ISNULL(@session_id_filter, N'') +
        ISNULL(@username_filter, N'') +
        ISNULL(@object_name_filter, N'') 
    );

/* For waits specifically, because they also need to filter on wait type and wait duration */
SET @session_filter_waits += 
    ( 
        ISNULL(@wait_duration_filter, N'') +
        ISNULL(@wait_type_filter, N'') +
        ISNULL(@client_app_name_filter, N'') +
        ISNULL(@client_hostname_filter, N'') +
        ISNULL(@database_name_filter, N'') +
        ISNULL(@session_id_filter, N'') +
        ISNULL(@username_filter, N'') +
        ISNULL(@object_name_filter, N'') 
    );

/* For sessions that can't filter on client app or host name */
SET @session_filter_limited += 
    ( 
        ISNULL(@query_duration_filter, N'') +
        ISNULL(@database_name_filter, N'') +
        ISNULL(@session_id_filter, N'') +
        ISNULL(@username_filter, N'') +
        ISNULL(@object_name_filter, N'') 
    );

/* For query plans, which can also filter on memory required */
SET @session_filter_query_plans += 
    ( 
        ISNULL(@query_duration_filter, N'') +
        ISNULL(@database_name_filter, N'') +
        ISNULL(@session_id_filter, N'') +
        ISNULL(@username_filter, N'') +
        ISNULL(@object_name_filter, N'') 
    );

/* Recompile can have almost everything except... duration */
SET @session_filter_recompile += 
    ( 
        ISNULL(@client_app_name_filter, N'') +
        ISNULL(@client_hostname_filter, N'') +
        ISNULL(@database_name_filter, N'') +
        ISNULL(@session_id_filter, N'') +
        ISNULL(@object_name_filter, N'') +
        ISNULL(@username_filter, N'')  
    );

/* Apparently statement completed can't filter on an object name so that's fun */
SET @session_filter_statement_completed += 
    ( 
        ISNULL(@query_duration_filter, N'') +
        ISNULL(@client_app_name_filter, N'') +
        ISNULL(@client_hostname_filter, N'') +
        ISNULL(@database_name_filter, N'') +
        ISNULL(@session_id_filter, N'') +
        ISNULL(@username_filter, N'') 
    );

/* Blocking woighoiughuohaeripugbapiouergb */
SET @session_filter_blocking += 
    ( 
        ISNULL(@blocking_duration_ms_filter, N'') +
        ISNULL(@database_name_filter, N'') +
        ISNULL(@session_id_filter, N'') +
        ISNULL(@username_filter, N'') +
        ISNULL(@object_name_filter, N'') +
        ISNULL(@requested_memory_mb_filter, N'') 
    );

/* The parameterization event is pretty limited in weird ways */
SET @session_filter_parameterization += 
    ( 
        ISNULL(@client_app_name_filter, N'') +
        ISNULL(@client_hostname_filter, N'') +
        ISNULL(@database_name_filter, N'') +
        ISNULL(@session_id_filter, N'') +
        ISNULL(@username_filter, N'') 
    );


/* This section sets up the event session definition */
RAISERROR(N'Setting up the event session', 0, 1) WITH NOWAIT;
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
      ADD EVENT sqlserver.sql_statement_completed 
        (SET collect_statement = 1
         ACTION(sqlserver.database_name, sqlserver.sql_text, sqlserver.plan_handle, sqlserver.query_hash_signed, sqlserver.query_plan_hash_signed)
         WHERE ( ' + @session_filter_statement_completed + N' )),
      ADD EVENT sqlserver.query_post_execution_showplan
        (
         ACTION(sqlserver.database_name, sqlserver.sql_text, sqlserver.plan_handle, sqlserver.query_hash_signed, sqlserver.query_plan_hash_signed)
         WHERE ( ' + @session_filter_query_plans + N' ))'
             WHEN LOWER(@event_type) LIKE N'%wait%' 
                    AND @v > 11
             THEN N' 
      ADD EVENT sqlos.wait_completed
        (SET collect_wait_resource = 1
         ACTION (sqlserver.database_name, sqlserver.plan_handle, sqlserver.query_hash_signed, sqlserver.query_plan_hash_signed)
         WHERE ( ' + @session_filter_waits + N' ))'
             WHEN LOWER(@event_type) LIKE N'%wait%' 
                    AND @v = 11
             THEN N' 
      ADD EVENT sqlos.wait_info
        (
         ACTION (sqlserver.database_name, sqlserver.plan_handle, sqlserver.query_hash_signed, sqlserver.query_plan_hash_signed)
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
             WHEN (LOWER(@event_type) LIKE N'%comp%' 
                     AND LOWER(@event_type) NOT LIKE N'%re%')
             THEN CASE WHEN @compile_events = 1
                       THEN N' 
      ADD EVENT sqlserver.sql_statement_post_compile 
        (SET collect_object_name = 1, collect_statement = 1
         ACTION(sqlserver.database_name)
         WHERE ( ' + @session_filter + N' ))'
                       ELSE N'
      ADD EVENT sqlserver.uncached_sql_batch_statistics
        (
         ACTION(sqlserver.database_name)
         WHERE ( ' + @session_filter_recompile + N' )),             
      ADD EVENT sqlserver.sql_statement_recompile 
        (SET collect_object_name = 1, collect_statement = 1
         ACTION(sqlserver.database_name)
         WHERE ( ' + @session_filter_recompile + N' ))'
                  END
                + CASE WHEN @parameterization_events = 1
                       THEN N',
      ADD EVENT sqlserver.query_parameterization_data
        (
         ACTION (sqlserver.database_name, sqlserver.plan_handle, sqlserver.sql_text)
         WHERE ( ' + @session_filter_parameterization + N' ))'
                       ELSE N''
                  END 
            ELSE N'i have no idea what i''m doing.'
        END;
/* End event session definition */
  

/* This creates the event session */
SET @session_sql += 
        @session_with;

IF @debug = 1 BEGIN RAISERROR(@session_sql, 0, 1) WITH NOWAIT; END;
EXEC (@session_sql);

/* This starts the event session */
IF @debug = 1 BEGIN RAISERROR(@start_sql, 0, 1) WITH NOWAIT; END;
EXEC (@start_sql);

/* bail out here if we want to keep the session */
IF @keep_alive = 1
BEGIN
    RAISERROR(N'Session %s created, exiting.', 0, 1, @session_name) WITH NOWAIT;
    RAISERROR(N'To collect data from it, run this proc from an agent job with an output database and schema name', 0, 1) WITH NOWAIT;
    RAISERROR(N'Alternately, you can watch live data stream in by accessing the GUI', 0, 1) WITH NOWAIT;
    RAISERROR(N'Just don''t forget to stop it when you''re done with it!', 0, 1) WITH NOWAIT;
    RETURN;
END;


/* NOW WE WAIT, MR. BOND */
WAITFOR DELAY @waitfor;


/* Dump whatever we got into a temp table */
IF @azure = 0
BEGIN
    INSERT
        #x
    (
        x
    )    
    SELECT 
        x = 
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
    INSERT
        #x
    (
        x
    )    
    SELECT 
        x = 
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
INTO #human_events_xml
FROM #x AS x
CROSS APPLY x.x.nodes('/RingBufferTarget/event') AS e(x);


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
                event_type = c.value('@name', 'nvarchar(256)'),
                database_name = c.value('(action[@name="database_name"]/value/text())[1]', 'nvarchar(256)'),                
                object_name = c.value('(data[@name="object_name"]/value/text())[1]', 'nvarchar(256)'),
                sql_text = c.value('(action[@name="sql_text"]/value/text())[1]', 'nvarchar(MAX)'),
                statement = c.value('(data[@name="statement"]/value/text())[1]', 'nvarchar(MAX)'),
                showplan_xml = c.query('(data[@name="showplan_xml"]/value/*)[1]'),
                cpu_ms = c.value('(data[@name="cpu_time"]/value/text())[1]', 'bigint') / 1000.,
                logical_reads = (c.value('(data[@name="logical_reads"]/value/text())[1]', 'bigint') * 8) / 1024.,
                physical_reads = (c.value('(data[@name="physical_reads"]/value/text())[1]', 'bigint') * 8) / 1024.,
                duration_ms = c.value('(data[@name="duration"]/value/text())[1]', 'bigint') / 1000.,
                writes = (c.value('(data[@name="writes"]/value/text())[1]', 'bigint') * 8) / 1024.,
                spills_mb = (c.value('(data[@name="spills"]/value/text())[1]', 'bigint') * 8) / 1024.,
                row_count = c.value('(data[@name="row_count"]/value/text())[1]', 'bigint'),
                estimated_rows = c.value('(data[@name="estimated_rows"]/value/text())[1]', 'bigint'),
                dop = c.value('(data[@name="dop"]/value/text())[1]', 'int'),
                serial_ideal_memory_mb = c.value('(data[@name="serial_ideal_memory_kb"]/value/text())[1]', 'bigint') / 1024.,
                requested_memory_mb = c.value('(data[@name="requested_memory_kb"]/value/text())[1]', 'bigint') / 1024.,
                used_memory_mb = c.value('(data[@name="used_memory_kb"]/value/text())[1]', 'bigint') / 1024.,
                ideal_memory_mb = c.value('(data[@name="ideal_memory_kb"]/value/text())[1]', 'bigint') / 1024.,
                granted_memory_mb = c.value('(data[@name="granted_memory_kb"]/value/text())[1]', 'bigint') / 1024.,
                query_plan_hash_signed = 
                    CONVERT
                    (
                        binary(8), 
                        c.value('(action[@name="query_plan_hash_signed"]/value/text())[1]', 'bigint')
                    ),
                query_hash_signed = 
                    CONVERT
                    (
                        binary(8), 
                        c.value('(action[@name="query_hash_signed"]/value/text())[1]', 'bigint')
                    ),
                plan_handle = c.value('xs:hexBinary((action[@name="plan_handle"]/value/text())[1])', 'varbinary(64)')
            FROM #human_events_xml AS xet
            OUTER APPLY xet.human_events_xml.nodes('//event') AS oa(c)
            WHERE c.exist('(action[@name="query_hash_signed"]/value[. != 0])') = 1
         )
         SELECT 
             q.*
         INTO #queries
         FROM queries AS q;
         
         IF @debug = 1 BEGIN SELECT N'#queries' AS table_name, * FROM #queries AS q; END;

         /* Add attribute StatementId to query plan if it is missing (versions before 2019) */
         WITH XMLNAMESPACES(DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
         UPDATE q1
             SET showplan_xml.modify('insert attribute StatementId {"1"} 
                                      into (/ShowPlanXML/BatchSequence/Batch/Statements/StmtSimple)[1]')
         FROM #queries AS q1
         CROSS APPLY 
         (
             SELECT TOP (1)
                 statement_text = q2.statement
             FROM #queries AS q2
             WHERE q1.query_hash_signed = q2.query_hash_signed
             AND   q1.query_plan_hash_signed = q2.query_plan_hash_signed
             AND   q2.statement IS NOT NULL
             ORDER BY q2.event_time DESC
         ) AS q2
         WHERE q1.showplan_xml IS NOT NULL
         AND   q1.showplan_xml.exist('/ShowPlanXML/BatchSequence/Batch/Statements/StmtSimple/@StatementId') = 0;
         
         /* Add attribute StatementText to query plan if it is missing (all versions) */
         WITH XMLNAMESPACES(DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
         UPDATE q1
             SET showplan_xml.modify('insert attribute StatementText {sql:column("q2.statement_text")} 
                                      into (/ShowPlanXML/BatchSequence/Batch/Statements/StmtSimple)[1]')
         FROM #queries AS q1
         CROSS APPLY 
         (
             SELECT TOP (1)
                 statement_text = q2.statement
             FROM #queries AS q2
             WHERE q1.query_hash_signed = q2.query_hash_signed
             AND   q1.query_plan_hash_signed = q2.query_plan_hash_signed
             AND   q2.statement IS NOT NULL
             ORDER BY q2.event_time DESC
         ) AS q2
         WHERE q1.showplan_xml IS NOT NULL 
         AND   q1.showplan_xml.exist('/ShowPlanXML/BatchSequence/Batch/Statements/StmtSimple/@StatementText') = 0;

         WITH query_agg AS 
         (
            SELECT 
                q.query_plan_hash_signed,
                q.query_hash_signed,
                plan_handle = CONVERT(varbinary(64), NULL),
                /*totals*/
                total_cpu_ms = ISNULL(q.cpu_ms, 0.),
                total_logical_reads = ISNULL(q.logical_reads, 0.),
                total_physical_reads = ISNULL(q.physical_reads, 0.),
                total_duration_ms = ISNULL(q.duration_ms, 0.),
                total_writes = ISNULL(q.writes, 0.),
                total_spills_mb = ISNULL(q.spills_mb, 0.),
                total_used_memory_mb = NULL,
                total_granted_memory_mb = NULL,
                total_rows = ISNULL(q.row_count, 0.),
                /*averages*/
                avg_cpu_ms = ISNULL(q.cpu_ms, 0.),
                avg_logical_reads = ISNULL(q.logical_reads, 0.),
                avg_physical_reads = ISNULL(q.physical_reads, 0.),
                avg_duration_ms = ISNULL(q.duration_ms, 0.),
                avg_writes = ISNULL(q.writes, 0.),
                avg_spills_mb = ISNULL(q.spills_mb, 0.),
                avg_used_memory_mb = NULL,
                avg_granted_memory_mb = NULL,
                avg_rows = ISNULL(q.row_count, 0)                    
            FROM #queries AS q
            WHERE q.event_type <> N'query_post_execution_showplan'
            
            UNION ALL 
            
            SELECT 
                q.query_plan_hash_signed,
                q.query_hash_signed,
                q.plan_handle,
                /*totals*/
                total_cpu_ms = NULL,
                total_logical_reads = NULL,
                total_physical_reads = NULL,
                total_duration_ms = NULL,
                total_writes = NULL,
                total_spills_mb = NULL,                        
                total_used_memory_mb = ISNULL(q.used_memory_mb, 0.),
                total_granted_memory_mb = ISNULL(q.granted_memory_mb, 0.),
                total_rows = NULL,
                /*averages*/
                avg_cpu_ms = NULL,
                avg_logical_reads = NULL,
                avg_physical_reads = NULL,
                avg_duration_ms = NULL,
                avg_writes = NULL,
                avg_spills_mb = NULL,
                avg_used_memory_mb = ISNULL(q.used_memory_mb, 0.),
                avg_granted_memory_mb = ISNULL(q.granted_memory_mb, 0.),
                avg_rows = NULL                     
            FROM #queries AS q
            WHERE q.event_type = N'query_post_execution_showplan'        
         )
         SELECT 
             qa.query_plan_hash_signed,
             qa.query_hash_signed,
             plan_handle = MAX(qa.plan_handle),
             total_cpu_ms = SUM(qa.total_cpu_ms),
             total_logical_reads_mb = SUM(qa.total_logical_reads),
             total_physical_reads_mb = SUM(qa.total_physical_reads),
             total_duration_ms = SUM(qa.total_duration_ms),
             total_writes_mb = SUM(qa.total_writes),
             total_spills_mb = SUM(qa.total_spills_mb),
             total_used_memory_mb = SUM(qa.total_used_memory_mb),
             total_granted_memory_mb = SUM(qa.total_granted_memory_mb),
             total_rows = SUM(qa.total_rows),
             avg_cpu_ms = AVG(qa.avg_cpu_ms),
             avg_logical_reads_mb = AVG(qa.avg_logical_reads),
             avg_physical_reads_mb = AVG(qa.avg_physical_reads),
             avg_duration_ms = AVG(qa.avg_duration_ms),
             avg_writes_mb = AVG(qa.avg_writes),
             avg_spills_mb = AVG(qa.avg_spills_mb),
             avg_used_memory_mb = AVG(qa.avg_used_memory_mb),
             avg_granted_memory_mb = AVG(qa.avg_granted_memory_mb),
             avg_rows = AVG(qa.avg_rows),
             executions = COUNT_BIG(qa.plan_handle)
         INTO #totals
         FROM query_agg AS qa
         GROUP BY 
             qa.query_plan_hash_signed,
             qa.query_hash_signed;
         
         IF @debug = 1 BEGIN SELECT N'#totals' AS table_name, * FROM #totals AS t; END;

         WITH query_results AS
         (
             SELECT 
                 q.event_time,
                 q.database_name,
                 q.object_name,
                 q2.statement_text,
                 q.sql_text,
                 q.showplan_xml,
                 t.executions,
                 t.total_cpu_ms,
                 t.avg_cpu_ms,
                 t.total_logical_reads_mb,
                 t.avg_logical_reads_mb,
                 t.total_physical_reads_mb,
                 t.avg_physical_reads_mb,
                 t.total_duration_ms,
                 t.avg_duration_ms,
                 t.total_writes_mb,
                 t.avg_writes_mb,
                 t.total_spills_mb,
                 t.avg_spills_mb,
                 t.total_used_memory_mb,
                 t.avg_used_memory_mb,
                 t.total_granted_memory_mb,
                 t.avg_granted_memory_mb,
                 t.total_rows,
                 t.avg_rows,
                 q.serial_ideal_memory_mb,
                 q.requested_memory_mb,
                 q.ideal_memory_mb,
                 q.estimated_rows,
                 q.dop,
                 q.query_plan_hash_signed,
                 q.query_hash_signed,
                 q.plan_handle,
                 n = 
                     ROW_NUMBER() 
                         OVER
                         ( 
                             PARTITION BY 
                                 q.query_plan_hash_signed, 
                                 q.query_hash_signed, 
                                 q.plan_handle
                             ORDER BY 
                                 q.query_plan_hash_signed, 
                                 q.query_hash_signed, 
                                 q.plan_handle 
                         )
             FROM #queries AS q
             JOIN #totals AS t
                 ON  q.query_hash_signed = t.query_hash_signed
                 AND q.query_plan_hash_signed = t.query_plan_hash_signed
                 AND q.plan_handle = t.plan_handle
             CROSS APPLY
             (
                 SELECT TOP (1) 
                     statement_text = 
                         q2.statement
                 FROM #queries AS q2
                 WHERE q.query_hash_signed = q2.query_hash_signed
                 AND   q.query_plan_hash_signed = q2.query_plan_hash_signed
                 AND   q2.statement IS NOT NULL
                 ORDER BY q2.event_time DESC
             ) AS q2
             WHERE q.showplan_xml.exist('*') = 1
         )
         SELECT 
             q.event_time,
             q.database_name,
             q.object_name,
             statement_text = 
                 (
                     SELECT
                         [processing-instruction(statement_text)] =
                             REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                             REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                             REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                 q.statement_text COLLATE Latin1_General_BIN2,
                             NCHAR(31),N'?'),NCHAR(30),N'?'),NCHAR(29),N'?'),NCHAR(28),N'?'),NCHAR(27),N'?'),NCHAR(26),N'?'),NCHAR(25),N'?'),NCHAR(24),N'?'),NCHAR(23),N'?'),NCHAR(22),N'?'),
                             NCHAR(21),N'?'),NCHAR(20),N'?'),NCHAR(19),N'?'),NCHAR(18),N'?'),NCHAR(17),N'?'),NCHAR(16),N'?'),NCHAR(15),N'?'),NCHAR(14),N'?'),NCHAR(12),N'?'),
                             NCHAR(11),N'?'),NCHAR(8),N'?'),NCHAR(7),N'?'),NCHAR(6),N'?'),NCHAR(5),N'?'),NCHAR(4),N'?'),NCHAR(3),N'?'),NCHAR(2),N'?'),NCHAR(1),N'?'),NCHAR(0),N'?')
                     FOR XML 
                         PATH(''), 
                         TYPE
                 ),
             sql_text = 
                 (
                     SELECT
                         [processing-instruction(sql_text)] =
                             REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                             REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                             REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                 q.sql_text COLLATE Latin1_General_BIN2,
                             NCHAR(31),N'?'),NCHAR(30),N'?'),NCHAR(29),N'?'),NCHAR(28),N'?'),NCHAR(27),N'?'),NCHAR(26),N'?'),NCHAR(25),N'?'),NCHAR(24),N'?'),NCHAR(23),N'?'),NCHAR(22),N'?'),
                             NCHAR(21),N'?'),NCHAR(20),N'?'),NCHAR(19),N'?'),NCHAR(18),N'?'),NCHAR(17),N'?'),NCHAR(16),N'?'),NCHAR(15),N'?'),NCHAR(14),N'?'),NCHAR(12),N'?'),
                             NCHAR(11),N'?'),NCHAR(8),N'?'),NCHAR(7),N'?'),NCHAR(6),N'?'),NCHAR(5),N'?'),NCHAR(4),N'?'),NCHAR(3),N'?'),NCHAR(2),N'?'),NCHAR(1),N'?'),NCHAR(0),N'?')
                     FOR XML 
                         PATH(''), 
                         TYPE
                 ),             
             q.showplan_xml,
             q.executions,
             q.total_cpu_ms,
             q.avg_cpu_ms,
             q.total_logical_reads_mb,
             q.avg_logical_reads_mb,
             q.total_physical_reads_mb,
             q.avg_physical_reads_mb,
             q.total_duration_ms,
             q.avg_duration_ms,
             q.total_writes_mb,
             q.avg_writes_mb,
             q.total_spills_mb,
             q.avg_spills_mb,
             q.total_used_memory_mb,
             q.avg_used_memory_mb,
             q.total_granted_memory_mb,
             q.avg_granted_memory_mb,
             q.total_rows,
             q.avg_rows,
             q.serial_ideal_memory_mb,
             q.requested_memory_mb,
             q.ideal_memory_mb,
             q.estimated_rows,
             q.dop,
             q.query_plan_hash_signed,
             q.query_hash_signed,
             q.plan_handle
         FROM query_results AS q
         WHERE q.n = 1
         ORDER BY 
              CASE @query_sort_order
                   WHEN N'cpu' THEN q.total_cpu_ms
                   WHEN N'reads' THEN q.total_logical_reads_mb + q.total_physical_reads_mb
                   WHEN N'writes' THEN q.total_writes_mb
                   WHEN N'duration' THEN q.total_duration_ms
                   WHEN N'spills' THEN q.total_spills_mb
                   WHEN N'memory' THEN q.total_granted_memory_mb
                   WHEN N'avg cpu' THEN q.avg_cpu_ms
                   WHEN N'avg reads' THEN q.avg_logical_reads_mb + q.avg_physical_reads_mb
                   WHEN N'avg writes' THEN q.avg_writes_mb
                   WHEN N'avg duration' THEN q.avg_duration_ms
                   WHEN N'avg spills' THEN q.avg_spills_mb
                   WHEN N'avg memory' THEN q.avg_granted_memory_mb
                   ELSE N'cpu'
              END DESC;
END;


IF LOWER(@event_type) LIKE N'%comp%' AND LOWER(@event_type) NOT LIKE N'%re%'
BEGIN

IF @compile_events = 1
    BEGIN
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
                event_type = c.value('@name', 'nvarchar(256)'),
                database_name = c.value('(action[@name="database_name"]/value/text())[1]', 'nvarchar(256)'),                
                object_name = c.value('(data[@name="object_name"]/value/text())[1]', 'nvarchar(256)'),
                statement_text = c.value('(data[@name="statement"]/value/text())[1]', 'nvarchar(MAX)'),
                compile_cpu_ms = c.value('(data[@name="cpu_time"]/value/text())[1]', 'bigint'),
                compile_duration_ms = c.value('(data[@name="duration"]/value/text())[1]', 'bigint')
            INTO #compiles_1
            FROM #human_events_xml AS xet
            OUTER APPLY xet.human_events_xml.nodes('//event') AS oa(c)
            WHERE c.exist('(data[@name="is_recompile"]/value[. = "false"])') = 1
            AND   c.exist('@name[.= "sql_statement_post_compile"]') = 1
            ORDER BY event_time;

            ALTER TABLE #compiles_1 ADD statement_text_checksum AS CHECKSUM(database_name + statement_text) PERSISTED;

            IF @debug = 1 BEGIN SELECT N'#compiles_1' AS table_name, * FROM #compiles_1 AS c; END;

            WITH cbq AS 
            (
                SELECT 
                    statement_text_checksum,
                    total_compiles = COUNT_BIG(*),
                    total_compile_cpu = SUM(compile_cpu_ms),
                    avg_compile_cpu = AVG(compile_cpu_ms),
                    max_compile_cpu = MAX(compile_cpu_ms),
                    total_compile_duration = SUM(compile_duration_ms),
                    avg_compile_duration = AVG(compile_duration_ms),
                    max_compile_duration = MAX(compile_duration_ms)
                FROM #compiles_1
                GROUP BY statement_text_checksum 
            )
            SELECT 
                pattern = N'total compiles',
                k.object_name,
                statement_text = 
                    (
                        SELECT
                            [processing-instruction(statement_text)] =
                                REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                    k.statement_text COLLATE Latin1_General_BIN2,
                                NCHAR(31),N'?'),NCHAR(30),N'?'),NCHAR(29),N'?'),NCHAR(28),N'?'),NCHAR(27),N'?'),NCHAR(26),N'?'),NCHAR(25),N'?'),NCHAR(24),N'?'),NCHAR(23),N'?'),NCHAR(22),N'?'),
                                NCHAR(21),N'?'),NCHAR(20),N'?'),NCHAR(19),N'?'),NCHAR(18),N'?'),NCHAR(17),N'?'),NCHAR(16),N'?'),NCHAR(15),N'?'),NCHAR(14),N'?'),NCHAR(12),N'?'),
                                NCHAR(11),N'?'),NCHAR(8),N'?'),NCHAR(7),N'?'),NCHAR(6),N'?'),NCHAR(5),N'?'),NCHAR(4),N'?'),NCHAR(3),N'?'),NCHAR(2),N'?'),NCHAR(1),N'?'),NCHAR(0),N'?')
                        FOR XML 
                            PATH(''), 
                            TYPE
                    ),                                
                c.total_compiles,
                c.total_compile_cpu,
                c.avg_compile_cpu,
                c.max_compile_cpu,
                c.total_compile_duration,
                c.avg_compile_duration,
                c.max_compile_duration
            FROM cbq AS c
            CROSS APPLY
            (
                SELECT TOP (1) 
                    k.*
                FROM #compiles_1 AS k
                WHERE c.statement_text_checksum = k.statement_text_checksum
                ORDER BY k.event_time DESC
            ) AS k
            ORDER BY c.total_compiles DESC;

    END;

IF @compile_events = 0
    BEGIN
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
                event_type = c.value('@name', 'nvarchar(256)'),
                database_name = c.value('(action[@name="database_name"]/value/text())[1]', 'nvarchar(256)'),                
                object_name = c.value('(data[@name="object_name"]/value/text())[1]', 'nvarchar(256)'),
                statement_text = c.value('(data[@name="statement"]/value/text())[1]', 'nvarchar(MAX)')
            INTO #compiles_0
            FROM #human_events_xml AS xet
            OUTER APPLY xet.human_events_xml.nodes('//event') AS oa(c)
            ORDER BY event_time;

            IF @debug = 1 BEGIN SELECT N'#compiles_0' AS table_name, * FROM #compiles_0 AS c; END;

            SELECT 
                c.event_time,
                c.event_type,
                c.database_name,
                c.object_name,
                statement_text = 
                    (
                        SELECT
                            [processing-instruction(statement_text)] =
                                REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                    c.statement_text COLLATE Latin1_General_BIN2,
                                NCHAR(31),N'?'),NCHAR(30),N'?'),NCHAR(29),N'?'),NCHAR(28),N'?'),NCHAR(27),N'?'),NCHAR(26),N'?'),NCHAR(25),N'?'),NCHAR(24),N'?'),NCHAR(23),N'?'),NCHAR(22),N'?'),
                                NCHAR(21),N'?'),NCHAR(20),N'?'),NCHAR(19),N'?'),NCHAR(18),N'?'),NCHAR(17),N'?'),NCHAR(16),N'?'),NCHAR(15),N'?'),NCHAR(14),N'?'),NCHAR(12),N'?'),
                                NCHAR(11),N'?'),NCHAR(8),N'?'),NCHAR(7),N'?'),NCHAR(6),N'?'),NCHAR(5),N'?'),NCHAR(4),N'?'),NCHAR(3),N'?'),NCHAR(2),N'?'),NCHAR(1),N'?'),NCHAR(0),N'?')
                        FOR XML 
                            PATH(''), 
                            TYPE
                    )
            FROM #compiles_0 AS c
            ORDER BY c.event_time;

    END;

IF @parameterization_events  = 1
    BEGIN
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
                event_type = c.value('@name', 'nvarchar(256)'),
                database_name = c.value('(action[@name="database_name"]/value/text())[1]', 'nvarchar(256)'),                
                sql_text = c.value('(action[@name="sql_text"]/value/text())[1]', 'nvarchar(MAX)'),
                compile_cpu_time_ms = c.value('(data[@name="compile_cpu_time"]/value/text())[1]', 'bigint') / 1000.,
                compile_duration_ms = c.value('(data[@name="compile_duration"]/value/text())[1]', 'bigint') / 1000.,
                query_param_type = c.value('(data[@name="query_param_type"]/value/text())[1]', 'int'),
                is_cached = c.value('(data[@name="is_cached"]/value/text())[1]', 'bit'),
                is_recompiled = c.value('(data[@name="is_recompiled"]/value/text())[1]', 'bit'),
                compile_code = c.value('(data[@name="compile_code"]/text)[1]', 'nvarchar(256)'),                  
                has_literals = c.value('(data[@name="has_literals"]/value/text())[1]', 'bit'),
                is_parameterizable = c.value('(data[@name="is_parameterizable"]/value/text())[1]', 'bit'),
                parameterized_values_count = c.value('(data[@name="parameterized_values_count"]/value/text())[1]', 'bigint'),
                query_plan_hash = c.value('xs:hexBinary((data[@name="query_plan_hash"]/value/text())[1])', 'binary(8)'),
                query_hash = c.value('xs:hexBinary((data[@name="query_hash"]/value/text())[1])', 'binary(8)'),
                plan_handle = c.value('xs:hexBinary((action[@name="plan_handle"]/value/text())[1])', 'varbinary(64)'), 
                statement_sql_hash = c.value('xs:hexBinary((data[@name="statement_sql_hash"]/value/text())[1])', 'varbinary(64)')
            INTO #parameterization
            FROM #human_events_xml AS xet
            OUTER APPLY xet.human_events_xml.nodes('//event') AS oa(c)
            WHERE c.exist('@name[. = "query_parameterization_data"]') = 1
            AND   c.exist('(data[@name="is_recompiled"]/value[. = "false"])') = 1
            ORDER BY event_time;

            IF @debug = 1 BEGIN SELECT N'#parameterization' AS table_name, * FROM #parameterization AS p; END;

            WITH cpq AS 
            (
                SELECT 
                    database_name,
                    query_hash,
                    total_compiles = COUNT_BIG(*),
                    plan_count = COUNT_BIG(DISTINCT query_plan_hash),
                    total_compile_cpu = SUM(compile_cpu_time_ms),
                    avg_compile_cpu = AVG(compile_cpu_time_ms),
                    max_compile_cpu = MAX(compile_cpu_time_ms),
                    total_compile_duration = SUM(compile_duration_ms),
                    avg_compile_duration = AVG(compile_duration_ms),
                    max_compile_duration = MAX(compile_duration_ms)
                FROM #parameterization
                GROUP BY 
                    database_name, 
                    query_hash
               )
               SELECT 
                   pattern = N'parameterization opportunities',
                   c.database_name,
                   sql_text = 
                       (
                           SELECT
                               [processing-instruction(sql_text)] =
                                   REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                   REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                   REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                       k.sql_text COLLATE Latin1_General_BIN2,
                                   NCHAR(31),N'?'),NCHAR(30),N'?'),NCHAR(29),N'?'),NCHAR(28),N'?'),NCHAR(27),N'?'),NCHAR(26),N'?'),NCHAR(25),N'?'),NCHAR(24),N'?'),NCHAR(23),N'?'),NCHAR(22),N'?'),
                                   NCHAR(21),N'?'),NCHAR(20),N'?'),NCHAR(19),N'?'),NCHAR(18),N'?'),NCHAR(17),N'?'),NCHAR(16),N'?'),NCHAR(15),N'?'),NCHAR(14),N'?'),NCHAR(12),N'?'),
                                   NCHAR(11),N'?'),NCHAR(8),N'?'),NCHAR(7),N'?'),NCHAR(6),N'?'),NCHAR(5),N'?'),NCHAR(4),N'?'),NCHAR(3),N'?'),NCHAR(2),N'?'),NCHAR(1),N'?'),NCHAR(0),N'?')
                           FOR XML 
                               PATH(''), 
                               TYPE
                       ),
                   k.is_parameterizable,
                   c.total_compiles,
                   c.plan_count,
                   c.total_compile_cpu,
                   c.avg_compile_cpu,
                   c.max_compile_cpu,
                   c.total_compile_duration,
                   c.avg_compile_duration,
                   c.max_compile_duration,
                   k.query_param_type,
                   k.is_cached,
                   k.is_recompiled,
                   k.compile_code,
                   k.has_literals,
                   k.parameterized_values_count
               FROM cpq AS c
               CROSS APPLY
               (
                   SELECT TOP (1) 
                       k.*
                   FROM #parameterization AS k
                   WHERE k.query_hash = c.query_hash
                   ORDER BY k.event_time DESC
               ) AS k
            ORDER BY c.total_compiles DESC;
    END;

END;


IF LOWER(@event_type) LIKE N'%recomp%'
BEGIN

IF @compile_events = 1
    BEGIN
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
                event_type = c.value('@name', 'nvarchar(256)'),
                database_name = c.value('(action[@name="database_name"]/value/text())[1]', 'nvarchar(256)'),                
                object_name = c.value('(data[@name="object_name"]/value/text())[1]', 'nvarchar(256)'),
                recompile_cause = c.value('(data[@name="recompile_cause"]/text)[1]', 'nvarchar(256)'),
                statement_text = c.value('(data[@name="statement"]/value/text())[1]', 'nvarchar(MAX)'),
                recompile_cpu_ms = c.value('(data[@name="cpu_time"]/value/text())[1]', 'bigint'),
                recompile_duration_ms = c.value('(data[@name="duration"]/value/text())[1]', 'bigint')
            INTO #recompiles_1
            FROM #human_events_xml AS xet
            OUTER APPLY xet.human_events_xml.nodes('//event') AS oa(c)
            WHERE c.exist('(data[@name="is_recompile"]/value[. = "false"])') = 0
            ORDER BY event_time;

            ALTER TABLE #recompiles_1 ADD statement_text_checksum AS CHECKSUM(database_name + statement_text) PERSISTED;

            IF @debug = 1 BEGIN SELECT N'#recompiles_1' AS table_name, * FROM #recompiles_1 AS r; END;

            WITH cbq AS 
            (
                SELECT 
                    statement_text_checksum,
                    total_recompiles = COUNT_BIG(*),
                    total_recompile_cpu = SUM(recompile_cpu_ms),
                    avg_recompile_cpu = AVG(recompile_cpu_ms),
                    max_recompile_cpu = MAX(recompile_cpu_ms),
                    total_recompile_duration = SUM(recompile_duration_ms),
                    avg_recompile_duration = AVG(recompile_duration_ms),
                    max_recompile_duration = MAX(recompile_duration_ms)
                FROM #recompiles_1
                GROUP BY statement_text_checksum 
            )
            SELECT 
                pattern = N'total recompiles',
                k.recompile_cause,
                k.object_name,
                statement_text = 
                    (
                        SELECT
                            [processing-instruction(statement_text)] =
                                REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                    k.statement_text COLLATE Latin1_General_BIN2,
                                NCHAR(31),N'?'),NCHAR(30),N'?'),NCHAR(29),N'?'),NCHAR(28),N'?'),NCHAR(27),N'?'),NCHAR(26),N'?'),NCHAR(25),N'?'),NCHAR(24),N'?'),NCHAR(23),N'?'),NCHAR(22),N'?'),
                                NCHAR(21),N'?'),NCHAR(20),N'?'),NCHAR(19),N'?'),NCHAR(18),N'?'),NCHAR(17),N'?'),NCHAR(16),N'?'),NCHAR(15),N'?'),NCHAR(14),N'?'),NCHAR(12),N'?'),
                                NCHAR(11),N'?'),NCHAR(8),N'?'),NCHAR(7),N'?'),NCHAR(6),N'?'),NCHAR(5),N'?'),NCHAR(4),N'?'),NCHAR(3),N'?'),NCHAR(2),N'?'),NCHAR(1),N'?'),NCHAR(0),N'?')
                        FOR XML 
                            PATH(''), 
                            TYPE
                    ),
                c.total_recompiles,
                c.total_recompile_cpu,
                c.avg_recompile_cpu,
                c.max_recompile_cpu,
                c.total_recompile_duration,
                c.avg_recompile_duration,
                c.max_recompile_duration
            FROM cbq AS c
            CROSS APPLY
            (
                SELECT TOP(1) *
                FROM #recompiles_1 AS k
                WHERE c.statement_text_checksum = k.statement_text_checksum
                ORDER BY k.event_time DESC
            ) AS k
            ORDER BY c.total_recompiles DESC;

    END;

IF @compile_events = 0
    BEGIN
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
                event_type = c.value('@name', 'nvarchar(256)'),
                database_name = c.value('(action[@name="database_name"]/value/text())[1]', 'nvarchar(256)'),                
                object_name = c.value('(data[@name="object_name"]/value/text())[1]', 'nvarchar(256)'),
                recompile_cause = c.value('(data[@name="recompile_cause"]/text)[1]', 'nvarchar(256)'),
                statement_text = c.value('(data[@name="statement"]/value/text())[1]', 'nvarchar(MAX)')
            INTO #recompiles_0
            FROM #human_events_xml AS xet
            OUTER APPLY xet.human_events_xml.nodes('//event') AS oa(c)
            ORDER BY event_time;

            IF @debug = 1 BEGIN SELECT N'#recompiles_0' AS table_name, * FROM #recompiles_0 AS r; END;

            SELECT 
                r.event_time,
                r.event_type,
                r.database_name,
                r.object_name,
                r.recompile_cause,
                statement_text = 
                    (
                        SELECT
                            [processing-instruction(statement_text)] =
                                REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                    r.statement_text COLLATE Latin1_General_BIN2,
                                NCHAR(31),N'?'),NCHAR(30),N'?'),NCHAR(29),N'?'),NCHAR(28),N'?'),NCHAR(27),N'?'),NCHAR(26),N'?'),NCHAR(25),N'?'),NCHAR(24),N'?'),NCHAR(23),N'?'),NCHAR(22),N'?'),
                                NCHAR(21),N'?'),NCHAR(20),N'?'),NCHAR(19),N'?'),NCHAR(18),N'?'),NCHAR(17),N'?'),NCHAR(16),N'?'),NCHAR(15),N'?'),NCHAR(14),N'?'),NCHAR(12),N'?'),
                                NCHAR(11),N'?'),NCHAR(8),N'?'),NCHAR(7),N'?'),NCHAR(6),N'?'),NCHAR(5),N'?'),NCHAR(4),N'?'),NCHAR(3),N'?'),NCHAR(2),N'?'),NCHAR(1),N'?'),NCHAR(0),N'?')
                        FOR XML 
                            PATH(''), 
                            TYPE
                    )
            FROM #recompiles_0 AS r
            ORDER BY r.event_time;

    END;
END;


IF LOWER(@event_type) LIKE N'%wait%'
BEGIN;
         WITH waits AS 
         (
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
                 event_type = c.value('@name', 'nvarchar(256)'),
                 database_name = c.value('(action[@name="database_name"]/value/text())[1]', 'nvarchar(256)'),                
                 wait_type = c.value('(data[@name="wait_type"]/text)[1]', 'nvarchar(256)'),
                 duration_ms = c.value('(data[@name="duration"]/value/text())[1]', 'bigint') ,
                 signal_duration_ms = c.value('(data[@name="signal_duration"]/value/text())[1]', 'bigint'),
                 wait_resource = 
                     CASE 
                         WHEN @v = 11 
                         THEN N'Not Available < 2014' 
                         ELSE c.value('(data[@name="wait_resource"]/value/text())[1]', 'nvarchar(256)') 
                     END,
                query_plan_hash_signed = 
                    CONVERT
                    (
                        binary(8), 
                        c.value('(action[@name="query_plan_hash_signed"]/value/text())[1]', 'bigint')
                    ),
                 query_hash_signed = 
                     CONVERT
                     (
                         binary(8), 
                         c.value('(action[@name="query_hash_signed"]/value/text())[1]', 'bigint')
                     ),
                 plan_handle = c.value('xs:hexBinary((action[@name="plan_handle"]/value/text())[1])', 'varbinary(64)')
             FROM 
             (
                 SELECT TOP (2147483647) 
                     xet.human_events_xml
                 FROM #human_events_xml AS xet
                 WHERE (xet.human_events_xml.exist('(//event/data[@name="duration"]/value[. > 0])') = 1 
                   OR      @gimme_danger = 1)
             ) AS c
             OUTER APPLY c.human_events_xml.nodes('//event') AS oa(c)
             )
             SELECT 
                 w.*
             INTO #waits_agg
             FROM waits AS w;
            
            IF @debug = 1 BEGIN SELECT N'#waits_agg' AS table_name, * FROM #waits_agg AS wa; END;

            SELECT 
                wait_pattern = N'total waits',
                min_event_time = MIN(wa.event_time),
                max_event_time = MAX(wa.event_time),
                wa.wait_type,
                total_waits = COUNT_BIG(*),
                sum_duration_ms = SUM(wa.duration_ms),
                sum_signal_duration_ms = SUM(wa.signal_duration_ms),
                avg_ms_per_wait = SUM(wa.duration_ms) / COUNT_BIG(*)
            FROM #waits_agg AS wa
            GROUP BY wa.wait_type
            ORDER BY sum_duration_ms DESC;            

            SELECT 
                wait_pattern = N'total waits by database',
                min_event_time = MIN(wa.event_time),
                max_event_time = MAX(wa.event_time),
                wa.database_name,
                wa.wait_type,
                total_waits = COUNT_BIG(*),
                sum_duration_ms = SUM(wa.duration_ms),
                sum_signal_duration_ms = SUM(wa.signal_duration_ms),
                avg_ms_per_wait = SUM(wa.duration_ms) / COUNT_BIG(*)
            FROM #waits_agg AS wa
            GROUP BY 
                wa.database_name, 
                wa.wait_type
            ORDER BY sum_duration_ms DESC; 

            WITH plan_waits AS 
            (
                SELECT 
                    wait_pattern = 
                        N'total waits by query and database',
                    min_event_time = 
                        MIN(wa.event_time),
                    max_event_time = 
                        MAX(wa.event_time),
                    wa.database_name,
                    wa.wait_type,
                    total_waits = 
                        COUNT_BIG(*),
                    wa.plan_handle,
                    sum_duration_ms = 
                        SUM(wa.duration_ms),
                    sum_signal_duration_ms = 
                        SUM(wa.signal_duration_ms),
                    avg_ms_per_wait = 
                        SUM(wa.duration_ms) / COUNT_BIG(*)
                FROM #waits_agg AS wa
                GROUP BY 
                    wa.database_name,
                    wa.wait_type, 
                    wa.plan_handle                 
            )
            SELECT 
                pw.wait_pattern,
                pw.min_event_time,
                pw.max_event_time,
                pw.database_name,
                pw.wait_type,
                pw.total_waits,
                pw.sum_duration_ms,
                pw.sum_signal_duration_ms,
                pw.avg_ms_per_wait,
                statement_text = 
                    (
                        SELECT
                            [processing-instruction(statement_text)] =
                                REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                    st.text COLLATE Latin1_General_BIN2,
                                NCHAR(31),N'?'),NCHAR(30),N'?'),NCHAR(29),N'?'),NCHAR(28),N'?'),NCHAR(27),N'?'),NCHAR(26),N'?'),NCHAR(25),N'?'),NCHAR(24),N'?'),NCHAR(23),N'?'),NCHAR(22),N'?'),
                                NCHAR(21),N'?'),NCHAR(20),N'?'),NCHAR(19),N'?'),NCHAR(18),N'?'),NCHAR(17),N'?'),NCHAR(16),N'?'),NCHAR(15),N'?'),NCHAR(14),N'?'),NCHAR(12),N'?'),
                                NCHAR(11),N'?'),NCHAR(8),N'?'),NCHAR(7),N'?'),NCHAR(6),N'?'),NCHAR(5),N'?'),NCHAR(4),N'?'),NCHAR(3),N'?'),NCHAR(2),N'?'),NCHAR(1),N'?'),NCHAR(0),N'?')
                        FOR XML 
                            PATH(''), 
                            TYPE
                    ),
                   qp.query_plan
            FROM plan_waits AS pw
            OUTER APPLY sys.dm_exec_query_plan(pw.plan_handle) AS qp
            OUTER APPLY sys.dm_exec_sql_text(pw.plan_handle) AS st
            ORDER BY pw.sum_duration_ms DESC;
END;


IF LOWER(@event_type) LIKE N'%lock%'
BEGIN

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
                spid = bd.value('(process/@spid)[1]', 'int'),
                ecid = bd.value('(process/@ecid)[1]', 'int'),            
                query_text_pre = bd.value('(process/inputbuf/text())[1]', 'nvarchar(MAX)'),
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
                activity = CASE WHEN oa.c.exist('//blocked-process-report/blocked-process') = 1 THEN 'blocked' END,
                blocked_process_report = c.query('.')
            INTO #blocked
            FROM #human_events_xml AS bx
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
                database_name = DB_NAME(c.value('(data[@name="database_id"]/value/text())[1]', 'int')),
                database_id = c.value('(data[@name="database_id"]/value/text())[1]', 'int'),
                object_id = c.value('(data[@name="object_id"]/value/text())[1]', 'int'),
                transaction_id = c.value('(data[@name="transaction_id"]/value/text())[1]', 'bigint'),
                resource_owner_type = c.value('(data[@name="resource_owner_type"]/text)[1]', 'nvarchar(256)'),
                monitor_loop = c.value('(//@monitorLoop)[1]', 'int'),
                spid = bg.value('(process/@spid)[1]', 'int'),
                ecid = bg.value('(process/@ecid)[1]', 'int'),
                query_text_pre = bg.value('(process/inputbuf/text())[1]', 'nvarchar(MAX)'),
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
                activity = CASE WHEN oa.c.exist('//blocked-process-report/blocking-process') = 1 THEN 'blocking' END,
                blocked_process_report = c.query('.')
            INTO #blocking
            FROM #human_events_xml AS bx
            OUTER APPLY bx.human_events_xml.nodes('//event') AS oa(c)
            OUTER APPLY oa.c.nodes('//blocked-process-report/blocking-process') AS bg(bg);

            IF @debug = 1 BEGIN SELECT '#blocking' AS table_name, * FROM #blocking AS wa; END;

            ALTER TABLE #blocked 
            ADD query_text 
            AS REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
               REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
               REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                   query_text_pre COLLATE Latin1_General_BIN2,
               NCHAR(31),N'?'),NCHAR(30),N'?'),NCHAR(29),N'?'),NCHAR(28),N'?'),NCHAR(27),N'?'),NCHAR(26),N'?'),NCHAR(25),N'?'),NCHAR(24),N'?'),NCHAR(23),N'?'),NCHAR(22),N'?'),
               NCHAR(21),N'?'),NCHAR(20),N'?'),NCHAR(19),N'?'),NCHAR(18),N'?'),NCHAR(17),N'?'),NCHAR(16),N'?'),NCHAR(15),N'?'),NCHAR(14),N'?'),NCHAR(12),N'?'),
               NCHAR(11),N'?'),NCHAR(8),N'?'),NCHAR(7),N'?'),NCHAR(6),N'?'),NCHAR(5),N'?'),NCHAR(4),N'?'),NCHAR(3),N'?'),NCHAR(2),N'?'),NCHAR(1),N'?'),NCHAR(0),N'?') 
            PERSISTED;

            ALTER TABLE #blocking 
            ADD query_text 
            AS REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
               REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
               REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                   query_text_pre COLLATE Latin1_General_BIN2,
               NCHAR(31),N'?'),NCHAR(30),N'?'),NCHAR(29),N'?'),NCHAR(28),N'?'),NCHAR(27),N'?'),NCHAR(26),N'?'),NCHAR(25),N'?'),NCHAR(24),N'?'),NCHAR(23),N'?'),NCHAR(22),N'?'),
               NCHAR(21),N'?'),NCHAR(20),N'?'),NCHAR(19),N'?'),NCHAR(18),N'?'),NCHAR(17),N'?'),NCHAR(16),N'?'),NCHAR(15),N'?'),NCHAR(14),N'?'),NCHAR(12),N'?'),
               NCHAR(11),N'?'),NCHAR(8),N'?'),NCHAR(7),N'?'),NCHAR(6),N'?'),NCHAR(5),N'?'),NCHAR(4),N'?'),NCHAR(3),N'?'),NCHAR(2),N'?'),NCHAR(1),N'?'),NCHAR(0),N'?') 
            PERSISTED;

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

END;

/* End magic happening */

IF @keep_alive = 0
BEGIN
    IF @debug = 1 BEGIN RAISERROR(@stop_sql, 0, 1) WITH NOWAIT; END;
    RAISERROR(N'all done, stopping session', 0, 1) WITH NOWAIT;
    EXEC (@stop_sql);
    
    IF @debug = 1 BEGIN RAISERROR(@drop_sql, 0, 1) WITH NOWAIT; END;
   RAISERROR(N'and dropping session', 0, 1) WITH NOWAIT;
   EXEC (@drop_sql);
END;
RETURN;


/*This section handles outputting data to tables*/
output_results:
RAISERROR(N'Starting data collection.', 0, 1) WITH NOWAIT;

WHILE 1 = 1
    BEGIN
    
    IF @azure = 0
    BEGIN
        IF NOT EXISTS
        (
            /*If we don't find any sessions to poll from, wait 5 seconds and restart loop*/
            SELECT 
                1/0
            FROM sys.server_event_sessions AS ses
            LEFT JOIN sys.dm_xe_sessions AS dxs
                ON dxs.name = ses.name
            WHERE ses.name LIKE N'keeper_HumanEvents_%'
            AND   dxs.create_time IS NOT NULL
        )
        BEGIN
            RAISERROR(N'No matching active session names found starting with keeper_HumanEvents', 0, 1) WITH NOWAIT;
        END;
        
        /*If we find any stopped sessions, turn them back on*/
        SELECT 
            @the_sleeper_must_awaken += 
                N'ALTER EVENT SESSION ' + 
                ses.name + 
                N' ON SERVER STATE = START;' + 
                @nc10
        FROM sys.server_event_sessions AS ses
        LEFT JOIN sys.dm_xe_sessions AS dxs
            ON dxs.name = ses.name
        WHERE ses.name LIKE N'keeper_HumanEvents_%'
        AND   dxs.create_time IS NULL;
    END;
    ELSE
    BEGIN
        /*If we don't find any sessions to poll from, wait 5 seconds and restart loop*/
        IF NOT EXISTS
        (
            SELECT 
                1/0
            FROM sys.database_event_sessions AS ses
            LEFT JOIN sys.dm_xe_database_sessions AS dxs
                ON dxs.name = ses.name
            WHERE ses.name LIKE N'keeper_HumanEvents_%'
            AND   dxs.create_time IS NOT NULL
        )
        BEGIN
            RAISERROR(N'No matching active session names found starting with keeper_HumanEvents', 0, 1) WITH NOWAIT;
        END;
        
        /*If we find any stopped sessions, turn them back on*/
        SELECT 
            @the_sleeper_must_awaken += 
                N'ALTER EVENT SESSION ' + 
                ses.name + 
                N' ON DATABASE STATE = START;' + 
                @nc10
        FROM sys.database_event_sessions AS ses
        LEFT JOIN sys.dm_xe_database_sessions AS dxs
            ON dxs.name = ses.name
        WHERE ses.name LIKE N'keeper_HumanEvents_%'
        AND   dxs.create_time IS NULL;
    END;

    IF LEN(@the_sleeper_must_awaken) > 0
    BEGIN     
     IF @debug = 1 BEGIN RAISERROR(@the_sleeper_must_awaken, 0, 1) WITH NOWAIT; END;
     RAISERROR(N'Starting keeper_HumanEvents... inactive sessions', 0, 1) WITH NOWAIT;
     
     EXEC sys.sp_executesql 
         @the_sleeper_must_awaken;
    END;

    IF 
    (
        SELECT
            COUNT_BIG(*)
        FROM #human_events_worker AS hew
    ) = 0
    BEGIN
    
        /*Insert any sessions we find*/
        IF @azure = 0
        BEGIN
            INSERT 
                #human_events_worker
            ( 
                event_type, 
                event_type_short, 
                is_table_created, 
                is_view_created, 
                last_checked, 
                last_updated, 
                output_database, 
                output_schema, 
                output_table 
            )        
            SELECT 
                s.name, 
                N'', 
                0, 
                0, 
                '19000101', 
                '19000101', 
                 @output_database_name, 
                 @output_schema_name, 
                 s.name
            FROM sys.server_event_sessions AS s
            LEFT JOIN sys.dm_xe_sessions AS r 
                ON r.name = s.name
            WHERE s.name LIKE N'keeper_HumanEvents_%'
            AND   r.create_time IS NOT NULL;
        END;
        ELSE
        BEGIN
            INSERT 
                #human_events_worker
            ( 
                event_type, 
                event_type_short, 
                is_table_created, 
                is_view_created, 
                last_checked, 
                last_updated, 
                output_database, 
                output_schema, 
                output_table 
            )        
            SELECT 
                s.name, 
                N'', 
                0, 
                0, 
                '19000101', 
                '19000101', 
                 @output_database_name, 
                 @output_schema_name, 
                 s.name
            FROM sys.database_event_sessions AS s
            LEFT JOIN sys.dm_xe_database_sessions AS r 
                ON r.name = s.name
            WHERE s.name LIKE N'keeper_HumanEvents_%'
            AND   r.create_time IS NOT NULL;
        END;

        /*If we're getting compiles, and the parameterization event is available*/
        /*Add a row to the table so we account for it*/
        IF @parameterization_events = 1
           AND EXISTS 
           ( 
               SELECT 
                   1/0 
               FROM #human_events_worker 
               WHERE event_type LIKE N'keeper_HumanEvents_compiles%' 
           )
        BEGIN
            INSERT 
                #human_events_worker 
            ( 
                event_type, 
                event_type_short, 
                is_table_created, 
                is_view_created, 
                last_checked, 
                last_updated, 
                output_database, 
                output_schema, 
                output_table 
            )
            SELECT 
                event_type + 
                N'_parameterization', 
                N'', 
                1, 
                0, 
                last_checked, 
                last_updated, 
                output_database, 
                output_schema, 
                output_table + N'_parameterization'
            FROM #human_events_worker 
            WHERE event_type LIKE N'keeper_HumanEvents_compiles%';
        END;

        /*Update this column for when we see if we need to create views.*/
        UPDATE hew
            SET hew.event_type_short = 
                    CASE 
                        WHEN hew.event_type LIKE N'%block%' 
                        THEN N'[_]Blocking'
                        WHEN ( hew.event_type LIKE N'%comp%' 
                                 AND hew.event_type NOT LIKE N'%re%' )
                        THEN N'[_]Compiles'
                        WHEN hew.event_type LIKE N'%quer%'
                        THEN N'[_]Queries'
                        WHEN hew.event_type LIKE N'%recomp%'
                        THEN N'[_]Recompiles'
                        WHEN hew.event_type LIKE N'%wait%'
                        THEN N'[_]Waits'
                        ELSE N'?'
                    END    
        FROM #human_events_worker AS hew
        WHERE hew.event_type_short = N'';

        IF @debug = 1 BEGIN SELECT N'#human_events_worker' AS table_name, * FROM #human_events_worker; END;

    END;

    /*This section is where tables that need tables get created*/
    IF EXISTS
    (
        SELECT 
            1/0
        FROM #human_events_worker AS hew
        WHERE hew.is_table_created = 0   
    )
    BEGIN
        RAISERROR(N'Sessions without tables found, starting loop.', 0, 1) WITH NOWAIT;
        
        SELECT 
            @min_id = 
                MIN(hew.id), 
            @max_id = 
                MAX(hew.id)
        FROM #human_events_worker AS hew
        WHERE hew.is_table_created = 0;
        
        RAISERROR(N'While, while, while...', 0, 1) WITH NOWAIT;
        WHILE @min_id <= @max_id
        BEGIN
            SELECT 
                @event_type_check  = 
                    hew.event_type,
                @object_name_check = 
                    QUOTENAME(hew.output_database) + 
                    N'.' + 
                    QUOTENAME(hew.output_schema) + 
                    N'.' + 
                    hew.output_table
            FROM #human_events_worker AS hew
            WHERE hew.id = @min_id
            AND   hew.is_table_created = 0;
        
            IF OBJECT_ID(@object_name_check) IS NULL
            BEGIN
            RAISERROR(N'Generating create table statement for %s', 0, 1, @event_type_check) WITH NOWAIT;
                SELECT 
                    @table_sql = 
                        CASE 
                            WHEN @event_type_check LIKE N'%wait%'
                            THEN N'CREATE TABLE ' + @object_name_check + @nc10 +
                                 N'( id bigint PRIMARY KEY IDENTITY, server_name sysname NULL, event_time datetime2 NULL, event_type sysname NULL,  ' + @nc10 +
                                 N'  database_name sysname NULL, wait_type nvarchar(60) NULL, duration_ms bigint NULL, signal_duration_ms bigint NULL, ' + @nc10 +
                                 N'  wait_resource nvarchar(256) NULL,  query_plan_hash_signed binary(8) NULL, query_hash_signed binary(8) NULL, plan_handle varbinary(64) NULL );'
                            WHEN @event_type_check LIKE N'%lock%'
                            THEN N'CREATE TABLE ' + @object_name_check + @nc10 +
                                 N'( id bigint PRIMARY KEY IDENTITY, server_name sysname NULL, event_time datetime2 NULL, ' + @nc10 +
                                 N'  activity nvarchar(20) NULL, database_name sysname NULL, database_id integer NULL, object_id bigint NULL, contentious_object AS OBJECT_NAME(object_id, database_id), ' + @nc10 +
                                 N'  transaction_id bigint NULL, resource_owner_type nvarchar(256) NULL, monitor_loop integer NULL, spid integer NULL, ecid integer NULL, query_text nvarchar(MAX) NULL, ' + 
                                 N'  wait_time bigint NULL, transaction_name nvarchar(256) NULL,  last_transaction_started nvarchar(30) NULL, wait_resource nvarchar(100) NULL, ' + @nc10 +
                                 N'  lock_mode nvarchar(10) NULL, status nvarchar(10) NULL, priority integer NULL, transaction_count integer NULL, ' + @nc10 +
                                 N'  client_app sysname NULL, host_name sysname NULL, login_name sysname NULL, isolation_level nvarchar(30) NULL, sql_handle varbinary(64) NULL, blocked_process_report XML NULL );'
                            WHEN @event_type_check LIKE N'%quer%'
                            THEN N'CREATE TABLE ' + @object_name_check + @nc10 +
                                 N'( id bigint PRIMARY KEY IDENTITY, server_name sysname NULL, event_time datetime2 NULL, event_type sysname NULL, ' + @nc10 +
                                 N'  database_name sysname NULL, object_name nvarchar(512) NULL, sql_text nvarchar(MAX) NULL, statement nvarchar(MAX) NULL, ' + @nc10 +
                                 N'  showplan_xml XML NULL, cpu_ms decimal(18,2) NULL, logical_reads decimal(18,2) NULL, ' + @nc10 +
                                 N'  physical_reads decimal(18,2) NULL,  duration_ms decimal(18,2) NULL, writes_mb decimal(18,2) NULL,' + @nc10 +
                                 N'  spills_mb decimal(18,2) NULL, row_count decimal(18,2) NULL, estimated_rows decimal(18,2) NULL, dop integer NULL,  ' + @nc10 +
                                 N'  serial_ideal_memory_mb decimal(18,2) NULL, requested_memory_mb decimal(18,2) NULL, used_memory_mb decimal(18,2) NULL, ideal_memory_mb decimal(18,2) NULL, ' + @nc10 +
                                 N'  granted_memory_mb decimal(18,2) NULL, query_plan_hash_signed binary(8) NULL, query_hash_signed binary(8) NULL, plan_handle varbinary(64) NULL );'
                            WHEN @event_type_check LIKE N'%recomp%'
                            THEN N'CREATE TABLE ' + @object_name_check + @nc10 +
                                 N'( id bigint PRIMARY KEY IDENTITY, server_name sysname NULL, event_time datetime2 NULL,  event_type sysname NULL,  ' + @nc10 +
                                 N'  database_name sysname NULL, object_name nvarchar(512) NULL, recompile_cause nvarchar(256) NULL, statement_text nvarchar(MAX) NULL, statement_text_checksum AS CHECKSUM(database_name + statement_text) PERSISTED '
                                 + CASE WHEN @compile_events = 1 THEN N', compile_cpu_ms bigint NULL, compile_duration_ms bigint NULL );' ELSE N' );' END
                            WHEN @event_type_check LIKE N'%comp%' AND @event_type_check NOT LIKE N'%re%'
                            THEN N'CREATE TABLE ' + @object_name_check + @nc10 +
                                 N'( id bigint PRIMARY KEY IDENTITY, server_name sysname NULL, event_time datetime2 NULL,  event_type sysname NULL,  ' + @nc10 +
                                 N'  database_name sysname NULL, object_name nvarchar(512) NULL, statement_text nvarchar(MAX) NULL, statement_text_checksum AS CHECKSUM(database_name + statement_text) PERSISTED '
                                 + CASE WHEN @compile_events = 1 THEN N', compile_cpu_ms bigint NULL, compile_duration_ms bigint NULL );' ELSE N' );' END
                                 + CASE WHEN @parameterization_events = 1 
                                        THEN 
                                 @nc10 + 
                                 N'CREATE TABLE ' + @object_name_check + N'_parameterization' + @nc10 +
                                 N'( id bigint PRIMARY KEY IDENTITY, server_name sysname NULL, event_time datetime2 NULL,  event_type sysname NULL,  ' + @nc10 +
                                 N'  database_name sysname NULL, sql_text nvarchar(MAX) NULL, compile_cpu_time_ms bigint NULL, compile_duration_ms bigint NULL, query_param_type integer NULL,  ' + @nc10 +
                                 N'  is_cached bit NULL, is_recompiled bit NULL, compile_code nvarchar(256) NULL, has_literals bit NULL, is_parameterizable bit NULL, parameterized_values_count bigint NULL, ' + @nc10 +
                                 N'  query_plan_hash binary(8) NULL, query_hash binary(8) NULL, plan_handle varbinary(64) NULL, statement_sql_hash varbinary(64) NULL );'
                                        ELSE N'' 
                                   END  
                            ELSE N''
                      END;          
            END;        
            
            IF @debug = 1 BEGIN RAISERROR(@table_sql, 0, 1) WITH NOWAIT; END;
            EXEC sys.sp_executesql 
                @table_sql;
            
            RAISERROR(N'Updating #human_events_worker to set is_table_created for %s', 0, 1, @event_type_check) WITH NOWAIT;
            UPDATE #human_events_worker 
                SET is_table_created = 1 
            WHERE id = @min_id 
            AND is_table_created = 0;

            IF @debug = 1 BEGIN RAISERROR(N'@min_id: %i', 0, 1, @min_id) WITH NOWAIT; END;

            RAISERROR(N'Setting next id after %i out of %i total', 0, 1, @min_id, @max_id) WITH NOWAIT;
            
            SET @min_id = 
            (
                SELECT TOP (1) 
                    hew.id
                FROM #human_events_worker AS hew
                WHERE hew.id > @min_id
                AND   hew.is_table_created = 0
                ORDER BY hew.id
            );

            IF @debug = 1 BEGIN RAISERROR(N'new @min_id: %i', 0, 1, @min_id) WITH NOWAIT; END;

            IF @min_id IS NULL BREAK;

        END;
    END;

    /*This section handles creating or altering views*/
    IF EXISTS
    (   /* Any views not created */
        SELECT 
            1/0
        FROM #human_events_worker AS hew
        WHERE hew.is_table_created = 1
        AND   hew.is_view_created = 0
    ) 
    OR 
    (   /* If the proc has been modified, maybe views have been added or changed? */
        SELECT 
            modify_date 
        FROM sys.all_objects
        WHERE type = N'P'
        AND name = N'sp_HumanEvents' 
    ) < DATEADD(HOUR, -1, SYSDATETIME())
    BEGIN

    RAISERROR(N'Found views to create, beginning!', 0, 1) WITH NOWAIT;

        IF 
        (
            SELECT
                COUNT_BIG(*)
            FROM #view_check AS vc
        ) = 0
        BEGIN
            
            RAISERROR(N'#view_check was empty, creating and populating', 0, 1) WITH NOWAIT;
            
            /* These binary values are the view definitions. If I didn't do this, I would have been adding >50k lines of code in here. */
            INSERT #view_check (view_name, view_definition)
            SELECT N'HumanEvents_Blocking', 0x4300520045004100540045002000560049004500570020005B00640062006F005D002E005B00480075006D0061006E004500760065006E00740073005F0042006C006F0063006B0069006E0067005D000D000A00410053000D000A00530045004C00450043005400200054004F00500020002800320031003400370034003800330036003400370029000D000A00200020002000200020002000200020002000200020006B006800650062002E006500760065006E0074005F00740069006D0065002C000D000A00200020002000200020002000200020002000200020006B006800650062002E00640061007400610062006100730065005F006E0061006D0065002C000D000A00200020002000200020002000200020002000200020006B006800650062002E0063006F006E00740065006E00740069006F00750073005F006F0062006A006500630074002C000D000A00200020002000200020002000200020002000200020006B006800650062002E00610063007400690076006900740079002C000D000A00200020002000200020002000200020002000200020006B006800650062002E0073007000690064002C000D000A00200020002000200020002000200020002000200020006B006800650062002E00710075006500720079005F0074006500780074002C000D000A00200020002000200020002000200020002000200020006B006800650062002E0077006100690074005F00740069006D0065002C000D000A00200020002000200020002000200020002000200020006B006800650062002E007300740061007400750073002C000D000A00200020002000200020002000200020002000200020006B006800650062002E00690073006F006C006100740069006F006E005F006C006500760065006C002C000D000A00200020002000200020002000200020002000200020006B006800650062002E006C006100730074005F007400720061006E00730061006300740069006F006E005F0073007400610072007400650064002C000D000A00200020002000200020002000200020002000200020006B006800650062002E007400720061006E00730061006300740069006F006E005F006E0061006D0065002C000D000A00200020002000200020002000200020002000200020006B006800650062002E006C006F0063006B005F006D006F00640065002C000D000A00200020002000200020002000200020002000200020006B006800650062002E007000720069006F0072006900740079002C000D000A00200020002000200020002000200020002000200020006B006800650062002E007400720061006E00730061006300740069006F006E005F0063006F0075006E0074002C000D000A00200020002000200020002000200020002000200020006B006800650062002E0063006C00690065006E0074005F006100700070002C000D000A00200020002000200020002000200020002000200020006B006800650062002E0068006F00730074005F006E0061006D0065002C000D000A00200020002000200020002000200020002000200020006B006800650062002E006C006F00670069006E005F006E0061006D0065002C000D000A00200020002000200020002000200020002000200020006B006800650062002E0062006C006F0063006B00650064005F00700072006F0063006500730073005F007200650070006F00720074000D000A00460052004F004D0020005B007200650070006C006100630065005F006D0065005D0020004100530020006B006800650062000D000A004F00520044004500520020004200590020006B006800650062002E006500760065006E0074005F00740069006D0065002C000D000A00200020002000200020002000200020002000430041005300450020005700480045004E0020006B006800650062002E006100630074006900760069007400790020003D002000270062006C006F0063006B0069006E006700270020005400480045004E00200031000D000A002000200020002000200020002000200020002000200020002000200045004C0053004500200039003900390020000D000A0020002000200020002000200020002000200045004E0044003B00;
            INSERT #view_check (view_name, view_definition)
            SELECT N'HumanEvents_CompilesByDatabaseAndObject', 0x0D000A000D000A00430052004500410054004500200056004900450057002000640062006F002E00480075006D0061006E004500760065006E00740073005F0043006F006D00700069006C0065007300420079004400610074006100620061007300650041006E0064004F0062006A006500630074000D000A00410053000D000A002000200020002000530045004C00450043005400200054004F005000280020003200310034003700340038003300360034003800200029000D000A00200020002000200020002000200020002000200020004D0049004E0028006500760065006E0074005F00740069006D006500290020004100530020006D0069006E005F006500760065006E0074005F00740069006D0065002C000D000A00200020002000200020002000200020002000200020004D004100580028006500760065006E0074005F00740069006D006500290020004100530020006D00610078005F006500760065006E0074005F00740069006D0065002C000D000A0020002000200020002000200020002000200020002000640061007400610062006100730065005F006E0061006D0065002C000D000A0020002000200020002000200020002000200020002000430041005300450020005700480045004E0020006F0062006A006500630074005F006E0061006D00650020003D0020004E00270027000D000A0020002000200020002000200020002000200020002000200020002000200020005400480045004E0020004E0027004E002F00410027000D000A0020002000200020002000200020002000200020002000200020002000200045004C005300450020006F0062006A006500630074005F006E0061006D0065000D000A002000200020002000200020002000200020002000200045004E00440020004100530020006F0062006A006500630074005F006E0061006D0065002C000D000A002000200020002000200020002000200020002000200043004F0055004E0054005F0042004900470028002A002900200041005300200074006F00740061006C005F0063006F006D00700069006C00650073002C000D000A0020002000200020002000200020002000200020002000530055004D00280063006F006D00700069006C0065005F006300700075005F006D0073002900200041005300200074006F00740061006C005F0063006F006D00700069006C0065005F006300700075002C000D000A0020002000200020002000200020002000200020002000410056004700280063006F006D00700069006C0065005F006300700075005F006D007300290020004100530020006100760067005F0063006F006D00700069006C0065005F006300700075002C000D000A00200020002000200020002000200020002000200020004D0041005800280063006F006D00700069006C0065005F006300700075005F006D007300290020004100530020006D00610078005F0063006F006D00700069006C0065005F006300700075002C000D000A0020002000200020002000200020002000200020002000530055004D00280063006F006D00700069006C0065005F006400750072006100740069006F006E005F006D0073002900200041005300200074006F00740061006C005F0063006F006D00700069006C0065005F006400750072006100740069006F006E002C000D000A0020002000200020002000200020002000200020002000410056004700280063006F006D00700069006C0065005F006400750072006100740069006F006E005F006D007300290020004100530020006100760067005F0063006F006D00700069006C0065005F006400750072006100740069006F006E002C000D000A00200020002000200020002000200020002000200020004D0041005800280063006F006D00700069006C0065005F006400750072006100740069006F006E005F006D007300290020004100530020006D00610078005F0063006F006D00700069006C0065005F006400750072006100740069006F006E000D000A002000200020002000460052004F004D0020005B007200650070006C006100630065005F006D0065005D000D000A002000200020002000470052004F00550050002000420059002000640061007400610062006100730065005F006E0061006D0065002C0020006F0062006A006500630074005F006E0061006D0065000D000A0020002000200020004F005200440045005200200042005900200074006F00740061006C005F0063006F006D00700069006C0065007300200044004500530043003B000D000A00
            WHERE @compile_events = 1;
            INSERT #view_check (view_name, view_definition)
            SELECT N'HumanEvents_CompilesByDuration', 0x0D000A000D000A00430052004500410054004500200056004900450057002000640062006F002E00480075006D0061006E004500760065006E00740073005F0043006F006D00700069006C0065007300420079004400750072006100740069006F006E000D000A00410053000D000A002000200020002000570049005400480020006300620071000D000A0020002000200020002000200041005300200028000D000A00200020002000200020002000200020002000530045004C004500430054002000730074006100740065006D0065006E0074005F0074006500780074005F0063006800650063006B00730075006D002C000D000A00200020002000200020002000200020002000200020002000200020002000200043004F0055004E0054005F0042004900470028002A002900200041005300200074006F00740061006C005F0063006F006D00700069006C00650073002C000D000A002000200020002000200020002000200020002000200020002000200020002000530055004D00280063006F006D00700069006C0065005F006300700075005F006D0073002900200041005300200074006F00740061006C005F0063006F006D00700069006C0065005F006300700075002C000D000A002000200020002000200020002000200020002000200020002000200020002000410056004700280063006F006D00700069006C0065005F006300700075005F006D007300290020004100530020006100760067005F0063006F006D00700069006C0065005F006300700075002C000D000A0020002000200020002000200020002000200020002000200020002000200020004D0041005800280063006F006D00700069006C0065005F006300700075005F006D007300290020004100530020006D00610078005F0063006F006D00700069006C0065005F006300700075002C000D000A002000200020002000200020002000200020002000200020002000200020002000530055004D00280063006F006D00700069006C0065005F006400750072006100740069006F006E005F006D0073002900200041005300200074006F00740061006C005F0063006F006D00700069006C0065005F006400750072006100740069006F006E002C000D000A002000200020002000200020002000200020002000200020002000200020002000410056004700280063006F006D00700069006C0065005F006400750072006100740069006F006E005F006D007300290020004100530020006100760067005F0063006F006D00700069006C0065005F006400750072006100740069006F006E002C000D000A0020002000200020002000200020002000200020002000200020002000200020004D0041005800280063006F006D00700069006C0065005F006400750072006100740069006F006E005F006D007300290020004100530020006D00610078005F0063006F006D00700069006C0065005F006400750072006100740069006F006E000D000A00200020002000200020002000200020002000460052004F004D0020005B007200650070006C006100630065005F006D0065005D000D000A00200020002000200020002000200020002000470052004F00550050002000420059002000730074006100740065006D0065006E0074005F0074006500780074005F0063006800650063006B00730075006D000D000A0020002000200020002000200020002000200048004100560049004E0047002000410056004700280063006F006D00700069006C0065005F006400750072006100740069006F006E005F006D007300290020003E0020003100300030003000200029000D000A002000200020002000530045004C00450043005400200054004F005000280020003200310034003700340038003300360034003800200029000D000A00200020002000200020002000200020002000200020006B002E006F0062006A006500630074005F006E0061006D0065002C000D000A00200020002000200020002000200020002000200020006B002E00730074006100740065006D0065006E0074005F0074006500780074002C000D000A002000200020002000200020002000200020002000200063002E0074006F00740061006C005F0063006F006D00700069006C00650073002C000D000A002000200020002000200020002000200020002000200063002E0074006F00740061006C005F0063006F006D00700069006C0065005F006300700075002C000D000A002000200020002000200020002000200020002000200063002E006100760067005F0063006F006D00700069006C0065005F006300700075002C000D000A002000200020002000200020002000200020002000200063002E006D00610078005F0063006F006D00700069006C0065005F006300700075002C000D000A002000200020002000200020002000200020002000200063002E0074006F00740061006C005F0063006F006D00700069006C0065005F006400750072006100740069006F006E002C000D000A002000200020002000200020002000200020002000200063002E006100760067005F0063006F006D00700069006C0065005F006400750072006100740069006F006E002C000D000A002000200020002000200020002000200020002000200063002E006D00610078005F0063006F006D00700069006C0065005F006400750072006100740069006F006E000D000A002000200020002000460052004F004D002000630062007100200041005300200063000D000A002000200020002000430052004F005300530020004100500050004C0059000D000A002000200020002000200020002000200028000D000A00200020002000200020002000200020002000200020002000530045004C00450043005400200054004F005000280020003100200029000D000A0020002000200020002000200020002000200020002000200020002000200020002000200020002A000D000A00200020002000200020002000200020002000200020002000460052004F004D0020005B007200650070006C006100630065005F006D0065005D0020004100530020006B000D000A0020002000200020002000200020002000200020002000200057004800450052004500200063002E00730074006100740065006D0065006E0074005F0074006500780074005F0063006800650063006B00730075006D0020003D0020006B002E00730074006100740065006D0065006E0074005F0074006500780074005F0063006800650063006B00730075006D000D000A002000200020002000200020002000200020002000200020004F00520044004500520020004200590020006B002E0069006400200044004500530043000D000A0020002000200020002000200020002000290020004100530020006B000D000A0020002000200020004F005200440045005200200042005900200063002E006100760067005F0063006F006D00700069006C0065005F006400750072006100740069006F006E00200044004500530043003B000D000A00
            WHERE @compile_events = 1;
            INSERT #view_check (view_name, view_definition)
            SELECT N'HumanEvents_CompilesByQuery', 0x0D000A000D000A00430052004500410054004500200056004900450057002000640062006F002E00480075006D0061006E004500760065006E00740073005F0043006F006D00700069006C006500730042007900510075006500720079000D000A00410053000D000A002000200020002000570049005400480020006300620071000D000A0020002000200020002000200041005300200028000D000A00200020002000200020002000200020002000530045004C004500430054002000730074006100740065006D0065006E0074005F0074006500780074005F0063006800650063006B00730075006D002C000D000A00200020002000200020002000200020002000200020002000200020002000200043004F0055004E0054005F0042004900470028002A002900200041005300200074006F00740061006C005F0063006F006D00700069006C00650073002C000D000A002000200020002000200020002000200020002000200020002000200020002000530055004D00280063006F006D00700069006C0065005F006300700075005F006D0073002900200041005300200074006F00740061006C005F0063006F006D00700069006C0065005F006300700075002C000D000A002000200020002000200020002000200020002000200020002000200020002000410056004700280063006F006D00700069006C0065005F006300700075005F006D007300290020004100530020006100760067005F0063006F006D00700069006C0065005F006300700075002C000D000A0020002000200020002000200020002000200020002000200020002000200020004D0041005800280063006F006D00700069006C0065005F006300700075005F006D007300290020004100530020006D00610078005F0063006F006D00700069006C0065005F006300700075002C000D000A002000200020002000200020002000200020002000200020002000200020002000530055004D00280063006F006D00700069006C0065005F006400750072006100740069006F006E005F006D0073002900200041005300200074006F00740061006C005F0063006F006D00700069006C0065005F006400750072006100740069006F006E002C000D000A002000200020002000200020002000200020002000200020002000200020002000410056004700280063006F006D00700069006C0065005F006400750072006100740069006F006E005F006D007300290020004100530020006100760067005F0063006F006D00700069006C0065005F006400750072006100740069006F006E002C000D000A0020002000200020002000200020002000200020002000200020002000200020004D0041005800280063006F006D00700069006C0065005F006400750072006100740069006F006E005F006D007300290020004100530020006D00610078005F0063006F006D00700069006C0065005F006400750072006100740069006F006E000D000A00200020002000200020002000200020002000460052004F004D0020005B007200650070006C006100630065005F006D0065005D000D000A00200020002000200020002000200020002000470052004F00550050002000420059002000730074006100740065006D0065006E0074005F0074006500780074005F0063006800650063006B00730075006D000D000A0020002000200020002000200020002000200048004100560049004E004700200043004F0055004E0054005F0042004900470028002A00290020003E003D00200031003000200029000D000A002000200020002000530045004C00450043005400200054004F005000280020003200310034003700340038003300360034003800200029000D000A00200020002000200020002000200020002000200020006B002E006F0062006A006500630074005F006E0061006D0065002C000D000A00200020002000200020002000200020002000200020006B002E00730074006100740065006D0065006E0074005F0074006500780074002C000D000A002000200020002000200020002000200020002000200063002E0074006F00740061006C005F0063006F006D00700069006C00650073002C000D000A002000200020002000200020002000200020002000200063002E0074006F00740061006C005F0063006F006D00700069006C0065005F006300700075002C000D000A002000200020002000200020002000200020002000200063002E006100760067005F0063006F006D00700069006C0065005F006300700075002C000D000A002000200020002000200020002000200020002000200063002E006D00610078005F0063006F006D00700069006C0065005F006300700075002C000D000A002000200020002000200020002000200020002000200063002E0074006F00740061006C005F0063006F006D00700069006C0065005F006400750072006100740069006F006E002C000D000A002000200020002000200020002000200020002000200063002E006100760067005F0063006F006D00700069006C0065005F006400750072006100740069006F006E002C000D000A002000200020002000200020002000200020002000200063002E006D00610078005F0063006F006D00700069006C0065005F006400750072006100740069006F006E000D000A002000200020002000460052004F004D002000630062007100200041005300200063000D000A002000200020002000430052004F005300530020004100500050004C0059000D000A002000200020002000200020002000200028000D000A00200020002000200020002000200020002000200020002000530045004C00450043005400200054004F005000280020003100200029000D000A0020002000200020002000200020002000200020002000200020002000200020002000200020002A000D000A00200020002000200020002000200020002000200020002000460052004F004D0020005B007200650070006C006100630065005F006D0065005D0020004100530020006B000D000A0020002000200020002000200020002000200020002000200057004800450052004500200063002E00730074006100740065006D0065006E0074005F0074006500780074005F0063006800650063006B00730075006D0020003D0020006B002E00730074006100740065006D0065006E0074005F0074006500780074005F0063006800650063006B00730075006D000D000A002000200020002000200020002000200020002000200020004F00520044004500520020004200590020006B002E0069006400200044004500530043000D000A0020002000200020002000200020002000290020004100530020006B000D000A0020002000200020004F005200440045005200200042005900200063002E0074006F00740061006C005F0063006F006D00700069006C0065007300200044004500530043003B000D000A00
            WHERE @compile_events = 1;
            INSERT #view_check (view_name, view_definition)
            SELECT N'HumanEvents_Parameterization', 0x0D000A000D000A00430052004500410054004500200056004900450057002000640062006F002E00480075006D0061006E004500760065006E00740073005F0050006100720061006D00650074006500720069007A006100740069006F006E000D000A00410053000D000A002000200020002000570049005400480020006300700071000D000A0020002000200020002000200041005300200028000D000A00200020002000200020002000200020002000530045004C004500430054002000640061007400610062006100730065005F006E0061006D0065002C000D000A002000200020002000200020002000200020002000200020002000200020002000710075006500720079005F0068006100730068002C000D000A00200020002000200020002000200020002000200020002000200020002000200043004F0055004E0054005F0042004900470028002A002900200041005300200074006F00740061006C005F0063006F006D00700069006C00650073002C000D000A00200020002000200020002000200020002000200020002000200020002000200043004F0055004E0054002800440049005300540049004E00430054002000710075006500720079005F0070006C0061006E005F0068006100730068002900200041005300200070006C0061006E005F0063006F0075006E0074002C000D000A002000200020002000200020002000200020002000200020002000200020002000530055004D00280063006F006D00700069006C0065005F006300700075005F00740069006D0065005F006D0073002900200041005300200074006F00740061006C005F0063006F006D00700069006C0065005F006300700075002C000D000A002000200020002000200020002000200020002000200020002000200020002000410056004700280063006F006D00700069006C0065005F006300700075005F00740069006D0065005F006D007300290020004100530020006100760067005F0063006F006D00700069006C0065005F006300700075002C000D000A0020002000200020002000200020002000200020002000200020002000200020004D0041005800280063006F006D00700069006C0065005F006300700075005F00740069006D0065005F006D007300290020004100530020006D00610078005F0063006F006D00700069006C0065005F006300700075002C000D000A002000200020002000200020002000200020002000200020002000200020002000530055004D00280063006F006D00700069006C0065005F006400750072006100740069006F006E005F006D0073002900200041005300200074006F00740061006C005F0063006F006D00700069006C0065005F006400750072006100740069006F006E002C000D000A002000200020002000200020002000200020002000200020002000200020002000410056004700280063006F006D00700069006C0065005F006400750072006100740069006F006E005F006D007300290020004100530020006100760067005F0063006F006D00700069006C0065005F006400750072006100740069006F006E002C000D000A0020002000200020002000200020002000200020002000200020002000200020004D0041005800280063006F006D00700069006C0065005F006400750072006100740069006F006E005F006D007300290020004100530020006D00610078005F0063006F006D00700069006C0065005F006400750072006100740069006F006E000D000A00200020002000200020002000200020002000460052004F004D0020005B007200650070006C006100630065005F006D0065005D000D000A00200020002000200020002000200020002000470052004F00550050002000420059002000640061007400610062006100730065005F006E0061006D0065002C002000710075006500720079005F006800610073006800200029000D000A002000200020002000530045004C00450043005400200054004F005000280020003200310034003700340038003300360034003800200029000D000A002000200020002000200020002000200020002000200063002E00640061007400610062006100730065005F006E0061006D0065002C000D000A00200020002000200020002000200020002000200020006B002E00730071006C005F0074006500780074002C000D000A00200020002000200020002000200020002000200020006B002E00690073005F0070006100720061006D00650074006500720069007A00610062006C0065002C000D000A002000200020002000200020002000200020002000200063002E0074006F00740061006C005F0063006F006D00700069006C00650073002C000D000A002000200020002000200020002000200020002000200063002E0070006C0061006E005F0063006F0075006E0074002C000D000A002000200020002000200020002000200020002000200063002E0074006F00740061006C005F0063006F006D00700069006C0065005F006300700075002C000D000A002000200020002000200020002000200020002000200063002E006100760067005F0063006F006D00700069006C0065005F006300700075002C000D000A002000200020002000200020002000200020002000200063002E006D00610078005F0063006F006D00700069006C0065005F006300700075002C000D000A002000200020002000200020002000200020002000200063002E0074006F00740061006C005F0063006F006D00700069006C0065005F006400750072006100740069006F006E002C000D000A002000200020002000200020002000200020002000200063002E006100760067005F0063006F006D00700069006C0065005F006400750072006100740069006F006E002C000D000A002000200020002000200020002000200020002000200063002E006D00610078005F0063006F006D00700069006C0065005F006400750072006100740069006F006E002C000D000A00200020002000200020002000200020002000200020006B002E00710075006500720079005F0070006100720061006D005F0074007900700065002C000D000A00200020002000200020002000200020002000200020006B002E00690073005F006300610063006800650064002C000D000A00200020002000200020002000200020002000200020006B002E00690073005F007200650063006F006D00700069006C00650064002C000D000A00200020002000200020002000200020002000200020006B002E0063006F006D00700069006C0065005F0063006F00640065002C000D000A00200020002000200020002000200020002000200020006B002E006800610073005F006C00690074006500720061006C0073002C000D000A00200020002000200020002000200020002000200020006B002E0070006100720061006D00650074006500720069007A00650064005F00760061006C007500650073005F0063006F0075006E0074000D000A002000200020002000460052004F004D002000630070007100200041005300200063000D000A002000200020002000430052004F005300530020004100500050004C0059000D000A002000200020002000200020002000200028000D000A00200020002000200020002000200020002000200020002000530045004C00450043005400200054004F005000280020003100200029000D000A0020002000200020002000200020002000200020002000200020002000200020002000200020002A000D000A00200020002000200020002000200020002000200020002000460052004F004D0020005B007200650070006C006100630065005F006D0065005D0020004100530020006B000D000A002000200020002000200020002000200020002000200020005700480045005200450020006B002E00710075006500720079005F00680061007300680020003D00200063002E00710075006500720079005F0068006100730068000D000A002000200020002000200020002000200020002000200020004F00520044004500520020004200590020006B002E0069006400200044004500530043000D000A0020002000200020002000200020002000290020004100530020006B000D000A0020002000200020004F005200440045005200200042005900200063002E0074006F00740061006C005F0063006F006D00700069006C0065007300200044004500530043003B000D000A00
            WHERE @parameterization_events = 1;
            INSERT #view_check (view_name, view_definition)
            SELECT N'HumanEvents_Queries', 0x4300520045004100540045002000560049004500570020005B00640062006F005D002E005B00480075006D0061006E004500760065006E00740073005F0051007500650072006900650073005D000D000A00410053000D000A00200020002000200057004900540048002000710075006500720079005F0061006700670020004100530020000D000A00200020002000200020002000200020002000200020002000200028000D000A002000200020002000200020002000200020002000200020002000200020002000530045004C00450043005400200071002E00710075006500720079005F0070006C0061006E005F0068006100730068005F007300690067006E00650064002C000D000A002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200071002E00710075006500720079005F0068006100730068005F007300690067006E00650064002C000D000A002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200071002E0070006C0061006E005F00680061006E0064006C0065002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000490053004E0055004C004C00280071002E006300700075005F006D0073002C00200030002E002900200041005300200074006F00740061006C005F006300700075005F006D0073002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000490053004E0055004C004C00280071002E006C006F0067006900630061006C005F00720065006100640073002C00200030002E002900200041005300200074006F00740061006C005F006C006F0067006900630061006C005F00720065006100640073002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000490053004E0055004C004C00280071002E0070006800790073006900630061006C005F00720065006100640073002C00200030002E002900200041005300200074006F00740061006C005F0070006800790073006900630061006C005F00720065006100640073002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000490053004E0055004C004C00280071002E006400750072006100740069006F006E005F006D0073002C00200030002E002900200041005300200074006F00740061006C005F006400750072006100740069006F006E005F006D0073002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000490053004E0055004C004C00280071002E007700720069007400650073005F006D0062002C00200030002E002900200041005300200074006F00740061006C005F007700720069007400650073005F006D0062002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000490053004E0055004C004C00280071002E007300700069006C006C0073005F006D0062002C00200030002E002900200041005300200074006F00740061006C005F007300700069006C006C0073005F006D0062002C000D000A00200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020004E0055004C004C00200041005300200074006F00740061006C005F0075007300650064005F006D0065006D006F00720079005F006D0062002C000D000A00200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020004E0055004C004C00200041005300200074006F00740061006C005F006700720061006E007400650064005F006D0065006D006F00720079005F006D0062002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000490053004E0055004C004C00280071002E0072006F0077005F0063006F0075006E0074002C00200030002E002900200041005300200074006F00740061006C005F0072006F00770073002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000490053004E0055004C004C00280071002E006300700075005F006D0073002C00200030002E00290020004100530020006100760067005F006300700075005F006D0073002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000490053004E0055004C004C00280071002E006C006F0067006900630061006C005F00720065006100640073002C00200030002E00290020004100530020006100760067005F006C006F0067006900630061006C005F00720065006100640073002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000490053004E0055004C004C00280071002E0070006800790073006900630061006C005F00720065006100640073002C00200030002E00290020004100530020006100760067005F0070006800790073006900630061006C005F00720065006100640073002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000490053004E0055004C004C00280071002E006400750072006100740069006F006E005F006D0073002C00200030002E00290020004100530020006100760067005F006400750072006100740069006F006E005F006D0073002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000490053004E0055004C004C00280071002E007700720069007400650073005F006D0062002C00200030002E00290020004100530020006100760067005F007700720069007400650073005F006D0062002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000490053004E0055004C004C00280071002E007300700069006C006C0073005F006D0062002C00200030002E00290020004100530020006100760067005F007300700069006C006C0073005F006D0062002C000D000A00200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020004E0055004C004C0020004100530020006100760067005F0075007300650064005F006D0065006D006F00720079005F006D0062002C000D000A00200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020004E0055004C004C0020004100530020006100760067005F006700720061006E007400650064005F006D0065006D006F00720079005F006D0062002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000490053004E0055004C004C00280071002E0072006F0077005F0063006F0075006E0074002C0020003000290020004100530020006100760067005F0072006F0077007300200020002000200020002000200020002000200020002000200020002000200020002000200020000D000A002000200020002000200020002000200020002000200020002000200020002000460052004F004D0020005B007200650070006C006100630065005F006D0065005D00200041005300200071000D000A00200020002000200020002000200020002000200020002000200020002000200057004800450052004500200071002E006500760065006E0074005F00740079007000650020003C003E0020004E002700710075006500720079005F0070006F00730074005F0065007800650063007500740069006F006E005F00730068006F00770070006C0061006E0027000D000A0020002000200020002000200020002000200020002000200020002000200020000D000A00200020002000200020002000200020002000200020002000200020002000200055004E0049004F004E00200041004C004C0020000D000A0020002000200020002000200020002000200020002000200020002000200020000D000A002000200020002000200020002000200020002000200020002000200020002000530045004C00450043005400200071002E00710075006500720079005F0070006C0061006E005F0068006100730068005F007300690067006E00650064002C000D000A002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200071002E00710075006500720079005F0068006100730068005F007300690067006E00650064002C000D000A002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200071002E0070006C0061006E005F00680061006E0064006C0065002C000D000A00200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002F002A0074006F00740061006C0073002A002F000D000A00200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020004E0055004C004C00200041005300200074006F00740061006C005F006300700075005F006D0073002C000D000A00200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020004E0055004C004C00200041005300200074006F00740061006C005F006C006F0067006900630061006C005F00720065006100640073002C000D000A00200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020004E0055004C004C00200041005300200074006F00740061006C005F0070006800790073006900630061006C005F00720065006100640073002C000D000A00200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020004E0055004C004C00200041005300200074006F00740061006C005F006400750072006100740069006F006E005F006D0073002C000D000A00200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020004E0055004C004C00200041005300200074006F00740061006C005F007700720069007400650073002C000D000A00200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020004E0055004C004C00200041005300200074006F00740061006C005F007300700069006C006C0073005F006D0062002C002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020000D000A0020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000490053004E0055004C004C00280075007300650064005F006D0065006D006F00720079005F006D0062002C00200030002E002900200041005300200074006F00740061006C005F0075007300650064005F006D0065006D006F00720079005F006D0062002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000490053004E0055004C004C0028006700720061006E007400650064005F006D0065006D006F00720079005F006D0062002C00200030002E002900200041005300200074006F00740061006C005F006700720061006E007400650064005F006D0065006D006F00720079005F006D0062002C000D000A00200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020004E0055004C004C00200041005300200074006F00740061006C005F0072006F00770073002C000D000A00200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002F002A00610076006500720061006700650073002A002F000D000A00200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020004E0055004C004C0020004100530020006100760067005F006300700075005F006D0073002C000D000A00200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020004E0055004C004C0020004100530020006100760067005F006C006F0067006900630061006C005F00720065006100640073002C000D000A00200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020004E0055004C004C0020004100530020006100760067005F0070006800790073006900630061006C005F00720065006100640073002C000D000A00200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020004E0055004C004C0020004100530020006100760067005F006400750072006100740069006F006E005F006D0073002C000D000A00200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020004E0055004C004C0020004100530020006100760067005F007700720069007400650073005F006D0062002C000D000A00200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020004E0055004C004C0020004100530020006100760067005F007300700069006C006C0073005F006D0062002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000490053004E0055004C004C00280071002E0075007300650064005F006D0065006D006F00720079005F006D0062002C00200030002E00290020004100530020006100760067005F0075007300650064005F006D0065006D006F00720079005F006D0062002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000490053004E0055004C004C00280071002E006700720061006E007400650064005F006D0065006D006F00720079005F006D0062002C00200030002E00290020004100530020006100760067005F006700720061006E007400650064005F006D0065006D006F00720079005F006D0062002C000D000A00200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020004E0055004C004C0020004100530020006100760067005F0072006F0077007300200020002000200020002000200020002000200020002000200020002000200020002000200020000D000A002000200020002000200020002000200020002000200020002000200020002000460052004F004D0020005B007200650070006C006100630065005F006D0065005D00200041005300200071000D000A00200020002000200020002000200020002000200020002000200020002000200057004800450052004500200071002E006500760065006E0074005F00740079007000650020003D0020004E002700710075006500720079005F0070006F00730074005F0065007800650063007500740069006F006E005F00730068006F00770070006C0061006E002700200020002000200020002000200020000D000A00200020002000200020002000200020002000200020002000200029002C002000200020002000200020002000200020002000200020002000200020002000200020000D000A0020002000200020002000200020002000200074006F00740061006C0073000D000A0020002000200020002000200041005300200028002000530045004C00450043005400200054004F005000280020003200310034003700340038003300360034003800200029000D000A0020002000200020002000200020002000200020002000200020002000200020002000200071002E00710075006500720079005F0070006C0061006E005F0068006100730068005F007300690067006E00650064002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200071002E00710075006500720079005F0068006100730068005F007300690067006E00650064002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200071002E0070006C0061006E005F00680061006E0064006C0065002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200043004F0055004E0054005F0042004900470028002A00290020004F0056004500520020002800200050004100520054004900540049004F004E00200042005900200071002E00710075006500720079005F0070006C0061006E005F0068006100730068005F007300690067006E00650064002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200071002E00710075006500720079005F0068006100730068005F007300690067006E00650064002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200071002E0070006C0061006E005F00680061006E0064006C0065000D000A002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002900200041005300200065007800650063007500740069006F006E0073002C000D000A002000200020002000200020002000200020002000200020002000200020002000200020002F002A0074006F00740061006C0073002A002F000D000A00200020002000200020002000200020002000200020002000200020002000200020002000530055004D002800490053004E0055004C004C00280071002E0074006F00740061006C005F006300700075005F006D0073002C00200030002E0029002900200041005300200074006F00740061006C005F006300700075005F006D0073002C000D000A00200020002000200020002000200020002000200020002000200020002000200020002000530055004D002800490053004E0055004C004C00280071002E0074006F00740061006C005F006C006F0067006900630061006C005F00720065006100640073002C00200030002E0029002900200041005300200074006F00740061006C005F006C006F0067006900630061006C005F00720065006100640073002C000D000A00200020002000200020002000200020002000200020002000200020002000200020002000530055004D002800490053004E0055004C004C00280071002E0074006F00740061006C005F0070006800790073006900630061006C005F00720065006100640073002C00200030002E0029002900200041005300200074006F00740061006C005F0070006800790073006900630061006C005F00720065006100640073002C000D000A00200020002000200020002000200020002000200020002000200020002000200020002000530055004D002800490053004E0055004C004C00280071002E0074006F00740061006C005F006400750072006100740069006F006E005F006D0073002C00200030002E0029002900200041005300200074006F00740061006C005F006400750072006100740069006F006E005F006D0073002C000D000A00200020002000200020002000200020002000200020002000200020002000200020002000530055004D002800490053004E0055004C004C00280071002E0074006F00740061006C005F007700720069007400650073005F006D0062002C00200030002E0029002900200041005300200074006F00740061006C005F007700720069007400650073002C000D000A00200020002000200020002000200020002000200020002000200020002000200020002000530055004D002800490053004E0055004C004C00280071002E0074006F00740061006C005F007300700069006C006C0073005F006D0062002C00200030002E0029002900200041005300200074006F00740061006C005F007300700069006C006C0073005F006D0062002C000D000A00200020002000200020002000200020002000200020002000200020002000200020002000530055004D002800490053004E0055004C004C00280071002E0074006F00740061006C005F0075007300650064005F006D0065006D006F00720079005F006D0062002C00200030002E0029002900200041005300200074006F00740061006C005F0075007300650064005F006D0065006D006F00720079005F006D0062002C000D000A00200020002000200020002000200020002000200020002000200020002000200020002000530055004D002800490053004E0055004C004C00280071002E0074006F00740061006C005F006700720061006E007400650064005F006D0065006D006F00720079005F006D0062002C00200030002E0029002900200041005300200074006F00740061006C005F006700720061006E007400650064005F006D0065006D006F00720079005F006D0062002C000D000A00200020002000200020002000200020002000200020002000200020002000200020002000530055004D002800490053004E0055004C004C00280071002E0074006F00740061006C005F0072006F00770073002C00200030002E0029002900200041005300200074006F00740061006C005F0072006F00770073002C000D000A002000200020002000200020002000200020002000200020002000200020002000200020002F002A00610076006500720061006700650073002A002F000D000A002000200020002000200020002000200020002000200020002000200020002000200020004100560047002800490053004E0055004C004C00280071002E006100760067005F006300700075005F006D0073002C00200030002E002900290020004100530020006100760067005F006300700075005F006D0073002C000D000A002000200020002000200020002000200020002000200020002000200020002000200020004100560047002800490053004E0055004C004C00280071002E006100760067005F006C006F0067006900630061006C005F00720065006100640073002C00200030002E002900290020004100530020006100760067005F006C006F0067006900630061006C005F00720065006100640073002C000D000A002000200020002000200020002000200020002000200020002000200020002000200020004100560047002800490053004E0055004C004C00280071002E006100760067005F0070006800790073006900630061006C005F00720065006100640073002C00200030002E002900290020004100530020006100760067005F0070006800790073006900630061006C005F00720065006100640073002C000D000A002000200020002000200020002000200020002000200020002000200020002000200020004100560047002800490053004E0055004C004C00280071002E006100760067005F006400750072006100740069006F006E005F006D0073002C00200030002E002900290020004100530020006100760067005F006400750072006100740069006F006E005F006D0073002C000D000A002000200020002000200020002000200020002000200020002000200020002000200020004100560047002800490053004E0055004C004C00280071002E006100760067005F007700720069007400650073005F006D0062002C00200030002E002900290020004100530020006100760067005F007700720069007400650073002C000D000A002000200020002000200020002000200020002000200020002000200020002000200020004100560047002800490053004E0055004C004C00280071002E006100760067005F007300700069006C006C0073005F006D0062002C00200030002E002900290020004100530020006100760067005F007300700069006C006C0073005F006D0062002C000D000A002000200020002000200020002000200020002000200020002000200020002000200020004100560047002800490053004E0055004C004C00280071002E006100760067005F0075007300650064005F006D0065006D006F00720079005F006D0062002C00200030002E002900290020004100530020006100760067005F0075007300650064005F006D0065006D006F00720079005F006D0062002C000D000A002000200020002000200020002000200020002000200020002000200020002000200020004100560047002800490053004E0055004C004C00280071002E006100760067005F006700720061006E007400650064005F006D0065006D006F00720079005F006D0062002C00200030002E002900290020004100530020006100760067005F006700720061006E007400650064005F006D0065006D006F00720079005F006D0062002C000D000A002000200020002000200020002000200020002000200020002000200020002000200020004100560047002800490053004E0055004C004C00280071002E006100760067005F0072006F00770073002C00200030002900290020004100530020006100760067005F0072006F00770073000D000A0020002000200020002000200020002000200020002000460052004F004D002000710075006500720079005F00610067006700200041005300200071000D000A0020002000200020002000200020002000200020002000470052004F0055005000200042005900200071002E00710075006500720079005F0070006C0061006E005F0068006100730068005F007300690067006E00650064002C000D000A002000200020002000200020002000200020002000200020002000200020002000200020002000200071002E00710075006500720079005F0068006100730068005F007300690067006E00650064002C000D000A002000200020002000200020002000200020002000200020002000200020002000200020002000200071002E0070006C0061006E005F00680061006E0064006C006500200029002C000D000A00200020002000200020002000200020002000710075006500720079005F0072006500730075006C00740073000D000A0020002000200020002000200041005300200028002000530045004C00450043005400200054004F005000280020003200310034003700340038003300360034003800200029000D000A0020002000200020002000200020002000200020002000200020002000200020002000200071002E006500760065006E0074005F00740069006D0065002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200071002E00640061007400610062006100730065005F006E0061006D0065002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200071002E006F0062006A006500630074005F006E0061006D0065002C000D000A00200020002000200020002000200020002000200020002000200020002000200020002000710032002E00730074006100740065006D0065006E0074005F0074006500780074002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200071002E00730071006C005F0074006500780074002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200071002E00730068006F00770070006C0061006E005F0078006D006C002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200074002E0065007800650063007500740069006F006E0073002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200074002E0074006F00740061006C005F006300700075005F006D0073002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200074002E006100760067005F006300700075005F006D0073002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200074002E0074006F00740061006C005F006C006F0067006900630061006C005F00720065006100640073002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200074002E006100760067005F006C006F0067006900630061006C005F00720065006100640073002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200074002E0074006F00740061006C005F0070006800790073006900630061006C005F00720065006100640073002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200074002E006100760067005F0070006800790073006900630061006C005F00720065006100640073002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200074002E0074006F00740061006C005F006400750072006100740069006F006E005F006D0073002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200074002E006100760067005F006400750072006100740069006F006E005F006D0073002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200074002E0074006F00740061006C005F007700720069007400650073002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200074002E006100760067005F007700720069007400650073002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200074002E0074006F00740061006C005F007300700069006C006C0073005F006D0062002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200074002E006100760067005F007300700069006C006C0073005F006D0062002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200074002E0074006F00740061006C005F0075007300650064005F006D0065006D006F00720079005F006D0062002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200074002E006100760067005F0075007300650064005F006D0065006D006F00720079005F006D0062002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200074002E0074006F00740061006C005F006700720061006E007400650064005F006D0065006D006F00720079005F006D0062002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200074002E006100760067005F006700720061006E007400650064005F006D0065006D006F00720079005F006D0062002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200074002E0074006F00740061006C005F0072006F00770073002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200074002E006100760067005F0072006F00770073002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200071002E00730065007200690061006C005F0069006400650061006C005F006D0065006D006F00720079005F006D0062002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200071002E007200650071007500650073007400650064005F006D0065006D006F00720079005F006D0062002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200071002E0069006400650061006C005F006D0065006D006F00720079005F006D0062002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200071002E0065007300740069006D0061007400650064005F0072006F00770073002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200071002E0064006F0070002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200071002E00710075006500720079005F0070006C0061006E005F0068006100730068005F007300690067006E00650064002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200071002E00710075006500720079005F0068006100730068005F007300690067006E00650064002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200071002E0070006C0061006E005F00680061006E0064006C0065002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200052004F0057005F004E0055004D004200450052002800290020004F0056004500520020002800200050004100520054004900540049004F004E00200042005900200071002E00710075006500720079005F0070006C0061006E005F0068006100730068005F007300690067006E00650064002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200071002E00710075006500720079005F0068006100730068005F007300690067006E00650064002C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200071002E0070006C0061006E005F00680061006E0064006C0065000D000A00200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020004F005200440045005200200042005900200071002E00710075006500720079005F0070006C0061006E005F0068006100730068005F007300690067006E00650064002C000D000A002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200071002E00710075006500720079005F0068006100730068005F007300690067006E00650064002C000D000A002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200071002E0070006C0061006E005F00680061006E0064006C0065000D000A00200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000290020004100530020006E000D000A0020002000200020002000200020002000200020002000460052004F004D0020005B007200650070006C006100630065005F006D0065005D00200041005300200071000D000A00200020002000200020002000200020002000200020004A004F0049004E00200074006F00740061006C007300200041005300200074000D000A002000200020002000200020002000200020002000200020002000200020004F004E002000200071002E00710075006500720079005F0068006100730068005F007300690067006E006500640020003D00200074002E00710075006500720079005F0068006100730068005F007300690067006E00650064000D000A0020002000200020002000200020002000200020002000200020002000200041004E004400200071002E00710075006500720079005F0070006C0061006E005F0068006100730068005F007300690067006E006500640020003D00200074002E00710075006500720079005F0070006C0061006E005F0068006100730068005F007300690067006E00650064000D000A0020002000200020002000200020002000200020002000200020002000200041004E004400200071002E0070006C0061006E005F00680061006E0064006C00650020003D00200074002E0070006C0061006E005F00680061006E0064006C0065000D000A0020002000200020002000200020002000200020002000430052004F005300530020004100500050004C0059000D000A0020002000200020002000200020002000200020002000200020002000200028000D000A002000200020002000200020002000200020002000200020002000200020002000200020002000530045004C00450043005400200054004F005000280020003100200029002000710032002E00730074006100740065006D0065006E0074002000410053002000730074006100740065006D0065006E0074005F0074006500780074000D000A002000200020002000200020002000200020002000200020002000200020002000200020002000460052004F004D0020005B007200650070006C006100630065005F006D0065005D002000410053002000710032000D000A00200020002000200020002000200020002000200020002000200020002000200020002000200057004800450052004500200071002E00710075006500720079005F0068006100730068005F007300690067006E006500640020003D002000710032002E00710075006500720079005F0068006100730068005F007300690067006E00650064000D000A00200020002000200020002000200020002000200020002000200020002000200020002000200041004E00440020002000200071002E00710075006500720079005F0070006C0061006E005F0068006100730068005F007300690067006E006500640020003D002000710032002E00710075006500720079005F0070006C0061006E005F0068006100730068005F007300690067006E00650064000D000A00200020002000200020002000200020002000200020002000200020002000200020002000200041004E00440020002000200071002E0070006C0061006E005F00680061006E0064006C00650020003D002000710032002E0070006C0061006E005F00680061006E0064006C0065000D000A00200020002000200020002000200020002000200020002000200020002000200020002000200041004E004400200020002000710032002E00730074006100740065006D0065006E00740020004900530020004E004F00540020004E0055004C004C000D000A0020002000200020002000200020002000200020002000200020002000200020002000200020004F0052004400450052002000420059002000710032002E006500760065006E0074005F00740069006D006500200044004500530043000D000A0020002000200020002000200020002000200020002000200020002000200029002000410053002000710032000D000A002000200020002000200020002000200020002000200057004800450052004500200071002E00730068006F00770070006C0061006E005F0078006D006C002E0065007800690073007400280027002A002700290020003D0020003100200029000D000A002000200020002000530045004C00450043005400200054004F005000280020003200310034003700340038003300360034003800200029000D000A002000200020002000200020002000200020002000200071002E006500760065006E0074005F00740069006D0065002C000D000A002000200020002000200020002000200020002000200071002E00640061007400610062006100730065005F006E0061006D0065002C000D000A002000200020002000200020002000200020002000200071002E006F0062006A006500630074005F006E0061006D0065002C000D000A002000200020002000200020002000200020002000200071002E00730074006100740065006D0065006E0074005F0074006500780074002C000D000A002000200020002000200020002000200020002000200071002E00730071006C005F0074006500780074002C000D000A002000200020002000200020002000200020002000200071002E00730068006F00770070006C0061006E005F0078006D006C002C000D000A002000200020002000200020002000200020002000200071002E0065007800650063007500740069006F006E0073002C000D000A002000200020002000200020002000200020002000200071002E0074006F00740061006C005F006300700075005F006D0073002C000D000A002000200020002000200020002000200020002000200071002E006100760067005F006300700075005F006D0073002C000D000A002000200020002000200020002000200020002000200071002E0074006F00740061006C005F006C006F0067006900630061006C005F00720065006100640073002C000D000A002000200020002000200020002000200020002000200071002E006100760067005F006C006F0067006900630061006C005F00720065006100640073002C000D000A002000200020002000200020002000200020002000200071002E0074006F00740061006C005F0070006800790073006900630061006C005F00720065006100640073002C000D000A002000200020002000200020002000200020002000200071002E006100760067005F0070006800790073006900630061006C005F00720065006100640073002C000D000A002000200020002000200020002000200020002000200071002E0074006F00740061006C005F006400750072006100740069006F006E005F006D0073002C000D000A002000200020002000200020002000200020002000200071002E006100760067005F006400750072006100740069006F006E005F006D0073002C000D000A002000200020002000200020002000200020002000200071002E0074006F00740061006C005F007700720069007400650073002C000D000A002000200020002000200020002000200020002000200071002E006100760067005F007700720069007400650073002C000D000A002000200020002000200020002000200020002000200071002E0074006F00740061006C005F007300700069006C006C0073005F006D0062002C000D000A002000200020002000200020002000200020002000200071002E006100760067005F007300700069006C006C0073005F006D0062002C000D000A002000200020002000200020002000200020002000200071002E0074006F00740061006C005F0075007300650064005F006D0065006D006F00720079005F006D0062002C000D000A002000200020002000200020002000200020002000200071002E006100760067005F0075007300650064005F006D0065006D006F00720079005F006D0062002C000D000A002000200020002000200020002000200020002000200071002E0074006F00740061006C005F006700720061006E007400650064005F006D0065006D006F00720079005F006D0062002C000D000A002000200020002000200020002000200020002000200071002E006100760067005F006700720061006E007400650064005F006D0065006D006F00720079005F006D0062002C000D000A002000200020002000200020002000200020002000200071002E0074006F00740061006C005F0072006F00770073002C000D000A002000200020002000200020002000200020002000200071002E006100760067005F0072006F00770073002C000D000A002000200020002000200020002000200020002000200071002E00730065007200690061006C005F0069006400650061006C005F006D0065006D006F00720079005F006D0062002C000D000A002000200020002000200020002000200020002000200071002E007200650071007500650073007400650064005F006D0065006D006F00720079005F006D0062002C000D000A002000200020002000200020002000200020002000200071002E0069006400650061006C005F006D0065006D006F00720079005F006D0062002C000D000A002000200020002000200020002000200020002000200071002E0065007300740069006D0061007400650064005F0072006F00770073002C000D000A002000200020002000200020002000200020002000200071002E0064006F0070002C000D000A002000200020002000200020002000200020002000200071002E00710075006500720079005F0070006C0061006E005F0068006100730068005F007300690067006E00650064002C000D000A002000200020002000200020002000200020002000200071002E00710075006500720079005F0068006100730068005F007300690067006E00650064002C000D000A002000200020002000200020002000200020002000200071002E0070006C0061006E005F00680061006E0064006C0065000D000A002000200020002000460052004F004D002000710075006500720079005F0072006500730075006C0074007300200041005300200071000D000A00200020002000200057004800450052004500200071002E006E0020003D00200031003B00;
            INSERT #view_check (view_name, view_definition)
            SELECT N'HumanEvents_RecompilesByDatabaseAndObject', 0x0D000A000D000A00430052004500410054004500200056004900450057002000640062006F002E00480075006D0061006E004500760065006E00740073005F005200650063006F006D00700069006C0065007300420079004400610074006100620061007300650041006E0064004F0062006A006500630074000D000A00410053000D000A002000200020002000530045004C00450043005400200054004F005000280020003200310034003700340038003300360034003800200029000D000A00200020002000200020002000200020002000200020004D0049004E0028006500760065006E0074005F00740069006D006500290020004100530020006D0069006E005F006500760065006E0074005F00740069006D0065002C000D000A00200020002000200020002000200020002000200020004D004100580028006500760065006E0074005F00740069006D006500290020004100530020006D00610078005F006500760065006E0074005F00740069006D0065002C000D000A0020002000200020002000200020002000200020002000640061007400610062006100730065005F006E0061006D0065002C000D000A0020002000200020002000200020002000200020002000430041005300450020005700480045004E0020006F0062006A006500630074005F006E0061006D00650020003D0020004E00270027000D000A0020002000200020002000200020002000200020002000200020002000200020005400480045004E0020004E0027004E002F00410027000D000A0020002000200020002000200020002000200020002000200020002000200045004C005300450020006F0062006A006500630074005F006E0061006D0065000D000A002000200020002000200020002000200020002000200045004E00440020004100530020006F0062006A006500630074005F006E0061006D0065002C000D000A002000200020002000200020002000200020002000200043004F0055004E0054005F0042004900470028002A002900200041005300200074006F00740061006C005F0063006F006D00700069006C00650073002C000D000A0020002000200020002000200020002000200020002000530055004D00280063006F006D00700069006C0065005F006300700075005F006D0073002900200041005300200074006F00740061006C005F0063006F006D00700069006C0065005F006300700075002C000D000A0020002000200020002000200020002000200020002000410056004700280063006F006D00700069006C0065005F006300700075005F006D007300290020004100530020006100760067005F0063006F006D00700069006C0065005F006300700075002C000D000A00200020002000200020002000200020002000200020004D0041005800280063006F006D00700069006C0065005F006300700075005F006D007300290020004100530020006D00610078005F0063006F006D00700069006C0065005F006300700075002C000D000A0020002000200020002000200020002000200020002000530055004D00280063006F006D00700069006C0065005F006400750072006100740069006F006E005F006D0073002900200041005300200074006F00740061006C005F0063006F006D00700069006C0065005F006400750072006100740069006F006E002C000D000A0020002000200020002000200020002000200020002000410056004700280063006F006D00700069006C0065005F006400750072006100740069006F006E005F006D007300290020004100530020006100760067005F0063006F006D00700069006C0065005F006400750072006100740069006F006E002C000D000A00200020002000200020002000200020002000200020004D0041005800280063006F006D00700069006C0065005F006400750072006100740069006F006E005F006D007300290020004100530020006D00610078005F0063006F006D00700069006C0065005F006400750072006100740069006F006E000D000A002000200020002000460052004F004D0020005B007200650070006C006100630065005F006D0065005D000D000A002000200020002000470052004F00550050002000420059002000640061007400610062006100730065005F006E0061006D0065002C0020006F0062006A006500630074005F006E0061006D0065000D000A0020002000200020004F005200440045005200200042005900200074006F00740061006C005F0063006F006D00700069006C0065007300200044004500530043003B000D000A00
            WHERE @compile_events = 1;
            INSERT #view_check (view_name, view_definition)
            SELECT N'HumanEvents_RecompilesByDuration', 0x0D000A000D000A00430052004500410054004500200056004900450057002000640062006F002E00480075006D0061006E004500760065006E00740073005F005200650063006F006D00700069006C0065007300420079004400750072006100740069006F006E000D000A00410053000D000A002000200020002000570049005400480020006300620071000D000A0020002000200020002000200041005300200028000D000A00200020002000200020002000200020002000530045004C004500430054002000730074006100740065006D0065006E0074005F0074006500780074005F0063006800650063006B00730075006D002C000D000A00200020002000200020002000200020002000200020002000200020002000200043004F0055004E0054005F0042004900470028002A002900200041005300200074006F00740061006C005F0063006F006D00700069006C00650073002C000D000A002000200020002000200020002000200020002000200020002000200020002000530055004D00280063006F006D00700069006C0065005F006300700075005F006D0073002900200041005300200074006F00740061006C005F0063006F006D00700069006C0065005F006300700075002C000D000A002000200020002000200020002000200020002000200020002000200020002000410056004700280063006F006D00700069006C0065005F006300700075005F006D007300290020004100530020006100760067005F0063006F006D00700069006C0065005F006300700075002C000D000A0020002000200020002000200020002000200020002000200020002000200020004D0041005800280063006F006D00700069006C0065005F006300700075005F006D007300290020004100530020006D00610078005F0063006F006D00700069006C0065005F006300700075002C000D000A002000200020002000200020002000200020002000200020002000200020002000530055004D00280063006F006D00700069006C0065005F006400750072006100740069006F006E005F006D0073002900200041005300200074006F00740061006C005F0063006F006D00700069006C0065005F006400750072006100740069006F006E002C000D000A002000200020002000200020002000200020002000200020002000200020002000410056004700280063006F006D00700069006C0065005F006400750072006100740069006F006E005F006D007300290020004100530020006100760067005F0063006F006D00700069006C0065005F006400750072006100740069006F006E002C000D000A0020002000200020002000200020002000200020002000200020002000200020004D0041005800280063006F006D00700069006C0065005F006400750072006100740069006F006E005F006D007300290020004100530020006D00610078005F0063006F006D00700069006C0065005F006400750072006100740069006F006E000D000A00200020002000200020002000200020002000460052004F004D0020005B007200650070006C006100630065005F006D0065005D000D000A00200020002000200020002000200020002000470052004F00550050002000420059002000730074006100740065006D0065006E0074005F0074006500780074005F0063006800650063006B00730075006D000D000A0020002000200020002000200020002000200048004100560049004E0047002000410056004700280063006F006D00700069006C0065005F006400750072006100740069006F006E005F006D007300290020003E0020003100300030003000200029000D000A002000200020002000530045004C00450043005400200054004F005000280020003200310034003700340038003300360034003800200029000D000A00200020002000200020002000200020002000200020006B002E006F0062006A006500630074005F006E0061006D0065002C000D000A00200020002000200020002000200020002000200020006B002E00730074006100740065006D0065006E0074005F0074006500780074002C000D000A002000200020002000200020002000200020002000200063002E0074006F00740061006C005F0063006F006D00700069006C00650073002C000D000A002000200020002000200020002000200020002000200063002E0074006F00740061006C005F0063006F006D00700069006C0065005F006300700075002C000D000A002000200020002000200020002000200020002000200063002E006100760067005F0063006F006D00700069006C0065005F006300700075002C000D000A002000200020002000200020002000200020002000200063002E006D00610078005F0063006F006D00700069006C0065005F006300700075002C000D000A002000200020002000200020002000200020002000200063002E0074006F00740061006C005F0063006F006D00700069006C0065005F006400750072006100740069006F006E002C000D000A002000200020002000200020002000200020002000200063002E006100760067005F0063006F006D00700069006C0065005F006400750072006100740069006F006E002C000D000A002000200020002000200020002000200020002000200063002E006D00610078005F0063006F006D00700069006C0065005F006400750072006100740069006F006E000D000A002000200020002000460052004F004D002000630062007100200041005300200063000D000A002000200020002000430052004F005300530020004100500050004C0059000D000A002000200020002000200020002000200028000D000A00200020002000200020002000200020002000200020002000530045004C00450043005400200054004F005000280020003100200029000D000A0020002000200020002000200020002000200020002000200020002000200020002000200020002A000D000A00200020002000200020002000200020002000200020002000460052004F004D0020005B007200650070006C006100630065005F006D0065005D0020004100530020006B000D000A0020002000200020002000200020002000200020002000200057004800450052004500200063002E00730074006100740065006D0065006E0074005F0074006500780074005F0063006800650063006B00730075006D0020003D0020006B002E00730074006100740065006D0065006E0074005F0074006500780074005F0063006800650063006B00730075006D000D000A002000200020002000200020002000200020002000200020004F00520044004500520020004200590020006B002E0069006400200044004500530043000D000A0020002000200020002000200020002000290020004100530020006B000D000A0020002000200020004F005200440045005200200042005900200063002E006100760067005F0063006F006D00700069006C0065005F006400750072006100740069006F006E00200044004500530043003B000D000A00
            WHERE @compile_events = 1;
            INSERT #view_check (view_name, view_definition)
            SELECT N'HumanEvents_RecompilesByQuery', 0x0D000A000D000A00430052004500410054004500200056004900450057002000640062006F002E00480075006D0061006E004500760065006E00740073005F005200650063006F006D00700069006C006500730042007900510075006500720079000D000A00410053000D000A002000200020002000570049005400480020006300620071000D000A0020002000200020002000200041005300200028000D000A00200020002000200020002000200020002000530045004C004500430054002000730074006100740065006D0065006E0074005F0074006500780074005F0063006800650063006B00730075006D002C000D000A00200020002000200020002000200020002000200020002000200020002000200043004F0055004E0054005F0042004900470028002A002900200041005300200074006F00740061006C005F007200650063006F006D00700069006C00650073002C000D000A002000200020002000200020002000200020002000200020002000200020002000530055004D00280063006F006D00700069006C0065005F006300700075005F006D0073002900200041005300200074006F00740061006C005F0063006F006D00700069006C0065005F006300700075002C000D000A002000200020002000200020002000200020002000200020002000200020002000410056004700280063006F006D00700069006C0065005F006300700075005F006D007300290020004100530020006100760067005F0063006F006D00700069006C0065005F006300700075002C000D000A0020002000200020002000200020002000200020002000200020002000200020004D0041005800280063006F006D00700069006C0065005F006300700075005F006D007300290020004100530020006D00610078005F0063006F006D00700069006C0065005F006300700075002C000D000A002000200020002000200020002000200020002000200020002000200020002000530055004D00280063006F006D00700069006C0065005F006400750072006100740069006F006E005F006D0073002900200041005300200074006F00740061006C005F0063006F006D00700069006C0065005F006400750072006100740069006F006E002C000D000A002000200020002000200020002000200020002000200020002000200020002000410056004700280063006F006D00700069006C0065005F006400750072006100740069006F006E005F006D007300290020004100530020006100760067005F0063006F006D00700069006C0065005F006400750072006100740069006F006E002C000D000A0020002000200020002000200020002000200020002000200020002000200020004D0041005800280063006F006D00700069006C0065005F006400750072006100740069006F006E005F006D007300290020004100530020006D00610078005F0063006F006D00700069006C0065005F006400750072006100740069006F006E000D000A00200020002000200020002000200020002000460052004F004D0020005B007200650070006C006100630065005F006D0065005D000D000A00200020002000200020002000200020002000470052004F00550050002000420059002000730074006100740065006D0065006E0074005F0074006500780074005F0063006800650063006B00730075006D000D000A0020002000200020002000200020002000200048004100560049004E004700200043004F0055004E0054005F0042004900470028002A00290020003E003D00200031003000200029000D000A002000200020002000530045004C00450043005400200054004F005000280020003200310034003700340038003300360034003800200029000D000A00200020002000200020002000200020002000200020006B002E006F0062006A006500630074005F006E0061006D0065002C000D000A00200020002000200020002000200020002000200020006B002E00730074006100740065006D0065006E0074005F0074006500780074002C000D000A002000200020002000200020002000200020002000200063002E0074006F00740061006C005F007200650063006F006D00700069006C00650073002C000D000A002000200020002000200020002000200020002000200063002E0074006F00740061006C005F0063006F006D00700069006C0065005F006300700075002C000D000A002000200020002000200020002000200020002000200063002E006100760067005F0063006F006D00700069006C0065005F006300700075002C000D000A002000200020002000200020002000200020002000200063002E006D00610078005F0063006F006D00700069006C0065005F006300700075002C000D000A002000200020002000200020002000200020002000200063002E0074006F00740061006C005F0063006F006D00700069006C0065005F006400750072006100740069006F006E002C000D000A002000200020002000200020002000200020002000200063002E006100760067005F0063006F006D00700069006C0065005F006400750072006100740069006F006E002C000D000A002000200020002000200020002000200020002000200063002E006D00610078005F0063006F006D00700069006C0065005F006400750072006100740069006F006E000D000A002000200020002000460052004F004D002000630062007100200041005300200063000D000A002000200020002000430052004F005300530020004100500050004C0059000D000A002000200020002000200020002000200028000D000A00200020002000200020002000200020002000200020002000530045004C00450043005400200054004F005000280020003100200029000D000A0020002000200020002000200020002000200020002000200020002000200020002000200020002A000D000A00200020002000200020002000200020002000200020002000460052004F004D0020005B007200650070006C006100630065005F006D0065005D0020004100530020006B000D000A0020002000200020002000200020002000200020002000200057004800450052004500200063002E00730074006100740065006D0065006E0074005F0074006500780074005F0063006800650063006B00730075006D0020003D0020006B002E00730074006100740065006D0065006E0074005F0074006500780074005F0063006800650063006B00730075006D000D000A002000200020002000200020002000200020002000200020004F00520044004500520020004200590020006B002E0069006400200044004500530043000D000A0020002000200020002000200020002000290020004100530020006B000D000A0020002000200020004F005200440045005200200042005900200063002E0074006F00740061006C005F007200650063006F006D00700069006C0065007300200044004500530043003B000D000A00
            WHERE @compile_events = 1;
            INSERT #view_check (view_name, view_definition)
            SELECT N'HumanEvents_WaitsByDatabase', 0x0D000A000D000A00430052004500410054004500200056004900450057002000640062006F002E00480075006D0061006E004500760065006E00740073005F005700610069007400730042007900440061007400610062006100730065000D000A00410053000D000A00200020002000200057004900540048002000770061006900740073000D000A0020002000200020002000200041005300200028000D000A00200020002000200020002000200020002000530045004C0045004300540020004E00270074006F00740061006C002000770061006900740073002000620079002000640061007400610062006100730065002700200041005300200077006100690074005F007000610074007400650072006E002C000D000A0020002000200020002000200020002000200020002000200020002000200020004D0049004E002800770061002E006500760065006E0074005F00740069006D006500290020004100530020006D0069006E005F006500760065006E0074005F00740069006D0065002C000D000A0020002000200020002000200020002000200020002000200020002000200020004D00410058002800770061002E006500760065006E0074005F00740069006D006500290020004100530020006D00610078005F006500760065006E0074005F00740069006D0065002C000D000A002000200020002000200020002000200020002000200020002000200020002000770061002E00640061007400610062006100730065005F006E0061006D0065002C000D000A002000200020002000200020002000200020002000200020002000200020002000770061002E0077006100690074005F0074007900700065002C000D000A00200020002000200020002000200020002000200020002000200020002000200043004F0055004E0054005F0042004900470028002A002900200041005300200074006F00740061006C005F00770061006900740073002C000D000A002000200020002000200020002000200020002000200020002000200020002000530055004D002800770061002E006400750072006100740069006F006E005F006D00730029002000410053002000730075006D005F006400750072006100740069006F006E005F006D0073002C000D000A002000200020002000200020002000200020002000200020002000200020002000530055004D002800770061002E007300690067006E0061006C005F006400750072006100740069006F006E005F006D00730029002000410053002000730075006D005F007300690067006E0061006C005F006400750072006100740069006F006E005F006D0073002C000D000A002000200020002000200020002000200020002000200020002000200020002000530055004D002800770061002E006400750072006100740069006F006E005F006D007300290020002F00200043004F0055004E0054005F0042004900470028002A00290020004100530020006100760067005F006D0073005F007000650072005F0077006100690074000D000A00200020002000200020002000200020002000460052004F004D0020005B007200650070006C006100630065005F006D0065005D002000410053002000770061000D000A00200020002000200020002000200020002000470052004F00550050002000420059002000770061002E00640061007400610062006100730065005F006E0061006D0065002C002000770061002E0077006100690074005F007400790070006500200029000D000A002000200020002000530045004C00450043005400200054004F005000280020003200310034003700340038003300360034003800200029000D000A0020002000200020002000200020002000200020002000770061006900740073002E0077006100690074005F007000610074007400650072006E002C000D000A0020002000200020002000200020002000200020002000770061006900740073002E006D0069006E005F006500760065006E0074005F00740069006D0065002C000D000A0020002000200020002000200020002000200020002000770061006900740073002E006D00610078005F006500760065006E0074005F00740069006D0065002C000D000A0020002000200020002000200020002000200020002000770061006900740073002E00640061007400610062006100730065005F006E0061006D0065002C000D000A0020002000200020002000200020002000200020002000770061006900740073002E0077006100690074005F0074007900700065002C000D000A0020002000200020002000200020002000200020002000770061006900740073002E0074006F00740061006C005F00770061006900740073002C000D000A0020002000200020002000200020002000200020002000770061006900740073002E00730075006D005F006400750072006100740069006F006E005F006D0073002C000D000A0020002000200020002000200020002000200020002000770061006900740073002E00730075006D005F007300690067006E0061006C005F006400750072006100740069006F006E005F006D0073002C000D000A0020002000200020002000200020002000200020002000770061006900740073002E006100760067005F006D0073005F007000650072005F0077006100690074002C000D000A0020002000200020002000200020002000200020002000490053004E0055004C004C0028000D000A0020002000200020002000200020002000200020002000200020002000200020002000200020002000200043004F0055004E0054005F0042004900470028002A0029000D000A002000200020002000200020002000200020002000200020002000200020002000200020002000200020002F0020004E0055004C004C004900460028004400410054004500440049004600460028000D000A002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020005300450043004F004E0044002C002000770061006900740073002E006D0069006E005F006500760065006E0074005F00740069006D0065002C000D000A00200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000770061006900740073002E006D00610078005F006500760065006E0074005F00740069006D0065000D000A002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200029002C002000300029002C00200030000D000A002000200020002000200020002000200020002000200020002000200020002000200029002000410053002000770061006900740073005F007000650072005F007300650063006F006E0064002C000D000A0020002000200020002000200020002000200020002000490053004E0055004C004C0028000D000A0020002000200020002000200020002000200020002000200020002000200020002000200020002000200043004F0055004E0054005F0042004900470028002A0029000D000A002000200020002000200020002000200020002000200020002000200020002000200020002000200020002F0020004E0055004C004C004900460028004400410054004500440049004600460028000D000A0020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200048004F00550052002C002000770061006900740073002E006D0069006E005F006500760065006E0074005F00740069006D0065002C000D000A00200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000770061006900740073002E006D00610078005F006500760065006E0074005F00740069006D0065000D000A002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200029002C002000300029002C00200030000D000A002000200020002000200020002000200020002000200020002000200020002000200029002000410053002000770061006900740073005F007000650072005F0068006F00750072002C000D000A0020002000200020002000200020002000200020002000490053004E0055004C004C0028000D000A0020002000200020002000200020002000200020002000200020002000200020002000200020002000200043004F0055004E0054005F0042004900470028002A0029000D000A002000200020002000200020002000200020002000200020002000200020002000200020002000200020002F0020004E0055004C004C004900460028004400410054004500440049004600460028000D000A002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020004400410059002C002000770061006900740073002E006D0069006E005F006500760065006E0074005F00740069006D0065002C000D000A00200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000770061006900740073002E006D00610078005F006500760065006E0074005F00740069006D0065000D000A002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200029002C002000300029002C00200030000D000A002000200020002000200020002000200020002000200020002000200020002000200029002000410053002000770061006900740073005F007000650072005F006400610079000D000A002000200020002000460052004F004D002000770061006900740073000D000A002000200020002000470052004F00550050002000420059002000770061006900740073002E0077006100690074005F007000610074007400650072006E002C000D000A002000200020002000200020002000200020002000200020002000770061006900740073002E006D0069006E005F006500760065006E0074005F00740069006D0065002C000D000A002000200020002000200020002000200020002000200020002000770061006900740073002E006D00610078005F006500760065006E0074005F00740069006D0065002C000D000A002000200020002000200020002000200020002000200020002000770061006900740073002E00640061007400610062006100730065005F006E0061006D0065002C000D000A002000200020002000200020002000200020002000200020002000770061006900740073002E0077006100690074005F0074007900700065002C000D000A002000200020002000200020002000200020002000200020002000770061006900740073002E0074006F00740061006C005F00770061006900740073002C000D000A002000200020002000200020002000200020002000200020002000770061006900740073002E00730075006D005F006400750072006100740069006F006E005F006D0073002C000D000A002000200020002000200020002000200020002000200020002000770061006900740073002E00730075006D005F007300690067006E0061006C005F006400750072006100740069006F006E005F006D0073002C000D000A002000200020002000200020002000200020002000200020002000770061006900740073002E006100760067005F006D0073005F007000650072005F0077006100690074000D000A0020002000200020004F0052004400450052002000420059002000770061006900740073002E00730075006D005F006400750072006100740069006F006E005F006D007300200044004500530043003B000D000A00;
            INSERT #view_check (view_name, view_definition)
            SELECT N'HumanEvents_WaitsByQueryAndDatabase', 0x0D000A000D000A00430052004500410054004500200056004900450057002000640062006F002E00480075006D0061006E004500760065006E00740073005F0057006100690074007300420079005100750065007200790041006E006400440061007400610062006100730065000D000A00410053000D000A0020002000200020005700490054004800200070006C0061006E005F00770061006900740073000D000A0020002000200020002000200041005300200028000D000A00200020002000200020002000200020002000530045004C0045004300540020004E00270077006100690074007300200062007900200071007500650072007900200061006E0064002000640061007400610062006100730065002700200041005300200077006100690074005F007000610074007400650072006E002C000D000A0020002000200020002000200020002000200020002000200020002000200020004D0049004E002800770061002E006500760065006E0074005F00740069006D006500290020004100530020006D0069006E005F006500760065006E0074005F00740069006D0065002C000D000A0020002000200020002000200020002000200020002000200020002000200020004D00410058002800770061002E006500760065006E0074005F00740069006D006500290020004100530020006D00610078005F006500760065006E0074005F00740069006D0065002C000D000A002000200020002000200020002000200020002000200020002000200020002000770061002E00640061007400610062006100730065005F006E0061006D0065002C000D000A002000200020002000200020002000200020002000200020002000200020002000770061002E0077006100690074005F0074007900700065002C000D000A00200020002000200020002000200020002000200020002000200020002000200043004F0055004E0054005F0042004900470028002A002900200041005300200074006F00740061006C005F00770061006900740073002C000D000A002000200020002000200020002000200020002000200020002000200020002000770061002E0070006C0061006E005F00680061006E0064006C0065002C000D000A002000200020002000200020002000200020002000200020002000200020002000770061002E00710075006500720079005F0070006C0061006E005F0068006100730068005F007300690067006E00650064002C000D000A002000200020002000200020002000200020002000200020002000200020002000770061002E00710075006500720079005F0068006100730068005F007300690067006E00650064002C000D000A002000200020002000200020002000200020002000200020002000200020002000530055004D002800770061002E006400750072006100740069006F006E005F006D00730029002000410053002000730075006D005F006400750072006100740069006F006E005F006D0073002C000D000A002000200020002000200020002000200020002000200020002000200020002000530055004D002800770061002E007300690067006E0061006C005F006400750072006100740069006F006E005F006D00730029002000410053002000730075006D005F007300690067006E0061006C005F006400750072006100740069006F006E005F006D0073002C000D000A002000200020002000200020002000200020002000200020002000200020002000530055004D002800770061002E006400750072006100740069006F006E005F006D007300290020002F00200043004F0055004E0054005F0042004900470028002A00290020004100530020006100760067005F006D0073005F007000650072005F0077006100690074000D000A00200020002000200020002000200020002000460052004F004D0020005B007200650070006C006100630065005F006D0065005D002000410053002000770061000D000A00200020002000200020002000200020002000470052004F00550050002000420059002000770061002E00640061007400610062006100730065005F006E0061006D0065002C000D000A00200020002000200020002000200020002000200020002000200020002000200020002000770061002E0077006100690074005F0074007900700065002C000D000A00200020002000200020002000200020002000200020002000200020002000200020002000770061002E00710075006500720079005F0068006100730068005F007300690067006E00650064002C000D000A00200020002000200020002000200020002000200020002000200020002000200020002000770061002E00710075006500720079005F0070006C0061006E005F0068006100730068005F007300690067006E00650064002C000D000A00200020002000200020002000200020002000200020002000200020002000200020002000770061002E0070006C0061006E005F00680061006E0064006C006500200029000D000A002000200020002000530045004C00450043005400200054004F005000280020003200310034003700340038003300360034003800200029000D000A0020002000200020002000200020002000200020002000700077002E0077006100690074005F007000610074007400650072006E002C000D000A0020002000200020002000200020002000200020002000700077002E006D0069006E005F006500760065006E0074005F00740069006D0065002C000D000A0020002000200020002000200020002000200020002000700077002E006D00610078005F006500760065006E0074005F00740069006D0065002C000D000A0020002000200020002000200020002000200020002000700077002E00640061007400610062006100730065005F006E0061006D0065002C000D000A0020002000200020002000200020002000200020002000700077002E0077006100690074005F0074007900700065002C000D000A0020002000200020002000200020002000200020002000700077002E0074006F00740061006C005F00770061006900740073002C000D000A0020002000200020002000200020002000200020002000700077002E00730075006D005F006400750072006100740069006F006E005F006D0073002C000D000A0020002000200020002000200020002000200020002000700077002E00730075006D005F007300690067006E0061006C005F006400750072006100740069006F006E005F006D0073002C000D000A0020002000200020002000200020002000200020002000700077002E006100760067005F006D0073005F007000650072005F0077006100690074002C000D000A0020002000200020002000200020002000200020002000730074002E0074006500780074002C000D000A0020002000200020002000200020002000200020002000710070002E00710075006500720079005F0070006C0061006E000D000A002000200020002000460052004F004D00200070006C0061006E005F00770061006900740073002000410053002000700077000D000A0020002000200020004F00550054004500520020004100500050004C00590020007300790073002E0064006D005F0065007800650063005F00710075006500720079005F0070006C0061006E002800700077002E0070006C0061006E005F00680061006E0064006C00650029002000410053002000710070000D000A0020002000200020004F00550054004500520020004100500050004C00590020007300790073002E0064006D005F0065007800650063005F00730071006C005F0074006500780074002800700077002E0070006C0061006E005F00680061006E0064006C00650029002000410053002000730074000D000A0020002000200020004F0052004400450052002000420059002000700077002E00730075006D005F006400750072006100740069006F006E005F006D007300200044004500530043003B000D000A00;
            INSERT #view_check (view_name, view_definition)
            SELECT N'HumanEvents_WaitsTotal', 0x0D000A000D000A00430052004500410054004500200056004900450057002000640062006F002E00480075006D0061006E004500760065006E00740073005F005700610069007400730054006F00740061006C000D000A00410053000D000A002000200020002000530045004C00450043005400200054004F005000280020003200310034003700340038003300360034003800200029000D000A00200020002000200020002000200020002000200020004E00270074006F00740061006C002000770061006900740073002700200041005300200077006100690074005F007000610074007400650072006E002C000D000A00200020002000200020002000200020002000200020004D0049004E002800770061002E006500760065006E0074005F00740069006D006500290020004100530020006D0069006E005F006500760065006E0074005F00740069006D0065002C000D000A00200020002000200020002000200020002000200020004D00410058002800770061002E006500760065006E0074005F00740069006D006500290020004100530020006D00610078005F006500760065006E0074005F00740069006D0065002C000D000A0020002000200020002000200020002000200020002000770061002E0077006100690074005F0074007900700065002C000D000A002000200020002000200020002000200020002000200043004F0055004E0054005F0042004900470028002A002900200041005300200074006F00740061006C005F00770061006900740073002C000D000A0020002000200020002000200020002000200020002000530055004D002800770061002E006400750072006100740069006F006E005F006D00730029002000410053002000730075006D005F006400750072006100740069006F006E005F006D0073002C000D000A0020002000200020002000200020002000200020002000530055004D002800770061002E007300690067006E0061006C005F006400750072006100740069006F006E005F006D00730029002000410053002000730075006D005F007300690067006E0061006C005F006400750072006100740069006F006E005F006D0073002C000D000A0020002000200020002000200020002000200020002000530055004D002800770061002E006400750072006100740069006F006E005F006D007300290020002F00200043004F0055004E0054005F0042004900470028002A00290020004100530020006100760067005F006D0073005F007000650072005F0077006100690074000D000A002000200020002000460052004F004D0020005B007200650070006C006100630065005F006D0065005D002000410053002000770061000D000A002000200020002000470052004F00550050002000420059002000770061002E0077006100690074005F0074007900700065000D000A0020002000200020004F0052004400450052002000420059002000730075006D005F006400750072006100740069006F006E005F006D007300200044004500530043003B000D000A00;    
            INSERT #view_check (view_name, view_definition)
            SELECT N'HumanEvents_Compiles_Legacy', 0x430052004500410054004500200056004900450057002000640062006F002E00480075006D0061006E004500760065006E00740073005F0043006F006D00700069006C00650073005F004C00650067006100630079000D000A00410053000D000A00530045004C00450043005400200054004F00500020002800320031003400370034003800330036003400380029000D000A0020002000200020002000200020006500760065006E0074005F00740069006D0065002C000D000A0020002000200020002000200020006500760065006E0074005F0074007900700065002C000D000A002000200020002000200020002000640061007400610062006100730065005F006E0061006D0065002C000D000A0020002000200020002000200020006F0062006A006500630074005F006E0061006D0065002C000D000A002000200020002000200020002000730074006100740065006D0065006E0074005F0074006500780074000D000A00460052004F004D0020005B007200650070006C006100630065005F006D0065005D000D000A004F00520044004500520020004200590020006500760065006E0074005F00740069006D0065003B00
            WHERE @compile_events = 0;
            INSERT #view_check (view_name, view_definition)
            SELECT N'HumanEvents_Recompiles_Legacy', 0x430052004500410054004500200056004900450057002000640062006F002E00480075006D0061006E004500760065006E00740073005F005200650063006F006D00700069006C00650073005F004C00650067006100630079000D000A00410053000D000A00530045004C00450043005400200054004F00500020002800320031003400370034003800330036003400380029000D000A0020002000200020002000200020006500760065006E0074005F00740069006D0065002C000D000A0020002000200020002000200020006500760065006E0074005F0074007900700065002C000D000A002000200020002000200020002000640061007400610062006100730065005F006E0061006D0065002C000D000A0020002000200020002000200020006F0062006A006500630074005F006E0061006D0065002C000D000A0020002000200020002000200020007200650063006F006D00700069006C0065005F00630061007500730065002C000D000A002000200020002000200020002000730074006100740065006D0065006E0074005F0074006500780074000D000A00460052004F004D0020005B007200650070006C006100630065005F006D0065005D000D000A004F00520044004500520020004200590020006500760065006E0074005F00740069006D0065003B00
            WHERE @compile_events = 0;

            RAISERROR(N'Updating #view_check with output database (%s) and schema (%s)', 0, 1, @output_database_name, @output_schema_name) WITH NOWAIT;
            UPDATE #view_check 
                SET 
                    output_database = @output_database_name, 
                    output_schema = @output_schema_name;
            
            RAISERROR(N'Updating #view_check with table names', 0, 1) WITH NOWAIT;
            UPDATE vc 
                SET 
                    vc.output_table = hew.output_table
            FROM #view_check AS vc
            JOIN #human_events_worker AS hew
                ON  vc.view_name LIKE N'%' + hew.event_type_short + N'%'
                AND hew.is_table_created = 1
                AND hew.is_view_created = 0;
        
            UPDATE vc 
                SET 
                    vc.output_table = hew.output_table + N'_parameterization'
            FROM #view_check AS vc
            JOIN #human_events_worker AS hew
                ON  vc.view_name = N'HumanEvents_Parameterization'
                AND hew.output_table LIKE N'keeper_HumanEvents_compiles%'
                AND hew.is_table_created = 1
                AND hew.is_view_created = 0;
        
            IF @debug = 1 BEGIN SELECT N'#view_check' AS table_name, * FROM #view_check AS vc; END;
        
        END;
        
        IF (@view_tracker IS NULL
                OR @view_tracker = 0 )
        BEGIN 
            RAISERROR(N'Starting view creation loop', 0, 1) WITH NOWAIT;
            
            SELECT 
               @min_id = MIN(vc.id), 
               @max_id = MAX(vc.id)
            FROM #view_check AS vc
            WHERE vc.output_table <> N''
            AND   EXISTS
            (
                SELECT 
                    1/0
                FROM #human_events_worker AS hew
                WHERE vc.view_name LIKE N'%' + hew.event_type_short + N'%'
                AND hew.is_table_created = 1
                AND hew.is_view_created = 0
            );
            
                WHILE @min_id <= @max_id
                BEGIN
                                
                    SELECT 
                        @event_type_check  = 
                            LOWER(vc.view_name),
                        @object_name_check = 
                            QUOTENAME(vc.output_database) + 
                            N'.' + 
                            QUOTENAME(vc.output_schema) + 
                            N'.' + 
                            QUOTENAME(vc.view_name),
                        @view_database = 
                            QUOTENAME(vc.output_database),
                        @view_sql = 
                            REPLACE
                            (
                                REPLACE
                                (
                                    REPLACE
                                    ( 
                                        vc.view_converted, 
                                        N'[replace_me]', 
                                        QUOTENAME(vc.output_schema)  + 
                                        N'.'  + 
                                        vc.output_table 
                                    ),
                                    N'[dbo]' + 
                                    '.' + 
                                    QUOTENAME(vc.view_name),
                                    QUOTENAME(vc.output_schema) + 
                                    '.' + 
                                    QUOTENAME(vc.view_name) 
                                ),
                                N'', 
                                N'''' 
                            )
                    FROM #view_check AS vc
                    WHERE vc.id = @min_id
                    AND   vc.output_table <> N'';
                
                    IF OBJECT_ID(@object_name_check) IS NOT NULL
                    BEGIN
                      RAISERROR(N'Uh oh, found a view', 0, 1) WITH NOWAIT;
                      SET 
                          @view_sql = 
                              REPLACE
                              (
                                  @view_sql, 
                                  N'CREATE VIEW', 
                                  N'ALTER VIEW'
                              );
                    END;
                    
                    SELECT @spe = @view_database + @spe;
                    
                    IF @debug = 1 BEGIN RAISERROR(@spe, 0, 1) WITH NOWAIT; END;
            
                    IF @debug = 1
                    BEGIN 
                        PRINT SUBSTRING(@view_sql, 0,     4000);
                        PRINT SUBSTRING(@view_sql, 4000,  8000);
                        PRINT SUBSTRING(@view_sql, 8000,  12000);
                        PRINT SUBSTRING(@view_sql, 12000, 16000);
                        PRINT SUBSTRING(@view_sql, 16000, 20000);
                        PRINT SUBSTRING(@view_sql, 20000, 24000);
                        PRINT SUBSTRING(@view_sql, 24000, 28000);
                        PRINT SUBSTRING(@view_sql, 28000, 32000);
                        PRINT SUBSTRING(@view_sql, 32000, 36000);
                        PRINT SUBSTRING(@view_sql, 36000, 40000);           
                    END;
                    
                    RAISERROR(N'creating view %s', 0, 1, @event_type_check) WITH NOWAIT;
                    EXEC @spe @view_sql;
            
                    IF @debug = 1 BEGIN RAISERROR(N'@min_id: %i', 0, 1, @min_id) WITH NOWAIT; END;
            
                    RAISERROR(N'Setting next id after %i out of %i total', 0, 1, @min_id, @max_id) WITH NOWAIT;
                    
                    SET @min_id = 
                    (
                        SELECT TOP (1) 
                            vc.id
                        FROM #view_check AS vc
                        WHERE vc.id > @min_id
                        AND   vc.output_table <> N''
                        ORDER BY vc.id
                    );
            
                    IF @debug = 1 BEGIN RAISERROR(N'new @min_id: %i', 0, 1, @min_id) WITH NOWAIT; END;
            
                    IF @min_id IS NULL BREAK;
            
                    SET @spe = N'.sys.sp_executesql ';
            
                END;
            
                UPDATE #human_events_worker 
                    SET 
                        is_view_created = 1;
                
                SET @view_tracker = 1;        
        END;
    END;

    /*This section handles inserting data into tables*/
    IF EXISTS
    (
        SELECT 
            1/0
        FROM #human_events_worker AS hew
        WHERE hew.is_table_created = 1
        AND   hew.last_checked < DATEADD(SECOND, -5, SYSDATETIME())
    )
    BEGIN
    
        RAISERROR(N'Sessions that need data found, starting loop.', 0, 1) WITH NOWAIT;
        
        SELECT 
            @min_id = MIN(hew.id), 
            @max_id = MAX(hew.id)
        FROM #human_events_worker AS hew
        WHERE hew.is_table_created = 1;

        WHILE @min_id <= @max_id
        BEGIN

            SELECT 
                @event_type_check  = 
                    hew.event_type,
                @object_name_check = 
                    QUOTENAME(hew.output_database) + 
                    N'.' + 
                    QUOTENAME(hew.output_schema) + 
                    N'.' + 
                    hew.output_table,
                @date_filter = 
                    DATEADD
                    (
                        MINUTE, 
                        DATEDIFF
                        (
                            MINUTE, 
                            SYSDATETIME(), 
                            GETUTCDATE()
                        ), 
                        hew.last_checked
                    )
            FROM #human_events_worker AS hew
            WHERE hew.id = @min_id
            AND   hew.is_table_created = 1;
        
            IF OBJECT_ID(@object_name_check) IS NOT NULL
            BEGIN
            RAISERROR(N'Generating insert table statement for %s', 0, 1, @event_type_check) WITH NOWAIT;
                SELECT 
                    @table_sql = 
                        CASE 
                        WHEN @event_type_check LIKE N'%wait%' /*Wait stats!*/
                        THEN N'INSERT INTO ' + @object_name_check + N' WITH(TABLOCK) ' + @nc10 + 
                             N'( server_name, event_time, event_type, database_name, wait_type, duration_ms, ' + @nc10 +
                             N'  signal_duration_ms, wait_resource,  query_plan_hash_signed, query_hash_signed, plan_handle )' + @nc10 +
                             N'SELECT 
        @@SERVERNAME,
        DATEADD
        (
            MINUTE, 
            DATEDIFF
            (
                 MINUTE, 
                 GETUTCDATE(), 
                 SYSDATETIME()
             ), 
             c.value(''@timestamp'', ''datetime2'')
        ) AS event_time,
        c.value(''@name'', ''nvarchar(256)'') AS event_type,
        c.value(''(action[@name="database_name"]/value/text())[1]'', ''nvarchar(256)'') AS database_name,                
        c.value(''(data[@name="wait_type"]/text)[1]'', ''nvarchar(256)'') AS wait_type,
        c.value(''(data[@name="duration"]/value/text())[1]'', ''bigint'')  AS duration_ms,
        c.value(''(data[@name="signal_duration"]/value/text())[1]'', ''bigint'') AS signal_duration_ms,' + @nc10 +
CASE 
    WHEN @v = 11 /*We can't get the wait resource on older versions of SQL Server*/
    THEN N'        ''Not Available < 2014'', ' + @nc10
    ELSE N'        c.value(''(data[@name="wait_resource"]/value/text())[1]'', ''nvarchar(256)'')  AS wait_resource, ' + @nc10
END + N'        CONVERT
                (
                    binary(8), 
                    c.value(''(action[@name="query_plan_hash_signed"]/value/text())[1]'', ''bigint'')
                ) AS query_plan_hash_signed,
        CONVERT
        (
            binary(8), 
            c.value(''(action[@name="query_hash_signed"]/value/text())[1]'', ''bigint'')
        ) AS query_hash_signed,
        c.value(''xs:hexBinary((action[@name="plan_handle"]/value/text())[1])'', ''varbinary(64)'') AS plan_handle
FROM #human_events_xml_internal AS xet
OUTER APPLY xet.human_events_xml.nodes(''//event'') AS oa(c)
WHERE c.exist(''(data[@name="duration"]/value/text()[. > 0])'') = 1 
AND   c.exist(''@timestamp[. > sql:variable("@date_filter")]'') = 1;'
                        WHEN @event_type_check LIKE N'%lock%' /*Blocking!*/
                                                              /*To cut down on nonsense, I'm only inserting new blocking scenarios*/
                                                              /*Any existing blocking scenarios will update the blocking duration*/
                        THEN N'INSERT INTO ' + @object_name_check + N' WITH(TABLOCK) ' + @nc10 + 
                             N'( server_name, event_time, activity, database_name, database_id, object_id, ' + @nc10 +
                             N'  transaction_id, resource_owner_type, monitor_loop, spid, ecid, query_text, wait_time, ' + @nc10 +
                             N'  transaction_name,  last_transaction_started, wait_resource, lock_mode, status, priority, ' + @nc10 +
                             N'  transaction_count, client_app, host_name, login_name, isolation_level, sql_handle, blocked_process_report )' + @nc10 +
N'
SELECT server_name, event_time, activity, database_name, database_id, object_id, 
       transaction_id, resource_owner_type, monitor_loop, spid, ecid, text, waittime, 
       transactionname,  lasttranstarted, wait_resource, lockmode, status, priority, 
       trancount, clientapp, hostname, loginname, isolationlevel, sqlhandle, process_report
FROM 
( 
    SELECT 
        x.*, 
        x = 
            ROW_NUMBER() 
                OVER
                ( 
                    PARTITION BY 
                        x.spid, 
                        x.ecid, 
                        x.transaction_id, 
                        x.activity 
                    ORDER BY     
                        x.spid, 
                        x.ecid, 
                        x.transaction_id, 
                        x.activity 
                )
    FROM 
    (
        SELECT 
            @@SERVERNAME AS server_name,
            DATEADD
            (
                MINUTE, 
                DATEDIFF
                (
                    MINUTE, 
                    GETUTCDATE(), 
                    SYSDATETIME()
                ), c.value(''@timestamp'', ''datetime2'')
            ) AS event_time,        
            ''blocked'' AS activity,
            DB_NAME(c.value(''(data[@name="database_id"]/value/text())[1]'', ''int'')) AS database_name,
            c.value(''(data[@name="database_id"]/value/text())[1]'', ''int'') AS database_id,
            c.value(''(data[@name="object_id"]/value/text())[1]'', ''int'') AS object_id,
            c.value(''(data[@name="transaction_id"]/value/text())[1]'', ''bigint'') AS transaction_id,
            c.value(''(data[@name="resource_owner_type"]/text)[1]'', ''nvarchar(256)'') AS resource_owner_type,
            c.value(''(//@monitorLoop)[1]'', ''int'') AS monitor_loop,
            bd.value(''(process/@spid)[1]'', ''int'') AS spid,
            bd.value(''(process/@ecid)[1]'', ''int'') AS ecid,
            bd.value(''(process/inputbuf/text())[1]'', ''nvarchar(MAX)'') AS text,
            bd.value(''(process/@waittime)[1]'', ''bigint'') AS waittime,
            bd.value(''(process/@transactionname)[1]'', ''nvarchar(256)'') AS transactionname,
            bd.value(''(process/@lasttranstarted)[1]'', ''datetime2'') AS lasttranstarted,
            bd.value(''(process/@waitresource)[1]'', ''nvarchar(100)'') AS wait_resource,
            bd.value(''(process/@lockMode)[1]'', ''nvarchar(10)'') AS lockmode,
            bd.value(''(process/@status)[1]'', ''nvarchar(10)'') AS status,
            bd.value(''(process/@priority)[1]'', ''int'') AS priority,
            bd.value(''(process/@trancount)[1]'', ''int'') AS trancount,
            bd.value(''(process/@clientapp)[1]'', ''nvarchar(256)'') AS clientapp,
            bd.value(''(process/@hostname)[1]'', ''nvarchar(256)'') AS hostname,
            bd.value(''(process/@loginname)[1]'', ''nvarchar(256)'') AS loginname,
            bd.value(''(process/@isolationlevel)[1]'', ''nvarchar(50)'') AS isolationlevel,
            CONVERT
            (
                varbinary(64), 
                bd.value(''(process/executionStack/frame/@sqlhandle)[1]'', ''nvarchar(260)'')
            ) AS sqlhandle,
            c.query(''.'') AS process_report
        FROM #human_events_xml_internal AS xet
        OUTER APPLY xet.human_events_xml.nodes(''//event'') AS oa(c)
        OUTER APPLY oa.c.nodes(''//blocked-process-report/blocked-process'') AS bd(bd)
        WHERE c.exist(''@timestamp[. > sql:variable("@date_filter")]'') = 1
        
        UNION ALL
        
        SELECT 
            @@SERVERNAME AS server_name,
            DATEADD
            (
                MINUTE, 
                DATEDIFF
                (
                    MINUTE, 
                    GETUTCDATE(), 
                    SYSDATETIME()
                ), 
                c.value(''@timestamp'', ''datetime2'')
            ) AS event_time,        
            ''blocking'' AS activity,
            DB_NAME(c.value(''(data[@name="database_id"]/value/text())[1]'', ''int'')) AS database_name,
            c.value(''(data[@name="database_id"]/value/text())[1]'', ''int'') AS database_id,
            c.value(''(data[@name="object_id"]/value/text())[1]'', ''int'') AS object_id,
            c.value(''(data[@name="transaction_id"]/value/text())[1]'', ''bigint'') AS transaction_id,
            c.value(''(data[@name="resource_owner_type"]/text)[1]'', ''nvarchar(256)'') AS resource_owner_type,
            c.value(''(//@monitorLoop)[1]'', ''int'') AS monitor_loop,
            bg.value(''(process/@spid)[1]'', ''int'') AS spid,
            bg.value(''(process/@ecid)[1]'', ''int'') AS ecid,
            bg.value(''(process/inputbuf/text())[1]'', ''nvarchar(MAX)'') AS text,
            NULL AS waittime,
            NULL AS transactionname,
            NULL AS lasttranstarted,
            NULL AS wait_resource,
            NULL AS lockmode,
            bg.value(''(process/@status)[1]'', ''nvarchar(10)'') AS status,
            bg.value(''(process/@priority)[1]'', ''int'') AS priority,
            bg.value(''(process/@trancount)[1]'', ''int'') AS trancount,
            bg.value(''(process/@clientapp)[1]'', ''nvarchar(256)'') AS clientapp,
            bg.value(''(process/@hostname)[1]'', ''nvarchar(256)'') AS hostname,
            bg.value(''(process/@loginname)[1]'', ''nvarchar(256)'') AS loginname,
            bg.value(''(process/@isolationlevel)[1]'', ''nvarchar(50)'') AS isolationlevel,
            NULL AS sqlhandle,
            c.query(''.'') AS process_report
        FROM #human_events_xml_internal AS xet
        OUTER APPLY xet.human_events_xml.nodes(''//event'') AS oa(c)
        OUTER APPLY oa.c.nodes(''//blocked-process-report/blocking-process'') AS bg(bg)
        WHERE c.exist(''@timestamp[. > sql:variable("@date_filter")]'') = 1
    ) AS x
) AS x
WHERE NOT EXISTS
(
    SELECT 
        1/0
    FROM ' + @object_name_check + N' AS x2
    WHERE x.database_id = x2.database_id
    AND   x.object_id = x2.object_id
    AND   x.transaction_id = x2.transaction_id
    AND   x.spid = x2.spid
    AND   x.ecid = x2.ecid
    AND   x.clientapp = x2.client_app
    AND   x.hostname = x2.host_name
    AND   x.loginname = x2.login_name
)
AND x.x = 1;

UPDATE x2
    SET 
        x2.wait_time = x.waittime
FROM ' + @object_name_check + N' AS x2
JOIN 
(
    SELECT 
        @@SERVERNAME AS server_name,       
        ''blocked'' AS activity,
        c.value(''(data[@name="database_id"]/value/text())[1]'', ''int'') AS database_id,
        c.value(''(data[@name="object_id"]/value/text())[1]'', ''int'') AS object_id,
        c.value(''(data[@name="transaction_id"]/value/text())[1]'', ''bigint'') AS transaction_id,
        c.value(''(//@monitorLoop)[1]'', ''int'') AS monitor_loop,
        bd.value(''(process/@spid)[1]'', ''int'') AS spid,
        bd.value(''(process/@ecid)[1]'', ''int'') AS ecid,
        bd.value(''(process/@waittime)[1]'', ''bigint'') AS waittime,
        bd.value(''(process/@clientapp)[1]'', ''nvarchar(256)'') AS clientapp,
        bd.value(''(process/@hostname)[1]'', ''nvarchar(256)'') AS hostname,
        bd.value(''(process/@loginname)[1]'', ''nvarchar(256)'') AS loginname
    FROM #human_events_xml_internal AS xet
    OUTER APPLY xet.human_events_xml.nodes(''//event'') AS oa(c)
    OUTER APPLY oa.c.nodes(''//blocked-process-report/blocked-process'') AS bd(bd)
    WHERE c.exist(''@timestamp[. > sql:variable("@date_filter")]'') = 1
) AS x
    ON    x.database_id = x2.database_id
    AND   x.object_id = x2.object_id
    AND   x.transaction_id = x2.transaction_id
    AND   x.spid = x2.spid
    AND   x.ecid = x2.ecid
    AND   x.clientapp = x2.client_app
    AND   x.hostname = x2.host_name
    AND   x.loginname = x2.login_name;
'
                       WHEN @event_type_check LIKE N'%quer%' /*Queries!*/
                       THEN N'INSERT INTO ' + @object_name_check + N' WITH(TABLOCK) ' + @nc10 + 
                            N'( server_name, event_time, event_type, database_name, object_name, sql_text, statement, ' + @nc10 +
                            N'  showplan_xml, cpu_ms, logical_reads, physical_reads, duration_ms, writes_mb, ' + @nc10 +
                            N'  spills_mb, row_count, estimated_rows, dop,  serial_ideal_memory_mb, ' + @nc10 +
                            N'  requested_memory_mb, used_memory_mb, ideal_memory_mb, granted_memory_mb, ' + @nc10 +
                            N'  query_plan_hash_signed, query_hash_signed, plan_handle )' + @nc10 +
                            N'SELECT 
    @@SERVERNAME, 
    DATEADD
    (
        MINUTE, 
        DATEDIFF
        (
            MINUTE, 
            GETUTCDATE(), 
            SYSDATETIME()
        ), 
        c.value(''@timestamp'', ''datetime2'')
    ) AS event_time,
    c.value(''@name'', ''nvarchar(256)'') AS event_type,
    c.value(''(action[@name="database_name"]/value/text())[1]'', ''nvarchar(256)'') AS database_name,                
    c.value(''(data[@name="object_name"]/value/text())[1]'', ''nvarchar(256)'') AS [object_name],
    c.value(''(action[@name="sql_text"]/value/text())[1]'', ''nvarchar(MAX)'') AS sql_text,
    c.value(''(data[@name="statement"]/value/text())[1]'', ''nvarchar(MAX)'') AS statement,
    c.query(''(data[@name="showplan_xml"]/value/*)[1]'') AS [showplan_xml],
    c.value(''(data[@name="cpu_time"]/value/text())[1]'', ''bigint'') / 1000. AS cpu_ms,
   (c.value(''(data[@name="logical_reads"]/value/text())[1]'', ''bigint'') * 8) / 1024. AS logical_reads,
   (c.value(''(data[@name="physical_reads"]/value/text())[1]'', ''bigint'') * 8) / 1024. AS physical_reads,
    c.value(''(data[@name="duration"]/value/text())[1]'', ''bigint'') / 1000. AS duration_ms,
   (c.value(''(data[@name="writes"]/value/text())[1]'', ''bigint'') * 8) / 1024. AS writes_mb,
   (c.value(''(data[@name="spills"]/value/text())[1]'', ''bigint'') * 8) / 1024. AS spills_mb,
    c.value(''(data[@name="row_count"]/value/text())[1]'', ''bigint'') AS row_count,
    c.value(''(data[@name="estimated_rows"]/value/text())[1]'', ''bigint'') AS estimated_rows,
    c.value(''(data[@name="dop"]/value/text())[1]'', ''int'') AS dop,
    c.value(''(data[@name="serial_ideal_memory_kb"]/value/text())[1]'', ''bigint'') / 1024. AS serial_ideal_memory_mb,
    c.value(''(data[@name="requested_memory_kb"]/value/text())[1]'', ''bigint'') / 1024. AS requested_memory_mb,
    c.value(''(data[@name="used_memory_kb"]/value/text())[1]'', ''bigint'') / 1024. AS used_memory_mb,
    c.value(''(data[@name="ideal_memory_kb"]/value/text())[1]'', ''bigint'') / 1024. AS ideal_memory_mb,
    c.value(''(data[@name="granted_memory_kb"]/value/text())[1]'', ''bigint'') / 1024. AS granted_memory_mb,
    CONVERT
    (
        binary(8), 
        c.value(''(action[@name="query_plan_hash_signed"]/value/text())[1]'', ''bigint'')
    ) AS query_plan_hash_signed,
    CONVERT
    (
        binary(8), 
        c.value(''(action[@name="query_hash_signed"]/value/text())[1]'', ''bigint'')
    ) AS query_hash_signed,
    c.value(''xs:hexBinary((action[@name="plan_handle"]/value/text())[1])'', ''varbinary(64)'') AS plan_handle
FROM #human_events_xml_internal AS xet
OUTER APPLY xet.human_events_xml.nodes(''//event'') AS oa(c)
WHERE c.exist(''@timestamp[. > sql:variable("@date_filter")]'') = 1
AND   c.exist(''(action[@name="query_hash_signed"]/value[. != 0])'') = 1; '
                       WHEN @event_type_check LIKE N'%recomp%' /*Recompiles!*/
                       THEN N'INSERT INTO ' + @object_name_check + N' WITH(TABLOCK) ' + @nc10 + 
                            N'( server_name, event_time,  event_type,  ' + @nc10 +
                            N'  database_name, object_name, recompile_cause, statement_text '
                            + CASE WHEN @compile_events = 1 THEN N', compile_cpu_ms, compile_duration_ms )' ELSE N' )' END + @nc10 +
                            N'SELECT 
    @@SERVERNAME,
    DATEADD
    (
        MINUTE, 
        DATEDIFF
        (
            MINUTE, 
            GETUTCDATE(), 
            SYSDATETIME()
        ), c.value(''@timestamp'', ''datetime2'')
    ) AS event_time,
    c.value(''@name'', ''nvarchar(256)'') AS event_type,
    c.value(''(action[@name="database_name"]/value/text())[1]'', ''nvarchar(256)'') AS database_name,                
    c.value(''(data[@name="object_name"]/value/text())[1]'', ''nvarchar(256)'') AS [object_name],
    c.value(''(data[@name="recompile_cause"]/text)[1]'', ''nvarchar(256)'') AS recompile_cause,
    c.value(''(data[@name="statement"]/value/text())[1]'', ''nvarchar(MAX)'') AS statement_text '
   + CASE WHEN @compile_events = 1 /*Only get these columns if we're using the newer XE: sql_statement_post_compile*/
          THEN 
   N'  , 
    c.value(''(data[@name="cpu_time"]/value/text())[1]'', ''bigint'') AS compile_cpu_ms,
    c.value(''(data[@name="duration"]/value/text())[1]'', ''bigint'') AS compile_duration_ms'
          ELSE N''
     END + N'
FROM #human_events_xml_internal AS xet
OUTER APPLY xet.human_events_xml.nodes(''//event'') AS oa(c)
WHERE 1 = 1 '
      + CASE WHEN @compile_events = 1 /*Same here, where we need to filter data*/
             THEN 
N'
AND c.exist(''(data[@name="is_recompile"]/value[. = "false"])'') = 0 '
             ELSE N''
        END + N'
AND c.exist(''@timestamp[. > sql:variable("@date_filter")]'') = 1
ORDER BY event_time;'
                       WHEN @event_type_check LIKE N'%comp%' AND @event_type_check NOT LIKE N'%re%' /*Compiles!*/
                       THEN N'INSERT INTO ' + REPLACE(@object_name_check, N'_parameterization', N'') + N' WITH(TABLOCK) ' + @nc10 + 
                            N'( server_name, event_time,  event_type,  ' + @nc10 +
                            N'  database_name, object_name, statement_text '
                            + CASE WHEN @compile_events = 1 THEN N', compile_cpu_ms, compile_duration_ms )' ELSE N' )' END + @nc10 +
                            N'SELECT 
    @@SERVERNAME,
    DATEADD
    (
        MINUTE, 
        DATEDIFF
        (
            MINUTE, 
            GETUTCDATE(), 
            SYSDATETIME()
        ), 
        c.value(''@timestamp'', ''datetime2'')
    ) AS event_time,
    c.value(''@name'', ''nvarchar(256)'') AS event_type,
    c.value(''(action[@name="database_name"]/value/text())[1]'', ''nvarchar(256)'') AS database_name,                
    c.value(''(data[@name="object_name"]/value/text())[1]'', ''nvarchar(256)'') AS [object_name],
    c.value(''(data[@name="statement"]/value/text())[1]'', ''nvarchar(MAX)'') AS statement_text '
   + CASE WHEN @compile_events = 1 /*Only get these columns if we're using the newer XE: sql_statement_post_compile*/
          THEN 
   N'  , 
    c.value(''(data[@name="cpu_time"]/value/text())[1]'', ''bigint'') AS compile_cpu_ms,
    c.value(''(data[@name="duration"]/value/text())[1]'', ''bigint'') AS compile_duration_ms'
          ELSE N''
     END + N'
FROM #human_events_xml_internal AS xet
OUTER APPLY xet.human_events_xml.nodes(''//event'') AS oa(c)
WHERE 1 = 1 '
      + CASE WHEN @compile_events = 1 /*Just like above*/
             THEN 
N' 
AND c.exist(''(data[@name="is_recompile"]/value[. = "false"])'') = 1 '
             ELSE N''
        END + N'
AND   c.exist(''@name[.= "sql_statement_post_compile"]'') = 1
AND   c.exist(''@timestamp[. > sql:variable("@date_filter")]'') = 1
ORDER BY event_time;' + @nc10
                            + CASE WHEN @parameterization_events = 1 /*The query_parameterization_data XE is only 2017+*/
                                   THEN 
                            @nc10 + 
                            N'INSERT INTO ' + REPLACE(@object_name_check, N'_parameterization', N'') + N'_parameterization' + N' WITH(TABLOCK) ' + @nc10 + 
                            N'( server_name, event_time,  event_type, database_name, sql_text, compile_cpu_time_ms, ' + @nc10 +
                            N'  compile_duration_ms, query_param_type, is_cached, is_recompiled, compile_code, has_literals, ' + @nc10 +
                            N'  is_parameterizable, parameterized_values_count, query_plan_hash, query_hash, plan_handle, statement_sql_hash ) ' + @nc10 +
                            N'SELECT 
    @@SERVERNAME,
    DATEADD
    (
        MINUTE, 
        DATEDIFF
        (
            MINUTE, 
            GETUTCDATE(), 
            SYSDATETIME()
        ), 
        c.value(''@timestamp'', ''datetime2'')
    ) AS event_time,
    c.value(''@name'', ''nvarchar(256)'') AS event_type,
    c.value(''(action[@name="database_name"]/value/text())[1]'', ''nvarchar(256)'') AS database_name,                
    c.value(''(action[@name="sql_text"]/value/text())[1]'', ''nvarchar(MAX)'') AS sql_text,
    c.value(''(data[@name="compile_cpu_time"]/value/text())[1]'', ''bigint'') / 1000. AS compile_cpu_time_ms,
    c.value(''(data[@name="compile_duration"]/value/text())[1]'', ''bigint'') / 1000. AS compile_duration_ms,
    c.value(''(data[@name="query_param_type"]/value/text())[1]'', ''int'') AS query_param_type,
    c.value(''(data[@name="is_cached"]/value/text())[1]'', ''bit'') AS is_cached,
    c.value(''(data[@name="is_recompiled"]/value/text())[1]'', ''bit'') AS is_recompiled,
    c.value(''(data[@name="compile_code"]/text)[1]'', ''nvarchar(256)'') AS compile_code,                  
    c.value(''(data[@name="has_literals"]/value/text())[1]'', ''bit'') AS has_literals,
    c.value(''(data[@name="is_parameterizable"]/value/text())[1]'', ''bit'') AS is_parameterizable,
    c.value(''(data[@name="parameterized_values_count"]/value/text())[1]'', ''bigint'') AS parameterized_values_count,
    c.value(''xs:hexBinary((data[@name="query_plan_hash"]/value/text())[1])'', ''binary(8)'') AS query_plan_hash,
    c.value(''xs:hexBinary((data[@name="query_hash"]/value/text())[1])'', ''binary(8)'') AS query_hash,
    c.value(''xs:hexBinary((action[@name="plan_handle"]/value/text())[1])'', ''varbinary(64)'') AS plan_handle, 
    c.value(''xs:hexBinary((data[@name="statement_sql_hash"]/value/text())[1])'', ''varbinary(64)'') AS statement_sql_hash
FROM #human_events_xml_internal AS xet
OUTER APPLY xet.human_events_xml.nodes(''//event'') AS oa(c)
WHERE c.exist(''@name[.= "query_parameterization_data"]'') = 1
AND   c.exist(''(data[@name="is_recompiled"]/value[. = "false"])'') = 1
AND   c.exist(''@timestamp[. > sql:variable("@date_filter")]'') = 1
ORDER BY event_time;'
                                   ELSE N'' 
                              END  
                       ELSE N''
                  END;
            
            /* this table is only used for the inserts, hence the "internal" in the name */
            IF @azure = 0
            BEGIN
                INSERT
                    #x
                (
                    x
                )  
                SELECT 
                    x = 
                        CONVERT
                        (
                            xml, 
                            t.target_data
                        )
                FROM   sys.dm_xe_session_targets AS t
                JOIN   sys.dm_xe_sessions AS s
                    ON s.address = t.event_session_address
                WHERE  s.name = @event_type_check
                AND    t.target_name = N'ring_buffer';
            END;
            ELSE
            BEGIN
                INSERT
                    #x
                (
                    x
                )  
                SELECT 
                    x = 
                        CONVERT
                        (
                            xml, 
                            t.target_data
                        )
                FROM   sys.dm_xe_database_session_targets AS t
                JOIN   sys.dm_xe_database_sessions AS s
                    ON s.address = t.event_session_address
                WHERE  s.name = @event_type_check
                AND    t.target_name = N'ring_buffer';
            END;
            
            INSERT 
                #human_events_xml_internal WITH (TABLOCK)
            (
                human_events_xml
            )            
            SELECT 
                human_events_xml = 
                    e.x.query('.')
                FROM #x AS x
            CROSS APPLY x.x.nodes('/RingBufferTarget/event') AS e(x)
            WHERE e.x.exist('@timestamp[. > sql:variable("@date_filter")]') = 1;
            
            IF @debug = 1
            BEGIN 
                PRINT SUBSTRING(@table_sql, 0, 4000);
                PRINT SUBSTRING(@table_sql, 4000, 8000);
                PRINT SUBSTRING(@table_sql, 8000, 12000);
                PRINT SUBSTRING(@table_sql, 12000, 16000);
                PRINT SUBSTRING(@table_sql, 16000, 20000);
                PRINT SUBSTRING(@table_sql, 20000, 24000);
                PRINT SUBSTRING(@table_sql, 24000, 28000);
                PRINT SUBSTRING(@table_sql, 28000, 32000);
                PRINT SUBSTRING(@table_sql, 32000, 36000);
                PRINT SUBSTRING(@table_sql, 36000, 40000);           
            END;
            
            /* this executes the insert */
            EXEC sys.sp_executesql 
                @table_sql, 
              N'@date_filter DATETIME', 
                @date_filter;
            
            /*Update the worker table's last checked, and conditionally, updated dates*/
            UPDATE hew
                SET 
                    hew.last_checked = 
                        SYSDATETIME(),
                    hew.last_updated = 
                        CASE 
                            WHEN @@ROWCOUNT > 0 
                            THEN SYSDATETIME()
                            ELSE hew.last_updated
                        END 
            FROM #human_events_worker AS hew
            WHERE hew.id = @min_id;
            
            IF @debug = 1 BEGIN SELECT N'#human_events_worker' AS table_name, * FROM #human_events_worker AS hew; END;
            IF @debug = 1 BEGIN SELECT N'#human_events_xml_internal' AS table_name, * FROM #human_events_xml_internal AS hew; END;

            /*Clear the table out between runs*/
            TRUNCATE TABLE #human_events_xml_internal;
            TRUNCATE TABLE #x;

            IF @debug = 1 BEGIN RAISERROR(N'@min_id: %i', 0, 1, @min_id) WITH NOWAIT; END;

            RAISERROR(N'Setting next id after %i out of %i total', 0, 1, @min_id, @max_id) WITH NOWAIT;
            
            SET @min_id = 
            (
                SELECT TOP (1) 
                    hew.id
                FROM #human_events_worker AS hew
                WHERE hew.id > @min_id
                AND   hew.is_table_created = 1
                ORDER BY hew.id
            );

            IF @debug = 1 BEGIN RAISERROR(N'new @min_id: %i', 0, 1, @min_id) WITH NOWAIT; END;

            IF @min_id IS NULL BREAK;
            
            END;
        END;
    
    END;


/*This section handles deleting data from tables older than the retention period*/
/*The idea is to only check once an hour so we're not constantly purging*/
SET @Time = SYSDATETIME();
IF 
( 
    DATEPART
    (
        MINUTE, 
        @Time
    ) <= 5 
)
BEGIN     
    
    IF (@delete_tracker IS NULL
            OR @delete_tracker <> DATEPART(HOUR, @Time) )
    BEGIN     
        
        SELECT 
            @the_deleter_must_awaken += 
                N' DELETE FROM ' + 
                QUOTENAME(hew.output_database) + 
                N'.' +
                QUOTENAME(hew.output_schema) + 
                N'.' +
                QUOTENAME(hew.event_type) + 
                N' WHERE event_time < DATEADD
                                      (
                                          DAY, 
                                          (-1 * @delete_retention_days
                                      ), 
                                      SYSDATETIME()); ' + @nc10
        FROM #human_events_worker AS hew;
        
        IF @debug = 1 BEGIN RAISERROR(@the_deleter_must_awaken, 0, 1) WITH NOWAIT; END;
        
        /* execute the delete */
        EXEC sys.sp_executesql 
            @the_deleter_must_awaken, 
          N'@delete_retention_days INT', 
            @delete_retention_days;
        
        /* set this to the hour it was last checked */
        SET @delete_tracker = DATEPART(HOUR, SYSDATETIME());    
    END;
END;

/*Wait 5 seconds, then start the output loop again*/
WAITFOR DELAY '00:00:05.000';

END;

/*This section handles cleaning up stuff.*/
cleanup:
BEGIN     
    RAISERROR(N'CLEAN UP PARTY TONIGHT', 0, 1) WITH NOWAIT;

    SET @executer = QUOTENAME(@output_database_name) + N'.sys.sp_executesql ';

    /*Clean up sessions, this isn't database-specific*/         
    SELECT 
        @cleanup_sessions +=   
            N'DROP EVENT SESSION ' + 
            ses.name + 
            N' ON SERVER;' + 
            @nc10  
    FROM sys.server_event_sessions AS ses  
    LEFT JOIN sys.dm_xe_sessions AS dxs  
        ON dxs.name = ses.name  
    WHERE ses.name LIKE N'%HumanEvents_%';  
        
    EXEC sys.sp_executesql 
        @cleanup_sessions;  
    
    IF @debug = 1 BEGIN RAISERROR(@cleanup_sessions, 0, 1) WITH NOWAIT; END;
  

    /*Clean up tables*/
    RAISERROR(N'CLEAN UP PARTY TONIGHT', 0, 1) WITH NOWAIT;
  
    SELECT 
        @cleanup_tables += N'
            SELECT 
                @i_cleanup_tables += 
                    N''DROP TABLE '' +  
                    SCHEMA_NAME(s.schema_id) + 
                    N''.'' + 
                    QUOTENAME(s.name) + 
                    ''; '' + 
                    NCHAR(10)
            FROM ' + QUOTENAME(@output_database_name) + N'.sys.tables AS s
            WHERE s.name LIKE ''' + '%HumanEvents%' + N''';';
    
    EXEC sys.sp_executesql 
        @cleanup_tables, 
      N'@i_cleanup_tables nvarchar(MAX) OUTPUT', 
        @i_cleanup_tables = @drop_holder OUTPUT;  
    
    IF @debug = 1 
    BEGIN
        RAISERROR(@executer, 0, 1) WITH NOWAIT;
        RAISERROR(@drop_holder, 0, 1) WITH NOWAIT;
    END;
    
    EXEC @executer @drop_holder;
  
    /*Cleanup views*/
    RAISERROR(N'CLEAN UP PARTY TONIGHT', 0, 1) WITH NOWAIT;

    SET @drop_holder = N'';
  
    SELECT 
        @cleanup_views += N'
            SELECT 
                @i_cleanup_views += 
                    N''DROP VIEW '' + 
                    SCHEMA_NAME(v.schema_id) + 
                    N''.'' + 
                    QUOTENAME(v.name) + 
                    ''; '' + 
                    NCHAR(10)
            FROM ' + QUOTENAME(@output_database_name) + N'.sys.views AS v
            WHERE v.name LIKE ''' + '%HumanEvents%' + N''';';
    
    EXEC sys.sp_executesql 
        @cleanup_views, 
      N'@i_cleanup_views nvarchar(MAX) OUTPUT', 
        @i_cleanup_views = @drop_holder OUTPUT;  
    
    IF @debug = 1 
    BEGIN
        RAISERROR(@executer, 0, 1) WITH NOWAIT;
        RAISERROR(@drop_holder, 0, 1) WITH NOWAIT;
    END;

    EXEC @executer @drop_holder;

    RETURN;
END; 


END TRY

/*Error handling, I guess*/
BEGIN CATCH
    BEGIN
    
    IF @@TRANCOUNT > 0 
        ROLLBACK TRANSACTION;
              
        /*Only try to drop a session if we're not outputting*/
        IF (@output_database_name = N''
              AND @output_schema_name = N'')
        BEGIN
            IF @debug = 1 BEGIN RAISERROR(@stop_sql, 0, 1) WITH NOWAIT; END;
            RAISERROR(N'all done, stopping session', 0, 1) WITH NOWAIT;
            EXEC (@stop_sql);
            
            IF @debug = 1 BEGIN RAISERROR(@drop_sql, 0, 1) WITH NOWAIT; END;
            RAISERROR(N'and dropping session', 0, 1) WITH NOWAIT;
            EXEC (@drop_sql);
        END;

        THROW;

        RETURN -138;
    END;
END CATCH;

END;
GO
