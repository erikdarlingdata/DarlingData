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

Copyright 2025 Darling Data, LLC
https://www.erikdarling.com/

For usage and licensing details, run:
EXECUTE sp_QuickieStore
    @help = 1;

For working through errors:
EXECUTE sp_QuickieStore
    @debug = 1;

For performance issues:
EXECUTE sp_QuickieStore
    @troubleshoot_performance = 1;

For support, head over to GitHub:
https://code.erikdarling.com

*/

IF OBJECT_ID(N'dbo.sp_QuickieStore', N'P') IS NULL
   BEGIN
       EXECUTE (N'CREATE PROCEDURE dbo.sp_QuickieStore AS RETURN 138;');
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
    @execution_type_desc nvarchar(60) = NULL, /*the type of execution you want to filter by (regular, aborted, exception)*/
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
    @query_text_search_not nvarchar(4000) = NULL, /*query text to exclude*/
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
    @hide_help_table bit = 0, /*hides the "bottom table" that shows help and support information*/
    @format_output bit = 1, /*returns numbers formatted with commas and most decimals rounded away*/
    @get_all_databases bit = 0, /*looks for query store enabled user databases and returns combined results from all of them*/
    @include_databases nvarchar(max) = NULL, /*comma-separated list of databases to include (only when @get_all_databases = 1)*/
    @exclude_databases nvarchar(max) = NULL, /*comma-separated list of databases to exclude (only when @get_all_databases = 1)*/
    @workdays bit = 0, /*Use this to filter out weekends and after-hours queries*/
    @work_start time(0) = '9am', /*Use this to set a specific start of your work days*/
    @work_end time(0) = '5pm', /*Use this to set a specific end of your work days*/
    @regression_baseline_start_date datetimeoffset(7) = NULL, /*the begin date of the baseline that you are checking for regressions against (if any), will be converted to UTC internally*/
    @regression_baseline_end_date datetimeoffset(7) = NULL, /*the end date of the baseline that you are checking for regressions against (if any), will be converted to UTC internally*/
    @regression_comparator varchar(20) = NULL, /*what difference to use ('relative' or 'absolute') when comparing @sort_order's metric for the normal time period with the regression time period.*/
    @regression_direction varchar(20) = NULL, /*when comparing against the regression baseline, want do you want the results sorted by ('magnitude', 'improved', or 'regressed')?*/
    @include_query_hash_totals bit = 0, /*will add an additional column to final output with total resource usage by query hash, may be skewed by query_hash and query_plan_hash bugs with forced plans/plan guides*/
    @include_maintenance bit = 0, /*Set this bit to 1 to add maintenance operations such as index creation to the result set*/
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
SET XACT_ABORT OFF;
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
    @version = '5.6',
    @version_date = '20250601';

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
    SELECT 'you got me from https://code.erikdarling.com' UNION ALL
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
                WHEN N'@execution_type_desc' THEN 'the type of execution you want to filter by (regular, aborted, exception)'
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
                WHEN N'@query_text_search_not' THEN 'query text to exclude'
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
                WHEN N'@hide_help_table' THEN 'hides the "bottom table" that shows help and support information'
                WHEN N'@format_output' THEN 'returns numbers formatted with commas and most decimals rounded away'
                WHEN N'@get_all_databases' THEN 'looks for query store enabled user databases and returns combined results from all of them'
                WHEN N'@include_databases' THEN 'comma-separated list of databases to include (only when @get_all_databases = 1)'
                WHEN N'@exclude_databases' THEN 'comma-separated list of databases to exclude (only when @get_all_databases = 1)'
                WHEN N'@workdays' THEN 'use this to filter out weekends and after-hours queries'
                WHEN N'@work_start' THEN 'use this to set a specific start of your work days'
                WHEN N'@work_end' THEN 'use this to set a specific end of your work days'
                WHEN N'@regression_baseline_start_date' THEN 'the begin date of the baseline that you are checking for regressions against (if any), will be converted to UTC internally'
                WHEN N'@regression_baseline_end_date' THEN 'the end date of the baseline that you are checking for regressions against (if any), will be converted to UTC internally'
                WHEN N'@regression_comparator' THEN 'what difference to use (''relative'' or ''absolute'') when comparing @sort_order''s metric for the normal time period with any regression time period.'
                WHEN N'@regression_direction' THEN 'when comparing against any regression baseline, what do you want the results sorted by (''magnitude'', ''improved'', or ''regressed'')?'
                WHEN N'@include_query_hash_totals' THEN N'will add an additional column to final output with total resource usage by query hash, may be skewed by query_hash and query_plan_hash bugs with forced plans/plan guides'
                WHEN N'@include_maintenance' THEN N'Set this bit to 1 to add maintenance operations such as index creation to the result set'
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
                WHEN N'@sort_order' THEN 'cpu, logical reads, physical reads, writes, duration, memory, tempdb, executions, recent, plan count by hashes, cpu waits, lock waits, locks waits, latch waits, latches waits, buffer latch waits, buffer latches waits, buffer io waits, log waits, log io waits, network waits, network io waits, parallel waits, parallelism waits, memory waits, total waits, rows'
                WHEN N'@top' THEN 'a positive integer between 1 and 9,223,372,036,854,775,807'
                WHEN N'@start_date' THEN 'January 1, 1753, through December 31, 9999'
                WHEN N'@end_date' THEN 'January 1, 1753, through December 31, 9999'
                WHEN N'@timezone' THEN 'SELECT tzi.* FROM sys.time_zone_info AS tzi;'
                WHEN N'@execution_count' THEN 'a positive integer between 1 and 9,223,372,036,854,775,807'
                WHEN N'@duration_ms' THEN 'a positive integer between 1 and 9,223,372,036,854,775,807'
                WHEN N'@execution_type_desc' THEN 'regular, aborted, exception'
                WHEN N'@procedure_schema' THEN 'a valid schema in your database'
                WHEN N'@procedure_name' THEN 'a valid programmable object in your database, can use wildcards'
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
                WHEN N'@query_text_search_not' THEN 'a string; leading and trailing wildcards will be added if missing'
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
                WHEN N'@hide_help_table' THEN '0 or 1'
                WHEN N'@format_output' THEN '0 or 1'
                WHEN N'@get_all_databases' THEN '0 or 1'
                WHEN N'@include_databases' THEN 'a string; comma separated database names'
                WHEN N'@exclude_databases' THEN 'a string; comma separated database names'
                WHEN N'@workdays' THEN '0 or 1'
                WHEN N'@work_start' THEN 'a time like 8am, 9am or something'
                WHEN N'@work_end' THEN 'a time like 5pm, 6pm or something'
                WHEN N'@regression_baseline_start_date' THEN 'January 1, 1753, through December 31, 9999'
                WHEN N'@regression_baseline_end_date' THEN 'January 1, 1753, through December 31, 9999'
                WHEN N'@regression_comparator' THEN 'relative, absolute'
                WHEN N'@regression_direction' THEN 'regressed, worse, improved, better, magnitude, absolute, whatever'
                WHEN N'@include_query_hash_totals' THEN N'0 or 1'
                WHEN N'@include_maintenance' THEN N'0 or 1'
                WHEN N'@help' THEN '0 or 1'
                WHEN N'@debug' THEN '0 or 1'
                WHEN N'@troubleshoot_performance' THEN '0 or 1'
                WHEN N'@version' THEN 'none; OUTPUT'
                WHEN N'@version_date' THEN 'none; OUTPUT'
            END,
        defaults =
            CASE
                ap.name
                WHEN N'@database_name' THEN 'NULL; current database name if NULL'
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
                WHEN N'@query_text_search_not' THEN 'NULL'
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
                WHEN N'@hide_help_table' THEN '0'
                WHEN N'@format_output' THEN '1'
                WHEN N'@get_all_databases' THEN '0'
                WHEN N'@include_databases' THEN 'NULL'
                WHEN N'@exclude_databases' THEN 'NULL'
                WHEN N'@workdays' THEN '0'
                WHEN N'@work_start' THEN '9am'
                WHEN N'@work_end' THEN '5pm'
                WHEN N'@regression_baseline_start_date' THEN 'NULL'
                WHEN N'@regression_baseline_end_date' THEN 'NULL; One week after @regression_baseline_start_date if that is specified'
                WHEN N'@regression_comparator' THEN 'NULL; absolute if @regression_baseline_start_date is specified'
                WHEN N'@regression_direction' THEN 'NULL; regressed if @regression_baseline_start_date is specified'
                WHEN N'@include_query_hash_totals' THEN N'0'
                WHEN N'@include_maintenance' THEN N'0'
                WHEN N'@help' THEN '0'
                WHEN N'@debug' THEN '0'
                WHEN N'@troubleshoot_performance' THEN '0'
                WHEN N'@version' THEN 'none; OUTPUT'
                WHEN N'@version_date' THEN 'none; OUTPUT'
            END
    FROM sys.all_parameters AS ap
    JOIN sys.all_objects AS o
      ON ap.object_id = o.object_id
    JOIN sys.types AS t
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
END; /*End @help section*/


/*
Validate Sort Order.
We do this super early on, because we care about it even
when populating the tables that we declare very soon.
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
       'recent',
       'plan count by hashes',
       'cpu waits',
       'lock waits',
       'locks waits',
       'latch waits',
       'latches waits',
       'buffer latch waits',
       'buffer latches waits',
       'buffer io waits',
       'log waits',
       'log io waits',
       'network waits',
       'network io waits',
       'parallel waits',
       'parallelism waits',
       'memory waits',
       'total waits',
       'rows'
   )
BEGIN
   RAISERROR('The sort order (%s) you chose is so out of this world that I''m using cpu instead', 10, 1, @sort_order) WITH NOWAIT;

   SELECT
       @sort_order = 'cpu';
END;

DECLARE
    @sort_order_is_a_wait bit;

/*
Checks if the sort order is for a wait.
Cuts out a lot of repetition.
*/
IF LOWER(@sort_order) IN
   (
       'cpu waits',
       'lock waits',
       'locks waits',
       'latch waits',
       'latches waits',
       'buffer latch waits',
       'buffer latches waits',
       'buffer io waits',
       'log waits',
       'log io waits',
       'network waits',
       'network io waits',
       'parallel waits',
       'parallelism waits',
       'memory waits',
       'total waits'
   )
BEGIN
   SELECT
       @sort_order_is_a_wait = 1;
END;

/*
We also validate regression mode super early.
We need to do this here so we can build @ColumnDefinitions correctly.
It also lets us fail fast, if needed.
*/
DECLARE
    @regression_mode bit;

/*
Set @regression_mode if the given arguments indicate that
we are checking for regressed queries.
Also set any default parameters for regression mode while we're at it.
*/
IF @regression_baseline_start_date IS NOT NULL
BEGIN
    SELECT
        @regression_mode = 1,
        @regression_comparator =
            ISNULL(@regression_comparator, 'absolute'),
        @regression_direction =
            ISNULL(@regression_direction, 'regressed');
END;

/*
Error out if the @regression parameters do not make sense.
*/
IF
(
  @regression_baseline_start_date IS NULL
  AND
  (
      @regression_baseline_end_date IS NOT NULL
   OR @regression_comparator IS NOT NULL
   OR @regression_direction IS NOT NULL
  )
)
BEGIN
    RAISERROR('@regression_baseline_start_date is mandatory if you have specified any other @regression_ parameter.', 11, 1) WITH NOWAIT;
    RETURN;
END;

/*
Error out if the @regression_baseline_start_date and
@regression_baseline_end_date are incompatible.
We could try and guess a sensible resolution, but
I do not think that we can know what people want.
*/
IF
(
    @regression_baseline_start_date IS NOT NULL
AND @regression_baseline_end_date IS NOT NULL
AND @regression_baseline_start_date >= @regression_baseline_end_date
)
BEGIN
    RAISERROR('@regression_baseline_start_date has been set greater than or equal to @regression_baseline_end_date.
This does not make sense. Check that the values of both parameters are as you intended them to be.', 11, 1) WITH NOWAIT;
    RETURN;
END;

/*
Validate @regression_comparator.
*/
IF
(
    @regression_comparator IS NOT NULL
AND @regression_comparator NOT IN ('relative', 'absolute')
)
BEGIN
   RAISERROR('The regression_comparator (%s) you chose is so out of this world that I''m using ''absolute'' instead', 10, 1, @regression_comparator) WITH NOWAIT;

   SELECT
       @regression_comparator = 'absolute';
END;

/*
Validate @regression_direction.
*/
IF
(
    @regression_direction IS NOT NULL
AND @regression_direction NOT IN ('regressed', 'worse', 'improved', 'better', 'magnitude', 'absolute')
)
BEGIN
   RAISERROR('The regression_direction (%s) you chose is so out of this world that I''m using ''regressed'' instead', 10, 1, @regression_direction) WITH NOWAIT;

   SELECT
       @regression_direction = 'regressed';
END;

/*
Error out if we're trying to do regression mode with 'recent'
as our @sort_order. How could that ever make sense?
*/
IF
(
    @regression_mode = 1
AND @sort_order = 'recent'
)
BEGIN
    RAISERROR('Your @sort_order is ''recent'', but you are trying to compare metrics for two time periods.
If you can imagine a useful way to do that, then make a feature request.
Otherwise, either stop specifying any @regression_ parameters or specify a different @sort_order.', 11, 1) WITH NOWAIT;
    RETURN;
END;

/*
Error out if we're trying to do regression mode with 'plan count by hashes'
as our @sort_order. How could that ever make sense?
*/
IF
(
    @regression_mode = 1
AND @sort_order = 'plan count by hashes'
)
BEGIN
    RAISERROR('Your @sort_order is ''plan count by hashes'', but you are trying to compare metrics for two time periods.
This is probably not useful, since our method of comparing two time period relies on only checking query hashes that are in both time periods.
If you can imagine a useful way to do that, then make a feature request.
Otherwise, either stop specifying any @regression_ parameters or specify a different @sort_order.', 11, 1) WITH NOWAIT;
    RETURN;
END;

/*
Error out if @regression_comparator tells us to use division,
but @regression_direction tells us to take the modulus.
It doesn't make sense to specifically ask us to remove the sign
of something that doesn't care about it.
*/
IF
(
    @regression_comparator = 'relative'
AND @regression_direction IN ('absolute', 'magnitude')
)
BEGIN
    RAISERROR('Your @regression_comparator is ''relative'', but you have asked for an ''absolute'' or ''magnitude'' @regression_direction. This is probably a mistake.
Your @regression_direction tells us to take the absolute value of our result of comparing the metrics in the current time period to the baseline time period,
but your @regression_comparator is telling us to use division to compare the two time periods. This is unlikely to produce useful results.
If you can imagine a useful way to do that, then make a feature request. Otherwise, either change @regression_direction to another value
(e.g. ''better'' or ''worse'') or change @regression_comparator to ''absolute''.', 11, 1) WITH NOWAIT;
    RETURN;
END;

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
    plan_id bigint PRIMARY KEY CLUSTERED
);

/*
Hold plan_ids for procedures we're searching
*/
CREATE TABLE
    #procedure_plans
(
    plan_id bigint PRIMARY KEY CLUSTERED
);

/*
Hold plan_ids for procedures we're searching
*/
CREATE TABLE
    #procedure_object_ids
(
    [object_id] bigint PRIMARY KEY CLUSTERED
);

/*
Hold plan_ids for ad hoc or procedures we're searching for
*/
CREATE TABLE
    #query_types
(
    plan_id bigint PRIMARY KEY CLUSTERED
);

/*
Hold plan_ids for plans we want
*/
CREATE TABLE
    #include_plan_ids
(
    plan_id bigint PRIMARY KEY CLUSTERED
                   WITH (IGNORE_DUP_KEY = ON)
);

/*
Hold query_ids for plans we want
*/
CREATE TABLE
    #include_query_ids
(
    query_id bigint PRIMARY KEY CLUSTERED
);

/*
Hold plan_ids for ignored plans
*/
CREATE TABLE
    #ignore_plan_ids
(
    plan_id bigint PRIMARY KEY CLUSTERED
                   WITH (IGNORE_DUP_KEY = ON)
);

/*
Hold query_ids for ignored plans
*/
CREATE TABLE
    #ignore_query_ids
(
    query_id bigint PRIMARY KEY CLUSTERED
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
        ) PERSISTED NOT NULL
          PRIMARY KEY CLUSTERED
);

/*
For filtering by @execution_count.
This is only used for filtering, so it only needs one column.
*/
CREATE TABLE
    #plan_ids_having_enough_executions
(
    plan_id bigint PRIMARY KEY CLUSTERED,
);

/*
The following two tables are for adding extra columns
on to our output. We need these for sorting by anything
that isn't in #query_store_runtime_stats.

We still have to declare these tables even when they're
not used because the debug output breaks if we don't.

They are database dependent but not truncated at
the end of each loop, so we need a database_id
column.

We do not truncate these because we need them to still
be in scope and fully populated when we return our
final results from #query_store_runtime_stats, which
is done after the point where we would truncate.
*/

/*
Holds plan_id with the count of the number of query hashes they have.
Only used when we're sorting by how many plan hashes each
query hash has.
*/
CREATE TABLE
    #plan_ids_with_query_hashes
(
    database_id integer NOT NULL,
    plan_id bigint NOT NULL,
    query_hash binary(8) NOT NULL,
    plan_hash_count_for_query_hash integer NOT NULL,
    PRIMARY KEY CLUSTERED (database_id, plan_id, query_hash)
);

/*
Largely just exists because total_query_wait_time_ms
isn't in our normal output.

Unfortunately needs an extra column for regression
mode's benefit. The alternative was either a
horrible UNPIVOT with an extra temp table
or changing @parameters everywhere (and
therefore every sp_executesql).
*/
CREATE TABLE
    #plan_ids_with_total_waits
(
    database_id integer NOT NULL,
    plan_id bigint NOT NULL,
    from_regression_baseline varchar(3) NOT NULL,
    total_query_wait_time_ms bigint NOT NULL,
    PRIMARY KEY CLUSTERED(database_id, plan_id, from_regression_baseline)
);

/*
Used in regression mode to hold the
statistics for each query hash in our
baseline time period.
*/
CREATE TABLE
    #regression_baseline_runtime_stats
(
    query_hash binary(8) NOT NULL PRIMARY KEY CLUSTERED,
    /* Nullable to protect from division by 0. */
    regression_metric_average float NULL
);

/*
Used in regression mode to hold the
statistics for each query hash in our
normal time period.
*/
CREATE TABLE
    #regression_current_runtime_stats
(
    query_hash binary(8) NOT NULL PRIMARY KEY CLUSTERED,
    /* Nullable to protect from division by 0. */
    current_metric_average float NULL
);

/*
Used in regression mode to hold the
results of comparing our two time
periods.

This is also used just like a
sort-helping table. For example,
it is used to bolt columns
on to our final output.
*/
CREATE TABLE
    #regression_changes
(
    database_id integer NOT NULL,
    plan_id bigint NOT NULL,
    query_hash binary(8) NOT NULL,
    change_since_regression_time_period float NULL,
    PRIMARY KEY CLUSTERED (database_id, plan_id, query_hash)
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
        ) PERSISTED NOT NULL
          PRIMARY KEY CLUSTERED
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
        ) PERSISTED NOT NULL
          PRIMARY KEY CLUSTERED
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
        ) PERSISTED NOT NULL
          PRIMARY KEY CLUSTERED
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
        ) PERSISTED NOT NULL
          PRIMARY KEY CLUSTERED
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
        ) PERSISTED NOT NULL
          PRIMARY KEY CLUSTERED
);

/*
Hold plan_ids for only query with hints
*/
CREATE TABLE
    #only_queries_with_hints
(
    plan_id bigint PRIMARY KEY CLUSTERED
);

/*
Hold plan_ids for only query with feedback
*/
CREATE TABLE
    #only_queries_with_feedback
(
    plan_id bigint PRIMARY KEY CLUSTERED
);

/*
Hold plan_ids for only query with variants
*/
CREATE TABLE
    #only_queries_with_variants
(
    plan_id bigint PRIMARY KEY CLUSTERED
);

/*
Hold plan_ids for forced plans and/or forced plan failures
I'm overloading this a bit for simplicity, since searching for
failures is just an extension of searching for forced plans
*/

CREATE TABLE
    #forced_plans_failures
(
    plan_id bigint PRIMARY KEY CLUSTERED
);

/*
Hold plan_ids for matching query text
*/
CREATE TABLE
    #query_text_search
(
    plan_id bigint PRIMARY KEY CLUSTERED
);

/*
Hold plan_ids for matching query text (not)
*/
CREATE TABLE
    #query_text_search_not
(
    plan_id bigint PRIMARY KEY CLUSTERED
);

/*
Hold plan_ids for matching wait filter
*/
CREATE TABLE
    #wait_filter
(
    plan_id bigint PRIMARY KEY CLUSTERED
);

/*
Index and statistics entries to avoid
*/
CREATE TABLE
    #maintenance_plans
(
    plan_id bigint PRIMARY KEY CLUSTERED
);

/*
Query Store Setup
*/
CREATE TABLE
    #database_query_store_options
(
    database_id integer NOT NULL,
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
    capture_policy_execution_count integer NULL,
    capture_policy_total_compile_cpu_time_ms bigint NULL,
    capture_policy_total_execution_cpu_time_ms bigint NULL,
    capture_policy_stale_threshold_hours integer NULL,
    size_based_cleanup_mode_desc nvarchar(60) NULL,
    wait_stats_capture_mode_desc nvarchar(60) NULL
);

/*
Query Store Trouble
*/
CREATE TABLE
    #query_store_trouble
(
    database_id integer NOT NULL,
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
    database_id integer NOT NULL,
    plan_id bigint NOT NULL,
    query_id bigint NOT NULL,
    all_plan_ids varchar(max),
    plan_group_id bigint NULL,
    engine_version nvarchar(32) NULL,
    compatibility_level smallint NOT NULL,
    query_plan_hash binary(8) NOT NULL,
    query_plan nvarchar(max) NULL,
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
    database_id integer NOT NULL,
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
            CASE
                WHEN object_id > 0
                THEN N'Unknown object_id: ' +
                     RTRIM(object_id)
                ELSE N'Adhoc'
            END
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
    database_id integer NOT NULL,
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
    database_id integer NOT NULL,
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
    from_regression_baseline varchar(3) NULL,
    context_settings nvarchar(256) NULL
);

/*
Wait Stats, When Available (2017+)
*/
CREATE TABLE
    #query_store_wait_stats
(
    database_id integer NOT NULL,
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
    database_id integer NOT NULL,
    context_settings_id bigint NOT NULL,
    set_options varbinary(8) NULL,
    language_id smallint NOT NULL,
    date_format smallint NOT NULL,
    date_first tinyint NOT NULL,
    status varbinary(2) NULL,
    required_cursor_options integer NOT NULL,
    acceptable_cursor_options integer NOT NULL,
    merge_action_type smallint NOT NULL,
    default_schema_id integer NOT NULL,
    is_replication_specific bit NOT NULL,
    is_contained varbinary(1) NULL
);

/*
Feed me Seymour
*/
CREATE TABLE
    #query_store_plan_feedback
(
    database_id integer NOT NULL,
    plan_feedback_id bigint NOT NULL,
    plan_id bigint NULL,
    feature_desc nvarchar(120) NULL,
    feedback_data nvarchar(max) NULL,
    state_desc nvarchar(120) NULL,
    create_time datetimeoffset(7) NOT NULL,
    last_updated_time datetimeoffset(7) NULL
);

/*
America's Most Hinted
*/
CREATE TABLE
    #query_store_query_hints
(
    database_id integer NOT NULL,
    query_hint_id bigint NOT NULL,
    query_id bigint NOT NULL,
    query_hint_text nvarchar(max) NULL,
    last_query_hint_failure_reason_desc nvarchar(256) NULL,
    query_hint_failure_count bigint NOT NULL,
    source_desc nvarchar(256) NULL
);

/*
Variant? Deviant? You decide!
*/
CREATE TABLE
    #query_store_query_variant
(
    database_id integer NOT NULL,
    query_variant_query_id bigint NOT NULL,
    parent_query_id bigint NOT NULL,
    dispatcher_plan_id bigint NOT NULL
);

/*
Replicants
*/
CREATE TABLE
    #query_store_replicas
(
    database_id integer NOT NULL,
    replica_group_id bigint NOT NULL,
    role_type smallint NOT NULL,
    replica_name nvarchar(1288) NULL
);

/*Gonna try gathering this based on*/
CREATE TABLE
    #query_hash_totals
(
    database_id integer NOT NULL,
    query_hash binary(8) NOT NULL,
    total_executions bigint NOT NULL,
    total_duration_ms decimal(19,2) NOT NULL,
    total_cpu_time_ms decimal(19,2) NOT NULL,
    total_logical_reads_mb decimal(19,2) NOT NULL,
    total_physical_reads_mb decimal(19,2) NOT NULL,
    total_logical_writes_mb decimal(19,2) NOT NULL,
    total_clr_time_ms decimal(19,2) NOT NULL,
    total_memory_mb decimal(19,2) NOT NULL,
    total_rowcount decimal(19,2) NOT NULL,
    total_num_physical_io_reads decimal(19,2) NULL,
    total_log_bytes_used_mb decimal(19,2) NULL,
    total_tempdb_space_used_mb decimal(19,2) NULL,
    PRIMARY KEY CLUSTERED(query_hash, database_id)
);

/*
Location, location, location
*/
CREATE TABLE
    #query_store_plan_forcing_locations
(
    database_id integer NOT NULL,
    plan_forcing_location_id bigint NOT NULL,
    query_id bigint NOT NULL,
    plan_id bigint NOT NULL,
    replica_group_id bigint NOT NULL
);

/*
Trouble Loves Me
*/
CREATE TABLE
    #troubleshoot_performance
(
    id bigint IDENTITY PRIMARY KEY CLUSTERED,
    current_table nvarchar(100) NOT NULL,
    start_time datetime NOT NULL,
    end_time datetime NULL,
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
    database_name sysname PRIMARY KEY CLUSTERED
);

/* Create tables for database filtering */
CREATE TABLE
    #include_databases
(
    database_name sysname PRIMARY KEY CLUSTERED
);

CREATE TABLE
    #exclude_databases
(
    database_name sysname PRIMARY KEY CLUSTERED
);

