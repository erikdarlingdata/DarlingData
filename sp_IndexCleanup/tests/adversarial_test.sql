/*
sp_IndexCleanup Adversarial Test Suite — Setup & Execute
========================================================
This script:
  1. Creates test tables with data and edge-case index configurations
  2. Generates usage stats
  3. Runs sp_IndexCleanup @dedupe_only = 1

Output is captured by the test runner (run_tests.py) for validation.
Run with: python run_tests.py

Direct execution (visual inspection only):
  sqlcmd -S SQL2022 -U sa -P "password" -d StackOverflow2013 -i adversarial_test.sql
*/
SET NOCOUNT ON;

USE StackOverflow2013;
GO

/* ============================================= */
/* Cleanup previous test artifacts               */
/* ============================================= */
IF OBJECT_ID('dbo.test_ic_view') IS NOT NULL
BEGIN
    IF EXISTS (SELECT 1/0 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.test_ic_view') AND name = N'cx_test_ic_view')
        DROP INDEX cx_test_ic_view ON dbo.test_ic_view;
END;
GO
IF OBJECT_ID('dbo.test_ic_view') IS NOT NULL DROP VIEW dbo.test_ic_view;
GO
DROP TABLE IF EXISTS dbo.test_ic_basic;
DROP TABLE IF EXISTS dbo.test_ic_uc;
DROP TABLE IF EXISTS dbo.test_ic_filtered;
DROP TABLE IF EXISTS dbo.test_ic_heap;
DROP TABLE IF EXISTS dbo.test_ic_multi;
DROP TABLE IF EXISTS dbo.test_ic_view_base;
DROP TABLE IF EXISTS dbo.test_ic_exact;
DROP TABLE IF EXISTS dbo.test_ic_reverse;
DROP TABLE IF EXISTS dbo.test_ic_filter_eq;
DROP TABLE IF EXISTS dbo.test_ic_uc_replace;
DROP TABLE IF EXISTS dbo.test_ic_uc_dup;
DROP TABLE IF EXISTS dbo.test_ic_interact;
DROP TABLE IF EXISTS dbo.test_ic_idk_fk_child;
DROP TABLE IF EXISTS dbo.test_ic_idk_fk;
DROP TABLE IF EXISTS dbo.test_ic_idk_pair;
DROP TABLE IF EXISTS dbo.test_ic_idk_rule7;
DROP TABLE IF EXISTS dbo.test_ic_idk_con_child;
DROP TABLE IF EXISTS dbo.test_ic_idk_con;
DROP TABLE IF EXISTS dbo.test_ic_fk_child;
DROP TABLE IF EXISTS dbo.test_ic_fk_parent;
DROP TABLE IF EXISTS dbo.test_ic_uc_solo;
DROP TABLE IF EXISTS dbo.test_ic_uc_pair;
DROP TABLE IF EXISTS dbo.test_ic_filt_sub;
DROP TABLE IF EXISTS dbo.test_ic_ks_narrow_first;
DROP TABLE IF EXISTS dbo.test_ic_ks_wide_first;
DROP TABLE IF EXISTS dbo.test_ic_ks_same_1;
DROP TABLE IF EXISTS dbo.test_ic_ks_same_2;
DROP TABLE IF EXISTS dbo.test_ic_idk_fk_child;
DROP TABLE IF EXISTS dbo.test_ic_idk_fk;
DROP TABLE IF EXISTS dbo.test_ic_idk_pair;
DROP TABLE IF EXISTS dbo.test_ic_idk_rule7;
DROP TABLE IF EXISTS dbo.test_ic_idk_con_child;
DROP TABLE IF EXISTS dbo.test_ic_idk_con;
GO

/* ============================================= */
/* Create test tables with data                  */
/* ============================================= */

CREATE TABLE dbo.test_ic_basic
(
    id bigint IDENTITY(1,1) NOT NULL PRIMARY KEY CLUSTERED,
    col_a integer NOT NULL,
    col_b integer NOT NULL,
    col_c integer NOT NULL,
    col_d integer NOT NULL,
    col_e nvarchar(100) NULL,
    col_f datetime NOT NULL DEFAULT GETDATE()
);

CREATE TABLE dbo.test_ic_uc
(
    id bigint IDENTITY(1,1) NOT NULL PRIMARY KEY CLUSTERED,
    col_a integer NOT NULL,
    col_b integer NOT NULL,
    col_c integer NOT NULL,
    col_d integer NOT NULL,
    col_e nvarchar(100) NULL
);

CREATE TABLE dbo.test_ic_filtered
(
    id bigint IDENTITY(1,1) NOT NULL PRIMARY KEY CLUSTERED,
    col_a integer NOT NULL,
    col_b integer NOT NULL,
    status_code integer NOT NULL
);

CREATE TABLE dbo.test_ic_heap
(
    col_a integer NOT NULL,
    col_b integer NOT NULL,
    col_c integer NOT NULL
);

CREATE TABLE dbo.test_ic_multi
(
    id bigint IDENTITY(1,1) NOT NULL PRIMARY KEY CLUSTERED,
    col_a integer NOT NULL,
    col_b integer NOT NULL
);

CREATE TABLE dbo.test_ic_exact
(
    id bigint IDENTITY(1,1) NOT NULL PRIMARY KEY CLUSTERED,
    col_a integer NOT NULL,
    col_b integer NOT NULL,
    col_c integer NOT NULL
);

CREATE TABLE dbo.test_ic_reverse
(
    id bigint IDENTITY(1,1) NOT NULL PRIMARY KEY CLUSTERED,
    col_a integer NOT NULL,
    col_b integer NOT NULL,
    col_c integer NOT NULL
);

CREATE TABLE dbo.test_ic_filter_eq
(
    id bigint IDENTITY(1,1) NOT NULL PRIMARY KEY CLUSTERED,
    col_a integer NOT NULL,
    col_b integer NOT NULL,
    status_code integer NOT NULL
);

CREATE TABLE dbo.test_ic_uc_replace
(
    id bigint IDENTITY(1,1) NOT NULL PRIMARY KEY CLUSTERED,
    col_a integer NOT NULL,
    col_b integer NOT NULL,
    col_c integer NOT NULL,
    col_d integer NOT NULL
);

CREATE TABLE dbo.test_ic_uc_dup
(
    id bigint IDENTITY(1,1) NOT NULL PRIMARY KEY CLUSTERED,
    col_a integer NOT NULL,
    col_b integer NOT NULL,
    col_c integer NOT NULL
);

CREATE TABLE dbo.test_ic_fk_parent
(
    id bigint IDENTITY(1,1) NOT NULL PRIMARY KEY CLUSTERED,
    code integer NOT NULL
);

CREATE TABLE dbo.test_ic_fk_child
(
    id bigint IDENTITY(1,1) NOT NULL PRIMARY KEY CLUSTERED,
    code integer NOT NULL
);

/* Group 14: a unique constraint with no other index on its key (issue #903) */
CREATE TABLE dbo.test_ic_uc_solo
(
    id bigint IDENTITY(1,1) NOT NULL PRIMARY KEY CLUSTERED,
    code integer NOT NULL
);

/* Group 14: two unique constraints on the same key, the pair that really is a duplicate */
CREATE TABLE dbo.test_ic_uc_pair
(
    id bigint IDENTITY(1,1) NOT NULL PRIMARY KEY CLUSTERED,
    code integer NOT NULL
);

/* Group 15: a column whose name is a substring of another's (issue #904) */
CREATE TABLE dbo.test_ic_filt_sub
(
    id bigint IDENTITY(1,1) NOT NULL PRIMARY KEY CLUSTERED,
    site_id integer NOT NULL,
    qty integer NULL
);

/* Group 16: Same Keys Different Order, which needs one table per index pair (issue #908) */
CREATE TABLE dbo.test_ic_ks_narrow_first
(
    id bigint IDENTITY(1,1) NOT NULL PRIMARY KEY CLUSTERED,
    col_a integer NOT NULL,
    col_b integer NOT NULL,
    col_c integer NOT NULL,
    col_d integer NOT NULL
);

CREATE TABLE dbo.test_ic_ks_wide_first
(
    id bigint IDENTITY(1,1) NOT NULL PRIMARY KEY CLUSTERED,
    col_a integer NOT NULL,
    col_b integer NOT NULL,
    col_c integer NOT NULL,
    col_d integer NOT NULL
);

CREATE TABLE dbo.test_ic_ks_same_1
(
    id bigint IDENTITY(1,1) NOT NULL PRIMARY KEY CLUSTERED,
    col_a integer NOT NULL,
    col_b integer NOT NULL,
    col_c integer NOT NULL,
    col_d integer NOT NULL
);

CREATE TABLE dbo.test_ic_ks_same_2
(
    id bigint IDENTITY(1,1) NOT NULL PRIMARY KEY CLUSTERED,
    col_a integer NOT NULL,
    col_b integer NOT NULL,
    col_c integer NOT NULL,
    col_d integer NOT NULL
);

CREATE TABLE dbo.test_ic_interact
(
    id bigint IDENTITY(1,1) NOT NULL PRIMARY KEY CLUSTERED,
    col_a integer NOT NULL,
    col_b integer NOT NULL,
    col_c integer NOT NULL,
    col_d integer NOT NULL,
    col_e nvarchar(100) NULL
);

CREATE TABLE dbo.test_ic_view_base
(
    id bigint IDENTITY(1,1) NOT NULL PRIMARY KEY CLUSTERED,
    col_a integer NOT NULL,
    col_b integer NOT NULL,
    col_c integer NOT NULL
);
GO

CREATE VIEW dbo.test_ic_view WITH SCHEMABINDING
AS
SELECT
    col_a = tvb.col_a,
    col_b = tvb.col_b,
    row_count = COUNT_BIG(*)
FROM dbo.test_ic_view_base AS tvb
GROUP BY tvb.col_a, tvb.col_b;
GO

/* Populate with 10K+ rows */
INSERT INTO dbo.test_ic_basic (col_a, col_b, col_c, col_d, col_e)
SELECT TOP (10000) ABS(CHECKSUM(NEWID())) % 1000, ABS(CHECKSUM(NEWID())) % 500,
    ABS(CHECKSUM(NEWID())) % 200, ABS(CHECKSUM(NEWID())) % 100, LEFT(NEWID(), 20)
FROM sys.all_objects AS a CROSS JOIN sys.all_objects AS b;

INSERT INTO dbo.test_ic_uc (col_a, col_b, col_c, col_d, col_e)
SELECT TOP (10000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),
    ABS(CHECKSUM(NEWID())) % 500, ABS(CHECKSUM(NEWID())) % 200,
    ABS(CHECKSUM(NEWID())) % 100, LEFT(NEWID(), 20)
FROM sys.all_objects AS a CROSS JOIN sys.all_objects AS b;

INSERT INTO dbo.test_ic_filtered (col_a, col_b, status_code)
SELECT TOP (10000) ABS(CHECKSUM(NEWID())) % 1000, ABS(CHECKSUM(NEWID())) % 500,
    ABS(CHECKSUM(NEWID())) % 5
FROM sys.all_objects AS a CROSS JOIN sys.all_objects AS b;

INSERT INTO dbo.test_ic_heap (col_a, col_b, col_c)
SELECT TOP (10000) ABS(CHECKSUM(NEWID())) % 1000, ABS(CHECKSUM(NEWID())) % 500,
    ABS(CHECKSUM(NEWID())) % 200
FROM sys.all_objects AS a CROSS JOIN sys.all_objects AS b;

INSERT INTO dbo.test_ic_multi (col_a, col_b)
SELECT TOP (10000) ABS(CHECKSUM(NEWID())) % 1000, ABS(CHECKSUM(NEWID())) % 500
FROM sys.all_objects AS a CROSS JOIN sys.all_objects AS b;

INSERT INTO dbo.test_ic_view_base (col_a, col_b, col_c)
SELECT TOP (10000) ABS(CHECKSUM(NEWID())) % 100, ABS(CHECKSUM(NEWID())) % 50,
    ABS(CHECKSUM(NEWID())) % 200
FROM sys.all_objects AS a CROSS JOIN sys.all_objects AS b;

INSERT INTO dbo.test_ic_exact (col_a, col_b, col_c)
SELECT TOP (10000) ABS(CHECKSUM(NEWID())) % 1000, ABS(CHECKSUM(NEWID())) % 500,
    ABS(CHECKSUM(NEWID())) % 200
FROM sys.all_objects AS a CROSS JOIN sys.all_objects AS b;

INSERT INTO dbo.test_ic_reverse (col_a, col_b, col_c)
SELECT TOP (10000) ABS(CHECKSUM(NEWID())) % 1000, ABS(CHECKSUM(NEWID())) % 500,
    ABS(CHECKSUM(NEWID())) % 200
FROM sys.all_objects AS a CROSS JOIN sys.all_objects AS b;

INSERT INTO dbo.test_ic_filter_eq (col_a, col_b, status_code)
SELECT TOP (10000) ABS(CHECKSUM(NEWID())) % 1000, ABS(CHECKSUM(NEWID())) % 500,
    ABS(CHECKSUM(NEWID())) % 5
FROM sys.all_objects AS a CROSS JOIN sys.all_objects AS b;

INSERT INTO dbo.test_ic_uc_replace (col_a, col_b, col_c, col_d)
SELECT TOP (10000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),
    ABS(CHECKSUM(NEWID())) % 500, ABS(CHECKSUM(NEWID())) % 200,
    ABS(CHECKSUM(NEWID())) % 100
FROM sys.all_objects AS a CROSS JOIN sys.all_objects AS b;

INSERT INTO dbo.test_ic_fk_parent (code)
SELECT TOP (100) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) FROM sys.all_columns;

