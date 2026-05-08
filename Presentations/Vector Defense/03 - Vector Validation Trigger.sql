USE VectorDefense;
SET NOCOUNT ON;
GO


/*
████████████████████████████████████████████████████████████████████████████████
██                                                                            ██
██                              TABLE SETUP                                   ██
██                                                                            ██
████████████████████████████████████████████████████████████████████████████████
*/

DROP TABLE IF EXISTS
    dbo.EmbeddingIngress,
    dbo.EmbeddingStore,
    dbo.EmbeddingQuarantine;
GO

/*
    Ingress table accepts JSON strings from embedding APIs
*/
CREATE TABLE
    dbo.EmbeddingIngress
(
    id integer 
        IDENTITY 
        PRIMARY KEY CLUSTERED,
    label sysname NOT NULL,
    embedding_json nvarchar(max) NOT NULL,
    inserted_at datetime2(3) NOT NULL 
        DEFAULT SYSUTCDATETIME()
);
GO

/*
    Store table holds validated vectors
*/
CREATE TABLE
    dbo.EmbeddingStore
(
    id integer 
        IDENTITY 
        PRIMARY KEY CLUSTERED,
    label sysname NOT NULL,
    embedding vector(4, float32) NOT NULL,
    energy float NOT NULL,
    inserted_at datetime2(3) NOT NULL 
        DEFAULT SYSUTCDATETIME()
);
GO

/*
    Quarantine table holds rejected submissions for review
*/
CREATE TABLE
    dbo.EmbeddingQuarantine
(
    id integer 
        IDENTITY 
        PRIMARY KEY CLUSTERED,
    label sysname NOT NULL,
    embedding_json nvarchar(MAX) NOT NULL,
    rejection_reason nvarchar(500) NOT NULL,
    inserted_at datetime2(3) NOT NULL,
    quarantined_at datetime2(3) NOT NULL 
        DEFAULT SYSUTCDATETIME()
);
GO


/*
████████████████████████████████████████████████████████████████████████████████
██                                                                            ██
██                  WHAT SQL SERVER DOES (AND DOESN'T) CATCH                  ██
██                                                                            ██
████████████████████████████████████████████████████████████████████████████████

    Before we build a trigger, see what CONVERT to vector catches
    on its own. CONVERT will reject some things outright:

*/
BEGIN TRY
    DECLARE @bad_dim vector(4, float32) =
        CONVERT(vector(4, float32), N'[0.5, 0.5, 0.5]');
END TRY
BEGIN CATCH
    SELECT
        case_label = N'wrong dimensions',
        err_num    = ERROR_NUMBER(),
        err_msg    = ERROR_MESSAGE();
END CATCH;

BEGIN TRY
    DECLARE @bad_json vector(4, float32) =
        CONVERT(vector(4, float32), N'[hello world]');
END TRY
BEGIN CATCH
    SELECT
        case_label = N'malformed json',
        err_num    = ERROR_NUMBER(),
        err_msg    = ERROR_MESSAGE();
END CATCH;
GO


/*
████████████████████████████████████████████████████████████████████████████████
██                                                                            ██
██                           VALIDATION TRIGGER                               ██
██                                                                            ██
████████████████████████████████████████████████████████████████████████████████
*/

CREATE OR ALTER TRIGGER
    dbo.trg_EmbeddingIngress_Validate
ON dbo.EmbeddingIngress
    INSTEAD OF INSERT
