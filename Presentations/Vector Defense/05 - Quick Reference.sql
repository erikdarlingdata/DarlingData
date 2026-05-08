/*
████████████████████████████████████████████████████████████████████████████████
██                                                                            ██
██                              Quick Reference                               ██
██                                                                            ██
████████████████████████████████████████████████████████████████████████████████

    The whole talk in one page.


    THE PROBLEM
    -----------
    SQL Server 2025 gives you DiskANN for vector search.
    DiskANN trusts your data completely. No validation.

    Duplicate vectors flood the graph with cosine-identical copies.
    The math says they ARE the nearest neighbors, so the index
    returns 50 of them and stops. The recall metric looks fine.
    The result set is 50 photocopies of the same direction.

    Zero vectors are garbage but mostly harmless to the graph.
    They're dead nodes the search routes around. They end up
    at the back of the result list, behind the real vectors.


    COSINE DISTANCE (for search)
    ----------------------------
    Measures direction only. Ignores magnitude.
    * 0   = identical direction (perfect match)
    * 1   = perpendicular (unrelated)
    * 2   = opposite direction (as different as possible)

    Blind spot: cosine says [5,5,5,5] and [50,50,50,50] are identical.
    It can't see duplicates or magnitude problems.


    SELF-DOT-PRODUCT (for detection)
    --------------------------------
    energy = VECTOR_DISTANCE('dot', v, v)

    Returns the negative sum of squared components.
    * Healthy vector: some negative number (-1, -4, -400)
    * Zero/near-zero vector: energy near 0

    Cosine for searching. Dot for detecting garbage.


    WHY DUPLICATES POISON YOUR RESULTS
    ----------------------------------
    DiskANN is a graph index. Search follows edges greedily
    toward the closest neighbor.

    Cosine-identical vectors (same direction, any magnitude)
    are tied at distance 0 from any cosine-aligned query.
    The index returns 50 of them and stops. Mathematically
    correct. Operationally useless.

    Distinct semantic neighbors at slightly non-zero distance
    never appear in the result set: they're behind 150+ tied
    distance-0 candidates.

    Recall looks fine. Result diversity is zero.


    MEASURING RECALL (and why it's not enough)
    -------------------------------------------
    recall = (matched / k) x 100

    Truth set:  brute-force ORDER BY VECTOR_DISTANCE (slow, correct)
    ANN result: VECTOR_SEARCH with DiskANN index (fast, approximate)

    Compare the two. If they don't match by Id, the index might
    be lying, or both lists might be picking different distance-0
    ties. Check recall by content too:

      * Group the result set by source / content / kind.
      * If 50 results came from one cluster, the metric lied to you.
      * Run this periodically on production data.


    VALIDATION: check three things
    ------------------------------
    Do this before CONVERT to vector type (while it's still JSON).

    1. Dimension count matches your model
       - Mismatch = model switch or pipeline bug

    2. All components parse to float
       - TRY_CAST catches nulls, strings, garbage

    3. Magnitude is not near-zero
       - SUM(component * component) > 1e-9
       - Zero magnitude = degenerate = quarantine it

    Route failures to a quarantine table with a rejection reason.
    Don't just reject. Give your pipeline team something to debug.


    STALENESS: hash the source content
    -----------------------------------
    At embed time: compute HASHBYTES('SHA2_256', content), store it.
    Later: compare document's current hash to stored hash.
    Different = stale. The document changed but the embedding didn't.
    Re-embed it.


    DUPLICATES: hash detects these too
    -----------------------------------
    Same content_hash = same content = duplicate embedding.
    GROUP BY content_hash, HAVING COUNT_BIG(*) > 1.

    This is how you keep the file 02 result-set poisoning from
    happening: catch duplicates before they're embedded.


    DUPLICATE PREVENTION: defense in depth
    --------------------------------------
    Database: unique index on content_hash with IGNORE_DUP_KEY.
    Application: hash and check before calling embedding API.
    Pipeline: dedup staging tables, track processing state.
    Source: one embedding per unique content, not per document.
    Audit:  periodic near-duplicate scan on the live table.
            Vector-index self-search or quantized-hash dedup
            catches paraphrase / formatting near-duplicates
            that byte-level hashing misses. (See file 04.)

    Treat the database as the last line, not the first.

*/