INSERT INTO dbo.test_ic_fk_child (code)
SELECT TOP (100) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) FROM sys.all_columns;

/*
Group 17: IGNORE_DUP_KEY (issue #916)

Four tables, because the four outcomes are decided in four different places:

  test_ic_idk_pair    two unique indexes, the skipper sorting LAST, so the name
                      tiebreak used to pick it as the loser. The term decides it now.
  test_ic_idk_fk      the interaction: the strict index backs a foreign key, the
                      skipper backs nothing. The key's index wins and takes the option.
  test_ic_idk_rule7   Rule 7, which reads no priority: the skipping CONSTRAINT is
                      dropped for the already-unique strict INDEX, so there is no
                      rebuild for the option to ride along in.
  test_ic_idk_con     two unique CONSTRAINTS, one backing a key and one skipping.
                      ALTER INDEX cannot give a constraint the option (error 1979),
                      so both have to stay.

ROW_NUMBER rather than a random value everywhere: every key below is unique, and
a duplicate would make the CREATE fail rather than the test.
*/
CREATE TABLE dbo.test_ic_idk_pair (id integer IDENTITY PRIMARY KEY, code integer NOT NULL);
CREATE TABLE dbo.test_ic_idk_fk (id integer IDENTITY PRIMARY KEY, code integer NOT NULL);
CREATE TABLE dbo.test_ic_idk_fk_child (id integer IDENTITY PRIMARY KEY, code integer NOT NULL);
CREATE TABLE dbo.test_ic_idk_rule7 (id integer IDENTITY PRIMARY KEY, code integer NOT NULL);
CREATE TABLE dbo.test_ic_idk_con (id integer IDENTITY PRIMARY KEY, code integer NOT NULL);
CREATE TABLE dbo.test_ic_idk_con_child (id integer IDENTITY PRIMARY KEY, code integer NOT NULL);

