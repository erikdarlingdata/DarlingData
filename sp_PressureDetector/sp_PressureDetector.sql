SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
SET IMPLICIT_TRANSACTIONS OFF;
SET STATISTICS TIME, IO OFF;
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

Copyright 2024 Darling Data, LLC
https://www.erikdarling.com/

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
    @what_to_check nvarchar(6) = N'all', /*areas to check for pressure*/
    @skip_queries bit = 0, /*if you want to skip looking at running queries*/
    @skip_plan_xml bit = 0, /*if you want to skip getting plan XML*/
    @minimum_disk_latency_ms smallint = 100, /*low bound for reporting disk latency*/
    @cpu_utilization_threshold smallint = 50, /*low bound for reporting high cpu utlization*/
    @skip_waits bit = NULL, /*skips waits when you do not need them on every run*/
    @help bit = 0, /*how you got here*/
    @debug bit = 0, /*prints dynamic sql, displays parameter and variable values, and table contents*/
    @version varchar(5) = NULL OUTPUT, /*OUTPUT; for support*/
    @version_date datetime = NULL OUTPUT /*OUTPUT; for support*/
)
WITH RECOMPILE
AS
BEGIN
SET STATISTICS XML OFF;   
SET NOCOUNT ON;
SET XACT_ABORT ON;   
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

SELECT
    @version = '4.13',
    @version_date = '20240101';


