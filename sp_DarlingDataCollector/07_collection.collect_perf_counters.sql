SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('collection.collect_perf_counters', 'P') IS NULL
BEGIN
    EXECUTE ('CREATE PROCEDURE collection.collect_perf_counters AS RETURN 0;');
END;
GO

/*
/**************************************************************
* 
* Performance Counters Collection Procedure for DarlingDataCollector
* 
* Copyright (C) Darling Data, LLC
* 
* Collects key performance counters from sys.dm_os_performance_counters
* 
**************************************************************/
*/

CREATE OR ALTER PROCEDURE
    collection.collect_perf_counters
(
    @debug BIT = 0, /*Print debugging information*/
    @include_all_counters BIT = 0 /*Include all counters, not just important ones*/
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
    
    BEGIN TRY
        /*
        Create perf_counters table if it doesn't exist
        */
        IF OBJECT_ID('collection.perf_counters') IS NULL
        BEGIN
            EXECUTE system.create_collector_table
                @table_name = 'perf_counters',
                @debug = @debug;
        END;
        
        /*
        Create key counters to collect if not including all counters
        */
        IF @include_all_counters = 0
        BEGIN
            DECLARE
                @key_counters TABLE
                (
                    object_name NVARCHAR(128) NOT NULL,
                    counter_name NVARCHAR(128) NOT NULL
                );
                
            -- Insert the key performance counters we want to collect
            INSERT @key_counters
            (
                object_name,
                counter_name
            )
            VALUES
                ('SQLServer:Buffer Manager', 'Page life expectancy'),
                ('SQLServer:Buffer Manager', 'Buffer cache hit ratio'),
                ('SQLServer:Buffer Manager', 'Page lookups/sec'),
                ('SQLServer:Buffer Manager', 'Page reads/sec'),
                ('SQLServer:Buffer Manager', 'Page writes/sec'),
                ('SQLServer:Memory Manager', 'Memory Grants Pending'),
                ('SQLServer:Memory Manager', 'Memory Grants Outstanding'),
                ('SQLServer:Memory Manager', 'Target Server Memory (KB)'),
                ('SQLServer:Memory Manager', 'Total Server Memory (KB)'),
                ('SQLServer:SQL Statistics', 'Batch Requests/sec'),
                ('SQLServer:SQL Statistics', 'Forced Parameterizations/sec'),
                ('SQLServer:SQL Statistics', 'SQL Compilations/sec'),
                ('SQLServer:SQL Statistics', 'SQL Re-Compilations/sec'),
                ('SQLServer:General Statistics', 'Processes blocked'),
                ('SQLServer:General Statistics', 'User Connections'),
                ('SQLServer:Locks', 'Lock Waits/sec'),
                ('SQLServer:Locks', 'Number of Deadlocks/sec'),
                ('SQLServer:Access Methods', 'Full Scans/sec'),
                ('SQLServer:Access Methods', 'Index Searches/sec'),
                ('SQLServer:Access Methods', 'Page Splits/sec'),
                ('SQLServer:Access Methods', 'Workfiles Created/sec'),
                ('SQLServer:Access Methods', 'Worktables Created/sec'),
                ('SQLServer:Transactions', 'Transactions'),
                ('SQLServer:Transactions', 'Write Transactions/sec'),
                ('SQLServer:Databases', 'Log Bytes Flushed/sec'),
                ('SQLServer:Databases', 'Log Flush Wait Time'),
                ('SQLServer:Databases', 'Log Flush Waits/sec'),
                ('SQLServer:Databases', 'Log Growths'),
                ('SQLServer:Databases', 'Percent Log Used'),
                ('SQLServer:Databases', 'Transactions/sec'),
                ('SQLServer:Plan Cache', 'Cache Hit Ratio'),
                ('SQLServer:Plan Cache', 'Cache Object Counts'),
                ('SQLServer:Resource Pool Stats', 'CPU usage %'),
                ('SQLServer:Resource Pool Stats', 'CPU usage % base'),
                ('SQLServer:Resource Pool Stats', 'Memory usage %'),
                ('SQLServer:Resource Pool Stats', 'Memory usage % base');
        END;
        
        /*
        Collect performance counter information
        */
        IF @include_all_counters = 1
        BEGIN
            INSERT
                collection.perf_counters
            (
                collection_time,
                object_name,
                counter_name,
                instance_name,
                cntr_value,
                cntr_type
            )
            SELECT
                collection_time = SYSDATETIME(),
                pc.object_name,
                pc.counter_name,
                pc.instance_name,
                pc.cntr_value,
                pc.cntr_type
            FROM sys.dm_os_performance_counters AS pc;
        END
        ELSE
        BEGIN
            INSERT
                collection.perf_counters
            (
                collection_time,
                object_name,
                counter_name,
                instance_name,
                cntr_value,
                cntr_type
            )
            SELECT
                collection_time = SYSDATETIME(),
                pc.object_name,
                pc.counter_name,
                pc.instance_name,
                pc.cntr_value,
                pc.cntr_type
            FROM sys.dm_os_performance_counters AS pc
            JOIN @key_counters AS kc
                ON pc.object_name LIKE kc.object_name
                AND pc.counter_name = kc.counter_name;
        END;
        
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
            'collection.collect_perf_counters',
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
                N'Performance Counters Collected' AS collection_type,
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
            'collection.collect_perf_counters',
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