CREATE TABLE
    #requested_but_skipped_databases
(
    database_name sysname PRIMARY KEY CLUSTERED,
    reason varchar(100) NOT NULL
);

/* Create a table variable to store ALL column definitions with logical ordering */
DECLARE
    @ColumnDefinitions table
(
    column_id integer
        PRIMARY KEY CLUSTERED, /* Controls the ordering of columns in output */
    metric_group nvarchar(50) NOT NULL, /* Grouping (duration, cpu, etc.) */
    metric_type nvarchar(20) NOT NULL, /* Type within group (avg, total, last, min, max) */
    column_name nvarchar(100) NOT NULL, /* Column name as it appears in output */
    column_source nvarchar(max) NOT NULL, /* Source expression or formula */
    is_conditional bit NOT NULL, /* Is this a conditional column (depends on a parameter) */
    condition_param nvarchar(50) NULL, /* Parameter name this column depends on */
    condition_value sql_variant NULL, /* Value the parameter must have */
    expert_only bit NOT NULL, /* Only include in expert mode */
    format_pattern nvarchar(20) NULL /* Format pattern (e.g., 'N0', 'P2', NULL for no formatting) */
);

/* Fill the table with ALL columns, including SQL 2022 views and regression columns */

/* Basic metadata columns (still part of prefix, but in the table) */
INSERT INTO
    @ColumnDefinitions
(
    column_id, metric_group, metric_type, column_name, column_source, is_conditional, condition_param, condition_value, expert_only, format_pattern
)
VALUES
    (20, 'metadata', 'force_count', 'force_failure_count', 'qsp.force_failure_count', 0, NULL, NULL, 0, NULL),
    (30, 'metadata', 'force_reason', 'last_force_failure_reason_desc', 'qsp.last_force_failure_reason_desc', 0, NULL, NULL, 0, NULL),
    /* SQL 2022 specific columns */
    (40, 'sql_2022', 'feedback', 'has_query_feedback', 'CASE WHEN EXISTS (SELECT 1/0 FROM #query_store_plan_feedback AS qspf WHERE qspf.plan_id = qsp.plan_id) THEN ''Yes'' ELSE ''No'' END', 1, 'sql_2022_views', 1, 0, NULL),
    (50, 'sql_2022', 'hints', 'has_query_store_hints', 'CASE WHEN EXISTS (SELECT 1/0 FROM #query_store_query_hints AS qsqh WHERE qsqh.query_id = qsp.query_id) THEN ''Yes'' ELSE ''No'' END', 1, 'sql_2022_views', 1, 0, NULL),
    (60, 'sql_2022', 'variants', 'has_plan_variants', 'CASE WHEN EXISTS (SELECT 1/0 FROM #query_store_query_variant AS qsqv WHERE qsqv.query_variant_query_id = qsp.query_id) THEN ''Yes'' ELSE ''No'' END', 1, 'sql_2022_views', 1, 0, NULL),
    (70, 'sql_2022', 'replay', 'has_compile_replay_script', 'qsp.has_compile_replay_script', 1, 'sql_2022_views', 1, 0, NULL),
    (80, 'sql_2022', 'opt_forcing', 'is_optimized_plan_forcing_disabled', 'qsp.is_optimized_plan_forcing_disabled', 1, 'sql_2022_views', 1, 0, NULL),
    (90, 'sql_2022', 'plan_type', 'plan_type_desc', 'qsp.plan_type_desc', 1, 'sql_2022_views', 1, 0, NULL),
    /* New version features */
    (95, 'new_features', 'forcing_type', 'plan_forcing_type_desc', 'qsp.plan_forcing_type_desc', 1, 'new', 1, 0, NULL),
    (97, 'new_features', 'top_waits', 'top_waits', 'w.top_waits', 1, 'new', 1, 0, NULL),
    /* Date/time columns (not conditional, always included) */
    (100, 'execution_time', 'first', 'first_execution_time', 'CASE WHEN @timezone IS NULL THEN SWITCHOFFSET(qsrs.first_execution_time, @utc_offset_string) WHEN @timezone IS NOT NULL THEN qsrs.first_execution_time AT TIME ZONE @timezone END', 0, NULL, NULL, 0, NULL),
    (110, 'execution_time', 'first_utc', 'first_execution_time_utc', 'qsrs.first_execution_time', 0, NULL, NULL, 0, NULL),
    (120, 'execution_time', 'last', 'last_execution_time', 'CASE WHEN @timezone IS NULL THEN SWITCHOFFSET(qsrs.last_execution_time, @utc_offset_string) WHEN @timezone IS NOT NULL THEN qsrs.last_execution_time AT TIME ZONE @timezone END', 0, NULL, NULL, 0, NULL),
    (130, 'execution_time', 'last_utc', 'last_execution_time_utc', 'qsrs.last_execution_time', 0, NULL, NULL, 0, NULL),
    /* Regression mode columns */
    (140, 'regression', 'baseline', 'from_regression_baseline_time_period', 'qsrs.from_regression_baseline', 1, 'regression_mode', 1, 0, NULL),
    (150, 'regression', 'hash', 'query_hash_from_regression_checking', 'regression.query_hash', 1, 'regression_mode', 1, 0, NULL),
    /* Execution columns */
    (200, 'executions', 'count', 'count_executions', 'qsrs.count_executions', 0, NULL, NULL, 0, 'N0'),
    (210, 'executions', 'per_second', 'executions_per_second', 'qsrs.executions_per_second', 0, NULL, NULL, 0, 'N0'),
    /* Hash totals - conditionally added */
    (215, 'executions', 'count_hash', 'count_executions_by_query_hash', 'qht.total_executions', 1, 'include_query_hash_totals', 1, 0, 'N0'),
    /* Duration metrics (group together avg, total, last, min, max) */
    (300, 'duration', 'avg', 'avg_duration_ms', 'qsrs.avg_duration_ms', 0, NULL, NULL, 0, 'N0'),
    (310, 'duration', 'total', 'total_duration_ms', 'qsrs.total_duration_ms', 0, NULL, NULL, 0, 'N0'),
    (320, 'duration', 'last', 'last_duration_ms', 'qsrs.last_duration_ms', 0, NULL, NULL, 1, 'N0'),
    (330, 'duration', 'min', 'min_duration_ms', 'qsrs.min_duration_ms', 0, NULL, NULL, 1, 'N0'),
    (340, 'duration', 'max', 'max_duration_ms', 'qsrs.max_duration_ms', 0, NULL, NULL, 0, 'N0'),
    /* Hash totals for duration */
    (315, 'duration', 'total_hash', 'total_duration_ms_by_query_hash', 'qht.total_duration_ms', 1, 'include_query_hash_totals', 1, 0, 'N0'),
    /* CPU metrics */
    (400, 'cpu', 'avg', 'avg_cpu_time_ms', 'qsrs.avg_cpu_time_ms', 0, NULL, NULL, 0, 'N0'),
    (410, 'cpu', 'total', 'total_cpu_time_ms', 'qsrs.total_cpu_time_ms', 0, NULL, NULL, 0, 'N0'),
    (420, 'cpu', 'last', 'last_cpu_time_ms', 'qsrs.last_cpu_time_ms', 0, NULL, NULL, 1, 'N0'),
    (430, 'cpu', 'min', 'min_cpu_time_ms', 'qsrs.min_cpu_time_ms', 0, NULL, NULL, 1, 'N0'),
    (440, 'cpu', 'max', 'max_cpu_time_ms', 'qsrs.max_cpu_time_ms', 0, NULL, NULL, 0, 'N0'),
    /* Hash totals for CPU */
    (415, 'cpu', 'total_hash', 'total_cpu_time_ms_by_query_hash', 'qht.total_cpu_time_ms', 1, 'include_query_hash_totals', 1, 0, 'N0'),
    /* Logical IO Reads */
    (500, 'logical_io_reads', 'avg', 'avg_logical_io_reads_mb', 'qsrs.avg_logical_io_reads_mb', 0, NULL, NULL, 0, 'N0'),
    (510, 'logical_io_reads', 'total', 'total_logical_io_reads_mb', 'qsrs.total_logical_io_reads_mb', 0, NULL, NULL, 0, 'N0'),
    (520, 'logical_io_reads', 'last', 'last_logical_io_reads_mb', 'qsrs.last_logical_io_reads_mb', 0, NULL, NULL, 1, 'N0'),
    (530, 'logical_io_reads', 'min', 'min_logical_io_reads_mb', 'qsrs.min_logical_io_reads_mb', 0, NULL, NULL, 1, 'N0'),
    (540, 'logical_io_reads', 'max', 'max_logical_io_reads_mb', 'qsrs.max_logical_io_reads_mb', 0, NULL, NULL, 0, 'N0'),
    /* Hash totals for logical reads */
    (515, 'logical_io_reads', 'total_hash', 'total_logical_io_reads_mb_by_query_hash', 'qht.total_logical_reads_mb', 1, 'include_query_hash_totals', 1, 0, 'N0'),
    /* Logical IO Writes */
    (600, 'logical_io_writes', 'avg', 'avg_logical_io_writes_mb', 'qsrs.avg_logical_io_writes_mb', 0, NULL, NULL, 0, 'N0'),
    (610, 'logical_io_writes', 'total', 'total_logical_io_writes_mb', 'qsrs.total_logical_io_writes_mb', 0, NULL, NULL, 0, 'N0'),
    (620, 'logical_io_writes', 'last', 'last_logical_io_writes_mb', 'qsrs.last_logical_io_writes_mb', 0, NULL, NULL, 1, 'N0'),
    (630, 'logical_io_writes', 'min', 'min_logical_io_writes_mb', 'qsrs.min_logical_io_writes_mb', 0, NULL, NULL, 1, 'N0'),
    (640, 'logical_io_writes', 'max', 'max_logical_io_writes_mb', 'qsrs.max_logical_io_writes_mb', 0, NULL, NULL, 0, 'N0'),
    /* Hash totals for logical writes */
    (615, 'logical_io_writes', 'total_hash', 'total_logical_io_writes_mb_by_query_hash', 'qht.total_logical_writes_mb', 1, 'include_query_hash_totals', 1, 0, 'N0'),
    /* Physical IO Reads */
    (700, 'physical_io_reads', 'avg', 'avg_physical_io_reads_mb', 'qsrs.avg_physical_io_reads_mb', 0, NULL, NULL, 0, 'N0'),
    (710, 'physical_io_reads', 'total', 'total_physical_io_reads_mb', 'qsrs.total_physical_io_reads_mb', 0, NULL, NULL, 0, 'N0'),
    (720, 'physical_io_reads', 'last', 'last_physical_io_reads_mb', 'qsrs.last_physical_io_reads_mb', 0, NULL, NULL, 1, 'N0'),
    (730, 'physical_io_reads', 'min', 'min_physical_io_reads_mb', 'qsrs.min_physical_io_reads_mb', 0, NULL, NULL, 1, 'N0'),
    (740, 'physical_io_reads', 'max', 'max_physical_io_reads_mb', 'qsrs.max_physical_io_reads_mb', 0, NULL, NULL, 0, 'N0'),
    /* Hash totals for physical reads */
    (715, 'physical_io_reads', 'total_hash', 'total_physical_io_reads_mb_by_query_hash', 'qht.total_physical_reads_mb', 1, 'include_query_hash_totals', 1, 0, 'N0'),
    /* CLR Time */
    (800, 'clr_time', 'avg', 'avg_clr_time_ms', 'qsrs.avg_clr_time_ms', 0, NULL, NULL, 0, 'N0'),
    (810, 'clr_time', 'total', 'total_clr_time_ms', 'qsrs.total_clr_time_ms', 0, NULL, NULL, 0, 'N0'),
    (820, 'clr_time', 'last', 'last_clr_time_ms', 'qsrs.last_clr_time_ms', 0, NULL, NULL, 1, 'N0'),
    (830, 'clr_time', 'min', 'min_clr_time_ms', 'qsrs.min_clr_time_ms', 0, NULL, NULL, 1, 'N0'),
    (840, 'clr_time', 'max', 'max_clr_time_ms', 'qsrs.max_clr_time_ms', 0, NULL, NULL, 0, 'N0'),
    /* Hash totals for CLR time */
    (815, 'clr_time', 'total_hash', 'total_clr_time_ms_by_query_hash', 'qht.total_clr_time_ms', 1, 'include_query_hash_totals', 1, 0, 'N0'),
    /* DOP (Degree of Parallelism) */
    (900, 'dop', 'last', 'last_dop', 'qsrs.last_dop', 0, NULL, NULL, 1, NULL),
    (910, 'dop', 'min', 'min_dop', 'qsrs.min_dop', 0, NULL, NULL, 0, NULL),
    (920, 'dop', 'max', 'max_dop', 'qsrs.max_dop', 0, NULL, NULL, 0, NULL),
    /* Memory metrics */
    (1000, 'memory', 'avg', 'avg_query_max_used_memory_mb', 'qsrs.avg_query_max_used_memory_mb', 0, NULL, NULL, 0, 'N0'),
    (1010, 'memory', 'total', 'total_query_max_used_memory_mb', 'qsrs.total_query_max_used_memory_mb', 0, NULL, NULL, 0, 'N0'),
    (1020, 'memory', 'last', 'last_query_max_used_memory_mb', 'qsrs.last_query_max_used_memory_mb', 0, NULL, NULL, 1, 'N0'),
    (1030, 'memory', 'min', 'min_query_max_used_memory_mb', 'qsrs.min_query_max_used_memory_mb', 0, NULL, NULL, 1, 'N0'),
    (1040, 'memory', 'max', 'max_query_max_used_memory_mb', 'qsrs.max_query_max_used_memory_mb', 0, NULL, NULL, 0, 'N0'),
    /* Hash totals for memory */
    (1015, 'memory', 'total_hash', 'total_query_max_used_memory_mb_by_query_hash', 'qht.total_memory_mb', 1, 'include_query_hash_totals', 1, 0, 'N0'),
    /* Row counts */
    (1100, 'rowcount', 'avg', 'avg_rowcount', 'qsrs.avg_rowcount', 0, NULL, NULL, 0, 'N0'),
    (1110, 'rowcount', 'total', 'total_rowcount', 'qsrs.total_rowcount', 0, NULL, NULL, 0, 'N0'),
    (1120, 'rowcount', 'last', 'last_rowcount', 'qsrs.last_rowcount', 0, NULL, NULL, 1, 'N0'),
    (1130, 'rowcount', 'min', 'min_rowcount', 'qsrs.min_rowcount', 0, NULL, NULL, 1, 'N0'),
    (1140, 'rowcount', 'max', 'max_rowcount', 'qsrs.max_rowcount', 0, NULL, NULL, 0, 'N0'),
    /* Hash totals for row counts */
    (1115, 'rowcount', 'total_hash', 'total_rowcount_by_query_hash', 'qht.total_rowcount', 1, 'include_query_hash_totals', 1, 0, 'N0'),
    /* New metrics for newer versions */
    /* Physical IO Reads (for newer versions) */
    (1200, 'num_physical_io_reads', 'avg', 'avg_num_physical_io_reads_mb', 'qsrs.avg_num_physical_io_reads_mb', 1, 'new', 1, 0, 'N0'),
    (1210, 'num_physical_io_reads', 'total', 'total_num_physical_io_reads_mb', 'qsrs.total_num_physical_io_reads_mb', 1, 'new', 1, 0, 'N0'),
    (1220, 'num_physical_io_reads', 'last', 'last_num_physical_io_reads_mb', 'qsrs.last_num_physical_io_reads_mb', 1, 'new', 1, 1, 'N0'),
    (1230, 'num_physical_io_reads', 'min', 'min_num_physical_io_reads_mb', 'qsrs.min_num_physical_io_reads_mb', 1, 'new', 1, 1, 'N0'),
    (1240, 'num_physical_io_reads', 'max', 'max_num_physical_io_reads_mb', 'qsrs.max_num_physical_io_reads_mb', 1, 'new', 1, 0, 'N0'),
    /* Hash totals for new physical IO reads */
    (1215, 'num_physical_io_reads', 'total_hash', 'total_num_physical_io_reads_mb_by_query_hash', 'qht.total_num_physical_io_reads', 1, 'new_with_hash_totals', 1, 0, 'N0'),
    /* Finish adding the remaining columns (log bytes and tempdb usage) */
    /* Log bytes used */
    (1300, 'log_bytes', 'avg', 'avg_log_bytes_used_mb', 'qsrs.avg_log_bytes_used_mb', 1, 'new', 1, 0, 'N0'),
    (1310, 'log_bytes', 'total', 'total_log_bytes_used_mb', 'qsrs.total_log_bytes_used_mb', 1, 'new', 1, 0, 'N0'),
    (1320, 'log_bytes', 'last', 'last_log_bytes_used_mb', 'qsrs.last_log_bytes_used_mb', 1, 'new', 1, 1, 'N0'),
    (1330, 'log_bytes', 'min', 'min_log_bytes_used_mb', 'qsrs.min_log_bytes_used_mb', 1, 'new', 1, 1, 'N0'),
    (1340, 'log_bytes', 'max', 'max_log_bytes_used_mb', 'qsrs.max_log_bytes_used_mb', 1, 'new', 1, 0, 'N0'),
    /* Hash totals for log bytes */
    (1315, 'log_bytes', 'total_hash', 'total_log_bytes_used_mb_by_query_hash', 'qht.total_log_bytes_used_mb', 1, 'new_with_hash_totals', 1, 0, 'N0'),
    /* TempDB usage  */
    (1400, 'tempdb', 'avg', 'avg_tempdb_space_used_mb', 'qsrs.avg_tempdb_space_used_mb', 1, 'new', 1, 0, 'N0'),
    (1410, 'tempdb', 'total', 'total_tempdb_space_used_mb', 'qsrs.total_tempdb_space_used_mb', 1, 'new', 1, 0, 'N0'),
    (1420, 'tempdb', 'last', 'last_tempdb_space_used_mb', 'qsrs.last_tempdb_space_used_mb', 1, 'new', 1, 1, 'N0'),
    (1430, 'tempdb', 'min', 'min_tempdb_space_used_mb', 'qsrs.min_tempdb_space_used_mb', 1, 'new', 1, 1, 'N0'),
    (1440, 'tempdb', 'max', 'max_tempdb_space_used_mb', 'qsrs.max_tempdb_space_used_mb', 1, 'new', 1, 0, 'N0'),
    /* Hash totals for tempdb */
    (1415, 'tempdb', 'total_hash', 'total_tempdb_space_used_mb_by_query_hash', 'qht.total_tempdb_space_used_mb', 1, 'new_with_hash_totals', 1, 0, 'N0'),
    /* Context settings and sorting columns  */
    (1500, 'metadata', 'context', 'context_settings', 'qsrs.context_settings', 0, NULL, NULL, 0, NULL);

/* Add special sorting columns based on @sort_order */
/* Plan hash count for 'plan count by hashes' sort */
IF @sort_order = 'plan count by hashes'
BEGIN
    INSERT INTO
        @ColumnDefinitions (column_id, metric_group, metric_type, column_name, column_source, is_conditional, condition_param, condition_value, expert_only, format_pattern)
    VALUES
        /* 230, so just before avg_query_duration_ms. */
        (230, 'sort_order', 'query_hash', 'query_hash_from_hash_counting', 'hashes.query_hash', 0, NULL, NULL, 0, NULL),
        (231, 'sort_order', 'plan_hash_count', 'plan_hash_count_for_query_hash', 'hashes.plan_hash_count_for_query_hash', 0, NULL, NULL, 0, 'N0');
END;

/* Dynamic regression change column based on formatting and comparator */
IF @regression_mode = 1 AND @regression_comparator = 'relative' AND @format_output = 1
BEGIN
    INSERT INTO
        @ColumnDefinitions (column_id, metric_group, metric_type, column_name, column_source, is_conditional, condition_param, condition_value, expert_only, format_pattern)
    VALUES (160, 'regression', 'change', 'change_in_average_for_query_hash_since_regression_time_period', 'regression.change_since_regression_time_period', 1, 'regression_mode', 1, 0, 'P2');
END;
ELSE IF @regression_mode = 1 AND @format_output = 1
BEGIN
    INSERT INTO
        @ColumnDefinitions (column_id, metric_group, metric_type, column_name, column_source, is_conditional, condition_param, condition_value, expert_only, format_pattern)
    VALUES (160, 'regression', 'change', 'change_in_average_for_query_hash_since_regression_time_period', 'regression.change_since_regression_time_period', 1, 'regression_mode', 1, 0, 'N2');
END;
ELSE IF @regression_mode = 1
BEGIN
    INSERT INTO
        @ColumnDefinitions (column_id, metric_group, metric_type, column_name, column_source, is_conditional, condition_param, condition_value, expert_only, format_pattern)
    VALUES (160, 'regression', 'change', 'change_in_average_for_query_hash_since_regression_time_period', 'regression.change_since_regression_time_period', 1, 'regression_mode', 1, 0, NULL);
END;

/* Wait time for wait-based sorting */
IF @sort_order_is_a_wait = 1
BEGIN
    INSERT INTO
        @ColumnDefinitions (column_id, metric_group, metric_type, column_name, column_source, is_conditional, condition_param, condition_value, expert_only, format_pattern)
    VALUES
        /* 240, so just before avg_query_duration_ms. */
        (240, 'sort_order', 'wait_time', 'total_wait_time_from_sort_order_ms', 'waits.total_query_wait_time_ms', 0, NULL, NULL, 0, 'N0');
END;

/* ROW_NUMBER window function for sorting */
INSERT INTO
    @ColumnDefinitions (column_id, metric_group, metric_type, column_name, column_source, is_conditional, condition_param, condition_value, expert_only, format_pattern)
VALUES
    (
        2000,
        'metadata',
        'n',
        'n',
        'ROW_NUMBER() OVER (PARTITION BY qsrs.plan_id ORDER BY ' +
        CASE WHEN @regression_mode = 1 THEN
             /* As seen when populating #regression_changes */
             CASE @regression_direction
                  WHEN 'regressed' THEN 'regression.change_since_regression_time_period'
                  WHEN 'worse' THEN 'regression.change_since_regression_time_period'
                  WHEN 'improved' THEN 'regression.change_since_regression_time_period * -1.0'
                  WHEN 'better' THEN 'regression.change_since_regression_time_period * -1.0'
                  WHEN 'magnitude' THEN 'ABS(regression.change_since_regression_time_period)'
                  WHEN 'absolute' THEN 'ABS(regression.change_since_regression_time_period)'
             END
        ELSE
            CASE @sort_order
                 WHEN 'cpu' THEN 'qsrs.avg_cpu_time_ms'
                 WHEN 'logical reads' THEN 'qsrs.avg_logical_io_reads_mb'
                 WHEN 'physical reads' THEN 'qsrs.avg_physical_io_reads_mb'
                 WHEN 'writes' THEN 'qsrs.avg_logical_io_writes_mb'
                 WHEN 'duration' THEN 'qsrs.avg_duration_ms'
                 WHEN 'memory' THEN 'qsrs.avg_query_max_used_memory_mb'
                 WHEN 'tempdb' THEN 'qsrs.avg_tempdb_space_used_mb' /*This gets validated later*/
                 WHEN 'executions' THEN 'qsrs.count_executions'
                 WHEN 'recent' THEN 'qsrs.last_execution_time'
                 WHEN 'rows' THEN 'qsrs.avg_rowcount'
                 WHEN 'plan count by hashes' THEN 'hashes.plan_hash_count_for_query_hash DESC, hashes.query_hash'
                 ELSE CASE WHEN @sort_order_is_a_wait = 1 THEN 'waits.total_query_wait_time_ms'
                 ELSE 'qsrs.avg_cpu_time_ms' END
            END
        END + ' DESC)',
        0,
        NULL,
        NULL,
        0,
        NULL
    );

/* Create a table variable to define parameter processing */
DECLARE
    @FilterParameters table
(
    parameter_name nvarchar(100) NOT NULL,
    parameter_value nvarchar(4000) NOT NULL,
    temp_table_name sysname NOT NULL,
    column_name sysname NOT NULL,
    data_type sysname NOT NULL,
    is_include bit NOT NULL,
    requires_secondary_processing bit NOT NULL
);

/* Populate with parameter definitions*/
INSERT INTO
    @FilterParameters
(
    parameter_name,
    parameter_value,
    temp_table_name,
    column_name,
    data_type,
    is_include,
    requires_secondary_processing
)
SELECT
    v.parameter_name,
    v.parameter_value,
    v.temp_table_name,
    v.column_name,
    v.data_type,
    v.is_include,
    v.requires_secondary_processing
FROM
(
    VALUES
        /* Include parameters */
        ('include_plan_ids', @include_plan_ids, '#include_plan_ids', 'plan_id', 'bigint', 1, 0),
        ('include_query_ids', @include_query_ids, '#include_query_ids', 'query_id', 'bigint', 1, 1),
        ('include_query_hashes', @include_query_hashes, '#include_query_hashes', 'query_hash_s', 'varchar', 1, 1),
        ('include_plan_hashes', @include_plan_hashes, '#include_plan_hashes', 'plan_hash_s', 'varchar', 1, 1),
        ('include_sql_handles', @include_sql_handles, '#include_sql_handles', 'sql_handle_s', 'varchar', 1, 1),
        /* Ignore parameters */
        ('ignore_plan_ids', @ignore_plan_ids, '#ignore_plan_ids', 'plan_id', 'bigint', 0, 0),
        ('ignore_query_ids', @ignore_query_ids, '#ignore_query_ids', 'query_id', 'bigint', 0, 1),
        ('ignore_query_hashes', @ignore_query_hashes, '#ignore_query_hashes', 'query_hash_s', 'varchar', 0, 1),
        ('ignore_plan_hashes', @ignore_plan_hashes, '#ignore_plan_hashes', 'plan_hash_s', 'varchar', 0, 1),
        ('ignore_sql_handles', @ignore_sql_handles, '#ignore_sql_handles', 'sql_handle_s', 'varchar', 0, 1)
    ) AS v
    (
        parameter_name,
        parameter_value,
        temp_table_name,
        column_name,
        data_type,
        is_include,
        requires_secondary_processing
    )
