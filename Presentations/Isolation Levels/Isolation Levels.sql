USE StackOverflow2013;
SET NOCOUNT ON;
EXEC dbo.DropIndexes;
IF @@TRANCOUNT > 0
BEGIN
    SELECT
        tc = @@TRANCOUNT;
    ROLLBACK;
END;
ALTER DATABASE Crap SET READ_COMMITTED_SNAPSHOT OFF;
ALTER DATABASE Crap SET ALLOW_SNAPSHOT_ISOLATION OFF;
ALTER DATABASE StackOverflow2013 SET READ_COMMITTED_SNAPSHOT OFF;
ALTER DATABASE StackOverflow2013 SET ALLOW_SNAPSHOT_ISOLATION OFF;
GO


/*

TURN ON QUERY PLANS ERIK
TURN ON QUERY PLANS ERIK
TURN ON QUERY PLANS ERIK

*/


/*Create these first - about 70 seconds*/
CREATE INDEX
    whatever
ON dbo.Votes
    (CreationDate, VoteTypeId)
WITH
    (SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);
GO

CREATE INDEX
    dethklok
ON dbo.Votes
    (VoteTypeId)
WITH
    (SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);
GO

CREATE INDEX
    p
ON dbo.Posts
    (ParentId)
WITH
    (SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);
GO





/*
███████╗██╗   ██╗███████╗██████╗ ██╗   ██╗████████╗██╗  ██╗██╗███╗   ██╗ ██████╗
██╔════╝██║   ██║██╔════╝██╔══██╗╚██╗ ██╔╝╚══██╔══╝██║  ██║██║████╗  ██║██╔════╝
█████╗  ██║   ██║█████╗  ██████╔╝ ╚████╔╝    ██║   ███████║██║██╔██╗ ██║██║  ███╗
██╔══╝  ╚██╗ ██╔╝██╔══╝  ██╔══██╗  ╚██╔╝     ██║   ██╔══██║██║██║╚██╗██║██║   ██║
███████╗ ╚████╔╝ ███████╗██║  ██║   ██║      ██║   ██║  ██║██║██║ ╚████║╚██████╔╝
╚══════╝  ╚═══╝  ╚══════╝╚═╝  ╚═╝   ╚═╝      ╚═╝   ╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝ ╚═════╝

██╗   ██╗ ██████╗ ██╗   ██╗    ██╗  ██╗███╗   ██╗ ██████╗ ██╗    ██╗     █████╗ ██████╗  ██████╗ ██╗   ██╗████████╗
╚██╗ ██╔╝██╔═══██╗██║   ██║    ██║ ██╔╝████╗  ██║██╔═══██╗██║    ██║    ██╔══██╗██╔══██╗██╔═══██╗██║   ██║╚══██╔══╝
 ╚████╔╝ ██║   ██║██║   ██║    █████╔╝ ██╔██╗ ██║██║   ██║██║ █╗ ██║    ███████║██████╔╝██║   ██║██║   ██║   ██║
  ╚██╔╝  ██║   ██║██║   ██║    ██╔═██╗ ██║╚██╗██║██║   ██║██║███╗██║    ██╔══██║██╔══██╗██║   ██║██║   ██║   ██║
   ██║   ╚██████╔╝╚██████╔╝    ██║  ██╗██║ ╚████║╚██████╔╝╚███╔███╔╝    ██║  ██║██████╔╝╚██████╔╝╚██████╔╝   ██║
   ╚═╝    ╚═════╝  ╚═════╝     ╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝  ╚══╝╚══╝     ╚═╝  ╚═╝╚═════╝  ╚═════╝  ╚═════╝    ╚═╝

██╗███████╗ ██████╗ ██╗      █████╗ ████████╗██╗ ██████╗ ███╗   ██╗    ██╗     ███████╗██╗   ██╗███████╗██╗     ███████╗
██║██╔════╝██╔═══██╗██║     ██╔══██╗╚══██╔══╝██║██╔═══██╗████╗  ██║    ██║     ██╔════╝██║   ██║██╔════╝██║     ██╔════╝
██║███████╗██║   ██║██║     ███████║   ██║   ██║██║   ██║██╔██╗ ██║    ██║     █████╗  ██║   ██║█████╗  ██║     ███████╗
██║╚════██║██║   ██║██║     ██╔══██║   ██║   ██║██║   ██║██║╚██╗██║    ██║     ██╔══╝  ╚██╗ ██╔╝██╔══╝  ██║     ╚════██║
██║███████║╚██████╔╝███████╗██║  ██║   ██║   ██║╚██████╔╝██║ ╚████║    ███████╗███████╗ ╚████╔╝ ███████╗███████╗███████║
╚═╝╚══════╝ ╚═════╝ ╚══════╝╚═╝  ╚═╝   ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝    ╚══════╝╚══════╝  ╚═══╝  ╚══════╝╚══════╝╚══════╝

██╗███████╗    ██╗    ██╗██████╗  ██████╗ ███╗   ██╗ ██████╗
██║██╔════╝    ██║    ██║██╔══██╗██╔═══██╗████╗  ██║██╔════╝
██║███████╗    ██║ █╗ ██║██████╔╝██║   ██║██╔██╗ ██║██║  ███╗
██║╚════██║    ██║███╗██║██╔══██╗██║   ██║██║╚██╗██║██║   ██║
██║███████║    ╚███╔███╔╝██║  ██║╚██████╔╝██║ ╚████║╚██████╔╝
╚═╝╚══════╝     ╚══╝╚══╝ ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝ ╚═════╝
*/










/*
███████╗██████╗ ██╗██╗  ██╗    ██████╗  █████╗ ██████╗ ██╗     ██╗███╗   ██╗ ██████╗
██╔════╝██╔══██╗██║██║ ██╔╝    ██╔══██╗██╔══██╗██╔══██╗██║     ██║████╗  ██║██╔════╝
█████╗  ██████╔╝██║█████╔╝     ██║  ██║███████║██████╔╝██║     ██║██╔██╗ ██║██║  ███╗
██╔══╝  ██╔══██╗██║██╔═██╗     ██║  ██║██╔══██║██╔══██╗██║     ██║██║╚██╗██║██║   ██║
███████╗██║  ██║██║██║  ██╗    ██████╔╝██║  ██║██║  ██║███████╗██║██║ ╚████║╚██████╔╝
╚══════╝╚═╝  ╚═╝╚═╝╚═╝  ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝╚═╝  ╚═══╝ ╚═════╝

    Consultant With Very Reasonable Rates™️

    W: erikdarling.com
    E: erik@erikdarling.com
    T: twitter.com/erikdarlingdata
    T: tiktok.com/@darling.data
    L: linkedin.com/company/darling-data/
    Y: youtube.com/c/ErikDarlingData

    Demos: https://go.erikdarling.com/Isolation
    Datas: https://go.erikdarling.com/Stack2013

*/










/*
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡴⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣼⠃⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀⣤⠤⠶⠶⠶⠶⠶⠶⢀⣾⡏⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⣀⡴⠞⠋⠁⠀⠀⠀⠀⠀⠀⠀⢠⣿⡿⠀⠙⠳⢦⣀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⣠⠞⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣰⣿⣿⠃⠀⠀⠀⠀⠉⠳⣄⠀⠀⠀⠀⠀
⠀⠀⠀⢠⠞⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣴⣿⣿⣇⣠⣴⡶⠀⠀⠀⠀⠈⠳⣄⠀⠀⠀
⠀⠀⣰⠋⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣼⣿⣿⣿⣿⣿⣿⠃⠀⠀⠀⠀⠀⠀⠙⣆⠀⠀
⠀⣰⠇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣾⣿⣿⣿⣿⣿⣿⠇⠀⠀⠀⠀⠀⠀⠀⠀⠘⣆⠀
⢠⡏⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⣿⣿⢿⣿⣿⣿⣿⡟⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢹⡄
⢸⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⠀⢠⣿⣿⣿⣿⡿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⡇
⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣿⣿⣿⣿⣿⠃⠀⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣿
⢿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣾⣿⣿⣿⣿⣷⣾⡿⠃⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡿
⢸⡄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣾⣿⣿⣿⣿⣿⣿⡿⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢠⡇
⠈⣧⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣾⣿⣿⣿⣿⣿⣿⠟⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣼⠁
⠀⠘⣇⠀⠀⠀⠀⠀⠀⠀⠀⣼⣿⣿⣿⣿⣿⣿⠋⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣸⠃⠀
⠀⠀⠘⢧⠀⠀⠀⠀⠀⠀⠘⠋⠉⣼⣿⣿⡿⠃⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡴⠃⠀⠀
⠀⠀⠀⠈⠳⣄⠀⠀⠀⠀⠀⠀⢰⣿⣿⡟⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⠞⠁⠀⠀⠀
⠀⠀⠀⠀⠀⠈⠳⣤⡀⠀⠀⢀⣿⣿⠏⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣤⠞⠁⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠙⠳⠂⣾⣿⠃⠀⠀⠀⠀⠀⠀⢀⣀⣠⡴⠞⠋⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣸⡿⠁⠉⠛⠛⠛⠛⠛⠛⠉⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⢰⠟⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⢀⠏⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
*/










