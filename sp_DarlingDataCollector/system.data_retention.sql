SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('system.data_retention', 'P') IS NULL
BEGIN
    EXECUTE ('CREATE PROCEDURE system.data_retention AS RETURN 0;');
END;
GO

/*
/**************************************************************
* 
* Data Retention Procedure for DarlingDataCollector
* 
* Copyright (C) Darling Data, LLC
* 
* Implements automatic data retention for all collection tables
* 
**************************************************************/
*/

CREATE OR ALTER PROCEDURE
    system.data_retention
(
    @retention_days INTEGER = 30, /*Number of days to retain collected data*/
    @debug BIT = 0, /*Print debugging information*/
    @exclude_tables NVARCHAR(MAX) = NULL, /*Optional: Comma-separated list of tables to exclude*/
    @help BIT = 0 /*Prints help information*/
)
WITH RECOMPILE
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
    
    BEGIN TRY
        /*
        Variable declarations
        */
        DECLARE
            @retention_date DATETIME2(7) = DATEADD(DAY, -1 * @retention_days, SYSDATETIME()),
            @table_name NVARCHAR(512) = N'',
            @schema_name NVARCHAR(128) = N'',
            @date_column NVARCHAR(128) = N'',
            @sql NVARCHAR(MAX) = N'',
            @rows_deleted BIGINT = 0,
            @total_deleted BIGINT = 0,
            @collection_started DATETIME2(7) = SYSDATETIME(),
            @collection_ended DATETIME2(7) = NULL,
            @error_number INTEGER = 0,
            @error_severity INTEGER = 0,
            @error_state INTEGER = 0,
            @error_line INTEGER = 0,
            @error_message NVARCHAR(4000) = N'',
            @exclude_table_list TABLE
            (
                table_name NVARCHAR(512) NOT NULL
            );

        /*
        Parameter validation
        */
        IF @retention_days < 1
        BEGIN
            RAISERROR(N'Retention days must be at least 1 day', 11, 1) WITH NOWAIT;
            RETURN;
        END;
        
        /*
        Help section
        */
        IF @help = 1
        BEGIN
            SELECT
                help = N'This procedure purges data older than the specified retention period from all collection tables.
                
Parameters:
  @retention_days = Number of days of data to keep (default 30)
  @debug = 1 to print detailed information, 0 for normal operation
  @exclude_tables = Comma-separated list of tables to exclude from purging
  @help = 1 to show this help information

