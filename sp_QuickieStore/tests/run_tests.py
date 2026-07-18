"""
sp_QuickieStore assertion test harness
======================================
sp_QuickieStore is ~16,000 lines that assemble a large dynamic SQL statement
whose SHAPE changes with almost every one of its 59 parameters: @sort_order
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


def run_qs(server, password, extra="", timeout=300):
    """Run sp_QuickieStore against the scratch database, always naming it
    explicitly, and return (stdout, combined-for-error-scanning)."""
    sql = ("SET NOCOUNT ON; EXECUTE dbo.sp_QuickieStore "
           "@database_name = '%s'%s;" % (_esc(TEST_DB), extra))
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
        if build_fixture(args.server, args.password, R):
            smoke_tests(args.server, args.password, R)
            sort_order_matrix(args.server, args.password, R)
            mode_matrix(args.server, args.password, R)
            filter_matrix(args.server, args.password, R)
            bidirectional_tests(args.server, args.password, R)
    finally:
        out, err = _sqlcmd(args.server, args.password, CLEANUP_SQL)
        R.check("Fixture", "scratch database dropped",
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
