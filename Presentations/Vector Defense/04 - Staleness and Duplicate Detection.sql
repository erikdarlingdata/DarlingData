USE VectorDefense;
SET NOCOUNT ON;
GO


/*
████████████████████████████████████████████████████████████████████████████████
██                                                                            ██
██               STALENESS AND DUPLICATE DETECTION via content_hash           ██
██                                                                            ██
████████████████████████████████████████████████████████████████████████████████

    File 03 caught bad vectors at ingest. This file catches two
    failure points that show up after ingestion:

    1. Staleness: the source document changed but nobody re-embedded
       it. The vector in the index no longer represents the current
       content. Search returns hits for text that no longer exists.

    2. Duplicates at the source: the same content was inserted as
       multiple documents (ETL re-runs, copy/paste, vendor feed
       overlap). Each one gets its own embedding row, and the
       vectors come out identical. That's the file 02 result-set
       poisoning, born one row at a time.

    Same defense for both: hash the source content.
     * Compare current_hash to stored_hash for staleness.
     * GROUP BY content_hash, HAVING COUNT > 1 for duplicates.
     * One column, two problems, plain T-SQL we've had for twenty years.

*/

DROP TABLE IF EXISTS
    dbo.DocumentEmbeddings,
    dbo.Documents;
GO

/*
    Source documents - the "ground truth" content
     * content_hash is a persisted computed column.
     * SQL Server updates it automatically when content changes.
*/
CREATE TABLE
    dbo.Documents
(
    document_id integer
        IDENTITY
        PRIMARY KEY CLUSTERED,
    title nvarchar(200) NOT NULL,
    content nvarchar(MAX) NOT NULL,
    /*
        modified_at is set manually by callers; in production
        you'd back this with an UPDATE trigger or ~something~
    */
    modified_at datetime2(3) NOT NULL
        DEFAULT SYSUTCDATETIME(),
    content_hash AS
        HASHBYTES
        (
            'SHA2_256',
            content
        ) PERSISTED
);
GO

/*
    Embeddings with source hash for staleness detection
*/
CREATE TABLE
    dbo.DocumentEmbeddings
(
    embedding_id integer
        IDENTITY
        PRIMARY KEY CLUSTERED,
    document_id integer NOT NULL,
    embedding vector(4, float32) NOT NULL,
    source_hash binary(32) NOT NULL,
    /* SHA2_256 of source content at embed time */
    embedded_at datetime2(3) NOT NULL
        DEFAULT SYSUTCDATETIME(),
    CONSTRAINT
        fk_DocumentEmbeddings_Documents
            FOREIGN KEY
                (document_id)
            REFERENCES
                dbo.Documents
                    (document_id),
    INDEX
        DocumentEmbeddings_document_id
            (document_id)
);
GO


/*
████████████████████████████████████████████████████████████████████████████████
██                                                                            ██
██                         EMBEDDING PROCEDURE                                ██
██                                                                            ██
████████████████████████████████████████████████████████████████████████████████

    In production, this would call an embedding API, or the
    AI_GENERATE_EMBEDDINGS() function in SQL Server 2025.

    For demo purposes, we generate a deterministic fake embedding
    based on content hash so we can verify staleness detection.

*/

CREATE OR ALTER PROCEDURE
    dbo.EmbedDocument
