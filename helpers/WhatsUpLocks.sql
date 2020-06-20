/*
Copyright (c) 2020 Darling Data, LLC

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

/*
This is a helper function I use in some of my presentations to look at locks taken.

It's definitely not a replacements for sp_WhoIsActive, it just gives me

*/

IF OBJECT_ID('dbo.WhatsUpLocks') IS NULL
BEGIN
DECLARE @fsql NVARCHAR(MAX) = 
    N'
CREATE FUNCTION WhatsUpLocks()
RETURNS TABLE
AS 
RETURN
SELECT 1 AS x;
    ';

PRINT @fsql;
EXEC (@fsql);
END;
GO 

ALTER FUNCTION dbo.WhatsUpLocks
(
    @SPID INT
)
RETURNS TABLE
AS
RETURN 
SELECT dtl.request_mode,
       CASE dtl.resource_type
            WHEN N'OBJECT' 
            THEN OBJECT_NAME(dtl.resource_associated_entity_id)
            ELSE OBJECT_NAME(p.object_id)
       END AS locked_object,
       ISNULL(i.name, N'OBJECT') AS index_name,
       dtl.resource_type,
       dtl.request_status,
       COUNT_BIG(*) AS total_locks
FROM sys.dm_tran_locks AS dtl WITH(NOLOCK)
LEFT JOIN sys.partitions AS p WITH(NOLOCK)
    ON p.hobt_id = dtl.resource_associated_entity_id
LEFT JOIN sys.indexes AS i WITH(NOLOCK)
    ON  p.object_id = i.object_id
    AND p.index_id = i.index_id
WHERE (dtl.request_session_id = @SPID OR @SPID IS NULL)
AND    dtl.resource_type <> N'DATABASE'
GROUP BY CASE dtl.resource_type
              WHEN N'OBJECT' 
              THEN OBJECT_NAME(dtl.resource_associated_entity_id)
              ELSE OBJECT_NAME(p.object_id)
         END,
         ISNULL(i.name, N'OBJECT'),
         dtl.resource_type,
         dtl.request_mode,
         dtl.request_status;
GO


