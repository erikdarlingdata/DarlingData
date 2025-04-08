/*
██╗███╗   ██╗██████╗ ███████╗██╗  ██╗    ██╗   ██╗███████╗ █████╗  ██████╗ ███████╗    ███████╗████████╗ █████╗ ████████╗███████╗
██║████╗  ██║██╔══██╗██╔════╝╚██╗██╔╝    ██║   ██║██╔════╝██╔══██╗██╔════╝ ██╔════╝    ██╔════╝╚══██╔══╝██╔══██╗╚══██╔══╝██╔════╝
██║██╔██╗ ██║██║  ██║█████╗   ╚███╔╝     ██║   ██║███████╗███████║██║  ███╗█████╗      ███████╗   ██║   ███████║   ██║   ███████╗
██║██║╚██╗██║██║  ██║██╔══╝   ██╔██╗     ██║   ██║╚════██║██╔══██║██║   ██║██╔══╝      ╚════██║   ██║   ██╔══██║   ██║   ╚════██║
██║██║ ╚████║██████╔╝███████╗██╔╝ ██╗    ╚██████╔╝███████║██║  ██║╚██████╔╝███████╗    ███████║   ██║   ██║  ██║   ██║   ███████║
╚═╝╚═╝  ╚═══╝╚═════╝ ╚══════╝╚═╝  ╚═╝     ╚═════╝ ╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝    ╚══════╝   ╚═╝   ╚═╝  ╚═╝   ╚═╝   ╚══════╝
                                                                                                                                  
Copyright (c) Darling Data, LLC
https://www.erikdarling.com/

--===== INDEX USAGE STATS COLLECTOR NOTES ====--
This procedure collects index usage stats from specified databases.
By default, it collects from the current database context.
Use the @database_list parameter to collect from multiple databases.
You can also collect a sample over a time period to get delta values.
*/

CREATE OR ALTER PROCEDURE
    collection.collect_index_usage_stats
