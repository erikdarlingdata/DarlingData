USE VectorDefense;
SET NOCOUNT ON;
GO


/*
████████████████████████████████████████████████████████████████████████████████
██                                                                            ██
██                    HOW DISKANN WORKS                                       ██
██                                                                            ██
████████████████████████████████████████████████████████████████████████████████

    B-Tree Index:
     * Navigate by comparison: "Is my value < or > this node?"

                      [M]
                     /   \
                  [E]     [R]
                 /   \   /   \
            [A-D] [F-L] [N-Q] [S-Z]

    Looking for "K"?
     * M > go left > E > go right > found in [F-L]

    The path is deterministic. Same query = same path every time.
     * There's no bad data that can make it go the wrong way.

    GRAPH INDEX (DiskANN):
     * Navigate by proximity: "Which neighbor is closest to my target?"

               A -------- B -------- C
               |          |          |
               |          |          |
               |          |          |
               D         [E]         F
                          |
                          |
                          |
               G -------- H -------- I

    Looking for something near I?
     * Start at E
     * E's neighbors: B, D, F, H
     * H is closer to I than the others, follow H
     * H's neighbors: E, G, I. Done.

    The path is greedy.
     * "Always move toward the closest neighbor."
     * If E has broken distances, it might send you to F instead of H.
     * F has no edge to I, so now you're stuck in the wrong neighborhood.

    Real DiskANN nodes have ~32-64 edges each, including long-range
    "shortcut" edges to distant points. Those long-range edges are
    what keep the graph from getting trapped locally.

    A B-tree is a deterministic hierarchy where you go left or right.

    Graph is a web where every node can affect routing to every other node.

    It's like asking strangers for directions:
     At every corner, you ask "which way to the train station?" and follow
     whoever points in whatever direction, no matter how dubious and shady.

     This works great, if everyone (or anyone) knows where it is.

     But if everyone you ask points to the same useless place (because
     they're all copies of the same person giving the same wrong answer)
     you end up there, no matter how many directions you ask.
      * You never get an error.
      * Everyone is very helpful (and very confident, probably good-looking).
      * Your top results are 50 photocopies of one wrong answer.

*/


/*
████████████████████████████████████████████████████████████████████████████████
██                                                                            ██
██                         SET UP THE EXPERIMENT                              ██
██                                                                            ██
████████████████████████████████████████████████████████████████████████████████

    Cosine normalizes magnitude away.
    [5, 5, 5, 5] and [50, 50, 50, 50] are cosine distance = 0.

    What happens when we flood the graph with cosine-identical copies?

    Setup:
    * 5 good vectors (healthy, varying directions near the query)
    * 3 scaled_big vectors (same direction as query, large magnitude)
    * 4 axis vectors (moderate distance from query)
    * Then 50x duplicates of scaled_big and axis = 350 copies

    Total: 362 vectors. Only 12 unique embedding values
    (and only 9 unique directions, since great_match shares
    its direction with the 3 scaled_big vectors).
    The graph is 97% duplicates.

    The 100-row floor matters: the latest DiskANN index version
    requires at least 100 rows with non-NULL vectors before it
    will build. Our setup clears that easily.

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
    /* Perfect match for our query [0.5, 0.5, 0.5, 0.5] */
    (N'great match', N'good', CONVERT(vector(4, float32), N'[0.5, 0.5, 0.5, 0.5]')),

    /* Close matches (should be top results) */
    (N'near 01', N'good', CONVERT(vector(4, float32), N'[0.52, 0.50, 0.49, 0.49]')),
    (N'near 02', N'good', CONVERT(vector(4, float32), N'[0.48, 0.51, 0.50, 0.51]')),
    (N'near 03', N'good', CONVERT(vector(4, float32), N'[0.51, 0.49, 0.51, 0.49]')),
    (N'near 04', N'good', CONVERT(vector(4, float32), N'[0.49, 0.52, 0.49, 0.50]')),

    /* Same DIRECTION as query, but very large magnitude, cosine distance = 0 */
    (N'big 01', N'scaled_big', CONVERT(vector(4, float32), N'[5,  5,  5,  5]')),
    (N'big 02', N'scaled_big', CONVERT(vector(4, float32), N'[10, 10, 10, 10]')),
    (N'big 03', N'scaled_big', CONVERT(vector(4, float32), N'[50, 50, 50, 50]')),

    /* Axis vectors: moderate cosine distance (0.5) from query */
    (N'axis x', N'axis', CONVERT(vector(4, float32), N'[1, 0, 0, 0]')),
    (N'axis y', N'axis', CONVERT(vector(4, float32), N'[0, 1, 0, 0]')),
    (N'axis z', N'axis', CONVERT(vector(4, float32), N'[0, 0, 1, 0]')),
    (N'axis w', N'axis', CONVERT(vector(4, float32), N'[0, 0, 0, 1]'));
