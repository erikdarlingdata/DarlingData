"""
sp_QueryReproBuilder generate-and-execute test harness
======================================================
sp_QueryReproBuilder reads a query plan and emits a RUNNABLE reproduction script
(the T-SQL in #repro_queries.executable_query, surfaced in the primary result set
keyed table_name = 'results'). @query_plan_xml = <ShowPlanXML> bypasses Query
Store and is the deterministic entry point this harness drives.

For every case the harness:
  1. GENERATES - feeds an embedded ShowPlanXML through @query_plan_xml and pulls
     the emitted repro out of the executable_query processing instruction
     (template_generate.sql; extracted from stdout, never INSERT ... EXECUTE).
  2. EXECUTES - hands the repro back and runs it for real with sys.sp_executesql
     inside BEGIN TRANSACTION ... ROLLBACK / TRY-CATCH (template_execute.sql).
     Compiling is not enough: many bugs in a generated repro are semantic and
     only surface when the script actually runs.
  3. ASSERTS - the repro built, is correct (param count/types/values and
     statement text preserved), and RAN.

Every plan is embedded as a string constant, so the suite is fully portable and
deterministic - it depends on no captured plan cache and no specific user
database. Plans reference sys objects (always present); the one case that needs
a real user table uses a small fixture the harness creates in tempdb and drops.

The authentic ParameterCompiledValue serializations used below (e.g. numeric as
(12.50), money as ($99.9500), datetimeoffset as '... +05:30', guid as
{guid'...'}) were captured from real sniffed plans on SQL Server, so the
embedded ParameterList entries match what the procedure sees in the wild.

Usage:
    python run_tests.py [--server SQL2022] [--password L!nt0044] [--only SUBSTR] [--verbose]

Exits 1 if any assertion fails.
"""

import argparse
import atexit
import base64
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
GEN_TEMPLATE = os.path.join(HERE, "template_generate.sql")
EXEC_TEMPLATE = os.path.join(HERE, "template_execute.sql")

# Per-case .sql files are ephemeral; keep them out of the committed tests dir.
WORKDIR = tempfile.mkdtemp(prefix="qrb_tests_")
atexit.register(lambda: shutil.rmtree(WORKDIR, ignore_errors=True))
NS = "http://schemas.microsoft.com/sqlserver/2004/07/showplan"
FIXTURE = "tempdb.dbo.qrb_repro_fixture"

# Authentic ParameterCompiledValue serializations captured from real sniffed
# plans on SQL Server. Kept as constants so the embedded plans stay honest.
CV = {
    "int_5": "(5)",
    "bigint": "(123456789)",
    "numeric_38_2": "(12.50)",
    "decimal_38_10": "(3.1415926535)",
    "money": "($99.9500)",
    "float": "(2.2500000000000000e+000)",
    "real": "(1.5000000000000000e+000)",
    "bit": "(1)",
    "datetime": "'2020-01-15 10:20:30.123'",
    "datetime2_7": "'2020-01-15 10:20:30.1234567'",
    "datetimeoffset": "'2020-01-15 10:20:30.1234567 +05:30'",
    "date": "'2020-01-15'",
    "time_7": "'10:20:30.1234567'",
    "guid": "{guid'6F9619FF-8B86-D011-B42D-00C04FC964FF'}",
    "varchar_8000": "'Autobiographer'",
    "nvarchar_40": "N'Community'",
    "varbinary_8": "0x0102030405060708",
}

# Warning text the procedure emits when a parameter is declared in the query
# text but absent from the plan ParameterList (the documented '?' fill-in path).
QMARK_WARNING = "were not found in the plan ParameterList"


# ------------------------------------------------------------------ plan builder

def xesc(s):
    """Escape a string for an XML double-quoted attribute value.

    CR/LF/TAB become numeric character references: a literal CR/TAB in an
    attribute is normalized by the XML parser, so to make the procedure actually
    see a carriage return in a compiled value (as real plans store it, via
    &#x0D;) we emit &#13; etc.
    """
    return (s.replace("&", "&amp;").replace("<", "&lt;")
             .replace(">", "&gt;").replace('"', "&quot;")
             .replace("\r", "&#13;").replace("\n", "&#10;").replace("\t", "&#9;"))


