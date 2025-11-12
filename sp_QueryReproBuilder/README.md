<img src="https://erikdarling.com/wp-content/uploads/2025/08/darling-data-logo_RGB.jpg" width="300px" />

# sp_QueryReproBuilder

This procedure extracts queries and their parameters from SQL Server Query Store and generates executable reproduction scripts that you can run in a new query window.

It's designed to make it easy to reproduce query performance issues by capturing the query text, parameter values, and execution context (SET options, language, date format, etc.) from Query Store.

The big upside of using this stored procedure is that you get ready-to-run scripts that include:
* Query text with parameter declarations removed
* Actual parameter values from the query plan
* Context settings (ANSI options, language, date format, etc.)
* Warnings about potential reproduction obstacles (temp tables, OPTION(RECOMPILE), etc.)
* Embedded constants extracted from plans using parameter embedding optimization

You can filter queries by plan_id or query_id, and optionally specify a date range.

## Parameters

| parameter_name         | data_type          | description                                                           | valid_inputs                                       | defaults                         |
|------------------------|--------------------|-----------------------------------------------------------------------|----------------------------------------------------|----------------------------------|
| @database_name         | sysname            | the name of the database you want to look at query store in           | a database name with query store enabled           | NULL; current database if NULL   |
| @start_date            | datetimeoffset(7)  | the begin date of your search, will be converted to UTC internally    | January 1, 1753, through December 31, 9999         | the last seven days              |
| @end_date              | datetimeoffset(7)  | the end date of your search, will be converted to UTC internally      | January 1, 1753, through December 31, 9999         | current date/time                |
| @include_plan_ids      | nvarchar(4000)     | a list of plan ids to search for                                      | a string; comma separated for multiple ids         | NULL                             |
| @include_query_ids     | nvarchar(4000)     | a list of query ids to search for                                     | a string; comma separated for multiple ids         | NULL                             |
| @ignore_plan_ids       | nvarchar(4000)     | a list of plan ids to ignore                                          | a string; comma separated for multiple ids         | NULL                             |
| @ignore_query_ids      | nvarchar(4000)     | a list of query ids to ignore                                         | a string; comma separated for multiple ids         | NULL                             |
| @procedure_schema      | sysname            | the schema of the procedure you're searching for                      | a valid schema in your database                    | NULL                             |
| @procedure_name        | sysname            | the name of the programmable object you're searching for              | a valid programmable object in your database       | NULL                             |
| @query_text_search     | nvarchar(4000)     | query text to search for                                              | a string; leading and trailing wildcards added    | NULL                             |
| @query_text_search_not | nvarchar(4000)     | query text to exclude                                                 | a string; leading and trailing wildcards added    | NULL                             |
| @help                  | bit                | return available parameter details, etc.                              | 0 or 1                                             | 0                                |
| @debug                 | bit                | prints dynamic sql, statement length, parameter and variable values   | 0 or 1                                             | 0                                |
| @version               | varchar(30)        | OUTPUT; for support                                                   | none; OUTPUT                                       | none; OUTPUT                     |
| @version_date          | datetime           | OUTPUT; for support                                                   | none; OUTPUT                                       | none; OUTPUT                     |

## Examples

```sql
-- Basic execution - generates repro scripts for all queries in the last 7 days
EXECUTE dbo.sp_QueryReproBuilder;

-- Generate repro scripts for specific plan IDs
EXECUTE dbo.sp_QueryReproBuilder
    @include_plan_ids = '12345,67890';

-- Generate repro scripts for specific query IDs
EXECUTE dbo.sp_QueryReproBuilder
    @include_query_ids = '100,200,300';

-- Exclude specific plan IDs
EXECUTE dbo.sp_QueryReproBuilder
    @ignore_plan_ids = '999,888';

-- Filter by date range
EXECUTE dbo.sp_QueryReproBuilder
    @start_date = '2025-01-01',
    @end_date = '2025-01-31';

-- Search for queries from a specific procedure
EXECUTE dbo.sp_QueryReproBuilder
    @procedure_schema = 'dbo',
    @procedure_name = 'usp_GetCustomerOrders';

-- Search for queries containing specific text
EXECUTE dbo.sp_QueryReproBuilder
    @query_text_search = 'SELECT * FROM Orders';

-- Exclude queries containing specific text
EXECUTE dbo.sp_QueryReproBuilder
    @query_text_search_not = 'temp table';

-- Combine multiple filters
EXECUTE dbo.sp_QueryReproBuilder
    @include_query_ids = '500',
    @start_date = '2025-01-15',
    @end_date = '2025-01-20',
    @query_text_search = 'Products';
```

## Output

The procedure returns multiple result sets:

### Main Results
The primary result set contains:
* **database_name**: The database the query came from
* **executable_query**: Clickable XML containing the ready-to-run query script (click to view formatted)
* **embedded_constants**: For queries with OPTION(RECOMPILE), shows literal values embedded in the plan
* **parameter_values**: The compiled parameter values from the plan
* **query_id/plan_id**: Identifiers to correlate back to Query Store
* **query_sql_text**: The original query text from Query Store
* **query_plan**: The query execution plan (clickable XML)
* All runtime statistics (duration, CPU, reads, writes, memory, etc.)
* Wait statistics broken down by category

### Warnings
Warnings are displayed in the executable_query script header and indicate potential issues with reproduction:
* **temp table**: Query uses temporary tables that may need to be created
* **table variable**: Query uses table variables that may need to be created
* **parameter embedding optimization**: Query uses OPTION(RECOMPILE) with embedded constants
* **parameter count mismatch**: Parameter declarations exist but no values found in plan (likely local variables)
* **plan too large for XML parsing**: Query plan couldn't be cast to XML
* **encrypted module**: Query is from an encrypted module
* **restricted text**: Query text is restricted (contains passwords or sensitive information)

### Additional Result Sets
* **#query_parameters**: Extracted parameters with names, data types, and compiled values
* **#embedded_constants**: Constants extracted from plans using parameter embedding
* **#reproduction_warnings**: All warnings for all plans
* All Query Store tables populated during execution (runtime stats, plans, queries, context settings, wait stats, etc.)

## Notes

* The **executable_query** column is displayed as XML with a processing instruction wrapper (`<?_ ... ?>`). Click on it in SSMS to view the formatted, executable script.
* For queries with parameters, the script generates `EXECUTE sys.sp_executesql` statements with proper parameter declarations and values.
* For queries without parameters, the script contains just the query text with context settings.
* Context settings (SET options) are decoded from binary and included in the script to match the original execution environment.
* For queries using OPTION(RECOMPILE), parameter values are embedded in the plan as constants. These are extracted separately and displayed in the **embedded_constants** column.
* Plans too large to cast to XML will have parameters extracted using string parsing on the ParameterList fragment.

## Resources
* [Blog post](https://www.erikdarling.com/sp_queryreprobuilder/)
