/*
Test script for validating system.manage_databases procedure
This script:
1. Creates the system schema if needed
2. Tests adding databases to different collection types
3. Tests listing database configuration
4. Tests removing databases from collection
*/

-- Use the DarlingDataCollector database
USE DarlingData;
GO

-- Enable advanced output
SET NOCOUNT ON;
PRINT '-- Starting database management test --';

-- Create system schema if it doesn't exist
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'system')
BEGIN
    PRINT 'Creating system schema...';
    EXEC('CREATE SCHEMA system');
END
GO

-- Clean up any existing config table from previous tests
IF OBJECT_ID('system.database_collection_config') IS NOT NULL
BEGIN
    PRINT 'Dropping existing database_collection_config table...';
    DROP TABLE system.database_collection_config;
END
GO

-- Help information
PRINT '-- Testing help information --';
EXEC system.manage_databases @help = 1;
GO

-- Validate parameter checks
PRINT '';
PRINT '-- Testing parameter validation --';
PRINT 'Testing missing action parameter (should fail):';
BEGIN TRY
    EXEC system.manage_databases;
    PRINT 'Test failed: Procedure should have raised an error for missing action';
END TRY
BEGIN CATCH
    PRINT 'Error caught as expected: ' + ERROR_MESSAGE();
END CATCH
GO

PRINT '';
PRINT 'Testing invalid action parameter (should fail):';
BEGIN TRY
    EXEC system.manage_databases @action = 'INVALID';
    PRINT 'Test failed: Procedure should have raised an error for invalid action';
END TRY
BEGIN CATCH
    PRINT 'Error caught as expected: ' + ERROR_MESSAGE();
END CATCH
GO

PRINT '';
PRINT 'Testing ADD without required parameters (should fail):';
BEGIN TRY
    EXEC system.manage_databases @action = 'ADD';
    PRINT 'Test failed: Procedure should have raised an error for missing params';
END TRY
BEGIN CATCH
    PRINT 'Error caught as expected: ' + ERROR_MESSAGE();
END CATCH
GO

PRINT '';
PRINT 'Testing invalid collection type (should fail):';
BEGIN TRY
    EXEC system.manage_databases 
        @action = 'ADD', 
        @database_name = 'master', 
        @collection_type = 'INVALID';
    PRINT 'Test failed: Procedure should have raised an error for invalid collection type';
END TRY
BEGIN CATCH
    PRINT 'Error caught as expected: ' + ERROR_MESSAGE();
END CATCH
GO

-- Test database validation
PRINT '';
PRINT '-- Testing database validation --';
PRINT 'Testing nonexistent database (should fail):';
BEGIN TRY
    EXEC system.manage_databases 
        @action = 'ADD', 
        @database_name = 'NonExistentDB', 
        @collection_type = 'INDEX',
        @debug = 1;
    PRINT 'Test failed: Procedure should have raised an error for nonexistent database';
END TRY
BEGIN CATCH
    PRINT 'Error caught as expected: ' + ERROR_MESSAGE();
END CATCH
GO

-- Test adding databases
PRINT '';
PRINT '-- Testing ADD action --';
PRINT 'Adding master database for INDEX collection:';
EXEC system.manage_databases 
    @action = 'ADD', 
    @database_name = 'master', 
    @collection_type = 'INDEX',
    @debug = 1;
GO

PRINT '';
PRINT 'Adding tempdb database for QUERY_STORE collection:';
EXEC system.manage_databases 
    @action = 'ADD', 
    @database_name = 'tempdb', 
    @collection_type = 'QUERY_STORE',
    @debug = 1;
GO

PRINT '';
PRINT 'Adding msdb database for ALL collection types:';
EXEC system.manage_databases 
    @action = 'ADD', 
    @database_name = 'msdb', 
    @collection_type = 'ALL',
    @debug = 1;
GO

-- List databases
PRINT '';
PRINT '-- Testing LIST action --';
PRINT 'Listing all configured databases:';
EXEC system.manage_databases 
    @action = 'LIST',
    @debug = 1;
GO

PRINT '';
PRINT 'Listing only INDEX collection databases:';
EXEC system.manage_databases 
    @action = 'LIST',
    @collection_type = 'INDEX',
    @debug = 1;
GO

PRINT '';
PRINT 'Listing only QUERY_STORE collection databases:';
EXEC system.manage_databases 
    @action = 'LIST',
    @collection_type = 'QUERY_STORE',
    @debug = 1;
GO

-- Test removing databases
PRINT '';
PRINT '-- Testing REMOVE action --';
PRINT 'Removing master database from INDEX collection:';
EXEC system.manage_databases 
    @action = 'REMOVE', 
    @database_name = 'master', 
    @collection_type = 'INDEX',
    @debug = 1;
GO

PRINT '';
PRINT 'Removing msdb database from ALL collections:';
EXEC system.manage_databases 
    @action = 'REMOVE', 
    @database_name = 'msdb', 
    @collection_type = 'ALL',
    @debug = 1;
GO

-- Verify removals
PRINT '';
PRINT '-- Verifying database removals --';
PRINT 'Listing all active database configurations:';
EXEC system.manage_databases 
    @action = 'LIST',
    @debug = 1;
GO

-- Clean up
PRINT '';
PRINT '-- Cleaning up --';
IF OBJECT_ID('system.database_collection_config') IS NOT NULL
BEGIN
    DROP TABLE system.database_collection_config;
    PRINT 'Dropped database_collection_config table';
END

PRINT '-- Database management test completed --';
GO