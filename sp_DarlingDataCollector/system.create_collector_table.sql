SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('system.create_collector_table', 'P') IS NULL
BEGIN
    EXECUTE ('CREATE PROCEDURE system.create_collector_table AS RETURN 0;');
END;
GO

/*
/**************************************************************
* 
* Table Creator Procedure for DarlingDataCollector
* 
* Copyright (C) Darling Data, LLC
* 
* Creates collection tables on demand if they don't exist
* 
**************************************************************/
*/

CREATE OR ALTER PROCEDURE
    system.create_collector_table
(
    @table_name NVARCHAR(128), /*Name of the table to create without schema prefix*/
    @debug BIT = 0 /*Print debugging information*/
)
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
    
    DECLARE
        @sql NVARCHAR(MAX) = N'',
        @full_table_name NVARCHAR(256),
        @error_number INTEGER,
        @error_message NVARCHAR(4000);
    
    BEGIN TRY
        /*
        Set full table name with schema
        */
        SET @full_table_name = N'collection.' + @table_name;
        
        /*
        Check if table already exists
        */
        IF OBJECT_ID(@full_table_name) IS NOT NULL
        BEGIN
            IF @debug = 1
            BEGIN
                RAISERROR(N'Table %s already exists', 0, 1, @full_table_name) WITH NOWAIT;
            END;
            RETURN;
        END;
        
        /*
        Create the requested table based on name
        */
        IF @table_name = N'wait_stats'
        BEGIN
            SET @sql = N'
            CREATE TABLE
                collection.wait_stats
            (
                collection_id BIGINT IDENTITY(1,1) NOT NULL,
                collection_time DATETIME2(7) NOT NULL,
                server_uptime_seconds BIGINT NULL,
                wait_type NVARCHAR(128) NOT NULL,
                waiting_tasks_count BIGINT NOT NULL,
                wait_time_ms BIGINT NOT NULL,
                max_wait_time_ms BIGINT NOT NULL,
                signal_wait_time_ms BIGINT NOT NULL,
                waiting_tasks_count_delta BIGINT NULL,
                wait_time_ms_delta BIGINT NULL,
                max_wait_time_ms_delta BIGINT NULL,
                signal_wait_time_ms_delta BIGINT NULL,
                sample_seconds INTEGER NULL,
                CONSTRAINT PK_wait_stats PRIMARY KEY CLUSTERED (collection_id)
            );
            
            CREATE NONCLUSTERED INDEX IX_wait_stats_collection_time
                ON collection.wait_stats (collection_time);
                
            CREATE NONCLUSTERED INDEX IX_wait_stats_wait_type
                ON collection.wait_stats (wait_type);';
        END
        ELSE IF @table_name = N'memory_clerks'
        BEGIN
            SET @sql = N'
            CREATE TABLE
                collection.memory_clerks
            (
                collection_id BIGINT IDENTITY(1,1) NOT NULL,
                collection_time DATETIME2(7) NOT NULL,
                clerk_name NVARCHAR(128) NOT NULL,
                memory_node_id INTEGER NOT NULL,
                pages_kb BIGINT NOT NULL,
                virtual_memory_reserved_kb BIGINT NOT NULL,
                virtual_memory_committed_kb BIGINT NOT NULL,
                awe_allocated_kb BIGINT NOT NULL,
                shared_memory_reserved_kb BIGINT NOT NULL,
                shared_memory_committed_kb BIGINT NOT NULL,
                pages_mb AS (pages_kb / 1024.0),
                virtual_memory_reserved_mb AS (virtual_memory_reserved_kb / 1024.0),
                virtual_memory_committed_mb AS (virtual_memory_committed_kb / 1024.0),
                awe_allocated_mb AS (awe_allocated_kb / 1024.0),
                shared_memory_reserved_mb AS (shared_memory_reserved_kb / 1024.0),
                shared_memory_committed_mb AS (shared_memory_committed_kb / 1024.0),
                CONSTRAINT PK_memory_clerks PRIMARY KEY CLUSTERED (collection_id)
            );
            
            CREATE NONCLUSTERED INDEX IX_memory_clerks_collection_time
                ON collection.memory_clerks (collection_time);
                
            CREATE NONCLUSTERED INDEX IX_memory_clerks_clerk_name
                ON collection.memory_clerks (clerk_name);';
        END
        ELSE IF @table_name = N'buffer_pool'
        BEGIN
            SET @sql = N'
            CREATE TABLE
                collection.buffer_pool
            (
                collection_id BIGINT IDENTITY(1,1) NOT NULL,
                collection_time DATETIME2(7) NOT NULL,
                database_id INTEGER NOT NULL,
                database_name NVARCHAR(128) NOT NULL,
                buffer_count BIGINT NOT NULL,
                buffer_count_percent DECIMAL(5,2) NOT NULL,
                buffer_mb DECIMAL(18,2) NOT NULL,
                buffer_percent DECIMAL(5,2) NOT NULL,
                CONSTRAINT PK_buffer_pool PRIMARY KEY CLUSTERED (collection_id)
            );
            
            CREATE NONCLUSTERED INDEX IX_buffer_pool_collection_time
                ON collection.buffer_pool (collection_time);
                
            CREATE NONCLUSTERED INDEX IX_buffer_pool_database_id
                ON collection.buffer_pool (database_id);';
        END
        ELSE IF @table_name = N'memory_grants'
        BEGIN
            SET @sql = N'
            CREATE TABLE
                collection.memory_grants
            (
                collection_id BIGINT IDENTITY(1,1) NOT NULL,
                collection_time DATETIME2(7) NOT NULL,
                session_id INTEGER NOT NULL,
                request_id INTEGER NOT NULL,
                scheduler_id INTEGER NULL,
                dop INTEGER NOT NULL,
                request_time DATETIME NOT NULL,
                grant_time DATETIME NULL,
                requested_memory_kb BIGINT NOT NULL,
                granted_memory_kb BIGINT NOT NULL,
                required_memory_kb BIGINT NOT NULL,
                used_memory_kb BIGINT NOT NULL,
                max_used_memory_kb BIGINT NOT NULL,
                ideal_memory_kb BIGINT NULL,
                query_cost DECIMAL(18,4) NULL,
                timeout_sec INTEGER NULL,
                wait_time_ms INTEGER NOT NULL,
                wait_resource_type NVARCHAR(256) NULL,
                plan_handle VARBINARY(64) NULL,
                statement_start_offset INTEGER NULL,
                statement_end_offset INTEGER NULL,
                sql_handle VARBINARY(64) NULL,
                query_hash BINARY(8) NULL,
                query_plan_hash BINARY(8) NULL,
                sql_text NVARCHAR(MAX) NULL,
                requested_memory_mb AS (requested_memory_kb / 1024.0),
                granted_memory_mb AS (granted_memory_kb / 1024.0),
                required_memory_mb AS (required_memory_kb / 1024.0),
                used_memory_mb AS (used_memory_kb / 1024.0),
                max_used_memory_mb AS (max_used_memory_kb / 1024.0),
                ideal_memory_mb AS (ideal_memory_kb / 1024.0),
                CONSTRAINT PK_memory_grants PRIMARY KEY CLUSTERED (collection_id)
            );
            
            CREATE NONCLUSTERED INDEX IX_memory_grants_collection_time
                ON collection.memory_grants (collection_time);
                
            CREATE NONCLUSTERED INDEX IX_memory_grants_session_id
                ON collection.memory_grants (session_id, request_id);';
        END
        ELSE IF @table_name = N'process_memory'
        BEGIN
            SET @sql = N'
            CREATE TABLE
                collection.process_memory
            (
                collection_id BIGINT IDENTITY(1,1) NOT NULL,
                collection_time DATETIME2(7) NOT NULL,
                physical_memory_kb BIGINT NOT NULL,
                virtual_memory_kb BIGINT NOT NULL,
                available_physical_kb BIGINT NOT NULL,
                available_virtual_kb BIGINT NOT NULL,
                virtual_address_space_committed_kb BIGINT NOT NULL,
                locked_page_allocations_kb BIGINT NOT NULL,
                memory_utilization_percentage INTEGER NOT NULL,
                large_page_allocations_kb BIGINT NOT NULL,
                total_vm_reserved_kb BIGINT NOT NULL,
                total_vm_committed_kb BIGINT NOT NULL,
                total_awe_allocated_kb BIGINT NOT NULL,
                physical_memory_mb AS (physical_memory_kb / 1024.0),
                virtual_memory_mb AS (virtual_memory_kb / 1024.0),
                available_physical_mb AS (available_physical_kb / 1024.0),
                available_virtual_mb AS (available_virtual_kb / 1024.0),
                virtual_address_space_committed_mb AS (virtual_address_space_committed_kb / 1024.0),
                locked_page_allocations_mb AS (locked_page_allocations_kb / 1024.0),
                large_page_allocations_mb AS (large_page_allocations_kb / 1024.0),
                total_vm_reserved_mb AS (total_vm_reserved_kb / 1024.0),
                total_vm_committed_mb AS (total_vm_committed_kb / 1024.0),
                total_awe_allocated_mb AS (total_awe_allocated_kb / 1024.0),
                CONSTRAINT PK_process_memory PRIMARY KEY CLUSTERED (collection_id)
            );
            
            CREATE NONCLUSTERED INDEX IX_process_memory_collection_time
                ON collection.process_memory (collection_time);';
        END
        ELSE IF @table_name = N'schedulers'
        BEGIN
            SET @sql = N'
            CREATE TABLE
                collection.schedulers
            (
                collection_id BIGINT IDENTITY(1,1) NOT NULL,
                collection_time DATETIME2(7) NOT NULL,
                scheduler_id INTEGER NOT NULL,
                cpu_id INTEGER NOT NULL,
                status NVARCHAR(60) NOT NULL,
                is_online BIT NOT NULL,
                is_idle BIT NOT NULL,
                preemptive_switches_count BIGINT NOT NULL,
                context_switches_count BIGINT NOT NULL,
                yield_count BIGINT NOT NULL,
                current_tasks_count INTEGER NOT NULL,
                runnable_tasks_count INTEGER NOT NULL,
                active_workers_count INTEGER NOT NULL,
                work_queue_count INTEGER NOT NULL,
                pending_disk_io_count INTEGER NOT NULL,
                load_factor INTEGER NOT NULL,
                cpu_usage DECIMAL(5,2) NULL,
                cpu_usage_delta DECIMAL(5,2) NULL,
                total_cpu_usage_ms BIGINT NULL,
                total_cpu_usage_ms_delta BIGINT NULL,
                CONSTRAINT PK_schedulers PRIMARY KEY CLUSTERED (collection_id)
            );
            
            CREATE NONCLUSTERED INDEX IX_schedulers_collection_time
                ON collection.schedulers (collection_time);
                
            CREATE NONCLUSTERED INDEX IX_schedulers_scheduler_id
                ON collection.schedulers (scheduler_id);';
        END
        ELSE IF @table_name = N'perf_counters'
        BEGIN
            SET @sql = N'
            CREATE TABLE
                collection.perf_counters
            (
                collection_id BIGINT IDENTITY(1,1) NOT NULL,
                collection_time DATETIME2(7) NOT NULL,
                object_name NVARCHAR(128) NOT NULL,
                counter_name NVARCHAR(128) NOT NULL,
                instance_name NVARCHAR(128) NULL,
                cntr_value BIGINT NOT NULL,
                cntr_value_prev BIGINT NULL,
                cntr_value_delta BIGINT NULL,
                cntr_value_per_second DECIMAL(18,2) NULL,
                sample_seconds INTEGER NULL,
                CONSTRAINT PK_perf_counters PRIMARY KEY CLUSTERED (collection_id)
            );
            
            CREATE NONCLUSTERED INDEX IX_perf_counters_collection_time
                ON collection.perf_counters (collection_time);
                
            CREATE NONCLUSTERED INDEX IX_perf_counters_object_counter
                ON collection.perf_counters (object_name, counter_name);';
        END
        ELSE IF @table_name = N'file_space'
        BEGIN
            SET @sql = N'
            CREATE TABLE
                collection.file_space
            (
                collection_id BIGINT IDENTITY(1,1) NOT NULL,
                collection_time DATETIME2(7) NOT NULL,
                database_id INTEGER NOT NULL,
                database_name NVARCHAR(128) NOT NULL,
                file_id INTEGER NOT NULL,
                file_name NVARCHAR(128) NOT NULL,
                file_path NVARCHAR(260) NOT NULL,
                type_desc NVARCHAR(60) NOT NULL,
                size_mb DECIMAL(18,2) NOT NULL,
                space_used_mb DECIMAL(18,2) NOT NULL,
                free_space_mb DECIMAL(18,2) NOT NULL,
                free_space_percent DECIMAL(5,2) NOT NULL,
                max_size_mb DECIMAL(18,2) NULL,
                growth DECIMAL(18,2) NOT NULL,
                is_percent_growth BIT NOT NULL,
                is_read_only BIT NOT NULL,
                CONSTRAINT PK_file_space PRIMARY KEY CLUSTERED (collection_id)
            );
            
            CREATE NONCLUSTERED INDEX IX_file_space_collection_time
                ON collection.file_space (collection_time);
                
            CREATE NONCLUSTERED INDEX IX_file_space_database_id
                ON collection.file_space (database_id, file_id);';
        END
        ELSE IF @table_name = N'procedure_stats'
        BEGIN
            SET @sql = N'
            CREATE TABLE
                collection.procedure_stats
            (
                collection_id BIGINT IDENTITY(1,1) NOT NULL,
                collection_time DATETIME2(7) NOT NULL,
                database_id INTEGER NOT NULL,
                database_name NVARCHAR(128) NOT NULL,
                object_id INTEGER NOT NULL,
                object_name NVARCHAR(386) NOT NULL,
                type NVARCHAR(60) NOT NULL,
                cached_time DATETIME NOT NULL,
                last_execution_time DATETIME NULL,
                execution_count BIGINT NOT NULL,
                execution_count_delta BIGINT NULL,
                total_worker_time_ms BIGINT NOT NULL,
                total_worker_time_ms_delta BIGINT NULL,
                avg_worker_time_ms DECIMAL(18,2) NOT NULL,
                last_worker_time_ms BIGINT NOT NULL,
                min_worker_time_ms BIGINT NOT NULL,
                max_worker_time_ms BIGINT NOT NULL,
                total_physical_reads BIGINT NOT NULL,
                total_physical_reads_delta BIGINT NULL,
                avg_physical_reads DECIMAL(18,2) NOT NULL,
                last_physical_reads BIGINT NOT NULL,
                min_physical_reads BIGINT NOT NULL,
                max_physical_reads BIGINT NOT NULL,
                total_logical_writes BIGINT NOT NULL,
                total_logical_writes_delta BIGINT NULL,
                avg_logical_writes DECIMAL(18,2) NOT NULL,
                last_logical_writes BIGINT NOT NULL,
                min_logical_writes BIGINT NOT NULL,
                max_logical_writes BIGINT NOT NULL,
                total_logical_reads BIGINT NOT NULL,
                total_logical_reads_delta BIGINT NULL,
                avg_logical_reads DECIMAL(18,2) NOT NULL,
                last_logical_reads BIGINT NOT NULL,
                min_logical_reads BIGINT NOT NULL,
                max_logical_reads BIGINT NOT NULL,
                total_elapsed_time_ms BIGINT NOT NULL,
                total_elapsed_time_ms_delta BIGINT NULL,
                avg_elapsed_time_ms DECIMAL(18,2) NOT NULL,
                last_elapsed_time_ms BIGINT NOT NULL,
                min_elapsed_time_ms BIGINT NOT NULL,
                max_elapsed_time_ms BIGINT NOT NULL,
                plan_handle VARBINARY(64) NULL,
                sql_handle VARBINARY(64) NULL,
                CONSTRAINT PK_procedure_stats PRIMARY KEY CLUSTERED (collection_id)
            );
            
            CREATE NONCLUSTERED INDEX IX_procedure_stats_collection_time
                ON collection.procedure_stats (collection_time);
                
            CREATE NONCLUSTERED INDEX IX_procedure_stats_database_object
                ON collection.procedure_stats (database_id, object_id);
                
            CREATE NONCLUSTERED INDEX IX_procedure_stats_execution_count
                ON collection.procedure_stats (execution_count DESC);';
        END
        ELSE IF @table_name = N'missing_indexes'
        BEGIN
            SET @sql = N'
            CREATE TABLE
                collection.missing_indexes
            (
                collection_id BIGINT IDENTITY(1,1) NOT NULL,
                collection_time DATETIME2(7) NOT NULL,
                database_id INTEGER NOT NULL,
                database_name NVARCHAR(128) NOT NULL,
                schema_name NVARCHAR(128) NOT NULL,
                table_name NVARCHAR(128) NOT NULL,
                equality_columns NVARCHAR(4000) NULL,
                inequality_columns NVARCHAR(4000) NULL,
                included_columns NVARCHAR(4000) NULL,
                unique_compiles BIGINT NOT NULL,
                user_seeks BIGINT NOT NULL,
                user_scans BIGINT NOT NULL,
                avg_total_user_cost DECIMAL(18,2) NOT NULL,
                avg_user_impact DECIMAL(5,2) NOT NULL,
                last_user_seek DATETIME NOT NULL,
                last_user_scan DATETIME NULL,
                index_advantage DECIMAL(18,2) NOT NULL,
                create_index_statement NVARCHAR(4000) NOT NULL,
                CONSTRAINT PK_missing_indexes PRIMARY KEY CLUSTERED (collection_id)
            );
            
            CREATE NONCLUSTERED INDEX IX_missing_indexes_collection_time
                ON collection.missing_indexes (collection_time);
                
            CREATE NONCLUSTERED INDEX IX_missing_indexes_database_id
                ON collection.missing_indexes (database_id);
                
            CREATE NONCLUSTERED INDEX IX_missing_indexes_advantage
                ON collection.missing_indexes (index_advantage DESC);';
        END
        ELSE IF @table_name = N'transactions'
        BEGIN
            SET @sql = N'
            CREATE TABLE
                collection.transactions
            (
                collection_id BIGINT IDENTITY(1,1) NOT NULL,
                collection_time DATETIME2(7) NOT NULL,
                session_id INTEGER NOT NULL,
                transaction_id BIGINT NOT NULL,
                database_id INTEGER NOT NULL,
                database_name NVARCHAR(128) NOT NULL,
                transaction_begin_time DATETIME NOT NULL,
                transaction_duration_seconds INTEGER NOT NULL,
                transaction_type NVARCHAR(60) NOT NULL,
                transaction_state NVARCHAR(60) NOT NULL,
                dtc_state NVARCHAR(60) NULL,
                transaction_status BIGINT NOT NULL,
                transaction_status2 BIGINT NOT NULL,
                is_local BIT NOT NULL,
                is_user_transaction BIT NOT NULL,
                is_distributed BIT NOT NULL,
                is_bound BIT NOT NULL,
                open_transaction_count INTEGER NOT NULL,
                login_name NVARCHAR(128) NOT NULL,
                host_name NVARCHAR(128) NULL,
                program_name NVARCHAR(128) NULL,
                client_net_address NVARCHAR(48) NULL,
                client_version NVARCHAR(20) NULL,
                log_reuse_wait_desc NVARCHAR(60) NULL,
                log_used_pct DECIMAL(5,2) NULL,
                log_used_gb DECIMAL(18,2) NULL,
                log_size_gb DECIMAL(18,2) NULL,
                CONSTRAINT PK_transactions PRIMARY KEY CLUSTERED (collection_id)
            );
            
            CREATE NONCLUSTERED INDEX IX_transactions_collection_time
                ON collection.transactions (collection_time);
                
            CREATE NONCLUSTERED INDEX IX_transactions_session_transaction
                ON collection.transactions (session_id, transaction_id);
                
            CREATE NONCLUSTERED INDEX IX_transactions_duration
                ON collection.transactions (transaction_duration_seconds DESC);';
        END
        ELSE IF @table_name = N'detailed_waits'
        BEGIN
            SET @sql = N'
            CREATE TABLE
                collection.detailed_waits
            (
                collection_id BIGINT IDENTITY(1,1) NOT NULL,
                collection_time DATETIME2(7) NOT NULL,
                session_id INTEGER NOT NULL,
                wait_type NVARCHAR(128) NOT NULL,
                wait_duration_ms BIGINT NOT NULL,
                resource_description NVARCHAR(4000) NULL,
                blocking_session_id INTEGER NULL,
                blocking_exec_context_id INTEGER NULL,
                resource_address VARBINARY(8) NULL,
                sql_text NVARCHAR(MAX) NULL,
                database_name NVARCHAR(128) NULL,
                wait_resource_type NVARCHAR(100) NULL,
                wait_resource_database_id INTEGER NULL,
                wait_resource_object_id INTEGER NULL,
                wait_resource_index_id INTEGER NULL,
                wait_resource_object_name NVARCHAR(386) NULL,
                wait_resource_index_name NVARCHAR(128) NULL,
                CONSTRAINT PK_detailed_waits PRIMARY KEY CLUSTERED (collection_id)
            );
            
            CREATE NONCLUSTERED INDEX IX_detailed_waits_collection_time
                ON collection.detailed_waits (collection_time);
                
            CREATE NONCLUSTERED INDEX IX_detailed_waits_session_id
                ON collection.detailed_waits (session_id);
                
            CREATE NONCLUSTERED INDEX IX_detailed_waits_wait_type
                ON collection.detailed_waits (wait_type);
                
            CREATE NONCLUSTERED INDEX IX_detailed_waits_duration
                ON collection.detailed_waits (wait_duration_ms DESC);';
        END
        ELSE IF @table_name = N'blocking'
        BEGIN
            SET @sql = N'
            CREATE TABLE
                collection.blocking
            (
                collection_id BIGINT IDENTITY(1,1) NOT NULL,
                collection_time DATETIME2(7) NOT NULL,
                blocked_spid INTEGER NOT NULL,
                blocking_spid INTEGER NOT NULL,
                blocked_login NVARCHAR(128) NOT NULL,
                blocked_hostname NVARCHAR(128) NULL,
                blocked_program NVARCHAR(128) NULL,
                blocked_database_id INTEGER NOT NULL,
                blocked_database_name NVARCHAR(128) NOT NULL,
                blocked_batch NVARCHAR(MAX) NULL,
                blocked_statement NVARCHAR(MAX) NULL,
                blocking_login NVARCHAR(128) NULL,
                blocking_hostname NVARCHAR(128) NULL,
                blocking_program NVARCHAR(128) NULL,
                blocking_database_id INTEGER NULL,
                blocking_database_name NVARCHAR(128) NULL,
                blocking_batch NVARCHAR(MAX) NULL,
                blocking_statement NVARCHAR(MAX) NULL,
                blocked_wait_type NVARCHAR(128) NULL,
                blocked_wait_time_ms BIGINT NULL,
                blocked_wait_resource NVARCHAR(256) NULL,
                blocked_transaction_count INTEGER NULL,
                blocked_transaction_duration_seconds INTEGER NULL,
                blocked_transaction_state NVARCHAR(60) NULL,
                blocked_transaction_type NVARCHAR(60) NULL,
                blocked_lock_mode NVARCHAR(60) NULL,
                blocking_lock_mode NVARCHAR(60) NULL,
                blocking_transaction_count INTEGER NULL,
                blocking_transaction_duration_seconds INTEGER NULL,
                blocking_transaction_state NVARCHAR(60) NULL,
                blocking_transaction_type NVARCHAR(60) NULL,
                blocking_chain NVARCHAR(4000) NULL,
                CONSTRAINT PK_blocking PRIMARY KEY CLUSTERED (collection_id)
            );
            
            CREATE NONCLUSTERED INDEX IX_blocking_collection_time
                ON collection.blocking (collection_time);
                
            CREATE NONCLUSTERED INDEX IX_blocking_spids
                ON collection.blocking (blocked_spid, blocking_spid);
                
            CREATE NONCLUSTERED INDEX IX_blocking_wait_time
                ON collection.blocking (blocked_wait_time_ms DESC);';
        END
        ELSE IF @table_name = N'connections'
        BEGIN
            SET @sql = N'
            CREATE TABLE
                collection.connections
            (
                collection_id BIGINT IDENTITY(1,1) NOT NULL,
                collection_time DATETIME2(7) NOT NULL,
                session_id INTEGER NOT NULL,
                connect_time DATETIME NOT NULL,
                connection_duration_minutes INTEGER NOT NULL,
                last_request_start_time DATETIME NULL,
                last_request_end_time DATETIME NULL,
                session_status NVARCHAR(30) NOT NULL,
                transaction_isolation_level INTEGER NULL,
                transaction_isolation_level_desc NVARCHAR(30) NULL,
                login_name NVARCHAR(128) NOT NULL,
                host_name NVARCHAR(128) NULL,
                program_name NVARCHAR(128) NULL,
                client_interface_name NVARCHAR(32) NULL,
                client_version NVARCHAR(20) NULL,
                client_net_address NVARCHAR(48) NULL,
                local_net_address NVARCHAR(48) NULL,
                auth_scheme NVARCHAR(40) NULL,
                endpoint_name NVARCHAR(128) NULL,
                protocol_type NVARCHAR(40) NULL,
                protocol_version INTEGER NULL,
                net_transport NVARCHAR(40) NULL,
                net_packet_size INTEGER NULL,
                open_transaction_count INTEGER NULL,
                database_id INTEGER NULL,
                database_name NVARCHAR(128) NULL,
                context_info VARBINARY(128) NULL,
                prev_error INTEGER NULL,
                CONSTRAINT PK_connections PRIMARY KEY CLUSTERED (collection_id)
            );
            
            CREATE NONCLUSTERED INDEX IX_connections_collection_time
                ON collection.connections (collection_time);
                
            CREATE NONCLUSTERED INDEX IX_connections_session_id
                ON collection.connections (session_id);
                
            CREATE NONCLUSTERED INDEX IX_connections_login_name
                ON collection.connections (login_name);';
        END
        ELSE IF @table_name = N'deadlocks'
        BEGIN
            SET @sql = N'
            CREATE TABLE
                collection.deadlocks
            (
                collection_id BIGINT IDENTITY(1,1) NOT NULL,
                collection_time DATETIME2(7) NOT NULL,
                deadlock_time DATETIME2(7) NOT NULL,
                deadlock_id UNIQUEIDENTIFIER NOT NULL,
                deadlock_victim_spid INTEGER NULL,
                deadlock_victim_database_id INTEGER NULL,
                deadlock_victim_database_name NVARCHAR(128) NULL,
                deadlock_victim_object_id INTEGER NULL,
                deadlock_victim_object_name NVARCHAR(386) NULL,
                deadlock_resources NVARCHAR(MAX) NULL,
                deadlock_victim_statement NVARCHAR(MAX) NULL,
                deadlock_victim_login NVARCHAR(128) NULL,
                deadlock_victim_hostname NVARCHAR(128) NULL,
                deadlock_victim_application NVARCHAR(128) NULL,
                deadlock_victim_wait_time INTEGER NULL,
                deadlock_victim_wait_resource NVARCHAR(256) NULL,
                deadlock_victim_lock_mode NVARCHAR(60) NULL,
                deadlock_victim_transaction_count INTEGER NULL,
                deadlock_victim_transaction_isolation_level NVARCHAR(30) NULL,
                deadlock_victim_input_buffer NVARCHAR(MAX) NULL,
                deadlock_graph XML NULL,
                deadlock_xml XML NULL,
                CONSTRAINT PK_deadlocks PRIMARY KEY CLUSTERED (collection_id)
            );
            
            CREATE NONCLUSTERED INDEX IX_deadlocks_collection_time
                ON collection.deadlocks (collection_time);
                
            CREATE NONCLUSTERED INDEX IX_deadlocks_deadlock_time
                ON collection.deadlocks (deadlock_time);
                
            CREATE NONCLUSTERED INDEX IX_deadlocks_victim_spid
                ON collection.deadlocks (deadlock_victim_spid);';
        END
        ELSE IF @table_name = N'index_usage_stats'
        BEGIN
            SET @sql = N'
            CREATE TABLE
                collection.index_usage_stats
            (
                collection_id BIGINT IDENTITY(1,1) NOT NULL,
                collection_time DATETIME2(7) NOT NULL,
                database_id INTEGER NOT NULL,
                database_name NVARCHAR(128) NOT NULL,
                object_id INTEGER NOT NULL,
                schema_name NVARCHAR(128) NOT NULL,
                object_name NVARCHAR(128) NOT NULL,
                index_id INTEGER NOT NULL,
                index_name NVARCHAR(128) NULL,
                user_seeks BIGINT NOT NULL,
                user_scans BIGINT NOT NULL,
                user_lookups BIGINT NOT NULL,
                user_updates BIGINT NOT NULL,
                last_user_seek DATETIME2(7) NULL,
                last_user_scan DATETIME2(7) NULL,
                last_user_lookup DATETIME2(7) NULL,
                last_user_update DATETIME2(7) NULL,
                user_seeks_delta BIGINT NULL,
                user_scans_delta BIGINT NULL,
                user_lookups_delta BIGINT NULL,
                user_updates_delta BIGINT NULL,
                sample_seconds INTEGER NULL,
                CONSTRAINT PK_index_usage_stats PRIMARY KEY CLUSTERED (collection_id)
            );
            
            CREATE NONCLUSTERED INDEX IX_index_usage_stats_collection_time
                ON collection.index_usage_stats (collection_time);
                
            CREATE NONCLUSTERED INDEX IX_index_usage_stats_database_object_index
                ON collection.index_usage_stats (database_id, object_id, index_id);
                
            CREATE NONCLUSTERED INDEX IX_index_usage_stats_user_seeks
                ON collection.index_usage_stats (user_seeks DESC);';
        END
        ELSE IF @table_name = N'io_stats'
        BEGIN
            SET @sql = N'
            CREATE TABLE
                collection.io_stats
            (
                collection_id BIGINT IDENTITY(1,1) NOT NULL,
                collection_time DATETIME2(7) NOT NULL,
                server_name NVARCHAR(256) NOT NULL,
                environment NVARCHAR(50) NOT NULL,
                database_id INTEGER NOT NULL,
                database_name NVARCHAR(128) NOT NULL,
                file_id INTEGER NOT NULL,
                file_name NVARCHAR(128) NOT NULL,
                file_path NVARCHAR(260) NOT NULL,
                drive_letter NVARCHAR(10) NULL,
                type_desc NVARCHAR(60) NOT NULL,
                state_desc NVARCHAR(60) NOT NULL,
                size_mb DECIMAL(18,2) NOT NULL,
                max_size_mb DECIMAL(18,2) NULL,
                growth DECIMAL(18,2) NOT NULL,
                is_percent_growth BIT NOT NULL,
                io_stall_read_ms BIGINT NOT NULL,
                io_stall_write_ms BIGINT NOT NULL,
                io_stall BIGINT NOT NULL,
                num_of_reads BIGINT NOT NULL,
                num_of_writes BIGINT NOT NULL,
                num_of_bytes_read BIGINT NOT NULL,
                num_of_bytes_written BIGINT NOT NULL,
                io_stall_read_ms_delta BIGINT NULL,
                io_stall_write_ms_delta BIGINT NULL,
                io_stall_delta BIGINT NULL,
                num_of_reads_delta BIGINT NULL,
                num_of_writes_delta BIGINT NULL,
                num_of_bytes_read_delta BIGINT NULL,
                num_of_bytes_written_delta BIGINT NULL,
                sample_seconds INTEGER NULL,
                read_latency_ms DECIMAL(18,2) NULL,
                write_latency_ms DECIMAL(18,2) NULL,
                avg_read_stall_ms DECIMAL(18,2) NULL,
                avg_write_stall_ms DECIMAL(18,2) NULL,
                size_on_disk_bytes BIGINT NULL,
                size_on_disk_mb DECIMAL(18,2) NULL,
                CONSTRAINT PK_io_stats PRIMARY KEY CLUSTERED (collection_id)
            );
            
            CREATE NONCLUSTERED INDEX IX_io_stats_collection_time
                ON collection.io_stats (collection_time);
                
            CREATE NONCLUSTERED INDEX IX_io_stats_database_file
                ON collection.io_stats (database_id, file_id);
                
            CREATE NONCLUSTERED INDEX IX_io_stats_io_stall
                ON collection.io_stats (io_stall DESC);';
        END
        ELSE IF @table_name = N'drive_stats'
        BEGIN
            SET @sql = N'
            CREATE TABLE
                collection.drive_stats
            (
                collection_id BIGINT IDENTITY(1,1) NOT NULL,
                collection_time DATETIME2(7) NOT NULL,
                server_name NVARCHAR(256) NOT NULL,
                drive_letter NVARCHAR(10) NOT NULL,
                io_stall_read_ms BIGINT NOT NULL,
                io_stall_write_ms BIGINT NOT NULL,
                io_stall BIGINT NOT NULL,
                num_of_reads BIGINT NOT NULL,
                num_of_writes BIGINT NOT NULL,
                num_of_bytes_read BIGINT NOT NULL,
                num_of_bytes_written BIGINT NOT NULL,
                read_latency_ms DECIMAL(18,2) NOT NULL,
                write_latency_ms DECIMAL(18,2) NOT NULL,
                total_mb_read DECIMAL(18,2) NOT NULL,
                total_mb_written DECIMAL(18,2) NOT NULL,
                size_on_disk_bytes BIGINT NULL,
                size_on_disk_gb DECIMAL(18,2) NULL,
                CONSTRAINT PK_drive_stats PRIMARY KEY CLUSTERED (collection_id)
            );
            
            CREATE NONCLUSTERED INDEX IX_drive_stats_collection_time
                ON collection.drive_stats (collection_time);
                
            CREATE NONCLUSTERED INDEX IX_drive_stats_drive_letter
                ON collection.drive_stats (drive_letter);';
        END
        ELSE IF @table_name = N'query_stats'
        BEGIN
            SET @sql = N'
            CREATE TABLE
                collection.query_stats
            (
                collection_id BIGINT IDENTITY(1,1) NOT NULL,
                collection_time DATETIME2(7) NOT NULL,
                server_name NVARCHAR(256) NOT NULL,
                sql_handle VARBINARY(64) NOT NULL,
                plan_handle VARBINARY(64) NOT NULL,
                query_hash BINARY(8) NULL,
                query_plan_hash BINARY(8) NULL,
                statement_start_offset INTEGER NOT NULL,
                statement_end_offset INTEGER NOT NULL,
                execution_count BIGINT NOT NULL,
                execution_count_delta BIGINT NULL,
                plan_generation_num BIGINT NOT NULL,
                creation_time DATETIME NOT NULL,
                last_execution_time DATETIME NOT NULL,
                total_worker_time_ms BIGINT NOT NULL,
                total_worker_time_ms_delta BIGINT NULL,
                avg_worker_time_ms DECIMAL(18,2) NOT NULL,
                last_worker_time_ms BIGINT NOT NULL,
                min_worker_time_ms BIGINT NOT NULL,
                max_worker_time_ms BIGINT NOT NULL,
                total_physical_reads BIGINT NOT NULL,
                total_physical_reads_delta BIGINT NULL,
                avg_physical_reads DECIMAL(18,2) NOT NULL,
                last_physical_reads BIGINT NOT NULL,
                min_physical_reads BIGINT NOT NULL,
                max_physical_reads BIGINT NOT NULL,
                total_logical_writes BIGINT NOT NULL,
                total_logical_writes_delta BIGINT NULL,
                avg_logical_writes DECIMAL(18,2) NOT NULL,
                last_logical_writes BIGINT NOT NULL,
                min_logical_writes BIGINT NOT NULL,
                max_logical_writes BIGINT NOT NULL,
                total_logical_reads BIGINT NOT NULL,
                total_logical_reads_delta BIGINT NULL,
                avg_logical_reads DECIMAL(18,2) NOT NULL,
                last_logical_reads BIGINT NOT NULL,
                min_logical_reads BIGINT NOT NULL,
                max_logical_reads BIGINT NOT NULL,
                total_elapsed_time_ms BIGINT NOT NULL,
                total_elapsed_time_ms_delta BIGINT NULL,
                avg_elapsed_time_ms DECIMAL(18,2) NOT NULL,
                last_elapsed_time_ms BIGINT NOT NULL,
                min_elapsed_time_ms BIGINT NOT NULL,
                max_elapsed_time_ms BIGINT NOT NULL,
                total_spills BIGINT NULL,
                total_spills_delta BIGINT NULL,
                avg_spills DECIMAL(18,2) NULL,
                last_spills BIGINT NULL,
                min_spills BIGINT NULL,
                max_spills BIGINT NULL,
                object_type NVARCHAR(60) NULL,
                object_id INTEGER NULL,
                database_id INTEGER NULL,
                object_name NVARCHAR(386) NULL,
                query_text NVARCHAR(MAX) NULL,
                statement_text NVARCHAR(MAX) NULL,
                sample_seconds INTEGER NULL,
                CONSTRAINT PK_query_stats PRIMARY KEY CLUSTERED (collection_id)
            );
            
            CREATE NONCLUSTERED INDEX IX_query_stats_collection_time
                ON collection.query_stats (collection_time);
                
            CREATE NONCLUSTERED INDEX IX_query_stats_sql_handle
                ON collection.query_stats (sql_handle, statement_start_offset, statement_end_offset);
                
            CREATE NONCLUSTERED INDEX IX_query_stats_query_hash
                ON collection.query_stats (query_hash);
                
            CREATE NONCLUSTERED INDEX IX_query_stats_worker_time
                ON collection.query_stats (total_worker_time_ms DESC);
                
            CREATE NONCLUSTERED INDEX IX_query_stats_logical_reads
                ON collection.query_stats (total_logical_reads DESC);
                
            CREATE NONCLUSTERED INDEX IX_query_stats_execution_count
                ON collection.query_stats (execution_count DESC);';
        END
        ELSE IF @table_name = N'query_store'
        BEGIN
            SET @sql = N'
            CREATE TABLE
                collection.query_store
            (
                collection_id BIGINT IDENTITY(1,1) NOT NULL,
                collection_time DATETIME2(7) NOT NULL,
                database_id INTEGER NOT NULL,
                database_name NVARCHAR(128) NOT NULL,
                query_id BIGINT NOT NULL,
                query_store_query_id BIGINT NOT NULL,
                query_text_id BIGINT NOT NULL,
                last_execution_time DATETIME2(7) NOT NULL,
                count_executions BIGINT NOT NULL,
                plan_id BIGINT NOT NULL,
                query_store_plan_id BIGINT NOT NULL,
                is_forced_plan BIT NOT NULL,
                is_natively_compiled BIT NOT NULL,
                force_failure_count BIGINT NOT NULL,
                last_force_failure_reason_desc NVARCHAR(256) NULL,
                compatibility_level INTEGER NOT NULL,
                total_cpu_time_ms BIGINT NOT NULL,
                avg_cpu_time_ms DECIMAL(18,2) NOT NULL,
                total_duration_ms BIGINT NOT NULL,
                avg_duration_ms DECIMAL(18,2) NOT NULL,
                total_logical_io_reads BIGINT NOT NULL,
                avg_logical_io_reads DECIMAL(18,2) NOT NULL,
                total_logical_io_writes BIGINT NOT NULL,
                avg_logical_io_writes DECIMAL(18,2) NOT NULL,
                total_physical_io_reads BIGINT NOT NULL,
                avg_physical_io_reads DECIMAL(18,2) NOT NULL,
                total_clr_time_ms BIGINT NOT NULL,
                avg_clr_time_ms DECIMAL(18,2) NOT NULL,
                total_dop BIGINT NOT NULL,
                avg_dop DECIMAL(18,2) NOT NULL,
                total_grant_kb BIGINT NOT NULL,
                avg_grant_kb DECIMAL(18,2) NOT NULL,
                total_used_grant_kb BIGINT NOT NULL,
                avg_used_grant_kb DECIMAL(18,2) NOT NULL,
                total_ideal_grant_kb BIGINT NOT NULL,
                avg_ideal_grant_kb DECIMAL(18,2) NOT NULL,
                total_reserved_threads BIGINT NOT NULL,
                avg_reserved_threads DECIMAL(18,2) NOT NULL,
                total_used_threads BIGINT NOT NULL,
                avg_used_threads DECIMAL(18,2) NOT NULL,
                total_tempdb_space_used_kb BIGINT NULL,
                avg_tempdb_space_used_kb DECIMAL(18,2) NULL,
                total_page_server_io_reads BIGINT NULL,
                avg_page_server_io_reads DECIMAL(18,2) NULL,
                total_log_bytes_used BIGINT NULL,
                avg_log_bytes_used DECIMAL(18,2) NULL,
                total_num_physical_io_reads BIGINT NULL,
                avg_num_physical_io_reads DECIMAL(18,2) NULL,
                total_log_bytes_used_mb AS (total_log_bytes_used / 1024.0 / 1024.0),
                query_sql_text NVARCHAR(MAX) NULL,
                query_plan XML NULL,
                CONSTRAINT PK_query_store PRIMARY KEY CLUSTERED (collection_id)
            );
            
            CREATE NONCLUSTERED INDEX IX_query_store_collection_time
                ON collection.query_store (collection_time);
                
            CREATE NONCLUSTERED INDEX IX_query_store_database_query_plan
                ON collection.query_store (database_id, query_store_query_id, query_store_plan_id);
                
            CREATE NONCLUSTERED INDEX IX_query_store_cpu_time
                ON collection.query_store (total_cpu_time_ms DESC);
                
            CREATE NONCLUSTERED INDEX IX_query_store_logical_reads
                ON collection.query_store (total_logical_io_reads DESC);
                
            CREATE NONCLUSTERED INDEX IX_query_store_execution_count
                ON collection.query_store (count_executions DESC);';
        END;
        ELSE
        BEGIN
            RAISERROR(N'Unknown table name: %s', 16, 1, @table_name) WITH NOWAIT;
            RETURN;
        END;
        
        /*
        Execute SQL to create the table
        */
        EXECUTE sp_executesql @sql;
        
        /*
        Print debug information
        */
        IF @debug = 1
        BEGIN
            RAISERROR(N'Created table: %s', 0, 1, @full_table_name) WITH NOWAIT;
        END;
    END TRY
    BEGIN CATCH
        SET @error_number = ERROR_NUMBER();
        SET @error_message = ERROR_MESSAGE();
        
        RAISERROR(N'Error %d creating table %s: %s', 16, 1, @error_number, @full_table_name, @error_message) WITH NOWAIT;
    END CATCH;
END;
GO