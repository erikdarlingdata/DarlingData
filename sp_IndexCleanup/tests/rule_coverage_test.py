"""
sp_IndexCleanup Rule Coverage Tests
===================================
Covers two things nothing else in this directory tests: Rule 1 (unused index
detection) and the @min_reads / @min_writes index-level screen.

Builds its own synthetic fixture in the Crap database -- three ~20,000 row tables,
scoped with @table_name so each procedure run is fast. It deliberately does not
touch StackOverflow2013: fixture_cases_test.py already spends two minutes there,
and this one is meant to be quick. Drops its tables afterward.

(a) Rule 1, unused index detection.

    The procedure auto-enables @dedupe_only when server uptime is <= 7 days, and
    Rule 1 only runs when @dedupe_only = 0. So on a recently restarted instance
    Rule 1 cannot be reached through the public interface at all. That is correct,
    deliberate behavior: usage data on a freshly started instance is worthless,
    and recommending index drops from it would be actively harmful.

    Rather than skip, this asserts whichever statement is true on the instance in
    front of it:

      - uptime > 7 days:  the never-read index gets a DISABLE with a consolidation
                          rule of 'Unused Index'.
      - uptime <= 7 days: the GUARD holds. @dedupe_only was auto-enabled (proven
                          by the procedure's own @debug message) and no 'Unused
                          Index' rows appear anywhere.

    The guard branch is a real assertion, not a silent pass. It is kept honest by
    positive controls: the harness first proves the index was analyzed (it appears
    in the output) and that it genuinely has zero reads, so the absence of an
    'Unused Index' row is the guard doing its job rather than the index being
    invisible for some unrelated reason.

(b) The @min_reads / @min_writes index-level screen.

    The screen gates DEDUPE ONLY. It must not take compression recommendations
    with it -- an index can be far too cold to bother deduping and still be worth
    compressing. It is also an OR: an index clears by meeting EITHER floor.

    The write-floor cases run against a table whose clustered PK carries reads
    (an UPDATE seeks it) while ix_w1/ix_w2 have none. The table therefore clears
    the object-level filter on its own, which means these cases exercise the
    index-level screen specifically rather than the coarser per-table filter.

Usage:
    python rule_coverage_test.py [--server SQL2022] [--password "L!nt0044"]
"""

import os
import subprocess
import sys
import tempfile


TEST_DATABASE = "Crap"

# Rows that represent a dedupe action. A COMPRESSION SCRIPT row is not one.
DEDUPE_SCRIPT_TYPES = ("DISABLE SCRIPT", "MERGE SCRIPT", "DISABLE CONSTRAINT SCRIPT")

GUARD_MESSAGE = "Automatically enabling @dedupe_only mode"

