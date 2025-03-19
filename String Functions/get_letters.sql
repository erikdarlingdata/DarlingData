/* This version relies on a Numbers table */
/* https://www.mssqltips.com/sqlservertip/4176/the-sql-server-numbers-table-explained--part-1/ */

CREATE FUNCTION
    dbo.get_letters
(
    @string nvarchar(4000)
)
RETURNS table
WITH SCHEMABINDING
AS
/*
For support:
https://code.erikdarling.com

Copyright 2025 Darling Data, LLC
https://erikdarling.com

MIT LICENSE

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"),
to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/
RETURN
WITH x AS
(
    SELECT TOP (LEN(ISNULL(@string, N'')))
        ROW_NUMBER() OVER
        (
            ORDER BY
                n.Number
        ) AS x
    FROM dbo.Numbers AS n
)
SELECT
    CONVERT
    (
        nvarchar(4000),
        (
            SELECT
                SUBSTRING
                (
                    @string COLLATE Latin1_General_100_BIN2,
                    x.x,
                    1
                )
            FROM x AS x
            WHERE SUBSTRING
                  (
                      @string COLLATE Latin1_General_100_BIN2,
                      x.x,
                      1
                  ) LIKE N'[a-zA-Z]'
            ORDER BY x.x
            FOR XML PATH(N''), TYPE
        ).value('./text()[1]', 'nvarchar(max)')
    ) AS letters_only;
GO


/*This version relies on an inline CTE to generate sequential numbers*/
/*User requested code (probably) originates here, from Jeff Moden*/
/* https://sqlservercentral.com/articles/the-numbers-or-tally-table-what-it-is-and-how-it-replaces-a-loop-1 */

CREATE FUNCTION
    dbo.get_letters_cte
(
    @string nvarchar(4000)
)
RETURNS table
WITH SCHEMABINDING
AS
/*
For support:
https://code.erikdarling.com

Copyright 2025 Darling Data, LLC
https://erikdarling.com

MIT LICENSE

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"),
to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.*/
RETURN
WITH e1 (n) AS
(
    SELECT
        n = 1
    FROM
    (
        VALUES
            (1), (1), (1), (1), (1),
            (1), (1), (1), (1), (1)
    ) AS x (n)
),
     e2 (n) AS
(
    SELECT
        1
    FROM e1 AS a
    CROSS JOIN e1 AS b
),
     e4 (n) AS
(
    SELECT
        1
     FROM e2 AS a
     CROSS JOIN e2 AS b
),
     x AS
(
    SELECT TOP (LEN(ISNULL(@string, N'')))
        ROW_NUMBER() OVER
        (
            ORDER BY
                n.n
        ) x
    FROM e4 AS n
)
SELECT
    CONVERT
    (
        nvarchar(4000),
        (
            SELECT
                SUBSTRING
                (
                    @string COLLATE Latin1_General_100_BIN2,
                    x.x,
                    1
                )
            FROM x AS x
            WHERE SUBSTRING
                  (
                      @string COLLATE Latin1_General_100_BIN2,
                      x.x,
                      1
                  ) LIKE N'[a-zA-Z]'
            ORDER BY x.x
            FOR XML PATH(''), TYPE
        ).value('./text()[1]', 'nvarchar(max)')
    ) AS letters_only;
GO
