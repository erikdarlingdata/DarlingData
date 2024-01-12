USE StackOverflow2013;
SET NOCOUNT ON;
EXEC dbo.DropIndexes;
DBCC FREEPROCCACHE;
DBCC DROPCLEANBUFFERS;
CREATE INDEX onesie ON dbo.Posts(OwnerUserId, Score, CreationDate) WITH(MAXDOP = 8, SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);
CREATE INDEX twosie ON dbo.Votes(VoteTypeId, CreationDate) WITH(MAXDOP = 8, SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);
CREATE INDEX threesie ON dbo.Posts(ParentId, OwnerUserId) WITH(MAXDOP = 8, SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);
CREATE INDEX foursie ON dbo.Comments(UserId) WITH(MAXDOP = 8, SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);
CREATE INDEX fivesie ON dbo.Comments(CreationDate) WITH(MAXDOP = 8, SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);
ALTER DATABASE StackOverflow2013 SET COMPATIBILITY_LEVEL = 150;
GO 













/* 
██████╗ ███████╗███████╗███████╗ █████╗ ████████╗██╗███╗   ██╗ ██████╗                                                                         
██╔══██╗██╔════╝██╔════╝██╔════╝██╔══██╗╚══██╔══╝██║████╗  ██║██╔════╝                                                                         
██║  ██║█████╗  █████╗  █████╗  ███████║   ██║   ██║██╔██╗ ██║██║  ███╗                                                                        
██║  ██║██╔══╝  ██╔══╝  ██╔══╝  ██╔══██║   ██║   ██║██║╚██╗██║██║   ██║                                                                        
██████╔╝███████╗██║     ███████╗██║  ██║   ██║   ██║██║ ╚████║╚██████╔╝                                                                        
╚═════╝ ╚══════╝╚═╝     ╚══════╝╚═╝  ╚═╝   ╚═╝   ╚═╝╚═╝  ╚═══╝ ╚═════╝                                                                         
                                                                                                                                               
██████╗  █████╗ ██████╗  █████╗ ███╗   ███╗███████╗████████╗███████╗██████╗     ███████╗███╗   ██╗██╗███████╗███████╗██╗███╗   ██╗ ██████╗     
██╔══██╗██╔══██╗██╔══██╗██╔══██╗████╗ ████║██╔════╝╚══██╔══╝██╔════╝██╔══██╗    ██╔════╝████╗  ██║██║██╔════╝██╔════╝██║████╗  ██║██╔════╝     
██████╔╝███████║██████╔╝███████║██╔████╔██║█████╗     ██║   █████╗  ██████╔╝    ███████╗██╔██╗ ██║██║█████╗  █████╗  ██║██╔██╗ ██║██║  ███╗    
██╔═══╝ ██╔══██║██╔══██╗██╔══██║██║╚██╔╝██║██╔══╝     ██║   ██╔══╝  ██╔══██╗    ╚════██║██║╚██╗██║██║██╔══╝  ██╔══╝  ██║██║╚██╗██║██║   ██║    
██║     ██║  ██║██║  ██║██║  ██║██║ ╚═╝ ██║███████╗   ██║   ███████╗██║  ██║    ███████║██║ ╚████║██║██║     ██║     ██║██║ ╚████║╚██████╔╝    
╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝   ╚═╝   ╚══════╝╚═╝  ╚═╝    ╚══════╝╚═╝  ╚═══╝╚═╝╚═╝     ╚═╝     ╚═╝╚═╝  ╚═══╝ ╚═════╝     
                                                                                                                                               
██╗    ██╗██╗████████╗██╗  ██╗    ██████╗ ██╗   ██╗███╗   ██╗ █████╗ ███╗   ███╗██╗ ██████╗    ███████╗ ██████╗ ██╗                            
██║    ██║██║╚══██╔══╝██║  ██║    ██╔══██╗╚██╗ ██╔╝████╗  ██║██╔══██╗████╗ ████║██║██╔════╝    ██╔════╝██╔═══██╗██║                            
██║ █╗ ██║██║   ██║   ███████║    ██║  ██║ ╚████╔╝ ██╔██╗ ██║███████║██╔████╔██║██║██║         ███████╗██║   ██║██║                            
██║███╗██║██║   ██║   ██╔══██║    ██║  ██║  ╚██╔╝  ██║╚██╗██║██╔══██║██║╚██╔╝██║██║██║         ╚════██║██║▄▄ ██║██║                            
╚███╔███╔╝██║   ██║   ██║  ██║    ██████╔╝   ██║   ██║ ╚████║██║  ██║██║ ╚═╝ ██║██║╚██████╗    ███████║╚██████╔╝███████╗                       
 ╚══╝╚══╝ ╚═╝   ╚═╝   ╚═╝  ╚═╝    ╚═════╝    ╚═╝   ╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝     ╚═╝╚═╝ ╚═════╝    ╚══════╝ ╚══▀▀═╝ ╚══════╝
*/






/* 

    * W: www.erikdarling.com
    * E: erik@erikdarling.com
    * T: @erikdarlingdata
    
    Demo database:
    * http://bit.ly/Stack2013

    Demo scripts: 
    * http://bit.ly/DefeatSniffing

*/

/* 

Copyright 2024 Darling Data, LLC.

License: Creative Commons Attribution-ShareAlike 3.0 Unported (CC BY-SA 3.0)
More info: https://creativecommons.org/licenses/by-sa/3.0/
 
You are free to:
* Share - copy and redistribute the material in any medium or format
* Adapt - remix, transform, and build upon the material for any purpose, even 
  commercially
 
Under the following terms:
* Attribution - You must give appropriate credit, provide a link to the license,
  and indicate if changes were made.
* ShareAlike - If you remix, transform, or build upon the material, you must
  distribute your contributions under the same license as the original.

*/





/* 

Why: Because it's a hard problem to solve,
     but it's not *always* a problem.
     Most of the time, sniffed parameters
     are a good thing for your queries!

{ Sure, there are a lot of other ways you can fix it,
  but sometimes you have to go the extra mile }

Before I show you how to do that, 
I have to make sure everyone understands:
 * What dynamic SQL is
 * How to use it safely
 
 * What a parameter really is
 * How they can cause performance problems
 
 * What parameter sniffing looks like
 * How you can observe it happening
 
 * What information you need to reproduce it
 * How to fix it with dynamic SQL 

Who:   You
When:  Constantly
Where: SQL Server

*/


