WHERE v.parameter_value IS NOT NULL;

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
Attempt at overloading procedure name so it can
accept a [schema].[procedure] pasted from results
from other executions of sp_QuickieStore
*/
IF
(
      @procedure_name LIKE N'[[]%].[[]%]'
  AND @procedure_schema IS NULL
)
BEGIN
    SELECT
        @procedure_schema = PARSENAME(@procedure_name, 2),
        @procedure_name   = PARSENAME(@procedure_name, 1);
END;

/*
Variables for the variable gods
*/
DECLARE
    @azure bit,
    @engine integer,
    @product_version integer,
    @database_id integer,
    @database_name_quoted sysname,
    @procedure_name_quoted nvarchar(1024),
    @collation sysname,
    @new bit,
    @sql nvarchar(max),
    @isolation_level nvarchar(max),
    @parameters nvarchar(4000),
    @plans_top bigint,
    @queries_top bigint,
    @nc10 nvarchar(2),
    @where_clause nvarchar(max),
    @query_text_search_original_value nvarchar(4000),
    @query_text_search_not_original_value nvarchar(4000),
    @procedure_exists bit,
    @query_store_exists bit,
    @query_store_trouble bit,
    @query_store_waits_enabled bit,
    @sql_2022_views bit,
    @ags_present bit,
    @string_split_ints nvarchar(1500),
    @string_split_strings nvarchar(1500),
    @current_table nvarchar(100),
    @troubleshoot_insert nvarchar(max),
    @troubleshoot_update nvarchar(max),
    @troubleshoot_info nvarchar(max),
    @rc bigint,
    @em tinyint,
    @fo tinyint,
    @start_date_original datetimeoffset(7),
    @end_date_original datetimeoffset(7),
    @utc_minutes_difference bigint,
    @utc_offset_string nvarchar(6),
    @df integer,
    @work_start_utc time(0),
    @work_end_utc time(0),
    @regression_baseline_start_date_original datetimeoffset(7),
    @regression_baseline_end_date_original datetimeoffset(7),
    @regression_where_clause nvarchar(max),
    @column_sql nvarchar(max),
    @param_name nvarchar(100),
    @param_value nvarchar(4000),
    @temp_table sysname,
    @column_name sysname,
    @data_type sysname,
    @is_include bit,
    @requires_secondary_processing bit,
    @split_sql nvarchar(max),
    @error_msg nvarchar(2000),
    @conflict_list nvarchar(max) = N'',
    @database_cursor CURSOR,
    @filter_cursor CURSOR,
    @dynamic_sql nvarchar(max) = N'',
    @secondary_sql nvarchar(max) = N'',
    @temp_target_table nvarchar(100),
    @exist_or_not_exist nvarchar(20);

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
         @query_text_search_original_value = @query_text_search,
         @query_text_search_not_original_value = @query_text_search_not;
END;

/*
We also need to capture original values here.
Doing it inside a loop over multiple databases
would break the UTC conversion.
*/
SELECT
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
        );

/*
Set the _original variables, as we have
for other values that would break inside
the loop without them.

This is also where we enforce the default
that leaving @regression_baseline_end_date
unspecified will set it to be a week
after @regression_baseline_start_date.

We do not need to account for the possibility
of @regression_baseline_start_date being NULL.
Due to the above error-throwing, it cannot be
NULL if we are doing anything that would care
about it.
*/
SELECT
    @regression_baseline_start_date_original =
        @regression_baseline_start_date,
    @regression_baseline_end_date_original =
        ISNULL
        (
            @regression_baseline_end_date,
            DATEADD
            (
                DAY,
                7,
                @regression_baseline_start_date
            )
        );

/*
Error out if the @execution_type_desc value is invalid.
*/
IF
(
    @execution_type_desc IS NOT NULL
AND @execution_type_desc NOT IN ('regular', 'aborted', 'exception')
)
BEGIN
    RAISERROR('@execution_type_desc can only take one of these three non-NULL values:
    1) ''regular'' (meaning a successful execution),
    2) ''aborted'' (meaning that the client cancelled the query),
    3) ''exception'' (meaning that an exception cancelled the query).

You supplied ''%s''.

If you leave @execution_type_desc NULL, then we grab every type of execution.

See the official documentation for sys.query_store_runtime_stats for more details on the execution types.', 11, 1, @execution_type_desc) WITH NOWAIT;
    RETURN;
END;


/*
This section is in a cursor whether we
hit one database, or multiple

I do all the variable assignment in the
cursor block because some of them
are assigned for the specific database
that is currently being looked at
*/

/*
Look at databases to include or exclude
*/
IF @get_all_databases = 1
BEGIN
    /* Check for contradictory parameters */
    IF @database_name IS NOT NULL
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR(N'@database name being ignored since @get_all_databases is set to 1', 0, 0) WITH NOWAIT;
        END;
        SET @database_name = NULL;
    END;

    /* Parse @include_databases if specified using XML for compatibility */
    IF @include_databases IS NOT NULL
    BEGIN
        INSERT
            #include_databases
        WITH
            (TABLOCK)
        (
            database_name
        )
        SELECT DISTINCT
            database_name =
                LTRIM(RTRIM(c.value(N'(./text())[1]', N'sysname')))
        FROM
        (
            SELECT
                x = CONVERT
                    (
                        xml,
                        N'<i>' +
                        REPLACE
                        (
                            @include_databases,
                            N',',
                            N'</i><i>'
                        ) +
                        N'</i>'
                    )
        ) AS a
        CROSS APPLY x.nodes(N'//i') AS t(c)
        WHERE LTRIM(RTRIM(c.value(N'(./text())[1]', N'sysname'))) <> N''
        OPTION(RECOMPILE);
    END;

    /* Parse @exclude_databases if specified using XML for compatibility */
    IF @exclude_databases IS NOT NULL
    BEGIN
        INSERT
            #exclude_databases
        WITH
            (TABLOCK)
        (
            database_name
        )
        SELECT DISTINCT
            database_name =
                LTRIM(RTRIM(c.value(N'(./text())[1]', N'sysname')))
        FROM
        (
            SELECT
                x = CONVERT
                    (
                        xml,
                        N'<i>' +
                        REPLACE
                        (
                            @exclude_databases,
                            N',',
                            N'</i><i>'
                        ) +
                        N'</i>'
                    )
        ) AS a
        CROSS APPLY x.nodes(N'//i') AS t(c)
        WHERE LTRIM(RTRIM(c.value(N'(./text())[1]', N'sysname'))) <> N''
        OPTION(RECOMPILE);

        /* Check for databases in both include and exclude lists */
        IF @include_databases IS NOT NULL
        BEGIN
            /* Build list of conflicting databases */
            SELECT
                @conflict_list =
                    @conflict_list +
                    ed.database_name + N', '
            FROM #exclude_databases AS ed
            WHERE EXISTS
                (
                    SELECT
                        1/0
                    FROM #include_databases AS id
                    WHERE id.database_name = ed.database_name
                )
            OPTION(RECOMPILE);

            /* If we found any conflicts, raise an error */
            IF LEN(@conflict_list) > 0
            BEGIN
                /* Remove trailing comma and space */
                SET @conflict_list = LEFT(@conflict_list, LEN(@conflict_list) - 2);

                SET @error_msg =
                    N'The following databases appear in both @include_databases and @exclude_databases, which creates ambiguity: ' +
                    @conflict_list + N'. Please remove these databases from one of the lists.';

                RAISERROR(@error_msg, 16, 1);
                RETURN;
            END;
        END;
    END;
END;

/*
Build up the databases to process
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
        #databases
    WITH
        (TABLOCK)
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
    AND   (
            @include_databases IS NULL
            OR EXISTS (SELECT 1/0 FROM #include_databases AS id WHERE id.database_name = d.name)
          )
    AND   (
            @exclude_databases IS NULL
            OR NOT EXISTS (SELECT 1/0 FROM #exclude_databases AS ed WHERE ed.database_name = d.name)
          )
    OPTION(RECOMPILE);

    /* Track which requested databases were skipped */
    IF  @include_databases IS NOT NULL
    AND @get_all_databases = 1
    BEGIN
        INSERT
            #requested_but_skipped_databases
        WITH
            (TABLOCK)
        (
            database_name,
            reason
        )
        SELECT
            id.database_name,
            reason =
                CASE
                    WHEN d.name IS NULL
                    THEN 'Database does not exist'
                    WHEN d.state <> 0
                    THEN 'Database not online'
                    WHEN d.is_query_store_on = 0
                    THEN 'Query Store not enabled'
                    WHEN d.is_in_standby = 1
                    THEN 'Database is in standby'
                    WHEN d.is_read_only = 1
                    THEN 'Database is read-only'
                    WHEN d.database_id <= 4
                    THEN 'System database'
                    ELSE 'Other issue'
                END
        FROM #include_databases AS id
        LEFT JOIN sys.databases AS d
          ON id.database_name = d.name
        WHERE NOT EXISTS
              (
                  SELECT
                      1/0
                  FROM #databases AS db
                  WHERE db.database_name = id.database_name
              )
        OPTION(RECOMPILE);
    END;
END;
ELSE
BEGIN
    INSERT
        #databases
    WITH
        (TABLOCK)
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
    AND   d.name NOT IN (N'master', N'model', N'msdb', N'tempdb', N'rdsadmin')
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
    AND   (
            @include_databases IS NULL
            OR EXISTS (SELECT 1/0 FROM #include_databases AS id WHERE id.database_name = d.name)
          )
    AND   (
            @exclude_databases IS NULL
            OR NOT EXISTS (SELECT 1/0 FROM #exclude_databases AS ed WHERE ed.database_name = d.name)
          )
    OPTION(RECOMPILE);

    /* Track which requested databases were skipped */
    IF  @include_databases IS NOT NULL
    AND @get_all_databases = 1
    BEGIN
        INSERT
            #requested_but_skipped_databases
        WITH
            (TABLOCK)
        (
            database_name,
            reason
        )
        SELECT
            id.database_name,
            reason =
                CASE
                    WHEN d.name IS NULL THEN 'Database does not exist'
                    WHEN d.state <> 0 THEN 'Database not online'
                    WHEN d.is_query_store_on = 0 THEN 'Query Store not enabled'
                    WHEN d.is_in_standby = 1 THEN 'Database is in standby'
                    WHEN d.is_read_only = 1 THEN 'Database is read-only'
                    WHEN d.database_id <= 4 THEN 'System database'
                    WHEN EXISTS
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
                         ) THEN 'AG replica issues'
                    ELSE 'Other issue'
                END
        FROM #include_databases AS id
        LEFT JOIN sys.databases AS d
          ON id.database_name = d.name
        WHERE NOT EXISTS
              (
                  SELECT
                      1/0
                  FROM #databases AS db
                  WHERE db.database_name = id.database_name
              )
        OPTION(RECOMPILE);
    END;
END;

SET
    @database_cursor =
        CURSOR
        LOCAL
        SCROLL
        DYNAMIC
        READ_ONLY
FOR
SELECT
    d.database_name
FROM #databases AS d;

OPEN @database_cursor;

FETCH FIRST
FROM @database_cursor
INTO @database_name;

WHILE @@FETCH_STATUS = 0
BEGIN
/*
These tables need to get cleared out
to avoid result pollution and
primary key violations
*/
IF @debug = 1
BEGIN
    RAISERROR('Truncating per-database temp tables for the next iteration', 0, 0) WITH NOWAIT;
END;

TRUNCATE TABLE
    #regression_baseline_runtime_stats;

TRUNCATE TABLE
    #regression_current_runtime_stats;

TRUNCATE TABLE
    #distinct_plans;

TRUNCATE TABLE
    #procedure_plans;

TRUNCATE TABLE
    #procedure_object_ids;

TRUNCATE TABLE
    #maintenance_plans;

TRUNCATE TABLE
    #query_text_search;

TRUNCATE TABLE
    #query_text_search_not;

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

TRUNCATE TABLE
    #plan_ids_having_enough_executions;

TRUNCATE TABLE
    #include_plan_ids;

TRUNCATE TABLE
    #include_query_ids;

TRUNCATE TABLE
    #include_query_hashes;

TRUNCATE TABLE
    #include_plan_hashes;

TRUNCATE TABLE
    #include_sql_handles;

TRUNCATE TABLE
    #ignore_plan_ids;

TRUNCATE TABLE
    #ignore_query_ids;

TRUNCATE TABLE
    #ignore_query_hashes;

TRUNCATE TABLE
    #ignore_plan_hashes;

TRUNCATE TABLE
    #ignore_sql_handles;

TRUNCATE TABLE
    #only_queries_with_hints;

TRUNCATE TABLE
    #only_queries_with_feedback;

TRUNCATE TABLE
    #only_queries_with_variants;

TRUNCATE TABLE
    #forced_plans_failures;

TRUNCATE TABLE
    #query_hash_totals;


/*
Some variable assignment, because why not?
*/
IF @debug = 1
BEGIN
    RAISERROR('Starting analysis for database %s', 0, 0, @database_name) WITH NOWAIT;
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
            integer,
            SERVERPROPERTY('ENGINEEDITION')
        ),
    @product_version =
        CONVERT
        (
            integer,
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
          @database_id integer,
          @queries_top bigint,
          @work_start_utc time(0),
          @work_end_utc time(0),
          @regression_baseline_start_date datetimeoffset(7),
          @regression_baseline_end_date datetimeoffset(7)',
    @plans_top =
        9223372036854775807,
    @queries_top =
        9223372036854775807,
    @nc10 = NCHAR(10),
    @where_clause = N'',
    @query_text_search =
        CASE
            WHEN @get_all_databases = 1
            AND  @escape_brackets = 1
            THEN @query_text_search_original_value
            ELSE @query_text_search
         END,
    @query_text_search_not =
        CASE
            WHEN @get_all_databases = 1
            AND  @escape_brackets = 1
            THEN @query_text_search_not_original_value
            ELSE @query_text_search_not
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
        OPTION(RECOMPILE);
        ',
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
        OPTION(RECOMPILE);
        ',
    @troubleshoot_insert = N'
        INSERT
            #troubleshoot_performance
        WITH
            (TABLOCK)
        (
            current_table,
            start_time
        )
        VALUES
        (
            @current_table,
            GETDATE()
        )
        OPTION(RECOMPILE);
        ',
    @troubleshoot_update = N'
        UPDATE
            tp
        SET
            tp.end_time = GETDATE()
        FROM #troubleshoot_performance AS tp
        WHERE tp.current_table = @current_table
        OPTION(RECOMPILE);
        ',
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
        OPTION(RECOMPILE);
        ',
    @rc = 0,
    @em = @expert_mode,
    @fo = @format_output,
    @utc_minutes_difference =
        DATEDIFF
        (
            MINUTE,
            SYSDATETIME(),
            SYSUTCDATETIME()
        ),
    /*
    There is no direct way to get the user's timezone in a
    format compatible with sys.time_zone_info.

    We also cannot directly get their UTC offset,
    so we need this hack to get it instead.

    This is to make our datetimeoffsets have the
    correct offset in cases where the user didn't
    give us their timezone.
    */
    @utc_offset_string = RIGHT(SYSDATETIMEOFFSET(), 6),
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
    @hide_help_table =
        ISNULL(@hide_help_table, 0),
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
    @include_query_hash_totals =
        ISNULL(@include_query_hash_totals, 0),
    @include_maintenance =
        ISNULL(@include_maintenance, 0),
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
                    @start_date_original
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
                    @end_date_original
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
As above, but for @regression_baseline_start_date and @regression_baseline_end_date.
*/
IF @regression_mode = 1
BEGIN
/*
We set both _date_original variables earlier.
*/
    SELECT
        @regression_baseline_start_date =
            DATEADD
            (
                MINUTE,
                @utc_minutes_difference,
                @regression_baseline_start_date_original
            ),
        @regression_baseline_end_date =
            DATEADD
            (
                MINUTE,
                @utc_minutes_difference,
                @regression_baseline_end_date_original
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
        IF @debug = 1
        BEGIN
            GOTO DEBUG;
        END;
        ELSE
        BEGIN
            RETURN;
        END;
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
    IF @debug = 1
    BEGIN
        GOTO DEBUG;
    END;
    ELSE
    BEGIN
        RETURN;
    END;
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
    IF @debug = 1
    BEGIN
        GOTO DEBUG;
    END;
    ELSE
    BEGIN
        RETURN;
    END;
END;

/*
Sometimes sys.databases will report Query Store being on, but it's really not
*/
SELECT
    @current_table = 'checking query store existence',
    @sql = @isolation_level;

IF @troubleshoot_performance = 1
BEGIN

    EXECUTE sys.sp_executesql
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

EXECUTE sys.sp_executesql
    @sql,
  N'@query_store_exists bit OUTPUT',
    @query_store_exists OUTPUT;

IF @troubleshoot_performance = 1
BEGIN
    SET STATISTICS XML OFF;

    EXECUTE sys.sp_executesql
        @troubleshoot_update,
      N'@current_table nvarchar(100)',
        @current_table;

    EXECUTE sys.sp_executesql
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
        IF @debug = 1
        BEGIN
            GOTO DEBUG;
        END;
        ELSE
        BEGIN
            RETURN;
        END;
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

    EXECUTE sys.sp_executesql
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
WHERE dqso.desired_state <> 4
AND   dqso.readonly_reason <> 8
AND   dqso.desired_state <> dqso.actual_state
AND   dqso.actual_state IN (0, 3)
OPTION(RECOMPILE);' + @nc10;

IF @debug = 1
BEGIN
    PRINT LEN(@sql);
    PRINT @sql;
END;

INSERT
    #query_store_trouble
WITH
    (TABLOCK)
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
EXECUTE sys.sp_executesql
    @sql,
  N'@database_id integer',
    @database_id;

IF ROWCOUNT_BIG() > 0
BEGIN
    SELECT
        @query_store_trouble = 1;
END;

IF @troubleshoot_performance = 1
BEGIN
    SET STATISTICS XML OFF;

    EXECUTE sys.sp_executesql
        @troubleshoot_update,
      N'@current_table nvarchar(100)',
        @current_table;

    EXECUTE sys.sp_executesql
        @troubleshoot_info,
      N'@sql nvarchar(max),
        @current_table nvarchar(100)',
        @sql,
        @current_table;
END;


/*
If you specified a procedure name, we need to figure out if there are any plans for it available
*/
IF @procedure_name IS NOT NULL
BEGIN
    IF @procedure_schema IS NULL
    BEGIN
        SELECT
            @procedure_schema = N'dbo';
    END;
    SELECT
        @current_table = 'checking procedure existence',
        @sql = @isolation_level;

    IF @troubleshoot_performance = 1
    BEGIN
        EXECUTE sys.sp_executesql
            @troubleshoot_insert,
          N'@current_table nvarchar(100)',
            @current_table;

        SET STATISTICS XML ON;
    END;

    IF CHARINDEX(N'%', @procedure_name) > 0
    BEGIN
        SELECT
            @current_table = 'getting procedure object ids for wildcard',
            @sql = @isolation_level;

        SELECT @sql += N'
SELECT
    p.object_id
FROM ' + @database_name_quoted + N'.sys.procedures AS p
JOIN ' + @database_name_quoted + N'.sys.schemas AS s
  ON p.schema_id = s.schema_id
WHERE s.name = @procedure_schema
AND   p.name LIKE @procedure_name
OPTION(RECOMPILE);' + @nc10;

        IF @debug = 1
        BEGIN
            PRINT LEN(@sql);
            PRINT @sql;
        END;

        INSERT
            #procedure_object_ids
        WITH
            (TABLOCK)
        (
            [object_id]
        )
        EXECUTE sys.sp_executesql
            @sql,
          N'@procedure_schema sysname,
            @procedure_name sysname',
            @procedure_schema,
            @procedure_name;

        IF ROWCOUNT_BIG() = 0
        BEGIN
            RAISERROR('No object_ids were found for %s in schema %s', 11, 1, @procedure_schema, @procedure_name) WITH NOWAIT;
            RETURN;
        END;

        IF @troubleshoot_performance = 1
        BEGIN
            SET STATISTICS XML OFF;

            EXECUTE sys.sp_executesql
                @troubleshoot_update,
              N'@current_table nvarchar(100)',
                @current_table;

            EXECUTE sys.sp_executesql
                @troubleshoot_info,
              N'@sql nvarchar(max),
                @current_table nvarchar(100)',
                @sql,
                @current_table;
        END;

        SELECT
            @current_table = 'checking wildcard procedure existence',
            @sql = @isolation_level;

        IF @troubleshoot_performance = 1
        BEGIN
            EXECUTE sys.sp_executesql
                @troubleshoot_insert,
              N'@current_table nvarchar(100)',
                @current_table;

            SET STATISTICS XML ON;
        END;

        SELECT
            @sql += N'
SELECT
    @procedure_exists =
        MAX(x.procedure_exists)
    FROM
    (
        SELECT
            procedure_exists =
                CASE
                    WHEN EXISTS
                         (
                             SELECT
                                 1/0
                             FROM ' + @database_name_quoted + N'.sys.query_store_query AS qsq
                             WHERE EXISTS
                             (
                                 SELECT
                                     1/0
                                 FROM #procedure_object_ids AS p
                                 WHERE qsq.[object_id] = p.[object_id]
                             )
                         )
                    THEN 1
                    ELSE 0
                END
    ) AS x
OPTION(RECOMPILE);' + @nc10;

        IF @debug = 1
        BEGIN
            PRINT LEN(@sql);
            PRINT @sql;
        END;

        EXECUTE sys.sp_executesql
            @sql,
          N'@procedure_exists bit OUTPUT,
            @procedure_name_quoted sysname',
            @procedure_exists OUTPUT,
            @procedure_name_quoted;

        IF @troubleshoot_performance = 1
        BEGIN
            SET STATISTICS XML OFF;

            EXECUTE sys.sp_executesql
                @troubleshoot_update,
              N'@current_table nvarchar(100)',
                @current_table;

            EXECUTE sys.sp_executesql
                @troubleshoot_info,
              N'@sql nvarchar(max),
                @current_table nvarchar(100)',
                @sql,
                @current_table;
        END;
    END; /*End procedure object id check*/

    IF CHARINDEX(N'%', @procedure_name) = 0
    BEGIN
        SELECT
            @current_table = 'checking single procedure existence',
            @sql = @isolation_level;

        IF @troubleshoot_performance = 1
        BEGIN
            EXECUTE sys.sp_executesql
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

        EXECUTE sys.sp_executesql
            @sql,
          N'@procedure_exists bit OUTPUT,
            @procedure_name_quoted sysname',
            @procedure_exists OUTPUT,
            @procedure_name_quoted;

        IF @troubleshoot_performance = 1
        BEGIN
            SET STATISTICS XML OFF;

            EXECUTE sys.sp_executesql
                @troubleshoot_update,
              N'@current_table nvarchar(100)',
                @current_table;

            EXECUTE sys.sp_executesql
                @troubleshoot_info,
              N'@sql nvarchar(max),
                @current_table nvarchar(100)',
                @sql,
                @current_table;
        END;
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
        FROM @database_cursor
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
            IF @debug = 1
            BEGIN
                GOTO DEBUG;
            END;
            ELSE
            BEGIN
                RETURN;
            END;
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
  AND  @sql_2022_views = 0
)
BEGIN
    RAISERROR('Query Store hints, feedback, and variants are not available prior to SQL Server 2022', 10, 1) WITH NOWAIT;

    IF @get_all_databases = 0
    BEGIN
        IF @debug = 1
        BEGIN
            GOTO DEBUG;
        END;
        ELSE
        BEGIN
            RETURN;
        END;
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
        IF @debug = 1
        BEGIN
            GOTO DEBUG;
        END;
        ELSE
        BEGIN
            RETURN;
        END;
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
        IF @debug = 1
        BEGIN
            GOTO DEBUG;
        END;
        ELSE
        BEGIN
            RETURN;
        END;
    END;
END;

/*
These columns are only available in 2017+.
This is an instance-level check.
We do it before the database-level checks because the relevant DMVs may not exist on old versions.
@wait_filter has already been checked.
*/
IF
(
  (
      @sort_order = 'tempdb'
   OR @sort_order_is_a_wait = 1
  )
  AND
  (
      @new = 0
  )
)
BEGIN
   RAISERROR('The sort order (%s) you chose is invalid in product version %i, reverting to sorting by cpu.', 10, 1, @sort_order, @product_version) WITH NOWAIT;

   SELECT
       @sort_order = N'cpu',
       @sort_order_is_a_wait = 0;

   DELETE
   FROM @ColumnDefinitions
   WHERE metric_type IN (N'wait_time', N'top waits');

   UPDATE
       @ColumnDefinitions
   SET
       column_source = N'ROW_NUMBER() OVER (PARTITION BY qsrs.plan_id ORDER BY qsrs.avg_cpu_time_ms DESC)'
   WHERE metric_type = N'n';
END;

/*
Wait stat capture can be enabled or disabled in settings.
This is a database-level check.
*/
IF
(
  @new = 1
)
BEGIN
    SELECT
        @current_table = 'checking query store waits are enabled',
        @sql = @isolation_level;

    IF @troubleshoot_performance = 1
    BEGIN

        EXECUTE sys.sp_executesql
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

    EXECUTE sys.sp_executesql
        @sql,
      N'@query_store_waits_enabled bit OUTPUT',
        @query_store_waits_enabled OUTPUT;

    IF @troubleshoot_performance = 1
    BEGIN
        SET STATISTICS XML OFF;

        EXECUTE sys.sp_executesql
            @troubleshoot_update,
          N'@current_table nvarchar(100)',
            @current_table;

        EXECUTE sys.sp_executesql
            @troubleshoot_info,
          N'@sql nvarchar(max),
            @current_table nvarchar(100)',
            @sql,
            @current_table;
    END;
END;

/*
To avoid mixing sort orders in the @get_all_databases = 1 case, we skip the
database if something wait related is requested on a database that does not capture waits.

There is an edge case.
If you have capturing wait stats disabled, your database can still hold wait stats.
This happens if you turned capturing off after having it on.
We make no attempt to handle this.
Instead, we assume that anyone with capturing wait stats turned off does not want to see them.
*/
IF
(
  (
      @wait_filter IS NOT NULL
   OR @sort_order_is_a_wait = 1
  )
  AND
  (
      @query_store_waits_enabled = 0
  )
)
BEGIN
    IF @get_all_databases = 1
    BEGIN
        RAISERROR('Query Store wait stats are not enabled for database %s, but you have requested them. We are skipping this database and continuing with any that remain.', 10, 1, @database_name_quoted) WITH NOWAIT;
        FETCH NEXT
        FROM @database_cursor
        INTO @database_name;

        CONTINUE;
    END;
    ELSE
    BEGIN
        RAISERROR('Query Store wait stats are not enabled for database %s, but you have requested them. We are reverting to sorting by cpu without respect for any wait filters.', 10, 1, @database_name_quoted) WITH NOWAIT;

        SELECT
            @sort_order = N'cpu',
            @sort_order_is_a_wait = 0,
            @wait_filter = NULL;

        DELETE
        FROM @ColumnDefinitions
        WHERE metric_type IN (N'wait_time');

        UPDATE
            @ColumnDefinitions
        SET
            column_source = N'ROW_NUMBER() OVER (PARTITION BY qsrs.plan_id ORDER BY qsrs.avg_cpu_time_ms DESC)'
        WHERE metric_type = N'n';
    END;
END;

/* There is no reason to show the top_waits column if we know it is NULL. */
IF
(
        @query_store_waits_enabled = 0
    AND @get_all_databases = 0
)
BEGIN
    DELETE
    FROM @ColumnDefinitions
    WHERE metric_type IN (N'top_waits');
END;

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
           IF @debug = 1
           BEGIN
               GOTO DEBUG;
           END;
           ELSE
           BEGIN
               RETURN;
           END;
       END;
END;

/*
See if AGs are a thing so we can skip the checks for replica stuff
*/
IF @azure = 1
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
    END;
END;

/*
Get filters ready, or whatever
We're only going to pull some stuff from runtime stats and plans
*/
IF @start_date <= @end_date
BEGIN
    SELECT
        @where_clause += N'AND   qsrs.last_execution_time >= @start_date
    AND   qsrs.last_execution_time <  @end_date' + @nc10;
END;

/*Other filters*/
IF @duration_ms IS NOT NULL
BEGIN
    SELECT
        @where_clause += N'    AND   qsrs.avg_duration >= (@duration_ms * 1000.)' + @nc10;
END;

IF @execution_type_desc IS NOT NULL
BEGIN
    SELECT
        @where_clause += N'    AND   qsrs.execution_type_desc = @execution_type_desc' + @nc10;
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
        IF @work_start_utc < @work_end_utc
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
        EXECUTE sys.sp_executesql
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
WHERE ';

IF CHARINDEX(N'%', @procedure_name) = 0
BEGIN
    SELECT
        @sql += N'qsq.object_id = OBJECT_ID(@procedure_name_quoted)';
END;

IF CHARINDEX(N'%', @procedure_name) > 0
BEGIN
    SELECT
        @sql += N'EXISTS
(
     SELECT
         1/0
    FROM #procedure_object_ids AS poi
    WHERE poi.[object_id] = qsq.[object_id]
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
        #procedure_plans
    WITH
        (TABLOCK)
    (
        plan_id
    )
    EXECUTE sys.sp_executesql
        @sql,
      N'@procedure_name_quoted sysname',
        @procedure_name_quoted;

    IF @troubleshoot_performance = 1
    BEGIN
        SET STATISTICS XML OFF;

        EXECUTE sys.sp_executesql
            @troubleshoot_update,
          N'@current_table nvarchar(100)',
            @current_table;

        EXECUTE sys.sp_executesql
            @troubleshoot_info,
          N'@sql nvarchar(max),
            @current_table nvarchar(100)',
            @sql,
            @current_table;
    END;

    SELECT
        @where_clause += N'    AND   EXISTS
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
        EXECUTE sys.sp_executesql
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
        #query_types
    WITH
        (TABLOCK)
    (
        plan_id
    )
    EXECUTE sys.sp_executesql
        @sql;

    IF @troubleshoot_performance = 1
    BEGIN
        SET STATISTICS XML OFF;

        EXECUTE sys.sp_executesql
            @troubleshoot_update,
          N'@current_table nvarchar(100)',
            @current_table;

        EXECUTE sys.sp_executesql
            @troubleshoot_info,
          N'@sql nvarchar(max),
            @current_table nvarchar(100)',
            @sql,
            @current_table;
    END;

    SELECT
        @where_clause += N'    AND   EXISTS
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
OR @include_query_hashes IS NOT NULL
OR @include_plan_hashes  IS NOT NULL
OR @include_sql_handles  IS NOT NULL
OR @ignore_query_hashes  IS NOT NULL
OR @ignore_plan_hashes   IS NOT NULL
OR @ignore_sql_handles   IS NOT NULL
)
BEGIN
    SET @filter_cursor =
        CURSOR
        LOCAL
        FORWARD_ONLY
        STATIC
        READ_ONLY
    FOR
    SELECT
        parameter_name,
        parameter_value,
        temp_table_name,
        column_name,
        data_type,
        is_include,
        requires_secondary_processing
    FROM @FilterParameters AS fp;

    OPEN @filter_cursor;

    FETCH NEXT
    FROM @filter_cursor
    INTO
        @param_name,
        @param_value,
        @temp_table,
        @column_name,
        @data_type,
        @is_include,
        @requires_secondary_processing;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        /* Clean parameter value */
        SELECT
            @param_value =
                REPLACE(REPLACE(REPLACE(REPLACE(
                LTRIM(RTRIM(@param_value)),
                CHAR(10), N''), CHAR(13), N''),
                NCHAR(10), N''), NCHAR(13), N'');

        /* Log current operation if debugging */
        IF @debug = 1
        BEGIN
            RAISERROR('Processing %s with value %s', 0, 0, @param_name, @param_value) WITH NOWAIT;
        END;

        /* Set current table name for troubleshooting */
        SELECT
            @current_table = 'inserting ' + @temp_table;

        /* Choose appropriate string split function based on data type */
        IF @data_type = N'bigint'
        BEGIN
            SELECT
                @split_sql = @string_split_ints;
        END
        ELSE
        BEGIN
            SELECT
                @split_sql = @string_split_strings;
        END;

        /* Execute the initial insert with troubleshooting if enabled */
        IF @troubleshoot_performance = 1
        BEGIN
            EXECUTE sys.sp_executesql
                @troubleshoot_insert,
              N'@current_table nvarchar(100)',
                @current_table;

            SET STATISTICS XML ON;
        END;

        /* Execute the dynamic SQL to populate the temporary table */
        SET @dynamic_sql = N'
        INSERT INTO
            ' + @temp_table + N'
        WITH
            (TABLOCK)
        (
            ' + @column_name +
      N')
        EXECUTE sys.sp_executesql
            @split_sql,
         N''@ids nvarchar(4000)'',
            @param_value;';

        IF @debug = 1
        BEGIN
            PRINT @dynamic_sql;
        END;

        EXEC sys.sp_executesql
            @dynamic_sql,
          N'@split_sql nvarchar(max),
            @param_value nvarchar(4000)',
            @split_sql,
            @param_value;

        IF @troubleshoot_performance = 1
        BEGIN
            SET STATISTICS XML OFF;

            EXECUTE sys.sp_executesql
                @troubleshoot_update,
              N'@current_table nvarchar(100)',
                @current_table;

            EXECUTE sys.sp_executesql
                @troubleshoot_info,
              N'@sql nvarchar(max),
                @current_table nvarchar(100)',
                @split_sql,
                @current_table;
        END;

        /* Secondary processing (for parameters that need to populate plan IDs) */
        IF @requires_secondary_processing = 1
        BEGIN
            SELECT
                @current_table = 'inserting #include_plan_ids for ' + @param_name;

            /* Build appropriate SQL based on parameter type */
            IF @param_name = 'include_query_ids'
            OR @param_name = 'ignore_query_ids'
            BEGIN
                SET @secondary_sql = @isolation_level;

                SELECT @secondary_sql += N'
                SELECT DISTINCT
                    qsp.plan_id
                FROM ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
                WHERE EXISTS
                      (
                          SELECT
                              1/0
                          FROM #' +
                              CASE
                                  WHEN @is_include = 1
                                  THEN N'include'
                                  ELSE N'ignore'
                              END +
                              N'_query_ids AS iqi
                          WHERE iqi.query_id = qsp.query_id
                      )
                OPTION(RECOMPILE);' + @nc10;
            END;
            ELSE

            IF @param_name = 'include_query_hashes'
            OR @param_name = 'ignore_query_hashes'
            BEGIN
                SET @secondary_sql = @isolation_level;

                SELECT @secondary_sql += N'
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
                                    FROM #' +
                                        CASE
                                            WHEN @is_include = 1
                                            THEN N'include'
                                            ELSE N'ignore'
                                         END +
                                         N'_query_hashes AS iqh
                                    WHERE iqh.query_hash = qsq.query_hash
                                )
                      )
                OPTION(RECOMPILE);' + @nc10;
            END;
            ELSE

            IF @param_name = 'include_plan_hashes'
            OR @param_name = 'ignore_plan_hashes'
            BEGIN
                SET @secondary_sql = @isolation_level;

                SELECT @secondary_sql += N'
                SELECT DISTINCT
                    qsp.plan_id
                FROM ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
                WHERE EXISTS
                      (
                          SELECT
                              1/0
                          FROM #' +
                              CASE
                                  WHEN @is_include = 1
                                  THEN N'include'
                                  ELSE N'ignore'
                              END + N'_plan_hashes AS iph
                          WHERE iph.plan_hash = qsp.query_plan_hash
                      )
                OPTION(RECOMPILE);' + @nc10;
            END;
            ELSE

            IF @param_name = 'include_sql_handles'
            OR @param_name = 'ignore_sql_handles'
            BEGIN
                SET @secondary_sql = @isolation_level;

                SELECT @secondary_sql += N'
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
                                            FROM #' +
                                                CASE
                                                    WHEN @is_include = 1
                                                    THEN N'include'
                                                    ELSE N'ignore'
                                                END + N'_sql_handles AS ish
                                            WHERE ish.sql_handle = qsqt.statement_sql_handle
                                        )
                              )
                      )
                OPTION(RECOMPILE);' + @nc10;
            END;

            /* Process secondary sql if defined */
            IF @secondary_sql IS NOT NULL
            BEGIN
                IF @troubleshoot_performance = 1
                BEGIN
                    EXECUTE sys.sp_executesql
                        @troubleshoot_insert,
                      N'@current_table nvarchar(100)',
                        @current_table;

                    SET STATISTICS XML ON;
                END;

                IF @debug = 1
                BEGIN
                    PRINT @secondary_sql;
                END;

                /* Insert into the correct target table based on include/ignore */
                IF @is_include = 1
                BEGIN
                    INSERT INTO
                        #include_plan_ids
                    WITH
                        (TABLOCK)
                    (
                        plan_id
                    )
                    EXECUTE sys.sp_executesql
                        @secondary_sql;
                END
                ELSE
                BEGIN
                    INSERT INTO
                        #ignore_plan_ids
                    WITH
                        (TABLOCK)
                    (
                        plan_id
                    )
                    EXECUTE sys.sp_executesql
                        @secondary_sql;
                END;

                IF @troubleshoot_performance = 1
                BEGIN
                    SET STATISTICS XML OFF;

                    EXECUTE sys.sp_executesql
                        @troubleshoot_update,
                      N'@current_table nvarchar(100)',
                        @current_table;

                    EXECUTE sys.sp_executesql
                        @troubleshoot_info,
                      N'@sql nvarchar(max), @current_table nvarchar(100)',
                        @secondary_sql,
                        @current_table;
                END;
            END;
        END;

        /* Update where clause based on parameter type */
        IF @param_name = 'include_plan_ids'
        OR @param_name = 'ignore_plan_ids'
        OR @requires_secondary_processing = 1
        BEGIN
            /* Choose the correct table and exists/not exists operator */
            SELECT
                @temp_target_table =
                    CASE
                        WHEN @is_include = 1
                        THEN N'#include_plan_ids'
                        ELSE N'#ignore_plan_ids'
                    END,
                @exist_or_not_exist =
                    CASE
                        WHEN @is_include = 1
                        THEN N'EXISTS'
                        ELSE N'NOT EXISTS'
                    END;

            /* Add the filter condition to the where clause */
            SELECT
                @where_clause +=
                N'AND   ' +
                @exist_or_not_exist +
                N'
              (
                 SELECT
                    1/0
                 FROM ' + @temp_target_table + N' AS idi
                 WHERE idi.plan_id = qsrs.plan_id
              )' + @nc10;

              IF @debug = 1
              BEGIN
                  PRINT @where_clause;
              END;
        END;

        FETCH NEXT
        FROM @filter_cursor
        INTO
            @param_name,
            @param_value,
            @temp_table,
            @column_name,
            @data_type,
            @is_include,
            @requires_secondary_processing;
    END;
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
            EXECUTE sys.sp_executesql
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
            #only_queries_with_hints
        WITH
            (TABLOCK)
        (
            plan_id
        )
        EXECUTE sys.sp_executesql
            @sql;

        IF @troubleshoot_performance = 1
        BEGIN
            SET STATISTICS XML OFF;

            EXECUTE sys.sp_executesql
                @troubleshoot_update,
              N'@current_table nvarchar(100)',
                @current_table;

            EXECUTE sys.sp_executesql
                @troubleshoot_info,
              N'@sql nvarchar(max),
                @current_table nvarchar(100)',
                @sql,
                @current_table;
        END;

        SELECT
            @where_clause += N'    AND   EXISTS
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
            EXECUTE sys.sp_executesql
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
            #only_queries_with_feedback
        WITH
            (TABLOCK)
        (
            plan_id
        )
        EXECUTE sys.sp_executesql
            @sql;

        IF @troubleshoot_performance = 1
        BEGIN
            SET STATISTICS XML OFF;

            EXECUTE sys.sp_executesql
                @troubleshoot_update,
              N'@current_table nvarchar(100)',
                @current_table;

            EXECUTE sys.sp_executesql
                @troubleshoot_info,
              N'@sql nvarchar(max),
                @current_table nvarchar(100)',
                @sql,
                @current_table;
        END;

        SELECT
            @where_clause += N'    AND   EXISTS
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
            EXECUTE sys.sp_executesql
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
            #only_queries_with_variants
        WITH
            (TABLOCK)
        (
            plan_id
        )
        EXECUTE sys.sp_executesql
            @sql;

        IF @troubleshoot_performance = 1
        BEGIN
            SET STATISTICS XML OFF;

            EXECUTE sys.sp_executesql
                @troubleshoot_update,
              N'@current_table nvarchar(100)',
                @current_table;

            EXECUTE sys.sp_executesql
                @troubleshoot_info,
              N'@sql nvarchar(max),
                @current_table nvarchar(100)',
                @sql,
                @current_table;
        END;

        SELECT
            @where_clause += N'    AND   EXISTS
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
        EXECUTE sys.sp_executesql
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
AND   qsp.last_force_failure_reason > 0';
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
        #forced_plans_failures
    WITH
        (TABLOCK)
    (
        plan_id
    )
    EXECUTE sys.sp_executesql
        @sql;

    IF @troubleshoot_performance = 1
    BEGIN
        SET STATISTICS XML OFF;

        EXECUTE sys.sp_executesql
            @troubleshoot_update,
          N'@current_table nvarchar(100)',
            @current_table;

        EXECUTE sys.sp_executesql
            @troubleshoot_info,
          N'@sql nvarchar(max),
            @current_table nvarchar(100)',
            @sql,
            @current_table;
    END;

    SELECT
        @where_clause += N'    AND   EXISTS
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
        EXECUTE sys.sp_executesql
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
        #query_text_search
    WITH
        (TABLOCK)
    (
        plan_id
    )
    EXECUTE sys.sp_executesql
        @sql,
      N'@query_text_search nvarchar(4000)',
        @query_text_search;

    IF @troubleshoot_performance = 1
    BEGIN
        SET STATISTICS XML OFF;

        EXECUTE sys.sp_executesql
            @troubleshoot_update,
          N'@current_table nvarchar(100)',
            @current_table;

        EXECUTE sys.sp_executesql
            @troubleshoot_info,
          N'@sql nvarchar(max),
            @current_table nvarchar(100)',
            @sql,
            @current_table;
    END;

    SELECT
        @where_clause += N'    AND   EXISTS
       (
           SELECT
               1/0
           FROM #query_text_search AS qst
           WHERE qst.plan_id = qsrs.plan_id
       )' + @nc10;
