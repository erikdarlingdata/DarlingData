/*
    sqlcmd-mode installer for Erik Darling Data sp_HumanEvents procs.

    run from sqlcmd.exe using the following command-line:

    sqlcmd -S {sql-server} -i .\install-human-events.sql -v TargetDB = "{target-database}"

    {sql-server} is the name of the target SQL Server
    {target-database} is where we'll install the sp_HumanEvents procedures.
*/
:on error exit
:setvar SqlCmdEnabled "True"
DECLARE @msg nvarchar(2048);
SET @msg = N'sp_HumanEvents installer, by Erik Darling Data.';
RAISERROR (@msg, 10, 1) WITH NOWAIT;
SET @msg = N'Connected to SQL Server ' + @@SERVERNAME + N' as ' + SUSER_SNAME();
RAISERROR (@msg, 10, 1) WITH NOWAIT;

IF '$(SqlCmdEnabled)' NOT LIKE 'True'
BEGIN
    RAISERROR (N'This script is designed to run via sqlcmd.  Aborting.', 10, 127) WITH NOWAIT;
    SET NOEXEC ON;
END

IF N'$(TargetDB)' = N''
BEGIN
    SET @msg = N'You must specify the target database via the sqlcmd -V parameter (TargetDB = "{server-name}")';
    RAISERROR (@msg, 10, 1) WITH NOWAIT;
    SET @msg = N'sqlcmd.exe -S <servername> -E -i .\install-human-events.sql -v TargetDB = "<database_name>"';
    RAISERROR (@msg, 10, 1) WITH NOWAIT;
    SET @msg = N'Aborting.';
    RAISERROR (@msg, 10, 127) WITH NOWAIT;
    SET NOEXEC ON;
END

IF NOT EXISTS
(
    SELECT 1
    FROM [sys].[databases] d
    WHERE d.[name] = N'$(TargetDB)'
)
BEGIN
    SET @msg = N'The specified target database, $(TargetDB), does not exist.  Please ensure the specified database exists, and is accessible to login ' + QUOTENAME(SUSER_SNAME()) + N'.';
    RAISERROR (@msg, 10, 127) WITH NOWAIT;
    SET NOEXEC ON;
END
ELSE
BEGIN
    SET @msg = N'sp_HumanEvents and related procs will be installed into the [$(TargetDB)] database.';
    RAISERROR (@msg, 10, 1) WITH NOWAIT;
END
GO

USE [$(TargetDB)];
GO

:r .\sp_HumanEvents.sql
GO

:r .\sp_HumanEventsBlockViewer.sql
GO

DECLARE @msg nvarchar(2048);
IF OBJECT_ID(N'dbo.sp_HumanEvents') IS NOT NULL
BEGIN
    SET @msg = N'dbo.sp_HumanEvents has been successfully installed into the [$(TargetDB)] database on ' + @@SERVERNAME + N'.';
    RAISERROR (@msg, 10, 1) WITH NOWAIT;
END

IF OBJECT_ID(N'dbo.sp_HumanEventsBlockViewer') IS NOT NULL
BEGIN
    SET @msg = N'dbo.sp_HumanEventsBlockViewer has been successfully installed into the [$(TargetDB)] database on ' + @@SERVERNAME + N'.';
    RAISERROR (@msg, 10, 1) WITH NOWAIT;
END

SET @msg = N'install-human-events.sql completed.';
RAISERROR (@msg, 10, 1) WITH NOWAIT;