/* 
██╗    ██╗██╗  ██╗ █████╗ ████████╗███████╗                                                 
██║    ██║██║  ██║██╔══██╗╚══██╔══╝██╔════╝                                                 
██║ █╗ ██║███████║███████║   ██║   ███████╗                                                 
██║███╗██║██╔══██║██╔══██║   ██║   ╚════██║                                                 
╚███╔███╔╝██║  ██║██║  ██║   ██║   ███████║                                                 
 ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝   ╚══════╝                                                 
                                                                                            
██████╗ ██╗   ██╗███╗   ██╗ █████╗ ███╗   ███╗██╗ ██████╗    ███████╗ ██████╗ ██╗   ██████╗ 
██╔══██╗╚██╗ ██╔╝████╗  ██║██╔══██╗████╗ ████║██║██╔════╝    ██╔════╝██╔═══██╗██║   ╚════██╗
██║  ██║ ╚████╔╝ ██╔██╗ ██║███████║██╔████╔██║██║██║         ███████╗██║   ██║██║     ▄███╔╝
██║  ██║  ╚██╔╝  ██║╚██╗██║██╔══██║██║╚██╔╝██║██║██║         ╚════██║██║▄▄ ██║██║     ▀▀══╝ 
██████╔╝   ██║   ██║ ╚████║██║  ██║██║ ╚═╝ ██║██║╚██████╗    ███████║╚██████╔╝███████╗██╗   
╚═════╝    ╚═╝   ╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝     ╚═╝╚═╝ ╚═════╝    ╚══════╝ ╚══▀▀═╝ ╚══════╝╚═╝ 
*/


/* 

A string that you build into a query to execute.

You might make some decisions based on user input, or state of data
 * Table name
 * User permissions
 * SQL Server version/edition
 * Object existence
 * Search arguments

The problem is, a lot of people write it unsafely.

For instance, you can't pass parameters to EXEC
 * Strings just get executed willy-nilly.

*/



/* 

Is this a problem?

*/
DECLARE 
    @SQLString nvarchar(MAX) = N'',
    @TableName sysname = N'Votes';

IF @TableName = N'Votes'
BEGIN
    SET @SQLString += N'SELECT records = COUNT_BIG(*) FROM dbo.Votes AS v;';
END;

IF @TableName = N'Posts'
BEGIN
    SET @SQLString += N'SELECT records = COUNT_BIG(*) FROM dbo.Posts AS p;';
END;

EXEC (@SQLString);
GO 


/* 

Of course, the problem with most dynamic SQL that I see is...

*/




DECLARE 
    @SQLString nvarchar(MAX) = N'',
    @Filter    nvarchar(MAX) = N'',
    @Title     nvarchar(250) = N''' 
  UNION ALL   
  SELECT 
      t.object_id, t.schema_id, t.name, SCHEMA_NAME(t.schema_id), t.create_date, t.modify_date, NULL 
  FROM sys.tables AS t --'; 
/* This ends the current statement, and adds in some sneaky code */

SET @SQLString += N' 
  SELECT TOP (5000) 
      p.OwnerUserId, p.Score, p.Tags, p.Title, p.CreationDate, p.LastActivityDate, p.Body 
  FROM dbo.Posts AS p 
  WHERE p.OwnerUserId = 22656 ';

/* This appends the sneaky code onto our harmless query */
IF @Title IS NOT NULL
BEGIN
    SET @Filter = @Filter + N' 
  AND p.Title LIKE ''' + N'%' + @Title + N'%''';
END;

IF @Filter IS NOT NULL
BEGIN
    SET @SQLString += @Filter;
END;

SET @SQLString += N' 
  ORDER BY p.Score DESC;';

/* Check the messages tab... */
RAISERROR('%s', 0, 1, @SQLString) WITH NOWAIT;

/* Check the results -- what's that at the end? */
EXEC (@SQLString);
GO



/* 

We can pass parameters to sp_executesql, 
but we need to... actually use parameters.

For instance, this still isn't safe.

*/


DECLARE 
    @SQLString nvarchar(MAX) = N'',
    @Filter    nvarchar(MAX) = N'',
    @Title     nvarchar(250) = N''' 
  UNION ALL   
  SELECT 
      t.object_id, t.schema_id, t.name, SCHEMA_NAME(t.schema_id), t.create_date, t.modify_date, NULL 
  FROM sys.tables AS t --';
/* This ends the current statement, and adds in some sneaky code */

SET @SQLString += N' 
  SELECT TOP (5000) 
      p.OwnerUserId, p.Score, p.Tags, p.Title, p.CreationDate, p.LastActivityDate, p.Body 
  FROM dbo.Posts AS p 
  WHERE p.OwnerUserId = 22656 ';

/* This appends the sneaky code onto our harmless query */
IF @Title IS NOT NULL
BEGIN
    SET @Filter = @Filter + N' 
  AND p.Title LIKE ''' + N'%' + @Title + N'%''';
END;

IF @Filter IS NOT NULL
BEGIN
    SET @SQLString += @Filter;
END;

SET @SQLString += N' 
  ORDER BY p.Score DESC;';

/* Check the messages tab... */
RAISERROR('%s', 0, 1, @SQLString) WITH NOWAIT;
/* Check the results -- what's that at the end? */
EXEC sys.sp_executesql 
    @SQLString;
GO



/* 

An actual factual parameter appears!

*/