(
    @document_id integer
)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;

    DECLARE
        @content nvarchar(max),
        @source_hash binary(32),
        @fake_embedding vector(4, float32);

    /*
        Get current content and compute hash
    */
    SELECT
        @content = d.content,
        @source_hash = d.content_hash
    FROM dbo.Documents AS d
    WHERE d.document_id = @document_id;

    IF @content IS NULL
    BEGIN
        RAISERROR(N'Document not found: %d', 16, 1, @document_id);
        RETURN;
    END;

    /*
        Generate a deterministic fake embedding from the content hash.
        Each component is one byte of the hash mapped to [0, 1].
        Different content > different hash > different vector,
        which is what we need to show staleness on demand.
        (In production you'd use an API call / AI_GENERATE_EMBEDDINGS.)
    */
    SELECT
        @fake_embedding =
            CONVERT
            (
                vector(4, float32),
                N'[' +
                CONVERT
                (
                  nvarchar(20),
                  CONVERT(tinyint, SUBSTRING(@source_hash, 1, 1)) / 255.0
                ) +
                N', ' +
                CONVERT
                (
                  nvarchar(20),
                  CONVERT(tinyint, SUBSTRING(@source_hash, 2, 1)) / 255.0
                ) +
                N', ' +
                CONVERT
                (
                  nvarchar(20),
                  CONVERT(tinyint, SUBSTRING(@source_hash, 3, 1)) / 255.0
                ) +
                N', ' +
                CONVERT
                (
                  nvarchar(20),
                  CONVERT(tinyint, SUBSTRING(@source_hash, 4, 1)) / 255.0
                ) +
                N']'
            );

    /*
        Check if embedding already exists for this document
    */
    IF EXISTS
    (
        SELECT
            1/0
        FROM dbo.DocumentEmbeddings AS de
            WITH (UPDLOCK, SERIALIZABLE)
        WHERE de.document_id = @document_id
    )
    BEGIN
        /*
            Update existing embedding
        */
        UPDATE
            de
        SET
            de.embedding = @fake_embedding,
            de.source_hash = @source_hash,
            de.embedded_at = SYSUTCDATETIME()
        FROM dbo.DocumentEmbeddings AS de
        WHERE de.document_id = @document_id;
    END;
    ELSE
    BEGIN
        /*
            Insert new embedding
        */
        INSERT INTO
            dbo.DocumentEmbeddings
        (
            document_id,
            embedding,
            source_hash,
            embedded_at
        )
        VALUES
        (
            @document_id,
            @fake_embedding,
            @source_hash,
            SYSUTCDATETIME()
        );
    END;
END;
GO


/*
████████████████████████████████████████████████████████████████████████████████
██                                                                            ██
██                       STALENESS DETECTION VIEWS                            ██
██                                                                            ██
████████████████████████████████████████████████████████████████████████████████

    View to detect stale embeddings
    Compares current source hash to stored embedding hash

*/

CREATE OR ALTER VIEW
    dbo.StaleEmbeddings
AS
SELECT
    d.document_id,
    d.title,
    d.modified_at,
    de.embedded_at,
    staleness_minutes =
        DATEDIFF
        (
            MINUTE,
            de.embedded_at,
            d.modified_at
        ),
    current_hash = d.content_hash,
    stored_hash = de.source_hash,
    is_stale =
        CASE
            WHEN d.content_hash <> de.source_hash
            THEN 1
            ELSE 0
        END
FROM dbo.Documents AS d
JOIN dbo.DocumentEmbeddings AS de
  ON de.document_id = d.document_id;
GO


/*
    View to find documents missing embeddings entirely
*/

CREATE OR ALTER VIEW
    dbo.MissingEmbeddings
AS
SELECT
    d.document_id,
    d.title,
    d.modified_at,
    content_length = LEN(d.content)
FROM dbo.Documents AS d
WHERE NOT EXISTS
(
    SELECT
        1/0
    FROM dbo.DocumentEmbeddings AS de
    WHERE de.document_id = d.document_id
);
GO


/*
████████████████████████████████████████████████████████████████████████████████
██                                                                            ██
██                       DUPLICATE DETECTION VIEWS                            ██
██                                                                            ██
████████████████████████████████████████████████████████████████████████████████

    Reuse the content_hash column to ask whether multiple documents
    share identical content. Catches:

    * Same document imported twice
    * Copy/paste errors in source data
    * ETL pipelines running twice

*/

CREATE OR ALTER VIEW
    dbo.DuplicateDocuments
