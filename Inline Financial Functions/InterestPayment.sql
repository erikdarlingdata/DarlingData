CREATE OR ALTER FUNCTION
    dbo.InterestPayment_Inline
(
    @Rate float,
    @Period integer,
    @Periods integer,
    @Present float,
    @Future float,
    @Type integer
)
RETURNS TABLE
AS
/*
For support, head over to GitHub:
https://github.com/erikdarlingdata/DarlingData
*/
RETURN
    WITH pre AS
    (
        SELECT
            Type =
                ISNULL(@Type, 0),
            Payment =
                (
                    SELECT
                        Payment
                    FROM dbo.Payment_Inline
                    (
                        @Rate,
                        @Periods,
                        @Present,
                        @Future,
                        @Type
                    )
                )
    ),
         post AS
    (
        SELECT
            InterestPayment =
                CASE
                    WHEN (@Period = 1
                            AND p.Type = 1)
                    THEN 0
                    WHEN (@Period = 1
                            AND p.Type = 0)
                    THEN (@Present * - 1.)
                    WHEN (@Period <> 1
                            AND p.Type = 0)
                    THEN (
                             SELECT
                                 FutureValue
                             FROM dbo.FutureValue_Inline
                             (
                                 @Rate,
                                 @Period - 1,
                                 p.Payment,
                                 @Present, 0
                              )
                         )
                    WHEN (@Period <> 1
                            AND p.Type = 1)
                    THEN (
                             SELECT
                                 FutureValue - p.Payment
                             FROM dbo.FutureValue_Inline
                             (
                                 @Rate,
                                 @Period - 2,
                                 p.Payment,
                                 @Present, 1
                              )
                          )
                    END
        FROM pre AS p
    )
    SELECT
        InterestPayment =
        CONVERT
        (
            float,
            p.InterestPayment * @Rate
        )
    FROM post AS p;
GO