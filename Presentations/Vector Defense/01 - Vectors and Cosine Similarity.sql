USE VectorDefense;
SET NOCOUNT ON;
GO


/*
    ██╗   ██╗███████╗ ██████╗████████╗ ██████╗ ██████╗
    ██║   ██║██╔════╝██╔════╝╚══██╔══╝██╔═══██╗██╔══██╗
    ██║   ██║█████╗  ██║        ██║   ██║   ██║██████╔╝
    ╚██╗ ██╔╝██╔══╝  ██║        ██║   ██║   ██║██╔══██╗
     ╚████╔╝ ███████╗╚██████╗   ██║   ╚██████╔╝██║  ██║
      ╚═══╝  ╚══════╝ ╚═════╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝

    ██████╗ ███████╗███████╗███████╗███╗   ██╗███████╗███████╗
    ██╔══██╗██╔════╝██╔════╝██╔════╝████╗  ██║██╔════╝██╔════╝
    ██║  ██║█████╗  █████╗  █████╗  ██╔██╗ ██║███████╗█████╗
    ██║  ██║██╔══╝  ██╔══╝  ██╔══╝  ██║╚██╗██║╚════██║██╔══╝
    ██████╔╝███████╗██║     ███████╗██║ ╚████║███████║███████╗
    ╚═════╝ ╚══════╝╚═╝     ╚══════╝╚═╝  ╚═══╝╚══════╝╚══════╝

    I'm Erik!
    (Consultare Maximus - Rationabile Pretium)

    W: https://erikdarling.com
    E: mailto:erik@erikdarling.com
    T: https://twitter.com/erikdarlingdata
    T: https://www.tiktok.com/@darling.data
    L: https://www.linkedin.com/company/darling-data/
    Y: https://www.youtube.com/@ErikDarlingData

    Demos:
     *

*/


/*
████████████████████████████████████████████████████████████████████████████████
██                                                                            ██
██                         WHY ARE WE HERE?                                   ██
██                                                                            ██
████████████████████████████████████████████████████████████████████████████████

    Most vector databases assume clean inputs, but they don't validate them.

    SQL Server 2025 gives you DiskANN indexes, but any valid vector can be
    indexed. Valid only means (for SQL Server) that the number of dimensions
    in the vector match the column specification in the table: vector(N).

    If duplicate data gets in, it does something worse than
    return wrong results: it returns useless correct results.

    Cosine-identical duplicates dominate the top of every result set,
    while the recall metric reads green. The math is fine, but the
    output is fifty photocopies of one direction.

    Where do duplicates come from? Garbage in...

    A nightly import job crashed and retried, now half your articles
    got entered twice, maybe a bulk CSV had duplicate rows nobody noticed.

    Support tickets all share the same footer text. Product
    descriptions reuse the same feature lists. Boring infrastructure
    stuff that happens every Tuesday at 3 in the morning.

    It gets worse if you're working from a data lake that's really
    just a data swamp. Five/ten years of teams dumping files
    in, crawler A pulling the same PDFs crawler B already pulled,
    report.pdf next to report_v2.pdf next to report_v2_FINAL.pdf,
    vendor feeds duplicating each other, snapshot tables piled next
    to live tables. Whatever's been accumulating in there is about
    to become your DiskANN index.

    Most of those duplicates aren't byte-for-byte identical.
    One has a different copyright year in the footer. Another
    has slightly different line endings. A simple content check
    (hash the bytes, see if any two hashes match) thinks they're
    all distinct. The embedding model produces near-identical
    vectors for them anyway, and cosine reads them as distance
    zero. Simple defenses miss those rows. The index doesn't.

    The embedding model (the thing that turns text into vectors)
    isn't producing the duplicates. Same text in, same vector out,
    every time. It reflects whatever's already in the source
    data. The fix has to live HERE, in the database, before the
    data is stored or right as it comes in. The embedding step
    is just a mirror.

    Today we're going to see how that happens, and how to stop it with
    T-SQL. After all, we are SQL Server people still, at least for now.

    But first we need a shared vocabulary.

    What are vectors? What do the distance numbers mean?

*/


/*
████████████████████████████████████████████████████████████████████████████████
██                                                                            ██
██                         WHAT ARE VECTORS?                                  ██
██                                                                            ██
████████████████████████████████████████████████████████████████████████████████

    A vector is a list of numbers.

    Embedding models turn text into vectors with magic GPUs.
     * Similar text > similar vectors.

    SQL Server 2025 has a native vector type, and three ways
    to measure distances between them. More on that below.

*/

