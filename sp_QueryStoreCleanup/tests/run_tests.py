"""
sp_QueryStoreCleanup assertion test harness
===========================================
sp_QueryStoreCleanup removes queries from Query Store. A bug here does not
return a wrong number on a screen: it removes the wrong queries, or refuses to
remove the right ones. So this harness builds Query Store scratch databases
with a known set of queries and asserts on what the procedure reports and
what it actually removes.

What it covers:
  - @help, and every parameter check (each bad value raises an error, and
    trimmed values are accepted).
  - Report mode counts on a duplicate fixture, for the default call, each
    @cleanup_targets value and each @dedupe_by value, plus the result set count.
  - Text search ignores case in a case-sensitive database (#882).
  - The procedure installed at every compat level the server supports runs
    the default call without Msg 8622, and Step 4 uses HASH JOIN (#867).
  - A forced plan is never removed.
  - A real removal removes exactly the listed query_ids and nothing else, in
    both @sort_direction orders.
  - A READ_ONLY Query Store: the error without @compact_tables, parameter
    checks with it (#886), and compaction.
  - Msg 12402 counts as skipped, not failed (#875), using a generated copy of
    the procedure that removes each query twice.
  - SQL Server 2022 and up: a parameter sensitive plan (PSP) parent and its
    variants. Report mode prints no NULL-aggregate warning (#883), and removal
    takes the variants before the parent with no Msg 12465.

The procedure is installed from the repo file (or --proc-file) into master and
into the qsc_tools_* databases, since CI installs from the Install-All bundle,
which leaves sp_QueryStoreCleanup out. Every database the harness creates is
named qsc_* and is dropped at the end.

Usage:
    python run_tests.py [--server SQL2025] [--password L!nt0044]
                        [--proc-file path/to/sp_QueryStoreCleanup.sql]

Exits 1 if any assertion fails.
"""

import argparse
import os
import re
import shlex
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_PROC_FILE = os.path.normpath(
    os.path.join(HERE, "..", "sp_QueryStoreCleanup.sql"))

DUPES_DB = "qsc_dupes"          # duplicate fixture, Latin1_General_100_CS_AS
PSP_DB = "qsc_psp"              # PSP parent and variants, 2022+ only
READONLY_DB = "qsc_readonly"    # Query Store in READ_ONLY
NOQS_DB = "qsc_noqs"            # Query Store off
TOOLS_DB = "qsc_tools_%d"       # procedure installed at one compat level
TOOLS_140 = TOOLS_DB % 140      # also home to the remove-twice copy
MISSING_DB = "qsc_missing_db"   # never created
ALL_COMPAT_LEVELS = range(100, 180, 10)
ALL_DBS = ([DUPES_DB, PSP_DB, READONLY_DB, NOQS_DB] +
           [TOOLS_DB % level for level in ALL_COMPAT_LEVELS])

PROC = "dbo.sp_QueryStoreCleanup"
TWICE_PROC = "dbo.sp_QueryStoreCleanup_twice"

# The duplicate fixture. Each group has one substring that identifies it in
# query_sql_text, and every statement carries a /* qsc_... */ comment so
# queries from anything else (a monitoring tool that runs in every database,
# for one) can be purged before the tests run.
#
#   S1, S2  system text (FROM sys.), 8 queries each, one query_hash and one
#           plan hash per group: duplicates by both.
#   X       system text, a single query: never a duplicate.
#   M       maintenance text ((@_msparam...), 4 queries: duplicates by both.
#   C1      custom marker, 4 queries: duplicates by both.
#   C1T     C1's statement with its own marker instead of the custom one,
#           1 query: same query_hash and plan hash as C1, never a text
#           target. With a text filter it must never be removed.
#   C2      custom marker, 2 queries with one query_hash but two plans
#           (a skewed literal): duplicates by query_hash only.
#   C3      custom marker, a single query.
#   U       no target text, 4 queries: duplicates, but never a text target.
#   T       its own marker, 2 queries, for the Msg 12402 test.
GROUP_KEYS = [
    ("S1", "sys.objects AS o"),
    ("S2", "sys.indexes AS i"),
    ("X", "sys.types AS t"),
    ("M", "@_msparam_0"),
    ("C1T", "qsc_hash_twin"),  # before C1: its text has C1's key too
    ("C1", "r.val, c = COUNT_BIG"),
    ("C2", "r.id, r.pad"),
    ("C3", "s = COUNT_BIG"),
    ("U", "o.val, c = COUNT_BIG"),
    ("T", "qsc_twice_marker"),
]
GROUP_SIZES = {"S1": 8, "S2": 8, "X": 1, "M": 4, "C1": 4, "C1T": 1,
               "C2": 2, "C3": 1, "U": 4, "T": 2}

CUSTOM_FILTER = "%qsc_custom_marker%"
TWICE_FILTER = "%qsc_twice_marker%"
PSP_FILTER = "%qsc_psp_rows%"

SEPARATOR = re.compile(r"^-+(\t-+)*$")
FOUND_REMOVE = re.compile(r"Found (\d+) queries to remove")
REMOVED_LINE = re.compile(r"Query \d+ of \d+: query_id (\d+) removed")
FINISHED = re.compile(r"Finished: (\d+) of (\d+) removed \((\d+) skipped, "
                      r"(\d+) PSP parents waiting on variants, (\d+) failed\)")
NULL_WARNING = "Null value is eliminated by an aggregate"


def _sqlcmd_prefix():
    """The sqlcmd binary plus any connection args, overridable via environment
    so one harness runs both locally and in CI. Locally SQLCMD_BIN defaults to
    'sqlcmd' on PATH and SQLCMD_CONN_ARGS is empty; CI sets SQLCMD_BIN to the
    go-based sqlcmd and SQLCMD_CONN_ARGS to '-C -N disable' -- trust the
    container's self-signed cert and disable encryption, which the modern Go
    TLS stack needs to connect to the SQL Server 2017 container."""
    return [os.environ.get("SQLCMD_BIN", "sqlcmd")] + shlex.split(
        os.environ.get("SQLCMD_CONN_ARGS", ""))


