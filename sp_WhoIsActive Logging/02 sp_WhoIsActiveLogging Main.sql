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

/*

Copyright 2024 Darling Data, LLC
https://www.erikdarling.com/

This will log sp_WhoIsActive to a table.
It will create a new table every day to do this,
so you don't have a gigantic table to sift through
forever and ever, or until your drive fills up.

If you need to get or update sp_WhoIsActive:
https://github.com/amachanic/sp_whoisactive
(C) 2007-2024, Adam Machanic

If you get an error message that @get_memory_info
isn't a valid parameter, that's a pretty good
sign that you need to update sp_WhoIsActive

*/

IF OBJECT_ID('dbo.sp_WhoIsActiveLogging_Main') IS NULL   
   BEGIN   
       EXEC ('CREATE PROCEDURE dbo.sp_WhoIsActiveLogging_Main AS RETURN 138;');   
   END;   
GO 

ALTER PROCEDURE
    dbo.sp_WhoIsActiveLogging_Main
(
    @RetentionPeriod int = 10
)
AS
BEGIN
    /*
    SQL Agent has some weird settings.
    This sets them to the correct ones.
    */
    SET
        NOCOUNT,
        XACT_ABORT,
        ANSI_NULLS,
        ANSI_PADDING,
        ANSI_WARNINGS,
        ARITHABORT,
        CONCAT_NULL_YIELDS_NULL,
        QUOTED_IDENTIFIER
    ON;

    SET NUMERIC_ROUNDABORT OFF;

    /*
    Variables we know and love.

    If you have weird date settings you might need to change the replace character below.
    */
    DECLARE
        @destination_table sysname =
            N'WhoIsActive_' +
            REPLACE
            (
                CONVERT
                (
                    date,
                    GETDATE()
                ),
                N'-',
                N''
            ),
        @destination_schema sysname =
            N'dbo',
        @destination_database sysname =
            N'master',
        @parameters nvarchar(MAX)  =
            N'@destination_table sysname',
        @schema nvarchar(MAX) =
            N'';

    /*
    Some assembly required
    */
    SELECT
        @destination_table =
            QUOTENAME(@destination_database) +
            N'.' +
            QUOTENAME(@destination_schema) +
            N'.' +
            QUOTENAME(@destination_table);

    /*
    Create the table for logging.
    */
    IF OBJECT_ID(@destination_table) IS NULL
    BEGIN

        EXEC dbo.sp_WhoIsActive
            @get_transaction_info = 1,
            @get_outer_command = 1,
            @get_plans = 1,
            @get_task_info = 2,
            @get_additional_info = 1,
            @find_block_leaders = 1,
            @get_memory_info = 1,
            @return_schema = 1,
            @schema = @schema OUTPUT;

        SELECT
            @schema =
                REPLACE
                (
                    @schema,
                    N'<table_name>',
                    @destination_table
                );

        EXEC sys.sp_executesql
            @schema;

    END;

    /*
    This logs to the table.
    */
    EXEC dbo.sp_WhoIsActive
        @get_transaction_info = 1,
        @get_outer_command = 1,
        @get_plans = 1,
        @get_task_info = 2,
        @get_additional_info = 1,
        @find_block_leaders = 1,
        @get_memory_info = 1,
        @destination_table = @destination_table;

    /*Execute this to prune tables*/
    EXEC dbo.sp_WhoIsActiveLogging_Retention
        @RetentionPeriod = @RetentionPeriod;
    
    /*Execute this to create views*/
    EXEC dbo.sp_WhoIsActiveLogging_CreateViews;
END;
GO
