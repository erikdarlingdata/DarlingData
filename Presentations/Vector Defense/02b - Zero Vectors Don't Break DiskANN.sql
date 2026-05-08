USE VectorDefense;
SET NOCOUNT ON;
GO


/*
████████████████████████████████████████████████████████████████████████████████
██                                                                            ██
██                         SET UP THE EXPERIMENT                              ██
██                                                                            ██
████████████████████████████████████████████████████████████████████████████████

    Same good vectors as file 02.
    Instead of 350 duplicates, we add 350 zero vectors.

    Same graph size, same ratio of "bad" data.
    The only difference: zeros instead of duplicates.

*/

DROP TABLE IF EXISTS
    dbo.VectorEmbeddings;
GO

CREATE TABLE
    dbo.VectorEmbeddings
(
    Id integer
        IDENTITY
        PRIMARY KEY CLUSTERED,
    Label nvarchar(50) NOT NULL,
    Kind nvarchar(30) NOT NULL,
    Embedding vector(4, float32) NOT NULL
);
GO

INSERT INTO
    dbo.VectorEmbeddings
(
    Label,
    Kind,
    Embedding
)
VALUES
    /* Same good vectors as file 02 */
    (N'great match', N'good', CONVERT(vector(4, float32), N'[0.5, 0.5, 0.5, 0.5]')),
    (N'near 01', N'good', CONVERT(vector(4, float32), N'[0.52, 0.50, 0.49, 0.49]')),
    (N'near 02', N'good', CONVERT(vector(4, float32), N'[0.48, 0.51, 0.50, 0.51]')),
    (N'near 03', N'good', CONVERT(vector(4, float32), N'[0.51, 0.49, 0.51, 0.49]')),
    (N'near 04', N'good', CONVERT(vector(4, float32), N'[0.49, 0.52, 0.49, 0.50]')),

    /* Same scaled_big and axis vectors, but ONE copy each, no duplication */
    (N'big 01', N'scaled_big', CONVERT(vector(4, float32), N'[5,  5,  5,  5]')),
    (N'big 02', N'scaled_big', CONVERT(vector(4, float32), N'[10, 10, 10, 10]')),
    (N'big 03', N'scaled_big', CONVERT(vector(4, float32), N'[50, 50, 50, 50]')),
    (N'axis x', N'axis', CONVERT(vector(4, float32), N'[1, 0, 0, 0]')),
    (N'axis y', N'axis', CONVERT(vector(4, float32), N'[0, 1, 0, 0]')),
    (N'axis z', N'axis', CONVERT(vector(4, float32), N'[0, 0, 1, 0]')),
    (N'axis w', N'axis', CONVERT(vector(4, float32), N'[0, 0, 0, 1]'));
GO


/*
    Add 350 zero vectors, matching the duplicate count from file 02.

*/

INSERT INTO
    dbo.VectorEmbeddings
(
    Label,
    Kind,
    Embedding
)
SELECT
    Label = CONCAT(N'zero ', g.value),
    Kind = N'zero',
    Embedding = CONVERT(vector(4, float32), N'[0, 0, 0, 0]')
FROM GENERATE_SERIES(1, 350) AS g;
GO

/*
    What did we end up with?

    362 vectors. 350 of them are zeros.
    97% of the graph is [0, 0, 0, 0].

*/

SELECT
    ve.Kind,
    vector_count = COUNT_BIG(*)
FROM dbo.VectorEmbeddings AS ve
GROUP BY
    ve.Kind
ORDER BY
    vector_count DESC;


/*
████████████████████████████████████████████████████████████████████████████████
██                                                                            ██
██                         BUILD DISKANN INDEX                                ██
██                                                                            ██
████████████████████████████████████████████████████████████████████████████████
*/

CREATE VECTOR INDEX
    VectorEmbeddings_DiskANN
ON dbo.VectorEmbeddings
    (Embedding)
WITH
(
    METRIC = 'cosine',
    TYPE = 'DiskANN'
);
GO


/*
████████████████████████████████████████████████████████████████████████████████
██                                                                            ██
██                         RECALL METRICS                                     ██
██                                                                            ██
████████████████████████████████████████████████████████████████████████████████

    Truth set vs ANN result, same as file 02.
    Skipping the side-by-side row table. The headline metrics
    plus the Kind breakdown tell the story.

*/

