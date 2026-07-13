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
 ██████╗ ██╗   ██╗██╗ ██████╗██╗  ██╗██╗███████╗ ██████╗ █████╗  ██████╗██╗  ██╗███████╗
██╔═══██╗██║   ██║██║██╔════╝██║ ██╔╝██║██╔════╝██╔════╝██╔══██╗██╔════╝██║  ██║██╔════╝
██║   ██║██║   ██║██║██║     █████╔╝ ██║█████╗  ██║     ███████║██║     ███████║█████╗
██║▄▄ ██║██║   ██║██║██║     ██╔═██╗ ██║██╔══╝  ██║     ██╔══██║██║     ██╔══██║██╔══╝
╚██████╔╝╚██████╔╝██║╚██████╗██║  ██╗██║███████╗╚██████╗██║  ██║╚██████╗██║  ██║███████╗
 ╚══▀▀═╝  ╚═════╝ ╚═╝ ╚═════╝╚═╝  ╚═╝╚═╝╚══════╝ ╚═════╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚══════╝

sp_QuickieCache: The plan cache companion to sp_QuickieStore.

Copyright 2026 Darling Data, LLC
https://www.erikdarling.com/

For usage and licensing details, run:
EXECUTE sp_QuickieCache
    @help = 1;

For working through errors:
EXECUTE sp_QuickieCache
    @debug = 1;

For support, head over to GitHub:
https://code.erikdarling.com

Uses the Pareto principle to find the vital few queries consuming
disproportionate resources across statements, procedures, functions,
and triggers. Scores across 7 dimensions using PERCENT_RANK and
surfaces queries with impact_score >= @impact_threshold.

Data sources:
 * sys.dm_exec_query_stats      (statements)
 * sys.dm_exec_procedure_stats  (stored procedures)
 * sys.dm_exec_function_stats   (scalar/table-valued functions)
 * sys.dm_exec_trigger_stats    (triggers)

Requires SQL Server 2016 SP1+ for memory grant and spill columns.
*/

IF OBJECT_ID(N'dbo.sp_QuickieCache', N'P') IS NULL
BEGIN
    EXECUTE(N'CREATE PROCEDURE dbo.sp_QuickieCache AS RETURN 138;');
END;
GO

ALTER PROCEDURE
    dbo.sp_QuickieCache
(
    @top bigint = 10, /*candidates per metric dimension before dedup*/
    @sort_order varchar(20) = 'cpu', /*secondary sort after impact_score: cpu, duration, reads, writes, memory, spills, executions*/
    @database_name sysname = NULL, /*filter to a specific database*/
    @start_date datetime = NULL, /*only include plans created after this date*/
    @end_date datetime = NULL, /*only include plans created before this date*/
    @minimum_execution_count bigint = 2, /*noise floor for single-exec queries*/
    @ignore_system_databases bit = 1, /*exclude master, model, msdb, tempdb*/
    @impact_threshold decimal(3, 2) = 0.50, /*minimum impact_score to surface (0.00-1.00)*/
    @find_single_use_plans bit = 0, /*show single-use plans consuming the most memory*/
    @find_duplicate_plans bit = 0, /*show query hashes with multiple cached plans*/
    @debug bit = 0, /*print diagnostics*/
    @help bit = 0, /*display parameter help*/
    @version varchar(30) = NULL OUTPUT, /*OUTPUT; for support*/
    @version_date datetime = NULL OUTPUT /*OUTPUT; for support*/
)
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    SELECT
        @version = '1.7',
        @version_date = '20260701';

    /*
    ╔══════════════════════════════════════════════════╗
    ║  Help section                                    ║
    ╚══════════════════════════════════════════════════╝
    */
    IF @help = 1
    BEGIN
        /*
        Introduction
        */
        SELECT
            introduction =
                'hi, i''m sp_QuickieCache!' UNION ALL
        SELECT 'you got me from https://code.erikdarling.com' UNION ALL
        SELECT 'i analyze the plan cache to find the vital few queries consuming disproportionate resources' UNION ALL
        SELECT 'think of me as the plan cache companion to sp_QuickieStore' UNION ALL
        SELECT 'i score queries across 7 dimensions using Pareto (80/20) analysis' UNION ALL
        SELECT 'from your loving sql server consultant, erik darling: https://erikdarling.com';

        /*
        Parameters
        */
        SELECT
            parameter_name =
                ap.name,
            data_type =
                t.name,
            description =
                CASE ap.name
                    WHEN N'@top'
                    THEN N'candidates per metric dimension before dedup'
                    WHEN N'@sort_order'
                    THEN N'secondary sort after impact_score'
                    WHEN N'@database_name'
                    THEN N'filter to a specific database'
                    WHEN N'@start_date'
                    THEN N'only include plans created after this date'
                    WHEN N'@end_date'
                    THEN N'only include plans created before this date'
                    WHEN N'@minimum_execution_count'
                    THEN N'minimum execution count to include a query'
                    WHEN N'@ignore_system_databases'
                    THEN N'exclude system databases (master, model, msdb, tempdb)'
                    WHEN N'@impact_threshold'
                    THEN N'minimum impact_score to surface in results'
                    WHEN N'@find_single_use_plans'
                    THEN N'show single-use plans consuming the most memory'
                    WHEN N'@find_duplicate_plans'
                    THEN N'show query hashes with multiple cached plans'
                    WHEN N'@debug'
                    THEN N'print diagnostic information'
                    WHEN N'@help'
                    THEN N'how you got here'
                    WHEN N'@version'
                    THEN N'OUTPUT; for support'
                    WHEN N'@version_date'
                    THEN N'OUTPUT; for support'
                    ELSE N''
                END,
            valid_inputs =
                CASE ap.name
                    WHEN N'@top'
                    THEN N'a positive integer'
                    WHEN N'@sort_order'
                    THEN N'cpu, duration, reads, writes, memory, spills, executions'
                    WHEN N'@database_name'
                    THEN N'a valid database name'
                    WHEN N'@start_date'
                    THEN N'a valid datetime'
                    WHEN N'@end_date'
                    THEN N'a valid datetime'
                    WHEN N'@minimum_execution_count'
                    THEN N'a positive integer'
                    WHEN N'@ignore_system_databases'
                    THEN N'0 or 1'
                    WHEN N'@impact_threshold'
                    THEN N'0.00 to 1.00'
                    WHEN N'@find_single_use_plans'
                    THEN N'0 or 1'
                    WHEN N'@find_duplicate_plans'
                    THEN N'0 or 1'
                    WHEN N'@debug'
                    THEN N'0 or 1'
                    WHEN N'@help'
                    THEN N'0 or 1'
                    WHEN N'@version'
                    THEN N'none; OUTPUT'
                    WHEN N'@version_date'
                    THEN N'none; OUTPUT'
                    ELSE N''
                END,
            defaults =
                CASE ap.name
                    WHEN N'@top'
                    THEN N'10'
                    WHEN N'@sort_order'
                    THEN N'cpu'
                    WHEN N'@database_name'
                    THEN N'NULL'
                    WHEN N'@start_date'
                    THEN N'NULL'
                    WHEN N'@end_date'
                    THEN N'NULL'
                    WHEN N'@minimum_execution_count'
                    THEN N'2'
                    WHEN N'@ignore_system_databases'
                    THEN N'1'
                    WHEN N'@impact_threshold'
                    THEN N'0.50'
                    WHEN N'@find_single_use_plans'
                    THEN N'0'
                    WHEN N'@find_duplicate_plans'
                    THEN N'0'
                    WHEN N'@debug'
                    THEN N'0'
                    WHEN N'@help'
                    THEN N'0'
                    WHEN N'@version'
                    THEN N'none; OUTPUT'
                    WHEN N'@version_date'
                    THEN N'none; OUTPUT'
                    ELSE N''
                END
        FROM sys.all_parameters AS ap
        JOIN sys.all_objects AS o
          ON ap.object_id = o.object_id
        JOIN sys.types AS t
          ON  ap.system_type_id = t.system_type_id
          AND ap.user_type_id = t.user_type_id
        WHERE o.name = N'sp_QuickieCache'
        ORDER BY
            ap.parameter_id
        OPTION(MAXDOP 1, RECOMPILE);

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

