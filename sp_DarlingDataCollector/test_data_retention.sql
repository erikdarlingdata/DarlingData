/*
Test script for validating system.data_retention procedure
This script:
1. Creates test tables with date columns
2. Inserts sample data with different dates
3. Runs the data_retention procedure
4. Verifies that only data within the retention period remains
*/

-- Use the DarlingDataCollector database
USE DarlingData;
GO

-- Enable advanced output
SET NOCOUNT ON;
PRINT '-- Starting data retention test --';

-- Create test schema if it doesn't exist
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'collection')
BEGIN
    PRINT 'Creating collection schema...';
    EXEC('CREATE SCHEMA collection');
END
GO

-- Create test tables
PRINT 'Creating test tables...';

-- Test table 1 - with collection_time
IF OBJECT_ID('collection.test_retention_1') IS NOT NULL
BEGIN
    DROP TABLE collection.test_retention_1;
END

CREATE TABLE 
    collection.test_retention_1
(
    id INTEGER IDENTITY(1, 1) PRIMARY KEY,
    collection_time DATETIME2(7) NOT NULL,
    test_data NVARCHAR(100) NOT NULL
);
PRINT 'Created collection.test_retention_1';

-- Test table 2 - with date_collected
IF OBJECT_ID('collection.test_retention_2') IS NOT NULL
BEGIN
    DROP TABLE collection.test_retention_2;
END

CREATE TABLE 
    collection.test_retention_2
(
    id INTEGER IDENTITY(1, 1) PRIMARY KEY,
    date_collected DATETIME2(7) NOT NULL,
    test_data NVARCHAR(100) NOT NULL
);
PRINT 'Created collection.test_retention_2';

-- Test table 3 - with update_date 
IF OBJECT_ID('collection.test_retention_3') IS NOT NULL
BEGIN
    DROP TABLE collection.test_retention_3;
END

CREATE TABLE 
    collection.test_retention_3
(
    id INTEGER IDENTITY(1, 1) PRIMARY KEY,
    update_date DATETIME2(7) NOT NULL,
    test_data NVARCHAR(100) NOT NULL
);
PRINT 'Created collection.test_retention_3';

-- Test table 4 - with no date column (should be ignored)
IF OBJECT_ID('collection.test_retention_4') IS NOT NULL
BEGIN
    DROP TABLE collection.test_retention_4;
END

CREATE TABLE 
    collection.test_retention_4
(
    id INTEGER IDENTITY(1, 1) PRIMARY KEY,
    nondate_column NVARCHAR(100) NOT NULL,
    test_data NVARCHAR(100) NOT NULL
);
PRINT 'Created collection.test_retention_4';

GO

-- Insert test data with various dates
PRINT 'Inserting test data...';

-- Current time reference
DECLARE @now DATETIME2(7) = SYSDATETIME();

-- Table 1: Insert records - 60, 45, 30, 15, 1 days old, and current
INSERT collection.test_retention_1 (collection_time, test_data)
VALUES
    (DATEADD(DAY, -60, @now), 'Data from 60 days ago'),
    (DATEADD(DAY, -45, @now), 'Data from 45 days ago'),
    (DATEADD(DAY, -30, @now), 'Data from 30 days ago'),
    (DATEADD(DAY, -15, @now), 'Data from 15 days ago'),
    (DATEADD(DAY, -1, @now), 'Data from yesterday'),
    (@now, 'Current data');

-- Table 2: Insert records - 60, 45, 30, 15, 1 days old, and current
INSERT collection.test_retention_2 (date_collected, test_data)
VALUES
    (DATEADD(DAY, -60, @now), 'Data from 60 days ago'),
    (DATEADD(DAY, -45, @now), 'Data from 45 days ago'),
    (DATEADD(DAY, -30, @now), 'Data from 30 days ago'),
    (DATEADD(DAY, -15, @now), 'Data from 15 days ago'),
    (DATEADD(DAY, -1, @now), 'Data from yesterday'),
    (@now, 'Current data');
    
-- Table 3: Insert records - 60, 45, 30, 15, 1 days old, and current
INSERT collection.test_retention_3 (update_date, test_data)
VALUES
    (DATEADD(DAY, -60, @now), 'Data from 60 days ago'),
    (DATEADD(DAY, -45, @now), 'Data from 45 days ago'),
    (DATEADD(DAY, -30, @now), 'Data from 30 days ago'),
    (DATEADD(DAY, -15, @now), 'Data from 15 days ago'),
    (DATEADD(DAY, -1, @now), 'Data from yesterday'),
    (@now, 'Current data');
    
-- Table 4: Insert records (no dates)
INSERT collection.test_retention_4 (nondate_column, test_data)
VALUES
    ('No date 1', 'This should not be affected'),
    ('No date 2', 'This should not be affected');
    
PRINT 'Data inserted. Counts before retention:';
SELECT 'collection.test_retention_1' AS table_name, COUNT(*) AS row_count FROM collection.test_retention_1
UNION ALL
SELECT 'collection.test_retention_2' AS table_name, COUNT(*) AS row_count FROM collection.test_retention_2
UNION ALL
SELECT 'collection.test_retention_3' AS table_name, COUNT(*) AS row_count FROM collection.test_retention_3
UNION ALL
SELECT 'collection.test_retention_4' AS table_name, COUNT(*) AS row_count FROM collection.test_retention_4;

-- Run data retention with 20 day retention period - should keep records from 20 days ago to now
PRINT '';
PRINT '-- Running data retention with 20 day retention period --';
EXEC system.data_retention 
    @retention_days = 20, 
    @debug = 1;

-- Verify data after retention
PRINT '';
PRINT '-- Data after retention: Only data newer than 20 days should remain --';
SELECT 'collection.test_retention_1' AS table_name, id, collection_time, test_data 
FROM collection.test_retention_1
ORDER BY collection_time;

SELECT 'collection.test_retention_2' AS table_name, id, date_collected, test_data 
FROM collection.test_retention_2
ORDER BY date_collected;

SELECT 'collection.test_retention_3' AS table_name, id, update_date, test_data 
FROM collection.test_retention_3
ORDER BY update_date;

SELECT 'collection.test_retention_4' AS table_name, id, nondate_column, test_data 
FROM collection.test_retention_4;

-- Test excluding a table from retention
PRINT '';
PRINT '-- Testing table exclusion --';
PRINT 'Running data retention with table 2 excluded:';
EXEC system.data_retention 
    @retention_days = 10, 
    @exclude_tables = 'test_retention_2',
    @debug = 1;
    
-- Verify data after exclusion - table 2 should have all data from before
PRINT '';
PRINT '-- Data after exclusion test: Table 2 should still have all data after 20 day retention --';
SELECT 'collection.test_retention_1' AS table_name, COUNT(*) AS row_count FROM collection.test_retention_1
UNION ALL
SELECT 'collection.test_retention_2' AS table_name, COUNT(*) AS row_count FROM collection.test_retention_2
UNION ALL
SELECT 'collection.test_retention_3' AS table_name, COUNT(*) AS row_count FROM collection.test_retention_3
UNION ALL
SELECT 'collection.test_retention_4' AS table_name, COUNT(*) AS row_count FROM collection.test_retention_4;

-- Clean up test tables
PRINT '';
PRINT '-- Cleaning up test tables --';
DROP TABLE collection.test_retention_1;
DROP TABLE collection.test_retention_2;
DROP TABLE collection.test_retention_3;
DROP TABLE collection.test_retention_4;
PRINT 'Test tables removed.';

PRINT '-- Data retention test completed --';
GO