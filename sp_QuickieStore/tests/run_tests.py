"""
sp_QuickieStore assertion test harness
======================================
sp_QuickieStore is ~20,000 lines that assemble a large dynamic SQL statement
whose SHAPE changes with almost every one of its 60 parameters: @sort_order
alone accepts 35+ values, each producing a different ORDER BY and column set,
and @wait_filter / @execution_type_desc / @query_type / @expert_mode /
@format_output each rewrite the statement again.

That is where this procedure's bugs live. A parameter combination nobody has
run assembles SQL that is malformed or references a column that is not in that
shape, and it fails only at EXECUTION -- compiling the procedure proves nothing,
because the statement that breaks is built at runtime from string fragments.

So the core of this harness is a parameter matrix: run the procedure across
every @sort_order, every @wait_filter, every @execution_type_desc and
@query_type, in both @expert_mode and @format_output states, and assert each
run executes cleanly and reaches completion. Every run executes the dynamic SQL
it just built, which is the only way to catch this class of defect.

On top of that, a few BIDIRECTIONAL filter assertions (finding present when the
filter should match, absent when it should not) prove the filters actually
filter rather than being silently ignored.

Fixture: the harness builds its own scratch database with Query Store enabled,
runs a small varied workload (ad hoc queries at different costs plus a stored
procedure, so @query_type has both kinds to separate), flushes Query Store, and
drops the database at the end. Nothing outside that database is touched.

Usage:
    python run_tests.py [--server SQL2022] [--password L!nt0044]

Exits 1 if any assertion fails.
"""

import argparse
import calendar
import math
import os
import re
import shlex
import subprocess
import sys
import time

TEST_DB = "quickiestore_test"

# The footer result set the procedure always emits last. Its presence proves the
# run reached completion rather than dying midway, and is the positive control
# for every "no rows" / absence assertion.
DONE_MARKER = "brought to you by darling data!"

# Every @sort_order the procedure documents. Each one builds a different
# ORDER BY (and for the wait sorts, joins query_store_wait_stats), so this is
# the highest-value axis in the matrix.
SORT_ORDERS = [
    "cpu", "logical reads", "physical reads", "writes", "duration", "memory",
    "tempdb", "executions", "recent", "plan count by hashes",
    "cpu waits", "lock waits", "locks waits", "latch waits", "latches waits",
    "buffer latch waits", "buffer latches waits", "buffer io waits",
    "log waits", "log io waits", "network waits", "network io waits",
    "parallel waits", "parallelism waits", "memory waits", "total waits",
    "rows",
    "total cpu", "total logical reads", "total physical reads", "total writes",
    "total duration", "total memory", "total tempdb", "total rows",
    # the avg/average prefixes the help text says are also accepted
    "avg cpu", "average duration", "avg tempdb",
]

WAIT_FILTERS = [
    "cpu", "lock", "latch", "buffer latch", "buffer io", "log io",
    "network io", "parallelism", "memory",
]

EXECUTION_TYPES = ["regular", "aborted", "exception", "failed"]

QUERY_TYPES = ["ad hoc", "adhoc", "proc", "procedure"]


def _sqlcmd_prefix():
    """The sqlcmd binary plus any connection args, overridable via environment
    so one harness runs both locally and in CI. Locally SQLCMD_BIN defaults to
    'sqlcmd' on PATH and SQLCMD_CONN_ARGS is empty; CI sets SQLCMD_BIN to the
    go-based sqlcmd and SQLCMD_CONN_ARGS to '-C -N disable' -- trust the
    container's self-signed cert and disable encryption, which the modern Go
    TLS stack needs to connect to the SQL Server 2017 container."""
    return [os.environ.get("SQLCMD_BIN", "sqlcmd")] + shlex.split(
        os.environ.get("SQLCMD_CONN_ARGS", ""))


def _sqlcmd(server, password, sql, database="master", timeout=300, width=200):
    """Run a batch and return (stdout, stderr) decoded as UTF-8.

    -y 200 truncates variable-length columns in the OUTPUT, which keeps the
    captured text small: the main result set carries query_plan as full
    ShowPlanXML and we only ever need enough of a column to detect errors and
    count rows, never the whole plan.
    """
    cmd = _sqlcmd_prefix() + [
        "-S", server, "-U", "sa", "-P", password,
        "-d", database,
        "-W",            # trim trailing spaces
        "-w", "65535",   # do not wrap wide rows
        "-y", str(width),  # truncate wide columns (plan XML) so rendering is fast
        "-s", "\t",      # tab delimiter
        "-Q", sql,
    ]
    r = subprocess.run(cmd, capture_output=True, timeout=timeout)
    return ((r.stdout or b"").decode("utf-8", errors="replace"),
            (r.stderr or b"").decode("utf-8", errors="replace"))


def _esc(s):
    """Escape a T-SQL single-quoted literal."""
    return s.replace("'", "''")


def find_sql_errors(text):
    """Severity 16+ errors from either stream. go-sqlcmd reports SQL errors on
    stdout, so both have to be checked. Msg 4060/911 ("Cannot open database")
    are only Level 11 but mean the batch never ran, so catch those too."""
    if not text:
        return []
    pattern = r"Msg (?:\d+, Level 1[6-9]|4060|911)[^\n]*"
    return re.findall(pattern, text)


def run_qs(server, password, extra="", timeout=300, database_name=TEST_DB,
           width=200):
    """Run sp_QuickieStore against the scratch database, always naming it
    explicitly, and return (stdout, combined-for-error-scanning)."""
    sql = ("SET NOCOUNT ON; EXECUTE dbo.sp_QuickieStore "
           "@database_name = '%s'%s;" % (_esc(database_name), extra))
    out, err = _sqlcmd(server, password, sql, timeout=timeout, width=width)
    return out, out + "\n" + err


def completed(stdout):
    """True if the procedure reached its final footer result set."""
    return DONE_MARKER in stdout


def result_rows(stdout):
    """Count of main result-set rows (each begins with the source column)."""
    return sum(1 for line in stdout.splitlines()
               if line.startswith("runtime_stats") or line.startswith("plan_forcing"))


class Results:
    def __init__(self):
        self.items = []

    def check(self, group, name, condition, detail=""):
        self.items.append({"group": group, "name": name,
                           "passed": bool(condition), "detail": detail})

    @property
    def passed(self):
        return sum(1 for r in self.items if r["passed"])

    @property
    def failed(self):
        return sum(1 for r in self.items if not r["passed"])


FIXTURE_SQL = """
SET NOCOUNT ON;
IF DB_ID(N'{db}') IS NOT NULL
BEGIN
    ALTER DATABASE {db} SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE {db};
END;
CREATE DATABASE {db};
ALTER DATABASE {db} SET QUERY_STORE = ON
    (OPERATION_MODE = READ_WRITE, DATA_FLUSH_INTERVAL_SECONDS = 60,
     INTERVAL_LENGTH_MINUTES = 1, QUERY_CAPTURE_MODE = ALL);
""".format(db=TEST_DB)

# Second batch: runs inside the scratch database. Kept separate because it needs
# the database to exist and to be the connection context.
WORKLOAD_SQL = """
SET NOCOUNT ON;
CREATE TABLE dbo.t
(
    id integer NOT NULL IDENTITY PRIMARY KEY,
    a integer NOT NULL,
    b varchar(100) NOT NULL
);

INSERT dbo.t WITH (TABLOCK) (a, b)
SELECT TOP (50000) ac1.column_id, REPLICATE('x', 50)
FROM sys.all_columns AS ac1 CROSS JOIN sys.all_columns AS ac2;

EXECUTE (N'CREATE PROCEDURE dbo.qs_test_proc AS BEGIN SELECT c = COUNT_BIG(*) FROM dbo.t WHERE a % 7 = 0; END;');

DECLARE @i integer = 0, @c bigint;
WHILE @i < 12
BEGIN
    SELECT @c = COUNT_BIG(*) FROM dbo.t WHERE a > 5;
    SELECT @c = SUM(CONVERT(bigint, a)) FROM dbo.t WHERE b LIKE 'x%';
    SELECT @c = COUNT_BIG(*) FROM dbo.t AS t1 JOIN dbo.t AS t2 ON t2.a = t1.a WHERE t1.id < 400;
    EXECUTE dbo.qs_test_proc;
    SET @i += 1;
END;

-- Parameter sensitivity fixture for @find_parameter_sensitive: a skewed table
-- (group 1 has 100k rows, groups 2-501 have one each) and a procedure compiled
-- on a tiny group so the seek + lookup plan gets reused for the giant group.
-- One plan shape, four orders of magnitude of cpu swing, flat-ish row counts.
CREATE TABLE dbo.skew
(
    id integer NOT NULL IDENTITY PRIMARY KEY,
    grp integer NOT NULL,
    pad char(200) NOT NULL
);

INSERT dbo.skew WITH (TABLOCK) (grp, pad)
SELECT TOP (100000) 1, REPLICATE('x', 200)
FROM sys.all_columns AS ac1 CROSS JOIN sys.all_columns AS ac2;

INSERT dbo.skew (grp, pad)
SELECT TOP (500) 1 + ROW_NUMBER() OVER (ORDER BY ac1.object_id), REPLICATE('y', 200)
FROM sys.all_columns AS ac1;

CREATE INDEX ix_grp ON dbo.skew (grp);

EXECUTE (N'CREATE PROCEDURE dbo.qs_sniff_proc (@grp integer) AS BEGIN SET NOCOUNT ON; DECLARE @c bigint, @p char(200); SELECT @c = COUNT_BIG(*) FROM dbo.skew AS s WHERE s.grp = @grp; SELECT TOP (10) @p = s2.pad FROM dbo.skew AS s2 WHERE s2.grp = @grp ORDER BY s2.pad; END;');

DECLARE @g integer = 0;
WHILE @g < 6
BEGIN
    EXECUTE dbo.qs_sniff_proc @grp = 5;
    SET @g += 1;
END;
EXECUTE dbo.qs_sniff_proc @grp = 1;
EXECUTE dbo.qs_sniff_proc @grp = 1;
EXECUTE dbo.qs_sniff_proc @grp = 1;
EXECUTE dbo.qs_sniff_proc @grp = 301;
EXECUTE dbo.qs_sniff_proc @grp = 302;
EXECUTE dbo.qs_sniff_proc @grp = 303;

EXECUTE sys.sp_query_store_flush_db;
"""

CLEANUP_SQL = """
SET NOCOUNT ON;
IF DB_ID(N'{db}') IS NOT NULL
BEGIN
    ALTER DATABASE {db} SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE {db};
END;
""".format(db=TEST_DB)

# Text searches run under a binary collation. query_sql_text is
# SQL_Latin1_General_CP1_CI_AS in every database, so a search has to ignore
# case even when the database collation does not. The main scratch database
# takes the server collation, which is case insensitive on every test server,
# so it can't show that. This second database is case sensitive and holds one
# mixed-case marker query.
CS_DB = TEST_DB + "_cs"

CS_FIXTURE_SQL = """
SET NOCOUNT ON;
IF DB_ID(N'{db}') IS NOT NULL
BEGIN
    ALTER DATABASE {db} SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE {db};
END;
CREATE DATABASE {db} COLLATE Latin1_General_100_CS_AS;
ALTER DATABASE {db} SET QUERY_STORE = ON
    (OPERATION_MODE = READ_WRITE, QUERY_CAPTURE_MODE = ALL);
""".format(db=CS_DB)

# Query Store starts asynchronously, and compiles that happen before it is
# READ_WRITE are lost, so wait for the state, then execute and flush in a
# retry loop until the marker query shows up (same as the ReproBuilder suite).
CS_WORKLOAD_SQL = """
SET NOCOUNT ON;
DECLARE @tries integer = 0, @rows bigint = 0;
WHILE @tries < 30
AND   NOT EXISTS (SELECT 1/0 FROM sys.database_query_store_options AS dqso
                  WHERE dqso.actual_state_desc = N'READ_WRITE')
BEGIN
    WAITFOR DELAY '00:00:01';
    SET @tries += 1;
END;
CREATE TABLE dbo.t (id integer NOT NULL);
EXECUTE (N'CREATE PROCEDURE dbo.qs_case_proc AS BEGIN SELECT /*qs_Case_Marker*/ c = COUNT_BIG(*) FROM dbo.t AS t; END;');
SET @tries = 0;
WHILE @tries < 10 AND @rows = 0
BEGIN
    EXECUTE dbo.qs_case_proc;
    EXECUTE dbo.qs_case_proc;
    EXECUTE sys.sp_query_store_flush_db;
    SELECT @rows = COUNT_BIG(*) FROM sys.query_store_query_text AS qsqt
    WHERE qsqt.query_sql_text LIKE N'%qs[_]Case[_]Marker%';
    IF @rows = 0 WAITFOR DELAY '00:00:01';
    SET @tries += 1;
END;
SELECT marker = 'CS_ROWS:' + CONVERT(varchar(20), @rows);
"""

CS_CLEANUP_SQL = """
SET NOCOUNT ON;
IF DB_ID(N'{db}') IS NOT NULL
BEGIN
    ALTER DATABASE {db} SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE {db};
END;
""".format(db=CS_DB)


def build_fixture(server, password, R):
    out, err = _sqlcmd(server, password, FIXTURE_SQL)
    errs = find_sql_errors(out + "\n" + err)
    R.check("Fixture", "scratch database created with Query Store on",
            not errs, str(errs))
    if errs:
        return False

    out, err = _sqlcmd(server, password, WORKLOAD_SQL, database=TEST_DB,
                       timeout=600)
    errs = find_sql_errors(out + "\n" + err)
    R.check("Fixture", "workload ran and Query Store flushed", not errs, str(errs))
    if errs:
        return False

    out, _ = _sqlcmd(server, password,
                     "SET NOCOUNT ON; SELECT COUNT_BIG(*) FROM sys.query_store_query;",
                     database=TEST_DB)
    captured = any(line.strip().isdigit() and int(line.strip()) > 0
                   for line in out.splitlines())
    R.check("Fixture", "Query Store captured queries to analyze",
            captured, "no queries captured; the matrix would pass vacuously")
    return captured


def smoke_tests(server, password, R):
    out, combined = run_qs(server, password)
    R.check("Smoke", "default run: no severe SQL error",
            not find_sql_errors(combined), str(find_sql_errors(combined)))
    R.check("Smoke", "default run: reached completion",
            completed(out), "footer result set missing")
    R.check("Smoke", "default run: returned query rows",
            result_rows(out) > 0, "no result rows from a populated Query Store")

    out, combined = run_qs(server, password, ", @help = 1")
    R.check("Smoke", "@help = 1: no severe SQL error",
            not find_sql_errors(combined), str(find_sql_errors(combined)))

    # @debug is exercised against a database with no Query Store data on
    # purpose. With data, debug mode returns the generated SQL as an XML column
    # (so it is clickable in SSMS), and go-sqlcmd renders XML columns so slowly
    # that capturing the output takes minutes and looks like a hang -- the
    # server parks in ASYNC_NETWORK_IO waiting for the client to drain it. SSMS
    # handles it fine; this is a client limitation, not a procedure defect, so
    # we exercise the debug code path where it is capturable rather than skip it.
    sql = "SET NOCOUNT ON; EXECUTE dbo.sp_QuickieStore @database_name = 'master', @debug = 1;"
    out, err = _sqlcmd(server, password, sql)
    R.check("Smoke", "@debug = 1: no severe SQL error",
            not find_sql_errors(out + "\n" + err),
            str(find_sql_errors(out + "\n" + err)))


def sort_order_matrix(server, password, R):
    """Every @sort_order, each of which builds a different ORDER BY. This is the
    highest-value axis: a bad sort order yields SQL that only fails at run time."""
    for so in SORT_ORDERS:
        out, combined = run_qs(server, password,
                               ", @sort_order = '%s'" % _esc(so))
        errs = find_sql_errors(combined)
        R.check("SortOrder", "@sort_order = '%s' executes cleanly" % so,
                not errs, str(errs[:2]))
        R.check("SortOrder", "@sort_order = '%s' reaches completion" % so,
                completed(out), "footer missing")


def mode_matrix(server, password, R):
    """@expert_mode and @format_output each rewrite the column list."""
    for expert in (0, 1):
        for fmt in (0, 1):
            extra = ", @expert_mode = %d, @format_output = %d" % (expert, fmt)
            out, combined = run_qs(server, password, extra)
            errs = find_sql_errors(combined)
            label = "expert_mode=%d format_output=%d" % (expert, fmt)
            R.check("Modes", "%s executes cleanly" % label, not errs, str(errs[:2]))
            R.check("Modes", "%s reaches completion" % label,
                    completed(out), "footer missing")

    # A sort order combined with expert mode changes both ORDER BY and columns.
    for so in ("cpu", "duration", "total waits", "plan count by hashes"):
        out, combined = run_qs(server, password,
                               ", @sort_order = '%s', @expert_mode = 1" % _esc(so))
        errs = find_sql_errors(combined)
        R.check("Modes", "@sort_order = '%s' + expert_mode executes cleanly" % so,
                not errs, str(errs[:2]))


def filter_matrix(server, password, R):
    """@wait_filter, @execution_type_desc and @query_type each add joins and
    predicates that reshape the statement."""
    for wf in WAIT_FILTERS:
        out, combined = run_qs(server, password,
                               ", @wait_filter = '%s'" % _esc(wf))
        errs = find_sql_errors(combined)
        R.check("WaitFilter", "@wait_filter = '%s' executes cleanly" % wf,
                not errs, str(errs[:2]))
        R.check("WaitFilter", "@wait_filter = '%s' reaches completion" % wf,
                completed(out), "footer missing")

    for et in EXECUTION_TYPES:
        out, combined = run_qs(server, password,
                               ", @execution_type_desc = '%s'" % _esc(et))
        errs = find_sql_errors(combined)
        R.check("ExecType", "@execution_type_desc = '%s' executes cleanly" % et,
                not errs, str(errs[:2]))

    for qt in QUERY_TYPES:
        out, combined = run_qs(server, password,
                               ", @query_type = '%s'" % _esc(qt))
        errs = find_sql_errors(combined)
        R.check("QueryType", "@query_type = '%s' executes cleanly" % qt,
                not errs, str(errs[:2]))


def bidirectional_tests(server, password, R):
    """Prove the filters actually filter, rather than being silently ignored.
    Each presence assertion is paired with an absence assertion on the same
    filter, and every absence run is checked for completion so an errored or
    empty run cannot pass vacuously."""
    # ---- @query_text_search --------------------------------------------
    out, combined = run_qs(server, password,
                           ", @query_text_search = 'qs_test_proc'")
    R.check("Search", "@query_text_search on a known string: no severe error",
            not find_sql_errors(combined), str(find_sql_errors(combined)))
    R.check("Search", "@query_text_search on a known string: reaches completion",
            completed(out), "footer missing")

    out2, combined2 = run_qs(server, password,
                             ", @query_text_search = 'zzz_no_such_text_zzz'")
    R.check("Search", "@query_text_search on nonsense: reaches completion "
            "(positive control for the absence below)",
            completed(out2), "footer missing")
    R.check("Search", "@query_text_search on nonsense returns no query rows",
            result_rows(out2) == 0,
            "expected zero rows, got %d" % result_rows(out2))

    # ---- @query_type separates the proc from the ad hoc queries --------
    out, combined = run_qs(server, password, ", @query_type = 'proc'")
    proc_rows = result_rows(out)
    R.check("Search", "@query_type = 'proc': reaches completion",
            completed(out), "footer missing")

    out, combined = run_qs(server, password, ", @query_type = 'ad hoc'")
    adhoc_rows = result_rows(out)
    R.check("Search", "@query_type = 'ad hoc': reaches completion",
            completed(out), "footer missing")
    R.check("Search", "@query_type actually partitions proc vs ad hoc",
            proc_rows > 0 and adhoc_rows > 0 and proc_rows != adhoc_rows,
            "proc=%d adhoc=%d (expected both non-zero and different)"
            % (proc_rows, adhoc_rows))

    # ---- @top bounds the result set ------------------------------------
    out, combined = run_qs(server, password, ", @top = 1")
    R.check("Top", "@top = 1: no severe error",
            not find_sql_errors(combined), str(find_sql_errors(combined)))
    R.check("Top", "@top = 1 returns at most one query row",
            result_rows(out) <= 1, "got %d rows" % result_rows(out))

    # ---- @execution_count filters out everything when set impossibly high
    out, combined = run_qs(server, password, ", @execution_count = 1000000")
    R.check("ExecCount", "@execution_count impossibly high: reaches completion",
            completed(out), "footer missing")
    R.check("ExecCount", "@execution_count impossibly high returns no rows",
            result_rows(out) == 0, "got %d rows" % result_rows(out))


