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

████████╗███████╗███████╗████████╗
╚══██╔══╝██╔════╝██╔════╝╚══██╔══╝
   ██║   █████╗  ███████╗   ██║
   ██║   ██╔══╝  ╚════██║   ██║
   ██║   ███████╗███████║   ██║
   ╚═╝   ╚══════╝╚══════╝   ╚═╝

██████╗  █████╗  ██████╗██╗  ██╗██╗   ██╗██████╗
██╔══██╗██╔══██╗██╔════╝██║ ██╔╝██║   ██║██╔══██╗
██████╔╝███████║██║     █████╔╝ ██║   ██║██████╔╝
██╔══██╗██╔══██║██║     ██╔═██╗ ██║   ██║██╔═══╝
██████╔╝██║  ██║╚██████╗██║  ██╗╚██████╔╝██║
╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝

██████╗ ███████╗██████╗ ███████╗ ██████╗ ██████╗ ███╗   ███╗ █████╗ ███╗   ██╗ ██████╗███████╗
██╔══██╗██╔════╝██╔══██╗██╔════╝██╔═══██╗██╔══██╗████╗ ████║██╔══██╗████╗  ██║██╔════╝██╔════╝
██████╔╝█████╗  ██████╔╝█████╗  ██║   ██║██████╔╝██╔████╔██║███████║██╔██╗ ██║██║     █████╗
██╔═══╝ ██╔══╝  ██╔══██╗██╔══╝  ██║   ██║██╔══██╗██║╚██╔╝██║██╔══██║██║╚██╗██║██║     ██╔══╝
██║     ███████╗██║  ██║██║     ╚██████╔╝██║  ██║██║ ╚═╝ ██║██║  ██║██║ ╚████║╚██████╗███████╗
╚═╝     ╚══════╝╚═╝  ╚═╝╚═╝      ╚═════╝ ╚═╝  ╚═╝╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝╚══════╝


Copyright 2026 Darling Data, LLC
https://www.erikdarling.com/

For usage and licensing details, run:
EXECUTE dbo.TestBackupPerformance
    @help = 1;

For support, head over to GitHub:
https://code.erikdarling.com

*/


IF OBJECT_ID(N'dbo.TestBackupPerformance', N'P') IS NULL
    EXECUTE (N'CREATE PROCEDURE dbo.TestBackupPerformance AS RETURN 138;');

GO

/*
    Upgrade path only: if dbo.backup_performance_results already exists from
    a prior version without the encryption column, add it before the
    ALTER PROCEDURE batch compiles.

    SQL Server validates column references (bpr.encryption in the result set
    queries) at ALTER PROCEDURE compile time, not at runtime. If the table
    exists but lacks the column, compilation fails with:
        Msg 207 "Invalid column name 'encryption'"
    before a single line of the proc body executes.

    Fresh installs: table does not exist yet, so this block is skipped.
    The CREATE TABLE inside the proc body handles fresh installs and already
    includes the encryption column.

    Upgrades from prior versions: table exists without encryption column,
    so we add it here before the ALTER PROCEDURE batch is submitted.
*/

IF  OBJECT_ID(N'dbo.backup_performance_results', N'U') IS NOT NULL
AND COL_LENGTH(N'dbo.backup_performance_results', N'encryption') IS NULL
BEGIN
    ALTER TABLE dbo.backup_performance_results
        ADD encryption bit NOT NULL
            CONSTRAINT df_bpr_encryption DEFAULT 0;
END;
GO


ALTER PROCEDURE
    dbo.TestBackupPerformance
(
    @database_name sysname = NULL, /*database to back up*/
    @backup_path nvarchar(4000) = NULL, /*directory path or NUL for discard*/
    @file_count_list varchar(100) = '1,2,4', /*comma-separated file counts*/
    @compression_list varchar(100) = '0,1', /*0 = no compression, 1 = compressed*/
    @encryption_list varchar(100) = '0', /*0 = no encryption, 1 = encrypted (requires a server certificate in master)*/
    @buffer_count_list varchar(100) = '0,15,30,50', /*0 = SQL Server default*/
    @max_transfer_size_list varchar(100) = '0,2097152,4194304', /*0 = default (1MB), max 4194304 (4MB)*/
    @stats tinyint = 1, /*backup completion percent to print progress at*/
    @iterations integer = 1, /*times to repeat each configuration*/
    @help bit = 0, /*how you got here*/
    @debug bit = 0, /*prints dynamic sql, displays parameter and variable values, and table contents*/
    @version varchar(5) = NULL OUTPUT, /*OUTPUT; for support*/
    @version_date datetime = NULL OUTPUT /*OUTPUT; for support*/
)
WITH RECOMPILE
AS
BEGIN
SET STATISTICS XML OFF;
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

SELECT
    @version = '1.0',
    @version_date = '20260327';