/*
███████╗██╗   ██╗██████╗ ██████╗ ██████╗ ██╗███████╗███████╗██╗
██╔════╝██║   ██║██╔══██╗██╔══██╗██╔══██╗██║██╔════╝██╔════╝██║
███████╗██║   ██║██████╔╝██████╔╝██████╔╝██║███████╗█████╗  ██║
╚════██║██║   ██║██╔══██╗██╔═══╝ ██╔══██╗██║╚════██║██╔══╝  ╚═╝
███████║╚██████╔╝██║  ██║██║     ██║  ██║██║███████║███████╗██╗
╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝     ╚═╝  ╚═╝╚═╝╚══════╝╚══════╝╚═╝

Run this first to talk about the query plan and show results
 * Order of operations
 * Look at the PostTypeId column data

*/


SELECT
    p.*
FROM dbo.Posts AS p WITH(INDEX = p)
WHERE p.ParentId =
(
    SELECT TOP (1)
        p2.ParentId
    FROM dbo.Posts AS p2
    WHERE p2.PostTypeId = 2
    ORDER BY
        p2.Score DESC,
        p2.Id DESC
)
OPTION(MAXDOP 1);


/*Put this one in a new window, run first*/
USE StackOverflow2013;
SET NOCOUNT ON;
BEGIN TRANSACTION;
    UPDATE
        p
    SET
        p.LastActivityDate =
            DATEADD
            (
                MILLISECOND,
                1,
                p.LastActivityDate
            )
    FROM dbo.Posts AS p
    WHERE p.Id = 21195018;
    /*Roll this back *after* you run the update below*/
ROLLBACK;


/*Run here, run second*/
SELECT
    p.*
FROM dbo.Posts AS p WITH(INDEX = p)
WHERE p.ParentId =
(
    SELECT TOP (1)
        p2.ParentId
    FROM dbo.Posts AS p2
    WHERE p2.PostTypeId = 2
    ORDER BY
        p2.Score DESC,
        p2.Id DESC
)
OPTION(MAXDOP 1);


/*Put this one in a new window, run third*/
USE StackOverflow2013;
SET NOCOUNT ON;

    UPDATE
        p
    SET
        p.PostTypeId = 1
    FROM dbo.Posts AS p
    WHERE p.Id IN
    (
        11227877,
        11227902,
        11237235,
        11303693,
        12853037,
        14889969,
        16184827,
        17782979,
        17828251
    );


/*
After you run this, roll back the update
query and look at the select query results
 * What is PostTypeId now?
 * How do you feel about that?

*/


/*Fix this*/
UPDATE
    p
SET
    p.PostTypeId = 2
FROM dbo.Posts AS p
WHERE p.Id IN
(
    11227877,
    11227902,
    11237235,
    11303693,
    12853037,
    14889969,
    16184827,
    17782979,
    17828251
);










/*
██╗███████╗ ██████╗ ██╗      █████╗ ████████╗██╗ ██████╗ ███╗   ██╗
██║██╔════╝██╔═══██╗██║     ██╔══██╗╚══██╔══╝██║██╔═══██╗████╗  ██║
██║███████╗██║   ██║██║     ███████║   ██║   ██║██║   ██║██╔██╗ ██║
██║╚════██║██║   ██║██║     ██╔══██║   ██║   ██║██║   ██║██║╚██╗██║
██║███████║╚██████╔╝███████╗██║  ██║   ██║   ██║╚██████╔╝██║ ╚████║
╚═╝╚══════╝ ╚═════╝ ╚══════╝╚═╝  ╚═╝   ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝

Isolation levels come in 2.5 flavors

WHATEVER:
 Read Uncommitted/NOLOCK (RU):
  * 🤔🤔🤔🤔🤔🤔🤔🤔
 Chaos (Not actually honored, but is a choice in maintenance plans):
  * 😬😬😬😬😬😬😬😬

Locking Reads:
 Read Committed (RC):
  * Pessimistic 🦐
 Repeatable Read (RR):
  * Really Pessimistic 🏋️‍
 Serializable (SZ):
  * Really, Really Pessimistic 🏋️‍🏋️‍

The vast majority of applications don't need RR/SZ across the board
 * Some may need it in specific places
 * Lots of potential blocking and deadlocking
 * Have some surprises, too

*/


/*Don't pretend you don't have one.*/
USE Crap;
SET NOCOUNT ON;
GO

/*el tiablo*/
DROP TABLE IF EXISTS
    dbo.Pessimism;
GO

/*HELLO.*/
CREATE TABLE
    dbo.Pessimism
(
    id bigint NOT NULL
       PRIMARY KEY CLUSTERED,
    a_thing integer NOT NULL,
    a_date datetime2(7) NOT NULL
        DEFAULT SYSDATETIME()
);

/*The odds are good when the goods are odd.*/
INSERT
    dbo.Pessimism
WITH
    (TABLOCK)
(
    id,
    a_thing
)
VALUES
     (1, 10),
     (3, 30),
     (5, 50),
     (7, 70),
     (9, 90);

/*
Repeatable Read
 * Only locks rows that it has read
 * Allows changes *around* locked keys
 * Does not allow changes *to* locked keys

*/


/*New window, scroll to stop message*/
USE Crap;
SET NOCOUNT ON;
GO

/*First, prove that keys are locked*/
BEGIN TRANSACTION;
    UPDATE
        p
    SET
        p.id = 10,
        p.a_thing = 100
    FROM dbo.Pessimism AS p
    WHERE p.id = 1;
ROLLBACK TRANSACTION;

/*Even Stevens, allowed by Repeatable Read*/
BEGIN TRANSACTION;
    SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;

    INSERT
        dbo.Pessimism
    (
        id,
        a_thing
    )
    VALUES
         (0, 0),
         (2, 20),
         (4, 40),
         (6, 60),
         (8, 80);

    SELECT
        p.*
    FROM dbo.Pessimism AS p;
ROLLBACK TRANSACTION;

/*Key movement, allowed by Repeatable Read*/
BEGIN TRANSACTION;
    SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;

    SELECT
        p.*
    FROM dbo.Pessimism AS p
    ORDER BY
        p.id;

    UPDATE
        p
    SET
        p.id = 2,
        p.a_thing = 20
    FROM dbo.Pessimism AS p
    WHERE p.id = 9;

    SELECT
        p.*
    FROM dbo.Pessimism AS p
    ORDER BY
        p.id;

    DELETE
        p
    FROM dbo.Pessimism AS p
    WHERE p.id = 2;

    SELECT
        p.*
    FROM dbo.Pessimism AS p
    ORDER BY
        p.id;

ROLLBACK TRANSACTION;
/*End New Window queries, run the below and come back to them*/


/*Begin but don't roll back!*/
BEGIN TRANSACTION;
    SELECT
        p.*
    FROM dbo.Pessimism AS p WITH(REPEATABLEREAD, ROWLOCK)
    WHERE p.id <= 7
    AND   1 = (SELECT 1);
ROLLBACK TRANSACTION;





/*
Serializable
 * Only locks rows that it has read
 * Blocks movement between keys (key range locks)
 * Is not a point in time from the *start* of the transaction

*/





/*Put this one in a new window*/
USE Crap;
SET NOCOUNT ON;
GO

BEGIN TRANSACTION;
    INSERT
        dbo.Pessimism
    (
        id,
        a_thing
    )
    VALUES
         (6, 60), /*Quote this out after showing blocking*/
         (8, 80),
         (10, 100);

    SELECT
        p.*
    FROM dbo.Pessimism AS p;
COMMIT TRANSACTION;



/*Make sure nothing weird is open*/
IF @@TRANCOUNT > 0
BEGIN
    SELECT
        tc = @@TRANCOUNT;
    ROLLBACK;