DECLARE 
    @SQLString nvarchar(MAX) = N'',
    @Filter    nvarchar(MAX) = N'',
    @Title     nvarchar(250) = N''' 
  UNION ALL 
  SELECT 
      t.object_id, t.schema_id, t.name, SCHEMA_NAME(t.schema_id), t.create_date, t.modify_date, NULL 
  FROM sys.tables AS t --'; 
/* This ends the current statement, and adds in some sneaky code */

SET @SQLString += N' 
  SELECT TOP (5000) 
      p.OwnerUserId, p.Score, p.Tags, p.Title, p.CreationDate, p.LastActivityDate, p.Body 
  FROM dbo.Posts AS p 
  WHERE p.OwnerUserId = 22656 ';

/* This appends the sneaky code onto our harmless query */
IF @Title IS NOT NULL
BEGIN
    SET @Filter = @Filter + N' 
  AND p.Title LIKE N''%'' + @Title + N''%'' ';
END;

IF @Filter IS NOT NULL
BEGIN
    SET @SQLString += @Filter;
END;

SET @SQLString += N' 
  ORDER BY p.Score DESC;' + NCHAR(13) + NCHAR(13);

/* Check the messages tab... */
RAISERROR('%s', 0, 1, @SQLString) WITH NOWAIT;

/* Check the results -- what's that at the end now? */
EXEC sys.sp_executesql 
    @SQLString, 
  N'@Title nvarchar(250)', 
    @Title;

RAISERROR('The @Title Parameter is this: %s', 0, 1, @Title) WITH NOWAIT;
GO













/* 

When is dynamic SQL a good idea?

When it replaces awful things like this:

*/

SELECT 
    p.*
FROM dbo.Posts AS p
WHERE (p.OwnerUserId   = @OwnerUserId  OR @OwnerUserId IS NULL)
AND   (p.CreationDate >= @CreationDate OR @CreationDate IS NULL);

SELECT 
    p.*
FROM dbo.Posts AS p
WHERE (p.OwnerUserId   = ISNULL(@OwnerUserId,  p.OwnerUserId))
AND   (p.CreationDate >= ISNULL(@CreationDate, p.CreationDate));
GO 

SELECT 
    p.*
FROM dbo.Posts AS p
WHERE (p.OwnerUserId   = COALESCE(@OwnerUserId,  p.OwnerUserId))
AND   (p.CreationDate >= COALESCE(@CreationDate, p.CreationDate));
GO


/* 

These techniques don't work well...
  Unless you're going to stick a recompile hint on there, too

And look, I'm fine with that, if:
 * Queries don't execute a kajillion times a minute
 * The plans don't take a long time to compile

*/



/* 

The indexes we have: 
 * CREATE INDEX onesie 
       ON dbo.Posts 
   (OwnerUserId, Score, CreationDate);

 * CREATE INDEX threesie 
       ON dbo.Posts
   (ParentId, OwnerUserId);

*/


DBCC FREEPROCCACHE;
GO
DECLARE 
    @OwnerUserId  int = 22656, --Swap back and forth between 22656 and 1. What happens to the estimates? 
    @CreationDate datetime = '20080101',
    @SQLString    nvarchar(MAX) = N'
--Using Or
SELECT 
    p.*
FROM dbo.Posts AS p
WHERE (p.OwnerUserId   = @OwnerUserId  OR @OwnerUserId IS NULL)
AND   (p.CreationDate >= @CreationDate OR @CreationDate IS NULL)
ORDER BY 
    p.Score DESC;

--Using ISNULL
SELECT 
    p.*
FROM dbo.Posts AS p
WHERE (p.OwnerUserId   = ISNULL(@OwnerUserId,  p.OwnerUserId))
AND   (p.CreationDate >= ISNULL(@CreationDate, p.CreationDate))
ORDER BY 
    p.Score DESC;

-- Using COALESCE
SELECT 
    p.*
FROM dbo.Posts AS p
WHERE (p.OwnerUserId   = COALESCE(@OwnerUserId,  p.OwnerUserId))
AND   (p.CreationDate >= COALESCE(@CreationDate, p.CreationDate))
ORDER BY 
    p.Score DESC;
';

EXEC sys.sp_executesql 
    @SQLString,
  N'@OwnerUserId int,
    @CreationDate datetime',
    @OwnerUserId,
    @CreationDate;
GO 


/* 

Problem we're running into:
 * Can't seek into the index (weird predicates)
 * Bad guesses on the functions

*/



/* 

How recompile helps!

*/

DBCC FREEPROCCACHE;
GO
DECLARE 
    @OwnerUserId  int = 22656, --Swap back and forth between 22656 and 1. What happens to the estimates? 
    @CreationDate datetime = '20080101',
    @SQLString    nvarchar(MAX) = N'
--Using Or
SELECT 
    p.*
FROM dbo.Posts AS p
WHERE (p.OwnerUserId   = @OwnerUserId  OR @OwnerUserId IS NULL)
AND   (p.CreationDate >= @CreationDate OR @CreationDate IS NULL)
ORDER BY 
    p.Score DESC
OPTION(RECOMPILE);

--Using ISNULL
SELECT 
    p.*
FROM dbo.Posts AS p
WHERE (p.OwnerUserId   = ISNULL(@OwnerUserId,  p.OwnerUserId))
AND   (p.CreationDate >= ISNULL(@CreationDate, p.CreationDate))
ORDER BY 
    p.Score DESC
OPTION(RECOMPILE);

-- Using COALESCE
SELECT 
    p.*
FROM dbo.Posts AS p
WHERE (p.OwnerUserId   = COALESCE(@OwnerUserId,  p.OwnerUserId))
AND   (p.CreationDate >= COALESCE(@CreationDate, p.CreationDate))
ORDER BY 
    p.Score DESC
OPTION(RECOMPILE);
';

EXEC sys.sp_executesql 
    @SQLString,
  N'@OwnerUserId int,
    @CreationDate datetime',
    @OwnerUserId,
    @CreationDate;


/* 

Problems that solved
 * Can seek into the index
 * Good guesses all around
 * No weird predicates

Problems that causes:
 * Constant plan creation
 * Plan cache kinds sucks anyway
 * No historical information about query performance

*/
























/* 
██╗    ██╗██╗  ██╗ █████╗ ████████╗███████╗     █████╗                      
██║    ██║██║  ██║██╔══██╗╚══██╔══╝██╔════╝    ██╔══██╗                     
██║ █╗ ██║███████║███████║   ██║   ███████╗    ███████║                     
██║███╗██║██╔══██║██╔══██║   ██║   ╚════██║    ██╔══██║                     
╚███╔███╔╝██║  ██║██║  ██║   ██║   ███████║    ██║  ██║                     
 ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝   ╚══════╝    ╚═╝  ╚═╝                     
                                                                            
██████╗  █████╗ ██████╗  █████╗ ███╗   ███╗███████╗████████╗███████╗██████╗ 
██╔══██╗██╔══██╗██╔══██╗██╔══██╗████╗ ████║██╔════╝╚══██╔══╝██╔════╝██╔══██╗
██████╔╝███████║██████╔╝███████║██╔████╔██║█████╗     ██║   █████╗  ██████╔╝
██╔═══╝ ██╔══██║██╔══██╗██╔══██║██║╚██╔╝██║██╔══╝     ██║   ██╔══╝  ██╔══██╗
██║     ██║  ██║██║  ██║██║  ██║██║ ╚═╝ ██║███████╗   ██║   ███████╗██║  ██║
╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝   ╚═╝   ╚══════╝╚═╝  ╚═╝ 
*/



/* 

Procedures have parameters

*/
GO 
CREATE OR ALTER PROCEDURE 
    dbo.a_procedure
(
    @a_parameter sql_variant
)
AS 
    RETURN 138;
GO 


/* 

Functions have parameters

*/
CREATE OR ALTER FUNCTION 
    dbo.a_function
(
    @a_parameter sql_variant
)
RETURNS table
AS 
RETURN 
    SELECT x = 1;
GO 


/* 

Dynamic SQL has parameters

*/
EXEC sys.sp_executesql 
    @sql,
  N'@a_parameter',
    @a_parameter;
GO 









/* 

This can be a parameter, depending on how you use it
https://www.erikdarlingdata.com/sql-server/yet-another-post-about-local-variables/

*/
DECLARE 
    @variable sql_variant;


/* 

This is not a parameter! This is a local variable.

*/
SELECT 
    _ = 1/0
FROM dbo.a_table
WHERE a_column = @variable;



/* 

But you can magically turn it into a parameter:

*/


/* 

Pass it to a procedure or function 
(I know, you don't exec functions. Sue me.)

*/
EXEC a_procedure 
    @variable;

/* 

Pass it to dynamic SQL

*/
EXEC sys.sp_executesql 
    @sql,
  N'@variable',
    @variable;
GO 



/* 

Why is this distinction important? 

Cardinality estimation! Local variables get stupid guesses.

Yes, recompile helps. Thanks for letting me know.

*/


/* Declare 4 */
DECLARE 
    @VoteTypeId int = 4;

SELECT 
    records = 
        COUNT_BIG(*)
FROM dbo.Votes AS v
WHERE v.VoteTypeId = @VoteTypeId;
GO 

/* Declare 2 */
DECLARE 
    @VoteTypeId int = 2;

SELECT 
    records = 
        COUNT_BIG(*)
FROM dbo.Votes AS v
WHERE v.VoteTypeId = @VoteTypeId;
GO 


/* 

In a perfect world, these'd get correct-ish estimates.

*/



/* 

And this is where the trouble begins. 

Plans start getting reused, whether it's a good or bad idea.

*/

DECLARE 
    @SQLString nvarchar(MAX) = N'';

/* @VoteTypeId is 4 here */
DECLARE 
    @VoteTypeId int = 4;

SET @SQLString = N'
SELECT 
    records = 
        COUNT_BIG(*)
FROM dbo.Votes AS v
WHERE v.VoteTypeId = @VoteTypeId;
';
EXEC sys.sp_executesql 
    @SQLString, 
  N'@VoteTypeId int', 
    @VoteTypeId;

/* @VoteTypeId changes to 2 here */
SET @VoteTypeId = 2;

SET @SQLString = N'
SELECT 
    records = 
        COUNT_BIG(*)
FROM dbo.Votes AS v
WHERE v.VoteTypeId = @VoteTypeId;
';
EXEC sys.sp_executesql 
    @SQLString, 
  N'@VoteTypeId int', 
    @VoteTypeId;
GO 

/* 

In reverse is okay, but...

*/


DBCC FREEPROCCACHE;
DECLARE 
    @SQLString nvarchar(MAX) = N'';

/* @VoteTypeId is 2 here */
DECLARE 
    @VoteTypeId int = 2;

SET @SQLString = N'
SELECT 
    records = 
        COUNT_BIG(*)
FROM dbo.Votes AS v
WHERE v.VoteTypeId = @VoteTypeId;
';

EXEC sys.sp_executesql 
    @SQLString, 
  N'@VoteTypeId int', 
    @VoteTypeId;

/* @VoteTypeId changes to 4 here */
SET @VoteTypeId = 4;

SET @SQLString = N'
SELECT 
    records = 
        COUNT_BIG(*)
FROM dbo.Votes AS v
WHERE v.VoteTypeId = @VoteTypeId;
';

EXEC sys.sp_executesql 
    @SQLString, 
  N'@VoteTypeId int', 
    @VoteTypeId;
GO 


/* 

Parallelism should probably only kick in when it's appropriate,
or some knucklehead will come along, see a bunch of CX* waits,
and set MAXDOP to 1 on you, which isn't what you want either. 

That's not a good time at all.

*/





























/* 
██╗    ██╗██╗  ██╗██╗   ██╗                                                                            
██║    ██║██║  ██║╚██╗ ██╔╝                                                                            
██║ █╗ ██║███████║ ╚████╔╝                                                                             
██║███╗██║██╔══██║  ╚██╔╝                                                                              
╚███╔███╔╝██║  ██║   ██║                                                                               
 ╚══╝╚══╝ ╚═╝  ╚═╝   ╚═╝                                                                               
                                                                                                       
██████╗  █████╗ ██████╗  █████╗ ███╗   ███╗███████╗████████╗███████╗██████╗ ██╗███████╗███████╗██████╗ 
██╔══██╗██╔══██╗██╔══██╗██╔══██╗████╗ ████║██╔════╝╚══██╔══╝██╔════╝██╔══██╗██║╚══███╔╝██╔════╝╚════██╗
██████╔╝███████║██████╔╝███████║██╔████╔██║█████╗     ██║   █████╗  ██████╔╝██║  ███╔╝ █████╗    ▄███╔╝
██╔═══╝ ██╔══██║██╔══██╗██╔══██║██║╚██╔╝██║██╔══╝     ██║   ██╔══╝  ██╔══██╗██║ ███╔╝  ██╔══╝    ▀▀══╝ 
██║     ██║  ██║██║  ██║██║  ██║██║ ╚═╝ ██║███████╗   ██║   ███████╗██║  ██║██║███████╗███████╗  ██╗   
╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝╚══════╝╚══════╝  ╚═╝   
*/




/* 

When you pass in concatenated values, 
the optimizer compiles a new plan each time

This might be okay *sometimes*, but not generally
what you want to happen. 
   
*/

DBCC FREEPROCCACHE;
GO 
DECLARE 
    @StartDate datetime = '20130101';

WHILE @StartDate < '20130601'
BEGIN
DECLARE 
    @NoParams4u nvarchar(MAX) = 
N'
SELECT
    TotalScore = 
        SUM(c.Score)
FROM dbo.Comments AS c
WHERE c.CreationDate BETWEEN CONVERT(datetime, ''' + RTRIM(@StartDate) + ''') 
                     AND     CONVERT(datetime, ''' + RTRIM(DATEADD(DAY, 11, @StartDate)) + ''')
AND 1 = (SELECT 1);
';

/* Check the messages tab, too */
EXEC sys.sp_executesql 
    @NoParams4u;
RAISERROR('%s', 0, 1, @NoParams4u);

SET @StartDate = DATEADD(DAY, 11, @StartDate);

END;
GO

/* firstresponderkit.org */
EXEC dbo.sp_BlitzCache 
    @HideSummary = 1,
    @DatabaseName = N'StackOverflow2013', 
    @SkipAnalysis = 1,
    @QueryFilter = 'statement';
GO 



DBCC FREEPROCCACHE;
GO 
DECLARE 
    @StartDate datetime = '20130101';

WHILE @StartDate < '20130601'
BEGIN
DECLARE 
    @NoParams4u nvarchar(MAX) = 
N'
SELECT 
    TotalScore = 
        SUM(c.Score)
FROM dbo.Comments AS c
WHERE c.CreationDate BETWEEN @StartDate 
                     AND     DATEADD(DAY, 11, @StartDate)
AND 1 = (SELECT 1);
';

EXEC sys.sp_executesql 
    @NoParams4u, 
  N'@StartDate datetime', 
    @StartDate;
/* Check the messages tab, too */
RAISERROR('%s', 0, 1, @NoParams4u);

SET @StartDate = DATEADD(DAY, 11, @StartDate);

END;
GO

/* firstresponderkit.org */
EXEC dbo.sp_BlitzCache 
    @HideSummary = 1,
    @DatabaseName = N'StackOverflow2013', 
    @SkipAnalysis = 1,
    @QueryFilter = 'statement';
GO 



























/* 
███████╗ ██████╗     ███████╗ █████╗ ██████╗            
██╔════╝██╔═══██╗    ██╔════╝██╔══██╗██╔══██╗           
███████╗██║   ██║    █████╗  ███████║██████╔╝           
╚════██║██║   ██║    ██╔══╝  ██╔══██║██╔══██╗           
███████║╚██████╔╝    ██║     ██║  ██║██║  ██║           
╚══════╝ ╚═════╝     ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝           
                                                        
███████╗ ██████╗      ██████╗  ██████╗  ██████╗ ██████╗ 
██╔════╝██╔═══██╗    ██╔════╝ ██╔═══██╗██╔═══██╗██╔══██╗
███████╗██║   ██║    ██║  ███╗██║   ██║██║   ██║██║  ██║
╚════██║██║   ██║    ██║   ██║██║   ██║██║   ██║██║  ██║
███████║╚██████╔╝    ╚██████╔╝╚██████╔╝╚██████╔╝██████╔╝
╚══════╝ ╚═════╝      ╚═════╝  ╚═════╝  ╚═════╝ ╚═════╝ 
(So What?)
*/


/* 

To recap what we know:
 * We can write dynamic SQL to produce different queries
 * We have to write it in a safe way to prevent teh hax
 * Parameters and variables are much different
 * Parameters encourage plan re-use
   * Which is great if you have a good plan for everyone
   * And not so great if your data has a lot of skew

*/


/* 

How to tell if it's parameter sniffing:
 * First, rule out resource contention
  * sp_PressureDetector: https://www.erikdarling.com/sp_pressuredetector/
 * Next, rule out blocking:
  * sp_WhoIsActive: http://whoisactive.com/


In a way, it's a lot easier to identify parameter sniffing while it's happening
 * The plan cache sucks for this; it's full of lies: 
  * https://www.youtube.com/playlist?list=PLt4QZ-7lfQic_jsjqZwd0tByF4nXl5eC_
 * Query Store is much better, you can use the built in views
  * Regressed Queries
  * Queries with High Variance



Let's look at how sp_WhoIsActive can help!

*/

EXEC dbo.sp_WhoIsActive 
    @get_full_inner_text = 1,  
    @get_outer_command = 1,    
    @get_plans = 1,               
    @get_avg_time = 1;       


/* 

Get full inner text: Query executing
Get outer command:   Was it called by a stored procedure or larger batch?
Get plans:           Return the query plan
Get avg time:        How long does this normally run for?


What we're looking for: 
 * Queries running for longer than average
 * Outer command is useful if the query is in a procedure
 * Inner text tells us which query is having problems
 * Query plan gives us compile and (sometimes) runtime values for parameters
  * Along with all the other goodies
  * Always hit F4/dig into properties of operators

To reproduce: Run the proc first with the compile-time value
              Run the proc second with the runtime value

*/









DBCC FREEPROCCACHE;
GO                              


CREATE OR ALTER PROCEDURE 
    dbo.TakeAChance
AS
BEGIN
SET 
    NOCOUNT, 
    XACT_ABORT ON;
    
    /* Generate a random number, pass it to dynamic SQL
       Remember that this makes it a parameter! */
    DECLARE 
        @ParentId int = (ABS(CHECKSUM(NEWID()))) % 100,
        @sql      nvarchar(MAX) = N'';
    
    /* Randomly set @ParentId to 0, which has a TON of rows 
       There are ~6 million or so, and every other Id has < 520 */
    IF @ParentId % 10 = 0
    BEGIN    
        SET @ParentId = 0;
    END;
    
    SET @sql += N'
        /* dbo.TakeAChance */
        SELECT TOP (10)
            u.DisplayName, 
            p.*
        FROM dbo.Posts AS p
        JOIN dbo.Users AS u
            ON p.OwnerUserId = u.Id
        WHERE p.ParentId = @iParentId
        ORDER BY 
            u.Reputation DESC;';

    EXEC sys.sp_executesql 
        @sql, 
      N'@iParentId int',
        @ParentId;

END;
GO



/* 
RML Utilities: https://www.microsoft.com/en-us/download/details.aspx?id=4511

ostress -SSQL2019 -d"StackOverflow2013" -Q"EXEC dbo.TakeAChance;" -U"ostress" -P"ostress" -q -n10 -r100 -o"C:\temp\crap"

*/

EXEC dbo.sp_WhoIsActive 
    @get_full_inner_text = 1,  
    @get_outer_command = 1,    
    @get_plans = 1,               
    @get_avg_time = 1;  






























/* 
███████╗██╗██╗  ██╗██╗███╗   ██╗ ██████╗     ██╗████████╗
██╔════╝██║╚██╗██╔╝██║████╗  ██║██╔════╝     ██║╚══██╔══╝
█████╗  ██║ ╚███╔╝ ██║██╔██╗ ██║██║  ███╗    ██║   ██║   
██╔══╝  ██║ ██╔██╗ ██║██║╚██╗██║██║   ██║    ██║   ██║   
██║     ██║██╔╝ ██╗██║██║ ╚████║╚██████╔╝    ██║   ██║   
╚═╝     ╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝ ╚═════╝     ╚═╝   ╚═╝   
*/



/* 

Let's put all the components together:
 * We have parameters that we can use to make decisions
 * We have dynamic SQL that we can use to build strings

Why not build different strings 
 based on what we know about the parameters?

First, we have to understand where skew lives:
 * Within equality predicates?
  * Outliers, or most common activity
 * Between ranges?
  * Dates, dollar amounts, scores

Are we doing anything stupid to mess up performance?
 * Local variables
 * Non-SARGable predicates
 * Table variables
 * Joining/Filtering on functions

What we need to repro:
 * Someplace safe to test, with representative data
 * The parameters from compile time and run time

*/





/* 

First, let's look at skewed data

*/
SELECT 
    v.VoteTypeId, 
    records = 
        FORMAT(COUNT_BIG(*), 'N0')
FROM dbo.Votes AS v
GROUP BY v.VoteTypeId
ORDER BY 
    COUNT_BIG(*) DESC;
GO 



/* 

Our proc only has one parameter that needs to find values

Our indexes: 
 * CREATE INDEX onesie ON dbo.Posts(OwnerUserId, Score, CreationDate);
 * CREATE INDEX twosie ON dbo.Votes(VoteTypeId, CreationDate);

*/
CREATE OR ALTER PROCEDURE 
    dbo.VotesAndScoresByType
(
    @VoteTypeId int
)
AS
BEGIN
SET 
    NOCOUNT, 
    XACT_ABORT ON;

    SELECT TOP (200)
        u.DisplayName,
        VoteType = 
            @VoteTypeId,
        TotalBounties = 
            SUM(ISNULL(v.BountyAmount, 0)),
        TotalScore = 
            SUM(p.Score),
        TotalPosts = 
            COUNT_BIG(*)
    FROM dbo.Votes AS v
    JOIN dbo.Posts AS p
      ON v.PostId = p.Id
    JOIN dbo.Users AS u
      ON p.OwnerUserId = u.Id
    WHERE v.VoteTypeId = @VoteTypeId 
    GROUP BY 
        u.DisplayName
    ORDER BY 
        TotalPosts DESC;

END;
GO 

/* 

Regression points, just for testing

* VoteTypeId 2 (big) using the plan for 9 (small)
* VoteTypeId 9 (small) using the plan for 2 (big)


{ This doesn't go into all the other possible VoteTypeId values,
  because all the values except 7, 12, and 4 get the same "big plan", 
  but with different values for memory grants }

*/

--Big plan, quite suitable
EXEC dbo.VotesAndScoresByType 
    @VoteTypeId = 2;
GO 

--Big plan, but not very suitable
EXEC dbo.VotesAndScoresByType 
    @VoteTypeId = 9;
GO 


--Recompile the proc
EXEC sys.sp_recompile 
    @objname = N'dbo.VotesAndScoresByType';
GO 


--Big plan, but not very suitable
EXEC dbo.VotesAndScoresByType 
    @VoteTypeId = 9;
GO 


--Big plan, quite suitable
EXEC dbo.VotesAndScoresByType 
    @VoteTypeId = 2;
GO 








/* 

Option 1: 
 * Trick the optimizer into building a different plan
 * Stick some useless logic in here
 * If you have forced parameterization turned on, you might have
   to pick numbers that fall into different integer data types, 
   e.g. tinyint, smallint, int, bigint

*/

DBCC FREEPROCCACHE;
GO 
CREATE OR ALTER PROCEDURE 
    dbo.VotesAndScoresByType
(
    @VoteTypeId int
)
AS
BEGIN
SET NOCOUNT, XACT_ABORT ON;

DECLARE 
    @sql nvarchar(MAX) = N'';

SET @sql += N'
    /* dbo.VotesAndScoresByType */
    SELECT TOP (200)
        u.DisplayName,
        VoteType = 
            @VoteTypeId,
        TotalBounties = 
            SUM(ISNULL(v.BountyAmount, 0)),
        TotalScore = 
            SUM(p.Score),
        TotalPosts = 
            COUNT_BIG(*)
    FROM dbo.Votes AS v
    JOIN dbo.Posts AS p
      ON v.PostId = p.Id
    JOIN dbo.Users AS u
      ON p.OwnerUserId = u.Id
    WHERE v.VoteTypeId = @VoteTypeId ';

/* For the "big" sets of data, 1 = (SELECT 1) */
IF @VoteTypeId IN (2, 1, 3, 5, 10, 6, 16)
BEGIN
    SET @sql += N'
    AND 1 = (SELECT 1) ';
END;

/* For the "small" sets of data, 2 = (SELECT 2) */
IF @VoteTypeId IN (15, 11, 8, 9, 7, 12, 4)
BEGIN
    SET @sql += N'
    AND 2 = (SELECT 2) ';
END;
 
SET @sql += N'    
    GROUP BY 
        u.DisplayName
    ORDER BY 
        TotalPosts DESC;';

RAISERROR('%s', 0, 1, @sql) WITH NOWAIT;
EXEC sys.sp_executesql 
    @sql,
  N'@VoteTypeId int',
    @VoteTypeId;

END;
GO 

--Small parallel plan, quite suitable
EXEC dbo.VotesAndScoresByType 
    @VoteTypeId = 9;
GO 

--Big plan, quite suitable
EXEC dbo.VotesAndScoresByType 
    @VoteTypeId = 2;
GO 






/* 

Another similar option:
 * Optimize for a specific value (NOT UNKNOWN, DAMMIT)
 * Works about the same as the ? = (SELECT ?)
 * Will get plan reuse for each optimize for
 * Probably not as safe as the other method with strings

*/



CREATE OR ALTER PROCEDURE 
    dbo.VotesAndScoresByType
(
    @VoteTypeId int
)
AS
BEGIN
SET 
    NOCOUNT, 
    XACT_ABORT ON;

DECLARE 
    @sql nvarchar(MAX) = N'';

SET @sql += N'
    /* dbo.VotesAndScoresByType */
    SELECT TOP (200)
        u.DisplayName,
        VoteType = 
            @VoteTypeId,
        TotalBounties = 
            SUM(ISNULL(v.BountyAmount, 0)),
        TotalScore = 
            SUM(p.Score),
        TotalPosts = 
            COUNT_BIG(*)
    FROM dbo.Votes AS v
    JOIN dbo.Posts AS p
      ON v.PostId = p.Id
    JOIN dbo.Users AS u
      ON p.OwnerUserId = u.Id
    WHERE v.VoteTypeId = @VoteTypeId   
    GROUP BY 
        u.DisplayName
    ORDER BY 
        TotalPosts DESC 
    OPTION(OPTIMIZE FOR(@VoteTypeId = [@@@]));';

IF @VoteTypeId IN (2, 1, 3, 5, 10, 6, 16)
BEGIN
    SET @sql = REPLACE(@sql, N'[@@@]', @VoteTypeId);
END;

IF @VoteTypeId IN (15, 11, 8, 9, 7, 12, 4)
BEGIN
    SET @sql = REPLACE(@sql, N'[@@@]', @VoteTypeId);   
END;

RAISERROR('%s', 0, 1, @sql) WITH NOWAIT;
EXEC sys.sp_executesql 
    @sql,
  N'@VoteTypeId int',
    @VoteTypeId;

END;
GO 


--Small parallel plan, quite suitable
EXEC dbo.VotesAndScoresByType 
    @VoteTypeId = 9;
GO 

--Big plan, quite suitable
EXEC dbo.VotesAndScoresByType 
    @VoteTypeId = 2;
GO 

/* 

Those are fine if:
 * You've got a manageable number of values
 * Their overall distribution will be stable
 * Equality predicates make this easier

Let's look at a different example with ranges

*/


CREATE OR ALTER PROCEDURE 
    dbo.VotesAndScoresByDate
(
    @StartDate datetime, 
    @EndDate datetime
)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;

    DECLARE 
        @sql nvarchar(MAX) = N'
    /* dbo.VotesAndScoresByDate */
    SELECT TOP (200)
        u.DisplayName,
        v.VoteTypeId,
        TotalBounties = 
            SUM(ISNULL(v.BountyAmount, 0)),
        TotalScore = 
            SUM(p.Score),
        TotalPosts = 
            COUNT_BIG(*)
    FROM dbo.Votes AS v
    JOIN dbo.Posts AS p
      ON v.PostId = p.Id
    JOIN dbo.Users AS u
      ON p.OwnerUserId = u.Id
    WHERE v.CreationDate BETWEEN @StartDate AND @EndDate
    AND   v.VoteTypeId IN (1, 3, 5, 10)
    GROUP BY 
        u.DisplayName,
        v.VoteTypeId
    ORDER BY 
        TotalPosts DESC;';

    IF 
    (
        DATEDIFF
        (
            MONTH, 
            @StartDate, 
            @EndDate
        ) >= 3
    )
    BEGIN
        SET @sql += N'
    OPTION(RECOMPILE);';
    END;
    ELSE
    BEGIN
        SET @sql += N';';
    END;
    
    /* Print the query text so we can make sure it works */
    RAISERROR('%s', 0, 1, @sql) WITH NOWAIT;
    
    EXEC sys.sp_executesql 
        @sql,
      N'@StartDate datetime,
        @EndDate datetime',
        @StartDate,
        @EndDate;

END;
GO 



DBCC FREEPROCCACHE;
GO 

EXEC dbo.VotesAndScoresByDate 
    @StartDate = '20130101',
    @EndDate   = '20130102'; 
GO

EXEC dbo.VotesAndScoresByDate 
    @StartDate = '20130101',
    @EndDate   = '20140101'; 
GO 






















/* 
██╗    ██╗██╗  ██╗███████╗██╗    ██╗
██║    ██║██║  ██║██╔════╝██║    ██║
██║ █╗ ██║███████║█████╗  ██║ █╗ ██║
██║███╗██║██╔══██║██╔══╝  ██║███╗██║
╚███╔███╔╝██║  ██║███████╗╚███╔███╔╝
 ╚══╝╚══╝ ╚═╝  ╚═╝╚══════╝ ╚══╝╚══╝ 
*/


/* 

What we learned:
 * What dynamic SQL is: A string you built into a query to execute
 * How to use it safely: Parameterization, sp_executesql
 * What a parameter is: Something you pass to a proc, function, or dynamic SQL. Not a local variable.
 * How they can cause performance problems: Plan re-use for highly skewed values.
 * What parameter sniffing looks like: Queries running much slower for no apparent reason.
 * How you can detect it: sp_WhoIsActive
 * What information you need to reproduce it: QTIP!
 * How to fix it with dynamic SQL: Isolate skewed values, detect incompatible ranges

*/



/* 
      ███████╗██╗███╗   ██╗      
      ██╔════╝██║████╗  ██║      
█████╗█████╗  ██║██╔██╗ ██║█████╗
╚════╝██╔══╝  ██║██║╚██╗██║╚════╝
      ██║     ██║██║ ╚████║      
      ╚═╝     ╚═╝╚═╝  ╚═══╝                         
*/

/* 

    * W: www.erikdarlingdata.com
    * E: erik@erikdarlingdata.com
    * T: @erikdarlingdata
    
    Demo database:
    * http://bit.ly/Stack2013

    Demo scripts: 
    * http://bit.ly/DefeatSniffing

*/















/* 

/* 

This does a somewhat naive search of the plan cache,
looking for compiled plans and the parameter values in them

*/

CREATE OR ALTER FUNCTION 
    dbo.query_plan_parameters
(
    @procid int
)
RETURNS table 
AS
RETURN

WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS x)
SELECT 
    params.parameter_name,
    params.parameter_datatype,
    compile_time_value = 
        CASE 
            WHEN params.parameter_datatype NOT IN 
                 ( 
                   N'char', N'nchar', N'varchar', N'nvarchar',
                   N'xml', N'binary', N'varbinary', N'image',
                   N'text', N'ntext', N'uniqueidentifier'
                 ) 
            THEN REPLACE
                 (
                     REPLACE
                     (
                         REPLACE
                         (
                             params.parameter_compiled_value, 
                             N'(', 
                             N''
                         ), 
                             N')', 
                             N''
                         
                     ), 
                             N'''', 
                             N''
                 )
            ELSE params.parameter_compiled_value
        END
