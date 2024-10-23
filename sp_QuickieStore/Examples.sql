/*
███████╗██╗  ██╗ █████╗ ███╗   ███╗██████╗ ██╗     ███████╗
██╔════╝╚██╗██╔╝██╔══██╗████╗ ████║██╔══██╗██║     ██╔════╝
█████╗   ╚███╔╝ ███████║██╔████╔██║██████╔╝██║     █████╗  
██╔══╝   ██╔██╗ ██╔══██║██║╚██╔╝██║██╔═══╝ ██║     ██╔══╝  
███████╗██╔╝ ██╗██║  ██║██║ ╚═╝ ██║██║     ███████╗███████╗
╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝╚═╝     ╚══════╝╚══════╝
                                                           
 ██████╗ █████╗ ██╗     ██╗     ███████╗                   
██╔════╝██╔══██╗██║     ██║     ██╔════╝                   
██║     ███████║██║     ██║     ███████╗                   
██║     ██╔══██║██║     ██║     ╚════██║                   
╚██████╗██║  ██║███████╗███████╗███████║                   
 ╚═════╝╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝

Copyright 2024 Darling Data, LLC
https://www.erikdarling.com/

For support, head over to GitHub:
https://github.com/erikdarlingdata/DarlingData
*/

/*Get help!*/
EXEC dbo.sp_QuickieStore
    @help = 1;


/*Find top 10 sorted by memory*/
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @sort_order = 'memory',
    @top = 10;              


/*Search for specific query_ids*/
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @top = 10,
    @include_query_ids = '13977, 13978';    


/*Search for specific plan_ids*/
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @sort_order = 'memory',
    @top = 10,
    @start_date = '20210320',
    @include_plan_ids = '1896, 1897';

    
/*Ignore for specific query_ids*/
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @top = 10,
    @ignore_query_ids = '13977, 13978';    


/*Ignore for specific plan_ids*/
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @sort_order = 'memory',
    @top = 10,
    @start_date = '20210320',
    @ignore_plan_ids = '1896, 1897'; 


/*Search for queries within a date range*/
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @sort_order = 'memory',
    @top = 10,
    @start_date = '20210320',
    @end_date = '20210321';              


/*Search for queries with a minimum execution count*/
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @top = 10,
    @execution_count = 10;


/*Search for queries over a specific duration*/
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @top = 10,
    @duration_ms = 10000;

/*Search for queries with a specific execution type*/
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @top = 10,
    @execution_type_desc = 'aborted';

/*Search for a specific stored procedure*/
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @procedure_name = 'top_percent_sniffer';   


/*Search for specific query text*/
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @query_text_search = 'WITH Comment'

/*Only return queries with query hints (2022+)*/
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @only_query_with_hints = 1;

/*Use expert mode to return additional columns*/
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @sort_order = 'memory',
    @top = 10,
    @expert_mode = 1;              


/*Use format output to add commas to larger numbers*/
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @sort_order = 'memory',
    @top = 10,
    @format_output = 1;


/*Use wait filter to search for queries responsible for high waits*/
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @wait_filter = 'memory',
    @sort_order = 'memory';

/*Search by query hashes*/
EXEC dbo.sp_QuickieStore
    @include_query_hashes = '0x1AB614B461F4D769,0x1CD777B461F4D769';

/*Search by plan hashes*/
EXEC dbo.sp_QuickieStore
    @include_plan_hashes = '0x6B84B820B8B38564,0x6B84B999D7B38564';

/*Search by SQL Handles 
Do you need to find if one Query Store is tracking the same query that is present in another database's Query Store? If so, use the statement_sql_handle to do that.
This helps with scenarios where you have multiple production databases which have the same schema and you want to compare performance across Query Stores.
*/
EXEC dbo.sp_QuickieStore
    @include_sql_handles = 
        '0x0900F46AC89E66DF744C8A0AD4FD3D3306B90000000000000000000000000000000000000000000000000000,0x0200000AC89E66DF744C8A0AD4FD3D3306B90000000000000000000000000000000000000000000000000000';

/*Check for regressions.
Specifically, this checks for queries that did more logical reads last week than this week.
The default dates are helpful here. The default @start_date and @end_date specify last week for us and @regression_baseline_end_date defaults to being one week after @regression_baseline_start_date.
However, we need to specify @regression_baseline_start_date so that sp_QuickieStore knows to check for regressions.
Searches by query hash, so you will won't be caught out by identical queries with different query ids.
*/
DECLARE @TwoWeekAgo datetimeoffset(7) = DATEADD(WEEK, -2, SYSDATETIMEOFFSET());

EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @sort_order = 'logical reads',
    @regression_baseline_start_date = @TwoWeekAgo;

/*Check for improved queries.
I deleted some indexes yesterday.
Let's see what's doing less writes today.
Since we're checking for improvements rather than regressions, we use @regression_direction = 'improved'.
This is a good chance to point out that the @end_date parameters do comparisons with < rather than <=.
The @start_data parameters, of course, use >=.
*/
DECLARE @StartOfYesterday datetimeoffset(7) = CONVERT(date, DATEADD(DAY, -1, SYSDATETIMEOFFSET())),
        @StartOfToday datetimeoffset(7) = CONVERT(date, SYSDATETIMEOFFSET()),
        @StartOfTomorrow datetimeoffset(7) = CONVERT(date, DATEADD(DAY, 1, SYSDATETIMEOFFSET()));

EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @sort_order = 'writes',
    @regression_direction = 'improved',
    @regression_baseline_start_date = @StartOfYesterday,
    @regression_baseline_end_date = @StartOfToday,
    @start_date = @StartOfToday,
    @end_date = @StartOfTomorrow;

/*Check for percentage changes in performance.
By default, our @regression parameters have us check for changes in the raw numbers.
It's just plain subtraction: new minus old.
This means that a query that used to read hardly anything from disk but now reads triple that is indistinguishable from the noise in a query that reads lots.
To get percentage changes instead, specify @regression_comparator = 'relative'.
The default is @regression_comparator = 'absolute'.

To see the difference, run `sp_QuickieStore` twice.
To save space on your screen, we will specify @hide_help_table = 1 to hide the table normally at the bottom of the normal output.
*/
DECLARE @TwoWeekAgo datetimeoffset(7) = DATEADD(WEEK, -2, SYSDATETIMEOFFSET());

EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @sort_order = 'physical reads',
    @hide_help_table = 1,
    @regression_comparator = 'relative',
    @regression_baseline_start_date = @TwoWeekAgo;

EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @sort_order = 'physical reads',
    @hide_help_table = 1,
    @regression_comparator = 'absolute',
    @regression_baseline_start_date = @TwoWeekAgo;

/*Check for changes in modulus.
What if you're looking for sheer size of changes, rather than the direction of the change?
For example, you might care about a 30 second reduction in duration just as much as a 30 second increase.
Use @regression_direction = 'absolute'.
And while we're at it, let's check all user databases with @get_all_databases = 1.
*/
DECLARE @TwoWeekAgo datetimeoffset(7) = DATEADD(WEEK, -2, SYSDATETIMEOFFSET());

EXEC dbo.sp_QuickieStore
    @get_all_databases = 1,
    @sort_order = 'duration',
    @regression_direction = 'absolute',
    @regression_baseline_start_date = @TwoWeekAgo;


/*Troubleshoot performance*/
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @troubleshoot_performance = 1;


/*Debug dynamic SQL and temp table contents*/
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @debug = 1;
