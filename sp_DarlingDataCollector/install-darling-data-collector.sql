/*
    sqlcmd-mode installer for Erik Darling Data DarlingDataCollector procs.

    run from sqlcmd.exe using the following command-line:

    sqlcmd -S {sql-server} -i .\install-darling-data-collector.sql -v TargetDB = "{target-database}"

    {sql-server} is the name of the target SQL Server
    {target-database} is where we'll install the DarlingDataCollector procedures.
*/
:on error exit
:setvar SqlCmdEnabled "True"
DECLARE @msg nvarchar(2048);
SET @msg = N'DarlingDataCollector installer, by Erik Darling Data.';
RAISERROR (@msg, 10, 1) WITH NOWAIT;
SET @msg = N'Connected to SQL Server ' + @@SERVERNAME + N' as ' + SUSER_SNAME();
RAISERROR (@msg, 10, 1) WITH NOWAIT;

IF '$(SqlCmdEnabled)' NOT LIKE 'True'
BEGIN
    RAISERROR (N'This script is designed to run via sqlcmd.  Aborting.', 10, 127) WITH NOWAIT;
    SET NOEXEC ON;
END

IF N'$(TargetDB)' = N''
BEGIN
    SET @msg = N'You must specify the target database via the sqlcmd -V parameter (TargetDB = "{server-name}")';
    RAISERROR (@msg, 10, 1) WITH NOWAIT;
    SET @msg = N'sqlcmd.exe -S <servername> -E -i .\install-darling-data-collector.sql -v TargetDB = "<database_name>"';
    RAISERROR (@msg, 10, 1) WITH NOWAIT;
    SET @msg = N'Aborting.';
    RAISERROR (@msg, 10, 127) WITH NOWAIT;
    SET NOEXEC ON;
END

IF NOT EXISTS
(
    SELECT 1
    FROM [sys].[databases] d
    WHERE d.[name] = N'$(TargetDB)'
)
BEGIN
    SET @msg = N'The specified target database, $(TargetDB), does not exist.  Please ensure the specified database exists, and is accessible to login ' + QUOTENAME(SUSER_SNAME()) + N'.';
    RAISERROR (@msg, 10, 127) WITH NOWAIT;
    SET NOEXEC ON;
END
ELSE
BEGIN
    SET @msg = N'DarlingDataCollector and related procs will be installed into the [$(TargetDB)] database.';
    RAISERROR (@msg, 10, 1) WITH NOWAIT;
END

USE [$(TargetDB)];
GO

/*
Create required schemas
*/
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'collection')
BEGIN
    EXEC('CREATE SCHEMA collection;');
    RAISERROR(N'Created [collection] schema', 0, 1) WITH NOWAIT;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'system')
BEGIN
    EXEC('CREATE SCHEMA system;');
    RAISERROR(N'Created [system] schema', 0, 1) WITH NOWAIT;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'analysis')
BEGIN
    EXEC('CREATE SCHEMA analysis;');
    RAISERROR(N'Created [analysis] schema', 0, 1) WITH NOWAIT;
END
GO

/*
Create system tables
*/
IF OBJECT_ID('system.collection_log') IS NULL
BEGIN
    CREATE TABLE
        system.collection_log
    (
        log_id BIGINT IDENTITY(1,1) NOT NULL,
        procedure_name NVARCHAR(400) NOT NULL,
        collection_start DATETIME2(7) NOT NULL,
        collection_end DATETIME2(7) NOT NULL,
        rows_collected BIGINT NOT NULL,
        status NVARCHAR(100) NOT NULL,
        error_number INTEGER NULL,
        error_message NVARCHAR(4000) NULL,
        CONSTRAINT pk_collection_log PRIMARY KEY CLUSTERED (log_id)
    );
    RAISERROR(N'Created [system].[collection_log] table', 0, 1) WITH NOWAIT;
END
GO

IF OBJECT_ID('system.server_info') IS NULL
BEGIN
    CREATE TABLE
        system.server_info
    (
        server_id INTEGER IDENTITY(1,1) NOT NULL,
        collection_time DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
        server_name NVARCHAR(128) NOT NULL,
        product_version NVARCHAR(128) NOT NULL,
        edition NVARCHAR(128) NOT NULL,
        platform NVARCHAR(50) NOT NULL, /* OnPrem, Azure, AWS */
        instance_type NVARCHAR(50) NOT NULL, /* Regular, AzureDB, AzureMI, AWSRDS */
        compatibility_level INTEGER NOT NULL,
        product_level NVARCHAR(128) NOT NULL,
        product_update_level NVARCHAR(128) NULL,
        physical_memory_mb BIGINT NULL,
        cpu_count INTEGER NOT NULL,
        scheduler_count INTEGER NOT NULL,
        CONSTRAINT pk_server_info PRIMARY KEY CLUSTERED (server_id)
    );
    RAISERROR(N'Created [system].[server_info] table', 0, 1) WITH NOWAIT;