INSERT INTO dbo.test_ic_idk_pair (code)
SELECT TOP (100) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) FROM sys.all_columns;

INSERT INTO dbo.test_ic_idk_fk (code)
SELECT TOP (100) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) FROM sys.all_columns;

INSERT INTO dbo.test_ic_idk_fk_child (code)
SELECT TOP (100) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) FROM sys.all_columns;

INSERT INTO dbo.test_ic_idk_rule7 (code)
SELECT TOP (100) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) FROM sys.all_columns;

INSERT INTO dbo.test_ic_idk_con (code)
SELECT TOP (100) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) FROM sys.all_columns;

INSERT INTO dbo.test_ic_idk_con_child (code)
SELECT TOP (100) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) FROM sys.all_columns;

/* ROW_NUMBER and not a random value: the unique constraints below have to be creatable, see the note on test_ic_interact */
INSERT INTO dbo.test_ic_uc_solo (code)
SELECT TOP (100) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) FROM sys.all_columns;

INSERT INTO dbo.test_ic_uc_pair (code)
SELECT TOP (100) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) FROM sys.all_columns;

INSERT INTO dbo.test_ic_filt_sub (site_id, qty)
SELECT TOP (1000) ABS(CHECKSUM(NEWID())) % 10, ABS(CHECKSUM(NEWID())) % 20
FROM sys.all_objects AS a CROSS JOIN sys.all_objects AS b;