def make_plan(stmt_text, params=None, body_extra="", statements_extra="", body_pre=""):
    """Build a minimal well-formed ShowPlanXML the procedure can parse.

    stmt_text: StatementText. For a parameterized repro it must begin with the
        '(@name type, ...)' prefix exactly as SQL Server stores it; the procedure
        strips that prefix and rebuilds the declaration list from the
        ParameterList (not from the text).
    params: list of (column, datatype, compiled_value) -> a ParameterList. Pass
        None to omit the ParameterList entirely (drives the '?' fill-in path when
        the text still declares parameters).
    body_pre: raw XML injected BEFORE the query's ParameterList (e.g. a decoy
        ParameterList, to probe the first-ParameterList-wins extraction).
    """
    plist = ""
    if params is not None:
        rows = "".join(
            '<ColumnReference Column="{}" ParameterDataType="{}" '
            'ParameterCompiledValue="{}"/>'.format(xesc(c), xesc(dt), xesc(cv))
            for (c, dt, cv) in params
        )
        plist = "<ParameterList>{}</ParameterList>".format(rows)
    return (
        '<ShowPlanXML xmlns="{ns}">'
        '<BatchSequence><Batch><Statements>'
        '<StmtSimple StatementText="{st}">'
        '<QueryPlan>'
        '<RelOp NodeId="0" PhysicalOp="Clustered Index Scan" LogicalOp="Clustered Index Scan">'
        '{bp}{pl}{be}'
        '</RelOp>'
        '</QueryPlan>'
        '</StmtSimple>{se}'
        '</Statements></Batch></BatchSequence>'
        '</ShowPlanXML>'
    ).format(ns=NS, st=xesc(stmt_text), pl=plist, be=body_extra, se=statements_extra, bp=body_pre)


# An internal-operator ParameterList (nested ColumnReference, no
# ParameterDataType), like the ones XML-reader / UDF operators emit. It
# serializes as <ParameterList> too, which is what makes it a decoy for the
# procedure's substring-based first-ParameterList extraction.
DECOY_PLIST = ('<ParameterList><ScalarOperator ScalarString="[Union1008]">'
               '<Identifier><ColumnReference Column="Union1008"/></Identifier>'
               '</ScalarOperator></ParameterList>')


# ------------------------------------------------------------------ sqlcmd plumbing

def _write_sql(path, sql):
    """Write a case file as UTF-8 with BOM so go-sqlcmd reads any N'...' unicode
    correctly."""
    with open(path, "w", encoding="utf-8-sig") as f:
        f.write(sql)


def _run_sql_file(server, password, path):
    cmd = [
        "sqlcmd", "-S", server, "-U", "sa", "-P", password,
        "-d", "master", "-i", path, "-y", "0", "-h", "-1",
    ]
    # Capture bytes and decode as UTF-8: go-sqlcmd emits UTF-8 on stdout, so a
    # unicode repro survives the round trip (text=True would use the console
    # code page on Windows and mangle it).
    r = subprocess.run(cmd, capture_output=True, timeout=180)
    out = (r.stdout or b"").decode("utf-8", errors="replace")
    err = (r.stderr or b"").decode("utf-8", errors="replace")
    return out + "\n" + err


def find_sql_errors(text):
    """Return SQL errors of severity 16 or higher. go-sqlcmd reports errors on
    stdout, so callers pass the combined stream. Matching severity numerically
    catches Level 16 through 19 rather than only the literal 'Level 16'."""
    if not text:
        return []
    return re.findall(r"Msg \d+, Level 1[6-9][^\n]*", text)


def generate(server, password, plan_text):
    """Run one plan through the procedure and pull the emitted repro out of the
    executable_query processing instruction on stdout."""
    with open(GEN_TEMPLATE, "r", encoding="utf-8") as f:
        tmpl = f.read()
    sql = tmpl.replace("@@PLAN@@", plan_text.replace("'", "''"))
    path = os.path.join(WORKDIR, "_gen_case.sql")
    _write_sql(path, sql)
    out = _run_sql_file(server, password, path)

    res = {"raw": out, "repro": None, "proc_error": None, "no_repro": False,
           "sql_errors": find_sql_errors(out)}

    m = re.search(r"PROC_ERROR:\s*(.+)", out)
    if m:
        res["proc_error"] = m.group(1).strip()

    # The repro renders as a processing instruction: <?_ ...repro... ?>. Its
    # content is emitted raw (entities decoded), so it is extracted verbatim.
    m = re.search(r"<\?_(.*?)\?>", out, re.DOTALL)
    if m:
        res["repro"] = m.group(1).strip("\r\n").lstrip()

    if res["repro"] is None:
        res["no_repro"] = True
    return res


def _b64_assignments(repro):
    b = base64.b64encode(repro.encode("utf-16-le")).decode("ascii")
    chunks = [b[i:i + 7000] for i in range(0, len(b), 7000)]
    return "\n".join("SET @b64 = @b64 + '%s';" % c for c in chunks)


RUNNER_PLAIN = """\
BEGIN TRANSACTION;
BEGIN TRY
    EXECUTE sys.sp_executesql @repro;
    PRINT 'EXEC_RESULT: PASS';
END TRY
BEGIN CATCH
    PRINT 'EXEC_RESULT: FAIL Msg ' + CONVERT(varchar(20), ERROR_NUMBER()) +
          ' Lvl ' + CONVERT(varchar(20), ERROR_SEVERITY()) +
          ' : ' + LEFT(ERROR_MESSAGE(), 300);
END CATCH;
IF XACT_STATE() <> 0
    ROLLBACK TRANSACTION;
"""

