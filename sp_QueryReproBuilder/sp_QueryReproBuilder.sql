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


CREATE OR ALTER PROCEDURE
    dbo.sp_QueryReproBuilder
(
    @database_name sysname = NULL, /*the name of the database you want to look at query store in*/
    @start_date datetimeoffset(7) = NULL, /*the begin date of your search, will be converted to UTC internally*/
    @end_date datetimeoffset(7) = NULL, /*the end date of your search, will be converted to UTC internally*/
    @include_plan_ids nvarchar(4000) = NULL, /*a list of query ids to search for*/
    @include_query_ids nvarchar(4000) = NULL, /*a list of plan ids to search for*/
    @ignore_plan_ids nvarchar(4000) = NULL, /*a list of plan ids to ignore*/
    @ignore_query_ids nvarchar(4000) = NULL, /*a list of query ids to ignore*/
    @procedure_schema sysname = NULL, /*the schema of the procedure you're searching for*/
    @procedure_name sysname = NULL, /*the name of the programmable object you're searching for*/
    @query_text_search nvarchar(4000) = NULL, /*query text to search for*/
    @query_text_search_not nvarchar(4000) = NULL, /*query text to exclude*/
    @help bit = 0, /*return available parameter details, etc.*/
    @debug bit = 0, /*prints dynamic sql, statement length, parameter and variable values, and raw temp table contents*/
    @version varchar(30) = NULL OUTPUT, /*OUTPUT; for support*/
    @version_date datetime = NULL OUTPUT /*OUTPUT; for support*/
)
WITH 
    RECOMPILE
AS
BEGIN
SET STATISTICS XML OFF;
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

BEGIN TRY

/*Version*/
SELECT
    @version = '0',
    @version_date = '20251001';

/*Help*/
IF @help = 1
BEGIN
    /*Introduction*/
    SELECT
        introduction =
           'hi, i''m sp_QueryReproBuilder!' UNION ALL
    SELECT 'you got me from https://code.erikdarling.com' UNION ALL
    SELECT 'i help you build repro scripts from query store data' UNION ALL
    SELECT 'i extract query text and parameters from query plans' UNION ALL
    SELECT 'and set them up to run with sp_executesql' UNION ALL
    SELECT '' UNION ALL
    SELECT 'from your loving sql server consultant, erik darling: erikdarling@hey.com';

    /*Parameters*/
    SELECT
        parameter_name = ap.name,
        data_type = t.name,
        description =
            CASE
                ap.name
                WHEN N'@database_name' THEN 'the name of the database you want to look at query store in'
                WHEN N'@start_date' THEN 'the begin date of your search, will be converted to UTC internally'
                WHEN N'@end_date' THEN 'the end date of your search, will be converted to UTC internally'
                WHEN N'@include_plan_ids' THEN 'a list of plan ids to search for'
                WHEN N'@include_query_ids' THEN 'a list of query ids to search for'
                WHEN N'@ignore_plan_ids' THEN 'a list of plan ids to ignore'
                WHEN N'@ignore_query_ids' THEN 'a list of query ids to ignore'
                WHEN N'@procedure_schema' THEN 'the schema of the procedure you''re searching for'
                WHEN N'@procedure_name' THEN 'the name of the programmable object you''re searching for'
                WHEN N'@query_text_search' THEN 'query text to search for'
                WHEN N'@query_text_search_not' THEN 'query text to exclude'
                WHEN N'@help' THEN 'how you got here'
                WHEN N'@debug' THEN 'prints dynamic sql, statement length, parameter and variable values'
                WHEN N'@version' THEN 'OUTPUT; for support'
                WHEN N'@version_date' THEN 'OUTPUT; for support'
                ELSE 'not documented'
            END,
        valid_inputs =
            CASE
                ap.name
                WHEN N'@database_name' THEN 'a database name with query store enabled'
                WHEN N'@start_date' THEN 'January 1, 1753, through December 31, 9999'
                WHEN N'@end_date' THEN 'January 1, 1753, through December 31, 9999'
                WHEN N'@include_plan_ids' THEN 'a string; comma separated for multiple ids'
                WHEN N'@include_query_ids' THEN 'a string; comma separated for multiple ids'
                WHEN N'@ignore_plan_ids' THEN 'a string; comma separated for multiple ids'
                WHEN N'@ignore_query_ids' THEN 'a string; comma separated for multiple ids'
                WHEN N'@procedure_schema' THEN 'a valid schema in your database'
                WHEN N'@procedure_name' THEN 'a valid programmable object in your database'
                WHEN N'@query_text_search' THEN 'a string; leading and trailing wildcards will be added if missing'
                WHEN N'@query_text_search_not' THEN 'a string; leading and trailing wildcards will be added if missing'
                WHEN N'@help' THEN '0 or 1'
                WHEN N'@debug' THEN '0 or 1'
                WHEN N'@version' THEN 'none; OUTPUT'
                WHEN N'@version_date' THEN 'none; OUTPUT'
                ELSE 'not documented'
            END,
        defaults =
            CASE
                ap.name
                WHEN N'@database_name' THEN 'NULL; current database name if NULL'
                WHEN N'@start_date' THEN 'the last seven days'
                WHEN N'@end_date' THEN 'NULL'
                WHEN N'@include_plan_ids' THEN 'NULL'
                WHEN N'@include_query_ids' THEN 'NULL'
                WHEN N'@ignore_plan_ids' THEN 'NULL'
                WHEN N'@ignore_query_ids' THEN 'NULL'
                WHEN N'@procedure_schema' THEN 'NULL; dbo if NULL and procedure name is not NULL'
                WHEN N'@procedure_name' THEN 'NULL'
                WHEN N'@query_text_search' THEN 'NULL'
                WHEN N'@query_text_search_not' THEN 'NULL'
                WHEN N'@help' THEN '0'
                WHEN N'@debug' THEN '0'
                WHEN N'@version' THEN 'none; OUTPUT'
                WHEN N'@version_date' THEN 'none; OUTPUT'
                ELSE 'not documented'
            END
    FROM sys.all_parameters AS ap
    INNER JOIN sys.all_objects AS o
      ON ap.object_id = o.object_id
    INNER JOIN sys.types AS t
      ON  ap.system_type_id = t.system_type_id
      AND ap.user_type_id = t.user_type_id
    WHERE o.name = N'sp_QueryReproBuilder'
    OPTION(RECOMPILE);

    RETURN;
END;

/*Variables*/
DECLARE
    @sql nvarchar(MAX) = N'',
    @database_id integer,
    @database_name_quoted sysname =
        QUOTENAME(@database_name),
    @collation sysname,
    @query_store_exists bit = 'true',
    @procedure_name_quoted nvarchar(1024),
    @procedure_exists bit = 0,
    @isolation_level nvarchar(100) = 
        N'SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;' + 
        NCHAR(10),
    @nc10 nchar(1) = NCHAR(10),
    @where_clause nvarchar(MAX) = N'',
    @start_date_original datetimeoffset(7),
    @end_date_original datetimeoffset(7),
    @utc_minutes_difference bigint,
    @product_version integer,
    @azure bit = 0,
    @sql_2022_views bit = 0,
    @new bit = 0,
    @current_table nvarchar(100)

/*Fix NULL @database_name*/
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
  )
BEGIN
    SELECT
        @database_name =
            DB_NAME();
END;


/*Initialize database variables*/
SELECT
    @database_id =
        DB_ID(@database_name),
    @database_name_quoted =
        QUOTENAME(@database_name),
    @collation =
        CONVERT
        (
            sysname,
            DATABASEPROPERTYEX
            (
                @database_name,
                'Collation'
            )
        );

/*Check if database exists*/
IF
(
    @database_id IS NULL
 OR @collation IS NULL
)
BEGIN
    RAISERROR('Database %s does not exist', 10, 1, @database_name) WITH NOWAIT;
    RETURN;
END;

