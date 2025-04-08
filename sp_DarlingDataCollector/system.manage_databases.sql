SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('system.manage_databases', 'P') IS NULL
BEGIN
    EXECUTE ('CREATE PROCEDURE system.manage_databases AS RETURN 0;');
END;
GO

/*
/**************************************************************
* 
* Database Management Procedure for DarlingDataCollector
* 
* Copyright (C) Darling Data, LLC
* 
* Manages database inclusion/exclusion for data collection
* 
**************************************************************/
*/

CREATE OR ALTER PROCEDURE
    system.manage_databases
(
    @action NVARCHAR(10) = NULL, /*ADD, REMOVE, LIST*/
    @database_name NVARCHAR(128) = NULL, /*Database to add or remove*/
    @collection_type NVARCHAR(50) = NULL, /*Type of collection: INDEX, QUERY_STORE, ALL*/
    @debug BIT = 0, /*Print debugging information*/
    @help BIT = 0 /*Prints help information*/
)
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
    
    BEGIN TRY
        /*
        Variable declarations
        */
        DECLARE
            @sql NVARCHAR(MAX) = N'',
            @error_number INTEGER = 0,
            @error_severity INTEGER = 0,
            @error_state INTEGER = 0,
            @error_line INTEGER = 0,
            @error_message NVARCHAR(4000) = N'',
            @database_id INTEGER = NULL,
            @online_status BIT = NULL,
            @readonly_status BIT = NULL;
            
        /*
        Create collection type table
        */
        DECLARE
            @collection_types TABLE
            (
                type_id INTEGER NOT NULL,
                type_name NVARCHAR(50) NOT NULL
            );
            
        INSERT @collection_types
        (
            type_id,
            type_name
        )
        VALUES
            (1, N'INDEX'),
            (2, N'QUERY_STORE'),
            (3, N'ALL');
            
        /*
        Parameter validation
        */
        IF @help = 1
        BEGIN
            SELECT
                help = N'This procedure manages databases for specific collection types.
                
Parameters:
  @action = Action to perform: ADD, REMOVE, LIST (required)
  @database_name = Database to add or remove (required for ADD, REMOVE)
  @collection_type = Collection type: INDEX, QUERY_STORE, ALL (required for ADD, REMOVE)
  @debug = 1 to print detailed information, 0 for normal operation
  @help = 1 to show this help information

