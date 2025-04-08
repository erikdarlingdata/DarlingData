SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('collection.collect_memory_clerks', 'P') IS NULL
BEGIN
    EXECUTE ('CREATE PROCEDURE collection.collect_memory_clerks AS RETURN 0;');
END;
GO

/*
/**************************************************************
* 
* Memory Clerks Collection Procedure for DarlingDataCollector
* 
* Copyright (C) Darling Data, LLC
* 
* Collects memory usage information from sys.dm_os_memory_clerks
* 
**************************************************************/
*/

CREATE OR ALTER PROCEDURE
    collection.collect_memory_clerks
(
    @debug BIT = 0 /*Print debugging information*/
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
        Collect memory clerks information
        */
        INSERT
            collection.memory_clerks
        (
            collection_time,
            clerk_name,
            memory_node_id,
            pages_kb,
            virtual_memory_reserved_kb,
            virtual_memory_committed_kb,
            awe_allocated_kb,
            shared_memory_reserved_kb,
            shared_memory_committed_kb
        )
        SELECT
            collection_time = SYSDATETIME(),
            clerk_name = type,
            memory_node_id,
            pages_kb,
            virtual_memory_reserved_kb,
            virtual_memory_committed_kb,
            awe_allocated_kb,
            shared_memory_reserved_kb,
            shared_memory_committed_kb
        FROM sys.dm_os_memory_clerks
        WHERE pages_kb > 0
        OR virtual_memory_committed_kb > 0;
        
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
            'collection.collect_memory_clerks',
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
                N'Memory Clerks Collected' AS collection_type,
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
            'collection.collect_memory_clerks',
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