/*Check for Azure and get SQL Server version*/
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
    @product_version =
        CONVERT
        (
            integer,
            SUBSTRING
            (
                CONVERT
                (
                    varchar(128),
                    SERVERPROPERTY('ProductVersion')
                ),
                1,
                CHARINDEX
                (
                    '.',
                    CONVERT
                    (
                        varchar(128),
                        SERVERPROPERTY('ProductVersion')
                    )
                ) - 1
            )
        );

/*Check for SQL Server 2019+ features*/
IF
(
    @product_version >= 15
 OR @azure = 1
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

/*Check database state*/
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
OPTION(RECOMPILE);
';

EXECUTE sys.sp_executesql
    @sql,
  N'@query_store_exists bit OUTPUT',
    @query_store_exists OUTPUT;

IF @query_store_exists = 0
BEGIN
    RAISERROR('Query Store doesn''t seem to be enabled for database: %s', 10, 1, @database_name) WITH NOWAIT;
    RETURN;
END;

/*
Initialize date variables
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
        ),
    @utc_minutes_difference =
        DATEDIFF
        (
            MINUTE,
            SYSDATETIME(),
            SYSUTCDATETIME()
        );

/*
Convert dates to UTC for filtering
*/
SELECT
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
Validate date range
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
NULLIF blank strings to NULL for consistent handling
*/
SELECT
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
    @query_text_search =
        NULLIF(@query_text_search, ''),
    @query_text_search_not =
        NULLIF(@query_text_search_not, '');

/*
Parse schema from procedure name if provided in schema.procedure format
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

/*Initialize procedure variables*/
IF @procedure_name IS NOT NULL
BEGIN
    IF @procedure_schema IS NULL
    BEGIN
        SELECT
            @procedure_schema = N'dbo';
    END;

    SELECT
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
            QUOTENAME(@procedure_name);

    /*Check if procedure exists in Query Store - single procedure (no wildcards)*/
    IF CHARINDEX(N'%', @procedure_name) = 0
    BEGIN
        SELECT
            @sql = @isolation_level;

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
            N'@procedure_exists bit OUTPUT, @procedure_name_quoted nvarchar(1024)',
            @procedure_exists OUTPUT,
            @procedure_name_quoted;

        IF @procedure_exists = 0
        BEGIN
            RAISERROR('The stored procedure %s does not appear to have any entries in Query Store for database %s
Check that you spelled everything correctly and you''re in the right database',
                       10, 1, @procedure_name, @database_name) WITH NOWAIT;
            RETURN;
        END;
    END;
END;

/*
Create temp tables for filter parameters
*/
CREATE TABLE
    #include_plan_ids
(
    plan_id bigint NOT NULL,
    INDEX plan_id CLUSTERED (plan_id)
);


CREATE TABLE
    #include_query_ids
(
    query_id bigint NOT NULL,
    INDEX query_id CLUSTERED (query_id)
);

CREATE TABLE
    #ignore_plan_ids
(
    plan_id bigint NOT NULL,
    INDEX plan_id CLUSTERED (plan_id)
);

CREATE TABLE
    #ignore_query_ids
(
    query_id bigint NOT NULL,
    INDEX query_id CLUSTERED (query_id)
);

CREATE TABLE
    #query_text_search
(
    plan_id bigint NOT NULL,
    INDEX plan_id CLUSTERED (plan_id)
);


CREATE TABLE
    #query_text_search_not
(
    plan_id bigint NOT NULL,
    INDEX plan_id CLUSTERED (plan_id)
);

/*
Create Query Store temp tables
*/
CREATE TABLE
    #query_store_runtime_stats
(
    database_id integer NOT NULL,
    runtime_stats_id bigint NOT NULL,
    plan_id bigint NOT NULL,
    INDEX plan_id CLUSTERED (plan_id),
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

CREATE TABLE
    #query_store_wait_stats
(
    database_id integer NOT NULL,
    plan_id bigint NOT NULL,
    INDEX plan_id CLUSTERED (plan_id),
    wait_category_desc nvarchar(60) NOT NULL,
    total_query_wait_time_ms bigint NOT NULL,
    avg_query_wait_time_ms float NULL,
    last_query_wait_time_ms bigint NOT NULL,
    min_query_wait_time_ms bigint NOT NULL,
    max_query_wait_time_ms bigint NOT NULL
);

CREATE TABLE
    #query_store_plan_feedback
(
    database_id integer NOT NULL,
    plan_feedback_id bigint NOT NULL,
    plan_id bigint NULL,
    INDEX plan_id CLUSTERED (plan_id),
    feature_desc nvarchar(120) NULL,
    feedback_data nvarchar(max) NULL,
    state_desc nvarchar(120) NULL,
    create_time datetimeoffset(7) NOT NULL,
    last_updated_time datetimeoffset(7) NULL
);

CREATE TABLE
    #query_store_query_hints
(
    database_id integer NOT NULL,
    query_hint_id bigint NOT NULL,
    query_id bigint NOT NULL,
    INDEX query_id CLUSTERED (query_id),
    query_hint_text nvarchar(max) NULL,
    last_query_hint_failure_reason_desc nvarchar(256) NULL,
    query_hint_failure_count bigint NOT NULL,
    source_desc nvarchar(256) NULL
);

CREATE TABLE
    #query_store_query_variant
(
    database_id integer NOT NULL,
    query_variant_query_id bigint NOT NULL,
    INDEX query_variant_query_id CLUSTERED (query_variant_query_id),
    parent_query_id bigint NOT NULL,
    dispatcher_plan_id bigint NOT NULL
);

CREATE TABLE
    #query_context_settings
(
    database_id integer NOT NULL,
    context_settings_id bigint NOT NULL,
    INDEX context_settings_id CLUSTERED (context_settings_id),
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

CREATE TABLE
    #query_store_query
(
    database_id integer NOT NULL,
    query_id bigint NOT NULL,
    INDEX query_id CLUSTERED (query_id),
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
    query_hash binary(8) NOT NULL,
    initial_compile_start_time datetimeoffset(7) NOT NULL,
    last_compile_start_time datetimeoffset(7) NULL,
    last_execution_time datetimeoffset(7) NULL
);

CREATE TABLE
    #query_store_query_text
(
    database_id integer NOT NULL,
    query_text_id bigint NOT NULL,
    INDEX query_text_id CLUSTERED (query_text_id),
    query_sql_text nvarchar(max) NULL,
    statement_sql_handle varbinary(64) NULL,
    is_part_of_encrypted_module bit NOT NULL,
    has_restricted_text bit NOT NULL
);

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
    plan_type_desc nvarchar(120) NULL,
    INDEX plan_id_query_id CLUSTERED (plan_id, query_id)
);

CREATE TABLE
    #query_parameters
(
    plan_id bigint NOT NULL,
    INDEX plan_id CLUSTERED (plan_id),
    parameter_name sysname NULL,
    parameter_data_type sysname NULL,
    parameter_compiled_value nvarchar(max) NULL
);

CREATE TABLE
    #query_text_parameters
(
    plan_id bigint NOT NULL,
    INDEX plan_id CLUSTERED (plan_id),
    parameter_declaration nvarchar(max) NULL
);

CREATE TABLE
    #reproduction_warnings
(
    plan_id bigint NOT NULL,
    INDEX plan_id CLUSTERED (plan_id),
    warning_type nvarchar(50) NULL,
    warning_message nvarchar(max) NULL
);

CREATE TABLE
    #repro_queries
(
    plan_id bigint NOT NULL,
    query_id bigint NOT NULL,
    executable_query nvarchar(max) NULL,
    INDEX plan_id_query_id CLUSTERED (plan_id, query_id)
);

CREATE TABLE
    #embedded_constants
(
    plan_id bigint NOT NULL,
    INDEX plan_id CLUSTERED (plan_id),
    constant_value nvarchar(max) NULL
);

/*
Populate filter temp tables using XML-based string splitting for compatibility
*/
IF @include_plan_ids IS NOT NULL
BEGIN
    SELECT
        @sql = @isolation_level;

    SELECT
        @sql += N'
    INSERT
        #include_plan_ids
    WITH
        (TABLOCK)
    (
        plan_id
    )
    SELECT
        ids.plan_id
    FROM
    (
        SELECT
            plan_id =
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
                            @include_plan_ids,
                            '','',
                            ''</x><x>''
                        ) +
                        ''</x>''
                    )
        ) AS ids
        CROSS APPLY ids.ids.nodes(''x'') AS x (x)
    ) AS ids
    WHERE ids.plan_id IS NOT NULL
    OPTION(RECOMPILE);' + @nc10;

    IF @debug = 1
    BEGIN
        PRINT LEN(@sql);
        PRINT @sql;
    END;

    EXECUTE sys.sp_executesql
        @sql,
        N'@include_plan_ids nvarchar(4000)',
        @include_plan_ids;
