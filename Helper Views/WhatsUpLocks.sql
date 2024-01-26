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
This is a helper function I use in some of my presentations to look at locks taken.
It's definitely not a replacement for sp_WhoIsActive, it just gives me what I care about at the moment.

https://github.com/erikdarlingdata/DarlingData

Copyright (c) 2024 Darling Data, LLC
https://www.erikdarling.com/

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction,
including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:
The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

IF OBJECT_ID(N'dbo.WhatsUpLocks') IS NULL
BEGIN
    DECLARE
        @fsql nvarchar(MAX) = N'
    CREATE FUNCTION
        dbo.WhatsUpLocks()
    RETURNS TABLE
    AS
    RETURN
    SELECT
        x = 138;';

    PRINT @fsql;
    EXEC (@fsql);
END;
GO

ALTER FUNCTION
    dbo.WhatsUpLocks
(
    @spid int
)
RETURNS table
AS
RETURN
SELECT
    dtl.request_mode,
    locked_object =
        CASE dtl.resource_type
             WHEN N'OBJECT'
             THEN OBJECT_NAME(dtl.resource_associated_entity_id)
             ELSE OBJECT_NAME(p.object_id)
        END,
    index_name =
        ISNULL(i.name, N'OBJECT'),
    dtl.resource_type,
    dtl.request_status,
    hobt_lock_count =
        SUM
        (
            IIF
            (
                dtl.resource_associated_entity_id = P.hobt_id,
                1,
                0
            )
        ),
    page_locks =
        SUM
        (
            IIF
            (
                dtl.resource_type = N'PAGE',
                1,
                0
            )
        ),
    row_locks =
        SUM
        (
            IIF
            (
                dtl.resource_type IN (N'RID', N'KEY'),
                1,
                0
            )
        ),
    total_locks =
        COUNT_BIG(*)
FROM sys.dm_tran_locks AS dtl WITH(NOLOCK)
LEFT JOIN sys.partitions AS p WITH(NOLOCK)
  ON p.hobt_id = dtl.resource_associated_entity_id
OUTER APPLY
(
    SELECT TOP (1)
        i.name
    FROM sys.indexes AS i WITH(NOLOCK)
    WHERE  p.object_id = i.object_id
    AND    p.index_id  = i.index_id
) AS i
WHERE (dtl.request_session_id = @spid OR @spid IS NULL)
AND    dtl.resource_type <> N'DATABASE'
AND    dtl.request_request_id = CURRENT_REQUEST_ID()
AND    dtl.request_owner_id = CURRENT_TRANSACTION_ID()
GROUP BY
    CASE dtl.resource_type
         WHEN N'OBJECT'
         THEN OBJECT_NAME(dtl.resource_associated_entity_id)
         ELSE OBJECT_NAME(p.object_id)
    END,
    i.name,
    dtl.resource_type,
    dtl.request_mode,
    dtl.request_status;