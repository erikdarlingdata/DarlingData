/*
sp_IndexCleanup Manual Test Runs
=================================
Assorted ways to invoke the procedure once fixtures are in place. These are for
eyeballing output, not assertions - the automated checks live in run_tests.py.

Prerequisites:
  1. fixtures_dupe_indexes.sql
  2. generate_index_reads.sql

Then run these individually rather than as one batch: most produce large result
sets, and @debug = 1 produces a lot more.
*/

/* Basic execution for a database */
EXECUTE dbo.sp_IndexCleanup
    @database_name = 'StackOverflow2013',
    @debug = 1;

/* Target a specific schema and table */
EXECUTE dbo.sp_IndexCleanup
    @database_name = 'StackOverflow2013',
    @schema_name = 'dbo',
    @table_name = 'Users',
    @debug = 0;

/*
Only consider indexes with minimum usage and size.

Both floors are applied twice: once per object (a table qualifies when its
indexes together clear a floor) and once per index (an individual index is
dropped from the analysis when it misses on its own). An index counts as used
when it clears EITHER floor.

With generate_index_reads.sql's default 100 iterations each index carries ~100
reads, so @min_reads = 1000 screens all of them out and the run comes back
empty. Lower the floor or raise the iteration count to see it filter partially,
which is the interesting case.
*/
EXECUTE dbo.sp_IndexCleanup
    @database_name = 'StackOverflow2013',
    @min_reads = 1000,    /* Only analyze indexes with at least 1000 reads */
    @min_writes = 500,    /* Only analyze indexes with at least 500 writes */
    @min_size_gb = 0.01,  /* Only analyze indexes at least 10MB in size */
    @min_rows = 10000,    /* Only analyze tables with at least 10,000 rows */
    @debug = 0;

/* Same filters, with the diagnostic output */
EXECUTE dbo.sp_IndexCleanup
    @database_name = 'StackOverflow2013',
    @min_reads = 1000,
    @min_writes = 500,
    @min_size_gb = 0.01,
    @min_rows = 10000,
    @debug = 1;

/* A floor low enough to keep some indexes and drop others */
EXECUTE dbo.sp_IndexCleanup
    @database_name = 'StackOverflow2013',
    @min_reads = 50,
    @debug = 0;

/* Deduplication rules only, skipping compression analysis */
EXECUTE dbo.sp_IndexCleanup
    @database_name = 'StackOverflow2013',
    @dedupe_only = 1,
    @debug = 0;

/* Production run without debug output */
EXECUTE dbo.sp_IndexCleanup
    @database_name = 'StackOverflow2013',
    @debug = 0;

/* View help documentation */
EXECUTE dbo.sp_IndexCleanup
    @help = 1;
