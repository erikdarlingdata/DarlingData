"""
sp_PerfCheck assertion test harness
====================================
sp_PerfCheck is a read-only server-health diagnostic. It inspects DMVs,
sys.configurations, and server state, and returns two result sets:

  1. #server_info : columns [Server Information], [Details]
  2. #results     : columns check_id, priority, priority_label, category,
                    finding, database_name, object_name, details, url

Almost every finding depends on VOLATILE server state (offline schedulers, I/O
latency, memory-starved queries, deadlock counts, memory dumps) that cannot be
controlled on a shared instance, so this harness does NOT assert on any of them.
A harness that flakes is worse than no harness. It asserts only on things that
are controllable or structurally invariant:

  * Structural / smoke: the proc runs without error; #server_info is populated;
    a default run emits a well-formed #results set (every row carries a
    check_id, priority, category, and finding); @help returns help text and no
    findings; @debug = 1 runs clean and prints diagnostics.

  * Forced-condition (the high-value core): conditions this harness can safely
    create and reset, proven BIDIRECTIONALLY (finding absent when the condition
    is not present, finding present when it is):
      - Server config: the "Non-Default Configuration" check (check_id 1000)
        reads sys.configurations. For a small set of SAFE options the harness
        forces each to a non-default value and back, and names the option in the
        details. Every option's original value_in_use is captured first and
        restored precisely in a finally block that runs even on assertion
        failure. The instance is never left reconfigured.
      - Database config: Auto-Shrink Enabled (7001) and Auto Update Statistics
        Disabled (7004) are forced on and off on a throwaway scratch database
        that is created and dropped by the harness.

Each absence assertion is paired with a positive control (#server_info
populated) so an empty or failed result set cannot pass vacuously, and with the
matching presence assertion, which proves the check actually runs.

After all tests the full sys.configurations snapshot is compared before/after to
prove zero net configuration change. The suite is idempotent: run it twice, same
result, no leaked config.

Usage:
    python run_tests.py [--server SQL2022] [--password L!nt0044]

Exits 1 if any assertion fails.
"""

import argparse
import re
import subprocess
import sys


# The "Non-Default Configuration" check (check_id 1000) fires when an option's
# value_in_use differs from the listed default. These three are SAFE to flip on
# a test instance: none require a restart, none are dangerous (no max server
# memory, no affinity), and nothing the CI does depends on them. Each is:
#   (option name, default value, forced non-default value)
# All three are "advanced" options, so 'show advanced options' must be 1 while
# they are configured; the harness sets it and restores it.
FORCED_OPTIONS = [
    ("cost threshold for parallelism", 5, 55),
    ("optimize for ad hoc workloads", 0, 1),
    ("access check cache bucket count", 0, 256),
]

# Column names expected in the #results header (shape-regression guard).
RESULTS_COLUMNS = [
    "check_id", "priority", "priority_label", "category", "finding",
    "database_name", "object_name", "details", "url",
]

# A diagnostic line the procedure prints only under @debug = 1.
DEBUG_MARKER = "Collecting server information"

# The last row the procedure always adds to #server_info (line ~5150). Its
# presence proves the proc ran to completion and emitted #server_info, which is
# the deterministic positive control for every absence assertion.
SERVER_INFO_MARKER = "Run Date"


def find_sql_errors(text):
    """Return any SQL errors of severity 16 or higher found in text.

    go-sqlcmd reports errors on stdout, so both streams have to be checked.
    Matching the severity numerically catches Level 16 through 19 rather than
    only the literal "Level 16".
    """
    if not text:
        return []
    return re.findall(r"Msg \d+, Level 1[6-9][^\n]*", text)


def _sqlcmd(server, password, sql, headers=True):
    """Run a batch and return (stdout, stderr) decoded as UTF-8.

    Capturing bytes and decoding as UTF-8 keeps any non-ASCII server/db name
    from being mangled by the Windows console code page (text=True would do
    that). Output is tab-delimited and trimmed (-W -s TAB) and the line width is
    maxed (-w 65535) so wide rows are not wrapped mid-row.
    """
    cmd = [
        "sqlcmd", "-S", server, "-U", "sa", "-P", password,
        "-d", "master",
        "-W",            # trim trailing spaces
        "-w", "65535",   # do not wrap wide rows
        "-s", "\t",      # tab delimiter
    ]
    if not headers:
        cmd += ["-h", "-1"]
    cmd += ["-Q", sql]
    r = subprocess.run(cmd, capture_output=True, timeout=300)
    out = (r.stdout or b"").decode("utf-8", errors="replace")
    err = (r.stderr or b"").decode("utf-8", errors="replace")
    return out, err


