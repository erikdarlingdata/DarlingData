SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('collection.collect_file_space', 'P') IS NULL
BEGIN
    EXECUTE ('CREATE PROCEDURE collection.collect_file_space AS RETURN 0;');
END;
GO

/*
/**************************************************************
* 
* File Space Collection Procedure for DarlingDataCollector
* 
* Copyright (C) Darling Data, LLC
* 
* Collects database file space information from 
* sys.dm_db_file_space_usage and sys.dm_db_log_space_usage
* 
**************************************************************/
*/

CREATE OR ALTER PROCEDURE
    collection.collect_file_space
(
    @debug BIT = 0, /*Print debugging information*/
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
        @error_message NVARCHAR(4000),
        @sql NVARCHAR(MAX) = N'',
        @database_name NVARCHAR(128);
    
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
            database_name NVARCHAR(128) NOT NULL
        );
    
    BEGIN TRY
        /*
        Create file_space_usage table if it doesn't exist
        */
        IF OBJECT_ID('collection.file_space_usage') IS NULL
        BEGIN
            CREATE TABLE
                collection.file_space_usage
            (
                collection_id BIGINT IDENTITY(1,1) NOT NULL,
                collection_time DATETIME2(7) NOT NULL,
                database_id INTEGER NOT NULL,
                database_name NVARCHAR(128) NOT NULL,
                file_id INTEGER NOT NULL,
                file_name NVARCHAR(128) NULL,
                file_type NVARCHAR(60) NULL,
                size_mb DECIMAL(18, 2) NULL,
                space_used_mb DECIMAL(18, 2) NULL,
                free_space_mb DECIMAL(18, 2) NULL,
                growth_units NVARCHAR(15) NULL,
                growth_increment DECIMAL(18, 2) NULL,
                max_size_mb DECIMAL(18, 2) NULL,
                is_percent_growth BIT NULL,
                is_read_only BIT NULL,
                is_log BIT NULL,
                log_space_in_use_percentage DECIMAL(5, 2) NULL,
                log_space_used_mb DECIMAL(18, 2) NULL,
                log_space_reserved_mb DECIMAL(18, 2) NULL,
                file_type_desc NVARCHAR(60) NULL,
                data_space_id INTEGER NULL,
                data_space_name NVARCHAR(128) NULL,
                total_page_count BIGINT NULL,
                allocated_extent_page_count BIGINT NULL,
                unallocated_extent_page_count BIGINT NULL,
                version_store_reserved_page_count BIGINT NULL,
                user_object_reserved_page_count BIGINT NULL,
                internal_object_reserved_page_count BIGINT NULL,
                mixed_extent_page_count BIGINT NULL,
                CONSTRAINT pk_file_space_usage PRIMARY KEY CLUSTERED (collection_id, database_id, file_id)
            );
            
            IF @debug = 1
            BEGIN
                RAISERROR(N'Created collection.file_space_usage table', 0, 1) WITH NOWAIT;
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
            WHERE collection_type IN (N'FILE_SPACE', N'ALL')
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
            database_name
        )
        SELECT
            d.database_id,
            database_name = d.name
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
        );
        
        IF @debug = 1
        BEGIN
            SELECT
                db_list = N'Final database list',
                dl.database_id,
                dl.database_name
            FROM @database_list AS dl
            ORDER BY
                dl.database_name;
        END;
        
        /*
        Loop through each database and collect file space information
        */
        DECLARE
            db_cursor CURSOR LOCAL FORWARD_ONLY STATIC READ_ONLY
        FOR
            SELECT
                database_id,
                database_name
            FROM @database_list
            ORDER BY
                database_name;
                
        OPEN db_cursor;
        
        FETCH NEXT FROM
            db_cursor
        INTO
            @database_id,
            @database_name;
            
        WHILE @@FETCH_STATUS = 0
        BEGIN
            IF @debug = 1
            BEGIN
                RAISERROR(N'Processing database %s (ID: %d)', 0, 1, @database_name, @database_id) WITH NOWAIT;
            END;
            
            -- Build dynamic SQL to get file space usage for the current database
            SET @sql = N'
            USE ' + QUOTENAME(@database_name) + N';
            
            INSERT
                collection.file_space_usage
            (
                collection_time,
                database_id,
                database_name,
                file_id,
                file_name,
                file_type,
                size_mb,
                space_used_mb,
                free_space_mb,
                growth_units,
                growth_increment,
                max_size_mb,
                is_percent_growth,
                is_read_only,
                is_log,
                log_space_in_use_percentage,
                log_space_used_mb,
                log_space_reserved_mb,
                file_type_desc,
                data_space_id,
                data_space_name,
                total_page_count,
                allocated_extent_page_count,
                unallocated_extent_page_count,
                version_store_reserved_page_count,
                user_object_reserved_page_count,
                internal_object_reserved_page_count,
                mixed_extent_page_count
            )
            SELECT
                collection_time = SYSDATETIME(),
                database_id = DB_ID(),
                database_name = DB_NAME(),
                mf.file_id,
                mf.name,
                file_type = 
                    CASE 
                        WHEN mf.type = 0 THEN ''DATA''
                        WHEN mf.type = 1 THEN ''LOG''
                        ELSE ''OTHER''
                    END,
                size_mb = 
                    CONVERT(DECIMAL(18,2), mf.size/128.0),
                space_used_mb = 
                    CONVERT(DECIMAL(18,2), FILEPROPERTY(mf.name, ''SpaceUsed'')/128.0),
                free_space_mb = 
                    CONVERT(DECIMAL(18,2), mf.size/128.0 - FILEPROPERTY(mf.name, ''SpaceUsed'')/128.0),
                growth_units = 
                    CASE 
                        WHEN mf.is_percent_growth = 1 THEN ''%''
                        ELSE ''MB''
                    END,
                growth_increment = 
                    CASE
                        WHEN mf.is_percent_growth = 1 THEN CONVERT(DECIMAL(18,2), mf.growth)
                        ELSE CONVERT(DECIMAL(18,2), mf.growth/128.0)
                    END,
                max_size_mb = 
                    CASE
                        WHEN mf.max_size = -1 THEN -1
                        WHEN mf.max_size = 268435456 THEN -1
                        ELSE CONVERT(DECIMAL(18,2), mf.max_size/128.0)
                    END,
                mf.is_percent_growth,
                mf.is_read_only,
                is_log = 
                    CASE 
                        WHEN mf.type = 1 THEN 1
                        ELSE 0
                    END,
                log_space_in_use_percentage = 
                    CASE 
                        WHEN mf.type = 1 THEN 
                            (SELECT CONVERT(DECIMAL(5,2), lsu.used_log_space_in_percent)
                             FROM sys.dm_db_log_space_usage AS lsu)
                        ELSE NULL
                    END,
                log_space_used_mb = 
                    CASE 
                        WHEN mf.type = 1 THEN 
                            (SELECT CONVERT(DECIMAL(18,2), lsu.used_log_space_in_bytes/1024.0/1024.0)
                             FROM sys.dm_db_log_space_usage AS lsu)
                        ELSE NULL
                    END,
                log_space_reserved_mb = 
                    CASE 
                        WHEN mf.type = 1 THEN 
                            (SELECT CONVERT(DECIMAL(18,2), lsu.total_log_size_in_bytes/1024.0/1024.0)
                             FROM sys.dm_db_log_space_usage AS lsu)
                        ELSE NULL
                    END,
                mf.type_desc,
                mf.data_space_id,
                data_space_name = ds.name,
                total_page_count = 
                    CASE 
                        WHEN mf.type = 0 THEN 
                            (SELECT fsu.total_page_count 
                             FROM sys.dm_db_file_space_usage AS fsu 
                             WHERE fsu.file_id = mf.file_id)
                        ELSE NULL
                    END,
                allocated_extent_page_count = 
                    CASE 
                        WHEN mf.type = 0 THEN 
                            (SELECT fsu.allocated_extent_page_count 
                             FROM sys.dm_db_file_space_usage AS fsu 
                             WHERE fsu.file_id = mf.file_id)
                        ELSE NULL
                    END,
                unallocated_extent_page_count = 
                    CASE 
                        WHEN mf.type = 0 THEN 
                            (SELECT fsu.unallocated_extent_page_count 
                             FROM sys.dm_db_file_space_usage AS fsu 
                             WHERE fsu.file_id = mf.file_id)
                        ELSE NULL
                    END,
                version_store_reserved_page_count = 
                    CASE 
                        WHEN mf.type = 0 THEN 
                            (SELECT fsu.version_store_reserved_page_count 
                             FROM sys.dm_db_file_space_usage AS fsu 
                             WHERE fsu.file_id = mf.file_id)
                        ELSE NULL
                    END,
                user_object_reserved_page_count = 
                    CASE 
                        WHEN mf.type = 0 THEN 
                            (SELECT fsu.user_object_reserved_page_count 
                             FROM sys.dm_db_file_space_usage AS fsu 
                             WHERE fsu.file_id = mf.file_id)
                        ELSE NULL
                    END,
                internal_object_reserved_page_count = 
                    CASE 
                        WHEN mf.type = 0 THEN 
                            (SELECT fsu.internal_object_reserved_page_count 
                             FROM sys.dm_db_file_space_usage AS fsu 
                             WHERE fsu.file_id = mf.file_id)
                        ELSE NULL
                    END,
                mixed_extent_page_count = 
                    CASE 
                        WHEN mf.type = 0 THEN 
                            (SELECT fsu.mixed_extent_page_count 
                             FROM sys.dm_db_file_space_usage AS fsu 
                             WHERE fsu.file_id = mf.file_id)
                        ELSE NULL
                    END
            FROM sys.database_files AS mf
            LEFT JOIN sys.data_spaces AS ds
                ON mf.data_space_id = ds.data_space_id
            OPTION(RECOMPILE);
            ';
            
            -- Execute the dynamic SQL to collect file space information
            BEGIN TRY
                EXECUTE sp_executesql @sql;
                
                IF @debug = 1
                BEGIN
                    RAISERROR(N'Collected file space data for database %s', 0, 1, @database_name) WITH NOWAIT;
                END;
            END TRY
            BEGIN CATCH
                IF @debug = 1
                BEGIN
                    RAISERROR(N'Error collecting file space data for database %s: %s', 0, 1, 
                              @database_name, ERROR_MESSAGE()) WITH NOWAIT;
                END;
            END CATCH;
            
            FETCH NEXT FROM
                db_cursor
            INTO
                @database_id,
                @database_name;
        END;
        
        CLOSE db_cursor;
        DEALLOCATE db_cursor;
        
        -- Get the count of rows collected
        SELECT
            @rows_collected = COUNT(*)
        FROM collection.file_space_usage
        WHERE collection_time = @collection_start;
        
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
            'collection.collect_file_space',
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
                N'File Space Usage Collected' AS collection_type,
                @rows_collected AS rows_collected,
                CAST(DATEDIFF(MILLISECOND, @collection_start, @collection_end) / 1000.0 AS DECIMAL(18,2)) AS duration_seconds;
        END;
    END TRY
    BEGIN CATCH
        IF CURSOR_STATUS('local', 'db_cursor') >= 0
        BEGIN
            CLOSE db_cursor;
            DEALLOCATE db_cursor;
        END;
        
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
            'collection.collect_file_space',
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