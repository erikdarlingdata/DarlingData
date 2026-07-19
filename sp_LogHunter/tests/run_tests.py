"""
sp_LogHunter assertion test harness
===================================
sp_LogHunter is a GENERATOR. It does not query the error log directly: it
builds an `EXECUTE master.dbo.xp_readerrorlog ...` command string in the
PERSISTED computed column #search.command, once per search string, then runs
each one through sys.sp_executesql inside a nested loop over every error log
archive.

That makes it a textbook case of this suite's characteristic bug: a command
that concatenates cleanly, reads correctly, and still fails when executed.
Worse, the failure is SILENT by design -- the EXECUTE is wrapped in
BEGIN TRY/BEGIN CATCH, and a command that throws is swallowed into #errors
rather than raised. A broken search string produces a clean-looking, quietly
incomplete result set: the procedure reports a healthy server because it never
managed to read the log.

The source carries comments describing four such bugs already fixed:

  * the second xp_readerrorlog search argument was a literal " ", which
    xp_readerrorlog ANDs with the first -- silently requiring every matched
    line to contain a space
  * in date-range mode @days_back is retired to NULL, which made the canary
    rows emit a NULL date argument and throw
  * a literal " inside @custom_message closed the quoted argument early and
    produced "Incorrect syntax near '+'"
  * an absurd @days_back overflowed DATEADD and killed the run

Every one of those lands in #errors instead of on the user's screen. So the
core assertion here is simple and blunt: **#errors must be empty**, across
every parameter combination that changes the generated command. That single
assertion regression-tests all four fixes above and anything similar.

On top of that, the harness proves the search actually searches, using a real
positive control:

  RAISERROR('<marker>', 10, 1) WITH LOG writes a known string to the error log.

Severity 10 is deliberate: it reaches the log while emitting no client-side
"Msg ..., Level 16" that the error detector would flag. The marker is chosen so
that NONE of the ~88 canned search strings match it and none of the noise
filters delete it, which makes the bidirectional pair meaningful:

  * @custom_message = marker            -> the row IS returned
  * @custom_message = never-written     -> it is NOT returned, run still clean
  * default run, no @custom_message     -> it is NOT returned

and likewise for date ranges: a window containing the write returns it, a
window 30 days in the past does not. Every absence assertion is paired with a
presence assertion on the same machinery, so nothing can pass vacuously by
returning an empty set.

SIDE EFFECT: this harness writes two informational lines to the SQL Server
error log (the markers). That cannot be undone without cycling the log, which
would be far more disruptive than the two lines, so the harness does not try.
The marker text is fixed rather than random so repeated runs do not accumulate
distinct junk. Nothing else on the instance is touched: no databases, no
configuration, no sessions.

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


# Written to the error log via RAISERROR ... WITH LOG, then searched for.
# Chosen so that none of sp_LogHunter's ~88 canned search strings match it
# (so a default run must NOT return it) and none of the "dumb messages"
# DELETE filters remove it (so a targeted run MUST return it).
MARKER = "DarlingDataLogHunterCanary"

# Never written to the log by anything. The negative half of the pair.
ABSENT_MARKER = "DarlingDataLogHunterNeverWrittenAnywhere"

# A marker containing a literal double quote. Search strings are wrapped in
# single quotes when the command is built, so a double quote must survive
# untouched; it was previously the delimiter and had to be doubled.
QUOTE_MARKER = 'DarlingDataLogHunter"Quoted"Canary'

# A marker longer than 128 characters. Search strings used to be wrapped in
# DOUBLE quotes, which under QUOTED_IDENTIFIER ON makes them identifiers --
# capped at 128 characters. Anything longer failed with Msg 103, was swallowed
# into #errors, and returned an empty result set that read as "nothing wrong".
# 150 characters puts this comfortably past the old ceiling.
LONG_MARKER = "DarlingDataLogHunterLongCanary" + ("X" * 120)

# Columns expected in the #error_log result set (shape-regression guard).
LOG_COLUMNS = ["table_name", "log_date", "process_info", "text"]

# Diagnostic lines the procedure prints only under @debug = 1.
DEBUG_MARKERS = ["@l_log:", "@t_searches:", "Declaring cursor"]


def find_sql_errors(text):
    """Return any SQL errors of severity 12 or higher found in text.

    go-sqlcmd reports errors on stdout, so both streams have to be checked.

    The bar is 12 here, not the 16 the other harnesses use, because the
    failure this procedure actually suffers from is quieter than that:
    xp_readerrorlog rejects a non-Unicode argument with "Msg 22004 ... Invalid
    Parameter Type" at Level 12, which reads on screen as simply finding
    nothing. A Level-16 filter walks straight past it -- the same blind spot
    that once let a Level-11 Msg 4060 masquerade as a procedure bug.

    Level 11 is deliberately still excluded: sp_LogHunter's own parameter
    guards (non-sysadmin, invalid @language_id, @custom_message_only with no
    message) raise at severity 11 by design, and those are expected output in
    the validation tests rather than failures.
    """
    if not text:
        return []
    return re.findall(r"Msg \d+, Level 1[2-9][^\n]*", text)


def _sqlcmd_prefix():
    """The sqlcmd binary plus any connection args, overridable via environment so
    one harness runs both locally and in CI. Locally SQLCMD_BIN defaults to the
    go-based 'sqlcmd' on PATH and SQLCMD_CONN_ARGS is empty; CI points SQLCMD_BIN
    at its own binary and sets SQLCMD_CONN_ARGS to '-C -N disable' -- trust the
    self-signed cert and disable encryption, since the modern Go TLS stack
    rejects the SQL Server 2017 container's certificate outright."""
    return [os.environ.get("SQLCMD_BIN", "sqlcmd")] + shlex.split(
        os.environ.get("SQLCMD_CONN_ARGS", ""))


