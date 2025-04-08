SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('collection.collect_buffer_pool', 'P') IS NULL
BEGIN
    EXECUTE ('CREATE PROCEDURE collection.collect_buffer_pool AS RETURN 0;');
END;
GO

/*
/**************************************************************
* 
* Buffer Pool Collection Procedure for DarlingDataCollector
* 
* Copyright (C) Darling Data, LLC
* 
* Collects buffer pool page usage from sys.dm_os_buffer_descriptors
* 
**************************************************************/
*/

CREATE OR ALTER PROCEDURE
    collection.collect_buffer_pool
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
        Collect buffer pool information
        */
        INSERT
            collection.buffer_pool
        (
            collection_time,
            database_id,
            database_name,
            file_id,
            file_type,
            page_count,
            cached_size_mb
        )
        SELECT
            collection_time = SYSDATETIME(),
            bd.database_id,
            database_name = DB_NAME(bd.database_id),
            bd.file_id,
            file_type = 
                CASE 
                    WHEN mf.type = 0 THEN 'DATA'
                    WHEN mf.type = 1 THEN 'LOG'
                    ELSE 'OTHER'
                END,
            page_count = COUNT(bd.page_id),
            cached_size_mb = COUNT(bd.page_id) * 8.0 / 1024
        FROM sys.dm_os_buffer_descriptors AS bd
        LEFT JOIN sys.master_files AS mf
          ON bd.database_id = mf.database_id
          AND bd.file_id = mf.file_id
        GROUP BY
            bd.database_id,
            bd.file_id,
            CASE 
                WHEN mf.type = 0 THEN 'DATA'
                WHEN mf.type = 1 THEN 'LOG'
                ELSE 'OTHER'
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
            'collection.collect_buffer_pool',
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
                N'Buffer Pool Collected' AS collection_type,
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
            'collection.collect_buffer_pool',
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