END;

/*Begin but don't roll back!*/
BEGIN TRANSACTION;
    SELECT
        p.*
    FROM dbo.Pessimism AS p WITH(SERIALIZABLE, ROWLOCK)
    WHERE p.id <= 5
    AND   1 = (SELECT 1);
    /*Stop here and show the inserts*/


    /*Run this after the inserts*/
    SELECT
        p.*
    FROM dbo.Pessimism AS p WITH(SERIALIZABLE, ROWLOCK)
    WHERE p.id <= 10
    AND   1 = (SELECT 1);
ROLLBACK TRANSACTION;


/*
This would not lock 6
 * Sunil Agarwal:
 * https://techcommunity.microsoft.com/t5/sql-server-blog/range-locks/ba-p/383080

*/


BEGIN TRANSACTION;
    /* Lock < 5 */
    SELECT
        p.*
    FROM dbo.Pessimism AS p WITH (SERIALIZABLE, ROWLOCK)
    WHERE p.id < 5

    UNION ALL

    /* Lock = 5 */
    SELECT
        p.*
    FROM dbo.Pessimism AS p WITH (SERIALIZABLE, ROWLOCK)
    WHERE p.id = 5;
ROLLBACK TRANSACTION;


/*
Under Serializable
 * The 6 is blocked, but 8 and 10 are allowed
 * More importantly, the second query will see the inserts
  * In other words, the transaction doesn't provide
    a consistent "snapshot" view of the data for
    *both* Serializable queries within it,
    at least not from the *start* of the transaction.

  * It does provide a consistent snapshot of the data
    as of the time the transaction *commits*,
    this presents the ~unchanging view~ of the data

  * What you don't know: the logical order that
    your transaction occurred among other
    concurrent transactions

*/










/*
██╗    ██╗██╗  ██╗██╗   ██╗    ██╗    ██╗      ██████╗ ██╗   ██╗███████╗
██║    ██║██║  ██║╚██╗ ██╔╝    ██║    ██║     ██╔═══██╗██║   ██║██╔════╝
██║ █╗ ██║███████║ ╚████╔╝     ██║    ██║     ██║   ██║██║   ██║█████╗
██║███╗██║██╔══██║  ╚██╔╝      ██║    ██║     ██║   ██║╚██╗ ██╔╝██╔══╝
╚███╔███╔╝██║  ██║   ██║       ██║    ███████╗╚██████╔╝ ╚████╔╝ ███████╗
 ╚══╝╚══╝ ╚═╝  ╚═╝   ╚═╝       ╚═╝    ╚══════╝ ╚═════╝   ╚═══╝  ╚══════╝

███╗   ██╗ ██████╗ ██╗      ██████╗  ██████╗██╗  ██╗
████╗  ██║██╔═══██╗██║     ██╔═══██╗██╔════╝██║ ██╔╝
██╔██╗ ██║██║   ██║██║     ██║   ██║██║     █████╔╝
██║╚██╗██║██║   ██║██║     ██║   ██║██║     ██╔═██╗
██║ ╚████║╚██████╔╝███████╗╚██████╔╝╚██████╗██║  ██╗
╚═╝  ╚═══╝ ╚═════╝ ╚══════╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝

(Which is the same thing as Read Uncommmitted, gosh darnit)

Because I'm A Consultant: More NOLOCK, More Money
 * The developers need a lot of training
 * The queries and indexes needs a lot of tuning
 * There are probably some serious bugs in the software

No one with a lot of NOLOCK hints in their queries is happy with things.

The only other thing produces as much money as NOLOCK is:
         "We're an Entity Framework only shop"

Because No One Knows What It Does:
 * I've heard hundreds of developers say "it keeps my query from taking locks"
 * It *still takes* locks (Sch-S), what it really does is IGNORE LOCKS

These are the phenomena you can see under *Read Committed*
  * See the same row twice with the same values
  * See the same row twice with different values
  * Miss rows entirely
  * Duplicate rows entirely

Read Uncommitted has *all* those problems, plus...
 * Dirty reads from uncommitted transactions
 * Partially committed row/column data
 * Data movement errors

SELECT
    m.*
FROM sys.messages AS m
WHERE m.message_id = 601
ORDER BY
    m.language_id;

Most people associate NOLOCK with dirty reads, but...

*/

/*Don't pretend you don't have one.*/
USE Crap;
SET NOCOUNT ON;
GO

/*Example 2, NOLOCK*/
DROP TABLE IF EXISTS
    dbo.[no],
    dbo.lock;

/*One happy table*/
CREATE TABLE
    dbo.[no]
(
    id integer NOT NULL,
    no integer NULL
);

/*Two happy tables*/
CREATE TABLE
    dbo.lock
(
    id integer NOT NULL,
    lock integer NOT NULL
);

/*Feed one some data*/
INSERT
    dbo.[no]
(
    id,
    [no]
)
SELECT
    id = 1,
    [no] = NULL;

/*Feed the other some data*/
INSERT
    dbo.lock
(
    id,
    lock
)
SELECT
    id = 1,
    lock = 100;

/*Put this one in a new window*/
USE Crap;
SET NOCOUNT ON;

BEGIN TRAN;
    UPDATE
        l
    SET
        l.lock = 2147483647
    FROM dbo.lock AS l;
    /*Stop here*/

ROLLBACK;


UPDATE
    n
SET
    n.no = l.lock
OUTPUT
    Inserted.id,
    Inserted.no
FROM dbo.no AS n
JOIN dbo.lock AS l WITH(NOLOCK)
  ON n.id = l.id;


/*
The NOLOCK hint in the source table
allows dirty reads to get into the target table

If you think it's bad that users may sometimes *see*
the results of dirty reads, imagine bad data now gets
written in your database, what happens now?

*/










/*
 ██████╗ ██████╗ ████████╗██╗███╗   ███╗██╗███████╗███╗   ███╗
██╔═══██╗██╔══██╗╚══██╔══╝██║████╗ ████║██║██╔════╝████╗ ████║
██║   ██║██████╔╝   ██║   ██║██╔████╔██║██║███████╗██╔████╔██║
██║   ██║██╔═══╝    ██║   ██║██║╚██╔╝██║██║╚════██║██║╚██╔╝██║
╚██████╔╝██║        ██║   ██║██║ ╚═╝ ██║██║███████║██║ ╚═╝ ██║
 ╚═════╝ ╚═╝        ╚═╝   ╚═╝╚═╝     ╚═╝╚═╝╚══════╝╚═╝     ╚═╝

Microsoft really screwed up a long time ago
 * Every sane RDBMS ever is optimistic by default
 * They use Multi-Version Concurrency Control (MVCC)
   out of the box, without you having to figure it out
 * No muss, no fuss, no hyperventilating blog posts
   about NOLOCK or marbles maybe being the wrong color

SQL Server uses Read Committed (pessimistic locking) by default,
which means you end up with a lot of dumb blocking problems to solve

You also end up with very weak guarantees about what your queries can see.

Most concerns about race conditions are true for Read Committed, too
 * Your queries probably all use NOLOCK anyway
 * Your code patterns are probably susceptible to race conditions anyway
 * Read Committed doesn't guarantee much anyway

Blocking and Deadlocking between read and write queries is stupid

Let's talk about why you should *probably* choose an
optimistic isolation level for your databases

The last of the 2.5 isolation levels:

Non-locking Reads (mostly):
 Read Committed Snapshot Isolation (RCSI):
  * Reads and Writes don't fight
  * Opt-out; all queries use it by default unless you tell them not to
 Snapshot Isolation (SI):
  * Reads and Writes don't fight
  * Writes can also not fight, but ~it's complicated~
  * Opt-in; you have to tell queries to use it

Optimistic isolation levels don't fix *all* reader blocking, some exceptions are:
 * Foreign key validation
 * Foreign key cascades (Serializable)
 * Some indexed view maintenance

Read Committed is not a snapshot-esque point-in-time view of your data.

It very briefly takes and releases locks and only guarantees
that the row you read holds committed values.

That's short for "getting blocked"

*/


/*Don't pretend you don't have one.*/
USE Crap;
SET NOCOUNT ON;

/*Make sure nothing weird is open*/
IF @@TRANCOUNT > 0
BEGIN
    SELECT
        tc = @@TRANCOUNT;
    ROLLBACK;
END;

/*Enable Snapshot Isolation*/
ALTER DATABASE
    Crap
