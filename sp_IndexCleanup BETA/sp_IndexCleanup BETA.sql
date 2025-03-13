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
    @debug bit = 'true',
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
        @version = '-2147483648',
        @version_date = '17530101';

    SELECT
        for_insurance_purposes = N'Read the messages pane carefully!'

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
            help = N'without careful analysis and consideration. it may be harmful.'

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
        OPTION(RECOMPILE);;
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
        index_name sysname NOT NULL
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
        PRIMARY KEY CLUSTERED(database_id, object_id, index_id, partition_id)
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
        action nvarchar(max) NULL,
        target_index_name sysname NULL,
        consolidation_rule varchar(512) NULL,
        index_priority int NULL,
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
        index_size_gb decimal(18,4) NULL,  /* Size of the index in GB */
        index_rows bigint NULL,            /* Number of rows in the index */
        index_reads bigint NULL,           /* Total reads (seeks + scans + lookups) */
        index_writes bigint NULL           /* Total writes (updates) */
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
        index_name = i.name
    FROM ' + QUOTENAME(@database_name) + N'.sys.tables AS t
    JOIN ' + QUOTENAME(@database_name) + N'.sys.schemas AS s
      ON t.schema_id = s.schema_id
    JOIN ' + QUOTENAME(@database_name) + N'.sys.indexes AS i
      ON t.object_id = i.object_id
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
      
    IF 
        /* Check SQL Server 2016+ for temporal tables support */
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
        index_name
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

    IF ROWCOUNT_BIG() = 0 BEGIN IF @debug = 1 BEGIN RAISERROR('No rows inserted into #filtered_objects', 0, 0) WITH NOWAIT END; END;

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#filtered_objects',
            fo.*
        FROM #filtered_objects AS fo
        OPTION(RECOMPILE);

        RAISERROR('Generaring #compression_eligibility insert', 0, 0) WITH NOWAIT;
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
        RAISERROR('Updating #compression_eligibility', 0, 0) WITH NOWAIT;
        
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
        index_name = i.name,
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

    IF ROWCOUNT_BIG() = 0 BEGIN IF @debug = 1 BEGIN RAISERROR('No rows inserted into #operational_stats', 0, 0) WITH NOWAIT END; END;

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
        index_name = i.name,
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
    JOIN ' + QUOTENAME(@database_name) + N'.sys.columns AS c
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
        FROM ' + QUOTENAME(@database_name) + 
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

    IF ROWCOUNT_BIG() = 0 BEGIN IF @debug = 1 BEGIN RAISERROR('No rows inserted into #index_details', 0, 0) WITH NOWAIT END; END;

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
        SELECT
            ps.object_id,
            ps.index_id,
            s.schema_id,
            schema_name = s.name,
            table_name = t.name,
            index_name = i.name,
            ps.partition_id,
            p.partition_number,
            total_rows = SUM(ps.row_count),
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
            t.name,
            i.name,
            i.data_space_id,
            s.schema_id,
            s.name,
            p.partition_number,
            p.data_compression_desc,
            ps.object_id,
            ps.index_id,
            ps.partition_id
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
                    FOR XML
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
        PRINT @sql;
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

    IF ROWCOUNT_BIG() = 0 BEGIN IF @debug = 1 BEGIN RAISERROR('No rows inserted into #partition_stats', 0, 0) WITH NOWAIT END; END;

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#partition_stats',
            *
        FROM #partition_stats AS ps
        OPTION(RECOMPILE);;

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
        filter_definition
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
                FOR XML
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
                FOR XML
                    PATH(''),
                    TYPE
              ).value('text()[1]','nvarchar(max)'),
              1,
              2,
              ''
            ),
        id1.filter_definition
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
        id1.filter_definition
    OPTION(RECOMPILE);

    IF ROWCOUNT_BIG() = 0 BEGIN IF @debug = 1 BEGIN RAISERROR('No rows inserted into #index_analysis', 0, 0) WITH NOWAIT END; END;

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#index_analysis',
            ia.*
        FROM #index_analysis AS ia
        OPTION(RECOMPILE);;

        RAISERROR('Starting updates', 0, 0) WITH NOWAIT;
    END;

    /* Calculate index priority scores based on actual columns that exist */
    UPDATE 
        #index_analysis
    SET 
        index_priority = 
            CASE 
                WHEN index_id = 1 
                THEN 1000  /* Clustered indexes get highest priority */
                ELSE 0
            END 
            + 
            CASE 
                WHEN is_unique = 1 
                THEN 500 
                ELSE 0 
            END  /* Unique indexes get high priority */
            + 
            CASE 
                WHEN EXISTS 
                (
                    SELECT 
                        1/0 
                    FROM #index_details id 
                    WHERE id.index_name = #index_analysis.index_name
                    AND   id.table_name = #index_analysis.table_name
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
                    FROM #index_details id 
                    WHERE id.index_name = #index_analysis.index_name
                    AND   id.table_name = #index_analysis.table_name
                    AND   id.user_scans > 0
                ) THEN 100 ELSE 0 
            END
        OPTION(RECOMPILE);;  /* Indexes with scans get some priority */


    /* Rule 1: Identify unused indexes */
    UPDATE 
        #index_analysis
    SET 
        consolidation_rule = 
            CASE 
                WHEN @uptime_warning = 1 
                THEN 'Unused Index (WARNING: Server uptime < 14 days - usage data may be incomplete)'
                ELSE 'Unused Index' 
            END,
        action = N'DISABLE'
    WHERE EXISTS 
    (
        SELECT 
            1/0 
        FROM #index_details id
        WHERE id.database_id = #index_analysis.database_id
        AND   id.object_id = #index_analysis.object_id
        AND   id.index_name = #index_analysis.index_name
        AND   id.user_seeks = 0
        AND   id.user_scans = 0
        AND   id.user_lookups = 0
        AND   id.is_primary_key = 0  /* Don't disable primary keys */
        AND   id.is_unique_constraint = 0  /* Don't disable unique constraints */
        AND   id.is_eligible_for_dedupe = 1 /* Only eligible indexes */
    )
    AND #index_analysis.index_id <> 1
    OPTION(RECOMPILE);  /* Don't disable clustered indexes */

    /* Rule 2: Exact duplicates - matching key columns and includes */
    UPDATE 
        ia1
    SET 
        ia1.consolidation_rule = 'Exact Duplicate',
        ia1.target_index_name = 
            CASE 
                WHEN ia1.index_priority >= ia2.index_priority 
                THEN NULL  /* This index is the keeper */
                ELSE ia2.index_name  /* Other index is the keeper */
            END,
        ia1.action = 
            CASE 
                WHEN ia1.index_priority >= ia2.index_priority 
                THEN 'KEEP'  /* This index is the keeper */
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
    AND   EXISTS 
    (
        SELECT 
            1/0 
        FROM #index_details id1
        WHERE id1.database_id = ia1.database_id
        AND   id1.object_id = ia1.object_id
        AND   id1.index_name = ia1.index_name
        AND   id1.is_eligible_for_dedupe = 1
    )
    AND EXISTS 
    (
        SELECT 
            1/0 
        FROM #index_details id2
        WHERE id2.database_id = ia2.database_id
        AND   id2.object_id = ia2.object_id
        AND   id2.index_name = ia2.index_name
        AND   id2.is_eligible_for_dedupe = 1
    )
    OPTION(RECOMPILE);

    /* Rule 3: Key duplicates - matching key columns, different includes */
    UPDATE 
        ia1
    SET 
        ia1.consolidation_rule = 'Key Duplicate',
        ia1.target_index_name = 
            CASE 
                /* If one is unique and the other isn't, prefer the unique one */
                WHEN ia1.is_unique = 1 AND ia2.is_unique = 0 
                THEN NULL
                WHEN ia1.is_unique = 0 AND ia2.is_unique = 1 
                THEN ia2.index_name
                /* Otherwise use priority */
                WHEN ia1.index_priority >= ia2.index_priority 
                THEN NULL
                ELSE ia2.index_name
            END,
        ia1.action = 
            CASE 
                WHEN (ia1.is_unique = 1 AND ia2.is_unique = 0) OR
                     (ia1.index_priority >= ia2.index_priority AND NOT (ia1.is_unique = 0 AND ia2.is_unique = 1))
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
                THEN 'Supersedes ' + ia2.index_name
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
    AND EXISTS 
    (
        SELECT 
            1/0 
        FROM #index_details id1
        WHERE id1.database_id = ia1.database_id
        AND   id1.object_id = ia1.object_id
        AND   id1.index_name = ia1.index_name
        AND   id1.is_eligible_for_dedupe = 1
    )
    AND EXISTS 
    (
        SELECT 
            1/0 
        FROM #index_details id2
        WHERE id2.database_id = ia2.database_id
        AND   id2.object_id = ia2.object_id
        AND   id2.index_name = ia2.index_name
        AND   id2.is_eligible_for_dedupe = 1
    )
    OPTION(RECOMPILE);
    
    /* Rule 4: Superset/subset key columns */
    UPDATE 
        ia1
    SET 
        ia1.consolidation_rule = 'Key Subset',
        ia1.target_index_name = ia2.index_name,
        ia1.action = 'DISABLE'  /* The narrower index gets disabled */
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
        FROM #index_details id1
        WHERE id1.database_id = ia1.database_id
        AND   id1.object_id = ia1.object_id
        AND   id1.index_name = ia1.index_name
        AND   id1.is_eligible_for_dedupe = 1
    )
    AND EXISTS 
    (
        SELECT 
            1/0 
        FROM #index_details id2
        WHERE id2.database_id = ia2.database_id
        AND   id2.object_id = ia2.object_id
        AND   id2.index_name = ia2.index_name
        AND   id2.is_eligible_for_dedupe = 1
    )
    OPTION(RECOMPILE);
    
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

    /* Rule 5: Unique constraint vs. nonclustered index handling */
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
    AND EXISTS 
    (
        /* Find nonclustered indexes */
        SELECT 
            1/0 
        FROM #index_details id1
        WHERE id1.database_id = ia1.database_id
        AND   id1.object_id = ia1.object_id
        AND   id1.index_name = ia1.index_name
        AND   id1.is_eligible_for_dedupe = 1
    )
    AND EXISTS 
    (
        /* Find unique constraints with matching key columns */
        SELECT 
            1/0
        FROM #index_details id2
        WHERE id2.database_id = ia1.database_id
        AND   id2.object_id = ia1.object_id
        AND   id2.is_unique_constraint = 1
        AND NOT EXISTS 
        (
            /* Verify key columns match between index and unique constraint */
            SELECT 
                id2_inner.column_name 
            FROM #index_details id2_inner
            WHERE id2_inner.database_id = id2.database_id
            AND   id2_inner.object_id = id2.object_id
            AND   id2_inner.index_id = id2.index_id
            AND   id2_inner.is_included_column = 0
            
            EXCEPT
            
            SELECT 
                id1_inner.column_name
            FROM #index_details id1_inner
            WHERE id1_inner.database_id = ia1.database_id
            AND   id1_inner.object_id = ia1.object_id
            AND   id1_inner.index_name = ia1.index_name
            AND   id1_inner.is_included_column = 0
        )
    )
    OPTION(RECOMPILE);
    
    /* Rule 7: Identify indexes with same keys but in different order after first column */
    /* This rule flags indexes that have the same set of key columns but ordered differently */
    /* These need manual review as they may be redundant depending on query patterns */
    UPDATE 
        ia1
    SET 
        ia1.consolidation_rule = 'Same Keys Different Order',
        ia1.action = 'REVIEW',  /* These need manual review */
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
            AND   id1.index_name = ia1.index_name
            AND   id2.index_name = ia2.index_name
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
            AND id1.index_name = ia1.index_name
            AND id1.is_included_column = 0
            AND id1.key_ordinal > 0
            
            EXCEPT
            
            SELECT 
                id2.column_name
            FROM #index_details AS id2
            WHERE id2.database_id = ia2.database_id
            AND   id2.object_id = ia2.object_id
            AND   id2.index_name = ia2.index_name
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
            AND   id1.index_name = ia1.index_name
            AND   id2.index_name = ia2.index_name
        )
    OPTION(RECOMPILE);


    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#index_analysis after update',
            ia.*
        FROM #index_analysis AS ia
        OPTION(RECOMPILE);

        RAISERROR('Generating results', 0, 0) WITH NOWAIT;
    END;


    /* Create a reference to the detailed summary that will appear at the end */
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
              AND candidate.action = 'MERGE INCLUDES'
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
                  AND inner_ia.action = 'MERGE INCLUDES'
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
    WHERE ia.action = 'MERGE INCLUDES'
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

    /* Update winning indexes that don't actually need changes to have action = 'KEEP' */
    UPDATE 
        ia
    SET
        /* Change action to 'KEEP' for indexes that don't need to be modified */
        ia.action = N'KEEP'
    FROM #index_analysis AS ia
    WHERE ia.action = 'MERGE INCLUDES'
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
        AND   ia_subset.action = 'DISABLE'
        AND   ia_subset.target_index_name = ia.index_name
        /* This complex check handles cases where the superset doesn't contain all subset columns */
        AND   CHARINDEX(ISNULL(ia_subset.included_columns, N''), ISNULL(ia.included_columns, N'')) = 0
        AND   ISNULL(ia_subset.included_columns, N'') <> N''
    )
    OPTION(RECOMPILE);

    /* Insert merge scripts for indexes */
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
        index_size_gb,
        index_rows,
        index_reads,
        index_writes
    )
    SELECT
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
                WHEN ia.action = 'MAKE UNIQUE' 
                THEN N'/* This index can replace a unique constraint */
        /* Creating unique index with same keys as constraint */
        CREATE UNIQUE '
                WHEN ia.action = 'MERGE INCLUDES'
                THEN N'/* This index can be merged with another index */
        /* Creating index with combined includes from both */
        CREATE '
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
                AND  ia.action = 'MERGE INCLUDES'
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
            END +
            N' WITH (DROP_EXISTING = ON, FILLFACTOR = 100, SORT_IN_TEMPDB = ON, ONLINE = ' +
            CASE 
                WHEN @online = 1 
                THEN N'ON' 
                ELSE N'OFF' 
            END +
            N', DATA_COMPRESSION = PAGE);',
            /* Additional info about what this script does */
        additional_info =
            CASE
                WHEN ia.action = 'MERGE INCLUDES' 
                THEN N'This index will absorb includes from duplicate indexes'
                WHEN ia.action = 'MAKE UNIQUE' 
                THEN N'This index will replace a unique constraint'
                ELSE NULL
            END,
        /* Add superseded_by information if available */
        ia.superseded_by,
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

    /* Insert disable scripts for unneeded indexes */
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
        index_size_gb,
        index_rows,
        index_reads,
        index_writes
    )
    SELECT
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
      AND id.index_name = ia.index_name
      AND id.is_included_column = 0 /* Get only one row per index */
      AND id.key_ordinal > 0
    WHERE ia.action = 'DISABLE'
    OPTION(RECOMPILE);

    /* Insert compression scripts for remaining indexes */
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
        index_size_gb,
        index_rows,
        index_reads,
        index_writes
    )
    SELECT
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
            CASE WHEN @online = 1 THEN N'ON' ELSE N'OFF' END +
            N', DATA_COMPRESSION = PAGE);',
        N'Compression type: All Partitions',
        superseded_info = NULL, /* No target index for compression scripts */
        ia.superseded_by, /* Include superseded_by info for compression scripts */
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
    ) ps 
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
      AND id.index_name = ia.index_name
      AND id.is_included_column = 0 /* Get only one row per index */
      AND id.key_ordinal > 0
    JOIN #compression_eligibility ce 
      ON  ia.database_id = ce.database_id
      AND ia.object_id = ce.object_id
      AND ia.index_id = ce.index_id
    WHERE 
        /* Indexes that are not being disabled or merged */
        (ia.action IS NULL OR ia.action = 'KEEP')
        /* Only indexes eligible for compression */
    AND  ce.can_compress = 1
    OPTION(RECOMPILE);

    /* Insert disable scripts for unique constraints */
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
        index_size_gb,
        index_rows,
        index_reads,
        index_writes
    )
    SELECT
        result_type = 'CONSTRAINT',
        sort_order = 30,
        ia.database_name,
        ia.schema_name,
        ia.table_name,
        ia.index_name,
        script_type = 'DISABLE CONSTRAINT SCRIPT',
        additional_info = 
            N'Constraint to disable: ' + 
            id.index_name,
        script = 
            N'ALTER TABLE ' +
            QUOTENAME(ia.database_name) +
            N'.' +
            QUOTENAME(ia.schema_name) +
            N'.' +
            QUOTENAME(ia.table_name) +
            N' NOCHECK CONSTRAINT ' +
            QUOTENAME(id.index_name) +
            N';',
        ps.total_space_gb,
        ps.total_rows,
        index_reads =
            (id2.user_seeks + id2.user_scans + id2.user_lookups),
        id2.user_updates
    FROM #index_analysis AS ia
    JOIN #index_details AS id 
      ON  id.database_id = ia.database_id
      AND id.object_id = ia.object_id
      AND id.is_unique_constraint = 1
    LEFT JOIN #index_details AS id2
      ON  id2.database_id = ia.database_id
      AND id2.object_id = ia.object_id
      AND id2.index_name = ia.index_name
      AND id2.is_included_column = 0 /* Get only one row per index */
      AND id2.key_ordinal > 0
    LEFT JOIN #partition_stats AS ps
      ON  ia.database_id = ps.database_id
      AND ia.object_id = ps.object_id
      AND ia.index_id = ps.index_id
    WHERE 
        /* Only indexes that are being made unique */
        ia.action = 'MAKE UNIQUE'
        /* Find the constraint that matches the index being made unique */
        AND EXISTS 
        (
            SELECT 
                1/0
            FROM #index_details id_nc
            WHERE id_nc.database_id = ia.database_id
            AND id_nc.object_id = ia.object_id
            AND id_nc.index_name = ia.index_name
            /* Matching key columns */
            AND NOT EXISTS 
            (
                SELECT 
                    id.column_name 
                FROM #index_details id_inner
                WHERE id_inner.database_id = id.database_id
                AND   id_inner.object_id = id.object_id
                AND   id_inner.index_id = id.index_id
                AND   id_inner.is_included_column = 0
                
                EXCEPT
                
                SELECT 
                    id_nc_inner.column_name
                FROM #index_details id_nc_inner
                WHERE id_nc_inner.database_id = id_nc.database_id
                AND   id_nc_inner.object_id = id_nc.object_id
                AND   id_nc_inner.index_name = id_nc.index_name
                AND   id_nc_inner.is_included_column = 0
            )
        )
    OPTION(RECOMPILE);

    /* Insert per-partition compression scripts */
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
        index_size_gb,
        index_rows,
        index_reads,
        index_writes
    )
    SELECT
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
            N', DATA_COMPRESSION = PAGE);',
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
      AND id.index_name = ia.index_name
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
    AND  (ia.action IS NULL OR ia.action = 'KEEP')
        /* Only indexes eligible for compression */
    AND   ce.can_compress = 1
    OPTION(RECOMPILE);

    /* Insert compression ineligible info */
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
        index_size_gb,
        index_rows,
        index_reads,
        index_writes
    )
    SELECT
        result_type = 'INELIGIBLE',
        sort_order = 90,
        ce.database_name,
        ce.schema_name,
        ce.table_name,
        ce.index_name,
        script_type = 'INELIGIBLE FOR COMPRESSION',
        ce.reason,
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
      AND id.index_name = ce.index_name
      AND id.is_included_column = 0 /* Get only one row per index */
      AND id.key_ordinal > 0
    WHERE ce.can_compress = 0
    OPTION(RECOMPILE);


    /* Insert indexes identified for manual review */
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
        index_size_gb,
        index_rows,
        index_reads,
        index_writes
    )
    SELECT
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
      AND id.index_name = ia.index_name
      AND id.is_included_column = 0 /* Get only one row per index */
      AND id.key_ordinal > 0
    WHERE ia.action = 'REVIEW'
    OPTION(RECOMPILE);


    /* Insert indexes that are being kept (superset indexes and others) */
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
                WHEN ia.action = 'KEEP' 
                THEN 'This index is being kept'
                ELSE NULL
            END,
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
      AND id.index_name = ia.index_name
      AND id.is_included_column = 0 /* Get only one row per index */
      AND id.key_ordinal > 0
    WHERE ia.action = 'KEEP' 
    OR 
    (
          ia.action IS NULL 
      AND ia.consolidation_rule IS NULL
    )
    OPTION(RECOMPILE);

    /* Create a new temp table for detailed reporting statistics */
    CREATE TABLE #index_reporting_stats
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
        leaf_delete_count bigint NULL,
        PRIMARY KEY (summary_level, ISNULL(database_name, ''), ISNULL(schema_name, ''), ISNULL(table_name, ''), ISNULL(index_name, ''))
    );

    /* Insert database-level summaries */
    INSERT INTO #index_reporting_stats
    (
        summary_level,
        database_name,
        index_count,
        total_size_gb,
        total_rows,
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
        summary_level = 'DATABASE',
        ps.database_name,
        index_count = COUNT(DISTINCT CONCAT(ps.object_id, N'.', ps.index_id)),
        total_size_gb = SUM(ps.total_space_gb),
        total_rows = SUM(ps.total_rows),
        unused_indexes = SUM(CASE WHEN id.user_seeks + id.user_scans + id.user_lookups = 0 THEN 1 ELSE 0 END),
        unused_size_gb = SUM(CASE WHEN id.user_seeks + id.user_scans + id.user_lookups = 0 THEN ps.total_space_gb ELSE 0 END),
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
    FROM #partition_stats ps
    LEFT JOIN #index_details id
        ON  id.database_id = ps.database_id
        AND id.object_id = ps.object_id
        AND id.index_id = ps.index_id
        AND id.is_included_column = 0
        AND id.key_ordinal > 0
    LEFT JOIN #operational_stats os
        ON  os.database_id = ps.database_id
        AND os.object_id = ps.object_id
        AND os.index_id = ps.index_id
    GROUP BY ps.database_name
    OPTION(RECOMPILE);

    /* Insert table-level summaries */
    INSERT INTO #index_reporting_stats
    (
        summary_level,
        database_name,
        schema_name,
        table_name,
        index_count,
        total_size_gb,
        total_rows,
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
        index_count = COUNT(DISTINCT ps.index_id),
        total_size_gb = SUM(ps.total_space_gb),
        total_rows = MAX(CASE WHEN ps.index_id IN (0, 1) THEN ps.total_rows ELSE 0 END),
        unused_indexes = SUM(CASE WHEN id.user_seeks + id.user_scans + id.user_lookups = 0 THEN 1 ELSE 0 END),
        unused_size_gb = SUM(CASE WHEN id.user_seeks + id.user_scans + id.user_lookups = 0 THEN ps.total_space_gb ELSE 0 END),
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
    FROM #partition_stats ps
    LEFT JOIN #index_details id
        ON  id.database_id = ps.database_id
        AND id.object_id = ps.object_id
        AND id.index_id = ps.index_id
        AND id.is_included_column = 0
        AND id.key_ordinal > 0
    LEFT JOIN #operational_stats os
        ON  os.database_id = ps.database_id
        AND os.object_id = ps.object_id
        AND os.index_id = ps.index_id
    GROUP BY ps.database_name, ps.schema_name, ps.table_name
    OPTION(RECOMPILE);

    /* Insert index-level summaries */
    INSERT INTO #index_reporting_stats
    (
        summary_level,
        database_name,
        schema_name,
        table_name,
        index_name,
        total_size_gb,
        total_rows,
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
        summary_level = 'INDEX',
        ps.database_name,
        ps.schema_name,
        ps.table_name,
        ps.index_name,
        total_size_gb = SUM(ps.total_space_gb),
        total_rows = SUM(ps.total_rows),
        total_reads = SUM(id.user_seeks + id.user_scans + id.user_lookups),
        total_writes = SUM(id.user_updates),
        user_seeks = MAX(id.user_seeks),
        user_scans = MAX(id.user_scans),
        user_lookups = MAX(id.user_lookups),
        user_updates = MAX(id.user_updates),
        range_scan_count = os.range_scan_count,
        singleton_lookup_count = os.singleton_lookup_count,
        row_lock_count = os.row_lock_count,
        row_lock_wait_count = os.row_lock_wait_count,
        row_lock_wait_in_ms = os.row_lock_wait_in_ms,
        page_lock_count = os.page_lock_count,
        page_lock_wait_count = os.page_lock_wait_count,
        page_lock_wait_in_ms = os.page_lock_wait_in_ms,
        page_latch_wait_count = os.page_latch_wait_count,
        page_latch_wait_in_ms = os.page_latch_wait_in_ms,
        page_io_latch_wait_count = os.page_io_latch_wait_count,
        page_io_latch_wait_in_ms = os.page_io_latch_wait_in_ms,
        forwarded_fetch_count = os.forwarded_fetch_count,
        leaf_insert_count = os.leaf_insert_count,
        leaf_update_count = os.leaf_update_count,
        leaf_delete_count = os.leaf_delete_count
    FROM #partition_stats ps
    LEFT JOIN #index_details id
        ON  id.database_id = ps.database_id
        AND id.object_id = ps.object_id
        AND id.index_name = ps.index_name
        AND id.is_included_column = 0
        AND id.key_ordinal > 0
    LEFT JOIN #operational_stats os
        ON  os.database_id = ps.database_id
        AND os.object_id = ps.object_id
        AND os.index_id = ps.index_id
    GROUP BY 
        ps.database_name, 
        ps.schema_name, 
        ps.table_name, 
        ps.index_name,
        os.range_scan_count,
        os.singleton_lookup_count,
        os.row_lock_count,
        os.row_lock_wait_count,
        os.row_lock_wait_in_ms,
        os.page_lock_count,
        os.page_lock_wait_count,
        os.page_lock_wait_in_ms,
        os.page_latch_wait_count,
        os.page_latch_wait_in_ms,
        os.page_io_latch_wait_count,
        os.page_io_latch_wait_in_ms,
        os.forwarded_fetch_count,
        os.leaf_insert_count,
        os.leaf_update_count,
        os.leaf_delete_count
    OPTION(RECOMPILE);

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

    SELECT
        /* First, show the information needed to understand the script */
        ir.script_type,
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
        /* Finally show the actual script */
        ir.script
    FROM #index_cleanup_results AS ir
    LEFT JOIN #index_analysis AS ia
      ON  ir.database_name = ia.database_name
      AND ir.schema_name = ia.schema_name
      AND ir.table_name = ia.table_name
      AND ir.index_name = ia.index_name
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
    INSERT INTO #index_reporting_stats
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
        total_max_savings_gb
    )
    SELECT 
        summary_level = 'SUMMARY',
        server_uptime_days = @uptime_days,
        uptime_warning = @uptime_warning,
        tables_analyzed = COUNT_BIG(DISTINCT CONCAT(ia.database_id, N'.', ia.schema_id, N'.', ia.object_id)),
        index_count = COUNT_BIG(*),
        indexes_to_disable = SUM(CASE WHEN ia.action = 'DISABLE' THEN 1 ELSE 0 END),
        indexes_to_merge = SUM(CASE WHEN ia.action IN ('MERGE INCLUDES', 'MAKE UNIQUE') THEN 1 ELSE 0 END),
        avg_indexes_per_table = COUNT_BIG(*) * 1.0 / 
            NULLIF(COUNT_BIG(DISTINCT CONCAT(ia.database_id, N'.', ia.schema_id, N'.', ia.object_id)), 0),
        /* Space savings from cleanup */
        space_saved_gb = SUM(CASE 
            WHEN ia.action IN ('DISABLE', 'MERGE INCLUDES', 'MAKE UNIQUE') 
            THEN ps.total_space_gb 
            ELSE 0 
        END),
        /* Conservative compression savings estimate (20%) */
        compression_min_savings_gb = SUM(CASE 
            WHEN (ia.action IS NULL OR ia.action = 'KEEP') 
            AND   ce.can_compress = 1 
            THEN ps.total_space_gb * 0.20
            ELSE 0 
        END),
        /* Optimistic compression savings estimate (60%) */
        compression_max_savings_gb = SUM(CASE 
            WHEN (ia.action IS NULL OR ia.action = 'KEEP') 
            AND   ce.can_compress = 1 
            THEN ps.total_space_gb * 0.60
            ELSE 0 
        END),
        /* Total conservative savings */
        total_min_savings_gb = SUM(CASE 
            WHEN ia.action IN ('DISABLE', 'MERGE INCLUDES', 'MAKE UNIQUE') 
            THEN ps.total_space_gb
            WHEN (ia.action IS NULL OR ia.action = 'KEEP') 
            AND   ce.can_compress = 1 
            THEN ps.total_space_gb * 0.20
            ELSE 0 
        END),
        /* Total optimistic savings */
        total_max_savings_gb = SUM(CASE 
            WHEN ia.action IN ('DISABLE', 'MERGE INCLUDES', 'MAKE UNIQUE') 
            THEN ps.total_space_gb
            WHEN (ia.action IS NULL OR ia.action = 'KEEP') 
            AND   ce.can_compress = 1 
            THEN ps.total_space_gb * 0.60
            ELSE 0 
        END)
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

    /* Return the detailed reporting statistics */
    SELECT 
        CASE 
            WHEN irs.summary_level = 'SUMMARY' 
            THEN '=== OVERALL ANALYSIS ==='
            ELSE irs.summary_level
        END AS summary_level,
        irs.database_name,
        irs.schema_name,
        irs.table_name,
        irs.index_name,
        
        /* Special formatting for summary level */
        CASE
            WHEN irs.summary_level = 'SUMMARY' 
            THEN 'Server uptime: ' + CONVERT(varchar(10), irs.server_uptime_days) + ' days' + 
                CASE 
                    WHEN irs.uptime_warning = 1 
                    THEN ' (WARNING: Low uptime - usage data may be incomplete!)' 
                    ELSE '' 
                END + 
                ' | Tables analyzed: ' + FORMAT(irs.tables_analyzed, 'N0') +
                ' | Total indexes: ' + FORMAT(irs.index_count, 'N0') +
                ' | Indexes to disable: ' + FORMAT(irs.indexes_to_disable, 'N0') +
                ' | Indexes to merge: ' + FORMAT(irs.indexes_to_merge, 'N0') +
                ' | Avg indexes per table: ' + FORMAT(irs.avg_indexes_per_table, 'N2')
            ELSE FORMAT(irs.index_count, 'N0')
        END AS index_count,
        
        /* Size metrics - special handling for summary */
        CASE
            WHEN irs.summary_level = 'SUMMARY' 
            THEN 'Space saved from cleanup: ' + FORMAT(irs.space_saved_gb, 'N4') + ' GB' +
                ' | Compression savings: ' + FORMAT(irs.compression_min_savings_gb, 'N4') + ' - ' + 
                FORMAT(irs.compression_max_savings_gb, 'N4') + ' GB' +
                ' | Total savings: ' + FORMAT(irs.total_min_savings_gb, 'N4') + ' - ' + 
                FORMAT(irs.total_max_savings_gb, 'N4') + ' GB'
            ELSE FORMAT(irs.total_size_gb, 'N4')
        END AS total_size_gb,
        
        /* Skip other metrics for summary level */
        CASE WHEN irs.summary_level = 'SUMMARY' THEN NULL ELSE FORMAT(irs.total_rows, 'N0') END AS total_rows,
        CASE WHEN irs.summary_level = 'SUMMARY' THEN NULL ELSE FORMAT(irs.unused_indexes, 'N0') END AS unused_indexes,
        CASE WHEN irs.summary_level = 'SUMMARY' THEN NULL ELSE FORMAT(irs.unused_size_gb, 'N4') END AS unused_size_gb,
        
        /* Usage metrics */
        CASE WHEN irs.summary_level = 'SUMMARY' THEN NULL ELSE FORMAT(irs.total_reads, 'N0') END AS total_reads,
        CASE WHEN irs.summary_level = 'SUMMARY' THEN NULL ELSE FORMAT(irs.total_writes, 'N0') END AS total_writes,
        CASE WHEN irs.summary_level = 'SUMMARY' THEN NULL ELSE FORMAT(irs.user_seeks, 'N0') END AS user_seeks,
        CASE WHEN irs.summary_level = 'SUMMARY' THEN NULL ELSE FORMAT(irs.user_scans, 'N0') END AS user_scans,
        CASE WHEN irs.summary_level = 'SUMMARY' THEN NULL ELSE FORMAT(irs.user_lookups, 'N0') END AS user_lookups,
        CASE WHEN irs.summary_level = 'SUMMARY' THEN NULL ELSE FORMAT(irs.user_updates, 'N0') END AS user_updates,
        
        /* Operational metrics */
        CASE WHEN irs.summary_level = 'SUMMARY' THEN NULL ELSE FORMAT(irs.range_scan_count, 'N0') END AS range_scan_count,
        CASE WHEN irs.summary_level = 'SUMMARY' THEN NULL ELSE FORMAT(irs.singleton_lookup_count, 'N0') END AS singleton_lookup_count,
        
        /* Lock wait percentages */
        CASE 
            WHEN irs.summary_level = 'SUMMARY' THEN NULL
            WHEN irs.row_lock_count > 0 
            THEN FORMAT(100.0 * irs.row_lock_wait_count / NULLIF(irs.row_lock_count, 0), 'N2') + '%'
            ELSE '0.00%' 
        END AS row_lock_wait_pct,
        
        CASE 
            WHEN irs.summary_level = 'SUMMARY' THEN NULL
            WHEN irs.row_lock_wait_count > 0 
            THEN FORMAT(1.0 * irs.row_lock_wait_in_ms / NULLIF(irs.row_lock_wait_count, 0), 'N2')
            ELSE '0.00' 
        END AS row_lock_wait_ms_avg,
        
        CASE 
            WHEN irs.summary_level = 'SUMMARY' THEN NULL
            WHEN irs.page_lock_count > 0 
            THEN FORMAT(100.0 * irs.page_lock_wait_count / NULLIF(irs.page_lock_count, 0), 'N2') + '%'
            ELSE '0.00%' 
        END AS page_lock_wait_pct,
        
        CASE 
            WHEN irs.summary_level = 'SUMMARY' THEN NULL
            WHEN irs.page_lock_wait_count > 0 
            THEN FORMAT(1.0 * irs.page_lock_wait_in_ms / NULLIF(irs.page_lock_wait_count, 0), 'N2')
            ELSE '0.00' 
        END AS page_lock_wait_ms_avg,
        
        /* Latch wait averages */
        CASE 
            WHEN irs.summary_level = 'SUMMARY' THEN NULL
            WHEN irs.page_latch_wait_count > 0 
            THEN FORMAT(1.0 * irs.page_latch_wait_in_ms / NULLIF(irs.page_latch_wait_count, 0), 'N2')
            ELSE '0.00' 
        END AS page_latch_wait_ms_avg,
        
        CASE 
            WHEN irs.summary_level = 'SUMMARY' THEN NULL
            WHEN irs.page_io_latch_wait_count > 0 
            THEN FORMAT(1.0 * irs.page_io_latch_wait_in_ms / NULLIF(irs.page_io_latch_wait_count, 0), 'N2')
            ELSE '0.00' 
        END AS page_io_latch_wait_ms_avg,
        
        /* DML Counts */
        CASE WHEN irs.summary_level = 'SUMMARY' THEN NULL ELSE FORMAT(irs.forwarded_fetch_count, 'N0') END AS forwarded_fetch_count,
        CASE WHEN irs.summary_level = 'SUMMARY' THEN NULL ELSE FORMAT(irs.leaf_insert_count, 'N0') END AS leaf_inserts,
        CASE WHEN irs.summary_level = 'SUMMARY' THEN NULL ELSE FORMAT(irs.leaf_update_count, 'N0') END AS leaf_updates,
        CASE WHEN irs.summary_level = 'SUMMARY' THEN NULL ELSE FORMAT(irs.leaf_delete_count, 'N0') END AS leaf_deletes
    FROM #index_reporting_stats AS irs
    ORDER BY 
        /* Order by level - put summary first */
        CASE 
            WHEN irs.summary_level = 'SUMMARY' THEN 0
            WHEN irs.summary_level = 'DATABASE' THEN 1
            WHEN irs.summary_level = 'TABLE' THEN 2
            WHEN irs.summary_level = 'INDEX' THEN 3
            ELSE 4
        END,
        /* Then by database name */
        irs.database_name,
        /* For tables and indexes, sort by size */
        CASE 
            WHEN irs.summary_level IN ('SUMMARY', 'DATABASE') THEN 0
            ELSE ISNULL(irs.total_size_gb, 0)
        END DESC,
        /* Then by schema, table, index name */
        irs.schema_name,
        irs.table_name,
        irs.index_name
    OPTION(RECOMPILE);

END TRY
BEGIN CATCH
    THROW;
END CATCH;
END; /*Final End*/
GO