DROP TABLE IF EXISTS
    #truth,
    #ann;

DECLARE
    @k integer = 50,
    @q vector(4, float32) =
        CONVERT(vector(4, float32), N'[0.5, 0.5, 0.5, 0.5]');

SELECT TOP (@k)
    f.Id,
    f.Label,
    f.Kind,
    truth_distance = VECTOR_DISTANCE('cosine', @q, f.Embedding)
INTO #truth
FROM dbo.VectorEmbeddings AS f
ORDER BY
    truth_distance ASC,
    f.Id ASC;

SELECT TOP (@k) WITH APPROXIMATE
    ve.Id,
    ve.Label,
    ve.Kind,
    ann_distance = vs.distance
INTO #ann
FROM VECTOR_SEARCH
(
    TABLE = dbo.VectorEmbeddings AS ve,
    COLUMN = Embedding,
    SIMILAR_TO = @q,
    METRIC = 'cosine'
) AS vs WITH (FORCE_ANN_ONLY)
ORDER BY
    vs.distance;
GO

DECLARE
    @k integer = 50;

SELECT
    requested_k = @k,
    returned_k =
        (
            SELECT
                COUNT_BIG(*)
            FROM #ann
        ),
    matched =
        (
            SELECT
                COUNT_BIG(*)
            FROM #truth AS t
            JOIN #ann AS a
              ON a.Id = t.Id
        ),
    recall_pct =
        CONVERT
        (
            decimal(5, 2),
            100.0 *
            (
                SELECT
                    COUNT_BIG(*)
                FROM #truth AS t
                JOIN #ann AS a
                  ON a.Id = t.Id
            ) / @k
        ),
    perfect_matches =
        (
            SELECT
                COUNT_BIG(*)
            FROM #truth AS t
            JOIN #ann AS a
              ON a.Id = t.Id
            WHERE t.truth_distance = 0
        ),
    closest_missed_distance =
        (
            SELECT
                MIN(t.truth_distance)
            FROM #truth AS t
            WHERE NOT EXISTS
            (
                SELECT
                    1/0
                FROM #ann AS a
                WHERE a.Id = t.Id
            )
        );
GO

/*
    File 02 vs file 02b at k = 50:
     * 02:  recall ~92%, returned 50, but the ENTIRE result set is duplicates
            from one cosine direction. Zero of the distinct "near" vectors.
     * 02b: recall near 100%, returned 50, and the result contains
            all 5 good + 4 axis + 3 scaled_big = 12 distinct vectors,
            with the rest filled by zeros.

    The recall metric is similar in both. The result contents are not.

*/


/*
    What kinds of vectors did ANN actually return?

    File 02 returned only dups, zero distinct semantic content.
    File 02b's breakdown should look very different.

*/

SELECT
    a.Kind,
    returned = COUNT_BIG(*)
FROM #ann AS a
GROUP BY
    a.Kind
ORDER BY
    returned DESC;
GO

/*
    All 5 good, all 4 axis, all 3 scaled_big. The search found
    everything semantically real, then padded the result set
    with zeros once it ran out of better options.

    Zeros are filler, not poison.

*/


/*
████████████████████████████████████████████████████████████████████████████████
██                                                                            ██
██                   WHY ZEROS DON'T BREAK THE GRAPH                          ██
██                                                                            ██
████████████████████████████████████████████████████████████████████████████████

    Cosine distance from any vector to [0,0,0,0] = 1, the maximum.
    DiskANN never routes through zeros because there's always a
    closer neighbor in a non-zero direction. They form a disconnected
    cluster at the edge of the graph and just sit there.

    Zero vectors are empty lots in a city.
     * Nobody goes there, they don't block any roads, just waste space

    Duplicates are a hall of mirrors.
     * Cosine identical means the math says they're THE answer.
     * The graph returns 50 copies of the same direction.

    But "doesn't break the graph" is not the same as "fine."
     * A zero vector in your results is meaningless to your application.
     * Something upstream returned nothing useful, or sent empty input,
       or zeroed out the array. The trigger in file 03 catches that.

*/


