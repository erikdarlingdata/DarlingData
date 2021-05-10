CREATE OR ALTER FUNCTION dbo.NumberOfYears_Inline
(
    @Rate float,
    @NumberPayments float,
    @PreviousValue float,
    @FutureValue float,
    @Payment float,
    @PaymentsPerYear float,
    @Type int
)
RETURNS table
AS
RETURN

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