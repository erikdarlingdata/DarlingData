USE StackOverflow2013;
EXEC dbo.DropIndexes;
DBCC FREEPROCCACHE;
SET STATISTICS TIME, IO ON;
SET NOCOUNT ON;
GO

/*
██╗███╗   ██╗██████╗ ███████╗██╗  ██╗███████╗███████╗██╗
██║████╗  ██║██╔══██╗██╔════╝╚██╗██╔╝██╔════╝██╔════╝██║
██║██╔██╗ ██║██║  ██║█████╗   ╚███╔╝ █████╗  ███████╗██║
██║██║╚██╗██║██║  ██║██╔══╝   ██╔██╗ ██╔══╝  ╚════██║╚═╝
██║██║ ╚████║██████╔╝███████╗██╔╝ ██╗███████╗███████║██╗
╚═╝╚═╝  ╚═══╝╚═════╝ ╚══════╝╚═╝  ╚═╝╚══════╝╚══════╝╚═╝
*/








/*
     ██╗ ██████╗ ██╗███╗   ██╗███████╗
     ██║██╔═══██╗██║████╗  ██║██╔════╝
     ██║██║   ██║██║██╔██╗ ██║███████╗
██   ██║██║   ██║██║██║╚██╗██║╚════██║
╚█████╔╝╚██████╔╝██║██║ ╚████║███████║
 ╚════╝  ╚═════╝ ╚═╝╚═╝  ╚═══╝╚══════╝
*/

    /*
    Is this appropriate?

    Id column is the PK/CX...
    */
    SELECT
        records = COUNT_BIG(*)
    FROM dbo.Posts AS p
    JOIN dbo.Users AS u
      ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 500000; --This isn't many people!











    /*Forcing bad choices*/
    SELECT
        records = COUNT_BIG(*)
    FROM dbo.Posts AS p
    JOIN dbo.Users AS u
      ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 100000
    OPTION(MERGE JOIN); --This isn't many people!

    SELECT
        records = COUNT_BIG(*)
    FROM dbo.Posts AS p
    JOIN dbo.Users AS u
      ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 100000
    OPTION(LOOP JOIN); --This isn't many people!


































    /*Silly willy.*/
    CREATE INDEX
        whatever
    ON dbo.Posts
        (OwnerUserId)
    WITH
        (MAXDOP = 8, SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);


    /*
    How about now?
    */
    SELECT
        records = COUNT_BIG(*)
    FROM dbo.Posts AS p
    JOIN dbo.Users AS u
      ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 100000;








    /*
    Lessons:
     * Well, duh.
     * Indexing columns you join on is a good thing.

    Without the index, Hash was the only sensible join strategy
     * Merge would have to sort and agg by OwnerUserId
     * Nested Loops would have to do some ugly stuff, too
    */


















































/*
██╗███╗   ██╗██████╗ ███████╗██╗  ██╗
██║████╗  ██║██╔══██╗██╔════╝╚██╗██╔╝
██║██╔██╗ ██║██║  ██║█████╗   ╚███╔╝
██║██║╚██╗██║██║  ██║██╔══╝   ██╔██╗
██║██║ ╚████║██████╔╝███████╗██╔╝ ██╗
╚═╝╚═╝  ╚═══╝╚═════╝ ╚══════╝╚═╝  ╚═╝


███████╗██████╗  ██████╗  ██████╗ ██╗     ███████╗
██╔════╝██╔══██╗██╔═══██╗██╔═══██╗██║     ██╔════╝
███████╗██████╔╝██║   ██║██║   ██║██║     ███████╗
╚════██║██╔═══╝ ██║   ██║██║   ██║██║     ╚════██║
███████║██║     ╚██████╔╝╚██████╔╝███████╗███████║
╚══════╝╚═╝      ╚═════╝  ╚═════╝ ╚══════╝╚══════╝
*/




    EXEC dbo.DropIndexes;

    --38 vs 39?
    SELECT TOP (38)
        u.DisplayName,
        b.Name
    FROM dbo.Users u
    CROSS APPLY
    (
        SELECT TOP (1)
            b.Name
        FROM dbo.Badges AS b
        WHERE b.UserId = u.Id
        ORDER BY 
            b.Date DESC
    ) AS b
    WHERE u.Reputation >= 10000
    ORDER BY 
        u.Reputation DESC;


    --38 vs 39?
    SELECT TOP (39)
        u.DisplayName,
        b.Name
    FROM dbo.Users u
    CROSS APPLY
    (
        SELECT TOP (1)
            b.Name
        FROM dbo.Badges AS b
        WHERE b.UserId = u.Id
        ORDER BY 
            b.Date DESC
    ) AS b
    WHERE u.Reputation >= 10000
    ORDER BY 
        u.Reputation DESC;



