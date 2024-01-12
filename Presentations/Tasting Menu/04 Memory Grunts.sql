USE StackOverflow2013;
EXEC dbo.DropIndexes;
SET NOCOUNT ON;
DBCC FREEPROCCACHE;
GO 

/*
███╗   ███╗███████╗███╗   ███╗ ██████╗ ██████╗ ██╗   ██╗    
████╗ ████║██╔════╝████╗ ████║██╔═══██╗██╔══██╗╚██╗ ██╔╝    
██╔████╔██║█████╗  ██╔████╔██║██║   ██║██████╔╝ ╚████╔╝     
██║╚██╔╝██║██╔══╝  ██║╚██╔╝██║██║   ██║██╔══██╗  ╚██╔╝      
██║ ╚═╝ ██║███████╗██║ ╚═╝ ██║╚██████╔╝██║  ██║   ██║       
╚═╝     ╚═╝╚══════╝╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝       
                                                            
 ██████╗ ██████╗  █████╗ ███╗   ██╗████████╗███████╗        
██╔════╝ ██╔══██╗██╔══██╗████╗  ██║╚══██╔══╝██╔════╝        
██║  ███╗██████╔╝███████║██╔██╗ ██║   ██║   ███████╗        
██║   ██║██╔══██╗██╔══██║██║╚██╗██║   ██║   ╚════██║        
╚██████╔╝██║  ██║██║  ██║██║ ╚████║   ██║   ███████║        
 ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝   ╚═╝   ╚══════╝                                                                    
*/



/*
Turn on query plans!
*/













/*
If I run this, there's one Sort
The query asks for 166MB of memory for it
No index to support my order by...
Id is only an integer
*/
SELECT 
    u.*
FROM 
(  
    SELECT TOP (1000) 
        u.Id 
    FROM dbo.Users AS u
    ORDER BY 
        u.Reputation
) AS u
OPTION(MAXDOP 1);

















/*
If I run this query, there are two Sorts
But the memory grant is about the same 

It goes up a little for the Hash Join
The blocking operation during the Hash Join 
(build probe) allows them to share memory
*/
SELECT 
    u.*,
    u2.*
FROM 
(  
    SELECT TOP (1000) 
        u.Id
    FROM dbo.Users AS u
    ORDER BY 
        u.Reputation
) AS u
JOIN 
(
    SELECT TOP (1000) 
        u.Id
    FROM dbo.Users AS u
    ORDER BY 
        u.Reputation
) AS u2
  ON u.Id = u2.Id
OPTION(MAXDOP 1);











/*
If we force a Nested Loop Join, the memory grant doubles
With no blocking operator, grants can't be shared

Nested loops doesn't block anything, it just starts
looking for rows on the inner side as soon as they arrive
*/
SELECT 
    u.*,
    u2.*
FROM 
(  
    SELECT TOP (1000) 
        u.Id
    FROM dbo.Users AS u
    ORDER BY 
        u.Reputation
) AS u
INNER LOOP JOIN --Force the loop join
(   
    SELECT TOP (1000) 
        u.Id
    FROM dbo.Users AS u
    ORDER BY 
        u.Reputation
) AS u2
  ON u.Id = u2.Id
OPTION(MAXDOP 1);











/*
If I run this, there's still only one Sort,
But as we add columns, the memory grant gets larger
Optimizer makes a fuzzy guess for string columns: 
    
    They'll be half full.
    Or half empty.
    Depends on how you look at it.

Check out the arrow going into the Sort for data size*/
SELECT 
    u.*
FROM 
(  
    SELECT TOP (1000) 
        u.Id          -- 166MB (INT)
      , u.DisplayName -- 300MB (NVARCHAR 40)
      , u.WebsiteUrl  -- 900MB (NVARCHAR 200)
      , u.Location    -- 1.2GB (NVARCHAR 100)
      , u.AboutMe     -- 9GB   (NVARCHAR MAX)
    FROM dbo.Users AS u
    ORDER BY 
        u.Reputation
) AS u
OPTION(MAXDOP 1);













/*
Memory Grants aren't Grant * DOP
They're Grant / DOP
Each thread gets an equal share
*/
SELECT 
    u.*,
    u2.*
FROM 
(  
    SELECT TOP (1000) 
        u.Id
    FROM dbo.Users AS u
    ORDER BY 
        u.Reputation
) AS u
INNER HASH JOIN 
(
    SELECT TOP (1000) 
        u.Id
    FROM dbo.Users AS u
    ORDER BY 
        u.Reputation
) AS u2
ON u.Id = u2.Id
ORDER BY 
    u.Id, 
    u2.Id -- Add an ORDER BY
OPTION(MAXDOP 8);


/*
We must be careful with memory grants!
 * Bad estimates can inflate them
 * Selecting a lot of columns (especially strings) can inflate them
 * You can put data in order with indexes
*/