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
    dbo.PrincipalPayment_Inline
(
    @Rate float,
    @Period integer,
    @Periods integer,
    @Present float,
    @Future float,
    @Type integer
)
RETURNS table
AS
RETURN
/*
For support, head over to GitHub:
https://code.erikdarling.com
*/
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