Copyright 2026 Darling Data, LLC

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

    /*
    ╔══════════════════════════════════════════════════╗
    ║  Version detection                               ║
    ╚══════════════════════════════════════════════════╝
    */
    DECLARE
        @has_spills bit = 0,
        @has_memory_grants bit = 0,
        @database_id integer = NULL;

    IF EXISTS
    (
        SELECT
            1/0
        FROM sys.all_columns AS ac
        WHERE ac.object_id = OBJECT_ID(N'sys.dm_exec_query_stats')
        AND   ac.name = N'total_spills'
    )
    BEGIN
        SELECT
            @has_spills = 1;
    END;

    IF EXISTS
    (
        SELECT
            1/0
        FROM sys.all_columns AS ac
        WHERE ac.object_id = OBJECT_ID(N'sys.dm_exec_query_stats')
        AND   ac.name = N'min_grant_kb'
    )
    BEGIN
        SELECT
            @has_memory_grants = 1;
    END;

    IF @debug = 1
    BEGIN
        DECLARE
            @debug_msg nvarchar(4000) = N'';

        SELECT
            @debug_msg =
                N'Has spill columns: ' + CONVERT(nvarchar(1), @has_spills) +
                N', Has memory grant columns: ' + CONVERT(nvarchar(1), @has_memory_grants);

        RAISERROR(N'%s', 0, 1, @debug_msg) WITH NOWAIT;
    END;

    /*
    ╔══════════════════════════════════════════════════╗
    ║  Parameter validation                            ║
    ╚══════════════════════════════════════════════════╝
    */
    IF @database_name IS NOT NULL
    BEGIN
        SELECT
            @database_id = DB_ID(@database_name);

        IF @database_id IS NULL
        BEGIN
            RAISERROR(N'Database [%s] does not exist on this server.', 16, 1, @database_name) WITH NOWAIT;
            RETURN;
        END;
    END;

    IF @impact_threshold < 0.0
    OR @impact_threshold > 1.0
    BEGIN
        RAISERROR(N'@impact_threshold must be between 0.00 and 1.00.', 16, 1) WITH NOWAIT;
        RETURN;
    END;

    IF @top < 1
    BEGIN
        RAISERROR(N'@top must be at least 1.', 16, 1) WITH NOWAIT;
        RETURN;
    END;

    SELECT
        @sort_order = LOWER(LTRIM(RTRIM(@sort_order)));

    IF @sort_order NOT IN
       (
           'cpu', 'duration', 'reads', 'writes',
           'memory', 'spills', 'executions'
       )
    BEGIN
        RAISERROR(N'@sort_order must be one of: cpu, duration, reads, writes, memory, spills, executions.', 16, 1) WITH NOWAIT;
        RETURN;
    END;

    /*
    ╔══════════════════════════════════════════════════╗
    ║  Single-use plans mode                           ║
    ╚══════════════════════════════════════════════════╝

    Shows the largest single-use plans by cached size,
    sorted by memory consumption descending.
    */
    IF @find_single_use_plans = 1
    BEGIN
        SELECT TOP (@top)
            database_name =
                DB_NAME(CONVERT(integer, pa.value)),
            qs.creation_time,
            qs.last_execution_time,
            plan_age =
                CASE
                    WHEN DATEDIFF(DAY, qs.creation_time, GETDATE()) > 0
                    THEN CONVERT(varchar(10), DATEDIFF(DAY, qs.creation_time, GETDATE())) + 'd '
                    ELSE N''
                END +
                CONVERT(varchar(10), DATEDIFF(HOUR, qs.creation_time, GETDATE()) % 24) + 'h ' +
                CONVERT(varchar(10), DATEDIFF(MINUTE, qs.creation_time, GETDATE()) % 60) + 'm',
            time_since_last_execution =
                CASE
                    WHEN DATEDIFF(DAY, qs.last_execution_time, GETDATE()) > 0
                    THEN CONVERT(varchar(10), DATEDIFF(DAY, qs.last_execution_time, GETDATE())) + 'd '
                    ELSE N''
                END +
                CONVERT(varchar(10), DATEDIFF(HOUR, qs.last_execution_time, GETDATE()) % 24) + 'h ' +
                CONVERT(varchar(10), DATEDIFF(MINUTE, qs.last_execution_time, GETDATE()) % 60) + 'm',
            cached_plan_size_kb =
                cp.size_in_bytes / 1024,
            clear_plan_command =
                N'DBCC FREEPROCCACHE (' +
                CONVERT
                (
                    nvarchar(max),
                    qs.plan_handle,
                    1
                ) + N');',
            query_text =
                (
                    SELECT
                        [processing-instruction(query)] =
                            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                st.text COLLATE Latin1_General_BIN2,
                            NCHAR(31),N'?'),NCHAR(30),N'?'),NCHAR(29),N'?'),NCHAR(28),N'?'),NCHAR(27),N'?'),NCHAR(26),N'?'),NCHAR(25),N'?'),NCHAR(24),N'?'),NCHAR(23),N'?'),NCHAR(22),N'?'),
                            NCHAR(21),N'?'),NCHAR(20),N'?'),NCHAR(19),N'?'),NCHAR(18),N'?'),NCHAR(17),N'?'),NCHAR(16),N'?'),NCHAR(15),N'?'),NCHAR(14),N'?'),NCHAR(12),N'?'),
                            NCHAR(11),N'?'),NCHAR(8),N'?'),NCHAR(7),N'?'),NCHAR(6),N'?'),NCHAR(5),N'?'),NCHAR(4),N'?'),NCHAR(3),N'?'),NCHAR(2),N'?'),NCHAR(1),N'?'),NCHAR(0),N'')
                    FOR
                        XML
                        PATH(N''),
                        TYPE
                ),
            query_plan =
                CASE
                    WHEN TRY_CAST(qp.query_plan AS xml) IS NOT NULL
                    THEN TRY_CAST(qp.query_plan AS xml)
                    WHEN TRY_CAST(qp.query_plan AS xml) IS NULL
                    THEN
                    (
                        SELECT
                            [processing-instruction(query_plan)] =
                                N'-- ' + NCHAR(13) + NCHAR(10) +
                                N'-- This is a huge query plan.' + NCHAR(13) + NCHAR(10) +
                                N'-- Remove the headers and footers, save it as a .sqlplan file, and re-open it.' + NCHAR(13) + NCHAR(10) +
                                NCHAR(13) + NCHAR(10) +
                                REPLACE(qp.query_plan, N'<RelOp', NCHAR(13) + NCHAR(10) + N'<RelOp') +
                                NCHAR(13) + NCHAR(10) COLLATE Latin1_General_Bin2
                        FOR
                            XML
                            PATH(N''),
                            TYPE
                    )
                END,
            qs.query_hash,
            qs.query_plan_hash,
            qs.sql_handle,
            qs.plan_handle
        FROM sys.dm_exec_query_stats AS qs
        JOIN sys.dm_exec_cached_plans AS cp
          ON cp.plan_handle = qs.plan_handle
        CROSS APPLY
        (
            SELECT TOP (1)
                value = pa.value
            FROM sys.dm_exec_plan_attributes(qs.plan_handle) AS pa
            WHERE pa.attribute = N'dbid'
        ) AS pa
        CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
        OUTER APPLY sys.dm_exec_text_query_plan
        (
            qs.plan_handle,
            qs.statement_start_offset,
            qs.statement_end_offset
        ) AS qp
        WHERE qs.execution_count = 1
        AND   (@ignore_system_databases = 0 OR ISNULL(CONVERT(integer, pa.value), 0) NOT IN (1, 2, 3, 4))
        AND   ISNULL(CONVERT(integer, pa.value), 0) < 32761
        AND   (@database_id IS NULL OR CONVERT(integer, pa.value) = @database_id)
        /* Honor @start_date / @end_date the same as the statement /
           procedure / function / trigger paths below — the filters
           were documented as applying to all modes, but this
           @find_single_use_plans branch silently ignored them before. */
        AND   (@start_date IS NULL OR qs.creation_time >= @start_date)
        AND   (@end_date   IS NULL OR qs.creation_time <  @end_date)
        ORDER BY
            cp.size_in_bytes DESC
        OPTION(RECOMPILE, MAXDOP 1);

        RETURN;
    END;

    /*
    ╔══════════════════════════════════════════════════╗
    ║  Duplicate plans mode                            ║
    ╚══════════════════════════════════════════════════╝

    Shows query hashes that have been compiled into
    multiple cached plans, sorted by plan count descending.
    */
    IF @find_duplicate_plans = 1
    BEGIN
        SELECT
            d.database_name,
            d.query_hash,
            d.plan_count,
            d.total_executions,
            d.total_cpu_ms,
            d.total_duration_ms,
            d.total_logical_reads,
            d.total_logical_writes,
            d.total_physical_reads,
            d.total_rows,
            d.min_rows,
            d.max_rows,
            d.total_cached_size_mb,
            d.oldest_plan,
            d.newest_plan,
            sample_query_text =
                (
                    SELECT
                        [processing-instruction(query)] =
                            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                d.sample_query_text COLLATE Latin1_General_BIN2,
                            NCHAR(31),N'?'),NCHAR(30),N'?'),NCHAR(29),N'?'),NCHAR(28),N'?'),NCHAR(27),N'?'),NCHAR(26),N'?'),NCHAR(25),N'?'),NCHAR(24),N'?'),NCHAR(23),N'?'),NCHAR(22),N'?'),
                            NCHAR(21),N'?'),NCHAR(20),N'?'),NCHAR(19),N'?'),NCHAR(18),N'?'),NCHAR(17),N'?'),NCHAR(16),N'?'),NCHAR(15),N'?'),NCHAR(14),N'?'),NCHAR(12),N'?'),
                            NCHAR(11),N'?'),NCHAR(8),N'?'),NCHAR(7),N'?'),NCHAR(6),N'?'),NCHAR(5),N'?'),NCHAR(4),N'?'),NCHAR(3),N'?'),NCHAR(2),N'?'),NCHAR(1),N'?'),NCHAR(0),N'')
                    FOR
                        XML
                        PATH(N''),
                        TYPE
                )
        FROM
        (
            SELECT TOP (@top)
                database_name =
                    DB_NAME(CONVERT(integer, MAX(pa.value))),
                qs.query_hash,
                plan_count =
                    FORMAT(COUNT_BIG(DISTINCT qs.plan_handle), N'N0'),
                total_executions =
                    FORMAT(SUM(qs.execution_count), N'N0'),
                total_cpu_ms =
                    FORMAT(SUM(qs.total_worker_time) / 1000.0, N'N3'),
                total_duration_ms =
                    FORMAT(SUM(qs.total_elapsed_time) / 1000.0, N'N3'),
                total_logical_reads =
                    FORMAT(SUM(qs.total_logical_reads), N'N0'),
                total_logical_writes =
                    FORMAT(SUM(qs.total_logical_writes), N'N0'),
                total_physical_reads =
                    FORMAT(SUM(qs.total_physical_reads), N'N0'),
                total_rows =
                    FORMAT(SUM(qs.total_rows), N'N0'),
                min_rows =
                    FORMAT(MIN(qs.min_rows), N'N0'),
                max_rows =
                    FORMAT(MAX(qs.max_rows), N'N0'),
                total_cached_size_mb =
                    FORMAT(SUM(cp.size_in_bytes) / 1048576.0, N'N2'),
                oldest_plan =
                    MIN(qs.creation_time),
                newest_plan =
                    MAX(qs.creation_time),
                sample_query_text =
                    MAX(st.text),
                sort_plan_count =
                    COUNT_BIG(DISTINCT qs.plan_handle),
                sort_cpu =
                    SUM(qs.total_worker_time)
            FROM sys.dm_exec_query_stats AS qs
            JOIN sys.dm_exec_cached_plans AS cp
              ON cp.plan_handle = qs.plan_handle
            CROSS APPLY
            (
                SELECT TOP (1)
                    value = pa.value
                FROM sys.dm_exec_plan_attributes(qs.plan_handle) AS pa
                WHERE pa.attribute = N'dbid'
            ) AS pa
            CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
            WHERE qs.query_hash <> 0x0000000000000000
            AND   (@ignore_system_databases = 0 OR ISNULL(CONVERT(integer, pa.value), 0) NOT IN (1, 2, 3, 4))
            AND   ISNULL(CONVERT(integer, pa.value), 0) < 32761
            AND   (@database_id IS NULL OR CONVERT(integer, pa.value) = @database_id)
            GROUP BY
                qs.query_hash
            HAVING
                COUNT_BIG(DISTINCT qs.plan_handle) > 1
            ORDER BY
                COUNT_BIG(DISTINCT qs.plan_handle) DESC,
                SUM(qs.total_worker_time) DESC
        ) AS d
        ORDER BY
            d.sort_plan_count DESC,
            d.sort_cpu DESC
        OPTION(RECOMPILE, MAXDOP 1);

        RETURN;
    END;

    /*
    ╔══════════════════════════════════════════════════╗
    ║  Step 0: Materialize the query stats DMV         ║
    ╚══════════════════════════════════════════════════╝

    sys.dm_exec_query_stats is a streaming view over the plan cache,
    not a table. There is nothing in it to seek, so every reference to
    it is a full scan of the cache stores, and the optimizer costs it
    with a fixed row guess no matter how many plans are really cached.

    Every consumer below used to read it directly: one full cache scan
    for the plan age distribution, one for the duplicate hash summary,
    two more for the duplicate plan detail, one for the statement
    aggregation, and then — worst of all — a correlated CROSS APPLY
    back into it to pick each collected hash's sample handles. Nothing
    in the DMV is seekable, so that apply nested-loops: the optimizer
    spools the whole thing and then rewinds, refilters, and re-sorts
    every cached statement once per collected query_hash. The work grew
    with (hashes × cached statements) rather than with the cache.

    Read it once into a temp table instead: one pass over the cache,
    one sys.dm_exec_plan_attributes call per row, and every query below
    then runs against real cardinality and real statistics.

    Only the database filters are applied here, because they are the
    only ones every consumer shares. The query_hash, date, and
    execution count filters stay with the queries that want them; the
    health checks deliberately measure the whole cache rather than the
    filtered slice of it.

    The memory grant and spill columns are the only reason any of this
    needs dynamic SQL. Version-gating them once, here, is what lets
    every query below be static: on versions without them we store
    NULL, so SUM() and MAX() produce the same zeros and NULLs that the
    old version-gated column lists produced by omitting them.
    */
    DECLARE
        @sql nvarchar(max) = N'';

    CREATE TABLE
        #dm_exec_query_stats
    (
        database_id integer NULL,
        query_hash binary(8) NULL,
        plan_handle varbinary(64) NULL,
        sql_handle varbinary(64) NULL,
        statement_start_offset integer NULL,
        statement_end_offset integer NULL,
        execution_count bigint NULL,
        total_worker_time bigint NULL,
        total_elapsed_time bigint NULL,
        total_logical_reads bigint NULL,
        total_logical_writes bigint NULL,
        total_physical_reads bigint NULL,
        total_rows bigint NULL,
        min_rows bigint NULL,
        max_rows bigint NULL,
        min_worker_time bigint NULL,
        max_worker_time bigint NULL,
        min_physical_reads bigint NULL,
        max_physical_reads bigint NULL,
        min_elapsed_time bigint NULL,
        max_elapsed_time bigint NULL,
        max_dop bigint NULL,
        max_grant_kb bigint NULL,
        max_used_grant_kb bigint NULL,
        total_spills bigint NULL,
        max_spills bigint NULL,
        creation_time datetime NULL,
        last_execution_time datetime NULL
    );

    SELECT
        @sql = N'
INSERT
    #dm_exec_query_stats
WITH
    (TABLOCK)
