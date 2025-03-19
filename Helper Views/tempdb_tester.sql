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

This generates some semi-random tempdb activity

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

CREATE OR ALTER PROCEDURE
    dbo.tempdb_tester
WITH RECOMPILE
AS
BEGIN;
    SET STATISTICS XML OFF;
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    WITH x1 (n) AS
    (
        SELECT 1 UNION ALL
        SELECT 1 UNION ALL
        SELECT 1 UNION ALL
        SELECT 1 UNION ALL
        SELECT 1 UNION ALL
        SELECT 1 UNION ALL
        SELECT 1 UNION ALL
        SELECT 1 UNION ALL
        SELECT 1 UNION ALL
        SELECT 1
    ),
         x2(n) AS
    (
        SELECT
            1
        FROM x1 AS x,
             x1 AS xx
    ),
         x4(n) AS
    (
        SELECT
            1
        FROM x2 AS x,
             x2 AS xx
    )
    SELECT
        ROW_NUMBER() OVER
        (
            ORDER BY
               (SELECT 1/0)
        ) AS x,
        CONVERT
        (
            varchar(100),
            REPLICATE('A', 10)
        ) AS textual
    INTO #t
    FROM x4;

    UPDATE #t
        SET
            textual =
                CONVERT
                (
                    varchar(100),
                    REPLICATE('Z', 100)
                )
    WHERE x <= 2000;

    DELETE
    FROM #t
    WHERE x > 8000;

    INSERT
        #t WITH(TABLOCK)
    (
        x,
        textual
    )
    SELECT
        t.x,
        t.textual
    FROM #t AS t;
END;
