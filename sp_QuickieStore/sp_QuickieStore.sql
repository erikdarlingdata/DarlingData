SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET IMPLICIT_TRANSACTIONS OFF;
SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
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

Copyright 2021 Darling Data, LLC
https://www.erikdarlingdata.com/

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

CREATE OR ALTER PROCEDURE dbo.sp_QuickieStore
(
    @database_name sysname = NULL,
    @sort_order varchar(20) = 'cpu',
    @top bigint = 10,
    @start_date datetime = NULL,
    @end_date datetime = NULL,
    @execution_count bigint = NULL,
    @duration_ms bigint = NULL ,
    @procedure_schema sysname = NULL,
    @procedure_name sysname = NULL,
    @include_plan_ids nvarchar(4000) = NULL,
    @include_query_ids nvarchar(4000) = NULL,
    @ignore_plan_ids nvarchar(4000) = NULL,
    @ignore_query_ids nvarchar(4000) = NULL,
    @query_text_search nvarchar(4000) = NULL,
    @wait_filter varchar(20) = NULL,
    @expert_mode bit = 0,
    @format_output bit = 0,
    @version varchar(30) = NULL OUTPUT,
    @version_date datetime = NULL OUTPUT,
    @help bit = 0,
    @debug bit = 0,
    @troubleshoot_performance bit = 0
)
WITH RECOMPILE
AS
BEGIN