SETUP_SQL = """
SET NOCOUNT ON;

DROP TABLE IF EXISTS dbo.ic_min_reads_test;
DROP TABLE IF EXISTS dbo.ic_min_writes_test;
DROP TABLE IF EXISTS dbo.ic_unused_test;
GO

/*
ic_min_reads_test: ix_hot (~200 reads), ix_warm (~5 reads, a key duplicate of
ix_hot with different includes so the two pair), clustered PK (0 reads).
*/
CREATE TABLE
    dbo.ic_min_reads_test
(
    id integer NOT NULL,
    col_a integer NOT NULL,
    col_b integer NOT NULL,
    col_c integer NOT NULL,
    filler varchar(100) NOT NULL,
    CONSTRAINT pk_ic_min_reads_test PRIMARY KEY CLUSTERED (id)
);

/*
ic_min_writes_test: ix_w1 / ix_w2 are a key-duplicate pair that is never read but
is written to. The clustered PK picks up reads from the UPDATE seeks, which lets
the table clear the object-level filter so the index-level screen is what gets
tested.
*/
CREATE TABLE
    dbo.ic_min_writes_test
(
    id integer NOT NULL,
    col_a integer NOT NULL,
    col_b integer NOT NULL,
    col_c integer NOT NULL,
    filler varchar(100) NOT NULL,
    CONSTRAINT pk_ic_min_writes_test PRIMARY KEY CLUSTERED (id)
);

/*
ic_unused_test: ix_never_read has distinct keys so no dedupe rule can fire on it.
The only thing that can flag it is Rule 1.
*/
CREATE TABLE
    dbo.ic_unused_test
(
    id integer NOT NULL,
    col_a integer NOT NULL,
    col_b integer NOT NULL,
    filler varchar(100) NOT NULL,
    CONSTRAINT pk_ic_unused_test PRIMARY KEY CLUSTERED (id)
);
GO

INSERT INTO
    dbo.ic_min_reads_test
(
    id,
    col_a,
    col_b,
    col_c,
    filler
)
SELECT TOP (20000)
    id = ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),
    col_a = ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) % 500,
    col_b = ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) % 100,
    col_c = ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) % 250,
    filler = REPLICATE('x', 100)
FROM sys.all_columns AS ac1
CROSS JOIN sys.all_columns AS ac2
OPTION(MAXDOP 1);

INSERT INTO
    dbo.ic_min_writes_test
(
    id,
    col_a,
    col_b,
    col_c,
    filler
)
SELECT TOP (20000)
    id = ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),
    col_a = ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) % 500,
    col_b = ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) % 100,
    col_c = ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) % 250,
    filler = REPLICATE('x', 100)
FROM sys.all_columns AS ac1
CROSS JOIN sys.all_columns AS ac2
OPTION(MAXDOP 1);

INSERT INTO
    dbo.ic_unused_test
(
    id,
    col_a,
    col_b,
    filler
)
SELECT TOP (20000)
    id = ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),
    col_a = ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) % 500,
    col_b = ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) % 100,
    filler = REPLICATE('x', 100)
FROM sys.all_columns AS ac1
CROSS JOIN sys.all_columns AS ac2
OPTION(MAXDOP 1);
GO

CREATE INDEX ix_hot ON dbo.ic_min_reads_test (col_a) INCLUDE (col_b);
CREATE INDEX ix_warm ON dbo.ic_min_reads_test (col_a) INCLUDE (col_c);

CREATE INDEX ix_w1 ON dbo.ic_min_writes_test (col_a) INCLUDE (col_b);
CREATE INDEX ix_w2 ON dbo.ic_min_writes_test (col_a) INCLUDE (col_c);

CREATE INDEX ix_never_read ON dbo.ic_unused_test (col_a);
GO

/*
Drive reads with forced index hints, bounded: ix_hot ~200, ix_warm ~5, PK 0.
Nothing reads ic_unused_test at all.
*/
DECLARE
    @c bigint,
    @i integer = 0;

WHILE @i < 200
BEGIN
    SELECT @c = COUNT_BIG(*) FROM dbo.ic_min_reads_test AS t WITH (INDEX = ix_hot) WHERE t.col_a = @i % 500 OPTION(MAXDOP 1);
    SELECT @i += 1;
END;

SELECT @i = 0;

WHILE @i < 5
BEGIN
    SELECT @c = COUNT_BIG(*) FROM dbo.ic_min_reads_test AS t WITH (INDEX = ix_warm) WHERE t.col_a = @i % 500 OPTION(MAXDOP 1);
    SELECT @i += 1;
END;
GO

/*
Drive writes on ic_min_writes_test. Updating col_a maintains both ix_w1 and ix_w2
(it is the key of both), so both collect writes while collecting no reads.
*/
DECLARE
    @i integer = 0;

WHILE @i < 60
BEGIN
    UPDATE
        t
    SET
        t.col_a = (t.col_a + 1) % 500
    FROM dbo.ic_min_writes_test AS t
    WHERE t.id = @i
    OPTION(MAXDOP 1);

    SELECT @i += 1;
END;
GO
"""

CLEANUP_SQL = """
SET NOCOUNT ON;
DROP TABLE IF EXISTS dbo.ic_min_reads_test;
DROP TABLE IF EXISTS dbo.ic_min_writes_test;
DROP TABLE IF EXISTS dbo.ic_unused_test;
"""