Example usage:
  -- Add a database for index collection
  EXECUTE system.manage_databases @action = ''ADD'', @database_name = ''AdventureWorks'', @collection_type = ''INDEX'';
  
  -- Remove a database from query store collection
  EXECUTE system.manage_databases @action = ''REMOVE'', @database_name = ''AdventureWorks'', @collection_type = ''QUERY_STORE'';
  
  -- List all databases in collection
  EXECUTE system.manage_databases @action = ''LIST'';';
            
            RETURN;
        END;
        
        IF @action IS NULL
        OR @action NOT IN (N'ADD', N'REMOVE', N'LIST')
        BEGIN
            RAISERROR(N'@action must be ADD, REMOVE, or LIST', 11, 1) WITH NOWAIT;
            RETURN;
        END;
        
        IF @action IN (N'ADD', N'REMOVE')
        AND (@database_name IS NULL OR @collection_type IS NULL)
        BEGIN
            RAISERROR(N'@database_name and @collection_type are required for ADD and REMOVE actions', 11, 1) WITH NOWAIT;
            RETURN;
        END;
        
        IF @collection_type IS NOT NULL
        AND NOT EXISTS
        (
            SELECT
                1
            FROM @collection_types AS ct
            WHERE ct.type_name = @collection_type
        )
        BEGIN
            RAISERROR(N'@collection_type must be INDEX, QUERY_STORE, or ALL', 11, 1) WITH NOWAIT;
            RETURN;
        END;
        
        /*
        Validate database exists and is accessible
        */
        IF @database_name IS NOT NULL
        BEGIN
            SELECT
                @database_id = d.database_id,
                @online_status = CASE WHEN d.state = 0 THEN 1 ELSE 0 END,
                @readonly_status = CASE 
                                      WHEN d.is_read_only = 1 
                                      OR d.user_access = 1 -- Single user
                                      OR d.state = 1 -- Restoring
                                      OR d.state = 2 -- Recovering
                                      OR d.state = 3 -- Recovery pending
                                      OR d.state = 4 -- Suspect
                                      OR d.state = 5 -- Emergency
                                      OR d.state = 6 -- Offline
                                      OR d.state = 7 -- Copying
                                      OR d.state_desc = N'STANDBY' -- Log restore with standby
                                   THEN 1
                                   ELSE 0
                                END
            FROM sys.databases AS d
            WHERE d.name = @database_name;
            
            IF @database_id IS NULL
            BEGIN
                RAISERROR(N'Database %s does not exist', 11, 1, @database_name) WITH NOWAIT;
                RETURN;
            END;
            
            IF @online_status = 0
            BEGIN
                RAISERROR(N'Database %s is not online', 11, 1, @database_name) WITH NOWAIT;
                RETURN;
            END;
        END;
        
        /*
        Create the database collection table if it doesn't exist
        */
        IF NOT EXISTS 
        (
            SELECT 
                1 
            FROM sys.objects 
            WHERE name = N'database_collection_config' 
            AND schema_id = SCHEMA_ID(N'system')
        )
        BEGIN
            CREATE TABLE
                system.database_collection_config
            (
                database_name NVARCHAR(128) NOT NULL,
                collection_type NVARCHAR(50) NOT NULL,
                added_date DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
                active BIT NOT NULL DEFAULT 1,
                CONSTRAINT PK_database_collection_config 
                    PRIMARY KEY (database_name, collection_type)
            );
            
            IF @debug = 1
            BEGIN
                RAISERROR(N'Created system.database_collection_config table', 0, 1) WITH NOWAIT;
            END;
        END;
        
        /*
        Process the requested action
        */
        IF @action = N'ADD'
        BEGIN
            IF @collection_type = N'ALL'
            BEGIN
                MERGE system.database_collection_config AS target
                USING 
                (
                    SELECT
                        type_name
                    FROM @collection_types
                    WHERE type_name <> N'ALL'
                ) AS source
                ON target.database_name = @database_name
                AND target.collection_type = source.type_name
                WHEN MATCHED THEN
                    UPDATE SET
                        active = 1,
                        added_date = SYSDATETIME()
                WHEN NOT MATCHED THEN
                    INSERT
                    (
                        database_name,
                        collection_type,
                        added_date,
                        active
                    )
                    VALUES
                    (
                        @database_name,
                        source.type_name,
                        SYSDATETIME(),
                        1
                    );
            END;
            ELSE
            BEGIN
                MERGE system.database_collection_config AS target
                USING 
                (
                    SELECT
                        @database_name AS database_name,
                        @collection_type AS collection_type
                ) AS source
                ON target.database_name = source.database_name
                AND target.collection_type = source.collection_type
                WHEN MATCHED THEN
                    UPDATE SET
                        active = 1,
                        added_date = SYSDATETIME()
                WHEN NOT MATCHED THEN
                    INSERT
                    (
                        database_name,
                        collection_type,
                        added_date,
                        active
                    )
                    VALUES
                    (
                        source.database_name,
                        source.collection_type,
                        SYSDATETIME(),
                        1
                    );
            END;
            
            IF @debug = 1
            BEGIN
                RAISERROR(N'Added database %s for %s collection', 0, 1, @database_name, @collection_type) WITH NOWAIT;
            END;
        END;
        ELSE IF @action = N'REMOVE'
        BEGIN
            IF @collection_type = N'ALL'
            BEGIN
                UPDATE
                    system.database_collection_config
                SET
                    active = 0
                WHERE
                    database_name = @database_name;
            END;
            ELSE
            BEGIN
                UPDATE
                    system.database_collection_config
                SET
                    active = 0
                WHERE
                    database_name = @database_name
                AND collection_type = @collection_type;
            END;
            
            IF @debug = 1
            BEGIN
                RAISERROR(N'Removed database %s from %s collection', 0, 1, @database_name, @collection_type) WITH NOWAIT;
            END;
        END;
        ELSE IF @action = N'LIST'
        BEGIN
            -- Extra validation checks for query store readiness
            IF @collection_type = N'QUERY_STORE' OR @collection_type IS NULL
            BEGIN
                SELECT
                    @sql = N'
                    WITH QueryStoreStatus AS
                    (
                        SELECT
                            database_name = DB_NAME(d.database_id),
                            query_store_enabled = CAST(ISNULL(DATABASEPROPERTYEX(DB_NAME(d.database_id), ''IsQueryStoreOn''), 0) AS BIT),
                            query_store_readonly = CAST(0 AS BIT)
                        FROM sys.databases AS d
                        WHERE d.state = 0 -- Online databases only
                        AND d.database_id > 4 -- Exclude system databases
                        AND d.is_read_only = 0
                    )
                    UPDATE qs
                    SET query_store_readonly = 
                        (
                            SELECT
                                CONVERT(BIT, 
                                    CASE
                                        WHEN actual_state = 1 THEN 0
                                        WHEN actual_state = 2 THEN 0
                                        WHEN actual_state = 3 THEN 1
                                        ELSE 1
                                    END
                                )
                            FROM (
                                SELECT
                                    actual_state = TRY_CAST(actual_state AS INTEGER)
                                FROM
                                (
                                    SELECT
                                        actual_state
                                    FROM OPENDATASOURCE(
                                        ''SQLNCLI'',
                                        ''Data Source=(local);Integrated Security=SSPI'').' 
                                        + QUOTENAME(qs.database_name) 
                                        + '.sys.database_query_store_options
                                ) AS x
                            ) AS y
                        )
                    FROM QueryStoreStatus AS qs
                    OPTION (RECOMPILE);
                    
                    SELECT
                        database_name,
                        query_store_enabled,
                        query_store_readonly
                    FROM QueryStoreStatus;
                    ';
            END;
            
            IF @sql <> N''
            BEGIN
                BEGIN TRY
                    EXECUTE sys.sp_executesql @sql;
                END TRY
                BEGIN CATCH
                    -- Gracefully handle query store check failures
                    RAISERROR(N'Could not validate Query Store status: %s', 0, 1, ERROR_MESSAGE()) WITH NOWAIT;
                END CATCH;
            END;
            
            SELECT
                dc.database_name,
                dc.collection_type,
                dc.added_date,
                dc.active,
                database_exists = CASE WHEN DB_ID(dc.database_name) IS NOT NULL THEN 1 ELSE 0 END,
                db_online = CASE WHEN DB_ID(dc.database_name) IS NOT NULL 
                              AND EXISTS (
                                 SELECT 1 FROM sys.databases 
                                 WHERE name = dc.database_name 
                                 AND state = 0
                              ) 
                              THEN 1 ELSE 0 END,
                db_readonly = CASE WHEN DB_ID(dc.database_name) IS NOT NULL 
                               AND EXISTS (
                                  SELECT 1 FROM sys.databases 
                                  WHERE name = dc.database_name 
                                  AND (
                                     is_read_only = 1
                                     OR user_access = 1
                                     OR state > 0
                                     OR state_desc = N'STANDBY'
                                  )
                               ) 
                               THEN 1 ELSE 0 END
            FROM system.database_collection_config AS dc
            WHERE dc.active = 1
            AND (@collection_type IS NULL OR dc.collection_type = @collection_type)
            ORDER BY
                dc.database_name,
                dc.collection_type;
        END;
    END TRY
    BEGIN CATCH
        SET @error_number = ERROR_NUMBER();
        SET @error_severity = ERROR_SEVERITY();
        SET @error_state = ERROR_STATE();
        SET @error_line = ERROR_LINE();
        SET @error_message = ERROR_MESSAGE();
        
        RAISERROR(N'Error %d at line %d: %s', 11, 1, @error_number, @error_line, @error_message) WITH NOWAIT;
        THROW;
    END CATCH;
END;
GO