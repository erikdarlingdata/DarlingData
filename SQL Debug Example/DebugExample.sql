/*

Copyright 2024 Darling Data, LLC
https://www.erikdarling.com/

*/

CREATE OR ALTER PROCEDURE
    dbo.DebugExample
(
    @debug_logic bit = 0,
    @debug_performance bit = 0,
    @execute_sql bit = 1
)
AS
BEGIN
/*
This is good to set on, because you don't need 
to see this output unless you're debugging a problem.
*/
SET NOCOUNT ON;


/*
This should be on 99% of the time, when you're okay
with the whole procedure failing when you hit one error
*/
SET XACT_ABORT ON;


/*
These are some declared variables that we're going to use
later on in the procedure at various points
*/
DECLARE
    @s nvarchar(MAX) =
        CONVERT
        (
            nvarchar(MAX),
            N'SELECT x = '
        ) +
        REPLICATE('A', 4000) +
        REPLICATE('B', 4000), /*Faked long dynamic SQL*/
    @len int = 0, /*Used to hold the length of the faked long dynamic SQL*/
    @block int = 1, /*Used for the dynamic SQL print loop*/
    @block_size int = 200, /*Same as above*/
    @rowcount_big bigint, /*Used to hold row counts from queries*/
    @low_id int = 0, /*Loop debugging stuff*/
    @high_id int = 0, /*Loop debugging stuff*/
    @total bigint = 0, /*Loop debugging stuff*/
    @current_id int = 0, /*Loop debugging stuff*/
    @loop_count int = 1, /*Loop debugging stuff*/
    @start_time datetime2 = NULL, /*Query timing stuff*/
    @edition sysname = NULL; /*A set variable example for later*/

    
    /*
    We're going to set this to a "dynamic" value
    meaning it might be different depending on
    where you run it.

    When we show this value later as part of the
    debugging process, it's nice to know what this
    ends up as, because we may make code path decisions
    based on this value throughout the procedure.
    */
    SELECT 
        @edition = 
             CONVERT
             (
                 sysname,
                 SERVERPROPERTY('Edition')
             );


/*
Sometimes you want to know which query is running.
If you're using dynamic SQL, you can do this, or print
the command out for debugging. But there's no way to print
a non-dynamic query like this. So we just tell ourselves
where we are.
*/
IF @debug_logic = 1
BEGIN
    RAISERROR('selecting from sys.databases', 0, 1) WITH NOWAIT;
END;

SELECT
    d.database_id
INTO #d
FROM sys.databases AS d;

SELECT
    @rowcount_big = ROWCOUNT_BIG();


/*
This will tell us how many rows we got out of sys.databases, using
raiserror with a substitution wildcard in the message. For regular integers,
you can use %i, %u, or %d, but bigger integers need to use %I64d.

The alternative is ugly:
    DECLARE 
        @msg nvarchar(MAX) = N'';
    
    SELECT
        @msg = N'there were ' + CONVERT(nvarchar(11), ROWCOUNT_BIG()) + N' rows in sys.databases';
    
    PRINT @msg;
*/
IF @debug_logic = 1
BEGIN
    RAISERROR('there were %I64d rows in sys.databases', 0, 1, @rowcount_big) WITH NOWAIT;
END;


/*
When we want to know what's actually in a temp table,
we should look at a couple things:
 * If there's anything in the table, show the data
 * Add a column to the results to tell us which table
   we're selecting from at this point in the procedure
 * If there's nothing in the table, raise a message
   to tell users so they know which table is empty
*/
IF @debug_logic = 1
BEGIN
    IF EXISTS
    (
        SELECT
            1/0
        FROM #d AS d
    )
    BEGIN
        SELECT
            table_name = '#d',
            d.*
        FROM #d AS d;
    END;
    ELSE
    BEGIN
        SELECT
            info = '#d is empty!';
    END;
END;


/*
Let's say we have a long dynamic statement we need to print
We'll want to:
 * Validate the length of the string
 * Print the string out in allowed lengths
 * In real life, you'd want to format the query
   and just print out ~4000 character blocks, but
   here I'm want nice tidy rectangles for the example.

HelperLongPrint: https://www.codeproject.com/articles/18881/sql-string-printing
*/
IF @debug_logic = 1
BEGIN
    SELECT
        @len = LEN(@s);

    RAISERROR('total length for %s is %i', 0, 1, N'@s', @len) WITH NOWAIT;
   
    WHILE @block < @len
    BEGIN
        PRINT SUBSTRING(@s, @block, @block_size);
       
        SELECT
            @block += @block_size -1;
    END;

    /*
    If you need to do this again, make sure to set @block back to zero
    */
END;


/*
If we're okay with executing the dynamic SQL, we
can go into this block and do that here
*/
IF @execute_sql = 1
BEGIN
    EXEC sys.sp_executesql
        @s;
END;


/*
Loop example!
 * I'm using this cursor type for very specific reasons.
 * I don't want to make another copy of the temp table in the cursor
 * Most of the time I'll use LOCAL STATIC, but it doesn't make sense
   for me to use that here for this reason
*/
IF @debug_logic = 1
BEGIN
    RAISERROR('starting cursor loop, setting ids', 0, 1) WITH NOWAIT;
END;

SELECT
    @low_id = MIN(d.database_id),
    @high_id = MAX(d.database_id),
    @total = COUNT_BIG(*)
