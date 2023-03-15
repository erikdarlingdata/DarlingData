USE StackOverflow2013;
EXEC dbo.DropIndexes;
SET NOCOUNT ON;
DBCC FREEPROCCACHE;
GO 

EXEC dbo.DropIndexes;
GO 

CREATE INDEX 
    whatever_multi_pass
ON dbo.Users
    (Reputation, UpVotes, DownVotes, CreationDate DESC) 
INCLUDE 
    (DisplayName ) 
WITH
    (SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);
GO 

/*
███████╗ ██████╗ ██████╗ ████████╗ █████╗ ██████╗ ██╗     ███████╗███████╗
██╔════╝██╔═══██╗██╔══██╗╚══██╔══╝██╔══██╗██╔══██╗██║     ██╔════╝██╔════╝
███████╗██║   ██║██████╔╝   ██║   ███████║██████╔╝██║     █████╗  ███████╗
╚════██║██║   ██║██╔══██╗   ██║   ██╔══██║██╔══██╗██║     ██╔══╝  ╚════██║
███████║╚██████╔╝██║  ██║   ██║   ██║  ██║██████╔╝███████╗███████╗███████║
╚══════╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝╚═════╝ ╚══════╝╚══════╝╚══════╝     
*/


/*

Turn on query plans

*/


/*

Why do we care about Sorts?
* Ask for memory grants
* Might spill to disk
* May make code sensitive to parameter sniffing
* Internally blocking

*/




/*Multi-key index!*/

CREATE INDEX 
    whatever_multi_pass
ON dbo.Users
(
    Reputation,
    UpVotes,
    DownVotes,
    CreationDate DESC
) INCLUDE 
(
    DisplayName 
);


SELECT TOP (1000)
    u.Reputation,
    u.UpVotes,
    u.DownVotes,
    u.CreationDate
FROM dbo.Users AS u
WHERE u.Reputation = 124
AND   u.UpVotes < 11
AND   u.DownVotes > 0
ORDER BY 
    u.Reputation,
    u.UpVotes,
    u.DownVotes,
    u.CreationDate DESC;


/*
Run these together
*/
SELECT TOP (1000)
    u.Reputation,
    u.UpVotes,
    u.DownVotes,
    u.CreationDate
FROM dbo.Users AS u
ORDER BY 
    u.UpVotes;

/*
Equality on first column, Order By second column
*/    
SELECT TOP (1000)
    u.Reputation,
    u.UpVotes,
    u.DownVotes,
    u.CreationDate
FROM dbo.Users AS u
WHERE 
    u.Reputation = 1
ORDER BY 
    u.UpVotes;



/*
Equality on first three columns
Order by fourth column
*/

SELECT TOP (1000)
    u.Reputation,
    u.UpVotes,
    u.DownVotes,
    u.CreationDate
FROM dbo.Users AS u
WHERE 
      u.Reputation = 1
AND   u.UpVotes = 0
AND   u.DownVotes = 0
ORDER BY 
    u.CreationDate DESC;


/*
Includes are Useless
*/
SELECT TOP (1000)
    u.Reputation,
    u.UpVotes,
    u.DownVotes,
    u.CreationDate
FROM dbo.Users AS u
WHERE 
      u.Reputation = 1
AND   u.UpVotes = 0
AND   u.DownVotes = 0
AND   u.CreationDate = '2013-12-31 23:59:23.147'
ORDER BY 
    u.DisplayName;





/*
Of course, inequalities are not so kind...
>, >=, <, <=, <>
*/

SELECT TOP (1000)
    u.Reputation,
    u.UpVotes,
    u.DownVotes,
    u.CreationDate
FROM dbo.Users AS u
WHERE 
    u.Reputation <= 1 
ORDER BY 
    u.UpVotes;

SELECT TOP (1000)
    u.Reputation,
    u.UpVotes,
    u.DownVotes,
    u.CreationDate
FROM dbo.Users AS u
WHERE 
    u.Reputation >= 1000000 
ORDER BY 
    u.UpVotes;

/*
Unless...
*/

SELECT TOP (1000) 
    u.Id, 
    u.Reputation, 
    u.UpVotes
FROM dbo.Users AS u
WHERE 
    u.Reputation >= 100000
ORDER BY 
    u.Reputation ASC;

SELECT TOP (1000) 
    u.Id, 
    u.Reputation, 
    u.UpVotes
FROM dbo.Users AS u
WHERE 
    u.Reputation <= 0
ORDER BY 
    u.Reputation ASC;

SELECT TOP (1000) 
    u.Id, 
    u.Reputation, 
    u.UpVotes
FROM dbo.Users AS u
WHERE 
    u.UpVotes >= 100000
ORDER BY 
    u.Reputation ASC;

SELECT TOP (1000) 
    u.Id, 
    u.Reputation, 
    u.UpVotes
FROM dbo.Users AS u
WHERE 
    u.DownVotes <= 100000
ORDER BY 
    u.Reputation ASC;









/*Clean up...*/
EXEC dbo.DropIndexes;
GO 


/*Create this while you talk about the query, bozo*/
CREATE INDEX 
    kerplop 
ON dbo.Votes
    (VoteTypeId, PostId, BountyAmount DESC, CreationDate)
WITH
    (SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);

/*
Without an index this will run for 34 seconds

With an index, will this have to Sort?
*/
WITH x AS 
(
    SELECT 
        v.Id, 
        v.PostId, 
        v.BountyAmount, 
        v.VoteTypeId, 
        v.CreationDate, 
        r = 
            ROW_NUMBER() OVER 
            ( 
                PARTITION BY 
                    v.PostId 
                ORDER BY 
                    v.BountyAmount DESC 
            )
    FROM dbo.Votes AS v
    WHERE 
        v.VoteTypeId IN 
        (
            1, 
            3
        )
    AND   
        v.CreationDate >= '20100101'
)
SELECT 
    x.*
FROM x
WHERE x.r = 0
OPTION(MAXDOP 1);




































/*
Without an index this will run for 34 seconds

With an index, will this have to Sort?
*/
SELECT 
    x.*
FROM 
(
    SELECT 
        v.Id, 
        v.PostId, 
        v.BountyAmount, 
        v.VoteTypeId, 
        v.CreationDate, 
        r = 
            ROW_NUMBER() OVER 
            ( 
                PARTITION BY 
                    v.PostId 
                ORDER BY 
                    v.BountyAmount DESC 
            )
    FROM dbo.Votes AS v
    WHERE 
        v.VoteTypeId = 1
    AND   
        v.CreationDate >= '20100101'
    
    UNION ALL 
    
    SELECT 
        v.Id, 
        v.PostId, 
        v.BountyAmount, 
        v.VoteTypeId, 
        v.CreationDate, 
        r = 
            ROW_NUMBER() OVER 
            ( 
                PARTITION BY 
                    v.PostId 
                ORDER BY 
                    v.BountyAmount DESC 
            )
    FROM   dbo.Votes AS v
    WHERE  
        v.VoteTypeId = 3
    AND    
        v.CreationDate >= '20100101'
) AS x
WHERE x.r = 0;



/*
Remember, we care about Sorts because...
* Ask for memory grants
* Might spill to disk
* May make code sensitive to parameter sniffing
* Internally blocking

Sometimes the optimizer will put a Sort in your plan without you asking...
http://bit.ly/NotMySort


*/