SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
SET IMPLICIT_TRANSACTIONS OFF;
SET STATISTICS TIME, IO OFF;
GO

CREATE OR ALTER FUNCTION
    dbo.EffectiveAnnualInterestRate_Inline
(
    @Rate float,
    @Periods integer
)
RETURNS TABLE
AS
RETURN
/*
For support, head over to GitHub:
https://github.com/erikdarlingdata/DarlingData
*/
    SELECT
        Rate =
            CONVERT
            (
                float,
                CASE
                    WHEN (@Rate < 1)
                      OR (@Periods < 1)
                    THEN 0
                    ELSE POWER(1 + @Rate / @Periods, @Periods) - 1
                END
            );
GO