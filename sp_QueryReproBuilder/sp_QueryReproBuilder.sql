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
    @isolation_level nvarchar(100) = N'SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;' + NCHAR(13) + NCHAR(10),
    @nc10 nchar(1) = NCHAR(10),
    @where_clause nvarchar(MAX) = N'',
    @start_date_original datetimeoffset(7),
    @end_date_original datetimeoffset(7),
    @utc_minutes_difference bigint

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
    plan_id bigint NOT NULL
);


CREATE TABLE
    #include_query_ids
(
    query_id bigint NOT NULL
);

CREATE TABLE
    #ignore_plan_ids
(
    plan_id bigint NOT NULL
);

CREATE TABLE
    #ignore_query_ids
(
    query_id bigint NOT NULL
);

CREATE TABLE
    #query_text_search
(
    plan_id bigint NOT NULL
);


CREATE TABLE
    #query_text_search_not
(
    plan_id bigint NOT NULL
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
                            @include_plan_ids,
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
                            @include_query_ids,
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
        N'@query_text_search nvarchar(4000), @procedure_name_quoted nvarchar(1024)',
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





END TRY

BEGIN CATCH
    SELECT x = 1
END CATCH 

END; /*Final end*/