GO


/*
    Now flood the graph with duplicates.

    50 copies of each scaled_big and axis vector.
    These are all cosine-identical to their source.

    Production sources for these are everywhere: ETL re-runs,
    retry logic, chunking overlap, boilerplate content. We'll
    enumerate them in file 04 where it matters for prevention.

*/

INSERT INTO
    dbo.VectorEmbeddings
(
    Label,
    Kind,
    Embedding
)
SELECT
    Label = CONCAT(f.Label, N' (dup ', g.value, N')'),
    Kind = N'dup',
    f.Embedding
FROM dbo.VectorEmbeddings AS f
CROSS JOIN GENERATE_SERIES(1, 50) AS g
WHERE f.Kind IN (N'scaled_big', N'axis');
GO


/*
    What did we end up with?
     * 362 vectors, 12 unique embedding values, 9 unique directions.
     * 97% of the graph is duplicates of just 7 source vectors.

    Every single vector is individually valid
     * No zeros. No near-zeros. No NaNs. No garbage.
     * Just a lot of duplicates

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
██                    HOW MANY UNIQUE DIRECTIONS?                             ██
██                                                                            ██
████████████████████████████████████████████████████████████████████████████████

    But how many cosine-identical groups do we have?

*/

SELECT
    ve1.Label,
    ve1.Kind,
    cosine_identical_count =
        (
            SELECT
                COUNT_BIG(*)
            FROM dbo.VectorEmbeddings AS ve2
            WHERE VECTOR_DISTANCE
                  (
                      'cosine',
                      ve1.Embedding,
                      ve2.Embedding
                  ) < 0.0001
        )
FROM dbo.VectorEmbeddings AS ve1
WHERE ve1.Kind NOT IN (N'dup')
ORDER BY
    cosine_identical_count DESC;
GO

/*
    Each scaled_big vector has 154 cosine-identical copies.
    Each axis vector has 51 cosine-identical copies.
    The "near" vectors are unique, 1 each.

    "great match" also shows 154. It's [0.5, 0.5, 0.5, 0.5],
    the same direction as the scaled_big vectors [5,5,5,5],
    [10,10,10,10], [50,50,50,50]. Cosine can't tell them
    apart because it ignores magnitude.
    That's 1 + 3 + (50 * 3) = 154.

    362 vectors, 9 unique directions.
     * The energy check would pass all of them.
     * The dimension check would pass all of them.
     * The JSON validation would pass all of them.

    This is the problem validation can't catch.
    Content hashing (file 04) can.

*/


/*
████████████████████████████████████████████████████████████████████████████████
██                                                                            ██
██                     THE DUPLICATE CLUSTERING PROBLEM                       ██
██                                                                            ██
████████████████████████████████████████████████████████████████████████████████

    During Index Construction:

    DiskANN assigns edges between vectors based on cosine distance.
    Vectors that are cosine-identical (distance = 0) get heavily
    cross-linked, they're "the same place" in the graph.

    When 97% of your vectors are duplicates of 7 directions:

    The duplicate vectors form dense clusters
     * All copies of [5,5,5,5] connect to each other
     * All copies of [1,0,0,0] connect to each other
     * They consume most of the available edge slots

    Good vectors get starved for edges
     * The "near" vectors at [0.52, 0.50, 0.49, 0.49] etc. are
       almost-but-not-quite the same direction as [0.5, 0.5, 0.5, 0.5]
     * Cosine distance ~0.0003: tiny but non-zero
     * They lose neighbor slots to the 150+ copies that ARE distance-0

    During Search:
     * The search asks for top-50 nearest neighbors.

    There are 154 cosine-identical-to-the-query duplicates in the data.
    The search returns 50 of them. Recall looks fine.

    But the actual result set is 50 photocopies of one direction.
    The 4 distinct "near" vectors that you'd want to see?
    They're sitting at rank 155+, never appearing in top-50 because
    154 distance-0 candidates pre-empt them.

    Healthy Graph:

         A ---- B ---- C
         |      |      |
         D ---- E ---- F
         |      |      |
         G ---- H ---- I

    Query near I?
     * Path: A > B > C > F > I
     * Returns A, B, C, F, I. The actual top 5 distinct neighbors.

    Duplicate-flooded Graph:

         near01 ... near04   (good, but at distance 0.0003)
              \          /
               \        /
           [E E E E E E E]   <- 154 cosine-identical copies. ALL
           [E E E E E E E]      at distance 0 from query. Search
           [E E E E E E E]      returns 50 of these and stops.
              /        \
             /          \
         axis01 ... axis04   (also at distance 0.5, never reached)

    Query for top-50?
     * Returns: 50 distance-0 duplicates, ranked correctly by distance,
       0 of the distinct good vectors.
     * Recall is high (every returned vector IS a true nearest neighbor).
     * Operationally: 50 copies of one direction. Useless.

*/