AS
SELECT
    d.content_hash,
    duplicate_count = COUNT_BIG(*),
    document_ids =
        STRING_AGG(d.document_id, ', ')
            WITHIN GROUP (ORDER BY d.document_id),
    titles =
        STRING_AGG(d.title, ', ')
            WITHIN GROUP (ORDER BY d.document_id)
FROM dbo.Documents AS d
GROUP BY
    d.content_hash
HAVING
    COUNT_BIG(*) > 1;
GO


/*
    Summary stats for monitoring
*/
CREATE OR ALTER VIEW
    dbo.DocumentHealthSummary
AS
SELECT
    total_documents =
    (
        SELECT TOP (1)
            COUNT_BIG(*)
        FROM dbo.Documents AS d
    ),
    unique_content =
    (
        SELECT TOP (1)
            COUNT_BIG(DISTINCT d.content_hash)
        FROM dbo.Documents AS d
    ),
    duplicate_groups =
    (
        SELECT TOP (1)
            COUNT_BIG(*)
        FROM dbo.DuplicateDocuments AS dd
    ),
    stale_embeddings =
    (
        SELECT TOP (1)
            COUNT_BIG(*)
        FROM dbo.StaleEmbeddings AS se
        WHERE se.is_stale = 1
    ),
    missing_embeddings =
    (
        SELECT TOP (1)
            COUNT_BIG(*)
        FROM dbo.MissingEmbeddings AS me
    );
GO


/*
████████████████████████████████████████████████████████████████████████████████
██                                                                            ██
██                         STALENESS DEMO SCENARIO                            ██
██                                                                            ██
████████████████████████████████████████████████████████████████████████████████

    Step 1: Insert some documents

*/

INSERT INTO
    dbo.Documents
(
    title,
    content
)
VALUES
(
  N'SQL Server Performance Tuning',
  N'Index maintenance, query optimization, and wait statistics analysis are key to SQL Server performance.'
),

(
  N'Vector Search Basics',
  N'Embeddings represent semantic meaning as high-dimensional vectors. Cosine similarity measures directional alignment.'
),

(
  N'Database Backup Strategies',
  N'Full, differential, and transaction log backups provide point-in-time recovery capabilities.'
),

(
  N'Query Store Overview',
  N'Query Store captures query plans and runtime statistics for performance troubleshooting.'
);


/*
    Step 2: Generate embeddings for all documents

*/
DECLARE
    @doc_id integer,
    @doc_cursor CURSOR;

SET
    @doc_cursor =
    CURSOR
    LOCAL
    FAST_FORWARD
FOR
SELECT
    d.document_id
FROM dbo.Documents AS d;

OPEN @doc_cursor;

FETCH NEXT
FROM @doc_cursor
INTO @doc_id;

WHILE @@FETCH_STATUS = 0
BEGIN
    EXECUTE dbo.EmbedDocument
        @document_id = @doc_id;

    FETCH NEXT
    FROM @doc_cursor
    INTO @doc_id;
END;
GO


/*
    Step 3: Verify everything is fresh

*/
SELECT
    status = N'Initial state - all fresh',
    se.document_id,
    se.title,
    se.is_stale
FROM dbo.StaleEmbeddings AS se;

SELECT
    status = N'Missing embeddings',
    me.*
FROM dbo.MissingEmbeddings AS me;
GO


/*
    Step 4: Simulate document updates WITHOUT re-embedding

    This is the failure mode we're trying to catch.

    Note: staleness_minutes will show 0 in the demo since everything
    happens in the same second. In production, you'd see actual drift.

*/
UPDATE
    d
SET
    d.content =
        d.content +
        N' Updated with new information about parameter sniffing.',
    d.modified_at = SYSUTCDATETIME()
FROM dbo.Documents AS d
WHERE d.title = N'SQL Server Performance Tuning';

UPDATE
    d
SET
    d.content =
        N'Completely rewriting a session when a feature comes out of preview',
    d.modified_at = SYSUTCDATETIME()
