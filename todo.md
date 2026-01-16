# DarlingData Code Review TODO

## sp_HealthParser.sql

### High Priority (Bugs)

- [x] **Memory Grant Conversion Error (Lines 5345-5352)** - FIXED. Removed `* 8` from KB columns.

- [x] **@wait_duration_ms ISNULL Mismatch (Line 453)** - FIXED. Changed to `ISNULL(@wait_duration_ms, 500)`.

- [x] **Deadlock Database Filter Logic** - NOT A BUG. Upstream validation added earlier handles invalid database names.

### Low Priority (Code Quality)

- [ ] **Unused Variables (Lines 221, 233)** - `@azure_msg` and `@mi_msg` declared and assigned but never used. SKIPPED - may be for future use.

- [ ] **Unused Columns in #scheduler_details (Lines 2717-2718)** - `name` and `component` columns extracted from XML but never referenced. SKIPPED - useful for debugging.

- [ ] **Commented-Out Dead Code (Lines 4454-4526)** - ~70 lines of `#useless` table code commented out. SKIPPED - intentionally preserved for future use.

- [x] **datetime vs datetime2 inconsistency (Lines 5097-5099)** - FIXED. Changed to `datetime2` for consistency.

---

## sp_HumanEvents.sql

### High Priority (Bugs)

- [x] **Azure Stopped Sessions Restart Logic Bug (Lines 3578-3588)** - FIXED. Changed to `LEFT JOIN` and added `AND dxs.create_time IS NULL`.

- [x] **Cleanup Section Missing Azure Support (Lines 4818-4828)** - FIXED. Added `IF @azure = 0 / ELSE` branch for Azure support.

- [x] **Division by Zero in Query Stats (Lines 3363, 3367)** - FIXED. Added `NULLIF(deqs.execution_count, 0)`.

### Low Priority

- [x] **datetime vs datetime2 inconsistencies (Lines 398-399, 518, 4707)** - FIXED. Changed to `datetime2(7)`. Line 79 (@version_date OUTPUT) left as datetime for backwards compatibility.

- [x] **Abbreviated data type INT (Line 4800)** - FIXED. Changed to `integer`.

---

## sp_HumanEventsBlockViewer.sql

### High Priority (Bugs)

- [x] **Azure Event File - Wrong DMV and Type Mismatch (Lines 1079-1111)** - FIXED. Changed to use `sys.database_event_session_targets`, `sys.database_event_sessions`, and `sys.database_event_session_fields` (catalog views with integer IDs).

- [x] **System Health - Column Name Mismatch (Lines 1318-1319 vs 1375-1376)** - FIXED. Changed `#blocked_sh` to use `last_transaction_started`/`last_transaction_completed` for consistency.

### Low Priority

- [ ] **datetime vs datetime2 (Line 85)** - `@version_date` OUTPUT parameter uses datetime. SKIPPED - backwards compatibility.

- [x] **Inconsistent Date Literal Formats (Lines 1688, 2734)** - FIXED. Changed to `'19000101'`.

- [x] **Redundant Nested BEGIN/END (Lines 1861-1867)** - FIXED. Removed unnecessary inner BEGIN/END.

---

## sp_IndexCleanup.sql

### Fixed Earlier (needs re-review like other procedures)

- [x] **Help @debug default (Line 192)** - FIXED. Changed from 'true' to 'false'.

- [x] **Missing space in CREATE INDEX (Line 4625)** - FIXED. Added space.

- [x] **@@ROWCOUNT usage (Lines 3185, 3318)** - FIXED. Changed to ROWCOUNT_BIG().

- [x] **@min_rows type mismatch (Line 2312)** - FIXED. Changed from integer to bigint.

- [x] **#requested_but_skipped_databases logic order** - FIXED. Moved to after #databases is populated.

### New Issues Found (Multi-Agent Review)

#### High Priority (Bugs)

- [x] **Missing ELSE Clause in CASE Expression (Lines 2179-2189)** - NOT A BUG. WHERE clause at line 2212 filters to `i.type IN (1, 2)`, so CASE always matches.

- [x] **Missing index_id in JOIN Condition (Lines 1434-1436)** - FIXED. Removed dead LEFT JOIN to `dm_db_index_usage_stats` entirely - no columns were selected from it. Left comment for future reference.

