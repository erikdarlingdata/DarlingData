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

This script can be used to create a nightly statistics update job, utilizing Ola's IndexOptimize stored procedure.

Things you may need to change:
 * Targets the master database
 * Job is owned by sa
 * Scheduled for every night at midnight
 * You need to do your own setup for failure emails and alerting

To use it, you do need the most up to date version:
 * https://ola.hallengren.com/downloads.html
 * This script utilizes the @StatisticsModificationLevel parameter, added 2018-06-16
 * This parameter is currently set to 5, and you may need to change that based on your environment

If you're using a version older than that, I feel sorry for your mother.

Ola's scripts and licensing information is available here:
 * https://github.com/olahallengren/sql-server-maintenance-solution

Copyright (c) 2024 Darling Data, LLC
https://www.erikdarling.com/

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction,
including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

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
    @schedule_uid nvarchar(36) = NEWID();


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
    @job_name = N'IndexOptimize - STATISTICS_ONLY',
    @enabled = 1,
    @notify_level_eventlog = 0,
    @notify_level_email = 0,
    @notify_level_netsend = 0,
    @notify_level_page = 0,
    @delete_level = 0,
    @description = N'Will use Ola Hallengren''s IndexOptimize procedure to update statistics without rebuilding or reorganizing indexes, care of Darling Data, LLC. https://www.erikdarling.com/',
    @category_name = N'[Uncategorized (Local)]',
    @owner_login_name = N'sa',
    @job_id = @jobId OUTPUT;

IF (@@ERROR <> 0 OR @ReturnCode <> 0)
    GOTO QuitWithRollback;

EXEC @ReturnCode = msdb.dbo.sp_add_jobstep
    @job_id = @jobId,
    @step_name = N'Update Statistics',
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
    @command = N'EXECUTE dbo.IndexOptimize @Databases = ''USER_DATABASES'', @FragmentationLow = NULL, @FragmentationMedium = NULL, @FragmentationHigh = NULL, @UpdateStatistics = ''ALL'', @StatisticsModificationLevel = 5, @MinNumberOfPages = 50000, @LogToTable = ''Y'';',
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
    @name = N'Nightly Statistics Update',
    @enabled = 1,
    @freq_type = 4,
    @freq_interval = 1,
    @freq_subday_type = 1,
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
