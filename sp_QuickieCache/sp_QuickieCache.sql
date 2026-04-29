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
        @version = '1.6',
        @version_date = '20260501';

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
                st.text,
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
                MAX(st.text)
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
        OPTION(RECOMPILE, MAXDOP 1);

        RETURN;
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
    */
    DECLARE
        @total_plans bigint = 0,
        @plans_24h bigint = 0,
        @plans_4h bigint = 0,
        @plans_1h bigint = 0,
        @pct_24h decimal(5, 2) = 0,
        @pct_4h decimal(5, 2) = 0,
        @pct_1h decimal(5, 2) = 0,
        @oldest_plan_date datetime = NULL;

    SELECT
        @total_plans = COUNT_BIG(*),
        @plans_24h =
            SUM
            (
                CASE
                    WHEN DATEDIFF(HOUR, qs.creation_time, GETDATE()) <= 24
                    THEN 1
                    ELSE 0
                END
            ),
        @plans_4h =
            SUM
            (
                CASE
                    WHEN DATEDIFF(HOUR, qs.creation_time, GETDATE()) <= 4
                    THEN 1
                    ELSE 0
                END
            ),
        @plans_1h =
            SUM
            (
                CASE
                    WHEN DATEDIFF(HOUR, qs.creation_time, GETDATE()) <= 1
                    THEN 1
                    ELSE 0
                END
            ),
        @oldest_plan_date = MIN(qs.creation_time)
    FROM sys.dm_exec_query_stats AS qs
    CROSS APPLY
    (
        SELECT TOP (1)
            value = pa.value
        FROM sys.dm_exec_plan_attributes(qs.plan_handle) AS pa
        WHERE pa.attribute = N'dbid'
    ) AS pa
    WHERE 1 = 1
    AND   (@database_id IS NULL OR CONVERT(integer, pa.value) = @database_id)
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
            N'Of ' + FORMAT(@total_plans, N'N0') +
            N' cached plans, ' +
            CONVERT(nvarchar(10), @pct_24h) + N'% created in the last 24 hours, ' +
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
            N'Of ' + FORMAT(@total_plans, N'N0') +
            N' cached plans, ' +
            CONVERT(nvarchar(10), @pct_24h) + N'% created in the last 24 hours, ' +
            CONVERT(nvarchar(10), @pct_4h) + N'% in the last 4 hours, ' +
            CONVERT(nvarchar(10), @pct_1h) + N'% in the last 1 hour. ' +
            N'Oldest cached plan: ' + CONVERT(nvarchar(30), @oldest_plan_date, 120) + N'.'
        );
    END;

    /*
    Single-use plan bloat per database:
    High % of execution_count = 1 plans suggests ad hoc workload
    that may benefit from Forced Parameterization.
    Only surfaces databases where single-use plans exceed 10%.
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
                WHEN single_use_pct > 75
                THEN N'Single-Use Plan Bloat'
                ELSE N'Single-Use Plans'
            END,
        finding =
            CASE
                WHEN single_use_pct > 75
                THEN N'Excessive single-use plans in cache'
                ELSE N'Notable single-use plan percentage'
            END,
        x.database_name,
        priority =
            CASE
                WHEN single_use_pct > 75
                THEN 1
                ELSE 254
            END,
        details =
            FORMAT(x.single_use_count, N'N0') +
            N' of ' + FORMAT(x.total_count, N'N0') +
            N' plans (' +
            CONVERT(nvarchar(10), x.single_use_pct) +
            N'%) executed only once. Consider Forced Parameterization if these are unparameterized ad hoc queries.'
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
                        WHEN qs.execution_count = 1
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
                            WHEN qs.execution_count = 1
                            THEN 1
                            ELSE 0
                        END
                    ) * 100.0 / COUNT_BIG(*)
                )
        FROM sys.dm_exec_query_stats AS qs
        CROSS APPLY
        (
            SELECT TOP (1)
                value = pa.value
            FROM sys.dm_exec_plan_attributes(qs.plan_handle) AS pa
            WHERE pa.attribute = N'dbid'
        ) AS pa
        WHERE pa.value IS NOT NULL
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
            plan_count = COUNT_BIG(*)
        FROM sys.dm_exec_query_stats AS qs
        CROSS APPLY
        (
            SELECT TOP (1)
                value = pa.value
            FROM sys.dm_exec_plan_attributes(qs.plan_handle) AS pa
            WHERE pa.attribute = N'dbid'
        ) AS pa
        WHERE qs.query_hash <> 0x0000000000000000
        AND   (@database_id IS NULL OR CONVERT(integer, pa.value) = @database_id)
        GROUP BY
            qs.query_hash
        HAVING
            COUNT_BIG(*) > 5
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
            database_name = DB_NAME(CONVERT(integer, pa.value)),
            priority =
                CASE
                    WHEN @pct_duplicate > 75
                    THEN 1
                    ELSE 254
                END,
            details =
                FORMAT(COUNT_BIG(DISTINCT qs2.query_hash), N'N0') +
                N' query hashes with 5+ plans, totaling ' +
                FORMAT(COUNT_BIG(*), N'N0') + N' plans. ' +
                N'Most likely unparameterized queries. SET option differences between sessions can also cause this. Consider Forced Parameterization.'
        FROM
        (
            SELECT
                qs.query_hash
            FROM sys.dm_exec_query_stats AS qs
            WHERE qs.query_hash <> 0x0000000000000000
            GROUP BY
                qs.query_hash
            HAVING
                COUNT_BIG(*) > 5
        ) AS x
        JOIN sys.dm_exec_query_stats AS qs2
          ON qs2.query_hash = x.query_hash
        CROSS APPLY
        (
            SELECT TOP (1)
                value = pa.value
            FROM sys.dm_exec_plan_attributes(qs2.plan_handle) AS pa
            WHERE pa.attribute = N'dbid'
        ) AS pa
        WHERE pa.value IS NOT NULL
        AND   (@ignore_system_databases = 0 OR CONVERT(integer, pa.value) NOT IN (1, 2, 3, 4))
        AND   CONVERT(integer, pa.value) < 32761
        AND   (@database_id IS NULL OR CONVERT(integer, pa.value) = @database_id)
        GROUP BY
            pa.value
        ORDER BY
            COUNT_BIG(*) DESC
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
                N'Plan cache health: ' + CONVERT(nvarchar(20), @total_plans) +
                N' total plans, ' + CONVERT(nvarchar(10), @pct_24h) +
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

    DECLARE
        @sql nvarchar(max) = N'';

    /*
    ╔══════════════════════════════════════════════════╗
    ║  Step 1a: Collect statement-level stats          ║
    ║  (sys.dm_exec_query_stats, grouped by hash)      ║
    ╚══════════════════════════════════════════════════╝
    */
    SELECT
        @sql = N'
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
    total_rows,' +
    CASE
        WHEN @has_memory_grants = 1
        THEN N'
    total_grant_mb,
    total_used_grant_mb,
    max_grant_mb,
    max_used_grant_mb,'
        ELSE N''
    END +
    CASE
        WHEN @has_spills = 1
        THEN N'
    total_spills,
    max_spills,'
        ELSE N''
    END + N'
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
    last_execution_time
)
SELECT
    query_type = ''Statement'',
    database_name =
        DB_NAME
        (
            CONVERT
            (
                integer,
                MAX(pa.value)
            )
        ),
    query_hash = qs.query_hash,
    plan_count = COUNT_BIG(DISTINCT qs.plan_handle),
    total_executions = SUM(qs.execution_count),
    total_cpu_ms = SUM(qs.total_worker_time) / 1000.0,
    total_duration_ms = SUM(qs.total_elapsed_time) / 1000.0,
    total_logical_reads = SUM(qs.total_logical_reads),
    total_logical_writes = SUM(qs.total_logical_writes),
    total_physical_reads = SUM(qs.total_physical_reads),
    total_rows = SUM(qs.total_rows),' +
    CASE
        WHEN @has_memory_grants = 1
        THEN N'
    total_grant_mb = SUM(ISNULL(qs.max_grant_kb, 0)) / 1024.0,
    total_used_grant_mb = SUM(ISNULL(qs.max_used_grant_kb, 0)) / 1024.0,
    max_grant_mb = MAX(ISNULL(qs.max_grant_kb, 0)) / 1024.0,
    max_used_grant_mb = MAX(ISNULL(qs.max_used_grant_kb, 0)) / 1024.0,'
        ELSE N''
    END +
    CASE
        WHEN @has_spills = 1
        THEN N'
    total_spills = SUM(ISNULL(qs.total_spills, 0)),
    max_spills = MAX(ISNULL(qs.max_spills, 0)),'
        ELSE N''
    END + N'
    max_dop = MAX(qs.max_dop),
    min_rows = MIN(qs.min_rows),
    max_rows = MAX(qs.max_rows),
    min_cpu_ms = MIN(qs.min_worker_time) / 1000.0,
    max_cpu_ms = MAX(qs.max_worker_time) / 1000.0,
    min_physical_reads = MIN(qs.min_physical_reads),
    max_physical_reads = MAX(qs.max_physical_reads),
    min_duration_ms = MIN(qs.min_elapsed_time) / 1000.0,
    max_duration_ms = MAX(qs.max_elapsed_time) / 1000.0,
    oldest_plan_creation = MIN(qs.creation_time),
    newest_plan_creation = MAX(qs.creation_time),
    last_execution_time = MAX(qs.last_execution_time)
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY
(
    SELECT TOP (1)
        value = pa.value
    FROM sys.dm_exec_plan_attributes(qs.plan_handle) AS pa
    WHERE pa.attribute = N''dbid''
) AS pa
WHERE qs.query_hash <> 0x0000000000000000' +
    /* @minimum_execution_count is enforced ONLY in the HAVING
       SUM(execution_count) below — applying it per-row here
       filtered out individual plans whose single-plan execution_count
       was below the floor but whose group total was above it
       (think: a recompile-heavy query with many plans each run a
       few times that add up to a lot). Same reasoning applies to
       the procedure / function / trigger paths further down. */
    CASE
        WHEN @ignore_system_databases = 1
        THEN N'