SET STATISTICS XML OFF;
SET NOCOUNT, XACT_ABORT ON;
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
    @version = '1.70', 
    @version_date = '20210731';

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
    SELECT 'you got me from https://www.erikdarlingdata.com/sp_quickiestore/' UNION ALL
    SELECT 'i can be used to quickly grab misbehaving queries from query store' UNION ALL
    SELECT 'the plan analysis is up to you; there will not be any XML shredding here' UNION ALL
    SELECT 'so what can you do, and how do you do it? read below!';

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
                WHEN '@database_name' THEN 'the name of the database you want to look at query store in'
                WHEN '@sort_order' THEN 'the runtime metric you want to prioritize results by'
                WHEN '@top' THEN 'the number of queries you want to pull back'
                WHEN '@start_date' THEN 'the begin date of your search'
                WHEN '@end_date' THEN 'the end date of your search'
                WHEN '@execution_count' THEN 'the minimum number of executions a query must have'
                WHEN '@duration_ms' THEN 'the minimum duration a query must have'
                WHEN '@procedure_schema' THEN 'the schema of the procedure you''re searching for'
                WHEN '@procedure_name' THEN 'the name of the programmable object you''re searching for'
                WHEN '@include_plan_ids' THEN 'a list of plan ids to search for'
                WHEN '@include_query_ids' THEN 'a list of query ids to search for'
                WHEN '@ignore_plan_ids' THEN 'a list of plan ids to ignore'
                WHEN '@ignore_query_ids' THEN 'a list of query ids to ignore'
                WHEN '@query_text_search' THEN 'query text to search for'
                WHEN '@wait_filter' THEN 'wait category to search for; category details are below'
                WHEN '@expert_mode' THEN 'returns additional columns and results'
                WHEN '@format_output' THEN 'returns numbers formatted with commas'
                WHEN '@version' THEN 'OUTPUT; for support'
                WHEN '@version_date' THEN 'OUTPUT; for support'
                WHEN '@help' THEN 'how you got here'
                WHEN '@debug' THEN 'prints dynamic sql (including statement length), parameter and variable values, and raw temp table contents'
                WHEN '@troubleshoot_performance' THEN 'set statistics xml on for queries against views'
            END,
        valid_inputs =
            CASE
                ap.name
                WHEN '@database_name' THEN 'a database name with query store enabled'
                WHEN '@sort_order' THEN 'cpu, logical reads, physical reads, writes, duration, memory, tempdb, executions'
                WHEN '@top' THEN 'a positive integer between 1 and 9,223,372,036,854,775,807'
                WHEN '@start_date' THEN 'January 1, 1753, through December 31, 9999'
                WHEN '@end_date' THEN 'January 1, 1753, through December 31, 9999'
                WHEN '@execution_count' THEN 'a positive integer between 1 and 9,223,372,036,854,775,807'
                WHEN '@duration_ms' THEN 'a positive integer between 1 and 9,223,372,036,854,775,807'
                WHEN '@procedure_schema' THEN 'a valid schema in your database'
                WHEN '@procedure_name' THEN 'a valid programmable object in your database'
                WHEN '@include_plan_ids' THEN 'a string; comma separated for multiple ids'
                WHEN '@include_query_ids' THEN 'a string; comma separated for multiple ids'
                WHEN '@ignore_plan_ids' THEN 'a string; comma separated for multiple ids'
                WHEN '@ignore_query_ids' THEN 'a string; comma separated for multiple ids'
                WHEN '@query_text_search' THEN 'a string; leading and trailing wildcards will be added if missing'
                WHEN '@wait_filter' THEN 'cpu, lock, latch, buffer latch, buffer io, log io, network io, parallelism, memory'
                WHEN '@expert_mode' THEN '0 or 1'
                WHEN '@format_output' THEN '0 or 1'
                WHEN '@version' THEN 'none'
                WHEN '@version_date' THEN 'none'
                WHEN '@help' THEN '0 or 1'
                WHEN '@debug' THEN '0 or 1'
                WHEN '@troubleshoot_performance' THEN '0 or 1'
            END,
        defaults =
            CASE
                ap.name
                WHEN '@database_name' THEN 'NULL'
                WHEN '@sort_order' THEN 'cpu'
                WHEN '@top' THEN '10'
                WHEN '@start_date' THEN 'the last 24 hours'
                WHEN '@end_date' THEN 'NULL'
                WHEN '@execution_count' THEN 'NULL'
                WHEN '@duration_ms' THEN 'NULL'
                WHEN '@procedure_schema' THEN 'NULL; dbo if NULL and procedure name is not NULL'
                WHEN '@procedure_name' THEN 'NULL'
                WHEN '@include_plan_ids' THEN 'NULL'
                WHEN '@include_query_ids' THEN 'NULL'
                WHEN '@ignore_plan_ids' THEN 'NULL'
                WHEN '@ignore_query_ids' THEN 'NULL'
                WHEN '@query_text_search' THEN 'NULL'
                WHEN '@wait_filter' THEN 'NULL'
                WHEN '@expert_mode' THEN '0'
                WHEN '@format_output' THEN '0'
                WHEN '@version' THEN 'none'
                WHEN '@version_date' THEN 'none'
                WHEN '@help' THEN '0'
                WHEN '@debug' THEN '0'
                WHEN '@troubleshoot_performance' THEN '0'
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
    Wait categories
    */

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
    SELECT 'Query Store Waits By Query(expert mode only): information about query duration and logged wait stats' UNION ALL
    SELECT 'it can sometimes be useful to compare query duration to query wait times' UNION ALL
    SELECT REPLICATE('-', 100) UNION ALL
    SELECT 'Query Store Waits Total(expert mode only): total wait stats for the chosen date range only' UNION ALL
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
    SELECT 'i do not currently support synapse or edge or other memes';

    /*
    License to F5
    */
    SELECT
        mit_license_yo =
           'i am MIT licensed, so like, do whatever' UNION ALL
    SELECT 'see printed messages for full license';

    RAISERROR('
MIT License

Copyright 2021 Darling Data, LLC

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
Hold plan_ids for plans we want
*/
CREATE TABLE
    #include_plan_ids
(
    plan_id bigint PRIMARY KEY
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
    plan_id bigint PRIMARY KEY
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
Plans and Plan information
*/
CREATE TABLE
    #query_store_plan
(
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
    last_force_failure_reason int NOT NULL,
    last_force_failure_reason_desc nvarchar(128) NULL,
    count_compiles bigint NULL,
    initial_compile_start_time datetimeoffset(7) NOT NULL,
    last_compile_start_time datetimeoffset(7) NULL,
    last_execution_time datetimeoffset(7) NULL,
    avg_compile_duration_ms float NULL,
    last_compile_duration_ms bigint NULL,
    plan_forcing_type int NULL,
    plan_forcing_type_desc nvarchar(60) NULL
);

/*
Queries and Compile Information
*/
CREATE TABLE
    #query_store_query
(
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
    query_parameterization_type tinyint NOT NULL,
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
    is_clouddb_internal_query bit NULL,
    database_id int NULL
);

/*
Query Text And Columns From sys.dm_exec_query_stats
*/
CREATE TABLE
    #query_store_query_text
(
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
                    ), 0
                ), 0
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
Wait Stats, When Available
*/
CREATE TABLE
    #query_store_wait_stats
(
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

/*
Try to be helpful by subbing in a database name if null
*/
IF
  (
      @database_name IS NULL
        AND LOWER
            (
                DB_NAME()
            )
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
    @sql nvarchar(max),
    @isolation_level nvarchar(max),
    @parameters nvarchar(200),
    @plans_top bigint,
    @nc10 nvarchar(2),
    @where_clause nvarchar(max),
    @procedure_exists bit,
    @query_store_exists bit,
    @query_store_waits_enabled bit,
    @string_split nvarchar(1500),
    @current_table nvarchar(100),
    @troubleshoot_insert nvarchar(max),
    @troubleshoot_update nvarchar(max),
    @troubleshoot_info nvarchar(max),
    @rc bigint;

/*
Some variable assignment, because why not?
*/
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
          @start_date datetime,
          @end_date datetime,
          @execution_count bigint,
          @duration_ms bigint',
    @plans_top =
        CASE
            WHEN @include_plan_ids IS NULL
            THEN 1
            ELSE 10
         END,
    @nc10 = NCHAR(10),
    @where_clause = N'',
    @procedure_exists = 0,
    @query_store_exists = 0,
    @query_store_waits_enabled = 0,
    @current_table = N'',
    @string_split = N'
    SELECT DISTINCT
        LTRIM
        (
            RTRIM
            (
                ids.ids
            )
        ) AS ids
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
        UPDATE tp
            SET tp.end_time = GETDATE()
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
                FOR XML PATH(N''''), TYPE
            ).query(''.[1]'') AS current_query
        OPTION(RECOMPILE);',
    @rc = 0;

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
    @wait_filter =
        NULLIF(@wait_filter, ''),
    @format_output =
        ISNULL(@format_output, 0),
    @help =
        ISNULL(@help, 0),
    @debug =
        ISNULL(@debug, 0),
    @troubleshoot_performance =
        ISNULL(@troubleshoot_performance, 0);

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
    RAISERROR('Database %s does not exist', 11, 1, @database_name) WITH NOWAIT;
    RETURN;
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
    RAISERROR('Azure databases in compatiblity levels under 130 are not supported', 11, 1) WITH NOWAIT;
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
                     WHERE ( dqso.actual_state = 0
                               OR dqso.actual_state IS NULL )
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

IF @debug = 1 BEGIN PRINT LEN(@sql); PRINT @sql; END;

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
        RAISERROR('Query Store doesn''t seem to be enabled for database: %s', 11, 1, @database_name) WITH NOWAIT;
        RETURN;
    END;

/*
If you specified a procedure name, we need to figure out if it's there
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

    IF @debug = 1 BEGIN PRINT LEN(@sql); PRINT @sql; END;

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

    IF @procedure_exists = 0
        BEGIN
            RAISERROR('The stored procedure %s does not appear to have any entries in Query Store for database %s
Check that you spelled everything correctly and you''re in the right database',
                       11, 1, @procedure_name, @database_name) WITH NOWAIT;
        RETURN;
    END;
END;

/*
Some things are version dependent.
Normally, I'd check for object existence, but the documentation
leads me to believe that certain things won't be back-ported,
like the wait stats DMV, and tempdb spills columns
*/
IF
  (
      @product_version > 13
        OR @azure = 1
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
                   'executions'
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

IF
(
    @wait_filter IS NOT NULL
      AND @new = 0
)
BEGIN
   RAISERROR('Query Store wait stats are not available prior to SQL Server 2017', 11, 1) WITH NOWAIT;
   RETURN;
END;

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
   RAISERROR('The wait category (%s) you chose is invalid', 11, 1, @wait_filter) WITH NOWAIT;
   RETURN;
END;

IF
(
    @wait_filter IS NOT NULL
      AND @new = 1
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
    
    IF @debug = 1 BEGIN PRINT LEN(@sql); PRINT @sql; END;
    
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
       RAISERROR('Query Store wait stats are not enabled for database %s', 11, 1, @database_name_quoted) WITH NOWAIT;
       RETURN;
    END

END;


/*
Get filters ready, or whatever
We're only going to pull some stuff from runtime stats and plans
*/

IF @start_date IS NULL
BEGIN
    SELECT
        @where_clause += N'AND   qsrs.last_execution_time >= DATEADD(DAY, -1, DATEDIFF(DAY, 0, SYSDATETIME()))' + @nc10;
END;

IF @start_date IS NOT NULL
BEGIN
    SELECT
        @where_clause += N'AND   qsrs.last_execution_time >= @start_date' + @nc10;
END;

IF @end_date IS NOT NULL
BEGIN
    SELECT
        @where_clause += N'AND   qsrs.last_execution_time < @end_date' + @nc10;
END;

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

    IF @debug = 1 BEGIN PRINT LEN(@sql); PRINT @sql; END;

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

END;

/*
This section filters query or plan ids
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
            @current_table = 'inserting #include_plan_ids';

        INSERT
            #include_plan_ids WITH(TABLOCK)
        (
            plan_id
        )
        EXEC sys.sp_executesql
            @string_split,
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

    END;

    IF @ignore_plan_ids IS NOT NULL
    BEGIN

        SELECT
            @current_table = 'inserting #ignore_plan_ids';

        INSERT
            #ignore_plan_ids WITH(TABLOCK)
        (
            plan_id
        )
        EXEC sys.sp_executesql
            @string_split,
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

    END;

    IF @include_query_ids IS NOT NULL
    BEGIN

        SELECT
            @current_table = 'inserting #include_query_ids',
            @sql = @isolation_level;

        INSERT
            #include_query_ids WITH(TABLOCK)
        (
            query_id
        )
        EXEC sys.sp_executesql
            @string_split,
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

        IF @debug = 1 BEGIN PRINT LEN(@sql); PRINT @sql; END;

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

    END;

    IF @ignore_query_ids IS NOT NULL
    BEGIN

        SELECT
            @current_table = 'inserting #ignore_query_ids',
            @sql = @isolation_level;

        INSERT
            #ignore_query_ids WITH(TABLOCK)
        (
            query_id
        )
        EXEC sys.sp_executesql
            @string_split,
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

        IF @debug = 1 BEGIN PRINT LEN(@sql); PRINT @sql; END;

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
    END;

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
      )
OPTION(RECOMPILE);' + @nc10;

    IF @debug = 1 BEGIN PRINT LEN(@sql); PRINT @sql; END;

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
WHERE qsws.execution_type = 0
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
GROUP BY qsws.plan_id
HAVING SUM(qsws.avg_query_wait_time_ms) > 1000.
ORDER BY SUM(qsws.avg_query_wait_time_ms) DESC
OPTION(RECOMPILE, OPTIMIZE FOR (@top = 9223372036854775807));' + @nc10;

    END;

    IF @debug = 1 BEGIN PRINT LEN(@sql); PRINT @sql; END;

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
              AND   qsqt.query_sql_text NOT LIKE ''ALTER INDEX%''
              AND   qsqt.query_sql_text NOT LIKE ''CREATE%INDEX%''
              AND   qsqt.query_sql_text NOT LIKE ''CREATE STATISTICS%''
              AND   qsqt.query_sql_text NOT LIKE ''UPDATE STATISTICS%''
              AND   qsqt.query_sql_text NOT LIKE ''SELECT StatMan%''
          )
OPTION(RECOMPILE);' + @nc10;

IF @debug = 1 BEGIN PRINT LEN(@sql); PRINT @sql; END;

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
            LEN
            (
                @where_clause
            ) - 1
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
WHERE qsrs.execution_type = 0
' + @where_clause
  + N'
GROUP BY qsrs.plan_id
ORDER BY MAX(' +
CASE @sort_order
     WHEN 'cpu' THEN N'qsrs.avg_cpu_time'
     WHEN 'logical reads' THEN N'qsrs.avg_logical_io_reads'
     WHEN 'physical reads' THEN N'qsrs.avg_physical_io_reads'
     WHEN 'writes' THEN N'qsrs.avg_logical_io_writes'
     WHEN 'duration' THEN N'qsrs.avg_duration'
     WHEN 'memory' THEN N'qsrs.avg_query_max_used_memory'
     WHEN 'tempdb' THEN CASE WHEN @new = 1 THEN N'qsrs.avg_tempdb_space_used' ELSE N'qsrs.avg_cpu_time' END
     WHEN 'executions' THEN N'qsrs.count_executions'
     ELSE N'qsrs.avg_cpu_time'
END +
N') DESC
OPTION(RECOMPILE, OPTIMIZE FOR (@top = 9223372036854775807));' + @nc10;

IF @debug = 1 BEGIN PRINT LEN(@sql); PRINT @sql; END;

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
    @duration_ms;

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
    qsrs.runtime_stats_id,
    qsrs.plan_id,
    qsrs.runtime_stats_interval_id,
    qsrs.execution_type_desc,
    qsrs.first_execution_time,
    qsrs.last_execution_time,
    qsrs.count_executions,
    (qsrs.avg_duration / 1000.),
    (qsrs.last_duration / 1000.),
    (qsrs.min_duration / 1000.),
    (qsrs.max_duration / 1000.),
    (qsrs.avg_cpu_time / 1000.),
    (qsrs.last_cpu_time / 1000.),
    (qsrs.min_cpu_time / 1000.),
    (qsrs.max_cpu_time / 1000.),
    ((qsrs.avg_logical_io_reads * 8.) / 1024.),
    ((qsrs.last_logical_io_reads * 8.) / 1024.),
    ((qsrs.min_logical_io_reads * 8.) / 1024.),
    ((qsrs.max_logical_io_reads * 8.) / 1024.),
    ((qsrs.avg_logical_io_writes * 8.) / 1024.),
    ((qsrs.last_logical_io_writes * 8.) / 1024.),
    ((qsrs.min_logical_io_writes * 8.) / 1024.),
    ((qsrs.max_logical_io_writes * 8.) / 1024.),
    ((qsrs.avg_physical_io_reads * 8.) / 1024.),
    ((qsrs.last_physical_io_reads * 8.) / 1024.),
    ((qsrs.min_physical_io_reads * 8.) / 1024.),
    ((qsrs.max_physical_io_reads * 8.) / 1024.),
    (qsrs.avg_clr_time / 1000.),
    (qsrs.last_clr_time / 1000.),
    (qsrs.min_clr_time / 1000.),
    (qsrs.max_clr_time / 1000.),
    qsrs.last_dop,
    qsrs.min_dop,
    qsrs.max_dop,
    ((qsrs.avg_query_max_used_memory * 8.) / 1024.),
    ((qsrs.last_query_max_used_memory * 8.) / 1024.),
    ((qsrs.min_query_max_used_memory * 8.) / 1024.),
    ((qsrs.max_query_max_used_memory * 8.) / 1024.),
    qsrs.avg_rowcount,
    qsrs.last_rowcount,
    qsrs.min_rowcount,
    qsrs.max_rowcount,';

IF @new = 1
    BEGIN

        SELECT
            @sql += N'
    ((qsrs.avg_num_physical_io_reads * 8.) / 1024.),
    ((qsrs.last_num_physical_io_reads * 8.) / 1024.),
    ((qsrs.min_num_physical_io_reads * 8.) / 1024.),
    ((qsrs.max_num_physical_io_reads * 8.) / 1024.),
    (qsrs.avg_log_bytes_used / 100000000.),
    (qsrs.last_log_bytes_used / 100000000.),
    (qsrs.min_log_bytes_used / 100000000.),
    (qsrs.max_log_bytes_used / 100000000.),
    ((qsrs.avg_tempdb_space_used * 8) / 1024.),
    ((qsrs.last_tempdb_space_used * 8) / 1024.),
    ((qsrs.min_tempdb_space_used * 8) / 1024.),
    ((qsrs.max_tempdb_space_used * 8) / 1024.),';

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
    SELECT TOP (1)
        qsrs.*
    FROM ' + @database_name_quoted + N'.sys.query_store_runtime_stats AS qsrs
    WHERE qsrs.plan_id = dp.plan_id
    AND   qsrs.execution_type = 0
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
     ELSE N'qsrs.avg_cpu_time'
END + N' DESC
) AS qsrs
OPTION(RECOMPILE);' + @nc10;

IF @debug = 1 BEGIN PRINT LEN(@sql); PRINT @sql; END;

INSERT
    #query_store_runtime_stats WITH(TABLOCK)
(
    runtime_stats_id, plan_id, runtime_stats_interval_id, execution_type_desc,
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
    @duration_ms;

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
FROM ' + @database_name_quoted + N'.sys.query_context_settings;';

INSERT
    #query_context_settings WITH(TABLOCK)
(
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
    qsp.last_force_failure_reason,
    qsp.last_force_failure_reason_desc,
    qsp.count_compiles,
    qsp.initial_compile_start_time,
    qsp.last_compile_start_time,
    qsp.last_execution_time,
    (qsp.avg_compile_duration / 1000.),
    (qsp.last_compile_duration / 1000.),';

IF @new = 1
BEGIN
    SELECT
        @sql += N'
    qsp.plan_forcing_type,
    qsp.plan_forcing_type_desc';
END;

IF @new = 0
BEGIN
    SELECT
        @sql += N'
    NULL,
    NULL';
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
    AND   qsp.last_execution_time >= qsrs.last_execution_time
    AND   qsp.is_online_index_plan = 0
    ORDER BY qsp.last_execution_time DESC
) AS qsp
OPTION(RECOMPILE, OPTIMIZE FOR (@plans_top = 9223372036854775807));' + @nc10;

IF @debug = 1 BEGIN PRINT LEN(@sql); PRINT @sql; END;

INSERT
    #query_store_plan WITH(TABLOCK)
(
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
    last_force_failure_reason,
    last_force_failure_reason_desc,
    count_compiles,
    initial_compile_start_time,
    last_compile_start_time,
    last_execution_time,
    avg_compile_duration_ms,
    last_compile_duration_ms,
    plan_forcing_type,
    plan_forcing_type_desc
)
EXEC sys.sp_executesql
    @sql,
  N'@plans_top bigint',
    @plans_top;

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
    qsq.query_id,
    qsq.query_text_id,
    qsq.context_settings_id,
    qsq.object_id,
    qsq.batch_sql_handle,
    qsq.query_hash,
    qsq.is_internal_query,
    qsq.query_parameterization_type,
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
    qsq.is_clouddb_internal_query,
    @database_id
FROM #query_store_plan AS qsp
CROSS APPLY
(
    SELECT TOP (1)
        qsq.*
    FROM ' + @database_name_quoted + N'.sys.query_store_query AS qsq
    WHERE qsq.query_id = qsp.query_id
    AND   qsq.last_execution_time >= qsp.last_execution_time
    ORDER BY qsq.last_execution_time DESC
) AS qsq
OPTION(RECOMPILE);' + @nc10;

IF @debug = 1 BEGIN PRINT LEN(@sql); PRINT @sql; END;

INSERT
    #query_store_query WITH(TABLOCK)
(
    query_id,
    query_text_id,
    context_settings_id,
    object_id,
    batch_sql_handle,
    query_hash,
    is_internal_query,
    query_parameterization_type,
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
    is_clouddb_internal_query,
    database_id
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
    qsqt.query_text_id,
    query_sql_text =
        (
             SELECT
                 [processing-instruction(query)] =
                     qsqt.query_sql_text
             FOR XML PATH(''''), TYPE
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
OPTION(RECOMPILE);' + @nc10;

IF @debug = 1 BEGIN PRINT LEN(@sql); PRINT @sql; END;

INSERT
    #query_store_query_text WITH(TABLOCK)
(
    query_text_id,
    query_sql_text,
    statement_sql_handle,
    is_part_of_encrypted_module,
    has_restricted_text
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
GROUP BY deqs.statement_sql_handle
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

END;

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

    UPDATE qsqt
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

END;

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
        WHEN (@product_version > 14
                OR @azure = 1)
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

IF @debug = 1 BEGIN PRINT LEN(@sql); PRINT @sql; END;

INSERT
    #database_query_store_options WITH(TABLOCK)
(
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
              WHERE dqso.wait_stats_capture_mode_desc = 'ON'
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
    AND   qsws.execution_type = 0
    AND   qsws.wait_category > 0
    ORDER BY qsws.avg_query_wait_time_ms DESC
) AS qsws
GROUP BY
    qsws.plan_id,
    qsws.wait_category_desc
HAVING SUM(qsws.min_query_wait_time_ms) >= 0.
OPTION(RECOMPILE);' + @nc10;

    IF @debug = 1 BEGIN PRINT LEN(@sql); PRINT @sql; END;

    INSERT
        #query_store_wait_stats WITH(TABLOCK)
    (
        plan_id,
        wait_category_desc,
        total_query_wait_time_ms,
        avg_query_wait_time_ms,
        last_query_wait_time_ms,
        min_query_wait_time_ms,
        max_query_wait_time_ms
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

END;

/*
Update things to get the context settings for each query
*/
SELECT
    @current_table = 'updating context_settings in #query_store_runtime_stats';

UPDATE qsrs
    SET qsrs.context_settings =
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
    ON qsrs.plan_id = qsp.plan_id
JOIN #query_store_query AS qsq
    ON qsp.query_id = qsq.query_id
JOIN #query_context_settings AS qcs
    ON qsq.context_settings_id = qcs.context_settings_id
OPTION(RECOMPILE);

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
        @current_table = 'selecting #query_store_wait_stats';

    SELECT
        @sql += N'
SELECT
    x.*
FROM
(';

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
            @sql += N'
    SELECT
        source =
            ''runtime_stats'',
        qsp.query_id,
        qsrs.plan_id,
        qsp.all_plan_ids,
        qsrs.execution_type_desc,
        qsq.object_name,
        qsqt.query_sql_text,
        qsp.compatibility_level,
        query_plan = TRY_CONVERT(XML, qsp.query_plan),'
        +
            CASE @new
                 WHEN 1
                 THEN
        N'
        qsp.plan_forcing_type_desc,
        w.top_waits,'
                 ELSE
        N''
            END + N'
        qsrs.first_execution_time,
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
            END + N'
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
        ELSE N'qsrs.avg_cpu_time_ms'
    END + N' DESC
            )';

    END;

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
            @sql += N'
    SELECT
        source =
            ''runtime_stats'',
        qsp.query_id,
        qsrs.plan_id,
        qsp.all_plan_ids,
        qsrs.execution_type_desc,
        qsq.object_name,
        qsqt.query_sql_text,
        qsp.compatibility_level,
        query_plan = TRY_CONVERT(XML, qsp.query_plan),'
        +
            CASE @new
                 WHEN 1
                 THEN
        N'
        qsp.plan_forcing_type_desc,
        w.top_waits,'
                 ELSE
        N''
            END + N'
        qsrs.first_execution_time,
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
        +
            CASE @new
                 WHEN 1
                 THEN
        CONVERT
        (
            nvarchar(max),
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
        )
                 ELSE
        N''
            END + N'
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
        ELSE N'qsrs.avg_cpu_time_ms'
    END + N' DESC
            )';

    END;

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
            @sql += N'
    SELECT
        source =
            ''runtime_stats'',
        qsp.query_id,
        qsrs.plan_id,
        qsp.all_plan_ids,
        qsrs.execution_type_desc,
        qsq.object_name,
        qsqt.query_sql_text,
        qsp.compatibility_level,
        query_plan = TRY_CONVERT(XML, qsp.query_plan),'
        +
            CASE @new
                 WHEN 1
                 THEN
        N'
        qsp.plan_forcing_type_desc,
        w.top_waits,'
                 ELSE
        N''
            END + N'
        qsrs.first_execution_time,
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
            END + N'
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
        ELSE N'qsrs.avg_cpu_time_ms'
    END + N' DESC
            )';

    END;

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
            @sql += N'
    SELECT
        source =
            ''runtime_stats'',
        qsp.query_id,
        qsrs.plan_id,
        qsp.all_plan_ids,
        qsrs.execution_type_desc,
        qsq.object_name,
        qsqt.query_sql_text,
        qsp.compatibility_level,
        query_plan = TRY_CONVERT(XML, qsp.query_plan),'
        +
            CASE @new
                 WHEN 1
                 THEN
        N'
        qsp.plan_forcing_type_desc,
        w.top_waits,'
                 ELSE
        N''
            END + N'
        qsrs.first_execution_time,
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
            END + N'
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
         ELSE N'qsrs.avg_cpu_time_ms'
    END + N' DESC
            )';

    END;

    /*
    Add on the from and stuff
    */
    SELECT
        @sql += N'
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
        ORDER BY qsq.last_execution_time DESC
    ) AS qsqt
    CROSS APPLY
    (
        SELECT TOP (1)
            qsq.*
        FROM #query_store_query AS qsq
        WHERE qsq.query_id = qsp.query_id
        ORDER BY qsq.last_execution_time DESC
    ) AS qsq';

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
            @sql += N'
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
                       GROUP BY qsws.wait_category_desc
                       ORDER BY SUM(qsws.avg_query_wait_time_ms) DESC
                       FOR XML PATH(''''), TYPE
                    ).value(''./text()[1]'', ''varchar(max)''),
                    1,
                    2,
                    ''''
                )
    ) AS w';

    END;

    IF
      (
          @new = 1
            AND @format_output = 1
      )
    BEGIN

        SELECT
            @sql += N'
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
                       GROUP BY qsws.wait_category_desc
                       ORDER BY SUM(qsws.avg_query_wait_time_ms) DESC
                       FOR XML PATH(''''), TYPE
                    ).value(''./text()[1]'', ''varchar(max)''),
                    1,
                    2,
                    ''''
                )
    ) AS w';

    END;

    SELECT
        @sql += N'
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
                  WHEN 'tempdb' THEN
                                CASE WHEN @new = 1
                                     THEN N'x.avg_tempdb_space_used_mb'
                                     ELSE N'x.avg_cpu_time'
                                END
                  WHEN 'executions' THEN N'x.count_executions'
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
                  WHEN 'tempdb' THEN
                                CASE WHEN @new = 1
                                     THEN N'CONVERT(money, x.avg_tempdb_space_used_mb)'
                                     ELSE N'CONVERT(money, x.avg_cpu_time)'
                                END
                  WHEN 'executions' THEN N'CONVERT(money, x.count_executions)'
                  ELSE N'CONVERT(money, x.avg_cpu_time_ms)'
             END
    END
             + N' DESC
