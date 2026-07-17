"""
sp_IndexCleanup Adversarial Test Runner
=======================================
Runs adversarial_test.sql, captures output, and validates expected results.

Usage:
    python run_tests.py [--server SQL2022] [--password "L!nt0044"]
"""

import subprocess
import sys
import re


def find_sql_errors(text):
    """Return any SQL errors of severity 16 or higher found in text.

    go-sqlcmd reports errors on stdout, so both streams have to be checked.
    Matching the severity numerically catches Level 16 through 19 rather than
    only the literal "Level 16".
    """
    if not text:
        return []

    return re.findall(r"Msg \d+, Level 1[6-9][^\n]*", text)


def run_sqlcmd(server, password):
    """Run the test SQL and capture output."""
    cmd = [
        "sqlcmd", "-S", server, "-U", "sa", "-P", password,
        "-d", "StackOverflow2013",
        "-i", "adversarial_test.sql",
        "-W",  # trim trailing spaces
        "-s", "\t",  # tab delimiter
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
    return result.stdout, result.stderr


def parse_output(stdout):
    """Parse sp_IndexCleanup tab-delimited output into rows."""
    rows = []
    lines = stdout.split("\n")
    headers = None

    for line in lines:
        if not line.strip():
            continue
        if "script_type" in line and "index_name" in line:
            headers = [h.strip() for h in line.split("\t")]
            continue
        if headers and line.startswith("---"):
            continue
        if headers and len(line.split("\t")) >= 6:
            cols = [c.strip() for c in line.split("\t")]
            if len(cols) >= len(headers):
                row = dict(zip(headers, cols))
                rows.append(row)

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


def run_tests(rows):
    """Run all assertions and return results."""
    results = []

    def assert_test(group, name, condition, detail=""):
        results.append({
            "group": group,
            "name": name,
            "passed": condition,
            "detail": detail,
        })

    # ---- Group 1: UC as superset (#721, #724) ----

    # 1a: NC subset of UC → DISABLE
    matches = find_rows(rows, table_name="test_ic_uc", index_name="ix_uc_ab",
                        script_type="DISABLE SCRIPT")
    assert_test("1-UC", "1a: NC subset of UC flagged DISABLE",
                len(matches) == 1, f"found {len(matches)}")

    # 1a: A unique CONSTRAINT must NOT be picked as the wider merge target.
    #
    # These two assertions used to expect the opposite, and the proc used to
    # oblige, emitting:
    #   CREATE UNIQUE INDEX [uq_uc_abc] ... INCLUDE ([col_e])
    #       WITH (DROP_EXISTING = ON, ...)
    # against a constraint-backed index. SQL Server rejects that outright with
    # Msg 1907 ("The new index definition does not match the constraint being
    # enforced by the existing index") - verified on 2016/2019/2022/2025. The
    # paired DISABLE of the subset ran fine, so the net effect was losing a
    # covering index while the constraint never absorbed its include.
    #
    # Contrast with 1d below: a plain unique INDEX does accept DROP_EXISTING
    # with an added INCLUDE, so it remains a valid merge target. The dividing
    # line is is_unique_constraint, not is_unique.
    matches = find_rows(rows, table_name="test_ic_uc", index_name="uq_uc_abc",
                        script_type="MERGE SCRIPT")
    assert_test("1-UC", "1a: UC NOT used as merge target (Msg 1907)",
                len(matches) == 0, f"found {len(matches)} merge rows (expected 0)")

    # 1b: A subset carrying an include the constraint cannot absorb must survive.
    # Disabling it would drop col_e coverage with no working merge to replace it.
    # (ix_uc_ab, which has no includes, is still correctly disabled above: the
    # constraint's keys already cover it, so no script against the constraint is
    # needed.)
    matches = find_rows(rows, table_name="test_ic_uc", index_name="ix_uc_ab_inc",
                        script_type="DISABLE SCRIPT")
    assert_test("1-UC", "1b: NC subset of UC (with includes) NOT disabled",
                len(matches) == 0, f"found {len(matches)} (expected 0)")

    # 1c: NC with non-prefix UC keys → NOT subset
    matches = find_rows(rows, table_name="test_ic_uc", index_name="ix_uc_bc",
                        script_type="DISABLE SCRIPT", additional_info__like="Key Subset")
    assert_test("1-UC", "1c: NC non-prefix keys NOT flagged as subset",
                len(matches) == 0, f"found {len(matches)} (expected 0)")

    # 1d: Unique index as superset → NC subset DISABLE
    matches = find_rows(rows, table_name="test_ic_uc", index_name="ix_uc_ac",
                        script_type="DISABLE SCRIPT")
    assert_test("1-UC", "1d: NC subset of unique index flagged DISABLE",
                len(matches) == 1, f"found {len(matches)}")

    # 1d: Unique index merge → CREATE UNIQUE
    matches = find_rows(rows, table_name="test_ic_uc", index_name="uix_uc_acd",
                        script_type="MERGE SCRIPT")
    has_unique = any("CREATE UNIQUE" in m.get("script", "") for m in matches)
    assert_test("1-UC", "1d: Unique index merge has CREATE UNIQUE",
                has_unique, f"found {len(matches)} merge rows, unique={has_unique}")

    # ---- Group 2: Sort direction ----

    # 2a: Same DESC duplicates → one DISABLE
    matches = find_rows(rows, table_name="test_ic_basic",
                        index_name__in={"ix_sort_a_desc", "ix_sort_a_desc2"},
                        script_type="DISABLE SCRIPT")
    assert_test("2-Sort", "2a: DESC duplicate flagged DISABLE",
                len(matches) >= 1, f"found {len(matches)}")

    # 2c: Subset with different sort → NOT subset
    matches = find_rows(rows, table_name="test_ic_basic", index_name="ix_sort_ab_mixed",
                        script_type="DISABLE SCRIPT", additional_info__like="Key Subset")
    assert_test("2-Sort", "2c: Different sort NOT flagged as subset",
                len(matches) == 0, f"found {len(matches)} (expected 0)")

    # ---- Group 3: Filtered indexes ----

    # 3a: Same filter duplicate → DISABLE
    matches = find_rows(rows, table_name="test_ic_filtered",
                        index_name__in={"ix_filt_a_s1", "ix_filt_a_s1_dup"},
                        script_type="DISABLE SCRIPT")
    assert_test("3-Filter", "3a: Filtered duplicate flagged DISABLE",
                len(matches) >= 1, f"found {len(matches)}")

    # 3b: Different filter → NOT duplicate
    matches = find_rows(rows, table_name="test_ic_filtered", index_name="ix_filt_a_s2",
                        script_type="DISABLE SCRIPT", additional_info__like="Duplicate")
    assert_test("3-Filter", "3b: Different filter NOT flagged duplicate",
                len(matches) == 0, f"found {len(matches)} (expected 0)")

    # 3c: Subset with same filter → DISABLE
    matches = find_rows(rows, table_name="test_ic_filtered", index_name="ix_filt_a_s3",
                        script_type="DISABLE SCRIPT")
    assert_test("3-Filter", "3c: Filtered subset flagged DISABLE",
                len(matches) == 1, f"found {len(matches)}")

    # 3d: Subset with different filter → NOT subset
    matches = find_rows(rows, table_name="test_ic_filtered", index_name="ix_filt_a_s0",
                        script_type="DISABLE SCRIPT", additional_info__like="Key Subset")
    assert_test("3-Filter", "3d: Different filter NOT flagged as subset",
                len(matches) == 0, f"found {len(matches)} (expected 0)")

    # ---- Group 4: Include merges ----

    # 4a: Same keys, different includes → one gets MERGE SCRIPT
    matches = find_rows(rows, table_name="test_ic_basic",
                        index_name__in={"ix_inc_f_inc_b", "ix_inc_f_inc_c"},
                        script_type="MERGE SCRIPT")
    assert_test("4-Includes", "4a: Key dup with different includes gets MERGE",
                len(matches) >= 1, f"found {len(matches)}")

    # 4a: The other gets DISABLE
    matches = find_rows(rows, table_name="test_ic_basic",
                        index_name__in={"ix_inc_f_inc_b", "ix_inc_f_inc_c"},
                        script_type="DISABLE SCRIPT")
    assert_test("4-Includes", "4a: Key dup loser gets DISABLE",
                len(matches) >= 1, f"found {len(matches)}")

    # 4b: Key subset with includes → DISABLE
    matches = find_rows(rows, table_name="test_ic_basic", index_name="ix_inc_c_inc_b",
                        script_type="DISABLE SCRIPT")
    assert_test("4-Includes", "4b: Key subset (with includes) flagged DISABLE",
                len(matches) == 1, f"found {len(matches)}")

    # ---- Group 5: Indexed view ----

    # 5a: Duplicate NC on indexed view → DISABLE
    matches = find_rows(rows, table_name="test_ic_view",
                        index_name__in={"ix_view_a", "ix_view_a_dup"},
                        script_type="DISABLE SCRIPT")
    assert_test("5-View", "5a: Duplicate NC on view flagged DISABLE",
                len(matches) >= 1, f"found {len(matches)}")

    # ---- Group 6: Heap ----

    # 6a: Duplicate on heap → DISABLE
    matches = find_rows(rows, table_name="test_ic_heap",
                        index_name__in={"ix_heap_a", "ix_heap_a_dup"},
                        script_type="DISABLE SCRIPT")
    assert_test("6-Heap", "6a: Duplicate on heap flagged DISABLE",
                len(matches) >= 1, f"found {len(matches)}")

    # ---- Group 7: Cross-table isolation ----

    # 7a: Different tables should NOT interact
    matches = find_rows(rows, table_name="test_ic_multi", index_name="ix_multi_a",
                        script_type="DISABLE SCRIPT", additional_info__like="Duplicate")
    assert_test("7-Isolation", "7a: Cross-table NOT flagged as duplicate",
                len(matches) == 0, f"found {len(matches)} (expected 0)")

    # ---- Group 8: Exact Duplicate ----

    # 8a: Same keys AND same includes → one DISABLE
    matches = find_rows(rows, table_name="test_ic_exact",
                        index_name__in={"ix_exact_ab_1", "ix_exact_ab_2"},
                        script_type="DISABLE SCRIPT")
    assert_test("8-Exact-Dup", "8a: Exact duplicate flagged DISABLE",
                len(matches) >= 1, f"found {len(matches)}")

    # ---- Group 9: Reverse Duplicate ----

    # 9a: Different leading column order → NOT flagged (by design — different query patterns)
    matches = find_rows(rows, table_name="test_ic_reverse",
                        index_name__in={"ix_rev_ab", "ix_rev_ba"},
                        script_type="DISABLE SCRIPT")
    assert_test("9-Reverse", "9a: Different leading col NOT flagged DISABLE (by design)",
                len(matches) == 0, f"found {len(matches)} (expected 0)")

    # ---- Group 10: Equal Except For Filter ----

    # 10a: Same keys, one filtered one not → should NOT be duplicates
    matches = find_rows(rows, table_name="test_ic_filter_eq", index_name="ix_feq_a_filt",
                        script_type="DISABLE SCRIPT", additional_info__like="Duplicate")
    assert_test("10-FilterEq", "10a: Filtered vs unfiltered NOT flagged duplicate",
                len(matches) == 0, f"found {len(matches)} (expected 0)")

    # ---- Group 11: UC Replacement (Rule 7/7.5) ----

    # 11a: UC exact match with NC that has includes → UC gets DROP CONSTRAINT
    matches = find_rows(rows, table_name="test_ic_uc_replace", index_name="uq_ucr_ab",
                        script_type="DISABLE CONSTRAINT SCRIPT")
    assert_test("11-UC-Replace", "11a: UC with exact-match NC gets DROP CONSTRAINT",
                len(matches) == 1, f"found {len(matches)}")

    # 11b: NC with includes gets MAKE UNIQUE (MERGE SCRIPT with CREATE UNIQUE)
    matches = find_rows(rows, table_name="test_ic_uc_replace", index_name="ix_ucr_ab_inc",
                        script_type="MERGE SCRIPT")
    has_unique = any("CREATE UNIQUE" in m.get("script", "") for m in matches)
    assert_test("11-UC-Replace", "11b: NC replacement has CREATE UNIQUE",
                has_unique, f"found {len(matches)} merge rows, unique={has_unique}")

    # 11c: UC-vs-UC duplicates with no NC sibling (issue #782, Rule 7.5b)
    # Keeper (alphabetically first) must NOT be dropped
    matches = find_rows(rows, table_name="test_ic_uc_dup", index_name="uq_ucd_keeper",
                        script_type="DISABLE CONSTRAINT SCRIPT")
    assert_test("11-UC-Replace", "11c: Duplicate UC keeper NOT dropped (#782)",
                len(matches) == 0, f"found {len(matches)} (expected 0)")

    # 11d: Loser UC must get exactly one DROP CONSTRAINT pointing at the keeper
    matches = find_rows(rows, table_name="test_ic_uc_dup", index_name="uq_ucd_zloser",
                        script_type="DISABLE CONSTRAINT SCRIPT")
    target_ok = len(matches) == 1 and matches[0].get("target_index_name") == "uq_ucd_keeper"
    assert_test("11-UC-Replace", "11d: Duplicate UC loser dropped, target = keeper (#782)",
                target_ok, f"found {len(matches)} drops, target={matches[0].get('target_index_name') if matches else None}")

    # ---- Group 12: Rule interactions ----

    # 12a: Multi-level subset: ix_int_a ⊂ ix_int_ab ⊂ ix_int_abc
    # Narrowest (ix_int_a) should be DISABLE
    matches = find_rows(rows, table_name="test_ic_interact", index_name="ix_int_a",
                        script_type="DISABLE SCRIPT")
    assert_test("12-Interact", "12a: Narrowest subset (A) flagged DISABLE",
                len(matches) == 1, f"found {len(matches)}")

    # Middle (ix_int_ab) should also be DISABLE
    matches = find_rows(rows, table_name="test_ic_interact", index_name="ix_int_ab",
                        script_type="DISABLE SCRIPT")
    assert_test("12-Interact", "12a: Middle subset (AB) flagged DISABLE",
                len(matches) == 1, f"found {len(matches)}")

    # Widest (ix_int_abc) should survive (MERGE or COMPRESSION, not DISABLE)
    matches = find_rows(rows, table_name="test_ic_interact", index_name="ix_int_abc",
                        script_type="DISABLE SCRIPT")
    assert_test("12-Interact", "12a: Widest (ABC) NOT disabled",
                len(matches) == 0, f"found {len(matches)} (expected 0)")

    # 12b: UC + NC + subset on same table
    # 12b: UC + key-duplicate NC + key-subset NC on the same table.
    #
    # This was skipped for a long time with a comment saying these three indexes
    # "don't appear in output at all -- needs investigation". They were absent
    # because the FIXTURE was broken, not the procedure: col_c and col_d were
    # random values from 200 and 100 buckets across 10,000 rows, so
    # uq_int_cd UNIQUE (col_c, col_d) failed to create on every run (Msg 1505),
    # and the read loop then aborted hinting the missing index (Msg 308). The
    # runner could not see any of it because it checked stderr and go-sqlcmd
    # reports errors on stdout. Both are fixed; on clean data the procedure gets
    # this group right.

    # 12b: the constraint is replaced by its nonclustered twin
    matches = find_rows(rows, table_name="test_ic_interact", index_name="uq_int_cd",
                        script_type="DISABLE CONSTRAINT SCRIPT")
    assert_test("12-Interact", "12b: uq_int_cd constraint dropped for ix_int_cd",
                len(matches) == 1, f"found {len(matches)}")

    # 12b: that twin is made unique
    matches = find_rows(rows, table_name="test_ic_interact", index_name="ix_int_cd",
                        script_type="MERGE SCRIPT")
    has_unique = any("CREATE UNIQUE" in m.get("script", "") for m in matches)
    assert_test("12-Interact", "12b: ix_int_cd made unique to replace the constraint",
                has_unique, f"found {len(matches)} merge rows, unique={has_unique}")

    # 12b: the key subset is disabled into it
    matches = find_rows(rows, table_name="test_ic_interact", index_name="ix_int_c",
                        script_type="DISABLE SCRIPT")
    assert_test("12-Interact", "12b: ix_int_c (key subset) disabled",
                len(matches) == 1, f"found {len(matches)}")

    # 12b: THE load-bearing one. ix_int_c is being disabled, so whatever it
    # covered has to survive in the index replacing it. Rule 6 merges col_b in as
    # a Key Subset; Rule 7.5 then rewrites the row to MAKE UNIQUE and Rule 7.6
    # recomputes the includes. A 7.6 that gathers only Key Duplicate losers drops
    # col_b here while ix_int_c's DISABLE still runs -- coverage silently gone on
    # scripts that all execute cleanly, which the execute check cannot see.
    matches = find_rows(rows, table_name="test_ic_interact", index_name="ix_int_cd",
                        script_type="MERGE SCRIPT")
    script = matches[0].get("script", "") if matches else ""
    include = script[script.find("INCLUDE"):script.find(")", script.find("INCLUDE")) + 1] if "INCLUDE" in script else ""
    kept_subset_col = "col_b" in include
    kept_own_col = "col_e" in include
    assert_test("12-Interact", "12b: merge keeps BOTH its own include and the disabled subset's",
                kept_subset_col and kept_own_col,
                f"INCLUDE={include or '(none)'} col_b={kept_subset_col} col_e={kept_own_col}")

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

    print(f"Running adversarial tests against {server}...")
    print()

    stdout, stderr = run_sqlcmd(server, password)

    # go-sqlcmd writes SQL errors to STDOUT, not stderr. Checking stderr alone
    # made this detection decorative: adversarial_test.sql was failing partway
    # through on every run (Msg 1505 on test_ic_interact) and the suite stayed
    # green, so group 12 was never really tested. Check both streams, and match
    # any severity 16+ rather than the literal string "Level 16".
    errors = find_sql_errors(stdout) + find_sql_errors(stderr)

    if errors:
        print("ERROR: SQL errors detected while running the fixture:")
        for e in errors:
            print("  " + e)
        print()
        print("The fixture did not build correctly, so the assertions below")
        print("would be testing something other than what they claim.")
        sys.exit(1)

    rows = parse_output(stdout)
    print(f"Captured {len(rows)} output rows from sp_IndexCleanup")
    print()

    if len(rows) == 0:
        print("ERROR: No output rows captured. Check SQL setup.")
        print("stderr:", stderr[:500] if stderr else "(empty)")
        sys.exit(1)

    results = run_tests(rows)

    # Report
    passed = sum(1 for r in results if r["passed"])
    failed = sum(1 for r in results if not r["passed"])

    for r in results:
        status = "PASS" if r["passed"] else "FAIL"
        print(f"  [{status}] {r['group']}: {r['name']}  ({r['detail']})")

    print()
    print(f"Results: {passed} passed, {failed} failed, {len(results)} total")

    if failed > 0:
        print()
        print("FAILED TESTS:")
        for r in results:
            if not r["passed"]:
                print(f"  {r['group']}: {r['name']}  ({r['detail']})")
        sys.exit(1)
    else:
        print("All tests passed!")


if __name__ == "__main__":
    main()
