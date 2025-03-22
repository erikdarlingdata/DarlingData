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
    dbo.NumberOfYears_Inline
(
    @Rate float,
    @NumberPayments float,
    @PreviousValue float,
    @FutureValue float,
    @Payment float,
    @PaymentsPerYear float,
    @Type integer
)
RETURNS TABLE
AS
RETURN
/*
For support, head over to GitHub:
https://code.erikdarling.com
*/
    SELECT
        NumberOfYears =
            CONVERT
            (
                float,
                CASE WHEN (@Type = 0
                             OR @Type IS NULL)
                     THEN LOG(((@FutureValue * (POWER(1 + @Rate / @PaymentsPerYear, @PaymentsPerYear / @NumberPayments) - 1) + @Payment))
                              / ((@PreviousValue * (POWER(1 + @Rate / @PaymentsPerYear, @PaymentsPerYear / @NumberPayments) - 1) + @Payment)))
                                  / LOG(POWER(1 + @Rate / @PaymentsPerYear, @PaymentsPerYear))
                     WHEN @Type = 1
                     THEN LOG(((@FutureValue * (POWER(1 + @Rate / @PaymentsPerYear, @PaymentsPerYear / @NumberPayments) - 1)
                              + @Payment * POWER(1 + @Rate / @PaymentsPerYear, @PaymentsPerYear / @NumberPayments)))
                                  / ((@PreviousValue * (POWER(1 + @Rate / @PaymentsPerYear, @PaymentsPerYear / @NumberPayments) - 1) + @Payment
                                      * POWER(1 + @Rate / @PaymentsPerYear, @PaymentsPerYear / @NumberPayments))))
                                          / LOG(POWER(1 + @Rate / @PaymentsPerYear, @PaymentsPerYear))
                END
            );
GO
