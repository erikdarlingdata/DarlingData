SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

/*

██████╗ ██████╗ ███████╗███████╗███████╗██╗   ██╗██████╗ ███████╗
██╔══██╗██╔══██╗██╔════╝██╔════╝██╔════╝██║   ██║██╔══██╗██╔════╝
██████╔╝██████╔╝█████╗  ███████╗███████╗██║   ██║██████╔╝█████╗
██╔═══╝ ██╔══██╗██╔══╝  ╚════██║╚════██║██║   ██║██╔══██╗██╔══╝
██║     ██║  ██║███████╗███████║███████║╚██████╔╝██║  ██║███████╗
╚═╝     ╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝

██████╗ ███████╗████████╗███████╗ ██████╗████████╗ ██████╗ ██████╗
██╔══██╗██╔════╝╚══██╔══╝██╔════╝██╔════╝╚══██╔══╝██╔═══██╗██╔══██╗
██║  ██║█████╗     ██║   █████╗  ██║        ██║   ██║   ██║██████╔╝
██║  ██║██╔══╝     ██║   ██╔══╝  ██║        ██║   ██║   ██║██╔══██╗
██████╔╝███████╗   ██║   ███████╗╚██████╗   ██║   ╚██████╔╝██║  ██║
╚═════╝ ╚══════╝   ╚═╝   ╚══════╝ ╚═════╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝

Copyright 2022 Darling Data, LLC
https://www.erikdarlingdata.com/

For usage and licensing details, run:
EXEC sp_PressureDetector
    @help = 1;

For working through errors:
EXEC sp_PressureDetector
    @debug = 1;

For support, head over to GitHub:
https://github.com/erikdarlingdata/DarlingData

*/


IF OBJECT_ID('dbo.sp_PressureDetector') IS NULL
    EXEC ('CREATE PROCEDURE dbo.sp_PressureDetector AS RETURN 138;');
GO

ALTER PROCEDURE
    dbo.sp_PressureDetector
(
    @what_to_check nvarchar(6) = N'both',
    @skip_plan_xml bit = 0,
    @help bit = 0,
    @debug bit = 0,
    @version varchar(5) = NULL OUTPUT,
    @version_date datetime = NULL OUTPUT
)
WITH RECOMPILE
AS
BEGIN

SET STATISTICS XML OFF;
SET NOCOUNT, XACT_ABORT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

SELECT
    @version = '2.80',
    @version_date = '20221201';