IF @help = 1
BEGIN
    /*
    Introduction
    */
    SELECT
        introduction =
           'hi, i''m TestBackupPerformance!' UNION ALL
    SELECT 'you got me from https://code.erikdarling.com' UNION ALL
    SELECT 'i test backup performance across combinations of:' UNION ALL
    SELECT ' * file count (striping)' UNION ALL
    SELECT ' * compression (on/off)' UNION ALL
    SELECT ' * encryption (on/off)' UNION ALL
    SELECT ' * buffer count' UNION ALL
    SELECT ' * max transfer size' UNION ALL
    SELECT 'results are stored in dbo.backup_performance_results' UNION ALL
    SELECT 'from https://erikdarling.com';

    /*
    Parameters
    */
    SELECT
        parameter_name =
            ap.name,
        data_type = t.name,
        description =
            CASE
                ap.name
                WHEN N'@database_name' THEN N'database to back up'
                WHEN N'@backup_path' THEN N'directory path, DEFAULT for instance default, or NUL to discard'
                WHEN N'@file_count_list' THEN N'comma-separated list of file counts (backup stripes)'
                WHEN N'@compression_list' THEN N'comma-separated list: 0 = no compression, 1 = compressed'
                WHEN N'@encryption_list' THEN N'comma-separated list: 0 = no encryption, 1 = encrypted (requires a server certificate in master)'
                WHEN N'@buffer_count_list' THEN N'comma-separated list of buffer counts (0 = SQL Server default)'
                WHEN N'@max_transfer_size_list' THEN N'comma-separated list of max transfer sizes in bytes (0 = default 1MB, max 4MB)'
                WHEN N'@stats' THEN N'backup completion percent to print progress at'
                WHEN N'@iterations' THEN N'times to repeat each configuration for averaging'
                WHEN N'@help' THEN N'how you got here'
                WHEN N'@debug' THEN N'prints dynamic sql, displays parameter and variable values, and table contents'
                WHEN N'@version' THEN N'OUTPUT; for support'
                WHEN N'@version_date' THEN N'OUTPUT; for support'
            END,
        valid_inputs =
            CASE
                ap.name
                WHEN N'@database_name' THEN N'a valid database name'
                WHEN N'@backup_path' THEN N'a valid directory path, DEFAULT, or NUL'
                WHEN N'@file_count_list' THEN N'comma-separated integers'
                WHEN N'@compression_list' THEN N'comma-separated 0s and 1s'
                WHEN N'@encryption_list' THEN N'comma-separated 0s and 1s'
                WHEN N'@buffer_count_list' THEN N'comma-separated integers (0 for default)'
                WHEN N'@max_transfer_size_list' THEN N'comma-separated integers, multiples of 65536, max 4194304'
                WHEN N'@stats' THEN N'1-100'
                WHEN N'@iterations' THEN N'a positive integer'
                WHEN N'@help' THEN N'0 or 1'
                WHEN N'@debug' THEN N'0 or 1'
                WHEN N'@version' THEN N'none'
                WHEN N'@version_date' THEN N'none'
            END,
        defaults =
            CASE
                ap.name
                WHEN N'@database_name' THEN N'(required)'
                WHEN N'@backup_path' THEN N'(required)'
                WHEN N'@file_count_list' THEN N'1,2,4'
                WHEN N'@compression_list' THEN N'0,1'
                WHEN N'@encryption_list' THEN N'0'
                WHEN N'@buffer_count_list' THEN N'0,15,30,50'
                WHEN N'@max_transfer_size_list' THEN N'0,2097152,4194304'
                WHEN N'@stats' THEN N'1'
                WHEN N'@iterations' THEN N'1'
                WHEN N'@help' THEN N'0'
                WHEN N'@debug' THEN N'0'
                WHEN N'@version' THEN N'none; OUTPUT'
                WHEN N'@version_date' THEN N'none; OUTPUT'
            END
    FROM sys.all_parameters AS ap
    JOIN sys.all_objects AS o
      ON ap.object_id = o.object_id
    JOIN sys.types AS t
      ON  ap.system_type_id = t.system_type_id
      AND ap.user_type_id = t.user_type_id
    WHERE o.name = N'TestBackupPerformance'
    OPTION(MAXDOP 1, RECOMPILE);

    SELECT
        mit_license_yo =
           'i am MIT licensed, so like, do whatever'

    UNION ALL

    SELECT
        mit_license_yo =
            'see printed messages for full license';

    RAISERROR('
MIT License

Copyright 2026 Darling Data, LLC

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
', 0, 1) WITH NOWAIT;

    RETURN;
END; /*End help section*/

    /*
        Validate required parameters
    */
    IF @database_name IS NULL
    BEGIN
        RAISERROR(N'@database_name is required.', 16, 1);
        RETURN;
    END;

    IF @backup_path IS NULL
    BEGIN
        RAISERROR(N'@backup_path is required.', 16, 1);
        RETURN;
    END;

    /*
        EXECUTE dbo.TestBackupPerformance
            @database_name = N'YourDatabase',
            @backup_path = N'D:\Backups',          /* or N'NUL' to test throughput without disk I/O */
            @file_count_list = '1,2,4',            /* number of backup stripes */
            @compression_list = '0,1',             /* 0 = none, 1 = compressed */
            @encryption_list = '0,1',              /* 0 = none, 1 = encrypted (requires server certificate in master) */
            @buffer_count_list = '0,15,30,50',     /* 0 = SQL Server default */
            @max_transfer_size_list = '0,2097152,4194304', /* 0 = default (1MB), values in bytes, max 4MB */
            @iterations = 3;                       /* repeat each combination for averaging */
    */

    /*
        Validate inputs
    */
    IF DB_ID(@database_name) IS NULL
    BEGIN
        RAISERROR(N'Database [%s] does not exist.', 16, 1, @database_name);
        RETURN;
    END;

    IF @iterations < 1
    BEGIN
        SET @iterations = 1;
    END;

    /*
        MAXTRANSFERSIZE: must be a multiple of 64KB (65536), max 4MB (4194304).
        Default for BACKUP TO DISK is 1MB (1048576).
        BUFFERCOUNT: total buffer memory = BUFFERCOUNT * MAXTRANSFERSIZE * buffer_sets.
        Compressed backups use 3 sets of buffers (3x memory), uncompressed uses 1 set.
        High values risk out-of-memory errors (buffers allocated outside buffer pool).
        Default BUFFERCOUNT formula: (NumDevices * 3) + NumDevices + (2 * NumVolumes)
    */

    /*
        Resolve DEFAULT to the server's default backup directory
    */
    IF UPPER(LTRIM(RTRIM(@backup_path))) = N'DEFAULT'
    BEGIN
        SET @backup_path =
            CONVERT(nvarchar(4000), SERVERPROPERTY(N'InstanceDefaultBackupPath'));

        IF @backup_path IS NULL
        BEGIN
            RAISERROR(N'Could not determine the default backup path for this instance.', 16, 1);
            RETURN;
        END;

        RAISERROR(N'Resolved DEFAULT backup path to: %s', 0, 1, @backup_path) WITH NOWAIT;
    END;

    DECLARE
        @is_nul bit =
            CASE
                WHEN UPPER(LTRIM(RTRIM(@backup_path))) = N'NUL'
                THEN 1
                ELSE 0
            END;

    IF @is_nul = 0
    BEGIN
        IF RIGHT(@backup_path, 1) <> N'\'
        BEGIN
            SET @backup_path += N'\';
        END;

        DECLARE
            @path_check table
            (
                file_exists integer,
                is_directory integer,
                parent_exists integer
            );

        INSERT INTO
            @path_check
        EXECUTE master.dbo.xp_fileexist
            @backup_path;

        IF NOT EXISTS
        (
            SELECT
                1/0
            FROM @path_check AS pc
            WHERE pc.is_directory = 1
        )
        BEGIN
            RAISERROR(N'Backup path [%s] does not exist or is not a directory.', 16, 1, @backup_path);
            RETURN;
        END;
    END;

    /*
        Validate MAXTRANSFERSIZE values: must be 0 (default) or
        a multiple of 65536 between 65536 and 4194304
    */
    DECLARE
        @bad_mts table
        (
            bad_value varchar(20) NOT NULL
        );

    INSERT INTO
        @bad_mts
    (
        bad_value
    )
    SELECT
        LTRIM(RTRIM(x.i.value(N'.', N'varchar(20)')))
    FROM
    (
        SELECT
            CONVERT(xml, N'<i>' + REPLACE(@max_transfer_size_list, N',', N'</i><i>') + N'</i>')
    ) AS d (x)
    CROSS APPLY d.x.nodes(N'i') AS x(i)
    WHERE LTRIM(RTRIM(x.i.value(N'.', N'varchar(20)'))) <> N''
    AND   CONVERT(integer, LTRIM(RTRIM(x.i.value(N'.', N'varchar(20)')))) <> 0
    AND
    (
        CONVERT(integer, LTRIM(RTRIM(x.i.value(N'.', N'varchar(20)')))) % 65536 <> 0
        OR CONVERT(integer, LTRIM(RTRIM(x.i.value(N'.', N'varchar(20)')))) < 65536
        OR CONVERT(integer, LTRIM(RTRIM(x.i.value(N'.', N'varchar(20)')))) > 4194304
    );

    IF EXISTS (SELECT 1/0 FROM @bad_mts)
    BEGIN
        DECLARE
            @bad_mts_list nvarchar(500) = N'';

        SELECT
            @bad_mts_list += bm.bad_value + N', '
        FROM @bad_mts AS bm;

        SET @bad_mts_list = LEFT(@bad_mts_list, LEN(@bad_mts_list) - 1);

        RAISERROR
        (
            N'Invalid MAXTRANSFERSIZE value(s): %s. Must be 0 (default) or a multiple of 65536 between 65536 and 4194304 (4 MB).',
            16,
            1,
            @bad_mts_list
        );
        RETURN;
    END;

    /*
        Create results table if it doesn't exist
    */
    IF OBJECT_ID(N'dbo.backup_performance_results', N'U') IS NULL
    BEGIN
        CREATE TABLE
            dbo.backup_performance_results
        (
            id integer IDENTITY(1, 1) NOT NULL,
            test_run_id uniqueidentifier NOT NULL,
            database_name sysname NOT NULL,
            backup_path nvarchar(4000) NOT NULL,
            file_count integer NOT NULL,
            compression bit NOT NULL,
            encryption bit NOT NULL,
            buffer_count integer NOT NULL,
            max_transfer_size integer NOT NULL,
            iteration integer NOT NULL,
            buffer_memory_mb decimal(10,2) NULL,
            backup_start_time datetime2(7) NULL,
            backup_end_time datetime2(7) NULL,
            duration_seconds decimal(10,2) NULL,
            backup_size_mb decimal(18,2) NULL,
            compressed_size_mb decimal(18,2) NULL,
            throughput_mbps decimal(18,2) NULL,
            compression_ratio decimal(5,2) NULL,
            server_name nvarchar(128) NULL,
            sql_server_version nvarchar(256) NULL,
            error_message nvarchar(max) NULL,
            CONSTRAINT pk_backup_performance_results
                PRIMARY KEY CLUSTERED (id)
        );
    END;

    /*
        Parse comma-separated lists into temp tables
    */
    DECLARE
        @test_run_id uniqueidentifier = NEWID(),
        @test_run_id_string nvarchar(36);

    SET @test_run_id_string = CONVERT(nvarchar(36), @test_run_id);

    CREATE TABLE
        #file_count_values
    (
        file_count integer NOT NULL
    );

    CREATE TABLE
        #compression_values
    (
        compression integer NOT NULL
    );

    CREATE TABLE
        #encryption_values
    (
        encryption integer NOT NULL
    );

    CREATE TABLE
        #buffer_count_values
    (
        buffer_count integer NOT NULL
    );

    CREATE TABLE
        #max_transfer_size_values
    (
        max_transfer_size integer NOT NULL
    );

    INSERT INTO
        #file_count_values
    (
        file_count
    )
    SELECT
        CONVERT(integer, LTRIM(RTRIM(x.i.value(N'.', N'varchar(20)'))))
    FROM
    (
        SELECT
            CONVERT(xml, N'<i>' + REPLACE(@file_count_list, N',', N'</i><i>') + N'</i>')
    ) AS d (x)
    CROSS APPLY d.x.nodes(N'i') AS x(i)
    WHERE LTRIM(RTRIM(x.i.value(N'.', N'varchar(20)'))) <> N'';

    INSERT INTO
        #compression_values
    (
        compression
    )
    SELECT
        CONVERT(integer, LTRIM(RTRIM(x.i.value(N'.', N'varchar(20)'))))
    FROM
    (
        SELECT
            CONVERT(xml, N'<i>' + REPLACE(@compression_list, N',', N'</i><i>') + N'</i>')
    ) AS d (x)
    CROSS APPLY d.x.nodes(N'i') AS x(i)
    WHERE LTRIM(RTRIM(x.i.value(N'.', N'varchar(20)'))) <> N'';

    INSERT INTO
        #encryption_values
    (
        encryption
    )
    SELECT
        CONVERT(integer, LTRIM(RTRIM(x.i.value(N'.', N'varchar(20)'))))
    FROM
    (
        SELECT
            CONVERT(xml, N'<i>' + REPLACE(@encryption_list, N',', N'</i><i>') + N'</i>')
    ) AS d (x)
    CROSS APPLY d.x.nodes(N'i') AS x(i)
    WHERE LTRIM(RTRIM(x.i.value(N'.', N'varchar(20)'))) <> N'';

    INSERT INTO
        #buffer_count_values
    (
        buffer_count
    )
    SELECT
        CONVERT(integer, LTRIM(RTRIM(x.i.value(N'.', N'varchar(20)'))))
    FROM
    (
        SELECT
            CONVERT(xml, N'<i>' + REPLACE(@buffer_count_list, N',', N'</i><i>') + N'</i>')
    ) AS d (x)
    CROSS APPLY d.x.nodes(N'i') AS x(i)
    WHERE LTRIM(RTRIM(x.i.value(N'.', N'varchar(20)'))) <> N'';

    INSERT INTO
        #max_transfer_size_values
    (
        max_transfer_size
    )
    SELECT
        CONVERT(integer, LTRIM(RTRIM(x.i.value(N'.', N'varchar(20)'))))
    FROM
    (
        SELECT
            CONVERT(xml, N'<i>' + REPLACE(@max_transfer_size_list, N',', N'</i><i>') + N'</i>')
    ) AS d (x)
    CROSS APPLY d.x.nodes(N'i') AS x(i)
    WHERE LTRIM(RTRIM(x.i.value(N'.', N'varchar(20)'))) <> N'';

    /*
        Validate that all parameter lists produced at least one value
    */
    IF NOT EXISTS (SELECT 1/0 FROM #file_count_values)
    BEGIN
        RAISERROR(N'@file_count_list produced no valid values.', 16, 1);
        RETURN;
    END;

    IF NOT EXISTS (SELECT 1/0 FROM #compression_values)
    BEGIN
        RAISERROR(N'@compression_list produced no valid values.', 16, 1);
        RETURN;
    END;

    IF NOT EXISTS (SELECT 1/0 FROM #encryption_values)
    BEGIN
        RAISERROR(N'@encryption_list produced no valid values.', 16, 1);
        RETURN;
    END;

    IF NOT EXISTS (SELECT 1/0 FROM #buffer_count_values)
    BEGIN
        RAISERROR(N'@buffer_count_list produced no valid values.', 16, 1);
        RETURN;
    END;

    IF NOT EXISTS (SELECT 1/0 FROM #max_transfer_size_values)
    BEGIN
        RAISERROR(N'@max_transfer_size_list produced no valid values.', 16, 1);
        RETURN;
    END;

    /*
        If any encryption=1 combinations are requested, verify a usable
        certificate exists in master before we spin up the test loop.
        A certificate is "usable" when its private key is present and
        protected by the master key (pvt_key_encryption_type = 'MK').
        We also accept password-protected keys (pvt_key_encryption_type = 'PW')
        though those are uncommon for backup certs.
        Encrypted backups also require the Database Master Key to exist in master.
    */
    IF EXISTS (SELECT 1/0 FROM #encryption_values WHERE encryption = 1)
    BEGIN
        DECLARE
            @msg nvarchar(2047);

        IF NOT EXISTS
        (
            SELECT 1/0
            FROM master.sys.symmetric_keys
            WHERE name = N'##MS_DatabaseMasterKey##'
        )
        BEGIN
            SET @msg =
                N'@encryption_list includes 1 (encrypted), but no Database Master Key exists in master. ' +
                N'Create one first: USE master; ' +
                N'CREATE MASTER KEY ENCRYPTION BY PASSWORD = N''<strong_password>'';';

            RAISERROR(@msg, 16, 1);
            RETURN;
        END;

        IF NOT EXISTS
        (
            SELECT 1/0
            FROM master.sys.certificates
            WHERE pvt_key_encryption_type IN (N'MK', N'PW')
        )
        BEGIN
            SET @msg =
                N'@encryption_list includes 1 (encrypted), but no certificate with a usable private key was found in master. ' +
                N'Create one first: USE master; ' +
                N'CREATE CERTIFICATE BackupEncryptionCert WITH SUBJECT = N''Backup Encryption''; ' +
                N'Then back it up immediately: BACKUP CERTIFICATE BackupEncryptionCert TO FILE = N''...'';';

            RAISERROR(@msg, 16, 1);
            RETURN;
        END;
    END;

    /*
        Resolve the certificate name once up front so we're not querying
        sys.certificates inside the hot loop on every encrypted iteration.
    */
    DECLARE
        @cert_name sysname = NULL;

    IF EXISTS (SELECT 1/0 FROM #encryption_values WHERE encryption = 1)
    BEGIN
        SELECT TOP (1)
            @cert_name = c.name
        FROM master.sys.certificates AS c
        WHERE c.pvt_key_encryption_type IN (N'MK', N'PW')
        ORDER BY
            c.certificate_id;

        RAISERROR(N'Encryption certificate resolved to: [%s]', 0, 1, @cert_name) WITH NOWAIT;
    END;

    /*
        Generate all test combinations via cross join
    */
    CREATE TABLE
        #test_combinations
    (
        combination_id integer IDENTITY(1, 1) NOT NULL,
        file_count integer NOT NULL,
        compression integer NOT NULL,
        encryption integer NOT NULL,
        buffer_count integer NOT NULL,
        max_transfer_size integer NOT NULL
    );

    INSERT INTO
        #test_combinations
    (
        file_count,
        compression,
        encryption,
        buffer_count,
        max_transfer_size
    )
    SELECT
        fc.file_count,
        cv.compression,
        ev.encryption,
        bc.buffer_count,
        mt.max_transfer_size
    FROM #file_count_values AS fc
    CROSS JOIN #compression_values AS cv
    CROSS JOIN #encryption_values AS ev
    CROSS JOIN #buffer_count_values AS bc
    CROSS JOIN #max_transfer_size_values AS mt;

    DECLARE
        @total_combinations integer =
        (
            SELECT COUNT_BIG(*) FROM #test_combinations
        ),
        @total_tests integer;

    SET @total_tests = @total_combinations * @iterations;

    /*
        Print test run header
    */
    RAISERROR(N'============================================', 0, 1) WITH NOWAIT;
    RAISERROR(N'  Backup Performance Test', 0, 1) WITH NOWAIT;
    RAISERROR(N'============================================', 0, 1) WITH NOWAIT;
    RAISERROR(N'Test Run ID:   %s', 0, 1, @test_run_id_string) WITH NOWAIT;
    RAISERROR(N'Database:      %s', 0, 1, @database_name) WITH NOWAIT;

    DECLARE
        @path_msg nvarchar(4000) = N'Backup Path:   ' + @backup_path;

    RAISERROR(@path_msg, 0, 1) WITH NOWAIT;

    DECLARE
        @count_msg nvarchar(200) =
            N'Combinations:  '
            + CONVERT(nvarchar(10), @total_combinations)
            + N' x '
            + CONVERT(nvarchar(10), @iterations)
            + N' iterations = '
            + CONVERT(nvarchar(10), @total_tests)
            + N' total tests';

    RAISERROR(@count_msg, 0, 1) WITH NOWAIT;

    /*
        Calculate and warn about max buffer memory consumption.
        Buffer memory = BUFFERCOUNT * MAXTRANSFERSIZE (allocated outside buffer pool).
        When buffer_count = 0 (default), SQL Server calculates it as:
            (NumDevices * 3) + NumDevices + (2 * NumVolumes)
        We estimate the default as (file_count * 3) + file_count + 2 for the warning.
    */
    DECLARE
        @max_buffer_memory_mb decimal(10,2),
        @mem_msg nvarchar(200);

    SELECT
        @max_buffer_memory_mb = MAX(
            CASE
                WHEN tc.buffer_count = 0
                THEN ((tc.file_count * 3) + tc.file_count + 2)
                ELSE tc.buffer_count
            END
            * CASE
                  WHEN tc.max_transfer_size = 0
                  THEN 1048576
                  ELSE tc.max_transfer_size
              END
            / 1048576.0
            * CASE tc.compression WHEN 1 THEN 3 ELSE 1 END
        )
    FROM #test_combinations AS tc;

    SET @mem_msg =
        N'Max Buffer RAM: ~'
        + CONVERT(nvarchar(20), CONVERT(decimal(10,1), @max_buffer_memory_mb))
        + N' MB (BUFFERCOUNT x MAXTRANSFERSIZE)';

    RAISERROR(@mem_msg, 0, 1) WITH NOWAIT;

    IF @max_buffer_memory_mb > 1024
    BEGIN
        RAISERROR(N'WARNING: Some combinations will use >1 GB of buffer memory!', 0, 1) WITH NOWAIT;
    END;

    RAISERROR(N'============================================', 0, 1) WITH NOWAIT;
    RAISERROR(N'', 0, 1) WITH NOWAIT;

    /*
        Loop through combinations and iterations
    */
    DECLARE
        @combination_id integer,
        @file_count integer,
        @compression integer,
        @encryption integer,
        @buffer_count integer,
        @max_transfer_size integer,
        @iteration integer,
        @backup_cmd nvarchar(max),
        @backup_start_time datetime2(7),
        @backup_end_time datetime2(7),
        @duration_seconds decimal(10,2),
        @backup_size_mb decimal(18,2),
        @compressed_size_mb decimal(18,2),
        @throughput_mbps decimal(18,2),
        @compression_ratio decimal(5,2),
        @error_message nvarchar(max),
        @test_number integer = 0,
        @progress_msg nvarchar(4000),
        @file_num integer,
        @file_path nvarchar(4000),
        @buffer_memory_mb decimal(10,2),
        @effective_buffer_count integer,
        @effective_mts integer;

    DECLARE
        @test_cursor CURSOR;

    SET @test_cursor = CURSOR LOCAL FAST_FORWARD
    FOR
    SELECT
        tc.combination_id,
        tc.file_count,
        tc.compression,
        tc.encryption,
        tc.buffer_count,
        tc.max_transfer_size
    FROM #test_combinations AS tc
    ORDER BY
        tc.combination_id;

    OPEN @test_cursor;

    FETCH NEXT
    FROM @test_cursor
    INTO
        @combination_id,
        @file_count,
        @compression,
        @encryption,
        @buffer_count,
        @max_transfer_size;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @iteration = 1;

        WHILE @iteration <= @iterations
        BEGIN
            SET @test_number += 1;
            SET @error_message = NULL;
            SET @backup_size_mb = NULL;
            SET @compressed_size_mb = NULL;
            SET @throughput_mbps = NULL;
            SET @compression_ratio = NULL;

            /*
                Calculate effective values and buffer memory for this combination
            */
            SET @effective_buffer_count =
                CASE
                    WHEN @buffer_count = 0
                    THEN (@file_count * 3) + @file_count + 2
                    ELSE @buffer_count
                END;

            SET @effective_mts =
                CASE
                    WHEN @max_transfer_size = 0
                    THEN 1048576
                    ELSE @max_transfer_size
                END;

            /*
                Compressed backups use 3 sets of buffers, uncompressed uses 1
            */
            SET @buffer_memory_mb =
                (@effective_buffer_count * @effective_mts) / 1048576.0
                * CASE @compression WHEN 1 THEN 3 ELSE 1 END;

            /*
                Progress message
            */
            SET @progress_msg =
                NCHAR(10)
                + N'============================================'
                + NCHAR(10)
                + N'Test '
                + CONVERT(nvarchar(10), @test_number)
                + N'/'
                + CONVERT(nvarchar(10), @total_tests)
                + N': Files='
                + CONVERT(nvarchar(10), @file_count)
                + N', Compression='
                + CASE @compression
                      WHEN 1
                      THEN N'YES'
                      ELSE N'NO'
                  END
                + N', Encryption='
                + CASE @encryption
                      WHEN 1
                      THEN N'YES'
                      ELSE N'NO'
                  END
                + N', BufferCount='
                + CASE
                      WHEN @buffer_count = 0
                      THEN N'DEFAULT'
                      ELSE CONVERT(nvarchar(10), @buffer_count)
                  END
                + N', MaxTransferSize='
                + CASE
                      WHEN @max_transfer_size = 0
                      THEN N'DEFAULT'
                      ELSE CONVERT(nvarchar(10), @max_transfer_size)
                  END
                + N', Iteration='
                + CONVERT(nvarchar(10), @iteration)
                + N' [BufferRAM='
                + CONVERT(nvarchar(20), CONVERT(decimal(10,1), @buffer_memory_mb))
                + N' MB]'
                + NCHAR(10);

            RAISERROR(@progress_msg, 0, 1) WITH NOWAIT;

            /*
                Build BACKUP DATABASE command
            */
            SET @backup_cmd =
                N'BACKUP DATABASE '
                + QUOTENAME(@database_name)
                + NCHAR(13) + NCHAR(10)
                + N'TO ';

            SET @file_num = 1;

            WHILE @file_num <= @file_count
            BEGIN
                IF @file_num > 1
                BEGIN
                    SET @backup_cmd +=
                        N','
                        + NCHAR(13) + NCHAR(10)
                        + N'   ';
                END;

                IF @is_nul = 1
                BEGIN
                    SET @backup_cmd += N'DISK = N''NUL''';
                END;
                ELSE
                BEGIN
                    SET @file_path =
                        @backup_path
                        + @database_name
                        + N'_test_'
                        + CONVERT(nvarchar(10), @file_num)
                        + N'_of_'
                        + CONVERT(nvarchar(10), @file_count)
                        + N'.bak';

                    SET @backup_cmd +=
                        N'DISK = N'''
                        + REPLACE(@file_path, N'''', N'''''')
                        + N'''';
                END;

                SET @file_num += 1;
            END;

            /*
                Build WITH clause
            */
            SET @backup_cmd +=
                NCHAR(13) + NCHAR(10)
                + N'WITH INIT, SKIP, FORMAT, STATS = '
                + CONVERT(nvarchar(10), @stats);

            IF @compression = 1
            BEGIN
                SET @backup_cmd += N', COMPRESSION';
            END;
            ELSE
            BEGIN
                SET @backup_cmd += N', NO_COMPRESSION';
            END;

            IF @encryption = 1
            BEGIN
                /*
                    ENCRYPTION clause requires both an ALGORITHM and a SERVER CERTIFICATE.
                    AES_256 is the recommended algorithm (strongest available).
                    Note: encryption and compression can be combined; SQL Server handles both.
                    The certificate name was resolved once before the loop (@cert_name).
                */
                SET @backup_cmd +=
                    N', ENCRYPTION (ALGORITHM = AES_256, SERVER CERTIFICATE = '
                    + QUOTENAME(@cert_name)
                    + N')';
            END;

            IF @buffer_count > 0
            BEGIN
                SET @backup_cmd +=
                    N', BUFFERCOUNT = '
                    + CONVERT(nvarchar(10), @buffer_count);
            END;

            IF @max_transfer_size > 0
            BEGIN
                SET @backup_cmd +=
                    N', MAXTRANSFERSIZE = '
                    + CONVERT(nvarchar(10), @max_transfer_size);
            END;

            SET @backup_cmd += N';';

            IF @debug = 1
            BEGIN
                RAISERROR(@backup_cmd, 0, 1) WITH NOWAIT;
            END;

            /*
                Execute backup with timing
            */
            SET @backup_start_time = SYSDATETIME();

            BEGIN TRY
                EXECUTE sys.sp_executesql
                    @backup_cmd;

                SET @backup_end_time = SYSDATETIME();

                SET @duration_seconds =
                    DATEDIFF(MILLISECOND, @backup_start_time, @backup_end_time) / 1000.0;

                /*
                    Get backup sizes from msdb
                */
                SELECT TOP (1)
                    @backup_size_mb = bs.backup_size / 1048576.0,
                    @compressed_size_mb = bs.compressed_backup_size / 1048576.0
                FROM msdb.dbo.backupset AS bs
                WHERE bs.database_name = @database_name
                AND   bs.type = N'D'
                ORDER BY
                    bs.backup_set_id DESC;

                IF @duration_seconds > 0
                BEGIN
                    SET @throughput_mbps = @backup_size_mb / @duration_seconds;
                END;

                IF  @compression = 1
                AND @compressed_size_mb > 0
                BEGIN
                    SET @compression_ratio = @backup_size_mb / @compressed_size_mb;
                END;
                ELSE
                BEGIN
                    SET @compression_ratio = NULL;
                END;
            END TRY
            BEGIN CATCH
                SET @backup_end_time = SYSDATETIME();

                SET @duration_seconds =
                    DATEDIFF(MILLISECOND, @backup_start_time, @backup_end_time) / 1000.0;

                SET @error_message = ERROR_MESSAGE();

                RAISERROR(N'  ERROR: %s', 0, 1, @error_message) WITH NOWAIT;
            END CATCH;

            /*
                Log results
            */
            INSERT INTO
                dbo.backup_performance_results
            (
                test_run_id,
                database_name,
                backup_path,
                file_count,
                compression,
                encryption,
                buffer_count,
                max_transfer_size,
                iteration,
                buffer_memory_mb,
                backup_start_time,
                backup_end_time,
                duration_seconds,
                backup_size_mb,
                compressed_size_mb,
                throughput_mbps,
                compression_ratio,
                server_name,
                sql_server_version,
                error_message
            )
            VALUES
            (
                @test_run_id,
                @database_name,
                @backup_path,
                @file_count,
                CONVERT(bit, @compression),
                CONVERT(bit, @encryption),
                @buffer_count,
                @max_transfer_size,
                @iteration,
                @buffer_memory_mb,
                @backup_start_time,
                @backup_end_time,
                @duration_seconds,
                @backup_size_mb,
                @compressed_size_mb,
                @throughput_mbps,
                @compression_ratio,
                @@SERVERNAME,
                @@VERSION,
                @error_message
            );

            /*
                Print per-test result
            */
            IF @error_message IS NULL
            BEGIN
                SET @progress_msg =
                    N'  Duration: '
                    + CONVERT(nvarchar(20), CONVERT(decimal(10,1), @duration_seconds))
                    + N's, Size: '
                    + CONVERT(nvarchar(20), CONVERT(decimal(10,1), @backup_size_mb))
                    + N' MB, Throughput: '
                    + CONVERT(nvarchar(20), CONVERT(decimal(10,1), @throughput_mbps))
                    + N' MB/s'
                    + CASE
                          WHEN @compression_ratio IS NOT NULL
                          THEN N', Ratio: '
                               + CONVERT(nvarchar(10), CONVERT(decimal(5,2), @compression_ratio))
                               + N':1'
                          ELSE N''
                      END;

                RAISERROR(@progress_msg, 0, 1) WITH NOWAIT;
            END;

            /*
                Cleanup backup files (skip for NUL and errors)
            */
            IF  @is_nul = 0
            AND @error_message IS NULL
            BEGIN
                SET @file_num = 1;

                WHILE @file_num <= @file_count
                BEGIN
                    SET @file_path =
                        @backup_path
                        + @database_name
                        + N'_test_'
                        + CONVERT(nvarchar(10), @file_num)
                        + N'_of_'
                        + CONVERT(nvarchar(10), @file_count)
                        + N'.bak';

                    BEGIN TRY
                        EXECUTE master.sys.xp_delete_file
                            0,
                            @file_path;
                    END TRY
                    BEGIN CATCH
                        RAISERROR
                        (
                            N'  Warning: Could not delete %s',
                            0,
                            1,
                            @file_path
                        ) WITH NOWAIT;
                    END CATCH;

                    SET @file_num += 1;
                END;
            END;

            SET @iteration += 1;
        END;

        FETCH NEXT
        FROM @test_cursor
        INTO
            @combination_id,
            @file_count,
            @compression,
            @encryption,
            @buffer_count,
            @max_transfer_size;
    END;

    /*
        Print best configuration via RAISERROR so it's visible in messages
    */
    DECLARE
        @best_file_count integer,
        @best_compression bit,
        @best_encryption bit,
        @best_buffer_count integer,
        @best_max_transfer_size integer,
        @best_avg_throughput decimal(18,2),
        @best_avg_duration decimal(10,2),
        @best_msg nvarchar(4000);

    SELECT TOP (1)
        @best_file_count = bpr.file_count,
        @best_compression = bpr.compression,
        @best_encryption = bpr.encryption,
        @best_buffer_count = bpr.buffer_count,
        @best_max_transfer_size = bpr.max_transfer_size,
        @best_avg_throughput = AVG(bpr.throughput_mbps),
        @best_avg_duration = AVG(bpr.duration_seconds)
    FROM dbo.backup_performance_results AS bpr
    WHERE bpr.test_run_id = @test_run_id
    AND   bpr.error_message IS NULL
    GROUP BY
        bpr.file_count,
        bpr.compression,
        bpr.encryption,
        bpr.buffer_count,
        bpr.max_transfer_size
    ORDER BY
        AVG(bpr.throughput_mbps) DESC,
        AVG(bpr.duration_seconds) ASC,
        AVG(bpr.buffer_memory_mb) ASC;

    RAISERROR(N'', 0, 1) WITH NOWAIT;
    RAISERROR(N'============================================', 0, 1) WITH NOWAIT;
    RAISERROR(N'  Test Run Complete', 0, 1) WITH NOWAIT;
    RAISERROR(N'============================================', 0, 1) WITH NOWAIT;

    SET @best_msg =
        N'  Best: Files='
        + CONVERT(nvarchar(10), @best_file_count)
        + N', Compression='
        + CASE @best_compression
              WHEN 1
              THEN N'YES'
              ELSE N'NO'
          END
        + N', Encryption='
        + CASE @best_encryption
              WHEN 1
              THEN N'YES'
              ELSE N'NO'
          END
        + N', BufferCount='
        + CASE
              WHEN @best_buffer_count = 0
              THEN N'DEFAULT'
              ELSE CONVERT(nvarchar(10), @best_buffer_count)
          END
        + N', MaxTransferSize='
        + CASE
              WHEN @best_max_transfer_size = 0
              THEN N'DEFAULT'
              ELSE CONVERT(nvarchar(10), @best_max_transfer_size)
          END;

    RAISERROR(@best_msg, 0, 1) WITH NOWAIT;

    SET @best_msg =
        N'  Avg Throughput: '
        + CONVERT(nvarchar(20), CONVERT(decimal(10,1), @best_avg_throughput))
        + N' MB/s, Avg Duration: '
        + CONVERT(nvarchar(20), CONVERT(decimal(10,1), @best_avg_duration))
        + N's';

    RAISERROR(@best_msg, 0, 1) WITH NOWAIT;
    RAISERROR(N'============================================', 0, 1) WITH NOWAIT;
    RAISERROR(N'', 0, 1) WITH NOWAIT;

    /*
        Result Set 1: Full summary ranked by throughput
        Every tested configuration ranked #1 (best) to #N (worst) by average throughput.
        Use this to see all configurations side by side and identify the top performers.
    */
    RAISERROR(N'-- [1/5] All configurations ranked by throughput (higher = faster backups):', 0, 1) WITH NOWAIT;

    SELECT
        rank =
            ROW_NUMBER() OVER
            (
                ORDER BY
                    AVG(bpr.throughput_mbps) DESC,
                    AVG(bpr.buffer_memory_mb) ASC
            ),
        bpr.file_count,
        compression =
            CASE bpr.compression
                 WHEN 1
                 THEN N'YES'
                 ELSE N'NO'
            END,
        encryption =
            CASE bpr.encryption
                 WHEN 1
                 THEN N'YES'
                 ELSE N'NO'
            END,
        buffer_count =
            CASE bpr.buffer_count
                 WHEN 0
                 THEN N'DEFAULT'
                 ELSE CONVERT(nvarchar(10), bpr.buffer_count)
            END,
        max_transfer_size =
            CASE bpr.max_transfer_size
                 WHEN 0
                 THEN N'DEFAULT'
                 ELSE CONVERT(nvarchar(10), bpr.max_transfer_size)
            END,
        tests =
            COUNT_BIG(*),
        avg_duration_sec =
            AVG(bpr.duration_seconds),
        avg_throughput_mbps =
            AVG(bpr.throughput_mbps),
        max_throughput_mbps =
            MAX(bpr.throughput_mbps),
        avg_backup_size_mb =
            AVG(bpr.backup_size_mb),
        avg_compressed_size_mb =
            AVG(bpr.compressed_size_mb),
        avg_compression_ratio =
            AVG(bpr.compression_ratio),
        avg_buffer_memory_mb =
            AVG(bpr.buffer_memory_mb),
        errors =
            SUM(CASE WHEN bpr.error_message IS NOT NULL THEN 1 ELSE 0 END)
    FROM dbo.backup_performance_results AS bpr
    WHERE bpr.test_run_id = @test_run_id
    GROUP BY
        bpr.file_count,
        bpr.compression,
        bpr.encryption,
        bpr.buffer_count,
        bpr.max_transfer_size
    ORDER BY
        AVG(bpr.throughput_mbps) DESC,
        AVG(bpr.duration_seconds) ASC,
        AVG(bpr.buffer_memory_mb) ASC;

    /*
        Result Set 2: Best configuration per compression + encryption pairing
        Shows the fastest config for each combination of compression and encryption.
        Four possible pairings: NO/NO, YES/NO, NO/YES, YES/YES.
        Useful for comparing the overhead of encryption within each compression mode.
    */
    RAISERROR(N'-- [2/5] Best config per compression+encryption pairing (fastest in each category):', 0, 1) WITH NOWAIT;

    WITH
        ranked
    (
        file_count,
        compression,
        encryption,
        buffer_count,
        max_transfer_size,
        avg_throughput_mbps,
        avg_duration_sec,
        avg_compressed_size_mb,
        avg_compression_ratio,
        rn
    ) AS
    (
        SELECT
            bpr.file_count,
            bpr.compression,
            bpr.encryption,
            bpr.buffer_count,
            bpr.max_transfer_size,
            AVG(bpr.throughput_mbps),
            AVG(bpr.duration_seconds),
            AVG(bpr.compressed_size_mb),
            AVG(bpr.compression_ratio),
            ROW_NUMBER() OVER
            (
                PARTITION BY
                    bpr.compression,
                    bpr.encryption
                ORDER BY
                    AVG(bpr.throughput_mbps) DESC,
                    AVG(bpr.duration_seconds) ASC,
                    AVG(bpr.buffer_memory_mb) ASC
            )
        FROM dbo.backup_performance_results AS bpr
        WHERE bpr.test_run_id = @test_run_id
        AND   bpr.error_message IS NULL
        GROUP BY
            bpr.file_count,
            bpr.compression,
            bpr.encryption,
            bpr.buffer_count,
            bpr.max_transfer_size
    )
    SELECT
        compression =
            CASE r.compression
                WHEN 1
                THEN N'YES'
                ELSE N'NO'
            END,
        encryption =
            CASE r.encryption
                WHEN 1
                THEN N'YES'
                ELSE N'NO'
            END,
        r.file_count,
        buffer_count =
            CASE r.buffer_count
                WHEN 0
                THEN N'DEFAULT'
                ELSE CONVERT(nvarchar(10), r.buffer_count)
            END,
        max_transfer_size =
            CASE r.max_transfer_size
                WHEN 0
                THEN N'DEFAULT'
                ELSE CONVERT(nvarchar(10), r.max_transfer_size)
            END,
        r.avg_throughput_mbps,
        r.avg_duration_sec,
        r.avg_compressed_size_mb,
        r.avg_compression_ratio
    FROM ranked AS r
    WHERE r.rn = 1
    ORDER BY
        r.compression,
        r.encryption;

    /*
        Result Set 3: Parameter impact
        Averages throughput across all other settings to isolate each parameter's effect.
        Compare values within a parameter_name group to see how much that knob matters.
        Large spread = high impact knob, small spread = doesn't matter much.
    */
    RAISERROR(N'-- [3/5] Parameter impact (which knob matters most? larger pct_improvement = bigger effect):', 0, 1) WITH NOWAIT;

    WITH
        raw_impact
    (
        parameter_name,
        parameter_value,
        avg_throughput_mbps,
        avg_duration_sec,
        tests
    ) AS
    (
        SELECT
            N'file_count',
            CONVERT(nvarchar(20), bpr.file_count),
            AVG(bpr.throughput_mbps),
            AVG(bpr.duration_seconds),
            COUNT_BIG(*)
        FROM dbo.backup_performance_results AS bpr
        WHERE bpr.test_run_id = @test_run_id
        AND   bpr.error_message IS NULL
        GROUP BY
            bpr.file_count

        UNION ALL

        SELECT
            N'compression',
            CASE bpr.compression
                WHEN 1
                THEN N'YES'
                ELSE N'NO'
            END,
            AVG(bpr.throughput_mbps),
            AVG(bpr.duration_seconds),
            COUNT_BIG(*)
        FROM dbo.backup_performance_results AS bpr
        WHERE bpr.test_run_id = @test_run_id
        AND   bpr.error_message IS NULL
        GROUP BY
            bpr.compression

        UNION ALL

        SELECT
            N'encryption',
            CASE bpr.encryption
                WHEN 1
                THEN N'YES'
                ELSE N'NO'
            END,
            AVG(bpr.throughput_mbps),
            AVG(bpr.duration_seconds),
            COUNT_BIG(*)
        FROM dbo.backup_performance_results AS bpr
        WHERE bpr.test_run_id = @test_run_id
        AND   bpr.error_message IS NULL
        GROUP BY
            bpr.encryption

        UNION ALL

        SELECT
            N'buffer_count',
            CASE bpr.buffer_count
                WHEN 0
                THEN N'DEFAULT'
                ELSE CONVERT(nvarchar(20), bpr.buffer_count)
            END,
            AVG(bpr.throughput_mbps),
            AVG(bpr.duration_seconds),
            COUNT_BIG(*)
        FROM dbo.backup_performance_results AS bpr
        WHERE bpr.test_run_id = @test_run_id
        AND   bpr.error_message IS NULL
        GROUP BY
            bpr.buffer_count

        UNION ALL

        SELECT
            N'max_transfer_size',
            CASE bpr.max_transfer_size
                WHEN 0
                THEN N'DEFAULT'
                ELSE CONVERT(nvarchar(20), bpr.max_transfer_size)
            END,
            AVG(bpr.throughput_mbps),
            AVG(bpr.duration_seconds),
            COUNT_BIG(*)
        FROM dbo.backup_performance_results AS bpr
        WHERE bpr.test_run_id = @test_run_id
        AND   bpr.error_message IS NULL
        GROUP BY
            bpr.max_transfer_size
    )
    SELECT
        ri.parameter_name,
        ri.parameter_value,
        ri.avg_throughput_mbps,
        ri.avg_duration_sec,
        pct_improvement =
            CASE
                WHEN MIN(ri.avg_throughput_mbps) OVER
                (
                    PARTITION BY
                        ri.parameter_name
                ) > 0
                THEN CONVERT
                     (
                         decimal(5,1),
                         (ri.avg_throughput_mbps - MIN(ri.avg_throughput_mbps) OVER
                         (
                             PARTITION BY
                                 ri.parameter_name
                         ))
                         / MIN(ri.avg_throughput_mbps) OVER
                         (
                             PARTITION BY
                                 ri.parameter_name
                         )
                         * 100.0
                     )
                ELSE NULL
            END,
        group_spread_pct =
            CASE
                WHEN MIN(ri.avg_throughput_mbps) OVER
                (
                    PARTITION BY
                        ri.parameter_name
                ) > 0
                THEN CONVERT
                     (
                         decimal(5,1),
                         (MAX(ri.avg_throughput_mbps) OVER
                         (
                             PARTITION BY
                                 ri.parameter_name
                         )
                         - MIN(ri.avg_throughput_mbps) OVER
                         (
                             PARTITION BY
                                 ri.parameter_name
                         ))
                         / MIN(ri.avg_throughput_mbps) OVER
                         (
                             PARTITION BY
                                 ri.parameter_name
                         )
                         * 100.0
                     )
                ELSE NULL
            END,
        ri.tests
    FROM raw_impact AS ri
    ORDER BY
        ri.parameter_name,
        ri.avg_throughput_mbps DESC;

    /*
        Result Set 4: Efficiency (throughput per MB of buffer RAM)
        Top 10 configs by throughput-per-MB-of-buffer-memory, but only configs
        that achieve at least 80% of the best throughput. Filters out configs
        that are "efficient" only because they're slow and use no memory.
        pct_of_best shows how close each config is to the fastest overall.
    */
    RAISERROR(N'-- [4/5] Efficiency (best throughput per MB of RAM, filtered to configs within 80%% of peak):', 0, 1) WITH NOWAIT;

    DECLARE
        @best_throughput decimal(18,2);

    SELECT
        @best_throughput = MAX(bpr.throughput_mbps)
    FROM dbo.backup_performance_results AS bpr
    WHERE bpr.test_run_id = @test_run_id
    AND   bpr.error_message IS NULL;

    SELECT TOP (10)
        bpr.file_count,
        compression =
            CASE bpr.compression
                WHEN 1
                THEN N'YES'
                ELSE N'NO'
            END,
        encryption =
            CASE bpr.encryption
                WHEN 1
                THEN N'YES'
                ELSE N'NO'
            END,
        buffer_count =
            CASE bpr.buffer_count
                WHEN 0
                THEN N'DEFAULT'
                ELSE CONVERT(nvarchar(10), bpr.buffer_count)
            END,
        max_transfer_size =
            CASE bpr.max_transfer_size
                WHEN 0
                THEN N'DEFAULT'
                ELSE CONVERT(nvarchar(10), bpr.max_transfer_size)
            END,
        avg_throughput_mbps =
            AVG(bpr.throughput_mbps),
        pct_of_best =
            CONVERT(decimal(5,1), AVG(bpr.throughput_mbps) / @best_throughput * 100),
        avg_buffer_memory_mb =
            AVG(bpr.buffer_memory_mb),
        throughput_per_mb_ram =
            CASE
                WHEN AVG(bpr.buffer_memory_mb) > 0
                THEN AVG(bpr.throughput_mbps) / AVG(bpr.buffer_memory_mb)
                ELSE NULL
            END
    FROM dbo.backup_performance_results AS bpr
    WHERE bpr.test_run_id = @test_run_id
    AND   bpr.error_message IS NULL
    GROUP BY
        bpr.file_count,
        bpr.compression,
        bpr.encryption,
        bpr.buffer_count,
        bpr.max_transfer_size
    HAVING
        AVG(bpr.throughput_mbps) >= @best_throughput * 0.8
    ORDER BY
        CASE
            WHEN AVG(bpr.buffer_memory_mb) > 0
            THEN AVG(bpr.throughput_mbps) / AVG(bpr.buffer_memory_mb)
            ELSE NULL
        END DESC;

    /*
        Result Set 5: Consistency (only when @iterations > 1)
        Shows min, max, and standard deviation of throughput per config.
        Low stddev = predictable performance. High stddev = results varied across iterations,
        which may indicate contention, caching effects, or I/O variability.
    */
    IF @iterations > 1
    BEGIN
        RAISERROR(N'-- [5/5] Consistency (lower stddev = more predictable, ordered most to least stable):', 0, 1) WITH NOWAIT;

        SELECT
            bpr.file_count,
            compression =
                CASE bpr.compression
                    WHEN 1
                    THEN N'YES'
                    ELSE N'NO'
                END,
            encryption =
                CASE bpr.encryption
                    WHEN 1
                    THEN N'YES'
                    ELSE N'NO'
                END,
            buffer_count =
                CASE bpr.buffer_count
                    WHEN 0
                    THEN N'DEFAULT'
                    ELSE CONVERT(nvarchar(10), bpr.buffer_count)
                END,
            max_transfer_size =
                CASE bpr.max_transfer_size
                    WHEN 0
                    THEN N'DEFAULT'
                    ELSE CONVERT(nvarchar(10), bpr.max_transfer_size)
                END,
            avg_throughput_mbps =
                AVG(bpr.throughput_mbps),
            min_throughput_mbps =
                MIN(bpr.throughput_mbps),
            max_throughput_mbps =
                MAX(bpr.throughput_mbps),
            stddev_throughput =
                STDEV(bpr.throughput_mbps),
            iterations =
                COUNT_BIG(*)
        FROM dbo.backup_performance_results AS bpr
        WHERE bpr.test_run_id = @test_run_id
        AND   bpr.error_message IS NULL
        GROUP BY
            bpr.file_count,
            bpr.compression,
            bpr.encryption,
            bpr.buffer_count,
            bpr.max_transfer_size
        ORDER BY
            STDEV(bpr.throughput_mbps) ASC;
    END;
END;
GO