def _run(cmd, timeout):
    r = subprocess.run(cmd, capture_output=True, timeout=timeout)
    return ((r.stdout or b"").decode("utf-8", errors="replace"),
            (r.stderr or b"").decode("utf-8", errors="replace"))


def _sqlcmd(server, password, sql, database="master", timeout=300):
    """Run a batch and return (stdout, stderr) decoded as UTF-8.
    Tab-delimited, trimmed, unwrapped, so result sets parse by line."""
    return _run(_sqlcmd_prefix() + [
        "-S", server, "-U", "sa", "-P", password,
        "-d", database,
        "-W",            # trim trailing spaces
        "-w", "65535",   # do not wrap wide rows
        "-y", "400",     # cap wide columns; fixture texts are shorter
        "-s", "\t",      # tab delimiter
        "-Q", sql,
    ], timeout)


def _sqlcmd_file(server, password, path, database):
    """Run a script file (it has GO separators) in a database."""
    return _run(_sqlcmd_prefix() + [
        "-S", server, "-U", "sa", "-P", password,
        "-d", database, "-i", path,
    ], 300)


def _esc(s):
    """Escape a T-SQL single-quoted literal."""
    return s.replace("'", "''")


def find_sql_errors(text):
    """Severity 16+ errors from either stream. go-sqlcmd reports SQL errors on
    stdout, so both have to be checked. Msg 4060/911 ("Cannot open database")
    are only Level 11 but mean the batch never ran, so catch those too."""
    if not text:
        return []
    return re.findall(r"Msg (?:\d+, Level 1[6-9]|4060|911)[^\n]*", text)


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


def query(server, password, sql, database="master"):
    """Rows of the first result set of a batch, plus any errors."""
    out, err = _sqlcmd(server, password, "SET NOCOUNT ON; " + sql, database)
    sets = result_sets(out)
    return (sets[0][1] if sets else []), find_sql_errors(out + "\n" + err)


def run_qsc(server, password, database_name, extra="", proc=PROC,
            home="master"):
    """Run the procedure against one database, always naming it, and return
    (stdout, stdout + stderr for error scanning)."""
    sql = ("SET NOCOUNT ON; EXECUTE %s @database_name = N'%s'%s;"
           % (proc, _esc(database_name), extra))
    out, err = _sqlcmd(server, password, sql, database=home)
    return out, out + "\n" + err


def summary(stdout):
    """The report-mode summary row as a dict, or {} if there is none."""
    for header, rows in result_sets(stdout):
        if header and header[0] == "queries_to_remove" and rows:
            return dict(zip(header, rows[0]))
    return {}


def found_to_remove(stdout):
    m = FOUND_REMOVE.search(stdout)
    return int(m.group(1)) if m else None


def raised(text, needle):
    """True if the run raised a severity 16 error carrying this message."""
    return bool(find_sql_errors(text)) and needle in text


class Results:
    def __init__(self):
        self.items = []

    def check(self, group, name, condition, detail=""):
        self.items.append({"group": group, "name": name, "status":
                           "PASS" if condition else "FAIL", "detail": detail})

    def skip(self, group, name, detail):
        self.items.append({"group": group, "name": name, "status": "SKIP",
                           "detail": detail})

    def count(self, status):
        return sum(1 for r in self.items if r["status"] == status)


# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------

def drop_db_sql(db):
    return ("IF DB_ID(N'{db}') IS NOT NULL BEGIN "
            "ALTER DATABASE [{db}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; "
            "DROP DATABASE [{db}]; END;").format(db=db)


def create_db(server, password, db, collate=None, compat=None):
    """Create a scratch database with Query Store off, so that setup never
    lands in it (SQL Server 2022 and up turn Query Store on for new
    databases). A compat level change is its own batch: the same batch would
    not see it."""
    sql = ("SET NOCOUNT ON; " + drop_db_sql(db) +
           " CREATE DATABASE [%s]%s;" % (db, " COLLATE " + collate if collate else "") +
           " ALTER DATABASE [%s] SET RECOVERY SIMPLE;" % db +
           " ALTER DATABASE [%s] SET QUERY_STORE = OFF;" % db +
           " ALTER DATABASE [%s] SET AUTO_CREATE_STATISTICS OFF;" % db +
           " ALTER DATABASE [%s] SET AUTO_UPDATE_STATISTICS OFF;" % db)
    out, err = _sqlcmd(server, password, sql)
    errors = find_sql_errors(out + "\n" + err)
    if compat and not errors:
        out, err = _sqlcmd(server, password,
                           "ALTER DATABASE [%s] SET COMPATIBILITY_LEVEL = %d;"
                           % (db, compat))
        errors = find_sql_errors(out + "\n" + err)
    return errors


def query_store_on(server, password, db, state="READ_WRITE", options=
                   "OPERATION_MODE = READ_WRITE, QUERY_CAPTURE_MODE = ALL, "
                   "INTERVAL_LENGTH_MINUTES = 1"):
    """Set Query Store options and wait (up to ~30 seconds) for
    actual_state_desc to reach the state asked for: it starts asynchronously."""
    sql = """
SET NOCOUNT ON;
ALTER DATABASE [{db}] SET QUERY_STORE = ON ({options});
DECLARE @i integer = 0;
WHILE @i < 60
AND NOT EXISTS
(
    SELECT 1/0
    FROM [{db}].sys.database_query_store_options AS dqso
    WHERE dqso.actual_state_desc = N'{state}'
)
BEGIN
    WAITFOR DELAY '00:00:00.500';
    SET @i += 1;
END;
SELECT actual_state_desc = dqso.actual_state_desc
FROM [{db}].sys.database_query_store_options AS dqso;
""".format(db=db, options=options, state=state)
    out, err = _sqlcmd(server, password, sql)
    sets = result_sets(out)
    actual = sets[0][1][0][0] if sets and sets[0][1] else "?"
    return actual == state, actual, find_sql_errors(out + "\n" + err)