SET
    READ_COMMITTED_SNAPSHOT ON
WITH
    ROLLBACK IMMEDIATE;

/*Create a couple tables*/
DROP TABLE IF EXISTS
    dbo.one,
    dbo.two;

/*Hello, you.*/
CREATE TABLE
    dbo.one
(
    id int
);

/*Hello you, two.*/
CREATE TABLE
    dbo.two
(
    totals int
);

/*Insert some data into both*/
INSERT
    dbo.one
WITH
    (TABLOCK)
(
    id
)
SELECT
    sv.number
FROM master..spt_values AS sv
WHERE sv.type = N'P'
AND   sv.number BETWEEN 1 AND 10;

/*Here I am!*/
INSERT
    dbo.two
WITH
    (TABLOCK)
(
    totals
)
SELECT
    o.id
FROM dbo.one AS o
    UNION ALL
SELECT
    o.id
FROM dbo.one AS o;

/*What's currently in there?*/
SELECT
    o.id,
    all_total =
    (
        SELECT
            SUM(t2.totals)
        FROM dbo.two AS t2
    )
FROM dbo.one AS o
OPTION(FORCE ORDER);


/*Stick this one in a new window*/
USE Crap;
SET NOCOUNT ON;
SET STATISTICS XML OFF;

WHILE 1 = 1
BEGIN
    UPDATE
        t
    SET
        t.totals += 1
    FROM dbo.two AS t;
END;


/*
Run this here
* Note the variation in results in the sum column when using Read Committed
* Quote out the WITH(READCOMMITTEDLOCK) hint to see RCSI behavior

Under RCSI, the results are identical

*/

SELECT
    o.id,
    all_total =
    (
        SELECT
            SUM(t2.totals)
        FROM dbo.two AS t2 --WITH(READCOMMITTEDLOCK)
    )
FROM dbo.one AS o
OPTION(FORCE ORDER);


/*Turn this back off*/
ALTER DATABASE
    Crap
SET
    READ_COMMITTED_SNAPSHOT OFF
WITH
    ROLLBACK IMMEDIATE;


/*
Result
 * Read Committed saw inconsistent results
   because reads were blocked and committed
   values were being incremented
 * Read Committed Snapshot Isolation saw consistent
   results because it read a consistent snapshot

*/










/*
██████╗ ███████╗ █████╗ ██████╗
██╔══██╗██╔════╝██╔══██╗██╔══██╗
██████╔╝█████╗  ███████║██║  ██║
██╔══██╗██╔══╝  ██╔══██║██║  ██║
██║  ██║███████╗██║  ██║██████╔╝
╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═════╝

 ██████╗ ██████╗ ███╗   ███╗███╗   ███╗██╗████████╗████████╗███████╗██████╗
██╔════╝██╔═══██╗████╗ ████║████╗ ████║██║╚══██╔══╝╚══██╔══╝██╔════╝██╔══██╗██╗
██║     ██║   ██║██╔████╔██║██╔████╔██║██║   ██║      ██║   █████╗  ██║  ██║╚═╝
██║     ██║   ██║██║╚██╔╝██║██║╚██╔╝██║██║   ██║      ██║   ██╔══╝  ██║  ██║██╗
╚██████╗╚██████╔╝██║ ╚═╝ ██║██║ ╚═╝ ██║██║   ██║      ██║   ███████╗██████╔╝╚═╝
 ╚═════╝ ╚═════╝ ╚═╝     ╚═╝╚═╝     ╚═╝╚═╝   ╚═╝      ╚═╝   ╚══════╝╚═════╝

███╗   ██╗ ██████╗ ████████╗    ███████╗ ██████╗      ██████╗ ██████╗ ███████╗ █████╗ ████████╗
████╗  ██║██╔═══██╗╚══██╔══╝    ██╔════╝██╔═══██╗    ██╔════╝ ██╔══██╗██╔════╝██╔══██╗╚══██╔══╝
██╔██╗ ██║██║   ██║   ██║       ███████╗██║   ██║    ██║  ███╗██████╔╝█████╗  ███████║   ██║
██║╚██╗██║██║   ██║   ██║       ╚════██║██║   ██║    ██║   ██║██╔══██╗██╔══╝  ██╔══██║   ██║
██║ ╚████║╚██████╔╝   ██║       ███████║╚██████╔╝    ╚██████╔╝██║  ██║███████╗██║  ██║   ██║
╚═╝  ╚═══╝ ╚═════╝    ╚═╝       ╚══════╝ ╚═════╝      ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝   ╚═╝

Read Committed kinda stinks.

Read Committed does not give you a *point in time* view of data
 * It isn't that optimistic isolation levels are perfect
 * It's that 99% of queries will run just fine using one

There are things that work differently between pessimistic and optimistic isolation levels,
but very few workloads rely on those differences for correctness

Read Committed can still:
 * Show deleted rows
 * See Rows Twice
 * Miss Rows Entirely

Modifications can happen before and after read queries release
their locks on the rows or pages they've finished reading

There is *usually no lock escalation* for read queries, though you can
use more strict isolation levels (Repeatable Read/Serializable)
to prevent those phenomena from happening.

(Lock escalation can happen, if something increases the lifespan of the S locks).

Some query plan shapes (more on this coming up) will cause
read queries to take and hold object level shared locks,
which cause a lot of blocking problems.

*/










/*
████████╗██╗  ██╗███████╗    ██████╗ ███████╗██████╗ ██╗██╗     ███████╗
╚══██╔══╝██║  ██║██╔════╝    ██╔══██╗██╔════╝██╔══██╗██║██║     ██╔════╝
   ██║   ███████║█████╗      ██████╔╝█████╗  ██████╔╝██║██║     ███████╗
   ██║   ██╔══██║██╔══╝      ██╔═══╝ ██╔══╝  ██╔══██╗██║██║     ╚════██║
   ██║   ██║  ██║███████╗    ██║     ███████╗██║  ██║██║███████╗███████║
   ╚═╝   ╚═╝  ╚═╝╚══════╝    ╚═╝     ╚══════╝╚═╝  ╚═╝╚═╝╚══════╝╚══════╝

 ██████╗ ███████╗    ██████╗ ███████╗ █████╗ ██████╗
██╔═══██╗██╔════╝    ██╔══██╗██╔════╝██╔══██╗██╔══██╗
██║   ██║█████╗      ██████╔╝█████╗  ███████║██║  ██║
██║   ██║██╔══╝      ██╔══██╗██╔══╝  ██╔══██║██║  ██║
╚██████╔╝██║         ██║  ██║███████╗██║  ██║██████╔╝
 ╚═════╝ ╚═╝         ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═════╝

 ██████╗ ██████╗ ███╗   ███╗███╗   ███╗██╗████████╗████████╗███████╗██████╗
██╔════╝██╔═══██╗████╗ ████║████╗ ████║██║╚══██╔══╝╚══██╔══╝██╔════╝██╔══██╗
██║     ██║   ██║██╔████╔██║██╔████╔██║██║   ██║      ██║   █████╗  ██║  ██║
██║     ██║   ██║██║╚██╔╝██║██║╚██╔╝██║██║   ██║      ██║   ██╔══╝  ██║  ██║
╚██████╗╚██████╔╝██║ ╚═╝ ██║██║ ╚═╝ ██║██║   ██║      ██║   ███████╗██████╔╝
 ╚═════╝ ╚═════╝ ╚═╝     ╚═╝╚═╝     ╚═╝╚═╝   ╚═╝      ╚═╝   ╚══════╝╚═════╝

These are the types of inconsistencies that can happen under Read Committed (pessimistic)

Remember that it's a very weak isolation level, and can encounter many of the same
types of inconsitencies that Read Uncommitted can, with the exception of dirty reads

+-----------------------------------+---------------+------------+--------------------+--------------+
|          isolation_level          | is_optimistic | dirty_read | nonrepeatable_read | phantom_read |
+-----------------------------------+---------------+------------+--------------------+--------------+
| Read Uncommitted                  | ???           | Yes        | Yes                | Yes          |
| Read Committed                    | No            | No         | Yes                | Yes          |
| Read Committed Snapshot Isolation | Yes           | No         | Yes                | Yes          |
| Repeatable Read                   | No            | No         | No                 | Yes          |
| Snapshot Isolation                | Yes           | No         | No                 | No           |
| Serializable                      | No            | No         | No                 | No           |
+-----------------------------------+---------------+------------+--------------------+--------------+

Dirty Reads:
 * If a transaction reads data that has been modified
   by another transaction but not yet committed.

Nonrepeatable Reads:
 * If a transaction reads the same row twice
   and finds different data each time.

Phantom Reads:
 * If a transaction retrieves a set of rows twice and...
  * New rows appear from another transaction
 * Serializable prevents this by not allowing other
   transactions to remove locked rows, but new qualifying
   rows may be inserted or updated

*/

