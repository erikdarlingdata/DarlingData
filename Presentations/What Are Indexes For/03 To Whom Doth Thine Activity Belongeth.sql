/*Hi Adam!*/
EXEC sp_WhoIsActive
    @get_locks = 1,
    @get_plans = 1;