def freeze_and_purge(server, password, db, keep_like):
    """Stop capturing new queries, then remove every captured query whose
    text does not match keep_like. Anything else that ran in the database
    while capture was on (another tool's collector, for one) would change
    the counts."""
    sql = """
SET NOCOUNT ON;
ALTER DATABASE [{db}] SET QUERY_STORE (QUERY_CAPTURE_MODE = NONE);
DECLARE
    @query_id bigint,
    @c CURSOR;
SET @c =
    CURSOR LOCAL FAST_FORWARD
    FOR
    SELECT
        qsq.query_id
    FROM [{db}].sys.query_store_query AS qsq
    JOIN [{db}].sys.query_store_query_text AS qsqt
      ON qsqt.query_text_id = qsq.query_text_id
    WHERE qsqt.query_sql_text NOT LIKE N'{keep}';
OPEN @c;
FETCH NEXT FROM @c INTO @query_id;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXECUTE [{db}].sys.sp_query_store_remove_query
        @query_id = @query_id;
    FETCH NEXT FROM @c INTO @query_id;
END;
""".format(db=db, keep=_esc(keep_like))
    out, err = _sqlcmd(server, password, sql)
    return find_sql_errors(out + "\n" + err)


def fixture_queries(server, password, db=DUPES_DB):
    """{query_id: group} for every fixture query in the duplicate database."""
    rows, _ = query(server, password, """
SELECT
    qsq.query_id,
    query_sql_text = REPLACE(REPLACE(qsqt.query_sql_text, CHAR(9), N' '), CHAR(10), N' ')
FROM [{db}].sys.query_store_query AS qsq
JOIN [{db}].sys.query_store_query_text AS qsqt
  ON qsqt.query_text_id = qsq.query_text_id;""".format(db=db))
    groups = {}
    for row in rows:
        if len(row) < 2 or not row[0].isdigit():
            continue
        text = "\t".join(row[1:])
        for name, key in GROUP_KEYS:
            if key in text:
                groups[int(row[0])] = name
                break
        else:
            groups[int(row[0])] = "?"
    return groups


def query_ids(server, password, db):
    rows, _ = query(server, password,
                    "SELECT qsq.query_id FROM [%s].sys.query_store_query AS qsq;" % db)
    return {int(r[0]) for r in rows if r and r[0].isdigit()}


def dupes_workload():
    """One batch with every duplicate-fixture statement, literals spelled out
    so each is its own query. The joins and GROUP BYs keep simple
    parameterization from folding the literals away. Query Store only sees a
    query when it compiles, and it can report READ_WRITE a moment before it
    captures anything, so each attempt clears this database's plan cache
    first: a plan cached in that gap would otherwise never be captured."""
    s = ["SET NOCOUNT ON;", "ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;"]
    for i in range(1, 9):
        s.append("SELECT /* qsc_fixture */ c = COUNT_BIG(*) FROM sys.objects AS o "
                 "JOIN sys.columns AS c ON c.object_id = o.object_id "
                 "WHERE o.object_id = %d;" % i)
        s.append("SELECT /* qsc_fixture */ n = COUNT_BIG(*) FROM sys.indexes AS i "
                 "JOIN sys.partitions AS p ON p.object_id = i.object_id "
                 "AND p.index_id = i.index_id WHERE i.index_id = %d;" % i)
    s.append("SELECT /* qsc_fixture */ t = COUNT_BIG(*) FROM sys.types AS t "
             "JOIN sys.schemas AS s ON s.schema_id = t.schema_id;")
    for i in range(1, 5):
        s.append("EXECUTE sys.sp_executesql N'SELECT /* qsc_fixture */ c = COUNT_BIG(*) "
                 "FROM dbo.qsc_rows AS r JOIN dbo.qsc_other AS o ON o.id = r.id "
                 "WHERE r.id = @_msparam_0 AND o.val > %d;', "
                 "N'@_msparam_0 integer', @_msparam_0 = 1;" % i)
    for i in range(9001, 9005):
        s.append("SELECT /* qsc_custom_marker */ r.val, c = COUNT_BIG(*) "
                 "FROM dbo.qsc_rows AS r JOIN dbo.qsc_other AS o ON o.val = r.val "
                 "WHERE r.id = %d GROUP BY r.val;" % i)
    s.append("SELECT /* qsc_hash_twin */ r.val, c = COUNT_BIG(*) "
             "FROM dbo.qsc_rows AS r JOIN dbo.qsc_other AS o ON o.val = r.val "
             "WHERE r.id = 9005 GROUP BY r.val;")
    for v in (1, 9999):
        s.append("SELECT /* qsc_custom_marker */ r.id, r.pad FROM dbo.qsc_rows AS r "
                 "JOIN dbo.qsc_other AS o ON o.id = r.id WHERE r.val = %d;" % v)
    s.append("SELECT /* qsc_custom_marker */ s = COUNT_BIG(*) FROM dbo.qsc_rows AS r "
             "JOIN dbo.qsc_other AS o ON o.id = r.id;")
    for i in (10, 20, 30, 40):
        s.append("SELECT /* qsc_fixture */ o.val, c = COUNT_BIG(*) FROM dbo.qsc_other AS o "
                 "WHERE o.id < %d GROUP BY o.val;" % i)
    for v in (9990, 9991):
        s.append("SELECT /* qsc_twice_marker */ c = COUNT_BIG(*) FROM dbo.qsc_other AS o "
                 "JOIN dbo.qsc_rows AS r ON r.id = o.id WHERE o.val = %d;" % v)
    s.append("EXECUTE sys.sp_query_store_flush_db;")
    return "\n".join(s)


DUPES_TABLES_SQL = """
SET NOCOUNT ON;
CREATE TABLE dbo.qsc_rows (id integer NOT NULL PRIMARY KEY CLUSTERED, val integer NOT NULL, pad char(100) NOT NULL);
INSERT dbo.qsc_rows WITH (TABLOCK) (id, val, pad)
SELECT x.n, CASE WHEN x.n <= 9000 THEN 1 ELSE x.n END, 'x'
FROM
(
    SELECT TOP (10000)
        n = CONVERT(integer, ROW_NUMBER() OVER (ORDER BY 1/0))
    FROM sys.all_columns AS ac1
    CROSS JOIN sys.all_columns AS ac2
) AS x;
CREATE INDEX ix_val ON dbo.qsc_rows (val);
CREATE TABLE dbo.qsc_other (id integer NOT NULL PRIMARY KEY CLUSTERED, val integer NOT NULL);
INSERT dbo.qsc_other WITH (TABLOCK) (id, val) SELECT r.id, r.val FROM dbo.qsc_rows AS r;
"""