/*Make sure nothing weird is open*/
IF @@TRANCOUNT > 0
BEGIN
    SELECT
        tc = @@TRANCOUNT;
    ROLLBACK;
END;


/*Don't pretend you don't have one.*/
USE Crap;
SET NOCOUNT ON;


/*GOODBYE FOREVER.*/
DROP TABLE IF EXISTS
    dbo.ReadCommittedStinks;

/*Oh welcome back.*/
CREATE TABLE
    dbo.ReadCommittedStinks
(
    id integer PRIMARY KEY,
    /* ˅˅˅˅˅ Pay attention to this */
    account_id bigint NOT NULL UNIQUE, /* <<<<< Pay attention to this */
    /* ˄˄˄˄˄ Pay attention to this */
    account_value money NOT NULL,
    f_name varchar(20) NOT NULL,
    l_name varchar(40) NOT NULL,
    creation_date datetime NOT NULL,
    last_activity datetime NULL
);

/*Get in here, you.*/
INSERT
    dbo.ReadCommittedStinks
(
    id,
    account_id,
    account_value,
    f_name,
    l_name,
    creation_date,
    last_activity
)
VALUES
    (1,  1001, $999,   'Eggs',   'Benedict',  GETDATE(), NULL),
    (2,  1002, $2000,  'Steak',  'Frites',    GETDATE(), NULL),
    (3,  1003, $3000,  'Chefs',  'Omelette',  GETDATE(), NULL),
    (4,  1004, $4000,  'Duck',   'Hash',      GETDATE(), NULL),
    (5,  1005, $5000,  'Bloody', 'Mary',      GETDATE(), NULL),
    (6,  1006, $6000,  'Scotch', 'Egg',       GETDATE(), NULL),
    (7,  1007, $7000,  'Quiche', 'Lorraine',  GETDATE(), NULL),
    (8,  1008, $8000,  'French', 'Toast',     GETDATE(), NULL),
    (9,  1009, $9000,  'Shak',   'Shuka',     GETDATE(), NULL),
    (10, 1010, $10000, 'Huevos', 'Rancheros', GETDATE(), NULL);

/*What's currently in the table?*/
SELECT
    rcs.*
FROM dbo.ReadCommittedStinks AS rcs
ORDER BY
    rcs.id;

/*Put this one in a new window, unquote the GO 2*/
USE Crap;
SET NOCOUNT ON;

SELECT
    rcs.*
FROM dbo.ReadCommittedStinks AS rcs
WHERE rcs.account_value > $999
ORDER BY
    rcs.account_value;
--GO 2

/*
Execute this here.

Start the transaction, run the first update,
and then go run the select query in the other window
with GO 2 unquoted.

It will get blocked on id 7, then we can make changes
to a bunch of other rows and see the results.

Remember: I am The Flash, and this is all happening very quickly.

*/

BEGIN TRANSACTION;
    UPDATE
        rcs
    SET
        rcs.account_value = $5001,
        rcs.last_activity = GETDATE()
    FROM dbo.ReadCommittedStinks AS rcs
    WHERE rcs.id = 7;


    UPDATE
        rcs
    SET
        rcs.account_value = $999,
        rcs.last_activity = GETDATE()
    FROM dbo.ReadCommittedStinks AS rcs
    WHERE rcs.id IN (1, 3, 4, 9);


    UPDATE
        rcs
    SET
        rcs.id = 11,
        rcs.last_activity = GETDATE()
    FROM dbo.ReadCommittedStinks AS rcs
    WHERE rcs.id = 6;


    UPDATE
        rcs
    SET
        rcs.id = 6,
        rcs.last_activity = GETDATE()
    FROM dbo.ReadCommittedStinks AS rcs
    WHERE rcs.id = 10;


    DELETE
        rcs
    FROM dbo.ReadCommittedStinks AS rcs
    WHERE rcs.id IN (2, 5, 8);


    INSERT
        dbo.ReadCommittedStinks
    (
        id,
        account_id,
        account_value,
        f_name,
        l_name,
        creation_date,
        last_activity
    )
    VALUES
        (2,  1002, $1000, 'French', 'Toast',   GETDATE(), GETDATE()),
        (8,  1008, $1000, 'Steak',  'Frites',  GETDATE(), GETDATE());
    /*
        Originals
        (2,  1002, $2000,  'Steak',  'Frites',    GETDATE(), NULL)
        (8,  1008, $8000,  'French', 'Toast',     GETDATE(), NULL)
    */
COMMIT TRANSACTION;


/*
After this commits, go back to the select query window.

What do the two result sets look like?

Imagine circumstances like this under high concurrency.

*/










/*
██████╗ ███████╗ █████╗ ██████╗
██╔══██╗██╔════╝██╔══██╗██╔══██╗
██████╔╝█████╗  ███████║██║  ██║
██╔══██╗██╔══╝  ██╔══██║██║  ██║
██║  ██║███████╗██║  ██║██████╔╝
╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═════╝

██████╗ ██╗      ██████╗  ██████╗██╗  ██╗███████╗██████╗
██╔══██╗██║     ██╔═══██╗██╔════╝██║ ██╔╝██╔════╝██╔══██╗
██████╔╝██║     ██║   ██║██║     █████╔╝ █████╗  ██████╔╝
██╔══██╗██║     ██║   ██║██║     ██╔═██╗ ██╔══╝  ██╔══██╗
██████╔╝███████╗╚██████╔╝╚██████╗██║  ██╗███████╗██║  ██║
╚═════╝ ╚══════╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝

Under Read Committed (pessimistic, locking)
read queries can block modification queries

Let's look at how

*/


/*Make sure nothing weird is open*/
IF @@TRANCOUNT > 0
BEGIN
    SELECT
        tc = @@TRANCOUNT;
    ROLLBACK;
END;


/*Back to sanity.*/
USE StackOverflow2013;
SET NOCOUNT ON;
DBCC FREEPROCCACHE;
GO

/*For a real reason...*/
CREATE OR ALTER PROCEDURE
    dbo.ReadBlocker
(
    @StartDate datetime
)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;

    DECLARE
        @i integer;

    SELECT
        @i = v.PostId
    FROM dbo.Votes AS v WITH(INDEX = whatever)
    WHERE v.CreationDate >= @StartDate
    AND   v.VoteTypeId > 5
    GROUP BY
        v.PostId
    ORDER BY
        v.PostId;
END;
GO

/*
Get a "bad" plan
 * Explain the lookup thing
*/

EXEC dbo.ReadBlocker
    @StartDate = '20131231'; /*The world ended*/

/*Trivia!*/
EXEC dbo.ReadBlocker
    @StartDate = '17530101'; /*Philip Stanhope*/


/*New window -- Look at locks, dangit*/
EXEC dbo.sp_WhoIsActive
    @get_locks = 1;


/*YET ANOTHER NEW WINDOW GOSH*/
USE StackOverflow2013;
SET NOCOUNT ON;
BEGIN TRAN;
    UPDATE dbo.Votes
        SET UserId = 2147483647
    WHERE 1 = 1;
ROLLBACK;










/*
██████╗ ███████╗ █████╗ ██████╗
██╔══██╗██╔════╝██╔══██╗██╔══██╗
██████╔╝█████╗  ███████║██║  ██║
██╔══██╗██╔══╝  ██╔══██║██║  ██║
██║  ██║███████╗██║  ██║██████╔╝
╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═════╝

██████╗ ███████╗ █████╗ ██████╗ ██╗      ██████╗  ██████╗██╗  ██╗
██╔══██╗██╔════╝██╔══██╗██╔══██╗██║     ██╔═══██╗██╔════╝██║ ██╔╝
██║  ██║█████╗  ███████║██║  ██║██║     ██║   ██║██║     █████╔╝
██║  ██║██╔══╝  ██╔══██║██║  ██║██║     ██║   ██║██║     ██╔═██╗
██████╔╝███████╗██║  ██║██████╔╝███████╗╚██████╔╝╚██████╗██║  ██╗
╚═════╝ ╚══════╝╚═╝  ╚═╝╚═════╝ ╚══════╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝

Similarly, read queries can deadlock with write queries

*/


