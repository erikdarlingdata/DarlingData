# Erik Darling's T-SQL Coding Style Guide

This document outlines the T-SQL coding style preferences for Erik Darling (Darling Data, LLC) and must be strictly followed when writing or modifying SQL code.

## General Formatting

- **Keywords**: All SQL keywords in UPPERCASE (SELECT, FROM, WHERE, JOIN, etc.)
- **Functions**: All SQL functions in UPPERCASE (CONVERT, ISNULL, OBJECT_ID, etc.)
- **Data types**: 
  - Never abbreviate data types (use INTEGER instead of INT)
  - All data types must be lowercase (varchar, nvarchar, datetime2, bigint, etc.)
  - Length specifications must also be lowercase: nvarchar(max), not nvarchar(MAX)
  - Precision and scale specifications must be lowercase: decimal(38,2), not DECIMAL(38,2)
- **Keywords**: Never abbreviate keywords (use EXECUTE instead of EXEC, TRANSACTION instead of TRAN, PROCEDURE instead of PROC)
- **Indentation**: 4 spaces for each level of indentation (NEVER use tabs)
- **Line breaks**: Each statement on a new line
- **Spacing**: Consistent spacing around operators (=, <, >, etc.)
- **Block separation**: Empty line between logical code blocks (maximum of two empty lines between statements)
- **Quotes**: Use single quotes for string literals and N-prefix for Unicode strings (N'string')
- **TOP syntax**: Always include parentheses, as in TOP (100) not TOP 100
- **Object creation**: Generally use CREATE OR ALTER for objects instead of DROP/CREATE
- **Table aliases**: Tables must always have aliases, even in simple queries
- **Column references**: Always qualify columns with their table alias
- **Commas**: Trailing commas always. 

## Comments

- Always use block comments with /* ... */ for most comments, never use double dash (--)
- Include parameter descriptions as inline comments after parameter definitions
- Use ASCII art for header blocks to visually distinguish sections
- Include copyright and attribution information in header comments
- Prefix code sections with descriptive comments about what the section does
- Use comments to describe:
  - New code blocks
  - Complex expressions
  - Table purposes
  - Complex logic
  - The logical flow of code

## Naming Conventions

- **Parameters**: Prefixed with @ and use snake_case (@database_name, @debug)
- **Variables**: Same as parameters (@database_id, @sql)
- **Temporary Tables**: Prefixed with # and use descriptive snake_case (#filtered_objects)
- **Aliases**: Short, meaningful lowercase names (ap, o, t)
- **Objects**: Use clear, descriptive names

## Query Structure

- **SELECT statements**:
  - SELECT keyword on first line
  - Column list starts on next line, indented four spaces
  - Trailing commas for multi-line column lists
  - Columns aligned vertically for readability
  - FROM clause on new line at same indent level as SELECT
  - Column aliases should always use the pattern: column_name = column_expression
    - Example: some_date = DATEADD(DAY, 1, GETDATE())
  - Always terminate queries with a semicolon

- **Table references**:
  - Always use schema prefixes for all objects except temporary objects
  - Examples: FROM dbo.objects, FROM tempdb.dbo.objects
  - Temporary tables don't need schema: FROM #temp_table

- **Table aliases**:
  - Always use the AS keyword with table aliases: table_name AS alias
  - Example: FROM dbo.sys_objects AS o

- **Windowing functions**:
  - Format with OVER on same line as function
  - PARTITION BY and ORDER BY on separate lines indented
  - Parentheses on their own lines
  ```sql
  SELECT
      n = ROW_NUMBER() OVER
          (
              PARTITION BY
                  column_name
              ORDER BY
                  other_column
          )
  ```

- **JOIN syntax**:
  - Use modern ANSI JOIN syntax (JOIN table ON condition)
  - JOIN keyword on new line at same indent level as FROM
  - ON conditions indented from JOIN
  - JOIN conditions with AND should be aligned like this:
  ```sql
  FROM dbo.table_a AS a0
  JOIN dbo.table_a AS a1
    ON  a0.col = a1.col
    AND a0.col = a1.col
  ```
  - For correlated queries and joins, the table most recently referenced should come first in the ON clause:
  ```sql
  FROM first_table AS ft0
  JOIN dbo.first_table AS ft1
    ON ft1.col = ft0.col
  ```

