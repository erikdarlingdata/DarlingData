"""
sp_QuickieStore assertion test harness
======================================
sp_QuickieStore is ~16,000 lines that assemble a large dynamic SQL statement
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
import math
import os
import re
import shlex
import subprocess
import sys

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


def _sqlcmd(server, password, sql, database="master", timeout=300):
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
        "-y", "200",     # truncate wide columns (plan XML) so rendering is fast
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


def run_qs(server, password, extra="", timeout=300, database_name=TEST_DB):
    """Run sp_QuickieStore against the scratch database, always naming it
    explicitly, and return (stdout, combined-for-error-scanning)."""
    sql = ("SET NOCOUNT ON; EXECUTE dbo.sp_QuickieStore "
           "@database_name = '%s'%s;" % (_esc(database_name), extra))
    out, err = _sqlcmd(server, password, sql, timeout=timeout)
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
    finally:
        _sqlcmd(server, password, CS_CLEANUP_SQL)


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
        rules = {"sum": sum, "avg": lambda v: sum(v) / len(v), "min": min, "max": max}
        bad = []
        for t in totals:
            key = (t.get("wait_category_desc"), t.get(period_col))
            rows = [r for r in by_query
                    if (r.get("wait_category_desc"), r.get(period_col)) == key]
            if not rows:
                bad.append("%s: no by-query rows" % (key,))
                continue
            for column, rule in (
                    ("total_query_wait_time_ms", "sum"),
                    ("total_query_duration_ms", "sum"),
                    ("avg_query_wait_time_ms", "avg"),
                    ("avg_query_duration_ms", "avg"),
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
        R.check(group, "wait stats total adds up, averages, and takes the min "
                "and max of the by-query rows", bool(totals) and not bad,
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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--server", default="SQL2022")
    ap.add_argument("--password", default="L!nt0044")
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
    try:
        # Slot A of the regression fixture runs first, so the other tests
        # put time between it and slot B.
        rm_state = regression_window_setup(args.server, args.password, R)
        if build_fixture(args.server, args.password, R):
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