END;

IF @query_text_search_not IS NOT NULL
BEGIN
    IF
    (
        LEFT
        (
            @query_text_search_not,
            1
        ) <> N'%'
    )
    BEGIN
        SELECT
            @query_text_search_not =
                N'%' + @query_text_search_not;
    END;

    IF
    (
        LEFT
        (
            REVERSE
            (
                @query_text_search_not
            ),
            1
        ) <> N'%'
    )
    BEGIN
        SELECT
            @query_text_search_not =
                @query_text_search_not + N'%';
    END;

    /* If our query texts contains square brackets (common in Entity Framework queries), add a leading escape character to each bracket character */
    IF @escape_brackets = 1
    BEGIN
        SELECT
            @query_text_search_not =
                REPLACE(REPLACE(REPLACE(
                    @query_text_search_not,
                N'[', @escape_character + N'['),
                N']', @escape_character + N']'),
                N'_', @escape_character + N'_');
    END;

    SELECT
        @current_table = 'inserting #query_text_search_not',
        @sql = @isolation_level;

    IF @troubleshoot_performance = 1
    BEGIN
        EXECUTE sys.sp_executesql
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
                  AND   qsqt.query_sql_text LIKE @query_text_search_not
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
                    N'@query_text_search_not',
                    N'@query_text_search_not ESCAPE ''' + @escape_character + N''''
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
        #query_text_search_not
    WITH
        (TABLOCK)
    (
        plan_id
    )
    EXECUTE sys.sp_executesql
        @sql,
      N'@query_text_search_not nvarchar(4000)',
        @query_text_search_not;

    IF @troubleshoot_performance = 1
    BEGIN
        SET STATISTICS XML OFF;

        EXECUTE sys.sp_executesql
            @troubleshoot_update,
          N'@current_table nvarchar(100)',
            @current_table;

        EXECUTE sys.sp_executesql
            @troubleshoot_info,
          N'@sql nvarchar(max),
            @current_table nvarchar(100)',
            @sql,
            @current_table;
    END;

    SELECT
        @where_clause += N'    AND   NOT EXISTS
       (
           SELECT
               1/0
           FROM #query_text_search_not AS qst
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
            EXECUTE sys.sp_executesql
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
        #wait_filter
    WITH
        (TABLOCK)
    (
        plan_id
    )
    EXECUTE sys.sp_executesql
        @sql,
      N'@top bigint',
        @top;

    IF @troubleshoot_performance = 1
    BEGIN
        SET STATISTICS XML OFF;

        EXECUTE sys.sp_executesql
            @troubleshoot_update,
          N'@current_table nvarchar(100)',
            @current_table;

        EXECUTE sys.sp_executesql
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
IF @include_maintenance = 0
BEGIN
SELECT
    @current_table = 'inserting #maintenance_plans',
    @sql = @isolation_level;

IF @troubleshoot_performance = 1
BEGIN
    EXECUTE sys.sp_executesql
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
          AND   qsqt.query_sql_text NOT LIKE N''%SELECT StatMan%''
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
    #maintenance_plans
WITH
    (TABLOCK)
(
    plan_id
)
EXECUTE sys.sp_executesql
    @sql;

IF @troubleshoot_performance = 1
BEGIN
    SET STATISTICS XML OFF;

    EXECUTE sys.sp_executesql
        @troubleshoot_update,
      N'@current_table nvarchar(100)',
        @current_table;

    EXECUTE sys.sp_executesql
        @troubleshoot_info,
      N'@sql nvarchar(max),
        @current_table nvarchar(100)',
        @sql,
        @current_table;
END;

SELECT
    @where_clause += N'    AND   NOT EXISTS
      (
          SELECT
              1/0
          FROM #maintenance_plans AS mp
          WHERE mp.plan_id = qsrs.plan_id
      )' + @nc10;
END;

/*
Filtering by @execution_count is non-trivial.
In the Query Store DMVs, execution counts only exist in
sys.query_store_runtime_stats.
That DMV has no query_id column (or anything similar),
but we promised that @execution_count would filter by the
number of executions of the query.
The best column for us in the DMV is plan_id, so we need
to get from there to query_id.
Because we do most of our filtering work in #distinct_plans,
we must also make what we do here compatible with that.

In conclusion, we want produce a temp table holding the
plan_ids for the queries with @execution_count or more executions.

This is similar to the sort-helping tables that you are
about to see, but easier because we do not need to return or sort
by the execution count.
We just need to know that these plans have enough executions.
*/
IF @execution_count > 0
BEGIN
    SELECT
        @current_table = 'inserting #plan_ids_having_enough_executions',
        @sql = @isolation_level;

    IF @troubleshoot_performance = 1
    BEGIN
        EXECUTE sys.sp_executesql
            @troubleshoot_insert,
          N'@current_table nvarchar(100)',
            @current_table;

        SET STATISTICS XML ON;
    END;

    SELECT
        @sql += N'
    SELECT DISTINCT
        unfiltered_execution_counts.plan_id
    FROM
    (
       SELECT
           qsp.plan_id,
           total_executions_for_query_of_plan =
               SUM(qsrs.count_executions) OVER (PARTITION BY qsq.query_id)
       FROM ' + @database_name_quoted + N'.sys.query_store_query AS qsq
       JOIN ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
         ON qsq.query_id = qsp.query_id
       JOIN ' + @database_name_quoted + N'.sys.query_store_runtime_stats AS qsrs
         ON qsp.plan_id = qsrs.plan_id
       WHERE 1 = 1
       ' + @where_clause
         + N'
    ) AS unfiltered_execution_counts
    WHERE
        unfiltered_execution_counts.total_executions_for_query_of_plan >= @execution_count
    OPTION(RECOMPILE);' + @nc10;

    IF @debug = 1
    BEGIN
        PRINT LEN(@sql);
        PRINT @sql;
    END;

    INSERT
        #plan_ids_having_enough_executions
    WITH
        (TABLOCK)
    (
        plan_id
    )
    EXECUTE sys.sp_executesql
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
        @work_end_utc,
        @regression_baseline_start_date,
        @regression_baseline_end_date;

    IF @troubleshoot_performance = 1
    BEGIN
        SET STATISTICS XML OFF;

        EXECUTE sys.sp_executesql
            @troubleshoot_update,
          N'@current_table nvarchar(100)',
            @current_table;

        EXECUTE sys.sp_executesql
            @troubleshoot_info,
          N'@sql nvarchar(max),
            @current_table nvarchar(100)',
            @sql,
            @current_table;
    END;

SELECT
    @where_clause += N'    AND EXISTS
    (
        SELECT
            1/0
        FROM #plan_ids_having_enough_executions AS enough_executions
        WHERE enough_executions.plan_id = qsrs.plan_id
    )' + @nc10;
END;

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
Regression mode differs significantly from our defaults.
In this mode, we measure every query hash in the time period
specified by @regression_baseline_start_date and
@regression_baseline_end_date ("the baseline time period").
Our measurements are taken based on the metric given
by @sort_order.
For all of the hashes we have taken measurements for, we
make the same measurement for the time period specified
by @start_date and @end_date ("the current time period").
We then compare each hashes' measurement across the two
time periods, by the means specified by
@regression_comparator and take the @top results ordered by
@regression_direction.
We then get every plan_id in both time periods for those
query hashes and carry on as normal.

This gives us three immediate concerns. We:
   1) Need to adjust our @where_clause to refer to the
      baseline time period.
   2) Need all of the queries from the baseline time
      period (rather than just the @top whatever).
   3) Are interested in the query hashes rather than
      just plan_ids.

We address part of the first concern immediately.
Later, we will do some wicked and foul things to
modify our dynamic SQL's usages of @where_clause
to use @regression_where_clause.
*/
IF @regression_mode = 1
BEGIN

SELECT
    @regression_where_clause =
        REPLACE
        (
            REPLACE
            (
                @where_clause,
                '@start_date',
                '@regression_baseline_start_date'
            ),
           '@end_date',
           '@regression_baseline_end_date'
        );
END;

/*
Populate sort-helping tables, if needed.

In theory, these exist just to put in scope
columns that wouldn't normally be in scope.
However, they're also quite helpful for the next
temp table, #distinct_plans.

Note that this block must come after we are done with
anything that edits @where_clause because we want to use
that here.

Regression mode complicates this process considerably.
It forces us to use different dates.
We also have to adjust @top.

Luckily, the 'plan count by hashes' sort
order is not supported in regression mode.
Earlier on, we throw an error if somebody
tries (it just doesn't make sense).
*/
IF @sort_order = 'plan count by hashes'
BEGIN
    SELECT
        @current_table = 'inserting #plan_ids_with_query_hashes',
        @sql = @isolation_level;

    IF @troubleshoot_performance = 1
    BEGIN
        EXECUTE sys.sp_executesql
            @troubleshoot_insert,
          N'@current_table nvarchar(100)',
            @current_table;

        SET STATISTICS XML ON;
    END;

    SELECT
    /*
    This sort order is useless if we don't show the
    ties, so only DENSE_RANK() makes sense to use.
    This is why this is not SELECT TOP.
    */
        @sql += N'
    SELECT
        @database_id,
        ranked_plans.plan_id,
        ranked_plans.query_hash,
        ranked_plans.plan_hash_count_for_query_hash
    FROM
    (
        SELECT
            QueryHashesWithIds.plan_id,
            QueryHashesWithCounts.query_hash,
            QueryHashesWithCounts.plan_hash_count_for_query_hash,
            ranking =
                DENSE_RANK() OVER
                (
                    ORDER BY
                        QueryHashesWithCounts.plan_hash_count_for_query_hash DESC,
                        QueryHashesWithCounts.query_hash DESC
                )
        FROM
        (
           SELECT
               qsq.query_hash,
               plan_hash_count_for_query_hash =
                   COUNT(DISTINCT qsp.query_plan_hash)
           FROM ' + @database_name_quoted + N'.sys.query_store_query AS qsq
           JOIN ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
             ON qsq.query_id = qsp.query_id
           JOIN ' + @database_name_quoted + N'.sys.query_store_runtime_stats AS qsrs
             ON qsp.plan_id = qsrs.plan_id
           WHERE 1 = 1
           ' + @where_clause
             + N'
           GROUP
               BY qsq.query_hash
        ) AS QueryHashesWithCounts
        JOIN
        (
           SELECT DISTINCT
               qsq.query_hash,
               qsp.plan_id
           FROM ' + @database_name_quoted + N'.sys.query_store_query AS qsq
           JOIN ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
              ON qsq.query_id = qsp.query_id
           JOIN ' + @database_name_quoted + N'.sys.query_store_runtime_stats AS qsrs
             ON qsp.plan_id = qsrs.plan_id
            WHERE 1 = 1
           ' + @where_clause
             + N'
        ) AS QueryHashesWithIds
          ON QueryHashesWithCounts.query_hash = QueryHashesWithIds.query_hash
    ) AS ranked_plans
    WHERE ranked_plans.ranking <= @top
    OPTION(RECOMPILE, OPTIMIZE FOR (@top = 9223372036854775807));' + @nc10;

    IF @debug = 1
    BEGIN
        PRINT LEN(@sql);
        PRINT @sql;
    END;

    INSERT
        #plan_ids_with_query_hashes
    WITH
        (TABLOCK)
    (
        database_id,
        plan_id,
        query_hash,
        plan_hash_count_for_query_hash
    )
    EXECUTE sys.sp_executesql
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
        @work_end_utc,
        @regression_baseline_start_date,
        @regression_baseline_end_date;

    IF @troubleshoot_performance = 1
    BEGIN
        SET STATISTICS XML OFF;

        EXECUTE sys.sp_executesql
            @troubleshoot_update,
          N'@current_table nvarchar(100)',
            @current_table;

        EXECUTE sys.sp_executesql
            @troubleshoot_info,
          N'@sql nvarchar(max),
            @current_table nvarchar(100)',
            @sql,
            @current_table;
    END;
END;
IF @sort_order = 'total waits'
BEGIN
    SELECT
        @current_table = 'inserting #plan_ids_with_total_waits',
        @sql = @isolation_level;

    IF @troubleshoot_performance = 1
    BEGIN
        EXECUTE sys.sp_executesql
            @troubleshoot_insert,
          N'@current_table nvarchar(100)',
            @current_table;

        SET STATISTICS XML ON;
    END;

    SELECT
        @sql += N'
    SELECT TOP (@top)
        @database_id,
        qsrs.plan_id,
        from_regression_baseline =
            CASE
                WHEN qsrs.last_execution_time >= @start_date
                AND  qsrs.last_execution_time < @end_date
                THEN ''No''
                ELSE ''Yes''
            END,
        total_query_wait_time_ms =
            SUM(qsws.total_query_wait_time_ms)
    FROM ' + @database_name_quoted + N'.sys.query_store_runtime_stats AS qsrs
    JOIN ' + @database_name_quoted + N'.sys.query_store_wait_stats AS qsws
      ON qsrs.plan_id = qsws.plan_id
    WHERE 1 = 1
    '
   + CASE WHEN @regression_mode = 1
      THEN N' AND ( 1 = 1
      ' + @regression_where_clause
      + N' )
OR
      ( 1 = 1
      '
      + @where_clause
      + N' ) '
      ELSE @where_clause
      END
      + N'
    GROUP
        BY qsrs.plan_id,
        CASE
            WHEN qsrs.last_execution_time >= @start_date
            AND  qsrs.last_execution_time < @end_date
            THEN ''No''
            ELSE ''Yes''
        END
    ORDER BY
        SUM(qsws.total_query_wait_time_ms) DESC
    OPTION(RECOMPILE, OPTIMIZE FOR (@top = 9223372036854775807));' + @nc10;

    IF @regression_mode = 1
    BEGIN

        /* Very stupid way to stop us repeating the above code. */
        SELECT
           @sql = REPLACE
                   (
                       @sql,
                       'TOP (@top)',
                       'TOP (2147483647 + (0 * @top))'
                   );
    END;

    IF @debug = 1
    BEGIN
        PRINT LEN(@sql);
        PRINT @sql;
    END;

    INSERT
        #plan_ids_with_total_waits
    WITH
        (TABLOCK)
    (
        database_id,
        plan_id,
        from_regression_baseline,
        total_query_wait_time_ms
    )
    EXECUTE sys.sp_executesql
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
        @work_end_utc,
        @regression_baseline_start_date,
        @regression_baseline_end_date;

    IF @troubleshoot_performance = 1
    BEGIN
        SET STATISTICS XML OFF;

        EXECUTE sys.sp_executesql
            @troubleshoot_update,
          N'@current_table nvarchar(100)',
            @current_table;

        EXECUTE sys.sp_executesql
            @troubleshoot_info,
          N'@sql nvarchar(max),
            @current_table nvarchar(100)',
            @sql,
            @current_table;
    END;
END;
/*
'total waits' is special. It's a sum, not a max, so
we cover it above rather than here.
*/

IF  @sort_order_is_a_wait = 1
AND @sort_order <> 'total waits'
BEGIN
    SELECT
        @current_table = 'inserting #plan_ids_with_total_waits',
        @sql = @isolation_level;

    IF @troubleshoot_performance = 1
    BEGIN
        EXECUTE sys.sp_executesql
            @troubleshoot_insert,
          N'@current_table nvarchar(100)',
            @current_table;

        SET STATISTICS XML ON;
    END;

    SELECT
        @sql += N'
    SELECT TOP (@top)
        @database_id,
        qsrs.plan_id,
        from_regression_baseline =
            CASE
                WHEN qsrs.last_execution_time >= @start_date
                AND   qsrs.last_execution_time < @end_date
                THEN ''No''
                ELSE ''Yes''
            END,
        total_query_wait_time_ms =
            MAX(qsws.total_query_wait_time_ms)
    FROM ' + @database_name_quoted + N'.sys.query_store_runtime_stats AS qsrs
    JOIN ' + @database_name_quoted + N'.sys.query_store_wait_stats AS qsws
      ON qsrs.plan_id = qsws.plan_id
    WHERE 1 = 1
    AND qsws.wait_category = '  +
    CASE @sort_order
         WHEN 'cpu waits' THEN N'1'
         WHEN 'lock waits' THEN N'3'
         WHEN 'locks waits' THEN N'3'
         WHEN 'latch waits' THEN N'4'
         WHEN 'latches waits' THEN N'4'
         WHEN 'buffer latch waits' THEN N'5'
         WHEN 'buffer latches waits' THEN N'5'
         WHEN 'buffer io waits' THEN N'6'
         WHEN 'log waits' THEN N'14'
         WHEN 'log io waits' THEN N'14'
         WHEN 'network waits' THEN N'15'
         WHEN 'network io waits' THEN N'15'
         WHEN 'parallel waits' THEN N'16'
         WHEN 'parallelism waits' THEN N'16'
         WHEN 'memory waits' THEN N'17'
    END
      + N'
      '
      + CASE WHEN @regression_mode = 1
         THEN N' AND ( 1 = 1
         ' + @regression_where_clause
         + N' )
   OR
         ( 1 = 1
         '
         + @where_clause
         + N' ) '
         ELSE @where_clause
         END
      + N'
    GROUP
        BY qsrs.plan_id,
        CASE
            WHEN qsrs.last_execution_time >= @start_date
            AND  qsrs.last_execution_time < @end_date
            THEN ''No''
            ELSE ''Yes''
        END
    ORDER BY
        MAX(qsws.total_query_wait_time_ms) DESC
    OPTION(RECOMPILE, OPTIMIZE FOR (@top = 9223372036854775807));' + @nc10;

    IF @regression_mode = 1
    BEGIN

        /* Very stupid way to stop us repeating the above code. */
        SELECT
           @sql = REPLACE
                   (
                       @sql,
                       'TOP (@top)',
                       'TOP (2147483647 + (0 * @top))'
                   );
    END;

    IF @debug = 1
    BEGIN
        PRINT LEN(@sql);
        PRINT @sql;
    END;

    INSERT
        #plan_ids_with_total_waits
    WITH
        (TABLOCK)
    (
        database_id,
        plan_id,
        from_regression_baseline,
        total_query_wait_time_ms
    )
    EXECUTE sys.sp_executesql
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
        @work_end_utc,
        @regression_baseline_start_date,
        @regression_baseline_end_date;

    IF @troubleshoot_performance = 1
    BEGIN
        SET STATISTICS XML OFF;

        EXECUTE sys.sp_executesql
            @troubleshoot_update,
          N'@current_table nvarchar(100)',
            @current_table;

        EXECUTE sys.sp_executesql
            @troubleshoot_info,
          N'@sql nvarchar(max),
            @current_table nvarchar(100)',
            @sql,
            @current_table;
    END;
END;
/*End populating sort-helping tables*/

/*
This is where the bulk of the regression mode
work is done. We grab the metrics for both time
periods for each query hash, compare them,
and get the @top.
*/
IF @regression_mode = 1
BEGIN
    /*
    We begin by getting the metrics per query hash
    in the time period.
    */
    SELECT
        @current_table = 'inserting #regression_baseline_runtime_stats',
        @sql = @isolation_level;

    IF @troubleshoot_performance = 1
    BEGIN
        EXECUTE sys.sp_executesql
            @troubleshoot_insert,
          N'@current_table nvarchar(100)',
            @current_table;

        SET STATISTICS XML ON;
    END;

    SELECT
        @sql += N'
    SELECT
        qsq.query_hash,
        /* All of these but count_executions are already floats. */
        regression_metric_average =
            CONVERT
            (
                float,
                AVG
                (' +
                CASE @sort_order
                     WHEN 'cpu' THEN N'qsrs.avg_cpu_time'
                     WHEN 'logical reads' THEN N'qsrs.avg_logical_io_reads'
                     WHEN 'physical reads' THEN N'qsrs.avg_physical_io_reads'
                     WHEN 'writes' THEN N'qsrs.avg_logical_io_writes'
                     WHEN 'duration' THEN N'qsrs.avg_duration'
                     WHEN 'memory' THEN N'qsrs.avg_query_max_used_memory'
                     WHEN 'tempdb' THEN CASE WHEN @new = 1 THEN N'qsrs.avg_tempdb_space_used' ELSE N'qsrs.avg_cpu_time' END
                     WHEN 'executions' THEN N'qsrs.count_executions'
                     WHEN 'rows' THEN N'qsrs.avg_rowcount'
                     ELSE CASE WHEN @sort_order_is_a_wait = 1 THEN N'waits.total_query_wait_time_ms' ELSE N'qsrs.avg_cpu_time' END
                END
                + N'
                )
            )
    FROM ' + @database_name_quoted + N'.sys.query_store_query AS qsq
    JOIN ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
      ON qsq.query_id = qsp.query_id
    JOIN ' + @database_name_quoted + N'.sys.query_store_runtime_stats AS qsrs
      ON qsp.plan_id = qsrs.plan_id
    LEFT JOIN #plan_ids_with_total_waits AS waits
      ON  qsp.plan_id = waits.plan_id
      AND waits.from_regression_baseline = ''Yes''
    WHERE 1 = 1
    ' + @regression_where_clause
      + N'
    GROUP
        BY qsq.query_hash
    OPTION(RECOMPILE);' + @nc10;

    IF @debug = 1
    BEGIN
        PRINT LEN(@sql);
        PRINT @sql;
    END;

    INSERT
        #regression_baseline_runtime_stats
    WITH
        (TABLOCK)
    (
        query_hash,
        regression_metric_average
    )
    EXECUTE sys.sp_executesql
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
        @work_end_utc,
        @regression_baseline_start_date,
        @regression_baseline_end_date;

    IF @troubleshoot_performance = 1
    BEGIN
        SET STATISTICS XML OFF;

        EXECUTE sys.sp_executesql
            @troubleshoot_update,
          N'@current_table nvarchar(100)',
            @current_table;

        EXECUTE sys.sp_executesql
            @troubleshoot_info,
          N'@sql nvarchar(max),
            @current_table nvarchar(100)',
            @sql,
            @current_table;
    END;

    /*
    We now take the same measurement for all of the same query hashes,
    but in the @where_clause time period.
    */
    SELECT
        @current_table = 'inserting #regression_current_runtime_stats',
        @sql = @isolation_level;

    IF @troubleshoot_performance = 1
    BEGIN
        EXECUTE sys.sp_executesql
            @troubleshoot_insert,
          N'@current_table nvarchar(100)',
            @current_table;

        SET STATISTICS XML ON;
    END;

    SELECT
        @sql += N'
    SELECT
        qsq.query_hash,
        /* All of these but count_executions are already floats. */
        current_metric_average =
            CONVERT
            (
                float,
                AVG
                (' +
                CASE @sort_order
                     WHEN 'cpu' THEN N'qsrs.avg_cpu_time'
                     WHEN 'logical reads' THEN N'qsrs.avg_logical_io_reads'
                     WHEN 'physical reads' THEN N'qsrs.avg_physical_io_reads'
                     WHEN 'writes' THEN N'qsrs.avg_logical_io_writes'
                     WHEN 'duration' THEN N'qsrs.avg_duration'
                     WHEN 'memory' THEN N'qsrs.avg_query_max_used_memory'
                     WHEN 'tempdb' THEN CASE WHEN @new = 1 THEN N'qsrs.avg_tempdb_space_used' ELSE N'qsrs.avg_cpu_time' END
                     WHEN 'executions' THEN N'qsrs.count_executions'
                     WHEN 'rows' THEN N'qsrs.avg_rowcount'
                     ELSE CASE WHEN @sort_order_is_a_wait = 1 THEN N'waits.total_query_wait_time_ms' ELSE N'qsrs.avg_cpu_time' END
                END
                + N'
               )
            )
    FROM ' + @database_name_quoted + N'.sys.query_store_query AS qsq
    JOIN ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
      ON qsq.query_id = qsp.query_id
    JOIN ' + @database_name_quoted + N'.sys.query_store_runtime_stats AS qsrs
      ON qsp.plan_id = qsrs.plan_id
    LEFT JOIN #plan_ids_with_total_waits AS waits
      ON  qsp.plan_id = waits.plan_id
      AND waits.from_regression_baseline = ''No''
    WHERE 1 = 1
    AND EXISTS
    (
        SELECT
            1/0
        FROM #regression_baseline_runtime_stats AS base
        WHERE base.query_hash = qsq.query_hash
    )
    ' + @where_clause
      + N'
    GROUP
        BY qsq.query_hash
    OPTION(RECOMPILE);' + @nc10;

    IF @debug = 1
    BEGIN
        PRINT LEN(@sql);
        PRINT @sql;
    END;

    INSERT
        #regression_current_runtime_stats
    WITH
        (TABLOCK)
    (
        query_hash,
        current_metric_average
    )
    EXECUTE sys.sp_executesql
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
        @work_end_utc,
        @regression_baseline_start_date,
        @regression_baseline_end_date;

    IF @troubleshoot_performance = 1
    BEGIN
        SET STATISTICS XML OFF;

        EXECUTE sys.sp_executesql
            @troubleshoot_update,
          N'@current_table nvarchar(100)',
            @current_table;

        EXECUTE sys.sp_executesql
            @troubleshoot_info,
          N'@sql nvarchar(max),
            @current_table nvarchar(100)',
            @sql,
            @current_table;
    END;

    SELECT
        @current_table = 'inserting #regression_changes',
        @sql = @isolation_level;

    IF @troubleshoot_performance = 1
    BEGIN
        EXECUTE sys.sp_executesql
            @troubleshoot_insert,
          N'@current_table nvarchar(100)',
            @current_table;

        SET STATISTICS XML ON;
    END;

    /*
    Now that we have the data from
    both time periods, we must
    compare them as @regression_comparator
    demands and order them as
    @regression_direction demands.

    However, we care about query_hashes
    here despite everything after this
    wanting plan_ids. This means we
    must repeat some of the tricks
    we used for #plan_ids_with_query_hashes.
    */
    SELECT
        @sql += N'
    SELECT
        @database_id,
        plans_for_hashes.plan_id,
        hashes_with_changes.query_hash,
        change_since_regression_time_period =
        ' +
        /*
        If we are returning differences that are not percentages,
        then we need the units we show for any given metric to be
        the same as anywhere else that gives the same metric.
        If we do not, then our final output will look wrong.
        For example, our CPU time will be 1,000 times bigger
        here than it is in any other column.
        To avoid this problem, we need to replicate the calculations
        later used to populate #query_store_runtime_stats.
        */
        CASE @regression_comparator
            WHEN 'absolute' THEN
                CASE @sort_order
                     WHEN 'cpu' THEN N'hashes_with_changes.change_since_regression_time_period / 1000.'
                     WHEN 'logical reads' THEN N'(hashes_with_changes.change_since_regression_time_period * 8.) / 1024.'
                     WHEN 'physical reads' THEN N'(hashes_with_changes.change_since_regression_time_period * 8.) / 1024.'
                     WHEN 'writes' THEN N'(hashes_with_changes.change_since_regression_time_period * 8.) / 1024.'
                     WHEN 'duration' THEN N'hashes_with_changes.change_since_regression_time_period / 1000.'
                     WHEN 'memory' THEN N'(hashes_with_changes.change_since_regression_time_period * 8.) / 1024.'
                     WHEN 'tempdb' THEN CASE WHEN @new = 1 THEN N'(hashes_with_changes.change_since_regression_time_period * 8.) / 1024.' ELSE N'hashes_with_changes.change_since_regression_time_period / 1000.' END
                     WHEN 'executions' THEN N'hashes_with_changes.change_since_regression_time_period'
                     WHEN 'rows' THEN N'hashes_with_changes.change_since_regression_time_period'
                     ELSE CASE WHEN @sort_order_is_a_wait = 1 THEN N'hashes_with_changes.change_since_regression_time_period / 1000.' ELSE N'hashes_with_changes.change_since_regression_time_period / 1000.' END
                END
            ELSE N'hashes_with_changes.change_since_regression_time_period' END
        + N'
    FROM
    (
        SELECT TOP (@top)
            compared_stats.query_hash,
            compared_stats.change_since_regression_time_period
        FROM
        (
            SELECT
                current_stats.query_hash,
                change_since_regression_time_period =
                '
                + CASE @regression_comparator
                      WHEN 'relative' THEN N'((current_stats.current_metric_average / NULLIF(baseline.regression_metric_average, 0.0)) - 1.0)'
                      WHEN 'absolute' THEN N'(current_stats.current_metric_average - baseline.regression_metric_average)'
                  END
                + N'
            FROM #regression_current_runtime_stats AS current_stats
            JOIN #regression_baseline_runtime_stats AS baseline
              ON current_stats.query_hash = baseline.query_hash
        ) AS compared_stats
        ORDER BY
            '
            /*
            Current metrics that are better than that of the baseline period,
            will give change_since_regression_time_period values that
            are smaller than metrics that are worse.
            In other words, ORDER BY change_since_regression_time_period DESC
            gives us the regressed queries first.
            This is true regardless of @regression_comparator.
            To make @regression_direction behave as intended, we
            need to account for this. We could use dynamic SQL,
            but mathematics has given us better tools.
            */
            + CASE @regression_direction
                   WHEN 'regressed' THEN N'change_since_regression_time_period'
                   WHEN 'worse' THEN N'change_since_regression_time_period'
                   WHEN 'improved' THEN N'change_since_regression_time_period * -1.0'
                   WHEN 'better' THEN N'change_since_regression_time_period * -1.0'
                   /*
                   The following two branches cannot be hit if
                   @regression_comparator is 'relative'.
                   We have made errors be thrown if somebody tries
                   to mix the two.
                   If you can figure out a way to make the two make
                   sense together, then feel free to add it in.
                   */
                   WHEN 'magnitude' THEN N'ABS(change_since_regression_time_period)'
                   WHEN 'absolute' THEN N'ABS(change_since_regression_time_period)'
              END
            + N' DESC
    ) AS hashes_with_changes
    JOIN
    (
       SELECT DISTINCT
           qsq.query_hash,
           qsp.plan_id
       FROM ' + @database_name_quoted + N'.sys.query_store_query AS qsq
       JOIN ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
         ON qsq.query_id = qsp.query_id
       JOIN ' + @database_name_quoted + N'.sys.query_store_runtime_stats AS qsrs
         ON qsp.plan_id = qsrs.plan_id
        WHERE
            ( 1 = 1
            '
            /* We want each time period's plan_ids for these query hashes. */
            + @regression_where_clause
            + N'
            )
        OR
            ( 1 = 1
            '
            + @where_clause
         + N'
            )
    ) AS plans_for_hashes
      ON hashes_with_changes.query_hash = plans_for_hashes.query_hash
    OPTION(RECOMPILE, OPTIMIZE FOR (@top = 9223372036854775807));' + @nc10;

    IF @debug = 1
    BEGIN
        PRINT LEN(@sql);
        PRINT @sql;
    END;

    INSERT
        #regression_changes
    WITH
        (TABLOCK)
    (
        database_id,
        plan_id,
        query_hash,
        change_since_regression_time_period
    )
    EXECUTE sys.sp_executesql
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
        @work_end_utc,
        @regression_baseline_start_date,
        @regression_baseline_end_date;

    IF @troubleshoot_performance = 1
    BEGIN
        SET STATISTICS XML OFF;

        EXECUTE sys.sp_executesql
            @troubleshoot_update,
          N'@current_table nvarchar(100)',
            @current_table;

        EXECUTE sys.sp_executesql
            @troubleshoot_info,
          N'@sql nvarchar(max),
            @current_table nvarchar(100)',
            @sql,
            @current_table;
    END;

END;

/*
This gets the plan_ids we care about.

We unfortunately need an ELSE IF chain here
because the final branch contains defaults
that we only want to hit if we did not hit
any others.
*/
SELECT
    @current_table = 'inserting #distinct_plans',
    @sql = @isolation_level;

IF @troubleshoot_performance = 1
BEGIN
    EXECUTE sys.sp_executesql
        @troubleshoot_insert,
      N'@current_table nvarchar(100)',
        @current_table;

    SET STATISTICS XML ON;
END;

IF @regression_mode = 1
BEGIN
    SELECT
        @sql += N'
    SELECT DISTINCT
        plan_id
    FROM #regression_changes
    WHERE database_id = @database_id
    OPTION(RECOMPILE);' + @nc10;
END;
ELSE IF @sort_order = 'plan count by hashes'
BEGIN
    SELECT
        @sql += N'
    SELECT DISTINCT
        plan_id
    FROM #plan_ids_with_query_hashes
    WHERE database_id = @database_id
    OPTION(RECOMPILE);' + @nc10;
END;
ELSE IF @sort_order_is_a_wait = 1
BEGIN
    SELECT
        @sql += N'
    SELECT DISTINCT
        plan_id
    FROM #plan_ids_with_total_waits
    WHERE database_id = @database_id
    OPTION(RECOMPILE);' + @nc10;
END;
ELSE
BEGIN
    SELECT
        @sql += N'
    SELECT TOP (@top)
        qsrs.plan_id
    FROM ' + @database_name_quoted + N'.sys.query_store_runtime_stats AS qsrs
    WHERE 1 = 1
    ' + @where_clause
      + N'
    GROUP BY
        qsrs.plan_id
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
         WHEN 'rows' THEN N'qsrs.avg_rowcount'
         ELSE N'qsrs.avg_cpu_time'
    END +
    N') DESC
    OPTION(RECOMPILE, OPTIMIZE FOR (@top = 9223372036854775807));' + @nc10;
END;

IF @debug = 1
BEGIN
    PRINT LEN(@sql);
    PRINT @sql;
END;

INSERT
    #distinct_plans
WITH
    (TABLOCK)
(
    plan_id
)
EXECUTE sys.sp_executesql
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
    @work_end_utc,
    @regression_baseline_start_date,
    @regression_baseline_end_date;

IF @troubleshoot_performance = 1
BEGIN
    SET STATISTICS XML OFF;

    EXECUTE sys.sp_executesql
        @troubleshoot_update,
      N'@current_table nvarchar(100)',
        @current_table;

    EXECUTE sys.sp_executesql
        @troubleshoot_info,
      N'@sql nvarchar(max),
        @current_table nvarchar(100)',
        @sql,
        @current_table;
END; /*End gathering plan ids*/

/*
This gets the runtime stats for the plans we care about.
It is notably the last usage of @where_clause.
*/
SELECT
    @current_table = 'inserting #query_store_runtime_stats',
    @sql = @isolation_level;

IF @troubleshoot_performance = 1
BEGIN
    EXECUTE sys.sp_executesql
        @troubleshoot_insert,
      N'@current_table nvarchar(100)',
        @current_table;

    SET STATISTICS XML ON;
END;

SELECT
    @sql += N'
SELECT
    @database_id,
    MAX(qsrs_with_lasts.runtime_stats_id),
    qsrs_with_lasts.plan_id,
    MAX(qsrs_with_lasts.runtime_stats_interval_id),
    MAX(qsrs_with_lasts.execution_type_desc),
    MIN(qsrs_with_lasts.first_execution_time),
    MAX(qsrs_with_lasts.partitioned_last_execution_time),
    SUM(qsrs_with_lasts.count_executions),
    AVG((qsrs_with_lasts.avg_duration / 1000.)),
    MAX((qsrs_with_lasts.partitioned_last_duration / 1000.)),
    MIN((qsrs_with_lasts.min_duration / 1000.)),
    MAX((qsrs_with_lasts.max_duration / 1000.)),
    AVG((qsrs_with_lasts.avg_cpu_time / 1000.)),
    MAX((qsrs_with_lasts.partitioned_last_cpu_time / 1000.)),
    MIN((qsrs_with_lasts.min_cpu_time / 1000.)),
    MAX((qsrs_with_lasts.max_cpu_time / 1000.)),
    AVG(((qsrs_with_lasts.avg_logical_io_reads * 8.) / 1024.)),
    MAX(((qsrs_with_lasts.partitioned_last_logical_io_reads * 8.) / 1024.)),
    MIN(((qsrs_with_lasts.min_logical_io_reads * 8.) / 1024.)),
    MAX(((qsrs_with_lasts.max_logical_io_reads * 8.) / 1024.)),
    AVG(((qsrs_with_lasts.avg_logical_io_writes * 8.) / 1024.)),
    MAX(((qsrs_with_lasts.partitioned_last_logical_io_writes * 8.) / 1024.)),
    MIN(((qsrs_with_lasts.min_logical_io_writes * 8.) / 1024.)),
    MAX(((qsrs_with_lasts.max_logical_io_writes * 8.) / 1024.)),
    AVG(((qsrs_with_lasts.avg_physical_io_reads * 8.) / 1024.)),
    MAX(((qsrs_with_lasts.partitioned_last_physical_io_reads * 8.) / 1024.)),
    MIN(((qsrs_with_lasts.min_physical_io_reads * 8.) / 1024.)),
    MAX(((qsrs_with_lasts.max_physical_io_reads * 8.) / 1024.)),
    AVG((qsrs_with_lasts.avg_clr_time / 1000.)),
    MAX((qsrs_with_lasts.partitioned_last_clr_time / 1000.)),
    MIN((qsrs_with_lasts.min_clr_time / 1000.)),
    MAX((qsrs_with_lasts.max_clr_time / 1000.)),
    MAX(qsrs_with_lasts.partitioned_last_dop),
    MIN(qsrs_with_lasts.min_dop),
    MAX(qsrs_with_lasts.max_dop),
    AVG(((qsrs_with_lasts.avg_query_max_used_memory * 8.) / 1024.)),
    MAX(((qsrs_with_lasts.partitioned_last_query_max_used_memory * 8.) / 1024.)),
    MIN(((qsrs_with_lasts.min_query_max_used_memory * 8.) / 1024.)),
    MAX(((qsrs_with_lasts.max_query_max_used_memory * 8.) / 1024.)),
    AVG(qsrs_with_lasts.avg_rowcount),
    MAX(qsrs_with_lasts.partitioned_last_rowcount),
    MIN(qsrs_with_lasts.min_rowcount),
    MAX(qsrs_with_lasts.max_rowcount),';

IF @new = 1
BEGIN
    SELECT
        @sql += N'
    AVG(((qsrs_with_lasts.avg_num_physical_io_reads * 8.) / 1024.)),
    MAX(((qsrs_with_lasts.partitioned_last_num_physical_io_reads * 8.) / 1024.)),
    MIN(((qsrs_with_lasts.min_num_physical_io_reads * 8.) / 1024.)),
    MAX(((qsrs_with_lasts.max_num_physical_io_reads * 8.) / 1024.)),
    AVG((qsrs_with_lasts.avg_log_bytes_used / 100000000.)),
    MAX((qsrs_with_lasts.partitioned_last_log_bytes_used / 100000000.)),
    MIN((qsrs_with_lasts.min_log_bytes_used / 100000000.)),
    MAX((qsrs_with_lasts.max_log_bytes_used / 100000000.)),
    AVG(((qsrs_with_lasts.avg_tempdb_space_used * 8) / 1024.)),
    MAX(((qsrs_with_lasts.partitioned_last_tempdb_space_used * 8) / 1024.)),
    MIN(((qsrs_with_lasts.min_tempdb_space_used * 8) / 1024.)),
    MAX(((qsrs_with_lasts.max_tempdb_space_used * 8) / 1024.)),';
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

/*
In regression mode, we do not mind seeing the
same plan_id twice. We need the below to make
the two time periods under consideration
distinct.
*/
IF @regression_mode = 1
BEGIN
   SELECT
       @sql +=  N'
   CASE
       WHEN qsrs_with_lasts.last_execution_time >= @start_date
       AND  qsrs_with_lasts.last_execution_time < @end_date
       THEN ''No''
       ELSE ''Yes''
   END,';
END;
ELSE
BEGIN
   SELECT
       @sql +=  N'
    NULL,';
END;

SELECT
    @sql += N'
    context_settings = NULL
FROM
(
    SELECT
        qsrs.*,
        /*
        We need this here to make sure that PARTITION BY runs before GROUP BY but after CROSS APPLY.
        If it were after GROUP BY, then we would be dealing with already aggregated data.
        If it were inside the CROSS APPLY, then we would be dealing with windows of size one.
        Both are very wrong, so we need this.
        */
        partitioned_last_execution_time =
            LAST_VALUE(qsrs.last_execution_time) OVER
            (
                PARTITION BY
                    qsrs.plan_id,
                    qsrs.execution_type
                ORDER BY
                    qsrs.runtime_stats_interval_id DESC
                ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
            ),
        partitioned_last_duration =
            LAST_VALUE(qsrs.last_duration) OVER
            (
                PARTITION BY
                    qsrs.plan_id,
                    qsrs.execution_type
                ORDER BY
                    qsrs.runtime_stats_interval_id DESC
                ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
            ),
        partitioned_last_cpu_time =
            LAST_VALUE(qsrs.last_cpu_time) OVER
            (
                PARTITION BY
                    qsrs.plan_id,
                    qsrs.execution_type
                ORDER BY
                    qsrs.runtime_stats_interval_id DESC
                ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
            ),
        partitioned_last_logical_io_reads =
            LAST_VALUE(qsrs.last_logical_io_reads) OVER
            (
                PARTITION BY
                    qsrs.plan_id,
                    qsrs.execution_type
                ORDER BY
                    qsrs.runtime_stats_interval_id DESC
                ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
            ),
        partitioned_last_logical_io_writes =
            LAST_VALUE(qsrs.last_logical_io_writes) OVER
            (
                PARTITION BY
                    qsrs.plan_id,
                    qsrs.execution_type
                ORDER BY
                    qsrs.runtime_stats_interval_id DESC
                ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
            ),
        partitioned_last_physical_io_reads =
            LAST_VALUE(qsrs.last_physical_io_reads) OVER
            (
                PARTITION BY
                    qsrs.plan_id,
                    qsrs.execution_type
                ORDER BY
                    qsrs.runtime_stats_interval_id DESC
                ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
            ),
        partitioned_last_clr_time =
            LAST_VALUE(qsrs.last_clr_time) OVER
            (
                PARTITION BY
                    qsrs.plan_id,
                    qsrs.execution_type
                ORDER BY
                    qsrs.runtime_stats_interval_id DESC
                ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
            ),
        partitioned_last_dop =
            LAST_VALUE(qsrs.last_dop) OVER
            (
                PARTITION BY
                    qsrs.plan_id,
                    qsrs.execution_type
                ORDER BY
                    qsrs.runtime_stats_interval_id DESC
                ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
            ),
        partitioned_last_query_max_used_memory =
            LAST_VALUE(qsrs.last_query_max_used_memory) OVER
            (
                PARTITION BY
                    qsrs.plan_id,
                    qsrs.execution_type
                ORDER BY
                    qsrs.runtime_stats_interval_id DESC
                ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
            ),
        partitioned_last_rowcount =
            LAST_VALUE(qsrs.last_rowcount) OVER
            (
                PARTITION BY
                    qsrs.plan_id,
                    qsrs.execution_type
                ORDER BY
                    qsrs.runtime_stats_interval_id DESC
                ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
            ),';

IF @new = 1
BEGIN
    SELECT
        @sql += N'
        partitioned_last_num_physical_io_reads =
            LAST_VALUE(qsrs.last_num_physical_io_reads) OVER
            (
                PARTITION BY
                    qsrs.plan_id,
                    qsrs.execution_type
                ORDER BY
                    qsrs.runtime_stats_interval_id DESC
                ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
            ),
        partitioned_last_log_bytes_used =
            LAST_VALUE(qsrs.last_log_bytes_used) OVER
            (
                PARTITION BY
                    qsrs.plan_id,
                    qsrs.execution_type
                ORDER BY
                    qsrs.runtime_stats_interval_id DESC
                ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
            ),
        partitioned_last_tempdb_space_used =
            LAST_VALUE(qsrs.last_tempdb_space_used) OVER
            (
                PARTITION BY
                    qsrs.plan_id,
                    qsrs.execution_type
                ORDER BY
                    qsrs.runtime_stats_interval_id DESC
                ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
            )';
END;

IF @new = 0
BEGIN
    SELECT
        @sql += N'
        not_used = NULL';
END;

SELECT
    @sql += N'
    FROM #distinct_plans AS dp
    CROSS APPLY
    (
        SELECT TOP (@queries_top)
            qsrs.*';

    SELECT
        @sql += N'
        FROM ' + @database_name_quoted + N'.sys.query_store_runtime_stats AS qsrs';
        IF @regression_mode = 1
        BEGIN
            SELECT
                @sql += N'
        JOIN #regression_changes AS regression
          ON qsrs.plan_id = regression.plan_id
         AND regression.database_id = @database_id';
        END;
        ELSE IF @sort_order = 'plan count by hashes'
        BEGIN
            SELECT
                @sql += N'
        JOIN #plan_ids_with_query_hashes AS hashes
          ON qsrs.plan_id = hashes.plan_id
         AND hashes.database_id = @database_id';
        END;
        ELSE IF @sort_order_is_a_wait = 1
        BEGIN
            /*
            Note that we do not need this join in
            regression mode, even if we are looking
            at a wait. The tables here are only for
            sorting. In regression mode, we sort
            by columns found in #regression_changes.
            */
            SELECT
                @sql += N'
        JOIN #plan_ids_with_total_waits AS waits
          ON qsrs.plan_id = waits.plan_id
         AND waits.database_id = @database_id';
        END;

    SELECT
        @sql += N'
        WHERE qsrs.plan_id = dp.plan_id
        AND   1 = 1
        '
        + CASE
              WHEN @regression_mode = 1
              THEN N' AND ( 1 = 1
          ' +
          @regression_where_clause
          + N' )
    OR
          ( 1 = 1
          ' + @where_clause
          + N' ) '
              ELSE @where_clause
          END
      + N'
    ORDER BY
        ' +
    CASE @regression_mode
    WHEN 1 THEN
        /* As seen when populating #regression_changes. */
        CASE @regression_direction
           WHEN 'regressed' THEN N'regression.change_since_regression_time_period'
           WHEN 'worse' THEN N'regression.change_since_regression_time_period'
           WHEN 'improved' THEN N'regression.change_since_regression_time_period * -1.0'
           WHEN 'better' THEN N'regression.change_since_regression_time_period * -1.0'
           WHEN 'magnitude' THEN N'ABS(regression.change_since_regression_time_period)'
           WHEN 'absolute' THEN N'ABS(regression.change_since_regression_time_period)'
        END
        ELSE
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
             WHEN 'rows' THEN N'qsrs.avg_rowcount'
             WHEN 'plan count by hashes' THEN N'hashes.plan_hash_count_for_query_hash DESC,
                hashes.query_hash'
             ELSE CASE WHEN @sort_order_is_a_wait = 1 THEN N'waits.total_query_wait_time_ms' ELSE N'qsrs.avg_cpu_time' END
        END
    END + N' DESC
    ) AS qsrs
) AS qsrs_with_lasts
GROUP BY
    qsrs_with_lasts.plan_id ' +
/*
In regression mode, we do not mind seeing the
same plan_id twice. We need the below to make
the two time periods under consideration
distinct.
*/
CASE @regression_mode
     WHEN 1
     THEN  N',
   CASE
       WHEN qsrs_with_lasts.last_execution_time >= @start_date AND qsrs_with_lasts.last_execution_time < @end_date
       THEN ''No''
       ELSE ''Yes''
   END'
   ELSE N' '
END
+
N'
OPTION(RECOMPILE, OPTIMIZE FOR (@queries_top = 9223372036854775807));' + @nc10;

IF @debug = 1
BEGIN
    PRINT LEN(@sql);

    IF LEN(@sql) > 4000
    BEGIN
        SELECT
            query =
            (
                SELECT
                    [processing-instruction(_)] =
                        @sql
                FOR XML
                    PATH(''),
                    TYPE
            );
    END;
    ELSE
    BEGIN
        PRINT @sql;
    END;
END;

INSERT
    #query_store_runtime_stats
WITH
    (TABLOCK)
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
    from_regression_baseline,
    context_settings
)
EXECUTE sys.sp_executesql
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
    @work_end_utc,
    @regression_baseline_start_date,
    @regression_baseline_end_date;

IF @troubleshoot_performance = 1
BEGIN
    SET STATISTICS XML OFF;

    EXECUTE sys.sp_executesql
        @troubleshoot_update,
      N'@current_table nvarchar(100)',
        @current_table;

    EXECUTE sys.sp_executesql
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
    EXECUTE sys.sp_executesql
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
                FOR XML
                    PATH(''''),
                    TYPE
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
    #query_store_plan