/*
████████████████████████████████████████████████████████████████████████████████
██                                                                            ██
██                           SUMMARY                                          ██
██                                                                            ██
████████████████████████████████████████████████████████████████████████████████

    1. Zeros don't poison DiskANN recall. They're dead nodes,
       and greedy search routes around them.

    2. Zeros also don't cap retrieval depth. You can ask for 360
       results out of 362 and still get them all. The search
       happily fills the result set with zeros after it runs out
       of better neighbors.

    3. Duplicates are the real silent failure (file 02). The math
       is correct, the metric is high, the result set is useless.

    4. So why validate zeros out at all? They waste space, they
       indicate upstream problems, and they're useless in results
       even when they don't break the graph.

    Next: How do we build the validation trigger?

*/


/*
████████████████████████████████████████████████████████████████████████████████
██                                                                            ██
██              TAKE-HOME: RECALL AT VARYING K (don't run live)               ██
██                                                                            ██
████████████████████████████████████████████████████████████████████████████████

    Skipped on stage for time. Here for the slide deck and for
    anyone who wants to verify the "recall stays 100% all the way
    to k = 360" claim themselves.

    File 02 stays at 100% recall by metric while serving useless
    duplicates. What does 02b's curve look like?

    Same slice-by-rank pattern as file 02: capture truth and ANN
    top-360 once each, then GENERATE_SERIES + JOIN for set-based
    recall at each k.

*/

DECLARE
    @q vector(4, float32) =
        CONVERT(vector(4, float32), N'[0.5, 0.5, 0.5, 0.5]');

DROP TABLE IF EXISTS
    #truth_raw,
    #ann_raw,
    #truth_full,
    #ann_full;

SELECT TOP (360)
    f.Id,
    truth_distance = c.v_distance
INTO #truth_raw
FROM dbo.VectorEmbeddings AS f
CROSS APPLY
(
    VALUES
        (VECTOR_DISTANCE('cosine', @q, f.Embedding))
) AS c (v_distance)
ORDER BY
    c.v_distance,
    f.Id;

SELECT TOP (360) WITH APPROXIMATE
    ve.Id,
    ann_distance = vs.distance
INTO #ann_raw
FROM VECTOR_SEARCH
(
    TABLE = dbo.VectorEmbeddings AS ve,
    COLUMN = Embedding,
    SIMILAR_TO = @q,
    METRIC = 'cosine'
) AS vs
  WITH (FORCE_ANN_ONLY)
ORDER BY
    vs.distance;

SELECT
    tf.Id,
    truth_rank =
        ROW_NUMBER() OVER
        (
            ORDER BY
                tf.truth_distance,
                tf.Id
        )
INTO #truth_full
FROM #truth_raw AS tf;

SELECT
    ar.Id,
    ann_rank =
        ROW_NUMBER() OVER
        (
            ORDER BY
                ar.ann_distance,
                ar.Id
        )
INTO #ann_full
FROM #ann_raw AS ar;

SELECT
    kv.k,
    matched =
        (
            SELECT
                COUNT_BIG(*)
            FROM #truth_full AS t
            JOIN #ann_full AS a
              ON a.Id = t.Id
            WHERE t.truth_rank <= kv.k
            AND   a.ann_rank   <= kv.k
        ),
    recall_pct =
        CONVERT
        (
            decimal(5, 2),
            100.0 *
            (
                SELECT
                    COUNT_BIG(*)
                FROM #truth_full AS t
                JOIN #ann_full AS a
                  ON a.Id = t.Id
                WHERE t.truth_rank <= kv.k
                AND   a.ann_rank   <= kv.k
            ) / CONVERT(decimal(5, 2), kv.k)
        )
FROM
(
    SELECT
        k = gs.value
    FROM GENERATE_SERIES(1, 360) AS gs
    WHERE gs.value IN (5, 10, 25, 50, 100, 150, 200, 250, 300, 360)
) AS kv
ORDER BY
    kv.k;
GO

/*
    Recall is 100% at every k all the way to k = 360 (the whole
    dataset). The graph reaches every real vector and dips into
    the zero cluster afterwards to fill whatever k you ask for.

    Same recall metric as file 02, also 100% across the board.
    The difference between the two files isn't in the metric,
    it's in what's IN the result set:
     * 02:  100% recall, kind breakdown is all 'dup'
     * 02b: 100% recall, kind breakdown has every real vector
            up front, zeros padding the end

*/
