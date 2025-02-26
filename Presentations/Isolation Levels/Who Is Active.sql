/*This is good enough for our demos*/
EXEC dbo.sp_WhoIsActive
    @get_plans = 1,
    @get_locks = 1;


/*You might find this useful*/
EXEC dbo.sp_WhoIsActive
    @get_task_info = 2,
    @get_additional_info = 1;


/*You might this find even more useful*/
EXEC dbo.sp_WhoIsActive
    @get_transaction_info = 1,
    @get_outer_command = 1,
    @get_plans = 1,
    @get_task_info = 2,
    @get_additional_info = 1,
    @find_block_leaders = 1,
    @sort_order = '[blocked_session_count] DESC';
