USE StackOverflow2013;
GO
/*Turn on query plans*/


    /*Not blocked*/
    SELECT
        b.*
    FROM dbo.Badges AS b
    WHERE b.Id = 82946;
    GO

    /*Immediately blocked?*/
    SELECT
        b.*
    FROM dbo.Badges AS b
    WHERE b.Id = 1317729;
    GO 