/*Make sure nothing weird is open*/
IF @@TRANCOUNT > 0
BEGIN
    SELECT
        tc = @@TRANCOUNT;
    ROLLBACK;
END;


/*Select query with a predicate on our index key*/
USE StackOverflow2013;
SET NOCOUNT ON;
DECLARE
    @i int = 0,
    @PostId int;

WHILE
    @i < 100000
BEGIN
    SELECT
        @PostId = v.PostId,
        @i += 1
    FROM dbo.Votes AS v WITH(INDEX = dethklok)
    WHERE v.VoteTypeId = 8;
END;
GO


/*Update query that just flips the VoteTypeId back and forth*/
/*Put this one in a new window and start running it first*/
USE StackOverflow2013;
SET NOCOUNT ON;
DECLARE
    @i int = 0;
WHILE
    @i < 100000
BEGIN
    UPDATE
        v
    SET
        v.VoteTypeId = 8 - v.VoteTypeId,
        @i += 1
    FROM dbo.Votes AS v
    WHERE v.Id = 55537618;
END;
GO


/*Great reset*/
UPDATE
    v
SET
    v.VoteTypeId = 8
FROM dbo.Votes AS v
WHERE v.Id = 55537618
AND   v.VoteTypeId <> 8;





/*
What happened?

Our query did a key lookup
 * The nested loop join used the unordered prefetch optimization
 * That caused locks to be held on the clustered index until the query finished
 * Object level S locks will block IX and X locks

It's not just lookups that do this, it's just easy to demo
You may see other nested loops joins plans exhibit the same issue

To fix the deadlock:
 * Create a covering index:
  * For lookups that require a small number of columns,
    it's probably okay to do this, but for larger ones...
 * Use an optimistic isolation level, like RCSI or SI
  * This will avoid the issue entirely

*/










/*
 ██████╗ ██████╗ ███╗   ██╗ ██████╗██╗   ██╗██████╗ ██████╗ ███████╗███╗   ██╗ ██████╗██╗   ██╗
██╔════╝██╔═══██╗████╗  ██║██╔════╝██║   ██║██╔══██╗██╔══██╗██╔════╝████╗  ██║██╔════╝╚██╗ ██╔╝
██║     ██║   ██║██╔██╗ ██║██║     ██║   ██║██████╔╝██████╔╝█████╗  ██╔██╗ ██║██║      ╚████╔╝
██║     ██║   ██║██║╚██╗██║██║     ██║   ██║██╔══██╗██╔══██╗██╔══╝  ██║╚██╗██║██║       ╚██╔╝
╚██████╗╚██████╔╝██║ ╚████║╚██████╗╚██████╔╝██║  ██║██║  ██║███████╗██║ ╚████║╚██████╗   ██║
 ╚═════╝ ╚═════╝ ╚═╝  ╚═══╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝ ╚═════╝   ╚═╝

███████╗███████╗███╗   ██╗███████╗██╗████████╗██╗██╗   ██╗██╗████████╗██╗   ██╗
██╔════╝██╔════╝████╗  ██║██╔════╝██║╚══██╔══╝██║██║   ██║██║╚══██╔══╝╚██╗ ██╔╝
███████╗█████╗  ██╔██╗ ██║███████╗██║   ██║   ██║██║   ██║██║   ██║    ╚████╔╝
╚════██║██╔══╝  ██║╚██╗██║╚════██║██║   ██║   ██║╚██╗ ██╔╝██║   ██║     ╚██╔╝
███████║███████╗██║ ╚████║███████║██║   ██║   ██║ ╚████╔╝ ██║   ██║      ██║
╚══════╝╚══════╝╚═╝  ╚═══╝╚══════╝╚═╝   ╚═╝   ╚═╝  ╚═══╝  ╚═╝   ╚═╝      ╚═╝

You're smart if you use an optimistic isolation level, because the behavior is reliable
 * Read Uncommitted makes almost no guarantees
 * Read Committed makes flimsy guarantees
 * Repeatable Read makes less flimsy guarantees, plus a lot of blocking
 * Serializable makes awesome guarantees, plus a lot of blocking

Many unexpected things can happen under concurrency with any isolation level, even pessimistic ones.

Surprise!

Read Uncommitted Guarantees
 * Table definition(s) won't change while the query runs
 * Schema stability locks prevent it (so much for NOLOCKs)

Read Committed Guarantees what Read Uncommitted Guarantees, plus
 * You'll get blocked by active modification queries
 * Which is desirable if you're doing something outlandish, like managing your own Sequence tables
 * Or writing queueing code that works off tables (which should have locking hints, anyway)

Repeatable Read Guarantees all the previous stuff, plus some more fun things:
 * Data won't change during the transaction, but…
 * It does not prevent new rows from being inserted
 * And only prevents changes to rows once they're read

Serializable guarantees all of the previous stuff, plus more strictness
 * Fills in the gaps of Repeatable Read
 * Uses locking (key, range) to prevent phantoms
 * But it's not a snapshot in time from transaction start

It will see the latest committed data when the structure was actually locked,
which might happen after locks from another transaction are released

Serializable and Snapshot Isolation do not allow for reads that are:
 * Dirty
 * Non-repeatable
 * Phantom

The difference is that Snapshot may see “stale” data in versioned rows,
where Serializable will read point in time data directly from the source tables and indexes

The point I'm trying to get across here is that:
 * No isolation level is perfect
 * All of them have trade-offs
 * Isolation level subtleties surprise a lot of people

The hysteria around "incorrect results" under optimistic isolation levels
is not unfounded, but it is often overblown, and many non-existent guarantees
are attributed to the default Read Committed isolation level that make it seem safest

The behavior of the Serializable isolation level is what people often think
using the default Read Committed isolation level achieves, which is plain wrong

If you're using default Read Committed, and NOT using NOLOCK everywhere:
 * Even simple query patterns can cause issues
 * People will often assign these issues solely to
   optimistic isolation levels, which is largely false
 * Sometimes blocking will give you more up to date results,
   but usually the performance costs are quite high

Code patterns that can give you unexpected results under:
 * Read Uncommitted/NOLOCK
 * Read Committed
 * Repeatable Read
 * Read Committed Snapshot Isolation

(Assuming no other locking hints)

*/


/*Variable assignment*/
BEGIN TRANSACTION;
    DECLARE
        @NextUser integer;

    SELECT TOP (1)
        @NextUser = u.Id
    FROM dbo.Users AS u /*WITH(UPDLOCK, SERIALIZABLE)*/
    WHERE u.LastAccessDate >=
          (
              SELECT
                  MAX(u2.LastAccessDate)
              FROM dbo.Users AS u2 /*WITH(UPDLOCK, SERIALIZABLE)*/
          )
    ORDER BY
        u.LastAccessDate DESC /*Non-unique column*/,
        u.Id DESC /*Unique tie-breaker*/;

    /*
    What if someone else logs in after you assign this variable?
     * What locking hints do you need each time you touch the Users table?
     * Do you need a transaction to protect the entire thing?

    Look at the join order
     * What if someone logs in after the first scan of the Users table?

    */

    UPDATE
        u
    SET
       u.Reputation += 1000000
    FROM dbo.Users AS u
    WHERE u.Id = @NextUser;
COMMIT TRANSACTION;


/*
Temp tables

Same questions here:
 * What if something changes in dbo.TotalScoreByUser after you
  * Insert to the temp table
  * While you're creating the index

The materialized data set is already loaded into a temporary object

Again, you need locking hints (serializable) and a transaction to
fully protect this code pattern

*/


BEGIN TRANSACTION;
    SELECT
        Id,
        MaxScore = MAX(Score)
    INTO #update
    FROM
    (
        SELECT
            tsbu.Id,
            tsbu.QuestionScore
        FROM dbo.TotalScoreByUser AS tsbu /*WITH(UPDLOCK, SERIALIZABLE)*/
        /*Brief Read Committed locks only here*/

        UNION ALL

        SELECT
            tsbu.Id,
            tsbu.AnswerScore
        FROM dbo.TotalScoreByUser AS tsbu /*WITH(UPDLOCK, SERIALIZABLE)*/
        /*Brief Read Committed locks only here*/
    ) AS x (Id, Score)
    GROUP BY
        x.Id;

    /*
    What if stuff changes here?

    Someone has a question get a bunch of votes?
    What if votes are removed by fraud detection?
    */

    UPDATE
        tsbu
    SET
        tsbu.MaxScore = u.MaxScore
    FROM dbo.TotalScoreByUser AS tsbu
    JOIN #update AS u
      ON u.Id = tsbu.Id;
