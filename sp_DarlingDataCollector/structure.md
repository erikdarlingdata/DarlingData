# DarlingDataCollector Revised Structure

Based on our review, we need to restructure the solution to address several key issues. Here's the plan:

## Core Issues and Solutions

1. **Blocking Data Collection**: 
   - Replace active waiting task detection with blocked process report XE approach
   - Reference `sp_HumanEventsBlockViewer.sql` implementation
   - Create table schema that accommodates XE data format
   - Implement proper XML parsing for the blocked process reports

2. **Deadlock Detection**:
   - Add deadlock collection based on xml_deadlock_report XE
   - Reference `sp_BlitzLock.sql` implementation
   - Create table schema for storing deadlock graphs
   - Implement XML parsing for deadlock reports

3. **Connections Monitoring**:
   - Replace naive session collection with more comprehensive approach
   - Reference `sp_whoisactive.sql` and `sp_BlitzWho.sql` implementations
   - Include query details, resource consumption, plan cache info
   - Avoid repeated collection of duplicate plans/texts

4. **Database-Specific Collections**:
   - Modify index usage stats and other database-specific collections
   - Add parameters to specify target database(s)
   - Create iteration mechanism for collecting from multiple databases
   - Ensure proper database context handling

5. **I/O Stats Collection**:
   - Create separate code paths for on-prem vs. managed instances
   - Reference `sp_PressureDetector` and `sp_PerfCheck` for examples
   - Handle differences in file path structures and master file joins

6. **Query Stats Collection**:
   - Expand to include procedure, trigger, and function stats
   - Add other relevant plan cache DMVs
   - Implement better query text and plan handling
   - Ensure efficient filtering and storage

7. **DM Coverage Cleanup**:
   - Remove all Azure SQL DB references
   - Ensure consistent environment type handling

8. **Installation Organization**:
   - Create a single, comprehensive installer script
   - Ensure everything is embedded in one file
   - Remove duplicate procedure definitions
   - Add clear validation and error handling

9. **Documentation Structure**:
   - Maintain .md files for documentation only
   - Move all implementation code to .sql files
   - Ensure consistent naming convention

## File Organization

### SQL Implementation Files:
- `DarlingDataCollector_Installation.sql` - Complete installer including all objects
- Individual collection procedures for development/maintenance:
  - `collection.collect_wait_stats.sql`
  - `collection.collect_memory_clerks.sql`
  - `collection.collect_buffer_pool.sql`
  - `collection.collect_io_stats.sql`
  - `collection.collect_index_usage_stats.sql`
  - `collection.collect_connections.sql`
  - `collection.collect_blocking.sql`
  - `collection.collect_deadlocks.sql` (new)
  - `collection.collect_query_stats.sql`

### Documentation Files:
- `README.md` - Project overview
- `DESIGN.md` - Architecture design
- `DMV_COVERAGE.md` - DMV tracking
- `SCHEMA.md` - Database schema documentation
- `ANALYZE.md` - Analysis engine documentation
- `REPORTING.md` - Reporting system documentation

## Next Steps:
1. Update environment detection to remove Azure SQL DB references
2. Rewrite collector_installation.sql with corrected procedures
3. Rewrite blocking collection using XE approach
4. Add deadlock collection using XE approach
5. Improve connections monitoring
6. Fix database-specific collections
7. Create I/O stats with environment-specific code paths
8. Expand query stats collection with additional DMVs
9. Implement data retention procedures

Let's work through these changes one by one to create a technically sound and well-organized solution.