SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('collection.collect_missing_indexes', 'P') IS NULL
BEGIN
    EXECUTE ('CREATE PROCEDURE collection.collect_missing_indexes AS RETURN 0;');
END;
GO

/*
/**************************************************************
* 
* Missing Indexes Collection Procedure for DarlingDataCollector
* 
* Copyright (C) Darling Data, LLC
* 
* Collects missing indexes information from various DMVs:
* sys.dm_db_missing_index_details
* sys.dm_db_missing_index_groups
* sys.dm_db_missing_index_group_stats
* 
**************************************************************/
*/

CREATE OR ALTER PROCEDURE
    collection.collect_missing_indexes
(
    @debug BIT = 0, /*Print debugging information*/
    @use_database_list BIT = 0, /*Use database list from system.database_collection_config*/
    @include_databases NVARCHAR(MAX) = NULL, /*Optional: Comma-separated list of databases to include*/
    @exclude_databases NVARCHAR(MAX) = NULL, /*Optional: Comma-separated list of databases to exclude*/
    @include_system_databases BIT = 0, /*Include system databases*/
    @min_user_seeks INTEGER = 0, /*Minimum number of user seeks to include*/
    @min_user_scans INTEGER = 0, /*Minimum number of user scans to include*/
    @min_avg_user_impact DECIMAL(5,2) = 0, /*Minimum average user impact percentage to include*/
    @min_avg_total_user_cost DECIMAL(18,2) = 0 /*Minimum average total user cost to include*/
)
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
    
    DECLARE
        @collection_start DATETIME2(7) = SYSDATETIME(),
        @collection_end DATETIME2(7),
        @rows_collected BIGINT = 0,
        @error_number INTEGER,
        @error_message NVARCHAR(4000);
    
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
    
    BEGIN TRY
        /*
        Create missing_indexes table if it doesn't exist
        */
        IF OBJECT_ID('collection.missing_indexes') IS NULL
        BEGIN
            EXECUTE system.create_collector_table
                @table_name = 'missing_indexes',
                @debug = @debug;
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
            WHERE collection_type IN (N'MISSING_INDEXES', N'ALL')
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
        Collect missing indexes
        */
        INSERT
            collection.missing_indexes
        (
            collection_time,
            database_id,
            database_name,
            schema_name,
            table_name,
            equality_columns,
            inequality_columns,
            included_columns,
            unique_compiles,
            user_seeks,
            user_scans,
            avg_total_user_cost,
            avg_user_impact,
            last_user_seek,
            last_user_scan,
            index_advantage,
            create_index_statement
        )
        SELECT
            collection_time = @collection_start,
            mid.database_id,
            database_name = DB_NAME(mid.database_id),
            schema_name = OBJECT_SCHEMA_NAME(mid.object_id, mid.database_id),
            table_name = OBJECT_NAME(mid.object_id, mid.database_id),
            equality_columns = mid.equality_columns,
            inequality_columns = mid.inequality_columns,
            included_columns = mid.included_columns,
            migs.unique_compiles,
            migs.user_seeks,
            migs.user_scans,
            migs.avg_total_user_cost,
            migs.avg_user_impact,
            migs.last_user_seek,
            migs.last_user_scan,
            index_advantage = CAST(migs.user_seeks AS DECIMAL(18,2)) * migs.avg_user_impact * migs.avg_total_user_cost / 100.0,
            create_index_statement = 
                'CREATE NONCLUSTERED INDEX ix_' + 
                ISNULL(REPLACE(REPLACE(REPLACE(REPLACE(
                    OBJECT_NAME(mid.object_id, mid.database_id),
                    ' ', ''), '[', ''), ']', ''), '.', '') + 
                '_missing_' + CAST(mid.index_handle AS NVARCHAR(20)), 'unknown_name') + 
                CASE 
                    WHEN mid.equality_columns IS NOT NULL AND mid.inequality_columns IS NULL 
                    THEN '_eq' 
                    WHEN mid.equality_columns IS NULL AND mid.inequality_columns IS NOT NULL 
                    THEN '_ineq' 
                    ELSE '_comb' 
                END + 
                ' ON ' + QUOTENAME(DB_NAME(mid.database_id)) + '.' + 
                QUOTENAME(OBJECT_SCHEMA_NAME(mid.object_id, mid.database_id)) + '.' + 
                QUOTENAME(OBJECT_NAME(mid.object_id, mid.database_id)) + 
                ' (' + ISNULL(mid.equality_columns, '') + 
                CASE 
                    WHEN mid.equality_columns IS NOT NULL AND mid.inequality_columns IS NOT NULL 
                    THEN ', ' 
                    ELSE '' 
                END + 
                ISNULL(mid.inequality_columns, '') + ')' + 
                ISNULL(' INCLUDE (' + mid.included_columns + ')', '')
        FROM sys.dm_db_missing_index_details AS mid
        JOIN sys.dm_db_missing_index_groups AS mig
            ON mid.index_handle = mig.index_handle
        JOIN sys.dm_db_missing_index_group_stats AS migs
            ON mig.index_group_handle = migs.group_handle
        WHERE mid.database_id > 0
        AND mid.object_id > 0
        AND migs.user_seeks >= @min_user_seeks
        AND migs.user_scans >= @min_user_scans
        AND migs.avg_user_impact >= @min_avg_user_impact
        AND migs.avg_total_user_cost >= @min_avg_total_user_cost
        AND ((@include_databases IS NULL AND @use_database_list = 0) -- If no includes specified, use all databases
             OR DB_NAME(mid.database_id) IN (SELECT database_name FROM @include_database_list))
        AND ((mid.database_id > 4) OR @include_system_databases = 1) -- User databases or if system databases are included
        AND DB_NAME(mid.database_id) NOT IN (SELECT database_name FROM @exclude_database_list) -- Not in exclude list
        ORDER BY index_advantage DESC;
        
        SET @rows_collected = @@ROWCOUNT;
        SET @collection_end = SYSDATETIME();
        
        /*
        Log collection results
        */
        INSERT
            system.collection_log
        (
            procedure_name,
            collection_start,
            collection_end,
            rows_collected,
            status
        )
        VALUES
        (
            'collection.collect_missing_indexes',
            @collection_start,
            @collection_end,
            @rows_collected,
            'Success'
        );
        
        /*
        Print debug information
        */
        IF @debug = 1
        BEGIN
            SELECT
                N'Missing Indexes Collected' AS collection_type,
                @rows_collected AS rows_collected,
                CAST(DATEDIFF(MILLISECOND, @collection_start, @collection_end) / 1000.0 AS DECIMAL(18,2)) AS duration_seconds;
        END;
    END TRY
    BEGIN CATCH
        SET @error_number = ERROR_NUMBER();
        SET @error_message = ERROR_MESSAGE();
        
        /*
        Log error
        */
        INSERT
            system.collection_log
        (
            procedure_name,
            collection_start,
            collection_end,
            rows_collected,
            status,
            error_number,
            error_message
        )
        VALUES
        (
            'collection.collect_missing_indexes',
            @collection_start,
            SYSDATETIME(),
            0,
            'Error',
            @error_number,
            @error_message
        );
        
        /*
        Re-throw error
        */
        THROW;
    END CATCH;
END;
GO