/*
EXECUTE sp_IndexCleanup
    @database_name = 'StackOverflow2013',
    @debug = 1;

EXECUTE sp_IndexCleanup
    @database_name = 'StackOverflow2013',
    @table_name = 'Users',
    @debug = 1
*/

SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
SET IMPLICIT_TRANSACTIONS OFF;
SET STATISTICS TIME, IO OFF;
GO

IF OBJECT_ID('dbo.sp_IndexCleanup', 'P') IS NULL
BEGIN
    EXECUTE ('CREATE PROCEDURE dbo.sp_IndexCleanup AS RETURN 138;');
END;
GO

ALTER PROCEDURE
    dbo.sp_IndexCleanup
(
    @database_name sysname = NULL,
    @schema_name sysname = NULL,
    @table_name sysname = NULL,
    @min_reads bigint = 0,
    @min_writes bigint = 0,
    @min_size_gb decimal(10,2) = 0,
    @min_rows bigint = 0,
    @help bit = 'false',
    @debug bit = 'false',
    @version varchar(20) = NULL OUTPUT,
    @version_date datetime = NULL OUTPUT
)
WITH RECOMPILE
AS
BEGIN
SET NOCOUNT ON;

BEGIN TRY
    /* Check for SQL Server 2012 (11.0) or later for FORMAT and CONCAT functions*/
    
    IF 
    /* Check SQL Server 2012+ for FORMAT and CONCAT functions */
    (
        CONVERT
        (
            integer, 
            SERVERPROPERTY('EngineEdition')
        ) NOT IN (5, 8) /* Not Azure SQL DB or Managed Instance */
    AND CONVERT
        (
            integer, 
            SUBSTRING
            (
                CONVERT
                (
                    varchar(20), 
                    SERVERPROPERTY('ProductVersion')
                ), 
                1, 
                2
            )
        ) < 11) /* Pre-2012 */    
    BEGIN
        RAISERROR('This procedure requires SQL Server 2012 (11.0) or later due to the use of FORMAT and CONCAT functions.', 11, 1);
        RETURN;
    END;

    SELECT
        @version = '1.4',
        @version_date = '20250401';

    SELECT
        for_insurance_purposes = N'Read the messages pane carefully!';

    PRINT N'
-------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------
This is the BETA VERSION of sp_IndexCleanup

It needs lots of love and testing in real environments with real indexes to fix many issues:
 * Data collection
 * Deduping logic
 * Result correctness
 * Edge cases
 * May not account for specific query patterns that benefit from seemingly redundant indexes
 
ALWAYS TEST THESE RECOMMENDATIONS IN A NON-PRODUCTION ENVIRONMENT FIRST"

