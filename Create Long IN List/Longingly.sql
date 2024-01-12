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

This procedure exists only to show how long IN clauses can hurt query performance.

Copyright 2024 Darling Data, LLC
https://www.erikdarling.com/

For support, head over to GitHub:
https://github.com/erikdarlingdata/DarlingData

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR
OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.

*/
CREATE OR ALTER PROCEDURE
    dbo.Longingly
(
    @loops int = 1,
    @debug bit = 0
)
AS
BEGIN
    SET NOCOUNT ON 
    SET XACT_ABORT OFF;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
    
    DECLARE
        @psql nvarchar(MAX) =
            N'DECLARE @p',
        @ssql nvarchar(MAX) =
            N'SELECT c = COUNT_BIG(*) FROM dbo.Users AS u WHERE u.Reputation < 0 OR u.DisplayName IN (@p',
        @asql nvarchar(MAX) =
            N'',
        @i int =
            1;

    WHILE @i <= @loops
    BEGIN
        SELECT
            @psql +=
                RTRIM(@i) +
                N' NVARCHAR(40) = N' +
                QUOTENAME
                (
                    CONVERT
                    (
                        nvarchar(36),
                        NEWID()
                    ),
                    N''''
                ) +
                N';' +
                NCHAR(10) +
                N'DECLARE @p',
            @ssql +=
                RTRIM(@i) +
                N', @p';

        SELECT
            @i += 1;
    END;

    SELECT
        @psql =
            SUBSTRING
            (
                @psql,
                1,
                LEN(@psql) - 10
            ),
        @ssql =
            SUBSTRING
            (
                @ssql,
                1,
                LEN(@ssql) - 4
            ) + N');';

    SELECT
        @asql =
            @psql +
            NCHAR(10) +
            @ssql;

    IF @debug = 1
    BEGIN
        PRINT N'----';
        PRINT N'@psql';
        PRINT @psql;
        PRINT N'----';
        PRINT N'@ssql';
        PRINT @ssql;
        PRINT N'----';
        PRINT N'@asql';
        PRINT @asql;
        PRINT N'----';
    END;

    SET STATISTICS XML ON;
        EXEC sys.sp_executesql
            @asql;
    SET STATISTICS XML OFF;
END;
