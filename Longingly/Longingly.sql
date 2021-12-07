
CREATE OR ALTER PROCEDURE 
    dbo.Longingly
(
    @loops int = 1,
    @debug bit = 0
)
AS
SET 
    NOCOUNT, 
    XACT_ABORT ON;

BEGIN
    DECLARE 
        @psql nvarchar(MAX) = N'DECLARE @p',
        @ssql nvarchar(MAX) = 
            N'SELECT c = COUNT_BIG(*) FROM dbo.Users AS u WHERE u.Reputation < 0 OR u.DisplayName IN (@p',
        @asql nvarchar(MAX) = N'',
        @i int = 1;

    WHILE @i <= @loops
    BEGIN
        SELECT
            @psql += 
                RTRIM(@i) +
                N' NVARCHAR(40) = N' +
                QUOTENAME 
                (
                    CONVERT
                    (
                        nvarchar(36), 
                        NEWID()
                    ), 
                    ''''
                ) +
                N';' +
                NCHAR(10) +
                N'DECLARE @p', 
            @ssql += 
                RTRIM(@i) +
                N', @p';

        SELECT 
            @i += 1;
    END;

    SELECT 
        @psql = 
            SUBSTRING
            (
                @psql, 
                1, 
                LEN(@psql) - 10
            ),
        @ssql = 
            SUBSTRING
            (
                @ssql, 
                1, 
                LEN(@ssql) - 4
            ) + N');';
    
    SELECT 
        @asql = 
            @psql + 
            NCHAR(10) + 
            @ssql;

    IF @debug = 1
    BEGIN
        PRINT N'----';
        PRINT N'@psql';
        PRINT @psql;
        PRINT N'----';
        PRINT N'@ssql';
        PRINT @ssql;
        PRINT N'----';
        PRINT N'@asql';
        PRINT @asql;
        PRINT N'----';
    END;

    SET STATISTICS XML ON;
        EXEC sys.sp_executesql 
            @asql;
    SET STATISTICS XML OFF;
END;
