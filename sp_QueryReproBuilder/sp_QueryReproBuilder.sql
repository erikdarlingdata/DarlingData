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


CREATE OR ALTER PROCEDURE
    dbo.sp_QueryReproBuilder
(
    @database_name sysname = NULL, /*the name of the database you want to look at query store in*/
    @include_plan_ids nvarchar(4000) = NULL, /*a list of query ids to search for*/
    @include_query_ids nvarchar(4000) = NULL, /*a list of plan ids to search for*/
    @ignore_plan_ids nvarchar(4000) = NULL, /*a list of plan ids to ignore*/
    @ignore_query_ids nvarchar(4000) = NULL, /*a list of query ids to ignore*/    
    @procedure_schema sysname = NULL, /*the schema of the procedure you're searching for*/
    @procedure_name sysname = NULL, /*the name of the programmable object you're searching for*/
    @query_text_search nvarchar(4000) = NULL, /*query text to search for*/
    @query_text_search_not nvarchar(4000) = NULL, /*query text to exclude*/    
    @help bit = 0, /*return available parameter details, etc.*/
    @debug bit = 0, /*prints dynamic sql, statement length, parameter and variable values, and raw temp table contents*/
    @version varchar(30) = NULL OUTPUT, /*OUTPUT; for support*/
    @version_date datetime = NULL OUTPUT /*OUTPUT; for support*/
)
WITH 
    RECOMPILE
AS
BEGIN
SET STATISTICS XML OFF;
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

BEGIN TRY

/*Version*/
SELECT
    @version = '0',
    @version_date = '20251001';

/*Help*/
IF @help = 1
BEGIN
    SELECT
        x = 'be helpful'
END;

/*Variables*/
DECLARE
    @sql nvarchar(MAX) = N'',
    @database_name_quoted sysname =
        QUOTENAME(@database_name),
    @query_store_exists bit = 'true'

/*Fix NULL @database_name*/
IF
  (
      @database_name IS NULL
      AND LOWER(DB_NAME())
          NOT IN
          (
              N'master',
              N'model',
              N'msdb',
              N'tempdb',
              N'dbatools',
              N'dbadmin',
              N'dbmaintenance',
              N'rdsadmin',
              N'other_memes'
          )
  )
BEGIN
    SELECT
        @database_name =
            DB_NAME();
END;


/*Check database state*/
SELECT
    @sql += N'
SELECT
    @query_store_exists =
        CASE
            WHEN EXISTS
                 (
                     SELECT
                         1/0
                     FROM ' + @database_name_quoted + N'.sys.database_query_store_options AS dqso
                     WHERE
                     (
                          dqso.actual_state = 0
                       OR dqso.actual_state IS NULL
                     )
                 )
            OR   NOT EXISTS
                 (
                     SELECT
                         1/0
                     FROM ' + @database_name_quoted + N'.sys.database_query_store_options AS dqso
                 )
            THEN 0
            ELSE 1
        END
OPTION(RECOMPILE);
';

EXECUTE sys.sp_executesql
    @sql,
  N'@query_store_exists bit OUTPUT',
    @query_store_exists OUTPUT;

IF @query_store_exists = 0
BEGIN
    RAISERROR('Query Store doesn''t seem to be enabled for database: %s', 10, 1, @database_name) WITH NOWAIT;
END;





END TRY

BEGIN CATCH
    SELECT x = 1
END CATCH 



END; /*Final end*/