/*
Test script for validating collection.collect_query_store procedure
This script:
1. Creates the collection schema if needed
2. Tests basic Query Store collection
3. Tests filtering by various metrics
4. Verifies database selection from configuration
*/

-- Use the DarlingDataCollector database
USE DarlingData;
GO

-- Enable advanced output
SET NOCOUNT ON;
PRINT '-- Starting Query Store collection test --';

-- Create collection schema if it doesn't exist
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'collection')
BEGIN
    PRINT 'Creating collection schema...';
    EXEC('CREATE SCHEMA collection');
END
GO

-- Create system schema if it doesn't exist
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'system')
BEGIN
    PRINT 'Creating system schema...';
    EXEC('CREATE SCHEMA system');
END
GO

-- Make sure system.database_collection_config exists
IF NOT EXISTS 
(
    SELECT 
        1 
    FROM sys.objects 
    WHERE name = N'database_collection_config' 
    AND schema_id = SCHEMA_ID(N'system')
)
BEGIN
    PRINT 'Creating database_collection_config table...';
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
END
GO

-- Help information
PRINT '';
PRINT '-- Testing help information --';
EXEC collection.collect_query_store @help = 1;
GO

-- Test collecting Query Store data without any database configured
PRINT '';
PRINT '-- Testing base collection with no database filtering --';
PRINT 'This will attempt to collect from all eligible databases:';
EXEC collection.collect_query_store 
    @debug = 1,
    @use_database_list = 0,
    @min_cpu_time_ms = 100;
GO

-- Add a system database to the collection configuration
PRINT '';
PRINT '-- Adding system database for collection --';
PRINT 'Adding master database for QUERY_STORE collection:';
IF EXISTS (SELECT 1 FROM system.database_collection_config WHERE database_name = 'master' AND collection_type = 'QUERY_STORE')
BEGIN
    UPDATE system.database_collection_config 
    SET active = 1 
    WHERE database_name = 'master' AND collection_type = 'QUERY_STORE';
END
ELSE
BEGIN
    INSERT system.database_collection_config (database_name, collection_type, active)
    VALUES ('master', 'QUERY_STORE', 1);
END
GO

-- Test collecting with database list from configuration
PRINT '';
PRINT '-- Testing collection with database configuration --';
EXEC collection.collect_query_store 
    @debug = 1,
    @use_database_list = 1,
    @min_cpu_time_ms = 100;
GO

-- Test parameter validation
PRINT '';
PRINT '-- Testing parameter validation --';
PRINT 'Testing invalid date range (should fail):';
BEGIN TRY
    EXEC collection.collect_query_store 
        @debug = 1,
        @start_time = '2025-01-01',
        @end_time = '2020-01-01';
    PRINT 'Test failed: Procedure should have raised an error for invalid date range';
END TRY
BEGIN CATCH
    PRINT 'Error caught as expected: ' + ERROR_MESSAGE();
END CATCH
GO

-- Test excluding system databases
PRINT '';
PRINT '-- Testing system database exclusion --';
EXEC collection.collect_query_store 
    @debug = 1,
    @use_database_list = 0,
    @exclude_system_databases = 1,
    @min_cpu_time_ms = 100;
GO

-- Test include/exclude lists
PRINT '';
PRINT '-- Testing include/exclude database lists --';
EXEC collection.collect_query_store 
    @debug = 1,
    @use_database_list = 0,
    @include_databases = 'master,msdb',
    @exclude_databases = 'msdb',
    @min_cpu_time_ms = 100;
GO

-- Test disabling collection components
PRINT '';
PRINT '-- Testing component disabling --';
EXEC collection.collect_query_store 
    @debug = 1,
    @use_database_list = 0,
    @include_query_text = 0,
    @include_query_plans = 0,
    @include_runtime_stats = 1,
    @include_wait_stats = 0,
    @min_cpu_time_ms = 100;
GO

-- Clean up database configuration
PRINT '';
PRINT '-- Cleaning up --';
UPDATE system.database_collection_config 
SET active = 0 
WHERE database_name = 'master' AND collection_type = 'QUERY_STORE';
PRINT 'Disabled master database for Query Store collection';

-- Check tables created
PRINT '';
PRINT 'Tables created by the collection procedure:';
SELECT name, create_date 
FROM sys.tables 
WHERE schema_id = SCHEMA_ID('collection') 
AND name LIKE 'query_store%';

PRINT '-- Query Store collection test completed --';
GO