- [x] **@supports_optimize_for_sequential_key Missing Standard Edition (Lines 294-318)** - FIXED. Changed `= 3` to `IN (2, 3)` to include Standard Edition.

#### Medium Priority

- [x] **Help Section Default Value Inconsistencies (Lines 60,61 vs 187,188)** - FIXED. Changed help section to show `'false'` for `@dedupe_only` and `@get_all_databases` to match declarations.

#### Low Priority (Code Quality)

- [x] **datetime vs datetime2 (Lines 67, 598-601)** - NOT AN ISSUE. The temp table columns match the source DMV `sys.dm_db_index_usage_stats` which uses `datetime`. `@version_date` OUTPUT parameter stays `datetime` for backwards compatibility.

- [x] **ROW_NUMBER Deduplication Ordering (Lines 6029-6052)** - FIXED. Removed stale comment about "non-NULL result types" - column is NOT NULL so comment was misleading.

---

## sp_LogHunter.sql

### High Priority (Bugs)

- [x] **Date Filtering May Delete Current Log (Lines 364-374)** - NOT A BUG. Intentional - explicit date ranges should filter the current log too since it can contain weeks/months of data.

- [x] **@days_back NULL in DATEADD (Lines 465, 493)** - NOT A BUG. The ISNULL at line 323 handles this - when start_date is provided, it's used; otherwise falls back to days_back. The NULL days_back is intentional when explicit dates are given.

- [x] **@t_searches Type Mismatch (Lines 272, 510)** - FIXED. Changed `@t_searches` from `integer` to `bigint`.

### Medium Priority

- [x] **Typo in Help Section (Line 111)** - FIXED. "substitions" → "substitutions".

### Low Priority (Code Quality)

- [x] **datetime vs datetime2 (Lines 55, 56, 64, 286)** - NOT AN ISSUE. xp_readerrorlog returns datetime, so keeping datetime for consistency.

- [x] **Redundant @stopper and BREAK (Lines 644-646)** - FIXED. Removed @stopper variable entirely - it was only ever set right before BREAK, making it pointless.

- [x] **Confusing CTE Alias (Lines 708-711)** - SKIPPED. Not worth changing.

---

## sp_PerfCheck.sql

### High Priority (Bugs)

- [x] **@processors Never Initialized (Line 257)** - FIXED. Added `SELECT @processors = osi.cpu_count FROM sys.dm_os_sys_info` after line 845.

- [x] **@physical_memory_gb Used Before Assignment (Line 1145 vs 2950)** - FIXED. Added assignment from sys.dm_os_sys_info before the LPIM check.

- [x] **Operator Precedence Bug in Trace Events (Lines 1490-1512)** - FIXED. Wrapped event conditions in parentheses so date filter applies to all events.

- [x] **Wrong Variable in Debug Print (Line 2906)** - FIXED. Changed `PRINT @file_io_sql` to `PRINT @db_size_sql`.

- [x] **Duplicate check_id 5001 (Lines 1420, 1538)** - FIXED. Changed "Default Trace Permissions" to check_id 5000.

### Medium Priority

- [x] **@debug Default Mismatch in Help (Lines 52, 121)** - FIXED. Changed help section from 'true' to 'false'.

- [x] **@database_name valid_inputs Copy-Paste Error (Line 109)** - FIXED. Changed "indexes in" to "check".

### Low Priority (Code Quality)

- [x] **datetime vs datetime2 (Lines 54, 522, 541)** - NOT AN ISSUE. Source DMVs (sys.databases.create_date, sys.fn_trace_gettable.StartTime) use datetime. @version_date OUTPUT parameter stays datetime for backwards compatibility.

---

## sp_PressureDetector.sql

### High Priority (Bugs)

- [x] **Missing Comma in Table Definition (Lines 847-848)** - FIXED. Added comma after `live_query_plan xml NULL` before PRIMARY KEY.

- [x] **Duplicated sp_executesql Call (Lines 907-923)** - FIXED BY USER. Removed duplicate execution block.

- [x] **Duplicate CASE Expression for HTREINIT (Lines 1272-1275)** - FIXED. Removed duplicate WHEN clause. Verified all HT* wait types are covered.

