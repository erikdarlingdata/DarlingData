
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

    DECLARE
        /*general script variables*/
        @sql nvarchar(MAX) = N'',
        @database_id integer = NULL,
        @object_id integer = NULL,
        @full_object_name nvarchar(768) = NULL,
        @final_script nvarchar(MAX) = '',
        /*cursor variables*/
        @c_database_id integer,
        @c_schema_name sysname,
        @c_table_name sysname,
        @c_index_name sysname,
        @c_is_unique bit,
        @c_filter_definition nvarchar(MAX),
        /*print variables*/
        @helper integer = 0,
        @sql_len integer,
        @sql_debug nvarchar(MAX) = N'';

    /*
    Initial checks for object validity
    */
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

    /*
    Temp tables!
    */
    CREATE TABLE
        #operational_stats
    (
        database_id integer NOT NULL,
        object_id integer NOT NULL,
        index_id integer NOT NULL,
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
        PRIMARY KEY CLUSTERED(database_id, object_id, index_id)
    );

    CREATE TABLE
        #index_details
    (
        database_id integer NOT NULL,
        object_id integer NOT NULL,
        index_id integer NOT NULL,
        schema_name sysname NOT NULL,
        table_name sysname NOT NULL,
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
        filter_definition nvarchar(MAX) NULL,
        is_max_length integer NOT NULL,
        user_seeks bigint NOT NULL,
        user_scans bigint NOT NULL,
        user_lookups bigint NOT NULL,
        user_updates bigint NOT NULL,
        last_user_seek datetime NULL,
        last_user_scan datetime NULL,
        last_user_lookup datetime NULL,
        last_user_update datetime NULL,
        PRIMARY KEY CLUSTERED(database_id, object_id, index_id, column_name)
    );

    CREATE TABLE
        #partition_stats
    (
        database_id integer NOT NULL,
        object_id integer NOT NULL,
        index_id integer NOT NULL,
        schema_name sysname NOT NULL,
        table_name sysname NOT NULL,
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
        partition_columns nvarchar(MAX)
        PRIMARY KEY CLUSTERED(database_id, object_id, index_id, partition_id)
    );

    CREATE TABLE 
        #index_analysis
    (
        database_id integer NOT NULL,
        schema_name sysname NOT NULL,
        table_name sysname NOT NULL,
        index_name sysname NOT NULL,
        is_unique bit NULL,
        key_columns nvarchar(MAX) NULL,
        included_columns nvarchar(MAX) NULL,
        filter_definition nvarchar(MAX) NULL,
        is_redundant bit NULL,
        superseded_by sysname NULL,
        missing_columns nvarchar(MAX) NULL,
        action nvarchar(MAX) NULL,
        PRIMARY KEY CLUSTERED (table_name, index_name)
    );

    CREATE TABLE 
        #index_cleanup_report
    (
        database_name sysname NOT NULL,
        table_name sysname NOT NULL,
        index_name sysname NOT NULL,
        action nvarchar(MAX) NULL,
        cleanup_script nvarchar(MAX) NULL,
        original_definition nvarchar(MAX) NULL,
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
        database_name sysname NOT NULL,
        table_name sysname NOT NULL,
        index_name sysname NOT NULL,
        action nvarchar(MAX) NOT NULL,
        details nvarchar(MAX) NULL,
        current_definition nvarchar(MAX) NOT NULL,
        proposed_definition nvarchar(MAX) NULL,
        usage_summary nvarchar(MAX) NULL,
        operational_summary nvarchar(MAX) NULL
    );

    CREATE TABLE
        #final_index_actions
    (
        database_name sysname NOT NULL,
        table_name sysname NOT NULL,
        index_name sysname NOT NULL,
        action nvarchar(MAX) NOT NULL,
        script nvarchar(MAX) NOT NULL
    );

    /*
    Start insert queries
    */
    SELECT
        @sql = N'
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;';

    SELECT
        @sql += N'
    SELECT
        os.database_id,
        os.object_id,
        os.index_id,
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
    WHERE EXISTS
    (
        SELECT
            1/0
        FROM ' + QUOTENAME(@database_name) + N'.sys.tables AS t
        WHERE t.object_id = os.object_id
        AND   t.is_ms_shipped = 0
    )
    AND os.index_id > 1
    GROUP BY
        os.database_id,
        os.object_id,
        os.index_id
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
        object_id,
        index_id,
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

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#operational_stats',
            os.*
        FROM #operational_stats AS os;
    END;

    SELECT
        @sql = N'
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;';

    SELECT
        @sql += N'
    SELECT
        database_id = @database_id,
        t.object_id,
        i.index_id,
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
        us.last_user_update
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
    AND   i.type = 2
    AND   i.is_disabled = 0
    AND   i.is_hypothetical = 0';

    IF @object_id IS NOT NULL
    BEGIN
        SELECT @sql += N'
    AND   t.object_id = @object_id';
    END;

    SELECT
        @sql += N'
    AND   NOT EXISTS
    (
          SELECT
              1/0
          FROM ' + QUOTENAME(@database_name) + N'.sys.objects AS so
          WHERE i.object_id = so.object_id
          AND   so.is_ms_shipped = 0
          AND   so.type = ''TF''
    )
    OPTION(RECOMPILE);';

    IF @debug = 1
    BEGIN
        PRINT @sql;
    END;

    INSERT
        #index_details
    WITH
        (TABLOCK)
    (
        database_id,
        object_id,
        index_id,
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
        last_user_update
    )
    EXEC sys.sp_executesql
        @sql,
      N'@database_id integer,
        @object_id integer',
        @database_id,
        @object_id;

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#index_details',
            *
        FROM #index_details AS id;
    END;

    SELECT
        @sql = N'
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;';

    SELECT
        @sql += N'
    SELECT
        database_id = @database_id,
        x.object_id,
        x.index_id,
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
        WHERE t.type <> ''TF''
        AND   i.type = 2';

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
                  ).value(''.'', ''nvarchar(MAX)''),
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
        object_id,
        index_id,
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

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#partition_stats',
            *
        FROM #partition_stats AS ps;
    END;

    INSERT INTO
        #index_analysis
    WITH
        (TABLOCK)
    (
        database_id,
        schema_name,
        table_name,
        index_name,
        is_unique,
        key_columns,
        included_columns,
        filter_definition
    )
    SELECT
        @database_id,
        id1.schema_name,
        id1.table_name,
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
    GROUP BY
        id1.schema_name,
        id1.table_name,
        id1.index_name,
        id1.is_unique,
        id1.object_id,
        id1.index_id,
        id1.filter_definition
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#partition_stats',
            *
        FROM #partition_stats AS ps;
    END;

    /*Analyze indexes*/
    DECLARE
        @index_cursor CURSOR;

    SET @index_cursor = CURSOR
        LOCAL
        STATIC
        FORWARD_ONLY
        READ_ONLY
    FOR
    SELECT DISTINCT
        ia.database_id,
        ia.schema_name,
        ia.table_name,
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
        @c_schema_name,
        @c_table_name,
        @c_index_name,
        @c_is_unique,
        @c_filter_definition;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        WITH
            IndexColumns AS
        (
            SELECT
                id.database_id,
                id.schema_name,
                id.table_name,
                id.index_name,
                id.column_name,
                id.is_included_column,
                id.key_ordinal
            FROM #index_details id
            WHERE id.database_id = @c_database_id
            AND   id.schema_name = @c_schema_name
            AND   id.table_name = @c_table_name
        ),
            CurrentIndexColumns AS
        (
            SELECT
                ic.*
            FROM IndexColumns AS ic
            WHERE ic.index_name = @c_index_name
        ),
            OtherIndexColumns AS
        (
            SELECT
                ic.*
            FROM IndexColumns AS ic
            WHERE ic.index_name <> @c_index_name
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
                        WHERE NOT EXISTS
                        (
                            SELECT
                                1/0
                            FROM OtherIndexColumns oic
                            WHERE oic.column_name = cic.column_name
                            AND   oic.is_included_column = cic.is_included_column
                            AND
                            (
                                 oic.key_ordinal = cic.key_ordinal
                              OR oic.is_included_column = 1
                            )
                        )
                    )
                    AND ISNULL(ia.filter_definition, '') = ISNULL(@c_filter_definition, '')
                    AND
                    (
                         ia.is_unique = 0
                      OR @c_is_unique = 1
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
                        WHERE NOT EXISTS
                        (
                            SELECT
                                1/0
                            FROM OtherIndexColumns oic
                            WHERE oic.column_name = cic.column_name
                            AND
                            (
                                oic.is_included_column = cic.is_included_column
                             OR oic.is_included_column = 0
                            )
                            AND
                            (
                                oic.key_ordinal = cic.key_ordinal
                             OR oic.is_included_column = 1
                            )
                        )
                    )
                    AND ISNULL(ia.filter_definition, '') = ISNULL(@c_filter_definition, '')
                    AND
                    (
                        ia.is_unique = 0
                     OR @c_is_unique = 1
                    )
                    THEN @c_index_name
                    ELSE ia.superseded_by
                END,
            ia.missing_columns =
                STUFF
                (
                  (
                      SELECT
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
                  ).value('.', 'nvarchar(MAX)'),
                  1,
                  2,
                  ''
                )
        FROM #index_analysis ia
        WHERE ia.database_id = @c_database_id
        AND   ia.schema_name = @c_schema_name
        AND   ia.table_name = @c_table_name
        AND   ia.index_name <> @c_index_name;

        FETCH NEXT
        FROM @index_cursor
        INTO
            @c_database_id,
            @c_schema_name,
            @c_table_name,
            @c_index_name,
            @c_is_unique,
            @c_filter_definition;
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
            table_name = '#index_analysis',
            ia.*
        FROM #index_analysis AS ia;
    END;

    INSERT INTO
        #index_cleanup_report
    WITH
        (TABLOCK)
    (
        database_name,
        table_name,
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
        @database_name,
        ia.table_name,
        ia.index_name,
        ia.action,
        cleanup_script =
            CASE
                WHEN ia.action = N'DROP'
                THEN N'DROP INDEX ' +
                     QUOTENAME(ia.index_name) +
                     N' ON ' +
                     QUOTENAME(ia.table_name) +
                     N';'
                WHEN ia.action LIKE N'MERGE INTO%'
                THEN N'CREATE ' +
                     CASE
                         WHEN ia.is_unique = 1
                         THEN N'UNIQUE '
                         ELSE N''
                     END +
                     N'INDEX ' +
                     QUOTENAME(ia.superseded_by) +
                     N' ON ' +
                     QUOTENAME(ia.table_name) +
                     N'(' +
                     ISNULL(superseding.key_columns, ia.key_columns) +
                     N')' +
                     CASE
                         WHEN ISNULL(superseding.included_columns, ia.included_columns) IS NOT NULL
                         THEN N' INCLUDE (' +
                              ISNULL(superseding.included_columns, ia.included_columns) +
                              CASE
                                  WHEN ia.missing_columns IS NOT NULL
                                  THEN N', ' +
                                  ia.missing_columns
                                  ELSE N''
                              END +
                              N')'
                         ELSE N''
                     END +
                     CASE
                         WHEN ps.partition_function_name IS NOT NULL
                         THEN N' ON ' +
                              QUOTENAME(ps.partition_function_name) +
                              N'(' +
                              ps.partition_columns +
                              N')'
                         ELSE N''
                     END +
                     CASE
                         WHEN ia.filter_definition IS NOT NULL
                         THEN N' WHERE ' +
                              ia.filter_definition
                         ELSE N''
                     END +
                     N' WITH (DROP_EXISTING = ON' +
                     CASE
                         WHEN ps.data_compression_desc <> N'NONE'
                         THEN N', DATA_COMPRESSION = ' +
                              ps.data_compression_desc
                         ELSE N''
                     END +
                     N');' +
                     NCHAR(13) + NCHAR(10) +
                     N'ALTER INDEX ' +
                     QUOTENAME(ia.index_name) +
                     N' ON ' +
                     QUOTENAME(ia.table_name) +
                     N' DISABLE;'
                ELSE N''
            END,
        original_definition =
            N'CREATE ' +
                CASE
                    WHEN ia.is_unique = 1
                    THEN N'UNIQUE '
                    ELSE N''
                END +
                N'INDEX ' +
                QUOTENAME(ia.index_name) +
                N' ON ' +
                QUOTENAME(ia.table_name) +
                N'(' +
                ia.key_columns +
                N')' +
                CASE
                    WHEN ia.included_columns IS NOT NULL
                    THEN N' INCLUDE (' +
                         ia.included_columns +
                         N')'
                    ELSE N''
                END +
                CASE
                    WHEN ps.partition_function_name IS NOT NULL
                    THEN N' ON ' +
                         QUOTENAME(ps.partition_function_name) +
                         N'(' +
                         ps.partition_columns +
                         N')'
                    ELSE N''
                END +
                CASE
                    WHEN ia.filter_definition IS NOT NULL
                    THEN N' WHERE ' +
                         ia.filter_definition
                    ELSE N''
                END,
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
    LEFT JOIN #partition_stats ps
      ON  ia.table_name = ps.table_name
      AND ia.index_name = ps.index_name
    LEFT JOIN #index_details id
      ON  ia.table_name = id.table_name
      AND ia.index_name = id.index_name
    LEFT JOIN #operational_stats os
      ON  id.object_id = os.object_id
      AND id.index_id = os.index_id
    LEFT JOIN #index_analysis superseding
      ON  ia.superseded_by = superseding.index_name
      AND ia.table_name = superseding.table_name;

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#index_cleanup_report',
            icr.*
        FROM #index_cleanup_report AS icr;
    END;

    INSERT INTO
        #index_cleanup_summary
    WITH
        (TABLOCK)
    (
        database_name,
        table_name,
        index_name,
        action,
        details,
        current_definition,
        proposed_definition,
        usage_summary,
        operational_summary
    )
    SELECT
        icr.database_name,
        icr.table_name,
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
            N', Deletes: '   + CONVERT(nvarchar(20), icr.leaf_delete_count)
    FROM #index_cleanup_report AS icr;

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#index_cleanup_summary',
            ics.*
        FROM #index_cleanup_summary AS ics;
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
        ics.operational_summary
    FROM #index_cleanup_summary AS ics
    ORDER BY
        CASE ics.action
             WHEN N'Drop' THEN 1
             WHEN N'Merge' THEN 2
             WHEN N'Keep' THEN 3
             ELSE 999
        END,
        ics.table_name,
        ics.index_name;

    WITH
        IndexActions AS
    (
        SELECT
            icr.database_name,
            icr.table_name,
            icr.index_name,
            icr.action,
            icr.cleanup_script,
            n = ROW_NUMBER() OVER
                (
                    PARTITION BY
                        icr.table_name,
                        icr.index_name
                    ORDER BY
                        CASE
                            WHEN icr.action LIKE N'MERGE INTO%'
                            THEN 1
                            WHEN icr.action = N'DROP'
                            THEN 2
                            ELSE 3
                        END
                )
        FROM #index_cleanup_report icr
    )
    INSERT INTO
        #final_index_actions
    WITH
        (TABLOCK)
    (
        database_name,
        table_name,
        index_name,
        action,
        script
    )
    SELECT
        database_name,
        table_name,
        index_name,
        action,
        CASE
            WHEN action LIKE N'MERGE INTO%'
            THEN cleanup_script
            WHEN action = N'DROP'
            THEN N'ALTER INDEX ' +
                 QUOTENAME(index_name) +
                 N' ON ' +
                 QUOTENAME(table_name) +
                 N' DISABLE;'
            ELSE N'???'
        END AS script
    FROM IndexActions
    WHERE n = 1;

    SELECT
        f.database_name,
        f.table_name,
        f.index_name,
        f.action,
        f.script,
        sort_order =
            CASE action
                WHEN N'MERGE INTO%' THEN 2
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
        table_name,
        index_name,
        sort_order;

    SELECT
        @final_script += f.script + NCHAR(13) + NCHAR(10)
    FROM #final_index_actions AS f
    WHERE f.action LIKE N'MERGE INTO%'
    ORDER BY
        f.table_name,
        f.index_name;

    SELECT
        @final_script += f.script + NCHAR(13) + NCHAR(10)
    FROM #final_index_actions AS f
    WHERE f.action IN
          (
              N'DROP',
              N'MERGE INTO%'
          )
    ORDER BY
        f.table_name,
        f.index_name;

    SELECT
        @final_script +=
            N'ALTER INDEX ' +
            QUOTENAME(i.index_name) +
            N' ON ' +
            QUOTENAME(i.table_name) +
            N' DISABLE;' +
            NCHAR(13) + NCHAR(10)
    FROM #index_cleanup_report AS i
    WHERE i.user_seeks = 0
    AND   i.user_scans = 0
    AND   i.user_lookups = 0
    AND   i.user_updates = 0
    ORDER BY
        i.table_name,
        i.index_name;

    PRINT N'----------------------';
    PRINT N'Final script to review. DO NOT EXECUTE WITHOUT CAREFUL REVIEW.';
    PRINT N'Implementation Script:';
    PRINT N'----------------------';
    SELECT
        @sql_len = LEN(@final_script);

    IF @sql_len < 4000
    BEGIN
        PRINT @sql;
    END
    ELSE
    BEGIN
        WHILE @helper <= @sql_len
        BEGIN
            SELECT
                @sql_debug =
                    SUBSTRING(@final_script, @helper + 1, 2000) + NCHAR(13) + NCHAR(10);

            PRINT @sql_debug;
            SET @helper += 2000;
        END;
    END;

END TRY
BEGIN CATCH
    PRINT N'Error occurred: ' + ERROR_MESSAGE();
END CATCH;
END; /*Final End*/
GO