END;

IF @include_query_ids IS NOT NULL
BEGIN
    SELECT
        @sql = @isolation_level;

    SELECT
        @sql += N'
    INSERT
        #include_query_ids
    WITH
        (TABLOCK)
    (
        query_id
    )
    SELECT
        ids.query_id
    FROM
    (
        SELECT
            query_id =
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
                            @include_query_ids,
                            '','',
                            ''</x><x>''
                        ) +
                        ''</x>''
                    )
        ) AS ids
        CROSS APPLY ids.ids.nodes(''x'') AS x (x)
    ) AS ids
    WHERE ids.query_id IS NOT NULL
    OPTION(RECOMPILE);' + @nc10;

    IF @debug = 1
    BEGIN
        PRINT LEN(@sql);
        PRINT @sql;
    END;

    EXECUTE sys.sp_executesql
        @sql,
        N'@include_query_ids nvarchar(4000)',
        @include_query_ids;

    /*Convert query IDs to plan IDs for filtering*/
    SELECT
        @sql = @isolation_level;

    SELECT
        @sql += N'
    INSERT
        #include_plan_ids
    WITH
        (TABLOCK)
    (
        plan_id
    )
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

    EXECUTE sys.sp_executesql
        @sql;
END;

IF @ignore_plan_ids IS NOT NULL
BEGIN
    SELECT
        @sql = @isolation_level;

    SELECT
        @sql += N'
    INSERT
        #ignore_plan_ids
    WITH
        (TABLOCK)
    (
        plan_id
    )
    SELECT
        x.plan_id
    FROM
    (
        SELECT
            plan_id =
                x.value
                (
                    ''(./text())[1]'',
                    ''bigint''
                )
        FROM
        (
            SELECT
                x =
                    CONVERT
                    (
                        xml,
                        ''<x>'' +
                        REPLACE
                        (
                            @ignore_plan_ids,
                            '','',
                            ''</x><x>''
                        ) +
                        ''</x>''
                    )
        ) AS a
        CROSS APPLY a.x.nodes(''x'') AS b (x)
    ) AS x
    WHERE x.plan_id IS NOT NULL
    OPTION(RECOMPILE);' + @nc10;

    IF @debug = 1
    BEGIN
        PRINT LEN(@sql);
        PRINT @sql;
    END;

    EXECUTE sys.sp_executesql
        @sql,
        N'@ignore_plan_ids nvarchar(4000)',
        @ignore_plan_ids;
END;

IF @ignore_query_ids IS NOT NULL
BEGIN
    SELECT
        @sql = @isolation_level;

    SELECT
        @sql += N'
    INSERT
        #ignore_query_ids
    WITH
        (TABLOCK)
    (
        query_id
    )
    SELECT
        x.query_id
    FROM
    (
        SELECT
            query_id =
                x.value
                (
                    ''(./text())[1]'',
                    ''bigint''
                )
        FROM
        (
            SELECT
                x =
                    CONVERT
                    (
                        xml,
                        ''<x>'' +
                        REPLACE
                        (
                            @ignore_query_ids,
                            '','',
                            ''</x><x>''
                        ) +
                        ''</x>''
                    )
        ) AS a
        CROSS APPLY a.x.nodes(''x'') AS b (x)
    ) AS x
    WHERE x.query_id IS NOT NULL
    OPTION(RECOMPILE);' + @nc10;

    IF @debug = 1
    BEGIN
        PRINT LEN(@sql);
        PRINT @sql;
    END;

    EXECUTE sys.sp_executesql
        @sql,
        N'@ignore_query_ids nvarchar(4000)',
        @ignore_query_ids;

    /*Convert query IDs to plan IDs for filtering*/
    SELECT
        @sql = @isolation_level;

    SELECT
        @sql += N'
    INSERT
        #ignore_plan_ids
    WITH
        (TABLOCK)
    (
        plan_id
    )
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

    EXECUTE sys.sp_executesql
        @sql;
END;

