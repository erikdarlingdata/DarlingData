/*
Generation half of the sp_QueryReproBuilder generate-and-execute harness.

run_tests.py substitutes @@PLAN@@ with a ShowPlanXML document (single-quotes
already doubled) and runs this file. The procedure is driven in
@query_plan_xml mode, which bypasses Query Store and is the deterministic entry
point. Its primary result set (table_name = 'results') prints to stdout;
run_tests.py extracts the emitted repro from the executable_query processing
instruction that renders as  <?_ ... ?> .

This is deliberately NOT an INSERT ... EXECUTE capture. sp_QueryReproBuilder can
return different result-set shapes (the wide 'results' set when a repro is built
versus the single-column '#repro_queries is empty' diagnostic when nothing
lands), and a fixed-shape INSERT ... EXECUTE target cannot absorb both. Driving
it through stdout keeps the harness correct no matter which shape comes back.
*/
SET NOCOUNT ON;
SET XACT_ABORT OFF;

DECLARE
    @plan xml = CONVERT(xml, N'@@PLAN@@');

BEGIN TRY
    EXECUTE dbo.sp_QueryReproBuilder
        @query_plan_xml = @plan;
END TRY
BEGIN CATCH
    PRINT 'PROC_ERROR: Msg ' + CONVERT(varchar(20), ERROR_NUMBER()) +
          ' Lvl ' + CONVERT(varchar(20), ERROR_SEVERITY()) +
          ' : ' + ERROR_MESSAGE();
END CATCH;
