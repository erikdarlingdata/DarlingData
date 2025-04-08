SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('collection.collect_query_store', 'P') IS NULL
BEGIN
    EXECUTE ('CREATE PROCEDURE collection.collect_query_store AS RETURN 0;');
END;
GO

/*
/**************************************************************
* 
* Query Store Collection Procedure for DarlingDataCollector
* 
* Copyright (C) Darling Data, LLC
* 
* Collects query store data from databases
* 
**************************************************************/
*/

CREATE OR ALTER PROCEDURE
    collection.collect_query_store
(
    @debug BIT = 0, /*Print debugging information*/
    @use_database_list BIT = 1, /*Use database list from system.database_collection_config*/
    @include_databases NVARCHAR(MAX) = NULL, /*Optional: Comma-separated list of databases to include*/
    @exclude_databases NVARCHAR(MAX) = NULL, /*Optional: Comma-separated list of databases to exclude*/
    @exclude_system_databases BIT = 1, /*Exclude system databases*/
    @include_query_text BIT = 1, /*Include query text*/
    @include_query_plans BIT = 0, /*Include query plans (can be expensive)*/
    @include_runtime_stats BIT = 1, /*Include runtime statistics*/
    @include_wait_stats BIT = 1, /*Include wait statistics*/
    @min_cpu_time_ms INTEGER = 1000, /*Minimum CPU time threshold*/
    @min_logical_io_reads INTEGER = 1000, /*Minimum logical IO reads threshold*/
    @min_logical_io_writes INTEGER = 0, /*Minimum logical IO writes threshold*/
    @min_physical_io_reads INTEGER = 0, /*Minimum physical IO reads threshold*/
    @min_clr_time_ms INTEGER = 0, /*Minimum CLR time threshold*/
    @min_dop INTEGER = 0, /*Minimum degree of parallelism threshold*/
    @min_query_max_used_memory INTEGER = 0, /*Minimum memory grant threshold*/
    @min_rowcount INTEGER = 0, /*Minimum row count threshold*/
    @min_tempdb_space INTEGER = 0, /*Minimum tempdb space used threshold*/
    @min_log_bytes_used INTEGER = 0, /*Minimum log bytes used threshold*/
    @start_time DATETIME2(7) = NULL, /*Query runtime start time filter*/
    @end_time DATETIME2(7) = NULL, /*Query runtime end time filter*/
    @help BIT = 0 /*Prints help information*/
)
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
    
    BEGIN TRY
        /*
        Variable declarations
        */
        DECLARE
            @sql NVARCHAR(MAX) = N'',
            @database_name NVARCHAR(128) = N'',
            @collection_count INTEGER = 0,
            @error_number INTEGER = 0,
            @error_severity INTEGER = 0,
            @error_state INTEGER = 0,
            @error_line INTEGER = 0,
            @error_message NVARCHAR(4000) = N'',
            @collection_starting DATETIME2(7) = SYSDATETIME(),
            @collection_ending DATETIME2(7) = NULL;
            
        DECLARE
            @include_database_list TABLE
            (
                database_name NVARCHAR(128) NOT NULL PRIMARY KEY
            );
            
        DECLARE
            @exclude_database_list TABLE
            (
                database_name NVARCHAR(128) NOT NULL PRIMARY KEY
            );
            
        DECLARE
            @database_list TABLE
            (
                database_id INTEGER NOT NULL PRIMARY KEY,
                database_name NVARCHAR(128) NOT NULL,
                qs_enabled BIT NOT NULL DEFAULT 0,
                qs_readonly BIT NOT NULL DEFAULT 0
            );
            
        /*
        Parameter validation
        */
        IF @help = 1
        BEGIN
            SELECT
                help = N'This procedure collects Query Store data from databases.
                
Parameters:
  @debug = 1 to print detailed information, 0 for normal operation
  @use_database_list = 1 to use database list from system.database_collection_config, 0 to use include/exclude lists
  @include_databases = Comma-separated list of databases to include (used if @use_database_list = 0)
  @exclude_databases = Comma-separated list of databases to exclude
  @exclude_system_databases = 1 to exclude system databases (master, model, msdb, tempdb)
  @include_query_text = 1 to include query text, 0 to exclude
  @include_query_plans = 1 to include query plans, 0 to exclude (can be expensive)
  @include_runtime_stats = 1 to include runtime statistics, 0 to exclude
  @include_wait_stats = 1 to include wait statistics, 0 to exclude
  @min_cpu_time_ms = Minimum CPU time threshold (default 1000ms)
  @min_logical_io_reads = Minimum logical IO reads threshold (default 1000)
  @min_logical_io_writes = Minimum logical IO writes threshold (default 0)
  @min_physical_io_reads = Minimum physical IO reads threshold (default 0)
  @min_clr_time_ms = Minimum CLR time threshold (default 0)
  @min_dop = Minimum degree of parallelism threshold (default 0)
  @min_query_max_used_memory = Minimum memory grant threshold (default 0)
  @min_rowcount = Minimum row count threshold (default 0)
  @min_tempdb_space = Minimum tempdb space used threshold (default 0)
  @min_log_bytes_used = Minimum log bytes used threshold (default 0)
  @start_time = Query runtime start time filter (default NULL for all time)
  @end_time = Query runtime end time filter (default NULL for all time)
  @help = 1 to show this help information