def _esc(s):
    """Escape a T-SQL single-quoted literal."""
    return s.replace("'", "''")


def run_perfcheck(server, password, args=""):
    """Run sp_PerfCheck and return combined (stdout, stderr)."""
    sql = "EXECUTE dbo.sp_PerfCheck %s;" % args if args else "EXECUTE dbo.sp_PerfCheck;"
    return _sqlcmd(server, password, sql)


def run_perfcheck_with_option(server, password, name, value):
    """Set one config option, RECONFIGURE, and run sp_PerfCheck in one batch so
    the run is guaranteed to see the new value_in_use."""
    sql = (
        "SET NOCOUNT ON; "
        "EXECUTE sys.sp_configure '%s', %d; "
        "RECONFIGURE; "
        "EXECUTE dbo.sp_PerfCheck;"
    ) % (_esc(name), value)
    return _sqlcmd(server, password, sql)


def set_option(server, password, name, value):
    """Set one config option and RECONFIGURE. Returns any severe errors."""
    sql = (
        "SET NOCOUNT ON; "
        "EXECUTE sys.sp_configure '%s', %d; "
        "RECONFIGURE;"
    ) % (_esc(name), value)
    out, err = _sqlcmd(server, password, sql)
    return find_sql_errors(out) + find_sql_errors(err)


def get_value_in_use(server, password, name):
    """Return the current value_in_use of a config option as an int."""
    sql = (
        "SET NOCOUNT ON; "
        "SELECT CONVERT(varchar(20), c.value_in_use) "
        "FROM sys.configurations AS c WHERE c.name = '%s';"
    ) % _esc(name)
    out, _ = _sqlcmd(server, password, sql, headers=False)
    for line in out.splitlines():
        line = line.strip()
        if line and (line.lstrip("-").isdigit()):
            return int(line)
    raise RuntimeError("could not read value_in_use for %r; output=%r" % (name, out[:200]))


def snapshot_config(server, password):
    """Return the full sys.configurations state as a sorted list of
    'name||value||value_in_use' lines, for a before/after zero-change diff."""
    sql = (
        "SET NOCOUNT ON; "
        "SELECT CONVERT(nvarchar(200), c.name) + N'||' + "
        "CONVERT(nvarchar(50), c.value) + N'||' + "
        "CONVERT(nvarchar(50), c.value_in_use) "
        "FROM sys.configurations AS c ORDER BY c.name;"
    )
    out, _ = _sqlcmd(server, password, sql, headers=False)
    return sorted(l.strip() for l in out.splitlines() if "||" in l)


def parse_result_rows(stdout):
    """Return the #results data rows as lists of tab-split fields.

    A real #results row starts with an integer check_id and has at least 8
    fields (check_id .. details). Continuation lines produced by embedded CR/LF
    inside a details value are only the tail of details plus url, so they carry
    few tabs and are filtered out. #server_info rows start with a text
    info_type, not a digit, so they are excluded too.
    """
    rows = []
    for line in stdout.splitlines():
        fields = line.split("\t")
        if len(fields) >= 8 and fields[0].strip().isdigit():
            rows.append([f.strip() for f in fields])
    return rows


def find_config_finding(rows, option_name):
    """Return the #results row for a Non-Default Configuration finding on the
    given option, or None."""
    want = "Non-Default Configuration: " + option_name
    for r in rows:
        if r[4] == want:
            return r
    return None


def find_db_finding(rows, finding_text, database_name):
    """Return the #results row whose finding and database_name match, or None."""
    for r in rows:
        if r[4] == finding_text and len(r) > 5 and r[5] == database_name:
            return r
    return None


def results_header_present(stdout):
    """True if the #results result set header was emitted."""
    for line in stdout.splitlines():
        if "check_id" in line and "finding" in line and "url" in line:
            return True
    return False


def results_header_columns_ok(stdout):
    """True if the #results header carries every expected column name."""
    for line in stdout.splitlines():
        if "check_id" in line and "finding" in line and "url" in line:
            return all(col in line for col in RESULTS_COLUMNS)
    return False


class Results:
    def __init__(self):
        self.items = []

    def check(self, group, name, condition, detail=""):
        self.items.append({
            "group": group,
            "name": name,
            "passed": bool(condition),
            "detail": detail,
        })

    @property
    def passed(self):
        return sum(1 for r in self.items if r["passed"])

    @property
    def failed(self):
        return sum(1 for r in self.items if not r["passed"])