FROM dbo.Documents AS d
WHERE d.title = N'Vector Search Basics';
GO


/*
    Step 5: Detect the staleness

*/
SELECT
    status = N'Stale documents needing re-embedding',
    se.document_id,
    se.title,
    se.modified_at,
    se.embedded_at
FROM dbo.StaleEmbeddings AS se
WHERE se.is_stale = 1;
GO


/*
    Step 5b: How far has the stored vector drifted?

    The stored vector still represents whatever content was there
    at embed time. Compute the embedding the current content would
    produce (same formula EmbedDocument uses, inline) and measure
    cosine distance between stored and current. That's the drift.

*/
WITH
    expected_now AS
(
    SELECT
        d.document_id,
        d.title,
        d.content_hash,
        embedding_now =
            CONVERT
            (
                vector(4, float32),
                N'[' +
                CONVERT
                (
                  nvarchar(20),
                  CONVERT(tinyint, SUBSTRING(d.content_hash, 1, 1)) / 255.0
                ) +
                N', ' +
                CONVERT
                (
                  nvarchar(20),
                  CONVERT(tinyint, SUBSTRING(d.content_hash, 2, 1)) / 255.0
                ) +
                N', ' +
                CONVERT
                (
                  nvarchar(20),
                  CONVERT(tinyint, SUBSTRING(d.content_hash, 3, 1)) / 255.0
                ) +
                N', ' +
                CONVERT
                (
                  nvarchar(20),
                  CONVERT(tinyint, SUBSTRING(d.content_hash, 4, 1)) / 255.0
                ) +
                N']'
            )
    FROM dbo.Documents AS d
)
SELECT
    en.document_id,
    en.title,
    stored_embedding = de.embedding,
    embedding_now = en.embedding_now,
    cosine_drift =
        VECTOR_DISTANCE
        (
            'cosine',
            de.embedding,
            en.embedding_now
        )
FROM expected_now AS en
JOIN dbo.DocumentEmbeddings AS de
  ON de.document_id = en.document_id
WHERE de.source_hash <> en.content_hash;
GO

/*
    Cosine drift > 0 means the stored vector no longer represents
    the document's current content. Search ranks against the OLD
    vector. Users get results based on content that no longer exists.

*/


/*
    Step 6: Insert a new document WITHOUT embedding

*/
INSERT INTO
    dbo.Documents
(
    title,
    content
)
VALUES
(
    N'New Document - No Embedding Yet',
    N'This document was added but the embedding pipeline did not run.'
);

SELECT
    status = N'Documents missing embeddings',
    me.document_id,
    me.title
FROM dbo.MissingEmbeddings AS me;
GO


/*
████████████████████████████████████████████████████████████████████████████████
██                                                                            ██
██                         DUPLICATE DEMO SCENARIO                            ██
██                                                                            ██
████████████████████████████████████████████████████████████████████████████████

    Step 7: Insert duplicate content

    Different titles, same content.
    This happens when ETL runs twice or someone copy/pastes.

*/

INSERT INTO
    dbo.Documents
(
    title,
    content
)
VALUES
(
  N'Query Store Overview (copy)',
  N'Query Store captures query plans and runtime statistics for performance troubleshooting.'
),
(
  N'Query Store Overview (another copy)',
  N'Query Store captures query plans and runtime statistics for performance troubleshooting.'
);
GO


/*
    Step 8: Detect the duplicates
*/
SELECT
    status = N'Duplicate content detected',
    dd.duplicate_count,
    dd.titles
FROM dbo.DuplicateDocuments AS dd;
GO


/*
    Step 9: Check overall health
*/
SELECT
    dhs.*
FROM dbo.DocumentHealthSummary AS dhs;
GO


/*
████████████████████████████████████████████████████████████████████████████████
██                                                                            ██
██                         REMEDIATION PROCEDURE                              ██
██                                                                            ██
████████████████████████████████████████████████████████████████████████████████

    Procedure to refresh all stale and missing embeddings
    Could be run as a scheduled job

*/