INSERT INTO dbo.test_ic_ks_narrow_first (col_a, col_b, col_c, col_d)
SELECT TOP (1000) ABS(CHECKSUM(NEWID())) % 100, ABS(CHECKSUM(NEWID())) % 50,
    ABS(CHECKSUM(NEWID())) % 20, ABS(CHECKSUM(NEWID())) % 10
FROM sys.all_objects AS a CROSS JOIN sys.all_objects AS b;

INSERT INTO dbo.test_ic_ks_wide_first (col_a, col_b, col_c, col_d)
SELECT TOP (1000) ABS(CHECKSUM(NEWID())) % 100, ABS(CHECKSUM(NEWID())) % 50,
    ABS(CHECKSUM(NEWID())) % 20, ABS(CHECKSUM(NEWID())) % 10
FROM sys.all_objects AS a CROSS JOIN sys.all_objects AS b;

INSERT INTO dbo.test_ic_ks_same_1 (col_a, col_b, col_c, col_d)
SELECT TOP (1000) ABS(CHECKSUM(NEWID())) % 100, ABS(CHECKSUM(NEWID())) % 50,
    ABS(CHECKSUM(NEWID())) % 20, ABS(CHECKSUM(NEWID())) % 10
FROM sys.all_objects AS a CROSS JOIN sys.all_objects AS b;

INSERT INTO dbo.test_ic_ks_same_2 (col_a, col_b, col_c, col_d)
SELECT TOP (1000) ABS(CHECKSUM(NEWID())) % 100, ABS(CHECKSUM(NEWID())) % 50,
    ABS(CHECKSUM(NEWID())) % 20, ABS(CHECKSUM(NEWID())) % 10
FROM sys.all_objects AS a CROSS JOIN sys.all_objects AS b;

INSERT INTO dbo.test_ic_uc_dup (col_a, col_b, col_c)
SELECT TOP (10000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),
    ABS(CHECKSUM(NEWID())) % 500, ABS(CHECKSUM(NEWID())) % 200
FROM sys.all_objects AS a CROSS JOIN sys.all_objects AS b;

/*
col_c is ROW_NUMBER(), not a random value, and that matters. Group 12b creates
uq_int_cd UNIQUE (col_c, col_d) below. With col_c and col_d drawn randomly from
200 and 100 values across 10,000 rows, duplicate pairs were a certainty, so the
constraint failed to create on EVERY run with Msg 1505, Msg 1750 followed, and
the read loop's forced hint on the missing index aborted the usage batch with
Msg 308. Group 12b was never actually tested, and the suite could not see any of
it because the runner checked stderr while go-sqlcmd reports errors on stdout.

A unique col_c makes (col_c, col_d) unique regardless of col_d. col_a and col_b
stay duplicated on purpose - the subset chain in 12a needs repeated values.
*/
INSERT INTO dbo.test_ic_interact (col_a, col_b, col_c, col_d, col_e)
SELECT TOP (10000) ABS(CHECKSUM(NEWID())) % 1000, ABS(CHECKSUM(NEWID())) % 500,
    ROW_NUMBER() OVER (ORDER BY (SELECT NULL)), ABS(CHECKSUM(NEWID())) % 100, LEFT(NEWID(), 20)
FROM sys.all_objects AS a CROSS JOIN sys.all_objects AS b;
GO

/* ============================================= */
/* Create test indexes                           */
/* ============================================= */

/* Group 1: UC as superset (#721, #724) */
ALTER TABLE dbo.test_ic_uc ADD CONSTRAINT uq_uc_abc UNIQUE (col_a, col_b, col_c);
CREATE NONCLUSTERED INDEX ix_uc_ab ON dbo.test_ic_uc (col_a, col_b);
CREATE NONCLUSTERED INDEX ix_uc_ab_inc ON dbo.test_ic_uc (col_a, col_b) INCLUDE (col_e);
CREATE NONCLUSTERED INDEX ix_uc_bc ON dbo.test_ic_uc (col_b, col_c);
CREATE UNIQUE NONCLUSTERED INDEX uix_uc_acd ON dbo.test_ic_uc (col_a, col_c, col_d);
/* col_e is what uix_uc_acd gains from the merge: without it the merge would change nothing (#906) */
CREATE NONCLUSTERED INDEX ix_uc_ac ON dbo.test_ic_uc (col_a, col_c) INCLUDE (col_e);
ALTER TABLE dbo.test_ic_uc ADD CONSTRAINT uq_uc_ad UNIQUE (col_a, col_d);

/* Group 2: Sort direction */
CREATE INDEX ix_sort_a_desc ON dbo.test_ic_basic (col_a DESC);
CREATE INDEX ix_sort_a_desc2 ON dbo.test_ic_basic (col_a DESC);
CREATE INDEX ix_sort_a_asc ON dbo.test_ic_basic (col_a ASC);
CREATE INDEX ix_sort_ab_asc ON dbo.test_ic_basic (col_a ASC, col_b ASC);
CREATE INDEX ix_sort_ab_mixed ON dbo.test_ic_basic (col_a DESC, col_b ASC);

