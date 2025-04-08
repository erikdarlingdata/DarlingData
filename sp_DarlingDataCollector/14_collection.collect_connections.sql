/*
 ██████╗ ██████╗ ███╗   ██╗███╗   ██╗███████╗ ██████╗████████╗██╗ ██████╗ ███╗   ██╗███████╗
██╔════╝██╔═══██╗████╗  ██║████╗  ██║██╔════╝██╔════╝╚══██╔══╝██║██╔═══██╗████╗  ██║██╔════╝
██║     ██║   ██║██╔██╗ ██║██╔██╗ ██║█████╗  ██║        ██║   ██║██║   ██║██╔██╗ ██║███████╗
██║     ██║   ██║██║╚██╗██║██║╚██╗██║██╔══╝  ██║        ██║   ██║██║   ██║██║╚██╗██║╚════██║
╚██████╗╚██████╔╝██║ ╚████║██║ ╚████║███████╗╚██████╗   ██║   ██║╚██████╔╝██║ ╚████║███████║
 ╚═════╝ ╚═════╝ ╚═╝  ╚═══╝╚═╝  ╚═══╝╚══════╝ ╚═════╝   ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝
                                                                                             
Copyright (c) Darling Data, LLC
https://www.erikdarling.com/

--===== CONNECTION COLLECTOR NOTES ====--
This procedure captures comprehensive information about active connections
on the SQL Server instance. It gathers session details, query information,
resource usage metrics, blocking chains, and memory grants.

Inspiration from:
- sp_whoisactive by Adam Machanic
- sp_BlitzWho by Brent Ozar Unlimited
*/

CREATE OR ALTER PROCEDURE
    collection.collect_connections
