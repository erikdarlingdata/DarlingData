"""
sp_HumanEvents DDL-validity and session-hygiene test harness
============================================================
sp_HumanEvents builds an Extended Events session out of dynamic SQL, samples
events for @seconds_sample seconds, then shreds and returns what it captured.
Its characteristic failure is generating a malformed CREATE EVENT SESSION for
some @event_type / filter-parameter combination -- a "generated script that will
not run" on the target server version. Live event CONTENT is timing-dependent
and thin, so this harness does NOT assert on captured rows; it asserts on the
thing that actually breaks: whether the generated DDL is accepted by SQL Server.

Two levers make that deterministic and fast, with no slow live captures:

  * @keep_alive = 1 creates a PERMANENT session and RETURNs immediately -- no
    WAITFOR sample, no drop (see the @keep_alive = 1 branch around line 1777 of
    sp_HumanEvents.sql). A session that CREATEs successfully is proof the
    generated DDL is valid on this server version. This is the high-value core:
    for every accepted @event_type, and for representative filter parameters,
    the harness runs @keep_alive = 1, asserts the call raised no error, asserts
    the named session now exists, asserts the session carries exactly the events
    that @event_type is supposed to add (read from the authoritative catalog
    sys.server_event_session_events, which cannot be truncated and proves SQL
    Server actually accepted each event), then DROPs the session and asserts it
    is gone.

  * @debug = 1 prints the generated @session_sql via RAISERROR (around line
    1768). The harness captures that per event category and asserts it contains
    CREATE EVENT SESSION plus the events expected for the category. (RAISERROR
    truncates a long message near 2044 chars, so the untruncated catalog check
    above is the authoritative one; the debug-text check is a secondary guard.)

Session hygiene is non-negotiable. Every session this proc or this harness
creates is dropped, even on assertion failure:

  * sp_HumanEvents names its sessions predictably:
      HumanEvents_<event_type>_<guid>   (one-shot, @keep_alive = 0)
      keeper_HumanEvents_<event_type>[_<custom_name>]   (@keep_alive = 1)
    The harness sweeps BOTH name patterns at start (idempotency: reap anything a
    prior aborted run left) and in a finally block at the end.
  * Each @keep_alive matrix case drops its own session immediately after the
    assertions, so at most one 100MB-ring-buffer session exists at a time.
    (Creating all of them at once demanded ~1.8 GB and drew Msg 701 -- a test
    artifact, not a proc bug; dropping-each-first avoids it.)
  * The short live-sample cases confirm the proc dropped its OWN session: the
    global session count is snapshotted before and after and must be equal.
  * Around the whole run, sys.server_event_sessions is diffed to prove zero net
    new sessions, and the diff is printed.

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


# ---------------------------------------------------------------- error scanning

def find_sql_errors(text):
    """Return any SQL errors of severity 16 or higher found in text.

    go-sqlcmd reports errors on stdout, so callers pass BOTH streams. Matching
    the severity numerically catches Level 16 through 19 rather than only the
    literal "Level 16". Note: sp_HumanEvents reports user-input problems with
    RAISERROR severity 11 (invalid @event_type, missing blocked process report,
    etc.); those are intentionally NOT matched here -- they are asserted on by
    text where relevant. A malformed CREATE EVENT SESSION shows up as a failed
    create (session absent) rather than only as a severe Msg, so the presence
    checks below are the real gate.
    """
    if not text:
        return []
    return re.findall(r"Msg \d+, Level 1[6-9][^\n]*", text)


# ---------------------------------------------------------------- sqlcmd plumbing

def _sqlcmd_prefix():
    """The sqlcmd binary plus any connection args, overridable via environment so
    one harness runs both locally and in CI. Locally SQLCMD_BIN defaults to the
    go-based 'sqlcmd' on PATH and SQLCMD_CONN_ARGS is empty; CI points SQLCMD_BIN
    at its own binary and sets SQLCMD_CONN_ARGS to the cert-trust flag its
    container connection needs (e.g. '-C')."""
    return [os.environ.get("SQLCMD_BIN", "sqlcmd")] + shlex.split(
        os.environ.get("SQLCMD_CONN_ARGS", ""))


def _sqlcmd(server, password, sql, database="master",
            query_timeout=None, subprocess_timeout=120):
    """Run a batch and return (stdout, stderr) decoded as UTF-8.

    Capturing bytes and decoding UTF-8 keeps any non-ASCII output from being
    mangled by the Windows console code page. -h -1 drops result-set headers so
    the RESULT| marker lines the batches emit are the only structured output.
    query_timeout maps to sqlcmd -t (a query timeout that sends an attention and
    cancels the batch server-side -- used to stop the never-ending collector
    loop); subprocess_timeout is a hard backstop on the whole process.
    """
    cmd = _sqlcmd_prefix() + [
        "-S", server, "-U", "sa", "-P", password,
        "-d", database,
        "-W",            # trim trailing spaces
        "-h", "-1",      # no result-set headers
        "-y", "0",       # unlimited variable column width (no truncation)
        "-w", "65535",   # do not wrap wide rows
    ]
    if query_timeout is not None:
        cmd += ["-t", str(query_timeout)]
    cmd += ["-Q", sql]
    try:
        r = subprocess.run(cmd, capture_output=True, timeout=subprocess_timeout)
    except subprocess.TimeoutExpired as e:
        out = (e.stdout or b"").decode("utf-8", errors="replace")
        err = (e.stderr or b"").decode("utf-8", errors="replace")
        return out, err + "\n[subprocess timeout]"
    out = (r.stdout or b"").decode("utf-8", errors="replace")
    err = (r.stderr or b"").decode("utf-8", errors="replace")
    return out, err


def _esc(s):
    """Escape a T-SQL single-quoted literal."""
    return str(s).replace("'", "''")


# ---------------------------------------------------------------- RESULT parsing

def parse_results(out):
    """Collect the RESULT| marker lines a batch emits into a dict."""
    d = {
        "events": set(), "proc_ok": False, "proc_error": None,
        "exists": None, "dropped": None, "gone": None,
        "before": None, "after": None, "tables": set(), "views": set(),
        "caps": {},
    }
    for line in out.splitlines():
        line = line.strip()
        if not line.startswith("RESULT|"):
            continue
        parts = line.split("|", 2)
        key = parts[1] if len(parts) > 1 else ""
        val = parts[2] if len(parts) > 2 else ""
        if key == "event":
            d["events"].add(val)
        elif key == "table":
            d["tables"].add(val)
        elif key == "view":
            d["views"].add(val)
        elif key == "proc_ok":
            d["proc_ok"] = (val == "1")
        elif key == "proc_error":
            d["proc_error"] = val
        elif key == "exists":
            d["exists"] = (val == "1")
        elif key == "dropped":
            d["dropped"] = (val == "1")
        elif key == "gone":
            d["gone"] = (val == "1")
        elif key in ("before", "after"):
            try:
                d[key] = int(val)
            except ValueError:
                d[key] = None
        elif key == "cap":
            sub = val.split("|", 1)
            if len(sub) == 2:
                d["caps"][sub[0]] = sub[1]
    return d


# ---------------------------------------------------------------- event mapping

def category_of(event_type):
    """Replicate the proc's event-type routing (the CASE around line 1650):
    %lock% then %quer% then %wait% then %recomp% then (%comp% and not %re%).
    Order matters; this mirrors it exactly."""
    et = event_type.lower()
    if "lock" in et:
        return "blocking"
    if "quer" in et:
        return "query"
    if "wait" in et:
        return "waits"
    if "recomp" in et:
        return "recompiles"
    if "comp" in et and "re" not in et:
        return "compiles"
    return None


def expected_events(event_type, caps, skip_plans=False):
    """Return the SET of event names sp_HumanEvents should attach for this
    event_type on this server, version-aware. Verified live against
    sys.server_event_session_events on SQL Server 2022."""
    cat = category_of(event_type)
    v = caps["v"]
    ce = caps["compile_events"]
    pe = caps["param_events"]
    if cat == "query":
        evs = ["module_end", "rpc_completed",
               "sp_statement_completed", "sql_statement_completed"]
        if not skip_plans:
            evs.append("query_post_execution_showplan")
        return set(evs)
    if cat == "waits":
        # proc keys purely on @v: wait_completed on 2014+, wait_info on 2012.
        return set(["wait_completed"]) if v > 11 else set(["wait_info"])
    if cat == "blocking":
        return set(["blocked_process_report"])
    if cat == "compiles":
        if ce:
            evs = ["sql_statement_post_compile"]
        else:
            evs = ["uncached_sql_batch_statistics", "sql_statement_recompile"]
        if pe:
            evs.append("query_parameterization_data")
        return set(evs)
    if cat == "recompiles":
        return set(["sql_statement_post_compile"]) if ce else set(["sql_statement_recompile"])
    return set()


def session_name(event_type, custom_name=None):
    n = "keeper_HumanEvents_" + event_type.lower()
    if custom_name:
        n += "_" + custom_name
    return n


def build_params(params):
    """Turn [(name, value, kind)] into a T-SQL argument tail."""
    s = ""
    for (name, value, kind) in params:
        if kind == "str":
            s += ", %s = N'%s'" % (name, _esc(value))
        else:  # int / bit
            s += ", %s = %s" % (name, value)
    return s


# ---------------------------------------------------------------- session sweeps

SWEEP_PREDICATE = (
    "s.name LIKE N'HumanEvents[_]%' OR s.name LIKE N'keeper[_]HumanEvents[_]%'"
)


def list_he_sessions(server, password):
    """Return the sorted list of sp_HumanEvents-owned session names present."""
    sql = (
        "SET NOCOUNT ON; SELECT line = 'RESULT|event|' + s.name "
        "FROM sys.server_event_sessions AS s WHERE " + SWEEP_PREDICATE + ";"
    )
    out, _ = _sqlcmd(server, password, sql)
    return sorted(parse_results(out)["events"])


def sweep_he_sessions(server, password):
    """Drop every sp_HumanEvents-owned session. These names are created only by
    sp_HumanEvents (naming contract documented in the proc's own cleanup), so
    sweeping them is safe and makes the suite idempotent."""
    sql = (
        "SET NOCOUNT ON; DECLARE @drop nvarchar(max) = N''; "
        "SELECT @drop += N'DROP EVENT SESSION ' + s.name + N' ON SERVER;' + NCHAR(10) "
        "FROM sys.server_event_sessions AS s WHERE " + SWEEP_PREDICATE + "; "
        "IF LEN(@drop) > 0 EXECUTE sys.sp_executesql @drop;"
    )
    return _sqlcmd(server, password, sql)


# ---------------------------------------------------------------- batch builders

def keepalive_batch(event_type, sname, params_sql):
    """Create a keep_alive session, report existence + its events, drop it,
    report gone -- all as RESULT| marker lines."""
    exists_expr = (
        "CASE WHEN EXISTS (SELECT 1 FROM sys.server_event_sessions AS s "
        "WHERE s.name = N'" + sname + "') THEN 1 ELSE 0 END"
    )
    return (
        "SET NOCOUNT ON;\n"
        "BEGIN TRY\n"
        "    EXECUTE dbo.sp_HumanEvents @event_type = N'" + event_type + "', "
        "@keep_alive = 1" + params_sql + ";\n"
        "    SELECT line = 'RESULT|proc_ok|1';\n"
        "END TRY\n"
        "BEGIN CATCH\n"
        "    SELECT line = 'RESULT|proc_error|' + "
        "LEFT(REPLACE(REPLACE(ERROR_MESSAGE(), CHAR(13), N' '), CHAR(10), N' '), 240);\n"
        "END CATCH;\n"
        "SELECT line = 'RESULT|exists|' + CONVERT(varchar(2), " + exists_expr + ");\n"
        "SELECT line = 'RESULT|event|' + sese.name "
        "FROM sys.server_event_sessions AS ses "
        "JOIN sys.server_event_session_events AS sese "
        "ON sese.event_session_id = ses.event_session_id "
        "WHERE ses.name = N'" + sname + "';\n"
        "IF EXISTS (SELECT 1 FROM sys.server_event_sessions AS s WHERE s.name = N'" + sname + "')\n"
        "BEGIN\n"
        "    BEGIN TRY EXECUTE (N'DROP EVENT SESSION " + sname + " ON SERVER;'); "
        "SELECT line = 'RESULT|dropped|1'; END TRY\n"
        "    BEGIN CATCH SELECT line = 'RESULT|dropped|0'; END CATCH;\n"
        "END;\n"
        "SELECT line = 'RESULT|gone|' + CONVERT(varchar(2), "
        "CASE WHEN EXISTS (SELECT 1 FROM sys.server_event_sessions AS s "
        "WHERE s.name = N'" + sname + "') THEN 0 ELSE 1 END);\n"
    )


# ---------------------------------------------------------------- results object

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


# ---------------------------------------------------------------- capability probe

def detect_caps(server, password):
    """Read version and XE capabilities so the expected-event sets are correct
    for whatever version we are pointed at."""
    sql = (
        "SET NOCOUNT ON;\n"
        "SELECT line = 'RESULT|cap|installed|' + CASE WHEN OBJECT_ID(N'dbo.sp_HumanEvents', N'P') IS NOT NULL THEN '1' ELSE '0' END;\n"
        "SELECT line = 'RESULT|cap|v|' + CONVERT(varchar(11), CONVERT(integer, PARSENAME(CONVERT(nvarchar(128), SERVERPROPERTY('ProductVersion')), 4)));\n"
        "SELECT line = 'RESULT|cap|mv|' + CONVERT(varchar(11), CONVERT(integer, PARSENAME(CONVERT(nvarchar(128), SERVERPROPERTY('ProductVersion')), 2)));\n"
        "SELECT line = 'RESULT|cap|azure|' + CASE WHEN CONVERT(integer, SERVERPROPERTY('EngineEdition')) = 5 THEN '1' ELSE '0' END;\n"
        "SELECT line = 'RESULT|cap|compile_events|' + CASE WHEN EXISTS (SELECT 1 FROM sys.dm_xe_objects AS o WHERE o.name = N'sql_statement_post_compile') THEN '1' ELSE '0' END;\n"
        "SELECT line = 'RESULT|cap|param_events|' + CASE WHEN EXISTS (SELECT 1 FROM sys.dm_xe_objects AS o WHERE o.name = N'query_parameterization_data') THEN '1' ELSE '0' END;\n"
        "SELECT line = 'RESULT|cap|bpr|' + CONVERT(varchar(11), ISNULL((SELECT CONVERT(integer, c.value_in_use) FROM sys.configurations AS c WHERE c.name = N'blocked process threshold (s)'), -1));\n"
    )
    out, err = _sqlcmd(server, password, sql)
    raw = parse_results(out)["caps"]
    return {
        "installed": raw.get("installed") == "1",
        "v": int(raw.get("v", "0") or "0"),
        "mv": int(raw.get("mv", "0") or "0"),
        "azure": raw.get("azure") == "1",
        "compile_events": raw.get("compile_events") == "1",
        "param_events": raw.get("param_events") == "1",
        "bpr": int(raw.get("bpr", "-1") or "-1"),
    }, (out, err)


# ---------------------------------------------------------------- config helpers

def get_config(server, password, name):
    sql = (
        "SET NOCOUNT ON; SELECT line = 'RESULT|before|' + "
        "CONVERT(varchar(11), CONVERT(integer, c.value_in_use)) "
        "FROM sys.configurations AS c WHERE c.name = N'" + _esc(name) + "';"
    )
    out, _ = _sqlcmd(server, password, sql)
    return parse_results(out)["before"]


def set_config(server, password, name, value):
    sql = (
        "SET NOCOUNT ON; EXECUTE sys.sp_configure '" + _esc(name) + "', "
        + str(value) + "; RECONFIGURE;"
    )
    return _sqlcmd(server, password, sql)


# ---------------------------------------------------------------- test groups

def matrix_case(server, password, R, group, label, event_type,
                params, caps, skip_plans=False, custom_name=None):
    sname = session_name(event_type, custom_name)
    params_sql = build_params(params)
    if skip_plans:
        params_sql += ", @skip_plans = 1"
    if custom_name:
        params_sql += ", @custom_name = N'" + _esc(custom_name) + "'"
    out, err = _sqlcmd(server, password, keepalive_batch(event_type, sname, params_sql))
    combined = out + "\n" + err
    d = parse_results(out)
    exp = expected_events(event_type, caps, skip_plans)

    R.check(group, "%s: no severe SQL error" % label,
            not find_sql_errors(combined), str(find_sql_errors(combined)))
    R.check(group, "%s: proc raised no error" % label,
            d["proc_ok"] and not d["proc_error"],
            "proc_error=%s" % d["proc_error"])
    R.check(group, "%s: session '%s' created" % (label, sname),
            d["exists"] is True, "exists=%s" % d["exists"])
    R.check(group, "%s: events == %s" % (label, sorted(exp)),
            d["events"] == exp,
            "got %s" % sorted(d["events"]))
    R.check(group, "%s: session dropped and gone" % label,
            d["gone"] is True, "gone=%s dropped=%s" % (d["gone"], d["dropped"]))
    # Belt-and-suspenders: nothing left behind by THIS case.
    return sname


def group_matrix_base(server, password, R, caps):
    all_types = [
        "waits", "blocking", "locking", "queries", "compiles", "recompiles",
        "wait", "block", "blocks", "lock", "locks", "query",
        "compile", "recompile", "compilation", "recompilation",
        "compilations", "recompilations",
    ]
    for et in all_types:
        matrix_case(server, password, R, "Matrix-Base", et, et, [], caps)


def group_matrix_filters(server, password, R, caps):
    cases = [
        ("query+duration+db", "query",
         [("@query_duration_ms", 1000, "int"), ("@database_name", "master", "str")], {}),
        ("query+memory+app+host+user", "query",
         [("@requested_memory_mb", 512, "int"),
          ("@client_app_name", "HE_TestApp", "str"),
          ("@client_hostname", "HE_TestHost", "str"),
          ("@username", "HE_TestUser", "str")], {}),
        ("query+session_sample", "query",
         [("@session_id", "sample", "str"), ("@sample_divisor", 3, "int")], {}),
        ("query+object", "query",
         [("@object_name", "spt_values", "str")], {}),
        ("query+skip_plans", "query", [], {"skip_plans": True}),
        ("query+custom_name", "query", [], {"custom_name": "unittest"}),
        ("waits+types+duration", "waits",
         [("@wait_type", "SOS_SCHEDULER_YIELD,CXPACKET", "str"),
          ("@wait_duration_ms", 5, "int")], {}),
        ("waits+all+danger", "waits",
         [("@wait_type", "ALL", "str"), ("@gimme_danger", 1, "bit")], {}),
        ("blocking+duration", "blocking",
         [("@blocking_duration_ms", 5000, "int")], {}),
        ("blocking+object", "blocking",
         [("@database_name", "master", "str"),
          ("@object_name", "spt_values", "str"),
          ("@object_schema", "dbo", "str"),
          ("@blocking_duration_ms", 1000, "int")], {}),
        ("compiles+app", "compiles",
         [("@client_app_name", "HE_TestApp", "str")], {}),
        ("recompiles+db", "recompiles",
         [("@database_name", "master", "str")], {}),
    ]
    for (label, et, params, opts) in cases:
        matrix_case(server, password, R, "Matrix-Filter", label, et, params, caps,
                    skip_plans=opts.get("skip_plans", False),
                    custom_name=opts.get("custom_name"))


def group_debug_ddl(server, password, R, caps):
    """Capture the @debug = 1 generated @session_sql per event category and
    assert it contains CREATE EVENT SESSION and each expected event."""
    reps = ["query", "waits", "blocking", "compiles", "recompiles"]
    first = True
    for et in reps:
        sname = session_name(et)
        batch = (
            "SET NOCOUNT ON;\n"
            "EXECUTE dbo.sp_HumanEvents @event_type = N'" + et + "', "
            "@keep_alive = 1, @debug = 1;\n"
            "IF EXISTS (SELECT 1 FROM sys.server_event_sessions AS s WHERE s.name = N'" + sname + "') "
            "EXECUTE (N'DROP EVENT SESSION " + sname + " ON SERVER;');\n"
        )
        out, err = _sqlcmd(server, password, batch)
        combined = out + "\n" + err
        exp = expected_events(et, caps)
        R.check("DebugDDL", "%s: no severe SQL error" % et,
                not find_sql_errors(combined), str(find_sql_errors(combined)))
        R.check("DebugDDL", "%s: debug prints CREATE EVENT SESSION for %s" % (et, sname),
                ("CREATE EVENT SESSION" in combined) and (sname in combined),
                "CREATE EVENT SESSION or session name not found in debug output")
        for ev in sorted(exp):
            R.check("DebugDDL", "%s: debug DDL names event %s" % (et, ev),
                    ev in combined, "event %s not present in debug text" % ev)
        if first:
            R.check("DebugDDL", "%s: @debug emits diagnostic markers" % et,
                    "Setting up the event session" in combined,
                    "expected diagnostic marker not found")
            first = False


def group_smoke(server, password, R, caps):
    # ---- @help = 1 -------------------------------------------------------
    help_batch = (
        "SET NOCOUNT ON;\n"
        "EXECUTE dbo.sp_HumanEvents @help = 1;\n"
        "SELECT line = 'RESULT|after|' + CONVERT(varchar(11), COUNT_BIG(*)) "
        "FROM sys.server_event_sessions AS s WHERE " + SWEEP_PREDICATE + ";\n"
    )
    out, err = _sqlcmd(server, password, help_batch)
    combined = out + "\n" + err
    d = parse_results(out)
    R.check("Smoke", "@help = 1: no severe SQL error",
            not find_sql_errors(combined), str(find_sql_errors(combined)))
    R.check("Smoke", "@help = 1: returns help text",
            "allow me to reintroduce myself" in combined,
            "help introduction text not found")
    R.check("Smoke", "@help = 1: creates no session",
            d["after"] == 0, "session count after @help = %s" % d["after"])

    # ---- invalid @event_type --------------------------------------------
    bad_batch = (
        "SET NOCOUNT ON;\n"
        "BEGIN TRY\n"
        "    EXECUTE dbo.sp_HumanEvents @event_type = N'garbage', @keep_alive = 1;\n"
        "    SELECT line = 'RESULT|proc_ok|1';\n"
        "END TRY\n"
        "BEGIN CATCH\n"
        "    SELECT line = 'RESULT|proc_error|' + "
        "LEFT(REPLACE(REPLACE(ERROR_MESSAGE(), CHAR(13), N' '), CHAR(10), N' '), 240);\n"
        "END CATCH;\n"
        "SELECT line = 'RESULT|after|' + CONVERT(varchar(11), COUNT_BIG(*)) "
        "FROM sys.server_event_sessions AS s WHERE s.name = N'keeper_HumanEvents_garbage';\n"
    )
    out, err = _sqlcmd(server, password, bad_batch)
    combined = out + "\n" + err
    d = parse_results(out)
    R.check("Smoke", "invalid @event_type: no severe SQL error (rejected at sev 11)",
            not find_sql_errors(combined), str(find_sql_errors(combined)))
    R.check("Smoke", "invalid @event_type: rejected with the validation message",
            "What on earth" in combined,
            "expected @event_type validation message not found")
    R.check("Smoke", "invalid @event_type: no session created",
            d["after"] == 0, "a keeper_HumanEvents_garbage session exists")


def group_live_sample(server, password, R, caps):
    """The full create/sample/query/drop path with a small @seconds_sample.
    Empty capture is expected and must NOT error, and the proc must drop its
    own throwaway session (global session count before == after)."""
    cases = [
        ("waits", [("@wait_duration_ms", 1, "int")]),
        ("query", [("@query_duration_ms", 0, "int")]),
    ]
    for (et, params) in cases:
        batch = (
            "SET NOCOUNT ON;\n"
            "SELECT line = 'RESULT|before|' + CONVERT(varchar(11), COUNT_BIG(*)) "
            "FROM sys.server_event_sessions AS s WHERE " + SWEEP_PREDICATE + ";\n"
            "BEGIN TRY\n"
            "    EXECUTE dbo.sp_HumanEvents @event_type = N'" + et + "', "
            "@seconds_sample = 3" + build_params(params) + ";\n"
            "    SELECT line = 'RESULT|proc_ok|1';\n"
            "END TRY\n"
            "BEGIN CATCH\n"
            "    SELECT line = 'RESULT|proc_error|' + "
            "LEFT(REPLACE(REPLACE(ERROR_MESSAGE(), CHAR(13), N' '), CHAR(10), N' '), 240);\n"
            "END CATCH;\n"
            "SELECT line = 'RESULT|after|' + CONVERT(varchar(11), COUNT_BIG(*)) "
            "FROM sys.server_event_sessions AS s WHERE " + SWEEP_PREDICATE + ";\n"
        )
        out, err = _sqlcmd(server, password, batch, subprocess_timeout=60)
        combined = out + "\n" + err
        d = parse_results(out)
        R.check("LiveSample", "%s 3s sample: no severe SQL error" % et,
                not find_sql_errors(combined), str(find_sql_errors(combined)))
        R.check("LiveSample", "%s 3s sample: proc completed (empty capture OK)" % et,
                d["proc_ok"] and not d["proc_error"],
                "proc_error=%s" % d["proc_error"])
        R.check("LiveSample", "%s 3s sample: proc dropped its own session (net 0)" % et,
                d["before"] is not None and d["after"] == d["before"],
                "before=%s after=%s" % (d["before"], d["after"]))


def group_collector(server, password, R, caps):
    """Logging-to-table mode: @keep_alive = 1 with @output_database_name enters
    an unbounded collector loop that creates permanent tables/views for keeper
    sessions and harvests into them forever. The tables are created in the first
    pass (well under a second), so the harness runs it with a query timeout
    (-t) that sends an attention and cleanly cancels the loop server-side, then
    asserts the logging objects were created. It then exercises the proc's own
    @cleanup = 1 teardown path and asserts the proc removed the session, tables,
    and views itself. Everything is created in and dropped with a throwaway
    scratch database.

    (This group runs last, after every matrix case has dropped its own session,
    so no other keeper_HumanEvents_ session exists when @cleanup = 1 -- which
    sweeps keeper sessions server-wide -- is invoked.)"""
    db = "sp_HumanEvents_test_scratch"
    sname = "keeper_HumanEvents_waits"
    drop_db = (
        "IF DB_ID('" + db + "') IS NOT NULL BEGIN "
        "ALTER DATABASE [" + db + "] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; "
        "DROP DATABASE [" + db + "]; END;"
    )
    # Idempotent setup.
    out, err = _sqlcmd(server, password,
                       "SET NOCOUNT ON; " + drop_db + " CREATE DATABASE [" + db + "];")
    setup_err = find_sql_errors(out) + find_sql_errors(err)
    R.check("Collector", "setup: scratch database created", not setup_err, str(setup_err))
    if setup_err:
        _sqlcmd(server, password, "SET NOCOUNT ON; " + drop_db)
        return

    want_views = {"HumanEvents_WaitsByDatabase",
                  "HumanEvents_WaitsByQueryAndDatabase",
                  "HumanEvents_WaitsTotal"}
    obj_chk = (
        "SET NOCOUNT ON;\n"
        "SELECT line = 'RESULT|table|' + t.name FROM sys.tables AS t;\n"
        "SELECT line = 'RESULT|view|' + v.name FROM sys.views AS v;\n"
    )

    try:
        collector = (
            "SET NOCOUNT ON; EXECUTE dbo.sp_HumanEvents "
            "@event_type = N'waits', @keep_alive = 1, @wait_duration_ms = 1, "
            "@output_database_name = N'" + db + "', @output_schema_name = N'dbo';"
        )
        # -t 15: the loop never returns on its own; time it out. Table creation
        # happens in the first pass, long before this fires.
        out, err = _sqlcmd(server, password, collector,
                           query_timeout=15, subprocess_timeout=60)
        combined = out + "\n" + err
        # The timeout itself is not a severe Msg; only real errors count.
        R.check("Collector", "collector run: no severe SQL error",
                not find_sql_errors(combined), str(find_sql_errors(combined)))

        out2, err2 = _sqlcmd(server, password, obj_chk, database=db)
        d = parse_results(out2)
        R.check("Collector", "collector created base table keeper_HumanEvents_waits",
                "keeper_HumanEvents_waits" in d["tables"],
                "tables=%s" % sorted(d["tables"]))
        R.check("Collector", "collector created waits views (%s)" % sorted(want_views),
                want_views <= d["views"], "views=%s" % sorted(d["views"]))

        # ----- exercise the proc's own @cleanup = 1 teardown ------------
        cleanup = (
            "SET NOCOUNT ON;\n"
            "BEGIN TRY\n"
            "    EXECUTE dbo.sp_HumanEvents @event_type = N'waits', @cleanup = 1, "
            "@output_database_name = N'" + db + "', @output_schema_name = N'dbo';\n"
            "    SELECT line = 'RESULT|proc_ok|1';\n"
            "END TRY\n"
            "BEGIN CATCH\n"
            "    SELECT line = 'RESULT|proc_error|' + "
            "LEFT(REPLACE(REPLACE(ERROR_MESSAGE(), CHAR(13), N' '), CHAR(10), N' '), 240);\n"
            "END CATCH;\n"
        )
        outc, errc = _sqlcmd(server, password, cleanup)
        dc = parse_results(outc)
        R.check("Collector", "@cleanup = 1: no severe SQL error",
                not find_sql_errors(outc + "\n" + errc),
                str(find_sql_errors(outc + "\n" + errc)))
        R.check("Collector", "@cleanup = 1: proc raised no error",
                dc["proc_ok"] and not dc["proc_error"],
                "proc_error=%s" % dc["proc_error"])

        out3, _ = _sqlcmd(server, password, obj_chk, database=db)
        d3 = parse_results(out3)
        R.check("Collector", "@cleanup = 1 removed the logging tables",
                "keeper_HumanEvents_waits" not in d3["tables"],
                "tables still present: %s" % sorted(d3["tables"]))
        R.check("Collector", "@cleanup = 1 removed the logging views",
                not (want_views & d3["views"]),
                "views still present: %s" % sorted(d3["views"] & want_views))
        out4, _ = _sqlcmd(server, password,
                          "SET NOCOUNT ON; SELECT line = 'RESULT|gone|' + CONVERT(varchar(2), "
                          "CASE WHEN EXISTS (SELECT 1 FROM sys.server_event_sessions AS s "
                          "WHERE s.name = N'" + sname + "') THEN 0 ELSE 1 END);")
        R.check("Collector", "@cleanup = 1 dropped the keeper session",
                parse_results(out4)["gone"] is True,
                "keeper session still present after @cleanup")
    finally:
        # Safety net: drop any residual session and the scratch database even if
        # the collector or the @cleanup path failed partway through.
        _sqlcmd(server, password,
                "SET NOCOUNT ON; "
                "IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = N'" + sname + "') "
                "DROP EVENT SESSION " + sname + " ON SERVER; " + drop_db)
        out, _ = _sqlcmd(server, password,
                         "SET NOCOUNT ON; SELECT line = 'RESULT|after|' + CONVERT(varchar(11), "
                         "(SELECT COUNT_BIG(*) FROM sys.databases WHERE name = N'" + db + "') + "
                         "(SELECT COUNT_BIG(*) FROM sys.server_event_sessions WHERE name = N'" + sname + "'));")
        left = parse_results(out)["after"]
        R.check("Collector", "cleanup: scratch database and keeper session dropped",
                left == 0, "residual objects = %s" % left)


# ---------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--server", default="SQL2022")
    ap.add_argument("--password", default="L!nt0044")
    args = ap.parse_args()

    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

    print("Running sp_HumanEvents DDL-validity tests against %s..." % args.server)
    print()

    caps, _raw = detect_caps(args.server, args.password)
    if not caps["installed"]:
        print("ERROR: dbo.sp_HumanEvents is not installed in master on %s." % args.server)
        print("Install sp_HumanEvents.sql before running this harness.")
        sys.exit(1)
    if caps["azure"]:
        print("ERROR: this harness targets a box-product instance "
              "(server-scoped sessions); the target reports Azure SQL DB.")
        sys.exit(1)

    print("Server: v=%d mv=%d  compile_events=%s  param_events=%s  bpr=%d"
          % (caps["v"], caps["mv"], caps["compile_events"],
             caps["param_events"], caps["bpr"]))

    R = Results()

    # ----- session hygiene: idempotent start ------------------------------
    sweep_he_sessions(args.server, args.password)
    before = list_he_sessions(args.server, args.password)
    print("Sessions before run (post-sweep): %s" % (before if before else "(none)"))
    print()

    # ----- blocked process report: blocking needs threshold > 0 ----------
    touched_bpr = False
    orig_show = None
    if caps["bpr"] == 0:
        orig_show = get_config(args.server, args.password, "show advanced options")
        set_config(args.server, args.password, "show advanced options", 1)
        set_config(args.server, args.password, "blocked process threshold (s)", 5)
        touched_bpr = True
        print("blocked process threshold was 0; temporarily set to 5 for the "
              "blocking cases (will be restored).")
        print()

    try:
        group_smoke(args.server, args.password, R, caps)
        group_matrix_base(args.server, args.password, R, caps)
        group_matrix_filters(args.server, args.password, R, caps)
        group_debug_ddl(args.server, args.password, R, caps)
        group_live_sample(args.server, args.password, R, caps)
        group_collector(args.server, args.password, R, caps)
    finally:
        # ----- session hygiene: measure leaks, then sweep ----------------
        after_tests = list_he_sessions(args.server, args.password)
        sweep_he_sessions(args.server, args.password)
        after_final = list_he_sessions(args.server, args.password)

        # ----- restore blocked process report ----------------------------
        if touched_bpr:
            set_config(args.server, args.password, "blocked process threshold (s)", 0)
            set_config(args.server, args.password, "show advanced options",
                       orig_show if orig_show is not None else 0)
            now_bpr = get_config(args.server, args.password, "blocked process threshold (s)")
            R.check("Hygiene", "blocked process threshold restored to 0",
                    now_bpr == 0, "bpr now %s" % now_bpr)

    R.check("Hygiene", "zero net Extended Events sessions after the run",
            after_tests == before,
            "leaked: %s" % [s for s in after_tests if s not in before])
    R.check("Hygiene", "no sp_HumanEvents sessions remain after sweep",
            after_final == before,
            "still present: %s" % after_final)

    print()
    print("Sessions after tests (pre-final-sweep): %s"
          % (after_tests if after_tests else "(none)"))
    print("Sessions after final sweep:             %s"
          % (after_final if after_final else "(none)"))
    net_new = [s for s in after_tests if s not in before]
    print("Net-new sessions (diff):                %s"
          % (net_new if net_new else "(none)  -> zero net"))
    print()

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