(
    @debug BIT = 0, /*Print debugging information*/
    @sample_seconds INTEGER = NULL, /*Optional: Collect sample over time period*/
    @database_list NVARCHAR(MAX) = NULL, /*Optional: Comma-separated list of databases*/
    @exclude_system_databases BIT = 1, /*Exclude system databases*/
    @exclude_databases NVARCHAR(MAX) = NULL /*Optional: Comma-separated list of databases to exclude*/
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
        @sql NVARCHAR(MAX),
        @databases TABLE
        (
            database_id INTEGER PRIMARY KEY,
            database_name NVARCHAR(128) NOT NULL
        ),
        @current_database_id INTEGER,
        @current_database_name NVARCHAR(128);
    
    BEGIN TRY
        /*
        Build list of databases to collect from
        */
        IF @database_list IS NULL
        BEGIN
            /*
            If no list specified, use current database
            */
            INSERT
                @databases
            (
                database_id,
                database_name
            )
            SELECT 
                database_id = DB_ID(),
                database_name = DB_NAME();
        END;
        ELSE
        BEGIN
            /*
            Parse comma-separated list of databases
            */
            WITH 
                parsed_list AS
            (
                SELECT
                    value
                FROM STRING_SPLIT(@database_list, ',')
            )
            INSERT
                @databases
            (
                database_id,
                database_name
            )
            SELECT 
                database_id = DB_ID(LTRIM(RTRIM(d.name))),
                database_name = d.name
            FROM sys.databases AS d
            JOIN parsed_list AS pl
              ON d.name LIKE LTRIM(RTRIM(pl.value))
            WHERE d.state_desc = N'ONLINE';
        END;
        
        /*
        Apply exclusions
        */
        IF @exclude_system_databases = 1
        BEGIN
            DELETE @databases
            WHERE database_id IN (1, 2, 3, 4); -- master, tempdb, model, msdb
        END;
        
        IF @exclude_databases IS NOT NULL
        BEGIN
            WITH 
                excluded_list AS
            (
                SELECT
                    value
                FROM STRING_SPLIT(@exclude_databases, ',')
            )
            DELETE d
            FROM @databases AS d
            JOIN excluded_list AS el
              ON d.database_name LIKE LTRIM(RTRIM(el.value));
        END;
        
        /*
        If sampling is requested, collect first sample
        */
        IF @sample_seconds IS NOT NULL
        BEGIN
            /*
            Create temporary table for collecting index usage stats samples
            */
            CREATE TABLE
                #index_usage_stats_before
            (
                database_id INTEGER NOT NULL,
                object_id INTEGER NOT NULL,
                index_id INTEGER NOT NULL,
                user_seeks BIGINT NOT NULL,
                user_scans BIGINT NOT NULL,
                user_lookups BIGINT NOT NULL,
                user_updates BIGINT NOT NULL,
                last_user_seek DATETIME2(7) NULL,
                last_user_scan DATETIME2(7) NULL,
                last_user_lookup DATETIME2(7) NULL,
                last_user_update DATETIME2(7) NULL,
                PRIMARY KEY (database_id, object_id, index_id)
            );
            
            /*
            Collect first sample from all databases
            */
            INSERT
                #index_usage_stats_before
            (
                database_id,
                object_id,
                index_id,
                user_seeks,
                user_scans,
                user_lookups,
                user_updates,
                last_user_seek,
                last_user_scan,
                last_user_lookup,
                last_user_update
            )
            SELECT
                database_id,
                object_id,
                index_id,
                user_seeks,
                user_scans,
                user_lookups,
                user_updates,
                last_user_seek,
                last_user_scan,
                last_user_lookup,
                last_user_update
            FROM sys.dm_db_index_usage_stats
            WHERE database_id IN (SELECT database_id FROM @databases);
            
            /*
            Wait for the specified sample period
            */
            WAITFOR DELAY CONVERT(CHAR(8), DATEADD(SECOND, @sample_seconds, 0), 114);
        END;
        
        /*
        Loop through each database to collect index usage stats
        */
        DECLARE db_cursor CURSOR LOCAL FAST_FORWARD
        FOR
            SELECT
                database_id,
                database_name
            FROM @databases
            ORDER BY database_name;
            
        OPEN db_cursor;
        FETCH NEXT FROM db_cursor INTO @current_database_id, @current_database_name;
        
        WHILE @@FETCH_STATUS = 0
        BEGIN
            /*
            Build dynamic SQL to collect index usage stats from the current database
            */
            SET @sql = N'
            USE ' + QUOTENAME(@current_database_name) + N';
            
            INSERT
                collection.index_usage_stats
            (
                collection_time,
                database_id,
                database_name,
                object_id,
                schema_name,
                object_name,
                index_id,
                index_name,
                user_seeks,
                user_scans,
                user_lookups,
                user_updates,
                last_user_seek,
                last_user_scan,
                last_user_lookup,
                last_user_update' + 
                CASE 
                    WHEN @sample_seconds IS NOT NULL
                    THEN N',
                user_seeks_delta,
                user_scans_delta,
                user_lookups_delta,
                user_updates_delta,
                sample_seconds'
                    ELSE N''
                END + N'
            )
            SELECT
                collection_time = SYSDATETIME(),
                ius.database_id,
                database_name = DB_NAME(ius.database_id),
                ius.object_id,
                schema_name = SCHEMA_NAME(o.schema_id),
                object_name = o.name,
                ius.index_id,
                index_name = i.name,
                ius.user_seeks,
                ius.user_scans,
                ius.user_lookups,
                ius.user_updates,
                ius.last_user_seek,
                ius.last_user_scan,
                ius.last_user_lookup,
                ius.last_user_update' +
                CASE 
                    WHEN @sample_seconds IS NOT NULL
                    THEN N',
                user_seeks_delta = ius.user_seeks - ISNULL(iusb.user_seeks, 0),
                user_scans_delta = ius.user_scans - ISNULL(iusb.user_scans, 0),
                user_lookups_delta = ius.user_lookups - ISNULL(iusb.user_lookups, 0),
                user_updates_delta = ius.user_updates - ISNULL(iusb.user_updates, 0),
                sample_seconds = ' + CAST(@sample_seconds AS NVARCHAR(20))
                    ELSE N''
                END + N'
            FROM sys.dm_db_index_usage_stats AS ius
            JOIN sys.objects AS o
              ON ius.object_id = o.object_id
            JOIN sys.indexes AS i
              ON ius.object_id = i.object_id
              AND ius.index_id = i.index_id' +
            CASE 
                WHEN @sample_seconds IS NOT NULL
                THEN N'
            LEFT JOIN #index_usage_stats_before AS iusb
              ON ius.database_id = iusb.database_id
              AND ius.object_id = iusb.object_id
              AND ius.index_id = iusb.index_id'
                ELSE N''
            END + N'
            WHERE ius.database_id = ' + CAST(@current_database_id AS NVARCHAR(10)) + N'
            AND o.is_ms_shipped = 0
            AND o.type IN (''U'', ''V'')  -- User tables and views only
            ';
            
            /*
            Execute the dynamic SQL
            */
            EXEC sp_executesql @sql;
            
            /*
            Update row count
            */
            SET @rows_collected = @rows_collected + @@ROWCOUNT;
            
            /*
            Move to the next database
            */
            FETCH NEXT FROM db_cursor INTO @current_database_id, @current_database_name;
        END;
        
        CLOSE db_cursor;
        DEALLOCATE db_cursor;
        
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
            'collection.collect_index_usage_stats',
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
                N'Index Usage Stats Collected' AS collection_type,
                @rows_collected AS rows_collected,
                CAST(DATEDIFF(MILLISECOND, @collection_start, @collection_end) / 1000.0 AS DECIMAL(18,2)) AS duration_seconds,
                database_count =
                (
                    SELECT
                        COUNT(*)
                    FROM @databases
                ),
                database_list =
                (
                    SELECT
                        STRING_AGG(database_name, N', ')
                    FROM @databases
                );
        END;
    END TRY
    BEGIN CATCH
        /*
        Clean up cursor if still open
        */
        IF CURSOR_STATUS('local', 'db_cursor') > 0
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
            'collection.collect_index_usage_stats',
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