def build_dupes(server, password, R):
    errors = create_db(server, password, DUPES_DB, collate="Latin1_General_100_CS_AS")
    if not errors:
        out, err = _sqlcmd(server, password, DUPES_TABLES_SQL, DUPES_DB)
        errors = find_sql_errors(out + "\n" + err)
    if errors:
        R.check("Fixture", "duplicate database built", False, errors[0])
        return False
    ok, state, errors = query_store_on(server, password, DUPES_DB)
    if not ok:
        R.check("Fixture", "duplicate database Query Store READ_WRITE", False,
                "actual_state_desc = %s %s" % (state, errors[:1]))
        return False
    # Capture can lag: run the workload, flush, look, and go again if short.
    # Re-running is harmless, since the same text is the same query.
    groups = {}
    for _ in range(5):
        out, err = _sqlcmd(server, password, dupes_workload(), DUPES_DB)
        errors = find_sql_errors(out + "\n" + err)
        if errors:
            R.check("Fixture", "duplicate workload ran", False, errors[0])
            return False
        groups = fixture_queries(server, password)
        if sum(1 for g in groups.values() if g != "?") >= sum(GROUP_SIZES.values()):
            break
        time.sleep(2)
    errors = freeze_and_purge(server, password, DUPES_DB, "%/* qsc[_]%")
    groups = fixture_queries(server, password)
    sizes = {g: sum(1 for v in groups.values() if v == g) for g in GROUP_SIZES}
    ok = sizes == GROUP_SIZES and "?" not in groups.values() and not errors
    R.check("Fixture", "duplicate fixture captured: %d queries in %d groups"
            % (sum(GROUP_SIZES.values()), len(GROUP_SIZES)), ok,
            "got %s, unknown %d, %s" % (sizes, sum(1 for v in groups.values() if v == "?"),
                                        errors[:1]))
    return ok


def build_readonly(server, password, R):
    errors = create_db(server, password, READONLY_DB)
    if not errors:
        ok, state, errors = query_store_on(server, password, READONLY_DB)
        if ok:
            out, err = _sqlcmd(server, password,
                               "SET NOCOUNT ON; SELECT /* qsc_ro */ c = COUNT_BIG(*) "
                               "FROM sys.objects AS o JOIN sys.columns AS c "
                               "ON c.object_id = o.object_id; "
                               "EXECUTE sys.sp_query_store_flush_db;", READONLY_DB)
            errors = find_sql_errors(out + "\n" + err)
            ok, state, errors2 = query_store_on(
                server, password, READONLY_DB, state="READ_ONLY",
                options="OPERATION_MODE = READ_ONLY")
            errors = errors or errors2 or ([] if ok else ["state " + state])
        else:
            errors = errors or ["state " + state]
    R.check("Fixture", "READ_ONLY Query Store database built", not errors,
            errors[0] if errors else "")
    return not errors


def build_noqs(server, password, R):
    errors = create_db(server, password, NOQS_DB)
    R.check("Fixture", "Query Store off database built", not errors,
            errors[0] if errors else "")
    return not errors


def install(server, password, database, text, R, label):
    """Write the procedure text to a temp file and run it in a database."""
    fd, path = tempfile.mkstemp(suffix=".sql", prefix="qsc_install_")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        out, err = _sqlcmd_file(server, password, path, database)
    finally:
        os.remove(path)
    errors = find_sql_errors(out + "\n" + err)
    R.check("Install", label, not errors, errors[0] if errors else "")
    return not errors


def twice_copy(proc_text):
    """A copy of the procedure under another name whose removal calls
    sp_query_store_remove_query twice: the second call raises Msg 12402,
    the same thing that happens when another session removes the query
    between the existence check and the removal."""
    call = ("    EXECUTE ' + @database_name_quoted + N'.sys.sp_query_store_remove_query\n"
            "        @query_id = @query_id;\n")
    text = proc_text.replace("\r\n", "\n")
    if text.count(call) != 1:
        return None
    return text.replace(call, call + "\n" + call).replace(
        "sp_QueryStoreCleanup", "sp_QueryStoreCleanup_twice")


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

def help_tests(server, password, R):
    out, _ = _sqlcmd(server, password,
                     "SET NOCOUNT ON; EXECUTE dbo.sp_QueryStoreCleanup @help = 1;")
    R.check("Help", "@help = 1 runs cleanly", not find_sql_errors(out))
    R.check("Help", "@help = 1 returns the introduction",
            "sp_QueryStoreCleanup!" in out and len(result_sets(out)) >= 2)


def parameter_tests(server, password, R):
    G = "Parameters"
    cases = [
        ("bad @cleanup_targets", ", @cleanup_targets = 'bogus'",
         "No valid cleanup targets specified"),
        ("bad @dedupe_by", ", @dedupe_by = 'bogus'", "@dedupe_by must be"),
        ("@min_age_days = 0", ", @min_age_days = 0",
         "@min_age_days must be a positive integer"),
        ("@min_age_days = -1", ", @min_age_days = -1",
         "@min_age_days must be a positive integer"),
        ("bad @sort_direction", ", @sort_direction = 'sideways'",
         "@sort_direction must be ASC or DESC"),
        ("custom target with no filter", ", @cleanup_targets = 'custom'",
         "@custom_query_filter is required"),
        ("none + none would remove everything",
         ", @cleanup_targets = 'none', @dedupe_by = 'none'",
         "would remove every query in query store"),
    ]
    for name, extra, needle in cases:
        _, all_text = run_qsc(server, password, DUPES_DB, extra + ", @report_only = 1")
        R.check(G, name + " raises an error", raised(all_text, needle),
                "no '%s' error" % needle)

    _, all_text = run_qsc(server, password, MISSING_DB, ", @report_only = 1")
    R.check(G, "missing database raises an error",
            raised(all_text, "does not exist"), "no 'does not exist' error")

    _, all_text = run_qsc(server, password, NOQS_DB, ", @report_only = 1")
    R.check(G, "Query Store off raises an error",
            raised(all_text, "Query Store is not enabled"),
            "no 'not enabled' error")

    out, all_text = run_qsc(server, password, DUPES_DB,
                            ", @cleanup_targets = ' all ', @dedupe_by = ' all ', "
                            "@sort_direction = ' desc ', @report_only = 1")
    R.check(G, "trimmed ' all ' / ' desc ' are accepted",
            not find_sql_errors(all_text) and found_to_remove(out) == 20,
            "errors %s, found %s" % (find_sql_errors(all_text)[:1], found_to_remove(out)))


