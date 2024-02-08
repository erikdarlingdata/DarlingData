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

/*Troubleshoot performance*/
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @troubleshoot_performance = 1;


/*Debug dynamic SQL and temp table contents*/
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @debug = 1;