/*
The optimizer decided to create an index for us!
 * Look at scan properties
 * Time stats on the spool
 * Where's our missing index request?

How do we solve it?
 * Create our own index!

Index spool properties:
 * Seek predicate: Key Columns
 * Output List: Includes

But this isn't too smart, because we still have to sort.
 * Better index?
 * UserId, Date DESC
*/

    CREATE INDEX
        whatever
    ON dbo.Badges
        (UserId, Date)
    INCLUDE
        (Name)
    WITH
        (MAXDOP = 8, SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);
    GO

    /*Spool no more*/
    SELECT TOP (39)
        u.DisplayName,
        b.Name
    FROM dbo.Users u
    CROSS APPLY
    (
        SELECT TOP (1)
            b.Name
        FROM dbo.Badges AS b
        WHERE b.UserId = u.Id
        ORDER BY 
            b.Date DESC
    ) AS b
    WHERE u.Reputation >= 10000
    ORDER BY 
        u.Reputation DESC;






















/*
████████╗ █████╗ ██████╗ ██╗     ███████╗
╚══██╔══╝██╔══██╗██╔══██╗██║     ██╔════╝
   ██║   ███████║██████╔╝██║     █████╗
   ██║   ██╔══██║██╔══██╗██║     ██╔══╝
   ██║   ██║  ██║██████╔╝███████╗███████╗
   ╚═╝   ╚═╝  ╚═╝╚═════╝ ╚══════╝╚══════╝

███████╗██████╗  ██████╗  ██████╗ ██╗     ███████╗
██╔════╝██╔══██╗██╔═══██╗██╔═══██╗██║     ██╔════╝
███████╗██████╔╝██║   ██║██║   ██║██║     ███████╗
╚════██║██╔═══╝ ██║   ██║██║   ██║██║     ╚════██║
███████║██║     ╚██████╔╝╚██████╔╝███████╗███████║
╚══════╝╚═╝      ╚═════╝  ╚═════╝ ╚══════╝╚══════╝
*/

    EXEC dbo.DropIndexes;

    CREATE INDEX
        stinkin
    ON dbo.Badges
        (Name, UserId)
    WHERE
        Name IN (N'Popular Question')
    WITH
        (MAXDOP = 8, SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);

    CREATE INDEX
        whatever
    ON dbo.Posts
        (OwnerUserId)
    INCLUDE
        (Score, PostTypeId)
    WHERE
        PostTypeId IN (1, 2)
    WITH
        (MAXDOP = 8, SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);
    GO


    /*Spool Spool Spoolio*/
    DROP TABLE IF EXISTS
        #waypops;

    CREATE TABLE
        #waypops
    (
        UserId int NOT NULL
    );

    INSERT
        #waypops WITH(TABLOCKX)
    (
        UserId
    )
    SELECT
        b.UserId
    FROM dbo.Badges AS b
    WHERE b.Name IN (N'Popular Question');



    SELECT TOP (100000)
        wp.UserId,
        SummaTime = SUM(ca.Score)
    FROM #waypops AS wp
    CROSS APPLY
    (
        SELECT
            p.Score,
            p.OwnerUserId,
            ScoreOrder =
                ROW_NUMBER() OVER
                (
                    PARTITION BY
                        p.OwnerUserId
                    ORDER BY
                        p.Score DESC
                )
        FROM dbo.Posts AS p
        WHERE p.OwnerUserId = wp.UserId
        AND p.PostTypeId IN (1, 2)
    ) AS ca
    WHERE ca.ScoreOrder <= 50
    GROUP BY 
        wp.UserId
    ORDER BY 
        wp.UserId;


    SELECT
        w.UserId,
        records =
            COUNT_BIG(*)
    FROM #waypops AS w
    GROUP BY w.UserId
    ORDER BY records DESC;

    SELECT
        records =
            FORMAT
            (
                COUNT_BIG(DISTINCT w.UserId),
                'N0'
            )
    FROM #waypops AS w;

