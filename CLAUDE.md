# Erik Darling's T-SQL Coding Style Guide

This document outlines the T-SQL coding style preferences for Erik Darling (Darling Data, LLC) and should be followed when writing or modifying SQL code.

## General Formatting

- **Keywords**: All SQL keywords in UPPERCASE (SELECT, FROM, WHERE, JOIN, etc.)
- **Functions**: All SQL functions in UPPERCASE (CONVERT, ISNULL, OBJECT_ID, etc.)
- **Indentation**: 4 spaces for each level of indentation (NEVER use tabs)
- **Line breaks**: Each statement on a new line
- **Spacing**: Consistent spacing around operators (=, <, >, etc.)
- **Block separation**: Empty line between logical code blocks (maximum of two empty lines between statements)
- **Quotes**: Use single quotes for string literals and N-prefix for Unicode strings (N'string')
- **Data types**: Never abbreviate data types (use INTEGER instead of INT)
- **Keywords**: Never abbreviate keywords (use EXECUTE instead of EXEC, TRANSACTION instead of TRAN, PROCEDURE instead of PROC)
- **TOP syntax**: Always include parentheses, as in TOP (100) not TOP 100
- **Object creation**: Generally use CREATE OR ALTER for objects instead of DROP/CREATE
- **Table aliases**: Tables should always have aliases, even in simple queries
- **Column references**: Always qualify columns with their table alias

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
  - Column list starts on next line, indented
  - Leading commas for multi-line column lists
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
     columns
  FROM dbo.a_table AS a

  EXCEPT

  SELECT
     columns
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
  - WITH keyword on first line
  - CTE name aligned with leading whitespace
  - CTE column list indented from CTE name
  - Multiple CTEs separated by commas at the end

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
  - Schema and table name on next line, indented
  - Column list in parentheses on new lines, indented
  ```sql
  INSERT
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
     col1 = value1,
     col2 = value2
  FROM dbo.table AS alias
  WHERE condition;
  ```

- **DELETE statements**:
  - DELETE on first line 
  - Table alias on next line, indented
  - FROM clause on its own line
  ```sql
  DELETE
      alias
  FROM dbo.table AS alias
  WHERE condition;
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
  ```sql
  DECLARE
      @sql nvarchar(max) = N''

  SET @sql += N'
      the query ' + QUOTENAME(object_name) + '
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

## Example

```sql
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.sp_MyProcedure', 'P') IS NULL
BEGIN
    EXECUTE ('CREATE PROCEDURE dbo.sp_MyProcedure AS RETURN 0;');
END;
GO

ALTER PROCEDURE
    dbo.sp_MyProcedure
(
    @database_name sysname = NULL, /*the database to analyze*/
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
            @sql nvarchar(MAX) = N'',
            @database_id integer = NULL;
            
        /*
        Parameter validation
        */
        IF @database_name IS NULL
        BEGIN
            SELECT
                @database_name = DB_NAME();
        END;
            
        /*
        Help section
        */
        IF @help = 1
        BEGIN
            SELECT
                help = N'This procedure analyzes database objects';
            
            RETURN;
        END;
        
        /*
        Main processing logic
        */
        SELECT
            object_id,
            object_name = o.name,
            schema_name = s.name
        FROM dbo.objects AS o
        JOIN dbo.schemas AS s
          ON o.schema_id = s.schema_id
        WHERE o.type = N'U'
        AND   o.is_ms_shipped = 0
        GROUP BY
            o.object_id,
            o.name,
            s.name
        ORDER BY
            o.name
        OPTION(RECOMPILE);
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;
END;
GO
```

This style guide is based on an analysis of Erik Darling's stored procedures from Darling Data, LLC.