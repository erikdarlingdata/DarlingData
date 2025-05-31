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
██╗      ██████╗  ██████╗
██║     ██╔═══██╗██╔════╝
██║     ██║   ██║██║  ███╗
██║     ██║   ██║██║   ██║
███████╗╚██████╔╝╚██████╔╝
╚══════╝ ╚═════╝  ╚═════╝

██╗  ██╗██╗   ██╗███╗   ██╗████████╗███████╗██████╗
██║  ██║██║   ██║████╗  ██║╚══██╔══╝██╔════╝██╔══██╗
███████║██║   ██║██╔██╗ ██║   ██║   █████╗  ██████╔╝
██╔══██║██║   ██║██║╚██╗██║   ██║   ██╔══╝  ██╔══██╗
██║  ██║╚██████╔╝██║ ╚████║   ██║   ███████╗██║  ██║
╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝   ╚═╝   ╚══════╝╚═╝  ╚═╝

Copyright 2025 Darling Data, LLC
https://www.erikdarling.com/

For usage and licensing details, run:
EXECUTE sp_LogHunter
    @help = 1;

For working through errors:
EXECUTE sp_LogHunter
    @debug = 1;

For support, head over to GitHub:
https://code.erikdarling.com

EXECUTE sp_LogHunter;

*/

IF OBJECT_ID(N'dbo.sp_LogHunter', N'P') IS NULL
   BEGIN
       EXECUTE (N'CREATE PROCEDURE dbo.sp_LogHunter AS RETURN 138;');
   END;
GO

ALTER PROCEDURE
    dbo.sp_LogHunter
(
    @days_back integer = -7, /*How many days back you want to look in the error logs*/
    @start_date datetime = NULL, /*If you want to search a specific time frame*/
    @end_date datetime = NULL, /*If you want to search a specific time frame*/
    @custom_message nvarchar(4000) = NULL, /*If there's something you specifically want to search for*/
    @custom_message_only bit = 0, /*If you only want to search for this specific thing*/
    @first_log_only bit = 0, /*If you only want to search the first log file*/
    @language_id integer = 1033, /*If you want to use a language other than English*/
    @help bit = 0, /*Get help*/
    @debug bit = 0, /*Prints messages and selects from temp tables*/
    @version varchar(30) = NULL OUTPUT,
    @version_date datetime = NULL OUTPUT
)
WITH RECOMPILE
AS
SET STATISTICS XML OFF;
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