END
GO

IF OBJECT_ID('system.database_collection_config') IS NULL
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
    RAISERROR(N'Created [system].[database_collection_config] table', 0, 1) WITH NOWAIT;
END
GO

/*
Create system.create_collector_table procedure
*/
RAISERROR (N'Creating system.create_collector_table procedure', 0, 1) WITH NOWAIT;
GO

:r ./system.create_collector_table.sql
GO

/*
Create system.detect_environment procedure
*/
RAISERROR (N'Creating system.detect_environment procedure', 0, 1) WITH NOWAIT;
GO
CREATE OR ALTER PROCEDURE
    system.detect_environment
(
    @debug BIT = 0 /*Print debugging information*/
)
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
    
    DECLARE
        @platform NVARCHAR(50),
        @instance_type NVARCHAR(50),
        @product_version NVARCHAR(128),
        @edition NVARCHAR(128),
        @compatibility_level INTEGER,
        @product_level NVARCHAR(128),
        @product_update_level NVARCHAR(128),
        @physical_memory_mb BIGINT,
        @cpu_count INTEGER,
        @scheduler_count INTEGER,
        @is_supported BIT = 1,
        @unsupported_message NVARCHAR(512) = NULL;
    
    /*
    Get product information
    */
    SELECT
        @product_version = CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(128)),
        @edition = CAST(SERVERPROPERTY('Edition') AS NVARCHAR(128)),
        @compatibility_level = compatibility_level,
        @product_level = CAST(SERVERPROPERTY('ProductLevel') AS NVARCHAR(128)),
        @product_update_level = CAST(SERVERPROPERTY('ProductUpdateLevel') AS NVARCHAR(128))
    FROM sys.databases
    WHERE database_id = DB_ID();
    
    /*
    Determine platform and instance type
    */
    IF @edition LIKE '%Azure%'
    BEGIN
        SET @platform = 'Azure';
        
        IF @edition LIKE '%Database%'
        BEGIN
            SET @instance_type = 'AzureDB';
            SET @is_supported = 0;
            SET @unsupported_message = 'Azure SQL Database is not supported by DarlingDataCollector due to limitations with SQL Agent and other system-level features.';
        END;
        ELSE IF @edition LIKE '%Managed%'
        BEGIN
            SET @instance_type = 'AzureMI';
        END;
    END;
    ELSE IF DB_ID('rdsadmin') IS NOT NULL
    BEGIN
        SET @platform = 'AWS';
        SET @instance_type = 'AWSRDS';
    END;
    ELSE
    BEGIN
        SET @platform = 'OnPrem';
        SET @instance_type = 'Regular';
    END;
    
    /* 
    Check for unsupported environment and print message
    */
    IF @is_supported = 0
    BEGIN
        RAISERROR('ENVIRONMENT NOT SUPPORTED: %s', 16, 1, @unsupported_message);
        RETURN;
    END;
    
    /*
    Get system information
    */
    SELECT
        @cpu_count = cpu_count,
        @scheduler_count = scheduler_count
    FROM sys.dm_os_sys_info;
    
    /*
    Get physical memory if available
    */
    IF @instance_type IN ('Regular', 'AWSRDS')
    BEGIN
        SELECT
            @physical_memory_mb = physical_memory_kb / 1024
        FROM sys.dm_os_sys_info;
    END;
    
    /*
    Store or update server information
    */
    IF EXISTS (SELECT 1 FROM system.server_info)
    BEGIN
        UPDATE
            system.server_info
        SET
            collection_time = SYSDATETIME(),
            server_name = @@SERVERNAME,
            product_version = @product_version,
            edition = @edition,
            platform = @platform,
            instance_type = @instance_type,
            compatibility_level = @compatibility_level,
            product_level = @product_level,
            product_update_level = @product_update_level,
            physical_memory_mb = @physical_memory_mb,
            cpu_count = @cpu_count,
            scheduler_count = @scheduler_count;
    END;
    ELSE
    BEGIN
        INSERT
            system.server_info
        (
            collection_time,
            server_name,
            product_version,
            edition,
            platform,
            instance_type,
            compatibility_level,
            product_level, 
            product_update_level,
            physical_memory_mb,
            cpu_count,
            scheduler_count
        )
        VALUES
        (
            SYSDATETIME(),
            @@SERVERNAME,
            @product_version,
            @edition,
            @platform,
            @instance_type,
            @compatibility_level,
            @product_level,
            @product_update_level,
            @physical_memory_mb,
            @cpu_count,
            @scheduler_count
        );
    END;
    
    /*
    Print debugging information if requested
    */
    IF @debug = 1
    BEGIN
        SELECT
            server_name,
            product_version,
            edition,
            platform,
            instance_type,
            compatibility_level,
            product_level,
            product_update_level,
            physical_memory_mb,
            cpu_count,
            scheduler_count
        FROM system.server_info;
    END;
