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

/*The default is finding the top 10 sorted by CPU in the last seven days.*/
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013';

/*Find top 10 sorted by memory*/
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @sort_order = 'memory',
    @top = 10;

/*Find top 10 in each user database sorted by cpu*/
EXEC dbo.sp_QuickieStore
    @get_all_databases = 1,
    @sort_order = 'cpu',
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

/*Filter out weekends and anything outside of your choice of hours.*/
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @workdays = 1,
    @work_start = '8am',
    @work_end = '6pm'


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


/*Use wait filter to search for queries responsible for high waits*/
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @wait_filter = 'memory',
    @sort_order = 'memory';

/*We also support using wait types as a sort order, see the documentation for the full list.
The wait-related sort orders are special because we add an extra column for the duration of the wait type you are asking for.
It's all the way over on the right.
*/
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @sort_order = 'memory waits';

/*You can also sort by total wait time across all waits. */
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @sort_order = 'total waits';


/*Search for queries with a specific execution type
When we do not provide this parameter, we grab all types.
This example grabs "aborted" queries, which are queries cancelled by the client.
This is a great way to find timeouts.
*/
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @top = 10,
    @execution_type_desc = 'aborted';

/*Search for queries that errored
As above, but for "exception" queries.
This grabs queries that were cancelled by throwing exceptions.
It's no substitute for proper error monitoring, but it can be a good early warning.
*/
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @top = 10,
    @execution_type_desc = 'exception';

/*Search for queries that finished normally
As above, but for "regular" queries.
This grabs queries that were not cancelled.
*/
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @top = 10,
    @execution_type_desc = 'regular';


/*Search for a specific stored procedure*/
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @procedure_name = 'top_percent_sniffer';

/*Search for a specific stored procedure in a specific schema*/
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @procedure_schema = 'not_dbo'
    @procedure_name = 'top_percent_sniffer';

/*Search for specific query text*/
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @query_text_search = 'WITH Comment'

/*Search for specific query text, with brackets automatically escaped.
Commonly needed when dealing with ORM queries.
*/
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @query_text_search = 'FROM [users] AS [t0]',
    @escape_brackets = 1;

/*By default, We use '\' to escape when @escape_brackets = 1 is set.
Maybe you want something else.
Provide it with @escape_character.
*/
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @query_text_search = 'FROM foo\bar AS [t0]',
    @escape_character = '~'
    @escape_brackets = 1;


/*Find every reference to a particular table in your Query Store data, sorted by their execution counts.
Quite expensive!
Handy when tuning or finding dependencies, but only as good as what your Query Store has captured.
Makes use of @get_all_databases = 1, which lets you search all user databases.
Note the abuse of @start_date. By setting it very far back in the past and leaving @end_date unspecified, we cover all of the data.
We also abuse @top by setting it very high.
*/
EXEC dbo.sp_QuickieStore
    @get_all_databases = 1,
    @start_date = '20000101',
    @sort_order = 'executions',
    @query_text_search = 'MyTable',
    @top = 100;

/*Filter out certain query text with @query_text_search_not.
Good for when @query_text_search gets false positives.
After all, it's only doing string searching.
*/
EXEC dbo.sp_QuickieStore
    @get_all_databases = 1,
    @start_date = '20000101',
    @sort_order = 'executions',
    @query_text_search = 'MyTable',
    @query_text_search_not = 'MyTable_secret_backup'
    @top = 100;


/*What happened recently on a database?*/
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013'
    @sort_order = 'recent';

/*What happened recently that referenced my database?
Good for finding cross-database queries, such as when checking if a database is dead code.
Don't forget that queries in a database do not need to reference it explicitly!
*/
EXEC dbo.sp_QuickieStore
    @get_all_databases = 1,
    @start_date = '20000101',
    @sort_order = 'recent',
    @query_text_search = 'StackOverflow2013'
    @top = 10;

/*Only return queries with feedback (2022+)*/
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @only_query_with_feedback = 1;

/*Only return queries with variants (2022+)*/
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @only_query_with_variants = 1;

/*Only return queries with forced plans (2022+)*/
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @only_query_with_forced_plans = 1;

/*Only return queries with forced plan failures (2022+)*/
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @only_query_with_forced_plan_failures = 1;

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


/*Use format output to add commas to larger numbers
This is enabled by default.
*/
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @sort_order = 'memory',
    @top = 10,
    @format_output = 1;

/*Disable format output to remove commas.*/
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @sort_order = 'memory',
    @top = 10,
    @format_output = 0;

/*Change the timezone show in your outputs.
This is only an output-formatting change.
It does not change how dates are processed.
*/
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @timezone = 'Egypt Standard Time';

/*Debugging something complex?
Hide the bottom table with @hide_help_table = 1 when you need more room.
*/
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @hide_help_table = 1,
    @sort_order = 'latch waits',
    @top = 50;

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

/*Search, but ignoring some query hashes*/
EXEC dbo.sp_QuickieStore
    @ignore_query_hashes = '0x1AB614B461F4D769,0x1CD777B461F4D769';

/*Search, but ignoring some plan hashes*/
EXEC dbo.sp_QuickieStore
    @ignore_plan_hashes = '0x6B84B820B8B38564,0x6B84B999D7B38564';

/*Search, but ignoring some SQL Handles*/
EXEC dbo.sp_QuickieStore
    @ignore_sql_handles = 
        '0x0900F46AC89E66DF744C8A0AD4FD3D3306B90000000000000000000000000000000000000000000000000000,0x0200000AC89E66DF744C8A0AD4FD3D3306B90000000000000000000000000000000000000000000000000000';

/*What query hashes have the most plans?
This sort order is special because it needs to return multiple rows for each of the @top hashes it looks at.
It is also special because it adds some new columns all the way over on the right of the output.
*/
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @sort_order = 'plan count by hashes';

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

/*Get version info.*/
DECLARE @version_output varchar(30),
        @version_date_output datetime;

EXEC sp_QuickieStore 
    @version = @version_output OUTPUT, 
    @version_date = @version_date_output OUTPUT;

SELECT
    Version = @version_output,
    VersionDate = @version_date_output;

/*Troubleshoot performance*/
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @troubleshoot_performance = 1;

/*Debug dynamic SQL and temp table contents*/
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @debug = 1;
