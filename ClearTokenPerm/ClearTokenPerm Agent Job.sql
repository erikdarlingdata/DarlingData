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
    WHERE name = N'[Uncategorized (Local)]'
    AND   category_class = 1
)
BEGIN

    EXEC @ReturnCode = msdb.dbo.sp_add_category
        @class = N'JOB',
        @type = N'LOCAL',
        @name = N'[Uncategorized (Local)]';

    IF (@@ERROR <> 0 OR @ReturnCode <> 0)
        GOTO QuitWithRollback;

END;


EXEC @ReturnCode = msdb.dbo.sp_add_job
    @job_name = N'Clear Security Cache Every 30 Minutes',
    @enabled = 1,
    @notify_level_eventlog = 0,
    @notify_level_email = 0,
    @notify_level_netsend = 0,
    @notify_level_page = 0,
    @delete_level = 0,
    @description = N'For background on why you need this:
https://www.erikdarlingdata.com/troubleshooting-security-cache-issues-userstore_tokenperm-and-tokenandpermuserstore/

Copyright 2022 Darling Data, LLC
https://www.erikdarlingdata.com/

For support, head over to GitHub:
https://github.com/erikdarlingdata/DarlingData',
    @category_name = N'[Uncategorized (Local)]',
    @owner_login_name = N'sa',
    @job_id = @jobId OUTPUT;

IF (@@ERROR <> 0 OR @ReturnCode <> 0)
    GOTO QuitWithRollback;

EXEC @ReturnCode = msdb.dbo.sp_add_jobstep
    @job_id = @jobId,
    @step_name = N'Execute dbo.ClearTokenPerm',
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
    @command = N'EXEC dbo.ClearTokenPerm
    @CacheSizeGB = 1;',
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
    @job_id = @jobId,
    @name = N'Clear Security Cache Every 30 Minutes',
    @enabled = 1,
    @freq_type = 4,
    @freq_interval = 1,
    @freq_subday_type = 8,
    @freq_subday_interval = 30,
    @freq_relative_interval = 0,
    @freq_recurrence_factor = 0,
    @active_start_date = @active_start_date,
    @active_end_date = 99991231,
    @active_start_time = 0,
    @active_end_time = 235959,
    @schedule_uid = N'b9dca576-7d86-4120-8f04-b666139677d6';

IF (@@ERROR <> 0 OR @ReturnCode <> 0)
    GOTO QuitWithRollback;

EXEC @ReturnCode = msdb.dbo.sp_add_jobserver
    @job_id =
    @jobId,
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