CREATE OR ALTER PROCEDURE
    dbo.RefreshStaleEmbeddings
(
    @debug bit = 0
)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;

    DECLARE
        @doc_id integer,
        @refreshed_count integer = 0;

    /*Process stale embeddings*/
    DECLARE
        @stale_cursor CURSOR;

    SET @stale_cursor =
        CURSOR
        LOCAL
        FAST_FORWARD
    FOR
    SELECT
        se.document_id
    FROM dbo.StaleEmbeddings AS se
    WHERE se.is_stale = 1;

    OPEN @stale_cursor;

    FETCH NEXT
    FROM @stale_cursor
    INTO @doc_id;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR(N'Refreshing stale embedding for document_id: %d', 0, 1, @doc_id) WITH NOWAIT;
        END;

        EXECUTE dbo.EmbedDocument
            @document_id = @doc_id;

        SET @refreshed_count += 1;

        FETCH NEXT
        FROM @stale_cursor
        INTO @doc_id;
    END;


    /*Process missing embeddings*/
    DECLARE
        @missing_cursor CURSOR;

    SET @missing_cursor =
        CURSOR
        LOCAL
        FAST_FORWARD
    FOR
    SELECT
        me.document_id
    FROM dbo.MissingEmbeddings AS me;

    OPEN @missing_cursor;

    FETCH NEXT
    FROM @missing_cursor
    INTO @doc_id;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF @debug = 1
        BEGIN
            RAISERROR(N'Creating missing embedding for document_id: %d', 0, 1, @doc_id) WITH NOWAIT;
        END;

        EXECUTE dbo.EmbedDocument
            @document_id = @doc_id;

        SET @refreshed_count += 1;

        FETCH NEXT
        FROM @missing_cursor
        INTO @doc_id;
    END;

    SELECT
        embeddings_refreshed = @refreshed_count;

END;
GO


/*
    Step 10: Run the refresh and verify
*/
EXECUTE dbo.RefreshStaleEmbeddings
    @debug = 1;

SELECT
    status = N'After refresh - all fresh again',
    se.document_id,
    se.title,
    se.is_stale
FROM dbo.StaleEmbeddings AS se;

SELECT
    status = N'Missing embeddings after refresh',
    me.*
FROM dbo.MissingEmbeddings AS me;
GO


/*
    Step 11: Duplicates at the source produce duplicates in the index.

    Now that the new "Query Store Overview" copies have been embedded,
    every duplicate document has its own embedding row. Because the
    content is identical, the vectors are identical too.

    This is how the 350 duplicate copies in file 02 got into the
    graph. The source had duplicate content, the embedding pipeline
    ran on every row, and the index filled up with copies of the
    same direction.

    Detect duplicate source content BEFORE you embed it, not after
    the index is already poisoned.

    Note: SQL Server doesn't allow GROUP BY directly on the vector
    type. We GROUP BY source_hash instead. Same content hash means
    same content, which means same embedding (because EmbedDocument
    derives the vector deterministically from the hash).

*/

SELECT
    source_hash = de.source_hash,
    embedding_copies = COUNT_BIG(*),
    document_ids =
        STRING_AGG(de.document_id, ', ')
            WITHIN GROUP
            (
                ORDER BY
                    de.document_id
             ),
    sample_embedding =
        MIN
        (
            CONVERT(nvarchar(max),
            de.embedding)
        )
FROM dbo.DocumentEmbeddings AS de
GROUP BY
    de.source_hash
HAVING
    COUNT_BIG(*) > 1;
GO