/* Group 3: Filtered indexes */
CREATE INDEX ix_filt_a_s1 ON dbo.test_ic_filtered (col_a) WHERE status_code = 1;
CREATE INDEX ix_filt_a_s1_dup ON dbo.test_ic_filtered (col_a) WHERE status_code = 1;
CREATE INDEX ix_filt_a_s2 ON dbo.test_ic_filtered (col_a) WHERE status_code = 2;
CREATE INDEX ix_filt_ab_s3 ON dbo.test_ic_filtered (col_a, col_b) WHERE status_code = 3;
CREATE INDEX ix_filt_a_s3 ON dbo.test_ic_filtered (col_a) WHERE status_code = 3;
CREATE INDEX ix_filt_ab_s4 ON dbo.test_ic_filtered (col_a, col_b) WHERE status_code = 4;
CREATE INDEX ix_filt_a_s0 ON dbo.test_ic_filtered (col_a) WHERE status_code = 0;

/* Group 4a: Key Duplicate — same keys, different includes, no wider index */
CREATE INDEX ix_inc_f_inc_b ON dbo.test_ic_basic (col_f) INCLUDE (col_b);
CREATE INDEX ix_inc_f_inc_c ON dbo.test_ic_basic (col_f) INCLUDE (col_c);

/* Group 4b: Key Subset — narrower key with includes absorbed by wider key */
CREATE INDEX ix_inc_cd_inc_e ON dbo.test_ic_basic (col_c, col_d) INCLUDE (col_e);
CREATE INDEX ix_inc_c_inc_b ON dbo.test_ic_basic (col_c) INCLUDE (col_b);

/* Group 5: Indexed view */
CREATE UNIQUE CLUSTERED INDEX cx_test_ic_view ON dbo.test_ic_view (col_a, col_b);
CREATE NONCLUSTERED INDEX ix_view_a ON dbo.test_ic_view (col_a);
CREATE NONCLUSTERED INDEX ix_view_a_dup ON dbo.test_ic_view (col_a);

/* Group 6: Heap */
CREATE NONCLUSTERED INDEX ix_heap_a ON dbo.test_ic_heap (col_a);
CREATE NONCLUSTERED INDEX ix_heap_a_dup ON dbo.test_ic_heap (col_a);

/* Group 7: Multi-table isolation */
CREATE INDEX ix_multi_a ON dbo.test_ic_multi (col_a);
CREATE INDEX ix_basic_col_d ON dbo.test_ic_basic (col_d);

/* Group 8: Exact Duplicate — same keys AND same includes */
CREATE INDEX ix_exact_ab_1 ON dbo.test_ic_exact (col_a, col_b) INCLUDE (col_c);
CREATE INDEX ix_exact_ab_2 ON dbo.test_ic_exact (col_a, col_b) INCLUDE (col_c);

/* Group 9: Reverse Duplicate — same columns, different leading order */
CREATE INDEX ix_rev_ab ON dbo.test_ic_reverse (col_a, col_b);
CREATE INDEX ix_rev_ba ON dbo.test_ic_reverse (col_b, col_a);

/* Group 10: Equal Except For Filter */
/* 10a: Same keys, one filtered one not — should NOT match */
CREATE INDEX ix_feq_a ON dbo.test_ic_filter_eq (col_a);
CREATE INDEX ix_feq_a_filt ON dbo.test_ic_filter_eq (col_a) WHERE status_code = 1;

/* Group 11: UC Replacement (Rule 7/7.5) — exact key match */
ALTER TABLE dbo.test_ic_uc_replace ADD CONSTRAINT uq_ucr_ab UNIQUE (col_a, col_b);
CREATE NONCLUSTERED INDEX ix_ucr_ab_inc ON dbo.test_ic_uc_replace (col_a, col_b) INCLUDE (col_c);

/* Group 11b: UC-vs-UC duplicates with no replacement NC (issue #782, Rule 7.5b)
   — keeper kept, duplicate dropped via DROP CONSTRAINT */
ALTER TABLE dbo.test_ic_uc_dup ADD CONSTRAINT uq_ucd_keeper UNIQUE (col_a, col_b, col_c);
ALTER TABLE dbo.test_ic_uc_dup ADD CONSTRAINT uq_ucd_zloser UNIQUE (col_a, col_b, col_c);

/* Group 13: A unique index a foreign key is backed by (issue #902)
   - ux_z is created first, so sys.foreign_keys.key_index_id names it
   - ux_a is an exact duplicate that sorts earlier by name, which is the
     tiebreak that used to make ux_z the loser and emit DISABLE against it,
     silently disabling the foreign key too */
CREATE UNIQUE INDEX ux_fkp_z_code ON dbo.test_ic_fk_parent (code);
ALTER TABLE dbo.test_ic_fk_child ADD CONSTRAINT fk_ic_child_code
    FOREIGN KEY (code) REFERENCES dbo.test_ic_fk_parent (code);
CREATE UNIQUE INDEX ux_fkp_a_code ON dbo.test_ic_fk_parent (code);

/* Group 17: IGNORE_DUP_KEY (issue #916) */

/* 17a: the skipper sorts LAST, which is what the name tiebreak used to punish */
CREATE UNIQUE INDEX ux_idkp_a_strict ON dbo.test_ic_idk_pair (code);
CREATE UNIQUE INDEX ux_idkp_z_skip ON dbo.test_ic_idk_pair (code) WITH (IGNORE_DUP_KEY = ON);

/* 17b: the strict one backs the key, so it outranks the skipper and takes the option */
CREATE UNIQUE INDEX ux_idkf_strict ON dbo.test_ic_idk_fk (code);
ALTER TABLE dbo.test_ic_idk_fk_child ADD CONSTRAINT fk_ic_idk_child_code
    FOREIGN KEY (code) REFERENCES dbo.test_ic_idk_fk (code);