def report_tests(server, password, R):
    G = "Report counts"
    # (name, extra parameters, expected queries_to_remove, found-message checks)
    cases = [
        ("default call", "", 20),
        ("@cleanup_targets = 'system'", ", @cleanup_targets = 'system'", 16),
        ("@cleanup_targets = 'maintenance'", ", @cleanup_targets = 'maintenance'", 4),
        ("@cleanup_targets = 'maint,system'", ", @cleanup_targets = 'maint,system'", 20),
        ("@cleanup_targets = 'custom'",
         ", @cleanup_targets = 'custom', @custom_query_filter = N'%s'" % CUSTOM_FILTER, 6),
        ("'all' with a custom filter adds it",
         ", @custom_query_filter = N'%s'" % CUSTOM_FILTER, 26),
        ("custom, @dedupe_by = 'all'",
         ", @cleanup_targets = 'custom', @custom_query_filter = N'%s', @dedupe_by = 'all'"
         % CUSTOM_FILTER, 6),
        ("custom, @dedupe_by = 'query_hash'",
         ", @cleanup_targets = 'custom', @custom_query_filter = N'%s', "
         "@dedupe_by = 'query_hash'" % CUSTOM_FILTER, 6),
        ("custom, @dedupe_by = 'plan_hash' (C2 has two plans)",
         ", @cleanup_targets = 'custom', @custom_query_filter = N'%s', "
         "@dedupe_by = 'plan_hash'" % CUSTOM_FILTER, 4),
        ("custom, @dedupe_by = 'none' (singletons too)",
         ", @cleanup_targets = 'custom', @custom_query_filter = N'%s', "
         "@dedupe_by = 'none'" % CUSTOM_FILTER, 7),
        ("system, @dedupe_by = 'none' (singletons too)",
         ", @cleanup_targets = 'system', @dedupe_by = 'none'", 17),
        ("@cleanup_targets = 'none', @dedupe_by = 'query_hash' (every duplicate)",
         ", @cleanup_targets = 'none', @dedupe_by = 'query_hash'", 33),
    ]
    for name, extra, expected in cases:
        out, all_text = run_qsc(server, password, DUPES_DB, extra + ", @report_only = 1")
        errors = find_sql_errors(all_text)
        s = summary(out)
        got = s.get("queries_to_remove")
        R.check(G, "%s -> %d queries" % (name, expected),
                not errors and got == str(expected) and found_to_remove(out) == expected,
                "errors %s, summary %s, found %s" % (errors[:1], got, found_to_remove(out)))

    # Which dedupe steps run, by their messages
    base = (", @cleanup_targets = 'custom', @custom_query_filter = N'%s', "
            "@report_only = 1" % CUSTOM_FILTER)
    out, _ = run_qsc(server, password, DUPES_DB, base + ", @dedupe_by = 'all'")
    R.check(G, "@dedupe_by = 'all' runs both dedupe steps",
            "Found 2 duplicate query hashes" in out and "Found 1 duplicate plan hashes" in out)
    out, _ = run_qsc(server, password, DUPES_DB, base + ", @dedupe_by = 'query_hash'")
    R.check(G, "@dedupe_by = 'query_hash' runs only the query_hash step",
            "Found 2 duplicate query hashes" in out and "duplicate plan hashes" not in out)
    out, _ = run_qsc(server, password, DUPES_DB, base + ", @dedupe_by = 'plan_hash'")
    R.check(G, "@dedupe_by = 'plan_hash' runs only the plan_hash step",
            "Found 1 duplicate plan hashes" in out and "duplicate query hashes" not in out)

    # With a text filter, removal stays inside it: C1T shares C1's hashes but
    # not the custom marker, so it is never listed. With no text filter,
    # every copy of a duplicated hash is listed, C1T included.
    groups = fixture_queries(server, password)
    for name, extra, expected_groups in (
            ("custom, @dedupe_by = 'all'",
             ", @cleanup_targets = 'custom', @custom_query_filter = N'%s', "
             "@dedupe_by = 'all'" % CUSTOM_FILTER, ("C1", "C2")),
            ("custom, @dedupe_by = 'plan_hash'",
             ", @cleanup_targets = 'custom', @custom_query_filter = N'%s', "
             "@dedupe_by = 'plan_hash'" % CUSTOM_FILTER, ("C1",)),
            ("@cleanup_targets = 'none', @dedupe_by = 'query_hash'",
             ", @cleanup_targets = 'none', @dedupe_by = 'query_hash'",
             ("S1", "S2", "M", "C1", "C1T", "C2", "U", "T"))):
        out, all_text = run_qsc(server, password, DUPES_DB,
                                extra + ", @report_only = 1, @debug = 1")
        listed = debug_list(out)
        expected = {q for q, g in groups.items() if g in expected_groups}
        R.check(G, "%s lists exactly %s" % (name, " + ".join(expected_groups)),
                not find_sql_errors(all_text) and listed == expected,
                "listed %d, expected %d, extra groups %s, missing groups %s"
                % (len(listed), len(expected),
                   sorted({groups.get(q, "?") for q in listed - expected}),
                   sorted({groups.get(q, "?") for q in expected - listed})))

    out, all_text = run_qsc(server, password, DUPES_DB, ", @report_only = 1")
    sets = result_sets(out)
    groups = [s for s in sets if s[0] and s[0][0] == "query_hash"]
    R.check(G, "report returns 2 result sets", len(sets) == 2, "got %d" % len(sets))
    R.check(G, "groups result set has one row per query_hash (8, 8, 4)",
            groups and sorted(int(r[1]) for r in groups[0][1]) == [4, 8, 8],
            "got %s" % ([r[1] for r in groups[0][1]] if groups else None))
    s = summary(out)
    R.check(G, "summary counts hashes, texts and plans",
            s.get("query_hashes") == "3" and s.get("query_texts") == "20"
            and s.get("plans") == "20" and s.get("plan_hashes") == "3",
            "got %s" % s)

    out, all_text = run_qsc(server, password, DUPES_DB,
                            ", @report_only = 1, @compact_tables = 1")
    sets = result_sets(out)
    R.check(G, "report with @compact_tables = 1 returns 3 result sets",
            len(sets) == 3 and not find_sql_errors(all_text), "got %d" % len(sets))
    R.check(G, "report with @compact_tables = 1 only lists what it would compact",
            "Would compact" in out and "Compacting finished" not in out)

    out, all_text = run_qsc(server, password, DUPES_DB, ", @min_age_days = 1, @report_only = 1")
    R.check(G, "@min_age_days = 1 keeps queries that ran today",
            not find_sql_errors(all_text) and "No queries to remove." in out
            and found_to_remove(out) == 0, "found %s" % found_to_remove(out))