Example usage:
  EXECUTE system.data_retention @retention_days = 90, @debug = 1;';
            
            RETURN;
        END;
        
        /*
        Create exclude table list
        */
        IF @exclude_tables IS NOT NULL
        BEGIN
            INSERT
                @exclude_table_list
            (
                table_name
            )
            SELECT
                table_name = LTRIM(RTRIM(value)) 
            FROM STRING_SPLIT(@exclude_tables, N',');
        END;
        
        IF @debug = 1
        BEGIN
            RAISERROR(N'Data retention started at %s, keeping data newer than %s', 0, 1, @collection_started, @retention_date) WITH NOWAIT;
            
            IF EXISTS (SELECT 1 FROM @exclude_table_list)
            BEGIN
                SELECT
                    excluded_tables = table_name
                FROM @exclude_table_list;
            END;
        END;
        
        /*
        Get list of collection tables and date columns
        */
        IF OBJECT_ID('tempdb.dbo.#collection_tables') IS NOT NULL
        BEGIN
            DROP TABLE #collection_tables;
        END;
        
        CREATE TABLE
            #collection_tables
        (
            id INTEGER IDENTITY(1, 1) NOT NULL,
            schema_name NVARCHAR(128) NOT NULL,
            table_name NVARCHAR(512) NOT NULL,
            date_column NVARCHAR(128) NOT NULL,
            sql_text NVARCHAR(MAX) NOT NULL
        );
        
        /*
        Identify all tables in collection schema with date columns
        */
        INSERT
            #collection_tables
        (
            schema_name,
            table_name,
            date_column,
            sql_text
        )
        SELECT
            schema_name = s.name,
            table_name = t.name,
            date_column = c.name,
            sql_text = N'DELETE ' + QUOTENAME(s.name) + N'.' + QUOTENAME(t.name) + 
                       N' WHERE ' + QUOTENAME(c.name) + N' < @retention_date;'
        FROM sys.tables AS t
        JOIN sys.schemas AS s
          ON t.schema_id = s.schema_id
        JOIN sys.columns AS c
          ON t.object_id = c.object_id
        JOIN sys.types AS ty
          ON c.system_type_id = ty.system_type_id
        WHERE s.name = N'collection'
        AND   ty.name IN (N'date', N'datetime', N'datetime2', N'datetimeoffset', N'smalldatetime')
        AND   c.name LIKE N'%date%'
        AND   t.name NOT IN (SELECT table_name FROM @exclude_table_list)
        ORDER BY
            s.name,
            t.name;
            
        IF @debug = 1
        BEGIN
            SELECT
                tables_found = COUNT(*)
            FROM #collection_tables;
            
            IF NOT EXISTS (SELECT 1 FROM #collection_tables)
            BEGIN
                RAISERROR(N'No collection tables with date columns were found', 0, 1) WITH NOWAIT;
                RETURN;
            END;
        END;
        
        /*
        Loop through tables and delete data
        */
        DECLARE
            table_cursor CURSOR LOCAL FORWARD_ONLY STATIC READ_ONLY
        FOR
            SELECT
                schema_name,
                table_name,
                date_column,
                sql_text
            FROM #collection_tables
            ORDER BY
                id;
                
        OPEN table_cursor;
        
        FETCH NEXT FROM
            table_cursor
        INTO
            @schema_name,
            @table_name,
            @date_column,
            @sql;
            
        WHILE @@FETCH_STATUS = 0
        BEGIN
            BEGIN TRANSACTION;

            IF @debug = 1
            BEGIN
                RAISERROR(N'Processing %s.%s using date column %s', 0, 1, @schema_name, @table_name, @date_column) WITH NOWAIT;
                RAISERROR(N'Executing: %s', 0, 1, @sql) WITH NOWAIT;
            END;
            
            BEGIN TRY
                EXECUTE sys.sp_executesql
                    @sql,
                    N'@retention_date DATETIME2(7)',
                    @retention_date;
                    
                SET @rows_deleted = ROWCOUNT_BIG();
                SET @total_deleted = @total_deleted + @rows_deleted;
                
                IF @debug = 1
                BEGIN
                    RAISERROR(N'Deleted %I64d rows from %s.%s', 0, 1, @rows_deleted, @schema_name, @table_name) WITH NOWAIT;
                END;
                
                COMMIT TRANSACTION;
            END TRY
            BEGIN CATCH
                IF @@TRANCOUNT > 0
                BEGIN
                    ROLLBACK TRANSACTION;
                END;
                
                SET @error_number = ERROR_NUMBER();
                SET @error_severity = ERROR_SEVERITY();
                SET @error_state = ERROR_STATE();
                SET @error_line = ERROR_LINE();
                SET @error_message = ERROR_MESSAGE();
                
                RAISERROR(N'Error processing %s.%s: Error %d at line %d - %s', 11, 1, 
                    @schema_name, @table_name, @error_number, @error_line, @error_message) WITH NOWAIT;
            END CATCH;
            
            FETCH NEXT FROM
                table_cursor
            INTO
                @schema_name,
                @table_name,
                @date_column,
                @sql;
        END;
        
        CLOSE table_cursor;
        DEALLOCATE table_cursor;
        
        SET @collection_ended = SYSDATETIME();
        
        IF @debug = 1
        BEGIN
            RAISERROR(N'Data retention completed at %s', 0, 1, @collection_ended) WITH NOWAIT;
            RAISERROR(N'Total rows deleted: %I64d', 0, 1, @total_deleted) WITH NOWAIT;
            RAISERROR(N'Execution time: %d seconds', 0, 1, DATEDIFF(SECOND, @collection_started, @collection_ended)) WITH NOWAIT;
        END;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
        BEGIN
            ROLLBACK TRANSACTION;
        END;
        
        SET @error_number = ERROR_NUMBER();
        SET @error_severity = ERROR_SEVERITY();
        SET @error_state = ERROR_STATE();
        SET @error_line = ERROR_LINE();
        SET @error_message = ERROR_MESSAGE();
        
        RAISERROR(N'Error %d at line %d: %s', 11, 1, @error_number, @error_line, @error_message) WITH NOWAIT;
        THROW;
    END CATCH;
END;
GO