IF @help = 1
BEGIN
    /*
    Introduction
    */
    SELECT
        introduction =
           'hi, i''m sp_PressureDetector!' UNION ALL
    SELECT 'you got me from https://github.com/erikdarlingdata/DarlingData/tree/main/sp_PressureDetector' UNION ALL
    SELECT 'i''m a lightweight tool for monitoring cpu and memory pressure' UNION ALL
    SELECT 'i''ll tell you: ' UNION ALL
    SELECT ' * what''s currently consuming memory on your server' UNION ALL
    SELECT ' * wait stats relevant to cpu, memory, and disk pressure, along with query performance' UNION ALL
    SELECT ' * how many worker threads and how much memory you have available' UNION ALL
    SELECT ' * running queries that are using cpu and memory' UNION ALL
    SELECT 'from your loving sql server consultant, erik darling: https://erikdarling.com';

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
                WHEN N'@what_to_check' THEN N'areas to check for pressure'
                WHEN N'@skip_queries' THEN N'if you want to skip looking at running queries'
                WHEN N'@skip_plan_xml' THEN N'if you want to skip getting plan XML'
                WHEN N'@minimum_disk_latency_ms' THEN N'low bound for reporting disk latency'
                WHEN N'@cpu_utilization_threshold' THEN N'low bound for reporting high cpu utlization'
                WHEN N'@skip_waits' THEN N'skips waits when you do not need them on every run'
                WHEN N'@help' THEN N'how you got here'
                WHEN N'@debug' THEN N'prints dynamic sql, displays parameter and variable values, and table contents'
                WHEN N'@version' THEN N'OUTPUT; for support'
                WHEN N'@version_date' THEN N'OUTPUT; for support'
            END,
        valid_inputs =
            CASE
                ap.name
                WHEN N'@what_to_check' THEN N'"all", "cpu", and "memory"'
                WHEN N'@skip_queries' THEN N'0 or 1'
                WHEN N'@skip_plan_xml' THEN N'0 or 1'
                WHEN N'@minimum_disk_latency_ms' THEN N'a reasonable number of milliseconds for disk latency'
                WHEN N'@cpu_utilization_threshold' THEN N'a reasonable cpu utlization percentage'
                WHEN N'@skip_waits' THEN N'NULL, 0, 1'
                WHEN N'@help' THEN N'0 or 1'
                WHEN N'@debug' THEN N'0 or 1'
                WHEN N'@version' THEN N'none'
                WHEN N'@version_date' THEN N'none'
            END,
        defaults =
            CASE
                ap.name
                WHEN N'@what_to_check' THEN N'both'
                WHEN N'@skip_queries' THEN N'0'
                WHEN N'@skip_plan_xml' THEN N'0'
                WHEN N'@minimum_disk_latency_ms' THEN N'100'
                WHEN N'@cpu_utilization_threshold' THEN N'50'
                WHEN N'@skip_waits' THEN N'NULL'
                WHEN N'@help' THEN N'0'
                WHEN N'@debug' THEN N'0'
                WHEN N'@version' THEN N'none; OUTPUT'
                WHEN N'@version_date' THEN N'none; OUTPUT'
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
           'i am MIT licensed, so like, do whatever'
  
    UNION ALL
  
    SELECT
        mit_license_yo =
            'see printed messages for full license';

    RAISERROR('
MIT License

Copyright 2024 Darling Data, LLC

https://www.erikdarling.com/

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
END; /*End help section*/

    /*
    Declarations of Variablependence
    */
    IF @debug = 1
    BEGIN
        RAISERROR('Declaring variables and temporary tables', 0, 1) WITH NOWAIT;
    END;

    DECLARE
        @azure bit =
            CASE
                WHEN
                    CONVERT
                    (
                        integer,
                        SERVERPROPERTY('EngineEdition')
                    ) = 5
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
        @reserved_worker_count_out varchar(10) = '0',
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
        @database_size_out_gb varchar(10) = '0',
        @total_physical_memory_gb bigint,
        @cpu_utilization xml = N'',
        @low_memory xml = N'',
        @disk_check nvarchar(MAX) = N'',
        @live_plans bit =
            CASE
                WHEN OBJECT_ID('sys.dm_exec_query_statistics_xml') IS NOT NULL
                THEN CONVERT(bit, 1)
                ELSE 0
            END;

    DECLARE
        @file_metrics table
    (
        hours_uptime int,
        drive nvarchar(255),
        database_name nvarchar(128),
        database_file_details nvarchar(1000),
        file_size_gb decimal(38,2),
        total_gb_read decimal(38,2),
        total_read_count bigint,
        avg_read_stall_ms decimal(38,2),
        total_gb_written decimal(38,2),
        total_write_count bigint,
        avg_write_stall_ms decimal(38,2)
    );

    DECLARE
        @threadpool_waits table
    (
        session_id smallint,
        wait_duration_ms bigint,
        threadpool_waits sysname
    );

    IF  @what_to_check = N'all'
    AND @skip_waits IS NULL
    BEGIN
        SELECT
            @skip_waits = 0;
    END;
  
    /*
    Check to see if the DAC is enabled.
    If it's not, give people some helpful information.
    */
    IF @what_to_check = N'all'
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Checking DAC status, etc.', 0, 1) WITH NOWAIT;
        END;

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
    END; /*End DAC section*/

    /*
    Look at wait stats related to performance only
    */
    IF
    (
            @what_to_check = N'all'
        AND @skip_waits <> 1
    )
    OR
    (
            @what_to_check IN (N'cpu', N'memory')
        AND @skip_waits = 0
    )
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Checking waits stats', 0, 1) WITH NOWAIT;
        END;

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
            hours_cpu_time =
                (
                    SELECT            
                        CONVERT
                        (
                            decimal(38, 2),
                            SUM(wg.total_cpu_usage_ms) / (1000. * 60. * 60.)
                        )
                    FROM sys.dm_resource_governor_workload_groups AS wg
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
                    THEN N'Potential worker thread exhaustion'
                    WHEN dows.wait_type = N'CMEMTHREAD'
                    THEN N'Tasks waiting on memory objects'
                    WHEN dows.wait_type = N'PAGELATCH_EX'
                    THEN N'Potential tempdb contention'
                    WHEN dows.wait_type = N'PAGELATCH_SH'
                    THEN N'Potential tempdb contention'
                    WHEN dows.wait_type = N'PAGELATCH_UP'
                    THEN N'Potential tempdb contention'
                    WHEN dows.wait_type LIKE N'LCK%'
                    THEN N'Queries waiting to acquire locks'
                    WHEN dows.wait_type = N'WRITELOG'
                    THEN N'Transaction Log writes'
                    WHEN dows.wait_type = N'LOGBUFFER'
                    THEN N'Transaction Log buffering'
                    WHEN dows.wait_type = N'LOG_RATE_GOVERNOR'
                    THEN N'Azure Transaction Log throttling'
                    WHEN dows.wait_type = N'POOL_LOG_RATE_GOVERNOR'
                    THEN N'Azure Transaction Log throttling'
                    WHEN dows.wait_type = N'SLEEP_TASK'
                    THEN N'Potential Hash spills'
                    WHEN dows.wait_type = N'BPSORT'
                    THEN N'Potential batch mode sort performance issues'
                    WHEN dows.wait_type = N'EXECSYNC'
                    THEN N'Potential eager index spool creation'
                    WHEN dows.wait_type = N'IO_COMPLETION'
                    THEN N'Potential sort spills'
                    WHEN dows.wait_type = N'ASYNC_NETWORK_IO'
                    THEN N'Potential client issues'
                    WHEN dows.wait_type = N'SLEEP_BPOOL_STEAL'
                    THEN N'Potential buffer pool pressure'
                    WHEN dows.wait_type = N'PWAIT_QRY_BPMEMORY'
                    THEN N'Potential batch mode performance issues'
                    WHEN dows.wait_type = N'HTREPARTITION'
                    THEN N'Potential batch mode performance issues'
                    WHEN dows.wait_type = N'HTBUILD'
                    THEN N'Potential batch mode performance issues'
                    WHEN dows.wait_type = N'HTMEMO'
                    THEN N'Potential batch mode performance issues'
                    WHEN dows.wait_type = N'HTDELETE'
                    THEN N'Potential batch mode performance issues'
                    WHEN dows.wait_type = N'HTREINIT'
                    THEN N'Potential batch mode performance issues'
                END,
            hours_wait_time =
                CONVERT
                (
                    decimal(38, 2),
                    dows.wait_time_ms / (1000. * 60. * 60.)
                ),
            avg_ms_per_wait =
                ISNULL
                (
                   CONVERT
                   (
                       decimal(38, 2),
                       dows.wait_time_ms /
                           NULLIF
                           (
                               1.*
                               dows.waiting_tasks_count,
                               0.
                           )
                    ),
                    0.
                ),
            percent_signal_waits =
                CONVERT
                (
                    decimal(38, 2),
                    ISNULL
                    (
                        100.0 * dows.signal_wait_time_ms
                           / NULLIF(dows.wait_time_ms, 0),
                        0.
                    )
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
                )
        FROM sys.dm_os_wait_stats AS dows
        WHERE
        (
          (      
                  dows.waiting_tasks_count > 0
              AND dows.wait_type <> N'SLEEP_TASK'
          )
        OR    
          (       
                 dows.wait_type = N'SLEEP_TASK'
             AND ISNULL(CONVERT(decimal(38, 2), dows.wait_time_ms /
                 NULLIF(1.* dows.waiting_tasks_count, 0.)), 0.) > 1000.
          )
        )
        AND
        (
            dows.wait_type IN
                 (
                     /*Disk*/
                     N'PAGEIOLATCH_SH',
                     N'PAGEIOLATCH_EX',
                     /*Memory*/
                     N'RESOURCE_SEMAPHORE',
                     N'RESOURCE_SEMAPHORE_QUERY_COMPILE',
                     N'CMEMTHREAD',
                     N'SLEEP_BPOOL_STEAL',
                     /*Parallelism*/
                     N'CXPACKET',
                     N'CXCONSUMER',
                     N'CXSYNC_PORT',
                     N'CXSYNC_CONSUMER',
                     /*CPU*/
                     N'SOS_SCHEDULER_YIELD',
                     N'THREADPOOL',
                     /*tempdb (potentially)*/
                     N'PAGELATCH_EX',
                     N'PAGELATCH_SH',
                     N'PAGELATCH_UP',
                     /*Transaction log*/
                     N'WRITELOG',
                     N'LOGBUFFER',
                     N'LOG_RATE_GOVERNOR',
                     N'POOL_LOG_RATE_GOVERNOR',
                     /*Some query performance stuff, spills and spools mostly*/
                     N'ASYNC_NETWORK_IO',
                     N'EXECSYNC',
                     N'IO_COMPLETION',                
                     N'SLEEP_TASK',
                     /*Batch Mode*/
                     N'HTBUILD',
                     N'HTDELETE',
                     N'HTMEMO',
                     N'HTREINIT',
                     N'HTREPARTITION',
                     N'PWAIT_QRY_BPMEMORY',
                     N'BPSORT'
                 )
            OR dows.wait_type LIKE N'LCK%' --Locking
        )
        ORDER BY
            dows.wait_time_ms DESC,
            dows.waiting_tasks_count DESC
        OPTION(MAXDOP 1, RECOMPILE);
    END;

    /*
    This section looks at disk metrics
    */
    IF @what_to_check = N'all'
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Checking file stats', 0, 1) WITH NOWAIT;
        END;

        SET @disk_check = N'
        SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
         
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
            drive =
                CASE
                    WHEN f.physical_name LIKE N''http%''
                    THEN f.physical_name
                    ELSE
                        UPPER
                        (
                            LEFT
                            (
                                f.physical_name,
                                2
                            )
                        )
                    END,
            database_name =
                 DB_NAME(vfs.database_id),
            database_file_details =
                ISNULL
                (
                    f.name COLLATE DATABASE_DEFAULT,
                    N''''
                ) +
                SPACE(1) +
                ISNULL
                (
                    CASE f.type
                         WHEN 0
                         THEN N''(data file)''
                         WHEN 1
                         THEN N''(transaction log)''
                         WHEN 2
                         THEN N''(filestream)''
                         WHEN 4
                         THEN N''(full-text)''
                         ELSE QUOTENAME
                              (
                                  f.type_desc COLLATE DATABASE_DEFAULT,
                                  N''()''
                              )
                    END,
                    N''''
                ) +
                SPACE(1) +
                ISNULL
                (
                    QUOTENAME
                    (
                        f.physical_name COLLATE DATABASE_DEFAULT,
                        N''()''
                    ),
                    N''''
                ),
            file_size_gb =
                CONVERT
                (
                    decimal(38, 2),
                    vfs.size_on_disk_bytes / 1073741824.
                ),
            total_gb_read =
                CASE
                    WHEN vfs.num_of_bytes_read > 0
                    THEN CONVERT
                         (
                             decimal(38, 2),
                             vfs.num_of_bytes_read / 1073741824.
                         )
                    ELSE 0
                END,
            total_read_count =  
                vfs.num_of_reads,
            avg_read_stall_ms =
                CONVERT
                (
                    decimal(38, 2),
                    vfs.io_stall_read_ms / (1.0 * vfs.num_of_reads)
                ),
            total_gb_written =
                CASE
                    WHEN vfs.num_of_bytes_written > 0
                    THEN CONVERT
                         (
                             decimal(38, 2),
                             vfs.num_of_bytes_written / 1073741824.
                         )
                    ELSE 0
                END,
            total_write_count =
                vfs.num_of_writes,
            avg_write_stall_ms =
                CONVERT
                (
                    decimal(38, 2),
                    vfs.io_stall_write_ms / (1.0 * vfs.num_of_writes)
                )     
        FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS vfs
        JOIN ' +
        CONVERT
        (
            nvarchar(MAX),
            CASE
                WHEN @azure = 1
                THEN N'sys.database_files AS f
          ON  vfs.file_id = f.file_id
          AND vfs.database_id = DB_ID()'
                ELSE N'sys.master_files AS f
          ON  vfs.file_id = f.file_id
          AND vfs.database_id = f.database_id'
        END +
        N'
        WHERE vfs.num_of_reads > 0
        AND   vfs.num_of_writes > 0;'
        );
      
        IF @debug = 1
        BEGIN
            PRINT SUBSTRING(@disk_check, 1, 4000);
            PRINT SUBSTRING(@disk_check, 4000, 8000);
        END;
      
        INSERT
            @file_metrics
        (
            hours_uptime,
            drive,
            database_name,
            database_file_details,
            file_size_gb,
            total_gb_read,
            total_read_count,
            avg_read_stall_ms,
            total_gb_written,
            total_write_count,
            avg_write_stall_ms
        )
        EXEC sys.sp_executesql
            @disk_check;

        SELECT
            fm.hours_uptime,
            fm.drive,
            fm.database_name,
            fm.database_file_details,
            fm.file_size_gb,
            fm.avg_read_stall_ms,
            fm.avg_write_stall_ms,
            fm.total_gb_read,
            fm.total_gb_written,
            total_read_count =
                REPLACE
                (
                    CONVERT
                    (
                        nvarchar(30),
                        CONVERT
                        (
                            money,
                            fm.total_read_count
                        ),
                        1
                    ),
                    N'.00',
                    N''
                ),
            total_write_count =
                REPLACE
                (
                    CONVERT
                    (
                        nvarchar(30),
                        CONVERT
                        (
                            money,
                            fm.total_write_count
                        ),
                        1
                    ),
                    N'.00',
                    N''
                )
        FROM @file_metrics AS fm
        WHERE fm.avg_read_stall_ms  > @minimum_disk_latency_ms
        OR    fm.avg_write_stall_ms > @minimum_disk_latency_ms
        ORDER BY
            fm.avg_read_stall_ms +
            fm.avg_write_stall_ms DESC;
    END; /*End file stats*/

    /*
    This section looks at tempdb config and usage
    */
    IF
    (
        @azure = 0
    AND @what_to_check = N'all'
    )
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Checking tempdb config and usage', 0, 1) WITH NOWAIT;
        END;

        SELECT
            tempdb_info =
                (
                    SELECT
                        tempdb_configuration =
                            (
                                SELECT
                                    total_data_files =
                                        COUNT_BIG(*),
                                    min_size_gb =
                                        MIN(mf.size * 8) / 1024 / 1024,
                                    max_size_gb =
                                        MAX(mf.size * 8) / 1024 / 1024,
                                    min_growth_increment_gb =
                                        MIN(mf.growth * 8) / 1024 / 1024,
                                    max_growth_increment_gb =
                                        MAX(mf.growth * 8) / 1024 / 1024,
                                    scheduler_total_count =
                                        (
                                            SELECT
                                                osi.cpu_count
                                            FROM sys.dm_os_sys_info AS osi
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
                                    free_space_gb =
                                        CONVERT
                                        (
                                            decimal(38, 2),
                                            SUM(d.unallocated_extent_page_count * 8.) / 1024. / 1024.
                                        ),
                                    user_objects_gb =
                                        CONVERT
                                        (
                                            decimal(38, 2),
                                            SUM(d.user_object_reserved_page_count * 8.) / 1024. / 1024.
                                        ),
                                    version_store_gb =
                                        CONVERT
                                        (
                                            decimal(38, 2),
                                            SUM(d.version_store_reserved_page_count * 8.) / 1024. / 1024.
                                        ),
                                    internal_objects_gb =
                                        CONVERT
                                        (
                                            decimal(38, 2),
                                            SUM(d.internal_object_reserved_page_count * 8.) / 1024. / 1024.
                                        )
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
                                    tempdb_allocations_gb =
                                        CONVERT
                                        (
                                            decimal(38, 2),
                                            SUM(t.tempdb_allocations * 8.) / 1024. / 1024.
                                        ),
                                    tempdb_current_gb =
                                        CONVERT
                                        (
                                            decimal(38, 2),
                                            SUM(t.tempdb_current * 8.) / 1024. / 1024.
                                        )
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
                                    (SUM(t.tempdb_allocations) * 8.) / 1024. > 0.
                                ORDER BY
                                    SUM(t.tempdb_allocations) DESC
                                FOR XML
                                    PATH('tempdb_query_activity'),
                                    TYPE

                            )
                        FOR XML
                            PATH('tempdb'),
                            TYPE
                )
        OPTION(RECOMPILE, MAXDOP 1);
    END; /*End tempdb check*/

    /*Memory info, utilization and usage*/
    IF @what_to_check IN (N'all', N'memory')
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Checking memory pressure', 0, 1) WITH NOWAIT;
        END;

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
                    decimal(38, 2),
                    SUM
                    (
                        ' +
            CONVERT
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
                REPLACE
                (
                    dopc.counter_name,
                    N'' (KB)'',
                    N''''
                ),
            memory_consumed_gb =
                CONVERT
                (
                    decimal(38, 2),
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
                        decimal(38, 2),
                        SUM
                        (
                        ' + CASE @pages_kb
                                 WHEN 1
                                 THEN
                        N'    domc.pages_kb '
                                 ELSE
                        N'    domc.single_pages_kb +
                            domc.multi_pages_kb '
                            END + N'
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
                      END + N'
               ) / 1024. / 1024. > 0.
            ORDER BY
                memory_used_gb DESC
        ) AS x
        OPTION(MAXDOP 1, RECOMPILE);
        ';

        IF @debug = 1
        BEGIN
            PRINT @pool_sql;
        END;

        EXEC sys.sp_executesql
            @pool_sql;

        /*Checking total database size*/
        IF @azure = 1
        BEGIN
            SELECT
                @database_size_out = N'
                SELECT
                    @database_size_out_gb =
                        SUM
                        (
                            CONVERT
                            (
                                bigint,
                                df.size
                            )
                        ) * 8 / 1024 / 1024
                FROM sys.database_files AS df
                OPTION(MAXDOP 1, RECOMPILE);';
        END;
        IF @azure = 0
        BEGIN
            SELECT
                @database_size_out = N'
                SELECT
                    @database_size_out_gb =
                        SUM
                        (
                            CONVERT
                            (
                                bigint,
                                mf.size
                            )
                        ) * 8 / 1024 / 1024
                FROM sys.master_files AS mf
                WHERE mf.database_id > 4
                OPTION(MAXDOP 1, RECOMPILE);';
        END;

        EXEC sys.sp_executesql
            @database_size_out,
          N'@database_size_out_gb varchar(10) OUTPUT',
            @database_size_out_gb OUTPUT;

        /*Check physical memory in the server*/
        IF @azure = 0
        BEGIN
            SELECT
                @total_physical_memory_gb =
                    CEILING(dosm.total_physical_memory_kb / 1024. / 1024.)
                FROM sys.dm_os_sys_memory AS dosm;
        END;
        IF @azure = 1
        BEGIN
            SELECT
                @total_physical_memory_gb =
                    SUM(osi.committed_target_kb / 1024. / 1024.)
            FROM sys.dm_os_sys_info osi;
        END;

        /*Checking for low memory indicators*/
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
                            (t.timestamp - osi.ms_ticks) / 1000,
                            SYSDATETIME()
                        )
                    ),
                notification_type =
                    t.record.value('(/Record/ResourceMonitor/Notification)[1]', 'varchar(50)'),
                indicators_process =
                    t.record.value('(/Record/ResourceMonitor/IndicatorsProcess)[1]', 'int'),
                indicators_system =
                    t.record.value('(/Record/ResourceMonitor/IndicatorsSystem)[1]', 'int'),
                physical_memory_available_gb =
                    t.record.value('(/Record/MemoryRecord/AvailablePhysicalMemory)[1]', 'bigint') / 1024 / 1024,
                virtual_memory_available_gb =
                    t.record.value('(/Record/MemoryRecord/AvailableVirtualAddressSpace)[1]', 'bigint') / 1024 / 1024
            FROM sys.dm_os_sys_info AS osi
            CROSS JOIN
            (
                SELECT
                    dorb.timestamp,
                    record =
                        CONVERT(xml, dorb.record)
                FROM sys.dm_os_ring_buffers AS dorb
                WHERE dorb.ring_buffer_type = N'RING_BUFFER_RESOURCE_MONITOR'
            ) AS t
            WHERE 
              (
                  t.record.exist('(Record/ResourceMonitor/Notification[. = "RESOURCE_MEMPHYSICAL_LOW"])') = 1
               OR t.record.exist('(Record/ResourceMonitor/Notification[. = "RESOURCE_MEMVIRTUAL_LOW"])') = 1
              )
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
               @low_memory;

        SELECT
            deqrs.resource_semaphore_id,
            total_database_size_gb =
                @database_size_out_gb,
            total_physical_memory_gb =
                @total_physical_memory_gb,
            max_server_memory_gb =
                (
                    SELECT
                        CONVERT
                        (
                            bigint,
                            c.value_in_use
                        )
                    FROM sys.configurations AS c
                    WHERE c.name = N'max server memory (MB)'
                ) / 1024,
            memory_model =
                (
                    SELECT
                        osi.sql_memory_model_desc
                    FROM sys.dm_os_sys_info AS osi
                ),
            target_memory_gb =
                CONVERT
                (
                    decimal(38, 2),
                    (deqrs.target_memory_kb / 1024. / 1024.)
                ),
            max_target_memory_gb =
                CONVERT(
                    decimal(38, 2),
                    (deqrs.max_target_memory_kb / 1024. / 1024.)
                ),
            total_memory_gb =
                CONVERT
                (
                    decimal(38, 2),
                    (deqrs.total_memory_kb / 1024. / 1024.)
                ),
            available_memory_gb =
                CONVERT
                (
                    decimal(38, 2),
                    (deqrs.available_memory_kb / 1024. / 1024.)
                ),
            granted_memory_gb =
                CONVERT
                (
                    decimal(38, 2),
                    (deqrs.granted_memory_kb / 1024. / 1024.)
                ),
            used_memory_gb =
                CONVERT
                (
                    decimal(38, 2),
                    (deqrs.used_memory_kb / 1024. / 1024.)
                ),
            deqrs.grantee_count,
            deqrs.waiter_count,
            deqrs.timeout_error_count,
            deqrs.forced_grant_count,
            wg.total_reduced_memory_grant_count,
            deqrs.pool_id
        FROM sys.dm_exec_query_resource_semaphores AS deqrs
        CROSS APPLY
        (
            SELECT TOP (1)
                total_reduced_memory_grant_count =
                    wg.total_reduced_memgrant_count
            FROM sys.dm_resource_governor_workload_groups AS wg
            WHERE wg.pool_id = deqrs.pool_id
            ORDER BY
                wg.total_reduced_memgrant_count DESC
        ) AS wg
        WHERE deqrs.max_target_memory_kb IS NOT NULL
        ORDER BY
            deqrs.pool_id
        OPTION(MAXDOP 1, RECOMPILE);
    END; /*End memory checks*/

    /*
    Track down queries currently asking for memory grants
    */
    IF
    (
        @skip_queries = 0
    AND @what_to_check IN (N'all', N'memory')
    )
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Checking queries with memory grants', 0, 1) WITH NOWAIT;
        END;

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
                    CASE
                        WHEN
                            DATEDIFF
                            (
                                DAY,
                                deqmg.request_time,
                                SYSDATETIME()
                            ) >= 24
                        THEN
                            DATEADD
                            (
                                SECOND,
                                DATEDIFF
                                (
                                    SECOND,
                                    deqmg.request_time,
                                    SYSDATETIME()
                                ),
                                ''19000101''                           
                            )                      
                        ELSE
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
                            )
                        END,
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
            deqp.query_plan,' +
                  CASE
                      WHEN @live_plans = 1
                      THEN N'
            live_query_plan =
                deqs.query_plan,'
                      ELSE N''
                  END
              END +
                      N'
            deqmg.request_time,
            deqmg.grant_time,
            wait_time_seconds =
                (deqmg.wait_time_ms / 1000.),
            requested_memory_gb =
                CONVERT(decimal(38, 2), (deqmg.requested_memory_kb / 1024. / 1024.)),
            granted_memory_gb =
                CONVERT(decimal(38, 2), (deqmg.granted_memory_kb / 1024. / 1024.)),
            used_memory_gb =
                CONVERT(decimal(38, 2), (deqmg.used_memory_kb / 1024. / 1024.)),
            max_used_memory_gb =
                CONVERT(decimal(38, 2), (deqmg.max_used_memory_kb / 1024. / 1024.)),
            ideal_memory_gb =
                CONVERT(decimal(38, 2), (deqmg.ideal_memory_kb / 1024. / 1024.)),
            required_memory_gb =
                CONVERT(decimal(38, 2), (deqmg.required_memory_kb / 1024. / 1024.)),
            deqmg.queue_id,
            deqmg.wait_order,
            deqmg.is_next_candidate,
            waits.wait_type,
            wait_duration_seconds =
                (waits.wait_duration_ms / 1000.),
            deqmg.dop,' +
                CASE
                    WHEN @helpful_new_columns = 1
                    THEN N'
            deqmg.reserved_worker_count,
            deqmg.used_worker_count,'
                    ELSE N''
                END + N'
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
        OUTER APPLY sys.dm_exec_sql_text(deqmg.plan_handle) AS dest' +
            CASE
                WHEN @live_plans = 1
                THEN N'
        OUTER APPLY sys.dm_exec_query_statistics_xml(deqmg.plan_handle) AS deqs'
                ELSE N''
            END +
       N'
        WHERE deqmg.session_id <> @@SPID
        ORDER BY
            requested_memory_gb DESC,
            deqmg.request_time
        OPTION(MAXDOP 1, RECOMPILE);
        '
                  );
      
        IF @debug = 1
        BEGIN
            PRINT SUBSTRING(@mem_sql, 1, 4000);
            PRINT SUBSTRING(@mem_sql, 4000, 8000);
        END;
      
        EXEC sys.sp_executesql
            @mem_sql;
    END;

    /*
    Looking at CPU config and indicators
    */
    IF @what_to_check IN (N'all', N'cpu')
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR('Checking CPU config', 0, 1) WITH NOWAIT;
        END;

        IF @helpful_new_columns = 1
        BEGIN
            IF @debug = 1
            BEGIN
                PRINT @reserved_worker_count;
            END;

            EXEC sys.sp_executesql
                @reserved_worker_count,
              N'@reserved_worker_count_out varchar(10) OUTPUT',
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
                    WHEN ac.name = N'scheduler_total_count'
                    THEN N'                osi.scheduler_total_count, ' + NCHAR(10)
                    WHEN ac.name = N'scheduler_count'
                    THEN N'                osi.scheduler_count, ' + NCHAR(10)
                    ELSE N''
                END
        FROM
        (
            SELECT
                ac.name
            FROM sys.all_columns AS ac
            WHERE ac.object_id = OBJECT_ID(N'sys.dm_os_sys_info')
            AND   ac.name IN
                  (
                      N'socket_count',
                      N'numa_node_count',
                      N'cpu_count',
                      N'cores_per_socket',
                      N'hyperthread_ratio',
                      N'softnuma_configuration_desc',
                      N'scheduler_total_count',
                      N'scheduler_count'
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

        IF @debug = 1
        BEGIN
            PRINT @cpu_details;
        END;

        EXEC sys.sp_executesql
            @cpu_details,
          N'@cpu_details_output xml OUTPUT',
            @cpu_details_output OUTPUT;

        /*
        Checking for high CPU utilization periods
        */
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
                            (t.timestamp - osi.ms_ticks) / 1000,
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
            FROM sys.dm_os_sys_info AS osi
            CROSS JOIN
            (
                SELECT
                    dorb.timestamp,
                    record =
                        CONVERT(xml, dorb.record)
                FROM sys.dm_os_ring_buffers AS dorb
                WHERE dorb.ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR'
            ) AS t
            WHERE t.record.exist('(Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization[.>= sql:variable("@cpu_utilization_threshold")])') = 1
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
                        N'No significant CPU usage data available.'
                    FOR XML
                        PATH(N'cpu_utilization'),
                        TYPE
                );
        END;

        SELECT
            cpu_details_output =
                @cpu_details_output,
            cpu_utilization_over_threshold =
                @cpu_utilization;      
      
        /*Thread usage*/
        SELECT
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
            total_active_request_count =
                SUM(wg.active_request_count),
            total_queued_request_count =
                SUM(wg.queued_request_count),
            total_blocked_task_count =
                SUM(wg.blocked_task_count),
            total_active_parallel_thread_count =
                SUM(wg.active_parallel_thread_count),
            avg_runnable_tasks_count =
                AVG(dos.runnable_tasks_count),
            high_runnable_percent =
                MAX(ISNULL(r.high_runnable_percent, 0))
        FROM sys.dm_os_schedulers AS dos
        CROSS JOIN sys.dm_os_sys_info AS osi
        CROSS JOIN
        (
            SELECT
                wg.active_request_count,
                wg.queued_request_count,
                wg.blocked_task_count,
                wg.active_parallel_thread_count
            FROM sys.dm_resource_governor_workload_groups AS wg      
        ) AS wg
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
                            decimal(38,2),
                            (
                                x.runnable / (1. * NULLIF(x.total, 0))
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
                                    WHEN der.status = N'runnable'
                                    THEN 1
                                    ELSE 0
                                END
                            )
                    FROM sys.dm_exec_requests AS der
                    WHERE der.session_id > 50
                ) AS x
            ) AS y
            WHERE y.runnable_pct >= 10
            AND   y.total >= 10
        ) AS r
        WHERE dos.status = N'VISIBLE ONLINE'
        OPTION(MAXDOP 1, RECOMPILE);


        /*
        Any current threadpool waits?
        */      
        INSERT
            @threadpool_waits
        (
            session_id,
            wait_duration_ms,
            threadpool_waits
        )
        SELECT
            dowt.session_id,
            dowt.wait_duration_ms,
            threadpool_waits =
                dowt.wait_type
        FROM sys.dm_os_waiting_tasks AS dowt
        WHERE dowt.wait_type = N'THREADPOOL'
        ORDER BY
            dowt.wait_duration_ms DESC
        OPTION(MAXDOP 1, RECOMPILE);

        IF @@ROWCOUNT = 0
        BEGIN
            SELECT
                THREADPOOL = N'No current THREADPOOL waits';
        END;
        ELSE
        BEGIN
            SELECT
                dowt.session_id,
                dowt.wait_duration_ms,
                threadpool_waits =
                    dowt.wait_type
            FROM sys.dm_os_waiting_tasks AS dowt
            WHERE dowt.wait_type = N'THREADPOOL'
            ORDER BY
                dowt.wait_duration_ms DESC
            OPTION(MAXDOP 1, RECOMPILE);
        END;


        /*
        Figure out who's using a lot of CPU
        */
        IF
        (
            @skip_queries = 0
        AND @what_to_check IN (N'all', N'cpu')
        )
        BEGIN
            IF @debug = 1
            BEGIN
                RAISERROR('Checking CPU queries', 0, 1) WITH NOWAIT;
            END;

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
                        CASE
                            WHEN
                                DATEDIFF
                                (
                                    DAY,
                                    der.start_time,
                                    SYSDATETIME()
                                ) >= 24
                            THEN
                                DATEADD
                                (
                                    SECOND,
                                    DATEDIFF
                                    (
                                        SECOND,
                                        der.start_time,
                                        SYSDATETIME()
                                    ),
                                    ''19000101''                           
                                )                      
                            ELSE
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
                                )
                            END,
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
                +
                CONVERT
                (
                    nvarchar(MAX),              
                CASE
                      WHEN @skip_plan_xml = 0
                      THEN N'
                deqp.query_plan,' +
                          CASE
                              WHEN @live_plans = 1
                              THEN
                           N'
                live_query_plan =
                    deqs.query_plan,'
                              ELSE N''
                          END
                      ELSE N''
                  END
                )
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
                granted_query_memory_gb =
                    CONVERT(decimal(38, 2), (der.granted_query_memory / 128. / 1024.)),
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
            OUTER APPLY sys.dm_exec_sql_text(der.plan_handle) AS dest
            OUTER APPLY sys.dm_exec_query_plan(der.plan_handle) AS deqp' +
                CASE
                    WHEN @live_plans = 1
                    THEN N'
            OUTER APPLY sys.dm_exec_query_statistics_xml(der.plan_handle) AS deqs'
                    ELSE N''
                END +
            N'
            WHERE der.session_id <> @@SPID
            AND   der.session_id >= 50
            AND   dest.text LIKE N''_%''
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
          
            IF @debug = 1
            BEGIN
                PRINT SUBSTRING(@cpu_sql, 0, 4000);
                PRINT SUBSTRING(@cpu_sql, 4000, 8000);
            END;
          
            EXEC sys.sp_executesql
                @cpu_sql;
        END; /*End not skipping queries*/
    END; /*End CPU checks*/

    IF @debug = 1
    BEGIN
        SELECT
            table_name = '@file_metrics',
            x.*
        FROM @file_metrics AS x
        ORDER BY
            x.database_name
        OPTION(RECOMPILE);

        SELECT
            table_name = '@threadpool_waits',
            x.*
        FROM @threadpool_waits AS x
        ORDER BY
            x.wait_duration_ms DESC
        OPTION(RECOMPILE);
       
        SELECT
            pattern =
                'parameters',
            what_to_check =
                @what_to_check,
            skip_queries =
                @skip_queries,
            skip_plan_xml =
                @skip_plan_xml,
            minimum_disk_latency_ms =
                @minimum_disk_latency_ms,
            cpu_utilization_threshold =
                @cpu_utilization_threshold,
            skip_waits =
                @skip_waits,
            help =
                @help,
            debug =
                @debug,
            version =
                @version,
            version_date =
                @version_date;
               
        SELECT
            pattern =
                'variables',
            azure =
                @azure,
            pool_sql =
                @pool_sql,
            pages_kb =
                @pages_kb,
            mem_sql =
                @mem_sql,
            helpful_new_columns =
                @helpful_new_columns,
            cpu_sql =
                @cpu_sql,
            cool_new_columns =
                @cool_new_columns,
            reserved_worker_count_out =
                @reserved_worker_count_out,
            reserved_worker_count =
                @reserved_worker_count,
            cpu_details =
                @cpu_details,
            cpu_details_output =
                @cpu_details_output,
            cpu_details_columns =
                @cpu_details_columns,
            cpu_details_select =
                @cpu_details_select,
            cpu_details_from =
                @cpu_details_from,
            database_size_out =
                @database_size_out,
            database_size_out_gb =
                @database_size_out_gb,
            total_physical_memory_gb =
                @total_physical_memory_gb,
            cpu_utilization =
                @cpu_utilization,
            low_memory =
                @low_memory,
            disk_check =
                @disk_check,
            live_plans =
                @live_plans;
       
    END; /*End Debug*/
END; /*Final End*/
GO