/*
████████████████████████████████████████████████████████████████████████████████
██                                                                            ██
██                         BUILD DISKANN INDEX                                ██
██                                                                            ██
████████████████████████████████████████████████████████████████████████████████

    Now let's build the index on our duplicate-flooded data
    and see what happens.

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
██                    EXACT VS APPROXIMATE COMPARISON                         ██
██                                                                            ██
████████████████████████████████████████████████████████████████████████████████

    Truth Set (VECTOR_DISTANCE):
     * Does not use vector index
     * Compares every vector
     * Slower but correcter

    ANN Result (VECTOR_SEARCH):
     * Uses the vector index
     * Looks for nearest neighbors
     * Fast, but...

    K is just "how many results do we want back". Top-K is the
    standard search-vocab term. We're going to ask for K = 50
    and see what each method returns.

    Note on syntax: latest-version vector indexes use
    SELECT TOP (N) WITH APPROXIMATE plus ORDER BY distance.
    The older TOP_N parameter inside VECTOR_SEARCH is deprecated
    and errors out (Msg 42274). FORCE_ANN_ONLY tells the optimizer
    to use the DiskANN graph even when it could brute-force at
    this size.

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
    truth_distance =
        VECTOR_DISTANCE('cosine', @q, f.Embedding)
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
) AS vs 
  WITH (FORCE_ANN_ONLY)
ORDER BY
    vs.distance;
GO


/*
    Side by side:
     * What #truth says vs what #ann says

*/

SELECT
    truth_rank =
        ROW_NUMBER() OVER
        (
            ORDER BY
                t.truth_distance,
                t.Id
        ),
    t.Id,
    t.Label,
    t.Kind,
    t.truth_distance,
    ann_distance = a.ann_distance,
    in_ann_result =
        CASE
            WHEN a.Id IS NOT NULL
            THEN 'YES'
            ELSE '** MISSED **'
        END,
    running_recall_pct =
        CONVERT
        (
            decimal(5, 2),
            100.0 *
            SUM
            (
                CASE
                    WHEN a.Id IS NOT NULL
                    THEN 1
                    ELSE 0
                END
            ) OVER
            (
                ORDER BY
                    t.truth_distance,
                    t.Id
                ROWS UNBOUNDED PRECEDING
            ) /
            ROW_NUMBER() OVER
            (
                ORDER BY
                    t.truth_distance,
                    t.Id
            )
        )
FROM #truth AS t
LEFT JOIN #ann AS a
  ON a.Id = t.Id
ORDER BY
    t.truth_distance ASC,
    t.Id ASC;
GO

/*
    Quick read of the results: every row has truth_distance = 0,
    ANN returned 50 distance-0 rows too, "** MISSED **" entries
    are just tie-break differences between equally-valid distance-0
    candidates.

    What matters more is what's NOT in either list. The 4 distinct
    "near" vectors (the rows that contain different content) never
    made the top-50. Where do they actually rank?

*/

DECLARE
    @q vector(4, float32) =
        CONVERT(vector(4, float32), N'[0.5, 0.5, 0.5, 0.5]');

WITH
    all_ranked AS
(
    SELECT
        f.Id,
        f.Label,
        truth_distance = c.v_distance,
        truth_rank =
            ROW_NUMBER() OVER
            (
                ORDER BY
                    c.v_distance,
                    f.Id
            )
    FROM dbo.VectorEmbeddings AS f
    CROSS APPLY
    (
        VALUES
            (VECTOR_DISTANCE('cosine', @q, f.Embedding))
    ) AS c (v_distance)
)
SELECT
    ar.truth_rank,
    ar.Id,
    ar.Label,
    ar.truth_distance,
    made_top_50 =
        CASE
            WHEN ar.truth_rank <= 50
            THEN 'YES'
            ELSE 'NO'
        END
FROM all_ranked AS ar
WHERE ar.Label LIKE N'near%'
ORDER BY
    ar.truth_rank;
GO

/*
    Ranks 155 through 158. Top-50 stops at rank 50. There are
    154 distance-0 duplicates ahead of them. They never appear
    in either list. The index isn't broken; the math just says
    photocopies come first.

*/