FROM 
(
    SELECT 
        parameter_name = q.n.value('@Column', 'nvarchar(256)'),
        parameter_datatype = q.n.value('@ParameterDataType', 'nvarchar(256)'),
        parameter_compiled_value = q.n.value('@ParameterCompiledValue', 'nvarchar(256)')
    FROM 
    (
        SELECT 
            deqps.query_plan
        FROM sys.dm_exec_procedure_stats AS deps
        CROSS APPLY sys.dm_exec_query_plan(deps.plan_handle) AS deqps
        CROSS APPLY 
        ( 
            SELECT 
                pa.value
            FROM sys.dm_exec_plan_attributes(deps.plan_handle) AS pa
            WHERE pa.attribute = 'dbid' 
        ) AS ca
        WHERE deps.object_id = @procid
        AND   ca.value = DB_ID()
    ) AS x
    CROSS APPLY x.query_plan.nodes('//x:StmtSimple/x:QueryPlan/x:ParameterList/x:ColumnReference') AS q(n)
) AS params;
GO 


/* 

Turn off query plans

No really, turn them off

They just get in the way after this

*/


/* 

A quick demonstration of how it works

*/


CREATE OR ALTER PROCEDURE 
    dbo.query_plan_parameters_test
(
    @param1 int
)
AS
BEGIN
SET 
    NOCOUNT, 
    XACT_ABORT ON;

    SELECT * FROM dbo.Posts AS p WHERE p.OwnerUserId = @param1;
    SELECT * FROM dbo.query_plan_parameters(@@PROCID) AS qpp OPTION(RECOMPILE);

