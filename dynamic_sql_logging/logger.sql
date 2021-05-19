CREATE OR ALTER PROCEDURE dbo.logging
( 
    @spid int, 
    @sql nvarchar(MAX), 
    @query_plan xml,
    @guid_in uniqueidentifier, 
    @guid_out uniqueidentifier OUTPUT 
)
WITH RECOMPILE 
AS 
BEGIN
SET NOCOUNT, XACT_ABORT ON;
SET TRAN ISOLATION LEVEL READ UNCOMMITTED;

/*
Copyright (c) 2020 Darling Data, LLC
Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

/*variables for the variable gods*/
DECLARE 
    @run_hash uniqueidentifier = NEWID(),
    @cpu_time decimal(18,2),
    @total_elapsed_time decimal(18,2),
    @reads decimal(18,2),
    @writes decimal(18,2),
    @logical_reads decimal(18,2);

/*first pass to collect initial metrics*/
IF @guid_in IS NULL
BEGIN

    INSERT 
        dbo.logger 
    ( 
        run_hash, 
        run_date, 
        user_name, 
        cpu_time_ms, 
        total_elapsed_time_ms, 
        physical_reads_mb, 
        logical_reads_mb, 
        writes_mb, 
        statement_text, 
        execution_text 
    )
    SELECT 
        @run_hash,
        SYSDATETIME(),
        SUSER_NAME(),
        cpu_time,
        total_elapsed_time,
        physical_reads_mb = 
            ((reads - logical_reads) * 8.) / 1024., 
        logical_reads_mb = 
            (logical_reads * 8.) / 1024.,
        writes_mb = 
            (writes * 8.) / 1024.,
        @sql AS statement_text,
        execution_text = 
            (
                SELECT 
                    deib.event_info 
                FROM sys.dm_exec_input_buffer(@spid, 0) AS deib
            )
    FROM sys.dm_exec_requests
    WHERE session_id = @spid
    OPTION(RECOMPILE);

    SET @guid_out = @run_hash;
    RETURN;

END

/*second pass to update metrics with final values*/
IF @guid_in IS NOT NULL
BEGIN

    UPDATE l
        SET 
            l.cpu_time_ms 
                = r.cpu_time - l.cpu_time_ms,
            l.total_elapsed_time_ms 
                = r.total_elapsed_time - l.total_elapsed_time_ms,
            l.physical_reads_mb 
                = (((reads - logical_reads) * 8.) / 1024.) - l.physical_reads_mb,
            l.logical_reads_mb 
                = ((r.logical_reads * 8.) / 1024.) - l.logical_reads_mb,
            l.writes_mb 
                = ((r.writes * 8.) / 1024.) - l.writes_mb,
            l.query_plan 
                = @query_plan,
            l.is_final 
                = CONVERT(bit, 1)
    FROM dbo.logger AS l
    CROSS JOIN sys.dm_exec_requests AS r
    WHERE l.run_hash = @guid_in
    AND   r.session_id = @spid
    OPTION(RECOMPILE);
    RETURN;

END

END
GO 
