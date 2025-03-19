USE msdb;
GO

/*
Remember to scroll down and replace the database and schema names you want to use.
(Line 65 or so)
*/

/*
Copyright 2025 Darling Data, LLC
https://www.erikdarling.com/

For support, head over to GitHub:
https://code.erikdarling.com

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


BEGIN TRANSACTION;
DECLARE
    @ReturnCode integer = 0,
    @jobId binary(16),
    @active_start_date int = (SELECT CONVERT(integer, CONVERT(varchar(35), GETDATE(), 112))),
    @schedule_uid nvarchar(36) = NEWID();


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

EXEC @ReturnCode = msdb.dbo.sp_add_job @job_name = N'sp_HumanEvents Logging',
        @enabled = 1,
        @notify_level_eventlog = 0,
        @notify_level_email = 0,
        @notify_level_netsend = 0,
        @notify_level_page = 0,
        @delete_level = 0,
        @description = N'Used to log sp_HumanEvents session data to permanent tables.',
        @category_name = N'Data Collector',
        @owner_login_name = N'sa',
        @job_id = @jobId OUTPUT;

IF (@@ERROR <> 0 OR @ReturnCode <> 0)
    GOTO QuitWithRollback;

EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id = @jobId, @step_name = N'Log sp_HumanEvents To Tables',
        @step_id = 1,
        @cmdexec_success_code = 0,
        @on_success_action = 1,
        @on_success_step_id = 0,
        @on_fail_action = 2,
        @on_fail_step_id = 0,
        @retry_attempts = 0,
        @retry_interval = 0,
        @os_run_priority = 0, @subsystem = N'TSQL',                   /* R E P L A C E - T H E S E - P L E A S E*/
        @command = N'EXEC sp_HumanEvents @output_database_name = N''YourDatabase'', @output_schema_name = N''dbo'';',
        @database_name = N'master',
        @flags = 4;

IF (@@ERROR <> 0 OR @ReturnCode <> 0)
    GOTO QuitWithRollback;

EXEC @ReturnCode = msdb.dbo.sp_update_job
    @job_id = @jobId,
    @start_step_id = 1;

IF (@@ERROR <> 0 OR @ReturnCode <> 0)
    GOTO QuitWithRollback;

EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id = @jobId, @name = N'sp_HumanEvents: 10 second Check In',
        @enabled = 1,
        @freq_type = 8,
        @freq_interval = 1,
        @freq_subday_type = 1,
        @freq_subday_interval = 0,
        @freq_relative_interval = 0,
        @freq_recurrence_factor = 1,
        @active_start_date = @active_start_date,
        @active_end_date = 99991231,
        @active_start_time = 0,
        @active_end_time = 235959,
        @schedule_uid = @schedule_uid;

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