WITH
    (TABLOCK)
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
EXECUTE sys.sp_executesql
    @sql,
  N'@plans_top bigint,
    @database_id int',
    @plans_top,
    @database_id;

IF @troubleshoot_performance = 1
BEGIN
    SET STATISTICS XML OFF;

    EXECUTE sys.sp_executesql
        @troubleshoot_update,
      N'@current_table nvarchar(100)',
        @current_table;

    EXECUTE sys.sp_executesql
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
    EXECUTE sys.sp_executesql
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
    ORDER BY
        qsq.last_execution_time DESC
) AS qsq
WHERE qsp.database_id = @database_id
OPTION(RECOMPILE);' + @nc10;

IF @debug = 1
BEGIN
    PRINT LEN(@sql);
    PRINT @sql;
END;

INSERT
    #query_store_query
WITH
    (TABLOCK)
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
EXECUTE sys.sp_executesql
    @sql,
  N'@database_id int',
    @database_id;

IF @troubleshoot_performance = 1
BEGIN
    SET STATISTICS XML OFF;

    EXECUTE sys.sp_executesql
        @troubleshoot_update,
      N'@current_table nvarchar(100)',
        @current_table;

    EXECUTE sys.sp_executesql
        @troubleshoot_info,
      N'@sql nvarchar(max),
        @current_table nvarchar(100)',
        @sql,
        @current_table;
