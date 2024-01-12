USE StackOverflow2013;
EXEC dbo.DropIndexes;
SET NOCOUNT ON;
DBCC FREEPROCCACHE;
GO    


/*
████████╗██████╗ ██╗██╗   ██╗██╗ █████╗ ██╗     
╚══██╔══╝██╔══██╗██║██║   ██║██║██╔══██╗██║     
   ██║   ██████╔╝██║██║   ██║██║███████║██║     
   ██║   ██╔══██╗██║╚██╗ ██╔╝██║██╔══██║██║     
   ██║   ██║  ██║██║ ╚████╔╝ ██║██║  ██║███████╗
   ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═══╝  ╚═╝╚═╝  ╚═╝╚══════╝
                                                
██████╗ ██╗      █████╗ ███╗   ██╗███████╗      
██╔══██╗██║     ██╔══██╗████╗  ██║██╔════╝      
██████╔╝██║     ███████║██╔██╗ ██║███████╗      
██╔═══╝ ██║     ██╔══██║██║╚██╗██║╚════██║      
██║     ███████╗██║  ██║██║ ╚████║███████║      
╚═╝     ╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚══════╝      
*/

/*

TURN ON QUERY PLANS DUMMY

*/




/*Trivial plan*/
SELECT TOP (100) 
    u.*
FROM dbo.Users AS u;

/*
Hit F4 to bring up plan properties, highlight the select operator
Sometimes you have to highlight a different one first to get properties to load correctly
*/




/*You can do some funny things that are still trivial*/
SELECT TOP (10000) 
    u.*, 
    n = 
        ROW_NUMBER() OVER 
        ( 
            PARTITION BY 
                u.Id 
            ORDER BY 
                u.Id 
        ) 
FROM dbo.Users AS u
ORDER BY 
    u.Id;




/*What gets us to full optimization?*/

/*Unique column*/
SELECT DISTINCT TOP (1000) 
    u.* /*Not this, we have a unique column in the table*/
FROM dbo.Users AS u;

/*Non-unique column - Run both of these together!*/

/*Few rows?*/
SELECT DISTINCT TOP (4304) 
    u.Reputation /*But this will!*/
FROM dbo.Users AS u;

/*Some more rows?*/
SELECT DISTINCT TOP (5000) 
    u.Reputation /*And this will!*/
FROM dbo.Users AS u;


/*
  The optimizer had a choice to make:
  How should I come up with a distinct list of Reputations?
  Sort > Stream Aggregate?
  Full Hash Match?
  Hash Match Flow Distinct?
*/


/*
There are obvious things that get full optimization, too
*/

/*Order by without an index?*/
SELECT TOP (100) 
    u.Id
FROM dbo.Users AS u
ORDER BY 
    u.AccountId;


/*If you have a parallel plan, you don't have a trivial plan*/






/*What about a really simple subquery?*/
SELECT TOP (100) 
    u.Id
FROM dbo.Users AS u;

SELECT TOP (100) 
    Id = (SELECT u.Id) --Only difference
FROM dbo.Users AS u;








/*What about an even simpler subquery?*/
SELECT 
    records = COUNT_BIG(*)
FROM dbo.Users AS u;

SELECT 
    records = COUNT_BIG(*)
FROM dbo.Users AS u
WHERE 1 = (SELECT 1);




/*
Why are trivial plans a problem?
When does it matter?

When you miss out on optimizations because they're not explored.    
*/


/*Nothing for you*/
SELECT 
    u.*
FROM dbo.Users AS u
WHERE u.Reputation = 2;

/*Missing index requests*/
SELECT 
    u.*
FROM dbo.Users AS u
WHERE u.Reputation = 2
AND   1 = (SELECT 1);




/*When Trivial Plans are a real bummer*/

/*Add a check constraint so we know Reputation boundaries*/
ALTER TABLE 
    dbo.Users
ADD CONSTRAINT 
    cn_rep 
CHECK 
(
    Reputation >= 1 
    AND Reputation <= 2000000
);


/*
Make sure it's trusted
... Or not NOT trusted.
*/
SELECT 
    cc.name, 
    cc.is_not_trusted 
FROM sys.check_constraints AS cc;

/*Query that should bail out (assuming you ran DropIndexes along the way as instructed) */
SELECT 
    u.DisplayName, 
    u.Age, 
    u.Reputation
FROM dbo.Users AS u
WHERE u.Reputation = 0;

/*
But we read every row in the table to return 0!
Check IO
*/

/*Query that does bail out*/
SELECT 
    u.DisplayName, 
    u.Age, 
    u.Reputation
FROM dbo.Users AS u
WHERE u.Reputation = 0
AND   1 = (SELECT 1);

/*
Check IO again
*/

    
    
    
    
    
    
    

/*
Trivial plans pair well with
 * No design spec
 * No constraints
 * Perfect indexes

Simple parameterization is good for
 * ??????????

*/