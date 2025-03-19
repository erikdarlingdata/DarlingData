/*
MIT License

Copyright (c) 2025 Darling Data, LLC

https://www.erikdarling.com/

For support, head over to GitHub:
https://code.erikdarling.com

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

USE master;
GO

CREATE DATABASE
    StackOverflowCS
CONTAINMENT = NONE
ON PRIMARY
(
    NAME = N'StackOverflow_1',
    FILENAME = N'D:\SQL2017\StackCS\StackOverflowCS_1.mdf',
    SIZE = 27252736KB,
    MAXSIZE = UNLIMITED,
    FILEGROWTH = 524288KB
),
(
    NAME = N'StackOverflow_2',
    FILENAME = N'D:\SQL2017\StackCS\StackOverflowCS_2.ndf',
    SIZE = 27251712KB,
    MAXSIZE = UNLIMITED,
    FILEGROWTH = 524288KB
),
(
    NAME = N'StackOverflow_3',
    FILENAME = N'D:\SQL2017\StackCS\StackOverflowCS_3.ndf',
    SIZE = 27252736KB,
    MAXSIZE = UNLIMITED,
    FILEGROWTH = 524288KB
),
(
    NAME = N'StackOverflow_4',
    FILENAME = N'D:\SQL2017\StackCS\StackOverflowCS_4.ndf',
    SIZE = 27382784KB,
    MAXSIZE = UNLIMITED,
    FILEGROWTH = 524288KB
)
LOG ON
(
    NAME = N'StackOverflow_log',
    FILENAME = N'D:\SQL2017\StackCS\StackOverflowCS_log.ldf',
    SIZE = 2877376KB,
    MAXSIZE = 2048GB,
    FILEGROWTH = 524288KB
);
GO

ALTER DATABASE StackOverflowCS
MODIFY FILEGROUP [PRIMARY] AUTOGROW_ALL_FILES;
GO

IF (1 = FULLTEXTSERVICEPROPERTY('IsFullTextInstalled'))
BEGIN
    EXECUTE StackOverflowCS.sys.sp_fulltext_database @action = 'enable';
END;
GO
ALTER DATABASE StackOverflowCS SET ANSI_NULL_DEFAULT OFF;
GO
ALTER DATABASE StackOverflowCS SET ANSI_NULLS OFF;
GO
ALTER DATABASE StackOverflowCS SET ANSI_PADDING OFF;
GO
ALTER DATABASE StackOverflowCS SET ANSI_WARNINGS OFF;
GO
ALTER DATABASE StackOverflowCS SET ARITHABORT OFF;
GO
ALTER DATABASE StackOverflowCS SET AUTO_CLOSE OFF;
GO
ALTER DATABASE StackOverflowCS SET AUTO_SHRINK OFF;
GO
ALTER DATABASE StackOverflowCS SET AUTO_UPDATE_STATISTICS ON;
GO
ALTER DATABASE StackOverflowCS SET CURSOR_CLOSE_ON_COMMIT OFF;
GO
ALTER DATABASE StackOverflowCS SET CURSOR_DEFAULT GLOBAL;
GO
ALTER DATABASE StackOverflowCS SET CONCAT_NULL_YIELDS_NULL OFF;
GO
ALTER DATABASE StackOverflowCS SET NUMERIC_ROUNDABORT OFF;
GO
ALTER DATABASE StackOverflowCS SET QUOTED_IDENTIFIER OFF;
GO
ALTER DATABASE StackOverflowCS SET RECURSIVE_TRIGGERS OFF;
GO
ALTER DATABASE StackOverflowCS SET DISABLE_BROKER;
GO
ALTER DATABASE StackOverflowCS SET AUTO_UPDATE_STATISTICS_ASYNC OFF;
GO
ALTER DATABASE StackOverflowCS SET DATE_CORRELATION_OPTIMIZATION OFF;
GO
ALTER DATABASE StackOverflowCS SET TRUSTWORTHY OFF;
GO
ALTER DATABASE StackOverflowCS SET ALLOW_SNAPSHOT_ISOLATION OFF;
GO
ALTER DATABASE StackOverflowCS SET PARAMETERIZATION SIMPLE;
GO
ALTER DATABASE StackOverflowCS SET READ_COMMITTED_SNAPSHOT OFF;
GO
ALTER DATABASE StackOverflowCS SET HONOR_BROKER_PRIORITY OFF;
GO
ALTER DATABASE StackOverflowCS SET RECOVERY SIMPLE;
GO
ALTER DATABASE StackOverflowCS SET MULTI_USER;
GO
ALTER DATABASE StackOverflowCS SET PAGE_VERIFY CHECKSUM;
GO
ALTER DATABASE StackOverflowCS SET DB_CHAINING OFF;
GO
ALTER DATABASE StackOverflowCS
SET FILESTREAM
    (
        NON_TRANSACTED_ACCESS = OFF
    );
GO
ALTER DATABASE StackOverflowCS SET TARGET_RECOVERY_TIME = 60 SECONDS;
GO
ALTER DATABASE StackOverflowCS SET DELAYED_DURABILITY = DISABLED;
GO
ALTER DATABASE StackOverflowCS SET QUERY_STORE = OFF;
GO
ALTER DATABASE StackOverflowCS SET READ_WRITE;
GO

USE StackOverflowCS;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS
(
    SELECT
        1/0
    FROM sys.partition_functions AS pf
    WHERE pf.name = N'pfunc'
    AND   pf.type = N'R'
)
BEGIN

    CREATE PARTITION FUNCTION pfunc (datetime)
    AS RANGE RIGHT FOR VALUES
    (
        N'2007-01-01T00:00:00.000',
        N'2008-01-01T00:00:00.000',
        N'2009-01-01T00:00:00.000',
        N'2010-01-01T00:00:00.000',
        N'2011-01-01T00:00:00.000',
        N'2012-01-01T00:00:00.000',
        N'2013-01-01T00:00:00.000',
        N'2014-01-01T00:00:00.000',
        N'2015-01-01T00:00:00.000',
        N'2016-01-01T00:00:00.000',
        N'2017-01-01T00:00:00.000',
        N'2018-01-01T00:00:00.000',
        N'2019-01-01T00:00:00.000',
        N'2020-01-01T00:00:00.000',
        N'2021-01-01T00:00:00.000',
        N'2022-01-01T00:00:00.000',
        N'2023-01-01T00:00:00.000',
        N'2024-01-01T00:00:00.000',
        N'2025-01-01T00:00:00.000',
        N'2026-01-01T00:00:00.000',
        N'2027-01-01T00:00:00.000'
    );
END;

IF NOT EXISTS
(
    SELECT
        1/0
    FROM sys.partition_schemes AS ps
    WHERE ps.name = N'pscheme'
    AND   ps.type = N'PS'
)
BEGIN
    CREATE PARTITION SCHEME pscheme
    AS PARTITION pfunc
    ALL TO ([PRIMARY]);
END;

IF NOT EXISTS
(
    SELECT
        1/0
    FROM sys.objects
    WHERE object_id = OBJECT_ID(N'[dbo].[Badges]')
    AND   type IN ( N'U' )
)
BEGIN
    CREATE TABLE
        dbo.Badges
    (
        Id bigint NULL,
        Name nvarchar(40) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
        UserId bigint NULL,
        Date datetime NOT NULL
    ) ON pscheme (Date);
END;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
IF NOT EXISTS
(
    SELECT
        1/0
    FROM sys.objects
    WHERE object_id = OBJECT_ID(N'[dbo].[Comments]')
    AND   type IN ( N'U' )
)
BEGIN
    CREATE TABLE
        dbo.Comments
    (
        Id bigint NULL,
        CreationDate datetime NOT NULL,
        PostId bigint NULL,
        Score integer NULL,
        UserId bigint NULL
    ) ON pscheme (CreationDate);
END;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
IF NOT EXISTS
(
    SELECT
        1/0
    FROM sys.objects
    WHERE object_id = OBJECT_ID(N'[dbo].[Posts]')
    AND   type IN ( N'U' )
)
BEGIN
    CREATE TABLE dbo.Posts
    (
        Id bigint NULL,
        AcceptedAnswerId bigint NULL,
        AnswerCount integer NULL,
        ClosedDate datetime NULL,
        CommentCount integer NULL,
        CommunityOwnedDate datetime NULL,
        CreationDate datetime NOT NULL,
        FavoriteCount integer NULL,
        LastActivityDate datetime NOT NULL,
        LastEditDate datetime NULL,
        LastEditorDisplayName nvarchar(40) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
        LastEditorUserId bigint NULL,
        OwnerUserId bigint NULL,
        ParentId bigint NULL,
        PostTypeId integer NOT NULL,
        Score integer NOT NULL,
        Tags nvarchar(150) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
        ViewCount integer NOT NULL
    ) ON pscheme (CreationDate);
END;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
IF NOT EXISTS
(
    SELECT
        1/0
    FROM sys.objects
    WHERE object_id = OBJECT_ID(N'[dbo].[PostTypes]')
    AND   type IN ( N'U' )
)
BEGIN
    CREATE TABLE
        dbo.PostTypes
    (
        Id integer IDENTITY(1, 1) NOT NULL,
        Type nvarchar(50) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
        CONSTRAINT PK_PostTypes__Id
            PRIMARY KEY CLUSTERED (Id ASC)
            WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON)
            ON [PRIMARY]
    ) ON [PRIMARY];
END;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
IF NOT EXISTS
(
    SELECT
        1/0
    FROM sys.objects
    WHERE object_id = OBJECT_ID(N'[dbo].[Users]')
    AND   type IN ( N'U' )
)
BEGIN
    CREATE TABLE
        dbo.Users
    (
        Id bigint NULL,
        Age integer NULL,
        CreationDate datetime NOT NULL,
        DisplayName nvarchar(40) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
        DownVotes integer NOT NULL,
        EmailHash nvarchar(40) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
        LastAccessDate datetime NOT NULL,
        Location nvarchar(100) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
        Reputation integer NOT NULL,
        UpVotes integer NOT NULL,
        Views integer NOT NULL,
        WebsiteUrl nvarchar(200) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
        AccountId bigint NULL
    ) ON pscheme (CreationDate);
END;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
IF NOT EXISTS
(
    SELECT
        1/0
    FROM sys.objects
    WHERE object_id = OBJECT_ID(N'[dbo].[Votes]')
    AND   type IN ( N'U' )
)
BEGIN
    CREATE TABLE
        dbo.Votes
    (
        Id bigint NULL,
        PostId bigint NULL,
        UserId bigint NULL,
        BountyAmount integer NULL,
        VoteTypeId integer NOT NULL,
        CreationDate datetime NOT NULL
    ) ON pscheme (CreationDate);
END;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
IF NOT EXISTS
(
    SELECT
        1/0
    FROM sys.objects
    WHERE object_id = OBJECT_ID(N'[dbo].[VoteTypes]')
    AND   type IN ( N'U' )
)
BEGIN
    CREATE TABLE
        dbo.VoteTypes
    (
        Id int IDENTITY(1, 1) NOT NULL,
        Name varchar(50) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
        CONSTRAINT PK_VoteType__Id
            PRIMARY KEY CLUSTERED (Id ASC)
            WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON)
            ON [PRIMARY]
    ) ON [PRIMARY];
END;
GO

IF NOT EXISTS
(
    SELECT
        1/0
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'[dbo].[Badges]')
    AND   name = N'ccsi_Badges'
)
    CREATE CLUSTERED COLUMNSTORE INDEX ccsi_Badges
    ON dbo.Badges
    WITH (DROP_EXISTING = OFF, COMPRESSION_DELAY = 0)
    ON [pscheme]([Date]);
GO

IF NOT EXISTS
(
    SELECT
        1/0
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'[dbo].[Comments]')
    AND   name = N'ccsi_Comments'
)
    CREATE CLUSTERED COLUMNSTORE INDEX ccsi_Comments
    ON dbo.Comments
    WITH (DROP_EXISTING = OFF, COMPRESSION_DELAY = 0)
    ON [pscheme]([CreationDate]);
GO

IF NOT EXISTS
(
    SELECT
        1/0
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'[dbo].[Posts]')
    AND   name = N'ccsi_Posts'
)
    CREATE CLUSTERED COLUMNSTORE INDEX ccsi_Posts
    ON dbo.Posts
    WITH (DROP_EXISTING = OFF, COMPRESSION_DELAY = 0)
    ON [pscheme]([CreationDate]);
GO

IF NOT EXISTS
(
    SELECT
        1/0
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'[dbo].[Users]')
    AND   name = N'ccsi_Users'
)
    CREATE CLUSTERED COLUMNSTORE INDEX ccsi_Users
    ON dbo.Users
    WITH (DROP_EXISTING = OFF, COMPRESSION_DELAY = 0)
    ON [pscheme]([CreationDate]);
GO

IF NOT EXISTS
(
    SELECT
        1/0
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'[dbo].[Votes]')
    AND   name = N'ccsi_Votes'
)
    CREATE CLUSTERED COLUMNSTORE INDEX ccsi_Votes
    ON dbo.Votes
    WITH (DROP_EXISTING = OFF, COMPRESSION_DELAY = 0)
    ON [pscheme]([CreationDate]);
GO