COMMIT TRANSACTION;


/*
Even a "simple" update...
 * This plan will read from dbo.TotalScoreByUser three times
 * Under Read Committed, no locks are held by reads, and there's no snapshot of the data

*/


BEGIN TRANSACTION;
    UPDATE
        tsbu
    SET
        tsbu.MaxScore = u.MaxScore
    FROM dbo.TotalScoreByUser AS tsbu
    /*This is the only table reference where exclusive locks will be acquired*/
    JOIN
    (
        SELECT
            Id,
            MaxScore = MAX(Score)
        FROM
        (
            SELECT
                tsbu.Id,
                tsbu.QuestionScore
            FROM dbo.TotalScoreByUser AS tsbu /*WITH(UPDLOCK, SERIALIZABLE)*/
            /*Brief Read Committed locks only here*/

            UNION ALL

            SELECT
                tsbu.Id,
                tsbu.AnswerScore
            FROM dbo.TotalScoreByUser AS tsbu /*WITH(UPDLOCK, SERIALIZABLE)*/
            /*Brief Read Committed locks only here*/
        ) AS x (Id, Score)
        GROUP BY
            x.Id
    ) AS u
      ON u.Id = tsbu.Id
    WHERE 1 = 1;
COMMIT TRANSACTION;


/*
Merge is a total disaster

There's lots of good advice about using SERIALIZABLE on the target table, but...
Under most isolation levels, data can change in the source tables too (Users and Posts in this case)
as you're reading from them.

Almost nothing is truly safe under high concurrency.
 * https://michaeljswart.com/2017/07/sql-server-upsert-patterns-and-antipatterns/

*/


BEGIN TRANSACTION;
    MERGE
        dbo.TotalScoreByUser /*WITH(SERIALIZABLE)*/ AS t
    USING
    (
        SELECT
            u.Id,
            u.DisplayName,
            QuestionScore =
                SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END),
            AnswerScore =
                SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END),
            TotalScore =
                SUM(CASE WHEN p.PostTypeId IN (1, 2) THEN p.Score ELSE 0 END),
            MaxScore =
                MAX(CASE WHEN p.PostTypeId IN (1, 2) THEN p.Score ELSE 0 END)
        FROM dbo.Users AS u
        LEFT JOIN dbo.Posts AS p
          ON p.OwnerUserId = u.Id
        GROUP BY
            u.Id,
            u.DisplayName
    ) AS x
    ON x.Id = t.Id
    WHEN MATCHED
    THEN
        UPDATE
          SET
            t.DisplayName = x.DisplayName,
            t.QuestionScore = x.QuestionScore,
            t.AnswerScore = x.AnswerScore,
            t.TotalScore = x.TotalScore,
            t.MaxScore = x.MaxScore
    WHEN NOT MATCHED
      BY TARGET
    THEN
        INSERT (  Id,   DisplayName,   QuestionScore,   AnswerScore,   TotalScore,   MaxScore)
        VALUES (x.Id, x.DisplayName, x.QuestionScore, x.AnswerScore, x.TotalScore, x.MaxScore)
    WHEN NOT MATCHED
      BY SOURCE
    THEN
        DELETE;
COMMIT TRANSACTION;


/*
All of these issues are related to timing and concurrency

While pessmistic isolation levels may give you more up-to-date data,
the blocking and deadlocking problems between read and write
queries while using them are horrible to constantly fire-fight

Your options are:
 * Use Snapshot Isolation and only opt-in safe queries to use it
 * Use Read Committed Snapshot Isolation, and add locking hints to not use it

Some third-party vendor apps are written with a lot of locking query hints,
and those will supercede database scoped isolation level settings

If you want queries to be blocked so they get the most recent version of row data,
then stick with Read Committed, and add Repeatable Read/Serializable hints where necessary

If you're okay with queries using the most recently known good version of row data
without being blocked, then an optimistic isolation level is for you
 * Some queries may read "out of date" data, but not "dirty" data

If you're okay with queries returning potato-faced nonsense, keep using NOLOCK

Things to watch out for if you start using an optimistic isolation level:
 * Long running modification queries
 * Sleeping queries that performed modifications

*/










/*
███████╗██╗    ██╗   ██╗███████╗
██╔════╝██║    ██║   ██║██╔════╝
███████╗██║    ██║   ██║███████╗
╚════██║██║    ╚██╗ ██╔╝╚════██║
███████║██║     ╚████╔╝ ███████║
╚══════╝╚═╝      ╚═══╝  ╚══════╝

██████╗  ██████╗███████╗██╗
██╔══██╗██╔════╝██╔════╝██║
██████╔╝██║     ███████╗██║
██╔══██╗██║     ╚════██║██║
██║  ██║╚██████╗███████║██║
╚═╝  ╚═╝ ╚═════╝╚══════╝╚═╝

If we're talking behavior, I like Snapshot Isolation (SI) better
than Read Committed Snapshot Isolation (RCSI), but it's sort of a pain.

Every query has to ask for it:
 * SET TRANSACTION ISOLATION LEVEL SNAPSHOT;

For some, this is attractive because they can test the behavior of specific
queries under concurrency to see if they indeed have race conditions before
enabling RCSI. This is a suitable arrangement for some long-term, too.

Some ORMs/data connectors allow you to specify it,
but it's not the default for anything in SQL Server

Lots of people get confused, turn it on, never use it,
and wonder why they still have dumb blocking problems

Both can fall victim to reading stale data from versioned rows

Snapshot Isolation can additionally hit problems with write skew,
but you have to sort of be a maniac to have modification queries use it

We're going to look at one important difference between the two

+-----------------------------------+---------------+------------+--------------------+--------------+
|          isolation_level          | is_optimistic | dirty_read | nonrepeatable_read | phantom_read |
+-----------------------------------+---------------+------------+--------------------+--------------+
| Read Committed Snapshot Isolation | Yes           | No         | Yes                | Yes          |
| Snapshot Isolation                | Yes           | No         | No                 | No           |
+-----------------------------------+---------------+------------+--------------------+--------------+

*/


/*Make sure nothing weird is open*/
IF @@TRANCOUNT > 0
BEGIN
    SELECT
        tc = @@TRANCOUNT;
    ROLLBACK;
END;


/*Don't pretend you don't have one.*/
USE Crap;
SET NOCOUNT ON;

/*OUT!*/
DROP TABLE IF EXISTS
    dbo.SnipSnap;

CREATE TABLE
    dbo.SnipSnap
(
    id integer
       PRIMARY KEY CLUSTERED,
    a_date datetime NOT NULL,
    a_number bigint NOT NULL
);

/*IN!*/
INSERT
    dbo.SnipSnap
WITH
    (TABLOCK)
(
    id,
    a_date,
    a_number
)
SELECT
    1,
    GETDATE(),
    138;


/*Current events*/
SELECT
    ss.*
FROM dbo.SnipSnap AS ss;


/*Turn both on*/
ALTER DATABASE Crap SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;
ALTER DATABASE Crap SET ALLOW_SNAPSHOT_ISOLATION ON;


/*
New window - Snapshot Isolation

Start running this, let it hit the WAITFOR

*/


USE Crap;
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL SNAPSHOT;
BEGIN TRANSACTION;
    SELECT
        ss.id,
        ss.a_date,
        ss.a_number,
        actual_date = GETDATE()
    FROM dbo.SnipSnap AS ss;

    WAITFOR DELAY '00:00:10.000';

    SELECT
        ss.id,
        ss.a_date,
        ss.a_number,
        actual_getdate = GETDATE()
    FROM dbo.SnipSnap AS ss;
COMMIT;


/*
New window - Read Committed Snapshot Isolation

Start running this, let it hit the WAITFOR

*/


USE Crap;
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
BEGIN TRANSACTION;
    SELECT
        ss.id,
        ss.a_date,
        ss.a_number,
        actual_getdate = GETDATE()
    FROM dbo.SnipSnap AS ss;

    WAITFOR DELAY '00:00:10.000';

    SELECT
        ss.id,
        ss.a_date,
        ss.a_number,
        actual_getdate = GETDATE()
    FROM dbo.SnipSnap AS ss;
