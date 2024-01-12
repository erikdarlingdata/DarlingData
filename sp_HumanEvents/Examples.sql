/*
Copyright 2024 Darling Data, LLC
https://www.erikdarling.com/

For support, head over to GitHub:
https://github.com/erikdarlingdata/DarlingData

MIT License    
    
Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"),     
to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute,    
sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the     
following conditions:    
    
The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.    
    
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE     
FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION     
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.  
*/

-- Here are some example calls to get you started.

-- To capture all types of “completed” queries that have run for at least one second, for 20 seconds, from a specific database

EXEC dbo.sp_HumanEvents
    @event_type = 'query',
    @query_duration_ms = 1000,
    @seconds_sample = 20,
    @database_name = 'YourMom';

-- Maybe you want to filter out queries that have asked for a bit of memory:

EXEC dbo.sp_HumanEvents
    @event_type = 'query',
    @query_duration_ms = 1000,
    @seconds_sample = 20,
    @requested_memory_mb = 1024;

-- Or maybe you want to find unparameterized queries from a poorly written app that constructs strings in ugly ways, but it generates a lot of queries so you only want data on about a third of them.

EXEC dbo.sp_HumanEvents
    @event_type = 'compilations',
    @client_app_name = N'GL00SNIFЯ',
    @session_id = 'sample',
    @sample_divisor = 3;

-- Perhaps you think queries recompiling are the cause of your problems! Heck, they might be. Have you tried removing recompile hints? 😁

EXEC dbo.sp_HumanEvents
    @event_type = 'recompilations',
    @seconds_sample = 30;

-- Look, blocking is annoying. Just turn on RCSI, you goblin. Unless you’re not allowed to.

EXEC dbo.sp_HumanEvents
    @event_type = 'blocking',
    @seconds_sample = 60,
    @blocking_duration_ms = 5000;

-- If you want to track wait stats, this’ll work pretty well. Keep in mind “all” is a focused list of “interesting” waits to queries, not every wait stat.

EXEC dbo.sp_HumanEvents
    @event_type = 'waits',
    @wait_duration_ms = 10,
    @seconds_sample = 100,
    @wait_type = N'all';

-- Note that THREADPOOL is SOS_WORKER in xe-land. why? I dunno.

EXEC dbo.sp_HumanEvents
    @event_type = 'waits',
    @wait_duration_ms = 100,
    @seconds_sample = 10,
    @wait_type = N'SOS_WORKER,RESOURCE_SEMAPHORE';

-- For some event types that allow you to set a minimum duration, I’ve set a default minimum to try to avoid you introducing a lot of observer overhead to the server. If you understand the potential danger here, or you’re just trying to test things, you need to use the @gimme_danger parameter. You would also use this if you wanted to set an impermanent session to run for longer than 10 minutes.

-- For example, if you run this command:

EXEC sp_HumanEvents
    @event_type = N'query',
    @query_duration_ms = 1;

-- You’ll see this message in the output:

-- Checking query duration filter
-- You chose a really dangerous value for @query_duration
-- If you really want that, please set @gimme_danger = 1, and re-run
-- Setting @query_duration to 500


-- You need to use this command instead:

EXEC sp_HumanEvents
    @event_type = N'query',
    @query_duration_ms = 1,
    @gimme_danger = 1;

--  Logging Data To Tables

-- First, you need to set up permanent sessions to collect data. You can use commands like these to do that, but I urge you to add some filters like above to cut down on the data collected. On busy servers, over-collection can cause performance issues.


EXEC sp_HumanEvents
    @event_type = N'compiles',
    @keep_alive = 1;

EXEC sp_HumanEvents
    @event_type = N'recompiles',
    @keep_alive = 1;


EXEC sp_HumanEvents
    @event_type = N'query',
    @keep_alive = 1;

EXEC sp_HumanEvents
    @event_type = N'waits',
    @keep_alive = 1;

EXEC sp_HumanEvents
    @event_type = N'blocking',
    @keep_alive = 1;


-- Once your sessions are set up, this is the command to tell sp_HumanEvents which database and schema to log data to.
-- Table names are created internally, so don’t worry about those.

EXEC sp_HumanEvents
    @output_database_name = N'YourDatabase',
    @output_schema_name = N'dbo';

-- Ideally, you’ll stick this in an Agent Job, so you don’t need to rely on an SSMS window being open all the time.
-- The job creation code linked is set to check in every 10 seconds, in case of errors.
-- Internally, this will run in its own loop with a WAITFOR of 5 seconds to flush data out.


-- Part of what gets installed when you log data to tables are some views in the same database.

-- You can check in on them like this:

/*Queries*/
SELECT TOP 1000 * FROM dbo.HumanEvents_Queries;
/*Waits*/
SELECT TOP 1000 * FROM dbo.HumanEvents_WaitsByQueryAndDatabase;
SELECT TOP 1000 * FROM dbo.HumanEvents_WaitsByDatabase;
SELECT TOP 1000 * FROM dbo.HumanEvents_WaitsTotal;
/*Blocking*/
SELECT TOP 1000 * FROM dbo.HumanEvents_Blocking;
/*Compiles, only on newer versions of SQL Server*/
SELECT TOP 1000 * FROM dbo.HumanEvents_CompilesByDatabaseAndObject;
SELECT TOP 1000 * FROM dbo.HumanEvents_CompilesByQuery;
SELECT TOP 1000 * FROM dbo.HumanEvents_CompilesByDuration;
/*Otherwise*/
SELECT TOP 1000 * FROM dbo.HumanEvents_Compiles_Legacy;
/*Parameterization data, if available (comes along with compiles)*/
SELECT TOP 1000 * FROM dbo.HumanEvents_Parameterization;
/*Recompiles, only on newer versions of SQL Server*/
SELECT TOP 1000 * FROM dbo.HumanEvents_RecompilesByDatabaseAndObject;
SELECT TOP 1000 * FROM dbo.HumanEvents_RecompilesByQuery;
SELECT TOP 1000 * FROM dbo.HumanEvents_RecompilesByDuration;
/*Otherwise*/
SELECT TOP 1000 * FROM dbo.HumanEvents_Recompiles_Legacy;