FROM #d AS d;


/*
Get some loop feedback at the beginning
so we know what we're starting with
*/
IF @debug_logic = 1
BEGIN
    RAISERROR('starting loop with low id: %i', 0, 1, @low_id) WITH NOWAIT;
    RAISERROR('starting loop with high id: %i', 0, 1, @high_id) WITH NOWAIT;
    RAISERROR('starting loop with %I64d total entries', 0, 1, @total) WITH NOWAIT;
END;

/*
Open cursor
*/
DECLARE
    c
CURSOR
    LOCAL 
    SCROLL 
    DYNAMIC 
    READ_ONLY
FOR
SELECT
    d.database_id
FROM #d AS d;

OPEN c;

FETCH FIRST
FROM c
INTO @current_id;

IF @debug_logic = 1
BEGIN
    RAISERROR('entering cursor loop', 0, 1) WITH NOWAIT;
END;

WHILE @@FETCH_STATUS = 0
BEGIN
    IF @debug_logic = 1
    BEGIN
        RAISERROR('id %i of %i, out of %I64d. current id: %i', 0, 1, @loop_count, @high_id, @total, @current_id) WITH NOWAIT;
    END;

    IF @debug_logic = 1
    BEGIN
        RAISERROR('fetching next', 0, 1) WITH NOWAIT;
    END;

    FETCH NEXT 
    FROM c
    INTO @current_id;

    IF @debug_logic = 1
    BEGIN
        RAISERROR('incrementing loop', 0, 1) WITH NOWAIT;
        SELECT
            @loop_count += 1;
    END;
END;

/*
Get some loop feedback at the end
so we know what we ended with: Did we miss anything?
*/
IF @debug_logic = 1
BEGIN
    RAISERROR('finished loop with low id: %i', 0, 1, @low_id) WITH NOWAIT;
    RAISERROR('finished loop with high id: %i', 0, 1, @high_id) WITH NOWAIT;
    RAISERROR('finished loop with %I64d total entries', 0, 1, @total) WITH NOWAIT;
END;




/*
If we know there are more important/problem queries
we can get query plans specifically for those instead
of having to get query plans for absolutely everything

If you only want to troubleshoot performance, read this:
https://erikdarling.com/how-to-use-sp_humanevents-to-troubleshoot-a-slow-stored-procedure/
*/
IF @debug_performance = 1
BEGIN
    SELECT
        @start_time = SYSDATETIME();
    
    SELECT
        query = 'start: querying system health data',
        start_time = @start_time,
        query_ms = 0;
    SET STATISTICS XML ON;
END;

    SELECT
        x =
            ISNULL
            (
                TRY_CAST(t.target_data AS xml),
                CONVERT(xml, N'<event>event</event>')
            )
    INTO #x
    FROM sys.dm_xe_session_targets AS t
    JOIN sys.dm_xe_sessions AS s
      ON s.address = t.event_session_address
    WHERE s.name = N'system_health'
    AND   t.target_name = N'ring_buffer'
    OPTION(RECOMPILE);

IF @debug_performance = 1
BEGIN
    SET STATISTICS XML OFF;
    SELECT
        query = 'finish: querying system health data',
        end_time = SYSDATETIME(),
        query_ms = 
            FORMAT
            (
                DATEDIFF
                (
                    MILLISECOND, 
                    @start_time, 
                    SYSDATETIME()
                ), 
                'N0'
            );
END;

/*
The table thing again!
*/
IF @debug_logic = 1
BEGIN
    IF EXISTS
    (
        SELECT
            1/0
        FROM #x AS x
    )
    BEGIN
        SELECT
            table_name = '#x',
            x.*
        FROM #x AS x;
    END;
    ELSE
    BEGIN
        SELECT
            info = '#x is empty!';
    END;
END;


/*
Be careful with error handling.
You might be swallowing them without
knowing it, and that can make troubleshooting
really difficult when your code ends unexpectedly
*/
BEGIN TRY
    SELECT
        x = 1/0;
END TRY
BEGIN CATCH
    --THROW;
/*
This isn't really about error handling, for that go see:
https://sommarskog.se/error_handling/Part1.html
*/
END CATCH;


/*
In this section, we list out the final state
of the parameters and variables in the stored procedure

It doesn't do anything magical here, but in code where
you may modify parameter and variable values throughout
the code, it makes a lot more sense.
*/
IF @debug_logic = 1
BEGIN
    SELECT
        parameter_values = 
            'parameter values',
        debug_logic = 
            @debug_logic,
        debug_performance = 
            @debug_performance,
        execute_sql = 
            @execute_sql;

    SELECT
        variable_values =
            'variable_values',
        s = 
            @s,
        [len] = 
            @len,
        [block] = 
            @block,
        block_size = 
            @block_size,
        rowcount_big = 
            @rowcount_big,
        low_id = 
            @low_id,
        high_id = 
            @high_id,
        total = 
            @total,
        current_id =
            @current_id,
        loop_count = 
            @loop_count,
        edition = 
            @edition;
END;
/*
Final end!
I usually make this note here to make BEGIN/END match
troubleshooting a lot easier, because I really hate that
*/
END;
GO

EXEC dbo.DebugExample
    @debug_logic = 1,
    @debug_performance = 1,
    @execute_sql = 0;