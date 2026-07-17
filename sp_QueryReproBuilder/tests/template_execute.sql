/*
Execution half of the sp_QueryReproBuilder generate-and-execute harness.

This is the check that earns the harness its keep. A repro that reads correctly
but will not run is the characteristic failure mode of a generator like this, and
only executing the generated script catches it. SET PARSEONLY ON would sail past
a semantic error; running the repro for real does not.

run_tests.py hands the emitted repro back in as base64 of its utf-16-le bytes
(assigned in @@B64_ASSIGNMENTS@@), so there is no quote-escaping to get wrong and
no 8000-character string-literal limit to trip over on long repros. The repro
lands in a genuine nvarchar(max) variable and is executed with
sys.sp_executesql inside BEGIN TRANSACTION ... ROLLBACK and TRY/CATCH:

  - the transaction rolls back any writes the repro performs (e.g. an UPDATE),
  - sp_executesql defers the repro's compile, so a compile or semantic error in
    the generated SQL is catchable here instead of aborting the whole batch, and
  - EXEC_RESULT reports PASS only when the repro actually ran.

@@RUNNER@@ is replaced with either a plain execute or, for echo cases, an
INSERT ... EXECUTE into a known 3-column #echo table so the actually-bound
parameter values can be read back and asserted.
*/
SET NOCOUNT ON;
SET XACT_ABORT OFF;

DECLARE
    @b64 varchar(max) = CONVERT(varchar(max), '');

@@B64_ASSIGNMENTS@@

DECLARE
    @repro nvarchar(max) =
        CONVERT
        (
            nvarchar(max),
            CAST(N'' AS xml).value('xs:base64Binary(sql:variable("@b64"))', 'varbinary(max)')
        );

@@RUNNER@@
