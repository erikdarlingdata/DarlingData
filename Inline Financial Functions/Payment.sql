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
    dbo.Payment_Inline
(
    @Rate float,
    @Periods integer,
    @Present float,
    @Future float,
    @Type integer
)
RETURNS TABLE
AS
RETURN
/*
For support, head over to GitHub:
https://code.erikdarling.com
*/
    WITH pre AS
    (
       SELECT
           Type =
               ISNULL(@Type, 0),
           Future =
               ISNULL(@Future, 0),
           Term =
               POWER(1 + @Rate, @Periods)
    ),
         post AS
    (
        SELECT
            Payment =
                CASE
                    WHEN @Rate = 0
                    THEN (@Present + p.Future) / @Periods
                    WHEN (@Rate <> 0
                           AND p.Type = 0)
                    THEN p.Future * @Rate / (p.Term - 1) + @Present * @Rate / (1 - 1 / p.Term)
                    WHEN (@Rate <> 0
                           AND p.Type = 1)
                    THEN (p.Future * @Rate / (p.Term - 1) + @Present * @Rate / (1 - 1 / p.Term)) / (1 + @Rate)
                END
        FROM pre AS p
    )
    SELECT
        Payment =
            CONVERT
            (
                float,
                p.Payment * -1
            )
    FROM post AS p;
GO