def structural_tests(server, password, R):
    """Structural / smoke assertions: crashes and shape regressions."""
    # ---- Default-parameters run -----------------------------------------
    out, err = run_perfcheck(server, password)
    combined = out + "\n" + err
    errors = find_sql_errors(combined)
    R.check("Smoke", "default run: no severe SQL error",
            not errors, str(errors))
    R.check("Smoke", "default run: #server_info populated (Run Date present)",
            SERVER_INFO_MARKER in out, "Run Date not found")
    R.check("Smoke", "default run: #results result set emitted",
            results_header_present(out), "results header not found")
    R.check("Smoke", "default run: #results header has all expected columns",
            results_header_columns_ok(out), "one or more columns missing")

    rows = parse_result_rows(out)
    malformed = []
    for r in rows:
        ok = (r[0].isdigit() and r[1].isdigit() and r[3] != "" and r[4] != "")
        if not ok:
            malformed.append(r[:5])
    R.check("Smoke", "default run: every #results row well-formed "
            "(check_id, priority, category, finding)",
            len(malformed) == 0,
            "%d rows parsed, %d malformed: %s" % (len(rows), len(malformed), malformed[:3]))

    # ---- @help = 1 -------------------------------------------------------
    out, err = run_perfcheck(server, password, "@help = 1")
    combined = out + "\n" + err
    R.check("Smoke", "@help = 1: no severe SQL error",
            not find_sql_errors(combined), "errors present")
    R.check("Smoke", "@help = 1: returns help text",
            "i am sp_PerfCheck" in out, "help text not found")
    R.check("Smoke", "@help = 1: emits no findings (short-circuits)",
            (SERVER_INFO_MARKER not in out) and (not results_header_present(out)),
            "server_info or results were emitted under @help")

    # ---- @debug = 1 ------------------------------------------------------
    out, err = run_perfcheck(server, password, "@debug = 1")
    combined = out + "\n" + err
    R.check("Smoke", "@debug = 1: no severe SQL error",
            not find_sql_errors(combined), str(find_sql_errors(combined)))
    R.check("Smoke", "@debug = 1: prints diagnostic messages",
            DEBUG_MARKER in combined, "debug marker %r not found" % DEBUG_MARKER)
    R.check("Smoke", "@debug = 1: still completes (Run Date present)",
            SERVER_INFO_MARKER in out, "Run Date not found under @debug")


def forced_condition_tests(server, password, R):
    """Bidirectional forced-condition assertions on the check_id 1000
    Non-Default Configuration check. Captures and restores exact originals."""
    # Snapshot the entire config before touching anything.
    before = snapshot_config(server, password)

    # Capture originals: 'show advanced options' plus every forced option.
    saw_advanced = get_value_in_use(server, password, "show advanced options")
    originals = {}
    for (name, _default, _forced) in FORCED_OPTIONS:
        originals[name] = get_value_in_use(server, password, name)

    def restore_all():
        # Restore every touched option to its captured original, then restore
        # 'show advanced options'. One RECONFIGURE at the end promotes them all.
        for (name, _d, _f) in FORCED_OPTIONS:
            _sqlcmd(server, password,
                    "SET NOCOUNT ON; EXECUTE sys.sp_configure '%s', %d; RECONFIGURE;"
                    % (_esc(name), originals[name]))
        _sqlcmd(server, password,
                "SET NOCOUNT ON; EXECUTE sys.sp_configure 'show advanced options', %d; RECONFIGURE;"
                % saw_advanced)

    try:
        # All chosen options are advanced; make sure they are configurable.
        err = set_option(server, password, "show advanced options", 1)
        R.check("Config", "setup: 'show advanced options' configurable",
                not err, str(err))

        for (name, default_value, forced_value) in FORCED_OPTIONS:
            grp = "Config[%s]" % name

            # ---- ABSENT at the default value ----------------------------
            out, e = run_perfcheck_with_option(server, password, name, default_value)
            combined = out + "\n" + e
            R.check(grp, "no severe error on default-value run",
                    not find_sql_errors(combined), str(find_sql_errors(combined)))
            # positive control: the check machinery actually ran and produced
            # output, so "absent" is not a vacuous pass.
            R.check(grp, "positive control: #server_info populated at default",
                    SERVER_INFO_MARKER in out, "Run Date not found")
            rows = parse_result_rows(out)
            R.check(grp, "finding ABSENT when option = default (%d)" % default_value,
                    find_config_finding(rows, name) is None,
                    "unexpected finding present at default")

            # ---- PRESENT when forced to a non-default value -------------
            out, e = run_perfcheck_with_option(server, password, name, forced_value)
            combined = out + "\n" + e
            R.check(grp, "no severe error on forced-value run",
                    not find_sql_errors(combined), str(find_sql_errors(combined)))
            rows = parse_result_rows(out)
            row = find_config_finding(rows, name)
            R.check(grp, "finding PRESENT when option = forced (%d)" % forced_value,
                    row is not None, "finding not emitted when forced")
            if row is not None:
                well_formed = (row[0] == "1000" and row[1] == "50"
                               and row[3] == "Server Configuration")
                R.check(grp, "forced finding row well-formed "
                        "(check_id 1000, priority 50, Server Configuration)",
                        well_formed,
                        "check_id=%s priority=%s category=%s" % (row[0], row[1], row[3]))
                details = row[7] if len(row) > 7 else ""
                names_option = (name in details
                                and ("Current: %d" % forced_value) in details)
                R.check(grp, "forced finding details names the option and value",
                        names_option, "details=%r" % details[:160])
            else:
                R.check(grp, "forced finding row well-formed "
                        "(check_id 1000, priority 50, Server Configuration)",
                        False, "no row to inspect")
                R.check(grp, "forced finding details names the option and value",
                        False, "no row to inspect")

            # ---- Restore THIS option to its exact original --------------
            set_option(server, password, name, originals[name])
            now = get_value_in_use(server, password, name)
            R.check(grp, "option restored to original value_in_use (%d)" % originals[name],
                    now == originals[name], "value_in_use is now %d" % now)
    finally:
        # Safety net: restore everything even if an exception was raised.
        restore_all()

    # Zero net configuration change after the whole run.
    after = snapshot_config(server, password)
    diff = [x for x in after if x not in set(before)] + \
           [x for x in before if x not in set(after)]
    R.check("Config", "zero net configuration change (sys.configurations before == after)",
            before == after,
            "differences: %s" % diff[:6] if diff else "")


