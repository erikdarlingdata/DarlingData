"""
sp_QueryReproBuilder harness mutation check
===========================================
Proves run_tests.py has teeth. A green test suite is only worth trusting if it
goes RED when the thing it tests is broken, so this planted-bug check:

  1. reads the REAL procedure from the repo (never edits that file),
  2. applies each plausible generation bug to a scratch copy,
  3. installs the mutant into master on the target,
  4. runs run_tests.py and asserts it goes RED (the mutation is CAUGHT), then
  5. restores the real build from the repo file and leaves it installed.

The mutations mirror the three failure modes the task calls out plus one more:
  M1 - value list re-sorted independently of the declaration list
       (silent parameter/value misbinding)
  M2 - every parameter's declared type forced to int
  M4 - statement-apostrophe doubling removed (broken outer N'...' literal)
  M6 - the '?' fill-in placeholder emitted as NULL (would silently run with a
       wrong value instead of failing loud)

Usage:
    python mutation_check.py [--server SQL2022] [--password L!nt0044] [--dry]

--dry only verifies each pattern still matches the current procedure exactly
once (run it after editing sp_QueryReproBuilder.sql to catch anchor drift).
Exits 1 if any mutation SURVIVES (a coverage hole) or the real build cannot be
restored.
"""

import argparse
import atexit
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_PROC = os.path.normpath(os.path.join(HERE, "..", "sp_QueryReproBuilder.sql"))
RUN_TESTS = os.path.join(HERE, "run_tests.py")

WORKDIR = tempfile.mkdtemp(prefix="qrb_mut_")
atexit.register(lambda: shutil.rmtree(WORKDIR, ignore_errors=True))

# Each mutation: (name, pattern, replacement, why it must be caught).
# Every pattern must match the current procedure exactly once; --dry checks that.
MUTATIONS = [
    ("M1_value_list_misalign",
     r"(ISNULL\s*\(\s*qp\.parameter_compiled_value,\s*N'NULL'\s*\)\s*"
     r"FROM #query_parameters AS qp\s*WHERE qp\.plan_id = qsp\.plan_id\s*ORDER BY\s*)"
     r"qp\.parameter_name",
     r"\1qp.parameter_compiled_value DESC",
     "value list re-sorted independently of the decl list -> silent misbinding"),

    ("M2_decl_type_forced_int",
     r"qp\.parameter_name\s*\+\s*N' '\s*\+\s*qp\.parameter_data_type",
     r"qp.parameter_name + N' ' + N'int'",
     "every parameter declared int -> wrong type for numeric/nvarchar/etc."),

    ("M4_no_stmt_apostrophe_doubling",
     r"REPLACE\s*\(\s*clean_query\.query_text_cleaned,\s*N'''',\s*N''''''\s*\)",
     r"clean_query.query_text_cleaned",
     "statement apostrophes not doubled -> broken outer N'...' literal"),

    ("M6_qmark_becomes_null",
     r"(parameter_compiled_value =\s*)N'\?'(\s*FROM #query_store_plan)",
     r"\1N'NULL'\2",
     "missing params default to NULL and silently execute instead of ?"),

    ("M3_scaled_type_split",
     r"REPLACE\(prefix\.param_prefix, N',@', N'</p><p>@'\)",
     r"REPLACE(prefix.param_prefix, N',', N'</p><p>')",
     "fill-in path splits scaled types like numeric(10,2) on the internal comma"),
]


def read_proc():
    with open(REPO_PROC, "r", encoding="utf-8-sig") as f:
        return f.read()


def pattern_check(base):
    print("Pattern match check (each must match exactly once):")
    all_ok = True
    for (name, pat, _repl, _why) in MUTATIONS:
        n = len(re.findall(pat, base, re.DOTALL))
        ok = n == 1
        all_ok = all_ok and ok
        print("  %-32s matches=%d %s" % (name, n, "OK" if ok else "!! DRIFTED"))
    return all_ok