- **Clauses**:
  - GROUP BY, ORDER BY, and HAVING clauses should always begin on a new line, indented four spaces from the main statement
  - WHERE clauses with AND conditions should be formatted with AND aligned:
  ```sql
  WHERE a.col = 1
  AND   b.col = 2
  ```
  - EXISTS and NOT EXISTS should use this format with 1/0 in the SELECT:
  ```sql
  WHERE EXISTS
  (
      SELECT
          1/0
      FROM other_table AS ot
      WHERE ot.col = t.col
  )
  ```

- **Subqueries**:
  - Subqueries should never be one-liners
  - Place on new lines with proper indentation
  ```sql
  SELECT
      column_name = 
      (
          SELECT
              column_name
          FROM dbo.table_name AS alias
          WHERE condition
      )
  ```

- **APPLY operators**:
  - Format CROSS APPLY and OUTER APPLY with the query on new lines
  ```sql
  FROM dbo.a_table AS y
  CROSS APPLY
  (
      SELECT
          columns
      FROM dbo.table_name AS x
      WHERE x.col = y.col
  ) AS x
  ```

- **Set operations**:
  - UNION, INTERSECT, EXCEPT should have the operator between statements with blank lines
  ```sql
  SELECT
     a.columns
  FROM dbo.a_table AS a

  EXCEPT

  SELECT
     b.columns
  FROM dbo.b_table AS b;
  ```

- **Table-valued constructors (VALUES)**:
  - Format with VALUES on its own line, and value rows indented:
  ```sql
  FROM 
  (
      VALUES
          (1, 2, 3)
  ) AS v (named_columns);
  ```

- **CTEs**:
  - WITH keyword on its own line
  - CTE name indented on next line
  - Opening parenthesis on same line as CTE name
  - Column list indented on subsequent lines
  - Closing parenthesis on its own line
  - AS keyword on its own line
  - Multiple CTEs separated by commas at the end
  ```sql
  WITH
      database_stats
  (
      database_name,
      recovery_model,
      log_size_mb
  ) AS
  (
      SELECT
          database_name = d.name,
          recovery_model = d.recovery_model_desc,
          log_size_mb = SUM(f.size) * 8 / 1024
      FROM sys.databases AS d
      JOIN sys.master_files AS f
        ON f.database_id = d.database_id
      GROUP BY
          d.name,
          d.recovery_model_desc
  ),
  second_cte
  (
      column_list
  ) AS
  (
      query
  )
  ```

- **Table Creation**:
  - CREATE TABLE on first line
  - Schema and table name on next line, indented
  - Opening parenthesis on its own line
  - Each column on a new line, indented
  - Always specify NULL or NOT NULL constraint for each column
  - DEFAULT constraints can generally follow other column descriptors on the same line
  - Closing parenthesis on its own line
  ```sql
  CREATE TABLE
      dbo.table_name
  (
      column_name bigint NOT NULL,
      another_column varchar(50) NULL DEFAULT 'value',
      third_column datetime2(7) NOT NULL DEFAULT SYSDATETIME()
  );
  ```

- **Index Creation**:
  - For multi-column indexes, format with columns on new lines:
  ```sql
  CREATE INDEX
      index_name
  ON dbo.table_name
  (
      column1,
      column2
  )
  INCLUDE
  (
      column3,
      column4
  )
  WITH
      (options);
  ```
  - For single-column indexes, a more compact format is acceptable:
  ```sql
  CREATE INDEX
      index_name
  ON dbo.table_name
      (column1)
  INCLUDE
      (column3)
  WITH
      (options);
  ```

- **INSERT statements**:
  - INSERT on first line
  - Always use INSERT INTO
  - Schema and table name on next line, indented
  - Column list in parentheses on new lines, indented
  ```sql
  INSERT INTO
      dbo.table_name
  (
      column1,
      column2
  )
  VALUES
  (
      value1,
      value2
  );
  ```
  