def run_sqlcmd(server, password, input_file=None, query=None,
               database=TEST_DATABASE, timeout=600):
    """Run SQL from a file or a query string and capture output."""
    cmd = [
        "sqlcmd", "-S", server, "-U", "sa", "-P", password,
        "-d", database,
        "-W",  # trim trailing spaces
        "-s", "\t",  # tab delimiter
    ]
    if input_file is not None:
        cmd += ["-i", input_file]
    else:
        cmd += ["-Q", query]

    result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    return result.stdout, result.stderr


def run_sql_script(server, password, sql, timeout=600):
    """Run a multi-batch script (one containing GO) through a temp file."""
    path = None
    try:
        handle, path = tempfile.mkstemp(suffix=".sql", prefix="ic_rule_cov_")
        with os.fdopen(handle, "w") as f:
            f.write(sql)
        return run_sqlcmd(server, password, input_file=path, timeout=timeout)
    finally:
        if path and os.path.exists(path):
            os.remove(path)


def parse_output(stdout):
    """
    Parse sp_IndexCleanup tab-delimited output into rows.

    Bounded to the script result set: the procedure emits several result sets and
    the later ones share nothing but a tab delimiter, so parsing stops at the
    blank line that ends this one. That bound matters here because most of the
    assertions below are assertions of absence.

    Column order, verified empirically against the running procedure:
        script_type, additional_info, database_name, schema_name, table_name,
        index_name, consolidation_rule, target_index_name, superseded_info,
        index_size_gb, index_rows, index_reads, index_writes,
        original_index_definition, script
    """
    rows = []
    lines = stdout.split("\n")
    headers = None
    started = False

    for line in lines:
        if headers is None:
            if "script_type" in line and "index_name" in line:
                headers = [h.strip() for h in line.split("\t")]
            continue

        if line.startswith("---"):
            continue

        if not line.strip():
            if started:
                break
            continue

        cols = [c.strip() for c in line.split("\t")]
        if len(cols) >= len(headers):
            rows.append(dict(zip(headers, cols)))
            started = True

    return rows


def find_rows(rows, **filters):
    """Find rows matching all filter criteria."""
    matches = []
    for row in rows:
        match = True
        for key, value in filters.items():
            if key.endswith("__like"):
                col = key[:-6]
                if col not in row or value.lower() not in row[col].lower():
                    match = False
                    break
            elif key.endswith("__in"):
                col = key[:-4]
                if col not in row or row[col] not in value:
                    match = False
                    break
            else:
                if key not in row or row[key] != value:
                    match = False
                    break
        if match:
            matches.append(row)
    return matches


def dedupe_rows(rows, index_name):
    """Every dedupe-action row for an index. Compression rows are not included."""
    return [
        r for r in rows
        if r.get("index_name") == index_name
        and r.get("script_type") in DEDUPE_SCRIPT_TYPES
    ]


def get_uptime_days(server, password):
    """Server uptime in days, as the procedure itself computes it."""
    stdout, _ = run_sqlcmd(
        server, password, database="master",
        query="SET NOCOUNT ON; SELECT uptime = DATEDIFF(DAY, osi.sqlserver_start_time,"
              " SYSDATETIME()) FROM sys.dm_os_sys_info AS osi;",
    )
    for line in stdout.split("\n"):
        line = line.strip()
        if line.isdigit():
            return int(line)
    raise RuntimeError("Could not read server uptime:\n%s" % stdout)


def run_proc(server, password, table_name, extra="", debug=False):
    """Run sp_IndexCleanup scoped to one table and return (rows, stdout)."""
    query = (
        "EXECUTE master.dbo.sp_IndexCleanup "
        "@database_name = '%s', @schema_name = 'dbo', @table_name = '%s'%s%s;"
        % (TEST_DATABASE, table_name, extra, ", @debug = 1" if debug else "")
    )
    stdout, _ = run_sqlcmd(server, password, database="master", query=query)
    return parse_output(stdout), stdout


