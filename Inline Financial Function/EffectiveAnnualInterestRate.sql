CREATE OR ALTER FUNCTION dbo.EffectiveAnnualInterestRate_Inline
(
    @Rate float,
    @Periods int
)
RETURNS table
AS
RETURN
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