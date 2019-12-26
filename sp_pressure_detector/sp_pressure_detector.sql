USE master;
GO


CREATE OR ALTER PROCEDURE dbo.sp_pressure_detector
AS 
BEGIN
SET NOCOUNT, XACT_ABORT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

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
    		'http://bit.ly/RemoteDAC' AS how_to_use_the_dac;
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
                (deqmg.required_memory_kb / 1024.) required_memory_mb,
                (deqmg.used_memory_kb / 1024.) used_memory_mb,
                (deqmg.max_used_memory_kb / 1024.) max_used_memory_mb,
                deqmg.queue_id,
                deqmg.wait_order,
                deqmg.is_next_candidate,
                (deqmg.wait_time_ms / 1000.) wait_time_s,
                (deqmg.ideal_memory_kb / 1024.) ideal_memory_mb,
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

END;