(
    @debug BIT = 0, /*Print debugging information*/
    @include_system_sessions BIT = 0, /*Include system sessions*/
    @collect_query_plans BIT = 1, /*Collect query plans for active sessions*/
    @collect_query_text BIT = 1, /*Collect query text for active sessions*/
    @collect_transaction_info BIT = 1, /*Collect transaction information*/
    @collect_blocking_info BIT = 1, /*Collect detailed blocking information*/
    @exclude_idle_sessions BIT = 1, /*Exclude sessions that are idle with no open transactions*/
    @include_sleeping_sessions_with_open_tran BIT = 1, /*Include sleeping sessions that have open transactions*/
    @min_blocking_duration_ms INTEGER = 500 /*Minimum blocking duration to track*/
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
        @error_message NVARCHAR(4000),
        @sql NVARCHAR(MAX) = N'';
    
    /*
    Create temp tables to store intermediate results
    */
    CREATE TABLE
        #sessions
    (
        session_id SMALLINT NOT NULL,
        request_id INTEGER NOT NULL,
        login_name NVARCHAR(128) NULL,
        host_name NVARCHAR(128) NULL,
        program_name NVARCHAR(128) NULL,
        client_interface_name NVARCHAR(128) NULL,
        login_time DATETIME NULL,
        status NVARCHAR(30) NULL,
        cpu_time BIGINT NULL,
        memory_usage BIGINT NULL,
        total_elapsed_time BIGINT NULL,
        last_request_start_time DATETIME NULL,
        last_request_end_time DATETIME NULL,
        reads BIGINT NULL,
        logical_reads BIGINT NULL,
        writes BIGINT NULL,
        database_id INTEGER NULL,
        database_name NVARCHAR(128) NULL,
        transaction_isolation_level NVARCHAR(30) NULL,
        lock_timeout INTEGER NULL,
        deadlock_priority INTEGER NULL,
        row_count BIGINT NULL,
        context_info VARBINARY(128) NULL,
        is_user_process BIT NULL,
        open_transaction_count INTEGER NULL,
        transaction_id BIGINT NULL,
        longest_transaction_start_time DATETIME NULL,
        wait_type NVARCHAR(60) NULL,
        wait_time_ms BIGINT NULL,
        wait_resource NVARCHAR(256) NULL,
        blocked_by SMALLINT NULL,
        blocking_these NVARCHAR(MAX) NULL,
        blocking_count INTEGER NULL,
        command NVARCHAR(32) NULL,
        statement_start_offset INTEGER NULL,
        statement_end_offset INTEGER NULL,
        sql_handle VARBINARY(64) NULL,
        plan_handle VARBINARY(64) NULL,
        query_hash BINARY(8) NULL,
        query_plan_hash BINARY(8) NULL,
        query_plan XML NULL,
        query_text NVARCHAR(MAX) NULL,
        percent_complete DECIMAL(5, 2) NULL,
        est_completion_time BIGINT NULL,
        tempdb_allocations_mb DECIMAL(18, 2) NULL,
        memory_grant_mb DECIMAL(18, 2) NULL,
        used_memory_mb DECIMAL(18, 2) NULL,
        granted_memory_mb DECIMAL(18, 2) NULL,
        requested_memory_mb DECIMAL(18, 2) NULL,
        ideal_memory_mb DECIMAL(18, 2) NULL,
        grant_wait_time_ms BIGINT NULL,
        dop SMALLINT NULL,
        parallel_worker_count SMALLINT NULL,
        session_resource_pool_id INTEGER NULL,
        session_resource_group_id INTEGER NULL,
        resource_pool_name NVARCHAR(128) NULL,
        resource_group_name NVARCHAR(128) NULL
    );
    
    CREATE TABLE
        #blocking_chains
    (
        session_id SMALLINT NOT NULL,
        lead_blocker BIT NOT NULL DEFAULT 0,
        is_victim BIT NOT NULL DEFAULT 0,
        blocking_level INTEGER NOT NULL,
        blocking_path NVARCHAR(MAX) NULL
    );
    
    BEGIN TRY
        /*
        Collect base session information with wait stats and query data
        */
        INSERT
            #sessions
        (
            session_id,
            request_id,
            login_name,
            host_name,
            program_name,
            client_interface_name,
            login_time,
            status,
            cpu_time,
            memory_usage,
            total_elapsed_time,
            last_request_start_time,
            last_request_end_time,
            reads,
            logical_reads,
            writes,
            database_id,
            database_name,
            transaction_isolation_level,
            lock_timeout,
            deadlock_priority,
            row_count,
            context_info,
            is_user_process,
            open_transaction_count,
            wait_type,
            wait_time_ms,
            wait_resource,
            blocked_by,
            command,
            statement_start_offset,
            statement_end_offset,
            sql_handle,
            plan_handle,
            query_hash,
            query_plan_hash,
            percent_complete,
            est_completion_time
        )
        SELECT
            s.session_id,
            request_id = ISNULL(r.request_id, 0),
            login_name = s.login_name,
            host_name = s.host_name,
            program_name = s.program_name,
            client_interface_name = s.client_interface_name,
            login_time = s.login_time,
            status = ISNULL(r.status, s.status),
            cpu_time = s.cpu_time,
            memory_usage = s.memory_usage,
            total_elapsed_time = s.total_elapsed_time,
            last_request_start_time = s.last_request_start_time,
            last_request_end_time = s.last_request_end_time,
            reads = s.reads,
            logical_reads = s.logical_reads,
            writes = s.writes,
            database_id = ISNULL(r.database_id, s.database_id),
            database_name = DB_NAME(ISNULL(r.database_id, s.database_id)),
            transaction_isolation_level = 
                CASE s.transaction_isolation_level
                    WHEN 0 THEN N'Unspecified'
                    WHEN 1 THEN N'ReadUncommitted'
                    WHEN 2 THEN N'ReadCommitted'
                    WHEN 3 THEN N'Repeatable'
                    WHEN 4 THEN N'Serializable'
                    WHEN 5 THEN N'Snapshot'
                    ELSE N'Unknown'
                END,
            lock_timeout = s.lock_timeout,
            deadlock_priority = s.deadlock_priority,
            row_count = s.row_count,
            context_info = s.context_info,
            is_user_process = s.is_user_process,
            open_transaction_count = ISNULL(s.open_transaction_count, 0),
            wait_type = ISNULL(r.wait_type, N''),
            wait_time_ms = ISNULL(r.wait_time, 0),
            wait_resource = ISNULL(r.wait_resource, N''),
            blocked_by = NULLIF(r.blocking_session_id, 0),
            command = ISNULL(r.command, N''),
            statement_start_offset = r.statement_start_offset,
            statement_end_offset = r.statement_end_offset,
            sql_handle = r.sql_handle,
            plan_handle = r.plan_handle,
            query_hash = r.query_hash,
            query_plan_hash = r.query_plan_hash,
            percent_complete = ISNULL(r.percent_complete, 0.0),
            est_completion_time = r.estimated_completion_time
        FROM 
            sys.dm_exec_sessions AS s
        LEFT JOIN 
            sys.dm_exec_requests AS r
            ON r.session_id = s.session_id
        WHERE
            /* Filter system sessions and idle sessions as requested */
            (s.is_user_process = 1 OR @include_system_sessions = 1)
            AND
            (
                @exclude_idle_sessions = 0
                OR s.open_transaction_count > 0
                OR r.session_id IS NOT NULL
                OR EXISTS
                (
                    SELECT
                        1
                    FROM
                        sys.dm_exec_requests AS r2
                    WHERE
                        r2.blocking_session_id = s.session_id
                )
            )
            AND
            (
                ISNULL(r.status, s.status) <> N'sleeping'
                OR s.open_transaction_count > 0
                OR @include_sleeping_sessions_with_open_tran = 0
                OR EXISTS
                (
                    SELECT
                        1
                    FROM
                        sys.dm_exec_requests AS r2
                    WHERE
                        r2.blocking_session_id = s.session_id
                )
            );
        
        /*
        Grab Transaction Information
        */
        IF @collect_transaction_info = 1
        BEGIN
            UPDATE
                s
            SET
                transaction_id = t.transaction_id,
                longest_transaction_start_time = t.transaction_begin_time
            FROM
                #sessions AS s
            CROSS APPLY
            (
                SELECT TOP (1)
                    t.transaction_id,
                    transaction_begin_time = DATEADD
                    (
                        MILLISECOND,
                        -ISNULL(transaction_duration, 0),
                        SYSDATETIME()
                    )
                FROM
                    sys.dm_tran_active_transactions AS t
                JOIN
                    sys.dm_tran_session_transactions AS st
                    ON t.transaction_id = st.transaction_id
                WHERE
                    s.session_id = st.session_id
                ORDER BY
                    t.transaction_begin_time ASC
            ) AS t
            WHERE
                s.open_transaction_count > 0;
        END;
        
        /*
        Collecting Memory Grant Information
        */
        UPDATE
            s
        SET
            memory_grant_mb = CONVERT(DECIMAL(18, 2), mg.grant_kb) / 1024.0,
            used_memory_mb = CONVERT(DECIMAL(18, 2), mg.used_memory_kb) / 1024.0,
            granted_memory_mb = CONVERT(DECIMAL(18, 2), mg.granted_memory_kb) / 1024.0,
            requested_memory_mb = CONVERT(DECIMAL(18, 2), mg.requested_memory_kb) / 1024.0,
            ideal_memory_mb = CONVERT(DECIMAL(18, 2), mg.ideal_memory_kb) / 1024.0,
            grant_wait_time_ms = mg.wait_time_ms,
            dop = mg.dop,
            parallel_worker_count = mg.used_worker_count,
            session_resource_pool_id = mg.group_id,
            session_resource_group_id = mg.pool_id
        FROM
            #sessions AS s
        JOIN
            sys.dm_exec_query_memory_grants AS mg
            ON s.session_id = mg.session_id
            AND s.request_id = mg.request_id;
        
        /*
        Collecting Resource Governor Information
        */
        UPDATE
            s
        SET
            resource_pool_name = rp.name,
            resource_group_name = rg.name
        FROM
            #sessions AS s
        LEFT JOIN
            sys.dm_resource_governor_workload_groups AS rg
            ON rg.group_id = s.session_resource_group_id
        LEFT JOIN
            sys.dm_resource_governor_resource_pools AS rp
            ON rp.pool_id = s.session_resource_pool_id;
        
        /*
        Calculating TempDB Allocations
        */
        UPDATE
            s
        SET
            tempdb_allocations_mb = tdb.tempdb_allocations_mb
        FROM
            #sessions AS s
        CROSS APPLY
        (
            SELECT
                tempdb_allocations_mb = 
                    CONVERT
                    (
                        DECIMAL(18, 2),
                        SUM(tsu.user_objects_alloc_page_count + tsu.internal_objects_alloc_page_count) / 128.0
                    )
            FROM
                sys.dm_db_task_space_usage AS tsu
            WHERE
                tsu.session_id = s.session_id
            GROUP BY
                tsu.session_id
        ) AS tdb;
        
        /*
        Construct Blocking Chains
        */
        IF @collect_blocking_info = 1
        BEGIN
            /* RECURSIVELY build blocking chain data */
            WITH
                blocking_hierarchy
            AS
            (
                /* Base case: sessions that aren't blocked, but blocking others */
                SELECT
                    src.session_id,
                    blocked_by = convert(smallint, NULL),
                    blocking_level = 0,
                    blocking_path = CONVERT(nvarchar(max), NULL)
                FROM
                    #sessions AS src
                LEFT JOIN
                    #sessions AS blocked
                    ON blocked.blocked_by = src.session_id
                WHERE
                    src.blocked_by IS NULL
                AND
                    blocked.session_id IS NOT NULL
                
                UNION ALL
                
                /* Recursively add all blocked sessions, incrementing the level */
                SELECT
                    blocked.session_id,
                    blocked_by = blocked.blocked_by,
                    blocking_level = b.blocking_level + 1,
                    blocking_path = CONVERT(nvarchar(max), 
                                   CASE 
                                       WHEN b.blocking_path IS NULL 
                                       THEN CAST(b.session_id AS nvarchar(10))
                                       ELSE b.blocking_path + N' → ' + CAST(blocked.session_id AS nvarchar(10))
                                   END)
                FROM
                    blocking_hierarchy AS b
                JOIN
                    #sessions AS blocked
                    ON blocked.blocked_by = b.session_id
            )
            INSERT
                #blocking_chains
            (
                session_id,
                lead_blocker,
                blocking_level,
                blocking_path
            )
            SELECT
                session_id,
                lead_blocker = CASE WHEN blocking_level = 0 THEN 1 ELSE 0 END,
                blocking_level,
                blocking_path
            FROM
                blocking_hierarchy;
            
            /*
            Update blocking_these with list of blocked sessions
            */
            UPDATE
                s
            SET
                blocking_these = c.blocking_these,
                blocking_count = c.blocking_count
            FROM
                #sessions AS s
            JOIN
            (
                SELECT
                    bc1.session_id,
                    blocking_these = STUFF(
                        (
                            SELECT
                                N', ' + CAST(bc2.session_id AS nvarchar(10))
                            FROM
                                #blocking_chains AS bc2
                            WHERE
                                bc2.blocking_path LIKE N'%' + CAST(bc1.session_id AS nvarchar(10)) + N'%'
                            AND
                                bc2.session_id <> bc1.session_id
                            ORDER BY
                                bc2.session_id
                            FOR XML PATH(N''), TYPE
                        ).value(N'.[1]', N'nvarchar(max)'),
                        1, 2, N''),
                    blocking_count = COUNT(*)
                FROM
                    #blocking_chains AS bc1
                WHERE
                    bc1.lead_blocker = 1
                GROUP BY
                    bc1.session_id
            ) AS c
            ON s.session_id = c.session_id;
        END;
        
        /*
        Get QueryText for active requests if requested
        */
        IF @collect_query_text = 1
        BEGIN
            UPDATE
                s
            SET
                query_text = SUBSTRING
                (
                    qt.text,
                    (s.statement_start_offset / 2) + 1,
                    CASE
                        WHEN s.statement_end_offset = -1 THEN LEN(CONVERT(nvarchar(max), qt.text)) * 2
                        ELSE (s.statement_end_offset - s.statement_start_offset) / 2
                    END
                )
            FROM
                #sessions AS s
            OUTER APPLY
                sys.dm_exec_sql_text(s.sql_handle) AS qt
            WHERE
                s.sql_handle IS NOT NULL;
        END;
        
        /*
        Get Query Plans if requested
        */
        IF @collect_query_plans = 1
        BEGIN
            UPDATE
                s
            SET
                query_plan = qp.query_plan
            FROM
                #sessions AS s
            OUTER APPLY
                sys.dm_exec_query_plan(s.plan_handle) AS qp
            WHERE
                s.plan_handle IS NOT NULL;
        END;
        
        /*
        Insert final results to collection table
        */
        INSERT
            collection.connections
        (
            collection_time,
            session_id,
            request_id,
            login_name,
            host_name,
            program_name,
            client_interface_name,
            login_time,
            status,
            cpu_time,
            memory_usage,
            total_elapsed_time,
            last_request_start_time,
            last_request_end_time,
            reads,
            logical_reads,
            writes,
            database_id,
            database_name,
            transaction_isolation_level,
            lock_timeout,
            deadlock_priority,
            row_count,
            context_info,
            is_user_process,
            open_transaction_count,
            transaction_id,
            longest_transaction_start_time,
            wait_type,
            wait_time_ms,
            wait_resource,
            blocked_by,
            blocking_these,
            blocking_count,
            lead_blocker,
            blocking_level,
            blocking_path,
            command,
            sql_handle,
            plan_handle,
            query_hash,
            query_plan_hash,
            query_plan,
            query_text,
            percent_complete,
            est_completion_time,
            tempdb_allocations_mb,
            memory_grant_mb,
            used_memory_mb,
            granted_memory_mb,
            requested_memory_mb,
            ideal_memory_mb,
            grant_wait_time_ms,
            dop,
            parallel_worker_count,
            resource_pool_name,
            resource_group_name
        )
        SELECT
            collection_time = @collection_start,
            s.session_id,
            s.request_id,
            s.login_name,
            s.host_name,
            s.program_name,
            s.client_interface_name,
            s.login_time,
            s.status,
            s.cpu_time,
            s.memory_usage,
            s.total_elapsed_time,
            s.last_request_start_time,
            s.last_request_end_time,
            s.reads,
            s.logical_reads,
            s.writes,
            s.database_id,
            s.database_name,
            s.transaction_isolation_level,
            s.lock_timeout,
            s.deadlock_priority,
            s.row_count,
            s.context_info,
            s.is_user_process,
            s.open_transaction_count,
            s.transaction_id,
            s.longest_transaction_start_time,
            s.wait_type,
            s.wait_time_ms,
            s.wait_resource,
            s.blocked_by,
            s.blocking_these,
            s.blocking_count,
            lead_blocker = ISNULL(bc.lead_blocker, 0),
            blocking_level = ISNULL(bc.blocking_level, 0),
            blocking_path = bc.blocking_path,
            s.command,
            s.sql_handle,
            s.plan_handle,
            s.query_hash,
            s.query_plan_hash,
            s.query_plan,
            s.query_text,
            s.percent_complete,
            s.est_completion_time,
            s.tempdb_allocations_mb,
            s.memory_grant_mb,
            s.used_memory_mb,
            s.granted_memory_mb,
            s.requested_memory_mb,
            s.ideal_memory_mb,
            s.grant_wait_time_ms,
            s.dop,
            s.parallel_worker_count,
            s.resource_pool_name,
            s.resource_group_name
        FROM
            #sessions AS s
        LEFT JOIN
            #blocking_chains AS bc
            ON s.session_id = bc.session_id
        WHERE
            s.wait_time_ms >= @min_blocking_duration_ms
            OR s.blocked_by IS NULL
            OR s.query_text IS NOT NULL
            OR s.open_transaction_count > 0
            OR bc.lead_blocker = 1;
        
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
            'collection.collect_connections',
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
                N'Connections Collected' AS collection_type,
                @rows_collected AS rows_collected,
                CAST(DATEDIFF(MILLISECOND, @collection_start, @collection_end) / 1000.0 AS DECIMAL(18,2)) AS duration_seconds,
                blocking_count = 
                (
                    SELECT
                        COUNT(*)
                    FROM
                        #sessions
                    WHERE
                        blocked_by IS NOT NULL
                ),
                lead_blocker_count = 
                (
                    SELECT
                        COUNT(*)
                    FROM
                        #blocking_chains
                    WHERE
                        lead_blocker = 1
                ),
                active_transaction_count = 
                (
                    SELECT
                        COUNT(*)
                    FROM
                        #sessions
                    WHERE
                        open_transaction_count > 0
                );
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
            'collection.collect_connections',
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