(
    database_id,
    query_hash,
    plan_handle,
    sql_handle,
    statement_start_offset,
    statement_end_offset,
    execution_count,
    total_worker_time,
    total_elapsed_time,
    total_logical_reads,
    total_logical_writes,
    total_physical_reads,
    total_rows,
    min_rows,
    max_rows,
    min_worker_time,
    max_worker_time,
    min_physical_reads,
    max_physical_reads,
    min_elapsed_time,
    max_elapsed_time,
    max_dop,
    max_grant_kb,
    max_used_grant_kb,
    total_spills,
    max_spills,
    creation_time,
    last_execution_time
)
SELECT
    database_id =
        CONVERT(integer, pa.value),
    qs.query_hash,
    qs.plan_handle,
    qs.sql_handle,
    qs.statement_start_offset,
    qs.statement_end_offset,
    qs.execution_count,
    qs.total_worker_time,
    qs.total_elapsed_time,
    qs.total_logical_reads,
    qs.total_logical_writes,
    qs.total_physical_reads,
    qs.total_rows,
    qs.min_rows,
    qs.max_rows,
    qs.min_worker_time,
    qs.max_worker_time,
    qs.min_physical_reads,
    qs.max_physical_reads,
    qs.min_elapsed_time,
    qs.max_elapsed_time,
    qs.max_dop,' +
    CASE
        WHEN @has_memory_grants = 1
        THEN N'
    max_grant_kb = ISNULL(qs.max_grant_kb, 0),
    max_used_grant_kb = ISNULL(qs.max_used_grant_kb, 0),'
        ELSE N'
    max_grant_kb = NULL,
    max_used_grant_kb = NULL,'
    END +
    CASE
        WHEN @has_spills = 1
        THEN N'
    total_spills = ISNULL(qs.total_spills, 0),
    max_spills = ISNULL(qs.max_spills, 0),'
        ELSE N'
    total_spills = NULL,
    max_spills = NULL,'
    END + N'
    qs.creation_time,
    qs.last_execution_time
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY
(
    SELECT TOP (1)
        value = pa.value
    FROM sys.dm_exec_plan_attributes(qs.plan_handle) AS pa
    WHERE pa.attribute = N''dbid''
) AS pa
WHERE ISNULL(CONVERT(integer, pa.value), 0) < 32761' +
    CASE
        WHEN @ignore_system_databases = 1
        THEN N'
AND   ISNULL(CONVERT(integer, pa.value), 0) NOT IN (1, 2, 3, 4)'
        ELSE N''
    END +
    CASE
        WHEN @database_id IS NOT NULL
        THEN N'
AND   CONVERT(integer, pa.value) = @database_id'
        ELSE N''
    END + N'
