<img src="https://erikdarling.com/wp-content/uploads/2025/08/darling-data-logo_RGB.jpg" width="300px" />

# sp_QuickieCache

The plan cache companion to sp_QuickieStore.

While QuickieStore digs into Query Store data, QuickieCache uses the same Pareto (80/20) analysis approach against the plan cache DMVs to find the vital few queries consuming disproportionate resources.

## How It Works

1. **Collects** data from all four plan cache stat DMVs (`dm_exec_query_stats`, `dm_exec_procedure_stats`, `dm_exec_function_stats`, `dm_exec_trigger_stats`)
2. **Selects candidates** by taking the top N queries per metric dimension (CPU, duration, reads, writes, memory grants, spills, executions) and deduplicating
3. **Scores** each candidate with `PERCENT_RANK` across all 7 dimensions, only counting dimensions where the query consumes >= 0.1% of the total
4. **Surfaces** queries with an `impact_score` above the threshold, along with diagnostic signals

## Result Sets

1. **Plan cache health findings**: plan age distribution, single-use plan bloat per database, duplicate plan detection per database, USERSTORE_TOKENPERM memory pressure
2. **High-impact queries**: Pareto-scored queries with resource shares and diagnostics
3. **Workload profile summary**: concentration analysis (Concentrated / Moderate / Flat) with recommendations

## Diagnostics Detected

* Parameter sniffing (CPU and reads variance > 30% from average)
* Plan instability (multiple cached plans for the same query)
* Wait-bound queries (duration >> CPU)
* Wasteful memory grants (< 10% utilization)
* TempDB spills
* Row count variance
* Rare but expensive queries (few executions, high resource share)
* High frequency queries (> 100 executions/minute)

## Parameters

| parameter_name | data_type | description | default |
|---|---|---|---|
| @top | integer | candidates per metric dimension before dedup | 10 |
| @database_name | sysname | filter to a specific database | NULL |
| @start_date | datetime | only include plans created after this date | NULL |
| @end_date | datetime | only include plans created before this date | NULL |
| @minimum_execution_count | bigint | minimum execution count to include a query | 2 |
| @ignore_system_databases | bit | exclude system databases | 1 |
| @impact_threshold | decimal(3,2) | minimum impact_score to surface | 0.50 |
| @debug | bit | print diagnostic information | 0 |
| @help | bit | display parameter help | 0 |

## Examples

```sql
-- Basic execution
EXECUTE dbo.sp_QuickieCache;

-- Focus on a specific database
EXECUTE dbo.sp_QuickieCache
    @database_name = N'YourDatabase';

-- Only plans created today
EXECUTE dbo.sp_QuickieCache
    @start_date = '20260403';

-- Lower the threshold to surface more queries
EXECUTE dbo.sp_QuickieCache
    @impact_threshold = 0.25,
    @top = 20;

-- Filter to a specific time window
EXECUTE dbo.sp_QuickieCache
    @start_date = '20260401',
    @end_date = '20260402';
```

## Requirements

* SQL Server 2016 SP1+ for full memory grant and spill analysis
* Older versions will work but with reduced metric coverage

## Resources
* [sp_QuickieStore](https://github.com/erikdarlingdata/DarlingData/tree/main/sp_QuickieStore) - the Query Store companion
* [Blog](https://www.erikdarling.com)