def case_tests(server, password, R):
    G = "Text case (#882)"
    for label, pattern in (("same case", CUSTOM_FILTER),
                           ("upper case", CUSTOM_FILTER.upper()),
                           ("mixed case", "%QSC_Custom_Marker%")):
        out, all_text = run_qsc(
            server, password, DUPES_DB,
            ", @cleanup_targets = 'custom', @custom_query_filter = N'%s', "
            "@report_only = 1" % pattern)
        R.check(G, "custom filter in %s matches in a CS_AS database" % label,
                not find_sql_errors(all_text) and found_to_remove(out) == 6,
                "found %s" % found_to_remove(out))


def debug_list(stdout):
    """The query_ids in the removal list that @debug = 1 returns."""
    for header, rows in result_sets(stdout):
        if header[:2] == ["query_id", "is_parent"]:
            return {int(r[0]) for r in rows}
    return set()


def step4_sql(stdout):
    """The Step 4 dynamic SQL printed by @debug = 1."""
    start = stdout.find("/* Step 4: Build removal list */")
    if start < 0:
        return ""
    ends = [e for e in (stdout.find("/* Step 4b", start), stdout.find("Found ", start))
            if e > 0]
    return stdout[start:min(ends) if ends else len(stdout)]


def compat_tests(server, password, R, major, proc_text):
    """Install the procedure at every compat level the server supports and
    run the default call from each. The dynamic SQL compiles in the
    procedure's own database, so that database's level is the one that
    counts. Step 4 used to put both dupe lists in one EXISTS, which fails
    with Msg 8622 under HASH JOIN below compat 150 (#867)."""
    G = "HASH JOIN at every compat level (#867)"
    for level in compat_levels(major):
        db = TOOLS_DB % level
        if level != 140:
            if create_db(server, password, db, compat=level):
                R.check(G, "compat %d: tools database created" % level, False,
                        "create failed")
                continue
            if not install(server, password, db, proc_text, R,
                           "into %s (compat %d)" % (db, level)):
                continue
        out, all_text = run_qsc(server, password, DUPES_DB,
                                ", @report_only = 1, @debug = 1", home=db)
        errors = find_sql_errors(all_text)
        R.check(G, "compat %d: default call raises no Msg 8622 or other error" % level,
                "Msg 8622" not in all_text and not errors, (errors or [""])[0])
        R.check(G, "compat %d: default call finds 20 queries" % level,
                found_to_remove(out) == 20, "found %s" % found_to_remove(out))
        sql = step4_sql(out)
        R.check(G, "compat %d: Step 4 uses HASH JOIN with both dupe lists" % level,
                "OPTION(RECOMPILE, HASH JOIN);" in sql
                and "#query_hash_dupes" in sql and "#plan_hash_dupes" in sql)


def compat_levels(major):
    """Compat levels the server supports: 100 up to its own (170 at most)."""
    return [level for level in ALL_COMPAT_LEVELS if level <= min(major, 17) * 10]


def forced_plan_and_removal_tests(server, password, R):
    G = "Removal"
    groups = fixture_queries(server, password)
    s1 = sorted(q for q, g in groups.items() if g == "S1")
    forced = s1[0]
    rows, errors = query(server, password, """
DECLARE @plan_id bigint =
(
    SELECT TOP (1) qsp.plan_id
    FROM [{db}].sys.query_store_plan AS qsp
    WHERE qsp.query_id = {q}
    ORDER BY qsp.plan_id
);
EXECUTE [{db}].sys.sp_query_store_force_plan
    @query_id = {q},
    @plan_id = @plan_id;
SELECT forced = COUNT_BIG(*)
FROM [{db}].sys.query_store_plan AS qsp
WHERE qsp.query_id = {q}
AND   qsp.is_forced_plan = 1;""".format(db=DUPES_DB, q=forced))
    R.check("Forced plan", "fixture: one S1 query has a forced plan",
            not errors and rows and rows[0][0] == "1", "%s %s" % (rows, errors[:1]))

    out, all_text = run_qsc(server, password, DUPES_DB, ", @report_only = 1, @debug = 1")
    listed = debug_list(out)
    expected = {q for q, g in groups.items() if g in ("S1", "S2", "M")} - {forced}
    R.check("Forced plan", "report leaves the forced query off the list (19 queries)",
            forced not in listed and found_to_remove(out) == 19,
            "found %s, forced listed: %s" % (found_to_remove(out), forced in listed))
    R.check(G, "debug list is the S1 + S2 + M queries, less the forced one",
            listed == expected, "listed %d, expected %d" % (len(listed), len(expected)))

    before = query_ids(server, password, DUPES_DB)
    out, all_text = run_qsc(server, password, DUPES_DB, "")
    after = query_ids(server, password, DUPES_DB)
    m = FINISHED.search(out)
    R.check(G, "default removal finishes 19 of 19, nothing skipped or failed",
            m is not None and m.groups() == ("19", "19", "0", "0", "0")
            and not find_sql_errors(all_text),
            m.group(0) if m else "no Finished line")
    R.check(G, "removed exactly the listed query_ids",
            before - after == listed, "removed %d, listed %d"
            % (len(before - after), len(listed)))
    R.check(G, "everything not listed is still there", after == before - listed)
    R.check("Forced plan", "the forced query survives a real removal", forced in after)
    ids = [int(x) for x in REMOVED_LINE.findall(out)]
    R.check(G, "@sort_direction = 'ASC' (default) removes in ascending order",
            ids == sorted(ids) and len(ids) == 19, "order %s" % ids[:5])

    before = after
    out, all_text = run_qsc(server, password, DUPES_DB,
                            ", @cleanup_targets = 'custom', @custom_query_filter = N'%s', "
                            "@sort_direction = 'DESC'" % CUSTOM_FILTER)
    after = query_ids(server, password, DUPES_DB)
    ids = [int(x) for x in REMOVED_LINE.findall(out)]
    custom = {q for q, g in groups.items() if g in ("C1", "C2")}
    R.check(G, "@sort_direction = 'DESC' removes in descending order",
            ids == sorted(ids, reverse=True) and len(ids) == 6
            and not find_sql_errors(all_text), "order %s" % ids)
    R.check(G, "DESC removed exactly the 6 custom duplicates",
            before - after == custom and after == before - custom,
            "removed %d" % len(before - after))


