SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('collection.collect_process_memory', 'P') IS NULL
BEGIN
    EXECUTE ('CREATE PROCEDURE collection.collect_process_memory AS RETURN 0;');
END;
GO

/*
/**************************************************************
* 
* Process Memory Collection Procedure for DarlingDataCollector
* 
* Copyright (C) Darling Data, LLC
* 
* Collects memory usage information from sys.dm_os_process_memory
* and sys.dm_os_sys_memory
* 
**************************************************************/
*/

CREATE OR ALTER PROCEDURE
    collection.collect_process_memory
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
        Create process_memory table if it doesn't exist
        */
        IF OBJECT_ID('collection.process_memory') IS NULL
        BEGIN
            CREATE TABLE
                collection.process_memory
            (
                collection_id BIGINT IDENTITY(1,1) NOT NULL,
                collection_time DATETIME2(7) NOT NULL,
                physical_memory_in_use_kb BIGINT NULL,
                large_page_allocations_kb BIGINT NULL,
                locked_page_allocations_kb BIGINT NULL,
                total_virtual_address_space_kb BIGINT NULL,
                virtual_address_space_reserved_kb BIGINT NULL,
                virtual_address_space_committed_kb BIGINT NULL,
                virtual_address_space_available_kb BIGINT NULL,
                page_fault_count BIGINT NULL,
                memory_utilization_percentage INTEGER NULL,
                process_physical_memory_low BIT NULL,
                process_virtual_memory_low BIT NULL,
                system_physical_memory_high BIT NULL,
                system_virtual_memory_low BIT NULL,
                system_total_physical_memory_kb BIGINT NULL,
                system_available_physical_memory_kb BIGINT NULL,
                system_total_page_file_kb BIGINT NULL,
                system_available_page_file_kb BIGINT NULL,
                system_cache_kb BIGINT NULL,
                system_kernel_paged_pool_kb BIGINT NULL,
                system_kernel_nonpaged_pool_kb BIGINT NULL,
                CONSTRAINT pk_process_memory PRIMARY KEY CLUSTERED (collection_id)
            );
            
            IF @debug = 1
            BEGIN
                RAISERROR(N'Created collection.process_memory table', 0, 1) WITH NOWAIT;
            END;
        END;
        
        /*
        Collect process memory information
        */
        INSERT
            collection.process_memory
        (
            collection_time,
            physical_memory_in_use_kb,
            large_page_allocations_kb,
            locked_page_allocations_kb,
            total_virtual_address_space_kb,
            virtual_address_space_reserved_kb,
            virtual_address_space_committed_kb,
            virtual_address_space_available_kb,
            page_fault_count,
            memory_utilization_percentage,
            process_physical_memory_low,
            process_virtual_memory_low,
            system_physical_memory_high,
            system_virtual_memory_low,
            system_total_physical_memory_kb,
            system_available_physical_memory_kb,
            system_total_page_file_kb,
            system_available_page_file_kb,
            system_cache_kb,
            system_kernel_paged_pool_kb,
            system_kernel_nonpaged_pool_kb
        )
        SELECT
            collection_time = SYSDATETIME(),
            pm.physical_memory_in_use_kb,
            pm.large_page_allocations_kb,
            pm.locked_page_allocations_kb,
            pm.total_virtual_address_space_kb,
            pm.virtual_address_space_reserved_kb,
            pm.virtual_address_space_committed_kb,
            pm.virtual_address_space_available_kb,
            pm.page_fault_count,
            pm.memory_utilization_percentage,
            pm.process_physical_memory_low,
            pm.process_virtual_memory_low,
            pm.system_physical_memory_high,
            pm.system_virtual_memory_low,
            sm.total_physical_memory_kb,
            sm.available_physical_memory_kb,
            sm.total_page_file_kb,
            sm.available_page_file_kb,
            sm.system_cache_kb,
            sm.kernel_paged_pool_kb,
            sm.kernel_nonpaged_pool_kb
        FROM sys.dm_os_process_memory AS pm
        CROSS JOIN sys.dm_os_sys_memory AS sm;
        
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
            'collection.collect_process_memory',
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
                N'Process Memory Collected' AS collection_type,
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
            'collection.collect_process_memory',
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