DECLARE
    @short vector(4, float32) =
        CONVERT(vector(4, float32), N'[1, 2, 3, 4]'),
    @long  vector(4, float32) =
        CONVERT(vector(4, float32), N'[100, 200, 300, 400]');

SELECT
    left_vector  = N'[1, 2, 3, 4]',
    right_vector = N'[100, 200, 300, 400]',
    cosine    = VECTOR_DISTANCE('cosine',    @short, @long),
    dot       = VECTOR_DISTANCE('dot',       @short, @long),
    euclidean = VECTOR_DISTANCE('euclidean', @short, @long);


/*
    Three distance metrics:

    COSINE:    Based on direction only
    DOT:       Based on magnitude AND direction
    EUCLIDEAN: More like GPS coordinates (we won't use it today).

    Magnitude = length of the vector.
     * Think of it as "how big" the numbers are overall.

    Direction = which way it points in Vector Space.
     * [1, 2, 3, 4]
     * [100, 200, 300, 400]

    Both point the same direction...
    But one is 100× longer than the other.
     * Cosine ignores that difference.
     * Dot product doesn't.

    SQL Server returns DISTANCE, not similarity.
     * Everyone calls it "similarity search" anyway.

    For cosine:
     * 0 = identical
     * 1 = perpendicular (unrelated)
     * 2 = opposite

    Lower is better, 0 indicates ~exact match

    For dot: more negative = more similar.
     * It's a different scale.
     * SQL Server flips these negative.

*/


/*
████████████████████████████████████████████████████████████████████████████████
██                                                                            ██
██                      WHY COSINE FOR SEMANTIC SEARCH?                       ██
██                                                                            ██
████████████████████████████████████████████████████████████████████████████████

    Embedding models encode meaning as direction.

    Magnitude is noise, an artifact of tokenization,
    model internals, batch normalization, etc.

    https://en.wikipedia.org/wiki/Batch_normalization
    https://en.wikipedia.org/wiki/Text_segmentation#Word_segmentation

    Cosine asks:
     * "Are these pointing the same way?"

    Dot asks:
     * "Are these pointing the same way AND how long are they?"
       (Or how far are they pointing; size matters, in other words)

    For semantic search, we really only care about direction.
     * Similarity without the magnitude differentiation

    Three vectors, same direction, three different magnitudes.
    Watch cosine call them all distance zero while dot doesn't.

    Same direction with different magnitudes is rare from a normalized
    API (OpenAI, Cohere, voyage, Anthropic all L2-normalize vectors).

    Objective = (1 / 2n) * Σ(yᵢ - ŷᵢ)² + λ * Σ(wⱼ²)

    L2 normalization takes a vector and shrinks it so its length equals 1,
    while keeping it pointing the same direction.

    Once everything is length 1, comparing two vectors with dot product gives
    you cosine similarity for free, because the magnitudes cancel out.

    Same direction with the SAME magnitude (duplicate text producing
    duplicate embeddings) is extremely common, and triggers the exact
    same cosine blindness this demo shows.

    We'll see what that does to the index in the next file.

*/

DECLARE
    @doc_short vector(4, float32) =
        CONVERT(VECTOR(4, float32), N'[1, 1, 1, 1]'),
    @doc_medium VECTOR(4, float32) =
        CONVERT(VECTOR(4, float32), N'[50, 50, 50, 50]'),
    @doc_long VECTOR(4, float32) =
        CONVERT(VECTOR(4, float32), N'[100, 100, 100, 100]');

SELECT
    left_vector  = N'[1, 1, 1, 1]',
    right_vector = N'[50, 50, 50, 50]',
    cosine = VECTOR_DISTANCE('cosine', @doc_short, @doc_medium),
    dot    = VECTOR_DISTANCE('dot',    @doc_short, @doc_medium)
UNION ALL
SELECT
    N'[1, 1, 1, 1]',
    N'[100, 100, 100, 100]',
    VECTOR_DISTANCE('cosine', @doc_short, @doc_long),
    VECTOR_DISTANCE('dot',    @doc_short, @doc_long)
UNION ALL
SELECT
    N'[50, 50, 50, 50]',
    N'[100, 100, 100, 100]',
    VECTOR_DISTANCE('cosine', @doc_medium, @doc_long),
    VECTOR_DISTANCE('dot',    @doc_medium, @doc_long);
GO