def install(path, server, password, label):
    r = subprocess.run(
        ["sqlcmd", "-S", server, "-U", "sa", "-P", password, "-d", "master",
         "-i", path, "-b"],
        capture_output=True, text=True, timeout=180)
    if r.returncode != 0:
        print("  install(%s) FAILED rc=%d: %s"
              % (label, r.returncode, (r.stdout + r.stderr).strip()[:300]))
        return False
    return True


def run_harness(server, password):
    """Run run_tests.py; return (failed_count, ok) where ok is False if the
    run could not be parsed."""
    r = subprocess.run(
        [sys.executable, RUN_TESTS, "--server", server, "--password", password],
        capture_output=True, text=True, timeout=900)
    m = re.search(r"Results:\s*(\d+) passed,\s*(\d+) failed", r.stdout)
    if not m:
        return None, r.stdout[-800:]
    return int(m.group(2)), None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--server", default="SQL2022")
    ap.add_argument("--password", default="L!nt0044")
    ap.add_argument("--dry", action="store_true")
    args = ap.parse_args()

    base = read_proc()

    all_ok = pattern_check(base)
    if args.dry:
        sys.exit(0 if all_ok else 1)
    if not all_ok:
        print("\nAborting: a mutation pattern no longer matches the procedure "
              "exactly once. Fix the anchors before trusting this check.")
        sys.exit(1)

    mutant_path = os.path.join(WORKDIR, "_mutant.sql")
    results = []
    baseline_failed = None

    try:
        print("\nInstalling the real build (baseline)...")
        if not install(REPO_PROC, args.server, args.password, "repo"):
            print("Could not install the real build; aborting.")
            sys.exit(1)
        baseline_failed, err = run_harness(args.server, args.password)
        if baseline_failed is None:
            print("Could not parse baseline harness output:\n" + (err or ""))
            sys.exit(1)
        print("Baseline: %d failed (expected 0)." % baseline_failed)
        if baseline_failed != 0:
            print("Baseline is not green; fix run_tests.py before mutating.")
            sys.exit(1)

        print("\nApplying mutations:")
        for (name, pat, repl, why) in MUTATIONS:
            mutant = re.sub(pat, repl, base, count=1, flags=re.DOTALL)
            if mutant == base:
                results.append((name, "NOT_APPLIED", why))
                print("  %-32s NOT APPLIED (pattern did not change anything)" % name)
                continue
            with open(mutant_path, "w", encoding="utf-8") as f:
                f.write(mutant)
            if not install(mutant_path, args.server, args.password, name):
                results.append((name, "INSTALL_FAIL", why))
                continue
            failed, err = run_harness(args.server, args.password)
            if failed is None:
                results.append((name, "HARNESS_UNPARSED", why))
                print("  %-32s harness output unparsed:\n%s" % (name, err or ""))
                continue
            caught = failed > baseline_failed
            results.append((name, "CAUGHT" if caught else "SURVIVED", why))
            print("  %-32s -> %s (%d failed)"
                  % (name, "CAUGHT" if caught else "SURVIVED !!", failed))
    finally:
        print("\nRestoring the real build from the repo...")
        restored = install(REPO_PROC, args.server, args.password, "repo-restore")
        if not restored:
            print("!! FAILED to restore the real build. Reinstall manually:")
            print("   sqlcmd -S %s -U sa -P *** -d master -i \"%s\" -b"
                  % (args.server, REPO_PROC))

    print("\n==== MUTATION SUMMARY ====")
    for (name, verdict, why) in results:
        print("  %-32s %s" % (name, verdict))
        print("      (%s)" % why)

    survived = [n for (n, v, _w) in results if v != "CAUGHT"]
    caught = sum(1 for (_n, v, _w) in results if v == "CAUGHT")
    print("\n%d of %d mutations caught." % (caught, len(results)))
    if survived:
        print("SURVIVED / not caught: " + ", ".join(survived))
        print("A surviving mutation is a hole in run_tests.py.")
        sys.exit(1)
    print("All planted bugs were caught: the harness has teeth.")


if __name__ == "__main__":
    main()
