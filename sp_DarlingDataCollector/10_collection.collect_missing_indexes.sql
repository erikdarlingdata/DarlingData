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
    @min_improvement_pct DECIMAL(5, 2) = 10.0, /*Minimum improvement percentage to include*/
    @min_user_seeks INTEGER = 1, /*Minimum number of user seeks to include*/
    @min_avg_user_impact DECIMAL(5, 2) = 50.0, /*Minimum average user impact to include*/
    @use_database_list BIT = 1, /*Use database list from system.database_collection_config*/
    @include_databases NVARCHAR(MAX) = NULL, /*Optional: Comma-separated list of databases to include*/
    @exclude_databases NVARCHAR(MAX) = NULL, /*Optional: Comma-separated list of databases to exclude*/
    @exclude_system_databases BIT = 1 /*Exclude system databases*/
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
            CREATE TABLE
                collection.missing_indexes
            (
                collection_id BIGINT IDENTITY(1,1) NOT NULL,
                collection_time DATETIME2(7) NOT NULL,
                database_id INTEGER NOT NULL,
                database_name NVARCHAR(128) NOT NULL,
                schema_name NVARCHAR(128) NULL,
                table_name NVARCHAR(128) NULL,
                index_handle INTEGER NOT NULL,
                missing_index_group_handle INTEGER NOT NULL,
                avg_total_user_cost DECIMAL(18, 2) NULL,
                avg_user_impact DECIMAL(5, 2) NULL,
                user_seeks BIGINT NULL,
                user_scans BIGINT NULL,
                last_user_seek DATETIME NULL,
                last_user_scan DATETIME NULL,
                improvement_measure DECIMAL(18, 2) NULL,
                included_columns NVARCHAR(MAX) NULL,
                equality_columns NVARCHAR(MAX) NULL,
                inequality_columns NVARCHAR(MAX) NULL,
                statement NVARCHAR(4000) NULL,
                create_index_statement NVARCHAR(MAX) NULL,
                CONSTRAINT pk_missing_indexes PRIMARY KEY CLUSTERED (collection_id, database_id, index_handle)
            );
            
            IF @debug = 1
            BEGIN
                RAISERROR(N'Created collection.missing_indexes table', 0, 1) WITH NOWAIT;
            END;
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
            WHERE collection_type IN (N'INDEX', N'ALL')
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
        Collect missing indexes information
        */
        INSERT
            collection.missing_indexes
        (
            collection_time,
            database_id,
            database_name,
            schema_name,
            table_name,
            index_handle,
            missing_index_group_handle,
            avg_total_user_cost,
            avg_user_impact,
            user_seeks,
            user_scans,
            last_user_seek,
            last_user_scan,
            improvement_measure,
            included_columns,
            equality_columns,
            inequality_columns,
            statement,
            create_index_statement
        )
        SELECT
            collection_time = SYSDATETIME(),
            mid.database_id,
            database_name = DB_NAME(mid.database_id),
            schema_name = OBJECT_SCHEMA_NAME(mid.object_id, mid.database_id),
            table_name = OBJECT_NAME(mid.object_id, mid.database_id),
            mid.index_handle,
            migs.group_handle AS missing_index_group_handle,
            migs.avg_total_user_cost,
            migs.avg_user_impact,
            migs.user_seeks,
            migs.user_scans,
            migs.last_user_seek,
            migs.last_user_scan,
            improvement_measure = (migs.user_seeks + migs.user_scans) * migs.avg_total_user_cost * (migs.avg_user_impact / 100.0),
            mid.included_columns,
            mid.equality_columns,
            mid.inequality_columns,
            mid.statement,
            create_index_statement = 
                N'CREATE INDEX [IX_' + 
                OBJECT_NAME(mid.object_id, mid.database_id) + N'_missing_' + 
                CAST(mid.index_handle AS NVARCHAR(20)) + N'] ON ' + 
                mid.statement + 
                CASE 
                    WHEN mid.equality_columns IS NOT NULL 
                    THEN N' (' + mid.equality_columns + 
                        CASE 
                            WHEN mid.inequality_columns IS NOT NULL 
                            THEN N', ' + mid.inequality_columns 
                            ELSE N'' 
                        END + N')' 
                    ELSE N' (' + mid.inequality_columns + N')' 
                END + 
                CASE 
                    WHEN mid.included_columns IS NOT NULL 
                    THEN N' INCLUDE (' + mid.included_columns + N')' 
                    ELSE N'' 
                END
        FROM sys.dm_db_missing_index_details AS mid
        JOIN sys.dm_db_missing_index_groups AS mig
            ON mid.index_handle = mig.index_handle
        JOIN sys.dm_db_missing_index_group_stats AS migs
            ON mig.index_group_handle = migs.group_handle
        WHERE 
            (migs.user_seeks + migs.user_scans) * migs.avg_total_user_cost * (migs.avg_user_impact / 100.0) > @min_improvement_pct
            AND migs.user_seeks >= @min_user_seeks
            AND migs.avg_user_impact >= @min_avg_user_impact
            AND 
            (
                -- Use include list if specified
                (
                    EXISTS (SELECT 1 FROM @include_database_list)
                    AND DB_NAME(mid.database_id) IN (SELECT database_name FROM @include_database_list)
                )
                OR 
                (
                    -- Otherwise use all databases except excluded ones
                    NOT EXISTS (SELECT 1 FROM @include_database_list)
                    AND 
                    (
                        -- Skip system databases if specified
                        (@exclude_system_databases = 0 OR mid.database_id > 4)
                        -- Skip excluded databases
                        AND DB_NAME(mid.database_id) NOT IN (SELECT database_name FROM @exclude_database_list)
                    )
                )
            );
        
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