def run_tests(server, password, uptime_days):
    """Run all assertions and return results."""
    results = []

    def assert_test(group, name, condition, detail=""):
        results.append({
            "group": group,
            "name": name,
            "passed": condition,
            "detail": detail,
        })

    # ---- Group A: Rule 1, unused index detection ----

    rows, _ = run_proc(server, password, "ic_unused_test")
    unused_rows = [
        r for r in rows
        if "unused index" in (r.get("consolidation_rule") or "").lower()
    ]

    if uptime_days > 7:
        # Rule 1 is reachable: @dedupe_only defaults to 0 and stays there.
        matches = find_rows(rows, index_name="ix_never_read",
                            script_type="DISABLE SCRIPT",
                            consolidation_rule__like="Unused Index")
        assert_test("A-Rule1", "ix_never_read disabled as Unused Index",
                    len(matches) == 1,
                    "found %d (uptime %d days, Rule 1 reachable)"
                    % (len(matches), uptime_days))
    else:
        # Rule 1 is unreachable by design. Assert the guard instead.
        #
        # Positive controls first: without them "no Unused Index rows" would be
        # true for any number of uninteresting reasons.
        present = find_rows(rows, index_name="ix_never_read")
        assert_test("A-Guard", "positive control: ix_never_read was analyzed",
                    len(present) >= 1,
                    "found %d rows for the index (%s)"
                    % (len(present), [p["script_type"] for p in present]))

        reads = present[0].get("index_reads") if present else None
        assert_test("A-Guard", "positive control: ix_never_read has zero reads",
                    reads == "0", "index_reads=%s" % reads)

        # The procedure says so itself when asked with @debug = 1.
        _, debug_stdout = run_proc(server, password, "ic_unused_test", debug=True)
        assert_test("A-Guard", "@dedupe_only auto-enabled by the uptime guard",
                    GUARD_MESSAGE in debug_stdout,
                    "procedure reported the auto-enable"
                    if GUARD_MESSAGE in debug_stdout
                    else "guard message never appeared with @debug = 1")

        # Therefore Rule 1 never ran, and nothing is recommended as unused.
        assert_test("A-Guard", "no Unused Index rows while the guard is active",
                    len(unused_rows) == 0,
                    "found %d unused rows (expected 0)" % len(unused_rows))

    # ---- Group B: @min_reads / @min_writes index-level screen ----

    # B1: no floor. ix_hot and ix_warm are key duplicates and should pair up.
    rows, _ = run_proc(server, password, "ic_min_reads_test", extra=", @min_reads = 0")

    hot = dedupe_rows(rows, "ix_hot")
    warm = dedupe_rows(rows, "ix_warm")
    assert_test("B-MinReads", "@min_reads = 0: ix_hot/ix_warm get a dedupe recommendation",
                len(hot) >= 1 and len(warm) >= 1,
                "ix_hot=%s ix_warm=%s"
                % ([h["script_type"] for h in hot], [w["script_type"] for w in warm]))

    # B2: floor above ix_warm's 5 reads. ix_warm is below it, so the pair cannot
    # be deduped -- both sides must clear the floor on their own.
    rows, _ = run_proc(server, password, "ic_min_reads_test", extra=", @min_reads = 100")

    warm = dedupe_rows(rows, "ix_warm")
    assert_test("B-MinReads", "@min_reads = 100: ix_warm not deduped (5 reads, below floor)",
                len(warm) == 0,
                "found %d (%s)" % (len(warm), [w["script_type"] for w in warm]))

    # And the half that actually matters: the screen gates dedupe ONLY. Losing a
    # compression recommendation to a reads floor would be a bug -- compression
    # eligibility has nothing to do with how often an index is read.
    matches = find_rows(rows, index_name="ix_warm", script_type="COMPRESSION SCRIPT")
    assert_test("B-MinReads", "@min_reads = 100: ix_warm still gets COMPRESSION SCRIPT",
                len(matches) == 1, "found %d" % len(matches))

    matches = find_rows(rows, index_name="pk_ic_min_reads_test",
                        script_type="COMPRESSION SCRIPT")
    assert_test("B-MinReads", "@min_reads = 100: PK still gets COMPRESSION SCRIPT",
                len(matches) == 1, "found %d" % len(matches))

    # B3: write floor only. ix_w1/ix_w2 have 60 writes and zero reads, so they
    # clear on the write side alone.
    rows, _ = run_proc(server, password, "ic_min_writes_test", extra=", @min_writes = 50")

    w1 = dedupe_rows(rows, "ix_w1")
    w2 = dedupe_rows(rows, "ix_w2")
    assert_test("B-MinWrites", "@min_writes = 50, no reads floor: write-only pair still dedupes",
                len(w1) >= 1 and len(w2) >= 1,
                "ix_w1=%s ix_w2=%s"
                % ([w["script_type"] for w in w1], [w["script_type"] for w in w2]))

    # B4: the same pair against a reads floor it cannot meet. Together with B3
    # this is what makes the floors an OR rather than an AND: identical indexes,
    # identical usage, deduped under the write floor and not under the read floor.
    rows, _ = run_proc(server, password, "ic_min_writes_test", extra=", @min_reads = 50")

    w1 = dedupe_rows(rows, "ix_w1")
    w2 = dedupe_rows(rows, "ix_w2")
    assert_test("B-MinWrites", "@min_reads = 50 alone: same pair not deduped (0 reads)",
                len(w1) == 0 and len(w2) == 0,
                "ix_w1=%s ix_w2=%s"
                % ([w["script_type"] for w in w1], [w["script_type"] for w in w2]))

    # Compression survives this screen too.
    matches = find_rows(rows, index_name="ix_w1", script_type="COMPRESSION SCRIPT")
    assert_test("B-MinWrites", "@min_reads = 50 alone: ix_w1 still gets COMPRESSION SCRIPT",
                len(matches) == 1, "found %d" % len(matches))

    return results