OPTION(RECOMPILE, MAXDOP 1);';

    IF @debug = 1
    BEGIN
        RAISERROR(N'Plan cache materialization SQL:', 0, 1) WITH NOWAIT;
        RAISERROR(N'%s', 0, 1, @sql) WITH NOWAIT;
    END;

    EXECUTE sys.sp_executesql
        @sql,
        N'@database_id integer',
        @database_id;

    IF @debug = 1
    BEGIN
        DECLARE
            @dmv_rows bigint;

        SELECT
            @dmv_rows = COUNT_BIG(*)
        FROM #dm_exec_query_stats AS s;

        RAISERROR(N'Plan cache rows materialized: %I64d', 0, 1, @dmv_rows) WITH NOWAIT;
    END;

    /*
    ╔══════════════════════════════════════════════════╗
    ║  Plan cache health analysis                      ║
    ╚══════════════════════════════════════════════════╝

    Context-level checks about the overall plan cache state,
    independent of individual query analysis.
    */
    CREATE TABLE
        #plan_cache_health
    (
        id integer NOT NULL IDENTITY(1, 1),
        finding_group nvarchar(100) NOT NULL,
        finding nvarchar(200) NOT NULL,
        database_name sysname NULL,
        priority integer NOT NULL,
        details nvarchar(max) NULL
    );

    /*
    Plan creation time distribution:
    What % of plans were created in the last 24h / 4h / 1h?
    High percentages suggest plan cache instability or memory pressure.

    @total_cached_plans is the true compiled-plan count from
    sys.dm_exec_cached_plans — the number the user actually sees in the
    cache — so the finding reconciles with what they observe. The age
    buckets are computed at plan grain (DISTINCT plan_handle) from
    #dm_exec_query_stats, the only source with per-plan compile
    times. Counting raw query_stats rows (statement grain) inflated
    every number, because a multi-statement plan contributes one row
    per statement; @total_plans is now distinct plans with execution
    stats, the consistent denominator for the recency percentages.

    The database filters were already applied when #dm_exec_query_stats
    was populated, so there is nothing left to filter here. The date
    filters are deliberately NOT applied: this measures the health of
    the whole cache, not of the slice the caller asked to analyze.
    */
    DECLARE
        @total_plans bigint = 0,
        @total_cached_plans bigint = 0,
        @plans_24h bigint = 0,
        @plans_4h bigint = 0,
        @plans_1h bigint = 0,
        @pct_24h decimal(5, 2) = 0,
        @pct_4h decimal(5, 2) = 0,
        @pct_1h decimal(5, 2) = 0,
        @oldest_plan_date datetime = NULL;

    SELECT
        @total_cached_plans = COUNT_BIG(*)
    FROM sys.dm_exec_cached_plans AS cp
    CROSS APPLY
    (
        SELECT TOP (1)
            value = pa.value
        FROM sys.dm_exec_plan_attributes(cp.plan_handle) AS pa
        WHERE pa.attribute = N'dbid'
    ) AS pa
    WHERE cp.cacheobjtype = N'Compiled Plan'
    AND   pa.value IS NOT NULL
    AND   (@ignore_system_databases = 0 OR CONVERT(integer, pa.value) NOT IN (1, 2, 3, 4))
    AND   CONVERT(integer, pa.value) < 32761
    AND   (@database_id IS NULL OR CONVERT(integer, pa.value) = @database_id)
    OPTION(RECOMPILE);

    /*
    The buckets are counted by first collapsing the statement-grained
    rows down to one row per plan, then adding up the plans that fall in
    each window.

    The obvious way to write this is
    COUNT_BIG(DISTINCT CASE WHEN ... THEN plan_handle END), and that is
    what it used to be. Every plan OUTSIDE the window makes that CASE
    return NULL, COUNT ignores it, and SQL Server says so: "Null value
    is eliminated by an aggregate or other SET operation" — printed on
    every run against any cache holding plans older than an hour, which
    is every real cache. Counting 1s and 0s over a pre-deduplicated set
    gets the same answers without ever handing an aggregate a NULL.

    Bucket on the NEWEST compile, and ONLY on the newest compile.

    creation_time is a property of the STATEMENT, not of the plan: when
    a single statement inside a batch recompiles, it restamps its own
    creation_time (and its own plan_generation_num) while the batch
    keeps its plan_handle. So rows sharing a plan_handle routinely carry
    different creation_times — days apart, on a cache with any recompile
    activity at all.

    That makes the choice of MIN vs MAX load-bearing rather than
    cosmetic. COUNT_BIG(DISTINCT CASE ...) counted a plan as recent if
    ANY of its rows landed in the window, which is MAX semantics.
    Collapsing on MIN instead would ask whether the plan's OLDEST
    statement is recent, silently under-reporting every bucket and
    letting a cache that churns through statement-level recompiles —
    exactly what this check exists to catch — report as healthy.

    @oldest_plan_date still wants the true minimum, so the derived table
    carries both ends.
    */
    SELECT
        @total_plans = COUNT_BIG(*),
        @plans_24h =
            ISNULL
            (
                SUM
                (
                    CASE
                        WHEN DATEDIFF(HOUR, p.newest_compile, GETDATE()) <= 24
                        THEN 1
                        ELSE 0
                    END
                ),
                0
            ),
        @plans_4h =
            ISNULL
            (
                SUM
                (
                    CASE
                        WHEN DATEDIFF(HOUR, p.newest_compile, GETDATE()) <= 4
                        THEN 1
                        ELSE 0
                    END
                ),
                0
            ),
        @plans_1h =
            ISNULL
            (
                SUM
                (
                    CASE
                        WHEN DATEDIFF(HOUR, p.newest_compile, GETDATE()) <= 1
                        THEN 1
                        ELSE 0
                    END
                ),
                0
            ),
        @oldest_plan_date = MIN(p.oldest_compile)
    FROM
    (
        SELECT
            s.plan_handle,
            newest_compile = MAX(s.creation_time),
            oldest_compile = MIN(s.creation_time)
        FROM #dm_exec_query_stats AS s
        GROUP BY
            s.plan_handle
    ) AS p
    OPTION(RECOMPILE);

    IF @total_plans > 0
    BEGIN
        SELECT
            @pct_24h = @plans_24h * 100.0 / @total_plans,
            @pct_4h = @plans_4h * 100.0 / @total_plans,
            @pct_1h = @plans_1h * 100.0 / @total_plans;
    END;

    IF @pct_24h > 75
    BEGIN
        INSERT
            #plan_cache_health
        (
            finding_group,
            finding,
            priority,
            details
        )
        VALUES
        (
            N'Plan Cache Instability',
            N'Most plans are recent',
            1,
            N'Of ' + FORMAT(@total_cached_plans, N'N0') +
            N' cached compiled plans, ' + FORMAT(@total_plans, N'N0') +
            N' have execution stats; of those, ' +
            CONVERT(nvarchar(10), @pct_24h) + N'% were compiled in the last 24 hours, ' +
            CONVERT(nvarchar(10), @pct_4h) + N'% in the last 4 hours, ' +
            CONVERT(nvarchar(10), @pct_1h) + N'% in the last 1 hour. ' +
            N'This may indicate memory pressure, frequent recompiles, or plan cache flushes. ' +
            N'Oldest cached plan: ' + CONVERT(nvarchar(30), @oldest_plan_date, 120) + N'.'
        );
    END;
    ELSE
    BEGIN
        INSERT
            #plan_cache_health
        (
            finding_group,
            finding,
            priority,
            details
        )
        VALUES
        (
            N'Plan Cache Stability',
            N'Plan age distribution looks healthy',
            254,
            N'Of ' + FORMAT(@total_cached_plans, N'N0') +
            N' cached compiled plans, ' + FORMAT(@total_plans, N'N0') +
            N' have execution stats; of those, ' +
            CONVERT(nvarchar(10), @pct_24h) + N'% were compiled in the last 24 hours, ' +
            CONVERT(nvarchar(10), @pct_4h) + N'% in the last 4 hours, ' +
            CONVERT(nvarchar(10), @pct_1h) + N'% in the last 1 hour. ' +
            N'Oldest cached plan: ' + CONVERT(nvarchar(30), @oldest_plan_date, 120) + N'.'
        );
    END;

    /*
    Single-use plan bloat per database:
    A high percentage of single-use adhoc/prepared plans suggests an
    unparameterized ad hoc workload that bloats the plan cache and may
    benefit from Forced Parameterization. Only surfaces databases where
    single-use plans exceed 10% of that database's cached compiled plans.

    Sourced from sys.dm_exec_cached_plans on purpose, NOT
    sys.dm_exec_query_stats. query_stats is statement-grained and only
    contains plans that have executed and are still cached, so its
    per-database counts are a small, misleading slice of the cache
    (e.g. "27 of 27 plans" on a server whose cache actually holds
    100k+ plans). dm_exec_cached_plans IS the plan cache the user sees,
    and usecounts = 1 on an Adhoc/Prepared compiled plan is the
    canonical single-use plan signal. total_count is every cached
    compiled plan for the database (the denominator the user counts),
    so the percentage reconciles with what they observe.
    */
    INSERT
        #plan_cache_health
    (
        finding_group,
        finding,
        database_name,
        priority,
        details
    )
    SELECT TOP (5)
        finding_group =
            CASE
                WHEN x.single_use_pct > 75
                THEN N'Single-Use Plan Bloat'
                ELSE N'Single-Use Plans'
            END,
        finding =
            CASE
                WHEN x.single_use_pct > 75
                THEN N'Excessive single-use plans in cache'
                ELSE N'Notable single-use plan percentage'
            END,
        x.database_name,
        priority =
            CASE
                WHEN x.single_use_pct > 75
                THEN 1
                ELSE 254
            END,
        details =
            FORMAT(x.single_use_count, N'N0') +
            N' of ' + FORMAT(x.total_count, N'N0') +
            N' cached plans (' +
            CONVERT(nvarchar(10), x.single_use_pct) +
            N'%) are single-use adhoc or prepared plans. Consider Forced Parameterization if these are unparameterized ad hoc queries.'
    FROM
    (
        SELECT
            database_name =
                DB_NAME(CONVERT(integer, pa.value)),
            total_count =
                COUNT_BIG(*),
            single_use_count =
                SUM
                (
                    CASE
                        WHEN cp.usecounts = 1
                        AND  cp.objtype IN (N'Adhoc', N'Prepared')
                        THEN 1
                        ELSE 0
                    END
                ),
            single_use_pct =
                CONVERT
                (
                    decimal(5, 2),
                    SUM
                    (
                        CASE
                            WHEN cp.usecounts = 1
                            AND  cp.objtype IN (N'Adhoc', N'Prepared')
                            THEN 1
                            ELSE 0
                        END
                    ) * 100.0 / COUNT_BIG(*)
                )
        FROM sys.dm_exec_cached_plans AS cp
        CROSS APPLY
        (
            SELECT TOP (1)
                value = pa.value
            FROM sys.dm_exec_plan_attributes(cp.plan_handle) AS pa
            WHERE pa.attribute = N'dbid'
        ) AS pa
        WHERE cp.cacheobjtype = N'Compiled Plan'
        AND   pa.value IS NOT NULL
        AND   (@ignore_system_databases = 0 OR CONVERT(integer, pa.value) NOT IN (1, 2, 3, 4))
        AND   CONVERT(integer, pa.value) < 32761
        AND   (@database_id IS NULL OR CONVERT(integer, pa.value) = @database_id)
        GROUP BY
            pa.value
    ) AS x
    WHERE x.single_use_pct > 10
    ORDER BY
        x.single_use_count DESC
    OPTION(RECOMPILE);

    /*
    Duplicate plan hashes:
    Same query_hash compiled into multiple plans suggests
    SET option differences or parameterization issues.
    */
    DECLARE
        @duplicate_hashes bigint = 0,
        @duplicate_plans bigint = 0,
        @pct_duplicate decimal(5, 2) = 0;

    SELECT
        @duplicate_hashes = COUNT_BIG(*),
        @duplicate_plans = SUM(x.plan_count)
    FROM
    (
        SELECT
            plan_count = COUNT_BIG(DISTINCT s.plan_handle)
        FROM #dm_exec_query_stats AS s
        WHERE s.query_hash <> 0x0000000000000000
        GROUP BY
            s.query_hash
        HAVING
            COUNT_BIG(DISTINCT s.plan_handle) > 5
    ) AS x
    OPTION(RECOMPILE);

    IF @total_plans > 0
    AND @duplicate_plans > 0
    BEGIN
        SELECT
            @pct_duplicate = @duplicate_plans * 100.0 / @total_plans;
    END;

    IF @pct_duplicate > 5
    BEGIN
        INSERT
            #plan_cache_health
        (
            finding_group,
            finding,
            database_name,
            priority,
            details
        )
        SELECT TOP (5)
            finding_group =
                CASE
                    WHEN @pct_duplicate > 75
                    THEN N'Severe Plan Duplication'
                    ELSE N'Plan Duplication'
                END,
            finding =
                CASE
                    WHEN @pct_duplicate > 75
                    THEN N'Massive duplicate plan compilation'
                    ELSE N'Notable duplicate plan compilation'
                END,
            database_name = DB_NAME(s2.database_id),
            priority =
                CASE
                    WHEN @pct_duplicate > 75
                    THEN 1
                    ELSE 254
                END,
            details =
                FORMAT(COUNT_BIG(DISTINCT s2.query_hash), N'N0') +
                N' query hashes with 5+ plans, totaling ' +
                FORMAT(COUNT_BIG(DISTINCT s2.plan_handle), N'N0') + N' plans. ' +
                N'Most likely unparameterized queries. SET option differences between sessions can also cause this. Consider Forced Parameterization.'
        /*
        Both sides now read the same filtered set, so the hashes counted
        here are the same hashes @duplicate_hashes and @duplicate_plans
        were computed from. The inner query used to scan the DMV with no
        database predicate at all while the outer one was filtered, which
        let a hash qualify on the strength of plans in databases the
        caller had excluded.
        */
        FROM
        (
            SELECT
                s.query_hash
            FROM #dm_exec_query_stats AS s
            WHERE s.query_hash <> 0x0000000000000000
            GROUP BY
                s.query_hash
            HAVING
                COUNT_BIG(DISTINCT s.plan_handle) > 5
        ) AS x
        JOIN #dm_exec_query_stats AS s2
          ON s2.query_hash = x.query_hash
        WHERE s2.database_id IS NOT NULL
        GROUP BY
            s2.database_id
        ORDER BY
            COUNT_BIG(DISTINCT s2.plan_handle) DESC
        OPTION(RECOMPILE);
    END;

    /*
    USERSTORE_TOKENPERM memory pressure:
    When the token/permission cache consumes >= 10% of buffer pool,
    it can starve the plan cache and cause churn.
    */
    DECLARE
        @buffer_pool_mb decimal(18, 2) = 0,
        @tokenperm_mb decimal(18, 2) = 0;

    SELECT
        @buffer_pool_mb =
            SUM
            (
                CASE
                    WHEN mc.type = N'MEMORYCLERK_SQLBUFFERPOOL'
                    THEN mc.pages_kb / 1024.0
                    ELSE 0
                END
            ),
        @tokenperm_mb =
            SUM
            (
                CASE
                    WHEN mc.type = N'USERSTORE_TOKENPERM'
                    THEN mc.pages_kb / 1024.0
                    ELSE 0
                END
            )
    FROM sys.dm_os_memory_clerks AS mc
    WHERE mc.type IN (N'MEMORYCLERK_SQLBUFFERPOOL', N'USERSTORE_TOKENPERM')
    OPTION(RECOMPILE);

    IF @buffer_pool_mb > 0
    AND @tokenperm_mb > 2048
    AND (@tokenperm_mb / @buffer_pool_mb) * 100.0 >= 10.0
    BEGIN
        INSERT
            #plan_cache_health
        (
            finding_group,
            finding,
            priority,
            details
        )
        VALUES
        (
            N'Memory Pressure',
            N'Large USERSTORE_TOKENPERM cache',
            10,
            N'USERSTORE_TOKENPERM is ' +
            FORMAT(CONVERT(bigint, @tokenperm_mb), N'N0') +
            N' MB (' +
            CONVERT
            (
                nvarchar(10),
                CONVERT(decimal(5, 1), (@tokenperm_mb / @buffer_pool_mb) * 100.0)
            ) +
            N'% of the ' +
            FORMAT(CONVERT(bigint, @buffer_pool_mb), N'N0') +
            N' MB buffer pool). ' +
            N'This can starve the plan cache and cause plan churn. ' +
            N'See KB4053569 or consider trace flag 4618/4610.'
        );
    END;

    IF @debug = 1
    BEGIN
        SELECT
            @debug_msg =
                N'Plan cache health: ' + CONVERT(nvarchar(20), @total_cached_plans) +
                N' cached compiled plans, ' + CONVERT(nvarchar(20), @total_plans) +
                N' with stats, ' + CONVERT(nvarchar(10), @pct_24h) +
                N'% < 24h, ' + CONVERT(nvarchar(10), @pct_4h) +
                N'% < 4h, ' + CONVERT(nvarchar(10), @pct_1h) + N'% < 1h';
        RAISERROR(N'%s', 0, 1, @debug_msg) WITH NOWAIT;

        SELECT
            @debug_msg =
                N'Duplicates: ' + CONVERT(nvarchar(10), @pct_duplicate) + N'%';
        RAISERROR(N'%s', 0, 1, @debug_msg) WITH NOWAIT;

        SELECT
            @debug_msg =
                N'TokenPerm: ' + CONVERT(nvarchar(20), @tokenperm_mb) +
                N' MB, Buffer pool: ' + CONVERT(nvarchar(20), @buffer_pool_mb) + N' MB';
        RAISERROR(N'%s', 0, 1, @debug_msg) WITH NOWAIT;
    END;

    /*
    ╔══════════════════════════════════════════════════╗
    ║  Create staging table                            ║
    ╚══════════════════════════════════════════════════╝

    All four stat DMVs feed into this single table.
    Statements group by query_hash; procedures, functions,
    and triggers group by database_id + object_id.
    */
    CREATE TABLE
        #query_stats
    (
        id integer NOT NULL IDENTITY(1, 1),
        query_type varchar(20) NOT NULL,
        database_name sysname NULL,
        object_name sysname NULL,
        query_hash binary(8) NULL,
        plan_count integer NOT NULL DEFAULT 0,
        total_executions bigint NOT NULL DEFAULT 0,
        total_cpu_ms decimal(38, 2) NOT NULL DEFAULT 0,
        total_duration_ms decimal(38, 2) NOT NULL DEFAULT 0,
        total_logical_reads bigint NOT NULL DEFAULT 0,
        total_logical_writes bigint NOT NULL DEFAULT 0,
        total_physical_reads bigint NOT NULL DEFAULT 0,
        total_rows bigint NOT NULL DEFAULT 0,
        total_grant_mb decimal(38, 2) NOT NULL DEFAULT 0,
        total_used_grant_mb decimal(38, 2) NOT NULL DEFAULT 0,
        total_spills bigint NOT NULL DEFAULT 0,
        max_grant_mb decimal(38, 2) NULL,
        max_used_grant_mb decimal(38, 2) NULL,
        max_spills bigint NULL,
        max_dop integer NULL,
        min_rows bigint NULL,
        max_rows bigint NULL,
        min_cpu_ms decimal(38, 2) NULL,
        max_cpu_ms decimal(38, 2) NULL,
        min_physical_reads bigint NULL,
        max_physical_reads bigint NULL,
        min_duration_ms decimal(38, 2) NULL,
        max_duration_ms decimal(38, 2) NULL,
        oldest_plan_creation datetime NULL,
        newest_plan_creation datetime NULL,
        last_execution_time datetime NULL,
        sample_sql_handle varbinary(64) NULL,
        sample_plan_handle varbinary(64) NULL,
        sample_statement_start integer NULL,
        sample_statement_end integer NULL
    );

    /*
    ╔══════════════════════════════════════════════════╗
    ║  Step 1a: Collect statement-level stats          ║
    ║  (#dm_exec_query_stats, grouped by hash)         ║
    ╚══════════════════════════════════════════════════╝

    Two things happen here, and they are deliberately kept apart.

    "totals" rolls the hash group up. "winner" picks the single plan
    that represents it — the most-executed one — and that one row
    supplies the database, both handles, and both offsets, so the text,
    the offsets, and the plan always describe the same plan instead of
    being MAX()'d independently out of different ones.

    The winner could instead be folded into the aggregate as
    MAX(CASE WHEN n = 1 THEN ... END). Don't. Every row that isn't the
    winner feeds a NULL into those MAX()es, and SQL Server answers with
    "Null value is eliminated by an aggregate or other SET operation" on
    every run. Joining to the winner asks the same question without ever
    handing an aggregate a NULL. The object path in Step 1b does the
    same thing for the same reason.

    Reading #dm_exec_query_stats twice — once for totals, once for the
    winner — is safe precisely BECAUSE it is a temp table. It holds
    still between the two reads. Do not repoint either side of this join
    at sys.dm_exec_query_stats directly: a DMV gets no statement-level
    snapshot, so the two sides would see two different plan caches and
    the inner join would silently drop any hash that got evicted in
    between.

    This all used to be a second pass — an UPDATE that CROSS APPLY'd
    sys.dm_exec_query_stats per collected query_hash to go find those
    handles. Nothing in the DMV is seekable, so the apply nested-loops
    over it: spool the whole cache, then rewind, refilter, and re-sort
    it once per hash. It also carried none of the database or date
    predicates, so with @database_name set it could hand back the
    handles of a plan from a database the caller had explicitly
    filtered out, and then show its text and its plan.
    */
    INSERT
        #query_stats
    WITH
        (TABLOCK)
    (
        query_type,
        database_name,
        query_hash,
        plan_count,
        total_executions,
        total_cpu_ms,
        total_duration_ms,
        total_logical_reads,
        total_logical_writes,
        total_physical_reads,
        total_rows,
        total_grant_mb,
        total_used_grant_mb,
        total_spills,
        max_grant_mb,
        max_used_grant_mb,
        max_spills,
        max_dop,
        min_rows,
        max_rows,
        min_cpu_ms,
        max_cpu_ms,
        min_physical_reads,
        max_physical_reads,
        min_duration_ms,
        max_duration_ms,
        oldest_plan_creation,
        newest_plan_creation,
        last_execution_time,
        sample_sql_handle,
        sample_plan_handle,
        sample_statement_start,
        sample_statement_end
    )
    SELECT
        query_type = 'Statement',
        database_name = DB_NAME(winner.database_id),
        query_hash = totals.query_hash,
        plan_count = totals.plan_count,
        total_executions = totals.total_executions,
        total_cpu_ms = totals.total_cpu_ms,
        total_duration_ms = totals.total_duration_ms,
        total_logical_reads = totals.total_logical_reads,
        total_logical_writes = totals.total_logical_writes,
        total_physical_reads = totals.total_physical_reads,
        total_rows = totals.total_rows,
        total_grant_mb = totals.total_grant_mb,
        total_used_grant_mb = totals.total_used_grant_mb,
        total_spills = totals.total_spills,
        max_grant_mb = totals.max_grant_mb,
        max_used_grant_mb = totals.max_used_grant_mb,
        max_spills = totals.max_spills,
        max_dop = totals.max_dop,
        min_rows = totals.min_rows,
        max_rows = totals.max_rows,
        min_cpu_ms = totals.min_cpu_ms,
        max_cpu_ms = totals.max_cpu_ms,
        min_physical_reads = totals.min_physical_reads,
        max_physical_reads = totals.max_physical_reads,
        min_duration_ms = totals.min_duration_ms,
        max_duration_ms = totals.max_duration_ms,
        oldest_plan_creation = totals.oldest_plan_creation,
        newest_plan_creation = totals.newest_plan_creation,
        last_execution_time = totals.last_execution_time,
        sample_sql_handle = winner.sql_handle,
        sample_plan_handle = winner.plan_handle,
        sample_statement_start = winner.statement_start_offset,
        sample_statement_end = winner.statement_end_offset
    FROM
    (
        SELECT
            s.query_hash,
            plan_count = COUNT_BIG(DISTINCT s.plan_handle),
            total_executions = SUM(s.execution_count),
            total_cpu_ms = SUM(s.total_worker_time) / 1000.0,
            total_duration_ms = SUM(s.total_elapsed_time) / 1000.0,
            total_logical_reads = SUM(s.total_logical_reads),
            total_logical_writes = SUM(s.total_logical_writes),
            total_physical_reads = SUM(s.total_physical_reads),
            total_rows = SUM(s.total_rows),
            /*
            On versions without the memory grant and spill columns these
            are NULL for every row, and the CASE hands back the same 0s
            and NULLs the old version-gated column lists produced by
            omitting them: the totals are NOT NULL columns that defaulted
            to 0, the maxes are nullable and stayed NULL.

            The ISNULL inside each aggregate is not decoration. Without
            it, SUM() and MAX() would skip NULLs on those versions and
            SQL Server would warn about it on every run. Feeding them
            zeros keeps them quiet, and the CASE — not the aggregate —
            decides whether the answer is a value or a NULL.
            */
            total_grant_mb =
                CASE
                    WHEN @has_memory_grants = 1
                    THEN SUM(ISNULL(s.max_grant_kb, 0)) / 1024.0
                    ELSE 0
                END,
            total_used_grant_mb =
                CASE
                    WHEN @has_memory_grants = 1
                    THEN SUM(ISNULL(s.max_used_grant_kb, 0)) / 1024.0
                    ELSE 0
                END,
            total_spills =
                CASE
                    WHEN @has_spills = 1
                    THEN SUM(ISNULL(s.total_spills, 0))
                    ELSE 0
                END,
            max_grant_mb =
                CASE
                    WHEN @has_memory_grants = 1
                    THEN MAX(ISNULL(s.max_grant_kb, 0)) / 1024.0
                END,
            max_used_grant_mb =
                CASE
                    WHEN @has_memory_grants = 1
                    THEN MAX(ISNULL(s.max_used_grant_kb, 0)) / 1024.0
                END,
            max_spills =
                CASE
                    WHEN @has_spills = 1
                    THEN MAX(ISNULL(s.max_spills, 0))
                END,
            max_dop = MAX(s.max_dop),
            min_rows = MIN(s.min_rows),
            max_rows = MAX(s.max_rows),
            min_cpu_ms = MIN(s.min_worker_time) / 1000.0,
            max_cpu_ms = MAX(s.max_worker_time) / 1000.0,
            min_physical_reads = MIN(s.min_physical_reads),
            max_physical_reads = MAX(s.max_physical_reads),
            min_duration_ms = MIN(s.min_elapsed_time) / 1000.0,
            max_duration_ms = MAX(s.max_elapsed_time) / 1000.0,
            oldest_plan_creation = MIN(s.creation_time),
            newest_plan_creation = MAX(s.creation_time),
            last_execution_time = MAX(s.last_execution_time)
        FROM #dm_exec_query_stats AS s
        /* @minimum_execution_count is enforced ONLY in the HAVING
           SUM(execution_count) below — applying it per-row here
           filtered out individual plans whose single-plan execution_count
           was below the floor but whose group total was above it
           (think: a recompile-heavy query with many plans each run a
           few times that add up to a lot). Same reasoning applies to
           the procedure / function / trigger paths further down.
           The database filters were already applied when
           #dm_exec_query_stats was populated. */
        WHERE s.query_hash <> 0x0000000000000000
        AND   s.creation_time >= ISNULL(@start_date, s.creation_time)
        AND   s.creation_time < ISNULL(@end_date, DATEADD(DAY, 1, s.creation_time))
        GROUP BY
            s.query_hash
        HAVING
            SUM(s.execution_count) >= @minimum_execution_count
    ) AS totals
    JOIN
    (
        SELECT
            s.query_hash,
            s.database_id,
            s.sql_handle,
            s.plan_handle,
            s.statement_start_offset,
            s.statement_end_offset,
            /*
            Ranked after the WHERE clause, so the winner is the most
            executed plan among the rows the caller actually asked for,
            not the most executed plan in the entire cache. The filters
            below have to stay in step with the ones above, or the winner
            could come from a row the totals never counted.
            */
            n =
                ROW_NUMBER() OVER
                (
                    PARTITION BY
                        s.query_hash
                    ORDER BY
                        s.execution_count DESC
                )
        FROM #dm_exec_query_stats AS s
        WHERE s.query_hash <> 0x0000000000000000
        AND   s.creation_time >= ISNULL(@start_date, s.creation_time)
        AND   s.creation_time < ISNULL(@end_date, DATEADD(DAY, 1, s.creation_time))
    ) AS winner
      ON  winner.query_hash = totals.query_hash
      AND winner.n = 1
    OPTION(RECOMPILE, MAXDOP 1);

    IF @debug = 1
    BEGIN
        DECLARE
            @stmt_count bigint;

        SELECT
            @stmt_count = COUNT_BIG(*)
        FROM #query_stats AS qs
        WHERE qs.query_type = 'Statement';

        RAISERROR(N'Statement query_hash groups collected: %I64d', 0, 1, @stmt_count) WITH NOWAIT;
    END;

    /*
    Link statement-level rows to their parent procedure
    via sql_handle in dm_exec_procedure_stats.
    */
    UPDATE
        qs
    SET
        qs.object_name =
            QUOTENAME(OBJECT_SCHEMA_NAME(ps.object_id, ps.database_id)) +
            N'.' +
            QUOTENAME(OBJECT_NAME(ps.object_id, ps.database_id))
    FROM #query_stats AS qs
    JOIN sys.dm_exec_procedure_stats AS ps
      ON ps.sql_handle = qs.sample_sql_handle
    WHERE qs.query_type = 'Statement'
    AND   qs.object_name IS NULL
    OPTION(RECOMPILE);

    /*
    ╔══════════════════════════════════════════════════╗
    ║  Step 1b: Collect object-level stats             ║
    ║  (procedures, functions, and triggers)           ║
    ╚══════════════════════════════════════════════════╝

    These three DMVs are materialized for the same reason
    sys.dm_exec_query_stats is, plus one that is specific to the
    totals + winner shape below.

    A DMV is not a table and gets no statement-level snapshot. Reading
    one twice in a single statement is two independent reads of live
    plan cache memory, and the optimizer does exactly that here: the
    totals side and the winner side each get their own scan operator.
    If a plan is evicted between the two reads — on a churning cache,
    which is the situation this proc exists to diagnose — the object
    appears in totals, is missing from winner, and the inner join drops
    it from the report entirely. No error, no warning, just a
    stored procedure that quietly stops existing.

    A temp table can be read twice safely, because it holds still. So
    read each DMV exactly once, up front, and let both sides of the
    join work from the same snapshot.

    The three DMVs are shaped identically across every column used here,
    so one staging table and one aggregate serve all of them; query_type
    keeps them apart. The row filters are applied on the way in, which
    is also why the totals and winner queries below need no WHERE clause
    of their own — there is no pair of predicate lists that can drift
    apart.
    */
    CREATE TABLE
        #dm_exec_object_stats
    (
        query_type varchar(20) NOT NULL,
        database_id integer NULL,
        object_id integer NULL,
        plan_handle varbinary(64) NULL,
        sql_handle varbinary(64) NULL,
        execution_count bigint NULL,
        total_worker_time bigint NULL,
        total_elapsed_time bigint NULL,
        total_logical_reads bigint NULL,
        total_logical_writes bigint NULL,
        total_physical_reads bigint NULL,
        cached_time datetime NULL,
        last_execution_time datetime NULL
    );

    /*
    @minimum_execution_count is enforced ONLY in the HAVING
    SUM(execution_count) below, never as a per-row filter here —
    applying it per row would drop individual plans whose single-plan
    execution_count was below the floor but whose group total was above
    it (a recompile-heavy object with many plans, each run a few times,
    that add up to a lot). Same reasoning as the statement path.
    */
    INSERT
        #dm_exec_object_stats
    WITH
        (TABLOCK)
    (
        query_type,
        database_id,
        object_id,
        plan_handle,
        sql_handle,
        execution_count,
        total_worker_time,
        total_elapsed_time,
        total_logical_reads,
        total_logical_writes,
        total_physical_reads,
        cached_time,
        last_execution_time
    )
    SELECT
        query_type = 'Procedure',
        ps.database_id,
        ps.object_id,
        ps.plan_handle,
        ps.sql_handle,
        ps.execution_count,
        ps.total_worker_time,
        ps.total_elapsed_time,
        ps.total_logical_reads,
        ps.total_logical_writes,
        ps.total_physical_reads,
        ps.cached_time,
        ps.last_execution_time
    FROM sys.dm_exec_procedure_stats AS ps
    WHERE ps.database_id > CASE WHEN @ignore_system_databases = 1 THEN 4 ELSE 0 END
    AND   ps.database_id < 32761
    AND   ps.database_id = ISNULL(@database_id, ps.database_id)
    AND   ps.cached_time >= ISNULL(@start_date, ps.cached_time)
    AND   ps.cached_time < ISNULL(@end_date, DATEADD(DAY, 1, ps.cached_time))
    OPTION(RECOMPILE, MAXDOP 1);

    /*
    sys.dm_exec_function_stats is available starting SQL Server 2016, so
    it has to be referenced from dynamic SQL to keep this procedure
    compiling on older builds.
    */
    IF EXISTS
    (
        SELECT
            1/0
        FROM sys.all_objects AS ao
        WHERE ao.name = N'dm_exec_function_stats'
        AND   ao.schema_id = SCHEMA_ID(N'sys')
    )
    BEGIN
        SELECT
            @sql = N'
