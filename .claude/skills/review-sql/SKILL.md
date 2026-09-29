---
name: review-sql
description: Review a T-SQL file against Erik Darling's coding style guide
argument-hint: [file-path]
disable-model-invocation: false
allowed-tools: Read, Grep, Glob
---

# T-SQL Style Review

Review a T-SQL file against the coding conventions defined in CLAUDE.md. This is a **read-only** analysis -- do not modify files.

Read the file at `$ARGUMENTS` and check for violations of every rule below.

## Checklist

### Keywords & Functions
- [ ] All SQL keywords UPPERCASE (SELECT, FROM, WHERE, JOIN, EXECUTE, TRANSACTION, PROCEDURE)
- [ ] All SQL functions UPPERCASE (CONVERT, ISNULL, OBJECT_ID, DATEADD, COUNT_BIG)
- [ ] Never abbreviated keywords (EXECUTE not EXEC, TRANSACTION not TRAN, PROCEDURE not PROC)
- [ ] TOP always has parentheses: `TOP (100)` not `TOP 100`

### Data Types
- [ ] All data types lowercase (varchar, nvarchar, datetime2, bigint, integer)
- [ ] Never abbreviated data types (integer not int)
- [ ] Length specs lowercase: nvarchar(max) not nvarchar(MAX)
- [ ] sysname used for SQL Server object names, not nvarchar(128)

### Formatting
- [ ] 4 spaces for indentation, no tabs
- [ ] Trailing commas on multi-line column lists
- [ ] Column aliases use `column_name = expression` pattern (not `expression AS column_name`)
- [ ] Statements terminated with semicolons
- [ ] Block comments `/* */` used, not double dash `--`
- [ ] Single quotes for strings, N-prefix for Unicode (N'string')

### Query Structure
- [ ] Tables always have aliases, using AS keyword: `FROM dbo.table AS t`
- [ ] Columns always qualified with table alias
- [ ] Schema prefix on all objects except temp tables
- [ ] WHERE conditions with AND aligned: `AND   ` (with spacing)
- [ ] EXISTS uses `SELECT 1/0` pattern
- [ ] JOINs use ANSI syntax with ON conditions indented
- [ ] Subqueries never one-liners

### Best Practices
- [ ] COUNT_BIG() used instead of COUNT()
- [ ] ROWCOUNT_BIG() used instead of @@ROWCOUNT
- [ ] CONVERT used instead of CAST (except TRY_CAST)
- [ ] IS NULL / IS NOT NULL for null comparisons, never = NULL
- [ ] No MERGE statements (unless absolutely necessary)
- [ ] Cursor variables instead of normal cursors
- [ ] Temp tables preferred over table variables for relational use
- [ ] Temp tables not explicitly dropped at end of procedures
- [ ] Date literals in yyyymmdd format
- [ ] TABLOCK hint on temp table inserts

### Procedure Structure (if applicable)
- [ ] SET NOCOUNT, XACT_ABORT ON at the top
- [ ] Parameter validation before main logic
- [ ] Help section for @help = 1
- [ ] BEGIN TRY / BEGIN CATCH with proper ROLLBACK pattern
- [ ] No additional dependency objects (all logic self-contained)

## Output Format

Present findings as:

1. **Summary**: Overall compliance rating (e.g., "12 issues found across 3 categories")
2. **Issues**: List each violation with:
   - Line number(s)
   - What's wrong
   - What it should be
3. **Good Practices**: Note anything done particularly well

Group issues by category (Keywords, Data Types, Formatting, Structure, Best Practices). Order by severity within each group.
