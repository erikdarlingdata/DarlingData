---
name: darlingdata-release
description: Prepare a DarlingData stored procedure for release with full audit
argument-hint: [procedure-name-or-file-path]
disable-model-invocation: false
---

# DarlingData Release Prep

Prepare a stored procedure for public release by running a comprehensive audit.

Target: `$ARGUMENTS` (procedure name or file path)

## Steps

### 1. Locate the Procedure
- If a file path is given, read it directly
- If a procedure name is given, search under the repository root and common locations
- Read the full source code

### 2. Style Guide Compliance Audit
Run the full checklist from the review-sql skill:
- Keywords and functions UPPERCASE
- Data types lowercase, never abbreviated
- sysname for object names
- 4-space indentation
- Trailing commas
- Column aliases as `name = expression`
- Schema prefixes on all non-temp objects
- Table aliases with AS keyword
- Block comments only
- COUNT_BIG, ROWCOUNT_BIG, CONVERT (not CAST)
- Proper BEGIN TRY/CATCH pattern
- No MERGE, no explicit temp table drops
- Semicolons on statements

### 3. SET Options Audit
Verify the file has proper SET options:
- `SET ANSI_NULLS ON;` before the procedure
- `SET QUOTED_IDENTIFIER ON;` before the procedure
- `SET NOCOUNT ON;` inside the procedure
- `SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;` if appropriate
- Check for `SET XACT_ABORT ON;` where transactions are used

### 4. Parameter Review
- All parameters have inline comments describing their purpose
- Default values are sensible
- @help and @debug parameters present
- Parameter validation section exists

### 5. Help Section Review
- Help section exists and is triggered by `@help = 1`
- Help text accurately describes the procedure's purpose and parameters

### 6. Error Handling Review
- BEGIN TRY / BEGIN CATCH present
- ROLLBACK in CATCH if transactions are used
- THROW used to re-raise errors

### 7. Dependency Check
- Verify no external helper functions, procedures, or views are referenced
- All logic is self-contained within the procedure
- Only references to system DMVs, catalog views, and standard system procedures

### 8. Version and Header
- Check for version information
- Check for copyright/attribution comments

## Output Format

Present as a release readiness report:

1. **Release Readiness**: READY / NOT READY (with blocking issues)
2. **Issues Found**: Grouped by severity (Blocking / Warning / Suggestion)
3. **Checklist Summary**: Table showing pass/fail for each audit category
4. **Recommended Fixes**: Specific changes needed before release, with line numbers

If the procedure is NOT READY, list exactly what needs to change. If it IS READY, confirm it and suggest committing.
