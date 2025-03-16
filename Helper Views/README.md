<img src="https://erikdarling.com/wp-content/uploads/2025/08/darling-data-logo_RGB.jpg" width="300px" />

# Helper Views

This directory contains helper views and functions for diagnosing various SQL Server performance issues. These scripts are particularly useful for presentations and educational purposes, but can also be used in troubleshooting scenarios.

## Overview

The collection includes:
- Views for analyzing index sizes
- Functions for examining lock information
- Views for examining memory usage
- Procedures for testing tempdb performance

## Components

### WhatsUpIndexes View

A view that provides detailed information about index sizes in the current database.

**Functionality**:
- Displays database, schema, table, and index names
- Shows in-row pages size in MB
- Shows LOB (Large Object) pages size in MB
- Reports number of in-row used pages
- Displays row count for each index
- Filters out system objects and table-valued functions

Usage:
```sql
SELECT
    w.*
FROM dbo.WhatsUpIndexes AS w
ORDER BY
    w.in_row_mb DESC;
```

### WhatsUpLocks Function

A table-valued function that provides information about locks taken by specific sessions.

| Parameter Name | Data Type | Default Value | Description |
|----------------|-----------|---------------|-------------|
| @spid | integer | NULL | Session ID to examine. If NULL, returns information for all sessions |

**Functionality**:
- Displays session ID and blocking session ID information
- Shows lock modes, resource types, and lock status
- Identifies locked objects and associated index names
- Counts different lock types (HOBT, object, page, and row locks)
- Reports total lock count

Usage:
```sql
-- Check locks for a specific session
SELECT
    wul.*
FROM dbo.WhatsUpLocks(51) AS wul;

-- Check locks for all sessions
SELECT
    wul.*
FROM dbo.WhatsUpLocks(NULL) AS wul;
```

### WhatsUpMemory View

A view that examines what's in SQL Server memory.

**Functionality**:
- Shows database, schema, object, and index information
- Calculates in-row pages in MB (for data types 1 and 3)
- Calculates LOB pages in MB (for data type 2)
- Reports total buffer cache pages

Usage:
```sql
SELECT
    wum.*
FROM dbo.WhatsUpMemory AS wum
ORDER BY
    wum.pages DESC;
```

### tempdb_tester Procedure

A stored procedure that generates semi-random tempdb activity, useful for testing and demonstration purposes.

**Functionality**:
- Creates a temporary table with approximately 10,000 rows
- Performs various DML operations (UPDATE, DELETE, INSERT)
- Uses RECOMPILE hint for optimal execution plans

Usage:
```sql
EXECUTE dbo.tempdb_tester;
```

## Warning

Some of these scripts (particularly WhatsUpMemory) may cause performance issues if run on busy production servers. Use with caution, especially on servers with large amounts of memory.

Copyright 2025 Darling Data, LLC  
Released under MIT license