def main():
    server = "SQL2022"
    password = "L!nt0044"

    # Parse args
    args = sys.argv[1:]
    for i, arg in enumerate(args):
        if arg == "--server" and i + 1 < len(args):
            server = args[i + 1]
        elif arg == "--password" and i + 1 < len(args):
            password = args[i + 1]

    print("Running rule coverage tests against %s..." % server)
    print()

    uptime_days = get_uptime_days(server, password)
    print("Server uptime: %d days" % uptime_days)

    if uptime_days > 7:
        print("Uptime is over 7 days, so @dedupe_only stays off and Rule 1 is")
        print("reachable. Asserting that the never-read index is flagged unused.")
    else:
        print("Uptime is 7 days or less, so sp_IndexCleanup auto-enables")
        print("@dedupe_only and Rule 1 cannot run. This is deliberate: usage data")
        print("from a freshly started instance is not worth acting on. Rule 1")
        print("itself is therefore not testable on this instance, so what gets")
        print("asserted instead is THE GUARD -- that @dedupe_only really was")
        print("auto-enabled and that no index is recommended as unused. This is a")
        print("verification, not a skip.")
    print()

    print("Building synthetic fixture in %s..." % TEST_DATABASE)
    stdout, stderr = run_sql_script(server, password, SETUP_SQL)

    if "Msg " in stdout or ("Msg " in stderr and "Level 16" in stderr):
        print("ERROR: SQL errors during fixture setup:")
        print(stdout[-2000:])
        print(stderr[:500] if stderr else "(empty stderr)")
        sys.exit(1)

    print()

    try:
        results = run_tests(server, password, uptime_days)
    finally:
        run_sql_script(server, password, CLEANUP_SQL)

    # Report
    passed = sum(1 for r in results if r["passed"])
    failed = sum(1 for r in results if not r["passed"])

    for r in results:
        status = "PASS" if r["passed"] else "FAIL"
        print("  [%s] %s: %s  (%s)" % (status, r["group"], r["name"], r["detail"]))

    print()
    print("Results: %d passed, %d failed, %d total" % (passed, failed, len(results)))

    if failed > 0:
        print()
        print("FAILED TESTS:")
        for r in results:
            if not r["passed"]:
                print("  %s: %s  (%s)" % (r["group"], r["name"], r["detail"]))
        sys.exit(1)
    else:
        print("All tests passed!")


if __name__ == "__main__":
    main()