/*Process @query_text_search parameter*/
IF @query_text_search IS NOT NULL
BEGIN
    /*Add leading wildcard if missing*/
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

    /*Add trailing wildcard if missing*/
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

    /*Populate #query_text_search with plan IDs matching the search text*/
    SELECT
        @sql = @isolation_level;

    SELECT
        @sql += N'
    INSERT
        #query_text_search
    WITH
        (TABLOCK)
    (
        plan_id
    )
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

    /*Add procedure filter if specified*/
    IF
    (
        @procedure_name IS NOT NULL
    AND @procedure_exists = 1
    AND CHARINDEX(N'%', @procedure_name) = 0
    )
    BEGIN
        SELECT
            @sql += N'
    AND   qsp.query_id IN
          (
              SELECT
                  qsq.query_id
              FROM ' + @database_name_quoted + N'.sys.query_store_query AS qsq
              WHERE qsq.object_id = OBJECT_ID(@procedure_name_quoted)
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

    EXECUTE sys.sp_executesql
        @sql,
      N'@query_text_search nvarchar(4000), 
        @procedure_name_quoted nvarchar(1024)',
        @query_text_search,
        @procedure_name_quoted;
END;

/*Process @query_text_search_not parameter*/
IF @query_text_search_not IS NOT NULL
BEGIN
    /*Add leading wildcard if missing*/
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

    /*Add trailing wildcard if missing*/
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

    /*Populate #query_text_search_not with plan IDs to exclude*/
    SELECT
        @sql = @isolation_level;

    SELECT
        @sql += N'
    INSERT
        #query_text_search_not
    WITH
        (TABLOCK)
    (
        plan_id
    )
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

    /*Add procedure filter if specified*/
    IF
    (
        @procedure_name IS NOT NULL
    AND @procedure_exists = 1
    AND CHARINDEX(N'%', @procedure_name) = 0
    )
    BEGIN
        SELECT
            @sql += N'
    AND   qsp.query_id IN
          (
              SELECT
                  qsq.query_id
              FROM ' + @database_name_quoted + N'.sys.query_store_query AS qsq
              WHERE qsq.object_id = OBJECT_ID(@procedure_name_quoted)
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

    EXECUTE sys.sp_executesql
        @sql,
      N'@query_text_search_not nvarchar(4000),
        @procedure_name_quoted nvarchar(1024)',
        @query_text_search_not,
        @procedure_name_quoted;
END;

/*
Populate #query_store_runtime_stats from sys.query_store_runtime_stats
This aggregates runtime stats for all filtered plan IDs
*/
SELECT
    @sql = @isolation_level;

SELECT
    @sql += N'
INSERT
    #query_store_runtime_stats
WITH
    (TABLOCK)
(
    database_id,
    runtime_stats_id,
    plan_id,
    runtime_stats_interval_id,
    execution_type_desc,
    first_execution_time,
    last_execution_time,
    count_executions,
    avg_duration_ms,
    last_duration_ms,
    min_duration_ms,
    max_duration_ms,
    avg_cpu_time_ms,
    last_cpu_time_ms,
    min_cpu_time_ms,
    max_cpu_time_ms,
    avg_logical_io_reads_mb,
    last_logical_io_reads_mb,
    min_logical_io_reads_mb,
    max_logical_io_reads_mb,
    avg_logical_io_writes_mb,
    last_logical_io_writes_mb,
    min_logical_io_writes_mb,
    max_logical_io_writes_mb,
    avg_physical_io_reads_mb,
    last_physical_io_reads_mb,
    min_physical_io_reads_mb,
    max_physical_io_reads_mb,
    avg_clr_time_ms,
    last_clr_time_ms,
    min_clr_time_ms,
    max_clr_time_ms,
    last_dop,
    min_dop,
    max_dop,
    avg_query_max_used_memory_mb,
    last_query_max_used_memory_mb,
    min_query_max_used_memory_mb,
    max_query_max_used_memory_mb,
    avg_rowcount,
    last_rowcount,
    min_rowcount,
    max_rowcount,
    avg_num_physical_io_reads_mb,
    last_num_physical_io_reads_mb,
    min_num_physical_io_reads_mb,
    max_num_physical_io_reads_mb,
    avg_log_bytes_used_mb,
    last_log_bytes_used_mb,
    min_log_bytes_used_mb,
    max_log_bytes_used_mb,
    avg_tempdb_space_used_mb,
    last_tempdb_space_used_mb,
    min_tempdb_space_used_mb,
    max_tempdb_space_used_mb,
    context_settings
)
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
    AVG((qsrs_with_lasts.avg_logical_io_reads * 8.) / 1024.),
    MAX((qsrs_with_lasts.partitioned_last_logical_io_reads * 8.) / 1024.),
    MIN((qsrs_with_lasts.min_logical_io_reads * 8.) / 1024.),
    MAX((qsrs_with_lasts.max_logical_io_reads * 8.) / 1024.),
    AVG((qsrs_with_lasts.avg_logical_io_writes * 8.) / 1024.),
    MAX((qsrs_with_lasts.partitioned_last_logical_io_writes * 8.) / 1024.),
    MIN((qsrs_with_lasts.min_logical_io_writes * 8.) / 1024.),
    MAX((qsrs_with_lasts.max_logical_io_writes * 8.) / 1024.),
    AVG((qsrs_with_lasts.avg_physical_io_reads * 8.) / 1024.),
    MAX((qsrs_with_lasts.partitioned_last_physical_io_reads * 8.) / 1024.),
    MIN((qsrs_with_lasts.min_physical_io_reads * 8.) / 1024.),
    MAX((qsrs_with_lasts.max_physical_io_reads * 8.) / 1024.),
    AVG((qsrs_with_lasts.avg_clr_time / 1000.)),
    MAX((qsrs_with_lasts.partitioned_last_clr_time / 1000.)),
    MIN((qsrs_with_lasts.min_clr_time / 1000.)),
    MAX((qsrs_with_lasts.max_clr_time / 1000.)),
    MAX(qsrs_with_lasts.partitioned_last_dop),
    MIN(qsrs_with_lasts.min_dop),
    MAX(qsrs_with_lasts.max_dop),
    AVG((qsrs_with_lasts.avg_query_max_used_memory * 8.) / 1024.),
    MAX((qsrs_with_lasts.partitioned_last_query_max_used_memory * 8.) / 1024.),
    MIN((qsrs_with_lasts.min_query_max_used_memory * 8.) / 1024.),
    MAX((qsrs_with_lasts.max_query_max_used_memory * 8.) / 1024.),
    AVG(qsrs_with_lasts.avg_rowcount * 1.),
    MAX(qsrs_with_lasts.partitioned_last_rowcount),
    MIN(qsrs_with_lasts.min_rowcount),
    MAX(qsrs_with_lasts.max_rowcount),';

/*Add SQL 2017+ columns*/
IF @new = 1
BEGIN
    SELECT @sql += N'
    AVG((qsrs_with_lasts.avg_num_physical_io_reads * 8.) / 1024.),
    MAX((qsrs_with_lasts.partitioned_last_num_physical_io_reads * 8.) / 1024.),
    MIN((qsrs_with_lasts.min_num_physical_io_reads * 8.) / 1024.),
    MAX((qsrs_with_lasts.max_num_physical_io_reads * 8.) / 1024.),
    AVG(qsrs_with_lasts.avg_log_bytes_used / 1000000.),
    MAX(qsrs_with_lasts.partitioned_last_log_bytes_used / 1000000.),
    MIN(qsrs_with_lasts.min_log_bytes_used / 1000000.),
    MAX(qsrs_with_lasts.max_log_bytes_used / 1000000.),
    AVG((qsrs_with_lasts.avg_tempdb_space_used * 8.) / 1024.),
    MAX((qsrs_with_lasts.partitioned_last_tempdb_space_used * 8.) / 1024.),
    MIN((qsrs_with_lasts.min_tempdb_space_used * 8.) / 1024.),
    MAX((qsrs_with_lasts.max_tempdb_space_used * 8.) / 1024.),';
END;
ELSE
BEGIN
    SELECT @sql += N'
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

SELECT @sql += N'
    context_settings = NULL
FROM
(
    SELECT
        qsrs.*,
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

/*Add SQL 2017+ windowing columns*/
IF @new = 1
BEGIN
    SELECT @sql += N'
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
ELSE
BEGIN
    SELECT @sql += N'
        partitioned_last_num_physical_io_reads = NULL,
        partitioned_last_log_bytes_used = NULL,
        partitioned_last_tempdb_space_used = NULL';
END;

SELECT @sql += N'
    FROM ' + @database_name_quoted + N'.sys.query_store_runtime_stats AS qsrs
    WHERE EXISTS
          (
              SELECT
                  1/0
              FROM ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
              WHERE qsp.plan_id = qsrs.plan_id
              AND   qsp.is_online_index_plan = 0
          )';

/*Add date filtering if specified*/
IF @start_date <= @end_date
BEGIN
    SELECT
        @sql += N'
    AND   qsrs.last_execution_time >= @start_date
    AND   qsrs.last_execution_time < @end_date';
END;

/*Add include plan IDs filter if specified*/
IF
(
    @include_plan_ids IS NOT NULL
 OR @include_query_ids IS NOT NULL
)
BEGIN
    SELECT
        @sql += N'
    AND   EXISTS
          (
              SELECT
                  1/0
              FROM #include_plan_ids AS ipi
              WHERE ipi.plan_id = qsrs.plan_id
          )';
END;

/*Add ignore plan IDs filter if specified*/
IF
(
    @ignore_plan_ids IS NOT NULL
 OR @ignore_query_ids IS NOT NULL
)
BEGIN
    SELECT
        @sql += N'
    AND   NOT EXISTS
          (
              SELECT
                  1/0
              FROM #ignore_plan_ids AS ipi
              WHERE ipi.plan_id = qsrs.plan_id
          )';
END;

/*Add query text search filter if specified*/
IF @query_text_search IS NOT NULL
BEGIN
    SELECT
        @sql += N'
    AND   EXISTS
          (
              SELECT
                  1/0
              FROM #query_text_search AS qts
              WHERE qts.plan_id = qsrs.plan_id
          )';
END;

/*Add query text exclusion filter if specified*/
IF @query_text_search_not IS NOT NULL
BEGIN
    SELECT
        @sql += N'
    AND   NOT EXISTS
          (
              SELECT
                  1/0
              FROM #query_text_search_not AS qtsn
              WHERE qtsn.plan_id = qsrs.plan_id
          )';
END;

/*Add procedure filter if specified*/
IF
(
    @procedure_name IS NOT NULL
AND @procedure_exists = 1
AND CHARINDEX(N'%', @procedure_name) = 0
)
BEGIN
    SELECT
        @sql += N'
    AND   qsrs.plan_id IN
          (
              SELECT
                  qsp.plan_id
              FROM ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
              WHERE qsp.query_id IN
                    (
                        SELECT
                            qsq.query_id
                        FROM ' + @database_name_quoted + N'.sys.query_store_query AS qsq
                        WHERE qsq.object_id = OBJECT_ID(@procedure_name_quoted)
                    )
          )';
END;

SELECT @sql += N'
) AS qsrs_with_lasts
GROUP BY
    qsrs_with_lasts.plan_id
ORDER BY
    MAX(qsrs_with_lasts.partitioned_last_execution_time) DESC
OPTION(RECOMPILE);' + @nc10;

IF @debug = 1
BEGIN
    PRINT LEN(@sql);
    PRINT @sql;
END;

/*Execute the population query*/
EXECUTE sys.sp_executesql
    @sql,
    N'@database_id integer,
      @start_date datetimeoffset(7),
      @end_date datetimeoffset(7),
      @procedure_name_quoted nvarchar(1024)',
    @database_id,
    @start_date,
    @end_date,
    @procedure_name_quoted;

/*
Populate #query_store_plan from sys.query_store_plan
This will pull plan details for all filtered plan IDs
*/
SELECT
    @sql = @isolation_level;

SELECT
    @sql += N'
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

/*Add version-specific columns*/
IF @sql_2022_views = 1
BEGIN
    SELECT @sql += N'
    qsp.plan_forcing_type_desc,
    qsp.has_compile_replay_script,
    qsp.is_optimized_plan_forcing_disabled,
    qsp.plan_type_desc';
END;
ELSE IF @new = 1
BEGIN
    SELECT @sql += N'
    qsp.plan_forcing_type_desc,
    NULL,
    NULL,
    NULL';
END;
ELSE
BEGIN
    SELECT @sql += N'
    NULL,
    NULL,
    NULL,
    NULL';
END;

/*Add FROM clause and filtering*/
SELECT
    @sql += N'
FROM ' + @database_name_quoted + N'.sys.query_store_plan AS qsp
WHERE qsp.is_online_index_plan = 0';

/*Add date filtering if specified*/
IF @start_date <= @end_date
BEGIN
    SELECT
        @sql += N'
AND   qsp.last_execution_time >= @start_date
AND   qsp.last_execution_time < @end_date';
END;

/*Add include plan IDs filter if specified*/
IF
(
    @include_plan_ids IS NOT NULL
 OR @include_query_ids IS NOT NULL
)
BEGIN
    SELECT
        @sql += N'
AND   EXISTS
      (
          SELECT
              1/0
          FROM #include_plan_ids AS ipi
          WHERE ipi.plan_id = qsp.plan_id
      )';
END;

/*Add ignore plan IDs filter if specified*/
IF
(
    @ignore_plan_ids IS NOT NULL
 OR @ignore_query_ids IS NOT NULL
)
BEGIN
    SELECT
        @sql += N'
AND   NOT EXISTS
      (
          SELECT
              1/0
          FROM #ignore_plan_ids AS ipi
          WHERE ipi.plan_id = qsp.plan_id
      )';
END;

/*Add query text search filter if specified*/
IF @query_text_search IS NOT NULL
BEGIN
    SELECT
        @sql += N'
AND   EXISTS
      (
          SELECT
              1/0
          FROM #query_text_search AS qts
          WHERE qts.plan_id = qsp.plan_id
      )';
END;

/*Add query text exclusion filter if specified*/
IF @query_text_search_not IS NOT NULL
BEGIN
    SELECT
        @sql += N'
AND   NOT EXISTS
      (
          SELECT
              1/0
          FROM #query_text_search_not AS qtsn
          WHERE qtsn.plan_id = qsp.plan_id
      )';
END;

/*Add procedure filter if specified*/
IF
(
    @procedure_name IS NOT NULL
AND @procedure_exists = 1
AND CHARINDEX(N'%', @procedure_name) = 0
)
BEGIN
    SELECT
        @sql += N'
AND   qsp.query_id IN
      (
          SELECT
              qsq.query_id
          FROM ' + @database_name_quoted + N'.sys.query_store_query AS qsq
          WHERE qsq.object_id = OBJECT_ID(@procedure_name_quoted)
      )';
END;

/*Add final ORDER BY and options*/
SELECT
    @sql += N'
ORDER BY
    qsp.last_execution_time DESC
OPTION(RECOMPILE);' + @nc10;

IF @debug = 1
BEGIN
    PRINT LEN(@sql);
    PRINT @sql;
END;

/*Execute the population query*/
EXECUTE sys.sp_executesql
    @sql,
  N'@database_id integer,
    @start_date datetimeoffset(7),
    @end_date datetimeoffset(7),
    @procedure_name_quoted nvarchar(1024)',
    @database_id,
    @start_date,
    @end_date,
    @procedure_name_quoted;

/*
Populate the #query_store_query table with query metadata
*/
SELECT
    @sql = N'',
    @current_table = N'inserting #query_store_query';

SELECT
    @sql += N'
SELECT
    @database_id,
    qsq.query_id,
    qsq.query_text_id,
    qsq.context_settings_id,
    qsq.object_id,
    qsq.query_hash,
    qsq.initial_compile_start_time,
    qsq.last_compile_start_time,
    qsq.last_execution_time
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
    query_hash,
    initial_compile_start_time,
    last_compile_start_time,
    last_execution_time
)
EXECUTE sys.sp_executesql
    @sql,
  N'@database_id integer',
    @database_id;

/*
Populate the #query_store_query_text table with query text
*/
SELECT
    @sql = N'',
    @current_table = N'inserting #query_store_query_text';

SELECT
    @sql += N'
SELECT
    @database_id,
    qsqt.query_text_id,
    qsqt.query_sql_text,
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
  N'@database_id integer',
    @database_id;

/*
Populate the #query_context_settings table with context settings
*/
SELECT
    @sql = N'',
    @current_table = N'inserting #query_context_settings';

SELECT
    @sql += N'
SELECT
    @database_id,
    qcs.context_settings_id,
    qcs.set_options,
    qcs.language_id,
    qcs.date_format,
    qcs.date_first,
    qcs.status,
    qcs.required_cursor_options,
    qcs.acceptable_cursor_options,
    qcs.merge_action_type,
    qcs.default_schema_id,
    qcs.is_replication_specific,
    qcs.is_contained
FROM ' + @database_name_quoted + N'.sys.query_context_settings AS qcs
WHERE EXISTS
      (
          SELECT
              1/0
          FROM #query_store_query AS qsq
          WHERE qsq.context_settings_id = qcs.context_settings_id
      )
OPTION(RECOMPILE);' + @nc10;

IF @debug = 1
BEGIN
    PRINT LEN(@sql);
    PRINT @sql;
END;

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
  N'@database_id integer',
    @database_id;

/*
Update things to get the context settings for each query
*/
SELECT
    @current_table = N'updating context_settings in #query_store_runtime_stats';

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
                THEN ', ARITHABORT'
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

/*
Populate the #query_store_wait_stats table with wait statistics (SQL 2017+)
*/
SELECT
    @sql = N'',
    @current_table = N'inserting #query_store_wait_stats';

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
  N'@database_id integer',
    @database_id;

/*
Populate SQL 2022+ Query Store tables
*/
IF @sql_2022_views = 1
BEGIN
    /*
    Populate the #query_store_plan_feedback table
    */
    SELECT
        @sql = N'',
        @current_table = N'inserting #query_store_plan_feedback';

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
      N'@database_id integer',
        @database_id;

    /*
    Populate the #query_store_query_variant table
    */
    SELECT
        @sql = N'',
        @current_table = N'inserting #query_store_query_variant';

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
      N'@database_id integer',
        @database_id;

    /*
    Populate the #query_store_query_hints table
    */
    SELECT
        @sql = N'',
        @current_table = N'inserting #query_store_query_hints';

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
      N'@database_id integer',
        @database_id;
END;

/*
Extract parameters from query plans
*/
SELECT
    @current_table = N'extracting parameters from query plans';

INSERT
    #query_parameters
WITH
    (TABLOCK)
(
    plan_id,
    parameter_name,
    parameter_data_type,
    parameter_compiled_value
)
SELECT
    qsp.plan_id,
    parameter_name =
        LTRIM(RTRIM(cr.c.value(N'@Column', N'sysname'))),
    parameter_data_type =
        LTRIM(RTRIM(cr.c.value(N'@ParameterDataType', N'sysname'))),
    parameter_compiled_value =
        CASE
            WHEN cr.c.value(N'@ParameterCompiledValue', N'nvarchar(MAX)') LIKE N'(%)'
            THEN SUBSTRING
                 (
                     cr.c.value(N'@ParameterCompiledValue', N'nvarchar(MAX)'),
                     2,
                     LEN(cr.c.value(N'@ParameterCompiledValue', N'nvarchar(MAX)')) - 2
                 )
            ELSE cr.c.value(N'@ParameterCompiledValue', N'nvarchar(MAX)')
        END
FROM #query_store_plan AS qsp
CROSS APPLY
(
    SELECT
        query_plan_xml =
            TRY_CAST(qsp.query_plan AS xml)
) AS x
CROSS APPLY x.query_plan_xml.nodes(N'declare namespace p="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; //p:ParameterList/p:ColumnReference') AS cr(c)
WHERE x.query_plan_xml IS NOT NULL
OPTION(RECOMPILE);

/*
Extract parameters from plans too large to cast as full XML
*/
INSERT
    #query_parameters
WITH
    (TABLOCK)
(
    plan_id,
    parameter_name,
    parameter_data_type,
    parameter_compiled_value
)
SELECT
    qsp.plan_id,
    parameter_name =
        LTRIM(RTRIM(cr.c.value(N'@Column', N'sysname'))),
    parameter_data_type =
        LTRIM(RTRIM(cr.c.value(N'@ParameterDataType', N'sysname'))),
    parameter_compiled_value =
        CASE
            WHEN cr.c.value(N'@ParameterCompiledValue', N'nvarchar(MAX)') LIKE N'(%)'
            THEN SUBSTRING
                 (
                     cr.c.value(N'@ParameterCompiledValue', N'nvarchar(MAX)'),
                     2,
                     LEN(cr.c.value(N'@ParameterCompiledValue', N'nvarchar(MAX)')) - 2
                 )
            ELSE cr.c.value(N'@ParameterCompiledValue', N'nvarchar(MAX)')
        END
FROM #query_store_plan AS qsp
CROSS APPLY
(
    SELECT
        parameter_list_xml =
            TRY_CAST
            (
                SUBSTRING
                (
                    qsp.query_plan,
                    CHARINDEX(N'<ParameterList>', qsp.query_plan),
                    CHARINDEX
                    (
                        N'</ParameterList>',
                        qsp.query_plan,
                        CHARINDEX(N'<ParameterList>', qsp.query_plan)
                    )
                    + LEN(N'</ParameterList>')
                    - CHARINDEX(N'<ParameterList>', qsp.query_plan)
                ) AS xml
            )
) AS x
CROSS APPLY x.parameter_list_xml.nodes(N'declare namespace p="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; //p:ParameterList/p:ColumnReference') AS cr(c)
WHERE TRY_CAST(qsp.query_plan AS xml) IS NULL
AND   CHARINDEX(N'<ParameterList>', qsp.query_plan) > 0
AND   x.parameter_list_xml IS NOT NULL
OPTION(RECOMPILE);

/*
Check for plans too large to cast to XML
*/
SELECT
    @current_table = N'checking for plans too large to cast to XML';

INSERT
    #reproduction_warnings
WITH
    (TABLOCK)
(
    plan_id,
    warning_type,
    warning_message
)
SELECT DISTINCT
    qsp.plan_id,
    warning_type = N'plan too large for XML parsing',
    warning_message =
        N'Query plan could not be cast to XML (likely too large). ' +
        N'Parameters and embedded constants cannot be extracted using XQuery. ' +
        N'Manual review of plan text required.'
FROM #query_store_plan AS qsp
WHERE TRY_CAST(qsp.query_plan AS xml) IS NULL
OPTION(RECOMPILE);

/*
Detect OPTION(RECOMPILE) usage and extract embedded constants
*/
SELECT
    @current_table = N'checking for OPTION(RECOMPILE) and extracting embedded constants';

INSERT
    #reproduction_warnings
WITH
    (TABLOCK)
(
    plan_id,
    warning_type,
    warning_message
)
SELECT DISTINCT
    qsp.plan_id,
    warning_type = N'parameter embedding optimization',
    warning_message =
        N'Query uses OPTION(RECOMPILE) with parameter embedding optimization. ' +
        N'Literal values are embedded throughout the plan instead of using parameters. ' +
        N'Parameter alignment may be incomplete. Review embedded constants and original query text.'
FROM #query_store_plan AS qsp
JOIN #query_store_query AS qsq
  ON qsp.query_id = qsq.query_id
JOIN #query_store_query_text AS qsqt
  ON qsq.query_text_id = qsqt.query_text_id
WHERE qsqt.query_sql_text LIKE N'%OPTION%(%RECOMPILE%)%'
OPTION(RECOMPILE);

/*
Extract embedded constants from plans with OPTION(RECOMPILE)
For plans that can be cast to XML, use XQuery
*/
SELECT
    @current_table = N'extracting embedded constants from plans';

INSERT
    #embedded_constants
WITH
    (TABLOCK)
(
    plan_id,
    constant_value
)
SELECT DISTINCT
    qsp.plan_id,
    constant_value =
        CASE
            WHEN c.const.value(N'@ConstValue', N'nvarchar(max)') LIKE N'(%)'
            THEN SUBSTRING
                 (
                     c.const.value(N'@ConstValue', N'nvarchar(max)'),
                     2,
                     LEN(c.const.value(N'@ConstValue', N'nvarchar(max)')) - 2
                 )
            ELSE LTRIM(RTRIM(c.const.value(N'@ConstValue', N'nvarchar(max)')))
        END
FROM #query_store_plan AS qsp
JOIN #query_store_query AS qsq
  ON qsp.query_id = qsq.query_id
JOIN #query_store_query_text AS qsqt
  ON qsq.query_text_id = qsqt.query_text_id
CROSS APPLY
(
    SELECT
        query_plan_xml =
            TRY_CAST(qsp.query_plan AS xml)
) AS x
CROSS APPLY x.query_plan_xml.nodes(N'declare namespace p="http://schemas.microsoft.com/sqlserver/2004/07/showplan"; //p:RelOp[@PhysicalOp="Index Scan" or @PhysicalOp="Index Seek" or @PhysicalOp="Clustered Index Scan" or @PhysicalOp="Clustered Index Seek"]//p:Const[@ConstValue]') AS c(const)
WHERE x.query_plan_xml IS NOT NULL
AND   qsqt.query_sql_text LIKE N'%OPTION%(%RECOMPILE%)%'
OPTION(RECOMPILE);

/*
Check for encrypted modules and restricted text
*/
SELECT
    @current_table = N'checking for encrypted modules and restricted text';

INSERT
    #reproduction_warnings
WITH
    (TABLOCK)
(
    plan_id,
    warning_type,
    warning_message
)
SELECT DISTINCT
    qsp.plan_id,
    warning_type =
        CASE
            WHEN qsqt.is_part_of_encrypted_module = 1
            THEN N'encrypted module'
            WHEN qsqt.has_restricted_text = 1
            THEN N'restricted text'
        END,
    warning_message =
        CASE
            WHEN qsqt.is_part_of_encrypted_module = 1
            THEN N'Query is part of an encrypted module. Full query text may not be available.'
            WHEN qsqt.has_restricted_text = 1
            THEN N'Query has restricted text. Full query text may not be available due to permissions or other restrictions.'
        END
FROM #query_store_plan AS qsp
JOIN #query_store_query AS qsq
  ON qsp.query_id = qsq.query_id
JOIN #query_store_query_text AS qsqt
  ON qsq.query_text_id = qsqt.query_text_id
WHERE qsqt.is_part_of_encrypted_module = 1
OR    qsqt.has_restricted_text = 1
OPTION(RECOMPILE);

/*
Check for temp tables and table variables in query text
*/
SELECT
    @current_table = N'checking for temp tables and table variables';

INSERT
    #reproduction_warnings
WITH
    (TABLOCK)
(
    plan_id,
    warning_type,
    warning_message
)
SELECT DISTINCT
    qsp.plan_id,
    warning_type = N'#temp table',
    warning_message = N'Query contains temp table(s) - reproduction may require temp table creation'
FROM #query_store_plan AS qsp
JOIN #query_store_query AS qsq
  ON qsp.query_id = qsq.query_id
JOIN #query_store_query_text AS qsqt
  ON qsq.query_text_id = qsqt.query_text_id
WHERE qsqt.query_sql_text LIKE N'%FROM #%'
OR    qsqt.query_sql_text LIKE N'%JOIN #%'
OR    qsqt.query_sql_text LIKE N'%INTO #%'
OPTION(RECOMPILE);

INSERT
    #reproduction_warnings
WITH
    (TABLOCK)
(
    plan_id,
    warning_type,
    warning_message
)
SELECT DISTINCT
    qsp.plan_id,
    warning_type = N'@table variable',
    warning_message = N'Query may contain table variable(s) - reproduction may require table variable creation'
FROM #query_store_plan AS qsp
JOIN #query_store_query AS qsq
  ON qsp.query_id = qsq.query_id
JOIN #query_store_query_text AS qsqt
  ON qsq.query_text_id = qsqt.query_text_id
WHERE qsqt.query_sql_text LIKE N'%FROM @%'
OR    qsqt.query_sql_text LIKE N'%JOIN @%'
OR    qsqt.query_sql_text LIKE N'%INTO @%'
OPTION(RECOMPILE);

/*
Check for parameter count mismatch
Only warn if query text starts with parameters but none found in plan
*/
SELECT
    @current_table = N'checking for parameter count mismatch';

INSERT
    #reproduction_warnings
WITH
    (TABLOCK)
(
    plan_id,
    warning_type,
    warning_message
)
SELECT
    qsp.plan_id,
    warning_type = N'parameter count mismatch',
    warning_message =
        N'Query text has parameter declarations but no parameters found in plan XML. ' +
        N'This typically indicates local variables that do not have sniffed values cached in the plan. ' +
        N'Review the stored procedure or batch text to determine how these variables are assigned values.'
FROM #query_store_plan AS qsp
JOIN #query_store_query AS qsq
  ON qsp.query_id = qsq.query_id
JOIN #query_store_query_text AS qsqt
  ON qsq.query_text_id = qsqt.query_text_id
CROSS APPLY
(
    SELECT
        plan_param_count =
            COUNT_BIG(*)
    FROM #query_parameters AS qp
    WHERE qp.plan_id = qsp.plan_id
) AS ppc
WHERE qsqt.query_sql_text LIKE N'(@%'
AND   ppc.plan_param_count = 0
OPTION(RECOMPILE);

/*
Build reproduction queries with sp_executesql
*/
SELECT
    @current_table = N'building reproduction queries';

INSERT
    #repro_queries
WITH
    (TABLOCK)
(
    plan_id,
    query_id,
    executable_query
)
SELECT
    qsp.plan_id,
    qsp.query_id,
    executable_query =
        N'/*' + NCHAR(10) +
        N'Query ID: ' + 
        RTRIM(qsp.query_id) + NCHAR(10) +
        N'Plan ID: ' + RTRIM(qsp.plan_id) + NCHAR(10) +
        ISNULL(
            (
                SELECT
                    N'Warnings:' + NCHAR(10) +
                    STUFF
                    (
                        (
                            SELECT
                                NCHAR(10) + 
                                N' - ' + 
                                rw.warning_message
                            FROM #reproduction_warnings AS rw
                            WHERE rw.plan_id = qsp.plan_id
                            ORDER BY
                                rw.warning_type
                            FOR XML
                                PATH(N''),
                                TYPE
                        ).value(N'./text()[1]', N'nvarchar(max)'),
                        1,
                        0,
                        N''
                    ) + NCHAR(10)
            ),
            N''
        ) +
        N'*/' +
        NCHAR(10) +
        ISNULL
        (
            N'SET ' +
            REPLACE(qsrs.context_settings, N', ', N' ON;' + NCHAR(10) + N'SET ') +
            N' ON;' +
            NCHAR(10),
            N''
        ) +
        ISNULL
        (
            N'SET LANGUAGE ' + 
            lang.name + 
            N';' + 
            NCHAR(10), 
            N''
        ) +
        ISNULL
        (
            N'SET DATEFORMAT ' +
            CASE qcs.date_format
                 WHEN 0 THEN N'mdy'
                 WHEN 1 THEN N'dmy'
                 WHEN 2 THEN N'ymd'
                 WHEN 3 THEN N'ydm'
                 WHEN 4 THEN N'myd'
                 WHEN 5 THEN N'dym'
                 ELSE N'mdy'
            END + 
            N';' + 
            NCHAR(10), 
            N''
        ) +
        ISNULL
        (
            N'SET DATEFIRST ' + 
            RTRIM(qcs.date_first) + 
            N';' + 
            NCHAR(10), 
            N''
        ) +
        NCHAR(10) +
        CASE
            WHEN qsqt.query_sql_text LIKE N'(@%'
            THEN
                N'EXECUTE sys.sp_executesql' +
                NCHAR(10) +
                N'    N''' +
                REPLACE
                (
                    clean_query.query_text_cleaned,
                    N'''',
                    N''''''
                ) +
                N''',' +
                NCHAR(10) +
                CASE
                    WHEN EXISTS
                         (
                             SELECT
                                 1/0
                             FROM #query_parameters AS qp
                             WHERE qp.plan_id = qsp.plan_id
                         )
                    THEN
                        N'N''' +
                        STUFF
                        (
                            (
                                SELECT
                                    N', ' +
                                    qp.parameter_name +
                                    N' ' +
                                    qp.parameter_data_type
                                FROM #query_parameters AS qp
                                WHERE qp.plan_id = qsp.plan_id
                                ORDER BY
                                    qp.parameter_name
                                FOR XML
                                    PATH(N''),
                                    TYPE
                            ).value(N'./text()[1]', N'nvarchar(max)'),
                            1,
                            2,
                            N''
                        ) +
                        N''',' +
                        NCHAR(10) +
                        STUFF
                        (
                            (
                                SELECT
                                    N', ' +
                                    ISNULL
                                    (
                                        qp.parameter_compiled_value,
                                        N'NULL'
                                    )
                                FROM #query_parameters AS qp
                                WHERE qp.plan_id = qsp.plan_id
                                ORDER BY
                                    qp.parameter_name
                                FOR XML
                                    PATH(N''),
                                    TYPE
                            ).value(N'./text()[1]', N'nvarchar(max)'),
                            1,
                            2,
                            N''
                        ) +
                        N';' +
                        NCHAR(10)
                    ELSE
                        N'N'''';' +
                        NCHAR(10)
                END
            ELSE
                qsqt.query_sql_text +
                NCHAR(10)
        END
FROM #query_store_plan AS qsp
JOIN #query_store_query AS qsq
  ON qsp.query_id = qsq.query_id
JOIN #query_store_query_text AS qsqt
  ON qsq.query_text_id = qsqt.query_text_id
CROSS APPLY
(
    SELECT
        query_text_cleaned =
            CASE
                WHEN qsqt.query_sql_text LIKE N'(@%'
                THEN
                    LTRIM
                    (
                        SUBSTRING
                        (
                            qsqt.query_sql_text,
                            PATINDEX(N'%))%', qsqt.query_sql_text) + 2,
                            LEN(qsqt.query_sql_text)
                        )
                    )
                ELSE qsqt.query_sql_text
            END
) AS clean_query
JOIN #query_store_runtime_stats AS qsrs
  ON qsp.plan_id = qsrs.plan_id
JOIN #query_context_settings AS qcs
  ON qsq.context_settings_id = qcs.context_settings_id
LEFT JOIN sys.syslanguages AS lang
  ON qcs.language_id = lang.langid
OPTION(RECOMPILE);


SELECT
    table_name =
        N'results',
    database_name =
        DB_NAME(qsrs.database_id),
    rq.executable_query,
    embedded_constants =
        ISNULL
        (
            STUFF
            (
                (
                    SELECT
                        N', ' +
                        ec.constant_value
                    FROM #embedded_constants AS ec
                    WHERE ec.plan_id = rq.plan_id
                    ORDER BY
                        ec.constant_value
                    FOR XML
                        PATH(N''),
                        TYPE
                ).value(N'./text()[1]', N'nvarchar(max)'),
                1,
                2,
                N''
            ),
        N'N/A'
    ),
    rq.query_id,
    rq.plan_id,
    qsp.all_plan_ids,
    qsp.compatibility_level,
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
                             N'-- ' + NCHAR(13) + NCHAR(10) +
                             N'-- This is a huge query plan.' + NCHAR(13) + NCHAR(10) +
                             N'-- Remove the headers and footers, save it as a .sqlplan file, and re-open it.' + NCHAR(13) + NCHAR(10) +
                             NCHAR(13) + NCHAR(10) +
                             REPLACE(qsp.query_plan, N'<RelOp', NCHAR(13) + NCHAR(10) + N'<RelOp') +
                             NCHAR(13) + NCHAR(10) COLLATE Latin1_General_Bin2
                     FOR XML
                         PATH(N''),
                         TYPE
                 )
         END,
    qsrs.execution_type_desc,
    qsrs.first_execution_time,
    qsrs.last_execution_time,
    qsws.waits,
    qsrs.count_executions,
    qsrs.executions_per_second,
    qsrs.avg_duration_ms,
    qsrs.min_duration_ms,
    qsrs.max_duration_ms,
    qsrs.total_duration_ms,
    qsrs.last_duration_ms,
    qsrs.avg_cpu_time_ms,
    qsrs.min_cpu_time_ms,
    qsrs.max_cpu_time_ms,
    qsrs.total_cpu_time_ms,
    qsrs.last_cpu_time_ms,
    qsrs.last_dop,
    qsrs.min_dop,
    qsrs.max_dop,
    qsrs.avg_query_max_used_memory_mb,
    qsrs.last_query_max_used_memory_mb,
    qsrs.min_query_max_used_memory_mb,
    qsrs.max_query_max_used_memory_mb,
    qsrs.total_query_max_used_memory_mb,
    qsrs.avg_rowcount,
    qsrs.min_rowcount,
    qsrs.max_rowcount,
    qsrs.total_rowcount,
    qsrs.last_rowcount,
    qsrs.avg_num_physical_io_reads_mb,
    qsrs.min_num_physical_io_reads_mb,
    qsrs.max_num_physical_io_reads_mb,
    qsrs.total_num_physical_io_reads_mb,
    qsrs.last_num_physical_io_reads_mb
FROM #repro_queries AS rq
CROSS APPLY
(
  SELECT TOP (1)
      qsrs.*
  FROM #query_store_runtime_stats AS qsrs
  WHERE qsrs.plan_id = rq.plan_id
  ORDER BY
      qsrs.plan_id DESC
) AS qsrs
CROSS APPLY
(
  SELECT TOP (1)
      qsp.*
  FROM #query_store_plan AS qsp
  WHERE qsp.plan_id = rq.plan_id
  AND   qsp.query_id = rq.query_id
  ORDER BY
      qsp.plan_id DESC,
      qsp.query_id DESC
) AS qsp
CROSS APPLY
(
  SELECT TOP (1)
      qsq.*
  FROM #query_store_query AS qsq
  WHERE qsq.query_id = rq.query_id
  ORDER BY 
      qsq.query_id DESC 
) AS qsq
CROSS APPLY
(
  SELECT TOP (1)
      qsqt.*
  FROM  #query_store_query_text AS qsqt
  WHERE qsqt.query_text_id = qsq.query_text_id
  ORDER BY 
      qsqt.query_text_id DESC 
) AS qsqt
OUTER APPLY
(
    SELECT
        qsws.plan_id,
        qsws.wait_category_desc,
        TotalWaitTime = SUM(qsws.total_query_wait_time_ms),
        AverageWaitTime = AVG(qsws.avg_query_wait_time_ms),
        MinimumWaitTime = MIN(qsws.min_query_wait_time_ms),
        MaximumWaitTime = MAX(qsws.max_query_wait_time_ms)
    FROM #query_store_wait_stats AS qsws
    WHERE qsws.plan_id = rq.plan_id
    GROUP BY 
        qsws.plan_id,
        qsws.wait_category_desc
    ORDER BY
        TotalWaitTime DESC
    FOR
        XML
        PATH('waits'),
        TYPE
) AS qsws(waits)
OPTION(RECOMPILE);

END TRY

BEGIN CATCH
    IF @current_table IS NOT NULL
    BEGIN
        RAISERROR('error while %s', 10, 1, @current_table) WITH NOWAIT;
    END;

    IF @sql IS NOT NULL
    BEGIN
        RAISERROR('current dynamic sql:', 10, 1) WITH NOWAIT;
        RAISERROR('%s', 10, 1, @sql) WITH NOWAIT;
    END;

    IF @@TRANCOUNT > 0
    BEGIN
        ROLLBACK;
    END;

    THROW;
END CATCH 

IF @debug = 1
BEGIN
    /*
    Debug result sets for temp tables
    */
    SELECT
        table_name =
            N'#query_store_runtime_stats',
        qsrs.*
    FROM #query_store_runtime_stats AS qsrs
    ORDER BY
        qsrs.plan_id
    OPTION(RECOMPILE);
    
    SELECT
        table_name =
            N'#query_store_plan',
        qsp.*
    FROM #query_store_plan AS qsp
    ORDER BY
        qsp.plan_id
    OPTION(RECOMPILE);
    
    SELECT
        table_name =
            N'#query_store_query_text',
        qsqt.*
    FROM #query_store_query_text AS qsqt
    ORDER BY
        qsqt.query_text_id
    OPTION(RECOMPILE);
    
    SELECT
        table_name =
            N'#query_store_query',
        qsq.*
    FROM #query_store_query AS qsq
    ORDER BY
        qsq.query_id
    OPTION(RECOMPILE);
    
    SELECT
        table_name =
            N'#query_context_settings',
        qcs.*
    FROM #query_context_settings AS qcs
    ORDER BY
        qcs.context_settings_id
    OPTION(RECOMPILE);

    SELECT
        table_name =
            N'#query_store_wait_stats',
        qsws.*
    FROM #query_store_wait_stats AS qsws
    ORDER BY
        qsws.plan_id
    OPTION(RECOMPILE);

    SELECT
        table_name =
            N'#query_store_plan_feedback',
        qspf.*
    FROM #query_store_plan_feedback AS qspf
    ORDER BY
        qspf.plan_feedback_id
    OPTION(RECOMPILE);
    
    SELECT
        table_name =
            N'#query_store_query_variant',
        qsqv.*
    FROM #query_store_query_variant AS qsqv
    ORDER BY
        qsqv.query_variant_query_id
    OPTION(RECOMPILE);
    
    SELECT
        table_name =
            N'#query_store_query_hints',
        qsqh.*
    FROM #query_store_query_hints AS qsqh
    ORDER BY
        qsqh.query_hint_id
    OPTION(RECOMPILE);

    SELECT
        table_name =
            N'#query_parameters',
        qp.*
    FROM #query_parameters AS qp
    ORDER BY
        qp.plan_id,
        qp.parameter_name
    OPTION(RECOMPILE);
    
    SELECT
        table_name =
            N'#reproduction_warnings',
        rw.*
    FROM #reproduction_warnings AS rw
    ORDER BY
        rw.plan_id,
        rw.warning_type
    OPTION(RECOMPILE);

    SELECT
        table_name =
            N'#repro_queries',
        rq.*
    FROM #repro_queries AS rq
    ORDER BY
        rq.plan_id
    OPTION(RECOMPILE);

    SELECT
        table_name =
            N'#embedded_constants',
        ec.*
    FROM #embedded_constants AS ec
    ORDER BY
        ec.plan_id,
        ec.constant_value
    OPTION(RECOMPILE);
END;

END; /*Final end*/