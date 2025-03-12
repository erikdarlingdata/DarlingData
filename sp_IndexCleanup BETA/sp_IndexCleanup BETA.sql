/*
EXEC sp_IndexCleanup
    @database_name = 'StackOverflow2013',
    @debug = 1;

EXEC sp_IndexCleanup
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
    SELECT
        @version = '-2147483648',
        @version_date = '17530101';

    SELECT
        warning = N'Read the messages pane carefully!'

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

 If you run this, only use the output to debug and validate result correctness.

 Do not run any of the output scripts, period. Doing so may be harmful.
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
                    WHEN ap.name
                    THEN ap.name
                END,
            valid_inputs =
                CASE
                    ap.name
                    WHEN ap.name
                    THEN ap.name
                END,
            defaults =
                CASE
                    ap.name
                    WHEN ap.name
                    THEN ap.name
                END
        FROM sys.all_parameters AS ap
        INNER JOIN sys.all_objects AS o
          ON ap.object_id = o.object_id
        INNER JOIN sys.types AS t
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
                WHEN CONVERT(int, SERVERPROPERTY('EngineEdition')) IN (3, 5, 8) 
                    OR (CONVERT(int, SERVERPROPERTY('EngineEdition')) = 2 
                        AND CONVERT(int, SUBSTRING(CONVERT(varchar(20), SERVERPROPERTY('ProductVersion')), 1, 2)) >= 13)
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
        WHERE d.name = @database_name;
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
        PRIMARY KEY 
            (database_id, schema_id, object_id, index_id)
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
        PRIMARY KEY CLUSTERED
            (database_id, schema_id, object_id, index_id)
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
        total_space_mb decimal(38, 2) NULL,
        reserved_lob_mb decimal(38, 2) NULL,
        reserved_row_overflow_mb decimal(38, 2) NULL,
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
        superseded_by sysname NULL,
        missing_columns nvarchar(max) NULL,
        action nvarchar(max) NULL,
        target_index_name sysname NULL,
        consolidation_rule varchar(50) NULL,
        index_priority int NULL,
        INDEX c CLUSTERED
            (database_id, schema_name, table_name, index_name)
    );

    CREATE TABLE
        #index_consolidation
    (
        database_id integer NOT NULL,
        database_name sysname NOT NULL,
        schema_id integer NOT NULL,
        schema_name sysname NOT NULL,
        object_id integer NOT NULL,
        table_name sysname NOT NULL,
        index_id integer NOT NULL,
        index_name sysname NOT NULL,
        target_index_name sysname NULL,
        consolidation_rule varchar(50) NULL,
        index_priority integer NULL,
        action varchar(50) NULL,
        PRIMARY KEY (database_id, object_id, index_id)
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
        PRIMARY KEY (database_id, object_id, index_id)
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
    AND   t.type <> N''TF'''

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
        AND ps.index_id IN (0, 1)
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
        AND ius.database_id = @database_id
        GROUP BY 
            ius.object_id
        HAVING 
            SUM(ius.user_seeks + ius.user_scans + ius.user_lookups) >= @min_reads
        AND 
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
    EXEC sys.sp_executesql
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
        FROM #filtered_objects AS fo;
    END;
    
    /* Populate compression eligibility table */
    IF @debug = 1
    BEGIN
        RAISERROR('Populating #compression_eligibility', 0, 0) WITH NOWAIT;
    END;  
    
    INSERT INTO #compression_eligibility
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
    FROM #filtered_objects;
    
    /* If SQL Server edition doesn't support compression, mark all as ineligible */
    IF @can_compress = 0
    BEGIN
        UPDATE #compression_eligibility
        SET 
            can_compress = 0,
            reason = N'SQL Server edition or version does not support compression'
        WHERE can_compress = 1;
    END;
    
    /* Check for sparse columns or incompatible data types */
    IF @can_compress = 1
    BEGIN
        SELECT
            @sql = N'
        SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
        
        UPDATE ce
        SET 
            can_compress = 0,
            reason = ''Table contains sparse columns or incompatible data types''
        FROM #compression_eligibility ce
        WHERE EXISTS 
        (
            SELECT 1/0
            FROM ' + QUOTENAME(@database_name) + N'.sys.columns c
            JOIN ' + QUOTENAME(@database_name) + N'.sys.types t 
              ON c.user_type_id = t.user_type_id
            WHERE c.object_id = ce.object_id
            AND (c.is_sparse = 1 OR t.name IN (N''text'', N''ntext'', N''image''))
        );
        ';
        
        EXEC sys.sp_executesql @sql;
    END;
    
    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#compression_eligibility',
            ce.*
        FROM #compression_eligibility AS ce;
    END;

    IF @debug = 1
    BEGIN
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
        FROM #filtered_objects fo
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
    EXEC sys.sp_executesql
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
        FROM #operational_stats AS os;
    END;

    IF @debug = 1
    BEGIN
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
        FROM #filtered_objects fo
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
    EXEC sys.sp_executesql
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
    END;

    IF @debug = 1
    BEGIN
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
        x.total_space_mb,
        x.reserved_lob_mb,
        x.reserved_row_overflow_mb,
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
            total_space_mb = SUM(a.total_pages) * 8 / 1024.0,
            reserved_lob_mb = SUM(ps.lob_reserved_page_count) * 8. / 1024.,
            reserved_row_overflow_mb = SUM(ps.row_overflow_reserved_page_count) * 8. / 1024.,
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
            FROM #filtered_objects fo
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
        total_space_mb,
        reserved_lob_mb,
        reserved_row_overflow_mb,
        data_compression_desc,
        built_on,
        partition_function_name,
        partition_columns
    )
    EXEC sys.sp_executesql
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
        FROM #partition_stats AS ps;
    END;

    IF @debug = 1
    BEGIN
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
        FROM #index_analysis AS ia;
    END;

    IF @debug = 1
    BEGIN
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
                ) THEN 50 ELSE 0 
            END;  /* Indexes with scans get some priority */


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
        action = 'DISABLE'
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
    AND #index_analysis.index_id <> 1;  /* Don't disable clustered indexes */

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
    FROM #index_analysis ia1
    JOIN #index_analysis ia2 
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
    );

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
            END
    FROM #index_analysis ia1
    JOIN #index_analysis ia2 
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
    );
    
    /* Rule 4: Superset/subset key columns */
    UPDATE 
        ia1
    SET 
        ia1.consolidation_rule = 'Key Subset',
        ia1.target_index_name = ia2.index_name,
        ia1.action = 'DISABLE'  /* The narrower index gets disabled */
    FROM #index_analysis ia1
    JOIN #index_analysis ia2 
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
    );
    
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
    FROM #index_analysis ia1
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
    );


    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#index_analysis after update',
            ia.*
        FROM #index_analysis AS ia;
    END;

    IF @debug = 1
    BEGIN
        RAISERROR('Generating results', 0, 0) WITH NOWAIT;
    END;

