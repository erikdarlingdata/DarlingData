/*
CI Test: Run default execution for procedures that are safe to execute without special setup.
Procs requiring extended events or special data (sp_HumanEvents, sp_HumanEventsBlockViewer,
sp_QueryReproBuilder) are tested with @help = 1 only (see test_help_output.sql).
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

/* sp_PerfCheck - comprehensive performance health check */
BEGIN TRY
    EXEC dbo.sp_PerfCheck;
    INSERT #exec_results VALUES ('sp_PerfCheck', 1);
    PRINT 'PASS: sp_PerfCheck (default)';
END TRY
BEGIN CATCH
    INSERT #exec_results VALUES ('sp_PerfCheck', 0);
    PRINT 'FAIL: sp_PerfCheck - ' + ERROR_MESSAGE();
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
