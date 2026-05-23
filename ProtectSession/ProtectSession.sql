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
██████╗ ██████╗  ██████╗ ████████╗███████╗ ██████╗████████╗
██╔══██╗██╔══██╗██╔═══██╗╚══██╔══╝██╔════╝██╔════╝╚══██╔══╝
██████╔╝██████╔╝██║   ██║   ██║   █████╗  ██║        ██║
██╔═══╝ ██╔══██╗██║   ██║   ██║   ██╔══╝  ██║        ██║
██║     ██║  ██║╚██████╔╝   ██║   ███████╗╚██████╗   ██║
╚═╝     ╚═╝  ╚═╝ ╚═════╝    ╚═╝   ╚══════╝ ╚═════╝   ╚═╝

███████╗███████╗███████╗███████╗██╗ ██████╗ ███╗   ██╗
██╔════╝██╔════╝██╔════╝██╔════╝██║██╔═══██╗████╗  ██║
███████╗█████╗  ███████╗███████╗██║██║   ██║██╔██╗ ██║
╚════██║██╔══╝  ╚════██║╚════██║██║██║   ██║██║╚██╗██║
███████║███████╗███████║███████║██║╚██████╔╝██║ ╚████║
╚══════╝╚══════╝╚══════╝╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═══╝


Copyright 2026 Darling Data, LLC
https://www.erikdarling.com/

For usage and licensing details, run:
EXECUTE dbo.ProtectSession
    @help = 1;

For working through errors:
EXECUTE dbo.ProtectSession
    @debug = 1;

For support, head over to GitHub:
https://code.erikdarling.com

*/

IF OBJECT_ID(N'dbo.ProtectSession', N'P') IS NULL
    EXECUTE (N'CREATE PROCEDURE dbo.ProtectSession AS RETURN 138;');
GO

ALTER PROCEDURE
    dbo.ProtectSession
