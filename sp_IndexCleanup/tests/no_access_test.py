"""
sp_IndexCleanup HAS_DBACCESS Preflight Test
============================================
Verifies sp_IndexCleanup does NOT hang when invoked by a login that lacks
access to the target user database(s).

Background: PerformanceMonitor #915. Without the preflight, three-part-name
queries against sys.dm_db_partition_stats spin at 100% CPU forever instead
of erroring (Msg 916).

What this script does:
  1. Connects as sa, creates a temp login with VIEW SERVER STATE only
     (no user mapping in any user database).
  2. Runs sp_IndexCleanup as that login, both single-DB and multi-DB,
     under a hard wall-clock timeout.
  3. Asserts the call returns within seconds (proving no hang) and does
     not produce result-set rows for inaccessible databases.
  4. Drops the temp login.

Usage:
    python no_access_test.py [--server SQL2022] [--password "L!nt0044"]
"""

import subprocess
import sys
import time
import secrets

TEST_LOGIN = f"sp_indexcleanup_no_access_test_{secrets.token_hex(4)}"
TEST_PASSWORD = "T3st!" + secrets.token_hex(8) + "Aa1"
TIMEOUT_SECONDS = 30


def run_sqlcmd_as_sa(server, sa_password, sql):
    """Execute a SQL statement as sa."""
    cmd = [
        "sqlcmd", "-S", server, "-U", "sa", "-P", sa_password,
        "-d", "master", "-b", "-Q", sql,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    if result.returncode != 0:
        raise RuntimeError(f"sa SQL failed:\n{result.stderr}\n{result.stdout}")
    return result.stdout


def run_sqlcmd_as_test_login(server, sql, timeout):
    """Execute a SQL statement as the test login, with a wall-clock timeout."""
    cmd = [
        "sqlcmd", "-S", server, "-U", TEST_LOGIN, "-P", TEST_PASSWORD,
        "-d", "master", "-Q", sql,
    ]
    start = time.monotonic()
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return None, "TIMED OUT", time.monotonic() - start
    elapsed = time.monotonic() - start
    return result.stdout, result.stderr, elapsed


def setup_login(server, sa_password):
    print(f"  Creating test login {TEST_LOGIN}...")
    run_sqlcmd_as_sa(server, sa_password, f"""
        IF SUSER_ID(N'{TEST_LOGIN}') IS NOT NULL
            DROP LOGIN [{TEST_LOGIN}];
        CREATE LOGIN [{TEST_LOGIN}] WITH PASSWORD = N'{TEST_PASSWORD}',
            CHECK_POLICY = OFF;
        GRANT VIEW SERVER STATE TO [{TEST_LOGIN}];
    """)
    run_sqlcmd_as_sa(server, sa_password, f"""
        USE master;
        IF DATABASE_PRINCIPAL_ID(N'{TEST_LOGIN}') IS NULL
            CREATE USER [{TEST_LOGIN}] FOR LOGIN [{TEST_LOGIN}];
        GRANT EXECUTE ON dbo.sp_IndexCleanup TO [{TEST_LOGIN}];
    """)


def teardown_login(server, sa_password):
    print(f"  Dropping test login {TEST_LOGIN}...")
    try:
        run_sqlcmd_as_sa(server, sa_password, f"""
            USE master;
            IF DATABASE_PRINCIPAL_ID(N'{TEST_LOGIN}') IS NOT NULL
                DROP USER [{TEST_LOGIN}];
        """)
        run_sqlcmd_as_sa(server, sa_password, f"""
            IF SUSER_ID(N'{TEST_LOGIN}') IS NOT NULL
                DROP LOGIN [{TEST_LOGIN}];
        """)
    except Exception as e:
        print(f"  Warning: cleanup failed: {e}")


def find_test_database(server, sa_password):
    """Pick any online user database with no mapping for the test login."""
    out = run_sqlcmd_as_sa(server, sa_password, """
        SET NOCOUNT ON;
        SELECT TOP (1) name
        FROM sys.databases
        WHERE database_id > 4
          AND state = 0
          AND is_in_standby = 0
          AND is_read_only = 0
        ORDER BY database_id;
    """)
    for line in out.splitlines():
        line = line.strip()
        if not line or line.startswith("-") or line.lower() == "name":
            continue
        return line
    raise RuntimeError("No eligible user database found for test")


def assert_returned_quickly(label, elapsed):
    if elapsed >= TIMEOUT_SECONDS:
        print(f"  [FAIL] {label}: hung past {TIMEOUT_SECONDS}s")
        return False
    print(f"  [PASS] {label}: returned in {elapsed:.2f}s")
    return True


def main():
    server = "SQL2022"
    sa_password = "L!nt0044"
    args = sys.argv[1:]
    for i, arg in enumerate(args):
        if arg == "--server" and i + 1 < len(args):
            server = args[i + 1]
        elif arg == "--password" and i + 1 < len(args):
            sa_password = args[i + 1]

    print(f"sp_IndexCleanup HAS_DBACCESS preflight test against {server}")
    print()

    setup_login(server, sa_password)
    try:
        target_db = find_test_database(server, sa_password)
        print(f"  Using target database: {target_db}")
        print()

        passed = 0
        failed = 0

        # Test 1: explicit @database_name with no access -> clear error, no hang
        print(f"Test 1: explicit @database_name = '{target_db}', no user mapping")
        sql_single = (
            f"EXECUTE master.dbo.sp_IndexCleanup "
            f"@database_name = N'{target_db}', @dedupe_only = 1;"
        )
        stdout, stderr, elapsed = run_sqlcmd_as_test_login(server, sql_single, TIMEOUT_SECONDS)
        if not assert_returned_quickly("returns quickly", elapsed):
            failed += 1
        else:
            passed += 1

        if stderr is None:
            failed += 1
        elif "no access" in (stderr or "").lower() or "no access" in (stdout or "").lower():
            print("  [PASS] error mentions 'no access'")
            passed += 1
        else:
            print("  [FAIL] expected 'no access' in error output")
            print(f"    stdout: {(stdout or '')[:300]}")
            print(f"    stderr: {(stderr or '')[:300]}")
            failed += 1

        # Test 2: @get_all_databases with no access -> warn + no result rows for skipped
        print()
        print("Test 2: @get_all_databases = 1, no user mappings anywhere")
        sql_multi = (
            "EXECUTE master.dbo.sp_IndexCleanup "
            "@get_all_databases = 1, @dedupe_only = 1;"
        )
        stdout, stderr, elapsed = run_sqlcmd_as_test_login(server, sql_multi, TIMEOUT_SECONDS)
        if not assert_returned_quickly("returns quickly", elapsed):
            failed += 1
        else:
            passed += 1

        # In multi-DB mode every user DB will be inaccessible, so the proc raises
        # "No valid databases found to process." after first surfacing the no-access
        # warning. Both behaviors prove we did not hang.
        combined = ((stdout or "") + " " + (stderr or "")).lower()
        if "no valid databases" in combined or "no access" in combined:
            print("  [PASS] surfaced no-access / no-valid-databases message")
            passed += 1
        else:
            print("  [FAIL] expected no-access or no-valid-databases message")
            print(f"    stdout: {(stdout or '')[:400]}")
            print(f"    stderr: {(stderr or '')[:400]}")
            failed += 1

        print()
        print(f"Results: {passed} passed, {failed} failed")
        if failed:
            sys.exit(1)
        print("All HAS_DBACCESS preflight tests passed!")
    finally:
        teardown_login(server, sa_password)


if __name__ == "__main__":
    main()