CREATE UNIQUE INDEX ux_idkf_skip ON dbo.test_ic_idk_fk (code) WITH (IGNORE_DUP_KEY = ON);

/* 17c: Rule 7 drops the skipping constraint for the already-unique strict index */
ALTER TABLE dbo.test_ic_idk_rule7 ADD CONSTRAINT uq_idk7_skip UNIQUE (code) WITH (IGNORE_DUP_KEY = ON);
CREATE UNIQUE INDEX ux_idk7_strict ON dbo.test_ic_idk_rule7 (code);

/* 17d: two CONSTRAINTS, one backing a key and one skipping. Neither can be altered. */
ALTER TABLE dbo.test_ic_idk_con ADD CONSTRAINT uq_idkc_a_key UNIQUE (code);
ALTER TABLE dbo.test_ic_idk_con_child ADD CONSTRAINT fk_ic_idkc_child_code
    FOREIGN KEY (code) REFERENCES dbo.test_ic_idk_con (code);
ALTER TABLE dbo.test_ic_idk_con ADD CONSTRAINT uq_idkc_z_skip UNIQUE (code) WITH (IGNORE_DUP_KEY = ON);

/* Group 14: A unique constraint with no other index on its key (issue #903)
   - Rule 7 used to match every unique constraint against ITSELF, so each one
     came back KEPT under 'Unique Constraint Replacement' with nothing to replace
   - nothing else on this table has the key (code), so there is no replacement
   - the table is compressed already, the way the issue's repro does it. An index
     that still needs compression gets a COMPRESSION SCRIPT row and no KEPT row,
     so the label would never reach the results and the test would pass for nothing
   - uc_pair is the control: two constraints on one key ARE duplicates of each
     other, so the keeper keeps its label and the loser is dropped */
ALTER TABLE dbo.test_ic_uc_solo ADD CONSTRAINT uq_ucs_code UNIQUE (code);
ALTER INDEX ALL ON dbo.test_ic_uc_solo REBUILD WITH (DATA_COMPRESSION = PAGE);
ALTER TABLE dbo.test_ic_uc_pair ADD CONSTRAINT uq_ucp_keeper UNIQUE (code);
ALTER TABLE dbo.test_ic_uc_pair ADD CONSTRAINT uq_ucp_zloser UNIQUE (code);
ALTER INDEX ALL ON dbo.test_ic_uc_pair REBUILD WITH (DATA_COMPRESSION = PAGE);

/* Group 15: Filtered indexes on a table whose column names overlap (issue #904)
   - id is a substring of site_id, and the finder used to match column names
     with LIKE '%' + name + '%', so a filter naming site_id also "needed" id
   - ix_fs_site: the filter names site_id, which is the key. Nothing is missing.
   - ix_fs_qty: the filter names qty and the index does not carry it. A real finding.
   - ix_fs_site_qty: both. Only qty is missing, and only qty may be reported. */
CREATE INDEX ix_fs_site ON dbo.test_ic_filt_sub (site_id) INCLUDE (qty) WHERE site_id = 1;
CREATE INDEX ix_fs_qty ON dbo.test_ic_filt_sub (site_id) WHERE qty = 5;
CREATE INDEX ix_fs_site_qty ON dbo.test_ic_filt_sub (site_id) WHERE site_id = 1 AND qty > 0;

/* Group 16: Same Keys Different Order, Rule 8 (issue #908)
   Rule 8 only checked that every key of the FIRST index is a key of the second,
   and visits each pair once with the lower index name first, so the answer
   depended on the names:
   - narrow_first: (a,b,c) sorts ahead of (a,c,b,d), passed the one-way test and
     was labelled "same keys" although the other index has an extra key column
   - wide_first: the same two indexes with the names swapped. The wide index
     sorts first, its extra column failed the one-way test, nothing was flagged
   Neither pair has the same SET of keys, so neither gets the label.
   - same_1 and same_2: positive controls. Exactly the same key set, a different
     order after the first column, once with each name order. Both are flagged. */
CREATE INDEX ix_ksn_a_abc ON dbo.test_ic_ks_narrow_first (col_a, col_b, col_c);
CREATE INDEX ix_ksn_b_acbd ON dbo.test_ic_ks_narrow_first (col_a, col_c, col_b, col_d);
CREATE INDEX ix_ksw_a_acbd ON dbo.test_ic_ks_wide_first (col_a, col_c, col_b, col_d);
CREATE INDEX ix_ksw_b_abc ON dbo.test_ic_ks_wide_first (col_a, col_b, col_c);
CREATE INDEX ix_kss1_a_abc ON dbo.test_ic_ks_same_1 (col_a, col_b, col_c);
CREATE INDEX ix_kss1_b_acb ON dbo.test_ic_ks_same_1 (col_a, col_c, col_b);
CREATE INDEX ix_kss2_a_acb ON dbo.test_ic_ks_same_2 (col_a, col_c, col_b);
CREATE INDEX ix_kss2_b_abc ON dbo.test_ic_ks_same_2 (col_a, col_b, col_c);

/* Group 12: Rule interactions */
/* 12a: Multi-level subset: A ⊂ AB ⊂ ABC */
CREATE INDEX ix_int_a ON dbo.test_ic_interact (col_a);
CREATE INDEX ix_int_ab ON dbo.test_ic_interact (col_a, col_b);
CREATE INDEX ix_int_abc ON dbo.test_ic_interact (col_a, col_b, col_c);