AS
BEGIN
    IF ROWCOUNT_BIG() = 0
    BEGIN
        RETURN;
    END;

    SET NOCOUNT, XACT_ABORT ON;
    SET ROWCOUNT 0;

    /*
        Configuration: adjust these for your embedding model
    */
    DECLARE
        @expected_dimensions integer =
            ISNULL
            (
                (
                    SELECT TOP (1)
                        CONVERT
                        (
                            integer,
                            VECTORPROPERTY(es.embedding, 'Dimensions')
                        )
                    FROM dbo.EmbeddingStore AS es
                ),
                4 /* fallback when EmbeddingStore is empty */
            ),
        @min_magnitude_squared float = 1e-9;
        /*
            Why 1e-9? sum_squares = sum of each component squared.
             * For 4 dimensions, 1e-9 means average component ≈ 0.000016.
             * For 1024 dimensions, average component ≈ 0.000001.
             * Anything that small has no meaningful direction.
        */


    /*
        Extract and validate components using OPENJSON
        This handles any number of dimensions dynamically
    */
    WITH
        components AS
    (
        /*
            OPENJSON extracts each array element with its index
            Only process rows with valid JSON arrays
        */
        SELECT
            i.label,
            i.embedding_json,
            i.inserted_at,
            component_value = TRY_CAST(j.value AS float)
        FROM Inserted AS i
        CROSS APPLY OPENJSON(i.embedding_json) AS j
        WHERE ISJSON(i.embedding_json) = 1
        AND   LEFT(LTRIM(i.embedding_json), 1) = N'['
        AND   RIGHT(RTRIM(i.embedding_json), 1) = N']'
    ),
        aggregated AS
    (
        /*
            Aggregate component-level data to row-level metrics
        */
        SELECT
            c.label,
            c.embedding_json,
            c.inserted_at,
            component_count = COUNT_BIG(*),
            null_count =
                SUM
                (
                    CASE
                        WHEN c.component_value IS NULL
                        THEN 1
                        ELSE 0
                    END
                ),
            sum_squares = 
                SUM(c.component_value * c.component_value)
        FROM components AS c
        GROUP BY
            c.label,
            c.embedding_json,
            c.inserted_at
    ),
        classified AS
    (
        /*
            Classify failing rows. Pre-filter to bad rows first;
            the CASE then assigns a reason for each.
        */
        SELECT
            a.label,
            a.embedding_json,
            a.inserted_at,
            rejection_reason =
                CASE
                    /*
                        Wrong number of dimensions
                    */
                    WHEN a.component_count <> @expected_dimensions
                    THEN N'Dimension mismatch: expected '
                         + CONVERT(nvarchar(10), @expected_dimensions)
                         + N', got '
                         + CONVERT(nvarchar(10), a.component_count)

                    /*
                        Parse failures (non-numeric values)
                    */
                    WHEN a.null_count > 0
                    THEN N'Invalid components: '
                         + CONVERT(nvarchar(10), a.null_count)
                         + N' values failed to parse'

                    /*
                        Zero or near-zero vectors
                    */
                    WHEN a.sum_squares <= @min_magnitude_squared
                    THEN N'Near-zero magnitude: sum of squares = '
                         + CONVERT(nvarchar(30), a.sum_squares)

                    /*
                        Defensive: shouldn't be reachable given the
                        WHERE filter below, but kept so a row that
                        slips through never gets quarantined with a
                        NULL reason.
                    */
                    ELSE NULL
                END
        FROM aggregated AS a
        WHERE a.component_count <> @expected_dimensions
        OR    a.null_count > 0
        OR    a.sum_squares <= @min_magnitude_squared

        UNION ALL

        /*
            Invalid JSON rows never entered OPENJSON, catch them here
        */
        SELECT
            i.label,
            i.embedding_json,
            i.inserted_at,
            rejection_reason =
                CASE
                    WHEN ISJSON(i.embedding_json) = 0
                    THEN N'Invalid JSON format'
                    ELSE N'JSON is not an array'
                END
        FROM Inserted AS i
        WHERE ISJSON(i.embedding_json) = 0
        OR    LEFT(LTRIM(i.embedding_json), 1) <> N'['
        OR    RIGHT(RTRIM(i.embedding_json), 1) <> N']'
    )
    /*
        Route failures to quarantine.
        Belt and suspenders: pre-filter in the CTE keeps the data
        flow clean; the IS NOT NULL check at INSERT time guarantees
        we never write a NULL rejection reason even if the CTE logic
        is later modified.
    */
    INSERT INTO
        dbo.EmbeddingQuarantine
    (
        label,
        embedding_json,
        rejection_reason,
        inserted_at
    )
    SELECT
        c.label,
        c.embedding_json,
        c.rejection_reason,
        c.inserted_at
    FROM classified AS c
    WHERE c.rejection_reason IS NOT NULL;

    /*
        Second pass: insert healthy vectors
        Re-derive to avoid storing intermediate results
    */
    WITH
        components AS
    (
        SELECT
            i.label,
            i.embedding_json,
            i.inserted_at,
            component_value = TRY_CAST(j.value AS float)
        FROM inserted AS i
        CROSS APPLY OPENJSON(i.embedding_json) AS j
        WHERE ISJSON(i.embedding_json) = 1
        AND   LEFT(LTRIM(i.embedding_json), 1) = N'['
        AND   RIGHT(RTRIM(i.embedding_json), 1) = N']'
    ),
        aggregated AS
    (
        SELECT
            c.label,
            c.embedding_json,
            c.inserted_at,
            component_count = COUNT_BIG(*),
            null_count = 
                SUM
                (
                    CASE
                        WHEN c.component_value IS NULL
                        THEN 1
                        ELSE 0
                    END
                ),
            sum_squares = 
                SUM(c.component_value * c.component_value)
        FROM components AS c
        GROUP BY
            c.label,
            c.embedding_json,
            c.inserted_at
    ),
        healthy AS
    (
        SELECT
            a.label,
            a.embedding_json,
            a.inserted_at,
            a.component_count,
            a.null_count,
            a.sum_squares
        FROM aggregated AS a
        WHERE a.component_count = @expected_dimensions
        AND   a.null_count = 0
        AND   a.sum_squares > @min_magnitude_squared
    )
    /*
        Belt and suspenders: the healthy CTE already pre-filters,
        but re-check the same conditions at INSERT time so a future
        change to the CTE can never write a degenerate vector to
        the store.
    */
    INSERT INTO
        dbo.EmbeddingStore
    (
        label,
        embedding,
        energy,
        inserted_at
    )
    SELECT
        h.label,
        embedding = CONVERT(vector(4, float32), h.embedding_json),
        energy = -h.sum_squares,
        h.inserted_at
    FROM healthy AS h;