END;
GO

/*
Create system.manage_databases procedure
*/
RAISERROR (N'Creating system.manage_databases procedure', 0, 1) WITH NOWAIT;
GO
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
            (3, N'FILE_SPACE'),
            (4, N'PROCEDURE_STATS'),
            (5, N'ALL');
            
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
  @collection_type = Collection type: INDEX, QUERY_STORE, FILE_SPACE, PROCEDURE_STATS, ALL (required for ADD, REMOVE)
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
            RAISERROR(N'@collection_type must be INDEX, QUERY_STORE, FILE_SPACE, PROCEDURE_STATS, or ALL', 11, 1) WITH NOWAIT;
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

/*
Create system.data_retention procedure
*/
RAISERROR (N'Creating system.data_retention procedure', 0, 1) WITH NOWAIT;
GO
CREATE OR ALTER PROCEDURE
    system.data_retention
(
    @retention_days INTEGER = 30, /*Number of days to retain collected data*/
    @exclude_tables NVARCHAR(MAX) = NULL, /*Comma-separated list of tables to exclude from purge*/
    @debug BIT = 0, /*Print debugging information*/
    @help BIT = 0 /*Print help information*/
)
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
            @cutoff_date DATETIME2(7) = DATEADD(DAY, -@retention_days, SYSDATETIME()),
            @table_name NVARCHAR(256),
            @rows_deleted BIGINT = 0,
            @total_rows_deleted BIGINT = 0;
            
        DECLARE
            @exclude_table_list TABLE
            (
                table_name NVARCHAR(256) NOT NULL PRIMARY KEY
            );
            
        DECLARE
            @collection_tables TABLE
            (
                table_id INTEGER IDENTITY(1,1) NOT NULL,
                table_name NVARCHAR(256) NOT NULL,
                schema_name NVARCHAR(128) NOT NULL,
                has_collection_time BIT NOT NULL,
                has_collection_id BIT NOT NULL,
                PRIMARY KEY (table_id)
            );
            
        /*
        Parameter validation
        */
        IF @help = 1
        BEGIN
            SELECT
                help = N'This procedure manages data retention for the collector tables.
                
Parameters:
  @retention_days = Number of days to retain data (default: 30)
  @exclude_tables = Comma-separated list of tables to exclude from purge
  @debug = 1 to print detailed information, 0 for normal operation
  @help = 1 to show this help information