END; /*End getting query details*/


IF @include_query_hash_totals = 1
BEGIN
    SELECT
        @current_table = 'inserting #query_hash_totals for @include_query_hash_totals',
        @sql = @isolation_level;

    IF @troubleshoot_performance = 1
    BEGIN
        EXECUTE sys.sp_executesql
            @troubleshoot_insert,
          N'@current_table nvarchar(100)',
            @current_table;

        SET STATISTICS XML ON;
    END;

    SELECT
        @sql += N'
    SELECT
        @database_id,
        qsq.query_hash,
        SUM(qsrs.count_executions),
        SUM(qsrs.count_executions * qsrs.avg_duration) / 1000.,
        SUM(qsrs.count_executions * qsrs.avg_cpu_time) / 1000.,
        SUM(qsrs.count_executions * (qsrs.avg_logical_io_reads * 8.)) / 1024.,
        SUM(qsrs.count_executions * (qsrs.avg_physical_io_reads * 8.)) / 1024.,
        SUM(qsrs.count_executions * (qsrs.avg_logical_io_writes * 8.)) / 1024.,
        SUM(qsrs.count_executions * qsrs.avg_clr_time) / 1000.,
        SUM(qsrs.count_executions * (qsrs.avg_query_max_used_memory * 8.)) / 1024.,
        SUM(qsrs.count_executions * qsrs.avg_rowcount)' +
  CASE
      @new
      WHEN 1
      THEN N',
        SUM(qsrs.count_executions * (qsrs.avg_num_physical_io_reads * 8)) / 1024.,
        SUM(qsrs.count_executions * qsrs.avg_log_bytes_used) / 100000000.,
        SUM(qsrs.count_executions * (qsrs.avg_tempdb_space_used * 8)) / 1024.'
      ELSE N'
        NULL,
        NULL,
        NULL'
  END +
  N'
    FROM ' + @database_name_quoted + N'.sys.query_store_runtime_stats AS qsrs
    JOIN ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
      ON qsrs.plan_id = qsp.plan_id
    JOIN ' + @database_name_quoted + N'.sys.query_store_query AS qsq
      ON qsp.query_id = qsq.query_id
    WHERE EXISTS
    (
        SELECT
            1/0
        FROM #query_store_query AS qsq2
        WHERE qsq2.query_hash = qsq.query_hash
    )
    GROUP BY
        qsq.query_hash
    OPTION(RECOMPILE);
';

    IF @debug = 1
    BEGIN
        PRINT LEN(@sql);
        PRINT @sql;
    END;

    INSERT INTO
        #query_hash_totals
    WITH
        (TABLOCK)
    (
        database_id,
        query_hash,
        total_executions,
        total_duration_ms,
        total_cpu_time_ms,
        total_logical_reads_mb,
        total_physical_reads_mb,
        total_logical_writes_mb,
        total_clr_time_ms,
        total_memory_mb,
        total_rowcount,
        total_num_physical_io_reads,
        total_log_bytes_used_mb,
        total_tempdb_space_used_mb
    )
    EXECUTE sys.sp_executesql
        @sql,
      N'@database_id int',
        @database_id;

    IF @troubleshoot_performance = 1
    BEGIN
        SET STATISTICS XML OFF;

        EXECUTE sys.sp_executesql
            @troubleshoot_update,
          N'@current_table nvarchar(100)',
            @current_table;

        EXECUTE sys.sp_executesql
            @troubleshoot_info,
          N'@sql nvarchar(max),
            @current_table nvarchar(100)',
            @sql,
            @current_table;
    END;
END;


/*
This gets the query text for them!
*/
SELECT
    @current_table = 'inserting #query_store_query_text',
    @sql = @isolation_level;

IF @troubleshoot_performance = 1
BEGIN
    EXECUTE sys.sp_executesql
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
    #query_store_query_text
WITH
    (TABLOCK)
(
    database_id,
    query_text_id,
    query_sql_text,
    statement_sql_handle,
    is_part_of_encrypted_module,
    has_restricted_text
)
EXECUTE sys.sp_executesql
    @sql,
  N'@database_id int',
    @database_id;

IF @troubleshoot_performance = 1
BEGIN
    SET STATISTICS XML OFF;

    EXECUTE sys.sp_executesql
        @troubleshoot_update,
      N'@current_table nvarchar(100)',
        @current_table;

    EXECUTE sys.sp_executesql
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
    EXECUTE sys.sp_executesql
        @troubleshoot_insert,
      N'@current_table nvarchar(100)',
        @current_table;

    SET STATISTICS XML ON;
END;

INSERT
    #dm_exec_query_stats
WITH
    (TABLOCK)
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
    deqs_with_lasts.statement_sql_handle,
    MAX(deqs_with_lasts.total_grant_kb) / 1024.,
    MAX(deqs_with_lasts.partitioned_last_grant_kb) / 1024.,
    MAX(deqs_with_lasts.min_grant_kb) / 1024.,
    MAX(deqs_with_lasts.max_grant_kb) / 1024.,
    MAX(deqs_with_lasts.total_used_grant_kb) / 1024.,
    MAX(deqs_with_lasts.partitioned_last_used_grant_kb) / 1024.,
    MAX(deqs_with_lasts.min_used_grant_kb) / 1024.,
    MAX(deqs_with_lasts.max_used_grant_kb) / 1024.,
    MAX(deqs_with_lasts.total_ideal_grant_kb) / 1024.,
    MAX(deqs_with_lasts.partitioned_last_ideal_grant_kb) / 1024.,
    MAX(deqs_with_lasts.min_ideal_grant_kb) / 1024.,
    MAX(deqs_with_lasts.max_ideal_grant_kb) / 1024.,
    MAX(deqs_with_lasts.total_reserved_threads),
    MAX(deqs_with_lasts.partitioned_last_reserved_threads),
    MAX(deqs_with_lasts.min_reserved_threads),
    MAX(deqs_with_lasts.max_reserved_threads),
    MAX(deqs_with_lasts.total_used_threads),
    MAX(deqs_with_lasts.partitioned_last_used_threads),
    MAX(deqs_with_lasts.min_used_threads),
    MAX(deqs_with_lasts.max_used_threads)
FROM
(
    SELECT
        deqs.statement_sql_handle,
        deqs.total_grant_kb,
        deqs.min_grant_kb,
        deqs.max_grant_kb,
        deqs.total_used_grant_kb,
        deqs.min_used_grant_kb,
        deqs.max_used_grant_kb,
        deqs.total_ideal_grant_kb,
        deqs.min_ideal_grant_kb,
        deqs.max_ideal_grant_kb,
        deqs.total_reserved_threads,
        deqs.min_reserved_threads,
        deqs.max_reserved_threads,
        deqs.total_used_threads,
        deqs.min_used_threads,
        deqs.max_used_threads,
        partitioned_last_grant_kb =
            LAST_VALUE(deqs.last_grant_kb) OVER
            (
                PARTITION BY
                    deqs.sql_handle
                ORDER BY
                    deqs.last_execution_time DESC
                ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
            ),
        partitioned_last_used_grant_kb =
            LAST_VALUE(deqs.last_used_grant_kb) OVER
            (
                PARTITION BY
                    deqs.sql_handle
                ORDER BY
                    deqs.last_execution_time DESC
                ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
            ),
        partitioned_last_ideal_grant_kb =
            LAST_VALUE(deqs.last_ideal_grant_kb) OVER
            (
                PARTITION BY
                    deqs.sql_handle
                ORDER BY
                    deqs.last_execution_time DESC
                ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
            ),
       partitioned_last_reserved_threads =
           LAST_VALUE(deqs.last_reserved_threads) OVER
           (
               PARTITION BY
                   deqs.sql_handle
               ORDER BY
                   deqs.last_execution_time DESC
               ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
           ),
       partitioned_last_used_threads =
           LAST_VALUE(deqs.last_used_threads) OVER
           (
               PARTITION BY
                   deqs.sql_handle
               ORDER BY
                   deqs.last_execution_time DESC
               ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
           )
    FROM sys.dm_exec_query_stats AS deqs
    WHERE EXISTS
          (
              SELECT
                  1/0
              FROM #query_store_query_text AS qsqt
              WHERE qsqt.statement_sql_handle = deqs.statement_sql_handle
          )
) AS deqs_with_lasts
GROUP BY
    deqs_with_lasts.statement_sql_handle
OPTION(RECOMPILE);

SELECT
    @rc = ROWCOUNT_BIG();

IF @troubleshoot_performance = 1
BEGIN
    SET STATISTICS XML OFF;

    EXECUTE sys.sp_executesql
        @troubleshoot_update,
      N'@current_table nvarchar(100)',
        @current_table;

    EXECUTE sys.sp_executesql
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
        EXECUTE sys.sp_executesql
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

        EXECUTE sys.sp_executesql
            @troubleshoot_update,
          N'@current_table nvarchar(100)',
            @current_table;

        EXECUTE sys.sp_executesql
            @troubleshoot_info,
          N'@sql nvarchar(max),
            @current_table nvarchar(100)',
            @sql,
            @current_table;
    END;
END; /*End updating runtime stats*/

/*
Check on settings, etc.
We do this first so we can see if wait stats capture mode is true more easily.
We do not truncate this table as part of the looping over databases.
Not truncating it makes it easier to show all set options when hitting multiple databases in expert mode.
*/
SELECT
    @current_table = 'inserting #database_query_store_options',
    @sql = @isolation_level;

IF @troubleshoot_performance = 1
BEGIN
    EXECUTE sys.sp_executesql
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
        WHEN
        (
              @product_version = 13
          AND @azure = 0
        )
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
    #database_query_store_options
WITH
    (TABLOCK)
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
EXECUTE sys.sp_executesql
    @sql,
  N'@database_id int',
    @database_id;

IF @troubleshoot_performance = 1
BEGIN
    SET STATISTICS XML OFF;

    EXECUTE sys.sp_executesql
        @troubleshoot_update,
      N'@current_table nvarchar(100)',
        @current_table;

    EXECUTE sys.sp_executesql
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
    /*
    Recall that we do not care about the edge case of a database holding
    wait stats despite capturing wait stats being turned off.
    */
    AND @database_id IN
        (
            SELECT
                dqso.database_id
            FROM #database_query_store_options AS dqso
            WHERE dqso.wait_stats_capture_mode_desc = N'ON'
            AND   dqso.database_id = @database_id
        )
)
BEGIN
    SELECT
        @current_table = 'inserting #query_store_wait_stats',
        @sql = @isolation_level;

    IF @troubleshoot_performance = 1
    BEGIN
        EXECUTE sys.sp_executesql
            @troubleshoot_insert,
          N'@current_table nvarchar(100)',
            @current_table;

        SET STATISTICS XML ON;
    END;

    SELECT
        @sql += N'
SELECT
    @database_id,
    qsws_with_lasts.plan_id,
    qsws_with_lasts.wait_category_desc,
    total_query_wait_time_ms =
        SUM(qsws_with_lasts.total_query_wait_time_ms),
    avg_query_wait_time_ms =
        SUM(qsws_with_lasts.avg_query_wait_time_ms),
    last_query_wait_time_ms =
        MAX(qsws_with_lasts.partitioned_last_query_wait_time_ms),
    min_query_wait_time_ms =
        SUM(qsws_with_lasts.min_query_wait_time_ms),
    max_query_wait_time_ms =
        SUM(qsws_with_lasts.max_query_wait_time_ms)
FROM
(
    SELECT
        qsws.*,
        /*
        We need this here to make sure that PARTITION BY runs before GROUP BY but after CROSS APPLY.
        If it were after GROUP BY, then we would be dealing with already aggregated data.
        If it were inside the CROSS APPLY, then we would be dealing with windows of size one.
        Both are very wrong, so we need this.
        */
        partitioned_last_query_wait_time_ms =
            LAST_VALUE(qsws.last_query_wait_time_ms) OVER
            (
                PARTITION BY
                    qsws.plan_id,
                    qsws.execution_type,
                    qsws.wait_category_desc
                ORDER BY
                    qsws.runtime_stats_interval_id DESC
                ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
            )
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
) AS qsws_with_lasts
GROUP BY
    qsws_with_lasts.plan_id,
    qsws_with_lasts.wait_category_desc
HAVING
    SUM(qsws_with_lasts.min_query_wait_time_ms) > 0.
OPTION(RECOMPILE);' + @nc10;

    IF @debug = 1
    BEGIN
        PRINT LEN(@sql);
        PRINT @sql;
    END;

    INSERT
        #query_store_wait_stats
    WITH
        (TABLOCK)
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
    EXECUTE sys.sp_executesql
        @sql,
      N'@database_id int',
        @database_id;

    IF @troubleshoot_performance = 1
    BEGIN
        SET STATISTICS XML OFF;

        EXECUTE sys.sp_executesql
            @troubleshoot_update,
          N'@current_table nvarchar(100)',
            @current_table;

        EXECUTE sys.sp_executesql
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
    EXECUTE sys.sp_executesql
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
OPTION(RECOMPILE);' + @nc10;

INSERT
    #query_context_settings
