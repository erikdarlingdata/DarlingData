/*
This script is designed to inflate the size of the security cache,
and provide some queries that analyze it. If you see inflated security
caches in a production SQL Server environment, you may want to use the
stored procdure in this repo to clear it out on a schedle.

!!!!!!!!!!!!!!!!!!!!!!!!!!!!PLEASE BE AWARE!!!!!!!!!!!!!!!!!!!!!!!!!!!!

    This script runs DBCC FREESYSTEMCACHE('TokenAndPermUserStore');

    It does so TWICE! If you're testing this in a an environment where
    you're unsure of the consequences of that, comment it out TWICE!

!!!!!!!!!!!!!!!!!!!!!!!!!!!!PLEASE BE AWARE!!!!!!!!!!!!!!!!!!!!!!!!!!!!

Copyright 2024 Darling Data, LLC
https://www.erikdarling.com/

For support, head over to GitHub:
https://code.erikdarling.com

MIT License

Copyright 2025 Darling Data, LLC

https://www.erikdarling.com/

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"),
to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute,
sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the
following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE
FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

SET NOCOUNT ON;
DBCC FREESYSTEMCACHE('TokenAndPermUserStore');

DECLARE
    @counter int = 0,
    @cronut varbinary(8000),
    @bl0b_eater sql_variant;

DECLARE @holder table
(
    id int PRIMARY KEY IDENTITY,
    cache_size decimal(10,2),
    run_date datetime2
);

IF NOT EXISTS
(
    SELECT
        1/0
    FROM sys.database_principals AS dp
    WHERE dp.name = N'your_terrible_app'
    AND   dp.default_schema_name = N'dbo'
    AND   dp.type = 'A'
)
BEGIN
    CREATE APPLICATION ROLE
        your_terrible_app
    WITH DEFAULT_SCHEMA = [dbo],
    PASSWORD = N'y0ur_t3rr1bl3_4pp';
END;

WHILE @counter < 50000
BEGIN
    EXECUTE sys.sp_setapprole
        @rolename = N'your_terrible_app',
        @password = N'y0ur_t3rr1bl3_4pp',
        @fCreateCookie = true,
        @cookie = @cronut OUTPUT;

    SELECT
        @bl0b_eater = USER_NAME();

    EXECUTE sys.sp_unsetapprole
        @cronut;

    SELECT
        @bl0b_eater = USER_NAME();

    IF @counter % 10000 = 0
    BEGIN
        RAISERROR('loop number: %i', 0, 1, @counter) WITH NOWAIT;

        INSERT
            @holder
        (
            cache_size,
            run_date
        )
        SELECT
            cache_size =
                CONVERT
                (
                    decimal(38, 2),
                    (mc.pages_kb / 128. / 1024.)
                ),
            run_date =
                SYSDATETIME()
        FROM sys.dm_os_memory_clerks AS mc
        WHERE mc.type = N'USERSTORE_TOKENPERM'
        AND   mc.name = N'TokenAndPermUserStore';
    END;

    SELECT
        @counter += 1;
END;

SELECT
    h.id,
    h.cache_size,
    h.run_date
FROM @holder AS h
ORDER BY
    h.id;

SELECT
    x.event_time,
    TokenAndPermUserStore =
        t.c.query('.'),
    ACRCacheStores =
        a.c.query('.')
FROM
(
    SELECT TOP (1)
        event_time =
            CONVERT
            (
                datetime,
                DATEADD
                (
                    SECOND,
                    (dorb.timestamp - inf.ms_ticks) / 1000,
                    SYSDATETIME()
                )
            ),
        record =
            CONVERT(xml, dorb.record)
    FROM sys.dm_os_ring_buffers AS dorb
    CROSS JOIN sys.dm_os_sys_info AS inf
    WHERE dorb.ring_buffer_type = N'RING_BUFFER_SECURITY_CACHE'
    ORDER BY
        dorb.timestamp DESC
) AS x
OUTER APPLY x.record.nodes('//TokenAndPermUserStore') AS t(c)
OUTER APPLY x.record.nodes('//ACRCacheStores') AS a(c)
ORDER BY
    x.event_time DESC;

DROP TABLE IF EXISTS
    #tapus;
GO

WITH
    x AS
(
    SELECT
        x = TRY_CAST(m.entry_data AS xml),
        cache_name = m.name
    FROM sys.dm_os_memory_cache_entries AS m
    WHERE m.name = N'TokenAndPermUserStore'
)
SELECT
    x.x,
    x.cache_name,
    token_name =
        c.c.value('@name', 'varchar(50)'),
    principal_id =
        c.c.value('@id', 'integer'),
    database_id =
        c.c.value('@dbid', 'integer'),
    time_stamp =
        c.c.value('@timestamp', 'bigint')
INTO #tapus
FROM x AS x
CROSS APPLY x.x.nodes('/entry') AS C(C);

--Distribution to See what's high
SELECT
    t.token_name,
    entries =
        COUNT_BIG(*)
FROM #tapus AS t
GROUP BY
    t.cache_name,
    t.token_name
ORDER BY
    entries DESC;

--unique logins and tokens per login
SELECT
    login_name =
        p.name,
    entries =
        COUNT_BIG(*)
FROM #tapus AS t
INNER JOIN sys.server_principals AS p
  ON t.principal_id = p.principal_id
WHERE t.token_name = N'SecContextToken'
GROUP BY
    p.name
ORDER BY
    entries DESC;

--users and tokens per user
SELECT
    database_name =
        d.name,
    entries =
        COUNT_BIG(*)
FROM #tapus AS t
INNER JOIN sys.databases AS d
  ON d.database_id = t.database_id
WHERE t.token_name = N'UserToken'
AND   t.cache_name = N'TokenAndPermUserStore'
GROUP BY
    d.name
ORDER BY
    entries DESC;

-- cache invalidations for usertokens
SELECT
    database_name =
        d.name,
    invalidations =
        COUNT_BIG(DISTINCT t.time_stamp)
FROM #tapus AS t
INNER JOIN sys.databases AS d
  ON d.database_id = t.database_id
WHERE t.token_name = N'UserToken'
GROUP BY
    d.name
ORDER BY
    invalidations DESC;

DBCC FREESYSTEMCACHE('TokenAndPermUserStore');

IF EXISTS
(
    SELECT
        1/0
    FROM sys.database_principals AS dp
    WHERE dp.name = N'your_terrible_app'
    AND   dp.default_schema_name = N'dbo'
    AND   dp.type = 'A'
)
BEGIN
    DROP APPLICATION ROLE
        your_terrible_app;
END;