IF @help = 1
BEGIN

    /*
    Introduction
    */
    SELECT
        introduction =
           'hi, i''m sp_PressureDetector!' UNION ALL
    SELECT 'you got me from https://www.erikdarlingdata.com/sp_pressuredetector/' UNION ALL
    SELECT 'i''m a lightweight tool for monitoring cpu and memory pressure' UNION ALL
    SELECT 'i''ll tell you: ' UNION ALL
    SELECT ' * what''s currently consuming memory on your server' UNION ALL
    SELECT ' * wait stats relevant to cpu, memory, and disk' UNION ALL
    SELECT ' * how many worker threads and how much memory you have available' UNION ALL
    SELECT ' * running queries that are using cpu and memory';

    /*
    Parameters
    */
    SELECT
        parameter_name =
            ap.name,
        data_type = t.name,
        description =
            CASE
                ap.name
                WHEN '@what_to_check' THEN 'areas to check for pressure'
                WHEN '@skip_plan_xml' THEN 'if you want to skip getting plan XML'
                WHEN '@version' THEN 'OUTPUT; for support'
                WHEN '@version_date' THEN 'OUTPUT; for support'
                WHEN '@help' THEN 'how you got here'
                WHEN '@debug' THEN 'prints dynamic sql'
            END,
        valid_inputs =
            CASE
                ap.name
                WHEN '@what_to_check' THEN '"both", "cpu", and "memory"'
                WHEN '@skip_plan_xml' THEN '0 or 1'
                WHEN '@version' THEN 'none'
                WHEN '@version_date' THEN 'none'
                WHEN '@help' THEN '0 or 1'
                WHEN '@debug' THEN '0 or 1'
            END,
        defaults =
            CASE
                ap.name
                WHEN '@what_to_check' THEN 'both'
                WHEN '@skip_plan_xml' THEN '1'
                WHEN '@version' THEN 'none; OUTPUT'
                WHEN '@version_date' THEN 'none; OUTPUT'
                WHEN '@help' THEN '0'
                WHEN '@debug' THEN '0'
            END
    FROM sys.all_parameters AS ap
    INNER JOIN sys.all_objects AS o
      ON ap.object_id = o.object_id
    INNER JOIN sys.types AS t
      ON  ap.system_type_id = t.system_type_id
      AND ap.user_type_id = t.user_type_id
    WHERE o.name = N'sp_PressureDetector'
    OPTION(MAXDOP 1, RECOMPILE);

    SELECT
        mit_license_yo =
           'i am MIT licensed, so like, do whatever' UNION ALL
    SELECT 'see printed messages for full license';

    RAISERROR('
MIT License

Copyright 2022 Darling Data, LLC

https://www.erikdarlingdata.com/

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"),
to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute,
sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the
following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE
FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
', 0, 1) WITH NOWAIT;

    RETURN;

END;

    /*
    Declarations of Variablependence
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
        @pages_kb bit =
            CASE
                WHEN
                (
                    SELECT
                        COUNT_BIG(*)
                    FROM sys.all_columns AS ac
                    WHERE ac.object_id = OBJECT_ID(N'sys.dm_os_memory_clerks')
                    AND   ac.name = N'pages_kb'
                ) = 1
                THEN 1
                ELSE 0
            END,
        @mem_sql nvarchar(MAX) = N'',
        @helpful_new_columns bit =
            CASE
                WHEN
                (
                    SELECT
                        COUNT_BIG(*)
                    FROM sys.all_columns AS ac
                    WHERE ac.object_id = OBJECT_ID(N'sys.dm_exec_query_memory_grants')
                    AND   ac.name IN
                          (
                              N'reserved_worker_count',
                              N'used_worker_count'
                          )
                ) = 2
                THEN 1
                ELSE 0
            END,
        @cpu_sql nvarchar(MAX) = N'',
        @cool_new_columns bit =
            CASE
                WHEN
                (
                    SELECT
                        COUNT_BIG(*)
                    FROM sys.all_columns AS ac
                    WHERE ac.object_id = OBJECT_ID(N'sys.dm_exec_requests')
                    AND ac.name IN
                        (
                            N'dop',
                            N'parallel_worker_count'
                        )
                ) = 2
                THEN 1
                ELSE 0
            END,
        @reserved_worker_count_out nvarchar(10) = N'0',
        @reserved_worker_count nvarchar(MAX) = N'
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

SELECT
    @reserved_worker_count_out =
        SUM(deqmg.reserved_worker_count)
FROM sys.dm_exec_query_memory_grants AS deqmg
OPTION(MAXDOP 1, RECOMPILE);
            ',
        @cpu_details nvarchar(MAX) = N'',
        @cpu_details_output xml = N'',
        @cpu_details_columns nvarchar(MAX) = N'',
        @cpu_details_select nvarchar(MAX) = N'
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

SELECT
    @cpu_details_output =
        (
            SELECT
                offline_cpus =
                    (SELECT COUNT_BIG(*) FROM sys.dm_os_schedulers dos WHERE dos.is_online = 0),
        ',
        @cpu_details_from nvarchar(MAX) = N'
            FROM sys.dm_os_sys_info AS osi
            FOR XML
                PATH(''cpu_details''),
                TYPE
        )
OPTION(MAXDOP 1, RECOMPILE);',
        @database_size_out nvarchar(MAX) = N'',
        @database_size_out_gb nvarchar(10) = N'0',
        @total_physical_memory_gb bigint,
        @cpu_utilization xml = N'',
        @low_memory xml = N'';

    /*
    Check to see if the DAC is enabled.
    If it's not, give people some helpful information.
    */
    IF
    (
        SELECT
            c.value_in_use
        FROM sys.configurations AS c
        WHERE c.name = N'remote admin connections'
    ) = 0
    BEGIN
        SELECT
            message =
                'This works a lot better on a troublesome server with the DAC enabled',
            command_to_run =
                'EXEC sp_configure ''remote admin connections'', 1; RECONFIGURE;',
            how_to_use_the_dac =
                'https://bit.ly/RemoteDAC';
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

    /*
    Look at wait stats related to CPU memory, disk, and query performance
    */
    SELECT
        hours_uptime =
            (
                SELECT
                    DATEDIFF
                    (
                        HOUR,
                        osi.sqlserver_start_time,
                        SYSDATETIME()
                    )
                FROM sys.dm_os_sys_info AS osi
            ),
        dows.wait_type,
        description =
            CASE
                WHEN dows.wait_type = N'PAGEIOLATCH_SH'
                THEN N'Selects reading pages from disk into memory'
                WHEN dows.wait_type = N'PAGEIOLATCH_EX'
                THEN N'Modifications reading pages from disk into memory'
                WHEN dows.wait_type = N'RESOURCE_SEMAPHORE'
                THEN N'Queries waiting to get memory to run'
                WHEN dows.wait_type = N'RESOURCE_SEMAPHORE_QUERY_COMPILE'
                THEN N'Queries waiting to get memory to compile'
                WHEN dows.wait_type = N'CXPACKET'
                THEN N'Query parallelism'
                WHEN dows.wait_type = N'CXCONSUMER'
                THEN N'Query parallelism'
                WHEN dows.wait_type = N'CXSYNC_PORT'
                THEN N'Query parallelism'
                WHEN dows.wait_type = N'CXSYNC_CONSUMER'
                THEN N'Query parallelism'
                WHEN dows.wait_type = N'SOS_SCHEDULER_YIELD'
                THEN N'Query scheduling'
                WHEN dows.wait_type = N'THREADPOOL'
                THEN N'Worker thread exhaustion'
                WHEN dows.wait_type = N'CMEMTHREAD'
                THEN N'Tasks waiting on memory objects'
                WHEN dows.wait_type = N'PAGELATCH_EX'
                THEN N'Potential tempdb contention'
                WHEN dows.wait_type = N'PAGELATCH_SH'
                THEN N'Potential tempdb contention'
                WHEN dows.wait_type = N'PAGELATCH_UP'
                THEN N'Potential tempdb contention'
                WHEN dows.wait_type LIKE N'LCK%'
                THEN N'Queries being blocked'
            END,
        hours_wait_time =
            CONVERT
            (
                numeric(38, 9),
                dows.wait_time_ms /
                    (1000. * 60. * 60.)
            ),
        hours_signal_wait_time =
            CONVERT
            (
                numeric(38, 9),
                dows.signal_wait_time_ms /
                    (1000. * 60. * 60.)
            ),
        waiting_tasks_count =
            REPLACE
            (
                CONVERT
                (
                    nvarchar(30),
                    CONVERT
                    (
                        money,
                        dows.waiting_tasks_count
                    ),
                    1
                ),
            N'.00',
            N''
            ),
        avg_ms_per_wait =
            ISNULL
            (
               CONVERT
               (
                   numeric(38, 9),
                   dows.wait_time_ms /
                       NULLIF
                       (
                           1. *
                           dows.waiting_tasks_count,
                           0.
                       )
                ),
                0.
            )
    FROM sys.dm_os_wait_stats AS dows
    WHERE dows.waiting_tasks_count > 0
    AND
    (
        dows.wait_type IN
             (
                 /*Disk*/
                 N'PAGEIOLATCH_SH', --Selects reading pages from disk into memory
                 N'PAGEIOLATCH_EX', --Modifications reading pages from disk into memory
                 /*Memory*/
                 N'RESOURCE_SEMAPHORE', --Queries waiting to get memory to run
                 N'RESOURCE_SEMAPHORE_QUERY_COMPILE', --Queries waiting to get memory to compile
                 N'CMEMTHREAD', --Tasks waiting on memory objects
                 /*Parallelism*/
                 N'CXPACKET', --Parallelism
                 N'CXCONSUMER', --Parallelism
                 N'CXSYNC_PORT', --Parallelism
                 N'CXSYNC_CONSUMER', --Parallelism
                 /*CPU*/
                 N'SOS_SCHEDULER_YIELD', --Query scheduling
                 N'THREADPOOL', --Worker thread exhaustion
                 /*tempdb (potentially)*/
                 N'PAGELATCH_EX', --Potential contention
                 N'PAGELATCH_SH', --Potential contention
                 N'PAGELATCH_UP' --Potential contention
             )
        OR dows.wait_type LIKE N'LCK%' --Locking
    )
    ORDER BY
        dows.wait_time_ms DESC
    OPTION(MAXDOP 1, RECOMPILE);

    IF @azure = 0
    BEGIN
        SELECT
            tempdb_info =
                (
                    SELECT
                        tempdb_configuration =
                            (
                                SELECT
                                    total_data_files =
                                        COUNT_BIG(*),
                                    min_size_mb =
                                        MIN(mf.size * 8) / 1024,
                                    max_size_mb =
                                        MAX(mf.size * 8) / 1024,
                                    min_growth_increment_mb =
                                        MIN(mf.growth * 8) / 1024,
                                    max_growth_increment_mb =
                                        MAX(mf.growth * 8) / 1024,
                                    scheduler_total_count =
                                        (
                                            SELECT
                                                i.scheduler_total_count
                                            FROM sys.dm_os_sys_info AS i
                                        )
                                FROM sys.master_files AS mf
                                WHERE mf.database_id = 2
                                AND   mf.type = 0
                                FOR XML
                                    PATH('tempdb_configuration'),
                                    TYPE
                            ),
                        tempdb_space_used =
                            (
                                SELECT
                                    free_space_mb =
                                        SUM(d.unallocated_extent_page_count * 8) / 1024,
                                    user_objects_mb =
                                        SUM(d.user_object_reserved_page_count * 8) / 1024,
                                    version_store_mb =
                                        SUM(d.version_store_reserved_page_count * 8) / 1024,
                                    internal_objects_mb =
                                        SUM(d.internal_object_reserved_page_count * 8) / 1024
                                FROM tempdb.sys.dm_db_file_space_usage AS d
                                WHERE d.database_id = 2
                                FOR XML
                                    PATH('tempdb_space_used'),
                                    TYPE
                            ),
                        tempdb_query_activity =
                            (
                                SELECT
                                    t.session_id,
                                    tempdb_allocations_mb =
                                        SUM(t.tempdb_allocations * 8) / 1024,
                                    tempdb_current_mb =
                                        SUM(t.tempdb_current * 8) / 1024
                                FROM
                                (
                                    SELECT
                                        t.session_id,
                                        tempdb_allocations =
                                            t.user_objects_alloc_page_count +
                                            t.internal_objects_alloc_page_count,
                                        tempdb_current =
                                            t.user_objects_alloc_page_count +
                                            t.internal_objects_alloc_page_count -
                                            t.user_objects_dealloc_page_count -
                                            t.internal_objects_dealloc_page_count
                                    FROM sys.dm_db_task_space_usage AS t

                                    UNION ALL

                                    SELECT
                                        s.session_id,
                                        tempdb_allocations =
                                            s.user_objects_alloc_page_count +
                                            s.internal_objects_alloc_page_count,
                                        tempdb_current =
                                            s.user_objects_alloc_page_count +
                                            s.internal_objects_alloc_page_count -
                                            s.user_objects_dealloc_page_count -
                                            s.internal_objects_dealloc_page_count
                                    FROM sys.dm_db_session_space_usage AS s
                                ) AS t
                                WHERE t.session_id > 50
                                GROUP BY
                                    t.session_id
                                HAVING
                                    (SUM(t.tempdb_allocations) * 8) / 1024 > 1
                                ORDER BY
                                    SUM(t.tempdb_allocations) DESC
                                FOR XML
                                    PATH('tempb_query_activity'),
                                    TYPE

                            )
                        FOR XML
                            PATH('tempdb'),
                            TYPE
                )
                OPTION(RECOMPILE, MAXDOP 1);
    END;

    /*Memory Grant info*/
    IF @what_to_check IN (N'both', N'memory')
    BEGIN

        /*
        See buffer pool size, along with stolen memory
        and top non-buffer pool consumers
        */
        SET @pool_sql += N'
        SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

        SELECT
            memory_source =
                N''Buffer Pool Memory'',
            memory_consumer =
                domc.type,
            memory_consumed_gb =
                CONVERT
                (
                    decimal(9, 2),
                    SUM
                    (
                        ' + CONVERT
                            (
                                nvarchar(MAX),
                          CASE @pages_kb
                               WHEN 1
                               THEN
                        N'domc.pages_kb + '
                               ELSE
                        N'domc.single_pages_kb +
                        domc.multi_pages_kb + '
                          END
                            )
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
            memory_source =
                N''Non-Buffer Pool Memory: Total'',
            memory_consumer =
                dopc.counter_name,
            memory_consumed_gb =
                CONVERT
                (
                    decimal(9, 2),
                    dopc.cntr_value / 1024. / 1024.
                )
        FROM sys.dm_os_performance_counters AS dopc
        WHERE dopc.counter_name LIKE N''Stolen Server%''

        UNION ALL

        SELECT
            memory_source =
                N''Non-Buffer Pool Memory: Top Five'',
            memory_consumer =
                x.type,
            memory_consumed_gb =
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
                        ' + CONVERT
                            (
                                nvarchar(MAX),
                          CASE @pages_kb
                               WHEN 1
                               THEN
                        N'    domc.pages_kb '
                               ELSE
                        N'    domc.single_pages_kb +
                            domc.multi_pages_kb '
                          END
                            )
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
                   ' + CONVERT
                       (
                           nvarchar(MAX),
                      CASE @pages_kb
                           WHEN 1
                           THEN
                    N'domc.pages_kb '
                           ELSE
                    N'domc.single_pages_kb +
                    domc.multi_pages_kb '
                      END
                       )
                    + N'
               ) / 1024. / 1024. > 0.
            ORDER BY
                memory_used_gb DESC
        ) AS x
        OPTION(MAXDOP 1, RECOMPILE);
        ';

        IF @debug = 1 BEGIN PRINT @pool_sql; END;

        EXEC sys.sp_executesql
            @pool_sql;

        /*
        Track down queries currently asking for memory grants
        */

        SET @mem_sql += N'
        SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

        SELECT
            deqmg.session_id,
            database_name =
                DB_NAME(deqp.dbid),
            [dd hh:mm:ss.mss] =
                RIGHT
                (
                    ''00'' +
                    CONVERT
                    (
                        varchar(10),
                        DATEDIFF
                        (
                            DAY,
                            deqmg.request_time,
                            SYSDATETIME()
                        )
                    ),
                    2
                ) +
                '' '' +
                CONVERT
                (
                    varchar(20),
                    DATEADD
                    (
                        MILLISECOND,
                        DATEDIFF
                        (
                            MILLISECOND,
                            deqmg.request_time,
                            SYSDATETIME()
                        ),
                        ''19000101''
                    ),
                    14
                ),
            query_text =
                (
                    SELECT
                        [processing-instruction(query)] =
                            SUBSTRING
                            (
                                REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                    dest.text COLLATE Latin1_General_BIN2,
                                NCHAR(31),N''?''),NCHAR(30),N''?''),NCHAR(29),N''?''),NCHAR(28),N''?''),NCHAR(27),N''?''),NCHAR(26),N''?''),NCHAR(25),N''?''),NCHAR(24),N''?''),NCHAR(23),N''?''),NCHAR(22),N''?''),
                                NCHAR(21),N''?''),NCHAR(20),N''?''),NCHAR(19),N''?''),NCHAR(18),N''?''),NCHAR(17),N''?''),NCHAR(16),N''?''),NCHAR(15),N''?''),NCHAR(14),N''?''),NCHAR(12),N''?''),
                                NCHAR(11),N''?''),NCHAR(8),N''?''),NCHAR(7),N''?''),NCHAR(6),N''?''),NCHAR(5),N''?''),NCHAR(4),N''?''),NCHAR(3),N''?''),NCHAR(2),N''?''),NCHAR(1),N''?''),NCHAR(0),N''''),
                                (der.statement_start_offset / 2) + 1,
                                (
                                    (
                                        CASE
                                            der.statement_end_offset
                                            WHEN -1
                                            THEN DATALENGTH(dest.text)
                                            ELSE der.statement_end_offset
                                        END
                                        - der.statement_start_offset
                                    ) / 2
                                ) + 1
                            )
                       FROM sys.dm_exec_requests AS der
                       WHERE der.session_id = deqmg.session_id
                            FOR XML
                                PATH(''''),
                                TYPE
                ),'
            + CONVERT
              (
                  nvarchar(MAX),
              CASE
                  WHEN @skip_plan_xml = 0
                  THEN N'
            deqp.query_plan,'
                  ELSE N''
              END
              ) + CONVERT
                  (
                      nvarchar(MAX),
                      N'
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
            wait_time_seconds =
                (deqmg.wait_time_ms / 1000.),
            waits.wait_type,
            wait_duration_seconds =
                (waits.wait_duration_ms / 1000.),
            deqmg.dop,'
                  )
            + CONVERT
              (
                  nvarchar(MAX),
                  CASE
                      WHEN @helpful_new_columns = 1
                      THEN N'
            deqmg.reserved_worker_count,
            deqmg.used_worker_count,'
                      ELSE N''
                  END
              ) + CONVERT
                  (
                      nvarchar(MAX),
                      N'
            deqmg.plan_handle
        FROM sys.dm_exec_query_memory_grants AS deqmg
        OUTER APPLY
        (
            SELECT TOP (1)
                dowt.*
            FROM sys.dm_os_waiting_tasks AS dowt
            WHERE dowt.session_id = deqmg.session_id
            ORDER BY dowt.wait_duration_ms DESC
        ) AS waits
        OUTER APPLY sys.dm_exec_query_plan(deqmg.plan_handle) AS deqp
        OUTER APPLY sys.dm_exec_sql_text(deqmg.plan_handle) AS dest

        WHERE deqmg.session_id <> @@SPID
        ORDER BY
            requested_memory_mb DESC,
            deqmg.request_time
        OPTION(MAXDOP 1, RECOMPILE);
        '
                  );

        IF @debug = 1 BEGIN PRINT @mem_sql; END;

        EXEC sys.sp_executesql
            @mem_sql;

        /*Resource semaphore info*/
        IF @azure = 1
        BEGIN
            SELECT
                @database_size_out = N'
                SELECT
                    @database_size_out_gb =
                        SUM(CONVERT(bigint, df.size)) * 8 / 1024 / 1024
                FROM sys.database_files AS df
                OPTION(MAXDOP 1, RECOMPILE);';
        END;
        IF @azure = 0
        BEGIN
            SELECT
                @database_size_out = N'
                SELECT
                    @database_size_out_gb =
                        SUM(CONVERT(bigint, mf.size)) * 8 / 1024 / 1024
                FROM sys.master_files AS mf
                WHERE mf.database_id > 4
                OPTION(MAXDOP 1, RECOMPILE);';
        END;

        EXEC sys.sp_executesql
            @database_size_out,
          N'@database_size_out_gb varchar(10) OUTPUT',
            @database_size_out_gb OUTPUT;

        IF @azure = 0
        BEGIN
            SELECT
                @total_physical_memory_gb =
                    CEILING(dosm.total_physical_memory_kb / 1024.)
                FROM sys.dm_os_sys_memory AS dosm;
        END;
        IF @azure = 1
        BEGIN
            SELECT
                @total_physical_memory_gb =
                    SUM(dosi.committed_target_kb) / 1024.
            FROM sys.dm_os_sys_info dosi;
        END;

        SELECT
            @low_memory =
                x.low_memory
        FROM
        (
            SELECT
                sample_time =
                    CONVERT
                    (
                        datetime,
                        DATEADD
                        (
                            SECOND,
                            (t.timestamp - inf.ms_ticks) / 1000,
                            SYSDATETIME()
                        )
                    ),
                notification_type =
                    t.record.value('(/Record/ResourceMonitor/Notification)[1]', 'varchar(50)'),
                indicators_process =
                    t.record.value('(/Record/ResourceMonitor/IndicatorsProcess)[1]', 'int'),
                indicators_system =
                    t.record.value('(/Record/ResourceMonitor/IndicatorsSystem)[1]', 'int'),
                physical_memory_availble_gb =
                    t.record.value('(/Record/MemoryRecord/AvailablePhysicalMemory)[1]', 'bigint') / 1024 / 1024,
                virtual_memory_availble_gb =
                    t.record.value('(/Record/MemoryRecord/AvailableVirtualAddressSpace)[1]', 'bigint') / 1024 / 1024
            FROM sys.dm_os_sys_info AS inf
            CROSS JOIN
            (
                SELECT
                    dorb.timestamp,
                    record =
                        CONVERT(xml, dorb.record)
                FROM sys.dm_os_ring_buffers AS dorb
                WHERE dorb.ring_buffer_type = N'RING_BUFFER_RESOURCE_MONITOR'
            ) AS t
            WHERE t.record.exist('(Record/ResourceMonitor/Notification[. = "RESOURCE_MEMPHYSICAL_LOW"])') = 1
            AND
              (
                  t.record.exist('(Record/ResourceMonitor/IndicatorsProcess[. > 0])') = 1
               OR t.record.exist('(Record/ResourceMonitor/IndicatorsSystem[. > 0])') = 1
              )
            ORDER BY
                sample_time DESC
            FOR XML
                PATH('memory'),
                TYPE
        ) AS x (low_memory)
        OPTION(MAXDOP 1, RECOMPILE);

        IF @low_memory IS NULL
        BEGIN
            SELECT
                @low_memory =
                (
                    SELECT
                        N'No RESOURCE_MEMPHYSICAL_LOW indicators detected'
                    FOR XML
                        PATH(N'memory'),
                        TYPE
                );
        END;

        SELECT
            low_memory =
               @low_memory

        SELECT
            deqrs.resource_semaphore_id,
            total_database_size_gb =
                @database_size_out_gb,
            total_physical_memory_mb =
                @total_physical_memory_gb,
            max_server_memory_mb =
                (
                    SELECT
                        CONVERT
                        (
                            bigint,
                            c.value_in_use
                        )
                    FROM sys.configurations AS c
                    WHERE c.name = N'max server memory (MB)'
                ),
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
        OPTION(MAXDOP 1, RECOMPILE);

    END;

    IF @what_to_check IN (N'cpu', N'both')
    BEGIN

        IF @helpful_new_columns = 1
        BEGIN
            IF @debug = 1 BEGIN PRINT @reserved_worker_count; END;

            EXEC sys.sp_executesql
                @reserved_worker_count,
              N'@reserved_worker_count_out nvarchar(10) OUTPUT',
                @reserved_worker_count_out OUTPUT;
        END;

            SELECT
                @cpu_details_columns += N'' +
                    CASE
                        WHEN ac.name = N'socket_count'
                        THEN N'                osi.socket_count, ' + NCHAR(10)
                        WHEN ac.name = N'numa_node_count'
                        THEN N'                osi.numa_node_count, ' + NCHAR(10)
                        WHEN ac.name = N'cpu_count'
                        THEN N'                osi.cpu_count, ' + NCHAR(10)
                        WHEN ac.name = N'cores_per_socket'
                        THEN N'                osi.cores_per_socket, ' + NCHAR(10)
                        WHEN ac.name = N'hyperthread_ratio'
                        THEN N'                osi.hyperthread_ratio, ' + NCHAR(10)
                        WHEN ac.name = N'softnuma_configuration_desc'
                        THEN N'                osi.softnuma_configuration_desc, ' + NCHAR(10)
                        ELSE N''
                    END
            FROM
            (
                SELECT
                    ac.name
                FROM sys.all_columns AS ac
                WHERE ac.object_id = OBJECT_ID('sys.dm_os_sys_info')
                AND   ac.name IN
                      (
                          N'socket_count',
                          N'numa_node_count',
                          N'cpu_count',
                          N'cores_per_socket',
                          N'hyperthread_ratio',
                          N'softnuma_configuration_desc'
                      )
            ) AS ac
            OPTION(MAXDOP 1, RECOMPILE);

            SELECT
                @cpu_details =
                    @cpu_details_select +
                    SUBSTRING
                    (
                        @cpu_details_columns,
                        1,
                        LEN(@cpu_details_columns) -3
                    ) +
                    @cpu_details_from;

            IF @debug = 1 BEGIN PRINT @cpu_details; END;

            EXEC sys.sp_executesql
                @cpu_details,
              N'@cpu_details_output xml OUTPUT',
                @cpu_details_output OUTPUT;

        SELECT
            @cpu_utilization =
                x.cpu_utilization
        FROM
        (
            SELECT
                sample_time =
                    CONVERT
                    (
                        datetime,
                        DATEADD
                        (
                            SECOND,
                            (t.timestamp - inf.ms_ticks) / 1000,
                            SYSDATETIME()
                        )
                    ),
                sqlserver_cpu_utilization =
                    t.record.value('(Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]','int'),
                other_process_cpu_utilization =
                    (100 - t.record.value('(Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]','int')
                     - t.record.value('(Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]','int')),
                total_cpu_utilization =
                    (100 - t.record.value('(Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int'))
            FROM sys.dm_os_sys_info AS inf
            CROSS JOIN
            (
                SELECT
                    dorb.timestamp,
                    record =
                        CONVERT(xml, dorb.record)
                FROM sys.dm_os_ring_buffers AS dorb
                WHERE dorb.ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR'
            ) AS t
            WHERE t.record.exist('(Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization[. > 0])') = 1
            ORDER BY
                sample_time DESC
            FOR XML
                PATH('cpu_utilization'),
                TYPE
        ) AS x (cpu_utilization)
        OPTION(MAXDOP 1, RECOMPILE);

        IF @cpu_utilization IS NULL
        BEGIN
            SELECT
                @cpu_utilization =
                (
                    SELECT
                        N'No signficant CPU usage data available.'
                    FOR XML
                        PATH(N'cpu_utilization'),
                        TYPE
                );
        END;

        /*Thread usage*/
        SELECT
            cpu_details_output =
                @cpu_details_output,
            cpu_utilization =
                @cpu_utilization,
            total_threads =
                MAX(osi.max_workers_count),
            used_threads =
                SUM(dos.active_workers_count),
            available_threads =
                MAX(osi.max_workers_count) - SUM(dos.active_workers_count),
            reserved_worker_count =
                CASE @helpful_new_columns
                     WHEN 1
                     THEN ISNULL
                          (
                              @reserved_worker_count_out,
                              N'0'
                          )
                     ELSE N'N/A'
                END,
            threads_waiting_for_cpu =
                SUM(dos.runnable_tasks_count),
            requests_waiting_for_threads =
                SUM(dos.work_queue_count),
            current_workers =
                SUM(dos.current_workers_count),
            avg_runnable_tasks_count =
                AVG(dos.runnable_tasks_count),
            high_runnable_percent =
                MAX(ISNULL(r.high_runnable_percent, 0))
        FROM sys.dm_os_schedulers AS dos
        CROSS JOIN sys.dm_os_sys_info AS osi
        OUTER APPLY
        (
            SELECT
                high_runnable_percent =
                    '' +
                    RTRIM(y.runnable_pct) +
                    '% of your queries are waiting to get on a CPU.'
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
            WHERE y.runnable_pct > 25.
            AND   y.total > 10
        ) AS r
        WHERE dos.status = N'VISIBLE ONLINE'
        OPTION(MAXDOP 1, RECOMPILE);


        /*Any current threadpool waits?*/
        SELECT
            dowt.session_id,
            dowt.wait_duration_ms,
            dowt.wait_type
        FROM sys.dm_os_waiting_tasks AS dowt
        WHERE dowt.wait_type = N'THREADPOOL'
        ORDER BY
            dowt.wait_duration_ms DESC
        OPTION(MAXDOP 1, RECOMPILE);


        /*Figure out who's using a lot of CPU*/

        SET @cpu_sql += N'
        SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

        SELECT
            der.session_id,
            database_name =
                DB_NAME(der.database_id),
            [dd hh:mm:ss.mss] =
                RIGHT
                (
                    ''00'' +
                    CONVERT
                    (
                        varchar(10),
                        DATEDIFF
                        (
                            DAY,
                            der.start_time,
                            SYSDATETIME()
                        )
                    ),
                    2
                ) +
                '' '' +
                CONVERT
                (
                    varchar(20),
                    DATEADD
                    (
                        MILLISECOND,
                        DATEDIFF
                        (
                            MILLISECOND,
                            der.start_time,
                            SYSDATETIME()
                        ),
                        ''19000101''
                    ),
                    14
                ),
            query_text =
                (
                    SELECT
                        [processing-instruction(query)] =
                            SUBSTRING
                            (
                                REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                    dest.text COLLATE Latin1_General_BIN2,
                                NCHAR(31),N''?''),NCHAR(30),N''?''),NCHAR(29),N''?''),NCHAR(28),N''?''),NCHAR(27),N''?''),NCHAR(26),N''?''),NCHAR(25),N''?''),NCHAR(24),N''?''),NCHAR(23),N''?''),NCHAR(22),N''?''),
                                NCHAR(21),N''?''),NCHAR(20),N''?''),NCHAR(19),N''?''),NCHAR(18),N''?''),NCHAR(17),N''?''),NCHAR(16),N''?''),NCHAR(15),N''?''),NCHAR(14),N''?''),NCHAR(12),N''?''),
                                NCHAR(11),N''?''),NCHAR(8),N''?''),NCHAR(7),N''?''),NCHAR(6),N''?''),NCHAR(5),N''?''),NCHAR(4),N''?''),NCHAR(3),N''?''),NCHAR(2),N''?''),NCHAR(1),N''?''),NCHAR(0),N''''),
                                (der.statement_start_offset / 2) + 1,
                                (
                                    (
                                        CASE
                                            der.statement_end_offset
                                            WHEN -1
                                            THEN DATALENGTH(dest.text)
                                            ELSE der.statement_end_offset
                                        END
                                        - der.statement_start_offset
                                    ) / 2
                                ) + 1
                            )
                            FOR XML PATH(''''),
                            TYPE
                ),'
            + CASE
                  WHEN @skip_plan_xml = 0
                  THEN CONVERT
                       (
                           nvarchar(MAX),
                           N'
            deqp.query_plan,'
                       )
                  ELSE CONVERT(nvarchar(MAX), N'')
              END
            + CONVERT
              (
                  nvarchar(MAX),
                  N'
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
                ) + 1,
            der.plan_handle,
            der.status,
            der.blocking_session_id,
            der.wait_type,
            wait_time_ms = der.wait_time,
            der.wait_resource,
            cpu_time_ms = der.cpu_time,
            total_elapsed_time_ms = der.total_elapsed_time,
            der.reads,
            der.writes,
            der.logical_reads,
            granted_query_memory_mb =
                (der.granted_query_memory / 128.),
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
                END'
              )
            + CASE
                  WHEN @cool_new_columns = 1
                  THEN CONVERT
                       (
                           nvarchar(MAX),
                           N',
            der.dop,
            der.parallel_worker_count'
                       )
                  ELSE N''
              END
            + CONVERT
              (
                  nvarchar(MAX),
                  N'
        FROM sys.dm_exec_requests AS der
        CROSS APPLY sys.dm_exec_sql_text(der.plan_handle) AS dest
        CROSS APPLY sys.dm_exec_query_plan(der.plan_handle) AS deqp
        WHERE der.session_id <> @@SPID
        AND   der.session_id >= 50
        ORDER BY '
        + CASE
              WHEN @cool_new_columns = 1
              THEN N'
            der.cpu_time DESC,
            der.parallel_worker_count DESC
        OPTION(MAXDOP 1, RECOMPILE);'
              ELSE N'
            der.cpu_time DESC
        OPTION(MAXDOP 1, RECOMPILE);'
          END
              );

        IF @debug = 1 BEGIN PRINT SUBSTRING(@cpu_sql, 0, 4000); PRINT SUBSTRING(@cpu_sql, 4000, 8000); END;

        EXEC sys.sp_executesql
            @cpu_sql;

    END;

END;
GO