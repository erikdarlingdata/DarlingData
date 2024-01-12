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

Copyright 2024 Darling Data, LLC
https://www.erikdarling.com/

This will set delete tables older than a defined retention period, with  default of 10 days.

If you need to get or update sp_WhoIsActive:
https://github.com/amachanic/sp_whoisactive
(C) 2007-2024, Adam Machanic

*/

/*
SQL Agent has some weird settings.
This sets them to the correct ones.
*/

IF OBJECT_ID('dbo.sp_WhoIsActiveLogging_Retention') IS NULL   
   BEGIN   
       EXEC ('CREATE PROCEDURE dbo.sp_WhoIsActiveLogging_Retention AS RETURN 138;');   
   END;   
GO 

ALTER PROCEDURE
    dbo.sp_WhoIsActiveLogging_Retention
(
    @RetentionPeriod integer = 10
)
AS
BEGIN
    SET STATISTICS XML OFF;
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    IF EXISTS
    (
        SELECT
            1/0
        FROM sys.tables AS t
        WHERE t.name LIKE N'WhoIsActive[_][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]%'
        AND   t.create_date < DATEADD(DAY, (@RetentionPeriod * -1), SYSDATETIME())
    )
    BEGIN
        DECLARE
            @dsql nvarchar(MAX) = N'';

        SELECT
            @dsql +=
        (
            SELECT TOP (9223372036854775807)
                [text()] =
                    N'DROP TABLE ' +
                    QUOTENAME(SCHEMA_NAME(t.schema_id)) +
                    N'.' +
                    QUOTENAME(t.name) +
                    N';'
            FROM sys.tables AS t
            WHERE t.name LIKE N'WhoIsActive[_][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]%'
            AND   t.create_date < DATEADD(DAY, (@RetentionPeriod * -1), SYSDATETIME())
            ORDER BY 
                t.create_date DESC
            FOR XML
                PATH(N''),
                TYPE
        ).value
             (
                 './text()[1]',
                 'nvarchar(max)'
             );

        EXEC sys.sp_executesql
            @dsql;
    END;
END;
GO 
