/*Make sure nothing weird is open*/
IF @@TRANCOUNT > 0
BEGIN
    SELECT
        tc = @@TRANCOUNT;
    ROLLBACK;
END;
