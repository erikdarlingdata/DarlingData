USE [msdb]

/*
See that @operator_name variable below?
You're gonna wanna set that to one of these.
*/
SELECT * FROM msdb..sysoperators AS s

/*
If there's nothing in there, you'll wanna follow this guide to set one up:
https://social.technet.microsoft.com/wiki/contents/articles/51133.sql-server-alerts-and-email-operator-notifications.aspx
*/


/*
Once you do that, you can get rid of this RETURN and F5 the whole script.
*/

DECLARE @operator_name sysname = 'Who You Want To Notify'

RETURN;

EXEC msdb.dbo.sp_add_alert @name=N'Severity 019',
@message_id=0,
@severity=19,
@enabled=1,
@delay_between_responses=60,
@include_event_description_in=1,
@job_id=N'00000000-0000-0000-0000-000000000000';

EXEC msdb.dbo.sp_add_notification @alert_name=N'Severity 019', @operator_name=@operator_name, @notification_method = 7;

EXEC msdb.dbo.sp_add_alert @name=N'Severity 020',
@message_id=0,
@severity=20,
@enabled=1,
@delay_between_responses=60,
@include_event_description_in=1,
@job_id=N'00000000-0000-0000-0000-000000000000';

EXEC msdb.dbo.sp_add_notification @alert_name=N'Severity 020', @operator_name=@operator_name, @notification_method = 7;

EXEC msdb.dbo.sp_add_alert @name=N'Severity 021',
@message_id=0,
@severity=21,
@enabled=1,
@delay_between_responses=60,
@include_event_description_in=1,
@job_id=N'00000000-0000-0000-0000-000000000000';

EXEC msdb.dbo.sp_add_notification @alert_name=N'Severity 021', @operator_name=@operator_name, @notification_method = 7;

EXEC msdb.dbo.sp_add_alert @name=N'Severity 022',
@message_id=0,
@severity=22,
@enabled=1,
@delay_between_responses=60,
@include_event_description_in=1,
@job_id=N'00000000-0000-0000-0000-000000000000';

EXEC msdb.dbo.sp_add_notification @alert_name=N'Severity 022', @operator_name=@operator_name, @notification_method = 7;

EXEC msdb.dbo.sp_add_alert @name=N'Severity 023',
@message_id=0,
@severity=23,
@enabled=1,
@delay_between_responses=60,
@include_event_description_in=1,
@job_id=N'00000000-0000-0000-0000-000000000000';

EXEC msdb.dbo.sp_add_notification @alert_name=N'Severity 023', @operator_name=@operator_name, @notification_method = 7;

EXEC msdb.dbo.sp_add_alert @name=N'Severity 024',
@message_id=0,
@severity=24,
@enabled=1,
@delay_between_responses=60,
@include_event_description_in=1,
@job_id=N'00000000-0000-0000-0000-000000000000';

EXEC msdb.dbo.sp_add_notification @alert_name=N'Severity 024', @operator_name=@operator_name, @notification_method = 7;

EXEC msdb.dbo.sp_add_alert @name=N'Severity 025',
@message_id=0,
@severity=25,
@enabled=1,
@delay_between_responses=60,
@include_event_description_in=1,
@job_id=N'00000000-0000-0000-0000-000000000000';

EXEC msdb.dbo.sp_add_notification @alert_name=N'Severity 025', @operator_name=@operator_name, @notification_method = 7;

EXEC msdb.dbo.sp_add_alert @name=N'Error Number 823',
@message_id=823,
@severity=0,
@enabled=1,
@delay_between_responses=60,
@include_event_description_in=1,
@job_id=N'00000000-0000-0000-0000-000000000000'

EXEC msdb.dbo.sp_add_notification @alert_name=N'Error Number 823', @operator_name=@operator_name, @notification_method = 7;

EXEC msdb.dbo.sp_add_alert @name=N'Error Number 824',
@message_id=824,
@severity=0,
@enabled=1,
@delay_between_responses=60,
@include_event_description_in=1,
@job_id=N'00000000-0000-0000-0000-000000000000'

EXEC msdb.dbo.sp_add_notification @alert_name=N'Error Number 824', @operator_name=@operator_name, @notification_method = 7;

EXEC msdb.dbo.sp_add_alert @name=N'Error Number 825',
@message_id=825,
@severity=0,
@enabled=1,
@delay_between_responses=60,
@include_event_description_in=1,
@job_id=N'00000000-0000-0000-0000-000000000000'

EXEC msdb.dbo.sp_add_notification @alert_name=N'Error Number 825', @operator_name=@operator_name, @notification_method = 7;
