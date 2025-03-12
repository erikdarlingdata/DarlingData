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

    PRINT '
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
        @final_script nvarchar(max) = '',
        /*cursor variables*/
        @c_database_id integer,
        @c_database_name sysname,
        @c_schema_id integer,
        @c_schema_name sysname,
        @c_object_id integer,
        @c_table_name sysname,
        @c_index_id integer,
        @c_index_name sysname,
        @c_is_unique bit,
        @c_filter_definition nvarchar(max),
        @index_cursor CURSOR,
        /*print variables*/
        @helper integer = 0,
        @sql_len integer,
        @sql_debug nvarchar(max) = N'',
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

    -- Parameter validation
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
        INDEX c CLUSTERED
            (database_id, schema_name, table_name, index_name)
    );

    CREATE TABLE
        #index_cleanup_report
    (
        database_id integer NOT NULL,
        database_name sysname NOT NULL,
        schema_id integer NOT NULL,
        schema_name sysname NOT NULL,
        object_id integer NOT NULL,
        table_name sysname NOT NULL,
        index_id integer NOT NULL,
        index_name sysname NOT NULL,
        action nvarchar(max) NULL,
        cleanup_script nvarchar(max) NULL,
        original_definition nvarchar(max) NULL,
        /*Usage details*/
        user_seeks bigint NULL,
        user_scans bigint NULL,
        user_lookups bigint NULL,
        user_updates bigint NULL,
        last_user_seek datetime NULL,
        last_user_scan datetime NULL,
        last_user_lookup datetime NULL,
        last_user_update datetime NULL,
        /*Operational stats*/
        range_scan_count bigint NULL,
        singleton_lookup_count bigint NULL,
        leaf_insert_count bigint NULL,
        leaf_update_count bigint NULL,
        leaf_delete_count bigint NULL,
        page_lock_count bigint NULL,
        page_lock_wait_count bigint NULL,
        page_lock_wait_in_ms bigint NULL
    );

    CREATE TABLE
        #index_cleanup_summary
    (
        database_id integer NOT NULL,
        database_name sysname NOT NULL,
        schema_id integer NOT NULL,
        schema_name sysname NOT NULL,
        object_id integer NOT NULL,
        table_name sysname NOT NULL,
        index_id integer NOT NULL,
        index_name sysname NOT NULL,
        action nvarchar(max) NOT NULL,
        details nvarchar(max) NULL,
        current_definition nvarchar(max) NOT NULL,
        proposed_definition nvarchar(max) NULL,
        usage_summary nvarchar(max) NULL,
        operational_summary nvarchar(max) NULL,
        uptime_warning nvarchar(512) NULL
    );

    CREATE TABLE
        #final_index_actions
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
        action nvarchar(max) NOT NULL,
        script nvarchar(max) NOT NULL
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
        RAISERROR('Starting cursor', 0, 0) WITH NOWAIT;
    END;  

    CREATE TABLE #index_supersede_debug
    (
        id integer IDENTITY(1,1) PRIMARY KEY,
        step nvarchar(100),
        current_index sysname,
        other_index sysname,
        current_key_columns nvarchar(max),
        other_key_columns nvarchar(max),
        current_include_columns nvarchar(max),
        other_include_columns nvarchar(max),
        decision nvarchar(100),
        reason nvarchar(max)
    );

    DECLARE 
        @current_key_cols nvarchar(max) = N'',
        @current_include_cols nvarchar(max) = N'';
    

    /*Analyze indexes*/
    SET @index_cursor = CURSOR
        LOCAL
        STATIC
        FORWARD_ONLY
        READ_ONLY
    FOR
    SELECT DISTINCT
        ia.database_id,
        ia.database_name,
        ia.schema_id,
        ia.schema_name,
        ia.object_id,
        ia.table_name,
        ia.index_id,
        ia.index_name,
        ia.is_unique,
        ia.filter_definition
    FROM #index_analysis AS ia
    ORDER BY
        ia.table_name,
        ia.index_name;

    OPEN @index_cursor;

    FETCH NEXT
    FROM @index_cursor
    INTO
        @c_database_id,
        @c_database_name,
        @c_schema_id,
        @c_schema_name,
        @c_object_id,
        @c_table_name,
        @c_index_id,
        @c_index_name,
        @c_is_unique,
        @c_filter_definition;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        
        IF @debug = 1
        BEGIN
            RAISERROR('Performing #index_analysis update', 0, 0) WITH NOWAIT;
        END;          
        
        SELECT 
            @current_key_cols = 
            STUFF
            (
              (
                  SELECT 
                      N', ' + 
                      id.column_name + 
                      CASE 
                          WHEN id.is_descending_key = 1 
                          THEN N' DESC' 
                          ELSE '' 
                      END
                  FROM #index_details AS id
                  WHERE id.database_id = @c_database_id
                  AND   id.object_id = @c_object_id
                  AND   id.index_id = @c_index_id
                  AND   id.is_included_column = 0
                  AND   id.key_ordinal > 0
                  ORDER BY 
                      id.key_ordinal
                  FOR 
                      XML 
                      PATH(''), 
                      TYPE
              ).value('.', 'nvarchar(max)'), 
              1, 
              2, 
              ''
            );

        SELECT 
            @current_include_cols = 
            STUFF
            (
              (
                  SELECT 
                      N', ' + 
                      id.column_name
                  FROM #index_details AS id
                  WHERE id.database_id = @c_database_id
                  AND   id.object_id = @c_object_id
                  AND   id.index_id = @c_index_id
                  AND   id.is_included_column = 1
                  ORDER BY 
                      id.column_name
                  FOR XML 
                      PATH(''), 
                      TYPE
              ).value('.', 'nvarchar(max)'), 
              1, 
              2, 
              ''
            );

        INSERT INTO 
            #index_supersede_debug
        (
            step, 
            current_index, 
            other_index, 
            current_key_columns, 
            other_key_columns,
            current_include_columns, 
            other_include_columns,
            decision, 
            reason
        )
        SELECT
            'Before Update',
            @c_index_name,
            other_indexes.other_index_name,
            @current_key_cols,
            other_indexes.other_key_cols,
            @current_include_cols,
            other_indexes.other_include_cols,
            'Checking',
            'Starting comparison'
        FROM
        (
            -- Get other indexes for the same table
            SELECT
                other_index_name = id2.index_name,
                other_key_cols = 
                STUFF
                (
                  (
                        SELECT
                            N', ' + 
                            id3.column_name + 
                            CASE
                                 WHEN id3.is_descending_key = 1
                                 THEN N' DESC'
                                 ELSE N''
                            END
                        FROM #index_details AS id3
                        WHERE id3.database_id = id2.database_id
                        AND   id3.object_id = id2.object_id
                        AND   id3.index_id = id2.index_id
                        AND   id3.is_included_column = 0
                        AND   id3.key_ordinal > 0
                        ORDER BY
                            id3.key_ordinal
                        FOR XML 
                            PATH(''), 
                            TYPE
                  ).value('.', 'nvarchar(max)'), 
                  1, 
                  2, 
                  ''
                ),
                other_include_cols = 
                STUFF
                (
                  (
                      SELECT
                          N', ' + 
                          id3.column_name
                      FROM #index_details AS id3
                      WHERE id3.database_id = id2.database_id
                      AND   id3.object_id = id2.object_id
                      AND   id3.index_id = id2.index_id
                      AND   id3.is_included_column = 1
                      ORDER BY
                          id3.column_name
                      FOR XML 
                          PATH(''), 
                          TYPE
                  ).value('.', 'nvarchar(max)'), 
                  1, 
                  2, 
                  ''
                )
            FROM #index_details AS id2
            WHERE id2.database_id = @c_database_id
            AND   id2.object_id = @c_object_id
            AND   id2.index_id <> @c_index_id
            AND
              (
                    id2.index_name = N'IX_Users_AccountId_DisplayName'
                OR  id2.index_name = N'u'
              ) -- Focus on problem indexes
            GROUP BY
                id2.database_id,
                id2.object_id,
                id2.index_id,
                id2.index_name
        ) AS other_indexes
        WHERE 
        (
             @c_index_name = N'IX_Users_AccountId_DisplayName'
          OR @c_index_name = N'u'
          OR -- Focus on problem indexes
             other_indexes.other_index_name = N'IX_Users_AccountId_DisplayName'
          OR other_indexes.other_index_name = N'u'
        );


        WITH
            IndexColumns AS
        (
            SELECT
                id.*
            FROM #index_details id
            WHERE id.database_id = @c_database_id
           AND    id.object_id = @c_object_id
           AND    id.is_eligible_for_dedupe = 1
        ),
            CurrentIndexColumns AS
        (
            SELECT
                ic.*
            FROM IndexColumns AS ic
            WHERE ic.index_id = @c_index_id
            AND   ic.is_eligible_for_dedupe = 1
        ),
            OtherIndexColumns AS
        (
            SELECT
                ic.*
            FROM IndexColumns AS ic
            WHERE ic.index_id <> @c_index_id
            AND   ic.is_eligible_for_dedupe = 1
        )
        UPDATE
            ia
        SET
            ia.is_redundant =
                CASE
                    WHEN NOT EXISTS
                    (
                        SELECT
                            1/0
                        FROM CurrentIndexColumns cic
                        WHERE cic.is_included_column = 0  /* Only check key columns */
                        AND NOT EXISTS
                        (
                            SELECT
                                1/0
                            FROM OtherIndexColumns oic
                            WHERE oic.column_name = cic.column_name
                            AND oic.is_included_column = 0  /* Must be in key columns */
                            AND oic.key_ordinal = cic.key_ordinal   /* Check leading edge */
                            AND oic.is_descending_key = cic.is_descending_key
                        )
                    )
                    AND 
                    (
                        /* Check included columns separately since order doesn't matter */
                        NOT EXISTS
                        (
                            SELECT
                                1/0
                            FROM CurrentIndexColumns cic
                            WHERE cic.is_included_column = 1
                            AND NOT EXISTS
                            (
                                SELECT
                                    1/0
                                FROM OtherIndexColumns oic
                                WHERE oic.column_name = cic.column_name
                                AND 
                                (
                                    oic.is_included_column = 1 
                                    OR oic.is_included_column = 0  /* Include cols can be covered by key cols */
                                )
                            )
                        )
                    )
                    AND ISNULL(REPLACE(REPLACE(REPLACE(ia.filter_definition, ' ', ''), '(', ''), ')', ''), '') = 
                        ISNULL(REPLACE(REPLACE(REPLACE(@c_filter_definition, ' ', ''), '(', ''), ')', ''), '')
                    AND
                    (
                        ia.is_unique = 0
                     OR 
                     (
                           ia.is_unique = 1 
                       AND @c_is_unique = 1
                     ) 
                    )
                    THEN 1
                    ELSE 0
                END,
            ia.superseded_by =
                CASE
                    WHEN NOT EXISTS
                    (
                        SELECT
                            1/0
                        FROM CurrentIndexColumns cic
                        WHERE cic.is_included_column = 0  /* Only check key columns */
                        AND NOT EXISTS
                        (
                            SELECT
                                1/0
                            FROM OtherIndexColumns oic
                            WHERE oic.column_name = cic.column_name
                            AND oic.is_included_column = 0  /* Must be in key columns */
                            AND oic.key_ordinal = cic.key_ordinal  /* Check leading edge */
                            AND oic.is_descending_key = cic.is_descending_key
                        )
                    )
                    AND 
                    (
                        /* Check included columns separately since order doesn't matter */
                        NOT EXISTS
                        (
                            SELECT
                                1/0
                            FROM CurrentIndexColumns cic
                            WHERE cic.is_included_column = 1
                            AND NOT EXISTS
                            (
                                SELECT
                                    1/0
                                FROM OtherIndexColumns oic
                                WHERE oic.column_name = cic.column_name
                                AND 
                                (
                                    oic.is_included_column = 1 
                                    OR oic.is_included_column = 0  /* Include cols can be covered by key cols */
                                )
                            )
                        )
                    )
                    AND ISNULL(ia.filter_definition, '') = ISNULL(@c_filter_definition, '')
                    AND
                    (
                        ia.is_unique = 0
                     OR @c_is_unique = 1
                    )
                    AND ia.index_name <> @c_index_name
                    THEN @c_index_name
                    ELSE ia.superseded_by
                END,
            ia.missing_columns =
                STUFF
                (
                  (
                      SELECT DISTINCT
                          N', ' +
                          oic.column_name
                      FROM OtherIndexColumns oic
                      WHERE NOT EXISTS
                      (
                          SELECT
                              1/0
                          FROM CurrentIndexColumns cic
                          WHERE cic.column_name = oic.column_name
                      )
                      FOR XML
                          PATH(''),
                          TYPE
                  ).value('.', 'nvarchar(max)'),
                  1,
                  2,
                  ''
                )
        FROM #index_analysis ia
        WHERE ia.database_id = @c_database_id
        AND   ia.schema_name = @c_schema_name
        AND   ia.table_name = @c_table_name
        AND   ia.index_name <> @c_index_name;

        INSERT INTO
            #index_supersede_debug
        (
            step,
            current_index,
            other_index,
            current_key_columns,
            other_key_columns,
            current_include_columns,
            other_include_columns,
            decision,
            reason
        )
        SELECT
            'After Update',
            @c_index_name,
            ia.index_name,
            @current_key_cols,
            other_key_cols = 
            STUFF
            (
              (
                  SELECT
                      N', ' + 
                      id3.column_name + 
                      CASE
                           WHEN id3.is_descending_key = 1
                           THEN N' DESC'
                           ELSE N''
                      END
                  FROM #index_details AS id3
                  WHERE id3.database_id = ia.database_id
                  AND id3.object_id = ia.object_id
                  AND id3.index_id = ia.index_id
                  AND id3.is_included_column = 0
                  AND id3.key_ordinal > 0
                  ORDER BY
                      id3.key_ordinal
                  FOR 
                      XML 
                      PATH(''), 
                      TYPE
              ).value('.', 'nvarchar(max)'), 
              1, 
              2, 
              ''
            ),
            @current_include_cols,
            other_include_cols = 
            STUFF
            (
              (
                  SELECT
                      N', ' + 
                      id3.column_name
                  FROM #index_details AS id3
                  WHERE id3.database_id = ia.database_id
                  AND   id3.object_id = ia.object_id
                  AND   id3.index_id = ia.index_id
                  AND   id3.is_included_column = 1
                  ORDER BY
                      id3.column_name
                  FOR XML PATH(''), TYPE
              ).value('.', 'nvarchar(max)'), 
              1, 
              2, 
              ''
            ),
            CASE
                 WHEN ia.superseded_by = @c_index_name
                 THEN 'Current supersedes Other'
                 ELSE 'No Change'
            END,
            'superseded_by: ' + 
            ISNULL(ia.superseded_by, 'NULL') + 
            ', is_redundant: ' + 
            CONVERT(varchar(MAX), ia.is_redundant)
        FROM #index_analysis AS ia
        WHERE ia.database_id = @c_database_id
        AND   ia.schema_id = @c_schema_id
        AND   ia.table_name = @c_table_name
        AND   ia.index_name <> @c_index_name
        AND
        (
              ia.index_name = 'IX_Users_AccountId_DisplayName'
          OR  ia.index_name = 'u'
          OR  -- Focus on problem indexes
              @c_index_name = 'IX_Users_AccountId_DisplayName'
          OR  @c_index_name = 'u'
        )
        AND   ia.superseded_by = @c_index_name;

        FETCH NEXT
        FROM @index_cursor
        INTO
            @c_database_id,
            @c_database_name,
            @c_schema_id,
            @c_schema_name,
            @c_object_id,
            @c_table_name,
            @c_index_id,
            @c_index_name,
            @c_is_unique,
            @c_filter_definition;
    END;

    SELECT
        *
    FROM #index_supersede_debug
    ORDER BY
        id;
    
    -- Also add this to see the final state of relevant indexes
    SELECT
        state = 'Final state',
        ia.table_name,
        ia.index_name,
        ia.is_redundant,
        ia.superseded_by,
        ia.action
    FROM #index_analysis AS ia
    WHERE ia.table_name = 'Users'
    AND
    (
        ia.index_name = 'IX_Users_AccountId_DisplayName'
    OR  ia.index_name = 'u'
    )
    ORDER BY
        ia.index_name;

    IF @debug = 1
    BEGIN
        RAISERROR('Performing #index_analysis update after cursor', 0, 0) WITH NOWAIT;
    END; 

    /*Determine actions*/
    UPDATE
        #index_analysis
    SET
        action =
            CASE
                WHEN is_redundant = 1
                THEN N'DROP'
                WHEN superseded_by IS NOT NULL
                AND  missing_columns IS NULL
                THEN N'MERGE INTO ' +
                     superseded_by
                WHEN superseded_by IS NOT NULL
                AND  missing_columns IS NOT NULL
                THEN N'MERGE INTO ' +
                     superseded_by +
                     N' (ADD ' +
                     missing_columns +
                     N')'
                ELSE N'KEEP'
            END;

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#index_analysis after update',
            ia.*
        FROM #index_analysis AS ia;
    END;

    IF @debug = 1
    BEGIN
        RAISERROR('Performing #index_cleanup_report insert', 0, 0) WITH NOWAIT;
    END; 

    INSERT INTO
        #index_cleanup_report
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
        action,
        cleanup_script,
        original_definition,
        user_seeks,
        user_scans,
        user_lookups,
        user_updates,
        last_user_seek,
        last_user_scan,
        last_user_lookup,
        last_user_update,
        range_scan_count,
        singleton_lookup_count,
        leaf_insert_count,
        leaf_update_count,
        leaf_delete_count,
        page_lock_count,
        page_lock_wait_count,
        page_lock_wait_in_ms
    )
    SELECT
        @database_id,
        @database_name,
        ia.schema_id,
        ia.schema_name,
        ia.table_name,
        ia.object_id,
        ia.index_id,
        ia.index_name,
        ia.action,
        cleanup_script =
            CASE
                WHEN ia.action = N'DROP'
                THEN NCHAR(10) +
                     N'DROP INDEX ' +
                     QUOTENAME(ia.index_name) +
                     N' ON ' +
                     QUOTENAME(DB_NAME(ia.database_id)) +
                     N'.' +
                     QUOTENAME(ia.schema_name) +
                     N'.' +
                     QUOTENAME(ia.table_name) +
                     N';'
                WHEN ia.action LIKE N'MERGE INTO%'
                THEN NCHAR(10) +
                     N'CREATE ' +
                     CASE
                         WHEN ia.is_unique = 1
                         THEN N'UNIQUE '
                         ELSE N''
                     END +
                     N'INDEX ' +
                     QUOTENAME(ia.superseded_by) +
                     NCHAR(10) +
                     N'ON ' +
                     QUOTENAME(DB_NAME(ia.database_id)) +
                     N'.' +
                     QUOTENAME(ia.schema_name) +
                     N'.' +
                     QUOTENAME(ia.table_name) +
                     NCHAR(10) +
                     N'    (' +
                     ISNULL(superseding.key_columns, ia.key_columns) +
                     N')' +
                     NCHAR(10) +
                     CASE
                         WHEN 
                         (
                              superseding.included_columns IS NOT NULL 
                           OR ia.included_columns IS NOT NULL
                         )
                         OR   ia.missing_columns IS NOT NULL
                         THEN N' INCLUDE' +
                              NCHAR(10) +
                              N'    (' +
                              -- Combine all INCLUDE columns with proper parsing
                              STUFF
                              (
                                (
                                  SELECT DISTINCT 
                                      N', ' + 
                                      column_value
                                  FROM 
                                  (
                                      -- From superseding index
                                      SELECT DISTINCT
                                          column_value = 
                                              LTRIM(RTRIM(value.c.value('.', 'sysname')))
                                      FROM 
                                      (
                                          SELECT 
                                              Columns =
                                                  CONVERT
                                                  (
                                                      xml, 
                                                      '<c>' + 
                                                      REPLACE
                                                      (
                                                          ISNULL
                                                          (
                                                              superseding.included_columns, 
                                                              ''
                                                          ), 
                                                          ', ', 
                                                          '</c><c>'
                                                      ) + 
                                                          '</c>'
                                                  )
                                      ) t
                                      CROSS APPLY t.Columns.nodes('/c') AS value(c)                                      
                                      
                                      UNION
                                      
                                      -- From current index
                                      SELECT DISTINCT
                                          column_value = 
                                              LTRIM(RTRIM(value.c.value('.', 'sysname')))
                                      FROM 
                                      (
                                          SELECT 
                                              Columns =
                                                  CONVERT
                                                  (
                                                      xml, 
                                                      '<c>' + 
                                                      REPLACE
                                                      (
                                                          ISNULL
                                                          (
                                                              ia.included_columns, 
                                                              ''
                                                          ), 
                                                          ', ', 
                                                          '</c><c>'
                                                      ) + 
                                                      '</c>'
                                                  )
                                      ) t
                                      CROSS APPLY t.Columns.nodes('/c') AS value(c)
                                      
                                      UNION
                                      
                                      -- From missing columns
                                      SELECT DISTINCT
                                          column_value = 
                                              LTRIM(RTRIM(value.c.value('.', 'sysname')))
                                      FROM 
                                      (
                                          SELECT 
                                          Columns = 
                                              CONVERT
                                              (
                                                  xml, 
                                                  '<c>' + 
                                                  REPLACE
                                                  (
                                                      ISNULL
                                                      (
                                                          ia.missing_columns, 
                                                          ''
                                                      ), 
                                                      ', ', 
                                                      '</c><c>'
                                                  ) + '</c>'
                                              )
                                      ) t
                                      CROSS APPLY t.Columns.nodes('/c') AS value(c)
                                  ) AS all_columns
                                  WHERE LEN(column_value) > 0
                                  /*ED TODO*/
                                  FOR 
                                      XML 
                                      PATH(''), 
                                      TYPE
                              ).value('.', 'nvarchar(max)'), 
                              1, 
                              2, 
                              ''
                              ) +
                              N')'
                         ELSE N''
                     END +                     
                     CASE
                         /* Check for partitioning in the superseding index first */
                         WHEN EXISTS 
                         (
                             SELECT 
                                 1/0
                             FROM #partition_stats ps_super
                             WHERE ps_super.table_name = ia.table_name
                             AND   ps_super.index_name = ia.superseded_by
                             AND   ps_super.partition_function_name IS NOT NULL
                         )
                         THEN 
                         (
                             SELECT TOP (1) 
                                 NCHAR(10) +
                                 N' ON ' +
                                 QUOTENAME(ps_super.partition_function_name) +
                                 N'(' +
                                 ps_super.partition_columns +
                                 N')'
                             FROM #partition_stats ps_super
                             WHERE ps_super.table_name = ia.table_name
                             AND   ps_super.index_name = ia.superseded_by
                         )
                         /* Fall back to the current index's partitioning if available */
                         WHEN ps.partition_function_name IS NOT NULL
                         THEN NCHAR(10) +
                              N' ON ' +
                              QUOTENAME(ps.partition_function_name) +
                              N'(' +
                              ps.partition_columns +
                              N')'
                         ELSE N''
                     END +                     
                     CASE
                         WHEN ia.filter_definition IS NOT NULL
                         THEN NCHAR(10) +
                              N' WHERE ' +
                              ia.filter_definition
                         ELSE N''
                     END +
                     NCHAR(10) +
                     N' WITH ' +
                     NCHAR(10) + 
                     N'    (DROP_EXISTING = ON, FILLFACTOR = 100, SORT_IN_TEMPDB = ON, ONLINE = ' +
                     CASE 
                         WHEN @online = 'true' /*Best effort at detecting online index abilities*/
                         THEN N'ON'
                         ELSE N'OFF'
                     END +
                     CASE
                         WHEN ps.data_compression_desc <> N'NONE'
                         THEN N', DATA_COMPRESSION = ' +
                              ps.data_compression_desc
                         ELSE N', DATA_COMPRESSION = PAGE'  /* Add PAGE compression by default for merged indexes */
                     END +
                     N');' +
                     NCHAR(10) +
                     NCHAR(10) +
                     N'    ALTER INDEX ' +
                     QUOTENAME(ia.index_name) +
                     N' ON ' +
                     QUOTENAME(DB_NAME(ia.database_id)) +
                     N'.' +
                     QUOTENAME(ia.schema_name) +
                     N'.' +
                     QUOTENAME(ia.table_name) +
                     N' DISABLE'
                ELSE N''
            END +
            N';',
        original_definition =
            NCHAR(10) +
            N'        -- CREATE ' +
                CASE
                    WHEN ia.is_unique = 1
                    THEN N'UNIQUE '
                    ELSE N''
                END +
                N'INDEX ' +
                QUOTENAME(ia.index_name) +
                NCHAR(10) +                
                N'        -- ON ' +
                QUOTENAME(DB_NAME(ia.database_id)) +
                N'.' +
                QUOTENAME(ia.schema_name) +
                N'.' +
                QUOTENAME(ia.table_name) +
                NCHAR(10) +
                N'        --    (' +
                ia.key_columns +
                N')' +
                CASE
                    WHEN ia.included_columns IS NOT NULL
                    THEN NCHAR(10) +
                         N'        -- INCLUDE' +
                         NCHAR(10) +
                         N'        --    (' +
                         ia.included_columns +
                         N')'
                    ELSE N''
                END +
                CASE
                    WHEN ps.partition_function_name IS NOT NULL
                    THEN NCHAR(10) +
                         N'        -- ON ' +
                         QUOTENAME(ps.partition_function_name) +
                         N'(' +
                         ps.partition_columns +
                         N')'
                    ELSE N''
                END +
                CASE
                    WHEN ia.filter_definition IS NOT NULL
                    THEN NCHAR(10) +
                         N'        -- WHERE ' +
                         ia.filter_definition
                    ELSE N''
                END +
                N';' +
                NCHAR(10),
        id.user_seeks,
        id.user_scans,
        id.user_lookups,
        id.user_updates,
        id.last_user_seek,
        id.last_user_scan,
        id.last_user_lookup,
        id.last_user_update,
        os.range_scan_count,
        os.singleton_lookup_count,
        os.leaf_insert_count,
        os.leaf_update_count,
        os.leaf_delete_count,
        os.page_lock_count,
        os.page_lock_wait_count,
        os.page_lock_wait_in_ms
    FROM #index_analysis ia
    LEFT JOIN #partition_stats AS ps
      ON  ia.table_name = ps.table_name
      AND ia.index_name = ps.index_name
    LEFT JOIN #index_details AS id
      ON  ia.table_name = id.table_name
      AND ia.index_name = id.index_name
    LEFT JOIN #operational_stats AS os
      ON  id.object_id = os.object_id
      AND id.index_id = os.index_id
    LEFT JOIN #index_analysis AS superseding
      ON  ia.superseded_by = superseding.index_name
      AND ia.table_name = superseding.table_name
    OPTION(RECOMPILE);

    IF ROWCOUNT_BIG() = 0 BEGIN IF @debug = 1 BEGIN RAISERROR('No rows inserted into #index_cleanup_report', 0, 0) WITH NOWAIT END; END;

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#index_cleanup_report',
            icr.*
        FROM #index_cleanup_report AS icr;
    END;

    IF @debug = 1
    BEGIN
        RAISERROR('Performing #index_cleanup_summary insert', 0, 0) WITH NOWAIT;
    END; 

    INSERT INTO
        #index_cleanup_summary
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
        action,
        details,
        current_definition,
        proposed_definition,
        usage_summary,
        operational_summary,
        uptime_warning
    )
    SELECT
        icr.database_id,
        icr.database_name,
        icr.schema_id,
        icr.schema_name,
        icr.table_name,
        icr.object_id,
        icr.index_id,
        icr.index_name,
        action =
            CASE
                 WHEN icr.action = N'KEEP'
                 THEN N'Keep'
                 WHEN icr.action = N'DROP'
                 THEN N'Drop'
                 WHEN icr.action LIKE N'MERGE INTO%'
                 THEN N'Merge'
                 ELSE N'???'
            END,
        details =
            CASE
                 WHEN icr.action = N'KEEP'
                 THEN N'No action needed'
                 WHEN icr.action = N'DROP'
                 THEN N'Index is redundant and can be safely dropped'
                 WHEN icr.action LIKE N'MERGE INTO%'
                 THEN N'Merge into index: ' +
                      SUBSTRING
                      (
                          icr.action,
                          12,
                          CHARINDEX(N' ', icr.action, 12) - 12
                      )
                 ELSE N'???'
            END,
        current_definition = icr.original_definition,
        proposed_definition =
            CASE
                 WHEN icr.action LIKE N'MERGE INTO%'
                 THEN icr.cleanup_script
                 ELSE NULL
            END,
        usage_summary =
            N'Seeks: '     + CONVERT(nvarchar(20), icr.user_seeks) +
            N', Scans: '   + CONVERT(nvarchar(20), icr.user_scans) +
            N', Lookups: ' + CONVERT(nvarchar(20), icr.user_lookups) +
            N', Updates: ' + CONVERT(nvarchar(20), icr.user_updates) +
            N', Last used: ' +
            ISNULL
            (
                 CONVERT
                 (
                     nvarchar(30),
                     NULLIF
                     (
                         DATEADD
                         (
                             SECOND,
                             -1,
                             CASE
                                  WHEN icr.last_user_seek > icr.last_user_scan
                                  AND  icr.last_user_seek > icr.last_user_lookup
                                  THEN icr.last_user_seek
                                  WHEN icr.last_user_scan > icr.last_user_lookup
                                  THEN icr.last_user_scan
                                  ELSE icr.last_user_lookup
                             END
                         ),
                         N'1900-01-01'
                     ), 120
                 ),
                 N'Unknown'
            ),
        operational_summary =
            N'Range scans: ' + CONVERT(nvarchar(20), icr.range_scan_count) +
            N', Lookups: '   + CONVERT(nvarchar(20), icr.singleton_lookup_count) +
            N', Inserts: '   + CONVERT(nvarchar(20), icr.leaf_insert_count) +
            N', Updates: '   + CONVERT(nvarchar(20), icr.leaf_update_count) +
            N', Deletes: '   + CONVERT(nvarchar(20), icr.leaf_delete_count),
        uptime_warning = 
            CASE 
                WHEN icr.user_seeks = 0 AND icr.user_scans = 0 AND icr.user_lookups = 0
                THEN
                    CASE
                        WHEN TRY_PARSE(@uptime_days AS integer) < 7
                        THEN N'WARNING: SQL Server has been running for only ' + 
                             @uptime_days + 
                             N' days. Usage statistics may not be reliable.'
                        WHEN TRY_PARSE(@uptime_days AS integer) < 14
                        THEN N'CAUTION: SQL Server has been running for only ' + 
                             @uptime_days + 
                             N' days. Usage statistics may be incomplete.'
                        WHEN TRY_PARSE(@uptime_days AS integer) < 30
                        THEN N'NOTE: SQL Server has been running for only ' + 
                             @uptime_days + 
                             N' days. Consider this when evaluating index usage.'
                        ELSE N'NOTE: SQL Server has been up for ' +
                             @uptime_days +
                             N' days, which makes analysis good, but... Are you patching this thing?'
                    END
                ELSE NULL
            END
    FROM #index_cleanup_report AS icr
    OPTION(RECOMPILE);

    IF ROWCOUNT_BIG() = 0 BEGIN IF @debug = 1 BEGIN RAISERROR('No rows inserted into #index_cleanup_summary', 0, 0) WITH NOWAIT END; END;

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#index_cleanup_summary',
            ics.*
        FROM #index_cleanup_summary AS ics;
    END;

    IF @debug = 1
    BEGIN
        RAISERROR('Going into summary and reports', 0, 0) WITH NOWAIT;
    END; 

    /* Index Cleanup Summary Report */

    IF @debug = 1
    BEGIN
        RAISERROR('Index Cleanup Summary', 0, 0) WITH NOWAIT;
    END; 

    SELECT
        summary_type = 
            'Index Cleanup Summary',
        total_indexes_analyzed = 
            COUNT_BIG(DISTINCT icr.index_name),
        indexes_to_drop = 
            SUM
            (   
                CASE
                    WHEN icr.action = 'DROP'
                    THEN 1
                    ELSE 0
                END
            ),
        indexes_to_merge = 
            SUM
            (   
                CASE
                    WHEN icr.action LIKE 'MERGE INTO%'
                    THEN 1
                    ELSE 0
                END
            ),
        unused_indexes = 
        SUM
        (   
            CASE
                WHEN icr.user_seeks = 0
                AND  icr.user_scans = 0
                AND  icr.user_lookups = 0
                THEN 1
                ELSE 0
            END
        ),
        space_savings_gb = 
        CONVERT
        (   
            decimal(10, 2),
            (
                SELECT
                    SUM(ps_total.space_saved_mb) / 1024.0
                FROM
                (
                    SELECT
                        icr_distinct.index_name,
                        icr_distinct.table_name,
                        space_saved_mb = SUM(ps_inner.total_space_mb)
                    FROM #index_cleanup_report AS icr_distinct
                    JOIN #partition_stats AS ps_inner
                      ON  ps_inner.table_name = icr_distinct.table_name
                      AND ps_inner.index_name = icr_distinct.index_name
                    WHERE icr_distinct.action = 'DROP'
                    OR  icr_distinct.action LIKE 'MERGE INTO%'
                    GROUP BY
                        icr_distinct.index_name,
                        icr_distinct.table_name
                ) AS ps_total
            )
        ),
        write_operations_avoided = 
            SUM
            (   
                CASE
                    WHEN icr.action = 'DROP'
                    OR   icr.action LIKE 'MERGE INTO%'
                    THEN ISNULL(icr.user_updates, 0)
                    ELSE 0
                END
            )
    FROM #index_cleanup_report AS icr
    OPTION (RECOMPILE);

    IF @debug = 1
    BEGIN
        RAISERROR('Top tables by potential space savings', 0, 0) WITH NOWAIT;
    END; 
    
    /* Top tables by potential space savings */
    SELECT TOP (10)
        icr.database_name,
        icr.table_name,
        indexes_affected = 
            COUNT_BIG(DISTINCT icr.index_name),
        space_savings_gb = 
            CONVERT
            (
                decimal(10,2), 
                (
                    SELECT 
                        SUM(ps_total.space_saved_mb) / 1024.0
                    FROM 
                    (
                        SELECT 
                            ps_inner.table_name,
                            space_saved_mb = 
                                SUM(ps_inner.total_space_mb)
                        FROM #partition_stats AS ps_inner
                        JOIN #index_cleanup_report AS icr_inner
                          ON  ps_inner.table_name = icr_inner.table_name
                          AND ps_inner.index_name = icr_inner.index_name
                        WHERE icr_inner.table_name = icr.table_name
                        AND 
                        (
                             icr_inner.action = 'DROP' 
                          OR icr_inner.action LIKE 'MERGE INTO%'
                        )
                        GROUP BY 
                            ps_inner.table_name
                    ) AS ps_total
                )
              ),
        write_operations_avoided = 
            SUM(ISNULL(icr.user_updates, 0))
    FROM #index_cleanup_report AS icr
    WHERE 
    (
         icr.action = 'DROP' 
      OR icr.action LIKE 'MERGE INTO%'
    )
    GROUP BY 
        icr.database_name, 
        icr.table_name
    ORDER BY 
        space_savings_gb DESC
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        RAISERROR('Page Compression Opportunity Summary', 0, 0) WITH NOWAIT;
    END; 

    /* Summary of non-compressed indexes */
    SELECT
        summary_type = 'Page Compression Opportunity Summary',
        candidate_indexes = 
            COUNT_BIG(*),
        total_size_gb = 
            SUM(ps.total_space_mb) / 1024.0,
        estimated_savings_low_gb = 
            (SUM(ps.total_space_mb) * 0.20) / 1024.0, /* Conservative estimate (20%) */
        estimated_savings_typical_gb = 
            (SUM(ps.total_space_mb) * 0.40) / 1024.0, /* Typical estimate (40%) */
        estimated_savings_high_gb = 
            (SUM(ps.total_space_mb) * 0.60) / 1024.0 /* Optimistic estimate (60%) */
    FROM #partition_stats ps
    WHERE ps.data_compression_desc = 'NONE'
    AND NOT EXISTS
    (
        SELECT 
            1/0
        FROM #index_cleanup_report AS icr
        WHERE icr.index_name = ps.index_name
        AND 
        (
             icr.action = 'DROP' 
          OR icr.action LIKE 'MERGE INTO%'
        )
    )
    OPTION(RECOMPILE);
    
    -- Top candidates for page compression

    IF @debug = 1
    BEGIN
        RAISERROR('Top candidates for page compression', 0, 0) WITH NOWAIT;
    END; 

    SELECT TOP (20)
        database_name = 
            @database_name,
        ps.schema_name,
        ps.table_name,
        ps.index_name,
        index_type = 
            CASE 
                WHEN ps.index_id = 1 
                THEN 'CLUSTERED' 
                ELSE 'NONCLUSTERED' 
            END,
        size_gb = 
            SUM(ps.total_space_mb) / 1024.0,
        estimated_savings_low_gb = 
            (SUM(ps.total_space_mb) * 0.20) / 1024.0, -- Conservative (20%)
        estimated_savings_typical_gb = 
            (SUM(ps.total_space_mb) * 0.40) / 1024.0, -- Typical (40%)
        estimated_savings_high_gb = 
            (SUM(ps.total_space_mb) * 0.60) / 1024.0, -- Optimistic (60%)
        rebuild_script = 
            N'ALTER INDEX ' + 
            QUOTENAME(ps.index_name) + 
            N' ON ' + 
            QUOTENAME(ps.schema_name) + 
            N'.' + 
            QUOTENAME(ps.table_name) + 
            N' REBUILD WITH 
    (DROP_EXISTING = ON, FILLFACTOR = 100, SORT_IN_TEMPDB = ON, ONLINE = ' +
            CASE 
                WHEN @online = 'true'
                THEN N'ON'
                ELSE N'OFF'
            END +
            N', DATA_COMPRESSION = PAGE
    );'
    FROM #partition_stats ps
    WHERE ps.data_compression_desc = N'NONE'
    GROUP BY 
        ps.schema_name, 
        ps.table_name, 
        ps.index_name, 
        ps.index_id
    ORDER BY 
        SUM(ps.total_space_mb) DESC
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        RAISERROR('Select from #index_cleanup_summary', 0, 0) WITH NOWAIT;
    END; 

    SELECT
        ics.database_name,
        ics.table_name,
        ics.index_name,
        ics.action,
        ics.details,
        ics.current_definition,
        ics.proposed_definition,
        ics.usage_summary,
        ics.operational_summary,
        ics.uptime_warning
    FROM #index_cleanup_summary AS ics
    ORDER BY
        CASE ics.action
             WHEN N'Drop' THEN 1
             WHEN N'Merge' THEN 2
             WHEN N'Keep' THEN 3
             ELSE 999
        END,
        ics.table_name,
        ics.index_name
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        RAISERROR('Performing #final_index_actions insert', 0, 0) WITH NOWAIT;
    END;     
    
    -- Replace the existing INSERT into #final_index_actions for MERGE operations with this:
    WITH 
        MergeTargets AS 
    (
        -- Get distinct target indexes for merges
        SELECT DISTINCT
            ia.database_id,
            ia.database_name,
            ia.schema_id,
            ia.schema_name,
            ia.object_id,
            ia.table_name,
            ia.index_name,
            target_index = 
                SUBSTRING
                (
                    ia.action, 
                    12, 
                    CHARINDEX
                    (
                        N' ', 
                        ia.action + 
                        N' ', 
                        12
                    ) - 12
                )
        FROM #index_cleanup_report ia
        WHERE ia.action LIKE N'MERGE INTO%'
        AND SUBSTRING
        (
            ia.action, 
            12, 
            CHARINDEX
            (
                N' ', 
                ia.action + 
                N' ', 
                12
            ) - 12
        ) <> ia.index_name
    )
    -- Insert a single CREATE INDEX statement for each target index
    INSERT INTO 
        #final_index_actions
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
        target_index_name,
        action, 
        script
    )
    SELECT DISTINCT
        mt.database_id,
        mt.database_name,
        mt.schema_id,
        mt.schema_name,
        mt.object_id,
        mt.table_name,
        index_id = 
            ISNULL
            (
                (
                    SELECT TOP (1) 
                        ia.index_id
                    FROM #index_analysis ia
                    WHERE ia.database_id = mt.database_id
                    AND   ia.table_name = mt.table_name
                    AND   ia.index_name = mt.target_index
                ), 
                0
            ),
        mt.index_name,
        mt.target_index,
        action =
            N'MERGE CONSOLIDATED',
        script = 
            N'CREATE INDEX ' + 
            QUOTENAME(mt.target_index) +
            N' ON ' + 
            QUOTENAME(mt.database_name) + 
            N'.' + 
            QUOTENAME(mt.schema_name) + 
            N'.' + 
            QUOTENAME(mt.table_name) +
            N' (' +
            -- Get key columns from one of the indexes being merged
            (
                SELECT TOP (1) 
                    ia.key_columns
                FROM #index_analysis ia
                WHERE ia.database_id = mt.database_id
                AND   ia.table_name = mt.table_name
                AND   ia.index_name = mt.target_index
            ) +
            N')' +
            -- Include all distinct columns from all indexes being merged into this target
            CASE
                WHEN EXISTS 
                     (
                         SELECT 
                             1/0
                         FROM #index_cleanup_report icr
                         WHERE icr.database_id = mt.database_id
                         AND   icr.table_name = mt.table_name
                         AND   icr.action LIKE N'MERGE INTO ' + mt.target_index + N'%'
                         AND 
                         (
                             EXISTS 
                             (
                                 SELECT 
                                     1/0
                                 FROM #index_analysis ia
                                 WHERE ia.database_id = icr.database_id
                                 AND   ia.table_name = icr.table_name
                                 AND   ia.index_name = icr.index_name
                                 AND   ia.included_columns IS NOT NULL
                             )
                             OR icr.action LIKE N'%ADD %'
                         )
                    )
                THEN N' INCLUDE (' +
                    STUFF
                    (
                      (
                        SELECT DISTINCT 
                            N', ' + 
                            col
                        FROM 
                        (
                            -- Get included columns from all source indexes
                            SELECT DISTINCT
                                col = LTRIM(RTRIM(value.c.value('.', 'sysname')))
                            FROM #index_cleanup_report icr
                            CROSS APPLY 
                            (
                                SELECT 
                                    ia.included_columns
                                FROM #index_analysis ia
                                WHERE ia.database_id = icr.database_id
                                AND   ia.table_name = icr.table_name
                                AND   ia.index_name = icr.index_name
                            ) src
                            CROSS APPLY 
                            (
                                SELECT 
                                    cols =
                                        CONVERT
                                        (
                                            xml,
                                            '<c>' + 
                                            REPLACE
                                            (
                                                ISNULL
                                                (
                                                    src.included_columns, 
                                                    ''
                                                ), 
                                                ', ', 
                                                '</c><c>') + 
                                                '</c>'
                                        )
                            ) x
                            CROSS APPLY x.cols.nodes('/c') AS value(c)
                            WHERE icr.database_id = mt.database_id
                            AND   icr.table_name = mt.table_name
                            AND   icr.action LIKE N'MERGE INTO ' + mt.target_index + N'%'
                            
                            UNION
                            
                            -- Get missing columns which need to be added
                            SELECT 
                                col = 
                                    LTRIM(RTRIM(value.c.value('.', 'sysname')))
                            FROM #index_cleanup_report icr
                            CROSS APPLY 
                            (
                                SELECT DISTINCT
                                    missing_cols =
                                        REPLACE(REPLACE(
                                        SUBSTRING
                                        (
                                            icr.action,
                                            CHARINDEX('ADD ', icr.action) + 4,
                                            LEN(icr.action)
                                        ),
                                        N')', ''), N'(', '')
                                WHERE icr.action LIKE N'%ADD %'
                            ) mc
                            CROSS APPLY 
                            (
                                SELECT 
                                    cols =
                                        CONVERT
                                        (
                                            xml, 
                                            '<c>' + 
                                            REPLACE
                                            (
                                                ISNULL
                                                (
                                                    mc.missing_cols, 
                                                    ''
                                                ), 
                                                ', ', 
                                                '</c><c>'
                                            ) + '</c>'
                                        )
                            ) x
                            CROSS APPLY x.cols.nodes('/c') AS value(c)
                            WHERE icr.database_id = mt.database_id
                            AND   icr.table_name = mt.table_name
                            AND   icr.action LIKE N'MERGE INTO ' + mt.target_index + N'%'
                            AND   icr.action LIKE N'%ADD %'
                        ) AS all_columns
                        WHERE DATALENGTH(col) > 0
                        FOR 
                            XML 
                            PATH(''), 
                            TYPE
                      ).value('.', 'nvarchar(max)'), 
                      1, 
                      2, 
                      ''
                    ) +
                    N')'
                ELSE N''
            END +
            -- Add partitioning if needed
            CASE
                WHEN EXISTS 
                (
                    SELECT 
                        1/0
                    FROM #partition_stats ps
                    WHERE ps.database_id = mt.database_id
                    AND   ps.table_name = mt.table_name
                    AND   ps.index_name = mt.target_index
                    AND   ps.partition_function_name IS NOT NULL
                )
                THEN 
                (
                    SELECT TOP (1) 
                        N' ON ' + 
                        QUOTENAME(ps.partition_function_name) + 
                        '(' + 
                        ps.partition_columns + 
                        ')'
                    FROM #partition_stats ps
                    WHERE ps.database_id = mt.database_id
                    AND   ps.table_name = mt.table_name
                    AND   ps.index_name = mt.target_index
                    AND   ps.partition_function_name IS NOT NULL
                )
                ELSE N''
            END +
            -- Add filter definition if needed
            CASE
                WHEN EXISTS 
                (
                    SELECT 
                        1/0
                    FROM #index_analysis ia
                    WHERE ia.database_id = mt.database_id
                    AND   ia.table_name = mt.table_name
                    AND   ia.index_name = mt.target_index
                    AND   ia.filter_definition IS NOT NULL
                )
                THEN 
                (
                    SELECT TOP (1) 
                        N' WHERE ' + 
                        ia.filter_definition
                    FROM #index_analysis ia
                    WHERE ia.database_id = mt.database_id
                    AND   ia.table_name = mt.table_name
                    AND   ia.index_name = mt.target_index
                    AND   ia.filter_definition IS NOT NULL
                )
                ELSE N''
            END +
            -- Add WITH options
            N' WITH (DROP_EXISTING = ON, FILLFACTOR = 100, SORT_IN_TEMPDB = ON, ONLINE = ' +
            CASE 
                WHEN @online = 'true'
                THEN N'ON'
                ELSE N'OFF'
            END +
        N', DATA_COMPRESSION = PAGE);'
    FROM MergeTargets AS mt;
    
    -- Then add DISABLE statements for all source indexes
    INSERT INTO 
        #final_index_actions
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
        action, 
        script
    )
    SELECT
        icr.database_id,
        icr.database_name,
        icr.schema_id,
        icr.schema_name,
        icr.object_id,
        icr.table_name,
        icr.index_id,
        icr.index_name,
        action = N'DISABLE MERGED',
        script = 
            N'ALTER INDEX ' + 
            QUOTENAME(icr.index_name) + 
            N' ON ' + 
            QUOTENAME(icr.database_name) + 
            N'.' + 
            QUOTENAME(icr.schema_name) + 
            N'.' + 
            QUOTENAME(icr.table_name) + 
            N' DISABLE;'
    FROM #index_cleanup_report icr
    WHERE icr.action LIKE N'MERGE INTO%';

    IF ROWCOUNT_BIG() = 0 BEGIN IF @debug = 1 BEGIN RAISERROR('No rows inserted into #final_index_actions', 0, 0) WITH NOWAIT END; END;

    IF @debug = 1
    BEGIN

        SELECT
            table_name = '#final_index_actions',
            fia.*
        FROM #final_index_actions AS fia;

        RAISERROR('Select from #final_index_actions', 0, 0) WITH NOWAIT;
    END; 

    SELECT
        f.database_name,
        f.table_name,
        f.index_name,
        f.action,
        f.script,
        sort_order =
            CASE f.action
                WHEN N'MERGE INTO' THEN 2
                WHEN N'DROP' THEN 3
                ELSE 999
            END
    FROM #final_index_actions AS f
    WHERE f.action <> N'KEEP'

    UNION ALL

    SELECT
        r.database_name,
        r.table_name,
        r.index_name,
        action =
            N'DISABLE (Unused)',
        script =
            N'ALTER INDEX ' +
            QUOTENAME(r.index_name) +
            N' ON ' +
            QUOTENAME(r.table_name) +
            N' DISABLE;',
        sort_order = 1
    FROM #index_cleanup_report AS r
    WHERE r.user_seeks = 0
    AND   r.user_scans = 0
    AND   r.user_lookups = 0
    AND   r.user_updates = 0
    ORDER BY
        f.table_name,
        f.index_name,
        sort_order
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        RAISERROR('Generating scripts', 0, 0) WITH NOWAIT;
    END;

    SELECT * FROM #final_index_actions AS fia

    /*Merge into*/
    SELECT
        @final_script += 
        N'
        -- =============================================================================
        -- MERGE INDEX: ' + 
        QUOTENAME(f.index_name) + 
        N' into ' +
        CASE
            WHEN f.action = 'MERGE CONSOLIDATED'
            THEN QUOTENAME(f.target_index_name)
            ELSE 'Unknown Target'
        END +
        N'
        -- Reason: This index overlaps with another index and can be consolidated
        -- Original definition: ' + 
        NCHAR(10) +
        (
            SELECT 
                MAX(ics.current_definition)
            FROM #index_cleanup_summary AS ics 
            WHERE ics.index_name = f.index_name 
            AND   ics.table_name = f.table_name
        ) + 
        N'
        -- Usage: Seeks: ' + 
        CONVERT
        (
            nvarchar(20), 
            ISNULL
            (
                (
                    SELECT 
                        SUM(DISTINCT id.user_seeks)
                    FROM #index_details AS id 
                    WHERE id.table_name = f.table_name 
                    AND   id.index_name = f.index_name
                ), 
                0
            )
        ) + 
        N', Scans: ' + 
        CONVERT
        (
            nvarchar(20), 
            ISNULL
            (
                (
                    SELECT 
                        SUM(DISTINCT id.user_scans)
                    FROM #index_details AS id 
                    WHERE id.table_name = f.table_name 
                    AND   id.index_name = f.index_name
                ), 
                0
            )
        ) +
        N', Lookups: ' + 
        CONVERT
        (
            nvarchar(20), 
            ISNULL
            (
                (
                    SELECT 
                        SUM(DISTINCT id.user_lookups)
                    FROM #index_details AS id 
                    WHERE id.table_name = f.table_name 
                    AND   id.index_name = f.index_name
                ), 
                0
            )
        ) +
        N', Updates: ' + 
        CONVERT
        (
            nvarchar(20), 
            ISNULL
            (
                (
                    SELECT 
                        SUM(DISTINCT id.user_updates)
                    FROM #index_details AS id 
                    WHERE id.table_name = f.table_name 
                    AND   id.index_name = f.index_name
                ), 
                0
            )
        ) +
        N'
        -- Space saved: ' + 
        CONVERT
        (
            nvarchar(20), 
            ISNULL
            (
                (
                    SELECT 
                        CONVERT
                        (
                            decimal(10,2), 
                            SUM(ps.total_space_mb) / 1024.0
                        )
                    FROM #partition_stats AS ps
                    WHERE ps.table_name = f.table_name 
                    AND   ps.index_name = f.index_name
                ), 
                0
            )
        ) + N' GB
        -- =============================================================================
        ' + 
        f.script + 
        NCHAR(10) + 
        NCHAR(10)
    FROM #final_index_actions AS f
    WHERE f.action = N'MERGE CONSOLIDATED'
    ORDER BY
        f.table_name,
        f.index_name;

    /*Disable merged indexes*/
    SELECT
        @final_script += N'
        /*
        -- =============================================================================
        -- DISABLE MERGED INDEX: ' + 
        QUOTENAME(f.index_name) + 
        N'
        -- Reason: This index has been merged into another index
        -- =============================================================================
        */' + 
        NCHAR(10) +
        f.script + 
        NCHAR(10) + 
        NCHAR(10)
    FROM 
    (
        -- Use a derived table with DISTINCT to avoid duplicates
        SELECT DISTINCT
            index_name,
            table_name,
            script
        FROM #final_index_actions
        WHERE action = N'DISABLE MERGED'
    ) AS f
    ORDER BY
        f.table_name,
        f.index_name;
    
    /*Drop indexes*/
    SELECT
        @final_script += N'
        /*
        -- =============================================================================
        -- DROP INDEX: ' + 
        QUOTENAME(f.index_name) + 
        N'
        -- Reason: This index is redundant with other indexes on the same table
        -- Current usage: Seeks: ' + 
        CONVERT
        (
            nvarchar(20), 
            ISNULL
            (
                (
                    SELECT 
                        SUM(DISTINCT id.user_seeks)
                    FROM #index_details AS id 
                    WHERE id.table_name = f.table_name 
                    AND   id.index_name = f.index_name
                ), 
                0
            )
        ) + 
        N', Scans: ' + 
        CONVERT
        (
            nvarchar(20), 
            ISNULL
            (
                (
                    SELECT 
                        SUM(DISTINCT id.user_scans)
                    FROM #index_details AS id 
                    WHERE id.table_name = f.table_name 
                    AND   id.index_name = f.index_name
                ), 
                0
            )
        ) +
        N', Lookups: ' + 
        CONVERT
        (
            nvarchar(20), 
            ISNULL
            (
                (
                    SELECT 
                        SUM(DISTINCT id.user_lookups) 
                    FROM #index_details AS id 
                    WHERE id.table_name = f.table_name 
                    AND   id.index_name = f.index_name
                ), 
                0
            )
        ) +
        N', Updates: ' + 
        CONVERT
        (
            nvarchar(20), 
            ISNULL
            (
                (
                    SELECT 
                        SUM(DISTINCT id.user_updates)
                    FROM #index_details AS id 
                    WHERE id.table_name = f.table_name 
                    AND   id.index_name = f.index_name
                ), 
                0
            )
        ) +
        N'
        -- Last used: ' + 
        ISNULL
        (
            CONVERT
            (
                nvarchar(30), 
                (
                    SELECT 
                        MAX
                        (
                            CASE 
                                WHEN id.last_user_seek > id.last_user_scan 
                                AND  id.last_user_seek > id.last_user_lookup 
                                THEN id.last_user_seek
                                WHEN id.last_user_scan > id.last_user_lookup
                                THEN id.last_user_scan
                                ELSE id.last_user_lookup
                            END
                        )
                    FROM #index_details AS id 
                    WHERE id.table_name = f.table_name 
                    AND   id.index_name = f.index_name
                ), 
                120
            ), 
            'Never'
        ) +
        N'
        -- Space reclaimed: ' + 
        CONVERT
        (
            nvarchar(20), 
            ISNULL
            (
                (
                    SELECT 
                        CONVERT
                        (
                            decimal(10,2), 
                            SUM(ps.total_space_mb) / 1024.0
                        )
                    FROM #partition_stats AS ps
                    WHERE ps.table_name = f.table_name 
                    AND   ps.index_name = f.index_name
                ), 
                0
            )
        ) + N' GB
        -- =============================================================================
        */' + 
        f.script + 
        NCHAR(10) + 
        NCHAR(10)
    FROM #final_index_actions AS f
    WHERE f.action = N'DROP'
    ORDER BY
        f.table_name,
        f.index_name;
       
    /*Unused indexes*/
    SELECT
        @final_script += N'
        /*
        -- =============================================================================
        -- DISABLE UNUSED INDEX: ' + 
        QUOTENAME(i.index_name) + 
        N'
        -- Reason: This index has never been used for reads but has been updated ' + 
        CONVERT
        (
            nvarchar(20), 
            i.user_updates
        ) + 
        N' times
        -- Space reclaimed: ' + 
        CONVERT
        (
            nvarchar(20), 
            ISNULL
            (
                (
                    SELECT 
                        CONVERT
                        (
                            decimal(10,2), 
                            SUM(ps.total_space_mb) / 1024.0
                        )
                    FROM #partition_stats AS ps
                    WHERE ps.table_name = i.table_name 
                    AND   ps.index_name = i.index_name
                ), 
                0
            )
        ) + N' GB
        -- Warning: Verify this index is truly not needed before dropping
        -- =============================================================================
        */' + 
        NCHAR(10) +
        N'ALTER INDEX ' + 
        QUOTENAME(i.index_name) + 
        N' ON ' + 
        QUOTENAME(i.database_name) +
        N'.' +
        QUOTENAME
        (i.schema_name) +
        N'.' +
        QUOTENAME(i.table_name) + 
        N' DISABLE;' +  
        NCHAR(10) +  
        NCHAR(10)
    FROM 
    (
        SELECT DISTINCT
            icr.database_name,
            icr.schema_name,
            icr.table_name,
            icr.index_name,
            icr.user_updates
        FROM #index_cleanup_report AS icr
        WHERE icr.user_seeks = 0
        AND   icr.user_scans = 0
        AND   icr.user_lookups = 0
        AND   icr.user_updates = 0
        AND   icr.action <> N'DROP'
        AND   icr.action NOT LIKE N'MERGE INTO%'
        AND   NOT EXISTS 
        (
            SELECT 
                1/0
            FROM #final_index_actions AS fia
            WHERE fia.index_name = icr.index_name
            AND   fia.table_name = icr.table_name
            AND   fia.action IN (N'MERGE CONSOLIDATED', N'DISABLE MERGED')
        )
    ) AS i
    ORDER BY
        i.table_name,
        i.index_name;

    
    /*Summary*/
    SELECT
        @final_script += N'
    -- =============================================================================
    -- SUMMARY OF CHANGES
    -- Total indexes analyzed: ' + 
        CONVERT
        (
            nvarchar(10), 
            (
                SELECT 
                    COUNT_BIG(*) 
                FROM #index_cleanup_report AS icr
            )
        ) + 
        N'
    -- Indexes recommended for dropping: ' + 
        CONVERT
        (
            nvarchar(10), 
            (
                SELECT 
                    COUNT_BIG(*) 
                FROM #index_cleanup_report AS icr 
                WHERE icr.action = 'DROP'
            )
        ) + 
        N'
    -- Indexes recommended for merging: ' + 
        CONVERT
        (
            nvarchar(10), 
            (
                SELECT 
                    COUNT_BIG(*) 
                FROM #index_cleanup_report AS icr 
                WHERE icr.action LIKE 'MERGE INTO%'
            )
        ) + 
        N'
    -- Unused indexes found: ' + 
        CONVERT
        (
            nvarchar(10), 
            (
                SELECT 
                    COUNT_BIG(*) 
                FROM #index_cleanup_report AS icr
                WHERE icr.user_seeks = 0 
                AND   icr.user_scans = 0 
                AND   icr.user_lookups = 0
            )
        ) + 
        N'
    -- Estimated space savings: ' + 
        CONVERT
        (
            nvarchar(20), 
            ISNULL
            (
                (
                    SELECT 
                        CONVERT
                        (
                            decimal(10,2), 
                            SUM(ps.total_space_mb) / 1024.0
                        )
                    FROM #partition_stats AS ps
                    JOIN #index_cleanup_report AS icr 
                      ON ps.table_name = icr.table_name 
                      AND ps.index_name = icr.index_name
                    WHERE icr.action = 'DROP' 
                    OR    icr.action LIKE 'MERGE INTO%' 
                    OR    
                    (
                          icr.user_seeks = 0 
                      AND icr.user_scans = 0 
                      AND icr.user_lookups = 0
                    )
                ), 
                0
            )
        ) + N' GB
    -- Estimated write operations reduced: ' + 
        CONVERT
        (
            nvarchar(20), 
            ISNULL
            (
                (
                    SELECT 
                        SUM(icr.user_updates)
                    FROM #index_cleanup_report AS icr
                    WHERE icr.action = 'DROP' 
                    OR    icr.action LIKE 'MERGE INTO%' 
                    OR 
                    (
                          icr.user_seeks = 0 
                      AND icr.user_scans = 0 
                      AND icr.user_lookups = 0
                    )
                ), 
                0
            )
        ) + N' operations
    -- =============================================================================
    ';

    SELECT 
        [text()] = 
            N'/* Index Cleanup Script for ' + 
            @database_name +
            N' */',
        [text()] = 
        (
            SELECT 
                NCHAR(10) +
                N'        ----------------------' +
                NCHAR(10) +
                N'        -- Final script to review. DO NOT EXECUTE WITHOUT CAREFUL REVIEW.' +
                NCHAR(10) +
                N'        -- Implementation Script:' +
                NCHAR(10) +
                N'        ----------------------' +
                NCHAR(10) +
                @final_script 
            FOR 
                XML 
                PATH(''), 
                TYPE
        ).value('(./text())[1]', 'nvarchar(max)')
    FOR 
        XML 
        PATH(''), 
        TYPE;
END TRY
BEGIN CATCH
    THROW;
END CATCH;
END; /*Final End*/
GO
