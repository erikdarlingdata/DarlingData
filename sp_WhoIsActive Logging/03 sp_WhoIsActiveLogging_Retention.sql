/*

Copyright 2023 Darling Data, LLC
https://www.erikdarlingdata.com/

This will set delete tables older than a defined retention period, with  default of 10 days.

If you need to get or update sp_WhoIsActive:
https://github.com/amachanic/sp_whoisactive
(C) 2007-2022, Adam Machanic

*/

/*
SQL Agent has some weird settings.
This sets them to the correct ones.
*/
CREATE OR ALTER PROCEDURE
    dbo.sp_WhoIsActiveLogging_Retention
(
    @RetentionPeriod integer = 10
)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    BEGIN
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
                ORDER BY t.create_date DESC
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
END;