BEGIN
    SELECT
        @version = '2.6',
        @version_date = '20250601';

    IF @help = 1
    BEGIN
        SELECT
            introduction =
                'hi, i''m sp_LogHunter!' UNION ALL
        SELECT  'you can use me to look through your error logs for bad stuff' UNION ALL
        SELECT  'all scripts and documentation are available here: https://code.erikdarling.com' UNION ALL
        SELECT  'from your loving sql server consultant, erik darling: https://erikdarling.com';

        SELECT
            parameter_name =
                ap.name,
            data_type = t.name,
            description =
                CASE ap.name
                     WHEN N'@days_back' THEN 'how many days back you want to search the logs'
                     WHEN N'@start_date' THEN 'if you want to search a specific time frame'
                     WHEN N'@end_date' THEN 'if you want to search a specific time frame'
                     WHEN N'@custom_message' THEN 'if you want to search for a custom string'
                     WHEN N'@custom_message_only' THEN 'only search for the custom string'
                     WHEN N'@first_log_only' THEN 'only search through the first error log'
                     WHEN N'@language_id' THEN 'to use something other than English'
                     WHEN N'@help' THEN 'how you got here'
                     WHEN N'@debug' THEN 'dumps raw temp table contents'
                     WHEN N'@version' THEN 'OUTPUT; for support'
                     WHEN N'@version_date' THEN 'OUTPUT; for support'
                END,
            valid_inputs =
                CASE ap.name
                     WHEN N'@days_back' THEN 'an integer; will be converted to a negative number automatically'
                     WHEN N'@start_date' THEN 'a datetime value'
                     WHEN N'@end_date' THEN 'a datetime value'
                     WHEN N'@custom_message' THEN 'something specific you want to search for. no wildcards or substitions.'
                     WHEN N'@custom_message_only' THEN 'NULL, 0, 1'
                     WHEN N'@first_log_only' THEN 'NULL, 0, 1'
                     WHEN N'@language_id' THEN 'SELECT DISTINCT m.language_id FROM sys.messages AS m ORDER BY m.language_id;'
                     WHEN N'@help' THEN 'NULL, 0, 1'
                     WHEN N'@debug' THEN 'NULL, 0, 1'
                     WHEN N'@version' THEN 'OUTPUT; for support'
                     WHEN N'@version_date' THEN 'OUTPUT; for support'
                END,
            defaults =
                CASE ap.name
                     WHEN N'@days_back' THEN '-7'
                     WHEN N'@start_date' THEN 'NULL'
                     WHEN N'@end_date' THEN 'NULL'
                     WHEN N'@custom_message' THEN 'NULL'
                     WHEN N'@custom_message_only' THEN '0'
                     WHEN N'@first_log_only' THEN '0'
                     WHEN N'@language_id' THEN '1033'
                     WHEN N'@help' THEN '0'
                     WHEN N'@debug' THEN '0'
                     WHEN N'@version' THEN 'none; OUTPUT'
                     WHEN N'@version_date' THEN 'none; OUTPUT'
                END
        FROM sys.all_parameters AS ap
        JOIN sys.all_objects AS o
          ON ap.object_id = o.object_id
        JOIN sys.types AS t
          ON  ap.system_type_id = t.system_type_id
          AND ap.user_type_id = t.user_type_id
        WHERE o.name = N'sp_LogHunter'
        OPTION(RECOMPILE);

        SELECT
            mit_license_yo = 'i am MIT licensed, so like, do whatever'

        UNION ALL

        SELECT
            mit_license_yo = 'see printed messages for full license';

        RAISERROR('
    MIT License

    Copyright 2025 Darling Data, LLC

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
    END;

    /*Check if we have sa permissisions, but not care in RDS*/
    IF
    (
        SELECT
            sa = ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0)
    ) = 0
    AND OBJECT_ID(N'rdsadmin.dbo.rds_read_error_log', N'P') IS NULL
    BEGIN
       RAISERROR(N'Current user is not a member of sysadmin, so we can''t read the error log', 11, 1) WITH NOWAIT;
       RETURN;
    END;

    /*Check if we're unfortunate*/
    IF
    (
        SELECT
            CONVERT
            (
                integer,
                SERVERPROPERTY('EngineEdition')
            )
    ) = 5
    BEGIN
       RAISERROR(N'This will not run on Azure SQL DB because it''s horrible.', 11, 1) WITH NOWAIT;
       RETURN;
    END;

    /*Validate the language id*/
    IF NOT EXISTS
    (
        SELECT
            1/0
        FROM sys.messages AS m
        WHERE m.language_id = @language_id
    )
    BEGIN
       RAISERROR(N'%i is not a valid language_id in sys.messages.', 11, 1, @language_id) WITH NOWAIT;
       RETURN;
    END;

    /*Fix days back a little bit*/
    IF @days_back = 0
    BEGIN
        SELECT
            @days_back = -1;
    END;

    IF @days_back > 0
    BEGIN
        SELECT
            @days_back *= -1;
    END;

    IF  @start_date IS NOT NULL
    AND @end_date   IS NOT NULL
    AND @days_back  IS NOT NULL
    BEGIN
        SELECT
            @days_back = NULL;
    END;

    /*Fix custom message only if NULL*/
    IF @custom_message_only IS NULL
    BEGIN
        SELECT
            @custom_message_only = 0;
    END;

    /*Fix @end_date*/
    IF  @start_date IS NOT NULL
    AND @end_date IS NULL
    BEGIN
        SELECT
             @end_date = SYSDATETIME();
    END;

    /*Fix @start_date*/
    IF  @start_date IS NULL
    AND @end_date IS NOT NULL
    BEGIN
        SELECT
             @start_date = DATEADD(DAY, -7, @end_date);
    END;

    /*Debuggo*/
    IF @debug = 1
    BEGIN
        SELECT
            days_back = @days_back,
            start_date = @start_date,
            end_date = @end_date;
    END;

    /*variables for the variable gods*/
    DECLARE
        @c nvarchar(4000) /*holds the command to execute*/,
        @l_log integer = 0 /*low log file id*/,
        @h_log integer = 0 /*high log file id*/,
        @t_searches integer = 0 /*total number of searches to run*/,
        @l_count integer = 1 /*loop count*/,
        @stopper bit = 0, /*stop loop execution safety*/
        @is_rds bit =
            CASE
                WHEN OBJECT_ID(N'rdsadmin.dbo.rds_read_error_log', N'P') IS NOT NULL
                THEN 1
                ELSE 0
            END;

    /*temp tables for holding temporary things*/
    CREATE TABLE
        #error_log
    (
        log_date datetime,
        process_info nvarchar(100),
        text nvarchar(4000)
    );

    CREATE TABLE
        #enum
    (
        archive integer
          PRIMARY KEY CLUSTERED,
        log_date date,
        log_size bigint
    );

    CREATE TABLE
        #search
    (
        id integer
           IDENTITY
           PRIMARY KEY CLUSTERED,
        search_string nvarchar(4000) DEFAULT N'""',
        days_back nvarchar(30) NULL,
        start_date nvarchar(30) NULL,
        end_date nvarchar(30) NULL,
        [current_date] nvarchar(10)
            DEFAULT N'"' + CONVERT(nvarchar(10), DATEADD(DAY, 1, SYSDATETIME()), 112) + N'"',
        search_order nvarchar(10)
            DEFAULT N'"DESC"',
        command AS
            CONVERT
            (
                nvarchar(4000),
                N'EXECUTE master.dbo.xp_readerrorlog [@@@], 1, '
                + search_string
                + N', '
                + N'" "'
                + N', '
                + ISNULL(start_date, days_back)
                + N', '
                + ISNULL(end_date, [current_date])
                + N', '
                + search_order
                + N';'
            ) PERSISTED
    );

    CREATE TABLE
        #errors
    (
        id integer
           PRIMARY KEY CLUSTERED
           IDENTITY,
        command nvarchar(4000) NOT NULL
    );

    /*get all the error logs*/
    INSERT
        #enum
    (
        archive,
        log_date,
        log_size
    )
    EXECUTE sys.sp_enumerrorlogs;

    IF @debug = 1 BEGIN SELECT table_name = '#enum before delete', e.* FROM #enum AS e; END;

    /*filter out log files we won't use, if @days_back is set*/
    IF @days_back IS NOT NULL
    BEGIN
        DELETE
            e WITH(TABLOCKX)
        FROM #enum AS e
        WHERE e.log_date < DATEADD(DAY, @days_back, SYSDATETIME())
        AND   e.archive > 0
        OPTION(RECOMPILE);
    END;

    /*filter out log files we won't use, if @start_date and @end_date are set*/
    IF  @start_date IS NOT NULL
    AND @end_date IS NOT NULL
    BEGIN
        DELETE
            e WITH(TABLOCKX)
        FROM #enum AS e
        WHERE e.log_date < CONVERT(date, @start_date)
        OR    e.log_date > CONVERT(date, @end_date)
        OPTION(RECOMPILE);
    END;

    /*maybe you only want the first one anyway*/
    IF @first_log_only = 1
    BEGIN
        DELETE
            e WITH(TABLOCKX)
        FROM #enum AS e
        WHERE e.archive > 1
        OPTION(RECOMPILE);
    END;

    IF @debug = 1 BEGIN SELECT table_name = '#enum after delete', e.* FROM #enum AS e; END;

    /*insert some canary values for things that we should always hit. look a little further back for these.*/
    INSERT
        #search
    (
        search_string,
        days_back,
        start_date,
        end_date
    )
    SELECT
        x.search_string,
        c.days_back,
        c.start_date,
        c.end_date
    FROM
    (
        VALUES
            (N'"Microsoft SQL Server"'),
            (N'"detected"'),
            (N'"SQL Server has encountered"'),
            (N'"Warning: Enterprise Server/CAL license used for this instance"')
    ) AS x (search_string)
    CROSS JOIN
    (
        SELECT
            days_back =
                N'"' + CONVERT(nvarchar(10), DATEADD(DAY, CASE WHEN @days_back > -90 THEN -90 ELSE @days_back END, SYSDATETIME()), 112) + N'"',
            start_date =
                N'"' + CONVERT(nvarchar(30), @start_date) + N'"',
            end_date =
                N'"' + CONVERT(nvarchar(30), @end_date) + N'"'
    ) AS c
    WHERE @custom_message_only = 0
    OPTION(RECOMPILE);

    /*these are the search strings we currently care about*/
    INSERT
        #search
    (
        search_string,
        days_back,
        start_date,
        end_date
    )
    SELECT
        search_string =
            N'"' +
            v.search_string +
            N'"',
        c.days_back,
        c.start_date,
        c.end_date
    FROM
    (
        VALUES
            ('error'), ('corrupt'), ('insufficient'), ('DBCC CHECKDB'), ('Attempt to fetch logical page'), ('Total Log Writer threads'),
            ('Wait for redo catchup for the database'), ('Restart the server to resolve this problem'), ('running low'), ('unexpected'),
            ('fail'), ('contact'), ('incorrect'), ('allocate'), ('allocation'), ('Timeout occurred'), ('memory manager'), ('operating system'),
            ('cannot obtain a LOCK resource'), ('Server halted'), ('spawn'), ('BobMgr'), ('Sort is retrying the read'), ('service'),
            ('resumed'), ('repair the database'), ('buffer'), ('I/O Completion Port'), ('assert'), ('integrity'), ('latch'), ('SQL Server is exiting'),
            ('SQL Server is unable to run'), ('suspect'), ('restore the database'), ('checkpoint'), ('version store is full'), ('Setting database option'),
            ('Perform a restore if necessary'), ('Autogrow of file'), ('Bringing down database'), ('hot add'), ('Server shut down'),
            ('stack'), ('inconsistency.'), ('invalid'), ('time out occurred'), ('The transaction log for database'), ('The virtual log file sequence'),
            ('Cannot accept virtual log file sequence'), ('The transaction in database'), ('Shutting down'), ('thread pool'), ('debug'), ('resolving'),
            ('Cannot load the Query Store metadata'), ('Cannot acquire'), ('SQL Server evaluation period has expired'), ('terminat'), ('currently busy'),
            ('SQL Server has been configured for lightweight pooling'), ('IOCP'), ('Not enough memory for the configured number of locks'),
            ('The tempdb database data files are not configured with the same initial size and autogrowth settings'), ('The SQL Server image'), ('affinity'),
            ('SQL Server is starting'), ('Ignoring trace flag '), ('20 physical cores'), ('No free space'), ('Warning ******************'),
            ('SQL Server should be restarted'), ('Server name is'), ('Could not connect'), ('yielding'), ('worker thread'), ('A new connection was rejected'),
            ('A significant part of sql server process memory has been paged out'), ('Dispatcher'), ('I/O requests taking longer than'), ('killed'),
            ('SQL Server could not start'), ('SQL Server cannot start'), ('System Manufacturer:'), ('columnstore'), ('timed out'), ('inconsistent'),
            ('flushcache'), ('Recovery for availability database')
    ) AS v (search_string)
    CROSS JOIN
    (
        SELECT
            days_back =
                N'"' + CONVERT(nvarchar(10), DATEADD(DAY, @days_back, SYSDATETIME()), 112) + N'"',
            start_date =
                N'"' + CONVERT(nvarchar(30), @start_date) + N'"',
            end_date =
                N'"' + CONVERT(nvarchar(30), @end_date) + N'"'
    ) AS c
    WHERE @custom_message_only = 0
    OPTION(RECOMPILE);

    /*deal with a custom search string here*/
    INSERT
        #search
    (
        search_string,
        days_back,
        start_date,
        end_date
    )
    SELECT
        x.search_string,
        x.days_back,
        x.start_date,
        x.end_date
    FROM
    (
        VALUES
           (
                N'"' + @custom_message + '"',
                N'"' + CONVERT(nvarchar(10), DATEADD(DAY, @days_back, SYSDATETIME()), 112) + N'"',
                N'"' + CONVERT(nvarchar(30), @start_date) + N'"',
                N'"' + CONVERT(nvarchar(30), @end_date) + N'"'
           )
    ) AS x (search_string, days_back, start_date, end_date)
    WHERE @custom_message LIKE N'_%'
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        SELECT table_name = '#search', s.* FROM #search AS s;
    END;

    /*Set the min and max logs we're getting for the loop*/
    SELECT
        @l_log = MIN(e.archive),
        @h_log = MAX(e.archive),
        @t_searches = (SELECT COUNT_BIG(*) FROM #search AS s)
    FROM #enum AS e
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        RAISERROR('@l_log: %i', 0, 1, @l_log) WITH NOWAIT;
        RAISERROR('@h_log: %i', 0, 1, @h_log) WITH NOWAIT;
        RAISERROR('@t_searches: %i', 0, 1, @t_searches) WITH NOWAIT;
    END;

    IF @debug = 1 BEGIN RAISERROR('Declaring cursor', 0, 1) WITH NOWAIT; END;

    /*start the loops*/
    WHILE @l_log <= @h_log
    BEGIN
        DECLARE
            @cs CURSOR;

        SET
            @cs =
        CURSOR
            LOCAL
            SCROLL
            DYNAMIC
            READ_ONLY
        FOR
        SELECT
            command
        FROM #search;

        IF @debug = 1 BEGIN RAISERROR('Opening cursor', 0, 1) WITH NOWAIT; END;

        OPEN @cs;

        FETCH FIRST
        FROM @cs
        INTO @c;

        IF @debug = 1 BEGIN RAISERROR('Entering WHILE loop', 0, 1) WITH NOWAIT; END;
        WHILE @@FETCH_STATUS = 0
        AND   @stopper = 0
        BEGIN
            IF @debug = 1 BEGIN RAISERROR('Entering cursor', 0, 1) WITH NOWAIT; END;

            /*If using RDS, need to call a different procedure*/
            IF @is_rds = 1
            BEGIN
                SELECT
                    @c =
                        REPLACE
                        (
                            @c,
                            N'master.dbo.xp_readerrorlog',
                            N'rdsadmin.dbo.rds_read_error_log'
                        );
            END;

            /*Replace the canary value with the log number we're working in*/
            SELECT
                @c =
                    REPLACE
                    (
                        @c,
                        N'[@@@]',
                        @l_log
                    );

            IF @debug = 1
            BEGIN
                RAISERROR('log %i of %i', 0, 1, @l_log, @h_log) WITH NOWAIT;
                RAISERROR('search %i of %i', 0, 1, @l_count, @t_searches) WITH NOWAIT;
                RAISERROR('@c: %s', 0, 1, @c) WITH NOWAIT;
            END;

            IF @debug = 1 BEGIN RAISERROR('Inserting to error log', 0, 1) WITH NOWAIT; END;
            BEGIN
                BEGIN TRY
                    /*Insert any log entries we find that match the search*/
                    INSERT
                        #error_log
                    (
                        log_date,
                        process_info,
                        text
                    )
                    EXECUTE sys.sp_executesql
                        @c;
                END TRY
                BEGIN CATCH
                    /*Insert any searches that throw an error here*/
                    INSERT
                        #errors
                    (
                        command
                    )
                    VALUES
                    (
                        @c
                    );
                END CATCH;
            END;

            IF @debug = 1 BEGIN RAISERROR('Fetching next', 0, 1) WITH NOWAIT; END;

            /*Get the next search command*/
            FETCH NEXT
            FROM @cs
            INTO @c;

            /*Increment our loop counter*/
            SELECT
                @l_count += 1;

        END;

        IF @debug = 1 BEGIN RAISERROR('Getting next log', 0, 1) WITH NOWAIT; END;

        /*Increment the log numbers*/
        SELECT
            @l_log = MIN(e.archive),
            @l_count = 1
        FROM #enum AS e
        WHERE e.archive > @l_log
        OPTION(RECOMPILE);

        IF @debug = 1
        BEGIN
            RAISERROR('log %i of %i', 0, 1, @l_log, @h_log) WITH NOWAIT;
        END;

        /*Stop the loop if this is NULL*/
        IF @l_log IS NULL
        BEGIN
            IF @debug = 1 BEGIN RAISERROR('Breaking', 0, 1) WITH NOWAIT; END;
            SET @stopper = 1;
            BREAK;
        END;
        IF @debug = 1 BEGIN RAISERROR('Ended WHILE loop', 0, 1) WITH NOWAIT; END;
    END;
    IF @debug = 1 BEGIN RAISERROR('Ended cursor', 0, 1) WITH NOWAIT; END;

    /*get rid of some messages we don't care about*/
    IF @debug = 1 BEGIN RAISERROR('Delete dumb messages', 0, 1) WITH NOWAIT; END;

    DELETE
        el WITH(TABLOCKX)
    FROM #error_log AS el
    WHERE el.text LIKE N'DBCC TRACEON 3604%'
    OR    el.text LIKE N'DBCC TRACEOFF 3604%'
    OR    el.text LIKE N'This instance of SQL Server has been using a process ID of%'
    OR    el.text LIKE N'Could not connect because the maximum number of ''1'' dedicated administrator connections already exists%'
    OR    el.text LIKE N'Login failed%'
    OR    el.text LIKE N'Backup(%'
    OR    el.text LIKE N'[[]INFO]%'
    OR    el.text LIKE N'[[]DISK_SPACE_TO_RESERVE_PROPERTY]%'
    OR    el.text LIKE N'[[]CFabricCommonUtils::GetFabricPropertyInternalWithRef]%'
    OR    el.text LIKE N'CHECKDB for database % finished without errors%'
    OR    el.text LIKE N'Parallel redo is shutdown for database%'
    OR    el.text LIKE N'%This is an informational message only. No user action is required.%'
    OR    el.text LIKE N'%SPN%'
    OR    el.text LIKE N'Service Broker manager has started.%'
    OR    el.text LIKE N'Parallel redo is started for database%'
    OR    el.text LIKE N'Starting up database%'
    OR    el.text LIKE N'Buffer pool extension is already disabled%'
    OR    el.text LIKE N'Buffer Pool: Allocating % bytes for % hashPages.'
    OR    el.text LIKE N'The client was unable to reuse a session with%'
    OR    el.text LIKE N'SSPI%'
    OR    el.text LIKE N'%Severity: 1[0-8]%'
    OR    el.text LIKE N'Login succeeded for user%'
    OR    el.text IN
          (
              N'The Database Mirroring endpoint is in disabled or stopped state.',
              N'The Service Broker endpoint is in disabled or stopped state.'
          )
    OPTION(RECOMPILE);

    /*get rid of duplicate messages we don't care about*/
    IF @debug = 1 BEGIN RAISERROR('Delete dupe messages', 0, 1) WITH NOWAIT; END;

    WITH
        d AS
    (
        SELECT
            el.*,
            n =
                ROW_NUMBER() OVER
                (
                    PARTITION BY
                        el.log_date,
                        el.process_info,
                        el.text
                    ORDER BY
                        el.log_date
                )
        FROM #error_log AS el
    )
    DELETE
        d
    FROM d AS d WITH (TABLOCK)
    WHERE d.n > 1;

    /*Return the search results*/
    SELECT
        table_name =
            '#error_log',
        el.*
    FROM #error_log AS el
    ORDER BY
        el.log_date DESC
    OPTION(RECOMPILE);

    /*If we hit any errors, show which searches failed here*/
    IF EXISTS
    (
        SELECT
            1/0
        FROM #errors AS e
    )
    BEGIN
        SELECT
            table_name =
                '#errors',
            e.*
        FROM #errors AS e
        ORDER BY
            e.id
        OPTION(RECOMPILE);
    END;
END;
GO