/*
████████████████████████████████████████████████████████████████████████████████
██                                                                            ██
██                          PREVENTION LAYERS                                 ██
██                                                                            ██
████████████████████████████████████████████████████████████████████████████████

    Catch this stuff before it gets into the index, not after.


    Where duplicates come from
    --------------------------
    Almost never on purpose. The usual suspects:

      * ETL re-runs and overlapping batch windows
      * Retry logic firing after an API call the caller didn't record
      * Chunking overlap: adjacent chunks of the same document
      * Template/boilerplate content (support tickets, product blurbs)
      * Source-system duplicates that nobody deduped before ingest

    None of these are "bad code," and all of them poison the graph
    the same way.


    The layers (cheapest to most expensive)
    ---------------------------------------
    1. Dedup at source
       Free. The earlier in the pipeline, the cheaper.

    2. Hash and check before you embed
       One index seek vs. one API call that costs money and 200ms.

    3. Dedup the staging table
       GROUP BY content_hash, take one row. Before insert.

    4. Database enforcement: IGNORE_DUP_KEY
       Unique index on content_hash with IGNORE_DUP_KEY = ON
       silently drops duplicates. The non-duplicate rows in the
       same batch still go in. No error, no rollback, no retry.

           CREATE TABLE
               dbo.EmbeddingStore
           (
               id integer
                   IDENTITY
                   PRIMARY KEY CLUSTERED,
               content_hash binary(32) NOT NULL,
               embedding vector(1024, float32) NOT NULL,
               INDEX
                   EmbeddingStore_content_hash
               UNIQUE
                   (content_hash)
               WITH
                   (IGNORE_DUP_KEY = ON)
           );

    5. Post-insert detection (everything in this file)
       The most expensive layer. The graph is already polluted.
       You're cleaning up, not preventing.

    Treat the database as the last line, not the first.

*/


/*
████████████████████████████████████████████████████████████████████████████████
██                                                                            ██
██               NEAR-DUPLICATE AUDIT (when content hash isn't enough)        ██
██                                                                            ██
████████████████████████████████████████████████████████████████████████████████

    Content hashing catches byte-for-byte duplicates. It does NOT catch
    near-duplicates: same logical content with a different copyright year,
    different line endings, a stray invisible character at the start.
    Those rows have different hashes, so the dedup check waves them
    through.

    The embedding model doesn't care about that formatting noise. It
    produces near-identical vectors, and cosine reads them as
    distance zero, so top-K floods with copies anyway.

    Three audit patterns, cheapest first.

    These run against dbo.VectorEmbeddings, whatever state the earlier
    files left it in. After the natural file order (02 then 02b), the
    table holds 350 zeros + 12 distinct vectors, and approach 1 finds
    an 8-vector near-duplicate cluster (great_match + 4 nears + 3
    scaled_big sit pairwise close at cosine ~0.0003). The bytes
    don't match, so content_hash lets them through, but cosine
    collapses them into one cluster. That's the gap the audit fills.

    Apply the patterns to whatever embedding table you have.

    Note: with 02b's zero-flooded state, approaches 2 and 3 produce
    weaker output (the 350 zeros dominate the quantized-hash buckets,
    and a random sample mostly picks zeros that don't cluster). If you
    want to show clusters of cosine-identical exact duplicates instead,
    re-run file 02's setup first.

*/


/*
    ──────────────────────────────────────────────────────────
    APPROACH 1: vector-index self-search
    ──────────────────────────────────────────────────────────
    For each row, ask the existing vector index for its nearest
    neighbors. Anything other than itself within a tight distance
    threshold is a semantic near-duplicate.

    Cost: O(N) index searches. Practical up to millions of rows
    because each search is fast.

    Tunable: the distance threshold. 0.01 is "near-identical"
    for cosine-distance metrics. Tighten to 0.001 if you only want
    perfect copies. Loosen to 0.05 if you want paraphrase-level
    near-duplicates (but you'll start catching legitimate neighbors).

*/

SELECT TOP (10)
    source_id = e.Id,
    source_label = e.Label,
    near_dup_id = vs.Id,
    near_dup_label = vs.Label,
    distance = vs.distance
