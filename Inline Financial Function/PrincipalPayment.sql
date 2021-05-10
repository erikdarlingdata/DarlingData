CREATE OR ALTER FUNCTION dbo.PrincipalPayment_Inline
(
    @Rate float,
    @Period int,
    @Periods int,
    @Present float,
    @Future float,
    @Type int
)
RETURNS table
AS
RETURN
    SELECT
        PrincipalPayment = 
            (
                (
                    SELECT 
                        p.Payment 
                    FROM dbo.Payment_Inline
                    (
                        @Rate, 
                        @Periods, 
                        @Present, 
                        @Future, 
                        @Type
                    ) AS  p
                )
                 - 
                (
                    SELECT 
                        i.InterestPayment 
                    FROM dbo.InterestPayment_Inline
                    (
                        @Rate, 
                        @Period, 
                        @Periods, 
                        @Present, 
                        @Future, 
                        @Type
                    ) AS i
                )
            );
GO