/*
Can you believe they call this a performance spool?!
 * 1,286,465 executions
 * 368,665 rebinds (SQL Server went to find new data)
 * 917,800 rewinds (SQL Server reused data in the spool)
 * 186,731,877 rows go through the spool from a 3,744,192 row table 🤔
 * 85MB memory grant

And this is all just dumped into tempdb!

How can we fix it?
*/






    /*Sexy Indexy*/
    DROP TABLE IF EXISTS
        #waypops;

    CREATE TABLE
        #waypops
    (
        UserId int NOT NULL
            PRIMARY KEY
            CLUSTERED  /*Let's make this unique*/
    );

    INSERT
        #waypops WITH(TABLOCKX)
    (
        UserId
    )
    SELECT DISTINCT
        b.UserId /*And not insert a bunch of duplicate IDs*/
    FROM dbo.Badges AS b
    WHERE b.Name IN (N'Popular Question');



    SELECT TOP (100000)
        wp.UserId,
        SUM(ca.Score) AS SummaTime
    FROM #waypops AS wp
    CROSS APPLY
    (
        SELECT
            p.Score,
            p.OwnerUserId,
            ScoreOrder =
               ROW_NUMBER() OVER
               (
                   PARTITION BY
                       p.OwnerUserId
                   ORDER BY
                       p.Score DESC
               )
        FROM dbo.Posts AS p
        WHERE p.OwnerUserId = wp.UserId
        AND p.PostTypeId IN (1, 2)
    ) AS ca
    WHERE ca.ScoreOrder <= 50
    GROUP BY 
        wp.UserId
    ORDER BY 
        wp.UserId;

/*
No spool!
 * 4MB memory grant
*/























/*
██████╗ ██╗      ██████╗  ██████╗██╗  ██╗██╗███╗   ██╗ ██████╗
██╔══██╗██║     ██╔═══██╗██╔════╝██║ ██╔╝██║████╗  ██║██╔════╝
██████╔╝██║     ██║   ██║██║     █████╔╝ ██║██╔██╗ ██║██║  ███╗
██╔══██╗██║     ██║   ██║██║     ██╔═██╗ ██║██║╚██╗██║██║   ██║
██████╔╝███████╗╚██████╔╝╚██████╗██║  ██╗██║██║ ╚████║╚██████╔╝
╚═════╝ ╚══════╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝ ╚═════╝

*/

    EXEC dbo.DropIndexes;

    /*Run this here*/

    BEGIN TRAN;
        UPDATE b
            SET b.UserId = 138
        FROM dbo.Badges AS b
        WHERE b.Date >= '2010-12-31'
        AND   b.Date <  '2011-01-01';

    ROLLBACK;








    /*I am helpful*/
    CREATE INDEX
        woah_mama
    ON dbo.Badges
        (Date)
    WITH
        (MAXDOP = 8, SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);


/*
With an index on Date, we made it easier
for the storage engine to find the data
it needed to update.

*/























































/*
███╗   ███╗███████╗███╗   ███╗ ██████╗ ██████╗ ██╗   ██╗
████╗ ████║██╔════╝████╗ ████║██╔═══██╗██╔══██╗╚██╗ ██╔╝
██╔████╔██║█████╗  ██╔████╔██║██║   ██║██████╔╝ ╚████╔╝
██║╚██╔╝██║██╔══╝  ██║╚██╔╝██║██║   ██║██╔══██╗  ╚██╔╝
██║ ╚═╝ ██║███████╗██║ ╚═╝ ██║╚██████╔╝██║  ██║   ██║
╚═╝     ╚═╝╚══════╝╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝
*/

    EXEC dbo.DropIndexes;

    /*9.4 GB memory grant*/
    GO
    CREATE OR ALTER PROCEDURE
        dbo.Blueprint_Memory
    AS
    BEGIN;
        WITH
            comments AS
        (
            SELECT
                c.Id,
                c.CreationDate,
                c.PostId,
                c.Score,
                c.Text,
                c.UserId,
                n =
                    ROW_NUMBER() OVER
                    (
                        PARTITION BY
                            c.UserId
                        ORDER BY
                            c.Score DESC
                    )
            FROM dbo.Comments AS c
            WHERE c.UserId IS NOT NULL
        )
        SELECT
            u.DisplayName,
            c.*
        FROM comments AS c
        JOIN dbo.Users AS u
          ON u.Id = c.UserId
        WHERE c.n = 0;
    END;
    GO