Example usage:
  -- Set retention to 90 days
  EXECUTE system.data_retention @retention_days = 90;
  
  -- Exclude specific tables from data retention
  EXECUTE system.data_retention @exclude_tables = ''query_store_queries,query_store_plans'';';
            
            RETURN;
        END;
        
        IF @retention_days <= 0
        BEGIN
            RAISERROR(N'@retention_days must be greater than 0', 11, 1) WITH NOWAIT;
            RETURN;
        END;
        
        /*
        Build exclude table list
        */
        IF @exclude_tables IS NOT NULL
        BEGIN
            INSERT @exclude_table_list
            (
                table_name
            )
            SELECT
                table_name = LTRIM(RTRIM(value))
            FROM STRING_SPLIT(@exclude_tables, N',');
            
            IF @debug = 1
            BEGIN
                SELECT
                    excluded_tables = STRING_AGG(table_name, ', ')
                FROM @exclude_table_list;
            END;
        END;
        
        /*
        Get list of collection tables with timestamps
        */
        INSERT @collection_tables
        (
            table_name,
            schema_name,
            has_collection_time,
            has_collection_id
        )
        SELECT
            t.name,
            s.name,
            has_collection_time = 
                CASE 
                    WHEN EXISTS (
                        SELECT 1
                        FROM sys.columns AS c
                        WHERE c.object_id = t.object_id
                        AND c.name = 'collection_time'
                    ) THEN 1 
                    ELSE 0 
                END,
            has_collection_id = 
                CASE 
                    WHEN EXISTS (
                        SELECT 1
                        FROM sys.columns AS c
                        WHERE c.object_id = t.object_id
                        AND c.name = 'collection_id'
                    ) THEN 1 
                    ELSE 0 
                END
        FROM sys.tables AS t
        JOIN sys.schemas AS s
            ON t.schema_id = s.schema_id
        WHERE s.name = 'collection'
        AND t.name NOT IN (SELECT table_name FROM @exclude_table_list);
        
        IF @debug = 1
        BEGIN
            SELECT
                table_count = COUNT(*)
            FROM @collection_tables;
        END;
        
        /*
        Process each collection table
        */
        DECLARE table_cursor CURSOR LOCAL FORWARD_ONLY READ_ONLY
        FOR
            SELECT
                schema_name + '.' + table_name
            FROM @collection_tables
            WHERE has_collection_time = 1
            ORDER BY
                table_id;
                
        OPEN table_cursor;
        
        FETCH NEXT FROM
            table_cursor
        INTO
            @table_name;
            
        WHILE @@FETCH_STATUS = 0
        BEGIN
            /*
            Build and execute DELETE statement
            */
            SET @sql = N'
                DELETE TOP (100000)
                FROM ' + @table_name + '
                WHERE collection_time < @cutoff_date;
                
                SET @rows_deleted = @@ROWCOUNT;
            ';
            
            SET @rows_deleted = 0;
            
            WHILE 1 = 1
            BEGIN
                EXECUTE sp_executesql
                    @sql,
                    N'@cutoff_date DATETIME2(7), @rows_deleted BIGINT OUTPUT',
                    @cutoff_date,
                    @rows_deleted OUTPUT;
                    
                SET @total_rows_deleted = @total_rows_deleted + @rows_deleted;
                
                IF @debug = 1 AND @rows_deleted > 0
                BEGIN
                    RAISERROR(N'Deleted %d rows from %s', 0, 1, @rows_deleted, @table_name) WITH NOWAIT;
                END;
                
                IF @rows_deleted < 100000
                    BREAK;
            END;
            
            FETCH NEXT FROM
                table_cursor
            INTO
                @table_name;
        END;
        
        CLOSE table_cursor;
        DEALLOCATE table_cursor;
        
        /*
        Log retention results
        */
        IF @debug = 1
        BEGIN
            RAISERROR(N'Data retention completed. Total rows deleted: %d', 0, 1, @total_rows_deleted) WITH NOWAIT;
        END;
    END TRY
    BEGIN CATCH
        IF CURSOR_STATUS('local', 'table_cursor') >= 0
        BEGIN
            CLOSE table_cursor;
            DEALLOCATE table_cursor;
        END;
        
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

/*
Create system.create_collection_jobs procedure
*/
RAISERROR (N'Creating system.create_collection_jobs procedure', 0, 1) WITH NOWAIT;
GO
CREATE OR ALTER PROCEDURE
    system.create_collection_jobs
