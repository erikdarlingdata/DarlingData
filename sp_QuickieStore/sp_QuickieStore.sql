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

 ██████╗ ██╗   ██╗██╗ ██████╗██╗  ██╗██╗███████╗
██╔═══██╗██║   ██║██║██╔════╝██║ ██╔╝██║██╔════╝
██║   ██║██║   ██║██║██║     █████╔╝ ██║█████╗
██║▄▄ ██║██║   ██║██║██║     ██╔═██╗ ██║██╔══╝
╚██████╔╝╚██████╔╝██║╚██████╗██║  ██╗██║███████╗
 ╚══▀▀═╝  ╚═════╝ ╚═╝ ╚═════╝╚═╝  ╚═╝╚═╝╚══════╝

███████╗████████╗ ██████╗ ██████╗ ███████╗██╗
██╔════╝╚══██╔══╝██╔═══██╗██╔══██╗██╔════╝██║
███████╗   ██║   ██║   ██║██████╔╝█████╗  ██║
╚════██║   ██║   ██║   ██║██╔══██╗██╔══╝  ╚═╝
███████║   ██║   ╚██████╔╝██║  ██║███████╗██╗
╚══════╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝

Copyright 2024 Darling Data, LLC
https://www.erikdarling.com/

For usage and licensing details, run:
EXEC sp_QuickieStore
    @help = 1;

For working through errors:
EXEC sp_QuickieStore
    @debug = 1;

For performance issues:
EXEC sp_QuickieStore
    @troubleshoot_performance = 1;

For support, head over to GitHub:
https://github.com/erikdarlingdata/DarlingData

*/

IF OBJECT_ID('dbo.sp_QuickieStore') IS NULL
   BEGIN
       EXEC ('CREATE PROCEDURE dbo.sp_QuickieStore AS RETURN 138;');
   END;
GO

ALTER PROCEDURE
    dbo.sp_QuickieStore
(
    @database_name sysname = NULL, /*the name of the database you want to look at query store in*/
    @sort_order varchar(20) = 'cpu', /*the runtime metric you want to prioritize results by*/
    @top bigint = 10, /*the number of queries you want to pull back*/
    @start_date datetimeoffset(7) = NULL, /*the begin date of your search, will be converted to UTC internally*/
    @end_date datetimeoffset(7) = NULL, /*the end date of your search, will be converted to UTC internally*/
    @timezone sysname = NULL, /*user specified time zone to override dates displayed in results*/
    @execution_count bigint = NULL, /*the minimum number of executions a query must have*/
    @duration_ms bigint = NULL, /*the minimum duration a query must have to show up in results*/
    @execution_type_desc nvarchar(60) = NULL, /*the type of execution you want to filter by (success, failure)*/
    @procedure_schema sysname = NULL, /*the schema of the procedure you're searching for*/
    @procedure_name sysname = NULL, /*the name of the programmable object you're searching for*/
    @include_plan_ids nvarchar(4000) = NULL, /*a list of plan ids to search for*/
    @include_query_ids nvarchar(4000) = NULL, /*a list of query ids to search for*/
    @include_query_hashes nvarchar(4000) = NULL, /*a list of query hashes to search for*/
    @include_plan_hashes nvarchar(4000) = NULL, /*a list of query plan hashes to search for*/
    @include_sql_handles nvarchar(4000) = NULL, /*a list of sql handles to search for*/
    @ignore_plan_ids nvarchar(4000) = NULL, /*a list of plan ids to ignore*/
    @ignore_query_ids nvarchar(4000) = NULL, /*a list of query ids to ignore*/
    @ignore_query_hashes nvarchar(4000) = NULL, /*a list of query hashes to ignore*/
    @ignore_plan_hashes nvarchar(4000) = NULL, /*a list of query plan hashes to ignore*/
    @ignore_sql_handles nvarchar(4000) = NULL, /*a list of sql handles to ignore*/
    @query_text_search nvarchar(4000) = NULL, /*query text to search for*/
    @escape_brackets bit = 0, /*Set this bit to 1 to search for query text containing square brackets (common in .NET Entity Framework and other ORM queries)*/
    @escape_character nchar(1) = N'\', /*Sets the ESCAPE character for special character searches, defaults to the SQL standard backslash (\) character*/
    @only_queries_with_hints bit = 0, /*Set this bit to 1 to retrieve only queries with query hints*/
    @only_queries_with_feedback bit = 0, /*Set this bit to 1 to retrieve only queries with query feedback*/
    @only_queries_with_variants bit = 0, /*Set this bit to 1 to retrieve only queries with query variants*/
    @only_queries_with_forced_plans bit = 0, /*Set this bit to 1 to retrieve only queries with forced plans*/
    @only_queries_with_forced_plan_failures bit = 0, /*Set this bit to 1 to retrieve only queries with forced plan failures*/
    @wait_filter varchar(20) = NULL, /*wait category to search for; category details are below*/
    @query_type varchar(11) = NULL, /*filter for only ad hoc queries or only from queries from modules*/
    @expert_mode bit = 0, /*returns additional columns and results*/
    @format_output bit = 1, /*returns numbers formatted with commas*/
    @get_all_databases bit = 0, /*looks for query store enabled databases and returns combined results from all of them*/
    @workdays bit = 0, /*Use this to filter out weekends and after-hours queries*/
    @work_start time(0) = '9am', /*Use this to set a specific start of your work days*/
    @work_end time(0) = '5pm', /*Use this to set a specific end of your work days*/
    @help bit = 0, /*return available parameter details, etc.*/
    @debug bit = 0, /*prints dynamic sql, statement length, parameter and variable values, and raw temp table contents*/
    @troubleshoot_performance bit = 0, /*set statistics xml on for queries against views*/
    @version varchar(30) = NULL OUTPUT, /*OUTPUT; for support*/
    @version_date datetime = NULL OUTPUT /*OUTPUT; for support*/
)
WITH RECOMPILE
AS
BEGIN
SET STATISTICS XML OFF;
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

BEGIN TRY
/*
If this column doesn't exist, you're not on a good version of SQL Server
*/
IF NOT EXISTS
   (
       SELECT
           1/0
       FROM sys.all_columns AS ac
       WHERE ac.object_id = OBJECT_ID(N'sys.dm_exec_query_stats', N'V')
       AND   ac.name = N'total_spills'
   )