RUNNER_ECHO = """\
CREATE TABLE #echo (col_a int NULL, col_s nvarchar(100) NULL, col_b int NULL);
BEGIN TRANSACTION;
BEGIN TRY
    INSERT #echo
    EXECUTE sys.sp_executesql @repro;
    PRINT 'EXEC_RESULT: PASS';
    SELECT echo_line =
        'ECHO: a=[' + ISNULL(CONVERT(varchar(20), e.col_a), '<null>') +
        '] s=[' + ISNULL(e.col_s, '<null>') +
        '] b=[' + ISNULL(CONVERT(varchar(20), e.col_b), '<null>') + ']'
    FROM #echo AS e;
END TRY
BEGIN CATCH
    PRINT 'EXEC_RESULT: FAIL Msg ' + CONVERT(varchar(20), ERROR_NUMBER()) +
          ' Lvl ' + CONVERT(varchar(20), ERROR_SEVERITY()) +
          ' : ' + LEFT(ERROR_MESSAGE(), 300);
END CATCH;
IF XACT_STATE() <> 0
    ROLLBACK TRANSACTION;
"""


def execute(server, password, repro, echo=False):
    """Execute a repro for real, inside a rolled-back transaction. Returns the
    EXEC_RESULT verdict and (for echo cases) the actually-bound values."""
    with open(EXEC_TEMPLATE, "r", encoding="utf-8") as f:
        tmpl = f.read()
    sql = (tmpl.replace("@@B64_ASSIGNMENTS@@", _b64_assignments(repro))
                .replace("@@RUNNER@@", RUNNER_ECHO if echo else RUNNER_PLAIN))
    path = os.path.join(WORKDIR, "_exec_case.sql")
    _write_sql(path, sql)
    out = _run_sql_file(server, password, path)

    res = {"raw": out, "exec_result": None, "echo": None,
           "sql_errors": find_sql_errors(out)}
    m = re.search(r"EXEC_RESULT:\s*(PASS|FAIL[^\n]*)", out)
    if m:
        res["exec_result"] = "PASS" if m.group(1) == "PASS" else m.group(1).strip()
    m = re.search(r"ECHO: a=\[(.*?)\] s=\[(.*?)\] b=\[(.*?)\]", out)
    if m:
        res["echo"] = {"a": m.group(1), "s": m.group(2), "b": m.group(3)}
    return res


# ------------------------------------------------------------------ repro parsing

def sql_literal_segments(text):
    """Yield (start, end, content) for each N'...'-quoted literal in order, with
    '' collapsed back to a single quote in content."""
    segs = []
    i = 0
    n = len(text)
    while i < n:
        q = text.find("'", i)
        if q < 0:
            break
        j = q + 1
        buf = []
        while j < n:
            if text[j] == "'":
                if j + 1 < n and text[j + 1] == "'":
                    buf.append("'")
                    j += 2
                    continue
                break
            buf.append(text[j])
            j += 1
        segs.append((q, j, "".join(buf)))
        i = j + 1
    return segs


def split_top_values(s):
    """Split an sp_executesql trailing value list on top-level commas (commas
    that are not inside a string literal)."""
    vals = []
    cur = []
    i = 0
    n = len(s)
    in_str = False
    while i < n:
        ch = s[i]
        if ch == "'":
            in_str = not in_str
            cur.append(ch)
            i += 1
            continue
        if not in_str and ch == ",":
            vals.append("".join(cur).strip())
            cur = []
            i += 1
            while i < n and s[i] == " ":
                i += 1
            continue
        cur.append(ch)
        i += 1
    last = "".join(cur).strip()
    if last:
        vals.append(last)
    return vals


# ------------------------------------------------------------------ test battery