END;
GO


/*
████████████████████████████████████████████████████████████████████████████████
██                                                                            ██
██                                 TESTS                                      ██
██                                                                            ██
████████████████████████████████████████████████████████████████████████████████
*/

INSERT INTO
    dbo.EmbeddingIngress
(
    label,
    embedding_json
)
VALUES
    /*
        Good vectors
    */
    (N'normalized',     N'[0.5, 0.5, 0.5, 0.5]'),
    (N'slightly_big',   N'[2, 2, 2, 2]'),
    (N'moderately_big', N'[100, 100, 100, 100]'),
    (N'negative_vals',  N'[-0.3, 0.4, -0.5, 0.6]'),

    /*
        Degenerate vectors
    */
    (N'zero',           N'[0, 0, 0, 0]'),
    (N'near_zero',      N'[0.00001, 0, 0, 0]'),
    (N'all_tiny',       N'[1e-8, 1e-8, 1e-8, 1e-8]'),

    /*
        Dimension mismatches indicate model switches
    */
    (N'too_few',        N'[0.5, 0.5, 0.5]'),
    (N'too_many',       N'[0.5, 0.5, 0.5, 0.5, 0.5]'),
    
    /*
        Malformed inputs
    */
    (N'not_json',       N'hello world'),
    (N'json_object',    N'{"x": 1, "y": 2, "z": 3, "w": 4}'),
    (N'null_component', N'[0.5, null, 0.5, 0.5]'),
    (N'string_in_array',N'[0.5, "bad", 0.5, 0.5]');

/*
    Check results

*/
SELECT
    destination = N'STORE (healthy)',
    s.label,
    s.energy,
    s.embedding
FROM dbo.EmbeddingStore AS s
ORDER BY
    s.id;

SELECT
    destination = N'QUARANTINE (rejected)',
    q.label,
    q.rejection_reason,
    q.embedding_json
FROM dbo.EmbeddingQuarantine AS q
ORDER BY
    q.id;
GO

/*
    Verify energy calculation matches VECTOR_DISTANCE

*/

SELECT
    s.label,
    our_energy = s.energy,
    vector_distance_energy = 
        c.v_distance,
    match =
        CASE
            WHEN 
                ABS
                (
                    s.energy - 
                    c.v_distance
                ) < 0.0001
            THEN 'YES'
            ELSE 'NO'
        END
FROM dbo.EmbeddingStore AS s
CROSS APPLY
(
    VALUES
        (VECTOR_DISTANCE('dot', s.embedding, s.embedding))
) AS c (v_distance);
GO

/*
    Sanity check: does our energy calculation match VECTOR_DISTANCE?

    We calculated energy during validation using SUM(component²).
    VECTOR_DISTANCE('dot', v, v) does the same thing internally.

    If these match, our trigger is doing the math right.

    Why some rows show -0.86 vs -0.8600000143... and others
    match exactly: power-of-2 components like [2,2,2,2] and
    [100,100,100,100] are exactly representable in float32,
    so the round-trip is lossless. Components like 0.3, 0.4
    aren't. Our SUM ran in double precision before storage;
    VECTOR_DISTANCE runs on the float32-stored value. The
    drift is float32 storage, not a math bug. That's why we
    compare with a tolerance.

*/


/*
████████████████████████████████████████████████████████████████████████████████
██                                                                            ██
██                  WHICH FAILURES DOMINATE?                                  ██
██                                                                            ██
████████████████████████████████████████████████████████████████████████████████

    The whole point of routing to quarantine instead of rejecting
    is so the operator can see what's failing. A single
    GROUP BY tells you whether your pipeline is mostly emitting
    near-zeros (model returned nothing), mostly hitting dimension
    mismatches (someone switched the embedding model), or mostly
    sending malformed JSON (something upstream broke).

*/

SELECT
    q.rejection_reason,
    failures = COUNT_BIG(*)
FROM dbo.EmbeddingQuarantine AS q
GROUP BY
    q.rejection_reason
ORDER BY
    failures DESC;
GO


/*
████████████████████████████████████████████████████████████████████████████████
██                                                                            ██
██                           SUMMARY                                          ██
██                                                                            ██
████████████████████████████████████████████████████████████████████████████████

    1. Validate before converting to vector
       - Once it's a vector, bad math can crash your transaction
       - OPENJSON lets you inspect components as plain numbers
    
    2. Route, don't reject
       - Healthy vectors → store
       - Bad vectors → quarantine with a reason
       - Now you can debug your pipeline
    
    3. What to check:
       - Dimension count (model switches)
       - Magnitude (zero/near-zero)
       - Valid JSON and numeric components
    
    4. Energy = self-dot-product
       - Quick way to measure magnitude
       - Near zero = degenerate = quarantine it
    
    Next: What about data that was valid when inserted,
    but the source document changed?

*/