def case_sensitive_search_tests(server, password, R):
    """Text searches ignore case in a case-sensitive database. The marker is
    qs_Case_Marker; a search in any other case has to find it, and an
    exclusion in any other case has to remove it."""
    try:
        out, err = _sqlcmd(server, password, CS_FIXTURE_SQL)
        errs = find_sql_errors(out + "\n" + err)
        R.check("CaseSearch", "case-sensitive scratch database created",
                not errs, str(errs))
        if errs:
            return

        out, err = _sqlcmd(server, password, CS_WORKLOAD_SQL, database=CS_DB,
                           timeout=600)
        m = re.search(r"CS_ROWS:(\d+)", out)
        captured = bool(m) and int(m.group(1)) > 0
        R.check("CaseSearch", "Query Store captured the mixed-case marker query",
                captured and not find_sql_errors(out + "\n" + err),
                "marker=%s errors=%s" % (m.group(1) if m else "absent",
                                         find_sql_errors(out + "\n" + err)))
        if not captured:
            return

        for search in ("qs_case_marker", "QS_CASE_MARKER"):
            out, combined = run_qs(server, password,
                                   ", @query_text_search = '%s'" % search,
                                   database_name=CS_DB)
            R.check("CaseSearch",
                    "@query_text_search = '%s' finds qs_Case_Marker" % search,
                    completed(out) and result_rows(out) > 0,
                    "completed=%s rows=%d errors=%s"
                    % (completed(out), result_rows(out),
                       find_sql_errors(combined)))

        # The search matches in exact case, so it finds the marker even where
        # a search is case sensitive; only the exclusion's case differs.
        out, combined = run_qs(server, password,
                               ", @query_text_search = 'qs_Case_Marker'"
                               ", @query_text_search_not = 'QS_CASE_MARKER'",
                               database_name=CS_DB)
        R.check("CaseSearch",
                "@query_text_search_not = 'QS_CASE_MARKER' removes qs_Case_Marker",
                completed(out) and result_rows(out) == 0,
                "completed=%s rows=%d errors=%s"
                % (completed(out), result_rows(out), find_sql_errors(combined)))

        # With @escape_brackets = 1 the underscore in the marker is escaped, so
        # it is a literal underscore and not a one-character wildcard. That
        # has to hold for every escape character, including the three that
        # are themselves special in a LIKE pattern: _ [ ].
        for esc in ("\\", "_", "[", "]"):
            extra = ", @escape_brackets = 1, @escape_character = '%s'" % esc
            out, combined = run_qs(server, password,
                                   ", @query_text_search = 'qs_case_marker'" + extra,
                                   database_name=CS_DB)
            R.check("Escape",
                    "@escape_character = '%s': a_b finds qs_Case_Marker" % esc,
                    completed(out) and result_rows(out) > 0,
                    "completed=%s rows=%d errors=%s"
                    % (completed(out), result_rows(out), find_sql_errors(combined)))

            out, combined = run_qs(server, password,
                                   ", @query_text_search = 'qsXcase_marker'" + extra,
                                   database_name=CS_DB)
            R.check("Escape",
                    "@escape_character = '%s': the underscore is not a wildcard" % esc,
                    completed(out) and result_rows(out) == 0,
                    "completed=%s rows=%d errors=%s"
                    % (completed(out), result_rows(out), find_sql_errors(combined)))
    finally:
        _sqlcmd(server, password, CS_CLEANUP_SQL)


MD_DBS = ("quickiestore_test_md1", "quickiestore_test_md2")

MD_SETUP_SQL = """
SET NOCOUNT ON;
IF DB_ID(N'{db}') IS NOT NULL
BEGIN
    ALTER DATABASE {db} SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE {db};
END;
CREATE DATABASE {db};
ALTER DATABASE {db} SET QUERY_STORE = ON
    (OPERATION_MODE = READ_WRITE, QUERY_CAPTURE_MODE = ALL);
"""

# Both databases run the same statements in the same order, so their
# query_id, query_text_id and plan_id values collide.
MD_TABLE_SQL = """
SET NOCOUNT ON;
DECLARE @tries integer = 0;
WHILE @tries < 30
AND   NOT EXISTS (SELECT 1/0 FROM sys.database_query_store_options AS dqso
                  WHERE dqso.actual_state_desc = N'READ_WRITE')
BEGIN
    WAITFOR DELAY '00:00:01';
    SET @tries += 1;
END;
CREATE TABLE dbo.t (id integer NOT NULL);
INSERT dbo.t (id) VALUES (1), (2), (3);
"""

# The self joins keep simple parameterization from folding the four markers
# into one parameterized query, which drops the comments and merges the
# literals. Each marker sits before the select list because Query Store keeps
# only the statement text, so a trailing comment is lost. Query Store can
# report READ_WRITE a moment before it captures anything, and a plan compiled
# in that gap is never captured and is then reused from cache, so every
# attempt clears this database's plan cache first.
MD_QUERIES_SQL = """
SET NOCOUNT ON;
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
SELECT /*md_q1*/ c = COUNT_BIG(*) FROM dbo.t AS t JOIN dbo.t AS u ON u.id = t.id WHERE t.id > 0;
SELECT /*md_q2*/ c = COUNT_BIG(*) FROM dbo.t AS t JOIN dbo.t AS u ON u.id = t.id WHERE t.id > 1;
SELECT /*md_q3*/ c = COUNT_BIG(*) FROM dbo.t AS t JOIN dbo.t AS u ON u.id = t.id WHERE t.id > 2;
SELECT /*md_q4*/ c = COUNT_BIG(*) FROM dbo.t AS t JOIN dbo.t AS u ON u.id = t.id WHERE t.id = 1;
EXECUTE sys.sp_query_store_flush_db;
"""

# One row per marker that has a query and runtime stats. The [_] keeps this
# probe's own text from matching its own patterns.
MD_PROBE_SQL = """
SET NOCOUNT ON;
SELECT DISTINCT
    marker = m.marker
FROM (VALUES (N'md_q1'), (N'md_q2'), (N'md_q3'), (N'md_q4')) AS m (marker)
JOIN sys.query_store_query_text AS qsqt
  ON qsqt.query_sql_text LIKE N'%/*' + REPLACE(m.marker, N'_', N'[_]') + N'*/%'
JOIN sys.query_store_query AS qsq
  ON qsq.query_text_id = qsqt.query_text_id
JOIN sys.query_store_plan AS qsp
  ON qsp.query_id = qsq.query_id
JOIN sys.query_store_runtime_stats AS qsrs
  ON qsrs.plan_id = qsp.plan_id;
"""

MD_MARKERS = ("md_q1", "md_q2", "md_q3", "md_q4")


def md_missing_markers(server, password, db):
    """Markers with no captured query and runtime stats in the database."""
    out, _ = _sqlcmd(server, password, MD_PROBE_SQL, database=db)
    found = {line.strip() for line in out.splitlines()}
    return [m for m in MD_MARKERS if m not in found]


def md_build_database(server, password, db):
    """Create one database, load it, and run the marker queries until every
    marker is captured. Returns (errors, missing markers)."""
    out, err = _sqlcmd(server, password, MD_SETUP_SQL.format(db=db))
    out2, err2 = _sqlcmd(server, password, MD_TABLE_SQL, database=db, timeout=600)
    errs = find_sql_errors(out + "\n" + err + "\n" + out2 + "\n" + err2)
    if errs:
        return errs, list(MD_MARKERS)
    missing = list(MD_MARKERS)
    for _ in range(5):
        out, err = _sqlcmd(server, password, MD_QUERIES_SQL, database=db,
                           timeout=600)
        errs = find_sql_errors(out + "\n" + err)
        if errs:
            return errs, missing
        missing = md_missing_markers(server, password, db)
        if not missing:
            break
        time.sleep(2)
    return [], missing


def multi_database_tests(server, password, R):
    """Two databases whose Query Store ids collide, read in one
    @get_all_databases run: expert mode has to return the compilation stats
    row of every query, not one per colliding id."""
    try:
        for db in MD_DBS:
            errs, missing = md_build_database(server, password, db)
            R.check("MultiDb", "%s created and loaded" % db, not errs, str(errs))
            if errs:
                return
            R.check("MultiDb", "%s captured every marker query" % db,
                    not missing, "missing from Query Store: %s" % ", ".join(missing))
            if missing:
                return

        out, err = _sqlcmd(
            server, password,
            "SET NOCOUNT ON; EXECUTE dbo.sp_QuickieStore @get_all_databases = 1, "
            "@include_databases = N'%s', @expert_mode = 1, @top = 50;"
            % ",".join(MD_DBS))
        combined = out + "\n" + err
        runtime = sum(1 for line in out.splitlines()
                      if line.startswith("runtime_stats"))
        compile_rows = sum(1 for line in out.splitlines()
                           if line.startswith("compilation_stats"))
        R.check("MultiDb", "@get_all_databases runs cleanly",
                completed(out) and not find_sql_errors(combined),
                str(find_sql_errors(combined)))
        R.check("MultiDb", "both databases return their queries",
                runtime >= 8, "runtime_stats rows=%d" % runtime)
        R.check("MultiDb",
                "expert mode returns one compilation_stats row per query "
                "when ids collide across databases",
                compile_rows == runtime,
                "runtime_stats=%d compilation_stats=%d" % (runtime, compile_rows))
    finally:
        for db in MD_DBS:
            _sqlcmd(server, password, CLEANUP_SQL.replace(TEST_DB, db))


def id_list_tests(server, password, R):
    """Id lists split on commas, spaces and line breaks, and may run past 4000
    characters once the splitter has expanded them."""
    out, err = _sqlcmd(server, password,
                       "SET NOCOUNT ON; SELECT TOP (2) 'PID:' + CONVERT(varchar(20), "
                       "qsrs.plan_id) FROM sys.query_store_runtime_stats AS qsrs "
                       "GROUP BY qsrs.plan_id ORDER BY qsrs.plan_id;",
                       database=TEST_DB)
    ids = re.findall(r"PID:(\d+)", out)
    R.check("IdList", "two real plan ids found", len(ids) == 2, out[:200])
    if len(ids) != 2:
        return

    def rows_for(list_expr):
        sql = ("SET NOCOUNT ON; DECLARE @ids nvarchar(4000) = %s; "
               "EXECUTE dbo.sp_QuickieStore @database_name = '%s', "
               "@include_plan_ids = @ids;" % (list_expr, TEST_DB))
        o, e = _sqlcmd(server, password, sql)
        return o, o + "\n" + e

    out, combined = rows_for("N'%s,%s'" % tuple(ids))
    baseline = result_rows(out)
    R.check("IdList", "comma separated plan ids return rows",
            completed(out) and baseline > 0,
            "rows=%d errors=%s" % (baseline, find_sql_errors(combined)))

    # CR and LF in a pasted list separate ids. Deleting them used to glue
    # the two ids into one number that matched nothing.
    for name, sep in (("CRLF", "CHAR(13) + CHAR(10)"), ("LF", "CHAR(10)"),
                      ("CR", "CHAR(13)")):
        out, combined = rows_for("N'%s' + %s + N'%s'" % (ids[0], sep, ids[1]))
        R.check("IdList", "plan ids separated by %s return the same rows" % name,
                completed(out) and result_rows(out) == baseline,
                "rows=%d expected=%d errors=%s"
                % (result_rows(out), baseline, find_sql_errors(combined)))

    # About 380 ids is 3,400 characters; the splitter adds six per comma, so
    # the expanded list passes 4,000 and used to fail with Msg 9400.
    filler = ",".join(str(900000 + i) for i in range(380))
    out, combined = rows_for("N'%s,%s,%s'" % (filler, ids[0], ids[1]))
    R.check("IdList", "a list of 380 plan ids is split without Msg 9400",
            completed(out) and not find_sql_errors(combined)
            and result_rows(out) == baseline,
            "rows=%d expected=%d errors=%s"
            % (result_rows(out), baseline, find_sql_errors(combined)))


PS_SUMMARY_MARKER = "multi_shape_query_hashes"

HI_SUMMARY_MARKER = "workload_profile"


def hash_totals_tests(server, password, R):
    """@include_query_hash_totals adds *_by_query_hash columns whose totals
    are scoped to the requested date window (they used to sum all of Query
    Store history, which sat next to window-scoped columns in the same row)."""
    out, combined = run_qs(server, password, ", @include_query_hash_totals = 1")
    errs = find_sql_errors(combined)
    R.check("HashTotals", "@include_query_hash_totals executes cleanly",
            not errs and completed(out), str(errs[:2]))
    R.check("HashTotals", "by_query_hash columns are in the output",
            "count_executions_by_query_hash" in out
            and "total_cpu_time_ms_by_query_hash" in out,
            "by_query_hash columns missing")

    # Window scoping: a window that predates the fixture workload returns no
    # rows at all, so the totals cannot be sourcing outside the window.
    out, combined = run_qs(server, password,
                           ", @include_query_hash_totals = 1, "
                           "@start_date = '2001-01-01', @end_date = '2001-01-02'")
    errs = find_sql_errors(combined)
    R.check("HashTotals",
            "empty window with hash totals completes cleanly",
            not errs, str(errs[:2]))
    R.check("HashTotals", "empty window returns no detail rows",
            ps_detail_rows(out) == 0, "got %d rows" % ps_detail_rows(out))


def hi_detail_rows(stdout):
    """Detail rows from @find_high_impact output: one per query_hash, each
    beginning with the analyzed database name."""
    return sum(1 for line in stdout.splitlines()
               if line.startswith(TEST_DB + "\t"))


def high_impact_tests(server, password, R):
    """@find_high_impact is the other takeover mode: a workload concentration
    summary plus one row per query_hash, top-N per resource dimension. These
    are its first assertions: clean execution, output shape (including the
    absolute total_* columns), the query-hash include/ignore lists filtering
    before the top-N picks, and the zero-value spills diagnostic staying
    quiet."""
    out, combined = run_qs(server, password, ", @find_high_impact = 1")
    errs = find_sql_errors(combined)
    R.check("HighImpact", "default run executes cleanly", not errs, str(errs[:2]))
    R.check("HighImpact", "default run returns the summary result set",
            HI_SUMMARY_MARKER in out, "summary header missing")
    R.check("HighImpact", "default run returns detail rows",
            hi_detail_rows(out) > 0, "no hashes surfaced from the workload")
    R.check("HighImpact", "absolute total columns are in the output",
            "total_cpu_ms" in out and "total_duration_ms" in out,
            "total_* columns missing")
    R.check("HighImpact", "spills diagnostic does not fire at 0.0 MB/exec",
            "(0.0 MB/exec)" not in out, "zero-value spills diagnostic fired")

    # Query-hash include/ignore: extract a surfaced hash (first 0x token in a
    # detail row is query_hash) and prove both directions on the hash VALUE.
    line = next((l for l in out.splitlines()
                 if l.startswith(TEST_DB + "\t") and "0x" in l), "")
    hashes = re.findall(r"0x[0-9A-Fa-f]{16}", line)
    R.check("HighImpact", "a surfaced hash is extractable",
            len(hashes) >= 1, "no hash token found in detail rows")
    if hashes:
        query_hash = hashes[0]
        out, combined = run_qs(server, password,
                               ", @find_high_impact = 1, "
                               "@ignore_query_hashes = '%s'" % query_hash)
        errs = find_sql_errors(combined)
        R.check("HighImpact", "@ignore_query_hashes executes cleanly",
                not errs and HI_SUMMARY_MARKER in out, str(errs[:2]))
        R.check("HighImpact", "@ignore_query_hashes removes the ignored hash",
                not any(query_hash in l for l in out.splitlines()
                        if l.startswith(TEST_DB + "\t")),
                "ignored query_hash still present in detail rows")
        out, combined = run_qs(server, password,
                               ", @find_high_impact = 1, "
                               "@include_query_hashes = '%s'" % query_hash)
        detail = [l for l in out.splitlines() if l.startswith(TEST_DB + "\t")]
        R.check("HighImpact", "@include_query_hashes keeps only the included hash",
                len(detail) >= 1 and all(query_hash in l for l in detail),
                "got %d detail rows, not all matching the included hash"
                % len(detail))
    out, combined = run_qs(server, password,
                           ", @find_high_impact = 1, "
                           "@include_query_hashes = '0xDEADBEEFDEADBEEF'")
    R.check("HighImpact",
            "@include_query_hashes nobody has: summary still returned "
            "(positive control for the absence below)",
            HI_SUMMARY_MARKER in out, "summary header missing")
    R.check("HighImpact", "@include_query_hashes nobody has returns no hashes",
            hi_detail_rows(out) == 0, "got %d rows" % hi_detail_rows(out))


def ps_detail_rows(stdout):
    """Detail rows from @find_parameter_sensitive output: one per plan shape,
    each beginning with the analyzed database name."""
    return sum(1 for line in stdout.splitlines()
               if line.startswith(TEST_DB + "\t"))