def build_cases():
    cases = []

    def add(name, plan, checks, echo=False, note=""):
        cases.append({"name": name, "plan": plan, "checks": checks,
                      "echo": echo, "note": note})

    # ---------- Parameterized, scaled/precision and edge types --------------
    # Each embeds the authentic ParameterCompiledValue for its type and asserts
    # the declared type round-trips into the sp_executesql declaration list and
    # the repro RUNS. This is the core of the required coverage: numeric(38,2),
    # decimal, varchar(8000), nvarchar(max), datetime2, datetimeoffset, plus a
    # broad type sweep.
    typed = [
        ("p_int", "@p", "int", CV["int_5"],
         "SELECT c = COUNT_BIG(*) FROM sys.all_columns AS ac WHERE ac.column_id = @p", ["5"]),
        ("p_bigint", "@p", "bigint", CV["bigint"],
         "SELECT c = COUNT_BIG(*) FROM sys.all_columns AS ac WHERE ac.object_id = @p", ["123456789"]),
        ("p_numeric_38_2", "@amt", "numeric(38,2)", CV["numeric_38_2"],
         "SELECT c = COUNT_BIG(*) FROM sys.all_columns AS ac WHERE ac.column_id > @amt", ["12.50"]),
        ("p_decimal_38_10", "@d", "decimal(38,10)", CV["decimal_38_10"],
         "SELECT c = COUNT_BIG(*) FROM sys.all_columns AS ac WHERE ac.column_id > @d", ["3.1415926535"]),
        ("p_money", "@m", "money", CV["money"],
         "SELECT c = COUNT_BIG(*) FROM sys.all_columns AS ac WHERE ac.column_id > @m", ["$99.9500"]),
        ("p_float", "@f", "float", CV["float"],
         "SELECT c = COUNT_BIG(*) FROM sys.all_columns AS ac WHERE ac.column_id > @f", None),
        ("p_real", "@r", "real", CV["real"],
         "SELECT c = COUNT_BIG(*) FROM sys.all_columns AS ac WHERE ac.column_id > @r", None),
        ("p_bit", "@b", "bit", CV["bit"],
         "SELECT c = COUNT_BIG(*) FROM sys.all_columns AS ac WHERE ac.is_nullable = @b", None),
        ("p_datetime", "@d", "datetime", CV["datetime"],
         "SELECT c = COUNT_BIG(*) FROM sys.objects AS o WHERE o.modify_date > @d", None),
        ("p_datetime2_7", "@d", "datetime2(7)", CV["datetime2_7"],
         "SELECT c = COUNT_BIG(*) FROM sys.objects AS o WHERE o.modify_date > @d", None),
        ("p_datetimeoffset", "@d", "datetimeoffset(7)", CV["datetimeoffset"],
         "SELECT c = COUNT_BIG(*) FROM sys.objects AS o WHERE o.modify_date > @d", None),
        ("p_date", "@d", "date", CV["date"],
         "SELECT c = COUNT_BIG(*) FROM sys.objects AS o WHERE CONVERT(date, o.modify_date) > @d", None),
        ("p_time_7", "@t", "time(7)", CV["time_7"],
         "SELECT c = COUNT_BIG(*) FROM sys.objects AS o WHERE CONVERT(time(7), o.modify_date) > @t", None),
        ("p_uniqueidentifier", "@g", "uniqueidentifier", CV["guid"],
         "SELECT c = COUNT_BIG(*) FROM sys.objects AS o WHERE o.object_id > 0 AND @g IS NOT NULL", None),
        ("p_varchar_8000", "@nm", "varchar(8000)", CV["varchar_8000"],
         "SELECT c = COUNT_BIG(*) FROM sys.all_columns AS ac WHERE ac.name = @nm", ["'Autobiographer'"]),
        ("p_nvarchar_40", "@nm", "nvarchar(40)", CV["nvarchar_40"],
         "SELECT c = COUNT_BIG(*) FROM sys.all_columns AS ac WHERE ac.name = @nm", ["N'Community'"]),
        ("p_nvarchar_max", "@b", "nvarchar(max)", "N'hello'",
         "SELECT c = COUNT_BIG(*) FROM sys.all_columns AS ac WHERE CONVERT(nvarchar(max), ac.name) = @b", ["N'hello'"]),
        ("p_varbinary_8", "@vb", "varbinary(8)", CV["varbinary_8"],
         "SELECT c = COUNT_BIG(*) FROM sys.all_columns AS ac WHERE @vb IS NOT NULL AND ac.column_id > 0", None),
    ]
    for (name, pn, dt, cv, body, present) in typed:
        stmt = "(%s %s)%s" % (pn, dt, body)
        add("type:%s" % name,
            make_plan(stmt, params=[(pn, dt, cv)]),
            {"must_exec": True, "expect_params": [(pn, dt)],
             "values_present": present})

    # ---------- No-parameter plans ----------------------------------------
    add("noparam:sys",
        make_plan("SELECT c = COUNT_BIG(*) FROM sys.all_objects AS o WHERE o.object_id > 0"),
        {"must_exec": True})

    # ---------- Long statement text: > 4000 and > 8000 --------------------
    pred_5k = " OR ".join("o.object_id = %d" % k for k in range(0, 300))   # ~ 5k chars
    add("long:stmt_gt4000",
        make_plan("SELECT c = COUNT_BIG(*) FROM sys.all_objects AS o WHERE " + pred_5k),
        {"must_exec": True, "min_repro_len": 4000})

    pred_9k = " OR ".join("o.object_id = %d" % k for k in range(0, 900))   # ~ 16k chars
    add("long:stmt_gt8000",
        make_plan("SELECT c = COUNT_BIG(*) FROM sys.all_objects AS o WHERE " + pred_9k),
        {"must_exec": True, "min_repro_len": 8000})

    long_in = ",".join("@p%d" % k for k in range(1, 400))
    long_decls = ",".join("@p%d int" % k for k in range(1, 400))
    add("long:param_stmt_gt8000",
        make_plan("(%s)SELECT c = COUNT_BIG(*) FROM sys.all_columns AS ac WHERE ac.column_id IN (%s)"
                  % (long_decls, long_in),
                  params=[("@p%d" % k, "int", "(%d)" % k) for k in range(1, 400)]),
        {"must_exec": True, "min_repro_len": 8000})

    # ---------- Entity characters (& < > ') in statement text -------------
    add("entity:literal_lt_gt_amp",
        make_plan("SELECT c = COUNT_BIG(*) FROM sys.all_columns AS ac WHERE ac.name = N'a<b>&c'"),
        {"must_exec": True, "stmt_contains": "a<b>&c"})

    add("entity:gt_lt_in_query",
        make_plan("SELECT x = (SELECT 1 WHERE 3 < 5 AND 5 > 3)"),
        {"must_exec": True})

    # Entity characters in a parameter's compiled value (authentic plans double
    # the quote inside the attribute: ParameterCompiledValue="N'O''Brien & <x>'").
    add("entity:param_value_quote_entity",
        make_plan("(@n nvarchar(40))SELECT c = COUNT_BIG(*) FROM sys.all_columns AS ac WHERE ac.name = @n",
                  params=[("@n", "nvarchar(40)", "N'O''Brien & <x>'")]),
        {"must_exec": True, "values_present": ["O''Brien"]})

    # ---------- Apostrophes -------------------------------------------------
    # Apostrophe inside a parameterized statement: must be re-doubled when the
    # statement is wrapped in the outer N'...' for sp_executesql.
    add("apostrophe:in_param_stmt",
        make_plan("(@x int)SELECT c = COUNT_BIG(*) FROM sys.all_columns AS ac "
                  "WHERE ac.name = N'O''Brien' AND ac.column_id = @x",
                  params=[("@x", "int", "(1)")]),
        {"must_exec": True, "stmt_contains": "O'"})

    # Apostrophe inside a non-parameterized statement (emitted as raw text).
    add("apostrophe:in_raw_stmt",
        make_plan("SELECT c = COUNT_BIG(*) FROM sys.all_columns AS ac WHERE ac.name = N'D''Angelo'"),
        {"must_exec": True, "stmt_contains": "D'"})

    # ---------- Unicode / N-literal ---------------------------------------
    # Literal kept as \u escapes so this file stays ASCII; at runtime the string
    # carries real U+00E9 (e-acute) and U+4E2D U+6587 (Chinese).
    add("unicode:n_literal",
        make_plan("SELECT c = COUNT_BIG(*) FROM sys.all_columns AS ac "
                  "WHERE ac.name = N'" + chr(0x00e9) + chr(0x4e2d) + chr(0x6587) + "'"),
        {"must_exec": True, "stmt_contains": chr(0x4e2d) + chr(0x6587)})

    # ---------- Alignment / multi-parameter --------------------------------
    add("align:autoparam_12",
        make_plan("(@1 int,@2 int,@3 int,@4 int,@5 int,@6 int,@7 int,@8 int,@9 int,@10 int,@11 int,@12 int)"
                  "SELECT c = COUNT_BIG(*) FROM sys.all_columns AS ac WHERE ac.column_id IN "
                  "(@1,@2,@3,@4,@5,@6,@7,@8,@9,@10,@11,@12)",
                  params=[("@%d" % k, "int", "(%d)" % k) for k in range(1, 13)]),
        {"must_exec": True, "align_check": True,
         "expect_params": [("@%d" % k, "int") for k in range(1, 13)]})

    # Declared order (@z, @a) differs from ParameterList order (@a, @z) and the
    # types differ; both declaration and value lists must sort by name so value i
    # binds to declaration i.
    add("align:name_order_mismatch",
        make_plan("(@z int, @a nvarchar(20))SELECT c = COUNT_BIG(*) FROM sys.all_columns AS ac "
                  "WHERE ac.column_id = @z AND ac.name = @a",
                  params=[("@a", "nvarchar(20)", "N'hi'"), ("@z", "int", "(5)")]),
        {"must_exec": True, "align_check": True,
         "expect_params": [("@a", "nvarchar(20)"), ("@z", "int")]})

    # ---------- Control characters in a parameter value --------------------
    # A sniffed string value with an embedded CR/LF is realistic (addresses,
    # JSON, SQL). The value list is built with FOR XML ... value('./text()[1]');
    # the marker after the control char must survive (not be truncated).
    add("control:cr_in_value",
        make_plan("(@s nvarchar(50))SELECT col_a = 1, col_s = @s, col_b = 2",
                  params=[("@s", "nvarchar(50)", "N'AAA" + chr(13) + "ZZZ'")]),
        {"must_exec": True, "repro_contains": "ZZZ"})

    add("control:lf_in_value",
        make_plan("(@s nvarchar(50))SELECT col_a = 1, col_s = @s, col_b = 2",
                  params=[("@s", "nvarchar(50)", "N'AAA" + chr(10) + "ZZZ'")]),
        {"must_exec": True, "repro_contains": "ZZZ"})

    # ---------- Embedded constant -----------------------------------------
    add("const:embedded_42",
        make_plan("SELECT c = COUNT_BIG(*) FROM sys.all_columns AS ac WHERE ac.column_id = 42",
                  body_extra='<IndexScan><Predicate><ScalarOperator>'
                             '<Const ConstValue="(42)"/></ScalarOperator></Predicate></IndexScan>'),
        {"must_exec": True})

    # ---------- Non-SELECT (UPDATE) against a real user table -------------
    # Needs a real table (cannot UPDATE a sys view). The harness creates
    # tempdb.dbo.qrb_repro_fixture at startup and drops it at the end; the repro
    # runs inside the rolled-back transaction so the write is undone.
    add("update:param",
        make_plan("(@r int)UPDATE f SET f.val = f.val FROM " + FIXTURE + " AS f WHERE f.id = @r",
                  params=[("@r", "int", "(1)")]),
        {"must_exec": True})

    # ---------- The documented '?' fill-in path (warned) ------------------
    # A parameter is declared in the query text but absent from the plan's
    # ParameterList. The procedure sets its value to ? and WARNS. This is
    # deliberate: the repro fails LOUD (Msg 102 near '?') rather than silently
    # running with a wrong value. Assert the warning fires, the placeholder is
    # present, and execution does not silently pass.
    add("qmark:no_paramlist_declared",
        make_plan("(@p1 int)SELECT c = COUNT_BIG(*) FROM sys.all_columns AS ac WHERE ac.column_id = @p1",
                  params=None),
        {"expect_qmark": True})

    # Same, with a scaled type in the text: the declared numeric(10,2) must not
    # be split on its internal comma while being carried into the declaration.
    add("qmark:scaled_fillin",
        make_plan("(@a numeric(10,2), @b int)SELECT c = COUNT_BIG(*) FROM sys.all_columns AS ac "
                  "WHERE ac.column_id = @b", params=None),
        {"expect_qmark": True, "decls_contain": ["numeric(10,2)"]})

    # ---------- First-ParameterList-wins hazard ----------------------------
    # E6-style control: real ParameterList first, decoy second -> binds 555.
    add("decoy:real_first_control",
        make_plan("(@id int)SELECT col_a = @id, col_s = N'q', col_b = @id",
                  params=[("@id", "int", "(555)")],
                  body_extra=DECOY_PLIST),
        {"echo_expect": {"a": "555", "s": "q", "b": "555"}}, echo=True)

    # E5-style probe: a decoy ParameterList (as XML-reader / UDF operators emit)
    # precedes the query's own. The procedure substring-extracts the FIRST
    # <ParameterList>, so the real @id is lost -> the fill-in path warns and
    # emits ? -> the repro fails LOUD. This documents that the hazard degrades
    # safely (loud failure with a warning), not into a silent wrong result.
    add("decoy:decoy_first_degrades_loud",
        make_plan("(@id int)SELECT col_a = @id, col_s = N'q', col_b = @id",
                  params=[("@id", "int", "(555)")],
                  body_pre=DECOY_PLIST),
        {"expect_qmark": True,
         "note": "decoy ParameterList precedes query's -> real @id skipped, ? fill-in"})

    # ---------- Echo cases: assert the ACTUAL bound values -----------------
    # These execute the repro and read back what was really bound, catching
    # silent value/parameter reordering that would still run.
    add("echo:two_int",
        make_plan("(@a int, @b int)SELECT col_a = @a, col_s = N'x', col_b = @b",
                  params=[("@a", "int", "(999)"), ("@b", "int", "(111)")]),
        {"echo_expect": {"a": "999", "s": "x", "b": "111"}}, echo=True)

    add("echo:mixed_types",
        make_plan("(@a int, @z int, @m nvarchar(20))SELECT col_a = @a, col_s = @m, col_b = @z",
                  params=[("@a", "int", "(777)"), ("@z", "int", "(222)"),
                          ("@m", "nvarchar(20)", "N'mid'")]),
        {"echo_expect": {"a": "777", "s": "mid", "b": "222"}}, echo=True)

    add("echo:quote_entity_value",
        make_plan("(@a int, @s nvarchar(50), @b int)SELECT col_a = @a, col_s = @s, col_b = @b",
                  params=[("@a", "int", "(1)"),
                          ("@s", "nvarchar(50)", "N'O''Brien & <b>'"),
                          ("@b", "int", "(2)")]),
        {"echo_expect": {"a": "1", "s": "O'Brien & <b>", "b": "2"}}, echo=True)

    add("echo:numeric_value_paren_strip",
        make_plan("(@a int, @b int)SELECT col_a = @a, col_s = N'n', col_b = @b",
                  params=[("@a", "int", "(-5)"), ("@b", "int", "(2147483647)")]),
        {"echo_expect": {"a": "-5", "s": "n", "b": "2147483647"}}, echo=True)

    # ---------- Negative: no repro should be built -------------------------
    add("negative:no_stmtsimple",
        '<ShowPlanXML xmlns="%s"><BatchSequence><Batch><Statements>'
        '</Statements></Batch></BatchSequence></ShowPlanXML>' % NS,
        {"expect_no_repro": True})

    add("negative:not_showplan",
        '<root><child a="1">hello</child></root>',
        {"expect_no_repro": True})

    return cases


