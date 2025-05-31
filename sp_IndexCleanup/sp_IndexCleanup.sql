SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
SET IMPLICIT_TRANSACTIONS OFF;
SET STATISTICS TIME, IO OFF;
GO


/*
██╗███╗   ██╗██████╗ ███████╗██╗  ██╗
██║████╗  ██║██╔══██╗██╔════╝╚██╗██╔╝
██║██╔██╗ ██║██║  ██║█████╗   ╚███╔╝
██║██║╚██╗██║██║  ██║██╔══╝   ██╔██╗
██║██║ ╚████║██████╔╝███████╗██╔╝ ██╗
╚═╝╚═╝  ╚═══╝╚═════╝ ╚══════╝╚═╝  ╚═╝

 ██████╗██╗     ███████╗ █████╗ ███╗   ██╗██╗   ██╗██████╗
██╔════╝██║     ██╔════╝██╔══██╗████╗  ██║██║   ██║██╔══██╗
██║     ██║     █████╗  ███████║██╔██╗ ██║██║   ██║██████╔╝
██║     ██║     ██╔══╝  ██╔══██║██║╚██╗██║██║   ██║██╔═══╝
╚██████╗███████╗███████╗██║  ██║██║ ╚████║╚██████╔╝██║
 ╚═════╝╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝


Copyright 2025 Darling Data, LLC
https://www.erikdarling.com/

For usage and licensing details, run:
EXECUTE sp_IndexCleanup
    @help = 1;

For working through errors:
EXECUTE sp_IndexCleanup
    @debug = 1;

For support, head over to GitHub:
https://code.erikdarling.com

*/


IF OBJECT_ID('dbo.sp_IndexCleanup', 'P') IS NULL
BEGIN
    EXECUTE ('CREATE PROCEDURE dbo.sp_IndexCleanup AS RETURN 138;');
END;
GO

ALTER PROCEDURE
    dbo.sp_IndexCleanup
(
    @database_name sysname = NULL, /*focus on a single database*/
    @schema_name sysname = NULL, /*use when focusing on a single table/view, or to a single schema with no table name*/
    @table_name sysname = NULL, /*use when focusing on a single table or view*/
    @min_reads bigint = 0, /*only look at indexes with a minimum number of reads*/
    @min_writes bigint = 0, /*only look at indexes with a minimum number of writes*/
    @min_size_gb decimal(10,2) = 0, /*only look at indexes with a minimum size*/
    @min_rows bigint = 0, /*only look at indexes with a minimum number of rows*/
    @dedupe_only bit = 'false', /*only perform deduplication, don't mark unused indexes for removal*/
    @get_all_databases bit = 'false', /*looks for all accessible user databases and returns combined results*/
    @include_databases nvarchar(max) = NULL, /*comma-separated list of databases to include (only when @get_all_databases = 1)*/
    @exclude_databases nvarchar(max) = NULL, /*comma-separated list of databases to exclude (only when @get_all_databases = 1)*/
    @help bit = 'false', /*learn about the procedure and parameters*/
    @debug bit = 'false', /*print dynamic sql, show temp table contents*/
    @version varchar(20) = NULL OUTPUT, /*script version number*/
    @version_date datetime = NULL OUTPUT /*script version date*/
)
WITH RECOMPILE
AS
BEGIN
SET NOCOUNT ON;
BEGIN TRY
    SELECT
        @version = '1.6',
        @version_date = '20250601';

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

    /*
    Help section, for help.
    Will become more helpful when out of beta.
    */
    IF @help = 1
    BEGIN
        SELECT
            help = N'hello, i am sp_IndexCleanup'
          UNION ALL
        SELECT
            help = N'this is a script to help clean up unused and duplicate indexes.'
          UNION ALL
        SELECT
            help = N'it will also help you add page compression to uncompressed indexes.'
          UNION ALL
        SELECT
            help = N'always validate all changes against a non-production environment!'
          UNION ALL
        SELECT
            help = N'please test carefully.'
          UNION ALL
        SELECT
            help = N'brought to you by erikdarling.com / code.erikdarling.com';

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
                    WHEN N'@schema_name' THEN 'limits analysis to tables in the specified schema when used without @table_name'
                    WHEN N'@table_name' THEN 'the table or view name to filter indexes by, requires @schema_name if not dbo'
                    WHEN N'@min_reads' THEN 'minimum number of reads for an index to be considered used'
                    WHEN N'@min_writes' THEN 'minimum number of writes for an index to be considered used'
                    WHEN N'@min_size_gb' THEN 'minimum size in GB for an index to be analyzed'
                    WHEN N'@min_rows' THEN 'minimum number of rows for a table to be analyzed'
                    WHEN N'@dedupe_only' THEN 'only perform index deduplication, do not mark unused indexes for removal'
                    WHEN N'@get_all_databases' THEN 'set to 1 to analyze all accessible user databases'
                    WHEN N'@include_databases' THEN 'comma-separated list of databases to include when @get_all_databases = 1'
                    WHEN N'@exclude_databases' THEN 'comma-separated list of databases to exclude when @get_all_databases = 1'
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
                    WHEN N'@table_name' THEN 'table (or view) name or NULL for all tables'
                    WHEN N'@min_reads' THEN 'any positive integer or 0'
                    WHEN N'@min_writes' THEN 'any positive integer or 0'
                    WHEN N'@min_size_gb' THEN 'any positive decimal or 0'
                    WHEN N'@min_rows' THEN 'any positive integer or 0'
                    WHEN N'@dedupe_only' THEN '0 or 1 - only perform index deduplication, do not mark unused indexes for removal'
                    WHEN N'@get_all_databases' THEN '0 or 1'
                    WHEN N'@include_databases' THEN 'comma-separated list of database names'
                    WHEN N'@exclude_databases' THEN 'comma-separated list of database names'
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
                    WHEN N'@dedupe_only' THEN '0'
                    WHEN N'@get_all_databases' THEN '0'
                    WHEN N'@include_databases' THEN 'NULL'
                    WHEN N'@exclude_databases' THEN 'NULL'
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