BEGIN
    RAISERROR('This procedure only runs on supported versions of SQL Server:
* 2016 SP2+
* 2017 CU3+
* 2019+
* Probably Azure?', 11, 1) WITH NOWAIT;

    RETURN;
END;

/*
These are for your outputs.
*/
SELECT
    @version = '4.5',
    @version_date = '20240401';

/*
Helpful section! For help.
*/
IF @help = 1
BEGIN
    /*
    Introduction
    */
    SELECT
        introduction =
           'hi, i''m sp_QuickieStore!' UNION ALL
    SELECT 'you got me from https://github.com/erikdarlingdata/DarlingData/tree/main/sp_QuickieStore' UNION ALL
    SELECT 'i can be used to quickly grab misbehaving queries from query store' UNION ALL
    SELECT 'the plan analysis is up to you; there will not be any XML shredding here' UNION ALL
    SELECT 'so what can you do, and how do you do it? read below!' UNION ALL
    SELECT  'from your loving sql server consultant, erik darling: https://erikdarling.com';

    /*
    Parameters
    */
    SELECT
        parameter_name =
            ap.name,
        data_type = t.name,
        description =
            CASE
                ap.name
                WHEN N'@database_name' THEN 'the name of the database you want to look at query store in'
                WHEN N'@sort_order' THEN 'the runtime metric you want to prioritize results by'
                WHEN N'@top' THEN 'the number of queries you want to pull back'
                WHEN N'@start_date' THEN 'the begin date of your search, will be converted to UTC internally'
                WHEN N'@end_date' THEN 'the end date of your search, will be converted to UTC internally'
                WHEN N'@timezone' THEN 'user specified time zone to override dates displayed in results'
                WHEN N'@execution_count' THEN 'the minimum number of executions a query must have'
                WHEN N'@duration_ms' THEN 'the minimum duration a query must have to show up in results'
                WHEN N'@execution_type_desc' THEN 'the type of execution you want to filter by (success, failure)'
                WHEN N'@procedure_schema' THEN 'the schema of the procedure you''re searching for'
                WHEN N'@procedure_name' THEN 'the name of the programmable object you''re searching for'
                WHEN N'@include_plan_ids' THEN 'a list of plan ids to search for'
                WHEN N'@include_query_ids' THEN 'a list of query ids to search for'
                WHEN N'@include_query_hashes' THEN 'a list of query hashes to search for'
                WHEN N'@include_plan_hashes' THEN 'a list of query plan hashes to search for'
                WHEN N'@include_sql_handles' THEN 'a list of sql handles to search for'
                WHEN N'@ignore_plan_ids' THEN 'a list of plan ids to ignore'
                WHEN N'@ignore_query_ids' THEN 'a list of query ids to ignore'
                WHEN N'@ignore_query_hashes' THEN 'a list of query hashes to ignore'
                WHEN N'@ignore_plan_hashes' THEN 'a list of query plan hashes to ignore'
                WHEN N'@ignore_sql_handles' THEN 'a list of sql handles to ignore'
                WHEN N'@query_text_search' THEN 'query text to search for'
                WHEN N'@escape_brackets' THEN 'Set this bit to 1 to search for query text containing square brackets (common in .NET Entity Framework and other ORM queries)'
                WHEN N'@escape_character' THEN 'Sets the ESCAPE character for special character searches, defaults to the SQL standard backslash (\) character'
                WHEN N'@only_queries_with_hints' THEN 'only return queries with query hints'
                WHEN N'@only_queries_with_feedback' THEN 'only return queries with query feedback'
                WHEN N'@only_queries_with_variants' THEN 'only return queries with query variants'
                WHEN N'@only_queries_with_forced_plans' THEN 'only return queries with forced plans'
                WHEN N'@only_queries_with_forced_plan_failures' THEN 'only return queries with forced plan failures'
                WHEN N'@wait_filter' THEN 'wait category to search for; category details are below'
                WHEN N'@query_type' THEN 'filter for only ad hoc queries or only from queries from modules'
                WHEN N'@expert_mode' THEN 'returns additional columns and results'
                WHEN N'@format_output' THEN 'returns numbers formatted with commas'
                WHEN N'@get_all_databases' THEN 'looks for query store enabled databases and returns combined results from all of them'
                WHEN N'@workdays' THEN 'use this to filter out weekends and after-hours queries'
                WHEN N'@work_start' THEN 'use this to set a specific start of your work days'
                WHEN N'@work_end' THEN 'use this to set a specific end of your work days'
                WHEN N'@help' THEN 'how you got here'
                WHEN N'@debug' THEN 'prints dynamic sql, statement length, parameter and variable values, and raw temp table contents'
                WHEN N'@troubleshoot_performance' THEN 'set statistics xml on for queries against views'
                WHEN N'@version' THEN 'OUTPUT; for support'
                WHEN N'@version_date' THEN 'OUTPUT; for support'
            END,
        valid_inputs =
            CASE
                ap.name
                WHEN N'@database_name' THEN 'a database name with query store enabled'
                WHEN N'@sort_order' THEN 'cpu, logical reads, physical reads, writes, duration, memory, tempdb, executions, recent'
                WHEN N'@top' THEN 'a positive integer between 1 and 9,223,372,036,854,775,807'
                WHEN N'@start_date' THEN 'January 1, 1753, through December 31, 9999'
                WHEN N'@end_date' THEN 'January 1, 1753, through December 31, 9999'
                WHEN N'@timezone' THEN 'SELECT tzi.* FROM sys.time_zone_info AS tzi;'
                WHEN N'@execution_count' THEN 'a positive integer between 1 and 9,223,372,036,854,775,807'
                WHEN N'@duration_ms' THEN 'a positive integer between 1 and 9,223,372,036,854,775,807'
                WHEN N'@execution_type_desc' THEN 'regular, aborted, exception'
                WHEN N'@procedure_schema' THEN 'a valid schema in your database'
                WHEN N'@procedure_name' THEN 'a valid programmable object in your database'
                WHEN N'@include_plan_ids' THEN 'a string; comma separated for multiple ids'
                WHEN N'@include_query_ids' THEN 'a string; comma separated for multiple ids'
                WHEN N'@include_query_hashes' THEN 'a string; comma separated for multiple hashes'
                WHEN N'@include_plan_hashes' THEN 'a string; comma separated for multiple hashes'
                WHEN N'@include_sql_handles' THEN 'a string; comma separated for multiple handles'
                WHEN N'@ignore_plan_ids' THEN 'a string; comma separated for multiple ids'
                WHEN N'@ignore_query_ids' THEN 'a string; comma separated for multiple ids'
                WHEN N'@ignore_query_hashes' THEN 'a string; comma separated for multiple hashes'
                WHEN N'@ignore_plan_hashes' THEN 'a string; comma separated for multiple hashes'
                WHEN N'@ignore_sql_handles' THEN 'a string; comma separated for multiple handles'
                WHEN N'@query_text_search' THEN 'a string; leading and trailing wildcards will be added if missing'
                WHEN N'@escape_brackets' THEN '0 or 1'
                WHEN N'@escape_character' THEN 'some escape character, SQL standard is backslash (\)'
                WHEN N'@only_queries_with_hints' THEN '0 or 1'
                WHEN N'@only_queries_with_feedback' THEN '0 or 1'
                WHEN N'@only_queries_with_variants' THEN '0 or 1'
                WHEN N'@only_queries_with_forced_plans' THEN '0 or 1'
                WHEN N'@only_queries_with_forced_plan_failures' THEN '0 or 1'
                WHEN N'@wait_filter' THEN 'cpu, lock, latch, buffer latch, buffer io, log io, network io, parallelism, memory'
                WHEN N'@query_type' THEN 'ad hoc, adhoc, proc, procedure, whatever.'
                WHEN N'@expert_mode' THEN '0 or 1'
                WHEN N'@format_output' THEN '0 or 1'
                WHEN N'@get_all_databases' THEN '0 or 1'
                WHEN N'@workdays' THEN '0 or 1'
                WHEN N'@work_start' THEN 'a time like 8am, 9am or something'
                WHEN N'@work_end' THEN 'a time like 5pm, 6pm or something'
                WHEN N'@help' THEN '0 or 1'
                WHEN N'@debug' THEN '0 or 1'
                WHEN N'@troubleshoot_performance' THEN '0 or 1'
                WHEN N'@version' THEN 'none; OUTPUT'
                WHEN N'@version_date' THEN 'none; OUTPUT'
            END,
        defaults =
            CASE
                ap.name
                WHEN N'@database_name' THEN 'NULL; current non-system database name if NULL'
                WHEN N'@sort_order' THEN 'cpu'
                WHEN N'@top' THEN '10'
                WHEN N'@start_date' THEN 'the last seven days'
                WHEN N'@end_date' THEN 'NULL'
                WHEN N'@timezone' THEN 'NULL'
                WHEN N'@execution_count' THEN 'NULL'
                WHEN N'@duration_ms' THEN 'NULL'
                WHEN N'@execution_type_desc' THEN 'NULL'
                WHEN N'@procedure_schema' THEN 'NULL; dbo if NULL and procedure name is not NULL'
                WHEN N'@procedure_name' THEN 'NULL'
                WHEN N'@include_plan_ids' THEN 'NULL'
                WHEN N'@include_query_ids' THEN 'NULL'
                WHEN N'@include_query_hashes' THEN 'NULL'
                WHEN N'@include_plan_hashes' THEN 'NULL'
                WHEN N'@include_sql_handles' THEN 'NULL'
                WHEN N'@ignore_plan_ids' THEN 'NULL'
                WHEN N'@ignore_query_ids' THEN 'NULL'
                WHEN N'@ignore_query_hashes' THEN 'NULL'
                WHEN N'@ignore_plan_hashes' THEN 'NULL'
                WHEN N'@ignore_sql_handles' THEN 'NULL'
                WHEN N'@query_text_search' THEN 'NULL'
                WHEN N'@escape_brackets' THEN '0'
                WHEN N'@escape_character' THEN '\'
                WHEN N'@only_queries_with_hints' THEN '0'
                WHEN N'@only_queries_with_feedback' THEN '0'
                WHEN N'@only_queries_with_variants' THEN '0'
                WHEN N'@only_queries_with_forced_plans' THEN '0'
                WHEN N'@only_queries_with_forced_plan_failures' THEN '0'
                WHEN N'@wait_filter' THEN 'NULL'
                WHEN N'@query_type' THEN 'NULL'
                WHEN N'@expert_mode' THEN '0'
                WHEN N'@format_output' THEN '1'
                WHEN N'@get_all_databases' THEN '0'
                WHEN N'@workdays' THEN '0'
                WHEN N'@work_start' THEN '9am'
                WHEN N'@work_end' THEN '5pm'
                WHEN N'@debug' THEN '0'
                WHEN N'@help' THEN '0'
                WHEN N'@troubleshoot_performance' THEN '0'
                WHEN N'@version' THEN 'none; OUTPUT'
                WHEN N'@version_date' THEN 'none; OUTPUT'
            END
    FROM sys.all_parameters AS ap
    INNER JOIN sys.all_objects AS o
      ON ap.object_id = o.object_id
    INNER JOIN sys.types AS t
      ON  ap.system_type_id = t.system_type_id
      AND ap.user_type_id = t.user_type_id
    WHERE o.name = N'sp_QuickieStore'
    OPTION(RECOMPILE);

    /*
    Wait categories: Only 2017+
    */
    IF EXISTS
    (
        SELECT
            1/0
        FROM sys.all_objects AS ao
        WHERE ao.name = N'query_store_wait_stats'
    )
    BEGIN
        SELECT
            wait_categories =
               'cpu (1): SOS_SCHEDULER_YIELD' UNION ALL
        SELECT 'lock (3): LCK_M_%' UNION ALL
        SELECT 'latch (4): LATCH_%' UNION ALL
        SELECT 'buffer latch (5): PAGELATCH_%' UNION ALL
        SELECT 'buffer io (6): PAGEIOLATCH_%' UNION ALL
        SELECT 'log io (14): LOGMGR, LOGBUFFER, LOGMGR_RESERVE_APPEND, LOGMGR_FLUSH, LOGMGR_PMM_LOG, CHKPT, WRITELOG' UNION ALL
        SELECT 'network io (15): ASYNC_NETWORK_IO, NET_WAITFOR_PACKET, PROXY_NETWORK_IO, EXTERNAL_SCRIPT_NETWORK_IOF' UNION ALL
        SELECT 'parallelism (16): CXPACKET, EXCHANGE, HT%, BMP%, BP%' UNION ALL
        SELECT 'memory (17): RESOURCE_SEMAPHORE, CMEMTHREAD, CMEMPARTITIONED, EE_PMOLOCK, MEMORY_ALLOCATION_EXT, RESERVED_MEMORY_ALLOCATION_EXT, MEMORY_GRANT_UPDATE';
    END;

    /*
    Results
    */
    SELECT
        results =
           'results returned at the end of the procedure:' UNION ALL
    SELECT REPLICATE('-', 100) UNION ALL
    SELECT 'Runtime Stats: data from query_store_runtime_stats, along with query plan, query text, wait stats (2017+, when enabled), and parent object' UNION ALL
    SELECT REPLICATE('-', 100) UNION ALL
    SELECT 'Compilation Stats (expert mode only): data from query_store_query about compilation metrics' UNION ALL
    SELECT REPLICATE('-', 100) UNION ALL
    SELECT 'Resource Stats (expert mode only): data from dm_exec_query_stats, when available' UNION ALL
    SELECT 'query store does not currently track some details about memory grants and thread usage' UNION ALL
    SELECT 'so i go back to a plan cache view to try to track it down' UNION ALL
    SELECT REPLICATE('-', 100) UNION ALL
    SELECT 'Query Store Plan Feedback (2022+, expert mode, or when using only_queries_with_feedback): Lists queries that have been adjusted based on automated feedback mechanisms' UNION ALL
    SELECT REPLICATE('-', 100) UNION ALL
    SELECT 'Query Store Hints (2022+, expert mode or when using @only_queries_with_hints): lists hints applied to queries from automated feedback mechanisms' UNION ALL
    SELECT REPLICATE('-', 100) UNION ALL
    SELECT 'Query Variants (2022+, expert mode or when using @only_queries_with_variants): lists plan variants from the Parameter Sensitive Plan feedback mechanism' UNION ALL
    SELECT REPLICATE('-', 100) UNION ALL
    SELECT 'Query Store Waits By Query (2017+, expert mode only): information about query duration and logged wait stats' UNION ALL
    SELECT 'it can sometimes be useful to compare query duration to query wait times' UNION ALL
    SELECT REPLICATE('-', 100) UNION ALL
    SELECT 'Query Store Waits Total (2017+, expert mode only): total wait stats for the chosen date range only' UNION ALL
    SELECT REPLICATE('-', 100) UNION ALL
    SELECT 'Query Replicas (2022+, expert mode only): lists plans forced on AG replicas' UNION ALL
    SELECT REPLICATE('-', 100) UNION ALL
    SELECT 'Query Store Options (expert mode only): details about current query store configuration';

    /*
    Limitations
    */
    SELECT
        limitations =
           'frigid shortcomings:'  UNION ALL
    SELECT 'you need to be on at least SQL Server 2016 SP2, 2017 CU3, or any higher version to run this' UNION ALL
    SELECT 'if you''re on azure sql db then you''ll need to be in compat level 130' UNION ALL
    SELECT 'i do not currently support synapse or edge or other memes, and azure sql db support is not guaranteed';

    /*
    License to F5
    */
    SELECT
        mit_license_yo =
           'i am MIT licensed, so like, do whatever'
    UNION ALL

    SELECT
        mit_license_yo =
            'see printed messages for full license';

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
END; /*End @help section*/

/*
These are the tables that we'll use to grab data from query store
It will be fun
You'll love it
*/

/*
Plans we'll be working on
*/
CREATE TABLE
    #distinct_plans
(
    plan_id bigint PRIMARY KEY
);

/*
Hold plan_ids for procedures we're searching
*/
CREATE TABLE
    #procedure_plans
(
    plan_id bigint PRIMARY KEY
);

/*
Hold plan_ids for ad hoc or procedures we're searching for
*/
CREATE TABLE
    #query_types
(
    plan_id bigint PRIMARY KEY
);

/*
Hold plan_ids for plans we want
*/
CREATE TABLE
    #include_plan_ids
(
    plan_id bigint PRIMARY KEY WITH (IGNORE_DUP_KEY = ON)
);

/*
Hold query_ids for plans we want
*/
CREATE TABLE
    #include_query_ids
(
    query_id bigint PRIMARY KEY
);

/*
Hold plan_ids for ignored plans
*/
CREATE TABLE
    #ignore_plan_ids
(
    plan_id bigint PRIMARY KEY WITH (IGNORE_DUP_KEY = ON)
);

/*
Hold query_ids for ignored plans
*/
CREATE TABLE
    #ignore_query_ids
(
    query_id bigint PRIMARY KEY
);

/*
Hold query hashes for plans we want
*/
CREATE TABLE
    #include_query_hashes
(
    query_hash_s varchar(131),
    query_hash AS
        CONVERT
        (
            binary(8),
            query_hash_s,
            1
        ) PERSISTED NOT NULL PRIMARY KEY
);

/*
Hold plan hashes for plans we want
*/
CREATE TABLE
    #include_plan_hashes
(
    plan_hash_s varchar(131),
    plan_hash AS
        CONVERT
        (
            binary(8),
            plan_hash_s,
            1
        ) PERSISTED NOT NULL PRIMARY KEY
);

/*
Hold query hashes for ignored plans
*/
CREATE TABLE
    #ignore_query_hashes
(
    query_hash_s varchar(131),
    query_hash AS
        CONVERT
        (
            binary(8),
            query_hash_s,
            1
        ) PERSISTED NOT NULL PRIMARY KEY
);

/*
Hold plan hashes for ignored plans
*/
CREATE TABLE
    #ignore_plan_hashes
(
    plan_hash_s varchar(131),
    plan_hash AS
        CONVERT
        (
            binary(8),
            plan_hash_s,
            1
        ) PERSISTED NOT NULL PRIMARY KEY
);

/*
Hold sql handles for plans we want
*/
CREATE TABLE
    #include_sql_handles
(
    sql_handle_s varchar(131),
    sql_handle AS
        CONVERT
        (
            varbinary(64),
            sql_handle_s,
            1
        ) PERSISTED NOT NULL PRIMARY KEY
);

/*
Hold sql handles for ignored plans
*/
CREATE TABLE
    #ignore_sql_handles
(
    sql_handle_s varchar(131),
    sql_handle AS
        CONVERT
        (
            varbinary(64),
            sql_handle_s,
            1
        ) PERSISTED NOT NULL PRIMARY KEY
);

/*
Hold plan_ids for only query with hints
*/
CREATE TABLE
    #only_queries_with_hints
(
    plan_id bigint PRIMARY KEY
);

/*
Hold plan_ids for only query with feedback
*/
CREATE TABLE
    #only_queries_with_feedback
(
    plan_id bigint PRIMARY KEY
);

/*
Hold plan_ids for only query with variants
*/
CREATE TABLE
    #only_queries_with_variants
(
    plan_id bigint PRIMARY KEY
);

/*
Hold plan_ids for forced plans and/or forced plan failures
I'm overloading this a bit for simplicity, since searching for
failures is just an extension of searching for forced plans
*/

CREATE TABLE
    #forced_plans_failures
(
    plan_id bigint PRIMARY KEY
);

/*
Hold plan_ids for matching query text
*/
CREATE TABLE
    #query_text_search
(
    plan_id bigint PRIMARY KEY
);

/*
Hold plan_ids for matching wait filter
*/
CREATE TABLE
    #wait_filter
(
    plan_id bigint PRIMARY KEY
);

/*
Index and statistics entries to avoid
*/
CREATE TABLE
    #maintenance_plans
(
    plan_id bigint PRIMARY KEY
);

/*
Query Store Setup
*/
CREATE TABLE
    #database_query_store_options
(
    database_id int NOT NULL,
    desired_state_desc nvarchar(60) NULL,
    actual_state_desc nvarchar(60) NULL,
    readonly_reason nvarchar(100) NULL,
    current_storage_size_mb bigint NULL,
    flush_interval_seconds bigint NULL,
    interval_length_minutes bigint NULL,
    max_storage_size_mb bigint NULL,
    stale_query_threshold_days bigint NULL,
    max_plans_per_query bigint NULL,
    query_capture_mode_desc nvarchar(60) NULL,
    capture_policy_execution_count int NULL,
    capture_policy_total_compile_cpu_time_ms bigint NULL,
    capture_policy_total_execution_cpu_time_ms bigint NULL,
    capture_policy_stale_threshold_hours int NULL,
    size_based_cleanup_mode_desc nvarchar(60) NULL,
    wait_stats_capture_mode_desc nvarchar(60) NULL
);

/*
Query Store Trouble
*/
CREATE TABLE
    #query_store_trouble
(
    database_id int NOT NULL,
    desired_state_desc nvarchar(60) NULL,
    actual_state_desc nvarchar(60) NULL,
    readonly_reason nvarchar(100) NULL,
    current_storage_size_mb bigint NULL,
    flush_interval_seconds bigint NULL,
    interval_length_minutes bigint NULL,
    max_storage_size_mb bigint NULL,
    stale_query_threshold_days bigint NULL,
    max_plans_per_query bigint NULL,
    query_capture_mode_desc nvarchar(60) NULL,
    size_based_cleanup_mode_desc nvarchar(60) NULL
);

/*
Plans and Plan information
*/
CREATE TABLE
    #query_store_plan
(
    database_id int NOT NULL,
    plan_id bigint NOT NULL,
    query_id bigint NOT NULL,
    all_plan_ids varchar(MAX),
    plan_group_id bigint NULL,
    engine_version nvarchar(32) NULL,
    compatibility_level smallint NOT NULL,
    query_plan_hash binary(8) NOT NULL,
    query_plan nvarchar(MAX) NULL,
    is_online_index_plan bit NOT NULL,
    is_trivial_plan bit NOT NULL,
    is_parallel_plan bit NOT NULL,
    is_forced_plan bit NOT NULL,
    is_natively_compiled bit NOT NULL,
    force_failure_count bigint NOT NULL,
    last_force_failure_reason_desc nvarchar(128) NULL,
    count_compiles bigint NULL,
    initial_compile_start_time datetimeoffset(7) NOT NULL,
    last_compile_start_time datetimeoffset(7) NULL,
    last_execution_time datetimeoffset(7) NULL,
    avg_compile_duration_ms float NULL,
    last_compile_duration_ms bigint NULL,
    plan_forcing_type_desc nvarchar(60) NULL,
    has_compile_replay_script bit NULL,
    is_optimized_plan_forcing_disabled bit NULL,
    plan_type_desc nvarchar(120) NULL
);

/*
Queries and Compile Information
*/
CREATE TABLE
    #query_store_query
(
    database_id int NOT NULL,
    query_id bigint NOT NULL,
    query_text_id bigint NOT NULL,
    context_settings_id bigint NOT NULL,
    object_id bigint NULL,
    object_name AS
        ISNULL
        (
            QUOTENAME
            (
                OBJECT_SCHEMA_NAME
                (
                    object_id,
                    database_id
                )
            ) +
            N'.' +
            QUOTENAME
            (
                OBJECT_NAME
                (
                    object_id,
                    database_id
                )
            ),
            N'Adhoc'
        ),
    batch_sql_handle varbinary(64) NULL,
    query_hash binary(8) NOT NULL,
    is_internal_query bit NOT NULL,
    query_parameterization_type_desc nvarchar(60) NULL,
    initial_compile_start_time datetimeoffset(7) NOT NULL,
    last_compile_start_time datetimeoffset(7) NULL,
    last_execution_time datetimeoffset(7) NULL,
    last_compile_batch_sql_handle varbinary(64) NULL,
    last_compile_batch_offset_start bigint NULL,
    last_compile_batch_offset_end bigint NULL,
    count_compiles bigint NULL,
    avg_compile_duration_ms float NULL,
    total_compile_duration_ms AS
        (count_compiles * avg_compile_duration_ms),
    last_compile_duration_ms bigint NULL,
    avg_bind_duration_ms float NULL,
    total_bind_duration_ms AS
        (count_compiles * avg_bind_duration_ms),
    last_bind_duration_ms bigint NULL,
    avg_bind_cpu_time_ms float NULL,
    total_bind_cpu_time_ms AS
        (count_compiles * avg_bind_cpu_time_ms),
    last_bind_cpu_time_ms bigint NULL,
    avg_optimize_duration_ms float NULL,
    total_optimize_duration_ms AS
        (count_compiles * avg_optimize_duration_ms),
    last_optimize_duration_ms bigint NULL,
    avg_optimize_cpu_time_ms float NULL,
    total_optimize_cpu_time_ms AS
        (count_compiles * avg_optimize_cpu_time_ms),
    last_optimize_cpu_time_ms bigint NULL,
    avg_compile_memory_mb float NULL,
    total_compile_memory_mb AS
        (count_compiles * avg_compile_memory_mb),
    last_compile_memory_mb bigint NULL,
    max_compile_memory_mb bigint NULL,
    is_clouddb_internal_query bit NULL
);

/*
Query Text And Columns From sys.dm_exec_query_stats
*/
CREATE TABLE
    #query_store_query_text
(
    database_id int NOT NULL,
    query_text_id bigint NOT NULL,
    query_sql_text xml NULL,
    statement_sql_handle varbinary(64) NULL,
    is_part_of_encrypted_module bit NOT NULL,
    has_restricted_text bit NOT NULL,
    total_grant_mb bigint NULL,
    last_grant_mb bigint NULL,
    min_grant_mb bigint NULL,
    max_grant_mb bigint NULL,
    total_used_grant_mb bigint NULL,
    last_used_grant_mb bigint NULL,
    min_used_grant_mb bigint NULL,
    max_used_grant_mb bigint NULL,
    total_ideal_grant_mb bigint NULL,
    last_ideal_grant_mb bigint NULL,
    min_ideal_grant_mb bigint NULL,
    max_ideal_grant_mb bigint NULL,
    total_reserved_threads bigint NULL,
    last_reserved_threads bigint NULL,
    min_reserved_threads bigint NULL,
    max_reserved_threads bigint NULL,
    total_used_threads bigint NULL,
    last_used_threads bigint NULL,
    min_used_threads bigint NULL,
    max_used_threads bigint NULL
);

/*
Figure it out.
*/
CREATE TABLE
    #dm_exec_query_stats
(
    statement_sql_handle varbinary(64) NOT NULL,
    total_grant_mb bigint NULL,
    last_grant_mb bigint NULL,
    min_grant_mb bigint NULL,
    max_grant_mb bigint NULL,
    total_used_grant_mb bigint NULL,
    last_used_grant_mb bigint NULL,
    min_used_grant_mb bigint NULL,
    max_used_grant_mb bigint NULL,
    total_ideal_grant_mb bigint NULL,
    last_ideal_grant_mb bigint NULL,
    min_ideal_grant_mb bigint NULL,
    max_ideal_grant_mb bigint NULL,
    total_reserved_threads bigint NULL,
    last_reserved_threads bigint NULL,
    min_reserved_threads bigint NULL,
    max_reserved_threads bigint NULL,
    total_used_threads bigint NULL,
    last_used_threads bigint NULL,
    min_used_threads bigint NULL,
    max_used_threads bigint NULL
);

/*
Runtime stats information
*/
CREATE TABLE
    #query_store_runtime_stats
(
    database_id int NOT NULL,
    runtime_stats_id bigint NOT NULL,
    plan_id bigint NOT NULL,
    runtime_stats_interval_id bigint NOT NULL,
    execution_type_desc nvarchar(60) NULL,
    first_execution_time datetimeoffset(7) NOT NULL,
    last_execution_time datetimeoffset(7) NOT NULL,
    count_executions bigint NOT NULL,
    executions_per_second AS
        ISNULL
        (
            count_executions /
                NULLIF
                (
                    DATEDIFF
                    (
                        SECOND,
                        first_execution_time,
                        last_execution_time
                    ),
                    0
                ),
                0
        ),
    avg_duration_ms float NULL,
    last_duration_ms bigint NOT NULL,
    min_duration_ms bigint NOT NULL,
    max_duration_ms bigint NOT NULL,
    total_duration_ms AS
        (avg_duration_ms * count_executions),
    avg_cpu_time_ms float NULL,
    last_cpu_time_ms bigint NOT NULL,
    min_cpu_time_ms bigint NOT NULL,
    max_cpu_time_ms bigint NOT NULL,
    total_cpu_time_ms AS
        (avg_cpu_time_ms * count_executions),
    avg_logical_io_reads_mb float NULL,
    last_logical_io_reads_mb bigint NOT NULL,
    min_logical_io_reads_mb bigint NOT NULL,
    max_logical_io_reads_mb bigint NOT NULL,
    total_logical_io_reads_mb AS
        (avg_logical_io_reads_mb * count_executions),
    avg_logical_io_writes_mb float NULL,
    last_logical_io_writes_mb bigint NOT NULL,
    min_logical_io_writes_mb bigint NOT NULL,
    max_logical_io_writes_mb bigint NOT NULL,
    total_logical_io_writes_mb AS
        (avg_logical_io_writes_mb * count_executions),
    avg_physical_io_reads_mb float NULL,
    last_physical_io_reads_mb bigint NOT NULL,
    min_physical_io_reads_mb bigint NOT NULL,
    max_physical_io_reads_mb bigint NOT NULL,
    total_physical_io_reads_mb AS
        (avg_physical_io_reads_mb * count_executions),
    avg_clr_time_ms float NULL,
    last_clr_time_ms bigint NOT NULL,
    min_clr_time_ms bigint NOT NULL,
    max_clr_time_ms bigint NOT NULL,
    total_clr_time_ms AS
        (avg_clr_time_ms * count_executions),
    last_dop bigint NOT NULL,
    min_dop bigint NOT NULL,
    max_dop bigint NOT NULL,
    avg_query_max_used_memory_mb float NULL,
    last_query_max_used_memory_mb bigint NOT NULL,
    min_query_max_used_memory_mb bigint NOT NULL,
    max_query_max_used_memory_mb bigint NOT NULL,
    total_query_max_used_memory_mb AS
        (avg_query_max_used_memory_mb * count_executions),
    avg_rowcount float NULL,
    last_rowcount bigint NOT NULL,
    min_rowcount bigint NOT NULL,
    max_rowcount bigint NOT NULL,
    total_rowcount AS
        (avg_rowcount * count_executions),
    avg_num_physical_io_reads_mb float NULL,
    last_num_physical_io_reads_mb bigint NULL,
    min_num_physical_io_reads_mb bigint NULL,
    max_num_physical_io_reads_mb bigint NULL,
    total_num_physical_io_reads_mb AS
        (avg_num_physical_io_reads_mb * count_executions),
    avg_log_bytes_used_mb float NULL,
    last_log_bytes_used_mb bigint NULL,
    min_log_bytes_used_mb bigint NULL,
    max_log_bytes_used_mb bigint NULL,
    total_log_bytes_used_mb AS
        (avg_log_bytes_used_mb * count_executions),
    avg_tempdb_space_used_mb float NULL,
    last_tempdb_space_used_mb bigint NULL,
    min_tempdb_space_used_mb bigint NULL,
    max_tempdb_space_used_mb bigint NULL,
    total_tempdb_space_used_mb AS
        (avg_tempdb_space_used_mb * count_executions),
    context_settings nvarchar(256) NULL
);

/*
Wait Stats, When Available (2017+)
*/
CREATE TABLE
    #query_store_wait_stats
(
    database_id int NOT NULL,
    plan_id bigint NOT NULL,
    wait_category_desc nvarchar(60) NOT NULL,
    total_query_wait_time_ms bigint NOT NULL,
    avg_query_wait_time_ms float NULL,
    last_query_wait_time_ms bigint NOT NULL,
    min_query_wait_time_ms bigint NOT NULL,
    max_query_wait_time_ms bigint NOT NULL
);

/*
Context is everything
*/
CREATE TABLE
    #query_context_settings
(
    database_id int NOT NULL,
    context_settings_id bigint NOT NULL,
    set_options varbinary(8) NULL,
    language_id smallint NOT NULL,
    date_format smallint NOT NULL,
    date_first tinyint NOT NULL,
    status varbinary(2) NULL,
    required_cursor_options int NOT NULL,
    acceptable_cursor_options int NOT NULL,
    merge_action_type smallint NOT NULL,
    default_schema_id int NOT NULL,
    is_replication_specific bit NOT NULL,
    is_contained varbinary(1) NULL
);

/*
Feed me Seymour
*/
CREATE TABLE
    #query_store_plan_feedback
(
    database_id int NOT NULL,
    plan_feedback_id bigint,
    plan_id bigint,
    feature_desc nvarchar(120),
    feedback_data nvarchar(MAX),
    state_desc nvarchar(120),
    create_time datetimeoffset(7),
    last_updated_time datetimeoffset(7)
);

/*
America's Most Hinted
*/
CREATE TABLE
    #query_store_query_hints
(
    database_id int NOT NULL,
    query_hint_id bigint,
    query_id bigint,
    query_hint_text nvarchar(MAX),
    last_query_hint_failure_reason_desc nvarchar(256),
    query_hint_failure_count bigint,
    source_desc nvarchar(256)
);

/*
Variant? Deviant? You decide!
*/
CREATE TABLE
    #query_store_query_variant
(
    database_id int NOT NULL,
    query_variant_query_id bigint,
    parent_query_id bigint,
    dispatcher_plan_id bigint
);

/*
Replicants
*/
CREATE TABLE
    #query_store_replicas
(
    database_id int NOT NULL,
    replica_group_id bigint,
    role_type smallint,
    replica_name nvarchar(1288)
);

/*
Location, location, location
*/
CREATE TABLE
    #query_store_plan_forcing_locations
(
    database_id int NOT NULL,
    plan_forcing_location_id bigint,
    query_id bigint,
    plan_id bigint,
    replica_group_id bigint
);

/*
Trouble Loves Me
*/
CREATE TABLE
    #troubleshoot_performance
(
    id bigint IDENTITY,
    current_table nvarchar(100),
    start_time datetime,
    end_time datetime,
    runtime_ms AS
        FORMAT
        (
            DATEDIFF
            (
                MILLISECOND,
                start_time,
                end_time
            ),
            'N0'
        )
);

/*GET ALL THOSE DATABASES*/
CREATE TABLE
    #databases
(
    database_name sysname PRIMARY KEY
);

/*
Try to be helpful by subbing in a database name if null
*/
IF
  (
      @database_name IS NULL
      AND LOWER(DB_NAME())
          NOT IN
          (
              N'master',
              N'model',
              N'msdb',
              N'tempdb',
              N'dbatools',
              N'dbadmin',
              N'dbmaintenance',
              N'rdsadmin',
              N'other_memes'
          )
      AND @get_all_databases = 0
  )
BEGIN
    SELECT
        @database_name =
            DB_NAME();
END;

/*
Variables for the variable gods
*/
DECLARE
    @azure bit,
    @engine int,
    @product_version int,
    @database_id int,
    @database_name_quoted sysname,
    @procedure_name_quoted sysname,
    @collation sysname,
    @new bit,
    @sql nvarchar(MAX),
    @isolation_level nvarchar(MAX),
    @parameters nvarchar(4000),
    @plans_top bigint,
    @queries_top bigint,
    @nc10 nvarchar(2),
    @where_clause nvarchar(MAX),
    @query_text_search_original_value nvarchar(4000),
    @procedure_exists bit,
    @query_store_exists bit,
    @query_store_trouble bit,
    @query_store_waits_enabled bit,
    @sql_2022_views bit,
    @ags_present bit,
    @string_split_ints nvarchar(1500),
    @string_split_strings nvarchar(1500),
    @current_table nvarchar(100),
    @troubleshoot_insert nvarchar(MAX),
    @troubleshoot_update nvarchar(MAX),
    @troubleshoot_info nvarchar(MAX),
    @rc bigint,
    @em tinyint,
    @fo tinyint,
    @start_date_original datetimeoffset(7),
    @end_date_original datetimeoffset(7),
    @utc_minutes_difference bigint,
    @utc_minutes_original bigint,
    @df integer,
    @work_start_utc time(0),
    @work_end_utc time(0);

/*
In cases where we are escaping @query_text_search and
looping over multiple databases, we need to make sure
to not escape the string more than once.

The solution is to reset to the original value each loop.
This therefore needs to be done before the cursor.
*/
IF
(
    @get_all_databases = 1
AND @escape_brackets = 1
)
BEGIN
    SELECT
         @query_text_search_original_value = @query_text_search;
END;

/*
This section is in a cursor whether we
hit one database, or multiple

I do all the variable assignment in the
cursor block because some of them
are assigned for the specific database
that is currently being looked at
*/

IF
(
SELECT
    CONVERT
    (
        sysname,
        SERVERPROPERTY('EngineEdition')
    )
) IN (5, 8)
BEGIN
    INSERT INTO
        #databases WITH(TABLOCK)
    (
        database_name
    )
    SELECT
        database_name =
            ISNULL(@database_name, DB_NAME())
    WHERE @get_all_databases = 0

    UNION ALL

    SELECT
        database_name =
            d.name
    FROM sys.databases AS d
    WHERE @get_all_databases = 1
    AND   d.is_query_store_on = 1
    AND   d.database_id > 4
    AND   d.state = 0
    AND   d.is_in_standby = 0
    AND   d.is_read_only = 0
    OPTION(RECOMPILE);
END
ELSE
BEGIN
    INSERT
        #databases WITH(TABLOCK)
    (
        database_name
    )
    SELECT
        database_name =
            ISNULL(@database_name, DB_NAME())
    WHERE @get_all_databases = 0

    UNION ALL

    SELECT
        database_name =
            d.name
    FROM sys.databases AS d
    WHERE @get_all_databases = 1
    AND   d.is_query_store_on = 1
    AND   d.database_id > 4
    AND   d.state = 0
    AND   d.is_in_standby = 0
    AND   d.is_read_only = 0
    AND   NOT EXISTS
    (
        SELECT
            1/0
        FROM sys.dm_hadr_availability_replica_states AS s
        JOIN sys.availability_databases_cluster AS c
          ON  s.group_id = c.group_id
          AND d.name = c.database_name
        WHERE s.is_local <> 1
        AND   s.role_desc <> N'PRIMARY'
        AND   DATABASEPROPERTYEX(c.database_name, N'Updateability') <> N'READ_WRITE'
    )
    OPTION(RECOMPILE);
END;

DECLARE
    database_cursor CURSOR
    LOCAL
    SCROLL
    DYNAMIC
    READ_ONLY
FOR
SELECT
    d.database_name
FROM #databases AS d;

OPEN database_cursor;

FETCH FIRST
FROM database_cursor
INTO @database_name;

WHILE @@FETCH_STATUS = 0
BEGIN
/*
Some variable assignment, because why not?
*/
IF @debug = 1
BEGIN
    RAISERROR('Starting analysis for database %s', 0, 1, @database_name) WITH NOWAIT;
END;

SELECT
    @azure =
        CASE
            WHEN
                CONVERT
                (
                    sysname,
                    SERVERPROPERTY('EDITION')
                ) = N'SQL Azure'
            THEN 1
            ELSE 0
        END,
    @engine =
        CONVERT
        (
            int,
            SERVERPROPERTY('ENGINEEDITION')
        ),
    @product_version =
        CONVERT
        (
            int,
            PARSENAME
            (
                CONVERT
                (
                    sysname,
                    SERVERPROPERTY('PRODUCTVERSION')
                ),
                4
            )
        ),
    @database_id =
        DB_ID(@database_name),
    @database_name_quoted =
        QUOTENAME(@database_name),
    @procedure_name_quoted =
         QUOTENAME(@database_name) +
         N'.' +
         QUOTENAME
         (
             ISNULL
             (
                 @procedure_schema,
                 N'dbo'
             )
         ) +
         N'.' +
         QUOTENAME(@procedure_name),
    @collation =
        CONVERT
        (
            sysname,
            DATABASEPROPERTYEX
            (
                @database_name,
                'Collation'
            )
        ),
    @new = 0,
    @sql = N'',
    @isolation_level =
        N'
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;',
    @parameters =
        N'@top bigint,
          @start_date datetimeoffset(7),
          @end_date datetimeoffset(7),
          @execution_count bigint,
          @duration_ms bigint,
          @execution_type_desc nvarchar(60),
          @database_id int,
          @queries_top bigint,
          @work_start_utc time(0),
          @work_end_utc time(0)',
    @plans_top =
        9223372036854775807,
    @queries_top =
        9223372036854775807,
    @nc10 = NCHAR(10),
    @where_clause = N'',
    @query_text_search =
        CASE
            WHEN @get_all_databases = 1 AND @escape_brackets = 1
            THEN @query_text_search_original_value
            ELSE @query_text_search
         END,
    @procedure_exists = 0,
    @query_store_exists = 0,
    @query_store_trouble = 0,
    @query_store_waits_enabled = 0,
    @sql_2022_views = 0,
    @ags_present = 0,
    @current_table = N'',
    @string_split_ints = N'
        SELECT DISTINCT
            ids =
                LTRIM
                (
                    RTRIM
                    (
                        ids.ids
                    )
                )
        FROM
        (
            SELECT
                ids =
                    x.x.value
                        (
                            ''(./text())[1]'',
                            ''bigint''
                        )
            FROM
            (
                SELECT
                    ids =
                        CONVERT
                        (
                            xml,
                            ''<x>'' +
                            REPLACE
                            (
                                REPLACE
                                (
                                    @ids,
                                    '','',
                                    ''</x><x>''
                                ),
                                '' '',
                                ''''
                            ) +
                            ''</x>''
                        ).query(''.'')
            ) AS ids
                CROSS APPLY ids.nodes(''x'') AS x (x)
        ) AS ids
        OPTION(RECOMPILE);',
    @string_split_strings = N'
        SELECT DISTINCT
            ids =
                LTRIM
                (
                    RTRIM
                    (
                        ids.ids
                    )
                )
        FROM
        (
            SELECT
                ids =
                    x.x.value
                        (
                            ''(./text())[1]'',
                            ''varchar(131)''
                        )
            FROM
            (
                SELECT
                    ids =
                        CONVERT
                        (
                            xml,
                            ''<x>'' +
                            REPLACE
                            (
                                REPLACE
                                (
                                    @ids,
                                    '','',
                                    ''</x><x>''
                                ),
                                '' '',
                                ''''
                            ) +
                            ''</x>''
                        ).query(''.'')
            ) AS ids
                CROSS APPLY ids.nodes(''x'') AS x (x)
        ) AS ids
        OPTION(RECOMPILE);',
    @troubleshoot_insert = N'
        INSERT
            #troubleshoot_performance WITH(TABLOCK)
        (
            current_table,
            start_time
        )
        VALUES
        (
            @current_table,
            GETDATE()
        )
        OPTION(RECOMPILE);',
    @troubleshoot_update = N'
        UPDATE
            tp
        SET
            tp.end_time = GETDATE()
        FROM #troubleshoot_performance AS tp
        WHERE tp.current_table = @current_table
        OPTION(RECOMPILE);',
    @troubleshoot_info = N'
        SELECT
            (
                SELECT
                    runtime_ms =
                        tp.runtime_ms,
                    current_table =
                        tp.current_table,
                    query_length =
                        FORMAT(LEN(@sql), ''N0''),
                    ''processing-instruction(statement_text)'' =
                        @sql
                FROM #troubleshoot_performance AS tp
                WHERE tp.current_table = @current_table
                FOR XML
                    PATH(N''''),
                    TYPE
            ).query(''.[1]'') AS current_query
        OPTION(RECOMPILE);',
    @rc = 0,
    @em = @expert_mode,
    @fo = @format_output,
    @start_date_original =
        ISNULL
        (
            @start_date,
            DATEADD
            (
                DAY,
                -7,
                DATEDIFF
                (
                    DAY,
                    '19000101',
                    SYSUTCDATETIME()
                )
            )
        ),
    @end_date_original =
        ISNULL
        (
            @end_date,
            DATEADD
            (
                DAY,
                1,
                DATEADD
                (
                    MINUTE,
                    0,
                    DATEDIFF
                    (
                        DAY,
                        '19000101',
                        SYSUTCDATETIME()
                    )
                )
            )
        ),
    @utc_minutes_difference =
        DATEDIFF
        (
            MINUTE,
            SYSDATETIME(),
            SYSUTCDATETIME()
        ),
    @utc_minutes_original =
        DATEDIFF
        (
            MINUTE,
            SYSUTCDATETIME(),
            SYSDATETIME()
        ),
    @df = @@DATEFIRST,
    @work_start_utc = @work_start,
    @work_end_utc = @work_end;

/*
Some parameters can't be NULL,
and some shouldn't be empty strings
*/
SELECT
    @sort_order =
        ISNULL(@sort_order, 'cpu'),
    @top =
        ISNULL(@top, 10),
    @expert_mode =
        ISNULL(@expert_mode, 0),
    @procedure_schema =
        NULLIF(@procedure_schema, ''),
    @procedure_name =
        NULLIF(@procedure_name, ''),
    @include_plan_ids =
        NULLIF(@include_plan_ids, ''),
    @include_query_ids =
        NULLIF(@include_query_ids, ''),
    @ignore_plan_ids =
        NULLIF(@ignore_plan_ids, ''),
    @ignore_query_ids =
        NULLIF(@ignore_query_ids, ''),
    @include_query_hashes =
        NULLIF(@include_query_hashes, ''),
    @include_plan_hashes =
        NULLIF(@include_plan_hashes, ''),
    @include_sql_handles =
        NULLIF(@include_sql_handles, ''),
    @ignore_query_hashes =
        NULLIF(@ignore_query_hashes, ''),
    @ignore_plan_hashes =
        NULLIF(@ignore_plan_hashes, ''),
    @ignore_sql_handles =
        NULLIF(@ignore_sql_handles, ''),
    @only_queries_with_hints =
        ISNULL(@only_queries_with_hints, 0),
    @only_queries_with_feedback =
        ISNULL(@only_queries_with_feedback, 0),
    @only_queries_with_variants =
        ISNULL(@only_queries_with_variants, 0),
    @only_queries_with_forced_plans =
        ISNULL(@only_queries_with_forced_plans, 0),
    @only_queries_with_forced_plan_failures =
        ISNULL(@only_queries_with_forced_plan_failures, 0),
    @wait_filter =
        NULLIF(@wait_filter, ''),
    @format_output =
        ISNULL(@format_output, 1),
    @help =
        ISNULL(@help, 0),
    @debug =
        ISNULL(@debug, 0),
    @troubleshoot_performance =
        ISNULL(@troubleshoot_performance, 0),
    @get_all_databases =
        ISNULL(@get_all_databases, 0),
    @workdays =
        ISNULL(@workdays, 0),
    /*
        doing start and end date last because they're more complicated
        if start or end date is null,
    */
    @start_date =
        CASE
            WHEN @start_date IS NULL
            THEN
                DATEADD
                (
                    DAY,
                    -7,
                    DATEDIFF
                    (
                        DAY,
                        '19000101',
                        SYSUTCDATETIME()
                    )
                )
            WHEN @start_date IS NOT NULL
            THEN
                DATEADD
                (
                    MINUTE,
                    @utc_minutes_difference,
                    @start_date
                )
        END,
    @end_date =
        CASE
            WHEN @end_date IS NULL
            THEN
                DATEADD
                (
                    DAY,
                    1,
                    DATEADD
                    (
                        MINUTE,
                        0,
                        DATEDIFF
                        (
                            DAY,
                            '19000101',
                            SYSUTCDATETIME()
                        )
                    )
                )
            WHEN @end_date IS NOT NULL
            THEN
                DATEADD
                (
                    MINUTE,
                    @utc_minutes_difference,
                    @end_date
                )
        END;

/*
I need to tweak this so the WHERE clause on the last execution column
works correctly as >= @start_date and < @end_date, otherwise there are no results
*/
IF @start_date >= @end_date
BEGIN
    SELECT
        @end_date =
            DATEADD
            (
                DAY,
                7,
                @start_date
            ),
        @end_date_original =
            DATEADD
            (
                DAY,
                1,
                @start_date_original
            );
END;

/*
Let's make sure things will work
*/

/*
Database are you there?
*/
IF
(
   @database_id IS NULL
OR @collation IS NULL
)
BEGIN
    RAISERROR('Database %s does not exist', 10, 1, @database_name) WITH NOWAIT;

    IF @get_all_databases = 0
    BEGIN
        RETURN;
    END;
END;

/*
Database what are you?
*/
IF
(
    @azure = 1
AND @engine NOT IN (5, 8)
)
BEGIN
    RAISERROR('Not all Azure offerings are supported, please try avoiding memes', 11, 1) WITH NOWAIT;
    RETURN;
END;

/*
Database are you compatible?
*/
IF
(
    @azure = 1
    AND EXISTS
        (
            SELECT
                1/0
             FROM sys.databases AS d
             WHERE d.database_id = @database_id
             AND   d.compatibility_level < 130
        )
)
BEGIN
    RAISERROR('Azure databases in compatibility levels under 130 are not supported', 11, 1) WITH NOWAIT;
    RETURN;
END;

/*
Sometimes sys.databases will report Query Store being on, but it's really not
*/
SELECT
    @current_table = 'checking query store existence',
    @sql = @isolation_level;

IF @troubleshoot_performance = 1
BEGIN

    EXEC sys.sp_executesql
        @troubleshoot_insert,
      N'@current_table nvarchar(100)',
        @current_table;

    SET STATISTICS XML ON;
END;

SELECT
    @sql += N'
SELECT
    @query_store_exists =
        CASE
            WHEN EXISTS
                 (
                     SELECT
                         1/0
                     FROM ' + @database_name_quoted + N'.sys.database_query_store_options AS dqso
                     WHERE
                     (
                          dqso.actual_state = 0
                       OR dqso.actual_state IS NULL
                     )
                 )
            OR   NOT EXISTS
                 (
                     SELECT
                         1/0
                     FROM ' + @database_name_quoted + N'.sys.database_query_store_options AS dqso
                 )
            THEN 0
            ELSE 1
        END
OPTION(RECOMPILE);' + @nc10;

IF @debug = 1
BEGIN
    PRINT LEN(@sql);
    PRINT @sql;
END;

EXEC sys.sp_executesql
    @sql,
  N'@query_store_exists bit OUTPUT',
    @query_store_exists OUTPUT;

IF @troubleshoot_performance = 1
BEGIN
    SET STATISTICS XML OFF;

    EXEC sys.sp_executesql
        @troubleshoot_update,
      N'@current_table nvarchar(100)',
        @current_table;

    EXEC sys.sp_executesql
        @troubleshoot_info,
      N'@sql nvarchar(max),
        @current_table nvarchar(100)',
        @sql,
        @current_table;
END;

IF @query_store_exists = 0
BEGIN
    RAISERROR('Query Store doesn''t seem to be enabled for database: %s', 10, 1, @database_name) WITH NOWAIT;

    IF @get_all_databases = 0
    BEGIN
        RETURN;
    END;
END;

/*
If Query Store is enabled, but in read only mode for some reason, return some information about why
*/
SELECT
    @current_table = 'checking for query store trouble',
    @sql = @isolation_level;

IF @troubleshoot_performance = 1
BEGIN

    EXEC sys.sp_executesql
        @troubleshoot_insert,
      N'@current_table nvarchar(100)',
        @current_table;

    SET STATISTICS XML ON;
END;

SELECT
    @sql += N'
SELECT
    database_id =
        @database_id,
    desired_state_desc,
    actual_state_desc,
    readonly_reason =
        CASE dqso.readonly_reason
             WHEN 0
             THEN ''None''
             WHEN 2
             THEN ''Database in single user mode''
             WHEN 4
             THEN ''Database is in emergency mode''
             WHEN 8
             THEN ''Database is AG secondary''
             WHEN 65536
             THEN ''Reached max size: '' +
                  FORMAT(dqso.current_storage_size_mb, ''N0'') +
                  '' of '' +
                  FORMAT(dqso.max_storage_size_mb, ''N0'') +
                  ''.''
             WHEN 131072
             THEN ''The number of different statements in Query Store has reached the internal memory limit''
             WHEN 262144
             THEN ''Size of in-memory items waiting to be persisted on disk has reached the internal memory limit''
             WHEN 524288
             THEN ''Database has reached disk size limit''
             ELSE ''WOAH''
        END,
    current_storage_size_mb,
    flush_interval_seconds,
    interval_length_minutes,
    max_storage_size_mb,
    stale_query_threshold_days,
    max_plans_per_query,
    query_capture_mode_desc,
    size_based_cleanup_mode_desc
FROM ' + @database_name_quoted + N'.sys.database_query_store_options AS dqso
WHERE
(
     dqso.desired_state <> 4
  OR dqso.readonly_reason <> 8
)
AND
(
      dqso.desired_state = 1
   OR dqso.actual_state IN (1, 3)
   OR dqso.desired_state <> dqso.actual_state
)
OPTION(RECOMPILE);' + @nc10;

IF @debug = 1
BEGIN
    PRINT LEN(@sql);
    PRINT @sql;
END;

INSERT
    #query_store_trouble WITH (TABLOCK)
(
    database_id,
    desired_state_desc,
    actual_state_desc,
    readonly_reason,
    current_storage_size_mb,
    flush_interval_seconds,
    interval_length_minutes,
    max_storage_size_mb,
    stale_query_threshold_days,
    max_plans_per_query,
    query_capture_mode_desc,
    size_based_cleanup_mode_desc
)
EXEC sys.sp_executesql
    @sql,
  N'@database_id integer',
    @database_id;

IF @@ROWCOUNT > 0
BEGIN
    SELECT
        @query_store_trouble = 1;
END;

IF @troubleshoot_performance = 1
BEGIN
    SET STATISTICS XML OFF;

    EXEC sys.sp_executesql
        @troubleshoot_update,
      N'@current_table nvarchar(100)',
        @current_table;

    EXEC sys.sp_executesql
        @troubleshoot_info,
      N'@sql nvarchar(max),
        @current_table nvarchar(100)',
        @sql,
        @current_table;
END;

IF @query_store_trouble = 1
BEGIN
    SELECT
        query_store_trouble =
             'Query Store may be in a disagreeable state',
        database_name =
            DB_NAME(qst.database_id),
        qst.desired_state_desc,
        qst.actual_state_desc,
        qst.readonly_reason,
        qst.current_storage_size_mb,
        qst.flush_interval_seconds,
        qst.interval_length_minutes,
        qst.max_storage_size_mb,
        qst.stale_query_threshold_days,
        qst.max_plans_per_query,
        qst.query_capture_mode_desc,
        qst.size_based_cleanup_mode_desc
    FROM #query_store_trouble AS qst
    OPTION(RECOMPILE);
END;

/*
If you specified a procedure name, we need to figure out if there are any plans for it available
*/
IF @procedure_name IS NOT NULL
BEGIN
    SELECT
        @current_table = 'checking procedure existence',
        @sql = @isolation_level;

    IF @troubleshoot_performance = 1
    BEGIN
        EXEC sys.sp_executesql
            @troubleshoot_insert,
          N'@current_table nvarchar(100)',
            @current_table;

        SET STATISTICS XML ON;
    END;

    SELECT
        @sql += N'
SELECT
    @procedure_exists =
        CASE
            WHEN EXISTS
                 (
                     SELECT
                         1/0
                     FROM ' + @database_name_quoted + N'.sys.query_store_query AS qsq
                     WHERE qsq.object_id = OBJECT_ID(@procedure_name_quoted)
                 )
            THEN 1
            ELSE 0
        END
OPTION(RECOMPILE);' + @nc10;

    IF @debug = 1
    BEGIN
        PRINT LEN(@sql);
        PRINT @sql;
    END;

    EXEC sys.sp_executesql
        @sql,
      N'@procedure_exists bit OUTPUT,
        @procedure_name_quoted sysname',
        @procedure_exists OUTPUT,
        @procedure_name_quoted;

    IF @troubleshoot_performance = 1
    BEGIN
        SET STATISTICS XML OFF;

        EXEC sys.sp_executesql
            @troubleshoot_update,
          N'@current_table nvarchar(100)',
            @current_table;

        EXEC sys.sp_executesql
            @troubleshoot_info,
          N'@sql nvarchar(max),
            @current_table nvarchar(100)',
            @sql,
            @current_table;
    END;

    IF
    (
        @procedure_exists = 0
    AND @get_all_databases = 1
    )
    BEGIN
        RAISERROR('The stored procedure %s does not appear to have any entries in Query Store for database %s
Check that you spelled everything correctly and you''re in the right database
We will skip this database and continue',
                       10, 1, @procedure_name, @database_name) WITH NOWAIT;
        FETCH NEXT
        FROM database_cursor
        INTO @database_name;

        CONTINUE;
    END;

    IF
    (
        @procedure_exists = 0
    AND @get_all_databases = 0
    )
        BEGIN
            RAISERROR('The stored procedure %s does not appear to have any entries in Query Store for database %s
Check that you spelled everything correctly and you''re in the right database',
                       10, 1, @procedure_name, @database_name) WITH NOWAIT;

        IF @get_all_databases = 0
        BEGIN
            RETURN;
        END;
    END;
END; /*End procedure existence checking*/

/*
Some things are version dependent.
Normally, I'd check for object existence, but the documentation
leads me to believe that certain things won't be back-ported,
like the wait stats DMV, and tempdb spills columns
*/
IF
(
   @product_version > 13
OR @engine IN (5, 8)
)
BEGIN
   SELECT
       @new = 1;
END;

/*
Validate Sort Order
*/
IF @sort_order NOT IN
   (
       'cpu',
       'logical reads',
       'physical reads',
       'writes',
       'duration',
       'memory',
       'tempdb',
       'executions',
       'recent'
   )
BEGIN
   RAISERROR('The sort order (%s) you chose is so out of this world that I''m using cpu instead', 10, 1, @sort_order) WITH NOWAIT;

   SELECT
       @sort_order = 'cpu';
END;

/*
These columns are only available in 2017+
*/
IF
(
    @sort_order = 'tempdb'
AND @new = 0
)
BEGIN
   RAISERROR('The sort order (%s) you chose is invalid in product version %i, reverting to cpu', 10, 1, @sort_order, @product_version) WITH NOWAIT;

   SELECT
       @sort_order = N'cpu';
END;

/*
See if our cool new 2022 views exist.
May have to tweak this if views aren't present in some cloudy situations.
*/
SELECT
    @sql_2022_views =
        CASE
            WHEN COUNT_BIG(*) = 5
            THEN 1
            ELSE 0
        END
FROM sys.all_objects AS ao
WHERE ao.name IN
      (
          N'query_store_plan_feedback',
          N'query_store_query_hints',
          N'query_store_query_variant',
          N'query_store_replicas',
          N'query_store_plan_forcing_locations'
      )
OPTION(RECOMPILE);

/*
Hints aren't in Query Store until 2022, so we can't do that on television
*/
IF
(
    (
         @only_queries_with_hints    = 1
      OR @only_queries_with_feedback = 1
      OR @only_queries_with_variants = 1
    )
AND @sql_2022_views = 0
)
BEGIN
    RAISERROR('Query Store hints, feedback, and variants are not available prior to SQL Server 2022', 10, 1) WITH NOWAIT;

    IF @get_all_databases = 0
    BEGIN
        RETURN;
    END;
END;

/*
Wait stats aren't in Query Store until 2017, so we can't do that on television
*/
IF
(
    @wait_filter IS NOT NULL
AND @new = 0
)
BEGIN
    RAISERROR('Query Store wait stats are not available prior to SQL Server 2017', 10, 1) WITH NOWAIT;

    IF @get_all_databases = 0
    BEGIN
        RETURN;
    END;
END;

/*
Make sure the wait filter is valid
*/
IF
(
    @new = 1
AND @wait_filter NOT IN
    (
        'cpu',
        'lock',
        'locks',
        'latch',
        'latches',
        'buffer latch',
        'buffer latches',
        'buffer io',
        'log',
        'log io',
        'network',
        'network io',
        'parallel',
        'parallelism',
        'memory'
    )
)
BEGIN
    RAISERROR('The wait category (%s) you chose is invalid', 10, 1, @wait_filter) WITH NOWAIT;

    IF @get_all_databases = 0
    BEGIN
        RETURN;
    END;
END;

/*
One last check: wait stat capture can be enabled or disabled in settings
*/
IF
(
   @wait_filter IS NOT NULL
OR @new = 1
)
BEGIN
    SELECT
        @current_table = 'checking query store waits are enabled',
        @sql = @isolation_level;

    IF @troubleshoot_performance = 1
    BEGIN

        EXEC sys.sp_executesql
            @troubleshoot_insert,
          N'@current_table nvarchar(100)',
            @current_table;

        SET STATISTICS XML ON;
    END;

    SELECT
        @sql += N'
SELECT
    @query_store_waits_enabled =
        CASE
            WHEN EXISTS
                 (
                     SELECT
                         1/0
                     FROM ' + @database_name_quoted + N'.sys.database_query_store_options AS dqso
                     WHERE dqso.wait_stats_capture_mode = 1
                 )
            THEN 1
            ELSE 0
        END
OPTION(RECOMPILE);' + @nc10;

    IF @debug = 1
    BEGIN
        PRINT LEN(@sql);
        PRINT @sql;
    END;

    EXEC sys.sp_executesql
        @sql,
      N'@query_store_waits_enabled bit OUTPUT',
        @query_store_waits_enabled OUTPUT;

    IF @troubleshoot_performance = 1
    BEGIN
        SET STATISTICS XML OFF;

        EXEC sys.sp_executesql
            @troubleshoot_update,
          N'@current_table nvarchar(100)',
            @current_table;

        EXEC sys.sp_executesql
            @troubleshoot_info,
          N'@sql nvarchar(max),
            @current_table nvarchar(100)',
            @sql,
            @current_table;
    END;

    IF @query_store_waits_enabled = 0
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Query Store wait stats are not enabled for database %s', 10, 1, @database_name_quoted) WITH NOWAIT;
        END
    END;
END; /*End wait stats checks*/

/*Check that the selected @timezone is valid*/
IF @timezone IS NOT NULL
BEGIN
    IF NOT EXISTS
       (
           SELECT
               1/0
           FROM sys.time_zone_info AS tzi
           WHERE tzi.name = @timezone
       )
       BEGIN
           RAISERROR('The time zone you chose (%s) is not valid. Please check sys.time_zone_info for a valid list.', 10, 1, @timezone) WITH NOWAIT;
           RETURN;
       END;
END;

/*
See if AGs are a thing so we can skip the checks for replica stuff
*/
IF (@azure = 1)
BEGIN
    SELECT
        @ags_present = 0;
END;
ELSE
BEGIN
    IF
    (
        SELECT
            CONVERT
            (
                sysname,
                SERVERPROPERTY('EngineEdition')
            )
    ) NOT IN (5, 8)
    BEGIN
        SELECT
            @ags_present =
                CASE
                    WHEN EXISTS
                         (
                             SELECT
                                 1/0
                             FROM sys.availability_groups AS ag
                         )
                    THEN 1
                    ELSE 0
                END
        OPTION(RECOMPILE);
    END
END;

/*
Get filters ready, or whatever
We're only going to pull some stuff from runtime stats and plans
*/
IF (@start_date <= @end_date)
BEGIN
    SELECT
        @where_clause += N'AND   qsrs.last_execution_time >= @start_date
AND   qsrs.last_execution_time <  @end_date' + @nc10;
END;

/*Other filters*/
IF @execution_count IS NOT NULL
BEGIN
    SELECT
        @where_clause += N'AND   qsrs.count_executions >= @execution_count' + @nc10;
END;

IF @duration_ms IS NOT NULL
BEGIN
    SELECT
        @where_clause += N'AND   qsrs.avg_duration >= (@duration_ms * 1000.)' + @nc10;
END;

IF @execution_type_desc IS NOT NULL
BEGIN
    SELECT
        @where_clause += N'AND   qsrs.execution_type_desc = @execution_type_desc' + @nc10;
END;

IF @workdays = 1
BEGIN
    IF  @work_start_utc IS NULL
    AND @work_end_utc   IS NULL
    BEGIN
         SELECT
             @work_start_utc = '09:00',
             @work_end_utc = '17:00';
    END;

    IF  @work_start_utc IS NOT NULL
    AND @work_end_utc   IS NULL
    BEGIN
        SELECT
            @work_end_utc =
                DATEADD
                (
                    HOUR,
                    8,
                    @work_start_utc
                );
    END;

    IF  @work_start_utc IS NULL
    AND @work_end_utc   IS NOT NULL
    BEGIN
        SELECT
            @work_start_utc =
                DATEADD
                (
                    HOUR,
                    -8,
                    @work_end_utc
                );
    END;

    SELECT
        @work_start_utc =
            DATEADD
            (
                MINUTE,
                @utc_minutes_difference,
                @work_start_utc
            ),
        @work_end_utc =
            DATEADD
            (
                MINUTE,
                @utc_minutes_difference,
                @work_end_utc
            );

    IF @df = 1
    BEGIN
       SELECT
           @where_clause += N'AND   DATEPART(WEEKDAY, qsrs.last_execution_time) BETWEEN 1 AND 5' + @nc10;
    END;/*df 1*/

    IF @df = 7
    BEGIN
       SELECT
           @where_clause += N'AND   DATEPART(WEEKDAY, qsrs.last_execution_time) BETWEEN 2 AND 6' + @nc10;
    END;/*df 7*/

    IF  @work_start_utc IS NOT NULL
    AND @work_end_utc IS NOT NULL
    BEGIN
        /*
          depending on local TZ, work time might span midnight UTC;
          account for that by splitting the interval into before/after midnight.
          for example:
              [09:00 - 17:00] PST
           =  [17:00 - 01:00] UTC
           =  [17:00 - 00:00) + [00:00 - 01:00] UTC

          NB: because we don't have the benefit of the context of what day midnight
          is occurring on, we have to rely on the behavior from the documentation of
          the time DT of higher to lower precision resulting in truncation to split
          the interval. i.e. 23:59:59.9999999 -> 23:59:59. which should make that
          value safe to use as the endpoint for our "before midnight" interval.
        */
        IF (@work_start_utc < @work_end_utc)
        SELECT
            @where_clause += N'AND   CONVERT(time(0), qsrs.last_execution_time) BETWEEN @work_start_utc AND @work_end_utc' + @nc10;
        ELSE
        SELECT
            @where_clause += N'AND
(' + @nc10 +
N'      CONVERT(time(0), qsrs.last_execution_time) BETWEEN @work_start_utc AND ''23:59:59'' ' + @nc10 +
N'   OR CONVERT(time(0), qsrs.last_execution_time) BETWEEN ''00:00:00'' AND @work_end_utc' + @nc10 +
N')' + @nc10;
    END; /*Work hours*/
END; /*Final end*/

/*
In this section we set up the filter if someone's searching for
a single stored procedure in Query Store.
*/
IF
(
    @procedure_name IS NOT NULL
AND @procedure_exists = 1
)
BEGIN
    SELECT
        @current_table = 'inserting #procedure_plans',
        @sql = @isolation_level;

    IF @troubleshoot_performance = 1
    BEGIN
        EXEC sys.sp_executesql
            @troubleshoot_insert,
          N'@current_table nvarchar(100)',
            @current_table;

        SET STATISTICS XML ON;
    END;

    SELECT
        @sql += N'
SELECT DISTINCT
    qsp.plan_id
FROM ' + @database_name_quoted + N'.sys.query_store_query AS qsq
JOIN ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
   ON qsq.query_id = qsp.query_id
WHERE qsq.object_id = OBJECT_ID(@procedure_name_quoted)
OPTION(RECOMPILE);' + @nc10;

    IF @debug = 1
    BEGIN
        PRINT LEN(@sql);
        PRINT @sql;
    END;

    INSERT
        #procedure_plans WITH(TABLOCK)
    (
        plan_id
    )
    EXEC sys.sp_executesql
        @sql,
      N'@procedure_name_quoted sysname',
        @procedure_name_quoted;

    IF @troubleshoot_performance = 1
    BEGIN
        SET STATISTICS XML OFF;

        EXEC sys.sp_executesql
            @troubleshoot_update,
          N'@current_table nvarchar(100)',
            @current_table;

        EXEC sys.sp_executesql
            @troubleshoot_info,
          N'@sql nvarchar(max),
            @current_table nvarchar(100)',
            @sql,
            @current_table;
    END;

    SELECT
        @where_clause += N'AND   EXISTS
        (
            SELECT
                1/0
            FROM #procedure_plans AS pp
            WHERE pp.plan_id = qsrs.plan_id
        )'  + @nc10;
END; /*End procedure filter table population*/


/*
In this section we set up the filter if someone's searching for
either ad hoc queries or queries from modules.
*/
IF LEN(@query_type) > 0
BEGIN
    SELECT
        @current_table = 'inserting #query_types',
        @sql = @isolation_level;

    IF @troubleshoot_performance = 1
    BEGIN
        EXEC sys.sp_executesql
            @troubleshoot_insert,
          N'@current_table nvarchar(100)',
            @current_table;

        SET STATISTICS XML ON;
    END;

    SELECT
        @sql += N'
SELECT DISTINCT
    qsp.plan_id
FROM ' + @database_name_quoted + N'.sys.query_store_query AS qsq
JOIN ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
  ON qsq.query_id = qsp.query_id
WHERE qsq.object_id ' +
CASE
    WHEN LOWER(@query_type) LIKE 'a%'
    THEN N'= 0'
    ELSE N'<> 0'
END
+ N'
OPTION(RECOMPILE);' + @nc10;

    IF @debug = 1
    BEGIN
        PRINT LEN(@sql);
        PRINT @sql;
    END;

    INSERT
        #query_types WITH(TABLOCK)
    (
        plan_id
    )
    EXEC sys.sp_executesql
        @sql;

    IF @troubleshoot_performance = 1
    BEGIN
        SET STATISTICS XML OFF;

        EXEC sys.sp_executesql
            @troubleshoot_update,
          N'@current_table nvarchar(100)',
            @current_table;

        EXEC sys.sp_executesql
            @troubleshoot_info,
          N'@sql nvarchar(max),
            @current_table nvarchar(100)',
            @sql,
            @current_table;
    END;

    SELECT
        @where_clause += N'AND   EXISTS
        (
            SELECT
                1/0
            FROM #query_types AS qt
            WHERE qt.plan_id = qsrs.plan_id
        )'  + @nc10;
END; /*End query type filter table population*/


/*
This section filters query or plan ids, both inclusive and exclusive
*/
IF
(
   @include_plan_ids  IS NOT NULL
OR @include_query_ids IS NOT NULL
OR @ignore_plan_ids   IS NOT NULL
OR @ignore_query_ids  IS NOT NULL
)
BEGIN
    IF @include_plan_ids IS NOT NULL
    BEGIN
        SELECT
            @include_plan_ids =
                REPLACE(REPLACE(REPLACE(REPLACE(
                    LTRIM(RTRIM(@include_plan_ids)),
                 CHAR(10), N''),  CHAR(13), N''),
                NCHAR(10), N''), NCHAR(13), N'');

        SELECT
            @current_table = 'inserting #include_plan_ids';

        INSERT
            #include_plan_ids WITH(TABLOCK)
        (
            plan_id
        )
        EXEC sys.sp_executesql
            @string_split_ints,
          N'@ids nvarchar(4000)',
            @include_plan_ids;

        SELECT
            @where_clause += N'AND   EXISTS
      (
         SELECT
            1/0
         FROM #include_plan_ids AS idi
         WHERE idi.plan_id = qsrs.plan_id
      )' + @nc10;
    END; /*End include plan ids*/

    IF @ignore_plan_ids IS NOT NULL
    BEGIN
        SELECT
            @ignore_plan_ids =
                REPLACE(REPLACE(REPLACE(REPLACE(
                    LTRIM(RTRIM(@ignore_plan_ids)),
                 CHAR(10), N''),  CHAR(13), N''),
                NCHAR(10), N''), NCHAR(13), N'');

        SELECT
            @current_table = 'inserting #ignore_plan_ids';

        INSERT
            #ignore_plan_ids WITH(TABLOCK)
        (
            plan_id
        )
        EXEC sys.sp_executesql
            @string_split_ints,
          N'@ids nvarchar(4000)',
            @ignore_plan_ids;

        SELECT
            @where_clause += N'AND   NOT EXISTS
      (
         SELECT
            1/0
         FROM #ignore_plan_ids AS idi
         WHERE idi.plan_id = qsrs.plan_id
      )' + @nc10;
    END; /*End ignore plan ids*/

    IF @include_query_ids IS NOT NULL
    BEGIN
        SELECT
            @include_query_ids =
                REPLACE(REPLACE(REPLACE(REPLACE(
                    LTRIM(RTRIM(@include_query_ids)),
                 CHAR(10), N''),  CHAR(13), N''),
                NCHAR(10), N''), NCHAR(13), N'');
        SELECT
            @current_table = 'inserting #include_query_ids',
            @sql = @isolation_level;

        INSERT
            #include_query_ids WITH(TABLOCK)
        (
            query_id
        )
        EXEC sys.sp_executesql
            @string_split_ints,
          N'@ids nvarchar(4000)',
            @include_query_ids;

        SELECT
            @current_table = 'inserting #include_plan_ids for included query ids';

        IF @troubleshoot_performance = 1
        BEGIN
            EXEC sys.sp_executesql
                @troubleshoot_insert,
              N'@current_table nvarchar(100)',
                @current_table;

            SET STATISTICS XML ON;
        END;

        SELECT
            @sql += N'
SELECT DISTINCT
    qsp.plan_id
FROM ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
WHERE EXISTS
      (
          SELECT
              1/0
          FROM #include_query_ids AS iqi
          WHERE iqi.query_id = qsp.query_id
      )
OPTION(RECOMPILE);' + @nc10;

        IF @debug = 1
        BEGIN
            PRINT LEN(@sql);
            PRINT @sql;
        END;

        INSERT
            #include_plan_ids
        (
            plan_id
        )
        EXEC sys.sp_executesql
            @sql;

        IF @troubleshoot_performance = 1
        BEGIN
            SET STATISTICS XML OFF;

            EXEC sys.sp_executesql
                @troubleshoot_update,
              N'@current_table nvarchar(100)',
                @current_table;

            EXEC sys.sp_executesql
                @troubleshoot_info,
              N'@sql nvarchar(max),
                @current_table nvarchar(100)',
                @sql,
                @current_table;
        END;

        /*
        This section of code confused me when I came back to it,
        so I'm going to add a note here about why I do this:

        If @include_plan_ids is NULL at this point, it's because
        the user didn't populate the parameter.

        We need to do this because it's how we figure
        out which plans to keep in the main query
        */
        IF @include_plan_ids IS NULL
        BEGIN
            SELECT
                @where_clause += N'AND   EXISTS
          (
             SELECT
                1/0
             FROM #include_plan_ids AS idi
             WHERE idi.plan_id = qsrs.plan_id
          )' + @nc10;
        END;
    END; /*End include query ids*/

    IF @ignore_query_ids IS NOT NULL
    BEGIN
        SELECT
            @ignore_query_ids =
                REPLACE(REPLACE(REPLACE(REPLACE(
                    LTRIM(RTRIM(@ignore_query_ids)),
                 CHAR(10), N''),  CHAR(13), N''),
                NCHAR(10), N''), NCHAR(13), N'');
        SELECT
            @current_table = 'inserting #ignore_query_ids',
            @sql = @isolation_level;

        INSERT
            #ignore_query_ids WITH(TABLOCK)
        (
            query_id
        )
        EXEC sys.sp_executesql
            @string_split_ints,
          N'@ids nvarchar(4000)',
            @ignore_query_ids;

        SELECT
            @current_table = 'inserting #ignore_plan_ids for ignored query ids';

        IF @troubleshoot_performance = 1
        BEGIN
            EXEC sys.sp_executesql
                @troubleshoot_insert,
              N'@current_table nvarchar(100)',
                @current_table;

            SET STATISTICS XML ON;
        END;

        SELECT
            @sql += N'
SELECT DISTINCT
    qsp.plan_id
FROM ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
WHERE EXISTS
      (
          SELECT
              1/0
          FROM #ignore_query_ids AS iqi
          WHERE iqi.query_id = qsp.query_id
      )
OPTION(RECOMPILE);' + @nc10;

        IF @debug = 1
        BEGIN
            PRINT LEN(@sql);
            PRINT @sql;
        END;

        INSERT
            #ignore_plan_ids
        (
            plan_id
        )
        EXEC sys.sp_executesql
            @sql;

        IF @troubleshoot_performance = 1
        BEGIN
            SET STATISTICS XML OFF;

            EXEC sys.sp_executesql
                @troubleshoot_update,
              N'@current_table nvarchar(100)',
                @current_table;

            EXEC sys.sp_executesql
                @troubleshoot_info,
              N'@sql nvarchar(max),
                @current_table nvarchar(100)',
                @sql,
                @current_table;
        END;

        /*
        This section of code confused me when I came back to it,
        so I'm going to add a note here about why I do this:

        If @ignore_plan_ids is NULL at this point, it's because
        the user didn't populate the parameter.

        We need to do this because it's how we figure
        out which plans to keep in the main query
        */
        IF @ignore_plan_ids IS NULL
        BEGIN
            SELECT
                @where_clause += N'AND   NOT EXISTS
          (
             SELECT
                1/0
             FROM #ignore_plan_ids AS idi
             WHERE idi.plan_id = qsrs.plan_id
          )' + @nc10;
        END;
    END; /*End ignore query ids*/
END; /*End query and plan id filtering*/

/*
This section filters query or plan hashes
*/
IF
(
   @include_query_hashes IS NOT NULL
OR @include_plan_hashes  IS NOT NULL
OR @include_sql_handles  IS NOT NULL
OR @ignore_query_hashes  IS NOT NULL
OR @ignore_plan_hashes   IS NOT NULL
OR @ignore_sql_handles   IS NOT NULL
)
BEGIN
    IF @include_query_hashes IS NOT NULL
    BEGIN
        SELECT
            @include_query_hashes =
                REPLACE(REPLACE(REPLACE(REPLACE(
                    LTRIM(RTRIM(@include_query_hashes)),
                 CHAR(10), N''),  CHAR(13), N''),
                NCHAR(10), N''), NCHAR(13), N'');

        SELECT
            @current_table = 'inserting #include_query_hashes',
            @sql = @isolation_level;

        INSERT
            #include_query_hashes WITH(TABLOCK)
        (
            query_hash_s
        )
        EXEC sys.sp_executesql
            @string_split_strings,
          N'@ids nvarchar(4000)',
            @include_query_hashes;

        SELECT
            @current_table = 'inserting #include_plan_ids for included query hashes';

        IF @troubleshoot_performance = 1
        BEGIN
            EXEC sys.sp_executesql
                @troubleshoot_insert,
              N'@current_table nvarchar(100)',
                @current_table;

            SET STATISTICS XML ON;
        END;

        SELECT
            @sql += N'
SELECT DISTINCT
    qsp.plan_id
FROM ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
WHERE EXISTS
      (
          SELECT
              1/0
          FROM ' + @database_name_quoted + N'.sys.query_store_query AS qsq
          WHERE qsq.query_id = qsp.query_id
          AND   EXISTS
                (
                    SELECT
                        1/0
                    FROM #include_query_hashes AS iqh
                    WHERE iqh.query_hash = qsq.query_hash
                )
      )
OPTION(RECOMPILE);' + @nc10;

        IF @debug = 1
        BEGIN
            PRINT LEN(@sql);
            PRINT @sql;
        END;

        INSERT
            #include_plan_ids
        (
            plan_id
        )
        EXEC sys.sp_executesql
            @sql;

        IF @troubleshoot_performance = 1
        BEGIN
            SET STATISTICS XML OFF;

            EXEC sys.sp_executesql
                @troubleshoot_update,
              N'@current_table nvarchar(100)',
                @current_table;

            EXEC sys.sp_executesql
                @troubleshoot_info,
              N'@sql nvarchar(max),
                @current_table nvarchar(100)',
                @sql,
                @current_table;
        END;

        /*
        This section of code confused me when I came back to it,
        so I'm going to add a note here about why I do this:

        If @include_plan_ids is NULL at this point, it's because
        the user didn't populate the parameter.

        We need to do this because it's how we figure
        out which plans to keep in the main query
        */
        IF @include_plan_ids IS NULL
        BEGIN
            SELECT
               @where_clause += N'AND   EXISTS
          (
             SELECT
                1/0
             FROM #include_plan_ids AS idi
             WHERE idi.plan_id = qsrs.plan_id
          )' + @nc10;
        END;
    END; /*End include query hashes*/

    IF @ignore_query_hashes IS NOT NULL
    BEGIN
        SELECT
            @ignore_query_hashes =
                REPLACE(REPLACE(REPLACE(REPLACE(
                    LTRIM(RTRIM(@ignore_query_hashes)),
                 CHAR(10), N''),  CHAR(13), N''),
                NCHAR(10), N''), NCHAR(13), N'');

        SELECT
            @current_table = 'inserting #ignore_query_hashes',
            @sql = @isolation_level;

        INSERT
            #ignore_query_hashes WITH(TABLOCK)
        (
            query_hash_s
        )
        EXEC sys.sp_executesql
            @string_split_strings,
          N'@ids nvarchar(4000)',
            @ignore_query_hashes;

        SELECT
            @current_table = 'inserting #ignore_plan_ids for ignored query hashes';

        IF @troubleshoot_performance = 1
        BEGIN
            EXEC sys.sp_executesql
                @troubleshoot_insert,
              N'@current_table nvarchar(100)',
                @current_table;

            SET STATISTICS XML ON;
        END;

        SELECT
            @sql += N'
SELECT DISTINCT
    qsp.plan_id
FROM ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
WHERE EXISTS
      (
          SELECT
              1/0
          FROM ' + @database_name_quoted + N'.sys.query_store_query AS qsq
          WHERE qsq.query_id = qsp.query_id
          AND   EXISTS
                (
                    SELECT
                        1/0
                    FROM #ignore_query_hashes AS iqh
                    WHERE iqh.query_hash = qsq.query_hash
                )
      )
OPTION(RECOMPILE);' + @nc10;

        IF @debug = 1
        BEGIN
            PRINT LEN(@sql);
            PRINT @sql;
        END;

        INSERT
            #ignore_plan_ids
        (
            plan_id
        )
        EXEC sys.sp_executesql
            @sql;

        IF @troubleshoot_performance = 1
        BEGIN
            SET STATISTICS XML OFF;

            EXEC sys.sp_executesql
                @troubleshoot_update,
              N'@current_table nvarchar(100)',
                @current_table;

            EXEC sys.sp_executesql
                @troubleshoot_info,
              N'@sql nvarchar(max),
                @current_table nvarchar(100)',
                @sql,
                @current_table;
        END;

        /*
        This section of code confused me when I came back to it,
        so I'm going to add a note here about why I do this:

        If @ignore_plan_ids is NULL at this point, it's because
        the user didn't populate the parameter.

        We need to do this because it's how we figure
        out which plans to keep in the main query
        */
        IF @ignore_plan_ids IS NULL
        BEGIN
            SELECT
               @where_clause += N'AND   NOT EXISTS
          (
             SELECT
                1/0
             FROM #ignore_plan_ids AS idi
             WHERE idi.plan_id = qsrs.plan_id
          )' + @nc10;
          END;
    END; /*End ignore query hashes*/

    IF @include_plan_hashes IS NOT NULL
    BEGIN
        SELECT
            @include_plan_hashes =
                REPLACE(REPLACE(REPLACE(REPLACE(
                    LTRIM(RTRIM(@include_plan_hashes)),
                 CHAR(10), N''),  CHAR(13), N''),
                NCHAR(10), N''), NCHAR(13), N'');

        SELECT
            @current_table = 'inserting #include_plan_hashes',
            @sql = @isolation_level;

        INSERT
            #include_plan_hashes WITH(TABLOCK)
        (
            plan_hash_s
        )
        EXEC sys.sp_executesql
            @string_split_strings,
          N'@ids nvarchar(4000)',
            @include_plan_hashes;

        SELECT
            @current_table = 'inserting #include_plan_ids for included plan hashes';

        IF @troubleshoot_performance = 1
        BEGIN
            EXEC sys.sp_executesql
                @troubleshoot_insert,
              N'@current_table nvarchar(100)',
                @current_table;

            SET STATISTICS XML ON;
        END;

        SELECT
            @sql += N'
SELECT DISTINCT
    qsp.plan_id
FROM ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
WHERE EXISTS
      (
          SELECT
              1/0
          FROM #include_plan_hashes AS iph
          WHERE iph.plan_hash = qsp.query_plan_hash
      )
OPTION(RECOMPILE);' + @nc10;

        IF @debug = 1
        BEGIN
            PRINT LEN(@sql);
            PRINT @sql;
        END;

        INSERT
            #include_plan_ids
        (
            plan_id
        )
        EXEC sys.sp_executesql
            @sql;

        IF @troubleshoot_performance = 1
        BEGIN
            SET STATISTICS XML OFF;

            EXEC sys.sp_executesql
                @troubleshoot_update,
              N'@current_table nvarchar(100)',
                @current_table;

            EXEC sys.sp_executesql
                @troubleshoot_info,
              N'@sql nvarchar(max),
                @current_table nvarchar(100)',
                @sql,
                @current_table;
        END;

        /*
        This section of code confused me when I came back to it,
        so I'm going to add a note here about why I do this:

        If @include_plan_ids is NULL at this point, it's because
        the user didn't populate the parameter.

        We need to do this because it's how we figure
        out which plans to keep in the main query
        */
        IF @include_plan_ids IS NULL
        BEGIN
            SELECT
               @where_clause += N'AND   EXISTS
          (
             SELECT
                1/0
             FROM #include_plan_ids AS idi
             WHERE idi.plan_id = qsrs.plan_id
          )' + @nc10;
        END;
    END; /*End include plan hashes*/

    IF @ignore_plan_hashes IS NOT NULL
    BEGIN
        SELECT
            @ignore_plan_hashes =
                REPLACE(REPLACE(REPLACE(REPLACE(
                    LTRIM(RTRIM(@ignore_plan_hashes)),
                 CHAR(10), N''),  CHAR(13), N''),
                NCHAR(10), N''), NCHAR(13), N'');

        SELECT
            @current_table = 'inserting #ignore_plan_hashes',
            @sql = @isolation_level;

        INSERT
            #ignore_plan_hashes WITH(TABLOCK)
        (
            plan_hash_s
        )
        EXEC sys.sp_executesql
            @string_split_strings,
          N'@ids nvarchar(4000)',
            @ignore_plan_hashes;

        SELECT
            @current_table = 'inserting #ignore_plan_ids for ignored query hashes';

        IF @troubleshoot_performance = 1
        BEGIN
            EXEC sys.sp_executesql
                @troubleshoot_insert,
              N'@current_table nvarchar(100)',
                @current_table;

            SET STATISTICS XML ON;
        END;

        SELECT
            @sql += N'
SELECT DISTINCT
    qsp.plan_id
FROM ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
WHERE EXISTS
      (
          SELECT
              1/0
          FROM #ignore_plan_hashes AS iph
          WHERE iph.plan_hash = qsp.query_plan_hash
      )
OPTION(RECOMPILE);' + @nc10;

        IF @debug = 1
        BEGIN
            PRINT LEN(@sql);
            PRINT @sql;
        END;

        INSERT
            #ignore_plan_ids
        (
            plan_id
        )
        EXEC sys.sp_executesql
            @sql;

        IF @troubleshoot_performance = 1
        BEGIN
            SET STATISTICS XML OFF;

            EXEC sys.sp_executesql
                @troubleshoot_update,
              N'@current_table nvarchar(100)',
                @current_table;

            EXEC sys.sp_executesql
                @troubleshoot_info,
              N'@sql nvarchar(max),
                @current_table nvarchar(100)',
                @sql,
                @current_table;
        END;

        /*
        This section of code confused me when I came back to it,
        so I'm going to add a note here about why I do this:

        If @ignore_plan_ids is NULL at this point, it's because
        the user didn't populate the parameter.

        We need to do this because it's how we figure
        out which plans to keep in the main query
        */
        IF @ignore_plan_ids IS NULL
        BEGIN
            SELECT
               @where_clause += N'AND   NOT EXISTS
          (
             SELECT
                1/0
             FROM #ignore_plan_ids AS idi
             WHERE idi.plan_id = qsrs.plan_id
          )' + @nc10;
          END;
    END; /*End ignore plan hashes*/

    IF @include_sql_handles IS NOT NULL
    BEGIN
        SELECT
            @include_sql_handles =
                REPLACE(REPLACE(REPLACE(REPLACE(
                    LTRIM(RTRIM(@include_sql_handles)),
                 CHAR(10), N''),  CHAR(13), N''),
                NCHAR(10), N''), NCHAR(13), N'');

        SELECT
            @current_table = 'inserting #include_sql_handles',
            @sql = @isolation_level;

        INSERT
            #include_sql_handles WITH(TABLOCK)
        (
            sql_handle_s
        )
        EXEC sys.sp_executesql
            @string_split_strings,
          N'@ids nvarchar(4000)',
            @include_sql_handles;

        SELECT
            @current_table = 'inserting #include_sql_handles for included sql handles';

        IF @troubleshoot_performance = 1
        BEGIN

            EXEC sys.sp_executesql
                @troubleshoot_insert,
              N'@current_table nvarchar(100)',
                @current_table;

            SET STATISTICS XML ON;
        END;

        SELECT
            @sql += N'
SELECT DISTINCT
    qsp.plan_id
FROM ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
WHERE EXISTS
      (
          SELECT
              1/0
          FROM ' + @database_name_quoted + N'.sys.query_store_query AS qsq
          WHERE qsp.query_id = qsq.query_id
          AND EXISTS
              (
                  SELECT
                      1/0
                  FROM ' + @database_name_quoted + N'.sys.query_store_query_text AS qsqt
                  WHERE qsqt.query_text_id = qsq.query_text_id
                  AND   EXISTS
                        (
                            SELECT
                                1/0
                            FROM #include_sql_handles AS ish
                            WHERE ish.sql_handle = qsqt.statement_sql_handle
                        )
              )
      )
OPTION(RECOMPILE);' + @nc10;

        IF @debug = 1
        BEGIN
            PRINT LEN(@sql);
            PRINT @sql;
        END;

        INSERT
            #include_plan_ids
        (
            plan_id
        )
        EXEC sys.sp_executesql
            @sql;

        IF @troubleshoot_performance = 1
        BEGIN
            SET STATISTICS XML OFF;

            EXEC sys.sp_executesql
                @troubleshoot_update,
              N'@current_table nvarchar(100)',
                @current_table;

            EXEC sys.sp_executesql
                @troubleshoot_info,
              N'@sql nvarchar(max),
                @current_table nvarchar(100)',
                @sql,
                @current_table;
        END;

        /*
        This section of code confused me when I came back to it,
        so I'm going to add a note here about why I do this:

        If @include_plan_ids is NULL at this point, it's because
        the user didn't populate the parameter.

        We need to do this because it's how we figure
        out which plans to keep in the main query
        */
        IF @include_plan_ids IS NULL
        BEGIN
            SELECT
                @where_clause += N'AND   EXISTS
          (
             SELECT
                1/0
             FROM #include_plan_ids AS idi
             WHERE idi.plan_id = qsrs.plan_id
          )' + @nc10;
        END;
    END; /*End include plan hashes*/

    IF @ignore_sql_handles IS NOT NULL
    BEGIN
        SELECT
            @ignore_sql_handles =
                REPLACE(REPLACE(REPLACE(REPLACE(
                    LTRIM(RTRIM(@ignore_sql_handles)),
                 CHAR(10), N''),  CHAR(13), N''),
                NCHAR(10), N''), NCHAR(13), N'');

        SELECT
            @current_table = 'inserting #ignore_sql_handles',
            @sql = @isolation_level;

        INSERT
            #ignore_sql_handles WITH(TABLOCK)
        (
            sql_handle_s
        )
        EXEC sys.sp_executesql
            @string_split_strings,
          N'@ids nvarchar(4000)',
            @ignore_sql_handles;

        SELECT
            @current_table = 'inserting #ignore_plan_ids for ignored sql handles';

        IF @troubleshoot_performance = 1
        BEGIN
            EXEC sys.sp_executesql
                @troubleshoot_insert,
              N'@current_table nvarchar(100)',
                @current_table;

            SET STATISTICS XML ON;
        END;

        SELECT
            @sql += N'
SELECT DISTINCT
    qsp.plan_id
FROM ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
WHERE EXISTS
      (
          SELECT
              1/0
          FROM ' + @database_name_quoted + N'.sys.query_store_query AS qsq
          WHERE qsp.query_id = qsq.query_id
          AND EXISTS
              (
                  SELECT
                      1/0
                  FROM ' + @database_name_quoted + N'.sys.query_store_query_text AS qsqt
                  WHERE qsqt.query_text_id = qsq.query_text_id
                  AND   EXISTS
                        (
                            SELECT
                                1/0
                            FROM #ignore_sql_handles AS ish
                            WHERE ish.sql_handle = qsqt.statement_sql_handle
                        )
              )
      )
OPTION(RECOMPILE);' + @nc10;

        IF @debug = 1
        BEGIN
            PRINT LEN(@sql);
            PRINT @sql;
        END;

        INSERT
            #ignore_plan_ids
        (
            plan_id
        )
        EXEC sys.sp_executesql
            @sql;

        IF @troubleshoot_performance = 1
        BEGIN
            SET STATISTICS XML OFF;

            EXEC sys.sp_executesql
                @troubleshoot_update,
              N'@current_table nvarchar(100)',
                @current_table;

            EXEC sys.sp_executesql
                @troubleshoot_info,
              N'@sql nvarchar(max),
                @current_table nvarchar(100)',
                @sql,
                @current_table;
        END;

        /*
        This section of code confused me when I came back to it,
        so I'm going to add a note here about why I do this:

        If @ignore_plan_ids is NULL at this point, it's because
        the user didn't populate the parameter.

        We need to do this because it's how we figure
        out which plans to keep in the main query
        */
        IF @ignore_plan_ids IS NULL
        BEGIN
            SELECT
                @where_clause += N'AND   NOT EXISTS
          (
             SELECT
                1/0
             FROM #ignore_plan_ids AS idi
             WHERE idi.plan_id = qsrs.plan_id
          )' + @nc10;
          END;
    END; /*End ignore plan hashes*/
END; /*End hash and handle filtering*/

IF @sql_2022_views = 1
BEGIN
    IF @only_queries_with_hints = 1
    BEGIN
        SELECT
            @current_table = 'inserting #only_queries_with_hints',
            @sql = @isolation_level;

        IF @troubleshoot_performance = 1
        BEGIN
            EXEC sys.sp_executesql
                @troubleshoot_insert,
              N'@current_table nvarchar(100)',
                @current_table;

            SET STATISTICS XML ON;
        END;

        SELECT
            @sql += N'
    SELECT DISTINCT
        qsp.plan_id
    FROM ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
    WHERE EXISTS
          (
              SELECT
                  1/0
              FROM ' + @database_name_quoted + N'.sys.query_store_query_hints AS qsqh
              WHERE qsqh.query_id = qsp.query_id
          )';

        SELECT
            @sql += N'
    OPTION(RECOMPILE);' + @nc10;

        IF @debug = 1
        BEGIN
            PRINT LEN(@sql);
            PRINT @sql;
        END;

        INSERT
            #only_queries_with_hints WITH(TABLOCK)
        (
            plan_id
        )
        EXEC sys.sp_executesql
            @sql

        IF @troubleshoot_performance = 1
        BEGIN
            SET STATISTICS XML OFF;

            EXEC sys.sp_executesql
                @troubleshoot_update,
              N'@current_table nvarchar(100)',
                @current_table;

            EXEC sys.sp_executesql
                @troubleshoot_info,
              N'@sql nvarchar(max),
                @current_table nvarchar(100)',
                @sql,
                @current_table;
        END;

        SELECT
            @where_clause += N'AND   EXISTS
           (
               SELECT
                   1/0
               FROM #only_queries_with_hints AS qst
               WHERE qst.plan_id = qsrs.plan_id
           )' + @nc10;
    END;

    IF @only_queries_with_feedback = 1
    BEGIN
        SELECT
            @current_table = 'inserting #only_queries_with_feedback',
            @sql = @isolation_level;

        IF @troubleshoot_performance = 1
        BEGIN
            EXEC sys.sp_executesql
                @troubleshoot_insert,
              N'@current_table nvarchar(100)',
                @current_table;

            SET STATISTICS XML ON;
        END;

        SELECT
            @sql += N'
    SELECT DISTINCT
        qsp.plan_id
    FROM ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
    WHERE EXISTS
          (
              SELECT
                  1/0
              FROM ' + @database_name_quoted + N'.sys.query_store_plan_feedback AS qsqf
              WHERE qsqf.plan_id = qsp.plan_id
          )';

        SELECT
            @sql += N'
    OPTION(RECOMPILE);' + @nc10;

        IF @debug = 1
        BEGIN
            PRINT LEN(@sql);
            PRINT @sql;
        END;

        INSERT
            #only_queries_with_feedback WITH(TABLOCK)
        (
            plan_id
        )
        EXEC sys.sp_executesql
            @sql

        IF @troubleshoot_performance = 1
        BEGIN
            SET STATISTICS XML OFF;

            EXEC sys.sp_executesql
                @troubleshoot_update,
              N'@current_table nvarchar(100)',
                @current_table;

            EXEC sys.sp_executesql
                @troubleshoot_info,
              N'@sql nvarchar(max),
                @current_table nvarchar(100)',
                @sql,
                @current_table;
        END;

        SELECT
            @where_clause += N'AND   EXISTS
           (
               SELECT
                   1/0
               FROM #only_queries_with_feedback AS qst
               WHERE qst.plan_id = qsrs.plan_id
           )' + @nc10;
    END;

    IF @only_queries_with_variants = 1
    BEGIN
        SELECT
            @current_table = 'inserting #only_queries_with_variants',
            @sql = @isolation_level;

        IF @troubleshoot_performance = 1
        BEGIN
            EXEC sys.sp_executesql
                @troubleshoot_insert,
              N'@current_table nvarchar(100)',
                @current_table;

            SET STATISTICS XML ON;
        END;

        SELECT
            @sql += N'
    SELECT DISTINCT
        qsp.plan_id
    FROM ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
    WHERE EXISTS
          (
              SELECT
                  1/0
              FROM ' + @database_name_quoted + N'.sys.query_store_query_variant AS qsqv
              WHERE qsqv.query_variant_query_id = qsp.query_id
          )';

        SELECT
            @sql += N'
    OPTION(RECOMPILE);' + @nc10;

        IF @debug = 1
        BEGIN
            PRINT LEN(@sql);
            PRINT @sql;
        END;

        INSERT
            #only_queries_with_variants WITH(TABLOCK)
        (
            plan_id
        )
        EXEC sys.sp_executesql
            @sql

        IF @troubleshoot_performance = 1
        BEGIN
            SET STATISTICS XML OFF;

            EXEC sys.sp_executesql
                @troubleshoot_update,
              N'@current_table nvarchar(100)',
                @current_table;

            EXEC sys.sp_executesql
                @troubleshoot_info,
              N'@sql nvarchar(max),
                @current_table nvarchar(100)',
                @sql,
                @current_table;
        END;

        SELECT
            @where_clause += N'AND   EXISTS
           (
               SELECT
                   1/0
               FROM #only_queries_with_variants AS qst
               WHERE qst.plan_id = qsrs.plan_id
           )' + @nc10;
    END;
END;

IF
(
     @only_queries_with_forced_plans = 1
  OR @only_queries_with_forced_plan_failures = 1
)
BEGIN
    SELECT
        @current_table = 'inserting #forced_plans_failures',
        @sql = @isolation_level;

    IF @troubleshoot_performance = 1
    BEGIN
        EXEC sys.sp_executesql
            @troubleshoot_insert,
          N'@current_table nvarchar(100)',
            @current_table;

        SET STATISTICS XML ON;
    END;

    SELECT
        @sql += N'
SELECT DISTINCT
    qsp.plan_id
FROM ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
WHERE qsp.is_forced_plan = 1';

IF @only_queries_with_forced_plan_failures = 1
BEGIN
    SELECT
        @sql += N'
AND   qsp.last_force_failure_reason > 0'
END

    SELECT
        @sql += N'
OPTION(RECOMPILE);' + @nc10;

    IF @debug = 1
    BEGIN
        PRINT LEN(@sql);
        PRINT @sql;
    END;

    INSERT
        #forced_plans_failures WITH(TABLOCK)
    (
        plan_id
    )
    EXEC sys.sp_executesql
        @sql

    IF @troubleshoot_performance = 1
    BEGIN
        SET STATISTICS XML OFF;

        EXEC sys.sp_executesql
            @troubleshoot_update,
          N'@current_table nvarchar(100)',
            @current_table;

        EXEC sys.sp_executesql
            @troubleshoot_info,
          N'@sql nvarchar(max),
            @current_table nvarchar(100)',
            @sql,
            @current_table;
    END;

    SELECT
        @where_clause += N'AND   EXISTS
       (
           SELECT
               1/0
           FROM #forced_plans_failures AS fpf
           WHERE fpf.plan_id = qsrs.plan_id
       )' + @nc10;
END;

IF @query_text_search IS NOT NULL
BEGIN
    IF
    (
        LEFT
        (
            @query_text_search,
            1
        ) <> N'%'
    )
    BEGIN
        SELECT
            @query_text_search =
                N'%' + @query_text_search;
    END;

    IF
    (
        LEFT
        (
            REVERSE
            (
                @query_text_search
            ),
            1
        ) <> N'%'
    )
    BEGIN
        SELECT
            @query_text_search =
                @query_text_search + N'%';
    END;

    /* If our query texts contains square brackets (common in Entity Framework queries), add a leading escape character to each bracket character */
    IF @escape_brackets = 1
    BEGIN
        SELECT
            @query_text_search =
                REPLACE(REPLACE(REPLACE(
                    @query_text_search,
                N'[', @escape_character + N'['),
                N']', @escape_character + N']'),
                N'_', @escape_character + N'_');
    END;

    SELECT
        @current_table = 'inserting #query_text_search',
        @sql = @isolation_level;

    IF @troubleshoot_performance = 1
    BEGIN
        EXEC sys.sp_executesql
            @troubleshoot_insert,
          N'@current_table nvarchar(100)',
            @current_table;

        SET STATISTICS XML ON;
    END;

    SELECT
        @sql += N'
SELECT DISTINCT
    qsp.plan_id
FROM ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
WHERE EXISTS
      (
          SELECT
              1/0
          FROM ' + @database_name_quoted + N'.sys.query_store_query AS qsq
          WHERE qsp.query_id = qsq.query_id
          AND EXISTS
              (
                  SELECT
                      1/0
                  FROM ' + @database_name_quoted + N'.sys.query_store_query_text AS qsqt
                  WHERE qsqt.query_text_id = qsq.query_text_id
                  AND   qsqt.query_sql_text LIKE @query_text_search
              )
      )';

    /* If we are escaping bracket character in our query text search, add the ESCAPE clause and character to the LIKE subquery*/
    IF @escape_brackets = 1
    BEGIN
        SELECT
            @sql =
                REPLACE
                (
                    @sql,
                    N'@query_text_search',
                    N'@query_text_search ESCAPE ''' + @escape_character + N''''
                );
    END;

/*If we're searching by a procedure name, limit the text search to it */
IF
(
    @procedure_name IS NOT NULL
AND @procedure_exists = 1
)
BEGIN
    SELECT
        @sql += N'
AND   EXISTS
      (
          SELECT
              1/0
          FROM #procedure_plans AS pp
          WHERE pp.plan_id = qsp.plan_id
      )';
END;

    SELECT
        @sql += N'
    OPTION(RECOMPILE);' + @nc10;

    IF @debug = 1
    BEGIN
        PRINT LEN(@sql);
        PRINT @sql;
    END;

    INSERT
        #query_text_search WITH(TABLOCK)
    (
        plan_id
    )
    EXEC sys.sp_executesql
        @sql,
      N'@query_text_search nvarchar(4000)',
        @query_text_search;

    IF @troubleshoot_performance = 1
    BEGIN
        SET STATISTICS XML OFF;

        EXEC sys.sp_executesql
            @troubleshoot_update,
          N'@current_table nvarchar(100)',
            @current_table;

        EXEC sys.sp_executesql
            @troubleshoot_info,
          N'@sql nvarchar(max),
            @current_table nvarchar(100)',
            @sql,
            @current_table;
    END;

    SELECT
        @where_clause += N'AND   EXISTS
       (
           SELECT
               1/0
           FROM #query_text_search AS qst
           WHERE qst.plan_id = qsrs.plan_id
       )' + @nc10;
END;

/*
Validate wait stats stuff
*/
IF @wait_filter IS NOT NULL
BEGIN
    BEGIN
        SELECT
            @current_table = 'inserting #wait_filter',
            @sql = @isolation_level;

        IF @troubleshoot_performance = 1
        BEGIN
            EXEC sys.sp_executesql
                @troubleshoot_insert,
              N'@current_table nvarchar(100)',
                @current_table;

            SET STATISTICS XML ON;
        END;

        SELECT
            @sql += N'
SELECT TOP (@top)
    qsws.plan_id
FROM  ' + @database_name_quoted + N'.sys.query_store_wait_stats AS qsws
WHERE 1 = 1
AND   qsws.wait_category = ' +
CASE @wait_filter
     WHEN 'cpu' THEN N'1'
     WHEN 'lock' THEN N'3'
     WHEN 'locks' THEN N'3'
     WHEN 'latch' THEN N'4'
     WHEN 'latches' THEN N'4'
     WHEN 'buffer latch' THEN N'5'
     WHEN 'buffer latches' THEN N'5'
     WHEN 'buffer io' THEN N'6'
     WHEN 'log' THEN N'14'
     WHEN 'log io' THEN N'14'
     WHEN 'network' THEN N'15'
     WHEN 'network io' THEN N'15'
     WHEN 'parallel' THEN N'16'
     WHEN 'parallelism' THEN N'16'
     WHEN 'memory' THEN N'17'
END
+ N'
GROUP BY
    qsws.plan_id
HAVING
    SUM(qsws.avg_query_wait_time_ms) > 1000.
ORDER BY
    SUM(qsws.avg_query_wait_time_ms) DESC
OPTION(RECOMPILE, OPTIMIZE FOR (@top = 9223372036854775807));' + @nc10;
    END;

    IF @debug = 1
    BEGIN
        PRINT LEN(@sql);
        PRINT @sql;
    END;

    INSERT
        #wait_filter WITH(TABLOCK)
    (
        plan_id
    )
    EXEC sys.sp_executesql
        @sql,
      N'@top bigint',
        @top;

    IF @troubleshoot_performance = 1
    BEGIN
        SET STATISTICS XML OFF;

        EXEC sys.sp_executesql
            @troubleshoot_update,
          N'@current_table nvarchar(100)',
            @current_table;

        EXEC sys.sp_executesql
            @troubleshoot_info,
          N'@sql nvarchar(max),
            @current_table nvarchar(100)',
            @sql,
            @current_table;
    END;

    SELECT
        @where_clause += N'AND   EXISTS
       (
           SELECT
               1/0
           FROM #wait_filter AS wf
           WHERE wf.plan_id = qsrs.plan_id
       )' + @nc10;
END;


/*
This section screens out index create and alter statements because who cares
*/

SELECT
    @current_table = 'inserting #maintenance_plans',
    @sql = @isolation_level;

IF @troubleshoot_performance = 1
BEGIN
    EXEC sys.sp_executesql
        @troubleshoot_insert,
      N'@current_table nvarchar(100)',
        @current_table;

    SET STATISTICS XML ON;
END;

SELECT
    @sql += N'
SELECT DISTINCT
   qsp.plan_id
FROM ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
WHERE NOT EXISTS
      (
          SELECT
             1/0
          FROM ' + @database_name_quoted + N'.sys.query_store_query AS qsq
          JOIN ' + @database_name_quoted + N'.sys.query_store_query_text AS qsqt
            ON qsqt.query_text_id = qsq.query_text_id
          WHERE qsq.query_id = qsp.query_id
          AND   qsqt.query_sql_text NOT LIKE N''ALTER INDEX%''
          AND   qsqt.query_sql_text NOT LIKE N''ALTER TABLE%''
          AND   qsqt.query_sql_text NOT LIKE N''CREATE%INDEX%''
          AND   qsqt.query_sql_text NOT LIKE N''CREATE STATISTICS%''
          AND   qsqt.query_sql_text NOT LIKE N''UPDATE STATISTICS%''
          AND   qsqt.query_sql_text NOT LIKE N''SELECT StatMan%''
          AND   qsqt.query_sql_text NOT LIKE N''DBCC%''
          AND   qsqt.query_sql_text NOT LIKE N''(@[_]msparam%''
      )
OPTION(RECOMPILE);' + @nc10;

IF @debug = 1
BEGIN
    PRINT LEN(@sql);
    PRINT @sql;
END;

INSERT
    #maintenance_plans WITH(TABLOCK)
(
    plan_id
)
EXEC sys.sp_executesql
    @sql;

IF @troubleshoot_performance = 1
BEGIN
    SET STATISTICS XML OFF;

    EXEC sys.sp_executesql
        @troubleshoot_update,
      N'@current_table nvarchar(100)',
        @current_table;

    EXEC sys.sp_executesql
        @troubleshoot_info,
      N'@sql nvarchar(max),
        @current_table nvarchar(100)',
        @sql,
        @current_table;
END;

SELECT
    @where_clause += N'AND   NOT EXISTS
      (
          SELECT
              1/0
          FROM #maintenance_plans AS mp
          WHERE mp.plan_id = qsrs.plan_id
      )' + @nc10;

/*
Tidy up the where clause a bit
*/
SELECT
    @where_clause =
        SUBSTRING
        (
            @where_clause,
            1,
            LEN(@where_clause) - 1
        );

/*
This gets the plan_ids we care about
*/
SELECT
    @current_table = 'inserting #distinct_plans',
    @sql = @isolation_level;

IF @troubleshoot_performance = 1
BEGIN
    EXEC sys.sp_executesql
        @troubleshoot_insert,
      N'@current_table nvarchar(100)',
        @current_table;

    SET STATISTICS XML ON;
END;

SELECT
    @sql += N'
SELECT TOP (@top)
    qsrs.plan_id
FROM ' + @database_name_quoted + N'.sys.query_store_runtime_stats AS qsrs
WHERE 1 = 1
' + @where_clause
  + N'
GROUP
    BY qsrs.plan_id
ORDER BY
    MAX(' +
CASE @sort_order
     WHEN 'cpu' THEN N'qsrs.avg_cpu_time'
     WHEN 'logical reads' THEN N'qsrs.avg_logical_io_reads'
     WHEN 'physical reads' THEN N'qsrs.avg_physical_io_reads'
     WHEN 'writes' THEN N'qsrs.avg_logical_io_writes'
     WHEN 'duration' THEN N'qsrs.avg_duration'
     WHEN 'memory' THEN N'qsrs.avg_query_max_used_memory'
     WHEN 'tempdb' THEN CASE WHEN @new = 1 THEN N'qsrs.avg_tempdb_space_used' ELSE N'qsrs.avg_cpu_time' END
     WHEN 'executions' THEN N'qsrs.count_executions'
     WHEN 'recent' THEN N'qsrs.last_execution_time'
     ELSE N'qsrs.avg_cpu_time'
END +
N') DESC
OPTION(RECOMPILE, OPTIMIZE FOR (@top = 9223372036854775807));' + @nc10;

IF @debug = 1
BEGIN
    PRINT LEN(@sql);
    PRINT @sql;
END;

INSERT
    #distinct_plans WITH(TABLOCK)
(
    plan_id
)
EXEC sys.sp_executesql
    @sql,
    @parameters,
    @top,
    @start_date,
    @end_date,
    @execution_count,
    @duration_ms,
    @execution_type_desc,
    @database_id,
    @queries_top,
    @work_start_utc,
    @work_end_utc;

IF @troubleshoot_performance = 1
BEGIN
    SET STATISTICS XML OFF;

    EXEC sys.sp_executesql
        @troubleshoot_update,
      N'@current_table nvarchar(100)',
        @current_table;

    EXEC sys.sp_executesql
        @troubleshoot_info,
      N'@sql nvarchar(max),
        @current_table nvarchar(100)',
        @sql,
        @current_table;
END; /*End gathering plan ids*/

/*
This gets the runtime stats for the plans we care about
*/
SELECT
    @current_table = 'inserting #query_store_runtime_stats',
    @sql = @isolation_level;

IF @troubleshoot_performance = 1
BEGIN
    EXEC sys.sp_executesql
        @troubleshoot_insert,
      N'@current_table nvarchar(100)',
        @current_table;

    SET STATISTICS XML ON;
END;

SELECT
    @sql += N'
SELECT
    @database_id,
    MAX(qsrs.runtime_stats_id),
    qsrs.plan_id,
    MAX(qsrs.runtime_stats_interval_id),
    MAX(qsrs.execution_type_desc),
    MIN(qsrs.first_execution_time),
    MAX(qsrs.last_execution_time),
    SUM(qsrs.count_executions),
    AVG((qsrs.avg_duration / 1000.)),
    MAX((qsrs.last_duration / 1000.)),
    MIN((qsrs.min_duration / 1000.)),
    MAX((qsrs.max_duration / 1000.)),
    AVG((qsrs.avg_cpu_time / 1000.)),
    MAX((qsrs.last_cpu_time / 1000.)),
    MIN((qsrs.min_cpu_time / 1000.)),
    MAX((qsrs.max_cpu_time / 1000.)),
    AVG(((qsrs.avg_logical_io_reads * 8.) / 1024.)),
    MAX(((qsrs.last_logical_io_reads * 8.) / 1024.)),
    MIN(((qsrs.min_logical_io_reads * 8.) / 1024.)),
    MAX(((qsrs.max_logical_io_reads * 8.) / 1024.)),
    AVG(((qsrs.avg_logical_io_writes * 8.) / 1024.)),
    MAX(((qsrs.last_logical_io_writes * 8.) / 1024.)),
    MIN(((qsrs.min_logical_io_writes * 8.) / 1024.)),
    MAX(((qsrs.max_logical_io_writes * 8.) / 1024.)),
    AVG(((qsrs.avg_physical_io_reads * 8.) / 1024.)),
    MAX(((qsrs.last_physical_io_reads * 8.) / 1024.)),
    MIN(((qsrs.min_physical_io_reads * 8.) / 1024.)),
    MAX(((qsrs.max_physical_io_reads * 8.) / 1024.)),
    AVG((qsrs.avg_clr_time / 1000.)),
    MAX((qsrs.last_clr_time / 1000.)),
    MIN((qsrs.min_clr_time / 1000.)),
    MAX((qsrs.max_clr_time / 1000.)),
    MAX(qsrs.last_dop),
    MIN(qsrs.min_dop),
    MAX(qsrs.max_dop),
    AVG(((qsrs.avg_query_max_used_memory * 8.) / 1024.)),
    MAX(((qsrs.last_query_max_used_memory * 8.) / 1024.)),
    MIN(((qsrs.min_query_max_used_memory * 8.) / 1024.)),
    MAX(((qsrs.max_query_max_used_memory * 8.) / 1024.)),
    AVG(qsrs.avg_rowcount),
    MAX(qsrs.last_rowcount),
    MIN(qsrs.min_rowcount),
    MAX(qsrs.max_rowcount),';

IF @new = 1
    BEGIN
        SELECT
            @sql += N'
    AVG(((qsrs.avg_num_physical_io_reads * 8.) / 1024.)),
    MAX(((qsrs.last_num_physical_io_reads * 8.) / 1024.)),
    MIN(((qsrs.min_num_physical_io_reads * 8.) / 1024.)),
    MAX(((qsrs.max_num_physical_io_reads * 8.) / 1024.)),
    AVG((qsrs.avg_log_bytes_used / 100000000.)),
    MAX((qsrs.last_log_bytes_used / 100000000.)),
    MIN((qsrs.min_log_bytes_used / 100000000.)),
    MAX((qsrs.max_log_bytes_used / 100000000.)),
    AVG(((qsrs.avg_tempdb_space_used * 8) / 1024.)),
    MAX(((qsrs.last_tempdb_space_used * 8) / 1024.)),
    MIN(((qsrs.min_tempdb_space_used * 8) / 1024.)),
    MAX(((qsrs.max_tempdb_space_used * 8) / 1024.)),';
    END;

IF @new = 0
    BEGIN
        SELECT
            @sql += N'
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,';
    END;

SELECT
    @sql += N'
    context_settings = NULL
FROM #distinct_plans AS dp
CROSS APPLY
(
    SELECT TOP (@queries_top)
        qsrs.*
    FROM ' + @database_name_quoted + N'.sys.query_store_runtime_stats AS qsrs
    WHERE qsrs.plan_id = dp.plan_id
    AND   1 = 1
    ' + @where_clause
  + N'
    ORDER BY ' +
CASE @sort_order
     WHEN 'cpu' THEN N'qsrs.avg_cpu_time'
     WHEN 'logical reads' THEN N'qsrs.avg_logical_io_reads'
     WHEN 'physical reads' THEN N'qsrs.avg_physical_io_reads'
     WHEN 'writes' THEN N'qsrs.avg_logical_io_writes'
     WHEN 'duration' THEN N'qsrs.avg_duration'
     WHEN 'memory' THEN N'qsrs.avg_query_max_used_memory'
     WHEN 'tempdb' THEN CASE WHEN @new = 1 THEN N'qsrs.avg_tempdb_space_used' ELSE N'qsrs.avg_cpu_time' END
     WHEN 'executions' THEN N'qsrs.count_executions'
     WHEN 'recent' THEN N'qsrs.last_execution_time'
     ELSE N'qsrs.avg_cpu_time'
END + N' DESC
) AS qsrs
GROUP BY
    qsrs.plan_id
OPTION(RECOMPILE, OPTIMIZE FOR (@queries_top = 9223372036854775807));' + @nc10;

IF @debug = 1
BEGIN
    PRINT LEN(@sql);
    PRINT @sql;
END;

INSERT
    #query_store_runtime_stats WITH(TABLOCK)
(
    database_id, runtime_stats_id, plan_id, runtime_stats_interval_id, execution_type_desc,
    first_execution_time, last_execution_time, count_executions,
    avg_duration_ms, last_duration_ms, min_duration_ms, max_duration_ms,
    avg_cpu_time_ms, last_cpu_time_ms, min_cpu_time_ms, max_cpu_time_ms,
    avg_logical_io_reads_mb, last_logical_io_reads_mb, min_logical_io_reads_mb, max_logical_io_reads_mb,
    avg_logical_io_writes_mb, last_logical_io_writes_mb, min_logical_io_writes_mb, max_logical_io_writes_mb,
    avg_physical_io_reads_mb, last_physical_io_reads_mb, min_physical_io_reads_mb, max_physical_io_reads_mb,
    avg_clr_time_ms, last_clr_time_ms, min_clr_time_ms, max_clr_time_ms,
    last_dop, min_dop, max_dop,
    avg_query_max_used_memory_mb, last_query_max_used_memory_mb, min_query_max_used_memory_mb, max_query_max_used_memory_mb,
    avg_rowcount, last_rowcount, min_rowcount, max_rowcount,
    avg_num_physical_io_reads_mb, last_num_physical_io_reads_mb, min_num_physical_io_reads_mb, max_num_physical_io_reads_mb,
    avg_log_bytes_used_mb, last_log_bytes_used_mb, min_log_bytes_used_mb, max_log_bytes_used_mb,
    avg_tempdb_space_used_mb, last_tempdb_space_used_mb, min_tempdb_space_used_mb, max_tempdb_space_used_mb,
    context_settings
)
EXEC sys.sp_executesql
    @sql,
    @parameters,
    @top,
    @start_date,
    @end_date,
    @execution_count,
    @duration_ms,
    @execution_type_desc,
    @database_id,
    @queries_top,
    @work_start_utc,
    @work_end_utc;

IF @troubleshoot_performance = 1
BEGIN
    SET STATISTICS XML OFF;

    EXEC sys.sp_executesql
        @troubleshoot_update,
      N'@current_table nvarchar(100)',
        @current_table;

    EXEC sys.sp_executesql
        @troubleshoot_info,
      N'@sql nvarchar(max),
        @current_table nvarchar(100)',
        @sql,
        @current_table;
END; /*End getting runtime stats*/

/*
This gets the query plans we're after
*/
SELECT
    @current_table = 'inserting #query_store_plan',
    @sql = @isolation_level;

IF @troubleshoot_performance = 1
BEGIN
    EXEC sys.sp_executesql
        @troubleshoot_insert,
      N'@current_table nvarchar(100)',
        @current_table;

    SET STATISTICS XML ON;
END;

SELECT
    @sql += N'
SELECT
    @database_id,
    qsp.plan_id,
    qsp.query_id,
    all_plan_ids =
        STUFF
        (
            (
                SELECT DISTINCT
                    '', '' +
                    RTRIM
                        (qsp_plans.plan_id)
                FROM ' + @database_name_quoted + N'.sys.query_store_plan AS qsp_plans
                WHERE qsp_plans.query_id = qsp.query_id
                FOR XML PATH(''''), TYPE
            ).value(''./text()[1]'', ''varchar(max)''),
            1,
            2,
            ''''
        ),
    qsp.plan_group_id,
    qsp.engine_version,
    qsp.compatibility_level,
    qsp.query_plan_hash,
    qsp.query_plan,
    qsp.is_online_index_plan,
    qsp.is_trivial_plan,
    qsp.is_parallel_plan,
    qsp.is_forced_plan,
    qsp.is_natively_compiled,
    qsp.force_failure_count,
    qsp.last_force_failure_reason_desc,
    qsp.count_compiles,
    qsp.initial_compile_start_time,
    qsp.last_compile_start_time,
    qsp.last_execution_time,
    (qsp.avg_compile_duration / 1000.),
    (qsp.last_compile_duration / 1000.),';

IF
(
      @new = 0
  AND @sql_2022_views = 0
)
BEGIN
    SELECT
        @sql += N'
    NULL,
    NULL,
    NULL,
    NULL';
END;

IF
(
      @new = 1
  AND @sql_2022_views = 0
)
BEGIN
    SELECT
        @sql += N'
    qsp.plan_forcing_type_desc,
    NULL,
    NULL,
    NULL';
END;

IF
(
      @new = 1
  AND @sql_2022_views = 1
)
BEGIN
    SELECT
        @sql += N'
    qsp.plan_forcing_type_desc,
    qsp.has_compile_replay_script,
    qsp.is_optimized_plan_forcing_disabled,
    qsp.plan_type_desc';
END;

SELECT
    @sql += N'
FROM #query_store_runtime_stats AS qsrs
CROSS APPLY
(
    SELECT TOP (@plans_top)
        qsp.*
    FROM ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
    WHERE qsp.plan_id = qsrs.plan_id
    AND   qsp.is_online_index_plan = 0
    ORDER BY
        qsp.last_execution_time DESC
) AS qsp
WHERE qsrs.database_id = @database_id
OPTION(RECOMPILE, OPTIMIZE FOR (@plans_top = 9223372036854775807));' + @nc10;

IF @debug = 1
BEGIN
    PRINT LEN(@sql);
    PRINT @sql;
END;

INSERT
    #query_store_plan WITH(TABLOCK)
(
    database_id,
    plan_id,
    query_id,
    all_plan_ids,
    plan_group_id,
    engine_version,
    compatibility_level,
    query_plan_hash,
    query_plan,
    is_online_index_plan,
    is_trivial_plan,
    is_parallel_plan,
    is_forced_plan,
    is_natively_compiled,
    force_failure_count,
    last_force_failure_reason_desc,
    count_compiles,
    initial_compile_start_time,
    last_compile_start_time,
    last_execution_time,
    avg_compile_duration_ms,
    last_compile_duration_ms,
    plan_forcing_type_desc,
    has_compile_replay_script,
    is_optimized_plan_forcing_disabled,
    plan_type_desc
)
EXEC sys.sp_executesql
    @sql,
  N'@plans_top bigint,
    @database_id int',
    @plans_top,
    @database_id;

IF @troubleshoot_performance = 1
BEGIN
    SET STATISTICS XML OFF;

    EXEC sys.sp_executesql
        @troubleshoot_update,
      N'@current_table nvarchar(100)',
        @current_table;

    EXEC sys.sp_executesql
        @troubleshoot_info,
      N'@sql nvarchar(max),
        @current_table nvarchar(100)',
        @sql,
        @current_table;
END; /*End getting query plans*/

/*
This gets some query information
*/
SELECT
    @current_table = 'inserting #query_store_query',
    @sql = @isolation_level;

IF @troubleshoot_performance = 1
BEGIN
    EXEC sys.sp_executesql
        @troubleshoot_insert,
      N'@current_table nvarchar(100)',
        @current_table;

    SET STATISTICS XML ON;
END;

SELECT
    @sql += N'
SELECT
    @database_id,
    qsq.query_id,
    qsq.query_text_id,
    qsq.context_settings_id,
    qsq.object_id,
    qsq.batch_sql_handle,
    qsq.query_hash,
    qsq.is_internal_query,
    qsq.query_parameterization_type_desc,
    qsq.initial_compile_start_time,
    qsq.last_compile_start_time,
    qsq.last_execution_time,
    qsq.last_compile_batch_sql_handle,
    qsq.last_compile_batch_offset_start,
    qsq.last_compile_batch_offset_end,
    qsq.count_compiles,
    (qsq.avg_compile_duration / 1000.),
    (qsq.last_compile_duration / 1000.),
    (qsq.avg_bind_duration / 1000.),
    (qsq.last_bind_duration / 1000.),
    (qsq.avg_bind_cpu_time / 1000.),
    (qsq.last_bind_cpu_time / 1000.),
    (qsq.avg_optimize_duration / 1000.),
    (qsq.last_optimize_duration / 1000.),
    (qsq.avg_optimize_cpu_time / 1000.),
    (qsq.last_optimize_cpu_time / 1000.),
    ((qsq.avg_compile_memory_kb * 8) / 1024.),
    ((qsq.last_compile_memory_kb * 8) / 1024.),
    ((qsq.max_compile_memory_kb * 8) / 1024.),
    qsq.is_clouddb_internal_query
FROM #query_store_plan AS qsp
CROSS APPLY
(
    SELECT TOP (1)
        qsq.*
    FROM ' + @database_name_quoted + N'.sys.query_store_query AS qsq
    WHERE qsq.query_id = qsp.query_id
    ORDER
        BY qsq.last_execution_time DESC
) AS qsq
WHERE qsp.database_id = @database_id
OPTION(RECOMPILE);' + @nc10;

IF @debug = 1
BEGIN
    PRINT LEN(@sql);
    PRINT @sql;
END;

INSERT
    #query_store_query WITH(TABLOCK)
(
    database_id,
    query_id,
    query_text_id,
    context_settings_id,
    object_id,
    batch_sql_handle,
    query_hash,
    is_internal_query,
    query_parameterization_type_desc,
    initial_compile_start_time,
    last_compile_start_time,
    last_execution_time,
    last_compile_batch_sql_handle,
    last_compile_batch_offset_start,
    last_compile_batch_offset_end,
    count_compiles,
    avg_compile_duration_ms,
    last_compile_duration_ms,
    avg_bind_duration_ms,
    last_bind_duration_ms,
    avg_bind_cpu_time_ms,
    last_bind_cpu_time_ms,
    avg_optimize_duration_ms,
    last_optimize_duration_ms,
    avg_optimize_cpu_time_ms,
    last_optimize_cpu_time_ms,
    avg_compile_memory_mb,
    last_compile_memory_mb,
    max_compile_memory_mb,
    is_clouddb_internal_query
)
EXEC sys.sp_executesql
    @sql,
  N'@database_id int',
    @database_id;

IF @troubleshoot_performance = 1
BEGIN
    SET STATISTICS XML OFF;

    EXEC sys.sp_executesql
        @troubleshoot_update,
      N'@current_table nvarchar(100)',
        @current_table;

    EXEC sys.sp_executesql
        @troubleshoot_info,
      N'@sql nvarchar(max),
        @current_table nvarchar(100)',
        @sql,
        @current_table;
END; /*End getting query details*/

/*
This gets the query text for them!
*/
SELECT
    @current_table = 'inserting #query_store_query_text',
    @sql = @isolation_level;

IF @troubleshoot_performance = 1
BEGIN
    EXEC sys.sp_executesql
        @troubleshoot_insert,
      N'@current_table nvarchar(100)',
        @current_table;

    SET STATISTICS XML ON;
END;


SELECT
    @sql += N'
SELECT
    @database_id,
    qsqt.query_text_id,
    query_sql_text =
        (
             SELECT
                 [processing-instruction(query)] =
                     REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                     REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                     REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                         qsqt.query_sql_text COLLATE Latin1_General_BIN2,
                     NCHAR(31),N''?''),NCHAR(30),N''?''),NCHAR(29),N''?''),NCHAR(28),N''?''),NCHAR(27),N''?''),NCHAR(26),N''?''),NCHAR(25),N''?''),NCHAR(24),N''?''),NCHAR(23),N''?''),NCHAR(22),N''?''),
                     NCHAR(21),N''?''),NCHAR(20),N''?''),NCHAR(19),N''?''),NCHAR(18),N''?''),NCHAR(17),N''?''),NCHAR(16),N''?''),NCHAR(15),N''?''),NCHAR(14),N''?''),NCHAR(12),N''?''),
                     NCHAR(11),N''?''),NCHAR(8),N''?''),NCHAR(7),N''?''),NCHAR(6),N''?''),NCHAR(5),N''?''),NCHAR(4),N''?''),NCHAR(3),N''?''),NCHAR(2),N''?''),NCHAR(1),N''?''),NCHAR(0),N'''')
             FOR XML
                 PATH(''''),
                 TYPE
        ),
    qsqt.statement_sql_handle,
    qsqt.is_part_of_encrypted_module,
    qsqt.has_restricted_text
FROM #query_store_query AS qsq
CROSS APPLY
(
    SELECT TOP (1)
        qsqt.*
    FROM ' + @database_name_quoted + N'.sys.query_store_query_text AS qsqt
    WHERE qsqt.query_text_id = qsq.query_text_id
) AS qsqt
WHERE qsq.database_id = @database_id
OPTION(RECOMPILE);' + @nc10;

IF @debug = 1
BEGIN
    PRINT LEN(@sql);
    PRINT @sql;
END;

INSERT
    #query_store_query_text WITH(TABLOCK)
(
    database_id,
    query_text_id,
    query_sql_text,
    statement_sql_handle,
    is_part_of_encrypted_module,
    has_restricted_text
)
EXEC sys.sp_executesql
    @sql,
  N'@database_id int',
    @database_id;

IF @troubleshoot_performance = 1
BEGIN
    SET STATISTICS XML OFF;

    EXEC sys.sp_executesql
        @troubleshoot_update,
      N'@current_table nvarchar(100)',
        @current_table;

    EXEC sys.sp_executesql
        @troubleshoot_info,
      N'@sql nvarchar(max),
        @current_table nvarchar(100)',
        @sql,
        @current_table;
END; /*End getting query text*/

/*
Here we try to get some data from the "plan cache"
that isn't available in Query Store :(
*/
SELECT
    @sql = N'',
    @current_table = 'inserting #dm_exec_query_stats';

IF @troubleshoot_performance = 1
BEGIN
    EXEC sys.sp_executesql
        @troubleshoot_insert,
      N'@current_table nvarchar(100)',
        @current_table;

    SET STATISTICS XML ON;
END;

INSERT
    #dm_exec_query_stats WITH(TABLOCK)
(
    statement_sql_handle,
    total_grant_mb,
    last_grant_mb,
    min_grant_mb,
    max_grant_mb,
    total_used_grant_mb,
    last_used_grant_mb,
    min_used_grant_mb,
    max_used_grant_mb,
    total_ideal_grant_mb,
    last_ideal_grant_mb,
    min_ideal_grant_mb,
    max_ideal_grant_mb,
    total_reserved_threads,
    last_reserved_threads,
    min_reserved_threads,
    max_reserved_threads,
    total_used_threads,
    last_used_threads,
    min_used_threads,
    max_used_threads
)
SELECT
    deqs.statement_sql_handle,
    MAX(deqs.total_grant_kb) / 1024.,
    MAX(deqs.last_grant_kb) / 1024.,
    MAX(deqs.min_grant_kb) / 1024.,
    MAX(deqs.max_grant_kb) / 1024.,
    MAX(deqs.total_used_grant_kb) / 1024.,
    MAX(deqs.last_used_grant_kb) / 1024.,
    MAX(deqs.min_used_grant_kb) / 1024.,
    MAX(deqs.max_used_grant_kb) / 1024.,
    MAX(deqs.total_ideal_grant_kb) / 1024.,
    MAX(deqs.last_ideal_grant_kb) / 1024.,
    MAX(deqs.min_ideal_grant_kb) / 1024.,
    MAX(deqs.max_ideal_grant_kb) / 1024.,
    MAX(deqs.total_reserved_threads),
    MAX(deqs.last_reserved_threads),
    MAX(deqs.min_reserved_threads),
    MAX(deqs.max_reserved_threads),
    MAX(deqs.total_used_threads),
    MAX(deqs.last_used_threads),
    MAX(deqs.min_used_threads),
    MAX(deqs.max_used_threads)
FROM sys.dm_exec_query_stats AS deqs
WHERE EXISTS
      (
          SELECT
              1/0
          FROM #query_store_query_text AS qsqt
          WHERE qsqt.statement_sql_handle = deqs.statement_sql_handle
      )
GROUP BY
    deqs.statement_sql_handle
OPTION(RECOMPILE);

SELECT
    @rc = @@ROWCOUNT;

IF @troubleshoot_performance = 1
BEGIN
    SET STATISTICS XML OFF;

    EXEC sys.sp_executesql
        @troubleshoot_update,
      N'@current_table nvarchar(100)',
        @current_table;

    EXEC sys.sp_executesql
        @troubleshoot_info,
      N'@sql nvarchar(max),
        @current_table nvarchar(100)',
        @sql,
        @current_table;
END; /*End getting runtime stats*/

/*Only update if we got anything*/
IF @rc > 0
BEGIN
    SELECT
        @current_table = 'updating #dm_exec_query_stats';

    IF @troubleshoot_performance = 1
    BEGIN
        EXEC sys.sp_executesql
            @troubleshoot_insert,
          N'@current_table nvarchar(100)',
            @current_table;

        SET STATISTICS XML ON;
    END;

    UPDATE
        qsqt
    SET
        qsqt.total_grant_mb = deqs.total_grant_mb,
        qsqt.last_grant_mb = deqs.last_grant_mb,
        qsqt.min_grant_mb = deqs.min_grant_mb,
        qsqt.max_grant_mb = deqs.max_grant_mb,
        qsqt.total_used_grant_mb = deqs.total_used_grant_mb,
        qsqt.last_used_grant_mb = deqs.last_used_grant_mb,
        qsqt.min_used_grant_mb = deqs.min_used_grant_mb,
        qsqt.max_used_grant_mb = deqs.max_used_grant_mb,
        qsqt.total_ideal_grant_mb = deqs.total_ideal_grant_mb,
        qsqt.last_ideal_grant_mb = deqs.last_ideal_grant_mb,
        qsqt.min_ideal_grant_mb = deqs.min_ideal_grant_mb,
        qsqt.max_ideal_grant_mb = deqs.max_ideal_grant_mb,
        qsqt.total_reserved_threads = deqs.total_reserved_threads,
        qsqt.last_reserved_threads = deqs.last_reserved_threads,
        qsqt.min_reserved_threads = deqs.min_reserved_threads,
        qsqt.max_reserved_threads = deqs.max_reserved_threads,
        qsqt.total_used_threads = deqs.total_used_threads,
        qsqt.last_used_threads = deqs.last_used_threads,
        qsqt.min_used_threads = deqs.min_used_threads,
        qsqt.max_used_threads = deqs.max_used_threads
    FROM #query_store_query_text AS qsqt
    JOIN #dm_exec_query_stats AS deqs
      ON qsqt.statement_sql_handle = deqs.statement_sql_handle
    OPTION(RECOMPILE);

    IF @troubleshoot_performance = 1
    BEGIN
        SET STATISTICS XML OFF;

        EXEC sys.sp_executesql
            @troubleshoot_update,
          N'@current_table nvarchar(100)',
            @current_table;

        EXEC sys.sp_executesql
            @troubleshoot_info,
          N'@sql nvarchar(max),
            @current_table nvarchar(100)',
            @sql,
            @current_table;
    END;
END; /*End updating runtime stats*/

/*
Let's check on settings, etc.
We do this first so we can see if wait stats capture mode is true more easily
*/
SELECT
    @current_table = 'inserting #database_query_store_options',
    @sql = @isolation_level;

IF @troubleshoot_performance = 1
BEGIN
    EXEC sys.sp_executesql
        @troubleshoot_insert,
      N'@current_table nvarchar(100)',
        @current_table;

    SET STATISTICS XML ON;
END;

SELECT
    @sql += N'
SELECT
    @database_id,
    dqso.desired_state_desc,
    dqso.actual_state_desc,
    readonly_reason =
        CASE dqso.readonly_reason
             WHEN 0
             THEN ''None''
             WHEN 2
             THEN ''Database in single user mode''
             WHEN 4
             THEN ''Database is in emergency mode''
             WHEN 8
             THEN ''Database is AG secondary''
             WHEN 65536
             THEN ''Reached max size: '' +
                  FORMAT(dqso.current_storage_size_mb, ''N0'') +
                  '' of '' +
                  FORMAT(dqso.max_storage_size_mb, ''N0'') +
                  ''.''
             WHEN 131072
             THEN ''The number of different statements in Query Store has reached the internal memory limit''
             WHEN 262144
             THEN ''Size of in-memory items waiting to be persisted on disk has reached the internal memory limit''
             WHEN 524288
             THEN ''Database has reached disk size limit''
             ELSE ''WOAH''
        END,
    dqso.current_storage_size_mb,
    dqso.flush_interval_seconds,
    dqso.interval_length_minutes,
    dqso.max_storage_size_mb,
    dqso.stale_query_threshold_days,
    dqso.max_plans_per_query,
    dqso.query_capture_mode_desc,'
    +
    CASE
        WHEN
        (
             @product_version > 14
          OR @azure = 1
        )
        THEN N'
    dqso.capture_policy_execution_count,
    dqso.capture_policy_total_compile_cpu_time_ms,
    dqso.capture_policy_total_execution_cpu_time_ms,
    dqso.capture_policy_stale_threshold_hours,'
        ELSE N'
    NULL,
    NULL,
    NULL,
    NULL,'
    END
    + N'
    dqso.size_based_cleanup_mode_desc,'
    +
    CASE
        WHEN (@product_version = 13
              AND @azure = 0)
        THEN N'
    NULL'
        ELSE N'
    dqso.wait_stats_capture_mode_desc'
    END
    + N'
FROM ' + @database_name_quoted + N'.sys.database_query_store_options AS dqso
OPTION(RECOMPILE);' + @nc10;

IF @debug = 1
BEGIN
    PRINT LEN(@sql);
    PRINT @sql;
END;

INSERT
    #database_query_store_options WITH(TABLOCK)
(
    database_id,
    desired_state_desc,
    actual_state_desc,
    readonly_reason,
    current_storage_size_mb,
    flush_interval_seconds,
    interval_length_minutes,
    max_storage_size_mb,
    stale_query_threshold_days,
    max_plans_per_query,
    query_capture_mode_desc,
    capture_policy_execution_count,
    capture_policy_total_compile_cpu_time_ms,
    capture_policy_total_execution_cpu_time_ms,
    capture_policy_stale_threshold_hours,
    size_based_cleanup_mode_desc,
    wait_stats_capture_mode_desc
)
EXEC sys.sp_executesql
    @sql,
  N'@database_id int',
    @database_id;

IF @troubleshoot_performance = 1
BEGIN
    SET STATISTICS XML OFF;

    EXEC sys.sp_executesql
        @troubleshoot_update,
      N'@current_table nvarchar(100)',
        @current_table;

    EXEC sys.sp_executesql
        @troubleshoot_info,
      N'@sql nvarchar(max),
        @current_table nvarchar(100)',
        @sql,
        @current_table;
END; /*End getting query store settings*/

/*
If wait stats are available, we'll grab them here
*/
IF
(
    @new = 1
    AND EXISTS
        (
            SELECT
                1/0
            FROM #database_query_store_options AS dqso
            WHERE dqso.wait_stats_capture_mode_desc = N'ON'
        )
)
BEGIN
    SELECT
        @current_table = 'inserting #query_store_wait_stats',
        @sql = @isolation_level;

    IF @troubleshoot_performance = 1
    BEGIN
        EXEC sys.sp_executesql
            @troubleshoot_insert,
          N'@current_table nvarchar(100)',
            @current_table;

        SET STATISTICS XML ON;
    END;

    SELECT
        @sql += N'
SELECT
    @database_id,
    qsws.plan_id,
    qsws.wait_category_desc,
    total_query_wait_time_ms =
        SUM(qsws.total_query_wait_time_ms),
    avg_query_wait_time_ms =
        SUM(qsws.avg_query_wait_time_ms),
    last_query_wait_time_ms =
        SUM(qsws.last_query_wait_time_ms),
    min_query_wait_time_ms =
        SUM(qsws.min_query_wait_time_ms),
    max_query_wait_time_ms =
        SUM(qsws.max_query_wait_time_ms)
FROM #query_store_runtime_stats AS qsrs
CROSS APPLY
(
    SELECT TOP (5)
        qsws.*
    FROM ' + @database_name_quoted + N'.sys.query_store_wait_stats AS qsws
    WHERE qsws.runtime_stats_interval_id = qsrs.runtime_stats_interval_id
    AND   qsws.plan_id = qsrs.plan_id
    AND   qsws.wait_category > 0
    AND   qsws.min_query_wait_time_ms > 0
    ORDER BY
        qsws.avg_query_wait_time_ms DESC
) AS qsws
WHERE qsrs.database_id = @database_id
GROUP BY
    qsws.plan_id,
    qsws.wait_category_desc
HAVING
    SUM(qsws.min_query_wait_time_ms) > 0.
OPTION(RECOMPILE);' + @nc10;

    IF @debug = 1
    BEGIN
        PRINT LEN(@sql);
        PRINT @sql;
    END;

    INSERT
        #query_store_wait_stats WITH(TABLOCK)
    (
        database_id,
        plan_id,
        wait_category_desc,
        total_query_wait_time_ms,
        avg_query_wait_time_ms,
        last_query_wait_time_ms,
        min_query_wait_time_ms,
        max_query_wait_time_ms
    )
    EXEC sys.sp_executesql
        @sql,
      N'@database_id int',
        @database_id;

    IF @troubleshoot_performance = 1
    BEGIN
        SET STATISTICS XML OFF;

        EXEC sys.sp_executesql
            @troubleshoot_update,
          N'@current_table nvarchar(100)',
            @current_table;

        EXEC sys.sp_executesql
            @troubleshoot_info,
          N'@sql nvarchar(max),
            @current_table nvarchar(100)',
            @sql,
            @current_table;
    END;
END; /*End getting wait stats*/

/*
This gets context info and settings
*/
SELECT
    @current_table = 'inserting #query_context_settings',
    @sql = @isolation_level;

IF @troubleshoot_performance = 1
BEGIN
    EXEC sys.sp_executesql
        @troubleshoot_insert,
      N'@current_table nvarchar(100)',
        @current_table;

    SET STATISTICS XML ON;
END;

SELECT
    @sql += N'
SELECT
    @database_id,
    context_settings_id,
    set_options,
    language_id,
    date_format,
    date_first,
    status,
    required_cursor_options,
    acceptable_cursor_options,
    merge_action_type,
    default_schema_id,
    is_replication_specific,
    is_contained
FROM ' + @database_name_quoted + N'.sys.query_context_settings AS qcs
WHERE EXISTS
      (
          SELECT
              1/0
          FROM #query_store_runtime_stats AS qsrs
          JOIN #query_store_plan AS qsp
            ON  qsrs.plan_id = qsp.plan_id
            AND qsrs.database_id = qsp.database_id
          JOIN #query_store_query AS qsq
            ON  qsp.query_id = qsq.query_id
            AND qsp.database_id = qsq.database_id
          WHERE qsq.context_settings_id = qcs.context_settings_id
      )
OPTION(RECOMPILE);';

INSERT
    #query_context_settings WITH(TABLOCK)
(
    database_id,
    context_settings_id,
    set_options,
    language_id,
    date_format,
    date_first,
    status,
    required_cursor_options,
    acceptable_cursor_options,
    merge_action_type,
    default_schema_id,
    is_replication_specific,
    is_contained
)
EXEC sys.sp_executesql
    @sql,
  N'@database_id int',
    @database_id;

IF @troubleshoot_performance = 1
BEGIN
    SET STATISTICS XML OFF;

    EXEC sys.sp_executesql
        @troubleshoot_update,
      N'@current_table nvarchar(100)',
        @current_table;

    EXEC sys.sp_executesql
        @troubleshoot_info,
      N'@sql nvarchar(max),
        @current_table nvarchar(100)',
        @sql,
        @current_table;
END; /*End getting context settings*/

/*
Update things to get the context settings for each query
*/
SELECT
    @current_table = 'updating context_settings in #query_store_runtime_stats';

UPDATE
    qsrs
SET
    qsrs.context_settings =
        SUBSTRING
        (
            CASE
                WHEN
                    CONVERT
                    (
                        int,
                        qcs.set_options
                    ) & 1 = 1
                THEN ', ANSI_PADDING'
                ELSE ''
            END +
            CASE
                WHEN
                    CONVERT
                    (
                        int,
                        qcs.set_options
                    ) & 8 = 8
                THEN ', CONCAT_NULL_YIELDS_NULL'
                ELSE ''
            END +
            CASE
                WHEN
                    CONVERT
                    (
                        int,
                        qcs.set_options
                    ) & 16 = 16
                THEN ', ANSI_WARNINGS'
                ELSE ''
            END +
            CASE
                WHEN
                    CONVERT
                    (
                        int,
                        qcs.set_options
                    ) & 32 = 32
                THEN ', ANSI_NULLS'
                ELSE ''
            END +
            CASE
                WHEN
                    CONVERT
                    (
                        int,
                        qcs.set_options
                    ) & 64 = 64
                THEN ', QUOTED_IDENTIFIER'
                ELSE ''
            END +
            CASE
                WHEN
                    CONVERT
                    (
                        int,
                        qcs.set_options
                    ) & 4096 = 4096
                THEN ', ARITH_ABORT'
                ELSE ''
            END +
            CASE
                WHEN
                    CONVERT
                    (
                        int,
                        qcs.set_options
                    ) & 8192 = 8192
                THEN ', NUMERIC_ROUNDABORT'
                ELSE ''
            END,
            2,
            256
        )
FROM #query_store_runtime_stats AS qsrs
JOIN #query_store_plan AS qsp
  ON  qsrs.plan_id = qsp.plan_id
  AND qsrs.database_id = qsp.database_id
JOIN #query_store_query AS qsq
  ON  qsp.query_id = qsq.query_id
  AND qsp.database_id = qsq.database_id
JOIN #query_context_settings AS qcs
  ON  qsq.context_settings_id = qcs.context_settings_id
  AND qsq.database_id = qcs.database_id
OPTION(RECOMPILE);

IF @sql_2022_views = 1
BEGIN
    /*query_store_plan_feedback*/
    SELECT
        @current_table = 'inserting #query_store_plan_feedback',
        @sql = @isolation_level;

    IF @troubleshoot_performance = 1
    BEGIN
        EXEC sys.sp_executesql
            @troubleshoot_insert,
          N'@current_table nvarchar(100)',
            @current_table;

        SET STATISTICS XML ON;
    END;

    SELECT
        @sql += N'
SELECT
    @database_id,
    qspf.plan_feedback_id,
    qspf.plan_id,
    qspf.feature_desc,
    qspf.feedback_data,
    qspf.state_desc,
    qspf.create_time,
    qspf.last_updated_time
FROM ' + @database_name_quoted + N'.sys.query_store_plan_feedback AS qspf
WHERE EXISTS
      (
          SELECT
              1/0
          FROM #query_store_plan AS qsp
          WHERE qspf.plan_id = qsp.plan_id
      )
OPTION(RECOMPILE);' + @nc10;

    IF @debug = 1
    BEGIN
        PRINT LEN(@sql);
        PRINT @sql;
    END;

    INSERT
        #query_store_plan_feedback WITH(TABLOCK)
    (
        database_id,
        plan_feedback_id,
        plan_id,
        feature_desc,
        feedback_data,
        state_desc,
        create_time,
        last_updated_time
    )
    EXEC sys.sp_executesql
        @sql,
      N'@database_id int',
        @database_id;

    IF @troubleshoot_performance = 1
    BEGIN
        SET STATISTICS XML OFF;

        EXEC sys.sp_executesql
            @troubleshoot_update,
          N'@current_table nvarchar(100)',
            @current_table;

        EXEC sys.sp_executesql
            @troubleshoot_info,
          N'@sql nvarchar(max),
            @current_table nvarchar(100)',
            @sql,
            @current_table;
    END;

    /*query_store_query_variant*/
    SELECT
        @current_table = 'inserting #query_store_query_variant',
        @sql = @isolation_level;

    IF @troubleshoot_performance = 1
    BEGIN
        EXEC sys.sp_executesql
            @troubleshoot_insert,
          N'@current_table nvarchar(100)',
            @current_table;

        SET STATISTICS XML ON;
    END;

    SELECT
        @sql += N'
SELECT
    @database_id,
    qsqv.query_variant_query_id,
    qsqv.parent_query_id,
    qsqv.dispatcher_plan_id
FROM ' + @database_name_quoted + N'.sys.query_store_query_variant AS qsqv
WHERE EXISTS
      (
          SELECT
              1/0
          FROM #query_store_plan AS qsp
          WHERE qsqv.query_variant_query_id = qsp.query_id
          AND   qsqv.dispatcher_plan_id = qsp.plan_id
      )
OPTION(RECOMPILE);' + @nc10;

    IF @debug = 1
    BEGIN
        PRINT LEN(@sql);
        PRINT @sql;
    END;

    INSERT
        #query_store_query_variant WITH(TABLOCK)
    (
        database_id,
        query_variant_query_id,
        parent_query_id,
        dispatcher_plan_id
    )
    EXEC sys.sp_executesql
        @sql,
      N'@database_id int',
        @database_id;

    IF @troubleshoot_performance = 1
    BEGIN
        SET STATISTICS XML OFF;

        EXEC sys.sp_executesql
            @troubleshoot_update,
          N'@current_table nvarchar(100)',
            @current_table;

        EXEC sys.sp_executesql
            @troubleshoot_info,
          N'@sql nvarchar(max),
            @current_table nvarchar(100)',
            @sql,
            @current_table;
    END;

    /*query_store_query_hints*/
    SELECT
        @current_table = 'inserting #query_store_query_hints',
        @sql = @isolation_level;

    IF @troubleshoot_performance = 1
    BEGIN
        EXEC sys.sp_executesql
            @troubleshoot_insert,
          N'@current_table nvarchar(100)',
            @current_table;

        SET STATISTICS XML ON;
    END;

    SELECT
        @sql += N'
SELECT
    @database_id,
    qsqh.query_hint_id,
    qsqh.query_id,
    qsqh.query_hint_text,
    qsqh.last_query_hint_failure_reason_desc,
    qsqh.query_hint_failure_count,
    qsqh.source_desc
FROM ' + @database_name_quoted + N'.sys.query_store_query_hints AS qsqh
WHERE EXISTS
      (
          SELECT
              1/0
          FROM #query_store_plan AS qsp
          WHERE qsqh.query_id = qsp.query_id
      )
OPTION(RECOMPILE);' + @nc10;

    IF @debug = 1
    BEGIN
        PRINT LEN(@sql);
        PRINT @sql;
    END;

    INSERT
        #query_store_query_hints WITH(TABLOCK)
    (
        database_id,
        query_hint_id,
        query_id,
        query_hint_text,
        last_query_hint_failure_reason_desc,
        query_hint_failure_count,
        source_desc
    )
    EXEC sys.sp_executesql
        @sql,
      N'@database_id int',
        @database_id;

    IF @troubleshoot_performance = 1
    BEGIN
        SET STATISTICS XML OFF;

        EXEC sys.sp_executesql
            @troubleshoot_update,
          N'@current_table nvarchar(100)',
            @current_table;

        EXEC sys.sp_executesql
            @troubleshoot_info,
          N'@sql nvarchar(max),
            @current_table nvarchar(100)',
            @sql,
            @current_table;
    END;

    IF @ags_present = 1
    BEGIN
        /*query_store_plan_forcing_locations*/
        SELECT
            @current_table = 'inserting #query_store_plan_forcing_locations',
            @sql = @isolation_level;

        IF @troubleshoot_performance = 1
        BEGIN
            EXEC sys.sp_executesql
                @troubleshoot_insert,
              N'@current_table nvarchar(100)',
                @current_table;

            SET STATISTICS XML ON;
        END;

        SELECT
            @sql += N'
SELECT
    @database_id,
    qspfl.plan_forcing_location_id,
    qspfl.query_id,
    qspfl.plan_id,
    qspfl.replica_group_id
FROM ' + @database_name_quoted + N'.sys.query_store_plan_forcing_locations AS qspfl
WHERE EXISTS
      (
          SELECT
              1/0
          FROM #query_store_plan AS qsp
          WHERE qspfl.query_id = qsp.query_id
          AND   qspfl.plan_id = qsp.plan_id
      )
OPTION(RECOMPILE);' + @nc10;

        IF @debug = 1
        BEGIN
            PRINT LEN(@sql);
            PRINT @sql;
        END;

        INSERT
            #query_store_plan_forcing_locations WITH(TABLOCK)
        (
            database_id,
            plan_forcing_location_id,
            query_id,
            plan_id,
            replica_group_id
        )
        EXEC sys.sp_executesql
            @sql,
          N'@database_id int',
            @database_id;

        IF @troubleshoot_performance = 1
        BEGIN
            SET STATISTICS XML OFF;

            EXEC sys.sp_executesql
                @troubleshoot_update,
              N'@current_table nvarchar(100)',
                @current_table;

            EXEC sys.sp_executesql
                @troubleshoot_info,
              N'@sql nvarchar(max),
                @current_table nvarchar(100)',
                @sql,
                @current_table;
        END;

        /*query_store_replicas*/
        SELECT
            @current_table = 'inserting #query_store_replicas',
            @sql = @isolation_level;

        IF @troubleshoot_performance = 1
        BEGIN
            EXEC sys.sp_executesql
                @troubleshoot_insert,
              N'@current_table nvarchar(100)',
                @current_table;

            SET STATISTICS XML ON;
        END;

        SELECT
            @sql += N'
SELECT
    @database_id,
    qsr.replica_group_id,
    qsr.role_type,
    qsr.replica_name
FROM ' + @database_name_quoted + N'.sys.query_store_replicas AS qsr
WHERE EXISTS
      (
          SELECT
              1/0
          FROM #query_store_plan_forcing_locations AS qspfl
          WHERE qspfl.replica_group_id = qsr.replica_group_id
      )
OPTION(RECOMPILE);' + @nc10;

        IF @debug = 1
        BEGIN
            PRINT LEN(@sql);
            PRINT @sql;
        END;

        INSERT
            #query_store_replicas WITH(TABLOCK)
        (
            database_id,
            replica_group_id,
            role_type,
            replica_name
        )
        EXEC sys.sp_executesql
            @sql,
          N'@database_id int',
            @database_id;

        IF @troubleshoot_performance = 1
        BEGIN
            SET STATISTICS XML OFF;

            EXEC sys.sp_executesql
                @troubleshoot_update,
              N'@current_table nvarchar(100)',
                @current_table;

            EXEC sys.sp_executesql
                @troubleshoot_info,
              N'@sql nvarchar(max),
                @current_table nvarchar(100)',
                @sql,
                @current_table;
        END;
    END; /*End AG queries*/
END; /*End SQL 2022 views*/

/*
These tables need to get cleared out
to avoid result pollution and
primary key violations
*/
IF @get_all_databases = 1
BEGIN
    TRUNCATE TABLE
        #distinct_plans;
    TRUNCATE TABLE
        #procedure_plans;
    TRUNCATE TABLE
        #maintenance_plans;
    TRUNCATE TABLE
        #query_text_search;
    TRUNCATE TABLE
        #dm_exec_query_stats;
    TRUNCATE TABLE
        #query_types;
    TRUNCATE TABLE
        #wait_filter;
    TRUNCATE TABLE
        #only_queries_with_hints;
    TRUNCATE TABLE
        #only_queries_with_feedback;
    TRUNCATE TABLE
        #only_queries_with_variants;
    TRUNCATE TABLE
        #forced_plans_failures;
END;

FETCH NEXT
FROM database_cursor
INTO @database_name;
END;

CLOSE database_cursor;
DEALLOCATE database_cursor;

/*
This is where we start returning results
*/
IF EXISTS
   (
      SELECT
          1/0
      FROM #query_store_runtime_stats AS qsrs
   )
BEGIN
    SELECT
        @sql = @isolation_level,
        @current_table = 'selecting final results';

    SELECT
        @sql +=
        CONVERT
        (
            nvarchar(MAX),
        N'
SELECT
    x.*
FROM
('
        );

    /*
    Expert mode returns more columns from runtime stats
    */
    IF
    (
        @expert_mode = 1
    AND @format_output = 0
    )
    BEGIN
        SELECT
            @sql +=
        CONVERT
        (
            nvarchar(MAX),
            N'
    SELECT
        source =
            ''runtime_stats'',
        database_name =
            DB_NAME(qsrs.database_id),
        qsp.query_id,
        qsrs.plan_id,
        qsp.all_plan_ids,'
        +
            CASE
                WHEN @include_plan_hashes IS NOT NULL
                THEN
        N'
        qsp.query_plan_hash,'
                WHEN @include_query_hashes IS NOT NULL
                THEN
        N'
        qsq.query_hash,'
                WHEN @include_sql_handles IS NOT NULL
                THEN
        N'
        qsqt.statement_sql_handle,'
                ELSE
        N''
            END + N'
        qsrs.execution_type_desc,
        qsq.object_name,
        qsqt.query_sql_text,
        query_plan =
             CASE
                 WHEN TRY_CAST(qsp.query_plan AS XML) IS NOT NULL
                 THEN TRY_CAST(qsp.query_plan AS XML)
                 WHEN TRY_CAST(qsp.query_plan AS XML) IS NULL
                 THEN
                     (
                         SELECT
                             [processing-instruction(query_plan)] =
                                 N''-- '' + NCHAR(13) + NCHAR(10) +
                                 N''-- This is a huge query plan.'' + NCHAR(13) + NCHAR(10) +
                                 N''-- Remove the headers and footers, save it as a .sqlplan file, and re-open it.'' + NCHAR(13) + NCHAR(10) +
                                 NCHAR(13) + NCHAR(10) +
                                 REPLACE(qsp.query_plan, N''<RelOp'', NCHAR(13) + NCHAR(10) + N''<RelOp'') +
                                 NCHAR(13) + NCHAR(10) COLLATE Latin1_General_Bin2
                         FOR XML PATH(N''''),
                                 TYPE
                     )
             END,
        qsp.compatibility_level,'
        +
            CASE @sql_2022_views
                 WHEN 1
                 THEN
        N'
        has_query_feedback =
            CASE WHEN EXISTS (SELECT 1/0 FROM #query_store_plan_feedback AS qspf WHERE qspf.plan_id = qsp.plan_id) THEN ''Yes'' ELSE ''No'' END,
        has_query_store_hints =
            CASE WHEN EXISTS (SELECT 1/0 FROM #query_store_query_hints AS qsqh WHERE qsqh.query_id = qsp.query_id) THEN ''Yes'' ELSE ''No'' END,
        has_plan_variants =
            CASE WHEN EXISTS (SELECT 1/0 FROM #query_store_query_variant AS qsqv WHERE qsqv.query_variant_query_id = qsp.query_id) THEN ''Yes'' ELSE ''No'' END,
        qsp.has_compile_replay_script,
        qsp.is_optimized_plan_forcing_disabled,
        qsp.plan_type_desc,'
                 ELSE
        N''
                 END +
        N'
        qsp.force_failure_count,
        qsp.last_force_failure_reason_desc,'
        +
        CONVERT
        (
            nvarchar(MAX),
            CASE @new
                 WHEN 1
                 THEN
        N'
        qsp.plan_forcing_type_desc,
        w.top_waits,'
                 ELSE
        N''
            END
        )
        + N'
        first_execution_time =
            CASE
                WHEN @timezone IS NULL
                THEN
                    DATEADD
                    (
                        MINUTE,
                        @utc_minutes_original,
                        qsrs.first_execution_time
                    )
                WHEN @timezone IS NOT NULL
                THEN qsrs.first_execution_time AT TIME ZONE @timezone
            END,
        first_execution_time_utc =
            qsrs.first_execution_time,
        last_execution_time =
            CASE
                WHEN @timezone IS NULL
                THEN
                    DATEADD
                    (
                        MINUTE,
                        @utc_minutes_original,
                        qsrs.last_execution_time
                    )
                WHEN @timezone IS NOT NULL
                THEN qsrs.last_execution_time AT TIME ZONE @timezone
            END,
        last_execution_time_utc =
            qsrs.last_execution_time,
        qsrs.count_executions,
        qsrs.executions_per_second,
        qsrs.avg_duration_ms,
        qsrs.total_duration_ms,
        qsrs.last_duration_ms,
        qsrs.min_duration_ms,
        qsrs.max_duration_ms,
        qsrs.avg_cpu_time_ms,
        qsrs.total_cpu_time_ms,
        qsrs.last_cpu_time_ms,
        qsrs.min_cpu_time_ms,
        qsrs.max_cpu_time_ms,
        qsrs.avg_logical_io_reads_mb,
        qsrs.total_logical_io_reads_mb,
        qsrs.last_logical_io_reads_mb,
        qsrs.min_logical_io_reads_mb,
        qsrs.max_logical_io_reads_mb,
        qsrs.avg_logical_io_writes_mb,
        qsrs.total_logical_io_writes_mb,
        qsrs.last_logical_io_writes_mb,
        qsrs.min_logical_io_writes_mb,
        qsrs.max_logical_io_writes_mb,
        qsrs.avg_physical_io_reads_mb,
        qsrs.total_physical_io_reads_mb,
        qsrs.last_physical_io_reads_mb,
        qsrs.min_physical_io_reads_mb,
        qsrs.max_physical_io_reads_mb,
        qsrs.avg_clr_time_ms,
        qsrs.total_clr_time_ms,
        qsrs.last_clr_time_ms,
        qsrs.min_clr_time_ms,
        qsrs.max_clr_time_ms,
        qsrs.last_dop,
        qsrs.min_dop,
        qsrs.max_dop,
        qsrs.avg_query_max_used_memory_mb,
        qsrs.total_query_max_used_memory_mb,
        qsrs.last_query_max_used_memory_mb,
        qsrs.min_query_max_used_memory_mb,
        qsrs.max_query_max_used_memory_mb,
        qsrs.avg_rowcount,
        qsrs.total_rowcount,
        qsrs.last_rowcount,
        qsrs.min_rowcount,
        qsrs.max_rowcount,'
        +
            CASE @new
                 WHEN 1
                 THEN
        N'
        qsrs.avg_num_physical_io_reads_mb,
        qsrs.total_num_physical_io_reads_mb,
        qsrs.last_num_physical_io_reads_mb,
        qsrs.min_num_physical_io_reads_mb,
        qsrs.max_num_physical_io_reads_mb,
        qsrs.avg_log_bytes_used_mb,
        qsrs.total_log_bytes_used_mb,
        qsrs.last_log_bytes_used_mb,
        qsrs.min_log_bytes_used_mb,
        qsrs.max_log_bytes_used_mb,
        qsrs.avg_tempdb_space_used_mb,
        qsrs.total_tempdb_space_used_mb,
        qsrs.last_tempdb_space_used_mb,
        qsrs.min_tempdb_space_used_mb,
        qsrs.max_tempdb_space_used_mb,'
                 ELSE
        N''
            END +
            CONVERT
            (
                nvarchar(MAX),
                N'
        qsrs.context_settings,
        n =
            ROW_NUMBER() OVER
            (
                PARTITION BY
                    qsrs.plan_id
                ORDER BY
                    ' +
        CASE @sort_order
            WHEN 'cpu' THEN N'qsrs.avg_cpu_time_ms'
            WHEN 'logical reads' THEN N'qsrs.avg_logical_io_reads_mb'
            WHEN 'physical reads' THEN N'qsrs.avg_physical_io_reads_mb'
            WHEN 'writes' THEN N'qsrs.avg_logical_io_writes_mb'
            WHEN 'duration' THEN N'qsrs.avg_duration_ms'
            WHEN 'memory' THEN N'qsrs.avg_query_max_used_memory_mb'
            WHEN 'tempdb' THEN CASE WHEN @new = 1 THEN N'qsrs.avg_tempdb_space_used_mb' ELSE N'qsrs.avg_cpu_time' END
            WHEN 'executions' THEN N'qsrs.count_executions'
            WHEN 'recent' THEN N'qsrs.last_execution_time'
            ELSE N'qsrs.avg_cpu_time_ms'
        END + N' DESC
            )'
            )
        );
    END; /*End expert mode 1, format output 0 columns*/

    /*
    Do we want to format things?
    */
    IF
    (
        @expert_mode = 1
    AND @format_output = 1
    )
    BEGIN
        SELECT
            @sql +=
        CONVERT
        (
            nvarchar(MAX),
            N'
    SELECT
        source =
            ''runtime_stats'',
        database_name =
            DB_NAME(qsrs.database_id),
        qsp.query_id,
        qsrs.plan_id,
        qsp.all_plan_ids,'
        +
            CASE
                WHEN @include_plan_hashes IS NOT NULL
                THEN
        N'
        qsp.query_plan_hash,'
                WHEN @include_query_hashes IS NOT NULL
                THEN
        N'
        qsq.query_hash,'
                WHEN @include_sql_handles IS NOT NULL
                THEN
        N'
        qsqt.statement_sql_handle,'
                ELSE
        N''
            END + N'
        qsrs.execution_type_desc,
        qsq.object_name,
        qsqt.query_sql_text,
        query_plan =
             CASE
                 WHEN TRY_CAST(qsp.query_plan AS XML) IS NOT NULL
                 THEN TRY_CAST(qsp.query_plan AS XML)
                 WHEN TRY_CAST(qsp.query_plan AS XML) IS NULL
                 THEN
                     (
                         SELECT
                             [processing-instruction(query_plan)] =
                                 N''-- '' + NCHAR(13) + NCHAR(10) +
                                 N''-- This is a huge query plan.'' + NCHAR(13) + NCHAR(10) +
                                 N''-- Remove the headers and footers, save it as a .sqlplan file, and re-open it.'' + NCHAR(13) + NCHAR(10) +
                                 NCHAR(13) + NCHAR(10) +
                                 REPLACE(qsp.query_plan, N''<RelOp'', NCHAR(13) + NCHAR(10) + N''<RelOp'') +
                                 NCHAR(13) + NCHAR(10) COLLATE Latin1_General_Bin2
                         FOR XML PATH(N''''),
                                 TYPE
                     )
             END,
        qsp.compatibility_level,'
        +
            CASE @sql_2022_views
                 WHEN 1
                 THEN
        N'
        has_query_feedback =
            CASE WHEN EXISTS (SELECT 1/0 FROM #query_store_plan_feedback AS qspf WHERE qspf.plan_id = qsp.plan_id) THEN ''Yes'' ELSE ''No'' END,
        has_query_store_hints =
            CASE WHEN EXISTS (SELECT 1/0 FROM #query_store_query_hints AS qsqh WHERE qsqh.query_id = qsp.query_id) THEN ''Yes'' ELSE ''No'' END,
        has_plan_variants =
            CASE WHEN EXISTS (SELECT 1/0 FROM #query_store_query_variant AS qsqv WHERE qsqv.query_variant_query_id = qsp.query_id) THEN ''Yes'' ELSE ''No'' END,
        qsp.has_compile_replay_script,
        qsp.is_optimized_plan_forcing_disabled,
        qsp.plan_type_desc,'
                 ELSE
        N''
                 END +
        N'
        qsp.force_failure_count,
        qsp.last_force_failure_reason_desc,'
        +
        CONVERT
        (
            nvarchar(MAX),
            CASE @new
                 WHEN 1
                 THEN
        N'
        qsp.plan_forcing_type_desc,
        w.top_waits,'
                 ELSE
        N''
            END
        ) +
        CONVERT
        (
            nvarchar(MAX),
            N'
        first_execution_time =
            CASE
                WHEN @timezone IS NULL
                THEN
                    DATEADD
                    (
                        MINUTE,
                        @utc_minutes_original,
                        qsrs.first_execution_time
                    )
                WHEN @timezone IS NOT NULL
                THEN qsrs.first_execution_time AT TIME ZONE @timezone
            END,
        first_execution_time_utc =
            qsrs.first_execution_time,
        last_execution_time =
            CASE
                WHEN @timezone IS NULL
                THEN
                    DATEADD
                    (
                        MINUTE,
                        @utc_minutes_original,
                        qsrs.last_execution_time
                    )
                WHEN @timezone IS NOT NULL
                THEN qsrs.last_execution_time AT TIME ZONE @timezone
            END,
        last_execution_time_utc =
            qsrs.last_execution_time,
        count_executions = FORMAT(qsrs.count_executions, ''N0''),
        executions_per_second = FORMAT(qsrs.executions_per_second, ''N0''),
        avg_duration_ms = FORMAT(qsrs.avg_duration_ms, ''N0''),
        total_duration_ms = FORMAT(qsrs.total_duration_ms, ''N0''),
        last_duration_ms = FORMAT(qsrs.last_duration_ms, ''N0''),
        min_duration_ms = FORMAT(qsrs.min_duration_ms, ''N0''),
        max_duration_ms = FORMAT(qsrs.max_duration_ms, ''N0''),
        avg_cpu_time_ms = FORMAT(qsrs.avg_cpu_time_ms, ''N0''),
        total_cpu_time_ms = FORMAT(qsrs.total_cpu_time_ms, ''N0''),
        last_cpu_time_ms = FORMAT(qsrs.last_cpu_time_ms, ''N0''),
        min_cpu_time_ms = FORMAT(qsrs.min_cpu_time_ms, ''N0''),
        max_cpu_time_ms = FORMAT(qsrs.max_cpu_time_ms, ''N0''),
        avg_logical_io_reads_mb = FORMAT(qsrs.avg_logical_io_reads_mb, ''N0''),
        total_logical_io_reads_mb = FORMAT(qsrs.total_logical_io_reads_mb, ''N0''),
        last_logical_io_reads_mb = FORMAT(qsrs.last_logical_io_reads_mb, ''N0''),
        min_logical_io_reads_mb = FORMAT(qsrs.min_logical_io_reads_mb, ''N0''),
        max_logical_io_reads_mb = FORMAT(qsrs.max_logical_io_reads_mb, ''N0''),
        avg_logical_io_writes_mb = FORMAT(qsrs.avg_logical_io_writes_mb, ''N0''),
        total_logical_io_writes_mb = FORMAT(qsrs.total_logical_io_writes_mb, ''N0''),
        last_logical_io_writes_mb = FORMAT(qsrs.last_logical_io_writes_mb, ''N0''),
        min_logical_io_writes_mb = FORMAT(qsrs.min_logical_io_writes_mb, ''N0''),
        max_logical_io_writes_mb = FORMAT(qsrs.max_logical_io_writes_mb, ''N0''),
        avg_physical_io_reads_mb = FORMAT(qsrs.avg_physical_io_reads_mb, ''N0''),
        total_physical_io_reads_mb = FORMAT(qsrs.total_physical_io_reads_mb, ''N0''),
        last_physical_io_reads_mb = FORMAT(qsrs.last_physical_io_reads_mb, ''N0''),
        min_physical_io_reads_mb = FORMAT(qsrs.min_physical_io_reads_mb, ''N0''),
        max_physical_io_reads_mb = FORMAT(qsrs.max_physical_io_reads_mb, ''N0''),
        avg_clr_time_ms = FORMAT(qsrs.avg_clr_time_ms, ''N0''),
        total_clr_time_ms = FORMAT(qsrs.total_clr_time_ms, ''N0''),
        last_clr_time_ms = FORMAT(qsrs.last_clr_time_ms, ''N0''),
        min_clr_time_ms = FORMAT(qsrs.min_clr_time_ms, ''N0''),
        max_clr_time_ms = FORMAT(qsrs.max_clr_time_ms, ''N0''),
        qsrs.last_dop,
        qsrs.min_dop,
        qsrs.max_dop,
        avg_query_max_used_memory_mb = FORMAT(qsrs.avg_query_max_used_memory_mb, ''N0''),
        total_query_max_used_memory_mb = FORMAT(qsrs.total_query_max_used_memory_mb, ''N0''),
        last_query_max_used_memory_mb = FORMAT(qsrs.last_query_max_used_memory_mb, ''N0''),
        min_query_max_used_memory_mb = FORMAT(qsrs.min_query_max_used_memory_mb, ''N0''),
        max_query_max_used_memory_mb = FORMAT(qsrs.max_query_max_used_memory_mb, ''N0''),
        avg_rowcount = FORMAT(qsrs.avg_rowcount, ''N0''),
        total_rowcount = FORMAT(qsrs.total_rowcount, ''N0''),
        last_rowcount = FORMAT(qsrs.last_rowcount, ''N0''),
        min_rowcount = FORMAT(qsrs.min_rowcount, ''N0''),
        max_rowcount = FORMAT(qsrs.max_rowcount, ''N0''),'
        )
        +
            CASE @new
                 WHEN 1
                 THEN
        N'
        avg_num_physical_io_reads_mb = FORMAT(qsrs.avg_num_physical_io_reads_mb, ''N0''),
        total_num_physical_io_reads_mb = FORMAT(qsrs.total_num_physical_io_reads_mb, ''N0''),
        last_num_physical_io_reads_mb = FORMAT(qsrs.last_num_physical_io_reads_mb, ''N0''),
        min_num_physical_io_reads_mb = FORMAT(qsrs.min_num_physical_io_reads_mb, ''N0''),
        max_num_physical_io_reads_mb = FORMAT(qsrs.max_num_physical_io_reads_mb, ''N0''),
        avg_log_bytes_used_mb = FORMAT(qsrs.avg_log_bytes_used_mb, ''N0''),
        total_log_bytes_used_mb = FORMAT(qsrs.total_log_bytes_used_mb, ''N0''),
        last_log_bytes_used_mb = FORMAT(qsrs.last_log_bytes_used_mb, ''N0''),
        min_log_bytes_used_mb = FORMAT(qsrs.min_log_bytes_used_mb, ''N0''),
        max_log_bytes_used_mb = FORMAT(qsrs.max_log_bytes_used_mb, ''N0''),
        avg_tempdb_space_used_mb = FORMAT(qsrs.avg_tempdb_space_used_mb, ''N0''),
        total_tempdb_space_used_mb = FORMAT(qsrs.total_tempdb_space_used_mb, ''N0''),
        last_tempdb_space_used_mb = FORMAT(qsrs.last_tempdb_space_used_mb, ''N0''),
        min_tempdb_space_used_mb = FORMAT(qsrs.min_tempdb_space_used_mb, ''N0''),
        max_tempdb_space_used_mb = FORMAT(qsrs.max_tempdb_space_used_mb, ''N0''),'
                 ELSE
        N''
            END +
            CONVERT
            (
                nvarchar(MAX),
                N'
        qsrs.context_settings,
        n =
            ROW_NUMBER() OVER
            (
                PARTITION BY
                    qsrs.plan_id
                ORDER BY
                    ' +
        CASE @sort_order
            WHEN 'cpu' THEN N'qsrs.avg_cpu_time_ms'
            WHEN 'logical reads' THEN N'qsrs.avg_logical_io_reads_mb'
            WHEN 'physical reads' THEN N'qsrs.avg_physical_io_reads_mb'
            WHEN 'writes' THEN N'qsrs.avg_logical_io_writes_mb'
            WHEN 'duration' THEN N'qsrs.avg_duration_ms'
            WHEN 'memory' THEN N'qsrs.avg_query_max_used_memory_mb'
            WHEN 'tempdb' THEN CASE WHEN @new = 1 THEN N'qsrs.avg_tempdb_space_used_mb' ELSE N'qsrs.avg_cpu_time' END
            WHEN 'executions' THEN N'qsrs.count_executions'
            WHEN 'recent' THEN N'qsrs.last_execution_time'
            ELSE N'qsrs.avg_cpu_time_ms'
        END + N' DESC
            )'
            )
        );
    END; /*End expert mode = 1, format output = 1*/

    /*
    For non-experts only!
    */
    IF
    (
        @expert_mode = 0
    AND @format_output = 0
    )
    BEGIN
        SELECT
            @sql +=
        CONVERT
        (
            nvarchar(MAX),
            N'
    SELECT
        source =
            ''runtime_stats'',
        database_name =
            DB_NAME(qsrs.database_id),
        qsp.query_id,
        qsrs.plan_id,
        qsp.all_plan_ids,'
        +
            CASE
                WHEN @include_plan_hashes IS NOT NULL
                THEN
        N'
        qsp.query_plan_hash,'
                WHEN @include_query_hashes IS NOT NULL
                THEN
        N'
        qsq.query_hash,'
                WHEN @include_sql_handles IS NOT NULL
                THEN
        N'
        qsqt.statement_sql_handle,'
                ELSE
        N''
            END + N'
        qsrs.execution_type_desc,
        qsq.object_name,
        qsqt.query_sql_text,
        query_plan =
             CASE
                 WHEN TRY_CAST(qsp.query_plan AS XML) IS NOT NULL
                 THEN TRY_CAST(qsp.query_plan AS XML)
                 WHEN TRY_CAST(qsp.query_plan AS XML) IS NULL
                 THEN
                     (
                         SELECT
                             [processing-instruction(query_plan)] =
                                 N''-- '' + NCHAR(13) + NCHAR(10) +
                                 N''-- This is a huge query plan.'' + NCHAR(13) + NCHAR(10) +
                                 N''-- Remove the headers and footers, save it as a .sqlplan file, and re-open it.'' + NCHAR(13) + NCHAR(10) +
                                 NCHAR(13) + NCHAR(10) +
                                 REPLACE(qsp.query_plan, N''<RelOp'', NCHAR(13) + NCHAR(10) + N''<RelOp'') +
                                 NCHAR(13) + NCHAR(10) COLLATE Latin1_General_Bin2
                         FOR XML PATH(N''''),
                                 TYPE
                     )
             END,
        qsp.compatibility_level,'
        +
            CASE @sql_2022_views
                 WHEN 1
                 THEN
        N'
        has_query_feedback =
            CASE WHEN EXISTS (SELECT 1/0 FROM #query_store_plan_feedback AS qspf WHERE qspf.plan_id = qsp.plan_id) THEN ''Yes'' ELSE ''No'' END,
        has_query_store_hints =
            CASE WHEN EXISTS (SELECT 1/0 FROM #query_store_query_hints AS qsqh WHERE qsqh.query_id = qsp.query_id) THEN ''Yes'' ELSE ''No'' END,
        has_plan_variants =
            CASE WHEN EXISTS (SELECT 1/0 FROM #query_store_query_variant AS qsqv WHERE qsqv.query_variant_query_id = qsp.query_id) THEN ''Yes'' ELSE ''No'' END,
        qsp.has_compile_replay_script,
        qsp.is_optimized_plan_forcing_disabled,
        qsp.plan_type_desc,'
                 ELSE
        N''
                 END +
        N'
        qsp.force_failure_count,
        qsp.last_force_failure_reason_desc,'
        +
        CONVERT
        (
            nvarchar(MAX),
            CASE @new
                 WHEN 1
                 THEN
        N'
        qsp.plan_forcing_type_desc,
        w.top_waits,'
                 ELSE
        N''
            END
        )
        + N'
        first_execution_time =
            CASE
                WHEN @timezone IS NULL
                THEN
                    DATEADD
                    (
                        MINUTE,
                        @utc_minutes_original,
                        qsrs.first_execution_time
                    )
                WHEN @timezone IS NOT NULL
                THEN qsrs.first_execution_time AT TIME ZONE @timezone
            END,
        first_execution_time_utc =
            qsrs.first_execution_time,
        last_execution_time =
            CASE
                WHEN @timezone IS NULL
                THEN
                    DATEADD
                    (
                        MINUTE,
                        @utc_minutes_original,
                        qsrs.last_execution_time
                    )
                WHEN @timezone IS NOT NULL
                THEN qsrs.last_execution_time AT TIME ZONE @timezone
            END,
        last_execution_time_utc =
            qsrs.last_execution_time,
        qsrs.count_executions,
        qsrs.executions_per_second,
        qsrs.avg_duration_ms,
        qsrs.total_duration_ms,
        qsrs.avg_cpu_time_ms,
        qsrs.total_cpu_time_ms,
        qsrs.avg_logical_io_reads_mb,
        qsrs.total_logical_io_reads_mb,
        qsrs.avg_logical_io_writes_mb,
        qsrs.total_logical_io_writes_mb,
        qsrs.avg_physical_io_reads_mb,
        qsrs.total_physical_io_reads_mb,
        qsrs.avg_clr_time_ms,
        qsrs.total_clr_time_ms,
        qsrs.min_dop,
        qsrs.max_dop,
        qsrs.avg_query_max_used_memory_mb,
        qsrs.total_query_max_used_memory_mb,
        qsrs.avg_rowcount,
        qsrs.total_rowcount,'
        +
            CASE @new
                 WHEN 1
                 THEN
        N'
        qsrs.avg_num_physical_io_reads_mb,
        qsrs.total_num_physical_io_reads_mb,
        qsrs.avg_log_bytes_used_mb,
        qsrs.total_log_bytes_used_mb,
        qsrs.avg_tempdb_space_used_mb,
        qsrs.total_tempdb_space_used_mb,'
                 ELSE
        N''
            END +
            CONVERT
            (
                nvarchar(MAX),
                N'
        qsrs.context_settings,
        n =
            ROW_NUMBER() OVER
            (
                PARTITION BY
                    qsrs.plan_id
                ORDER BY
                    '
        +
        CASE @sort_order
            WHEN 'cpu' THEN N'qsrs.avg_cpu_time_ms'
            WHEN 'logical reads' THEN N'qsrs.avg_logical_io_reads_mb'
            WHEN 'physical reads' THEN N'qsrs.avg_physical_io_reads_mb'
            WHEN 'writes' THEN N'qsrs.avg_logical_io_writes_mb'
            WHEN 'duration' THEN N'qsrs.avg_duration_ms'
            WHEN 'memory' THEN N'qsrs.avg_query_max_used_memory_mb'
            WHEN 'tempdb' THEN CASE WHEN @new = 1 THEN N'qsrs.avg_tempdb_space_used_mb' ELSE N'qsrs.avg_cpu_time' END
            WHEN 'executions' THEN N'qsrs.count_executions'
            WHEN 'recent' THEN N'qsrs.last_execution_time'
            ELSE N'qsrs.avg_cpu_time_ms'
        END + N' DESC
            )'
            )
        );
    END; /*End expert mode = 0, format output = 0*/

    /*
    Formatted but not still not expert output
    */
    IF
    (
        @expert_mode = 0
    AND @format_output = 1
    )
    BEGIN
        SELECT
            @sql +=
        CONVERT
        (
            nvarchar(MAX),
            N'
    SELECT
        source =
            ''runtime_stats'',
        database_name =
            DB_NAME(qsrs.database_id),
        qsp.query_id,
        qsrs.plan_id,
        qsp.all_plan_ids,'
        +
            CASE
                WHEN @include_plan_hashes IS NOT NULL
                THEN
        N'
        qsp.query_plan_hash,'
                WHEN @include_query_hashes IS NOT NULL
                THEN
        N'
        qsq.query_hash,'
                WHEN @include_sql_handles IS NOT NULL
                THEN
        N'
        qsqt.statement_sql_handle,'
                ELSE
        N''
            END
        + N'
        qsrs.execution_type_desc,
        qsq.object_name,
        qsqt.query_sql_text,
        query_plan =
             CASE
                 WHEN TRY_CAST(qsp.query_plan AS XML) IS NOT NULL
                 THEN TRY_CAST(qsp.query_plan AS XML)
                 WHEN TRY_CAST(qsp.query_plan AS XML) IS NULL
                 THEN
                     (
                         SELECT
                             [processing-instruction(query_plan)] =
                                 N''-- '' + NCHAR(13) + NCHAR(10) +
                                 N''-- This is a huge query plan.'' + NCHAR(13) + NCHAR(10) +
                                 N''-- Remove the headers and footers, save it as a .sqlplan file, and re-open it.'' + NCHAR(13) + NCHAR(10) +
                                 NCHAR(13) + NCHAR(10) +
                                 REPLACE(qsp.query_plan, N''<RelOp'', NCHAR(13) + NCHAR(10) + N''<RelOp'') +
                                 NCHAR(13) + NCHAR(10) COLLATE Latin1_General_Bin2
                         FOR XML PATH(N''''),
                                 TYPE
                     )
             END,
        qsp.compatibility_level,'
        +
            CASE @sql_2022_views
                 WHEN 1
                 THEN
        N'
        has_query_feedback =
            CASE WHEN EXISTS (SELECT 1/0 FROM #query_store_plan_feedback AS qspf WHERE qspf.plan_id = qsp.plan_id) THEN ''Yes'' ELSE ''No'' END,
        has_query_store_hints =
            CASE WHEN EXISTS (SELECT 1/0 FROM #query_store_query_hints AS qsqh WHERE qsqh.query_id = qsp.query_id) THEN ''Yes'' ELSE ''No'' END,
        has_plan_variants =
            CASE WHEN EXISTS (SELECT 1/0 FROM #query_store_query_variant AS qsqv WHERE qsqv.query_variant_query_id = qsp.query_id) THEN ''Yes'' ELSE ''No'' END,
        qsp.has_compile_replay_script,
        qsp.is_optimized_plan_forcing_disabled,
        qsp.plan_type_desc,'
                 ELSE
        N''
                 END +
        N'
        qsp.force_failure_count,
        qsp.last_force_failure_reason_desc,'
        +
        CONVERT
        (
            nvarchar(MAX),
            CASE @new
                 WHEN 1
                 THEN
        N'
        qsp.plan_forcing_type_desc,
        w.top_waits,'
                 ELSE
        N''
            END
        )
        + N'
        first_execution_time =
            CASE
                WHEN @timezone IS NULL
                THEN
                    DATEADD
                    (
                        MINUTE,
                        @utc_minutes_original,
                        qsrs.first_execution_time
                    )
                WHEN @timezone IS NOT NULL
                THEN qsrs.first_execution_time AT TIME ZONE @timezone
            END,
        first_execution_time_utc =
            qsrs.first_execution_time,
        last_execution_time =
            CASE
                WHEN @timezone IS NULL
                THEN
                    DATEADD
                    (
                        MINUTE,
                        @utc_minutes_original,
                        qsrs.last_execution_time
                    )
                WHEN @timezone IS NOT NULL
                THEN qsrs.last_execution_time AT TIME ZONE @timezone
            END,
        last_execution_time_utc =
            qsrs.last_execution_time,
        count_executions = FORMAT(qsrs.count_executions, ''N0''),
        executions_per_second = FORMAT(qsrs.executions_per_second, ''N0''),
        avg_duration_ms = FORMAT(qsrs.avg_duration_ms, ''N0''),
        total_duration_ms = FORMAT(qsrs.total_duration_ms, ''N0''),
        avg_cpu_time_ms = FORMAT(qsrs.avg_cpu_time_ms, ''N0''),
        total_cpu_time_ms = FORMAT(qsrs.total_cpu_time_ms, ''N0''),
        avg_logical_io_reads_mb = FORMAT(qsrs.avg_logical_io_reads_mb, ''N0''),
        total_logical_io_reads_mb = FORMAT(qsrs.total_logical_io_reads_mb, ''N0''),
        avg_logical_io_writes_mb = FORMAT(qsrs.avg_logical_io_writes_mb, ''N0''),
        total_logical_io_writes_mb = FORMAT(qsrs.total_logical_io_writes_mb, ''N0''),
        avg_physical_io_reads_mb = FORMAT(qsrs.avg_physical_io_reads_mb, ''N0''),
        total_physical_io_reads_mb = FORMAT(qsrs.total_physical_io_reads_mb, ''N0''),
        avg_clr_time_ms = FORMAT(qsrs.avg_clr_time_ms, ''N0''),
        total_clr_time_ms = FORMAT(qsrs.total_clr_time_ms, ''N0''),
        min_dop = FORMAT(qsrs.min_dop, ''N0''),
        max_dop = FORMAT(qsrs.max_dop, ''N0''),
        avg_query_max_used_memory_mb = FORMAT(qsrs.avg_query_max_used_memory_mb, ''N0''),
        total_query_max_used_memory_mb = FORMAT(qsrs.total_query_max_used_memory_mb, ''N0''),
        avg_rowcount = FORMAT(qsrs.avg_rowcount, ''N0''),
        total_rowcount = FORMAT(qsrs.total_rowcount, ''N0''),'
        +
            CASE @new
                 WHEN 1
                 THEN
        N'
        avg_num_physical_io_reads_mb = FORMAT(qsrs.avg_num_physical_io_reads_mb, ''N0''),
        total_num_physical_io_reads_mb = FORMAT(qsrs.total_num_physical_io_reads_mb, ''N0''),
        avg_log_bytes_used_mb = FORMAT(qsrs.avg_log_bytes_used_mb, ''N0''),
        total_log_bytes_used_mb = FORMAT(qsrs.total_log_bytes_used_mb, ''N0''),
        avg_tempdb_space_used_mb = FORMAT(qsrs.avg_tempdb_space_used_mb, ''N0''),
        total_tempdb_space_used_mb = FORMAT(qsrs.total_tempdb_space_used_mb, ''N0''),'
                 ELSE
        N''
            END +
            CONVERT
            (
                nvarchar(MAX),
                N'
        qsrs.context_settings,
        n =
            ROW_NUMBER() OVER
            (
                PARTITION BY
                    qsrs.plan_id
                ORDER BY
                    '
        +
        CASE @sort_order
             WHEN 'cpu' THEN N'qsrs.avg_cpu_time_ms'
             WHEN 'logical reads' THEN N'qsrs.avg_logical_io_reads_mb'
             WHEN 'physical reads' THEN N'qsrs.avg_physical_io_reads_mb'
             WHEN 'writes' THEN N'qsrs.avg_logical_io_writes_mb'
             WHEN 'duration' THEN N'qsrs.avg_duration_ms'
             WHEN 'memory' THEN N'qsrs.avg_query_max_used_memory_mb'
             WHEN 'tempdb' THEN CASE WHEN @new = 1 THEN N'qsrs.avg_tempdb_space_used_mb' ELSE N'qsrs.avg_cpu_time' END
             WHEN 'executions' THEN N'qsrs.count_executions'
             WHEN 'recent' THEN N'qsrs.last_execution_time'
             ELSE N'qsrs.avg_cpu_time_ms'
        END + N' DESC
            )'
            )
        );
    END; /*End expert mode = 0, format output = 1*/

    /*
    Add on the from and stuff
    */
    SELECT
        @sql +=
    CONVERT
    (
        nvarchar(MAX),
        N'
    FROM #query_store_runtime_stats AS qsrs
    CROSS APPLY
    (
        SELECT
            x.*
        FROM
        (
            SELECT
                qsp.*,
                pn =
                    ROW_NUMBER() OVER
                    (
                        PARTITION BY
                            qsp.query_plan_hash
                        ORDER BY
                            qsp.last_execution_time DESC
                    )
            FROM #query_store_plan AS qsp
            WHERE qsp.plan_id = qsrs.plan_id
            AND   qsp.database_id = qsrs.database_id
        ) AS x
        WHERE x.pn = 1
    ) AS qsp
    CROSS APPLY
    (
        SELECT TOP (1)
            qsqt.*
        FROM #query_store_query AS qsq
        JOIN #query_store_query_text AS qsqt
          ON qsqt.query_text_id = qsq.query_text_id
        WHERE qsq.query_id = qsp.query_id
        AND   qsq.query_id = qsp.query_id
        ORDER BY
            qsq.last_execution_time DESC
    ) AS qsqt
    CROSS APPLY
    (
        SELECT TOP (1)
            qsq.*
        FROM #query_store_query AS qsq
        WHERE qsq.query_id = qsp.query_id
        AND   qsq.database_id = qsp.database_id
        ORDER
            BY qsq.last_execution_time DESC
    ) AS qsq'
    );

    /*
    Get wait stats if we can
    */
    IF
    (
        @new = 1
    AND @format_output = 0
    )
    BEGIN
        SELECT
            @sql +=
        CONVERT
        (
            nvarchar(MAX),
            N'
    CROSS APPLY
    (
        SELECT TOP (1)
            top_waits =
                STUFF
                (
                    (
                       SELECT TOP (5)
                            '', '' +
                            qsws.wait_category_desc +
                            '' ('' +
                            CONVERT
                            (
                                varchar(20),
                                SUM
                                (
                                    CONVERT
                                    (
                                        bigint,
                                        qsws.avg_query_wait_time_ms
                                    )
                                )
                            ) +
                            '' ms)''
                       FROM #query_store_wait_stats AS qsws
                       WHERE qsws.plan_id = qsrs.plan_id
                       AND   qsws.database_id = qsrs.database_id
                       GROUP BY
                           qsws.wait_category_desc
                       ORDER BY
                           SUM(qsws.avg_query_wait_time_ms) DESC
                       FOR XML PATH(''''), TYPE
                    ).value(''./text()[1]'', ''varchar(max)''),
                    1,
                    2,
                    ''''
                )
    ) AS w'
    );
    END; /*End format output = 0 wait stats query*/

    IF
    (
        @new = 1
    AND @format_output = 1
    )
    BEGIN
        SELECT
            @sql +=
        CONVERT
        (
            nvarchar(MAX),
            N'
    CROSS APPLY
    (
        SELECT TOP (1)
            top_waits =
                STUFF
                (
                    (
                       SELECT TOP (5)
                            '', '' +
                            qsws.wait_category_desc +
                            '' ('' +
                            FORMAT
                            (
                                SUM
                                (
                                    CONVERT
                                    (
                                        bigint,
                                        qsws.avg_query_wait_time_ms
                                    )
                                ), ''N0''
                            ) +
                            '' ms)''
                       FROM #query_store_wait_stats AS qsws
                       WHERE qsws.plan_id = qsrs.plan_id
                       AND   qsws.database_id = qsrs.database_id
                       GROUP BY
                           qsws.wait_category_desc
                       ORDER BY
                           SUM(qsws.avg_query_wait_time_ms) DESC
                       FOR XML PATH(''''), TYPE
                    ).value(''./text()[1]'', ''varchar(max)''),
                    1,
                    2,
                    ''''
                )
    ) AS w'
    );
    END; /*End format output = 1 wait stats query*/

    SELECT
        @sql +=
    CONVERT
    (
        nvarchar(MAX),
        N'
) AS x
WHERE x.n = 1
ORDER BY ' +
    CASE @format_output
         WHEN 0
         THEN
             CASE @sort_order
                  WHEN 'cpu' THEN N'x.avg_cpu_time_ms'
                  WHEN 'logical reads' THEN N'x.avg_logical_io_reads_mb'
                  WHEN 'physical reads' THEN N'x.avg_physical_io_reads_mb'
                  WHEN 'writes' THEN N'x.avg_logical_io_writes_mb'
                  WHEN 'duration' THEN N'x.avg_duration_ms'
                  WHEN 'memory' THEN N'x.avg_query_max_used_memory_mb'
                  WHEN 'tempdb' THEN CASE WHEN @new = 1 THEN N'x.avg_tempdb_space_used_mb' ELSE N'x.avg_cpu_time' END
                  WHEN 'executions' THEN N'x.count_executions'
                  WHEN 'recent' THEN N'x.last_execution_time'
                  ELSE N'x.avg_cpu_time_ms'
             END
         WHEN 1
         THEN
             CASE @sort_order
                  WHEN 'cpu' THEN N'CONVERT(money, x.avg_cpu_time_ms)'
                  WHEN 'logical reads' THEN N'CONVERT(money, x.avg_logical_io_reads_mb)'
                  WHEN 'physical reads' THEN N'CONVERT(money, x.avg_physical_io_reads_mb)'
                  WHEN 'writes' THEN N'CONVERT(money, x.avg_logical_io_writes_mb)'
                  WHEN 'duration' THEN N'CONVERT(money, x.avg_duration_ms)'
                  WHEN 'memory' THEN N'CONVERT(money, x.avg_query_max_used_memory_mb)'
                  WHEN 'tempdb' THEN CASE WHEN @new = 1 THEN N'CONVERT(money, x.avg_tempdb_space_used_mb)' ELSE N'CONVERT(money, x.avg_cpu_time)' END
                  WHEN 'executions' THEN N'CONVERT(money, x.count_executions)'
                  WHEN 'recent' THEN N'x.last_execution_time'
                  ELSE N'CONVERT(money, x.avg_cpu_time_ms)'
             END
    END
             + N' DESC
OPTION(RECOMPILE);'
    + @nc10
    );

    IF @debug = 1
    BEGIN
        PRINT LEN(@sql);
        PRINT SUBSTRING(@sql, 0, 4000);
        PRINT SUBSTRING(@sql, 4000, 8000);
        PRINT SUBSTRING(@sql, 8000, 16000);
    END;

    EXEC sys.sp_executesql
        @sql,
      N'@utc_minutes_original bigint,
        @timezone sysname',
        @utc_minutes_original,
        @timezone;
END; /*End runtime stats main query*/
ELSE
    BEGIN
        SELECT
            result =
                '#query_store_runtime_stats is empty';
    END;

/*
Return special things, unformatted
*/
IF
(
    (
         @expert_mode = 1
      OR
      (
           @only_queries_with_hints = 1
        OR @only_queries_with_feedback = 1
        OR @only_queries_with_variants = 1
      )
    )
AND @format_output = 0
)
BEGIN
    IF @sql_2022_views = 1
    BEGIN
        IF @expert_mode = 1
        BEGIN
            IF EXISTS
            (
                SELECT
                    1/0
                FROM #query_store_plan_feedback AS qspf
            )
            BEGIN
                SELECT
                    @current_table = 'selecting plan feedback';

                SELECT
                    database_name =
                        DB_NAME(qspf.database_id),
                    qspf.plan_feedback_id,
                    qspf.plan_id,
                    qspf.feature_desc,
                    qspf.feedback_data,
                    qspf.state_desc,
                    create_time =
                        CASE
                            WHEN @timezone IS NULL
                            THEN
                                DATEADD
                                (
                                    MINUTE,
                                    @utc_minutes_original,
                                    qspf.create_time
                                )
                            WHEN @timezone IS NOT NULL
                            THEN qspf.create_time AT TIME ZONE @timezone
                        END,
                    create_time_utc =
                        qspf.create_time,
                    last_updated_time =
                        CASE
                            WHEN @timezone IS NULL
                            THEN
                                DATEADD
                                (
                                    MINUTE,
                                    @utc_minutes_original,
                                    qspf.last_updated_time
                                )
                            WHEN @timezone IS NOT NULL
                            THEN qspf.last_updated_time AT TIME ZONE @timezone
                        END,
                    last_updated_time_utc =
                        qspf.last_updated_time
                FROM #query_store_plan_feedback AS qspf
                ORDER BY
                    qspf.plan_id
                OPTION(RECOMPILE);
            END;
            ELSE
            BEGIN
                SELECT
                    result = '#query_store_plan_feedback is empty';
            END;
        END;

        IF EXISTS
        (
            SELECT
                1/0
            FROM #query_store_query_hints AS qsqh
        )
        BEGIN
            SELECT
                @current_table = 'selecting query hints';

            SELECT
                database_name =
                    DB_NAME(qsqh.database_id),
                qsqh.query_hint_id,
                qsqh.query_id,
                qsqh.query_hint_text,
                qsqh.last_query_hint_failure_reason_desc,
                qsqh.query_hint_failure_count,
                qsqh.source_desc
            FROM #query_store_query_hints AS qsqh
            ORDER BY
                qsqh.query_id
            OPTION(RECOMPILE);
        END;
        ELSE
        BEGIN
            SELECT
                result = '#query_store_query_hints is empty';
        END;

        IF @expert_mode = 1
        BEGIN
            IF EXISTS
            (
                SELECT
                    1/0
                FROM #query_store_query_variant AS qsqv
            )
            BEGIN
                SELECT
                    @current_table = 'selecting query variants';

                SELECT
                    database_name =
                        DB_NAME(qsqv.database_id),
                    qsqv.query_variant_query_id,
                    qsqv.parent_query_id,
                    qsqv.dispatcher_plan_id
                FROM #query_store_query_variant AS qsqv
                ORDER BY
                    qsqv.parent_query_id
                OPTION(RECOMPILE);
            END;
            ELSE
            BEGIN
                SELECT
                    result = '#query_store_query_variant is empty';
            END;
        END;
    END;

    IF @expert_mode = 1
    BEGIN
        IF EXISTS
        (
            SELECT
                1/0
                FROM #query_store_query AS qsq
        )
        BEGIN
            SELECT
                @current_table = 'selecting compilation stats';

            SELECT
                x.*
            FROM
            (
                SELECT
                    source =
                        'compilation_stats',
                    database_name =
                        DB_NAME(qsq.database_id),
                    qsq.query_id,
                    qsq.object_name,
                    qsq.query_text_id,
                    qsq.query_parameterization_type_desc,
                    initial_compile_start_time =
                        CASE
                            WHEN @timezone IS NULL
                            THEN
                                DATEADD
                                (
                                    MINUTE,
                                    @utc_minutes_original,
                                    qsq.initial_compile_start_time
                                )
                            WHEN @timezone IS NOT NULL
                            THEN qsq.initial_compile_start_time AT TIME ZONE @timezone
                        END,
                    initial_compile_start_time_utc =
                        qsq.initial_compile_start_time,
                    last_compile_start_time =
                        CASE
                            WHEN @timezone IS NULL
                            THEN
                                DATEADD
                                (
                                    MINUTE,
                                    @utc_minutes_original,
                                    qsq.last_compile_start_time
                                )
                            WHEN @timezone IS NOT NULL
                            THEN qsq.last_compile_start_time AT TIME ZONE @timezone
                        END,
                    last_compile_start_time_utc =
                        qsq.last_compile_start_time,
                    last_execution_time =
                        CASE
                            WHEN @timezone IS NULL
                            THEN
                                DATEADD
                                (
                                    MINUTE,
                                    @utc_minutes_original,
                                    qsq.last_execution_time
                                )
                            WHEN @timezone IS NOT NULL
                            THEN qsq.last_execution_time AT TIME ZONE @timezone
                        END,
                    last_execution_time_utc =
                        qsq.last_execution_time,
                    qsq.count_compiles,
                    qsq.avg_compile_duration_ms,
                    qsq.total_compile_duration_ms,
                    qsq.last_compile_duration_ms,
                    qsq.avg_bind_duration_ms,
                    qsq.total_bind_duration_ms,
                    qsq.last_bind_duration_ms,
                    qsq.avg_bind_cpu_time_ms,
                    qsq.total_bind_cpu_time_ms,
                    qsq.last_bind_cpu_time_ms,
                    qsq.avg_optimize_duration_ms,
                    qsq.total_optimize_duration_ms,
                    qsq.last_optimize_duration_ms,
                    qsq.avg_optimize_cpu_time_ms,
                    qsq.total_optimize_cpu_time_ms,
                    qsq.last_optimize_cpu_time_ms,
                    qsq.avg_compile_memory_mb,
                    qsq.total_compile_memory_mb,
                    qsq.last_compile_memory_mb,
                    qsq.max_compile_memory_mb,
                    qsq.query_hash,
                    qsq.batch_sql_handle,
                    qsqt.statement_sql_handle,
                    qsq.last_compile_batch_sql_handle,
                    qsq.last_compile_batch_offset_start,
                    qsq.last_compile_batch_offset_end,
                    ROW_NUMBER() OVER
                    (
                        PARTITION BY
                            qsq.query_id,
                            qsq.query_text_id
                        ORDER BY
                            qsq.query_id
                    ) AS n
                FROM #query_store_query AS qsq
                CROSS APPLY
                (
                    SELECT TOP (1)
                        qsqt.*
                    FROM #query_store_query_text AS qsqt
                    WHERE qsqt.query_text_id = qsq.query_text_id
                    AND   qsqt.database_id = qsq.database_id
                ) AS qsqt
            ) AS x
            WHERE x.n = 1
            ORDER BY
                x.query_id
            OPTION(RECOMPILE);

        END; /*End compilation stats query*/
        ELSE
        BEGIN
            SELECT
                result =
                    '#query_store_query is empty';
        END;
    END;

    IF @expert_mode = 1
    BEGIN
        IF @rc > 0
        BEGIN
            SELECT
                @current_table = 'selecting resource stats';

            SELECT
                source =
                    'resource_stats',
                database_name =
                    DB_NAME(qsq.database_id),
                qsq.query_id,
                qsq.object_name,
                qsqt.total_grant_mb,
                qsqt.last_grant_mb,
                qsqt.min_grant_mb,
                qsqt.max_grant_mb,
                qsqt.total_used_grant_mb,
                qsqt.last_used_grant_mb,
                qsqt.min_used_grant_mb,
                qsqt.max_used_grant_mb,
                qsqt.total_ideal_grant_mb,
                qsqt.last_ideal_grant_mb,
                qsqt.min_ideal_grant_mb,
                qsqt.max_ideal_grant_mb,
                qsqt.total_reserved_threads,
                qsqt.last_reserved_threads,
                qsqt.min_reserved_threads,
                qsqt.max_reserved_threads,
                qsqt.total_used_threads,
                qsqt.last_used_threads,
                qsqt.min_used_threads,
                qsqt.max_used_threads
            FROM #query_store_query AS qsq
            JOIN #query_store_query_text AS qsqt
            ON  qsq.query_text_id = qsqt.query_text_id
            AND qsq.database_id = qsqt.database_id
            WHERE
            (
                qsqt.total_grant_mb IS NOT NULL
            OR qsqt.total_reserved_threads IS NOT NULL
            )
            ORDER BY
                qsq.query_id
            OPTION(RECOMPILE);

        END; /*End resource stats query*/
        ELSE
        BEGIN
            SELECT
                result =
                    '#dm_exec_query_stats is empty';
        END;
    END;

    IF @new = 1
    BEGIN
        IF @expert_mode = 1
        BEGIN
            IF EXISTS
            (
                SELECT
                    1/0
                    FROM #query_store_wait_stats AS qsws
            )
            BEGIN
                SELECT
                    @current_table = 'selecting wait stats by query';

                SELECT DISTINCT
                    source =
                        'query_store_wait_stats_by_query',
                    database_name =
                        DB_NAME(qsws.database_id),
                    qsws.plan_id,
                    x.object_name,
                    qsws.wait_category_desc,
                    qsws.total_query_wait_time_ms,
                    total_query_duration_ms =
                        x.total_duration_ms,
                    qsws.avg_query_wait_time_ms,
                    avg_query_duration_ms =
                        x.avg_duration_ms,
                    qsws.last_query_wait_time_ms,
                    last_query_duration_ms =
                        x.last_duration_ms,
                    qsws.min_query_wait_time_ms,
                    min_query_duration_ms =
                        x.min_duration_ms,
                    qsws.max_query_wait_time_ms,
                    max_query_duration_ms =
                        x.max_duration_ms
                FROM #query_store_wait_stats AS qsws
                CROSS APPLY
                (
                    SELECT
                        qsrs.avg_duration_ms,
                        qsrs.last_duration_ms,
                        qsrs.min_duration_ms,
                        qsrs.max_duration_ms,
                        qsrs.total_duration_ms,
                        qsq.object_name
                    FROM #query_store_runtime_stats AS qsrs
                    JOIN #query_store_plan AS qsp
                    ON  qsrs.plan_id = qsp.plan_id
                    AND qsrs.database_id = qsp.database_id
                    JOIN #query_store_query AS qsq
                    ON  qsp.query_id = qsq.query_id
                    AND qsp.database_id = qsq.database_id
                    WHERE qsws.plan_id = qsrs.plan_id
                    AND   qsws.database_id = qsrs.database_id
                ) AS x
                ORDER BY
                    qsws.plan_id,
                    qsws.total_query_wait_time_ms DESC
                OPTION(RECOMPILE);

                SELECT
                    @current_table = 'selecting wait stats in total';

                SELECT
                    source =
                        'query_store_wait_stats_total',
                    database_name =
                        DB_NAME(qsws.database_id),
                    qsws.wait_category_desc,
                    total_query_wait_time_ms =
                        SUM(qsws.total_query_wait_time_ms),
                    total_query_duration_ms =
                        SUM(x.total_duration_ms),
                    avg_query_wait_time_ms =
                        SUM(qsws.avg_query_wait_time_ms),
                    avg_query_duration_ms =
                        SUM(x.avg_duration_ms),
                    last_query_wait_time_ms =
                        SUM(qsws.last_query_wait_time_ms),
                    last_query_duration_ms =
                        SUM(x.last_duration_ms),
                    min_query_wait_time_ms =
                        SUM(qsws.min_query_wait_time_ms),
                    min_query_duration_ms =
                        SUM(x.min_duration_ms),
                    max_query_wait_time_ms =
                        SUM(qsws.max_query_wait_time_ms),
                    max_query_duration_ms =
                        SUM(x.max_duration_ms)
                FROM #query_store_wait_stats AS qsws
                CROSS APPLY
                (
                    SELECT
                        qsrs.avg_duration_ms,
                        qsrs.last_duration_ms,
                        qsrs.min_duration_ms,
                        qsrs.max_duration_ms,
                        qsrs.total_duration_ms,
                        qsq.object_name
                    FROM #query_store_runtime_stats AS qsrs
                    JOIN #query_store_plan AS qsp
                    ON  qsrs.plan_id = qsp.plan_id
                    AND qsrs.database_id = qsp.database_id
                    JOIN #query_store_query AS qsq
                    ON  qsp.query_id = qsq.query_id
                    AND qsp.database_id = qsq.database_id
                    WHERE qsws.plan_id = qsrs.plan_id
                ) AS x
                GROUP BY
                    qsws.wait_category_desc,
                    qsws.database_id
                ORDER BY
                    SUM(qsws.total_query_wait_time_ms) DESC
                OPTION(RECOMPILE);

            END; /*End unformatted wait stats*/
            ELSE
            BEGIN
                SELECT
                    result =
                        '#query_store_wait_stats is empty' +
                        CASE
                            WHEN
                            (
                                    @product_version = 13
                                AND @azure = 0
                            )
                            THEN ' because it''s not available < 2017'
                            WHEN EXISTS
                                (
                                    SELECT
                                        1/0
                                    FROM #database_query_store_options AS dqso
                                    WHERE dqso.wait_stats_capture_mode_desc <> 'ON'
                                )
                            THEN ' because you have it disabled in your Query Store options'
                            ELSE ' for the queries in the results'
                        END;
            END;
        END;
    END; /*End wait stats queries*/

    IF
    (
        @sql_2022_views = 1
    AND @ags_present = 1
    )
    BEGIN
        IF @expert_mode = 1
        BEGIN
            IF EXISTS
            (
                SELECT
                    1/0
                FROM #query_store_replicas AS qsr
                JOIN #query_store_plan_forcing_locations AS qspfl
                    ON  qsr.replica_group_id = qspfl.replica_group_id
                    AND qsr.database_id = qspfl.database_id
            )
            BEGIN
                SELECT
                    @current_table = 'selecting #query_store_replicas and #query_store_plan_forcing_locations';

                SELECT
                    database_name =
                        DB_NAME(qsr.database_id),
                    qsr.replica_group_id,
                    qsr.role_type,
                    qsr.replica_name,
                    qspfl.plan_forcing_location_id,
                    qspfl.query_id,
                    qspfl.plan_id,
                    qspfl.replica_group_id
                FROM #query_store_replicas AS qsr
                JOIN #query_store_plan_forcing_locations AS qspfl
                ON qsr.replica_group_id = qspfl.replica_group_id
                ORDER BY
                    qsr.replica_group_id;
            END;
            ELSE
                BEGIN
                    SELECT
                        result = 'Availability Group information is empty';
            END;
        END;
    END;

    IF @expert_mode = 1
    BEGIN
        SELECT
            @current_table = 'selecting query store options',
            @sql = N'';

        SELECT
            @sql +=
        CONVERT
        (
            nvarchar(MAX),
            N'
        SELECT
            source =
                ''query_store_options'',
            database_name =
                DB_NAME(dqso.database_id),
            dqso.desired_state_desc,
            dqso.actual_state_desc,
            dqso.readonly_reason,
            dqso.current_storage_size_mb,
            dqso.flush_interval_seconds,
            dqso.interval_length_minutes,
            dqso.max_storage_size_mb,
            dqso.stale_query_threshold_days,
            dqso.max_plans_per_query,
            dqso.query_capture_mode_desc,'
            +
            CASE
                WHEN
                (
                    @azure = 1
                OR @product_version > 13
                )
                THEN N'
            dqso.wait_stats_capture_mode_desc,'
                ELSE N''
            END
            +
            CASE
                WHEN
                (
                    @azure = 1
                OR @product_version > 14
                )
                THEN N'
            dqso.capture_policy_execution_count,
            dqso.capture_policy_total_compile_cpu_time_ms,
            dqso.capture_policy_total_execution_cpu_time_ms,
            dqso.capture_policy_stale_threshold_hours,'
                ELSE N''
            END
        );

        SELECT
            @sql +=
        CONVERT
        (
            nvarchar(MAX),
            N'
        dqso.size_based_cleanup_mode_desc
        FROM #database_query_store_options AS dqso
        OPTION(RECOMPILE);'
        );

        IF @debug = 1
        BEGIN
            PRINT LEN(@sql);
            PRINT @sql;
        END;

        EXEC sys.sp_executesql
            @sql;
    END;
END; /*End expert mode format output = 0*/

/*
Return special things, formatted
*/
IF
(
    (
        @expert_mode = 1
      OR
      (
           @only_queries_with_hints = 1
        OR @only_queries_with_feedback = 1
        OR @only_queries_with_variants = 1
      )
    )
AND @format_output = 1
)
BEGIN
    IF @sql_2022_views = 1
    BEGIN
        IF @expert_mode = 1
        BEGIN
            IF EXISTS
               (
                   SELECT
                       1/0
                   FROM #query_store_plan_feedback AS qspf
               )
            BEGIN
                SELECT
                    @current_table = 'selecting plan feedback';

                SELECT
                    database_name =
                        DB_NAME(qspf.database_id),
                    qspf.plan_feedback_id,
                    qspf.plan_id,
                    qspf.feature_desc,
                    qspf.feedback_data,
                    qspf.state_desc,
                    create_time =
                        CASE
                            WHEN @timezone IS NULL
                            THEN
                                DATEADD
                                (
                                    MINUTE,
                                    @utc_minutes_original,
                                    qspf.create_time
                                )
                            WHEN @timezone IS NOT NULL
                            THEN qspf.create_time AT TIME ZONE @timezone
                        END,
                    create_time_utc =
                        qspf.create_time,
                    last_updated_time =
                        CASE
                            WHEN @timezone IS NULL
                            THEN
                                DATEADD
                                (
                                    MINUTE,
                                    @utc_minutes_original,
                                    qspf.last_updated_time
                                )
                            WHEN @timezone IS NOT NULL
                            THEN qspf.last_updated_time AT TIME ZONE @timezone
                        END,
                    last_updated_time_utc =
                        qspf.last_updated_time
                FROM #query_store_plan_feedback AS qspf
                ORDER BY
                    qspf.plan_id
                OPTION(RECOMPILE);
            END;
            ELSE
            BEGIN
                SELECT
                    result = '#query_store_plan_feedback is empty';
            END;
        END

        IF EXISTS
           (
               SELECT
                   1/0
               FROM #query_store_query_hints AS qsqh
           )
        BEGIN
            SELECT
                @current_table = 'selecting query hints';

            SELECT
                database_name =
                    DB_NAME(qsqh.database_id),
                qsqh.query_hint_id,
                qsqh.query_id,
                qsqh.query_hint_text,
                qsqh.last_query_hint_failure_reason_desc,
                qsqh.query_hint_failure_count,
                qsqh.source_desc
            FROM #query_store_query_hints AS qsqh
            ORDER BY
                qsqh.query_id
            OPTION(RECOMPILE);
        END;
        ELSE
        BEGIN
            SELECT
                result = '#query_store_query_hints is empty';
        END;

        IF @expert_mode = 1
        BEGIN
            IF EXISTS
               (
                   SELECT
                       1/0
                   FROM #query_store_query_variant AS qsqv
               )
            BEGIN
                SELECT
                    @current_table = 'selecting query variants';

                SELECT
                    database_name =
                        DB_NAME(qsqv.database_id),
                    qsqv.query_variant_query_id,
                    qsqv.parent_query_id,
                    qsqv.dispatcher_plan_id
                FROM #query_store_query_variant AS qsqv
                ORDER BY
                    qsqv.parent_query_id
                OPTION(RECOMPILE);
            END;
            ELSE
            BEGIN
                SELECT
                    result = '#query_store_query_variant is empty';
            END;
        END;
    END;

    IF @expert_mode = 1
    BEGIN
        IF EXISTS
           (
              SELECT
                  1/0
              FROM #query_store_query AS qsq
           )
        BEGIN
            SELECT
                @current_table = 'selecting compilation stats';

            SELECT
                x.*
            FROM
            (
                SELECT
                    source =
                        'compilation_stats',
                    database_name =
                        DB_NAME(qsq.database_id),
                    qsq.query_id,
                    qsq.object_name,
                    qsq.query_text_id,
                    qsq.query_parameterization_type_desc,
                    initial_compile_start_time =
                        CASE
                            WHEN @timezone IS NULL
                            THEN
                                DATEADD
                                (
                                    MINUTE,
                                    @utc_minutes_original,
                                    qsq.initial_compile_start_time
                                )
                            WHEN @timezone IS NOT NULL
                            THEN qsq.initial_compile_start_time AT TIME ZONE @timezone
                        END,
                    initial_compile_start_time_utc =
                        qsq.initial_compile_start_time,
                    last_compile_start_time =
                        CASE
                            WHEN @timezone IS NULL
                            THEN
                                DATEADD
                                (
                                    MINUTE,
                                    @utc_minutes_original,
                                    qsq.last_compile_start_time
                                )
                            WHEN @timezone IS NOT NULL
                            THEN qsq.last_compile_start_time AT TIME ZONE @timezone
                        END,
                    last_compile_start_time_utc =
                        qsq.last_compile_start_time,
                    last_execution_time =
                        CASE
                            WHEN @timezone IS NULL
                            THEN
                                DATEADD
                                (
                                    MINUTE,
                                    @utc_minutes_original,
                                    qsq.last_execution_time
                                )
                            WHEN @timezone IS NOT NULL
                            THEN qsq.last_execution_time AT TIME ZONE @timezone
                        END,
                    last_execution_time_utc =
                        qsq.last_execution_time,
                    count_compiles =
                        FORMAT(qsq.count_compiles, 'N0'),
                    avg_compile_duration_ms =
                        FORMAT(qsq.avg_compile_duration_ms, 'N0'),
                    total_compile_duration_ms =
                        FORMAT(qsq.total_compile_duration_ms, 'N0'),
                    last_compile_duration_ms =
                        FORMAT(qsq.last_compile_duration_ms, 'N0'),
                    avg_bind_duration_ms =
                        FORMAT(qsq.avg_bind_duration_ms, 'N0'),
                    total_bind_duration_ms =
                        FORMAT(qsq.total_bind_duration_ms, 'N0'),
                    last_bind_duration_ms =
                        FORMAT(qsq.last_bind_duration_ms, 'N0'),
                    avg_bind_cpu_time_ms =
                        FORMAT(qsq.avg_bind_cpu_time_ms, 'N0'),
                    total_bind_cpu_time_ms =
                        FORMAT(qsq.total_bind_cpu_time_ms, 'N0'),
                    last_bind_cpu_time_ms =
                        FORMAT(qsq.last_bind_cpu_time_ms, 'N0'),
                    avg_optimize_duration_ms =
                        FORMAT(qsq.avg_optimize_duration_ms, 'N0'),
                    total_optimize_duration_ms =
                        FORMAT(qsq.total_optimize_duration_ms, 'N0'),
                    last_optimize_duration_ms =
                        FORMAT(qsq.last_optimize_duration_ms, 'N0'),
                    avg_optimize_cpu_time_ms =
                        FORMAT(qsq.avg_optimize_cpu_time_ms, 'N0'),
                    total_optimize_cpu_time_ms =
                        FORMAT(qsq.total_optimize_cpu_time_ms, 'N0'),
                    last_optimize_cpu_time_ms =
                        FORMAT(qsq.last_optimize_cpu_time_ms, 'N0'),
                    avg_compile_memory_mb =
                        FORMAT(qsq.avg_compile_memory_mb, 'N0'),
                    total_compile_memory_mb =
                        FORMAT(qsq.total_compile_memory_mb, 'N0'),
                    last_compile_memory_mb =
                        FORMAT(qsq.last_compile_memory_mb, 'N0'),
                    max_compile_memory_mb =
                        FORMAT(qsq.max_compile_memory_mb, 'N0'),
                    qsq.query_hash,
                    qsq.batch_sql_handle,
                    qsqt.statement_sql_handle,
                    qsq.last_compile_batch_sql_handle,
                    qsq.last_compile_batch_offset_start,
                    qsq.last_compile_batch_offset_end,
                    ROW_NUMBER() OVER
                    (
                        PARTITION BY
                            qsq.query_id,
                            qsq.query_text_id
                        ORDER BY
                            qsq.query_id
                    ) AS n
                FROM #query_store_query AS qsq
                CROSS APPLY
                (
                    SELECT TOP (1)
                        qsqt.*
                    FROM #query_store_query_text AS qsqt
                    WHERE qsqt.query_text_id = qsq.query_text_id
                    AND   qsqt.database_id = qsq.database_id
                ) AS qsqt
            ) AS x
            WHERE x.n = 1
            ORDER BY
                x.query_id
            OPTION(RECOMPILE);

        END; /*End query store query, format output = 1*/
        ELSE
        BEGIN
            SELECT
                result =
                    '#query_store_query is empty';
        END;
    END;

    IF @expert_mode = 1
    BEGIN
        IF @rc > 0
        BEGIN
            SELECT
                @current_table = 'selecting resource stats';

            SELECT
                source =
                    'resource_stats',
                database_name =
                    DB_NAME(qsq.database_id),
                qsq.query_id,
                qsq.object_name,
                total_grant_mb =
                    FORMAT(qsqt.total_grant_mb, 'N0'),
                last_grant_mb =
                    FORMAT(qsqt.last_grant_mb, 'N0'),
                min_grant_mb =
                    FORMAT(qsqt.min_grant_mb, 'N0'),
                max_grant_mb =
                    FORMAT(qsqt.max_grant_mb, 'N0'),
                total_used_grant_mb =
                    FORMAT(qsqt.total_used_grant_mb, 'N0'),
                last_used_grant_mb =
                    FORMAT(qsqt.last_used_grant_mb, 'N0'),
                min_used_grant_mb =
                    FORMAT(qsqt.min_used_grant_mb, 'N0'),
                max_used_grant_mb =
                    FORMAT(qsqt.max_used_grant_mb, 'N0'),
                total_ideal_grant_mb =
                    FORMAT(qsqt.total_ideal_grant_mb, 'N0'),
                last_ideal_grant_mb =
                    FORMAT(qsqt.last_ideal_grant_mb, 'N0'),
                min_ideal_grant_mb =
                    FORMAT(qsqt.min_ideal_grant_mb, 'N0'),
                max_ideal_grant_mb =
                    FORMAT(qsqt.max_ideal_grant_mb, 'N0'),
                qsqt.total_reserved_threads,
                qsqt.last_reserved_threads,
                qsqt.min_reserved_threads,
                qsqt.max_reserved_threads,
                qsqt.total_used_threads,
                qsqt.last_used_threads,
                qsqt.min_used_threads,
                qsqt.max_used_threads
            FROM #query_store_query AS qsq
            JOIN #query_store_query_text AS qsqt
              ON  qsq.query_text_id = qsqt.query_text_id
              AND qsq.database_id = qsqt.database_id
            WHERE
            (
                 qsqt.total_grant_mb IS NOT NULL
              OR qsqt.total_reserved_threads IS NOT NULL
            )
            ORDER BY
                qsq.query_id
            OPTION(RECOMPILE);

        END; /*End resource stats, format output = 1*/
        ELSE
        BEGIN
            SELECT
                result =
                    '#dm_exec_query_stats is empty';
        END;
    END;

    IF @new = 1
    BEGIN
        IF EXISTS
           (
               SELECT
                   1/0
                FROM #query_store_wait_stats AS qsws
           )
        AND @expert_mode = 1
        BEGIN
            SELECT
                @current_table = 'selecting wait stats by query';

            SELECT
                source =
                    'query_store_wait_stats_by_query',
                database_name =
                    DB_NAME(qsws.database_id),
                qsws.plan_id,
                x.object_name,
                qsws.wait_category_desc,
                total_query_wait_time_ms =
                    FORMAT(qsws.total_query_wait_time_ms, 'N0'),
                total_query_duration_ms =
                    FORMAT(x.total_duration_ms, 'N0'),
                avg_query_wait_time_ms =
                    FORMAT(qsws.avg_query_wait_time_ms, 'N0'),
                avg_query_duration_ms =
                    FORMAT(x.avg_duration_ms, 'N0'),
                last_query_wait_time_ms =
                    FORMAT(qsws.last_query_wait_time_ms, 'N0'),
                last_query_duration_ms =
                    FORMAT(x.last_duration_ms, 'N0'),
                min_query_wait_time_ms =
                    FORMAT(qsws.min_query_wait_time_ms, 'N0'),
                min_query_duration_ms =
                    FORMAT(x.min_duration_ms, 'N0'),
                max_query_wait_time_ms =
                    FORMAT(qsws.max_query_wait_time_ms, 'N0'),
                max_query_duration_ms =
                    FORMAT(x.max_duration_ms, 'N0')
            FROM #query_store_wait_stats AS qsws
            CROSS APPLY
            (
                SELECT DISTINCT
                    qsrs.avg_duration_ms,
                    qsrs.last_duration_ms,
                    qsrs.min_duration_ms,
                    qsrs.max_duration_ms,
                    qsrs.total_duration_ms,
                    qsq.object_name
                FROM #query_store_runtime_stats AS qsrs
                JOIN #query_store_plan AS qsp
                  ON  qsrs.plan_id = qsp.plan_id
                  AND qsrs.database_id = qsp.database_id
                JOIN #query_store_query AS qsq
                  ON  qsp.query_id = qsq.query_id
                  AND qsp.database_id = qsq.database_id
                WHERE qsws.plan_id = qsrs.plan_id
                AND   qsws.database_id = qsrs.database_id
            ) AS x
            ORDER BY
                qsws.plan_id,
                qsws.total_query_wait_time_ms DESC
            OPTION(RECOMPILE);

            SELECT
                @current_table = 'selecting wait stats in total';

            SELECT
                source =
                    'query_store_wait_stats_total',
                database_name =
                    DB_NAME(qsws.database_id),
                qsws.wait_category_desc,
                total_query_wait_time_ms =
                    FORMAT(SUM(qsws.total_query_wait_time_ms), 'N0'),
                total_query_duration_ms =
                    FORMAT(SUM(x.total_duration_ms), 'N0'),
                avg_query_wait_time_ms =
                    FORMAT(SUM(qsws.avg_query_wait_time_ms), 'N0'),
                avg_query_duration_ms =
                    FORMAT(SUM(x.avg_duration_ms), 'N0'),
                last_query_wait_time_ms =
                    FORMAT(SUM(qsws.last_query_wait_time_ms), 'N0'),
                last_query_duration_ms =
                    FORMAT(SUM(x.last_duration_ms), 'N0'),
                min_query_wait_time_ms =
                    FORMAT(SUM(qsws.min_query_wait_time_ms), 'N0'),
                min_query_duration_ms =
                    FORMAT(SUM(x.min_duration_ms), 'N0'),
                max_query_wait_time_ms =
                    FORMAT(SUM(qsws.max_query_wait_time_ms), 'N0'),
                max_query_duration_ms =
                    FORMAT(SUM(x.max_duration_ms), 'N0')
            FROM #query_store_wait_stats AS qsws
            CROSS APPLY
            (
                SELECT
                    qsrs.avg_duration_ms,
                    qsrs.last_duration_ms,
                    qsrs.min_duration_ms,
                    qsrs.max_duration_ms,
                    qsrs.total_duration_ms,
                    qsq.object_name
                FROM #query_store_runtime_stats AS qsrs
                JOIN #query_store_plan AS qsp
                  ON  qsrs.plan_id = qsp.plan_id
                  AND qsrs.database_id = qsp.database_id
                JOIN #query_store_query AS qsq
                  ON  qsp.query_id = qsq.query_id
                  AND qsp.database_id = qsq.database_id
                WHERE qsws.plan_id = qsrs.plan_id
                AND   qsws.database_id = qsrs.database_id
            ) AS x
            GROUP BY
                qsws.wait_category_desc,
                qsws.database_id
            ORDER BY
                SUM(qsws.total_query_wait_time_ms) DESC
            OPTION(RECOMPILE);

        END;

    END; /*End wait stats, format output = 1*/
    ELSE
    BEGIN
        SELECT
            result =
                '#query_store_wait_stats is empty' +
                CASE
                    WHEN (
                             @product_version = 13
                         AND @azure = 0
                         )
                    THEN ' because it''s not available < 2017'
                    WHEN EXISTS
                         (
                             SELECT
                                 1/0
                             FROM #database_query_store_options AS dqso
                             WHERE dqso.wait_stats_capture_mode_desc <> 'ON'
                         )
                    THEN ' because you have it disabled in your Query Store options'
                    ELSE ' for the queries in the results'
                END;
    END;

    IF
    (
        @sql_2022_views = 1
    AND @ags_present = 1
    )
    BEGIN
        IF @expert_mode = 1
        BEGIN
            IF EXISTS
            (
                SELECT
                    1/0
                FROM #query_store_replicas AS qsr
                JOIN #query_store_plan_forcing_locations AS qspfl
                    ON  qsr.replica_group_id = qspfl.replica_group_id
                    AND qsr.replica_group_id = qspfl.database_id
            )
            BEGIN
                SELECT
                    @current_table = '#query_store_replicas and #query_store_plan_forcing_locations';

                SELECT
                    database_name =
                        DB_NAME(qsr.database_id),
                    qsr.replica_group_id,
                    qsr.role_type,
                    qsr.replica_name,
                    qspfl.plan_forcing_location_id,
                    qspfl.query_id,
                    qspfl.plan_id,
                    qspfl.replica_group_id
                FROM #query_store_replicas AS qsr
                JOIN #query_store_plan_forcing_locations AS qspfl
                ON  qsr.replica_group_id = qspfl.replica_group_id
                AND qsr.database_id = qspfl.database_id
                ORDER BY
                    qsr.replica_group_id
                OPTION(RECOMPILE);
            END;
            ELSE
            BEGIN
                SELECT
                    result = 'Availability Group information is empty';
            END;
        END;
    END;

    IF @expert_mode = 1
    BEGIN
        SELECT
            @current_table = 'selecting query store options',
            @sql = N'';

        SELECT
            @sql +=
        CONVERT
        (
            nvarchar(MAX),
            N'
        SELECT
            source =
                ''query_store_options'',
            database_name =
                DB_NAME(dqso.database_id),
            dqso.desired_state_desc,
            dqso.actual_state_desc,
            dqso.readonly_reason,
            current_storage_size_mb =
                FORMAT(dqso.current_storage_size_mb, ''N0''),
            flush_interval_seconds =
                FORMAT(dqso.flush_interval_seconds, ''N0''),
            interval_length_minutes =
                FORMAT(dqso.interval_length_minutes, ''N0''),
            max_storage_size_mb =
                FORMAT(dqso.max_storage_size_mb, ''N0''),
            dqso.stale_query_threshold_days,
            max_plans_per_query =
                FORMAT(dqso.max_plans_per_query, ''N0''),
            dqso.query_capture_mode_desc,'
            +
            CASE
                WHEN
                (
                    @azure = 1
                    OR @product_version > 13
                )
                THEN N'
            dqso.wait_stats_capture_mode_desc,'
                ELSE N''
            END
            +
            CASE
                WHEN
                (
                     @azure = 1
                  OR @product_version > 14
                )
                THEN N'
            capture_policy_execution_count =
                FORMAT(dqso.capture_policy_execution_count, ''N0''),
            capture_policy_total_compile_cpu_time_ms =
                FORMAT(dqso.capture_policy_total_compile_cpu_time_ms, ''N0''),
            capture_policy_total_execution_cpu_time_ms =
               FORMAT(dqso.capture_policy_total_execution_cpu_time_ms, ''N0''),
            capture_policy_stale_threshold_hours =
                FORMAT(dqso.capture_policy_stale_threshold_hours, ''N0''),'
                ELSE N''
            END
            );

        SELECT
            @sql += N'
        dqso.size_based_cleanup_mode_desc
        FROM #database_query_store_options AS dqso
        OPTION(RECOMPILE);';


        IF @debug = 1
        BEGIN
            PRINT LEN(@sql);
            PRINT @sql;
        END;

        EXEC sys.sp_executesql
            @sql;
    END;

END; /*End expert mode = 1, format output = 1*/

SELECT
    x.all_done,
    x.period,
    x.support,
    x.help,
    x.problems,
    x.performance,
    x.version_and_date,
    x.thanks
FROM
(
    SELECT
        sort =
            1,
        period =
            N'query store data for period ' +
            CONVERT
            (
                nvarchar(10),
                ISNULL
                (
                    @start_date_original,
                    DATEADD
                    (
                        DAY,
                        -7,
                        DATEDIFF
                        (
                            DAY,
                            '19000101',
                            SYSDATETIME()
                        )
                    )
                ),
                23
            ) +
            N' through ' +
            CONVERT
            (
                nvarchar(10),
                ISNULL
                (
                    @end_date_original,
                    SYSDATETIME()
                ),
                23
            ),
        all_done =
            'brought to you by darling data!',
        support =
            'for support, head over to github',
        help =
            'for local help, use @help = 1',
        problems =
            'to debug issues, use @debug = 1;',
        performance =
            'if this runs slowly, use to get query plans',
        version_and_date =
            N'version: ' + CONVERT(nvarchar(10), @version),
        thanks =
            'thanks for using sp_QuickieStore!'

    UNION ALL

    SELECT
        sort =
            2,
        period =
            N'query store data for period ' +
            CONVERT
            (
                nvarchar(10),
                ISNULL
                (
                    @start_date_original,
                    DATEADD
                    (
                        DAY,
                        -7,
                        DATEDIFF
                        (
                            DAY,
                            '19000101',
                            SYSDATETIME()
                        )
                    )
                ),
                23
            ) +
            N' through ' +
            CONVERT
            (
                nvarchar(10),
                ISNULL
                (
                    @end_date_original,
                    SYSDATETIME()
                ),
                23
            ),
        all_done =
            'https://www.erikdarling.com/',
        support =
            'https://github.com/erikdarlingdata/DarlingData',
        help =
            'EXEC sp_QuickieStore @help = 1;',
        problems =
            'EXEC sp_QuickieStore @debug = 1;',
        performance =
            'EXEC sp_QuickieStore @troubleshoot_performance = 1;',
        version_and_date =
            N'version date: ' + CONVERT(nvarchar(10), @version_date, 23),
        thanks =
            'i hope you find it useful, or whatever'
) AS x
ORDER BY
    x.sort;

END TRY

/*Error handling!*/
BEGIN CATCH
    /*
    Where the error happened and the message
    */
    IF @current_table IS NOT NULL
    BEGIN
        RAISERROR('error while %s with @expert mode = %i and format_output = %i', 11, 1, @current_table, @em, @fo) WITH NOWAIT;
    END;

        /*
        Query that caused the error
        */
    IF @sql IS NOT NULL
    BEGIN
        RAISERROR('offending query:', 10, 1) WITH NOWAIT;
        RAISERROR('%s', 10, 1, @sql) WITH NOWAIT;
    END;

    /*
    This reliably throws the actual error from dynamic SQL
    */
    THROW;
END CATCH;

/*
Debug elements!
*/
IF @debug = 1
BEGIN
    SELECT
        parameter_type =
            'procedure_parameters',
        database_name =
            @database_name,
        sort_order =
            @sort_order,
        [top] =
            @top,
        start_date =
            @start_date,
        end_date =
            @end_date,
        timezone =
            @timezone,
        execution_count =
            @execution_count,
        duration_ms =
            @duration_ms,
        execution_type_desc =
            @execution_type_desc,
        procedure_schema =
            @procedure_schema,
        procedure_name =
            @procedure_name,
        include_plan_ids =
            @include_plan_ids,
        include_query_ids =
            @include_query_ids,
        include_query_hashes =
            @include_query_hashes,
        include_plan_hashes =
            @include_plan_hashes,
        include_sql_handles =
            @include_sql_handles,
        ignore_plan_ids =
            @ignore_plan_ids,
        ignore_query_ids =
            @ignore_query_ids,
        ignore_query_hashes =
            @ignore_query_hashes,
        ignore_plan_hashes =
            @ignore_plan_hashes,
        ignore_sql_handles =
            @ignore_sql_handles,
        query_text_search =
            @query_text_search,
        escape_brackets =
            @escape_brackets,
        escape_character =
            @escape_character,
        only_query_with_hints =
            @only_queries_with_hints,
        only_query_with_feedback =
            @only_queries_with_feedback,
        only_query_with_hints =
            @only_queries_with_variants,
        only_queries_with_forced_plans =
            @only_queries_with_forced_plans,
        only_queries_with_forced_plan_failures =
            @only_queries_with_forced_plan_failures,
        wait_filter =
            @wait_filter,
        query_type =
            @query_type,
        expert_mode =
            @expert_mode,
        format_output =
            @format_output,
        get_all_databases =
            @get_all_databases,
        workdays =
            @workdays,
        work_start =
            @work_start,
        work_end =
            @work_end,
        help =
            @help,
        debug =
            @debug,
        troubleshoot_performance =
            @troubleshoot_performance,
        version =
            @version,
        version_date =
            @version_date;

    SELECT
        parameter_type =
            'declared_variables',
        azure =
            @azure,
        engine =
            @engine,
        product_version =
            @product_version,
        database_id =
            @database_id,
        database_name_quoted =
            @database_name_quoted,
        procedure_name_quoted =
            @procedure_name_quoted,
        collation =
            @collation,
        new =
            @new,
        sql =
            @sql,
         len_sql =
             LEN(@sql),
        isolation_level =
            @isolation_level,
        parameters =
            @parameters,
        plans_top =
            @plans_top,
        queries_top =
            @queries_top,
        nc10 =
            @nc10,
        where_clause =
            @where_clause,
        procedure_exists =
            @procedure_exists,
        query_store_exists =
            @query_store_exists,
        query_store_trouble =
            @query_store_trouble,
        query_store_waits_enabled =
            @query_store_waits_enabled,
        sql_2022_views =
            @sql_2022_views,
        ags_present =
            @ags_present,
        string_split_ints =
            @string_split_ints,
        string_split_strings =
            @string_split_strings,
        current_table =
            @current_table,
        troubleshoot_insert =
            @troubleshoot_insert,
        troubleshoot_update =
            @troubleshoot_update,
        troubleshoot_info =
            @troubleshoot_info,
        rc =
            @rc,
       em =
           @em,
       fo =
          @fo,
       start_date_original =
           @start_date_original,
       end_date_original =
           @end_date_original,
       timezone =
           @timezone,
       utc_minutes_difference =
           @utc_minutes_difference,
       utc_minutes_original =
           @utc_minutes_original,
        df =
            @df,
        work_start_utc =
            @work_start_utc,
        work_end_utc =
            @work_end_utc;

    IF EXISTS
       (
           SELECT
               1/0
           FROM #databases AS d
       )
    BEGIN
        SELECT
            table_name =
                '#databases',
            d.*
        FROM #databases AS d
        ORDER BY
            d.database_name
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#databases is empty';
    END;

    IF EXISTS
       (
           SELECT
               1/0
           FROM #distinct_plans AS dp
       )
    BEGIN
        SELECT
            table_name =
                '#distinct_plans',
            dp.*
        FROM #distinct_plans AS dp
        ORDER BY
            dp.plan_id
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#distinct_plans is empty';
    END;

    IF EXISTS
       (
           SELECT
               1/0
           FROM #procedure_plans AS pp
       )
    BEGIN
        SELECT
            table_name =
                '#procedure_plans',
            pp.*
        FROM #procedure_plans AS pp
        ORDER BY
            pp.plan_id
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#procedure_plans is empty';
    END;

    IF EXISTS
       (
           SELECT
               1/0
           FROM #query_types AS qt
       )
    BEGIN
        SELECT
            table_name =
                '#query_types',
            qt.*
        FROM #query_types AS qt
        ORDER BY
            qt.plan_id
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#query_types is empty';
    END;

    IF EXISTS
       (
           SELECT
               1/0
           FROM #include_plan_ids AS ipi
       )
    BEGIN
        SELECT
            table_name =
                '#include_plan_ids',
            ipi.*
        FROM #include_plan_ids AS ipi
        ORDER BY
            ipi.plan_id
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#include_plan_ids is empty';
    END;

    IF EXISTS
       (
           SELECT
               1/0
           FROM #include_query_ids AS iqi
       )
    BEGIN
        SELECT
            table_name =
                '#include_query_ids',
            iqi.*
        FROM #include_query_ids AS iqi
        ORDER BY
            iqi.query_id
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#include_query_ids is empty';
    END;

    IF EXISTS
       (
           SELECT
               1/0
           FROM #include_query_hashes AS iqh
       )
    BEGIN
        SELECT
            table_name =
                '#include_query_hashes',
            iqh.*
        FROM #include_query_hashes AS iqh
        ORDER BY
            iqh.query_hash
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#include_query_hashes is empty';
    END;

    IF EXISTS
       (
           SELECT
               1/0
           FROM #include_plan_hashes AS iph
       )
    BEGIN
        SELECT
            table_name =
                '#include_plan_hashes',
            iph.*
        FROM #include_plan_hashes AS iph
        ORDER BY
            iph.plan_hash
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#include_plan_hashes is empty';
    END;

    IF EXISTS
       (
           SELECT
               1/0
           FROM #include_sql_handles AS ish
       )
    BEGIN
        SELECT
            table_name =
                '#include_sql_handles',
            ish.*
        FROM #include_sql_handles AS ish
        ORDER BY
            ish.sql_handle
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#include_sql_handles is empty';
    END;

    IF EXISTS
       (
           SELECT
               1/0
           FROM #ignore_plan_ids AS ipi
       )
    BEGIN
        SELECT
            table_name =
                '#ignore_plan_ids',
            ipi.*
        FROM #ignore_plan_ids AS ipi
        ORDER BY
            ipi.plan_id
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#ignore_plan_ids is empty';
    END;

    IF EXISTS
       (
           SELECT
               1/0
           FROM #ignore_query_ids AS iqi
       )
    BEGIN
        SELECT
            table_name =
                '#ignore_query_ids',
            iqi.*
        FROM #ignore_query_ids AS iqi
        ORDER BY
            iqi.query_id
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#ignore_query_ids is empty';
    END;

    IF EXISTS
       (
           SELECT
               1/0
           FROM #ignore_query_hashes AS iqh
       )
    BEGIN
        SELECT
            table_name =
                '#ignore_query_hashes',
            iqh.*
        FROM #ignore_query_hashes AS iqh
        ORDER BY
            iqh.query_hash
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#ignore_query_hashes is empty';
    END;

    IF EXISTS
       (
           SELECT
               1/0
           FROM #ignore_plan_hashes AS iph
       )
    BEGIN
        SELECT
            table_name =
                '#ignore_plan_hashes',
            iph.*
        FROM #ignore_plan_hashes AS iph
        ORDER BY
            iph.plan_hash
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#ignore_plan_hashes is empty';
    END;

    IF EXISTS
       (
           SELECT
               1/0
           FROM #ignore_sql_handles AS ish
       )
    BEGIN
        SELECT
            table_name =
                '#ignore_sql_handles',
            ish.*
        FROM #ignore_sql_handles AS ish
        ORDER BY
            ish.sql_handle
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#ignore_sql_handles is empty';
    END;

    IF EXISTS
       (
          SELECT
              1/0
          FROM #query_text_search AS qst
       )
    BEGIN
        SELECT
            table_name =
                '#query_text_search',
            qst.*
        FROM #query_text_search AS qst
        ORDER BY
            qst.plan_id
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#query_text_search is empty';
    END;

    IF EXISTS
       (
          SELECT
              1/0
          FROM #wait_filter AS wf
       )
    BEGIN
        SELECT
            table_name =
                '#wait_filter',
            wf.*
        FROM #wait_filter AS wf
        ORDER BY
            wf.plan_id
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#wait_filter is empty';
    END;

    IF EXISTS
       (
          SELECT
              1/0
          FROM #maintenance_plans AS mp
       )
    BEGIN
        SELECT
            table_name =
                '#maintenance_plans',
            mp.*
        FROM #maintenance_plans AS mp
        ORDER BY
            mp.plan_id
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#maintenance_plans is empty';
    END;

    IF EXISTS
       (
          SELECT
              1/0
          FROM #database_query_store_options AS qst
       )
    BEGIN
        SELECT
            table_name =
                '#database_query_store_options',
            dqso.*
        FROM #database_query_store_options AS dqso
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#database_query_store_options is empty';
    END;

    IF EXISTS
       (
          SELECT
              1/0
          FROM #query_store_trouble AS qst
       )
    BEGIN
        SELECT
            table_name =
                '#query_store_trouble',
            qst.*
        FROM #query_store_trouble AS qst
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#database_query_store_options is empty';
    END;

    IF EXISTS
       (
          SELECT
              1/0
          FROM #query_store_plan AS qsp
       )
    BEGIN
        SELECT
            table_name =
                '#query_store_plan',
            qsp.*
        FROM #query_store_plan AS qsp
        ORDER BY
            qsp.plan_id, qsp.query_id
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#query_store_plan is empty';
    END;

    IF EXISTS
       (
          SELECT
              1/0
          FROM #query_store_query AS qsq
       )
    BEGIN
        SELECT
            table_name =
                '#query_store_query',
            qsq.*
        FROM #query_store_query AS qsq
        ORDER BY
            qsq.query_id,
            qsq.query_text_id
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#query_store_query is empty';
    END;

    IF EXISTS
       (
          SELECT
              1/0
          FROM #query_store_query_text AS qsqt
       )
    BEGIN
        SELECT
            table_name =
                '#query_store_query_text',
            qsqt.*
        FROM #query_store_query_text AS qsqt
        ORDER BY
            qsqt.query_text_id
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#query_store_query_text is empty';
    END;

    IF EXISTS
       (
          SELECT
              1/0
          FROM #dm_exec_query_stats AS deqs
       )
    BEGIN
        SELECT
            table_name =
                '#dm_exec_query_stats ',
            deqs.*
        FROM #dm_exec_query_stats AS deqs
        ORDER BY
            deqs.statement_sql_handle
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#dm_exec_query_stats is empty';
    END;

    IF EXISTS
       (
          SELECT
              1/0
          FROM #query_store_runtime_stats AS qsrs
       )
    BEGIN
        SELECT
            table_name =
                '#query_store_runtime_stats',
            qsrs.*
        FROM #query_store_runtime_stats AS qsrs
        ORDER BY
            qsrs.plan_id
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#query_store_runtime_stats is empty';
    END;

    IF
      (
          @new = 1
          AND EXISTS
              (
                 SELECT
                     1/0
                 FROM #query_store_wait_stats AS qsws
              )
      )
    BEGIN
        SELECT
            table_name =
                '#query_store_wait_stats',
            qsws.*
        FROM #query_store_wait_stats AS qsws
        ORDER BY
            qsws.plan_id
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#query_store_wait_stats is empty' +
                CASE
                    WHEN (
                                @product_version = 13
                            AND @azure = 0
                         )
                    THEN ' because it''s not available < 2017'
                    WHEN EXISTS
                         (
                             SELECT
                                 1/0
                             FROM #database_query_store_options AS dqso
                             WHERE dqso.wait_stats_capture_mode_desc <> 'ON'
                         )
                    THEN ' because you have it disabled in your Query Store options'
                    ELSE ' for the queries in the results'
                END;
    END;

    IF EXISTS
       (
          SELECT
              1/0
          FROM #query_context_settings AS qcs
       )
    BEGIN
        SELECT
            table_name =
                '#query_context_settings',
            qcs.*
        FROM #query_context_settings AS qcs
        ORDER BY
            qcs.context_settings_id
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#query_context_settings is empty';
    END;

    IF @sql_2022_views = 1
    BEGIN
        IF EXISTS
           (
              SELECT
                  1/0
              FROM #query_store_plan_feedback AS qspf
           )
        BEGIN
            SELECT
                table_name =
                    '#query_store_plan_feedback',
                qspf.*
            FROM #query_store_plan_feedback AS qspf
            ORDER BY
                qspf.plan_feedback_id
            OPTION(RECOMPILE);
        END;
        ELSE
        BEGIN
            SELECT
                result =
                    '#query_store_plan_feedback is empty';
        END;

        IF EXISTS
           (
              SELECT
                  1/0
              FROM #query_store_query_hints AS qsqh
           )
        BEGIN
            SELECT
                table_name =
                    '#query_store_query_hints',
                qsqh.*
            FROM #query_store_query_hints AS qsqh
            ORDER BY
                qsqh.query_hint_id
            OPTION(RECOMPILE);
        END;
        ELSE
        BEGIN
            SELECT
                result =
                    '#query_store_query_hints is empty';
        END;

        IF EXISTS
           (
              SELECT
                  1/0
              FROM #query_store_query_variant AS qsqv
           )
        BEGIN
            SELECT
                table_name =
                    '#query_store_query_variant',
                qsqv.*
            FROM #query_store_query_variant AS qsqv
            ORDER BY
                qsqv.query_variant_query_id
            OPTION(RECOMPILE);
        END;
        ELSE
        BEGIN
            SELECT
                result =
                    '#query_store_query_variant is empty';
        END;

        IF @ags_present = 1
        BEGIN
            IF EXISTS
               (
                  SELECT
                      1/0
                  FROM #query_store_replicas AS qsr
               )
            BEGIN
                SELECT
                    table_name =
                        '#query_store_replicas',
                    qsr.*
                FROM #query_store_replicas AS qsr
                ORDER BY
                    qsr.replica_group_id
                OPTION(RECOMPILE);
            END;
            ELSE
            BEGIN
                SELECT
                    result =
                        '#query_store_replicas is empty';
            END;

            IF EXISTS
               (
                  SELECT
                      1/0
                  FROM #query_store_plan_forcing_locations AS qspfl
               )
            BEGIN
                SELECT
                    table_name =
                        '#query_store_plan_forcing_locations',
                    qspfl.*
                FROM #query_store_plan_forcing_locations AS qspfl
                ORDER BY
                    qspfl.plan_forcing_location_id
                OPTION(RECOMPILE);
            END;
            ELSE
            BEGIN
                SELECT
                    result =
                        '#query_store_plan_forcing_locations is empty';
            END;
        END;

        IF EXISTS
           (
              SELECT
                  1/0
              FROM #only_queries_with_hints AS oqwh
           )
        BEGIN
            SELECT
                table_name =
                    '#only_queries_with_hints',
                oqwh.*
            FROM #only_queries_with_hints AS oqwh
            ORDER BY
                oqwh.plan_id
            OPTION(RECOMPILE);
        END;
        ELSE
        BEGIN
            SELECT
                result =
                    '#only_queries_with_hints is empty';
        END;

        IF EXISTS
           (
              SELECT
                  1/0
              FROM #only_queries_with_feedback AS oqwf
           )
        BEGIN
            SELECT
                table_name =
                    '#only_queries_with_feedback',
                oqwf.*
            FROM #only_queries_with_feedback AS oqwf
            ORDER BY
                oqwf.plan_id
            OPTION(RECOMPILE);
        END;
        ELSE
        BEGIN
            SELECT
                result =
                    '#only_queries_with_feedback is empty';
        END;

        IF EXISTS
           (
              SELECT
                  1/0
              FROM #only_queries_with_variants AS oqwv
           )
        BEGIN
            SELECT
                table_name =
                    '#only_queries_with_variants',
                oqwv.*
            FROM #only_queries_with_variants AS oqwv
            ORDER BY
                oqwv.plan_id
            OPTION(RECOMPILE);
        END;
        ELSE
        BEGIN
            SELECT
                result =
                    '#only_queries_with_variants is empty';
        END;
    END;

    IF EXISTS
       (
          SELECT
              1/0
          FROM #forced_plans_failures AS fpf
       )
    BEGIN
        SELECT
            table_name =
                '#forced_plans_failures',
            fpf.*
        FROM #forced_plans_failures AS fpf
        ORDER BY
            fpf.plan_id
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#forced_plans_failures is empty';
    END;

    IF EXISTS
       (
          SELECT
              1/0
          FROM #troubleshoot_performance AS tp
       )
    BEGIN
        SELECT
            table_name =
                '#troubleshoot_performance',
            tp.*
        FROM #troubleshoot_performance AS tp
        ORDER BY
            tp.id
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#troubleshoot_performance is empty';
    END;
    RETURN; /*Stop doing anything, I guess*/
END; /*End debug*/
RETURN; /*Yeah sure why not?*/
END;/*Final End*/
GO