# ------------------------------------------------------------------ assertions

def check_case(case, gen, ex):
    """Return list of (ok, label, detail)."""
    out = []
    checks = case["checks"]

    def ck(ok, label, detail=""):
        out.append((bool(ok), label, detail))

    repro = gen["repro"] or ""

    # ----- negative cases: the procedure must refuse, and say why ----------
    if checks.get("expect_no_repro"):
        ck(gen["repro"] is None, "no repro emitted", "repro present")
        ck("has no StmtSimple" in gen["raw"],
           "StmtSimple diagnostic emitted", "diagnostic message absent")
        ck(not gen["sql_errors"], "no severe error on no-repro", str(gen["sql_errors"]))
        return out

    # ----- '?' fill-in path: warned, builds, fails loud, never silent ------
    if checks.get("expect_qmark"):
        ck(gen["repro"] is not None and gen["proc_error"] is None,
           "repro built", "proc_error=%s" % gen["proc_error"])
        ck("?" in repro, "contains ? placeholder", "no ? in repro")
        ck(QMARK_WARNING in repro, "missing-parameter warning fires",
           "warning text absent from repro")
        for v in checks.get("decls_contain", []):
            ck(v in repro, "decls contain: %s" % v, "not found in repro")
        # documented behavior: it must NOT silently pass with a wrong value.
        ck(ex is not None and ex["exec_result"] != "PASS",
           "repro fails loud (not a silent wrong result)",
           "exec_result=%s" % (ex["exec_result"] if ex else None))
        return out

    # ----- echo cases: assert the actually-bound values --------------------
    if "echo_expect" in checks:
        exp = checks["echo_expect"]
        ck(gen["repro"] is not None and gen["proc_error"] is None,
           "echo repro built", "proc_error=%s" % gen["proc_error"])
        ck(ex["exec_result"] == "PASS", "echo repro executes",
           "exec_result=%s" % ex["exec_result"])
        got = ex["echo"]
        ck(got is not None, "echo captured",
           "no ECHO line (exec_result=%s)" % ex["exec_result"])
        if got:
            for k in ("a", "s", "b"):
                ck(got[k] == exp[k], "echo %s == %r" % (k, exp[k]), "got %r" % got[k])
        return out

    # ----- normal cases ----------------------------------------------------
    ck(gen["repro"] is not None and gen["proc_error"] is None,
       "repro built without proc error",
       "proc_error=%s no_repro=%s" % (gen["proc_error"], gen["no_repro"]))

    if checks.get("min_repro_len"):
        ck(len(repro) >= checks["min_repro_len"],
           "repro length >= %d" % checks["min_repro_len"], "len=%d" % len(repro))

    if checks.get("stmt_contains"):
        ck(checks["stmt_contains"] in repro, "statement text preserved",
           "missing %r" % checks["stmt_contains"])

    if checks.get("repro_contains"):
        ck(checks["repro_contains"] in repro, "value not truncated (marker present)",
           "marker %r absent" % checks["repro_contains"])

    for v in (checks.get("values_present") or []):
        ck(v in repro, "value present: %s" % v, "not found in repro")

    # parameter declaration count + types
    if checks.get("expect_params") is not None:
        expect = checks["expect_params"]
        body = repro[repro.find("EXECUTE sys.sp_executesql"):] \
            if "EXECUTE sys.sp_executesql" in repro else ""
        segs = sql_literal_segments(body)
        if len(segs) >= 2:
            decls = segs[1][2]
            got_names = re.findall(r"@\w+", decls)
            ck(len(got_names) == len(expect), "param count == %d" % len(expect),
               "got %d (%s)" % (len(got_names), decls[:160]))
            for (nm, dt) in expect:
                pat = re.escape(nm) + r"\s+" + re.escape(dt) + r"(?:\s*,|\s*$)"
                ck(re.search(pat, decls) is not None,
                   "decl %s %s present" % (nm, dt), "decls=%s" % decls[:200])
        else:
            ck(False, "sp_executesql decls found", "segments=%d" % len(segs))

    # declaration list and value list must be positionally consistent
    if checks.get("align_check"):
        body = repro[repro.find("EXECUTE sys.sp_executesql"):] \
            if "EXECUTE sys.sp_executesql" in repro else ""
        segs = sql_literal_segments(body)
        if len(segs) >= 2:
            decls = segs[1][2]
            parts = [p.strip() for p in re.split(r",\s*(?=@)", decls) if p.strip()]
            names = []
            for p in parts:
                mm = re.match(r"(@\w+)\s+(.+)", p)
                if mm:
                    names.append((mm.group(1), mm.group(2).strip()))
            after = body[segs[1][1] + 1:].split(";", 1)[0]
            after = after.lstrip().lstrip(",").lstrip()
            vals = split_top_values(after)
            ck(len(names) == len(vals), "decl count == value count",
               "decls=%d vals=%d :: %s || %s" % (len(names), len(vals), decls[:120], after[:120]))
            for ((nm, dt), val) in zip(names, vals):
                dtl = dt.strip().lower()
                v = val.strip()
                if dtl.startswith(("numeric", "decimal", "int", "bigint", "smallint",
                                   "tinyint", "float", "real", "money")):
                    ck(not v.startswith("N'") and not v.startswith("'"),
                       "numeric param %s not bound to a string value" % nm, "val=%r" % v)
                if dtl.startswith(("nvarchar", "varchar", "nchar", "char", "sysname")):
                    ck(v.startswith("N'") or v.startswith("'") or v in ("NULL", "?"),
                       "string param %s bound to a string value" % nm, "val=%r" % v)
        else:
            ck(False, "align: sp_executesql decls found", "segments=%d" % len(segs))

    # the point of the whole thing: it must RUN, not just parse
    if checks.get("must_exec"):
        ck(ex is not None and ex["exec_result"] == "PASS",
           "repro EXECUTES (runs, not just parses)",
           "exec_result=%s" % (ex["exec_result"] if ex else None))
        ck(not (ex or {}).get("sql_errors"),
           "no severe SQL error during execution", str((ex or {}).get("sql_errors")))

    return out


