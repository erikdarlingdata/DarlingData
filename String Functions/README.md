<img src="https://erikdarling.com/wp-content/uploads/2025/08/darling-data-logo_RGB.jpg" width="300px" />

# String Functions

This directory contains a set of utility functions for string manipulation in SQL Server. These functions provide efficient ways to extract or remove specific characters from strings.

## Overview

The functions in this directory help with common string manipulation tasks:
- Extracting only letters from strings
- Extracting only numbers from strings
- Removing specific characters from strings

Each function is provided in two versions:
1. A version that requires an existing Numbers table
2. A self-contained version with an inline CTE (no external dependencies)

## Functions

### get_letters

Extracts only alphabetic characters (A-Z, a-z) from a string.

| Parameter Name | Data Type | Description |
|----------------|-----------|-------------|
| @string | nvarchar(4000) | The input string to extract letters from |

**Return Value**: Table with a single column `letters_only` containing only the letters from the input string.

Usage:
```sql
SELECT
    gl.letters_only
FROM dbo.get_letters(N'abc123!@#') AS gl;
-- Returns: abc

-- Self-contained version (no dependency on Numbers table)
SELECT
    gl.letters_only
FROM dbo.get_letters_cte(N'abc123!@#') AS gl;
-- Returns: abc
```

### get_numbers

Extracts only numeric characters (0-9) from a string.

| Parameter Name | Data Type | Description |
|----------------|-----------|-------------|
| @string | nvarchar(4000) | The input string to extract numbers from |

**Return Value**: Table with a single column `numbers_only` containing only the numbers from the input string.

Usage:
```sql
SELECT
    gn.numbers_only
FROM dbo.get_numbers(N'abc123!@#') AS gn;
-- Returns: 123

-- Self-contained version (no dependency on Numbers table)
SELECT
    gn.numbers_only
FROM dbo.get_numbers_cte(N'abc123!@#') AS gn;
-- Returns: 123
```

### strip_characters

Removes specified characters from a string.

| Parameter Name | Data Type | Description |
|----------------|-----------|-------------|
| @string | nvarchar(4000) | The input string to process |
| @match_expression | nvarchar(100) | Characters to remove, specified as a LIKE pattern |

**Return Value**: Table with a single column `strip_characters` containing the input string with specified characters removed.

Usage:
```sql
SELECT
    sc.strip_characters
FROM dbo.strip_characters(N'abc123!@#', N'0-9') AS sc;
-- Returns: abc!@#

-- Self-contained version (no dependency on Numbers table)
SELECT
    sc.strip_characters
FROM dbo.strip_characters_cte(N'abc123!@#', N'^a-z') AS sc;
-- Returns: abc
```

## Implementation Notes

- All functions are schema-bound for better performance
- String concatenation is implemented using XML PATH, making the functions independent of SQL Server version
- The _cte variants don't require an external Numbers table, but may be less efficient for very large strings

Copyright 2025 Darling Data, LLC  
Released under MIT license