- **Temporary table inserts**:
  - Use TABLOCK hint with temporary table inserts
  ```sql
  INSERT
      #table_name
  WITH
      (TABLOCK)
  (
      column_list
  )
  ```

- **UPDATE statements**:
  - UPDATE on first line
  - Table alias on next line, indented
  - SET on its own line with same indentation as alias
  - FROM clause on its own line 
  ```sql
  UPDATE
      alias
  SET
     alias.col1 = value1,
     alias.col2 = value2
  FROM dbo.table AS alias
  WHERE alias.condition;
  ```

- **DELETE statements**:
  - DELETE on first line 
  - Table alias on next line, indented
  - FROM clause on its own line
  ```sql
  DELETE
      alias
  FROM dbo.table AS alias
  WHERE alias.condition;
  ```

- **Parentheses**:
  - Opening parenthesis on same line as function/procedure name
  - Closing parenthesis aligned with starting line or on its own line for long expressions
  - Use extra parentheses for clarity in complex expressions
  - Function arguments should be indented four spaces and on new lines:
  ```sql
  CONVERT
  (
      data_type,
      value
  )
  ```
  
- **Multi-parameter functions**:
  - For functions with multiple parameters or complex expressions, format the function name on its own line
  - Place parameters on subsequent lines with proper indentation
  ```sql
  SELECT
      formatted_date = 
          DATEFROMPARTS
          (
              YEAR(date_column),
              MONTH(date_column),
              1
          )
  ```

## Code Organization

- SET statements grouped at procedure start
- Validation checks before main logic
- Help/documentation sections clearly separated from main logic
- Version information tracked explicitly
- Parameter validation at beginning of procedures
- CREATE/ALTER statements separated with GO

## Code Blocks and Control Structures

- BEGIN/END contents should be indented four spaces:
  ```sql
  BEGIN
      /*logic*/
  END;
  ```

- CASE expression contents should be indented, with each condition on a new line:
  ```sql
  CASE
      WHEN thing
      AND  other_thing
      THEN stuff
      ELSE result
  END
  ```

- IF/ELSE blocks should be formatted with BEGIN/END on their own lines:
  ```sql
  IF condition
  BEGIN
      logic
  END;
  ELSE
  BEGIN
      logic
  END;
  ```

- WHILE loops should follow similar formatting:
  ```sql
  WHILE condition
  BEGIN
      work
  END;
  ```

- Error handling should follow this template:
  ```sql
  BEGIN
      BEGIN TRY
          do stuff
      END TRY
      BEGIN CATCH
          IF @@TRANCOUNT > 0
          BEGIN
              ROLLBACK;
          END;
      
          THROW;
      END CATCH;
  END;
  ```

- DECLARE blocks should put everything on a new line:
  ```sql
  DECLARE
      @t1 integer,
      @t2 integer;
  ```

- Variables should be declared and initialized together for static values:
  ```sql
  DECLARE
      @t1 integer = 1,
      @t2 integer = 2;
  ```
  - Take care when initializing to ensure you don't introduce logical flaws with NULL checks

- Dynamic SQL should follow specific formatting:
  - Initial declaration with empty string
  - Each string concatenation part on its own line
  - Each QUOTENAME or variable reference on its own line
  ```sql
  DECLARE
      @sql nvarchar(max) = N''

  SET @sql += N'
SELECT
    column_name = 
        value ' + 
    QUOTENAME(alias.object_name) + N'
FROM
    table_name
  ';

  EXECUTE sys.sp_executesql
      @sql,
     N'@parameters',
       @input;
  ```

- Transaction blocks should use consistent indentation:
  ```sql
  BEGIN TRANSACTION
      work
  COMMIT TRANSACTION;
  ```

- XML and JSON output should be formatted with each option on a new line:
  ```sql
  FOR
     XML
     PATH
     TYPE
  ```

## SQL Best Practices

