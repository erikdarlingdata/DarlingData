/*
    sqlcmd-mode installer for Erik Darling Data sp_HumanEvents procs.

    run from sqlcmd.exe using the following command-line:

    sqlcmd -S {sql-server} -i .\install-human-events.sql -v TargetDB = "{target-database}"

    {sql-server} is the name of the target SQL Server
    {target-database} is where we'll install the sp_HumanEvents procedures.
*/
:on error exit
:setvar SqlCmdEnabled "True"
PRINT N'sp_HumanEvents installer, by Erik Darling Data';
PRINT N'sp_HumanEvents will be installed into the $(TargetDB) database.';

IF '($SqlCmdEnabled)' NOT LIKE 'True'
BEGIN
    RAISERROR (N'This script is designed to run via sqlcmd.  Aborting.');
    SET NOEXEC ON;
END

IF N'($TargetDB)' = N''
BEGIN
    RAISERROR (N'You must specify the target database via the sqlcmd -V parameter (TargetDB = "{server-name}")');
    SET NOEXEC ON;
END

:r .\sp_HumanEvents.sql

:r .\sp_HumanEventsBlockViewer.sql