-------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------
';


    /*
    Help section, for help.
    Will become more helpful when out of beta.
    */
    IF @help = 1
    BEGIN
        SELECT
            help = N'hello, i am sp_IndexCleanup - BETA'
          UNION ALL
        SELECT
            help = N'this is a script to help clean up unused and duplicate indexes'
          UNION ALL
        SELECT
            help = N'you are currently using a beta version, and the advice should not be followed'
          UNION ALL
        SELECT
            help = N'without careful analysis and consideration. it may be harmful.';

        /*
        Parameters
        */
        SELECT
            parameter_name =
                ap.name,
            data_type =
                t.name,
            description =
                CASE
                    ap.name
                    WHEN N'@database_name' THEN 'the name of the database you wish to analyze'
                    WHEN N'@schema_name' THEN 'the schema name to filter indexes by'
                    WHEN N'@table_name' THEN 'the table name to filter indexes by'
                    WHEN N'@min_reads' THEN 'minimum number of reads for an index to be considered used'
                    WHEN N'@min_writes' THEN 'minimum number of writes for an index to be considered used'
                    WHEN N'@min_size_gb' THEN 'minimum size in GB for an index to be analyzed'
                    WHEN N'@min_rows' THEN 'minimum number of rows for a table to be analyzed'
                    WHEN N'@help' THEN 'displays this help information'
                    WHEN N'@debug' THEN 'prints debug information during execution'
                    WHEN N'@version' THEN 'returns the version number of the procedure'
                    WHEN N'@version_date' THEN 'returns the date this version was released'
                    ELSE NULL
                END,
            valid_inputs =
                CASE
                    ap.name
                    WHEN N'@database_name' THEN 'the name of a database you care about indexes in'
                    WHEN N'@schema_name' THEN 'schema name or NULL for all schemas'
                    WHEN N'@table_name' THEN 'table name or NULL for all tables'
                    WHEN N'@min_reads' THEN 'any positive integer or 0'
                    WHEN N'@min_writes' THEN 'any positive integer or 0'
                    WHEN N'@min_size_gb' THEN 'any positive decimal number or 0'
                    WHEN N'@min_rows' THEN 'any positive integer or 0'
                    WHEN N'@help' THEN '0 or 1'
                    WHEN N'@debug' THEN '0 or 1'
                    WHEN N'@version' THEN 'OUTPUT parameter'
                    WHEN N'@version_date' THEN 'OUTPUT parameter'
                    ELSE NULL
                END,
            defaults =
                CASE
                    ap.name
                    WHEN N'@database_name' THEN 'NULL'
                    WHEN N'@schema_name' THEN 'NULL'
                    WHEN N'@table_name' THEN 'NULL'
                    WHEN N'@min_reads' THEN '0'
                    WHEN N'@min_writes' THEN '0'
                    WHEN N'@min_size_gb' THEN '0'
                    WHEN N'@min_rows' THEN '0'
                    WHEN N'@help' THEN 'false'
                    WHEN N'@debug' THEN 'true'
                    WHEN N'@version' THEN 'NULL'
                    WHEN N'@version_date' THEN 'NULL'
                    ELSE NULL
                END
        FROM sys.all_parameters AS ap
        JOIN sys.all_objects AS o
          ON ap.object_id = o.object_id
        JOIN sys.types AS t
          ON  ap.system_type_id = t.system_type_id
          AND ap.user_type_id = t.user_type_id
        WHERE o.name = N'sp_IndexCleanup'
        OPTION(MAXDOP 1, RECOMPILE);

        SELECT
            mit_license_yo = 'i am MIT licensed, so like, do whatever'

        UNION ALL

        SELECT
            mit_license_yo = 'see printed messages for full license';

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
    END;

    IF @debug = 1
    BEGIN
        RAISERROR('Declaring variables', 0, 0) WITH NOWAIT;
    END;

    DECLARE
        /*general script variables*/
        @sql nvarchar(max) = N'',
        @database_id integer = NULL,
        @object_id integer = NULL,
        @full_object_name nvarchar(768) = NULL,
        @uptime_warning bit = 0, /* Will set after @uptime_days is calculated */
        /*print variables*/
        @online bit = 
            CASE 
                WHEN 
                    CONVERT
                    (
                        integer, 
                        SERVERPROPERTY('EngineEdition')
                    ) IN (3, 5, 8) 
                THEN 'true' /* Enterprise, Azure SQL DB, Managed Instance */
                ELSE 'false'
            END,
        /* Compression variables */
        @can_compress bit = 
            CASE 
                WHEN 
                    CONVERT(integer, SERVERPROPERTY('EngineEdition')) IN (3, 5, 8) 
                    OR 
                    (
                          CONVERT(integer, SERVERPROPERTY('EngineEdition')) = 2 
                      AND CONVERT(integer, SUBSTRING(CONVERT(varchar(20), SERVERPROPERTY('ProductVersion')), 1, 2)) >= 13
                    )
                THEN 1
                ELSE 0
            END,
        @uptime_days nvarchar(10) = 
        (
            SELECT
                DATEDIFF
                (
                    DAY, 
                    osi.sqlserver_start_time, 
                    SYSDATETIME()
                )
            FROM sys.dm_os_sys_info AS osi
        );
        
    /* Set uptime warning flag after @uptime_days is calculated */
    SELECT 
        @uptime_warning = 
            CASE 
                WHEN CONVERT(integer, @uptime_days) < 14 
                THEN 1 
                ELSE 0 
            END;

    /*
    Initial checks for object validity
    */
    IF @debug = 1
    BEGIN
        RAISERROR('Checking paramaters...', 0, 0) WITH NOWAIT;
    END;

    IF  @database_name IS NULL
    AND DB_NAME() NOT IN
        (
            N'master',
            N'model',
            N'msdb',
            N'tempdb',
            N'rdsadmin'
        )
    BEGIN
        SELECT
            @database_name = DB_NAME();
    END;

    IF @database_name IS NOT NULL
    BEGIN
        SELECT
            @database_id = d.database_id
        FROM sys.databases AS d
        WHERE d.name = @database_name
        OPTION(RECOMPILE);
    END;

    IF  @schema_name IS NULL
    AND @table_name IS NOT NULL
    BEGIN
        SELECT
            @schema_name = N'dbo';
    END;

    IF  @schema_name IS NOT NULL
    AND @table_name IS NOT NULL
    BEGIN
        SELECT
            @full_object_name =
                QUOTENAME(@database_name) +
                N'.' +
                QUOTENAME(@schema_name) +
                N'.' +
                QUOTENAME(@table_name);

        SELECT
            @object_id =
                OBJECT_ID(@full_object_name);

        IF @object_id IS NULL
        BEGIN
            RAISERROR('The object %s doesn''t seem to exist', 16, 1, @full_object_name) WITH NOWAIT;
            RETURN;
        END;
    END;

    /* Parameter validation */
    IF @min_reads < 0
    OR @min_reads IS NULL
    BEGIN
        RAISERROR('Parameter @min_reads cannot be NULL or negative. Setting to 0.', 10, 1) WITH NOWAIT;
        SET @min_reads = 0;
    END;
    
    IF @min_writes < 0
    OR @min_writes IS NULL
    BEGIN
        RAISERROR('Parameter @min_writes cannot be NULL or negative. Setting to 0.', 10, 1) WITH NOWAIT;
        SET @min_writes = 0;
    END;
    
    IF @min_size_gb < 0
    OR @min_size_gb IS NULL
    BEGIN
        RAISERROR('Parameter @min_size_gb cannot be NULL or negative. Setting to 0.', 10, 1) WITH NOWAIT;
        SET @min_size_gb = 0;
    END;
    
    IF @min_rows < 0
    OR @min_rows IS NULL
    BEGIN
        RAISERROR('Parameter @min_rows cannot be NULL or negative. Setting to 0.', 10, 1) WITH NOWAIT;
        SET @min_rows = 0;
    END;

    /*
    Temp tables!
    */

    IF @debug = 1
    BEGIN
        RAISERROR('Creating temp tables', 0, 0) WITH NOWAIT;
    END;

    CREATE TABLE 
        #filtered_objects
    (
        database_id integer NOT NULL,
        database_name sysname NOT NULL,
        schema_id integer NOT NULL,
        schema_name sysname NOT NULL,
        object_id integer NOT NULL,
        table_name sysname NOT NULL,
        index_id integer NOT NULL,
        index_name sysname NOT NULL,
        can_compress bit NOT NULL
        PRIMARY KEY CLUSTERED(database_id, schema_id, object_id, index_id)
    );

    CREATE TABLE
        #operational_stats
    (
        database_id integer NOT NULL,
        database_name sysname NOT NULL,
        schema_id integer NOT NULL,
        schema_name sysname NOT NULL,
        object_id integer NOT NULL,
        table_name sysname NOT NULL,
        index_id integer NOT NULL,
        index_name sysname NOT NULL,
        range_scan_count bigint NULL,
        singleton_lookup_count bigint NULL,
        forwarded_fetch_count bigint NULL,
        lob_fetch_in_pages bigint NULL,
        row_overflow_fetch_in_pages bigint NULL,
        leaf_insert_count bigint NULL,
        leaf_update_count bigint NULL,
        leaf_delete_count bigint NULL,
        leaf_ghost_count bigint NULL,
        nonleaf_insert_count bigint NULL,
        nonleaf_update_count bigint NULL,
        nonleaf_delete_count bigint NULL,
        leaf_allocation_count bigint NULL,
        nonleaf_allocation_count bigint NULL,
        row_lock_count bigint NULL,
        row_lock_wait_count bigint NULL,
        row_lock_wait_in_ms bigint NULL,
        page_lock_count bigint NULL,
        page_lock_wait_count bigint NULL,
        page_lock_wait_in_ms bigint NULL,
        index_lock_promotion_attempt_count bigint NULL,
        index_lock_promotion_count bigint NULL,
        page_latch_wait_count bigint NULL,
        page_latch_wait_in_ms bigint NULL,
        tree_page_latch_wait_count bigint NULL,
        tree_page_latch_wait_in_ms bigint NULL,
        page_io_latch_wait_count bigint NULL,
        page_io_latch_wait_in_ms bigint NULL,
        page_compression_attempt_count bigint NULL,
        page_compression_success_count bigint NULL,
        PRIMARY KEY CLUSTERED (database_id, schema_id, object_id, index_id)
    );

    CREATE TABLE
        #partition_stats
    (
        database_id integer NOT NULL,
        database_name sysname NOT NULL,
        schema_id integer NOT NULL,
        schema_name sysname NOT NULL,
        object_id integer NOT NULL,
        table_name sysname NOT NULL,
        index_id integer NOT NULL,
        index_name sysname NULL,
        partition_id bigint NOT NULL,
        partition_number int NOT NULL,
        total_rows bigint NULL,
        total_space_gb decimal(38, 4) NULL, /* Using 4 decimal places for GB to maintain precision */
        reserved_lob_gb decimal(38, 4) NULL, /* Using 4 decimal places for GB to maintain precision */
        reserved_row_overflow_gb decimal(38, 4) NULL, /* Using 4 decimal places for GB to maintain precision */
        data_compression_desc nvarchar(60) NULL,
        built_on sysname NULL,
        partition_function_name sysname NULL,
        partition_columns nvarchar(max)
        PRIMARY KEY CLUSTERED(database_id, schema_id, object_id, index_id, partition_id)
    );

    CREATE TABLE
        #index_details
    (
        database_id integer NOT NULL,
        database_name sysname NOT NULL,
        schema_id integer NOT NULL,
        schema_name sysname NOT NULL,
        object_id integer NOT NULL,
        table_name sysname NOT NULL,
        index_id integer NOT NULL,
        index_name sysname NULL,
        column_name sysname NOT NULL,
        is_primary_key bit NULL,
        is_unique bit NULL,
        is_unique_constraint bit NULL,
        is_indexed_view integer NOT NULL,
        is_foreign_key bit NULL,
        is_foreign_key_reference bit NULL,
        key_ordinal tinyint NOT NULL,
        index_column_id integer NOT NULL,
        is_descending_key bit NOT NULL,
        is_included_column bit NULL,
        filter_definition nvarchar(max) NULL,
        is_max_length integer NOT NULL,
        user_seeks bigint NOT NULL,
        user_scans bigint NOT NULL,
        user_lookups bigint NOT NULL,
        user_updates bigint NOT NULL,
        last_user_seek datetime NULL,
        last_user_scan datetime NULL,
        last_user_lookup datetime NULL,
        last_user_update datetime NULL,
        is_eligible_for_dedupe bit NOT NULL
        PRIMARY KEY CLUSTERED(database_id, object_id, index_id, column_name)
    );

    CREATE TABLE
        #index_analysis
    (
        database_id integer NOT NULL,
        database_name sysname NOT NULL,
        schema_id integer NOT NULL,
        schema_name sysname NOT NULL,
        object_id integer NOT NULL,
        table_name sysname NOT NULL,
        index_id integer NULL,
        index_name sysname NOT NULL,
        is_unique bit NULL,
        key_columns nvarchar(max) NULL,
        included_columns nvarchar(max) NULL,
        filter_definition nvarchar(max) NULL,
        is_redundant bit NULL,
        superseded_by nvarchar(256) NULL,
        missing_columns nvarchar(max) NULL,
        action nvarchar(30) NULL,
        target_index_name sysname NULL,
        consolidation_rule varchar(512) NULL,
        index_priority int NULL,
        original_index_definition nvarchar(max) NULL, /* Original CREATE INDEX statement */
        INDEX c CLUSTERED (database_id, schema_id, object_id, index_id)
    );
    
    CREATE TABLE 
        #compression_eligibility
    (
        database_id integer NOT NULL,
        database_name sysname NOT NULL,
        schema_id integer NOT NULL,
        schema_name sysname NOT NULL,
        object_id integer NOT NULL,
        table_name sysname NOT NULL,
        index_id integer NOT NULL,
        index_name sysname NOT NULL,
        can_compress bit NOT NULL,
        reason nvarchar(200) NULL,
        PRIMARY KEY CLUSTERED(database_id, object_id, index_id)
    );

    CREATE TABLE 
        #key_duplicate_dedupe
    (
        database_id integer NOT NULL,
        object_id integer NOT NULL,
        database_name sysname NOT NULL,
        schema_name sysname NOT NULL,
        table_name sysname NOT NULL,
        base_key_columns nvarchar(max) NULL,
        filter_definition nvarchar(max) NULL,
        winning_index_name sysname NULL,
        index_list nvarchar(max) NULL,
    );

    CREATE TABLE 
        #include_subset_dedupe
    (
        database_id integer NOT NULL,
        object_id integer NOT NULL,
        subset_index_name sysname NULL,
        superset_index_name sysname NULL,
        subset_included_columns nvarchar(max) NULL,
        superset_included_columns nvarchar(max) NULL
    );

    CREATE TABLE 
        #index_cleanup_results
    (
        result_type varchar(50) NOT NULL,  /* 'SUMMARY', 'MERGE', 'DISABLE', 'COMPRESS', etc. */
        sort_order integer NOT NULL,       /* Keeps results in logical order */
        database_name sysname NULL,
        schema_name sysname NULL,
        table_name sysname NULL,
        index_name sysname NULL,
        script_type nvarchar(50) NULL,     /* 'MERGE', 'DISABLE', 'COMPRESS', etc. */
        consolidation_rule nvarchar(256) NULL,
        target_index_name sysname NULL,
        script nvarchar(max) NULL,
        additional_info nvarchar(max) NULL, /* For stats, constraints, etc. */
        superseded_info nvarchar(max) NULL, /* To store superseded_by information */
        original_index_definition nvarchar(max) NULL, /* Original index definition for validation */
        index_size_gb decimal(18,4) NULL,  /* Size of the index in GB */
        index_rows bigint NULL,            /* Number of rows in the index */
        index_reads bigint NULL,           /* Total reads (seeks + scans + lookups) */
        index_writes bigint NULL           /* Total writes (updates) */
    );

    /* Create a new temp table for detailed reporting statistics */
    CREATE TABLE 
        #index_reporting_stats
    (
        summary_level varchar(20) NOT NULL,  /* 'DATABASE', 'TABLE', 'INDEX', 'SUMMARY' */
        database_name sysname NULL,
        schema_name sysname NULL,
        table_name sysname NULL,
        index_name sysname NULL,
        server_uptime_days int NULL,
        uptime_warning bit NULL,
        tables_analyzed int NULL,
        index_count int NULL,
        total_size_gb decimal(38, 4) NULL,
        total_rows bigint NULL,
        unused_indexes int NULL,
        unused_size_gb decimal(38, 4) NULL,
        indexes_to_disable int NULL,
        indexes_to_merge int NULL,
        avg_indexes_per_table decimal(10, 2) NULL,
        space_saved_gb decimal(10, 4) NULL,
        compression_min_savings_gb decimal(10, 4) NULL,
        compression_max_savings_gb decimal(10, 4) NULL,
        total_min_savings_gb decimal(10, 4) NULL,
        total_max_savings_gb decimal(10, 4) NULL,
        /* Index usage metrics */
        total_reads bigint NULL,
        total_writes bigint NULL,
        user_seeks bigint NULL,
        user_scans bigint NULL,
        user_lookups bigint NULL,
        user_updates bigint NULL,
        /* Operational stats */
        range_scan_count bigint NULL,
        singleton_lookup_count bigint NULL,
        /* Lock stats */
        row_lock_count bigint NULL,
        row_lock_wait_count bigint NULL,
        row_lock_wait_in_ms bigint NULL,
        page_lock_count bigint NULL,
        page_lock_wait_count bigint NULL,
        page_lock_wait_in_ms bigint NULL,
        /* Latch stats */
        page_latch_wait_count bigint NULL,
        page_latch_wait_in_ms bigint NULL,
        page_io_latch_wait_count bigint NULL,
        page_io_latch_wait_in_ms bigint NULL,
        /* Misc stats */
        forwarded_fetch_count bigint NULL,
        leaf_insert_count bigint NULL,
        leaf_update_count bigint NULL,
        leaf_delete_count bigint NULL
    );

    /*
    Start insert queries
    */

    IF @debug = 1
    BEGIN
        RAISERROR('Generating #filtered_object insert', 0, 0) WITH NOWAIT;
    END;    
    
    SELECT
        @sql = N'
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;';

    SELECT
        @sql = N'
    SELECT DISTINCT
        @database_id,
        database_name = DB_NAME(@database_id),
        schema_id = t.schema_id,
        schema_name = s.name,
        object_id = t.object_id,
        table_name = t.name,
        index_id = i.index_id,
        index_name = ISNULL(i.name, t.name + N''.Heap''),
        can_compress = 
            CASE 
                WHEN p.index_id > 0 
                AND  p.data_compression = 0 
                THEN 1 
                ELSE 0 
            END
    FROM ' + QUOTENAME(@database_name) + N'.sys.tables AS t
    JOIN ' + QUOTENAME(@database_name) + N'.sys.schemas AS s
      ON t.schema_id = s.schema_id
    JOIN ' + QUOTENAME(@database_name) + N'.sys.indexes AS i
      ON t.object_id = i.object_id
    JOIN ' + QUOTENAME(@database_name) + N'.sys.partitions AS p
      ON  i.object_id = p.object_id
      AND i.index_id = p.index_id
    LEFT JOIN ' + QUOTENAME(@database_name) + N'.sys.dm_db_index_usage_stats AS us
      ON  t.object_id = us.object_id
      AND us.database_id = @database_id
    WHERE t.is_ms_shipped = 0
    AND   t.type <> N''TF''
    AND   NOT EXISTS 
    (
        SELECT 
            1/0
        FROM ' + QUOTENAME(@database_name) + N'.sys.views AS v
        WHERE v.object_id = i.object_id 
    )';
      
    IF /* Check SQL Server 2016+ for temporal tables support */
    (
        CONVERT
        (
            integer, 
            SERVERPROPERTY('EngineEdition')
        ) IN (5, 8) /* Azure SQL DB or Managed Instance */
    OR  CONVERT
        (
            integer, 
            SUBSTRING
            (
                CONVERT
                (
                    varchar(20), 
                    SERVERPROPERTY('ProductVersion')
                ), 
                1, 
                2
            )
        ) >= 13
    ) /* SQL 2016+ */
    BEGIN
        SET @sql += N'
    AND   NOT EXISTS 
    (
        SELECT 
            1/0 
        FROM ' + QUOTENAME(@database_name) + N'.sys.tables AS t
        WHERE t.object_id = i.object_id 
        AND   t.temporal_type > 0
    )';
    END;


    IF @object_id IS NOT NULL
    BEGIN
        SELECT @sql += N'
    AND   t.object_id = @object_id';
    END;

    SET @sql += N'
    AND EXISTS 
    (
        SELECT 
            1/0 
        FROM ' + QUOTENAME(@database_name) + N'.sys.dm_db_partition_stats AS ps
        JOIN ' + QUOTENAME(@database_name) + N'.sys.allocation_units AS au
          ON ps.partition_id = au.container_id
        WHERE ps.object_id = t.object_id
        GROUP 
            BY ps.object_id
        HAVING 
            SUM(au.total_pages) * 8.0 / 1048576.0 >= @min_size_gb
    )
    AND EXISTS 
    (
        SELECT 
            1/0
        FROM ' + QUOTENAME(@database_name) + N'.sys.dm_db_partition_stats AS ps
        WHERE ps.object_id = t.object_id
        AND   ps.index_id IN (0, 1)
        GROUP 
            BY ps.object_id
        HAVING 
            SUM(ps.row_count) >= @min_rows
    )    
    AND EXISTS 
    (
        SELECT 
            1/0
        FROM ' + QUOTENAME(@database_name) + N'.sys.dm_db_index_usage_stats AS ius
        WHERE ius.object_id = t.object_id
        AND   ius.database_id = @database_id
        GROUP BY 
            ius.object_id
        HAVING 
            SUM(ius.user_seeks + ius.user_scans + ius.user_lookups) >= @min_reads
        OR 
            SUM(ius.user_updates) >= @min_writes
    )
    OPTION(RECOMPILE);';

    IF @debug = 1
    BEGIN
        PRINT @sql;
    END;
      
    INSERT
        #filtered_objects
    WITH
        (TABLOCK)
    (
        database_id,
        database_name,          
        schema_id,
        schema_name,
        object_id, 
        table_name,
        index_id,
        index_name,
        can_compress
    )
    EXECUTE sys.sp_executesql
        @sql,
      N'@database_id int,
        @min_reads bigint,
        @min_writes bigint,
        @min_size_gb decimal(10,2),
        @min_rows bigint,
        @object_id integer',
        @database_id,
        @min_reads,
        @min_writes,
        @min_size_gb,
        @min_rows,
        @object_id;

    IF ROWCOUNT_BIG() = 0 
    BEGIN 
        IF @debug = 1 
        BEGIN
            RAISERROR('No rows inserted into #filtered_objects', 0, 0) WITH NOWAIT; 
        END; 
    END;

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#filtered_objects',
            fo.*
        FROM #filtered_objects AS fo
        OPTION(RECOMPILE);

        RAISERROR('Generating #compression_eligibility insert', 0, 0) WITH NOWAIT;
    END;
    
    /* Populate compression eligibility table */    
    INSERT INTO 
        #compression_eligibility
    WITH
        (TABLOCK)
    (
        database_id,
        database_name,
        schema_id,
        schema_name,
        object_id,
        table_name,
        index_id,
        index_name,
        can_compress,
        reason
    )
    SELECT 
        fo.database_id,
        fo.database_name,
        fo.schema_id,
        fo.schema_name,
        fo.object_id,
        fo.table_name,
        fo.index_id,
        fo.index_name,
        1, /* Default to compressible */
        NULL
    FROM #filtered_objects AS fo
    WHERE fo.can_compress = 1
    OPTION(RECOMPILE);
    
    /* If SQL Server edition doesn't support compression, mark all as ineligible */
    IF @can_compress = 0
    BEGIN
        UPDATE 
            #compression_eligibility
        SET 
            can_compress = 0,
            reason = N'SQL Server edition or version does not support compression'
        WHERE can_compress = 1
        OPTION(RECOMPILE);
    END;
    
    /* Check for sparse columns or incompatible data types */
    IF @can_compress = 1
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Updating #compression_eligibility', 0, 0) WITH NOWAIT;
        END;

        SELECT
            @sql = N'
        SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
        
        UPDATE 
            ce
        SET 
            ce.can_compress = 0,
            ce.reason = ''Table contains sparse columns or incompatible data types''
        FROM #compression_eligibility AS ce
        WHERE EXISTS 
        (
            SELECT 
                1/0
            FROM ' + QUOTENAME(@database_name) + N'.sys.columns AS c
            JOIN ' + QUOTENAME(@database_name) + N'.sys.types AS t 
              ON c.user_type_id = t.user_type_id
            WHERE c.object_id = ce.object_id
            AND 
            (
                 c.is_sparse = 1 
              OR t.name IN (N''text'', N''ntext'', N''image'')
            )
        )
        OPTION(RECOMPILE);
        ';

        IF @debug = 1
        BEGIN
            PRINT @sql;
        END;
        
        EXECUTE sys.sp_executesql 
            @sql;
    END;
    
    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#compression_eligibility',
            ce.*
        FROM #compression_eligibility AS ce
        OPTION(RECOMPILE);

        RAISERROR('Generating #operational_stats insert', 0, 0) WITH NOWAIT;
    END; 

    SELECT
        @sql = N'
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;';

    SELECT
        @sql += N'
    SELECT
        os.database_id,
        database_name = DB_NAME(os.database_id),
        schema_id = s.schema_id,
        schema_name = s.name,
        os.object_id,
        table_name = t.name,
        os.index_id,
        index_name = ISNULL(i.name, t.name + N''.Heap''),
        range_scan_count = SUM(os.range_scan_count),
        singleton_lookup_count = SUM(os.singleton_lookup_count),
        forwarded_fetch_count = SUM(os.forwarded_fetch_count),
        lob_fetch_in_pages = SUM(os.lob_fetch_in_pages),
        row_overflow_fetch_in_pages = SUM(os.row_overflow_fetch_in_pages),
        leaf_insert_count = SUM(os.leaf_insert_count),
        leaf_update_count = SUM(os.leaf_update_count),
        leaf_delete_count = SUM(os.leaf_delete_count),
        leaf_ghost_count = SUM(os.leaf_ghost_count),
        nonleaf_insert_count = SUM(os.nonleaf_insert_count),
        nonleaf_update_count = SUM(os.nonleaf_update_count),
        nonleaf_delete_count = SUM(os.nonleaf_delete_count),
        leaf_allocation_count = SUM(os.leaf_allocation_count),
        nonleaf_allocation_count = SUM(os.nonleaf_allocation_count),
        row_lock_count = SUM(os.row_lock_count),
        row_lock_wait_count = SUM(os.row_lock_wait_count),
        row_lock_wait_in_ms = SUM(os.row_lock_wait_in_ms),
        page_lock_count = SUM(os.page_lock_count),
        page_lock_wait_count = SUM(os.page_lock_wait_count),
        page_lock_wait_in_ms = SUM(os.page_lock_wait_in_ms),
        index_lock_promotion_attempt_count = SUM(os.index_lock_promotion_attempt_count),
        index_lock_promotion_count = SUM(os.index_lock_promotion_count),
        page_latch_wait_count = SUM(os.page_latch_wait_count),
        page_latch_wait_in_ms = SUM(os.page_latch_wait_in_ms),
        tree_page_latch_wait_count = SUM(os.tree_page_latch_wait_count),
        tree_page_latch_wait_in_ms = SUM(os.tree_page_latch_wait_in_ms),
        page_io_latch_wait_count = SUM(os.page_io_latch_wait_count),
        page_io_latch_wait_in_ms = SUM(os.page_io_latch_wait_in_ms),
        page_compression_attempt_count = SUM(os.page_compression_attempt_count),
        page_compression_success_count = SUM(os.page_compression_success_count)
    FROM ' + QUOTENAME(@database_name) + N'.sys.dm_db_index_operational_stats
    (
        @database_id,
        @object_id,
        NULL,
        NULL
    ) AS os
    JOIN ' + QUOTENAME(@database_name) + N'.sys.tables AS t
      ON os.object_id = t.object_id
    JOIN ' + QUOTENAME(@database_name) + N'.sys.schemas AS s
      ON t.schema_id = s.schema_id
    JOIN ' + QUOTENAME(@database_name) + N'.sys.indexes AS i
      ON  os.object_id = i.object_id
      AND os.index_id = i.index_id
    WHERE EXISTS
    (
        SELECT
            1/0
        FROM #filtered_objects AS fo
        WHERE fo.database_id = os.database_id
        AND   fo.object_id = os.object_id
    )
    GROUP BY
        os.database_id,
        DB_NAME(os.database_id),
        s.schema_id,
        s.name,
        os.object_id,
        t.name,
        os.index_id,
        i.name
    OPTION(RECOMPILE);';

    IF @debug = 1
    BEGIN
        PRINT @sql;
    END;

    INSERT
        #operational_stats
    WITH
        (TABLOCK)
    (
        database_id,
        database_name,
        schema_id,
        schema_name,
        object_id,
        table_name,
        index_id,
        index_name,
        range_scan_count,
        singleton_lookup_count,
        forwarded_fetch_count,
        lob_fetch_in_pages,
        row_overflow_fetch_in_pages,
        leaf_insert_count,
        leaf_update_count,
        leaf_delete_count,
        leaf_ghost_count,
        nonleaf_insert_count,
        nonleaf_update_count,
        nonleaf_delete_count,
        leaf_allocation_count,
        nonleaf_allocation_count,
        row_lock_count,
        row_lock_wait_count,
        row_lock_wait_in_ms,
        page_lock_count,
        page_lock_wait_count,
        page_lock_wait_in_ms,
        index_lock_promotion_attempt_count,
        index_lock_promotion_count,
        page_latch_wait_count,
        page_latch_wait_in_ms,
        tree_page_latch_wait_count,
        tree_page_latch_wait_in_ms,
        page_io_latch_wait_count,
        page_io_latch_wait_in_ms,
        page_compression_attempt_count,
        page_compression_success_count
    )
    EXECUTE sys.sp_executesql
        @sql,
      N'@database_id integer,
        @object_id integer',
        @database_id,
        @object_id;

    IF ROWCOUNT_BIG() = 0 
    BEGIN 
        IF @debug = 1 
        BEGIN
            RAISERROR('No rows inserted into #operational_stats', 0, 0) WITH NOWAIT; 
        END; 
    END;

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#operational_stats',
            os.*
        FROM #operational_stats AS os
        OPTION(RECOMPILE);

        RAISERROR('Generating #index_details insert', 0, 0) WITH NOWAIT;
    END;

    SELECT
        @sql = N'
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;';

    SELECT
        @sql += N'
    SELECT
        database_id = @database_id,
        database_name = DB_NAME(@database_id),
        t.object_id,
        i.index_id,
        s.schema_id,
        schema_name = s.name,
        table_name = t.name,
        index_name = ISNULL(i.name, t.name + N''.Heap''),
        column_name = c.name,
        i.is_primary_key,
        i.is_unique,
        i.is_unique_constraint,
        is_indexed_view =
            CASE
                WHEN EXISTS
                (
                    SELECT
                        1/0
                    FROM ' + QUOTENAME(@database_name) + N'.sys.objects AS so
                    WHERE i.object_id = so.object_id
                    AND   so.is_ms_shipped = 0
                    AND   so.type = ''V''
                )
                THEN 1
                ELSE 0
            END,
        is_foreign_key =
            CASE
                WHEN EXISTS
                     (
                         SELECT
                             1/0
                         FROM ' + QUOTENAME(@database_name) + N'.sys.foreign_key_columns AS f
                         WHERE f.parent_column_id = c.column_id
                         AND   f.parent_object_id = c.object_id
                     )
                THEN 1
                ELSE 0
            END,
        is_foreign_key_reference =
            CASE
                WHEN EXISTS
                     (
                         SELECT
                             1/0
                         FROM ' + QUOTENAME(@database_name) + N'.sys.foreign_key_columns AS f
                         WHERE f.referenced_column_id = c.column_id
                         AND   f.referenced_object_id = c.object_id
                     )
                THEN 1
                ELSE 0
            END,
        ic.key_ordinal,
        ic.index_column_id,
        ic.is_descending_key,
        ic.is_included_column,
        i.filter_definition,
        is_max_length =
            CASE
                WHEN EXISTS
                     (
                         SELECT
                             1/0
                         FROM ' + QUOTENAME(@database_name) + N'.sys.types AS t
                         WHERE  c.system_type_id = t.system_type_id
                         AND    c.user_type_id = t.user_type_id
                         AND    t.name IN (N''varchar'', N''nvarchar'')
                         AND    t.max_length = -1
                     )
                THEN 1
                ELSE 0
            END,
        user_seeks = ISNULL(us.user_seeks, 0),
        user_scans = ISNULL(us.user_scans, 0),
        user_lookups = ISNULL(us.user_lookups, 0),
        user_updates = ISNULL(us.user_updates, 0),
        us.last_user_seek,
        us.last_user_scan,
        us.last_user_lookup,
        us.last_user_update,
        is_eligible_for_dedupe = 
            CASE
                WHEN i.type = 2
                THEN 1
                WHEN i.type = 1
                THEN 0
            END
    FROM ' + QUOTENAME(@database_name) + N'.sys.tables AS t
    JOIN ' + QUOTENAME(@database_name) + N'.sys.schemas AS s
      ON t.schema_id = s.schema_id
    JOIN ' + QUOTENAME(@database_name) + N'.sys.indexes AS i
      ON t.object_id = i.object_id
    JOIN ' + QUOTENAME(@database_name) + N'.sys.index_columns AS ic
      ON  i.object_id = ic.object_id
      AND i.index_id = ic.index_id
    JOIN ' + QUOTENAME(@database_name) + 
    CONVERT
    (
        nvarchar(MAX),
        N'.sys.columns AS c
      ON  ic.object_id = c.object_id
      AND ic.column_id = c.column_id
    LEFT JOIN sys.dm_db_index_usage_stats AS us
      ON  i.object_id = us.object_id
      AND i.index_id = us.index_id
      AND us.database_id = @database_id
    WHERE t.is_ms_shipped = 0
    AND   i.type IN (1, 2)
    AND   i.is_disabled = 0
    AND   i.is_hypothetical = 0
    AND   EXISTS
    (
        SELECT
            1/0
        FROM #filtered_objects AS fo
        WHERE fo.database_id = @database_id
        AND   fo.object_id = t.object_id
    )        
    AND   EXISTS 
    (
        SELECT 
            1/0
        FROM '
    ) + QUOTENAME(@database_name) + 
        CONVERT
        (
            nvarchar(MAX), 
            N'.sys.dm_db_partition_stats ps
        WHERE ps.object_id = t.object_id
        AND   ps.index_id = 1
        AND   ps.row_count >= @min_rows
    )'
        );

    IF @object_id IS NOT NULL
    BEGIN
        SELECT @sql += N'
    AND   t.object_id = @object_id';
    END;

    SELECT
        @sql += CONVERT
        (
            nvarchar(max),
            N'
    AND   NOT EXISTS
    (
          SELECT
              1/0
          FROM ' + QUOTENAME(@database_name) + N'.sys.objects AS so
          WHERE i.object_id = so.object_id
          AND   so.is_ms_shipped = 0
          AND   so.type = N''TF''
    )
    OPTION(RECOMPILE);'
        );

    IF @debug = 1
    BEGIN
        PRINT SUBSTRING(@sql, 1, 4000);
        PRINT SUBSTRING(@sql, 4000, 8000);
    END;

    INSERT
        #index_details
    WITH
        (TABLOCK)
    (
        database_id,
        database_name,
        object_id,
        index_id,
        schema_id,
        schema_name,
        table_name,
        index_name,
        column_name,
        is_primary_key,
        is_unique,
        is_unique_constraint,
        is_indexed_view,
        is_foreign_key,
        is_foreign_key_reference,
        key_ordinal,
        index_column_id,
        is_descending_key,
        is_included_column,
        filter_definition,
        is_max_length,
        user_seeks,
        user_scans,
        user_lookups,
        user_updates,
        last_user_seek,
        last_user_scan,
        last_user_lookup,
        last_user_update,
        is_eligible_for_dedupe
    )
    EXECUTE sys.sp_executesql
        @sql,
      N'@database_id integer,
        @object_id integer,
        @min_rows integer',
        @database_id,
        @object_id,
        @min_rows;

    IF ROWCOUNT_BIG() = 0 
    BEGIN 
        IF @debug = 1 
        BEGIN
            RAISERROR('No rows inserted into #index_details', 0, 0) WITH NOWAIT; 
        END; 
    END;

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#index_details',
            *
        FROM #index_details AS id;

        RAISERROR('Generating #partition_stats insert', 0, 0) WITH NOWAIT;
    END;

    SELECT
        @sql = N'
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;';

    SELECT
        @sql += N'
    SELECT
        database_id = @database_id,
        database_name = DB_NAME(@database_id),
        x.object_id,
        x.index_id,
        x.schema_id,
        x.schema_name,
        x.table_name,
        x.index_name,
        x.partition_id,
        x.partition_number,
        x.total_rows,
        x.total_space_gb,
        x.reserved_lob_gb,
        x.reserved_row_overflow_gb,
        x.data_compression_desc,
        built_on =
            ISNULL
            (
                psfg.partition_scheme_name,
                psfg.filegroup_name
            ),
        psfg.partition_function_name,
        pc.partition_columns
    FROM
    (
        SELECT DISTINCT
            ps.object_id,
            ps.index_id,
            s.schema_id,
            schema_name = s.name,
            table_name = t.name,
            index_name = ISNULL(i.name, t.name + N''.Heap''),
            ps.partition_id,
            p.partition_number,
            total_rows = ps.row_count,
            total_space_gb = SUM(a.total_pages) * 8 / 1024.0 / 1024.0, /* Convert directly to GB */
            reserved_lob_gb = SUM(ps.lob_reserved_page_count) * 8. / 1024. / 1024.0, /* Convert directly to GB */
            reserved_row_overflow_gb = SUM(ps.row_overflow_reserved_page_count) * 8. / 1024. / 1024.0, /* Convert directly to GB */
            p.data_compression_desc,
            i.data_space_id
        FROM ' + QUOTENAME(@database_name) + N'.sys.tables AS t
        JOIN ' + QUOTENAME(@database_name) + N'.sys.indexes AS i
          ON t.object_id = i.object_id
        JOIN ' + QUOTENAME(@database_name) + N'.sys.schemas AS s
          ON t.schema_id = s.schema_id
        JOIN ' + QUOTENAME(@database_name) + N'.sys.partitions AS p
          ON  i.object_id = p.object_id
          AND i.index_id = p.index_id
        JOIN ' + QUOTENAME(@database_name) + N'.sys.allocation_units AS a
          ON p.partition_id = a.container_id
        LEFT HASH JOIN ' + QUOTENAME(@database_name) + N'.sys.dm_db_partition_stats AS ps
          ON p.partition_id = ps.partition_id
        WHERE t.type <> N''TF''
        AND   i.type IN (1, 2)
        AND   EXISTS
        (
            SELECT
                1/0
            FROM #filtered_objects AS fo
            WHERE fo.database_id = @database_id
            AND   fo.object_id = t.object_id
        )';

    IF @object_id IS NOT NULL
    BEGIN
        SELECT @sql += N'
        AND   t.object_id = @object_id';
    END;

    SELECT
        @sql += N'
        GROUP BY
            ps.object_id,
            ps.index_id,
            s.schema_id,
            s.name,
            t.name,
            i.name,
            ps.partition_id,
            p.partition_number,
            ps.row_count,
            p.data_compression_desc,
            i.data_space_id
    ) AS x
    OUTER APPLY
    (
        SELECT
            filegroup_name =
                fg.name,
            partition_scheme_name =
                ps.name,
            partition_function_name =
                pf.name
        FROM ' + QUOTENAME(@database_name) + N'.sys.filegroups AS fg
        FULL JOIN ' + QUOTENAME(@database_name) + N'.sys.partition_schemes AS ps
          ON ps.data_space_id = fg.data_space_id
        LEFT JOIN ' + QUOTENAME(@database_name) + N'.sys.partition_functions AS pf
          ON pf.function_id = ps.function_id
        WHERE x.data_space_id = fg.data_space_id
        OR    x.data_space_id = ps.data_space_id
    ) AS psfg
    OUTER APPLY
    (
        SELECT
            partition_columns =
                STUFF
                (
                  (
                    SELECT
                        N'', '' +
                        c.name
                    FROM ' + QUOTENAME(@database_name) + N'.sys.index_columns AS ic
                    JOIN ' + QUOTENAME(@database_name) + N'.sys.columns AS c
                      ON c.object_id = ic.object_id
                     AND c.column_id = ic.column_id
                    WHERE ic.object_id = x.object_id
                    AND   ic.index_id = x.index_id
                    AND   ic.partition_ordinal > 0
                    ORDER BY
                        ic.partition_ordinal
                    FOR 
                        XML
                        PATH(''''),
                        TYPE
                  ).value(''.'', ''nvarchar(max)''),
                  1,
                  2,
                  ''''
                )
    ) AS pc
    OPTION(RECOMPILE);';

    IF @debug = 1
    BEGIN
        PRINT SUBSTRING(@sql, 1, 4000);
        PRINT SUBSTRING(@sql, 4000, 8000);
    END;

    INSERT
        #partition_stats WITH(TABLOCK)
    (
        database_id,
        database_name,
        object_id,
        index_id,
        schema_id,
        schema_name,
        table_name,
        index_name,
        partition_id,
        partition_number,
        total_rows,
        total_space_gb,
        reserved_lob_gb,
        reserved_row_overflow_gb,
        data_compression_desc,
        built_on,
        partition_function_name,
        partition_columns
    )
    EXECUTE sys.sp_executesql
        @sql,
      N'@database_id integer,
        @object_id integer',
        @database_id,
        @object_id;

    IF ROWCOUNT_BIG() = 0 
    BEGIN 
        IF @debug = 1 
        BEGIN
            RAISERROR('No rows inserted into #partition_stats', 0, 0) WITH NOWAIT; 
        END; 
    END;

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#partition_stats',
            *
        FROM #partition_stats AS ps
        OPTION(RECOMPILE);

        RAISERROR('Performing #index_analysis insert', 0, 0) WITH NOWAIT;
    END; 

    INSERT INTO
        #index_analysis
    WITH
        (TABLOCK)
    (
        database_id,
        database_name,
        schema_id,
        schema_name,
        table_name,
        object_id,
        index_id,
        index_name,
        is_unique,
        key_columns,
        included_columns,
        filter_definition,
        original_index_definition
    )
    SELECT
        @database_id,
        database_name = DB_NAME(@database_id),
        id1.schema_id,
        id1.schema_name,
        id1.table_name,
        id1.object_id,
        id1.index_id,
        id1.index_name,
        id1.is_unique,
        key_columns =
            STUFF
            (
              (
                SELECT
                    N', ' +
                    id2.column_name +
                    CASE
                        WHEN id2.is_descending_key = 1
                        THEN N' DESC'
                        ELSE N''
                    END
                FROM #index_details id2
                WHERE id2.object_id = id1.object_id
                AND   id2.index_id = id1.index_id
                AND   id2.is_included_column = 0
                GROUP BY
                    id2.column_name,
                    id2.is_descending_key,
                    id2.key_ordinal
                ORDER BY
                    id2.key_ordinal
                FOR 
                    XML
                    PATH(''),
                    TYPE
              ).value('text()[1]','nvarchar(max)'),
              1,
              2,
              ''
            ),
        included_columns =
            STUFF
            (
              (
                SELECT
                    N', ' +
                    id2.column_name
                FROM #index_details id2
                WHERE id2.object_id = id1.object_id
                AND   id2.index_id = id1.index_id
                AND   id2.is_included_column = 1
                GROUP BY
                    id2.column_name
                ORDER BY
                    id2.column_name
                FOR 
                    XML
                    PATH(''),
                    TYPE
              ).value('text()[1]','nvarchar(max)'),
              1,
              2,
              ''
            ),
        id1.filter_definition,
        /* Store the original index definition for validation */
        original_index_definition = 
            CASE
                /* For unique constraints, use ALTER TABLE ADD CONSTRAINT syntax */
                WHEN id1.is_unique_constraint = 1
                THEN
                    N'ALTER TABLE ' + 
                    QUOTENAME(DB_NAME(@database_id)) + 
                    N'.' +
                    QUOTENAME(id1.schema_name) + 
                    N'.' +
                    QUOTENAME(id1.table_name) + 
                    N' ADD CONSTRAINT ' +
                    QUOTENAME(id1.index_name) +
                    N' UNIQUE ('
                /* For regular indexes, use CREATE INDEX syntax */    
                ELSE
                    N'CREATE ' +
                    CASE WHEN id1.is_unique = 1 THEN N'UNIQUE ' ELSE N'' END +
                    N'INDEX ' + 
                    QUOTENAME(id1.index_name) + 
                    N' ON ' + 
                    QUOTENAME(DB_NAME(@database_id)) + 
                    N'.' +
                    QUOTENAME(id1.schema_name) + 
                    N'.' +
                    QUOTENAME(id1.table_name) + 
                    N' ('
            END +
            STUFF
            (
                (
                    SELECT
                        N', ' +
                        id2.column_name +
                        CASE
                            WHEN id2.is_descending_key = 1
                            THEN N' DESC'
                            ELSE N''
                        END
                    FROM #index_details id2
                    WHERE id2.object_id = id1.object_id
                    AND   id2.index_id = id1.index_id
                    AND   id2.is_included_column = 0
                    GROUP BY
                        id2.column_name,
                        id2.is_descending_key,
                        id2.key_ordinal
                    ORDER BY
                        id2.key_ordinal
                    FOR 
                        XML
                        PATH(''),
                        TYPE
                ).value('text()[1]','nvarchar(max)'),
                1,
                2,
                ''
            ) +
            N')' +
            CASE 
                WHEN EXISTS 
                (
                    SELECT 
                        1/0 
                    FROM #index_details id3
                    WHERE id3.object_id = id1.object_id
                    AND   id3.index_id = id1.index_id
                    AND   id3.is_included_column = 1
                )
                THEN N' INCLUDE (' + 
                    STUFF
                    (
                        (
                            SELECT
                                N', ' +
                                id4.column_name
                            FROM #index_details id4
                            WHERE id4.object_id = id1.object_id
                            AND   id4.index_id = id1.index_id
                            AND   id4.is_included_column = 1
                            GROUP BY
                                id4.column_name
                            ORDER BY
                                id4.column_name
                            FOR 
                                XML
                                PATH(''),
                                TYPE
                        ).value('text()[1]','nvarchar(max)'),
                        1,
                        2,
                        ''
                    ) + 
                    N')'
                ELSE N''
            END +
            CASE 
                WHEN id1.filter_definition IS NOT NULL
                THEN N' WHERE ' + id1.filter_definition
                ELSE N''
            END
    FROM #index_details id1
    WHERE id1.is_eligible_for_dedupe = 1
    GROUP BY
        id1.schema_name,
        id1.schema_id,
        id1.table_name,
        id1.index_name,
        id1.index_id,
        id1.is_unique,
        id1.object_id,
        id1.index_id,
        id1.filter_definition,
        id1.is_unique_constraint
    OPTION(RECOMPILE);

    IF ROWCOUNT_BIG() = 0 
    BEGIN 
        IF @debug = 1 
        BEGIN
            RAISERROR('No rows inserted into #index_analysis', 0, 0) WITH NOWAIT; 
        END; 
    END;

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#index_analysis',
            ia.*
        FROM #index_analysis AS ia
        OPTION(RECOMPILE);

        RAISERROR('Starting updates', 0, 0) WITH NOWAIT;
    END;

    /* Calculate index priority scores based on actual columns that exist */
    UPDATE 
        #index_analysis
    SET 
        #index_analysis.index_priority = 
            CASE 
                WHEN index_id = 1 
                THEN 1000  /* Clustered indexes get highest priority */
                ELSE 0
            END 
            + 
            CASE 
                /* Unique indexes get high priority, but reduce priority for unique constraints */
                WHEN is_unique = 1 AND NOT EXISTS 
                (
                    SELECT 
                        1/0 
                    FROM #index_details AS id_uc 
                    WHERE id_uc.index_id = #index_analysis.index_id
                    AND   id_uc.object_id = #index_analysis.object_id
                    AND   id_uc.is_unique_constraint = 1
                ) THEN 500 
                /* Unique constraints get lower priority */
                WHEN is_unique = 1 AND EXISTS 
                (
                    SELECT 
                        1/0 
                    FROM #index_details AS id_uc 
                    WHERE id_uc.index_id = #index_analysis.index_id
                    AND   id_uc.object_id = #index_analysis.object_id
                    AND   id_uc.is_unique_constraint = 1
                ) THEN 50 
                ELSE 0 
            END
            + 
            CASE 
                WHEN EXISTS 
                (
                    SELECT 
                        1/0 
                    FROM #index_details AS id 
                    WHERE id.index_id = #index_analysis.index_id
                    AND   id.object_id = #index_analysis.object_id
                    AND   id.user_seeks > 0
                ) THEN 200 
                ELSE 0 
            END  /* Indexes with seeks get priority */
            + 
            CASE 
                WHEN EXISTS 
                (
                    SELECT 
                        1/0 
                    FROM #index_details AS  id 
                    WHERE id.index_id = #index_analysis.index_id
                    AND   id.object_id = #index_analysis.object_id
                    AND   id.user_scans > 0
                ) THEN 100 ELSE 0 
            END
    OPTION(RECOMPILE);  /* Indexes with scans get some priority */

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#index_analysis after priority score',
            ia.*
        FROM #index_analysis AS ia
        OPTION(RECOMPILE);
    END;

    /* Rule 1: Identify unused indexes */
    UPDATE 
        #index_analysis
    SET 
        #index_analysis.consolidation_rule = 
            CASE 
                WHEN @uptime_warning = 1 
                THEN 'Unused Index (WARNING: Server uptime < 14 days - usage data may be incomplete)'
                ELSE 'Unused Index' 
            END,
        #index_analysis.action = N'DISABLE'
    WHERE EXISTS 
    (
        SELECT 
            1/0 
        FROM #index_details id
        WHERE id.database_id = #index_analysis.database_id
        AND   id.object_id = #index_analysis.object_id
        AND   id.index_id = #index_analysis.index_id
        AND   id.user_seeks = 0
        AND   id.user_scans = 0
        AND   id.user_lookups = 0
        AND   id.is_primary_key = 0  /* Don't disable primary keys */
        AND   id.is_unique_constraint = 0  /* Don't disable unique constraints */
        AND   id.is_eligible_for_dedupe = 1 /* Only eligible indexes */
    )
    AND #index_analysis.index_id <> 1
    OPTION(RECOMPILE);  /* Don't disable clustered indexes */

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#index_analysis after rule 1',
            ia.*
        FROM #index_analysis AS ia
        OPTION(RECOMPILE);
    END;

    /* Rule 2: Exact duplicates - matching key columns and includes */
    UPDATE 
        ia1
    SET 
        ia1.consolidation_rule = 'Exact Duplicate',
        ia1.target_index_name = 
            CASE 
                WHEN ia1.index_priority > ia2.index_priority 
                THEN NULL  /* This index is the keeper */
                WHEN ia1.index_priority = ia2.index_priority AND ia1.index_name < ia2.index_name
                THEN NULL  /* When tied, use alphabetical ordering for consistency */
                ELSE ia2.index_name  /* Other index is the keeper */
            END,
        ia1.action = 
            CASE 
                WHEN ia1.index_priority > ia2.index_priority 
                THEN 'KEEP'  /* This index is the keeper */
                WHEN ia1.index_priority = ia2.index_priority AND ia1.index_name < ia2.index_name
                THEN 'KEEP'  /* When tied, use alphabetical ordering for consistency */
                ELSE 'DISABLE'  /* Other index gets disabled */
            END
    FROM #index_analysis AS ia1
    JOIN #index_analysis AS ia2 
      ON  ia1.database_id = ia2.database_id
      AND ia1.object_id = ia2.object_id
      AND ia1.index_name <> ia2.index_name
      AND ia1.key_columns = ia2.key_columns  /* Exact key match */
      AND ISNULL(ia1.included_columns, '') = ISNULL(ia2.included_columns, '')  /* Exact includes match */
      AND ISNULL(ia1.filter_definition, '') = ISNULL(ia2.filter_definition, '')  /* Matching filters */
    WHERE ia1.consolidation_rule IS NULL  /* Not already processed */
    AND   ia2.consolidation_rule IS NULL  /* Not already processed */
    /* Exclude unique constraints - we'll handle those separately in Rule 7 */
    AND NOT EXISTS 
    (
        SELECT 
            1/0 
        FROM #index_details AS id1_uc
        WHERE id1_uc.database_id = ia1.database_id
        AND   id1_uc.object_id = ia1.object_id
        AND   id1_uc.index_id = ia1.index_id
        AND   id1_uc.is_unique_constraint = 1
    )
    AND NOT EXISTS 
    (
        SELECT 
            1/0 
        FROM #index_details AS id2_uc
        WHERE id2_uc.database_id = ia2.database_id
        AND   id2_uc.object_id = ia2.object_id
        AND   id2_uc.index_id = ia2.index_id
        AND   id2_uc.is_unique_constraint = 1
    )
    AND   EXISTS 
    (
        SELECT 
            1/0 
        FROM #index_details AS id1
        WHERE id1.database_id = ia1.database_id
        AND   id1.object_id = ia1.object_id
        AND   id1.index_id = ia1.index_id
        AND   id1.is_eligible_for_dedupe = 1
    )
    AND EXISTS 
    (
        SELECT 
            1/0 
        FROM #index_details AS id2
        WHERE id2.database_id = ia2.database_id
        AND   id2.object_id = ia2.object_id
        AND   id2.index_id = ia2.index_id
        AND   id2.is_eligible_for_dedupe = 1
    )
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#index_analysis after rule 2',
            ia.*
        FROM #index_analysis AS ia
        OPTION(RECOMPILE);
        
        /* Special debug for exact duplicates */
        RAISERROR('Special debug for exact duplicates after rule 2:', 0, 0) WITH NOWAIT;
        SELECT 
            ia1.index_name AS index1_name,
            ia1.action AS index1_action,
            ia1.consolidation_rule AS index1_rule,
            ia1.index_priority AS index1_priority,
            ia1.target_index_name AS index1_target,
            ia1.filter_definition AS index1_filter,
            ia2.index_name AS index2_name,
            ia2.action AS index2_action,
            ia2.consolidation_rule AS index2_rule,
            ia2.index_priority AS index2_priority,
            ia2.target_index_name AS index2_target,
            ia2.filter_definition AS index2_filter
        FROM #index_analysis AS ia1
        JOIN #index_analysis AS ia2 
          ON  ia1.database_id = ia2.database_id
          AND ia1.object_id = ia2.object_id
          AND ia1.index_name <> ia2.index_name
          AND ia1.key_columns = ia2.key_columns  /* Exact key match */
          AND ISNULL(ia1.included_columns, '') = ISNULL(ia2.included_columns, '')  /* Exact includes match */
          AND ISNULL(ia1.filter_definition, '') = ISNULL(ia2.filter_definition, '')  /* Matching filters */
        WHERE ia1.consolidation_rule = 'Exact Duplicate'
           OR ia2.consolidation_rule = 'Exact Duplicate'
        ORDER BY ia1.index_name
        OPTION(RECOMPILE);
    END;

    /* Rule 3: Key duplicates - matching key columns, different includes */
    UPDATE 
        ia1
    SET 
        ia1.consolidation_rule = 'Key Duplicate',
        ia1.target_index_name = 
            CASE 
                /* If one is unique and the other isn't, prefer the unique one */
                WHEN ia1.is_unique = 1 
                AND  ia2.is_unique = 0 
                THEN NULL
                WHEN ia1.is_unique = 0 
                AND  ia2.is_unique = 1 
                THEN ia2.index_name
                /* Otherwise use priority */
                WHEN ia1.index_priority >= ia2.index_priority 
                THEN NULL
                ELSE ia2.index_name
            END,
        ia1.action = 
            CASE 
                WHEN (ia1.is_unique = 1 AND ia2.is_unique = 0) 
                OR   
                (
                    ia1.index_priority >= ia2.index_priority 
                  AND NOT (ia1.is_unique = 0 AND ia2.is_unique = 1)
                )
                AND ISNULL(ia1.included_columns, N'') <> ISNULL(ia2.included_columns, N'')
                THEN 'MERGE INCLUDES'  /* Keep this index but merge includes */
                ELSE 'DISABLE'  /* Other index is keeper, disable this one */
            END,
        /* For the winning index, set clear superseded_by text for the report */
        ia1.superseded_by = 
            CASE 
                WHEN (ia1.is_unique = 1 AND ia2.is_unique = 0) 
                OR   
                (
                    ia1.index_priority >= ia2.index_priority 
                  AND NOT (ia1.is_unique = 0 AND ia2.is_unique = 1)
                )
                THEN 'Supersedes ' + 
                     ia2.index_name
                ELSE NULL
            END
    FROM #index_analysis AS ia1
    JOIN #index_analysis AS ia2 
      ON  ia1.database_id = ia2.database_id
      AND ia1.object_id = ia2.object_id
      AND ia1.index_name <> ia2.index_name
      AND ia1.key_columns = ia2.key_columns  /* Exact key match */
      AND ISNULL(ia1.included_columns, '') <> ISNULL(ia2.included_columns, '')  /* Different includes */
      AND ISNULL(ia1.filter_definition, '') = ISNULL(ia2.filter_definition, '')  /* Matching filters */
    WHERE ia1.consolidation_rule IS NULL  /* Not already processed */
    AND   ia2.consolidation_rule IS NULL  /* Not already processed */
    /* Exclude pairs where either one is a unique constraint (we'll handle those separately in Rule 7) */
    AND NOT EXISTS 
    (
        SELECT 
            1/0 
        FROM #index_details AS id1_uc
        WHERE id1_uc.database_id = ia1.database_id
        AND   id1_uc.object_id = ia1.object_id
        AND   id1_uc.index_id = ia1.index_id
        AND   id1_uc.is_unique_constraint = 1
    )
    AND NOT EXISTS 
    (
        SELECT 
            1/0 
        FROM #index_details AS id2_uc
        WHERE id2_uc.database_id = ia2.database_id
        AND   id2_uc.object_id = ia2.object_id
        AND   id2_uc.index_id = ia2.index_id
        AND   id2_uc.is_unique_constraint = 1
    )
    AND EXISTS 
    (
        SELECT 
            1/0 
        FROM #index_details AS id1
        WHERE id1.database_id = ia1.database_id
        AND   id1.object_id = ia1.object_id
        AND   id1.index_id = ia1.index_id
        AND   id1.is_eligible_for_dedupe = 1
    )
    AND EXISTS 
    (
        SELECT 
            1/0 
        FROM #index_details AS id2
        WHERE id2.database_id = ia2.database_id
        AND   id2.object_id = ia2.object_id
        AND   id2.index_id = ia2.index_id
        AND   id2.is_eligible_for_dedupe = 1
    )
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#index_analysis after rule 3',
            ia.*
        FROM #index_analysis AS ia
        OPTION(RECOMPILE);
    END;
        
    /* Rule 4: Superset/subset key columns */
    UPDATE 
        ia1
    SET 
        ia1.consolidation_rule = 'Key Subset',
        ia1.target_index_name = ia2.index_name,
        ia1.action = N'DISABLE'  /* The narrower index gets disabled */
    FROM #index_analysis AS ia1
    JOIN #index_analysis AS ia2 
      ON  ia1.database_id = ia2.database_id
      AND ia1.object_id = ia2.object_id
      AND ia1.index_name <> ia2.index_name
      AND ia2.key_columns LIKE (ia1.key_columns + '%')  /* ia2 has wider key that starts with ia1's key */
      AND ISNULL(ia1.filter_definition, '') = ISNULL(ia2.filter_definition, '')  /* Matching filters */
      /* Exception: If narrower index is unique and wider is not, they should not be merged */
      AND NOT (ia1.is_unique = 1 AND ia2.is_unique = 0)
    WHERE ia1.consolidation_rule IS NULL  /* Not already processed */
    AND   ia2.consolidation_rule IS NULL  /* Not already processed */
    AND EXISTS 
    (
        SELECT 
            1/0 
        FROM #index_details AS id1
        WHERE id1.database_id = ia1.database_id
        AND   id1.object_id = ia1.object_id
        AND   id1.index_id = ia1.index_id
        AND   id1.is_eligible_for_dedupe = 1
    )
    AND EXISTS 
    (
        SELECT 
            1/0 
        FROM #index_details AS id2
        WHERE id2.database_id = ia2.database_id
        AND   id2.object_id = ia2.object_id
        AND   id2.index_id = ia2.index_id
        AND   id2.is_eligible_for_dedupe = 1
    )
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#index_analysis after rule 4',
            ia.*
        FROM #index_analysis AS ia
        OPTION(RECOMPILE);
    END;
    
    /* Rule 5: Mark superset indexes for merging with includes from subset */
    UPDATE 
        ia2
    SET 
        ia2.consolidation_rule = 'Key Superset',
        ia2.action = N'MERGE INCLUDES',  /* The wider index gets merged with includes */
        ia2.superseded_by = COALESCE(ia2.superseded_by + ', ', '') + 'Supersedes ' + ia1.index_name
    FROM #index_analysis AS ia1
    JOIN #index_analysis AS ia2 
      ON  ia1.database_id = ia2.database_id
      AND ia1.object_id = ia2.object_id
      AND ia1.target_index_name = ia2.index_name  /* Link from Rule 4 */
    WHERE ia1.consolidation_rule = 'Key Subset'
    AND   ia1.action = 'DISABLE'
    AND   ia2.consolidation_rule IS NULL  /* Not already processed */
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#index_analysis after rule 5',
            ia.*
        FROM #index_analysis AS ia
        OPTION(RECOMPILE);
    END;
    
    /* Rule 6: Merge includes from subset to superset indexes */
    WITH KeySubsetSuperset AS
    (
        SELECT 
            superset.database_id,
            superset.object_id,
            superset.index_id,
            superset.index_name,
            superset.included_columns AS superset_includes,
            subset.included_columns AS subset_includes
        FROM #index_analysis AS superset
        JOIN #index_analysis AS subset
          ON  superset.database_id = subset.database_id
          AND superset.object_id = subset.object_id
          AND subset.target_index_name = superset.index_name
        WHERE superset.action = 'MERGE INCLUDES'
        AND   subset.action = 'DISABLE'
        AND   superset.consolidation_rule = 'Key Superset'
        AND   subset.consolidation_rule = 'Key Subset'
    )
    UPDATE 
        ia
    SET 
        ia.included_columns = 
        CASE
            /* If both have includes, combine them without duplicates */
            WHEN kss.superset_includes IS NOT NULL 
            AND kss.subset_includes IS NOT NULL
            THEN 
                /* Create combined includes using XML method that works with all SQL Server versions */
                (
                    SELECT 
                        /* Combine both sets of includes */
                        combined_cols = 
                            STUFF
                            (
                                (
                                    SELECT DISTINCT
                                        N', ' + t.c.value('.', 'sysname')
                                    FROM 
                                    (
                                        /* Create XML from superset includes */
                                        SELECT 
                                            x = CONVERT
                                            (
                                                xml, 
                                                N'<c>' + 
                                                REPLACE(kss.superset_includes, N', ', N'</c><c>') + 
                                                N'</c>'
                                            )

                                        UNION ALL

                                        /* Create XML from subset includes */
                                        SELECT 
                                            x = CONVERT
                                            (
                                                xml, 
                                                N'<c>' + 
                                                REPLACE(kss.subset_includes, N', ', N'</c><c>') + 
                                                N'</c>'
                                            )
                                    ) AS a
                                    /* Split XML into individual columns */
                                    CROSS APPLY a.x.nodes('/c') AS t(c)
                                    FOR 
                                        XML 
                                        PATH('')
                                ),
                                1, 
                                2, 
                                ''
                            )
                )
            /* If only subset has includes, use those */
            WHEN kss.superset_includes IS NULL AND kss.subset_includes IS NOT NULL
            THEN kss.subset_includes
            /* If only superset has includes or neither has includes, keep superset's includes */
            ELSE kss.superset_includes
        END
    FROM #index_analysis AS ia
    JOIN KeySubsetSuperset AS kss
      ON  ia.database_id = kss.database_id
      AND ia.object_id = kss.object_id
      AND ia.index_id = kss.index_id
    WHERE ia.action = 'MERGE INCLUDES';

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#index_analysis after rule 6',
            ia.*
        FROM #index_analysis AS ia
        OPTION(RECOMPILE);
    END;
    
    /* Update the superseded_by column for the wider index in a separate statement */
    UPDATE 
        ia2
    SET 
        ia2.superseded_by = 'Supersedes ' + ia1.index_name
    FROM #index_analysis AS ia1
    JOIN #index_analysis AS ia2 
      ON  ia1.database_id = ia2.database_id
      AND ia1.object_id = ia2.object_id
      AND ia1.index_name <> ia2.index_name
      AND ia2.key_columns LIKE (ia1.key_columns + '%')  /* ia2 has wider key that starts with ia1's key */
      AND ISNULL(ia1.filter_definition, '') = ISNULL(ia2.filter_definition, '')  /* Matching filters */
      /* Exception: If narrower index is unique and wider is not, they should not be merged */
      AND NOT (ia1.is_unique = 1 AND ia2.is_unique = 0)
    WHERE ia1.consolidation_rule = 'Key Subset'  /* Use records just processed in previous UPDATE */
    AND   ia1.target_index_name = ia2.index_name  /* Make sure we're updating the right wider index */
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#index_analysis after update superseded',
            ia.*
        FROM #index_analysis AS ia
        OPTION(RECOMPILE);
    END;

    /* Rule 7: Unique constraint vs. nonclustered index handling */
    UPDATE 
        ia1
    SET 
        ia1.consolidation_rule = 'Unique Constraint Replacement',
        ia1.action = 
            CASE 
                WHEN ia1.is_unique = 0 
                THEN 'MAKE UNIQUE'  /* Convert to unique index */
                ELSE 'KEEP'  /* Already unique, so just keep it */
            END
    FROM #index_analysis AS ia1
    WHERE ia1.consolidation_rule IS NULL /* Not already processed */
    AND ia1.action IS NULL /* Not already processed by earlier rules */
    AND EXISTS 
    (
        /* Find nonclustered indexes */
        SELECT 
            1/0 
        FROM #index_details AS id1
        WHERE id1.database_id = ia1.database_id
        AND   id1.object_id = ia1.object_id
        AND   id1.index_id = ia1.index_id
        AND   id1.is_eligible_for_dedupe = 1
    )
    AND EXISTS 
    (
        /* Find unique constraints with matching key columns */
        SELECT 
            1/0
        FROM #index_details AS id2
        WHERE id2.database_id = ia1.database_id
        AND   id2.object_id = ia1.object_id
        AND   id2.is_unique_constraint = 1
        AND NOT EXISTS 
        (
            /* Verify key columns match between index and unique constraint */
            SELECT 
                id2_inner.column_name 
            FROM #index_details AS id2_inner
            WHERE id2_inner.database_id = id2.database_id
            AND   id2_inner.object_id = id2.object_id
            AND   id2_inner.index_id = id2.index_id
            AND   id2_inner.is_included_column = 0
            
            EXCEPT
            
            SELECT 
                id1_inner.column_name
            FROM #index_details AS id1_inner
            WHERE id1_inner.database_id = ia1.database_id
            AND   id1_inner.object_id = ia1.object_id
            AND   id1_inner.index_id = ia1.index_id
            AND   id1_inner.is_included_column = 0
        )
    )
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#index_analysis after rule 7',
            ia.*
        FROM #index_analysis AS ia
        OPTION(RECOMPILE);
    END;
    
    /* Rule 7.5: Mark unique constraints that have matching nonclustered indexes for disabling */
    /* First, mark unique constraints for disabling */
    UPDATE 
        ia_uc
    SET 
        ia_uc.consolidation_rule = 'Unique Constraint Replacement',
        ia_uc.action = N'DISABLE', /* Mark unique constraint for disabling */
        ia_uc.target_index_name = ia_nc.index_name /* Point to the nonclustered index that will replace it */
    FROM #index_analysis AS ia_uc /* Unique constraint */
    JOIN #index_details AS id_uc /* Join to get unique constraint details */
      ON  id_uc.database_id = ia_uc.database_id
      AND id_uc.object_id = ia_uc.object_id
      AND id_uc.index_id = ia_uc.index_id
      AND id_uc.is_unique_constraint = 1 /* This is a unique constraint */
    JOIN #index_analysis AS ia_nc /* Join to find nonclustered index */
      ON  ia_nc.database_id = ia_uc.database_id
      AND ia_nc.object_id = ia_uc.object_id
      AND ia_nc.index_name <> ia_uc.index_name /* Different index */
    WHERE 
        /* Verify key columns EXACT match between index and unique constraint */
        ia_uc.key_columns = ia_nc.key_columns
    OPTION(RECOMPILE);

    /* Second, mark nonclustered indexes to be made unique */
    UPDATE 
        ia_nc
    SET 
        ia_nc.consolidation_rule = 'Unique Constraint Replacement',
        ia_nc.action = N'MAKE UNIQUE', /* Mark nonclustered index to be made unique */
        /* CRITICAL: Set target_index_name to NULL to ensure it gets a MERGE script */
        ia_nc.target_index_name = NULL
    FROM #index_analysis AS ia_nc /* Nonclustered index */
    JOIN #index_details AS id_nc /* Join to get nonclustered index details */
      ON  id_nc.database_id = ia_nc.database_id
      AND id_nc.object_id = ia_nc.object_id
      AND id_nc.index_id = ia_nc.index_id
      AND id_nc.is_unique_constraint = 0 /* This is not a unique constraint */
    WHERE 
        /* Two conditions for matching:
           1. Index key columns exactly match a unique constraint's key columns
           2. A unique constraint is already marked for DISABLE and has this index as target */
        (EXISTS (
            /* Find unique constraint with matching keys that should be disabled */
            SELECT 1
            FROM #index_analysis AS ia_uc
            JOIN #index_details AS id_uc
              ON  id_uc.database_id = ia_uc.database_id
              AND id_uc.object_id = ia_uc.object_id
              AND id_uc.index_id = ia_uc.index_id
              AND id_uc.is_unique_constraint = 1
            WHERE 
                ia_uc.database_id = ia_nc.database_id
                AND ia_uc.object_id = ia_nc.object_id
                /* Check that both indexes have EXACTLY the same key columns */
                AND ia_uc.key_columns = ia_nc.key_columns
        ))
    OPTION(RECOMPILE);
    
    /* CRITICAL: Ensure that only the unique constraints that exactly match get this treatment */
    /* And remove any incorrect MAKE UNIQUE actions */
    UPDATE ia
    SET action = NULL,
        consolidation_rule = NULL,
        target_index_name = NULL
    FROM #index_analysis AS ia
    WHERE ia.action = N'MAKE UNIQUE'
    AND NOT EXISTS (
        /* Check if there's a unique constraint with matching keys that points to this index */
        SELECT 1
        FROM #index_analysis AS ia_uc
        WHERE ia_uc.database_id = ia.database_id
        AND ia_uc.object_id = ia.object_id
        AND ia_uc.key_columns = ia.key_columns
        AND ia_uc.action = N'DISABLE'
        AND ia_uc.target_index_name = ia.index_name
    );
    
    /* Make sure the nonclustered index has the superseded_by field set correctly */
    UPDATE ia_nc
    SET 
        ia_nc.superseded_by = 
            CASE 
                WHEN ia_nc.superseded_by IS NULL THEN N'Will replace constraint ' + ia_uc.index_name
                ELSE ia_nc.superseded_by + N', will replace constraint ' + ia_uc.index_name
            END
    FROM #index_analysis AS ia_nc
    JOIN #index_analysis AS ia_uc
      ON  ia_uc.database_id = ia_nc.database_id
      AND ia_uc.object_id = ia_nc.object_id
      AND ia_uc.action = N'DISABLE'
      AND ia_uc.target_index_name = ia_nc.index_name
    WHERE ia_nc.action = N'MAKE UNIQUE'
    OPTION(RECOMPILE);
    
    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#index_analysis after rule 7.5',
            ia.*
        FROM #index_analysis AS ia
        OPTION(RECOMPILE);
        
        /* Special debug for uq_a and uq_i_a */
        RAISERROR('Special debug for uq_a and uq_i_a after rule 7.5:', 0, 0) WITH NOWAIT;
        SELECT 
            index_name,
            action,
            consolidation_rule,
            target_index_name,
            superseded_by,
            included_columns,
            index_priority
        FROM #index_analysis
        WHERE index_name IN ('uq_a', 'uq_i_a')
        ORDER BY index_name
        OPTION(RECOMPILE);
        
        /* Check the merge script eligibility */
        RAISERROR('Checking MERGE script eligibility for uq_i_a:', 0, 0) WITH NOWAIT;
        SELECT
            'uq_i_a eligibility check',
            ia.index_name,
            ia.action,
            ia.target_index_name,
            ce.can_compress,
            /* Show which conditions are being met for script generation */
            condition1 = CASE WHEN ia.action IN (N'MERGE INCLUDES', N'MAKE UNIQUE') THEN 'YES' ELSE 'NO' END,
            condition2 = CASE WHEN ce.can_compress = 1 THEN 'YES' ELSE 'NO' END, 
            condition3 = CASE WHEN ia.target_index_name IS NULL THEN 'YES' ELSE 'NO' END,
            /* Will this index get a MERGE script? */
            will_get_merge_script = 
                CASE 
                    WHEN ia.action IN (N'MERGE INCLUDES', N'MAKE UNIQUE')
                    AND  ce.can_compress = 1
                    AND  ia.target_index_name IS NULL
                    THEN 'YES'
                    ELSE 'NO'
                END
        FROM #index_analysis AS ia
        JOIN #compression_eligibility AS ce 
          ON  ia.database_id = ce.database_id
          AND ia.object_id = ce.object_id
          AND ia.index_id = ce.index_id
        WHERE ia.index_name = 'uq_i_a'
        OPTION(RECOMPILE);
    END;
    
    /* Rule 8: Identify indexes with same keys but in different order after first column */
    /* This rule flags indexes that have the same set of key columns but ordered differently */
    /* These need manual review as they may be redundant depending on query patterns */
    UPDATE 
        ia1
    SET 
        ia1.consolidation_rule = 'Same Keys Different Order',
        ia1.action = N'REVIEW',  /* These need manual review */
        ia1.target_index_name = ia2.index_name  /* Reference the partner index */
    FROM #index_analysis AS ia1
    JOIN #index_analysis AS ia2
      ON  ia1.database_id = ia2.database_id
      AND ia1.object_id = ia2.object_id
      AND ia1.index_name < ia2.index_name  /* Only process each pair once */
      AND ia1.consolidation_rule IS NULL  /* Not already processed */
      AND ia2.consolidation_rule IS NULL  /* Not already processed */
    WHERE 
        /* Leading columns match */
        EXISTS 
        (
            SELECT
                1/0
            FROM #index_details AS id1
            JOIN #index_details AS id2
              ON  id1.database_id = id2.database_id
              AND id1.object_id = id2.object_id
              AND id1.column_name = id2.column_name
              AND id1.key_ordinal = 1
              AND id2.key_ordinal = 1
            WHERE id1.database_id = ia1.database_id
            AND   id1.object_id = ia1.object_id
            AND   id1.index_id = ia1.index_id
            AND   id2.index_id = ia2.index_id
        )
        /* Same set of key columns but in different order */
        AND NOT EXISTS 
        (
            /* Make sure the sets of key columns are exactly the same */
            SELECT
                id1.column_name
            FROM #index_details AS id1
            WHERE id1.database_id = ia1.database_id
            AND id1.object_id = ia1.object_id
            AND id1.index_id = ia1.index_id
            AND id1.is_included_column = 0
            AND id1.key_ordinal > 0
            
            EXCEPT
            
            SELECT 
                id2.column_name
            FROM #index_details AS id2
            WHERE id2.database_id = ia2.database_id
            AND   id2.object_id = ia2.object_id
            AND   id2.index_id = ia2.index_id
            AND   id2.is_included_column = 0
            AND   id2.key_ordinal > 0
        )
        /* But the order is different (excluding the first column) */
        AND EXISTS 
        (
            /* There's at least one column in a different position */
            SELECT 
                1/0
            FROM #index_details AS id1
            JOIN #index_details AS id2
              ON  id1.database_id = id2.database_id
              AND id1.object_id = id2.object_id
              AND id1.column_name = id2.column_name
              AND id1.key_ordinal <> id2.key_ordinal
              AND id1.key_ordinal > 1  /* After the first column */
              AND id2.key_ordinal > 1  /* After the first column */
            WHERE id1.database_id = ia1.database_id
            AND   id1.object_id = ia1.object_id
            AND   id1.index_id = ia1.index_id
            AND   id2.index_id = ia2.index_id
        )
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#index_analysis after rule 8',
            ia.*
        FROM #index_analysis AS ia
        OPTION(RECOMPILE);
    END;

    /* Create a reference to the detailed summary that will appear at the end */
    IF @debug = 1
    BEGIN
        RAISERROR('Generating #index_cleanup_results insert', 0, 0) WITH NOWAIT;
    END;

    INSERT INTO 
        #index_cleanup_results
    (
        result_type,
        sort_order,
        script_type,
        additional_info
    )
    SELECT 
        result_type = 'SUMMARY',
        sort_order = 1,
        script_type = 'Index Cleanup Scripts',
        additional_info = N'A detailed index analysis report appears after these scripts'
    OPTION(RECOMPILE);


    /* Identify key duplicates where both indexes have MERGE INCLUDES action */
    IF @debug = 1
    BEGIN
        RAISERROR('Generating #key_duplicate_dedupe insert', 0, 0) WITH NOWAIT;
    END;

    INSERT INTO 
        #key_duplicate_dedupe
    WITH
        (TABLOCK)
    (
        database_id,
        object_id,
        database_name,
        schema_name,
        table_name,
        base_key_columns,
        filter_definition,
        winning_index_name,
        index_list
    )
    SELECT
        ia.database_id,
        ia.object_id,
        database_name = MAX(ia.database_name),
        schema_name = MAX(ia.schema_name),
        table_name = MAX(ia.table_name),
        base_key_columns = ia.key_columns,
        filter_definition = ISNULL(ia.filter_definition, N''),
        /* Choose the index with most included columns as the winner (or first alphabetically if tied) */
        winning_index_name =
        (
            SELECT TOP (1) 
                candidate.index_name
            FROM #index_analysis AS candidate
            WHERE candidate.database_id = ia.database_id
              AND candidate.object_id = ia.object_id
              AND candidate.key_columns = ia.key_columns
              AND ISNULL(candidate.filter_definition, '') = ISNULL(ia.filter_definition, '')
              AND candidate.action = N'MERGE INCLUDES'
              AND candidate.consolidation_rule = 'Key Duplicate'
            ORDER BY 
                /* First prefer indexes with "_Extended" in the name */
                CASE WHEN candidate.index_name LIKE '%\_Extended%' ESCAPE '\' THEN 1 ELSE 0 END DESC,
                /* Then prefer indexes with more included columns (by length as a proxy) */
                LEN(ISNULL(candidate.included_columns, '')) DESC,
                /* Then alphabetically for stability */
                candidate.index_name
        ),
        /* Build a list of other indexes in this group */
        index_list =
            STUFF
            (
              (
                SELECT 
                    N', ' + 
                    inner_ia.index_name
                FROM #index_analysis AS inner_ia
                WHERE inner_ia.database_id = ia.database_id
                  AND inner_ia.object_id = ia.object_id
                  AND inner_ia.key_columns = ia.key_columns
                  AND ISNULL(inner_ia.filter_definition, '') = ISNULL(ia.filter_definition, '')
                  AND inner_ia.action = N'MERGE INCLUDES'
                  AND inner_ia.consolidation_rule = 'Key Duplicate'
                ORDER BY 
                    inner_ia.index_name
                FOR 
                    XML 
                    PATH(''), 
                    TYPE
              ).value('.', 'nvarchar(max)'), 
              1, 
              2, 
              ''
            )
    FROM #index_analysis AS ia
    WHERE ia.action = N'MERGE INCLUDES'
      AND ia.consolidation_rule = 'Key Duplicate'
    GROUP BY
        ia.database_id,
        ia.object_id,
        ia.key_columns,
        ia.filter_definition
    HAVING 
        COUNT_BIG(*) > 1
    OPTION(RECOMPILE); /* Only groups with multiple MERGE INCLUDES */

    /* Update the index_analysis table to make only one index the winner in each group */
    IF @debug = 1
    BEGIN
        RAISERROR('Generating #index_analysis updates', 0, 0) WITH NOWAIT;
    END;

    UPDATE 
        ia
    SET
        ia.action = N'DISABLE',
        ia.target_index_name = kdd.winning_index_name,
        ia.superseded_by = NULL
    FROM #index_analysis AS ia
    JOIN #key_duplicate_dedupe AS kdd
      ON  ia.database_id = kdd.database_id
      AND ia.object_id = kdd.object_id
      AND ia.key_columns = kdd.base_key_columns
      AND ISNULL(ia.filter_definition, N'') = kdd.filter_definition
    WHERE ia.index_name <> kdd.winning_index_name
      AND ia.action = N'MERGE INCLUDES'
      AND ia.consolidation_rule = 'Key Duplicate'
    OPTION(RECOMPILE);

    /* Update the winning index's superseded_by to list all other indexes */
    UPDATE 
        ia
    SET
        ia.superseded_by = 'Supersedes ' + 
        REPLACE
        (
            kdd.index_list, 
            ia.index_name + N', ', N''
        ) /* Remove self from list if present */
    FROM #index_analysis AS ia
    JOIN #key_duplicate_dedupe AS kdd
      ON  ia.database_id = kdd.database_id
      AND ia.object_id = kdd.object_id
      AND ia.key_columns = kdd.base_key_columns
      AND ISNULL(ia.filter_definition, '') = kdd.filter_definition
    WHERE ia.index_name = kdd.winning_index_name
    OPTION(RECOMPILE);

    /* Find indexes with same key columns where one has includes that are a subset of another */
    IF @debug = 1
    BEGIN
        RAISERROR('Generating #include_subset_dedupe insert', 0, 0) WITH NOWAIT;
    END;

    INSERT INTO 
        #include_subset_dedupe
    WITH
        (TABLOCK)
    (
        database_id,
        object_id,
        subset_index_name,
        superset_index_name,
        subset_included_columns,
        superset_included_columns
    )
    SELECT
        ia1.database_id,
        ia1.object_id,
        ia1.index_name AS subset_index_name,
        ia2.index_name AS superset_index_name,
        ia1.included_columns AS subset_included_columns,
        ia2.included_columns AS superset_included_columns
    FROM #index_analysis AS ia1
    JOIN #index_analysis AS ia2
      ON  ia1.database_id = ia2.database_id
      AND ia1.object_id = ia2.object_id
      AND ia1.key_columns = ia2.key_columns
      AND ISNULL(ia1.filter_definition, N'') = ISNULL(ia2.filter_definition, N'')
      AND ia1.index_name <> ia2.index_name
      AND ia1.action = N'MERGE INCLUDES'
      AND ia2.action = N'MERGE INCLUDES'
      AND ia1.consolidation_rule = 'Key Duplicate'
      AND ia2.consolidation_rule = 'Key Duplicate'
      /* Find where subset's includes are contained within superset's includes */
      AND 
      (
             ia1.included_columns IS NULL 
          OR CHARINDEX(ia1.included_columns, ia2.included_columns) > 0
      )
      /* Don't match if lengths are the same (would be exact duplicates) */
      AND 
      (
           ia1.included_columns IS NULL 
        OR ia2.included_columns IS NULL 
        OR LEN(ia1.included_columns) < LEN(ia2.included_columns)
      )
    OPTION(RECOMPILE);

    /* Update the subset indexes to be disabled, since supersets already contain their columns */
    IF @debug = 1
    BEGIN
        RAISERROR('Generating #index_analysis updates', 0, 0) WITH NOWAIT;
    END;

    UPDATE 
        ia
    SET
        ia.action = N'DISABLE',
        ia.target_index_name = isd.superset_index_name,
        ia.superseded_by = NULL
    FROM #index_analysis AS ia
    JOIN #include_subset_dedupe AS isd
      ON  ia.database_id = isd.database_id
      AND ia.object_id = isd.object_id
      AND ia.index_name = isd.subset_index_name
    OPTION(RECOMPILE);

    /* Update the superset indexes to indicate they supersede the subset indexes */
    UPDATE 
        ia
    SET
        ia.superseded_by = 
            CASE
                WHEN ia.superseded_by IS NULL 
                THEN N'Supersedes ' + isd.subset_index_name
                ELSE ia.superseded_by + N', ' + isd.subset_index_name
            END
    FROM #index_analysis AS ia
    JOIN #include_subset_dedupe AS isd
      ON  ia.database_id = isd.database_id
      AND ia.object_id = isd.object_id
      AND ia.index_name = isd.superset_index_name
    OPTION(RECOMPILE);

    /* Update winning indexes that don't actually need changes to have action = N'KEEP' */
    UPDATE 
        ia
    SET
        /* Change action to 'KEEP' for indexes that don't need to be modified */
        ia.action = N'KEEP'
    FROM #index_analysis AS ia
    WHERE ia.action = N'MERGE INCLUDES'
    AND   ia.superseded_by IS NOT NULL
    /* Check if the index name contains "Extended" and has more included columns */
    AND  (ia.index_name LIKE '%\_Extended%' ESCAPE '\' OR ia.index_name LIKE '%\_Extended' OR ia.index_name LIKE '%_Extended%')
    /* This should indicate it already has all the needed includes */
    AND NOT EXISTS 
    (
        /* Find any indexes it supersedes that have includes not in this index */
        SELECT 
            1/0
        FROM #index_analysis AS ia_subset
        WHERE ia_subset.database_id = ia.database_id
        AND   ia_subset.object_id = ia.object_id
        AND   ia_subset.key_columns = ia.key_columns
        AND   ia_subset.action = N'DISABLE'
        AND   ia_subset.target_index_name = ia.index_name
        /* This complex check handles cases where the superset doesn't contain all subset columns */
        AND   CHARINDEX(ISNULL(ia_subset.included_columns, N''), ISNULL(ia.included_columns, N'')) = 0
        AND   ISNULL(ia_subset.included_columns, N'') <> N''
    )
    OPTION(RECOMPILE);

    /* Insert merge scripts for indexes */
    IF @debug = 1
    BEGIN
        RAISERROR('Generating #index_cleanup_results insert, MERGE', 0, 0) WITH NOWAIT;
    END;

    INSERT INTO 
        #index_cleanup_results
    (
        result_type,
        sort_order,
        database_name,
        schema_name,
        table_name,
        index_name,
        script_type,
        consolidation_rule,
        target_index_name,
        script,
        additional_info,
        superseded_info,
        original_index_definition,
        index_size_gb,
        index_rows,
        index_reads,
        index_writes
    )
    SELECT DISTINCT
        result_type = 'MERGE',
        /* Put merge target indexes higher in sort order (5) so they appear before 
           indexes that will be disabled (20) */
        sort_order = 5,
        ia.database_name,
        ia.schema_name,
        ia.table_name,
        ia.index_name,
        script_type = N'MERGE SCRIPT',
        ia.consolidation_rule,
        ia.target_index_name,
        script =
            CASE 
                WHEN ia.action = N'MAKE UNIQUE' 
                THEN N'CREATE UNIQUE '
                WHEN ia.action = N'MERGE INCLUDES'
                THEN N'CREATE '
                ELSE N'CREATE '
            END +
            N'INDEX ' +
            QUOTENAME(ia.index_name) +
            N' ON ' +
            QUOTENAME(ia.database_name) +
            N'.' +
            QUOTENAME(ia.schema_name) +
            N'.' +
            QUOTENAME(ia.table_name) +
            N' (' +
            ia.key_columns +
            N')' +
            CASE 
                WHEN ia.included_columns IS NOT NULL 
                AND  LEN(ia.included_columns) > 0 
                AND  ia.action = N'MERGE INCLUDES'
                THEN N' INCLUDE (' +
                     ia.included_columns +
                     N')'
                WHEN ia.included_columns IS NOT NULL 
                AND  LEN(ia.included_columns) > 0
                THEN N' INCLUDE (' +
                     ia.included_columns +
                     N')'
                ELSE N''
            END +
            CASE 
                WHEN ia.filter_definition IS NOT NULL
                THEN N' WHERE ' +
                     ia.filter_definition
                ELSE N''
            END +
            N' WITH (DROP_EXISTING = ON, FILLFACTOR = 100, SORT_IN_TEMPDB = ON, ONLINE = ' +
            CASE 
                WHEN @online = 1 
                THEN N'ON' 
                ELSE N'OFF' 
            END +
            CASE 
                WHEN ce.can_compress = 1
                THEN ', DATA_COMPRESSION = PAGE'
                ELSE N''
                END +
            N')' +
            CASE 
                WHEN ps.partition_function_name IS NOT NULL
                THEN N' ON ' +
                     QUOTENAME(ps.partition_function_name) +
                     N'(' +
                     ISNULL(ps.partition_columns, N'') +
                     N')'
                WHEN ps.built_on IS NOT NULL
                THEN N' ON ' +
                     QUOTENAME(ps.built_on)
                ELSE N''
            END + N';',
            /* Additional info about what this script does */
        additional_info =
            CASE
                WHEN ia.action = N'MERGE INCLUDES' 
                THEN N'This index will absorb includes from duplicate indexes'
                WHEN ia.action = N'MAKE UNIQUE' 
                THEN N'This index will replace a unique constraint'
                ELSE NULL
            END,
        /* Add superseded_by information if available */
        ia.superseded_by,
        /* Original index definition for validation */
        ia.original_index_definition,
        NULL,
        NULL,
        NULL,
        NULL
    FROM #index_analysis AS ia
    LEFT JOIN 
    (
        /* Get the partition info for each index */
        SELECT 
            ps.database_id,
            ps.object_id,
            ps.index_id,
            ps.built_on,
            ps.partition_function_name,
            ps.partition_columns
        FROM #partition_stats ps
        GROUP BY
            ps.database_id,
            ps.object_id,
            ps.index_id,
            ps.built_on,
            ps.partition_function_name,
            ps.partition_columns
    ) AS ps 
      ON  ia.database_id = ps.database_id 
      AND ia.object_id = ps.object_id
      AND ia.index_id = ps.index_id
    JOIN #compression_eligibility AS ce 
      ON  ia.database_id = ce.database_id
      AND ia.object_id = ce.object_id
      AND ia.index_id = ce.index_id
    WHERE ia.action IN (N'MERGE INCLUDES', N'MAKE UNIQUE')
    AND   ce.can_compress = 1
    /* Only create merge scripts for the indexes that should remain after merging */
    AND   ia.target_index_name IS NULL
    OPTION(RECOMPILE);

    /* Debug which indexes are getting MERGE scripts */
    IF @debug = 1
    BEGIN
        RAISERROR('Indexes getting MERGE scripts:', 0, 0) WITH NOWAIT;
        SELECT 
            ia.index_name,
            ia.action,
            ia.consolidation_rule,
            ia.target_index_name,
            script_type = 'WILL GET MERGE SCRIPT',
            ia.included_columns
        FROM #index_analysis AS ia 
        JOIN #compression_eligibility AS ce 
          ON  ia.database_id = ce.database_id
          AND ia.object_id = ce.object_id
          AND ia.index_id = ce.index_id
        WHERE ia.action IN (N'MERGE INCLUDES', N'MAKE UNIQUE')
        AND   ce.can_compress = 1
        AND   ia.target_index_name IS NULL
        ORDER BY ia.index_name
        OPTION(RECOMPILE);
    END;

    /* Insert disable scripts for unneeded indexes */
    IF @debug = 1
    BEGIN
        RAISERROR('Generating #index_cleanup_results insert, DISABLE', 0, 0) WITH NOWAIT;
        
        /* Debug for indexes that should get DISABLE scripts */
        RAISERROR('Indexes that should get DISABLE scripts:', 0, 0) WITH NOWAIT;
        SELECT
            ia.index_name,
            ia.consolidation_rule,
            ia.action,
            ia.target_index_name,
            ia.is_unique,
            ia.index_priority,
            is_unique_constraint = 
                CASE WHEN EXISTS (
                    SELECT 1 
                    FROM #index_details AS id 
                    WHERE id.database_id = ia.database_id 
                    AND id.object_id = ia.object_id 
                    AND id.index_id = ia.index_id 
                    AND id.is_unique_constraint = 1
                ) THEN 'YES' ELSE 'NO' END,
            make_unique_target = 
                CASE WHEN EXISTS (
                    SELECT 1 
                    FROM #index_analysis AS ia_make 
                    WHERE ia_make.database_id = ia.database_id 
                    AND ia_make.object_id = ia.object_id 
                    AND ia_make.action = 'MAKE UNIQUE' 
                    AND ia_make.target_index_name = ia.index_name
                ) THEN 'YES' ELSE 'NO' END,
            will_get_script = 
                CASE WHEN ia.action = 'DISABLE' AND NOT EXISTS (
                    SELECT 1 
                    FROM #index_details AS id_uc 
                    WHERE id_uc.database_id = ia.database_id 
                    AND id_uc.object_id = ia.object_id 
                    AND id_uc.index_id = ia.index_id 
                    AND id_uc.is_unique_constraint = 1
                ) THEN 'YES' ELSE 'NO' END
        FROM #index_analysis AS ia
        WHERE ia.index_name LIKE 'ix_filtered_%' OR ia.index_name LIKE 'ix_desc_%'
        ORDER BY ia.index_name;
        
        /* Debug for all indexes marked with action = DISABLE */
        RAISERROR('All indexes with action = DISABLE:', 0, 0) WITH NOWAIT;
        SELECT
            ia.index_name,
            ia.consolidation_rule,
            ia.action,
            ia.target_index_name
        FROM #index_analysis AS ia
        WHERE ia.action = 'DISABLE'
        ORDER BY ia.index_name;
    END;

    INSERT INTO 
        #index_cleanup_results
    (
        result_type,
        sort_order,
        database_name,
        schema_name,
        table_name,
        index_name,
        script_type,
        consolidation_rule,
        script,
        additional_info,
        target_index_name,
        superseded_info,
        original_index_definition,
        index_size_gb,
        index_rows,
        index_reads,
        index_writes
    )
    SELECT DISTINCT
        result_type = 'DISABLE',
        /* Sort duplicate/subset indexes first (20), then unused indexes last (25) */
        sort_order =
            CASE 
                WHEN ia.consolidation_rule LIKE 'Unused Index%' THEN 25
                ELSE 20
            END,
        ia.database_name,
        ia.schema_name,
        ia.table_name,
        ia.index_name,
        script_type = 'DISABLE SCRIPT',
        ia.consolidation_rule,
        script =
            /* Use regular DISABLE syntax for indexes */
            N'ALTER INDEX ' +
            QUOTENAME(ia.index_name) +
            N' ON ' +
            QUOTENAME(ia.database_name) +
            N'.' +
            QUOTENAME(ia.schema_name) +
            N'.' +
            QUOTENAME(ia.table_name) +
            N' DISABLE;',
            CASE 
                WHEN ia.consolidation_rule = 'Key Subset' 
                THEN N'This index is superseded by a wider index: ' + ISNULL(ia.target_index_name, N'(unknown)')
                WHEN ia.consolidation_rule = 'Exact Duplicate' 
                THEN N'This index is an exact duplicate of: ' + ISNULL(ia.target_index_name, N'(unknown)')
                WHEN ia.consolidation_rule = 'Key Duplicate' 
                THEN N'This index has the same keys as: ' + ISNULL(ia.target_index_name, N'(unknown)')
                WHEN ia.consolidation_rule LIKE 'Unused Index%' 
                THEN ia.consolidation_rule
                WHEN ia.action = N'DISABLE'
                THEN N'This index is redundant and will be disabled'
                ELSE N'This index is redundant'
            END,
        ia.target_index_name,  /* Include the target index name */
        superseded_info = NULL,  /* Don't need superseded_by info for disabled indexes */
        /* Original index definition for validation */
        ia.original_index_definition,
        ps.total_space_gb,
        ps.total_rows,
        index_reads = 
            (id.user_seeks + id.user_scans + id.user_lookups),
        id.user_updates
    FROM #index_analysis AS ia
    LEFT JOIN #partition_stats AS ps
      ON  ia.database_id = ps.database_id
      AND ia.object_id = ps.object_id
      AND ia.index_id = ps.index_id
    LEFT JOIN #index_details AS id
      ON  id.database_id = ia.database_id
      AND id.object_id = ia.object_id
      AND id.index_id = ia.index_id
      AND id.is_included_column = 0 /* Get only one row per index */
      AND id.key_ordinal > 0
    WHERE ia.action = N'DISABLE'
    /* Exclude unique constraints - they are handled by DISABLE CONSTRAINT scripts */
    AND NOT EXISTS
    (
        SELECT 
            1/0
        FROM #index_details AS id_uc
        WHERE id_uc.database_id = ia.database_id
        AND   id_uc.object_id = ia.object_id
        AND   id_uc.index_id = ia.index_id
        AND   id_uc.is_unique_constraint = 1
    )
    /* Also exclude any index that is also going to be made unique in rule 7.5 */
    AND NOT EXISTS
    (
        SELECT
            1/0
        FROM #index_analysis AS ia_unique
        WHERE ia_unique.database_id = ia.database_id
        AND   ia_unique.object_id = ia.object_id
        AND   ia_unique.index_name = ia.index_name
        AND   ia_unique.action = N'MAKE UNIQUE'
    )
    OPTION(RECOMPILE);

    /* Insert compression scripts for remaining indexes */
    IF @debug = 1
    BEGIN
        RAISERROR('Generating #index_cleanup_results insert, COMPRESS', 0, 0) WITH NOWAIT;
    END;

    INSERT INTO 
        #index_cleanup_results
    (
        result_type,
        sort_order,
        database_name,
        schema_name,
        table_name,
        index_name,
        script_type,
        script,
        additional_info,
        target_index_name,
        superseded_info,
        original_index_definition,
        index_size_gb,
        index_rows,
        index_reads,
        index_writes
    )
    SELECT DISTINCT
        result_type = 'COMPRESS',
        sort_order = 40,
        ia.database_name,
        ia.schema_name,
        ia.table_name,
        ia.index_name,
        script_type = 'COMPRESSION SCRIPT',
        script =
            N'ALTER INDEX ' +
            QUOTENAME(ia.index_name) +
            N' ON ' +
            QUOTENAME(ia.database_name) +
            N'.' +
            QUOTENAME(ia.schema_name) +
            N'.' +
            QUOTENAME(ia.table_name) +
            CASE 
                WHEN ps.partition_function_name IS NOT NULL
                THEN N' REBUILD PARTITION = ALL' 
                ELSE N' REBUILD' 
            END +
            N' WITH (FILLFACTOR = 100, SORT_IN_TEMPDB = ON, ONLINE = ' +
            CASE 
                WHEN @online = 1 
                THEN N'ON' 
                ELSE N'OFF' 
            END +
            CASE 
                WHEN ce.can_compress = 1
                THEN ', DATA_COMPRESSION = PAGE'
                ELSE N''
            END +
            N')' +
        N'Compression type: All Partitions',
        superseded_info = NULL, /* No target index for compression scripts */
        ia.superseded_by, /* Include superseded_by info for compression scripts */
        /* Original index definition for validation */
        ia.original_index_definition,
        ps_full.total_space_gb,
        ps_full.total_rows,
        index_reads =
            (id.user_seeks + id.user_scans + id.user_lookups),
        id.user_updates
    FROM #index_analysis AS ia
    LEFT JOIN 
    (
        /* Get the partition info for each index */
        SELECT 
            ps.database_id,
            ps.object_id,
            ps.index_id,
            ps.built_on,
            ps.partition_function_name,
            ps.partition_columns
        FROM #partition_stats ps
        GROUP BY
            ps.database_id,
            ps.object_id,
            ps.index_id,
            ps.built_on,
            ps.partition_function_name,
            ps.partition_columns
    ) 
      AS ps 
      ON  ia.database_id = ps.database_id
      AND ia.object_id = ps.object_id
      AND ia.index_id = ps.index_id
    LEFT JOIN #partition_stats AS ps_full
      ON  ia.database_id = ps_full.database_id
      AND ia.object_id = ps_full.object_id
      AND ia.index_id = ps_full.index_id
    LEFT JOIN #index_details AS id
      ON  id.database_id = ia.database_id
      AND id.object_id = ia.object_id
      AND id.index_id = ia.index_id
      AND id.is_included_column = 0 /* Get only one row per index */
      AND id.key_ordinal > 0
    JOIN #compression_eligibility AS ce 
      ON  ia.database_id = ce.database_id
      AND ia.object_id = ce.object_id
      AND ia.index_id = ce.index_id
    WHERE 
        /* Indexes that are not being disabled or merged */
        (ia.action IS NULL OR ia.action = N'KEEP')
        /* Only indexes eligible for compression */
    AND  ce.can_compress = 1
    OPTION(RECOMPILE);

    /* Insert disable scripts for unique constraints */
    IF @debug = 1
    BEGIN
        RAISERROR('Generating #index_cleanup_results insert, CONSTRAINT', 0, 0) WITH NOWAIT;
    END;
    
    /* Add code to insert KEPT indexes into the results - THESE WERE MISSING! */
    IF @debug = 1
    BEGIN
        RAISERROR('Generating #index_cleanup_results insert, KEPT', 0, 0) WITH NOWAIT;
    END;
    
    /* Insert KEPT indexes into results */
    INSERT INTO 
        #index_cleanup_results
    (
        result_type,
        sort_order,
        database_name,
        schema_name,
        table_name,
        index_name,
        script_type,
        consolidation_rule,
        additional_info,
        script,
        original_index_definition,
        index_size_gb,
        index_rows,
        index_reads,
        index_writes
    )
    SELECT DISTINCT
        result_type = 'KEPT',
        sort_order = 95, /* Put kept indexes at the end */
        ia.database_name,
        ia.schema_name,
        ia.table_name,
        ia.index_name,
        script_type = NULL,
        ia.consolidation_rule,
        additional_info = 
            CASE 
                WHEN ia.consolidation_rule IS NOT NULL
                THEN 'This index is being kept'
                ELSE NULL
            END,
        script = NULL, /* No script for kept indexes */
        /* Original index definition for validation */
        ia.original_index_definition,
        ps.total_space_gb,
        ps.total_rows,
        index_reads =
            (id.user_seeks + id.user_scans + id.user_lookups),
        id.user_updates
    FROM #index_analysis AS ia
    LEFT JOIN #partition_stats AS ps
      ON  ia.database_id = ps.database_id
      AND ia.object_id = ps.object_id
      AND ia.index_id = ps.index_id
    LEFT JOIN #index_details AS id
      ON  id.database_id = ia.database_id
      AND id.object_id = ia.object_id
      AND id.index_id = ia.index_id
      AND id.is_included_column = 0 /* Get only one row per index */
      AND id.key_ordinal > 0
    /* Check that this index is not already in the results */
    WHERE NOT EXISTS (
        SELECT 1 FROM #index_cleanup_results AS ir
        WHERE ir.database_name = ia.database_name
        AND   ir.schema_name = ia.schema_name
        AND   ir.table_name = ia.table_name
        AND   ir.index_name = ia.index_name
    )
    /* And include only indexes that should be kept */
    AND (
        /* Include indexes marked KEEP */
        (ia.action = 'KEEP')
        /* And all indexes we haven't determined an action for (not disable, merge, etc.) */
        OR (ia.action IS NULL AND ia.index_id > 0)
    )
    OPTION(RECOMPILE);

    INSERT INTO 
        #index_cleanup_results
    (
        result_type,
        sort_order,
        database_name,
        schema_name,
        table_name,
        index_name,
        script_type,
        additional_info,
        script,
        original_index_definition,
        index_size_gb,
        index_rows,
        index_reads,
        index_writes
    )
    SELECT DISTINCT
        result_type = 'CONSTRAINT',
        sort_order = 30,
        ia_uc.database_name,
        ia_uc.schema_name,
        ia_uc.table_name,
        ia_uc.index_name,
        script_type = 'DISABLE CONSTRAINT SCRIPT',
        additional_info = 
            N'This constraint is being replaced by: ' + 
            ISNULL(ia_uc.target_index_name, N'(unknown)'),
        script = 
            N'ALTER TABLE ' +
            QUOTENAME(ia_uc.database_name) +
            N'.' +
            QUOTENAME(ia_uc.schema_name) +
            N'.' +
            QUOTENAME(ia_uc.table_name) +
            N' NOCHECK CONSTRAINT ' +
            QUOTENAME(ia_uc.index_name) +
            N';',
        /* Original index definition for validation */
        original_index_definition = ia_uc.original_index_definition,
        ps.total_space_gb,
        ps.total_rows,
        index_reads =
            (id2.user_seeks + id2.user_scans + id2.user_lookups),
        id2.user_updates
    FROM #index_analysis AS ia_uc
    JOIN #index_details AS id 
      ON  id.database_id = ia_uc.database_id
      AND id.object_id = ia_uc.object_id
      AND id.index_id = ia_uc.index_id
      AND id.is_unique_constraint = 1
    LEFT JOIN #index_details AS id2
      ON  id2.database_id = ia_uc.database_id
      AND id2.object_id = ia_uc.object_id
      AND id2.index_id = ia_uc.index_id
      AND id2.is_included_column = 0 /* Get only one row per index */
      AND id2.key_ordinal > 0
    LEFT JOIN #partition_stats AS ps
      ON  ia_uc.database_id = ps.database_id
      AND ia_uc.object_id = ps.object_id
      AND ia_uc.index_id = ps.index_id
    WHERE 
        /* Only constraints that are marked for disabling */
        ia_uc.action = N'DISABLE'
        /* That have consolidation_rule of 'Unique Constraint Replacement' */
        AND ia_uc.consolidation_rule = 'Unique Constraint Replacement'
    OPTION(RECOMPILE);

    /* Insert per-partition compression scripts */
    IF @debug = 1
    BEGIN
        RAISERROR('Generating #index_cleanup_results insert, COMPRESS_PARTITION', 0, 0) WITH NOWAIT;
    END;

    INSERT INTO 
        #index_cleanup_results
    (
        result_type,
        sort_order,
        database_name,
        schema_name,
        table_name,
        index_name,
        script_type,
        script,
        additional_info,
        target_index_name,
        superseded_info,
        original_index_definition,
        index_size_gb,
        index_rows,
        index_reads,
        index_writes
    )
    SELECT DISTINCT
        result_type = 'COMPRESS_PARTITION',
        sort_order = 50,
        ia.database_name,
        ia.schema_name,
        ia.table_name,
        ia.index_name,
        script_type = 'PARTITION COMPRESSION SCRIPT',
        script = 
            N'ALTER INDEX ' +
            QUOTENAME(ia.index_name) +
            N' ON ' +
            QUOTENAME(ia.database_name) +
            N'.' +
            QUOTENAME(ia.schema_name) +
            N'.' +
            QUOTENAME(ia.table_name) +
            N' REBUILD PARTITION = ' +
            CONVERT
            (
                nvarchar(20), 
                ps.partition_number
            ) +
            N' WITH (FILLFACTOR = 100, SORT_IN_TEMPDB = ON, ONLINE = ' +
            CASE 
                WHEN @online = 1 
                THEN N'ON' 
                ELSE N'OFF' 
            END +
                        CASE 
                WHEN ce.can_compress = 1
                THEN ', DATA_COMPRESSION = PAGE'
                ELSE N''
                END +
            N')',
            N'Compression type: Per Partition | Partition: ' + 
            CONVERT
            (
                nvarchar(20), 
                ps.partition_number
            ) +
            N' | Rows: ' +
            CONVERT
            (
                nvarchar(20), 
                ps.total_rows
            ) +
            N' | Size: ' +
            CONVERT
            (
                nvarchar(20), 
                CONVERT
                (
                    decimal(10,4), 
                    ps.total_space_gb
                )
            ) + 
            N' GB',
        target_index_name = NULL,
        superseded_info = NULL,
        ia.original_index_definition,
        ps.total_space_gb,
        ps.total_rows,
        index_reads =
            (id.user_seeks + id.user_scans + id.user_lookups),
        id.user_updates
    FROM #index_analysis AS ia
    JOIN #partition_stats AS ps 
      ON  ia.database_id = ps.database_id
      AND ia.object_id = ps.object_id
      AND ia.index_id = ps.index_id
    LEFT JOIN #index_details AS id
      ON  id.database_id = ia.database_id
      AND id.object_id = ia.object_id
      AND id.index_id = ia.index_id
      AND id.is_included_column = 0 /* Get only one row per index */
      AND id.key_ordinal > 0
    JOIN #compression_eligibility AS ce 
      ON  ia.database_id = ce.database_id
      AND ia.object_id = ce.object_id
      AND ia.index_id = ce.index_id
    WHERE 
        /* Only partitioned indexes */
        ps.partition_function_name IS NOT NULL
        /* Indexes that are not being disabled or merged */
    AND  (ia.action IS NULL OR ia.action = N'KEEP')
        /* Only indexes eligible for compression */
    AND   ce.can_compress = 1
    OPTION(RECOMPILE);

    /* Insert compression ineligible info */
    IF @debug = 1
    BEGIN
        RAISERROR('Generating #index_cleanup_results insert, INELIGIBLE', 0, 0) WITH NOWAIT;
    END;

    INSERT INTO 
        #index_cleanup_results
    WITH
        (TABLOCK)
    (
        result_type,
        sort_order,
        database_name,
        schema_name,
        table_name,
        index_name,
        script_type,
        additional_info,
        original_index_definition,
        index_size_gb,
        index_rows,
        index_reads,
        index_writes
    )
    SELECT DISTINCT
        result_type = 'INELIGIBLE',
        sort_order = 90,
        ce.database_name,
        ce.schema_name,
        ce.table_name,
        ce.index_name,
        script_type = 'INELIGIBLE FOR COMPRESSION',
        ce.reason,
        /* Original index definition for validation */
        original_index_definition = 
            (
                SELECT TOP (1)
                    ia.original_index_definition
                FROM #index_analysis AS ia
                WHERE ia.database_id = ce.database_id
                AND   ia.object_id = ce.object_id
                AND   ia.index_id = ce.index_id
            ),
        ps.total_space_gb,
        ps.total_rows,
        index_reads =
            (id.user_seeks + id.user_scans + id.user_lookups),
        id.user_updates
    FROM #compression_eligibility AS ce
    LEFT JOIN #partition_stats AS ps
      ON  ce.database_id = ps.database_id
      AND ce.object_id = ps.object_id
      AND ce.index_id = ps.index_id
    LEFT JOIN #index_details AS id
      ON  id.database_id = ce.database_id
      AND id.object_id = ce.object_id
      AND id.index_id = ce.index_id
      AND id.is_included_column = 0 /* Get only one row per index */
      AND id.key_ordinal > 0
    WHERE ce.can_compress = 0
    OPTION(RECOMPILE);


    /* Insert indexes identified for manual review */
    IF @debug = 1
    BEGIN
        RAISERROR('Generating #index_cleanup_results insert, REVIEW', 0, 0) WITH NOWAIT;
    END;

    INSERT INTO 
        #index_cleanup_results
    WITH
        (TABLOCK)
    (
        result_type,
        sort_order,
        database_name,
        schema_name,
        table_name,
        index_name,
        script_type,
        consolidation_rule,
        target_index_name,
        additional_info,
        original_index_definition,
        index_size_gb,
        index_rows,
        index_reads,
        index_writes
    )
    SELECT DISTINCT
        result_type = 'REVIEW',
        sort_order = 93, /* Just before KEPT indexes */
        ia.database_name,
        ia.schema_name,
        ia.table_name,
        ia.index_name,
        script_type = 'NEEDS REVIEW',
        ia.consolidation_rule,
        ia.target_index_name,
        additional_info =
            CASE
                WHEN ia.consolidation_rule = 'Same Keys Different Order' 
                THEN N'This index has the same key columns as ' + ISNULL(ia.target_index_name, N'(unknown)') + 
                     N' but in a different order. May be redundant depending on query patterns.'
                ELSE N'This index needs manual review'
            END,
        /* Original index definition for validation */
        ia.original_index_definition,
        ps.total_space_gb,
        ps.total_rows,
        index_reads =
            (id.user_seeks + id.user_scans + id.user_lookups),
        id.user_updates
    FROM #index_analysis AS ia
    LEFT JOIN #partition_stats AS ps
      ON  ia.database_id = ps.database_id
      AND ia.object_id = ps.object_id
      AND ia.index_id = ps.index_id
    LEFT JOIN #index_details AS id
      ON  id.database_id = ia.database_id
      AND id.object_id = ia.object_id
      AND id.index_id = ia.index_id
      AND id.is_included_column = 0 /* Get only one row per index */
      AND id.key_ordinal > 0
    WHERE ia.action = N'REVIEW'
    OPTION(RECOMPILE);


    /* Insert indexes that are being kept (superset indexes and others) */
    IF @debug = 1
    BEGIN
        RAISERROR('Generating #index_cleanup_results insert, KEEP', 0, 0) WITH NOWAIT;
    END;

    INSERT INTO 
        #index_cleanup_results
    WITH
        (TABLOCK)
    (
        result_type,
        sort_order,
        database_name,
        schema_name,
        table_name,
        index_name,
        script_type,
        consolidation_rule,
        superseded_info,
        additional_info,
        original_index_definition,
        index_size_gb,
        index_rows,
        index_reads,
        index_writes
    )
    SELECT DISTINCT
        result_type = 'KEEP',
        sort_order = 95, /* Just before END OF REPORT at 99 */
        ia.database_name,
        ia.schema_name,
        ia.table_name,
        ia.index_name,
        script_type = 'KEPT',
        ia.consolidation_rule,
        ia.superseded_by,
        additional_info =
            CASE
                WHEN ia.superseded_by IS NOT NULL 
                THEN 'This index supersedes other indexes and already has all needed columns'
                WHEN ia.action = N'KEEP' 
                THEN 'This index is being kept'
                ELSE NULL
            END,
        /* Original index definition for validation */
        ia.original_index_definition,
        ps.total_space_gb,
        ps.total_rows,
        index_reads =
            (id.user_seeks + id.user_scans + id.user_lookups),
        id.user_updates
    FROM #index_analysis AS ia
    LEFT JOIN #partition_stats AS ps
      ON  ia.database_id = ps.database_id
      AND ia.object_id = ps.object_id
      AND ia.index_id = ps.index_id
    LEFT JOIN #index_details AS id
      ON  id.database_id = ia.database_id
      AND id.object_id = ia.object_id
      AND id.index_id = ia.index_id
      AND id.is_included_column = 0 /* Get only one row per index */
      AND id.key_ordinal > 0
    WHERE ia.action = N'KEEP' 
    OR 
    (
          ia.action IS NULL 
      AND ia.consolidation_rule IS NULL
    )
    OPTION(RECOMPILE);

    /* Insert database-level summaries */
    IF @debug = 1
    BEGIN
        RAISERROR('Generating #index_reporting_stats insert, DATABASE', 0, 0) WITH NOWAIT;
    END;

    INSERT INTO 
        #index_reporting_stats
    (
        summary_level,
        database_name,
        index_count,
        total_size_gb,
        total_rows,
        indexes_to_merge,
        unused_indexes,
        unused_size_gb,
        total_reads,
        total_writes,
        user_seeks,
        user_scans,
        user_lookups,
        user_updates,
        range_scan_count,
        singleton_lookup_count,
        row_lock_count,
        row_lock_wait_count,
        row_lock_wait_in_ms,
        page_lock_count,
        page_lock_wait_count,
        page_lock_wait_in_ms,
        page_latch_wait_count,
        page_latch_wait_in_ms,
        page_io_latch_wait_count,
        page_io_latch_wait_in_ms,
        forwarded_fetch_count,
        leaf_insert_count,
        leaf_update_count,
        leaf_delete_count
    )
    SELECT
        summary_level = 
            'DATABASE',
        ps.database_name,
        index_count = 
            COUNT_BIG(DISTINCT CONCAT(ps.object_id, N'.', ps.index_id)),
        total_size_gb = SUM(ps.total_space_gb),
        /* Use a simple aggregation to avoid double-counting */
        /* Get actual row count by grabbing the real row count from clustered index/heap per table */
        total_rows = SUM(DISTINCT d.actual_rows),
        indexes_to_merge = 
            (
                SELECT 
                    COUNT_BIG(*) 
                FROM #index_analysis AS ia 
                WHERE ia.action IN (N'MERGE INCLUDES', N'MAKE UNIQUE') 
                AND   ia.database_id = ps.database_id
            ),
        /* Use count from analysis to keep consistent with SUMMARY level */
        unused_indexes = 
            (
                SELECT 
                    COUNT_BIG(*) 
                FROM #index_analysis AS ia 
                WHERE ia.action = N'DISABLE' 
                AND   ia.database_id = ps.database_id
            ),
        unused_size_gb = 
            SUM
            (
                CASE 
                    WHEN id.user_seeks + id.user_scans + id.user_lookups = 0 
                    THEN ps.total_space_gb 
                    ELSE 0 
                END
            ),
        total_reads = SUM(id.user_seeks + id.user_scans + id.user_lookups),
        total_writes = SUM(id.user_updates),
        user_seeks = SUM(id.user_seeks),
        user_scans = SUM(id.user_scans),
        user_lookups = SUM(id.user_lookups),
        user_updates = SUM(id.user_updates),
        range_scan_count = SUM(os.range_scan_count),
        singleton_lookup_count = SUM(os.singleton_lookup_count),
        row_lock_count = SUM(os.row_lock_count),
        row_lock_wait_count = SUM(os.row_lock_wait_count),
        row_lock_wait_in_ms = SUM(os.row_lock_wait_in_ms),
        page_lock_count = SUM(os.page_lock_count),
        page_lock_wait_count = SUM(os.page_lock_wait_count),
        page_lock_wait_in_ms = SUM(os.page_lock_wait_in_ms),
        page_latch_wait_count = SUM(os.page_latch_wait_count),
        page_latch_wait_in_ms = SUM(os.page_latch_wait_in_ms),
        page_io_latch_wait_count = SUM(os.page_io_latch_wait_count),
        page_io_latch_wait_in_ms = SUM(os.page_io_latch_wait_in_ms),
        forwarded_fetch_count = SUM(os.forwarded_fetch_count),
        leaf_insert_count = SUM(os.leaf_insert_count),
        leaf_update_count = SUM(os.leaf_update_count),
        leaf_delete_count = SUM(os.leaf_delete_count)
    FROM #partition_stats AS ps
    LEFT JOIN #index_details AS id
        ON  id.database_id = ps.database_id
        AND id.object_id = ps.object_id
        AND id.index_id = ps.index_id
        AND id.is_included_column = 0
        AND id.key_ordinal > 0
    LEFT JOIN #operational_stats AS os
        ON  os.database_id = ps.database_id
        AND os.object_id = ps.object_id
        AND os.index_id = ps.index_id
    OUTER APPLY 
    (
        /* Get actual row count per table using MAX from clustered index/heap */
        SELECT 
            actual_rows = 
                MAX
                (
                    CASE 
                        WHEN ps2.index_id IN (0, 1) 
                        THEN ps2.total_rows 
                        ELSE 0 
                    END
                )
        FROM #partition_stats AS ps2 
        WHERE ps2.database_id = ps.database_id
        AND   ps2.object_id = ps.object_id
        AND   ps2.index_id IN (0, 1)
        GROUP BY 
            ps2.object_id
    ) AS d
    GROUP BY 
        ps.database_name,
        ps.database_id
    OPTION(RECOMPILE);

    /* Insert table-level summaries */
    IF @debug = 1
    BEGIN
        RAISERROR('Generating #index_reporting_stats insert, TABLE', 0, 0) WITH NOWAIT;
    END;

    /* No need for a temporary table - we'll use a simpler approach */

    INSERT INTO 
        #index_reporting_stats
    (
        summary_level,
        database_name,
        schema_name,
        table_name,
        index_count,
        total_size_gb,
        total_rows,
        indexes_to_merge,
        unused_indexes,
        unused_size_gb,
        total_reads,
        total_writes,
        user_seeks,
        user_scans,
        user_lookups,
        user_updates,
        range_scan_count,
        singleton_lookup_count,
        row_lock_count,
        row_lock_wait_count,
        row_lock_wait_in_ms,
        page_lock_count,
        page_lock_wait_count,
        page_lock_wait_in_ms,
        page_latch_wait_count,
        page_latch_wait_in_ms,
        page_io_latch_wait_count,
        page_io_latch_wait_in_ms,
        forwarded_fetch_count,
        leaf_insert_count,
        leaf_update_count,
        leaf_delete_count
    )
    SELECT
        summary_level = 'TABLE',
        ps.database_name,
        ps.schema_name,
        ps.table_name,
        index_count = COUNT_BIG(DISTINCT ps.index_id),
        total_size_gb = SUM(ps.total_space_gb),
        /* Use MAX to get the row count from the clustered index or heap */
        total_rows = 
            MAX
            (
                CASE 
                    WHEN ps.index_id IN (0, 1) 
                    THEN ps.total_rows 
                    ELSE 0 
                END
            ),
        indexes_to_merge = 
            (
                SELECT 
                    COUNT_BIG(*) 
                FROM #index_analysis AS ia 
                WHERE ia.action IN (N'MERGE INCLUDES', N'MAKE UNIQUE')
                AND   ia.database_id = ps.database_id 
                AND   ia.schema_id = ps.schema_id
                AND   ia.object_id = ps.object_id
            ),
        /* Use count from analysis to keep consistent with SUMMARY level */
        unused_indexes = 
            (
                SELECT 
                    COUNT_BIG(*) 
                FROM #index_analysis AS ia 
                WHERE ia.action = N'DISABLE' 
                AND   ia.database_id = ps.database_id 
                AND   ia.schema_id = ps.schema_id 
                AND   ia.object_id = ps.object_id
            ),
        unused_size_gb = 
            SUM
            (
                CASE 
                    WHEN id.user_seeks + id.user_scans + id.user_lookups = 0 
                    THEN ps.total_space_gb 
                    ELSE 0 
                END
            ),
        total_reads = SUM(id.user_seeks + id.user_scans + id.user_lookups),
        total_writes = SUM(id.user_updates),
        user_seeks = SUM(id.user_seeks),
        user_scans = SUM(id.user_scans),
        user_lookups = SUM(id.user_lookups),
        user_updates = SUM(id.user_updates),
        range_scan_count = SUM(os.range_scan_count),
        singleton_lookup_count = SUM(os.singleton_lookup_count),
        row_lock_count = SUM(os.row_lock_count),
        row_lock_wait_count = SUM(os.row_lock_wait_count),
        row_lock_wait_in_ms = SUM(os.row_lock_wait_in_ms),
        page_lock_count = SUM(os.page_lock_count),
        page_lock_wait_count = SUM(os.page_lock_wait_count),
        page_lock_wait_in_ms = SUM(os.page_lock_wait_in_ms),
        page_latch_wait_count = SUM(os.page_latch_wait_count),
        page_latch_wait_in_ms = SUM(os.page_latch_wait_in_ms),
        page_io_latch_wait_count = SUM(os.page_io_latch_wait_count),
        page_io_latch_wait_in_ms = SUM(os.page_io_latch_wait_in_ms),
        forwarded_fetch_count = SUM(os.forwarded_fetch_count),
        leaf_insert_count = SUM(os.leaf_insert_count),
        leaf_update_count = SUM(os.leaf_update_count),
        leaf_delete_count = SUM(os.leaf_delete_count)
    FROM #partition_stats AS ps
    LEFT JOIN #index_details AS id
        ON  id.database_id = ps.database_id
        AND id.object_id = ps.object_id
        AND id.index_id = ps.index_id
        AND id.is_included_column = 0
        AND id.key_ordinal > 0
    LEFT JOIN #operational_stats AS os
        ON  os.database_id = ps.database_id
        AND os.object_id = ps.object_id
        AND os.index_id = ps.index_id
    GROUP BY 
        ps.database_name, 
        ps.database_id,
        ps.schema_name,
        ps.schema_id,
        ps.table_name,
        ps.object_id
    OPTION(RECOMPILE);

    /* We're not doing index-level summaries - focusing on database and table level reports */

    /* 
    Return the consolidated results in a single result set
    Results are ordered by:
    1. Summary information (overall stats, savings estimates)
    2. Merge scripts (includes merges and unique conversions) - sort_order 5
    3. Disable scripts (for redundant indexes) - sort_order 20
    4. Constraint scripts (for unique constraints to disable)
    5. Compression scripts (for tables eligible for compression)
    6. Partition-specific compression scripts
    7. Ineligible objects (tables that can't be compressed)
    8. Kept indexes - sort_order 95
    
    Note: Merge target scripts are sorted higher in the results (sort_order 5)
    so that new merged indexes are created before subset indexes are disabled.
    
    Within each category, indexes are sorted by size and impact for better prioritization.
    */
    IF @debug = 1
    BEGIN
        RAISERROR('Generating #index_cleanup_results, RESULTS', 0, 0) WITH NOWAIT;
    END;

    SELECT
        /* First, show the information needed to understand the script */
        script_type = CASE WHEN ir.result_type = 'KEPT' AND ir.script_type IS NULL THEN 'KEPT' ELSE ir.script_type END,
        ir.additional_info,
        /* Then show identifying information for the index */
        ir.database_name,
        ir.schema_name,
        ir.table_name,
        ir.index_name,
        /* Then show relationship information */
        ir.consolidation_rule,
        ir.target_index_name,
        /* Include superseded_by info for winning indexes */
        superseded_info =
            CASE 
                WHEN ia.superseded_by IS NOT NULL 
                THEN ia.superseded_by 
                ELSE ir.superseded_info 
            END,
        /* Add size and usage metrics */
        index_size_gb = 
            CASE 
                WHEN ir.result_type = 'SUMMARY' 
                THEN NULL
                ELSE FORMAT(ir.index_size_gb, 'N4')
            END,
        index_rows = 
            CASE 
                WHEN ir.result_type = 'SUMMARY' 
                THEN NULL
                ELSE FORMAT(ir.index_rows, 'N0')
            END,
        index_reads = 
            CASE 
                WHEN ir.result_type = 'SUMMARY' 
                THEN NULL
                ELSE FORMAT(ir.index_reads, 'N0')
            END,
        index_writes = 
            CASE 
                WHEN ir.result_type = 'SUMMARY' 
                THEN NULL
                ELSE FORMAT(ir.index_writes, 'N0')
            END,
        ia.original_index_definition,
        /* Finally show the actual script */
        ir.script
    FROM 
    (
        /* Use a subquery with ROW_NUMBER to ensure we only get one row per index */
        SELECT *, 
            ROW_NUMBER() OVER(
                PARTITION BY database_name, schema_name, table_name, index_name 
                ORDER BY result_type DESC /* Prefer non-NULL result types */
            ) AS rn
        FROM #index_cleanup_results
    ) AS ir
    LEFT JOIN #index_analysis AS ia
      ON  ir.database_name = ia.database_name
      AND ir.schema_name = ia.schema_name
      AND ir.table_name = ia.table_name
      AND ir.index_name = ia.index_name
    WHERE ir.rn = 1 /* Take only the first row for each index */
    ORDER BY
        ir.sort_order,
        ir.database_name,
        /* Within each sort_order group, prioritize by size and usage */
        CASE
            /* For SUMMARY, keep the original order */
            WHEN ir.result_type = 'SUMMARY' 
            THEN 0
            /* For script categories, order by size and impact */
            ELSE ISNULL(ir.index_size_gb, 0)
        END DESC,
        CASE
            /* For SUMMARY, keep the original order */
            WHEN ir.result_type = 'SUMMARY' 
            THEN 0
            /* For script categories, consider rows as secondary sort */
            ELSE ISNULL(ir.index_rows, 0)
        END DESC,
        /* Then by database, schema, table, index name for consistent ordering */
        ir.schema_name,
        ir.table_name,
        ir.index_name
    OPTION(RECOMPILE);

    /* Insert overall summary information */
    IF @debug = 1
    BEGIN
        RAISERROR('Generating #index_reporting_stats insert, SUMMARY', 0, 0) WITH NOWAIT;
    END;

    INSERT INTO 
        #index_reporting_stats
    WITH
        (TABLOCK)
    (
        summary_level,
        server_uptime_days,
        uptime_warning,
        tables_analyzed,
        index_count,
        indexes_to_disable,
        indexes_to_merge,
        avg_indexes_per_table,
        space_saved_gb,
        compression_min_savings_gb,
        compression_max_savings_gb,
        total_min_savings_gb,
        total_max_savings_gb,
        total_rows
    )
    SELECT 
        summary_level = 'SUMMARY',
        server_uptime_days = @uptime_days,
        uptime_warning = @uptime_warning,
        tables_analyzed = 
            COUNT_BIG(DISTINCT CONCAT(ia.database_id, N'.', ia.schema_id, N'.', ia.object_id)),
        index_count = 
            COUNT_BIG(*),
        indexes_to_disable = 
            SUM
            (
                CASE 
                    WHEN ia.action = N'DISABLE' 
                    THEN 1 
                    ELSE 0 
                END
            ),
        indexes_to_merge = 
            SUM
            (
                CASE 
                    WHEN ia.action IN (N'MERGE INCLUDES', N'MAKE UNIQUE') 
                    THEN 1 
                    ELSE 0 
                END
            ),
        avg_indexes_per_table = 
            COUNT_BIG(*) * 1.0 / 
            NULLIF
            (
                COUNT_BIG(DISTINCT CONCAT(ia.database_id, N'.', ia.schema_id, N'.', ia.object_id)), 
                0
            ),
        /* Space savings from cleanup */
        space_saved_gb = 
            SUM
            (
                CASE 
                    WHEN ia.action IN (N'DISABLE', N'MERGE INCLUDES', N'MAKE UNIQUE') 
                    THEN ps.total_space_gb 
                    ELSE 0 
                END
            ),
        /* Conservative compression savings estimate (20%) */
        compression_min_savings_gb = 
            SUM
            (
                CASE 
                    WHEN (ia.action IS NULL OR ia.action = N'KEEP') 
                    AND   ce.can_compress = 1 
                    THEN ps.total_space_gb * 0.20
                    ELSE 0 
                END
            ),
        /* Optimistic compression savings estimate (60%) */
        compression_max_savings_gb = 
            SUM
            (
                CASE 
                    WHEN (ia.action IS NULL OR ia.action = N'KEEP') 
                    AND   ce.can_compress = 1 
                    THEN ps.total_space_gb * 0.60
                    ELSE 0 
                END
            ),
        /* Total conservative savings */
        total_min_savings_gb = 
            SUM
            (
                CASE 
                    WHEN ia.action IN (N'DISABLE', N'MERGE INCLUDES', N'MAKE UNIQUE') 
                    THEN ps.total_space_gb
                    WHEN (ia.action IS NULL OR ia.action = N'KEEP') 
                    AND   ce.can_compress = 1 
                    THEN ps.total_space_gb * 0.20
                    ELSE 0 
                END
            ),
        /* Total optimistic savings */
        total_max_savings_gb = 
            SUM
            (
                CASE 
                    WHEN ia.action IN (N'DISABLE', N'MERGE INCLUDES', N'MAKE UNIQUE') 
                    THEN ps.total_space_gb
                    WHEN (ia.action IS NULL OR ia.action = N'KEEP') 
                    AND   ce.can_compress = 1 
                    THEN ps.total_space_gb * 0.60
                    ELSE 0 
                END
            ),
        /* Get total rows from database unique tables */
        total_rows = 
        (
            SELECT 
                SUM(t.row_count)
            FROM 
            (
                SELECT 
                    ps_distinct.object_id,
                    row_count = 
                        MAX
                        (
                            CASE 
                                WHEN ps_distinct.index_id IN (0, 1) 
                                THEN ps_distinct.total_rows 
                                ELSE 0 
                            END
                        )
                FROM #partition_stats AS ps_distinct
                WHERE ps_distinct.index_id IN (0, 1)
                GROUP BY 
                    ps_distinct.object_id
            ) AS t
        )
    FROM #index_analysis AS ia
    LEFT JOIN #partition_stats AS ps 
      ON  ia.database_id = ps.database_id
      AND ia.object_id = ps.object_id
      AND ia.index_id = ps.index_id
    LEFT JOIN #compression_eligibility AS ce 
      ON  ia.database_id = ce.database_id
      AND ia.object_id = ce.object_id
      AND ia.index_id = ce.index_id
    OPTION(RECOMPILE);

    /* Return enhanced database impact summaries */
    IF @debug = 1
    BEGIN
        RAISERROR('Generating enhanced summary reports', 0, 0) WITH NOWAIT;
    END;

    /*
    Enhanced Database Impact Summary - Shows total space and performance savings
    */
    SELECT
        summary_type = 'DATABASE IMPACT SUMMARY',
        database_name = irs.database_name,
        total_indexes = FORMAT(irs.index_count, 'N0'),
        indexes_to_disable = FORMAT(irs.indexes_to_disable, 'N0'),
        indexes_to_merge = FORMAT(irs.indexes_to_merge, 'N0'),
        percent_reduction = FORMAT(((irs.indexes_to_disable + irs.indexes_to_merge) / NULLIF(CONVERT(DECIMAL(10,2), irs.index_count), 0)) * 100, 'N1') + '%',
        current_size_gb = FORMAT(irs.total_size_gb, 'N2'),
        space_saved_gb = FORMAT(irs.space_saved_gb, 'N2'),
        size_reduction_percent = FORMAT((irs.space_saved_gb / NULLIF(irs.total_size_gb, 0)) * 100, 'N1') + '%',
        write_operations_saved = FORMAT(irs.user_updates, 'N0'),
        lock_operations_saved = FORMAT(irs.row_lock_count + irs.page_lock_count, 'N0'),
        latch_operations_saved = FORMAT(irs.page_latch_wait_count + irs.page_io_latch_wait_count, 'N0')
    FROM #index_reporting_stats AS irs
    WHERE irs.summary_level = 'DATABASE'
    ORDER BY irs.database_name;

    /*
    Table-Level Impact - Top tables by space savings
    */
    SELECT TOP(10)
        summary_type = 'TOP TABLES BY IMPACT',
        table_name = QUOTENAME(irs.schema_name) + '.' + QUOTENAME(irs.table_name),
        total_indexes = FORMAT(irs.index_count, 'N0'),
        removable_indexes = FORMAT(irs.unused_indexes, 'N0'),
        mergeable_indexes = FORMAT(irs.indexes_to_merge, 'N0'),
        current_size_gb = FORMAT(irs.total_size_gb, 'N2'),
        space_saved_gb = FORMAT(irs.unused_size_gb, 'N2'),
        percent_reduction = FORMAT((irs.unused_size_gb / NULLIF(irs.total_size_gb, 0)) * 100, 'N1') + '%',
        total_write_ops = FORMAT(irs.user_updates, 'N0'),
        write_ops_per_day = FORMAT(irs.user_updates / NULLIF(CONVERT(DECIMAL(10,2), 
                               (SELECT TOP 1 server_uptime_days FROM #index_reporting_stats WHERE summary_level = 'DATABASE')), 0), 'N0')
    FROM #index_reporting_stats AS irs
    WHERE irs.summary_level = 'TABLE'
    ORDER BY irs.unused_size_gb DESC;

    /*
    Before/After Comparison for Database
    */
    SELECT
        comparison_metric = 'BEFORE/AFTER COMPARISON',
        total_indexes_before = FORMAT(irs.index_count, 'N0'),
        total_indexes_after = FORMAT(irs.index_count - (irs.indexes_to_disable + irs.indexes_to_merge), 'N0'),
        index_reduction = FORMAT(((irs.indexes_to_disable + irs.indexes_to_merge) / NULLIF(CONVERT(DECIMAL(10,2), irs.index_count), 0)) * 100, 'N1') + '%',
        size_before_gb = FORMAT(irs.total_size_gb, 'N2'),
        size_after_gb = FORMAT(irs.total_size_gb - irs.space_saved_gb, 'N2'),
        space_saved_gb = FORMAT(irs.space_saved_gb, 'N2'),
        percent_space_saved = FORMAT((irs.space_saved_gb / NULLIF(irs.total_size_gb, 0)) * 100, 'N1') + '%',
        daily_write_ops_saved = FORMAT(irs.user_updates / NULLIF(CONVERT(DECIMAL(10,2), irs.server_uptime_days), 0) * 
                               ((irs.indexes_to_disable + irs.indexes_to_merge) / NULLIF(CONVERT(DECIMAL(10,2), irs.index_count), 0)), 'N0')
    FROM #index_reporting_stats AS irs
    WHERE irs.summary_level = 'DATABASE';

    /* Return streamlined reporting statistics focused on key metrics */
    IF @debug = 1
    BEGIN
        RAISERROR('Generating #index_reporting_stats, REPORT', 0, 0) WITH NOWAIT;
    END;

    SELECT 
        /* Basic identification */
        level =
            CASE 
                WHEN irs.summary_level = 'SUMMARY' THEN '=== OVERALL ANALYSIS ==='
                ELSE irs.summary_level
            END,
        
        /* Server info (for summary) or database name */
        database_info =
            CASE 
                WHEN irs.summary_level = 'SUMMARY' 
                AND  irs.uptime_warning = 1 
                THEN 'WARNING: Server uptime only ' + 
                     CONVERT(varchar(10), irs.server_uptime_days) + 
                     ' days - usage data may be incomplete!'
                WHEN irs.summary_level = 'SUMMARY' 
                THEN 'Server uptime: ' + 
                     CONVERT(varchar(10), irs.server_uptime_days) + 
                     ' days'
                ELSE irs.database_name
            END,
        
        /* Schema and table names (except for summary) */
        irs.schema_name,
        irs.table_name,
        
        /* ===== Section 1: Index Counts ===== */
        /* Tables analyzed (summary only) */
        tables_analyzed =
            CASE
                WHEN irs.summary_level = 'SUMMARY' 
                THEN FORMAT(irs.tables_analyzed, 'N0')
                ELSE NULL
            END,
        
        /* Total indexes */
        total_indexes = FORMAT(irs.index_count, 'N0'),
        
        /* Removable indexes - report consistent values across levels */
        removable_indexes =
            CASE
                WHEN irs.summary_level = 'SUMMARY' 
                THEN FORMAT(irs.indexes_to_disable, 'N0') /* Indexes that will be disabled based on analysis */
                ELSE FORMAT(irs.unused_indexes, 'N0') /* Unused indexes at database/table level */
            END,
        
        /* Show mergeable indexes across all levels */
        mergeable_indexes =
            CASE
                WHEN irs.summary_level = 'SUMMARY' 
                THEN FORMAT(irs.indexes_to_merge, 'N0')
                ELSE FORMAT(irs.indexes_to_merge, 'N0') 
            END,
        
        /* Percent of indexes that can be removed */
        pct_removable =
            CASE
                WHEN irs.summary_level = 'SUMMARY' 
                THEN FORMAT(100.0 * irs.indexes_to_disable / NULLIF(irs.index_count, 0), 'N1') + '%'
                WHEN irs.index_count > 0
                THEN FORMAT(100.0 * irs.unused_indexes / NULLIF(irs.index_count, 0), 'N1') + '%'
                ELSE '0.0%'
            END,
        
        /* ===== Section 2: Size and Space Savings ===== */
        /* Current size in GB */
        current_size_gb = FORMAT(irs.total_size_gb, 'N2'),
        
        /* Size that can be saved through cleanup */
        cleanup_savings_gb =
            CASE
                WHEN irs.summary_level = 'SUMMARY' 
                THEN FORMAT(irs.space_saved_gb, 'N2')
                ELSE FORMAT(irs.unused_size_gb, 'N2')
            END,
        
        /* Potential additional savings */
        potential_savings_gb =
            CASE
                WHEN irs.summary_level = 'SUMMARY' 
                THEN FORMAT(irs.total_min_savings_gb, 'N2') + 
                     ' - ' + 
                     FORMAT(irs.total_max_savings_gb, 'N2')
                ELSE FORMAT(irs.unused_size_gb, 'N2') /* Show at all levels */
            END,
        
        /* ===== Section 3: Table and Usage Statistics ===== */
        /* Row count */
        FORMAT(irs.total_rows, 'N0') AS total_rows,
        
        /* Total reads - combined total and breakdown */
        reads_breakdown =
            CASE 
                WHEN irs.summary_level <> 'SUMMARY' 
                THEN FORMAT(irs.total_reads, 'N0') + 
                     ' (' + 
                     FORMAT(irs.user_seeks, 'N0') + ' seeks, ' +
                     FORMAT(irs.user_scans, 'N0') + ' scans, ' +
                     FORMAT(irs.user_lookups, 'N0') + ' lookups)'
                ELSE NULL
            END,
        
        /* Total writes */
        writes =
            CASE 
                WHEN irs.summary_level <> 'SUMMARY' 
                THEN FORMAT(irs.total_writes, 'N0')
                ELSE NULL
            END,
        
        /* ===== Section 4: Consolidated Performance Metrics ===== */
        /* Total count of lock waits (row + page) */
        lock_wait_count =
            CASE 
                WHEN irs.summary_level <> 'SUMMARY'
                THEN FORMAT(irs.row_lock_wait_count + 
                     irs.page_lock_wait_count, 'N0')
                ELSE NULL
            END,
        
        /* Average lock wait time in ms */
        avg_lock_wait_ms =
            CASE 
                WHEN irs.summary_level <> 'SUMMARY' 
                AND (irs.row_lock_wait_count + irs.page_lock_wait_count) > 0
                THEN FORMAT(1.0 * (irs.row_lock_wait_in_ms + irs.page_lock_wait_in_ms) / 
                     NULLIF(irs.row_lock_wait_count + irs.page_lock_wait_count, 0), 'N2')
                ELSE NULL
            END,
        
        /* Combined latch wait time in ms */
        avg_latch_wait_ms =
            CASE 
                WHEN irs.summary_level <> 'SUMMARY' 
                AND (irs.page_latch_wait_count + irs.page_io_latch_wait_count) > 0
                THEN FORMAT(1.0 * (irs.page_latch_wait_in_ms + irs.page_io_latch_wait_in_ms) / 
                     NULLIF(irs.page_latch_wait_count + irs.page_io_latch_wait_count, 0), 'N2')
                ELSE NULL
            END
    FROM #index_reporting_stats AS irs
    WHERE irs.summary_level IN ('SUMMARY', 'DATABASE', 'TABLE') /* Filter out INDEX level */
    ORDER BY 
        /* Order by level - summary first */
        CASE 
            WHEN irs.summary_level = 'SUMMARY' THEN 0
            WHEN irs.summary_level = 'DATABASE' THEN 1
            WHEN irs.summary_level = 'TABLE' THEN 2
            ELSE 3
        END,
        /* Then by database name */
        irs.database_name,
        /* For tables, sort by potential savings and size */
        CASE 
            WHEN irs.summary_level = 'TABLE' THEN irs.unused_size_gb
            ELSE 0
        END DESC,
        CASE 
            WHEN irs.summary_level = 'TABLE' THEN irs.total_size_gb
            ELSE 0
        END DESC,
        /* Then by schema, table */
        irs.schema_name,
        irs.table_name
    OPTION(RECOMPILE);

END TRY
BEGIN CATCH
    THROW;
END CATCH;
END; /*Final End*/
GO