- Always use IS NULL / IS NOT NULL for NULL comparisons, never = NULL or != NULL
- Use ISNULL() function for value replacement
- Include RECOMPILE hints for procedures with variable data distributions
- Use RAISERROR with NOWAIT for immediate message display
- Include thorough error handling with BEGIN TRY/CATCH blocks
- Always validate user inputs before using them
- Use semicolons at the end of statements (but only at the very end, after any query hints)
- Apply query hints consistently (RECOMPILE, MAXDOP, etc.)
- Always use ROWCOUNT_BIG() instead of @@ROWCOUNT
- Always use COUNT_BIG() instead of COUNT() to avoid potential integer overflow
  - Example: `COUNT_BIG(i.index_id)` not `COUNT(i.index_id)`
  - Even if the result will never be large enough to overflow, use COUNT_BIG() for consistency
- Always use CONVERT over CAST for data type conversions (except when using TRY_CAST, as TRY_CAST isn't dependent on SQL Server version)
- Use XML for string splitting and string building (concatenation), as these methods aren't dependent on SQL Server version or database compatibility level
- Always use cursor variables instead of normal cursors, as they don't require explicit CLOSE/DEALLOCATE statements
- Do not use MERGE statements unless absolutely necessary for functional reasons
- Prefer temporary tables over table variables for performance reasons, especially when the data will be used in joins
- Table variables are acceptable for situations where contents are not used relationally or when insert performance is critical
- Do not drop temporary tables at the end of stored procedures (they're automatically cleaned up when the procedure exits)
- Prefer + operator for string concatenation as it's not version dependent (though CONCAT is acceptable for SQL Server 2012+)
- FORMAT is preferred for adding commas to numbers, but complex CONVERT to money with substring operations is also acceptable
- Date literals should always follow yyyymmdd format (e.g., 20250101), with additional precision as needed for the data type

## Stored Procedure Structure

1. SET configuration statements at the top
2. Procedure declaration (CREATE/ALTER)
3. Parameter definitions with inline comments
4. BEGIN block
5. SET NOCOUNT ON and other session settings
6. Variable declarations
7. Validation checks
8. Help section (@help = 1)
9. Main processing logic
10. Error handling
11. Cleanup

Basic stored procedure outline:
```sql
CREATE OR ALTER PROCEDURE
    dbo.procedure_name
(
    @parameter_list
)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;

    queries...

END;
```

Trigger template:
```sql
CREATE OR ALTER TRIGGER
    dbo.a_trigger
ON dbo.a_table
AFTER/INSTEAD OF
AS
BEGIN
    IF ROWCOUNT_BIG() = 0
    BEGIN
        RETURN
    END;
    
    work

END;
```

View template:
```sql
CREATE OR ALTER VIEW
    dbo.a_view
AS
SELECT
    column1 = t.column1,
    column2 = t.column2
FROM dbo.table AS t
WHERE t.condition = 1;
```

Function template:
```sql
CREATE OR ALTER FUNCTION
    dbo.a_function
(
    @parameter1 integer,
    @parameter2 varchar(50)
)
RETURNS data_type
AS
BEGIN
    RETURN value;
END;
```

## Examples

### Complex SELECT with Multiple JOINs, GROUP BY, and HAVING

```sql
SELECT
    database_name = d.name,
    index_count = COUNT_BIG(i.index_id),
    total_size_mb = SUM(a.total_pages) * 8 / 1024,
    read_operations = SUM(ius.user_seeks + ius.user_scans + ius.user_lookups),
    write_operations = SUM(ius.user_updates),
    avg_fragmentation = AVG(ps.avg_fragmentation_in_percent)
FROM sys.databases AS d
JOIN sys.tables AS t
  ON t.database_id = d.database_id
LEFT JOIN sys.indexes AS i
  ON  i.object_id = t.object_id
  AND i.index_id > 0
  AND i.is_disabled = 0
LEFT JOIN sys.dm_db_index_usage_stats AS ius
  ON  ius.database_id = d.database_id
  AND ius.object_id = i.object_id
  AND ius.index_id = i.index_id
LEFT JOIN sys.dm_db_index_physical_stats
(
    DB_ID(),
    NULL,
    NULL,
    NULL,
    'LIMITED'
) AS ps
  ON  ps.object_id = i.object_id
  AND ps.index_id = i.index_id
LEFT JOIN sys.allocation_units AS a
  ON a.container_id = i.hobt_id
WHERE d.database_id > 4
AND   d.is_read_only = 0
AND   d.state_desc = N'ONLINE'
GROUP BY
    d.name,
    d.create_date
HAVING
    COUNT(i.index_id) > 10
ORDER BY
    total_size_mb DESC,
    database_name ASC
OPTION(MAXDOP 1, RECOMPILE);
```

### CTE with Multiple Definitions and Nested Queries

```sql
WITH
    database_stats
(
    database_name,
    recovery_model,
    log_size_mb,
    log_used_percent
) AS
(
    SELECT
        database_name = d.name,
        recovery_model = d.recovery_model_desc,
        log_size_mb = SUM(CASE WHEN f.type_desc = N'LOG' THEN f.size END) * 8 / 1024,
        log_used_percent = SUM(CASE WHEN f.type_desc = N'LOG' THEN CONVERT(decimal(19,2), fileproperty(f.name, 'SpaceUsed')) / f.size * 100 END)
    FROM sys.databases AS d
    JOIN sys.master_files AS f
      ON f.database_id = d.database_id
    WHERE d.state_desc = N'ONLINE'
    GROUP BY
        d.name,
        d.recovery_model_desc
),
    database_backups AS
(
    SELECT
        database_name = b.database_name,
        last_full_backup = MAX(CASE WHEN b.type = 'D' THEN b.backup_finish_date END),
        last_log_backup = MAX(CASE WHEN b.type = 'L' THEN b.backup_finish_date END)
    FROM msdb.dbo.backupset AS b
    WHERE b.backup_finish_date > DATEADD(DAY, -7, GETDATE())
    GROUP BY
        b.database_name
)
SELECT
    ds.database_name,
    ds.recovery_model,
    ds.log_size_mb,
    ds.log_used_percent,
    days_since_full_backup = 
        CASE 
            WHEN db.last_full_backup IS NULL 
            THEN 999 
            ELSE DATEDIFF(DAY, db.last_full_backup, GETDATE()) 
        END,
    days_since_log_backup = 
        CASE 
            WHEN db.last_log_backup IS NULL 
            THEN 999 
            ELSE DATEDIFF(DAY, db.last_log_backup, GETDATE()) 
        END
FROM database_stats AS ds
LEFT JOIN database_backups AS db
  ON db.database_name = ds.database_name
WHERE ds.log_size_mb > 100
ORDER BY
    log_size_mb DESC;
```

### Dynamic SQL Generation and Execution

```sql
DECLARE
    @database_name sysname = N'AdventureWorks',
    @table_name sysname = N'SalesOrderHeader',
    @column_name sysname = N'OrderDate',
    @sql nvarchar(max) = N'';

/*
Build query dynamically using proper quoting and formatting
*/
SET @sql = N'
SELECT
    order_month =
        DATEFROMPARTS
        (
            YEAR
            (t.' +
            QUOTENAME(@column_name) +
            N'),
            MONTH
            (t.' +
            QUOTENAME(@column_name) +
            N'),
            1
        ),
    order_count = COUNT_BIG(*),
    total_amount = SUM(t.TotalDue),
    avg_amount = AVG(t.TotalDue)
FROM ' + QUOTENAME(@database_name) + N'.dbo.' + QUOTENAME(@table_name) + N' AS t
WHERE ' + QUOTENAME(@column_name) + N' >= DATEADD(YEAR, -1, GETDATE())
GROUP BY
        DATEFROMPARTS
        (
            YEAR
            (t.' +
            QUOTENAME(@column_name) +
            N'),
            MONTH
            (t.' +
            QUOTENAME(@column_name) +
            N'),
            1
        )
ORDER BY
    order_month;
';

/*
Execute the dynamic SQL with proper parameter passing
*/
EXECUTE sys.sp_executesql
    @sql,
    N'',
    N'';
```

### Stored Procedure with Temp Tables and Flow Control

```sql
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'dbo.sp_MyProcedure', N'P') IS NULL
BEGIN
    EXECUTE(N'CREATE PROCEDURE dbo.sp_MyProcedure AS RETURN 138;');
END;
GO

ALTER PROCEDURE
    dbo.sp_MyProcedure
(
    @database_name sysname = NULL, /*the database to analyze*/
    @days_back integer = 7, /*how many days of history to analyze*/
    @threshold_percent integer = 20, /*minimum percentage change to report*/
    @debug bit = 0, /*prints additional diagnostic information*/
    @help bit = 0 /*prints help information*/
)
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
    
    BEGIN TRY
        /*
        Variable declarations
        */
        DECLARE
            @sql nvarchar(max) = N'',
            @database_id integer = NULL,
            @start_date datetime2(7) = DATEADD(DAY, -@days_back, GETDATE()),
            @error_msg nvarchar(2048) = N'';
            
        /*
        Parameter validation
        */
        IF @database_name IS NULL
        BEGIN
            SELECT
                @database_name = DB_NAME();
        END;
            
        IF @threshold_percent <= 0 OR @threshold_percent > 100
        BEGIN
            SELECT
                @error_msg = N'@threshold_percent must be between 1 and 100.';
                
            RAISERROR(@error_msg, 16, 1);
            RETURN;
        END;
            
        /*
        Help section
        */
        IF @help = 1
        BEGIN
            SELECT
                help = N'This procedure analyzes database performance changes';
            
            RETURN;
        END;
        
        /*
        Create temp tables for analysis
        */
        CREATE TABLE
            #baseline_metrics
        (
            object_id bigint NOT NULL,
            metric_name varchar(50) NOT NULL,
            metric_value decimal(38,2) NOT NULL
        );
        
        CREATE TABLE
            #current_metrics
        (
            object_id bigint NOT NULL,
            metric_name varchar(50) NOT NULL,
            metric_value decimal(38,2) NOT NULL
        );
        
        /*
        Populate baseline data
        */
        INSERT
            #baseline_metrics
        WITH
            (TABLOCK)
        (
            object_id,
            metric_name,
            metric_value
        )
        SELECT
            object_id = t.object_id,
            metric_name = 'query_cost',
            metric_value = AVG(qs.total_elapsed_time / 1000.0)
        FROM sys.dm_exec_query_stats AS qs
        CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS t
        WHERE qs.creation_time < @start_date
        AND   t.dbid = DB_ID(@database_name)
        GROUP BY
            t.object_id
        OPTION(RECOMPILE);
        
        IF @debug = 1
        BEGIN
            SELECT
                baseline_rows = COUNT(*)
            FROM #baseline_metrics;
        END;
        
        /*
        Main processing logic - analyze changes
        */
        SELECT
            object_name = o.name,
            schema_name = s.name,
            b.metric_name,
            baseline_value = b.metric_value,
            current_value = c.metric_value,
            percent_change = 
                CASE 
                    WHEN b.metric_value = 0 
                    THEN NULL
                    ELSE (c.metric_value - b.metric_value) / b.metric_value * 100 
                END
        FROM #baseline_metrics AS b
        JOIN #current_metrics AS c
          ON  c.object_id = b.object_id
          AND c.metric_name = b.metric_name
        JOIN sys.objects AS o
          ON o.object_id = b.object_id
        JOIN sys.schemas AS s
          ON s.schema_id = o.schema_id
        WHERE ABS((c.metric_value - b.metric_value) / NULLIF(b.metric_value, 0) * 100) >= @threshold_percent
        ORDER BY
            ABS((c.metric_value - b.metric_value) / NULLIF(b.metric_value, 0) * 100) DESC;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
        BEGIN
            ROLLBACK;
        END;        
        THROW;
    END CATCH;
END;
GO
```

This style guide is based on an analysis of Erik Darling's stored procedures from Darling Data, LLC.