def database_scoped_tests(server, password, R):
    """Bidirectional forced-condition assertions on two database-level checks
    that read pure metadata: Auto-Shrink Enabled (check_id 7001) and Auto Update
    Statistics Disabled (check_id 7004). Both are instant, reversible ALTER
    DATABASE settings, so a scratch database can force each on and off
    deterministically, and both leave the database OPEN.

    (AUTO_CLOSE was deliberately NOT used. Forcing AUTO_CLOSE on and scoping the
    procedure to the closed database makes sys.databases return NULL for
    collation_name / target_recovery_time_in_seconds / delayed_durability_desc
    on SQL Server 2025, which sp_PerfCheck's #databases insert rejects with
    Msg 515. That is a real, version-dependent fragility in the procedure, not a
    test artifact; it is documented in README.md rather than asserted, so this
    harness stays deterministic across versions.)

    The design keeps every absence assertion non-vacuous WITHOUT relying on any
    volatile finding: in each run one toggle is set to its finding-producing
    state and the other is not, so the finding that IS present (scoped to the
    scratch database by name) proves the database was actually analyzed -- the
    positive control -- while the other finding's absence is therefore real, not
    the result of the database being skipped. Across the two runs each toggle is
    proven both present and absent.
    """
    db = "perfcheck_test_scratch"
    grp = "DbConfig"
    SHRINK = "Auto-Shrink Enabled"
    STATS = "Auto Update Statistics Disabled"

    drop_sql = (
        "SET NOCOUNT ON; "
        "IF DB_ID('%s') IS NOT NULL "
        "BEGIN "
        "ALTER DATABASE [%s] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; "
        "DROP DATABASE [%s]; "
        "END;"
    ) % (db, db, db)

    def scoped_run():
        return run_perfcheck(server, password, "@database_name = N'%s'" % db)

    # Idempotent setup: drop any leaked copy, then create fresh.
    out, err = _sqlcmd(server, password, drop_sql + " CREATE DATABASE [%s];" % db)
    setup_err = find_sql_errors(out) + find_sql_errors(err)
    R.check(grp, "setup: scratch database created",
            not setup_err and DB_marker(server, password, db), str(setup_err))
    if setup_err:
        _sqlcmd(server, password, drop_sql)
        return

    try:
        # ---- Run A: AUTO_SHRINK ON, AUTO_UPDATE_STATISTICS ON -----------
        _sqlcmd(server, password,
                "ALTER DATABASE [%s] SET AUTO_SHRINK ON; "
                "ALTER DATABASE [%s] SET AUTO_UPDATE_STATISTICS ON;" % (db, db))
        out, err = scoped_run()
        R.check(grp, "run A: no severe SQL error",
                not (find_sql_errors(out) + find_sql_errors(err)),
                str(find_sql_errors(out) + find_sql_errors(err)))
        R.check(grp, "run A: #server_info populated",
                SERVER_INFO_MARKER in out, "Run Date not found")
        rows = parse_result_rows(out)
        shrink = find_db_finding(rows, SHRINK, db)
        stats = find_db_finding(rows, STATS, db)
        # Auto-Shrink PRESENT: this both proves the toggle fires AND proves the
        # scratch database was analyzed (positive control for the absence below).
        R.check(grp, "Auto-Shrink PRESENT when forced on (proves db analyzed)",
                shrink is not None, "Auto-Shrink finding missing when forced on")
        if shrink is not None:
            R.check(grp, "Auto-Shrink row well-formed (check_id 7001, db scoped)",
                    shrink[0] == "7001" and shrink[3] == "Database Configuration",
                    "check_id=%s category=%s" % (shrink[0], shrink[3]))
        R.check(grp, "Auto-Update-Stats-Disabled ABSENT when stats on "
                "(db was analyzed, so non-vacuous)",
                stats is None, "stats-disabled finding present when stats on")

        # ---- Run B: AUTO_SHRINK OFF, AUTO_UPDATE_STATISTICS OFF ---------
        _sqlcmd(server, password,
                "ALTER DATABASE [%s] SET AUTO_SHRINK OFF; "
                "ALTER DATABASE [%s] SET AUTO_UPDATE_STATISTICS OFF;" % (db, db))
        out, err = scoped_run()
        R.check(grp, "run B: no severe SQL error",
                not (find_sql_errors(out) + find_sql_errors(err)),
                str(find_sql_errors(out) + find_sql_errors(err)))
        rows = parse_result_rows(out)
        shrink = find_db_finding(rows, SHRINK, db)
        stats = find_db_finding(rows, STATS, db)
        # Stats-disabled PRESENT is now the positive control that db was analyzed.
        R.check(grp, "Auto-Update-Stats-Disabled PRESENT when stats off "
                "(proves db analyzed)",
                stats is not None, "stats-disabled finding missing when stats off")
        if stats is not None:
            R.check(grp, "Stats-disabled row well-formed (check_id 7004, db scoped)",
                    stats[0] == "7004" and stats[3] == "Database Configuration",
                    "check_id=%s category=%s" % (stats[0], stats[3]))
        R.check(grp, "Auto-Shrink ABSENT when off (db was analyzed, so non-vacuous)",
                shrink is None, "Auto-Shrink finding present when off")
    finally:
        # Always drop the scratch database, even on assertion failure.
        _sqlcmd(server, password, drop_sql)
        R.check(grp, "cleanup: scratch database dropped",
                not DB_marker(server, password, db), "scratch database still exists")