AND   ISNULL(pa.value, 0) NOT IN (1, 2, 3, 4)
AND   ISNULL(pa.value, 0) < 32761'
        ELSE N''
    END +
    CASE
        WHEN @database_id IS NOT NULL
        THEN N'
AND   CONVERT(integer, pa.value) = @database_id'
        ELSE N''
    END +
    CASE
        WHEN @start_date IS NOT NULL
        THEN N'
AND   qs.creation_time >= @start_date'
        ELSE N''
    END +
    CASE
        WHEN @end_date IS NOT NULL
        THEN N'
AND   qs.creation_time < @end_date'
        ELSE N''
    END + N'
GROUP BY
    qs.query_hash
HAVING
    SUM(qs.execution_count) >= @minimum_execution_count
OPTION(RECOMPILE, MAXDOP 1);';

    IF @debug = 1
    BEGIN
        RAISERROR(N'Statement aggregation SQL:', 0, 1) WITH NOWAIT;
        RAISERROR(N'%s', 0, 1, @sql) WITH NOWAIT;
    END;

    EXECUTE sys.sp_executesql
        @sql,
        N'@minimum_execution_count bigint, @database_id integer, @start_date datetime, @end_date datetime',
        @minimum_execution_count,
        @database_id,
        @start_date,
        @end_date;

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
    Fix up sample handles and offsets so they come from
    the same plan row. MAX() in the GROUP BY can mismatch
    a sql_handle from one plan with offsets from another,
    producing clipped or blank query text.
    */
    UPDATE
        qs
    SET
        qs.sample_sql_handle = x.sql_handle,
        qs.sample_plan_handle = x.plan_handle,
        qs.sample_statement_start = x.statement_start_offset,
        qs.sample_statement_end = x.statement_end_offset
    FROM #query_stats AS qs
    CROSS APPLY
    (
        SELECT TOP (1)
            dqs.sql_handle,
            dqs.plan_handle,
            dqs.statement_start_offset,
            dqs.statement_end_offset
        FROM sys.dm_exec_query_stats AS dqs
        WHERE dqs.query_hash = qs.query_hash
        ORDER BY
            dqs.execution_count DESC
    ) AS x
    WHERE qs.query_type = 'Statement'
    OPTION(RECOMPILE);

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
    ║  Step 1b: Collect procedure-level stats          ║
    ║  (sys.dm_exec_procedure_stats)                   ║
    ╚══════════════════════════════════════════════════╝
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
    /*
    sample_sql_handle and sample_plan_handle previously used
    MAX(ps.sql_handle) and MAX(ps.plan_handle) — each picked the
    lexicographic max independently, so the two values could come
    from different plan rows and produce a mismatched text/plan
    pair when retrieved downstream. ROW_NUMBER() OVER
    (PARTITION BY database_id, object_id ORDER BY execution_count
    DESC) in a derived table, then MAX(CASE WHEN n = 1 THEN ...)
    in the outer aggregate, pulls both handles from the SAME winner
    row. Single DMV scan + one sort + one aggregate — much lighter
    than CROSS APPLY-ing the DMV per group, which nested-loops
    poorly on busy servers.
    */
    SELECT
        query_type = 'Procedure',
        database_name = DB_NAME(r.database_id),
        object_name = OBJECT_SCHEMA_NAME(r.object_id, r.database_id) + N'.' + OBJECT_NAME(r.object_id, r.database_id),
        plan_count = COUNT_BIG(DISTINCT r.plan_handle),
        total_executions = SUM(r.execution_count),
        total_cpu_ms = SUM(r.total_worker_time) / 1000.0,
        total_duration_ms = SUM(r.total_elapsed_time) / 1000.0,
        total_logical_reads = SUM(r.total_logical_reads),
        total_logical_writes = SUM(r.total_logical_writes),
        total_physical_reads = SUM(r.total_physical_reads),
        oldest_plan_creation = MIN(r.cached_time),
        newest_plan_creation = MAX(r.cached_time),
        last_execution_time = MAX(r.last_execution_time),
        sample_sql_handle = MAX(CASE WHEN r.n = 1 THEN r.sql_handle END),
        sample_plan_handle = MAX(CASE WHEN r.n = 1 THEN r.plan_handle END)
    FROM
    (
        SELECT
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
            ps.last_execution_time,
            n =
                ROW_NUMBER() OVER
                (
                    PARTITION BY
                        ps.database_id,
                        ps.object_id
                    ORDER BY
                        ps.execution_count DESC
                )
        FROM sys.dm_exec_procedure_stats AS ps
        /* See Statement path comment re: why @minimum_execution_count
           is HAVING-only rather than a per-row pre-filter. */
        WHERE ps.database_id > CASE WHEN @ignore_system_databases = 1 THEN 4 ELSE 0 END
        AND   ps.database_id < 32761
        AND   ps.database_id = ISNULL(@database_id, ps.database_id)
        AND   ps.cached_time >= ISNULL(@start_date, ps.cached_time)
        AND   ps.cached_time < ISNULL(@end_date, DATEADD(DAY, 1, ps.cached_time))
    ) AS r
    GROUP BY
        r.database_id,
        r.object_id
    HAVING
        SUM(r.execution_count) >= @minimum_execution_count
    OPTION(RECOMPILE, MAXDOP 1);

    IF @debug = 1
    BEGIN
        DECLARE
            @proc_count bigint;

        SELECT
            @proc_count = COUNT_BIG(*)
        FROM #query_stats AS qs
        WHERE qs.query_type = 'Procedure';

        RAISERROR(N'Procedure objects collected: %I64d', 0, 1, @proc_count) WITH NOWAIT;
    END;

    /*
    ╔══════════════════════════════════════════════════╗
    ║  Step 1c: Collect function-level stats           ║
    ║  (sys.dm_exec_function_stats)                    ║
    ╚══════════════════════════════════════════════════╝

    dm_exec_function_stats is available starting SQL Server 2016.
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
/* Same ROW_NUMBER + derived-table pattern as procedure path. */
SELECT
    query_type = ''Function'',
    database_name = DB_NAME(r.database_id),
    object_name = OBJECT_SCHEMA_NAME(r.object_id, r.database_id) + N''.'' + OBJECT_NAME(r.object_id, r.database_id),
    plan_count = COUNT_BIG(DISTINCT r.plan_handle),
    total_executions = SUM(r.execution_count),
    total_cpu_ms = SUM(r.total_worker_time) / 1000.0,
    total_duration_ms = SUM(r.total_elapsed_time) / 1000.0,
    total_logical_reads = SUM(r.total_logical_reads),
    total_logical_writes = SUM(r.total_logical_writes),
    total_physical_reads = SUM(r.total_physical_reads),
    oldest_plan_creation = MIN(r.cached_time),
    newest_plan_creation = MAX(r.cached_time),
    last_execution_time = MAX(r.last_execution_time),
    sample_sql_handle = MAX(CASE WHEN r.n = 1 THEN r.sql_handle END),
    sample_plan_handle = MAX(CASE WHEN r.n = 1 THEN r.plan_handle END)