# ------------------------------------------------------------------ fixture

FIXTURE_SETUP = """\
SET NOCOUNT ON;
IF OBJECT_ID('tempdb.dbo.qrb_repro_fixture') IS NOT NULL
    DROP TABLE tempdb.dbo.qrb_repro_fixture;
CREATE TABLE tempdb.dbo.qrb_repro_fixture
(
    id integer NOT NULL,
    val integer NOT NULL,
    name nvarchar(50) NULL
);
INSERT tempdb.dbo.qrb_repro_fixture (id, val, name)
VALUES (1, 10, N'a'), (2, 20, N'b'), (3, 30, N'c');
"""

FIXTURE_TEARDOWN = """\
IF OBJECT_ID('tempdb.dbo.qrb_repro_fixture') IS NOT NULL
    DROP TABLE tempdb.dbo.qrb_repro_fixture;
"""


def _run_inline(server, password, sql, tag):
    path = os.path.join(WORKDIR, "_%s.sql" % tag)
    _write_sql(path, sql)
    return _run_sql_file(server, password, path)


# ------------------------------------------------------------------ main

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--server", default="SQL2022")
    ap.add_argument("--password", default="L!nt0044")
    ap.add_argument("--only", default=None, help="substring filter on case name")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    # A failure detail can contain non-ASCII (e.g. the unicode case); make sure
    # printing it never crashes on a Windows console code page.
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

    print("Running sp_QueryReproBuilder generate-and-execute tests against %s..." % args.server)
    print()

    setup_out = _run_inline(args.server, args.password, FIXTURE_SETUP, "fixture_setup")
    setup_err = find_sql_errors(setup_out)
    if setup_err:
        print("ERROR: could not create the tempdb fixture:")
        for e in setup_err:
            print("  " + e)
        sys.exit(1)

    cases = build_cases()
    if args.only:
        cases = [c for c in cases if args.only in c["name"]]

    results = []
    try:
        for case in cases:
            gen = generate(args.server, args.password, case["plan"])
            ex = None
            need_exec = ("echo_expect" in case["checks"]
                         or case["checks"].get("must_exec")
                         or case["checks"].get("expect_qmark"))
            if gen["repro"] is not None and need_exec:
                ex = execute(args.server, args.password, gen["repro"], echo=case["echo"])
            checks = check_case(case, gen, ex)
            case_failed = any(not ok for (ok, _l, _d) in checks)
            for (ok, label, detail) in checks:
                results.append((case["name"], ok, label, detail))
            if case_failed and not args.verbose:
                exr = ex["exec_result"] if ex else None
                print("FAIL  %s" % case["name"])
                for (ok, label, detail) in checks:
                    if not ok:
                        print("        - %s :: %s" % (label, detail))
                print("        exec_result=%s proc_error=%s" % (exr, gen["proc_error"]))
                if gen["repro"]:
                    print("        repro[:300]=%s" % gen["repro"][:300].replace("\n", "\\n"))
            elif not case_failed:
                print("PASS  %s" % case["name"])
                if args.verbose:
                    for (ok, label, detail) in checks:
                        print("        - %s" % label)
    finally:
        _run_inline(args.server, args.password, FIXTURE_TEARDOWN, "fixture_teardown")

    passed = sum(1 for (_n, ok, _l, _d) in results if ok)
    failed = sum(1 for (_n, ok, _l, _d) in results if not ok)

    print()
    print("Results: %d passed, %d failed, %d total" % (passed, failed, len(results)))

    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
