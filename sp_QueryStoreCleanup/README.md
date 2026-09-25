<img src="https://erikdarling.com/wp-content/uploads/2025/08/darling-data-logo_RGB.jpg" width="300px" />

# sp_QueryStoreCleanup

Query Store is great, but it collects a lot of noise. System DMV queries, index maintenance, statistics updates, and other background operations all pile up as duplicate entries, wasting space and making it harder to find the queries you actually care about.

This procedure identifies and removes duplicate and noisy queries from Query Store in any database on your server. It uses text pattern matching and hash-based deduplication to find the junk, and removes it using `sp_query_store_remove_query`.

By default, it targets system queries (`FROM sys.%`), maintenance operations (index rebuilds, statistics updates, DBCC commands, etc.), and removes all copies of duplicated query and plan hashes. You can customize what to target, how to deduplicate, and whether to just report or actually remove.

Queries with forced plans are always protected from removal. On SQL Server 2022 or later, the same protection applies to a query with a forced Query Store hint.

## Parameters

| parameter_name | data_type | description | valid_inputs | defaults |
|---|---|---|---|---|
| @database_name | sysname | the database to clean query store in | a database name with query store enabled | NULL; current database if NULL |
| @cleanup_targets | varchar(100) | what to target for cleanup | all, system, maintenance (or maint), custom, none, or comma-separated combination | all |
| @custom_query_filter | nvarchar(1024) | custom LIKE pattern for query text filtering; also applied when @cleanup_targets = all | a valid LIKE pattern | NULL |
| @dedupe_by | varchar(50) | deduplication strategy | all, query_hash, plan_hash, none | all |
| @min_age_days | integer | only remove queries whose last execution is older than this many days | a positive integer | NULL; no age filter |
| @report_only | bit | report what would be removed without removing; see Report Mode | 0 or 1 | 0 |
| @sort_direction | varchar(10) | removal order by query_id; see Splitting a Long Removal | ASC, DESC | ASC |
| @debug | bit | prints dynamic sql and diagnostics | 0 or 1 | 0 |
| @help | bit | how you got here | 0 or 1 | 0 |
| @version | varchar(30) | OUTPUT; for support | none; OUTPUT | none; OUTPUT |
| @version_date | datetime | OUTPUT; for support | none; OUTPUT | none; OUTPUT |

### Cleanup Targets

The `@cleanup_targets` parameter controls which queries are identified by text pattern matching:

| Value | What It Matches |
|---|---|
| `system` | Queries containing `FROM sys.%` |
| `maintenance` (or `maint`) | Index operations (`ALTER INDEX`, `CREATE INDEX`, `ALTER TABLE`), statistics operations (`UPDATE STATISTICS`, `CREATE STATISTICS`, `SELECT StatMan`), DBCC commands, and parameterized maintenance queries (`@_msparam`) |
| `custom` | Uses your `@custom_query_filter` LIKE pattern |
| `all` | system + maintenance combined; also applies `@custom_query_filter` if provided |
| `none` | No text filtering; deduplication is purely hash-based across all queries |

### Deduplication Strategy

The `@dedupe_by` parameter controls how duplicates are identified after text filtering:

| Value | Behavior |
|---|---|
| `query_hash` | Find queries with duplicate `query_hash` values (same query compiled multiple times) |
| `plan_hash` | Find queries with duplicate `query_plan_hash` values (different queries producing identical plans) |
| `all` | Both query_hash and plan_hash |
| `none` | Skip hash deduplication entirely; send all text-matched queries directly to removal |

**Note:** Hash deduplication removes all copies of duplicated hashes, not all-but-one. This is intentional, as the queries targeted are noise that will be recaptured by Query Store if they execute again.

### Splitting a Long Removal

`sp_query_store_remove_query` removes one query at a time, and removals serialize on a lock, so a big cleanup can run for hours. Two sessions working one list from opposite ends finish sooner: in testing on a Query Store with about 800,000 queries, two sessions removed about 1.4 times as many queries a second as one. More than two sessions added nothing.

Run the same command in two sessions at the same time, one with `@sort_direction = 'ASC'` and one with `@sort_direction = 'DESC'`. Before each removal, the procedure checks that the query still exists, and it skips any query the other session already removed. Two sessions in the same order gain nothing, because they keep trying to remove the same queries.

## Report Mode

`@report_only = 1` removes nothing. It returns two result sets:

1. One summary row for the whole removal list: the number of queries, distinct query hashes, query texts, plans and plan hashes, how many queries belong to modules, the oldest and newest last execution, and the share of all Query Store queries.
2. One row per query_hash, biggest first: the same counts for that hash, the module name if there is one, the oldest and newest last execution, and a sample query_id with the first 200 characters of its text.

Add `@debug = 1` to also list every query_id on the removal list.

## Examples

```sql
-- Default: remove all system + maintenance duplicates from the current database
EXECUTE dbo.sp_QueryStoreCleanup;

-- Target a specific database
EXECUTE dbo.sp_QueryStoreCleanup
    @database_name = N'StackOverflow2013';

-- Report what would be removed without removing anything
EXECUTE dbo.sp_QueryStoreCleanup
    @database_name = N'YourDatabase',
    @report_only = 1;

-- Only clean up system DMV queries
EXECUTE dbo.sp_QueryStoreCleanup
    @database_name = N'YourDatabase',
    @cleanup_targets = 'system';

-- Only clean up maintenance operations (index rebuilds, stats updates, DBCC, etc.)
EXECUTE dbo.sp_QueryStoreCleanup
    @database_name = N'YourDatabase',
    @cleanup_targets = 'maint';

-- Remove all text-matched queries without hash deduplication
EXECUTE dbo.sp_QueryStoreCleanup
    @database_name = N'YourDatabase',
    @cleanup_targets = 'system',
    @dedupe_by = 'none';

-- Use a custom text filter to find specific query patterns
EXECUTE dbo.sp_QueryStoreCleanup
    @database_name = N'YourDatabase',
    @cleanup_targets = 'custom',
    @custom_query_filter = N'%some_noisy_query%';

-- Only remove queries that haven't executed in the last 30 days
EXECUTE dbo.sp_QueryStoreCleanup
    @database_name = N'YourDatabase',
    @min_age_days = 30;

-- Split a long removal: run these two at the same time, in separate sessions
EXECUTE dbo.sp_QueryStoreCleanup
    @database_name = N'YourDatabase',
    @cleanup_targets = 'custom',
    @custom_query_filter = N'%some_noisy_query%',
    @dedupe_by = 'none',
    @sort_direction = 'ASC';

EXECUTE dbo.sp_QueryStoreCleanup
    @database_name = N'YourDatabase',
    @cleanup_targets = 'custom',
    @custom_query_filter = N'%some_noisy_query%',
    @dedupe_by = 'none',
    @sort_direction = 'DESC';

-- Debug mode to see the generated dynamic SQL
EXECUTE dbo.sp_QueryStoreCleanup
    @database_name = N'YourDatabase',
    @debug = 1;
```

Copyright 2026 Darling Data, LLC
Released under MIT license