OPTION(RECOMPILE);' + @nc10;

    IF @debug = 1
    BEGIN
        PRINT LEN(@sql);
        PRINT SUBSTRING(@sql, 0, 4000);
        PRINT SUBSTRING(@sql, 4000, 8000);
    END;


    EXEC sys.sp_executesql
        @sql;

END;
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
      @expert_mode = 1
        AND @format_output = 0
  )
BEGIN

    IF EXISTS
       (
           SELECT
               1/0
            FROM #query_store_query
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
                qsq.query_id,
                qsq.object_name,
                qsq.query_text_id,
                qsq.query_parameterization_type_desc,
                qsq.initial_compile_start_time,
                qsq.last_compile_start_time,
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
            ) AS qsqt
        ) AS x
        WHERE x.n = 1
        ORDER BY x.query_id
        OPTION(RECOMPILE);

    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#query_store_query is empty';
    END;

    IF @rc > 0
    BEGIN

        SELECT
            @current_table = 'selecting resource stats';

        SELECT
            source =
                'resource_stats',
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
            ON qsq.query_text_id = qsqt.query_text_id
        WHERE ( qsqt.total_grant_mb IS NOT NULL
        OR      qsqt.total_reserved_threads IS NOT NULL )
        ORDER BY qsq.query_id
        OPTION(RECOMPILE);

    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#dm_exec_query_stats is empty';
    END;

    IF @new = 1
    BEGIN

        IF EXISTS
           (
               SELECT
                   1/0
                FROM #query_store_wait_stats
           )
        BEGIN

            SELECT
                @current_table = 'selecting wait stats by query';

            SELECT DISTINCT
                source =
                    'query_store_wait_stats_by_query',
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
                    ON qsrs.plan_id = qsp.plan_id
                JOIN #query_store_query AS qsq
                    ON qsp.query_id = qsq.query_id
                WHERE qsws.plan_id = qsrs.plan_id
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
                    ON qsrs.plan_id = qsp.plan_id
                JOIN #query_store_query AS qsq
                    ON qsp.query_id = qsq.query_id
                WHERE qsws.plan_id = qsrs.plan_id
            ) AS x
            GROUP BY qsws.wait_category_desc
            ORDER BY SUM(qsws.total_query_wait_time_ms) DESC
            OPTION(RECOMPILE);

        END;
        ELSE
        BEGIN
            SELECT
                result =
                    '#query_store_wait_stats is empty' +
                    CASE
                        WHEN (@product_version = 13
                                AND @azure = 0)
                        THEN ' because it''s not available < 2017'
                        ELSE ''
                    END;
        END;

    END;

    SELECT
        @current_table = 'selecting query store options',
        @sql = N'';

    SELECT
        @sql += N'
    SELECT
        source =
            ''query_store_options'',
        dqso.desired_state_desc,
        dqso.actual_state_desc,
        dqso.readonly_reason,
        dqso.current_storage_size_mb,
        dqso.flush_interval_seconds,
        dqso.interval_length_minutes,
        dqso.max_storage_size_mb,
        dqso.stale_query_threshold_days,
        dqso.max_plans_per_query,
        dqso.query_capture_mode_desc,';

        IF
          (
              @azure = 1
                OR @product_version > 13
          )
        BEGIN
            SELECT
                @sql += N'
        dqso.wait_stats_capture_mode_desc,';
        END;

        IF
          (
              @azure = 1
                OR @product_version > 14
          )
        BEGIN
            SELECT
                @sql += N'
        dqso.capture_policy_execution_count,
        dqso.capture_policy_total_compile_cpu_time_ms,
        dqso.capture_policy_total_execution_cpu_time_ms,
        dqso.capture_policy_stale_threshold_hours,';
        END;

    SELECT
        @sql += N'
    dqso.size_based_cleanup_mode_desc
    FROM #database_query_store_options AS dqso
    OPTION(RECOMPILE);';

    IF @debug = 1 BEGIN PRINT LEN(@sql); PRINT @sql; END;

    EXEC sys.sp_executesql
        @sql;