/*
    Results:
     Cosine:
      * All zeros. Same direction = identical semantically.
     Dot:
      * Very different numbers. Magnitude differences.

    Now add documents that are semantically different.
     @sql_perf and @sql_perf_big:
      * Same topic, different magnitudes
     @amiga_repair:
      * Unrelated topic, perpendicular to sql_perf

    Two rows below: cosine 0 (identical direction) and cosine 1
    (unrelated). That's the practical range you'll see in real
    text embeddings.

*/

DECLARE
    @sql_perf vector(4, float32) =
        CONVERT(vector(4, float32), N'[1, 2, 3, 4]'),
    @sql_perf_big vector(4, float32) =
        CONVERT(vector(4, float32), N'[100, 200, 300, 400]'),
    @amiga_repair vector(4, float32) =
        CONVERT(vector(4, float32), N'[4, -3, 2, -1]');

SELECT
    comparison = N'same topic, different magnitude',
    left_vector  = N'[1, 2, 3, 4]',
    right_vector = N'[100, 200, 300, 400]',
    cosine = VECTOR_DISTANCE('cosine', @sql_perf, @sql_perf_big),
    dot    = VECTOR_DISTANCE('dot',    @sql_perf, @sql_perf_big)
UNION ALL
SELECT
    N'unrelated topic (perpendicular)',
    N'[1, 2, 3, 4]',
    N'[4, -3, 2, -1]',
    VECTOR_DISTANCE('cosine', @sql_perf, @amiga_repair),
    VECTOR_DISTANCE('dot',    @sql_perf, @amiga_repair);
GO

/*
    Cosine identifies what we care about:
      * Same direction = 0 (identical meaning)
      * Perpendicular  = 1 (unrelated topics)

    The metric does go up to 2 (opposite direction) but real text
    embeddings cluster in a narrow cone. You'll see 0 to about
    1.8 in production, almost never 2.

    Look back at the short/medium/long demo above. Three vectors
    that all point the SAME direction (semantically identical)
    scored -200, -400, and -20000 with dot product. Same meaning,
    three very different "distances." Not what we want.

    That's dot's problem area for search: identical meaning
    gets scored differently because magnitudes differ. Sort
    by that and you'll rank the longest document first every
    time, regardless of relevance. Again, size matters for dot.

*/


/*
████████████████████████████████████████████████████████████████████████████████
██                                                                            ██
██                      READING THE NUMBERS                                   ██
██                                                                            ██
████████████████████████████████████████████████████████████████████████████████

    SQL Server displays tiny numbers in scientific notation.

    This will trip you up if you're not expecting it.

    -4.00000044464832E-06 means -0.000004

    The E-06 means "move the decimal 6 places left."

    The E+20 means "move the decimal 20 places right."

    Converting to a decimal is a good way to not feel dumb.

*/

SELECT
    scientific =
        VECTOR_DISTANCE
        (
            'dot',
            CONVERT(vector(4, float32), N'[0.001, 0.001, 0.001, 0.001]'),
            CONVERT(vector(4, float32), N'[0.001, 0.001, 0.001, 0.001]')
        ),
    readable =
        CONVERT
        (
            decimal(20,19),
            VECTOR_DISTANCE
            (
                'dot',
                 CONVERT(vector(4, float32), N'[0.001, 0.001, 0.001, 0.001]'),
                 CONVERT(vector(4, float32), N'[0.001, 0.001, 0.001, 0.001]')
            )
        );