WITH
    (TABLOCK)
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
EXECUTE sys.sp_executesql
    @sql,
  N'@database_id int',
    @database_id;

IF @troubleshoot_performance = 1
BEGIN
    SET STATISTICS XML OFF;

    EXECUTE sys.sp_executesql
        @troubleshoot_update,
      N'@current_table nvarchar(100)',
        @current_table;

    EXECUTE sys.sp_executesql
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
                        integer,
                        qcs.set_options
                    ) & 1 = 1
                THEN ', ANSI_PADDING'
                ELSE ''
            END +
            CASE
                WHEN
                    CONVERT
                    (
                        integer,
                        qcs.set_options
                    ) & 8 = 8
                THEN ', CONCAT_NULL_YIELDS_NULL'
                ELSE ''
            END +
            CASE
                WHEN
                    CONVERT
                    (
                        integer,
                        qcs.set_options
                    ) & 16 = 16
                THEN ', ANSI_WARNINGS'
                ELSE ''
            END +
            CASE
                WHEN
                    CONVERT
                    (
                        integer,
                        qcs.set_options
                    ) & 32 = 32
                THEN ', ANSI_NULLS'
                ELSE ''
            END +
            CASE
                WHEN
                    CONVERT
                    (
                        integer,
                        qcs.set_options
                    ) & 64 = 64
                THEN ', QUOTED_IDENTIFIER'
                ELSE ''
            END +
            CASE
                WHEN
                    CONVERT
                    (
                        integer,
                        qcs.set_options
                    ) & 4096 = 4096
                THEN ', ARITH_ABORT'
                ELSE ''
            END +
            CASE
                WHEN
                    CONVERT
                    (
                        integer,
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
        EXECUTE sys.sp_executesql
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
        #query_store_plan_feedback
    WITH
        (TABLOCK)
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
    EXECUTE sys.sp_executesql
        @sql,
      N'@database_id int',
        @database_id;

    IF @troubleshoot_performance = 1
    BEGIN
        SET STATISTICS XML OFF;

        EXECUTE sys.sp_executesql
            @troubleshoot_update,
          N'@current_table nvarchar(100)',
            @current_table;

        EXECUTE sys.sp_executesql
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
        EXECUTE sys.sp_executesql
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
        #query_store_query_variant
    WITH
        (TABLOCK)
    (
        database_id,
        query_variant_query_id,
        parent_query_id,
        dispatcher_plan_id
    )
    EXECUTE sys.sp_executesql
        @sql,
      N'@database_id int',
        @database_id;

    IF @troubleshoot_performance = 1
    BEGIN
        SET STATISTICS XML OFF;

        EXECUTE sys.sp_executesql
            @troubleshoot_update,
          N'@current_table nvarchar(100)',
            @current_table;

        EXECUTE sys.sp_executesql
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
        EXECUTE sys.sp_executesql
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
        #query_store_query_hints
    WITH
        (TABLOCK)
    (
        database_id,
        query_hint_id,
        query_id,
        query_hint_text,
        last_query_hint_failure_reason_desc,
        query_hint_failure_count,
        source_desc
    )
    EXECUTE sys.sp_executesql
        @sql,
      N'@database_id int',
        @database_id;

    IF @troubleshoot_performance = 1
    BEGIN
        SET STATISTICS XML OFF;

        EXECUTE sys.sp_executesql
            @troubleshoot_update,
          N'@current_table nvarchar(100)',
            @current_table;

        EXECUTE sys.sp_executesql
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
            EXECUTE sys.sp_executesql
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
            #query_store_plan_forcing_locations
        WITH
            (TABLOCK)
        (
            database_id,
            plan_forcing_location_id,
            query_id,
            plan_id,
            replica_group_id
        )
        EXECUTE sys.sp_executesql
            @sql,
          N'@database_id int',
            @database_id;

        IF @troubleshoot_performance = 1
        BEGIN
            SET STATISTICS XML OFF;

            EXECUTE sys.sp_executesql
                @troubleshoot_update,
              N'@current_table nvarchar(100)',
                @current_table;

            EXECUTE sys.sp_executesql
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
            EXECUTE sys.sp_executesql
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
            #query_store_replicas
        WITH
            (TABLOCK)
        (
            database_id,
            replica_group_id,
            role_type,
            replica_name
        )
        EXECUTE sys.sp_executesql
            @sql,
          N'@database_id int',
            @database_id;

        IF @troubleshoot_performance = 1
        BEGIN
            SET STATISTICS XML OFF;

            EXECUTE sys.sp_executesql
                @troubleshoot_update,
              N'@current_table nvarchar(100)',
                @current_table;

            EXECUTE sys.sp_executesql
                @troubleshoot_info,
              N'@sql nvarchar(max),
                @current_table nvarchar(100)',
                @sql,
                @current_table;
        END;
    END; /*End AG queries*/
END; /*End SQL 2022 views*/

FETCH NEXT
FROM @database_cursor
INTO @database_name;
END;

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
            nvarchar(max),
        N'
SELECT
    x.*
FROM
(
    SELECT
        source = ''runtime_stats'',
        database_name = DB_NAME(qsrs.database_id),
        qsp.query_id,
        qsrs.plan_id,
        qsp.all_plan_ids,' +
        CASE
            WHEN @include_plan_hashes IS NOT NULL
            OR   @ignore_plan_hashes IS NOT NULL
            OR   @sort_order = 'plan count by hashes'
            THEN N'
        qsp.query_plan_hash,'
            ELSE N''
        END +
        CASE
            WHEN @include_query_hashes IS NOT NULL
            OR   @ignore_query_hashes IS NOT NULL
            OR   @sort_order = 'plan count by hashes'
            OR   @include_query_hash_totals = 1
            THEN N'
        qsq.query_hash,'
            ELSE N''
        END +
        CASE
            WHEN @include_sql_handles IS NOT NULL
            OR   @ignore_sql_handles IS NOT NULL
            THEN N'
        qsqt.statement_sql_handle,'
            ELSE N''
        END + N'
        qsrs.execution_type_desc,
        qsq.object_name,
        qsqt.query_sql_text,
        query_plan =
             CASE
                 WHEN TRY_CAST(qsp.query_plan AS xml) IS NOT NULL
                 THEN TRY_CAST(qsp.query_plan AS xml)
                 WHEN TRY_CAST(qsp.query_plan AS xml) IS NULL
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
                         FOR XML
                             PATH(N''''),
                             TYPE
                     )
             END,
        qsp.compatibility_level,
'
        );

    /* Build column list according to mode (expert vs. non-expert) and format_output */
    SELECT
        @column_sql =
        (
            SELECT
                CASE
                    /* Non-formatted columns */
                    WHEN @format_output = 0
                    THEN
                            N'
                        ' +
                        cd.column_name +
                        N' = ' +
                        cd.column_source +
                        N','
                        /* Formatted columns with FORMAT function */
                        ELSE
                            N'
                        ' +
                        cd.column_name +
                        N' = ' +
                        CASE
                            WHEN cd.format_pattern IS NOT NULL
                            THEN N'FORMAT(' +
                                 cd.column_source +
                                 N', ''' +
                                 cd.format_pattern +
                                 N''')'
                            ELSE cd.column_source
                        END +
                        N','
                END
            FROM @ColumnDefinitions AS cd
            WHERE (@expert_mode = 1 OR cd.expert_only = 0) /* Only include expert columns in expert mode */
            AND
            (
                cd.is_conditional = 0  /* Either non-conditional columns */
                OR /* Or conditional columns where the condition is met */
                (
                   cd.is_conditional = 1
                   AND cd.condition_param IS NOT NULL
                   AND CASE
                           WHEN cd.condition_param = N'sql_2022_views'
                           THEN @sql_2022_views
                           WHEN cd.condition_param = N'new'
                           THEN @new
                           WHEN cd.condition_param = N'regression_mode'
                           THEN @regression_mode
                           WHEN cd.condition_param = N'include_query_hash_totals'
                           THEN @include_query_hash_totals
                           WHEN cd.condition_param = N'new_with_hash_totals'
                           THEN CASE
                                    WHEN @new = 1
                                    AND  @include_query_hash_totals = 1
                                    THEN 1
                                    ELSE 0
                                END
                           ELSE 0
                       END = cd.condition_value
                )
            )
            ORDER BY
                cd.column_id
            FOR
                XML
                PATH(''),
                TYPE
        ).value('.', 'nvarchar(max)');

    /* Remove the trailing comma */
    IF LEN(@column_sql) > 0
    BEGIN
        SET @column_sql =
            LEFT
            (
                @column_sql,
                LEN(@column_sql) - 1
            );
    END;

    /* Append the column SQL to the main SQL */
    SELECT
        @sql += @column_sql;

    /*
    Add on the from and stuff
    */
    SELECT
        @sql +=
    CONVERT
    (
        nvarchar(max),
        N'
        FROM #query_store_runtime_stats AS qsrs'
    );

    /*
    Bolt on any sort-helping tables.
    */
    IF @regression_mode = 1
    BEGIN
        SELECT
            @sql += N'
        JOIN #regression_changes AS regression
          ON  qsrs.plan_id = regression.plan_id
          AND qsrs.database_id = regression.database_id';
    END;

    IF @sort_order = 'plan count by hashes'
    BEGIN
        SELECT
            @sql += N'
        JOIN #plan_ids_with_query_hashes AS hashes
          ON  qsrs.plan_id = hashes.plan_id
          AND qsrs.database_id = hashes.database_id';
    END;

    IF @sort_order_is_a_wait = 1
    BEGIN
        SELECT
            @sql += N'
        JOIN #plan_ids_with_total_waits AS waits
          ON  qsrs.plan_id = waits.plan_id
          AND qsrs.database_id = waits.database_id';

        IF @regression_mode = 1
        BEGIN
            SELECT
                @sql += N'
        AND qsrs.from_regression_baseline = waits.from_regression_baseline';
        END;
    END;

/*Get more stuff, like query plans and query text*/
SELECT
    @sql +=
    CONVERT
    (
        nvarchar(max),
        N'
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
          ON  qsqt.query_text_id = qsq.query_text_id
          AND qsqt.database_id = qsq.database_id
        WHERE qsq.query_id = qsp.query_id
        AND   qsq.database_id = qsp.database_id
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
        ORDER BY
            qsq.last_execution_time DESC
    ) AS qsq'
    );

    /*
    Get wait stats if we can
    */
    IF
    (
        @new = 1
    )
    BEGIN
        SELECT
            @sql +=
        CONVERT
        (
            nvarchar(max),
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
                            '' ('' + ' +
                            CASE
                                @format_output
                                WHEN 0
                                THEN N'
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
                            ) + '
                                 ELSE N'
                            FORMAT
                            (
                                SUM
                                (
                                    CONVERT
                                    (
                                        bigint,
                                        qsws.avg_query_wait_time_ms
                                    )
                                ),
                                ''N0''
                            ) + '
                            END + N' '' ms)''
                       FROM #query_store_wait_stats AS qsws
                       WHERE qsws.plan_id = qsrs.plan_id
                       AND   qsws.database_id = qsrs.database_id
                       GROUP BY
                           qsws.wait_category_desc
                       ORDER BY
                           SUM(qsws.avg_query_wait_time_ms) DESC
                       FOR XML
                           PATH(''''),
                           TYPE
                    ).value(''./text()[1]'', ''varchar(max)''),
                    1,
                    2,
                    ''''
                )
    ) AS w'
    );
    END; /*End wait stats query*/

    /*Strap on the query hash totals table*/
    IF @include_query_hash_totals = 1
    BEGIN
        SELECT
            @sql += N'
    JOIN #query_hash_totals AS qht
      ON  qsq.query_hash = qht.query_hash
      AND qsq.database_id = qht.database_id';
    END;

    SELECT
        @sql +=
    CONVERT
    (
        nvarchar(max),
        N'
) AS x
' + CASE WHEN @regression_mode = 1 THEN N'' ELSE N'WHERE x.n = 1 ' END
+ N'
ORDER BY
    ' +
    CASE @format_output
         WHEN 0
         THEN
             CASE WHEN @regression_mode = 1
             AND @regression_direction IN ('improved', 'better')
             THEN 'x.change_in_average_for_query_hash_since_regression_time_period ASC,
                   x.query_hash_from_regression_checking,
                   x.from_regression_baseline_time_period'
             WHEN @regression_mode = 1
             AND @regression_direction IN ('regressed', 'worse')
             THEN 'x.change_in_average_for_query_hash_since_regression_time_period DESC,
                   x.query_hash_from_regression_checking,
                   x.from_regression_baseline_time_period'
             WHEN @regression_mode = 1
             AND @regression_direction IN ('magnitude', 'absolute')
             THEN 'ABS(x.change_in_average_for_query_hash_since_regression_time_period) DESC,
                   x.query_hash_from_regression_checking,
                   x.from_regression_baseline_time_period'
             ELSE
             CASE @sort_order
                  WHEN 'cpu' THEN N'x.avg_cpu_time_ms'
                  WHEN 'logical reads' THEN N'x.avg_logical_io_reads_mb'
                  WHEN 'physical reads' THEN N'x.avg_physical_io_reads_mb'
                  WHEN 'writes' THEN N'x.avg_logical_io_writes_mb'
                  WHEN 'duration' THEN N'x.avg_duration_ms'
                  WHEN 'memory' THEN N'x.avg_query_max_used_memory_mb'
                  WHEN 'tempdb' THEN CASE WHEN @new = 1 THEN N'x.avg_tempdb_space_used_mb' ELSE N'x.avg_cpu_time_ms' END
                  WHEN 'executions' THEN N'x.count_executions'
                  WHEN 'recent' THEN N'x.last_execution_time'
                  WHEN 'rows' THEN N'x.avg_rowcount'
                  WHEN 'plan count by hashes' THEN N'x.plan_hash_count_for_query_hash DESC,
    x.query_hash_from_hash_counting'
                  ELSE CASE WHEN @sort_order_is_a_wait = 1 THEN N'x.total_wait_time_from_sort_order_ms' ELSE N'x.avg_cpu_time_ms' END
             END END
         /*
         The ORDER BY is on the same level as the topmost SELECT, which is just SELECT x.*.
         This means that to sort formatted output, we have to un-format it.
         */
         WHEN 1
         THEN
             CASE WHEN @regression_mode = 1
                  AND @regression_direction IN ('improved', 'better')
                  THEN 'TRY_PARSE(replace(x.change_in_average_for_query_hash_since_regression_time_period, ''%'', '''') AS money) ASC,
                        x.query_hash_from_regression_checking,
                        x.from_regression_baseline_time_period'
                  WHEN @regression_mode = 1
                  AND @regression_direction IN ('regressed', 'worse')
                  THEN 'TRY_PARSE(replace(x.change_in_average_for_query_hash_since_regression_time_period, ''%'', '''') AS money) DESC,
                        x.query_hash_from_regression_checking,
                        x.from_regression_baseline_time_period'
                  WHEN @regression_mode = 1
                  AND @regression_direction IN ('magnitude', 'absolute')
                  THEN 'ABS(TRY_PARSE(replace(x.change_in_average_for_query_hash_since_regression_time_period, ''%'', '''') AS money)) DESC,
                        x.query_hash_from_regression_checking,
                        x.from_regression_baseline_time_period'
             ELSE
             CASE @sort_order
                  WHEN 'cpu' THEN N'TRY_PARSE(x.avg_cpu_time_ms AS money)'
                  WHEN 'logical reads' THEN N'TRY_PARSE(x.avg_logical_io_reads_mb AS money)'
                  WHEN 'physical reads' THEN N'TRY_PARSE(x.avg_physical_io_reads_mb AS money)'
                  WHEN 'writes' THEN N'TRY_PARSE(x.avg_logical_io_writes_mb AS money)'
                  WHEN 'duration' THEN N'TRY_PARSE(x.avg_duration_ms AS money)'
                  WHEN 'memory' THEN N'TRY_PARSE(x.avg_query_max_used_memory_mb AS money)'
                  WHEN 'tempdb' THEN CASE WHEN @new = 1 THEN N'TRY_PARSE(x.avg_tempdb_space_used_mb AS money)' ELSE N'TRY_PARSE(x.avg_cpu_time_ms AS money)' END
                  WHEN 'executions' THEN N'TRY_PARSE(x.count_executions AS money)'
                  WHEN 'recent' THEN N'x.last_execution_time'
                  WHEN 'rows' THEN N'TRY_PARSE(x.avg_rowcount AS money)'
                  WHEN 'plan count by hashes' THEN N'TRY_PARSE(x.plan_hash_count_for_query_hash AS money) DESC,
    x.query_hash_from_hash_counting'
                  ELSE CASE WHEN @sort_order_is_a_wait = 1 THEN N'TRY_PARSE(x.total_wait_time_from_sort_order_ms AS money)' ELSE N'TRY_PARSE(x.avg_cpu_time_ms AS money)' END
             END END
    END
             + N' DESC
OPTION(RECOMPILE);' + @nc10
    );

    IF @debug = 1
    BEGIN
        PRINT LEN(@sql);
        PRINT SUBSTRING(@sql, 0, 4000);
        PRINT SUBSTRING(@sql, 4001, 8000);
        PRINT SUBSTRING(@sql, 8001, 12000);
        PRINT SUBSTRING(@sql, 12001, 16000);
    END;

    EXECUTE sys.sp_executesql
        @sql,
      N'@utc_offset_string nvarchar(6),
        @timezone sysname',
        @utc_offset_string,
        @timezone;
END; /*End runtime stats main query*/
ELSE
BEGIN
    SELECT
        result =
            '#query_store_runtime_stats is empty';
END;

/*
Return special things: plan feedback, query hints, query variants, query text, wait stats, and query store options
This section handles all expert mode and special output formats
Format numeric values based on @format_output
*/
IF
(
    @expert_mode = 1
  OR
  (
       @only_queries_with_hints = 1
    OR @only_queries_with_feedback = 1
    OR @only_queries_with_variants = 1
  )
)
BEGIN
    /*
    SQL 2022+ features: plan feedback, query hints, and query variants
    */
    IF @sql_2022_views = 1
    BEGIN
        /*
        Handle query_store_plan_feedback
        */
        IF @expert_mode = 1
        OR @only_queries_with_feedback = 1
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

                /*
                Use dynamic SQL to handle formatting differences based on @format_output
                */
                SELECT
                    @sql = @isolation_level;

                SELECT
                    @sql += N'
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
                                SWITCHOFFSET
                                (
                                    qspf.create_time,
                                    @utc_offset_string
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
                                SWITCHOFFSET
                                (
                                    qspf.last_updated_time,
                                    @utc_offset_string
                                )
                            WHEN @timezone IS NOT NULL
                            THEN qspf.last_updated_time AT TIME ZONE @timezone
                        END,
                    last_updated_time_utc =
                        qspf.last_updated_time
                FROM #query_store_plan_feedback AS qspf
                ORDER BY
                    qspf.plan_id
                OPTION(RECOMPILE);' + @nc10;

                IF @debug = 1
                BEGIN
                    PRINT LEN(@sql);
                    PRINT @sql;
                END;

                EXECUTE sys.sp_executesql
                    @sql,
                  N'@timezone sysname, @utc_offset_string nvarchar(6)',
                    @timezone, @utc_offset_string;
            END;
            ELSE IF @only_queries_with_feedback = 1
            BEGIN
                SELECT
                    result = '#query_store_plan_feedback is empty';
            END;
        END; /*@only_queries_with_feedback*/

        IF @expert_mode = 1
        OR @only_queries_with_hints = 1
        BEGIN
            IF EXISTS
               (
                   SELECT
                       1/0
                   FROM #query_store_query_hints AS qsqh
               )
            BEGIN
                SELECT
                    @current_table = 'selecting query hints';

                /*
                Use dynamic SQL to handle formatting differences based on @format_output
                */
                SELECT
                    @sql = @isolation_level;

                SELECT
                    @sql += N'
                SELECT
                    database_name =
                        DB_NAME(qsqh.database_id),
                    qsqh.query_hint_id,
                    qsqh.query_id,
                    qsqh.query_hint_text,
                    qsqh.last_query_hint_failure_reason_desc,
                    query_hint_failure_count = ' +
                    CASE
                        WHEN @format_output = 1
                        THEN N'FORMAT(qsqh.query_hint_failure_count, ''N0'')'
                        ELSE N'qsqh.query_hint_failure_count'
                    END + N',
                    qsqh.source_desc
                FROM #query_store_query_hints AS qsqh
                ORDER BY
                    qsqh.query_id
                OPTION(RECOMPILE);' + @nc10;

                IF @debug = 1
                BEGIN
                    PRINT LEN(@sql);
                    PRINT @sql;
                END;

                EXECUTE sys.sp_executesql
                    @sql;
            END;
            ELSE IF @only_queries_with_hints = 1
            BEGIN
                SELECT
                    result = '#query_store_query_hints is empty';
            END;
        END; /*@only_queries_with_hints*/

        IF @expert_mode = 1
        OR @only_queries_with_variants = 1
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

                /*
                Use dynamic SQL to handle formatting differences based on @format_output
                */
                SELECT
                    @sql = @isolation_level;

                SELECT
                    @sql += N'
                SELECT
                    database_name =
                        DB_NAME(qsqv.database_id),
                    qsqv.query_variant_query_id,
                    qsqv.parent_query_id,
                    qsqv.dispatcher_plan_id
                FROM #query_store_query_variant AS qsqv
                ORDER BY
                    qsqv.parent_query_id
                OPTION(RECOMPILE);' + @nc10;

                IF @debug = 1
                BEGIN
                    PRINT LEN(@sql);
                    PRINT @sql;
                END;

                EXECUTE sys.sp_executesql
                    @sql;
            END;
            ELSE IF @only_queries_with_variants = 1
            BEGIN
                SELECT
                    result = '#query_store_query_variant is empty';
            END;
        END; /*@only_queries_with_variants*/

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
                        qsr.replica_group_id
                    OPTION(RECOMPILE);
                END;
                ELSE
                BEGIN
                    SELECT
                        result = 'Availability Group information is empty';
                END;
            END;
        END; /*@ags_present*/
    END; /*End 2022 views*/

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

            /*
            Use dynamic SQL to handle formatting differences based on @format_output
            */
            SELECT
                @sql = @isolation_level;

            SELECT
                @sql += N'
            SELECT
                x.*
            FROM
            (
                SELECT
                    source =
                        ''compilation_stats'',
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
                                SWITCHOFFSET
                                (
                                    qsq.initial_compile_start_time,
                                    @utc_offset_string
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
                                SWITCHOFFSET
                                (
                                    qsq.last_compile_start_time,
                                    @utc_offset_string
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
                                SWITCHOFFSET
                                (
                                    qsq.last_execution_time,
                                    @utc_offset_string
                                )
                            WHEN @timezone IS NOT NULL
                            THEN qsq.last_execution_time AT TIME ZONE @timezone
                        END,
                    last_execution_time_utc =
                        qsq.last_execution_time,
                    count_compiles = ' +
                    CONVERT
                    (
                        nvarchar(max),
                        CASE
                            WHEN @format_output = 1
                            THEN N'FORMAT(qsq.count_compiles, ''N0'')'
                            ELSE N'qsq.count_compiles'
                        END + N',
                    avg_compile_duration_ms = ' +
                        CASE
                            WHEN @format_output = 1
                            THEN N'FORMAT(qsq.avg_compile_duration_ms, ''N0'')'
                            ELSE N'qsq.avg_compile_duration_ms'
                        END + N',
                    total_compile_duration_ms = ' +
                        CASE
                            WHEN @format_output = 1
                            THEN N'FORMAT(qsq.total_compile_duration_ms, ''N0'')'
                            ELSE N'qsq.total_compile_duration_ms'
                        END + N',
                    last_compile_duration_ms = ' +
                        CASE
                            WHEN @format_output = 1
                            THEN N'FORMAT(qsq.last_compile_duration_ms, ''N0'')'
                            ELSE N'qsq.last_compile_duration_ms'
                        END + N',
                    avg_bind_duration_ms = ' +
                        CASE
                            WHEN @format_output = 1
                            THEN N'FORMAT(qsq.avg_bind_duration_ms, ''N0'')'
                            ELSE N'qsq.avg_bind_duration_ms'
                        END + N',
                    total_bind_duration_ms = ' +
                        CASE
                            WHEN @format_output = 1
                            THEN N'FORMAT(qsq.total_bind_duration_ms, ''N0'')'
                            ELSE N'qsq.total_bind_duration_ms'
                        END + N',
                    last_bind_duration_ms = ' +
                        CASE
                            WHEN @format_output = 1
                            THEN N'FORMAT(qsq.last_bind_duration_ms, ''N0'')'
                            ELSE N'qsq.last_bind_duration_ms'
                        END + N',
                    avg_bind_cpu_time_ms = ' +
                        CASE
                            WHEN @format_output = 1
                            THEN N'FORMAT(qsq.avg_bind_cpu_time_ms, ''N0'')'
                            ELSE N'qsq.avg_bind_cpu_time_ms'
                        END + N',
                    total_bind_cpu_time_ms = ' +
                        CASE
                            WHEN @format_output = 1
                            THEN N'FORMAT(qsq.total_bind_cpu_time_ms, ''N0'')'
                            ELSE N'qsq.total_bind_cpu_time_ms'
                        END + N',
                    last_bind_cpu_time_ms = ' +
                        CASE
                            WHEN @format_output = 1
                            THEN N'FORMAT(qsq.last_bind_cpu_time_ms, ''N0'')'
                            ELSE N'qsq.last_bind_cpu_time_ms'
                        END + N',
                    avg_optimize_duration_ms = ' +
                        CASE
                            WHEN @format_output = 1
                            THEN N'FORMAT(qsq.avg_optimize_duration_ms, ''N0'')'
                            ELSE N'qsq.avg_optimize_duration_ms'
                        END + N',
                    total_optimize_duration_ms = ' +
                        CASE
                            WHEN @format_output = 1
                            THEN N'FORMAT(qsq.total_optimize_duration_ms, ''N0'')'
                            ELSE N'qsq.total_optimize_duration_ms'
                        END + N',
                    last_optimize_duration_ms = ' +
                        CASE
                            WHEN @format_output = 1
                            THEN N'FORMAT(qsq.last_optimize_duration_ms, ''N0'')'
                            ELSE N'qsq.last_optimize_duration_ms'
                        END + N',
                    avg_optimize_cpu_time_ms = ' +
                        CASE
                            WHEN @format_output = 1
                            THEN N'FORMAT(qsq.avg_optimize_cpu_time_ms, ''N0'')'
                            ELSE N'qsq.avg_optimize_cpu_time_ms'
                        END + N',
                    total_optimize_cpu_time_ms = ' +
                        CASE
                            WHEN @format_output = 1
                            THEN N'FORMAT(qsq.total_optimize_cpu_time_ms, ''N0'')'
                            ELSE N'qsq.total_optimize_cpu_time_ms'
                        END + N',
                    last_optimize_cpu_time_ms = ' +
                        CASE
                            WHEN @format_output = 1
                            THEN N'FORMAT(qsq.last_optimize_cpu_time_ms, ''N0'')'
                            ELSE N'qsq.last_optimize_cpu_time_ms'
                        END + N',
                    avg_compile_memory_mb = ' +
                        CASE
                            WHEN @format_output = 1
                            THEN N'FORMAT(qsq.avg_compile_memory_mb, ''N0'')'
                            ELSE N'qsq.avg_compile_memory_mb'
                        END + N',
                    total_compile_memory_mb = ' +
                        CASE
                            WHEN @format_output = 1
                            THEN N'FORMAT(qsq.total_compile_memory_mb, ''N0'')'
                            ELSE N'qsq.total_compile_memory_mb'
                        END + N',
                    last_compile_memory_mb = ' +
                        CASE
                            WHEN @format_output = 1
                            THEN N'FORMAT(qsq.last_compile_memory_mb, ''N0'')'
                            ELSE N'qsq.last_compile_memory_mb'
                        END + N',
                    max_compile_memory_mb = ' +
                        CASE
                            WHEN @format_output = 1
                            THEN N'FORMAT(qsq.max_compile_memory_mb, ''N0'')'
                            ELSE N'qsq.max_compile_memory_mb'
                        END
                   ) + N',
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
            OPTION(RECOMPILE);' + @nc10;

            IF @debug = 1
            BEGIN
                PRINT LEN(@sql);
                PRINT @sql;
            END;

            EXECUTE sys.sp_executesql
                @sql,
              N'@timezone sysname, @utc_offset_string nvarchar(6)',
                @timezone, @utc_offset_string;

        END; /*End compilation query section*/
        ELSE
        BEGIN
            SELECT
                result =
                    '#query_store_query is empty';
        END;
    END; /*compilation stats*/

    IF @rc > 0
    BEGIN
        SELECT
            @current_table = 'selecting resource stats';

        SET @sql = N'';

        SELECT
            @sql =
        CONVERT
        (
            nvarchar(max),
            N'
        SELECT
            source =
                ''resource_stats'',
            database_name =
                DB_NAME(qsq.database_id),
            qsq.query_id,
            qsq.object_name,
            total_grant_mb = '
            +
            CONVERT
            (
                nvarchar(max),
            CASE
                WHEN @format_output = 1
                THEN N'FORMAT(qsqt.total_grant_mb, ''N0'')'
                ELSE N'qsqt.total_grant_mb'
            END
            + N',
            last_grant_mb = '
            +
            CASE
                WHEN @format_output = 1
                THEN N'FORMAT(qsqt.last_grant_mb, ''N0'')'
                ELSE N'qsqt.last_grant_mb'
            END
            + N',
            min_grant_mb = '
            +
            CASE
                WHEN @format_output = 1
                THEN N'FORMAT(qsqt.min_grant_mb, ''N0'')'
                ELSE N'qsqt.min_grant_mb'
            END
            + N',
            max_grant_mb = '
            +
            CASE
                WHEN @format_output = 1
                THEN N'FORMAT(qsqt.max_grant_mb, ''N0'')'
                ELSE N'qsqt.max_grant_mb'
            END
            + N',
            total_used_grant_mb = '
            +
            CASE
                WHEN @format_output = 1
                THEN N'FORMAT(qsqt.total_used_grant_mb, ''N0'')'
                ELSE N'qsqt.total_used_grant_mb'
            END
            + N',
            last_used_grant_mb = '
            +
            CASE
                WHEN @format_output = 1
                THEN N'FORMAT(qsqt.last_used_grant_mb, ''N0'')'
                ELSE N'qsqt.last_used_grant_mb'
            END
            + N',
            min_used_grant_mb = '
            +
            CASE
                WHEN @format_output = 1
                THEN N'FORMAT(qsqt.min_used_grant_mb, ''N0'')'
                ELSE N'qsqt.min_used_grant_mb'
            END
            + N',
            max_used_grant_mb = '
            +
            CASE
                WHEN @format_output = 1
                THEN N'FORMAT(qsqt.max_used_grant_mb, ''N0'')'
                ELSE N'qsqt.max_used_grant_mb'
            END
            + N',
            total_ideal_grant_mb = '
            +
            CASE
                WHEN @format_output = 1
                THEN N'FORMAT(qsqt.total_ideal_grant_mb, ''N0'')'
                ELSE N'qsqt.total_ideal_grant_mb'
            END
            + N',
            last_ideal_grant_mb = '
            +
            CASE
                WHEN @format_output = 1
                THEN N'FORMAT(qsqt.last_ideal_grant_mb, ''N0'')'
                ELSE N'qsqt.last_ideal_grant_mb'
            END
            + N',
            min_ideal_grant_mb = '
            +
            CASE
                WHEN @format_output = 1
                THEN N'FORMAT(qsqt.min_ideal_grant_mb, ''N0'')'
                ELSE N'qsqt.min_ideal_grant_mb'
            END
            + N',
            max_ideal_grant_mb = '
            +
            CASE
                WHEN @format_output = 1
                THEN N'FORMAT(qsqt.max_ideal_grant_mb, ''N0'')'
                ELSE N'qsqt.max_ideal_grant_mb'
            END
            + N',
            total_reserved_threads = '
            +
            CASE
                WHEN @format_output = 1
                THEN N'FORMAT(qsqt.total_reserved_threads, ''N0'')'
                ELSE N'qsqt.total_reserved_threads'
            END
            + N',
            last_reserved_threads = '
            +
            CASE
                WHEN @format_output = 1
                THEN N'FORMAT(qsqt.last_reserved_threads, ''N0'')'
                ELSE N'qsqt.last_reserved_threads'
            END
            + N',
            min_reserved_threads = '
            +
            CASE
                WHEN @format_output = 1
                THEN N'FORMAT(qsqt.min_reserved_threads, ''N0'')'
                ELSE N'qsqt.min_reserved_threads'
            END
            + N',
            max_reserved_threads = '
            +
            CASE
                WHEN @format_output = 1
                THEN N'FORMAT(qsqt.max_reserved_threads, ''N0'')'
                ELSE N'qsqt.max_reserved_threads'
            END
            + N',
            total_used_threads = '
            +
            CASE
                WHEN @format_output = 1
                THEN N'FORMAT(qsqt.total_used_threads, ''N0'')'
                ELSE N'qsqt.total_used_threads'
            END
            + N',
            last_used_threads = '
            +
            CASE
                WHEN @format_output = 1
                THEN N'FORMAT(qsqt.last_used_threads, ''N0'')'
                ELSE N'qsqt.last_used_threads'
            END
            + N',
            min_used_threads = '
            +
            CASE
                WHEN @format_output = 1
                THEN N'FORMAT(qsqt.min_used_threads, ''N0'')'
                ELSE N'qsqt.min_used_threads'
            END
            + N',
            max_used_threads = '
            +
            CASE
                WHEN @format_output = 1
                THEN N'FORMAT(qsqt.max_used_threads, ''N0'')'
                ELSE N'qsqt.max_used_threads'
            END
            ) + N'
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
        OPTION(RECOMPILE);' + @nc10
        );

        IF @debug = 1
        BEGIN
            PRINT LEN(@sql);
            PRINT @sql;
        END;

        EXECUTE sys.sp_executesql
            @sql;

    END; /*End resource stats query*/
    ELSE
    BEGIN
        SELECT
            result =
                '#dm_exec_query_stats is empty';
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
                /*
                Wait stats by query
                */
                SELECT
                    @current_table = 'selecting wait stats by query';

                SET @sql = N'';

                SELECT
                    @sql =
                CONVERT
                (
                    nvarchar(max),
                    N'
                SELECT
                    source =
                        ''query_store_wait_stats_by_query'',
                    database_name =
                        DB_NAME(qsws.database_id),
                    qsws.plan_id,
                    x.object_name,
                    qsws.wait_category_desc,
                    total_query_wait_time_ms = '
                    +
                    CONVERT
                    (
                        nvarchar(max),
                    CASE
                        WHEN @format_output = 1
                        THEN N'FORMAT(qsws.total_query_wait_time_ms, ''N0'')'
                        ELSE N'qsws.total_query_wait_time_ms'
                    END
                    + N',
                    total_query_duration_ms = '
                    +
                    CASE
                        WHEN @format_output = 1
                        THEN N'FORMAT(x.total_duration_ms, ''N0'')'
                        ELSE N'x.total_duration_ms'
                    END
                    + N',
                    avg_query_wait_time_ms = '
                    +
                    CASE
                        WHEN @format_output = 1
                        THEN N'FORMAT(qsws.avg_query_wait_time_ms, ''N0'')'
                        ELSE N'qsws.avg_query_wait_time_ms'
                    END
                    + N',
                    avg_query_duration_ms = '
                    +
                    CASE
                        WHEN @format_output = 1
                        THEN N'FORMAT(x.avg_duration_ms, ''N0'')'
                        ELSE N'x.avg_duration_ms'
                    END
                    + N',
                    last_query_wait_time_ms = '
                    +
                    CASE
                        WHEN @format_output = 1
                        THEN N'FORMAT(qsws.last_query_wait_time_ms, ''N0'')'
                        ELSE N'qsws.last_query_wait_time_ms'
                    END
                    + N',
                    last_query_duration_ms = '
                    +
                    CASE
                        WHEN @format_output = 1
                        THEN N'FORMAT(x.last_duration_ms, ''N0'')'
                        ELSE N'x.last_duration_ms'
                    END
                    + N',
                    min_query_wait_time_ms = '
                    +
                    CASE
                        WHEN @format_output = 1
                        THEN N'FORMAT(qsws.min_query_wait_time_ms, ''N0'')'
                        ELSE N'qsws.min_query_wait_time_ms'
                    END
                    + N',
                    min_query_duration_ms = '
                    +
                    CASE
                        WHEN @format_output = 1
                        THEN N'FORMAT(x.min_duration_ms, ''N0'')'
                        ELSE N'x.min_duration_ms'
                    END
                    + N',
                    max_query_wait_time_ms = '
                    +
                    CASE
                        WHEN @format_output = 1
                        THEN N'FORMAT(qsws.max_query_wait_time_ms, ''N0'')'
                        ELSE N'qsws.max_query_wait_time_ms'
                    END
                    + N',
                    max_query_duration_ms = '
                    +
                    CASE
                        WHEN @format_output = 1
                        THEN N'FORMAT(x.max_duration_ms, ''N0'')'
                        ELSE N'x.max_duration_ms'
                    END
                    ) + N'
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
                OPTION(RECOMPILE);' + @nc10
                );

                IF @debug = 1
                BEGIN
                    PRINT LEN(@sql);
                    PRINT @sql;
                END;

                EXECUTE sys.sp_executesql
                    @sql;

                /*
                Wait stats in total
                */
                SELECT
                    @current_table = 'selecting wait stats in total';

                SET @sql = N'';

                SELECT
                    @sql =
                CONVERT
                (
                    nvarchar(max),
                    N'
                SELECT
                    source =
                        ''query_store_wait_stats_total'',
                    database_name =
                        DB_NAME(qsws.database_id),
                    qsws.wait_category_desc,
                    total_query_wait_time_ms = '
                    +
                    CONVERT
                    (
                        nvarchar(max),
                    CASE
                        WHEN @format_output = 1
                        THEN N'FORMAT(SUM(qsws.total_query_wait_time_ms), ''N0'')'
                        ELSE N'SUM(qsws.total_query_wait_time_ms)'
                    END
                    + N',
                    total_query_duration_ms = '
                    +
                    CASE
                        WHEN @format_output = 1
                        THEN N'FORMAT(SUM(x.total_duration_ms), ''N0'')'
                        ELSE N'SUM(x.total_duration_ms)'
                    END
                    + N',
                    avg_query_wait_time_ms = '
                    +
                    CASE
                        WHEN @format_output = 1
                        THEN N'FORMAT(SUM(qsws.avg_query_wait_time_ms), ''N0'')'
                        ELSE N'SUM(qsws.avg_query_wait_time_ms)'
                    END
                    + N',
                    avg_query_duration_ms = '
                    +
                    CASE
                        WHEN @format_output = 1
                        THEN N'FORMAT(SUM(x.avg_duration_ms), ''N0'')'
                        ELSE N'SUM(x.avg_duration_ms)'
                    END
                    + N',
                    last_query_wait_time_ms = '
                    +
                    CASE
                        WHEN @format_output = 1
                        THEN N'FORMAT(SUM(qsws.last_query_wait_time_ms), ''N0'')'
                        ELSE N'SUM(qsws.last_query_wait_time_ms)'
                    END
                    + N',
                    last_query_duration_ms = '
                    +
                    CASE
                        WHEN @format_output = 1
                        THEN N'FORMAT(SUM(x.last_duration_ms), ''N0'')'
                        ELSE N'SUM(x.last_duration_ms)'
                    END
                    + N',
                    min_query_wait_time_ms = '
                    +
                    CASE
                        WHEN @format_output = 1
                        THEN N'FORMAT(SUM(qsws.min_query_wait_time_ms), ''N0'')'
                        ELSE N'SUM(qsws.min_query_wait_time_ms)'
                    END
                    + N',
                    min_query_duration_ms = '
                    +
                    CASE
                        WHEN @format_output = 1
                        THEN N'FORMAT(SUM(x.min_duration_ms), ''N0'')'
                        ELSE N'SUM(x.min_duration_ms)'
                    END
                    + N',
                    max_query_wait_time_ms = '
                    +
                    CASE
                        WHEN @format_output = 1
                        THEN N'FORMAT(SUM(qsws.max_query_wait_time_ms), ''N0'')'
                        ELSE N'SUM(qsws.max_query_wait_time_ms)'
                    END
                    + N',
                    max_query_duration_ms = '
                    +
                    CASE
                        WHEN @format_output = 1
                        THEN N'FORMAT(SUM(x.max_duration_ms), ''N0'')'
                        ELSE N'SUM(x.max_duration_ms)'
                    END
                    ) + N'
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
                OPTION(RECOMPILE);' + @nc10
                );

                IF @debug = 1
                BEGIN
                    PRINT LEN(@sql);
                    PRINT @sql;
                END;

                EXECUTE sys.sp_executesql
                    @sql;
            END;
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
                                     WHERE dqso.wait_stats_capture_mode_desc <> N'ON'
                                 )
                            AND EXISTS
                                (
                                    SELECT
                                        1/0
                                    FROM #database_query_store_options AS dqso
                                    WHERE dqso.wait_stats_capture_mode_desc = N'ON'
                                )
                            THEN ' because we ignore wait stats if you have disabled capturing them in your Query Store options and everywhere that had it enabled had no data'
                            WHEN EXISTS
                                 (
                                     SELECT
                                         1/0
                                     FROM #database_query_store_options AS dqso
                                     WHERE dqso.wait_stats_capture_mode_desc <> N'ON'
                                 )
                            THEN ' because we ignore wait stats if you have disabled capturing them in your Query Store options'
                            ELSE ' for the queries in the results'
                        END;
            END;
        END;
    END; /*End wait stats queries*/

    IF @expert_mode = 1
    BEGIN
        SELECT
            @current_table = 'selecting query store options',
            @sql = N'';

        SELECT
            @sql +=
        CONVERT
        (
            nvarchar(max),
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
            nvarchar(max),
            N'
            dqso.size_based_cleanup_mode_desc
        FROM #database_query_store_options AS dqso
        OPTION(RECOMPILE);' + @nc10
        );

        IF @debug = 1
        BEGIN
            PRINT LEN(@sql);
            PRINT @sql;
        END;

        EXECUTE sys.sp_executesql
            @sql;
    END;
END; /*End Expert Mode*/

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
Return help table, unless told not to
*/
IF
(
    @hide_help_table <> 1
)
BEGIN
    SELECT
        x.all_done,
        x.period,
        x.databases,
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
                    nvarchar(19),
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
                    21
                ) +
                N' through ' +
                CONVERT
                (
                    nvarchar(19),
                    ISNULL
                    (
                        @end_date_original,
                        SYSDATETIME()
                    ),
                    21
                ),
            all_done =
                'brought to you by darling data!',
            databases =
                N'processed: ' +
                CASE
                    WHEN @get_all_databases = 0
                    THEN ISNULL(@database_name, N'None')
                    ELSE
                        ISNULL
                        (
                            STUFF
                            (
                                (
                                    SELECT
                                        N', ' +
                                        d.database_name
                                    FROM #databases AS d
                                    ORDER BY
                                        d.database_name
                                    FOR
                                        XML
                                        PATH(''),
                                        TYPE
                                ).value('.', 'nvarchar(max)'),
                                1,
                                2,
                                N''
                            ),
                            N'None'
                        )
                END,
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
                    nvarchar(19),
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
                    21
                ) +
                N' through ' +
                CONVERT
                (
                    nvarchar(19),
                    ISNULL
                    (
                        @end_date_original,
                        SYSDATETIME()
                    ),
                    21
                ),
            all_done =
                'https://www.erikdarling.com/',
            databases =
                N'skipped: ' +
                ISNULL
                (
                    STUFF
                    (
                        (
                            SELECT
                                N', ' +
                                rbs.database_name +
                                N' (' +
                                rbs.reason +
                                N')'
                            FROM #requested_but_skipped_databases AS rbs
                            ORDER BY
                                rbs.database_name
                            FOR
                                XML
                                PATH(''),
                                TYPE
                        ).value('.', 'nvarchar(max)'),
                        1,
                        2,
                        N''
                    ),
                    N'None'
                ),
            support =
                'https://code.erikdarling.com',
            help =
                'EXECUTE sp_QuickieStore @help = 1;',
            problems =
                'EXECUTE sp_QuickieStore @debug = 1;',
            performance =
                'EXECUTE sp_QuickieStore @troubleshoot_performance = 1;',
            version_and_date =
                N'version date: ' + CONVERT(nvarchar(10), @version_date, 23),
            thanks =
                'i hope you find it useful, or whatever'
    ) AS x
    ORDER BY
        x.sort;
END; /*End hide_help_table <> 1 */

END TRY

/*Error handling!*/
BEGIN CATCH
    /*
    Where the error happened and the message
    */
    IF @current_table IS NOT NULL
    BEGIN
        RAISERROR('current dynamic activity', 10, 1) WITH NOWAIT;
        RAISERROR('error while %s with @expert mode = %i and format_output = %i', 10, 1, @current_table, @em, @fo) WITH NOWAIT;
    END;

    /*
    Query that caused the error
    */
    IF @sql IS NOT NULL
    BEGIN
        RAISERROR('current dynamic sql:', 10, 1) WITH NOWAIT;
        RAISERROR('%s', 10, 1, @sql) WITH NOWAIT;
    END;

    IF @debug = 1
    BEGIN
        GOTO DEBUG;
    END;
    IF @debug = 0
    BEGIN;
        THROW;
    END;
END CATCH;

/*
Debug elements!
*/
DEBUG:
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
        query_text_search_not =
            @query_text_search_not,
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
        hide_help_table =
            @hide_help_table,
        format_output =
            @format_output,
        get_all_databases =
            @get_all_databases,
        include_databases =
            @include_databases,
        exclude_databases =
            @exclude_databases,
        workdays =
            @workdays,
        work_start =
            @work_start,
        work_end =
            @work_end,
        regression_baseline_start_date =
            @regression_baseline_start_date,
        regression_baseline_end_date =
            @regression_baseline_end_date,
        regression_comparator =
            @regression_comparator,
        regression_direction =
            @regression_direction,
        include_query_hash_totals =
            @include_query_hash_totals,
        include_maintenance =
            @include_maintenance,
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
        regression_where_clause =
            @regression_where_clause,
        procedure_exists =
            @procedure_exists,
        query_store_exists =
            @query_store_exists,
        query_store_trouble =
            @query_store_trouble,
        query_store_waits_enabled =
            @query_store_waits_enabled,
        sort_order_is_a_wait =
            @sort_order_is_a_wait,
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
       regression_baseline_start_date_original =
           @regression_baseline_start_date_original,
       regression_baseline_end_date_original =
           @regression_baseline_end_date_original,
       regression_mode =
           @regression_mode,
       timezone =
           @timezone,
       utc_minutes_difference =
           @utc_minutes_difference,
       utc_offset_string =
           @utc_offset_string,
       df =
           @df,
       work_start_utc =
           @work_start_utc,
       work_end_utc =
           @work_end_utc,
       column_sql =
           @column_sql,
       param_name =
           @param_name,
       param_value =
           @param_value,
       temp_table =
           @temp_table,
       column_name =
           @column_name,
       data_type =
           @data_type,
       is_include =
           @is_include,
       requires_secondary_processing =
           @requires_secondary_processing,
       split_sql =
           @split_sql;

    SELECT
        table_name = '@ColumnDefinitions',
        cd.*
    FROM @ColumnDefinitions AS cd
    WHERE cd.column_id LIKE '%15'
    ORDER BY
        cd.column_id;

    SELECT
        table_name = '@FilterParameters',
        fp.*
    FROM @FilterParameters AS fp
    ORDER BY
        fp.parameter_name;

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
           FROM #include_databases AS id
       )
    BEGIN
        SELECT
            table_name =
                '#include_databases',
            id.*
        FROM #include_databases AS id
        ORDER BY
            id.database_name
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#include_databases is empty';
    END;

    IF EXISTS
       (
           SELECT
               1/0
           FROM #exclude_databases AS ed
       )
    BEGIN
        SELECT
            table_name =
                '#exclude_databases',
            ed.*
        FROM #exclude_databases AS ed
        ORDER BY
            ed.database_name
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#exclude_databases is empty';
    END;

    IF EXISTS
       (
           SELECT
               1/0
           FROM #requested_but_skipped_databases AS rsdb
       )
    BEGIN
        SELECT
            table_name =
                '#requested_but_skipped_databases',
            rsdb.*
        FROM #requested_but_skipped_databases AS rsdb
        ORDER BY
            rsdb.database_name
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#requested_but_skipped_databases is empty';
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
           FROM #procedure_object_ids AS poi
       )
    BEGIN
        SELECT
            table_name =
                '#procedure_object_ids',
            poi.*
        FROM #procedure_object_ids AS poi
        ORDER BY
            poi.object_id
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#procedure_object_ids is empty';
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
           FROM #plan_ids_having_enough_executions AS plans
       )
    BEGIN
        SELECT
            table_name =
                '#plan_ids_having_enough_executions',
            plans.*
        FROM #plan_ids_having_enough_executions AS plans
        ORDER BY
            plans.plan_id
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#plan_ids_having_enough_executions is empty';
    END;

    IF EXISTS
       (
           SELECT
               1/0
           FROM #plan_ids_with_query_hashes AS hashes
       )
    BEGIN
        SELECT
            table_name =
                '#plan_ids_with_query_hashes',
            hashes.*
        FROM #plan_ids_with_query_hashes AS hashes
        ORDER BY
            hashes.plan_id
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#plan_ids_with_query_hashes is empty';
    END;

    IF EXISTS
       (
           SELECT
               1/0
           FROM #plan_ids_with_total_waits AS waits
       )
    BEGIN
        SELECT
            table_name =
                '#plan_ids_with_total_waits',
            waits.*
        FROM #plan_ids_with_total_waits AS waits
        ORDER BY
            waits.plan_id
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#plan_ids_with_total_waits is empty';
    END;

    IF EXISTS
       (
           SELECT
               1/0
           FROM #regression_baseline_runtime_stats AS runtime_stats_baseline
       )
    BEGIN
        SELECT
            table_name =
                '#regression_baseline_runtime_stats',
            runtime_stats_baseline.*
        FROM #regression_baseline_runtime_stats AS runtime_stats_baseline
        ORDER BY
           runtime_stats_baseline.query_hash
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#regression_baseline_runtime_stats is empty';
    END;

    IF EXISTS
       (
           SELECT
               1/0
           FROM #regression_current_runtime_stats AS runtime_stats_current
       )
    BEGIN
        SELECT
            table_name =
                '#regression_current_runtime_stats',
            runtime_stats_current.*
        FROM #regression_current_runtime_stats AS runtime_stats_current
        ORDER BY
           runtime_stats_current.query_hash
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#regression_current_runtime_stats is empty';
    END;

    IF EXISTS
       (
           SELECT
               1/0
           FROM #regression_changes AS changes
       )
    BEGIN
        SELECT
            table_name =
                '#regression_changes',
            changes.*
        FROM #regression_changes AS changes
        ORDER BY
           changes.plan_id
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#regression_changes is empty';
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
                             WHERE dqso.wait_stats_capture_mode_desc <> N'ON'
                         )
                    AND EXISTS
                        (
                            SELECT
                                1/0
                            FROM #database_query_store_options AS dqso
                            WHERE dqso.wait_stats_capture_mode_desc = N'ON'
                        )
                    THEN ' because we ignore wait stats if you have disabled capturing them in your Query Store options and everywhere that had it enabled had no data'
                    WHEN EXISTS
                         (
                             SELECT
                                 1/0
                             FROM #database_query_store_options AS dqso
                             WHERE dqso.wait_stats_capture_mode_desc <> N'ON'
                         )
                    THEN ' because we ignore wait stats if you have disabled capturing them in your Query Store options'
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
    IF EXISTS
       (
          SELECT
              1/0
          FROM #query_hash_totals AS qht
       )
    BEGIN
        SELECT
            table_name =
                '#query_hash_totals',
            qht.*
        FROM #query_hash_totals AS qht
        ORDER BY
            qht.database_id
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#query_hash_totals is empty';
    END;
    RETURN; /*Stop doing anything, I guess*/
END; /*End debug*/
RETURN; /*Yeah sure why not?*/
END;/*Final End*/
GO
