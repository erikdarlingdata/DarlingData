SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('analysis.top_queries', 'P') IS NULL
BEGIN
    EXECUTE ('CREATE PROCEDURE analysis.top_queries AS RETURN 0;');
END;
GO

/*
/**************************************************************
* 
* Query Analysis Procedure for DarlingDataCollector
* 
* Copyright (C) Darling Data, LLC
* 
* Creates narratives about query performance based on collected data
* 
**************************************************************/
*/

CREATE OR ALTER PROCEDURE
    analysis.top_queries
(
    @start_date DATETIME2(7) = NULL, /*Starting date range for analysis*/
    @end_date DATETIME2(7) = NULL, /*Ending date range for analysis*/
    @database_name NVARCHAR(128) = NULL, /*Specific database to analyze*/
    @top INTEGER = 10, /*Number of top queries to analyze*/
    @metric_filter NVARCHAR(50) = 'CPU', /*Filter by: CPU, READS, WRITES, DURATION, MEMORY, TEMPDB, or ALL*/
    @story_mode BIT = 1, /*Set to 1 for narrative output, 0 for tabular data*/
    @debug BIT = 0, /*Print debugging information*/
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
            @collection_min_date DATETIME2(7),
            @collection_max_date DATETIME2(7),
            @server_name NVARCHAR(256) = @@SERVERNAME,
            @database_count INTEGER = 0,
            @query_count INTEGER = 0,
            @metric_name NVARCHAR(100) = N'',
            @narrative NVARCHAR(MAX) = N'',
            @error_number INTEGER = 0,
            @error_severity INTEGER = 0,
            @error_state INTEGER = 0,
            @error_line INTEGER = 0,
            @error_message NVARCHAR(4000) = N'';
            
        DECLARE 
            @query_metrics TABLE
            (
                query_rank INTEGER IDENTITY(1, 1) NOT NULL,
                database_name NVARCHAR(128) NOT NULL,
                query_id BIGINT NOT NULL,
                object_name NVARCHAR(256) NULL,
                query_text NVARCHAR(MAX) NULL,
                execution_count BIGINT NULL,
                total_cpu_time BIGINT NULL,
                avg_cpu_time BIGINT NULL, 
                max_cpu_time BIGINT NULL,
                total_logical_reads BIGINT NULL,
                avg_logical_reads BIGINT NULL,
                max_logical_reads BIGINT NULL,
                total_physical_reads BIGINT NULL,
                avg_physical_reads BIGINT NULL,
                max_physical_reads BIGINT NULL,
                total_logical_writes BIGINT NULL,
                avg_logical_writes BIGINT NULL,
                max_logical_writes BIGINT NULL,
                total_duration BIGINT NULL,
                avg_duration BIGINT NULL,
                max_duration BIGINT NULL,
                total_tempdb_space BIGINT NULL,
                avg_tempdb_space BIGINT NULL,
                max_tempdb_space BIGINT NULL,
                total_memory_grant BIGINT NULL,
                avg_memory_grant BIGINT NULL,
                max_memory_grant BIGINT NULL,
                first_execution_time DATETIME2(7) NULL,
                last_execution_time DATETIME2(7) NULL,
                PRIMARY KEY (query_rank)
            );
            
        /*
        Parameter validation
        */
        IF @help = 1
        BEGIN
            SELECT
                help = N'This procedure analyzes collected query data and generates a performance narrative.
                
Parameters:
  @start_date = Starting date range for analysis (default: 24 hours ago)
  @end_date = Ending date range for analysis (default: current time)
  @database_name = Specific database to analyze (default: all databases)
  @top = Number of top queries to analyze (default: 10)
  @metric_filter = Filter queries by: CPU, READS, WRITES, DURATION, MEMORY, TEMPDB, or ALL (default: CPU)
  @story_mode = 1 for narrative output, 0 for tabular data (default: 1)
  @debug = 1 to print detailed information, 0 for normal operation
  @help = 1 to show this help information

Example usage:
  EXECUTE analysis.top_queries @metric_filter = ''MEMORY'', @top = 5;';
            
            RETURN;
        END;
        
        -- Validate and set date range
        IF @start_date IS NULL 
        BEGIN
            SELECT @start_date = DATEADD(DAY, -1, SYSDATETIME());
        END;
        
        IF @end_date IS NULL
        BEGIN
            SELECT @end_date = SYSDATETIME();
        END;
        
        IF @start_date > @end_date
        BEGIN
            RAISERROR(N'@start_date cannot be greater than @end_date', 11, 1) WITH NOWAIT;
            RETURN;
        END;
        
        -- Validate available data range
        SELECT 
            @collection_min_date = MIN(collection_time),
            @collection_max_date = MAX(collection_time)
        FROM collection.query_stats;
        
        IF @collection_min_date IS NULL OR @collection_max_date IS NULL
        BEGIN
            RAISERROR(N'No query data has been collected yet. Run collection.collect_query_stats first.', 11, 1) WITH NOWAIT;
            RETURN;
        END;
        
        IF @start_date < @collection_min_date
        BEGIN
            RAISERROR(N'Warning: @start_date (%s) is earlier than oldest collection data (%s). Using earliest available data.', 
                0, 1, @start_date, @collection_min_date) WITH NOWAIT;
            SET @start_date = @collection_min_date;
        END;
        
        IF @end_date > @collection_max_date
        BEGIN
            RAISERROR(N'Warning: @end_date (%s) is later than newest collection data (%s). Using latest available data.', 
                0, 1, @end_date, @collection_max_date) WITH NOWAIT;
            SET @end_date = @collection_max_date;
        END;
        
        -- Validate metric filter
        IF @metric_filter NOT IN (N'CPU', N'READS', N'WRITES', N'DURATION', N'MEMORY', N'TEMPDB', N'ALL')
        BEGIN
            RAISERROR(N'Invalid @metric_filter. Must be one of: CPU, READS, WRITES, DURATION, MEMORY, TEMPDB, or ALL', 11, 1) WITH NOWAIT;
            RETURN;
        END;
        
        -- Set friendly metric name for narratives
        SELECT @metric_name = 
            CASE @metric_filter
                WHEN N'CPU' THEN N'CPU time'
                WHEN N'READS' THEN N'logical reads'
                WHEN N'WRITES' THEN N'logical writes'
                WHEN N'DURATION' THEN N'duration'
                WHEN N'MEMORY' THEN N'memory grant'
                WHEN N'TEMPDB' THEN N'tempdb usage'
                WHEN N'ALL' THEN N'overall resource usage'
            END;
        
        /*
        Collect query metrics
        */
        IF @debug = 1
        BEGIN
            RAISERROR(N'Analyzing top queries from %s to %s filtered by %s', 0, 1, 
                @start_date, @end_date, @metric_filter) WITH NOWAIT;
        END;
        
        -- Query store data if available
        IF EXISTS (SELECT 1 FROM collection.query_store_runtime_stats WHERE collection_time BETWEEN @start_date AND @end_date)
        BEGIN
            IF @debug = 1
            BEGIN
                RAISERROR(N'Using Query Store data for analysis', 0, 1) WITH NOWAIT;
            END;
            
            INSERT @query_metrics
            (
                database_name,
                query_id,
                object_name,
                query_text,
                execution_count,
                total_cpu_time,
                avg_cpu_time,
                max_cpu_time,
                total_logical_reads,
                avg_logical_reads,
                max_logical_reads,
                total_logical_writes,
                avg_logical_writes,
                max_logical_writes,
                total_duration,
                avg_duration,
                max_duration,
                total_tempdb_space,
                avg_tempdb_space,
                max_tempdb_space,
                total_memory_grant,
                avg_memory_grant,
                max_memory_grant,
                first_execution_time,
                last_execution_time
            )
            SELECT TOP (@top)
                q.database_name,
                q.query_id,
                q.object_name,
                q.query_text,
                SUM(rs.count_executions),
                SUM(rs.count_executions * rs.avg_cpu_time),
                AVG(rs.avg_cpu_time),
                MAX(rs.max_cpu_time),
                SUM(rs.count_executions * rs.avg_logical_io_reads),
                AVG(rs.avg_logical_io_reads),
                MAX(rs.max_logical_io_reads),
                SUM(rs.count_executions * rs.avg_logical_io_writes),
                AVG(rs.avg_logical_io_writes),
                MAX(rs.max_logical_io_writes),
                SUM(rs.count_executions * rs.avg_duration),
                AVG(rs.avg_duration),
                MAX(rs.max_duration),
                SUM(rs.count_executions * rs.avg_tempdb_space_used),
                AVG(rs.avg_tempdb_space_used),
                MAX(rs.max_tempdb_space_used),
                SUM(rs.count_executions * rs.avg_query_max_used_memory),
                AVG(rs.avg_query_max_used_memory),
                MAX(rs.max_query_max_used_memory),
                MIN(q.initial_compile_start_time),
                MAX(q.last_execution_time)
            FROM collection.query_store_queries AS q
            JOIN collection.query_store_runtime_stats AS rs
              ON q.database_name = rs.database_name
              AND q.query_id = (SELECT query_id FROM collection.query_store_plans WHERE plan_id = rs.plan_id)
            WHERE rs.collection_time BETWEEN @start_date AND @end_date
            AND (@database_name IS NULL OR q.database_name = @database_name)
            GROUP BY
                q.database_name,
                q.query_id,
                q.object_name,
                q.query_text
            ORDER BY
                CASE @metric_filter
                    WHEN N'CPU' THEN SUM(rs.count_executions * rs.avg_cpu_time)
                    WHEN N'READS' THEN SUM(rs.count_executions * rs.avg_logical_io_reads)
                    WHEN N'WRITES' THEN SUM(rs.count_executions * rs.avg_logical_io_writes)
                    WHEN N'DURATION' THEN SUM(rs.count_executions * rs.avg_duration)
                    WHEN N'MEMORY' THEN SUM(rs.count_executions * rs.avg_query_max_used_memory)
                    WHEN N'TEMPDB' THEN SUM(rs.count_executions * rs.avg_tempdb_space_used)
                    WHEN N'ALL' THEN (
                        SUM(rs.count_executions * rs.avg_cpu_time) / 1000 +
                        SUM(rs.count_executions * rs.avg_logical_io_reads) / 100 +
                        SUM(rs.count_executions * rs.avg_duration) / 1000
                    )
                END DESC;
        END
        ELSE
        BEGIN
            -- Use query_stats if query store data isn't available
            IF @debug = 1
            BEGIN
                RAISERROR(N'Using Query Stats data for analysis', 0, 1) WITH NOWAIT;
            END;
            
            INSERT @query_metrics
            (
                database_name,
                query_id,
                object_name,
                query_text,
                execution_count,
                total_cpu_time,
                avg_cpu_time,
                max_cpu_time,
                total_logical_reads,
                avg_logical_reads,
                max_logical_reads,
                total_physical_reads,
                avg_physical_reads,
                max_physical_reads,
                total_logical_writes,
                avg_logical_writes,
                max_logical_writes,
                total_duration,
                avg_duration,
                max_duration,
                total_tempdb_space,
                avg_tempdb_space,
                max_tempdb_space,
                total_memory_grant,
                avg_memory_grant,
                max_memory_grant,
                first_execution_time,
                last_execution_time
            )
            SELECT TOP (@top)
                qs.database_name,
                qs.query_hash, -- Using query_hash in place of query_id
                qs.object_name,
                qs.query_text,
                SUM(qs.execution_count),
                SUM(qs.total_worker_time),
                SUM(qs.total_worker_time) / NULLIF(SUM(qs.execution_count), 0),
                MAX(qs.max_worker_time),
                SUM(qs.total_logical_reads),
                SUM(qs.total_logical_reads) / NULLIF(SUM(qs.execution_count), 0),
                MAX(qs.max_logical_reads),
                SUM(qs.total_physical_reads),
                SUM(qs.total_physical_reads) / NULLIF(SUM(qs.execution_count), 0),
                MAX(qs.max_physical_reads),
                SUM(qs.total_logical_writes),
                SUM(qs.total_logical_writes) / NULLIF(SUM(qs.execution_count), 0),
                MAX(qs.max_logical_writes),
                SUM(qs.total_elapsed_time),
                SUM(qs.total_elapsed_time) / NULLIF(SUM(qs.execution_count), 0),
                MAX(qs.max_elapsed_time),
                SUM(qs.total_used_tempdb_space),
                SUM(qs.total_used_tempdb_space) / NULLIF(SUM(qs.execution_count), 0),
                MAX(qs.max_used_tempdb_space),
                SUM(qs.total_grant_kb),
                SUM(qs.total_grant_kb) / NULLIF(SUM(qs.execution_count), 0),
                MAX(qs.max_grant_kb),
                MIN(qs.creation_time),
                MAX(qs.last_execution_time)
            FROM collection.query_stats AS qs
            WHERE qs.collection_time BETWEEN @start_date AND @end_date
            AND (@database_name IS NULL OR qs.database_name = @database_name)
            GROUP BY
                qs.database_name,
                qs.query_hash,
                qs.object_name,
                qs.query_text
            ORDER BY
                CASE @metric_filter
                    WHEN N'CPU' THEN SUM(qs.total_worker_time)
                    WHEN N'READS' THEN SUM(qs.total_logical_reads)
                    WHEN N'WRITES' THEN SUM(qs.total_logical_writes)
                    WHEN N'DURATION' THEN SUM(qs.total_elapsed_time)
                    WHEN N'MEMORY' THEN SUM(qs.total_grant_kb)
                    WHEN N'TEMPDB' THEN SUM(qs.total_used_tempdb_space)
                    WHEN N'ALL' THEN (
                        SUM(qs.total_worker_time) / 1000 +
                        SUM(qs.total_logical_reads) / 100 +
                        SUM(qs.total_elapsed_time) / 1000
                    )
                END DESC;
        END;
        
        SET @query_count = @@ROWCOUNT;
        
        IF @query_count = 0
        BEGIN
            SELECT narrative = N'🔍 No queries found matching the filter criteria';
            RETURN;
        END;
        
        -- Get database count
        SELECT @database_count = COUNT(DISTINCT database_name)
        FROM @query_metrics;
        
        /*
        Generate narrative
        */
        IF @story_mode = 1
        BEGIN
            -- Introduction section
            SET @narrative = N'# SQL Server Performance Story: ' + @server_name + CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10);
            SET @narrative += N'## Top Queries by ' + @metric_name + N' (' + 
                CONVERT(NVARCHAR(30), @start_date, 120) + N' to ' + 
                CONVERT(NVARCHAR(30), @end_date, 120) + N')' + CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10);
                
            IF @database_name IS NULL
            BEGIN
                SET @narrative += N'Analyzed ' + CONVERT(NVARCHAR(10), @database_count) + 
                    N' database' + CASE WHEN @database_count <> 1 THEN N's' ELSE N'' END + N'.' + 
                    CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10);
            END
            ELSE
            BEGIN
                SET @narrative += N'Focused on the `' + @database_name + N'` database.' + 
                    CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10);
            END;
            
            -- Overall summary section
            IF EXISTS (SELECT 1 FROM @query_metrics WHERE object_name IS NOT NULL)
            BEGIN
                DECLARE @proc_count INTEGER = (SELECT COUNT(*) FROM @query_metrics WHERE object_name IS NOT NULL);
                SET @narrative += N'📊 ' + CONVERT(NVARCHAR(10), @proc_count) + 
                    N' of the top ' + CONVERT(NVARCHAR(10), @query_count) + N' queries are stored procedures.' +
                    CHAR(13) + CHAR(10);
            END;
            
            -- Generate detailed query narratives
            DECLARE
                @current_rank INTEGER = 1,
                @db_name NVARCHAR(128),
                @object_nm NVARCHAR(256),
                @query_tx NVARCHAR(MAX),
                @exec_count BIGINT,
                @avg_cpu BIGINT,
                @max_cpu BIGINT,
                @avg_reads BIGINT,
                @max_reads BIGINT,
                @avg_writes BIGINT,
                @max_writes BIGINT,
                @avg_duration BIGINT,
                @max_duration BIGINT,
                @first_exec DATETIME2(7),
                @last_exec DATETIME2(7),
                @query_age_days FLOAT,
                @avg_memory BIGINT,
                @max_memory BIGINT,
                @avg_tempdb BIGINT,
                @max_tempdb BIGINT;
                
            WHILE @current_rank <= @query_count
            BEGIN
                SELECT
                    @db_name = database_name,
                    @object_nm = object_name,
                    @query_tx = query_text,
                    @exec_count = execution_count,
                    @avg_cpu = avg_cpu_time,
                    @max_cpu = max_cpu_time,
                    @avg_reads = avg_logical_reads,
                    @max_reads = max_logical_reads,
                    @avg_writes = avg_logical_writes,
                    @max_writes = max_logical_writes,
                    @avg_duration = avg_duration,
                    @max_duration = max_duration,
                    @first_exec = first_execution_time,
                    @last_exec = last_execution_time,
                    @avg_memory = avg_memory_grant,
                    @max_memory = max_memory_grant,
                    @avg_tempdb = avg_tempdb_space,
                    @max_tempdb = max_tempdb_space
                FROM @query_metrics
                WHERE query_rank = @current_rank;
                
                -- Calculate query age
                SET @query_age_days = DATEDIFF(DAY, @first_exec, @last_exec);
                
                -- Generate individual query narrative
                SET @narrative += CHAR(13) + CHAR(10) + N'### ' + CONVERT(NVARCHAR(10), @current_rank) + N'. ' + 
                    CASE WHEN @object_nm IS NOT NULL THEN N'Procedure: `' + @object_nm + N'`' 
                         ELSE N'Ad-hoc Query' END + 
                    N' in `' + @db_name + N'`' + CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10);
                
                -- Execution pattern
                SET @narrative += N'⚡ Executed **' + CONVERT(NVARCHAR(20), @exec_count) + N' times** ' +
                    CASE
                        WHEN @query_age_days < 1 THEN N'today'
                        WHEN @query_age_days < 7 THEN N'over the past ' + CONVERT(NVARCHAR(10), @query_age_days) + N' days'
                        ELSE N'since ' + CONVERT(NVARCHAR(20), @first_exec, 120)
                    END + N'.' + CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10);
                    
                -- Resource metrics based on filter
                IF @metric_filter IN (N'CPU', N'ALL')
                BEGIN
                    SET @narrative += N'🔥 **CPU Time**: ' + 
                        N'Avg: ' + CONVERT(NVARCHAR(20), @avg_cpu / 1000) + N'ms, ' +
                        N'Max: ' + CONVERT(NVARCHAR(20), @max_cpu / 1000) + N'ms.' + CHAR(13) + CHAR(10);
                END;
                
                IF @metric_filter IN (N'READS', N'ALL')
                BEGIN
                    SET @narrative += N'📖 **Logical Reads**: ' + 
                        N'Avg: ' + CONVERT(NVARCHAR(20), @avg_reads) + N' pages, ' +
                        N'Max: ' + CONVERT(NVARCHAR(20), @max_reads) + N' pages.' + CHAR(13) + CHAR(10);
                END;
                
                IF @metric_filter IN (N'WRITES', N'ALL')
                BEGIN
                    SET @narrative += N'✍️ **Logical Writes**: ' + 
                        N'Avg: ' + CONVERT(NVARCHAR(20), @avg_writes) + N' pages, ' +
                        N'Max: ' + CONVERT(NVARCHAR(20), @max_writes) + N' pages.' + CHAR(13) + CHAR(10);
                END;
                
                IF @metric_filter IN (N'DURATION', N'ALL')
                BEGIN
                    SET @narrative += N'⏱️ **Duration**: ' + 
                        N'Avg: ' + CONVERT(NVARCHAR(20), @avg_duration / 1000) + N'ms, ' +
                        N'Max: ' + CONVERT(NVARCHAR(20), @max_duration / 1000) + N'ms.' + CHAR(13) + CHAR(10);
                END;
                
                IF @metric_filter IN (N'MEMORY', N'ALL') AND @avg_memory IS NOT NULL
                BEGIN
                    SET @narrative += N'🧠 **Memory Grant**: ' + 
                        N'Avg: ' + CONVERT(NVARCHAR(20), @avg_memory / 1024) + N'MB, ' +
                        N'Max: ' + CONVERT(NVARCHAR(20), @max_memory / 1024) + N'MB.' + CHAR(13) + CHAR(10);
                END;
                
                IF @metric_filter IN (N'TEMPDB', N'ALL') AND @avg_tempdb IS NOT NULL
                BEGIN
                    SET @narrative += N'📁 **TempDB Usage**: ' + 
                        N'Avg: ' + CONVERT(NVARCHAR(20), @avg_tempdb / 1024) + N'MB, ' +
                        N'Max: ' + CONVERT(NVARCHAR(20), @max_tempdb / 1024) + N'MB.' + CHAR(13) + CHAR(10);
                END;
                
                -- Add query text
                SET @narrative += CHAR(13) + CHAR(10) + N'```sql' + CHAR(13) + CHAR(10) + 
                    LEFT(@query_tx, 1000) + 
                    CASE WHEN LEN(@query_tx) > 1000 THEN N'...' ELSE N'' END +
                    CHAR(13) + CHAR(10) + N'```' + CHAR(13) + CHAR(10);
                    
                -- Add insights
                SET @narrative += CHAR(13) + CHAR(10) + N'💡 **Insights**:' + CHAR(13) + CHAR(10);
                
                -- Generate insight based on metrics
                IF @metric_filter = N'CPU' OR @metric_filter = N'ALL'
                BEGIN
                    IF @max_cpu > 30000000 -- 30 seconds
                    BEGIN
                        SET @narrative += N'- ⚠️ Extremely high CPU usage detected (over 30 seconds).' + CHAR(13) + CHAR(10);
                    END
                    ELSE IF @max_cpu > 5000000 -- 5 seconds
                    BEGIN
                        SET @narrative += N'- 🟠 High CPU usage detected (over 5 seconds).' + CHAR(13) + CHAR(10);
                    END;
                END;
                
                IF @metric_filter = N'READS' OR @metric_filter = N'ALL'
                BEGIN
                    IF @max_reads > 1000000 -- 1M reads
                    BEGIN
                        SET @narrative += N'- ⚠️ Extremely high logical reads (over 1M pages, ~8GB of data).' + CHAR(13) + CHAR(10);
                    END
                    ELSE IF @max_reads > 100000 -- 100K reads
                    BEGIN
                        SET @narrative += N'- 🟠 High logical reads (over 100K pages, ~800MB of data).' + CHAR(13) + CHAR(10);
                    END;
                END;
                
                IF @metric_filter = N'MEMORY' OR @metric_filter = N'ALL'
                BEGIN
                    IF @max_memory > 102400 -- 100MB
                    BEGIN
                        SET @narrative += N'- ⚠️ Large memory grant required (over 100MB).' + CHAR(13) + CHAR(10);
                    END;
                END;
                
                IF @metric_filter = N'TEMPDB' OR @metric_filter = N'ALL'
                BEGIN
                    IF @max_tempdb > 102400 -- 100MB
                    BEGIN
                        SET @narrative += N'- ⚠️ Heavy tempdb usage detected (over 100MB).' + CHAR(13) + CHAR(10);
                    END;
                END;
                
                -- Pattern recognition
                IF @avg_cpu > 0 AND @avg_reads > 0
                BEGIN
                    DECLARE @cpu_reads_ratio FLOAT = CONVERT(FLOAT, @avg_cpu) / NULLIF(CONVERT(FLOAT, @avg_reads), 0);
                    
                    IF @cpu_reads_ratio > 5000 -- High CPU to reads ratio
                    BEGIN
                        SET @narrative += N'- 🔍 CPU-intensive pattern: High computation with relatively few reads.' + CHAR(13) + CHAR(10);
                    END
                    ELSE IF @cpu_reads_ratio < 100 AND @avg_reads > 10000 -- Low CPU to reads ratio
                    BEGIN
                        SET @narrative += N'- 🔍 I/O-bound pattern: Lots of data scanning with little processing.' + CHAR(13) + CHAR(10);
                    END;
                END;
                
                -- Add recommendations based on patterns
                SET @narrative += CHAR(13) + CHAR(10) + N'🛠️ **Recommendations**:' + CHAR(13) + CHAR(10);
                
                IF @object_nm IS NULL
                BEGIN
                    SET @narrative += N'- Consider parameterizing this ad-hoc query to reduce compilation overhead.' + CHAR(13) + CHAR(10);
                END;
                
                IF @metric_filter IN (N'READS', N'ALL') AND @avg_reads > 10000
                BEGIN
                    SET @narrative += N'- Review indexes to reduce page reads.' + CHAR(13) + CHAR(10);
                END;
                
                IF @metric_filter IN (N'CPU', N'ALL') AND @avg_cpu > 1000000
                BEGIN
                    SET @narrative += N'- Analyze query plan for expensive operations like sorts, table scans or scalar functions.' + CHAR(13) + CHAR(10);
                END;
                
                IF @metric_filter IN (N'MEMORY', N'ALL') AND @avg_memory > 51200 -- 50MB
                BEGIN
                    SET @narrative += N'- Consider rewriting the query to use less memory by chunking data or using spools.' + CHAR(13) + CHAR(10);
                END;
                
                IF @metric_filter IN (N'TEMPDB', N'ALL') AND @avg_tempdb > 51200 -- 50MB
                BEGIN
                    SET @narrative += N'- Analyze tempdb usage to identify operations like sorts, hash joins, or spills.' + CHAR(13) + CHAR(10);
                END;
                
                SET @current_rank = @current_rank + 1;
            END;
            
            SELECT narrative = @narrative;
        END
        ELSE
        BEGIN
            -- Tabular output mode
            SELECT
                query_rank,
                database_name,
                object_name,
                execution_count,
                cpu_time_ms = avg_cpu_time / 1000,
                logical_reads = avg_logical_reads,
                logical_writes = avg_logical_writes,
                duration_ms = avg_duration / 1000,
                memory_grant_mb = avg_memory_grant / 1024,
                tempdb_mb = avg_tempdb_space / 1024,
                last_execution_time,
                query_text
            FROM @query_metrics
            ORDER BY
                query_rank;
        END;
    END TRY
    BEGIN CATCH
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