def parameter_sensitive_tests(server, password, R):
    """@find_parameter_sensitive is a takeover mode like @find_high_impact: it
    returns its own result sets (a summary plus one row per plan shape) and
    never reaches the footer, so completion is proven by the summary result
    set's header instead of DONE_MARKER. The fixture's qs_sniff_proc gives it
    a real conviction to make: one plan shape whose cpu swings four orders of
    magnitude while rows stay flat."""
    out, combined = run_qs(server, password, ", @find_parameter_sensitive = 1")
    errs = find_sql_errors(combined)
    R.check("ParamSensitive", "default run executes cleanly", not errs, str(errs[:2]))
    R.check("ParamSensitive", "default run returns the summary result set",
            PS_SUMMARY_MARKER in out, "summary header missing")
    R.check("ParamSensitive", "default run returns detail rows",
            ps_detail_rows(out) > 0, "no shapes surfaced from the skewed workload")
    R.check("ParamSensitive", "the sniffed procedure is surfaced",
            "qs_sniff_proc" in out, "qs_sniff_proc missing from output")
    R.check("ParamSensitive", "the parameter sensitive signal fires",
            "parameter sensitive (cpu" in out, "signals column missing the verdict")

    # Each of these picks a different volatility column to rank by; the wait
    # sort falls back to cpu. 'tempdb' additionally exercises the 2017+ branch.
    for so in ("duration", "memory", "rows", "tempdb", "physical reads",
               "cpu waits"):
        out, combined = run_qs(server, password,
                               ", @find_parameter_sensitive = 1, "
                               "@sort_order = '%s'" % _esc(so))
        errs = find_sql_errors(combined)
        R.check("ParamSensitive", "@sort_order = '%s' executes cleanly" % so,
                not errs and PS_SUMMARY_MARKER in out, str(errs[:2]))

    for expert in (0, 1):
        for fmt in (0, 1):
            extra = (", @find_parameter_sensitive = 1, @expert_mode = %d, "
                     "@format_output = %d" % (expert, fmt))
            out, combined = run_qs(server, password, extra)
            errs = find_sql_errors(combined)
            R.check("ParamSensitive",
                    "expert_mode=%d format_output=%d executes cleanly"
                    % (expert, fmt),
                    not errs and PS_SUMMARY_MARKER in out, str(errs[:2]))

    out, combined = run_qs(server, password,
                           ", @find_parameter_sensitive = 1, @top = 1")
    R.check("ParamSensitive", "@top = 1 returns exactly one shape",
            ps_detail_rows(out) == 1, "got %d rows" % ps_detail_rows(out))

    out, combined = run_qs(server, password,
                           ", @find_parameter_sensitive = 1, "
                           "@execution_count = 1000000")
    R.check("ParamSensitive",
            "@execution_count impossibly high: summary still returned "
            "(positive control for the absence below)",
            PS_SUMMARY_MARKER in out, "summary header missing")
    R.check("ParamSensitive", "@execution_count impossibly high returns no shapes",
            ps_detail_rows(out) == 0, "got %d rows" % ps_detail_rows(out))

    # The hash-based include/ignore lists are honored in this mode: shapes are
    # keyed by (query_hash, query_plan_hash), so the lists filter shapes
    # directly, before the top-N cut. Extract the sniffed shape's query_hash
    # from a default run's detail row (the first two 0x tokens in a detail row
    # are query_hash and query_plan_hash), then prove both directions on the
    # hash VALUE in detail rows -- object names can also appear in other
    # shapes' query text, hash values cannot.
    out, combined = run_qs(server, password, ", @find_parameter_sensitive = 1")
    sniff_line = next((line for line in out.splitlines()
                       if line.startswith(TEST_DB + "\t")
                       and "qs_sniff_proc" in line), "")
    hashes = re.findall(r"0x[0-9A-Fa-f]{16}", sniff_line)
    R.check("ParamSensitive", "sniffed shape's hashes are extractable",
            len(hashes) >= 2, "found %d hash tokens" % len(hashes))
    if len(hashes) >= 2:
        query_hash = hashes[0]
        out, combined = run_qs(server, password,
                               ", @find_parameter_sensitive = 1, "
                               "@ignore_query_hashes = '%s'" % query_hash)
        errs = find_sql_errors(combined)
        R.check("ParamSensitive", "@ignore_query_hashes executes cleanly",
                not errs and PS_SUMMARY_MARKER in out, str(errs[:2]))
        R.check("ParamSensitive",
                "@ignore_query_hashes removes the ignored shape",
                not any(query_hash in line for line in out.splitlines()
                        if line.startswith(TEST_DB + "\t")),
                "ignored query_hash still present in detail rows")
        out, combined = run_qs(server, password,
                               ", @find_parameter_sensitive = 1, "
                               "@include_query_hashes = '%s'" % query_hash)
        detail = [line for line in out.splitlines()
                  if line.startswith(TEST_DB + "\t")]
        R.check("ParamSensitive",
                "@include_query_hashes keeps only the included shape",
                len(detail) >= 1
                and all(query_hash in line for line in detail),
                "got %d detail rows, not all matching the included hash"
                % len(detail))
    out, combined = run_qs(server, password,
                           ", @find_parameter_sensitive = 1, "
                           "@include_query_hashes = '0xDEADBEEFDEADBEEF'")
    R.check("ParamSensitive",
            "@include_query_hashes nobody has: summary still returned "
            "(positive control for the absence below)",
            PS_SUMMARY_MARKER in out, "summary header missing")
    R.check("ParamSensitive",
            "@include_query_hashes nobody has returns no shapes",
            ps_detail_rows(out) == 0, "got %d rows" % ps_detail_rows(out))

    # Ranking is work-weighted volatility; the summary explains top_waits
    # availability; the internal sort_value column must not leak into output.
    out, combined = run_qs(server, password, ", @find_parameter_sensitive = 1")
    R.check("ParamSensitive", "ranked_on says the ranking is work-weighted",
            "volatility, work-weighted" in out, "work-weighted marker missing")
    R.check("ParamSensitive", "summary explains top_waits availability",
            "wait_stats" in out, "wait_stats summary column missing")
    R.check("ParamSensitive", "internal sort_value column does not leak",
            "sort_value" not in out, "sort_value column leaked into output")

    for extra, what in (
            (", @find_parameter_sensitive = 1, @find_high_impact = 1",
             "@find_high_impact"),
            (", @find_parameter_sensitive = 1, @get_all_databases = 1",
             "@get_all_databases"),
            (", @find_parameter_sensitive = 1, @log_to_table = 1",
             "@log_to_table")):
        out, combined = run_qs(server, password, extra)
        R.check("ParamSensitive", "conflict with %s raises the guard error" % what,
                "cannot be used with" in combined, "guard error missing")

    # DEBUG dumps: run against a scratch database with Query Store ON but no
    # captured queries. master's Query Store is off, which bails out long
    # before the mode block, so it cannot reach the new dump section. This
    # reaches the mode with an empty Query Store (covering that path too),
    # dumps every #ps_* table as its "is empty" row, and exercises the
    # extended guards that skip the normal-path tables the mode never
    # creates. With no XML rows, the go-sqlcmd rendering problem the other
    # @debug test dodges does not apply here.
    empty_db = TEST_DB + "_empty"
    drop_empty = ("IF DB_ID(N'%s') IS NOT NULL BEGIN "
                  "ALTER DATABASE %s SET SINGLE_USER WITH ROLLBACK IMMEDIATE; "
                  "DROP DATABASE %s; END;" % (empty_db, empty_db, empty_db))
    _sqlcmd(server, password,
            drop_empty +
            " CREATE DATABASE %s; ALTER DATABASE %s SET QUERY_STORE = ON "
            "(OPERATION_MODE = READ_WRITE);" % (empty_db, empty_db))
    try:
        sql = ("SET NOCOUNT ON; EXECUTE dbo.sp_QuickieStore "
               "@database_name = '%s', @find_parameter_sensitive = 1, "
               "@debug = 1;" % empty_db)
        out, err = _sqlcmd(server, password, sql)
        R.check("ParamSensitive",
                "@debug = 1 on an empty Query Store: no severe SQL error",
                not find_sql_errors(out + "\n" + err),
                str(find_sql_errors(out + "\n" + err)))
        R.check("ParamSensitive", "@debug = 1 reaches the mode's DEBUG dumps",
                "#ps_shape_stats is empty" in out,
                "new dump section not reached")
    finally:
        _sqlcmd(server, password, drop_empty)


# Regression mode, and wait stats across more than one Query Store interval.
# The main fixture runs its whole workload in one burst, so each plan has one
# interval and neither of these shows there. This database uses one-minute
# intervals, and its workload runs in two slots: slot A when the harness
# starts, and slot B after the other tests, in a later interval. In each slot,
# one rm_q1 execution waits on a lock that a second session holds, and the
# other executions don't wait. Slot A runs that execution last, and slot B
# runs it first, so the last duration differs between the two periods. rm_q3
# reads the same row and waits once in each slot: after rm_q1 in slot A, and
# before it in slot B. So the latest Lock wait comes from rm_q3 in the
# baseline period, and from rm_q1 in the current period and the whole window.
# rm_q2 never waits, and gets a new index between the slots, so it has one
# plan in each slot.
RM_DB = TEST_DB + "_rm"
RM_MARKER = "qs_rm_marker"

RM_FIXTURE_SQL = """
SET NOCOUNT ON;
IF DB_ID(N'{db}') IS NOT NULL
BEGIN
    ALTER DATABASE {db} SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE {db};
END;
CREATE DATABASE {db};
ALTER DATABASE {db} SET QUERY_STORE = ON
    (OPERATION_MODE = READ_WRITE, INTERVAL_LENGTH_MINUTES = 1,
     QUERY_CAPTURE_MODE = ALL, WAIT_STATS_CAPTURE_MODE = ON);
""".format(db=RM_DB)

# Wait for READ_WRITE, then run a throwaway query in a retry loop until Query
# Store captures it, so capture is known to be live before slot A compiles
# anything. Clearing the plan cache after that makes rm_q1, rm_q2, and rm_q3
# compile fresh in slot A, with capture on.
RM_SCHEMA_SQL = """
SET NOCOUNT ON;
DECLARE @tries integer = 0, @rows bigint = 0;
WHILE @tries < 30
AND   NOT EXISTS (SELECT 1/0 FROM sys.database_query_store_options AS dqso
                  WHERE dqso.actual_state_desc = N'READ_WRITE')
BEGIN
    WAITFOR DELAY '00:00:01';
    SET @tries += 1;
END;
CREATE TABLE dbo.rm_lock (id integer NOT NULL PRIMARY KEY, v integer NOT NULL);
INSERT dbo.rm_lock (id, v) VALUES (1, 0);
CREATE TABLE dbo.rm_scan (id integer NOT NULL PRIMARY KEY, v integer NOT NULL, pad char(200) NOT NULL);
INSERT dbo.rm_scan WITH (TABLOCK) (id, v, pad)
SELECT x.n, x.n % 100, 'x'
FROM
(
    SELECT TOP (5000)
        n = ROW_NUMBER() OVER (ORDER BY (SELECT NULL))
    FROM sys.all_columns AS ac1
    CROSS JOIN sys.all_columns AS ac2
) AS x;
EXECUTE (N'CREATE PROCEDURE dbo.rm_q1 AS BEGIN SELECT /* qs_rm_marker */ l.v FROM dbo.rm_lock AS l WHERE l.id = 1; END;');
EXECUTE (N'CREATE PROCEDURE dbo.rm_q2 AS BEGIN SELECT /* qs_rm_marker */ c = COUNT_BIG(*) FROM dbo.rm_scan AS s WHERE s.v = 5; END;');
EXECUTE (N'CREATE PROCEDURE dbo.rm_q3 AS BEGIN SELECT /* qs_rm_marker */ l.id, l.v FROM dbo.rm_lock AS l WHERE l.id = 1; END;');
SET @tries = 0;
WHILE @tries < 10 AND @rows = 0
BEGIN
    EXECUTE (N'SELECT /* rm_warmup */ c = COUNT_BIG(*) FROM dbo.rm_lock AS l;');
    EXECUTE sys.sp_query_store_flush_db;
    SELECT @rows = COUNT_BIG(*) FROM sys.query_store_query_text AS qsqt
    WHERE qsqt.query_sql_text LIKE N'%rm[_]warmup%';
    IF @rows = 0 WAITFOR DELAY '00:00:01';
    SET @tries += 1;
END;
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
SELECT marker = 'RM_WARM:' + CONVERT(varchar(20), @rows);
"""

# The lock holder: takes an X lock on the row rm_q1 and rm_q3 read, waits
# until it sees a request blocked behind it, then holds the lock 2 more
# seconds.
RM_HOLDER_SQL = """
SET NOCOUNT ON;
BEGIN TRANSACTION;
UPDATE l SET l.v += 1 FROM dbo.rm_lock AS l WHERE l.id = 1;
DECLARE @tries integer = 0;
WHILE @tries < 300
AND   NOT EXISTS (SELECT 1/0 FROM sys.dm_exec_requests AS der
                  WHERE der.blocking_session_id = @@SPID)
BEGIN
    WAITFOR DELAY '00:00:00.100';
    SET @tries += 1;
END;
WAITFOR DELAY '00:00:02';
COMMIT TRANSACTION;
"""

# The waiter: runs {proc} (rm_q1 or rm_q3) once the holder's X lock on
# rm_lock is granted, so it blocks. The check names the table because other
# sessions, such as Query Store's own writes, can hold X key locks in the
# same database.
RM_BLOCKED_SQL = """
SET NOCOUNT ON;
DECLARE @tries integer = 0;
WHILE @tries < 300
AND   NOT EXISTS (SELECT 1/0 FROM sys.dm_tran_locks AS dtl
                  JOIN sys.partitions AS p
                    ON p.hobt_id = dtl.resource_associated_entity_id
                  WHERE dtl.resource_database_id = DB_ID()
                  AND   dtl.resource_type = N'KEY'
                  AND   dtl.request_mode = N'X'
                  AND   dtl.request_status = N'GRANT'
                  AND   p.object_id = OBJECT_ID(N'dbo.rm_lock'))
BEGIN
    WAITFOR DELAY '00:00:00.100';
    SET @tries += 1;
END;
EXECUTE dbo.{proc};
"""

# {proc}'s Lock wait so far, in ms, after a flush.
RM_LOCK_TOTAL_SQL = """
SET NOCOUNT ON;
EXECUTE sys.sp_query_store_flush_db;
SELECT marker = 'RM_LOCK:' + CONVERT(varchar(20), ISNULL(SUM(qsws.total_query_wait_time_ms), 0))
FROM sys.query_store_wait_stats AS qsws
JOIN sys.query_store_plan AS qsp ON qsp.plan_id = qsws.plan_id
JOIN sys.query_store_query AS qsq ON qsq.query_id = qsp.query_id
WHERE qsq.object_id = OBJECT_ID(N'dbo.{proc}')
AND   qsws.wait_category_desc = N'Lock';
"""

# Server time: local for the procedure's date parameters, which it reads as
# server local time; with offset for comparing to last_execution_time; and the
# UTC minute number, to tell when a new one-minute interval has started.
RM_NOW_SQL = """
SET NOCOUNT ON;
SELECT marker = 'RM_NOW|' +
    CONVERT(varchar(23), CONVERT(datetime2(3), SYSDATETIME()), 126) + '|' +
    CONVERT(varchar(40), SYSDATETIMEOFFSET(), 127) + '|' +
    CONVERT(varchar(20), DATEDIFF(MINUTE, '20000101', SYSUTCDATETIME()));
"""

# Query Store's own numbers, per plan and period. A runtime row belongs to
# the current period when its last execution is at or after the split, as in
# the procedure. A wait row belongs to the period of the runtime row for the
# same plan, interval, and execution type.
RM_TRUTH_SQL = """
SET NOCOUNT ON;
DECLARE @split datetimeoffset(7) = CONVERT(datetimeoffset(7), '{split}', 127);
SELECT
    gt = 'GT|runs|' + CONVERT(varchar(20), qsrs.plan_id) + '|' +
         OBJECT_NAME(qsq.object_id) + '|' + p.period + '|' +
         CONVERT(varchar(20), SUM(qsrs.count_executions))
FROM sys.query_store_runtime_stats AS qsrs
JOIN sys.query_store_plan AS qsp ON qsp.plan_id = qsrs.plan_id
JOIN sys.query_store_query AS qsq ON qsq.query_id = qsp.query_id
CROSS APPLY
(
    SELECT period = CASE WHEN qsrs.last_execution_time >= @split THEN 'No' ELSE 'Yes' END
) AS p
WHERE qsq.object_id IN (OBJECT_ID(N'dbo.rm_q1'), OBJECT_ID(N'dbo.rm_q2'),
                        OBJECT_ID(N'dbo.rm_q3'))
GROUP BY qsrs.plan_id, qsq.object_id, p.period;
SELECT
    gt = 'GT|waits|' + CONVERT(varchar(20), qsws.plan_id) + '|' +
         OBJECT_NAME(qsq.object_id) + '|' + p.period + '|' +
         qsws.wait_category_desc + '|' +
         CONVERT(varchar(20), SUM(qsws.total_query_wait_time_ms))
FROM sys.query_store_wait_stats AS qsws
JOIN sys.query_store_plan AS qsp ON qsp.plan_id = qsws.plan_id
JOIN sys.query_store_query AS qsq ON qsq.query_id = qsp.query_id
CROSS APPLY
(
    SELECT period = CASE WHEN MAX(qsrs.last_execution_time) >= @split THEN 'No' ELSE 'Yes' END
    FROM sys.query_store_runtime_stats AS qsrs
    WHERE qsrs.plan_id = qsws.plan_id
    AND   qsrs.runtime_stats_interval_id = qsws.runtime_stats_interval_id
    AND   qsrs.execution_type = qsws.execution_type
) AS p
WHERE qsq.object_id IN (OBJECT_ID(N'dbo.rm_q1'), OBJECT_ID(N'dbo.rm_q2'),
                        OBJECT_ID(N'dbo.rm_q3'))
GROUP BY qsws.plan_id, qsq.object_id, p.period, qsws.wait_category_desc;
SELECT
    gt = 'GT|wexec|' + CONVERT(varchar(20), qsws.plan_id) + '|' +
         OBJECT_NAME(qsq.object_id) + '|' + p.period + '|' +
         qsws.wait_category_desc + '|' +
         CONVERT(varchar(40), SUM(qsws.total_query_wait_time_ms / NULLIF(qsws.avg_query_wait_time_ms, 0)))
FROM sys.query_store_wait_stats AS qsws
JOIN sys.query_store_plan AS qsp ON qsp.plan_id = qsws.plan_id
JOIN sys.query_store_query AS qsq ON qsq.query_id = qsp.query_id
CROSS APPLY
(
    SELECT period = CASE WHEN MAX(qsrs.last_execution_time) >= @split THEN 'No' ELSE 'Yes' END
    FROM sys.query_store_runtime_stats AS qsrs
    WHERE qsrs.plan_id = qsws.plan_id
    AND   qsrs.runtime_stats_interval_id = qsws.runtime_stats_interval_id
    AND   qsrs.execution_type = qsws.execution_type
) AS p
WHERE qsq.object_id IN (OBJECT_ID(N'dbo.rm_q1'), OBJECT_ID(N'dbo.rm_q2'),
                        OBJECT_ID(N'dbo.rm_q3'))
AND   qsws.total_query_wait_time_ms > 0
GROUP BY qsws.plan_id, qsq.object_id, p.period, qsws.wait_category_desc;
"""

# WaitStatsByQuery and WaitStatsTotal log tables in the shape the procedure
# created before they had a period column. Logging to them has to add the
# column first.
RM_OLD_LOG_SQL = """
SET NOCOUNT ON;
CREATE TABLE dbo.qs_rm_old_WaitStatsByQuery
(
    id bigint IDENTITY,
    collection_time datetime2(7) NOT NULL DEFAULT SYSDATETIME(),
    source nvarchar(40) NULL,
    database_name sysname NULL,
    plan_id bigint NULL,
    object_name nvarchar(257) NULL,
    wait_category_desc nvarchar(60) NULL,
    total_query_wait_time_ms bigint NULL,
    total_query_duration_ms bigint NULL,
    avg_query_wait_time_ms bigint NULL,
    avg_query_duration_ms bigint NULL,
    last_query_wait_time_ms bigint NULL,
    last_query_duration_ms bigint NULL,
    min_query_wait_time_ms bigint NULL,
    min_query_duration_ms bigint NULL,
    max_query_wait_time_ms bigint NULL,
    max_query_duration_ms bigint NULL,
    PRIMARY KEY CLUSTERED (collection_time, id)
);
CREATE TABLE dbo.qs_rm_old_WaitStatsTotal
(
    id bigint IDENTITY,
    collection_time datetime2(7) NOT NULL DEFAULT SYSDATETIME(),
    source nvarchar(40) NULL,
    database_name sysname NULL,
    wait_category_desc nvarchar(60) NULL,
    total_query_wait_time_ms bigint NULL,
    total_query_duration_ms bigint NULL,
    avg_query_wait_time_ms bigint NULL,
    avg_query_duration_ms bigint NULL,
    last_query_wait_time_ms bigint NULL,
    last_query_duration_ms bigint NULL,
    min_query_wait_time_ms bigint NULL,
    min_query_duration_ms bigint NULL,
    max_query_wait_time_ms bigint NULL,
    max_query_duration_ms bigint NULL,
    PRIMARY KEY CLUSTERED (collection_time, id)
);
"""

# Whether the WaitStatsByQuery and WaitStatsTotal log tables have the period
# column, then their rows.
RM_LOG_COLUMN_SQL = """
SET NOCOUNT ON;
SELECT marker = 'RM_COL|' +
    CASE
        WHEN COL_LENGTH(N'dbo.{prefix}_WaitStatsByQuery',
                        N'from_regression_baseline_time_period') IS NULL
        THEN 'missing'
        ELSE 'present'
    END + '|' +
    CASE
        WHEN COL_LENGTH(N'dbo.{prefix}_WaitStatsTotal',
                        N'from_regression_baseline_time_period') IS NULL
        THEN 'missing'
        ELSE 'present'
    END;
"""

RM_LOG_ROWS_SQL = """
SET NOCOUNT ON;
SELECT
    rm_log = 'RM_LOG|' + CONVERT(varchar(20), w.plan_id) + '|' +
             COALESCE(w.from_regression_baseline_time_period, 'NULL') + '|' +
             w.wait_category_desc + '|' +
             CONVERT(varchar(20), w.total_query_wait_time_ms)
FROM dbo.{prefix}_WaitStatsByQuery AS w;
"""

RM_LOG_TOTAL_ROWS_SQL = """
SET NOCOUNT ON;
SELECT
    rm_tot = 'RM_TOT|' +
             COALESCE(t.from_regression_baseline_time_period, 'NULL') + '|' +
             t.wait_category_desc + '|' +
             CONVERT(varchar(20), t.total_query_wait_time_ms)
FROM dbo.{prefix}_WaitStatsTotal AS t;
"""

RM_CLEANUP_SQL = """
SET NOCOUNT ON;
IF DB_ID(N'{db}') IS NOT NULL
BEGIN
    ALTER DATABASE {db} SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE {db};
END;
""".format(db=RM_DB)

SEPARATOR = re.compile(r"^-+(\t-+)*$")


def number(value):
    """A result set value as a float, or None."""
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def result_sets(stdout):
    """Every result set as (header, rows): a header line, a dashed separator
    line, then rows up to the next blank line."""
    lines = stdout.splitlines()
    sets = []
    i = 0
    while i < len(lines) - 1:
        if lines[i].strip() and SEPARATOR.match(lines[i + 1]):
            header = lines[i].split("\t")
            rows = []
            j = i + 2
            while j < len(lines) and lines[j].strip():
                rows.append(lines[j].split("\t"))
                j += 1
            sets.append((header, rows))
            i = j
        else:
            i += 1
    return sets