/* Generate index merge scripts with compression and drop_existing */
SELECT
    ia.database_name,
    ia.schema_name,
    ia.table_name,
    ia.index_name,
    ia.target_index_name,
    ia.consolidation_rule,
    merge_script =
        N'CREATE ' +
        CASE WHEN ia.action = 'MAKE UNIQUE' THEN N'UNIQUE ' ELSE N'' END +
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
            WHEN ia.included_columns IS NOT NULL AND LEN(ia.included_columns) > 0
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
        CASE WHEN @online = 1 THEN N'ON' ELSE N'OFF' END +
        N', DATA_COMPRESSION = PAGE);'
FROM #index_analysis ia
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
) ps ON
    ia.database_id = ps.database_id AND
    ia.object_id = ps.object_id AND
    ia.index_id = ps.index_id
JOIN #compression_eligibility ce ON
      ia.database_id = ce.database_id
      AND ia.object_id = ce.object_id
      AND ia.index_id = ce.index_id
WHERE ia.action IN ('MERGE INCLUDES', 'MAKE UNIQUE')
AND ce.can_compress = 1
ORDER BY
    ia.table_name,
    ia.index_name;

/* Generate disable scripts for unneeded indexes */
SELECT
    ia.database_name,
    ia.schema_name,
    ia.table_name,
    ia.index_name,
    ia.consolidation_rule,
    disable_script =
        N'ALTER INDEX ' +
        QUOTENAME(ia.index_name) +
        N' ON ' +
        QUOTENAME(ia.database_name) +
        N'.' +
        QUOTENAME(ia.schema_name) +
        N'.' +
        QUOTENAME(ia.table_name) +
        N' DISABLE;'