Copyright 2025 Darling Data, LLC

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
                    CONVERT
                    (
                        integer,
                        SERVERPROPERTY('EngineEdition')
                    ) IN (3, 5, 8)
                    OR
                    (
                      CONVERT
                      (
                          integer,
                          SERVERPROPERTY('EngineEdition')
                      ) = 2
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
                          ) >= 13
                    )
                THEN 1
                ELSE 0
            END,
        /* OPTIMIZE_FOR_SEQUENTIAL_KEY variables (SQL 2019+, Azure SQL DB, and Managed Instance) */
        @supports_optimize_for_sequential_key bit =
            CASE
                /* Azure SQL DB or Managed Instance */
                WHEN CONVERT(integer, SERVERPROPERTY('EngineEdition')) IN (5, 8)
                THEN 1
                /* SQL Server 2019+ */
                WHEN CONVERT(integer, SERVERPROPERTY('EngineEdition')) = 3
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
                         ) >= 15
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
        ),
        @database_cursor CURSOR,
        @current_database_name sysname,
        @current_database_id integer,
        @error_msg nvarchar(2048),
        @conflict_list nvarchar(max) = N'',
        @rc bigint;

    /* Set uptime warning flag after @uptime_days is calculated */
    SELECT
        @uptime_warning =
            CASE
                WHEN CONVERT(integer, @uptime_days) < 14
                THEN 1
                ELSE 0
            END;

    /* Auto-enable dedupe_only mode if server uptime is low */
    IF CONVERT(integer, @uptime_days) <= 7 AND @dedupe_only = 0
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Server uptime is less than 7 days. Automatically enabling @dedupe_only mode.', 0, 1) WITH NOWAIT;
        END;

        SET @dedupe_only = 1;
    END;

    /*
    Initial checks for object validity
    */
    IF @debug = 1
    BEGIN
        RAISERROR('Checking parameters...', 0, 0) WITH NOWAIT;
    END;

    IF  @schema_name IS NULL
    AND @table_name IS NOT NULL
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Parameter @schema_name cannot be NULL when specifying a table, defaulting to dbo', 10, 1) WITH NOWAIT;
        END;

        SET @schema_name = N'dbo';
    END;

    IF @min_reads < 0
    OR @min_reads IS NULL
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Parameter @min_reads cannot be NULL or negative. Setting to 0.', 10, 1) WITH NOWAIT;
        END;

        SET @min_reads = 0;
    END;

    IF @min_writes < 0
    OR @min_writes IS NULL
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Parameter @min_writes cannot be NULL or negative. Setting to 0.', 10, 1) WITH NOWAIT;
        END;

        SET @min_writes = 0;
    END;

    IF @min_size_gb < 0
    OR @min_size_gb IS NULL
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Parameter @min_size_gb cannot be NULL or negative. Setting to 0.', 10, 1) WITH NOWAIT;
        END;

        SET @min_size_gb = 0;
    END;

    IF @min_rows < 0
    OR @min_rows IS NULL
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Parameter @min_rows cannot be NULL or negative. Setting to 0.', 10, 1) WITH NOWAIT;
        END;

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
        INDEX filtered_objects CLUSTERED
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
        partition_number integer NOT NULL,
        total_rows bigint NULL,
        total_space_gb decimal(38, 4) NULL, /* Using 4 decimal places for GB to maintain precision */
        reserved_lob_gb decimal(38, 4) NULL, /* Using 4 decimal places for GB to maintain precision */
        reserved_row_overflow_gb decimal(38, 4) NULL, /* Using 4 decimal places for GB to maintain precision */
        data_compression_desc nvarchar(60) NULL,
        built_on sysname NULL,
        partition_function_name sysname NULL,
        partition_columns nvarchar(max)
        PRIMARY KEY CLUSTERED
            (database_id, schema_id, object_id, index_id, partition_id)
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
        column_id int NOT NULL,
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
        optimize_for_sequential_key bit NOT NULL,
        user_seeks bigint NOT NULL,
        user_scans bigint NOT NULL,
        user_lookups bigint NOT NULL,
        user_updates bigint NOT NULL,
        last_user_seek datetime NULL,
        last_user_scan datetime NULL,
        last_user_lookup datetime NULL,
        last_user_update datetime NULL,
        is_eligible_for_dedupe bit NOT NULL
        PRIMARY KEY CLUSTERED
            (database_id, schema_id, object_id, index_id, column_id)
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
        index_id integer NOT NULL,
        index_name sysname NOT NULL,
        is_unique bit NULL,
        key_columns nvarchar(MAX) NULL,
        included_columns nvarchar(MAX) NULL,
        filter_definition nvarchar(MAX) NULL,
        /* Query plan for original CREATE INDEX statement */
        original_index_definition nvarchar(MAX) NULL,
        /*
        Consolidation rule that matched (e.g., Key Duplicate, Key Subset, etc)
        For exact duplicates, use one of: Exact Duplicate, Reverse Duplicate, or Equal Except For Filter
        */
        consolidation_rule nvarchar(256) NULL,
        /*
        Action to take (e.g., DISABLE, MERGE INCLUDES, KEEP)
        If NULL, no action to be taken
        */
        action nvarchar(100) NULL,
        /* Target index to merge with or use instead of this one */
        target_index_name sysname NULL,
        /* When this is a target, the index which points to it as a supersedes in consolidation */
        superseded_by nvarchar(4000) NULL,
        /* Priority score from 0-1 to determine which index to keep (higher is better) */
        index_priority decimal(10,6) NULL
        INDEX index_analysis CLUSTERED
            (database_id, schema_id, object_id, index_id)
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
        PRIMARY KEY CLUSTERED
            (database_id, schema_id, object_id, index_id, can_compress)
    );

    CREATE TABLE
        #index_cleanup_results
    (
        result_type varchar(100) NOT NULL,
        sort_order integer NOT NULL,
        database_name nvarchar(max) NULL,
        schema_name nvarchar(max) NULL,
        table_name sysname NULL,
        index_name sysname NULL,
        script_type nvarchar(60) NULL, /* Type of script (e.g., MERGE SCRIPT, DISABLE SCRIPT, etc.) */
        consolidation_rule nvarchar(256) NULL, /* Reason for action (e.g., Exact Duplicate, Key Subset) */
        target_index_name sysname NULL, /* If this index is a duplicate, indicates which index is the preferred one */
        superseded_info nvarchar(4000) NULL, /* If this is a kept index, indicates which indexes it supersedes */
        additional_info nvarchar(max) NULL, /* Additional information about the action */
        original_index_definition nvarchar(max) NULL, /* Original statement to create the index */
        index_size_gb decimal(38, 4) NULL, /* Size of the index in GB */
        index_rows bigint NULL, /* Number of rows in the index */
        index_reads bigint NULL, /* Total reads (seeks + scans + lookups) */
        index_writes bigint NULL, /* Total writes */
        script nvarchar(max) NULL /* Script to execute the action */
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
        index_list nvarchar(max) NULL
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

    /* Create a new temp table for detailed reporting statistics */
    CREATE TABLE
        #index_reporting_stats
    (
        summary_level varchar(20) NOT NULL, /* 'DATABASE', 'TABLE', 'INDEX', 'SUMMARY' */
        database_name sysname NULL,
        schema_name sysname NULL,
        table_name sysname NULL,
        index_name sysname NULL,
        server_uptime_days integer NULL,
        uptime_warning bit NULL,
        tables_analyzed integer NULL,
        index_count integer NULL,
        total_size_gb decimal(38, 4) NULL,
        total_rows bigint NULL,
        unused_indexes integer NULL,
        unused_size_gb decimal(38, 4) NULL,
        indexes_to_disable integer NULL,
        indexes_to_merge integer NULL,
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

    /* Create temp tables for database filtering */
    CREATE TABLE
        #include_databases
    (
        database_name sysname NOT NULL PRIMARY KEY CLUSTERED
    );

    CREATE TABLE
        #exclude_databases
    (
        database_name sysname NOT NULL PRIMARY KEY CLUSTERED
    );

    CREATE TABLE
        #databases
    (
        database_name sysname NOT NULL PRIMARY KEY CLUSTERED,
        database_id int NOT NULL
    );

    CREATE TABLE
        #requested_but_skipped_databases
    (
        database_name sysname NOT NULL PRIMARY KEY CLUSTERED,
        reason nvarchar(100) NOT NULL
    );

    CREATE TABLE
        #computed_columns_analysis
    (
        database_id integer NOT NULL,
        database_name sysname NOT NULL,
        schema_id integer NOT NULL,
        schema_name sysname NOT NULL,
        object_id integer NOT NULL,
        table_name sysname NOT NULL,
        column_id integer NOT NULL,
        column_name sysname NOT NULL,
        definition nvarchar(max) NULL,
        contains_udf bit NOT NULL,
        udf_names nvarchar(max) NULL,
        PRIMARY KEY CLUSTERED
            (database_id, schema_id, object_id, column_id)
    );

    CREATE TABLE
        #check_constraints_analysis
    (
        database_id integer NOT NULL,
        database_name sysname NOT NULL,
        schema_id integer NOT NULL,
        schema_name sysname NOT NULL,
        object_id integer NOT NULL,
        table_name sysname NOT NULL,
        constraint_id integer NOT NULL,
        constraint_name sysname NOT NULL,
        definition nvarchar(max) NULL,
        contains_udf bit NOT NULL,
        udf_names nvarchar(max) NULL,
        PRIMARY KEY CLUSTERED
            (database_id, schema_id, object_id, constraint_id)
    );

    CREATE TABLE
        #filtered_index_columns_analysis
    (
        database_id integer NOT NULL,
        database_name sysname NOT NULL,
        schema_id integer NOT NULL,
        schema_name sysname NOT NULL,
        object_id integer NOT NULL,
        table_name sysname NOT NULL,
        index_id integer NOT NULL,
        index_name sysname NULL,
        filter_definition nvarchar(max) NULL,
        missing_included_columns nvarchar(max) NULL,
        should_include_filter_columns bit NOT NULL,
        INDEX c CLUSTERED
            (database_id, schema_id, object_id, index_id)
    );

    /* Parse @include_databases comma-separated list */
    IF  @get_all_databases = 1
    AND @include_databases IS NOT NULL
    BEGIN
        INSERT INTO
            #include_databases
        WITH
            (TABLOCK)
        (
            database_name
        )
        SELECT DISTINCT
            database_name =
                LTRIM(RTRIM(c.value(N'(./text())[1]', N'sysname')))
        FROM
        (
            SELECT
                x = CONVERT
                    (
                        xml,
                        N'<i>' +
                        REPLACE
                        (
                            @include_databases,
                            N',',
                            N'</i><i>'
                        ) +
                        N'</i>'
                    )
        ) AS a
        CROSS APPLY x.nodes(N'//i') AS t(c)
        WHERE LTRIM(RTRIM(c.value(N'(./text())[1]', N'sysname'))) <> N''
        OPTION(RECOMPILE);

        IF @debug = 1
        BEGIN
            SELECT
                table_name = '#include_databases',
                id.*
            FROM #include_databases AS id
            OPTION(RECOMPILE);
        END;
    END;

    IF  @get_all_databases = 1
    AND @include_databases IS NOT NULL
    BEGIN
        INSERT INTO
            #requested_but_skipped_databases
        WITH
            (TABLOCK)
        (
            database_name,
            reason
        )
        SELECT
            id.database_name,
            reason =
                CASE
                    WHEN d.name IS NULL
                    THEN 'Database does not exist'
                    WHEN d.state <> 0
                    THEN 'Database not online'
                    WHEN d.is_in_standby = 1
                    THEN 'Database is in standby'
                    WHEN d.is_read_only = 1
                    THEN 'Database is read-only'
                    WHEN d.database_id <= 4
                    THEN 'System database'
                    ELSE 'Other issue'
                END
        FROM #include_databases AS id
        LEFT JOIN sys.databases AS d
          ON id.database_name = d.name
        WHERE NOT EXISTS
              (
                  SELECT
                      1/0
                  FROM #databases AS db
                  WHERE db.database_name = id.database_name
              )
        OPTION(RECOMPILE);

        IF @debug = 1
        BEGIN
            SELECT
                table_name = '#requested_but_skipped_databases',
                rbsd.*
            FROM #requested_but_skipped_databases AS rbsd
            OPTION(RECOMPILE);
        END;
    END;

    /* Parse @exclude_databases comma-separated list */
    IF  @get_all_databases = 1
    AND @exclude_databases IS NOT NULL
    BEGIN
        INSERT INTO
            #exclude_databases
        WITH
            (TABLOCK)
        (
            database_name
        )
        SELECT DISTINCT
            database_name =
                LTRIM(RTRIM(c.value(N'(./text())[1]', N'sysname')))
        FROM
        (
            SELECT
                x = CONVERT
                    (
                        xml,
                        N'<i>' +
                        REPLACE
                        (
                            @exclude_databases,
                            N',',
                            N'</i><i>'
                        ) +
                        N'</i>'
                    )
        ) AS a
        CROSS APPLY x.nodes(N'//i') AS t(c)
        WHERE LTRIM(RTRIM(c.value(N'(./text())[1]', N'sysname'))) <> N''
        OPTION(RECOMPILE);

        IF @debug = 1
        BEGIN
            SELECT
                table_name = '#exclude_databases',
                ed.*
            FROM #exclude_databases AS ed
            OPTION(RECOMPILE);
        END;
    END;

    /* Check for conflicts between include and exclude lists */
    IF  @get_all_databases = 1
    AND @include_databases IS NOT NULL
    AND @exclude_databases IS NOT NULL
    BEGIN
        SELECT
            @conflict_list =
                @conflict_list +
                ed.database_name + N', '
        FROM #exclude_databases AS ed
        WHERE EXISTS
            (
                SELECT
                    1/0
                FROM #include_databases AS id
                WHERE id.database_name = ed.database_name
            )
        OPTION(RECOMPILE);

        /* If we found any conflicts, raise an error */
        IF LEN(@conflict_list) > 0
        BEGIN
            /* Remove trailing comma and space */
            SET @conflict_list = LEFT(@conflict_list, LEN(@conflict_list) - 2);

            SET @error_msg =
                N'The following databases appear in both @include_databases and @exclude_databases, which creates ambiguity: ' +
                @conflict_list + N'. Please remove these databases from one of the lists.';

            RAISERROR(@error_msg, 16, 1);
            RETURN;
        END;
    END;

    /* Handle contradictory parameters */
    IF  @get_all_databases = 1
    AND @database_name IS NOT NULL
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR(N'@database name being ignored since @get_all_databases is set to 1', 0, 0) WITH NOWAIT;
        END;
        SET @database_name = NULL;
    END;

    /* Build the #databases table */
    IF @get_all_databases = 0
    BEGIN
        /* Default to current database if not system db */
        IF @database_name IS NULL
        AND DB_NAME() NOT IN
            (
                N'master',
                N'model',
                N'msdb',
                N'tempdb',
                N'rdsadmin'
            )
        BEGIN
            SET @database_name = DB_NAME();
        END;

        /* Single database mode */
        IF @database_name IS NOT NULL
        BEGIN
            INSERT INTO
                #databases
            WITH
                (TABLOCK)
            (
                database_name,
                database_id
            )
            SELECT
                d.name,
                d.database_id
            FROM sys.databases AS d
            WHERE d.database_id = DB_ID(@database_name)
            AND   d.state = 0
            AND   d.is_in_standby = 0
            AND   d.is_read_only = 0
            OPTION(RECOMPILE);

            /* Get the database_id for backwards compatibility */
            SELECT
                @current_database_id = d.database_id
            FROM #databases AS d
            OPTION(RECOMPILE);
        END;
    END
    ELSE
    BEGIN
        /* Multi-database mode */
        INSERT INTO
            #databases
        WITH
            (TABLOCK)
        (
            database_name,
            database_id
        )
        SELECT
            d.name,
            d.database_id
        FROM sys.databases AS d
        WHERE d.database_id > 4 /* Skip system databases */
        AND   d.state = 0
        AND   d.is_in_standby = 0
        AND   d.is_read_only = 0
        AND   (
                @include_databases IS NULL
                OR EXISTS (SELECT 1/0 FROM #include_databases AS id WHERE id.database_name = d.name)
              )
        AND   (
                @exclude_databases IS NULL
                OR NOT EXISTS (SELECT 1/0 FROM #exclude_databases AS ed WHERE ed.database_name = d.name)
              )
        OPTION(RECOMPILE);
    END;

    /* Check for empty database list */
    IF (SELECT COUNT_BIG(*) FROM #databases AS d) = 0
    BEGIN
        RAISERROR('No valid databases found to process.', 16, 1);
        RETURN;
    END;

    /* Show database list in debug mode */
    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#databases',
            d.*
        FROM #databases AS d
        OPTION(RECOMPILE);
    END;

    /*
    Set up database cursor processing
    */

    /* Create a cursor to process each database */
    SET @database_cursor =
            CURSOR
            LOCAL
            SCROLL
            DYNAMIC
            READ_ONLY
    FOR
    SELECT
        d.database_name,
        d.database_id
    FROM #databases AS d
    ORDER BY
        d.database_id;

    OPEN @database_cursor;

    FETCH FIRST
    FROM @database_cursor
    INTO
        @current_database_name,
        @current_database_id;

    /*
    Start insert queries
    */
    IF @debug = 1
    BEGIN
        RAISERROR('Generating #filtered_object insert', 0, 0) WITH NOWAIT;
    END;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        /*Truncate temp tables between database iterations*/
        IF @debug = 1
        BEGIN
            RAISERROR('Truncating per-database temp tables for the next iteration', 0, 0) WITH NOWAIT;
        END;

        TRUNCATE TABLE
            #filtered_objects;
        TRUNCATE TABLE
            #operational_stats;
        TRUNCATE TABLE
            #partition_stats;
        TRUNCATE TABLE
            #index_details;
        TRUNCATE TABLE
            #compression_eligibility;
        TRUNCATE TABLE
            #key_duplicate_dedupe;
        TRUNCATE TABLE
            #include_subset_dedupe;
        TRUNCATE TABLE
            #computed_columns_analysis;
        TRUNCATE TABLE
            #check_constraints_analysis;
        TRUNCATE TABLE
            #filtered_index_columns_analysis;

         /*Validate searched objects per-database*/
         IF  @schema_name IS NOT NULL
         AND @table_name IS NOT NULL
         BEGIN
             IF @debug = 1
             BEGIN
                 RAISERROR('validating object existence for %s.%s.%s.', 0, 0, @current_database_name, @schema_name, @table_name) WITH NOWAIT;
             END;

             SELECT
                 @full_object_name =
                     QUOTENAME(@current_database_name) +
                     N'.' +
                     QUOTENAME(@schema_name) +
                     N'.' +
                     QUOTENAME(@table_name);

             SET @object_id = OBJECT_ID(@full_object_name);

             IF @object_id IS NULL
             BEGIN
                 RAISERROR('The object %s doesn''t seem to exist', 10, 1, @full_object_name) WITH NOWAIT;

                 IF @get_all_databases = 0
                 BEGIN
                     RETURN;
                 END;

                 /* Get the next database and continue the loop */
                 FETCH NEXT
                 FROM @database_cursor
                 INTO
                     @current_database_name,
                     @current_database_id;
                 CONTINUE;
             END;
         END;

        /* Process current database */
        IF @debug = 1
        BEGIN
            RAISERROR('Processing @current_database_name: %s and @current_database_id: %d', 0, 0, @current_database_name, @current_database_id) WITH NOWAIT;
        END;

        SELECT
            @sql = N'
        SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;';

        SELECT
            @sql = N'
        SELECT DISTINCT
            @database_id,
            database_name = DB_NAME(@database_id),
            schema_id = s.schema_id,
            schema_name = s.name,
            object_id = i.object_id,
            table_name = ISNULL(t.name, v.name),
            index_id = i.index_id,
            index_name = ISNULL(i.name, ISNULL(t.name, v.name) + N''.Heap''),
            can_compress =
                CASE
                    WHEN p.index_id > 0
                    AND  p.data_compression = 0
                    THEN 1
                    ELSE 0
                END
        FROM ' + QUOTENAME(@current_database_name) + N'.sys.indexes AS i
        LEFT JOIN ' + QUOTENAME(@current_database_name) + N'.sys.tables AS t
          ON i.object_id = t.object_id
        LEFT JOIN ' + QUOTENAME(@current_database_name) + N'.sys.views AS v
          ON i.object_id = v.object_id
        JOIN ' + QUOTENAME(@current_database_name) + N'.sys.schemas AS s
          ON ISNULL(t.schema_id, v.schema_id) = s.schema_id
        JOIN ' + QUOTENAME(@current_database_name) + N'.sys.partitions AS p
          ON  i.object_id = p.object_id
          AND i.index_id = p.index_id
        LEFT JOIN ' + QUOTENAME(@current_database_name) + N'.sys.dm_db_index_usage_stats AS us
          ON  i.object_id = us.object_id
          AND us.database_id = @database_id
        WHERE (t.object_id IS NULL OR t.is_ms_shipped = 0)
        AND   (t.object_id IS NULL OR t.type <> N''TF'')
        AND i.is_disabled = 0
        AND i.is_hypothetical = 0';

    IF /* Check for temporal tables support */
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
        IF @debug = 1
        BEGIN
            RAISERROR('adding temporal table screening', 0, 0) WITH NOWAIT;
        END;

        SET @sql += N'
        AND   NOT EXISTS
        (
            SELECT
                1/0
            FROM ' + QUOTENAME(@current_database_name) + N'.sys.tables AS t
            WHERE t.object_id = i.object_id
            AND   t.temporal_type > 0
        )';
    END;

    IF @object_id IS NOT NULL
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('adding object_id filter', 0, 0) WITH NOWAIT;
        END;

        SET @sql += N'
        AND   i.object_id = @object_id';
    END;

    IF  @schema_name IS NOT NULL
    AND @object_id IS NULL
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('adding schema_name filter', 0, 0) WITH NOWAIT;
        END;

        SET @sql += N'
        AND   s.name = @schema_name';
    END;

    SET @sql += N'
        AND EXISTS
        (
            SELECT
                1/0
            FROM ' + QUOTENAME(@current_database_name) + N'.sys.dm_db_partition_stats AS ps
            JOIN ' + QUOTENAME(@current_database_name) + N'.sys.allocation_units AS au
              ON ps.partition_id = au.container_id
            WHERE ps.object_id = i.object_id
            GROUP BY
                ps.object_id
            HAVING
                SUM(au.total_pages) * 8.0 / 1048576.0 >= @min_size_gb
        )
        AND EXISTS
        (
            SELECT
                1/0
            FROM ' + QUOTENAME(@current_database_name) + N'.sys.dm_db_partition_stats AS ps
            WHERE ps.object_id = i.object_id
            AND   ps.index_id IN (0, 1)
            GROUP BY
                ps.object_id
            HAVING
                SUM(ps.row_count) >= @min_rows
        )
        AND EXISTS
        (
            SELECT
                1/0
            FROM ' + QUOTENAME(@current_database_name) + N'.sys.dm_db_index_usage_stats AS ius
            WHERE ius.object_id = i.object_id
            AND   ius.database_id = @database_id
            GROUP BY
                ius.object_id
            HAVING
                SUM(ius.user_seeks + ius.user_scans + ius.user_lookups) >= @min_reads
            OR
                SUM(ius.user_updates) >= @min_writes
        )
        OPTION(RECOMPILE);
    ';

    IF @debug = 1
    BEGIN
        PRINT @sql;
    END;

    INSERT INTO
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
      N'@database_id integer,
        @min_reads bigint,
        @min_writes bigint,
        @min_size_gb decimal(10,2),
        @min_rows bigint,
        @object_id integer,
        @schema_name sysname',
        @current_database_id,
        @min_reads,
        @min_writes,
        @min_size_gb,
        @min_rows,
        @object_id,
        @schema_name;

    SET @rc = ROWCOUNT_BIG();

    IF @rc = 0
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('No rows inserted into #filtered_objects from %s, continuing to next database...', 10, 0, @current_database_name) WITH NOWAIT;
        END;

        IF @get_all_databases = 0
        BEGIN
            RETURN;
        END;

        /* Get the next database and continue the loop */
        FETCH NEXT
        FROM @database_cursor
        INTO
            @current_database_name,
            @current_database_id;
        CONTINUE;
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
        can_compress =
            CASE
                 @can_compress
                 WHEN 0
                 THEN 0
                 ELSE 1
            END,
        reason =
            CASE
                 @can_compress
                 WHEN 0
                 THEN N'SQL Server edition or version does not support compression'
                 ELSE NULL
            END
    FROM #filtered_objects AS fo
    WHERE fo.can_compress = 1
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#compression_eligibility before update',
            ce.*
        FROM #compression_eligibility AS ce
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
            ce.reason = ''Table contains sparse columns''
        FROM #compression_eligibility AS ce
        WHERE EXISTS
        (
            SELECT
                1/0
            FROM ' + QUOTENAME(@current_database_name) + N'.sys.columns AS c
            WHERE c.object_id = ce.object_id
            AND
            (
                 c.is_sparse = 1
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

         SELECT
            @sql = N'
        SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

        UPDATE
            ce
        SET
            ce.can_compress = 0,
            ce.reason = ''Index contains incompatible data types''
        FROM #compression_eligibility AS ce
        JOIN ' + QUOTENAME(@current_database_name) + N'.sys.indexes AS i
          ON i.object_id = ce.object_id AND i.index_id = ce.index_id
        WHERE ce.can_compress = 1
          AND i.type = 1
          AND EXISTS
        (
            SELECT
                1/0
            FROM ' + QUOTENAME(@current_database_name) + N'.sys.columns AS c
            JOIN ' + QUOTENAME(@current_database_name) + N'.sys.types AS t
              ON c.user_type_id = t.user_type_id
            WHERE c.object_id = ce.object_id
            AND
            (
                 t.name IN (N''text'', N''ntext'', N''image'')
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
            table_name = '#compression_eligibility after update',
            ce.*
        FROM #compression_eligibility AS ce
        OPTION(RECOMPILE);

        RAISERROR('Analyzing computed columns for UDF references', 0, 0) WITH NOWAIT;
    END;

    /* Check for computed columns that potentially use UDFs */
    SELECT
        @sql = N'
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    SELECT DISTINCT
        fo.database_id,
        fo.database_name,
        fo.schema_id,
        fo.schema_name,
        fo.object_id,
        fo.table_name,
        c.column_id,
        column_name = c.name,
        definition = cc.definition,
        contains_udf =
            CASE
                WHEN cc.definition LIKE ''%|].|[%'' ESCAPE ''|''
                THEN 1
                ELSE 0
            END,
        udf_names =
            CASE
                WHEN cc.definition LIKE ''%|].|[%'' ESCAPE ''|''
                THEN
                    SUBSTRING
                    (
                        cc.definition,
                        CHARINDEX(N''['', cc.definition),
                        CHARINDEX
                        (
                            N'']'',
                            cc.definition,
                            CHARINDEX
                            (
                                N''].['',
                                cc.definition
                            ) + 3
                        ) -
                        CHARINDEX(N''['', cc.definition) + 1
                    )
                ELSE NULL
            END
    FROM #filtered_objects AS fo
    JOIN ' + QUOTENAME(@current_database_name) + N'.sys.columns AS c
      ON fo.object_id = c.object_id
    JOIN ' + QUOTENAME(@current_database_name) + N'.sys.computed_columns AS cc
      ON  c.object_id = cc.object_id
      AND c.column_id = cc.column_id
    OPTION(RECOMPILE);';

    IF @debug = 1
    BEGIN
        PRINT @sql;
    END;

    INSERT INTO
        #computed_columns_analysis
    WITH
        (TABLOCK)
    (
        database_id,
        database_name,
        schema_id,
        schema_name,
        object_id,
        table_name,
        column_id,
        column_name,
        definition,
        contains_udf,
        udf_names
    )
    EXECUTE sys.sp_executesql
        @sql;

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#computed_columns_analysis',
            cca.*
        FROM #computed_columns_analysis AS cca
        OPTION(RECOMPILE);

        RAISERROR('Analyzing check constraints for UDF references', 0, 0) WITH NOWAIT;
    END;

    /* Check for check constraints that potentially use UDFs */
    SELECT
        @sql = N'
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    SELECT DISTINCT
        fo.database_id,
        fo.database_name,
        fo.schema_id,
        fo.schema_name,
        fo.object_id,
        fo.table_name,
        cc.object_id AS constraint_id,
        constraint_name = cc.name,
        definition = cc.definition,
        contains_udf =
            CASE
                WHEN cc.definition LIKE ''%|].|[%'' ESCAPE ''|''
                THEN 1
                ELSE 0
            END,
        udf_names =
            CASE
                WHEN cc.definition LIKE ''%|].|[%'' ESCAPE ''|''
                THEN
                    SUBSTRING
                    (
                        cc.definition,
                        CHARINDEX(N''['', cc.definition),
                        CHARINDEX
                        (
                            N'']'',
                            cc.definition,
                            CHARINDEX
                            (
                                N''].['',
                                cc.definition
                            ) + 3
                        ) -
                        CHARINDEX(N''['', cc.definition) + 1
                    )
                ELSE NULL
            END
    FROM #filtered_objects AS fo
    JOIN ' + QUOTENAME(@current_database_name) + N'.sys.check_constraints AS cc
      ON fo.object_id = cc.parent_object_id
    OPTION(RECOMPILE);';

    IF @debug = 1
    BEGIN
        PRINT @sql;
    END;

    INSERT INTO
        #check_constraints_analysis
    WITH
        (TABLOCK)
    (
        database_id,
        database_name,
        schema_id,
        schema_name,
        object_id,
        table_name,
        constraint_id,
        constraint_name,
        definition,
        contains_udf,
        udf_names
    )
    EXECUTE sys.sp_executesql
        @sql;

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#check_constraints_analysis',
            cca.*
        FROM #check_constraints_analysis AS cca
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
        table_name = ISNULL(t.name, v.name),
        os.index_id,
        index_name = ISNULL(i.name, ISNULL(t.name, v.name) + N''.Heap''),
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
    FROM ' + QUOTENAME(@current_database_name) + N'.sys.dm_db_index_operational_stats
    (
        @database_id,
        @object_id,
        NULL,
        NULL
    ) AS os
    LEFT JOIN ' + QUOTENAME(@current_database_name) + N'.sys.tables AS t
      ON os.object_id = t.object_id
    LEFT JOIN ' + QUOTENAME(@current_database_name) + N'.sys.views AS v
      ON os.object_id = v.object_id
    JOIN ' + QUOTENAME(@current_database_name) + N'.sys.schemas AS s
      ON ISNULL(t.schema_id, v.schema_id) = s.schema_id
    JOIN ' + QUOTENAME(@current_database_name) + N'.sys.indexes AS i
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
        ISNULL(t.name, v.name),
        os.index_id,
        i.name
    OPTION(RECOMPILE);
    ';

    IF @debug = 1
    BEGIN
        PRINT @sql;
    END;

    INSERT INTO
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
        @current_database_id,
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
        i.object_id,
        i.index_id,
        s.schema_id,
        schema_name = s.name,
        table_name = ISNULL(t.name, v.name),
        index_name = ISNULL(i.name, ISNULL(t.name, v.name) + N''.Heap''),
        column_name = c.name,
        column_id = c.column_id,
        i.is_primary_key,
        i.is_unique,
        i.is_unique_constraint,
        is_indexed_view =
            CASE
                WHEN EXISTS
                (
                    SELECT
                        1/0
                    FROM ' + QUOTENAME(@current_database_name) + N'.sys.objects AS so
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
                         FROM ' + QUOTENAME(@current_database_name) + N'.sys.foreign_key_columns AS f
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
                         FROM ' + QUOTENAME(@current_database_name) + N'.sys.foreign_key_columns AS f
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
                         FROM ' + QUOTENAME(@current_database_name) + N'.sys.types AS t
                         WHERE  c.system_type_id = t.system_type_id
                         AND    c.user_type_id = t.user_type_id
                         AND    t.name IN (N''varchar'', N''nvarchar'')
                         AND    t.max_length = -1
                     )
                THEN 1
                ELSE 0
            END,' +
        CASE
            WHEN @supports_optimize_for_sequential_key = 1
            THEN N'
        optimize_for_sequential_key = ISNULL(i.optimize_for_sequential_key, 0),'
            ELSE N'
        optimize_for_sequential_key = 0,'
        END + N'
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
                WHEN
                (
                     i.type = 1
                  OR i.is_primary_key = 1
                )
                THEN 0
            END
    FROM ' + QUOTENAME(@current_database_name) + N'.sys.indexes AS i
    LEFT JOIN ' + QUOTENAME(@current_database_name) + N'.sys.tables AS t
      ON i.object_id = t.object_id
    LEFT JOIN ' + QUOTENAME(@current_database_name) + N'.sys.views AS v
      ON i.object_id = v.object_id
    JOIN ' + QUOTENAME(@current_database_name) + N'.sys.schemas AS s
      ON ISNULL(t.schema_id, v.schema_id) = s.schema_id
    JOIN ' + QUOTENAME(@current_database_name) + N'.sys.index_columns AS ic
      ON  i.object_id = ic.object_id
      AND i.index_id = ic.index_id
    JOIN ' + QUOTENAME(@current_database_name) +
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
    WHERE (t.object_id IS NULL OR t.is_ms_shipped = 0)
    AND   i.type IN (1, 2)
    AND   i.is_disabled = 0
    AND   i.is_hypothetical = 0
    AND   EXISTS
    (
        SELECT
            1/0
        FROM #filtered_objects AS fo
        WHERE fo.database_id = @database_id
        AND   fo.object_id = i.object_id
    )
    AND   EXISTS
    (
        SELECT
            1/0
        FROM '
    ) + QUOTENAME(@current_database_name) +
        CONVERT
        (
            nvarchar(MAX),
            N'.sys.dm_db_partition_stats ps
        WHERE ps.object_id = i.object_id
        AND   ps.index_id = 1
        AND   ps.row_count >= @min_rows
    )'
        );

    IF @object_id IS NOT NULL
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('adding object+id filter', 0, 0) WITH NOWAIT;
        END;

        SELECT @sql += N'
    AND   i.object_id = @object_id';
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
          FROM ' + QUOTENAME(@current_database_name) + N'.sys.objects AS so
          WHERE i.object_id = so.object_id
          AND   so.is_ms_shipped = 0
          AND   so.type = N''TF''
    )
    OPTION(RECOMPILE);
    '
        );

    IF @debug = 1
    BEGIN
        PRINT SUBSTRING(@sql, 1, 4000);
        PRINT SUBSTRING(@sql, 4000, 8000);
    END;

    INSERT INTO
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
        column_id,
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
        optimize_for_sequential_key,
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
        @current_database_id,
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
            table_name = ISNULL(t.name, v.name),
            index_name = ISNULL(i.name, ISNULL(t.name, v.name) + N''.Heap''),
            ps.partition_id,
            p.partition_number,
            total_rows = ps.row_count,
            total_space_gb = SUM(a.total_pages) * 8 / 1024.0 / 1024.0, /* Convert directly to GB */
            reserved_lob_gb = SUM(ps.lob_reserved_page_count) * 8. / 1024. / 1024.0, /* Convert directly to GB */
            reserved_row_overflow_gb = SUM(ps.row_overflow_reserved_page_count) * 8. / 1024. / 1024.0, /* Convert directly to GB */
            p.data_compression_desc,
            i.data_space_id
        FROM ' + QUOTENAME(@current_database_name) + N'.sys.indexes AS i
        LEFT JOIN ' + QUOTENAME(@current_database_name) + N'.sys.tables AS t
          ON i.object_id = t.object_id
        LEFT JOIN ' + QUOTENAME(@current_database_name) + N'.sys.views AS v
          ON i.object_id = v.object_id
        JOIN ' + QUOTENAME(@current_database_name) + N'.sys.schemas AS s
          ON ISNULL(t.schema_id, v.schema_id) = s.schema_id
        JOIN ' + QUOTENAME(@current_database_name) + N'.sys.partitions AS p
          ON  i.object_id = p.object_id
          AND i.index_id = p.index_id
        JOIN ' + QUOTENAME(@current_database_name) + N'.sys.allocation_units AS a
          ON p.partition_id = a.container_id
        LEFT HASH JOIN ' + QUOTENAME(@current_database_name) + N'.sys.dm_db_partition_stats AS ps
          ON p.partition_id = ps.partition_id
        WHERE (t.object_id IS NULL OR t.type <> N''TF'')
        AND   i.type IN (1, 2)
        AND   EXISTS
        (
            SELECT
                1/0
            FROM #filtered_objects AS fo
            WHERE fo.database_id = @database_id
            AND   fo.object_id = i.object_id
        )';

    IF @object_id IS NOT NULL
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('adding in object_id filter', 0, 0) WITH NOWAIT;
        END;

        SELECT @sql += N'
        AND   i.object_id = @object_id';
    END;

    SELECT
        @sql += N'
        GROUP BY
            ps.object_id,
            ps.index_id,
            s.schema_id,
            s.name,
            ISNULL(t.name, v.name),
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
        FROM ' + QUOTENAME(@current_database_name) + N'.sys.filegroups AS fg
        FULL JOIN ' + QUOTENAME(@current_database_name) + N'.sys.partition_schemes AS ps
          ON ps.data_space_id = fg.data_space_id
        LEFT JOIN ' + QUOTENAME(@current_database_name) + N'.sys.partition_functions AS pf
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
                    FROM ' + QUOTENAME(@current_database_name) + N'.sys.index_columns AS ic
                    JOIN ' + QUOTENAME(@current_database_name) + N'.sys.columns AS c
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
    OPTION(RECOMPILE);
    ';

    IF @debug = 1
    BEGIN
        PRINT SUBSTRING(@sql, 1, 4000);
        PRINT SUBSTRING(@sql, 4000, 8000);
    END;

    INSERT INTO
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
        @current_database_id,
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
        @current_database_id,
        database_name = DB_NAME(@current_database_id),
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
                    QUOTENAME(id2.column_name) +
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
                    QUOTENAME(id2.column_name)
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
                    QUOTENAME(DB_NAME(@current_database_id)) +
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
                    CASE
                        WHEN id1.is_unique = 1
                        THEN N'UNIQUE '
                    ELSE N''
                    END +
                    CASE
                        WHEN id1.index_id = 1
                        THEN N'CLUSTERED '
                        WHEN id1.index_id > 1
                        THEN N'NONCLUSTERED '
                        ELSE N''
                    END +
                    N'INDEX ' +
                    QUOTENAME(id1.index_name) +
                    N' ON ' +
                    QUOTENAME(DB_NAME(@current_database_id)) +
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
                        QUOTENAME(id2.column_name) +
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
                                QUOTENAME(id4.column_name)
                            FROM #index_details id4
                            WHERE id4.object_id = id1.object_id
                            AND   id4.index_id = id1.index_id
                            AND   id4.is_included_column = 1
                            GROUP BY
                                id4.column_id,
                                id4.column_name
                            ORDER BY
                                id4.column_id,
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
            END +
            N';'
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

        RAISERROR('Analyzing filtered indexes for columns to include', 0, 0) WITH NOWAIT;
    END;

    /* Analyze filtered indexes to identify columns used in filters that should be included */
    SET @sql = N'
    SELECT DISTINCT
        ia.database_id,
        ia.database_name,
        ia.schema_id,
        ia.schema_name,
        ia.object_id,
        ia.table_name,
        ia.index_id,
        ia.index_name,
        ia.filter_definition,
        missing_included_columns =
            (
                SELECT
                    STUFF
                    (
                        (
                            /* Find column names mentioned in filter_definition that aren''t already key or included columns */
                            SELECT
                                N'', '' +
                                c.name
                            FROM ' + QUOTENAME(@current_database_name) + N'.sys.columns AS c
                            WHERE c.object_id = ia.object_id
                            AND   ia.filter_definition LIKE N''%'' + c.name + N''%'' COLLATE DATABASE_DEFAULT
                            AND   NOT EXISTS
                            (
                                SELECT
                                    1/0
                                FROM #index_details AS id
                                WHERE id.object_id = ia.object_id
                                AND   id.index_id = ia.index_id
                                AND   id.column_id = c.column_id
                            )
                            GROUP BY
                                c.name
                            FOR
                                XML
                                PATH(''''),
                                TYPE
                        ).value(''text()[1]'',''nvarchar(max)''),
                        1,
                        2,
                        N''''
                    )
            ),
        should_include_filter_columns =
            CASE
                WHEN EXISTS
                (
                    /* Check if any columns mentioned in filter_definition aren''t already in the index */
                    SELECT
                        1/0
                    FROM ' + QUOTENAME(@current_database_name) + N'.sys.columns AS c
                    WHERE c.object_id = ia.object_id
                    AND   ia.filter_definition LIKE N''%'' + c.name + N''%'' COLLATE DATABASE_DEFAULT
                    AND   NOT EXISTS
                    (
                        SELECT
                            1/0
                        FROM #index_details AS id
                        WHERE id.object_id = ia.object_id
                        AND   id.index_id = ia.index_id
                        AND   id.column_id = c.column_id
                    )
                )
                THEN 1
                ELSE 0
            END
    FROM #index_analysis AS ia
    WHERE ia.filter_definition IS NOT NULL
    AND   ia.database_id = @current_database_id
    OPTION(RECOMPILE);';

    IF @debug = 1
    BEGIN
        RAISERROR('Filtered index analysis SQL:', 0, 1) WITH NOWAIT;
        PRINT @sql;
    END;

    /* The correct pattern: INSERT ... EXECUTE */
    INSERT INTO
        #filtered_index_columns_analysis
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
        filter_definition,
        missing_included_columns,
        should_include_filter_columns
    )
    EXECUTE sys.sp_executesql
        @sql,
      N'@current_database_id integer',
        @current_database_id;

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#filtered_index_columns_analysis',
            fica.*
        FROM #filtered_index_columns_analysis AS fica
        OPTION(RECOMPILE);

        RAISERROR('Starting updates', 0, 0) WITH NOWAIT;
    END;

    /* Calculate index priority scores based on actual columns that exist */
    UPDATE
        #index_analysis
    SET
        #index_analysis.index_priority =
            CASE
                WHEN #index_analysis.index_id = 1
                THEN 1000  /* Clustered indexes get highest priority */
                ELSE 0
            END
            +
            CASE
                /* Unique indexes get high priority, but reduce priority for unique constraints */
                WHEN #index_analysis.is_unique = 1 AND NOT EXISTS
                (
                    SELECT
                        1/0
                    FROM #index_details AS id_uc
                    WHERE id_uc.index_id = #index_analysis.index_id
                    AND   id_uc.object_id = #index_analysis.object_id
                    AND   id_uc.is_unique_constraint = 1
                ) THEN 500
                /* Unique constraints get lower priority */
                WHEN #index_analysis.is_unique = 1 AND EXISTS
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
                    FROM #index_details AS id
                    WHERE id.index_id = #index_analysis.index_id
                    AND   id.object_id = #index_analysis.object_id
                    AND   id.user_scans > 0
                ) THEN 100 ELSE 0
            END /* Indexes with scans get some priority */
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#index_analysis after priority score',
            ia.*
        FROM #index_analysis AS ia
        OPTION(RECOMPILE);
    END;

    /* Rule 1: Identify unused indexes */
    IF @dedupe_only = 0
    BEGIN
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
        AND #index_analysis.index_id <> 1 /* Don't disable clustered indexes */
        OPTION(RECOMPILE);
    END;

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
        ia1.consolidation_rule = N'Exact Duplicate',
        ia1.target_index_name =
            CASE
                WHEN ia1.index_priority > ia2.index_priority
                THEN NULL  /* This index is the keeper */
                WHEN ia1.index_priority = ia2.index_priority
                AND  ia1.index_name < ia2.index_name
                THEN NULL  /* When tied, use alphabetical ordering for consistency */
                ELSE ia2.index_name  /* Other index is the keeper */
            END,
        ia1.action =
            CASE
                WHEN ia1.index_priority > ia2.index_priority
                THEN N'KEEP'  /* This index is the keeper */
                WHEN ia1.index_priority = ia2.index_priority
                AND  ia1.index_name < ia2.index_name
                THEN N'KEEP'  /* When tied, use alphabetical ordering for consistency */
                ELSE N'DISABLE'  /* Other index gets disabled */
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
    AND NOT EXISTS
    (
         SELECT
             1/0
         FROM #index_details AS id1
         JOIN #index_details AS id2
           ON  id2.database_id = id1.database_id
           AND id2.object_id = id1.object_id
           AND id2.column_name = id1.column_name
           AND id2.key_ordinal = id1.key_ordinal
         WHERE id1.database_id = ia1.database_id
           AND id1.object_id = ia1.object_id
           AND id1.index_id = ia1.index_id
           AND id2.database_id = ia2.database_id
           AND id2.object_id = ia2.object_id
           AND id2.index_id = ia2.index_id
           AND id1.is_descending_key <> id2.is_descending_key  /* Different sort direction */
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
        WHERE ia1.consolidation_rule = N'Exact Duplicate'
           OR ia2.consolidation_rule = N'Exact Duplicate'
        ORDER BY ia1.index_name
        OPTION(RECOMPILE);
    END;

    /* Rule 3: Key duplicates - matching key columns, different includes */
    UPDATE
        ia1
    SET
        ia1.consolidation_rule = N'Key Duplicate',
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
                THEN N'MERGE INCLUDES'  /* Keep this index but merge includes */
                ELSE N'DISABLE'  /* Other index is keeper, disable this one */
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
                THEN N'Supersedes ' +
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
        ia1.consolidation_rule = N'Key Subset',
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
     AND NOT EXISTS
     (
      SELECT
          1/0
      FROM #index_details AS id1
      JOIN #index_details AS id2
        ON  id2.database_id = id1.database_id
        AND id2.object_id = id1.object_id
        AND id2.column_name = id1.column_name
        AND id2.key_ordinal = id1.key_ordinal
      WHERE id1.database_id = ia1.database_id
        AND id1.object_id = ia1.object_id
        AND id1.index_id = ia1.index_id
        AND id2.database_id = ia2.database_id
        AND id2.object_id = ia2.object_id
        AND id2.index_id = ia2.index_id
        AND id1.is_descending_key <> id2.is_descending_key  /* Different sort direction */
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
        ia2.consolidation_rule = N'Key Superset',
        ia2.action = N'MERGE INCLUDES',  /* The wider index gets merged with includes */
        ia2.superseded_by =
            ISNULL
            (
                ia2.superseded_by +
                ', ',
                ''
            ) +
            N'Supersedes ' +
            ia1.index_name
    FROM #index_analysis AS ia1
    JOIN #index_analysis AS ia2
      ON  ia1.database_id = ia2.database_id
      AND ia1.object_id = ia2.object_id
      AND ia1.target_index_name = ia2.index_name  /* Link from Rule 4 */
    WHERE ia1.consolidation_rule = N'Key Subset'
    AND   ia1.action = N'DISABLE'
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
    WITH
        KeySubsetSuperset AS
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
        WHERE superset.action = N'MERGE INCLUDES'
        AND   subset.action = N'DISABLE'
        AND   superset.consolidation_rule = N'Key Superset'
        AND   subset.consolidation_rule = N'Key Subset'
    )
    UPDATE
        ia
    SET
        ia.included_columns =
        CASE
            /* If both have includes, combine them without duplicates */
            WHEN kss.superset_includes IS NOT NULL
            AND  kss.subset_includes IS NOT NULL
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
                                        N', ' +
                                        t.c.value('.', 'sysname')
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
            WHEN kss.superset_includes IS NULL
            AND  kss.subset_includes IS NOT NULL
            THEN kss.subset_includes
            /* If only superset has includes or neither has includes, keep superset's includes */
            ELSE kss.superset_includes
        END
    FROM #index_analysis AS ia
    JOIN KeySubsetSuperset AS kss
      ON  ia.database_id = kss.database_id
      AND ia.object_id = kss.object_id
      AND ia.index_id = kss.index_id
    WHERE ia.action = N'MERGE INCLUDES'
    OPTION(RECOMPILE);

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
        ia2.superseded_by =
            N'Supersedes ' +
            ia1.index_name
    FROM #index_analysis AS ia1
    JOIN #index_analysis AS ia2
      ON  ia1.database_id = ia2.database_id
      AND ia1.object_id = ia2.object_id
      AND ia1.index_name <> ia2.index_name
      AND ia2.key_columns LIKE (ia1.key_columns + N'%')  /* ia2 has wider key that starts with ia1's key */
      AND ISNULL(ia1.filter_definition, '') = ISNULL(ia2.filter_definition, '')  /* Matching filters */
      /* Exception: If narrower index is unique and wider is not, they should not be merged */
      AND NOT (ia1.is_unique = 1 AND ia2.is_unique = 0)
    WHERE ia1.consolidation_rule = N'Key Subset'  /* Use records just processed in previous UPDATE */
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
        ia1.consolidation_rule = N'Unique Constraint Replacement',
        ia1.action =
            CASE
                WHEN ia1.is_unique = 0
                THEN 'MAKE UNIQUE'  /* Convert to unique index */
                ELSE 'KEEP'  /* Already unique, so just keep it */
            END
    FROM #index_analysis AS ia1
    WHERE ia1.consolidation_rule IS NULL /* Not already processed */
    AND   ia1.action IS NULL /* Not already processed by earlier rules */
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
        ia_uc.consolidation_rule = N'Unique Constraint Replacement',
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
        ia_nc.consolidation_rule = N'Unique Constraint Replacement',
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
        EXISTS
        (
            /* Find unique constraint with matching keys that should be disabled */
            SELECT
                1/0
            FROM #index_analysis AS ia_uc
            JOIN #index_details AS id_uc
              ON  id_uc.database_id = ia_uc.database_id
              AND id_uc.object_id = ia_uc.object_id
              AND id_uc.index_id = ia_uc.index_id
              AND id_uc.is_unique_constraint = 1
            WHERE ia_uc.database_id = ia_nc.database_id
            AND   ia_uc.object_id = ia_nc.object_id
                  /* Check that both indexes have EXACTLY the same key columns */
            AND   ia_uc.key_columns = ia_nc.key_columns
        )
    OPTION(RECOMPILE);

    /* CRITICAL: Ensure that only the unique constraints that exactly match get this treatment */
    /* And remove any incorrect MAKE UNIQUE actions */
    UPDATE
        ia
    SET
        action = NULL,
        consolidation_rule = NULL,
        target_index_name = NULL
    FROM #index_analysis AS ia
    WHERE ia.action = N'MAKE UNIQUE'
    AND NOT EXISTS (
        /* Check if there's a unique constraint with matching keys that points to this index */
        SELECT 1
        FROM #index_analysis AS ia_uc
        WHERE ia_uc.database_id = ia.database_id
        AND   ia_uc.object_id = ia.object_id
        AND   ia_uc.key_columns = ia.key_columns
        AND   ia_uc.action = N'DISABLE'
        AND   ia_uc.target_index_name = ia.index_name
    )
    OPTION(RECOMPILE);

    /* Make sure the nonclustered index has the superseded_by field set correctly */
    UPDATE
        ia_nc
    SET
        ia_nc.superseded_by =
            CASE
                WHEN ia_nc.superseded_by IS NULL
                THEN N'Will replace constraint ' +
                     ia_uc.index_name
                ELSE ia_nc.superseded_by +
                     N', will replace constraint ' + ia_uc.index_name
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
    END;

    /* Rule 8: Identify indexes with same keys but in different order after first column */
    /* This rule flags indexes that have the same set of key columns but ordered differently */
    /* These need manual review as they may be redundant depending on query patterns */
    UPDATE
        ia1
    SET
        ia1.consolidation_rule = N'Same Keys Different Order',
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
            AND   id1.object_id = ia1.object_id
            AND   id1.index_id = ia1.index_id
            AND   id1.is_included_column = 0
            AND   id1.key_ordinal > 0

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
        database_name,
        schema_name,
        table_name,
        index_name,
        consolidation_rule,
        script_type,
        additional_info,
        target_index_name,
        superseded_info,
        original_index_definition,
        script,
        index_size_gb,
        index_rows,
        index_reads,
        index_writes
    )
    SELECT
        result_type = 'SUMMARY',
        sort_order = -1,
        database_name =
            N'processed databases: ' +
            CASE
                WHEN @get_all_databases = 0
                THEN ISNULL(@database_name, N'None')
                ELSE
                    ISNULL
                    (
                        STUFF
                        (
                            (
                                SELECT
                                    N', ' +
                                    d.database_name
                                FROM #databases AS d
                                ORDER BY
                                    d.database_name
                                FOR
                                    XML
                                    PATH(''),
                                    TYPE
                            ).value('.', 'nvarchar(max)'),
                            1,
                            2,
                            N''
                        ),
                        N'None'
                    )
            END,
        schema_name =
            N'skipped databases: ' +
            ISNULL
            (
                STUFF
                (
                    (
                        SELECT
                            N', ' +
                            rbs.database_name +
                            N' (' +
                            rbs.reason +
                            N')'
                        FROM #requested_but_skipped_databases AS rbs
                        ORDER BY
                            rbs.database_name
                        FOR
                            XML
                            PATH(''),
                            TYPE
                    ).value('.', 'nvarchar(MAX)'),
                    1,
                    2,
                    N''
                ),
                N'None'
            ),
        table_name = N'brought to you by erikdarling.com',
        index_name = N'for support: https://code.erikdarling.com/',
        consolidation_rule = N'run date: ' + CONVERT(nvarchar(30), SYSDATETIME(), 120),
        script_type = N'Index Cleanup Scripts',
        additional_info = N'A detailed index analysis report appears after these scripts',
        target_index_name = N'ALWAYS TEST THESE RECOMMENDATIONS',
        superseded_info = N'IN A NON-PRODUCTION ENVIRONMENT FIRST!',
        original_index_definition = N'please enjoy responsibly!',
        script = N'happy index cleaning!',
        index_size_gb = 0,
        index_rows = 0,
        index_reads = 0,
        index_writes = 0
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
              AND candidate.consolidation_rule = N'Key Duplicate'
            ORDER BY
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
                  AND inner_ia.consolidation_rule = N'Key Duplicate'
                GROUP BY
                    inner_ia.index_name
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
      AND ia.consolidation_rule = N'Key Duplicate'
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
    AND   ia.action = N'MERGE INCLUDES'
    AND   ia.consolidation_rule = N'Key Duplicate'
    OPTION(RECOMPILE);

    /* Update the winning index's superseded_by to list all other indexes */
    UPDATE
        ia
    SET
        ia.superseded_by = N'Supersedes ' +
        REPLACE
        (
            kdd.index_list,
            ia.index_name + N', ',
            N''
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
      AND ia1.consolidation_rule = N'Key Duplicate'
      AND ia2.consolidation_rule = N'Key Duplicate'
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
                THEN N'Supersedes ' +
                     isd.subset_index_name
                ELSE ia.superseded_by +
                     N', ' +
                     isd.subset_index_name
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
        SELECT
            table_name = '#index_analysis after all updates',
            ia.*
        FROM #index_analysis AS ia
        OPTION(RECOMPILE);

        RAISERROR('Generating #index_cleanup_results insert, MERGE', 0, 0) WITH NOWAIT;
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
        ORDER BY
            ia.index_name
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
                CASE
                    WHEN EXISTS
                    (
                        SELECT
                            1/0
                        FROM #index_details AS id
                        WHERE id.database_id = ia.database_id
                        AND   id.object_id = ia.object_id
                        AND   id.index_id = ia.index_id
                        AND   id.is_unique_constraint = 1
                    )
                    THEN 'YES'
                    ELSE 'NO'
                END,
            make_unique_target =
                CASE
                    WHEN EXISTS
                    (
                        SELECT
                            1/0
                        FROM #index_analysis AS ia_make
                        WHERE ia_make.database_id = ia.database_id
                        AND   ia_make.object_id = ia.object_id
                        AND   ia_make.action = N'MAKE UNIQUE'
                        AND   ia_make.target_index_name = ia.index_name
                    )
                    THEN 'YES'
                    ELSE 'NO'
                END,
            will_get_script =
                CASE
                    WHEN ia.action = N'DISABLE'
                    AND NOT EXISTS
                    (
                        SELECT 1
                        FROM #index_details AS id_uc
                        WHERE id_uc.database_id = ia.database_id
                        AND id_uc.object_id = ia.object_id
                        AND id_uc.index_id = ia.index_id
                        AND id_uc.is_unique_constraint = 1
                    )
                    THEN 'YES'
                    ELSE 'NO'
                END
        FROM #index_analysis AS ia
        WHERE ia.index_name LIKE 'ix_filtered_%'
        OR    ia.index_name LIKE 'ix_desc_%'
        ORDER BY
            ia.index_name
        OPTION(RECOMPILE);

        /* Debug for all indexes marked with action = DISABLE */
        RAISERROR('All indexes with action = DISABLE:', 0, 0) WITH NOWAIT;
        SELECT
            ia.index_name,
            ia.consolidation_rule,
            ia.action,
            ia.target_index_name
        FROM #index_analysis AS ia
        WHERE ia.action = N'DISABLE'
        ORDER BY
            ia.index_name
        OPTION(RECOMPILE);
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
                WHEN ia.consolidation_rule LIKE 'Unused Index%'
                THEN 25
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
                WHEN ia.consolidation_rule = N'Key Subset'
                THEN N'This index is superseded by a wider index: ' +
                     ISNULL(ia.target_index_name, N'(unknown)')
                WHEN ia.consolidation_rule = N'Exact Duplicate'
                THEN N'This index is an exact duplicate of: ' +
                     ISNULL(ia.target_index_name, N'(unknown)')
                WHEN ia.consolidation_rule = N'Key Duplicate'
                THEN N'This index has the same keys as: ' +
                     ISNULL(ia.target_index_name, N'(unknown)')
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

    /* Add clustered indexes to #index_analysis specifically for compression purposes */
    IF @debug = 1
    BEGIN
        RAISERROR('Adding clustered indexes to #index_analysis for compression', 0, 0) WITH NOWAIT;
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
        fo.database_id,
        fo.database_name,
        fo.schema_id,
        fo.schema_name,
        fo.table_name,
        fo.object_id,
        fo.index_id,
        fo.index_name,
        is_unique =
            CASE
                WHEN ce.can_compress = 1
                THEN id.is_unique
                ELSE NULL
            END,
        key_columns =
            STUFF
            (
              (
                SELECT
                    N', ' +
                    QUOTENAME(id2.column_name) +
                    CASE
                        WHEN id2.is_descending_key = 1
                        THEN N' DESC'
                        ELSE N''
                    END
                FROM #index_details id2
                WHERE id2.object_id = fo.object_id
                AND   id2.index_id = fo.index_id
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
        included_columns = NULL, /* Clustered indexes cannot have included columns */
        filter_definition = NULL, /* Clustered indexes cannot have filters */
        original_index_definition =
            CASE
                WHEN id.is_primary_key = 1
                THEN
                    N'ALTER TABLE ' +
                    QUOTENAME(fo.database_name) +
                    N'.' +
                    QUOTENAME(fo.schema_name) +
                    N'.' +
                    QUOTENAME(fo.table_name) +
                    N' ADD CONSTRAINT ' +
                    QUOTENAME(fo.index_name) +
                    N' PRIMARY KEY ' +
                    CASE
                        WHEN ce.index_id = 1
                        THEN N'CLUSTERED'
                        ELSE N'NONCLUSTERED'
                    END
                    +
                    N' (' +
                    STUFF
                    (
                      (
                        SELECT
                            N', ' +
                            QUOTENAME(id2.column_name) +
                            CASE
                                WHEN id2.is_descending_key = 1
                                THEN N' DESC'
                                ELSE N''
                            END
                        FROM #index_details id2
                        WHERE id2.object_id = fo.object_id
                        AND   id2.index_id = fo.index_id
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
                    N');'
                WHEN id.is_primary_key = 0
                THEN N'CREATE ' +
                    CASE
                        WHEN id.is_unique = 1
                        THEN N'UNIQUE '
                        ELSE N''
                    END +
                N'CLUSTERED INDEX' +
                QUOTENAME(fo.index_name) +
                N' ON ' +
                QUOTENAME(fo.database_name) +
                N'.' +
                QUOTENAME(fo.schema_name) +
                N'.' +
                QUOTENAME(fo.table_name) +
                N' (' +
                STUFF
                (
                  (
                    SELECT
                        N', ' +
                        QUOTENAME(id2.column_name) +
                        CASE
                            WHEN id2.is_descending_key = 1
                            THEN N' DESC'
                            ELSE N''
                        END
                    FROM #index_details id2
                    WHERE id2.object_id = fo.object_id
                    AND   id2.index_id = fo.index_id
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
                N');'
            ELSE N''
        END
    FROM #filtered_objects AS fo
    JOIN #index_details AS id
      ON  id.database_id = fo.database_id
      AND id.object_id = fo.object_id
      AND id.index_id = fo.index_id
      AND id.key_ordinal = 1 /* Only need one row per index */
    JOIN #compression_eligibility AS ce
      ON  ce.database_id = fo.database_id
      AND ce.object_id = fo.object_id
      AND ce.index_id = fo.index_id
    WHERE
    (
         fo.index_id = 1 /* Clustered indexes only */
      OR id.is_primary_key = 1
    )
    AND   ce.can_compress = 1 /* Only those eligible for compression */
    /* Only add if not already in #index_analysis */
    AND   NOT EXISTS
    (
        SELECT
            1/0
        FROM #index_analysis AS ia
        WHERE ia.database_id = fo.database_id
        AND   ia.object_id = fo.object_id
        AND   ia.index_id = fo.index_id
    )
    OPTION(RECOMPILE);

    /* If any clustered indexes were added, mark them as KEEP */
    UPDATE
        #index_analysis
    SET
        #index_analysis.action = N'KEEP'
    WHERE #index_analysis.index_id = 1 /* Clustered indexes */
    AND   #index_analysis.action IS NULL;

    /* Update index priority for clustered indexes to ensure they're not chosen for deduplication */
    UPDATE
        #index_analysis
    SET
        #index_analysis.index_priority = 1000 /* Maximum priority */
    WHERE #index_analysis.index_id = 1 /* Clustered indexes */
    AND   #index_analysis.index_priority IS NULL;

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '#index_analysis after adding clustered indexes',
            *
        FROM #index_analysis AS ia
        WHERE ia.index_id = 1
        OPTION(RECOMPILE);
    END;

    /* Insert compression scripts for remaining indexes */
    IF @debug = 1
    BEGIN
        RAISERROR('Generating #index_cleanup_results insert, COMPRESS', 0, 0) WITH NOWAIT;
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
            CASE
                WHEN @supports_optimize_for_sequential_key = 1
                AND EXISTS
                (
                    SELECT
                        1/0
                    FROM #index_details AS id_ofsk
                    WHERE id_ofsk.database_id = ia.database_id
                    AND   id_ofsk.object_id = ia.object_id
                    AND   id_ofsk.index_id = ia.index_id
                    AND   id_ofsk.optimize_for_sequential_key = 1
                )
                THEN N', OPTIMIZE_FOR_SEQUENTIAL_KEY = ON'
                ELSE N''
            END +
            N')',
        additional_info = N'Compression type: All Partitions',
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
        AND ia_uc.consolidation_rule = N'Unique Constraint Replacement'
    OPTION(RECOMPILE);

    /* Insert per-partition compression scripts */
    IF @debug = 1
    BEGIN
        RAISERROR('Generating #index_cleanup_results insert, COMPRESS_PARTITION', 0, 0) WITH NOWAIT;
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
        script_type = 'COMPRESSION SCRIPT - PARTITION',
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
                CASE
                    WHEN @supports_optimize_for_sequential_key = 1
                    AND EXISTS
                    (
                        SELECT
                            1/0
                        FROM #index_details AS id_ofsk
                        WHERE id_ofsk.database_id = ia.database_id
                        AND   id_ofsk.object_id = ia.object_id
                        AND   id_ofsk.index_id = ia.index_id
                        AND   id_ofsk.optimize_for_sequential_key = 1
                    )
                    THEN N', OPTIMIZE_FOR_SEQUENTIAL_KEY = ON'
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
        script_type = 'COMPRESSION INELIGIBLE',
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
                WHEN ia.consolidation_rule = N'Same Keys Different Order'
                THEN N'This index has the same key columns as ' +
                     ISNULL(ia.target_index_name, N'(unknown)') +
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


    /* Insert kept indexes into results - Consolidated all kept indexes logic in one place */
    IF @debug = 1
    BEGIN
        RAISERROR('Generating #index_cleanup_results insert, KEPT INDEXES', 0, 0) WITH NOWAIT;
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
        index_writes,
        script
    )
    SELECT DISTINCT
        result_type = 'KEPT',
        sort_order = 95, /* Put kept indexes at the end */
        ia.database_name,
        ia.schema_name,
        ia.table_name,
        ia.index_name,
        script_type =
            CASE
                /* Add compression status to script_type */
                WHEN ce.can_compress = 1
                THEN 'KEPT - NEEDS COMPRESSION'
                ELSE 'KEPT'
            END,
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
        id.user_updates,
        /* Include compression script directly on KEPT records when needed */
        script =
            CASE
                WHEN ce.can_compress = 1
                THEN N'ALTER INDEX ' +
                    QUOTENAME(ia.index_name) +
                    N' ON ' +
                    QUOTENAME(ia.database_name) +
                    N'.' +
                    QUOTENAME(ia.schema_name) +
                    N'.' +
                    QUOTENAME(ia.table_name) +
                    CASE
                        WHEN ps_part.partition_function_name IS NOT NULL
                        THEN N' REBUILD PARTITION = ALL'
                        ELSE N' REBUILD'
                    END +
                    N' WITH (FILLFACTOR = 100, SORT_IN_TEMPDB = ON, ONLINE = ' +
                    CASE
                        WHEN @online = 1
                        THEN N'ON'
                        ELSE N'OFF'
                    END +
                    N', DATA_COMPRESSION = PAGE)'
                ELSE NULL
            END
    FROM #index_analysis AS ia
    LEFT JOIN #partition_stats AS ps
      ON  ia.database_id = ps.database_id
      AND ia.object_id = ps.object_id
      AND ia.index_id = ps.index_id
    LEFT JOIN
    (
        /* Get the partition info for each index */
        SELECT
            ps.database_id,
            ps.object_id,
            ps.index_id,
            ps.partition_function_name
        FROM #partition_stats ps
        GROUP BY
            ps.database_id,
            ps.object_id,
            ps.index_id,
            ps.partition_function_name
    )
      AS ps_part
      ON  ia.database_id = ps_part.database_id
      AND ia.object_id = ps_part.object_id
      AND ia.index_id = ps_part.index_id
    LEFT JOIN #index_details AS id
      ON  id.database_id = ia.database_id
      AND id.object_id = ia.object_id
      AND id.index_id = ia.index_id
      AND id.is_included_column = 0 /* Get only one row per index */
      AND id.key_ordinal > 0
    LEFT JOIN #compression_eligibility AS ce
      ON  ia.database_id = ce.database_id
      AND ia.object_id = ce.object_id
      AND ia.index_id = ce.index_id
    /* Check that this index is not already in the results */
    WHERE NOT EXISTS
    (
        SELECT
            1/0
        FROM #index_cleanup_results AS ir
        WHERE ir.database_name = ia.database_name
        AND   ir.schema_name = ia.schema_name
        AND   ir.table_name = ia.table_name
        AND   ir.index_name = ia.index_name
        AND   ir.script_type NOT LIKE N'COMPRESSION%'
    )
    /* Include only indexes that should be kept */
    AND
    (
        ia.action = N'KEEP'
        OR
        (
          ia.action IS NULL
          AND ia.index_id > 0
        )
    )
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
        total_size_gb,
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
        index_count = COUNT_BIG(*),
        total_size_gb = SUM(ps.total_space_gb),
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
        /* Space savings from cleanup - only count DISABLE actions */
        space_saved_gb =
            SUM
            (
                CASE
                    WHEN ia.action = N'DISABLE'
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
        /* Total conservative savings - only count DISABLE actions for space savings */
        total_min_savings_gb =
            SUM
            (
                CASE
                    WHEN ia.action = N'DISABLE'
                    THEN ps.total_space_gb
                    WHEN (ia.action IS NULL OR ia.action = N'KEEP')
                    AND   ce.can_compress = 1
                    THEN ps.total_space_gb * 0.20
                    ELSE 0
                END
            ),
        /* Total optimistic savings - only count DISABLE actions for space savings */
        total_max_savings_gb =
            SUM
            (
                CASE
                    WHEN ia.action = N'DISABLE'
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
    WHERE ia.index_id > 1
    OPTION(RECOMPILE);

    /* Return enhanced database impact summaries */
    IF @debug = 1
    BEGIN
        RAISERROR('Generating enhanced summary reports', 0, 0) WITH NOWAIT;
    END;

    /* Insert database-level summaries */
    IF @debug = 1
    BEGIN
        RAISERROR('Generating #index_reporting_stats insert, DATABASE', 0, 0) WITH NOWAIT;
    END;

    INSERT INTO
        #index_reporting_stats
    WITH
        (TABLOCK)
    (
        summary_level,
        database_name,
        index_count,
        total_size_gb,
        total_rows,
        indexes_to_merge,
        unused_indexes,
        unused_size_gb,
        compression_min_savings_gb,
        compression_max_savings_gb,
        total_min_savings_gb,
        total_max_savings_gb,
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
        index_count =
            COUNT_BIG(DISTINCT CONCAT(ps.object_id, N'.', ps.index_id)),
        total_size_gb = SUM(DISTINCT ps.total_space_gb),
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
            (
                SELECT
                    SUM(subps.total_space_gb)
                FROM #partition_stats AS subps
                JOIN #index_analysis AS subia
                  ON  subps.database_id = subia.database_id
                  AND subps.object_id = subia.object_id
                  AND subps.index_id = subia.index_id
                WHERE subia.action = N'DISABLE'
                AND   subia.database_id = ps.database_id
            ),
        /* Conservative compression savings estimate (20%) */
        compression_min_savings_gb =
            (
                SELECT
                    SUM(subps.total_space_gb * 0.20)
                FROM #partition_stats AS subps
                JOIN #index_analysis AS subia
                  ON  subps.database_id = subia.database_id
                  AND subps.object_id = subia.object_id
                  AND subps.index_id = subia.index_id
                JOIN #compression_eligibility AS subce
                  ON  subce.database_id = subia.database_id
                  AND subce.object_id = subia.object_id
                  AND subce.index_id = subia.index_id
                WHERE (subia.action IS NULL OR subia.action = N'KEEP')
                AND   subce.can_compress = 1
                AND   subia.database_id = ps.database_id
            ),
        /* Optimistic compression savings estimate (60%) */
        compression_max_savings_gb =
            (
                SELECT
                    SUM(subps.total_space_gb * 0.60)
                FROM #partition_stats AS subps
                JOIN #index_analysis AS subia
                  ON  subps.database_id = subia.database_id
                  AND subps.object_id = subia.object_id
                  AND subps.index_id = subia.index_id
                JOIN #compression_eligibility AS subce
                  ON  subce.database_id = subia.database_id
                  AND subce.object_id = subia.object_id
                  AND subce.index_id = subia.index_id
                WHERE (subia.action IS NULL OR subia.action = N'KEEP')
                AND   subce.can_compress = 1
                AND   subia.database_id = ps.database_id
            ),
        /* Total conservative savings */
        total_min_savings_gb =
            (
                SELECT
                    SUM
                    (
                        CASE
                            WHEN subia.action = N'DISABLE'
                            THEN subps.total_space_gb
                            WHEN (subia.action IS NULL OR subia.action = N'KEEP')
                            AND   subce.can_compress = 1
                            THEN subps.total_space_gb * 0.20
                            ELSE 0
                        END
                    )
                FROM #partition_stats AS subps
                JOIN #index_analysis AS subia
                  ON  subps.database_id = subia.database_id
                  AND subps.object_id = subia.object_id
                  AND subps.index_id = subia.index_id
                LEFT JOIN #compression_eligibility AS subce
                  ON  subce.database_id = subia.database_id
                  AND subce.object_id = subia.object_id
                  AND subce.index_id = subia.index_id
                WHERE subia.database_id = ps.database_id
            ),
        /* Total optimistic savings */
        total_max_savings_gb =
            (
                SELECT
                    SUM
                    (
                        CASE
                            WHEN subia.action = N'DISABLE'
                            THEN subps.total_space_gb
                            WHEN (subia.action IS NULL OR subia.action = N'KEEP')
                            AND   subce.can_compress = 1
                            THEN subps.total_space_gb * 0.60
                            ELSE 0
                        END
                    )
                FROM #partition_stats AS subps
                JOIN #index_analysis AS subia
                  ON  subps.database_id = subia.database_id
                  AND subps.object_id = subia.object_id
                  AND subps.index_id = subia.index_id
                LEFT JOIN #compression_eligibility AS subce
                  ON  subce.database_id = subia.database_id
                  AND subce.object_id = subia.object_id
                  AND subce.index_id = subia.index_id
                WHERE subia.database_id = ps.database_id
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

    INSERT INTO
        #index_reporting_stats
    WITH
        (TABLOCK)
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
        compression_min_savings_gb,
        compression_max_savings_gb,
        total_min_savings_gb,
        total_max_savings_gb,
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
        total_size_gb = SUM(DISTINCT ps.total_space_gb),
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
            (
                SELECT
                    SUM(subps.total_space_gb)
                FROM #partition_stats AS subps
                JOIN #index_analysis AS subia
                  ON  subps.database_id = subia.database_id
                  AND subps.object_id = subia.object_id
                  AND subps.index_id = subia.index_id
                WHERE subia.action = N'DISABLE'
                AND   subia.database_id = ps.database_id
                AND   subia.schema_id = ps.schema_id
                AND   subia.object_id = ps.object_id
            ),
        /* Conservative compression savings estimate (20%) */
        compression_min_savings_gb =
            (
                SELECT
                    SUM(subps.total_space_gb * 0.20)
                FROM #partition_stats AS subps
                JOIN #index_analysis AS subia
                  ON  subps.database_id = subia.database_id
                  AND subps.object_id = subia.object_id
                  AND subps.index_id = subia.index_id
                JOIN #compression_eligibility AS subce
                  ON  subce.database_id = subia.database_id
                  AND subce.object_id = subia.object_id
                  AND subce.index_id = subia.index_id
                WHERE (subia.action IS NULL OR subia.action = N'KEEP')
                AND   subce.can_compress = 1
                AND   subia.database_id = ps.database_id
                AND   subia.schema_id = ps.schema_id
                AND   subia.object_id = ps.object_id
            ),
        /* Optimistic compression savings estimate (60%) */
        compression_max_savings_gb =
            (
                SELECT
                    SUM(subps.total_space_gb * 0.60)
                FROM #partition_stats AS subps
                JOIN #index_analysis AS subia
                  ON  subps.database_id = subia.database_id
                  AND subps.object_id = subia.object_id
                  AND subps.index_id = subia.index_id
                JOIN #compression_eligibility AS subce
                  ON  subce.database_id = subia.database_id
                  AND subce.object_id = subia.object_id
                  AND subce.index_id = subia.index_id
                WHERE (subia.action IS NULL OR subia.action = N'KEEP')
                AND   subce.can_compress = 1
                AND   subia.database_id = ps.database_id
                AND   subia.schema_id = ps.schema_id
                AND   subia.object_id = ps.object_id
            ),
        /* Total conservative savings */
        total_min_savings_gb =
            (
                SELECT
                    SUM
                    (
                        CASE
                            WHEN subia.action = N'DISABLE'
                            THEN subps.total_space_gb
                            WHEN (subia.action IS NULL OR subia.action = N'KEEP')
                            AND   subce.can_compress = 1
                            THEN subps.total_space_gb * 0.20
                            ELSE 0
                        END
                    )
                FROM #partition_stats AS subps
                JOIN #index_analysis AS subia
                  ON  subps.database_id = subia.database_id
                  AND subps.object_id = subia.object_id
                  AND subps.index_id = subia.index_id
                LEFT JOIN #compression_eligibility AS subce
                  ON  subce.database_id = subia.database_id
                  AND subce.object_id = subia.object_id
                  AND subce.index_id = subia.index_id
                WHERE subia.database_id = ps.database_id
                AND   subia.schema_id = ps.schema_id
                AND   subia.object_id = ps.object_id
            ),
        /* Total optimistic savings */
        total_max_savings_gb =
            (
                SELECT
                    SUM
                    (
                        CASE
                            WHEN subia.action = N'DISABLE'
                            THEN subps.total_space_gb
                            WHEN (subia.action IS NULL OR subia.action = N'KEEP')
                            AND   subce.can_compress = 1
                            THEN subps.total_space_gb * 0.60
                            ELSE 0
                        END
                    )
                FROM #partition_stats AS subps
                JOIN #index_analysis AS subia
                  ON  subps.database_id = subia.database_id
                  AND subps.object_id = subia.object_id
                  AND subps.index_id = subia.index_id
                LEFT JOIN #compression_eligibility AS subce
                  ON  subce.database_id = subia.database_id
                  AND subce.object_id = subia.object_id
                  AND subce.index_id = subia.index_id
                WHERE subia.database_id = ps.database_id
                AND   subia.schema_id = ps.schema_id
                AND   subia.object_id = ps.object_id
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
        SELECT
            table_name = '#index_reporting_stats',
            irs.*
        FROM #index_reporting_stats AS irs
        OPTION(RECOMPILE);

        SELECT
            table_name = '#index_cleanup_results',
            icr.*
        FROM #index_cleanup_results AS icr
        OPTION(RECOMPILE);
    END;

        /* Get the next database */
        FETCH NEXT
        FROM @database_cursor
        INTO
            @current_database_name,
            @current_database_id;
    END;

    IF @debug = 1
    BEGIN
        RAISERROR('Generating #index_cleanup_results, RESULTS', 0, 0) WITH NOWAIT;
    END;

    SELECT
        /* First, show the information needed to understand the script */
        script_type =
            CASE
                WHEN ir.result_type = 'KEPT'
                AND  ir.script_type IS NULL
                THEN 'KEPT'
                ELSE ir.script_type
            END,
        ir.additional_info,
        /* Then show identifying information for the index */
        ir.database_name,
        ir.schema_name,
        ir.table_name,
        ir.index_name,
        /* Then show relationship information */
        consolidation_rule = ISNULL(ir.consolidation_rule, N'N/A'),
        target_index_name = ISNULL(ir.target_index_name, N'N/A'),
        /* Include superseded_by info for winning indexes */
        superseded_info =
            CASE
                WHEN ia.superseded_by IS NOT NULL
                THEN ia.superseded_by
                ELSE ISNULL(ir.superseded_info, N'N/A')
            END,
        /* Add size and usage metrics */
        index_size_gb =
            CASE
                WHEN ir.result_type = 'SUMMARY'
                THEN '0.0000'
                ELSE FORMAT(ISNULL(ir.index_size_gb, 0), 'N4')
            END,
        index_rows =
            CASE
                WHEN ir.result_type = 'SUMMARY'
                THEN '0'
                ELSE FORMAT(ISNULL(ir.index_rows, 0), 'N0')
            END,
        index_reads =
            CASE
                WHEN ir.result_type = 'SUMMARY'
                THEN '0'
                ELSE FORMAT(ISNULL(ir.index_reads, 0), 'N0')
            END,
        index_writes =
            CASE
                WHEN ir.result_type = 'SUMMARY'
                THEN '0'
                ELSE FORMAT(ISNULL(ir.index_writes, 0), 'N0')
            END,
        original_index_definition =
            CASE
                WHEN ir.result_type = 'SUMMARY'
                THEN N'please enjoy responsibly!'
                ELSE ia.original_index_definition
            END,
        /* Finally show the actual script */
        ir.script
    FROM
    (
        /* Use a subquery with ROW_NUMBER to ensure we only get one row per index */
        SELECT
            irs.*,
            ROW_NUMBER() OVER
            (
                PARTITION BY
                    irs.database_name,
                    irs.schema_name,
                    irs.table_name,
                    irs.index_name,
                    irs.script_type
                ORDER BY
                    irs.result_type DESC /* Prefer non-NULL result types */
            ) AS rn
        FROM #index_cleanup_results AS irs
    ) AS ir
    LEFT JOIN #index_analysis AS ia
      ON  ir.database_name = ia.database_name
      AND ir.schema_name = ia.schema_name
      AND ir.table_name = ia.table_name
      AND ir.index_name = ia.index_name
    WHERE ir.rn = 1 /* Take only the first row for each index */
    ORDER BY
        ir.database_name,
        ir.sort_order,
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

    /*
    This section now REPLACES the existing summary view rather than supplementing it
    We'll modify the existing query below rather than creating new output panes
    */

    /* Return streamlined reporting statistics focused on key metrics */
    IF @debug = 1
    BEGIN
        RAISERROR('Generating #index_reporting_stats, REPORT', 0, 0) WITH NOWAIT;
    END;

    SELECT
        /* Basic identification with enhanced naming */
        level =
            CASE
                WHEN irs.summary_level = 'SUMMARY'
                THEN 'ANALYZED OBJECT DETAILS'
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
        schema_name =
            CASE
                WHEN irs.summary_level = 'SUMMARY'
                THEN ISNULL(irs.schema_name, 'ALWAYS TEST THESE RECOMMENDATIONS')
                WHEN irs.summary_level = 'DATABASE'
                THEN N'N/A'
                ELSE irs.schema_name
            END,
        table_name =
            CASE
                WHEN irs.summary_level = 'SUMMARY'
                THEN ISNULL(irs.table_name, 'IN A NON-PRODUCTION ENVIRONMENT FIRST!')
                WHEN irs.summary_level = 'DATABASE'
                THEN N'N/A'
                ELSE irs.table_name
            END,

        /* ===== Section 1: Index Counts ===== */
        /* Tables analyzed (summary only) */
        tables_analyzed =
            CASE
                WHEN irs.summary_level = 'SUMMARY'
                THEN FORMAT(irs.tables_analyzed, 'N0')
                WHEN irs.summary_level = 'DATABASE'
                THEN FORMAT
                     (
                       (
                           SELECT
                               COUNT_BIG(DISTINCT CONCAT(ia.schema_id, N'.', ia.object_id))
                           FROM #index_analysis AS ia
                           WHERE ia.database_name = irs.database_name
                       ),
                       'N0'
                     )
                WHEN irs.summary_level = 'TABLE'
                THEN FORMAT(1, 'N0') /* Each table row represents 1 analyzed table */
                ELSE FORMAT(0, 'N0') /* Show 0 instead of NULL */
            END,

        /* Total indexes */
        total_indexes = FORMAT(ISNULL(irs.index_count, 0), 'N0'),

        /* Removable indexes - report consistent values across levels */
        removable_indexes =
            CASE
                WHEN irs.summary_level = 'SUMMARY'
                THEN FORMAT(ISNULL(irs.indexes_to_disable, 0), 'N0') /* Indexes that will be disabled based on analysis */
                ELSE FORMAT(ISNULL(irs.unused_indexes, 0), 'N0') /* Unused indexes at database/table level */
            END,

        /* Show mergeable indexes across all levels */
        mergeable_indexes = FORMAT(ISNULL(irs.indexes_to_merge, 0), 'N0'),

        /* Percent of indexes that can be removed */
        percent_removable =
            CASE
                WHEN irs.summary_level = 'SUMMARY'
                AND  irs.index_count > 0
                THEN FORMAT(100.0 * ISNULL(irs.indexes_to_disable, 0)
                     / NULLIF(irs.index_count, 0), 'N1') + '%'
                WHEN irs.index_count > 0
                THEN FORMAT(100.0 * ISNULL(irs.unused_indexes, 0)
                     / NULLIF(irs.index_count, 0), 'N1') + '%'
                ELSE '0.0%'
            END,

        /* ===== Section 2: Size and Space Savings with Before/After comparison ===== */
        /* Current size in GB */
        current_size_gb = FORMAT(ISNULL(irs.total_size_gb, 0), 'N2'),

        /* Size after cleanup - added this as new metric */
        size_after_cleanup_gb =
            CASE
                WHEN irs.summary_level = 'SUMMARY'
                THEN FORMAT(ISNULL(irs.total_size_gb, 0) - ISNULL(irs.space_saved_gb, 0), 'N2')
                ELSE FORMAT(ISNULL(irs.total_size_gb, 0) - ISNULL(irs.unused_size_gb, 0), 'N2')
            END,

        /* Size that can be saved through cleanup */
        space_saved_gb =
            CASE
                WHEN irs.summary_level = 'SUMMARY'
                THEN FORMAT(ISNULL(irs.space_saved_gb, 0), 'N2')
                ELSE FORMAT(ISNULL(irs.unused_size_gb, 0), 'N2')
            END,

        /* Space reduction percentage - added this as new metric */
        space_reduction_percent =
            CASE
                WHEN ISNULL(irs.total_size_gb, 0) > 0
                THEN
                    CASE
                        WHEN irs.summary_level = 'SUMMARY'
                        THEN FORMAT((ISNULL(irs.space_saved_gb, 0) /
                             NULLIF(irs.total_size_gb, 0)) * 100, 'N1') + '%'
                        ELSE FORMAT((ISNULL(irs.unused_size_gb, 0) /
                             NULLIF(irs.total_size_gb, 0)) * 100, 'N1') + '%'
                    END
                ELSE '0.0%'
            END,

        /* ===== Additional Space Savings from Compression ===== */
        /* Conservative compression estimate (20%) */
        compression_savings_potential =
            N'minimum: ' +
            FORMAT(ISNULL(irs.compression_min_savings_gb, 0), 'N2') +
            N' GB maximum ' +
            FORMAT(ISNULL(irs.compression_max_savings_gb, 0), 'N2')
            + N'GB',
        compression_savings_potential_total =
            N'total minimum: ' +
            FORMAT(ISNULL(irs.total_min_savings_gb, 0), 'N2') +
            N' GB total maximum: ' +
            FORMAT(ISNULL(irs.total_max_savings_gb, 0), 'N2') +
            N'GB',

        /* ===== Section for Computed Columns with UDFs ===== */
        computed_columns_with_udfs =
            CASE
                WHEN irs.summary_level = 'TABLE'
                THEN
                    CONVERT
                    (
                        nvarchar(20),
                        (
                          SELECT
                              COUNT_BIG(*)
                          FROM #computed_columns_analysis AS cca
                          WHERE cca.database_name = irs.database_name
                          AND   cca.schema_name = irs.schema_name
                          AND   cca.table_name = irs.table_name
                          AND   cca.contains_udf = 1
                        )
                    )
                WHEN irs.summary_level = 'DATABASE'
                THEN
                    CONVERT
                    (
                        nvarchar(20),
                        (
                          SELECT
                              COUNT_BIG(*)
                          FROM #computed_columns_analysis AS cca
                          WHERE cca.database_name = irs.database_name
                          AND   cca.contains_udf = 1
                        )
                    )
                WHEN irs.summary_level = 'SUMMARY'
                THEN
                    CONVERT
                    (
                        nvarchar(20),
                        (
                          SELECT
                              COUNT_BIG(*)
                          FROM #computed_columns_analysis AS cca
                          WHERE cca.contains_udf = 1
                        )
                    )
                ELSE '0'
            END,

        /* ===== Section for Check Constraints with UDFs ===== */
        check_constraints_with_udfs =
            CASE
                WHEN irs.summary_level = 'TABLE'
                THEN
                    CONVERT
                    (
                        nvarchar(20),
                        (
                          SELECT
                              COUNT_BIG(*)
                          FROM #check_constraints_analysis AS cca
                          WHERE cca.database_name = irs.database_name
                          AND   cca.schema_name = irs.schema_name
                          AND   cca.table_name = irs.table_name
                          AND   cca.contains_udf = 1
                        )
                    )
                WHEN irs.summary_level = 'DATABASE'
                THEN
                    CONVERT
                    (
                        nvarchar(20),
                        (
                          SELECT
                              COUNT_BIG(*)
                          FROM #check_constraints_analysis AS cca
                          WHERE cca.database_name = irs.database_name
                          AND   cca.contains_udf = 1
                        )
                    )
                WHEN irs.summary_level = 'SUMMARY'
                THEN
                    CONVERT
                    (
                        nvarchar(20),
                        (
                          SELECT
                              COUNT_BIG(*)
                          FROM #check_constraints_analysis AS cca
                          WHERE cca.contains_udf = 1
                        )
                    )
                ELSE '0'
            END,

        /* ===== Section for Filtered Indexes Analysis ===== */
        filtered_indexes_needing_includes =
            CASE
                WHEN irs.summary_level = 'TABLE'
                THEN
                    CONVERT
                    (
                        nvarchar(20),
                        (
                          SELECT
                              COUNT_BIG(*)
                          FROM #filtered_index_columns_analysis AS fica
                          WHERE fica.database_name = irs.database_name
                          AND   fica.schema_name = irs.schema_name
                          AND   fica.table_name = irs.table_name
                          AND   fica.should_include_filter_columns = 1
                        )
                    )
                WHEN irs.summary_level = 'DATABASE'
                THEN
                    CONVERT
                    (
                        nvarchar(20),
                        (
                          SELECT
                              COUNT_BIG(*)
                          FROM #filtered_index_columns_analysis AS fica
                          WHERE fica.database_name = irs.database_name
                          AND   fica.should_include_filter_columns = 1
                        )
                    )
                WHEN irs.summary_level = 'SUMMARY'
                THEN
                    CONVERT
                    (
                        nvarchar(20),
                        (
                          SELECT
                              COUNT_BIG(*)
                          FROM #filtered_index_columns_analysis AS fica
                          WHERE fica.should_include_filter_columns = 1
                        )
                    )
                ELSE '0'
            END,

        /* ===== Section 3: Table and Usage Statistics ===== */
        /* Row count */
        total_rows = FORMAT(ISNULL(irs.total_rows, 0), 'N0'),

        /* Total reads - combined total and breakdown */
        reads_breakdown =
            CASE
                WHEN irs.summary_level <> 'SUMMARY'
                THEN FORMAT(ISNULL(irs.total_reads, 0), 'N0') +
                     ' (' +
                     FORMAT(ISNULL(irs.user_seeks, 0), 'N0') +
                     ' seeks, ' +
                     FORMAT(ISNULL(irs.user_scans, 0), 'N0') +
                     ' scans, ' +
                     FORMAT(ISNULL(irs.user_lookups, 0), 'N0') +
                     ' lookups)'
                ELSE 'N/A'
            END,

        /* Total writes */
        writes =
            CASE
                WHEN irs.summary_level = 'SUMMARY'
                THEN 'N/A'
                WHEN irs.summary_level <> 'SUMMARY'
                THEN FORMAT(ISNULL(irs.total_writes, 0), 'N0')
                ELSE '0'
            END,

        /* Write operations saved - added as new metric */
        daily_write_ops_saved =
            CASE
                WHEN irs.summary_level = 'SUMMARY'
                THEN 'N/A' /* For SUMMARY row, use N/A to be consistent with other metrics */
                WHEN irs.summary_level = 'DATABASE'
                THEN 'N/A'
                WHEN irs.summary_level = 'TABLE'
                THEN
                    /* For TABLE rows, calculate estimated savings */
                    CASE
                        WHEN ISNULL(irs.unused_indexes, 0) > 0
                        THEN FORMAT
                             (
                                 CONVERT
                                 (
                                     decimal(38,2),
                                     ISNULL
                                     (
                                         irs.user_updates /
                                         NULLIF
                                         (
                                             CONVERT
                                             (
                                                 decimal(38,2),
                                                 (
                                                   SELECT TOP (1)
                                                       irs2.server_uptime_days
                                                   FROM #index_reporting_stats AS irs2
                                                   WHERE irs2.summary_level = 'SUMMARY'
                                                 )
                                             ),
                                             0
                                         ) *
                                         (
                                           ISNULL
                                           (
                                               irs.unused_indexes,
                                               0
                                           ) /
                                           NULLIF
                                           (
                                               CONVERT
                                               (
                                                   decimal(38,2),
                                                   irs.index_count
                                               ),
                                               0
                                           )
                                         ),
                                         0
                                     )
                                 ),
                                 'N0'
                             )
                        /* Rows without unused indexes have no savings */
                        ELSE '0'
                    END
                ELSE '0'
            END,

        /* ===== Section 4: Consolidated Performance Metrics ===== */
        /* Total count of lock waits (row + page) */
        lock_wait_count =
            CASE
                WHEN irs.summary_level = 'SUMMARY'
                THEN 'N/A'
                WHEN irs.summary_level <> 'SUMMARY'
                THEN FORMAT(ISNULL(irs.row_lock_wait_count, 0) +
                     ISNULL(irs.page_lock_wait_count, 0), 'N0')
                ELSE '0'
            END,

        /* Lock waits saved - new column */
        daily_lock_waits_saved =
            CASE
                WHEN irs.summary_level = 'SUMMARY'
                THEN 'N/A' /* For SUMMARY row, use N/A to be consistent with other metrics */
                WHEN irs.summary_level = 'DATABASE'
                THEN 'N/A'
                WHEN irs.summary_level = 'TABLE'
                THEN
                    /* For TABLE rows, calculate estimated savings */
                    CASE
                        WHEN ISNULL(irs.unused_indexes, 0) > 0
                        THEN
                            FORMAT
                            (
                                CONVERT
                                (
                                    decimal(38,2),
                                    ISNULL
                                    (
                                        (irs.row_lock_wait_count + irs.page_lock_wait_count) /
                                        NULLIF
                                        (
                                            CONVERT
                                            (
                                                decimal(38,2),
                                                (
                                                  SELECT TOP (1)
                                                      irs2.server_uptime_days
                                                  FROM #index_reporting_stats AS irs2
                                                  WHERE irs2.summary_level = 'SUMMARY'
                                                )
                                            ),
                                            0
                                        ) *
                                        (
                                          ISNULL
                                          (
                                              irs.unused_indexes,
                                              0
                                          ) /
                                          NULLIF
                                          (
                                              CONVERT
                                              (
                                                  decimal(38,2),
                                                  irs.index_count
                                              ),
                                              0
                                          )
                                        ),
                                        0
                                    )
                                ),
                                'N0'
                            )
                        /* Rows without unused indexes have no savings */
                        ELSE '0'
                    END
                ELSE '0'
            END,

        /* Average lock wait time in ms */
        avg_lock_wait_ms =
            CASE
                WHEN irs.summary_level = 'SUMMARY'
                THEN 'N/A'
                WHEN irs.summary_level <> 'SUMMARY'
                AND (ISNULL(irs.row_lock_wait_count, 0) +
                     ISNULL(irs.page_lock_wait_count, 0)) > 0
                THEN FORMAT(1.0 * (ISNULL(irs.row_lock_wait_in_ms, 0) +
                     ISNULL(irs.page_lock_wait_in_ms, 0)) /
                     NULLIF(ISNULL(irs.row_lock_wait_count, 0) +
                     ISNULL(irs.page_lock_wait_count, 0), 0), 'N2')
                ELSE '0'
            END,

        /* Total count of latch waits (page + io) - new column */
        latch_wait_count =
            CASE
                WHEN irs.summary_level = 'SUMMARY'
                THEN 'N/A'
                WHEN irs.summary_level <> 'SUMMARY'
                THEN FORMAT(ISNULL(irs.page_latch_wait_count, 0) +
                     ISNULL(irs.page_io_latch_wait_count, 0), 'N0')
                ELSE '0'
            END,

        /* Latch waits saved - new column */
        daily_latch_waits_saved =
            CASE
                WHEN irs.summary_level = 'SUMMARY'
                THEN 'N/A' /* For SUMMARY row, use N/A to be consistent with other metrics */
                WHEN irs.summary_level = 'DATABASE'
                THEN 'N/A'
                WHEN irs.summary_level = 'TABLE'
                THEN
                    /* For TABLE rows, calculate estimated savings */
                    CASE
                        WHEN ISNULL(irs.unused_indexes, 0) > 0
                        THEN
                            FORMAT
                            (
                                CONVERT
                                (
                                    decimal(38,2),
                                    ISNULL
                                    (
                                        (irs.page_latch_wait_count + irs.page_io_latch_wait_count) /
                                        NULLIF
                                        (
                                            CONVERT
                                            (
                                                decimal(38,2),
                                                (
                                                  SELECT TOP (1)
                                                      irs2.server_uptime_days
                                                  FROM #index_reporting_stats AS irs2
                                                  WHERE irs2.summary_level = 'SUMMARY'
                                                )
                                            ),
                                            0
                                        ) *
                                        (
                                            ISNULL
                                            (
                                                irs.unused_indexes,
                                                0
                                            ) /
                                            NULLIF
                                            (
                                                CONVERT
                                                (
                                                    decimal(38,2),
                                                    irs.index_count
                                                ),
                                                0
                                            )
                                        ),
                                        0
                                    )
                                ),
                                'N0'
                            )
                        /* Rows without unused indexes have no savings */
                        ELSE '0'
                    END
                ELSE '0'
            END,

        /* Combined latch wait time in ms */
        avg_latch_wait_ms =
            CASE
                WHEN irs.summary_level = 'SUMMARY'
                THEN 'N/A'
                WHEN irs.summary_level <> 'SUMMARY'
                AND (ISNULL(irs.page_latch_wait_count, 0) +
                     ISNULL(irs.page_io_latch_wait_count, 0)) > 0
                THEN FORMAT(1.0 * (ISNULL(irs.page_latch_wait_in_ms, 0) +
                     ISNULL(irs.page_io_latch_wait_in_ms, 0)) /
                     NULLIF(ISNULL(irs.page_latch_wait_count, 0) +
                     ISNULL(irs.page_io_latch_wait_count, 0), 0), 'N2')
                ELSE '0'
            END
    FROM #index_reporting_stats AS irs
    ORDER BY
        /* Order by database name */
        irs.database_name,
        /* Then order by level - summary first */
        CASE
            WHEN irs.summary_level = 'SUMMARY' THEN 0
            WHEN irs.summary_level = 'DATABASE' THEN 1
            WHEN irs.summary_level = 'TABLE' THEN 2
            ELSE 3
        END,
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

    /* Output message for dedupe_only mode */
    IF @dedupe_only = 1
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Note: Operating in dedupe_only mode. Unused indexes were considered for deduplication only, not for removal.', 0, 1) WITH NOWAIT;
        END;
    END;

    /* Display detailed reports for computed columns with UDFs */
    IF EXISTS
    (
        SELECT
            1/0
        FROM #computed_columns_analysis  AS cca
        WHERE cca.contains_udf = 1
    )
    BEGIN
        SELECT
            finding_type = 'COMPUTED COLUMNS WITH UDF REFERENCES',
            cca.database_name,
            cca.schema_name,
            cca.table_name,
            cca.column_name,
            cca.definition,
            recommendation = 'Consider replacing UDF with inline logic to improve performance'
        FROM #computed_columns_analysis AS cca
        WHERE cca.contains_udf = 1
        ORDER BY
            cca.database_name,
            cca.schema_name,
            cca.table_name,
            cca.column_name;
    END;

    /* Display detailed reports for check constraints with UDFs */
    IF EXISTS
    (
        SELECT
            1/0
        FROM #check_constraints_analysis AS cca
        WHERE cca.contains_udf = 1
    )
    BEGIN
        SELECT
            finding_type = 'CHECK CONSTRAINTS WITH UDF REFERENCES',
            cca.database_name,
            cca.schema_name,
            cca.table_name,
            cca.constraint_name,
            cca.definition,
            recommendation = 'Consider replacing UDF with inline logic to improve performance'
        FROM #check_constraints_analysis AS cca
        WHERE cca.contains_udf = 1
        ORDER BY
            cca.database_name,
            cca.schema_name,
            cca.table_name,
            cca.constraint_name;
    END;

    /* Display detailed reports for filtered indexes that need column optimization */
    IF EXISTS
    (
        SELECT
            1/0
        FROM #filtered_index_columns_analysis AS fica
        WHERE fica.should_include_filter_columns = 1
    )
    BEGIN
        SELECT
            finding_type = 'FILTERED INDEXES NEEDING INCLUDED COLUMNS',
            fica.database_name,
            fica.schema_name,
            fica.table_name,
            fica.index_name,
            fica.filter_definition,
            ia.original_index_definition,
            fica.missing_included_columns,
            recommendation = 'Add filter columns to INCLUDE list to improve performance and avoid key lookups'
        FROM #filtered_index_columns_analysis AS fica
        JOIN #index_analysis AS ia
          ON  ia.database_id = fica.database_id
          AND ia.schema_id = fica.schema_id
          AND ia.object_id = fica.object_id
          AND ia.index_id = fica.index_id
        WHERE fica.should_include_filter_columns = 1
        ORDER BY
            fica.database_name,
            fica.schema_name,
            fica.table_name,
            fica.index_name;
    END;

    /* Check for databases that were processed but had no objects to analyze */
    IF EXISTS
    (
        SELECT
            1/0
        FROM #databases AS d
        WHERE NOT EXISTS
        (
            SELECT
                1/0
            FROM #index_reporting_stats AS irs
            WHERE irs.database_name = d.database_name
        )
    )
    BEGIN
        WITH
            empty_databases AS
        (
            SELECT
                database_name
            FROM #databases AS d
            WHERE NOT EXISTS
            (
                SELECT
                    1/0
                FROM #index_reporting_stats AS irs
                WHERE irs.database_name = d.database_name
            )
        )
        SELECT
            finding_type = 'DATABASES WITH NO QUALIFYING OBJECTS',
            database_name = d.database_name + N' - Nothing Found',
            recommendation = 'Database was processed but no objects met the analysis criteria'
        FROM empty_databases AS d
        ORDER BY
            database_name
        OPTION(RECOMPILE);
    END;

END TRY
BEGIN CATCH
    THROW;
END CATCH;
END; /*Final End*/
GO