(
    @debug BIT = 0, /*Print debugging information*/
    @minute_frequency INTEGER = 15, /*Frequency in minutes for regular collections*/
    @hourly_frequency INTEGER = 60, /*Frequency in minutes for hourly collections*/
    @daily_frequency INTEGER = 1440, /*Frequency in minutes for daily collections*/
    @retention_days INTEGER = 30 /*Number of days to retain collected data*/
)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE
        @job_exists INTEGER,
        @job_id UNIQUEIDENTIFIER,
        @platform NVARCHAR(50),
        @instance_type NVARCHAR(50),
        @is_supported BIT = 1;
    
    /*
    Check environment type
    */
    SELECT TOP 1
        @platform = platform,
        @instance_type = instance_type
    FROM system.server_info
    ORDER BY collection_time DESC;
    
    /*
    Verify we're not in Azure SQL DB
    */
    IF @instance_type = 'AzureDB'
    BEGIN
        RAISERROR('SQL Agent jobs cannot be created in Azure SQL Database. Please use an external scheduling mechanism.', 16, 1);
        RETURN;
    END;
    
    /*
    Check if SQL Agent is available
    */
    IF NOT EXISTS (SELECT 1 FROM sys.all_objects WHERE name = 'sysjobs' AND type = 'U')
    BEGIN
        RAISERROR('SQL Agent is not available in this environment. Job creation skipped.', 16, 1);
        RETURN;
    END;
    
    /*
    Create master collection job
    */
    SELECT
        @job_exists = 0;
        
    IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = 'DarlingDataCollector - Master Collection')
    BEGIN
        SELECT
            @job_exists = 1,
            @job_id = job_id
        FROM msdb.dbo.sysjobs
        WHERE name = 'DarlingDataCollector - Master Collection';
    END;
    
    IF @job_exists = 0
    BEGIN
        EXECUTE msdb.dbo.sp_add_job
            @job_name = 'DarlingDataCollector - Master Collection',
            @description = 'Master job for all DarlingDataCollector activities',
            @category_name = 'Data Collector',
            @owner_login_name = 'sa',
            @enabled = 1,
            @job_id = @job_id OUTPUT;
        
        EXECUTE msdb.dbo.sp_add_jobserver
            @job_id = @job_id,
            @server_name = @@SERVERNAME;
    END;
    
    /*
    Create regular collection job
    */
    SELECT
        @job_exists = 0;
        
    IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = 'DarlingDataCollector - Regular Collections')
    BEGIN
        SELECT
            @job_exists = 1,
            @job_id = job_id
        FROM msdb.dbo.sysjobs
        WHERE name = 'DarlingDataCollector - Regular Collections';
    END;
    
    IF @job_exists = 0
    BEGIN
        DECLARE
            @cmd_wait_stats NVARCHAR(512),
            @cmd_memory_clerks NVARCHAR(512),
            @cmd_buffer_pool NVARCHAR(512),
            @cmd_io_stats NVARCHAR(512),
            @cmd_memory_grants NVARCHAR(512),
            @cmd_process_memory NVARCHAR(512),
            @cmd_connections NVARCHAR(512),
            @cmd_blocking NVARCHAR(512),
            @cmd_perf_counters NVARCHAR(512),
            @cmd_schedulers NVARCHAR(512);
            
        SELECT
            @cmd_wait_stats = N'EXECUTE ' + QUOTENAME(DB_NAME()) + N'.collection.collect_wait_stats @sample_seconds = 60;',
            @cmd_memory_clerks = N'EXECUTE ' + QUOTENAME(DB_NAME()) + N'.collection.collect_memory_clerks;',
            @cmd_buffer_pool = N'EXECUTE ' + QUOTENAME(DB_NAME()) + N'.collection.collect_buffer_pool;',
            @cmd_io_stats = N'EXECUTE ' + QUOTENAME(DB_NAME()) + N'.collection.collect_io_stats @sample_seconds = 60;',
            @cmd_memory_grants = N'EXECUTE ' + QUOTENAME(DB_NAME()) + N'.collection.collect_memory_grants;',
            @cmd_process_memory = N'EXECUTE ' + QUOTENAME(DB_NAME()) + N'.collection.collect_process_memory;',
            @cmd_connections = N'EXECUTE ' + QUOTENAME(DB_NAME()) + N'.collection.collect_connections;',
            @cmd_blocking = N'EXECUTE ' + QUOTENAME(DB_NAME()) + N'.collection.collect_blocking;',
            @cmd_perf_counters = N'EXECUTE ' + QUOTENAME(DB_NAME()) + N'.collection.collect_perf_counters;',
            @cmd_schedulers = N'EXECUTE ' + QUOTENAME(DB_NAME()) + N'.collection.collect_schedulers;';
            
        EXECUTE msdb.dbo.sp_add_job
            @job_name = 'DarlingDataCollector - Regular Collections',
            @description = 'Collects regular performance metrics (wait stats, memory, blocking)',
            @category_name = 'Data Collector',
            @owner_login_name = 'sa',
            @enabled = 1,
            @job_id = @job_id OUTPUT;
        
        EXECUTE msdb.dbo.sp_add_jobserver
            @job_id = @job_id,
            @server_name = @@SERVERNAME;
            
        /*
        Add job steps
        */
        EXECUTE msdb.dbo.sp_add_jobstep
            @job_id = @job_id,
            @step_name = 'Collect Wait Stats',
            @step_id = 1,
            @subsystem = 'TSQL',
            @command = @cmd_wait_stats,
            @database_name = DB_NAME(),
            @on_success_action = 3,
            @on_fail_action = 3;
            
        EXECUTE msdb.dbo.sp_add_jobstep
            @job_id = @job_id,
            @step_name = 'Collect Memory Clerks',
            @step_id = 2,
            @subsystem = 'TSQL',
            @command = @cmd_memory_clerks,
            @database_name = DB_NAME(),
            @on_success_action = 3,
            @on_fail_action = 3;
            
        EXECUTE msdb.dbo.sp_add_jobstep
            @job_id = @job_id,
            @step_name = 'Collect Buffer Pool',
            @step_id = 3,
            @subsystem = 'TSQL',
            @command = @cmd_buffer_pool,
            @database_name = DB_NAME(),
            @on_success_action = 3,
            @on_fail_action = 3;
            
        EXECUTE msdb.dbo.sp_add_jobstep
            @job_id = @job_id,
            @step_name = 'Collect I/O Stats',
            @step_id = 4,
            @subsystem = 'TSQL',
            @command = @cmd_io_stats,
            @database_name = DB_NAME(),
            @on_success_action = 3,
            @on_fail_action = 3;
            
        EXECUTE msdb.dbo.sp_add_jobstep
            @job_id = @job_id,
            @step_name = 'Collect Memory Grants',
            @step_id = 5,
            @subsystem = 'TSQL',
            @command = @cmd_memory_grants,
            @database_name = DB_NAME(),
            @on_success_action = 3,
            @on_fail_action = 3;
            
        EXECUTE msdb.dbo.sp_add_jobstep
            @job_id = @job_id,
            @step_name = 'Collect Process Memory',
            @step_id = 6,
            @subsystem = 'TSQL',
            @command = @cmd_process_memory,
            @database_name = DB_NAME(),
            @on_success_action = 3,
            @on_fail_action = 3;
            
        EXECUTE msdb.dbo.sp_add_jobstep
            @job_id = @job_id,
            @step_name = 'Collect Connections',
            @step_id = 7,
            @subsystem = 'TSQL',
            @command = @cmd_connections,
            @database_name = DB_NAME(),
            @on_success_action = 3,
            @on_fail_action = 3;
            
        EXECUTE msdb.dbo.sp_add_jobstep
            @job_id = @job_id,
            @step_name = 'Collect Blocking',
            @step_id = 8,
            @subsystem = 'TSQL',
            @command = @cmd_blocking,
            @database_name = DB_NAME(),
            @on_success_action = 3,
            @on_fail_action = 3;
            
        EXECUTE msdb.dbo.sp_add_jobstep
            @job_id = @job_id,
            @step_name = 'Collect Performance Counters',
            @step_id = 9,
            @subsystem = 'TSQL',
            @command = @cmd_perf_counters,
            @database_name = DB_NAME(),
            @on_success_action = 3,
            @on_fail_action = 3;
            
        EXECUTE msdb.dbo.sp_add_jobstep
            @job_id = @job_id,
            @step_name = 'Collect Schedulers',
            @step_id = 10,
            @subsystem = 'TSQL',
            @command = @cmd_schedulers,
            @database_name = DB_NAME(),
            @on_success_action = 1,
            @on_fail_action = 2;
            
        /*
        Create schedule
        */
        EXECUTE msdb.dbo.sp_add_jobschedule
            @job_id = @job_id,
            @name = 'Regular Collection Schedule',
            @enabled = 1,
            @freq_type = 4, -- Daily
            @freq_interval = 1,
            @freq_subday_type = 4, -- Minutes
            @freq_subday_interval = @minute_frequency,
            @active_start_date = 20250101,
            @active_end_date = 99991231,
            @active_start_time = 0,
            @active_end_time = 235959;
    END;
    
    /*
    Create hourly collection job
    */
    SELECT
        @job_exists = 0;
        
    IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = 'DarlingDataCollector - Hourly Collections')
    BEGIN
        SELECT
            @job_exists = 1,
            @job_id = job_id
        FROM msdb.dbo.sysjobs
        WHERE name = 'DarlingDataCollector - Hourly Collections';
    END;
    
    IF @job_exists = 0
    BEGIN
        DECLARE
            @cmd_index_usage_stats NVARCHAR(512),
            @cmd_query_stats NVARCHAR(512),
            @cmd_detailed_waits NVARCHAR(512),
            @cmd_procedure_stats NVARCHAR(512);
            
        SELECT
            @cmd_index_usage_stats = N'EXECUTE ' + QUOTENAME(DB_NAME()) + N'.collection.collect_index_usage_stats @use_database_list = 1;',
            @cmd_query_stats = N'EXECUTE ' + QUOTENAME(DB_NAME()) + N'.collection.collect_query_stats;',
            @cmd_detailed_waits = N'EXECUTE ' + QUOTENAME(DB_NAME()) + N'.collection.collect_detailed_waits;',
            @cmd_procedure_stats = N'EXECUTE ' + QUOTENAME(DB_NAME()) + N'.collection.collect_procedure_stats @use_database_list = 1;';
            
        EXECUTE msdb.dbo.sp_add_job
            @job_name = 'DarlingDataCollector - Hourly Collections',
            @description = 'Collects hourly performance metrics (indexes, queries, procedures)',
            @category_name = 'Data Collector',
            @owner_login_name = 'sa',
            @enabled = 1,
            @job_id = @job_id OUTPUT;
        
        EXECUTE msdb.dbo.sp_add_jobserver
            @job_id = @job_id,
            @server_name = @@SERVERNAME;
            
        /*
        Add job steps
        */
        EXECUTE msdb.dbo.sp_add_jobstep
            @job_id = @job_id,
            @step_name = 'Collect Index Usage Stats',
            @step_id = 1,
            @subsystem = 'TSQL',
            @command = @cmd_index_usage_stats,
            @database_name = DB_NAME(),
            @on_success_action = 3,
            @on_fail_action = 3;
            
        EXECUTE msdb.dbo.sp_add_jobstep
            @job_id = @job_id,
            @step_name = 'Collect Query Stats',
            @step_id = 2,
            @subsystem = 'TSQL',
            @command = @cmd_query_stats,
            @database_name = DB_NAME(),
            @on_success_action = 3,
            @on_fail_action = 3;
            
        EXECUTE msdb.dbo.sp_add_jobstep
            @job_id = @job_id,
            @step_name = 'Collect Detailed Waits',
            @step_id = 3,
            @subsystem = 'TSQL',
            @command = @cmd_detailed_waits,
            @database_name = DB_NAME(),
            @on_success_action = 3,
            @on_fail_action = 3;
            
        EXECUTE msdb.dbo.sp_add_jobstep
            @job_id = @job_id,
            @step_name = 'Collect Procedure Stats',
            @step_id = 4,
            @subsystem = 'TSQL',
            @command = @cmd_procedure_stats,
            @database_name = DB_NAME(),
            @on_success_action = 1,
            @on_fail_action = 2;
            
        /*
        Create schedule
        */
        EXECUTE msdb.dbo.sp_add_jobschedule
            @job_id = @job_id,
            @name = 'Hourly Collection Schedule',
            @enabled = 1,
            @freq_type = 4, -- Daily
            @freq_interval = 1,
            @freq_subday_type = 4, -- Minutes
            @freq_subday_interval = @hourly_frequency,
            @active_start_date = 20250101,
            @active_end_date = 99991231,
            @active_start_time = 0,
            @active_end_time = 235959;
    END;
    
    /*
    Create daily collection job
    */
    SELECT
        @job_exists = 0;
        
    IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = 'DarlingDataCollector - Daily Collections')
    BEGIN
        SELECT
            @job_exists = 1,
            @job_id = job_id
        FROM msdb.dbo.sysjobs
        WHERE name = 'DarlingDataCollector - Daily Collections';
    END;
    
    IF @job_exists = 0
    BEGIN
        DECLARE
            @cmd_file_space NVARCHAR(512),
            @cmd_query_store NVARCHAR(512),
            @cmd_missing_indexes NVARCHAR(512),
            @cmd_deadlocks NVARCHAR(512),
            @cmd_data_retention NVARCHAR(512);
            
        SELECT
            @cmd_file_space = N'EXECUTE ' + QUOTENAME(DB_NAME()) + N'.collection.collect_file_space @use_database_list = 1;',
            @cmd_query_store = N'EXECUTE ' + QUOTENAME(DB_NAME()) + N'.collection.collect_query_store @use_database_list = 1;',
            @cmd_missing_indexes = N'EXECUTE ' + QUOTENAME(DB_NAME()) + N'.collection.collect_missing_indexes @use_database_list = 1;',
            @cmd_deadlocks = N'EXECUTE ' + QUOTENAME(DB_NAME()) + N'.collection.collect_deadlocks;',
            @cmd_data_retention = N'EXECUTE ' + QUOTENAME(DB_NAME()) + N'.system.data_retention @retention_days = ' + 
                CAST(@retention_days AS NVARCHAR(10)) + N';';
            
        EXECUTE msdb.dbo.sp_add_job
            @job_name = 'DarlingDataCollector - Daily Collections',
            @description = 'Collects daily metrics and performs data maintenance',
            @category_name = 'Data Collector',
            @owner_login_name = 'sa',
            @enabled = 1,
            @job_id = @job_id OUTPUT;
        
        EXECUTE msdb.dbo.sp_add_jobserver
            @job_id = @job_id,
            @server_name = @@SERVERNAME;
            
        /*
        Add job steps
        */
        EXECUTE msdb.dbo.sp_add_jobstep
            @job_id = @job_id,
            @step_name = 'Collect File Space',
            @step_id = 1,
            @subsystem = 'TSQL',
            @command = @cmd_file_space,
            @database_name = DB_NAME(),
            @on_success_action = 3,
            @on_fail_action = 3;
            
        EXECUTE msdb.dbo.sp_add_jobstep
            @job_id = @job_id,
            @step_name = 'Collect Query Store',
            @step_id = 2,
            @subsystem = 'TSQL',
            @command = @cmd_query_store,
            @database_name = DB_NAME(),
            @on_success_action = 3,
            @on_fail_action = 3;
            
        EXECUTE msdb.dbo.sp_add_jobstep
            @job_id = @job_id,
            @step_name = 'Collect Missing Indexes',
            @step_id = 3,
            @subsystem = 'TSQL',
            @command = @cmd_missing_indexes,
            @database_name = DB_NAME(),
            @on_success_action = 3,
            @on_fail_action = 3;
            
        EXECUTE msdb.dbo.sp_add_jobstep
            @job_id = @job_id,
            @step_name = 'Collect Deadlocks',
            @step_id = 4,
            @subsystem = 'TSQL',
            @command = @cmd_deadlocks,
            @database_name = DB_NAME(),
            @on_success_action = 3,
            @on_fail_action = 3;
            
        EXECUTE msdb.dbo.sp_add_jobstep
            @job_id = @job_id,
            @step_name = 'Run Data Retention',
            @step_id = 5,
            @subsystem = 'TSQL',
            @command = @cmd_data_retention,
            @database_name = DB_NAME(),
            @on_success_action = 1,
            @on_fail_action = 2;
            
        /*
        Create schedule
        */
        EXECUTE msdb.dbo.sp_add_jobschedule
            @job_id = @job_id,
            @name = 'Daily Collection Schedule',
            @enabled = 1,
            @freq_type = 4, -- Daily
            @freq_interval = 1,
            @freq_subday_type = 1, -- At specified time
            @freq_subday_interval = 0,
            @active_start_date = 20250101,
            @active_end_date = 99991231,
            @active_start_time = 10000, -- 1:00 AM
            @active_end_time = 235959;
    END;
    
    /*
    Print debug information
    */
    IF @debug = 1
    BEGIN
        SELECT
            'Collection and retention jobs created' AS status,
            @platform AS platform,
            @instance_type AS instance_type;
            
        SELECT
            name,
            enabled,
            description
        FROM msdb.dbo.sysjobs
        WHERE name LIKE 'DarlingDataCollector%';
        
        SELECT
            j.name AS job_name,
            s.step_id,
            s.step_name,
            s.database_name,
            s.command
        FROM msdb.dbo.sysjobs AS j
        JOIN msdb.dbo.sysjobsteps AS s
            ON j.job_id = s.job_id
        WHERE j.name LIKE 'DarlingDataCollector%'
        ORDER BY j.name, s.step_id;
    END;