FROM #index_analysis ia
WHERE ia.action = 'DISABLE'
ORDER BY
    ia.table_name,
    ia.index_name;

/* Generate compression scripts for remaining indexes */
SELECT
    ia.database_name,
    ia.schema_name,
    ia.table_name,
    ia.index_name,
    compression_type = N'All Partitions',
    compression_script =
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
        N', DATA_COMPRESSION = PAGE);'
FROM #index_analysis ia
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
) ps ON
      ia.database_id = ps.database_id
      AND ia.object_id = ps.object_id
      AND ia.index_id = ps.index_id
JOIN #compression_eligibility ce ON
      ia.database_id = ce.database_id
      AND ia.object_id = ce.object_id
      AND ia.index_id = ce.index_id
WHERE 
    /* Indexes that are not being disabled or merged */
    ia.action IS NULL OR ia.action = 'KEEP'
    /* Only indexes eligible for compression */
    AND ce.can_compress = 1
ORDER BY
    ia.table_name,
    ia.index_name;

/* Generate scripts to disable unique constraints that are being replaced by unique indexes */
SELECT
    ia.database_name,
    ia.schema_name,
    ia.table_name,
    ia.index_name,
    constraint_name = id.index_name,
    disable_constraint_script =
        N'ALTER TABLE ' +
        QUOTENAME(ia.database_name) +
        N'.' +
        QUOTENAME(ia.schema_name) +
        N'.' +
        QUOTENAME(ia.table_name) +
        N' NOCHECK CONSTRAINT ' +
        QUOTENAME(id.index_name) +
        N';'
FROM #index_analysis ia
JOIN #index_details id ON
    id.database_id = ia.database_id AND
    id.object_id = ia.object_id AND
    id.is_unique_constraint = 1
WHERE 
    /* Only indexes that are being made unique */
    ia.action = 'MAKE UNIQUE'
    /* Find the constraint that matches the index being made unique */
    AND EXISTS (
        SELECT 1/0
        FROM #index_details id_nc
        WHERE id_nc.database_id = ia.database_id
        AND id_nc.object_id = ia.object_id
        AND id_nc.index_name = ia.index_name
        /* Matching key columns */
        AND NOT EXISTS (
            SELECT id.column_name 
            FROM #index_details id_inner
            WHERE id_inner.database_id = id.database_id
            AND id_inner.object_id = id.object_id
            AND id_inner.index_id = id.index_id
            AND id_inner.is_included_column = 0
            EXCEPT
            SELECT id_nc_inner.column_name
            FROM #index_details id_nc_inner
            WHERE id_nc_inner.database_id = id_nc.database_id
            AND id_nc_inner.object_id = id_nc.object_id
            AND id_nc_inner.index_name = id_nc.index_name
            AND id_nc_inner.is_included_column = 0
        )
    )
ORDER BY
    ia.table_name,
    ia.index_name;

/* Generate per-partition compression scripts for partitioned indexes */
SELECT
    ia.database_name,
    ia.schema_name,
    ia.table_name,
    ia.index_name,
    compression_type = N'Per Partition',
    partition_number = ps.partition_number,
    total_rows = ps.total_rows,
    total_space_mb = ps.total_space_mb,
    compression_script =
        N'ALTER INDEX ' +
        QUOTENAME(ia.index_name) +
        N' ON ' +
        QUOTENAME(ia.database_name) +
        N'.' +
        QUOTENAME(ia.schema_name) +
        N'.' +
        QUOTENAME(ia.table_name) +
        N' REBUILD PARTITION = ' +
        CAST(ps.partition_number AS nvarchar(20)) +
        N' WITH (FILLFACTOR = 100, SORT_IN_TEMPDB = ON, ONLINE = ' +
        CASE WHEN @online = 1 THEN N'ON' ELSE N'OFF' END +
        N', DATA_COMPRESSION = PAGE);'
FROM #index_analysis ia
JOIN #partition_stats ps ON
      ia.database_id = ps.database_id
      AND ia.object_id = ps.object_id
      AND ia.index_id = ps.index_id