/* 12b: UC exact match AND UC superset on same table */
/*
This group is the one shape where three rules meet, and every piece of it is
load-bearing:

  uq_int_cd   the unique CONSTRAINT that Rule 7.5 wants to replace
  ix_int_cd   a key duplicate of it, with its own include
  ix_int_cd2  a SECOND key duplicate with a DIFFERENT include, which is what
              routes the winner through Rule 7.6 at all
  ix_int_c    a key SUBSET carrying an include of its own

Rule 6 merges ix_int_c's col_b into the winner as a Key Subset. Rule 7.5 then
rewrites that same row to MAKE UNIQUE. Rule 7.6 recomputes the winner's includes,
and if it gathers only Key Duplicate losers it silently drops col_b while
ix_int_c's DISABLE still runs - a covering column gone, on scripts that all
execute cleanly, which the execute check cannot see.

Drop ix_int_cd2 and the interaction stops firing: with one duplicate there is no
7.6 pass to lose anything. That is why a fixture without it looked healthy.
*/
ALTER TABLE dbo.test_ic_interact ADD CONSTRAINT uq_int_cd UNIQUE (col_c, col_d);
CREATE INDEX ix_int_cd ON dbo.test_ic_interact (col_c, col_d) INCLUDE (col_e);
CREATE INDEX ix_int_cd2 ON dbo.test_ic_interact (col_c, col_d) INCLUDE (col_a);
CREATE INDEX ix_int_c ON dbo.test_ic_interact (col_c) INCLUDE (col_b);

/* Group 13: @min_reads filter — run separately in Python */
GO

/* ============================================= */
/* Generate usage stats                          */
/* ============================================= */
DECLARE @c bigint, @i integer = 0;
WHILE @i < 10
BEGIN
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_uc WITH (INDEX = uq_uc_abc) WHERE col_a = 1;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_uc WITH (INDEX = ix_uc_ab) WHERE col_a = 1;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_uc WITH (INDEX = ix_uc_ab_inc) WHERE col_a = 1;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_uc WITH (INDEX = ix_uc_bc) WHERE col_b = 1;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_uc WITH (INDEX = uix_uc_acd) WHERE col_a = 1;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_uc WITH (INDEX = ix_uc_ac) WHERE col_a = 1;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_uc WITH (INDEX = uq_uc_ad) WHERE col_a = 1;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_basic WITH (INDEX = ix_sort_a_desc) WHERE col_a > 500;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_basic WITH (INDEX = ix_sort_a_desc2) WHERE col_a > 600;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_basic WITH (INDEX = ix_sort_a_asc) WHERE col_a < 100;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_basic WITH (INDEX = ix_sort_ab_asc) WHERE col_a = 1;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_basic WITH (INDEX = ix_sort_ab_mixed) WHERE col_a = 2;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_filtered WITH (INDEX = ix_filt_a_s1) WHERE col_a > 500 AND status_code = 1;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_filtered WITH (INDEX = ix_filt_a_s1_dup) WHERE col_a > 600 AND status_code = 1;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_filtered WITH (INDEX = ix_filt_a_s2) WHERE col_a > 500 AND status_code = 2;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_filtered WITH (INDEX = ix_filt_ab_s3) WHERE col_a = 1 AND status_code = 3;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_filtered WITH (INDEX = ix_filt_a_s3) WHERE col_a = 2 AND status_code = 3;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_filtered WITH (INDEX = ix_filt_ab_s4) WHERE col_a = 1 AND status_code = 4;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_filtered WITH (INDEX = ix_filt_a_s0) WHERE col_a = 1 AND status_code = 0;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_basic WITH (INDEX = ix_inc_f_inc_b) WHERE col_f > '2020-01-01';
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_basic WITH (INDEX = ix_inc_f_inc_c) WHERE col_f > '2021-01-01';
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_basic WITH (INDEX = ix_inc_cd_inc_e) WHERE col_c = 1 AND col_d = 1;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_basic WITH (INDEX = ix_inc_c_inc_b) WHERE col_c = 2;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_view WITH (INDEX = ix_view_a, NOEXPAND) WHERE col_a = 1;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_view WITH (INDEX = ix_view_a_dup, NOEXPAND) WHERE col_a = 2;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_heap WITH (INDEX = ix_heap_a) WHERE col_a = 1;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_heap WITH (INDEX = ix_heap_a_dup) WHERE col_a = 2;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_multi WITH (INDEX = ix_multi_a) WHERE col_a = 1;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_basic WITH (INDEX = ix_basic_col_d) WHERE col_d = 1;
    /* Group 8: Exact duplicates */
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_exact WITH (INDEX = ix_exact_ab_1) WHERE col_a = 1;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_exact WITH (INDEX = ix_exact_ab_2) WHERE col_a = 2;
    /* Group 9: Reverse duplicates */
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_reverse WITH (INDEX = ix_rev_ab) WHERE col_a = 1;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_reverse WITH (INDEX = ix_rev_ba) WHERE col_b = 1;
    /* Group 10: Equal except filter */
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_filter_eq WITH (INDEX = ix_feq_a) WHERE col_a = 1;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_filter_eq WITH (INDEX = ix_feq_a_filt) WHERE col_a = 1 AND status_code = 1;
    /* Group 11: UC replacement */
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_uc_replace WITH (INDEX = uq_ucr_ab) WHERE col_a = 1;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_uc_replace WITH (INDEX = ix_ucr_ab_inc) WHERE col_a = 1;
    /* Group 11b: UC-vs-UC duplicates */
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_uc_dup WITH (INDEX = uq_ucd_keeper) WHERE col_a = 1;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_uc_dup WITH (INDEX = uq_ucd_zloser) WHERE col_a = 1;
    /* Group 13: FK-backed unique index */
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_fk_parent WITH (INDEX = ux_fkp_z_code) WHERE code = 1;
    /* Group 17: IGNORE_DUP_KEY */
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_idk_pair WITH (INDEX = ux_idkp_a_strict) WHERE code = 1;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_idk_pair WITH (INDEX = ux_idkp_z_skip) WHERE code = 1;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_idk_fk WITH (INDEX = ux_idkf_strict) WHERE code = 1;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_idk_fk WITH (INDEX = ux_idkf_skip) WHERE code = 1;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_idk_rule7 WITH (INDEX = uq_idk7_skip) WHERE code = 1;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_idk_rule7 WITH (INDEX = ux_idk7_strict) WHERE code = 1;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_idk_con WITH (INDEX = uq_idkc_a_key) WHERE code = 1;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_idk_con WITH (INDEX = uq_idkc_z_skip) WHERE code = 1;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_fk_parent WITH (INDEX = ux_fkp_a_code) WHERE code = 1;
    /* Group 14: unique constraint with no sibling */
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_uc_solo WITH (INDEX = uq_ucs_code) WHERE code = 1;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_uc_pair WITH (INDEX = uq_ucp_keeper) WHERE code = 1;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_uc_pair WITH (INDEX = uq_ucp_zloser) WHERE code = 1;
    /* Group 15: filtered indexes, overlapping column names */
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_filt_sub WITH (INDEX = ix_fs_site) WHERE site_id = 1;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_filt_sub WITH (INDEX = ix_fs_qty) WHERE site_id = 1 AND qty = 5;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_filt_sub WITH (INDEX = ix_fs_site_qty) WHERE site_id = 1 AND qty > 0;
    /* Group 16: Same Keys Different Order */
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_ks_narrow_first WITH (INDEX = ix_ksn_a_abc) WHERE col_a = 1;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_ks_narrow_first WITH (INDEX = ix_ksn_b_acbd) WHERE col_a = 1;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_ks_wide_first WITH (INDEX = ix_ksw_a_acbd) WHERE col_a = 1;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_ks_wide_first WITH (INDEX = ix_ksw_b_abc) WHERE col_a = 1;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_ks_same_1 WITH (INDEX = ix_kss1_a_abc) WHERE col_a = 1;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_ks_same_1 WITH (INDEX = ix_kss1_b_acb) WHERE col_a = 1;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_ks_same_2 WITH (INDEX = ix_kss2_a_acb) WHERE col_a = 1;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_ks_same_2 WITH (INDEX = ix_kss2_b_abc) WHERE col_a = 1;
    /* Group 12: Interactions */
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_interact WITH (INDEX = ix_int_a) WHERE col_a = 1;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_interact WITH (INDEX = ix_int_ab) WHERE col_a = 1;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_interact WITH (INDEX = ix_int_abc) WHERE col_a = 1;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_interact WITH (INDEX = uq_int_cd) WHERE col_c = 1;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_interact WITH (INDEX = ix_int_cd) WHERE col_c = 1;
    SELECT @c = COUNT_BIG(*) FROM dbo.test_ic_interact WITH (INDEX = ix_int_c) WHERE col_c = 1;
    SELECT @i += 1;