END; 
GO 

EXEC dbo.query_plan_parameters_test 
    @param1 = 8;
GO 



/* 

A new parameter sniffing example!

This time we're using a date range rather than
a simple equality test, because it's a little harder
to figure out "safe" values for each end of the range.

*/



CREATE OR ALTER PROCEDURE 
    dbo.VotesAndScoresByDate
(
    @StartDate datetime, 
    @EndDate datetime
)
AS
BEGIN
SET 
    NOCOUNT, 
    XACT_ABORT ON;

    SET STATISTICS XML ON;
    
    SELECT TOP (200)
        u.DisplayName,
        v.VoteTypeId,
        TotalBounties = SUM(ISNULL(v.BountyAmount, 0)),
        TotalScore = SUM(p.Score),
        TotalPosts = COUNT_BIG(*)
    FROM dbo.Votes AS v
    JOIN dbo.Posts AS p
      ON v.PostId = p.Id
    JOIN dbo.Users AS u
      ON p.OwnerUserId = u.Id
    WHERE v.CreationDate BETWEEN @StartDate AND @EndDate
    AND   v.VoteTypeId IN (1, 3, 5, 10)
    GROUP BY 
        u.DisplayName,
        v.VoteTypeId
    ORDER BY 
        TotalPosts DESC;
    
    SET STATISTICS XML OFF;

