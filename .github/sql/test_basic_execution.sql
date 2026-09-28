/*
CI Test: Run default execution for procedures that are safe to execute without special setup.
Procs requiring extended events, special data, or host features not available in Docker
(sp_HumanEvents, sp_HumanEventsBlockViewer, sp_QueryReproBuilder, sp_PerfCheck)
are tested with @help = 1 only (see test_help_output.sql).
sp_PerfCheck reads the default trace which does not exist in Docker containers.
sp_QuickieCache has no harness of its own, so it also runs in each of its modes here.
Uses a temp table to track results across GO batches.
*/

SET NOCOUNT ON;

CREATE TABLE #exec_results (proc_name VARCHAR(100) NOT NULL, passed BIT NOT NULL);
GO

PRINT '========================================';
PRINT 'Testing default execution';
PRINT '========================================';
PRINT '';
GO

/* sp_PressureDetector - detects CPU and memory pressure */
BEGIN TRY
    EXEC dbo.sp_PressureDetector;
    INSERT #exec_results VALUES ('sp_PressureDetector', 1);
    PRINT 'PASS: sp_PressureDetector (default)';
END TRY
BEGIN CATCH
    INSERT #exec_results VALUES ('sp_PressureDetector', 0);
    PRINT 'FAIL: sp_PressureDetector - ' + ERROR_MESSAGE();
END CATCH;
GO

/* sp_HealthParser - analyzes system health extended event */
BEGIN TRY
    EXEC dbo.sp_HealthParser;
    INSERT #exec_results VALUES ('sp_HealthParser', 1);
    PRINT 'PASS: sp_HealthParser (default)';
END TRY
BEGIN CATCH
    INSERT #exec_results VALUES ('sp_HealthParser', 0);
    PRINT 'FAIL: sp_HealthParser - ' + ERROR_MESSAGE();
END CATCH;
GO

/* sp_LogHunter - searches error logs */
BEGIN TRY
    EXEC dbo.sp_LogHunter;
    INSERT #exec_results VALUES ('sp_LogHunter', 1);
    PRINT 'PASS: sp_LogHunter (default)';
END TRY
BEGIN CATCH
    INSERT #exec_results VALUES ('sp_LogHunter', 0);
    PRINT 'FAIL: sp_LogHunter - ' + ERROR_MESSAGE();
END CATCH;
GO

/* sp_IndexCleanup - identifies unused/duplicate indexes */
BEGIN TRY
    EXEC dbo.sp_IndexCleanup
        @database_name = N'DarlingData_CI_Test';
    INSERT #exec_results VALUES ('sp_IndexCleanup', 1);
    PRINT 'PASS: sp_IndexCleanup (default)';
END TRY
BEGIN CATCH
    INSERT #exec_results VALUES ('sp_IndexCleanup', 0);
    PRINT 'FAIL: sp_IndexCleanup - ' + ERROR_MESSAGE();
END CATCH;
GO

/* sp_QuickieStore - navigates Query Store data */
BEGIN TRY
    EXEC dbo.sp_QuickieStore
        @database_name = N'DarlingData_CI_Test';
    INSERT #exec_results VALUES ('sp_QuickieStore', 1);
    PRINT 'PASS: sp_QuickieStore (default)';
END TRY
BEGIN CATCH
    INSERT #exec_results VALUES ('sp_QuickieStore', 0);
    PRINT 'FAIL: sp_QuickieStore - ' + ERROR_MESSAGE();
END CATCH;
GO

/* sp_QuickieCache - finds high-impact queries in the plan cache */
BEGIN TRY
    EXECUTE dbo.sp_QuickieCache;
    INSERT #exec_results VALUES ('sp_QuickieCache', 1);
    PRINT 'PASS: sp_QuickieCache (default)';
END TRY
BEGIN CATCH
    INSERT #exec_results VALUES ('sp_QuickieCache', 0);
    PRINT 'FAIL: sp_QuickieCache - ' + ERROR_MESSAGE();
END CATCH;
GO

/*
sp_QuickieCache with every query counted, so the scoring runs
even on a container's small plan cache
*/
BEGIN TRY
    EXECUTE dbo.sp_QuickieCache
        @ignore_system_databases = 0,
        @minimum_execution_count = 1,
        @impact_threshold = 0.00;
    INSERT #exec_results VALUES ('sp_QuickieCache (all queries)', 1);
    PRINT 'PASS: sp_QuickieCache (all queries)';
END TRY
BEGIN CATCH
    INSERT #exec_results VALUES ('sp_QuickieCache (all queries)', 0);
    PRINT 'FAIL: sp_QuickieCache (all queries) - ' + ERROR_MESSAGE();
END CATCH;
GO

/* sp_QuickieCache single-use plans mode */
BEGIN TRY
    EXECUTE dbo.sp_QuickieCache
        @find_single_use_plans = 1;
    INSERT #exec_results VALUES ('sp_QuickieCache (single-use plans)', 1);
    PRINT 'PASS: sp_QuickieCache (single-use plans)';
END TRY
BEGIN CATCH
    INSERT #exec_results VALUES ('sp_QuickieCache (single-use plans)', 0);
    PRINT 'FAIL: sp_QuickieCache (single-use plans) - ' + ERROR_MESSAGE();
END CATCH;
GO

/* sp_QuickieCache duplicate plans mode */
BEGIN TRY
    EXECUTE dbo.sp_QuickieCache
        @find_duplicate_plans = 1;
    INSERT #exec_results VALUES ('sp_QuickieCache (duplicate plans)', 1);
    PRINT 'PASS: sp_QuickieCache (duplicate plans)';
END TRY
BEGIN CATCH
    INSERT #exec_results VALUES ('sp_QuickieCache (duplicate plans)', 0);
    PRINT 'FAIL: sp_QuickieCache (duplicate plans) - ' + ERROR_MESSAGE();
END CATCH;
GO

/* sp_QuickieCache with NULL parameters, which take their defaults */
BEGIN TRY
    EXECUTE dbo.sp_QuickieCache
        @top = NULL,
        @sort_order = NULL,
        @minimum_execution_count = NULL,
        @impact_threshold = NULL;
    INSERT #exec_results VALUES ('sp_QuickieCache (NULL parameters)', 1);
    PRINT 'PASS: sp_QuickieCache (NULL parameters)';
END TRY
BEGIN CATCH
    INSERT #exec_results VALUES ('sp_QuickieCache (NULL parameters)', 0);
    PRINT 'FAIL: sp_QuickieCache (NULL parameters) - ' + ERROR_MESSAGE();
END CATCH;
GO

/* Summary - fail the build if any test failed */
PRINT '';
PRINT '========================================';

DECLARE @failed int = (SELECT COUNT(*) FROM #exec_results WHERE passed = 0);
DECLARE @total int = (SELECT COUNT(*) FROM #exec_results);

PRINT 'Basic execution: ' + CONVERT(varchar(10), @total - @failed) + '/' + CONVERT(varchar(10), @total) + ' passed';

IF @failed > 0
    RAISERROR('%d procedure(s) failed default execution', 16, 1, @failed);
ELSE
    PRINT 'All procedures passed';

PRINT '========================================';

DROP TABLE #exec_results;
GO
