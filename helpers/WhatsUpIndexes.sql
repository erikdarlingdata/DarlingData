/*
Copyright (c) 2020 Darling Data, LLC

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

/*
This is a helper view I use in some of my presentations to look at index sizes quickly.

It's not a replacement for index analysis tools. There's just less overhead and baggage.
*/

IF OBJECT_ID('dbo.WhatsUpIndexes') IS NULL
BEGIN
DECLARE @vsql NVARCHAR(MAX) = 
    N'
CREATE VIEW dbo.WhatsUpIndexes
    AS
SELECT 1 AS x;
    ';

PRINT @vsql;
EXEC (@vsql);
END;
GO 


ALTER VIEW dbo.WhatsUpIndexes
AS
SELECT TOP ( 2147483647 )
       N'WhatsUpIndexes' AS view_name,
       DB_NAME() AS database_name,
       s.name AS schema_name,
       OBJECT_NAME(ps.object_id) AS table_name,
       i.name AS index_name,
       ( ps.reserved_page_count * 8. / 1024. ) AS in_row_pages_mb,
       ( ps.lob_reserved_page_count * 8. / 1024. ) AS lob_pages_mb,
       ps.in_row_used_page_count,
       ps.row_count
FROM sys.dm_db_partition_stats AS ps
JOIN sys.objects AS so
    ON  ps.object_id = so.object_id
    AND so.is_ms_shipped = 0
    AND so.type <> 'TF'
JOIN sys.schemas AS s
    ON s.schema_id = so.schema_id
JOIN sys.indexes AS i
    ON  ps.object_id = i.object_id
    AND ps.index_id = i.index_id
ORDER BY ps.object_id,
         ps.index_id,
         ps.partition_number;
GO