END;
GO

/*
Now include all the collector files in logical order:
1. Core metrics (wait stats, memory, buffer pool)
2. I/O and resource monitoring
3. Query and index monitoring
4. Session and blocking monitoring
5. Advanced data collection
*/

-- Core metrics
:r ./01_collection.collect_wait_stats.sql
:r ./02_collection.collect_memory_clerks.sql
:r ./03_collection.collect_buffer_pool.sql

-- I/O and resource monitoring
:r ./17_collection.collect_io_stats.sql
:r ./05_collection.collect_process_memory.sql
:r ./04_collection.collect_memory_grants.sql
:r ./06_collection.collect_schedulers.sql
:r ./07_collection.collect_perf_counters.sql
:r ./08_collection.collect_file_space.sql

-- Query and index monitoring
:r ./18_collection.collect_query_stats.sql
:r ./09_collection.collect_procedure_stats.sql
:r ./19_collection.collect_query_store.sql
:r ./16_collection.collect_index_usage_stats.sql
:r ./10_collection.collect_missing_indexes.sql

-- Session and blocking monitoring
:r ./14_collection.collect_connections.sql
:r ./13_collection.collect_blocking.sql
:r ./12_collection.collect_detailed_waits.sql
:r ./11_collection.collect_transactions.sql
:r ./15_collection.collect_deadlocks.sql
GO

/*
Post-installation steps
*/
RAISERROR (N'Running post-installation setup', 0, 1) WITH NOWAIT;
GO

-- Run environment detection
EXECUTE system.detect_environment
    @debug = 1;
GO

-- Create initial jobs
EXECUTE system.create_collection_jobs
    @debug = 1;
GO

RAISERROR (N'Installation complete!', 0, 1) WITH NOWAIT;
GO