END;
GO 



/* 

A one day range

*/
EXEC dbo.VotesAndScoresByDate 
    @StartDate = '20130101',
    @EndDate   = '20130102'; 

/* 

A one year range

*/
EXEC dbo.VotesAndScoresByDate 
    @StartDate = '20130101',
    @EndDate   = '20140101'; 
GO 




/* 

Let's fight sniffing based on some other details!

*/


CREATE OR ALTER PROCEDURE 
    dbo.VotesAndScoresByDate
(
    @StartDate datetime, 
    @EndDate datetime
)
AS
BEGIN
SET NOCOUNT, XACT_ABORT ON;

    /* Helper variables to hold previously compiled values */
    DECLARE 
        @compile_start_date datetime,
        @compile_end_date   datetime;

    /* Only go to the cache once */
    SELECT 
        qpp.parameter_name,
        qpp.parameter_datatype,
        qpp.compile_time_value
    INTO #parameter_info
    FROM dbo.query_plan_parameters(@@PROCID) AS qpp 
    OPTION(RECOMPILE);

    /* Set the previously compiled start date */
    SELECT 
        @compile_start_date 
            = qpp.compile_time_value
    FROM #parameter_info AS qpp 
    WHERE qpp.parameter_name = '@StartDate'
    OPTION(RECOMPILE);

    /* Set the previously compiled end date */
    SELECT 
        @compile_end_date 
            = qpp.compile_time_value
    FROM #parameter_info AS qpp 
    WHERE qpp.parameter_name = '@EndDate'
    OPTION(RECOMPILE);

    /* Insert current params to a table variable
       Otherwise, they don't end up in the query plan with values
       Why? I don't know  */
    DECLARE 
        @oh_no table
    (
        StartDate datetime, 
        EndDate datetime
    );
    INSERT  
        @oh_no 
    (
        StartDate, 
        EndDate 
    )
    VALUES 
    ( 
        @StartDate, 
        @EndDate  
    );


    DECLARE 
        @sql nvarchar(MAX) = N'
    SELECT TOP (200)
        u.DisplayName,
        v.VoteTypeId,
        TotalBounties = SUM(ISNULL(v.BountyAmount, 0)),
        TotalScore = SUM(p.Score),
        TotalPosts = COUNT_BIG(*)
    /* dbo.VotesAndScoresByDate */
    FROM dbo.Votes AS v
    JOIN dbo.Posts AS p
      ON v.PostId = p.Id
    JOIN dbo.Users AS u
      ON p.OwnerUserId = u.Id
    WHERE v.CreationDate BETWEEN @StartDate AND @EndDate
    AND   v.VoteTypeId IN (1, 3, 5, 10)
    GROUP BY 
        u.DisplayName,
        v.VoteTypeId
    ORDER BY 
        TotalPosts DESC';

    /* Sort of a general approach: If the current search is > 3 months, and
       the compiled search is < 2 months or vice versa, we want to recompile 
       we could totally do something similar to before, but sometimes 
       you really do have to recompile. I acknowledge that. */
    IF  ( DATEDIFF(MONTH, @StartDate, @EndDate) > 3
          AND DATEDIFF(MONTH, @compile_start_date, @compile_end_date) < 2 )
            OR 
        ( DATEDIFF(MONTH, @StartDate, @EndDate) < 2
              AND DATEDIFF(MONTH, @compile_start_date, @compile_end_date) > 3 )
    BEGIN
        SET @sql += N'
    OPTION(RECOMPILE);';
    END;
    ELSE
    BEGIN
        /* So Itzik doesn't yell at me */
        SET @sql += N';';
    END;
    
    /* Print the query text so we can make sure it works */
    RAISERROR('%s', 0, 1, @sql) WITH NOWAIT;
    
    /* To validate, we're going to get the query plan for
       just the dynamic SQL back with the results */
    SET STATISTICS XML ON;
    
    EXEC sys.sp_executesql 
        @sql,
      N'@StartDate datetime,
        @EndDate datetime',
        @StartDate,
        @EndDate;
    
    SET STATISTICS XML OFF;

END;
GO 


/* Small first? */
DBCC FREEPROCCACHE;

EXEC dbo.VotesAndScoresByDate 
    @StartDate = '20130101',
    @EndDate   = '20130102'; 
GO 2

EXEC dbo.VotesAndScoresByDate 
    @StartDate = '20130101',
    @EndDate   = '20140101'; 
GO 

/* Big First? */
DBCC FREEPROCCACHE;

EXEC dbo.VotesAndScoresByDate 
    @StartDate = '20130101',
    @EndDate   = '20140101'; 
GO 2

EXEC dbo.VotesAndScoresByDate 
    @StartDate = '20130101',
    @EndDate   = '20130102'; 
GO 


*/