/*
████████████████████████████████████████████████████████████████████████████████
██                                                                            ██
██                         RECALL METRICS                                     ██
██                                                                            ██
████████████████████████████████████████████████████████████████████████████████

    Recall = what percentage of the true top-K did we actually find?
    * Recall = (matched / k) × 100
    * 100% = perfect, we found everything we should have
    * 50% = we're missing half the results

    But for vector search, recall by Id is almost meaningless
    when ties exist. Recall by content is the operational question.

*/

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
    Reading the tea leaves:
      * requested_k = 50, returned_k = 50: we got everything we asked for.
      * recall_pct around 90%: looks fine.
      * closest_missed_distance = 0: every "miss" was a tie at distance 0.
        The graph isn't broken, it just picked different distance-0
        copies than the truth set's deterministic Id-based tiebreak.

    By the standard recall metric, this looks acceptable. That's the
    problem here: the metric reassures you while your result set is
    50 copies of the same vector and zero of the distinct near
    matches.

*/


/*
    What kinds of vectors did ANN actually return?

    THIS is the echo chamber. Not in the graph routing.
    In the result set. The recall metric stays green. Every
    returned row is a real, valid nearest neighbor by cosine.
    But every single one is a duplicate. None of the 5 distinct
    good vectors. None of the axis vectors. 50 copies from
    one cluster.

    The graph fails silently. No errors. No warnings.
    The dashboard says everything is healthy.

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
    Both are zero. The truth set didn't include the near vectors
    either, because by strict cosine ranking 154 distance-0 dups
    come first. So this isn't an ANN bug. It's a data-quality
    problem the metric can't see.

    That's the point: cosine + duplicates means the right answer
    by the math is 50 copies of the same direction. Math is fine.
    Search results are useless.

*/


/*
████████████████████████████████████████████████████████████████████████████████
██                                                                            ██
██                           SUMMARY                                          ██
██                                                                            ██
████████████████████████████████████████████████████████████████████████████████

    1. DiskANN uses greedy routing through a proximity graph
       - The latest version index doesn't have the catastrophic
         "search gives up" failures we used to see.

    2. Duplicate vectors create a different silent failure:
       - The math is correct, but cosine can't tell direction-similar
         from direction-identical.
       - Top-K fills with cosine-distance-0 duplicates.
       - The distinct neighbors you wanted never appear.

    3. The failure mode is silent
       - Recall metric looks acceptable.
       - returned_k matches requested_k.
       - But the returned set is operationally noise.

    4. Every vector passes individual validation
       - No zeros, no NaNs, no malformed data
       - The problem is volume, not validity.

    5. Always have a truth set AND a content sanity check
       - Recall = (matched / k) × 100 still useful, just not sufficient.
       - Also check: how many distinct directions / clusters
         appear in the result set?

    6. The fix: deduplicate AND validate at ingestion
       - Energy check catches zero/near-zero (file 03)
       - Content hashing catches duplicates (file 04)
       - Both are necessary

    But wait, what about zero vectors?
    Are they actually dangerous? Let's find out.

*/


/*
████████████████████████████████████████████████████████████████████████████████
██                                                                            ██
██              TAKE-HOME: RECALL AT VARYING K (don't run live)               ██
██                                                                            ██
████████████████████████████████████████████████████████████████████████████████

    Skipped on stage for time. Here for the slide deck and for
    anyone who wants to verify the "recall stays 100% across all
    k" claim themselves.

    We measured recall at one specific k. Does the picture get
    better or worse as we ask for more (or fewer) results?

    Capture truth and ANN top-360 once each, slice by rank for
    each k. The TOP (N) WITH APPROXIMATE form won't take a
    correlated variable, but slicing pre-ranked results works
    fine and stays set-based.

*/

DECLARE
    @q vector(4, float32) =
        CONVERT(vector(4, float32), N'[0.5, 0.5, 0.5, 0.5]');

DROP TABLE IF EXISTS
    #truth_raw,
    #ann_raw,
    #truth_full,
    #ann_full;

/* Truth: top-360 by exact cosine, with Id tiebreak */
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

/* ANN: top-360 via the index. ORDER BY can only hit distance
   in the WITH APPROXIMATE form, so the Id tiebreak waits. */
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

/* Window functions can't sit inside WITH APPROXIMATE, so the
   rank assignment is its own statement. */
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

/* Set-based recall at each k via GENERATE_SERIES */
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
    WHERE gs.value IN (5, 10, 25, 50, 100, 150, 200, 250)
) AS kv
ORDER BY
    kv.k;
GO

/*
    Recall is 100% at every k. The metric gives an unambiguous
    green light. By the standard recall measure, the system
    is working perfectly.

    Think back to the kind breakdown earlier. Every single result
    is a duplicate. None of the 4 distinct "near" vectors made it
    in. The metric and the result content disagree completely.

    Don't validate vector search by recall alone. Validate by
    content diversity in the result set.

*/