def msg12402_tests(server, password, R, proc_text):
    G = "Msg 12402 (#875)"
    text = twice_copy(proc_text)
    if text is None:
        R.check(G, "generate the remove-twice copy", False,
                "the sp_query_store_remove_query call is not where expected")
        return
    if not install(server, password, TOOLS_140, text, R,
                   "remove-twice copy into %s" % TOOLS_140):
        return
    groups = fixture_queries(server, password)
    twice = {q for q, g in groups.items() if g == "T"}
    out, all_text = run_qsc(server, password, DUPES_DB,
                            ", @cleanup_targets = 'custom', @custom_query_filter = N'%s', "
                            "@dedupe_by = 'none'" % TWICE_FILTER,
                            proc=TWICE_PROC, home=TOOLS_140)
    m = FINISHED.search(out)
    R.check(G, "a query gone before its removal counts as skipped, not failed",
            m is not None and m.groups() == ("0", "2", "2", "0", "0"),
            m.group(0) if m else "no Finished line %s" % find_sql_errors(all_text)[:1])
    R.check(G, "both queries are gone", not (twice & query_ids(server, password, DUPES_DB)))


def readonly_tests(server, password, R):
    G = "READ_ONLY (#886)"
    _, all_text = run_qsc(server, password, READONLY_DB, "")
    R.check(G, "without @compact_tables raises an error",
            raised(all_text, "READ_ONLY state"), "no READ_ONLY error")
    for name, extra, needle in (
            ("bad @sort_direction", ", @sort_direction = 'sideways'",
             "@sort_direction must be ASC or DESC"),
            ("bad @dedupe_by", ", @dedupe_by = 'bogus'", "@dedupe_by must be"),
            ("bad @cleanup_targets", ", @cleanup_targets = 'bogus'",
             "No valid cleanup targets specified"),
            ("@min_age_days = 0", ", @min_age_days = 0",
             "@min_age_days must be a positive integer")):
        _, all_text = run_qsc(server, password, READONLY_DB,
                              ", @compact_tables = 1" + extra)
        R.check(G, "@compact_tables = 1 with %s still raises an error" % name,
                raised(all_text, needle), "no '%s' error" % needle)

    out, all_text = run_qsc(server, password, READONLY_DB,
                            ", @compact_tables = 1, @report_only = 1")
    R.check(G, "@compact_tables = 1, report mode lists what it would compact",
            not find_sql_errors(all_text) and "Compacting its internal tables only" in out
            and "Would compact" in out and len(result_sets(out)) == 1,
            (find_sql_errors(all_text) or [""])[0])
    out, all_text = run_qsc(server, password, READONLY_DB, ", @compact_tables = 1")
    R.check(G, "@compact_tables = 1 compacts",
            not find_sql_errors(all_text) and "Compacting finished" in out
            and "failed" not in out,
            (find_sql_errors(all_text) or [""])[0])


PSP_TABLE_SQL = """
SET NOCOUNT ON;
CREATE TABLE dbo.qsc_psp_rows (id integer NOT NULL PRIMARY KEY CLUSTERED, val integer NOT NULL, pad char(200) NOT NULL);
INSERT dbo.qsc_psp_rows WITH (TABLOCK) (id, val, pad)
SELECT x.n, CASE WHEN x.n <= 1000000 THEN 1 ELSE x.n END, 'x'
FROM
(
    SELECT TOP (2000000)
        n = CONVERT(integer, ROW_NUMBER() OVER (ORDER BY 1/0))
    FROM sys.all_columns AS ac1
    CROSS JOIN sys.all_columns AS ac2
) AS x;
CREATE INDEX ix_val ON dbo.qsc_psp_rows (val);
UPDATE STATISTICS dbo.qsc_psp_rows WITH FULLSCAN;
"""

PSP_WORKLOAD_SQL = """
SET NOCOUNT ON;
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
DECLARE @sql nvarchar(200) = N'SELECT /* qsc_psp */ m = MAX(r.pad) FROM dbo.qsc_psp_rows AS r WHERE r.val = @v;';
EXECUTE sys.sp_executesql @sql, N'@v integer', @v = 1;
EXECUTE sys.sp_executesql @sql, N'@v integer', @v = 1500000;
EXECUTE sys.sp_executesql @sql, N'@v integer', @v = 1;
EXECUTE sys.sp_executesql @sql, N'@v integer', @v = 1500000;
EXECUTE sys.sp_query_store_flush_db;
"""


def psp_state(server, password):
    """(parents, variants) of the PSP fixture query."""
    rows, _ = query(server, password, """
SELECT
    parents = COUNT_BIG(DISTINCT qsqv.parent_query_id),
    variants = COUNT_BIG(DISTINCT qsqv.query_variant_query_id)
FROM [{db}].sys.query_store_query_variant AS qsqv;""".format(db=PSP_DB))
    if rows and len(rows[0]) == 2:
        return int(rows[0][0]), int(rows[0][1])
    return 0, 0


