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
* Collects file space usage information for databases
* 
**************************************************************/
*/

CREATE OR ALTER PROCEDURE
    collection.collect_file_space
(
    @debug BIT = 0, /*Print debugging information*/
    @use_database_list BIT = 0, /*Use database list from system.database_collection_config*/
    @include_databases NVARCHAR(MAX) = NULL, /*Optional: Comma-separated list of databases to include*/
    @exclude_databases NVARCHAR(MAX) = NULL, /*Optional: Comma-separated list of databases to exclude*/
    @include_system_databases BIT = 0 /*Include system databases*/
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
        @database_name NVARCHAR(128),
        @database_id INTEGER;
    
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
        Create file_space table if it doesn't exist
        */
        IF OBJECT_ID('collection.file_space') IS NULL
        BEGIN
            EXECUTE system.create_collector_table
                @table_name = 'file_space',
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
            database_id,
            name
        FROM sys.databases
        WHERE (@include_databases IS NULL AND @use_database_list = 0) -- If no includes specified, use all databases
        OR name IN (SELECT database_name FROM @include_database_list)
        AND state = 0 -- Online databases only
        AND (database_id > 4 OR @include_system_databases = 1) -- User databases or if system databases are included
        AND name NOT IN (SELECT database_name FROM @exclude_database_list) -- Not in exclude list
        ORDER BY name;
        
        IF @debug = 1
        BEGIN
            SELECT
                database_count = COUNT(*)
            FROM @database_list;
        END;
        
        /*
        Process each database
        */
        DECLARE db_cursor CURSOR LOCAL FAST_FORWARD
        FOR
            SELECT 
                database_id,
                database_name
            FROM @database_list
            ORDER BY database_name;
        
        OPEN db_cursor;
        
        FETCH NEXT FROM
            db_cursor
        INTO
            @database_id,
            @database_name;
            
        WHILE @@FETCH_STATUS = 0
        BEGIN
            /*
            Build SQL to collect file space info from the current database
            */
            SET @sql = N'
            USE ' + QUOTENAME(@database_name) + N';
            
            INSERT
                collection.file_space
            (
                collection_time,
                database_id,
                database_name,
                file_id,
                file_name,
                file_path,
                type_desc,
                size_mb,
                space_used_mb,
                free_space_mb,
                free_space_percent,
                max_size_mb,
                growth,
                is_percent_growth,
                is_read_only
            )
            SELECT
                collection_time = ''' + CONVERT(NVARCHAR(30), @collection_start, 126) + N''',
                database_id = ' + CAST(@database_id AS NVARCHAR(10)) + N',
                database_name = ''' + @database_name + N''',
                file_id = f.file_id,
                file_name = f.name,
                file_path = f.physical_name,
                type_desc = f.type_desc,
                size_mb = CAST(f.size AS DECIMAL(18,2)) * 8.0 / 1024,
                space_used_mb = CAST(FILEPROPERTY(f.name, ''SpaceUsed'') AS DECIMAL(18,2)) * 8.0 / 1024,
                free_space_mb = CAST((f.size - FILEPROPERTY(f.name, ''SpaceUsed'')) AS DECIMAL(18,2)) * 8.0 / 1024,
                free_space_percent = 
                    CASE 
                        WHEN f.size > 0 
                        THEN CAST(100.0 * (f.size - FILEPROPERTY(f.name, ''SpaceUsed'')) / f.size AS DECIMAL(5,2))
                        ELSE 0
                    END,
                max_size_mb = 
                    CASE 
                        WHEN f.max_size = -1 THEN -1 -- Unlimited
                        WHEN f.max_size = 268435456 THEN -1 -- Unlimited
                        ELSE CAST(f.max_size AS DECIMAL(18,2)) * 8.0 / 1024 -- Convert from 8KB pages to MB
                    END,
                growth = 
                    CASE 
                        WHEN f.is_percent_growth = 1 THEN f.growth
                        ELSE CAST(f.growth AS DECIMAL(18,2)) * 8.0 / 1024 -- Convert from 8KB pages to MB
                    END,
                is_percent_growth = f.is_percent_growth,
                is_read_only = f.is_read_only
            FROM sys.database_files AS f
            WHERE f.type IN (0, 1, 2, 4) -- Data (0), Log (1), Filestream (2), Full-text (4)
            ORDER BY f.type, f.file_id;
            ';
            
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
        FROM collection.file_space
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
                N'File Space Collected' AS collection_type,
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