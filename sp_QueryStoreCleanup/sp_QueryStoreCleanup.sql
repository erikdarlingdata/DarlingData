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
Copyright 2026 Darling Data, LLC
https://www.erikdarling.com/

For usage and licensing details, run:
EXECUTE dbo.sp_QueryStoreCleanup
    @help = 1;

For working through errors:
EXECUTE dbo.sp_QueryStoreCleanup
    @debug = 1;

For support, head over to GitHub:
https://code.erikdarling.com
*/

IF OBJECT_ID(N'dbo.sp_QueryStoreCleanup', N'P') IS NULL
BEGIN
    EXECUTE (N'CREATE PROCEDURE dbo.sp_QueryStoreCleanup AS RETURN 138;');
END;
GO

ALTER PROCEDURE
    dbo.sp_QueryStoreCleanup
(
    @database_name sysname = NULL,               /*database to clean; NULL = current database*/
    @cleanup_targets varchar(100) = 'all',       /*what to target: all, system, maintenance, custom, none*/
    @custom_query_filter nvarchar(1024) = NULL,  /*custom LIKE pattern when using custom target*/
    @dedupe_by varchar(50) = 'all',              /*deduplication strategy: all, query_hash, plan_hash, none*/
    @min_age_days integer = NULL,                /*only remove queries not executed in this many days*/
    @report_only bit = 0,                        /*1 = report what would be removed without removing*/
    @sort_direction varchar(10) = 'ASC',         /*removal order by query_id: ASC or DESC*/
    @debug bit = 0,                              /*prints dynamic sql and diagnostics*/
    @help bit = 0,                               /*prints help information*/
    @version varchar(30) = NULL OUTPUT,          /*OUTPUT; for support*/
    @version_date datetime = NULL OUTPUT         /*OUTPUT; for support*/
)
WITH RECOMPILE
AS
BEGIN
    SET STATISTICS XML OFF;
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    SELECT
        @version = '1.6',
        @version_date = '20260501';

    /*
    Help section
    */
    IF @help = 1
    BEGIN
        /*
        Introduction
        */
        SELECT
            introduction =
                'hi, i''m sp_QueryStoreCleanup!' UNION ALL
        SELECT  'i clean up duplicate and noisy queries from query store' UNION ALL
        SELECT  'you can find me at https://code.erikdarling.com' UNION ALL
        SELECT  '' UNION ALL
        SELECT  'for support, head over to github:' UNION ALL
        SELECT  'https://code.erikdarling.com';

        /*
        Parameter descriptions
        */
        SELECT
            parameter_name =
                ap.name,
            data_type =
                t.name,
            description =
                CASE
                    ap.name
                    WHEN N'@database_name'
                    THEN 'the database to clean query store in'
                    WHEN N'@cleanup_targets'
                    THEN 'what to target: all, system, maintenance (or maint), custom, none'
                    WHEN N'@custom_query_filter'
                    THEN 'custom LIKE pattern for query text filtering; also applied when @cleanup_targets = all'
                    WHEN N'@dedupe_by'
                    THEN 'deduplication strategy: all, query_hash, plan_hash, none. note: hash dedup removes ALL copies of duplicated hashes, not all-but-one'
                    WHEN N'@min_age_days'
                    THEN 'only remove queries whose last execution is older than this many days; NULL = no age filter'
                    WHEN N'@report_only'
                    THEN 'report what would be removed without removing: one summary row, then one row per query_hash, biggest first. @debug = 1 also lists every query_id'
                    WHEN N'@sort_direction'
                    THEN 'removal order by query_id. to split a long removal, run two sessions at once, one ASC and one DESC. each skips queries the other already removed'
                    WHEN N'@debug'
                    THEN 'prints dynamic sql and diagnostics'
                    WHEN N'@help'
                    THEN 'prints this help information'
                    WHEN N'@version'
                    THEN 'OUTPUT; for support'
                    WHEN N'@version_date'
                    THEN 'OUTPUT; for support'
                END,
            valid_inputs =
                CASE
                    ap.name
                    WHEN N'@database_name'
                    THEN 'a database name with query store enabled'
                    WHEN N'@cleanup_targets'
                    THEN 'all, system, maintenance (or maint), custom, none, or comma-separated combination'
                    WHEN N'@custom_query_filter'
                    THEN 'any valid LIKE pattern, e.g. N''%some_text%'''
                    WHEN N'@dedupe_by'
                    THEN 'all, query_hash, plan_hash, none'
                    WHEN N'@min_age_days'
                    THEN 'any positive integer, e.g. 7, 30, 90'
                    WHEN N'@report_only'
                    THEN '0 or 1'
                    WHEN N'@sort_direction'
                    THEN 'ASC, DESC'
                    WHEN N'@debug'
                    THEN '0 or 1'
                    WHEN N'@help'
                    THEN '0 or 1'
                    WHEN N'@version'
                    THEN 'none; OUTPUT'
                    WHEN N'@version_date'
                    THEN 'none; OUTPUT'
                END,
            defaults =
                CASE
                    ap.name
                    WHEN N'@database_name'
                    THEN 'NULL; current database name if NULL'
                    WHEN N'@cleanup_targets'
                    THEN 'all'
                    WHEN N'@custom_query_filter'
                    THEN 'NULL'
                    WHEN N'@dedupe_by'
                    THEN 'all'
                    WHEN N'@min_age_days'
                    THEN 'NULL; no age filter'
                    WHEN N'@report_only'
                    THEN '0'
                    WHEN N'@sort_direction'
                    THEN 'ASC'
                    WHEN N'@debug'
                    THEN '0'
                    WHEN N'@help'
                    THEN '0'
                    WHEN N'@version'
                    THEN 'none; OUTPUT'
                    WHEN N'@version_date'
                    THEN 'none; OUTPUT'
                END
        FROM sys.all_parameters AS ap
        JOIN sys.all_objects AS o
          ON ap.object_id = o.object_id
        JOIN sys.types AS t
          ON  ap.system_type_id = t.system_type_id
          AND ap.user_type_id = t.user_type_id
        WHERE o.name = N'sp_QueryStoreCleanup'
        ORDER BY
            ap.parameter_id
        OPTION(MAXDOP 1, RECOMPILE);

        /*
        Example usage
        */
        SELECT
            example =
                '/* default: clean all known noise from current database */' UNION ALL
        SELECT  'EXECUTE dbo.sp_QueryStoreCleanup;' UNION ALL
        SELECT  '' UNION ALL
        SELECT  '/* target a specific database */' UNION ALL
        SELECT  'EXECUTE dbo.sp_QueryStoreCleanup @database_name = N''YourDatabase'';' UNION ALL
        SELECT  '' UNION ALL
        SELECT  '/* report only mode */' UNION ALL
        SELECT  'EXECUTE dbo.sp_QueryStoreCleanup @database_name = N''YourDatabase'', @report_only = 1;' UNION ALL
        SELECT  '' UNION ALL
        SELECT  '/* clean only system DMV queries */' UNION ALL
        SELECT  'EXECUTE dbo.sp_QueryStoreCleanup @database_name = N''YourDatabase'', @cleanup_targets = ''system'';' UNION ALL
        SELECT  '' UNION ALL
        SELECT  '/* clean only maintenance noise (index rebuilds, stats updates, DBCC, etc.) */' UNION ALL
        SELECT  'EXECUTE dbo.sp_QueryStoreCleanup @database_name = N''YourDatabase'', @cleanup_targets = ''maintenance'';' UNION ALL
        SELECT  '' UNION ALL
        SELECT  '/* deduplicate all queries by query hash only, no text filtering */' UNION ALL
        SELECT  'EXECUTE dbo.sp_QueryStoreCleanup @database_name = N''YourDatabase'', @cleanup_targets = ''none'', @dedupe_by = ''query_hash'';' UNION ALL
        SELECT  '' UNION ALL
        SELECT  '/* custom text filter */' UNION ALL
        SELECT  'EXECUTE dbo.sp_QueryStoreCleanup @database_name = N''YourDatabase'', @cleanup_targets = ''custom'', @custom_query_filter = N''%my_noisy_query%'';' UNION ALL
        SELECT  '' UNION ALL
        SELECT  '/* combine targets */' UNION ALL
        SELECT  'EXECUTE dbo.sp_QueryStoreCleanup @database_name = N''YourDatabase'', @cleanup_targets = ''system,maint'';' UNION ALL
        SELECT  '' UNION ALL
        SELECT  '/* text-only removal, no deduplication required */' UNION ALL
        SELECT  'EXECUTE dbo.sp_QueryStoreCleanup @database_name = N''YourDatabase'', @cleanup_targets = ''system'', @dedupe_by = ''none'';' UNION ALL
        SELECT  '' UNION ALL
        SELECT  '/* only remove queries not executed in 30+ days */' UNION ALL
        SELECT  'EXECUTE dbo.sp_QueryStoreCleanup @database_name = N''YourDatabase'', @min_age_days = 30;' UNION ALL
        SELECT  '' UNION ALL
        SELECT  '/* split a long removal across two sessions: run both at the same time */' UNION ALL
        SELECT  'EXECUTE dbo.sp_QueryStoreCleanup @database_name = N''YourDatabase'', @cleanup_targets = ''custom'', @custom_query_filter = N''%my_noisy_query%'', @dedupe_by = ''none'', @sort_direction = ''ASC'';' UNION ALL
        SELECT  'EXECUTE dbo.sp_QueryStoreCleanup @database_name = N''YourDatabase'', @cleanup_targets = ''custom'', @custom_query_filter = N''%my_noisy_query%'', @dedupe_by = ''none'', @sort_direction = ''DESC'';' UNION ALL
        SELECT  '' UNION ALL
        SELECT  '/* emergency flush: remove all noise older than 7 days */' UNION ALL
        SELECT  'EXECUTE dbo.sp_QueryStoreCleanup @database_name = N''YourDatabase'', @dedupe_by = ''none'', @min_age_days = 7;';

        /*
        MIT License
        */
        RAISERROR('
MIT License

Copyright 2026 Darling Data, LLC
https://www.erikdarling.com/

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
', 0, 1) WITH NOWAIT;

        RETURN;
    END; /*End help section*/

    /*
    Variable declarations
    */
    DECLARE
        @sql nvarchar(max) = N'',
        @database_name_quoted sysname = N'',
        @actual_state integer = NULL,
        @has_query_store_hints bit = 0,
        @include_system bit = 0,
        @include_maintenance bit = 0,
        @include_custom bit = 0,
        @no_text_filter bit = 0,
        @dedupe_query_hash bit = 0,
        @dedupe_plan_hash bit = 0,
        @no_dedupe bit = 0,
        @text_filter nvarchar(max) = N'',
        @exists_clause nvarchar(max) = N'',
        @removal_filters nvarchar(max) = N'',
        @age_cutoff datetime = NULL,
        @text_target_count bigint = 0,
        @query_hash_dupe_count bigint = 0,
        @plan_hash_dupe_count bigint = 0,
        @removal_count bigint = 0,
        @remove_sql nvarchar(max) = N'',
        @error_message nvarchar(4000) = N'',
        @c CURSOR,
        @query_id bigint,
        @current bigint = 0,
        @removed bigint = 0,
        @skipped bigint = 0,
        @was_removed tinyint = 0,
        @is_parent bit = 0,
        @has_query_variants bit = 0,
        @variant_parents_kept bigint = 0,
        @variant_waits bigint = 0,
        @failed bigint = 0,
        @query_store_queries bigint = 0,
        @database_id integer = NULL,
        @search_text nvarchar(200) = N'',
        @pattern_open nvarchar(10) = N'',
        @pattern_close nvarchar(50) = N') COLLATE Latin1_General_100_BIN2';

    /*
    Default database to current
    */
    IF @database_name IS NULL
    BEGIN
        SELECT
            @database_name = DB_NAME();
    END;

    /*
    Validate database exists
    */
    IF DB_ID(@database_name) IS NULL
    BEGIN
        RAISERROR('Database %s does not exist.', 16, 1, @database_name) WITH NOWAIT;
        RETURN;
    END;

    SELECT
        @database_name_quoted = QUOTENAME(@database_name),
        @database_id = DB_ID(@database_name);

    /*
    Check Query Store is enabled
    */
    SELECT
        @sql = N'
SELECT
    @actual_state = dqso.actual_state
FROM ' + @database_name_quoted + N'.sys.database_query_store_options AS dqso
OPTION(RECOMPILE);';

    IF @debug = 1
    BEGIN
        RAISERROR('/* Query Store check */', 0, 1) WITH NOWAIT;
        PRINT @sql;
    END;

    EXECUTE sys.sp_executesql
        @sql,
        N'@actual_state integer OUTPUT',
        @actual_state OUTPUT;

    IF @actual_state IS NULL
    OR @actual_state = 0
    BEGIN
        RAISERROR('Query Store is not enabled for database %s.', 16, 1, @database_name) WITH NOWAIT;
        RETURN;
    END;

    /*
    Reject any state where Query Store cannot accept writes. sp_query_store_remove_query
    modifies Query Store data; calling it against a READ_ONLY (1) or ERROR (3) database
    fails once per target in the cursor, producing noisy error output and leaving the
    caller with no useful result. Catch it up front instead. Only actual_state = 2
    (READ_WRITE) is safe for cleanup.
    */
    IF @actual_state = 1
    BEGIN
        RAISERROR('Query Store is in READ_ONLY state for database %s. Writes are blocked, so cleanup cannot run. This is typically caused by hitting MAX_STORAGE_SIZE_MB or by an explicit READ_ONLY operation_mode.', 16, 1, @database_name) WITH NOWAIT;
        RETURN;
    END;

    IF @actual_state = 3
    BEGIN
        RAISERROR('Query Store is in ERROR state for database %s. Cleanup cannot run until Query Store is recovered (see sys.database_query_store_options.readonly_reason).', 16, 1, @database_name) WITH NOWAIT;
        RETURN;
    END;

    /*
    sys.query_store_query_hints is SQL Server 2022+ only (same probe pattern
    sp_QuickieStore uses for its 2022-era catalog views). A query with a
    forced hint gets the same removal protection as a query with a forced
    plan, but only where the view exists to check.
    */
    IF EXISTS
    (
        SELECT
            1/0
        FROM sys.all_objects AS ao
        WHERE ao.name = N'query_store_query_hints'
    )
    BEGIN
        SELECT
            @has_query_store_hints = 1;
    END;

    /*
    sys.query_store_query_variant is SQL Server 2022+ only. A parameter
    sensitive plan (PSP) parent query cannot be removed while any of its
    variant queries remain (Msg 12465), so parents need special handling.
    */
    IF EXISTS
    (
        SELECT
            1/0
        FROM sys.all_objects AS ao
        WHERE ao.name = N'query_store_query_variant'
    )
    BEGIN
        SELECT
            @has_query_variants = 1;
    END;

    /*
    Parse @cleanup_targets
    */
    SELECT
        @cleanup_targets = LOWER(LTRIM(RTRIM(@cleanup_targets)));

    IF @cleanup_targets = 'all'
    BEGIN
        SELECT
            @include_system = 1,
            @include_maintenance = 1;

        IF @custom_query_filter IS NOT NULL
        BEGIN
            SELECT
                @include_custom = 1;
        END;
    END;
    ELSE IF @cleanup_targets = 'none'
    BEGIN
        SELECT
            @no_text_filter = 1;
    END;
    ELSE
    BEGIN
        IF CHARINDEX('system', @cleanup_targets) > 0
        BEGIN
            SELECT
                @include_system = 1;
        END;

        /*
        CHARINDEX('maint', ...) matches maint, maintenance, etc.
        */
        IF CHARINDEX('maint', @cleanup_targets) > 0
        BEGIN
            SELECT
                @include_maintenance = 1;
        END;

        IF CHARINDEX('custom', @cleanup_targets) > 0
        BEGIN
            SELECT
                @include_custom = 1;
        END;
    END;

    /*
    Validate custom filter
    */
    IF  @include_custom = 1
    AND @custom_query_filter IS NULL
    BEGIN
        RAISERROR('@custom_query_filter is required when @cleanup_targets includes ''custom''.', 16, 1) WITH NOWAIT;
        RETURN;
    END;

    /*
    Validate at least one target is set
    */
    IF  @no_text_filter = 0
    AND @include_system = 0
    AND @include_maintenance = 0
    AND @include_custom = 0
    BEGIN
        RAISERROR('No valid cleanup targets specified. Use all, system, maintenance, custom, or none.', 16, 1) WITH NOWAIT;
        RETURN;
    END;

    /*
    Parse @dedupe_by
    */
    SELECT
        @dedupe_by = LOWER(LTRIM(RTRIM(@dedupe_by)));

    IF @dedupe_by = 'all'
    BEGIN
        SELECT
            @dedupe_query_hash = 1,
            @dedupe_plan_hash = 1;
    END;
    ELSE IF @dedupe_by = 'query_hash'
    BEGIN
        SELECT
            @dedupe_query_hash = 1;
    END;
    ELSE IF @dedupe_by = 'plan_hash'
    BEGIN
        SELECT
            @dedupe_plan_hash = 1;
    END;
    ELSE IF @dedupe_by = 'none'
    BEGIN
        SELECT
            @no_dedupe = 1;
    END;
    ELSE
    BEGIN
        RAISERROR('@dedupe_by must be all, query_hash, plan_hash, or none. You passed: %s', 16, 1, @dedupe_by) WITH NOWAIT;
        RETURN;
    END;

    /*
    Validate that @cleanup_targets and @dedupe_by aren't both none
    That would remove every query in query store
    */
    IF  @no_text_filter = 1
    AND @no_dedupe = 1
    BEGIN
        RAISERROR('@cleanup_targets = ''none'' and @dedupe_by = ''none'' would remove every query in query store. That''s probably not what you want.', 16, 1) WITH NOWAIT;
        RETURN;
    END;

    /*
    Validate @min_age_days
    A negative value would push @age_cutoff into the future, which would
    silently disable the age filter instead of erroring, since nothing
    has a last_execution_time in the future.
    */
    IF @min_age_days <= 0
    BEGIN
        RAISERROR('@min_age_days must be a positive integer. You passed: %d', 16, 1, @min_age_days) WITH NOWAIT;
        RETURN;
    END;

    /*
    Validate @sort_direction
    */
    SELECT
        @sort_direction = UPPER(ISNULL(@sort_direction, 'ASC'));

    IF @sort_direction NOT IN ('ASC', 'DESC')
    BEGIN
        RAISERROR('@sort_direction must be ASC or DESC. You passed: %s', 16, 1, @sort_direction) WITH NOWAIT;
        RETURN;
    END;

    /*
    Create temp tables
    */
    CREATE TABLE
        #text_targets
    (
        query_text_id bigint NOT NULL PRIMARY KEY
    );

    CREATE TABLE
        #query_hash_dupes
    (
        query_hash binary(8) NOT NULL,
        total_plans bigint NOT NULL
    );

    CREATE TABLE
        #plan_hash_dupes
    (
        query_plan_hash binary(8) NOT NULL,
        total_plans bigint NOT NULL
    );

    CREATE TABLE
        #removals
    (
        query_id bigint NOT NULL PRIMARY KEY,
        is_parent bit NOT NULL DEFAULT 0
    );

    CREATE TABLE
        #query_variants
    (
        parent_query_id bigint NOT NULL,
        query_variant_query_id bigint NOT NULL
    );

    /*
    Step 1: Find text targets
    */
    IF @no_text_filter = 0
    BEGIN
        /*
        Text search runs under a binary collation, which is several times
        cheaper than a linguistic LIKE over query_sql_text. When the
        database collation ignores case, both sides are upper-cased first
        so the matches stay the same.
        */
        IF CONVERT
           (
               integer,
               COLLATIONPROPERTY
               (
                   CONVERT(sysname, DATABASEPROPERTYEX(@database_name, 'Collation')),
                   'ComparisonStyle'
               )
           ) & 1 = 1
        BEGIN
            SELECT
                @search_text = N'UPPER(qsqt.query_sql_text) COLLATE Latin1_General_100_BIN2',
                @pattern_open = N'UPPER(';
        END;
        ELSE
        BEGIN
            SELECT
                @search_text = N'qsqt.query_sql_text COLLATE Latin1_General_100_BIN2',
                @pattern_open = N'(';
        END;

        /*
        Build text filter WHERE clause
        Each condition is prefixed with newline + "OR    " (7 chars)
        so we can STUFF off the leading OR and prepend WHERE
        */
        IF @include_system = 1
        BEGIN
            SELECT
                @text_filter += N'
OR    st.search_text LIKE ' + @pattern_open + N'N''%FROM sys.%''' + @pattern_close;
        END;

        /*
        Maintenance patterns from sp_QuickieStore:
        index rebuilds, stats updates, DBCC, StatMan, maintenance plan params
        */
        IF @include_maintenance = 1
        BEGIN
            SELECT
                @text_filter += N'
OR    st.search_text LIKE ' + @pattern_open + N'N''ALTER INDEX%''' + @pattern_close + N'
OR    st.search_text LIKE ' + @pattern_open + N'N''ALTER TABLE%''' + @pattern_close + N'
OR    st.search_text LIKE ' + @pattern_open + N'N''CREATE%INDEX%''' + @pattern_close + N'
OR    st.search_text LIKE ' + @pattern_open + N'N''CREATE STATISTICS%''' + @pattern_close + N'
OR    st.search_text LIKE ' + @pattern_open + N'N''UPDATE STATISTICS%''' + @pattern_close + N'
OR    st.search_text LIKE ' + @pattern_open + N'N''%SELECT StatMan%''' + @pattern_close + N'
OR    st.search_text LIKE ' + @pattern_open + N'N''DBCC%''' + @pattern_close + N'
OR    st.search_text LIKE ' + @pattern_open + N'N''(@[_]msparam%''' + @pattern_close;
        END;

        IF @include_custom = 1
        BEGIN
            SELECT
                @text_filter += N'
OR    st.search_text LIKE ' + @pattern_open + N'@custom_query_filter' + @pattern_close;
        END;

        /*
        Remove leading newline + "OR    " (7 chars) and prepend WHERE
        */
        SELECT
            @text_filter = N'WHERE ' + STUFF(@text_filter, 1, 7, N'');

        SELECT
            @sql = N'
INSERT
    #text_targets
WITH
    (TABLOCK)
(
    query_text_id
)
SELECT
    qsqt.query_text_id
FROM ' + @database_name_quoted + N'.sys.query_store_query_text AS qsqt
CROSS APPLY
(
    SELECT
        search_text = ' + @search_text + N'
) AS st
' + @text_filter + N'
OPTION(RECOMPILE);';

        IF @debug = 1
        BEGIN
            RAISERROR('/* Step 1: Find text targets */', 0, 1) WITH NOWAIT;
            PRINT @sql;
        END;

        EXECUTE sys.sp_executesql
            @sql,
            N'@custom_query_filter nvarchar(1024)',
            @custom_query_filter;

        SELECT
            @text_target_count = ROWCOUNT_BIG();

        RAISERROR('Found %I64d query texts matching cleanup targets', 0, 1, @text_target_count) WITH NOWAIT;

        IF @debug = 1
        BEGIN
            SELECT
                tt.*
            FROM #text_targets AS tt;
        END;

        IF @text_target_count = 0
        BEGIN
            RAISERROR('No matching query texts found. Exiting.', 0, 1) WITH NOWAIT;
            RETURN;
        END;
    END;

    /*
    Step 2: Find query_hash duplicates
    */
    IF @dedupe_query_hash = 1
    BEGIN
        SELECT
            @sql = N'
INSERT
    #query_hash_dupes
WITH
    (TABLOCK)
(
    query_hash,
    total_plans
)
SELECT
    qsq.query_hash,
    total_plans = COUNT_BIG(DISTINCT qsq.query_id)
FROM ' + @database_name_quoted + N'.sys.query_store_runtime_stats AS qsrs
JOIN ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
  ON qsrs.plan_id = qsp.plan_id
JOIN ' + @database_name_quoted + N'.sys.query_store_query AS qsq
  ON qsp.query_id = qsq.query_id
WHERE qsp.is_forced_plan = 0' +
        CASE
            WHEN @has_query_store_hints = 1
            THEN N'
AND   NOT EXISTS
      (
          SELECT
              1/0
          FROM ' + @database_name_quoted + N'.sys.query_store_query_hints AS qsqh
          WHERE qsqh.query_id = qsq.query_id
      )'
            ELSE N''
        END +
        CASE
            WHEN @no_text_filter = 0
            THEN N'
AND   EXISTS
      (
          SELECT
              1/0
          FROM #text_targets AS tt
          WHERE tt.query_text_id = qsq.query_text_id
      )'
            ELSE N''
        END + N'
GROUP BY
    qsq.query_hash
HAVING
    COUNT_BIG(DISTINCT qsq.query_id) > 1
OPTION(RECOMPILE);';

        IF @debug = 1
        BEGIN
            RAISERROR('/* Step 2: Find query_hash duplicates */', 0, 1) WITH NOWAIT;
            PRINT @sql;
        END;

        EXECUTE sys.sp_executesql
            @sql;

        SELECT
            @query_hash_dupe_count = ROWCOUNT_BIG();

        RAISERROR('Found %I64d duplicate query hashes', 0, 1, @query_hash_dupe_count) WITH NOWAIT;

        IF @debug = 1
        BEGIN
            SELECT
                qd.*
            FROM #query_hash_dupes AS qd;
        END;
    END;

    /*
    Step 3: Find plan_hash duplicates
    */
    IF @dedupe_plan_hash = 1
    BEGIN
        SELECT
            @sql = N'
INSERT
    #plan_hash_dupes
WITH
    (TABLOCK)
(
    query_plan_hash,
    total_plans
)
SELECT
    qsp.query_plan_hash,
    total_plans = COUNT_BIG(DISTINCT qsp.plan_id)
FROM ' + @database_name_quoted + N'.sys.query_store_runtime_stats AS qsrs
JOIN ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
  ON qsrs.plan_id = qsp.plan_id
JOIN ' + @database_name_quoted + N'.sys.query_store_query AS qsq
  ON qsp.query_id = qsq.query_id
WHERE qsp.is_forced_plan = 0' +
        CASE
            WHEN @has_query_store_hints = 1
            THEN N'
AND   NOT EXISTS
      (
          SELECT
              1/0
          FROM ' + @database_name_quoted + N'.sys.query_store_query_hints AS qsqh
          WHERE qsqh.query_id = qsq.query_id
      )'
            ELSE N''
        END +
        CASE
            WHEN @no_text_filter = 0
            THEN N'
AND   EXISTS
      (
          SELECT
              1/0
          FROM #text_targets AS tt
          WHERE tt.query_text_id = qsq.query_text_id
      )'
            ELSE N''
        END + N'
GROUP BY
    qsp.query_plan_hash
HAVING
    COUNT_BIG(DISTINCT qsp.plan_id) > 1
OPTION(RECOMPILE);';

        IF @debug = 1
        BEGIN
            RAISERROR('/* Step 3: Find plan_hash duplicates */', 0, 1) WITH NOWAIT;
            PRINT @sql;
        END;

        EXECUTE sys.sp_executesql
            @sql;

        SELECT
            @plan_hash_dupe_count = ROWCOUNT_BIG();

        RAISERROR('Found %I64d duplicate plan hashes', 0, 1, @plan_hash_dupe_count) WITH NOWAIT;

        IF @debug = 1
        BEGIN
            SELECT
                qd.*
            FROM #plan_hash_dupes AS qd;
        END;
    END;

    /*
    Check if any duplicates were found (skip when @no_dedupe = 1)
    */
    IF  @no_dedupe = 0
    AND @query_hash_dupe_count = 0
    AND @plan_hash_dupe_count = 0
    BEGIN
        RAISERROR('No duplicates found. Exiting.', 0, 1) WITH NOWAIT;
        RETURN;
    END;

    /*
    Build removal filters applied to both Step 4 paths:
    forced plan protection + forced hint protection + optional age filter
    */
    SELECT
        @removal_filters = N'
AND   NOT EXISTS
      (
          SELECT
              1/0
          FROM ' + @database_name_quoted + N'.sys.query_store_plan AS qsp_forced
          WHERE qsp_forced.query_id = qsq.query_id
          AND   qsp_forced.is_forced_plan = 1
      )';

    IF @has_query_store_hints = 1
    BEGIN
        SELECT
            @removal_filters += N'
AND   NOT EXISTS
      (
          SELECT
              1/0
          FROM ' + @database_name_quoted + N'.sys.query_store_query_hints AS qsqh_forced
          WHERE qsqh_forced.query_id = qsq.query_id
      )';
    END;

    IF @min_age_days IS NOT NULL
    BEGIN
        SELECT
            @age_cutoff = DATEADD(DAY, -@min_age_days, GETUTCDATE());

        SELECT
            @removal_filters += N'
AND   NOT EXISTS
      (
          SELECT
              1/0
          FROM ' + @database_name_quoted + N'.sys.query_store_plan AS qsp_age
          WHERE qsp_age.query_id = qsq.query_id
          AND   qsp_age.last_execution_time > @age_cutoff
      )';
    END;

    /*
    Step 4: Build removal list
    */
    IF @no_dedupe = 1
    BEGIN
        /*
        No deduplication: all text-matched queries go directly to removal
        */
        SELECT
            @sql = N'
INSERT
    #removals
WITH
    (TABLOCK)
(
    query_id
)
SELECT DISTINCT
    qsq.query_id
FROM ' + @database_name_quoted + N'.sys.query_store_query AS qsq
WHERE EXISTS
      (
          SELECT
              1/0
          FROM #text_targets AS tt
          WHERE tt.query_text_id = qsq.query_text_id
      )' + @removal_filters + N'
OPTION(RECOMPILE, HASH JOIN);';
    END;
    ELSE
    BEGIN
        /*
        Build the EXISTS clause based on which strategies found results
        */
        IF  @dedupe_query_hash = 1
        AND @query_hash_dupe_count > 0
        BEGIN
            SELECT
                @exists_clause += N'
    SELECT
        1/0
    FROM #query_hash_dupes AS qd
    WHERE qd.query_hash = qsq.query_hash';
        END;

        IF  @dedupe_plan_hash = 1
        AND @plan_hash_dupe_count > 0
        BEGIN
            IF LEN(@exists_clause) > 0
            BEGIN
                SELECT
                    @exists_clause += N'

    UNION ALL
';
            END;

            SELECT
                @exists_clause += N'
    SELECT
        1/0
    FROM #plan_hash_dupes AS qd
    WHERE qd.query_plan_hash = qsp.query_plan_hash';
        END;

        SELECT
            @sql = N'
INSERT
    #removals
WITH
    (TABLOCK)
(
    query_id
)
SELECT DISTINCT
    qsp.query_id
FROM ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
JOIN ' + @database_name_quoted + N'.sys.query_store_query AS qsq
  ON qsp.query_id = qsq.query_id
WHERE EXISTS
      (' + @exists_clause + N'
      )' + @removal_filters + N'
OPTION(RECOMPILE, HASH JOIN);';
    END;

    IF @debug = 1
    BEGIN
        RAISERROR('/* Step 4: Build removal list */', 0, 1) WITH NOWAIT;
        PRINT @sql;
    END;

    EXECUTE sys.sp_executesql
        @sql,
        N'@age_cutoff datetime',
        @age_cutoff;

    SELECT
        @removal_count = ROWCOUNT_BIG();

    /*
    PSP parents: a parent can only be removed after all of its variants.
    Drop parents with a variant that is not on the list, since removing
    them would fail every time, and mark the rest so they go last.
    */
    IF  @has_query_variants = 1
    AND @removal_count > 0
    BEGIN
        SELECT
            @sql = N'
INSERT
    #query_variants
WITH
    (TABLOCK)
(
    parent_query_id,
    query_variant_query_id
)
SELECT
    qsqv.parent_query_id,
    qsqv.query_variant_query_id
FROM ' + @database_name_quoted + N'.sys.query_store_query_variant AS qsqv
WHERE EXISTS
      (
          SELECT
              1/0
          FROM #removals AS r
          WHERE r.query_id = qsqv.parent_query_id
      )
OPTION(RECOMPILE, HASH JOIN);';

        IF @debug = 1
        BEGIN
            RAISERROR('/* Step 4b: PSP variants of parents on the list */', 0, 1) WITH NOWAIT;
            PRINT @sql;
        END;

        EXECUTE sys.sp_executesql
            @sql;

        DELETE
            r
        FROM #removals AS r
        WHERE EXISTS
              (
                  SELECT
                      1/0
                  FROM #query_variants AS qv
                  WHERE qv.parent_query_id = r.query_id
                  AND   NOT EXISTS
                        (
                            SELECT
                                1/0
                            FROM #removals AS r2
                            WHERE r2.query_id = qv.query_variant_query_id
                        )
              )
        OPTION(RECOMPILE);

        SELECT
            @variant_parents_kept = ROWCOUNT_BIG();

        UPDATE
            r
        SET
            r.is_parent = 1
        FROM #removals AS r
        WHERE EXISTS
              (
                  SELECT
                      1/0
                  FROM #query_variants AS qv
                  WHERE qv.parent_query_id = r.query_id
              )
        OPTION(RECOMPILE);

        SELECT
            @removal_count -= @variant_parents_kept;

        IF @variant_parents_kept > 0
        BEGIN
            RAISERROR('Kept %I64d PSP parent queries that have a variant not on the removal list. A parent cannot be removed while any variant remains.', 0, 1, @variant_parents_kept) WITH NOWAIT;
        END;
    END;

    RAISERROR('Found %I64d queries to remove', 0, 1, @removal_count) WITH NOWAIT;

    IF @debug = 1
    BEGIN
        SELECT
            r.*
        FROM #removals AS r;
    END;

    IF @removal_count = 0
    BEGIN
        RAISERROR('No queries to remove. Exiting.', 0, 1) WITH NOWAIT;
        RETURN;
    END;

    /*
    Step 5: Report or remove
    */
    IF @report_only = 1
    BEGIN
        /*
        Report mode: summarize what would be removed.
        Each Query Store view goes into its own temp table first,
        and only the temp tables are joined.
        */
        CREATE TABLE
            #report_queries
        (
            query_id bigint NOT NULL,
            query_hash binary(8) NOT NULL,
            query_text_id bigint NOT NULL,
            object_id bigint NOT NULL,
            last_execution_time datetimeoffset(7) NULL
        );

        CREATE TABLE
            #report_plans
        (
            plan_id bigint NOT NULL,
            query_id bigint NOT NULL,
            query_plan_hash binary(8) NOT NULL
        );

        CREATE TABLE
            #report_groups
        (
            query_hash binary(8) NOT NULL,
            queries bigint NOT NULL,
            query_texts bigint NOT NULL,
            plans bigint NOT NULL,
            plan_hashes bigint NOT NULL,
            object_id bigint NOT NULL,
            oldest_last_execution datetimeoffset(7) NULL,
            newest_last_execution datetimeoffset(7) NULL,
            sample_query_id bigint NOT NULL
        );

        SELECT
            @sql = N'
INSERT
    #report_queries
WITH
    (TABLOCK)
(
    query_id,
    query_hash,
    query_text_id,
    object_id,
    last_execution_time
)
SELECT
    qsq.query_id,
    qsq.query_hash,
    qsq.query_text_id,
    qsq.object_id,
    qsq.last_execution_time
FROM ' + @database_name_quoted + N'.sys.query_store_query AS qsq
WHERE EXISTS
      (
          SELECT
              1/0
          FROM #removals AS r
          WHERE r.query_id = qsq.query_id
      )
OPTION(RECOMPILE, HASH JOIN);

INSERT
    #report_plans
WITH
    (TABLOCK)
(
    plan_id,
    query_id,
    query_plan_hash
)
SELECT
    qsp.plan_id,
    qsp.query_id,
    qsp.query_plan_hash
FROM ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
WHERE EXISTS
      (
          SELECT
              1/0
          FROM #removals AS r
          WHERE r.query_id = qsp.query_id
      )
OPTION(RECOMPILE, HASH JOIN);

SELECT
    @query_store_queries = COUNT_BIG(*)
FROM ' + @database_name_quoted + N'.sys.query_store_query AS qsq
OPTION(RECOMPILE);';

        IF @debug = 1
        BEGIN
            RAISERROR('/* Step 5: Report staging */', 0, 1) WITH NOWAIT;
            PRINT @sql;
        END;

        EXECUTE sys.sp_executesql
            @sql,
            N'@query_store_queries bigint OUTPUT',
            @query_store_queries OUTPUT;

        /*
        One row per query_hash, with the plan counts rolled up from #report_plans
        */
        INSERT
            #report_groups
        WITH
            (TABLOCK)
        (
            query_hash,
            queries,
            query_texts,
            plans,
            plan_hashes,
            object_id,
            oldest_last_execution,
            newest_last_execution,
            sample_query_id
        )
        SELECT
            rq.query_hash,
            queries = COUNT_BIG(*),
            query_texts = COUNT_BIG(DISTINCT rq.query_text_id),
            plans = MAX(ISNULL(p.plans, 0)),
            plan_hashes = MAX(ISNULL(p.plan_hashes, 0)),
            object_id = MAX(rq.object_id),
            oldest_last_execution = MIN(rq.last_execution_time),
            newest_last_execution = MAX(rq.last_execution_time),
            sample_query_id = MAX(rq.query_id)
        FROM #report_queries AS rq
        LEFT JOIN
        (
            SELECT
                rq2.query_hash,
                plans = COUNT_BIG(*),
                plan_hashes = COUNT_BIG(DISTINCT rp.query_plan_hash)
            FROM #report_plans AS rp
            JOIN #report_queries AS rq2
              ON rq2.query_id = rp.query_id
            GROUP BY
                rq2.query_hash
        ) AS p
          ON p.query_hash = rq.query_hash
        GROUP BY
            rq.query_hash
        OPTION(RECOMPILE);

        /*
        Summary: one row for the whole removal list
        */
        SELECT
            queries_to_remove = COUNT_BIG(*),
            query_hashes = COUNT_BIG(DISTINCT rq.query_hash),
            query_texts = COUNT_BIG(DISTINCT rq.query_text_id),
            plans =
            (
                SELECT
                    COUNT_BIG(*)
                FROM #report_plans AS rp
            ),
            plan_hashes =
            (
                SELECT
                    COUNT_BIG(DISTINCT rp.query_plan_hash)
                FROM #report_plans AS rp
            ),
            queries_in_modules =
                SUM
                (
                    CASE
                        WHEN rq.object_id <> 0
                        THEN 1
                        ELSE 0
                    END
                ),
            oldest_last_execution = MIN(rq.last_execution_time),
            newest_last_execution = MAX(rq.last_execution_time),
            psp_parents_to_remove =
            (
                SELECT
                    COUNT_BIG(*)
                FROM #removals AS r
                WHERE r.is_parent = 1
            ),
            psp_parents_kept = @variant_parents_kept,
            query_store_queries = @query_store_queries,
            percent_of_query_store =
                CONVERT
                (
                    decimal(5,2),
                    COUNT_BIG(*) * 100. / NULLIF(@query_store_queries, 0)
                )
        FROM #report_queries AS rq
        OPTION(RECOMPILE);

        /*
        Groups: one row per query_hash, biggest first, with a sample of the text
        */
        SELECT
            @sql = N'
SELECT
    rg.query_hash,
    rg.queries,
    rg.query_texts,
    rg.plans,
    rg.plan_hashes,
    object_name =
        CASE
            WHEN rg.object_id <> 0
            THEN OBJECT_SCHEMA_NAME(rg.object_id, @database_id) +
                 N''.'' +
                 OBJECT_NAME(rg.object_id, @database_id)
        END,
    rg.oldest_last_execution,
    rg.newest_last_execution,
    rg.sample_query_id,
    sample_query_sql_text =
        SUBSTRING
        (
            qsqt.query_sql_text,
            1,
            200
        )
FROM #report_groups AS rg
JOIN #report_queries AS rq
  ON rq.query_id = rg.sample_query_id
JOIN ' + @database_name_quoted + N'.sys.query_store_query_text AS qsqt
  ON qsqt.query_text_id = rq.query_text_id
ORDER BY
    rg.queries DESC,
    rg.query_hash
OPTION(RECOMPILE);';

        IF @debug = 1
        BEGIN
            RAISERROR('/* Step 5: Report groups */', 0, 1) WITH NOWAIT;
            PRINT @sql;
        END;

        EXECUTE sys.sp_executesql
            @sql,
            N'@database_id integer',
            @database_id;

        RAISERROR('%I64d queries would be removed (report only mode)', 0, 1, @removal_count) WITH NOWAIT;
        RETURN;
    END;

    /*
    Removal mode: cursor through and remove each query
    */
    /*
    Skip queries that are already gone, so two sessions working
    from opposite ends don't each retry the other's half
    */
    /*
    PSP parents go last, and are skipped without a removal attempt if a
    variant is still there (another session may not have reached it yet)
    */
    SELECT
        @remove_sql = N'
IF EXISTS
(
    SELECT
        1/0
    FROM ' + @database_name_quoted + N'.sys.query_store_query AS qsq
    WHERE qsq.query_id = @query_id
)
BEGIN' +
        CASE
            WHEN @has_query_variants = 1
            THEN N'
    IF  @is_parent = 1
    AND EXISTS
        (
            SELECT
                1/0
            FROM ' + @database_name_quoted + N'.sys.query_store_query_variant AS qsqv
            WHERE qsqv.parent_query_id = @query_id
        )
    BEGIN
        SELECT
            @was_removed = 2;

        RETURN;
    END;
'
            ELSE N''
        END + N'
    EXECUTE ' + @database_name_quoted + N'.sys.sp_query_store_remove_query
        @query_id = @query_id;

    SELECT
        @was_removed = 1;
END;';

    IF @debug = 1
    BEGIN
        RAISERROR('/* Remove SQL */', 0, 1) WITH NOWAIT;
        PRINT @remove_sql;
    END;

    IF @sort_direction = 'DESC'
    BEGIN
        SET @c =
            CURSOR
            LOCAL
            DYNAMIC
            READ_ONLY
            FORWARD_ONLY
        FOR
        SELECT
            r.query_id,
            r.is_parent
        FROM #removals AS r
        ORDER BY
            r.is_parent,
            r.query_id DESC;
    END;
    ELSE
    BEGIN
        SET @c =
            CURSOR
            LOCAL
            DYNAMIC
            READ_ONLY
            FORWARD_ONLY
        FOR
        SELECT
            r.query_id,
            r.is_parent
        FROM #removals AS r
        ORDER BY
            r.is_parent,
            r.query_id ASC;
    END;

    OPEN @c;

    FETCH NEXT
    FROM @c
    INTO
        @query_id,
        @is_parent;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SELECT
            @current += 1;

        BEGIN TRY
            SELECT
                @was_removed = 0;

            EXECUTE sys.sp_executesql
                @remove_sql,
                N'@query_id bigint, @is_parent bit, @was_removed tinyint OUTPUT',
                @query_id,
                @is_parent,
                @was_removed OUTPUT;

            IF @was_removed = 1
            BEGIN
                SELECT
                    @removed += 1;

                RAISERROR('Query %I64d of %I64d: query_id %I64d removed', 0, 1, @current, @removal_count, @query_id) WITH NOWAIT;
            END;
            ELSE IF @was_removed = 2
            BEGIN
                SELECT
                    @variant_waits += 1;

                RAISERROR('Query %I64d of %I64d: query_id %I64d skipped (PSP parent, variants still present)', 0, 1, @current, @removal_count, @query_id) WITH NOWAIT;
            END;
            ELSE
            BEGIN
                SELECT
                    @skipped += 1;

                RAISERROR('Query %I64d of %I64d: query_id %I64d skipped (already gone)', 0, 1, @current, @removal_count, @query_id) WITH NOWAIT;
            END;
        END TRY
        BEGIN CATCH
            SELECT
                @failed += 1,
                @error_message = ERROR_MESSAGE();

            RAISERROR('Query %I64d of %I64d: query_id %I64d not removed (%s)', 0, 1, @current, @removal_count, @query_id, @error_message) WITH NOWAIT;
        END CATCH;

        FETCH NEXT
        FROM @c
        INTO
            @query_id,
            @is_parent;
    END;

    RAISERROR('Finished: %I64d of %I64d removed (%I64d skipped, %I64d PSP parents waiting on variants, %I64d failed)', 0, 1, @removed, @removal_count, @skipped, @variant_waits, @failed) WITH NOWAIT;

END;
GO