def source_rows(stdout, source):
    """Rows, as dicts, from every result set whose source column is `source`."""
    found = []
    for header, rows in result_sets(stdout):
        if header and header[0] == "source":
            found.extend(dict(zip(header, r)) for r in rows
                         if r and r[0] == source)
    return found


def rm_now(server, password):
    """(local, with offset, UTC minute number) from the server clock."""
    out, _ = _sqlcmd(server, password, RM_NOW_SQL)
    m = re.search(r"RM_NOW\|([^|]+)\|([^|]+)\|(\d+)", out)
    return (m.group(1), m.group(2).strip(), int(m.group(3))) if m else None


def rm_lock_total(server, password, proc="rm_q1"):
    out, _ = _sqlcmd(server, password, RM_LOCK_TOTAL_SQL.format(proc=proc),
                     database=RM_DB)
    m = re.search(r"RM_LOCK:(\d+)", out)
    return int(m.group(1)) if m else None


def rm_plain(server, password, count):
    """rm_q1 and rm_q2, `count` times each, with nothing blocking them."""
    sql = "SET NOCOUNT ON; " + " ".join(
        ["EXECUTE dbo.rm_q1;"] * count + ["EXECUTE dbo.rm_q2;"] * count)
    out, err = _sqlcmd(server, password, sql, database=RM_DB)
    return find_sql_errors(out + "\n" + err)