COMMIT;


/*
Run this update while they both WAITFOR, run here.

Once both have completed, look at the different results
between the SI and RCSI results with the transaction.

*/


UPDATE
    ss
SET
    ss.a_date = GETDATE(),
    ss.a_number = 138138
FROM dbo.SnipSnap AS ss;

INSERT
    dbo.SnipSnap
(
    id,
    a_date,
    a_number
)
SELECT
    2,
    GETDATE(),
    831;

/*
Results:
 * Snapshot Isolation showed consistent results
   from when locks were first taken by a query
* Read Committed Snapshot Isolation showed consistent
  results from when each query started taking locks

*/


ALTER DATABASE Crap SET READ_COMMITTED_SNAPSHOT OFF WITH ROLLBACK IMMEDIATE;
ALTER DATABASE Crap SET ALLOW_SNAPSHOT_ISOLATION OFF;










/*
██████╗  █████╗  ██████╗███████╗
██╔══██╗██╔══██╗██╔════╝██╔════╝
██████╔╝███████║██║     █████╗
██╔══██╗██╔══██║██║     ██╔══╝
██║  ██║██║  ██║╚██████╗███████╗
╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚══════╝

 ██████╗ ██████╗ ███╗   ██╗██████╗ ██╗████████╗██╗ ██████╗ ███╗   ██╗██████╗
██╔════╝██╔═══██╗████╗  ██║██╔══██╗██║╚══██╔══╝██║██╔═══██╗████╗  ██║╚════██╗
██║     ██║   ██║██╔██╗ ██║██║  ██║██║   ██║   ██║██║   ██║██╔██╗ ██║  ▄███╔╝
██║     ██║   ██║██║╚██╗██║██║  ██║██║   ██║   ██║██║   ██║██║╚██╗██║  ▀▀══╝
╚██████╗╚██████╔╝██║ ╚████║██████╔╝██║   ██║   ██║╚██████╔╝██║ ╚████║  ██╗
 ╚═════╝ ╚═════╝ ╚═╝  ╚═══╝╚═════╝ ╚═╝   ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝  ╚═╝

When you might *need* blocking to save yourself from race conditions

Let's go to dinner!

*/


/*Make sure nothing weird is open*/
IF @@TRANCOUNT > 0
BEGIN
    SELECT
        tc = @@TRANCOUNT;
    ROLLBACK;
END;


/*Don't pretend you don't have one.*/
USE Crap;
SET NOCOUNT ON;

/*OUT!*/
DROP TABLE IF EXISTS
    dbo.DinnerPlans;

/*Hello.*/
CREATE TABLE
    dbo.DinnerPlans
(
    id bigint NOT NULL
       PRIMARY KEY CLUSTERED
       IDENTITY,
    name nvarchar(40) NULL,
    seat_number tinyint NULL,
    is_free bit NOT NULL
            DEFAULT 'false'
);

/*IN!*/
INSERT
    dbo.DinnerPlans WITH(TABLOCKX)
(
    name,
    seat_number,
    is_free
)
SELECT TOP (6)
    name =
        CASE m.message_id
             WHEN 21
             THEN NULL
             WHEN 101
             THEN N'Paul'
             WHEN 102
             THEN N'Kendra'
             WHEN 103
             THEN N'Joe'
             WHEN 104
             THEN N'Taryn'
             WHEN 105
             THEN N'Erin'
        END,
    seat_number =
        ROW_NUMBER() OVER
        (
            ORDER BY
                1/0
        ),
    is_free =
        CASE m.severity
             WHEN 20
             THEN 1
             ELSE 0
        END
FROM sys.messages AS m
WHERE m.language_id = 1033
ORDER BY
    m.message_id;


/*What does this look like?*/
SELECT
    dp.*
FROM dbo.DinnerPlans AS dp
ORDER BY
    dp.id;

/*Make sure this is off on the first run*/
ALTER DATABASE
    Crap
SET READ_COMMITTED_SNAPSHOT OFF
WITH
    ROLLBACK IMMEDIATE;

/*Do this on the second run*/
ALTER DATABASE
    Crap
SET READ_COMMITTED_SNAPSHOT ON
WITH
    ROLLBACK IMMEDIATE;


/*
Put this in two separate windows
 * Run each without the COMMIT
 * COMMIT the first first one
 * Look at the results

Don't forget to run the reset update after
changing isolation levels, or else FAILURE

*/

USE Crap;
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED; /*Need this in new window to reset from snapshot*/
BEGIN TRANSACTION;
     DECLARE
         @name nvarchar(40) = 'Erik'; /*Use in first session*/
         --@name nvarchar(40) = REVERSE('Erik'); /*Use in second session*/

    WITH
        FirstFreeTable AS
    (
        SELECT TOP (1)
            dp.id
        FROM dbo.DinnerPlans AS dp --WITH(READCOMMITTEDLOCK)
        WHERE dp.is_free = 1
    )
    UPDATE
        dp
    SET
        dp.[name] = @name,
        dp.is_free = 0
    OUTPUT
        Inserted.*
    FROM dbo.DinnerPlans AS dp
    JOIN FirstFreeTable AS fft
      ON fft.id = dp.id;
COMMIT;


/*Reset*/
UPDATE
    dp
 SET
    dp.name = NULL,
    dp.is_free = 1
OUTPUT
    Inserted.*
FROM dbo.DinnerPlans AS dp
WHERE dp.id  = 1
AND   dp.is_free = 0;


/*What do we end up with?*/
SELECT
    dp.*
FROM dbo.DinnerPlans AS dp
ORDER BY
    dp.id;


/*
A direct update wouldn't have this problem,
because there's no read-only locks taken
against a second reference to the table

*/


UPDATE TOP (1)
    dp
SET
    dp.name = N'Erik',
    dp.is_free = 0
FROM dbo.DinnerPlans AS dp
WHERE dp.is_free = 1;


/*

This is a somewhat common query pattern that will behave differently
under Read Committed (locking) and Read Committed Snapshot Isolation (optimistic),
and one you have to be careful of when considering switching over.

There are other query patterns where it may not be work identically, too.
 * Triggers that enforce integrity (without the presence of keys and constraints)

Like I said before, it's unlikely that any isolation level is 100% correct
for every nook and cranny of your workload, but optimistic ones tend to be
the better choice for large portions of most workloads that I see.

I mean that in the sense that they would be a better choice than Read Committed,
the default database isolation level for SQL Server.

You should think of them sort of like other server and database settings, for instance:
 * Max Degree Of Parallelism: 8
 * Cost Threshold For Parallelism: 50

These are good ways to set reasonable guardrails for the majority of your workload,
but you will probably always have queries that require different and special handling.

When you consider the sheer amount of NOLOCK hints written to avoid Read Committed
because of locking and blocking, it's obvious that it's not a good general choice.

Think about the number of people in the world who believe NOLOCK to be a
"best practice", even via a misunderstanding of what it means in reality.

Even if you don't leave here aching to use an optimistic isolation level,
I hope that you'll view your current set of queries with new suspicion
for how they'll behave under concurrency, and the potential for weird/incorrect
results even under pessimistic locking isolation levels without additional protection.

*/










/*
 ██████╗ ██╗   ██╗███████╗███████╗████████╗██╗ ██████╗ ███╗   ██╗███████╗██████╗
██╔═══██╗██║   ██║██╔════╝██╔════╝╚══██╔══╝██║██╔═══██╗████╗  ██║██╔════╝╚════██╗
██║   ██║██║   ██║█████╗  ███████╗   ██║   ██║██║   ██║██╔██╗ ██║███████╗  ▄███╔╝
██║▄▄ ██║██║   ██║██╔══╝  ╚════██║   ██║   ██║██║   ██║██║╚██╗██║╚════██║  ▀▀══╝
╚██████╔╝╚██████╔╝███████╗███████║   ██║   ██║╚██████╔╝██║ ╚████║███████║  ██╗
 ╚══▀▀═╝  ╚═════╝ ╚══════╝╚══════╝   ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝  ╚═╝

    W: erikdarling.com
    E: erik@erikdarling.com
    T: twitter.com/erikdarlingdata
    T: tiktok.com/@darling.data
    L: linkedin.com/company/darling-data/
    Y: youtube.com/c/ErikDarlingData

    Demos: https://go.erikdarling.com/Isolation
    Datas: https://go.erikdarling.com/Stack2013

*/