FROM
(
    SELECT
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
        fs.last_execution_time,
        n =
            ROW_NUMBER() OVER
            (
                PARTITION BY
                    fs.database_id,
                    fs.object_id
                ORDER BY
                    fs.execution_count DESC
            )
    FROM sys.dm_exec_function_stats AS fs
    /* See Statement path comment re: why @minimum_execution_count
       is HAVING-only rather than a per-row pre-filter. */
    WHERE fs.database_id > CASE WHEN @ignore_system_databases = 1 THEN 4 ELSE 0 END
    AND   fs.database_id < 32761
    AND   fs.database_id = ISNULL(@database_id, fs.database_id)
    AND   fs.cached_time >= ISNULL(@start_date, fs.cached_time)
    AND   fs.cached_time < ISNULL(@end_date, DATEADD(DAY, 1, fs.cached_time))
) AS r
GROUP BY
    r.database_id,
    r.object_id
HAVING
    SUM(r.execution_count) >= @minimum_execution_count
OPTION(RECOMPILE, MAXDOP 1);';

        EXECUTE sys.sp_executesql
            @sql,
            N'@minimum_execution_count bigint, @database_id integer, @ignore_system_databases bit, @start_date datetime, @end_date datetime',
            @minimum_execution_count,
            @database_id,
            @ignore_system_databases,
            @start_date,
            @end_date;

        IF @debug = 1
        BEGIN
            DECLARE
                @func_count bigint;

            SELECT
                @func_count = COUNT_BIG(*)
            FROM #query_stats AS qs
            WHERE qs.query_type = 'Function';

            RAISERROR(N'Function objects collected: %I64d', 0, 1, @func_count) WITH NOWAIT;
        END;
    END;

    /*
    ╔══════════════════════════════════════════════════╗
    ║  Step 1d: Collect trigger-level stats            ║
    ║  (sys.dm_exec_trigger_stats)                     ║
    ╚══════════════════════════════════════════════════╝
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
    /* Same ROW_NUMBER + derived-table pattern as procedure/function paths. */
    SELECT
        query_type = 'Trigger',
        database_name = DB_NAME(r.database_id),
        object_name = OBJECT_SCHEMA_NAME(r.object_id, r.database_id) + N'.' + OBJECT_NAME(r.object_id, r.database_id),
        plan_count = COUNT_BIG(DISTINCT r.plan_handle),
        total_executions = SUM(r.execution_count),
        total_cpu_ms = SUM(r.total_worker_time) / 1000.0,
        total_duration_ms = SUM(r.total_elapsed_time) / 1000.0,
        total_logical_reads = SUM(r.total_logical_reads),
        total_logical_writes = SUM(r.total_logical_writes),
        total_physical_reads = SUM(r.total_physical_reads),
        oldest_plan_creation = MIN(r.cached_time),
        newest_plan_creation = MAX(r.cached_time),
        last_execution_time = MAX(r.last_execution_time),
        sample_sql_handle = MAX(CASE WHEN r.n = 1 THEN r.sql_handle END),
        sample_plan_handle = MAX(CASE WHEN r.n = 1 THEN r.plan_handle END)
    FROM
    (
        SELECT
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
            ts.last_execution_time,
            n =
                ROW_NUMBER() OVER
                (
                    PARTITION BY
                        ts.database_id,
                        ts.object_id
                    ORDER BY
                        ts.execution_count DESC
                )
        FROM sys.dm_exec_trigger_stats AS ts
        /* See Statement path comment re: why @minimum_execution_count
           is HAVING-only rather than a per-row pre-filter. */
        WHERE ts.database_id > CASE WHEN @ignore_system_databases = 1 THEN 4 ELSE 0 END
        AND   ts.database_id < 32761
        AND   ts.database_id = ISNULL(@database_id, ts.database_id)
        AND   ts.cached_time >= ISNULL(@start_date, ts.cached_time)
        AND   ts.cached_time < ISNULL(@end_date, DATEADD(DAY, 1, ts.cached_time))
    ) AS r
    GROUP BY
        r.database_id,
        r.object_id
    HAVING
        SUM(r.execution_count) >= @minimum_execution_count
    OPTION(RECOMPILE, MAXDOP 1);

    IF @debug = 1
    BEGIN
        DECLARE
            @trig_count bigint;

        SELECT
            @trig_count = COUNT_BIG(*)
        FROM #query_stats AS qs
        WHERE qs.query_type = 'Trigger';

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
            END,
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