END;

/*
Return special things, formatted
*/
IF
  (
      @expert_mode = 1
        AND @format_output = 1
  )
BEGIN

    IF EXISTS
       (
          SELECT
              1/0
          FROM #query_store_query
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
                qsq.query_id,
                qsq.object_name,
                qsq.query_text_id,
                qsq.query_parameterization_type_desc,
                qsq.initial_compile_start_time,
                qsq.last_compile_start_time,
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
            ) AS qsqt
        ) AS x
        WHERE x.n = 1
        ORDER BY x.query_id
        OPTION(RECOMPILE);

    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#query_store_query is empty';
    END;

    IF @rc > 0
    BEGIN

        SELECT
            @current_table = 'selecting resource stats';

        SELECT
            source =
                'resource_stats',
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
            ON qsq.query_text_id = qsqt.query_text_id
        WHERE ( qsqt.total_grant_mb IS NOT NULL
        OR      qsqt.total_reserved_threads IS NOT NULL )
        ORDER BY qsq.query_id
        OPTION(RECOMPILE);

    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#dm_exec_query_stats is empty';
    END;

    IF @new = 1
    BEGIN

        IF EXISTS
           (
               SELECT
                   1/0
                FROM #query_store_wait_stats
           )
        BEGIN

            SELECT
                @current_table = 'selecting wait stats by query';

            SELECT
                source =
                    'query_store_wait_stats_by_query',
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
                    ON qsrs.plan_id = qsp.plan_id
                JOIN #query_store_query AS qsq
                    ON qsp.query_id = qsq.query_id
                WHERE qsws.plan_id = qsrs.plan_id
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
                    ON qsrs.plan_id = qsp.plan_id
                JOIN #query_store_query AS qsq
                    ON qsp.query_id = qsq.query_id
                WHERE qsws.plan_id = qsrs.plan_id
            ) AS x
            GROUP BY qsws.wait_category_desc
            ORDER BY SUM(qsws.total_query_wait_time_ms) DESC
            OPTION(RECOMPILE);

        END;

    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#query_store_wait_stats is empty' +
                CASE
                    WHEN (@product_version = 13
                            AND @azure = 0)
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

    SELECT
        @current_table = 'selecting query store options',
        @sql = N'';

    SELECT
        @sql += N'
    SELECT
        source =
            ''query_store_options'',
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
        dqso.query_capture_mode_desc,';

        IF
          (
              @azure = 1
                OR @product_version > 13
          )
        BEGIN
            SELECT
                @sql += N'
        dqso.wait_stats_capture_mode_desc,';
        END;

        IF
          (
              @azure = 1
                OR @product_version > 14
          )
        BEGIN
            SELECT
                @sql += N'
        capture_policy_execution_count =
            FORMAT(dqso.capture_policy_execution_count, ''N0''),
        capture_policy_total_compile_cpu_time_ms =
            FORMAT(dqso.capture_policy_total_compile_cpu_time_ms, ''N0''),
        capture_policy_total_execution_cpu_time_ms =
           FORMAT(dqso.capture_policy_total_execution_cpu_time_ms, ''N0''),
        capture_policy_stale_threshold_hours =
            FORMAT(dqso.capture_policy_stale_threshold_hours, ''N0''),';
        END;

    SELECT
        @sql += N'
    dqso.size_based_cleanup_mode_desc
    FROM #database_query_store_options AS dqso
    OPTION(RECOMPILE);';

    IF @debug = 1 BEGIN PRINT LEN(@sql); PRINT @sql; END;

    EXEC sys.sp_executesql
        @sql;