def rm_blocked(server, password, proc="rm_q1"):
    """One execution of proc (rm_q1 or rm_q3) that waits on a lock for at
    least 2 seconds. Tries up to 3 times, so one run that Query Store does
    not record as a wait can't fail the fixture. Returns (errors, proc's
    Lock wait increase in ms)."""
    before = rm_lock_total(server, password, proc) or 0
    errs, added = [], 0
    for _ in range(3):
        holder = subprocess.Popen(
            _sqlcmd_prefix() + ["-S", server, "-U", "sa", "-P", password,
                                "-d", RM_DB, "-Q", RM_HOLDER_SQL],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            out, err = _sqlcmd(server, password, RM_BLOCKED_SQL.format(proc=proc),
                               database=RM_DB, timeout=120)
            h_out, h_err = holder.communicate(timeout=120)
        finally:
            if holder.poll() is None:
                holder.kill()
        text = (out + "\n" + err + "\n" +
                h_out.decode("utf-8", errors="replace") + "\n" +
                h_err.decode("utf-8", errors="replace"))
        errs = find_sql_errors(text)
        if holder.returncode:
            errs.append("lock holder exited %d: %s"
                        % (holder.returncode, text.strip()[-200:]))
        added = (rm_lock_total(server, password, proc) or 0) - before
        if errs or added >= 1000:
            break
    return errs, added


def regression_window_setup(server, password, R):
    """Build the regression database and run slot A. Returns what slot B
    needs, or None if the fixture failed."""
    out, err = _sqlcmd(server, password, RM_FIXTURE_SQL)
    errs = find_sql_errors(out + "\n" + err)
    if not errs:
        out, err = _sqlcmd(server, password, RM_SCHEMA_SQL, database=RM_DB,
                           timeout=600)
        errs = find_sql_errors(out + "\n" + err)
    m = re.search(r"RM_WARM:(\d+)", out)
    R.check("RegressionFixture", "database built and Query Store capturing",
            not errs and bool(m) and int(m.group(1)) > 0,
            "errors=%s warmup=%s" % (errs[:2], m.group(1) if m else "absent"))
    if errs or not m or int(m.group(1)) == 0:
        return None

    # Slot A: plain runs, then rm_q1 waits, then rm_q3 waits, so rm_q3 has
    # the latest Lock wait in the baseline period.
    start = rm_now(server, password)
    errs = rm_plain(server, password, 3)
    block_errs, waited = rm_blocked(server, password, "rm_q1")
    block_errs3, waited3 = rm_blocked(server, password, "rm_q3")
    errs += block_errs + block_errs3
    end = rm_now(server, password)
    ok = bool(not errs and waited >= 1000 and waited3 >= 1000 and start and end)
    R.check("RegressionFixture", "slot A: rm_q1 and rm_q3 waited on a lock", ok,
            "errors=%s lock wait added: rm_q1 %d ms, rm_q3 %d ms"
            % (errs[:2], waited, waited3))
    if not ok:
        return None
    return {"start": start, "slot_a_end": end}


def regression_window_tests(server, password, R, state):
    """Slot B, then regression mode and a whole-window run, checked against
    Query Store's own numbers."""
    # Slot B has to be in a later interval than slot A. The other tests
    # usually take longer than a minute, so this rarely waits.
    _sqlcmd(server, password,
            "SET NOCOUNT ON; WHILE DATEDIFF(MINUTE, '20000101', SYSUTCDATETIME()) "
            "<= %d WAITFOR DELAY '00:00:00.500';" % state["slot_a_end"][2],
            timeout=120)
    out, err = _sqlcmd(server, password,
                       "SET NOCOUNT ON; CREATE INDEX v ON dbo.rm_scan (v);",
                       database=RM_DB)
    errs = find_sql_errors(out + "\n" + err)
    # Slot B: rm_q3 waits, then rm_q1 waits, then the plain runs, so rm_q1
    # has the latest Lock wait in the current period and the whole window.
    split = rm_now(server, password)
    block_errs3, waited3 = rm_blocked(server, password, "rm_q3")
    block_errs, waited = rm_blocked(server, password, "rm_q1")
    errs += block_errs3 + block_errs + rm_plain(server, password, 5)
    _sqlcmd(server, password,
            "SET NOCOUNT ON; EXECUTE sys.sp_query_store_flush_db; WAITFOR DELAY '00:00:01';",
            database=RM_DB)
    end = rm_now(server, password)
    ok = bool(not errs and waited >= 1000 and waited3 >= 1000 and split and end)
    R.check("RegressionFixture", "slot B: rm_q3 and rm_q1 waited on a lock", ok,
            "errors=%s lock wait added: rm_q3 %d ms, rm_q1 %d ms"
            % (errs[:2], waited3, waited))
    if not ok:
        return

    out, err = _sqlcmd(server, password, RM_TRUTH_SQL.format(split=split[1]),
                       database=RM_DB)
    runs = {}
    for plan, obj, period, n in re.findall(
            r"GT\|runs\|(\d+)\|(\w+)\|(Yes|No)\|(\d+)", out):
        runs[(plan, period)] = (obj, int(n))
    waits = {}
    for plan, obj, period, cat, ms in re.findall(
            r"GT\|waits\|(\d+)\|(\w+)\|(Yes|No)\|([^|\r\n]+)\|(\d+)", out):
        waits[(plan, period, cat)] = int(ms)
    # The executions behind each wait average, from Query Store's own total
    # and average: its avg_query_wait_time_ms is the total over an execution
    # count. On SQL Server 2025 the count is the executions that had the wait,
    # not the interval's count_executions.
    wait_execs = {}
    for plan, obj, period, cat, n in re.findall(
            r"GT\|wexec\|(\d+)\|(\w+)\|(Yes|No)\|([^|\r\n]+)\|([\d.]+)", out):
        wait_execs[(plan, period, cat)] = float(n)
    q1_plans = sorted({p for (p, _), (o, _) in runs.items() if o == "rm_q1"})
    q2_plans = sorted({p for (p, _), (o, _) in runs.items() if o == "rm_q2"},
                      key=int)
    q3_plans = sorted({p for (p, _), (o, _) in runs.items() if o == "rm_q3"})
    R.check("RegressionFixture",
            "Query Store has one rm_q1 plan, one rm_q3 plan, and an rm_q2 plan "
            "in each slot",
            len(q1_plans) == 1 and len(q3_plans) == 1 and len(q2_plans) == 2
            and (q2_plans[0], "Yes") in runs and (q2_plans[1], "No") in runs,
            "rm_q1 plans=%s rm_q2 plans=%s rm_q3 plans=%s runs=%s"
            % (q1_plans, q2_plans, q3_plans, runs))
    if len(q1_plans) != 1 or len(q3_plans) != 1 or len(q2_plans) != 2:
        return
    q1 = q1_plans[0]
    q3 = q3_plans[0]

    def lock_ms(period=None, plan=None):
        return sum(ms for (p, per, cat), ms in waits.items()
                   if p == (plan or q1) and cat == "Lock" and period in (None, per))

    def lock_execs(period=None, plan=None):
        return sum(n for (p, per, cat), n in wait_execs.items()
                   if p == (plan or q1) and cat == "Lock" and period in (None, per))

    def one_per_query(stdout, group):
        for source in ("compilation_stats", "resource_stats"):
            ids = [r.get("query_id") for r in source_rows(stdout, source)]
            R.check(group, "%s has one row per query" % source,
                    len(ids) == 3 and len(set(ids)) == 3,
                    "query_id values: %s" % ids)

    def totals_checks(stdout, group, latest):
        """The wait stats total rows, checked against the by-query rows they
        add up, from the same run, and against Query Store. latest maps each
        period (None outside regression mode) to the plan with the latest
        Lock wait, whose last values the totals take."""
        period_col = "from_regression_baseline_time_period"
        by_query = source_rows(stdout, "query_store_wait_stats_by_query")
        totals = source_rows(stdout, "query_store_wait_stats_total")
        lock = {}
        for r in totals:
            if r.get("wait_category_desc") == "Lock":
                lock.setdefault(r.get(period_col), []).append(r)
        R.check(group, "wait stats total has one Lock row"
                + ("" if None in latest else " per period"),
                sorted(lock, key=str) == sorted(latest, key=str)
                and all(len(v) == 1 for v in lock.values()),
                "Lock rows by period: %s" % {k: len(v) for k, v in lock.items()})
        expected = {p: lock_ms(p, q1) + lock_ms(p, q3) for p in latest}
        got = {p: [r.get("total_query_wait_time_ms") for r in v]
               for p, v in lock.items()}
        R.check(group, "wait stats total Lock covers rm_q1 and rm_q3, matching "
                "Query Store", all(got.get(p) == [str(n)] for p, n in expected.items()),
                "got=%s expected=%s" % (got, expected))
        # Lock's average is the wait over the executions that had it, from
        # Query Store, not a mean of per-interval or per-plan averages.
        bad = []
        for p in latest:
            execs = lock_execs(p, q1) + lock_execs(p, q3)
            got_avg = [number(r.get("avg_query_wait_time_ms")) for r in lock.get(p, [])]
            want_avg = expected[p] / execs if execs else None
            if (want_avg is None or len(got_avg) != 1 or got_avg[0] is None
                    or not math.isclose(got_avg[0], want_avg, rel_tol=1e-6, abs_tol=0.001)):
                bad.append("%s: got %s, %s ms over %s executions = %s; by-query "
                           "(plan, total, avg) %s; execs %s"
                           % (p, got_avg, expected[p], execs, want_avg,
                              [(r.get("plan_id"), r.get("total_query_wait_time_ms"),
                                r.get("avg_query_wait_time_ms")) for r in by_query
                               if r.get("wait_category_desc") == "Lock"
                               and r.get(period_col) == p],
                              {k: v for k, v in wait_execs.items() if k[1:] == (p, "Lock")}))
        R.check(group, "wait stats total Lock average is the wait per execution "
                "from Query Store", not bad, "; ".join(bad[:3]))
        rules = {"sum": sum, "min": min, "max": max}
        bad = []
        for t in totals:
            key = (t.get("wait_category_desc"), t.get(period_col))
            rows = [r for r in by_query
                    if (r.get("wait_category_desc"), r.get(period_col)) == key]
            if not rows:
                bad.append("%s: no by-query rows" % (key,))
                continue
            # The averages are weighted by executions: a by-query row's total
            # divided by its average is its executions, so the total row's
            # average is the sum of the totals over the sum of the executions.
            # A plain mean of the by-query averages is what it used to be.
            for column, total in (("avg_query_wait_time_ms", "total_query_wait_time_ms"),
                                  ("avg_query_duration_ms", "total_query_duration_ms")):
                totals_v = [number(r.get(total)) for r in rows]
                avgs = [number(r.get(column)) for r in rows]
                value = number(t.get(column))
                if None in totals_v or None in avgs or 0 in avgs:
                    expected_avg = None
                else:
                    expected_avg = sum(totals_v) / sum(a_t / a for a_t, a in zip(totals_v, avgs))
                if (value is None or expected_avg is None or not math.isclose(
                        value, expected_avg, rel_tol=1e-6, abs_tol=0.001)):
                    bad.append("%s %s: got %s, executions-weighted %s of %s"
                               % (key, column, t.get(column), expected_avg,
                                  [(r.get(total), r.get(column)) for r in rows]))
            for column, rule in (
                    ("total_query_wait_time_ms", "sum"),
                    ("total_query_duration_ms", "sum"),
                    ("min_query_wait_time_ms", "min"),
                    ("min_query_duration_ms", "min"),
                    ("max_query_wait_time_ms", "max"),
                    ("max_query_duration_ms", "max")):
                values = [number(r.get(column)) for r in rows]
                value = number(t.get(column))
                if (value is None or None in values or not math.isclose(
                        value, rules[rule](values), rel_tol=1e-9, abs_tol=0.001)):
                    bad.append("%s %s: got %s, %s of %s"
                               % (key, column, t.get(column), rule,
                                  [r.get(column) for r in rows]))
        R.check(group, "wait stats total adds up, weights the averages by "
                "executions, and takes the min and max of the by-query rows", bool(totals) and not bad,
                "; ".join(bad[:3]) or "no wait stats total rows")
        bad = []
        for period, plan in latest.items():
            t = lock.get(period, [])
            q = [r for r in by_query if r.get("wait_category_desc") == "Lock"
                 and r.get(period_col) == period and r.get("plan_id") == plan]
            if len(t) != 1 or len(q) != 1:
                bad.append("%s: %d total rows, %d by-query rows for plan %s"
                           % (period, len(t), len(q), plan))
                continue
            for column in ("last_query_wait_time_ms", "last_query_duration_ms"):
                a, b = number(t[0].get(column)), number(q[0].get(column))
                if a is None or b is None or not math.isclose(
                        a, b, rel_tol=1e-9, abs_tol=0.001):
                    bad.append("%s %s: got %s, plan %s has %s"
                               % (period, column, t[0].get(column), plan,
                                  q[0].get(column)))
        R.check(group, "wait stats total takes Lock's last values from the plan "
                "with the latest Lock wait", not bad, "; ".join(bad[:3]))

    # Regression mode: slot A is the baseline, slot B is the current period.
    out, combined = run_qs(server, password,
                           ", @regression_baseline_start_date = '%s'"
                           ", @regression_baseline_end_date = '%s'"
                           ", @start_date = '%s', @end_date = '%s'"
                           ", @query_text_search = '%s'"
                           ", @expert_mode = 1, @format_output = 0"
                           % (state["start"][0], split[0], split[0], end[0],
                              RM_MARKER),
                           database_name=RM_DB)
    errs = find_sql_errors(combined)
    R.check("Regression", "executes cleanly and completes",
            not errs and completed(out), str(errs[:2]))
    main_rows = source_rows(out, "runtime_stats")
    keys = [(r.get("plan_id"), r.get("from_regression_baseline_time_period"))
            for r in main_rows]
    R.check("Regression", "one row per plan and period, matching Query Store",
            sorted(keys) == sorted(runs), "rows=%s expected=%s"
            % (sorted(keys), sorted(runs)))
    got = {(r.get("plan_id"), r.get("from_regression_baseline_time_period")):
           r.get("count_executions") for r in main_rows}
    R.check("Regression", "count_executions per plan and period match Query Store",
            all(got.get(k) == str(n) for k, (_, n) in runs.items()),
            "got=%s expected=%s" % (got, {k: n for k, (_, n) in runs.items()}))
    by_key = {(r.get("plan_id"), r.get("from_regression_baseline_time_period")): r
              for r in main_rows}
    base = by_key.get((q1, "Yes"), {})
    current = by_key.get((q1, "No"), {})
    try:
        base_last = float(base.get("last_duration_ms", "nan"))
        current_last = float(current.get("last_duration_ms", "nan"))
    except ValueError:
        base_last = current_last = float("nan")
    R.check("Regression",
            "rm_q1 baseline last_duration_ms is its own period's last run (waited)",
            base_last >= 1000, "baseline last_duration_ms=%s" % base_last)
    R.check("Regression",
            "rm_q1 current last_duration_ms is its own period's last run (no wait)",
            current_last < 1000, "current last_duration_ms=%s" % current_last)
    R.check("Regression", "top_waits shows Lock for rm_q1 in both periods",
            "Lock" in base.get("top_waits", "")
            and "Lock" in current.get("top_waits", ""),
            "baseline=%r current=%r" % (base.get("top_waits"),
                                        current.get("top_waits")))
    wait_rows = source_rows(out, "query_store_wait_stats_by_query")
    wkeys = [(r.get("plan_id"), r.get("from_regression_baseline_time_period"),
              r.get("wait_category_desc")) for r in wait_rows]
    R.check("Regression", "one wait row per plan, period, and category",
            len(wkeys) == len(set(wkeys)), "rows=%s" % wkeys)
    got_lock = {r.get("from_regression_baseline_time_period"):
                r.get("total_query_wait_time_ms") for r in wait_rows
                if r.get("plan_id") == q1 and r.get("wait_category_desc") == "Lock"}
    R.check("Regression", "rm_q1 Lock wait per period matches Query Store",
            got_lock.get("Yes") == str(lock_ms("Yes"))
            and got_lock.get("No") == str(lock_ms("No")),
            "got=%s expected Yes=%d No=%d" % (got_lock, lock_ms("Yes"),
                                              lock_ms("No")))
    one_per_query(out, "Regression")
    totals_checks(out, "Regression", {"Yes": q3, "No": q1})

    # The whole window, both slots, without regression mode.
    out, combined = run_qs(server, password,
                           ", @start_date = '%s', @end_date = '%s'"
                           ", @query_text_search = '%s'"
                           ", @expert_mode = 1, @format_output = 0"
                           % (state["start"][0], end[0], RM_MARKER),
                           database_name=RM_DB)
    errs = find_sql_errors(combined)
    R.check("WaitWindow", "executes cleanly and completes",
            not errs and completed(out), str(errs[:2]))
    main_rows = source_rows(out, "runtime_stats")
    plans = sorted(r.get("plan_id") for r in main_rows)
    all_plans = sorted(q1_plans + q2_plans + q3_plans)
    R.check("WaitWindow", "one row per plan", plans == all_plans,
            "rows=%s expected=%s" % (plans, all_plans))
    totals = {}
    for (p, _), (_, n) in runs.items():
        totals[p] = totals.get(p, 0) + n
    got = {r.get("plan_id"): r.get("count_executions") for r in main_rows}
    R.check("WaitWindow", "count_executions per plan match Query Store",
            all(got.get(p) == str(n) for p, n in totals.items()),
            "got=%s expected=%s" % (got, totals))
    # executions_per_second is a fraction below one execution per second: it
    # is count_executions over the whole seconds between the first and last
    # execution, and it is NULL when they fall in the same second.
    def whole_seconds(first, last):
        def secs(v):
            m = re.match(r"(\d{4})-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)", v)
            return calendar.timegm(tuple(int(g) for g in m.groups()) + (0, 0, 0))
        return secs(last) - secs(first)
    eps_bad = []
    eps_slow = 0
    for r in main_rows:
        gap = whole_seconds(r["first_execution_time"], r["last_execution_time"])
        want = int(r["count_executions"]) / gap if gap > 0 else None
        have = r.get("executions_per_second")
        have = float(have) if have not in (None, "", "NULL") else None
        if want is None:
            ok = have is None or have == 0
        else:
            ok = have is not None and abs(have - want) < 1e-6
            eps_slow += 1 if want < 1 else 0
        if not ok:
            eps_bad.append((r.get("plan_id"), r["count_executions"], gap, have))
    R.check("WaitWindow", "executions_per_second is a fraction below one per second",
            not eps_bad and eps_slow > 0,
            "bad=%s slow rows=%d" % (eps_bad, eps_slow))
    by_plan = {r.get("plan_id"): r for r in main_rows}
    R.check("WaitWindow", "top_waits shows Lock for rm_q1",
            "Lock" in by_plan.get(q1, {}).get("top_waits", ""),
            "top_waits=%r" % by_plan.get(q1, {}).get("top_waits"))
    R.check("WaitWindow", "top_waits shows no Lock for rm_q2 (control)",
            all("Lock" not in by_plan.get(p, {}).get("top_waits", "")
                for p in q2_plans) and all(p in by_plan for p in q2_plans),
            "top_waits=%s" % [by_plan.get(p, {}).get("top_waits") for p in q2_plans])
    wait_rows = source_rows(out, "query_store_wait_stats_by_query")
    wkeys = [(r.get("plan_id"), r.get("wait_category_desc")) for r in wait_rows]
    R.check("WaitWindow", "one wait row per plan and category",
            len(wkeys) == len(set(wkeys)), "rows=%s" % wkeys)
    got_lock = [r.get("total_query_wait_time_ms") for r in wait_rows
                if r.get("plan_id") == q1 and r.get("wait_category_desc") == "Lock"]
    R.check("WaitWindow", "rm_q1 Lock wait covers both slots, matching Query Store",
            got_lock == [str(lock_ms())],
            "got=%s expected=%d" % (got_lock, lock_ms()))
    one_per_query(out, "WaitWindow")
    totals_checks(out, "WaitWindow", {None: q1})

    # Regression mode logged to tables: once into tables the procedure
    # creates, once into older WaitStatsByQuery and WaitStatsTotal tables it
    # has to upgrade.
    # This runs last, so the log tables in the fixture database can't
    # affect the checks above.
    out, err = _sqlcmd(server, password, RM_OLD_LOG_SQL, database=RM_DB)
    old_errs = find_sql_errors(out + "\n" + err)
    for prefix, label, errs in (("qs_rm_new", "new log table", []),
                                ("qs_rm_old", "upgraded log table", old_errs)):
        _, combined = run_qs(server, password,
                             ", @regression_baseline_start_date = '%s'"
                             ", @regression_baseline_end_date = '%s'"
                             ", @start_date = '%s', @end_date = '%s'"
                             ", @query_text_search = '%s'"
                             ", @log_to_table = 1, @log_database_name = '%s'"
                             ", @log_table_name_prefix = '%s'"
                             % (state["start"][0], split[0], split[0], end[0],
                                RM_MARKER, RM_DB, prefix),
                             database_name=RM_DB)
        run_errs = errs + find_sql_errors(combined)
        col_out, _ = _sqlcmd(server, password,
                             RM_LOG_COLUMN_SQL.format(prefix=prefix), database=RM_DB)
        present = "RM_COL|present" in col_out
        total_present = bool(re.search(r"RM_COL\|\w+\|present", col_out))
        R.check("RegressionLog", "%s: executes cleanly and has the period column"
                % label, not run_errs and present,
                "errors=%s column=%s" % (run_errs[:2],
                                         "present" if present else "missing"))
        if present:
            out, _ = _sqlcmd(server, password, RM_LOG_ROWS_SQL.format(prefix=prefix),
                             database=RM_DB)
            rows = [(plan, period, cat.strip(), ms) for plan, period, cat, ms in
                    re.findall(r"RM_LOG\|(\d+)\|(Yes|No|NULL)\|([^|\r\n]+)\|(\d+)",
                               out)]
            keys = [(plan, period, cat) for plan, period, cat, _ in rows]
            R.check("RegressionLog",
                    "%s: one wait row per plan, period, and category, each with its "
                    "period" % label, bool(rows) and len(keys) == len(set(keys))
                    and all(period != "NULL" for _, period, _ in keys),
                    "rows=%s" % keys)
            got_lock = {period: ms for plan, period, cat, ms in rows
                        if plan == q1 and cat == "Lock"}
            R.check("RegressionLog",
                    "%s: rm_q1 Lock wait per period matches Query Store" % label,
                    got_lock.get("Yes") == str(lock_ms("Yes"))
                    and got_lock.get("No") == str(lock_ms("No")),
                    "got=%s expected Yes=%d No=%d" % (got_lock, lock_ms("Yes"),
                                                      lock_ms("No")))
        R.check("RegressionLog", "%s: WaitStatsTotal has the period column" % label,
                total_present,
                "column=%s" % ("present" if total_present else "missing"))
        if total_present:
            out, _ = _sqlcmd(server, password,
                             RM_LOG_TOTAL_ROWS_SQL.format(prefix=prefix), database=RM_DB)
            got = {}
            for period, cat, ms in re.findall(
                    r"RM_TOT\|(Yes|No|NULL)\|([^|\r\n]+)\|(\d+)", out):
                if cat.strip() == "Lock":
                    got.setdefault(period, []).append(ms)
            expected = {p: lock_ms(p, q1) + lock_ms(p, q3) for p in ("Yes", "No")}
            R.check("RegressionLog",
                    "%s: WaitStatsTotal has one Lock row per period, matching Query "
                    "Store" % label,
                    sorted(got) == ["No", "Yes"]
                    and all(got[p] == [str(n)] for p, n in expected.items()),
                    "got=%s expected=%s" % (got, expected))


# ---------------------------------------------------------------------------
# @plan_parsing
#
# One extra result set of plan findings, opt-in. The fixture is its own scratch
# database so the 1,000,000 row table does not slow the groups above. Every
# fixture query carries a /*pp_...*/ marker comment right after its first
# keyword (Query Store drops comments in front of the statement for
# sp_executesql and simple-parameterized queries), and the group finds each
# query_id by that marker, then asks sp_QuickieStore about exactly those ids.
#
# Rules not covered here, and why:
#   15 remote query        needs a linked server; no reliable loopback on a
#                          Linux container (no OLE DB provider)
#   17 Standard Edition    needs Standard Edition; CI and the lab run Developer
#   19 long compile        needs a compile of 1 second or more, which is not
#                          reproducible across machines
# ---------------------------------------------------------------------------
PP_DB = TEST_DB + "_pp"

PP_COLUMNS = ["database_name", "query_id", "plan_id", "rule_id", "rule_name",
              "finding", "object_name", "node_ids"]

PP_FIXTURE_SQL = """
SET NOCOUNT ON;
IF DB_ID(N'{db}') IS NOT NULL
BEGIN
    ALTER DATABASE {db} SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE {db};
END;
CREATE DATABASE {db};
ALTER DATABASE {db} SET QUERY_STORE = ON
    (OPERATION_MODE = READ_WRITE, DATA_FLUSH_INTERVAL_SECONDS = 60,
     INTERVAL_LENGTH_MINUTES = 1, QUERY_CAPTURE_MODE = ALL);
""".format(db=PP_DB)

# Objects. Row counts matter: the scan rules (9, 18) read the 1,000,000 row
# TableCardinality of pp_big; the rest only need enough rows for a real plan.
PP_OBJECTS_SQL = """
SET NOCOUNT ON;
DECLARE @tries integer = 0;
WHILE @tries < 30
AND   NOT EXISTS (SELECT 1/0 FROM sys.database_query_store_options AS dqso
                  WHERE dqso.actual_state_desc = N'READ_WRITE')
BEGIN
    WAITFOR DELAY '00:00:01';
    SET @tries += 1;
END;

/* one shared narrow 1,000,000 row table, built set-based */
CREATE TABLE dbo.pp_big
(
    id integer NOT NULL PRIMARY KEY CLUSTERED,
    k integer NOT NULL,
    pad char(20) NOT NULL
);

INSERT dbo.pp_big WITH (TABLOCK) (id, k, pad)
SELECT x.n, x.n % 1000, 'x'
FROM
(
    SELECT TOP (1000000) n = ROW_NUMBER() OVER (ORDER BY (SELECT NULL))
    FROM sys.all_columns AS ac1 CROSS JOIN sys.all_columns AS ac2
) AS x;

/* 100,000 rows: nonclustered index on a only, nullable n, b has few values */
CREATE TABLE dbo.pp_small
(
    id integer NOT NULL PRIMARY KEY CLUSTERED,
    a integer NOT NULL,
    b integer NOT NULL,
    c varchar(100) NOT NULL,
    n integer NULL
);

INSERT dbo.pp_small WITH (TABLOCK) (id, a, b, c, n)
SELECT x.n, x.n % 1000, x.n % 7, REPLICATE('c', 50),
       CASE WHEN x.n % 10 = 0 THEN NULL ELSE x.n % 500 END
FROM
(
    SELECT TOP (100000) n = ROW_NUMBER() OVER (ORDER BY (SELECT NULL))
    FROM sys.all_columns AS ac1 CROSS JOIN sys.all_columns AS ac2
) AS x;

CREATE INDEX ix_a ON dbo.pp_small (a);

/* a heap with no index at all: the inner side of the eager spool query */
CREATE TABLE dbo.pp_heap
(
    a integer NOT NULL,
    b integer NOT NULL,
    c varchar(100) NOT NULL
);

INSERT dbo.pp_heap WITH (TABLOCK) (a, b, c)
SELECT x.n % 5000, 1, REPLICATE('h', 50)
FROM
(
    SELECT TOP (50000) n = ROW_NUMBER() OVER (ORDER BY (SELECT NULL))
    FROM sys.all_columns AS ac1 CROSS JOIN sys.all_columns AS ac2
) AS x;

/* a two row outer table: forced nested loops runs the big scan once per row */
CREATE TABLE dbo.pp_outer (a integer NOT NULL);
INSERT dbo.pp_outer (a) VALUES (1), (2);

/* varchar column on a SQL collation, indexed: nvarchar parameters convert it */
CREATE TABLE dbo.pp_str
(
    id integer NOT NULL PRIMARY KEY CLUSTERED,
    code varchar(20) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    pad char(100) NOT NULL
);

INSERT dbo.pp_str WITH (TABLOCK) (id, code, pad)
SELECT x.n, CONVERT(varchar(20), x.n), 'p'
FROM
(
    SELECT TOP (50000) n = ROW_NUMBER() OVER (ORDER BY (SELECT NULL))
    FROM sys.all_columns AS ac1 CROSS JOIN sys.all_columns AS ac2
) AS x;

CREATE INDEX ix_code ON dbo.pp_str (code);

/* five nonclustered indexes plus the clustered key: one insert maintains six */
CREATE TABLE dbo.pp_wide
(
    id integer NOT NULL PRIMARY KEY CLUSTERED,
    c1 integer NOT NULL,
    c2 integer NOT NULL,
    c3 integer NOT NULL,
    c4 integer NOT NULL,
    c5 integer NOT NULL
);

CREATE INDEX ix1 ON dbo.pp_wide (c1);
CREATE INDEX ix2 ON dbo.pp_wide (c2);
CREATE INDEX ix3 ON dbo.pp_wide (c3);
CREATE INDEX ix4 ON dbo.pp_wide (c4);
CREATE INDEX ix5 ON dbo.pp_wide (c5);

/* the missing index query's table: unindexed, selective lookups */
CREATE TABLE dbo.pp_mi
(
    id integer NOT NULL PRIMARY KEY CLUSTERED,
    v integer NOT NULL,
    w integer NOT NULL,
    pad char(200) NOT NULL
);

INSERT dbo.pp_mi WITH (TABLOCK) (id, v, w, pad)
SELECT x.n, x.n, 1, 'm'
FROM
(
    SELECT TOP (20000) n = ROW_NUMBER() OVER (ORDER BY (SELECT NULL))
    FROM sys.all_columns AS ac1 CROSS JOIN sys.all_columns AS ac2
) AS x;

/* a scalar UDF that cannot be inlined (GETDATE), and a multi-statement TVF */
EXECUTE (N'CREATE FUNCTION dbo.pp_udf (@a integer) RETURNS integer AS BEGIN RETURN @a + DATEPART(SECOND, GETDATE()); END;');
EXECUTE (N'CREATE FUNCTION dbo.pp_mstvf () RETURNS @t TABLE (a integer NOT NULL) AS BEGIN INSERT @t (a) VALUES (1), (2), (3); RETURN; END;');
"""

# The workload. Results go into variables so the output stays small. Each
# statement is its own Query Store query.
PP_WORKLOAD_SQL = """
SET NOCOUNT ON;
DECLARE @i integer, @j integer, @c bigint, @s varchar(100);

/* 4: key lookup that applies its own predicate (b) */
EXECUTE sys.sp_executesql N'SELECT /*pp_r4*/ s.id, s.c FROM dbo.pp_small AS s WHERE s.a = @p AND s.b = @q;', N'@p integer, @q integer', 5, 3;

/* 5: NOT IN against a nullable column */
SELECT /*pp_r5*/ @i = s.id FROM dbo.pp_small AS s WHERE s.a NOT IN (SELECT s2.n FROM dbo.pp_small AS s2 WHERE s2.b = 3);

/* 6: nvarchar parameter against an indexed varchar column */
EXECUTE sys.sp_executesql N'SELECT /*pp_r6*/ s.id, s.pad FROM dbo.pp_str AS s WHERE s.code = @p;', N'@p nvarchar(20)', N'123';

/* 8: a filter that has to wait for the outer join. The OR with a column from
   the other side keeps it a Filter. A bare IS NULL on the inner side becomes an
   anti semi join on SQL Server 2025 and the Filter is gone. */
SELECT /*pp_r8*/ @i = s.id FROM dbo.pp_small AS s LEFT JOIN dbo.pp_heap AS h ON h.a = s.a WHERE h.b IS NULL OR s.b = 3;

/* 3: UDF that blocks inlining on every version */
SELECT /*pp_r3*/ @i = s.id, @j = dbo.pp_udf(s.a) FROM dbo.pp_small AS s WHERE s.id < 100;

/* 9: residual predicate on a scan of the 1,000,000 row table */
SELECT /*pp_r9*/ @c = COUNT_BIG(*) FROM dbo.pp_big AS b WHERE b.k = 77 OPTION (RECOMPILE);

/* 10: functions and a leading wildcard around columns */
SELECT /*pp_r10*/ @i = s.id FROM dbo.pp_small AS s WHERE ABS(s.b) = 5;
SELECT /*pp_r10b*/ @i = s.id FROM dbo.pp_small AS s WHERE s.c LIKE '%cc';

/* 11: multi-statement table-valued function */
SELECT /*pp_r11*/ @i = s.id FROM dbo.pp_small AS s JOIN dbo.pp_mstvf() AS f ON f.a = s.b;

/* 12: TopN Sort over a scan */
SELECT /*pp_r12*/ TOP (10) @s = s.c FROM dbo.pp_small AS s ORDER BY s.c;

/* 13: many-to-many merge join (duplicate a values on both sides) */
SELECT /*pp_r13*/ @c = SUM(CONVERT(bigint, x.id) * y.id) FROM dbo.pp_small AS x JOIN dbo.pp_small AS y ON y.a = x.a WHERE x.id < 3000 AND y.id < 3000 OPTION (MERGE JOIN);

/* 1: correlated subquery against a heap under forced nested loops */
SELECT /*pp_r1*/ @i = s.id, @j = (SELECT MAX(h.b) FROM dbo.pp_heap AS h WHERE h.a = s.a) FROM dbo.pp_small AS s WHERE s.id < 2000 OPTION (LOOP JOIN);

/* 18: the 1,000,000 row scan on the inner side of nested loops. On a small
   machine (4 cores, 1 GB: the CI containers) the optimizer puts a lazy Table
   Spool over the scan; trace flag 8690 turns the performance spool off, and
   FORCE ORDER and MAXDOP 1 keep the join order and the serial shape. */
SELECT /*pp_r18*/ @c = SUM(CONVERT(bigint, b.id) * o.a) FROM dbo.pp_outer AS o JOIN dbo.pp_big AS b ON b.k = o.a OPTION (LOOP JOIN, FORCE ORDER, MAXDOP 1, QUERYTRACEON 8690);

/* 18, unpinned: the same query with nothing but LOOP JOIN. Whatever shape the
   hardware gives (the scan directly under the join, or under a chain of spools
   and compute scalars), rule 18 has to find it. */
SELECT /*pp_r18u*/ @c = SUM(CONVERT(bigint, b.id) * o.a) FROM dbo.pp_outer AS o JOIN dbo.pp_big AS b ON b.k = o.a OPTION (LOOP JOIN);

/* 16: one insert into a table with six indexes */
INSERT /*pp_r16*/ dbo.pp_wide (id, c1, c2, c3, c4, c5) SELECT TOP (1) 2, 1, 1, 1, 1, 1 FROM sys.objects AS o OPTION (RECOMPILE);

/* 2: serial because the text says MAXDOP 1, with well over a second of CPU:
   about 150 million rows go through a hash join */
SELECT /*pp_r2*/ @c = SUM(CONVERT(bigint, b1.id) * b2.id) FROM dbo.pp_big AS b1 JOIN dbo.pp_big AS b2 ON b2.k = b1.k WHERE b2.id < 150000 OPTION (MAXDOP 1);

/* 2, negative: serial for the same reason but cheap */
SELECT /*pp_r2cheap*/ @c = COUNT_BIG(*) FROM dbo.pp_small AS s WHERE s.b = 3 OPTION (MAXDOP 1);

/* clean: a primary key seek, nothing to find */
EXECUTE sys.sp_executesql N'SELECT /*pp_clean*/ s.c FROM dbo.pp_small AS s WHERE s.id = @i;', N'@i integer', 7;

/* 7: a small query that asks for an index, run 1,100 times. Cheap per run, so
   only the executions per day gate can let it through. The join keeps the plan
   from being trivial (trivial plans carry no missing index request). */
SET @i = 0;
WHILE @i < 1100
BEGIN
    SELECT /*pp_r7*/ @j = m.id FROM dbo.pp_mi AS m JOIN dbo.pp_outer AS o ON o.a = m.w WHERE m.v = @i;
    SET @i += 1;
END;
"""

# Fixtures for the review findings. Each marker is the query the finding was
# reproduced with; the assertions are in plan_parsing_tests.
PP_REVIEW_OBJECTS_SQL = """
SET NOCOUNT ON;
/* a two row table with a key: a keyset cursor needs a unique key on every table */
CREATE TABLE dbo.pp_nl (a integer NOT NULL PRIMARY KEY CLUSTERED);
INSERT dbo.pp_nl (a) VALUES (1), (2);

/* NOT IN: a primary key against a nullable, indexed foreign key. The IS NULL test
   of the null handling is the seek itself (or its residual predicate). */
CREATE TABLE dbo.pp_pk (id integer NOT NULL PRIMARY KEY CLUSTERED);
CREATE TABLE dbo.pp_fk (id integer NOT NULL PRIMARY KEY CLUSTERED, pk_id integer NULL);
INSERT dbo.pp_pk WITH (TABLOCK) (id)
SELECT TOP (5000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) FROM sys.all_columns AS ac1;
INSERT dbo.pp_fk WITH (TABLOCK) (id, pk_id)
SELECT p.id, CASE WHEN p.id % 11 = 0 THEN NULL ELSE p.id % 400 + 1 END FROM dbo.pp_pk AS p;
CREATE INDEX ix_fk_pk ON dbo.pp_fk (pk_id);

/* a table with three nonclustered indexes: UPDATE ... OPTION (QUERYTRACEON 8790) gets a wide (per index) plan */
CREATE TABLE dbo.pp_upd (id integer NOT NULL PRIMARY KEY CLUSTERED, a integer NOT NULL, b integer NOT NULL, n integer NULL);
INSERT dbo.pp_upd WITH (TABLOCK) (id, a, b, n)
SELECT TOP (50000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)), ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) % 1000, ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) % 7,
       CASE WHEN ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) % 10 = 0 THEN NULL ELSE ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) % 500 END
FROM sys.all_columns AS ac1 CROSS JOIN sys.all_columns AS ac2;
CREATE INDEX ix_a ON dbo.pp_upd (a);
CREATE INDEX ix_b ON dbo.pp_upd (b);
CREATE INDEX ix_n ON dbo.pp_upd (n);

/* a procedure whose only plan statement is an IF condition */
EXECUTE (N'CREATE PROCEDURE dbo.pp_ifproc AS BEGIN IF /*pp_cond*/ EXISTS (SELECT 1/0 FROM dbo.pp_small AS s WHERE s.a = 5) SELECT 1; END;');
"""

PP_REVIEW_SQL = """
SET NOCOUNT ON;
DECLARE @i integer, @j integer, @c bigint, @s varchar(100), @a integer;

/* 1: an eager spool that seeks a range on one column and an equality on another,
   and returns a computed column. The key list is range columns twice, no
   commas, and Expr columns in the include list, before the fix. */
SELECT /*pp_r1b*/ @c = SUM(x.c) FROM dbo.pp_small AS o CROSS APPLY (SELECT c = SUM(h.w2) FROM (SELECT h.a, h.b, w2 = LEN(h.c) FROM dbo.pp_heap AS h) AS h WHERE h.a >= o.a AND h.a < o.a + 3 AND h.b = o.b) AS x WHERE o.id < 2000 OPTION (LOOP JOIN);

/* 4: a key lookup that fetches two columns (c and n) and applies a predicate */
EXECUTE sys.sp_executesql N'SELECT /*pp_r4b*/ s.id, s.c, s.n FROM dbo.pp_small AS s WHERE s.a = @p AND s.b = @q;', N'@p integer, @q integer', 5, 3;

/* 4: a self-join lookup. Its predicate compares the looked-up column n with a column of the outer
   alias (o.b), which is an outer row value: the finding must list n and not b */
SELECT /*pp_r4self*/ @c = SUM(LEN(s.c)) FROM dbo.pp_small AS o JOIN dbo.pp_small AS s WITH (INDEX (ix_a)) ON s.a = o.a AND s.n <> o.b WHERE o.id < 30 OPTION (LOOP JOIN, FORCE ORDER);

/* 5, negative: NOT IN over NOT NULL keys, with an unrelated IS NULL filter */
SELECT /*pp_r5nn*/ @i = s.id FROM dbo.pp_small AS s WHERE s.n IS NULL AND s.id NOT IN (SELECT s2.id FROM dbo.pp_small AS s2 WHERE s2.b = 3) OPTION (LOOP JOIN);

/* 5, negative: NOT EXISTS whose subquery has an unrelated IS NULL */
SELECT /*pp_r5ne*/ @i = s.id FROM dbo.pp_small AS s WHERE NOT EXISTS (SELECT 1/0 FROM dbo.pp_small AS s2 WHERE s2.a = s.a AND s2.b = 3 AND s2.n IS NULL) OPTION (LOOP JOIN);

/* 5, positive: <> ALL over a nullable column has the same meaning as NOT IN
   and the same plan with the null handling. Rule 5 reads the plan, not the
   query text, so it fires. */
SELECT /*pp_r5c*/ @i = s.id FROM dbo.pp_small AS s WHERE s.a <> ALL (SELECT s2.n FROM dbo.pp_small AS s2 WHERE s2.b = 3);

/* 5, positive: a NOT NULL primary key NOT IN a nullable foreign key. The IS NULL
   test is the index seek on pk_id (r5pk) or the seek's residual predicate (r5pk2). */
SELECT /*pp_r5pk*/ @i = p.id FROM dbo.pp_pk AS p WHERE p.id NOT IN (SELECT f.pk_id FROM dbo.pp_fk AS f);
SELECT /*pp_r5pk2*/ @i = p.id FROM dbo.pp_pk AS p WHERE p.id NOT IN (SELECT f.pk_id FROM dbo.pp_fk AS f WHERE f.id > 100);

/* 5, negative: NOT EXISTS with a time range on a nullable column. The anti join
   reads n IS NULL and compares n with >, never with =. */
SELECT /*pp_r5tr*/ @i = s.id FROM dbo.pp_small AS s WHERE s.id < 3000 AND NOT EXISTS (SELECT 1/0 FROM dbo.pp_small AS s2 WHERE s2.a = s.a AND s2.b <= s.b AND (s2.n IS NULL OR s2.n > s.b)) OPTION (HASH JOIN);

/* 5, negative: a hand-written wildcard (n = b OR n IS NULL) is the same shape in
   the plan as a correlated NOT IN. Only the query text tells them apart. */
SELECT /*pp_r5wild*/ @i = s.id FROM dbo.pp_small AS s WHERE s.id < 3000 AND NOT EXISTS (SELECT 1/0 FROM dbo.pp_small AS s2 WHERE s2.a = s.a AND (s2.n = s.b OR s2.n IS NULL)) OPTION (HASH JOIN);

/* 10: a table variable column under a function. The column has no database in the plan. */
DECLARE @tv TABLE (a integer NOT NULL PRIMARY KEY, k integer NOT NULL);
INSERT @tv (a, k) SELECT p.id, p.id % 7 FROM dbo.pp_pk AS p;
SELECT /*pp_r10tv*/ @i = t.a FROM @tv AS t WHERE ABS(t.k) = 3 OPTION (RECOMPILE);

/* 8, negative: a catalog view has a has_access filter on its base table */
SELECT /*pp_r8cat*/ @i = o.object_id FROM sys.objects AS o WHERE o.name LIKE N'pp_x%';

/* 3: the same UDF under MAXDOP 1. The plan gives MaxDOPSetToOne as the reason, so rule 3
   must not say the function forced the serial plan */
SELECT /*pp_r3m*/ @i = s.id, @j = dbo.pp_udf(s.a) FROM dbo.pp_small AS s WHERE s.id < 100 OPTION (MAXDOP 1);

/* 1: an eager index spool over a table variable. The finding cannot be CREATE INDEX on it */
DECLARE @tv1 TABLE (a integer NOT NULL, b integer NOT NULL);
INSERT @tv1 (a, b) SELECT h.a, h.b FROM dbo.pp_heap AS h;
SELECT /*pp_r1tv*/ @j = MAX(x.m) FROM dbo.pp_small AS s CROSS APPLY (SELECT m = MAX(t.b) FROM @tv1 AS t WHERE t.a = s.a) AS x WHERE s.id < 2000 OPTION (LOOP JOIN, RECOMPILE);

/* 8, negative: the Filter compares a column with an aggregate (an Expr another operator
   computed), so it cannot move down to the scan */
SELECT /*pp_r8expr*/ @i = s.id FROM dbo.pp_small AS s WHERE s.b <> ISNULL((SELECT MAX(h.b) FROM dbo.pp_heap AS h WHERE h.a = s.a), 0);

/* 8, negative: HAVING, a Filter on the values a Hash Match aggregate computes */
SELECT /*pp_r8hav*/ @i = s.a FROM dbo.pp_small AS s GROUP BY s.a HAVING COUNT_BIG(*) > 50 AND MAX(s.b) > 3;

/* 8, negative: a Filter on ROW_NUMBER(), which a Sequence Project computes */
SELECT /*pp_r8rn*/ @i = d.id FROM (SELECT s.id, rn = ROW_NUMBER() OVER (PARTITION BY s.a ORDER BY s.id) FROM dbo.pp_small AS s) AS d WHERE d.rn = 2;

/* 8, positive: the Filter reads an Expr a Compute Scalar builds from table columns. The TOP
   keeps the Filter above the scan */
SELECT /*pp_r8cs*/ @s = d.u FROM (SELECT TOP (1000) s.id, u = UPPER(s.c) + CONVERT(varchar(10), s.b * 2) FROM dbo.pp_small AS s ORDER BY s.id) AS d WHERE d.u LIKE 'X%';

/* 8, positive: a mixed predicate, a table column and a window aggregate. The column part could
   filter earlier, so it counts; the finding says the other part reads a window result */
SELECT /*pp_r8mix*/ @i = d.id FROM (SELECT s.id, s.b, cnt = COUNT_BIG(*) OVER (PARTITION BY s.a) FROM dbo.pp_small AS s) AS d WHERE d.b = 3 AND d.cnt > 2;

/* 8, negative: a wide (per index) UPDATE. The optimizer adds a Filter over the Split (and over a Table Spool that
   reads the Split's spool) to test whether the index key changed; there is no earlier place for it */
UPDATE /*pp_r8upd*/ dbo.pp_upd SET b = 1 WHERE a < 800 AND n IS NULL OPTION (QUERYTRACEON 8790);

/* 8, negative: the Filter reads the probe result of a semi join (EXISTS inside a CASE), which only the join makes.
   The default plan is a Merge Join (the probe Expr is only in its OutputList); LOOP JOIN gives a Nested Loops
   (ProbeColumn) */
SELECT /*pp_r8semi*/ @i = s.id FROM dbo.pp_small AS s WHERE CASE WHEN EXISTS (SELECT 1/0 FROM dbo.pp_heap AS h WHERE h.a = s.a AND h.b = 1) THEN s.b ELSE 0 END = 3;
SELECT /*pp_r8semiL*/ @i = s.id FROM dbo.pp_small AS s WHERE CASE WHEN EXISTS (SELECT 1/0 FROM dbo.pp_heap AS h WHERE h.a = s.a AND h.b = 1) THEN s.b ELSE 0 END = 3 OPTION (LOOP JOIN);

/* 8, positive: the Filter compares a table column with a value from a VALUES list (UnionNNNN, which a Constant Scan
   outputs and the joins above only pass up). It is a late Filter over the eager index spool, so rule 8 still fires. */
SELECT /*pp_r8val*/ @c = MAX(y.c) FROM (SELECT c = (SELECT COUNT_BIG(*) FROM dbo.pp_heap AS h WHERE h.a >= d.d AND h.b >= r.r) FROM (VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10),(11),(12),(13),(14),(15),(16),(17),(18),(19),(20),(21),(22),(23),(24)) AS d (d) CROSS JOIN (VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10),(11),(12),(13),(14),(15),(16),(17),(18),(19),(20),(21),(22),(23),(24)) AS r (r)) AS y OPTION (LOOP JOIN);

/* 0, negative: a plan that is only an IF condition */
EXECUTE dbo.pp_ifproc;
"""

# Rule 8 on a batch mode Window Aggregate: COUNT_BIG(*) OVER (...) has no DefinedValue, so its
# Expr is defined nowhere. Batch mode on rowstore needs compatibility level 150 and up (SQL Server 2019+).
# The partition is the constant pad column, so the filter on k cannot move below the window.
PP_BATCH_SQL = """
SET NOCOUNT ON;
DECLARE @i integer;
SELECT /*pp_r8bat*/ @i = d.id FROM (SELECT b.id, b.k, cnt = COUNT_BIG(*) OVER (PARTITION BY b.pad) FROM dbo.pp_big AS b) AS d WHERE d.k = 3 OR d.cnt > 50;
SELECT /*pp_r8bat2*/ @i = d.id FROM (SELECT b.id, b.k, cnt = COUNT_BIG(*) OVER (PARTITION BY b.pad) FROM dbo.pp_big AS b) AS d WHERE d.k = 3 AND d.cnt > 50;
"""

# Cursors, each its own batch: a STATIC and a KEYSET cursor over a join. The
# population and the fetch phases each number their operators from 0.
PP_CURSOR_SQL = """
SET NOCOUNT ON;
DECLARE @c integer;
DECLARE cs CURSOR LOCAL STATIC FOR SELECT /*pp_curs*/ s.id FROM dbo.pp_small AS s JOIN dbo.pp_heap AS h ON h.a = s.a WHERE s.a = 5 AND h.b = 1;
OPEN cs; FETCH NEXT FROM cs INTO @c; CLOSE cs; DEALLOCATE cs;
DECLARE ck CURSOR LOCAL KEYSET FOR SELECT /*pp_curk*/ s.id FROM dbo.pp_small AS s JOIN dbo.pp_str AS t ON t.id = s.id WHERE s.a = 5 AND s.b = 3 AND t.pad = 'p';
OPEN ck; FETCH NEXT FROM ck INTO @c; CLOSE ck; DEALLOCATE ck;
/* A DYNAMIC cursor has no populate step; its fetch step scans the table for the next row. The
   hashes make that scan cost well over a second of CPU, and the fetch step of every KEYSET and
   DYNAMIC cursor says NonParallelizableIntrinsicFunction, so rule 2 has to ignore it. */
DECLARE cd CURSOR LOCAL DYNAMIC FOR SELECT /*pp_curd*/ b.id FROM dbo.pp_big AS b WHERE HASHBYTES('SHA2_512', b.pad + CONVERT(varchar(20), b.id)) = 0x01 OR HASHBYTES('SHA2_512', CONVERT(varchar(20), b.k) + b.pad) = 0x02 OR HASHBYTES('SHA2_512', b.pad + CONVERT(varchar(20), b.k + b.id)) = 0x03 OR HASHBYTES('SHA2_512', CONVERT(varchar(20), b.id - b.k) + b.pad) = 0x04;
OPEN cd; FETCH NEXT FROM cd INTO @c; CLOSE cd; DEALLOCATE cd;
DECLARE cn CURSOR LOCAL KEYSET FOR SELECT /*pp_curn*/ b.id FROM dbo.pp_nl AS o JOIN dbo.pp_big AS b ON b.k = o.a OPTION (LOOP JOIN, FORCE ORDER, MAXDOP 1, QUERYTRACEON 8690);
OPEN cn; FETCH NEXT FROM cn INTO @c; CLOSE cn; DEALLOCATE cn;
"""

# Rule 2, MaxDOPSetToOne from the database scoped MAXDOP: the setting is 1 for
# this query's compile and put back afterward. About 150 million rows go
# through a hash join, as in r2.
PP_MAXDOP_COMMENT_SQL = """
SET NOCOUNT ON;
DECLARE @c bigint;
SELECT /*pp_r2c*/ @c = SUM(CONVERT(bigint, b1.id) * b2.id) FROM dbo.pp_big AS b1 JOIN dbo.pp_big AS b2 ON b2.k = b1.k WHERE b2.id < 150000;
"""

# Rule 14: a table variable compiled for one row only counts below compat 150,
# so the "old" query compiles at 140 and the "new" one at the server default.
PP_TABLEVAR_SQL = """
SET NOCOUNT ON;
DECLARE @t TABLE (a integer NOT NULL);
DECLARE @c bigint;
INSERT @t (a) VALUES (1);
SELECT /*pp_{tag}*/ @c = COUNT_BIG(*) FROM dbo.pp_small AS s JOIN @t AS t ON t.a = s.a;
"""

# Rule 0: 130 joins forced into one left-deep chain nest the plan XML past the
# 128 level limit, so it will not convert to xml. No row ever matches, so the
# first join comes back empty and the rest of the chain never runs.
PP_DEEP_SQL = ("SET NOCOUNT ON; DECLARE @i integer; SELECT /*pp_r0*/ @i = s0.a "
               "FROM dbo.pp_outer AS s0 %s OPTION (FORCE ORDER, LOOP JOIN);")

# (rule_id, rule_name, marker): each is asserted for its fixture query
PP_RULE_CASES = [
    (1, "eager index spool", "r1"),
    (2, "serial plan", "r2"),
    (3, "scalar UDF", "r3"),
    (4, "lookup with predicate", "r4"),
    (5, "NOT IN on nullable column", "r5"),
    (6, "implicit conversion prevents seek", "r6"),
    (7, "missing index request", "r7"),
    (8, "late filter", "r8"),
    (9, "scan with residual predicate", "r9"),
    (10, "non-SARGable predicate", "r10"),
    (10, "non-SARGable predicate", "r10b"),
    (11, "multi-statement table-valued function", "r11"),
    (12, "TOP over scan", "r12"),
    (13, "many-to-many merge join", "r13"),
    (16, "wide DML", "r16"),
    (18, "scan on inner side of nested loops", "r18"),
    (18, "scan on inner side of nested loops", "r18u"),
]


def pp_markers(server, password):
    """Fixture marker -> query_id, from the scratch database's Query Store."""
    out, _ = _sqlcmd(
        server, password,
        "SET NOCOUNT ON; SELECT q.query_id, "
        "SUBSTRING(t.query_sql_text, CHARINDEX(N'/*pp_', t.query_sql_text) + 5, "
        "CHARINDEX(N'*/', t.query_sql_text) - CHARINDEX(N'/*pp_', t.query_sql_text) - 5) "
        "FROM sys.query_store_query AS q "
        "JOIN sys.query_store_query_text AS t ON t.query_text_id = q.query_text_id "
        "WHERE t.query_sql_text LIKE N'%/*pp[_]%*/%' "
        "AND t.query_sql_text NOT LIKE N'%sys.query_store%' "
        "AND t.query_sql_text NOT LIKE N'%CREATE %' "
        "ORDER BY q.query_id;",
        database=PP_DB)
    found = {}
    for line in out.splitlines():
        parts = line.split("\t")
        if len(parts) == 2 and parts[0].strip().isdigit():
            found[parts[1].strip()] = int(parts[0])
    return found


def pp_run(server, password, query_ids, extra="", width=200):
    """Run sp_QuickieStore with @plan_parsing = 1 for exactly these query ids.
    Returns (stdout, findings), findings being one dict per finding row."""
    out, combined = run_qs(
        server, password,
        ", @plan_parsing = 1, @top = 1000, @include_query_ids = '%s'%s"
        % (",".join(str(q) for q in sorted(set(query_ids))), extra),
        timeout=600, database_name=PP_DB, width=width)
    return out, combined, pp_findings(out)


def pp_findings(stdout):
    """Rows of the plan findings result set: everything after its header line
    that begins with the database name and three integers. A finding can run
    over several lines, so continuation lines are skipped, not parsed."""
    header = "\t".join(PP_COLUMNS)
    lines = stdout.splitlines()
    start = next((i for i, l in enumerate(lines) if l.strip() == header), None)
    if start is None:
        return None
    rows = []
    for line in lines[start + 2:]:
        parts = line.split("\t")
        if (len(parts) >= 5 and parts[0] == PP_DB and parts[1].isdigit()
                and parts[2].isdigit() and parts[3].isdigit()):
            rows.append(dict(zip(PP_COLUMNS, parts)))
    return rows


def pp_has(findings, query_id, rule_id):
    return any(f["query_id"] == str(query_id) and f["rule_id"] == str(rule_id)
               for f in findings or [])


def pp_operators(server, password, query_id):
    """The operator list (NodeId PhysicalOp/LogicalOp) of a query's newest
    Query Store plan, on one line. A failed rule check prints it, so the next
    CI failure shows the plan shape the runner actually got."""
    try:
        out, _ = _sqlcmd(
            server, password,
            "SET NOCOUNT ON; SELECT TOP (1) 'OPS:' + ISNULL(STUFF((SELECT '; ' + "
            "CONVERT(varchar(10), r.n.value('@NodeId', 'integer')) + ' ' + "
            "r.n.value('@PhysicalOp', 'varchar(60)') + '/' + "
            "r.n.value('@LogicalOp', 'varchar(60)') "
            "FROM x.x.nodes('//*:RelOp') AS r(n) "
            "ORDER BY r.n.value('@NodeId', 'integer') "
            "FOR XML PATH('')), 1, 2, ''), '(no operators)') "
            "FROM (SELECT TRY_CAST(p.query_plan AS xml) AS x "
            "      FROM sys.query_store_plan AS p WHERE p.query_id = %d "
            "      ORDER BY p.plan_id DESC "
            "      OFFSET 0 ROWS FETCH NEXT 1 ROWS ONLY) AS x;" % int(query_id),
            database=PP_DB)
        m = re.search(r"OPS:(.*)", out)
        return " | plan operators: " + (m.group(1).strip() if m else "(none read)")
    except Exception as ex:  # diagnostics must never fail the run
        return " | plan operators unavailable: %s" % ex


def pp_phase_ops(server, password, query_id):
    """The operators of a cursor's newest Query Store plan, by phase:
    {(phase, node_id): physical_op}, phase being populate, fetch or refresh."""
    out, _ = _sqlcmd(
        server, password,
        "SET NOCOUNT ON; WITH XMLNAMESPACES (DEFAULT N'http://schemas.microsoft.com/sqlserver/2004/07/showplan') "
        "SELECT 'PH:' + CASE o.o.value('@OperationType', 'varchar(30)') WHEN 'PopulateQuery' THEN 'populate' "
        "WHEN 'FetchQuery' THEN 'fetch' WHEN 'RefreshQuery' THEN 'refresh' ELSE 'other' END + ':' + "
        "CONVERT(varchar(10), r.n.value('@NodeId', 'integer')) + ':' + r.n.value('@PhysicalOp', 'varchar(60)') "
        "FROM (SELECT TOP (1) x = TRY_CAST(p.query_plan AS xml) FROM sys.query_store_plan AS p "
        "WHERE p.query_id = %d ORDER BY p.plan_id DESC) AS x "
        "CROSS APPLY x.x.nodes('//CursorPlan/Operation') AS o (o) "
        "CROSS APPLY o.o.nodes('QueryPlan//RelOp') AS r (n);" % int(query_id),
        database=PP_DB)
    ops = {}
    for m in re.finditer(r"PH:(\w+):(\d+):([^\r\n]*)", out):
        ops[(m.group(1), int(m.group(2)))] = m.group(3).strip()
    return ops


def pp_node_refs(node_ids):
    """"3 (fetch), 5 (populate) and 2 more" -> [(3, "fetch"), (5, "populate")]"""
    return [(int(n), ph) for n, ph in re.findall(r"(\d+)(?: \((\w+)\))?(?:,|$| and)", node_ids or "")]


PP_BRACKETED = re.compile(r"\[[^\]]+\]")
PP_CREATE_INDEX = re.compile(
    r"CREATE (?:NONCLUSTERED )?INDEX \[[^\]]+\] ON (?:\[[^\]]+\]\.){0,2}\[[^\]]+\] "
    r"\(([^)]*)\)(?: INCLUDE \(([^)]*)\))?;")


def pp_index_problem(finding):
    """What is wrong with the CREATE INDEX in a rule 1 finding, or "" if it is
    fine: key and include columns bracketed and separated by ", ", no column
    twice, no Expr column. Returns (problem, statement)."""
    m = PP_CREATE_INDEX.search(finding)
    if not m:
        return "no well formed CREATE INDEX in: " + finding[:300], ""
    keys = [c.strip() for c in m.group(1).split(",")]
    incl = [c.strip() for c in m.group(2).split(",")] if m.group(2) else []
    for part in keys + incl:
        if not PP_BRACKETED.fullmatch(part):
            return "column %r is not one bracketed name" % part, m.group(0)
        if "expr" in part.lower():
            return "computed column %s in the index" % part, m.group(0)
    if ", ".join(keys) != m.group(1).strip():
        return "key list is not comma separated", m.group(0)
    if incl and ", ".join(incl) != m.group(2).strip():
        return "include list is not comma separated", m.group(0)
    if len(set(keys)) != len(keys):
        return "duplicate key column in " + m.group(1), m.group(0)
    if len(set(incl)) != len(incl) or set(keys) & set(incl):
        return "duplicate include column in " + m.group(2), m.group(0)
    return "", m.group(0)


def pp_sql_errors(text):
    """Errors from the fixture and the runs: severity 11 and up, which takes in
    the syntax errors (level 15) find_sql_errors lets through."""
    if not text:
        return []
    return re.findall(r"Msg (?:\d+, Level 1[1-9]|4060|911)[^\n]*", text)


def plan_parsing_tests(server, password, R):
    """@plan_parsing: one extra result set with plan findings, opt-in, normal
    mode only. One fixture query per rule; each rule is asserted for its query,
    clean and below-threshold queries are asserted quiet, the column list is
    pinned, the off state is asserted silent, and each rejected combination is
    asserted to raise."""
    G = "PlanParsing"
    try:
        out, err = _sqlcmd(server, password, PP_FIXTURE_SQL)
        errs = pp_sql_errors(out + "\n" + err)
        R.check(G, "scratch database created with Query Store on",
                not errs, str(errs))
        if errs:
            return
        out, err = _sqlcmd(server, password, PP_OBJECTS_SQL, database=PP_DB,
                           timeout=900)
        errs = pp_sql_errors(out + "\n" + err)
        R.check(G, "objects built", not errs, str(errs[:2]))
        if errs:
            return

        # Default compat for new databases on this server (model's level)
        out, _ = _sqlcmd(server, password,
                         "SET NOCOUNT ON; SELECT 'COMPAT:' + CONVERT(varchar(10), "
                         "d.compatibility_level) FROM sys.databases AS d "
                         "WHERE d.name = N'model';")
        m = re.search(r"COMPAT:(\d+)", out)
        default_compat = int(m.group(1)) if m else 140

        out, err = _sqlcmd(server, password, PP_WORKLOAD_SQL, database=PP_DB,
                           timeout=900)
        errs = pp_sql_errors(out + "\n" + err)
        R.check(G, "workload ran", not errs, str(errs[:2]))
        if errs:
            return

        # Rule 14 needs a plan compiled below compat 150. Compile the "old"
        # query at 140; compile a "new" one at the server default too, when the
        # default is 150 or higher, for the negative case.
        _sqlcmd(server, password,
                "ALTER DATABASE %s SET COMPATIBILITY_LEVEL = 140;" % PP_DB)
        out, err = _sqlcmd(server, password,
                           PP_TABLEVAR_SQL.format(tag="r14old"), database=PP_DB)
        errs = pp_sql_errors(out + "\n" + err)
        _sqlcmd(server, password,
                "ALTER DATABASE %s SET COMPATIBILITY_LEVEL = %d;"
                % (PP_DB, default_compat))
        if default_compat >= 150:
            out, err = _sqlcmd(server, password,
                               PP_TABLEVAR_SQL.format(tag="r14new"), database=PP_DB)
            errs += pp_sql_errors(out + "\n" + err)
        R.check(G, "table variable queries ran", not errs, str(errs[:2]))

        # Fixtures for the review findings. Rule 2's MaxDOPSetToOne case needs a
        # serial plan from a database scoped MAXDOP of 1 at compile time.
        errs = []
        for sql in (PP_REVIEW_OBJECTS_SQL, PP_REVIEW_SQL, PP_CURSOR_SQL):
            out, err = _sqlcmd(server, password, sql, database=PP_DB, timeout=900)
            errs += pp_sql_errors(out + "\n" + err)
        if default_compat >= 150:
            out, err = _sqlcmd(server, password, PP_BATCH_SQL, database=PP_DB, timeout=900)
            errs += pp_sql_errors(out + "\n" + err)
        _sqlcmd(server, password,
                "ALTER DATABASE SCOPED CONFIGURATION SET MAXDOP = 1;", database=PP_DB)
        out, err = _sqlcmd(server, password, PP_MAXDOP_COMMENT_SQL,
                           database=PP_DB, timeout=900)
        errs += pp_sql_errors(out + "\n" + err)
        _sqlcmd(server, password,
                "ALTER DATABASE SCOPED CONFIGURATION SET MAXDOP = 0;", database=PP_DB)
        R.check(G, "review fixture queries ran", not errs, str(errs[:2]))

        # Rule 0, first form: a plan too deeply nested to convert to xml.
        joins = " ".join("JOIN dbo.pp_outer AS s%d ON s%d.a = s%d.a + 100"
                         % (n, n, n - 1) for n in range(1, 131))
        out, err = _sqlcmd(server, password, PP_DEEP_SQL % joins,
                           database=PP_DB, timeout=600)
        R.check(G, "too-deep plan query ran",
                not pp_sql_errors(out + "\n" + err),
                str(pp_sql_errors(out + "\n" + err)[:2]))

        _sqlcmd(server, password, "EXECUTE sys.sp_query_store_flush_db;",
                database=PP_DB)
        ids = pp_markers(server, password)
        want = {c[2] for c in PP_RULE_CASES} | {
            "r2cheap", "clean", "r14old", "r0", "r1b", "r4b", "r4self", "r5nn", "r5ne",
            "r5c", "r8cat", "r8expr", "r8hav", "r8rn", "r8cs", "r8mix", "r8upd", "r8semi", "r8semiL", "r8val", "r1tv", "r3m", "cond", "curs", "curk", "curn", "curd", "r2c", "r5pk",
            "r5pk2", "r5tr", "r5wild", "r10tv"}
        missing = sorted(want - set(ids))
        R.check(G, "every fixture query is in Query Store", not missing,
                "missing markers: %s" % missing)
        if missing:
            return

        # A short window so executions per day clears the rule 7 gate.
        # A date without an offset is read as server local time, so ask the
        # server for its own local time two hours ago.
        out, _ = _sqlcmd(server, password,
                         "SET NOCOUNT ON; SELECT 'WIN:' + CONVERT(varchar(19), "
                         "DATEADD(HOUR, -2, SYSDATETIME()), 120);")
        window = re.search(r"WIN:(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)", out).group(1)
        all_ids = [ids[k] for k in want] + [ids[k] for k in ("r14new", "r8bat", "r8bat2") if k in ids]

        out, combined, found = pp_run(server, password, all_ids,
                                      ", @start_date = '%s'" % window)
        errs = pp_sql_errors(combined)
        R.check(G, "@plan_parsing = 1 executes cleanly", not errs, str(errs[:2]))
        R.check(G, "@plan_parsing = 1 reaches completion", completed(out),
                "footer result set missing")
        R.check(G, "findings result set has the contracted columns, in order",
                found is not None,
                "no result set headed %s" % ", ".join(PP_COLUMNS))
        found = found or []
        R.check(G, "findings result set has rows", len(found) > 0,
                "no finding rows")

        for rule_id, rule_name, marker in PP_RULE_CASES:
            hits = [f for f in found if f["query_id"] == str(ids[marker])
                    and f["rule_id"] == str(rule_id)]
            R.check(G, "rule %d (%s) fires for %s" % (rule_id, rule_name, marker),
                    len(hits) > 0 and all(h["rule_name"] == rule_name for h in hits),
                    ("no row" + pp_operators(server, password, ids[marker]))
                    if not hits else "rule_name was %r" % hits[0]["rule_name"])

        # The output is one row per (plan, rule) by construction (the fold
        # groups on it), so the check that can fail is the fold's content: the
        # same finding text must not be listed twice inside one row.
        def repeated_texts(rows):
            bad = []
            for f in rows:
                parts = re.sub(r" \| and \d+ more$", "", f["finding"]).split(" | ")
                if len(parts) != len(set(parts)):
                    bad.append((f["query_id"], f["rule_id"]))
            return bad
        R.check(G, "no finding text is listed twice in one row",
                len(found) > 0 and not repeated_texts(found),
                "repeated: %s" % repeated_texts(found)[:3])

        # Quiet cases
        R.check(G, "clean primary key seek has no findings",
                len(found) > 0
                and not any(f["query_id"] == str(ids["clean"]) for f in found),
                "findings for the clean query")
        R.check(G, "rule 2 stays quiet below 1,000 ms of CPU (MAXDOP 1, cheap)",
                len(found) > 0 and not pp_has(found, ids["r2cheap"], 2),
                "rule 2 fired")
        R.check(G, "rule 2 leaves the scalar UDF reason to rule 3",
                len(found) > 0 and not pp_has(found, ids["r3"], 2),
                "rule 2 fired for the UDF query")

        # The text of a few findings
        def finding_text(marker, rule_id):
            return next((f["finding"] for f in found
                         if f["query_id"] == str(ids[marker])
                         and f["rule_id"] == str(rule_id)), "")
        R.check(G, "rule 1 finding scripts a CREATE INDEX on the heap",
                "CREATE" in finding_text("r1", 1).upper()
                and "pp_heap" in finding_text("r1", 1),
                finding_text("r1", 1)[:120])
        R.check(G, "rule 3 finding names the function",
                "pp_udf" in finding_text("r3", 3), finding_text("r3", 3)[:120])
        R.check(G, "rule 3 says the UDF forces a serial plan when the plan gives the UDF reason",
                "force a serial plan" in finding_text("r3", 3), finding_text("r3", 3)[:160])
        R.check(G, "rule 3 does not blame the UDF when the plan is serial for MAXDOP 1",
                pp_has(found, ids["r3m"], 3) and "force a serial plan" not in finding_text("r3m", 3),
                finding_text("r3m", 3)[:160])
        R.check(G, "rule 4 finding names the table",
                "pp_small" in finding_text("r4", 4), finding_text("r4", 4)[:120])
        R.check(G, "rule 18 finding does not claim a count of executions",
                "can run again for each row" in finding_text("r18", 18),
                finding_text("r18", 18)[:160])
        R.check(G, "rule 9 finding shows the 1,000,000 row table cardinality "
                   "with thousands separators",
                "(1,000,000 rows)" in finding_text("r9", 9),
                finding_text("r9", 9)[:160])

        # --- Regression tests for the round 1 review findings ---------------
        def quiet(marker, rule_id, label):
            hit = pp_has(found, ids[marker], rule_id)
            R.check(G, label, len(found) > 0 and not hit,
                    ("rule %d fired" % rule_id) + pp_operators(server, password, ids[marker])
                    if hit else "no findings at all")

        # Rule 1 scripts a valid CREATE INDEX: the equality spool (r1), and a
        # range seek that also outputs a computed column (r1b). The harness
        # cuts wide columns at 200 characters, so read these at full width.
        out, combined, found_full = pp_run(server, password,
                                           [ids["r1"], ids["r1b"], ids["r4b"], ids["r4self"], ids["r1tv"], ids["r2c"], ids["r8mix"]]
                                           + ([ids["r8bat2"]] if "r8bat2" in ids else []),
                                           width=8000)
        found_full = found_full or []

        def full_text(marker, rule_id):
            return next((f["finding"] for f in found_full
                         if f["query_id"] == str(ids[marker])
                         and f["rule_id"] == str(rule_id)), "")
        for marker in ("r1", "r1b"):
            problem, stmt = pp_index_problem(full_text(marker, 1))
            R.check(G, "rule 1 (%s) scripts a valid CREATE INDEX" % marker,
                    not problem, problem)
            if stmt:
                perr, perr2 = _sqlcmd(server, password,
                                      "SET PARSEONLY ON; " + stmt, database=PP_DB)
                errs = pp_sql_errors(perr + "\n" + perr2)
                R.check(G, "rule 1 (%s) CREATE INDEX compiles under PARSEONLY" % marker,
                        not errs, str(errs[:1]) + " " + stmt)

        # Rule 1 on a table variable: the index goes in the DECLARE, not CREATE INDEX ... ON @t.
        # Before SQL Server 2019 an inline INDEX cannot take INCLUDE (Msg 102), so there the
        # include column goes at the end of the key and the temp table alternative is a
        # separate CREATE INDEX ... INCLUDE. Every statement the text suggests must parse.
        tv_text = full_text("r1tv", 1)
        vout, _ = _sqlcmd(server, password,
                          "SET NOCOUNT ON; SELECT 'VER:' + CONVERT(varchar(10), "
                          "SERVERPROPERTY('ProductMajorVersion'));")
        vm = re.search(r"VER:(\d+)", vout)
        server_major = int(vm.group(1)) if vm else 99
        R.check(G, "rule 1 (r1tv) suggests an inline INDEX for the table variable, not CREATE INDEX",
                "INDEX [ix_tv1_spool] ([a]" in tv_text and "in its DECLARE" in tv_text
                and "CREATE INDEX [" not in tv_text.replace(", or use a temp table and CREATE INDEX [", "")
                and " ON @" not in tv_text,
                tv_text[:400])
        inline = re.search(r"INDEX \[ix_tv1_spool\] \([^)]*\)(?: INCLUDE \([^)]*\))?", tv_text)
        if server_major < 15:
            R.check(G, "rule 1 (r1tv) on SQL Server before 2019 puts the include column in the key, "
                       "no inline INCLUDE",
                    inline is not None and inline.group(0) == "INDEX [ix_tv1_spool] ([a], [b])"
                    and "INCLUDE" not in tv_text.split("in its DECLARE")[0],
                    tv_text[:400])
            temp_ix = re.search(r"CREATE INDEX \[ix_tv1_spool\] ON \[#tv1\] \(\[a\]\) INCLUDE \(\[b\]\);",
                                tv_text)
            R.check(G, "rule 1 (r1tv) on SQL Server before 2019 gives the temp table a separate "
                       "CREATE INDEX ... INCLUDE",
                    temp_ix is not None, tv_text[:400])
        else:
            R.check(G, "rule 1 (r1tv) on SQL Server 2019 and up keeps INCLUDE in the inline index",
                    inline is not None
                    and inline.group(0) == "INDEX [ix_tv1_spool] ([a]) INCLUDE ([b])",
                    tv_text[:400])
        R.check(G, "rule 1 (r1tv) says a table-valued parameter takes the index in its table type",
                "table-valued parameter" in tv_text and "table type" in tv_text, tv_text[:400])
        if inline:
            perr, perr2 = _sqlcmd(server, password,
                                  "SET PARSEONLY ON; DECLARE @tv1 TABLE (a integer NOT NULL, "
                                  "b integer NOT NULL, " + inline.group(0) + ");",
                                  database=PP_DB)
            errs = pp_sql_errors(perr + "\n" + perr2)
            R.check(G, "rule 1 (r1tv) inline table variable INDEX parses on this version",
                    not errs, str(errs[:1]) + " " + inline.group(0))
        if server_major < 15:
            temp_stmt = re.search(r"CREATE INDEX [^;]*;", tv_text)
            if temp_stmt:
                perr, perr2 = _sqlcmd(server, password,
                                      "SET PARSEONLY ON; " + temp_stmt.group(0), database=PP_DB)
                errs = pp_sql_errors(perr + "\n" + perr2)
                R.check(G, "rule 1 (r1tv) temp table CREATE INDEX ... INCLUDE parses on this version",
                        not errs, str(errs[:1]) + " " + temp_stmt.group(0))

        # Rule 4 lists the columns it fetches with commas, and the column its
        # own predicate reads (b) after "filters on"
        fetched = re.search(r"It fetches (.*?)(?: and filters on (.*?))?: add", full_text("r4b", 4))
        items = [c.strip() for c in fetched.group(1).split(",")] if fetched else []
        R.check(G, "rule 4 lists two fetched columns, comma separated",
                len(items) >= 2 and all(re.fullmatch(r"\[?\w+\]?", c) for c in items),
                full_text("r4b", 4)[:300])
        R.check(G, "rule 4 lists the predicate column of the looked-up table",
                fetched is not None and fetched.group(2) is not None and "[b]" in fetched.group(2)
                and "[b]" not in items,
                full_text("r4b", 4)[:300])
        # In a self-join the predicate also reads the outer alias of the same table (o.b):
        # that is an outer row value, so only the looked-up alias column (n) is listed
        self_text = full_text("r4self", 4)
        self_fetched = re.search(r"It fetches (.*?)(?: and filters on (.*?))?: add", self_text)
        R.check(G, "rule 4 in a self-join lists the looked-up alias column and not the outer alias column",
                self_fetched is not None and self_fetched.group(2) is not None
                and "[n]" in self_fetched.group(2) and "[b]" not in self_fetched.group(2)
                and "[b]" not in self_fetched.group(1),
                self_text[:400])
        quiet("r8cat", 4, "rule 4 stays quiet for a lookup into a system table")

        # Rule 5 only for a real nullable NOT IN
        quiet("r5nn", 5, "rule 5 stays quiet for NOT IN over NOT NULL keys with an unrelated IS NULL")
        quiet("r5ne", 5, "rule 5 stays quiet for NOT EXISTS with an unrelated IS NULL")
        R.check(G, "rule 5 fires for <> ALL over a nullable column (same plan as NOT IN)",
                pp_has(found, ids["r5c"], 5),
                "no row" + pp_operators(server, password, ids["r5c"]))

        # Rule 2: MaxDOPSetToOne is judged from the server and database MAXDOP
        # as they are now. r2c compiled while the database MAXDOP was 1. With it
        # back at 0 the procedure cannot tell where the MAXDOP 1 came from, so it
        # is flagged, and the finding has to say that MAXDOP may have been 1 when
        # the plan compiled. With the database MAXDOP at 1 it is not flagged.
        R.check(G, "rule 2 flags MaxDOPSetToOne when server and database MAXDOP are not 1 now",
                pp_has(found, ids["r2c"], 2),
                "no row" + pp_operators(server, password, ids["r2c"]))
        R.check(G, "rule 2 MaxDOPSetToOne finding allows for a MAXDOP of 1 at compile time",
                "unless MAXDOP was 1 when the plan compiled" in full_text("r2c", 2),
                full_text("r2c", 2)[:300])
        _sqlcmd(server, password,
                "ALTER DATABASE SCOPED CONFIGURATION SET MAXDOP = 1;", database=PP_DB)
        try:
            out_m, combined_m, found_m = pp_run(server, password, [ids["r2c"]],
                                                ", @start_date = '%s'" % window)
        finally:
            _sqlcmd(server, password,
                    "ALTER DATABASE SCOPED CONFIGURATION SET MAXDOP = 0;", database=PP_DB)
        R.check(G, "rule 2 does not flag MaxDOPSetToOne when database MAXDOP 1 explains it",
                completed(out_m) and found_m is not None
                and not pp_has(found_m, ids["r2c"], 2),
                "rule 2 fired or the run did not finish")

        # Rule 12 and 8: the optimizer's own Top and has_access filter
        quiet("r5", 12, "rule 12 stays quiet for the Top inside the NOT IN null check")
        quiet("r5c", 12, "rule 12 stays quiet for the Top inside a <> ALL null check")
        quiet("r8cat", 8, "rule 8 stays quiet for the has_access filter on a catalog view")
        quiet("r8expr", 8, "rule 8 stays quiet for a filter on an aggregate result (an Expr from another operator)")
        quiet("r8hav", 8, "rule 8 stays quiet for HAVING (a filter on Hash Match aggregate values)")
        quiet("r8rn", 8, "rule 8 stays quiet for a filter on ROW_NUMBER()")
        R.check(G, "rule 8 fires for a filter on a Compute Scalar over table columns",
                pp_has(found, ids["r8cs"], 8),
                "no row" + pp_operators(server, password, ids["r8cs"]))
        # The wide UPDATE has to have the shape the rule skips, or the check proves nothing
        out, _ = _sqlcmd(server, password,
                         "SET NOCOUNT ON; SELECT 'SPLITFILTER:' + CONVERT(varchar(10), COUNT(*)) FROM "
                         "sys.query_store_plan AS p CROSS APPLY (SELECT x = TRY_CONVERT(xml, p.query_plan)) AS c "
                         "WHERE p.query_id = %d AND c.x.exist('declare default element namespace "
                         "\"http://schemas.microsoft.com/sqlserver/2004/07/showplan\"; "
                         "//RelOp[@PhysicalOp = \"Filter\"]/Filter/RelOp[@PhysicalOp = \"Split\" or @PhysicalOp = \"Table Spool\"]') = 1;"
                         % ids["r8upd"], database=PP_DB)
        R.check(G, "wide UPDATE fixture has a Filter over a Split or Table Spool",
                "SPLITFILTER:1" in out, out[:200])
        quiet("r8upd", 8, "rule 8 stays quiet for the index key change Filter over a Split in a wide UPDATE")
        quiet("r8semi", 8, "rule 8 stays quiet for a filter on a Merge Join semi join probe result")
        quiet("r8semiL", 8, "rule 8 stays quiet for a filter on a Nested Loops semi join probe result")
        # The VALUES outer side passes UnionNNNN columns up through the joins; only a column no input outputs is a join's own
        out, _ = _sqlcmd(server, password,
                         "SET NOCOUNT ON; SELECT 'VALFILTER:' + CONVERT(varchar(10), COUNT(*)) FROM "
                         "sys.query_store_plan AS p CROSS APPLY (SELECT x = TRY_CONVERT(xml, p.query_plan)) AS c "
                         "WHERE p.query_id = %d AND c.x.exist('declare default element namespace "
                         "\"http://schemas.microsoft.com/sqlserver/2004/07/showplan\"; "
                         "//RelOp[@PhysicalOp = \"Filter\"][Filter/Predicate/ScalarOperator[contains(@ScalarString, \"[Union\")]]"
                         "[Filter/RelOp/@PhysicalOp = \"Index Spool\"]') = 1;"
                         % ids["r8val"], database=PP_DB)
        R.check(G, "VALUES fixture has a Filter on a Union column over an Index Spool",
                "VALFILTER:1" in out, out[:200] + pp_operators(server, password, ids["r8val"]))
        R.check(G, "rule 8 fires for a late filter that compares a column with a VALUES list value",
                pp_has(found, ids["r8val"], 8),
                "no row" + pp_operators(server, password, ids["r8val"]))
        mix_text = full_text("r8mix", 8)
        R.check(G, "rule 8 fires for a mixed predicate and says part of it reads a window result",
                pp_has(found, ids["r8mix"], 8) and "[b]=(3)" in mix_text
                and "part of the predicate reads an aggregate" in mix_text,
                mix_text[:200])

        # A batch mode Window Aggregate has empty DefinedValues. Batch mode on rowstore is SQL Server 2019+
        # (compatibility level 150), so this is skipped on SQL Server 2017 and earlier.
        if default_compat >= 150:
            R.check(G, "batch mode window fixtures ran", "r8bat" in ids and "r8bat2" in ids,
                    "missing markers: %s" % [k for k in ("r8bat", "r8bat2") if k not in ids])
            if "r8bat" in ids and "r8bat2" in ids:
                out, _ = _sqlcmd(server, password,
                                 "SET NOCOUNT ON; SELECT 'BATCHWIN:' + CONVERT(varchar(10), COUNT(*)) FROM "
                                 "sys.query_store_plan AS p CROSS APPLY (SELECT x = TRY_CONVERT(xml, p.query_plan)) AS c "
                                 "WHERE p.query_id = %d AND c.x.exist('declare default element namespace "
                                 "\"http://schemas.microsoft.com/sqlserver/2004/07/showplan\"; "
                                 "//RelOp[@PhysicalOp = \"Window Aggregate\"][@EstimatedExecutionMode = \"Batch\"]"
                                 "[WindowAggregate/DefinedValues[not(DefinedValue)]]') = 1;"
                                 % ids["r8bat"], database=PP_DB)
                R.check(G, "batch mode window fixture has a Window Aggregate with no DefinedValue",
                        "BATCHWIN:1" in out, out[:200])
                quiet("r8bat", 8, "rule 8 stays quiet when the other part of an OR reads a batch mode COUNT(*) OVER result")
                bat_text = full_text("r8bat2", 8)
                R.check(G, "rule 8 fires for the AND form and says part of it reads a window result",
                        pp_has(found, ids["r8bat2"], 8) and "[k]=(3)" in bat_text
                        and "part of the predicate reads an aggregate" in bat_text,
                        bat_text[:200])

        # Rule 0: a plan that is only an IF condition is checked or skipped
        quiet("cond", 0, "rule 0 does not fire for a plan that is only an IF condition")

        # Rule 5 across the shapes real NOT IN bugs produce, and the ones that
        # only look like them
        for marker, label in (("r5pk", "a NOT NULL key NOT IN a nullable indexed column (the seek tests IS NULL)"),
                              ("r5pk2", "a NOT NULL key NOT IN a nullable column, IS NULL in the seek's residual predicate")):
            R.check(G, "rule 5 fires for %s" % label,
                    pp_has(found, ids[marker], 5),
                    "no row" + pp_operators(server, password, ids[marker]))
        quiet("r5tr", 5, "rule 5 stays quiet for NOT EXISTS with a time range (IS NULL OR column > x)")
        quiet("r5wild", 5, "rule 5 stays quiet for a hand-written wildcard (n = x OR n IS NULL) with no NOT IN")
        R.check(G, "rule 10 fires for a function over a table variable column",
                pp_has(found, ids["r10tv"], 10),
                "no row" + pp_operators(server, password, ids["r10tv"]))

        # Rule 1's index covers the columns behind a computed spool output:
        # r1b outputs LEN(c), so c has to be in the INCLUDE list
        m1b = PP_CREATE_INDEX.search(full_text("r1b", 1))
        R.check(G, "rule 1 (r1b) INCLUDE has the column behind the computed output",
                m1b is not None and m1b.group(2) is not None and "[c]" in m1b.group(2),
                full_text("r1b", 1)[:300])

        # Cursors: the populate, fetch and refresh phases each number their
        # operators from 0. A node id in a cursor finding must name its phase,
        # and that phase must have an operator with that id.
        cursor_ops = {m: pp_phase_ops(server, password, ids[m])
                      for m in ("curs", "curk", "curn", "curd")}
        for marker, ops in cursor_ops.items():
            rows = [f for f in found if f["query_id"] == str(ids[marker]) and f["node_ids"] not in ("", "NULL")]
            bad = []
            for f in rows:
                for node, phase in pp_node_refs(f["node_ids"]):
                    if phase is None or (phase, node) not in ops:
                        bad.append((f["rule_id"], node, phase))
            R.check(G, "cursor query %s: every node id names a phase that has that operator" % marker,
                    len(ops) > 0 and not bad,
                    "node ids with no matching operator in their phase: %s (phase operators: %d)" % (bad, len(ops)))

        # curk: the KEYSET cursor's only node level finding is the key lookup
        # that applies a predicate (rule 4). It names pp_small, and its node id
        # is a lookup in the populate phase, not a node of the same number in
        # the fetch phase.
        k4 = [f for f in found if f["query_id"] == str(ids["curk"]) and f["rule_id"] == "4"]
        k_ops = cursor_ops["curk"]

        def k_ok(f):
            nodes = pp_node_refs(f["node_ids"])
            return ("pp_small" in f["finding"] and len(nodes) > 0
                    and all(ph == "populate"
                            and ("Seek" in k_ops.get((ph, n), "") or "Lookup" in k_ops.get((ph, n), ""))
                            for n, ph in nodes))
        R.check(G, "cursor query curk: rule 4 names pp_small and points at a lookup in the populate phase",
                len(k4) >= 1 and all(k_ok(f) for f in k4),
                "rule 4 rows: %s; phase operators: %s" % (k4[:2], k_ops))
        stray = sorted({(m, f["rule_id"]) for m in ("curs", "curk") for f in found
                        if f["query_id"] == str(ids[m])
                        and f["rule_id"] in ("4", "5", "8", "12", "14", "18")
                        and (m, f["rule_id"]) != ("curk", "4")})
        R.check(G, "cursor queries curs and curk have no stray node level findings",
                len(found) > 0 and not stray, "rules fired: %s" % stray)
        R.check(G, "cursor query curn: rule 18 fires and no other node level rule does",
                pp_has(found, ids["curn"], 18)
                and not ({f["rule_id"] for f in found if f["query_id"] == str(ids["curn"])}
                         & {"4", "5", "8", "12", "14"}),
                "rules: %s" % sorted({f["rule_id"] for f in found
                                      if f["query_id"] == str(ids["curn"])}))

        # Rule 2 reads NonParallelPlanReason from a cursor's populate step only.
        # curd is a DYNAMIC cursor, so it has no populate step, and its fetch
        # step always says NonParallelizableIntrinsicFunction. The check is only
        # worth anything if the fixture really has the CPU, so that is asserted.
        out_cpu, _ = _sqlcmd(
            server, password,
            "SET NOCOUNT ON; SELECT 'CPU:' + CONVERT(varchar(30), CONVERT(bigint, "
            "MAX(rs.avg_cpu_time) / 1000.0)) FROM sys.query_store_runtime_stats AS rs "
            "JOIN sys.query_store_plan AS p ON p.plan_id = rs.plan_id WHERE p.query_id = %d;"
            % ids["curd"], database=PP_DB)
        m_cpu = re.search(r"CPU:(\d+)", out_cpu)
        cpu_ms = int(m_cpu.group(1)) if m_cpu else 0
        reasons_fetch = any(ph == "fetch" for ph, _ in cursor_ops["curd"])
        R.check(G, "cursor query curd has a fetch step and at least 1,000 ms of CPU (fixture is hot enough)",
                reasons_fetch and cpu_ms >= 1000,
                "fetch step: %s, CPU %d ms" % (reasons_fetch, cpu_ms))
        R.check(G, "rule 2 stays quiet for a cursor's fetch step reason",
                len(found) > 0 and not pp_has(found, ids["curd"], 2),
                "rule 2 fired for the DYNAMIC cursor")

        # Rule 7 gate: the same query with the default 7 day window runs about
        # 157 times a day, and costs almost nothing, so it should not fire.
        out, combined, found7 = pp_run(server, password, [ids["r7"]])
        R.check(G, "rule 7 stays quiet under 1,000 executions a day",
                found7 is not None and not pp_has(found7, ids["r7"], 7),
                "rule 7 fired on the default window")

        # Rule 14: compat gate. Fires for the plan compiled at 140 while the
        # database is at 140; silent for the plan compiled at the default
        # level when that is 150 or higher.
        _sqlcmd(server, password,
                "ALTER DATABASE %s SET COMPATIBILITY_LEVEL = 140;" % PP_DB)
        out, combined, found14 = pp_run(server, password, [ids["r14old"]])
        R.check(G, "rule 14 (table variable) fires for a plan compiled below compat 150",
                pp_has(found14, ids["r14old"], 14)
                and all(f["rule_name"] == "table variable" for f in found14
                        if f["rule_id"] == "14"),
                "no rule 14 row")
        _sqlcmd(server, password,
                "ALTER DATABASE %s SET COMPATIBILITY_LEVEL = %d;"
                % (PP_DB, default_compat))
        if default_compat >= 150 and "r14new" in ids:
            out, combined, found14 = pp_run(server, password, [ids["r14new"]])
            R.check(G, "rule 14 stays quiet at compat 150 and up",
                    found14 is not None and not pp_has(found14, ids["r14new"], 14),
                    "rule 14 fired for a plan compiled at compat %d" % default_compat)

        # Rule 0: a plan too deeply nested to convert
        if True:
            out, combined, found0 = pp_run(server, password, [ids["r0"]])
            R.check(G, "rule 0 (plan not checked) fires for a plan too deep to convert",
                    pp_has(found0, ids["r0"], 0)
                    and all(f["rule_name"] == "plan not checked" for f in found0
                            if f["rule_id"] == "0"),
                    "no rule 0 row")

        # Off by default: no findings result set, and nothing else changes
        out, combined = run_qs(server, password,
                               ", @plan_parsing = 0, @top = 1000, "
                               "@include_query_ids = '%s'" % ids["r4"],
                               database_name=PP_DB)
        R.check(G, "@plan_parsing = 0 returns no findings result set",
                not pp_sql_errors(combined) and completed(out)
                and "rule_id" not in out and "node_ids" not in out,
                "findings columns present or run failed")
        out, combined = run_qs(server, password,
                               ", @top = 1000, @include_query_ids = '%s'" % ids["r4"],
                               database_name=PP_DB)
        R.check(G, "default run (no @plan_parsing) returns no findings result set",
                not pp_sql_errors(combined) and completed(out)
                and "rule_id" not in out and "node_ids" not in out,
                "findings columns present or run failed")

        # @debug = 1 with @plan_parsing = 1 on the early exits (a database that
        # does not exist, a time zone that does not exist) goes to the debug dump
        # before the plan tables are filled; the dump must not fail on them.
        # (The empty table shows as its header: table_name, database_id, ..., obj_index.)
        # A database with Query Store off exits the same way, but the debug dump
        # for it stalls go-sqlcmd on an xml column, so it was run with pyodbc.
        for label, extra, dbname in (
                ("a database that does not exist", "", PP_DB + "_nope"),
                ("a time zone that does not exist", ", @timezone = N'No Such Zone'", PP_DB)):
            out, combined = run_qs(server, password,
                                   ", @plan_parsing = 1, @debug = 1" + extra,
                                   database_name=dbname)
            R.check(G, "@debug = 1 with @plan_parsing = 1 for %s dumps without Msg 208" % label,
                    "Msg 208" not in combined and "Invalid object name" not in combined
                    and re.search(r"table_name\s+database_id\s+plan_id\s+stmt_id\s+obj_schema\s+obj_table\s+obj_index", out),
                    combined.replace("\n", " ")[:160])

        # @workdays = 1: rule 7 counts executions per work day; the run has to finish cleanly
        out, combined = run_qs(server, password,
                               ", @plan_parsing = 1, @workdays = 1, @top = 5",
                               database_name=PP_DB, timeout=600)
        R.check(G, "@plan_parsing = 1 with @workdays = 1 runs cleanly",
                completed(out) and not pp_sql_errors(combined),
                combined.replace("\n", " ")[:160])

        # @troubleshoot_performance = 1 times the plan parsing steps like the
        # rest of the procedure: one current_query row per step
        out, combined = run_qs(server, password,
                               ", @plan_parsing = 1, @troubleshoot_performance = 1, @top = 5",
                               database_name=PP_DB, timeout=600)
        R.check(G, "@troubleshoot_performance = 1 covers the plan parsing steps",
                completed(out) and not pp_sql_errors(combined)
                and "plan parsing: shredding operators" in out
                and "plan parsing: running the rules" in out,
                combined.replace("\n", " ")[:160])

        # Rejected combinations: severity 11 error that names @plan_parsing,
        # and the run does not reach the footer.
        rejected = [
            ("@find_high_impact = 1", ", @find_high_impact = 1"),
            ("@find_parameter_sensitive = 1", ", @find_parameter_sensitive = 1"),
            ("regression mode", ", @regression_baseline_start_date = '2020-01-01'"),
            ("@log_to_table = 1", ", @log_to_table = 1, @log_database_name = '%s'" % PP_DB),
        ]
        for label, extra in rejected:
            out, combined = run_qs(server, password,
                                   ", @plan_parsing = 1" + extra,
                                   database_name=PP_DB)
            R.check(G, "@plan_parsing = 1 with %s is rejected" % label,
                    re.search(r"Level 11", combined) is not None
                    and "plan_parsing" in combined and not completed(out),
                    combined.replace("\n", " ")[:160])
    finally:
        _sqlcmd(server, password, CLEANUP_SQL.replace(TEST_DB, PP_DB))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--server", default="SQL2022")
    ap.add_argument("--password", default="L!nt0044")
    ap.add_argument("--only", choices=["multidb", "plan_parsing"],
                    help="run one group by itself (multidb: the MultiDb group, "
                         "plan_parsing: the PlanParsing group)")
    args = ap.parse_args()

    print("Running sp_QuickieStore assertion tests against %s..." % args.server)
    print()

    out, _ = _sqlcmd(args.server, args.password,
                     "SET NOCOUNT ON; SELECT CASE WHEN OBJECT_ID(N'dbo.sp_QuickieStore', N'P') "
                     "IS NULL THEN 'MISSING' ELSE 'PRESENT' END;")
    if "PRESENT" not in out:
        print("ERROR: dbo.sp_QuickieStore is not installed in master on %s."
              % args.server)
        print("Install sp_QuickieStore.sql before running this harness.")
        sys.exit(1)

    R = Results()
    if args.only == "plan_parsing":
        plan_parsing_tests(args.server, args.password, R)
        for item in R.items:
            print("  [%s] %s: %s  (%s)" % ("PASS" if item["passed"] else "FAIL",
                                           item["group"], item["name"], item["detail"]))
        print("Total: %d passed, %d failed" % (R.passed, R.failed))
        sys.exit(1 if R.failed else 0)
    if args.only == "multidb":
        try:
            multi_database_tests(args.server, args.password, R)
        finally:
            for db in MD_DBS:
                _sqlcmd(args.server, args.password, CLEANUP_SQL.replace(TEST_DB, db))
        for item in R.items:
            print("  [%s] %s: %s  (%s)" % ("PASS" if item["passed"] else "FAIL",
                                           item["group"], item["name"], item["detail"]))
        sys.exit(1 if R.failed else 0)
    try:
        # Slot A of the regression fixture runs first, so the other tests
        # put time between it and slot B.
        rm_state = regression_window_setup(args.server, args.password, R)
        build_ok = build_fixture(args.server, args.password, R)
        if build_ok:
            smoke_tests(args.server, args.password, R)
            sort_order_matrix(args.server, args.password, R)
            mode_matrix(args.server, args.password, R)
            filter_matrix(args.server, args.password, R)
            bidirectional_tests(args.server, args.password, R)
            case_sensitive_search_tests(args.server, args.password, R)
            hash_totals_tests(args.server, args.password, R)
            parameter_sensitive_tests(args.server, args.password, R)
            high_impact_tests(args.server, args.password, R)
        if rm_state:
            regression_window_tests(args.server, args.password, R, rm_state)
        # These create databases and run many procedure calls, so they go after
        # the regression window tests, which read plan cache data.
        if build_ok:
            multi_database_tests(args.server, args.password, R)
            id_list_tests(args.server, args.password, R)
        plan_parsing_tests(args.server, args.password, R)
    finally:
        out, err = _sqlcmd(args.server, args.password, CLEANUP_SQL + RM_CLEANUP_SQL)
        R.check("Fixture", "scratch databases dropped",
                not find_sql_errors(out + "\n" + err), "cleanup failed")

    for item in R.items:
        status = "PASS" if item["passed"] else "FAIL"
        detail = ("  (%s)" % item["detail"]) if item["detail"] and not item["passed"] else ""
        print("  [%s] %s: %s%s" % (status, item["group"], item["name"], detail))

    print()
    print("Results: %d passed, %d failed, %d total"
          % (R.passed, R.failed, R.passed + R.failed))

    if R.failed:
        print()
        print("FAILED TESTS:")
        for item in R.items:
            if not item["passed"]:
                print("  %s: %s  (%s)" % (item["group"], item["name"], item["detail"]))
        sys.exit(1)

    print("All tests passed!")


if __name__ == "__main__":
    main()
