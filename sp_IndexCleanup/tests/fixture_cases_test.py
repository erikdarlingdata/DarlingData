"""
sp_IndexCleanup Fixture Case Assertions
=======================================
Drives fixtures_more_dupe_indexes.sql and asserts the "Expected:" comments in it.
Those comments are the specification: two of them caught bugs that shipped, that
compiled cleanly, and that the adversarial suite did not cover. Until now nothing
asserted them automatically -- the README called wiring them up "the most
valuable improvement available to this directory". This is that.

The fixture is self-contained: it drops every nonclustered index in the database,
builds cases 1 through 8d on StackOverflow2013.dbo.Users, drives reads through
each one, and ends by running the procedure with @dedupe_only = 1. It takes about
two minutes, most of it in the read-generation loop.

HOW GENERATED SCRIPTS ARE VALIDATED: they are EXECUTED, not parsed.

Every MERGE SCRIPT, DISABLE SCRIPT, and DISABLE CONSTRAINT SCRIPT in the output
is run for real, each inside its own BEGIN TRANSACTION ... ROLLBACK, via
sp_executesql inside TRY/CATCH so that a compile error surfaces as a catchable
error rather than killing the batch. Each script is rolled back individually, so
database state is identical before and after and the captured output stays valid.

This matters, and SET PARSEONLY ON would not do. Every bug found in this
procedure so far had the same shape: a script that reads correctly and parses
correctly but cannot execute. The canonical example is case 7c, where the
procedure emitted a merge into a unique constraint and SQL Server rejected it
with Msg 1907 ("The new index definition does not match the constraint being
enforced by the existing index") -- a semantic error that PARSEONLY sails right
past, while the paired DISABLE ran fine and quietly cost a covering index.
Executing is the only check that tells the two apart.

Cleanup: drops the three unique constraints (uq_test_c1/c2/c3 -- DropIndexes does
not reliably remove constraints) and runs StackOverflow2013.dbo.DropIndexes.

Prerequisites:
  - A scratch StackOverflow2013 (the fixture drops every nonclustered index).
  - A dbo.DropIndexes helper procedure in that database.
  - sp_IndexCleanup installed in master.

Usage:
    python fixture_cases_test.py [--server SQL2022] [--password "L!nt0044"]
"""

import os
import re
import shlex
import subprocess
import sys
import tempfile


HERE = os.path.dirname(os.path.abspath(__file__))
FIXTURE_FILE = os.path.join(HERE, "fixtures_more_dupe_indexes.sql")


def _sqlcmd_prefix():
    """The sqlcmd binary plus any connection args, overridable via environment
    so the harness runs both locally and in CI. Locally SQLCMD_BIN defaults to
    'sqlcmd' on PATH and SQLCMD_CONN_ARGS is empty; CI sets SQLCMD_BIN to the
    go-based sqlcmd and SQLCMD_CONN_ARGS to '-C -N disable' -- trust the
    container's self-signed cert and disable encryption, which the modern Go
    TLS stack needs to connect to the SQL Server 2017 container."""
    return [os.environ.get("SQLCMD_BIN", "sqlcmd")] + shlex.split(
        os.environ.get("SQLCMD_CONN_ARGS", ""))

# Rows that represent a dedupe action. A COMPRESSION SCRIPT row is not one of
# these: an index that gets no dedupe action still gets compression advice, and
# that is expected, so "no dedupe action" means none of these three.
DEDUPE_SCRIPT_TYPES = ("DISABLE SCRIPT", "MERGE SCRIPT", "DISABLE CONSTRAINT SCRIPT")


