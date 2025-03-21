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

Copyright 2025 Darling Data, LLC
https://www.erikdarling.com/

This will log sp_WhoIsActive to a table.
It will create a new table every day,
so you don''t have a gigantic table to sift through
forever and ever or until your drive fills up.

If you need to get or update sp_WhoIsActive:
https://github.com/amachanic/sp_whoisactive
(C) 2007-2024, Adam Machanic

If you get an error message that @get_memory_info
isn't a valid parameter, that's a pretty good
sign you need to update.

To change the table retention period from 10 days, edit the below declare statement.

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
    @active_start_date int = (SELECT CONVERT(int, CONVERT(varchar(35), GETDATE(), 112))),
    @schedule_uid nvarchar(36) = NEWID(),
    @RetentionPeriod nvarchar(10) = N'10';

DECLARE
    @command nvarchar(MAX) = N'EXECUTE dbo.sp_WhoIsActiveLogging_Main ' + @RetentionPeriod + N';'


IF NOT EXISTS
(
    SELECT
        1/0
    FROM msdb.dbo.syscategories
    WHERE name = N'Data Collector'
    AND   category_class = 1
)
BEGIN
    EXECUTE @ReturnCode = msdb.dbo.sp_add_category
        @class = N'JOB',
        @type = N'LOCAL',
        @name = N'Data Collector';

    IF (@@ERROR <> 0 OR @ReturnCode <> 0)
        GOTO QuitWithRollback;
END;


EXECUTE @ReturnCode =  msdb.dbo.sp_add_job
        @job_name = N'Log sp_WhoIsActive To A Daily Table',
        @enabled = 1,
        @notify_level_eventlog = 0,
        @notify_level_email = 0,
        @notify_level_netsend = 0,
        @notify_level_page = 0,
        @delete_level = 0,
        @description = N'Copyright 2022 Darling Data, LLC
https://www.erikdarling.com/

This will log sp_WhoIsActive to a table.
It will create a new table every day,
so you don''t have a gigantic table to sift through
forever and ever or until your drive fills up.

If you need to get or update sp_WhoIsActive:
https://github.com/amachanic/sp_whoisactive
(C) 2007-2024, Adam Machanic

If you get an error message that @get_memory_info
isn''t a valid parameter, that''s a pretty good
sign you need to update.',
        @category_name = N'Data Collector',
        @owner_login_name = N'sa',
        @job_id = @jobId OUTPUT;

IF (@@ERROR <> 0 OR @ReturnCode <> 0)
    GOTO QuitWithRollback;


EXECUTE @ReturnCode = msdb.dbo.sp_add_jobstep
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
    @command = @command,
    @database_name = N'master',
    @flags = 0;

IF (@@ERROR <> 0 OR @ReturnCode <> 0)
    GOTO QuitWithRollback;

    EXECUTE @ReturnCode = msdb.dbo.sp_update_job
        @job_id = @jobId,
        @start_step_id = 1;

IF (@@ERROR <> 0 OR @ReturnCode <> 0)
    GOTO QuitWithRollback;

    EXECUTE @ReturnCode = msdb.dbo.sp_add_jobschedule
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
        @schedule_uid = @schedule_uid;

IF (@@ERROR <> 0 OR @ReturnCode <> 0)
    GOTO QuitWithRollback;

    EXECUTE @ReturnCode = msdb.dbo.sp_add_jobserver
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