(
    @protected_session_id integer = NULL, /*the session_id to keep alive*/
    @block_threshold_seconds integer = 5, /*how long the protected session must wait on an LCK before we act*/
    @check_interval_seconds integer = 1, /*how often each cycle samples and acts*/
    @abort_on_modification_block bit = 0, /*if 1, kill the protected session when blocked by a permanent-data modification*/
    @kill_modification_blockers bit = 0, /*if 1, kill permanent-data modification blockers too (rolls back their work)*/
    @abort_reason nvarchar(2048) = NULL, /*free-text reason printed in the abort message*/
    @debug bit = 0, /*prints each cycle's #blockers contents*/
    @help bit = 0, /*how you got here*/
    @version varchar(5) = NULL OUTPUT, /*OUTPUT; for support*/
    @version_date datetime = NULL OUTPUT /*OUTPUT; for support*/
)
WITH RECOMPILE
AS
BEGIN
    /*
    No SET XACT_ABORT ON here. ProtectSession is a long-running watchdog with
    BEGIN TRY/CATCH around its work; XACT_ABORT would terminate the loop on the
    first transient error (a session dying between sampling and KILL, a brief
    DMV unavailability) instead of letting the catch swallow it and the next
    cycle recover. Deliberate omission, not a missing setting.
    */
    SET STATISTICS XML OFF;
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    SELECT
        @version = '1.0',
        @version_date = '20260522';

    BEGIN TRY
        IF @help = 1
        BEGIN
            /*
            Introduction
            */
            SELECT
                help = 'hi, i''m ProtectSession!' UNION ALL
            SELECT 'you got me from https://code.erikdarling.com' UNION ALL
            SELECT 'i watch one session and decide what to do with whoever is blocking it.' UNION ALL
            SELECT 'by default i only kill blockers that aren''t durably modifying permanent data --' UNION ALL
            SELECT 'reads, and modifications that only touch #temp / ##temp / table variables.' UNION ALL
            SELECT 'a blocker holding X/IX/U/SIX/BU/Sch-M on an OBJECT outside tempdb counts as a' UNION ALL
            SELECT 'permanent-data modification and gets left alone -- unless you flip a flag:' UNION ALL
            SELECT ' * @kill_modification_blockers = 1 -> kill it anyway (rolls back its work)' UNION ALL
            SELECT ' * @abort_on_modification_block = 1 -> kill the protected session instead' UNION ALL
            SELECT 'classification reads sys.dm_tran_locks, never the blocker''s current command,' UNION ALL
            SELECT 'so it stays correct when the current statement is a SELECT but the transaction' UNION ALL
            SELECT 'still holds X locks from an earlier UPDATE, or when the blocker is sleeping.' UNION ALL
            SELECT 'each cycle also walks the blocking chain upstream for diagnostics --' UNION ALL
            SELECT 'the KILL target stays the immediate blocker, since that''s what frees you.' UNION ALL
            SELECT 'sessions are fingerprinted by (session_id, login_time) before any KILL,' UNION ALL
            SELECT 'so a recycled spid can''t trick me into killing the wrong session.' UNION ALL
            SELECT 'run me from a separate connection. from https://erikdarling.com';

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
                        WHEN N'@protected_session_id' THEN N'the session_id you want kept alive (watched, not run from)'
                        WHEN N'@block_threshold_seconds' THEN N'how long the protected session must wait on an LCK before any action'
                        WHEN N'@check_interval_seconds' THEN N'how often each cycle samples and acts'
                        WHEN N'@abort_on_modification_block' THEN N'when blocked by a permanent-data modification, kill the protected session instead of the blocker'
                        WHEN N'@kill_modification_blockers' THEN N'kill permanent-data modification blockers too (rolls back their work)'
                        WHEN N'@abort_reason' THEN N'free-text reason printed when the protected session is aborted'
                        WHEN N'@debug' THEN N'prints each cycle''s #blockers contents'
                        WHEN N'@help' THEN N'how you got here'
                        WHEN N'@version' THEN N'OUTPUT; for support'
                        WHEN N'@version_date' THEN N'OUTPUT; for support'
                    END,
                valid_inputs =
                    CASE
                        ap.name
                        WHEN N'@protected_session_id' THEN N'a session_id of another spid'
                        WHEN N'@block_threshold_seconds' THEN N'a positive integer'
                        WHEN N'@check_interval_seconds' THEN N'a positive integer'
                        WHEN N'@abort_on_modification_block' THEN N'0 or 1'
                        WHEN N'@kill_modification_blockers' THEN N'0 or 1'
                        WHEN N'@abort_reason' THEN N'any string or NULL'
                        WHEN N'@debug' THEN N'0 or 1'
                        WHEN N'@help' THEN N'0 or 1'
                        WHEN N'@version' THEN N'none'
                        WHEN N'@version_date' THEN N'none'
                    END,
                defaults =
                    CASE
                        ap.name
                        WHEN N'@protected_session_id' THEN N'(required)'
                        WHEN N'@block_threshold_seconds' THEN N'5'
                        WHEN N'@check_interval_seconds' THEN N'1'
                        WHEN N'@abort_on_modification_block' THEN N'0'
                        WHEN N'@kill_modification_blockers' THEN N'0'
                        WHEN N'@abort_reason' THEN N'NULL'
                        WHEN N'@debug' THEN N'0'
                        WHEN N'@help' THEN N'0'
                        WHEN N'@version' THEN N'none; OUTPUT'
                        WHEN N'@version_date' THEN N'none; OUTPUT'
                    END
            FROM sys.all_parameters AS ap
            JOIN sys.all_objects AS o
              ON ap.object_id = o.object_id
            JOIN sys.types AS t
              ON  ap.system_type_id = t.system_type_id
              AND ap.user_type_id = t.user_type_id
            WHERE o.name = N'ProtectSession'
            ORDER BY
                ap.parameter_id
            OPTION(MAXDOP 1, RECOMPILE);

            /*
            MIT License
            */
            SELECT
                mit_license_yo = 'i am MIT licensed, so like, do whatever'

            UNION ALL

            SELECT
                mit_license_yo = 'see printed messages for full license';

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
        END;

        IF @protected_session_id IS NULL
        BEGIN
            RAISERROR(N'@protected_session_id is required.', 16, 1);
            RETURN;
        END;

        IF @protected_session_id = @@SPID
        BEGIN
            RAISERROR(N'@protected_session_id cannot be the session running ProtectSession (%d). Run this procedure from a separate connection.', 16, 1, @@SPID);
            RETURN;
        END;

        IF @block_threshold_seconds < 1
        BEGIN
            RAISERROR(N'@block_threshold_seconds must be >= 1.', 16, 1);
            RETURN;
        END;

        IF @check_interval_seconds < 1
        BEGIN
            RAISERROR(N'@check_interval_seconds must be >= 1.', 16, 1);
            RETURN;
        END;

        /*
        Capture the protected session's login_time as a fingerprint. SQL Server
        recycles session_ids aggressively (a closed spid can be reassigned to a
        new connection within microseconds), so the spid alone is not a stable
        identifier across cycles -- or even between a snapshot of dm_exec_sessions
        and a subsequent KILL. The (session_id, login_time) pair is stable for
        the lifetime of the session; if the spid is reused, login_time changes.
        We re-check this pair before doing anything destructive. Declared here
        (separately from the main DECLARE block below) so it is in scope for
        the active-session check that immediately follows.
        */
        DECLARE @protected_login_time datetime;

        SELECT
            @protected_login_time = s.login_time
        FROM sys.dm_exec_sessions AS s
        WHERE s.session_id = @protected_session_id;

        IF @protected_login_time IS NULL
        BEGIN
            RAISERROR(N'Session %d is not currently active.', 16, 1, @protected_session_id);
            RETURN;
        END;

        DECLARE
            @sleep_for char(8) =
                CONVERT
                (
                    char(8),
                    DATEADD(SECOND, @check_interval_seconds, CONVERT(datetime, N'19000101', 112)),
                    108
                ),
            @threshold_ms integer = @block_threshold_seconds * 1000,
            @msg nvarchar(2048) = N'',
            @kill_sql nvarchar(128) = N'',
            @blocker_session_id integer = NULL,
            @blocker_wait_ms integer = NULL,
            @blocker_command nvarchar(32) = NULL,
            @blocker_login_time datetime = NULL,
            @blocker_chain_depth integer = NULL,
            @blocker_lead_session_id integer = NULL,
            @blocker_contended_db sysname = NULL,
            @blocker_contended_type nvarchar(60) = NULL,
            @blocker_contended_object sysname = NULL;

        DECLARE
            @blocker_kill_cursor cursor;

        CREATE TABLE
            #blockers
        (
            blocker_session_id integer NOT NULL,         /* the immediate blocker -- kill target */
            wait_type nvarchar(60) NULL,
            wait_milliseconds integer NOT NULL,
            blocker_command nvarchar(32) NULL,
            blocker_status nvarchar(30) NULL,
            blocker_login_time datetime NULL,            /* fingerprint to detect spid reuse between snapshot and KILL */
            is_modification bit NOT NULL,
            chain_depth integer NOT NULL,                /* 0 = single-hop, >0 = at tail of a chain */
            lead_blocker_session_id integer NULL,        /* terminal session in the blocking chain, NULL when chain_depth = 0 */
            contended_db_name sysname NULL,              /* resource the protected session is waiting on */
            contended_resource_type nvarchar(60) NULL,
            contended_object_name sysname NULL,          /* only populated for OBJECT-type contention */
            statement_text nvarchar(max) NULL
        );

        CREATE UNIQUE CLUSTERED INDEX
            cx_blockers
        ON #blockers
            (blocker_session_id);

        WHILE EXISTS
        (
            SELECT
                1/0
            FROM sys.dm_exec_sessions AS s
            WHERE s.session_id = @protected_session_id
            AND   s.login_time = @protected_login_time
        )
        BEGIN
            TRUNCATE TABLE #blockers;

            /*
            Snapshot: take the protected session's own LCK_M_* waits and, for
            each immediate blocker, also walk the blocking chain upstream to
            capture chain_depth + the lead session id (diagnostic only -- the
            kill target stays the immediate blocker, because that's the session
            holding the lock the protected session is actually waiting on).
            Also resolve the contended resource (database + object when
            applicable) from sys.dm_tran_locks for the protected session's
            WAIT-status row. wait_milliseconds is the protected session's
            wait_time on this resource.
            */
            WITH immediate_blocker AS
            (
                SELECT
                    blocker_session_id = w.blocker_session_id,
                    wait_type = w.wait_type,
                    wait_milliseconds = w.wait_milliseconds
                FROM
                (
                    SELECT
                        blocker_session_id = pr.blocking_session_id,
                        wait_type = pr.wait_type,
                        wait_milliseconds = pr.wait_time,
                        rn =
                            ROW_NUMBER() OVER
                            (
                                PARTITION BY
                                    pr.blocking_session_id
                                ORDER BY
                                    pr.wait_time DESC
                            )
                    FROM sys.dm_exec_requests AS pr
                    WHERE pr.session_id = @protected_session_id
                    AND   pr.blocking_session_id > 0
                    AND   pr.blocking_session_id <> @protected_session_id
                    AND   pr.wait_type LIKE N'LCK%'
                    AND   EXISTS
                          (
                              SELECT
                                  1/0
                              FROM sys.dm_exec_sessions AS bs
                              WHERE bs.session_id = pr.blocking_session_id
                              AND   bs.is_user_process = 1
                          )
                ) AS w
                WHERE w.rn = 1
            ),
            blocking_chain AS
            (
                /*
                Anchor: each immediate blocker enters the chain at depth 0.
                Recurse upstream by following each session's own
                blocking_session_id in dm_exec_requests. Recursion stops
                naturally when the next hop has no active request (sleeping
                blocker = end of chain) or its blocking_session_id is 0
                (running, not blocked). depth < 16 is a safety bound; the
                protected session is excluded to defend against pathological
                cycles.
                */
                SELECT
                    immediate_blocker_id = ib.blocker_session_id,
                    depth = 0,
                    session_id = ib.blocker_session_id
                FROM immediate_blocker AS ib

                UNION ALL

                SELECT
                    immediate_blocker_id = c.immediate_blocker_id,
                    depth = c.depth + 1,
                    session_id = bpr.blocking_session_id
                FROM blocking_chain AS c
                INNER JOIN sys.dm_exec_requests AS bpr
                  ON bpr.session_id = c.session_id
                WHERE bpr.blocking_session_id > 0
                AND   bpr.blocking_session_id <> @protected_session_id
                AND   c.depth < 16
            )
            INSERT
                #blockers
            WITH
                (TABLOCK)
            (
                blocker_session_id,
                wait_type,
                wait_milliseconds,
                blocker_command,
                blocker_status,
                blocker_login_time,
                is_modification,
                chain_depth,
                lead_blocker_session_id,
                contended_db_name,
                contended_resource_type,
                contended_object_name,
                statement_text
            )
            SELECT
                blocker_session_id = ib.blocker_session_id,
                wait_type = ib.wait_type,
                wait_milliseconds = ib.wait_milliseconds,
                blocker_command = blocker.command,
                blocker_status = blocker.status,
                blocker_login_time = blocker_sess.login_time,
                /*
                Classify the immediate blocker (the kill target) purely by the
                locks it actually holds -- NEVER by its current command. The
                command is unreliable in both directions: a blocker whose
                current statement is a SELECT can still hold X locks from an
                UPDATE in an earlier statement of the same transaction, and
                SELECT ... INTO a permanent table is itself a modification
                reported with command = 'SELECT'. is_modification = 1 when
                sys.dm_tran_locks shows the blocker holding a modification or
                schema-change lock (X/IX/U/SIX/BU/Sch-M) on an OBJECT in a
                database other than tempdb -- i.e. it is durably changing
                permanent data or schema. Anything else -- a read-only SELECT
                (which holds only IS/S/RangeS-S), or a blocker whose only such
                locks are on tempdb objects (#temp, ##temp, table variables,
                work tables) -- is is_modification = 0: killable and cheap, and
                never a reason to abort the protected session. Reading the
                held locks (not the statement text) also means this still
                classifies a sleeping blocker with no active request correctly.
                */
                is_modification =
                    CASE
                        WHEN EXISTS
                             (
                                 SELECT
                                     1/0
                                 FROM sys.dm_tran_locks AS tl
                                 WHERE tl.request_session_id = ib.blocker_session_id
                                 AND   tl.request_status = N'GRANT'
                                 AND   tl.resource_type = N'OBJECT'
                                 AND   tl.resource_database_id <> 2
                                 AND   tl.request_mode IN
                                       (N'X', N'IX', N'U', N'SIX', N'BU', N'Sch-M')
                             )
                        THEN 1
                        ELSE 0
                    END,
                chain_depth = ct.chain_depth,
                lead_blocker_session_id =
                    CASE
                        WHEN ct.chain_depth > 0
                        THEN ct.lead_blocker_session_id
                        ELSE NULL
                    END,
                contended_db_name = DB_NAME(wt.resource_database_id),
                contended_resource_type = wt.resource_type,
                contended_object_name =
                    CASE
                        WHEN wt.resource_type = N'OBJECT'
                        THEN OBJECT_NAME(wt.resource_associated_entity_id, wt.resource_database_id)
                        ELSE NULL
                    END,
                statement_text =
                    SUBSTRING
                    (
                        t.text,
                        (blocker.statement_start_offset / 2) + 1,
                        CASE
                            WHEN blocker.statement_end_offset = -1
                            THEN DATALENGTH(t.text)
                            ELSE (blocker.statement_end_offset - blocker.statement_start_offset) / 2 + 1
                        END
                    )
            FROM immediate_blocker AS ib
            CROSS APPLY
            (
                SELECT TOP (1)
                    chain_depth = bc.depth,
                    lead_blocker_session_id = bc.session_id
                FROM blocking_chain AS bc
                WHERE bc.immediate_blocker_id = ib.blocker_session_id
                ORDER BY
                    bc.depth DESC
            ) AS ct
            LEFT JOIN sys.dm_exec_requests AS blocker
              ON blocker.session_id = ib.blocker_session_id
            LEFT JOIN sys.dm_exec_sessions AS blocker_sess
              ON blocker_sess.session_id = ib.blocker_session_id
            OUTER APPLY sys.dm_exec_sql_text(blocker.sql_handle) AS t
            OUTER APPLY
            (
                /*
                Pick the resource the protected session is currently waiting on
                (a WAIT-status row in dm_tran_locks). Prefer OBJECT > HOBT >
                KEY > RID > PAGE so the most informative resource wins when
                more than one wait is recorded.
                */
                SELECT TOP (1)
                    tl.resource_database_id,
                    tl.resource_type,
                    tl.resource_associated_entity_id
                FROM sys.dm_tran_locks AS tl
                WHERE tl.request_session_id = @protected_session_id
                AND   tl.request_status = N'WAIT'
                ORDER BY
                    CASE tl.resource_type
                        WHEN N'OBJECT' THEN 1
                        WHEN N'HOBT' THEN 2
                        WHEN N'KEY' THEN 3
                        WHEN N'RID' THEN 4
                        WHEN N'PAGE' THEN 5
                        ELSE 6
                    END
            ) AS wt
            OPTION (RECOMPILE, MAXDOP 1, MAXRECURSION 32);

            IF @debug = 1
            AND EXISTS
            (
                SELECT
                    1/0
                FROM #blockers AS b
            )
            BEGIN
                SELECT
                    cycle_time = SYSDATETIME(),
                    b.blocker_session_id,
                    b.wait_type,
                    b.wait_milliseconds,
                    b.blocker_command,
                    b.blocker_status,
                    b.is_modification,
                    b.chain_depth,
                    b.lead_blocker_session_id,
                    b.contended_db_name,
                    b.contended_resource_type,
                    b.contended_object_name,
                    b.statement_text
                FROM #blockers AS b
                ORDER BY
                    b.wait_milliseconds DESC;
            END;

            SET @blocker_kill_cursor =
                    CURSOR
                    LOCAL
                    FAST_FORWARD
                    READ_ONLY
                FOR
                    SELECT
                        b.blocker_session_id,
                        b.wait_milliseconds,
                        b.blocker_command,
                        b.blocker_login_time,
                        b.chain_depth,
                        b.lead_blocker_session_id,
                        b.contended_db_name,
                        b.contended_resource_type,
                        b.contended_object_name
                    FROM #blockers AS b
                    WHERE b.wait_milliseconds >= @threshold_ms
                    AND   ISNULL(b.blocker_status, N'') <> N'rollback'
                    AND   (b.is_modification = 0 OR @kill_modification_blockers = 1);

            OPEN @blocker_kill_cursor;

            FETCH NEXT
            FROM @blocker_kill_cursor
            INTO
                @blocker_session_id,
                @blocker_wait_ms,
                @blocker_command,
                @blocker_login_time,
                @blocker_chain_depth,
                @blocker_lead_session_id,
                @blocker_contended_db,
                @blocker_contended_type,
                @blocker_contended_object;

            WHILE @@FETCH_STATUS = 0
            BEGIN
                /*
                Fingerprint check: confirm the spid still belongs to the same
                session we snapshotted (same login_time). SQL Server can recycle
                a freed spid to a new connection within microseconds, so without
                this we risk killing an unrelated session that has inherited the
                recycled spid between the #blockers snapshot and this KILL.
                */
                IF EXISTS
                (
                    SELECT
                        1/0
                    FROM sys.dm_exec_sessions AS s
                    WHERE s.session_id = @blocker_session_id
                    AND   s.login_time = @blocker_login_time
                )
                BEGIN
                    SET @msg =
                        N'ProtectSession: killing session ' +
                        CONVERT(nvarchar(10), @blocker_session_id) +
                        N' (' +
                        ISNULL(@blocker_command, N'idle/sleeping') +
                        N' blocker of session ' +
                        CONVERT(nvarchar(10), @protected_session_id) +
                        N'; protected session has been waiting ' +
                        CONVERT(nvarchar(10), @blocker_wait_ms) +
                        N' ms on ' +
                        ISNULL(@blocker_contended_type, N'unknown resource') +
                        CASE
                            WHEN @blocker_contended_db IS NOT NULL
                            THEN N' in ' + QUOTENAME(@blocker_contended_db)
                            ELSE N''
                        END +
                        CASE
                            WHEN @blocker_contended_object IS NOT NULL
                            THEN N'.' + QUOTENAME(@blocker_contended_object)
                            ELSE N''
                        END +
                        CASE
                            WHEN @blocker_chain_depth > 0
                            THEN N'; immediate blocker in a chain of depth ' +
                                 CONVERT(nvarchar(10), @blocker_chain_depth) +
                                 N', lead blocker is session ' +
                                 CONVERT(nvarchar(10), @blocker_lead_session_id)
                            ELSE N''
                        END +
                        N').';

                    RAISERROR(@msg, 10, 1) WITH NOWAIT;

                    SET @kill_sql = N'KILL ' + CONVERT(nvarchar(10), @blocker_session_id) + N';';

                    BEGIN TRY
                        EXECUTE sys.sp_executesql
                            @kill_sql;
                    END TRY
                    BEGIN CATCH
                        SET @msg =
                            N'ProtectSession: KILL of session ' +
                            CONVERT(nvarchar(10), @blocker_session_id) +
                            N' failed: ' +
                            ERROR_MESSAGE();

                        RAISERROR(@msg, 10, 1) WITH NOWAIT;
                    END CATCH;
                END;
                ELSE
                BEGIN
                    SET @msg =
                        N'ProtectSession: skipping KILL of session ' +
                        CONVERT(nvarchar(10), @blocker_session_id) +
                        N' -- login_time changed since snapshot (spid recycled or session ended).';

                    RAISERROR(@msg, 10, 1) WITH NOWAIT;
                END;

                FETCH NEXT
                FROM @blocker_kill_cursor
                INTO
                    @blocker_session_id,
                    @blocker_wait_ms,
                    @blocker_command,
                    @blocker_login_time,
                    @blocker_chain_depth,
                    @blocker_lead_session_id,
                    @blocker_contended_db,
                    @blocker_contended_type,
                    @blocker_contended_object;
            END;

            IF @abort_on_modification_block = 1
            AND @kill_modification_blockers = 0
            AND EXISTS
            (
                SELECT
                    1/0
                FROM #blockers AS b
                WHERE b.is_modification = 1
                AND   b.wait_milliseconds >= @threshold_ms
            )
            BEGIN
                SELECT TOP (1)
                    @blocker_wait_ms = b.wait_milliseconds,
                    @blocker_contended_db = b.contended_db_name,
                    @blocker_contended_type = b.contended_resource_type,
                    @blocker_contended_object = b.contended_object_name
                FROM #blockers AS b
                WHERE b.is_modification = 1
                AND   b.wait_milliseconds >= @threshold_ms
                ORDER BY
                    b.wait_milliseconds DESC;

                /*
                Same fingerprint check for the protected session before we KILL
                it: a race between the outer WHILE EXISTS and here could leave us
                killing a recycled spid. The outer loop already includes login_time
                in its check, but defense-in-depth is cheap here.
                */
                IF EXISTS
                (
                    SELECT
                        1/0
                    FROM sys.dm_exec_sessions AS s
                    WHERE s.session_id = @protected_session_id
                    AND   s.login_time = @protected_login_time
                )
                BEGIN
                    SET @msg =
                        N'ProtectSession: aborting protected session ' +
                        CONVERT(nvarchar(10), @protected_session_id) +
                        N' after ' +
                        CONVERT(nvarchar(10), @blocker_wait_ms) +
                        N' ms of LCK wait on a modification blocker (' +
                        ISNULL(@blocker_contended_type, N'unknown resource') +
                        CASE
                            WHEN @blocker_contended_db IS NOT NULL
                            THEN N' in ' + QUOTENAME(@blocker_contended_db)
                            ELSE N''
                        END +
                        CASE
                            WHEN @blocker_contended_object IS NOT NULL
                            THEN N'.' + QUOTENAME(@blocker_contended_object)
                            ELSE N''
                        END +
                        N'). Reason: ' +
                        ISNULL(@abort_reason, N'blocked by a modification query past @block_threshold_seconds.');

                    RAISERROR(@msg, 10, 1) WITH NOWAIT;

                    SET @kill_sql = N'KILL ' + CONVERT(nvarchar(10), @protected_session_id) + N';';

                    BEGIN TRY
                        EXECUTE sys.sp_executesql
                            @kill_sql;
                    END TRY
                    BEGIN CATCH
                        SET @msg =
                            N'ProtectSession: KILL of protected session ' +
                            CONVERT(nvarchar(10), @protected_session_id) +
                            N' failed: ' +
                            ERROR_MESSAGE();

                        RAISERROR(@msg, 10, 1) WITH NOWAIT;
                    END CATCH;
                END;
                ELSE
                BEGIN
                    SET @msg =
                        N'ProtectSession: skipping abort of protected session ' +
                        CONVERT(nvarchar(10), @protected_session_id) +
                        N' -- login_time changed since proc start (session already ended).';

                    RAISERROR(@msg, 10, 1) WITH NOWAIT;
                END;

                RETURN;
            END;

            WAITFOR DELAY @sleep_for;
        END;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
        BEGIN
            ROLLBACK;
        END;

        THROW;
    END CATCH;
END;
GO
