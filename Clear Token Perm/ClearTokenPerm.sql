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

For background on why you might need this:
 * https://www.erikdarling.com/troubleshooting-security-cache-issues-userstore_tokenperm-and-tokenandpermuserstore/

In short, if your security caches are growing out of control, it can cause all sorts of weird issues with SQL Server.

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
    dbo.ClearTokenPerm
(
    @CacheSizeGB decimal(38,2)
)
WITH RECOMPILE
AS
BEGIN
SET NOCOUNT, XACT_ABORT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE
    @clear_triggered bit = 0;

IF OBJECT_ID(N'dbo.ClearTokenPermLogging', N'U') IS NULL
BEGIN
    CREATE TABLE
        dbo.ClearTokenPermLogging
    (
        id bigint IDENTITY PRIMARY KEY,
        cache_size_gb decimal(38,2) NOT NULL,
        log_date datetime NOT NULL,
        clear_triggered bit NOT NULL
    );
END;

IF
(
    SELECT
        cache_size =
            CONVERT
            (
                decimal(38,2),
                (domc.pages_kb / 1024. / 1024.)
            )
    FROM sys.dm_os_memory_clerks AS domc
    WHERE domc.type = N'USERSTORE_TOKENPERM'
    AND   domc.name = N'TokenAndPermUserStore'
) >= @CacheSizeGB
BEGIN
    INSERT
        dbo.ClearTokenPermLogging
    (
        cache_size_gb,
        log_date,
        clear_triggered
    )
    SELECT
        cache_size =
            CONVERT
            (
                decimal(38,2),
                (domc.pages_kb / 1024. / 1024.)
            ),
        log_date =
            GETDATE(),
        clear_triggered =
            1
    FROM sys.dm_os_memory_clerks AS domc
    WHERE domc.type = N'USERSTORE_TOKENPERM'
    AND   domc.name = N'TokenAndPermUserStore';

    DBCC FREESYSTEMCACHE('TokenAndPermUserStore');
END;
ELSE
BEGIN
    INSERT
        dbo.ClearTokenPermLogging
    (
        cache_size_gb,
        log_date,
        clear_triggered
    )
    SELECT
        cache_size =
            CONVERT
            (
                decimal(38, 2),
                (domc.pages_kb / 1024. / 1024.)
            ),
        log_date =
            GETDATE(),
        clear_triggered =
            0
    FROM sys.dm_os_memory_clerks AS domc
    WHERE domc.type = N'USERSTORE_TOKENPERM'
    AND   domc.name = N'TokenAndPermUserStore';
    END;
END;
RETURN;

/*Example execution*/
EXECUTE dbo.ClearTokenPerm
    @CacheSizeGB = 1;

/*Query a log*/
SELECT
    ctpl.*
FROM dbo.ClearTokenPermLogging AS ctpl;

/*Truncate a log*/
TRUNCATE TABLE
    dbo.ClearTokenPermLogging;
