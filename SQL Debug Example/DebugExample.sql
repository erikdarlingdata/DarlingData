/*
Copyright 2024 Darling Data, LLC
https://www.erikdarling.com/
*/

CREATE OR ALTER PROCEDURE dbo.DebugExample
(
    @debug_logic bit = 0,
    @debug_performance bit = 0,
    @execute_sql bit = 1
)
AS
BEGIN
    -- Suppress extra result sets to reduce network traffic
    SET NOCOUNT ON;

    -- Rollback a transaction if a T-SQL statement raises a runtime error
    SET XACT_ABORT ON;

    DECLARE
        @s nvarchar(MAX) = CONVERT(nvarchar(MAX), N'SELECT x = ') + REPLICATE('A', 4000) + REPLICATE('B', 4000),
        @len int = 0,
        @block int = 1,
        @block_size int = 200,
        @rowcount_big bigint,
        @low_id int = 0,
        @high_id int = 0,
        @total bigint = 0,
        @current_id int = 0,
        @loop_count int = 1,
        @start_time datetime2 = NULL,
        @edition sysname = NULL;

    -- Set the SQL Server edition
    SELECT @edition = CONVERT(sysname, SERVERPROPERTY('Edition'));

    -- Debug: Notify which query is running
    IF @debug_logic = 1
    BEGIN
        RAISERROR('selecting from sys.databases', 0, 1) WITH NOWAIT;
    END;

    -- Query to select from sys.databases
    SELECT d.database_id INTO #d FROM sys.databases AS d;
    SELECT @rowcount_big = ROWCOUNT_BIG();

    -- Debug: Output row count from sys.databases
    IF @debug_logic = 1
    BEGIN
        RAISERROR('there were %I64d rows in sys.databases', 0, 1, @rowcount_big) WITH NOWAIT;
    END;

    -- Debug: Check contents of temporary table #d
    IF @debug_logic = 1
    BEGIN
        IF EXISTS (SELECT 1 FROM #d AS d)
        BEGIN
            SELECT table_name = '#d', d.* FROM #d AS d;
        END
        ELSE
        BEGIN
            SELECT info = '#d is empty!';
        END;
    END;

    -- Debug: Print long dynamic SQL in manageable chunks
    IF @debug_logic = 1
    BEGIN
        SELECT @len = LEN(@s);
        RAISERROR('total length for %s is %i', 0, 1, N'@s', @len) WITH NOWAIT;

        WHILE @block < @len
        BEGIN
            PRINT SUBSTRING(@s, @block, @block_size);
            SELECT @block += @block_size - 1;
        END;
    END;

    -- Execute dynamic SQL if enabled
    IF @execute_sql = 1
    BEGIN
        EXEC sys.sp_executesql @s;
    END;

    -- Debug: Initialize and loop through cursor for sys.databases
    IF @debug_logic = 1
    BEGIN
        RAISERROR('starting cursor loop, setting ids', 0, 1) WITH NOWAIT;
    END;

    SELECT @low_id = MIN(d.database_id), @high_id = MAX(d.database_id), @total = COUNT_BIG(*) FROM #d AS d;

    -- Debug: Provide initial loop feedback
    IF @debug_logic = 1
    BEGIN
        RAISERROR('starting loop with low id: %i', 0, 1, @low_id) WITH NOWAIT;
        RAISERROR('starting loop with high id: %i', 0, 1, @high_id) WITH NOWAIT;
        RAISERROR('starting loop with %I64d total entries', 0, 1, @total) WITH NOWAIT;
    END;

    -- Declare and open cursor
    DECLARE c CURSOR LOCAL SCROLL DYNAMIC READ_ONLY FOR SELECT d.database_id FROM #d AS d;
    OPEN c;
    FETCH FIRST FROM c INTO @current_id;

    -- Debug: Enter cursor loop
    IF @debug_logic = 1
    BEGIN
        RAISERROR('entering cursor loop', 0, 1) WITH NOWAIT;
    END;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF @debug_logic = 1
        BEGIN
            RAISERROR('id %i of %i, out of %I64d. current id: %i', 0, 1, @loop_count, @high_id, @total, @current_id) WITH NOWAIT;
            RAISERROR('fetching next', 0, 1) WITH NOWAIT;
        END;

        FETCH NEXT FROM c INTO @current_id;

        IF @debug_logic = 1
        BEGIN
            RAISERROR('incrementing loop', 0, 1) WITH NOWAIT;
            SELECT @loop_count += 1;
        END;
    END;

    -- Debug: Provide final loop feedback
    IF @debug_logic = 1
    BEGIN
        RAISERROR('finished loop with low id: %i', 0, 1, @low_id) WITH NOWAIT;
        RAISERROR('finished loop with high id: %i', 0, 1, @high_id) WITH NOWAIT;
        RAISERROR('finished loop with %I64d total entries', 0, 1, @total) WITH NOWAIT;
    END;

    -- Performance debugging
    IF @debug_performance = 1
    BEGIN
        SELECT @start_time = SYSDATETIME();
        SELECT query = 'start: querying system health data', start_time = @start_time, query_ms = 0;
        SET STATISTICS XML ON;

        SELECT x = ISNULL(TRY_CAST(t.target_data AS xml), CONVERT(xml, N'<event>event</event>')) INTO #x
        FROM sys.dm_xe_session_targets AS t
        JOIN sys.dm_xe_sessions AS s ON s.address = t.event_session_address
        WHERE s.name = N'system_health' AND t.target_name = N'ring_buffer' OPTION (RECOMPILE);

        SET STATISTICS XML OFF;
        SELECT query = 'finish: querying system health data', end_time = SYSDATETIME(), query_ms = FORMAT(DATEDIFF(MILLISECOND, @start_time, SYSDATETIME()), 'N0');
    END;

    -- Debug: Check contents of temporary table #x
    IF @debug_logic = 1
    BEGIN
        IF EXISTS (SELECT 1 FROM #x AS x)
        BEGIN
            SELECT table_name = '#x', x.* FROM #x AS x;
        END
        ELSE
        BEGIN
            SELECT info = '#x is empty!';
        END;
    END;

    -- Error handling example
    BEGIN TRY
        SELECT x = 1/0;
    END TRY
    BEGIN CATCH
        --THROW;
    END CATCH;

    -- Debug: Output final state of parameters and variables
    IF @debug_logic = 1
    BEGIN
        SELECT parameter_values = 'parameter values', debug_logic = @debug_logic, debug_performance = @debug_performance, execute_sql = @execute_sql;
        SELECT variable_values = 'variable values', s = @s, [len] = @len, [block] = @block, block_size = @block_size, rowcount_big = @rowcount_big, low_id = @low_id, high_id = @high_id, total = @total, current_id = @current_id, loop_count = @loop_count, edition = @edition;
    END;
END;
GO

EXEC dbo.DebugExample @debug_logic = 1, @debug_performance = 1, @execute_sql = 0;