def run_sqlcmd(server, password, input_file=None, query=None,
               database="StackOverflow2013", timeout=600):
    """Run SQL from a file or a query string and capture output."""
    cmd = [
        *_sqlcmd_prefix(),
        "-S", server, "-U", "sa", "-P", password,
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


def parse_output(stdout):
    """
    Parse sp_IndexCleanup tab-delimited output into rows.

    Bounded to the script result set. The procedure emits several result sets and
    the ones after this share nothing but a tab delimiter, so parsing stops at the
    blank line that ends this one. Without that bound the summary rows get zipped
    against these headers and land in the same list, which matters here because
    several assertions below are assertions of absence.

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
            # Blank line ends the result set once rows have started.
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


def include_columns(script):
    """The contents of a script's INCLUDE (...) clause, or '' if it has none."""
    match = re.search(r"INCLUDE\s*\(([^)]*)\)", script or "", re.IGNORECASE)
    return match.group(1) if match else ""


def script_rows(rows):
    """Every generated script row worth executing, in output order."""
    seen = []
    for r in rows:
        if r.get("script_type") not in DEDUPE_SCRIPT_TYPES:
            continue
        script = r.get("script", "")
        if not script or script == "NULL":
            continue
        seen.append(r)
    return seen


def validate_scripts(server, password, rows):
    """
    Execute every generated script inside its own rolled-back transaction.

    sp_executesql inside TRY/CATCH, so a compile error in a generated script is
    catchable instead of aborting the batch. Returns a list of
    (index_name, script_type, error_or_None).
    """
    targets = script_rows(rows)
    if not targets:
        return []

    batches = [
        "SET NOCOUNT ON;",
        "SET XACT_ABORT OFF;",
    ]
    for i, r in enumerate(targets):
        escaped = r["script"].replace("'", "''")
        tag = "SCRIPTCHECK~%d~" % i
        batches.append(
            "BEGIN TRY\n"
            "    BEGIN TRANSACTION;\n"
            "    EXECUTE sys.sp_executesql N'" + escaped + "';\n"
            "    IF @@TRANCOUNT > 0 ROLLBACK;\n"
            "    SELECT r = CONVERT(varchar(1000), '" + tag + "OK');\n"
            "END TRY\n"
            "BEGIN CATCH\n"
            "    IF @@TRANCOUNT > 0 ROLLBACK;\n"
            "    SELECT r = CONVERT(varchar(1000), '" + tag + "ERROR: Msg ' + "
            "CONVERT(varchar(10), ERROR_NUMBER()) + ' - ' + ERROR_MESSAGE());\n"
            "END CATCH;"
        )

    path = None
    try:
        handle, path = tempfile.mkstemp(suffix=".sql", prefix="ic_scriptcheck_")
        with os.fdopen(handle, "w") as f:
            f.write("\nGO\n".join(batches) + "\nGO\n")

        stdout, _ = run_sqlcmd(server, password, input_file=path, timeout=600)
    finally:
        if path and os.path.exists(path):
            os.remove(path)

    results = {}
    for line in stdout.split("\n"):
        line = line.strip()
        if not line.startswith("SCRIPTCHECK~"):
            continue
        _, index, outcome = line.split("~", 2)
        results[int(index)] = outcome

    out = []
    for i, r in enumerate(targets):
        outcome = results.get(i)
        if outcome is None:
            error = "no result captured for this script"
        elif outcome == "OK":
            error = None
        else:
            error = outcome
        out.append((r["index_name"], r["script_type"], error))
    return out


def run_tests(rows, script_results):
    """Run all assertions and return results."""
    results = []

    def assert_test(group, name, condition, detail=""):
        results.append({
            "group": group,
            "name": name,
            "passed": condition,
            "detail": detail,
        })

    # ---- Case 1: Exact duplicates (same keys, same includes) ----
    # ix_test_1 / ix_test_2 on (DisplayName) INCLUDE (Reputation).

    matches = find_rows(rows, table_name="Users", index_name="ix_test_2",
                        script_type="DISABLE SCRIPT")
    assert_test("1-Exact-Dup", "ix_test_2 disabled (exact duplicate of ix_test_1)",
                len(matches) == 1, "found %d" % len(matches))

    # ---- Case 2: Key duplicates with different includes ----
    # ix_test_3 INCLUDE (Reputation) / ix_test_4 INCLUDE (UpVotes) on (AccountId).
    # Expected: one kept with includes merged, other disabled.

    matches = find_rows(rows, table_name="Users", index_name="ix_test_4",
                        script_type="DISABLE SCRIPT")
    assert_test("2-Key-Dup", "ix_test_4 disabled (key duplicate of ix_test_3)",
                len(matches) == 1, "found %d" % len(matches))

    matches = find_rows(rows, table_name="Users", index_name="ix_test_3",
                        script_type="MERGE SCRIPT")
    includes = include_columns(matches[0]["script"]) if matches else ""
    merged = ("Reputation" in includes) and ("UpVotes" in includes)
    assert_test("2-Key-Dup", "ix_test_3 merged, INCLUDE has both Reputation and UpVotes",
                len(matches) == 1 and merged,
                "found %d merge rows, INCLUDE=(%s)" % (len(matches), includes))

    # ---- Case 3: Key duplicates, one a unique INDEX ----
    # uq_test_1 UNIQUE (Location, Id) / ix_test_5 (Location, Id) INCLUDE
    # (LastAccessDate). Expected: unique index kept, includes merged in.
    #
    # This is one of the two cases that caught a shipped bug: ix_test_5 used to be
    # disabled with uq_test_1 as its target while nothing merged the include into
    # uq_test_1, silently dropping LastAccessDate coverage. Unlike a constraint, a
    # plain unique index does accept DROP_EXISTING with an added INCLUDE, so the
    # merge is legal and must happen.

    matches = find_rows(rows, table_name="Users", index_name="uq_test_1",
                        script_type="MERGE SCRIPT")
    script = matches[0]["script"] if matches else ""
    assert_test("3-Unique-Index", "uq_test_1 merged and script has CREATE UNIQUE",
                len(matches) == 1 and "CREATE UNIQUE" in script,
                "found %d merge rows, CREATE UNIQUE=%s"
                % (len(matches), "CREATE UNIQUE" in script))

    includes = include_columns(script)
    assert_test("3-Unique-Index", "uq_test_1 INCLUDE absorbed LastAccessDate",
                "LastAccessDate" in includes, "INCLUDE=(%s)" % includes)

    matches = find_rows(rows, table_name="Users", index_name="ix_test_5",
                        script_type="DISABLE SCRIPT")
    assert_test("3-Unique-Index", "ix_test_5 disabled (its include went to uq_test_1)",
                len(matches) == 1, "found %d" % len(matches))

    # ---- Case 4: Superset/subset keys, neither unique ----
    # ix_test_6 (Age) is a subset of ix_test_7 (Age, CreationDate).

    matches = find_rows(rows, table_name="Users", index_name="ix_test_6",
                        script_type="DISABLE SCRIPT")
    assert_test("4-Key-Subset", "ix_test_6 disabled (subset of ix_test_7)",
                len(matches) == 1, "found %d" % len(matches))

    # ---- Case 5: Superset/subset with a unique narrower index ----
    # uq_test_2 UNIQUE (EmailHash, Id) / ix_test_8 (EmailHash, Id, WebsiteUrl).
    # Expected: both kept. A unique index must not be folded into a wider
    # non-unique one -- the wider index cannot enforce the uniqueness.

    matches = dedupe_rows(rows, "uq_test_2")
    assert_test("5-Unique-Subset", "uq_test_2 gets no dedupe action",
                len(matches) == 0,
                "found %d (%s)" % (len(matches), [m["script_type"] for m in matches]))

    matches = dedupe_rows(rows, "ix_test_8")
    assert_test("5-Unique-Subset", "ix_test_8 gets no dedupe action",
                len(matches) == 0,
                "found %d (%s)" % (len(matches), [m["script_type"] for m in matches]))

    # ---- Case 6: Mismatched key orders (Rule 8) ----
    # ix_test_9 (CreationDate, LastAccessDate, Views) vs
    # ix_test_10 (CreationDate, Views, LastAccessDate).
    # Expected: flagged "Same Keys Different Order" for review. This surfaces as
    # an analysis report row with script_type NEEDS REVIEW and a NULL script, not
    # as generated DDL, so it is not a dedupe action and must not be one.

    matches = [
        r for r in rows
        if r.get("index_name") in ("ix_test_9", "ix_test_10")
        and r.get("script_type") == "NEEDS REVIEW"
        and r.get("consolidation_rule") == "Same Keys Different Order"
    ]
    targets_each_other = all(
        m.get("target_index_name") in ("ix_test_9", "ix_test_10") for m in matches
    )
    assert_test("6-Key-Order", "ix_test_9/ix_test_10 flagged Same Keys Different Order",
                len(matches) >= 1 and targets_each_other,
                "found %d review rows (%s)"
                % (len(matches),
                   [(m["index_name"], m["target_index_name"]) for m in matches]))

    # ---- Case 7a: Unique CONSTRAINT with an exact-match nonclustered index ----
    # uq_test_c1 UNIQUE (DownVotes, Id) / ix_c1 (DownVotes, Id) INCLUDE (AboutMe).
    # Expected: constraint dropped, index made unique to take over enforcement.

    matches = find_rows(rows, table_name="Users", index_name="uq_test_c1",
                        script_type="DISABLE CONSTRAINT SCRIPT")
    assert_test("7a-UC-Replace", "uq_test_c1 gets DISABLE CONSTRAINT",
                len(matches) == 1, "found %d" % len(matches))

    matches = find_rows(rows, table_name="Users", index_name="ix_c1",
                        script_type="MERGE SCRIPT")
    script = matches[0]["script"] if matches else ""
    assert_test("7a-UC-Replace", "ix_c1 merged and script has CREATE UNIQUE",
                len(matches) == 1 and "CREATE UNIQUE" in script,
                "found %d merge rows, CREATE UNIQUE=%s"
                % (len(matches), "CREATE UNIQUE" in script))

    # ---- Case 7b: Unique constraint vs a WIDER nonclustered index ----
    # uq_test_c2 UNIQUE (UpVotes, Id) / ix_c2 (UpVotes, Id, Reputation).
    # Expected: no action, keys do not match exactly.

    matches = dedupe_rows(rows, "uq_test_c2")
    assert_test("7b-UC-Wider-NC", "uq_test_c2 gets no dedupe action",
                len(matches) == 0,
                "found %d (%s)" % (len(matches), [m["script_type"] for m in matches]))

    matches = dedupe_rows(rows, "ix_c2")
    assert_test("7b-UC-Wider-NC", "ix_c2 gets no dedupe action",
                len(matches) == 0,
                "found %d (%s)" % (len(matches), [m["script_type"] for m in matches]))

    # ---- Case 7c: Unique constraint WIDER than the nonclustered index ----
    # uq_test_c3 UNIQUE (Id, DisplayName) / ix_c3 (Id) INCLUDE (LastAccessDate).
    # Expected: no action, keys do not match exactly.
    #
    # Load-bearing. The procedure used to emit a merge into the constraint --
    # CREATE INDEX ... WITH (DROP_EXISTING = ON) against a constraint-backed
    # index, which SQL Server rejects with Msg 1907 -- while still emitting a
    # runnable DISABLE of ix_c3. The merge failed, the disable succeeded, and
    # ix_c3's LastAccessDate coverage vanished with nothing absorbing it. The
    # dividing line is is_unique_constraint, not is_unique: contrast case 3,
    # where a plain unique index is a legal merge target.

    matches = dedupe_rows(rows, "uq_test_c3")
    assert_test("7c-UC-Wider", "uq_test_c3 gets no dedupe action (Msg 1907 merge)",
                len(matches) == 0,
                "found %d (%s)" % (len(matches), [m["script_type"] for m in matches]))

    matches = dedupe_rows(rows, "ix_c3")
    assert_test("7c-UC-Wider", "ix_c3 gets no dedupe action (would lose LastAccessDate)",
                len(matches) == 0,
                "found %d (%s)" % (len(matches), [m["script_type"] for m in matches]))

    # ---- Case 8a: Filtered indexes with matching filters ----
    # ix_filtered_1 / ix_filtered_2, both WHERE (Reputation > 1000).

    matches = find_rows(rows, table_name="Users", index_name="ix_filtered_2",
                        script_type="DISABLE SCRIPT")
    assert_test("8a-Filter-Match", "ix_filtered_2 disabled (same filter as ix_filtered_1)",
                len(matches) == 1, "found %d" % len(matches))

    # ---- Case 8b: Filtered index with a different filter ----
    # ix_filtered_3 WHERE (Reputation > 2000). Covers different rows, keep it.

    matches = dedupe_rows(rows, "ix_filtered_3")
    assert_test("8b-Filter-Diff", "ix_filtered_3 gets no dedupe action (different filter)",
                len(matches) == 0,
                "found %d (%s)" % (len(matches), [m["script_type"] for m in matches]))

    # ---- Case 8c: Matching descending sort orders ----
    # ix_desc_1 / ix_desc_2, both (Reputation DESC).

    matches = find_rows(rows, table_name="Users", index_name="ix_desc_2",
                        script_type="DISABLE SCRIPT")
    assert_test("8c-Sort-Match", "ix_desc_2 disabled (same sort as ix_desc_1)",
                len(matches) == 1, "found %d" % len(matches))

    # ---- Case 8d: Different sort direction ----
    # ix_desc_3 (Reputation ASC). Different ordering, different query patterns.

    matches = dedupe_rows(rows, "ix_desc_3")
    assert_test("8d-Sort-Diff", "ix_desc_3 gets no dedupe action (different sort)",
                len(matches) == 0,
                "found %d (%s)" % (len(matches), [m["script_type"] for m in matches]))

    # ---- Every generated script must actually execute ----
    # A script that reads correctly but cannot run is the bug this procedure keeps
    # producing. Each was executed inside a rolled-back transaction.

    for index_name, script_type, error in script_results:
        assert_test("9-Executable", "%s (%s) executes" % (index_name, script_type),
                    error is None, error if error else "rolled back clean")

    return results


def cleanup(server, password):
    """
    Drop the three unique constraints and every nonclustered index the fixture
    built. DropIndexes does not reliably remove constraints, so they go first and
    explicitly.
    """
    query = """
SET NOCOUNT ON;
IF EXISTS (SELECT 1/0 FROM sys.key_constraints AS kc WHERE kc.name = N'uq_test_c1')
BEGIN
    ALTER TABLE dbo.Users DROP CONSTRAINT uq_test_c1;
END;
IF EXISTS (SELECT 1/0 FROM sys.key_constraints AS kc WHERE kc.name = N'uq_test_c2')
BEGIN
    ALTER TABLE dbo.Users DROP CONSTRAINT uq_test_c2;
END;
IF EXISTS (SELECT 1/0 FROM sys.key_constraints AS kc WHERE kc.name = N'uq_test_c3')
BEGIN
    ALTER TABLE dbo.Users DROP CONSTRAINT uq_test_c3;
END;
EXECUTE StackOverflow2013.dbo.DropIndexes;
"""
    run_sqlcmd(server, password, query=query, timeout=600)


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

    print("Running fixture case tests against %s..." % server)
    print("Building fixtures and generating reads (about two minutes)...")
    print()

    try:
        stdout, stderr = run_sqlcmd(server, password, input_file=FIXTURE_FILE,
                                    timeout=600)

        # go-sqlcmd reports SQL errors on STDOUT, so checking stderr alone made
        # this decorative: a fixture could fail partway through and the suite
        # would still go green, asserting against a half-built schema. Match any
        # severity 16+ on both streams.
        errors = (re.findall(r"Msg \d+, Level 1[6-9][^\n]*", stdout or "") +
                  re.findall(r"Msg \d+, Level 1[6-9][^\n]*", stderr or ""))

        if errors:
            print("ERROR: SQL errors detected while building the fixture:")
            for e in errors:
                print("  " + e)
            print()
            print("The fixture did not build correctly, so the assertions below")
            print("would be testing something other than what they claim.")
            sys.exit(1)

        rows = parse_output(stdout)
        print("Captured %d output rows from sp_IndexCleanup" % len(rows))

        if len(rows) == 0:
            print("ERROR: No output rows captured. Check SQL setup.")
            print("stderr:", stderr[:500] if stderr else "(empty)")
            sys.exit(1)

        targets = script_rows(rows)
        print("Executing %d generated scripts in rolled-back transactions..."
              % len(targets))
        print()
        script_results = validate_scripts(server, password, rows)

        results = run_tests(rows, script_results)
    finally:
        cleanup(server, password)

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
