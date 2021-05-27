SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

IF OBJECT_ID('dbo.sp_PressureDetector') IS  NULL
    EXEC ('CREATE PROCEDURE dbo.sp_PressureDetector AS RETURN 138;');
GO

ALTER PROCEDURE dbo.sp_PressureDetector 
(
    @what_to_check nvarchar(6) = N'both',    
    @skip_plan_xml bit = 0,
    @version varchar(5) = NULL OUTPUT,
    @versiondate datetime = NULL OUTPUT
)
WITH RECOMPILE
AS 
BEGIN

SET STATISTICS XML OFF;
SET NOCOUNT, XACT_ABORT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
    
SELECT @version = '1.50', @versiondate = '20210519';

/*
    Copyright (c) 2021 Darling Data, LLC 
  
    https://erikdarlingdata.com/
  
    MIT License
    
    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:
    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.
    
    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
*/

    /*
    Check to see if the DAC is enabled.
    If it's not, give people some helpful information.
    */
    DECLARE
        @azure bit = 
            CASE 
                WHEN 
                    CONVERT
                    (
                        sysname, 
                        SERVERPROPERTY('EDITION')
                    ) = N'SQL Azure'
                THEN 1
                ELSE 0
            END,
        @pool_sql nvarchar(MAX) = N'',
        @pages_kb bit = 0,
        @mem_sql nvarchar(MAX) = N'',
        @helpful_new_columns bit = 0,
        @cpu_sql nvarchar(MAX) = N'',
        @cool_new_columns bit = 0;
           
    IF 
    (
        SELECT 
            c.value_in_use
        FROM sys.configurations AS c
        WHERE c.name = N'remote admin connections' 
    ) = 0
    BEGIN
        SELECT 
            'This works a lot better on a troublesome server with the DAC enabled' AS message,
            'EXEC sp_configure ''remote admin connections'', 1; RECONFIGURE;' AS command_to_run,
            'https://bit.ly/RemoteDAC' AS how_to_use_the_dac;
    END;
    
    /*
    See if someone else is using the DAC.
    Return some helpful information if they are.
    */
    IF @azure = 0
    BEGIN
        IF EXISTS 
        (
            SELECT 
                1/0
            FROM sys.endpoints AS ep
            JOIN sys.dm_exec_sessions AS ses
                ON ep.endpoint_id = ses.endpoint_id
            WHERE ep.name = N'Dedicated Admin Connection'
            AND   ses.session_id <> @@SPID 
        )
        BEGIN
            SELECT 
                dac_thief =
                   'who stole the dac?',
                ses.session_id,
                ses.login_time,
                ses.host_name,
                ses.program_name,
                ses.login_name,
                ses.nt_domain,
                ses.nt_user_name,
                ses.status,
                ses.last_request_start_time,
                ses.last_request_end_time
            FROM sys.endpoints AS ep
            JOIN sys.dm_exec_sessions AS ses
                ON ep.endpoint_id = ses.endpoint_id
            WHERE ep.name = N'Dedicated Admin Connection'
            AND   ses.session_id <> @@SPID
            OPTION(MAXDOP 1, RECOMPILE);
        END;
    END;


    /*Memory Grant info*/
    IF @what_to_check IN (N'both', N'memory')
    BEGIN   
        IF
        (
            SELECT
                COUNT_BIG(*)
            FROM sys.all_columns AS ac 
            WHERE ac.object_id = OBJECT_ID(N'sys.dm_os_memory_clerks')
            AND   ac.name = N'pages_kb'
        ) = 1    
        BEGIN
            SET @pages_kb = 1;
        END;
    
        /*
            See buffer pool size, along with stolen memory
            and top non-buffer pool consumers
        */
        SET @pool_sql += N'
        SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

        SELECT 
            memory_consumer = 
                N''Buffer Pool Memory'',
            domc.type,
            memory_used_gb = 
                CONVERT
                (
                    decimal(9, 2),
                    SUM
                    (
                        ' +
                          CASE @pages_kb
                               WHEN 1 
                               THEN
                        N'domc.pages_kb + '
                               ELSE 
                        N'domc.single_pages_kb +
                        domc.multi_pages_kb + '
                          END
                        + N'
                        domc.virtual_memory_committed_kb +
                        domc.awe_allocated_kb +
                        domc.shared_memory_committed_kb
                    ) / 1024. / 1024. 
                )
        FROM sys.dm_os_memory_clerks AS domc
        WHERE domc.type = N''MEMORYCLERK_SQLBUFFERPOOL''
        AND   domc.memory_node_id < 64
        GROUP BY 
            domc.type
        
        UNION ALL
        
        SELECT
            N''Non-Buffer Pool Memory: Total'',
            dopc.counter_name AS memory_consumer,
            CONVERT
            (
                decimal(9, 2), 
                dopc.cntr_value / 1024. / 1024.
            ) AS stolen_memory_gb
        FROM sys.dm_os_performance_counters AS dopc
        WHERE dopc.counter_name LIKE N''Stolen Server%''
        
        UNION ALL
        
        SELECT
            N''Non-Buffer Pool Memory: Top Five'',
            x.type, 
            x.memory_used_gb
        FROM
        (
            SELECT TOP (5)
                domc.type,
                memory_used_gb =
                    CONVERT
                    (
                        decimal(9, 2), 
                        SUM
                        (
                        ' +
                          CASE @pages_kb
                               WHEN 1 
                               THEN
                        N'    domc.pages_kb '
                               ELSE 
                        N'    domc.single_pages_kb +
                            domc.multi_pages_kb '
                          END
                        + N'
                        ) / 1024. / 1024. 
                    )
            FROM sys.dm_os_memory_clerks AS domc
            WHERE domc.type <> N''MEMORYCLERK_SQLBUFFERPOOL''
            GROUP BY
                domc.type
            HAVING
               SUM
               (
                   ' +
                      CASE @pages_kb
                           WHEN 1 
                           THEN
                    N'domc.pages_kb '
                           ELSE 
                    N'domc.single_pages_kb +
                    domc.multi_pages_kb '
                      END
                    + N'
               ) / 1024. / 1024. > 0.
            ORDER BY
                memory_used_gb DESC
        ) AS x
        OPTION(MAXDOP 1, RECOMPILE);
        ';
        
        EXEC sys.sp_executesql
            @pool_sql;
        
        IF 
        (
            SELECT 
                COUNT_BIG(*)
            FROM sys.all_columns AS ac 
            WHERE ac.object_id = OBJECT_ID(N'sys.dm_exec_query_memory_grants')
            AND   ac.name IN (N'reserved_worker_count', N'used_worker_count') 
        ) = 2
        BEGIN
            SET @helpful_new_columns = 1;
        END;    
        
        SET @mem_sql += N'
        SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

        SELECT 
            deqmg.session_id,
            database_name = 
                DB_NAME(deqp.dbid),
            deqmg.request_time,
            deqmg.grant_time,
            requested_memory_mb = 
                (deqmg.requested_memory_kb / 1024.),
            granted_memory_mb = 
                (deqmg.granted_memory_kb / 1024.),
            ideal_memory_mb = 
                (deqmg.ideal_memory_kb / 1024.),        
            required_memory_mb = 
                (deqmg.required_memory_kb / 1024.),
            used_memory_mb = 
                (deqmg.used_memory_kb / 1024.),
            max_used_memory_mb = 
                (deqmg.max_used_memory_kb / 1024.),
            deqmg.queue_id,
            deqmg.wait_order,
            deqmg.is_next_candidate,
            wait_time_s = 
                (deqmg.wait_time_ms / 1000.),
            wait_duration_s = 
                (waits.wait_duration_ms / 1000.),
            deqmg.dop,
            waits.wait_type,'
            + CASE 
                  WHEN @helpful_new_columns = 1
                  THEN N'
            deqmg.reserved_worker_count,
            deqmg.used_worker_count,'
                  ELSE N''
              END
            + CASE 
                  WHEN @skip_plan_xml = 0
                  THEN N'
            deqp.query_plan,'
                  ELSE N''
              END
            + N'
            deqmg.plan_handle
        FROM sys.dm_exec_query_memory_grants AS deqmg
        OUTER APPLY 
        (
            SELECT TOP (1) 
                dowt.*
            FROM sys.dm_os_waiting_tasks AS dowt
            WHERE dowt.session_id = deqmg.session_id
            ORDER BY dowt.session_id 
        ) AS waits
        OUTER APPLY sys.dm_exec_query_plan(deqmg.plan_handle) AS deqp
        WHERE deqmg.session_id <> @@SPID
        ORDER BY deqmg.request_time
        OPTION(MAXDOP 1, RECOMPILE);
        ';

        EXEC sys.sp_executesql @mem_sql;
        
        /*Resource semaphore info*/
        SELECT  
            deqrs.resource_semaphore_id,
            target_memory_mb = 
                (deqrs.target_memory_kb / 1024.),
            max_target_memory_mb =
                (deqrs.max_target_memory_kb / 1024.),
            total_memory_mb = 
                (deqrs.total_memory_kb / 1024.),
            available_memory_mb = 
                (deqrs.available_memory_kb / 1024.),
            granted_memory_mb = 
                (deqrs.granted_memory_kb / 1024.),
            used_memory_mb = 
                (deqrs.used_memory_kb / 1024.),
            deqrs.grantee_count,
            deqrs.waiter_count,
            deqrs.timeout_error_count,
            deqrs.forced_grant_count,
            deqrs.pool_id
        FROM sys.dm_exec_query_resource_semaphores AS deqrs
        WHERE deqrs.resource_semaphore_id = 0
        AND   deqrs.pool_id > 1
        OPTION(MAXDOP 1, RECOMPILE);
    END;

    IF @what_to_check IN (N'cpu', N'both')
    BEGIN
        /*Thread usage*/
        SELECT
            total_threads = 
                MAX(osi.max_workers_count),
            used_threads = 
                SUM(dos.active_workers_count),
            available_threads = 
                MAX(osi.max_workers_count) - SUM(dos.active_workers_count),
            threads_waiting_for_cpu = 
                SUM(dos.runnable_tasks_count),
            requests_waiting_for_threads = 
                SUM(dos.work_queue_count),
            current_workers = 
                SUM(dos.current_workers_count),
            high_runnable_percent = 
                MAX(ISNULL(r.high_runnable_percent, 0))
        FROM sys.dm_os_schedulers AS dos
        CROSS JOIN sys.dm_os_sys_info AS osi
        OUTER APPLY 
        (
            SELECT
                ''
                + RTRIM(y.runnable_pct)
                + '% of your queries are waiting to get on a CPU. ' AS high_runnable_percent
            FROM
            (
                SELECT
                    x.total, 
                    x.runnable,
                    runnable_pct = 
                        CONVERT
                        (
                            decimal(9,2),
                            (
                                x.runnable / 
                                    (1. * NULLIF(x.total, 0))
                            )
                        ) * 100.
                FROM 
                (
                    SELECT
                        total = 
                            COUNT_BIG(*), 
                        runnable = 
                            SUM
                            (
                                CASE 
                                    WHEN r.status = N'runnable' 
                                    THEN 1 
                                    ELSE 0 
                                END
                            )
                    FROM sys.dm_exec_requests AS r
                    WHERE r.session_id > 50
                ) AS x
            ) AS y
            WHERE y.runnable_pct > 20.
        ) AS r
        WHERE dos.status = N'VISIBLE ONLINE'
        OPTION(MAXDOP 1, RECOMPILE);
        
        
        /*Any threadpool waits*/
        SELECT 
            dowt.session_id,
            dowt.wait_duration_ms,
            dowt.wait_type
        FROM sys.dm_os_waiting_tasks AS dowt
        WHERE dowt.wait_type = N'THREADPOOL'
        ORDER BY dowt.wait_duration_ms DESC
        OPTION(MAXDOP 1, RECOMPILE);
        
        
        /*Figure out who's using a lot of CPU*/    
        IF 
        (
            SELECT 
                COUNT_BIG(*)
            FROM sys.all_columns AS ac 
            WHERE ac.object_id = OBJECT_ID(N'sys.dm_exec_requests')
            AND ac.name IN (N'dop', N'parallel_worker_count') 
        ) = 2
        BEGIN
            SET @cool_new_columns = 1;
        END;
        
        SET @cpu_sql += N'
        SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
        
        SELECT 
            der.session_id,
            database_name = 
                DB_NAME(der.database_id),
            der.start_time,
            query_text =
                SUBSTRING
                (
                    dest.text, 
                    (der.statement_start_offset / 2) + 1,
                    (
                        (
                            CASE der.statement_end_offset 
                                WHEN -1 
                                THEN DATALENGTH(dest.text) 
                                ELSE der.statement_end_offset 
                            END
                            - der.statement_start_offset 
                        ) / 2 
                    ) + 1
                ),
            statement_start_offset = 
                (der.statement_start_offset / 2) + 1,
            statement_end_offset = 
                (
                    (
                        CASE der.statement_end_offset 
                            WHEN -1 
                            THEN DATALENGTH(dest.text) 
                            ELSE der.statement_end_offset 
                        END 
                        - der.statement_start_offset 
                    ) / 2 
                ) + 1,'
            + CASE 
                  WHEN @skip_plan_xml = 0
                  THEN N'
            deqp.query_plan,'
                  ELSE N''
              END
            + N'
            der.plan_handle,
            der.status,
            der.blocking_session_id,
            der.wait_type,
            der.wait_time,
            der.wait_resource,
            der.cpu_time,
            der.total_elapsed_time,
            der.reads,
            der.writes,
            der.logical_reads,
            transaction_isolation_level = 
                CASE 
                    WHEN der.transaction_isolation_level = 0 
                    THEN ''Unspecified''
                    WHEN der.transaction_isolation_level = 1 
                    THEN ''Read Uncommitted''
                    WHEN der.transaction_isolation_level = 2 
                    AND  EXISTS 
                         (
                             SELECT 
                                 1/0 
                             FROM sys.dm_tran_active_snapshot_database_transactions AS trn 
                             WHERE der.session_id = trn.session_id 
                             AND   trn.is_snapshot = 0 
                         ) 
                    THEN ''Read Committed Snapshot Isolation''
                    WHEN der.transaction_isolation_level = 2 
                    AND  NOT EXISTS 
                             (
                                 SELECT 
                                     1/0 
                                 FROM sys.dm_tran_active_snapshot_database_transactions AS trn 
                                 WHERE der.session_id = trn.session_id 
                                 AND   trn.is_snapshot = 0 
                             ) 
                    THEN ''Read Committed''
                    WHEN der.transaction_isolation_level = 3 
                    THEN ''Repeatable Read''
                    WHEN der.transaction_isolation_level = 4 
                    THEN ''Serializable''
                    WHEN der.transaction_isolation_level = 5 
                    THEN ''Snapshot''
                    ELSE ''???''
                END,
            der.granted_query_memory'
            + CASE 
                  WHEN @cool_new_columns = 1
                  THEN N',
            der.dop,
            der.parallel_worker_count'
                  ELSE N''
              END
            + N'
        FROM sys.dm_exec_requests AS der
        CROSS APPLY sys.dm_exec_sql_text(der.plan_handle) AS dest
        CROSS APPLY sys.dm_exec_query_plan(der.plan_handle) AS deqp
        WHERE der.session_id <> @@SPID
        AND   der.session_id >= 50
        ORDER BY ' 
        + CASE 
              WHEN @cool_new_columns = 1
              THEN N'
        der.parallel_worker_count DESC
        OPTION(MAXDOP 1, RECOMPILE);'
              ELSE N'
        der.cpu_time DESC
        OPTION(MAXDOP 1, RECOMPILE);'
          END;
        
        EXEC sys.sp_executesql @cpu_sql;
    END;
END;