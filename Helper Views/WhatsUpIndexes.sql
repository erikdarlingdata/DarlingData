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
This is a quick one-off script I use in some presentations to look at index sizes.

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

IF OBJECT_ID(N'dbo.WhatsUpIndexes') IS NULL
BEGIN
    DECLARE
        @vsql nvarchar(MAX) = N'
    CREATE VIEW
        dbo.WhatsUpIndexes
    AS
    SELECT
        x = 138;';

    PRINT @vsql;
    EXEC (@vsql);
END;
GO


ALTER VIEW
    dbo.WhatsUpIndexes
AS
SELECT TOP (2147483647)
    view_name =
        'WhatsUpIndexes',
    database_name =
        DB_NAME(),
    schema_name =
        s.name,
    table_name =
        OBJECT_NAME(ps.object_id),
    index_name =
        i.name,
    in_row_pages_mb =
        (ps.reserved_page_count * 8. / 1024.),
    lob_pages_mb =
        (ps.lob_reserved_page_count * 8. / 1024.),
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
  AND ps.index_id  = i.index_id
ORDER BY
    ps.object_id,
    ps.index_id,
    ps.partition_number;