def _sqlcmd(server, password, sql, headers=True):
    """Run a batch and return (stdout, stderr) decoded as UTF-8.

    Capturing bytes and decoding as UTF-8 keeps any non-ASCII log text from
    being mangled by the Windows console code page (text=True would do that).
    Output is tab-delimited and trimmed (-W -s TAB) and the line width is maxed
    (-w 65535) so wide log rows are not wrapped mid-row.
    """
    cmd = _sqlcmd_prefix() + [
        "-S", server, "-U", "sa", "-P", password,
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


def run_loghunter(server, password, args="", preamble=""):
    """Run sp_LogHunter and return (stdout, stderr).

    `preamble` allows a DECLARE block so date arguments can be computed
    SERVER-side (SYSDATETIME), which avoids any clock or timezone skew between
    this machine and the instance under test.
    """
    call = "EXECUTE dbo.sp_LogHunter %s;" % args if args else "EXECUTE dbo.sp_LogHunter;"
    return _sqlcmd(server, password, "SET NOCOUNT ON; " + preamble + call)


def write_marker(server, password, marker):
    """Write a marker line into the SQL Server error log.

    Severity 10 with WITH LOG reaches the error log without raising a
    client-side Msg/Level 16 that find_sql_errors would flag as a failure.
    Requires sysadmin, which the harness already needs to read the log at all.
    """
    out, err = _sqlcmd(server, password,
                       "SET NOCOUNT ON; RAISERROR('%s', 10, 1) WITH LOG;" % _esc(marker))
    return out + "\n" + err


def log_rows(stdout):
    """Return the #error_log data rows as lists of tab-split fields.

    A real row's first field is exactly '#error_log'. Error log text can
    contain embedded newlines, which produce continuation lines carrying only
    the tail of `text`; those do not start with the table marker and are
    skipped. The '#errors' result set is likewise excluded (different marker).
    """
    rows = []
    for line in stdout.splitlines():
        fields = line.split("\t")
        if fields and fields[0].strip() == "#error_log":
            rows.append([f.strip() for f in fields])
    return rows


def failed_commands(stdout):
    """Return the generated commands that THREW, from the #errors result set.

    sp_LogHunter swallows a failing xp_readerrorlog command into #errors rather
    than raising it, so this -- not the exit code, and not find_sql_errors -- is
    how a broken generated command is detected. Anything here is a real defect.
    """
    cmds = []
    for line in stdout.splitlines():
        fields = line.split("\t")
        if fields and fields[0].strip() == "#errors":
            cmds.append(line.strip())
    return cmds


def log_header_ok(stdout):
    """True if the #error_log result set header carries every expected column."""
    for line in stdout.splitlines():
        if "log_date" in line and "process_info" in line and "text" in line:
            return all(col in line for col in LOG_COLUMNS)
    return False


def marker_found(stdout, marker):
    """True if any #error_log row's text contains the marker."""
    return any(marker in row[-1] for row in log_rows(stdout))


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


def clean_run(R, group, name, out, err, expect_rows=True):
    """Assert one run was clean: no severe SQL error AND no generated command
    landed in #errors. Returns the parsed rows so callers can assert further.

    This is the workhorse. #errors being empty is the assertion that actually
    matters, because that is where a malformed generated command goes to die
    quietly.
    """
    combined = out + "\n" + err
    errors = find_sql_errors(combined)
    R.check(group, "%s: no severe SQL error" % name, not errors, str(errors[:3]))

    failures = failed_commands(out)
    R.check(group, "%s: no generated command failed (#errors empty)" % name,
            not failures,
            "%d command(s) threw, first: %s" % (len(failures), failures[:1]))

    rows = log_rows(out)
    if expect_rows:
        R.check(group, "%s: returned the #error_log result set" % name,
                log_header_ok(out), "#error_log header missing or incomplete")
    return rows


def smoke_tests(server, password, R):
    """Structural assertions: the proc runs, emits a well-formed result set,
    and honors @help / @debug."""
    grp = "Smoke"

    out, err = run_loghunter(server, password)
    rows = clean_run(R, grp, "default run", out, err)
    R.check(grp, "default run: returned at least one log row "
            "(positive control -- the log is readable)",
            len(rows) > 0, "no rows returned; is the error log empty?")

    malformed = [r for r in rows if len(r) < 4]
    R.check(grp, "default run: every row well-formed (4 fields)",
            not malformed,
            "%d rows, %d malformed: %s" % (len(rows), len(malformed), malformed[:2]))

    # ---- @help = 1 -------------------------------------------------------
    out, err = run_loghunter(server, password, "@help = 1")
    combined = out + "\n" + err
    R.check(grp, "@help = 1: no severe SQL error",
            not find_sql_errors(combined), str(find_sql_errors(combined)[:3]))
    R.check(grp, "@help = 1: returns help text",
            "i'm sp_LogHunter" in out or "sp_LogHunter" in out, "help text not found")
    R.check(grp, "@help = 1: emits no log rows (short-circuits)",
            not log_rows(out), "log rows emitted under @help")

    # ---- @debug = 1 ------------------------------------------------------
    # Scoped to a single custom search so the debug dump of #search is one row
    # rather than ~90, keeping the output small without changing the path.
    out, err = run_loghunter(
        server, password,
        "@custom_message = N'%s', @custom_message_only = 1, @debug = 1" % MARKER)
    combined = out + "\n" + err
    clean_run(R, grp, "@debug = 1", out, err, expect_rows=False)
    missing = [m for m in DEBUG_MARKERS if m not in combined]
    R.check(grp, "@debug = 1: prints diagnostics",
            not missing, "missing debug markers: %s" % missing)


def canary_tests(server, password, R):
    """Bidirectional proof that the search actually searches, using a real
    marker written to the error log."""
    grp = "Canary"

    write_marker(server, password, MARKER)

    # PRESENT: the marker is found when searched for. This is the positive
    # control that makes every absence assertion below non-vacuous.
    out, err = run_loghunter(
        server, password,
        "@custom_message = N'%s', @custom_message_only = 1" % MARKER)
    clean_run(R, grp, "marker search", out, err, expect_rows=False)
    R.check(grp, "marker PRESENT when searched for (proves search works)",
            marker_found(out, MARKER),
            "marker %r not returned; the custom search found nothing" % MARKER)

    # ABSENT: a string never written is not found -- but the run is still
    # clean, so this is a real negative rather than a crash.
    out, err = run_loghunter(
        server, password,
        "@custom_message = N'%s', @custom_message_only = 1" % ABSENT_MARKER)
    clean_run(R, grp, "never-written search", out, err, expect_rows=False)
    R.check(grp, "never-written string ABSENT (search filters, not passes all)",
            not marker_found(out, ABSENT_MARKER),
            "a string that was never logged came back")

    # ABSENT from a default run: none of the ~88 canned strings match the
    # marker, so a default run must not surface it. This proves @custom_message
    # is what found it above, not the canned sweep.
    out, err = run_loghunter(server, password)
    rows_default = clean_run(R, grp, "default run (no custom message)", out, err)
    R.check(grp, "marker ABSENT from a default run (canned searches do not match it)",
            not marker_found(out, MARKER),
            "marker surfaced without @custom_message; it collides with a canned string")

    # @custom_message_only = 0 runs BOTH the canned sweep and the custom
    # search: the marker is found AND the canned results are still there.
    out, err = run_loghunter(
        server, password,
        "@custom_message = N'%s', @custom_message_only = 0" % MARKER)
    rows_both = clean_run(R, grp, "custom + canned", out, err)
    R.check(grp, "@custom_message_only = 0: marker PRESENT (custom search ran)",
            marker_found(out, MARKER), "marker missing when combined with canned sweep")
    R.check(grp, "@custom_message_only = 0: canned sweep still ran "
            "(more rows than the marker alone)",
            len(rows_both) > 1,
            "only %d row(s); the canned searches appear to have been skipped"
            % len(rows_both))

    # And the inverse: only = 1 must NOT run the canned sweep, so it returns
    # strictly fewer rows than the combined run above.
    out, err = run_loghunter(
        server, password,
        "@custom_message = N'%s', @custom_message_only = 1" % MARKER)
    rows_only = log_rows(out)
    R.check(grp, "@custom_message_only = 1: skips the canned sweep "
            "(fewer rows than only = 0)",
            len(rows_only) < len(rows_both),
            "only=1 returned %d rows, only=0 returned %d -- the flag did nothing"
            % (len(rows_only), len(rows_both)))


def date_range_tests(server, password, R):
    """Bidirectional proof that the date arguments actually bound the search.

    Dates are computed server-side so no clock skew between this machine and
    the instance can affect the result.
    """
    grp = "DateRange"

    write_marker(server, password, MARKER)

    # A window that contains the write: the marker comes back.
    out, err = run_loghunter(
        server, password,
        "@start_date = @s, @end_date = @e, @custom_message = N'%s', "
        "@custom_message_only = 1" % MARKER,
        preamble="DECLARE @s datetime = DATEADD(HOUR, -1, SYSDATETIME()), "
                 "@e datetime = DATEADD(HOUR, 1, SYSDATETIME()); ")
    clean_run(R, grp, "window containing the write", out, err, expect_rows=False)
    R.check(grp, "marker PRESENT inside its window (proves date args work)",
            marker_found(out, MARKER),
            "marker not returned for a window that contains it")

    # A window 30 days in the past: the same marker must NOT come back. The
    # assertion above proves this run is capable of finding it, so this is a
    # real filter test rather than an empty result set.
    out, err = run_loghunter(
        server, password,
        "@start_date = @s, @end_date = @e, @custom_message = N'%s', "
        "@custom_message_only = 1" % MARKER,
        preamble="DECLARE @s datetime = DATEADD(DAY, -30, SYSDATETIME()), "
                 "@e datetime = DATEADD(DAY, -29, SYSDATETIME()); ")
    clean_run(R, grp, "window before the write", out, err, expect_rows=False)
    R.check(grp, "marker ABSENT outside its window (date range actually filters)",
            not marker_found(out, MARKER),
            "marker returned for a window 30 days before it was written")

    # @first_log_only = 1 still finds a marker written moments ago, since the
    # current log is log 0. Proves the flag narrows scope without breaking it.
    out, err = run_loghunter(
        server, password,
        "@first_log_only = 1, @custom_message = N'%s', "
        "@custom_message_only = 1" % MARKER)
    clean_run(R, grp, "@first_log_only = 1", out, err, expect_rows=False)
    R.check(grp, "@first_log_only = 1: still finds a marker in the current log",
            marker_found(out, MARKER),
            "marker missing when restricted to the first log")


def generated_command_tests(server, password, R):
    """The core matrix. Every case below changes how the xp_readerrorlog
    command string is built; each asserts the generated command EXECUTED
    cleanly (#errors empty). Several are direct regression tests for bugs
    documented in the source."""
    grp = "Generated"

    cases = [
        # (label, args, note)
        ("@days_back = 0 (normalized to -1)", "@days_back = 0", ""),
        ("@days_back positive (normalized to -7)", "@days_back = 7", ""),
        # Regression: an absurd value once overflowed DATEADD and killed the run.
        ("@days_back absurd (clamped to -36500)", "@days_back = -99999", ""),
        ("@days_back = -1", "@days_back = -1", ""),
        ("@first_log_only = 1", "@first_log_only = 1", ""),
        ("@language_id = 1033 explicit", "@language_id = 1033", ""),
    ]
    for label, args, _note in cases:
        out, err = run_loghunter(server, password, args)
        clean_run(R, grp, label, out, err)

    # Regression: in date-range mode @days_back is retired to NULL, and the
    # canary rows then had to fall back to @start_date for their floor. When
    # that fallback was missing the generated command received a NULL date and
    # threw -- straight into #errors, invisible to the caller. All three
    # date-range shapes are covered because the proc fills in whichever date
    # the caller omitted.
    date_cases = [
        ("@start_date only",
         "@start_date = @s",
         "DECLARE @s datetime = DATEADD(DAY, -3, SYSDATETIME()); "),
        ("@end_date only",
         "@end_date = @e",
         "DECLARE @e datetime = SYSDATETIME(); "),
        ("@start_date and @end_date",
         "@start_date = @s, @end_date = @e",
         "DECLARE @s datetime = DATEADD(DAY, -3, SYSDATETIME()), "
         "@e datetime = SYSDATETIME(); "),
    ]
    for label, args, preamble in date_cases:
        out, err = run_loghunter(server, password, args, preamble=preamble)
        clean_run(R, grp, "date-range mode: %s" % label, out, err)

    # Regression: a literal " inside @custom_message closed the quoted
    # xp_readerrorlog argument early and produced "Incorrect syntax near '+'".
    # The command is built by concatenation, so this is a parse-time failure of
    # the GENERATED batch -- exactly what #errors captures.
    write_marker(server, password, QUOTE_MARKER)
    out, err = run_loghunter(
        server, password,
        "@custom_message = N'%s', @custom_message_only = 1" % _esc(QUOTE_MARKER))
    clean_run(R, grp, "@custom_message containing a double quote", out, err,
              expect_rows=False)
    R.check(grp, "@custom_message with a double quote still MATCHES "
            "(quotes doubled, not dropped)",
            marker_found(out, QUOTE_MARKER),
            "quoted marker not returned; the quote handling changed its meaning")

    # A single quote is escaped on the T-SQL side rather than the
    # xp_readerrorlog side, so it exercises a different path.
    out, err = run_loghunter(
        server, password,
        "@custom_message = N'%s', @custom_message_only = 1"
        % _esc("DarlingData's LogHunter"))
    clean_run(R, grp, "@custom_message containing a single quote", out, err,
              expect_rows=False)

    # Regression: a @custom_message longer than 128 characters. While search
    # strings were wrapped in double quotes they parsed as identifiers, which
    # SQL Server caps at 128 characters, so anything longer died with Msg 103
    # ("The identifier that starts with ... is too long") -- into #errors,
    # never onto the caller's screen. Asserting only that it does not throw
    # would be too weak, so the marker is written to the log first and must
    # come back: proof that a long search actually searches.
    write_marker(server, password, LONG_MARKER)
    out, err = run_loghunter(
        server, password,
        "@custom_message = N'%s', @custom_message_only = 1" % _esc(LONG_MARKER))
    clean_run(R, grp, "@custom_message longer than 128 chars", out, err,
              expect_rows=False)
    R.check(grp, "@custom_message of %d chars MATCHES "
            "(no 128-char identifier limit)" % len(LONG_MARKER),
            marker_found(out, LONG_MARKER),
            "long marker not returned; the search string hit a length limit")


def validation_tests(server, password, R):
    """The guard paths that RAISERROR and RETURN before doing any work."""
    grp = "Validation"

    # Invalid @language_id: rejected up front.
    out, err = run_loghunter(server, password, "@language_id = 999999")
    combined = out + "\n" + err
    R.check(grp, "@language_id invalid: rejected with a message",
            "not a valid language_id" in combined,
            "expected language_id rejection, got: %r" % combined[:200])
    R.check(grp, "@language_id invalid: returns no log rows",
            not log_rows(out), "log rows emitted despite invalid language_id")

    # @custom_message_only = 1 with nothing to search for: rejected, because
    # it would otherwise leave #search empty and make the whole run a no-op
    # that reports a clean bill of health.
    for label, args in [
        ("NULL @custom_message", "@custom_message_only = 1"),
        ("empty @custom_message",
         "@custom_message_only = 1, @custom_message = N''"),
    ]:
        out, err = run_loghunter(server, password, args)
        combined = out + "\n" + err
        R.check(grp, "@custom_message_only = 1 with %s: rejected" % label,
                "requires a non-empty @custom_message" in combined,
                "expected rejection, got: %r" % combined[:200])
        R.check(grp, "@custom_message_only = 1 with %s: returns no log rows" % label,
                not log_rows(out), "log rows emitted despite rejection")

    # A valid non-English language_id warns rather than silently returning
    # nothing, because the search strings are English literals. Only asserted
    # when the instance actually has a non-English message set installed --
    # most containers ship 1033 only, and asserting unconditionally would fail
    # for a reason that has nothing to do with the procedure.
    out, _ = _sqlcmd(
        server, password,
        "SET NOCOUNT ON; SELECT TOP (1) CONVERT(varchar(10), m.language_id) "
        "FROM sys.messages AS m WHERE m.language_id <> 1033 "
        "GROUP BY m.language_id;",
        headers=False)
    other = next((l.strip() for l in out.splitlines() if l.strip().isdigit()), None)
    if other:
        out, err = run_loghunter(server, password, "@language_id = %s" % other)
        combined = out + "\n" + err
        R.check(grp, "non-English @language_id warns instead of returning silence",
                "will not translate" in combined,
                "no warning for language_id %s" % other)


def preflight(server, password):
    out, _ = _sqlcmd(
        server, password,
        "SET NOCOUNT ON; SELECT CASE WHEN OBJECT_ID(N'dbo.sp_LogHunter', N'P') "
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

    print("Running sp_LogHunter assertion tests against %s..." % args.server)
    print()

    if not preflight(args.server, args.password):
        print("ERROR: dbo.sp_LogHunter is not installed in master on %s." % args.server)
        print("Install sp_LogHunter.sql before running this harness.")
        sys.exit(1)

    R = Results()
    smoke_tests(args.server, args.password, R)
    canary_tests(args.server, args.password, R)
    date_range_tests(args.server, args.password, R)
    generated_command_tests(args.server, args.password, R)
    validation_tests(args.server, args.password, R)

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
