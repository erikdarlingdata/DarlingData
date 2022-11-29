CREATE OR ALTER FUNCTION
    dbo.FutureValue_Inline
(
    @Rate float,
    @Periods int,
    @Payment float,
    @Value float,
    @Type int
)
RETURNS TABLE
AS
RETURN
/*
For support, head over to GitHub:
https://github.com/erikdarlingdata/DarlingData
*/
    WITH pre AS
    (
        SELECT
            Type =
               ISNULL(@Type, 0),
            Value =
               ISNULL(@Value, 0),
            Term =
               POWER(1 + @Rate, @Periods)

    ),
        post AS
    (
        SELECT
            FutureValue =
                CASE
                    WHEN @Rate = 0
                    THEN (p.Value + @Payment) * @Periods
                    WHEN (@Rate <> 0
                           AND p.Type = 0)
                    THEN p.Value * p.Term + @Payment * (p.Term - 1) / @Rate
                    WHEN (@Rate <> 0
                           AND p.Type = 1)
                    THEN p.Value * p.Term + @Payment * (1 + @Rate) * (p.Term - 1.0) / @Rate
                END
        FROM pre AS p
    )
    SELECT
        FutureValue =
            CONVERT
            (
                float,
                p.FutureValue * -1.
            )
    FROM post AS p;
GO