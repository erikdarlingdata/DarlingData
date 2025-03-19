SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET STATISTICS TIME, IO OFF;
GO

/*

This script will set up alerts for high severity and corruption errors in SQL Server.

Copyright 2025 Darling Data, LLC
https://www.erikdarling.com/

For support, head over to GitHub:
https://code.erikdarling.com

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR
OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.

*/

USE [msdb];

/*
See that @operator_name variable below?
You're gonna wanna set that to one of these.
*/
SELECT
    s.*
FROM msdb..sysoperators AS s;

/*
If there's nothing in there, you'll wanna follow this guide to set one up:
https://social.technet.microsoft.com/wiki/contents/articles/51133.sql-server-alerts-and-email-operator-notifications.aspx
*/


/*
Once you do that, you can get rid of this RETURN and F5 the whole script.
*/

DECLARE
    @operator_name sysname  =  N'Who You Want To Notify';

RETURN;

EXECUTE msdb.dbo.sp_add_alert
    @name = N'Severity 019',
    @message_id = 0,
    @severity = 19,
    @enabled = 1,
    @delay_between_responses = 60,
    @include_event_description_in = 1,
    @job_id = N'00000000-0000-0000-0000-000000000000';

EXECUTE msdb.dbo.sp_add_notification
    @alert_name = N'Severity 019',
    @operator_name = @operator_name,
    @notification_method = 7;

EXECUTE msdb.dbo.sp_add_alert
    @name = N'Severity 020',
    @message_id = 0,
    @severity = 20,
    @enabled = 1,
    @delay_between_responses = 60,
    @include_event_description_in = 1,
    @job_id = N'00000000-0000-0000-0000-000000000000';

EXECUTE msdb.dbo.sp_add_notification
    @alert_name = N'Severity 020',
    @operator_name = @operator_name,
    @notification_method = 7;

EXECUTE msdb.dbo.sp_add_alert
    @name = N'Severity 021',
    @message_id = 0,
    @severity = 21,
    @enabled = 1,
    @delay_between_responses = 60,
    @include_event_description_in = 1,
    @job_id = N'00000000-0000-0000-0000-000000000000';

EXECUTE msdb.dbo.sp_add_notification
    @alert_name = N'Severity 021',
    @operator_name = @operator_name,
    @notification_method = 7;

EXECUTE msdb.dbo.sp_add_alert
    @name = N'Severity 022',
    @message_id = 0,
    @severity = 22,
    @enabled = 1,
    @delay_between_responses = 60,
    @include_event_description_in = 1,
    @job_id = N'00000000-0000-0000-0000-000000000000';

EXECUTE msdb.dbo.sp_add_notification
    @alert_name = N'Severity 022',
    @operator_name = @operator_name,
    @notification_method = 7;

EXECUTE msdb.dbo.sp_add_alert
    @name = N'Severity 023',
    @message_id = 0,
    @severity = 23,
    @enabled = 1,
    @delay_between_responses = 60,
    @include_event_description_in = 1,
    @job_id = N'00000000-0000-0000-0000-000000000000';

EXECUTE msdb.dbo.sp_add_notification
    @alert_name = N'Severity 023',
    @operator_name = @operator_name,
    @notification_method = 7;

EXECUTE msdb.dbo.sp_add_alert
    @name = N'Severity 024',
    @message_id = 0,
    @severity = 24,
    @enabled = 1,
    @delay_between_responses = 60,
    @include_event_description_in = 1,
    @job_id = N'00000000-0000-0000-0000-000000000000';

EXECUTE msdb.dbo.sp_add_notification
    @alert_name = N'Severity 024',
    @operator_name = @operator_name,
    @notification_method = 7;

EXECUTE msdb.dbo.sp_add_alert
    @name = N'Severity 025',
    @message_id = 0,
    @severity = 25,
    @enabled = 1,
    @delay_between_responses = 60,
    @include_event_description_in = 1,
    @job_id = N'00000000-0000-0000-0000-000000000000';

EXECUTE msdb.dbo.sp_add_notification
    @alert_name = N'Severity 025',
    @operator_name = @operator_name,
    @notification_method = 7;

EXECUTE msdb.dbo.sp_add_alert
    @name = N'Error Number 823',
    @message_id = 823,
    @severity = 0,
    @enabled = 1,
    @delay_between_responses = 60,
    @include_event_description_in = 1,
    @job_id = N'00000000-0000-0000-0000-000000000000';

EXECUTE msdb.dbo.sp_add_notification
    @alert_name = N'Error Number 823',
    @operator_name = @operator_name,
    @notification_method = 7;

EXECUTE msdb.dbo.sp_add_alert
    @name = N'Error Number 824',
    @message_id = 824,
    @severity = 0,
    @enabled = 1,
    @delay_between_responses = 60,
    @include_event_description_in = 1,
    @job_id = N'00000000-0000-0000-0000-000000000000';

EXECUTE msdb.dbo.sp_add_notification
    @alert_name = N'Error Number 824',
    @operator_name = @operator_name,
    @notification_method = 7;

EXECUTE msdb.dbo.sp_add_alert
    @name = N'Error Number 825',
    @message_id = 825,
    @severity = 0,
    @enabled = 1,
    @delay_between_responses = 60,
    @include_event_description_in = 1,
    @job_id = N'00000000-0000-0000-0000-000000000000';

EXECUTE msdb.dbo.sp_add_notification
    @alert_name = N'Error Number 825',
    @operator_name = @operator_name,
    @notification_method = 7;