END;
GO

/* ============================================= */
/* Run sp_IndexCleanup                           */
/* ============================================= */
EXECUTE dbo.sp_IndexCleanup
    @database_name = N'StackOverflow2013',
    @dedupe_only = 1;
GO

/* ============================================= */
/* Cleanup                                       */
/* ============================================= */
IF OBJECT_ID('dbo.test_ic_view') IS NOT NULL
BEGIN
    DROP INDEX ix_view_a ON dbo.test_ic_view;
    DROP INDEX ix_view_a_dup ON dbo.test_ic_view;
    DROP INDEX cx_test_ic_view ON dbo.test_ic_view;
END;
GO
IF OBJECT_ID('dbo.test_ic_view') IS NOT NULL DROP VIEW dbo.test_ic_view;
GO
DROP TABLE IF EXISTS dbo.test_ic_basic;
DROP TABLE IF EXISTS dbo.test_ic_uc;
DROP TABLE IF EXISTS dbo.test_ic_filtered;
DROP TABLE IF EXISTS dbo.test_ic_heap;
DROP TABLE IF EXISTS dbo.test_ic_multi;
DROP TABLE IF EXISTS dbo.test_ic_view_base;
DROP TABLE IF EXISTS dbo.test_ic_exact;
DROP TABLE IF EXISTS dbo.test_ic_reverse;
DROP TABLE IF EXISTS dbo.test_ic_filter_eq;
DROP TABLE IF EXISTS dbo.test_ic_uc_replace;
DROP TABLE IF EXISTS dbo.test_ic_uc_dup;
DROP TABLE IF EXISTS dbo.test_ic_interact;
DROP TABLE IF EXISTS dbo.test_ic_fk_child;
DROP TABLE IF EXISTS dbo.test_ic_fk_parent;
DROP TABLE IF EXISTS dbo.test_ic_uc_solo;
DROP TABLE IF EXISTS dbo.test_ic_uc_pair;
DROP TABLE IF EXISTS dbo.test_ic_filt_sub;
DROP TABLE IF EXISTS dbo.test_ic_ks_narrow_first;
DROP TABLE IF EXISTS dbo.test_ic_ks_wide_first;
DROP TABLE IF EXISTS dbo.test_ic_ks_same_1;
DROP TABLE IF EXISTS dbo.test_ic_ks_same_2;
GO