Example usage:
  EXECUTE collection.collect_query_store @debug = 1, @min_cpu_time_ms = 5000;';
            
            RETURN;
        END;
        
        IF @start_time IS NOT NULL AND @end_time IS NOT NULL
        AND @start_time > @end_time
        BEGIN
            RAISERROR(N'@start_time cannot be greater than @end_time', 11, 1) WITH NOWAIT;
            RETURN;
        END;
        
        /*
        Build database lists
        */
        IF @use_database_list = 1
        BEGIN
            INSERT @include_database_list
            (
                database_name
            )
            SELECT
                database_name
            FROM system.database_collection_config
            WHERE collection_type = N'QUERY_STORE'
            AND active = 1;
            
            IF @debug = 1
            BEGIN
                SELECT
                    list_source = N'Using configured database list',
                    database_count = COUNT(*)
                FROM @include_database_list;
            END;
        END;
        ELSE IF @include_databases IS NOT NULL
        BEGIN
            INSERT @include_database_list
            (
                database_name
            )
            SELECT
                database_name = LTRIM(RTRIM(value))
            FROM STRING_SPLIT(@include_databases, N',');
            
            IF @debug = 1
            BEGIN
                SELECT
                    list_source = N'Using @include_databases parameter',
                    database_count = COUNT(*)
                FROM @include_database_list;
            END;
        END;
        
        IF @exclude_databases IS NOT NULL
        BEGIN
            INSERT @exclude_database_list
            (
                database_name
            )
            SELECT
                database_name = LTRIM(RTRIM(value))
            FROM STRING_SPLIT(@exclude_databases, N',');
            
            IF @debug = 1
            BEGIN
                SELECT
                    list_source = N'Using @exclude_databases parameter',
                    database_count = COUNT(*)
                FROM @exclude_database_list;
            END;
        END;
        
        /*
        Build final database list
        */
        INSERT @database_list
        (
            database_id,
            database_name,
            qs_enabled,
            qs_readonly
        )
        SELECT
            d.database_id,
            database_name = d.name,
            qs_enabled = ISNULL(CONVERT(BIT, ISNULL(DATABASEPROPERTYEX(d.name, 'IsQueryStoreOn'), 0)), 0),
            qs_readonly = 0
        FROM sys.databases AS d
        WHERE d.state = 0 -- Only online databases
        AND 
        (
            -- Use include list if specified
            (
                EXISTS (SELECT 1 FROM @include_database_list)
                AND d.name IN (SELECT database_name FROM @include_database_list)
            )
            OR 
            (
                -- Otherwise use all databases except excluded ones
                NOT EXISTS (SELECT 1 FROM @include_database_list)
                AND 
                (
                    -- Skip system databases if specified
                    (@exclude_system_databases = 0 OR d.database_id > 4)
                    -- Skip excluded databases
                    AND d.name NOT IN (SELECT database_name FROM @exclude_database_list)
                )
            )
        )
        AND d.is_read_only = 0;
        
        /*
        Validate query store status
        */
        SELECT
            @sql = N'
            BEGIN TRY
                UPDATE dl
                SET qs_enabled = ISNULL(CONVERT(BIT, ISNULL(DATABASEPROPERTYEX(dl.database_name, ''IsQueryStoreOn''), 0)), 0),
                    qs_readonly = 
                    (
                        SELECT
                            CONVERT(BIT, 
                                CASE
                                    WHEN actual_state = 1 THEN 0
                                    WHEN actual_state = 2 THEN 0
                                    WHEN actual_state = 3 THEN 1
                                    ELSE 1
                                END
                            )
                        FROM (
                            SELECT
                                actual_state = TRY_CAST(actual_state AS INTEGER)
                            FROM
                            (
                                SELECT
                                    actual_state
                                FROM OPENDATASOURCE(
                                    ''SQLNCLI'',
                                    ''Data Source=(local);Integrated Security=SSPI'').'
                                    + QUOTENAME(dl.database_name) 
                                    + '.sys.database_query_store_options
                            ) AS x
                        ) AS y
                    )
                FROM @database_list AS dl
                OPTION (RECOMPILE);
            END TRY
            BEGIN CATCH
                -- Ignore errors because we will recheck individual databases
            END CATCH;
            ';
                    
        EXECUTE sys.sp_executesql 
            @sql,
            N'@database_list @database_list READONLY',
            @database_list;
        
        -- Remove databases with query store disabled
        DELETE 
            @database_list
        WHERE
            qs_enabled = 0
        OR  qs_readonly = 1;
        
        IF @debug = 1
        BEGIN
            SELECT
                db_list = N'Final database list',
                dl.database_id,
                dl.database_name,
                dl.qs_enabled,
                dl.qs_readonly
            FROM @database_list AS dl
            ORDER BY
                dl.database_name;
                
            IF NOT EXISTS (SELECT 1 FROM @database_list)
            BEGIN
                RAISERROR(N'No databases with active query store found, collection skipped', 11, 1) WITH NOWAIT;
                RETURN;
            END;
        END;
        
        /*
        Create collection tables if they don't exist
        */
        IF OBJECT_ID('collection.query_store_queries') IS NULL
        BEGIN
            CREATE TABLE
                collection.query_store_queries
            (
                collection_time DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
                database_name NVARCHAR(128) NOT NULL,
                query_id BIGINT NOT NULL,
                query_text_id BIGINT NOT NULL,
                query_hash BINARY(8) NULL,
                query_parameterization_type_desc NVARCHAR(60) NULL,
                initial_compile_start_time DATETIME2(7) NULL,
                last_compile_start_time DATETIME2(7) NULL,
                last_execution_time DATETIME2(7) NULL,
                object_id BIGINT NULL,
                object_name NVARCHAR(256) NULL,
                is_internal_query BIT NULL,
                query_text NVARCHAR(MAX) NULL,
                INDEX CIX_query_store_queries
                (
                    collection_time,
                    database_name,
                    query_id
                )
            );
            
            IF @debug = 1
            BEGIN
                RAISERROR(N'Created collection.query_store_queries', 0, 1) WITH NOWAIT;
            END;
        END;
        
        IF OBJECT_ID('collection.query_store_plans') IS NULL
        BEGIN
            CREATE TABLE
                collection.query_store_plans
            (
                collection_time DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
                database_name NVARCHAR(128) NOT NULL,
                plan_id BIGINT NOT NULL,
                query_id BIGINT NOT NULL,
                plan_group_id BIGINT NULL,
                engine_version NVARCHAR(32) NULL,
                compatibility_level INTEGER NULL,
                query_plan_hash BINARY(8) NULL,
                query_plan XML NULL,
                is_online_index_plan BIT NULL,
                is_trivial_plan BIT NULL,
                is_parallel_plan BIT NULL,
                is_forced_plan BIT NULL,
                force_failure_count BIGINT NULL,
                last_force_failure_reason_desc NVARCHAR(128) NULL,
                count_compiles BIGINT NULL,
                initial_compile_start_time DATETIME2(7) NULL,
                last_compile_start_time DATETIME2(7) NULL,
                last_execution_time DATETIME2(7) NULL,
                INDEX CIX_query_store_plans
                (
                    collection_time,
                    database_name,
                    plan_id
                )
            );
            
            IF @debug = 1
            BEGIN
                RAISERROR(N'Created collection.query_store_plans', 0, 1) WITH NOWAIT;
            END;
        END;
        
        IF OBJECT_ID('collection.query_store_runtime_stats') IS NULL
        BEGIN
            CREATE TABLE
                collection.query_store_runtime_stats
            (
                collection_time DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
                database_name NVARCHAR(128) NOT NULL,
                runtime_stats_id BIGINT NOT NULL,
                plan_id BIGINT NOT NULL,
                runtime_stats_interval_id BIGINT NOT NULL,
                start_time DATETIME2(7) NULL,
                end_time DATETIME2(7) NULL,
                execution_type_desc NVARCHAR(60) NULL,
                count_executions BIGINT NULL,
                cpu_time_min BIGINT NULL,
                cpu_time_max BIGINT NULL,
                cpu_time_avg BIGINT NULL,
                duration_min BIGINT NULL,
                duration_max BIGINT NULL,
                duration_avg BIGINT NULL,
                physical_io_reads_min BIGINT NULL,
                physical_io_reads_max BIGINT NULL,
                physical_io_reads_avg BIGINT NULL,
                logical_io_reads_min BIGINT NULL,
                logical_io_reads_max BIGINT NULL,
                logical_io_reads_avg BIGINT NULL,
                logical_io_writes_min BIGINT NULL,
                logical_io_writes_max BIGINT NULL,
                logical_io_writes_avg BIGINT NULL,
                clr_time_min BIGINT NULL,
                clr_time_max BIGINT NULL,
                clr_time_avg BIGINT NULL,
                dop_min BIGINT NULL,
                dop_max BIGINT NULL,
                dop_avg BIGINT NULL,
                query_max_used_memory_min BIGINT NULL,
                query_max_used_memory_max BIGINT NULL,
                query_max_used_memory_avg BIGINT NULL,
                rowcount_min BIGINT NULL,
                rowcount_max BIGINT NULL,
                rowcount_avg BIGINT NULL,
                tempdb_space_used_min BIGINT NULL,
                tempdb_space_used_max BIGINT NULL,
                tempdb_space_used_avg BIGINT NULL,
                log_bytes_used_min BIGINT NULL,
                log_bytes_used_max BIGINT NULL,
                log_bytes_used_avg BIGINT NULL,
                memory_consumption_min BIGINT NULL,
                memory_consumption_max BIGINT NULL,
                memory_consumption_avg BIGINT NULL,
                NUM_PHYSICAL_IO_READS BIGINT NULL,
                INDEX CIX_query_store_runtime_stats
                (
                    collection_time,
                    database_name,
                    runtime_stats_id
                )
            );
            
            IF @debug = 1
            BEGIN
                RAISERROR(N'Created collection.query_store_runtime_stats', 0, 1) WITH NOWAIT;
            END;
        END;
        
        IF OBJECT_ID('collection.query_store_wait_stats') IS NULL
        BEGIN
            CREATE TABLE
                collection.query_store_wait_stats
            (
                collection_time DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
                database_name NVARCHAR(128) NOT NULL,
                wait_stats_id BIGINT NOT NULL,
                plan_id BIGINT NOT NULL,
                runtime_stats_interval_id BIGINT NOT NULL,
                wait_category_desc NVARCHAR(60) NULL,
                execution_type_desc NVARCHAR(60) NULL,
                total_query_wait_time_ms BIGINT NULL,
                avg_query_wait_time_ms BIGINT NULL,
                last_query_wait_time_ms BIGINT NULL,
                min_query_wait_time_ms BIGINT NULL,
                max_query_wait_time_ms BIGINT NULL,
                stdev_query_wait_time_ms BIGINT NULL,
                INDEX CIX_query_store_wait_stats
                (
                    collection_time,
                    database_name,
                    wait_stats_id
                )
            );
            
            IF @debug = 1
            BEGIN
                RAISERROR(N'Created collection.query_store_wait_stats', 0, 1) WITH NOWAIT;
            END;
        END;
        
        /*
        Loop through each database and collect query store data
        */
        DECLARE
            db_cursor CURSOR LOCAL FORWARD_ONLY STATIC READ_ONLY
        FOR
            SELECT
                database_name
            FROM @database_list
            ORDER BY
                database_name;
                
        OPEN db_cursor;
        
        FETCH NEXT FROM
            db_cursor
        INTO
            @database_name;
            
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @collection_count = @collection_count + 1;
            
            IF @debug = 1
            BEGIN
                RAISERROR(N'Processing database %s (%d of %d)', 0, 1, 
                @database_name, @collection_count, 
                (SELECT COUNT(*) FROM @database_list)) WITH NOWAIT;
            END;
            
            BEGIN TRY
                /*
                Collect query store data
                */
                
                -- Query and text collection
                IF @include_query_text = 1
                BEGIN
                    SELECT
                        @sql = N'
                        INSERT
                            collection.query_store_queries
                        (
                            collection_time,
                            database_name,
                            query_id,
                            query_text_id,
                            query_hash,
                            query_parameterization_type_desc,
                            initial_compile_start_time,
                            last_compile_start_time,
                            last_execution_time,
                            object_id,
                            object_name,
                            is_internal_query,
                            query_text
                        )
                        SELECT
                            collection_time = SYSDATETIME(),
                            database_name = N''' + @database_name + N''',
                            q.query_id,
                            q.query_text_id,
                            q.query_hash,
                            q.query_parameterization_type_desc,
                            q.initial_compile_start_time,
                            q.last_compile_start_time,
                            q.last_execution_time,
                            q.object_id,
                            object_name = QUOTENAME(ISNULL(OBJECT_SCHEMA_NAME(q.object_id, DB_ID(''' + @database_name + N''')), N'''')) + N''.'' + 
                                       QUOTENAME(ISNULL(OBJECT_NAME(q.object_id, DB_ID(''' + @database_name + N''')), N'''')),
                            q.is_internal_query,
                            query_text = qt.query_sql_text
                        FROM OPENDATASOURCE(
                            ''SQLNCLI'',
                            ''Data Source=(local);Integrated Security=SSPI'').'
                            + QUOTENAME(@database_name) 
                            + '.sys.query_store_query AS q
                        JOIN OPENDATASOURCE(
                            ''SQLNCLI'',
                            ''Data Source=(local);Integrated Security=SSPI'').'
                            + QUOTENAME(@database_name) 
                            + '.sys.query_store_query_text AS qt
                          ON q.query_text_id = qt.query_text_id
                        JOIN OPENDATASOURCE(
                            ''SQLNCLI'',
                            ''Data Source=(local);Integrated Security=SSPI'').'
                            + QUOTENAME(@database_name) 
                            + '.sys.query_store_plan AS p
                          ON q.query_id = p.query_id
                        JOIN OPENDATASOURCE(
                            ''SQLNCLI'',
                            ''Data Source=(local);Integrated Security=SSPI'').'
                            + QUOTENAME(@database_name) 
                            + '.sys.query_store_runtime_stats AS rs
                          ON p.plan_id = rs.plan_id
                        WHERE rs.avg_cpu_time >= ' + CONVERT(NVARCHAR(20), @min_cpu_time_ms) + N' * 1000
                        OR rs.avg_logical_io_reads >= ' + CONVERT(NVARCHAR(20), @min_logical_io_reads) + N'
                        OR rs.avg_logical_io_writes >= ' + CONVERT(NVARCHAR(20), @min_logical_io_writes) + N'
                        OR rs.avg_physical_io_reads >= ' + CONVERT(NVARCHAR(20), @min_physical_io_reads) + N'
                        OR rs.avg_clr_time >= ' + CONVERT(NVARCHAR(20), @min_clr_time_ms) + N' * 1000
                        OR rs.avg_dop >= ' + CONVERT(NVARCHAR(20), @min_dop) + N'
                        OR rs.avg_query_max_used_memory >= ' + CONVERT(NVARCHAR(20), @min_query_max_used_memory) + N'
                        OR rs.avg_rowcount >= ' + CONVERT(NVARCHAR(20), @min_rowcount) + N'
                        OR rs.avg_tempdb_space_used >= ' + CONVERT(NVARCHAR(20), @min_tempdb_space) + N'
                        OR rs.avg_log_bytes_used >= ' + CONVERT(NVARCHAR(20), @min_log_bytes_used) + N'
                        ';
                        
                        IF @start_time IS NOT NULL
                        BEGIN
                            SET @sql = @sql + N'
                            AND rs.last_execution_time >= ''' + CONVERT(NVARCHAR(34), @start_time, 126) + N'''';
                        END;
                        
                        IF @end_time IS NOT NULL
                        BEGIN
                            SET @sql = @sql + N'
                            AND rs.last_execution_time <= ''' + CONVERT(NVARCHAR(34), @end_time, 126) + N'''';
                        END;
                        
                        SET @sql = @sql + N'
                        GROUP BY
                            q.query_id,
                            q.query_text_id,
                            q.query_hash,
                            q.query_parameterization_type_desc,
                            q.initial_compile_start_time,
                            q.last_compile_start_time,
                            q.last_execution_time,
                            q.object_id,
                            q.is_internal_query,
                            qt.query_sql_text;
                        ';
                        
                    EXECUTE sys.sp_executesql @sql;
                    
                    IF @debug = 1
                    BEGIN
                        RAISERROR(N'Collected %d queries from %s', 0, 1, @@ROWCOUNT, @database_name) WITH NOWAIT;
                    END;
                END;
                
                -- Plan collection
                IF @include_query_plans = 1
                BEGIN
                    SELECT
                        @sql = N'
                        INSERT
                            collection.query_store_plans
                        (
                            collection_time,
                            database_name,
                            plan_id,
                            query_id,
                            plan_group_id,
                            engine_version,
                            compatibility_level,
                            query_plan_hash,
                            query_plan,
                            is_online_index_plan,
                            is_trivial_plan,
                            is_parallel_plan,
                            is_forced_plan,
                            force_failure_count,
                            last_force_failure_reason_desc,
                            count_compiles,
                            initial_compile_start_time,
                            last_compile_start_time,
                            last_execution_time
                        )
                        SELECT
                            collection_time = SYSDATETIME(),
                            database_name = N''' + @database_name + N''',
                            p.plan_id,
                            p.query_id,
                            p.plan_group_id,
                            p.engine_version,
                            p.compatibility_level,
                            p.query_plan_hash,
                            p.query_plan,
                            p.is_online_index_plan,
                            p.is_trivial_plan,
                            p.is_parallel_plan,
                            p.is_forced_plan,
                            p.force_failure_count,
                            p.last_force_failure_reason_desc,
                            p.count_compiles,
                            p.initial_compile_start_time,
                            p.last_compile_start_time,
                            p.last_execution_time
                        FROM OPENDATASOURCE(
                            ''SQLNCLI'',
                            ''Data Source=(local);Integrated Security=SSPI'').'
                            + QUOTENAME(@database_name) 
                            + '.sys.query_store_plan AS p
                        JOIN OPENDATASOURCE(
                            ''SQLNCLI'',
                            ''Data Source=(local);Integrated Security=SSPI'').'
                            + QUOTENAME(@database_name) 
                            + '.sys.query_store_runtime_stats AS rs
                          ON p.plan_id = rs.plan_id
                        WHERE rs.avg_cpu_time >= ' + CONVERT(NVARCHAR(20), @min_cpu_time_ms) + N' * 1000
                        OR rs.avg_logical_io_reads >= ' + CONVERT(NVARCHAR(20), @min_logical_io_reads) + N'
                        OR rs.avg_logical_io_writes >= ' + CONVERT(NVARCHAR(20), @min_logical_io_writes) + N'
                        OR rs.avg_physical_io_reads >= ' + CONVERT(NVARCHAR(20), @min_physical_io_reads) + N'
                        OR rs.avg_clr_time >= ' + CONVERT(NVARCHAR(20), @min_clr_time_ms) + N' * 1000
                        OR rs.avg_dop >= ' + CONVERT(NVARCHAR(20), @min_dop) + N'
                        OR rs.avg_query_max_used_memory >= ' + CONVERT(NVARCHAR(20), @min_query_max_used_memory) + N'
                        OR rs.avg_rowcount >= ' + CONVERT(NVARCHAR(20), @min_rowcount) + N'
                        OR rs.avg_tempdb_space_used >= ' + CONVERT(NVARCHAR(20), @min_tempdb_space) + N'
                        OR rs.avg_log_bytes_used >= ' + CONVERT(NVARCHAR(20), @min_log_bytes_used) + N'
                        ';
                        
                        IF @start_time IS NOT NULL
                        BEGIN
                            SET @sql = @sql + N'
                            AND rs.last_execution_time >= ''' + CONVERT(NVARCHAR(34), @start_time, 126) + N'''';
                        END;
                        
                        IF @end_time IS NOT NULL
                        BEGIN
                            SET @sql = @sql + N'
                            AND rs.last_execution_time <= ''' + CONVERT(NVARCHAR(34), @end_time, 126) + N'''';
                        END;
                        
                        SET @sql = @sql + N'
                        GROUP BY
                            p.plan_id,
                            p.query_id,
                            p.plan_group_id,
                            p.engine_version,
                            p.compatibility_level,
                            p.query_plan_hash,
                            p.query_plan,
                            p.is_online_index_plan,
                            p.is_trivial_plan,
                            p.is_parallel_plan,
                            p.is_forced_plan,
                            p.force_failure_count,
                            p.last_force_failure_reason_desc,
                            p.count_compiles,
                            p.initial_compile_start_time,
                            p.last_compile_start_time,
                            p.last_execution_time;
                        ';
                        
                    EXECUTE sys.sp_executesql @sql;
                    
                    IF @debug = 1
                    BEGIN
                        RAISERROR(N'Collected %d plans from %s', 0, 1, @@ROWCOUNT, @database_name) WITH NOWAIT;
                    END;
                END;
                
                -- Runtime stats collection
                IF @include_runtime_stats = 1
                BEGIN
                    SELECT
                        @sql = N'
                        INSERT
                            collection.query_store_runtime_stats
                        (
                            collection_time,
                            database_name,
                            runtime_stats_id,
                            plan_id,
                            runtime_stats_interval_id,
                            start_time,
                            end_time,
                            execution_type_desc,
                            count_executions,
                            cpu_time_min,
                            cpu_time_max,
                            cpu_time_avg,
                            duration_min,
                            duration_max,
                            duration_avg,
                            physical_io_reads_min,
                            physical_io_reads_max,
                            physical_io_reads_avg,
                            logical_io_reads_min,
                            logical_io_reads_max,
                            logical_io_reads_avg,
                            logical_io_writes_min,
                            logical_io_writes_max,
                            logical_io_writes_avg,
                            clr_time_min,
                            clr_time_max,
                            clr_time_avg,
                            dop_min,
                            dop_max,
                            dop_avg,
                            query_max_used_memory_min,
                            query_max_used_memory_max,
                            query_max_used_memory_avg,
                            rowcount_min,
                            rowcount_max,
                            rowcount_avg,
                            tempdb_space_used_min,
                            tempdb_space_used_max,
                            tempdb_space_used_avg,
                            log_bytes_used_min,
                            log_bytes_used_max,
                            log_bytes_used_avg,
                            memory_consumption_min,
                            memory_consumption_max,
                            memory_consumption_avg,
                            NUM_PHYSICAL_IO_READS
                        )
                        SELECT
                            collection_time = SYSDATETIME(),
                            database_name = N''' + @database_name + N''',
                            rs.runtime_stats_id,
                            rs.plan_id,
                            rs.runtime_stats_interval_id,
                            i.start_time,
                            i.end_time,
                            rs.execution_type_desc,
                            rs.count_executions,
                            rs.min_cpu_time,
                            rs.max_cpu_time,
                            rs.avg_cpu_time,
                            rs.min_duration,
                            rs.max_duration,
                            rs.avg_duration,
                            rs.min_physical_io_reads,
                            rs.max_physical_io_reads,
                            rs.avg_physical_io_reads,
                            rs.min_logical_io_reads,
                            rs.max_logical_io_reads,
                            rs.avg_logical_io_reads,
                            rs.min_logical_io_writes,
                            rs.max_logical_io_writes,
                            rs.avg_logical_io_writes,
                            rs.min_clr_time,
                            rs.max_clr_time,
                            rs.avg_clr_time,
                            rs.min_dop,
                            rs.max_dop,
                            rs.avg_dop,
                            rs.min_query_max_used_memory,
                            rs.max_query_max_used_memory,
                            rs.avg_query_max_used_memory,
                            rs.min_rowcount,
                            rs.max_rowcount,
                            rs.avg_rowcount,
                            rs.min_tempdb_space_used,
                            rs.max_tempdb_space_used,
                            rs.avg_tempdb_space_used,
                            rs.min_log_bytes_used,
                            rs.max_log_bytes_used,
                            rs.avg_log_bytes_used,
                            rs.min_memory_consumption,
                            rs.max_memory_consumption,
                            rs.avg_memory_consumption,
                            rs.last_physical_io_reads
                        FROM OPENDATASOURCE(
                            ''SQLNCLI'',
                            ''Data Source=(local);Integrated Security=SSPI'').'
                            + QUOTENAME(@database_name) 
                            + '.sys.query_store_runtime_stats AS rs
                        JOIN OPENDATASOURCE(
                            ''SQLNCLI'',
                            ''Data Source=(local);Integrated Security=SSPI'').'
                            + QUOTENAME(@database_name) 
                            + '.sys.query_store_runtime_stats_interval AS i
                          ON rs.runtime_stats_interval_id = i.runtime_stats_interval_id
                        WHERE rs.avg_cpu_time >= ' + CONVERT(NVARCHAR(20), @min_cpu_time_ms) + N' * 1000
                        OR rs.avg_logical_io_reads >= ' + CONVERT(NVARCHAR(20), @min_logical_io_reads) + N'
                        OR rs.avg_logical_io_writes >= ' + CONVERT(NVARCHAR(20), @min_logical_io_writes) + N'
                        OR rs.avg_physical_io_reads >= ' + CONVERT(NVARCHAR(20), @min_physical_io_reads) + N'
                        OR rs.avg_clr_time >= ' + CONVERT(NVARCHAR(20), @min_clr_time_ms) + N' * 1000
                        OR rs.avg_dop >= ' + CONVERT(NVARCHAR(20), @min_dop) + N'
                        OR rs.avg_query_max_used_memory >= ' + CONVERT(NVARCHAR(20), @min_query_max_used_memory) + N'
                        OR rs.avg_rowcount >= ' + CONVERT(NVARCHAR(20), @min_rowcount) + N'
                        OR rs.avg_tempdb_space_used >= ' + CONVERT(NVARCHAR(20), @min_tempdb_space) + N'
                        OR rs.avg_log_bytes_used >= ' + CONVERT(NVARCHAR(20), @min_log_bytes_used) + N'
                        ';
                        
                        IF @start_time IS NOT NULL
                        BEGIN
                            SET @sql = @sql + N'
                            AND i.end_time >= ''' + CONVERT(NVARCHAR(34), @start_time, 126) + N'''';
                        END;
                        
                        IF @end_time IS NOT NULL
                        BEGIN
                            SET @sql = @sql + N'
                            AND i.start_time <= ''' + CONVERT(NVARCHAR(34), @end_time, 126) + N'''';
                        END;
                        
                    EXECUTE sys.sp_executesql @sql;
                    
                    IF @debug = 1
                    BEGIN
                        RAISERROR(N'Collected %d runtime stats from %s', 0, 1, @@ROWCOUNT, @database_name) WITH NOWAIT;
                    END;
                END;
                
                -- Wait stats collection
                IF @include_wait_stats = 1
                BEGIN
                    SELECT
                        @sql = N'
                        INSERT
                            collection.query_store_wait_stats
                        (
                            collection_time,
                            database_name,
                            wait_stats_id,
                            plan_id,
                            runtime_stats_interval_id,
                            wait_category_desc,
                            execution_type_desc,
                            total_query_wait_time_ms,
                            avg_query_wait_time_ms,
                            last_query_wait_time_ms,
                            min_query_wait_time_ms,
                            max_query_wait_time_ms,
                            stdev_query_wait_time_ms
                        )
                        SELECT
                            collection_time = SYSDATETIME(),
                            database_name = N''' + @database_name + N''',
                            ws.wait_stats_id,
                            ws.plan_id,
                            ws.runtime_stats_interval_id,
                            ws.wait_category_desc,
                            ws.execution_type_desc,
                            ws.total_query_wait_time_ms,
                            ws.avg_query_wait_time_ms,
                            ws.last_query_wait_time_ms,
                            ws.min_query_wait_time_ms,
                            ws.max_query_wait_time_ms,
                            ws.stdev_query_wait_time_ms
                        FROM OPENDATASOURCE(
                            ''SQLNCLI'',
                            ''Data Source=(local);Integrated Security=SSPI'').'
                            + QUOTENAME(@database_name) 
                            + '.sys.query_store_wait_stats AS ws
                        JOIN OPENDATASOURCE(
                            ''SQLNCLI'',
                            ''Data Source=(local);Integrated Security=SSPI'').'
                            + QUOTENAME(@database_name) 
                            + '.sys.query_store_runtime_stats AS rs
                          ON ws.plan_id = rs.plan_id
                          AND ws.runtime_stats_interval_id = rs.runtime_stats_interval_id
                        JOIN OPENDATASOURCE(
                            ''SQLNCLI'',
                            ''Data Source=(local);Integrated Security=SSPI'').'
                            + QUOTENAME(@database_name) 
                            + '.sys.query_store_runtime_stats_interval AS i
                          ON rs.runtime_stats_interval_id = i.runtime_stats_interval_id
                        WHERE rs.avg_cpu_time >= ' + CONVERT(NVARCHAR(20), @min_cpu_time_ms) + N' * 1000
                        OR rs.avg_logical_io_reads >= ' + CONVERT(NVARCHAR(20), @min_logical_io_reads) + N'
                        OR rs.avg_logical_io_writes >= ' + CONVERT(NVARCHAR(20), @min_logical_io_writes) + N'
                        OR rs.avg_physical_io_reads >= ' + CONVERT(NVARCHAR(20), @min_physical_io_reads) + N'
                        OR rs.avg_clr_time >= ' + CONVERT(NVARCHAR(20), @min_clr_time_ms) + N' * 1000
                        OR rs.avg_dop >= ' + CONVERT(NVARCHAR(20), @min_dop) + N'
                        OR rs.avg_query_max_used_memory >= ' + CONVERT(NVARCHAR(20), @min_query_max_used_memory) + N'
                        OR rs.avg_rowcount >= ' + CONVERT(NVARCHAR(20), @min_rowcount) + N'
                        OR rs.avg_tempdb_space_used >= ' + CONVERT(NVARCHAR(20), @min_tempdb_space) + N'
                        OR rs.avg_log_bytes_used >= ' + CONVERT(NVARCHAR(20), @min_log_bytes_used) + N'
                        ';
                        
                        IF @start_time IS NOT NULL
                        BEGIN
                            SET @sql = @sql + N'
                            AND i.end_time >= ''' + CONVERT(NVARCHAR(34), @start_time, 126) + N'''';
                        END;
                        
                        IF @end_time IS NOT NULL
                        BEGIN
                            SET @sql = @sql + N'
                            AND i.start_time <= ''' + CONVERT(NVARCHAR(34), @end_time, 126) + N'''';
                        END;
                        
                    EXECUTE sys.sp_executesql @sql;
                    
                    IF @debug = 1
                    BEGIN
                        RAISERROR(N'Collected %d wait stats from %s', 0, 1, @@ROWCOUNT, @database_name) WITH NOWAIT;
                    END;
                END;
            END TRY
            BEGIN CATCH
                SET @error_number = ERROR_NUMBER();
                SET @error_severity = ERROR_SEVERITY();
                SET @error_state = ERROR_STATE();
                SET @error_line = ERROR_LINE();
                SET @error_message = ERROR_MESSAGE();
                
                RAISERROR(N'Error collecting query store data from database %s: Error %d at line %d - %s', 
                    11, 1, @database_name, @error_number, @error_line, @error_message) WITH NOWAIT;
            END CATCH;
            
            FETCH NEXT FROM
                db_cursor
            INTO
                @database_name;
        END;
        
        CLOSE db_cursor;
        DEALLOCATE db_cursor;
        
        SET @collection_ending = SYSDATETIME();
        
        IF @debug = 1
        BEGIN
            RAISERROR(N'Query store collection completed at %s', 0, 1, @collection_ending) WITH NOWAIT;
            RAISERROR(N'Total execution time: %d seconds', 0, 1, 
                DATEDIFF(SECOND, @collection_starting, @collection_ending)) WITH NOWAIT;
        END;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
        BEGIN
            ROLLBACK TRANSACTION;
        END;
        
        IF CURSOR_STATUS('local', 'db_cursor') <> -3
        BEGIN
            CLOSE db_cursor;
            DEALLOCATE db_cursor;
        END;
        
        SET @error_number = ERROR_NUMBER();
        SET @error_severity = ERROR_SEVERITY();
        SET @error_state = ERROR_STATE();
        SET @error_line = ERROR_LINE();
        SET @error_message = ERROR_MESSAGE();
        
        RAISERROR(N'Error %d at line %d: %s', 11, 1, @error_number, @error_line, @error_message) WITH NOWAIT;
        THROW;
    END CATCH;
END;
GO