FROM dbo.VectorEmbeddings AS e
CROSS APPLY
(
    SELECT TOP (10) WITH APPROXIMATE
        ve.Id,
        ve.Label,
        r.distance
    FROM VECTOR_SEARCH
    (
        TABLE = dbo.VectorEmbeddings AS ve,
        COLUMN = Embedding,
        SIMILAR_TO = e.Embedding,
        METRIC = 'cosine'
    ) AS r
      WITH (FORCE_ANN_ONLY)
    ORDER BY
        r.distance
) AS vs
WHERE vs.Id <> e.Id
AND   vs.distance < 0.01
ORDER BY
    vs.distance,
    e.Id;
GO

/*
    Cluster-size summary: how many near-duplicate neighbors does
    each row have? A row with hundreds of cosine-zero neighbors is
    the center of a large duplicate cluster.

*/

SELECT
    cluster_size =
        c.n,
    rows_with_this_neighbor_count =
        COUNT_BIG(*)
FROM
(
    SELECT
        n =
        (
            SELECT
                COUNT_BIG(*)
            FROM
            (
                SELECT TOP (200) WITH APPROXIMATE
                    r.distance
                FROM VECTOR_SEARCH
                (
                    TABLE = dbo.VectorEmbeddings AS ve,
                    COLUMN = Embedding,
                    SIMILAR_TO = e.Embedding,
                    METRIC = 'cosine'
                ) AS r
                  WITH (FORCE_ANN_ONLY)
                ORDER BY
                    r.distance
            ) AS s
            WHERE s.distance < 0.01
        )
    FROM dbo.VectorEmbeddings AS e
) AS c
GROUP BY
    c.n
ORDER BY
    c.n DESC;
GO


/*
    ──────────────────────────────────────────────────────────
    APPROACH 2: quantized-hash dedup
    ──────────────────────────────────────────────────────────
    Round each component to N decimals, hash the rounded JSON
    representation, group by hash. Vectors that round to the
    same values produce the same hash.

    Cost: O(N) rows, single pass. No index dependency. Fastest
    of the three for large-scale audit.

    Tunable: ROUND precision (3 decimals here). For normalized
    embeddings (magnitude = 1), 3 decimals is reasonable. For
    unnormalized vectors, this approach catches duplicates with
    SAME magnitude but misses cosine-identical pairs that differ
    only in magnitude. Approach 1 catches both.

*/

WITH q AS
(
    SELECT
        e.Id,
        e.Label,
        quantized_hash =
            HASHBYTES
            (
                'SHA2_256',
                CONVERT
                (
                    nvarchar(max),
                    (
                        SELECT
                            v = ROUND(CAST(j.value AS float), 3)
                        FROM OPENJSON(CAST(e.Embedding AS nvarchar(max))) AS j
                        FOR JSON PATH
                    )
                )
            )
    FROM dbo.VectorEmbeddings AS e
)
SELECT
    quantized_hash = q.quantized_hash,
    cluster_size = COUNT_BIG(*),
    sample_ids =
        LEFT
        (
            STRING_AGG
            (
                CONVERT(nvarchar(20), q.Id),
                ','
            )
                WITHIN GROUP (ORDER BY q.Id),
            80
        )
FROM q
GROUP BY
    q.quantized_hash
HAVING
    COUNT_BIG(*) > 1
ORDER BY
    cluster_size DESC;
GO


/*
    ──────────────────────────────────────────────────────────
    APPROACH 3: random-sample brute-force via VECTOR_DISTANCE
    ──────────────────────────────────────────────────────────
    Pick K random rows using CRYPT_GEN_RANDOM (avoids the
    NEWID full-sort that haunts perf reviews), compare each
    against the whole table with VECTOR_DISTANCE.

    Cost: O(sample × N), exact distances, no index needed.

    Use for ground-truthing the threshold from approach 1.
    If approach 1 says 0.01 catches the duplicates, run this
    on a sample and confirm you're not also catching legitimate
    near-neighbors at 0.005 or 0.008.

*/

DECLARE
    @sample_rows integer = 20,
    @min_id integer,
    @max_id integer,
    @range integer;

