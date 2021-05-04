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
*/

--Get help!
EXEC dbo.sp_QuickieStore
    @help = 1;


--Find top 10 sorted by memory 
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @sort_order = 'memory',
    @top = 10;              


--Search for specific query_ids
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @top = 10,
    @include_query_ids = '13977, 13978';    


--Search for specific plan_ids
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @sort_order = 'memory',
    @top = 10,
    @start_date = '20210320',
    @include_plan_ids = '1896, 1897';

    
--Ignore for specific query_ids
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @top = 10,
    @ignore_query_ids = '13977, 13978';    


--Ignore for specific plan_ids
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @sort_order = 'memory',
    @top = 10,
    @start_date = '20210320',
    @ignore_plan_ids = '1896, 1897'; 


--Search for queries within a date range
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @sort_order = 'memory',
    @top = 10,
    @start_date = '20210320',
    @end_date = '20210321';              


--Search for queries with a minimum execution count
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @top = 10,
    @execution_count = 10;


--Search for queries over a specific duration
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @top = 10,
    @duration_ms = 10000;


--Search for a specific stored procedure
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @procedure_name = 'top_percent_sniffer';   


--Search for specific query tex
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @query_text_search = 'WITH Comment'


--Use expert mode to return additional columns
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @sort_order = 'memory',
    @top = 10,
    @expert_mode = 1;              


--Use format output to add commas to larger numbers
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @sort_order = 'memory',
    @top = 10,
    @format_output = 1;


--Troubleshoot performance
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @troubleshoot_performance = 1;


--Debug dynamic SQL and temp table contents
EXEC dbo.sp_QuickieStore
    @database_name = 'StackOverflow2013',
    @debug = 1;