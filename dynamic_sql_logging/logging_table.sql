/*

Creates a table to log statement information from dynamic SQL to.

Should be used in conjunction with dbo.logging
 * https://github.com/erikdarlingdata/DarlingData/tree/main/dynamic_sql_logging

Copyright (c) 2022 Darling Data, LLC

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"),
to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
USE OR OTHER DEALINGS IN THE SOFTWARE.

*/

DROP TABLE IF EXISTS
    dbo.logger;

CREATE TABLE
    dbo.logger
(
    run_hash uniqueidentifier,
    run_date datetime,
    user_name sysname,
    cpu_time_ms decimal(18,2),
    total_elapsed_time_ms decimal(18,2),
    physical_reads_mb decimal(18,2),
    logical_reads_mb decimal(18,2),
    writes_mb decimal(18,2),
    statement_text nvarchar(MAX),
    execution_text nvarchar(MAX),
    query_plan xml,
    is_final bit DEFAULT 0,
  CONSTRAINT loggerino PRIMARY KEY (run_hash)
);
GO
