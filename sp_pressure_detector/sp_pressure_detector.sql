CREATE OR ALTER PROCEDURE dbo.sp_pressure_detector
AS 
BEGIN
SET NOCOUNT, XACT_ABORT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

/*
        Copyright (c) 2020 Erik Darling Data 
  
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
    IF ( SELECT c.value_in_use
         FROM sys.configurations AS c
         WHERE c.name = N'remote admin connections' ) = 0
    BEGIN
        SELECT 'This works a lot better on a troublesome server with the DAC enabled' AS message,
    	       'EXEC sp_configure ''remote admin connections'', 1; RECONFIGURE;' AS command_to_run,
    	       'https://bit.ly/RemoteDAC' AS how_to_use_the_dac;
    END
    
    /*
    See if someone else is using the DAC.
    Return some helpful information if they are.
    */
    IF EXISTS ( SELECT 1/0
                FROM sys.endpoints AS ep
                JOIN sys.dm_exec_sessions AS ses
                    ON ep.endpoint_id = ses.endpoint_id
                WHERE ep.name = N'Dedicated Admin Connection'
                AND   ses.session_id <> @@SPID )
    BEGIN
        SELECT 'who stole the dac?' AS dac_thief,
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
        WHERE ep.name = 'Dedicated Admin Connection'
        AND   ses.session_id <> @@SPID;
    END


    /*Memory Grant info*/
    SELECT      deqmg.session_id,
                deqmg.request_time,
                deqmg.grant_time,
                (deqmg.requested_memory_kb / 1024.) requested_memory_mb,
                (deqmg.granted_memory_kb / 1024.) granted_memory_mb,
                (deqmg.ideal_memory_kb / 1024.) ideal_memory_mb,		
                (deqmg.required_memory_kb / 1024.) required_memory_mb,
                (deqmg.used_memory_kb / 1024.) used_memory_mb,
                (deqmg.max_used_memory_kb / 1024.) max_used_memory_mb,
                deqmg.queue_id,
                deqmg.wait_order,
                deqmg.is_next_candidate,
                (deqmg.wait_time_ms / 1000.) wait_time_s,
                (waits.wait_duration_ms / 1000.) wait_duration_s,
                deqmg.dop,
                waits.wait_type,
                deqmg.reserved_worker_count,
                deqmg.used_worker_count,
		deqp.query_plan
    FROM        sys.dm_exec_query_memory_grants AS deqmg
    OUTER APPLY ( SELECT   TOP (1) *
                  FROM     sys.dm_os_waiting_tasks AS dowt
                  WHERE    dowt.session_id = deqmg.session_id
                  ORDER BY dowt.session_id ) AS waits
    OUTER APPLY sys.dm_exec_query_plan(deqmg.plan_handle) AS deqp
    WHERE deqmg.session_id <> @@SPID
    ORDER BY deqmg.request_time
    OPTION(MAXDOP 1);
    
    
    /*Resource semaphore info*/
    SELECT  deqrs.resource_semaphore_id,
            (deqrs.target_memory_kb / 1024.) target_memory_mb,
            (deqrs.max_target_memory_kb / 1024.) max_target_memory_mb,
            (deqrs.total_memory_kb / 1024.) total_memory_mb,
            (deqrs.available_memory_kb / 1024.) available_memory_mb,
            (deqrs.granted_memory_kb / 1024.) granted_memory_mb,
            (deqrs.used_memory_kb / 1024.) used_memory_mb,
            deqrs.grantee_count,
            deqrs.waiter_count,
            deqrs.timeout_error_count,
            deqrs.forced_grant_count,
            deqrs.pool_id
    FROM sys.dm_exec_query_resource_semaphores AS deqrs
    WHERE deqrs.resource_semaphore_id = 0
    AND   deqrs.pool_id = 2
    OPTION(MAXDOP 1);


    /*Thread usage*/
    SELECT     MAX(osi.max_workers_count) AS total_threads,
               SUM(dos.active_workers_count) AS used_threads,
               MAX(osi.max_workers_count) - SUM(dos.active_workers_count) AS available_threads,
               SUM(dos.runnable_tasks_count) AS threads_waiting_for_cpu,
               SUM(dos.work_queue_count) AS requests_waiting_for_threads,
               SUM(dos.current_workers_count) AS current_workers
    FROM       sys.dm_os_schedulers AS dos
    CROSS JOIN sys.dm_os_sys_info AS osi
    WHERE      dos.status = N'VISIBLE ONLINE'
    OPTION(MAXDOP 1);

	
    /*Any threadpool waits*/
    SELECT dowt.session_id,
           dowt.wait_duration_ms,
           dowt.wait_type
    FROM sys.dm_os_waiting_tasks AS dowt
    WHERE dowt.wait_type = N'THREADPOOL'
    ORDER BY dowt.wait_duration_ms DESC
    OPTION(MAXDOP 1);


    /*Figure out who's using a lot of CPU*/
    DECLARE @sql NVARCHAR(MAX) = N''
    DECLARE @cool_new_columns BIT = 0;
    
    IF ( SELECT COUNT(*)
    	 FROM sys.all_columns AS ac 
    	 WHERE OBJECT_NAME(ac.object_id) = N'dm_exec_requests'
    	 AND ac.name IN (N'dop', N'parallel_worker_count') ) = 2
    BEGIN
        SET @cool_new_columns = 1;
    END
    
    SET @sql += N'
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
    
    SELECT der.session_id,
           DB_NAME(der.database_id) AS database_name,
           der.start_time,
    	   SUBSTRING(
                    dest.text, ( der.statement_start_offset / 2 ) + 1,
                    (( CASE der.statement_end_offset WHEN -1 THEN DATALENGTH(dest.text) ELSE der.statement_end_offset END
                       - der.statement_start_offset ) / 2 ) + 1) AS query_text,
	   deqp.query_plan,
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
           CASE 
    	       WHEN der.transaction_isolation_level = 0 THEN ''Unspecified''
    	       WHEN der.transaction_isolation_level = 1 THEN ''Read Uncommitted''
    	       WHEN der.transaction_isolation_level = 2 AND EXISTS ( SELECT 1/0 FROM sys.dm_tran_active_snapshot_database_transactions AS trn WHERE der.session_id = trn.session_id AND is_snapshot = 0 ) THEN ''Read Committed Snapshot Isolation''
    	       WHEN der.transaction_isolation_level = 2 AND NOT EXISTS ( SELECT 1/0 FROM sys.dm_tran_active_snapshot_database_transactions AS trn WHERE der.session_id = trn.session_id AND is_snapshot = 0 ) THEN ''Read Committed''
    	       WHEN der.transaction_isolation_level = 3 THEN ''Repeatable Read''
    	       WHEN der.transaction_isolation_level = 4 THEN ''Serializable''
    	       WHEN der.transaction_isolation_level = 5 THEN ''Snapshot''
    	       ELSE ''???''
    	   END AS transaction_isolation_level ,
           der.granted_query_memory'
    	   + CASE WHEN @cool_new_columns = 1
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
    AND der.session_id >= 50
    ORDER BY ' + CASE WHEN @cool_new_columns = 1
    		      THEN N'der.parallel_worker_count DESC
    			     OPTION(MAXDOP 1);'
    	              ELSE N'der.cpu_time DESC
    			     OPTION(MAXDOP 1);'
    		 END
    
    EXEC sys.sp_executesql @sql;

END;