END;

SELECT
    x.all_done,
    x.support,
    x.help,
    x.problems,
    x.performance,
    x.thanks
FROM
(
    SELECT
        sort =
            1,
        all_done =
            'brought to you by erik darling data!',
        support =
            'for support, head over to github',
        help =
            'for local help, use @help = 1',
        problems =
            'to debug issues, use @debug = 1;',
        performance =
            'if this runs slowly, use to get query plans',
        thanks =
            'thanks for using sp_QuickieStore!'

    UNION ALL

    SELECT
        sort =
            2,
        all_done =
            'https://www.erikdarlingdata.com/',
        support =
            'https://github.com/erikdarlingdata/DarlingData',
        help =
            'EXEC sp_QuickieStore @help = 1;',
        problems =
            'EXEC sp_QuickieStore @debug = 1;',
        performance =
            'EXEC sp_QuickieStore @troubleshoot_performance = 1;',
        thanks =
            'i hope you find it useful, or whatever'
) AS x
ORDER BY x.sort;

END TRY
BEGIN CATCH

    /*
    Where the error happened and the message
    */
    IF @current_table IS NOT NULL
    BEGIN
        RAISERROR ('error while %s', 11, 1, @current_table) WITH NOWAIT;
    END;

        /*
        Query that caused the error
        */
    IF @sql IS NOT NULL
    BEGIN
        RAISERROR ('offending query:', 10, 1) WITH NOWAIT;
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
        execution_count =
            @execution_count,
        duration_ms =
            @duration_ms,
        procedure_schema =
            @procedure_schema,
        procedure_name =
            @procedure_name,
        include_plan_ids =
            @include_plan_ids,
        include_query_ids =
            @include_query_ids,
        ignore_plan_ids =
            @ignore_plan_ids,
        ignore_query_ids =
            @ignore_query_ids,
        query_text_search =
            @query_text_search,
        wait_filter =
            @wait_filter,
        expert_mode =
            @expert_mode,
        format_output =
            @format_output,
        version =
            @version,
        version_date =
            @version_date,
        help =
            @help,
        debug =
            @debug,
        troubleshoot_performance =
            @troubleshoot_performance;

    SELECT
        parameter_type =
            'declared_parameters',
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
        [sql] =
            @sql,
         len_sql =
             LEN(@sql),
        isolation_level =
            @isolation_level,
        parameters =
            @parameters,
        plans_top =
            @plans_top,
        nc10 =
            @nc10,
        where_clause =
            @where_clause,
        procedure_exists =
            @procedure_exists,
        query_store_exists =
            @query_store_exists,
        query_store_waits_enabled =
            @query_store_waits_enabled,
        [string_split] =
            @string_split,
        current_table =
            @current_table,
        troubleshoot_insert =
            @troubleshoot_insert,
        troubleshoot_update =
            @troubleshoot_update,
        xml_info =
            @troubleshoot_info,
        rc =
            @rc;

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
        ORDER BY dp.plan_id
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
        ORDER BY pp.plan_id
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
           FROM #include_plan_ids AS ipi
       )
    BEGIN
        SELECT
            table_name =
                '#include_plan_ids',
            ipi.*
        FROM #include_plan_ids AS ipi
        ORDER BY ipi.plan_id
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
        ORDER BY iqi.query_id
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
           FROM #ignore_plan_ids AS ipi
       )
    BEGIN
        SELECT
            table_name =
                '#ignore_plan_ids',
            ipi.*
        FROM #ignore_plan_ids AS ipi
        ORDER BY ipi.plan_id
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
        ORDER BY iqi.query_id
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
          FROM #query_text_search AS qst
       )
    BEGIN
        SELECT
            table_name =
                '#query_text_search',
            qst.*
        FROM #query_text_search AS qst
        ORDER BY qst.plan_id
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
        ORDER BY wf.plan_id
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
        ORDER BY mp.plan_id
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
          FROM #query_store_plan AS qsp
       )
    BEGIN
        SELECT
            table_name =
                '#query_store_plan',
            qsp.*
        FROM #query_store_plan AS qsp
        ORDER BY qsp.plan_id, qsp.query_id
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
        ORDER BY qsq.query_id, qsq.query_text_id
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
        ORDER BY qsqt.query_text_id
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
        ORDER BY deqs.statement_sql_handle
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
        ORDER BY qsrs.plan_id
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
        ORDER BY qsws.plan_id
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#query_store_wait_stats is empty';
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
        ORDER BY qcs.context_settings_id
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#query_context_settings is empty';
    END;

    IF EXISTS
       (
          SELECT
              1/0
          FROM #troubleshoot_performance AS qcs
       )
    BEGIN
        SELECT
            table_name =
                '#troubleshoot_performance',
            tp.*
        FROM #troubleshoot_performance AS tp
        ORDER BY tp.id
        OPTION(RECOMPILE);
    END;
    ELSE
    BEGIN
        SELECT
            result =
                '#troubleshoot_performance is empty';
    END;

    RETURN;

END;

RETURN;

END;
/*
Final End
*/
GO