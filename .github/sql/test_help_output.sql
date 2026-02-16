/*
CI Test: Validate @help = 1 output for all procedures.
Uses a temp table to track results across GO batches.
Fails with RAISERROR if any proc errors on @help = 1.
*/

SET NOCOUNT ON;

CREATE TABLE #help_results (proc_name VARCHAR(100) NOT NULL, passed BIT NOT NULL);
GO

PRINT '========================================';
PRINT 'Testing @help = 1 for all procedures';
PRINT '========================================';
PRINT '';
GO

/* sp_HealthParser */
BEGIN TRY
    EXEC dbo.sp_HealthParser @help = 1;
    INSERT #help_results VALUES ('sp_HealthParser', 1);
    PRINT 'PASS: sp_HealthParser @help = 1';
END TRY
BEGIN CATCH
    INSERT #help_results VALUES ('sp_HealthParser', 0);
    PRINT 'FAIL: sp_HealthParser @help = 1 - ' + ERROR_MESSAGE();
END CATCH;
GO

/* sp_HumanEvents */
BEGIN TRY
    EXEC dbo.sp_HumanEvents @help = 1;
    INSERT #help_results VALUES ('sp_HumanEvents', 1);
    PRINT 'PASS: sp_HumanEvents @help = 1';
END TRY
BEGIN CATCH
    INSERT #help_results VALUES ('sp_HumanEvents', 0);
    PRINT 'FAIL: sp_HumanEvents @help = 1 - ' + ERROR_MESSAGE();
END CATCH;
GO

/* sp_HumanEventsBlockViewer */
BEGIN TRY
    EXEC dbo.sp_HumanEventsBlockViewer @help = 1;
    INSERT #help_results VALUES ('sp_HumanEventsBlockViewer', 1);
    PRINT 'PASS: sp_HumanEventsBlockViewer @help = 1';
END TRY
BEGIN CATCH
    INSERT #help_results VALUES ('sp_HumanEventsBlockViewer', 0);
    PRINT 'FAIL: sp_HumanEventsBlockViewer @help = 1 - ' + ERROR_MESSAGE();
END CATCH;
GO

/* sp_IndexCleanup */
BEGIN TRY
    EXEC dbo.sp_IndexCleanup @help = 1;
    INSERT #help_results VALUES ('sp_IndexCleanup', 1);
    PRINT 'PASS: sp_IndexCleanup @help = 1';
END TRY
BEGIN CATCH
    INSERT #help_results VALUES ('sp_IndexCleanup', 0);
    PRINT 'FAIL: sp_IndexCleanup @help = 1 - ' + ERROR_MESSAGE();
END CATCH;
GO

/* sp_LogHunter */
BEGIN TRY
    EXEC dbo.sp_LogHunter @help = 1;
    INSERT #help_results VALUES ('sp_LogHunter', 1);
    PRINT 'PASS: sp_LogHunter @help = 1';
END TRY
BEGIN CATCH
    INSERT #help_results VALUES ('sp_LogHunter', 0);
    PRINT 'FAIL: sp_LogHunter @help = 1 - ' + ERROR_MESSAGE();
END CATCH;
GO

/* sp_PerfCheck */
BEGIN TRY
    EXEC dbo.sp_PerfCheck @help = 1;
    INSERT #help_results VALUES ('sp_PerfCheck', 1);
    PRINT 'PASS: sp_PerfCheck @help = 1';
END TRY
BEGIN CATCH
    INSERT #help_results VALUES ('sp_PerfCheck', 0);
    PRINT 'FAIL: sp_PerfCheck @help = 1 - ' + ERROR_MESSAGE();
END CATCH;
GO

/* sp_PressureDetector */
BEGIN TRY
    EXEC dbo.sp_PressureDetector @help = 1;
    INSERT #help_results VALUES ('sp_PressureDetector', 1);
    PRINT 'PASS: sp_PressureDetector @help = 1';
END TRY
BEGIN CATCH
    INSERT #help_results VALUES ('sp_PressureDetector', 0);
    PRINT 'FAIL: sp_PressureDetector @help = 1 - ' + ERROR_MESSAGE();
END CATCH;
GO

/* sp_QueryReproBuilder */
BEGIN TRY
    EXEC dbo.sp_QueryReproBuilder @help = 1;
    INSERT #help_results VALUES ('sp_QueryReproBuilder', 1);
    PRINT 'PASS: sp_QueryReproBuilder @help = 1';
END TRY
BEGIN CATCH
    INSERT #help_results VALUES ('sp_QueryReproBuilder', 0);
    PRINT 'FAIL: sp_QueryReproBuilder @help = 1 - ' + ERROR_MESSAGE();
END CATCH;
GO

/* sp_QuickieStore */
BEGIN TRY
    EXEC dbo.sp_QuickieStore @help = 1;
    INSERT #help_results VALUES ('sp_QuickieStore', 1);
    PRINT 'PASS: sp_QuickieStore @help = 1';
END TRY
BEGIN CATCH
    INSERT #help_results VALUES ('sp_QuickieStore', 0);
    PRINT 'FAIL: sp_QuickieStore @help = 1 - ' + ERROR_MESSAGE();
END CATCH;
GO

/* Summary - fail the build if any test failed */
PRINT '';
PRINT '========================================';

DECLARE @failed int = (SELECT COUNT(*) FROM #help_results WHERE passed = 0);
DECLARE @total int = (SELECT COUNT(*) FROM #help_results);

PRINT 'Help output: ' + CONVERT(varchar(10), @total - @failed) + '/' + CONVERT(varchar(10), @total) + ' passed';

IF @failed > 0
    RAISERROR('%d procedure(s) failed @help = 1', 16, 1, @failed);
ELSE
    PRINT 'All procedures passed';

PRINT '========================================';

DROP TABLE #help_results;
GO