INSERT
    #dm_exec_object_stats
WITH
    (TABLOCK)
(
    query_type,
    database_id,
    object_id,
    plan_handle,
    sql_handle,
    execution_count,
    total_worker_time,
    total_elapsed_time,
    total_logical_reads,
    total_logical_writes,
    total_physical_reads,
    cached_time,
    last_execution_time
)
SELECT
    query_type = ''Function'',
    fs.database_id,
    fs.object_id,
    fs.plan_handle,
    fs.sql_handle,
    fs.execution_count,
    fs.total_worker_time,
    fs.total_elapsed_time,
    fs.total_logical_reads,
    fs.total_logical_writes,
    fs.total_physical_reads,
    fs.cached_time,
    fs.last_execution_time
FROM sys.dm_exec_function_stats AS fs
WHERE fs.database_id > CASE WHEN @ignore_system_databases = 1 THEN 4 ELSE 0 END
AND   fs.database_id < 32761
AND   fs.database_id = ISNULL(@database_id, fs.database_id)
AND   fs.cached_time >= ISNULL(@start_date, fs.cached_time)
AND   fs.cached_time < ISNULL(@end_date, DATEADD(DAY, 1, fs.cached_time))
OPTION(RECOMPILE, MAXDOP 1);';

        IF @debug = 1
        BEGIN
            RAISERROR(N'Function stats materialization SQL:', 0, 1) WITH NOWAIT;
            RAISERROR(N'%s', 0, 1, @sql) WITH NOWAIT;
        END;

        EXECUTE sys.sp_executesql
            @sql,
            N'@database_id integer, @ignore_system_databases bit, @start_date datetime, @end_date datetime',
            @database_id,
            @ignore_system_databases,
            @start_date,
            @end_date;
    END;

    INSERT
        #dm_exec_object_stats
    WITH
        (TABLOCK)
    (
        query_type,
        database_id,
        object_id,
        plan_handle,
        sql_handle,
        execution_count,
        total_worker_time,
        total_elapsed_time,
        total_logical_reads,
        total_logical_writes,
        total_physical_reads,
        cached_time,
        last_execution_time
    )
    SELECT
        query_type = 'Trigger',
        ts.database_id,
        ts.object_id,
        ts.plan_handle,
        ts.sql_handle,
        ts.execution_count,
        ts.total_worker_time,
        ts.total_elapsed_time,
        ts.total_logical_reads,
        ts.total_logical_writes,
        ts.total_physical_reads,
        ts.cached_time,
        ts.last_execution_time
    FROM sys.dm_exec_trigger_stats AS ts
    WHERE ts.database_id > CASE WHEN @ignore_system_databases = 1 THEN 4 ELSE 0 END
    AND   ts.database_id < 32761
    AND   ts.database_id = ISNULL(@database_id, ts.database_id)
    AND   ts.cached_time >= ISNULL(@start_date, ts.cached_time)
    AND   ts.cached_time < ISNULL(@end_date, DATEADD(DAY, 1, ts.cached_time))
    OPTION(RECOMPILE, MAXDOP 1);

    /*
    One aggregate for all three object types. Same shape as the
    statement path: totals rolls the object up, winner picks the
    most-executed plan to represent it, and both handles come from that
    one row so the text and the plan always describe the same plan.
    */
    INSERT
        #query_stats
    WITH
        (TABLOCK)
    (
        query_type,
        database_name,
        object_name,
        plan_count,
        total_executions,
        total_cpu_ms,
        total_duration_ms,
        total_logical_reads,
        total_logical_writes,
        total_physical_reads,
        oldest_plan_creation,
        newest_plan_creation,
        last_execution_time,
        sample_sql_handle,
        sample_plan_handle
    )
    SELECT
        query_type = totals.query_type,
        database_name = DB_NAME(totals.database_id),
        object_name =
            OBJECT_SCHEMA_NAME(totals.object_id, totals.database_id) +
            N'.' +
            OBJECT_NAME(totals.object_id, totals.database_id),
        plan_count = totals.plan_count,
        total_executions = totals.total_executions,
        total_cpu_ms = totals.total_cpu_ms,
        total_duration_ms = totals.total_duration_ms,
        total_logical_reads = totals.total_logical_reads,
        total_logical_writes = totals.total_logical_writes,
        total_physical_reads = totals.total_physical_reads,
        oldest_plan_creation = totals.oldest_plan_creation,
        newest_plan_creation = totals.newest_plan_creation,
        last_execution_time = totals.last_execution_time,
        sample_sql_handle = winner.sql_handle,
        sample_plan_handle = winner.plan_handle
    FROM
    (
        SELECT
            os.query_type,
            os.database_id,
            os.object_id,
            plan_count = COUNT_BIG(DISTINCT os.plan_handle),
            total_executions = SUM(os.execution_count),
            total_cpu_ms = SUM(os.total_worker_time) / 1000.0,
            total_duration_ms = SUM(os.total_elapsed_time) / 1000.0,
            total_logical_reads = SUM(os.total_logical_reads),
            total_logical_writes = SUM(os.total_logical_writes),
            total_physical_reads = SUM(os.total_physical_reads),
            oldest_plan_creation = MIN(os.cached_time),
            newest_plan_creation = MAX(os.cached_time),
            last_execution_time = MAX(os.last_execution_time)
        FROM #dm_exec_object_stats AS os
        GROUP BY
            os.query_type,
            os.database_id,
            os.object_id
        HAVING
            SUM(os.execution_count) >= @minimum_execution_count
    ) AS totals
    JOIN
    (
        SELECT
            os.query_type,
            os.database_id,
            os.object_id,
            os.sql_handle,
            os.plan_handle,
            n =
                ROW_NUMBER() OVER
                (
                    PARTITION BY
                        os.query_type,
                        os.database_id,
                        os.object_id
                    ORDER BY
                        os.execution_count DESC
                )
        FROM #dm_exec_object_stats AS os
    ) AS winner
      ON  winner.query_type = totals.query_type
      AND winner.database_id = totals.database_id
      AND winner.object_id = totals.object_id
      AND winner.n = 1
    OPTION(RECOMPILE, MAXDOP 1);

    IF @debug = 1
    BEGIN
        DECLARE
            @proc_count bigint,
            @func_count bigint,
            @trig_count bigint;

        /*
        ISNULL because SUM over ZERO rows returns NULL, not 0 — the
        ELSE 0 only guards against NULL inputs, not against #query_stats
        being empty, which it is whenever the filters match nothing.
        Without this these print "(null)" where the three separate
        COUNT_BIG(*) reads they replaced printed "0".
        */
        SELECT
            @proc_count =
                ISNULL(SUM(CASE WHEN qs.query_type = 'Procedure' THEN 1 ELSE 0 END), 0),
            @func_count =
                ISNULL(SUM(CASE WHEN qs.query_type = 'Function' THEN 1 ELSE 0 END), 0),
            @trig_count =
                ISNULL(SUM(CASE WHEN qs.query_type = 'Trigger' THEN 1 ELSE 0 END), 0)
        FROM #query_stats AS qs;

        RAISERROR(N'Procedure objects collected: %I64d', 0, 1, @proc_count) WITH NOWAIT;
        RAISERROR(N'Function objects collected: %I64d', 0, 1, @func_count) WITH NOWAIT;
        RAISERROR(N'Trigger objects collected: %I64d', 0, 1, @trig_count) WITH NOWAIT;
    END;

    /*
    Bail out early if nothing to analyze
    */
    IF NOT EXISTS
    (
        SELECT
            1/0
        FROM #query_stats
    )
    BEGIN
        RAISERROR(N'No queries found in the plan cache matching the filter criteria.', 10, 1) WITH NOWAIT;
        RETURN;
    END;

    /*
    ╔══════════════════════════════════════════════════╗
    ║  Compute workload totals for share calculations  ║
    ╚══════════════════════════════════════════════════╝
    */
    DECLARE
        @total_cpu_ms decimal(38, 2) = 0,
        @total_duration_ms decimal(38, 2) = 0,
        @total_physical_reads bigint = 0,
        @total_logical_writes bigint = 0,
        @total_grant_mb decimal(38, 2) = 0,
        @total_spills bigint = 0,
        @total_executions bigint = 0,
        @total_entries bigint = 0;

    SELECT
        @total_cpu_ms = SUM(qs.total_cpu_ms),
        @total_duration_ms = SUM(qs.total_duration_ms),
        @total_physical_reads = SUM(qs.total_physical_reads),
        @total_logical_writes = SUM(qs.total_logical_writes),
        @total_grant_mb = SUM(qs.total_grant_mb),
        @total_spills = SUM(qs.total_spills),
        @total_executions = SUM(qs.total_executions),
        @total_entries = COUNT_BIG(*)
    FROM #query_stats AS qs
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        SELECT
            @debug_msg =
                N'Workload totals — CPU: ' + CONVERT(nvarchar(20), @total_cpu_ms) +
                N' ms, Physical Reads: ' + CONVERT(nvarchar(20), @total_physical_reads) +
                N', Executions: ' + CONVERT(nvarchar(20), @total_executions) +
                N', Entries: ' + CONVERT(nvarchar(20), @total_entries);
        RAISERROR(N'%s', 0, 1, @debug_msg) WITH NOWAIT;
    END;

    /*
    ╔══════════════════════════════════════════════════╗
    ║  Step 2: Select interesting candidates           ║
    ║  (Top N per metric, then deduplicate)            ║
    ╚══════════════════════════════════════════════════╝
    */
    CREATE TABLE
        #candidates
    (
        id integer NOT NULL
    );

    /*
    Union of top N by each metric dimension
    */
    INSERT
        #candidates
    WITH
        (TABLOCK)
    (
        id
    )
    SELECT DISTINCT
        x.id
    FROM
    (
        SELECT TOP (@top)
            qs.id
        FROM #query_stats AS qs
        ORDER BY
            qs.total_cpu_ms DESC

        UNION

        SELECT TOP (@top)
            qs.id
        FROM #query_stats AS qs
        ORDER BY
            qs.total_duration_ms DESC

        UNION

        SELECT TOP (@top)
            qs.id
        FROM #query_stats AS qs
        ORDER BY
            qs.total_physical_reads DESC

        UNION

        SELECT TOP (@top)
            qs.id
        FROM #query_stats AS qs
        ORDER BY
            qs.total_logical_writes DESC

        UNION

        SELECT TOP (@top)
            qs.id
        FROM #query_stats AS qs
        WHERE qs.total_grant_mb > 0
        ORDER BY
            qs.total_grant_mb DESC

        UNION

        SELECT TOP (@top)
            qs.id
        FROM #query_stats AS qs
        WHERE qs.total_spills > 0
        ORDER BY
            qs.total_spills DESC

        UNION

        SELECT TOP (@top)
            qs.id
        FROM #query_stats AS qs
        ORDER BY
            qs.total_executions DESC
    ) AS x
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        DECLARE
            @candidate_count bigint;

        SELECT
            @candidate_count = COUNT_BIG(*)
        FROM #candidates;

        RAISERROR(N'Unique candidates: %I64d', 0, 1, @candidate_count) WITH NOWAIT;
    END;

    /*
    ╔══════════════════════════════════════════════════╗
    ║  Step 3: Score with PERCENT_RANK                 ║
    ║  Only active if query >= 0.1% of total resource  ║
    ╚══════════════════════════════════════════════════╝
    */
    CREATE TABLE
        #scored
    (
        id integer NOT NULL,
        query_type varchar(20) NOT NULL,
        database_name sysname NULL,
        object_name sysname NULL,
        query_hash binary(8) NULL,
        plan_count integer NOT NULL,
        total_executions bigint NOT NULL,
        total_cpu_ms decimal(38, 2) NOT NULL,
        total_duration_ms decimal(38, 2) NOT NULL,
        total_physical_reads bigint NOT NULL,
        total_logical_writes bigint NOT NULL,
        total_rows bigint NOT NULL,
        total_grant_mb decimal(38, 2) NOT NULL,
        total_used_grant_mb decimal(38, 2) NOT NULL,
        max_grant_mb decimal(38, 2) NULL,
        max_used_grant_mb decimal(38, 2) NULL,
        total_spills bigint NOT NULL,
        max_spills bigint NULL,
        max_dop integer NULL,
        min_rows bigint NULL,
        max_rows bigint NULL,
        min_cpu_ms decimal(38, 2) NULL,
        max_cpu_ms decimal(38, 2) NULL,
        min_physical_reads bigint NULL,
        max_physical_reads bigint NULL,
        min_duration_ms decimal(38, 2) NULL,
        max_duration_ms decimal(38, 2) NULL,

        /* resource shares */
        cpu_share decimal(5, 2) NULL,
        duration_share decimal(5, 2) NULL,
        reads_share decimal(5, 2) NULL,
        writes_share decimal(5, 2) NULL,
        grant_share decimal(5, 2) NULL,
        spills_share decimal(5, 2) NULL,
        executions_share decimal(5, 2) NULL,

        /* percentile ranks */
        cpu_pctl decimal(5, 4) NULL,
        duration_pctl decimal(5, 4) NULL,
        reads_pctl decimal(5, 4) NULL,
        writes_pctl decimal(5, 4) NULL,
        grant_pctl decimal(5, 4) NULL,
        spills_pctl decimal(5, 4) NULL,
        executions_pctl decimal(5, 4) NULL,

        /* composite score */
        impact_score decimal(5, 2) NULL,
        high_signals nvarchar(500) NULL,
        diagnostics nvarchar(max) NULL,

        /* resource rollup */
        resource_metrics xml NULL,

        /* plan metadata */
        oldest_plan_creation datetime NULL,
        newest_plan_creation datetime NULL,
        last_execution_time datetime NULL,
        sample_sql_handle varbinary(64) NULL,
        sample_plan_handle varbinary(64) NULL,
        sample_statement_start integer NULL,
        sample_statement_end integer NULL
    );

    INSERT
        #scored
    WITH
        (TABLOCK)
    (
        id,
        query_type,
        database_name,
        object_name,
        query_hash,
        plan_count,
        total_executions,
        total_cpu_ms,
        total_duration_ms,
        total_physical_reads,
        total_logical_writes,
        total_rows,
        total_grant_mb,
        total_used_grant_mb,
        max_grant_mb,
        max_used_grant_mb,
        total_spills,
        max_spills,
        max_dop,
        min_rows,
        max_rows,
        min_cpu_ms,
        max_cpu_ms,
        min_physical_reads,
        max_physical_reads,
        min_duration_ms,
        max_duration_ms,
        cpu_share,
        duration_share,
        reads_share,
        writes_share,
        grant_share,
        spills_share,
        executions_share,
        cpu_pctl,
        duration_pctl,
        reads_pctl,
        writes_pctl,
        grant_pctl,
        spills_pctl,
        executions_pctl,
        resource_metrics,
        oldest_plan_creation,
        newest_plan_creation,
        last_execution_time,
        sample_sql_handle,
        sample_plan_handle,
        sample_statement_start,
        sample_statement_end
    )
    SELECT
        id = qs.id,
        query_type = qs.query_type,
        database_name = qs.database_name,
        object_name = qs.object_name,
        query_hash = qs.query_hash,
        plan_count = qs.plan_count,
        total_executions = qs.total_executions,
        total_cpu_ms = qs.total_cpu_ms,
        total_duration_ms = qs.total_duration_ms,
        total_physical_reads = qs.total_physical_reads,
        total_logical_writes = qs.total_logical_writes,
        total_rows = qs.total_rows,
        total_grant_mb = qs.total_grant_mb,
        total_used_grant_mb = qs.total_used_grant_mb,
        max_grant_mb = qs.max_grant_mb,
        max_used_grant_mb = qs.max_used_grant_mb,
        total_spills = qs.total_spills,
        max_spills = qs.max_spills,
        max_dop = qs.max_dop,
        min_rows = qs.min_rows,
        max_rows = qs.max_rows,
        min_cpu_ms = qs.min_cpu_ms,
        max_cpu_ms = qs.max_cpu_ms,
        min_physical_reads = qs.min_physical_reads,
        max_physical_reads = qs.max_physical_reads,
        min_duration_ms = qs.min_duration_ms,
        max_duration_ms = qs.max_duration_ms,

        /* resource shares (% of total workload) */
        cpu_share =
            CASE
                WHEN @total_cpu_ms > 0
                THEN CONVERT(decimal(5, 2), qs.total_cpu_ms * 100.0 / @total_cpu_ms)
                ELSE 0
            END,
        duration_share =
            CASE
                WHEN @total_duration_ms > 0
                THEN CONVERT(decimal(5, 2), qs.total_duration_ms * 100.0 / @total_duration_ms)
                ELSE 0
            END,
        reads_share =
            CASE
                WHEN @total_physical_reads > 0
                THEN CONVERT(decimal(5, 2), qs.total_physical_reads * 100.0 / @total_physical_reads)
                ELSE 0
            END,
        writes_share =
            CASE
                WHEN @total_logical_writes > 0
                THEN CONVERT(decimal(5, 2), qs.total_logical_writes * 100.0 / @total_logical_writes)
                ELSE 0
            END,
        grant_share =
            CASE
                WHEN @total_grant_mb > 0
                THEN CONVERT(decimal(5, 2), qs.total_grant_mb * 100.0 / @total_grant_mb)
                ELSE 0
            END,
        spills_share =
            CASE
                WHEN @total_spills > 0
                THEN CONVERT(decimal(5, 2), qs.total_spills * 100.0 / @total_spills)
                ELSE 0
            END,
        executions_share =
            CASE
                WHEN @total_executions > 0
                THEN CONVERT(decimal(5, 2), qs.total_executions * 100.0 / @total_executions)
                ELSE 0
            END,

        /*
        PERCENT_RANK across all entries in the workload (not just candidates).
        NULL if the query contributes < 0.1% of total for that metric.
        */
        cpu_pctl =
            CASE
                WHEN @total_cpu_ms > 0
                AND  qs.total_cpu_ms * 1.0 / @total_cpu_ms >= 0.001
                THEN PERCENT_RANK() OVER
                     (
                         ORDER BY
                             qs.total_cpu_ms
                     )
                ELSE NULL
            END,
        duration_pctl =
            CASE
                WHEN @total_duration_ms > 0
                AND  qs.total_duration_ms * 1.0 / @total_duration_ms >= 0.001
                THEN PERCENT_RANK() OVER
                     (
                         ORDER BY
                             qs.total_duration_ms
                     )
                ELSE NULL
            END,
        reads_pctl =
            CASE
                WHEN @total_physical_reads > 0
                AND  qs.total_physical_reads * 1.0 / @total_physical_reads >= 0.001
                THEN PERCENT_RANK() OVER
                     (
                         ORDER BY
                             qs.total_physical_reads
                     )
                ELSE NULL
            END,
        writes_pctl =
            CASE
                WHEN @total_logical_writes > 0
                AND  qs.total_logical_writes * 1.0 / @total_logical_writes >= 0.001
                THEN PERCENT_RANK() OVER
                     (
                         ORDER BY
                             qs.total_logical_writes
                     )
                ELSE NULL
            END,
        grant_pctl =
            CASE
                WHEN @total_grant_mb > 0
                AND  qs.total_grant_mb * 1.0 / @total_grant_mb >= 0.001
                THEN PERCENT_RANK() OVER
                     (
                         ORDER BY
                             qs.total_grant_mb
                     )
                ELSE NULL
            END,
        spills_pctl =
            CASE
                WHEN @total_spills > 0
                AND  qs.total_spills * 1.0 / @total_spills >= 0.001
                THEN PERCENT_RANK() OVER
                     (
                         ORDER BY
                             qs.total_spills
                     )
                ELSE NULL
            END,
        executions_pctl =
            CASE
                WHEN @total_executions > 0
                AND  qs.total_executions * 1.0 / @total_executions >= 0.001
                THEN PERCENT_RANK() OVER
                     (
                         ORDER BY
                             qs.total_executions
                     )
                ELSE NULL
            END,

        resource_metrics =
        (
            SELECT
                [cpu/@total_ms]              = qs.total_cpu_ms,
                [cpu/@avg_ms]                = qs.total_cpu_ms / NULLIF(qs.total_executions, 0),
                [cpu/@min_ms]                = qs.min_cpu_ms,
                [cpu/@max_ms]                = qs.max_cpu_ms,
                [duration/@total_ms]         = qs.total_duration_ms,
                [duration/@avg_ms]           = qs.total_duration_ms / NULLIF(qs.total_executions, 0),
                [duration/@min_ms]           = qs.min_duration_ms,
                [duration/@max_ms]           = qs.max_duration_ms,
                [physical_reads/@total]      = qs.total_physical_reads,
                [physical_reads/@avg]        = CONVERT(decimal(38, 2), qs.total_physical_reads) / NULLIF(qs.total_executions, 0),
                [physical_reads/@min]        = qs.min_physical_reads,
                [physical_reads/@max]        = qs.max_physical_reads,
                [logical_writes/@total]      = qs.total_logical_writes,
                [logical_writes/@avg]        = CONVERT(decimal(38, 2), qs.total_logical_writes) / NULLIF(qs.total_executions, 0),
                [rows/@total]                = qs.total_rows,
                [rows/@avg]                  = CONVERT(decimal(38, 2), qs.total_rows) / NULLIF(qs.total_executions, 0),
                [rows/@min]                  = qs.min_rows,
                [rows/@max]                  = qs.max_rows,
                [grant/@total_mb]            = qs.total_grant_mb,
                [grant/@avg_mb]              = qs.total_grant_mb / NULLIF(qs.total_executions, 0),
                [grant/@max_mb]              = qs.max_grant_mb,
                [used_grant/@total_mb]       = qs.total_used_grant_mb,
                [used_grant/@avg_mb]         = qs.total_used_grant_mb / NULLIF(qs.total_executions, 0),
                [used_grant/@max_mb]         = qs.max_used_grant_mb,
                [spills/@total]              = qs.total_spills,
                [spills/@avg]                = CONVERT(decimal(38, 2), qs.total_spills) / NULLIF(qs.total_executions, 0),
                [spills/@max]                = qs.max_spills,
                [executions/@total]          = qs.total_executions,
                [parallelism/@max_dop]       = qs.max_dop
            FOR
                XML
                PATH(N'metrics'),
                TYPE
        ),

        oldest_plan_creation = qs.oldest_plan_creation,
        newest_plan_creation = qs.newest_plan_creation,
        last_execution_time = qs.last_execution_time,
        sample_sql_handle = qs.sample_sql_handle,
        sample_plan_handle = qs.sample_plan_handle,
        sample_statement_start = qs.sample_statement_start,
        sample_statement_end = qs.sample_statement_end
    FROM #query_stats AS qs
    WHERE EXISTS
    (
        SELECT
            1/0
        FROM #candidates AS c
        WHERE c.id = qs.id
    )
    OPTION(RECOMPILE);

    /*
    ╔══════════════════════════════════════════════════╗
    ║  Step 4: Compute impact_score and high_signals   ║
    ╚══════════════════════════════════════════════════╝

    impact_score = average of non-NULL percentile ranks.
    high_signals = dimensions >= 80th percentile.
    */
    UPDATE
        s
    SET
        s.impact_score =
            CONVERT
            (
                decimal(5, 2),
                (
                    ISNULL(s.cpu_pctl, 0) +
                    ISNULL(s.duration_pctl, 0) +
                    ISNULL(s.reads_pctl, 0) +
                    ISNULL(s.writes_pctl, 0) +
                    ISNULL(s.grant_pctl, 0) +
                    ISNULL(s.spills_pctl, 0) +
                    ISNULL(s.executions_pctl, 0)
                ) /
                NULLIF
                (
                    CASE WHEN s.cpu_pctl        IS NOT NULL THEN 1 ELSE 0 END +
                    CASE WHEN s.duration_pctl   IS NOT NULL THEN 1 ELSE 0 END +
                    CASE WHEN s.reads_pctl      IS NOT NULL THEN 1 ELSE 0 END +
                    CASE WHEN s.writes_pctl     IS NOT NULL THEN 1 ELSE 0 END +
                    CASE WHEN s.grant_pctl      IS NOT NULL THEN 1 ELSE 0 END +
                    CASE WHEN s.spills_pctl     IS NOT NULL THEN 1 ELSE 0 END +
                    CASE WHEN s.executions_pctl IS NOT NULL THEN 1 ELSE 0 END,
                    0
                )
            ),
        s.high_signals =
            CASE WHEN s.cpu_pctl        >= 0.80 THEN N'cpu, '        ELSE N'' END +
            CASE WHEN s.duration_pctl   >= 0.80 THEN N'duration, '   ELSE N'' END +
            CASE WHEN s.reads_pctl      >= 0.80 THEN N'physical reads, ' ELSE N'' END +
            CASE WHEN s.writes_pctl     >= 0.80 THEN N'writes, '     ELSE N'' END +
            CASE WHEN s.grant_pctl      >= 0.80 THEN N'memory, '     ELSE N'' END +
            CASE WHEN s.spills_pctl     >= 0.80 THEN N'spills, '     ELSE N'' END +
            CASE WHEN s.executions_pctl >= 0.80 THEN N'executions, ' ELSE N'' END
    FROM #scored AS s
    OPTION(RECOMPILE);

    /*
    Trim trailing comma from high_signals
    */
    UPDATE
        s
    SET
        s.high_signals =
            CASE
                WHEN s.high_signals = N''
                THEN NULL
                ELSE LEFT(s.high_signals, LEN(s.high_signals) - 1)
            END
    FROM #scored AS s
    OPTION(RECOMPILE);

    /*
    ╔══════════════════════════════════════════════════╗
    ║  Step 5: Diagnostic heuristics                   ║
    ╚══════════════════════════════════════════════════╝
    */
    UPDATE
        s
    SET
        s.diagnostics =
            /*
            Wait-bound: duration >> cpu indicates blocking, locks, I/O waits
            */
            CASE
                WHEN s.total_cpu_ms > 0
                AND  s.total_duration_ms / s.total_cpu_ms > 5.0
                THEN N'Wait-bound (duration ' +
                     CONVERT
                     (
                         nvarchar(10),
                         CONVERT(decimal(10, 1), s.total_duration_ms / s.total_cpu_ms)
                     ) +
                     N'x CPU); '
                ELSE N''
            END +
            /*
            Plan instability: multiple cached plans for the same query
            */
            CASE
                WHEN s.plan_count > 1
                THEN N'Plan instability (' +
                     CONVERT(nvarchar(10), s.plan_count) +
                     N' plans); '
                ELSE N''
            END +
            /*
            Row count variance: huge gap between min and max rows
            suggests parameter sensitivity or data skew
            */
            CASE
                WHEN s.min_rows IS NOT NULL
                AND  s.max_rows IS NOT NULL
                AND  s.min_rows > 0
                AND  s.max_rows * 1.0 / s.min_rows >= 100.0
                THEN N'Row count variance (' +
                     FORMAT(s.min_rows, N'N0') +
                     N' to ' +
                     FORMAT(s.max_rows, N'N0') +
                     N'); '
                ELSE N''
            END +
            /*
            Parameter sniffing: execution_count > 3 and either
            CPU or reads have > 30% variance between min and avg.
            Uses the same heuristic as sp_BlitzCache.
            */
            CASE
                WHEN s.total_executions > 3
                AND  s.min_cpu_ms IS NOT NULL
                AND  s.max_cpu_ms IS NOT NULL
                AND  s.total_cpu_ms / s.total_executions > 0
                AND
                (
                    s.min_cpu_ms < (s.total_cpu_ms / s.total_executions) * 0.70
                    OR s.max_cpu_ms > (s.total_cpu_ms / s.total_executions) * 1.30
                )
                THEN N'Parameter sniffing (CPU ' +
                     FORMAT(CONVERT(bigint, s.min_cpu_ms), N'N0') +
                     N'-' +
                     FORMAT(CONVERT(bigint, s.max_cpu_ms), N'N0') +
                     N' ms, avg ' +
                     FORMAT(CONVERT(bigint, s.total_cpu_ms / s.total_executions), N'N0') +
                     N' ms); '
                WHEN s.total_executions > 3
                AND  s.min_physical_reads IS NOT NULL
                AND  s.max_physical_reads IS NOT NULL
                AND  s.total_physical_reads / s.total_executions > 1000
                AND
                (
                    s.min_physical_reads < (s.total_physical_reads / s.total_executions) * 0.70
                    OR s.max_physical_reads > (s.total_physical_reads / s.total_executions) * 1.30
                )
                THEN N'Parameter sniffing (physical reads ' +
                     FORMAT(s.min_physical_reads, N'N0') +
                     N'-' +
                     FORMAT(s.max_physical_reads, N'N0') +
                     N', avg ' +
                     FORMAT(s.total_physical_reads / s.total_executions, N'N0') +
                     N'); '
                ELSE N''
            END +
            /*
            Wasteful memory grant: large grant with < 10% utilization
            */
            CASE
                WHEN s.max_grant_mb IS NOT NULL
                AND  s.max_grant_mb > 1.0
                AND  s.max_used_grant_mb IS NOT NULL
                AND  s.max_used_grant_mb * 1.0 /
                     NULLIF(s.max_grant_mb, 0) < 0.10
                THEN N'Wasteful grant (' +
                     CONVERT(nvarchar(20), s.max_grant_mb) +
                     N' MB granted, ' +
                     CONVERT
                     (
                         nvarchar(10),
                         CONVERT
                         (
                             decimal(5, 1),
                             s.max_used_grant_mb * 100.0 /
                             NULLIF(s.max_grant_mb, 0)
                         )
                     ) +
                     N'% used); '
                ELSE N''
            END +
            /*
            Spilling queries
            */
            CASE
                WHEN ISNULL(s.total_spills, 0) > 0
                THEN N'Spills (' +
                     FORMAT(s.total_spills, N'N0') +
                     N' total); '
                ELSE N''
            END +
            /*
            Parallel plans with high DOP
            */
            CASE
                WHEN ISNULL(s.max_dop, 0) > 1
                THEN N'Parallel (max DOP ' +
                     CONVERT(nvarchar(10), s.max_dop) +
                     N'); '
                ELSE N''
            END +
            /*
            Rare but expensive: <= 10 executions but big resource share
            */
            CASE
                WHEN s.total_executions <= 10
                AND
                (
                    s.cpu_share >= 5.0
                    OR s.reads_share >= 5.0
                    OR s.grant_share >= 5.0
                )
                THEN N'Rare but expensive (' +
                     CONVERT(nvarchar(20), s.total_executions) +
                     N' execs); '
                ELSE N''
            END +
            /*
            Frequently executed: > 100 executions per minute
            */
            CASE
                WHEN s.total_executions > 0
                AND  s.oldest_plan_creation IS NOT NULL
                AND  DATEDIFF(MINUTE, s.oldest_plan_creation, GETDATE()) > 0
                AND  s.total_executions * 1.0 /
                     NULLIF(DATEDIFF(MINUTE, s.oldest_plan_creation, GETDATE()), 0) > 100.0
                THEN N'High frequency (' +
                     FORMAT
                     (
                         CONVERT
                         (
                             bigint,
                             s.total_executions * 1.0 /
                             NULLIF(DATEDIFF(MINUTE, s.oldest_plan_creation, GETDATE()), 0)
                         ),
                         N'N0'
                     ) +
                     N'/min); '
                ELSE N''
            END
    FROM #scored AS s
    OPTION(RECOMPILE);

    /*
    Trim trailing semicolons from diagnostics
    */
    UPDATE
        s
    SET
        s.diagnostics =
            CASE
                WHEN s.diagnostics = N''
                THEN NULL
                ELSE LEFT(s.diagnostics, LEN(s.diagnostics) - 1)
            END
    FROM #scored AS s
    OPTION(RECOMPILE);

    /*
    ╔══════════════════════════════════════════════════╗
    ║  Result set 1: Workload profile summary            ║
    ╚══════════════════════════════════════════════════╝
    */
    DECLARE
        @surfaced_count bigint = 0,
        @surfaced_cpu_pct decimal(5, 2) = 0,
        @surfaced_reads_pct decimal(5, 2) = 0,
        @surfaced_duration_pct decimal(5, 2) = 0,
        @surfaced_grant_pct decimal(5, 2) = 0;

    SELECT
        @surfaced_count = COUNT_BIG(*),
        @surfaced_cpu_pct = ISNULL(SUM(s.cpu_share), 0),
        @surfaced_reads_pct = ISNULL(SUM(s.reads_share), 0),
        @surfaced_duration_pct = ISNULL(SUM(s.duration_share), 0),
        @surfaced_grant_pct = ISNULL(SUM(s.grant_share), 0)
    FROM #scored AS s
    WHERE s.impact_score >= @impact_threshold
    OPTION(RECOMPILE);

    SELECT
        total_plan_cache_entries = @total_entries,
        surfaced_entries = @surfaced_count,
        cpu_captured_pct = @surfaced_cpu_pct,
        reads_captured_pct = @surfaced_reads_pct,
        duration_captured_pct = @surfaced_duration_pct,
        grant_captured_pct = @surfaced_grant_pct,
        workload_profile =
            CASE
                WHEN @surfaced_cpu_pct >= 50.0
                OR   @surfaced_reads_pct >= 50.0
                THEN N'Concentrated — a few queries dominate resource usage'
                WHEN @surfaced_cpu_pct >= 25.0
                OR   @surfaced_reads_pct >= 25.0
                THEN N'Moderate — some clear outliers but workload is spread'
                ELSE N'Flat — resource usage is distributed across many queries'
            END,
        recommendation =
            CASE
                WHEN @surfaced_count = 0
                THEN N'No high-impact queries found. Try lowering @impact_threshold or @minimum_execution_count.'
                WHEN @surfaced_cpu_pct >= 50.0
                OR   @surfaced_reads_pct >= 50.0
                THEN N'Concentrated workload. Tuning the surfaced queries will have outsized impact.'
                WHEN @surfaced_cpu_pct >= 25.0
                OR   @surfaced_reads_pct >= 25.0
                THEN N'Moderate concentration. Focus on queries with the highest impact_score first.'
                ELSE N'Flat workload. Individual query tuning has limited ROI. Consider systemic improvements (indexing strategy, caching, architecture).'
            END;

    /*
    ╔══════════════════════════════════════════════════╗
    ║  Result set 2: High-impact queries               ║
    ╚══════════════════════════════════════════════════╝
    */
    SELECT
        s.database_name,
        s.query_type,
        s.object_name,
        query_text =
            (
                SELECT
                    [processing-instruction(query)] =
                        REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                        REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                        REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                            CASE
                                WHEN s.query_type = 'Statement'
                                THEN SUBSTRING
                                     (
                                         st.text,
                                         (s.sample_statement_start / 2) + 1,
                                         (
                                             CASE s.sample_statement_end
                                                 WHEN -1
                                                 THEN DATALENGTH(st.text)
                                                 ELSE s.sample_statement_end
                                             END - s.sample_statement_start
                                         ) / 2 + 1
                                     )
                                ELSE st.text
                            END COLLATE Latin1_General_BIN2,
                        NCHAR(31),N'?'),NCHAR(30),N'?'),NCHAR(29),N'?'),NCHAR(28),N'?'),NCHAR(27),N'?'),NCHAR(26),N'?'),NCHAR(25),N'?'),NCHAR(24),N'?'),NCHAR(23),N'?'),NCHAR(22),N'?'),
                        NCHAR(21),N'?'),NCHAR(20),N'?'),NCHAR(19),N'?'),NCHAR(18),N'?'),NCHAR(17),N'?'),NCHAR(16),N'?'),NCHAR(15),N'?'),NCHAR(14),N'?'),NCHAR(12),N'?'),
                        NCHAR(11),N'?'),NCHAR(8),N'?'),NCHAR(7),N'?'),NCHAR(6),N'?'),NCHAR(5),N'?'),NCHAR(4),N'?'),NCHAR(3),N'?'),NCHAR(2),N'?'),NCHAR(1),N'?'),NCHAR(0),N'')
                FOR
                    XML
                    PATH(N''),
                    TYPE
            ),
        query_plan =
            CASE
                WHEN TRY_CAST(qp.query_plan AS xml) IS NOT NULL
                THEN TRY_CAST(qp.query_plan AS xml)
                WHEN TRY_CAST(qp.query_plan AS xml) IS NULL
                THEN
                (
                    SELECT
                        [processing-instruction(query_plan)] =
                            N'-- ' + NCHAR(13) + NCHAR(10) +
                            N'-- This is a huge query plan.' + NCHAR(13) + NCHAR(10) +
                            N'-- Remove the headers and footers, save it as a .sqlplan file, and re-open it.' + NCHAR(13) + NCHAR(10) +
                            NCHAR(13) + NCHAR(10) +
                            REPLACE(qp.query_plan, N'<RelOp', NCHAR(13) + NCHAR(10) + N'<RelOp') +
                            NCHAR(13) + NCHAR(10) COLLATE Latin1_General_Bin2
                    FOR
                        XML
                        PATH(N''),
                        TYPE
                )
            END,
        s.query_hash,
        s.plan_count,
        s.impact_score,
        s.high_signals,
        s.total_executions,
        s.cpu_share,
        s.duration_share,
        s.reads_share,
        s.writes_share,
        s.grant_share,
        s.spills_share,
        s.executions_share,
        s.diagnostics,
        s.resource_metrics,
        s.oldest_plan_creation,
        s.last_execution_time,
        s.sample_sql_handle,
        s.sample_plan_handle
    FROM #scored AS s
    OUTER APPLY sys.dm_exec_sql_text(s.sample_sql_handle) AS st
    OUTER APPLY sys.dm_exec_text_query_plan
    (
        s.sample_plan_handle,
        ISNULL(s.sample_statement_start, 0),
        ISNULL(s.sample_statement_end, -1)
    ) AS qp
    WHERE s.impact_score >= @impact_threshold
    ORDER BY
        s.impact_score DESC,
        CASE @sort_order
            WHEN 'cpu'        THEN s.cpu_share
            WHEN 'duration'   THEN s.duration_share
            WHEN 'reads'      THEN s.reads_share
            WHEN 'writes'     THEN s.writes_share
            WHEN 'memory'     THEN s.grant_share
            WHEN 'spills'     THEN s.spills_share
            WHEN 'executions' THEN s.executions_share
        END DESC
    OPTION(RECOMPILE);

    /*
    ╔══════════════════════════════════════════════════╗
    ║  Result set 3: Plan cache health findings        ║
    ╚══════════════════════════════════════════════════╝
    */
    SELECT
        pch.finding_group,
        pch.finding,
        pch.database_name,
        pch.priority,
        pch.details
    FROM #plan_cache_health AS pch
    ORDER BY
        pch.priority,
        pch.finding_group,
        pch.id
    OPTION(RECOMPILE);

END;
GO