/*
████████████████████████████████████████████████████████████████████████████████
██                                                                            ██
██                     SELF-DOT AS A HEALTH CHECK                             ██
██                                                                            ██
████████████████████████████████████████████████████████████████████████████████

    We just saw that dot product is wrong for similarity search.
     * It penalizes magnitude, gets rankings backwards, etc.

    But cosine has a problem: it normalizes magnitude away.
     * That's great for search, and terrible for quality control.

    A near-zero vector and a healthy vector can point the same
    direction. Cosine says "identical!" and moves on. Oopsie.

    It can't see that one of them is basically empty.

    Dot product *can* see it: Magnitude sensitivity is a bug
    for search, but it's a feature for quality control (that's you).

    Each metric has a job:
     * Cosine for searching (direction matters, magnitude doesn't)
     * Dot for detecting garbage (magnitude is the whole point)

    We compute energy = VECTOR_DISTANCE('dot', vector1, vector1)

    That's the self-dot-product, it returns the negative
    sum of each component squared. A magnitude check.

    We don't care if energy is -1 or -4 or -400.

    Any real number means the vector has something in it.

    We care if it's close to zero.
     * Near zero = the vector is basically empty = degenerate
     * Big negative number = the vector has stuff in it = healthy

    Where do zero and near-zero vectors come from? Same answer
    as duplicates: nobody puts them there on purpose.

    Most common: empty input. Someone called the embedding API
    with an empty string, a whitespace-only string, or a string
    that got fully stripped during pre-processing. The model
    produces a zero (or near-zero) vector instead of throwing.

    Or: the embedding call failed mid-pipeline and a fallback
    path stored a zero vector as a placeholder while the rest
    of the row went in fine. The row looks valid. The embedding
    is meaningless.

    Or: someone initialized a vector array to all zeros and a
    code path skipped the actual embedding call but still
    inserted the row. Surprisingly common.

    Or: the input was emoji-only, foreign-language, or all
    out-of-vocabulary tokens for a model trained on a different
    corpus. The model has no representation for the input and
    falls back to something near the origin.

    All of these pass the dimension check and the type check.
    Cosine search would happily try to process them, right up
    until the math divides by zero. That's why we use the
    energy check at ingest.

    Five test vectors, from healthy to degenerate:

    @normalized:
     * magnitude = 1. This is what embedding APIs typically return.
    @unnormalized:
     * magnitude = 2. Same direction, bigger numbers. Cosine doesn't care.
    @big_healthy:
     * magnitude = 200. Way bigger numbers. Still healthy. Energy is -40000.
    @zero:
     * magnitude = 0. No direction at all. Cosine divides by zero.
    @near_zero:
     * magnitude ≈ 0. Technically has direction, but it's noise.

*/

DECLARE
    @normalized vector(4, float32) =
        CONVERT(vector(4, float32), N'[0.5, 0.5, 0.5, 0.5]'),
    @unnormalized vector(4, float32) =
        CONVERT(vector(4, float32), N'[1, 1, 1, 1]'),
    @big_healthy vector(4, float32) =
        CONVERT(vector(4, float32), N'[100, 100, 100, 100]'),
    @zero vector(4, float32) =
        CONVERT(vector(4, float32), N'[0, 0, 0, 0]'),
    @near_zero vector(4, float32) =
        CONVERT(vector(4, float32), N'[0.001, 0.001, 0.001, 0.001]');

SELECT
    vector_text =
        N'[0.5, 0.5, 0.5, 0.5]',
    energy =
        CONVERT
        (
            decimal(25, 19),
            VECTOR_DISTANCE('dot', @normalized, @normalized)
        ),
    verdict = N'healthy'
UNION ALL
SELECT
    N'[1, 1, 1, 1]',
        CONVERT
        (
            decimal(25, 19),
            VECTOR_DISTANCE('dot', @unnormalized, @unnormalized)
        ),
    N'healthy'
UNION ALL
SELECT
    N'[100, 100, 100, 100]',
    CONVERT
    (
        decimal(25, 19),
        VECTOR_DISTANCE('dot', @big_healthy, @big_healthy)
    ),
    N'healthy'
UNION ALL
SELECT
    N'[0, 0, 0, 0]',
    CONVERT
    (
        decimal(25, 19),
        VECTOR_DISTANCE('dot', @zero, @zero)
    ),
    N'degenerate'
UNION ALL
SELECT
    N'[0.001, 0.001, 0.001, 0.001]',
    CONVERT
    (
        decimal(25, 19),
        VECTOR_DISTANCE('dot', @near_zero, @near_zero)
    ),
    N'degenerate';
GO

/*
    Healthy normalized vector:
      Energy ≈ -1
    Degenerate vector:
      Energy ≈ 0 or way off from -1

    This is the foundation of our validation strategy.

*/


/*
████████████████████████████████████████████████████████████████████████████████
██                                                                            ██
██                              SUMMARY                                       ██
██                                                                            ██
████████████████████████████████████████████████████████████████████████████████

    1. Embedding models encode meaning as DIRECTION
       Magnitude is noise.

    2. Use COSINE for semantic search
       It normalizes magnitude out of the equation.

    3. Self-dot-product is your health check
       energy = VECTOR_DISTANCE('dot', v, v)
       Healthy: some negative number (-1 for normalized, bigger is fine)
       Degenerate: energy ≈ 0

    4. Duplicate vectors are dangerous
       Cosine-identical copies flood the graph.
       They don't just return wrong results,
       they make good results unreachable.

       That's what we'll see next.

*/