SELECT
    @min_id = MIN(Id),
    @max_id = MAX(Id)
FROM dbo.VectorEmbeddings;

SET @range = (@max_id - @min_id) + 1;

WITH
    random_rows
AS
(
    /* @sample_rows distinct random Ids that exist in the table */
    SELECT DISTINCT TOP (@sample_rows)
        random.Id
    FROM dbo.VectorEmbeddings AS ve
    CROSS APPLY
    (
        /* Random Id in [@min_id, @max_id] */
        VALUES
            (@min_id + (CONVERT(integer, CRYPT_GEN_RANDOM(4)) % @range))
    ) AS random (Id)
    WHERE EXISTS
    (
        /* Ensure the row still exists */
        SELECT
            1
        FROM dbo.VectorEmbeddings AS v2
          WITH (REPEATABLEREAD)
        WHERE v2.Id = random.Id
    )
)
SELECT TOP (10)
    sample_id = sampled.Id,
    sample_label = sampled.Label,
    near_dup_id = other.Id,
    near_dup_label = other.Label,
    distance = c.v_distance
FROM random_rows AS r
JOIN dbo.VectorEmbeddings AS sampled
  ON sampled.Id = r.Id
JOIN dbo.VectorEmbeddings AS other
  ON other.Id <> sampled.Id
CROSS APPLY
(
    VALUES
        (VECTOR_DISTANCE('cosine', sampled.Embedding, other.Embedding))
) AS c (v_distance)
WHERE c.v_distance < 0.01
ORDER BY
    distance,
    sample_id,
    near_dup_id;
GO


/*
    None of these three approaches catch paraphrase-level
    near-duplicates. "The system was slow yesterday" vs "yesterday
    the system performed poorly" embed at distance ~0.15, the same
    range as legitimate semantic neighbors. No threshold cleanly
    separates "duplicate I should reject" from "neighbor I should
    return."

    Upstream text-side dedupe (normalize whitespace, strip
    boilerplate, canonicalize formatting) still earns its keep,
    even after you've got vectors and an index.

*/


/*
████████████████████████████████████████████████████████████████████████████████
██                                                                            ██
██                            THE ROUND TRIP                                  ██
██                                                                            ██
████████████████████████████████████████████████████████████████████████████████

    We started this talk with file 02:
     * 362 vectors
     * 350 of them duplicates of 7 source vectors
     * Asked DiskANN for top-50
     * Got 50 photocopies of one direction
     * Recall metric reads 92%, looks fine
     * Result set contains zero of the 4 distinct "near" vectors
       you wanted
     * The dashboard says everything is healthy

    Walk through what each defense would have caught:

      Bad JSON, missing dimensions, parse failures
        * The validation trigger (file 03) routes them to quarantine

      Zero and near-zero magnitude vectors
        * The energy check (file 03) catches them at ingress

      Duplicate source content
        * Content_hash detection flags it before embedding,
          IGNORE_DUP_KEY blocks it at the unique index

      Near-duplicate content that survived the byte-level hash
        * Vector-index self-search, quantized-hash audit, or
          random-sample brute-force (above). Pick the cheapest
          one your scale supports.

      Stale embeddings
        * Current_hash vs source_hash comparison + refresh procedure

      Echo chambers in the result set
        * Prevented entirely if the layers above did their jobs

    All of this is plain T-SQL. Triggers, hashes, GROUP BY, views.
     * You've had every tool to defend a vector graph for twenty years.

    The hype is new. The failure modes are new. The discipline isn't.

    When AI confidently returns wrong answers, you're the person in
    the room who can prove it and fix it.

    W: https://erikdarling.com
    E: mailto:erik@erikdarling.com
    T: https://twitter.com/erikdarlingdata
    T: https://www.tiktok.com/@darling.data
    L: https://www.linkedin.com/company/darling-data/
    Y: https://www.youtube.com/@ErikDarlingData

    Demos:

*/
