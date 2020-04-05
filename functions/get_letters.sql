CREATE FUNCTION dbo.get_letters(@string NVARCHAR(4000))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN 

WITH x
  AS ( SELECT TOP (LEN(@string))
                  ROW_NUMBER() OVER (ORDER BY n.n) AS x
       FROM dbo.Numbers AS n )
    SELECT CONVERT(NVARCHAR(4000),
           ( SELECT SUBSTRING(@string COLLATE Latin1_General_100_BIN2, x.x, 1)
             FROM x AS x
             WHERE SUBSTRING(@string COLLATE Latin1_General_100_BIN2, x.x, 1) LIKE '[a-zA-Z]'
             ORDER BY x.x
             FOR XML PATH('') )
           ) AS letters_only;
GO 