def DB_marker(server, password, db):
    """True if the named database currently exists."""
    out, _ = _sqlcmd(
        server, password,
        "SET NOCOUNT ON; SELECT CASE WHEN DB_ID('%s') IS NOT NULL "
        "THEN 'YES' ELSE 'NO' END;" % _esc(db),
        headers=False,
    )
    return "YES" in out


def preflight(server, password):
    """Confirm sp_PerfCheck is installed before running anything."""
    out, err = _sqlcmd(
        server, password,
        "SET NOCOUNT ON; SELECT CASE WHEN OBJECT_ID(N'dbo.sp_PerfCheck', N'P') "
        "IS NOT NULL THEN 'OK' ELSE 'MISSING' END;",
        headers=False,
    )
    return "OK" in out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--server", default="SQL2022")
    ap.add_argument("--password", default="L!nt0044")
    args = ap.parse_args()

    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

    print("Running sp_PerfCheck assertion tests against %s..." % args.server)
    print()

    if not preflight(args.server, args.password):
        print("ERROR: dbo.sp_PerfCheck is not installed in master on %s." % args.server)
        print("Install sp_PerfCheck.sql before running this harness.")
        sys.exit(1)

    R = Results()
    structural_tests(args.server, args.password, R)
    forced_condition_tests(args.server, args.password, R)
    database_scoped_tests(args.server, args.password, R)

    for r in R.items:
        status = "PASS" if r["passed"] else "FAIL"
        detail = ("  (%s)" % r["detail"]) if (not r["passed"] and r["detail"]) else ""
        print("  [%s] %s: %s%s" % (status, r["group"], r["name"], detail))

    print()
    print("Results: %d passed, %d failed, %d total" % (R.passed, R.failed, len(R.items)))

    if R.failed > 0:
        print()
        print("FAILED TESTS:")
        for r in R.items:
            if not r["passed"]:
                print("  %s: %s  (%s)" % (r["group"], r["name"], r["detail"]))
        sys.exit(1)
    else:
        print("All tests passed!")


if __name__ == "__main__":
    main()