/*

/*
Get RML Utils here.
https://www.microsoft.com/en-gb/download/details.aspx?id=4511
*/

We can only run three copies of this before we tank memory
ostress -SSQL2017 -d"StackOverflow2013" -Q"EXEC dbo.Blueprint_Memory;" -U"ostress" -P"ostress" -q -n4 -r20 -o"C:\temp\crap"

*/

EXEC dbo.sp_PressureDetector
    @what_to_check = N'memory';


/*
Let's get it on!
*/

    /*Let's get it on!*/
    CREATE INDEX
        whatever
    ON dbo.Comments
        (UserId, Score DESC)
    INCLUDE
        (CreationDate, PostId, Text)
    WITH
        (MAXDOP = 8, SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);

    /*Thank you for being a friend*/
    EXEC dbo.sp_WhoIsActive;

    EXEC dbo.Blueprint_Memory;

    /*
    The sort in the window function required memory
     - We can fix it by adding an index:
      - Key: Partition By columns, Order by columns
      - Indlude: Columns we're selecting
    */
































/*
████████╗██╗  ██╗██████╗ ███████╗ █████╗ ██████╗ ███████╗
╚══██╔══╝██║  ██║██╔══██╗██╔════╝██╔══██╗██╔══██╗██╔════╝
   ██║   ███████║██████╔╝█████╗  ███████║██║  ██║███████╗
   ██║   ██╔══██║██╔══██╗██╔══╝  ██╔══██║██║  ██║╚════██║
   ██║   ██║  ██║██║  ██║███████╗██║  ██║██████╔╝███████║
   ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═════╝ ╚══════╝

*/

    EXEC dbo.DropIndexes;
    GO

    CREATE OR ALTER PROCEDURE
        dbo.Blueprint_Threads
    AS
    BEGIN
        SELECT 
            records = COUNT_BIG(*)
        FROM dbo.Users AS u
        JOIN dbo.Comments AS c
          ON u.Id = c.UserId
        JOIN dbo.Badges AS b
          ON b.Id = c.Id
        WHERE u.Reputation = 73;
    END;
GO


    SELECT
        total_worker_threads =
            (
                512 +
                (
                  (
                      COUNT_BIG(*) - 4
                  ) * 16
                )
            )
    FROM   sys.dm_os_schedulers AS dos
    WHERE  dos.status = N'VISIBLE ONLINE';


/*
Let's just beat the crap out of it!

ostress -SSQL2017 -d"StackOverflow2013" -Q"EXEC dbo.Blueprint_Threads;" -U"ostress" -P"ostress" -q -n448 -r20 -o"C:\temp\crap"
*/

EXEC dbo.sp_PressureDetector
    @what_to_check = 'cpu';

/*
You can probably guess...
 * If we add some indexes, maybe we can...
  * Get a serial plan?
  * Get a different join order?
*/

    CREATE INDEX
        whatever
    ON dbo.Users
        (Reputation, Id)
    WITH
        (MAXDOP = 8, SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);

    CREATE INDEX
        whatever
    ON dbo.Comments
        (UserId, Id)
    WITH(MAXDOP = 8, SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);

    CREATE INDEX
        whatever
    ON dbo.Badges
        (Id)
    WITH
        (MAXDOP = 8, SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);

    EXEC dbo.Blueprint_Threads;


/*
███████╗██╗███╗   ██╗
██╔════╝██║████╗  ██║
█████╗  ██║██╔██╗ ██║
██╔══╝  ██║██║╚██╗██║
██║     ██║██║ ╚████║
╚═╝     ╚═╝╚═╝  ╚═══╝
*/