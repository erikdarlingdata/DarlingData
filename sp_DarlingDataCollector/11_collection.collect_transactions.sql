SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('collection.collect_transactions', 'P') IS NULL
BEGIN
    EXECUTE ('CREATE PROCEDURE collection.collect_transactions AS RETURN 0;');
END;
GO

/*
/**************************************************************
* 
* Transactions Collection Procedure for DarlingDataCollector
* 
* Copyright (C) Darling Data, LLC
* 
* Collects information about active transactions from
* sys.dm_tran_active_transactions
* sys.dm_tran_database_transactions
* sys.dm_tran_session_transactions
* 
**************************************************************/
*/

CREATE OR ALTER PROCEDURE
    collection.collect_transactions
(
    @debug BIT = 0, /*Print debugging information*/
    @min_age_seconds INTEGER = 0, /*Minimum transaction age in seconds to include*/
    @include_system_transactions BIT = 0, /*Include system transactions in collection*/
    @include_query_text BIT = 1 /*Include query text in collection*/
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
        Create the collection table if it doesn't exist
        */
        IF OBJECT_ID('collection.transactions') IS NULL
        BEGIN
            EXECUTE system.create_collector_table
                @table_name = 'transactions',
                @debug = @debug;
        END;
        
        /*
        Collect active transactions
        */
        INSERT
            collection.transactions
        (
            collection_time,
            transaction_id,
            name,
            transaction_begin_time,
            transaction_type,
            transaction_state,
            transaction_status,
            transaction_status2,
            dtc_state,
            is_user_transaction,
            is_local,
            session_id,
            login_name,
            host_name,
            program_name,
            database_id,
            database_name,
            is_snapshot,
            isolation_level,
            has_snapshot_capability,
            first_snapshot_sequence_num,
            max_version_chain_traversed,
            transaction_sequence_num,
            is_enlisted,
            is_bound,
            open_transaction_count,
            database_transaction_begin_time,
            database_transaction_log_record_count,
            database_transaction_replicate_record_count,
            database_transaction_log_bytes_used,
            database_transaction_log_bytes_reserved,
            database_transaction_log_bytes_used_system,
            database_transaction_log_bytes_reserved_system,
            active_transaction_duration_seconds,
            elapsed_time_seconds,
            transaction_sql_text
        )
        SELECT
            collection_time = SYSDATETIME(),
            at.transaction_id,
            at.name,
            at.transaction_begin_time,
            transaction_type = 
                CASE at.transaction_type
                    WHEN 1 THEN 'Read/Write'
                    WHEN 2 THEN 'Read-Only'
                    WHEN 3 THEN 'System'
                    WHEN 4 THEN 'Distributed'
                    ELSE 'Unknown'
                END,
            transaction_state = 
                CASE at.transaction_state
                    WHEN 0 THEN 'Initializing'
                    WHEN 1 THEN 'Initialized'
                    WHEN 2 THEN 'Active'
                    WHEN 3 THEN 'Ended'
                    WHEN 4 THEN 'Preparing'
                    WHEN 5 THEN 'Prepared'
                    WHEN 6 THEN 'Committed'
                    WHEN 7 THEN 'Rolling Back'
                    WHEN 8 THEN 'Rolled Back'
                    ELSE 'Unknown'
                END,
            at.transaction_status,
            at.transaction_status2,
            dtc_state = 
                CASE at.dtc_state
                    WHEN 1 THEN 'Active'
                    WHEN 2 THEN 'Prepared'
                    WHEN 3 THEN 'Committed'
                    WHEN 4 THEN 'Aborted'
                    WHEN 5 THEN 'Recovered'
                    ELSE 'Unknown'
                END,
            at.is_user_transaction,
            at.is_local,
            s.session_id,
            es.login_name,
            es.host_name,
            es.program_name,
            dt.database_id,
            database_name = DB_NAME(dt.database_id),
            dt.is_snapshot,
            isolation_level = 
                CASE dt.database_transaction_isolation_level
                    WHEN 0 THEN 'Unspecified'
                    WHEN 1 THEN 'ReadUncommitted'
                    WHEN 2 THEN 'ReadCommitted'
                    WHEN 3 THEN 'Repeatable'
                    WHEN 4 THEN 'Serializable'
                    WHEN 5 THEN 'Snapshot'
                    ELSE 'Unknown'
                END,
            dt.database_transaction_has_snapshot_capability,
            dt.database_transaction_first_snapshot_sequence_num,
            dt.database_transaction_max_version_chain_traversed,
            dt.database_transaction_sequence_num,
            dt.is_enlisted,
            dt.is_bound,
            dt.database_transaction_count,
            dt.database_transaction_begin_time,
            dt.database_transaction_log_record_count,
            dt.database_transaction_replicate_record_count,
            dt.database_transaction_log_bytes_used,
            dt.database_transaction_log_bytes_reserved,
            dt.database_transaction_log_bytes_used_system,
            dt.database_transaction_log_bytes_reserved_system,
            active_transaction_duration_seconds = 
                DATEDIFF(SECOND, at.transaction_begin_time, SYSDATETIME()),
            elapsed_time_seconds = 
                DATEDIFF(SECOND, dt.database_transaction_begin_time, SYSDATETIME()),
            transaction_sql_text = 
                CASE WHEN @include_query_text = 1 
                    THEN 
                        CASE
                            WHEN es.session_id IS NOT NULL THEN
                                (SELECT TOP 1 text FROM sys.dm_exec_sql_text(er.sql_handle))
                            ELSE NULL
                        END
                    ELSE NULL 
                END
        FROM sys.dm_tran_active_transactions AS at
        LEFT JOIN sys.dm_tran_session_transactions AS s
            ON at.transaction_id = s.transaction_id
        LEFT JOIN sys.dm_tran_database_transactions AS dt
            ON at.transaction_id = dt.transaction_id
        LEFT JOIN sys.dm_exec_sessions AS es
            ON s.session_id = es.session_id
        LEFT JOIN sys.dm_exec_requests AS er
            ON s.session_id = er.session_id
        WHERE (at.is_user_transaction = 1 OR @include_system_transactions = 1)
        AND DATEDIFF(SECOND, at.transaction_begin_time, SYSDATETIME()) >= @min_age_seconds;
        
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
            'collection.collect_transactions',
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
                N'Transactions Collected' AS collection_type,
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
            'collection.collect_transactions',
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