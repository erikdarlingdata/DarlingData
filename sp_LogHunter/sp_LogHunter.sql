SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
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
    
Copyright 2023 Darling Data, LLC
https://www.erikdarlingdata.com/

For usage and licensing details, run:
EXEC sp_LogHunter
    @help = 1;

For working through errors:
EXEC sp_LogHunter
    @debug = 1;

For support, head over to GitHub:
https://github.com/erikdarlingdata/DarlingData

EXEC sp_LogHunter;

*/

CREATE OR ALTER PROCEDURE
    dbo.sp_LogHunter
(
    @days_back int = -7, /*How many days back you want to look in the error logs*/
    @custom_message nvarchar(4000) = NULL, /*If there's something you specifically want to search for*/
    @custom_message_only bit = 0, /*If you only want to search for this specific thing*/
    @language_id int = 1033, /*If you want to use a language other than English*/
    @first_log_only bit = 0, /*If you only want to search the first log file*/
    @help bit = 0, /*Get help*/
    @debug bit = 0, /*Prints messages and selects from temp tables*/
    @version varchar(30) = NULL OUTPUT,
    @version_date datetime = NULL OUTPUT
)
WITH RECOMPILE
AS
SET STATISTICS XML OFF;
SET NOCOUNT, XACT_ABORT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
BEGIN
    SELECT
        @version = '1b',
        @version_date = '20230701';

    IF @help = 1
    BEGIN
        SELECT
            introduction =
                'hi, i''m sp_LogHunter!' UNION ALL
        SELECT  'you can use me to look through your error logs for bad stuff' UNION ALL
        SELECT  'all scripts and documentation are available here: https://github.com/erikdarlingdata/DarlingData/tree/main/sp_LogHunter' UNION ALL
        SELECT  'from your loving sql server consultant, erik darling: https://erikdarlingdata.com';
    
        SELECT
            parameter_name =
                ap.name,
            data_type = t.name,
            description =
                CASE ap.name
                     WHEN N'@days_back' THEN 'how many days back you want to search the logs'
                     WHEN N'@custom_message' THEN 'if you want to search for a custom string'
                     WHEN N'@custom_message_only' THEN 'only search for the custom string'
                     WHEN N'@language_id' THEN 'to use something other than English'
                     WHEN N'@first_log_only' THEN 'only search through the first error log'
                     WHEN N'@help' THEN 'how you got here'
                     WHEN N'@debug' THEN 'dumps raw temp table contents'
                     WHEN N'@version' THEN 'OUTPUT; for support'
                     WHEN N'@version_date' THEN 'OUTPUT; for support'
                END,
            valid_inputs =
                CASE ap.name
                     WHEN N'@days_back' THEN 'an integer; will be converted to a negative number automatically'
                     WHEN N'@custom_message' THEN 'something specific you want to search for. no wildcards or substitions.'
                     WHEN N'@custom_message_only' THEN 'NULL, 0, 1'
                     WHEN N'@language_id' THEN 'SELECT DISTINCT m.language_id FROM sys.messages AS m ORDER BY m.language_id;'
                     WHEN N'@first_log_only' THEN 'NULL, 0, 1'
                     WHEN N'@help' THEN 'NULL, 0, 1'
                     WHEN N'@debug' THEN 'NULL, 0, 1'
                     WHEN N'@version' THEN 'OUTPUT; for support'
                     WHEN N'@version_date' THEN 'OUTPUT; for support'
                END,
            defaults =
                CASE ap.name
                     WHEN N'@days_back' THEN '-7'
                     WHEN N'@custom_message' THEN 'NULL'
                     WHEN N'@custom_message_only' THEN '0'
                     WHEN N'@language_id' THEN '1033'
                     WHEN N'@first_log_only' THEN '0'
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
    
    Copyright 2023 Darling Data, LLC
    
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
  
    /*Check if we're using RDS*/
    IF OBJECT_ID(N'rdsadmin.dbo.rds_read_error_log') IS NOT NULL
    BEGIN
       RAISERROR(N'This will not run on Amazon RDS with rdsadmin.dbo.rds_read_error_log because it doesn''t support search strings', 11, 1) WITH NOWAIT;
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
       RAISERROR(N'%i is not not a valid language_id in sys.messages.', 11, 1, @language_id) WITH NOWAIT;
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

    IF @debug = 1
    BEGIN
        SELECT
            DaysBack = @days_back;
    END;

    /*variables for the variable gods*/
    DECLARE
        @c nvarchar(4000),
        @l_log int = 0,
        @h_log int = 0,
        @t_searches int = 0,
        @l_count int = 1,
        @stopper bit = 0;
    
    /*temp tables for holding things*/
    CREATE TABLE
        #error_log
    (
        log_date datetime ,
        process_info nvarchar(100) ,
        text nvarchar(4000)
    ) ;
   
    CREATE TABLE
        #enum
    (
        archive int PRIMARY KEY,
        log_date date,
        log_size bigint
    );

    CREATE TABLE
        #search
    (
        id int IDENTITY PRIMARY KEY,
        search_string nvarchar(4000),
        days_back nvarchar(10),
        [current_date] nvarchar(10)
            DEFAULT N'"' + CONVERT(nvarchar(10), DATEADD(DAY, 1, SYSDATETIME()), 112) + N'"',
        search_order nvarchar(10)
            DEFAULT N'"DESC"',
        command AS
            CONVERT
            (
                nvarchar(4000),
                N'EXEC master.dbo.xp_readerrorlog [@@@], 1, '
                + search_string
                + N', '
                + N'" "'
                + N', '
                + days_back
                + N', '
                + [current_date]
                + N', '
                + search_order
                + N';'
            )
    );

    CREATE TABLE
        #errors
    (
        id int PRIMARY KEY IDENTITY,
        command nvarchar(4000)
    );

    /*get all the error logs*/
    INSERT
        #enum
    (
        archive,
        log_date,
        log_size
    )
    EXEC sys.sp_enumerrorlogs;

    IF @debug = 1 BEGIN SELECT table_name = '#enum before delete', e.* FROM #enum AS e; END;

    /*filter out log files we won't use*/
    DELETE 
        e WITH(TABLOCKX)
    FROM #enum AS e
    WHERE e.log_date < DATEADD(DAY, @days_back, SYSDATETIME())
    AND   e.archive > 0
    OPTION(RECOMPILE);

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
        days_back
    )
    SELECT
        x.search_string,
        c.days_back
    FROM
    (
        VALUES
            (N'"Microsoft SQL Server"'),
            (N'"detected"'),
            (N'"SQL Server has encountered"')
    ) AS x (search_string)
    CROSS JOIN
    (
        SELECT
            days_back =
                N'"' + CONVERT(nvarchar(10), DATEADD(DAY, CASE WHEN @days_back < 90 THEN 90 ELSE @days_back END, SYSDATETIME()), 112) + N'"'
    ) AS c
    WHERE @custom_message_only = 0
    OPTION(RECOMPILE);

    /*these are the search strings we currently care about*/
    INSERT
        #search
    (
        search_string,
        days_back
    )
    SELECT
        search_string =
            N'"' + v.search_string + N'"',
        c.days_back
    FROM
    (
        VALUES
            ('Fatal error'), ('corrupt'), ('insufficient'), ('SQL Server is shutting down'), ('DBCC CHECKDB'), ('Attempt to fetch logical page'),
            ('Wait for redo catchup for the database'), ('Restart the server to resolve this problem'), ('Error occurred'), ('running low'), ('unexpected'),
            ('fail'), ('contact'), ('This is a severe system-level error'), ('incorrect'), ('allocate'), ('allocation'), ('Timeout occurred'), ('memory manager'),
            ('operating system'), ('serious error'), ('Error while allocating'), ('cannot obtain a LOCK resource'), ('Server halted'), ('spawn'), ('Internal Error'),
            ('BobMgr'), ('Sort is retrying the read'), ('Shutting down SQL Server'), ('resumed'), ('repair the database'), ('buffer'), ('I/O Completion Port'),
            ('assert'), ('integrity'), ('latch'), ('Errors occurred during recovery while rolling back a transaction'), ('SQL Server is exiting'), ('SQL Server is unable to run'),
            ('Recovery is unable to defer error'), ('suspect'), ('restore the database'), ('checkpoint'), ('version store is full'), ('Setting database option'),
            ('Perform a restore if necessary'), ('Autogrow of file'), ('Bringing down database'), ('hot add'), ('Server shut down'), ('Customer Support Services'), ('stack overflow'),
            ('inconsistency.'), ('invalid'), ('time out occurred'), ('The transaction log for database'), ('The virtual log file sequence'), ('Cannot accept virtual log file sequence'),
            ('The transaction in database'), ('Shutting down the server'), ('Shutting down database'), ('Error releasing reserved log space'), ('Cannot load the Query Store metadata'),
            ('Cannot acquire'), ('SQL Server evaluation period has expired'), ('terminat'), ('SQL Server has been configured for lightweight pooling'), ('IOCP'),
            ('Not enough memory for the configured number of locks'), ('The tempdb database data files are not configured with the same initial size and autogrowth settings'),
            ('The SQL Server image'), ('affinity'), ('SQL Server is starting'), ('Ignoring trace flag '), ('20 physical cores'), ('System error'), ('No free space'),
            ('Warning ******************'), ('SQL Server should be restarted'), ('Server name is'), ('Could not connect'), ('yielding'), ('worker thread'), ('A new connection was rejected'), 
            ('A significant part of sql server process memory has been paged out'), ('Dispatcher'), ('I/O requests taking longer than'), ('killed'), ('SQL Server could not start'), 
            ('SQL Server cannot start'), ('System Manufacturer:'), ('columnstore'), ('timed out'), ('inconsistent'), ('flushcache'), ('Recovery for availability database'), ('currently busy'), 
            ('The service is experiencing a problem'), ('The service account is'), ('Total Log Writer threads'), ('thread pool'), ('debug'), ('resolving')  
    ) AS v (search_string)
    CROSS JOIN
    (
        SELECT
            days_back =
                N'"' + CONVERT(nvarchar(10), DATEADD(DAY, @days_back, SYSDATETIME()), 112) + N'"'
    ) AS c
    WHERE @custom_message_only = 0
    OPTION(RECOMPILE);   

    /*deal with a custom search string here*/
    INSERT
        #search
    (
        search_string,
        days_back
    )
    SELECT
        x.search_string,
        x.days_back
    FROM
    (
        VALUES
           (
                N'"' + @custom_message + '"',
                N'"' + CONVERT(nvarchar(10), DATEADD(DAY, @days_back, SYSDATETIME()), 112) + N'"'
           )
    ) AS x (search_string, days_back)
    WHERE @custom_message LIKE N'_%'
    OPTION(RECOMPILE);

    IF @debug = 1
    BEGIN
        SELECT table_name = '#search', s.* FROM #search AS s;
    END;
    
    SELECT
        @l_log = MIN(e.archive),
        @h_log = MAX(e.archive),
        @t_searches = (SELECT COUNT_BIG(*) FROM #search AS s)
    FROM #enum AS e
    OPTION(RECOMPILE);

    IF @debug = 1 BEGIN RAISERROR('Declaring cursor', 0, 1) WITH NOWAIT; END;

    IF @debug = 1
    BEGIN
        RAISERROR('@l_log: %i', 0, 1, @l_log) WITH NOWAIT;
        RAISERROR('@h_log: %i', 0, 1, @h_log) WITH NOWAIT;
        RAISERROR('@t_searches: %i', 0, 1, @t_searches) WITH NOWAIT;
    END;
   
    /*start the loops*/
    WHILE @l_log <= @h_log
    BEGIN
        DECLARE
            c
        CURSOR
            LOCAL
            STATIC
        FOR
        SELECT
            command
        FROM #search;
        
        IF @debug = 1 BEGIN RAISERROR('Opening cursor', 0, 1) WITH NOWAIT; END;
        OPEN c;
        
        FETCH NEXT
        FROM c
        INTO @c;

        IF @debug = 1 BEGIN RAISERROR('Entering WHILE loop', 0, 1) WITH NOWAIT; END;
        WHILE @@FETCH_STATUS = 0 AND @stopper = 0           
        BEGIN
            IF @debug = 1 BEGIN RAISERROR('Entering cursor', 0, 1) WITH NOWAIT; END;
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
                    INSERT
                        #error_log
                    (
                        log_date,
                        process_info,
                        text
                    )
                    EXEC sys.sp_executesql
                        @c;
                END TRY
                BEGIN CATCH
                    INSERT
                        #errors
                    (
                        command
                    )
                    VALUES
                    (
                        @c
                    );           
                END CATCH
            END;
           
            IF @debug = 1 BEGIN RAISERROR('Fetching next', 0, 1) WITH NOWAIT; END;
            FETCH NEXT
            FROM c
            INTO @c;

            SELECT
                @l_count += 1;

        END;
           
        IF @debug = 1 BEGIN RAISERROR('Getting next log', 0, 1) WITH NOWAIT; END;
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

        IF @l_log IS NULL
        BEGIN
            IF @debug = 1 BEGIN RAISERROR('Breaking', 0, 1) WITH NOWAIT; END;          
            SET @stopper = 1;
            BREAK;
        END;               
        IF @debug = 1 BEGIN RAISERROR('Ended WHILE loop', 0, 1) WITH NOWAIT; END;
   
        CLOSE c;
        DEALLOCATE c;
    END;
    IF @debug = 1 BEGIN RAISERROR('Ended cursor', 0, 1) WITH NOWAIT; END;

    /*get rid of some messages we don't care about*/
    DELETE
        el WITH(TABLOCKX)
    FROM #error_log AS el
    WHERE el.text LIKE N'DBCC TRACEON 3604%'
    OR    el.text LIKE N'DBCC TRACEOFF 3604%'
    OR    el.text LIKE N'This instance of SQL Server has been using a process ID of%'
    OR    el.text LIKE N'Could not connect because the maximum number of ''1'' dedicated administrator connections already exists%'
    OR    el.text LIKE N'Login failed for user%'
    OR    el.text  IN
          (
              N'The Database Mirroring endpoint is in disabled or stopped state.',
              N'The Service Broker endpoint is in disabled or stopped state.'
          )
    OPTION(RECOMPILE);
    
    SELECT
        table_name =
            '#error_log',
        el.*
    FROM #error_log AS el
    ORDER BY
        el.log_date DESC
    OPTION(RECOMPILE);

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