def psp_tests(server, password, R, major):
    G = "PSP (#883)"
    if major < 16:
        R.skip(G, "PSP parent and variants", "PSP optimization needs SQL Server 2022 or later")
        return
    errors = create_db(server, password, PSP_DB, compat=160)
    if not errors:
        out, err = _sqlcmd(server, password, PSP_TABLE_SQL, PSP_DB, timeout=600)
        errors = find_sql_errors(out + "\n" + err)
    if not errors:
        ok, state, errors = query_store_on(server, password, PSP_DB)
        errors = errors or ([] if ok else ["state " + state])
    parents = variants = 0
    if not errors:
        for _ in range(3):
            out, err = _sqlcmd(server, password, PSP_WORKLOAD_SQL, PSP_DB)
            errors = find_sql_errors(out + "\n" + err)
            parents, variants = psp_state(server, password)
            if errors or (parents == 1 and variants >= 1):
                break
            time.sleep(2)
        errors = errors or freeze_and_purge(server, password, PSP_DB, "%qsc[_]psp[_]rows%")
    R.check(G, "fixture: one PSP parent with variants",
            not errors and parents == 1 and variants >= 1,
            "parents %d, variants %d %s" % (parents, variants, errors[:1]))
    if errors or parents != 1 or variants < 1:
        return
    expected = 1 + variants

    extra = ", @cleanup_targets = 'custom', @custom_query_filter = N'%s'" % PSP_FILTER
    out, all_text = run_qsc(server, password, PSP_DB, extra + ", @report_only = 1")
    s = summary(out)
    R.check(G, "report lists the parent and its %d variants" % variants,
            not find_sql_errors(all_text) and s.get("queries_to_remove") == str(expected)
            and s.get("psp_parents_to_remove") == "1",
            "summary %s" % s)
    R.check(G, "report prints no NULL-aggregate warning", NULL_WARNING not in all_text,
            "warning printed")

    minmax, _ = query(server, password, """
SELECT
    oldest = MIN(qsq.last_execution_time),
    newest = MAX(qsq.last_execution_time)
FROM [{db}].sys.query_store_query AS qsq
WHERE qsq.last_execution_time IS NOT NULL;""".format(db=PSP_DB))
    oldest_actual, newest_actual = (minmax[0][0], minmax[0][1]) if minmax else (None, None)
    R.check(G, "summary oldest/newest last_execution match the catalog exactly",
            s.get("oldest_last_execution") == oldest_actual
            and s.get("newest_last_execution") == newest_actual,
            "summary oldest %s, newest %s; catalog oldest %s, newest %s"
            % (s.get("oldest_last_execution"), s.get("newest_last_execution"),
               oldest_actual, newest_actual))

    rows, _ = query(server, password, """
SELECT qsqv.parent_query_id
FROM [{db}].sys.query_store_query_variant AS qsqv;""".format(db=PSP_DB))
    parent = int(rows[0][0]) if rows else -1
    out, all_text = run_qsc(server, password, PSP_DB, extra)
    m = FINISHED.search(out)
    ids = [int(x) for x in REMOVED_LINE.findall(out)]
    R.check(G, "removal finishes %d of %d with nothing skipped or failed"
            % (expected, expected),
            m is not None and m.groups() == (str(expected), str(expected), "0", "0", "0")
            and "12465" not in all_text and not find_sql_errors(all_text),
            m.group(0) if m else "no Finished line %s" % find_sql_errors(all_text)[:1])
    R.check(G, "variants go before the parent",
            len(ids) == expected and ids[-1] == parent, "order %s, parent %d" % (ids, parent))
    R.check(G, "Query Store has no PSP queries left",
            psp_state(server, password) == (0, 0)
            and not query_ids(server, password, PSP_DB))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--server", default="SQL2025")
    ap.add_argument("--password", default="L!nt0044")
    ap.add_argument("--proc-file", default=DEFAULT_PROC_FILE,
                    help="procedure script to test (default: the repo copy)")
    args = ap.parse_args()
    server, password = args.server, args.password
    started = time.time()

    with open(args.proc_file, encoding="utf-8-sig") as f:
        proc_text = f.read()

    print("Running sp_QueryStoreCleanup assertion tests against %s..." % server)
    print("Procedure: %s" % args.proc_file)
    print()

    rows, _ = query(server, password,
                    "SELECT major = CONVERT(integer, SERVERPROPERTY('ProductMajorVersion'));")
    major = int(rows[0][0]) if rows and rows[0][0].isdigit() else 0

    R = Results()
    try:
        if not install(server, password, "master", proc_text, R, "into master"):
            raise SystemExit(1)
        help_tests(server, password, R)

        tools_ok = not create_db(server, password, TOOLS_140, compat=140)
        tools_ok = tools_ok and install(server, password, TOOLS_140, proc_text, R,
                                        "into %s (compat 140)" % TOOLS_140)

        if build_dupes(server, password, R) and build_noqs(server, password, R):
            parameter_tests(server, password, R)
            report_tests(server, password, R)
            case_tests(server, password, R)
            if tools_ok:
                compat_tests(server, password, R, major, proc_text)
            forced_plan_and_removal_tests(server, password, R)
            if tools_ok:
                msg12402_tests(server, password, R, proc_text)
        if build_readonly(server, password, R):
            readonly_tests(server, password, R)
        psp_tests(server, password, R, major)
    finally:
        out, err = _sqlcmd(server, password,
                           "SET NOCOUNT ON; " + " ".join(drop_db_sql(db) for db in ALL_DBS))
        R.check("Fixture", "scratch databases dropped",
                not find_sql_errors(out + "\n" + err), "cleanup failed")

    for item in R.items:
        detail = ("  (%s)" % item["detail"]) if item["detail"] and item["status"] != "PASS" else ""
        print("  [%s] %s: %s%s" % (item["status"], item["group"], item["name"], detail))

    print()
    print("Total: %d passed, %d failed, %d skipped (%.0f s)"
          % (R.count("PASS"), R.count("FAIL"), R.count("SKIP"), time.time() - started))

    if R.count("FAIL"):
        print()
        print("FAILED TESTS:")
        for item in R.items:
            if item["status"] == "FAIL":
                print("  %s: %s  (%s)" % (item["group"], item["name"], item["detail"]))
        sys.exit(1)

    print("All tests passed!")


if __name__ == "__main__":
    main()
