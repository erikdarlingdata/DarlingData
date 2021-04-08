CREATE OR ALTER PROCEDURE dbo.ClearTokenPerm
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

IF OBJECT_ID('dbo.ClearTokenPermLogging') IS NULL
BEGIN

    CREATE TABLE dbo.ClearTokenPermLogging
    (
        id bigint IDENTITY PRIMARY KEY,
        cache_size_gb decimal(38,2) NOT NULL,
        log_date datetime NOT NULL,
        clear_triggered bit NOT NULL
    );

END

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
    WHERE domc.type = 'USERSTORE_TOKENPERM'
    AND   domc.name = 'TokenAndPermUserStore'
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
    WHERE domc.type = 'USERSTORE_TOKENPERM'
    AND   domc.name = 'TokenAndPermUserStore';
    
    DBCC FREESYSTEMCACHE('TokenAndPermUserStore');

END
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
    WHERE domc.type = 'USERSTORE_TOKENPERM'
    AND   domc.name = 'TokenAndPermUserStore';
    END

END
GO 

/*Example execution*/
EXEC dbo.ClearTokenPerm @CacheSizeGB = 0.10;

/*Query a log*/
SELECT 
    *
FROM dbo.ClearTokenPermLogging AS ctpl

/*Truncate a log*/
TRUNCATE TABLE dbo.ClearTokenPermLogging;
