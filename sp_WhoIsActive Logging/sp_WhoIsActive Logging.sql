/*

Copyright 2022 Darling Data, LLC
https://www.erikdarlingdata.com/

This will log sp_WhoIsActive to a table.
It will create a new table every day,
so you don''t have a gigantic table to sift through 
forever and ever or until your drive fills up.

If you need to get or update sp_WhoIsActive: 
https://github.com/amachanic/sp_whoisactive
(C) 2007-2022, Adam Machanic

If you get an error message that @get_memory_info
isn't a valid parameter, that's a pretty good
sign you need to update.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR 
OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR 
OTHER DEALINGS IN THE SOFTWARE.

*/

USE msdb;
GO

BEGIN TRANSACTION;

DECLARE 
    @ReturnCode int = 0,
    @jobId binary(16),
    @active_start_date int = (SELECT CONVERT(int, CONVERT(varchar(35), GETDATE(), 112)));


IF NOT EXISTS 
(
    SELECT
        1/0
    FROM msdb.dbo.syscategories 
    WHERE name = N'Data Collector' 
    AND   category_class = 1
)
BEGIN

    EXEC @ReturnCode = msdb.dbo.sp_add_category 
        @class = N'JOB', 
        @type = N'LOCAL', 
        @name = N'Data Collector';
    
    IF (@@ERROR <> 0 OR @ReturnCode <> 0) 
        GOTO QuitWithRollback;

END;


EXEC @ReturnCode =  msdb.dbo.sp_add_job 
        @job_name = N'Log sp_WhoIsActive To A Daily Table', 
        @enabled = 1, 
        @notify_level_eventlog = 0, 
        @notify_level_email = 0, 
        @notify_level_netsend = 0, 
        @notify_level_page = 0, 
        @delete_level = 0, 
        @description = N'Copyright 2022 Darling Data, LLC
https://www.erikdarlingdata.com/

This will log sp_WhoIsActive to a table.
It will create a new table every day,
so you don''t have a gigantic table to sift through 
forever and ever or until your drive fills up.

If you need to get or update sp_WhoIsActive: 
https://github.com/amachanic/sp_whoisactive
(C) 2007-2022, Adam Machanic

If you get an error message that @get_memory_info
isn''t a valid parameter, that''s a pretty good
sign you need to update.', 
        @category_name = N'Data Collector', 
        @owner_login_name = N'sa', 
        @job_id = @jobId OUTPUT;

IF (@@ERROR <> 0 OR @ReturnCode <> 0) 
    GOTO QuitWithRollback;


EXEC @ReturnCode = msdb.dbo.sp_add_jobstep 
    @job_id = @jobId, 
    @step_name = N'Log sp_WhoIsActive To A Daily Table', 
    @step_id = 1, 
    @cmdexec_success_code = 0, 
    @on_success_action = 1, 
    @on_success_step_id = 0, 
    @on_fail_action = 2, 
    @on_fail_step_id = 0, 
    @retry_attempts = 0, 
    @retry_interval = 0, 
    @os_run_priority = 0, 
    @subsystem = N'TSQL', 
    @command = N'/*
SQL Agent has some weird settings.
This sets them to the correct ones.
*/
SET 
    NOCOUNT, 
    XACT_ABORT,
    ANSI_NULLS,
    ANSI_PADDING,
    ANSI_WARNINGS,
    ARITHABORT,
    CONCAT_NULL_YIELDS_NULL,
    QUOTED_IDENTIFIER
ON;

/*
Variables we know and love.

If you have weird date settings you might need to change the replace character below.
*/
DECLARE
    @destination_table sysname = 
        N''WhoIsActive_'' +
        REPLACE
        (
            CONVERT
            (
                date,
                GETDATE()
            ),
            ''-'',
            ''''
        ),
    @destination_schema sysname = 
        N''dbo'',
    @destination_database sysname = 
        N''master'',
    @parameters nvarchar(MAX)  = 
        N''@destination_table sysname'',
    @schema nvarchar(MAX) = 
        N'''';

/*
Some assembly required
*/
SELECT
    @destination_table = 
        QUOTENAME(@destination_database) + 
        N''.'' + 
        QUOTENAME(@destination_schema) + 
        N''.'' + 
        QUOTENAME(@destination_table);

/*
Create the table for logging.
*/
IF OBJECT_ID(@destination_table) IS NULL
BEGIN;

    EXEC sp_WhoIsActive
        @get_transaction_info = 1,
        @get_outer_command = 1,
        @get_plans = 1,
        @get_task_info = 2,
        @get_additional_info = 1,
        @find_block_leaders = 1,
        @get_memory_info = 1,
        @return_schema = 1,
        @schema = @schema OUTPUT;

    SELECT 
        @schema = 
            REPLACE
            (
                @schema, 
                N''<table_name>'', 
                @destination_table
            );

    EXEC sys.sp_executesql
        @schema;

END;

/*
This logs to the table.
*/
EXEC sp_WhoIsActive
    @get_transaction_info = 1,
    @get_outer_command = 1,
    @get_plans = 1,
    @get_task_info = 2,
    @get_additional_info = 1,
    @find_block_leaders = 1,
    @get_memory_info = 1,
    @destination_table = @destination_table;', 
    @database_name = N'master', 
    @flags = 0;

IF (@@ERROR <> 0 OR @ReturnCode <> 0) 
    GOTO QuitWithRollback;
    
    EXEC @ReturnCode = msdb.dbo.sp_update_job 
        @job_id = @jobId, 
        @start_step_id = 1;

IF (@@ERROR <> 0 OR @ReturnCode <> 0) 
    GOTO QuitWithRollback;
    
    EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule 
        @job_id = @jobId, @name = N'Log sp_WhoIsActive To A Daily Table Every Minute', 
        @enabled = 1, 
        @freq_type = 4, 
        @freq_interval = 1, 
        @freq_subday_type = 4, 
        @freq_subday_interval = 1, 
        @freq_relative_interval = 0, 
        @freq_recurrence_factor = 0, 
        @active_start_date = @active_start_date, 
        @active_end_date = 99991231, 
        @active_start_time = 0, 
        @active_end_time = 235959, 
        @schedule_uid = N'eb778522-86e7-4c47-8f7c-efadc7e22f9d';

IF (@@ERROR <> 0 OR @ReturnCode <> 0) 
    GOTO QuitWithRollback;
    
    EXEC @ReturnCode = msdb.dbo.sp_add_jobserver 
        @job_id = @jobId, 
        @server_name = N'(local)';

IF (@@ERROR <> 0 OR @ReturnCode <> 0) 
    GOTO QuitWithRollback;
    
    COMMIT TRANSACTION;

GOTO EndSave;

QuitWithRollback:
    IF (@@TRANCOUNT > 0) 
        ROLLBACK TRANSACTION;

EndSave:
GO