JOIN #compression_eligibility ce ON
      ia.database_id = ce.database_id
      AND ia.object_id = ce.object_id
      AND ia.index_id = ce.index_id
WHERE 
    /* Only partitioned indexes */
    ps.partition_function_name IS NOT NULL
    /* Indexes that are not being disabled or merged */
    AND (ia.action IS NULL OR ia.action = 'KEEP')
    /* Only indexes eligible for compression */
    AND ce.can_compress = 1
ORDER BY
    ia.table_name,
    ia.index_name,
    ps.partition_number;

/* Generate index statistics and reporting */
SELECT
    report_title = N'Index Cleanup Summary',
    server_uptime_days = @uptime_days,
    uptime_warning = 
        CASE 
            WHEN @uptime_warning = 1 
            THEN N'Low uptime detected! Index usage data may be incomplete.' 
            ELSE NULL 
        END,
    tables_analyzed = COUNT(DISTINCT CONCAT(ia.database_id, N'.', ia.schema_id, N'.', ia.object_id)),
    total_indexes = COUNT(*),
    indexes_to_disable = SUM(CASE WHEN ia.action = 'DISABLE' THEN 1 ELSE 0 END),
    indexes_to_merge = SUM(CASE WHEN ia.action IN ('MERGE INCLUDES', 'MAKE UNIQUE') THEN 1 ELSE 0 END),
    avg_indexes_per_table = CONVERT(DECIMAL(10,2), COUNT(*) * 1.0 / NULLIF(COUNT(DISTINCT CONCAT(ia.database_id, N'.', ia.schema_id, N'.', ia.object_id)), 0))
FROM #index_analysis ia;

/* Generate estimated space savings report */
SELECT
    report_title = N'Estimated Space Savings',
    space_saved_from_cleanup_mb = 
        SUM(CASE 
            WHEN ia.action IN ('DISABLE', 'MERGE INCLUDES', 'MAKE UNIQUE') 
            THEN ps.total_space_mb 
            ELSE 0 
        END),
    estimated_min_compression_savings_mb = 
        SUM(CASE 
            WHEN (ia.action IS NULL OR ia.action = 'KEEP') AND ce.can_compress = 1 
            THEN ps.total_space_mb * 0.20 /* Conservative estimate - 20% compression ratio */
            ELSE 0 
        END),
    estimated_max_compression_savings_mb = 
        SUM(CASE 
            WHEN (ia.action IS NULL OR ia.action = 'KEEP') AND ce.can_compress = 1 
            THEN ps.total_space_mb * 0.60 /* Optimistic estimate - 60% compression ratio */
            ELSE 0 
        END),
    total_min_estimated_savings_mb = 
        SUM(CASE 
            WHEN ia.action IN ('DISABLE', 'MERGE INCLUDES', 'MAKE UNIQUE') 
            THEN ps.total_space_mb
            WHEN (ia.action IS NULL OR ia.action = 'KEEP') AND ce.can_compress = 1 
            THEN ps.total_space_mb * 0.20
            ELSE 0 
        END),
    total_max_estimated_savings_mb = 
        SUM(CASE 
            WHEN ia.action IN ('DISABLE', 'MERGE INCLUDES', 'MAKE UNIQUE') 
            THEN ps.total_space_mb
            WHEN (ia.action IS NULL OR ia.action = 'KEEP') AND ce.can_compress = 1 
            THEN ps.total_space_mb * 0.60
            ELSE 0 
        END)
FROM #index_analysis ia
LEFT JOIN #partition_stats ps ON 
      ia.database_id = ps.database_id
      AND ia.object_id = ps.object_id
      AND ia.index_id = ps.index_id
LEFT JOIN #compression_eligibility ce ON
      ia.database_id = ce.database_id
      AND ia.object_id = ce.object_id
      AND ia.index_id = ce.index_id;

/* Report on tables that can't be compressed */
SELECT
    ce.database_name,
    ce.schema_name,
    ce.table_name,
    ce.index_name,
    compression_ineligibility_reason = ce.reason
FROM #compression_eligibility ce
WHERE ce.can_compress = 0
ORDER BY
    ce.database_name,
    ce.schema_name,
    ce.table_name,
    ce.index_name;

END TRY
BEGIN CATCH
    THROW;
END CATCH;
END; /*Final End*/
GO
