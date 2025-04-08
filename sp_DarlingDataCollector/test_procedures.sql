/*
Test script for validating DarlingDataCollector procedures
*/

-- Set database context - CHANGE THIS TO YOUR DATABASE NAME
USE DarlingData;
GO

PRINT 'Testing system.data_retention procedure';
EXECUTE system.data_retention 
    @retention_days = 30, 
    @debug = 1;
GO

PRINT 'Testing system.manage_databases procedure';
EXECUTE system.manage_databases 
    @action = 'LIST',
    @debug = 1;
GO

PRINT 'Testing collection.collect_query_store procedure';
EXECUTE collection.collect_query_store 
    @debug = 1,
    @min_cpu_time_ms = 1000,
    @min_logical_io_reads = 1000;
GO

PRINT 'Tests completed successfully';
GO