- [x] **Wrong Parameter for sys.dm_exec_query_statistics_xml (Lines 3210, 3914)** - FIXED. Changed from plan_handle to session_id (function takes session_id per MS docs).

- [x] **Missing ISNULL for Some Parameters (Lines 228-237)** - FIXED. Added @skip_perfmon, @log_to_table, @troubleshoot_blocking to ISNULL block.

- [x] **Division by Zero in Perfmon Counters (Lines 2105-2115, 2156-2157)** - FIXED. Wrapped DATEDIFF with ISNULL(..., 1) to avoid divide by zero.

### Low Priority (Code Quality)

- [x] **@@ROWCOUNT instead of ROWCOUNT_BIG() (Line 3695)** - FIXED. Changed to ROWCOUNT_BIG().

- [x] **Missing AS keyword on table alias (Line 2605)** - FIXED. Changed to `FROM sys.dm_os_sys_info AS osi`.

### Not Issues

- datetime types are justified (match source DMVs like sys.dm_exec_query_memory_grants)
- Parameter/help section defaults all match correctly
- No abbreviated data types, no COUNT() issues

---

## sp_QueryReproBuilder.sql

### High Priority (Bugs)

- [x] **Query Store Wait Stats Version Check Missing (Lines 2452-2532)** - FIXED. Added @sql_2017 variable (set for version >= 14 or Azure) and wrapped wait stats section with IF @sql_2017 = 1.

- [x] **Wildcard Procedure Filtering Broken (Lines 554-597)** - FIXED. Ported wildcard handling from sp_QuickieStore: added #procedure_object_ids table, wildcard procedure existence check, and wildcard filter branches in all 4 procedure filter sections.

- [x] **Missing @isolation_level in Dynamic SQL (Lines 2168, 2226, 2292, 2452, 2542, 2595, 2640)** - FIXED. Changed all 7 occurrences from `@sql = N''` to `@sql = @isolation_level`.

### Low Priority (Code Quality)

- [x] **Swapped Parameter Comments (Lines 60-61)** - FIXED. Swapped comments so @include_plan_ids says "plan ids" and @include_query_ids says "query ids".

- [x] **Unused Variable @where_clause (Line 193)** - FIXED. Removed unused variable.

- [x] **Unused Temp Table #query_text_parameters (Lines 948-954)** - FIXED. Removed unused temp table.

### Not Issues

- datetime on @version_date (Line 71) - backwards compatibility
- No @@ROWCOUNT, no COUNT(), no abbreviated types

---

## sp_QuickieStore.sql

### High Priority (Bugs)

- [x] **RAISERROR Parameter Order Reversed (Line 3223)** - FIXED. Swapped to `@procedure_name, @procedure_schema`.

- [x] **Debug Output Duplicate Column Name (Line 10354)** - FIXED. Changed to `only_query_with_variants`.

- [x] **Missing @isolation_level in Expert Mode Dynamic SQL (Lines 9435, 9660, 9799, 9977)** - FIXED. Changed all four to use `@sql = @isolation_level`.

### Medium Priority

- [x] **Typo in @regression_direction Comment (Line 101)** - FIXED. "want do you want" → "what do you want".

- [x] **Missing ISNULL Handling for Parameters** - FIXED. Added `@escape_brackets`, `@query_type`, `@execution_type_desc` to ISNULL/NULLIF block.

- [x] **COUNT() instead of COUNT_BIG() (Line 5522)** - FIXED. Changed to COUNT_BIG().

- [x] **Abbreviated Data Type 'int' in Dynamic SQL (12 occurrences)** - FIXED. Changed all `N'@database_id int'` to `N'@database_id integer'`.

### Low Priority (Code Quality)

- [ ] **Missing ELSE Branch in @wait_filter CASE (Lines 5116-5132)** - SKIPPED. Validation exists earlier, defensive coding not needed.

- [ ] **datetime Instead of datetime2 in #troubleshoot_performance (Lines 1463-1464)** - SKIPPED. Internal temp table, no external impact.

- [x] **EXEC Instead of EXECUTE (Line 4196)** - FIXED. Changed to EXECUTE.

### Not Issues

- datetime on @version_date (Line 108) - backwards compatibility with OUTPUT parameter
- Azure SQL MI @ags_present logic - appears intentional, Azure SQL MI AG support is complex
